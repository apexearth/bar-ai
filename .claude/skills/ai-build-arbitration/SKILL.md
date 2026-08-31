---
name: ai-build-arbitration
description: How a builder gets its job — the arbiter owns the choice (the old AiMakeTask ladder is gone), Brain wants and budget, the Requests governor, and where a new rule may sit
---

# Build arbitration — who claims a constructor

The single scarcest resource is constructor time (see CLAUDE.md "The path
fires"). Three layers decide every builder's job, in order.

## Layer 1: the entry point (`manager/builder/maketask.as`)

**THE LADDER IS GONE. `MakeTaskInner` no longer chooses what to build.** Read
`manager/builder/maketask.as:51` — in full it is: rezzer flee → rezzer chain
(rez bots only) → return any BUILDER task the unit already holds → **`Brain::
Decide`**. Nothing else. No energy lane, no mex-upgrade lane, no EcoFusion or
converter branch, no `AlwaysEco` floor, no OptionalWork, and no screens on
`aiBuilderMgr.DefaultMakeTask` — the overhaul (docs/20-brain-overhaul.md) moved
every one of those into the arbiter, and `check.py` now fails a build that calls
`DefaultMakeTask` outside it at all.

What survives of the old order is only SAFETY, and it creates no work: a rez bot
flees, and a constructor already on a task keeps it.

**So "where does my new rule go in the ladder" is the wrong question now** — it
was the design decision and it is not one any more. A new behaviour is a Want
with a price, ranked against every other Want in Layer 2. If a rule seems to
need to run before the arbiter, that is a statement that its price is wrong.

This section described the pre-overhaul ladder as current until 2026-08-31, and
an agent reading it would have tried to insert a rule into a list that no longer
exists. Verified against the tree that day: `MakeTaskInner` at
`maketask.as:51`, and the military one at `military/hooks.as:78`.

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
