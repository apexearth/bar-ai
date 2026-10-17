# Working here

How to work in this repo: the rules, the commands, lanes, testing, building and releasing.
Traps with S numbers are in `traps.md`.

## Rules of work

- **Instrument first.** Prove the code executes (the log line), prove its output decides the outcome, then change it; if the instrument shows the decision did not move, say so.
- **Ask before inventing policy.** Caps, exclusivity, switching a behaviour off and thresholds are decisions about what the AI is allowed to do, and they are his. In order: derive it from the economy; ask him (one plain sentence, in game terms); a named constant with the derivation in the commit message.
- **A tunable is the last resort.** Create one only for a sweep you will run and report this session; a proven change deletes its gate and `TUNE_` constant in the same commit. A new tunable or want kind is not finished until the dashboard shows it (`dashboard-ui`).
- **He reverts behaviours freely and keeps build rules.** When a change is ambiguous, ask which of the two it is.
- **Price the cost before writing the code.** A proposer or anything an election calls runs ~1,000-1,500 times a minute per AI, times up to 16 AIs: write down what it loops over and how that grows; build lists once on a clock or exact key; check `apex: perf AiMakeTask avgUs` at minute 10+ of an 8v8 (`ai-performance`, 0.417 ms/AI/frame budget).
- **Spread work across frames, never batch it.** A section whose `maxMs` is many times its `avgUs` is batching.
- **One change at a time**, judged on `composition.py`; firing is not evidence (`traps.md`, Method).
- **Comments:** default none; one line of what looks wrong otherwise and why. Never a finding, measurement, date or session story; change the code, change the comment; never state a cause you did not measure. Run `comment_audit.py` before committing a change that touched comments.
- **Where things are written:** the commit message (what changed, what was measured); `ISSUES.md` (wrong now, with evidence); `USER-FEEDBACK.md` (his open asks); `TODO.md` (his named plays, unbuilt); `tunables.md` (why a default is what it is); `doctrine.md` (his directives only). An entry is deleted when built and measured.
- **Files stay under ~600 lines**; an edit anchor that does not match does nothing (S18).
- **Never author Python in a Bash heredoc**: `Write` a script (scratchpad or `tools/`), then run it.
- **Work directly**; delegate only when he asks or for a broad search whose file dumps you do not need. Write the finding down before an agent ends.
- **Watching beats measuring.** A watched game answers in minutes; hand him a windowed run when he asks for one, and measure alongside.
- Conventions: Python 3.13, stdlib only; tools import `bar_env.py` and never hardcode a path; `reference/` is read-only; LF line endings (`normalize_eol.py`); scripts that rewrite a file use `write_bytes` (S21).

## Context discipline

Measured over 20 sessions, 86% of tokens were Bash, by volume. Batch independent probes into one
call; ask for the answer (`grep -c`, `| sort | uniq -c`, `| head`), not the corpus; `grep -n` then
`sed -n 'A,Bp'` instead of `cat`; use `review.py`/`trace.py`/`diagnose.py` instead of hand-rolled
infolog greps; load the owning skill instead of reading the source tree; exclude `vendor/`,
`matches/`, `changes/`, `reference/` from repo-wide searches.

## Commands

```bash
python tools/review.py <run> [--control <run>]  # THE way to judge a run; gate 1 = compiled, ran, no crash
python tools/story.py <match> --bucket 120      # why a game was won or lost: read FIRST
python tools/minutes.py <match> [--step 2]      # per minute, per side: income, energy, waste, mexes, k/l, damage
python tools/mapframe.py <match> --minutes 4,8,12,16,20,24   # PNG contact sheet of the game
python tools/trace.py latest --filter=decide    # apex: lines for one tag, minute-stamped
python tools/diagnose.py <run>                  # 3 lines when clean
python tools/deadcheck.py <run>                 # rules that never fired
python tools/frametime.py <run>                 # per-section maxMs + the 16-AI verdict (apex_perf=1)
python tools/hitch.py <run>                     # wall-gap freezes no section owns (S31)
python tools/scenario.py run all --parallel 2   # scripted fights, PASS/FAIL in ~1 min each (army.md)
python tools/composition.py <tournament>        # where the metal went
python tools/spendtable.py <tournament>         # income/mex/army/spend/lost per 4 min, us vs them
python tools/progress.py [--games] [--by day]   # are we getting better vs BARb, batch over batch
python tools/ecoside.py / allies.py / ecotimeline.py   # economy per side; 8v8 allies; bank over time
python tools/deaths.py / battles.py / fight1v1.py      # why a fight was lost
python tools/check.py 2>&1 | tail -30           # static checks incl. the kill census and docs audit
python tools/as_scope.py                        # AngelScript declaration-order check
python tools/comment_audit.py                   # run reports and essays in your diff
python tools/unitdef.py <unit> [--builders|--builds|--trees]
python tools/bar_env.py                         # resolved paths and engine
python tools/lane.py init <name>|status|list|drop <name>
python tools/build_dll.py [--deploy]
python tools/deploy_ai.py status|deploy [Unstable]|pull Unstable|gadgets|patches
python tools/dashboard.py                       # his UI: runs, launch, deploy, tunables, nets
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard --map "Comet Catcher" --minutes 60 --seed 1
python tools/run_tournament.py --a ... --b ... --maps ... --games 10   # then --report
python tools/ab.py / battery.py / expect.py     # paired arms; the regression battery; what a battery must show
python tools/randsearch.py --status             # the policy-net search
python tools/reclaim.py [--apply <category>]    # disk the repo costs and what can go (never du)
python tools/context_size.py                    # what the repo costs to read
```

