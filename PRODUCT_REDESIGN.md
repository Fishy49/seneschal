# Seneschal Product Redesign - The Collaborative Orchestrator

This is a product design document, not an implementation plan. It defines what
the redesigned Seneschal should be: the information architecture, the screens,
the vocabulary, and the product priorities. A separate implementation plan will
be derived from it once the design is agreed.

Author stance: product manager. The engine room (StepExecutor, runners,
worktrees, the run lifecycle) is excellent and proven; the recent collaboration
work (attribution, approvals, comments, activity, presence, share links,
per-user credentials, command palette) gives us the nuts and bolts of
multiplayer. What we have NOT done is design the product around them. The UI is
still a single engineer's cockpit: it exposes the implementation, not the
workflow of a team.

---

## 1. Product goals

Seneschal's new identity: **a collaborative AI orchestrator a team can trust.**

Three goals, in priority order:

- **A. Easy to learn.** A new engineer on the team should go from invite link
  to their first successful run in one sitting, without reading source code,
  without learning JSON Schema, and without being told the secret order of
  objects to create.
- **B. Convenient by default, deep on demand.** Common pipelines should be one
  template-pick away. Every power feature that exists today must remain
  reachable, but behind progressive disclosure rather than in the first form a
  user ever sees.
- **C. Engineers learn from each other and stay in control.** The product
  should make good pipelines visible and copyable, make every action
  attributable, and make it obvious - before launch - what an AI run is
  allowed to touch. Confidence is the feature.

## 2. Diagnosis - why the current UI fights all three goals

From a full audit of every screen and the authoring plane (July 2026):

1. **The object model is exposed raw.** 13 sidebar items. To get one run, a
   newcomer must assemble 8 concepts across 7 screens in an undocumented
   order: Project > clone > Skill (+ SkillRepo or files on disk) > JsonSchema
   > Workflow > Step xN > Task > Run. Nothing in the product states this
   order. First run: ~12 clicks across 8 pages, with a hard clone blocker in
   the middle that nothing warns about.
2. **The step form is the whole product's complexity in one modal.** 806
   lines, 4 tabs, ~40 fields, 7 step types multiplexed through one form via
   show/hide. Validation errors on hidden tabs. A shell step shows an "AI
   Engine" tab. A raw `Position` number field competes with drag-and-drop.
   Switching a step's type silently wipes its config.
3. **Machine-shaped inputs everywhere.** ~24 places ask a human to type
   something a parser will consume: bare JSON Schema textareas, raw cron
   expressions, `${var}` template syntax, comma-separated lists, a
   tool-matcher DSL (`Bash(git *)`), jq expressions, absolute server paths.
4. **The voice is split-brained.** Half the app is terse and plain; the step
   form speaks marketing ("Default Brand Choice", "Lightning response",
   "Self-Healing & Auto-Recovery", "Allowed Tools Rule-Matcher"). One page
   leaks a class name to users ("This run has no RunSteps yet.").
5. **Runs are labeled by database id.** `Run #47` is the primary identity of
   the most important object in the system, on every list and header.
6. **Dead ends and orphans.** `workflows#index` is a routed 500. Projects and
   workflows cannot be deleted from the UI. The Templates page is
   delete-only. `self_review` is a fully implemented step type absent from
   the form. `script` and `command` are byte-identical twins with different
   labels. 11 of 18 real settings have no UI. The workflow model carries dead
   trigger columns while real scheduling lives on tasks.
7. **The collaboration features are bolted on, not centered.** Comments,
   presence, activity, and share links exist but live at the edges of screens
   designed for a solo operator. The dashboard shows four overlapping run
   lists instead of one clear picture of "what does the team need to do".

## 3. Design principles

1. **The run is the product.** Everything a team cares about - progress,
   approvals, cost, discussion, learning - hangs off runs. Runs get human
   names, the best page in the app, and the center of the home screen.
2. **Templates before blank pages.** Nobody should ever stare at an empty
   workflow. Every create flow leads with proven starting points; "start
   blank" is the escape hatch, not the default.
3. **Progressive disclosure, not tabs.** Essentials visible, everything else
   in collapsed groups on one scrollable surface. No field the user cannot
   understand at the moment they see it. Advanced never means hidden - it
   means later.
4. **Human words; machine details on demand.** UI copy never contains config
   keys, CLI flags, Ruby expressions, or class names. The machine shapes
   (schemas, cron, tool matchers) survive - wrapped in pickers, presets,
   validation, and preview, with the raw form one click away for power users.
