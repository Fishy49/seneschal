# UI Overhaul Phase A - Foundation

Component kit, navigation IA, vocabulary, settings UI, and the new Home.
Design source: `PRODUCT_REDESIGN.md` sections 3, 4, 5.1, 5.7, 8. Read the
design doc's section before starting an item when one is cited.

## How to use this document

- Work items are ordered. Do them top to bottom.
- One work item = one commit on the phase branch (`feat/ui-phase-a`).
  Do not batch items.
- Before editing ANYTHING in an item, read every file under "Read first".
  Trust file contents over this plan's descriptions - the plan was written
  against a July 2026 snapshot and details may have drifted.
- If the code contradicts this plan (a method is missing, a partial is
  already there, an association behaves differently than stated), STOP and
  report the discrepancy instead of improvising.
- Do not refactor or "clean up" outside the current item's scope. Do not
  upgrade dependencies.

## Project context

Seneschal: self-hosted AI pipeline orchestrator. Rails 8.1, SQLite,
Solid Queue, Hotwire (Turbo + Stimulus, importmap, controllers eager-loaded
via `pin_all_from`), Tailwind CSS v4 (design tokens in
`app/assets/tailwind/application.css`: `--color-surface`,
`--color-surface-card`, `--color-surface-input`, `--color-edge`,
`--color-content`, `--color-content-muted`, `--color-accent`,
`--color-success`, `--color-warning`, `--color-danger`, `--color-info`),
Propshaft, minitest. Authoritative schema: `db/structure.sql`
(`schema_format = :sql`).

Domain: `Project` (git repo) has `Workflow`s (ordered `Step`s); a
`PipelineTask` feeds a workflow; executing creates a `Run` with `RunStep`s
via `ExecuteRunJob` in a git worktree, streaming to the run page over Turbo
Streams. Collaboration layer (already on main): attribution columns
(`created_by`/`started_by`/`stopped_by`), `ApprovalEvent`, `Comment`,
`Event` + activity feed, `PresenceChannel` + `RunPresence`, `ShareLink`,
`UserCredential` + `CredentialEnv`, command palette
(`shared/_command_palette.html.erb` + `command_palette_controller.js`),
dashboard auto-refresh (`dashboard_refresh_controller.js`).

## Hard rules (every item)

1. NEVER write an em dash (U+2014) or en dash (U+2013) anywhere - files,
   comments, commit messages. A pre-write hook rejects files containing
   them. Use a plain hyphen.
2. Match surrounding code style. Comments only for non-obvious
   constraints, never narration.
3. Every behavioral change gets a minitest test. Follow existing fixtures
   and conventions in `test/`.
4. Add a `CHANGELOG.md` entry per item under
   `## Unreleased - UI overhaul phase A`.
5. NEVER modify: `StepExecutor` internals, `app/services/runners/*`,
   `WorktreeManager`, `ExecuteRunJob`'s step-walking logic. Nothing in
   this phase needs the engine room.
6. Conventional commits matching `git log` style
   (`feat(scope): ...`, `fix(scope): ...`).

## Harness notes (learned the hard way - do not rediscover these)

- Lint is `bundle exec rubocop`. There is NO `bin/rubocop`.
- `bin/rails test` does NOT run system tests. Run `bin/rails test:system`
  separately (Capybara + headless Chrome). Both must pass per item; UI
  items routinely break system tests that click on renamed labels.
- minitest 6: `require "minitest/mock"` raises LoadError. No WebMock. Stub
  with `define_singleton_method` and restore in `ensure` (see
  `test/jobs/notify_job_test.rb` for the pattern).
- No rails-controller-testing gem: `assigns` is unavailable. Assert on
  response markup instead.
- Fixtures: `users(:admin)` (admin), `users(:other)` (member). Test cache
  store is `:memory_store` on purpose (PresenceChannel needs it). Test
  cable adapter is `test` - presence is not assertable in system tests.
- Confirm-dialog convention: `turbo_confirm` ONLY on destructive actions
  (deletes, Stop, data import, disable 2FA). Never on launch/approve/etc.

---

## A.1 Shared component kit

