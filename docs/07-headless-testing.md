# 07 — Headless testing and debugging

The iteration loop. `tools/run_match.py` wraps all of this; this document exists
so you can debug it or drive the engine by hand.

Measured on this machine (`recoil_2026.06.12`; the active engine is now
`recoil_2026.07.04` -- `python tools/bar_env.py` resolves it. Comet Catcher
Remake 1.8, BARb vs
BARb): **a 27 game-minute match finished in 43.7 s wall — about 37× realtime.**
Cold archive cache adds ~35 s to the first run; the harness keeps a persistent
write dir at `matches/_engine` so you pay that once.

## Running

```powershell
$BAR = "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data"
$ENG = "$BAR\engine\recoil_2026.07.04"

& "$ENG\spring-headless.exe" --write-dir "$BAR" --config headless.cfg match.txt
```

`spring-headless` runs the full simulation with GL/SDL stubbed out and
`-DNO_SOUND`. **Widgets and gadgets still run** — that's your data-extraction and
control surface. `spring-dedicated` is *not* what you want: it relays network
traffic without simulating.

Useful flags (`--help` on the binary is authoritative):

```
--write-dir <dir>      where the engine writes logs, cache, demos
--config <file>        exclusive config file — keeps harness settings out of yours
--isolation            limit the archive scanner to one directory tree
--isolation-dir <dir>
--only-local           no listening sockets; use when running many in parallel
--list-skirmish-ais    verify your AI registered
--list-config-vars     every tunable
--game <name> --map <name>    quick launch without a start script
```

Env vars: `SPRING_DATADIR`, `SPRING_WRITEDIR`, `SPRING_ISOLATED`. The harness
sets `SPRING_DATADIR` to the real data dir so content resolves while writes go
to `matches/_engine`.

## The start script

