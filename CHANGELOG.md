# Changelog

## Unreleased - UI overhaul phase B

Authoring surfaces from `PRODUCT_REDESIGN.md`; see
`plans/PHASE_B_AUTHORING.md`.

### B.10 Templates become a real gallery

- Step templates gain a nullable `description`, asked for when capturing one.
- The index is a card gallery (name, description, type, skill, timeout and
  retries) rather than a table whose only action was Delete.
- New show and edit pages. Show explains in plain terms what a template sets
  up, including what it publishes and reads. Edit changes the name and
  description only: the configuration was captured from a step that worked, so
  it is re-captured from a step rather than hand-edited here.

### B.9 Output schemas grow up

- The schema body is a syntax-highlighted editor rather than a bare textarea,
  and a new schema starts from a small worked example instead of an empty box.
  Save-time validation errors still render beside it.
- The show page lists "Exposes to downstream steps": the dotted paths a step
  publishing this shape makes readable, so the blast radius of a schema edit
  is visible before making it.
- Used-by counts now include skills that name the schema as their default,
  counted separately from steps ("3 steps · 2 skills"), and an unreferenced
  schema says "unused" rather than "0 steps".

### B.8 Skills are editable in the app

- The skill edit page carries a raw `SKILL.md` editor covering the whole file,
  frontmatter included. Saving writes it back to disk and re-reads the cached
  frontmatter, so the next run picks up the new prompt.
- Guardrails: the destination is always the skill's own resolved path and
  never anything from the request; skills synced from a git repository are
  read-only, with a notice naming the repository, and a posted write to one is
  refused; and a change to the frontmatter `name:` is rejected, because
  renaming also moves the folder.
- The show page states which of the four resolution tiers a skill came from,
  with the precedence order in its tooltip.
- `SkillImporter` now scans both `.claude/skills` and `.seneschal/skills`. It
  only ever read the first, while the scaffolder writes to the second, so
  skills created in Seneschal were invisible to Import skills.

### B.7 Retire the dead workflow trigger columns

- `workflows.trigger_type` and `workflows.trigger_config` are dropped. No form
  set them, no job read them, and every row said "manual"; real scheduling
  lives on `PipelineTask`, whose trigger columns are untouched.
- Exporters stop writing the two keys. Importers still accept and ignore them,
  so export files written before this change keep importing - there is a test
  for exactly that.

### B.6 Access and engine chips

- New `WorkflowAccessSummary` derives, from steps that already exist, what a
  workflow can reach: "opens PRs", "runs shell", "writes files", "approval
  gated", the project's "danger mode", or "read-only" when it touches nothing.
  A step with no allowed-tools list counts as writing, because blank inherits
  a server default that contains Edit.
- The chips render on the workflow editor header and on project hub rows, each
  titled with the steps responsible. Nothing about execution changes.

### B.5 Data wiring, in plain language

Landed with B.4, since it relabels the same markup that item decomposed.

- The consumes table's columns are "Include value in prompt" and "Queryable in
  workspace (advanced)"; the `seneschal-context` and jq detail moved into that
  column's tooltip instead of leading the legend.
- Inheriting a skill's schema now reads as one line - "Using skill default:
  plan (Feature plan) Change" - rather than a badge cluster.
- The `output` block and `::set-output` protocol text is preserved verbatim
  inside a collapsed "How outputs work" disclosure, so power users keep it and
  newcomers do not read it first.

### B.4 One form per step type

- The 806-line multiplexed step form is gone. Each type renders its own
  partial under `app/views/steps/forms/`, so a Wait-for-CI step no longer
  ships hidden pull-request fields. The controller's config builders are
  unchanged, and a test per type pins every key each one writes.
- Four JavaScript tabs become three disclosure groups: **Data** (open when the
  step already wires something), **Model and tools**, and **Guards and
  recovery**. Validation errors sit at the top where they are always visible.
