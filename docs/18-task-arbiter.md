# Wants and an arbiter — replacing the first-match ladder

apexearth: *"what if we created a stack/list of all the things we wanted to do and
then properly prioritized them after in some process which has a better macro
view?"*

Yes. This is the right shape, and today's mex-upgrade investigation is the
argument for it.

## What is wrong with the ladder

`builder/maketask.as` is an ordered pipeline: `AiMakeTask` is called for ONE
constructor, each rule is asked in turn, and **the first rule that returns a task
wins**. That has three properties that keep producing the same class of bug.

**Position is the only priority.** A rule's importance is expressed solely by where
it sits in the list, so tuning it means moving it past unrelated rules. Measured
today: `CommanderMexGuard` sat above `DefaultMakeTask` and took 162
constructor-picks against 4 mex upgrades in one game -- not because a turret was
judged more valuable than a moho, but because it was earlier.

**No rule can see what the others wanted.** Each returns a task or null, so nothing
compares "a moho worth ~1.8 metal/s" against "a turret that covers a bare mex"
against "a fifth reactor". The five-AFUS case is the same hole from the other
side: `HomeEnergy` enqueues directly and no other rule can know it already did.

**Decisions are per constructor, never per team.** Each call answers "what should
THIS unit do", so nothing asks "of everything the base could be doing with 12
advanced constructors and a full bank, which twelve things are worth most?"

## The shape that fixes it

Split *proposing* from *choosing*, which the ladder currently conflates:

    rules  ->  Want{ kind, pos, def, value, urgency, tier, cost }  ->  arbiter  ->  enqueue

- A **Want** is a proposal, not a task. Cheap to produce, no side effects, and
  several may exist for the same thing.
- The **arbiter** runs once per tick with the whole list, ranks it, and enqueues
  the top N subject to global limits (build power already committed, bank,
  energy).
- Only the arbiter enqueues. Rules stop having side effects, which is what makes
  them testable.

**Scoring, concretely.** The unit that makes economic sense here is *metal per
second gained per metal spent, discounted by how long it takes to pay back*:

    value = expected_income_gain / cost          (economy: mex, moho, reactor, converter)
    value = threat_denied / cost                 (defence: turret, AA, shield)
    value = enemy_metal_removed / cost           (offence: silo, gantry, pushes)

with two multipliers the ladder cannot express at all:

- **urgency** — a bare mex under observed threat outranks a moho; an idle factory
  with a full bank outranks both. This is where "if we don't have any upgraded
  mexes and we're poor, upgrading is priority #1" lives, as a number.
- **phase** — `docs/12-build-phases.md` already defines what we are buying now.
  The arbiter is the consumer that document was missing.

## Why this is worth the refactor

Every unexplained result today becomes a printable line:

- *Why no mex upgrade?* Because these five Wants outranked it, with their scores.
- *Why five reactors?* Because five Wants for the same def were all admitted --
  the arbiter caps by kind.
- *Why 41% waste with idle factories?* Because the Want list was empty and nothing
  proposed spending. That is a visible, alarming state instead of a silent one.

And the audit gains its most useful check: **the arbiter's own ranking is a log
line**, so `tools/audit.py` can assert "a moho was available and something beat
it" rather than inferring starvation from outcomes three layers downstream.

## What it cannot fix, and must not break

- **The engine still creates work we do not see.** `CEconomyManager` enqueues MEX,
  MEXUP, energy and factory tasks in C++, and `CBuilderManager::AssignTask`
  matches builders to tasks by its own priority/distance rules. The arbiter
  proposes on top of that; it does not replace it. `DefaultMakeTask`'s offer
  should enter the list as a Want like any other, which is what
  `ExpansionAlwaysWins` does crudely today.
- **Reflexive rules must stay outside it.** Repair-nearby, retreat, abandoning an
  unsafe site and the commander's own safety answer something happening NOW.
  Ranking them against a reactor is a category error; `docs/12-build-phases.md`
  already draws this line and it holds here.
