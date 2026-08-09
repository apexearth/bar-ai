# 03 — BARb architecture

How a BARb match assembles itself, and which file you edit to change what.

## Where the behaviour comes from

Three sources, resolved at AI init:

```
SkirmishAI.dll                          the C++ engine of the AI (CircuitAI)
  ├─ engine/<ver>/AI/Skirmish/BARb/<version>/{config,script}/    fallback defaults
  └─ BAR.sdd/luarules/configs/<shortName>/<version>/{config,script}/  what actually loads
```

The game-side path is built in CircuitAI's `util/FileSystem.h`:

```cpp
return std::string("LuaRules" SLASH "Configs" SLASH) + shortName + SLASH + version + SLASH + subdir + SLASH;
```

`shortName` and `version` come straight out of your `AIInfo.lua`. `ScriptManager::Load`
and `SetupManager::LoadConfig` check the game-side path first and fall back to the
DLL-side folder only if the file is missing there — gated on the `game_config` AI
option, which defaults to **true**.

Confirmed in a real infolog from this machine:

```
Skirmish AI <Apex-apex>: 1.6.24
Skirmish AI <Apex-apex>: Load script: LuaRules\Configs\Apex\apex\script\hard_aggressive\init.as
Skirmish AI <Apex-apex>: hard_aggressive AngelScript Rules!
```

So with `game_config` on, effectively 100% of the JSON and AngelScript come from
the game archive. That is the whole reason layers 1 and 2 need no compiler.

## Version vs profile

Three separate dimensions, easy to conflate:

**shortName** — the AI's identity, and the only one that survives the lobby.
`ADDBOT` carries a single `aiLib` field with no version, so in a hosted game the
start script's `Version` is empty and the engine resolves the shortName to its
highest version by `VersionCompare` — `stable` beats `apex`. A variant shipped as
a *version* of `BARb` therefore plays as stock BARb in multiplayer, silently.
Ours is `Apex`. (It was `BARbApex` until 2026-08. Nothing validates a shortName
— the harness writes it straight into the start script — so an out-of-date
command yields `FetchSkirmishAILibrary: unknown skirmish AI` and a side that
scores zero on every metric, which reads exactly like a catastrophic
regression.)

The variants in this repo, each a distinct shortName for that reason:

| repo dir | shortName | version | what it is |
|---|---|---|---|
| `ai/apex` | `Apex` | `apex` | the AI under development |
| `ai/ctl` | `ApexCtl` | `ctl` | frozen control, for self-play A/B |
| `ai/stk` | `ApexStk` | `stk` | stock config + stock script on the apex DLL, to isolate DLL effects |

**AI version** — a variant within one shortName. Needs both halves:

```
engine/<ver>/AI/Skirmish/Apex/apex/     AIInfo.lua (version='apex') + SkirmishAI.dll + config/ + script/
BAR.sdd/luarules/configs/Apex/apex/     config/ + script/   (local iteration only)
```

The engine-side `config/`+`script/` are what a hosted game actually loads: other
players are on released BAR, which has no `luarules/configs/` for us, so
CircuitAI logs "Game-side config: missing!" and falls back to the AI data dir.

**Profile** — a difficulty/playstyle *inside* one version, selected by the
`profile` AI option that version's `AIOptions.lua` declares:

```
config/hard_aggressive/*.json
script/hard_aggressive/{init,main}.as
script/hard_aggressive/manager/{air,assist,baseplan,builder,crew,economy,
                                factory,frontline,military}.as
script/hard_aggressive/misc/commander.as
```

Stock ships `easy`, `medium`, `hard`, `hard_aggressive` game-side, plus `dev`
engine-side. **`apex` ships exactly one, `hard_aggressive`** — the other trees
were deleted because they carried none of this AI's work. Chobby overrides the
visible list via `aiCustomData.lua` — which only knows about `BARb stable`. **A
custom version is not in Chobby's config, so you must declare your own profiles
in your own `AIOptions.lua`** or the dropdown will show only whatever the
engine-side file lists.

