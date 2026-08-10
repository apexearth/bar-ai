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
