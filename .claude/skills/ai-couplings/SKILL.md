---
name: ai-couplings
description: The cross-domain feedback loops and hidden gates that make this AI build the wrong things — targets, priors, vetoes, and the laws that keep them honest. Load before adding ANY gate, target, prior or role rule.
---

# Couplings — why the AI builds the wrong things

Everything is priced in one currency and everything feeds everything else, so
the recurring bug in this codebase is not a wrong number. It is a term in the
wrong place: a demand that its own answer inflates, or a refusal the ranking
cannot see. Five separate symptoms in one session (2026-08-25/26) were all one
of the four laws below.

## LAW 1 — nothing may inflate the demand it is bought to satisfy

A quantity in a target's BASIS that cannot appear in that target's VALUE is a
positive feedback loop.

Measured: a nano turret is a standing structure, so it landed in `gAssetsM`,
the basis of `ArmyTarget` — while `ArmyValue` counts only mobile non-builder
units, so lathe could never close the gap it widened.

> nano → gAssetsM ↑ → ArmyTarget ↑ → `funded` ↓ → no T2 → army weak → nano

30 turrets, 6,300 of 16,905 metal on lathe, T2 in 3/8 games. Fixed by
`EconAssetsM = gAssetsM - gProtM - gBPM` (`market/army.as`): defence and lathe
are ANSWERS to demand, not wealth that invites attack. `census.as` had already
applied this law to `gProtM` for the same reason; the army target never got it.

**Adding a structure class that answers demand? Subtract it in `EconAssetsM`.**

## LAW 2 — every demand term must subtract the supply already standing

Otherwise the demand never closes and buys the same thing forever.

`NeediestLine`/`UnservedLineSpend` subtract `nanosNear * NANO_ABSORB`.
`ProposeNano`'s ARMY branch subtracted nothing, so an army below target bought
a turret however many were standing.

Healthy loops subtract; vicious ones land in the basis. `BPGap()` subtracts
`BPCapacity()`, so arriving hands close the gap — that is the shape to copy.

## LAW 3 — a want nobody may execute must not be ranked

A hard gate is a price of infinity. A price the arbiter cannot read is a bug by
construction: it elects the want, the executor refuses, the builder idles and
re-elects, forever.

`Role::DefenceAllowed()` gated ground defence at `Requests::Take` — downstream
of `Brain::Decide`. The rear eco specialist put 2,491 of 2,933 decisions (85%)
into a want that could never be built.

**Worse, a veto can break an unrelated mechanism's exit condition.** The DEF
PANIC in `decide.as` fires while we own zero ground defence and something is
killing us, and ends "the moment the first tower stands" — which a player
forbidden to build one never does. The panic latched for the whole game.

All three copies of that veto are deleted. apexearth: *"if want for defence or
army is 0 then we should have none. It should really be that simple."* A role
may change how MUCH, never WHETHER.

## LAW 4 — every major want needs a target, or it never stops

Army had `ArmyTarget` and saturated. AA had a target (`aaCover` against
`AirSeenEver` — "prices itself out... no count, no cap"). **Ground defence had
none**, so it was bought marginally forever at a value that never decayed,
because the hazard it multiplies is floored by a prior scaling with our OWN
economy. Defence therefore tracked the economy at a fixed ratio: measured
**175% of eco against stock BARb's 52%**, on a quarter of stock's income.

`DefenceTarget` (`want_protect.as`) fixed it: def/eco **146% → 7%**, team eco
**108,448 → 207,842** in one 8v8. That is the largest single measured move in
the project.

## The shortfall trap — one number, three consumers

`ShortfallAt(pos)` = share of a wave our own towers fail to stop. It multiplies
in THREE places at once:

| consumer | effect when shortfall is high |
|---|---|
| `StreamSurvival` (`coverage.as`) | every ECO build discounted |
| `TechSurvival` (`want_tech.as`) | the T2 lab discounted |
| `DefenceTarget` / the defence gain | more turrets wanted |

So one wrong reading suppresses economy AND tech together, and the only thing
it encourages is the turrets. Zeroing the defence target without fixing this
gives "don't build eco on unprotected ground" + "never build defence" =
**build nothing**, which is what an AI doing absolutely nothing looks like.

`TechSurvival` compounds three of these: undefended discounts tech, UNSCOUTED
is treated as maximally undefended (`FoeKnown()` false ⇒ `shortH = 1.0`), and
POOR is discounted hardest (`T` includes time for income to pay for the lab —
a poverty trap aimed at the player that most needs T2). They multiply.

## Traps measured the hard way

- **`ai.GetAllyInflAt` counts the whole alliance, US INCLUDED.** It read 3.71
  at our own base in a 1v1 with no teammates. It cannot answer "am I standing
  behind my team". Use `Market::TeamExposure()` — a rank among the team's own
  published homes, which excludes us by construction.
- **The `apex: decide -> X` line names what ranked FIRST, not what was built.**
  `Decide` falls through the whole ranked list calling `ExecuteWant`. Counting
  decide lines measures ranking. `apex: exec-refused` counts what could not be
  turned into a task; `apex: site-fail` (C++) counts where the site search
  failed and the builder was handed back to `FallbackTask`.
- **A builder logging a decision every update holds NO task** — `AiMakeTask`
  returns a held BUILDER task before ever reaching `Decide`.
- **`SiegeRiskAt` at prior 1.0** assumes the enemy converted an amount equal to
  our entire economy into army. Its own comment says "never to size
  production"; `StreamSurvival` and `TechSurvival` both size against it.

## Before you add anything

1. Does it enter a target's basis that its own value cannot enter? (Law 1)
2. Does the demand subtract what already supplies it? (Law 2)
3. Can the arbiter see it, or does it refuse after the auction? (Law 3)
4. Does it saturate? (Law 4)
5. How many consumers does the number you are changing already have?
