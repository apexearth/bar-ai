---
name: bar-benchmark
description: Run and interpret headless AI-vs-AI matches in Beyond All Reason to measure whether an AI change actually helped. Use when testing a BARb config or script change, comparing AI variants or profiles, measuring win rates, or debugging why a headless match hangs, ends instantly, or reports no winner.
---

# Benchmarking a BAR AI change

The point of the harness is to answer "did that change help?" — which is harder
than it looks, because BARb-vs-BARb outcomes are very noisy.

## One-time setup

```bash
python tools/deploy_ai.py gadgets
```

Installs `dev_autoquit.lua` into `BAR.sdd`. Without it a match runs to the frame
cap instead of ending at game over, and no winner is recorded. It is inert unless
the start script sets `dev_autoquit=1`, so it cannot affect normal play.

## Single match

```bash
python tools/run_match.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
```

Spec format `ShortName[:Version[:profile]]`, or `lua:SimpleAI` for a LuaAI.
Output lands in `matches/<stamp>-<slug>/`: `script.txt`, `infolog.txt`,
`result.json`, optionally the replay (`--replay`).

Reference timing on this machine: a 27 game-minute match ≈ 44 s wall (~37×
realtime), plus ~35 s the first time while the archive cache builds.

Useful flags: `--windowed` (run in `spring.exe` to watch it), `--dry-run` (print
the start script and stop), `--speed`, `--engine`.

## Batch

```bash
python tools/run_tournament.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10
python tools/run_tournament.py --report          # re-summarise the ledger
```

Sides swap every other game — team 0 and team 1 do not get equivalent start
positions on most maps, so without the swap you are measuring the map. Results
append to `matches/tournament.jsonl`.

## Reading results honestly

`result.json` → `result.reason`:

| reason | meaning |
|---|---|
| `gameover` | a real result; `winner_specs` is meaningful |
| `timelimit` | hit the `--minutes` cap — **not** a win for anyone |
| `walltimeout` | the process was killed; something is wrong |
| `unknown` | the autoquit gadget isn't installed, or it didn't run |

Also check `desync` and `ai_errors` — an AI that threw exceptions all game is not
a valid data point.

**Interpretation rules:**

- A single match tells you nothing. 10 games with side swapping is a weak signal.
- Only `gameover` matches count toward win rate. A change that pushes lots of
  matches into `timelimit` has changed the game length distribution, which is
  itself a finding — report it rather than hiding it.
- Comparing `hard_aggressive` against `hard` compares two profiles, not two
  variants. To isolate your change, benchmark your variant against **the same
  profile** in stock BARb.
- Vary the map. Config changes routinely help on one map and hurt on another.
- Change one thing per benchmark run.

When reporting to the user, give the counts and the reason breakdown, not just a
percentage. Say plainly when a result is within noise.

## When a match misbehaves

**Ends instantly / no AI in the log** — the AI didn't load. Check
`python tools/unitsync.py ais`, then grep the infolog for `Skirmish AI`.

**Runs to the cap every time** — either the gadget isn't installed
(`deploy_ai.py gadgets`), or `deathmode` is set to `neverend`, or the AIs really
are stalemating; check `game_minutes` against the cap.

**Very slow** — sim speed comes from `MinSpeed`, not `MaxSpeed`
(`UserSpeedChange` clamps the start speed *into* the range). The harness sets
both; if you hand-wrote a script, that's the usual cause.

**"no map matching"** — start scripts take display names, not filenames.
`python tools/unitsync.py maps <substring>`.

**Wrong game loads** — `GameType` must be `Beyond All Reason $VERSION` for the
`.sdd` checkout; `$VERSION` is literal. `python tools/unitsync.py games`.

## Digging into a match

```bash
D=matches/<stamp>-<slug>
grep -a "Skirmish AI" $D/infolog.txt | head -30      # AI init, config paths, script errors
grep -a "BARAI_RESULT" $D/infolog.txt                # the result line
grep -aiE "error|exception" $D/infolog.txt | head    # failures
```

The AI's own `AiLog()` output appears prefixed with its display name, so
instrumenting AngelScript and reading it back from a headless run is a fast
debugging loop — much faster than launching the client.
