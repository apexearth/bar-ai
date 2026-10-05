# 33 — Turning the 2026-10-03/04 exceptions into prices

His instruction, 2026-10-04: "think macro about all these exceptions and choices"
and then "start turning them into prices". Each rule below fixed something
measurable, and each is a queue-jump that skips the market. `value-paradigm` is
the frame: a choice that comes out wrong has a mispriced term, and a rule on top
is a bug wearing a fix's clothes. The obligation that comes with it: log what
carries the winning choice and the runner-up before repricing.

| Rule (switch) | What it fixed, measured | The price that should replace it | State |
|---|---|---|---|
| Far hands keep claiming: skip estall/role/metal-first, take the nearest spot (`apex_far_hand_s` 45 s) | walk-backs 22% -> 7%, mexes at 12 min 22 -> 32.5 (4 seeds vs BARb) | **DONE 2026-10-04: builder time at the hand's runner-up with one step of foresight (`OppTimeReprice`): delay to the best other job = walk(A)+build(A)+walk(A->B)-walk(B), at its stream. vs v0.1.4 (far rule): walk-backs 19% vs 18%, home hands 6.4/8.1 vs 6.0/8.0, eco at 16 min 100 vs 82 at +50% handicap (+22%); wins 21-27 over +0% and +50% (n.s.). Far rule and both tunables deleted.** Before it, tried and removed: comparative advantage (ticket x (this hand's price / best price any hand saw lately)^2), in the draw alone (walk-backs 24% vs v0.1.4's 12%) and in the estall/role/unlock-assist overrides too (31% vs 20%; 11-13). A far hand's price for a home job is barely below a home hand's -- the walk is a small part of the price -- so the ratio stays near 1. | done |
| Extractor gun queue-jump while losing >= 10% (`apex_mex_loss_cover`), always for far hands | half of all builder decisions were guns; gated +22% eco (n.s.) | The protect price at a mex reads the measured loss share as its hazard (it already reads the structure-loss field); no push | open |
| Base-front lasers while out-massed or recently attacked (`apex_base_front`) | 1-2 -> up to 13 base guns | Drop the wall's "ring waits for the line" suppression (`WallDirW` rear minimum while the line has an open slot) and let the threat bearing price the ring | open |
| Commander to the lab while escorts are owed, and every other minute of the opening (`apex_com_escort`, `apex_com_lab_early`) | early constructor losses 0.9 -> 0.5 by minute 10 | His build power at the lab priced as army arriving sooner, past `FreeMetalFlow` only by what the bank holds; the escort case as the expected constructor loss it prevents | open |
| Escorts: cap 8, 2 per exposed constructor (`apex_escort_cap`, `apex_escorts_per_con`) | same | An escort's worth = exposure x constructor value at risk, against the unit's army value elsewhere; no count | open |
| Army spend weight 6 (`SPEND_ARMY`) | army at 12 min +2% -- one lab is the bottleneck | A weight, not a rule: belongs to the search | search |
| One lab per 50 m/s (`apex_plant_income_per`) | -- | Belongs to the search; "a same-tier second lab must lose on price, never by rule" | search |

How each conversion is judged: run_tournament (records carried) against the
release that carries the rule, 24+ games, plus the mechanism the rule fixed
(walkback.py, condeaths.py, armyby.py). A conversion is kept when it holds the
mechanism within noise and does not lose games; then the rule and its tunable
go in the same commit ([[proven-changes-lose-their-tunable]]).