5. **Show the people.** Every object shows who made it, who ran it, who
   approved it. Avatars and attribution are structural, not decorative -
   they are how engineers discover whose pipelines to copy.
6. **Confidence before launch, transparency after.** What a pipeline can
   touch (tools, write access, danger mode) is visible before running it.
   What it did (cost, diff, transcript, approvals) is legible after.
7. **Don't touch the engine.** This is a UI/UX and product-surface redesign.
   StepExecutor, runners, worktrees, and run semantics are out of scope,
   except where a screen needs one small, well-contained seam.

## 4. The new information architecture

### 4.1 Sidebar: 13 items down to 6 (+ admin)

```
  Seneschal
  ----------------------------
  Home            (mission control; today's Dashboard, redesigned)
  Runs            (badge: needs-you count)
  Projects        (with the existing collapsible project tree)
  Library         (Skills · Schemas · Templates · Skill repos)
  Activity
  ----------------------------
  Admin           (Users · Groups · Server settings · Data)   [admin only]
  ----------------------------
  Launch ⌘K       (button, not a hint - opens the palette)
  [avatar] rick@…  (Account: profile, connections, 2FA)
  theme toggle
```

What moved where:

- **Skills, Skill Repos, Schemas, Templates** merge into one **Library**
  section with tabs. They are all "reusable ingredients"; none deserves a
  top-level nav slot. Skill Repos stays admin-gated inside Library.
- **Groups** moves under Admin (it is org-shaping, used rarely). The project
  tree keeps showing groups; the management page moves.
- **Setup** dies as a permanent destination. First-boot keeps a guided
  wizard (see 6.1); its settings move to **Admin > Server settings**, which
  also gains UI for the 11 currently console-only settings.
- **Users, Data** move under Admin.
- **2FA** moves onto the Account page where it belongs; the sidebar link
  goes away.
- **Tasks** loses its top-level slot; tasks live inside their project hub
  and inside the launch flow (see 5.4). A global tasks view survives as a
  filter on Runs ("drafts & scheduled") because its main use is "what is
  queued or scheduled", which is run-adjacent.

### 4.2 Vocabulary (UI labels only; no DB renames)

| Today | Redesign | Why |
|---|---|---|
| Pipeline Task | **Task** | Already half-renamed; finish it. |
| Run #47 | **"<task title>" - run 3** (id demoted to metadata) | Humans think in tasks, not ids. Numbering is per-task ordinal; #47 remains visible in details and URLs. |
| Kind (Feature/Bugfix/Chore, required) | **Tag** (optional, default "feature") | It gates nothing but a template variable; stop making it a required decision. |
| Skill (AI Agent) | **Skill** | Fine as-is; drop the parenthetical. |
| Prompt (Direct LLM) | **Prompt** | Same. |
| Script (File) + Command (Shell) | **Shell** (one type) | Byte-identical implementations; two labels is a lie. Existing rows keep working; the form offers one type. |
| CI Check (GitHub) | **Wait for CI** | Says what it does. |
| Context Fetch (Ingestion) | **Fetch context** | Same. |
| Open PR (Git Flow) | **Open PR** | Drop the parenthetical. |
| (unreachable) self_review | **Self review** | Fully implemented; expose it. |
| Runner (claude_cli / claude_sdk) | **Engine: "Standard" / "Advanced (SDK)"** with plain help | No Ruby paths in a select. |
| JSON Schemas | **Output schemas** | Names the purpose, not the format. |
| Step Templates | **Templates** | Within Library context. |
| Spec / body / task_body | **Spec** everywhere in UI | One name; the variable name stays `task_body` and is documented in the variables panel. |

### 4.3 Voice

One register everywhere: plain, terse, confident - the voice of the runs
pages today. A single copy pass removes every CLI flag, config key, class
name, and marketing adjective from user-facing text. Machine syntax appears
only inside monospace affordances that exist to hold it (template fields,
the schema editor), always with a one-line plain-language explanation.

## 5. The screens

### 5.1 Home (replaces Dashboard)

One question answered above the fold: **"What does the team need right now?"**

- **Needs you** banner (exists) stays at top - the single most important
  region in the product. Each row: task title, project, who launched it,
  how long it has been parked, avatar of anyone currently viewing it,
  `Review` button.
