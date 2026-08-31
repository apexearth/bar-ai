---
name: value-paradigm
description: The core design frame for all AI decisions — the AI picks a TARGET STATE and takes the fastest path to it (minimise ETA), and prices Wants in one currency to serve that; cost includes time; nothing is gated, capped, or sequenced by hand. Load before designing ANY new behavior or diagnosing a wrong choice.
---

# The value paradigm — cost/value mentality and choice modeling

Set by apexearth 2026-08-23, during the Brain rebuild design: "This is the
right paradigm... It is an important frame of thought." It is the successor to
the leaf-logic era and the reason that era was killed.

## The failure mode of this frame: too many terms

"Find the mispriced term" only works while a price has few terms. Measured
2026-08-30, a defence price was a product of **twelve independent multipliers**
(stake, hazard, stopped, time-to-defence, tier discount, wall efficiency,
team-best-tower ratio, target fill, and inside the cover term: surface DPS,
outrange share, durability, trade rate). With twelve, no single term controls
the outcome: one term was changed by 4.6x and the choice did not move, because
another moved 6.5x in the opposite direction. Matched seeds then disagree in
sign, because a different term is extreme in each game.

apexearth: *"I see it terribly often that you make changes which have little or
no effect."* That is this, structurally.

So the frame carries an obligation: **when a price grows past a handful of
terms, the fix is to DELETE terms, not to add a better one.** Before repricing
anything, log the decomposition of the winning choice and the runner-up, and
find which three or four terms actually carry it. See
`docs/21-simplification.md`.

## The objective: FASTEST PATH TO A TARGET STATE

Read this before the pricing frame below, because the pricing exists to serve
it and has repeatedly been mistaken for it.

apexearth, 2026-08-31, and he considers this how the AI was always meant to
work: *"We're supposed to do things based on math... If you were to calculate
out the ETA to getting your first fusion, then increasing your economy before
getting T2 would show as the right choice. Also upgrading mexes once we get to
T2 would also show as the proper choice to get that fusion faster... There is
theoretically a 'perfect' play to get to your first fusion the fastest."*

