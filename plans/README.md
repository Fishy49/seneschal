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

- [x] Phase A - Foundation (built on `feat/ui-phase-a`, awaiting merge)
- [x] Phase B - Authoring (built on `feat/ui-phase-b`, awaiting merge)
- [ ] Phase C - Runs
- [ ] Phase D - Adoption

Both branches were cut from `feat/ux-collab-redesign` rather than `main`,
because the collaboration work they depend on has not merged to main yet. The
order still holds: merge collab, then A, then B.

Notes for Phase C:

- B.5's relabels landed inside B.4, since both touched the same markup.
- The step inspector answers `turbo_stream` (replacing `workflow_steps` and
  `step_inspector`) with an HTML redirect fallback. C.1's run chrome should
  follow the same pattern rather than inventing another.
- `test/application_system_test_case.rb#sign_in_as` waits on `h1` "Home". Any
  further change to the dashboard heading breaks every system test at once.

Check a box when the phase branch is merged. `IMPLEMENTATION_PLAN.md` at
the repo root is the previous (completed) plan and is kept for history;
nothing in it is pending.
