# The army layer (design, 2026-10-16)

Why the army has resisted months of fixes, and the shape that replaces it. Every change to army
control follows this document; where code disagrees, the code is the bug.

## Why it kept failing

1. **No single owner.** Raid nets, hunts, strikes, team pushes, the fight estimate, gather, focus
   fire, withdraw and the C++ tasks each ordered the same units and undid each other.
2. **No visible state.** No log said why a unit walked in, so fixes chased symptoms.
3. **Slow, noisy verification.** Twenty-game batches judged changes by averages; an inert fix
   survived for hours.
4. **Big-bang changes.** Each layer arrived large, untested, on top of the others.

## The shape

- **One owner.** `Army` owns every combat unit from the moment it is built. Only a `Squad` issues
  commands to its members. Nothing else in the AI may command a combat unit; a static check
  enforces it.
- **The army decides what, the squad decides how.** The army hands each squad an intent (hold here,
  take this area, defend this place). The squad turns it into moves, fights and targets on its own
  update.
- **One assessment.** `assess(at, radius)` returns their strength and ours that can be there,
  calibrated against fight outcomes. Every decision that weighs a fight calls it; nothing keeps a
  private estimate.
- **A small, explicit state machine per squad**, each transition logged with its reason:
  `forming -> moving -> engaged -> {winning: continue | losing: falling_back} -> regrouping -> forming`.
  Membership is open only in `forming` and `regrouping`.
- **Air squads** are the same type with a different `update` (search, strike, return).

## How changes are made

- **Scenario tests first.** A behaviour is written against a short scripted scenario (a few
  minutes, fixed units: a squad meets an LLT with a Centurion beside it; a raid meets their army; a
  commander walks into our base). The scenario passes or fails on a counter in a minute, before
  any full game.
- **Then three or four games** against BARb. A landslide decides; only a close result earns more.
- **Counters before scores**: units that died alone, standing still, joined after commit, or
  walked into armed reach they could not beat. A change that does not move its counter did
  nothing, whatever the score says.
- **One behaviour per change**, small enough to read in one sitting.

## Order of work

1. `TUNE_STOCK_ARMY`: our economy with stock BARb army control -- the floor and the census of
   every layer that must go quiet.
2. The skeleton: `Army`, `Squad`, `assess`, the state machine and its log, owning units under one
   switch, with the simplest behaviours (guard home, form, advance together, fall back whole).
3. Behaviours one at a time, each with its scenario: defend, raid the flanks, focus fire,
   matchups, air.

## Scenarios

`python tools/scenario.py run all --parallel 2 [--ai-option K=V]` plays each spec in
`tools/scenarios/` on Geyser Plains through `dev_scenario.lua` (`deploy_ai.py gadgets`, or
`--install-gadget` for that one file): starting units removed, units spawned at frame 90, global
LOS, resources topped up, about 50 s wall at `--speed 20`. Groups with a scripted order belong to a
NullAI holder on that side; `disableAiControl` is read only when CircuitAI loads a save, so it
cannot take a unit from an AI. `judge <dir>` re-reads a run. One run each, `apex_stock_army=1` on
Apexc9 vs BARb hard, 2026-10-16:

| scenario | passes when | stock baseline |
|---|---|---|
| `llt_trickle` | no bot reaches the LLT + Centurion, or all but one arrive within 4 s of the first, at most one dies alone | PASS: 0/12 lost, none came in reach; the raid group skirted the map edge for 2 min |
| `open_blob` | 6 of 8 survive 10 Centurions + 10 Pawns walking at them, at most one dies standing | FAIL: 5/8 dead, 1 alone, 0 still; killed 7/20 (270 m lost, 378 killed). An earlier run: 4/8 dead, killed 1 |
| `com_in_base` | the walking commander dies, all but one bot arrive together, at most one dies alone | PASS: the two LLTs killed it at 35 s and died in its death blast; the 10 bots were away raiding and never came in reach |
| `flank_mexes` | 3 of 4 flank mexes die and half the pack of 8 lives | PASS: 4/4 mexes by 26 s, no losses (same in an earlier run) |

`apex_squads=1` (on `apex_stock_army=1`, `military/army/`; `python tools/scenario.py run all --parallel 2
--ai-option apex_stock_army=1 --ai-option apex_squads=1`), first run 2026-10-16 (6d6706b9):

| scenario | squads | why |
|---|---|---|
| `llt_trickle` | PASS, but 9/12 dead, killed 0 | went in together and never turned |
| `open_blob` | FAIL: 6/8 dead, killed 3 | launched at `them=0/0` (registry half-scanned), then engaged never let go |
| `com_in_base` | FAIL: trickle 2, alone 1; commander killed | 8 launched; 2 claimed a moment later launched alone |
| `flank_mexes` | PASS: 4/4 mexes, no losses | |

Never turning: comfight's band with no measured fight is the whole estimate, `|L - K| <= sqrt(L^2 + K^2)`, so
the hysteresis never crossed; under stock army nothing fed the calibration. Fixed next: the registry is read whole
each update, the reach counts our own closing as comfight's does, the band is 0 until a fight is measured and each
squad fight feeds `CfCalAdd` (`apex: squad-fight`), a squad that grew since the last update waits one, and every
transition after an estimate logs its inputs (`apex: squad-assess`).

What each scenario should show if the skeleton works: `open_blob` -- no launch (the blob reaches every path), the squad gathers at home out of
its reach; `llt_trickle` -- one launch of all 12 at the Centurion if the estimate wins there, else none;
`com_in_base` -- the whole squad onto the commander (an army target, or guard-home once it nears our buildings);
`flank_mexes` -- launch at the best mex, `at-target`, then `fight-over` -> `retarget` mex by mex.

Two stock passes come from absence: a pack that is elsewhere neither trickles nor dies alone. The
scripted commander never D-guns. `contact` is sampled every 15 frames; "still" is under 40 elmos
moved in the 3 s before death.
