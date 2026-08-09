# Runtime tunables — the registry

Twenty-one constants can be overridden per match without a rebuild and without
touching the AI's shipped defaults. They exist so a threshold can be A/B'd
instead of argued about.

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
| `apex_range_mod` | 0.95 (`ATTACK_RANGE_MOD`) | C++ `SquadTask.cpp` `Attack` | standoff as a fraction of weapon range |
| `apex_orbit_rate` | 0.18 | C++ `SquadTask.cpp` `Attack` | rate the standoff ring precesses |
| `apex_reclaim_energy_dist` | 900 | C++ `EconomyManager.cpp` `UpdateReclaimTasks` | how far a constructor may walk for a tree |
| `apex_wind_per_metal` | 1.0 | AngelScript `builder/mexguard.as` | 0 restores picking wind-vs-solar on raw output |
| `apex_comm_flee_influence` | 0 (off) | AngelScript `builder/rules_commander.as` | enemy influence at which the commander leaves |
| `apex_rush_min_metal` | 14 (`RUSH_MIN_METAL`) | AngelScript `factory/techlead.as` | income the tech rush waits for |

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
`apex_orbit_rate`. Setting them now does nothing. They are left in
`dev_tunables.lua` and in the table above because the behaviours they measure
are expected to be re-landed one at a time, and each will want its tunable back.

`apex_attack_minpower_threat`, `apex_scout_threat` and `apex_reclaim_energy_dist`
live in MilitaryManager/EconomyManager and are unaffected.

## Added 2026-08-10

| name | default | read by | what it does |
|---|---|---|---|
| `apex_solo_stock` | 1 (on) | AngelScript `script/world.as` `ApexActive()` | 0 makes apex run its own game-side rules even with no allies, i.e. the pre-2026-08-10 behaviour |

## The raid-the-economy set

Added alongside the raiding work; verified 2026-08-09 by reading every call
site. These were in `dev_tunables.lua` but had no row here.

| name | default | read by | what it does |
|---|---|---|---|
| `apex_attack_threat_mod` | 1.0 (upstream behaviour) | C++ `AttackTask.cpp` `Update` | what an attack party pays for contested ground in the path query. Raising it makes the flank the shortest path, the way `RaidTask`'s `RAID_ROAM_THREAT_MOD = 8` already does for raid parties |
| `apex_eco_target` | 1.0 (on) | C++ `AttackTask.cpp` `FindTarget` | 0 drops the preference for economic targets with little army standing beside them |
| `apex_mass_vs_army` | 0 (off) | AngelScript `military/massing.as` `MassWant` | 0 pins the massing quota at the floor. Above 0, the quota scales between `MASS_FLOOR` and `MASS_CAP` on the enemy-to-our army ratio |
| `apex_mass_floor` | 30 (`MASS_FLOOR`) | AngelScript `military/massing.as` `MassWant` | smallest attack party, as a **power** sum — not a unit count and not metal |
| `apex_mass_hold_secs` | 120 | AngelScript `military/massing.as` `UpdateMassing` | how long the army may wait for a full mass before committing anyway |

`MASS_CAP` is 48 and `MASS_FLOOR` 30, both in `military/roles.as`.

| name | default | read by | what it does |
|---|---|---|---|
| `apex_edge_band` | 0.20 (`EDGE_ECO_BAND`) | C++ `AttackTask.cpp` `FindTarget` | how wide the map-edge strip is, as a fraction of the map's shorter side |
| `apex_edge_bonus` | 2.0 (`EDGE_ECO_BONUS`) | C++ `AttackTask.cpp` `FindTarget` | preference multiplier for economic targets inside that strip. apexearth: "the best mex attacks can be done around the edges of the map" |
| `apex_ping_attacks` | 0 (off) | C++ `AttackTask.cpp` `FindTarget` | 1 drops one "ATTACK" map marker per attack party, the first time it picks a target. Dev aid for watching a game; markers are visible clutter otherwise |
