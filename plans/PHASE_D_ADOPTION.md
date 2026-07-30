# UI Overhaul Phase D - Adoption

Starter templates, onboarding, provenance, and teaching empty states -
the layer that makes the product easy to pick up and worth copying from
each other. Design source: `PRODUCT_REDESIGN.md` sections 6, 7. Requires
Phases A-C merged (gallery lands in the B editor, checklist on the A
Home, stats/chips from B).

## How to use this document

- Work items are ordered; one item = one commit on `feat/ui-phase-d`.
- Read every "Read first" file before editing. Trust code over plan.
- If the code contradicts this plan, STOP and report.

## Hard rules (every item)

1. NEVER write an em dash (U+2014) or en dash (U+2013) anywhere. Plain
   hyphens only. A pre-write hook enforces this - including inside the
   template JSON and SKILL.md content authored in D.1.
2. Match surrounding code style; comments only for non-obvious
   constraints.
3. Every behavioral change gets a minitest test.
4. CHANGELOG.md entry per item under `## Unreleased - UI overhaul phase D`.
5. NEVER modify: `StepExecutor` internals, `app/services/runners/*`,
   `WorktreeManager`, `ExecuteRunJob` step-walking logic.
6. Conventional commits.

## Harness notes

- Lint: `bundle exec rubocop`. Tests: `bin/rails test` AND
  `bin/rails test:system`, both required.
- minitest 6: no `minitest/mock`. No `assigns` - assert on markup.
- Fixtures: `users(:admin)`, `users(:other)`.

---

## D.1 The starter template pack

**Goal:** Five curated workflows shipped as bundled export files in the
existing `seneschal_workflow_export` v1 format, so "Use template" is just
the existing importer. Design: section 6.2.

**Read first:** `app/services/workflow_exporter.rb` (the exact export
shape: version, workflow + steps with `skill_ref`/`json_schema_ref`,
skills with `skill_md_content`, json_schemas),
`app/services/workflow_importer.rb` (what it requires, how skills are
materialized, name-conflict suffixing), `app/models/step.rb`
(config keys per type - get `${var}` names right)

**Changes:**

1. Author five export JSONs under `lib/seneschal/starter_templates/`:
   - `classic_feature.json` - plan (skill) -> implement (skill, consumes
     the plan output) -> self review -> open PR -> wait for CI. Teaches
     the core loop + self review.
   - `bugfix.json` - reproduce and diagnose (skill) -> fix (skill) ->
     self review -> open PR -> wait for CI. Teaches diagnosis-first.
   - `guarded_refactor.json` - plan with `manual_approval: true` ->
     implement -> open PR. Teaches approval gates.
   - `docs_pass.json` - analyze (skill) -> write docs (skill) -> open
     PR (draft). Teaches a light no-CI pipeline.
   - `scheduled_maintenance.json` - dependency update (skill) -> open
     PR -> wait for CI; description notes it is built to pair with a
     cron-triggered task. Teaches scheduling.
   Authoring rules: every skill ships generic, well-written
   `skill_md_content` (frontmatter `name:`/`description:` + a prompt
   body that uses `${task_title}`/`${task_body}` where sensible); pr
   steps title from `${task_title}`; ci steps use `${pr_number}` and
   `${branch_name}` (NOT `${branch}`); modest timeouts; no schemas in
   the starter pack (keep the on-ramp unstructured); ABSOLUTELY no em
   or en dashes in any content.
2. A registry `Seneschal::StarterTemplates` (or matching lib naming
   conventions) exposing `all` -> ordered entries `{key, name,
   description, teaches, path}` and `find(key)`.
3. Validation test harness: for EACH template, a test imports it into a
   fixture project via `WorkflowImporter` and asserts the workflow
   exists with the expected step count and step types. This is the
   contract that the pack stays importable as the format evolves.

**Acceptance criteria:** all five import cleanly into a fresh project;
skills materialize on disk with valid frontmatter; the registry lists
them in order.

**Tests:** the round-trip import test per template (use `Dir.mktmpdir`
for the project local_path so SKILL.md materialization has a real
target).

**Gotchas:** the importer materializes skill files to disk - tests must
point projects at tmp dirs, never the repo tree. If the export format
has version-gating, match the version the exporter currently writes.

## D.2 Template gallery in New Workflow (and the Library)

**Goal:** Nobody starts from a blank workflow. Design: section 6.2.

**Read first:** `app/views/workflows/new.html.erb` + `_form.html.erb`,
`app/controllers/workflows_controller.rb`,
`app/controllers/workflow_imports_controller.rb` (how imports are
invoked - reuse, do not duplicate), the D.1 registry,
`app/views/step_templates/index.html.erb` (Library Templates tab)

**Changes:**

1. `workflows/new` leads with the starter gallery: one card per
   template (name, description, ordered step-type list as small badges,
   a "teaches" tag) with a `Use template` button; "Start blank" (the
   existing form) renders below the gallery.
2. `Use template` POSTs to a new
   `create_from_template` action (nested under the project) that runs
   `WorkflowImporter` with the template's JSON against `@project`,
   then redirects to the new workflow's editor with a notice. Name
   conflicts rely on the importer's existing suffix behavior.
3. Library Templates tab gains a "Workflow starters" section at top:
   the same cards with a project picker per card (or one shared select)
   feeding the same action.

**Acceptance criteria:** from a project, two clicks produce a fully
wired starter workflow open in the editor; using the same template
twice produces a suffixed second copy, not an error.

**Tests:** controller test for `create_from_template` (workflow +
steps + skills created, redirect to editor); a duplicate-use test.

