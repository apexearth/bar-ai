# Performance: what is open

Budget: 0.417 ms per AI per frame at the worst minute (`ai-performance` skill).

## v0.5.01 fails the 16-AI budget; his online seats cost 2-3.5 ms a frame (2026-10-31)

Skill benchmark (Greenest Fields, 8 Apex v0.5.01 vs 8 BARb hard, +100, seed 1, uncapped): 0.718 ms/AI/frame
(min 25, Apex won at 33 min). The same code on the same seed: 0.386 PASS (lost at 30), 0.581, 0.874 (won at 43,
3,474 units). One run cannot carry the verdict: the outcome and the unit curve change run to run.
His 10-31 hosted game (3 seats on his machine, apex_perf off): 2.6 / 3.5 / 3.1 ms per seat per frame at the worst
minute, bldIdle 2-4 s a minute per seat; lag ladder up 19-20 of 33 minutes, up to 65-110 builder sets queued,
election wait median 1.3-9.6 s, worst 200-320 s. Builder AiMakeTask calls run 1,000-2,500 a minute a seat
there against ~170 in the benchmark: the benchmark does not load the AI the way his games do.
- Spikes: LatheSiteRaw is 99% of the >=30 ms AI frames in a won benchmark (gantry, T3 plants, converters, fusions
  in a packed base; ls.raw up to 37.7 ms, ls.find 13 ms, ls.room 21 ms) and the top tag of his spikes.
  PlotSearch did the same (up to 35 ms) and is sliced now. In C++, a failed FindBuildSite (apex: site-fail,
  r=1600) is searched twice (BuilderTask.cpp FindBuildSite, selfClear then 0) and coincides with a third of his
  >=40 ms frames.
- The benchmark runs work releases do not: up.facexit (apex_perf only, 4.7 s a game) and dec.nnrec (apex_nn_record).

## His +100 scav 8v8 fails 4x (2026-10-18)

Solo run (matches/perfsolo/base-s32; 8 Apex vs 8 BARb hard, Comet Catcher Remake, +100, income x2, scav units):
1.771 ms per AI per frame at min 20, 4,537 units; the engine is 75-85% of the late frame. Builder elections are
~55%: hk.maketask.builder 155 s, job:bldIdle 143 s, bld.decide 40,581 decisions at 2.6 ms; elec-slice asks 3-4 ms
a frame for 50-60 constructors a seat, oppFlips ~1,000 a minute on one seat. Fewer cons was tried (a third fewer,
eco not better; deleted 11-04).

Memo census (matches/memocensus-w4, 18 min): 30,293 hits against 41,366 misses -- ownership/position 25,336, empty
or evicted 11,896. A proposer's key carries the asker's cell and hands move between elections. Widening the rows
4 -> 16 gained nothing. The fix is structural: memo the asker-independent part of a proposal (candidate scan, site
search -- pw.cands, prot.loop, plant.lathesite, sense.*) and re-price only the walk per asker on a hit. Biggest
first: want.protect 17.6 s, want.plant 17.6 s, want.sense 13.2 s, want.nano 12.4 s of a 27-min game.

## Smaller open items (2026-10-01 .. 10-18)

- Every allied seat walks the same enemy registry in FoeMemStep (~0.45 ms a tick, 1,500 enemies); sharing it
  within an ally team is the next large cut.
- Benchmarks here read machine stalls as AI cost: read the C++ job rows before believing a FAIL.
- `sync_cpp.py pull` finds no merge base between barbarian-apex and apex/barbarian since the 10-16 restore, and
  0003-cumulative.patch is stale.
- The lag ladder starves builders when the sim trails the asked speed (10-03, `tournaments/cadence-fast2`): at
  --speed 5 the slice falls 8000 -> 417 us, worst builder wait 70-150 s. Benchmarks pass apex_lag_speed=0.
  His call: a watched game at 10-20x the machine cannot hold reads as host lag the same way.
- Judge memo changes on a 1v1 battery, not eco-only: a global memo refresh cap starved the nano proposer
  (10-01) and only a fight showed it.
