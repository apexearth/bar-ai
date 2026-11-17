# A seat that loses most of its base never rebuilds

His 11-14 (watching a hosted game): "when we lose too much of our base we don't rebuild. Something breaks and we
don't make the cons we need to keep building more."

## One measured case: matches/pkg0-cm-C9505, team 0 (estall, Cortex, Carrot Mountains)

- Income 60 m/s at 17.5 min, 0 by 25 min; labs gone (plant-halves logs, which only fire with no factory standing);
  495/500 metal banked and unspent for the last 12 minutes; built +0 per 2 min from minute 18 to 30.
- One T2 con left (a corack given by an ally, `unit-given`). Every election it wins `tech:corlab` with nothing in
  second place (`pricecard ... | 2nd -`), at a priced walk of 2,908-2,759 s although it stands ~150 elmos from the
  site (exec at=9336,548 task=9200,608).
- The order is released and re-taken every ~30 s (`order-release ... by=left / adopt / lines`, age=30-31), 140+
  requests; the lab never starts.

Same shape in pkg0-cm-A9502 t1, pkg0-cm-A9505 t1, hcL-v0-cc-L9481 t0: cons 0-1 and +0 built for many minutes.

## His ruling (11-14)

Building on an ally's ground is fine, own space preferred; a lost base on open, uncontested ground must be rebuilt.

## Found by the anomaly sweep (11-14, tools/anomaly_sweep.py)

98 seats on disk fell to 0-1 standing constructors (`conT1+conT2`) mid-game with their commander alive and labs still
producing (v0.5.11 too). aa1-cm-C9505 t0: cons 13 -> 0 over minutes 22-30, the con floor asking 75-77 and firing 3
times; 75 mex/moho lost, not rebuilt. Cause: the con floor yields to army (`foeOutguns`, `ftrOwed`, army share behind)
whatever hands are left. Fix: `apex_con_bare_floor` (production.as) -- below the base con floor (TUNE_CON_BASE, his
"2 or 3 cons at 12 income") it never yields. Contract check "bare-hands minutes".

## Found (11-14, same seat after minute 24)

`expand-stat`: own ground 24 open spots, mid 33, far 46 -- every one priced hot (`hotPriced=85`, `foeHeld=104`) and
economic power `P=0.00`; `valitem` offers only plant:corlab, tech:corlab and super:corint, no mex and no energy at all.
The enemy army sat on our base: every spot read hot, and with P=0 the lab orders were all that priced. The ally (t1)
still stood. So the open question is what a seat with one con, a full bank and an occupied base should do -- build on
the ally's ground, or hand the con and the bank to the ally -- not only which veto fired.

## Suspects, unconfirmed

1. No eco want at all reaches the con (no mex, no energy in the draw) -- the danger/risk vetoes around a lost base.
2. The walk term of a con in a wrecked base reads ~48 min; the lab order is released each re-election.
3. With no lab standing, the survivor never buys a cheap thing it can finish with the bank it has.

## Next

A scenario that wipes most of a seat's base mid-game (tools/scenario.py), then trace which rule blocks the rebuild.
Wanted behaviour: a seat that lost its base always has a path back -- income at the nearest spot it can hold, then
a lab, then cons; a danger veto must leave something it can build.

## 11-16: the open-ground case recovers on v0.5.14 (tools/scenarios/rebuild_bare.json)

One T1 con, two extractors, two solars, no lab, no commander, nothing of theirs near (Geyser Plains, NullAI): the con
builds extractors, orders a lab at 2.5 min (`request new armlab`, walk358 build530: no 48-min walk), the lab stands at
4.2 min and its queue runs (facqueue orders 4 -> 8, milreq 4-5), then a nano, an advanced solar and wind.
`matches/scenario-dev/20261116-094238-rebuild_bare`. The scenario banks 20k metal, so it shows the path, not its speed.

Our frozen seats in rc8-rc10 / na7-na9 (12 of 104 seat-games, release seats about as many) are the contested case:
rc10-rc2-C9704 t0 lost 21k in 2 min at minute 20 with the enemy army on its base (`foeHeld=100-120`, own spots
priced hot), cons 7 -> 0 as they died, the lab priced 1-8 against extractors at 40k. rc10-rc2-C9701 t1 rebuilt a lab
at minute 28 once the ground cleared. What remains is the fight for the base (validation row 114, his decision), not
a missing rebuild rule.