- Position is gone from the form; B.3 made the server append.
- Script and Command were the same behaviour under two names. The form offers
  one **Shell** type; existing script steps open and save as Shell.
- **Self review** is selectable at last. It was fully implemented in the
  executor and unreachable from the UI; it now has `base_ref` and `focus`
  fields and a `build_self_review_config`.
- Changing a saved step's type warns first and names what it will discard,
  then re-fetches the inspector for the new type.
- Templates apply on the server, so every captured key survives - including
  `queries`, `context_projects`, `preview_assets` and the reopen
  instructions, all of which the old JavaScript loader silently dropped.
- Copy fixes: the Wait-for-CI branch field defaults to `${branch_name}`, which
  is the variable a PR step actually publishes (it was `${branch}`, which
  nothing sets); the allowed-tools help says blank inherits the server default
  rather than claiming "full capability"; model ids moved to `StepsHelper`;
  and the marketing register is gone throughout.
- New field: how many times a step retries when its answer does not match the
  output shape. The executor already read `validation_max_attempts`; nothing
  could set it.

### B.3 The workflow editor: canvas and inspector

- The workflow page is now one editing surface. The step list on the left is
  the canvas; a step's name opens it in a `step_inspector` Turbo Frame on the
  right. Saving refreshes both the canvas and the inspector in place, so
  editing a step never leaves the workflow page. A direct visit to a step form
  still works and still redirects.
- Steps carry a visible drag grip; per-row Edit links are gone (the name is
  the link) and Remove stays.
- Adding a step no longer requires choosing a position: the server appends
  `max(position) + 1` whenever one is not supplied.
- A Variables strip lists everything available at the end of the workflow.
  Clicking one highlights every step that produces or consumes it, with a
  one-line legend for the arrow pills.
- The header gains the engine chip and the B.2 stats line, and collects Edit,
  Copy, Export and Delete into one menu.

### B.2 Workflow stats

- New `Workflow#stats`: total run count, success rate and median cost. Rate
  and cost come from the last 20 finished runs so one bad week long ago stops
  dragging the number down forever; cost is read from each run's step results,
  since there is no cost column.
- `workflow_stats_line` renders "34 runs · 91% succeeded · ~$1.20", dropping
  any part there is no honest number for and returning nothing at all for a
  workflow nobody has run, which the hub reports as "never run".

### B.1 Project hub

- The project page becomes a tabbed hub: Overview, Workflows, Tasks, Runs,
  Skills, Settings, chosen with a `section` param. Only the requested tab's
  data is loaded.
- The header drops from six buttons to a repo chip, a Danger-mode chip when
  the project has permissions skipped, one **New** menu (Workflow, Task,
  Import workflow) and a **Launch** button that opens the palette with this
  project chosen. Refetch and Import skills move into the Overview repo card.
- Tasks are one filterable table instead of five stacked status tables, with
  a Run button on each executable row. Runs gains a project-scoped list.
  Workflows rows carry their step count, last-run status and every action
  (Run, Edit, Copy, Export, Delete).
- Settings holds the project form plus the Danger zone. `/projects/:id/edit`
  redirects there and keeps working.
- Where a missing clone blocks running a workflow, the actual Clone button is
  offered instead of a disabled control with the reason hidden in a tooltip.

## Unreleased - UI overhaul phase A

Foundation work for the redesign in `PRODUCT_REDESIGN.md`; see
`plans/PHASE_A_FOUNDATION.md`.

### A.1 Shared component kit

- New partials under `app/views/shared/components/`: `page_header` (title,
  optional subtitle, optional actions block), `card` (optional title and
  header action, body block), `empty_state` (message plus optional CTA) and
  `chip` (five tones). Later screens compose these instead of repeating
  utility-class strings.
- New `ComponentsHelper` with `avatar_for(user, size:)` (initials circle,
  email tooltip, nil-safe) and `status_dot(status)`. `avatar_for` follows the
  same initials rule as `presence_controller.js`, so a server-rendered avatar
  and a live presence chip show the same letters.
