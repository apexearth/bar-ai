# What this AI does that stock BARb does not

One AI, built on BARb (CircuitAI). Everything here is a deliberate difference
from `BARb/stable`; anything not listed behaves as stock.

| variant | shortName | intent | best measured result |
|---|---|---|---|
| **apex** | `Apex` | team T2 rush in team games; stock behaviour with no allies | **1v1 vs `BARb:stable:hard`: 56-57 over 113 decided games (49.6%)**, 2026-08-10 |

`apexdef` ("hold ground, out-eco, finish with T3", 4-3 over 10 clean games) was
merged into apex and no longer exists as a separate variant.

`ai/ctl` (`ApexCtl`) and `ai/stk` (`ApexStk`) are measurement fixtures, not AIs
being developed: a frozen control for self-play A/B, and stock config + stock
script on the apex DLL to isolate what the DLL itself changes.

The 8v8 numbers that used to sit here (16-0 vs medium, 8-0 vs hard) were taken
on the `hard_aggressive` config base, which is no longer what apex ships. They
are not withdrawn, they are simply no longer about this build.


## Change log

Full detail moved to `changes/<date>.md`, one file per day, newest first. This index lists each day's entry titles; open the day file for the mechanism, evidence, and measurement.

Older reference/appendix material with no date of its own (binding tables, config tables, known-not-done lists): `changes/reference.md`.

### 2026-08-14

- 2026-08-14: opening-sequence income gate made economy-only, no time cap
- 2026-08-14: many DIFFERENT sites of the same building opened at once — VERIFIED

Full detail: `changes/2026-08-14.md`

### 2026-08-13

- 2026-08-13/14: the army answers one breach at a time, not all of them at once
- 2026-08-13/14: generator tier selection is one energy-per-metal ranking — VERIFIED
- 2026-08-13: duplicate energy buildings landed on the identical tile — VERIFIED
- 2026-08-13: defence budget is a share of metal, not a count of towers
- 2026-08-13: duplicate energy builds were checked against the wrong position
- 2026-08-13: radar towers were placed only where a wall also went up
- 2026-08-13: the enemy model never forgot, and raids never checked
- 2026-08-13: reactors started in parallel and never finished
- 2026-08-13: the front-hold gate skipped the merge, so the army could never mass
- 2026-08-13: rez bots had a hard cap of 8, and two of them
- 2026-08-13: a rezbot and a con turret fought each other over a windmill forever
- 2026-08-13: a T1 constructor was blocked by a job only a T2 one can do

Full detail: `changes/2026-08-13.md`

### 2026-08-12

- 2026-08-12: ally aid — the signal was already there, the response needs the DLL
- 2026-08-12: Fight is the wrong primitive -- move, and set-target the preference
- 2026-08-12: the standoff was silently reverted by a factory commit, and the ring leaked
- 2026-08-12 (night): five mechanisms, all found by agents from a watched game
- 2026-08-12 (evening): six things apexearth saw in one watched game
- 2026-08-12 (later still): the budget counted solar collectors as defence
- 2026-08-12 (later): the quota was building nothing but constructors, and the benchmark was hiding it
- 2026-08-12: factories run our own standing queue, not one CRecruitTask per unit

Full detail: `changes/2026-08-12.md`

### 2026-08-11

- 2026-08-11: three rules deleted, one real bug fixed, and a pattern banned
- 2026-08-11: the tower blobs were ONE rule, and its throttle was never wired
- 2026-08-11 (corrected): the safe ground exists, and it is EARLY
- 2026-08-11: there is no ground forward that a builder is allowed to work on
- 2026-08-11: WHY the front orders are never filled -- the site search refuses
- 2026-08-11: the front line is aimed correctly and almost never built

Full detail: `changes/2026-08-11.md`

### 2026-08-10

- 2026-08-10: the Brain — rules propose Wants, one ranking decides
- 2026-08-10: where the 1v1 ended up
- 2026-08-10: the 1v1 win rate is 1/66, and the 20-minute cap was hiding it
- 2026-08-10: `hard_aggressive` is a STALE stock profile, and apex was forked from it
- 2026-08-10: the fighter-task C++ delta costs 12 points, and is reverted
- 2026-08-10: apex stands aside when it has no allies, and moves onto the `hard` base
- 2026-08-10 (NEGATIVE): switching the T2 rush off in small teams changes nothing