**The AI picks a TARGET STATE and takes the fastest path to it.** The target is
itself a choice and it is composite -- "a 10,000-metal army", or "a 5,000-metal
army AND a fusion" -- and different targets are different valid ways to play.

    t_direct(T) = max( (T - bank)/income , T/buildPower )
    t_via(X,T)  = t_build(X) + max( (T - bank')/(income + dI_X) ,
                                     T/buildPower' )
    choose argmin over candidate next investments X

Everything he keeps asking for falls out of that and needs no rule:

- **Economy before tech** wins whenever `dI_X` pays back inside the horizon.
- **Mex upgrades after T2** win for the same reason, in the new income regime.
- **How many constructors and nanos** is the SECOND term of the max: when
  `buildPower < income` the plan is build-power-limited, so the answer is a
  lathe, not another building. "100% efficiency" is not a separate rule.
- **T2 at 15 m/s loses on its own arithmetic** -- it lengthens the ETA to every
  target -- with no threshold and no tunable anywhere.

### The failure mode of a per-instant price

A value compared **now** cannot express "worse this minute, sooner to the
goal". It is greedy, and greed cannot see compounding. That is not a small
inaccuracy; it is the whole difference between the two models, and it is what
lost the 1v1 he watched on 2026-08-31 (see USER-FEEDBACK.md): the T2 lab was
priced on capability while nothing charged it for the delay it imposed on
everything else.

Note carefully what this does NOT mean. `ai-eco-pricing`'s "moho 0.0194 vs
fusion 0.0029 per metal" is CORRECT, and while we are poor on metal the moho
really is the better buy -- rate and ETA agree, because the fast payback
shortens the path to everything after it. The rate is not the enemy of this
objective; it is how the objective is computed one step at a time.

The gap is the question the rate cannot answer: WHICH target are we heading
for, and can we afford to start it yet. A per-instant price ranks the options
in front of it; it never asks whether beginning a 4,300-metal reactor at 10 m/s
delays every other target past the point where we survive to use it.

### The constraint that keeps it honest

A pure minimise-time-to-fusion optimiser builds ZERO army and dies at minute
12. The objective is time-to-target **subject to surviving**, and the survival
constraint is the hard half -- it is not simple arithmetic and it is not
solved. Any first implementation is judged on whether it still defends itself,
not only on whether it reaches the target sooner.

## The frame

Every decision the AI makes — what to build, what to produce, whether to
assist, reclaim, tech, or idle — is a **choice among priced alternatives**,
never a rule that fires. A behavior is expressed as a Want; a Want carries a
value; one arbiter compares values and spends. If the AI does the wrong
thing, its price for something is wrong — find the mispriced term, never add
a gate.

**But a price is a MEANS to the objective above, not the objective.** Where the
two disagree, the ETA to the target is right and the price is wrong.

## One currency

Value is denominated in **metal/s equivalent**: expected return per
metal-second of total spend. One currency is the whole point — it is what
makes a fusion comparable to a tank batch, a moho to a nano, army to economy.

## Cost always includes time

Cost = **metal + the builder-time the choice occupies**, and builder-time is
priced at opportunity cost — what that lathe would earn on the runner-up
Want. Consequences that fall out for free:

- Tech ambition scales with the economy: the time term is cheap at 400 m/s
  and ruinous at 40. No income gate needed — the price does it.
- Assist is pure time, no metal. Reclaim is negative metal, time only.
- Walking is builder-time too: a far mex is dearer than a near one by the
  travel term, not by a distance cap.
- Constructor time IS the economy (the 2026-08-01 lesson: twelve "firing"
  rules cut metal 4.3x because each spent con time). The time term is how
  the market feels that cost automatically.

## Choices come from data, not names

The Catalog — built at init from the engine's own def table (GetDefCount /
GetCircuitDef(Id) / CanBuild / IsAvailable) — supplies every def's cost,
buildtime, yield, upkeep, and the full who-builds-what graph. Extra-units
and scavenger packs are present exactly when the game ships them. What to
build next is arithmetic over the Catalog plus live income; unit NAMES never
appear in decision logic.

## Where the math is honest, and where a model enters

- **Real arithmetic**: everything economic (mex, energy, converters, BP as a
  closed loop, con demand, tech = price the best unlockable def against the
  best available one minus lab cost+time).
- **One modeled quantity**: army/defence have no literal payback — their
  value derives from a single named model term (expected metal protected or
  destroyed, from measured enemy mass × stance × front pressure). The model
  term is where tuning lives; the math downstream of it stays honest.
- **Thin ice**: attack timing stays in the military USE layer; scouting is
  priced as uncertainty reduction (value rises as the enemy census goes
  stale); placement is the geometric layer, not the market.

Every modeled term must be ONE visible, named quantity — never a scatter of
gates that jointly imply a value.

## Pricing laws proven by measurement (2026-08-23, prototype 1)

- **Temporal consistency**: value a gain at DELIVERY-time conditions, not at
  decision-time conditions. A scarcity premium decays at the market's own
  supply-response speed; a long build priced at today's spike is wrong twice
  (the 7,000s AFUS that froze the only T2 con; energy perpetually outbidding
  mohos). Premiums apply for the response window; equilibrium rates apply
  for the lifetime.
- **Exchange rates come from the game**: energy's metal price is anchored on
  the best available converter's ratio (the game's own arbitrage floor), a
  stall multiplying it only while pull exceeds income.
- **Cost is what is actually forgone**: resources in overflow are free to
  spend (E-cost forgiven at a full bank); a builder's time is priced at its
  runner-up want; asymmetric gain/cost pricing is legitimate when the two
  sides genuinely forgo different things.