- **A ranked list can starve the tail.** Anything scored lowest never runs. Needs
  ageing (a Want's score rises while it waits) or per-kind floors, or the AI
  stops doing whole categories of thing and looks broken in a new way.

## Staging it, so it is measurable at every step

The 2026-08-01 finding says a batch of changes tells you the batch is bad and
nothing about which member. So:

1. **Instrument only.** Every rule that fires also records a Want (kind, value,
   cost). Nothing changes behaviour; the log gains a ranked list per tick. This
   alone answers "what displaced the upgrade" for free.
2. **Arbitrate the optional class only** -- gantry, silo, Pulsar, Pinpointer,
   shield, converter, reactor, nano. These are the open-ended investments, they
   are already gated behind `MexUpgradesOutstanding()`, and they are where the
   displacement measurably happens.
3. **Add expansion** (mex, moho) as Wants competing on income-per-metal.
4. **Add defence**, which needs `threat_denied` to mean something -- the hardest
   scoring problem and the last to attempt.

Stage 1 is worth doing regardless of whether 2-4 ever happen: it is the missing
instrument, and it costs no behaviour change to find out.

## Which strategies belong in the Brain, and which do not

apexearth listed five: air assassin, nuke strategies, eco lead, tech lead,
slinging. They are not one kind of thing, and forcing them into one mechanism
would be the mistake this design is meant to avoid.

**Two faculties, one macro state.**

| faculty | question it answers | mechanism |
|---|---|---|
| **Wants** | what should this metal / build power / squad buy? | ranked by value per cost |
| **Roles** | which PLAYER on this team plays which part? | assignment over the team blackboard |

Ranking answers "is a moho worth more than a gantry". It cannot answer "which of
eight players should be the tech lead" -- that is an assignment problem with one
winner and seven losers, and squeezing it into value/cost would lose the
constraint that makes it work.

### Wants (route these in)

- **Air assassin.** Today it is a veto: `air assassin holding off -- losing the
  ground war`, 31 times in one game, which is circular -- we are behind, so air
  stands down, so we stay behind. As a Want it is `enemy_metal_removed / cost`
  and "losing the ground war" becomes a multiplier on value, not a gate. A raid
  that removes 3,000 metal of undefended economy should outrank a gantry whether
  or not the ground war is going badly.
- **Nuke strategies.** Two separable pieces. Building a silo is a Want
  (`docs/16-big-plays.md` stage 0, 8,100 metal and 90,000 energy each, currently
  nothing proposes them). The salvo TRIGGER is not -- it is a policy over a count
  the Brain already holds, and it fires when enough silos are loaded.
- **Slinging.** Metal sent to an ally competes directly with metal spent here, so
  it is a Want whose value is "what the receiver converts it into, minus what we
  would have". Needs the team layer below.

### Roles (route in, different mechanism)

- **Eco lead** and **tech lead** are elections: exactly one player takes the part
  and the rest defer. They already run over `PublishTeamValue`/`ReadTeamValue`,
  which is the right substrate; what they lack is a shared view of what the team
  is short of. The Brain should own that state and the election should read it,
  rather than each player deciding alone from its own economy.

### Neither (leave alone)

Reflexive rules -- repair nearby, retreat, abandon an unsafe site, commander
safety. They answer something happening NOW. Ranking a wounded constructor
against a reactor is a category error, and `docs/12-build-phases.md` already
draws the same line.

### Order to do it in

One per validation cycle, because the 2026-08-01 finding is that a batch tells
you the batch is bad and nothing about which member. Measured payoff first:

1. **The optional class** -- gantry, silo, Pulsar, Pinpointer, reactor, converter,
   nano. Already gated behind `MexUpgradesOutstanding()`, so the ranking replaces
   a crude boolean with a comparison, and the mex Want has something to rank
   against. (Stage 2 of the plan above.)
2. **Air assassin**, which converts a circular veto into a value.
3. **Slinging**, which needs the team layer and is the first genuinely team-wide
   Want.
4. **Roles**, last, because they need the Brain's team state to exist first.

## Three faculties, not one

apexearth's second list -- where is their main base, where are my defensive gaps,
is my commander in danger, is T3 walking at him, have they gone quiet, do they
have twenty silos, should I make spam to distract them, which target should the
air squad take -- is not more Wants. It is a different faculty, and the Brain
needs three:

| faculty | question | output | example |
|---|---|---|---|
| **Knowledge** | what do I believe, and how stale is it? | beliefs with confidence | "their main base is here, seen 4 min ago" |
| **Wants** | what should this metal buy? | ranked proposals | a moho beats a gantry |
| **Directives** | what should these units do? | standing orders | "air squad: this target, this approach" |

Knowledge feeds the other two. A nuke Want cannot be scored without a belief
about where their base is; an air Directive cannot pick a target without one
about where their AA is not.

**Beliefs must carry staleness, and unknown must never read as zero.** This is
the failure mode already on record here twice: `GetEnemyCost` only accumulates on
EnemyEnterLOS, so a zero means "not looked", not "not there" -- which is how an
unscouted enemy army read as 90 metal and a team push fired on ignorance. Every
belief needs a `lastSeen` frame and a confidence, and every consumer needs to
treat low confidence as danger rather than safety.

### What each item needs, and what exists today

| apexearth's item | needs | available now |
|---|---|---|
| where is their main base (nuke targeting) | belief with staleness | `aiEnemyMgr.GetEnemyPos()`, `ai.GetEnemyCostAt(pos, r)` -- a centroid exists, confidence does not |
| gaps in my defences | coverage map over our territory | `DefenceWithin(pos, r)` and the front line exist; nothing sweeps for holes |
| danger approaching the commander | threat at a moving point | `ai.GetUnitThreatAt(unit, pos)`; `apex_comm_flee_influence` exists and is OFF |
| T3 walking at the commander: d-gun or evade | enemy def identity nearby | **missing** -- no binding enumerates enemy units near a point by def |
| they have gone quiet, scout them | time since last LOS on anything of theirs | **missing** -- needs a lastSeen ledger; scouting itself exists |
| they have 20 silos, build anti-nuke | enemy count BY DEF | **missing** -- `GetEnemyCost(Type)` is by role, not by def |
| spam to distract, auto-move into their half | factory ratio + standing move order | ratios exist; a standing "send these there" directive does not |
| tell air squads about high-value targets | target list + safe approach | `GetAttackHotspot` exists; `apex_attack_threat_mod` is the routing lever and is unmeasured |

Three of the eight need new bindings. That is the honest cost, and it is worth
paying: "enemy units near a point, by def" unlocks the commander d-gun/evade
decision, the anti-nuke response and most target selection at once.

### Where this goes wrong if rushed

- **A belief store that nothing consumes is dead weight.** Add each belief WITH
  its first consumer.
- **Directives fight the task system.** CircuitAI already assigns units to tasks;
  a Directive that issues raw orders will be overwritten next frame. They must be
  expressed as task preferences, not as commands.
- **Confidence gets ignored under pressure.** The temptation is always to treat a
  stale belief as fact because it is the only one available. The consumer, not
  the store, has to decide -- and "unknown" must cost something.
