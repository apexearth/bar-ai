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
can place) → `EPrice` / `ECostSpot` (one derivation on both sides since
2026-09-08: lathes run at the smaller feed share, so one e/s is worth
`flow / (eInc * (1 + excess))` with `flow = min(BPCapacity, mInc + bank/
apex_e_lookahead)` — the fleet's spend capacity, NOT `metal.pull`, which the
stall has already throttled; `excess` is headroom-scaled forecast pull over
supply, and supply is `income + EMakeInFlight()`) → `EPriceAt`/`EPriceCostAt`
decay premium→floor over `apex_e_response/buildSec`. `EPriceCostAt` returns 0
while the E bank is full, income (plus ordered generation) exceeds pull plus
the lines about to run, AND the build would not drain the bank over its own
duration. The old `excess*metal.pull/eInc` overpriced a deep stall six-fold
(and read 4 m/s of throttled pull as the whole economy); the old cost side
`excess*metal.income/eInc` billed a 5,000-E advanced solar 167 metal at
64 e/s.

**HardEStall is true only when energy is the TIGHTER feed**: with the metal
bank also dry (`mShare < eShare`, both feeds over the generator's build
seconds) more energy unlocks nothing and the hoist/interrupt stand down.

**Then the realizable share.** A price is what one E/s is worth; it is not a
claim that anyone will use it. `ERealizeShare(addE, buildSec)` multiplies a
generator's gain by the share of its output something would actually absorb:

    target = max(pull − convUse, slow-decay peak) * apex_e_headroom
           + convCap + (eStorage − eCurrent)/apex_e_lookahead
    share  = max(clamp((target − eIncome − EMakeInFlight) / addE, 0, 1), apex_e_waste_worth)

Above the line the gain decays to the `apex_e_waste_worth` floor (0.25) -- NOT
to zero: energy in the wasted band is worth the conversion floor as soon as a
converter follows, and that converter's cost is already netted out inside
`EPriceFloor`, so what is missing is only the wait and the risk. An overflow
makes a generator LOSE to the converter that realizes it and never makes it
unbuildable (apexearth's standing ruling: the generator ladder never pauses on
waste) — and the share lifts by itself the moment
capacity or demand rises. `ProposeEnergy` and `ProposeGeo` apply it.
`apex_e_realize=0` restores flat floor pricing and is the control arm.

Three things that formula insists on, each from a way of getting it wrong:
**demand excludes converter draw** (a converter is the sink for what nothing
else wants, not a consumer to lead at headroom); **demand is a fast-attack,
slow-decay peak, not raw pull** (pull is throttled AND drops to nothing between
jobs — read raw it flipped the share 1.00/0.00 tick to tick); **a bank that is
not full is a real use** (storage is spent later, and at frame zero it is the
only consumer there is).

## EcoPowerM — the shared denominator

`metal.income + (energy.income − ConvUseE()) * OwnConvCeil()`: total economic
power in metal/s. Subtract what the converters ACTUALLY chew (their metal is
already inside `metal.income`), at a rate we can actually place — nameplate
capacity erased real energy income whenever capacity exceeded income.

BOTH growth premiums divide by it. Measured against
its own economy each premium saturated differently (a fusion took the full 9x,
a moho 1.6x) — a denominator artefact, not a fact about the game.

- `apex_mex_growth` (8) in `want_mex.as` and the mexup half of `want_tech.as`
- `apex_energy_growth` (8) in `want_energy.as`, on `makeE*BestConvRatio`
  — and on `ProposeConvert`'s own metal gain, so both halves of the
  generator/converter pair carry it