Each `manager/<name>.as` is now a **shim** — an ordered `#include` list of the
real code in the sibling `manager/<name>/` directory (69 `.as` files in all).
The order is load-bearing; see the CLAUDE.md section "How the AngelScript is
laid out" before moving anything. Both `AiMakeTask`s are rule pipelines:
`builder/maketask.as` and `factory/maketask.as` are short ordered lists of
named rules living in the sibling `rules_*.as`.

## Config layering

For each config part, `SetupManager::ReadConfig` tries the profile folder first,
then the version root:

```
config/<profile>/factory.json   →   config/factory.json
```

So a profile *can* contain only the files it changes. **`apex` does not use this
fallback**: the seven top-level `config/*.json` files were deleted as
unreachable, and every config it loads sits in `config/hard_aggressive/`. The
fallback is described here because stock relies on it, not because we do.

Faction
variants are separate files rather than another directory level: `*_leg.json`
for Legion, plus `behaviour_extra_units.json` and `behaviour_scav_units.json`.
Which of these load is logged at init (`Ignoring Legion`, `Ignoring Scav Units`,
`Ignoring Extra Units`).

## AIOptions.lua

Declared engine-side, shown in the lobby, delivered to the AI in the start
script's `[AI0][OPTIONS]` block.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `profile` | list | `hard` | which config/script subfolder to use |
| `game_config` | bool | `true` | load config from the game archive |
| `cheating` | bool | `false` | global sight |
| `comm_merge` | bool | `false` | merge nearby allied BARb commanders |
| `ally_base` | bool | `true` | avoid building inside allied bases |
| `disabledunits` | string | `''` | `armwar+armpw+raveparty` |

The commented-out `random_seed` and `json` (per-AI JSON override) entries are
present in the file if you want them.

## Making a new variant

What `tools/deploy_ai.py deploy` automates:

1. Copy the engine's `AI/Skirmish/BARb/stable/` → `AI/Skirmish/<shortName>/<name>/`,
   the shortName coming from the variant's own `AIInfo.lua` (`Apex`, not `BARb`).
   This is what supplies the correct `SkirmishAI.dll` for the installed engine.
2. Overwrite `AIInfo.lua` with `version = '<name>'` (must match the folder) and a
   distinct `name` for the lobby.
3. Overwrite `AIOptions.lua` with your profile list.
4. Copy your `config/` and `script/` to
   `BAR.sdd/luarules/configs/<shortName>/<name>/`.
5. Restart the client — the AI list is built at startup.

Verify without launching the game:

```bash
"…/engine/recoil_2026.06.12/spring-headless.exe" --list-skirmish-ais
# BARb   apex     C   0.1
# BARb   stable   C   0.1
```

or `python tools/unitsync.py ais`, which also shows the display names.

Step 1 is why this survives engine updates: the DLL is re-derived from whatever
engine is installed rather than carried along from an old one.

CircuitAI's own guide to profiles is
[`doc/Profile.md`](https://github.com/rlcevg/CircuitAI/blob/barbarian/doc/Profile.md)
— the only real prose documentation the project has.

## CircuitAI internals (for when you go to C++)

```
src/AIExport.cpp                DLL entry points
src/circuit/CircuitAI.*         root object
src/circuit/module/             EconomyManager, MilitaryManager, FactoryManager, BuilderManager
src/circuit/task/               UnitTask, IdleTask, RetreatTask, ...
    task/builder/               MexTask, EnergyTask, FactoryTask, DefenceTask, CombatTask, BuildChain, ...
src/circuit/map/                ThreatMap, InfluenceMap, GridAnalyzer
src/circuit/resource/           MetalManager, EnergyGrid, EnergyLink, ...
src/circuit/setup/              SetupManager (reads the JSON), DefenceData
src/circuit/script/             AngelScript bindings  <- see doc 05
src/circuit/terrain/ unit/ util/
src/circuit/util/math/          ConvexHull, KMeansCluster, HierarchCluster, QuadField, ...
```

There is essentially no prose documentation; `doc/` holds only `Profile.md` and
the README is self-marked *"requires info update"*. Expect to read source.
