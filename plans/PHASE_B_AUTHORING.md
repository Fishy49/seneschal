# UI Overhaul Phase B - Authoring

Project hub, the workflow editor + step inspector (the flagship), and the
Library. Design source: `PRODUCT_REDESIGN.md` sections 5.2, 5.3, 5.6, 7.
Phase A must be merged first (this phase uses its components, nav, and
helpers).

## How to use this document

- Work items are ordered. Do them top to bottom.
- One work item = one commit on the phase branch (`feat/ui-phase-b`).
- Before editing ANYTHING in an item, read every file under "Read first".
  Trust file contents over this plan.
- If the code contradicts this plan, STOP and report instead of
  improvising.
- Do not refactor outside the current item's scope.

## Hard rules (every item)

1. NEVER write an em dash (U+2014) or en dash (U+2013) anywhere. Plain
   hyphens only. A pre-write hook enforces this.
2. Match surrounding code style; comments only for non-obvious
   constraints.
3. Every behavioral change gets a minitest test.
4. CHANGELOG.md entry per item under `## Unreleased - UI overhaul phase B`.
5. NEVER modify: `StepExecutor` internals, `app/services/runners/*`,
   `WorktreeManager`, `ExecuteRunJob` step-walking. Everything in this
   phase is UI, models, and controllers. If an item seems to require an
   executor change, STOP and report.
6. Conventional commits.

## Harness notes

- Lint: `bundle exec rubocop` (no `bin/rubocop`). Tests: `bin/rails test`
  AND `bin/rails test:system` (separate commands, both required).
- minitest 6: no `minitest/mock`; stub via `define_singleton_method` with
  `ensure` restore. No `assigns` in controller tests - assert on markup.
- Fixtures: `users(:admin)`, `users(:other)`; steps fixtures include
  `steps(:skill_step)`; check `test/fixtures/` before inventing data.
- `turbo_confirm` only on destructive actions.
- The step form is heavily exercised by system tests - expect to update
  them throughout B.3-B.5.

## Key facts about today's step machinery (verified July 2026)

- `Step::STEP_TYPES = ["skill", "script", "command", "ci_check",
  "context_fetch", "prompt", "pr", "self_review"]`. The form offers only
  7 - `self_review` is fully implemented in the executor (reads config
  keys `base_ref`, `focus`) but unreachable from the UI.
- `execute_script` and `execute_command` in the executor are identical;
  script/command are one behavior with two names.
- `app/views/steps/_form.html.erb` is ~806 lines, 4 JS tabs, ~40 fields;
  `step_form_controller.js` has ~35 targets. Non-`step[...]` fields are
  top-level params hand-marshalled by `StepsController#build_step_config`
  (`build_ci_check_config`, `build_skill_config`,
  `build_context_fetch_config`, `build_pr_config`); switching a saved
  step's type silently discards its old config.
- The ci_check field `ci_ref` defaults to `${branch}` but the variable a
  pr step actually emits is `branch_name` - a shipped mismatch.
- The allowed-tools help text claims blank means "full capability"; in
  reality blank inherits `Setting["default_allowed_tools"]`, falling back
  to `StepExecutor::DEFAULT_ALLOWED_TOOLS` ("Bash,Read,Edit,Glob,Grep").
- Skill-default schema inheritance is a three-state picker
  (`schema_picker_mode` inherit/override) driven by
  `Step#inherit_skill_defaults`.
- `Step.available_variables_for(workflow, position)` returns globals +
  prior outputs + schema-derived dotted paths, each with a `queryable`
  flag. `GLOBAL_VARIABLES = task_title, task_body, task_kind, repo_owner,
  repo_name, context_files`.
- `Workflow#trigger_type`/`trigger_config` are dead columns (no form, no
  reader in app code); real scheduling lives on PipelineTask.
- `SkillImporter` scans only `<project>/.claude/skills` even though
  `SkillScaffolder` writes project skills to `<project>/.seneschal/skills`.
- Skills are pointers to `SKILL.md` files on disk (`Skill#body` reads and
  parses frontmatter per call); there is no in-app editor after create.

