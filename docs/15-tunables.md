# Runtime tunables — the registry

Fifteen constants can be overridden per match without a rebuild and without
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

## Added 2026-08-10

| name | default | read by | what it does |
|---|---|---|---|
| `apex_solo_stock` | 1 (on) | AngelScript `script/world.as` `ApexActive()` | 0 makes apex run its own game-side rules even with no allies, i.e. the pre-2026-08-10 behaviour |
