# UI Overhaul Phase C - Runs and Launching

The run page becomes one collaboration surface with three modes; the task
form becomes a launch composer. Design source: `PRODUCT_REDESIGN.md`
sections 5.4, 5.5. Requires Phase A (components, run naming); B.2/B.6
(stats, access chips) are consumed by C.3/C.4 - if Phase B has not
merged, STOP and report rather than stubbing them.

## How to use this document

- Work items are ordered; one item = one commit on `feat/ui-phase-c`.
- Read every "Read first" file before editing. Trust code over plan.
- If the code contradicts this plan, STOP and report.

## Hard rules (every item)

1. NEVER write an em dash (U+2014) or en dash (U+2013) anywhere. Plain
   hyphens only. A pre-write hook enforces this.
2. Match surrounding code style; comments only for non-obvious
   constraints.
3. Every behavioral change gets a minitest test.
4. CHANGELOG.md entry per item under `## Unreleased - UI overhaul phase C`.
5. NEVER modify: `StepExecutor` internals, `app/services/runners/*`,
   `WorktreeManager`, `ExecuteRunJob` step-walking logic.
6. Conventional commits.

## Harness notes

- Lint: `bundle exec rubocop`. Tests: `bin/rails test` AND
  `bin/rails test:system`, both required.
- minitest 6: no `minitest/mock`. No `assigns` - assert on markup.
- Test cable adapter is `test`: live streaming and presence are NOT
  assertable in system tests; assert mount points and server-side
  behavior instead (see `test/` for the existing pattern).
- The run page is the live-streaming surface. Turbo Stream broadcasts
  render specific partials into specific DOM ids. Before restructuring
  ANY run partial, grep for its broadcast sites
  (`grep -rn "broadcast" app/models app/jobs app/channels`) and keep the
  partial paths and DOM ids that broadcasts target STABLE. Breaking a
  target id silently kills live updates - system tests may not catch it.
- `turbo_confirm` only on destructive actions (Stop keeps its confirm).

---

## C.1 Shared run chrome - one identity, three modes

**Goal:** Show, Replay, and Compare share one header and a mode tab bar.
URLs do not change (permalinks and share flows survive); the three pages
just stop looking like three products. Design: section 5.5.

**Read first:** `app/views/runs/show.html.erb`,
`app/views/runs/_run_header.html.erb`, `app/views/runs/replay.html.erb`,
`app/views/runs/diff.html.erb`, the presence roster partial/controller
(grep `presence` in `app/views/runs` and `app/javascript/controllers`),
`app/helpers/application_helper.rb` (`run_display_name` from A.5)

**Changes:**

1. New partial `runs/_run_chrome.html.erb` rendered at the top of all
   three views:
   - H1 `run_display_name(run)` + status badge + danger pill; the raw
     `#id` moves to the Run info card (C.2).
   - The presence avatar strip moves INTO the header row (it currently
     renders as a separate hidden-by-default roster; keep the same
     Stimulus subscription mechanics, restyle as overlapping avatars).
   - Meta line: "Started by <label> · <relative time> · $cost · Ntok ·
     project · workflow" (omit nil parts).
   - Actions: Stop (active runs, keeps confirm), Re-run, Resume (when
     applicable), Share (existing flow), and any remaining header
     actions from `_run_header` in a trailing menu. Nothing is removed -
     relocated only.
   - Mode tab bar: Overview -> `run_path`, Transcript ->
     `replay_run_path`, Compare -> `diff_run_path`; active state from
     the current action.
2. Replay and diff drop their own H1/button rows in favor of the chrome
   (their mode-specific controls - filter chips, compare picker - stay).
3. Replay's metrics grid (Cost/Tokens/Turns/Duration) stays on the
   Transcript mode only.

**Acceptance criteria:** all three modes show identical identity/actions
and a working tab bar; presence avatars visible in the header on all
three; every action previously on any of the three headers is still
reachable; permalinked replay anchors still scroll and highlight.

**Tests:** integration tests asserting the chrome renders on all three
paths and the tab links are present; update system tests that clicked
the old "Replay"/"Compare"/"Live view" buttons.

## C.2 Overview - the curated timeline

**Goal:** The default run view reads like a report: per-step status,
duration, cost, one-line result. The raw material moves one level deeper
but stays one click away. Design: section 5.5.

**Read first:** `app/views/runs/_run_step.html.erb` (all of it - you are
re-layering its ~10 collapsibles), `app/views/runs/show.html.erb`
(column layout, `_run_context`, input card, Share card, Follow Up
block), `app/views/runs/_approval_actions.html.erb`, the broadcast sites
that target run-step DOM ids (see Harness notes - this is the item where
that warning bites), `app/models/run_step.rb` (what summary data exists:
duration, cost, error, output variables)

**Changes:**