---

## B.1 Project hub

**Goal:** The project page becomes a tabbed hub: Overview, Workflows,
Tasks, Runs, Skills, Settings. Design: section 5.2.

**Read first:** `app/views/projects/show.html.erb` and every partial it
renders (`_repo_status`, code map status), `app/controllers/projects_controller.rb`,
`app/views/pipeline_tasks/index.html.erb` (the status-grouped tables you
are replacing with one filtered table), `app/views/shared/_runs_list.html.erb`,
`app/views/projects/_form.html.erb`, `app/models/project.rb`

**Changes:**

1. `projects#show` gains a `section` param (default "overview"); a tab
   row renders under the page header. Header: project name, repo chip
   (cloned / clone needed / error, from `repo_status`), Danger Mode chip
   when `skip_permissions?`, primary `Launch` button (palette with
   project preselected - the Phase A mechanism), and one `New` dropdown
   (Workflow, Task, Import workflow) replacing today's six header
   buttons. Refetch and Import Skills move into the Overview repo card.
2. Sections:
   - **Overview:** description, repo card (status + clone/refetch/import
     skills), code map card (unchanged behavior), recent runs strip
     (last 5, `run_display_name`).
   - **Workflows:** one row per workflow - name, description, step
     count, stats (from B.2 once it lands; render a placeholder note
     until then is NOT acceptable - do B.2 immediately after and wire it
     there; this item renders name/description/steps/last-run status),
     actions Run / Edit / Copy / Export / Delete.
   - **Tasks:** ONE table (title, status badge, workflow, updated) with
     a status filter chip row (server-side param) and per-row Run button
     when `task.executable?`. This replaces the five stacked
     status-grouped tables pattern for project scope; the global
     `/tasks` page is untouched.
   - **Runs:** `shared/_runs_list` scoped to the project
     (`Run.joins(workflow: :project).where(projects: {id: ...})` - check
     Run associations for the cheapest correct join).
   - **Skills:** the project's skills (name, description, used-by count)
     plus a link to the Library.
   - **Settings:** the existing project form rendered inline, plus the
     Danger-zone delete card (move it here from the edit page if A.6 put
     it there; `/projects/:id/edit` keeps working and can simply
     redirect to the settings tab).
3. Clone stops being a dead end: on the workflow show/editor page and
   anywhere a launch is blocked by `repo_status != "ready"`, render the
   actual `Clone repository` button (existing clone action) instead of a
   disabled control with a tooltip.

**Acceptance criteria:** all six tabs render with real data; header has
exactly Launch + New + tabs; a task is runnable from the Tasks tab; a
project-scoped run list exists; clone is offered inline wherever it
blocks.

**Tests:** controller tests per section (response contains the section's
marker content); a test that the Tasks tab filters by status param; the
project-scoped runs query returns only that project's runs.

**Gotchas:** the sidebar project tree links to `project_path` - default
section must render fast. Keep `@project.refresh_repo_status!` behavior
as-is (it runs on show).

## B.2 Workflow stats

**Goal:** Workflows carry run count, success rate, and median cost -
the social-proof numbers. Design: sections 5.2, 7.

**Read first:** `app/models/workflow.rb`, `app/models/run.rb` (statuses,
cost fields - find the exact column names for total cost),
`app/views/projects/` workflows section from B.1

**Changes:**

1. `Workflow#stats` returning a small struct computed from the last 20
   finished runs (statuses completed/failed/stopped): `run_count` (all
   time), `success_rate` (completed / finished, nil when no finished
   runs), `median_cost` (median of completed runs' total cost, ignoring
   nil costs). One query per workflow; no caching layer.
2. Render in the hub Workflows tab rows ("34 runs · 91% · ~$1.20",
   omitting parts that are nil) and in the workflow editor header (B.3
   consumes this).

**Acceptance criteria:** a workflow with mixed run outcomes shows correct
numbers; a never-run workflow shows "No runs yet" instead of fake zeros.

**Tests:** model test with fixture/created runs covering: no runs, all
completed, mixed, nil costs.

## B.3 Workflow editor shell - canvas + inspector