**Goal:** The ~10 recurring UI patterns become shared partials/helpers so
later items compose screens instead of copy-pasting utility strings.
Design: `PRODUCT_REDESIGN.md` section 8.

**Read first:** `app/views/layouts/application.html.erb`,
`app/views/dashboard/index.html.erb`, `app/views/activity/index.html.erb`,
`app/views/runs/index.html.erb`, `app/views/pipeline_tasks/index.html.erb`,
`app/helpers/application_helper.rb` (`status_badge`, `type_badge`),
`app/views/runs/_presence.html.erb` or wherever presence initials chips
render (grep `initials`), `app/views/shared/_runs_list.html.erb`

**Changes:**

1. Create partials under `app/views/shared/components/`:
   - `_page_header.html.erb` - locals `title:`, optional `subtitle:`;
     rendered with `render layout:` so callers pass an actions block
     (right-aligned).
   - `_card.html.erb` - locals optional `title:`, optional `action:`
     (`{label:, path:}` rendered as the small accent link in the header
     row); body via `render layout:` block. Match the current card look
     (surface-card background, edge border, rounded-lg, existing padding).
   - `_empty_state.html.erb` - locals `message:`, optional `cta_label:` +
     `cta_path:`.
   - `_chip.html.erb` - locals `text:`, `tone:` in
     `[:neutral, :accent, :ok, :warn, :danger]`.
2. Helpers in `ApplicationHelper` (or a new `ComponentsHelper` if
   ApplicationHelper is near its rubocop length limit - it was split once
   already):
   - `avatar_for(user, size: :sm)` - initials circle with the user's email
     as `title` tooltip. Reuse the presence chip styling; nil user renders
     nothing.
   - `status_dot(status)` - small colored dot span; running/streaming get
     info color, completed success, failed danger, awaiting_approval and
     waiting_for_tokens warning, everything else muted.
3. Convert three simple screens as the proving ground: page headers and
   outer cards of `/activity`, `/runs`, and `/tasks` indexes now use the
   components. Visual output should be near-identical; this item is
   structural.

**Acceptance criteria:** the three converted pages render as before;
components exist and are the documented way to build screens in later
items.

**Tests:** helper tests for `avatar_for` (initials, tooltip, nil) and
`status_dot` mapping. Full suite + system suite pass.

**Gotchas:** `render layout:` partial blocks use `<%= yield %>` inside the
partial. Keep component markup theme-token based (`bg-surface-card`,
`border-edge`, `text-content-muted`) - never raw hex.

## A.2 2FA management moves onto the Account page

**Goal:** Account is the one place for identity: profile, connections,
and 2FA. (The sidebar 2FA links are removed in A.3 - this item must land
first so the destination exists before the shortcut disappears.)

**Read first:** `app/views/account/edit.html.erb`,
`app/views/account/_connections.html.erb`,
`app/controllers/two_factor_controller.rb` + its routes in
`config/routes.rb`, `app/views/two_factor/setup.html.erb`

**Changes:** add a "Security" card to the Account page: shows whether 2FA
is enabled; when disabled, a link "Enable two-factor authentication" to
the existing setup path; when enabled, the existing disable button (KEEP
its `turbo_confirm` - disabling 2FA is security-destructive). Do not
change the two_factor controller or setup flow.

**Acceptance criteria:** both 2FA states render correctly on `/account`;
enable/disable flows work as before from the new entry point.

**Tests:** controller/view test asserting the Security card renders in
both states (toggle via the user fixture's otp fields - read
`app/models/user.rb` for the enabled predicate).

## A.3 Navigation IA - the six-item sidebar

**Goal:** Sidebar goes from 13 items to Home, Runs, Projects, Library,
Activity, Admin, plus a Launch button and an account footer. Design:
`PRODUCT_REDESIGN.md` section 4.1.

**Read first:** `app/views/layouts/application.html.erb` (entire sidebar),
`app/javascript/controllers/command_palette_controller.js` (how the
palette opens - you will add a click entry point),
`app/helpers/application_helper.rb` (`awaiting_approval_count`),
`config/routes.rb`

**Changes:**

