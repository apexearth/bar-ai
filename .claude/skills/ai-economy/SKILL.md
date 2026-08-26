---
name: ai-economy
description: Who decides energy, fusion, converters, reclaim, and mex upgrades — the eco pipeline's owners, gates, log lines, and tunables
---

# The economy pipeline — what owns what

All economy decisions are Wants in the Brain market: `manager/brain/market/`.
Proposers are pure, `decide.as` ranks, `execute.as` is the only spender.

> **The kill phase (docs/20-brain-overhaul.md) DELETED the whole leaf layer.**
> `manager/builder/{mexguard,fusion,converter,obsolete,share,statics,nano,
> rules_hold,rules_optional,defcap}.as` and `manager/factory/{techlead,
> airsupport}.as` no longer exist, and neither does `AlwaysEco`. Many tunable
> comments in `tunables.as` still name those files — the comment is the stale
> part, not the tunable. Check a path exists before believing any doc that
> names one, this file included.

## Ownership

| Decision | Owner | File |
|---|---|---|
| Energy: which rung, how much | `ProposeEnergy` | `market/want_energy.as` |
| Converters | `ProposeConvert` | `market/want_energy.as:334` |
| Storage | `ProposeStore` | `market/want_energy.as:390` |
| Build-power demand | `BPGap()` — income headroom + bank backlog + ordered backlog, minus `BPCapacity()` | `market/want_energy.as:287` |
| Overflow sense | `OverflowM()` | `market/want_energy.as:320` |
| Mex claiming, walk safety | `ProposeMex` | `market/want_mex.as:246` |
| Mex upgrades (moho) | `ProposeMexUp` | `market/want_tech.as:54` |
| Tech plants | `ProposeTech` (`funded` discount — see the coupling section) | `market/want_tech.as:102` |
| Factory plants, geothermal | `ProposePlant` / `ProposeGeo` | `market/want_plant.as` |
| Nano turrets | `ProposeNano` | `market/want_nano.as` |
| Reclaiming our own | `ProposeReclaimObsolete`; blocked-slot variant default OFF | `market/want_reclaim.as` |
| Where an eco build stands | `FarmSlot` on the base lattice; `BigEnergySite` for fusion-tier | `market/sites.as` |
| Pricing (the one currency) | `ValueOf`, `EPriceFloor`, `Wage` | `market/price.as` |
| What we own | `gAssetsM`, `gProtM`, `gBPM`, `gOwnGen` | `market/census.as` |

## The architecture in one paragraph

Energy demand is NOT read off `energy.pull` alone — pull is THROTTLED demand
(factories slow on a short grid, pull falls, the grid self-reports "fine" while
starving). Demand is priced against metal income and the conversion floor
instead. Generation never pauses; converters are what modulate on waste.
Everything competes in one currency, `value = gain / (mCost + tCost)`, and the
category roulette (see `ai-auction`) draws proportionally rather than argmax.

## THERE IS NO FLOOR ANY MORE

`Builder::AiMakeTask` is holds → `Brain::Decide` → **idle**. There is
deliberately no fall-through to `aiBuilderMgr.DefaultMakeTask`, and the old
`AlwaysEco` never-zero floor was deleted with the leaf layer. A constructor the
market has no answer for does nothing at all. This bites the rear eco
specialist hardest: `Role::DefenceAllowed()` forbids it ground defence and
`apex_eco_army_mul` (0.03) cuts its army target to 3%, so it has the fewest
want sources of any player and the least to fall back on.

## The economy is coupled to the ARMY TARGET — in both directions

The full statement and its three laws are in the `ai-military` skill
("How much army"). What the economy side has to know:

- **Economy is the basis of the army target.** `ArmyTarget` is built from
  `EconAssetsM = gAssetsM - gProtM - gBPM` (`market/army.as`, `census.as`).
  Every mex, generator and converter that finishes raises the army the AI
  thinks it needs. That coupling is deliberate.
- **Defence and lathe are NOT in that basis, on purpose.** Both answer demand
  rather than create wealth, and neither can ever count toward `ArmyValue`
  (which is mobile non-builder units only), so leaving them in made each one
  raise the target that bought the next. If you add a structure class that is
  an ANSWER to demand, subtract it in `EconAssetsM` as well.
- **Eco growth is a way to SATISFY an army shortfall, not just a cause of it.**
  Metal/s is one of the three amplifiers (with build power and tech). A gap
  answered only by more lathe is the failure mode measured on 2026-08-25 —
  37% of all metal in nano turrets and no T2 in 5 of 8 games.
- **`ArmyGapStream()` (`want_mex.as`) is how the gap prices as a COST**: a slow
  eco build is charged for the army production it postpones. It is the same
  quantity, entering the other side of the ledger — do not add a second one.

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
