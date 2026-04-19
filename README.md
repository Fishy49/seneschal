<p align="center">
  <img src="app/assets/images/logo.png" width="80" alt="Seneschal" />
</p>

<h1 align="center">Seneschal</h1>

<p align="center">An AI pipeline orchestrator for software projects. Define workflows that use Claude to plan, implement, and validate features, then watch them run.</p>

<p align="center">
  
https://github.com/user-attachments/assets/51d96dcf-b06a-48eb-9092-28e8e4cc03d8

</p>

## Table of contents

- [What it does](#what-it-does)
- [Installation](#installation)
- [How to use Seneschal](#how-to-use-seneschal)
- [Concepts](#concepts)
  - [Step types](#step-types)
  - [Failure recovery](#failure-recovery)
- [Stack](#stack)

## What it does

Seneschal connects your Git repositories to multi-step AI workflows. A typical pipeline might:

1. Create a feature branch and draft PR
2. Explore the codebase and write an implementation plan
3. Implement the feature (tests first, then code)
4. Monitor CI checks and automatically retry on failure

Each step can be a **skill** (a Claude CLI prompt), a **shell script**, a **command**, a **CI check** monitor, or a **context fetch**. Steps pass context to each other through captured outputs and template variables. Failed CI checks can inject fix-up steps into the running pipeline and re-check automatically.

Streaming output from Claude skills is captured in real time and stored for historical review.

## Installation

For development setup, production setup on a Raspberry Pi (or any Debian/Ubuntu server), and system requirements, see **[SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md)**.

## How to use Seneschal

This section walks through the full lifecycle: from first-run setup to running a workflow against a task. Most work flows in this order — **integrations → project → skills → workflow → task → run** — but you can revisit earlier steps any time to tweak things.

### Usage table of contents

- [1. First run: admin account and integrations](#1-first-run-admin-account-and-integrations)
- [2. Creating projects](#2-creating-projects)
  - [Cloning the repository](#cloning-the-repository)
  - [Code maps](#code-maps)
- [3. Creating skills](#3-creating-skills)
  - [Shared vs. project-scoped skills](#shared-vs-project-scoped-skills)
  - [Template variables in prompts](#template-variables-in-prompts)
  - [Produces and consumes](#produces-and-consumes)
  - [Context projects](#context-projects)
  - [Per-step Claude configuration](#per-step-claude-configuration)
- [4. Creating workflows](#4-creating-workflows)
  - [Adding and ordering steps](#adding-and-ordering-steps)
  - [Step templates](#step-templates)
  - [Failure recovery configuration](#failure-recovery-configuration)
- [5. Creating tasks](#5-creating-tasks)
  - [The task body and "Format with Claude"](#the-task-body-and-format-with-claude)
  - [Context file selection](#context-file-selection)
  - [Triggers: manual, cron, and GitHub branch watch](#triggers-manual-cron-and-github-branch-watch)
- [6. Running](#6-running)
  - [Watching a run](#watching-a-run)
  - [Stopping, resuming, and retrying](#stopping-resuming-and-retrying)
  - [Follow-ups](#follow-ups)
- [7. User management and data export](#7-user-management-and-data-export)

### 1. First run: admin account and integrations

On a fresh install, the first visit to Seneschal redirects you to `/setup/admin`. You'll create the initial admin account with an email and password — this user has full access to every feature.

After logging in, the dashboard guides you to the **Setup** page (`/setup`) where Seneschal verifies the two external CLIs it shells out to:

- **Claude CLI** — runs `claude --version` to confirm the binary is on the path and prints the version.
- **GitHub CLI** — runs `gh auth status` to confirm `gh` is installed and authenticated.

If either check fails you'll see a red "Not verified" badge and an error message. Install or authenticate whatever's missing, then click the re-check button. The same page has a field for **default Claude allowed tools** (for example `Bash(git *), Read, Edit, Glob, Grep`) that applies to every skill/prompt step unless overridden per-step.

Don't skip this — workflows won't run correctly without both integrations passing.

### 2. Creating projects

A **Project** is a Git repository that Seneschal clones locally so Claude can work in it. From the sidebar, go to **Projects → New** and fill in:

- **Name** — unique identifier shown throughout the UI.
- **Repo URL** — SSH or HTTPS URL that `git clone` can reach. Authentication uses whatever credentials (`gh auth`, SSH keys) are configured on the host.
- **Local path** — where the working copy lives on disk. Click **Default** to auto-fill `<rails_root>/repos/<project_name>`.
- **Description** — optional notes.

After saving, the project exists but the repo is not yet on disk. The repo status indicator shows `not_cloned`.

#### Cloning the repository

Click **Clone Repository** on the project show page. This enqueues a background job (`CloneRepoJob`) that:

1. Runs `git clone <repo_url> <local_path>` if nothing exists yet.
2. Runs `git pull --ff-only` if the directory already has a `.git` folder (handy for re-syncing).
3. Cleans up empty directories so `git clone` doesn't error out.

Progress is streamed back to the page via Turbo — the status badge moves from `cloning` → `ready` (or `error`, with stderr shown so you can fix auth issues and retry). Workflows can only execute against a project with `ready` status.

#### Code maps

A **code map** is an AI-generated overview of your repo that powers smarter context suggestions. From the project show page click **Generate Code Map** to enqueue `GenerateCodeMapJob`, which:

1. Walks the file tree (respecting `.gitignore`).
2. Asks Claude Haiku to group files into 5–15 logical modules (e.g. "Authentication", "API Controllers") with short summaries per file.
3. Stores the result as a module list, a per-file index, and a full-text search index.

Code maps are tagged with the commit SHA they were built against and go stale after 24 hours — regenerate when your repo has changed meaningfully. Once a code map is ready, the task form's **Suggest with Claude** button can use it to recommend relevant context files (see [Context file selection](#context-file-selection)).

### 3. Creating skills

A **Skill** is a reusable Claude CLI prompt template. Think of skills as the building blocks your workflows plug into. Four skills ship seeded by `db:seed`: `ingest_feature`, `plan_feature`, `implement_feature`, and `fix_failing_tests` — together they form a feature-development pipeline.

From **Skills → New**, the form has four fields:

- **Name** — short identifier (snake_case works well).
- **Project** — leave blank for a shared skill, or pick one to scope it.
- **Description** — what this skill does, for future you.
- **Body** — the prompt, written in Markdown, with `${variable}` interpolation.

#### Shared vs. project-scoped skills

- **Shared** (`project_id` blank) — usable by any project's workflows. Ideal for generic skills like "plan a feature" or "fix failing tests" that aren't repo-specific.
- **Project-scoped** (`project_id` set) — only appears in skill pickers for workflows in that project. Useful for skills that reference specific conventions, internal tools, or file layouts.

When editing a workflow step of type `skill`, the skill picker shows everything returned by `Skill.for_project(project)` — that's shared skills plus the project's own skills.

#### Template variables in prompts

Anywhere in a skill body you can write `${variable_name}` and Seneschal substitutes the value at runtime via `TemplateRenderer`. Three kinds of variables are available:

- **Global variables** (always present): `task_title`, `task_body`, `task_kind`, `trigger_reason`, `repo_owner`, `repo_name`, `context_files`.
- **Produced variables** from earlier steps in the same run (see below).
- **Recovery variables** during failure handling: `previous_failure`, `previous_failure_step`, `recovery_round`.

Example body:

```markdown
You are implementing: ${task_title}

Task description:
${task_body}

Follow this plan:
${implementation_plan}

PR to push to: #${pr_number}
```

#### Produces and consumes

Steps can pass data to later steps. This is wired up on the **step** form, not the skill itself, but it's worth introducing here because most skill bodies are written to match.

- **Produces** — comma-separated list of output variable names this step should emit. For skill/prompt steps, Seneschal appends an instruction to the prompt telling Claude to emit a fenced `` ```output `` block like:

  ```
  ```output
  pr_number: 42
  branch: feature/add-thing
  implementation_plan: |
    Step one...
    Step two...
  ```
  ```

  `PipelineExtractor` parses this at the end of the step and stores each key in the run's context. Multiline values use `|` with 2-space indentation.

- **Consumes** — checkboxes picking from the list of variables available at this step's position. Setting consumes explicitly scopes the step to just those variables plus the globals; leaving it empty means the step receives everything produced so far.

For script and command steps, produced variables are read from lines like `::set-output name=pr_number::42`.

#### Context projects

Skill and prompt steps can attach **other Seneschal projects** as reference directories. This is useful when one repo needs to read docs or source from a companion repo (for example, a frontend project referencing API schemas in a backend project).

On the step form, the **Context Projects** multi-select shows every other project. Hold Cmd/Ctrl to pick several. At run time:

- Each selected project's `local_path` is passed to Claude via `--add-dir`, giving Claude read access.
- The prompt gets an appended section listing the directories:
  ```
  ## Available Project Directories
  - other_project_name: /path/to/other_project
  ```
- Projects that aren't cloned or aren't on disk are silently skipped (the step still runs).

Context projects aren't saved into step templates, since project IDs aren't portable across installs.

#### Per-step Claude configuration

For skill and prompt steps the form also exposes:

- **Model** — Opus 4.7, Sonnet 4.6, Haiku 4.5, or Default.
- **Effort** — low, medium, high, xhigh, max (maps to Claude CLI's `--effort`).
- **Max Turns** — cap on agent turns.
- **Allowed Tools** — comma-separated list like `Bash(git *), Read, Edit, Glob, Grep`. Leave blank to inherit the global default from the Setup page.

### 4. Creating workflows

A **Workflow** is an ordered sequence of steps that runs against a task. From a project's page choose **New Workflow**, give it a name and optional description, and pick a trigger type (usually `manual` — per-task triggers on the task itself give you more control).

#### Adding and ordering steps

From the workflow page, click **Add Step**. Each step has:

- **Name** — shown in run timelines.
- **Position** — execution order. Auto-assigns to `max + 1` for new steps; you can also drag to reorder.
- **Type** — one of `skill`, `prompt`, `script`, `command`, `ci_check`, `context_fetch` (see [Step types](#step-types) for details).
- **Body** (or **Skill**) — the work to do.
- **Produces** / **Consumes** — see above.
- **Additional Context** — freeform text injected into skill prompts (appended) or exposed to scripts as `$INPUT_CONTEXT`. Supports `${variable}` interpolation.
- **Max Retries** / **Timeout (seconds)** — per-step execution guards.
- **On Fail** — optional recovery action (next subsection).

Steps execute sequentially by position. When a step passes, its produced variables merge into the run's context; if the step declared `produces` but Claude didn't emit those values, Seneschal marks the step failed.

#### Step templates

Once you've configured a step you're happy with, check **Save as Template** at the bottom of the form and give it a name. Templates are global across projects and are listed under **Templates** in the sidebar.

New steps can start from a template via the **Choose Template** button at the top of the step form — it copies over the type, body, config, skill, retries, timeout, and input context. (Context projects are intentionally excluded, since project IDs don't match across installs.)

#### Failure recovery configuration

Any step can define an **On Fail** action that fires when the step fails, with up to `max_rounds` (default 3) attempts:

- **Re-Open Previous Step** — resumes the previous skill/prompt step's Claude session with the failure output and optional extra instructions. Good for "the test I wrote failed — fix your own work." Uses the stored `claude_session_id` so Claude has full memory of the original attempt.
- **Run Skill** — injects an ad-hoc step using a chosen recovery skill. The failure output and step name are prepended to the prompt automatically, so you don't need to reference `${previous_failure}` manually.
- **Run Script** / **Run Command** — injects an ad-hoc shell step. Has `$PREVIOUS_FAILURE` and `$PREVIOUS_FAILURE_STEP` env vars available.

After each recovery round, the original step is re-executed. The loop exits when it passes or when `max_rounds` is exhausted.

CI check steps can also download failure artifacts (test screenshots, JUnit XML, etc.) to `.seneschal/ci-artifacts/<run_id>/`, which any recovery skill can `Read` to diagnose what broke.

### 5. Creating tasks

A **Task** is a single piece of work (feature, bugfix, chore) fed into a workflow. Creating one is where you describe what you want done and point at the right workflow. From a project, go to **Tasks → New**.

Form fields:

- **Title** — one-line summary (e.g. "Add OAuth sign-in").
- **Kind** — `feature`, `bugfix`, or `chore`. Exposed to prompts as `${task_kind}`.
- **Workflow** — which workflow this task feeds.
- **Body** — detailed description (see next).
- **Context files** — list of repo files to include (see below).
- **Trigger** — manual / cron / GitHub branch watch.

#### The task body and "Format with Claude"

The body is Markdown. It's exposed to skill prompts as `${task_body}` and is the primary thing Claude reads to understand the work. Two things worth knowing:

1. **Format with Claude** — a button on the task form that sends your raw notes to Claude Haiku and returns a structured spec: a 2–3 sentence description plus an `## Acceptance criteria` section with testable bullet points. Handy when you're jotting down rough thoughts and want a cleaner brief. Always review the output before saving — it's a starting point, not gospel.
2. **Template variables** — the body itself supports `${variable}` interpolation at render time, so you can reference run context values if you wire them up.

Use whatever structure works for your team, but a rough ceiling of sections like **Context**, **Requirements**, **Acceptance criteria**, and **Non-goals** gives Claude plenty to work with.

#### Context file selection

Most workflows benefit from pointing Claude at the right files up-front. The **Context Files** picker lets you hand-select paths from the repo or auto-suggest them.

- **Suggest with Claude** — requires a ready code map on the project (see [Code maps](#code-maps)). Claude reads your task title and body, scans the code map, and returns a list of relevant files with short reasons ("defines the User model", "route config", etc.). You tick the ones you want to keep.
- **Manual entry** — you can also add paths directly. Each entry is `{ "path": "...", "reason": "..." }` under the hood.

At run time, the selected files are flattened into a multi-line string and exposed to every step as the `${context_files}` global variable. A skill body might include:

```markdown
Focus your work on these files:
${context_files}
```

Claude still has full access to the rest of the repo via its Read/Glob/Grep tools — this is just a nudge toward the right starting point.

#### Triggers: manual, cron, and GitHub branch watch

A task's **trigger** decides when runs fire. Pick one:

- **Manual** — default. Runs only fire when you click **Execute** on the task.
- **Cron** — schedule with a cron expression. The form has presets (hourly, every 4 hours, daily at 9am, weekdays at 9am, Mondays at 9am) plus a custom option. `CronTickJob` polls and fires `enqueue_run!(reason: "cron")` when the schedule matches; `last_fired_at` is tracked on the task for debugging.
- **GitHub branch watch** — give it a `repo_url` and a `branch` (you can auto-list branches by repo URL via the picker). `BranchWatchPollJob` runs every 15 minutes, calls `git ls-remote` to read the branch's HEAD SHA, and fires a run when the SHA changes. Useful for "run this task whenever `main` moves on the upstream project."

A task's status moves from `draft` → `ready` once a workflow is assigned and the trigger is configured. Runs transition it to `running` / `completed` / `failed`.

### 6. Running

Clicking **Execute** on a task (or any of the automatic triggers firing) calls `enqueue_run!`, which creates a `Run` record and queues `ExecuteRunJob`. The job:

1. Verifies the project's repo is cloned.
2. Seeds the run's context with globals (`task_title`, `task_body`, `task_kind`, `trigger_reason`, `repo_owner`, `repo_name`, `context_files`).
3. Walks the workflow's steps in position order plus any ad-hoc steps created during the run (recovery, follow-ups).
4. For each step, creates a `RunStep` record and hands it to `StepExecutor`.

#### Watching a run

The run page (`/runs/:id`) is a live view backed by Turbo Streams. For every step you can see:

- Status badge (`pending` → `running` → `passed` / `failed` / `retrying` / `skipped`).
- Output and error output, updated as it streams.
- Elapsed time and duration on finish.

For skill/prompt steps, Seneschal runs Claude with `--output-format stream-json --verbose` and parses each line of stdout as a streaming event. Events are broadcast every ~2 seconds and persisted to `RunStep.stream_log` for historical replay. You can read a run from weeks ago and watch it back.

Token counts and cost are extracted from stream events and surfaced in the UI via `RunStep#usage_stats`.

#### Stopping, resuming, and retrying

From a running run you can **Stop** to halt execution (status moves to `stopped`). From a failed or stopped run you have three recovery options:

- **Resume** — picks up from where it failed, re-executing the failed step. Useful if the failure was transient.
- **Retry from step** — choose any earlier step and re-run from there. Context from earlier successful steps is preserved.
- **Follow-up** — append new ad-hoc steps to an already-completed run. See below.

Seneschal also has a background `RunRecoveryJob` that catches runs whose jobs crashed (no heartbeat for 10+ minutes) and re-enqueues them with a `resume: true` flag so they skip completed steps.

#### Follow-ups

Sometimes a run finishes and you realize you want "one more thing" — rename some files, update a doc, etc. On any completed run, **Follow-Up** opens a form for adding a new ad-hoc step (skill, prompt, script, or command) with full access to the run's final context. The step runs as a fresh `RunStep` attached to the existing run, so all the plumbing (logs, token tracking) works the same.

### 7. User management and data export

- **Users** (admin only, `/users`) — invite collaborators by email. Seneschal generates an invite token; share the resulting `/invite/:token` link so the user can set their own password. Admins can reset invite tokens for users who lost their link, and toggle admin status or delete users.
- **Account** (`/account`) — any logged-in user can change their own email, password, and optionally enable two-factor auth.
- **Data** (admin only, `/data`) — download a full JSON export of projects, workflows, steps, skills, step templates, and pipeline tasks. Importing the same file is **destructive** (deletes existing pipeline data before loading the export) — user accounts and settings are preserved. Handy for moving between hosts or for periodic off-box backups alongside the `storage/` directory.

## Concepts

| Concept | Description |
|---------|-------------|
| **Project** | A Git repository. Cloned locally for Claude to work in. |
| **Code Map** | AI-generated index of a project's file tree grouped into modules, with per-file summaries. Powers context-file suggestions on tasks. |
| **Workflow** | An ordered sequence of steps belonging to a project. |
| **Step** | A single unit of work: skill, prompt, script, command, ci_check, or context_fetch. |
| **Skill** | A reusable Claude CLI prompt template. Can be shared across projects or scoped to one. |
| **Task** | A feature/bug/chore that gets fed into a workflow as context. |
| **Run** | One execution of a workflow for a given task. Tracks status of each step. |
| **Step Template** | A saved step configuration for quick reuse across workflows. |

### Step types

- **skill** — Sends a prompt to Claude CLI using the body of a Skill record. Supports `--output-format stream-json` for real-time streaming. Captures output into named variables for downstream steps.
- **prompt** — Same as skill, but the prompt is written inline on the step instead of referencing a reusable Skill.
- **script** — Runs a shell script (`bash -c`) with `${variable}` interpolation and run context as environment variables.
- **command** — Runs a single shell command (`bash -c`). Same interpolation as scripts.
- **ci_check** — Polls GitHub PR checks or a workflow run. On failure, returns cleaned job logs (and, when enabled, downloads failure artifacts to `.seneschal/ci-artifacts/<run_id>/` so recovery steps can Read screenshots, JUnit XML, etc.).
- **context_fetch** — Fetches content from a URL and stores it in the run context under a named key. GitHub repo URLs automatically resolve to the README; blob URLs fetch the file. Useful for pulling in docs from related repos.

### Failure recovery

Each step can configure an **On Fail** action that fires when the step fails, retrying up to `max_rounds` times (default 3):

- **Re-Open Previous Step** — resume the previous skill's Claude session with the failure and optional extra instructions.
- **Run Skill** — inject an ad-hoc recovery skill.
- **Run Script** / **Run Command** — inject an ad-hoc shell recovery action with `$PREVIOUS_FAILURE` env var.

After the recovery action, the original step re-executes. CI check steps are a natural fit: pair a CI check with a **Run Skill** recovery that invokes a "fix failing tests" skill, and you get a retry loop that runs until tests pass or rounds are exhausted.

## Stack

- Rails 8.1 with SQLite
- Solid Queue for background jobs
- Hotwire (Turbo + Stimulus) for real-time UI
- Tailwind CSS v4
- Propshaft asset pipeline