- **One run module, not three.** "Active" and "Recent" become sections of a
  single Runs card (live region, already auto-refreshing). Each row: status
  dot, task title, per-task run ordinal, project, launcher avatar, cost,
  relative time.
- **Right rail: Projects** (exists, keep), each with `Launch` (opens the
  palette pre-filtered to that project), plus a compact **Activity** strip
  (latest 5, attributed, links to /activity).
- **Launch** is the primary page action, top right, opening the ⌘K palette.
  Same palette, mouse-discoverable.
- **Empty state = onboarding checklist** (see 6.1), not a blank card.

Removed: the standalone "Recent Runs" duplicate list, the "Ready to run"
card as a separate region (draft/scheduled tasks fold into the project hub
and the Runs filter; genuinely launchable tasks surface inside the Runs
card's empty state and the palette).

### 5.2 Project hub

The project page becomes the team's home for a repo, with tabs:

```
<project name>   [repo chip: cloned ✓ | clone needed | error]  [Danger Mode ⚠]
Overview | Workflows | Tasks | Runs | Skills | Settings
```

- **Overview:** description, repo + code map status (generate/refresh here),
  latest runs strip, who's been active. Header has one primary action
  (`Launch`) and one `New ▾` menu (Workflow, Task, Import workflow) instead
  of today's six undifferentiated buttons.
- **Workflows:** the workflow list with real information density: name,
  description, step count, **last run status, run count, success rate over
  last 20, median cost** - the stats that let engineers judge and adopt each
  other's pipelines. Actions: Run, Edit, Copy to project, Export, Delete
  (finally). This also retires the broken `workflows#index` route by giving
  it a real page.
- **Tasks:** today's per-status card stack becomes one table with a status
  filter chip row (one header, not five). Row action: Run (when
  executable) - fixing "must open the task first to run it".
- **Runs:** the project-scoped run list that does not exist today.
- **Skills:** project-scoped skills (shared library linked), fixing the
  "where do skills for this project live" question.
- **Settings:** name, repo URL, local path (relabeled "Server checkout
  path", with the default prominent and the free-form path as the advanced
  case), context markdown, group, Danger Mode (unchanged, still loud), and
  **Delete project** (finally, with a typed-name confirm).

Clone stops being a mystery blocker: everywhere a run could be launched
against an uncloned project, the CTA becomes `Clone & continue` rather than
a disabled control with a tooltip.

### 5.3 Workflow editor - the flagship redesign

Today: workflow show page + a separate 4-tab, 40-field step page per step.
Redesign: **one editing surface.** The step list is the canvas; selecting a
step opens an inspector panel beside it. No page navigation per step.

```
<workflow name>  · engine chip · access chip        [Run workflow] [⋯ menu]
"Build a classic mode feature from spec to PR"       stats: 34 runs · 91% · ~$1.20

+---------------------------- + -----------------------------+
| 1 ● plan        [skill]     |  INSPECTOR (selected step)   |
|     → feature_plan          |                              |
| 2 ● implement   [skill]     |  Name        [implement    ] |
|     ← feature_plan          |  Type        [Skill      ▾]  |
|     → diff_summary          |  Skill       [impl-classic ] |
| 3 ● self review [review]    |                              |
| 4 ● open PR     [pr]        |  ▸ Data (1 output, 1 input)  |
|     → pr_number, pr_url     |  ▸ Model & tools             |
| 5 ● wait for CI [ci]        |  ▸ Guards & recovery         |
|                             |                              |
| [+ Add step ▾]              |  [Save]     [Save as template]|
+---------------------------- + -----------------------------+
Variables: task_title · task_body · feature_plan (plan) · diff_summary (implement) · pr_number …
```

Key decisions:

- **The inspector is per-type.** Choosing "Shell" renders the shell form:
  name, command, timeout, retries. Nothing else. Choosing "Skill" renders
  skill picker + the three collapsed groups. The 40 fields still exist -
  distributed across types and disclosure groups so no one ever sees more
  than ~8 at once.
- **Groups, not tabs:** `Data` (outputs, schema, inputs), `Model & tools`
  (model, effort, max turns, allowed tools, previews - skill/prompt only),
  `Guards & recovery` (timeout, retries, manual approval, on-fail). All on
  one scroll; validation errors are always visible.
- **Position dies as a field.** Drag to reorder is the only ordering model,
  and the drag handle becomes visible (grip icon).
- **Type switching warns** before discarding config ("Switching to Shell
  clears this step's PR settings - continue?") instead of silently wiping.
- **Data wiring becomes legible without changing semantics.** The canvas
  keeps the `→ produces` / `← consumes` pills but they gain a legend; a
  persistent **Variables strip** under the canvas lists every variable with
  its producing step and schema, and clicking one highlights its producers
  and consumers on the canvas. In the inspector, `Data` shows:
  - *Outputs:* the tag input (exists), or the schema picker when the skill
    has a default (inherit/override widget survives, restyled as a simple
    "Using skill default: feature_plan (plan_schema) - change").
  - *Inputs:* the checkbox table (exists), with "Inject" relabeled
    **"Include value in prompt"** and "Query" relabeled **"Make queryable
    in workspace (advanced)"** - jq is mentioned only in the advanced help
    popover, not in the primary legend.
- **Access chip** in the header summarizes what the workflow can touch:
  allowed tools union, write access, danger mode - the pre-launch
  confidence surface (goal C). Clicking it lists per-step access.
- **Self review** joins the type menu. **Shell** replaces script+command.
  The CI step's `${branch}` default is corrected to the variable a PR step
  actually emits (`branch_name`).
- **Engine select** speaks human: "Standard (Claude CLI)" / "Advanced SDK -
  structured outputs, hooks, MCP", with setup state shown inline if the SDK
  runner is not installed.

### 5.4 Launch flow (task composer)

Tasks are reframed as **the thing you write to launch a workflow**, not a
peer object to manage. Two entry points, one form:

- **⌘K palette** (exists): the fast path. Description + project + workflow,
  Enter. Gains one line showing the chosen workflow's access chip and
  median cost - a confidence glance before launch.
- **Full composer** (`New Task` / palette's "more options"): a single page
  in this order:
  1. **Project** then **Workflow as cards** (name, description, step
     count, stats, access chip) - not a `<select>`. The card grid is where
     engineers see each other's proven pipelines at the moment of choice.
  2. **Spec** - the markdown editor with `Format with Claude` (exists).
  3. **Relevant files** (exists; now always visible - when no code map,
     the section explains and offers `Generate code map` instead of
     vanishing).
  4. **When to run:** Now / On a schedule (presets + custom cron behind
     "custom", with a plain-language echo of what it means: "Weekdays at
     9:00 UTC") / When a branch changes (exists).
  5. Primary `Launch` (or `Schedule`), secondary `Save draft`.
- "Kind" becomes an optional tag on the advanced disclosure.

### 5.5 Run page - the collaboration surface

Merge today's three pages (show / replay / diff) into one page with view
modes; nothing gets lost, everything gets one address.

```
"NPC dialogue trees" · run 3          [status]  [⚠]   ● rick ● dana (viewing)
Started by rick · 4m ago · $0.84 · 41k tokens
[Overview] [Transcript] [Compare]              [Stop] [Re-run] [Share] [⋯]
```

- **Overview** (new default): the step timeline - one row per step with
  status, duration, cost, and a one-line result summary; expanding a row
  reveals the *curated* essentials (output variables, error message,
  approval history, step discussion). The raw material (stderr, raw
  output, context queries, input dump) moves behind a per-step "Raw
  details" disclosure - still one click for power users, no longer the
  default texture of the page. The right rail: run info, context/input
  cards (collapsed by default), share card, discussion.
- **Approval banner** (exists) stays maximally prominent; approve with
  note, reject with feedback, history shown - unchanged behavior.
- **Transcript** = today's Replay (filters, permalinks, trajectory) as a
  mode, not a separate page. The "no RunSteps" copy becomes "This run has
  no steps yet."
- **Compare** = today's diff view as a mode; the run picker options say
  "run 2 · completed · 3 days ago" instead of `#42 · 2026-07-19 14:03`.
- **Discussion and presence** stay structural on all three modes (rail on
  Overview/Compare, docked on Transcript).

### 5.6 Library

One section, four tabs. The theme is: ingredients get real editors, real
provenance, and real usage data.

- **Skills:** list with scope chips (shared / project / repo) and "used by
  N steps". The show page gains an **in-app SKILL.md editor** (CodeJar,
  same as project context) replacing "go edit files on disk" - the single
  biggest authoring-plane fix. Scripts/references file lists stay
  read-only with on-disk paths shown under an advanced disclosure. The
  four-tier resolution order gets rendered as a visible "resolves from"
  line on each skill ("project copy overrides repo copy").
- **Output schemas:** the JSON editor gets the CodeJar treatment plus live
  validation feedback and a starter snippet; "used by" counts include
  skill defaults. Each schema shows the dotted paths it will expose to
  consumers (the thing that silently changes when you edit one).
- **Templates:** becomes a real gallery - name, description, type, source
  workflow, "use in workflow" action - with create/edit, not just delete.
  Ship the starter pack here too (see 6.2).
- **Skill repos (admin):** as today, with "Pri" spelled "Priority (lower
  resolves first)" and sync state made friendlier.

### 5.7 Admin

- **Server settings:** the current Setup checks (Claude CLI, gh, SDK
  runner) presented as a health panel, plus forms for every real setting -
  allowed tools, default engine, notification URLs, skill roots, worktree
  root/retention, assets root, MCP servers (textarea with JSON validation),
  write confinement. 11 settings leave the console.
- **Users / Groups / Data:** as today, relocated. The invite flow keeps
  its copy-link model but says so honestly on the create form.

## 6. The convenience layer

### 6.1 First-boot wizard and onboarding checklist

Replace the Setup gate with a linear first-boot flow: admin account > CLI
health checks (same probes) > **create first project** (name + repo URL,
clone starts immediately with progress) > **pick a starter workflow
template** > land on Home with the checklist completed. Every step
skippable; the gate only requires the CLI checks as today.

For invited (non-first) users, Home's empty state is a 3-item checklist:
connect your GitHub/Claude credentials (Account > Connections), pick a
project, launch your first run.

### 6.2 Starter workflow templates

The single highest-leverage convenience feature, and nearly free: the
`seneschal_workflow_export` v1 format already round-trips workflows with
skills and schemas. Ship 5 curated exports as in-app templates, surfaced in
"New workflow" (gallery first, "Start blank" below) and in the Library:

1. **Feature: spec to PR** - plan (skill) > implement (skill) > self
   review > open PR > wait for CI.
2. **Bugfix: reproduce first** - reproduce & diagnose > fix > self review
   > open PR > wait for CI.
3. **Guarded refactor** - plan > approval gate > implement > open PR.
4. **Docs pass** - analyze > write docs > open PR (no CI wait).
5. **Scheduled maintenance** - a cron-ready dependency-bump pipeline.

Each ships with generic, editable SKILL.md content and demonstrates one
concept (self review, approval gates, CI wait, scheduling) so templates
double as teaching material.

### 6.3 Empty states that teach

Every empty region names the next action and offers its button: an empty
workflow list offers the template gallery; an empty run list offers Launch;
a missing code map explains what it unlocks and offers Generate. The golden
path is taught in place, never in a manual.

## 7. The collaboration and confidence layers

Mostly built in the last cycle; the redesign centers them:

- **Attribution everywhere** (exists): avatars on runs, workflows, tasks,
  comments, approvals. New: workflow cards credit their author; the
  Workflows tab is sortable by "most run" - the social proof that spreads
  good pipelines.
- **Copyability:** `Copy to project` and `Export` get equal billing on
  workflow cards; a copied workflow records provenance ("copied from
  infra/classic_feature").
- **Access chips** (new, see 5.3): the pre-launch answer to "what can this
  thing do to my repo". Derived from existing per-step config (allowed
  tools, danger mode, step types that write). Purely presentational - no
  engine changes.
- **Cost transparency** (exists): kept at run and step level, added at
  workflow level (median cost on cards) - powered by existing run data.
- **Approvals, comments, presence, share links, activity** (exist):
  unchanged in behavior, repositioned as described in 5.1/5.5.

## 8. Component system (the visual layer)

The current templates repeat long Tailwind utility strings per element;
consistency is by copy-paste. The redesign extracts the ~10 recurring
patterns into shared partials/helpers so every screen speaks the same
dialect and future restyling is one-file work:

`page_header` (title, chips, actions) · `card` (title, action, body) ·
`filter_bar` · `data_table` · `status_dot` + unified `badge` set (with a
legend popover) · `avatar` / `avatar_strip` · `empty_state` (message +
CTA) · `chip` (access/engine/repo) · `inspector_panel` · `stat` (label +
value).

The existing token system (`--bg #0f1117`, card `#1a1d27`, accent
`#6366f1`, success/warning/danger/info, radius 8px, dark default + light
theme) is kept as-is per the brief. Density tightens on data surfaces
(runs, tables) and loosens on authoring surfaces (composer, inspector).

## 9. Bugs and dead ends folded into this redesign

Cataloged during the audit; each is owned by a screen above: the routed but
missing `workflows#index` (5.2) · no project/workflow delete UI (5.2) ·
delete-only Templates page (5.6) · unreachable `self_review` type (5.3) ·
script/command duplication (5.3) · silent config wipe on type switch (5.3)
· `${branch}` vs `branch_name` CI default mismatch (5.3) · wrong
allowed-tools help text ("full capability" vs actual default) (5.3) · 11
console-only settings (5.7) · workflow dead trigger columns (retire the
validation + columns during 5.3 work) · `.claude/skills` vs
`.seneschal/skills` import asymmetry (5.6, import scans both) · Setup page
misnested div (dies with the page) · "RunSteps" copy leak (5.5) · 2FA
orphaned from Account (4.1) · code map reachable only via one small link
(5.2) · raw `#id` labels (4.2).

## 10. Out of scope

- StepExecutor, runners, worktree management, run/step lifecycle semantics.
- Per-project membership, roles, or access control (unchanged from prior
  plan's Phase 4).
- Email notifications.
- The assistant branch (`feature/ai-application-assistant`).
- New color/brand identity - tokens stay; this is IA, screens, and
  components, not a rebrand.
- Changing produces/consumes/queries execution semantics. We relabel and
  visualize; the wiring model itself is untouched.

## 11. Design position - why linear beats a node graph

Decided July 2026, recorded so it is not relitigated every time someone
demos an n8n-style canvas.

Seneschal stays a **linear pipeline of smart steps**, not a node graph
with branching edges. Three reasons, in order of weight:

1. **Node canvases exist to compensate for dumb nodes.** In integration
   tools each node does one deterministic thing, so all intelligence must
   live in the topology - the canvas IS the program. Seneschal's steps
   contain agents that read, decide, loop, and retry; conditional logic
   migrates into the step, and the topology stays simple. Linear + smart
   steps is a bet that models keep improving at judgment, which is the
   right bet.
2. **The engine is single-threaded by design.** Every run executes in one
   shared git worktree. Concurrent graph branches editing the same working
   tree would be a merge-conflict generator, not a feature. Integration
   tools can fan out because their branches touch different services; ours
   would touch the same files.
3. **The domain's ancestor is CI, not n8n.** GitHub Actions - the most
   successful pipeline tool for this exact audience - is a linear list
   with `needs` and `if`, no canvas. Engineers trust text-shaped pipelines
   they can diff, export, and copy; the collaboration thesis (stats,
   access chips, copy-to-project) depends on workflows staying legible
   objects.

When branching pressure arrives, it clusters into two shapes, and both
preserve the list:

- **Conditional skip** - a `when` predicate on a step ("skip the fix step
  when self review says PASS"). Renders as one annotation line. The
  precedent already exists: on_fail recovery, approval gates, and CI wait
  are conditionality expressed as step properties, not graph edges.
- **Parallel groups** - consecutive read-only steps marked as a concurrent
  block, like Actions' `needs`. This one is real engine work (worktree
  isolation for writers), so it is demand-driven and explicitly deferred.

If a graph *view* is ever wanted, render a read-only mini-DAG derived from
the produces/consumes wiring we already track - the visualization without
the editing surface. The variables strip (5.3) delivers most of that value
already.

## 12. Phasing

Four phases, each shippable, ordered to de-risk:

- **Phase A - Foundation:** component partials (8), IA + navigation
  (4.1), vocabulary + copy pass (4.2/4.3), dead-end fixes that are pure
  additions (deletes, workflows tab, settings UI), Home (5.1).
- **Phase B - Authoring:** the workflow editor + step inspector (5.3),
  Library with in-app skill/schema editors (5.6), project hub (5.2).
- **Phase C - Runs:** run page consolidation with Overview mode (5.5),
  launch composer (5.4).
- **Phase D - Adoption:** starter templates (6.2), first-boot wizard +
  onboarding checklists (6.1), workflow stats + access chips everywhere
  (7).

Phase A is light-to-moderate work; B is the intensive one; C is moderate;
D is light and mostly content. Each phase gets its own implementation plan
in the style of IMPLEMENTATION_PLAN.md when we commit to it.
