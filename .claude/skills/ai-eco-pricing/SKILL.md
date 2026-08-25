---
name: ai-eco-pricing
description: How economic wants are priced — ValueOf's cost terms, the energy price ladder, displacement, total economic power, and the growth premiums. Load before touching any eco gain or cost term.
---

# Eco pricing — the arithmetic behind every economic Want

Files: `manager/brain/market/{price,want_energy,want_mex,want_tech}.as`.
Read `value-paradigm` first; this is its economic half made concrete.

## ValueOf — the one pricing function

`value = gain / (mCost + tCost)`, in `price.as`.

| Term | Composition |
|---|---|
| `mCost` | `costM*MCostScale + costE*EPriceCostAt(buildSec) + areaCells*apex_space_m` (+ `SpaceRentM(site,cells)` where the caller knows the site) |
| `tCost` | `(walkSec + buildSec)*Wage + displacedM` (+ the E-drain throttle charge) |
| `buildSec` | `BuildSecondsAt(def, EffBP(bp))`, then floored by the metal FEED time `(costM − bank/2)/income` |
| `Wage` | `metal.income / workerCount` — one builder-second of forgone flow |
| `EffBP` | solo BP + `apex_assist_share` of the rest of the fleet; Requests folds joiners, so big builds really are faster |
| `MCostScale` | forgiveness ramping from a half-full metal bank down to 0.2x — a bank still filling forgoes little |

## displacedM — what a build postpones

`UpDemand() * duration * share`, `share = costM/(income*duration)` clamped to 1.
Extractors are exempt (they ARE the stream). At share 1 the old feed-bound
formula is recovered exactly; a cheap fast build charges near nothing.

It formerly fired ONLY in the feed-bound branch, so a def with a huge
buildtime (an AFUS) kept income "fed" the whole way, never tripped the gate,
and paid NOTHING for the upgrades it delayed — the same afus priced t=15319
and t=904 in one game.

## The energy price ladder

`EPriceFloor` (converter arbitrage, solved for P, restricted to converters we
can place) → `EPrice` (GAIN: stall premium `excess*metal.pull/eInc`) /
`ECostSpot` (COST: premium only above balance) → `EPriceAt`/`EPriceCostAt`
decay premium→floor over `apex_e_response/buildSec`. `EPriceCostAt` returns 0
outright while the E bank is full and income exceeds pull.

## EcoPowerM — the shared denominator

`metal.income + (energy.income − StandingConvCap()) * BestConvRatio()`: total
economic power in metal/s. BOTH growth premiums divide by it. Measured against
its own economy each premium saturated differently (a fusion took the full 9x,
a moho 1.6x) — a denominator artefact, not a fact about the game.

- `apex_mex_growth` (8) in `want_mex.as` and the mexup half of `want_tech.as`
- `apex_energy_growth` (8) in `want_energy.as`, on `makeE*BestConvRatio`
- `ConvUpDemand()` = tier's unlock on the ENERGY side, `ConvertibleE * (best
  ratio in game − best ratio we can place)`. `ProposeTech`'s demand is
  `UpDemand + ConvUpDemand`; without the second term a map with no metal spots
  has UpDemand identically 0 and NO T2 lab is ever proposed.

## Arithmetic worth remembering

- moho ~620 m for +12 m/s: payback 52 s, **0.0194 m/s per metal**
- fusion ~4900 m for +14.3 m/s at the game's 70:1 conversion: payback 343 s,
  **0.0029 per metal** — an order of magnitude behind a moho
- cormakr converts 70 E→1 M/s for ONE metal; cormmkr 600 E→10.3 M/s for 370.
  T2's edge is space and toughness, not ratio.

## Traps

- **NEVER cache a zero** in a lazy catalog scan keyed on `Catalog::gAvailable`
  — availability is frame-dependent (the DLL's `IsAvailable(frame)`), and an
  early call latched `BestConvRatio` at 0 forever, silently collapsing
  `EcoPowerM` to metal income. Same shape in `LineMeans`/`FoeSpeedCap`.
- Do not charge near-free claims (50m mexes) through `UpDemand` — it
  double-counts income `FreeMetalFlow` already frees.
- A premium priced at decision time and paid over a 7,000 s build is wrong
  twice; always price the gain through `EPriceAt(buildSec)`.

## Tunables

`apex_space_m` (1.0) · `apex_assist_share` (0.5) · `apex_conv_horizon` (300) ·
`apex_e_response` (45) · `apex_e_lookahead` (30) · `apex_e_headroom` (1.75) ·
`apex_mex_growth` (8) · `apex_energy_growth` (8) · `apex_tech_pipe` (2.0) ·
`apex_eco_survival` (1) · `apex_join_min_m` (500)

## Log lines

`apex: efloor` (gate on `apex_efloor_diag`) · `apex: tech-diag ... upD=` ·
`apex: mexdiag` · `apex: eco-status` · `apex: decide <unit> -> <want> v=…`