Full detail: `changes/2026-08-10.md`

### 2026-08-09

- 2026-08-09: Behemoths charge the front instead of walking round the map
- 2026-08-09: units walled in by our own buildings get a way out
- 2026-08-09: the AI desynced multiplayer by asking the engine for a path
- 2026-08-09: the AI crashed the engine because C++ deleted tasks the script held
- 2026-08-09: the front line gets per-player sectors, and defenders stop garrisoning minute 5
- 2026-08-09: a raid that runs out of targets presses on instead of walking home
- 2026-08-09: T3 heavies hold the defence line instead of walking out alone
- 2026-08-09: keep building silos while both banks are over 80%
- 2026-08-09: nuke the army massed on our own border
- 2026-08-09: help the identical building already started, instead of starting a second
- 2026-08-09: mobile AA is all-or-nothing, and it never travels with the army
- 2026-08-09: long guns stand at 90% of their range instead of 40%
- 2026-08-09: The ally-mex upgrade also CLOGGED the mex_up slots — fixed in C++
- 2026-08-09: A crash in AiTaskRemoved — a dangling task handle, not the mex work
- 2026-08-09: Constructors walked into an ally's base to upgrade a mex that was not ours
- 2026-08-09: A mobile radar travels with the army
- 2026-08-09: A defensive posture buys artillery and fodder, not Bulls
- 2026-08-09: Jammers are placed deliberately instead of by chain accident
- 2026-08-09: Pinpointers are capped at three for the whole TEAM
- 2026-08-09: mex defence scales with how close the mex is to the enemy
- 2026-08-09: the AngelScript was split up (pure refactor, no behaviour change)
- 2026-08-09: found while refactoring, NOT fixed
- 2026-08-09: we never attacked, and the group size was the reason
- 2026-08-09: solar was chosen over wind on essentially every map
- 2026-08-09: the T2 rush is a TEAM strategy running in 1v1
- 2026-08-09: every 24-game arm, and what actually survived
- 2026-08-09 (SETTLED): trade caution is HARMFUL at proper sample size
- 2026-08-09: constructors walk the whole map for trees
- 2026-08-09 (CORRECTION): the army-trade metric has a 30% noise floor at n=8
- 2026-08-09: adaptive caution improves the army trade 47%; a blanket bar makes it worse
- 2026-08-09 (CORRECTED): the 25% close-range deficit was contamination
- 2026-08-09 (WITHDRAWN, see above): we lose close-range fights by 25%

Full detail: `changes/2026-08-09.md`

### 2026-08-08

- 2026-08-08: the bank is empty, not full — the fraction-of-storage gates are dead
- 2026-08-08: the gantry cap WAS the T3 constraint
- 2026-08-08: measured -- the six changes are a net win
- 2026-08-08: the constraint is build power, not space
- 2026-08-08: one base layout, replacing position-plus-shake

Full detail: `changes/2026-08-08.md`

### 2026-08-07

- 2026-08-07: naval response was switched off entirely
- 2026-08-07: front vs back, and the front starts UNKNOWN
- 2026-08-07: the front is our own perimeter, not a seam
- 2026-08-07: the front line is not at the chokepoints
- 2026-08-07: BWEM chokepoints exist, and were unreachable
- 2026-08-07: constructors no longer pre-empt themselves into reclaim
- 2026-08-07: RESULTS BELOW WERE VOID -- read this first
- 2026-08-07: the aggression session (RESULTS VOID, SEE ABOVE)
- The metal-full fallback was buying Pit Bulls — 2026-08-07
- Commander idling at a haven patrolled back and forth forever

Full detail: `changes/2026-08-07.md`

### 2026-08-02

- How the AI judges a fight — four defects found 2026-08-02
- Defence towers were always the cheapest one — FIXED, unmeasured
- Rez bots died to all-or-nothing resurrects — FIXED, unmeasured
- Metal converters may be eating the expansion gap — NOT ACTED ON

Full detail: `changes/2026-08-02.md`

