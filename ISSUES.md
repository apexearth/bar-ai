# Open issues — what is wrong with this AI right now

Each entry is a thing that is still WRONG, with the evidence for it and, where
known, the mechanism in our own code. Add to it rather than re-deriving the same
complaint next session.

What does NOT belong here: anything whose fix has been measured and confirmed.
That goes in the commit message, next to the diff, and the entry gets DELETED —
not marked FIXED and left to accumulate. `CHANGES.md` is frozen; git history is
the record of what was done, `USER-FEEDBACK.md` the record of what was asked
for, and this file only the open list.

Pruned 2026-08-30 from 2,637 lines. Everything dated 2026-08-27 or earlier was
dropped: those entries are campaign notes from before the wall revamp, the brain
market rework and the perf campaign, and the code they describe has been
rewritten under them. `git log -p -- ISSUES.md` has all of it if a claim needs
its provenance.

## 2026-09-08 — SENSE: the radar want is elected thousands of times and executed once in thirty

Supreme Isthmus 1v1 +100%, 33 min, `roles-h100-t` t002: 2,775 sense elections
won, 84 executed, `apex: exec-refused ... sense=2052`; of the advanced radars
that did become tasks, 21 of 24 died `unreach-safe` (`corarad done=3
abort=21`). Same shape with roles off (`roles-h100-c` t002: 872 sense wins in
the last ten minutes, `corarad done=4 abort=6`). His first game of the day had
417 `sense/sense:armrad` decides, `armrad done=18 abort=30`.

Couplings law 3: a want the executor refuses must not be ranked. The sense
want passes its gates (`GATE_RADAR_GAP`, `_FRONT`, `_HOT`) on a site the
request layer then refuses or the builder cannot reach safely, and nothing
closes the demand, so every free hand re-elects it. Under constructor roles
this became half the split of need at minute 28 with 41 hands holding the
sense role (fixed the same night: a role is released when its category is
refused at execution -- `fell=` on `apex: roles`); the churn itself is not
fixed. Read `Requests::gLastWhat` on the refusal before pricing anything.

## 2026-09-08 — NANO: the lines starve while turrets go up at the sinks; the batch cannot open

His game (Supreme Isthmus 1v1, +100%, 33 min): 116 nanos finished, and the
neediest factory line held 10-50 m/s of lathe against 100-330 m/s of unserved
spend from minute 22 (`apex: nanowant line= lathe=`). At the same settings on
the lane a game finished 436 nanos and aborted 332 (`cornanotc` in
`task-gone`), 264k metal, 12.4% of spend -- the most of any def.

Three measured pieces, none fixed:

- **The batch cannot open.** `apex: nano batch want= ... ask/got/fold/ref`:
  the lattice walk finds the cells (317 of 380 asked over 8 games) and
  `Requests::Take` returns an EXISTING task for nearly all of them
  (`fold2..7/ref0`, every batch): 13 requests opened of 328 wanted. Not the
  join-near fold -- `JoinFor` refuses defs under `JOIN_MIN_COST` -- so it is
  `CoverFor`/adopt-orphan or `frame-standing`. Trace which before touching it.
- **Execute re-derives the site.** Its sink loop runs after the want chose a
  line, under the same law, so a full bank sends the turret to a frame. Making
  execute honour the want's site (`w.spotId` NS_LINE/NS_ARMY, tagged now) was
  tried 2026-09-08 and REVERTED the same evening: the NS_ARMY site
  (`AnyLineSite`) named ground a land con could not reach -- 52 of 75 nano
  tasks died `unreach-safe` in 23 minutes against 2 in the earlier game, the
  election churned (89 buildpower decides in 12 min against 23) and the
  economy fell to 12k built at minute 12 against 22k. Honouring the site
  needs a reachability test on the named line first.
- **The gantry has no nanos** (apexearth, watching 2026-09-08). While it is a
  frame it is a sink (`nano-to-sink at corgant`); once standing it competes as
  a line on unserved spend, and a gantry's spend is bursty.

## 2026-09-08 — T1 converters stand until they die; the obsolete-reclaim market barely fires

apexearth, watching: "We have a lot of fragile T1 energy converters which
should be reclaimed to make room for better things." `want_reclaim.as` exists
(`reclaim/reclaim:armmakr` 14 decides in a 33-minute game, 124 built) and
prices retirement; measure why it loses before pricing it higher.

## 2026-09-08 (night) — The canon economy scenario: where we stand against his curve
- **The canon-driven commit (950094b5) regressed the real-game batteries, and
  the cause was the hands-share multiplier on constructor demand.** Carrot at
  30, ours vs BARb hard: t3 282 vs 228; t4 219 vs 215; t5 213 vs 248; t6 (hands
  term out, converter ticket in) 272 vs 259, cons at 20 13.1 (t5 7.8). Isthmus
  t4: 147.5 vs 224.3. t4 was a mixed sweep (S19: production.as redeployed at
  12:37 into a battery started 12:30) and t5 ran the gate it was labelled as
  lacking -- the deploy mtimes say so; classify a battery from its deployed
  tree, not from the session's intent. In real games EtaHandsShare read 0 in
  most elections (60-195 con-floor log lines per game at hands=0.00), so the
  unspent-metal term bought nothing. Still open from the canon: the lab pumps
  constructors into an energy stall (minute 8: lab 287 + nano ring 278 of
  845 e/s), and the con floor's energy-throttle discount was bypassed while
  metal wasted -- reverted; whether a stalled factory should pause is his call.
- **The canon's minute 4-10 energy stall was self-inflicted three ways** (all
  read off `apex_efloor_diag=1` + the DLL's `apex: strand` census, 2026-09-08):
  the stall answer counted in-flight generators as feed (each crawling advsol
  frame made the next price as if it already ran: 30/69/82 advsol picks a
  minute at a 0-6% bank); the stall deficit credited in-flight make and read a
  deep stall as covered; and `ConsolidateEnergy` (his "focus on the most
  efficient energy project") scored frames by a time-to-energy with no energy
  bill and stripped whole crews, including the last hand -- the engine deletes
  a zero-progress frame the moment no one lathes it: 33 solar frames destroyed
  at 0.00, 293 consolidations in twelve minutes. Fixed: feed without in-flight
  make, live deficit, TTE with the energy bill (EStretch), never the last hand.
  12-min canon: solars at 8 6 -> 16, e/s at 12 1,899 -> 4,044, waste 14.9k ->
  9.5k, strands 17 -> 0. The "walks longer than it lathes" rule for the stall
  hoist was WRONG on Carrot: it declined 416 hoists in 12 games, energy
  executions per game fell ~110 -> ~73, stalled share at 20 doubled (12% ->
  24%), metal wasted by 30 10.1k -> 27.8k (carrot30-t7 vs t6) -- on a 24x24
  map every claimer walks longer than a solar lathes, so it declined everyone.
  Reverted. t8 (per-frame idle pass, rule in) 243 vs 276 at n=7; t9 (rule
  out) 191 vs 249 at n=7, waste 27.4k, 0-5 wins, 73% of produced metal spent
  vs BARb's 87%. So the rule was not the cause: t7/t8/t9 all waste ~27k where
  t6 wasted 10k, and the difference is 699e5f68's pieces (stall feed, live
  deficit, energy-aware TTE, last hand, UnspentByHands) -- each proven on the
  canon, none yet on Carrot. t10 = HEAD (walk charge + two-currency pool) on
  top; if waste stays, bisect 699e5f68 starting with UnspentByHands (no canon
  evidence either). The held finishes were the DLL idle pass batching ~10
  elections into one frame every 8 frames -- fixed in 011f3b04 (held 363 -> 0).
  **t10 (cb57923d: walk-charged first move + two-currency pool): 307 vs 256 at
  30 (n=10), 132 vs 123 at 20, 46 vs 37 at 10; produced 184k vs 162k, spent
  90% vs 84%, waste 7.1k, e/s 10.0k vs 4.1k, mexes 106 vs 87, wins 2-0.** The
  first arm ahead at every mark. t11 (same tree): 325 vs 267 at 30 (n=8),
  112 vs 150 at 20, 43 vs 36 at 10, produced 170k vs 169k, wins 2-2. Two
  batteries ahead at 30 by ~20%; minute 20 is not resolved (132/123 then
  112/150).
- **Late constructor idle in the canon was an election livelock, not pricing.**
  Census (`apex: elec-slice`): minute 20 done=0, lapse-dropped 1,581, queued
  568. The 8 s ELEC_LAPSE was shorter than the engine's idle-pass revisit
  (measured 4-13 s late), so every sliced set expired before its builder came
  back to collect it. Lapse now derives from the measured revisit period;
  idle 41% -> 17%, elections at minute 20 0 -> 740. The finish was also held
  behind the pump's steps (held=189/min once the lapse stopped): the finish
  is budgeted against finishes only. Remaining: `hk.maketask.builder` is still
  ~0.7 ms a call; the idle pass itself (`job:bldIdle`) is the revisit clock.


apexearth's reference (Comet Catcher Remake 1.8, +50% bonus, vs inactive AI,
`tools/canon.py matches/_replay-canon`): minute 10 352 m/s / 4.8k e/s, minute
16 1,567 / 86k. Ours, same map and bonus, `apex_eco_only=1`, `--speed 5`,
minute 10 and 16 (m/s / e/s):

| tree | min 10 | min 16 | min 20 |
|---|---|---|---|
| with military, HEAD of the morning | 43 / 200 | 88 / 571 | 120 / 1,272 |
| economy-only switch | 96 / 1,390 | 236 / 7,463 | 366 / 12,0k |
| + hands sized by the ladder, T2 priced without an army mandate, upgrade credit only for hands that can build the game's best mex, stuck watch spares on-site builders | 104 / 1,344 | 293 / 9,127 | 744 / 20,7k |
| + factories idle when no rung waits for hands | 121 / 2,172 | 400 / 14,0k | 925 / 35,5k |
| + the ladder's energy-feed arm | 129 / 1,828 | 446 / 13,8k | 884 / 34,5k |

Still 3x behind at minute 10 and 3.5x at 16. What his curve has that ours
lacks at minute 10: 15 mohos (ours 2), 62 nano turrets (17), 2 fusions (0),
6 advanced converters (0); his T2 lab stands at ~5.5, ours at 6.7-7.2 after
a 15,000 E bill on 300-500 e/s of income. His hands stay 6 T1 + 4 T2 + 10 air
for the whole game; ours run to 80 T1 + 72 T2 + 209 air by minute 20 (the
hands gate reads some rung as hands-bound late; `hands=` is now on the con
floor log line). T1 converters (128) instead of advanced (9): the converter
want priced per metal, where the 1-metal T1 converter always wins -- now
discounted per cell against the best the asker can place (unmeasured).

## 2026-09-08 (evening) — Carrot Mountains at 30: behind on METAL, ahead on energy

New goal: "Refine our economy logic until we out-eco our opponents at 30m in
Carrot Mountain." Baseline `carrot30-base` (HEAD 98f0b3f8, 1v1 vs BARb hard,
12 games, 31 min, `--speed 10` -- the late-order tail at full speed trips the stuck watch, S24):

| minute | n | our m/s | BARb m/s | our mexes | BARb mexes | our e/s | BARb e/s |
|---|---|---|---|---|---|---|---|
| 10 | 12 | 42.7 | 40.2 | 19.6 | 17.9 | 407 | 614 |
| 20 | 12 | 83.0 | 133.9 | 38.8 | 53.1 | 1,479 | 1,605 |
| 30 | 9 | 188.0 | 236.9 | 68.6 | 83.6 | 4,736 | 3,636 |

Metal from mexes at 30 (new gadget field): 171 vs 232. The map has 172 spots;
the sweep marks 98-118 of them risky. Wins 0-3 with 9 timelimits.
Mechanism in t000, minutes 10-25: the energy bank sat at 5-24 of 2,000-4,000
for ten minutes with the METAL bank full, so the hoist fired on 182 of 185
energy elections (`why=estall`, `mFull=1`, deficit 3,200-3,700) and the fleet
executed 136 advanced solars, 29 fusions and 20 solars against 67 mexes.
Energy income rose 295 -> 865 over those ten minutes (BARb 614 -> 1,605 over
10-20) while BARb claimed 14 more spots. On this map the metal-full hoist
trades compounding extraction for generation; on Isthmus the same tree
plateaued on energy instead. The market is greedy in both cases; the ETA
objective (`apex_eta=1`, eta-objective skill) is the designed answer and is
being A/B'd (`carrot30-eta`). Also running: `carrot30-t1` = hoist income bar
removed + generators never retired while energy is short.

- **Same tree on Isthmus (`isthmus30-t3`, 12 games):** minute 14 37.1 vs 49.3 m/s,
  minute 20 86.9 vs 98.2, minute 30 (n=9) 192.6 vs 234.2, produced 114k vs 147k,
  mexes 52 vs 63, energy 5,931 vs 4,421; wins 3-0, nine timelimits. No regression
  against the earlier Isthmus batteries (130-146 vs 141-176) but still behind on
  extraction; the early curve (minute 14) is the gap on both maps.
- **t3 = ETA + hoist/retire/T2-floor: 282.0 vs 228.4 m/s at 30 (n=11), production
  157.8k vs 159.5k, 0 losses.** Behind at 20 (99.9 vs 120.3): the early curve is
  the remaining problem on Carrot; energy 7,898 vs 4,093 says the late game is
  now energy-rich and the metal follows.
- **The ETA objective closes the Carrot gap (`carrot30-eta`, apex_eta=1 on the
  baseline tree, 12 games, all to 30).** Minute 20: 102.8 vs 116.6 m/s (base
  83.0); minute 30: **236.3 vs 232.1** (base 188.0), 99.8 vs 81.5 mexes, 47.8
  vs 19.2 constructors, energy 5,306 vs 3,628, rich-income stall 50% vs 32%,
  no game lost (base 0-3). The shift is our arm's alone (BARb 237 -> 232), so
  it clears the 15% floor. The ladder's pick disagreed with the market's
  almost never in the log sample (`mkt=mex eta=mex`), which says the merge of
  the three eco tickets into one, not the pick, is what moved. Default flipped
  to 1. Open: 48 constructors at 30 is metal in hands that mohos would pay
  more for; the rich stall rose to 50%.
- **Carrot at 30, after t1 (82037166): the gap is mohos and T2 hands.** Minute
  30, n=10: T2 mexes 9 vs 18, T2 constructors 9 vs 13, mex income 163 vs 227
  with our T2 lab up two minutes EARLIER (12.2 vs 14.2). Our T2 cons' executions
  in minutes 12-30: 15 assist, 10 fusion, 7 afus, 7 doomsday, 12 mex upgrades.
  Spend: army 64.7k vs 35.8k, defence 7.4k vs 28.5k, build power 11.2k vs 16.3k.
- **Rascal spam (army side, not touched).** 282 corfav (26 m scout cars) built
  and 247 lost by minute 30 in one game; `prodrank` values it at 18.2M against
  1.9M for the next product (g=472k, p=385). 7.3k metal and a factory's time.
  docs/24 territory; recorded here because it is where economy metal goes.

## 2026-09-08 (late) — ECONOMY at 30 minutes: Altair ahead, Isthmus behind

Goal moved by apexearth: "prove that we out-eco our opponents at 30m into the
game." First 30-minute battery (`eco30-head`, 12 games per map vs BARb hard,
`--minutes 31`, tree = guard fix + stall-by-time-to-cover + fleet-ask):

| map | minute | n | our m/s | BARb m/s | our produced | BARb produced |
|---|---|---|---|---|---|---|
| Altair | 14 | 10 | 24.2 | 14.0 | 11,576 | 8,726 |
| Altair | 30 | 4 | 51.7 | 33.6 | 57,022 | 34,734 |
| Isthmus | 14 | 12 | 33.9 | 36.0 | 15,255 | 11,446 |
| Isthmus | 30 | 7 | **130.2** | **176.2** | 90,795 | 100,832 |

n at 30 is the games that reached it: 9 of 24 ended in a gameover first
(we won 7, lost 7 overall). Isthmus is the open problem: level at 14, 26%
behind on income at 30, with 13,392 metal wasted per game against BARb's
4,254 -- metal overflows while energy stalls 35% of rich-income samples.
Constructor samples idle (new gadget field): 13.3% ours vs 9.3% BARb on
Isthmus; 11.5% vs 15.7% on Altair.

- **Early constructors idle half the time.** Altair seed 0, our first corck:
  61% of samples in minutes 2-4 and 46% in 4-6 held no engine order. Trace:
  elected a solar at 2.2 m, task died 11 s later (`task-die ... why=?`), no
  re-election for 17 s, three more solar elections 2 s apart, then the stuck
  watch found it 720 elmos from its site "still 30s" -- twice more at the
  same coordinate holding a nano and a wind. The engine fires no idle for a
  unit that was already idle when its order was refused, so nothing but the
  30 s stuck watch ends it. Now: a task-holder off its site with
  `CmdQueueSize()==0` for 2 s is re-elected (stuck.as, unmeasured).
  `task-die why=?` was 29 of 80 deaths in that game -- the DLL has no reason
  code for an engine-refused build.