- Activity, Runs and Tasks indexes now build their headers, cards and empty
  states from the components. No visual change intended.

### A.2 2FA management on the Account page

- The Account page gains a "Security" card showing whether two-factor
  authentication is on, with the enable link or the disable button (which
  keeps its confirmation - turning 2FA off is destructive). The two_factor
  controller and setup flow are untouched; this is a second entry point, and
  the sidebar shortcuts go away in A.3.

### A.3 Six-section navigation

- The sidebar drops from thirteen entries to Home, Runs, Projects, Library,
  Activity and an admin block. Skills, Output schemas, Templates and Skill
  repos merge into **Library**; Users, Groups, Data and Setup move under
  **Admin**; Tasks and the 2FA shortcuts lose their slots (tasks live in the
  Runs and project surfaces, 2FA on Account). No routes were removed.
- New `shared/_library_nav` and `shared/_admin_nav` tab rows carry the
  merged sections, rendered atop those index pages. The admin row renders
  nothing for non-admins, so /setup stays usable during first boot.
- New `NavigationHelper` maps a controller to its sidebar section, so a
  nested page (a workflow, a task, a schema) highlights the section it
  belongs to.
- The footer gains a real **Launch** button next to the ⌘K hint; the
  command-palette Stimulus controller now sits on `<body>` so Launch buttons
  anywhere on the page are in its scope. The account link shows the signed-in
  user's avatar.

### A.4 Vocabulary and copy pass

- `PipelineTask` is "Task" in validation messages and default form labels.
- The replay empty state no longer says "RunSteps".
- Status and type badges carry a plain-language tooltip per value
  ("awaiting approval" reads "Paused until a person approves this step"), so
  the legend lives on the badge instead of on a page nobody visits.
- The badge machinery moves out of `ApplicationHelper` into a new
  `BadgeHelper`, keeping both modules under the rubocop length limit.

### A.5 Human run names

- New `Run#ordinal` (this run's 1-based position among its task's runs) and
  `run_display_name(run)`, which reads "Add search · run 2" and falls back to
  "Manual run #47" for runs with no task.
- Run lists, the Needs-you queue and the compare picker lead with the name;
  the database id survives as a muted column on the task page, in run
  details, and in URLs.

### A.6 Dead ends

- `GET /projects/:id/workflows` was routed at a controller action and view
  that never existed, so it answered with a 500. The index route is gone;
  create still POSTs to the same path.
- Workflows can be deleted from their own page, and projects from a Danger
  zone on their edit page. Both confirms state what actually happens: the
  cascade counts, and the fact that a deleted project leaves its git
  checkout on disk.

### A.7 Server settings, and Setup slims to health checks

- New admin-only **Server settings** page at `/admin/settings` covering every
  setting that previously had to be written from a Rails console: the default
  engine, allowed tools, write confinement, the four filesystem paths and
  worktree retention, the Agent SDK sidecar's python and script paths, MCP
  servers, and the three notification keys (moved off Setup).
- Saving validates before writing: retention must be a whole number of days
  of 1 or more, and MCP servers must be a JSON object. A rejected save
  changes nothing and says why. A blank field deletes the key so its built-in
  default applies again, rather than storing an empty string.
- The three host-tool checks move into `shared/_health_checks`, rendered both
  by Server settings (as a panel) and by `/setup`, which is now just an intro,
  the checks, and Continue. Its permissions and notifications forms are gone,
  along with the two actions that backed them. The `require_setup` gate is
  unchanged.
- Admin navigation gains "Server settings"; "Setup" is now "Health checks".

### A.8 Home, mission control

- The dashboard is now "Home" and leads with a Launch button.
- Active Runs, Recent Runs and Ready-to-run collapse into a single **Runs**
  card with an Active and a Recent section. Rows carry a status dot, the run's
  human name, what step it is on, who launched it, and its cost.
