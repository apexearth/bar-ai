---
name: ai-build-arbitration
description: How a builder gets its job — the AiMakeTask ladder order, Brain wants and budget, the Requests governor, and where a new rule may sit
---

# Build arbitration — who claims a constructor

The single scarcest resource is constructor time (see CLAUDE.md "The path
fires"). Three layers decide every builder's job, in order.

## Layer 1: the ladder (`manager/builder/maketask.as`)

`MakeTaskInner` is an ORDERED list; the first rule to return a task wins.
Current order (top → bottom): commander rules → hold/abandon safety → the
energy lane → mex-upgrade lane → EcoFusion/converter (adv cons) →
**Brain::Decide** (macro ranking; a deferral stops the ladder) → `AlwaysEco`
floor → OptionalWork (phase-gated one-offs) → screens/vetoes on the ENGINE
OFFER (`aiBuilderMgr.DefaultMakeTask`) — including the STORE veto and the mex
walk cap — → scavenge → fallbacks.

**Where a new rule goes in this list IS the design decision.** Anything above
DefaultMakeTask displaces mex expansion. Rules that SPEND are never free.

## Layer 2: the Brain (`manager/brain.as`, `brain/budget.as`, `targets.as`)

Rules propose Wants (value, cost, def); one arbiter ranks them by a
proportional draw (roulette, not argmax — argmax starved every non-#1 want).
Category budgets (ARMY/DEFENCE/ECONOMY/BUILDPOWER) come from `targets.as`
shares through the RawTarget multiplier stack (persona, stance, deficits).
`Brain::UnderBudget`/`ShareOf`/`TargetShare` are the public reads.

## Layer 3: the Requests governor (`manager/builder/requests.as`)

THE chokepoint every posted build passes: capability check (asker CanBuild),
site dedup (`CoverFor`), fold-onto-nearby (`JoinFor`), and `EffectiveCap` —
income-wide in-flight cap AND the duplicate rule: a second simultaneous copy
of a def requires its full cost banked (`apex_dup_bank`); advsolars are
strictly serial. The advsol PACK (stand together, near home, rear band
founder) also lives here.

## The re-election trap (memorize this)

`AiMakeTask` re-runs for every builder not yet in build range, every update.
A rule that Enqueues fresh on each call creates one orphan per tick (measured
15 orphans/3min). Return an existing task (`Requests::Take` joins), or
remember what you placed. Reevaluate only reassigns on a DIFFERENT build
type — a same-type better answer is ignored mid-walk (why the mex walk cap
works only at election time).

## Log lines

`apex: con-veto ...` (safety refusals) · `Requests` refusal census
`created/joined/covered/full` · `apex: brain ...` want elections ·
`apex: defcap share=...`

## Tunables

`apex_dup_bank` (1.0) · `apex_advsol_serial` · `apex_request_drain` ·
`apex_con_tasks_each` · `apex_greed_cons` · con curves in Policy::ConLog*
