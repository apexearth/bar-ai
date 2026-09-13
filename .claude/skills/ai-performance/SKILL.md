---
name: ai-performance
description: Performance of the apex BAR AI -- the 16-AI frame budget, the instruments (apex_perf, frametime.py, perf sec/jobs/work/sweep lines), the approved fixes (time slices, caches keyed on frame+stamp, grids over sweeps) and the forbidden ones (behavioural caps in a perf costume). Use for any hitch, sim-speed drop, "the game lags", a FAIL verdict, or the periodic performance review apexearth asked for.
---

# Performance — the budget, the instruments, the review

apexearth 2026-09-12: *"We should have a special agent or skill dedicated to
performance in this AI. It is an easy problem to run into so we frequently have
to resolve performance issues."* This is that skill. It is a **procedure**;
the mechanism lives in `perf.as`, `tools/frametime.py` and the commits below.

## The budget (his ruling, 2026-09-05)

Sixteen of these AIs in an hour-long game, never below 1x. 1x is 30 sim
frames/s, so the WHOLE frame — engine sim, pathing, every AI — fits in
33.3 ms, and the AI's working share of that is 20%:

    <= 0.417 ms per AI per sim frame, at the WORST game-minute

`frametime.py` prints the verdict (PASS/FAIL, and how many times over). First
PASS: `ad82faac`, 0.412 ms. Anything that reads FAIL is a bug in this AI, not
a property of the map.

The lag budget is also a **behaviour**: `Perf::` measures sim speed against
wall time and `gLagSev` thins slices under load (memory: lag-budget-ruling —
"spreading AI work over more frames is approved; slower orders beats a hitch").
That ruling licenses **time slices, not behavioural caps**.

## The instruments — read these, never "it feels smoother"

```bash
python tools/frametime.py <run>        # ms/frame per game-minute, AI share, worst spike,
                                       # per-section table, growth table, 16-AI verdict,
                                       # worker pool, map rebuild, sweep counts
python tools/review.py <run>           # gate 1 first: a crashed/compile-failed run has no perf
```

`run_match.py` passes `apex_perf=1` by default (`tools/run_match.py:424`). The
lines it produces, one per game-minute per player:

| line | what it is |
|---|---|
| `apex: perf AiFrame calls= totalMs= avgUs= maxMs=` | the WHOLE AI per player — this is what the verdict divides |
| `apex: perf sec <name> calls= totalMs= maxMs=` | script sections wrapped in `Perf::T0()/Add()` (127 of them: `dec.*` decide, `want.*` proposers, `exec.*`, `up.*` AiUpdate passes, `hk.*` hooks, `front.*`, `prot.*`, `post.*`, `xw.*` executor batches) |
| `apex: perf jobs (ms/calls/maxMs)` | the C++ scheduler jobs — ~87% of aiMs at hour scale (`575b814a`) |
| `apex: perf work (...) qavg= qmax=` | the SHARED worker pool (threat/influence/enemy rebuilds, every path query); NOT in aiMs, comes out of the engine's sim thread; `wait=` is queue latency |
| `apex: perf sweep <helper>=elements/calls` | how much WORK the O(n) helpers did |
| `apex: perf map t= ...` | element counts of the per-ally-team map rebuild |

**The batching signature: a section whose `maxMs` is many times its `avgUs`.**
That section does N things in one frame. Lowering its frequency makes the
spike rarer, not smaller (CLAUDE.md). The fix is a slice.

- `python tools/hitch.py <run>` -- the largest wall gaps between consecutive
  infolog lines, the frame period they sit on, and the line before and after.
  The instrument for a freeze that `frametime.py` reads as clean (S31).

## The benchmark

Perf is judged on HIS setting at scale, not on a 2v2:

```bash
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Greenest Fields" --per-side 8 --sides Cortex,Cortex --boxes lr --box-size 0.1 \
    --handicap 100 --minutes 60 --seed 1 --write-dir matches/_engine_perf
python tools/frametime.py matches/<that run>
```

Uncapped, so the sim runs as fast as the CPU allows and the AI's think budget
is what it would be for him. **Nothing else on the machine while it runs**
(S29: an uncapped game under load measures the CPU, not the tree). Same map,
same seed, before and after — the arc in `ad82faac` was measured that way.
A 1v1 or 2v2 cannot FAIL this verdict and proves nothing about it.