1. Restructure `_run_step.html.erb` IN PLACE (same partial path, same
   outer DOM id so broadcasts keep landing):
   - Collapsed row: `status_dot`, step name, type badge, duration,
     cost, attempt count when > 1, and a one-line result - for
     completed: the produced variable names; for failed: the first line
     of the error; for awaiting approval: "waiting on a human".
   - Expanded (the row's `<details>`): output variables, error message,
     approval history, step discussion, and the Retry-from-here button -
     the curated layer.
   - A nested `Raw details` disclosure inside the expanded area holding
     everything else exactly as it renders today: input vars, todo
     list, context queries, activity log, step assets, raw output,
     stderr, View Context. Move the existing markup; do not rewrite it.
2. Show page right rail order becomes: approval banner stays above the
   columns (unchanged); rail: Run info (gains a muted `Run id  #47`
   row), Share card, Discussion (run-level comments move UP the rail),
   then Context and Input cards COLLAPSED by default (wrap in
   `<details>`); Follow Up block unchanged in place.
3. Empty/edge states: a run with no steps yet shows the A.4 copy; a
   streaming step keeps its live log exactly as today (the streaming
   region sits inside Raw details' parent - verify live updates still
   render while collapsed and expand correctly mid-stream).

**Acceptance criteria:** a finished run's default view fits the "report"
description with no raw JSON visible; every piece of information
previously on the page is still reachable (audit by listing the old
partial's sections and checking each off); live streaming of an active
run still updates rows in place (verify manually with a real run via
`bin/dev` - system tests cannot see broadcasts).

**Tests:** view tests asserting the one-line result for a completed and
a failed fixture step; a test that stderr content is NOT in the
top-level collapsed markup but IS present within the raw-details
section; suite + system suite.

**Gotchas:** THE BROADCAST IDS. If `ExecuteRunJob` or a model broadcasts
`runs/_run_step` replacements, the partial's outer element id and path
must not change - restructure inside it. Do not touch the job. If the
broadcast mechanism turns out to target something incompatible with this
restructure, STOP and report the specifics.

## C.3 Launch composer

**Goal:** The task form becomes the launch flow: workflow cards with
stats, spec, files, and scheduling in one deliberate page. Design:
section 5.4.

**Read first:** `app/views/pipeline_tasks/_form.html.erb` +
`_trigger_fields.html.erb`, `app/controllers/pipeline_tasks_controller.rb`
(create/update, `after_save_redirect`, `run_now` handling),
`app/javascript/controllers/task_form_controller.js` (project ->
workflow filtering you are adapting to cards),
`app/models/workflow.rb` (`stats` from B.2),
`WorkflowAccessSummary` (B.6), the code map status partial + generate
route (`app/views/projects/` code map card)

**Changes:**

1. Form order becomes: Title; Project; Workflow as a CARD GRID (each
   card: name, description, step count, stats line, access chips, a
   hidden radio `pipeline_task[workflow_id]`; cards carry
   `data-project-id` and the task-form controller shows/hides by
   project exactly as it does for options today; selected card gets the
   accent ring; include a "No workflow yet - save as draft" card);
   Spec (existing editor + Format with Claude); Relevant files (ALWAYS
   rendered: with a ready code map, today's checkbox list + Suggest
   with Claude; without one, an explanation + a `Generate code map`
   button posting to the existing generate route for the selected
   project; with no project selected, a muted "Pick a project first");
   When to run (chip-style radio row: Now / On a schedule / When a
   branch changes, mapping to the existing trigger_type values; the
   cron panel keeps its presets with Custom revealing the raw
   expression field; branch watch panel unchanged).
2. Buttons: primary `Launch` (the existing `run_now=1` submit), secondary
   `Save draft`. On edit the same labels apply (`Launch` still means
   save-then-run via the existing controller path).
3. Kind demotion: `kind` moves into an "Advanced" disclosure at the
   bottom, relabeled "Tag"; the model gains a default of `"feature"`
   (set in a `before_validation` or column default migration - match
   codebase conventions) so the field can be omitted entirely.
   Validation stays (`inclusion` on the three values).
4. `pipeline_tasks#new` accepts optional `description` and `project_id`
   params to prefill body/title/project (C.4 links the palette here).

**Acceptance criteria:** a task can be composed and launched top to
bottom; workflow cards filter by project and show stats + access; the
files section explains itself in all three states; kind is optional and
defaults to feature; drafts still work.

**Tests:** controller tests - kind omitted saves as feature; new-with-
prefill params; existing create/run_now tests still pass. System test:
compose and launch via cards end to end (update the existing task form
system tests - the workflow `<select>` is gone).

**Gotchas:** `task_params` must keep permitting `workflow_id` from the
radio; the JS filter must also CLEAR a selected card that the new
project hides (the old controller does this for options - port that
behavior).

## C.4 Palette polish

**Goal:** The ⌘K fast path gains the same confidence glance, and a door
to the full composer. Design: section 5.4.

**Read first:** `app/controllers/quick_launch_controller.rb` (`options`
JSON shape), `app/javascript/controllers/command_palette_controller.js`,
`app/views/shared/_command_palette.html.erb`

**Changes:**

1. `quick_launch#options` adds per-workflow `stats` (the B.2 numbers,
   pre-formatted server-side as one string) and `access` (B.6 labels
   joined) to the JSON.
2. The palette renders a muted one-line summary under the workflow
   select whenever a workflow is chosen ("34 runs · 91% · ~$1.20 ·
   opens PRs"), updating on change.
3. A "Full composer" link in the palette footer navigating to
   `/tasks/new` carrying the typed description and selected project as
   params (C.3's prefill).

**Acceptance criteria:** choosing a workflow in the palette shows its
stats/access line; the composer link lands with description and project
prefilled; quick launch itself is unchanged.

**Tests:** controller test for the extended options JSON shape; system
test asserting the summary line appears after selecting a workflow.

---

# Definition of done (every item)

1. `bin/rails test` passes.
2. `bin/rails test:system` passes.
3. `bundle exec rubocop` passes.
4. No em/en dash characters anywhere in the diff.
5. CHANGELOG.md entry added.
6. The item's acceptance criteria demonstrably hold.
7. Nothing outside the item's stated scope changed.
