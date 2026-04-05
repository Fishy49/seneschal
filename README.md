<p align="center">
  <img src="app/assets/images/logo.png" width="80" alt="Seneschal" />
</p>

<h1 align="center">Seneschal</h1>

<p align="center">An AI pipeline orchestrator for software projects. Define workflows that use Claude to plan, implement, and validate features, then watch them run.</p>

## What it does

Seneschal connects your Git repositories to multi-step AI workflows. A typical pipeline might:

1. Create a feature branch and draft PR
2. Explore the codebase and write an implementation plan
3. Implement the feature (tests first, then code)
4. Monitor CI checks and automatically retry on failure

Each step can be a **skill** (a Claude CLI prompt), a **shell script**, a **command**, or a **CI check** monitor. Steps pass context to each other through captured outputs and template variables. Failed CI checks can inject fix-up steps into the running pipeline and re-check automatically.

Streaming output from Claude skills is captured in real time and stored for historical review.

## Requirements

- Ruby 3.4+
- Node.js (for Tailwind CSS builds)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated

## Setup

```sh
git clone <repo-url> && cd seneschal
bundle install
bin/rails db:prepare
bin/rails db:seed        # creates a default user and shared skills
```

Start the dev server (runs Rails + Solid Queue + Tailwind watcher):

```sh
bin/dev
```

Visit `http://localhost:3000`. On first login you will be guided through an integration check to verify that `claude` and `gh` are available on the host.

### Default credentials

```
Email:    admin@seneschal.dev
Password: password
```

You can change these from the Account page after logging in. Two-factor authentication (TOTP) can be enabled from the sidebar.

## Concepts

| Concept | Description |
|---------|-------------|
| **Project** | A Git repository. Cloned locally for Claude to work in. |
| **Workflow** | An ordered sequence of steps belonging to a project. |
| **Step** | A single unit of work: skill, script, command, or ci_check. |
| **Skill** | A reusable Claude CLI prompt template. Can be shared across projects or scoped to one. |
| **Task** | A feature/bug/chore that gets fed into a workflow as context. |
| **Run** | One execution of a workflow for a given task. Tracks status of each step. |

### Step types

- **skill** - Sends a prompt to Claude CLI. Supports `--output-format stream-json` for real-time streaming. Can capture output into named variables for downstream steps.
- **script** - Runs a shell script with environment variables from previous step outputs.
- **command** - Runs a single shell command.
- **ci_check** - Polls GitHub PR checks. On failure, can inject steps (like a fix skill) back into the running pipeline and re-validate.

### Failure injection

CI check steps can be configured with `on_failure_inject` to automatically insert repair steps when checks fail. For example, a CI check can inject a "fix failing tests" skill followed by another CI check, creating a retry loop that runs until tests pass or the injection limit is reached.

Steps can be marked as **inject only**, meaning they do not run in the normal workflow sequence but are available as injection targets.

## Stack

- Rails 8.1 with SQLite
- Solid Queue for background jobs
- Hotwire (Turbo + Stimulus) for real-time UI
- Tailwind CSS v4
- Propshaft asset pipeline
