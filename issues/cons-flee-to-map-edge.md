# Constructors run to the map edge when nowhere is safe (his 11-04)

**What he saw** (11-04, spectating a friend's hosted randomizer game, v0.5.05): constructors kept moving to the bottom
edge of the map and doing nothing. The randomizer gave some units very long-range lasers, so threat covered the base
too. His read: "even at home they feel unsafe and run to the map edge ... really there's no safer area ... might as well
just try to do their best".

**The rule it breaks:** a retreat is worth what it saves. Moving pays only when the threat at the destination is
meaningfully lower than where the unit stands *and* that drop is worth more than the work given up walking there and
idling. When threat is everywhere, the lowest-threat cell is barely safer and far from any job: stay and work.

**Where to look:** cpp/src/circuit/task/RetreatTask.cpp (wounded units walk to the lowest threat, taken when it is
under 0.8x the threat here: a relative test with no price on the work lost and no floor on how safe the refuge must
be), manager/builder/sitesafety.as and builder/events.as (site evacuation). The logs are on the host's machine, so the
first step is reproducing it here: a randomizer-style game (long-range units) or a crowded 8v8 where threat covers
the base, then `apex: retreat` lines and the cons' positions.

Randomizer games are analysed apart from version comparisons (memory: randomizer-games), but the flaw is general:
any game where threat is everywhere shows it.
