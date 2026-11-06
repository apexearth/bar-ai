# The seat plan: decide from the top, builders are hands (his 11-05)

His words: "Not even think on a builder level... Alright, these are the resources I have available. Of all the things
I could do, what is it I want to be doing right now? And the answer might just be: only upgrade this one metal
extractor... think from the top down: here's my current state, how does it differ from my preferred state?" And:
"Think big. Think idealism... not confined to boundaries pre-existing."

## Why the election cannot get there

Every constructor runs its own election (Market::Decide) over wants priced one step at a time, then a weighted draw.
Each asks "what should THIS builder do", in gains that carry premiums and network multipliers (a T1 mex at gain=55.96,
nn=21.8). Nothing asks what the SEAT should do with all it has. Measured 11-05: 15 live build requests per seat in a
1v1 (39 mean / 90 peak in his 8v8), 1,200 frames never finished in one 8v8, help priced at a median 0.001 of the
start that won. The ETA ladder (eta.as) already plans the economy top-down every 5 s -- and is only consulted to pick
which eco want represents the economy in each builder's draw. The plan exists; nothing follows it.

## The ideal

One planner per seat (later per team -- "team thinks as one") owns the seat's resources and decides the work; builders
and turrets carry it out.

1. **State.** Metal and energy: income, bank, storage, pull. Build power: every mobile builder (BP, position, speed,
   what it can start) and every turret (BP, reach). Every job in progress: def, position, remaining metal, energy and
   build work. The spend shares the target names (army, defence, air defence, economy, build power; budget.as).
2. **Jobs.** Frames in progress, priced on what they STILL need: sunk metal is gone, so a frame half built pays back
   on half its bill and ranks ahead of the same building fresh -- finishing what we started falls out of arithmetic,
   with no rule. New economy jobs from the ladder's pool (claims, upgrades, generation, conversion, build power),
   at catalog gains in metal/s (DPowerOf), never market gains. Defence, air defence, sensors and plants keep their
   proposers' order inside their own kind.
3. **Which kinds get resources now.** The target's spend shares, as the build-priority pass already uses them (his
   11-05: "always distribute resources evenly based on the target, such as percentage of spend"): a kind under its
   share is open, a kind over it waits. Within economy, one currency: seconds of the binding feed per metal/s added,
   `max(remaining metal / metal feed, remaining work / build power) / gain`, over survival -- the ladder's own key.
4. **The plan: admit in order until the resources are spent.** Walk the ranked jobs; each takes build power up to
   what the metal feed can keep lathing on it (its draw is BP x cost/buildtime) and what can physically reach it in
   time. Stop admitting when the feed or the build power is used up. The plan is usually short -- often one job --
   and that is the point: everything on one extractor upgrade, then the next.
5. **Dispatch.** Each builder goes to the highest planned job it can serve: help a frame that stands (any hand can
   lathe it), or found a planned job it can start; nearest first, never one it would reach after the job is done.
   Turrets: high priority on planned jobs in reach, passive on the rest (BAR's priority, lift.as). A builder with no
   planned job it can serve does what the plan leaves -- reclaim, or nothing. Nobody starts what the plan did not
   admit.
6. **Every 5 s, and on events.** Re-plan on the pool's clock and when a job finishes or dies; a builder keeps its
   job while the plan keeps it, so there is no churn.

Rules this replaces without one of them being written: finish in series, not parallel; metal first when metal binds;
no new lab while upgrades wait (the lab is not admitted while the feed is spoken for); help instead of starting; do
nothing when nothing admitted fits.

## Build order

1. Shadow: the plan is computed and logged next to what the builders actually did -- planned jobs, their build power,
   live sites, and per election whether the builder's choice matches its dispatch.
2. Control: an election follows the dispatch (help -> the assist want on that job; found -> the best site the
   proposers give for that def), falling back to today's election only when the plan has nothing for the builder.
3. Bench against v0.5.06 (tools/focus.py: unfinished frames, live sites per seat; income 8-20; scorecard), then a
   watch game for him.
4. Team: one plan across allied seats -- shared frames, the team's metal.

## Measured 11-05 (1v1 vs BARb hard, 24 pairs, plan on vs off, tools/focus.py + bench metrics)

| run | change | live requests / seat | unfinished frames | army | extractors at 16 | income at 12 |
|---|---|---|---|---|---|---|
| plan1 | snapshot admission | 15.2 -> 9.6 | 34.6 -> 27.0 | -41% (t -2.2) | -5.7 (t -1.9) | -7.0 (t -1.6) |
| plan2 | 60 s window, hands land before done, factory assist yields | 16.6 -> 8.4 | 27 -> 28 | -63% (t -2.9) | -4.1 (t -1.9) | -4.1 (t -1.4) |
| plan3 | economy takes only its spend share of feed and hands | 16.2 -> 10.1 | 33.6 -> 29.9 | -34% (t -2.7) | -5.4 (t -2.6) | -4.5 (t -0.9) |

- Focus is real every time: live sites per seat fall 37-49%.
- Expansion is NOT slower: extractor frames started by 16 min 19.0 vs 19.1, finished 16.3 vs 16.5 (plan2). Fewer stand at
  16 because more die: the army is smaller.
- The hands do less: constructors' build output into units -16% and into buildings -13% (plan3, BARAI_LIFE gaveMobileM /
  gaveStaticM) -- dispatch sent every hand to the top job however far. plan4: a hand takes the planned job where its
  time does most good, return per unit of work x the seconds it lathes inside the window after its walk.
