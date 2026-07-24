# Changelog

## Unreleased - UX + collaboration redesign

Work in progress. Items land one at a time; see `IMPLEMENTATION_PLAN.md`.

### 1.6 Task form cascade and integrity validation

The task form referenced a `task-form` Stimulus controller that did not exist,
so changing Project never filtered the Workflow select and a new task could be
saved pointing at a workflow from a different project.

- New `task_form_controller.js` caches the full workflow option list on connect
  and rebuilds the select from the options matching the selected project,
  clearing a selection that no longer belongs. It runs on connect too, which
  also fixes the old view bug where `/tasks/new` listed every workflow in the
  install.
- Workflow options now carry `data-project-id`.
- `PipelineTask` validates `workflow_matches_project`, so a crafted request
  cannot attach a foreign workflow.

### 1.5 The Launch Bar

Cmd/Ctrl+K from any page opens an overlay: describe the work, confirm project
and workflow, Enter, and a run is streaming. No form, no draft, no navigation.

- New `QuickLaunchController`. `GET /quick_launch/options` returns projects
  with their workflows as JSON; `POST /quick_launch` builds a `PipelineTask`
  (first line as the title truncated to 80 chars, whole description as the
  body) and enqueues its run, answering with `{ redirect: "/runs/N" }` or a
  422 carrying the validation messages.
- New `command_palette_controller.js` owns the shortcut. It only claims Escape
  while the overlay is open so other modals keep their handlers, and it
  remembers the last-used project and workflow in `localStorage`
  (`seneschal.launch.project` / `seneschal.launch.workflow`).
- Rendered once from the layout for signed-in users, with a sidebar hint.

### 1.4 Dashboard mission control

The landing page now answers "what needs me?" and "what can I start?" before
it answers "what happened recently?".

- New "Needs you" section at the top listing every run parked on a manual
  approval gate, with a count and a Review link. Renders nothing when empty.
  Those runs are excluded from Active Runs so nothing is listed twice.
- New "Ready to run" section finally renders `@actionable_tasks`, which the
  controller had been querying and the view had been ignoring. Executable
  tasks get a Run button; the rest get an Edit link.
- `Run.awaiting_approval` scope added.
- New `dashboard_refresh_controller.js` re-fetches the page every 5s and swaps
  only the marked regions (`#dashboard_awaiting`, `#dashboard_active`,
  `#dashboard_actionable`), skipping the work entirely while the tab is hidden
  and leaving the DOM untouched when the markup is unchanged.

### 1.3 Workflow trigger has a button

`workflows#trigger` existed but nothing in the UI called it. The workflow show
page now leads with a "Run workflow" button that creates a run and lands on it.
When the project repo is not cloned the button renders disabled with a tooltip
explaining why, instead of queueing a run that would fail on allocation.

### 1.2 Re-run affordances

Finished runs are one click away from being run again.

- The run header shows a "Re-run" button on completed / failed / stopped runs
  whose task is still executable, next to Replay and Compare.
- `shared/_runs_list` gained a right-aligned actions column with a compact
  Re-run button under the same conditions, so every run list (dashboard,
  runs index, project page) can relaunch without a detour.
- Neither button confirms.

### 1.1 Save & Run

Launching a task no longer requires the draft -> ready -> execute ratchet.

- `PipelineTask#executable?` is now `workflow.present? && !archived? && status != "running"`.
  Drafts, completed, and failed tasks are all launchable; only an in-flight run
  or an archived task blocks the button.
- The task form gained a primary "Save & Run" submit (`run_now=1`) that saves
  and starts a run in one trip, landing on the streaming run page. Plain "Save"
  is still there as the secondary action. Saving with `run_now` and no workflow
  saves the task and flashes an explanation instead of erroring.
- `PipelineTasksController#execute` promotes a draft to `ready` before
  enqueueing, so the Execute button works straight off a new task.
- The "Mark Ready" button is gone from the task page (the route and action
  remain). The Execute button relabels itself "Re-run" once the task has runs.

## Unreleased — Previewable assets

Skill / prompt steps can now register generated images, audio, or video as
"previewable assets" that show up as clickable tiles on the step's run row.
Clicking a tile opens a modal with the appropriate player (`<img>`,
`<audio controls>`, or `<video controls>`).

- New `bin/seneschal-asset register --path <file> [--kind …] [--label …]` CLI,
  sibling to `bin/seneschal-context`. Talks to SQLite directly (no Rails
  boot), scoped by the same `SENESCHAL_DB_PATH` / `SENESCHAL_RUN_ID` /
  `SENESCHAL_RUN_STEP_ID` env vars, plus `SENESCHAL_ASSETS_ROOT`. Refuses
  to register an asset if `run_step_id` doesn't belong to the given run.
