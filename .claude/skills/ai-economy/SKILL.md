---
name: ai-economy
description: Who decides energy, fusion, converters, reclaim, and mex upgrades — the eco pipeline's owners, gates, log lines, and tunables
---

# The economy pipeline — what owns what

All paths live under `ai/apex/game-side/script/hard_aggressive/`. Thresholds
live in `policy.as` (Policy::) — never restate a default at a call site.

## Ownership

| Decision | Owner | File |
|---|---|---|
| "Is energy short?" | the energy lane (target = max(pull×headroom, mIncome×Policy::EPerMetal)) | `manager/builder/maketask.as` energy lane |
| Which generator rung | `HomeEnergy`/`HomeEnergyFresh` per-metal ranking + forced fusion | `manager/builder/mexguard.as` |
| Fusion yes/no | `EcoFusion` gates + forced-fusion (SteadyIncome ≥ 50, energy ≥ Policy::FusionMinEnergy 1000) | `manager/builder/fusion.as`, `mexguard.as` |
| "Never zero eco in flight" floor | `AlwaysEco` (fires only when no ENERGY and no CONVERT task exists) | `manager/builder/mexguard.as` |
| Converters | `EnergyConverter`/`EcoConverters`, self-gated on `EnergyWasting()` | `manager/builder/converter.as` |
| Reclaiming own generators | `EnergyReclaimable`: replacement standing + income cliff + pull padding + solars wait for a REACTOR (eco/tech lead excepted) | `manager/builder/obsolete.as` |
| Mex upgrades | Brain "mexup" want (exempt from eco damps) | `manager/brain.as` |
| Metal-full sink | `MetalSurplusIsReal` distinguishes rich from grid-down | `manager/builder/share.as` |

## The architecture in one paragraph

Energy demand is measured two ways because `energy.pull` is THROTTLED demand
(factories slow on a short grid, pull falls, the grid self-reports "fine"
while starving — the root cause of every "we suck with energy" era). The
metal-income-scaled target breaks that circularity; the deficit sizes how
many parallel generator sites may open; the Brain's "energy" want handles
allocation pressure; `AlwaysEco` is the floor that guarantees never-zero.
Both halves funnel through `HomeEnergy`/`Requests::Take`, whose dedup makes a
second asker JOIN the standing build.

## Log lines to read first

- `apex: energy pipeline -- eInc N below forecast M` — the lane firing, with the live target
- `apex: fusion-gate diag ...` — every fusion gate's state, once/period
- `apex: always-eco -- nothing eco in flight` — the floor caught a gap
- `apex: fusion posted to the pool` — an incapable asker delegated it

## Key tunables

`apex_e_per_metal` (20) · `apex_energy_headroom` (1.35) ·
`apex_fusion_min_energy` (1000, apexearth's number) ·
`apex_fusion_prefer_income` (50, his number) · `apex_reclaim_pad` (1.5) ·
`apex_reclaim_solar_e/advsol_e/wind_e` (500/2000/2000, his numbers) ·
`apex_always_eco` · `apex_advsol_serial` (strictly one advsol order at a time,
his rule)

## Traps

- A fusion costs ~21k ENERGY to build: starting one below the 1000 bar stalls
  the grid it was meant to fix.
- One T2 con = fusion queues behind mohos (measured 11-minute lag); a
  justified fusion floors the adv-con want at 2 (`share.as`).
- Reclaim eligibility must price the grid AFTER eating the victim, and solars
  wait for a standing reactor — both are apexearth directives with dates in
  the code comments.
