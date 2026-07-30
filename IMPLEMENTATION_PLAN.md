# Seneschal Redesign - Implementation Plan

This document is a self-contained work queue for implementing the Seneschal UX +
collaboration redesign. It is written to be executed by an AI coding model one
work item at a time. Each item stands alone: goal, files to read first, exact
changes, acceptance criteria, tests, and gotchas.

## How to use this document

- Work items are ordered. Do them top to bottom unless the item says otherwise.
- One work item = one branch = one commit (or PR). Do not batch items.
- Before editing ANYTHING in an item, read every file listed under "Read first".
  Line numbers in this plan were accurate when written but may have drifted -
  trust the file contents, not the line numbers.
- If the code you find contradicts this plan (a method is missing, a column
  already exists), STOP and report the discrepancy instead of improvising.
- Do not refactor, rename, or "clean up" code outside the scope of the current
  item. Do not upgrade dependencies. Do not touch files not implicated by the
  item.

## Project context

Seneschal is a self-hosted AI pipeline orchestrator: Rails 8.1, SQLite,
Solid Queue, Hotwire (Turbo + Stimulus), Tailwind CSS v4, Propshaft, minitest.
Domain: `Project` (a git repo) has `Workflow`s (ordered `Step`s);
a `PipelineTask` (title + markdown body) feeds a workflow; executing creates a
`Run` with `RunStep`s, executed by `ExecuteRunJob` in an isolated git worktree,
streaming live to the run page via Turbo Streams.

Key facts:

- Authoritative schema is `db/structure.sql` (`config.active_record.schema_format = :sql`).
  `db/schema.rb` is stale and gets deleted in item 1.9.
- Auth: session-based, `current_user` helper in `ApplicationController`. Users
  table exists; NO domain table currently references users.
- The app shells out to the `claude` and `gh` CLIs via `Open3` with a
  per-invocation env hash (`StepExecutor#env_vars`).
- Tests: `bin/rails test`. Lint: `bin/rubocop`. Both must pass before an item
  is done.

## Hard rules (apply to every item)

1. NEVER write an em dash (U+2014) or en dash (U+2013) in any file, comment,
   or commit message. A pre-write hook rejects files containing them. Use a
   plain hyphen.
2. Match surrounding code style: comment density, naming, Ruby idiom. This
   codebase writes comments only for non-obvious constraints, never narration.
3. Every behavioral change gets a minitest test. Look at the existing tests in
   `test/` for fixtures and conventions before writing new ones.
4. Add a short entry to `CHANGELOG.md` under an `## Unreleased` heading for
   each completed item (follow the existing entry style).
5. Never modify these without an item explicitly saying so: `StepExecutor`
   internals, `app/services/runners/*`, `WorktreeManager`, `ExecuteRunJob`'s
   step-walking logic. This is the engine room and it works.
6. Commit messages: conventional style matching `git log` (`feat(scope): ...`,
   `fix(scope): ...`).

---

# PHASE 1 - Launch fast

## 1.1 Kill the draft ratchet: Save & Run

**Goal:** A task can be created and executed in one form submission, and the
Execute button no longer requires the draft > ready two-step.

**Read first:** `app/models/pipeline_task.rb`,
`app/controllers/pipeline_tasks_controller.rb`,
`app/views/pipeline_tasks/_form.html.erb`,
`app/views/pipeline_tasks/show.html.erb`

**Changes:**

1. In `PipelineTask#executable?` (currently
   `workflow.present? && status.in?(["ready", "failed"])`), change to:
   `workflow.present? && !archived? && status != "running"`.
   This makes draft, ready, failed, AND completed tasks executable (completed
   being executable is the re-run fix - see 1.2).
2. In `PipelineTasksController#execute`, before `enqueue_run!`, promote drafts:
   `@task.update!(status: "ready") if @task.status == "draft"`. Note
   `validates :workflow, presence: true, if: -> { status != "draft" }` already
   guarantees a workflow exists at that point because `executable?` checked it.
3. In the form (`_form.html.erb`), add a second submit button labeled
   "Save & Run" that submits with an extra param `run_now=1`
   (`button_tag ... name: "run_now", value: "1"`). Make it the visually
   primary button; plain "Save" (existing submit) becomes secondary.
4. In `PipelineTasksController#create`: after a successful save, if
   `params[:run_now].present? && @task.executable?`, call
   `run = @task.enqueue_run!(reason: "manual")` and
   `redirect_to run_path(run)`. If the task saved but is not executable (no
   workflow chosen), redirect to the task with an alert explaining a workflow
   is needed. Same logic in `#update`.
