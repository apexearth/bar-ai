---
name: eta-objective
description: How the AI answers "what is the fastest path to the state I am trying to reach" — the target, the growth ladder, what it can and cannot price, and the instrument. Load before touching manager/brain/market/eta.as, before changing any economic gain, and before adding army to the target.
---

# The ETA objective

`docs/23-the-plan.md` is the intent and comes first. This skill is the mechanism:
what the code actually computes, what it deliberately refuses to compute, and how
to tell whether it is working. It describes **`manager/brain/market/eta.as`** and
the one block it added to `market/decide.as`.

Status, 2026-09-08: **ON by default (`apex_eta=1`) since the Carrot Mountains
battery: minute-30 metal income 188 -> 236 m/s against a flat BARb, 12 games;
see docs/27 `TUNE_ETA`.** Still economy-only, and the army half is not built. The target
names a level of economic power and nothing else. Everything below is scoped to
that; do not read it as a description of how the AI values army or defence.

## Why it exists

The market prices ONE STEP: `value = gain / (mCost + tCost)`, a rate of return
compared *now*. A per-instant price is greedy, and greed cannot see compounding —
it cannot express "this is worse this minute and reaches the goal sooner". That
is not a small inaccuracy. It is the whole difference between ranking the options
in front of you and reaching a target.

Measured against an **inactive** opponent (NullAI, Comet Catcher, 13 seeds), the
greedy market produced **4 mexes at minute 10 and 7 at minute 14** on 18 metal/s,
with more metal in army than in economy from minute 10 — with no enemy on the
board to justify either. That is the failure this layer exists to fix, reproduced with nothing to
blame it on.

## The model, in full

Three moving parts. There is no fourth, and nothing here is a threshold, a cap or
a sequence.

### 1. The target

    target = EcoPowerM() * ETA_TARGET_MUL        (4x, a named constant)

Economic power is `EcoPowerM()` — metal income plus net energy carried at the
conversion anchor. The target is a MULTIPLE of where we stand, so it is
scale-free and renews itself as the economy grows. Far enough away that a long
build's delay is felt; near enough that the ladder terminates.

### 2. The pool — every way the economy can still grow

Rebuilt every 5 seconds, in `PoolFill`. Three sources, each a `(def, cost, gain,
count)` rung:

| Rung | Gain | Count |
|---|---|---|
| Open ground | `SpotM()` — the last probed spot yield | spots on the map minus spots we hold |
| Held ground | `spotIncome x (bestExtract - standing)` per spot | 1 per upgradable mex we own |
| Generation | `gMakeM + gMakeE x ConvRate()` | inexhaustible |

**The pool is sorted by seconds per power at the current feed and lathe**
(`max(cost/P, buildSeconds/wide) / gain`, over survival), ascending. For a
feed-bound rung that is the old payback order (`cost/gain`, exact while metal
binds); for a lathe-bound one -- an afus at 711 s, a fusion at 300 -- it is the
order the ladder's own objective needs. Metal-only ordering put the afus ahead
of the fusion and charged a moho-first path a slice of it (2026-09-20). The
pool is rebuilt every 5 s, so the sort is still one pass per fill. `wide` is
how many of our hands can build the def, capped by the rung's count.

Geos are in the pool as a vent-limited rung, `n` = `OpenGeoSpotCount()`.
Left out, a path that *started* with the geo held power no other path could
reach, and the ladder sent T2 cons across the map for it over mohos priced
four times higher.

Two pools are kept: `gPoolNow` (what our constructors can build) and
`gPoolTech` (what anyone could build, i.e. the world after an advanced plant).
**Comparing the two is how "is T2 worth it yet" gets answered by arithmetic.**

### 3. The ladder

`LadderRun` walks the sorted pool, taking the shortest-payback growth still
standing until the target is reached, accumulating time:

    stepSec = max( buildSeconds(def, buildPower), (cost - bank) / P )

That `max` is the plan's own formula, applied per rung: **metal feeds the lathe**,
so a step takes the longer of what the fleet can build and what the economy can
pay for.

**Rungs are taken in BATCHES sized to grow the economy by `ETA_CHUNK` (25%), not
one at a time.** This is not an optimisation, it is correctness: the target
scales with the economy, so a budget spent one claim or one solar at a time runs
out of steps as the economy grows. Measured at P=63.6 against a target of 254.4,
the walk exhausted `ETA_MAX_STEPS` among the open claims and returned
"unreachable" — which silently switched the whole objective off exactly when the
economy got big, and is very likely why the first measured effect faded by
minute 18. Batching also removed the special-cased generator tail: an
inexhaustible rung is just one whose count never runs out.

