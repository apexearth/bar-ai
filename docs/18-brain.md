# The Brain — a macro view that decides, instead of a first-match ladder

apexearth: *"I want it to generally be a macro-view brain/logic center."*

Three faculties: **Knowledge** (what do I believe, and how stale is it),
**Wants** (what should this metal buy), **Directives** (what should these units
do). The ranking described first is the Wants faculty; the other two are further
down, and Knowledge is what makes the other two scorable at all.

apexearth: *"what if we created a stack/list of all the things we wanted to do and
then properly prioritized them after in some process which has a better macro
view?"*

Yes. This is the right shape, and today's mex-upgrade investigation is the
argument for it.

**The rest of this document is the design. What is actually built is the next
section — read that first if you are about to change the code.**

## What exists today (2026-08-10)

Two files, both in the `Brain` namespace, both included from
`script/hard_aggressive/main.as`:

| file | faculty | entry point | called from |
|---|---|---|---|
| `manager/brain.as` | **Wants** — what should this metal buy | `Brain::Decide(unit, isAdvCon)` | `builder/maketask.as`, above `OptionalWork` and below the engine's expansion offer |
| `manager/brain/mix.as` | **Composition** — what should this factory build | `Brain::MixTask(fac)` | `factory/maketask.as`, above the generic production branches and below the specific floors (assist, air, rez) |

**Directives do not exist yet, and Knowledge exists only inside the mix.**
Nothing carries a belief with a `lastSeen`; what `mix.as` has is the one property
the design insists on — *unknown must not read as zero* — expressed as a
confidence weight rather than as a stored belief. See "Knowledge, as far as it
goes" below. The belief tables further down are still a plan.

### Wants — `manager/brain.as`

A `Want` is `{kind, value (metal/s gained), cost (metal), pos, def, have}`.
`Decide` proposes, ranks, then acts:

    Score() = value / (1 + have) / cost        [× ECO_SATED_MULT for eco kinds when both banks are full]

`/(1 + have)` is what stops one cheap thing winning forever — without it a
Pinpointer (0.5 metal/s, ~800 metal) outscored a nuke silo (4.0, 8,100) and took
every pick.

Kinds proposed today, with their compiled values in metal/second-equivalent:

| kind | value | executed by | gate |
|---|---|---|---|
| `mexup` | 3.6 (moho over mex) | `aiBuilderMgr.EnqueueMexUp` directly | an extractor of ours within 2400 |
| `energy` | 1.2 × 6.0 while stalling | `Builder::HomeEnergy` | only proposed while `isEnergyStalling` |
| `convert` | 1.0 | `Builder::EnergyConverter` | post-T2, `Builder::EnergyWasting()` |
| `nano` | 7.0 | `Builder::EcoNano` | post-T2, metal full |
| `frontnano` | 3.0 | `Builder::FrontNano` | post-T2, `apex_front_nano` |
| `gantry` | 2.0 | `Builder::SurplusGantry` | post-T2 |
| `silo` | 4.0 | `Builder::NukeSilo` | post-T2 |
| `pulsar` | 1.5 | `Builder::Pulsar` | post-T2 |
| `pinpoint` | 0.5 | `Builder::Pinpointer` | post-T2 |

Four rules of precedence sit around the ranking, and each exists because
measuring without it went backwards:

- **Advanced constructors only.** `Decide` returns null for anyone else.
- **Nothing optional before T2 exists.** With `Factory::gHaveT2` false, only the
  mex upgrade and an energy stall may be proposed — converters, nanos and
  reactors had starved the advanced plant that unlocks the rest.
- **Upgrades are not optional spending.** If a `mexup` Want is in the list, no
  other kind may execute this tick; a failed enqueue falls back to the engine's
  own work rather than starting something else. Lifted once both banks are full.
- **The Brain decides ORDER, not eligibility.** Every kind except `mexup` is
  executed by calling the existing rule, which keeps its own preconditions; if
  it refuses, `Decide` falls through to the next-ranked Want.

`Brain::Execute` is the kind → rule table. **Adding a Want means adding a line
there as well as a `Propose` call**, or the Want ranks and can never fire.

The ranked list is logged in full every 30 s as `apex: brain wants=N | kind=score
…`; the chosen one as `apex: brain picks <kind> score=…`; ordered upgrades as
`apex: brain orders mexup #N`.

`EnqueueMexUp` is ours — `cpp/src/circuit/script/BuilderScript.cpp`. A MEXUP task
carries a metal-spot INDEX as well as a position, so the generic `Enqueue` could
not express it, which is why no rule of ours could order an upgrade before this.
How many upgrades the engine will hold open is still C++, in
`CEconomyManager::UpdateMexUp`, tuned by `apex_mexup_per_income` /
`apex_mexup_full_bonus` / `apex_mexup_first`.

