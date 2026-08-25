---
name: ai-army-composition
description: What the army is made OF — the four line classes, the composition target, and the range/speed/coverage multipliers that price a unit. Load before diagnosing a wrong unit mix.
---

# Army composition — the four lines and their prices

Files: `manager/brain/market/army.as` (the model) and the unit-pricing block in
`manager/brain/market/production.as` (where it is spent). Nothing here names a
unit; everything is read off catalog data.

## The four classes

| Class | Stands out on |
|---|---|
| `LC_TANK` | health per metal |
| `LC_REACH` | weapon range |
| `LC_DPS` | damage per metal |
| `LC_MID` | nothing dominant — a real role, what holds the line when shields are gone |

`LineClassOf` picks the axis with the highest ratio to the field mean, and
returns MID unless the winner clears `apex_line_edge` (1.15).

- Means (`LineMeans`) are taken over the **GAME's** own mobile combat units,
  not our army — a mean over an empty army classifies everything as middling.
- **DPS is not bound to script.** It is recovered as `power*power/health`,
  because the DLL builds `power = sqrt(dps)*dmg^0.25*sqrt(hp+shield)/128`.
  Every consumer normalizes, so the constants drop out.

## The target

30/25/25/20 (tank/mid/reach/dps) as shares of **army metal**, tracked by
`TrackLine`. `LineShortfall(cls)` is the proportional miss 0..1, spent as
`ppc *= 1 + apex_line_bite * LineShortfall(...)`. **Never a veto** — a class
over target simply stops being favoured. Tanks die first, so their share falls
and the term pulls back to them on its own.

## The multipliers on a unit's combat-per-metal

| Term | Meaning |
|---|---|
| `ShieldShare()` | tank+mid share of the line; scales the range bonus, so a fragile long-range unit fighting alone is not worth its range |
| `apex_range_worth * range/1000 * ShieldShare` | reach as free damage, bought only with shield to stand in front |
| `apex_speed_worth * speed/FoeSpeedCap()` | speed valued against the fastest ground combat unit the GAME offers — read from the catalog, NOT from what we have seen, because the assumption must hold while blind |
| `apex_cover_worth * CoverPerMetal(d) * PatrolShort()` | coverage = quantity x speed per metal against the sites we must watch; buys cheap fast bodies while thin, fades to zero as they arrive |
| `apex_los_worth * losR/1000` | sight, because every other sense reads zero while blind |

`PatrolShort` counts standing sites (mex spots + generators + plants) times
`FoeSpeedCap` as the need, and our fielded ground speed as the have.

## The budget

`ArmyTarget()` = `gAssetsM*apex_guard_rate + expectedEnemy*apex_match_ratio`,
where `expectedEnemy = max(seen census, (gAssetsM + ArmyValue()) *
apex_enemy_prior)` — a **symmetric prior**: pre-contact the census is blind,
and blind read as safe lost a game with three army units built.
`ArmyTargetFull()` is the same without eco-role suppression.

## Traps

- **Never cache a zero** in `LineMeans`/`FoeSpeedCap` — availability is
  frame-dependent; both recompute until the field is non-empty.
- Composition is decided HERE, not in `factory.json` — read the facqueue quota
  lines first for any "wrong units built" complaint.
- A class over target is deprioritized, never blocked; adding a veto here is
  the mistake the proportional shortfall exists to avoid.

## Tunables

`apex_line_tank/mid/reach/dps` (0.30/0.25/0.25/0.20) · `apex_line_edge` (1.15) ·
`apex_line_bite` (1.5) · `apex_range_worth` (2) · `apex_speed_worth` (0.5) ·
`apex_cover_worth` (1.5) · `apex_los_worth` (1) · `apex_enemy_prior` (0.25) ·
`apex_guard_rate` (0.15) · `apex_match_ratio` (1.2) · `apex_army_fill_s` (180)

## Log lines

`apex: facqueue ... quota:` (per-line have/want) · `apex: decide <unit> ->
<want> v=…` · `apex: rear-elect` / `apex: rear-specialist` (eco-role quality bias)