### 2026-08-03

- Gating CDefendTask promotion — TRIED, REVERTED 2026-08-03
- Squad join radius 1000 -> 3000 — squad size FIXED, win effect UNPROVEN
- Naval players built no energy at all — 2026-08-03
- Range: no tower we build can answer enemy artillery
- The army loses; the towers do not carry us — measured 2026-08-03
- ENGAGE_MARGIN works at 25 minutes and not at 40
- Reclaim cannot see the bodies

Full detail: `changes/2026-08-03.md`

### 2026-08-06

- Three fixes from one live session — 2026-08-06
- Three more, same session, from watching two windowed games back to back
- The tech-lead election was a one-way trip past 15 minutes

Full detail: `changes/2026-08-06.md`


### 2026-08-21

Tunables audit (git-history-verified per item), all compile-gated clean:

- `factory/buildpower.as` REMOVED — factory build-power requests, apexearth's
  own 2026-08-19 idea, but measured hurting (K/D 0.86 -> 0.48 paired seed),
  default-off since, and its problem statement is now solved by the assist
  path's army-shortfall gate (`apex_assist_army_frac`). Four knobs went with
  it (`fac_demand`, `fac_ask_hold`, `fac_help_mult`, `fac_spare_frac`).
- Jammer gate merged: `apex_jammer_upkeep_margin` deleted;
  `JammersAfforded` no longer grants a free first jammer (`1 + int(...)` ->
  `int(...)`), so the count formula is also the gate. First jammer now needs
  income >= upkeep/share (10x upkeep at the 0.10 default) vs 4x before —
  slightly later on small grids, unchanged at scale.
- `apex_t2_energy_floor` (700) deleted — the pre-T2 energy forecast now
  builds to `apex_t2_energy` (800) itself, so the grid the forecast builds is
  the grid the rush bar demands.
- `apex_reclaim_advsol_e` + `apex_reclaim_wind_e` (both 2000) merged into
  `apex_reclaim_gen_e` — one number in apexearth's own statement
  (">2000 reclaim wind and advanced solar"); wind's map-wind scaling kept.
- Incoming-push DETECTION renamed `apex_push_*` -> `apex_incoming_*`
  (notice_r, cost, closing, danger_pad, danger_cost, answer_frac, stand) —
  the prefix had collided with the team-push family.

KEPT, verified against history (do not re-propose):

- `ArmyPressureMod` is NOT redundant with the budget's `LossArmyMult`/stance
  multipliers: the budget never reaches facqueue army production (targets.as
  2026-08-16 warning), so it is the only adaptive army-count response.
- The three outnumbered predicates (`Outmassed`, `ConservativeStance`,
  `mass_no_commit_ratio`) differ deliberately in ratio, fog policy and
  consumer; fog-flooring `Outmassed` would suppress constructor growth while
  blind, which is the wrong direction for the economy.

### 2026-08-21 (later)

- `apex_rez_per_income` 0.1 -> 0.2 — double the rez fleet, still income-scaled.
- BATTLEFIELD MEDICS (`rules_rezzer.as` RezzerMedic, apexearth request): a
  tunable share of rez bots (`apex_medic_share` 0.4) stays with the army's
  staging anchor — repairs wounded mobiles near it (`apex_medic_r` 1200),
  holds station by area-reclaiming the aftermath there. Flee rule still wins;
  threat at the anchor holds the medic home. Compile-gated clean.
- FORMATION TRAVEL (C++, AttackTask+DefendTask, apexearth: enemy "uses the
  synchronized move speed fight orders... we give spread out move orders"):
  ground squads now travel on CFightAction (CmdFightTo waypoints +
  CmdWantedSpeed at the squad's lowestSpeed) instead of per-unit CMoveAction.
  Previously only SIEGE-attr units (32 defs) fought-travelled. Flyers keep
  MOVE; RaidTask untouched (raiders bypass fights). Wounded pull-back is
  unchanged: RetreatTask swaps the travel act out, which IS dropping the
  fight order; the standoff/kite ring still owns distance in the engagement
  phase. Tunable `apex_fight_travel` (default 1, in dev_tunables.lua) for the
  A/B. NOT yet judged on a watched game.