- **Capability is a fleet property**: builds run at fleet-assisted speed
  (Requests folds joiners), so big builds get cheaper as the fleet grows --
  price them that way or they never win. Same for tier-unique demand:
  diminishing returns per serving unit, never a binary "one exists".
- **Feedback must read the honest signal**: idle builders do not pull, so
  "overflow" lies about BP need -- close loops on CAPACITY vs income, not on
  observed flow. Storage buys TIME: worthless while headroom already covers
  the horizon.
- **Feasibility is part of the price**: a def must be able to EXIST at the
  site (terrain area of a plant's products, floaters/submerged on land, geo
  vents, spot ids) -- an infeasible want churns forever at any value.

## What this frame forbids

- Hard caps, clocks, exclusivity, hardcoded sequences (long-standing rules —
  see CLAUDE.md "Ask before inventing policy"). Orderings EMERGE from prices.
- New behavior as a ladder rule or quota floor (the overhaul mandate).
- Fixing "builds too many X" with a limit — the fix is X's value relative to
  alternatives.
- A static number that is not either physics read from defs or a tunable
  with a written derivation.

## How to apply when working

- Designing a behavior: state its Want, its return, its cost incl. time, and
  which multipliers (Role, Persona, stance, handicap) scale it. If you
  cannot price it, you have not understood it yet — model the one missing
  quantity explicitly and say so.
- Diagnosing a wrong choice: read the decision log (`apex: decide <unit> ->
  <want> v=... over <runner-up> v=...`) and ask which TERM is wrong, not
  which rule to add.
- Multipliers change how much, never whether. A role's "no army" is a 0x
  multiplier on the army value, not thirteen early returns.

Design record: docs/20-brain-overhaul.md and the session design page
("The Brain Rebuild" artifact). Related memories: economy-over-static-numbers,
build-power-closed-loop, brain-overhaul-mandate.

## The temporal-consistency law (MANDATORY on every pricing change)

Metal feeds the lathe. When income is the binding constraint, marginal build
power at a fed site is worth ZERO and marginal income is worth everything --
including to the very build it delays. apexearth's canonical arithmetic
(2026-08-23): at 10 m/s, com + 3 cons feeding a T2 lab take 5 minutes;
claiming 2 open safe mexes first makes it 3; growing to 35 m/s makes it 75
seconds AND funds army, defence, and the T2 units after.

The law has shared primitives in market.as -- new pricing goes THROUGH
them, never around:

- `FreeMetalFlow()` — unspent income + bank trickle. Any want whose gain is
  "my BP moves metal" (assist, nano, guard-shaped things) caps its gain here.
- `UpDemand()` — the FEED-COMPETING streams a feed-bound build postpones
  (builds that need the same income, e.g. 620m mohos). Charge is
  `UpDemand × feedSec`. Do NOT charge near-free claims (50m mexes) here --
  they proceed in parallel on freed hands, and charging them double-counts
  the income FreeMetalFlow already frees (measured: T2 priced out of an
  entire 25-minute game).
- The build's own duration is floored by `(costM − bank/2)/income` in
  `ValueOf`. Do NOT scale it by committed-debt "fair share" -- tried and
  reverted 2026-08-23: a debt ledger is not a flow commitment, and three
  seeds wasted 3.5-8.7k while metal overflowed (overflow is PROOF income
  was not spoken for). Affordability lives on the GAIN side: unserved
  demand divides among the pipes in flight (tech demand / (1+liveKin)).
  apexearth's standard: a same-tier second lab must lose on PRICE, never
  by rule.

Review checklist for ANY new/changed gain: (1) does it claim throughput the
economy hasn't got? cap by FreeMetalFlow. (2) does it occupy income for a
long build? charge displacement. (3) is it a one-shot? amortize over the
horizon, never price as a stream. Violations of this law have each cost a
measured failure: nano-at-face-value, fusion-before-mohos, converter spikes,
and the assist pile-on.