- New `preview_assets` table + `PreviewAsset` model, with `kind`, `label`,
  `original_filename`, `content_type`, `byte_size`, `storage_path`.
- Files are copied out of the worktree into persistent storage at
  registration time (default `storage/run_assets/<run_id>/<run_step_id>/…`,
  overridable via `Setting["run_assets_root"]`) so old runs stay browsable
  after `WorktreeManager` reaps the worktree. If the underlying file is
  missing the tile renders dimmed and the modal explains why; the controller
  serves a 410 instead of crashing.
- Step form gains a "Preview Assets" checkbox under Claude config. When on,
  `StepExecutor` appends a tool-usage block to the prompt explaining the
  CLI and auto-merges `Bash(seneschal-asset:*)` into `allowed_tools` so the
  operator only has to toggle the one checkbox.
- New `PreviewAssetsController#show` route serves the file inline with the
  recorded `content_type`.
- UI: `app/views/runs/_step_assets.html.erb` renders the tile grid;
  `asset_preview_modal_controller.js` Stimulus controller swaps player
  elements per kind.

No reaper job for `storage/run_assets/` yet — assets currently live for the
life of the database row. A future mirror of `WorktreeManager.reap_stale`
can sweep old run subtrees on the same retention window if desired.

## Unreleased — `refactor/agent-runtime` (the architectural refactor)

A foundation pass on the agent-runtime stack, organized into five phases. Each
phase is independently functional; the order is the dependency order. No
existing behavior is removed — these changes are additive scaffolding that
later phases will start *using* for default code paths.

### Phase 1: Runner abstraction

The `claude` CLI invocation no longer lives inside `StepExecutor`. Skill /
prompt steps now dispatch through a `Runners::Base` interface:

- `Runners::ClaudeCLI` — the current `claude -p` shell-out, fully extracted
- `Runners::ClaudeSDK` — `NotImplementedError` stub preserving the seam for a
  future Claude Agent SDK runner (Python or TypeScript sidecar)
- `Runners.lookup(name)` dispatches by name; per-step override via
  `Step.config["runner"]` falls back to `Setting["default_runner"]`
  ("claude_cli" by default)
- `Runners::Result` is a shared struct with `session_id` as a first-class
  field. `StepExecutor::Result` is aliased for backward compat.

Inflector adds `CLI` / `SDK` / `MCP` acronyms so namespaced class names
resolve correctly under Zeitwerk.

Pure refactor — same CLI flags, same env, same stream parsing.

### Phase 2: Worktree isolation

Each Run now owns an isolated git worktree under `Setting["worktree_root"]`
(default `tmp/worktrees/<run_id>/`), on a deterministic
`seneschal/run-<id>` branch.

- `WorktreeManager` — `allocate / ensure_for / cleanup / retain / reap_stale`
- Allocation does `git fetch` + branches off `origin/HEAD` (with fallbacks),
  so it's **independent of whatever state `project.local_path` is in**
- `ExecuteRunJob` allocates at run start, cleans up on success, retains on
  failure / stop, leaves the worktree intact across `awaiting_approval`
- `WorktreeReaperJob` runs daily at 4am, prunes retained worktrees past the
  configurable window (`Setting["worktree_retention_days"]`, default 7 days)
- `git pull --ff-only` switched from `system` to `Open3.capture3` so its
  stderr gets logged instead of leaked to job output
- `seneschal:projects:prepare_for_worktrees` and `:reap_all_worktrees`
  rake tasks — optional cleanup, no longer required for the migration

Concurrent runs on the same project no longer corrupt each other's working
tree. Failed runs preserve their worktree state for forensics.

### Phase 3: SKILL.md infrastructure

Skills can now be backed by agentskills.io `SKILL.md` folders on disk.
Nothing is migrated yet — this phase only adds the plumbing.

- `Skill` model gains `source_kind`, `relative_path`, `content_hash`, and
  `cached_metadata` columns; `body` becomes nullable
- `SkillMdParser` — strict-line frontmatter splitter (won't be fooled by
  markdown `---` horizontal rules in the body)
- `SkillMdValidator` — validates against `config/schemas/skill_md.schema.json`
  via json_schemer (requires `name` + `description`, tolerates extra fields)
- `SkillLoader` — resolves a skill name across four tiers (introduced
  progressively in phases 3 and 5):
  1. `<project>/.claude/skills/<name>/`
  2. `<project>/.seneschal/skills/<name>/`
  3. each path in `Setting["skills_global_roots"]`
  4. each enabled `SkillRepo` (priority order)
- `Skill#body` is now backing-aware: filesystem-backed skills read from disk
  transparently, so `Step#prompt_body` and `TemplateRenderer` work unchanged
