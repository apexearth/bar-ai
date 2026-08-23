> **Stale since the 2026-08-23 overhaul kill + tunables trim** — 308 dead names were removed from dev_tunables.lua and tunables.as; the live list is those two files, not this doc.

# Runtime tunables — the registry

Constants can be overridden per match without a rebuild and without touching the
AI's shipped defaults. They exist so a threshold can be A/B'd instead of argued
about.

The table below is not the whole set — `dev_tunables.lua`'s `NAMES` is what the
harness can actually set, and a few readers (`apex_unblock_test_wait`) are in
neither. `grep -rhoE 'GetTunable\("[a-z_]+"' ai cpp` is the authority.

    python tools/run_match.py ... --modoption apex_orbit_rate=0
    python tools/run_tournament.py ... --modoption apex_rush_min_metal=22

## How the mechanism works

1. `game-patches/gadgets/dev_tunables.lua` reads any modoption named in its
   `NAMES` table and republishes it as a game rules param of the same name. A
   name that is not in `NAMES` is not republished — the gadget names them
   explicitly because `pairs()` over the modoptions table yields nothing here
   even though direct key access works.
2. The gadget runs at `layer = -1000`, ahead of the AI's first frame, because
   the DLL caches each value on first read.
3. `CCircuitAI::GetTunable(name, fallback)` (`src/circuit/CircuitAI.cpp`) reads
   the param once, caches it in `tunables`, and returns the compiled default
   when the param is absent — which is every game that does not set the
   modoption. Nothing ships to multiplayer.
4. AngelScript reaches the same function as `ai.GetTunable(name, fallback)`.

Two consequences worth knowing: the value is read once, so changing it later in
a game does nothing; and the gadget only exists in `BAR.sdd`, so tunables are a
bench facility, not a live one.

## The registry

Verified 2026-08-09 by reading every call site.

| name | default | read by | what it does |
|---|---|---|---|
| `apex_engage_margin` | 1.35 | C++ `AttackTask.cpp` `TradeScaledMargin` | power ratio needed before a squad commits |
| `apex_trade_margin_max` | 1.00 | C++ `AttackTask.cpp` `TradeScaledMargin` | ceiling on how far a bad trade record raises that margin |
| `apex_continue_margin` | 0.85 | C++ `AttackTask.cpp` `FindTarget` (two sites) | power ratio needed to keep going once engaged |
| `apex_air_threat_mod` | 0 (0 keeps `ATTACK_THREAT_MOD` 2.0) | C++ `AttackTask.cpp` `Update` | what air pays for threat in the path query |
| `apex_static_no_continue` | 0 (off) | C++ `AttackTask.cpp` `FindTarget` | drop the sunk-cost discount under static guns |
| `apex_encircle_penalty` | 0 (off) | C++ `AttackTask.cpp` `FindTarget` | penalty for a target that would encircle us |
| `apex_attack_minpower_threat` | 0 (off, flat `minAttackers`) | C++ `MilitaryManager.cpp` `Enqueue` | scale the attack party size with threat |
| `apex_scout_threat` | 1.0 (`THREAT_MIN`) | C++ `MilitaryManager.cpp` `GetScoutPosition` | how hot a metal cluster may be and still be scoutable |
| `apex_squad_spacing` | 96 | C++ `SquadTask.cpp` `ActivePath` | lateral spacing of a travelling line |
| `apex_range_mod` | 0.95 (`STANDOFF_RANGE_MOD`) | C++ `FighterTask.cpp` + `SquadTask.cpp` `Attack` | standoff as a fraction of the unit's own `GetMaxRange()` |
| `apex_los_standoff` | 1 (on) | C++ `FighterTask.cpp` + `SquadTask.cpp` `Attack` | 0 restores clamping the standoff to the unit's own `losRadius` even when it can see the target |
| `apex_prefer_target` | 1 (on) | C++ `CircuitUnit.cpp` `Attack(pos, ...)` | 0 restores `CMD_ATTACK` + `CMD_FIGHT` behind the standoff move instead of move + set-target |
| `apex_siege_fight` | 0 (off) | C++ the eight fighter `AssignTo` | 1 restores `CFightAction` travel for `siege` defs instead of `CMoveAction` |
| `apex_orbit_rate` | 0.18 | C++ `SquadTask.cpp` `Attack` | rate the standoff ring precesses |
| `apex_reclaim_energy_dist` | 900 | C++ `EconomyManager.cpp` `UpdateReclaimTasks` | how far a constructor may walk for a tree |
| `apex_comm_flee_influence` | 0.01 (on 2026-08-14) | AngelScript `builder/rules_commander.as` | enemy influence at which the commander leaves |
| `apex_rush_min_metal` | 14 (`RUSH_MIN_METAL`) | AngelScript `factory/techlead.as` | income the tech rush waits for |
| `apex_unblock` | 1 (on) | AngelScript `military/unblock.as` | 0 stops reclaiming our own cheap buildings to free a unit walled in by them |
| `apex_front_nano` | 1 (on) | AngelScript `brain.as` `Decide` | 0 stops the Brain proposing a nano turret behind the front line |
| `apex_mix` | 1 (on) | AngelScript `brain/mix.as` `MixTask` | 0 turns the target-composition system off; factories fall back to the old production rules |
| `apex_mix_con_income` | 6 | AngelScript `brain/mix.as` `BuildPowerFirst` | metal income per constructor the mix builds before it looks at the army ratio |
| `apex_mix_counter` | 1 | AngelScript `brain/mix.as` `CounterShares` | multiplier on how far observed enemy composition pulls the target mix; 0 restores the fixed table. Capped by `MIX_COUNTER_MAX` (0.6) |
| `apex_mix_scout` | 1 (on) | AngelScript `brain/mix.as` `MixTask` | 0 removes the scout floor, which is the only way an owned factory line builds a scout at all |
| `apex_mix_scout_per_mex` | 4 | AngelScript `brain/mix.as` `ScoutFloor` | extractors held per standing scout wanted; 0 pins it at one |
| `apex_mexup_per_income` | 25 | C++ `EconomyManager.cpp` `UpdateMexUp` | metal income per concurrent mex upgrade the engine will hold open |
| `apex_mexup_full_bonus` | 4 | C++ `EconomyManager.cpp` `UpdateMexUp` | extra concurrent upgrades allowed while the metal bank is full |
| `apex_mexup_first` | 3 | C++ `EconomyManager.cpp` `UpdateMexUp` | floor on that cap while nothing is upgraded yet — the "priority #1" burst |