- `ConvUpDemand()` = tier's unlock on the ENERGY side, `ConvertibleE * (best
  ratio in game − best ratio we can place)`. `ProposeTech`'s demand is
  `UpDemand + ConvUpDemand`; without the second term a map with no metal spots
  has UpDemand identically 0 and NO T2 lab is ever proposed.

## Arithmetic worth remembering

- moho ~620 m for +12 m/s: payback 52 s, **0.0194 m/s per metal**
- fusion ~4900 m for +14.3 m/s at the game's 70:1 conversion: payback 343 s,
  **0.0029 per metal**

  **These numbers are RIGHT, and while we are poor on metal the moho really is
  the better buy** (apexearth, 2026-08-31: "a moho is in fact better than a
  fusion when we are poor on metal"). A 52-second payback against 343 is
  exactly why, and the min-ETA objective in `value-paradigm` derives the same
  answer — the fast-payback investment shortens the path to everything
  downstream. Rate and ETA agree here; they are not competing models.

  What the rate CANNOT do is stand as a permanent verdict. It is
  regime-dependent: at 15 m/s the moho wins, and at 300 m/s with converters
  fed and spots exhausted the fusion is the only thing left that scales. And
  the two are not even the same resource — the fusion's +14.3 m/s is energy
  converted at 70:1, which is worth nothing without converters and spare
  energy, while a moho is metal directly.

  So use the rate to pick the NEXT investment, and use the ETA to a named
  target to decide WHICH target you are heading for and whether you can afford
  to start it yet. The 2026-08-31 loss (USER-FEEDBACK.md) was the second
  question going unasked: T2 at 15 m/s was priced on capability with nothing
  charging it for the delay it imposed on everything else.
- cormakr converts 70 E→1 M/s for ONE metal; cormmkr 600 E→10.3 M/s for 370.
  T2's edge is space and toughness, not ratio.

## Traps

- **NEVER cache a zero** in a lazy catalog scan keyed on `Catalog::gAvailable`
  — availability is frame-dependent (the DLL's `IsAvailable(frame)`), and an
  early call latched `BestConvRatio` at 0 forever, silently collapsing
  `EcoPowerM` to metal income. Same shape in `LineMeans`/`FoeSpeedCap`.
- Do not charge near-free claims (50m mexes) through `UpDemand` — it
  double-counts income `FreeMetalFlow` already frees.
- **`energy.pull` ALREADY CONTAINS the converters' draw.** BAR's
  `game_energy_conversion.lua` charges each maker via `SetUnitResourcing
  "uue"`, which lands in `CTeam::resPull`, so any surplus built from
  `income − pull` is already net of them. `ProposeConvert` subtracted
  `StandingConvCap()` from that surplus a second time and so read a saturated
  fleet with 50 e/s still spilling as −50, proposing nothing: the mechanism
  behind "we never build enough converters". Subtract only capacity already
  ORDERED (`ConvCapInFlight`). Ground truth for the fleet is the gadget's own
  `mmUse`/`mmCapacity` team rules params — `ConvUseE()` / `ConvCapE()`, via
  `ai.GetTeamRulesParam`.
- **Price both halves of a pair the same way.** The generator carried the
  `apex_energy_growth` premium and the converter that realizes its energy did
  not, so the pair could never be bought in the order that pays off. If one
  side of a complementary pair gets a premium, the other needs it too.
- A premium priced at decision time and paid over a 7,000 s build is wrong
  twice; always price the gain through `EPriceAt(buildSec)`.

## Tunables

`apex_space_m` (1.0) · `apex_assist_share` (0.5) · `apex_conv_horizon` (300) ·
`apex_e_response` (45) · `apex_e_lookahead` (30) · `apex_e_headroom` (1.75) ·
`apex_e_realize` (1) · `apex_e_waste_worth` (0.25) ·
`apex_mex_growth` (8) · `apex_energy_growth` (8) · `apex_tech_pipe` (2.0) ·
`apex_eco_survival` (1) · `apex_join_min_m` (500)

## Log lines

`apex: efloor` (gate on `apex_efloor_diag`, and it carries the overflow state:
`eInc ePull convUse convCap realize`) · `apex: ewant` (same gate; EVERY factor
of every generator rung an asker priced: `P grow surv inf real`, `m=(M+E+A+
rent)`, `t=(walk+build+late+rest)`, and the energy ledger — read this before
touching any term here; it is how the seven 2026-09-08 defects were found) ·
`tools/ecotimeline.py` (bank/income/pull minute by minute per arm) ·
`apex: tech-diag ... upD=` ·
`apex: mexdiag` · `apex: eco-status` · `apex: decide <unit> -> <want> v=…`