Batch output lands in `tournaments/<stamp>-<slug>/` (ledger, summary, per-match folders); single
matches in `matches/`. A 27 game-minute match takes ~45 s wall warm.

## Lanes: several sessions, one repo

`python tools/lane.py init <name>` once per session. Claims are keyed by session id in
`.barai-lanes`; after that `build_dll`, `deploy_ai`, `sync_cpp`, `smoke` and `run_match` follow the
lane with no flags. Your AI is `Apex<name>:lane-<name>` (`lane.py status` prints it).

| | shared slot (his) | lane `foo` |
|---|---|---|
| C++ source you edit | `vendor/engine/AI/Skirmish/BARb` | `.../BARb-foo` |
| build output | `vendor/engine/build-amd64-windows` | `vendor/engine/build-foo` |
| deployed AI | `Apex:Unstable` | `Apexfoo:lane-foo` |
| engine write dir | `matches/_engine` | `matches/_engine-foo` |

- `Apex:Unstable` is his slot (dashboard, his games): a session with no claim is refused by every writing tool; `BARAI_LANE=shared` names it on purpose.
- `ai/Unstable/` is shared by every lane and re-copied into the lane on each deploy: a lane is a shipping slot, not a fork. A peer's script that calls a binding only their DLL has compiles to a disabled variant under yours (S3).
- After every C++ edit, `python tools/sync_cpp.py pull` mirrors the lane into `cpp/` (the only copy git keeps). Before a pull, `git diff --stat cpp/`: hunks that are not yours mean merge, not pull.
- Gadgets and patches in `BAR.sdd` are global to all lanes. No leading underscore in a lane name (S53). `lane.py drop` when done (~0.7 GB each).

## Machine limits and his game

- Count every `spring-headless` and `spring` process before launching: limits are machine totals, and the search's keepalive restarts it behind you. Stopping the search means stopping its engines too.
- While he plays online: at most 4 headless games in total. While he only watches our watch game: up to 8. Not playing: up to 10. His online game shows as our bots' `apex-t*.log` written in the last ~2 minutes (`mp_archive.his_game_running()`); the lobby itself is a `spring.exe`, so a process check cannot tell.
- A headless engine commits ~5-6 GB; 12 is the hard ceiling, 8 is comfortable for him.
- Watch games for him: `run_match.py --watch --speed 10 --handicap 0`.
- Never run two engines on one write dir; never edit a file a running tournament uses; deploying while BAR has the AI folder open fails half-written (`WinError 5`). `pgrep`/`pkill` do not work here: wait on an artifact, stop processes with PowerShell `Get-Process ... | Stop-Process`. Run Python with `-u` when logging to a file.

## Testing and judging a change

- **Every batch passes `--speed`** (`--speed 20` for A/B and tests): uncapped runs stall commanders (S24, S29, S34). Comparable arms need the same worker count or a fixed speed.
- **Handicap is part of the regime**: `run_match` and `run_tournament` default to +0; his tournaments run +50, `ab.py` and many batteries +100. Never compare economies across handicaps; check `Handicap=` per team in a side-swapped script.
- **Give every A/B game its own write dir**: `apex-record.txt` (the unit track record) carries over between games in one dir. Late-game numbers from parallel engines can be the lag ladder starving builders unless `apex_lag_speed=0`.
- **Tests run his lobby's game version**: when his lobby updates, stop engines, `python tools/sync_game.py`, `deploy_ai.py gadgets`, redeploy, smoke.
- **Small batches read deeply**: 4-6 games read for mechanism, then decide whether to run more. A genuinely ambiguous result gets one properly powered batch, not pooled small ones. Ten games resolve only a landslide; 60% vs 50% needs 100+ decided games.
- **Read a WIN and a LOSS minute by minute** (`story.py`, then `minutes.py`): when we lose we make less metal because we are losing, so a batch average reports the consequence as the cause. The final numbers are never the story; find the turn.
- **Trades by damage efficiency** (D% = dealt / received), not K/D. A short game plus `deaths.py` answers why a fight was lost; "retreat" is never the answer, the action before it is.
- **A 1v1 result is commander death**: judge economy with `techtime.py`, against a fixed opponent (self-play eco ratios are noise).
- **Maps that are not data**: reclaim-heavy, water or asymmetric maps for an economy question; All That Glitters 2v2 and seat 4 of Supreme Isthmus 8v8 spawn trapped in the harness.
- Map by feature: air on Carrot Mountains, navy on Supreme Isthmus, fast 1v1 on Comet Catcher Remake; he watches Greenest Fields 2v2/8v8, same faction both sides. His games run the scavenger pack (`experimentalextraunits=1`, `scavunitsforplayers=1`).
- A fixed seed lets a search overfit one game; every search game takes its own seed.
- Do not restate the seed caveat to him; he knows `FixedRNGSeed` does not reproduce a run.

