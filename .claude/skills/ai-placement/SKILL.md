---
name: ai-placement
description: Where buildings land — base bands, nano gravity, the advsol pack, defence placement gates, site safety vetoes Defence slots come from the TEAM hull and its walkable gaps (docs/32, protect_team.as).
---

# Placement — where things get built

## Ownership

| Decision | Owner | File |
|---|---|---|
| Base grid / bands (ECO band, rear "deep band") | `Base::Spot` (deep band = the BACK of the base on the home→enemy axis); axis, grid, reserve and state are its parts | `manager/baseplan/{spot,axis,grid,reserve,state}.as` |
| Expensive builds near nanos ("nano gravity", his metaphor) | `BigEnergySite` / `RefreshInsureCluster` pick the cluster; `ProbedSite` proves it | `brain/market/sites.as` |
| Advsol pack | Requests chokepoint: advanced solars are STRICTLY SERIAL whatever the bank (`apex_advsol_serial`) — a second asker folds onto the live site through `JoinFor` instead of opening another, and the pack rule keeps them adjacent | `builder/requests/governed.as` (`EffectiveCap`) |
| Nano turret sites | `ExecuteWant`'s `WK_NANO` branch: the hungriest working line (`NeediestLine`, the same arithmetic that BOUGHT the turret), else the biggest uncovered frame, else beside any factory | `brain/market/execute.as` |
| A taken lattice slot | C++ `IBuilderTask::Execute`: the def's own lattice rings (`CCircuitAI::LatticeNeighbour`, 4 rings, nearest free cell first) before the 1600-elmo square-by-square search -- his "a converter only builds up, left, down, or right... snap to a grid of the building's own size" | `cpp/.../BuilderTask.cpp`, `CircuitAI.cpp` |
| Ground the reach veto refused | `NearBlocked` / `ProbedSite` -- energy, convert, sense/defence, nano pack cells and the idle wreck fallback all honour the C++ mark; a path that does not re-elects the same unreachable point forever (measured: 27 converter deaths at one point, 1,624 wreck trips) | `brain/market/execute.as`, `nanopack.as`, `builder/reclaim.as` |
| Reactor spacing (chain-blast) | `FarmSlot`: a big generator's same-def cluster caps at HALF its standing fleet, never under 2, and clusters part by a blast-scale aisle rather than a walkway ("better if only half our economy blows up"). Foreign-def lattice spacing is untouched | `brain/market/sites.as` |
| Defence allowed here? | `ExecuteWant`'s `WK_PROTECT`/`WK_SENSE`/`WK_AIRDEF` branch is THE chokepoint -- deliberately not the proposers, because three separate gain branches each carried their own veto and gating two still let claws through. Classified by the DEF's surface threat, never by spotId | `brain/market/execute.as` |
| Mex guard tier & site | priced as ordinary protect wants over the mex's stake; no separate mex-guard rule survives the overhaul | `brain/market/protect_*.as` |
| Site safety | `ThreatFor` = threat map (mostly dead) → LOS foes count → geometric PastFront fallback; `MexHeat` relaxes it for mexes | `builder/sitesafety.as` |
| Rising lava | `Lava::` learns the tide from the gadget's `lavaLevel` param and answers `Eta(height)`. `ProbedSite` refuses ground that floods before a build pays, then retries without the filter; the C++ site predicate refuses anything already under the surface (farm builds only -- fixed sites are filtered in script). Inert off a lava map | `manager/lava.as`, `brain/market/sites.as`, `cpp/.../BuilderTask.cpp` |
| Which mex to claim | priced in the market: `ProposeMex` ranks spots, and the walk is charged as builder-time in `ValueOf`'s `tCost`, so a far mex is dearer than a near one by the travel term rather than by a distance cap | `brain/market/want_mex.as` |

## Principles that keep recurring

- Eco/energy behind the base; defence on the line; nanos tight with lanes.
- Placement rules must RESERVE sites (`Base::ReserveSite`) or the same ground
  gets picked every period.
- `FindBuildSiteNear` returns any legal site — snap/verify, never trust the
  raw point (slopes, water, inside buildings).
- An uninitialized AIFloat3 is (0,0,0) and IS on-map — always seed invalid
  (`-1`) before conditional fills.

## Log lines

`apex: defence refused here -- N standing, front/rear` ·
`apex: nano sited at the <big> build` · `apex: con-foe-diag near=...`

## Tunables

`apex_advsol_serial` · `apex_dup_bank` · `apex_reactor_spacing/tight`

(Six placement knobs this skill used to list were deleted 2026-08-31 — `git log
-p` on this file has the names. `tools/dashboard_audit.py` is the live list;
never re-add a tunable name from memory.)
