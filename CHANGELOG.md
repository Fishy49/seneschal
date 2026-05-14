# Changelog

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