- The Needs-you queue credits whoever launched each run and, when anyone has
  the run open, shows their avatars, so two people do not review the same gate
  at once.
- The Projects rail gains a per-project Launch button that opens the palette
  with that project already chosen (new `openWithProject` action).
- Empty regions use the shared empty state; the launch-palette variant of the
  component renders a Stimulus-backed button rather than a link.

## Unreleased - UX + collaboration redesign

Work in progress. Items land one at a time; see `IMPLEMENTATION_PLAN.md`.

### 3.6 Per-user Connections (the credential plane)

Runs can now execute under the identity of the person who launched them,
instead of everything going through the server's one `claude` and `gh` login.

- New `UserCredential` (`user`, `kind` of `github_token` /
  `anthropic_api_key` / `claude_oauth_token`, `encrypts :value`, unique per
  user and kind). A test asserts the token is not sitting in SQLite in
  plaintext.
- A "Connections" panel on the account page: one row per kind showing only a
  fixed mask and a character count, a paste field that is never pre-filled
  with the stored value, and a Remove button. Per-kind help text explains what
  to paste (fine-grained PAT with pull-request and contents write; a personal
  API key, or the output of `claude setup-token`).
- New `CredentialEnv.for(user)` maps stored credentials to `GH_TOKEN`,
  `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`, following each CLI's own
  documented precedence. When a user stores both Claude kinds only the API key
  is sent, so the two can never disagree about which identity is in use. A
  GitHub token also sets `GIT_AUTHOR_*` / `GIT_COMMITTER_*` from the user's
  email so their commits carry their name.
- `ExecuteRunJob` computes the overlay once per job and passes it to
  `StepExecutor` as `extra_env:`. `env_vars` merges it LAST, so a launcher's
  credential always beats a colliding run-context variable.

Engine-room note: this touches the spawn seam, and the change is deliberately
one constructor keyword and one `merge` on the final line of `env_vars`. No
spawn call was restructured. `env_vars` is the single funnel every subprocess
goes through - the skill and prompt runners via `runner_call_kwargs`, and the
`gh` calls in the pr and ci_check paths, since `PrCreator` is mixed into
`StepExecutor` rather than being a separate object with its own environment.
A test asserts an empty overlay leaves `env_vars` byte-identical to what it
produced before this existed, which is what keeps host-session auth working
untouched for everybody who does not connect anything.

Security invariants, each asserted in tests:

- Only the launcher's own credentials are ever injected, never another user's.
- Runs with no `started_by` - cron ticks and branch-watch polls - get an
  empty overlay and keep using the host session.
- Credentials never reach the run context, input, system flags, error
  message, step output, `resolved_input_context`, or `stream_log`.
- The decrypted value is never rendered into HTML.

`CredentialEnv.for` is called from exactly one place, and the credential value
is read in exactly two: that service, and `masked`, which only reads its
length.

**Deploy note:** this requires Active Record encryption. If
`bin/rails credentials:show` has no `active_record_encryption` section, run
`bin/rails db:encryption:init` and add the three keys via
`bin/rails credentials:edit` before deploying, or saving a connection will
fail.

### 3.7 Read-only share links

A run can be shown to someone outside Seneschal without giving them an
account or leaking anything.

- New `ShareLink` (`run`, nullable `created_by`, unique `token` from
  `SecureRandom.urlsafe_base64(32)`, `expires_at` defaulting to 30 days).
- A Share card on the run page mints links and lists existing ones with their
  expiry and a Revoke button.
- `GET /shared/:token` skips authentication and the setup gate. Unknown or
  revoked tokens render a 404 page; expired tokens render a friendly 410
  "link expired" page rather than a crash.
- The public view is purpose-built and reuses no `runs/` partial. It shows
  ONLY: task title, project name, workflow name, run status, per-step names,
  statuses and durations, total cost, and started / finished times. Tests
  assert the absence of stream-log markers, step output, branch names from
  output, error messages, repo and worktree paths, environment variables, and
  comments.
