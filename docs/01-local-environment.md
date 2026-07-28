# 01 — Local environment

Surveyed 2026-07-27. Re-check before trusting: engine versions rotate, and the
launcher replaces the engine directory on update.

## Install

The launcher is an Electron app; the game data sits in a `data` subfolder that
serves as Spring's **write dir**.

```
C:\Users\apexe\AppData\Local\Programs\Beyond-All-Reason\
├── Beyond-All-Reason.exe        launcher (Chobby wrapper)
├── bin\pr-downloader.exe
├── devmode.txt                  enables the launcher's "Dev" singleplayer entry
└── data\                        <- Spring write dir
    ├── engine\<version>\        15 versions installed
    ├── games\BAR.sdd            git checkout of the BAR repo
    ├── maps\                    252 maps, 23 GB
    ├── pool\ packages\ rapid\   rapid content store
    ├── demos\                   replays, 5.2 GB
    ├── infolog.txt              last run's engine log
    ├── springsettings.cfg
    ├── config.json              launcher manifest (setups -> engine version)
    ├── launcher_cfg.json        {"config": "manual-win"} -> which setup is active
    └── _script.txt              last start script the launcher generated
```

There is no `Documents\My Games\Spring`; the install folder is the data dir.

## Engines

`data\engine\` holds 15 versions. Naming went
`105.1.1-2590-gb9462a0 bar` → `rel2501.2025.01.x` → `recoil_YYYY.MM.PATCH`.
The third field is a patch counter, **not** a day — `recoil_2026.06.12` was
released 2026-07-14.

Active engine is **`recoil_2026.06.12`**, resolved as
`launcher_cfg.json` (`manual-win`) → `config.json` → `setups[].launch.engine`.
`tools/bar_env.py` does that lookup for you.

Every engine dir ships `spring.exe`, `spring-headless.exe`, `spring-dedicated.exe`,
`pr-downloader.exe`, `unitsync.dll`, and:

```
AI\Interfaces\C\0.1\{AIInterface.dll, InterfaceInfo.lua}   <- the only AI interface
AI\Skirmish\BARb\stable\      AIInfo.lua AIOptions.lua config\ script\ SkirmishAI.dll
AI\Skirmish\CircuitAI\stable\ (same shape; the Zero-K-tuned build)
AI\Skirmish\NullAI\0.1\
```

No AI SDK headers are shipped — building a DLL requires the engine source.

## Game: a live git checkout

`data\games\BAR.sdd` is a clone of `beyond-all-reason/Beyond-All-Reason`.
A `.sdd` is just a directory the engine reads unpacked, so Lua and AI configs can
be edited in place and reloaded.

Its `modinfo.lua` has `version = '$VERSION'`, uninterpolated. Two consequences:

- The game's name is literally `Beyond All Reason $VERSION` — that exact string
  goes in a start script's `GameType`.
- `luarules/gadgets.lua` greps `Game.gameVersion` for `$VERSION` and sets
  `isDevMode`, which unlocks BAR's debug gadgets and widgets. Running from the
  checkout *is* what turns dev mode on.

State when surveyed: branch `apex`, 2 commits ahead of a `origin/master` ref last
fetched 2025-11-28.

## Prior work found on this machine

Two attempts at a custom AI, both since broken by engine updates.

**1. `ApexAI` (April 2025) — a standalone AI.**
`engine\recoil_2025.04.01\AI\Skirmish\ApexAI\stable\` — a whole copy of BARb with
`shortName = 'ApexAI'`, its own DLL, config and script. Superseded.

**2. `BARb/apex` (November 2025) — a version fork. This is the good one.**

- Engine side: `engine\recoil_2025.06.11\AI\Skirmish\BARb\apex\` — identical to
  `BARb/stable` (the DLL is byte-for-byte the same) except `AIInfo.lua` declares
  `version = 'apex'`, `name = 'BARbarIAn Apex'`, and `AIOptions.lua` defaults to
  the `hard_aggressive` profile and un-comments the profile list.
- Game side: `BAR.sdd\luarules\configs\BARb\apex\` — a full copy of the `stable`
  config tree with `hard_aggressive` tuned. Committed as *"default apex copy from
  barb stable"* then *"changeset 1"*.
- Plus a patch to `luarules/gadgets/ai_namer.lua` adding a `getAIPrefix()` that
  tags AI teams `[APEX]` / `[BARb]` / `[Raptor]` / `[Scav]` using
  `Spring.GetAIInfo`.
- Uncommitted at survey time: `hard_aggressive/factory.json`, adding
  `income_tier` bands (`[1,30,60,80]` → `[1,30,60,80,120,180]`) with new
  per-tier unit weight rows biased toward late-game combat units.

Only three files differ from stable, all under `hard_aggressive`:
`behaviour.json`, `build_chain.json`, `factory.json`.

**Why it stopped working.** The engine-side half only ever existed in
`recoil_2025.06.11`. Engine updates install a fresh directory, so from
`recoil_2025.06.12` onward there was no `BARb/apex` and the variant vanished from
the lobby — while the game-side configs sat there looking fine.

`tools/deploy_ai.py` exists to fix exactly this: it regenerates the engine-side
half from whatever engine is current, every time.

## Toolchain

Present: `git` 2.34, Python 3.13.2, Node 22.14, .NET 10, Docker Desktop
(installed, daemon stopped), WSL (installed, **no distro**), 157 GB free.

Absent: cmake, gcc/g++, MinGW, MSVC, ninja, 7z.

Native AI compilation therefore needs setup — see
[06 — Building the DLL](06-building-the-dll.md). Config and AngelScript work
needs nothing.
