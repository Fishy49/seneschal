<p align="center">
  <img src="app/assets/images/logo.png" width="80" alt="Seneschal" />
</p>

<h1 align="center">Seneschal</h1>

<p align="center">A self-hosted AI pipeline orchestrator for software projects. Define workflows that use Claude to plan, implement, review, and ship features — then watch them run, replay them later, and compare runs against each other.</p>

<p align="center">

https://github.com/user-attachments/assets/51d96dcf-b06a-48eb-9092-28e8e4cc03d8

</p>

## Table of contents

- [What it does](#what-it-does)
- [Installation](#installation)
- [How to use Seneschal](#how-to-use-seneschal)
- [Concepts](#concepts)
  - [Step types](#step-types)
  - [Runners](#runners)
  - [Failure recovery](#failure-recovery)
- [Stack](#stack)

## What it does

Seneschal connects your Git repositories to multi-step AI workflows. A typical pipeline:

1. Cut a feature branch and open a draft PR
2. Read the codebase, write an implementation plan, validate it against a JSON schema
3. Implement the feature (tests first, then code) inside an isolated git worktree
4. Self-review the diff against a read-only Claude session before going further
5. Monitor CI, inject fix-up steps on failure, promote the PR to ready when green

Each step is one of: a **skill** (a versioned, agentskills.io-conformant prompt + tooling bundle), a **prompt** (inline), a **shell script** or **command**, a **CI-check** monitor, a **context fetch**, a first-class **pr** step, or a read-only **self_review**. Steps pass data to each other through schema-validated structured outputs (via the Claude Agent SDK) or fenced text blocks (via the Claude CLI), and a failed CI run can inject recovery steps into the running pipeline and re-check automatically.

Every Claude invocation streams in real time and is persisted for replay. The Replay view scrubs through a finished run's full trajectory; the Compare view diffs two runs of the same task side-by-side.

## Installation

### Docker quick start

If you have Docker, this is the fastest way in:

```sh
docker run -p 3000:3000 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e GH_TOKEN=gh_... \
  -v $PWD/storage:/rails/storage \
  -v $PWD/repos:/rails/repos \
  -v $PWD/skills:/rails/skills \
  ghcr.io/fishy49/seneschal:latest
```

Then open [http://localhost:3000](http://localhost:3000) and create the admin account. The image bundles Ruby + Node + Python + the Claude Agent SDK sidecar + the `claude` and `gh` CLIs, so nothing on the host is required besides Docker. Multi-arch — works on Intel and Apple Silicon / arm64 Linux servers.

For a persistent setup, copy `.env.example` to `.env`, fill in the secrets, and run `docker compose up -d` against the [`docker-compose.yml`](docker-compose.yml) shipped in this repo.

**Volume layout**

| Mount | Purpose |
|---|---|
| `/rails/storage` | SQLite databases (projects, workflows, runs, skills metadata). **Back this up.** |
| `/rails/repos` | One git clone per Project (your code lives here). |
| `/rails/skills` | Filesystem-backed shared Skills (agentskills.io standard). Optional. |
| `/rails/tmp/worktrees` | Per-run git worktrees. Ephemeral but bind-mounting keeps `git worktree` snappier than tmpfs. |

**Auth options**

- **Claude API key** (works on every host, recommended): set `ANTHROPIC_API_KEY`. Headless, container-friendly. If you also have a Claude Pro/Max subscription, API usage is metered separately from the flat-rate subscription.
- **Claude Pro / OAuth — Linux hosts only**: run `claude auth login` on the host once, then mount `~/.claude` read-only into the container — `-v ~/.claude:/home/rails/.claude:ro`. **macOS hosts can't do this** because `claude auth login` stores credentials in the system Keychain, not in a flat file the container can see. macOS users with Pro/Max either need to use an API key for the container's runner or run Seneschal on a Linux box (Pi, NAS, VM).
- **GitHub**: set `GH_TOKEN` with `repo` scope (works everywhere), or — on Linux hosts — mount `~/.config/gh:/home/rails/.config/gh:ro`.

### Bare-metal install

For dev setup or a Linux-host install without Docker (Pi, NAS, VM, dev box), see **[SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md)**.

## How to use Seneschal

This section walks the full lifecycle, from first-run setup to running a workflow against a task. The general direction of travel is **integrations → project → skills → workflow → task → run**, but you can revisit any step at any time.

### Usage table of contents

- [1. First run: admin account and integrations](#1-first-run-admin-account-and-integrations)
- [2. Creating projects](#2-creating-projects)
  - [Cloning the repository](#cloning-the-repository)
  - [Worktrees: isolation per run](#worktrees-isolation-per-run)
  - [Code maps](#code-maps)
- [3. Skills](#3-skills)
  - [Authoring a skill](#authoring-a-skill)
  - [Skill scopes: shared, project, skill-repo](#skill-scopes-shared-project-skill-repo)
  - [Skill repos: subscribe to external libraries](#skill-repos-subscribe-to-external-libraries)
  - [JSON schemas, the default output variable, and one-click import](#json-schemas-the-default-output-variable-and-one-click-import)
- [4. Workflows](#4-workflows)
  - [Adding and ordering steps](#adding-and-ordering-steps)
  - [Choosing a runner](#choosing-a-runner)
  - [Step templates](#step-templates)
  - [Per-step Claude configuration](#per-step-claude-configuration)
  - [MCP servers and subagents](#mcp-servers-and-subagents)
  - [Failure recovery configuration](#failure-recovery-configuration)
- [5. Creating tasks](#5-creating-tasks)
- [6. Running, replaying, comparing](#6-running-replaying-comparing)
- [7. User management and data export](#7-user-management-and-data-export)

### 1. First run: admin account and integrations

On a fresh install, the first visit to Seneschal redirects you to `/setup/admin`. Create the initial admin account; this user has full access to every feature.

After logging in, the dashboard guides you to **Setup** (`/setup`), where Seneschal verifies the external tooling it shells out to:

- **Claude CLI** — `claude --version`. The CLI runner uses this directly; the SDK runner uses the CLI as a child process under the hood.
- **GitHub CLI** — `gh auth status`. Required for the `pr` step type and for CI-check polling.
- **SDK runner (optional)** — checks for the Python sidecar venv (`lib/sdk_runner/.venv`). If you only use the CLI runner you can ignore this.

If a check fails you'll see a red "Not verified" badge. Install or authenticate whatever's missing, then click re-check. The same page exposes settings for the **default Claude allowed tools** (e.g. `Bash(git *), Read, Edit, Glob, Grep`) and the **default runner** (CLI or SDK) — both are inherited by every step unless overridden per-step or per-workflow.

### 2. Creating projects

A **Project** is a Git repository Seneschal clones locally so Claude can work in it. From the sidebar choose **Projects → New** and fill in:

- **Name** — unique identifier shown throughout the UI.
- **Repo URL** — SSH or HTTPS URL that `git clone` can reach. Authentication uses whatever credentials (`gh auth`, SSH keys) are configured on the host.
- **Local path** — where the canonical clone lives on disk. Click **Default** to auto-fill `<rails_root>/repos/<project_name>` (or `/rails/repos/<project_name>` in Docker).
- **Project group** (optional) — grouping for the sidebar / filters.
- **Skip permissions** (optional, dangerous) — when set, every Claude invocation runs with `--dangerously-skip-permissions`. Use only for repos you fully trust.

#### Cloning the repository

Click **Clone Repository** on the project page. `CloneRepoJob` runs `git clone` (or `git pull --ff-only` if the directory already has a `.git`), streams progress to the page via Turbo, and flips the status from `not_cloned` → `cloning` → `ready` (or `error`, with stderr shown). Workflows can only execute against a project in `ready` status.

#### Worktrees: isolation per run

When a workflow runs, Seneschal allocates an **isolated git worktree** for that run under `tmp/worktrees/<run_id>/`, branched off `origin/HEAD`. Concurrent runs against the same project can no longer corrupt each other's working tree. Each worktree:

- Lives on a deterministic branch named `seneschal/run-<id>-<slug-of-task-title>`, persisted on the Run row so cleanup + the `pr` step's pre-flight idempotency check always reference the same name even if the task is renamed mid-flight.
- Gets torn down on success. On failure or stop it's **retained** for forensics, and a nightly reaper cleans up anything older than `worktree_retention_days` (default 7).
- Shares the project's git object database, so commits made in the worktree are visible from the canonical clone after the fact.

#### Code maps

A **code map** is an AI-generated overview of your repo that powers smarter context suggestions. From the project page click **Generate Code Map** to enqueue `GenerateCodeMapJob`, which walks the file tree (respecting `.gitignore`), asks Claude Haiku to group files into 5–15 logical modules with per-file summaries, and stores a module list plus a full-text search index. Code maps are tagged with the commit SHA they were built against and go stale after 24h — regenerate when your repo has changed meaningfully. The task form's **Suggest with Claude** button uses this to recommend relevant context files.

### 3. Skills

A **Skill** in Seneschal is an [agentskills.io](https://agentskills.io)-conformant package on disk: a directory containing a `SKILL.md` with YAML frontmatter, an optional `scripts/` directory (deterministic helpers that run without consuming context), an optional `references/` directory (lazily-loaded docs and schemas the agent can read on demand). This is the same format Claude Code, Codex CLI, Gemini CLI, Copilot, and Cursor adopted in late 2025 — skills you author in Seneschal are portable to any of those clients, and conversely any agentskills.io-compatible skill repo works here.

Four shared skills ship seeded by `db:seed`: `ingest_feature`, `plan_feature`, `implement_feature`, and `fix_failing_tests`. Together they form a complete feature-development pipeline.

#### Authoring a skill

From **Skills → New**:

- **Name** — kebab-case identifier. Becomes the directory name on disk.
- **Scope** — Shared (default) or scoped to a specific project (see below).
- **Description** — when-to-use prose. This is how the agent decides whether to load this skill at activation time, so prefer concrete triggers over vague language.
- **Starter body** — optional initial body for the SKILL.md.

Submitting scaffolds the SKILL.md to disk and shows you the on-disk path. From there, edit the file directly in your editor — Seneschal auto-syncs the cached frontmatter whenever you revisit the show page and the on-disk content hash has drifted.

The show page also surfaces:

- **Frontmatter table** — every key the agent will see (name, description, `allowed-tools`, version, etc.).
- **`scripts/` listing** — every file under `<skill>/scripts/`, with inline preview. These execute without consuming context window — the deterministic-inside-agentic pattern that makes skills compose at scale.
- **`references/` listing** — every file under `<skill>/references/`, with inline preview. The agent loads these lazily, on-demand, via Read.
- **Used in steps** — which workflow steps reference this skill.

#### Skill scopes: shared, project, skill-repo

- **Shared** (`project_id` is nil, `skill_repo_id` is nil) — usable by every project. Lives under `<SkillLoader.global_root>/<name>/` on disk (default `<rails_root>/skills/` or `/rails/skills/` in Docker). Ideal for generic skills like "plan a feature" or "fix failing tests."
- **Project-scoped** (`project_id` set) — only appears in the picker for workflows in that project. Lives under `<project>/.seneschal/skills/<name>/` so it commits alongside the project's code and travels with the repo.
- **Skill-repo-backed** (`skill_repo_id` set) — synced from an external git repository of skills. Read-only inside Seneschal; the upstream repo is the source of truth.

The skill picker on a workflow step shows everything returned by `Skill.for_project(project)` — that's shared skills + the project's own skills + any skill-repo skills.

#### Skill repos: subscribe to external libraries

A **Skill Repo** is a git repository of skills you subscribe to. From **Skill Repos → New** give it a name, a `repo_url`, and a branch — `SkillRepoSyncer` clones it, indexes every `*/SKILL.md` as a Skill row, captures any per-skill `.install-notes` content, and re-runs on a daily cron (or whenever you click **Sync** manually). Skills that disappear from upstream are *archived* (not deleted) so your workflow steps that reference them don't break silently.

During sync, Seneschal also scans each skill's `references/` for JSON Schema files (detected by an `$schema` keyword, `properties` / `oneOf` / `anyOf` / `allOf` keys, or an `{type: "object", properties: …}` shape) and auto-imports them as top-level `JsonSchema` rows. If a skill ships exactly one schema in `references/` and has no manual default set, that schema gets wired as the skill's `default_json_schema`. Multiple schemas import every row but leave the linking to you — pick one via the show page's **Import as default schema** button.

#### JSON schemas, the default output variable, and one-click import

A skill can declare a **default output schema** (`default_json_schema_id` + `default_output_variable`) — when set, every step that uses this skill inherits the schema and the output variable name unless explicitly overridden. Steps with a schema attached produce structured, validated output (via the SDK runner's `StructuredOutput` tool or the CLI runner's prompt-engineered fenced block; see [Runners](#runners)).

You set the default in three ways:

1. **In the skill form** — pick from existing JsonSchemas via the dropdown.
2. **Import a `references/*.schema.json`** — the show page detects schema-shaped JSON files in `references/` and surfaces an "Import as default schema" button. Click → confirm → done; a new JsonSchema is created (named `<skill>__<basename>`), `$schema` is stripped (a quirk of the bundled `claude` CLI), and the skill's default is wired.
3. **Auto-imported on SkillRepo sync** — see above.

Re-importing the same reference file overwrites the JsonSchema in place, so on-disk edits propagate cleanly on the next click (or the next sync).

### 4. Workflows

A **Workflow** is an ordered sequence of steps that runs against a task. From a project's page choose **New Workflow**, give it a name and description, and pick a trigger type (usually `manual` — per-task triggers on the task give you more control).

Each workflow can also pick a **default runner** (CLI or SDK) — see [Choosing a runner](#choosing-a-runner).

#### Adding and ordering steps

From the workflow page, click **Add Step**. Each step has:

- **Name** — shown in run timelines.
- **Position** — execution order. Auto-assigns to `max + 1`; drag to reorder.
- **Type** — one of `skill`, `prompt`, `script`, `command`, `ci_check`, `context_fetch`, `pr`, `self_review` (see [Step types](#step-types)).
- **Body** (or **Skill**) — the work to do.
- **Produces** / **Consumes** — variables this step emits / accepts. Schema-bound steps (default or explicit `json_schema_id`) get structured output; unbound steps use a fenced `` ```output `` block parsed by `PipelineExtractor`.
- **Additional Context** — freeform text injected into prompts or exposed to scripts as `$INPUT_CONTEXT`. Supports `${variable}` interpolation.
- **Max Retries** / **Timeout** — per-step execution guards.
- **On Fail** — optional recovery action.

Steps execute in position order. On success, produced variables merge into the run's context; if a schema-bound step's output fails validation, the runner retries within the same Claude session up to `validation_max_attempts` (default 3) before failing the step.

#### Choosing a runner

Seneschal can route Claude work through two different runners:

- **Claude CLI runner** — shells out to `claude` with `--output-format stream-json`. Simple, well-understood, no extra deps.
- **Claude Agent SDK runner** — a Python sidecar (`lib/sdk_runner/`) that wraps the [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python). Buys you schema-validated structured outputs (auto-injected `StructuredOutput` tool, no prompt-engineered output blocks), per-call subagent definitions, MCP server configuration, and policy hooks like `confine_writes_to_cwd`.

The runner is resolved per-step in this order: explicit `Step.config["runner"]` → workflow-level `Workflow.config["runner"]` → global `Setting["default_runner"]`. You can flip the global default on the Setup page; you can flip a single workflow via its edit form; you can flip a single step via the step form. Mix-and-match is fine — the CLI runner ignores SDK-only kwargs cleanly.

For schema-bound steps the SDK runner is strongly recommended: structured outputs short-circuit the prompt-engineered retry loop and produce cleanly validated objects every time.

#### Step templates

Once you've configured a step you like, check **Save as Template** at the bottom of the form and give it a name. Templates are global across projects and listed under **Templates** in the sidebar. New steps can start from a template via **Choose Template** — it copies the type, body, config, skill, retries, timeout, and input context.

#### Per-step Claude configuration

Skill and prompt steps expose:

- **Model** — Opus 4.7, Sonnet 4.6, Haiku 4.5, or Default.
- **Effort** — low, medium, high, xhigh, max (maps to `--effort`).
- **Max Turns** — cap on agent turns.
- **Allowed Tools** — comma-separated list like `Bash(git *), Read, Edit, Glob, Grep`. Leave blank to inherit the global default.
- **JSON Schema** — pick a JsonSchema to validate this step's structured output against. Skill steps inherit the skill's default if unset.
- **Produces variable** — the output variable name the schema-validated payload gets stored under.

#### MCP servers and subagents

Two SDK-runner-only knobs on skill / prompt / self_review steps:

- **MCP servers** — a JSON map of [Model Context Protocol](https://modelcontextprotocol.io/) server configurations the agent can call into. Per-step config beats the global `Setting["mcp_servers"]`. Each entry is either a `stdio`, `sse`, or `http` server spec.
- **Subagents** — a JSON map of named agent definitions surfaced via the SDK's `Task` tool. Each entry takes the SDK's `AgentDefinition` fields (description, prompt, tools, model, …). Useful for "this step can spawn a code-reviewer subagent with read-only tools."

Both are ignored by the CLI runner.

#### Failure recovery configuration

Any step can define an **On Fail** action that fires when the step fails, with up to `max_rounds` (default 3) attempts:

- **Re-Open Previous Step** — resume the previous skill/prompt step's Claude session with the failure output and optional extra instructions. Uses the stored `claude_session_id` so the model has full memory of the original attempt.
- **Run Skill** — inject an ad-hoc step using a chosen recovery skill. The failure output and step name are prepended automatically.
- **Run Script** / **Run Command** — inject an ad-hoc shell step. Has `$PREVIOUS_FAILURE` and `$PREVIOUS_FAILURE_STEP` env vars available.

After each recovery round, the original step re-executes. The loop exits when it passes or when `max_rounds` is exhausted.

CI-check steps can also download failure artifacts (test screenshots, JUnit XML, etc.) to `.seneschal/ci-artifacts/<run_id>/`, which any recovery skill can `Read` to diagnose what broke.

### 5. Creating tasks

A **Task** is one piece of work (feature, bugfix, chore) fed into a workflow. From a project, go to **Tasks → New** and fill in:

- **Title** — one-line summary. Slugified into the run's worktree branch name (`seneschal/run-<id>-<slug>`).
- **Kind** — `feature`, `bugfix`, or `chore`. Exposed to prompts as `${task_kind}`.
- **Workflow** — which workflow this task feeds.
- **Body** — detailed description. Markdown. Exposed as `${task_body}`.
- **Context files** — list of repo paths to include (manual or **Suggest with Claude** if a code map is ready).
- **Trigger** — manual / cron / GitHub branch watch.

Triggers:

- **Manual** — runs only fire when you click **Execute**.
- **Cron** — schedule with a cron expression (presets available). `CronTickJob` polls every minute and fires when the schedule matches.
- **GitHub branch watch** — give it a `repo_url` and `branch`; `BranchWatchPollJob` runs every 15 minutes, reads the branch's HEAD SHA via `git ls-remote`, and fires a run when the SHA changes.

The body has a **Format with Claude** button that sends raw notes to Claude Haiku and returns a structured spec with `## Acceptance criteria` bullets — handy when you're jotting rough thoughts.

### 6. Running, replaying, comparing

Clicking **Execute** on a task (or any trigger firing) calls `enqueue_run!`, which creates a `Run`, allocates a fresh git worktree, and queues `ExecuteRunJob`. The job seeds the run's context with globals (`task_title`, `task_body`, `task_kind`, `trigger_reason`, `repo_owner`, `repo_name`, `context_files`) and walks the workflow's steps in order.

**Watching a run.** The run page (`/runs/:id`) is a live Turbo-Streams view. For each step you see status (pending → running → passed / failed / retrying / skipped), streaming output, elapsed time, token counts, and cost. Skill / prompt / self_review steps stream every event from the runner; everything lands in `RunStep.stream_log` for historical replay.

**Stop, resume, retry.** From a running run, **Stop** halts execution. From a failed or stopped run, **Resume** re-executes the failed step, **Retry from step** re-runs from any earlier step (preserving context), and **Follow-up** appends a new ad-hoc step to a completed run with full access to its context. A background `RunRecoveryJob` catches runs whose jobs crashed (no heartbeat for 10+ min) and re-enqueues them with `resume: true` so completed steps are skipped.

**Replay** (`/runs/:id/replay`). A drill-down view of the full trajectory. For every RunStep, paints a chronological timeline pairing each `tool_use` block with its `tool_result`, surfacing thinking blocks behind a filter chip, and breaking down per-step / per-run cost / duration / turn counts. Filter chips toggle visibility per entry kind. Recovery attempts nest under their parent step.

**Compare** (`/runs/:id/diff?against=<id>`). Side-by-side comparison of two Runs. Defaults to the most-recent other Run of the same task (apples-to-apples). Per-step alignment by position; **Diverged** badges surface where the two runs structurally differ (different tool calls, different stop reasons). Each side drops a per-kind tally + an expandable full trajectory.

### 7. User management and data export

- **Users** (admin only, `/users`) — invite collaborators by email. Seneschal generates an invite token; share the resulting `/invite/:token` link so the user can set their own password. Admins can rotate tokens, toggle admin status, or delete users.
- **Account** (`/account`) — any logged-in user can change their own email, password, and optionally enable two-factor auth.
- **Data** (admin only, `/data`) — download a full JSON export of projects, workflows, steps, skills (including SKILL.md content for filesystem-backed skills), step templates, and pipeline tasks. Importing is **destructive** (wipes existing pipeline data before loading) — user accounts and settings are preserved. Handy for moving between hosts or off-box backups alongside `storage/`.

## Concepts

| Concept | Description |
|---------|-------------|
| **Project** | A Git repository. Cloned locally for Claude to work in. |
| **Worktree** | An isolated `git worktree` allocated per Run so concurrent runs don't corrupt each other. Branch name is deterministic: `seneschal/run-<id>-<slug>`. |
| **Code Map** | AI-generated index of a project's file tree grouped into modules with per-file summaries. Powers context-file suggestions. |
| **Skill** | An agentskills.io-conformant folder on disk: `SKILL.md` + optional `scripts/` + optional `references/`. Portable across every client that adopts the standard. |
| **Skill Repo** | An external git repo of skills, cloned and indexed by Seneschal. Auto-syncs and auto-imports any `references/*.schema.json` files. |
| **JSON Schema** | A schema document Seneschal validates structured step outputs against. Can be the default for a Skill, an explicit pick per Step, or imported one-click from a skill's `references/`. |
| **Workflow** | An ordered sequence of Steps belonging to a Project. Has a default runner (CLI or SDK). |
| **Step** | A single unit of work. See [Step types](#step-types). |
| **Runner** | The agent backend a skill / prompt / self_review step routes through: Claude CLI or Claude Agent SDK. |
| **Task** | A feature/bug/chore fed into a workflow as context. |
| **Run** | One execution of a workflow for a given task. Runs in an isolated worktree, on a deterministic branch. |
| **Step Template** | A saved step configuration for quick reuse across workflows. |

### Step types

- **skill** — Runs Claude against the SKILL.md body of a Skill record. Inherits the skill's default JSON schema + output variable unless overridden. Streams real-time output via `--output-format stream-json`.
- **prompt** — Same as skill, but the prompt is written inline on the step rather than referencing a reusable Skill.
- **script** — Runs a shell script (`bash -c`) with `${variable}` interpolation and run context as environment variables.
- **command** — Runs a single shell command (`bash -c`). Same interpolation as scripts.
- **ci_check** — Polls GitHub PR checks or a workflow run. On failure, returns cleaned job logs and (optionally) downloads failure artifacts to `.seneschal/ci-artifacts/<run_id>/` for recovery steps to Read.
- **context_fetch** — Fetches content from a URL and stores it in the run context under a named key. GitHub repo URLs resolve to the README; blob URLs fetch the file.
- **pr** — First-class GitHub PR creation. Declares title / body / base / draft / branch / reviewers / labels / assignees in structured config (no prompt-engineering `gh pr create`). Idempotent: pre-flight `gh pr list --head <branch>` reuses any existing PR on the worktree's branch by default; `clean: true` closes the existing PR + wipes the remote ref + creates fresh.
- **self_review** — Read-only Claude session over the current `git diff <base>...HEAD`. Forces the tool set to `Read,Grep,Glob`. Designed to slot between an implement step and a `pr` step so a draft only gets promoted to ready when the review verdict is PASS.

### Runners

A runner is resolved per-step. Precedence: `Step.config["runner"]` → `Workflow.config["runner"]` → `Setting["default_runner"]` → `claude_cli`.

- **`claude_cli`** — shells out to the `claude` CLI binary. Default. Simplest setup; no Python deps.
- **`claude_sdk`** — Python sidecar wrapping the Claude Agent SDK. Provides schema-validated structured outputs, per-call subagent definitions, MCP server config, and declarative policy hooks (write-confinement default-on). Requires the SDK runner to be installed — see [SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md#optional-claude-agent-sdk-runner) (the Docker image bundles it).

### Failure recovery

Each step can configure an **On Fail** action that fires when the step fails, retrying up to `max_rounds` times (default 3):

- **Re-Open Previous Step** — resume the previous skill/prompt step's Claude session with the failure and optional extra instructions.
- **Run Skill** — inject an ad-hoc recovery skill.
- **Run Script** / **Run Command** — inject an ad-hoc shell recovery action with `$PREVIOUS_FAILURE` env var.

After the recovery action, the original step re-executes. CI-check steps are a natural fit: pair a CI check with a Run Skill recovery that invokes a "fix failing tests" skill, and you get a retry loop that runs until tests pass or rounds are exhausted.

## Stack

- Rails 8.1 with SQLite (primary + Solid Queue / Cache / Cable auxiliaries)
- Solid Queue for background jobs
- Hotwire (Turbo + Stimulus) for real-time UI
- Tailwind CSS v4
- Propshaft asset pipeline
- Python 3 + [claude-agent-sdk](https://github.com/anthropics/claude-agent-sdk-python) sidecar (optional runner)
- Multi-arch Docker image published to GHCR
