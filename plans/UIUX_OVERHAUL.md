# UI/UX Overhaul - "The Steward's Console"

Top-down redesign of Seneschal into a polished, collaboration-first product.
Interactive mockups + full rationale: see the "Seneschal - Redesign Proposal"
artifact (published 2026-07-28). This document is the implementable spec.

## Thesis

Agents do the work; the team holds the seal. Every human decision (approve,
reject, retry, comment) is a first-class event in one thread per run. The UI
has three jobs: surface what needs a person now, make the decision one click
with full context, and keep the record.

Three pillars:

1. **The Inbox** - home becomes an attention queue (approvals, failures,
   mentions, replies), each answerable in place.
2. **The Room** - one unified thread per run: agent events + human comments +
   sealed decisions interleaved in a persistent rail beside the timeline.
3. **The Seal** - brass is reserved exclusively for human decisions. A
   geometric seal rosette marks approvals everywhere (button, thread event,
   timeline node, board column, brand).

## Design language

### Palette (CSS custom properties, same token architecture as today)

Dark "Nightwatch" (default):

| token | value | role |
|---|---|---|
| --bg | #0E1113 | page ground |
| --bg-card | #15191C | raised surfaces |
| --bg-input | #1C2124 | inputs / inset wells (also fixes dead `surface-muted`) |
| --border | #262D31 / strong #374147 | edges |
| --text | #E8ECED / #9FAAB0 / #68757C | content / muted / faint |
| --accent | #41BFAB (hover #63D2BF, on-accent #0A1411) | verdigris, all interactive |
| --brass | #C6A268 (hover #D9BA82, on-brass #141008) | human decisions ONLY |
| --success / --warning / --danger / --info | #53C287 / #DCA83F / #E36A5E / #6AA5E8 | semantic status |

Light "Daybook": #F1F2F1 ground, #FBFBFA card, #E8EAE9 input, #D6DAD8 edge,
text #171C1E / #525E63 / #8A959B, accent #0E8A7A (on-accent #FFF), brass
#96783D (on-brass #FFF), status #1E9459 / #AD7712 / #C74538 / #2A6FC4.

Rules:
- Accent is a USER PREFERENCE (5 presets: verdigris default, cobalt, heather,
  claret, moss). Brass + status colors are NOT customizable - decisions and
  states must read identically for every teammate.
- New `--on-accent` / `--on-brass` tokens replace every hardcoded `text-white`.
- awaiting_approval moves from warning-amber to brass everywhere.

### Type

- Display: **Cabinet Grotesk** 700/800 (page titles, big numbers, wordmark).
- UI/body: **Switzer** 400/500/600 (everything else).
- Data: **JetBrains Mono** 400/500 (ids, costs, tokens, durations, timestamps,
  logs, exit codes). `tabular-nums` wherever digits align.
- All three are free (Fontshare / OFL), self-hosted woff2 via propshaft
  (~20KB per weight; 7 files total ~140KB).

### The seal mark

SVG, three sizes (14/22/150): outer notched ring (`stroke-dasharray`), thin
inner ring, center dot, always `var(--brass)`. Used for: brand mark, approve
buttons, "sealed by" chips, thread seal events, board "Waiting on you" column,
awaiting timeline nodes.

## IA restructure

Sidebar rail (icons + labels, collapsible): **Inbox** (unread badge), **Board**,
**Runs**, **Projects**, **Library**, pinned projects section, Admin + account
at bottom. Top bar per page: breadcrumb, centered command bar (Cmd+K), presence
avatars, Launch.

- Home (dashboard#index) becomes the Inbox.
- /tasks becomes the Board (kanban: Draft, Ready, Running, Waiting on you, Done).
- Activity page folds into the Inbox as an "everything" tab.
- Project accordion tree leaves the sidebar; projects get pinning instead.

## Core-logic changes (model/view layer only - executors, runners,
## WorktreeManager, ExecuteRunJob step-walking stay untouched)

### 1. Notifications become data (enables Inbox)
Today NOTHING is per-user: no notifications table, no read state, zero
`read_at` anywhere; mentions are parsed (`Comment#mentioned_users`), fired at a
webhook (`NotifyJob`), then discarded.
- New table `notifications`: user_id, event_id FK, read_at, created_at.
  Fan out on `Event.record` to participants (run starter, commenters,
  mentioned users, approvers). Index on (user_id, read_at).
- Nav badge = current_user's unread count (replaces global
  `awaiting_approval_count`).
- Mentions keep the webhook but also persist as notifications; task-comment
  mentions stop being silently dropped (today they require a run).

### 2. The thread unifies three logs (enables the Room)
Today comments, `events`, and `approval_events` are three parallel records;
events never broadcast; `run.awaiting_approval` - the single most
notification-worthy transition - produces NO Event row (it's in
`NotifyJob::EVENTS` but not `Event::ACTIONS`).
- Add `run.awaiting_approval` (and `run.resumed`, `step.sealed`) to
  `Event::ACTIONS`; emit from the existing controller/job emission points.
