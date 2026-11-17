# v0.5.14 review findings left for the next version

Reviews of 11-16 (three rounds on the Unstable diff since v0.5.13). Must-fix items were fixed before the rc9 gate;
these were left because the gate was running on the final code, or they cost time without changing behaviour.

1. **A held long-range gun idles after its kill** (brain/lrpc.as, CSuperTask::Update). The director's hold
   (`scriptFree`) stays set after the target dies, so the gun waits for the next look: 10 s on a building focus, 3 s on
   an army. Before the director, C++ re-aimed every TARGET_DELAY. Fix: look every 3 s while any gun is held, or let
   C++ step aside only while the gun still has a command queued. Also: a held gun whose new `CmdAttackEnemy` fails
   keeps its old order (let it go instead).
2. **Arrival weight jumps after a small first arrival** (market/protect_measured.as DefMeasuredStep). The first
   arrival of the game (or after ~4.6 tau quiet) gets w=1 and sets the mean to its own size: a 30 m scout then a 600 m
   raid gives w=20 near that spot for about one tau. Unbounded. Check rc9's early defence spend; a fix needs a scale
   that does not come from the arrivals alone (ask before inventing one).
3. **Arrival logs count every pacing swing** (`arrivals=`, `arrM` are unweighted). No tool reads them yet.
4. **DmAdd eviction** compares the weakest entry with 1, not with the new weight: a tiny pacing arrival can evict an
   entry worth up to 1.
5. **GetFriendlyCostIn per candidate** in the focus cell, before sorting: ~100 engine queries every 3 s against a
   100-unit army. Stop once every gun has a target.
6. **Sensor spacing ignores nanoframes** (BuilderTask.cpp SitePredicate): two concurrent radar tasks, or an ally's,
   can still land adjacent. Excluding only this task's own target would keep them apart. A def that is both radar and
   jammer is spaced against jammers only.
7. **Jammer site cache thrash** (perf): the jam site lookup can run two engine searches per election.
8. **Lean 2 also reaches an ATTACK squad's own regroup and fall-back moves** in contact (they lose the per-second
   re-path). Watch the stuck counter.
9. **Constructor claim split** (production.as, openrace.as): the reviewer asked whether the spot-race value is now
   discounted twice for a seat with many claimers; unmeasured.
10. **A stream held at a steady level counts as one arrival** (enemy replacing what our towers kill). A high-water mark
    cannot tell replenishment from pacing; enemy ids new to a probe could.
11. **The near-done strips check is a raw count** (tools/contract.py near_done_stripped): it grows with how much a seat
    builds, so a seat that out-builds the release fails it (rc10: 17.1 vs 10.7 on 290k vs 223k metal built; per 10k
    built 0.59 vs 0.48, rc9 0.47 vs 0.52, rc8 0.42 vs 0.50). Ask him before changing it to a rate: it gates releases.