- `to_param` is deliberately left as the record id so an incidental
  `url_for(link)` cannot mint a shareable URL; the public path is always
  built explicitly from the token.

### 3.5 Activity feed

A chronological, attributed record of what happened across the system.

- New append-only `Event` (nullable `user`, polymorphic `subject`, `action`,
  `metadata`, `created_at` only - an event is a fact about a moment and is
  never edited). Indexed on `created_at` and on the subject.
- `Event.record` is fire-and-forget: an invalid action, a missing subject, or
  any other failure is logged and swallowed, so recording history can never
  break the action it describes. The subject association is optional, so the
  feed survives its subject being deleted afterwards.
- Instrumented at every site the attribution work already touched: task
  create (form and launch bar), run start (execute, quick launch, workflow
  trigger, retry-from-here), stop, approve, reject, workflow create and
  update, comment create, and the terminal completed / failed transitions
  inside `ExecuteRunJob`.
- New `/activity` page with a sidebar link, 50 rows per page, and
  newer/older links. A "Recent activity" card shows the latest 8 on the
  dashboard and joins the polled refresh regions.
- Rows tolerate a deleted subject, rendering "(deleted)" rather than blowing
  up the page.

Project filtering is deliberately absent: every subject type reaches its
project through a different association, so a cheap filter is not available
without denormalizing a `project_id` onto Event. Noted rather than half-built.

The new view helpers live in their own `ActivityHelper` and `CommentsHelper`
modules rather than growing `ApplicationHelper` past its length budget.

### 3.4 Comments with mentions

Humans can now talk about a run, a step, or a task, in the app rather than
around it.

- New polymorphic `Comment` (`commentable`, `user`, `body`, optional `anchor`
  pointing at a Replay DOM id from 2.4). `commentable_type` is validated
  against an allowlist and the controller refuses anything outside it, so a
  crafted request cannot reach an arbitrary model through the polymorphic
  association.
- `CommentsController` handles create and destroy only; destroy is restricted
  to the author or an admin.
- Threads render on the run page, inside each step's collapsible
  "discussion", and on the task page. A step thread stamps the comment with
  that step's replay anchor automatically.
- New comments broadcast an append to the run's existing Turbo stream, so
  everyone watching sees them without a refresh. Broadcast failures are caught
  and logged.
- `@mention` matching is deliberately narrow and documented on the model: a
  token matches a user when it equals the whole local part of their email or
  that local part's first `.`/`_`/`-` delimited segment. So `@rick` reaches
  `rick@` and `rick.cagle@`, but `@dan` does not reach `dana@`. Self-mentions
  are ignored. Each match enqueues `NotifyJob` with a `comment.mentioned`
  event carrying the author, body, and replay anchor; `NotifyJob` deep-links
  the Slack button straight to the anchor.
- Comment bodies are HTML-escaped and then have their mention tokens tinted.
  There is no shared markdown renderer in this app (the markdown Stimulus
  controller only syntax-highlights source), so comments are plain text.

### 3.3 Presence on run pages

Run pages now show who else is looking at them.

- `ApplicationCable::Connection` is no longer empty: it is `identified_by
  :current_user`, resolved from the same encrypted session cookie the HTTP side
  reads, and rejects unauthenticated connections.
- New `RunPresence` service keeps a per-run viewer roster in the Rails cache
  (SolidCache in production), so it survives more than one web worker. Viewers
  are reference-counted, so closing one of two tabs does not evict the person.
- New `PresenceChannel` joins on subscribe, leaves on unsubscribe, and
  broadcasts the roster on its own `presence:run:<id>` stream. Deliberately not
  the run's Turbo stream, which carries HTML fragments.
- New `presence_controller.js` renders initials chips with email tooltips. Any
  failure is swallowed: presence is decoration and must never take down the run
  page or its existing Turbo stream. `@rails/actioncable` is pinned in the
  importmap (served by the actioncable gem, nothing vendored).

