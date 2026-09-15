---
name: ai-risk-model
description: The measured risk model — threat, hazard, cover, stake, siege priors, and the survival discounts every deferred want is priced through
---

# The risk model (`manager/brain/market/coverage.as`)

One measured risk field feeds every protect price, every survival discount and
the exposure charge on immobile wants. Load before touching any defence,
tech or energy price.

## The field

| Term | Means | Units | Consumed by |
|---|---|---|---|
| `ThreatM(pos)` | size of the wave that ARRIVES here — sightings, floored by the loss field, floored by a raid→army gradient toward them | metal | `ShortfallAt`, defence pricing |
| `HazardAt(pos)` | how OFTEN lethal force arrives — max(loss/stake, gradient × foe/(foe+defended)), floored by `apex_risk_floor`, × `1/apex_exposed_loss_s` | per second | `ExpectedLossAt`, `StreamSurvival`, `TechSurvival`, defence gain |
| `ShortfallAt(pos)` | share of local threat our standing guns fail to stop: `(threat − CoverAt)/threat` | 0..1 | every risk product; a tower in reach lowers it |
| `ExpectedLossAt(pos, valueM)` | `valueM × HazardAt × ShortfallAt` | metal/s | `decide.as:108` charges it against EVERY immobile non-`WK_PROTECT` want (PROTECT is exempt — its gain already IS prevented loss) |
| `CoverAt(pos)` | adversarial cover: samples 6 bearings on the ring at `Military::FoeReach()` standoff and takes the **WEAKEST** — they pick where to stand. `CoverPointM` is the inner sum (turrets whose `gMaxRange` reaches, × `apex_def_trade`) | metal of wave stopped | shortfall, hazard, siege, rent |

## Stake — what is actually being defended

- `StakeAt(pos, r)` — our metal within `r`; mexes at capitalized stream
  (`income × extract × apex_stake_horizon_s`), not build cost.
- `FrontedStakeAt(pos, reach)` — plain `StakeAt(pos, reach)`. Distance only; a
  side test zeroed home towers, subtracting standoff zeroed nearly everything.
- `ShieldedStakeAt(pos, reach)` — what a forward post intercepts BEYOND its own
  reach, on the true enemy bearing; credited in proportion to the closure the
  post adds (`protect_sense.as`, `LineClosure`). Used by front and gate sites.
- **Wall slots are priced by the TEAM's gap, not by this** (2026-09-15,
  `protect_team.as`, docs/32): each bearing of the team hull carries whether
  their ground can walk in, the cover meeting it (ours and allies' guns),
  the metal behind it, the interior shared among the open holes, and the
  mex spots raids through it starve; `GapBehindAt` is the slot's stake and a
  walkable bearing faces the wave prior even at threat 0.

## Two priors, one function

`SiegeRiskAt(pos, priorFrac)` = `foe/(foe+defended) / apex_eco_raid_tau`, with
`foe = max(seen enemy army, (gAssetsM − gProtM + ArmyValue()) × priorFrac)`.
Our own turrets are EXCLUDED from the basis, or defences justify defences.

- `SiegeRisk` — `apex_siege_prior` (1.0). Worst case: they spent their whole
  economy on army. Answers *does a long bet have time to pay*.
- `SiegeExpect` — `apex_enemy_prior` (0.25). Answers *how much defence to BUY*.
  Buying against the worst case is a feedback loop (economy → assumed army →
  turrets → economy stalls).

## Survival discounts and rent

- `StreamRisk(pos)` — `max(HazardAt, SiegeRisk) × ShortfallAt`, cached 3 s.
  `StreamSurvivalOver(pos, T)` = `1/(1+risk·T)`. `StreamSurvival(pos)` uses
  `T = apex_stake_horizon_s` (300 s) and prices tech SITES; a mex pays it
  over its own delivery time (walk + build) since 2026-09-05, the horizon
  energy pays in `TechSurvival` — the fixed 300 s halved every home mex
  against the solar beside it. Cover includes posted guards
  (`Military::UnitCoverAt`), so a tower OR a posted unit in reach raises it.
- `TechSurvival(defId, askerBP)` (`want_tech.as:12`) — `1/(1+risk·T)`,
  `T = PipeLatencySec + (costM − bank/2)/income`. Blind (`!Front::FoeKnown()`)
  forces shortfall to 1. Applied to tech and, via `apex_eco_survival`, to
  energy.
- `SpaceRentM(pos, areaCells)` — rent for standing on defended ground: each
  covering turret's metal spread over its own coverage circle in 16-elmo
  cells, × footprint × `apex_space_rent`. Zero outside cover; rises as the
  perimeter fills.

## The tide, alongside

`Lava::RiskAt(pos)` (`manager/lava.as`) is a per-second rate in the same units
as `HazardAt`, combined into `StreamRisk` **outside its 256-elmo cache** (lava
risk follows elevation, which that cell cannot carry) and **never multiplied by
`ShortfallAt`** (no gun turns away lava). It is deliberately NOT in `HazardAt`:
that field drives defence gain, and a hazard turrets cannot answer would read
there as a reason to buy turrets. `PfRebuild` discounts each asset's defence
worth by `Lava::Survival` over the stake horizon, which is what makes the
basin earn a light gun and the shelf a real one. `apex_lava`, docs/27.

## Traps

- **`HazardAt` is ~0 at our own start by design** — its pressure term is scaled
  by `ThreatGradient`, which is 0 at home. That is why the siege prior exists.
- **A global "unknown = dangerous" prior inside `HazardAt` repriced every want
  and cost 87% of standing army** (6 games). Such priors must be SCOPED to
  survival discounts, never to the shared field.
- `ai.GetBuilderThreatAt` is ~97% zero and CRASHES off-map — not a risk source.
- Threat magnitude belongs in `ThreatM`, arrival frequency in `HazardAt`. Mixing
  them double-counts and made every tower look 70% useless.
- `ExposureAt` is deliberately NOT a factor in `ThreatM`/`HazardAt` any more —
  it is zero at home, so the base priced as the safest ground on the map.

## Log lines

`apex: defprice t=… gain= stake= threat= cover= short=x->y hz= (hazard= siege=)
| econM= protM= army= foeSeen=` — every term of the defence gain, 30 s cadence.
`apex: risk mex= covered= meanShort= lostM= home[hazard=/ks short=] worst=…`
(`RiskDiag`, 60 s).

## Tunables

`apex_risk_floor` (0, measured and left off 2026-09-11) · `apex_enemy_prior` (0.25) · `apex_siege_prior` (1.0) ·
`apex_threat_r` (900) · `apex_threat_gradient` (1) · `apex_stake_horizon_s` (300) ·
`apex_exposed_loss_s` (120) · `apex_eco_raid_tau` (180) · `apex_expose_r` (1200) ·
`apex_def_trade` (2) · `apex_standoff_cover` (1) ·
`apex_stream_survival` (1) · `apex_space_rent` (1) · `apex_tech_survival` (1) ·
`apex_eco_survival` (1)
