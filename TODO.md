# Plays and behaviours he has asked for, not yet built

One file per play in `todo/`, one line per file here. `ISSUES.md` is what is wrong now (with evidence);
`USER-FEEDBACK.md` his open asks; `docs/doctrine.md` the principles. His words carry intent; a number in them is the
symptom he was watching, not a threshold. When a play is built and measured, delete its file and its line. Older
text: `git log -p TODO.md`.

## Team strategies and personalities

| Play | His date | In one line |
|---|---|---|
| [team-strategies](todo/team-strategies.md) | 10-24, 11-02 | Team strategies that shift: build-up, strike, follow-up; one pick on every host |
| [t3-style-screen](todo/t3-style-screen.md) | 11-01 | toward the gantry early, then T3 behind a screen of scouts |

## Know them, then hit with conviction

| Play | His date | In one line |
|---|---|---|
| [air-scouts-for-the-army](todo/air-scouts-for-the-army.md) | 10-22 | air scouts priced by what the army gains from the look |
| [mass-then-commit](todo/mass-then-commit.md) | 10-22 | one big attack, not many small ones; no trickle-back |
| [adapt-by-realized-return](todo/adapt-by-realized-return.md) | 10-22 | a line that keeps failing prices itself down |
| [strike-their-aa](todo/strike-their-aa.md) | 10-23 | their AA as a target; the air waits until it falls |
| [offensive-air-escalate](todo/offensive-air-escalate.md) | 10-24 | after failed runs, bigger waves, not none |
| [air-arrives-together](todo/air-arrives-together.md) | 10-24 | wings timed to reach the target together |
| [gunships-answer-raids](todo/gunships-answer-raids.md) | 10-23 | gunships sent at a raid on our mexes |
| [air-swarms-slow-push](todo/air-swarms-slow-push.md) | 10-23 | a packed enemy army as a strike target |
| [aa-answers-big-air](todo/aa-answers-big-air.md) | 10-23 | our AA stayed small against a huge late air attack |
| [ultra-late-air](todo/ultra-late-air.md) | 10-22 | air falls off late; a game-ending strike |
| [lrpc-volley](todo/lrpc-volley.md) | 10-18, 10-23 | the LRPC volley priced, not each gun alone |
| [dont-let-them-mass-lrpcs](todo/dont-let-them-mass-lrpcs.md) | 10-23 | their LRPCs and frames as top targets |
| [one-target-late-game](todo/one-target-late-game.md) | 10-23 | LRPC, nukes, air and T3 on one target |

## Next big job

| Play | His date | In one line |
|---|---|---|
| [one-pricing-scale](todo/one-pricing-scale.md) | 10-19 | THE CURRENT JOB (valuation): one inherited price, then no overrides |

## Team T2 and the economy ramp

| Play | His date | In one line |
|---|---|---|
| [fly-t2-cons-to-allies](todo/fly-t2-cons-to-allies.md) | 10-19 | transports deliver T2 constructors to allies |
| [eco-ramp](todo/eco-ramp.md) | 10-20 | his eco-test notes: upgrades, turrets ahead, packing |

## Strategies

| Play | His date | In one line |
|---|---|---|
| [hold-and-let-them-come](todo/hold-and-let-them-come.md) | 09-01 | abuse BARb: the bait, healers, reclaim after a win |
| [siege-screen-and-deep-raid](todo/siege-screen-and-deep-raid.md) | 09-01 | two squad doctrines |
| [anchored-range-ladder](todo/anchored-range-ladder.md) | 09-01 | the anchored range ladder: one Mammoth, all guard it |
| [finish-a-won-game](todo/finish-a-won-game.md) | 09-18, 10-12 | what a human would do to us |
| [jammer-ring](todo/jammer-ring.md) | 09-21 | a jammer-covered ring as a priced stall |
| [three-detectors](todo/three-detectors.md) | 08-19 | complacency, being pushed, the wrapping flank |

## Unbuilt behaviours

| Play | His date | In one line |
|---|---|---|
| [glacier-two-lanes](todo/glacier-two-lanes.md) | 11-03 | wall one approach, push down the other |
| [squad-judged-record](todo/squad-judged-record.md) | 09-16 | a squad's record against a unit |
| [formation-spacing-by-type](todo/formation-spacing-by-type.md) | 10-11 | spacing and squad membership per type |
| [metal-maps](todo/metal-maps.md) | 10-08 | an extractor farm on metal maps |
| [late-game-tips](todo/late-game-tips.md) | 09 | air cons, cloaked commander, hills, Behemoths |
| [size-raid-to-target](todo/size-raid-to-target.md) | 08-09 | scout first, size the group to the target |
| [t3-rim-raider](todo/t3-rim-raider.md) | 08-09 | a lone T3 raider round the map edge |
| [basemap-territory](todo/basemap-territory.md) | 09-05 | defence and army as substitutes |
| [airlift](todo/airlift.md) | 09-24, 10-07 | lifted turrets and towers, a hidden base |
| [escort-by-risk](todo/escort-by-risk.md) | 09-24 | escort sized to the trip's risk |
| [build-from-the-want](todo/build-from-the-want.md) | 09-20 | the want first, then the hand |
| [early-game-directives](todo/early-game-directives.md) | 09-22 | the commander's walk; guard energy |
| [spread-eco-risk](todo/spread-eco-risk.md) | 10-14 | the share of eco we can lose at once |
| [seat-merge](todo/seat-merge.md) | 09-30 | Seat merge: built, off, unfinished |
| [lobby-bot-host](todo/lobby-bot-host.md) | 09-30 | host from a lobby bot (parked) |
| [map-lag-pathing](todo/map-lag-pathing.md) | 10-19 | lag on maps: stuck units, unreachable ground |

## Move the hot script into C++ (his 11-03: "we've just always had performance issues")

Wanted eventually, not this week. In his 16-seat 8v8 (v0.5.05, 1x) the scripts were ~85% of AI time (19.5 of
23 s per seat per game-minute) and 0.76 ms per AI per frame against the 0.417 ms budget. The builder election
leads (hk.maketask.builder 903 ms, bld.pump 460, bld.decide 375 in one window); want.protect, want.mexup,
want.mex next. AngelScript has no JIT here. The plan: the election's inner pricing loop as C++ bindings, the
rules staying in script (hot-swappable deploys, tunables, nets); proven identical on fixed seeds by the decide
lines; measured with frametime.py. Not Rust: CircuitAI and the script bindings are C++.
