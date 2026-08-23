---
name: value-paradigm
description: The core design frame for all AI decisions — every choice is a priced Want in one currency; cost includes time; nothing is gated, capped, or sequenced by hand. Load before designing ANY new behavior or diagnosing a wrong choice.
---

# The value paradigm — cost/value mentality and choice modeling

Set by apexearth 2026-08-23, during the Brain rebuild design: "This is the
right paradigm... It is an important frame of thought." It is the successor to
the leaf-logic era and the reason that era was killed.

## The frame

Every decision the AI makes — what to build, what to produce, whether to
assist, reclaim, tech, or idle — is a **choice among priced alternatives**,
never a rule that fires. A behavior is expressed as a Want; a Want carries a
value; one arbiter compares values and spends. If the AI does the wrong
thing, its price for something is wrong — find the mispriced term, never add
a gate.

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