Two environment notes:

- Development uses the async cable adapter, which is in-process only, so
  presence across two separately-started servers will not work in dev.
- The test environment uses the `test` cable adapter, which collects broadcasts
  for `assert_broadcast_on` but never delivers them to a real websocket client.
  The roster therefore cannot be asserted in a browser test; `RunPresence` and
  `PresenceChannel` carry that coverage, and the system test only proves the
  strip mounts.
- `config.cache_store` in the test environment moved from `:null_store` to
  `:memory_store`, since a null store makes cache-backed behavior untestable.
  Nothing else in the app used `Rails.cache`.

### 3.2 Slack notifications

New `slack_webhook_url` setting. When present, `NotifyJob` also posts a Block
Kit message for the same four events: a header naming the event and task, a
section with project and run status, a context line with workflow and who
started it, and a button linking back to the run ("Review & approve" for an
approval gate, "View run" otherwise). The button block is omitted entirely
when no `app_base_url` is configured.

The two destinations are delivered independently with separate rescues, so a
broken generic webhook cannot cost the Slack message or vice versa.

Link buttons only. True interactive approve/reject in Slack needs a Slack app
and a signed callback endpoint, which is out of scope.

### 3.1 Outbound webhooks

Seneschal can now tell something outside itself that a run needs attention.

- Two settings on the Setup page: `webhook_url` (blank turns the feature off
  completely, and nothing is enqueued) and `app_base_url` (used to build
  absolute run links; blank means the payload omits the URL rather than
  guessing a host).
- New `NotifyJob` POSTs `{ event, run: { id, status, url, task_title, project,
  workflow, started_by }, timestamp }` with 5 second open and read timeouts.
  Every error is caught and logged: a notification failure can never affect a
  run, including a malformed URL, a refused connection, or a deleted run.
- `ExecuteRunJob` enqueues it at six terminal transitions covering four events:
  `run.awaiting_approval`, `run.completed`, `run.waiting_for_tokens`, and
  `run.failed` (from a missing repo, a failed worktree allocation, or a failed
  step). The enqueue itself is guarded and rescued.

Test note: this project has no HTTP-stubbing gem and minitest 6 no longer ships
`minitest/mock`, so the job test swaps `Net::HTTP.new` for a recording double
around each example.

### 2.4 Replay permalinks

Anything in a Replay is now addressable, so a run can be discussed by URL.

- Every step card carries `id="replay_step_<id>"`; every trajectory entry
  carries `id="entry_<run_step_id>_<index>"`. Entries rendered inside the
  Compare view stay unanchored (they are not individually addressable there).
- A "Link" button on each step header, and on each entry on hover, copies the
  full URL to that element. New `permalink_controller.js` builds it from the
  live location so the current query string rides along.
- `replay_filter_controller.js` round-trips chip state through a `show` query
  param via `history.replaceState`. The default set produces no param at all,
  so ordinary URLs stay clean, and the defaults are read off the rendered
  checkboxes rather than duplicated in JS.
- A `:target` outline marks whichever element the URL pointed at.

### 2.3 The needs-you badge

`awaiting_approval_count` helper plus a warning-coloured count next to the Runs
link in the sidebar, shown only when something is actually parked. Computed per
page load; the dashboard polling from 1.4 covers the live case.

### 2.2 Approval attribution and history

New `ApprovalEvent` model (`run_step`, nullable `user`, `action`, optional
`comment`, timestamps) recording every approve and reject decision. It is
append-only: nothing overwrites an earlier decision.

- Approve gained an optional note field beside the button.
- Reject stores its feedback as the event comment as well as in
  `RunStep#rejection_context`. That column's semantics are untouched, because
  `ExecuteRunJob` keys prompt re-injection off it and clears it on consumption;
  the durable human-readable record now lives in the event row.
- Decision history renders newest-first under the approval panel for the parked
  step, and under every other step that has events, so it survives the approval.