## Building the DLL

`python tools/build_dll.py` runs the Docker ninja build (`recoil-build-amd64-windows` image,
MinGW-w64 GCC 13 posix, static libstdc++, msvcrt) and refuses `--deploy` unless the exit code is 0
and the artifact is newer than the sources (S54). Start Docker Desktop first. The artifact is
`vendor/engine/build-<lane>/AI/Skirmish/BARb/data/SkirmishAI.dll` (~205 MB with DWARF; never commit
it). `deploy` refuses to ship the stale checked-in DLL without `--repo-dll` (S26). Build against the
engine tag you run: the AI-engine boundary is a struct of function pointers with no ABI promise.
A crash offset in an infolog is relative to the module base: add the PE ImageBase, and the PC is
the return address (`x86_64-w64-mingw32-addr2line -f -C -i -e SkirmishAI.dll <addr>`). The
`cpp-dll` skill has the rest.

## Deploying and releasing

- `deploy_ai.py deploy` copies the variant to the engine's `AI/Skirmish/Apex/<version>/` (DLL, AIInfo, AIOptions, config, script) and the game-side config/script. Deploy in the foreground, verify it (or `deploy_ai.py status`), then background the run. Deploying the AI does not deploy the gadgets (S8).
- **A hosted game loads the highest installed Apex version**, never the lobby's pick, so deploying to `Unstable` never reaches his online games. VersionCompare compares each dot part as a string: never put a two-digit part next to a one-digit one; go to the next minor.
- Release: copy `ai/Unstable` to `ai/v0.N.M` and set its `AIInfo.lua` version; build the shared DLL from current `cpp/` (`BARAI_LANE=shared sync_cpp.py apply` + `build_dll.py`); put the chosen policy weights in the release's `policydata.as` (the search republishes the lane's copy on every restart); `BARAI_LANE=shared deploy_ai.py deploy v0.N.M` (needs a green gate or his OK for `--allow-red`); smoke one short match (no `ERR`, `apex: version ... v0.N.M`); drop the old version from the install.
- GitHub release: a `v*` tag runs `.github/workflows/release.yml`, which builds the DLL from the fork pinned in `.github/release.env` and refuses unless the tagged `cpp/src` equals `CIRCUITAI_SHA`. Push the release's `cpp/src` to apexearth/CircuitAI `barbarian-apex` first, set the pin and `VARIANT`, test with `tools/package_ai.py`, then push the annotated tag.

## Environment

`python tools/bar_env.py` resolves the install (`%LOCALAPPDATA%\Programs\Beyond-All-Reason\data`
is the engine's write dir), the active engine (launcher config -> setup -> engine version) and the
game tree; override with `BAR_ROOT`, `BAR_DATA`, `BAR_ENGINE`, `BAR_GAME_SDD`. `data/games/BAR.sdd`
is the harness's game (built from his lobby's version by `sync_game.py`, `modinfo` version
`$VERSION`, which turns BAR's dev mode on); Chobby plays the rapid `.sdp` packages. `vendor/bar`
tracks upstream master, a different vintage (S11). No native toolchain is installed; the DLL builds
in Docker. Headless needs `MinSpeed` raised (the harness does it); `debugcommands=<frame>:quitforce`
and `dev_autoquit.lua` end a match; `ThreadPinPolicy = 0` lets parallel engines use all cores.

## Upstream

Game-side configs go to `beyond-all-reason/Beyond-All-Reason`; C++ and binding changes to
`rlcevg/CircuitAI` branch `barbarian`. BAR's `AI_POLICY.md` requires disclosing AI-assisted code
in the PR, and human verification of it.

## References

- Game https://github.com/beyond-all-reason/Beyond-All-Reason · engine https://github.com/beyond-all-reason/RecoilEngine · AI https://github.com/rlcevg/CircuitAI (`barbarian` = BARb; `doc/Profile.md` is its only prose doc)
- Engine docs https://recoilengine.org/docs/ (Lua API, synced/unsynced commands, config vars) · start scripts `RecoilEngine/doc/StartScriptFormat.txt`
- Replays: `sdfz-demo-parser` (npm); public game data `https://api.bar-rts.com` (bar-db)
- BAR Discord is the primary dev hub.
