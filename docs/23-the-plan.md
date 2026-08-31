# The plan

*apexearth's mentality for this AI, 2026-08-31, stated once and kept short on
purpose. Operational detail — the formulas, the worked cases, what the frame
forbids — lives in the `value-paradigm` skill. This file is the intent those
mechanics serve, and it is the thing to read first.*

Every decision this AI makes is an answer to a single question: **what is the
fastest path to the state I am trying to reach?** Not "what is worth the most
right now" — that is a shopkeeper's question, and it cannot see that a move
which looks poor this minute may arrive sooner. The AI names a target — ten
thousand metal of army; or five thousand of army with a fusion standing behind
it — and then works out, in seconds and honestly, which of the moves available
to it makes that target arrive first. Investing in the economy wins whenever
the income it returns pays for itself before the target is due, and loses when
it does not. Nothing is sequenced by hand, because the sequence is a *result*:
mexes before tech, upgrades after tech, and a constructor rather than another
building whenever the plan is short of hands rather than short of metal — all
of it falls out of the same arithmetic, and none of it needs a rule.

The numbers that would otherwise harden into thresholds are consequences too. A
rung of the economy is not reached at an income; it is reached when the cheaper
growth beneath it is **exhausted** — spots taken, upgrades done, or ground we
cannot hold — at which point energy and conversion are simply what is left to
buy. And because a target is worth nothing to a player who dies before reaching
it, the whole plan runs under one standing obligation: **army and defence are
held at their proper share of the economy we have built**, and the search for
the shortest path proceeds with what remains. Dropping below that share is not
thrift. It is borrowing against survival, and the debt is always called.

## What this rules out

- **Thresholds.** "Go T2 above N metal/s" is a claim the arithmetic should be
  making for us. If a number is needed, the model produces it; we never supply
  it.
- **Hand-written sequences.** Build orders, phase tables, "first this then
  that". The order is an output.
- **Caps, floors and exclusivity.** Nothing is forbidden to a player or capped
  at a count; a choice that should not happen is one whose ETA is worse.
- **Greedy pricing as the last word.** A per-instant value is how one step of
  the plan is costed, not what the plan optimises. Where the two disagree, the
  ETA to the target is right.
