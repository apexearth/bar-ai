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
| Where a plant (gantry, air plant, tech lab) lands | `LatheSite`: one probe per nano block, the legal footprint scored on standing lathe PLUS room for the ring the line is due (`RoomBPAt`: `PackSlots` in probe mode, capped at `NanosDueFor` -- his 2026-09-20: not against a wall with no room for turrets, preferably where turrets already stand), snapped to the cell C++ keeps; a ground plant's doorway must face out; the interior site is the fallback. Log `apex: lathe-site ... stand= room= due=` | `brain/market/sites.as` |
| The nano core | `PackSlots` walks from the plant's heart-facing edge (`PackHeart`), resumes where the last slice stopped (`PackResume`) -- one turret core, plants on its rim | `brain/market/nanopack.as` |
| A plant the core swallowed | moves: priced in the reclaim market as room (footprint + doorway) against the line's downtime, `PlantEnclosure` = least-filled of beyond-doorway and both flanks; `retire=false` so the re-buy is not discounted. Log `apex: plant-walled` | `brain/market/want_reclaim.as` |
| Advsol pack | Requests chokepoint: advanced solars are STRICTLY SERIAL whatever the bank (`apex_advsol_serial`) — a second asker folds onto the live site through `JoinFor` instead of opening another, and the pack rule keeps them adjacent | `builder/requests/governed.as` (`EffectiveCap`) |
| Nano turret sites | `ExecuteWant`'s `WK_NANO` branch: the working army line furthest short of its ceiling-weighted flow share NET of the lathe already on it (`LineSiteFor`, 09-18 -- `NeediestLine`'s floored number is the count's currency and ties every line once the economy is spending, tie = oldest lab), a sink frame only while positive, a bare reactor frame over a served line, else the biggest line | `brain/market/execute.as` |
| The lattice itself | `CCircuitAI::LatticeOf`: per def, world axes, pitch = footprint, phase = the base anchor's CORNER (so 6-cell labs and 3-cell nanos share edge lines). Snapping is idempotent -- the parity is in the phase, not applied after rounding. Applies everywhere on the map, not only inside `GRID_RANGE`. Script asks `ai.SnapToLattice(def, pos)`; there is no script-side copy of the rounding | `CircuitAI.cpp`, `manager/lattice.as` |
| A taken lattice slot | C++ `IBuilderTask::Execute`: rings of the def's lattice (`LatticeNeighbour`, 8 rings / 200 probes, nearest free first, each probe ONE build square wide with the commit's own predicate) before the 1600-elmo square search -- and the square search's answer is put back on the lattice (its cell or a neighbour); only when none is free does a building stand off the row, logged `apex: off-lattice`. `CBNanoTask` used to override this with a private square search: that was the "nano one space away" | `cpp/.../BuilderTask.cpp`, `NanoTask.cpp` |
| Is the base tiled? | `python tools/tiling.py <run> --show` -- ALIGNED (nearest kin a whole number of pitches off on both axes), PHASE (one residue per def), FOREIGN (edge gap to the nearest other def, in squares). The `apex: tiling flush=` line cannot see a one-square miss | `tools/tiling.py`, `apex: placed` lines |
| Who may stand flush | `config/standard/block_map.json`: only a lab's apron (and mex/geo upgrade room) keeps ground now. LLTs, reactors, radar and every unlisted def had 5-8-cell yards that refused converters, storages and labs beside them (his 2026-09-16: "you want things to be very tight"). **Every `not_ignore` list carries `mex`, `geo`**: metal and geo spots are blockers of those types, and a list without them let the ring search put an LLT on a spot (his Frozen Ford game, 2026-09-20). `python tools/spotcheck.py <match>` is the census; `apex: spot-squatter` is the in-game detector and `ProposeReclaimSquatter` prices the reclaim | `block_map.json`, `want_reclaim.as` |
| Ground the reach veto refused | `NearBlocked` / `ProbedSite` -- energy, convert, sense/defence, nano pack cells and the idle wreck fallback all honour the C++ mark; a path that does not re-elects the same unreachable point forever (measured: 27 converter deaths at one point, 1,624 wreck trips). The mark carries the def since 09-18 (S35): `NearBlockedFor(p, def)` for a footprint probe, so a wind's refusal no longer bans the gantry's block | `brain/market/execute.as`, `nanopack.as`, `builder/reclaim.as` |
| Reactor spacing (chain-blast) | `FarmSlot`: a big generator's same-def cluster caps at HALF its standing fleet, never under 2, and clusters part by a blast-scale aisle rather than a walkway ("better if only half our economy blows up"). Foreign-def lattice spacing is untouched | `brain/market/sites.as` |
| Defence allowed here? | `ExecuteWant`'s `WK_PROTECT`/`WK_SENSE`/`WK_AIRDEF` branch is THE chokepoint -- deliberately not the proposers, because three separate gain branches each carried their own veto and gating two still let claws through. Classified by the DEF's surface threat, never by spotId | `brain/market/execute.as` |
| Keep-out gaps (alliance perimeter) | `KeepOutUpdate`: the convex hull of every allied seat's eco/nano/lab buildings (humans' too), scaled up to the GROWTH ZONE (room for as many buildings again as the alliance built over the last payback window, `apex_reclaim_amort`, sized from its peak count; clamped halfway to the enemy), pushed out by the enemy's seen reach, sampled every half light-tower reach; a sample is open when allied gun power there (`PfCoverPoint`, ours + `GetAllyDefences`) is under the team wave. Open runs are cut into one-light-tower pieces; each piece goes to the nearest of our AIs or its team-board claimant (`KO_BOARD`), and the owner's fill offers its most exposed sample as a keep site that takes the wall's demand pull (`KoShape`). `KoWrongGun` drops a gun that cannot stand before the threat assigned to that piece arrives, and a basic tower against their T2 while a T2 gun can. No rim/ring/wall slot or net alternative inside the growth zone (`KoInsideGrowth`; extractor guards and front sites exempt). When the seats' defence budgets cannot hold the whole ring, only the worst `offer` pieces are owned; the rest are `deferred`. Logs `apex: keepout scope=ally`, `keepout-gap`, `keepout-leak`, `keepout-sum`; post-game `tools/keepout.py` | `brain/market/protect_keepout.as` |
| Mex guard tier & site | priced as ordinary protect wants over the mex's stake; no separate mex-guard rule survives the overhaul | `brain/market/protect_*.as` |
| Guns in knots, facing what comes | every defence site's prevented loss x `KnotKappa`: 1 + (standing gun cover there, ours and allies')/(knot wave) until the knot beats the wave (seen raider metal, floor two of this gun; a gate's is its own threat), then wave/cover. `KnotSites` offers one site per cluster of our guns. The siege hazard is spread over 12 bearings by `FaceAt` (start prior + our losses + walking formations seen, mean 1). Basefront picks its slot by face x kappa. Logs `apex: defknot`, `apex: defface`, `knot= kappa= sup= face=` on `defplace`, `xKnot= sup= xFace=` on `defwhy`, `knot= joined= bestKnotGain=` on `defsite` | `brain/market/protect_knot.as` |
| Site safety | `ThreatFor` = threat map (mostly dead) → LOS foes count → geometric PastFront fallback; `MexHeat` relaxes it for mexes | `builder/sitesafety.as` |
| Rising lava | `Lava::` learns the tide from the gadget's `lavaLevel` param and answers `Eta(height)`. `ProbedSite` refuses ground that floods before a build pays, then retries without the filter; the C++ site predicate refuses anything already under the surface (farm builds only -- fixed sites are filtered in script). Inert off a lava map | `manager/lava.as`, `brain/market/sites.as`, `cpp/.../BuilderTask.cpp` |
| Which mex to claim | priced in the market: `ProposeMex` ranks spots, and the walk is charged as builder-time in `ValueOf`'s `tCost`, so a far mex is dearer than a near one by the travel term rather than by a distance cap | `brain/market/want_mex.as` |

## Principles that keep recurring

- Eco/energy behind the base; defence on the line; nanos tight with lanes.
- Streets (`IsInBaseLane`, `Base::LaneHalf`): forward of the anchor only, 720
  apart, as wide as twice the widest ground hull we FIELD (`Lattice::AisleW`,
  monotonic; 96 for a bot base, was 256 from the widest buildable hull --
  his 09-18 "we're wasting a lot of space"). Republished to C++ when it grows.
- Placement rules must RESERVE sites (`Base::ReserveSite`) or the same ground
  gets picked every period.
- `FindBuildSiteNear` returns any legal site — snap/verify, never trust the
  raw point (slopes, water, inside buildings).
- An uninitialized AIFloat3 is (0,0,0) and IS on-map — always seed invalid
  (`-1`) before conditional fills.

## Log lines

`apex: defence refused here -- N standing, front/rear` ·
`apex: nano sited at the <big> build` · `apex: con-foe-diag near=...` ·
`apex: spots t= n=` (the map's spot table, once) · `apex: spot-squatter`

## Tunables

`apex_advsol_serial` · `apex_dup_bank` · `apex_reactor_spacing/tight`

(Six placement knobs this skill used to list were deleted 2026-08-31 — `git log
-p` on this file has the names. `tools/dashboard_audit.py` is the live list;
never re-add a tunable name from memory.)