1. Sidebar top section: `Home` (root), `Runs` (+ existing needs-you
   badge), `Projects` (+ existing disclosure tree, unchanged), `Library`
   (links to `skills_path`), `Activity`.
2. Admin section (render only for `current_user.admin?` - grep how admin
   gating is checked today and reuse it): heading rule + `Admin` links:
   Users, Groups, Data, Setup. (Setup is renamed/absorbed by A.7; leave
   the label "Setup" for now.)
3. Footer: a real `Launch  ⌘K` button that opens the command palette on
   click. Add an explicit `open` action to `command_palette_controller.js`
   if only the keydown path exists; wire via `data-action`. Below it: the
   account link becomes `avatar_for(current_user)` + email; theme toggle
   stays. REMOVE from the sidebar: Groups, Tasks, Skills, Skill Repos,
   Schemas, Templates, Users, Data, Setup, Enable/Disable 2FA (all now
   reachable via Library/Admin/Account).
4. Sub-navigation partials:
   - `app/views/shared/_library_nav.html.erb` - tab row: Skills, Output
     schemas, Templates, and (admin only) Skill repos, linking to the
     existing `skills_path`, `json_schemas_path`, `step_templates_path`,
     `skill_repos_path`. Render it at the top of those four index views.
   - `app/views/shared/_admin_nav.html.erb` - Users, Groups, Data, Setup;
     render atop those index/show views.
5. Active-state helper `nav_section` returning one of
   `[:home, :runs, :projects, :library, :activity, :admin]` from
   `controller_name`/`controller_path`, used to highlight the sidebar
   item. Skills/json_schemas/step_templates/skill_repos map to `:library`;
   users/project_groups/data/setup to `:admin`; pipeline_tasks maps to
   `:projects` (tasks lost their top-level slot but pages still exist).

**Acceptance criteria:** every page previously reachable is still
reachable through Home/Runs/Projects/Library/Activity/Admin/Account; the
sidebar shows exactly the six sections plus footer; clicking Launch opens
the palette; the correct section highlights on each page.

**Tests:** a layout-level integration test asserting the sidebar contains
the six links and does NOT contain "Skill Repos" or "Schemas" as
top-level links; palette-open covered by adjusting the existing launch
system test to click the button.

**Gotchas:** system tests navigate via sidebar link text - expect several
to need updated selectors; run `bin/rails test:system` and fix them as
part of this item. Do not remove any routes.

## A.4 Vocabulary and copy pass

**Goal:** One plain, terse voice; human words for model names. Design:
`PRODUCT_REDESIGN.md` sections 4.2, 4.3. (Step-form copy is EXCLUDED -
Phase B rebuilds that form entirely.)

**Read first:** `config/locales/en.yml`,
`app/views/runs/replay.html.erb` (the "RunSteps" string),
`app/helpers/application_helper.rb` (`status_badge`, `type_badge`),
grep views for `Pipeline task`, `Pipeline Task`, `RunSteps`

**Changes:**

1. Locale: set `activerecord.models.pipeline_task` to "Task" so
   validation messages and default submit labels say Task.