- **Builder idle time in batteries is inflated by the stuck watch (S24, re-measured).**
  Orders arrive at every speed (>98%); a tail lands >90 frames late in 4% of
  orders at full speed vs 0.3% at `--speed 5`, and the watch kills and
  re-elects those (17 kills vs 0 in the same canon). Read idle at `--speed 5`
  or watched until the watch re-issues instead of killing. What IS real: in an 8v8 the
  commander forward cap measured forward-ness against the ALLIED centre, so
  the team nearest the middle refused every want ("blue and light green ...
  weren't doing anything"); now relative to where he stands.
- **The stall interrupt thrashes when its answer cannot execute.** Same con,
  minutes 4-5: interrupted off a 90%-done tower "to answer the energy stall",
  the solar request was refused (log rate-limited, reason unseen), exec fell
  to alternate picks (mex, tower, maw, nano) and the interrupt fired again on
  each 0.00 build -- five interrupts in 500 frames. The startable check
  passed and the request still failed; the refusal reason is the next read.
- **In-flight energy drain was N half-fleets.** `EDrainInFlight` priced every
  ledger row at `EffBP(0)` alone: 2,658 e/s of "drain" on 621 e/s income at
  14 m. Now shares the fleet across rows (unmeasured; battery `eco30-b`).
- **Growth premium is convex in generator size** (`fGrow` 7.1 for an afus vs
  3.0 for a fusion at the same moment) with no arrival-time discount, so
  outside a stall the biggest generator still wins on rate. Not changed.

## 2026-09-08 — ECONOMY: what the e-stall session left open

Measured with `tools/ecotimeline.py` (minute-by-minute, his recommendation)
on 1v1 vs BARb hard, 15 min, 6 games per map. The opening e-stall is gone
(stalled share in minutes 2-6: 28-54% -> 0-8%); these are what the same
instrument shows next.

- **The lab's product drain is invisible between its first order and the
  engine's build delay.** `LineWorking` is `CountQueued > 0`, so a factory
  that has orders but has not started drawing (the DLL's `buildDelay`) is
  neither in `energy.pull` nor in `LineDrainE`. Measured on Altair seed 1:
  `lineE=111` while the lab was framed, `lineE=0` and `pull=6` at 1.0-1.5 m
  with the queue full, then `pull=161` at 2.0 m and the bank at 10. No
  script binding reports whether a factory is currently building.
- **First factory late on Supreme Isthmus.** Seed 1: two light towers at 35 s
  and 1.8 m by `draw` (LLT v=21 over plant 13.7), lab at 2.3 m. The plant's
  price loses ordinary draws to towers and solars in the opening; the cover
  push's `PlantFramed` gate does not apply because these were not pushes.
- **Isthmus still e-stalls 30-50% of samples per bin from minute 8.** After
  the parallel-site commit (eb0a389e) the minute-14 stalled share is 24%
  (BARb hard 13-20%) with the economy 25% ahead on metal produced. The
  timeline says the ladder is not the limit any more: energy income climbs
  ~60 e/s per minute, but pull climbs faster (268 -> 556 e/s between
  minutes 8 and 10, 830 at 13) while the metal bank sits at 60-90%. The
  fleet at 14 min holds 5-9 nano turrets, 6-8 constructors and 1-2 plants
  on 25-40 m/s of metal -- several times the build power income can feed --
  and `energy.pull` is that fleet's UNTHROTTLED ask, so the stall metric
  saturates whenever hands outnumber income. The nano ring is sized to a
  line's appetite (`LineCostCeil`, want_nano.as), not to income; that is
  the coupling to price next (`ai-couplings`). Measured and reverted the
  same day: pricing the hoist's deficit off the peak-held demand
  (`gEDemandPk`) instead of raw pull -- 24.0% -> 36.7% stalled, n=6.
  Untried: the lab's product drain while `LineWorking` (queued but between
  units) is in neither pull nor `LineDrainE`.
  **Split by income (his filter, `ecotimeline.py`):** stalled while energy
  income < 400 is 3% on Altair (BARb 6%) and **22% on Isthmus (BARb 9%)**;
  above 400 both sides sit at 40%. The poor-income Isthmus stall lives in
  minutes 6-10, and in 4 of 6 games the opening plant there is an AIR plant
  (`corap`) pumping Whirlwinds at 4,600 E per 150 metal on 200-300 e/s
  (4-8 bombers by minute 10). `production.as` prices products on metal
  alone -- no energy term anywhere. Billing products for their energy at
  `EPriceCostAt` over the line's build seconds (one helper, six value
  sites) was tried and MEASURED WORSE on the same battery (Isthmus
  poor-income stall 22% -> 28%, metal produced 12,609 -> 11,120; Altair
  3% -> 6%), reverted the same day; the plant choice varies by seed, so
  n=6 cannot separate the bill's effect from which plant was opened. Next:
  pin the plant (or filter the battery by opening plant) before judging any
  production-side energy price; and the gadget's `eAskFac/eAskCon/eAskNano/
  eUseTop` now say who is asking.
  **Isthmus-only, 12 games, split by opening plant** (`isthmus-base`): air
  openings 26.9% poor-income stall, bot-lab openings 16.1%. The
  decomposition names the lab-game sink: 2-3 nano turrets assisting a
  Fast Infantry Bot line ask ~130 e/s EACH (300 of a 555 pull at minute 10
  on 334 income); the air-game sink is the plant itself. Pricing a nano by
  the share of its energy ask the economy can feed (`isthmus-nanoE`, 12
  games) moved the minute-14 stalled share 27.8% -> 22.5% and the
  poor-income share 22% -> 21%, but tripled wasted metal (856 -> 2,587,
  BARb 1,017) with metal produced unchanged -- reverted as a mixed result.
  Then, from his watched game (c8392af6): the hoist bar no longer applies
  with the metal bank full, a nano is worth the share of its energy ask the
  economy can feed, a second big generator is not held when the bank covers
  it, and an energy-costing build's priced duration is stretched by the
  stall's throttle. Isthmus 12 games: poor-income stall 22% -> 19%, rich
  51% -> 32%, minute-14 share 27.8% -> 22.6%, production level.
  Altair regression check on the same commit (12 games): metal produced
  10,839 (earlier batteries 11,335-11,910), income 23.4 (24-34), stalled
  7.1% (8-9%), poor-income stall 8% (was 3%), rich 9% (was 21%); BARb
  8,812 / 16.5 / 5.5%. Inside the spread on production, but the early
  stall on Altair should be re-read after the next change there.
  **RETRACTED 2026-09-08 (S22):** the "supply discount" battery
  (`isthmus-stuck2`, and `isthmus-stuck`, `isthmus-fleetask`,
  `isthmus-fleetask2`) all ran the SAME stale lane snapshot -- the tree of
  c8392af6 -- because a lane named on the deploy line was not
  re-materialised. Their spread, 17.2% / 21.0% / 22.6% / 27.0% stalled at
  minute 14 and 15-21% below 400 e/s, is the noise floor of a 12-game
  Isthmus battery. fd140d87's numbers are that noise; the commit stands on
  its derivation only and is unmeasured, as is the fleet-ask demand (in the
  working tree). `isthmus-base` (27.8%) against that pooled 22% is inside
  the same floor, so the c8392af6 changes are also not resolved by n=12.
  Only the session's first batteries (control 36-38% -> 9-24%) are outside
  it. Any further Isthmus claim needs ~36 games per arm.
  **The geo next to the base, started and abandoned** (his watched seed 12,
  5.2 min): `apex: stuck -- armck held armgeo progress=0.11 toSite=127
  buildDist=130 still 30s` -- the constructor stood 127 elmos from the vent
  (range 130), made no progress for 30 s with both banks full, and the
  stuck detector aborted and re-elected. The abort put the vent on the
  block list (`NearBlocked`), so the next two geo elections went to vents
  3,000+ elmos away and died on the walk, while the 11% frame at home
  stayed orphaned. Why the engine made no progress in range is not known
  (3D range at a cliff vent, or a blocked footprint); the response to look
  at is the block-list entry after a no-progress abort, which is what sent
  the builders away from the one vent that was reachable.
  Still open there: the sense want elects a radar 37 times for 9 built
  (refused "full", re-elected every draw -- a wasted election per builder
  per cycle); and the air-plant opening (Whirlwinds at 4,600 E) remains the
  worst case at 20% poor-income stall.
- **`ECostSpot` and `EPrice` now share one derivation** (flow / energy need,
  flow = min(BPCapacity, income + bank/lookahead)). The old cost-side
  asymmetry ("spending E is cheap at balance, which is what lets advsol and
  fusion be bought while solar-fed") is gone with it. Whether the fusion
  still gets bought at the right time is NOT measured; check
  `techStart`/fusion count on a 30-minute battery before trusting it.
- **Commander idle -- a SECOND cause found 2026-09-08 (S27).** Beyond S24's
  sim-speed lag, the engine flatly discards a build order whose square is
  blocked: `CBuilderCAI::GiveCommandReal` returns before queueing, and since
  the builder never left idle no `UnitIdle` event follows either, so neither
  of CircuitAI's retry routes can fire. The commander is worst hit because an
  in-base build skips pathing, so his travel ends at once and that one
  `Execute` is the only order the task will ever issue. Signature:
  `apex: com-still ... q=0` for tens of seconds with a valid buildPos and the
  site hundreds of elmos away, while `apex: com-exec` shows the AI issuing him
  a build order every ~30 s. `stuck.as`'s `gStuckDeadAt`/`gOrderLagMax`
  recovery (6318a09e) is the right shape for it -- it does not currently catch
  the commander often enough.
  **Not measured honestly yet:** 43.7% of commander samples idle and stalls to
  183 s are BATTERY-SPEED figures and S24 says they are inflated; the real
  number needs a `--speed 1` or watched game, which has not been run.

## 2026-09-06 — THE REZ FLEET IS SIZED TO A STREAM IT DOES NOT CONVERT

Both halves of the demand are honest rates now (docs/27 `TUNE_REZ_HORIZON`
carries the measurement that cleared the repair half) and the servo works: on
the 60-minute 16-AI game `20260906-105022` the fleet tracks `stream/cap` all
game (have 12.3 vs 10.9 at minute 36, 35.4 vs 33.3 at 54). Nothing measures
whether the fleet CONVERTS the stream, and it does not.

Per AI at minute 54: 35.4 bots, nominal capacity 83 metal/s. Realised, from the
stats gadget: `mReclaim` 1,455 metal over 54 minutes = **0.45 metal/s**,
`mRezSpend` 702 for the whole game. `apex: rez-time` per AI per minute: rez
2.5, medic 36, repair 21, salvage 26, against idleRule 78, none 19 and
**frontVeto 692** -- and two of the three `gRzFrontVeto` sites are on DAMAGED
UNITS, so the veto suppresses the repair half as hard as the wreck half. The
slope is fine (halving the fleet across 7331b1d, same map and seed, cost 42% of
the reclaim: 2,524 -> 1,455); the level is not.

`unmet = stream - have x cap` has no term reading realised output, so a fleet
converting 0.5% of what it is sized for still reads as under-supplied -- and
lowering `TUNE_REZ_UTIL`, the estimate that scales the fleet 1:1, would demand
MORE bots. Cost: 542 of the 5,921 units at minute 58 (**9.2%**) for 2.0% of the
metal, the largest units-per-metal line item left; 1,221 of 6,239 before
7331b1d. The fix is apexearth's call: scope the stream to ground the rez rules
permit, divide the repair demand among all repair-capable build power, or teach
the price that the engine charges per unit.

The first of those three is RULED OUT on arithmetic. `have* = stream/cap`, and
`cap` does not depend on reachability, so discounting the repair half by any
fraction below 1 shrinks the fleet in EVERY minute: the repair half is 36% of
the stream at minute 12 and 40% at 54. The crude accept share
`(medic+repair)/(medic+repair+frontVeto)` is 1.00 until minute 9 and 0.03-0.10
from minute 10 on, so the discount bites hardest across minutes 12-24 -- where
apexearth asked for "4 or 5" and the curve gives 3.0 and 5.4. It would take
minute 12 to ~1.5 bots and minute 24 to ~3.2 for ~3.5% of unit count, and add
no realised metal, since the work it stops counting is work the fleet never
did. Scoping the demand honestly is a statement that the VETO is wrong.

`RezSiteOk` is `!InEnemyReach(site)` and nothing else (`BehindLine(site, true)`
returns true on its first line): refuse any ground an enemy weapon covers,
which is the whole battlefield. `docs/24-how-units-fight.md` asks the opposite
-- rezbots "repair the screen mid-fight", "eat their wrecks... the battlefield
is the richest reclaim on the map" -- and the survival rule he gave is
POSITIONAL: stand behind allied units, "back away when enemy units are close to
being within range". His file outranks the code, and the DLL guard agrees the
fleet lives inside that envelope (`apex: rez-guard`: 56,633 pressed, 17,970
forced walk-outs).

There are FOUR `gRzFrontVeto` sites, not three -- `rules_rezzer.as` medic,
salvage and repair, plus `reclaim.as` `EnqueueWreckReclaim` -- two on damaged
units and two on ground, lumped into one counter, so the repair stream's own
share was not measurable. `hurtOk=`/`groundOk=` on `apex: rez-time` now carry
accepted/tested per stream, biased optimistic (a candidate beaten on distance
is never tested, and those are the farther, more forward ones). One 16-AI hour
turns the bound above into a census.

## 2026-09-05 — ENGINE COST WE CAUSE: 52k move orders/min, and two mechanisms behind them

Not our frame time — the engine's, which is 30.93 ms of the 37.56 ms frame at
minute 59 of a 16-AI hour. Read off `dev_order_counter.lua`, summed over 16 AIs:
min 59 total 92,990/min = **51.7 orders per sim frame**, move 52,255, fight
19,628, other 13,827, patrol 3,273. Builders are NOT in it (build+repair+reclaim
+guard+stop together are 4,007). Static reading of the emitters, no run yet:

**1. Every re-issued move whose point moved at all costs a full path request.**
`CMobileCAI::ExecuteMove` guards `SetGoal` with
`!moveType->IsMovingTowards(cmdPos, GetGoalRadius(0), false)`, and
`CGroundMoveType::IsMovingTowards` is `goalPos == pos * XZVector && goalRadius
== radius` — **exact float equality**. So a bit-identical repeat is already free
in the engine, and anything else runs `StartMoving` → `ReRequestPath(true)`.
`ISquadTask::Attack` recomputes a standoff point per engaged unit **every second**
(`isRepeatAttack = frame >= attackFrame + FRAMES_PER_SEC * 1`, shortened from 3s)
from `LeadPos` + an orbit angle + a threat veto — a point that is different every
time by construction. That is one path request per engaged unit per second,
16 AIs wide. `IFighterTask::DodgeFire`/`KeepRange` add a second one per unit under
fire, on their own 1 s cooldown, and the two overwrite each other.
The `apex: orders` / `apex: order-rep` census now in `CircuitAI.cpp` measures the
size of this: `move same/lt8/lt32/lt128/far`. Everything past `same` re-paths.

**2. `CmdSetTarget` enrols the unit in a synced Lua loop that never stops.**
`unit_target_on_the_move.lua` blocks the command (never reaches `CCommandAI`) and
keeps the unit in `unitTargets` until the target dies or leaves radar+LOS. Every
5 frames — 6×/second — it walks that whole table and runs `setTarget`, which calls
`spGetUnitWeaponTryTarget` per weapon plus `SetUnitTarget` plus four
`SetUnitRulesParam`, all synced. This cost scales with the number of units HOLDING
a target, not with our order rate, so at ~5,700 units it is a standing per-frame
tax that `apex_prefer_target=1` created. It is also very likely most of
`other=13,827/min` (each repeat rebuilds the gadget's table and sends an
unsynced message). `dev_order_counter.lua` now prints `othNNN=` raw ids so the
next run names it instead of guessing.

**3. fight went 2,798 → 26,368 between min 30 and 50 while units grew ~2x.** The
likely mechanism is a BRANCH change, not a superlinear loop: `ISquadTask::Attack`
sends 1 move + 1 set-target on the standoff branch, but 2 fight orders + 1
set-target on the `rowBrawls` / `staticCantReply` plain-attack branches, and mid-
game is when squads start pressing static defence. The census splits FIGHT from
ATTACK, which confirms or kills this in one run.

None of the three is measured yet. The instrument shipped 2026-09-05; a 16-AI
hour with it is what settles the sizes.

## 2026-09-06 — the move census cannot name the loop, and the arc tiebreak reverses whole rows

Four 16-AI hours on Supreme Isthmus v2.1, seed 1, all 976 `order-rep` lines
(16 teams x 61 min) summed:

| run | move | reps | same | lt8 | lt32 | lt128 | far |
|---|---|---|---|---|---|---|---|
| 06:23 | 1,638,177 | 979,421 | 20,276 | 44,922 | 182,152 | 214,701 | 517,370 |
| 07:06 | 1,137,674 | 442,782 | 17,063 | 10,940 | 33,852 | 48,572 | 332,355 |
| 07:54 | 1,124,169 | 503,898 | 31,470 | 7,918 | 28,623 | 51,415 | 384,472 |
| 08:50 | 1,064,897 | 465,995 | 53,654 | 9,443 | 29,169 | 43,472 | 330,257 |

Move volume fell 35% across the session under other work; `far` is now 71% of
repeats. `dev_order_counter` agrees on the total (move=1,123,923 at 08:50), so
the AI is essentially the only source of move commands.

**The census cannot attribute any of it.** `NoteOrder` buckets a repeat only when
`opts` and `id` match the previous order of that kind, so two sources alternating
on one unit register as no repeat at all: `CMoveAction::Update` alternates RMB and
RMB|SHIFT and therefore contributes ZERO to the histogram, and `DodgeFire`/
`KeepRange` (opts 0) alternating with the squad ring (opts RMB) likewise. Every
rule aimed at the number has been a guess. `apex: order-src` (2026-09-06) splits
sent / repeat-within-3s / far-repeat by call site — ring, travel, dodge, standoff,
post, retreat, build, scout — and one 16-AI hour names the loop.

**The arc-end tiebreak reverses a row's whole slot assignment.**
`ISquadTask::Attack` picks between two mirrored ring ends and, when it picks the
second, does `delta = -delta; beta = -beta`. That maps unit i from angle
`alpha + d*(i - n/2)` to `alpha + d*(n/2 - i)` — its mirror about alpha. At the
arc cap (`maxDelta = 0.9*PI/n`) a four-unit row's outer units swap across ~2.8 rad,
a chord of ~1,200 elmos at r=600: n `far` move orders and n units walking past
each other for a formation that occupies the same arc either way. It is decided
against `testPos`, the row's first unit, which is orbiting, while `newPos1`/
`newPos2` are built from `alpha + beta` with **neither the orbit term nor
`wrapAlpha`** — so the comparison reverses on its own as the ring precesses, with
nothing tactical changed, and the threat sample that picks the "safer angle" is
taken at two points no unit is going to. The stated intent in that code is
already "so a squad does not zigzag between two near-identical tiles".
`apex_arc_sticky` (default 0) holds the row's chosen side against the DISTANCE
tiebreak only — a threat asymmetry still re-decides — and `arcflip=churn/held` in
`apex: order-src` counts it with the switch off. The `newPos1`/`newPos2` phase
mismatch is NOT fixed: fixing it changes which side squads approach from.

**Do not suppress the orbit re-issue.** `ORBIT_RATE` 0.18 rad/s is 108 elmo/s of
slot travel at r=600 and 153 at r=850 — faster than a Sheldon walks, so the ring
is a heading, not a destination. Holding the order would leave the unit standing
at its slot, against `docs/24` ("almost always stay moving", "circle around the
enemies they are shooting"). The cadence is not the bug and neither is the orbit.

**`work:areas` is not the problem.** `CTerrainData::UpdateAreas`, 6 calls/min
(one per 10 s, whole process, not per AI), 35.9 ms avg / 39.7 ms max — but
`waitMs 0.0 / maxWaitMs 0.0`: it never queues and nothing waits on it. Its
main-thread partner `CTerrainData::EnqueueUpdate` (the heightmap + slopemap copy)
is `terrain=7.7/6/1.3` — 1.3 ms every 10 s. 0.34% of one core, off the main
thread. Leave it alone.

## 2026-09-05 — Utilization() is blind to factories, so an idle gantry does not discount the next one

apexearth: *"we have a lot of gantries which are idle yet we will continue to
create more gantries. Why bother making a gantry if we're not using the ones we
already have?"*

`Utilization()` (`market/army.as:1172`) is the term written to stop exactly
this — its own comment reads *"capability nobody uses is not capability"* — and
it iterates `gWorkers`, the mobile-BUILDER list (`market/guards.as:353`). It
counts constructors holding a task. **It never looks at a factory.** It scales
`apex_plant_pipe` in `want_plant.as:758` and the BP gain in
`production.as:280`, so a base with four idle gantries prices the fifth exactly
as it would with four busy ones.

The other half of the same loop, still standing: in `want_plant.as` the
supported-line count reads `structInc = income + OverflowM()` (`:716`) and
`prodTerm` is capped by `SpareMetalRate() = gMSpareEma + OverflowM()` (`:748`).
Both are "metal nothing is spending" — which idle production is what CREATES.
The less the lines build, the more affordable another line looks.

The army-demand half of this was fixed 2026-09-05 (`RichArmyGapM`, production.as
— free flow instead of the storage-gated overflow), which is upstream of it: a
line that has army to build is not idle, so the blind term stops being reachable
in the common case. It is still wrong, and it is still the term that would catch
a line idle for any OTHER reason. Not yet measured, so not yet changed.

## 2026-09-05 — the STALL interrupt abandons builds at ANY progress, commander first

apexearth: *"Sometimes we will build 90% of a building and then choose to do
something else... I've seen it happen with a commander on the botlab in the
beginning of a game."* Third time this shape has been raised — the comment in
`requests/register.as:317` already quotes him on it (*"when we e-stall we think
to do something else... instead of choosing to finish the original lab
afterwards we just start making a new one"*).

**Mechanism, pinned.** `market/army.as` StallDry → `p.task.Abort()`. The picker
runs two passes over the workers (commander inserted at the FRONT of the
candidate list, `army.as:1277`):

- pass 0 refuses anyone with `Requests::Progress(t) > 0.01` — walkers only, the
  free interrupt. Correct.
- **pass 1 has no progress term at all.** If every candidate is mid-build it
  takes one anyway, and 96%-done is as takeable as 2%-done.

`Abort()` kills the request while the builder is still standing on it, so the
task dies `crew=1 fails=0 framed=1 why=?` (no death note — that combination in
the `task-die` histogram IS this rung) and the frame is handed to the orphan
ledger. Nothing walks the interrupted builder back afterwards; he re-elects from
scratch and the market sites the next thing wherever it likes.

**Measured**, `grep "STALL interrupt" matches/*/infolog.txt`: 4,986 interrupts
across 336 match logs; **605 abandon a build with real progress (≥0.10), 53 of
those at ≥0.90**. The commander is 1,869 of the 4,986 — armcom 1,156, corcom
713 — because he is deliberately ordered first. What gets abandoned with
progress on it: armnanotc 94 (armck), armllt 47 (armcom), armmex 26 (armcom),
armvp 12 + corvp 10 + armalab 10 + armlab 5 (the plant cases he watched).
Current build still does it: 66 interrupts in
`matches/20260905-203045-…-BARb-stable-hard`, 7 of them with progress.

**His exact report, reproduced**, `matches/20260830-063145-…-BARb-stable-hard`:

```
f=2550 STALL interrupt -- armcom #30690 progress=0.96 (1/1)
f=2550 task-die t=0 armlab bt=0 at=688,1872 fails=0 crew=1 framed=1 why=?
f=2550 frame-orphan armlab at=688,1872 done=0.96
f=2577 exec t=0 armcom #30690 energy:armsolar pick=0 at=384,1658   (304 away)
f=3001 exec t=0 armcom #30690 mex:armmex   pick=0 at=1376,1136     (further still)
```

A lab four seconds from finishing, dropped for a solar. (That one survived —
the engine build order outlived the task and it completed at f=2571 — which is
luck, not design; t0 was still the last of eight teams to field a lab.)

**Not yet decided (his call, per docs/26):** what the pass-1 interrupt should
cost. Options, none of them a flat threshold: charge the interrupt the metal
already sunk in the frame (`Progress × costM`) against the stall it answers, so
a 96% lab is unaffordable and a 5% one is cheap; or keep the interrupt and make
the interrupted builder's NEXT election re-adopt its own orphan
(`PendAnyOfDef` exists and already answers "the same def wherever it stands" —
nothing calls it on the return trip). The instrument is already in place: the
`STALL interrupt … progress=` line and the paired `frame-orphan … done=`.

**Instrument gap while we are here:** the `task-die` line has no progress field,
so the abandonment rate can only be read by pairing it against `frame-orphan` on
frame+def+position. One `prog=%.2f` on that line would make it a one-grep
question.

## 2026-09-05 — army_mix.py and expected_units.py still cannot see units under 120 metal

`dev_stats_export.lua:44-47` sets `SPAM_COST = 120` and at :359-364 diverts every
def cheaper than that into `cheapBuilt=`, out of `builtReal`, `allBuilt=` and
`top=`. `top=` is additionally only the top FOUR defs per player-game
(:631-639), so pooling it across games over-weights whatever placed in each
game's top four.

`tools/composition.py` was fixed on 2026-09-05 to pool `allBuilt` + `cheapBuilt`
and to report `unitCount=`. Two tools still read the truncated or partial fields:

- `tools/army_mix.py:43-47` reads ONLY `top=` -- the top-4, cheap units missing.
- `tools/expected_units.py:117` reads ONLY `allBuilt=`, so its "did we build the
  units we expect" check cannot see a cheap def at all, which is exactly the
  question that tool exists to answer.

What the blindness cost, before the composition.py fix: `corstorm` (Aggravator,
the Cortex T1 rocket bot) is 110 metal and `armrock` (Rocketeer, Armada's) is
120, so the same unit class was visible for one faction and invisible for the
other. This produced a wrong finding in this repo on 2026-09-05 -- "Cortex builds
no rocket bots, so the tanky row has no carry to screen for" -- when corstorm was
outspending the Thug 4.6:1 and winning 129 produce elections to 53. Any past
conclusion of the form "Apex's army is all Thugs" drawn from these three tools is
suspect.

## 2026-09-04 — EARLY FIGHT TEST: the first five minutes contain no fights on the harness

`tools/test_earlyfight.py` is the loop for docs/24's no-turret test: Apex with
`apex_def_off=1` (verified: `mDefence=0` in all 14 games, `[BARAI_TUNABLE]
apex_def_off=1` in the infolog) against stock BARb hard, 1v1, Geyser Plains BAR
v1.2.1, handicap 50, Armada both sides. The gadget now emits `[BARAI_DMG]`
(damage split mobile/static both ways, constructor interruptions, constructor
deaths) and the tool judges at a fixed minute and at the end.

The five-minute window he named is EMPTY here. Eight 8-minute games, medians at
5 min: 0 enemy units killed, 0 lost, 0 damage on buildings, 0 constructor
interruptions; stock has 1-2 units in the field at 8 min. First contact on this
map is at 8-12 min. Six 15-minute games judged at 10 min have data but only in
4 of 6 games; end-of-game medians (no turrets on our side): damage efficiency
1.09, metal K/D 0.98, buildings receive 1618 vs deal 320, 4.5 constructor
interruptions and 3 constructors lost per game, 2 of 6 won inside 15 min.

So the test that judges the early window is `tools/test_raid.py`:
`dev_raid.lua` spawns waves for a NullAI holder team on stock's side (run_match
`--extra-ai NullAI:0.1@1`) at fixed minutes, aimed at our buildings' live
centroid, and the tool scores each wave -- wiped or not, seconds to wipe, its
nearest approach, our metal lost to the raiders against the wave's cost,
building damage and constructor interruptions meanwhile. Validated on one
seed (2026-09-04): a 2-Pawn wave at minute 2 killed a mex and two
constructors with only the commander home; a 5-unit wave at 3.5 died to the
commander and Pawns. Thresholds in the tool are calibrated on the first
baseline set and catch regression from that state, not distance from ideal.
`tools/test_earlyfight.py` stays as the natural-play set (15 min, judge at 10).
Squad spread at engage reads 25-112 elmo (a ball) in every game with an engage.

Measured on the unchanged AI, 8 games per level, 11-minute games, waves at
minutes 3/5/7/9 (`--level`; medians per wave):

    level  raid shape                                  kd   wipe s  closest  lost/wave
      1    one clump, from the enemy, at the centre   2.0     26      275      104
      2    one clump, random bearing, at a mex        0.9     50      518      307
      3    two groups, two bearings, 8 s apart, edge  1.2     41      473      210
      4    three bigger groups, 10 s apart, at cons   0.9     76      342      397  (4 of 30 waves never wiped)
      5 with our army PINNED at 2x the raiders (`--ratio 2`, his early-game
        framing: 3-8 mexes, wind, a T1 lab, twice their raiders):
           placed at the base centre                  1.1     33      360      359  1 building killed per wave; 54 over 32 waves
           spread beside the buildings                1.4     41      448      351  1 building killed per wave; 53 over 32 waves
        Even at 2:1 only 2-5 of our 10-30 units are at the first contact; the
        army clears the five groups one at a time and a mex or wind dies
        first in every game. The AI's own army at those minutes was about
        HALF the pin (4.5 vs 10 at min 3, 9.5 vs 20 at min 5).
      5    FIVE groups at once, five bearings, each at
           a mex or solar (his stated shape)          1.1     48      250      380  3 buildings killed per wave;
                                                                                    108 buildings over 32 waves; no game lost 0

Response, from the gadget: raiders show on radar/LOS 5-8 s after spawning
(~1400 elmo out); first hit 2.5-6 s after sighting; 2-4 of our mobile units
near the wave at first contact, peak 5-7 of an army of 7-9 (70% of the army
ends up near the wave because the wave walks to where the army stands).
MECHANISM: nothing dispatches on a sighting. `basedefence.as` UpdateApproach
needs an enemy group >= 800 metal (danger) or >= 2500 (push) -- a 108-476
metal raid never trips it, 0 firings in 24 games; the RAIDED sensor fires
only after a building dies and feeds turret siting and consolidation, not a
sortie. What answers is the C++ DefendTask post: re-elects a target inside
post range + 500 elmo at 1.2x odds, and units auto-fire. No squad sizing for
a raid exists anywhere. Wave one (min 3, commander alone) gets inside 50
elmo in 30-40% of games; it is reported, not gated.

INTERCEPT, first cut (2026-09-04, C++ CDefendTask, `apex_intercept`, OFF by
default): an enemy whose 30-second course crosses our buildings' influence is
electable from anywhere, the pool aims at the meeting point, a raider already
covered by 2x its worth in other pools is skipped, pools neither merge nor
promote while one is inbound. It FIRED (10 `apex: intercept` lines per short
game) and DID NOT MOVE THE OUTCOME: level 5 pinned, buildings lost per 32
waves 59 (off, same DLL) vs 50 (on) vs 54 (old DLL); units at first contact
fell 3.5 -> 2. Level 1 got WORSE: 13 buildings lost over 32 waves against 0,
wave K/D gate 7/8 -- lone Pawns ran at a 5-raider clump because the odds gate
counts every squad within 3000 elmo as allies. Two things the election alone
cannot do: SPLIT a pool that merged before the raid (a 12-unit pool still
walks as one at one raider), and hold an under-sized pool back until it has
2x the GROUP it is going for. The next cut is an allocation, not an election:
partition the home guard across inbound groups by worth, moving units between
tasks (AssignTask), and let pools merge only toward the group they are short
for.

THE DISPATCHER (2026-09-04, `CMilitaryManager::DispatchRaids`, same switch,
OFF by default). Every 2 s: visible mobile armed enemies near home are read
one by one, clustered at 450 elmo into raids, sorted by arrival, and each
raid takes the nearest fighters at home (DEFEND, ATTACK, RALLY, RAID and
SCOUT pools) until they hold 2x its worth; one CDefendTask per raid, moved
into with AssignTask, standing at the building on the raid's course, engaging
once it carries the raid's worth itself, no merge or promote while dispatched.
Three cuts, 8 games each, level 5 pinned buildings lost per 32 waves: before
54, switch off 48, v2 54, v3 45 -- noise. Level 1: v2 13, v3 15, against 0,
and v3 failed the closest gate 5/8. Sizing worked (got >= need in nearly
every line; `short` almost never); what did not was TIME: most dispatches
read eta=0, i.e. the raider was already inside the base ring when first
allocated, because `CEnemyInfo::GetVel()` is ZERO for a radar-only contact
(`still` was 40-60% of inbound contacts), so the trajectory branch never
fires before LOS. "Look at the trajectory" needs a velocity the AI does not
have from the engine for radar blips; the next cut derives it from the
contact's own position history over the last 2-4 s (the approach tracker in
basedefence.as already does exactly that for groups). Until then a dispatcher
can only allocate after the raid is at the buildings, which is what level 5
measures.

v4 added the position-history velocity (still contacts fell from 40-60% to
~10% of inbound) and aimed inside-ring contacts at the nearest own structure:
level 5 pinned 55 buildings per 32 waves, level 1 16. Still nothing. And the
ring itself explains the ETA: base range 1222 x 1.25 = 1527 elmo, the raid
spawns ~1500 out, so every contact is "inside" at first sight and the
trajectory branch is moot on this harness. POST-MORTEM of the building deaths
(ARMY snapshot before each death): our nearest mobile unit was a median
237-337 elmo from the building that died, with 9-11 of ours within 1000 elmo
and only 21-28% of deaths with none within 500. The army IS there. A mex or
wind dies in the ~10 s a Pawn needs while our two nearest units walk 300 elmo
and elect it -- a race lost by seconds, not a positioning failure. Allocation
cannot fix that; what can is reaction latency (2 s dispatch cadence, the
defend task's 16-update election, the async path query before a move) and
meeting the raid outside the buildings, which needs the raid seen earlier
than 1500 elmo out.

THE TIME-RACE TEST: same level 5 pinned, raids spawned at 0.9 of the way to
the enemy (~2250 elmo, ~30 s walk) instead of 0.6. Dispatcher ON 35 buildings
per 32 waves, OFF 61 (seeds 1-8). Given time, the dispatcher halves the
losses; at 1500 elmo the race is over before allocation matters. Second pair
on seeds 9-16: ON 48, OFF 51. Combined 83 vs 112 over 64 waves each, with
per-game spreads that overlap (ON 2-8 per game, OFF 1-12): the first pair's
gap was mostly noise, and the honest reading is a weak effect at best. The
dispatcher stays in the code behind `apex_intercept=1`, default OFF. What the
five measured cuts established: allocation and sizing were never the gap
(need met in nearly every dispatch); the loss is a ten-second race between a
raider at a building and two of ours 300 elmo away, and that is decided by
reaction latency and by fighting, which no dispatcher touches.

Base spread at the waves: 7-12 buildings, RMS 450 elmo from centroid, the
farthest building/mex at 800-1000 elmo.

`closest` is a high-variance metric: waves 2-4 per-game minima ran 177+,
112+ and 23+ across three identical sets. The gate is 50 elmo on waves 2-4
only; do not tighten it without more games.

## 2026-08-31 — vs an INACTIVE opponent we still barely expand, and army still outspends economy

The first controlled economy measurement this repo has had. `NullAI:0.1` does
nothing at all -- no army, no expansion, no pressure -- so every number below is
this AI arguing with itself. Comet Catcher Remake 1.8, 30-minute cap, 13 seeds,
medians at fixed game minutes (the games end early, at ~20-28 min, when we kill
the passive commander, so end-of-game totals are not comparable and fixed
minutes are).

    min   mInc  produced   mEco    mBP  mArmy   mex   eInc
      6   11.2      2700    615    220   2862   4.0    104
     10   13.5      5666    965    480   4098   5.0    133
     14   18.1      9672   1836   1010   5590   7.0    256
     18   36.4     14916   3196   1630   7318  14.0    469

- **4 mexes at minute 10, 7 at minute 14, on a map with ~20+ spots and nothing
  contesting them.** This is apexearth's 2026-08-31 complaint ("4 un-upgraded
  mexes, income 15 m/s") reproduced with no enemy on the board to blame.
- **Army outspends economy from minute 10.** `mArmy` includes the ~2700-metal
  commander, so real army is ~1400 at min 10 against 965 of economy, and ~4600
  against 3196 at min 18. Against an opponent that cannot attack.
- Economy is ~21% of all metal produced at every checkpoint.

MECHANISM, partly identified and NOT yet fixed: most of that army metal never
passes through the builder market at all. `Market::ConOrderFor`
(`brain/market/production.as`) is the factory's own path, and the Brain drives
it independently of the Want auction -- so anything that reweights the
constructor market, the ETA objective included, structurally cannot move the
army/economy split. Whatever holds army at this share against a dead opponent
lives on the production side.

Do NOT read this as "the market is broken and the factory is fine". It is a
statement about WHERE to look: an economy-vs-army fix has to reach the producing
code, per CLAUDE.md's standing rule about attributing a composition problem
before touching any config table.

## 2026-08-31 — ENERGY: 46-58% of everything we generate is thrown away

apexearth: "We have not nearly enough energy converters. Take a look at how much
energy we waste."

Measured, watch-nanopack (SI 8v8 +100%, 26 min): median **57.8%** of all energy
produced wasted, 80.7% on the worst team, against 0.6% metal waste. Red Comet
1v1 +100%: 45.9% and 55.8%. An `armmmkr` is 380 metal, chews 600 e/s at
0.01724 -- 10.3 metal/s, a **37-second payback** -- and 11-13 stood per player
against an overflow needing ~16 more.

TWO WRONG DIAGNOSES BEFORE THE RIGHT ONE, both recorded so they are not retried:

1. "The storage gate blocks it" -- no. The bank sat at 87-99% of storage all
   game, so `current >= 0.85 * storage` passed throughout.
2. "The parallel-site fix is the answer" -- the serialization is real
   (`par` reads MCostScale, a METAL stall, so the one building whose trigger is
   surplus ENERGY was serialized), but it was not what bound. `apex: conv batch`
   fired ZERO times after the fix.

THE ACTUAL CAUSE, from `apex: convwhy`: the want fires and proposes 196 times,
nothing obsolete, nothing short of candidates -- and `ema=782` e/s in a game
discarding ~31,000. `gESurplusEma` is `energy.income - energy.pull`, and **pull
is DEMAND**: a fleet of 250 nano turrets asks for energy it is not drawing. So
the surplus is understated by more than an order of magnitude, a 600 e/s machine
is priced against a 1,000 e/s surplus, one order exhausts it, and the fleet
stalls.

FIX IN, NOT YET PROVEN: `EnergyPinned()` (bank >= 98% of storage) means
production exceeds consumption whatever the EMA says, so the chew is the
converter's full capacity and metal is the only bound on how many to start.
Self-limiting -- the bank empties, and the pin breaks once enough stands.

WHY IT IS NOT YET PROVEN: waste fell 51.7% -> 14.7% between the army sweep's 0s
and 40s arms, but a bigger army means a smaller energy grid. That is confounded
with the army change and separates nothing. The clean test is converters
STANDING and `conv batch` firing at a fixed army setting.

## 2026-09-02 — FRONT DEFENCE: the line now forms in 1v1; what is still open

The 2026-08-31 entry ("the line is drawn along the TEAM's band, and the wall
generator places 96% of everything") is closed by the 2026-09-02 commit that
carries the mechanisms and the numbers; `python tools/test_frontline.py` is
the regression contract (a gun per mex by minute 8, a line of >= 4 towers
>= 800 wide between us and them by minute 14, a factory by minute 4, no mex
with more than two guns on it). Residue, each measured in the same batteries
(Comet Catcher 1v1 vs BARb hard, +50%, 20 min):

- **The line is T1 and stays T1.** After T2 the T1 hands stop buying defence
  (`xT1late=0.020` x `xTeamPow=0.035` on an LLT once a Pulsar is the team's
  best) and the T2 con prices its own gun through `xWallEff=0.141`, so
  defence held 870 of a 16,988 target at minute 18 (`apex: targets`) and
  towers were lost faster than replaced (8 standing at 18 min from 10 at 16).
  His fortification doctrine (T2 con builds T2 guns, nanos heal them) has no
  path while both discounts stand; the dominance rule already drops dominated
  towers, so the per-metal `apex_wall_efficient` discount is now a second
  penalty on the only candidate left.
- **The commander walks to the line and dies there.** `Decide` exempts wall
  work from the 400-elmo forward limit on his ruling that commanders are good
  early wall makers; with the line at fwd 0.3-0.45 he walked 2,000 elmos and
  died to pawns at fwd 0.43 (fl-b s5, the only loss with a line standing).
  Exposure is charged to non-defence wants only; his own 2,700 metal is not
  in the price of a forward tower.
- **THE OPENING WEDGE on the (1460,2976) Comet Catcher start -- the main
  source of red test runs.** Six games of 38 (always seeds 2 and 6): the
  commander stands IN RANGE of his own site and does not build, for minutes.
  fl-j s2: solar requested at 1401 with the site at 2648,2344, commander at
  2646,2335 from frame 1200 to 2700, `framed=0`; mex at 3008,1952 elected at
  2953, commander at 2904,2071 (104 elmos away) from 5100 to 12000+, never
  built; the solar task finally dies at 11930 with `fails=3`. Build orders
  ARE issued (`ORDERS ... build=2` a minute) and metal/energy are full. The
  same corner in every case (x 2450-3000, z 1750-2350), and two commanders
  died there. Suspects, unverified: a crater rim that puts the site out of
  3D build range while the path ends at the cliff, or the builder blocking
  its own footprint (Spring's BuggerOff excludes the builder). It only
  happens when the draw sends the commander to that corner before the lab;
  in the other seeds the lab is drawn by frame 681 and cons cap that mex
  later without trouble. `tools/test_frontline.py` reports it as the `plant`
  metric (warn-only until fixed). The defence rules that used to key on an
  ORDERED plant now wait for a frame (`PlantFramed`), which removes their
  part in it.
- **The e-stall hoist owned the opening.** Before the fix 36-80% of builder
  elections in the first eight minutes were `why=estall`, every one joining
  the same solar. Now one generator on the way ends the hoist, but the stall
  itself is the ENERGY entry above: the lab eats the metal, solars starve.
- **Nanos outbid guns early.** `buildpower/nano` wins at v=50-54 against
  defence at 20-40 through minutes 2-8 (three nanos by minute 8 = seven
  LLTs); `apex: budget` reads bp=0.67-0.95 against its 0.16 target. Not
  touched here.
- **Team games are unmeasured.** Every battery above is a 1v1; `FoeRef` uses
  the mirror of the team's homes, which is right for lr/tb boxes and wrong
  for a corner start. A `--per-side 4` run on Comet Catcher is NOT a
  measurement: the auto start box puts all four players within 100 elmos
  of each other (starts 1268-1364, 2784-2880), every line is cut to 1-6
  slots by the ally-lane rule and lineFwd reads ~0 (fl-4v4: guard 7/8,
  line 2/8). Use his 4v4 map (Aethermoor Creek 1.0, battery.py) before
  believing any team-game number.

## 2026-08-31 — NANO: the fortification site is priced and then thrown away

`want_nano.as` prices a fortification lathe (`fortNeed`, from
`Military::FenceLostNear` -- demand where our own guns are actually dying) and
sets `w.pos` to that ground. `execute.as` then re-derives the site from scratch:
neediest line, then metal sinks, then bare big frames, then "any factory", and
only uses `w.pos` if we own no factory at all. So a nano bought to hold the wall
is built beside a lab.

This is why apexearth's split -- "defense oriented emplacements of nano turrets
are better when they're spread out so they don't all get blown up at the same
time" -- has no code path today: every executed nano is an assist turret. The
packed lattice (`market/nanopack.as`, 2026-08-31) is correct for all of them
until the fortification site is honoured; the spread answer has nothing to site.

## 2026-08-31 — NAVY: the T2 con is BUILT and then never elects; naval mex never happens

apexearth: "What we lack: T2 navy lab & T2 navy con; upgrade navy mexes." Probed
on Nine_Metal_Islands_V1, 4v4, +100%, 22 min. The chain is
shipyard -> advanced shipyard -> advanced construction sub -> naval advanced mex
(`armuwmme`/`coruwmme`, **620 metal, the same price as a land moho**), and every
link exists in the pinned game.

WHAT IS NOT THE PROBLEM, stated because a first reading of the code said it was:
the T2 shipyard is NOT unreachable. Measured, `plant:armasy` executed once and
`produce:armacsub` three times in one game -- the plant lane reaches it when a
navy con elects. It is RARE (1 advanced shipyard against 20 T1 ones), and
`want_tech.as` did skip every floater outright, which is now fixed -- but "never
built" was wrong.

THE ACTUAL GAP, and it is one step further down: **an advanced construction sub
is produced and then never takes a job.** In a whole game `acsub` appears in
three `apex: decide` lines and all three are a SHIPYARD deciding to produce one;
not one is an acsub electing work. Consequently `uwmme` is elected **zero**
times, while the AI's own `apex: upcons` line lists acsub among the constructors
that can upgrade a mex -- so the catalog knows, and the market never asks.

Next step is to find where a submerged builder falls out of the builder market:
`gWorkers` registration, the `OnMap`/reach guards, or an execute path that has
no water case. Do not "fix" the pricing before that is known -- the unit is not
losing an auction, it is not entering one.

ALSO OPEN, apexearth's ruling on how much navy to want: *"There are two sections
of water on the map. We should try to control each of those. Too much presence
would mean we lack ground forces - so we need a reasonable mix."* Today
`NavalLead()` elects a SINGLE player by distance-to-water and gates on
`OwnedWaterPlants() == 0` -- the exclusivity shape he has rejected before ("a
role may change how OFTEN or how MUCH; it must not decide WHETHER"), and it
cannot express per-water-body control at all: there is one `NAVDIST`, one cached
`WetPlantSite`, one lead. Naval demand wants to be per water BODY, with the mix
against ground falling out of the price rather than a cap.

## 2026-08-31 — the eco scoreboard: method, and what it has bought so far

A/B testing was ABANDONED here on apexearth's call: *"I also thought an A/B test
was silly to do here. Benchmark against ourselves, iterate and improve."* The
earlier attempt is why -- two batches of the identical configuration differed by
+9.3% and +13.3% mean `metalProduced` (sd ~20%, minute-18 CI excluding zero), so
the benchmark reported a significant difference between a config and itself, and
resolving a 10% effect would have needed ~60 pairs. **A 10-game eco A/B on this
benchmark measures noise. Do not run one.**

RETRACTED from the first attempt, and do not cite it: "the ETA arm builds more
army, +12.5% at minute 6, p=0.039". The identical-config control threw a p=0.039
too, and there are 28 tests per comparison.

THE METHOD INSTEAD. One scoreboard, 10 seeds, Apex vs `NullAI:0.1` (which does
nothing at all), Comet Catcher Remake 1.8, `apex_eta=1`, medians at fixed game
minutes. Only runs that actually REACHED a mark count toward it -- carrying a
finished run's last sample forward reports an early win as a small economy.

    SB1  economy-only          SB2  + spend the metal
    min  income  mex  waste%   min  income   mex  waste%
     10    15.8  6.0    46.6    10    18.2   6.5    18.2
     20    53.6 27.0    18.6    20   131.1  54.5    19.1
     30   211.2 64.0    11.7    30   233.1  66.0    13.0

**2.4x the income at minute 20**, n=10 each, far outside the noise floor above.

WHAT EACH STEP WAS, so the next one is not re-derived:

- **SB1 -- economy is the only target.** Two independent army drivers had to go,
  and the second is the one that matters: `ArmyTarget()` falls back to a
  SYMMETRIC PRIOR when no enemy is visible, so against an opponent that does
  nothing we built army to match an imagined mirror of ourselves; and
  `sinkGap = OverflowM() x fillS` **defines metal we fail to spend as army
  demand**, which is why army ran at 1.58x its own target (7370 against 4666).
  Army metal at minute 18: 5544 -> 324. Expressing "this player is for economy"
  as a zero target is apexearth's own shape, quoted in `protect_target.as:15`.
- **SB2 -- spend the metal, do not bank it.** `OverflowM()` only reports once the
  bank is past 80% of storage, a LATE report of a fact available immediately:
  measured, the bank pegged at its cap around minute 5 and the AI first admitted
  it lacked hands at minute 6, having already binned 792 metal (apexearth:
  *"Relying on storage is lazy - make sure spend the metal. (need more build
  power)"*). Replaced by `SlackFrac()` -- smoothed `(income - pull)/income`, no
  storage term -- which floors `feedRoom`, the forecast that had switched
  constructor production off at ten builders while 46% of the metal was being
  thrown away. A prediction must not veto production when a measurement refutes
  it.

OPEN, both attributed and neither guessed:

1. **Late-game waste is untouched.** 19.1% at minute 20 and 13.0% at minute 30 --
   the same failure as the early game, at a larger scale. SB2 bought the opening
   only.
2. **The frame budget is now violated by the economy this created.** 1v1 watch,
   `apex_perf=1`: worst spike **102 ms**, `hk.maketask.builder` 10,197 ms total,
   and the top per-call offender is `want.mexup` at 4.0 ms average / **75.3 ms
   worst**. That walk is O(spots x constructors) and this build reaches 98 mexes
   and 232 builders where the old one reached 14 -- a throttle sized for an
   economy a fifth the size, which is CLAUDE.md's "a bulk pass that got BIGGER
   without its throttle being revisited", exactly.

## 2026-08-31 — `policy.as` is 17 knobs and ONE of them is connected

The docs were swept against `docs/23-the-plan.md` on 2026-08-31 and this is what
the sweep found in the code. `policy.as` opens by declaring itself the home of
eco THRESHOLDS -- "the numbers that decide when energy is short, when a
generator is obsolete, when a constructor is worth buying" -- which is the shape
the plan forbids. But the file turns out to be a smaller problem and a stranger
one than that header implies.

MEASURED (grep over the whole of `ai/Unstable/game-side/script/`, verified twice
-- by `Policy::<name>` and again by the raw `apex_*` tunable string, because
absence is the least reliable finding here):

- **17 accessors. Exactly ONE call site in the entire tree**:
  `Policy::AntinukeIncome()` at `market/want_super.as:421`.
- The other 16 are read by nothing. `EnergyHeadroom`, `EPerMetal`, `T2Energy`,
  `T2Metal`, `T2EnergyFrom`, `T2EnergyReactor`, `FusionMinEnergy`,
  `ReclaimSolarE`, `ReclaimGenE`, `ReclaimPad`, the four `ConLog*` curve
  coefficients, `GreedCons`, `ShieldIncome`.
- All 16 are still registered in `game-patches/gadgets/dev_tunables.lua`, so
  they are live modoptions a dev game can set, that do nothing. They are NOT on
  the dashboard's guided page -- they sit in `dashboard_audit.py`'s waived list,
  which is why nothing has flagged them (see the audit gap below).
- Their comments name the code that used to read them: `techlead.as`,
  `manager/factory/phase.as`, `manager/builder/share.as`,
  `manager/builder/fusion.as`. **None of those files exist.** The brain overhaul
  deleted them and rebuilt their jobs as priced Wants in `brain/market/`, which
  read continuous inputs (`EcoPowerM`, `BestConvRatio`, `GenObsoleteOnArrival`'s
  ratio test) rather than any threshold. So the ETA-shaped replacements already
  exist and run; `policy.as` is the orphaned old interface sitting beside them.

So this is mostly a CULL, not a redesign, and it is cheap: 16 accessors, their
`TUNE_` constants, their `dev_tunables.lua` entries, and the stale comments that
cite deleted files. Do not confuse the cull with the one real issue below it.

### The one live one: an income floor stacked on top of an affordability test

`want_super.as` already refuses what it cannot afford -- `if (bill >=
classBudget) continue;` at :407, before the antinuke branch. The floor at :421
is an EXTRA gate, and its own comment says why it was added: the anti-nuke is
the cheapest class on the list, so it clears a budget-relative affordability
test long before a gantry or a silo does, and "took every super-push".

That diagnosis is right and the patch is the wrong shape. `afford =
(classBudget - bill)/classBudget` rewards being cheap by construction -- the
code says so itself, twenty lines later, where the gantry needed a special gain
term for exactly this reason. A hand-set 60 m/s bar on one class papers over a
pricing function that cannot rank a cheap insurance policy against an expensive
production line. The plan's answer is the comparison the floor replaces: which
of these makes the target arrive sooner. Fixing `afford` is the change;
deleting the floor is a consequence of it, not a change on its own.

### Why nothing flagged it, and the 26-knob cull list it was hiding

`unread` was `bool(tunable) and not sites` and `sites` counted any
`GetTunable("apex_x")` anywhere -- including the one inside the dead accessor
itself -- so every knob read only by an uncalled wrapper passed clean. A second
layer compounded it: `dashboard_audit.py` tested `unread` on CURATED entries
only, and all 16 policy.as knobs are waived.

FIXED 2026-08-31. `tools/as_scope.py reachable()` is a fixpoint reachability
walk seeded from the engine's own entry points (taken from
`reference/barb-stable`, not from us); `python tools/as_scope.py --dead` prints
it. A read inside an unreachable function is no longer counted, and waived
knobs are checked too. It also found **91 unreachable functions tree-wide** --
a cull list in its own right, and the same rot class as the accessors.

That turns up **26 tunables nothing can read**, not 16 -- live modoptions on
apexearth's dashboard wired to nothing:

    ENERGY_HEADROOM E_PER_METAL FUSION_MIN_ENERGY RECLAIM_GEN_E RECLAIM_PAD
    RECLAIM_SOLAR_E T2_METAL T2_ENERGY T2_ENERGY_FROM T2_ENERGY_REACTOR
    CON_LOG_T1_A CON_LOG_T1_B CON_LOG_T2_A CON_LOG_T2_B GREED_CONS SIEGE
    KILL_FLOOR RAID_MIN_EARLY SHIELD_INCOME SCOUT_BLIND_MULT E_STALL_BOOST
    LINE_PULL NUKE_RISK WAVE_MEET BUDGET ALLY_COVER

Verified per knob against `ai/Unstable`, `cpp/src`, `tools` and
`game-patches`, because two rounds of this produced false positives: **the C++
DLL reads tunables too** (`apex_porc_obsolete_ratio`/`_secs` are live reads in
`DefenceData.cpp` and were briefly on this list -- `dashboard.py` now scans
`cpp/src`), and `apex_siege` -- which IS gone -- looks read until you match
exactly, when the hits turn out to be the live `apex_siege_prior`.

NOT CULLED, because two are not mechanical and are apexearth's call:

- `TUNE_CON_LOG_T1_A/B`, `T2_A/B` are drawn as a curve by
  `dashboard_ui.html:1535-1537`. The UI rows go with them.
- `apex_t2_metal` has a SECOND life as a hardcoded `T2_BAR = 30.0` in
  `tools/audit.py:848`, which checks whether the AI went T2 above 30 m/s.
  Under `docs/23-the-plan.md` that bar should not exist to be checked against
  -- but deciding what the audit asks INSTEAD is a real question, not a
  deletion.

## 2026-08-31 — the T2 affordability FLOOR is gone; only a soft price remains

apexearth, watching a 1v1 loss: we started T2 at ~15 metal/s, and a fusion at
~10 metal/s (4,300 metal, roughly seven minutes of the entire economy). "I
thought these issues were fixed" — they were, by machinery that no longer exists.

VERIFIED, two ways, because absence is the least reliable finding here:

- `RushReady` has ZERO definitions in the tree. Five references survive and all
  five are comments (`factory/state.as:17`, `policy.as:31`, `tunables.as:158`,
  `:165`, `:314`), pointing at a `techlead.as` function the brain overhaul
  deleted.
- `T2Energy()`, `T2EnergyFrom()`, `T2EnergyReactor()` and `T2Metal()` are still
  defined in `policy.as` and are called from NOWHERE. So `apex_t2_energy`
  (1200), `apex_t2_energy_from` (12) and `apex_t2_energy_reactor` (400) are
  live knobs on the dashboard's Balance tab, adjustable, wired to nothing.

WHAT IS *NOT* TRUE, and the distinction changes the fix: it is not that nothing
expresses affordability. `want_tech.as` prices the advanced plant with real
arithmetic — `aiEconomyMgr.metal.income` and ValueOf's `feedSec` term, "half the
bank is spendable now, the rest waits on income". The hard FLOOR became a SOFT
PRICE, and the soft price does not bite. That is the same disease as
`docs/21-simplification.md`: one term among many cannot order an outcome.

The ruling has since landed, and it is neither of the two obvious patches.
`docs/23-the-plan.md` (2026-08-31): a floor is forbidden, and so is a decisive
affordability multiplier tuned by hand — **a plant we cannot feed loses because
starting it lengthens the ETA to every target we might name**, and at 15 m/s
with four un-upgraded mexes the cheap growth beneath T2 was not yet exhausted.
So the fix is the ETA comparison itself, not a term added to the existing
price. The three dead tunables above are what a *floor* would have consumed;
under the plan nothing will consume them, and they can be culled when the ETA
work lands rather than before.

ALSO OPEN, from the same watched game and unranked here: army sent out to die
instead of holding inside our own turret cover; the turret line drifting
backward rather than concentrating forward; fight orders issued too freely.

INSTRUMENT GAP, found while confirming the above: `tools/dashboard_audit.py`
cannot see this class. Its `unread` test asks only whether SOME `GetTunable`
call exists, and `policy.as` has one — so a knob read exclusively by an
accessor that nothing calls passes the audit clean. An attempt to add the
detection produced eleven false positives (`if (...)` parses as a function
definition, and a one-line `float T2Energy() { ... }` body does not) and was
reverted; doing it properly needs the real scope walk `tools/as_scope.py`
already implements, not another regex.

## 2026-08-30 — defence pricing: reach is paid as AREA, damage rate was paid as sqrt

apexearth: "you can get like 10x the DPS from HLT per mass compared to the
gauntlet style defense... dps per metal and range is usually what my brain
thinks about", then "So we value range a bit too generously :-P".

Three terms decide a turret's cover, and they were weighted almost exactly
backwards. Measured off the pinned tree (a scratch script, since deleted; dps counts
every weapon mount, range is the weapon's own):

| tower | cost | hp | dps | alpha | range | dps/metal | old threat/metal |
|---|---|---|---|---|---|---|---|
| armllt Sentry | 85 | 620 | 241 | 112 | 430 | 2.84 | 14.81 |
| armbeamer Beamer | 190 | 1430 | 400 | 40 | 480 | 2.11 | 10.01 |
| armhlt Sentinel | 440 | 2600 | 322 | 580 | 620 | 0.73 | 10.22 |
| armguard Gauntlet | 1250 | 3050 | 211 | 300 | 1220 | 0.17 | 2.67 |
| armanni Pulsar | 3500 | 6100 | 1091 | 10800 | 1400 | 0.31 | 7.51 |
| cordoom Bulwark | 3000 | 9400 | 1513 | 4500 | 950 | 0.50 | 10.30 |
| corbhmth Cerberus | 3100 | 8300 | 324 | 450 | 1650 | 0.10 | 2.44 |

- **REACH: paid as area, and still is.** `PfStakeIn` buckets our economy at
  the candidate turret's OWN range (protect_field.as:436, "The slot's pitch IS
  that reach"), so a 1220-reach gun is credited with 6.5x a 480-reach gun's
  stake. That would be right if a turret defended all of it at once; it shoots
  one thing at a time. **This is the open item.**
- **HIT POINTS: paid twice.** `sqrt(health)` inside CircuitAI's surfThreat
  (CircuitDef.cpp:623) and again as `hp/(hp+PfAlphaRef())` in `PfTowerKill`.
  The second is deliberate and earns its place (it is what makes a Bulwark
  reachable over twelve Beamers); the double count is the accident.
- **DAMAGE RATE: was paid as `sqrt(dps)`** — FIXED. A Beamer's real 12x
  damage-per-metal edge over a Gauntlet read as 3.7x. `PfTowerKill` now
  prices on surface DPS recovered from surfT (`apex_def_dps_linear`, default
  on; 0 restores the old pricing).

Net before the fix: Gauntlet beat Beamer 6.5x on reach and ~2x on doubled hp,
losing only 3.7x on compressed dps — **1.7x in the Gauntlet's favour**, which
is what the auction did. After it, Beamer wins ~2x early and they are level
late; the Gauntlet is held up entirely by the r² reach term.

Also fixed alongside (weakly): `apex_t1_def_late`'s gate was a STANDING
advanced defence constructor, so any player with an advanced lab but no such
con kept buying light towers at full price. Now `Factory::gHaveT2 ||
T2DefHandsStanding()`, default 0.15 -> 0.02. Matched 4v4 A/B (same map, seed,
handicap; control = discount off) moved T1 metal after T2 by only -43% / -14%
on two seeds with the tower COUNT unchanged (117->109, 132->133) — it shifted
which light tower gets picked, not whether. The multiplier is not the lever;
the pricing is.


## 2026-08-30 — we do not raid at all; stock BARb raids all game

apexearth: "I am convinced the barb stable AI uses raiders better than we do.
So I think we need to rethink our own usage of them." Measured, not inferred.

**Stock's pipeline, entire game.** `CMilitaryManager::DefaultMakeTask` maps
ROLE_RAIDER to `Defend(RAID, quota.raid.min)` (MilitaryManager.cpp:1679).
`CDefendTask::Update` promotes to a real `CRaidTask` at `quota.raid.min`
(10.0 power in hard_aggressive) **or the instant any RAID task already
exists** — so after the first pack it is a continuous stream, not one blob.
`CRaidTask::CanAssignTo` caps a pack at `quota.raid.avg` (65 power), same def
only, within 1000 elmos of the leader, so they field many small same-unit
packs concurrently. `CRaidTask::FindTarget` is economy-first: an enemy
BUILDER or COMM is taken with `maxThreat = FLT_MAX`, anything whose local
threat exceeds 0.75x the pack's power is skipped, and the allowed threat
DOUBLES inside their own base radius. No target -> `FallbackRaid` roams to an
unclaimed scout position.

**Ours diverts every raider out of that pipeline**, both in
`manager/military/hooks.as`:

1. `IsFodder` (hooks.as:8) — SCOUT/RAIDER ground units under
   `apex_fodder_cost` (100m). In `SpamPhase()` (posture.as:310, true once
   `Factory::gHaveT2`, `apex_spam_suicidal` default on) they become **solo
   `CScoutTask`s**, one per unscouted metal cluster. `CScoutTask` is not an
   `ISquadTask`, so they can never group, and they hunt unscouted ground, not
   the enemy's constructors.
2. `WantsMassing` (hooks.as:44) — `if (role == RT::RAIDER) return
   Factory::gHaveT2;` Every raider at or above 100m joins the single massing
   DEFEND pool the moment our advanced lab stands. They become line army.

Before T2 raiders do reach the stock pool, but `UpdateRaidCaution`
(posture.as:37) rewrites `quota.raid.min` from 10 to `apex_raid_pack (8) +
0.2 * metal income` — roughly double stock's first-pack bar at 40 m/s income.

**Evidence.** `NoteFightElection` stamps the elected fight type on each unit
(`f<N>@frame`; 1=GUARD 2=DEFEND 3=SCOUT 4=RAID 5=ATTACK 6=BOMB 9=AA
11=SUPPORT). Across the 11 most recent matches in `matches/`, **f4 = 0 and
f5 = 0 in every one**. f2 (the massing pool) runs 243–417 per game, f3
(fodder-as-scout) 121–253, f1 (escort guard) 36–183.

So the gap is not that we raid badly — after our own T2 we hold no RAID task
at all, and the same T2 flip is what turns the whole raider class into line
army. This also re-loses his 2026-08-20 "tit for tat" ruling, which is quoted
in UpdateRaidCaution's own comment.

**2026-09-05 — RULED, and the numbered list above is stale.** apexearth, asked
whether a raider stops being a raider on T2: *"Even marauders are raiders and
most people play them as raiders, skirting their way around the front lines to
attack enemies behind"* — Marauder (`armmar`) is T3, named as the extreme case.
No tier converts the class, and the route is part of it. `docs/24` carries it.
Diverters 1 and 2 are already off by default (`TUNE_RAIDER_MASSING = 0`,
`TUNE_SPAM_RAIDERS = 0`, both since 2026-08-30) — check the tunables before
repeating them, as this entry was once quoted forward without doing so.

A third diverter was real and is fixed: the cover branch in `AiMakeTask` claimed
the raider class permanently, because `gPostReq` floored each asset's cover need
at its own worth and so demanded the whole base's worth in guards. It is
`Market::ThreatM(pos)` now.

What remains is the pool, not the routing. The `apex: elect` branch census shows
13 raiders reaching `Defend(RAID, raid.min)` in one game with zero raids formed:
`Enqueue` builds a fresh one-unit `CDefendTask` per unit, packs form only via
`GetMergeTask()`, and a 2.5-power Pawn against an 18-power bar never gets there.
`military/raid.as` (`apex_raid_ask`) works around it from the script side by
assembling packs directly. The pool itself is still wrong, and separating raid
from massing pools in the census needs `GetPromote()` bound — a DLL change.

## 2026-08-30 — parallel expensive energy: FIXED, two residues open

He raised it four times, the last with a screenshot of a fusion at 55%, a
second reactor at 50%, an AFUS at 11% (ETA 64 min) and an abandoned frame at
`ETA ???`, then again live: "we're making 2 fusions and 1 afus all at the same
time... I feel like giving up." Cause: every duplicate gate keyed on DEF ID and
the energy ladder is six defs, so the per-def gate refused `armfus` and the
stall ladder immediately founded `armckfus` and `armafus` instead. Fixed in
e593ace: expensive energy (>=300m, makes energy, immobile) is one CLASS with
one site, enforced at the Requests chokepoint every entrance passes.
Validated over 32 4v4 Comet games (76cd434): zero episodes, peak concurrency 1
on 144 of 148 team-slots. `python tools/energy_parallel.py <run>` is the
instrument; the audit carries it as `parallel-big-energy`.

1. **`t1-eco-with-afus` is the price of the rule** — ~54 T1 generators and
   converters left standing with AFUS fielded, up from clean on the same seed
   before the gate. Serializing reactors sends more asks down to the sub-bar
   generators, and obsolete-reclaim is what should be clearing them. Not yet
   attributed to a reclaim rule; measure before touching one.
2. **The gate reads a ledger that drifts in team games.** `ledger-drift` fails
   32/32 in 4v4 (25 missed events; clean in every 1v1) and was already failing
   in the first 4v4 of the day, BEFORE any of this work — pre-existing, but now
   load-bearing, because `ComBigEnergyRising` is what decides whether a second
   reactor may be founded. Validation passed regardless, so the drift does not
   currently defeat the gate; that is luck, not design.
3. **No wealth exemption, deliberately.** Three were tried and each was the
   clause the overlaps returned through. His older "more than 1 of any building
   at one time if we are wealthy enough" still governs buildings at large; this
   class is now strictly serial. If he wants reactors to parallelize when rich,
   that is a policy change and needs a number he agrees with, not a re-derived
   guess.

## 2026-08-30 — the wall revamp: LANDED (75b2d97), residue open

His ask: towers blobbed at the start area; he wants a wall wrapping the base,
joining allied walls, advancing with expansion, rear towers reclaimed, tiers
rising — explicitly NOT the front-line or base-border models. Landed as
`apex_wall` (default on): perimeter slots on the building rim
(protect_wall.as), the open-slot target pull, the held-ahead stranded
retirement, and the frontier anchor (the furthest capped mex along the enemy
axis, midline-bounded). `tools/wall_check.py` and `tools/wall_map.py` are the
instruments; `lineFill` is the one that measures sealing.

1. **Walk churn eats the early sentry** (vs hard, 20260830-190332). The
   memo-starvation fix got the commander WINNING the sentry election at 2.6
   min; the re-election roulette then swapped his task for energy/mex six
   times mid-walk and the first tower stood at 12:00. Same class for every
   want: a walking builder re-rolls every update and any different-build-type
   winner replaces the task. The fix is election-to-standing stickiness during
   a committed short walk — a measured change on its own, NOT more pricing.
2. **The line advances faster than it fills** (smoke 20260830-184343). Every
   defence election lands exactly on the wall (wallD=0 throughout), but
   lineFill sat at 0.00 until minute 14: each newly capped mex steps the anchor
   forward, so the wall chases the frontier instead of sealing, holding, then
   stepping. Candidates, untried: quantize the advance harder (512), or anchor
   on a robust percentile of forward mex depth instead of the max.
3. **The early seal is late.** His doctrine: towers exist to stop leaks into
   the backline; "oftentimes its solved by 4 or 5 well placed turrets". The
   first defence election lands at a healthy 5.0 min, but the auction takes a
   420m HLT (TeamBestTowerPower scales the sentry down against it inside T1)
   and walk+build runs minutes, so nothing STANDS before ~8-10 min. Candidates,
   untried: sharpen apex_def_ttd_h so short threat windows favour the
   20-second sentry, or scope the power routing to tier gaps only.
4. **The commander never elects defence** — eco wants outbid the wall pull. He
   permitted commander wall work; it is not price-favoured. Ask him whether the
   commander should carry an explicit early-wall preference before nudging it.
5. **His 2v2 expectation — "a clear line of towers across the map" — is NOT
   met, and the blocker is the army, not the placement.** The machinery sites
   correctly (1v1 win, 26 towers, 69% enemy-side), but three 2v2s vs BARb
   medium lost on army/eco, the front collapses to the base corner, and the
   wall honestly concentrates THERE — which reads on screen as "towers in the
   middle of our base like always". See the 8v8 entry; re-show him a 2v2 after
   the team-fight work moves.
6. **Front::GateChokes returns ZERO candidates in every 1v1** (`lineSpots=0`
   all game), so the concentration-doctrine gates are inert and the wall
   carries everything. Pre-existing, now load-bearing.
7. **Untested, in order of risk:** tier progression on the wall at high economy
   (the T1-late ×0.15 discount should put T2 guns up late — verify in a long
   game); ally-join is smoke-tested only, never visually confirmed to meet.
8. Towers finish ~200 elmos inside the wall because it steps outward during the
   walk. Harmless at one quantum; the at-build rim/core split reads worse than
   election siting (election wallD≈0), so judge siting at the election.

## 2026-08-30 — all-angle defence: closure-ring candidates (LANDED, awaiting measurement)

His ask: "on some maps you might be completely surrounded. So our angle of
defense has to be really flexible." The closure ring already PAID for every
approach bearing a post newly closes, but no candidate ever stood on a cold
bearing — guard sites hug our metal and shift toward the enemy centroid,
FrontBuildSpots offers only hot bearings, and ShieldArcSpots/NetSpots had ZERO
callers. The credit existed and nothing could collect it. `apex_def_ring` now
offers one candidate per OPEN ring bearing, pulled inward so the def's own reach
covers the ring point; map-edge bearings are walls and are never offered. No arc
constant — a surround makes every on-map bearing a candidate, priced
individually.

OFF-path while `apex_wall=1`, which is the default, so this is measured only if
the wall is switched off. Read it via `apex: defsite ... ring=N bestRingGain=`
and `apex: fronttowers ... closure=`. Verify on a long high-economy game: at low
income DefenceTarget is a handful of light towers and ring sites correctly lose
to mex floors.

## 2026-08-30 — 8v8 vs 1v1 gap: the measured deltas from the first clean Supreme Isthmus soak

His report: "We perform worse on 8v8 games than we do 1v1 games." First
instrumented 8v8 since the AV fix (Supreme Isthmus v2.1, per-side 8, +50%,
16 min, timelimit, matches/soak8v8-s1). One game -- directional, not proof.
Side sums, us vs stock:

- FIGHTS: we built MORE army (70.5k vs 57.9k) and held more standing
  (26.9k vs 22.3k) yet traded 0.48 -- killed 12.4k, lost 25.7k; damage
  101k dealt vs 150k received. His complaint #1 at team scale; the
  DefendTask home-muster/towers fix (commit 28acfa1) targets this. Re-soak
  and compare this exact line.
- INCOME diverges late: final 289 vs 364 m/s on EQUAL mex counts (62 vs
  61, and we hold MORE mohos 11v8). Two of our eight sat at 2 mexes at 16m
  (t0, t2) with huge energy grids (t0 eInc 663 at mInc 19) -- expansion
  stopped, spend went to energy/BP (t0 budget line: bp=0.48 vs target
  0.17). Their stunted players have causes (t12 comm died); ours look like
  threat-priced-out mex wants (risk lines: threat 226-259, short=1.00).
  UPDATE same night: commit 5918909 aligned the PickSpot sweep on
  FoeAnchor (it still read the mobile centroid -- the documented collapse
  frontline.as:757 cures), but the re-soak (soak8v8-s1b, same settings)
  did NOT move the needle: pastFront intervals 356-1347, apex mex spread
  [2,3,4,4,7,8,11,14] vs stock 63 total. The interval counters aggregate
  many sweeps, so high counts may just be the enemy half of 90 spots
  legitimately refused -- they cannot distinguish "axis collapsed" from
  "half the map is theirs". ANSWERED same night by the sweep instrument
  (soak8v8-s2, seed 2): geometry is NOT the binder. Every player's sweep
  reads a healthy axis (span 6,680-9,345 elmos) and keeps 40-56 of 90
  candidates; pastFront refusals are the legitimate enemy half
  (~35/sweep). The worst player (t6, held=4) PRICED mex wants all game
  (claimed=0, noOpen~0), WON the auction 35x, EXECUTED 28 claims -- and
  lost zero cons and zero mexes. The claims CHURN: exec positions scatter
  map-wide (armcom #19794 sent to 6456,312; spot 4520,7208 claimed twice
  by different cons), and on a long walk the 3s re-election window lets a
  local want outbid the mex claim mid-walk -- the abandonment leaves no
  corpse, no task-die, no log. 1v1 walks are short, so claims complete
  before churn strikes; 8v8's taken-near/far-remainder geometry makes
  every claim a long walk. This is the commitment/stale-count bug class
  the velocity plan's commitment ledger targets -- the likely fix shape
  is claim stickiness priced by the walk already paid (sunk walk raises
  the incumbent's price), not a gate. Next instrument if needed:
  claim->finish conversion by claim distance. Keep 5918909 (the
  documented cure's missing half, strictly more stable).
- AIR is a team-scale write-off: all 8 players built an armap; the elected
  assassin (t4) logged "air lead NOT armed" from 11m to end while
  non-leads t5/t6 launched 5-6 bomber home waves scoring dmg/bomber=0 at
  0.20 survival. The non-lead frozen-bar fix (entry below) is now
  evidenced: waves launch undersized and die, and the lead never commits.
- DEFENCE: stock spent 20.1k on defence vs our 9.3k, and our defence was
  100% T1 towers (audit defence-tier flag) with advanced cons fielded.
  His concentration doctrine wants the opposite lean.

## 2026-08-29 (late night) — PERF: his target is <10% of tonight's AI cost; campaign open

His ruling, watching a laggy ~1500 m/s 1v1: "to be OK the perf needs to be
less than 10% of the impact we currently experience." Baseline measured on
that game (37 game-min, Archsimkats +150%, 655 builders at the end):
`apex: perf AiFrame` peaked at 10.6s per 60 game-sec (~18% of sim), with
30-146ms single-frame spikes every 8 frames continuously. Attribution:
hk.maketask.builder 7.0s/min of it (~66%) — 407 full want-stack elections
a minute at ~9.5ms plus exec.want at ~6ms; the C++ remainder (threat maps
etc.) is ~3s/min and second-order. Landed tonight, unmeasured: the
election memo (six proposers shared per asker-def for 1.5s, evicted on
execute), the rezzer-chain 2s gate, exec.orph/exec.pend/exec.k* and
dec.* attribution timers. STILL UNATTRIBUTED: the exec tail (~6ms/call —
exec.pend measured 0.02ms, so it is the per-kind Enqueue/dispatch), and
want.protect's fill residual (~3.3ms/call at scale, cap already 2/frame).
Compare `perf sec`/`perf AiFrame` on the next long high-income game
against the numbers above; the 10% bar is AiFrame ≤ ~1s/min at that scale.

Round 1+2 MEASURED (repro-4: Archsimkats +150% seed 2, WON, 1675 m/s,
395 builders, f=63000 window vs the baseline's same window): AiFrame
10,054 -> 4,652ms/min (-54%), worst frame 172 -> 69ms,
hk.maketask.builder 6,975 -> 2,265ms (-68%), full stacks 407 -> 148/min,
exec.knano 11.7 -> 3.4ms/call. dec.deferred fired 5 times all game (the
budget is a backstop).

Round 3 (C++, DLL rebuilt): `perf split` says ProcessJobs is ~97% of the
frame; inside it the ally FRIENDLY LIST was rebuilt 630x/min at 1,151
units (delete+new+engine call each, 1.83s of every game-minute) because
any task update demands it. Throttled to at most 2/sec -- verified 113
calls/283ms at 930 units.

Round 4 (his "do A and B" ruling): (A) IBuilderTask::Reevaluate now asks
the script market at most every 3s per walking builder (commanders and
rez bots exempt -- their safety lives inside the election; completion/
abort still elect immediately). Measured: hook calls 3,047 -> 1,023/min,
hk.maketask.builder 1.35s/min, AiFrame 2.4-2.7s/min maxMs 47-83 at 444
builders, 0 exceptions, won. (B, slice 1) DeathWalk's GetEnemyCostAt
engine sweep cached per cell/3s -- want.mexup per-call halved, mex
pipeline unharmed (94 mexes / 30 T2 on the validation win).

STILL OPEN toward his <10% bar (~1s/min): the board at 444 builders
reads want.protect 409 + fills ~500 (the memo-miss fills are now the
biggest script item), factory hook 262 with 61ms max spikes, and the
next long 650-builder game must confirm the at-scale total (projection
~2.5-3s/min there). B's remaining slices, in order: the protect fill/
election split (core per stamp, walk pricing per asker), then the full
market snapshot if still over. `perf AiFrame`/`perf split`/
`perf friendly` + the section board are the instruments; his watched
feel is the acceptance test.


Folded in from the 2026-08-29 spike entry: the two prescribed protect-stack
optimizations LANDED (RiskFill/RiskFillSiege frame memos, ClosurePrep memoized
on the field stamp, DefSiteFill capped at two fresh fills per frame). Worst
single call on a 12-min smoke: 12ms against a 126ms baseline — but that
baseline was a 43-min base, so it is NOT re-measured at scale yet. Do not add
more candidate generators to the protect stack before that measurement.

## 2026-08-29 (late night) — air release: non-lead home-wave still tracks the live want

The lead's release gates were all indexed to ScaledBombers(), which grows
with income AND their AA — measured 30/93 held forever, no strike all
game, then bar=-1 on the next watch because the market built the plants
and the assassin never "committed" at all. Fixed for the lead (frozen
commit snapshot + decaying deadline bar + standing-wing clock + the
stood-down wing still spends at deadline). NOT fixed: the non-lead
`apex_air_home_wave` release still compares against the LIVE
ScaledBombers() — same treadmill in team games; give it the same frozen
bar when a team game shows allied bombers hoarding.

## 2026-08-29 (late) — ZERO Titans at 500 m/s (his report; prodrank instrument landed)

"we have 2 players pulling around 500m/s income and neither one has made
any titans. We lose these games because we don't make those units. The
last adaptation didn't seem to change anything at all." At 500 m/s the
afford window is NOT the binder (x0.78 at 120s, x0.55 even at the old
60s), and armbanth's core worth ranks #3 in the game — by the visible
arithmetic (ppc/linePPC ~1 vs Vanguard's ~0.03) it should DOMINATE the
gantry draw. Something zeroes it upstream that no log shows, and hosted
games leave no infolog. `apex: prodrank` (production.as, defrank's
pattern) now prints every candidate per line per minute with draw weight
or drop reason (:aff0/:gap0/:eco/:amph). Read it on the next high-income
game; the term it names is the fix.

## 2026-08-29 (late) — behaviour.json power overrides leak into production worth (survey open)

The armthor x0.1 case is fixed by counter-mod (commit dac0946), but the
class remains: 22 defs carry hand-set "power" values written for THREAT
reading, and UnitCore inherits every one as production worth via PowerMod.
armvader sits at x100 (produces nothing today — a crawling bomb priced as
a god is a landmine, not a bug yet); armstil x0.05, corbw x0.1, several
aircraft at x0.5. Audit the 22 against the worth model's own means before
the next composition complaint lands on one of them.

## 2026-08-29 (arena) — amphibious units act cowardly (OPEN)

apexearth, watching arena rounds: "Not sure why but our amphibious tanks
act very very cowardly. Same with platypus, maybe it is an amphibious
behavior we have." Suspects, unattributed: (1) the standoff-row system
holding short-range brawlers at max range (apex_brawl_pass=0 default --
the arm built for exactly this measured neutral at the OLD noise floor,
re-test with the big-battle instrument); (2) amph-specific role/terrain
logic in CircuitAI (diver/submarine gates, water threat layer). Attribute
before touching either.
ATTRIBUTION 1: retreat threshold is NOT it (floor 0.08 + cost/3000 caps
Platypus at 17% hp, Triton at 50%); no amph gate exists in fight logic
(grep: amph only affects squad grouping affinity). Remaining suspect is
the standoff ring holding short-range rows at the squad's longest range
-- apex_brawl_pass is the existing arm, re-test with the big-battle
instrument; if positive, flip its default.

## 2026-08-29 — THE CONVERSION FAILURE: a 3.5x economy loses the 1v1 anyway

Measured on decision-length games (50m caps, 8 per map, winrate-comet /
winrate-glacier): decided results 2-10 vs stock overall. On Comet we led the mex
race 18v14 @15m, 45v29 @25m, 102v29 @35m — three and a half times their economy
— and went 2-6. Five of those six losses ended with OUR COMMANDER dying at
fwd 0.00-0.18 (AT HOME) between 18.7m and 32.7m: the economy never killed them,
the game ran long, and one breach decapitated us.

The eco lead converts into mexes, not into finishing power or commander safety.
Suspects, unattributed: the killing blow not firing or not finishing on a won
economy; home defence plus army-at-home losing to the late push despite wealth;
overflow (12% metal-wasted flag) meaning the lead is partly paper. Use
decision-length games and the death ledger — a 6-game arm cannot see this.

## 2026-08-29 — UpdateWithdraw throws "Index out of bounds" (FIX LANDED, awaiting a clean game)

2 occurrences in one battery game, 7 in the first 14 min of the 08-29
Small_Supreme watch (Function: void UpdateWithdraw(), Line: 500 — the
gCombatSent[i] region, withdraw.as). ROOT CAUSE READ FROM THE CODE, not
raced: pass 1 walks the registry descending and removeAt(i) on a dead
entry shifts every aliveSlot already cached (all recorded from ABOVE i)
down one — pass 2 then reads a neighbour's reissue stamp, WRITES the
wrong unit's stamp even in bounds, and the highest cached slot indexes
past the end. Fix: each removal decrements every cached slot. Delete this
entry when a long game shows zero UpdateWithdraw exceptions.

## 2026-08-29 — flanking: charger question RULED, two structural gaps remain

His ruling (same day): Behemoths through the middle (slow), Titans may take
the side — and the classes were never actually conflated in code (armthor
has no melee attr; it is a colossus by cost and already rolls the flank
via). The charge doctrine (never recalled, richest-in-reach set-target)
landed in 0ab7ded. Still open, structural: (1) the flank via needs an
approach over apex_flank_min_dist=1200 — tight-map targets sit closer, so
his Glacier games saw zero flanks (vs 13 on Isthmus); (2) DEFEND-pool
fights, most of a defensive game, have no flank concept at all. Both are
design work, not knobs.

The geo-abandonment check (his ask: con abandoned a damaged build while
allied combat idled nearby) needs the `apex: con-retreat` line to carry
POSITION and the def under construction — both in scope at the log site
(BuilderTask.cpp OnUnitDamaged). Add on the next DLL build cycle, then the
audit joins it against BARAI_ARMY snapshots (idle = position-stable combat
units within ~800). The flank detector (every attack entered the enemy's
front arc) reads BARAI_ARMY tracks alone — no new field needed.

## 2026-08-29 — long-range survival: two residues after the walk-in fix

The walk-in orders themselves are fixed (radar-aware `prefer` gate + long-gun
hold in `CCircuitUnit::Attack`; `apex_arty_mass` routes mobile arty into the
squads — see the commit). Left open:

1. **The ride to the squad is still a raw fight order.** `CSupportTask`
   (snipers via the `anti_heavy_ass`→SUPPORT binding, mobile radar/jammer)
   walks recruits to the nearest squad with `CmdFightTo` straight-line to the
   path end (`SupportTask.cpp` Start/ApplyPath). A 455-sight sniper crossing
   contested ground on a fight order can still stop-and-trade on its own
   acquisitions until it arrives. Squads reposition it on arrival, so the
   exposure is the trip only.
2. **`apex_arty_mass=0` arm keeps the old CArtilleryTask** — statics-only
   FindTarget, raw engine attack, CFightAction travel. If the A/B retires the
   OFF arm, nothing runs that code; until then it is the control, not a fix
   target.
3. **"Build up their numbers"** (his 2026-08-29 ask) — long-range composition
   share untouched; the army market prices ARTY off enemy static cost only
   (`market/army.as` counter). Judge after survival beds in: units that stop
   dying compound on their own before any pricing change.

## 2026-08-29 — builder retreat trigger is a hair trigger (his policy call pending)

Every builder retreats at 80-89% health (`behaviour.json` `retreat.builder
[0.80, 0.89]`, per-unit roll) and walks to the crow-flies-closest haven.
Measured the first game the `apex: con-retreat` line existed (s11 2v2, low
contact): 8 switches in 20 minutes, armck at hp=0.85-0.86 walking 924, 1475
and 3218 elmos — his sighting ("long walk for no big gain") exactly.
Stand-and-heal (ec2913b) removes the walk only when the con is already
inside a haven's assist reach. RULED 2026-08-29 ("Threat-gate it"), after
the eco cost was measured: 43 con-retreats in one Glacier Pass game, corck
at hp 0.81 walking 2400-2900 elmos, 42 mex elections -> 12 standing mexes
vs stock's 17. LANDED (apex_con_scratch_gate, BuilderTask.cpp): above the
stand floor a builder retreats only when the known attacker's gun reaches
its spot or the threat map covers it; below 0.5 hp always retreats. Awaiting
a measured `con-scratch` vs `con-retreat` count on his maps to close.

## 2026-08-28 (night) — THE OVERFLOW CAMPAIGN: residue only

Nine goals, all LANDED and MEASURED (commits 709e550, 1d1f1b8, 224a8c4,
6bb4561, d3fe925, 860e8f0) — super-site relocation, the strategic market's
serialization when rich, the overflow ladder, T1 air after T2, front towers and
mex guards, the 156x exec loop, the eco-player AFK, nano turret reclaim, eco
cluster split. Both reserved rulings were taken: T3 pacing became
`apex_unit_afford_s` (60s of income fades every unit bid toward zero at the full
bill, no tier table) and front towers got `apex_def_setback` (250). What is
left:

- **armmex unreach-safe churn, 156-228 per game**: mex claims elected at spots
  the walker cannot safely reach. The refusals are correct; the elections are
  waste. Election-side threat pricing is the lever if it grows.
- **armmakr (T1 converter) reclaim-rebuild loop, 11-16 per game**: the converter
  obsolete law eats makers the convert want then re-buys. Same shape the plant
  retire law had; needs its own waiver/window pass.
- **Radar at the front dies why=unreach-safe** (290 sense execs for 29 radars) —
  deliberately NOT exempted: walking a builder into fire for an unarmed radar is
  a real loss. If forward intel is worth more than that, it is a pricing
  question, not an exemption.
- **Tower SITING depth is a policy ruling, not a bug.** Completion is fixed (47
  towers finished, 4 defence-task deaths in a 57.9-min game); elections win front
  sites and towers still land rear/mid. Superseded in practice by the wall entry.
- The task-die `why=` distribution is this family's instrument; any new face
  shows up there first. A LOSING base abandons everything (719 nanoframes in s43
  vs 87-312 elsewhere) — never read that as a regression without a same-outcome
  control.

## 2026-08-28 (night) — THE ORDERS-THAT-DON'T-STICK FAMILY (next campaign, top priority)

One disease, four faces, all measured today:
1. **Mex guards never materialize** (his report: "we turned off the logic to
   make sure we build defensive turrets on our mexes... we lose them all").
   NOT the pricing: in his watched game (watch-vsmedium-s125) asset sites
   WON the defence election **677 times and 14 towers were built** (10
   standing, all in the base core; mexFloor 1,890 and the target lifted
   correctly). 98% completion failure.
2. **Front towers**: wonFront=63, built 2, standing 0 (same game; standing
   ISSUES item since 2026-08-27).
3. **The eco commander's 156x exec loop** (same converter, same occupied
   square, engine refusing every order — fixed at the Take door by the
   backoff, but the PLACEMENT that returns occupied ground is unfixed).
4. **The abandonment class**: 42 nanoframes abandoned in one game
   (cormex=22), 'finish before founding' flagging all day.
The common shape: an election is won, an order is issued, and between the
executor and a standing building the order dies -- placement on occupied
ground, task killed same-frame, builder peeled/re-elected, frame never
resumed. The dig is the task lifecycle from `apex: exec` to BARAI_BUILD:
pick ONE won defence election from s125 and trace its task id to its
death. Note: the TaskRemovedInner exception storm (fixed tonight) was
ABORTING the removal hook mid-flight all day, so ledger drift and Forget
misses may have been feeding this family -- re-measure completion rates
FIRST on the fixed build before digging deeper.

## 2026-08-28 (late) — the eco commander's 156-exec loop IS the AFK

His "eco player goes AFK" reproduced on the 15m SI 8v8 tell
(matches/si8-fix2-15m-s104): t7 (rear specialist) commander idle 49% vs
10-20% line teams, income 32 m/s at 13m (POORER than the line players).
Mechanism pinned: corcom #20590 elected AND EXECUTED the same
convert:cormakr at the same position (367,9665) **156 times**, one per
task update, gain=1.17 -- the order never becomes a task that sticks and
nothing logs an abort (so the abort-backoff never trips; suspect the exec
returns an existing covered/held task the unit never walks to, or a
same-frame silent rejection below the TaskRemoved hook). Next session:
trace ONE of those execs through Requests::Take's branch logging (which
Log(want,...) label fires 156x) and the C++ task lifecycle. Also open:
WHY the rear economist is the poorest player at 13m -- its pocket runs
out of T1 work and nothing routes it to T2/mohos/assist; the commIdle
number on the tell is the regression check. (Residue moved from the deleted
ArmyTarget entry, same player: the eco-role election never fires on
line-abreast starts -- 0 of 92 targets samples showed eco=1.)

## 2026-08-28 (evening) — T3 production pacing: the early gantry's products eat the mid-game

The gantry-by-100-team-m/s change works as asked (elections 27.8-28.6min ->
7.4-10.9min, gantries FINISHED on both apex teams, T3 fielded 50-55k vs
8.4k) and costs nothing through minute 10 (income tracks the control
exactly). The damage is 15-25min: the standing T3 line pulls Juggernauts
(20k) and Demons (12k) into the mid-game, the army flatlines at 20m while
BARb masses 43 Goliaths, and s21's side income collapsed 1045->212 while
the control compounded 1836->2537 (side metal 776k -> 393k; s23 640k ->
543k). BARb won the same game fielding 3 KORGOTHS — T3 is not the sin,
SEQUENCING is: they bought mass first and T3 from surplus; we bought T3
instead of mass. The lever is production-side (what a T3 unit bid may cost
against income mid-game — an affordability ramp like the supers carry),
NOT the gantry want. Decide with apexearth before wiring: it is his
composition philosophy. Evidence: matches/gantry-on-s21 vs
matches/allyshare-on-s21 (same seed, same day, one change).

## 2026-08-28 — nano turrets cannot be told to reclaim (mechanism gap)

His ask: "We have a lot of constructor units & turrets which could be doing
this [reclaiming old buildings]." Turrets is the blocked half. Verified in the
DLL source: `CmdReclaimUnit` exists in C++ (`common/ReclaimTask.cpp:83`) but
has no AngelScript binding, and the static-task route (`TaskS::Reclaim` →
`CSReclaimTask`, `task/static/ReclaimTask.cpp`) is area-only AND aborts
whenever `IsMetalFull()` — exactly the overflowing-bank state where space
reclaim matters most. So idle nano lathe cannot be pointed at an obsolete
neighbour from script today. Fix is C++: either bind `CmdReclaimUnit` on
`CCircuitUnit` or a unit-target static reclaim task without the metal-full
abort. Until then reclaim parallelism is constructors only (the claim
registry in `want_reclaim.as`, 2026-08-28).
His note 2026-08-28 (night): "nano turrets were able to reclaim prior to
us doing the big reimagining of the AI so maybe it really is there but we
just didn't see it" -- consistent with the mechanism above: the stock
static reclaim task exists but aborts on IsMetalFull(), and at his +100%
regime the bank is pinned full, so it aborts always. The C++ fix is the
same either way: drop/gate the metal-full abort (space reclaim matters
most exactly when full) or bind CmdReclaimUnit.

## 2026-09-05 (morning) — what he saw in the first watched game on the committed build

Seed 16, lost 17.5 min, lab 13.7, commander 17.4. His words and the mechanism:

- **"The commander always seems to make his lab in the same spot, even when
  it's really far from the last mex he makes."** Plants stand at the base
  anchor = the commander's START position, the only candidate; the lab want
  paid the walk back (t=2534) and still won. His ruling: *"the base anchor
  should depend on where our buildings are placed. So if we made 3 mexes
  then our anchorpoint is between them all."* Built: before the lab stands
  `Base::gAnchor` tracks the centroid of `Market::gPfPos`; the farm latches
  only once the anchor is final. Smoke: lab at 557,6626 beside mexes at
  504,7176 / 552,6872.
- **"Wind on this map is 5-25... we should be making more wind but I still
  see mostly solar."** The game chose 8 wind / 6 solar; every solar carried
  `why=estall` -- his own hard-stall ruling (basic solar under 300 E/s).
  His answer: *"make energy earlier, that'll save us metal in the long
  run."* Built: `LineDrainE()` -- the production draw of factories in
  flight or standing idle, which the pull does not show yet -- is added to
  the energy spot price (`ECostSpot`), so the price rises before the lab's
  first unit stalls us; `apex: energy ... lineE=` shows it.
- **Commander deaths decide the losses (17 of 36 last night, 16 inside the
  retreat task).** Seed 16: the com-fwd MEX exemption (added 09-04) sent
  him to a 0.45-value spot 1900 elmo out at 12.9; hurt at 14.5, then a
  3-minute retreat loop along the map edge (rear haven with no lab alive),
  caught at 17.4. The exemption is removed; his "commander stays home"
  ruling stands (spots inside 400 forward remain his). The retreat-path
  loop itself is still open: `GetRearHaven` pushes the haven 900 elmo away
  from the enemy centroid and the target flips as that centroid moves.

## 2026-09-04 (night) — what he saw in the fair raid game, and the mechanisms

Watched level 5 (five groups from five bearings, raiders sized to half our
army's metal, no turrets, passive opponent), seed 4, 12 minutes: 28 buildings
lost over four waves; wave 3 had a raider alive at game end. His reports and
what the logs say about each:

- **"The first units out of the factory are rocket bots and thugs."** The
  price model already puts the Pawn first by a wide margin: at 1.5 min
  `prodrank` read armpw=2127 vs armham=497, armrock=448, armwar=165 (value
  per metal). The proportional draw hands the 34% of non-Pawn value to the
  first two slots often: census over 79 raid games, both first orders Pawns
  in 43, a Rocko/Thug/Warrior among the first two in ~35. The draw, not the
  price, is what decides the opening. The Flea reads `gap0` (its role has no
  target early) and is never a candidate. OPEN: how the opening draw should
  be sharpened is a policy question for him.
- **"Almost 5 minutes in and no radar."** Across 109 level-5 games the first
  radar finished at a median 8.5 min (min 1.9, max 10.9); 243 radar orders
  were executed and 99 radars finished. Radar's gain is
  `(assets + army) * apex_insure_rate(0.0003) * unseenFrac` -- at 2.8 min
  gain=0.45 for 111 metal against a mex's gain=15.9 for 72, so per metal it
  bids at about 2% of a mex and is elected only by draw luck; and the sites
  it is elected to sit on the base edge where the raiders kill it (two of
  three radars in the watched game died to Pawns within a minute of
  finishing). OPEN: the first radar's price. The insurance rate is a number
  pulled out of the air; his directive is that vision is the precondition of
  every reaction.
- **"Squads don't separate; the whole army chases."** `commit` (peak of our
  units within 600 elmo of a raider / army) reads a median 0.90-1.00 across
  every level-5 set: at some point during each wave essentially the whole
  army is beside a raider. The mechanism is in C++: every new DEFEND-pool
  member is sent to `GetDefenceStand()`, which with no towers is the base
  centre with a 256-elmo jitter (`CDefendTask::Start`), and the pool elects
  one target for all of its units. The gadget now logs `armyRms` (army
  spread from the base centroid) at each wave so a fix can be measured.
  OPEN: the posting design -- greedy k-centre over the base's buildings
  (each idle guard stands at the building whose nearest guard is farthest)
  minimises the worst reaction walk without a cap or a number; needs his
  sign-off and is C++.
- **"The commander should spam D-guns while he has power."** `CDGunAction`
  fires whenever the D-gun is reloaded, its energy cost is under 90% of the
  bank, a target is in radar/LOS within range (1.1x D-gun range or LOS for
  fighter tasks; D-gun range with a paid walk-in for builder tasks), passes
  the trajectory ray, and -- unless the def carries `dg_cost` -- has
  influence above THREAT_MIN. The combat log now counts `dg` (D-gun hits)
  and `dgm` (metal killed by the D-gun) per team, and `test_raid.py` reports
  both per wave. Fair baseline, 8 games: 0 D-gun hits while the commander
  killed 4-13 raiders a game with his laser. The energy gate was moved from
  90% of the bank to the whole bank (a commander stores exactly the 500 the
  shot costs) -- INERT: still 0 hits in 8 games. The gate trace
  (`apex_dgun_log=1`) then showed the action choosing a target and issuing
  the order 50+ times a set with energy 800-1250 in the bank, and the
  combat log's `mfo` counter showed 6-33 manual-fire orders per game
  REACHING the engine -- yet no manual-fire weapon ever dealt damage in
  any game (`[BARAI_DGUNWD]` never echoed). The `[BARAI_MF]`/`[BARAI_MFNEXT]`
  trace found the mechanism: every D-gun order was followed IN THE SAME
  FRAME by a move (cmd 10) and a stop (cmd 2) on the commander, which
  replace it in the engine's queue before the shot. Fix in the DLL:
  `CCircuitUnit::IsDGunHeld` -- after a manual-fire order every
  queue-replacing helper (move, fight, stop, build, repair, reclaim...) is
  skipped until the shot fires (reload frame advances) or the order's
  window passes. Also: commanders now carry `dg_cost` (D-gun by target
  cost, no minimum-threat filter) and the walk-in worth bar defaults to 0
  (his "spam d-guns" ruling), read back via `apex_dgun_close_worth`.
  With the hold in: STILL 0 hits (8 games). The queue trace explains it:
  at the harness's full speed every manual-fire order arrived at the engine
  targeting a unit that was ALREADY DEAD (`dist=-1`, queue empty a frame
  later) -- the order lag that scales with sim speed (CLAUDE.md) is longer
  than a raider lives under the commander's laser, and the same-frame
  bursts of 3-11 orders are several frames' worth landing together. At
  `--speed 3` the order does enter the queue (`queue=105`) against a live
  target. Whether the shot then FIRES is what `dgp` (D-gun projectiles
  created, new in `[BARAI_DMG]`) measures. At `--speed 3`, 9-minute games:
  walk-in bar 0 (new default) fired 5/4/2 D-guns on 7/6/8 orders; walk-in
  bar 1 (the old rule) fired 2/4 on 2/4 orders in the two games that
  logged. So the D-gun fires at 3x either way and the hold lets every
  queued order fire; the zero walk-in bar roughly doubles the orders.
  Three games an arm -- an anecdote. The full-speed raid test is BLIND to
  the D-gun by construction.
- **Guard posts, measured.** `military/guardposts.as` +
  `CDefendTask::FallbackPosts` (switch `apex_guard_posts`, default 1).
  Buildings lost per 8-game level-5 set, raiders at half our army: posts
  ON 70 and 69 (two sets) against OFF 91, 76 and 98 (three sets, same or
  older DLL). Late-wave army spread from the base centroid 891 with posts
  vs 1116-1670 without: the pool stays at the buildings instead of
  trailing off after a chase. Directional, one-in-four-ish; not yet
  beyond the noise of two arms. The pools do merge with posts on (walk
  lines show pools of 1-5). Next: a 16-game paired A/B before believing
  the 25%.
- **Coverage as army demand** (his "we still need a lot more light
  units" and "quantify the value of grunts... the speed"): the post model
  keeps virtually posting the fastest-per-metal unit our lab makes until
  the base is covered; the count is `CoverNeedM()`, floored into
  `armyGap`, and `PatrolShort()` reads the uncovered share. Measured, 8
  games: combat orders 140 -> 174, Pawns 73 -> 88 (share unchanged at
  ~51%), buildings lost 55 -> 67. NOTE the harness sizes raiders to HALF
  OUR ARMY, so more army cannot reduce losses in this test by mass -- it
  measures positioning and reaction only; a fixed-size raid arm is the
  test for "does more army help". The reach reads ~320 elmo (a wind dies
  in ~3.6 s under a Flea-class gun), so the need early is 17-32 Pawns.
  Second cut: the coverage share of the gap priced by cover-per-metal
  (speed/cost): Pawns 132 of 210 combat orders (63%, from 51%), six of
  eight games open Pawn-Pawn, buildings lost 69 (raiders scale with us,
  so unchanged as expected). The remaining dilution is the role prior
  (`roleW` 0.35-0.46 for the Pawn once raiders hold a sixth of the army);
  third cut lets the coverage share bypass it: Pawns 150 of 207 (72%),
  openings Pawn-Pawn-Pawn in six of eight, buildings lost 52 (the lowest
  of ten fair sets: 98, 76, 88, 92, 70, 69, 91, 67, 69, 52), economy
  unchanged (built 4900 vs 5248 in the DLL-only arm, mex 6 vs 5, metal
  lost 840 vs 1225). Still one 8-game set per cut.

Harness changes the same night: the opponent is a passive NullAI (stock's
own raids were arriving at ~4 min and being counted against the scripted
waves, so every earlier level-5 number carries that confound); the army
pin is gone and `dev_raid_ratio` now sizes the raiders from our army
(metal / ratio, roster proportions, one per group minimum); a relative
`--write-dir` is made absolute (the engine resolved it against its own exe
folder and the first watch game's log vanished into the install).

- **"When the enemy kills our mexes we don't seem in a rush to rebuild
  them... maybe they refuse to build there because of some sort of threat
  memory?"** Yes, and the memory is the FRONT ANCHOR, not the threat map.
  `Front::Scan` accumulates `gFoeSeen` per grid cell (+1 per scan the cell
  reads enemy influence, x0.995 per scan otherwise -- a ~23 game-minute
  half-life at the 10 s rescan), and `gFoeMid` is the `gFoeSeen`-weighted
  centroid. `FoeAnchor()` returns `gFoeMid` once anything has been seen, and
  `PastFrontFrac(spot, MEX_FAR_FRAC=0.92)` in `PickSpot`/`ProposeMex`
  projects every mex spot onto the home->gFoeMid axis. Before first contact
  no enemy has been seen, the anchor is the engine's centroid and the axis
  spans the map (watch seed 6: `span=1797`, `0past+5own/30 cand=25`). The
  first raid is the first enemy influence ever seen, INSIDE our base, so the
  anchor lands on the raiders' corpses: `foeMid=1880,2624` at 3.2 min, ~200
  elmo from the mex it killed at 2432,2736 (the real enemy start is
  3221,1952), the axis shrinks to `span=1198-1400`, and 20-21 of 30 spots
  read past the front (`pastFront=211` then `875` per minute, `cand=1-6`).
  That mex was never rebuilt in 11 minutes; the two at 2048,3904/2144,4000
  waited 47-58 s and the one at 1520,3872 151 s. Same shape in the fair-base
  set (seed 1: span 1797 -> 730-948, 16-23 of 30 spots refused after wave
  1). `NoteDead` does drop the dead mex from the ledger correctly, so the
  spot is offered; the geometry veto is what refuses it. The anchor's
  comment says it is "structure-dominated" -- true once their base has been
  seen, which in a raid harness (NullAI has no structures) is never, and in
  a real game not until we scout; until then the anchor IS the last raid.
  Not fixed. Candidate: weight `gFoeSeen` by what was seen (a structure is
  territory, a passing raider is not), or fall back to the map's mirror /
  start positions until a structure has been seen.

- **"Do we in general feel like further from the base is more dangerous?"**
  Not in a graded way. Distance reaches the mex price through three
  things, and none of them is a slope. (1) Two BINARY vetoes on the
  home->foe axis: `PastFrontFrac` at 0.92 for mexes, `PastFront` at 0.72
  for other sites; inside the line every spot is equally safe. (2)
  `StreamSurvival`, the only graded term, is floored: hazard =
  max(loss-implied, gradient x foe/(foe+our army+cover), `apex_risk_floor`
  0.15), and with foe = 0.25 x our army the gradient term peaks at 0.20 AT
  THEIR START, so the price at home (survival 0.727) and at their door
  (0.667) differ by 8%; the watch game logged `hazard=1.25/ks` (exactly the
  floor) at home and at the worst mex in every sample. Against a real army
  the term reaches ~0.5 at their start, so the nearest ~30% of the axis is
  still flat. Either way it discounts the STREAM, never the constructor.
  (3) The constructor's own life is priced nowhere: `ValueOf` charges walk
  seconds at a wage and nothing for the chance the walker dies, and the one
  walk-risk term, `DeathWalk`, compares the con's METAL cost against
  `ai.GetEnemyCostAt`, which returns a unit COUNT (CircuitAI.cpp:2426), so
  it fired 0 times across every tournament run tonight (`deathWalk=0` in 8
  of 8 sets; `pastFront` 2k-23k per set). `mexdiag depthMax=1.00` in every
  set: a constructor took a spot at the enemy's own start. His directive:
  "I don't want us to be scared all the time but we need to understand
  that the further out we go the more likely our constructor is to die."
  Not built. Shape: P(con dies on this trip) rising with depth along the
  axis, charged as conCost x P against the want, with the two vetoes
  folded into it. And his second directive, same conversation: "The more
  army we have relative to our overall mass the safer we should feel." So
  the scale of the fear is our army's share of everything we own (army /
  (army + assets)), not our army against theirs: the existing hazard term
  reads foe/(foe+our army), which is the other ratio and reads 0.2 flat
  when the enemy is unscouted. BUILT 2026-09-04 late: `TripRisk` = depth
  x (1 - army/(army+assets)) prices every mex spot (stream x (1-P), con
  cost x P charged) and the two mex vetoes are gone; the anchor is
  `aiEnemyMgr.GetEnemyStructPos()` (new binding: cost-weighted centre of
  known enemy structures) else the mirror of home. Raid set L5: refused
  spots per sweep 22 -> 5, never-rebuilt dead mexes 9 -> 4 (anchor), rebuild
  lag median 76 -> 35 s but never-rebuilt back to 9 (trip risk: with no
  army the share is 0 and a depth-0.6 spot loses 60% of its value). The
  mirror of HOME is a poor pre-contact anchor on an asymmetric map (this
  map: mirror 1900 elmo from their real base); the enemy start BOX centre
  is the honest one and needs a binding (CSetupData has the boxes).

- **"Still one of the bigger issues we have is not making the early
  radar - its cheap and we should make it... bumping up the importance of
  radar/vision."** Mechanism: radar gain was (assets+army) x
  `apex_insure_rate` 0.0003 x unseenFrac = ~0.3 against a mex at 3-4 in
  minute three; first radar median 7.8-9.8 min across the night's sets.
  First reprice (warning = extra reach for posted guards, gain = hazard x
  asset metal newly covered) measured INERT: eyes 0-80 metal, because a
  posted Pawn is 54 metal of cover. Second reprice: the light-unit metal
  the warning makes unnecessary (virtual posting with and without warning)
  over `apex_army_fill_s`. The warning is (best radar range - unit sight)
  / fastest foe speed = ~10 s; a Pawn's reach without it is ~4-6 s of
  building life, so it doubles every guard's reach.

- **"We're still not spreading out well. Maybe because this round we made
  hardly any pawns"** (watch seed 8, the first radar reprice deployed,
  radar at 3.6 min). CAUSE, read from the live log: the guard-post cover
  model let one guard's metal count against EVERY asset within reach
  (metal covers metal, per asset), and a standing radar doubled that reach
  -- need went 54 Pawns (4.2m) -> 8 (7.2m) -> 0 (8.2m), coverShare hit 0,
  the role prior came back and the lab drew 20 Rocko / 14 Hammer / 8 Pawn
  (40 Pawn the game before). Fixed the same hour: required cover at an
  asset is `max(ThreatM(pos), worth)` -- the WAVE that arrives there --
  and uncovered worth is worth x shortfall share, the turret price's own
  arithmetic (`ShortWith`). Threat per asset refreshed every 10 s
  (`gPostReq`). `req=` on the posts line. reqcover set: radar in 8/8 games,
  first at 2.8 min median (was 7.8-9.8) -- the radar reprice bites; Pawn
  share 0.52 (was 0.58-0.61), buildings lost 78, built 5335 (highest of
  the night's sets). Watch seed 9 on that build: radar at 1.6 min, 13 Pawn
  vs 22 Rocko + 18 Hammer with need=30 Pawns unmet all game -- the
  coverage share of the army gap was PROPORTIONAL and the economy's army
  target drowned it. Changed to: cover is the first claim on the lab while
  any is unmet (coverShare=1). And the census at minute 12 showed 13 units
  in an ATTACK task promoted out of the pool, 4 Pawns in a stock RAID pool
  in another game: units bought for cover were leaving or invisible to the
  posts. Cover-worthy units (CoverPerMetal >= 1, ground, line combat) now
  join a MELEE-promoting Defend pool while cover is short. coverfirst set:
  posted units (2nd half) 4 -> 7 per game, end census raid pool 0, Pawn
  share 0.58 (need was only ~8 Pawns in these games, and in-flight army
  covers a gap that small), radar 8/8 at 3.2 min, metal lost to raiders
  12,972 (lowest of the night's six sets), built 5530 (highest), buildings
  lost 73 (noise band). Not yet measured against BARb.

- **"Sometimes these enemies spawn right on top of us."** `dev_raid.lua`
  spawned at 0.6 of the base->enemy distance along a random bearing and
  CLAMPED to the map edge, so a bearing toward the near edge put the group
  ~900 elmo out, inside radar (2100). Now each spawn walks outward along
  its bearing until `Spring.IsPosInLos/IsPosInRadar` for the target's ally
  team are both false; a bearing that hits the edge still watched is
  redrawn. Check game: 10/10 groups `seen=0`, 1300-1800 elmo out.

- **First real 1v1 with no towers (BARb hard, Geyser Plains, seed 11):
  lost at 9.1 min.** Radar at 0.9 min (the reprice works against a real
  opponent too). BARb's first raid (10 Pawns, 3 Fleas, 3 Hammers) landed at
  3.5 min against 4-6 units of ours; four constructors dead by 5.2 min, two
  of them at HOME (fwd -0.37, -0.04), the lab at 5.3. apexearth, watching:
  "lost our entire lab in this one because our army was too busy chasing 1
  enemy pawn across the map... that's one of the core things we talked
  about - not overcommitting to a chase, appropriately sizing the group we
  send after raiders." MECHANISM: the cover units all sit in ONE defend
  pool, `CDefendTask` sends every member at its elected target, and the
  posts only apply when there is NO target (`FallbackPosts` is gated on
  `!isTargetsFound`). BUILT: `CDefendTask::LeashPosts` -- after the pool's
  attack/path order, members whose post is farther than its reach from the
  target are sent back to the post; of the rest, the nearest go until their
  power reaches 1.5x the threat at the target (RESPONSE_MARGIN, the margin a
  winning fight needs), and the remainder hold their posts. Reach rides in
  the post binding (`SetGuardPost(unit, pos, reach)`). Log `apex: leash n=
  sent= held= unposted= need= sent_pw=`. Leash set: only 3 of 8 games ran
  (drive full; 8.1 GB of replays and 46 GB of old runs deleted on his
  say-so); in those 3 the leash fired 12-19 times a game, buildings lost
  21 / metal lost 2894 over 3 games (per-game ~7 / ~960 against ~9 / ~1600
  in the earlier sets) -- directional only. 1v1 seed 12 with the leash:
  lost again at 9.1 min; lab died 7.4 min (was 5.3), constructors dead at
  5.2, 5.9, 7.4, 8.4, commander 9.0. Army 10 vs their 15 at 4 min, 8 vs
  26 at 6 min: the lab dies and the army never grows. apexearth: "our
  entire army grouped up into one blob at one spot most of the time. We
  don't make enough of the quick units still" (Pawn was 21 of 31 lab
  orders; the count is small because the lab is dead by 7 min). Leash log
  says why the blob: BARb's raid group reads threat ~36 and every post's
  reach (600-1000 with radar warning) covers the whole base, so all 9 are
  both in reach and needed (`sent=8 held=1 need=36`). The sizing is right
  for that wave; the spread only exists between waves.

- **"Our commander took a long walk, past a 2.5 metal mex spot, to make a
  converter."** MECHANISM: the exec loop in `decide.as` skips, for the
  commander, any want more than 400 elmo forward of the base anchor --
  silently, no log, no counter (the 2026-09-02 "commander builds at home"
  rule, written for the wall). On Geyser Plains the nearest 2.5 spots lie
  toward the enemy, so every decided mex fell through to the next-ranked
  want, a converter at home (`exec ... pick=1..3` on 5 of his 30
  executions; `decide -> metal/mex v=32` then `exec convert:armmakr
  pick=1`). FIXED: WK_MEX/WK_MEXUP exempt (TripRisk prices the walk with
  his 2700 metal at stake), other kinds still gated, skip logged as
  `apex: com-fwd skip` (sampled 30 s). leash2 set (leash + this fix):
  buildings lost 101, waves cleared 0.91, metal lost 16,075 -- the WORST of
  the night's sets. Two mechanisms: (a) the pool has ONE target, so held
  guards stood at posts while one of the other four groups killed the
  building beside them, and the sized group could not finish its wave; (b)
  the commander now claims forward mexes at 0.7/1.8 min instead of energy,
  and the first radar slid 3.3 -> 7.0 min (5/8 games). Fix for (a) built:
  every posted guard first answers the nearest visible mobile contact
  within its own post's reach (`local=` on the leash line); the pool
  target and the sizing apply only to guards with nothing local. (b) is the
  price doing what it says: a 2.5 mex at depth 0.3 beats a radar; open.
- **Guards held while the base burned (1v1 seed 13, lost 13.0 min, commander
  dead 12.9).** Every `apex: leash` line read `held=8 sent=0 need=2`: a guard
  whose post was beyond its own reach of the fight was held outright, so a
  one-Pawn attack on the base drew no answer from eight mex guards. His
  words (docs/24): "the mex guards don't move to help the main base... It
  is really bad that they don't respond to nearby parts of our base being
  attacked." Fix built 23:42: reach ORDERS the answer (in-reach guards
  first, then by distance) and `need` = 1.5x threat decides how many go;
  the rest stay. Same build carries the per-post local target.
- **"Dry hump our most valuable mex."** Posting put every guard of an asset
  ON the asset (`SetGuardPost(unit, gPfPos[bi], ...)`), a pile that takes
  flanking damage. Fix: `Military::WallPost` -- the k-th guard of an asset
  stands forward of it toward `Front::FoeAnchor()` by half its gun range
  (cap 160 elmo) and beside the others at 96 elmo, alternating sides. Raid
  set `wall` (level 5) is the read; compare bldLost/metal lost against
  coverfirst 73/12972 and leash2 101/16075.
  READ: wall set 30 waves, bldLost 63, metal lost 11482, cleared 1.00,
  radar 3.1 min -- lowest metal lost of every set so far (cover-role
  baseline 61/15667). 1v1 seed 14 with it: "this one looks much better",
  lost 17.3 min (lab 14.2).
- **Hounds walked into T1 tanks (seed 14, 12.9-13.0 min, 3 x 285 metal).**
  His words in docs/24. Hound range 650 outranges every T1 tank; the
  standoff only ever measured the TARGET's range, so a standoff point
  relative to one enemy sat inside another's reach, and the leash's local
  order was a raw `CmdAttack`. Fix built 00:04: `IFighterTask::SafeStandoff`
  pushes every standoff point (single-unit path, squad rows, leash local)
  out of `range x 1.1` of every visible non-arty enemy the unit outranges
  by 1.15x (KeepRange's bar); enemies it does not outrange stay the odds
  election's business. Logged as act `SAFE` in `unit-destroyed acts=`.
- **Artillery shelling us is not answered (seed 14, corwolv).** Wolverine
  range 710 sits outside `atUs` (highestRange+500) for a Pawn pool, so it
  is refused as small fry unless inbound. Fix built: an outranging
  attacker whose gun reaches the post or any of our structures
  (`GetOwnStructsNear`, only evaluated for outranging attackers) is `atUs`
  and electable; the single-unit standoff no longer backs off from
  `IsRoleArty` targets (the squad rows already did not). Read: does the
  DEFEND pool elect a corwolv; deaths of corwolv in `unit-destroyed`.
- **Commander idle for the last ten minutes (seed 14).** Last decide 7.1
  min (a forward mex via the com-fwd exemption), `con-retreat hp=0.60
  walk=2751` at 7.5, then no decide, no floor line, only D-guns until the
  end: it sat in `CRetreatTask`, which releases a commander only when
  enemy influence at its feet reads ZERO (the 2026-08 fix for the
  flee-influence flap), and a raided base never reads zero. Fix built:
  the commander's bar is its own power (`GetUnitPower`, the influence
  currency) instead of zero; log `apex: com-retreat-hold hp= infl= pw=`
  every 30 s while held. Open: the com-fwd exemption let the commander
  claim a mex 2751 elmo out; the risk term should be pricing that.
- **Dead mex rebuild, measured (`tools/rebuild_lag.py`, 6-game sets vs BARb
  hard, no turrets, Geyser Plains, 20 min; deaths in the last 2 min
  excluded).** Before (wall+standoff build): 37 deaths, 9 NEVER re-ordered,
  lag quartiles 0.2/0.7/1.4 min, 6 over two minutes. After posted units count
  as cover in the risk model (`Military::UnitCoverAt` in `CoverWith`):
  32 deaths, 3 never, 0.2/0.6/1.6, 7 over two. Never-rebuilt fell; the lag
  did not. The `apex: rebuild` line says why: at home spots with the raid
  cleared, `threat=700-1500` came from the loss memory (`LossRateAt x tau`
  as implied threat, and as hazard p=m/stake), so surv=0.32-0.45 and the
  mex priced v=2-4 under energy at 4-9. Next arm deployed (`mexeyes`): the
  memory speaks only where no radar sees the spot (`ThreatAt`, `HazardWith`
  gated on `RadarSees`). Results before 1W/3L/2 timeouts, after 1W/2L/3T --
  noise.
- **Factory support, instrumented.** `[BARAI_DUTY] facPow= nanoOnFac=`:
  after set, our lab busy 79% of samples at 0.76 of full power when busy,
  nanos lathing the line 42% of samples; BARb 64% / 47%. Labs 1-2 a side,
  nanos 2-7 us vs 1-7 them. Seed 15's "full on metal, no army" had an
  e-stall 4.5-6.0 min and a bank at 100% from 6.5; no nano was even
  PROPOSED 4.6-10.4 min (17 converters, 16 radars, 7 mexes won the draw).
  `apex: nanowant` (feed/line/lathe/sink/army/waste/over/bank, 10 s) now
  logs what the want saw; read it in the mexeyes set.
  mexeyes set (memory gated on radar): 43 deaths, 15 NEVER, 0.3/0.9/3.1,
  9 over two, 0W/4L/2T -- worse on every axis; REVERTED. Its rebuild lines
  still read threat 1500-3400 at unseen mid-map spots and surv 0.41-0.47 at
  home spots with threat under 250, so survival there is the presence and
  floor terms, not the memory. The priced cost is the bigger lever: a
  50-metal mex carried m=26..587 (median 171); `apex: rebuild` now prints
  m as (M+E+A) and t as (walk+build+risk+late). Read the mexcost set.
  mexcost set (cover fix + breakdown, 49 rebuild prices): surv med 0.5
  (q1 0.4), m med 256 = M50 + E med 30 (q3 135, max 472) + A16 (a mex pays
  16 metal of space for a spot nothing else can use), t med 503 = walk 252
  + build 23 + con-risk 40 (max 1178) + late 65; v med 2.3. The half-value
  is the hazard field's presence term (foe mass against our army, at home
  depth), which ONLY mex and tech gains pay -- a converter beside the dead
  mex pays none of it. Lag 0.2/0.4/1.5, never 8/24, 1W/4L/1T. Next arm
  (`mexsurv`): mex gain x (1 - TripRisk) only; StreamSurvival logged, not
  charged.
  mexsurv read: rebuild v med 2.3 -> 4.4, mex wins 136 -> 160 of ~300
  decides, 2W/1L/3T (best of the night) -- but lag 0.7/1.2/2.5, never
  11/36: the lag instrument did NOT move with the price. Five 6-game sets
  put "never" at 9-35% and the median lag at 0.4-1.2 min with no ordering
  by arm; at n=6 this instrument cannot resolve a change of that size.
  Final arm (`mexsym`): the mex pays survival over its own delivery time
  (walk + build), the horizon energy already pays (`TechSurvival`), via
  `StreamSurvivalOver`; the 300 s `StreamSurvival` stays for tech siting.
  mexsym read: surv med 0.92 (was 0.5), v med 4.3, never 6/43, lag
  0.3/0.8/1.8, 0W/3L/3T. Six sets, all arms: never 3-15 of 24-43, median
  lag 0.4-1.2 min, no ordering by arm. VERDICT: the price inconsistencies
  are fixed and stay (units as cover; delivery-time survival horizon); the
  rebuild LAG is not shown to move by this instrument at n=6. What still
  sets it is structural: the per-category draw gives a v=4 mex about one
  ticket in three against energy/sense/buildpower bests, and 2-5 cons each
  busy 20-60 s per task, so a dead spot waits one or two elections. A
  "rebuild what just died" preemption is a POLICY question for apexearth
  (it is a rule, not a price); ask before adding one.

## 2026-08-28 — the +100% spend bottleneck (his Titan complaint, half-closed)

At his regime the AI banks a third of its metal (his game 31%, seeds 14-15:
27%/34%). The all-quiet gate half is FIXED (overflow floors the army gap;
milreq 1,665 -> 4,412 and demand now flows). The remaining half: the lines
only SENT 948 orders against 4,637 requested (seed 15) — the spend cap is
now the facqueue's 15s-per-line buffer (LineWindow = FQ_WAIT x
apex_fac_queue) and/or the line count at high income (9 lines; the overLine
income-supported count). Next lever: scale LineWindow with the overflow, or
let plant demand read the overflow the same way. Measure on metal-wasted at
+100%, 35 min. Related singles: our gantry hit 21.1m (seed 14) vs 30.2m in
his game after the super-lane copy law — directional, one seed each.

### Second watched game (seed 17, lost at 16 min) and what was changed for it

His words are in docs/24 and USER-FEEDBACK. Mechanisms found, each in the log:

- **No rezbots, ever.** `armrectr` is a builder to the catalog, so it priced
  in the builder branch on the loss pool alone in build-power units, then
  paid the con discounts, and was dropped silently at gain <= 0.5. Never in
  `prodrank`. Now priced after the loop as army: restore rate =
  min(unmet stream, BP x line metal-per-effort x util) with the stream =
  own AND enemy wrecks (`AiEnemyDestroyed byUs` feeds the pool) / horizon +
  medic share, on the line's mean quality (`apex: rezwant`).
- **New units left the base under attack.** The DEFEND pool promotes to an
  ATTACK at quota whatever the guards read; at 8.5-11.4 min `leash` read
  need 38-58 vs sent_pw 29-35 while the pool left. Now a pool whose last
  leash read a shortfall does not promote (`apex: defend-hold`).
- **Chase to where the target is.** Every attack point was the enemy's
  current position; `LeadPos` leads by its velocity over our closing time,
  capped at 6 s, in both the lone and the squad path.
- **Commander distracted by pawns.** The engage rule walked him to any
  group under his cost that beat his wage; a pawn group moving faster than
  him was re-elected every tick. The trip is now the catch at closing speed
  (`GetEnemyGroupVel`) and the fight is judged by `UnitStrength`
  (hp/dps/alpha/range/speed, no metal) against the group's visible members.
- **T2 lab while losing the front (OPEN).** `tech:armalab` drawn at 8.5 and
  11.4 min with `funded` 0.62-0.94 and the guards short; the lab died at
  14.5 min. The tech price carries `fundedMul` only; the plan's obligation
  is not in the con market. Not changed -- it is the "army in the target"
  half of the ETA objective.
- **Engaging with every army made (OPEN).** `apex: mass want=` 29-60 power
  at 4-10 min (12-24 pawns) and `squadsize` own avg 3-5.5 vs enemy 3-6.
  Not measured further.
- **Expansion (OPEN).** analyze_stats prints no mex timeline for this run;
  no instrument read yet.

Control on the energy change alone (`ctl-energy`, 6 games): 1W 1L 4T; wind
317 vs solar 182 (previous sets 275/241 and 190/213); `lineE>0` in 39
samples. Direction only at n=6.

### Seed 18 (third watched game), on the six-change build

- **Rez price was in the wrong branch.** armrectr has no build list, so
  `Catalog::gBuilder` is false and it prices in the NON-builder block; the
  builder-branch price never ran (inert, said so). Two rezbots were drawn
  by the old block once enemy wrecks fed the pool (v=102 vs pawn 15006).
  Rescaled: gain = armyGap/fillS x pMedic, pMedic = restore x fillS / cost
  x line mean quality. Undeployed at the time of writing.
- **Commander "braindead".** Trail: fought forward (z=2360) at 14.1 min,
  RetreatTask from there; reached 821,3541 at 15.3 min with hp 0.91;
  `com-retreat-hold` infl 36-78 vs pw 6.3-6.6 the whole way, so the task
  never released; stood 40 s; Banisher at 1005,3195 took him 0.91 -> 0.27
  in 12 s, dead 16.1 min. A retreat whose haven is inside the enemy's
  influence is a stand-still. Open: the retreat destination must be judged
  by reach (who can hit it) not influence, or the held commander must
  evade the nearest outranging attacker (SafeStandoff on the retreat point).
- **`defend-hold` fires constantly** (24 lines by 10 min, pools of 1-12
  held at short 2-56). Whether this turtles the army is unmeasured; the
  leash reads a shortfall whenever any enemy stands near a post.
- **Rocket bot died to a T1 turret it outranges** (his words, docs/24).
  Not traced yet: deaths.py on watch-1v1-barb8.

Measured (`six-changes`, 6 games, same map/handicap, vs `ctl-energy`): W4 L0
T2 against W1 L1 T4. Rezbots per game 2-20 (2-4 by 12 min) vs 0-5 on the
old block; the fleet saturates where `rezwant restore=0` (t000: have=9
against stream 21, cap 2.5 each). `defend-hold` 1-21 lines per game; army
count at 14 min median 39 vs 26. `com-evade` never fired and no commander
died (control: 1). n=6, direction only; the seed-18 Banisher case is not
reproduced by the harness.

### Seed 19 (fourth watched game), on the rezbot/defend/lead/commander build

Lost heavily (K/D 0.19 vs 3.86, quit at 17.7 min). What the log said:

- **Commander "chasing into the sunset".** `commander engaging` fired 0
  times; the D-gun action issues no move orders. His trail is far mex and
  radar jobs 1,500-2,000 elmo north (472,2424 / 232,1976 / 456,2120), each
  `pick=1`: the drawn want (a converter, refused by the duplicate governor)
  fell through to the next ranked want, and the `com-fwd skip` reads only
  the east-pointing axis. 12 of his 29 jobs were fall-throughs. Changed: a
  refused or skipped drawn want redraws among the rest (`redraw=` on the
  exec line) instead of walking down the value order. OPEN: a far spot
  sideways of the axis still passes the skip; a home radius is his call.
- **Rezbots only reclaim, and die doing it.** 22 built, 20 died in reclaim
  tasks at fwd ~1.0. `PreferReclaim()` returned true until a T2 lab stood
  and resurrect only looked at wrecks of 900+ metal, so no T1 wreck was
  ever resurrected. Changed: pre-T2 clause removed; resurrect any wreck by
  the cost of the unit it returns (`GetBestRezPos`) while the army is below
  target and energy is not stalling. OPEN: standing idle between scans is
  not measured; dying at the front is not addressed.
- **Buildings not remade.** 14 mex deaths, 5 never re-ordered, median lag
  2.0 min; two were moho frames killed mid-build (rebuild_lag counts them).
  Tried: a mex want at a spot with a recent loss hoisted to the front of
  the draw (`why=rebuild`), a RULE on his fifth report. REVERTED the same
  day on mechanism, not on score: the hoist skipped the price, took a v=2
  mex at surv 0.78 / threat 1277 over a v=13 generator, sent the commander
  out to rebuild (decide `corcom ... why=rebuild over energy`), and the
  same spot (240,1983) was rebuilt and lost three times in one game. The
  6-game sets cannot order it: the identical control code went W4 L0 T2
  and then W0 L2 T4 with mex deaths 12 and 40 -- the hoist arms (W0 L1 T5,
  W1 L1 T4) sit inside that spread. Rebuild lag median 0.3-0.7 in every
  arm. OPEN: the starve-out he watched is real; the fix is not a rule that
  ignores where the loss happened.
- The T2 lab-while-losing, piecemeal engagement and expansion items above
  remain untouched.

## 2026-09-05 pm: strength, the T2 lab, the commander's minutes

- **UnitStrength scale.** Means are taken over every producible mobile def
  including T3, so a pawn reads 0.0046, the commander 0.0307, a Bantha 823.
  Only ratios mean anything; any code comparing it to a threshold or a
  metal number is wrong. The commander's raw dps was 111,297 (D-gun) until
  manual-fire weapons were excluded; by construction UnitStrength ~
  power^2 / means, so the exclusion changed PowerMod (0.00 -> 0.12) and
  not his value. His ~6.5 pawns is the DLL's own power for him.
- **Commander eviction loop (fixed).** With no turrets a raided base has
  influence 5-60 at his tile; the flee gate at 0.01 evicted him every
  election (t005 strength-hold: 11 and 15 empty elections in two minutes,
  each a 20 s patrol home). Now strength-gated. He still leaves when the
  field near him is bigger (t001 com-strength3: near str 0.17 vs 0.011,
  15x him, died evading inside a base with no defence). 1-2 commander
  deaths per 6-game set is the baseline under apex_def_off=1 in every arm
  today, including the ones before the change.
- **Commander sideways jobs (fixed).** `com-fwd skip` used the axis
  projection only; a radar at (2369,2488) read fwd -267 by the axis and
  0.82 by ForwardFraction. In the smoke the axis also read a home mex as
  fwd 1098 at ff 0.05, so the axis is wrong in both directions early; the
  forward fraction is the reliable one of the two.
- **T2 lab timing.** 24 games: lab at 8.3-15.3 min in 19, none in 5; at the
  decide, enemyArmy 0 and bleed 1.00 in all but one. The spare-metal cap on
  the gap stream cannot be judged from these -- no game bought a lab while
  bleeding. The seed 17 case (8.9 min, gain 23.5, active fighting) is the
  one to reproduce: a watch game with `apex_techcand_diag=1`.
- **FoeMobileMassing goes negative** (`enemyArmy=-134` in t002
  strength-hold) when the static share subtracted exceeds the mobile cost.
  Harmless in StrRatio (returns 0) but the mass ratio prints -0.06.
- **Empty elections vs bounces.** `com-time none=` was counting Decide's
  2 s rate gate (a task that died young re-entering); those are now
  `bounce=` (0-59 per game, 37-59 when the base is raided). True empty
  elections: 0 in 12 games since.

## 2026-09-05 seed 20 watch: starvation, rezbots, the T2 lab

- **Pinned converters ignored in-flight capacity (fixed).** `EnergyPinned`
  (bank >= 98%) priced each converter at full capacity; with 670 e/s already
  ordered and the EMA surplus at -69..-374 e/s the pin never broke until
  they were built. `convwhy` showed it; the T2 converter want read 19.9
  m/s and the assist want (metal cost 1) inherited it. 41 of 82 con jobs
  at 16-20 min were assist. Now `chew = max(surplus - inflight, capacity -
  inflight)` when pinned. Next set: inflight 0-70 in every game.
- **D-gun collateral.** The ray check traced only to the target; the shot
  runs to full range. Seed 20 lost 9 converters, 5 winds, 4 nanos and 2
  cons to our own commander. A second trace from 48 elmos past the target
  now refuses the shot if it hits anything of ours. After: own-commander
  kills of our units 1-18 per game (atkteam = us, atk = our commander def),
  so either splash, moving targets, or the death blast remain. Not closed.
- **Assist want at metal cost 1.** `want_assist.as` prices a con's time
  only; its gain is the boss job's gain times seconds saved over the
  payback horizon. With a sane boss gain it is fine; with an inflated one it
  swallows every con. Watch `assist=` in the late job mix.
- **T2 lab roulette.** Sharpshooter ranked first once and top-four
  throughout the last 8 min of seed 20 and was drawn 0 of 22 times; the
  production draw has no commitment sharpening. His call.
- **test_frontline `line` fails on the current build, and it is not the rez
  work.** 2026-09-06: 2/8, 1/8 and 3/8 games pass across three 8-game sets,
  with the rez reflex on and off (`apex_rez_react_s` default flipped) --
  same failure either way. `guard` swung 4-7/8 across the same sets, i.e.
  noise. Whatever moved the tower line moved before this session.
- **Rezbots refused more than they take.** rez-reflex sets (2026-09-06):
  with the enemy-reach envelope on, `frontVeto` 526 and `none` 129 per game
  against 27 and 63 with it off. Deaths fell 8.2 -> 1.4 per game, so the
  trade is paying, but a bot refused near the fighting with nothing safe
  behind it still stands. Next read: what the refused sites were worth.
- **Rez fleet still short early.** 2.7 bots at 12 min (his bar: 4-5), same
  as before the reflex. `RezWorkM` pricing, not behaviour.
- **The reach envelope is LOS-gated.** `CCircuitAI::GetEnemyReachSlack`
  skips hidden enemies, so the back-away reads "clear" exactly when we
  cannot see. Same family as every visible-strength gate.
- **Rezbot elections.** rez-behind set: `none` (chain refused everything)
  300-1400 per game, `gate` 560-1060, `frontVeto` 1600-6700, resurrect 0,
  eat 0-14, worst no-job stretch 89-193 s. Every empty election found the
  bot holding a non-patrol task (`noneHeld=0/0/N`) -- decode pending
  (`heldBt=` in the next instrument). The lane point is behind most wrecks,
  so BehindLine against the lane refuses nearly all work; the reference
  must be our units' front. Instrument prints `ffLane`, `ffFront`,
  `ffVetoAvg` from the rez-inst set on.
- **Never re-ordered in a collapsing base.** conv-pin t000: lab died 15.3
  min, 10 mex deaths 14-17 min all NEVER -- the base was overrun (no
  turrets); the instrument counts them, the pricing did not refuse them.

## 2026-09-05 — the DLL committed in ae9f21d predates the C++ in the same commit

`ai/Unstable/engine-side/SkirmishAI.dll` was built 13:11. `cpp/src/circuit/CircuitAI.cpp`,
`CircuitAI.h` and `task/builder/BuilderTask.cpp` were last edited 14:54-14:55,
after that build. So the binary in the repo does not contain the C++ changes
committed alongside it, and anything measured against the shipped DLL is
measuring different code from what `cpp/` describes.

This is the S3 family — a variant that is quietly not what the source says. It
does not affect AngelScript work (game-side is hot-swappable), but any C++
result attributed to ae9f21d is unproven until the DLL is rebuilt from that
tree and the two are shipped together.

## 2026-09-06 — BehindLine has never once vetoed a rez site

`ffVetoAvg=0.00` in all 459 `rez-time` lines of a 60-minute 16-AI game. The rule
— apexearth's "never stand in front of our units where they're likely to become
collateral damage" — is unreachable: `RezSiteOk` rejects on `InEnemyReach` first,
which already implies the reach is clear, so `BehindLine`'s only veto branch can
never be taken. `RezSiteOk` is, in effect, just `!InEnemyReach(site)`.

Found while profiling; the call was removed as a loop-invariant (it cost an
`ArmyFront` + `ForwardFraction` + a second whole-enemy-set `EnemyReachSlack` per
candidate for a decided answer), and the behaviour is byte-identical because the
branch never fired. What the rule SHOULD do is open: the lane point is behind
most wrecks, so a front reference taken from our own units, not the lane, is the
likely fix. Not a performance item any more — a behaviour one.

## 2026-09-06 — ExecuteWant:404 throws from the engine on a reclaim target, intermittently

`manager/brain/market/execute.as:404`, `tgt.CmdMoveTo(unit.GetPos(ai.frame))` on
the condemned-unit branch of WK_RECLAIM. `tgt` is null-checked at :399 and its
def is read at :403, so the throw is inside the binding — the likeliest cause is
the target dying between the check and the order, which the async command model
makes ordinary (S13).

Seen 1x in a 60-minute 16-AI run at 00:59 and 4x in another at 07:06, and absent
from four runs in between, so it is state-dependent, not a compile or a
regression from the performance work. An exception aborts that election, so it
is a behaviour bug: the reclaim silently does not happen.

## 2026-09-06 — 16 AIs hold 1x to ~5,600 units; the AI builds 7,000 by minute 59

The envelope, measured on a 5800X3D (8C/16T), 8v8 Supreme Isthmus v2.1, seed 1,
apex_perf=0, gate 1 clean. `python tools/frametime.py <run>` prints the verdict.

  min 51   32.47 ms/frame   5,492 units   ai 19.3%   holds 1x
  min 52   35.43 ms/frame   5,869 units   ai 18.7%   BREAKS
  min 59   47.71 ms/frame   6,998 units   ai 18.1%

1x is 33.33 ms. With the AI at ~18-19% of the frame, sixteen of them hold 1x to
about **5,600 units**. Zero the AI entirely and the engine alone crosses 33.33
at about **6,400**. The game reaches 7,000 by minute 59, so the last several
minutes are over budget on simulation cost, not on AI cost.

Every AI-side category is now measured and none of them closes it: the frame
callback is 9.07 ms across all sixteen (0.567 per AI, against a 0.417 target);
the worker pool is 3.27 ms of CPU per frame and mostly parallel; event handlers
are 18-33 ms per AI per game-minute; the set-target gadget tax is 0.03%; and
order suppression covers 4.7% of re-paths and is not behaviour-safe.

So the open question is not "make the AI faster" -- it is whether the AI should
be fielding 7,000 units at minute 59 at all. That is the same question as his
basemap ruling in TODO.md: defend territory rather than a plethora of buildings,
and balance mobility against concentrated power. A smaller, better army is the
performance fix as well as the design one.

## 2026-09-06 — we send 1.36M set-targets a game and almost none stick

`apex: tgthold t=0 own=78 ... samp=1800 hold=25 rel=375 est=5.3 units=385`.
About 1.2% of sampled own units hold a set-target at any instant; 22.6% held one
and were released. Over a 60-minute 16-AI game the AI issues 1,357,207
CmdSetTarget — 31% of its entire order volume, and 61% of what the order census
could not otherwise account for.

Costs nothing: the intercepting gadget is layer 0 and blocks the command before
it reaches the engine's command system (id 34923 appears zero times in
dev_order_counter's log all game), and the per-holder sweep is 0.03% of a frame.
So this is not a performance issue.

It is a BEHAVIOUR question: apexearth's doctrine is "move within range and use
set target", and the instrument says the targets are not landing. Either the
doctrine is not doing what he expects, or the units are being told and the
engine is refusing. Related: ~22% of our fight/attack orders never reach
AllowCommand at all (AI 1,034,609 sent vs 804,251 seen), most likely CmdAttack
on an enemy the engine will not accept a unit-target order for.

## 2026-09-06 — one nuke silo puts the WHOLE MAP inside `InEnemyReach`

`CCircuitAI::RebuildReachCache` takes `edef->GetMaxRange()` for every visible
non-flying enemy, and a silo's own weapon range is map-scale. From the frame the
first one is seen, `GetEnemyReachSlack` returns a large negative everywhere, so
`InEnemyReach(anywhere) == true` for the rest of the game.

Measured, `matches/20260906-105022-*` (60 min, 16 AIs, seed 1), worst slack per
minute across all rez bots: -100 to -600 elmos (ordinary weapon overlap) until
minute 47, then **-66,469 at minute 48** and map-scale for most minutes after.
`apex: rez-guard` totals 326,875 pressed / 107,740 forced walk-outs over the
game, t3 alone 100,739 / 31,943.

What it breaks, all on the same predicate:
- `RezzerIdle` (`rules_rezzer.as`) — `InEnemyReach(here)` is true wherever the
  bot stands, so every idle rez bot returns `Retreat(unit)` forever, and the
  station walk below it (`!InEnemyReach(station)`) can never fire.
- `CBuilderManager::UpdateRezGuard` — every rez bot gets an evade order and has
  its builder task dropped 6/s for the last twelve minutes.
- `RezRezSiteOk` — no resurrect anywhere after minute 48.

The fix is in `RebuildReachCache`, not in the callers: a weapon that cannot
plausibly shoot a walking rez bot is not "reach". It needs a DLL rebuild and its
own measurement, so it was deliberately left out of the `RezSiteOk` cover change
of the same date rather than confounding it.

## 2026-09-06 — the guard leash walks single units to mid-map, with no odds test

apexearth, watching: "I wonder if sometimes we're treating the frontline like
this, as part of our base... Maybe we're sending guards out on the frontline
which would be quite silly."

He is right that guards die on the front and wrong about why. Posts are NOT on
the frontline: `guardposts.as:707` anchors each post to an asset via `WallPost`,
pushed toward the enemy by at most `WALL_FWD_MAX = 160` elmo. Measured over
`matches/20260906-183021-*` (38 min): front at fwd 0.23 (median of 226), posts
at fwd 0.06 (median of 76 passes), and virtually every defender IS a posted
guard (`unposted=20` across ~5,900 unit-samples).

But defend deaths land at **fwd 0.39 median, 0.61 p75, 0.84 p90** -- 160 of 322
beyond fwd 0.4, where only 24 of 289 of our finished buildings (8%) ever stood.
`fight:defend` is 77,234 metal / 300 units, 35% of ALL losses and the largest
bucket. The structure comparison is conservative: buildings that die skew to our
most forward ones, so the real asset cloud is even more homeward.

Two mechanisms, both in `CDefendTask::LeashPosts` (`DefendTask.cpp:792`):

- **`local` (DefendTask.cpp:836-857) has no odds test at all.** One guard
  attacks the nearest visible mobile enemy within `reach` and `continue`s out
  before `need` is computed. `reach` = `PostReach` (`guardposts.as:251`) =
  `speed * (assetLifetime + radarWarning)`, **clamped to 1500 elmo**, and it hit
  that ceiling in 40 of 76 passes -- on this map, Δfwd 0.36-0.59. Fired in 312
  of 359 passes, 1,928 unit-engagements; the `need` at those moments was median
  66, p90 259, max 3,312. In 48 passes the pool was ONE unit and it went anyway.
  The derivation is the bug: `reach` answers "could this guard get back before
  its asset dies", then is reused as "this guard may pick this fight alone",
  which it never established.
- **The leash releases entirely when the fight is too big** (`:861-864`, "Reach
  orders the answer, it does not veto it"): out-of-reach guards get `FAR_RANK`
  but stay eligible. In **172 of 359 passes (48%) `held=0` and `sent_pw < need`**
  -- the whole pool went out and still fell short. 510 unit-dispatches.

NOT FIXED: both need a number that is apexearth's, not ours -- what ratio lets
one guard take a contact alone, how far from its post `local` may reach (as
opposed to the dispatch ordering), and whether the release in branch 2 should
have a floor. He was asked on 2026-09-06 and declined the framing.

Not new: `DefendTask.cpp:326` already records "73% of combat metal on DEFEND at
fwd ~0.7" from an earlier watched game. `apex_defend_muster` / `apex_home_muster`
were the mitigations and have not closed it.

## 2026-09-06 — the squad arc is capped in ANGLE, so frontage shrinks with range

`SquadTask.cpp:1203-1224`, `ARC_SPAN 0.9f`:
`maxDelta = (M_PI * apex_arc_span) / row.size()`. Total arc LENGTH available to
a row is `range * pi * 0.9 ~= range * 2.83` however many units are in it. A Pawn
row (range 180, x0.9 standoff ~162) gets ~458 elmos of frontage; a Pawn's
footprint is ~30. Past ~15 Pawns the row is shoulder to shoulder and one
artillery shell covers it. The comment above the line reasons about the ANGLE
being a half circle; splash damage cares about elmos.

Measured same game: `apex: squadsize own n=4 avg=19.8 max=57`,
`fightcensus defend=5/90/39700` -- 90 units in 5 tasks, one of 57.

NOT FIXED: converting the cap from angle to frontage needs a minimum
separation in elmos, which is a doctrine number and his call.

## 2026-09-06 — the A/B says today's nine fixes changed no outcome; the real gap is composition

Paired 8+8 on Comet Catcher vs BARb:stable:hard, 40-minute cap, treatment
`tournaments/20260906-123343-fixes-on` against its own parent build
`tournaments/20260906-123756-fixes-off`.

**Both arms 0-8.** Survival time is the same (mean 25.9 vs 25.6 min), so nothing
here is a game-length artefact. Metal produced: ours 47,908 vs 35,302, theirs
82,216 vs 65,685 -- our SHARE moved 0.537 -> 0.583, +8% relative, which is
inside the +/-15% this repo already calls noise at this sample size.

What the composition table says, and it is the same in BOTH arms:

    category            Apex(on/off)      BARb(on/off)
    static defence      2.2% / 2.3%       23.9% / 24.3%
    army (real)        10.0% / 9.7%       22.8% / 17.2%
    factories           7.8% / 10.8%      6.5% / 7.3%
    constructors        7.4% / 6.9%       9.5% / 10.2%

We put ~10% of metal into army and ~2% into static defence; BARb puts ~23% into
army and ~24% into defence -- an order of magnitude more porc. That ratio is
unchanged by every fix landed today, and it is the thing losing the games. None
of the nine changes addressed it because none of them was about how much army
and defence we buy, only about how the units we do buy behave.

Two instrument results worth keeping:

- STANDOFF (new telemetry, treatment arm only): 21,541 engagements over 8 games,
  worst margin **-8 elmos**, 3,010 (14%) marginally inside a target's reach --
  all consistent with being outranged, none with being ORDERED inside. The old
  code's arithmetic predicts armart 710 -> 328 against a 435 turret (-107) and
  armsnipe 900 -> 410 against 480 (-70); nothing of that magnitude occurs. There
  is no baseline instrument, so this is "the predicted failure is absent", not a
  before/after.
- RAIDS -- CORRECTION TO THE 2026-09-06 CLAIM. "The raid director never fired
  once" was true of ONE watched game (58/58 refused). Over 8 BASELINE games it
  produced 4 real targets in 365 asks; fixed, 6 in 176. Refusal 98.9% -> 96.6%.
  The prize fix is directionally right and nearly irrelevant at this rate: the
  binding it now reads is only as good as what we have scouted, and we still run
  essentially no scouts.

UNEXERCISED, therefore still unvalidated: the shield work (no enemy LRPC
appeared in ANY of the 16 games; zero shields elected in either arm) and, in
these runs, the fusion pricing and the escort change.

## Order thrash: 16 logic centres move the same units (2026-09-06)

`apex: order-src`, one minute of a 1v1, ~276 units of ours:

    ring=662/367/260  build=1135/818/18  post=679/295/126  travel=786/32/25
    attack=180/71/0   escort=74/73/62    regroup=42/24/24  standoff=23/12/9

sent / re-sent within 3s / re-sent with the goal moved >128 elmos. ~4,400 orders
a minute is one per unit every 3.8s; for combat units alone it is every 3s.
Escort contradicts itself 99% of the time, regroup on every single repeat.

Consequence: a fix to the CONTENT of a movement decision can be measurably
correct and behaviourally inert. The `FighterTask.cpp` standoff clamp was fixed
2026-09-05 (verified: 21,541 engagements, worst margin -8 elmos) and apexearth
still watches snipers walk into mammoths, because a unit re-ordered every three
seconds never arrives at any standoff position.

Instrument added: `apex_order_trace=1` writes one line per order with its call
site, and `tools/orders.py` reconstructs a single unit's control lifecycle
(`--unit N`), ranks the worst-controlled units, and reports which pairs of
centres hand units back and forth (`--pairs`). NOT YET RUN -- the first job is
to point it at a game and find who sends a lone sniper to the map midpoint.

## The attack bar is per-pool, so we never attack (2026-09-06)

A DEFEND pool promotes to ATTACK only when it alone reaches
`max(minAttackers, GetPreMaxGroupThreat())` -- the enemy's second-largest group
-- rewritten onto every pool every 5s by `CMilitaryManager::UpdateDefenceTasks`,
which discards whatever `quota.attack` the whole AngelScript posture layer
computed (measured: quota 25-60, rewritten to a mean of 146).

Measured over an 8v8: 42% of pools held 1-2 units, pools sat at 0.32 of their
bar, only 3% of 507 readings reached it, 218 of 240 census samples had zero
attack tasks in existence, and the army spent 1.6% of its time attacking against
63% defending. The bar is set by enemy strength, so losing raises it.

apexearth's ruling 2026-09-06: "We shouldn't need to be one big squad in order to
attack, we should be able to coordinate attacks with multiple groups." So the
odds are judged on what commits together; the pools stay separate. NOT YET BUILT.

## Half of all defence builds die before they become a nanoframe (2026-09-07)

12 games, Comet Catcher 1v1 vs BARb:stable:hard, 25 min:

| arm | defence auction wins | died before framing | lost |
|---|---|---|---|
| teampow=all (old) | 67 | 33 | 49% |
| teampow=affordable | 73 | 39 | 53% |

`apex: task-gone` in one game: **`armllt done=2 abort=8`**. The `apex: abort`
lines carry `workers=1 builderToSite=398` -- a builder was assigned and walking
when the task was removed.

This is why loosening the team-power discount raised defence WINS (11% -> 23%
of decisions in the single-game check, 67 -> 73 across the batch) and did NOT
raise defence STANDING: `defHave` 368 -> 251, `defPeak` 452 -> 459, flat. The
price was never the binding constraint. **Defence loses on the walk, not in the
auction.**

Same shape as the squad-destination flapping fixed the same day: a decision is
re-taken while it is still being carried out. S14 says `AiMakeTask` is a
RE-ELECTION, so a builder walking to a tower site is re-elected onto whatever
prices best at that instant -- and a tower site is always further away than the
mex next door. Not yet confirmed as the mechanism; the abort's caller has not
been traced.