The last five are what bound the Brain's mex-upgrade Want (`docs/18-brain.md`):
the script proposes and enqueues, the engine decides how many upgrades may be
open at once.

Anything shipped at 0 is **off by default** and exists only for the A/B that
would justify turning it on.

## Adding one

Three edits, all of them required:

1. read it where it matters — `GetTunable("apex_x", COMPILED_DEFAULT)`;
2. add `"apex_x"` to `NAMES` in `game-patches/gadgets/dev_tunables.lua`, or the
   modoption is silently ignored;
3. add a row here.

The compiled default must stay the shipped behaviour. A tunable is a way to
measure a change, not a way to make one.

## 2026-08-10: nine of these no longer have a reader

The fighter-task C++ delta was reverted to upstream (see CHANGES.md), and with
it went every call site of `apex_engage_margin`, `apex_trade_margin_max`,
`apex_continue_margin`, `apex_air_threat_mod`, `apex_static_no_continue`,
`apex_encircle_penalty`, `apex_squad_spacing`, `apex_range_mod` and
`apex_orbit_rate`. Setting them now does nothing -- **except `apex_range_mod`
and `apex_los_standoff`, whose readers were removed a second time by an
unrelated commit and restored on 2026-08-12 (see CHANGES.md); the rows above
are current.** They are left in
`dev_tunables.lua` and in the table above because the behaviours they measure
are expected to be re-landed one at a time, and each will want its tunable back.

`apex_attack_minpower_threat`, `apex_scout_threat` and `apex_reclaim_energy_dist`
live in MilitaryManager/EconomyManager and are unaffected.

## The raid-the-economy set

Added alongside the raiding work; verified 2026-08-09 by reading every call
site. These were in `dev_tunables.lua` but had no row here.