- Broadcast events into `#run_discussion` the same way comments broadcast
  (`broadcast_append_later_to`), rendered as compact muted rows; seal events
  get the brass treatment.
- Render `approval_events` history into the thread (keep the table as the
  audit source; absorb its display).
- Coalesce consecutive step-passed events client-side ("Steps 1-3 passed").

### 3. Per-user appearance settings
Today theme is localStorage only; users table has no prefs column.
- Migration: `users.settings` JSON (theme, accent, density).
- Layout renders `data-theme` / `data-accent` / `data-density` server-side
  (kills the theme flash); logged-out falls back to the current inline script.
- Account page gains an Appearance card (theme segmented control, accent
  swatches, density toggle). AccountController permits the new keys.

### 4. Command palette v2
Today Cmd+K is a launch-only form (no search, no results, no keyboard nav).
- Fuzzy search across runs, tasks, projects, workflows, skills + actions
  (approve, retry, jump to inbox) + navigation. Keep the launch flow as the
  default action on free text.

### 5. One component kit (fixes from the audit)
- One form-field partial replaces ~40 verbatim copies of the input class
  string (admin_settings' local `field`/`label`/`hint` vars are the seed).
- One table treatment (kills the users/index `rounded-xl` variant); card
  partial adoption goes from ~50% to all; one slide-over partial replaces the
  three copies in steps/_template_panel, _skill_panel, _file_panel; one
  details-menu partial replaces the two divergent dropdowns.
- Fix dead `bg-surface-muted` token (currently renders NOTHING on 6 screens:
  skills/show, _skill_md_editor, skills/_form, _diff_step_row, _replay_step,
  _diff_step_side) - map it to --bg-input or add a real token.
- Kill hardcoded colors: `bg-black/50` + `bg-black/60` scrims (one token),
  `text-white` on buttons (use --on-accent), `steps/_type_pill` second color
  map (use `type_badge`).
- Style the replay filter checkboxes (only unstyled inputs in the app).

### 6. Responsive + outward surfaces
- Nine screens use `grid-cols-2` with no breakpoints; add stacking. Shell
  collapses to icon rail, then a sheet.
- The public shared-run page (the ONLY externally visible surface) gets the
  brand: wordmark, seal, tokens. Keep its redaction boundary (no runs/
  partials reuse).
- Login page gets the seal + new type (keep the circuit animation concept).

## Rollout (each phase shippable alone)

1. **The language** - tokens, fonts, seal mark, component kit, shell/nav,
   server-side appearance settings. Every screen reskinned; nothing moves.
   **STATUS: shipped on this branch.** Follow-ups deferred from the sweep:
   - Cost/Duration columns in shared/_runs_list need run_steps preloaded by
     its callers first (runs#index, projects/_section_runs, workflows/show);
     same preload fixes a pre-existing N+1 in dashboard/_run_row usage_stats.
   - Consider a :warning btn variant (steps/_form "Switch anyway" currently
     uses :danger).
   - The card partial appends class: after its own p-5 and hardcodes
     border-edge, so padding/border overrides depend on stylesheet order;
     fine today, formalize if it bites.
2. **The room** - unified thread on the run page: events broadcast into the
   feed, approval history absorbed, thread-rail layout, brass seal treatment.
   Preserve the broadcast contract (#run_header, #run_info, #run_context,
   #run_steps_list, #run_step_<id> ids + partial paths + locals).
   **STATUS: shipped on this branch.** Notes: run.approved/run.rejected
   Events stay recorded for the Activity page but are THREAD_HIDDEN in the
   run feed; the ApprovalEvent row tells the decision with its comment.
   Step-passed event coalescing deferred (it would need new emission points
   inside ExecuteRunJob, which stays off-limits).
3. **The inbox** - notifications table, mention fanout, read tracking, new
   home screen, honest badges, activity fold-in.
   **STATUS: shipped on this branch.** Notes: fanout covers run.failed and
   comment.created (mention outranks reply via the unique-index dedupe);
   awaiting-approval stays a live query, not notification rows. The
   Activity page survives as its own nav item rather than folding in - the
   recent-activity card already covers the inbox's "everything" glance.
4. **The board & the palette** - tasks kanban, command palette v2, branded
   share page, workflow editor cleanup (inspector density, starter gallery
   dedupe).

## Standing constraints

- Never modify StepExecutor internals, app/services/runners/*, WorktreeManager,
  or ExecuteRunJob's step-walking logic.
- `turbo_confirm` only for destructive actions.
- Comment commentable types stay allowlisted (`Comment::COMMENTABLE_TYPES`).
- No em/en dashes in any file content.