5. On the task show page, remove the "Mark Ready" button block entirely. Keep
   the `mark_ready` route and controller action (other things may link to it;
   removing routes is out of scope). The Execute button's render condition
   becomes `@task.executable?`.

**Acceptance criteria:**

- Creating a task with a workflow via "Save & Run" lands on a streaming run
  page in one submission.
- A draft task with a workflow shows an Execute button; clicking it starts a
  run.
- A task with no workflow shows no Execute button and "Save & Run" produces a
  clear alert, not a 500.

**Tests:** model test covering the new `executable?` truth table (draft with
workflow: true; running: false; archived: false; completed with workflow:
true; no workflow: false). Controller tests for create-with-run_now (asserts
redirect to run and a Run was created) and execute-on-draft.

**Gotchas:** `enqueue_run!` raises if `workflow` is blank - always guard with
`executable?` first. `task_params` already permits `:status`; do not expose a
status field in the form.

## 1.2 Re-run affordances everywhere

**Goal:** One click re-runs a finished task from any run page or run list. No
confirm dialog.

**Read first:** `app/views/runs/_run_header.html.erb`,
`app/views/shared/_runs_list.html.erb`, `app/views/dashboard/index.html.erb`,
`config/routes.rb` (runs + pipeline_tasks member routes)

**Changes:**

1. In `_run_header.html.erb`, for runs whose status is in
   `["completed", "failed", "stopped"]` and whose `pipeline_task` is present
   and executable, render a "Re-run" button: `button_to "Re-run",
   execute_pipeline_task_path(run.pipeline_task), method: :post` with NO
   `turbo_confirm`. Place it alongside the existing Replay / Compare buttons.
2. In `shared/_runs_list.html.erb`, add a compact Re-run button per row under
   the same conditions.

**Acceptance criteria:** after a successful run, the run page and every run
list offer a one-click Re-run that starts a fresh run and navigates to it.

