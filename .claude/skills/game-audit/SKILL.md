---
name: game-audit
description: Audit one BAR game (or a tournament) against apexearth's complaint list with tools/audit.py — what each check asserts, which telemetry it trusts, and the traps that make naive log reading lie. Use after any behaviour change, on any game he watched, or when deciding whether a reported problem is fixed.
---

# Auditing a game — did the AI make the mistakes he reported?

```bash
python tools/audit.py <match-dir-or-infolog>     # one game
python tools/audit.py <tournament-dir>           # aggregates matches/*/infolog.txt
```

Also a button on every run in the dashboard (Games tab → audit). Non-zero
exit when anything flags, so a runner can act on it.

**A FLAG is a lead, not a verdict.** Each one names the log line to read
next. A clean section is a real answer too — do not manufacture findings.
And a single game is noise: pool before claiming a trend (a per-game "e.g."
line read as a trend produced a false 45%→29% improvement claim once).

## What it reads — three telemetry layers, trust them in this order

1. **`[BARAI_BUILD]` gadget events** — one line per structure FINISHED, with
   team, frame, minute, def, cost. Ground truth for "what stood".
   Widened 2026-08-27 to `isBuilding or speed==0`: before that date nano
   turrets and dragon's teeth were INVISIBLE here — "0 nanos built" from an
   old log is *unmeasurable*, not zero.
2. **`apex: exec` lines** — what actually became a task, with `pick=N`
   (fallthrough depth past the drawn winner).
3. **`apex: decide` lines** — the *drawn* rank-0 want. The executor can
   refuse it and silently run the runner-up, so decide counts overcount
   every refused want. Count decides only for *election-preference*
   questions, never for "what did we do".

Other inputs: `apex: unit-destroyed` (our losses, with `built=0/1` for
frames), `apex: frontline` / `fronttowers` (geometry), `apex: perf sec`
(AI time), `apex: plantdup`, `apex: frame-orphan` / `frame-adopt`,
`apex: task-gone` (per-def `done=`/`abort=` — **`done` means the TASK ended
well, NOT that a building stands**; nano tasks logged done=171 in a game
with none standing).

## The checks, by section

- **HEALTH** — AngelScript errors (warnings are errors and print with NO
  filename), engine hang, `apex:` lines nonzero, ghost deaths.
- **PRIORITY** — advanced-con decision shares; moho-ranked-second-and-lost;
  duplicate-plant pricing (`plantdup` fields); frame abandonment.
  **A decision share is not an outcome**: boosting apex_mexup_boost once
  turned this section green while mexes held FELL 243→182. Read these
  against t2Mex / structures standing, never alone.
- **STRUCTURES** — the 2026-08-27 complaint list as assertions over what was
  BUILT: `no-storage` (his ruling: zero), `reclaim-rebuild loop` (same def:
  our reclaim exec then a rebuild), `plant-count` (any plant def ×3+),
  `nanos-standing`, `nano-latency` (plant→first nano), `t1-eco-with-afus`,
  `sense-churn` (executions per radar standing), `defence-tier` (T1-tower
  share once advanced cons exist).
- **GEOMETRY** — `front-band` (band/R ~1.0 = the trim is inert and "front"
  wraps the base), `front-towers` (sites won vs towers standing),
  `grid-tightness` (% of eco structures touching a neighbour).
- **ECONOMY / MILITARY / EFFICIENCY / VS-ENEMY** — the older checks:
  metal/energy wasted, hopeless attacks, raids, constructor attrition,
  mex race.
- **PERF** — worst single AI call and busiest sections from `apex: perf`.
  A 30ms single call is a visible hitch at watch speed.

## Traps that have produced wrong audits

- **Team attribution**: "ours" = every team that prints `apex: decide t=N`.
  In an 8v8 the STRUCTURES thresholds pool 8 teams crudely — a per-team
  outlier (7 nanos on one team, 148 on another) hides in the pool.
- **`result.json` `teams[].team` is the SPEC index**, not a game team; in
  per-side games spec b's players are teams N..2N-1. Anchor side splits on
  allyteam, never on that field.
- **unit-destroyed counts include unfinished frames** (`built=0`), so
  built−destroyed can read negative; and it cannot attribute the killer —
  our own reclaim shows only via a preceding `exec ... reclaim:` line.
- **Mid-game reads**: a live game's infolog is in `matches/_engine*/` —
  check the file's mtime against the game being discussed; `_engine_watch`
  once served a 17-day-old log as "live". DURING a game the AI's own lines are
  not in it: they go to `apex-t<team>.log` in the AI's data dir (the infolog's
  `apex: log file` line names them) and `run_match` merges them in when the
  game ends. For a mid-game read, or a lobby game's `<data>/infolog.txt`, run
  `python tools/apexlog.py <infolog> --out <copy>` first (S31).
- **Handicap**: `Handicap=100` doubles engine income but NOT
  `GetMexSpotIncome` — economics read off spot income must go through
  `Market::IncomeMult()`.

## Lab timing runs on RECLAIM-CORRECTED income (2026-08-28)

`check_lab_timing` judges T2/gantry timing and advanced-plant
serialization. Its income basis is `(d metalProduced - d mReclaim) / d sec`
between periodic BARAI_STATS rows -- Spring's income folds reclaim in, so a
wreck feast reads as a rich economy and both the AI and a naive audit call
a lab "licensed" (apexearth: "Make sure we aren't tricked by reclaim
events"). Every flag prints corrected AND raw so the reclaim share shows on
its face. The bars are the AI's own (apex_t2_metal 30; gantry team ~100 via
apex_gantry_afford_s, host floor 0.6 x apex_gantry_host_inc with a 0.9x
window-vs-EMA tolerance); `gantry-too-late` requires a FED HOST to have
existed, because the host floor holds a poor-split team back by design.
`adv-plant-overlap` counts a second advanced plant requested before the
first finished -- a flag is simultaneous build OR a died first order;
cross-check `finish-before-founding` before treating it as the former.
The AI-side counterpart: dev_team_income publishes cumulative
`apexReclaimM` per team, and `TrackIncome` subtracts the reclaim rate
before its EMA, so gIncEma (every super/lab anchor) and the TV_MINC_NET
team lane are structural income; TV_MINC stays raw for the front budget
and the census share.

## The standing rule

**A reported behaviour is not fixed until a check would catch its
regression.** When apexearth reports a mistake: find the mechanism, land the
fix, and land the check in the same session — plus whatever log line or
gadget field the check needs (the `dashboard-ui` skill covers surfacing new
telemetry). Adding a check = one function in `tools/audit.py`, appended to
`CHECKS`, section named in `Report.show`'s tuple; anchor it on exec lines
and BARAI_BUILD events, not decides.

Companions: `build_timeline.py --window a,b --spec Apex` (exact per-def
build list for any window), `diagnose.py` (front geometry and frame-waste
sweeps), `review.py --control` (the benchmark checklist — see
`bar-benchmark` when the question is "did it help" rather than "did it
misbehave").
