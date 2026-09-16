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
| The lattice itself | `CCircuitAI::LatticeOf`: per def, world axes, pitch = footprint, phase = the base anchor's CORNER (so 6-cell labs and 3-cell nanos share edge lines). Snapping is idempotent -- the parity is in the phase, not applied after rounding. Applies everywhere on the map, not only inside `GRID_RANGE`. Script asks `ai.SnapToLattice(def, pos)`; there is no script-side copy of the rounding | `CircuitAI.cpp`, `manager/lattice.as` |
| A taken lattice slot | C++ `IBuilderTask::Execute`: rings of the def's lattice (`LatticeNeighbour`, 8 rings / 200 probes, nearest free first, each probe ONE build square wide with the commit's own predicate) before the 1600-elmo square search -- and the square search's answer is put back on the lattice (its cell or a neighbour); only when none is free does a building stand off the row, logged `apex: off-lattice`. `CBNanoTask` used to override this with a private square search: that was the "nano one space away" | `cpp/.../BuilderTask.cpp`, `NanoTask.cpp` |
| Is the base tiled? | `python tools/tiling.py <run> --show` -- ALIGNED (nearest kin a whole number of pitches off on both axes), PHASE (one residue per def), FOREIGN (edge gap to the nearest other def, in squares). The `apex: tiling flush=` line cannot see a one-square miss | `tools/tiling.py`, `apex: placed` lines |
| Who may stand flush | `config/standard/block_map.json`: only a lab's apron (and mex/geo upgrade room) keeps ground now. LLTs, reactors, radar and every unlisted def had 5-8-cell yards that refused converters, storages and labs beside them (his 2026-09-16: "you want things to be very tight") | `block_map.json` |
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
