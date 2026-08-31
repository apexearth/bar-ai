---
name: bar-benchmark
description: Run and interpret headless AI-vs-AI matches in Beyond All Reason to measure whether an AI change actually helped. Use when testing a BARb config or script change, comparing AI variants or profiles, measuring win rates, or debugging why a headless match hangs, ends instantly, or reports no winner.
---

# Benchmarking a BAR AI change

Treat every run as an experiment, not a demo. BARb-vs-BARb outcomes are noisy,
so the question is never "did it win" — it's "does this result survive a
control, a decent sample size, and a look at the metric over time."

## Method

1. Change **one thing**. State what you're testing before you run it.
2. Run a **control** — the unmodified baseline — under identical settings
   (map, seed, speed, player count). Never judge a treatment without one run
   alongside it; a bad result on its own could be a pre-existing regression,
   not your change.
3. Take **equal-sized samples** of control and treatment. A handful of games
   is a weak signal either way — say so rather than declaring victory.
4. Judge a metric by its **behaviour over the timeline**, not its value at
   game-end (see below — this is the part most likely to mislead).
5. Report the counts and what they show, including when it's within noise.
   Don't round a coin flip up to a finding.

## Setup

```bash
python tools/deploy_ai.py gadgets
```

Installs `dev_autoquit.lua` into `BAR.sdd`. Without it a match runs to the frame
cap instead of ending at game over, and no winner is recorded. It is inert unless
the start script sets `dev_autoquit=1`, so it cannot affect normal play.

## Running matches

```bash
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
```

Spec format `ShortName[:Version[:profile]]`, or `lua:SimpleAI` for a LuaAI.
Output lands in `matches/<stamp>-<slug>/`: `script.txt`, `infolog.txt`,
`result.json`, optionally the replay (`--replay`).
Useful flags: `--windowed` (watch it live), `--dry-run` (print the start
script and stop), `--speed`, `--engine`.

```bash
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10
python tools/run_tournament.py --report          # re-summarise the ledger
```

Sides swap every other game — without the swap you're measuring the map's
starting-position asymmetry, not your change. Vary the map across the batch
too: a config change routinely helps on one map and hurts on another. Results
append to `matches/tournament.jsonl`.

## Judge the timeline, not the end state

This is the single most common way to misread a run. Standing counters —
constructors, army size, `mCon` — go to **zero** when a team loses, so the
last sample of a lost game is a corpse, not data. Reading only the end state
has produced backwards conclusions here before (a team that actually held
*more* constructors all game read as building "1 to the other side's 10"
because the sample was taken after it died).

- `analyze_stats.py <run>` samples every couple of game-minutes. Use it. The
  timeline shows *when* two runs diverge, which is usually the actual finding
  — a cumulative total or an end-of-game snapshot hides it.
- Cumulative counters (total metal produced, kills, losses) are safe to read
  at the end; standing/instantaneous ones are not.
- `composition.py` reports standing counters as PEAK for this reason, and
  flags how many player-games ended wiped out — read that line before trusting
  a composition claim.

## Reading run status honestly

`result.json` → `result.reason`:

| reason | meaning |
|---|---|
| `gameover` | a real result; `winner_specs` is meaningful |
| `timelimit` | hit the `--minutes` cap — **not** a win for anyone |
| `walltimeout` | the process was killed; something is wrong |
| `unknown` | the autoquit gadget isn't installed, or it didn't run |

Also check `desync` and `ai_errors` — an AI that threw exceptions all game is
not a valid data point. Only `gameover` matches count toward a win rate; a
change that pushes matches into `timelimit` instead has changed the game
length distribution, which is itself a finding worth reporting, not hiding.

Comparing two profiles is not comparing two variants — to isolate your change,
benchmark against the closest stock profile and change nothing else. (`Unstable`
ships exactly one profile, `standard`; the stock easy/medium/hard/rush trees
were deleted, so the stock side of the comparison is a `BARb:stable:<profile>`
spec.) And note the shortName: a spec beginning `BARb:` runs STOCK, whatever
version you name after it — ours is `Apex`.

## Telemetry fields that under-count

`dev_stats_export.lua` has `SPAM_COST = 120`, and **anything cheaper is excluded
from `mBuiltReal`, `top=` and `allBuilt`**. That is not a rounding detail:

- **a mex is 26 metal**, so extractors appear in NONE of those three fields.
  `allBuilt` with no `armmex` in it is normal, not evidence of a broken economy;
  read `mex=` (extractors finished) instead.
- cheap army (a Pawn is 54) is likewise absent — `cheapBuilt`/`counts=` carry it.

So `mBuiltReal` is biased AGAINST a mex-heavy or chaff-heavy strategy, and two
arms that differ in how much they expand cannot be compared on it. **Prefer
`mEco`** — the eco/army/bp/def classification runs on every finished unit with
no cost gate, so it does include extractors — and quote `mex=`, `t2Mex=` and
`techStart=` alongside anything headline.

## Confounds to rule out before trusting a result

Don't assume you know the numbers ahead of time — measure them on the run in
front of you. Two ways this harness has produced a misleading result:

- **The benchmark's pace may not match what you're trying to reproduce.**
  If a behaviour is gated on some in-game condition (an income threshold, a
  unit count, elapsed time), check what that condition's actual value is in
  *this* run before concluding the behaviour is broken — a benchmark that
  never reaches the gate will never show it firing, and that's a setup
  problem, not a bug. Don't carry forward last month's measured numbers as if
  they still apply; conditions in a fast-moving codebase drift.
- **Simulation speed can distort AI behaviour, not just wall-clock time.**
  Orders given to a unit are sent over the network and applied when that
  message is processed, not the instant you issue them — so at a high sim
  speed, code that reads a unit's state and issues more work based on it can
  read stale state and pile up backlog. If you're testing anything that
  touches production, task assignment, or command volume, check the actual
  command backlog (e.g. `facQueued` in `dev_stats_export.lua`) rather than
  assuming a given `--speed` is safe, and always compare treatment against a
  control run at the **same** speed.

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

**A compile error can disable the whole AI and still report a normal
result.** Grep the infolog before trusting anything else:
`grep -ciE "\.as \([0-9]+, [0-9]+\) : ERR" infolog.txt`

**A grep that returns nothing means the pattern is stale, not that the thing
is absent.** Log formats drift over time — confirm the pattern matches
*something* in a run you know fired before concluding it never fires.

**Player count vs. map size.** Match the number of players to what the map is
built for; a mismatch starves everyone and invalidates the economy for the
whole run.

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

`python tools/review.py <run> --control <run>` runs the checks above as a
gate and withholds a verdict when one fails. Prefer it to doing them by hand.