- `SkillImporter` refactored to use the new parser (one canonical splitter)

### Phase 4: Skill export to filesystem

`SkillExporter` materializes legacy DB-backed skills as on-disk
`SKILL.md` folders. Opt-in via rake task.

- Shared skills export to `<SkillLoader.global_root>/<slug>/SKILL.md`
- Project-scoped skills export to `<project>/.seneschal/skills/<slug>/`
- Group-scoped skills are skipped with a warning (no single project to
  attach to)
- Frontmatter derived: name from kebab-case slug, description from the
  existing column (TODO placeholder if blank), `allowed-tools` from the most
  common `Step.config["allowed_tools"]` across using steps
- Idempotent: re-running skips skills already on disk, so operator
  hand-edits survive
- `seneschal:skills:export_to_filesystem` is the rake task; no behavior
  change until the operator runs it
- `body` column stays populated during transition — `Skill#body` reads
  from disk, but the column is the fallback if the file vanishes (drops
  in a future migration)

### Phase 5: External skill repos (first-class)

External git repos full of agentskills.io skills can be registered, cloned,
and indexed automatically. Models the `~/code/claude-skills/` install.sh
pattern but server-side and team-shared.

- `SkillRepo` model: name, repo_url, local_path, branch, enabled,
  priority, last_synced_at, last_sync_error, install_notes
- `SkillRepoSyncer` — clones (or fetches + reset --hard to track upstream),
  walks `*/SKILL.md`, upserts `Skill` records with
  `source_kind: "skill_repo"`, archives skills whose folders disappeared
  (doesn't delete — preserves `Step.skill_id` foreign keys), captures each
  skill's `.install-notes` content
- `SyncSkillRepoJob` — per-repo background sync
- `SyncAllSkillReposJob` — fan-out scheduled every 6 hours
- `Setting["skills_global_roots"]` — comma- or newline-separated list of
  global skill roots (multi-source). Walks in priority order. First match
  wins. Backward-compat with the singular `skills_global_root`.
- Admin-only UI at `/skill_repos` — list, add, edit (name/branch/priority/
  enabled, NOT repo_url to avoid orphaning the local clone), sync, remove
- `Skill.uniqueness` scope now includes `skill_repo_id` so the same skill
  name can exist in multiple repos and the shared scope simultaneously,
  disambiguated by `display_name` (`<repo_name>/<skill_name>`)
- Rake tasks for full CLI lifecycle: `seneschal:skill_repos:{add,list,sync,remove}`

### Migrations included

```
20260512000001 AddWorktreeFieldsToRuns
20260512000002 AddFilesystemFieldsToSkills
20260512000003 CreateSkillRepos
```

All forward-compatible — running `db:migrate` is safe and non-destructive.

### Deploy notes

1. `bin/rails db:migrate` is the only required step.
2. Optionally `bin/rails seneschal:skills:export_to_filesystem` to migrate
   the four seeded skills onto disk. Idempotent, can be deferred.
3. Optionally register external skill repos:
   `bin/rails 'seneschal:skill_repos:add[git@github.com:org/skills,my-skills,main]'`
   or via the new `/skill_repos` UI.
4. `git worktree` is now a hard dependency — already standard on git ≥ 2.5
   so nothing to install, but worth knowing.

### Review feedback fixes

A round of polish after the PR review:

- **WorktreeManager.cleanup** now runs `worktree prune` before `branch -D`,
  so when the worktree dir is removed out-of-band and cleanup falls back
  to `rm_rf`, stale metadata is pruned and branch deletion still succeeds.
- **SkillRepoSyncer** now runs each imported `SKILL.md` through
  `SkillMdValidator` and logs a warning via `Rails.logger.warn` when the
  frontmatter doesn't match the schema. Import stays permissive
  (slug-fallback for missing `name`, nil description allowed) but
  operators get visibility into upstream skills with broken metadata.
- **Skill#body** memoizes the `File.exist?` + parse so a single record
  reads disk at most once. Skill index pages and other list views stop
  paying O(N) stat syscalls on every render.
- **SkillRepo#repo_url** validates URL form: accepts http(s)/ssh/git/file
  schemes, scp-like `git@host:path`, and absolute paths; rejects git's
  `ext::` helper and bare strings. Defense-in-depth against typo-style
  bugs reaching `git clone`.
- **SkillRepoSyncer** caps each captured `.install-notes` at 10 KB so an
  oversized upstream file can't bloat the `install_notes` JSON column.
- **WorktreeManager.default_branch_name** extracted as a shared helper;
  MegaUpdate and the `prepare_for_worktrees` rake task both use it
  instead of inlining `git symbolic-ref refs/remotes/origin/HEAD`.

### Stats

23 commits, 679 tests passing (up from 555), rubocop clean.
