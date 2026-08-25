---
name: ai-builder-crew
description: How many hands work one site — the request lifecycle, the income-derived in-flight cap and crew size, peeling, and the frozen-builder trap
---

# The builder crew (`manager/builder/requests.as`, `builder/maketask.as`)

`Requests` is the one place that decides whether a building may be started and
how many constructors may stand on it.

## The lifecycle IS the engine's task

The request record is an `IBuilderTask`, not a parallel structure, so it cannot
drift out of step:

| State | What it is |
|---|---|
| proposed | in the queue, `GetUnits()` empty — the next asker for this def here is handed THIS task |
| claimed | `GetUnits()` non-empty; a builder is walking |
| in-progress | `target` set — `SetTarget` runs when the nanoframe appears |
| cancelled | builder reassigned; the task keeps its place, i.e. proposed again |
| done/aborted | `DequeueTask` → `AiTaskRemoved` → `Forget` |

Every producer is seen, C++ ones included: all tasks go through
`CBuilderManager::Enqueue` → `TaskAdded` → `Register`.

## The numbers, all income-derived

| Function | Meaning |
|---|---|
| `InFlightCap()` | `metal.income / DRAIN`, min 2. **`DRAIN = 7.0` m/s is what one constructor pulls**, whatever it builds — so this is the total hands the economy can keep fed |
| `LiveSiteCount()` | live BUILDER tasks standing, min 1 |
| `FeedableCrew(def)` | `InFlightCap / LiveSiteCount`, times `apex_peel_eco_keep` for eco defs (makes energy / extracts metal / converts) |
| `SiteWorkerCap(def)` | `1 + costM/apex_site_cost_per_worker`, clamped down by `InFlightCap` **and by `FeedableCrew`** — the join rung |
| `PeelSurplus()` | per slow update, `RemoveUnit`s workers beyond `FeedableCrew` off any site with a standing nanoframe, 3 per tick, largest ids first |

`EffectiveCap` (duplicate gate, `apex_dup_bank`, advsols serial) is separate —
that bounds parallel SITES, not crew size.

## THE BIG TRAP — a parked constructor never re-elects

`IBuilderTask::Reevaluate` (`cpp/src/circuit/task/builder/BuilderTask.cpp`)
**does not call the script for a builder already within build range of its
task**, and `maketask.as` returns the held BUILDER task before `Brain::Decide`
is reached. So a constructor standing on a site proposes nothing, ever, until
that site finishes.

Crew size used to be cost-derived (`1 + costM/300`, i.e. seventeen workers on
one fusion), so every T2 constructor welded itself to a fusion and nobody was
left to bid a mex upgrade — **t2Mex 0 for a whole session**. Crew size is now
feed-derived, and the join rung and the peel rung use the SAME number
(`FeedableCrew`) so a peeled worker cannot walk straight back on; peeling
against one number while `SiteWorkerCap` admitted against another only cycled
them.

Corollary: any complaint of the shape "elections just don't happen often
enough" is a crew-size question, not an auction question.

## Log lines

`apex: request <new|join|...> <def> inFlight=N cap=N live=N new=N join=N
covered=N full=N tooFar=N` — **`join=` is the assister count**.
`apex: peeled N surplus assister(s) back to the auction (total N)`.

**Near-zero `peeled` with a high and climbing `join` is the frozen-builder
signature**: hands are going onto sites and never coming back off, so the
auction sees fewer and fewer bidders each election.

## Tunables

`apex_request_drain` (7.0) · `apex_site_cost_per_worker` (300) ·
`apex_peel_eco_keep` (2) · `apex_assist_release` (1, master for peeling) ·
`apex_dup_bank` (1.0) · `apex_advsol_serial`
