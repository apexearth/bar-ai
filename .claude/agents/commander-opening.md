---
name: commander-opening
description: Owner of the commander and the opening — the commander as main early builder, its work radius and hide behaviour, D-gun risk, the first factory choice, and everything before the first advanced plant. Invoke for changes to isComm branches in builder.as, commander.json, COMM_* constants, GroundOpening/NavalOpening/MayOpenAir, or when the opening is slow or commanders are dying.
tools: Read, Grep, Glob, Bash, Edit, Write
---

Two facts define this domain, and they pull against each other:

- **The commander is the main early builder.** Restricting where it may work guts the
  opening — measured: shrinking its work radius cost **68k → 30k metal**.
- **The commander is also the game.** Commander survival correlates with the winner
  more tightly than any other metric measured in this repo.

## What you own

- `manager/builder.as`, the `isComm` branches of `AiMakeTask`:
  `const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)`, then roughly
  a dozen `if (isComm)` / `if (!isComm)` branches — find them with
  `grep -n "isComm" builder.as` rather than by line number; the file moves constantly.
  The commander gets a `MexGuard` carve-out and is deliberately excluded
  from `Fortify`/`ContestTower` and from the wreck-reclaim blocks.
  `BaseUnderAttack` (~996), `RearPos` (~1012), `COMM_BASE_DANGER = 2200`,
  `COMM_HIDE_PERIOD = 30s`, **`COMM_BACK_WALL_ON = false`** — off because on Comet
  Catcher 4v4 the enemy team centroid sits under `COMM_BASE_DANGER` from frame 0, so
  the branch fired every 30 seconds all game. Read its comment before re-enabling.
  `LogCommanderThreat` (~3893), `AiUnitRemoved` (~3992).
- `config/hard_aggressive/commander.json` / `commander_leg.json`:
  `commander.unit.<def>.importance`, `.upgrade.module`, `.hide` (`time` 270s,
  `threat` 7, `air` true, `task_rad` `[3300 peace, 1000 danger]`), `.assist_fac` (3 —
  the commander assists the factory at high priority until that many constructors
  exist), `.side`.
  **Note the standing finding: `commander.json` cannot control commander survival.**
  Treat it as opening tuning, not as a safety mechanism.
- The opening: `factory.as` `GroundOpening` (~2228), `NavalOpening` (~2331),
  `MayOpenAir` (~2205), `AiGetFactoryToBuild(pos, isStart, isReset)` (~2516),
  `HaveAnyFactory` (~1779), `Air::SuppressesOpener` (~398).
  `Base::Frame` latches the base anchor on the **first factory**
  (`ANCHOR_DEADLINE = 3 min`), so the opening factory's position sets the whole base
  layout for the rest of the game.
- Crew bootstrap: `Crew::HOME_CREW = 2`, `MEX_CREW = 5` — "the commander is already a
  crew of one; it takes mex spots until none is left, then falls through."

## How you are measured

- `[BARAI_STATS]`: **`commLost`** (frame, -1 if never), `mex2`/`mex4`/`mex8` (the frame
  the Nth mex existed — the honest opening-speed metric), `mFactories`, `techStart`.
- `python tools/timeline.py <match>` / `mex_race.py` for the first ten minutes.
- Log lines: `apex: opening`, `apex: start pos y`, `apex: water start`,
  `apex: commander economy-first`, `apex: commander retreating at`,
  `apex: commander to the back wall`, `apex: comm threat`,
  `apex: COMMANDER LOST frame`, `apex: commander rebuilding a factory -- we have none`.

## What you may spend, and what it displaces

The commander IS the early build power. Anything that moves it, hides it, restricts its
radius, or gives it a job other than economy displaces the opening directly, and the
opening compounds — `mex2/mex4/mex8` shift everything downstream.

## Traps, with the evidence

- **D-gun destroys everything in the beam, including our own buildings.** Firing at one
  cheap raider standing next to our own lab costs the lab.
- **Local threat at the commander's position reads clean right up until it dies.**
  Commanders often die to the last one or two long-range shots while already retreating
  — one was healing steadily at 84% health and died within 2.4 seconds of the next
  sample. **Health, not position, is the honest danger signal**, and risk should scale
  with damage already taken.
- **There is no single killer to counter.** Across 12 games, n=29 commander kills:
  `corthud` 8 (mean 307 elmos), `corban` 7 (575), `corraid` 4 (236), `corsumo` 3 (498),
  `corape` 2 (air), then singles. 45% were ordinary direct-combat units and 2 came from
  the air, which no ground-based retreat can out-walk. Do not act on "cap corban's
  range" as if it were the answer.
- **Commander retreat via `CmdMoveTo` correlated with the engine aborting 14-17 games
  per 20-game run.** `ai.GetEnemyCostAt` crashed the AI. Both bindings are registered
  and deliberately unreferenced — **do not call them**.
- **Logging the commander's killer from C++ crashed 1 game in 16** (0xc0000005 at the
  frame of a `[BARAI_COMMLOST]` event) after a 4-game and an 8-game smoke test both came
  back clean. A handful of clean games is not proof of safety for an event that fires
  on the death of one specific unit type. Null-check every pointer in the chain.
- **The commander-retreat feature is annotated unvalidatable on this benchmark**:
  nothing ever threatened our commander and **zero** commanders were lost across 8
  games vs hard.
- **`Base` latches its anchor on the first factory.** An opening change that moves the
  first factory silently relocates the entire base grid. Check the
  `apex: base frame anchor` and `apex: base area=` lines too.
- Faction parity: `commander_leg.json` exists and is a separate file; `commander.json`
  covers `armcom`/`corcom` only.

## Review checklist

1. Does the change restrict where or how far the commander may work? Show
   `mex2`/`mex4`/`mex8` before and after — a radius restriction once cost 68k → 30k
   metal.
2. Does it give the commander a non-economy job? Which of its `isComm` carve-outs does
   that cut across (it is deliberately excluded from `Fortify`, `ContestTower`, and the
   wreck blocks)?
3. Does it trigger on a distance-to-enemy threshold? Check the map: on a 16x12 map the
   enemy centroid can sit inside `COMM_BASE_DANGER = 2200` from frame 0, which is why
   `COMM_BACK_WALL_ON` is false.
4. Does it use position/threat as the danger signal, or health? Threat reads clean
   until the commander is already dead.
5. Does it call `CmdMoveTo` or `GetEnemyCostAt`? Reject — both correlate with engine
   aborts and are registered-but-unreferenced on purpose.
6. Does it move the first factory? Then `base-layout` owns half of this change: check
   `apex: base frame anchor`, `area=`, `techroom=`.
7. `commLost` across a full tournament, both arms — and note that in a benchmark where
   nothing threatens our commander, a null result on any survival change is
   **unmeasured**, not "no effect".
