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

## Why prioritisation is structurally hard here, and what a phase does not fix

There is no scheduler. `AiMakeTask` is an ordered list of `if` statements, and
each one either **takes** the constructor or passes it on. Priority is therefore
encoded implicitly in the order the branches happen to sit in a function — which
is invisible, untunable, and identical whether the AI holds one constructor or
twenty.

That last part is the trap, and it has already been observed live: an AI with
**one** advanced constructor used it to build fusions and nothing else, forever.
Two reasonable rules produced it —

- own one advanced constructor and never build another (the `!gHaveAdvCon` cap)
- keep a fusion going up

— and neither is wrong on its own. With eight constructors, a rule that claims
one takes an eighth of build power. With one constructor, the same rule takes
**all of it**. Nothing in a winner-take-all list can express that difference,
because no branch knows how much capacity exists or how much it is consuming.

A phase does not fix this by itself. It narrows *which* rules compete, but the
winner still takes the whole constructor. Two things are needed alongside it:

- **Never let a rule take the last constructor.** A build-power floor reserved
  for ordinary expansion — mexes and upgrades — that discretionary rules cannot
  touch. One constructor means one job, and that job should be the economy.
- **Gate on share, not on truth.** "Is my condition true" scales badly; "would
  this be more than my share of current build power" does not. Build power is
  readable (`aiBuilderMgr.GetWorkerCount()`), so a rule can ask whether it has
  already taken enough.

The general shape: the reason a dozen sensible rules cut metal production 4.3x
is that each of them was written as *"if X then take a constructor"* and none as
*"if X, and we can spare one"*.

## Priority is a function of the follow-through, not a constant

apexearth: *"why build another fusion if we are max energy? I'll tell you why,
because you're gonna make tons of advanced energy converters!! ah shit but you
never did... and then that dude never made t3... oops... and we get rekt."*

That is the whole problem in one sentence. A fusion at max energy is **correct**
if converters follow it and **wrong** if they do not — the same purchase, the
opposite verdict, decided entirely by something that has not happened yet. No
static priority can express that, because the number would have to change based
on a plan.

Measured over 8 games with the flat rule set:

| | apex | stock |
|---|---|---|
| spend on fusion + afus | 32% | 24% |
| energy wasted | 235,160 | 38,113 |
| T3 spend | **0** | 9,469 |

Both halves of the sentence, in numbers. The energy got built, the conversion
did not, and the metal that should have become a gantry is sitting in generators
feeding nothing. "We get rekt" is the T3 column.

The rule that falls out:

**Never buy a prerequisite unless the thing it is for is actually reachable.**

Reachable is answerable, not a guess:

- is there build power to do the follow-up, given the floor reserved for economy
- does the phase we are in (or the next one) include that follow-up at all
- can our constructors even build it — `armmakr` for the ground line, `armmmkr`
  for the advanced one; a converter no constructor of ours can build makes the
  fusion permanently wasted (see `docs/11-dead-unit-references.md`)

Which suggests generation and conversion should be treated as **one purchase**
rather than two rules that happen to run in sequence. A fusion whose converters
are not affordable is not a cheaper fusion — it is a dead 4,300 metal, and the
opportunity cost lands on whatever the next tier was going to be.

The same test generalises to every prerequisite in the game: an advanced plant
whose units we will not fund, a gantry with no economy behind it, a radar hub
whose jammers never come. Ask what the purchase is FOR, and whether that thing is
reachable, before spending on the step that enables it.

## Hardest part

Not the phases — the transition conditions. "Ensure we have enough energy and
metal to build T2 and afford those expensive units" is the right intent and needs
real numbers behind it. Those numbers are measurable now (`composition.py` gives
per-phase spend, income and upgrade counts), so they should be read off games
rather than guessed, and written here when they are.