**Goal:** One editing surface: the step list is the canvas; selecting a
step edits it in an inspector panel beside the list, via Turbo Frames. No
page navigation per step. Design: section 5.3.

**Read first:** `app/views/workflows/show.html.erb`,
`app/views/steps/new.html.erb` + `edit.html.erb`,
`app/controllers/steps_controller.rb` (redirects after create/update),
the drag-reorder Stimulus controller (grep `sortable`),
`app/models/step.rb` (`available_variables_for`), `config/routes.rb`
(steps nesting)

**Changes:**

1. Workflow show becomes a two-column editor: left the steps list
   (existing rows: position badge, consumes pills, name, type badge,
   produces pills; ADD a visible drag grip glyph and keep the existing
   drag-reorder behavior), right a `turbo_frame_tag "step_inspector"`
   showing "Select a step to edit it" when empty.
2. Step row names become links targeting the `step_inspector` frame,
   loading the edit form inside it. `+ Add step` targets the same frame
   with the new form. `steps/new` and `steps/edit` views wrap their form
   in the matching frame tag; after successful create/update the
   controller redirects to the workflow page (full page - list and
   inspector both refresh). Remove per-row `Edit` links (the name is the
   link); keep per-row `Remove` buttons.
3. New steps no longer ask for Position: the controller assigns
   `workflow.steps.maximum(:position).to_i + 1` when position is absent.
   The Position field disappears from the form in B.4; this item makes
   the server default safe first.
4. Variables strip: beneath the list render every variable available at
   the end of the workflow (`Step.available_variables_for`) as
   `name (source step)` pills, globals labeled `global`. Add `data-variable`
   attributes to the strip pills AND the rows' produces/consumes pills; a
   small Stimulus controller (`variable_highlight`) toggles a highlight
   class on matching pills when a strip pill is clicked. Add a one-line
   legend: "-> produced by this step · <- injected into this step".
5. Header row per design: name, description, engine chip + access chip
   (placeholders until B.6 - render engine only if trivially readable
   from the model), stats from B.2, `Run workflow` (existing button,
   including the B.1 clone-inline behavior), and a `...` menu holding
   Edit (name/description form), Copy to project, Export, Delete.

**Acceptance criteria:** a step can be opened, edited, and saved without
leaving the page; adding a step needs no position input; drag reorder
still works and has a visible grip; clicking a variable highlights its
producers and consumers; all previous header actions remain reachable.

**Tests:** controller test asserting create-without-position assigns
max+1; a system test: open workflow, click a step name, edit its name in
the inspector, save, see the updated name in the list without a page
URL change (frame navigation), then add a step end-to-end.

**Gotchas:** the reorder endpoint renumbers 1..n - creating with max+1
composes fine. Keep `turbo_stream`/frame semantics straight: the form
must render INSIDE the frame on validation errors (status
`:unprocessable_content`) so errors appear in the inspector, not on a
bare page.

## B.4 Step inspector - per-type forms

**Goal:** The 806-line multiplexed form becomes small per-type partials
with three disclosure groups. Position dies, Shell replaces
script/command, self_review appears, type switches warn, shipped copy
bugs die. Design: section 5.3.

**Read first:** ALL of `app/views/steps/_form.html.erb` (yes, all 806
lines - you are decomposing it and must not drop a field),
`app/javascript/controllers/step_form_controller.js`,
`app/controllers/steps_controller.rb` (`build_step_config` and the four
builders, `save_as_template`), `app/views/steps/_skill_panel.html.erb`,
`_file_panel.html.erb`, `app/models/step.rb`,
`app/models/step_template.rb`, the executor ONLY at
`app/services/step_executor.rb` for the self_review config keys
(`base_ref`, `focus`) - do not modify it

**Changes:**

1. Split the form: `steps/_form.html.erb` becomes a thin shell (name,
   type select, then `render "steps/forms/#{type}"`), with per-type
   partials under `app/views/steps/forms/`: `_skill`, `_prompt`,
   `_shell`, `_ci_check`, `_context_fetch`, `_pr`, `_self_review`. Every
   existing field survives into its type's partial. Fields common to
   skill/prompt (model, effort, max turns, allowed tools, preview
   assets, schema picker, consumes table, context projects, input
   context) live in shared sub-partials.