| name | default | read by | what it does |
|---|---|---|---|
| `apex_attack_threat_mod` | 1.0 (upstream behaviour) | C++ `AttackTask.cpp` `Update` | what an attack party pays for contested ground in the path query. Raising it makes the flank the shortest path, the way `RaidTask`'s `RAID_ROAM_THREAT_MOD = 8` already does for raid parties |
| `apex_eco_target` | 1.0 (on) | C++ `AttackTask.cpp` `FindTarget` | 0 drops the preference for economic targets with little army standing beside them |
| `apex_eco_unseen` | 1.0 (no-op) | C++ `AttackTask.cpp` `FindTarget` | multiplier on the `FREE_ECO_PRIORITY` raid bonus when the target's ground is NOT in current LOS. `localInfl == 0` only means "no army remembered there"; below 1.0 the bonus is discounted for ground we have not actually looked at. `seen=` on the `apex: engage` line reports whether the chosen target was in LOS |
| `apex_mass_vs_army` | 0 (off) | AngelScript `military/massing.as` `MassWant` | 0 pins the massing quota at the floor. Above 0, the quota scales between `MASS_FLOOR` and `MASS_CAP` on the enemy-to-our army ratio |
| `apex_mass_floor` | 30 (`MASS_FLOOR`) | AngelScript `military/massing.as` `MassWant` | smallest attack party, as a **power** sum — not a unit count and not metal |
| `apex_mass_hold_secs` | 120 | AngelScript `military/massing.as` `UpdateMassing` | how long the army may wait for a full mass before committing anyway |
| `apex_ghost_weight` | 1.0 (no-op) | AngelScript `military/territory.as` `EnemyCostOf` | how much a mobile enemy unit still counts for once it has not been seen inside `CEnemyManager`'s freshness window (60 s). `GetEnemyCost` never forgets a unit once registered, so `EnemyArmyCost`/`EnemyFieldCost` accumulate every raider ever sighted; the fresh part comes from the new `GetEnemyCostFresh` binding and the remainder is weighted by this. At 1.0 the sum is arithmetically identical to the raw one. Statics are never discounted. The `apexfoe: raw= fresh= ghost%=` log line reports the fraction at stake |

`MASS_CAP` is 48 and `MASS_FLOOR` 30, both in `military/roles.as`.

| name | default | read by | what it does |
|---|---|---|---|
| `apex_edge_band` | 0.20 (`EDGE_ECO_BAND`) | C++ `AttackTask.cpp` `FindTarget` | how wide the map-edge strip is, as a fraction of the map's shorter side |
| `apex_edge_bonus` | 2.0 (`EDGE_ECO_BONUS`) | C++ `AttackTask.cpp` `FindTarget` | preference multiplier for economic targets inside that strip. apexearth: "the best mex attacks can be done around the edges of the map" |
| `apex_super_guard` | 1 (on) | AngelScript `military/superguard.as` | 0 restores stock routing for mobile supers: one solo `CAttackTask` each, the frame they finish |
| `apex_super_cost` | 7000 (`SUPER_COST`) | AngelScript `military/superguard.as` | cost at which a non-SUPER-role unit is treated as a T3 heavy and held on the defence line. Legion tags no gantry unit "super", which is why cost is a second key |
| `apex_ping_attacks` | 0 (off) | C++ `AttackTask.cpp` `FindTarget` | 1 drops one "ATTACK" map marker per attack party, the first time it picks a target. Dev aid for watching a game; markers are visible clutter otherwise |

## Added 2026-08-10

| name | default | read by | what it does |
|---|---|---|---|
| `apex_kill_quota` | 300 (`KILL_QUOTA`) | AngelScript `military/posture.as` | attack power the killing blow commits at. Was 10, i.e. SMALLER than the ordinary floor of 30 -- winning made the AI disperse. Measured: 44% of engagements became 15+ unit pushes against 6%, and the result did not move |
| `apex_unblock` | 1 (on) | AngelScript `military/unblock.as` | 0 disables the walled-in-unit rule entirely |
| `apex_unblock_still` | 1350 frames (45 s) | AngelScript `military/unblock.as` | how long a unit must be motionless to become a candidate |
| `apex_unblock_period` | 90 frames (3 s) | AngelScript `military/unblock.as` | minimum spacing between probes |
| `apex_unblock_test_wait` | 240 frames (8 s) | AngelScript `military/unblock.as` | how long a unit gets to obey the move order before it counts as penned |
| `apex_mexup_per_income` | 25 | C++ `EconomyManager.cpp` | metal/s per simultaneous mex-upgrade slot |
| `apex_mexup_full_bonus` | 4 | C++ `EconomyManager.cpp` | extra upgrade slots while the metal bank is full |
| `apex_mexup_first` | 3 | C++ `EconomyManager.cpp` | minimum slots while NOTHING is upgraded yet -- "if we don't have any upgraded mexes and we're poor then upgrading a mex is priority #1" |

Measured note on the mexup set: the cap was never the binding constraint. Over
four 8v8 games, counting only builders that can upgrade, mean upgrades in flight
were 1.3 against a cap of 13.9 and 89.6% of spots examined were rejected as "not
ours". The fix that helped was searching our OWN extractors first
(`EconomyManager.cpp`), not raising the ceiling.
