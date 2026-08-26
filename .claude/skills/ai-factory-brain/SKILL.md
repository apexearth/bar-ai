---
name: ai-factory-brain
description: What gets BUILT from factories — the facqueue executor, the production market, queue depth, plant choice, tech-lead election, and why factory.json is mostly not in the loop
---

# The factory brain — what comes out of the labs

## Ownership

| Decision | Owner | File |
|---|---|---|
| Which units a line makes | `Market::ConOrderFor` — floors first (escort, any-con, ceiling-con), then a proportional value draw over the plant's products | `manager/brain/market/production.as` |
| Line mechanics: adoption, Wait-hold, recruit abort, the order ledger, queue depth | `facqueue` | `manager/brain/facqueue.as` |
| Con counts | `ConsNeedAny` (2.7 + inc/44) and `CeilingConsNeed` (base + inc/25), both floors, both in-flight aware | production.as |
| Which plant to build / switch | C++ FactoryToBuild + `PlantApproved` backstops (T1-commit, income cap `FactoryTypeCap`) | `manager/factory/choose.as`, `switch.as`, `builder/sitesafety.as` |
| T2 timing | `RushReady` (energy ≥ Policy::T2Energy 800, or 400 with a reactor) + `MayPursueT2`/`T2ArmyReady`; NO tech lead in 1v1 (his rule) | `manager/factory/techlead.as` |
| T1-commit (duels, small maps) | `T1Commit` with plateau/enemy-T2/income releases | techlead.as |
| Team roles (tech lead, eco lead) | `RefreshLead` election; eco lead holds the slot from frame 0 pre-designation | techlead.as, `mexhold.as` |
| Adv-con sharing | `ShareAdvCon` (lead keeps AdvConsWanted/2, gifts one per teammate) | `manager/builder/share.as` |

`QuotaFor` is GONE (the overhaul kill). Anything still describing per-line
quotas or `quota:` log lines is describing code that no longer exists.

## The one thing to never forget

**While a line is driven, `factory.json` tier tables and `response.json`
decide nothing.** Attribute any "wrong units built" complaint to
`ConOrderFor`'s pricing first — the `apex: decide ... -> produce:` lines carry
the winning def, its value and its gain. Days were lost tuning factory.json
weights for a composition the market owned.

## How a line is fed — the cadence is the whole story

A driven line is parked on `TaskS::Wait(false, FQ_WAIT)` (10 s). **`IWaitTask::OnUnitIdle`
is a no-op** (`task/common/WaitTask.cpp`), so a plant that finishes its last
unit is NOT re-elected — nothing looks at it until the Wait times out. One
order per election therefore means one unit per `max(build time, 10 s)`, with
the plant idle for the remainder. Measured 2026-08-25 before the fix: real
factory lines held zero work in 50% of samples.

So the facqueue queues a **window of work**, not one order: `LineWindow()` =
`FQ_WAIT` × `apex_fac_queue` (1.5) seconds, and it asks `ConOrderFor`
repeatedly (slot 0, 1, 2 …) until the line covers it. Each slot is priced
separately against a ledger that already holds the slots before it, so floors
satisfied by slot 0 do not repeat.

**Measure the BUFFER, not the total** — `LineSeconds(line, fac, skipHead=true)`
drops the oldest ledger entry, the one being built. Measuring total work is a
bug that looks like it works: every unit an armlab makes takes 11–28 s
(armpw 11, armrock 13, armham 15, armck 23, armwar 28 at BP 150), so a single
order cleared a 15 s bar, the batch was 1, and the plant went empty the instant
it finished — apexearth, watched: *"once that unit is complete we are idle
until we queue the next unit."* Measured across three runs, line-empty samples:
50% (one order, only when bare) → 10% (total-work window) → **0%** (buffer
window), and 81% of samples have the next order already in hand.

## The order primitives — there is no "append one"

- `CmdBuildUnit(def, n, replace)` — `replace=true` issues one order with no
  options, which **wipes the queue it lands on** (only safe with nothing
  outstanding). `replace=false` SHIFT-appends, and `CFactoryCAI::GetCountMultiplierFromOptions`
  **multiplies SHIFT by five** — so this is never one unit.
- `CmdInsertBuild(def, front)` — CMD_INSERT at position `front ? 0 : 1`.
  Position 1 is behind the unit under construction and **ahead of everything
  else**. This is the only exactly-one append, and it is a FRONT insert.

Consequence: a batch is issued **back to front** so it comes out in the order
it was decided, and it lands ahead of work queued on an earlier pass. That is
also what puts an escort or a constructor floor in front of the army — those
are priced first, so they sit at the head of the batch.

## The order ledger is the only truth

`gFQPendLine`/`gFQPendDef` hold every order until the unit is **finished**
(`NoteProduced`). `CountQueued` lags sends by a whole order window
(`CAICallback::GiveOrder` only sends a net message), so it must never retire a
ledger entry — and anything adding `CountQueued` to `PendCount` **double
counts** once the order becomes visible. A never-landed order is retired by
drought instead: nothing visible, nothing produced, nothing sent for 60 s.

`ArmyInFlightM()` subtracts ordered-but-unbuilt army metal from the army gap.
Without it every slot of a batch — and every election inside the lag window —
prices against the same gap and buys it again.

## NANO TURRETS COME THROUGH `Factory::AiMakeTask` TOO

`CFactoryManager` owns its assist units, so the script hook fires for them.
A turret has no build options; adopted as a "line" and parked on the Wait it
puts its build power on **nothing at all**. Measured 2026-08-25: 56
`cornanotc` adopted as lines in one 29-minute game, 11,760 metal of build
power dead, and dead turrets never released their line (`ReleaseFactory` only
fires for `usage == FACTORY`) so the array grew to 65 entries.

`maketask.as` routes anything with an empty `Catalog::BuildsOf` to
`aiFactoryMgr.DefaultMakeTask`, which is the ONLY path to
`CFactoryManager::CreateAssistTask` (repair/assist/reclaim near the turret).
`tools/check.py`'s spend census allowlists that one call site — an assist
turret commits no metal, it applies build power to work already commissioned.

## Log lines

`apex: facqueue takes <plant> #id` (line adopted — a `cornanotc` here is the
bug above) · `apex: facqueue lines=N orders=… depth+pend: #id:Q+P/Ss` (per
line: visible queue, ledger, and seconds of work) · `apex: decide … ->
produce:<def> v=… (gain=…)` (what the market bought and why) · `apex: rush
team=N LEAD/follower …` · `apexphase: N -> M mInc=…`

## Tunables

`apex_fac_queue_brain` (master) · `apex_fac_queue` (queue depth as a multiple
of the re-election gap) · `apex_con_base`/`apex_con_per_m` ·
`apex_t2_con_base`/`apex_t2_con_per_m` · `apex_army_fill_s` ·
`apex_line_floor` (opportunity floor) · `apex_t1_commit` family ·
Policy::T2Energy/T2EnergyReactor

## Traps

- Factories consume orders in bursts at high sim speed (the GiveOrder lag);
  count what was SENT, never what is visible.
- Zero `facqueue takes` = the facqueue never took lines — check that before
  anything else.
- The `cpp/` tree is a partial overlay of modified files only. The full
  CircuitAI source, including every AngelScript binding, is under
  `vendor/engine/AI/Skirmish/BARb/src/` — `aiFactoryMgr`'s methods are
  registered in `script/FactoryScript.cpp`, not anywhere in `cpp/`.
