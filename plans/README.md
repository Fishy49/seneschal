# Seneschal UI/UX Overhaul - Implementation Plans

This directory packages the redesign defined in `../PRODUCT_REDESIGN.md`
into four executable work queues, one file per phase. Each phase file is
self-contained and written to be executed by an AI coding model one work
item at a time, in the same format as the (completed) root
`IMPLEMENTATION_PLAN.md`.

## Prerequisite

The collaboration branch `feat/ux-collab-redesign` (21 commits: Save & Run,
dashboard regions, command palette, attribution, approvals, comments,
activity feed, presence, share links, per-user credentials) must be merged
into main before Phase A starts. Phase items reference files and features
that branch created. If `app/models/comment.rb` or
`app/views/shared/_command_palette.html.erb` do not exist on your base,
STOP - you are on the wrong base.

## Order and dependencies

Execute phases in order. Do not start a phase until the previous phase is
merged.

| File | Theme | Depends on |
|---|---|---|
| `PHASE_A_FOUNDATION.md` | Component kit, navigation IA, vocabulary, settings UI, Home | collab branch merged |
| `PHASE_B_AUTHORING.md` | Project hub, workflow editor + step inspector, Library | A |
| `PHASE_C_RUNS.md` | Run page consolidation, launch composer | A (B recommended) |
| `PHASE_D_ADOPTION.md` | Starter templates, onboarding, provenance | A + B + C |

One phase = one feature branch off main (`feat/ui-phase-a`, etc.).
One work item = one commit. Do not batch items.

## How to run a phase

Prompt the executing model with the single phase file, for example:
"Implement plans/PHASE_A_FOUNDATION.md, one work item at a time, top to
bottom." Each file repeats the hard rules and harness notes so no other
context is required beyond the repo itself and `PRODUCT_REDESIGN.md` for
design intent.

## Status

- [x] Phase A - Foundation (squashed into `feat/ux-collab-redesign`)
- [x] Phase B - Authoring (squashed into `feat/ux-collab-redesign`)
- [x] Phase C - Runs (`feat/ui-phase-c`)
- [x] Phase D - Adoption (`feat/ui-phase-d`)

All four phases are built. A and B were squashed into
`feat/ux-collab-redesign`; C and D sit on branches stacked above it. None of
it is on `main` yet, because the collaboration work underneath has not merged
either.

Things a later change should not undo:

- B.5's relabels landed inside B.4, since both touched the same markup.
- `ExecuteRunJob` broadcasts into `run_header`, `run_info`, `run_context`,
  `run_steps_list` and `run_step_<id>`. Those element ids and partial paths
  are a contract. `test/controllers/runs_controller_test.rb` renders each
  partial the way the job does; system tests cannot see broadcasts.
- The presence roster sits OUTSIDE `#run_header` on purpose. Inside, it would
  be re-mounted on every step broadcast and the viewer would appear to leave
  and rejoin constantly.
- `preserve_details_controller` keys open/closed state on summary text unless
  a `data-preserve-key` is given. Anything whose summary contains a live
  number needs the explicit key or it will collapse itself mid-stream.
- `test/application_system_test_case.rb#sign_in_as` waits on `h1` "Home".
  Changing the dashboard heading breaks every system test at once.
- The starter pack under `lib/seneschal/starter_templates/` is validated by
  importing each file for real. If the export format changes, fix the pack.

Not verified: live Turbo Stream delivery during a real run. It needs `bin/dev`
plus a cloned repo and the Claude CLI. Worth one manual smoke run before
merging.

Check a box when the phase branch is merged. `IMPLEMENTATION_PLAN.md` at
the repo root is the previous (completed) plan and is kept for history;
nothing in it is pending.
