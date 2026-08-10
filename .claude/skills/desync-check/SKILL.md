---
name: desync-check
description: Check whether a game desynced, watch a live multiplayer game for sync errors, or reproduce and bisect a desync with paired host/peer processes. Use when apexearth reports a desync, asks to be watched during a hosted game, or when a change touches AI code that calls into the engine.
---

# Desync check

A desync is silent. The engine writes one line to the infolog and the game keeps
running and looking normal, so the usual first symptom is that the replay
disagrees with what was on screen. Everything here exists because of that.

## The one fact the whole thing rests on

**AI code runs on ONE machine.** Every `[AI]` block in a start script carries
`Host=<player number>`; that process executes the AI, and every other client
only replays its netted orders. So:

- AI *orders* are safe. They go out as net messages and every client applies the
  identical command.
- An AI call that **touches engine state directly** is not. It happens on the
  host and nowhere else, and that is the whole class of bug.

This is why a single-process benchmark match can never desync, and why months of
`run_match.py` runs found nothing.

## Did this game desync?

    grep -c "Sync error for" <infolog>
    grep -m3 "Sync error for" <infolog>

The live install's log is `<data>/infolog.txt` (see `tools/bar_env.py`); harness
runs keep their own copy in the run directory. The line reads
`Sync error for <player> in frame <n>`, logged by the SERVER, and the named
player is the one whose checksum differs.

Read the frame: divergence that repeats every few hundred frames from one point
onward is permanent, which is the normal shape.

**Before blaming the AI, rule out an archive mismatch.** Search the log for
`mod-checksums` and `map-checksums`; the server and client values are printed for
every player. If they all match, `BAR.sdd`, the dev gadgets and `game-patches`
are irrelevant — a hosted game plays the rapid packages, not `BAR.sdd`.

## Watching a live game

Poll the live infolog in the background and report the moment it appears:

    while ...; do grep -q "Sync error for" "<data>/infolog.txt" && break; sleep 15; done

`game-patches/widgets/dbg_desync_alarm.lua` does the same thing on screen —
a red band with who diverged and at what frame. Installed to
`<data>/LuaUI/Widgets/`. If it does not show up, check F11.

## Reproducing one

`tools/run_netmatch.py` runs a host process and a peer process against each
other on one machine. The host runs both AIs; the peer is a spectator that
simulates from the net stream, which is what makes disagreement observable.

    python tools/run_netmatch.py --a Apex:apex:hard_aggressive --b BARb:stable:hard \
        --map "Flats and Forests v2.2" --per-side 4 --minutes 12 --seed 11

About two minutes per run. Sequential only — two netmatches on one port collide,
and two at once halve the sim speed.

**Three ways a run lies, all of them reported by the tool:**

1. **The peer never simulated.** It prints the frame each process reached and
   says `INVALID` rather than "none" when the peer trails. The first version of
   this harness lost the peer at load (the engine's default
   `initialNetworkTimeout` is 30s, BAR takes ~40s to load) and reported a clean
   game. The tool now writes 600s timeouts into both write dirs.
2. **The variant did not compile.** It prints the AngelScript error count. A
   compile error disables the variant, it plays near-stock, and of course
   nothing desyncs. This is how mixing new scripts with an old DLL fails.
3. **A tunable was silently ignored.** `dev_tunables.lua` has an explicit
   `NAMES` list; a modoption not in it is dropped with no message. Confirm
   `[BARAI_TUNABLE] <name>=<value>` is in the log before believing an A/B.

## Bisecting

Cut along one axis at a time. The variants under `ai/` are frozen snapshots and
make good controls (`ord`, `ctl`, `stk`).

1. **Stock vs stock** first. If `BARb:stable` desyncs too, it is upstream and
   not ours to fix.
2. **A frozen variant vs stock.** Clean means the cause is newer than it.
3. **Split C++ from game-side** with a hybrid: copy the deployed variant folder
   in `<engine>/AI/Skirmish/`, swap in the other DLL, and edit `AIInfo.lua`'s
   `shortName`/`version` to a new name. Old scripts against a new DLL compile
   (bindings only get added); new scripts against an old DLL do not.
4. **Then compare binding usage** between the clean variant's scripts and the
   desyncing one. The bug is in what only the broken one calls.

## Bindings, by whether they touch the simulation

Verified 2026-08-09 by reading each implementation.

**Dangerous — executes on the host alone:**

- `ai.GetPathLength` → `CAICallback::InitPath` → `QTPFS RequestPath(...,
  synced=false, immediateResult=true)`. Runs a real A* inline and creates
  entities in the same global `entt` registry as the synced paths. QTPFS's own
  `ExecuteQueuedSearches` warns "Do NOT impact this group while the background
  tasks are running". **This caused the 2026-08-09 desync.**
- `ai.CallRules` → `luaRules->RecvSkirmishAIMessage`, a direct call into
  **synced Lua** with no net message. Currently unused by any apex script and no
  gadget implements the receiver. Never use it.

**Safe — netted:** `SendResources` (`SendAIShare`), `GiveUnits` (`SendUnits`),
`CmdMoveTo` and every other order.

**Safe — host-local memory or reads:** `PublishTeamValue`/`ReadTeamValue` (a
plain in-process map), `UnitControl` (AI task bookkeeping), `GetTunable`,
`GetGameRulesParam`, `GetTeamRulesParam`, `GetTeamMetalFill/Income`,
`GetOwnStructsNear`, `IsMex`, position reads.

It is **not** the synced RNG: `grep gsRNG rts/Sim/Path/` is empty. The synced RNG
users are `GroundMoveType`, `HoverAirMoveType`, `Wind`, `Feature`,
`SimObjectIDPool`, `LuaHandleSynced`.

## Judging a fix

Turning the suspect off and getting a clean run is one direction. Prefer both:
turn it off (clean), turn it up (worse). Note that on 2026-08-09 the dose-response
did **not** appear — 6× the probe rate changed nothing — so an on/off result may
be all that is available. Say so rather than implying more.

Then check the replacement still does its job. A rule that is clean because it
never fires has not been validated; find the log line that proves it acted.
