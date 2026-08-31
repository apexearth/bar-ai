# How BAR actually works — the model to reason from

Written because reasoning about this AI from telemetry alone produced repeated
nonsense: treating T3 as reachable at 40 metal/s, not knowing what a D-gun does
to your own buildings, calling a broken run a "scaling" property. Everything
below came from apexearth, who plays the game. Re-read it before diagnosing.

## The two resources

**Metal** is the constraint on almost everything. It comes from **mexes** built
on fixed map spots, and from **reclaiming** wrecks and features.

**Energy** comes from solars, wind, fusions. Its main use beyond upkeep is
**converters**, which turn surplus energy into metal at roughly **60 energy per
1 metal**. So 1000 energy/second ≈ 17 metal/second of conversion.

## The economic ladder, and why it has no thresholds

This is the ORDER the arithmetic produces, not a sequence to code. Each rung is
reached when the cheaper growth below it is **exhausted** — spots taken,
upgrades done, or ground we cannot hold — at which point the next rung is
simply the best remaining thing to buy. See `docs/23-the-plan.md`.

1. **T1**: mexes, solars/wind.
2. **T2 constructors** — this is the unlock, not the T2 factory itself. A T2 con
   upgrades a mex to a **Moho**, worth roughly **4x** the metal of a T1 mex.
   *Upgrading every mex is the single biggest economic step in the game*, and it
   is worth most exactly when income is small: +12 m/s onto 15 m/s is +80%, onto
   300 m/s it is +4%.
3. **Fusion**, once converters are already running and cheaper growth is gone.
   Fusion is a "wait for something good" investment — you can die while paying
   for it. **Advanced solar has much faster ROI** and is not a bad choice.
4. **Advanced fusion (AFUS)**, one or two of them.
5. **T3**, after those AFUS.

NO NUMBERS IN THAT LIST, ON PURPOSE. It used to read "fusion at ~1000 energy/s"
and "T3 only once over 100 metal/s". Deleted 2026-08-31 on apexearth's ruling:
they are exactly the numbers a gate would use, a cold reader takes them as the
bar to code against, and they contradict the objective — a rung is reached by
exhaustion, not by income crossing a line. The model should PRODUCE numbers
like these, never be told them.

## What T3 costs, which is a fact and not a threshold

Real costs, read from the pinned tree 2026-08-30: gantry `corgant` **8,400**,
`corshiva` 1,550, `corcat` 4,900, `armbanth` (Titan) 13,500, `corjugg`
(Behemoth) 20,000, `corkorg` (Juggernaut) **29,000**.

What makes T3 cheap or dear is the RATIO of that cost to the income, and
whether cheaper growth is still on the board. At 40 metal/s a Juggernaut is
twelve minutes of a whole team's income, so T3 at benchmark scale is two or
three units, not an army. At the 250-400 metal/s a bonused hosted game reaches,
a gantry is ~20 seconds of income and the arithmetic inverts completely — read
the actual income before calling T3 affordable or unaffordable, and do not
turn either reading into a bar.

**Corollary**: if the AI is not upgrading mexes, nothing downstream works. Zero
`t2Mex` is a bug, never a strategy characteristic.

## Team play

- Usually **one player techs** to T2 and **shares advanced constructors** with
  teammates, so nobody else pays for their own advanced factory.
- Allies can **send metal** to that player to get there faster ("slinging").
- Once teammates have cons, **everyone upgrades their own mexes**.
- Anyone with T2 and no advanced con should build one — a T2 factory with
  nothing to upgrade mexes is useless.
- **On a 4v4, nobody should go air.** One of four contributing no ground army
  loses the game. On 8v8 one air player is affordable.

## Combat

- **Spam is not waste.** Cheap fast units give vision and soak shots. An
  expensive long-range unit firing at a Tick is a huge waste of its firepower —
  a very strong anti-AI tactic. Keep spam in the mix at ALL tiers, especially
  once the enemy fields long-range T2 like **Banishers** (`corban`), which kill
  expensive things from a distance.
- **Attack in a mass, not a trickle.** Feeding units piecemeal into a fight
  loses them for nothing.
- **Static defence trades very well** against an AI that keeps attacking, and is
  what lets you out-eco behind it. Pair defences with **jammers** (hide what you
  have) and **radar** (see what is coming) — a radar AND a jammer together is
  much better than either.
- **Winning a fight and holding the field is a large metal swing**, because you
  reclaim the wrecks. Reclaiming yields metal; **resurrecting spends it**.

## The commander

- It is the **main early builder** — restricting where it may work guts the
  opening. Measured: shrinking its work radius cost 68k → 30k metal.
- It is also **the game**. Losing it usually loses the match; commander survival
  correlates with the winner more tightly than any other metric measured here.
- At T1 it can be an action hero. Once **heavy T2** is on the field it needs to
  be careful.
- **D-gun destroys everything in the beam, including your own buildings.**
  Firing at one cheap raider standing next to your own lab costs you the lab.
- Commanders often die to **the last one or two long-range shots while already
  retreating**, so local threat at the commander's position reads clean right up
  until it dies. Health, not position, is the honest danger signal — and risk
  should scale with damage already taken.

## Game length

A game that reaches T3 can easily run **45+ minutes**. Cutting benchmark matches
at 30 minutes truncates the whole late game and biases results against any
strategy whose payoff is late.

## How humans beat this AI

Capture territory, wall it with defences, out-eco behind the wall, then finish
with massed T3. Let the enemy attack into static defence, die there, and reclaim
their dead — the enemy funds your economy.