### Composition — `manager/brain/mix.as`

The same inversion applied to production: instead of "what should this factory
build NEXT", a target share of army METAL per role is stated and each decision is
"which role is furthest below it". Targets: raider .30, assault .30, skirm .15,
riot .10, arty .08, AA .07. One unit is chosen per call, so the army *converges*
rather than being reset.

Two things about it are load-bearing:

- **Build power is a FLOOR, not a share.** As a share (0.15) it never won —
  combat shares start at zero and are constantly emptied by losses, so the
  largest gap is always a combat role. `BuildPowerFirst` runs before the ratio:
  one constructor per `apex_mix_con_income` (30) of metal income.
- **Ownership.** The first successful enqueue claims that factory
  (`Brain::OwnsFactory`), and from then on the apex production rules are skipped
  for that line entirely — an owned line that the mix cannot answer falls through
  to `aiFactoryMgr.DefaultMakeTask`, never to our floors. `factory/hooks.as`
  releases the id when the factory dies. apexearth: *"make sure the old system
  doesn't interact with that factory and add its own things."*

- **Eyes are a floor too, and for the same reason.** `ScoutFloor` runs after the
  build-power floor and before the ratio. A scout share cannot work: scouts are
  the cheapest units in the game, so a metal share big enough to yield a useful
  COUNT is a large share of the army and one small enough not to distort it
  yields none. The wanted number follows the ground there is to watch —
  `1 + mexes / apex_mix_scout_per_mex` (4) — and the def's own `IsAvailable`
  enforces behaviour.json's `limit`. Off with `apex_mix_scout=0`.

  Until this existed an owned line could not build a SCOUT at all: the mix table
  is combat roles only and a claimed factory skips every rule below it. That is
  the mechanism behind *"enemy super light units would harass our early game
  mexes very effectively and we didn't have any super lights of our own."*

  Know what it does NOT buy: `CMilitaryManager::DefaultMakeTask` gives a
  scout-role unit a SCOUT fight task whether or not `quota.scout` (2) is already
  met — the over-quota branch falls through to `Common(SCOUT)`. So extra Ticks
  scout, they do not garrison. The production answer to being raided is the
  counter weighting below, which turns enemy RAIDER cost into RIOT share, and
  RIOT is the role CircuitAI gives a DEFEND task.

Off with `apex_mix=0`. Logs `apex: mix claims <fac>`, `apex: mix scout #N`, and
`apex: mix -> <def> picks=N counterW=W | <the six targets>`.

### Knowledge, as far as it goes — `CounterShares()`

The base table is what we want in a vacuum. Each role also names the enemy roles
it answers — CircuitAI's own relations, stated where the roles are defined in
behaviour.json: riot answers raiders, skirmish answers riots and assaults,
assault answers statics. `response.json` encodes the same idea and **an owned
line never reaches it**, which is how the enemy could field a role we had no
production answer to with nothing in the path noticing.

    demand_i = sum over the roles i counters of aiEnemyMgr.GetEnemyCost(role)
    counter_i = demand_i / sum(demand)
    target_i  = base_i * (1 - w) + counter_i * w

The whole design of this is in `w`. `GetEnemyCost` only accumulates on
EnemyEnterLOS, so a zero is *not looked*, never *not there*:

    w = MIX_COUNTER_MAX (0.6) * seen / (seen + ours) * apex_mix_counter

With nothing scouted `w` is 0 and the balanced base table is used unchanged —
ignorance keeps the rounded composition instead of reading as "the enemy has
nothing", which is the exact failure that made a team push fire on an unscouted
army worth 90 metal. A glimpse of one squad while we hold an army barely moves
the target; a well-scouted enemy army moves it most of the way. It is capped
below 1.0 on purpose: the roles we hold for reasons the enemy does not dictate —
something to raid with, something to hold ground — have to survive a reading of
their army.

This is a confidence, not a belief: there is still no `lastSeen`, and a role the
enemy stopped fielding decays only as our own army grows. A real Knowledge
faculty would store both.

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

1. ~~**Instrument only.**~~ **Done.** Every proposed Want is logged with its
   score every 30 s, which is what answers "what displaced the upgrade".
2. ~~**Arbitrate the optional class only**~~ -- gantry, silo, Pulsar,
   Pinpointer, converter, reactor, nano. **Done**; shield is still not proposed.
3. ~~**Add expansion**~~ -- the moho Want landed with stage 1 and is the one
   thing the Brain enqueues itself. Plain mex claiming is still the engine's.
4. **Add defence**, which needs `threat_denied` to mean something -- the hardest
   scoring problem and the last to attempt. **Not started.**

Composition (`brain/mix.as`) was not on this list and arrived alongside stage 3;
it is the same inversion applied to the factory rather than to the constructor.

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
   against. (Stage 2 of the plan above.) **Done.**
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