## The approved fixes, in the order to try them

1. **Slice it.** A periodic pass over N things is N/frames per frame:
   `units/120 + 1` per frame instead of `units/15` every 8 frames
   (`011f3b04`). The facqueue batch loop stops at `BATCH_SLICE_US` and resumes
   next election (`facqueue.as`). `FacYardWatch` does one line per call.
2. **Cache on an exact key.** `(ai.frame, gOwnStamp)` is exact for anything
   that reads income, ownership and the pull tracker (`ArmyTargetFull`,
   `OwnConvCellCeil`). A 5 s clock (`DenserConvCapE`, `PoolFill`) is fine for
   a census. **S20: a latch-once cache is a decision about WHEN** — never cache
   a first reading forever.
3. **Replace the sweep with a structure.** `ComNear` grid over the ledger,
   `NanoNear`/`gNanoGrid`, the reach cache. The `perf sweep` line says which
   helper is doing the work; a sweep whose elements/call grows with the base is
   the next O(n²).
4. **Hoist loop invariants** out of per-candidate loops (the claimer fleet,
   `bpProt`, `LineBuildPower` taken once per batch — all measured, all in
   `production.as`/`facqueue.as` comments).
5. **Then C++** — the jobs and the worker pool are most of the cost at hour
   scale (`208a82b3`, `e6e842c7`, `575b814a`). `cpp-dll` skill.

## The forbidden fixes

- A behavioural cap ("only consider 20 candidates", "skip defence every other
  election", "no more than N nanos") is not a perf fix; it is policy, and
  policy is his (docs/26). If the arithmetic says edits cannot get there, say
  so and propose the restructure — that is approved.
- Turning a section off "because it's slow". Measure what it decides first
  (`deadcheck.py`); a section that decides nothing is deleted, not silenced.
- Lowering a frequency to hide a spike (see the signature above).
- Reading the verdict off a loaded machine, a capped sim, or a small game.

## The review (what he asked for: periodic "performance review and fixup")

1. `git log --oneline -S"Perf::Add" --since=<last review>` and
   `git log --since=<last review> --stat -- ai/Unstable cpp/src` — what was
   added since; every new periodic pass and every new O(n) helper is a suspect.
2. Run the benchmark above, twice if the first is within 10% of the line.
3. `frametime.py`: verdict; the ten largest sections by totalMs; every
   section with maxMs > 20x its avgUs; the growth table (which sections scale
   with minute/units); the worker-pool wait; the sweep counts.
4. For each suspect: find its log line, prove it fires, prove what it decides
   (CLAUDE.md "instrument first"), then apply the fixes above in order.
5. Re-run the SAME map and seed. Report per-AI-per-frame before/after, the
   worst spike before/after, and the per-section table for what you touched.
   A change that did not move the number is reverted, not kept as "cleaner".
6. Record the arc in the commit message (as `ad82faac` did); the verdict line
   goes in `docs/27` only if a default changed.

Previous reviews, for the arc: `208a82b3` (worker pool seen), `e6e842c7`
(order census closed), `011f3b04` (idle pass sliced), `ad82faac` (first PASS,
0.412 ms), `575b814a` (7% off per unit, first real 16-AI hour).

## Traps

- `apex_perf=1` itself costs: `ai.ClockUs()` on every scope close. Compare
  runs with the same setting; the verdict was first reached at `apex_perf=0`.
- **S12** a duplicate `RegisterObjectMethod` kills the AI at init and the run
  reads as "fast".
- **S13** orders apply late and the lag scales with sim speed; the stuck watch
  (`stuck.as`) measures `gOrderLagMax` — a perf regression shows up there as
  labs being aborted before the engine answers.
- A watched game at 1x hides everything; a 30 ms single call is a visible
  hitch there and nowhere else (`game-audit` PERF section).
- **S31** the AI's clock only sees the AI. A hitch on a fixed frame period
  that no section owns is in the engine or in LuaUI (which headless loads
  too); scan the infolog for wall gaps between consecutive `[t=` stamps and
  check what else logs at that frame. One long `Spring.Echo` line costs
  `gui_chat.lua` the square of its length.