## D.3 First-boot wizard

**Goal:** A fresh install rails the operator from admin account to a
templated workflow without guesswork. Design: section 6.1.

**Read first:** `app/controllers/application_controller.rb`
(`require_setup` gate), `app/controllers/setup_controller.rb`,
`app/views/setup/index.html.erb` (post-Phase-A: checks + Continue),
`app/controllers/registrations_controller.rb`,
`app/views/projects/_form.html.erb`, `app/controllers/projects_controller.rb`
(clone action), the D.2 gallery

**Changes:**

1. The Setup page's `Continue to Dashboard` becomes smart: when
   `Project.none?`, it goes to `/projects/new?onboarding=1` instead of
   Home.
2. `projects/new` with `onboarding=1` renders a trimmed flow: heading
   "Create your first project", name + repository URL only (local path
   auto-filled with the default the form's Default button uses;
   description/group/context stay off this screen), and on create,
   clone starts immediately (invoke the same clone action/job the Clone
   button uses) and the redirect lands on the project page with an
   onboarding banner: "Cloning your repo. Next: add a workflow from a
   starter template" linking to the D.2 gallery.
3. The banner is param/state driven (show while `onboarding=1` is in
   the redirect chain or while the project has zero workflows and was
   created in this session - pick the simplest stateless mechanism and
   note it in the code).
4. The `require_setup` gate itself is UNCHANGED - the wizard is a
   routing garnish, not a new gate. All wizard steps are skippable by
   normal navigation.

**Acceptance criteria:** on a fresh database: create admin -> checks ->
Continue -> first-project form -> create -> clone running + banner ->
gallery -> templated workflow in the editor. Every step also escapable
via the sidebar.

**Tests:** integration test walking setup-Continue with zero projects
to the onboarding form; project create with `onboarding=1` starts a
clone (assert enqueued job) and renders the banner.

**Gotchas:** do not touch the registration flow or the gate conditions;
existing setup tests must keep passing.

## D.4 Home onboarding checklist

**Goal:** An invited engineer's empty Home tells them exactly what to do.
Design: section 6.1.

**Read first:** `app/views/dashboard/index.html.erb` (Phase A version),
`app/models/user_credential.rb`, `app/models/run.rb`

**Changes:** when the current user has never started a run
(`Run.where(started_by: current_user).none?`), Home renders a checklist
card above the Runs card with three items, each with a done-checkmark
state and a CTA link:
1. "Connect your accounts" - done when the user has any UserCredential;
   links to Account.
2. "Find your project" - done when any Project exists; links to Projects
   (or New Project for admins when none exist).
3. "Launch your first run" - done never (its completion hides the whole
   card); CTA opens the palette.
The card disappears entirely once the user has started a run.

**Acceptance criteria:** a fresh member sees the checklist with correct
per-item states; after their first launched run it is gone.

**Tests:** view/controller tests for the three state combinations and
the hidden-after-first-run case.

## D.5 Provenance, credit, and most-run sorting

**Goal:** Good pipelines are findable and their lineage visible. Design:
section 7.

**Read first:** `app/services/workflow_copier.rb`,
`app/models/workflow.rb` (`created_by` from the collab work, `config`
json), the hub Workflows tab (B.1), the workflow editor header (B.3)

**Changes:**

1. `WorkflowCopier` stamps the copy's `config["copied_from"]` with
   "<source project name>/<source workflow name>". Display "Copied from
   X" as a muted line on the editor header and hub row when present.
2. Author credit: `avatar_for(workflow.created_by)` on hub rows and the
   editor header (nil-safe - historical rows have no creator).
3. Hub Workflows tab sorting: a small sort control - Name (default),
   Most run, Recently run - server-side param ordering by the B.2 stats
   inputs (count of runs, latest run timestamp). Keep it to `order`
   clauses with a counter subquery or a `left_joins` count - no caching.

**Acceptance criteria:** a copied workflow names its source; workflows
show their author; sorting by Most run puts the workhorse first.

**Tests:** copier test for the stamp; controller test for the sort
param orderings.

## D.6 Teaching empty states sweep

**Goal:** Every empty region names the next action. Design: section 6.3.

**Read first:** the `empty_state` component (A.1); grep views for the
existing empty-state strings ("No runs", "No tasks yet", "Nothing has
happened yet", "No templates yet", "Add the first step", etc.)

**Changes:** convert every empty region to the component with a
message + CTA:
- Workflow editor, no steps: "No steps yet." + `Add step` (and, if the
  workflow came from Start blank, a link back to the starter gallery).
- Hub Workflows tab: "No workflows yet." + `Start from a template`.
- Hub Tasks / Runs tabs: message + `Launch`.
- Runs index, Activity, Library tabs (Skills / Output schemas /
  Templates / Skill repos): message + the section's create action.
- Code map card, not generated: one line on what it unlocks (file
  suggestions in the composer) + `Generate`.
Inventory every empty string you find in the grep and cover it; list
the files touched in the commit body.

**Acceptance criteria:** no bare "No X yet." without a next action
remains in any view the grep surfaced.

**Tests:** suite + system suite pass (several system tests assert empty
state text - update them).

---

# Definition of done (every item)

1. `bin/rails test` passes.
2. `bin/rails test:system` passes.
3. `bundle exec rubocop` passes.
4. No em/en dash characters anywhere in the diff.
5. CHANGELOG.md entry added.
6. The item's acceptance criteria demonstrably hold.
7. Nothing outside the item's stated scope changed.