- The opening stays the election's until the first factory stands (the first controlled game built no lab).
| plan4 | dispatch by the hand's own return: gain / work x seconds lathed in the window after its walk | 15.2 -> 11.0 | 28.2 -> 26.9 | -31% standing at the end (t -1.5) | -1.4 (t -0.8) | -2.0 (t -0.8) |

plan4, games reaching minute 20 (18 off / 15 on): metal produced 26,414 -> 28,963, army spend 9,598 -> 9,419 (equal),
economy spend 6,178 -> 7,397, metal lost by 30 min 20,416 -> 12,391 (t -1.9). The hands' output is equal again (units
16.4k vs 15.9k, buildings 26.7k vs 27.2k). Next: 4v4 (plan4v4), where his complaints came from.

**plan2v2 (11-06 00:02, 2v2 vs BARb hard, 3 land maps, 24 pairs; plan.as with every spend through the plan, orphans
resumed, q deleted in both arms):** wins 0 -> 4 (t 2.1), income at 8 min 34.3 -> 41.3 (t 2.7), at 16 56.8 -> 66.6
(t 1.7), at 20 68.8 -> 83.0 (t 1.2), metal lost 38,440 -> 27,174 (t -3.3); by 20 min metal produced +8%, army spend
+11%; scorecard vs BARb: damage efficiency 0.84-0.87 -> 0.98-1.06, metal produced 0.92-0.98 -> 1.09-1.22. Live
requests per seat 17.0 -> 11.1. Worse: unfinished extractor frames 29.0 -> 41.2 a game -- next.

**plan4v4b (11-06 00:13, 4v4 vs BARb hard, 3 land maps, 12 pairs, 40 min):** metal killed 51.6k -> 61.8k (t 2.9),
army standing 32.9k -> 43.0k (t 1.7), metal lost 162.6k -> 138.6k (t -1.3), extractors at 16 min 65.1 -> 68.0 (t 1.3);
income mixed (12 min +9.6, 16 min -15.6, both inside noise); scorecard vs BARb equal (metal produced 1.18-1.27 both).

**plan2v2b (11-06 01:21, the plan2v2 setup again, instrumented):** no repeat of plan2v2 -- income at 16 min -13.0
(t -1.6), at 20 +11.4 (t 0.8), metal lost -10% (t -1.1), wins 0 -> 1. Instruments: 1,025 plan switches in 24
games, 961 of them a claim left for another claim (713 at 0%, 198 under half, 50 over half) -- every claim was scored
on the mean walk, so all scored alike and the first in the list took the hand; T1 claims decayed under 10% 4.5 ->
9.8 a game. 712 of 4,238 planned starts were rated by the election under a quarter of its best want. Fix: the job a
hand holds is scored on its real walk and real remaining work and kept while it scores at least the best other job
(12-min 2v2: 6 switches, 21 stays).

**plan2v2c (11-06 01:56, the plan2v2 setup with the stay fix):** AGAINST the plan -- income at 8 min -9.3 (t -2.6), at
16 -15.6 (t -3.0), at 20 -36.9 (t -2.6), army standing -36% (t -2.5), metal killed -26% (t -2.6). The stay fix did its
job (switch lines 1,025 -> 521, T1 claims decayed under 10% 9.8 -> 3.5, off arm 4.0), and by 20 min metal produced
(53.3k vs 53.7k) and army spend (18.9k vs 17.2k) were even. The same comparison across three runs read income at 16
+9.8, -13.0, -15.6: before reading any single 2v2 run, an A/A of this setup (aa2v2) measures how far it swings alone.

**aa2v2 (11-06 02:28, A/A: plan off in both arms, the same 2v2 setup, 24 pairs):** income at 16 min +3.1 +- 7.4, metal
killed +2.7k (t 1.8), metal lost -4.5k (t -1.4) -- single 2v2 runs reach t ~1.8 by chance, and the plan-off arm's own
income at 16 min read 56.8, 75.4, 66.4 and 66.5 across runs: compare arms within a run, never runs. plan2v2c's -15.6
(t -3.0) is beyond that. Its cause: the stay returned before the yields, so a hand holding any plan job never stepped
aside for a lab, a factory or defence under its share (factories spend 5.5k -> 4.2k by 20 min). The stay now comes
after them. Next: plan2v2d, 48 pairs.

**plan2v2d (11-06 03:04, 48 pairs, stay after the yields):** the plan is NOT better in 2v2 yet -- income at 12 min
56.5 -> 48.1 (t -2.3), at 16 -7.5 (t -1.3), army standing -29% (t -1.8); better: jobs failed -11% (t -1.9), metal
lost -12% (t -1.4), live requests per seat 17.6 -> 8.7, damage efficiency vs BARb 0.90-0.96 -> 0.96-1.02. By 20 min
metal produced -2%, army spend +3%, economy spend -7%, factories -13%. Suspect: economy jobs held to the economy's spend
share of the HANDS as well as the metal (~45% of build power), the rest left to the election. Next (plan2v2e, 48
pairs): all hands to the plan, the metal share kept.