**Tests:** system-level controller test: POST execute on a completed task
creates a new Run (depends on 1.1's `executable?` change).

**Gotchas:** `_runs_list.html.erb` is rendered from multiple pages including
the dashboard - keep the button markup small and defensive
(`run.pipeline_task&.executable?`).

## 1.3 Surface the workflow trigger endpoint

**Goal:** A "Run workflow" button on the workflow show page, using the
existing but UI-less `workflows#trigger` action.

**Read first:** `app/controllers/workflows_controller.rb` (the `trigger`
action - read it fully to learn its params and redirect behavior),
`app/views/workflows/show.html.erb`,
`test/controllers/workflows_controller_test.rb` (existing trigger test shows
the expected params).

**Changes:** add a `button_to "Run workflow",
trigger_project_workflow_path(@project, @workflow), method: :post` to the
workflow show header actions (Edit / Copy / Export row). No confirm. If the
trigger action requires the project repo to be `ready`, disable the button
with a tooltip when it is not.

**Acceptance criteria:** clicking Run workflow creates a run and navigates to
it (match whatever redirect the action already implements; if it does not
redirect to the run, change the action so it does).

**Tests:** extend the existing trigger controller test to assert the redirect.

## 1.4 Dashboard mission control

**Goal:** The landing page surfaces (a) runs waiting on a human, (b)
actionable tasks with Execute buttons, (c) auto-refreshing active runs.

**Read first:** `app/controllers/dashboard_controller.rb`,
`app/views/dashboard/index.html.erb`, `app/models/run.rb` (statuses + scopes),
`app/javascript/controllers/poll_status_controller.js` (existing polling
mechanism - reuse its pattern),
`app/views/shared/_runs_list.html.erb`

**Changes:**

1. `Run` model: add `scope :awaiting_approval, -> { where(status: "awaiting_approval") }`
   if it does not already exist (verify the exact status string in the model).
2. Controller: add `@awaiting_runs = Run.awaiting_approval.includes(:pipeline_task, workflow: :project).recent`.
3. View, in order from the top:
   - A "Needs you" section rendering `@awaiting_runs` prominently (distinct
     card styling, count in the heading). Each row links to the run page.
     Render nothing when empty.
   - The existing Active Runs section.
   - A "Ready to run" section rendering `@actionable_tasks` (the controller
     already queries this; the view currently ignores it). Each row: task
     title, project, workflow name, and an Execute `button_to` (no confirm)
     when `task.executable?`, else an "Edit" link.
   - Existing Recent Runs and project cards below.
4. Auto-refresh: wrap the "Needs you" + Active Runs sections in a container
   using the same Stimulus polling mechanism `poll_status_controller.js` uses
   on run rows, pointed at the dashboard path, swapping the container. Follow
   that controller's existing conventions exactly; if it is too row-specific,
   add a small `dashboard_refresh_controller.js` that fetches
   `window.location.pathname` every 5s and replaces the container's innerHTML
   with the matching element from the response. Respect
   `document.hidden` (skip polling when the tab is not visible).

**Acceptance criteria:** with a run in `awaiting_approval`, the dashboard
shows it in "Needs you" within 5 seconds without a manual refresh; actionable
tasks are launchable directly from the dashboard.

**Tests:** dashboard controller test asserting the new assigns; view test (or
controller test with `assert_select`) for the Execute button presence.

## 1.5 The Launch Bar (command palette)

**Goal:** Cmd+K (Ctrl+K on non-Mac) anywhere opens an overlay: type a task
description, pick project + workflow (pre-filled from last use), Enter, and a
run is streaming.

**Read first:** `app/views/layouts/application.html.erb`,
`app/javascript/controllers/index.js` (how controllers register),
`app/javascript/controllers/content_modal_controller.js` (existing modal
pattern), `config/importmap.rb`,
`app/controllers/pipeline_tasks_controller.rb`, `app/models/pipeline_task.rb`

**Changes:**

1. Route + controller: `post "quick_launch", to: "quick_launch#create"` and
   `get "quick_launch/options", to: "quick_launch#options"`.
   - `options` returns JSON: every project (`id`, `name`, `repo_status`) with
     its workflows (`id`, `name`). Only include projects; do not include
     archived anything.
   - `create` takes `description`, `project_id`, `workflow_id`. It builds a
     `PipelineTask`: `title` = first line of description truncated to 80
     chars, `body` = full description (if the description is a single short
     line, body and title may be identical - body must not be blank), `kind`
     = "feature", `status` = "ready", plus project + workflow. Then
     `enqueue_run!(reason: "manual")` and respond with JSON
     `{ redirect: run_path(run) }`. On validation failure return 422 with
     `{ error: messages }`.
2. Partial `app/views/shared/_command_palette.html.erb` rendered once in the
   layout: hidden overlay (fixed, centered, backdrop) containing a form with
   a textarea (autofocused when opened), project select, workflow select, and
   a submit. Style with existing Tailwind conventions from other modals.
3. Stimulus `command_palette_controller.js`:
   - Global `keydown` listener: Cmd/Ctrl+K toggles, Escape closes. Register
     the listener on `connect`, remove on `disconnect`.
   - On first open, fetch `/quick_launch/options`, populate selects, filter
     workflow options by selected project, and restore last-used
     project/workflow ids from `localStorage`
     (`seneschal.launch.project`, `seneschal.launch.workflow`).
   - Cmd/Ctrl+Enter or the submit button POSTs as JSON; on success store the
     ids in localStorage and `window.location = redirect`; on 422 show the
     error inline in the overlay.
4. Add a small visible hint in the sidebar footer: "Launch: ⌘K".

**Acceptance criteria:** from any page, Cmd+K > type "test the launch bar" >
Enter starts a run against the last-used project/workflow and navigates to it.
The overlay is keyboard-accessible (Escape closes, focus lands in the
textarea).

**Tests:** controller tests for `options` (shape) and `create` (creates task +
run, returns redirect; 422 when workflow missing).

**Gotchas:** CSRF - include the token from the meta tag in the fetch headers
(look at how `format_body_controller`/`task_suggestions_controller` already do
authenticated fetches and copy that). Do not break the existing Escape
handlers in other modals; namespace your listener.

## 1.6 Fix the task form cascade + integrity validation

**Goal:** Changing Project on the task form filters the Workflow select, and
a task can never reference a workflow from a different project.

**Read first:** `app/views/pipeline_tasks/_form.html.erb` (the select at the
`task-form#projectChanged` action - the referenced Stimulus controller does
not exist), `app/models/pipeline_task.rb`

**Changes:**

1. Create `app/javascript/controllers/task_form_controller.js` with targets
   `projectSelect` and `workflowSelect`. Render every workflow option with a
   `data-project-id` attribute in the ERB; the controller's `projectChanged`
   shows/hides options by matching project id, clears the selection if it no
   longer matches, and runs once on `connect`.
2. Register it wherever `index.js` registers controllers (follow the existing
   pattern).
3. Model validation:
   ```ruby
   validate :workflow_matches_project
   def workflow_matches_project
     return if workflow.blank? || workflow.project_id == project_id
     errors.add(:workflow, "does not belong to the selected project")
   end
   ```

**Acceptance criteria:** picking a project on `/tasks/new` narrows the
workflow list; submitting a mismatched pair (crafted request) is rejected
with a validation error.

**Tests:** model test for the validation both ways.

**Gotchas:** the workflow select currently renders all workflows globally
when no `project_id` param is present - after this item, the connect-time
filter fixes that view bug too. Confirm no fixture tasks violate the new
validation (fix fixtures if so).

## 1.7 Reserve confirm dialogs for destruction

**Goal:** Non-destructive actions stop asking "are you sure".

**Read first:** grep the views for `turbo_confirm`.

**Changes:** remove `turbo_confirm` from: Execute
(`pipeline_tasks/show.html.erb`), Refetch (`projects/show.html.erb`), Clone
(`projects/_repo_status.html.erb`), Approve (`runs/_approval_actions.html.erb`),
Resume (`runs/_run_header.html.erb`), Retry-from-here
(`runs/_run_step.html.erb`), Archive/Unarchive (task show). KEEP confirms on:
every `method: :delete` destroy, Stop (kills an in-flight run), data import,
disable 2FA, and anything mentioning Danger Mode.

**Acceptance criteria:** launching, approving, resuming, and archiving are
single-click; deleting anything still confirms.

**Tests:** none required (markup-only); run the full suite to catch system
tests that asserted confirm dialogs.

## 1.8 Remove the CDN dependency for editors

**Goal:** The app renders and the task Spec field works with no network
access.

**Read first:** `app/views/layouts/application.html.erb` (the two
`cdnjs.cloudflare.com` tags), `app/javascript/controllers/code_editor_controller.js`,
`config/importmap.rb`, `vendor/javascript/` (see what is already vendored and
how it is pinned)

**Changes:**

1. Vendor highlight.js: download the minified core build (with the languages
   the editor actually uses - check what `code_editor_controller` and
   `highlight_controller` call) into `vendor/javascript/` and pin it in the
   importmap, or place it under `app/assets` and load with
   `javascript_include_tag` - follow whichever pattern the repo already uses
   for third-party JS. Same for the highlight.js CSS theme: copy into
   `app/assets/stylesheets/` (both light and dark themes if both are
   referenced).
2. Remove the two CDN tags from the layout.
3. Defensive fallback in `code_editor_controller.js`: if `window.hljs` is
   undefined, fall back to a plain editable behavior instead of throwing
   (guard the highlight call), so the hidden `body` field still syncs and the
   form still submits.

**Acceptance criteria:** with network access blocked (or the CDN tags gone
and vendored files temporarily renamed), the task form still submits a
non-empty body. With vendored files in place, syntax highlighting works as
before.

**Tests:** none automated beyond the suite passing; verify manually per
acceptance criteria.

## 1.9 Housekeeping

**Goal:** Remove the two known landmines.

**Read first:** `config/application.rb` (confirm
`config.active_record.schema_format = :sql`), `db/structure.sql` (confirm the
`assistant_conversations` / `assistant_messages` tables exist there)

**Changes:**

1. Delete `db/schema.rb` (stale; `structure.sql` is authoritative). Verify
   nothing in `bin/`, `lib/tasks/`, or CI references it first.
2. Migration dropping the orphaned assistant tables:
   `drop_table :assistant_messages, if_exists: true` then
   `drop_table :assistant_conversations, if_exists: true` (messages first -
   FK order). These tables have no model, controller, or migration on main;
   they are debris from an unmerged branch. (The assistant feature may be
   revived later from its branch, which carries its own migrations - that
   revival is explicitly NOT part of this plan.)

**Acceptance criteria:** `bin/rails db:prepare` on a fresh database works;
full test suite passes.

---

# PHASE 2 - Who did what

## 2.1 The attribution spine

**Goal:** Tasks, workflows, and runs record which user created / started /
stopped them. Nullable everywhere - cron and branch-watch runs have no user.

**Read first:** `app/models/run.rb`, `app/models/pipeline_task.rb`
(`enqueue_run!`), `app/controllers/pipeline_tasks_controller.rb`,
`app/controllers/workflows_controller.rb` (create + trigger),
`app/controllers/runs_controller.rb` (stop), `app/jobs/cron_tick_job.rb`,
`app/jobs/branch_watch_poll_job.rb`,
`app/controllers/application_controller.rb` (`current_user`)

**Changes:**

1. Migration (all nullable, FK to users, `on_delete: :nullify`):
   - `pipeline_tasks.created_by_id`
   - `workflows.created_by_id`
   - `runs.started_by_id`, `runs.stopped_by_id`
2. Associations: `belongs_to :created_by, class_name: "User", optional: true`
   etc. On `Run`, also add a display helper:
   `def started_by_label = started_by&.email || input["trigger_reason"] || "system"`.
3. `PipelineTask#enqueue_run!` gains a keyword `started_by: nil` and writes it
   to the created run. Update the three callers: the controller `execute`
   passes `current_user`; the two jobs pass nothing (default nil).
4. Controllers set `created_by: current_user` on task and workflow create,
   and `workflows#trigger` sets `started_by: current_user` on the run it
   creates. `runs#stop` sets `stopped_by: current_user` and changes the
   hardcoded `error_message: "Stopped by user"` to
   `"Stopped by #{current_user.email}"`.
5. Display: run header shows "Started by <label>"; task show shows
   "Created by <email>" when present. Keep it to one quiet line each.

**Acceptance criteria:** a manually executed run displays the launching
user's email; a cron-fired run displays "cron"; stopping a run records who
stopped it.

**Tests:** model test for `started_by_label`; controller tests asserting
attribution is written on execute and stop.

**Gotchas:** historical rows are all NULL - every view must handle nil.
Fixtures may need a user reference for new controller tests; reuse existing
user fixtures.

## 2.2 Approval attribution and history

**Goal:** Every approve/reject is recorded as an event with actor, optional
comment, and timestamp - and history is never overwritten.

**Read first:** `app/controllers/runs_controller.rb` (`approve` and `reject` -
note approve currently nils out `rejection_context`),
`app/jobs/execute_run_job.rb` (search `rejection_context` and
`append_rejection_context` to understand how rejection feedback re-enters the
prompt - do NOT change that mechanism),
`app/views/runs/_approval_actions.html.erb`, `app/models/run_step.rb`

**Changes:**

1. New model + migration `ApprovalEvent`: `run_step_id` (FK, null: false),
   `user_id` (FK, nullable), `action` (string, "approved" or "rejected"),
   `comment` (text, nullable), timestamps. Index on `run_step_id`.
2. In `runs#approve`: create an ApprovalEvent (actor = current_user, comment
   from an optional new `comment` param) before resuming the run. STOP
   nulling `rejection_context` if that is what the code does - preserve
   whatever the job needs, but the human-readable history now lives in
   ApprovalEvents. If the job's re-injection logic requires
   `rejection_context` to be cleared on approve, keep the clear but note the
   content is already captured in the event row.
3. In `runs#reject`: create an ApprovalEvent with the rejection feedback as
   the comment, in addition to the existing `rejection_context` write (the
   job still consumes that column - leave its semantics alone).
4. UI: `_approval_actions.html.erb` gains an optional comment field on
   approve; below the actions, render the step's ApprovalEvents newest-first
   ("Approved by rick@... at 14:02", with comment if present). When a user
   hits approve on a run that is no longer awaiting, the alert should say who
   got there first (query the latest event).

**Acceptance criteria:** approving with a comment stores and displays actor +
comment; a second approver sees "Already approved by <email>"; reject
feedback still reaches the re-run prompt exactly as before.

**Tests:** controller tests for both actions asserting event creation;
regression test that reject still writes `rejection_context`.

## 2.3 The "Needs you" badge

**Goal:** The sidebar shows a live-ish count of runs awaiting approval.

**Read first:** `app/views/layouts/application.html.erb` (sidebar),
`app/helpers/application_helper.rb`

**Changes:** helper `awaiting_approval_count` returning
`Run.awaiting_approval.count`; render a small badge next to the Runs sidebar
link when the count is positive. Computed per page load is acceptable; the
dashboard polling from 1.4 covers the live case.

**Acceptance criteria:** a parked run puts a visible count in the sidebar on
the next navigation.

## 2.4 Replay permalinks

**Goal:** Any step or trajectory entry in the Replay view is addressable by
URL, and filter state survives in the URL.

**Read first:** `app/views/runs/replay.html.erb`,
`app/views/runs/_replay_step.html.erb`,
`app/views/runs/_trajectory_entry.html.erb`,
`app/javascript/controllers/replay_filter_controller.js`,
`app/javascript/controllers/clipboard_controller.js` (existing copy-to-clipboard
pattern)

**Changes:**

1. Add `id="replay_step_<run_step.id>"` to each replay step container and
   `id="entry_<run_step.id>_<index>"` to each trajectory entry (the entry
   partial receives or can receive an index - check how it is rendered and
   thread a counter through if needed).
2. Add a small copy-link button to each step header (and each entry, if the
   markup allows it cheaply) that copies
   `<current URL without hash>#<element id>` using the existing clipboard
   controller.
3. CSS: a `:target` style (subtle accent outline) so the linked element is
   visually located after navigation.
4. `replay_filter_controller.js`: on connect, read filter state from
   `URLSearchParams` (e.g. `?show=tool_use,thinking`) and apply it; on every
   toggle, write state back with `history.replaceState`. Default state (all
   on, or whatever the current default is) produces no query param.

**Acceptance criteria:** pasting a copied step link into a new tab opens the
replay scrolled to that step with it highlighted, with the same filter chips
active.

**Tests:** none required beyond suite passing; verify manually.

---

# PHASE 3 - Multiplayer

## 3.1 Outbound webhooks

**Goal:** Seneschal POSTs JSON to a configured URL when a run needs approval,
fails, completes, or parks for tokens. This is the foundation the Slack item
builds on.

**Read first:** `app/jobs/execute_run_job.rb` (find the four transitions: the
awaiting-approval park, the failure path, the completion path, and the
token-park - search for status writes), `app/models/setting.rb`,
`app/controllers/setup_controller.rb` + `app/views/setup/index.html.erb`
(where settings UI lives)

**Changes:**

1. Settings: `webhook_url` (blank = feature off) and `app_base_url` (used to
   build absolute run URLs; default to blank and omit URLs when unset). Add
   both to the Setup page form, following the existing allowed-tools setting
   pattern.
2. New job `NotifyJob` (queue: default): takes `event` (string) and `run_id`.
   Builds payload:
   ```json
   { "event": "run.awaiting_approval",
     "run": { "id": 12, "status": "...", "url": "https://.../runs/12",
              "task_title": "...", "project": "...", "workflow": "...",
              "started_by": "email-or-reason" },
     "timestamp": "iso8601" }
   ```
   POSTs it with `Net::HTTP` (5 second open/read timeouts,
   `Content-Type: application/json`). Rescue ALL errors, log, never raise -
   a notification failure must never affect a run.
3. Enqueue `NotifyJob` at the four transitions in `ExecuteRunJob` with events
   `run.awaiting_approval`, `run.failed`, `run.completed`,
   `run.waiting_for_tokens`. Guard with `Setting["webhook_url"].present?`
   before enqueueing.

**Acceptance criteria:** with a webhook URL configured (test with a local
listener), each of the four transitions produces exactly one POST; with it
blank, no jobs are enqueued.

**Tests:** job test with WebMock or a stubbed `Net::HTTP` asserting payload
shape; job test asserting errors are swallowed. Check the Gemfile for an
HTTP-stubbing gem before adding one; if none exists, stub `Net::HTTP` with
minitest mocks.

## 3.2 Slack notifications

**Goal:** Same four events posted as Slack Block Kit messages with buttons
that deep-link back to the run.

**Read first:** `NotifyJob` from 3.1.

**Changes:** setting `slack_webhook_url` (a Slack incoming-webhook URL). In
`NotifyJob`, when present, additionally POST a Block Kit payload: header line
(event + task title + project), context line (workflow, started_by), and a
button linking to the run URL (label "Review & approve" for
awaiting_approval, "View run" otherwise). Link buttons only - true
interactive Slack approve/reject requires a Slack app and a callback
endpoint, which is out of scope.

**Acceptance criteria:** an awaiting-approval run produces a Slack message
whose button opens the run page.

**Tests:** payload-shape test as in 3.1.

## 3.3 Presence on run pages

**Goal:** Run pages show who else is currently watching.

**Read first:** `app/channels/application_cable/connection.rb` (currently
empty), `app/controllers/application_controller.rb` (how the session stores
the user id - find the exact session key), `config/cable.yml`,
`app/views/runs/show.html.erb`

**Changes:**

1. `ApplicationCable::Connection`: `identified_by :current_user`, resolving
   from the session cookie (find the cookie/session mechanism the app uses -
   `cookies.encrypted` against the Rails session cookie name - and reject
   unauthenticated connections).
2. `PresenceChannel` subscribed with a run id: on subscribe, add
   `current_user.email` to a per-run set (SolidCache or an in-memory
   class-level store is fine at this scale; SolidCache survives multi-process),
   broadcast the roster to the run's stream; on unsubscribe, remove +
   broadcast.
3. Run page: an avatar strip (initials chips with email tooltips) fed by a
   small Stimulus controller subscribing to the channel.

**Acceptance criteria:** two logged-in browsers on the same run page each see
the other appear within a couple of seconds and disappear on tab close.

**Tests:** channel test for subscribe/unsubscribe roster changes.

**Gotchas:** development uses the async cable adapter (in-process only) -
presence across two terminals will not work in dev unless you run a single
server process; note this in the changelog entry. Do not let presence errors
break the existing `turbo_stream_from` on the run page.

## 3.4 Comments with mentions

**Goal:** Humans can discuss a run, a step, or a task, with @mentions that
notify.

**Read first:** `app/models/run.rb`, `run_step.rb`, `pipeline_task.rb`;
`app/views/runs/show.html.erb` + `_run_step.html.erb` (where to render);
`NotifyJob` (3.1)

**Changes:**

1. Model + migration `Comment`: `commentable` polymorphic (null: false),
   `user_id` (FK, null: false), `body` (text, null: false), optional `anchor`
   (string - a DOM id from 2.4 so a comment can point at a trajectory entry),
   timestamps. Index on `[commentable_type, commentable_id]`.
2. `CommentsController` (create + destroy only; destroy restricted to author
   or admin). Nested form partials rendered on the run page (comments on the
   run) and inside each step's details (comments on the run_step). Task show
   gets the same treatment.
3. Turbo: broadcast `append` of new comments to the run's existing stream so
   everyone watching sees them live. Render via a `comments` frame per
   commentable.
4. Mentions: after create, scan body for `@<text>` tokens; match against
   `User.email` prefixes (the part before `@` in the email, e.g.
   `@rick` matches `rick.cagle@hey.com` by prefix before the first dot or
   the full local part - implement prefix-of-local-part matching, document it
   in the model). For each match, enqueue `NotifyJob` with a
   `comment.mentioned` event including the comment body, author, and the run
   URL + anchor.
5. Markdown: render comment bodies through the same helper the app already
   uses for markdown elsewhere (find it - the runs views render markdown
   somewhere); plain text fallback is acceptable if none is shared.

**Acceptance criteria:** two browsers on a run both see a new comment live;
a mention fires a webhook/Slack notification with a working deep link.

**Tests:** model test for mention extraction; controller test for create +
authorization on destroy; broadcast test if the codebase has precedent for
one.

## 3.5 Activity feed

**Goal:** A chronological, attributed feed of what happened across the
system.

**Read first:** the models being instrumented; `app/views/dashboard/index.html.erb`

**Changes:**

1. Model + migration `Event`: `user_id` (nullable FK), `action` (string:
   `task.created`, `run.started`, `run.stopped`, `run.completed`,
   `run.failed`, `run.approved`, `run.rejected`, `workflow.created`,
   `workflow.updated`, `comment.created`), `subject` polymorphic, `metadata`
   (json, default {}), `created_at`. Index on `created_at`, and on
   `[subject_type, subject_id]`.
2. Emit events from the controller/job sites where those things happen (the
   attribution work in 2.1/2.2 already touched most of them - add
   `Event.create!` alongside). Keep creation fire-and-forget: wrap in a
   `rescue => e; Rails.logger.error(...)` so feed writes never break the
   action.
3. `/activity` page (new controller, sidebar link): paginated list (50 per
   page, `created_at desc`), each row: actor (or "system"), verb phrase,
   subject link, relative time. Filter by project via the subject's
   association where cheap; skip complex filtering otherwise.
4. Dashboard: a compact "Recent activity" card showing the latest 8 events.

**Acceptance criteria:** launching, approving, and commenting each add a
feed row attributing the acting user, visible on /activity and the
dashboard.

**Tests:** one test per instrumented site asserting the event row.

## 3.6 Per-user Connections (the credential plane)

**Goal:** Each user can store their own GitHub token and Claude credential;
runs they launch use their identity. Host-session auth remains the fallback
for everyone else and for cron/branch-watch runs.

**Read first:** `app/services/step_executor.rb` (`env_vars` and every
`Open3` spawn site - including `step_executor/pr_creator.rb` and the ci_check
path), `app/jobs/execute_run_job.rb` (how StepExecutor is constructed - the
extra env must flow from the Run to every subprocess), `app/views/account/`
+ `app/controllers/account_controller.rb`

**Changes:**

1. Encryption prerequisite: Active Record encryption must be configured. If
   `bin/rails credentials:show` lacks `active_record_encryption` keys, STOP
   and report - the operator must run `bin/rails db:encryption:init` and add
   the keys before this item can proceed. Do not generate or commit keys
   yourself.
2. Model + migration `UserCredential`: `user_id` (FK, null: false), `kind`
   (string, one of `github_token`, `anthropic_api_key`,
   `claude_oauth_token`), `value` (text, `encrypts :value`), timestamps.
   Unique index on `[user_id, kind]`.
3. Account page: a "Connections" section - one row per kind with a masked
   indicator when set ("GitHub token: set, last updated ..."), a paste field
   to set/replace, and a remove button. Include one-line help text per kind:
   GitHub wants a fine-grained PAT with pull-request and contents write on
   the target repos; Claude wants either a personal API key or the output of
   `claude setup-token` (lasts one year).
4. Env resolution: a small service `CredentialEnv.for(user)` returning a hash:
   `github_token` > `{"GH_TOKEN" => v}`; `claude_oauth_token` >
   `{"CLAUDE_CODE_OAUTH_TOKEN" => v}`; `anthropic_api_key` >
   `{"ANTHROPIC_API_KEY" => v}`. If the user set both Claude kinds, prefer
   the API key (matches the CLI's own precedence) and surface that in the
   Account UI copy. Also include `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/
   `GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL` derived from the user's email
   when a GitHub token is present.
5. Threading: `ExecuteRunJob` computes
   `CredentialEnv.for(run.started_by)` once (empty hash when started_by is
   nil or has no credentials) and passes it into StepExecutor as an
   `extra_env:` kwarg; `env_vars` merges it LAST (so it wins over context
   vars); ensure the pr_creator and ci_check `gh` spawns receive the same
   merged env - follow how they currently source env and extend minimally.
   THIS ITEM TOUCHES THE ENGINE ROOM: make the smallest possible change,
   keep the default behavior byte-identical when `extra_env` is empty, and
   do not restructure any spawn call.
6. Security invariants (enforce in code, assert in tests): only the
   launcher's credentials are ever injected; cron/branch-watch runs (nil
   started_by) get an empty overlay; credentials never appear in
   `stream_log`, `resolved_input_context`, run context, or any broadcast.

**Acceptance criteria:** a run launched by a user with a GH token creates
PRs authored by that user; a run launched by a user with no connections
behaves exactly as today; `git grep`-level review confirms tokens are only
read at the spawn seam.

**Tests:** unit tests for `CredentialEnv.for` (all kinds, both-Claude-kinds
precedence, nil user); an executor-level test asserting `extra_env` reaches
the spawned process env (there are existing StepExecutor tests - follow
their harness); a test asserting empty overlay leaves `env_vars` unchanged.

**Gotchas:** `Open3` merges the env hash over the parent process env, so an
empty overlay preserves today's host-session behavior automatically. Do not
log the overlay. The masked Account display must never round-trip the
decrypted value into HTML.

## 3.7 Read-only share links

**Goal:** A tokenized, no-login, redacted view of a run for people outside
Seneschal.

**Read first:** `app/controllers/invites_controller.rb` (the existing
public-token pattern: `skip_before_action` + token lookup),
`app/models/user.rb` (token generation), `app/views/runs/show.html.erb`
(to understand what must NOT leak)

**Changes:**

1. Model + migration `ShareLink`: `run_id` (FK), `token` (unique index,
   `SecureRandom.urlsafe_base64(32)`), `created_by_id` (FK),
   `expires_at` (datetime, default 30 days out), timestamps.
2. "Share" button on the run header (POST creates the link, flash shows the
   copyable URL); a revoke list on the same page for existing links.
3. Public controller `SharedRunsController#show` at `GET /shared/:token`:
   skips auth, 404s on unknown/expired token. Renders a PURPOSE-BUILT view -
   never reuse `runs/show` partials that render stream logs. The shared view
   shows ONLY: task title, project name, workflow name, run status, per-step
   names + statuses + durations, total cost, started/finished times. NO
   stream logs, NO tool calls, NO file contents, NO error output, NO worktree
   or repo paths, NO env, NO context variables.
4. Expired links render a friendly "link expired" page, not a 500.

**Acceptance criteria:** an incognito browser can open the share URL and see
the summary; view source contains none of the forbidden content; revoking
kills the link immediately.

**Tests:** controller tests: valid token renders, expired 404s (or renders
the expired page), revoked 404s, and an assertion that the response body
does not contain a known stream_log marker from the fixture run.

## 3.8 Assistant revival - NOT for this queue

The unmerged branch `feature/ai-application-assistant` contains a complete
conversational assistant (chat bubble + internal API + UI actions). Reviving
it means rebasing ~2,400 lines across a diverged main and re-reviewing its
auth model. This is deliberate senior-review work: DO NOT attempt it as part
of this plan. It is listed here only so nobody "helpfully" deletes the
branch.

---

# PHASE 4 - Explicitly out of scope

Do not implement any of the following as part of this plan; they are
separately-scoped future projects:

- Per-project membership, roles, or any access-control scoping
- N-of-M approvals, approval assignment, or escalation policies
- Email notifications (ActionMailer is not loaded; webhook/Slack cover v1)
- Step-form redesign beyond what an item above touches
- Any change to runners, worktrees, or the step execution model

---

# Definition of done (every item)

1. `bin/rails test` passes.
2. `bin/rubocop` passes.
3. No em dash / en dash characters anywhere in the diff.
4. CHANGELOG.md entry added.
5. The item's acceptance criteria demonstrably hold.
6. Nothing outside the item's stated scope changed.