- A second approver arriving at a decided run now gets "Already approved by
  <email>." instead of a bare "Run is not awaiting approval."

### 2.1 The attribution spine

Until now no domain table referenced a user, so nothing recorded who did what.
Migration `20260724160000_add_attribution_columns` adds four nullable foreign
keys, all `on_delete: :nullify` so removing a user never takes history with it:

- `pipeline_tasks.created_by_id`
- `workflows.created_by_id`
- `runs.started_by_id`, `runs.stopped_by_id`

`PipelineTask#enqueue_run!` takes a `started_by:` keyword (default nil), so the
cron and branch-watch callers keep behaving exactly as before while the manual
paths pass `current_user`. Attribution is now written on task create, workflow
create, task execute, quick launch, workflow trigger, retry-from-here, and
stop; `runs#stop` records the actor and its `error_message` names them instead
of saying "Stopped by user".

`Run#started_by_label` renders the launching user's email, falling back to the
run's trigger reason ("cron", "branch_update") and then to "system" for
historical rows. The run header shows it under the title; the task page shows
"Created ... by <email>" when known.

### 1.9 Housekeeping

Two landmines removed.

- Deleted `db/schema.rb`. The app runs `config.active_record.schema_format = :sql`,
  so `db/structure.sql` is authoritative; the Ruby schema had been frozen at
  `2026_04_13_025821` while migrations ran through `2026_05_24`, and reading
  it gave a wrong picture of the database. Nothing in `bin/`, `lib/tasks/`, or
  CI referenced it.
- Migration `20260724152000_drop_orphaned_assistant_tables` drops
  `assistant_messages` and then `assistant_conversations`. Those tables were in
  `structure.sql` with no model, controller, or migration on main - debris from
  the unmerged `feature/ai-application-assistant` branch, which carries its own
  migrations if that work is ever revived. The migration is irreversible; any
  rows in an existing database are deleted (confirmed as intended by the
  operator before running).

### 1.5 follow-up: launch bar fixes found in the browser

A headless-Chrome test of the launch bar (`test/system/launch_bar_test.rb`)
turned up a real defect: the launch POST read
`document.querySelector('meta[name="csrf-token"]').content` unguarded, so on
any install where forgery protection is off Rails emits no meta tag and the
palette died with "Cannot read properties of null". The header is now sent
only when a token exists.

### 1.8 No CDN dependency

The layout pulled highlight.js and its two themes from cdnjs on every page
load, so an air-gapped or offline install rendered an unhighlighted, partly
broken editor. All three files are now vendored at the same version
(11.11.1, byte-identical to the cdnjs build, BSD-3-Clause):

- `vendor/javascript/highlight.min.js`
- `app/assets/stylesheets/highlight-github-dark.css`
- `app/assets/stylesheets/highlight-github.css`

The layout emits digest-stamped `asset_path` URLs, and `theme_toggle_controller`
takes the two theme paths as Stimulus values instead of hardcoding CDN URLs.
Every `window.hljs` call site is now guarded, so a missing highlighter degrades
to a plain editable field that still syncs and submits rather than throwing.

Also repaired two system tests that clicked the Rails default submit labels
("Create Pipeline task" / "Update Pipeline task"), renamed by item 1.1. System
tests do not run under `bin/rails test`, so run `bin/rails test:system` too.

### 1.7 Confirm dialogs are for destruction only

Dropped `turbo_confirm` from Execute, Archive, Clone Repository, Refetch,
Approve, Resume, and Retry-from-here. Kept it on every destroy, on Stop
(which kills an in-flight run), on Disable 2FA, on the data import that wipes
the database, and on replacing a skill's default schema.

Note: Refetch resets the primary clone to `origin/HEAD`, so it can discard
uncommitted work in `project.local_path`. Since runs execute in per-run
worktrees the primary clone is effectively a cache, which is why this one lost
its confirm along with the rest.

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