2. Fix the replay empty state to "This run has no steps yet."
3. `status_badge` and `type_badge` gain `title` tooltips with a
   plain-language gloss per value (e.g. `awaiting_approval` -> "Paused
   until a person approves this step", `ci_check` -> "Waits for GitHub
   checks"). This is the badge legend - inline, not a separate page.
4. Every visible "Diff" label for the run comparison view becomes
   "Compare" (route helpers stay `diff_run_path`; label only).
5. Sweep remaining user-facing "Pipeline task" strings to "Task".

**Acceptance criteria:** no user-visible "RunSteps" or "Pipeline task"
strings remain (`git grep` the views); badges carry tooltips.

**Tests:** suite passes (validation-message assertions may need
updating); one test asserting a badge renders its title attribute.

## A.5 Human run names

**Goal:** Runs are named "<task title> · run N" everywhere in lists; the
database id retires to detail surfaces. Design: section 4.2. (The run
page header itself is Phase C - this item covers lists and pickers.)

**Read first:** `app/models/run.rb`, `app/views/shared/_runs_list.html.erb`,
`app/views/dashboard/_awaiting_runs.html.erb` and the dashboard run
partials, `app/views/pipeline_tasks/show.html.erb` (runs table),
`app/views/runs/diff.html.erb` (the compare `<select>` options)

**Changes:**

1. `Run#ordinal` - this run's 1-based position among its task's runs by
   id (`pipeline_task.runs.where(id: ..id).count`); returns nil when
   `pipeline_task` is nil.
2. Helper `run_display_name(run)`: with a task,
   `"#{task.title} · run #{ordinal}"`; without, `"Manual run ##{id}"`.
3. Adopt in `shared/_runs_list`, the dashboard run rows, the task show
   runs table (keep a small muted `#id` column there - it is the detail
   surface), and the compare select options, which become
   `"run 2 · completed · 3 days ago"` (use `time_ago_in_words`).

**Acceptance criteria:** run lists lead with task titles; the compare
picker is human-readable; task-less runs (workflow trigger) still render.

**Tests:** model test for `ordinal` (first and second run of a task,
task-less run); helper test for both branches.

**Gotchas:** `ordinal` is one COUNT query per row. Fine at self-hosted
scale; do not build a caching layer for it.

## A.6 Dead ends: the missing index and the missing deletes

**Goal:** No routed 500s, and projects/workflows can be deleted from the
UI. Design: section 9.

**Read first:** `config/routes.rb` (the nested `resources :workflows`
block), `app/controllers/workflows_controller.rb`,
`app/models/workflow.rb` and `app/models/project.rb` (read the `has_many`
`dependent:` options CAREFULLY - the confirm copy below must state what
actually happens), `app/controllers/projects_controller.rb#destroy`
(check whether it touches the filesystem - if it deletes `local_path`,
STOP and report before wiring any button),
`app/views/workflows/show.html.erb`, `app/views/projects/edit.html.erb`

**Changes:**

1. Routes: `resources :workflows, except: [:index]` (there is no index
   action or view; verify nothing links `project_workflows_path` first).
2. Workflow show: add a `Delete` button (method delete, `turbo_confirm`)
   whose confirm text states the real cascade behavior found in the
   model. Redirect to the project on success.
3. Project edit: add a "Danger zone" card at the bottom with a Delete
   button (`turbo_confirm` naming the project and stating the real
   cascade). Redirect to projects index.

**Acceptance criteria:** deleting a workflow and a project each work from
the UI with an honest confirm; `GET /projects/:id/workflows` is no longer
a routable path.

**Tests:** controller destroy tests for both (if absent), asserting the
redirect and record removal.

## A.7 Admin server settings, and Setup slims to health checks

**Goal:** Every real setting has a form; the setup page becomes a health
panel. Design: section 5.7. The 11 console-only keys: `default_runner`,
`skills_global_roots`, `skill_repo_root`, `worktree_root`,
`worktree_retention_days`, `run_assets_root`, `mcp_servers`,
`confine_writes_to_cwd`, `python_bin`, `sdk_runner_script` (plus legacy
`skills_global_root` - display-only note, do not add a field for it).

**Read first:** `app/models/setting.rb`,
`app/views/setup/index.html.erb` (all of it - note the misnested `</div>`
around the Permissions card), `app/controllers/setup_controller.rb`,
grep `Setting[` across `app/` to confirm each key's consumer and expected
format before writing its form field, and how admin-only controllers gate
access (`app/controllers/users_controller.rb`)

**Changes:**

1. New admin-gated controller + view at `GET/PATCH /admin/settings`
   ("Server settings"): sections Execution defaults (`default_runner`
   select with plain labels "Standard (Claude CLI)" / "Advanced (Agent
   SDK)", `default_allowed_tools`, `confine_writes_to_cwd` checkbox),
   Paths (`skills_global_roots` textarea, `skill_repo_root`,
   `worktree_root`, `worktree_retention_days` number,
   `run_assets_root`), SDK sidecar (`python_bin`, `sdk_runner_script`),
   Notifications (`webhook_url`, `slack_webhook_url`, `app_base_url` -
   moved here from Setup), and MCP servers (textarea; on save, reject
   invalid JSON with an inline error; blank clears the key).
2. Validate before writing: `worktree_retention_days` must be a positive
   integer; `mcp_servers` must be blank or valid JSON. Everything else is
   free text (the consumers tolerate it today).
3. Extract the three CLI check cards into a shared partial rendered by
   BOTH the settings page (top, as a health panel) and `/setup`. Rebuild
   `setup/index.html.erb` as: intro + checks partial + Continue button.
   This removes the Permissions and Notifications forms from Setup and
   fixes the misnested div by replacement. The `require_setup` gate logic
   is unchanged.
4. Admin sub-nav (A.3) gains "Server settings"; its "Setup" link becomes
   "Health checks" pointing at `/setup`.

**Acceptance criteria:** every listed key is editable by an admin and
takes effect (spot-check `default_runner` by reading its consumer);
non-admins get a redirect; Setup still gates a fresh install and still
verifies CLIs; invalid MCP JSON is rejected with a message, not saved.

**Tests:** controller tests - admin required; each section saves; bad
JSON and bad integer rejected; blank clears. A setup-page test asserting
the forms moved (no `default_allowed_tools` field on `/setup`).

**Gotchas:** `Setting` values are strings; keep `to_s` semantics. Do not
add a key whitelist to the model - out of scope. Never render a setting
value into a log message.

## A.8 Home - mission control

**Goal:** One Runs module instead of three overlapping lists; people
visible everywhere; Launch as the primary action. Design: section 5.1.

**Read first:** `app/views/dashboard/index.html.erb` and every partial it
renders, `app/controllers/dashboard_controller.rb`,
`app/javascript/controllers/dashboard_refresh_controller.js` (region
mechanism - it swaps elements by id; your new regions must keep ids in
sync with what the controller expects),
`app/services/run_presence.rb` (roster reads),
`app/javascript/controllers/command_palette_controller.js`

**Changes:**

1. Page header "Home" with a primary `Launch` button (palette open, as in
   A.3).
2. Keep the "Needs you" banner region; each row adds "launched by <name>"
   (use `started_by_label`) and, when `RunPresence` reports viewers, an
   avatar strip of who is looking at it.
3. Replace Active Runs + Recent Runs + Ready to run with ONE Runs card
   (component from A.1): an Active section (running/streaming/awaiting
   runs with current-step progress text) and a Recent section (last ~8
   finished), rows using `status_dot`, `run_display_name`,
   `avatar_for(run.started_by)`, and cost. "View all" -> `runs_path`.
4. Right rail: Projects card - name, workflow/task counts, and a
   `Launch` button per project that opens the palette with that project
   preselected (pass the project id via a data attribute; extend the
   palette controller with an `openWithProject` action that sets the
   project select and triggers its change handler so workflow filtering
   applies). Below it, the Recent activity card (existing partial,
   latest 5).
5. Update `dashboard_controller.rb` assigns to match (merge the run
   queries; drop actionable-tasks unless the empty state needs it).
   Keep the auto-refresh regions working: adjust the region ids/targets
   together with the JS controller if the region count changes.
6. Empty states use the `empty_state` component ("No runs yet" -> Launch;
   "No projects yet" -> New Project). The full onboarding checklist is
   Phase D - leave a plain empty state here.

**Acceptance criteria:** dashboard shows Needs you + one Runs card +
Projects + Activity; auto-refresh still updates Needs you and Active
within ~5s; per-project Launch opens a prefiltered palette; no duplicate
run lists remain.

**Tests:** update the existing dashboard controller/view tests to the new
structure (they assert on old markup and WILL fail); add an assertion
that a run row contains the launcher's avatar title. Run the system suite
- the dashboard and launch system tests interact with this page.

---

# Definition of done (every item)

1. `bin/rails test` passes.
2. `bin/rails test:system` passes.
3. `bundle exec rubocop` passes.
4. No em/en dash characters anywhere in the diff.
5. CHANGELOG.md entry added.
6. The item's acceptance criteria demonstrably hold.
7. Nothing outside the item's stated scope changed.
