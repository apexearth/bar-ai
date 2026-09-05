# 01 — Local environment

Surveyed 2026-07-27; engine version re-checked 2026-08-09. Re-check before
trusting: engine versions rotate, and the
launcher replaces the engine directory on update.

## Install

**Never hardcode any path below.** `tools/bar_env.py` resolves all of them at
runtime — import it. `python tools/bar_env.py` prints what it resolved. Override
with the `BAR_ROOT`, `BAR_DATA`, `BAR_ENGINE` and `BAR_GAME_SDD` environment
variables.

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

Active engine is **`recoil_2026.07.04`** (verified 2026-08-09), resolved as
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

**The game itself does not play it.** Chobby plays the rapid-downloaded `.sdp`
packages in `data/packages`/`data/pool`; `BAR.sdd` is an extra entry the engine
picks up by scanning `data/games/`, used only by this harness. It is the only
place the dev gadgets can live, and those gadgets produce all telemetry — which
is why it sat eight months stale without anyone noticing.

Its `modinfo.lua` has `version = '$VERSION'`, uninterpolated. Two consequences:

- The game's name is literally `Beyond All Reason $VERSION` — that exact string
  goes in a start script's `GameType`.
- `luarules/gadgets.lua` greps `Game.gameVersion` for `$VERSION` and sets
  `isDevMode`, which unlocks BAR's debug gadgets and widgets. Running from the
  checkout *is* what turns dev mode on.

Branch `apex`, pinned to an `origin/master` ref last fetched **2025-11-28**.
`vendor/bar` tracks upstream `master` and is a different, newer vintage — never
answer a unit question from one tree. `tools/unitdef.py` reads both and says
which it found the answer in.

## Toolchain

Present: `git` 2.34, Python 3.13.2, Node 22.14, .NET 10, Docker Desktop
(installed, daemon stopped), WSL (installed, **no distro**), 157 GB free.

Absent: cmake, gcc/g++, MinGW, MSVC, ninja, 7z.

No native toolchain is needed: the DLL is built in the official Docker
container — see [06 — Building the DLL](06-building-the-dll.md), which is
verified working on this machine. Config and AngelScript work needs nothing at
all.
