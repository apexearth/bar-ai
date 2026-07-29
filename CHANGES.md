# What this AI does that stock BARb does not

Two variants, both built on BARb (CircuitAI). Everything here is a deliberate
difference from `BARb/stable`; anything not listed behaves as stock.

| variant | intent | best measured result |
|---|---|---|
| **apex** | stock BARb plus a team T2 rush | T2 at 5.7 min vs stock 13.9; ~45% wins |
| **apexdef** | hold ground, out-eco, finish with T3 | 4-3 over 10 clean games |

Status column below: **measured** = validated in a clean run; **unmeasured** =
implemented and smoke-tested only; **suspect** = measured under conditions later
found invalid.

---

## C++ / SkirmishAI.dll

New bindings in `vendor/engine/AI/Skirmish/BARb/src/circuit/`. The DLL is rebuilt
from source and stripped; see `docs/06-building-the-dll.md`.

| binding | purpose | status |
|---|---|---|
| `ai.SendResources(m, e, team)` | give metal to an ally — makes slinging possible at all | measured |
| `ai.GetTeamMetalIncome(team)` | ally income, for ranking the tech lead | measured |
| `ai.GetBestWreckPos(pos, r, min)` | richest wreck nearby, so reclaim is *valued* | measured |
| `ai.GetBuilderThreatAt(pos)` | per-position danger from the engine's `CThreatMap` | diagnostic only |
| `CCircuitUnit::CmdMoveTo(pos)` | raw move order, outside the task system | **not called** |
| `ai.GetEnemyCostAt(pos, r)` | enemy count in radius | **not called — unsafe** |

`ai.GetTeamMetalFill` also exists but returns nothing useful; see the engine bug
note in `CLAUDE.md`.

**Do not call** the last two. `GetEnemyCostAt` crashed the AI, and commander
retreat via `CmdMoveTo` correlated with the engine aborting 14-17 games per
20-game run. Both are registered but unreferenced.

## AngelScript (`script/hard_aggressive/`)

### Team tech coordination — the core of both variants
- **One designated tech lead**, chosen as the **richest ally by smoothed metal
  income**, latched at 5 min (or immediately once anyone clears 15 m/s).
  Stock has no team coordination at all — each instance decides alone.
- **Slinging**: followers send 450-metal lumps to the lead, keeping 220, from
  5 min until they receive their own advanced constructor.
- **The lead techs on zero bank**: stock requires `0.5 x plant cost` banked,
  which is never reachable. It places the plant and pours income in.
- **Followers get the same no-bank switch** once past 13 min — and **only one
  advanced plant each**.
- **Advanced plant matches the opening factory**: T1 bot lab → T2 bot lab,
  vehicle → vehicle. Stock forced a vehicle plant a bot lab cannot build.
- **The lead reclaims its own T1 lab** into the plant it replaces.
- **Advanced constructors are shared**, one per teammate. Big teams pre-empt the
  factory line to do it; small teams do not (measured: pre-empting cost 3-13).
- **The tech lead never opens air**, and on teams under 6 **nobody** does.

### Combat posture
- **Mass before attacking**: attack quota grows 30 at 8 min → +3.5/min → cap 80.
  Stock attacks with whatever is to hand.
- **Refuse bad trades**: hold when enemy threat exceeds 0.95x our army cost.
  Calibrated from live ratios, not invented.
- **Reactive turtling**: hold when our army value drops 18% in 20 s, resume at
  85% of the pre-collapse peak, max 6 min, not before 5 min (apexdef).

### Economy
- **Reclaim over resurrect**: rez bots are handed a wreck reclaim before
  `DefaultMakeTask` can give them a resurrect. Resurrecting spends metal;
  reclaiming yields it.
- **Valued corpse reclaim**: idle builders go to the *richest* nearby wreck, not
  the closest. apexdef reaches further (2200) and accepts smaller bodies (55).
- **Reclaim when broke**: a builder standing on metal with an empty bank eats it
  rather than holding an unaffordable build task.
- **T3 gantry** is an explicit tech goal above 100 metal/s (apexdef).

## Config (`config/hard_aggressive/`)

| change | why | status |
|---|---|---|
| `mex_up` 3 → 10 | T2 mexes are 4x metal; upgrade them all | measured |
| Metal storage `since` 300 → 1200 | at 5 min there is nothing to store | unmeasured |
| Fusion gated `m_inc > 28` | ~1000 e/s of economy, per human practice | suspect |
| Advanced fusion added to the fusion hub | it existed only as a hub *key*, so nothing ever built one | unmeasured |
| Nano gates on reachable income (14/22) | old gates of 22-46 produced **zero** nanos | measured |
| T1.5 towers at every advanced plant | plants had four nanos, a fusion, and no defence | unmeasured |
| Jammer towers rehung + `sensor: 900` | parent was porcupine index 12, never built, so `chance` never rolled | unmeasured |
| Commanders get `dg_cost` | stop D-gunning our own lab to kill one raider | unmeasured |
| Spam kept at high tiers (all factions) | cheap units for vision and distraction vs long-range T2 | unmeasured |
| Radar + mobile jammer paired | `coreter` beside `corvrad` (Cortex only so far) | unmeasured |
| Gantry `income_tier` 100/200 → 45/90 | unreachable, so a built gantry sat in its last tier | unmeasured |

Upstream bugs found and worked around: `legbombard` has no builder, `armfmd` is
not a unit def, three `nanotct2` variants are buildable by nobody, several
porcupine entries ship `on: false` and are built inert.

## Dev instrumentation (not part of the AI)

`game-patches/gadgets/` — installed into `BAR.sdd`, inert in normal play.
- `dev_stats_export.lua` — value-weighted telemetry: real vs chaff kills, T2
  placement *and* completion, T2 mex count, reclaim, **commander losses**.
- `dev_team_income.lua` — publishes smoothed per-team metal income as a game
  rules param, because the engine's own ally-income callback is broken.
- `ai_namer.lua` patch — prefixes AI names with their variant so replays are
  readable.

---

## Known not done

- **Factory placement in safe ground.** The `"support"` attribute is documented
  as "build in base radius, not on front" and is already set on every factory —
  but there is no `IsAttrSupport` in the source, so it is unclear anything reads
  it. Unsolved.
- **Commander retreat.** Three approaches tried, none worked. `commander.json`
  hide levers moved losses not at all and cost 10-20k metal; `GetEnemyCostAt`
  crashed and returned zeros; `GetBuilderThreatAt` works but **does not predict
  death** — across 10 games, readings within 30 s of a commander dying were
  *lower* than baseline (3% nonzero vs 8%). Commander survival is still the
  strongest outcome correlate measured here, so it is worth pursuing, but not
  through a sampled position-threat signal.
- **Sling guard when under attack.** Followers give away metal with no check on
  their own safety.
- **Nuke bomber massing, progressive scout quotas, all-in timing scaled to T3.**
- **Armada and Legion radar/jammer pairing.**

## Reading results

Check `exit_code` and `reason` in `result.json`, not just the winner. A run where
games end without a winner may be aborting rather than drawing — that mistake
invalidated several days of conclusions here. Clean games are `exit 0` with
`reason=gameover` or `reason=timelimit`.