Canonical reference:
[`RecoilEngine/doc/StartScriptFormat.txt`](https://github.com/beyond-all-reason/RecoilEngine/blob/master/doc/StartScriptFormat.txt).
BAR's own working example is `BAR.sdd/tools/headless_testing/`.

```
[GAME]
{
    MapName=Comet Catcher Remake 1.8;      // display name, not filename
    GameType=Beyond All Reason $VERSION;   // $VERSION is LITERAL for a .sdd checkout
    StartPosType=0;                        // 0 fixed, 1 random, 2 in-game, 3 pre-game
    GameStartDelay=0;
    RecordDemo=0;
    IsHost=1;
    HostIP=127.0.0.1;
    HostPort=0;
    NumPlayers=1;
    NumUsers=1;
    MyPlayerName=BenchHost;
    FixedRNGSeed=1;                        // NOT RandomSeed

    [PLAYER0] { Name=BenchHost; Spectator=1; }

    [AI0]  { Name=apex; ShortName=Apex; Version=Unstable; Team=0; Host=0;
             [OPTIONS] { profile=standard; } }
             // ShortName is OURS, not BARb. A variant shipped as a *version*
             // of BARb loads stock BARb in every hosted game -- see CLAUDE.md,
             // "Three axes". Reproduce that with run_match.py --drop-ai-version.
    [AI1]  { Name=stock; ShortName=BARb; Version=stable; Team=1; Host=0;
             [OPTIONS] { profile=hard; } }

    [TEAM0] { TeamLeader=0; AllyTeam=0; Side=Armada; Handicap=0; }
    [TEAM1] { TeamLeader=0; AllyTeam=1; Side=Cortex; Handicap=0; }
    [ALLYTEAM0] { NumAllies=0; }
    [ALLYTEAM1] { NumAllies=0; }

    [MODOPTIONS]
    {
        MinSpeed=9999;
        MaxSpeed=9999;
        debugcommands=108000:quitforce;
    }
}
```

Three things are easy to get wrong:

- **`GameType`** must be the game's *advertised* name. From a `.sdd` checkout
  that's literally `Beyond All Reason $VERSION`, because `modinfo.lua` ships with
  `version = '$VERSION'` and only CI substitutes it. Run
  `python tools/unitsync.py games` to see the real strings.
- **`MapName`** is the display name. `python tools/unitsync.py maps <substring>`.
- **`Host=0`** in an `[AI]` block is the *player number* whose machine runs the
  AI, not a boolean.

A LuaAI is selected differently — no `[AI]` section, instead `LuaAI=SimpleAI;`
inside the team block.

Shortcut for bootstrapping: configure a skirmish in the normal client, launch,
quit, and read `<data>/_script.txt` — the engine writes the last start script
there.

## Speed: MinSpeed is the lever

The non-obvious one. `GameServer::UserSpeedChange` does:

```cpp
if (userSpeedFactor == (newSpeed = std::clamp(newSpeed, minUserSpeed, maxUserSpeed))) return;
```

The initial speed is clamped **into** `[MinSpeed, MaxSpeed]`, so raising
`MaxSpeed` alone changes nothing — `MinSpeed` is what pushes the sim above 1×.
Set both. Defaults are `MaxSpeed=20`, `MinSpeed=0.1`. The adaptive throttle then
runs as fast as the CPU allows; config var `SpeedControl` (1 = average CPU,
2 = highest) tunes it.

There is no `--maxspeed` CLI flag.

## Ending the run

**`debugcommands`** is BAR's own hook, declared in `modoptions.lua` and
implemented by `luarules/gadgets/cmd_dev_helpers.lua`:

```lua
function gadget:GameFrame(n)
    if debugcommands and debugcommands[n] then
        Spring.SendCommands(debugcommands[n])
    end
end
```

Format `frame:command|frame:command`. 30 frames = 1 sim second.

```
debugcommands=1:cheat|2:globallos|3:godmode|108000:quitforce;
```

`quitforce` is the correct quit command (`quit` is deprecated). This is the
guaranteed cap and needs nothing installed into the game.

It fires at a **fixed frame**, though — a match that ends at minute 12 would
still run to the cap. `game-patches/gadgets/dev_autoquit.lua` fixes that: it
hooks `gadget:GameOver`, prints a machine-readable result line, and quits.
Install with `python tools/deploy_ai.py gadgets`. It is inert unless the start
script sets `dev_autoquit=1`, so it cannot affect normal play.

```
[BARAI_RESULT] reason=gameover frame=48464 winners=1
```

BAR also ships `luaui/Widgets/cmd_autoquit.lua`, which quits 12 s after game over
— but it postpones on mouse movement, so `debugcommands` is the reliable
primitive for a harness.

Add `deathmode=neverend;` when you want a fixed-length run that can't end early.

## Logs

`infolog.txt` lands in the **write dir**. The harness copies it into each match
folder.

Config vars worth setting (`tools/headless.cfg` does):

```
LogFlushLevel = 0      # flush everything immediately — essential if the run gets killed
RotateLogFiles = 0
LogSections = ...      # comma-separated filter; the engine prints available sections at startup
```

Delete `<writedir>/LuaUI/Config` between runs — BAR's own `start.sh` does this,
because stale widget config silently changes which widgets load.

From Lua: `Spring.Echo`, `Spring.Log(section, LOG.WARNING, msg)`,
`Spring.SetLogSectionFilterLevel`.

## Console commands

Dump the real list from your binary:
`spring-headless.exe --list-synced-commands` / `--list-unsynced-commands`.

Synced: `cheat`, `godmode`, `globallos`, `give`, `nocost`, `take`, `skip <frame>`,
`destroy`, `luarules <sub>`, `luagaia <sub>`.
Unsynced: `quitforce`, `reloadforce`, `luaui <sub>`, `debug`, `debuginfo`,
`debugdrawai`, `debugpath`, `pause`, `setspeed`, `reloadshaders`.

Hot reload while playing: **`/luarules reload`** (gadgets), **`/luaui reload`**
(widgets). AngelScript and JSON are read at **AI init** — no hot reload; start a
new match.

BAR's `cmd_dev_helpers.lua` adds many `/luarules <cmd>` helpers after `/cheat`:
`givecat`, `destroyunits`, `removeunits`, `killteam`, `spawnceg`, `maxhealth`,
`sethealth`, `relocate`, `globallos`, `desync`, and more. And
`dbg_test_env_helper.lua` adds `setTestEndConditions`, which strips the game-end
gadgets so a match cannot terminate early.

BAR ships auto-reloaders too (dev mode only):
`dbg_gadget_auto_reloader.lua`, `dbg_widget_auto_reloader.lua`.

## Replays

Written to `<writedir>/demos/*.sdfz`. Off by default in the harness (`RecordDemo=0`)
because they're large and slow batches down — pass `--replay` to keep them.

Play one back:

```powershell
& "$ENG\spring.exe" --write-dir "$BAR" "path\to\match.sdfz"
```

Use `--only-local` when replaying many in parallel.

Parsers:
- **`sdfz-demo-parser`** (TypeScript, official, actively maintained) —
  `npm i sdfz-demo-parser`, has a CLI with JSON output. You have Node 22.
- `parse_demo_file.py` in `beyond-all-reason/bar_debug_launcher` — lower level,
  packet/bandwidth analysis. There is no maintained general-purpose Python
  `.sdfz` library.

## Profiling

`/debuginfo profiling`. In-game profilers: `dbg_widget_profiler.lua`,
`dbg_gadget_profiler.lua`, `dbg_benchmark.lua`. `Spring.GetLuaMemUsage()` returns
8 values (handle/global/synced/unsynced alloced KB and alloc counts).
For C++-level work, the release page has a Tracy-instrumented engine build
(`recoil_2026.06.12_amd64-windows-tracy.7z`).

Headless gotcha BAR itself hit: `dbg_test_headless_overrides.lua` stubs
`gl.PushMatrix`/`gl.PopMatrix` because they still do accounting under headless
and error inside display lists. Any `gl.*` call in a data-extraction widget is a
landmine.

## Batch runs

```bash
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10
python tools/run_tournament.py --report
```

Sides are swapped every other game because team 0 and team 1 don't get equivalent
start positions on most maps — without the swap you measure the map.

Output is one self-contained directory per run — **`tournaments/`, not
`matches/`**:

```
tournaments/<stamp>-<slug>/
    ledger.jsonl      one JSON row per completed match
    summary.txt       the printed report
    config.json       what was run, so a result is reproducible
    matches/tNNN-.../ script.txt, infolog.txt, result.json per match
```

Engine scratch (write dirs, archive caches, demos) lives in `runtime/`. Both
`tournaments/` and `runtime/` are gitignored.

Parallelism only scales with `ThreadPinPolicy = 0` in `tools/headless.cfg` —
with the engine's default pinning every instance pins to the *same* cores and
they serialise while the rest of the machine idles.

### Reading a batch

```bash
python tools/review.py <run> --control <run>   # the verdict, with gates
python tools/tl.py tournaments/<run>           # paired timeline by game minute
python tools/composition.py <run>              # where the metal actually went
python tools/fight1v1.py <run-dir> [more...]   # army trade efficiency in metal
```

`tl.py` reads which side is which from each match's `script.txt`, so a
side-swapping tournament never averages us against ourselves. `fight1v1.py`
takes each side's own last sample, because a dead team stops reporting and the
global last frame contains only the survivor.

### The game-length cap is part of the measurement

Every 1v1 tournament in this repo before 2026-08-10 capped at 20 minutes, and
most games were still running at the cap — so the win rate was not merely noisy,
it was unmeasurable, and the army-trade proxy stood in for it. At 45 minutes
essentially every 1v1 reaches game over. Median 1v1 game length is 24-34 min:
a 20-minute cap cuts games off at roughly the point they are being decided.
Check that your cap is longer than the games before reading a win rate.

At ~45 s per match, 10 games is ~8 minutes. Parallelising is possible with
separate write dirs plus `--only-local`, at the cost of contended CPU; the sim is
already CPU-bound, so expect sublinear gains.

## Sample size: 10 games is not enough

Learned the hard way. The same variant (`apex6`, unchanged) was measured twice:

```
batch 1, mixed faction     6-4   60%   CI 31-83%
batch 4, Cortex v Cortex   1-9   10%   CI  2-40%
pooled                     7-13  35%
```

A **50-point swing on the same AI**. A stable-vs-stable control run in the same
configuration came out 4-6 for ally team 0 (CI 17-69%), so the harness is fair --
the swing is pure sampling variance.

Consequences for anyone using this harness:

- **Always run a self-play control** (`--a X --b X`) before trusting a
  comparison. It gives you the noise floor and proves the side swap actually
  cancels start-position bias. Do this first, not last.
- **10 games resolves nothing** short of a landslide. Separating 60% from 50% at
  95% confidence needs roughly 100+ decided games; 10 games has a CI about 30
  points wide in each direction. Use 10-game runs to catch *catastrophic*
  regressions (apex3's 0-10 was real), never to confirm an improvement.
- **Pin the faction with `--sides`.** Mixed factions add variance for no benefit,
  and any faction-specific unit only appears in half the games.
- **Do not stack changes selected on small samples.** Building apex7 on top of
  apex6's apparent 60% compounded a result that turned out to be noise.

Rough costs on a 12-core machine, 4v4, 60-minute cap, 3 workers:
10 games ~25 min, 100 games ~4 hours. Screen wide and shallow for breakage;
confirm narrow and deep for improvement.
