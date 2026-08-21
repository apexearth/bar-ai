---
name: ai-placement
description: Where buildings land — base bands, nano gravity, the advsol pack, defence placement gates, site safety vetoes
---

# Placement — where things get built

## Ownership

| Decision | Owner | File |
|---|---|---|
| Base grid / bands (ECO band, rear "deep band") | `Base::Spot`, `BandSpot` (deep band = the BACK of the base on the home→enemy axis) | `manager/baseplan.as`, `builder/nano.as` |
| Expensive builds near nanos ("nano gravity", his metaphor) | `NanoCluster` centroid consumed by: fusion direct path + pool-post, gantry, EcoNano big-build, converters | `builder/nano.as`, `fusion.as`, `statics.as` |
| Advsol pack | Requests chokepoint: chain onto kin ONLY within `apex_advsol_home_r` (1600) of home; no near-home seed → deep band founder ("they should be behind our base") | `builder/requests.as` |
| Nano turret sites | `NanoSiteAt` (pack near factory, snap to nano grid, reserve) | `builder/nano.as` |
| Reactor spacing | `SectionSafeSpot`/`ReactorBatchOK` (chain-blast sections; tighten-to-batch) | `builder/fusion.as` |
| Defence allowed here? | `DefenceAllowedAt`: crowd cap → static-AA bypass → BaseRaided PANIC (budget suspended) → rear veto (fwd<0) → front share vs local share budgets | `military/defenceline.as` |
| Mex guard tier & site | `MexGuardWanted` (forwardness-scaled count), `MexGuardTower` (income-tiered def) | `builder/mexguard.as` |
| Site safety | `ThreatFor` = threat map (mostly dead) → LOS foes count → geometric PastFront fallback; `MexHeat` relaxes it for mexes | `builder/sitesafety.as` |
| Which mex to claim | engine offer + the walk cap (a far mex offer swaps for a near open spot at election — mid-walk re-elections can't fix it, same-build-type answers are ignored) | `builder/maketask.as` |

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

`apex_advsol_home_r`/`apex_advsol_pack_r` · `apex_def_panic` ·
`apex_local_def_share` (0.10) · `apex_mex_walk_cap` (1500) ·
`apex_nano_pack_r` · `apex_reactor_spacing/tight`
