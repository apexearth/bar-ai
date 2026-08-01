# BUILD_PHASE — a single sense of "what are we buying right now"

apexearth's design. Written down because it is the missing dimension behind the
regression recorded in `CLAUDE.md`: twelve rules that each fired on their own
local condition, competed for the same constructor-seconds, and cut metal
production 4.3x while every one of them was working exactly as written.

A rule that asks *"is my condition true?"* will always fire. A rule that asks
*"is my condition true, and is this the phase where that matters?"* will not.

## The phases

| # | phase | what it is for |
|---|---|---|
| 0 | opening | initial mex building, energy, and the first factory |
| 1 | expand | constructors, more mexes, scouts, a small army |
| 2 | build up | T1 size — army, economy |
| 3 | pre-T2 | ensure enough energy and metal to build T2 *and* afford its expensive units |
| 4 | T2 | continue building economy and a T2 army |
| 5 | pre-T3 | with ~2 fusions and some advanced converters, start afus and more advanced converters |
| 6 | T3 | economy is good — gantry and T3 units |
| 7 | late | keep scaling afus and advanced converters, expand the army, and consider special strategies: bomber raids, nuke spam |

## Three things that decide whether this works

### 1. Drive it from state, never from a clock

A timer is wrong in every game that does not go to plan, and those are the games
that matter. Each transition should read facts the AI already has:

- mex count and how many are upgraded (`T2MexCount`-style, from `armmoho.count`)
- averaged metal income (`gMetalAvg`, a one-minute mean — the instantaneous
  figure swings hard as tasks start and finish)
- energy income against pull, and whether energy is being *wasted*
- factory count, whether an advanced plant exists, fusion count

Every one of those is already readable from script, and every one appears in
`tools/composition.py`, so a phase timeline can be checked against the same
telemetry used to judge the change.

### 2. It has to be able to go DOWN

"Starts at 0 and keeps incrementing" is the natural reading, and it is the one
thing here that will bite. Games go backwards: a base gets razed, a commander
dies, income collapses. A player stuck at phase 6 because it once reached phase 6
will keep buying gantries with an economy that can no longer feed one — and this
exact case was watched live this session, a player that lost its commander and
sat in a rough spot for minutes.

Either let the phase fall when its entry conditions stop holding, or keep a
separate distress state that suspends the ladder until the situation is
recovered. The phase should describe *what the economy can currently afford*, not
*the furthest it ever got*.

### 3. Phases govern INVESTMENT, not reflexes

Being attacked does not wait for the right phase. The split:

- **Phase-gated** — anything that spends surplus on the future: extra
  constructors, fusions, converters, gantries, tech, standing army size.
- **Never phase-gated** — answering something happening now: retreating a
  constructor under fire, defending a cluster being raided, AA when bombers are
  overhead.

Get this wrong in the tight direction and the AI stands still while it is killed
for being in the wrong phase.

## The risk to watch for

BUILD_PHASE only pays off if it *removes* competition. If it becomes one more
`&&` on twelve rules that otherwise still all want to fire, nothing changes —
they will simply all fire in the phases where they are permitted. The test is
whether, at any given phase, there is a **short list** of things worth building
and everything else defers.

That is also the measurement: after wiring it up, `composition.py` should show
spend concentrating differently by phase, and `mex upgrades` recovering toward
stock's 8-11 rather than the 2 the flat rule set produced.

## Hardest part

Not the phases — the transition conditions. "Ensure we have enough energy and
metal to build T2 and afford those expensive units" is the right intent and needs
real numbers behind it. Those numbers are measurable now (`composition.py` gives
per-phase spend, income and upgrade counts), so they should be read off games
rather than guessed, and written here when they are.
