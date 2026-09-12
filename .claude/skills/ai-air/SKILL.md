---
name: ai-air
description: Everything airborne — the air line, wings, T2 air constructors, anti-air (static and mobile), and the air-threat response
---

# Air (`manager/air/` shim `air.as`, plus AA in military/builder)

## The part files

The shim's order is load-bearing (globals must be declared before the line that
reads them; functions are visible module-wide regardless).

| Part | Holds |
|---|---|
| `air/state.as` | every global and every constant, the strike-outcome ledger (`ObsSurv`/`ObsDmg`), `StrikeWorth`, `ScaledBombers` |
| `air/election.as` | resolving the faction's air defs, electing the air lead |
| `air/wing.as` | `Bombers()`/`Fighters()`/`Massed()`, `Armed()`, `FactoryToBuild`, `IntelPlantToBuild` |
| `air/wave.as` | the roster one strike owns — see below |
| `air/update.as` | `HoldsUnit`, `LookDispatch`/`LookWatch`, `Intercept`, `Release`, `ReArm`, `Update` |
| `air/station.as` | spreading fighters over the fence ledger, spending obsolete T1 fighters |

## Ownership

| Decision | Owner | File |
|---|---|---|
| Air line lifecycle | `Armed()`, air lead election; basic plant → T1 air con → advanced plant chain | `air/election.as`, `air/wing.as` |
| Which plant to build next | `FactoryToBuild` (strike) and `IntelPlantToBuild` (intel/mandatory air) | `air/wing.as` |
| Advanced plant output | **T2 air constructors FIRST**, then the T2 wing. His standing want is "by ~200 metal you should definitely be having one"; the `apex_aca_per_income` knob that encoded it as a rate is GONE, and air-con demand is priced through the market like any other build power — re-derive from `docs/23-the-plan.md` before restoring a per-income rule | facqueue |
| Whether a plane flies at all | `HoldsUnit` | `air/update.as` |
| The look the wing is priced on | `LookGainFor` prices an air scout at what seeing their economy adds to the first bomber's `PrizeGain` (mirror of our assets vs the census, fading after a look over `apex_ghost_stale_min`); `LookDispatch` flies it across `Front::FoeAnchor()`, the enemy army on a miss | `air/state.as`, `air/update.as`, `market/production.as` `:look` |
| Which planes a strike owns | the wave roster | `air/wave.as` |
| Recycling stale T1 air | station recycle (adv standing vs basic count) | `air/station.as` |
| Static AA | `ProposeAirDef` prices a `WK_AIRDEF` want; the census and the heavy-AA ceiling are `HeavyAAWant` -- an income BAR (`apex_flak_floor_income`) plus one more per `apex_flak_per` of income beyond it, maxed against what air we have SEEN. That bar is a threshold `docs/23-the-plan.md` forbids; it is in the code today, see ISSUES.md | `brain/market/protect_want.as`, `military/airthreat.as` |
| AA placement exemption | static AA bypasses the behind-base defence veto (air ignores the front line) | `military/defenceline.as` |
| Mobile AA | excluded from massing (can't hit ground; died "for nothing" in pools); stock AA tasks | `military/hooks.as` |

## How an aircraft is held

`Air::HoldsUnit` is called from `Military::MakeTaskInner`
(`military/hooks.as`). Returning true makes that hook return null, which leaves
the unit in `CIdleTask` — no orders, hovering where it was built. That is the
ONLY hold mechanism available: there is no way to land an aircraft from
AngelScript (`CmdFindPad`/`CmdWait` exist in C++ but only `CmdMoveTo` is bound).

Three states decide it, in this order:

1. `gDefendHome` — the base is contested and their AA is thin. Everything
   flies. **Not** a strike; do not route it through `Release()`.
2. `gStrike` — a wave is out. Only roster members fly; everything else keeps
   holding. New production is for the NEXT wave.
3. otherwise — the lead holds per `Armed()`, everyone else per
   `apex_air_home_wave`.

## The wave roster (`air/wave.as`)

`gWave` is filled at `Release()` with every aircraft then standing, pruned by
`ScanWave()` as they die, and cleared when `ReArm()` ends the run. It exists
because `gStrike` alone opened `HoldsUnit` for every plane, so each one built
mid-run left the pad alone — and, since `ReArm` counted TOTAL bombers, that
trickle held the count above the spent bar and the strike never re-armed.

A run ends when the wave is spent, or when what was built while it was away is
already the bigger force (no clock in either). Survivors are then recalled home
and mass with the pool. `gRunWave` is a separate snapshot so `SettleStrike` can
score the run's own survivors on its own clock.

`HeldBombers()`/`HeldFighters()` are the at-home counts — use these, not
`Bombers()`/`Fighters()`, anywhere that asks "what could we send next".

## Enumerating our own aircraft

`ai.GetOwnUnitsOfDef(def, pos, radius)` — **radius 0 means all of them**,
position ignored. Skips nanoframes. `cpp/src/circuit/CircuitAI.cpp:1987`, bound
at `cpp/src/circuit/script/InitScript.cpp:1142`. It is not in `vendor/circuitai`
— it is one of ours.

`CCircuitUnit` exposes `const Id id` (`InitScript.cpp:725`), which is what makes
per-unit rosters possible at all.

## Known C++ constraint

Air squads cannot group (the C++ constant behind "AI never masses air") —
memory `bar-ai-air-grouping`. Wing behavior works around it, not through it.

## Measuring air changes

The standard benchmark **never commits the assassin**: at benchmark income the
air lead reports `air assassin holding off -- losing the ground war` for the
whole game, and `Release()` is never reached. To exercise the strike path use
self-play (`--a Apex:Unstable --b Apex:Unstable`) with `--handicap`, which keeps
ground parity and lets the commitment gate open.

## Log lines

`apex: air <n>/<want> bombers, <n>/<want> fighters ...` (60s heartbeat) ·
`apex: air lead NOT armed ...` · `apex: air assassin holding off -- ...` ·
`apex: air look <def> #<id> -> x,z structs= mirror= stale= worth=` · `apex: air look landed|lost #<id> structs=<before>-><after> miss= next=` ·
`apex: air assassin committing, first plant <x>` · `apex: air strike -- <why>` ·
`apex: air strike over -- <n> of the wave home, <n> built since` ·
`apex: air run scored def=<x> sent= home= surv= dmg/bomber=` ·
`apex: intercepting for ally t<n>` · `apex: fighters spread -- ...`

## Tunables

`apex_flak_floor_income` (60) ·
`apex_flak_per` (60) · `apex_air_home_wave` · `apex_air_spread` ·
`apex_air_recycle` · `apex_intercept_min_fighters` · `apex_intercept_min` ·
`apex_bomb_defend_aa` · `apex_air_payoff` · `apex_air_aa_soak` ·
air ratios via `factory.json` air_map/no_air blocks