A batch is priced at its STARTING power, which understates the speedup within
the batch and so overestimates time — the conservative direction. (A closed form
would want a logarithm, and this AngelScript has no `log` binding.)

`EtaWith(def, dPower, addBP, tech)` = time to build that first move, then the
ladder from the resulting state.

**Two arms added 2026-09-08.** (1) Every rung carries its energy bill and its
energy output; `StepSec` is `max(build, metal feed, energy feed)` with the feed
`EtaEnergyAvail()` = surplus over pull plus bank over the lookahead, and a rung
taken adds its `makeE` to the feed -- so a solar shortens a 15,000 E lab. (2)
Claim and upgrade rungs are built by MOBILE hands only (`Pool.mob`,
`MobileBPShare`); a nano turret's `addBP` reaches the generation rungs alone.
`EtaHandsShare()` (the next four rungs' build-bound share, income-fed) sizes
constructors and lets a factory idle when nothing waits for hands. `def = 0` is the ladder as it stands, which is
the baseline every candidate is measured against.

## What falls out with no rule saying so

- **Mexes before tech.** Extraction has the shortest payback while ground is
  open, so the ladder takes it first, and any first move that delays it lengthens
  the ETA.
- **Upgrades after tech.** In `gPoolTech` the ceiling extractor is available, so
  every held spot gains a rung it did not have — which is what can make the plant
  pay for itself.
- **Constructors when short of hands, not metal.** A nano adds no income; it adds
  `buildPower`, which only shortens the ETA where `stepSec` is build-bound rather
  than feed-bound. The plan's "a constructor rather than another building" is the
  `max()` picking its other branch.
- **The switch to reactors.** Finite rungs empty. When the spots are claimed and
  the upgrades done, generation is simply the best remaining payback. **This is
  the whole of "exhaustion is what ends a regime, not a threshold."**

## What it deliberately CANNOT price — and why that is not a gap to fill

`EtaRanks()` admits exactly six want kinds: `MEX`, `MEXUP`, `ENERGY`, `GEO`,
`NANO`, `TECH`. Everything else keeps its market price. This is a scope, not an
oversight:

- **A factory (`WK_PLANT`)** returns army. An economy-only target cannot name
  that, so it must not be allowed to rank it. `CAT_PRODUCE` is excluded from the
  merge below and keeps its own ticket and market ordering — which is also what
  guarantees the first factory is never at risk.
- **A converter and a store** are already inside `EcoPowerM`'s valuation: it
  carries net energy at the conversion rate whether or not a converter stands, so
  a converter is power-neutral *by construction* here. Ranking it by this target
  would price it at zero, which is a statement about the measure, not about the
  converter.
- **Assist** adds no def and so has no rung.

**Read the first move's power gain from the CATALOG, never from `w.gain`.** They
are different numbers: a market gain carries scarcity premiums, survival
discounts and stated preferences. Feeding those into the ladder invents income.
This was measured on the very first probe — a vehicle plant's *capability* gain
entered as metal/s and reached the target in 83 s against a mex's 280. `DPowerOf`
is the honest read; do not "simplify" it back to `w.gain`.

## How it steers

`apex_eta`:

- **0 (default)** — shadow. The ladder runs and logs; the market decides.
- **1** — the three economic categories it can price (`CAT_METAL`, `CAT_ENERGY`,
  `CAT_BP`) become ONE draw ticket, whose representative is the ladder's pick
  (`EtaEcoPick`).

The merge is the actual behaviour change, and it is the same fix the
kinds-to-categories merge already made one level down: as three separate tickets,
extraction/generation/build-power were each sampled against everything else, so
the economy question got asked three times and answered three different ways.
One question, one answer.

**The ticket carries the economy's BEST market value, never the value of the want
the ladder chose** (`EtaEcoWeight`). This one is easy to get wrong and was: the
ladder exists to prefer wants the per-instant price rates *lower*, so paying the
economy's draw odds out of that pick shrinks how often economy wins an election
at all. That argument stands on its own logic — it is **not** backed by a
measurement, and an earlier version of this file wrongly claimed it was. See
`ISSUES.md`: the significant-looking result behind that claim was reproduced by
an identical-config control, so it was noise. The ladder decides WHICH want;
how loudly economy speaks is not its business.

So *how much* economy competes against defence is unchanged. Only *which* economy
want competes changes. That confinement is deliberate — the eco-vs-army balance is the army
half of the plan and is not wired.

## Whether it works is NOT known, and this benchmark cannot tell you

Two A/B batches (11-13 matched seeds, NullAI, Comet Catcher) resolved nothing.
The control that explains why: **two batches of the identical configuration
differ by +9.3% and +13.3% mean `metalProduced`, sd ~20%, with the minute-18
interval excluding zero** — the benchmark reports a significant difference
between a config and itself.

**Required N here is ~60 pairs (120 games, ~1.5 h) for a 10% effect at 80%
power; ~80 pairs at minute 18.** Anything smaller measures noise. Do not run a
10-game eco A/B on this benchmark and report a direction — that is how the
retraction above happened. `FixedRNGSeed` pairs weakly (the DLL is
multithreaded), so matched seeds remove far less variance than they appear to.

## The instrument

    grep "apex: eta " infolog.txt

    apex: eta t=0 P=21.1 tgt=84.4 cheap=9.18 base=213 mkt=mex:armmex
        eta=tech:armavp=89 | mex:armmex=205 nano:armnanotc=138
        energy:armadvsol=193 tech:armavp=89

- `P` / `tgt` — economic power now, and the target.
- `cheap` — `ServableUpDemand() + OpenSpotStream()`, the cheap growth the board
  still owes us. **This is the quantity a threshold used to stand in for.** High
  `cheap` while the AI reaches for expensive growth is the 2026-08-31 loss.
- `base` — the ETA with no first move. Every candidate is measured against it.
- `mkt` vs `eta` — what the market's price put first, and what the ladder would.
  Their disagreement is the layer's whole reason to exist; if they never
  disagree, the layer is inert and should be said so rather than shipped.
- One line per 15 s. **It is a sample, not a census.**

Per-frame cost is under `dec.eta` in `apex_perf=1` / `tools/frametime.py`. The
pool rebuild is the only bulk pass and it is on a 5 s clock; the per-election
work is a handful of 64-step walks over a pre-sorted array.

## Modelling assumptions, stated so they can be attacked

Each of these is a place the model is knowingly coarse. None is hidden in a
constant.

1. **Open spots are priced at one average yield** (`SpotM()`, the last probed
   spot), not per spot. Real yields differ across a map.
2. **A batch is lathed as wide as the hands that can build it** (`StepSecWide`):
   the feed is charged for all k, the build time for k/wide. Before 2026-09-20 it
   was fully serial, and the bias was NOT common-mode: a 127-wind tail read
   1,400 s, and any head that trimmed it by a few power won the ladder --
   fusion over moho, geo over moho, measured in a 2v2 trace. The head is
   still the asker's own time while the tail is fleet-time; measured harmless
   for T1 elections (same category shares over 9 seeds x 2 maps), unproven
   in general.
3. **Tech unlocks everything at once.** `gPoolTech` ignores `CanBuildEver`
   entirely, so an advanced plant is credited with the whole T2 tree. Broadly
   true (a T2 con builds fusion and moho), but it is an upper bound.
4. **A batch is priced at its starting power**, so a long batch overestimates its
   own duration. Bounded by `ETA_CHUNK`. The LAST batch is pro-rated to the power
   still needed: whole-unit overshoot turned a 7-power margin into a 1,392 s afus.
5. **The layers can still disagree**: `apex: eta-pick` logs every ladder pick
   that is not the best-valued rung (sampled, unsampled when priced under half),
   and `apex: eta-pick-trace` prints both ladders when the rung it outranks is a
   mexup. Read those before touching the arithmetic.

## Rules for working on this

- **Do not add a term to make an outcome happen.** The failure mode of the
  paradigm is term count (`docs/21-simplification.md`): twelve multipliers and no
  single one controls anything. This file has three moving parts on purpose.
- **A threshold here is a bug, not a fix.** If the ladder picks wrong, the pool's
  arithmetic is wrong — a missing rung, a dishonest gain, a count that does not
  empty.
- **Prove it moved the decision.** `mkt` vs `eta` in the log, then composition.
  An inert edit is worse than none.
- Next step is **army in the target**, which is where the plan's standing
  obligation (army and defence at their share of our own economy — *own*, not
  the enemy's, per apexearth 2026-08-31) enters. Until then this layer is
  economy-only and must not be described otherwise.

Related: `value-paradigm` (the pricing frame this serves), `ai-eco-pricing` (the
per-step gains the ladder consumes), `docs/23-the-plan.md` (the intent).