2. Three disclosure groups (open/closed `<details>` styled to match, or
   the Phase A pattern if one emerged) inside skill/prompt:
   `Data` (open when configured), `Model & tools`, `Guards & recovery`.
   Other types get only the groups that apply (`Guards & recovery` for
   all; shell/ci/fetch/pr have no `Model & tools`). Validation errors
   render at the top of the inspector, always visible - the tab
   mechanism and its JS die with this item.
3. Type select: options Skill, Prompt, Shell, Wait for CI, Fetch
   context, Open PR, Self review - plain labels, no parentheticals. The
   Shell option's value is `command`; an existing `script` step loads as
   Shell and saves as `command` (identical behavior in the executor;
   verify `Step` validations treat both alike). `self_review` gets a
   minimal partial: base branch (`base_ref`, default `main`), focus
   instructions (`focus`, textarea), and the shared Guards group; wire a
   `build_self_review_config` in the controller.
4. Position field: removed (B.3 made the server default safe).
5. Type-switch warning: changing the type select on a PERSISTED step
   with non-empty config shows an inline warning ("Switching type clears
   this step's <old type> settings") requiring a confirm click before
   the partial swaps. New records swap freely. Keep the swap client-side
   (fields for all types are present but only the active type's partial
   is enabled/submitted - or re-fetch the form via the inspector frame
   with a `type` param, whichever is simpler given the frame from B.3;
   the frame re-fetch is cleaner and avoids the display:none multiplex
   this item exists to kill).
6. Copy fixes while decomposing: `ci_ref` default becomes
   `${branch_name}`; the allowed-tools help states the real inheritance
   ("Blank inherits the server default allowed tools"); all marketing
   register dies ("Default Brand Choice" -> "Default", "Lightning
   response" -> plain model names, "Self-Healing & Auto-Recovery" ->
   "On failure", "Allowed Tools Rule-Matcher" -> "Allowed tools",
   "Requires Manual Operator Approval" -> "Pause for approval"). Model
   ids in the model select move to a helper constant so the view stops
   hardcoding them. Submit button: "Save step".
7. `Guards & recovery` gains one new field: schema validation attempts
   (`validation_max_attempts`, number, default 3, only for skill/prompt
   with a schema) - the executor already reads it; only the form and
   `build_skill_config` marshalling are new.
8. Template capture/load survives: the save-as-template checkbox +
   name field stay in the shell; the template slide-out on `steps/new`
   keeps working. FIX the known loadTemplate gaps: restore
   `cfg.queries`, `cfg.context_projects`, `cfg.preview_assets`, and
   `on_fail.instructions` when applying a template.

**Acceptance criteria:** each of the seven types shows only its own
fields; a persisted pr step warns before switching type; a self_review
step can be created from the UI and executes (create one against a test
workflow and verify the run step starts - its executor path already
works); no marketing copy remains in step screens; every config key that
`build_step_config` previously wrote can still be written (diff the
builders' outputs before/after against a fixture of each type).

**Tests:** controller tests per type asserting round-trip of that type's
config keys (create then reload and compare config); a test that
switching a persisted step's type via update replaces config (existing
behavior, now intentional and warned); self_review create test; template
apply test covering the previously-dropped keys. System test: create a
Shell step and a Self review step through the inspector.

**Gotchas:** this is the highest-risk item in the phase. The controller
builders are the contract - decompose the VIEW, keep the PARAMS. If a
param must be renamed, update builder + view + tests together and say so
in the commit body. `_skill_panel` and `_file_panel` slide-outs are
reused as-is.

## B.5 Data wiring presentation

**Goal:** produces/consumes/queries become legible without changing
execution semantics. Design: section 5.3.

**Read first:** the consumes table + schema picker markup inside the B.4
partials you created, `app/models/step.rb`
(`available_variables_for`, `queryable_variable_schemas`),
`app/services/json_path_resolver.rb`

**Changes:**

1. Consumes table relabels: column "Inject" -> "Include value in
   prompt"; column "Query" -> "Queryable in workspace" with an
   `(advanced)` marker; the jq mention moves into a help popover/title
   on that column header ("The step's shell can extract subpaths with
   the seneschal-context CLI"), out of the primary legend.
2. Schema picker restates itself in one line when inheriting: "Using
   skill default: <variable> (<schema name>) - Change". Override keeps
   the existing select + reset. No behavior change - restyle of the
   existing three-state mechanism.
3. Outputs tag input help drops the ` ```output ` protocol details into
   a collapsed "How outputs work" disclosure (protocol text preserved
   verbatim inside it - power users need it; newcomers should not read
   `::set-output` first).

**Acceptance criteria:** the Data group reads in plain language at first
glance; every advanced detail is still present one disclosure deeper;
saved step configs are byte-identical for equivalent selections.

**Tests:** none beyond the suite passing (markup-level); update any
system test that referenced the old column labels.

## B.6 Access and engine chips

**Goal:** Pre-launch visibility of what a workflow can touch. Design:
sections 5.3, 7. Purely presentational - derived from existing config.

**Read first:** `app/models/workflow.rb` (how `runner` is stored - form
field exists, find the accessor/config key), `app/models/step.rb`,
`StepsController#build_skill_config` (the allowed-tools config key
name), `app/models/project.rb` (`skip_permissions`)

**Changes:**

1. `WorkflowAccessSummary.for(workflow)` (new small service or model
   method) returning ordered labels from: project danger mode ->
   "danger mode"; any pr step -> "opens PRs"; any shell step -> "runs
   shell"; any skill/prompt step whose allowed tools include Edit/Write
   or are blank (inherits a default containing Edit) -> "writes files";
   any manual_approval -> "approval gated". Empty list -> "read-only".
2. Render as chips in the workflow editor header (danger mode uses the
   danger tone) with a `title` listing the contributing steps; render
   compactly on hub workflow rows.
3. Engine chip: "Engine: Standard" / "Engine: Advanced SDK" from the
   workflow's runner (global default when unset - mirror the existing
   select's "currently X" logic).

**Acceptance criteria:** a workflow with a pr step + danger-mode project
shows both chips; a read-only workflow says so; chip titles name the
steps.

**Tests:** unit tests for the summary across the five conditions and the
read-only case.

## B.7 Retire the dead workflow trigger columns

**Goal:** Workflows stop carrying trigger fields that nothing uses (real
scheduling lives on PipelineTask). Design: section 9.

**Read first:** `app/models/workflow.rb` (the trigger validation),
`grep -rn "trigger_type\|trigger_config" app/ lib/ test/` - split hits
between Workflow and PipelineTask carefully (the TASK's trigger fields
are LIVE; only the WORKFLOW's are dead),
`app/services/workflow_exporter.rb` + `workflow_importer.rb` +
`app/services/data_exporter.rb`/`data_importer.rb` (they may serialize
workflow trigger fields)

**Changes:** verify every workflow row has trigger_type "manual"/nil
(`bin/rails runner` check; if ANY row differs, STOP and report). Remove
the workflow trigger validation and any exporter/importer handling of
workflow-level trigger fields (accept-and-ignore on import for backward
compatibility with old export files). Migration dropping
`workflows.trigger_type` and `workflows.trigger_config`.

**Acceptance criteria:** fresh `bin/rails db:prepare` works; export ->
import round-trip of a workflow still succeeds; an OLD export file
containing workflow trigger keys still imports (ignored).

**Tests:** importer test with a legacy payload containing
`trigger_type`; suite passes.

## B.8 Library: skills become editable in the app

**Goal:** SKILL.md editing without leaving the browser, and the import
asymmetry fix. Design: section 5.6.

**Read first:** `app/models/skill.rb` (path resolution, `body`,
frontmatter parsing, `content_hash`, `SOURCE_KINDS`),
`app/services/skill_loader.rb`, `app/services/skill_importer.rb`,
`app/services/skill_scaffolder.rb`, `app/views/skills/show.html.erb` +
`_form.html.erb`, `app/controllers/skills_controller.rb`

**Changes:**

1. Skill edit page gains a raw SKILL.md editor (the CodeJar
   `code-editor` controller used by project context) loading the full
   file (frontmatter + body). On save, the controller writes the file
   back to the skill's resolved SKILL.md path and refreshes
   `content_hash` if the model tracks one. Guardrails:
   - Refuse the save with a clear error if the frontmatter `name:`
     changed (renames require the on-disk move; keep the existing
     explainer copy).
   - Skills with `source_kind == "skill_repo"` are READ-ONLY: no editor;
     show "Synced from <repo name> - edit it in that repository. Local
     edits would be overwritten on sync."
   - The write path comes ONLY from the skill's own resolved path -
     never from a request param.
2. Show page: a "Resolves from" line naming the source tier, with the
   four-tier precedence order (project > project .seneschal > shared >
   repo) stated in its help title.
3. `SkillImporter` scans BOTH `<project>/.claude/skills` and
   `<project>/.seneschal/skills` (it currently reads only the former
   while the scaffolder writes the latter).

**Acceptance criteria:** editing a project skill's body in the app
changes what the next run's prompt loads (assert via `Skill#body`); a
repo-synced skill shows the read-only notice; import picks up a skill
placed under `.seneschal/skills`.

**Tests:** controller update test writing to a tmp-dir-backed skill
(create the file structure in setup, point the skill at it); the
name-change rejection; the repo-skill 403/redirect; an importer test for
the `.seneschal` directory.

**Gotchas:** tests must not write inside the real repo tree - use
`Dir.mktmpdir` and clean up. File writes are the item's entire point;
keep them in the controller/service layer, never in a view.

## B.9 Library: output schemas grow up

**Goal:** The schema form stops being a bare textarea; schemas show what
they expose. Design: section 5.6.

**Read first:** `app/views/json_schemas/_form.html.erb`, `show.html.erb`,
`index.html.erb`, `app/models/json_schema.rb` (the two validations),
`app/services/json_path_resolver.rb`, `app/models/skill.rb`
(`default_json_schema_id` usage)

**Changes:**

1. The body field gets the CodeJar `code-editor` treatment (JSON), plus
   a starter snippet placeholder (a small object schema with two
   properties) and the existing save-time validation errors rendered
   next to the field.
2. Show page: an "Exposes to downstream steps" list - the dotted paths
   from `JsonPathResolver.paths_for_schema` - so schema edits' blast
   radius is visible.
3. "Used by" counts (index + show) include skills referencing the schema
   as `default_json_schema_id`, labeled separately from step usage
   ("3 steps · 2 skills").

**Acceptance criteria:** invalid JSON still fails with the model's
message beside an editor (not a bare textarea); the paths list matches
the resolver's output; skill defaults are counted.

**Tests:** view/controller test for the combined used-by counts; suite
passes.

## B.10 Library: templates become a real gallery

**Goal:** Step templates get show/edit and a description - not just a
delete column. Design: section 5.6.

**Read first:** `app/models/step_template.rb` + its table in
`db/structure.sql`, `app/views/step_templates/index.html.erb`,
`app/controllers/step_templates_controller.rb`,
`StepsController#save_as_template`

**Changes:** migration adding nullable `description` to step_templates;
index becomes a card gallery (name, description, type badge, skill name
when present, timeout/retries as muted meta); add show (summary of the
captured config in plain terms) and edit (name + description only - the
config is captured from steps, not hand-edited); capture flow gains an
optional description field. Delete stays with its confirm.

**Acceptance criteria:** a template can be described, browsed, and
renamed; capture and apply flows are unchanged otherwise.

**Tests:** controller tests for edit/update; capture-with-description
test.

---

# Definition of done (every item)

1. `bin/rails test` passes.
2. `bin/rails test:system` passes.
3. `bundle exec rubocop` passes.
4. No em/en dash characters anywhere in the diff.
5. CHANGELOG.md entry added.
6. The item's acceptance criteria demonstrably hold.
7. Nothing outside the item's stated scope changed.
