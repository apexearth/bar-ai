# Open issues — what is wrong with this AI right now

Each entry: what is wrong, the evidence (one run, one number), what was tried.
An entry is DELETED when its fix is measured; the measurement goes in the
commit message. `USER-FEEDBACK.md` is what he asked for, `TODO.md` the named
plays. `git log -p -- ISSUES.md` has every deleted entry with its provenance.

Pruned 2026-09-15 from 3,634 lines. Every 2026-09-08..09-10 economy-session
narrative is gone (stage 1 of price-is-delta-ETA shipped 09-11; what is still
open from those sessions is under ECONOMY LADDER). Every entry about the custom
C++ fight layer (guard posts, leash, intercept dispatcher, arc tiebreak,
SafeStandoff) is gone: that code was reverted to stock BARb on 2026-09-07
(`7a1a9895`, `docs/30-fight-revert-plan.md`).

The fight layer is stock since 09-07; "unverified" below means a fix landed
and no game since has been read for it.

## PERFORMANCE

### HIS MULTIPLAYER GAMES LAG: 1.2-2.0 ms/AI/frame by minute 11-20 (2026-10-01)

His 8-AI games with 7 humans: Center Command (09-30, 1.3 ms at min 11,
maxMs 26) and Mediterraneum_V1 (10-01, 0.80 at min 11 after the ally-upgrade
fix, 1.2-1.7 at min 20, sim fell to 0.94x). Budget 0.417. bldIdle (the
builder election) is nearly all of it; its per-call cost grows 0.26 -> 1.1-1.7
ms over the game and it runs ~1,900x/min/AI. lagSev=3 throughout, so the
election slice was already at its floor: the cost is in work the slice does
not charge.
- Cause 1, fixed in script: AllyUpgradeSpots walked every allied structure x
  every map spot per election.
- Cause 2, fixed in script: on a sea map rez bots were sent to reclaim our
  own converters on other continents (ReachVictimMul tested reach from the
  target to itself), nopath, re-sent every ~2 s: 200-2,800 nopath per AI per
  game; one target 140 times.
- Cause 3, fixed in C++ (unmeasured): the failure memory was a single slot
  read at elections, so most marks were overwritten unread.
- `docs/34-perf-audit.md`: a 20-agent audit of the whole tree, 132 verified
  findings ranked by cost. Most of the top of the table is fixed.
- Where it stands (10-01 evening, his settings, Mediterraneum 8v8 vs BARb hard,
  apex_perf=0): worst game-minute 0.239 / 0.252 ms/AI/frame (seeds 1/2), from
  0.77-1.12 at the start of the day. Inside the 0.417 budget; NOT at the 0.209
  (half-budget) stretch goal. Run-to-run spread is ~+-10% on one seed.
- What is left, late game (min 16-19): builder elections ~33% (memo cores
  ~18%: mex 0.6 ms/miss, protect 2-5 ms/miss with a 5 ms single-call spike,
  reclobs 0.6), rez-bot chain ~9% (most runs end with nothing: front veto),
  raid/attack FindTarget ~6% (memory latency over ~460 enemies a call),
  periodic up.* passes ~12%.
- REGRESSION FOUND AND FIXED (10-01 evening): the memo's ONE global refresh
  per 8 frames starved the rarely-asked proposers -- nano most of all. Supreme
  Isthmus 1v1 vs BARb hard +100%, 4 seeds: with it 0-1 wins, 3-12 nanos, 40-75%
  metal wasted; pre-perf script 3 wins + 1 draw, 20-466 nanos, 0-27% waste.
  Now the gap is per proposer: 4/4 wins, 30-209 nanos; 8v8 worst minute
  0.282 / 0.303 (was 0.24-0.25 with the starving cap). The eco-only NullAI
  check did not see this -- it needs a fight to show. Judge memo changes on
  a 1v1 battery, not eco-only.
- Not kept: MEMO_FRESH_GAP 8 -> 16 read built -10% on two eco-only seeds, but
  the same tree's built ranges 72k-92k across the day's 18 runs, so it is
  unresolved, not refuted; 30 earlier cost ~15% of energy. Also not kept
  (no measured gain): a memo key on the build-only owned set, 8 memo ways.
- Eco-only check of the final tree vs the deployed slot, seeds 3/4: income
  438/446 vs 458/437, built 76k/81k vs 82k/76k -- no difference resolvable.

## ARMY

### SHIPPED 2026-09-30 EVENING, PARTLY MEASURED

From his Greenest Fields 8v8s (no T2/T3) and his rulings in them. What is
measured is in the commit messages; what is not:
- Squad targeting (push, no ghosts, real armies first, keep the target):
  A/B 6+6 Greenest 4v4 notech2 lost 18% less metal and stood 0.88 vs 0.72
  forward at 20 min, but target changes rose 34 -> 56 per seat-minute (the
  nearest unit of a moving army keeps changing). Squads converging on one
  army and walking into unseen ones are unmeasured.
- Regroup at the front, held only under half the squad's power
  (`apex: regroup held= kept-going=`): his game read 19 held / 97 kept going;
  whether units now trickle into fights one by one is unmeasured.
- Withdraw held while our side is twice theirs (`apex: hold-strong`).
- Heal station (`apex: retreat-dest heal= home=`): heal took the majority on
  every seat; where the rez bots actually stand is not logged.
- Repair-break fired 15x in tests, all on factories/mohos repaired by cons;
  never yet on a tower held up by construction turrets.
- Room pricing (full-bill per cell, local converter crowding): no clean A/B;
  wind:advsol 8-10:1 in tests vs 13:1 in his game, different setups.
- Energy storage band: converters 27-93 per seat at 30 min vs ~180 in his
  8v8 at 24; 1-2 storages per seat. Working.
- Builders past halfway finish the walk (C++ re-election skip + peel): the
  counter counts checks, not hands; walk-backs saved is unmeasured. Open: one
  far defence site can still draw nearly the whole pool while defence is far
  behind target (FeedableCrew x DefenceShortfall, his 09-28 rule).
- Advanced air plant / gantry copies on overflow or the eco seat: no copy
  appeared in two Glacier 2v2s at ~500 m/s (no overflow, no eco seat); his
  8v8 is the first test.
- Ally clearance (OffAllyBuildings) for ground defence and transport drops:
  never run in a test before deploy. Whose building pens our units is not
  logged.

### REGRESSION CHECK 2026-09-30 NIGHT: today's five commits vs f51a423f

Control = f51a423f C++ and script in lane `pushctl` (C++ overlaid from
`git archive`, script copied over both deployed copies). Head = lane
`neartarget`.
- 1v1 vs BARb hard +100%, 30 min, Comet Catcher + Supreme Isthmus, 6 seeds
  per arm: head ahead on metal produced (CC 144k vs 85k, SI 261k vs 228k) and
  T3 metal (CC 16k vs 2.6k, SI 65k vs 37k); wins 5/6 each. Most games end
  early on a commander kill, so totals mix with game length.
- Opening on Supreme Isthmus is behind: mex at 12 min 20 vs 24 pooled over
  16 seeds per arm (10 of them 12-minute games: 21.3 vs 24.5, income 91 vs
  96, metal waste min 4-12 19% vs 17%); fewer cons electing by 12 min (19 vs
  24 per game in the 30-min set). Not significant at this n; cause not
  found. Comet Catcher shows no gap. Early metal waste is 30-46% on Comet in
  BOTH arms -- an old problem, not today's.
- FOUND AND FIXED: the "builders past halfway finish the walk" rule (peel.as
  and C++ IBuilderTask::Reevaluate) counted a hand standing at its site as
  past halfway, so surplus crews were never peeled (40 vs 109, 63 vs 139
  peels on matching seeds). Now only a hand still walking (beyond build reach)
  is kept. Did not by itself close the opening gap.
- Greenest 8v8 seed 1 (the perf benchmark): head won at 40 min, control lost
  at 50; income 893 vs 601 at 30 min.
- Perf: both FAIL the 16-AI budget (control 0.519, head 0.660 ms/AI/frame at
  the worst minute). Same AI ms over minutes 20-39 with ~10% fewer units in
  head: ~10% dearer per unit (rez bots near the front: rz.salvage +76%; path
  queries +60%/min from the push targeting). Half the AI is the builder
  election (bld.decide ~1.2 ms a call), unchanged by today.
- 1366fa22 let LRPCs skip the affordability skip, so every election sites
  each cannon through HighGroundNear (up to ~110 FindBuildSiteNear calls,
  twice); want.super max went 12.7 -> 17.9 ms. HighGroundNear now probes
  highest-first, stops at the first legal site, cached 10 s per def+spot.
  Re-measured (same seed, different game): want.super avg 105 -> 106 us,
  max 17.9 -> 15.4 ms -- the avg is NOT this; the spike moved little.
  Whole-AI ms over minutes 20-39 fell 15% at more units, spread over every
  section: game-path variance, not attributable. One seed per tree cannot
  separate code from game; the late verdict (0.889 at min 46 in a 51-min
  game vs 0.660 in head's 40-min one) is not comparable either.

### ARMY SHARE (STALE for the Glacier 2v2 regime -- see the HOLDING FAILURE entry at the end; there we are 53% army to BARb's 43%): we put ~10% of metal into army, BARb 23-32% (2026-09-06, re-read 09-15)

`tournaments/20260906-123343-fixes-on` vs `-123756-fixes-off`, Comet 1v1 vs
BARb hard, 8+8: both arms 0-8; army 10.0% / 9.7% of spend against BARb's
22.8% / 17.2%, static defence 2.2% against 24%. Nine behaviour fixes changed
nothing because none changed what we buy. Defence is now 16% (docs/32); the
army share is not: `f4017fe5` reads Isthmus 8v8 seed 4 and Frozen Ford 2v2
still BARb-led at army 10% vs 32%. In team games our trade is 0.4-0.6 at
16-20 min in every format (TEAM GAMES below) -- we win only where we
out-produce. The army target (`ArmyTarget`, `RichArmyGapM`, the escort
conscription fixed 09-13) is the term to read; docs/32 says "the target's
question, not the line's".
2026-09-19 night, Comet Catcher 1v1 seed 3 at --speed 20, after the opening
fixes: 7-11 mexes to their 5-6 at minute 4, income 42-54 to 26-31 -- and
250-350 metal of army to their 1,500 at minute 5. The one T1 lab made six
cons in its first five minutes (con floor need=4 at 42 m/s, plus the
UnspentByHands term while the bank sat full) and three combat units; its
lathe is the army's only supplier. Zero nanos stood by minute 8 in one
game and one by minute 7 in the other (frames killed by the minute-5 flash
raid; `apex: nano-hot refused` now stops the re-election churn). Whether
the lab's minutes go to cons or to army at 40 m/s is his call
(USER-FEEDBACK: apex_con_per_m).

### CLOSING: a 25-50% lead at 30 minutes marches in waves of 240 into 17k of static and never ends the game (2026-09-13)

`tournaments/*rd3hold2*/carrotmoun-B-s2`: standing army 16k vs their 7.6k
mobile + 17.5k static, 231k built / 79k lost, timed out. `apex: mass want=240
floor=239 enemyArmy=-2375` -- the wave is sized by MassWant against their
MOBILE army (negative until floored 09-13), so each pool marched at ~240 into
towers. `rd3air/carrotmoun-A-s1`: 751k built vs 291k, killing blow on from
15 min, base standing at 30; `deaths.py`: 498 of ~730 army deaths were
`mov>mov>mov` oscillation between the squad's forward order and the retreat's
homeward one, dying in the open at fwd 0.8-1.3. Same shape 2026-08-29: a 3.5x
mex lead went 2-6 on Comet with the commander dying at home. The ending wave
has to be sized against what STANDS at the target (their static plus arrivals),
the killing-blow's question, not the massing law's. `apex: tgthold hold=31
rel=85` reads a target hold releasing far more than it holds.

### WE ENGAGE AT WORSE ODDS THAN STOCK: thr_mod attack [1,1] / defence [1,1] vs stock hard [0.6,0.8] / [0.3,0.5] (2026-09-20)

His question: are we more cautious than BARb, less likely to take ground.
Audited (commit `TBD`, agent report in its message): the C++ squad core is
stock since 09-07, but `behaviour.json` `quota/thr_mod` is the one knob the
stock engage test multiplies (`MilitaryManager.cpp:716`, `AttackTask.cpp:273`,
`DefendTask.cpp:228`): ours gives attack powerMod 0.8 and defence 1.0 where
stock hard rolls 1.0-1.33 and 2.0-3.3. The comment at `behaviour.json:13` says
the neutral value is offset by `TradeScaledMargin` -- deleted in the revert.
Second: `withdraw.as:142/561` orders a unit off enemy-influenced ground with
no gun on it (62 orders + 304 in-contact holds in one 1v1). Third: the MELEE
hold pool (`hooks.as`, `massing.as:369`) never marches while the base reads
"under attack" (4669 ticks in that game). Not tried: the JSON A/B is one line,
no rebuild -- run it on the battery before any script change.
RUN 2026-09-26 for attack only (defence left at 1.0, his "allies don't come to
help" reason): Koom 8v8 +100%, 4 paired games, first 12 min. attack [0.6,0.8]
lost 68.5k vs their 50.7k, control [1.0,1.0] 55.7k vs 41.3k -- ratio 1.35 both.
More fighting, same trade; reverted. The defence value is untested and his call.

### ONE FACTORY ORDER COSTS 8-28 ms (2026-09-20)

`apex: facqueue short ... stop=slice us=8086` avg over 327 elections, max
28 ms, in a 2v2: `ConOrderFor` alone exceeds the 4 ms batch slice every
time. The line is fed again after a second now instead of idling to the next
window (empty-line samples 28% -> 2%), but the per-order cost is the thing;
`hk.maketask.factory` avg 3-4 ms, max 28 ms, on a FAIL frame budget.

### check.py reports 'from' as a reserved word at lines that do not contain it (2026-09-20)

`sites.as:682/738` carry no `from`; the variant compiled (review gate 1, the
lathe-site line prints). The identifier was renamed anyway; the check's regex
matches comment text and the line numbers are wrong.

### ALL ALLIES PICK THE SAME ATTACK TARGET (2026-09-28)

His report, live Comet 4v4. `CAttackTask::FindTarget` (cpp AttackTask.cpp)
ranks by leader distance^2 x scale / pull, pull = enemy cost / (enemy power
+ own power). Stock's own-base term `scale = min(distBE / sqOBDist, 1)` is
linear in distBE once the leader's constant cancels, and flat when the
leader stands at home; pull outweighs it, and every ally sees the same enemy
groups, so all squads converge on the same high cost/power structure. His
directive (docs/24 Targeting): prefer targets near our own base; weigh the
enemy's walk to our base against ours home. Built 2026-09-28: squared
own-base distance in the rank, and a target we cannot walk home from before
the soonest enemy ground army stronger than our home statics arrives is
refused (`apex: atktgt ... backS deadlineS refused`). Open: with home well
defended nothing counts as a threat and allies still converge (Comet 4v4
seed 8: all four's top pick one spot, deadlines 87-166 s); seed 7 split
north/south. A tie-break toward the enemy across from our own base is
unbuilt, his call. 2026-09-29: "too passive" on his Special Creek 8v8 (180-250
candidates refused per pick); home strength is now the allied influence along
the threat's path minus the squad's own, and a squad that cannot reach home
(boats off an inland base) is exempt. With no target a squad marches on the
enemy start box (`apex: atkbox`, 26-47 a game vs 0). Not yet read from one of
his games: his logs of that night were overwritten (now kept as .prev.log).

### SUPREME ISTHMUS trbl 0.45 +100%: out-expanded from minute 12 (2026-09-29)

Four 4v4 games vs BARb hard: 3 losses at 32-38 min, one to the time limit
(`tools/minutes.py`). Level to minute 8, then minutes 9-12 trade at k/l ~0.2
(D% 50-64) -- half of it the seat nearest them, to AK raiders and Skuttles --
and their mexes climb 23 -> 53 by minute 16 while ours stall near 30; their
income passes ours at 12, energy at 16. Minutes 4-16 they put 40k into
constructors against our 23k and 13.8k into extractors against our 4.6k.
Army spend by minute 16: ours 2.7-2.9x our economy spend, theirs 1.1x -- with
our army TARGET at 0 (the T2 switch) the buyers were cover demand (a guard by
every building), the navy budget and, in one game, the spare-metal sink.
Not the nanos: theirs work factories more than ours (31-69% vs 38-45%); ours
idle 38-46% against their 16-33% late. The EcoBehind blind read is fixed
(behind=1 there now) without moving the army/eco split. Open: why our mex
count stalls at ~30 from minute 8 (site vetoes, the con cap, assisting, the
moho wait under the T2 switch); whether cover demand should bind under the T2
switch (his call); which basis binds -- output share or holdings (asked).

### SIEGE: the Paralyzer is priced but never bought; allied Junos double up (2026-09-30)

His play (docs/24 2026-09-30): outrange a turtle with long-range cannons,
EMP launchers (Paralyzer), tactical launchers (Catalyst, Perdition) and the
Juno, fired at buildings. Built 09-30:
- Cannons aim at structures only (`apex: lrpc aim`); their count comes from
  the metal in reach.
- Target first, then site: `Military::TurretTarget` picks the known enemy
  group of armed buildings nearest where their turrets kill us
  (`apex: turret-target`); a launcher stands halfway between that group's
  reach and its own (`apex: siege t= ... target= targetM= targetR= at=`).
- Launchers fire a volley sized to kill (health / missile damage), saving for
  the best target while the stock grows (`apex: launch|launch saving|idle|wait`).

At real prices vs BARb hard +100% (real-51..54, 4 games): Cortex seats built
Catalysts and Junos, Armada seats Junos and a Basilica. Catalysts hit
armanni/armamb/armpb and saved for a 2-missile Pulsar; Junos hit only radar,
jammers and radar vehicles. Open:
- The Paralyzer is priced (gain 0.02-6.9) but lost every draw; never built or
  fired in any test, so its squad-in-reach gate is unmeasured.
- Allied Junos fire at the same target: target de-confliction is per player.
- Forward Catalyst frames die unfinished when the target group is the one
  killing our army (siege-force2, volley-41).
- Choices made without his ruling: a paralyzer counts as answering the whole
  loss at one spot (one per player); one Juno per player; a missile's bar is
  its cost (energy at 60 E/M) divided by the missiles already stocked; the
  site is halfway between the two reaches.
- The cannon count is untested in a long game.

### LATE GAME: what is built but only partly verified (2026-09-29)

- Rapid cannons (Ragnarok/Calamity/Starfall): priced by the metal of their
  structures they destroy (LrpcGain), and an unaffordable one may not
  super-push. No rapid cannon finished in any test; the three started before
  the push guard all died as frames. Open: whether one is ever built at the
  income his games reach.
- Torpedo aircraft: released once enemy ships or yards are known
  (`apex: foewet`, 23-32 on Isthmus v2.1). Only one Lance was built there, at
  35 min, and dealt nothing: its attack is unconfirmed.
- Bomber pooling (`apex: air share`): any player buys bombers, priced against
  the pooled wing; Carrot 4v4 Armada: all four bought, 95 hand-overs, strikes
  from the lead and a non-lead receiver. Open: the receiver changes as holdings
  shift, so some planes cross between bases more than once.

### The attack bar is per-pool, so we rarely attack (2026-09-06)

Stock `CMilitaryManager::UpdateDefenceTasks` (MilitaryManager.cpp:1578) rewrites
every pool's bar to `max(minAttackers, GetPreMaxGroupThreat())` -- the enemy's
second-largest group -- every 5 s. 8v8 census: 42% of pools held 1-2 units,
3% of 507 readings reached the bar, the army attacked 1.6% of its time against
63% defending; losing raises the bar. His ruling 2026-09-06: "we should be able
to coordinate attacks with multiple groups" -- odds judged on what commits
together, pools stay separate. Not built.

Re-measured 2026-09-26, Koom 8v8 +100%, first 12 min: at a fight's start ~1.3k
of our army is within 900 of it and 7-13k stands 900-2500 away, mostly guard
(f1) and defend (f2) pools; we lose 1.3-1.9x the metal they do, even in fights
where we had the numbers. TRIED AND REVERTED: `CDefendTask::FindTarget` judging
a target by `max(pool power, GetAllyInflAt(ePos))` (the side's power there).
4 paired games: less army waiting (5.4-11k vs 7.4-11.3k) but loss ratio 1.79
against the control's 1.35. Joining more of the waiting army did not trade.
ALSO TRIED AND REVERTED 2026-09-26: `UpdateDefenceTasks` promoting every
attack-bound pool together once their SUM met the bar (his 09-06 "coordinate
attacks with multiple groups"). 4 paired games: fired 19 times, attack-task
units +57% (767 -> 1207 census), loss ratio 1.13 -> 1.20, worse in all four.
More of the army committing is not the missing piece; what it fights with, and
how, is (Rocko 10.3k lost for 4.1k killed in the same games).

### RAIDS: the director produces a real target in 1-3% of asks; we run almost no scouts (2026-09-06)

8 baseline Comet games: 4 real targets in 365 `raid.as` asks; after the prize
fix 6 in 176 (refusal 98.9% -> 96.6%). The binding is only as good as what we
have scouted, and `quota.scout: 2` in `behaviour.json` caps scouting at two
tasks whatever the map -- a flat number. The route ("skirting around the front
lines", docs/24) is `CRaidTask::FindTarget`, stock C++, no binding hands it a
target. `TUNE_SPAM_RAIDERS` on since 09-13: unmeasured.

### The squad arc is capped in ANGLE, so frontage shrinks with range (2026-09-06)

Stock `SquadTask.cpp:431`, `maxDelta = M_PI*0.9/n`: a Pawn row at 162 standoff
gets ~458 elmos of frontage for any n; past ~15 units the row is shoulder to
shoulder under one shell. `apex: squadsize own avg=19.8 max=57`. Converting
to a frontage needs a separation in elmos -- his doctrine number.

### Set-targets do not land (2026-09-06)

1,357,207 `CmdSetTarget` in a 60-minute 16-AI game (31% of order volume);
`apex: tgthold` samp=1800 hold=25 -- 1.2% of own units hold one at any
instant. Free (the gadget intercepts it, 0.03% of a frame), but the doctrine
"move within range and use set target" is not doing what he expects.
`apex_prefer_target` is still 1. ~22% of fight/attack orders never reach
`AllowCommand` (1,034,609 sent vs 804,251 seen).

### Small residues, one line each

- `Military::ForwardFraction` runs from the territory centre to the NEAREST
  enemy (`GetEnemyPos`), so a raider in the base shrinks its span to the
  raider's distance and every point in the base reads +-1 (gate f791769d
  s5: the start at -1.3, a point 400 elmo from it at -0.9). 37 call sites
  read it as "0 home, 1 their base" -- the commander chase's 0.5 bar, the
  defplace fwd, the caution cap. The commander leash left it 2026-09-15; the
  rest still read it.
- Amphibious units "act very cowardly" (2026-08-29 arena): retreat threshold
  ruled out; no amph gate in fight logic; the standoff suspect is stock code
  now. Unattributed.
- The commander's D-gun still kills our own units behind the raider it shoots
  (1-18 own kills per game after the ray-past-target check, 2026-09-05 seed 20:
  9 converters, 5 winds, 4 nanos). Splash, moving targets or the death blast.
- A retreating commander whose haven lies inside enemy influence stands still
  and dies (seed 18, `com-retreat-hold infl 36-78 vs pw 6.5`). The retreat
  destination re-check went back to stock on his ruling (docs/30); not
  re-measured since.
- `behaviour.json` "power" overrides written for THREAT reading leak into
  production worth via `PowerMod` (22 defs; armvader x100, armstil x0.05,
  corbw x0.1). Survey open since 2026-08-29.

## DEFENCE

### DEFENCE SHARE: 2-6% of metal against BARb's 15-18%; the target is 90% unmet from minute 10 (2026-09-20)

His ask: "we're pretty much always making a lot less [defence] than the
barbarian stable AI is... we should be making the long range plasma cannons
as well." Frozen Ford 1v1 +100% (his 20:57 game and `matches/def-ctl-ff-s3`):
static defence 3.8% of spend vs BARb 17.7%; `apex: targets` def=85-765
against a target of 5-30k from minute 10; per 5-min bucket we spent
85/190/0/0/0 on defence from 5 to 30 min while BARb spent 885/1865/2560/1210/
14440. Found and fixed 09-20 (commit message has the numbers):
- `apex: roles` read `defence=0.00+0.90:0/3` for 17 minutes: the gap earned
  the quota and `RoleWorthDoing` (09-16) re-judged it by the draw's ticket.
  A gap-earned quota now stands when the category's best want is a turret;
  teeth and anything else in the category are judged as the draw would (the
  first cut hoisted 153 dragon's-teeth elections at v=0.06 -- the eco-seat
  Bulwark again).
- `PfSurfDps` inverted the engine threat with behaviour.json's threat-map
  mods inside it (Pulsar surf 0.5, Pit Bull 1.5, squared): Pulsar kill 567
  vs Pit Bull 1341 at real dps 1091 vs 422, and `PfKillCapM` in those units
  capped every stake at ~1 metal, so the threat-priced arm of the gain was
  inert. Real dps now; `defwhy` prints `cap=`.
- The LRPC's "worth what it reaches" read `ai.GetEnemyCostAt`, a count of
  enemies visible now: `inReach=0.00` in every reading. Reads remembered
  structure metal now (`apex: lrpc` line).
Open after the fixes: the quota is still 0/4-0/6 on Frozen Ford at 13-25
min. Only T2 hands can propose a turret (his 09-19 no-basic-tower rule), the
first takes no role, and a roled T2 hand's Pulsar order is repeatedly pulled
off by the e-stall hoist (`why=estall role=defence`, 6-15 a game) -- 13
Pulsar executions, 1 placed in `defB/frozenford-B-s2`. The e-stall is the
energy side's problem; the defence hole is its shadow. Also unread as metal:
`ThreatAt` (coverage.as), `foeHere` (protect_fill.as), the shield-far gate,
gift.as and HoldNeedM all read the same visible-unit count as metal; each
has a floor that hides it. Not changed.

Raised again 2026-09-28 (his live Comet Catcher 4v4 +100%, `matches/_engine`,
no extra-units pack so no T3 turrets exist): at 31 min `apex: targets`
def=250/6929, 4570/43358, 970/34450, 2435/43433 (t0..t3) -- 1-10% of target.
Defence wins elections (200-400 per team) but mostly Dragon's Teeth
(armdrag 102/149/236 on t0/t2/t3). t3: 42 Pulsar execs, 2 placed; each
built by one worker (`latency armanni done=214 workers=1`, 220 s); the
21-30 min retries hit `interior-gun refused`. Half the towers built die
(`fronttowers` backBuilt/backLost 24/16, 25/26, 17/10). Enemy T3 on field
104k (`foetier`). Built the same day: a gun's crew grows with the shortfall
(FeedableCrew) and free hands join it (`why=defjoin`, 47-187 a team); the
first cut raised the cap alone and no hand ever joined. Crews at completion
still mean ~2. Coastal torpedo launchers (Jellyfish/Anemone, 1-9 a team at
kill=0) are dropped on land maps.

### THE 10-20 MINUTE HOLE: T1 hands are routed out, the T2 hand's gun loses to eco (2026-09-18)

His watch of `matches/20260918-055500`: five LLTs and a beamer die at
15-17 min to the first T2 wave and nothing replaces them until minute 20.
Read from the log: the defence target asked for 2,400-4,200 metal of guns
from minute 6 (`defTarget=2413..4204 defHave=740..1185`) and no defence
election won between 5 and 20 min -- never even runner-up. Two prices
under it, both fixed 09-18 (wall slots price the whole shortfall over the
army's fill time; the T1 discount keys on a T2 hand, not the lab), and the
window still reads 0-2 towers in four treated games (seeds 33-36): the
remaining mechanism is `def.route=411/411` -- once the team-wide winner is
a T2 gun, every T1 hand proposes nothing (his 08-27/08-30 ruling), and the
one T2 constructor prices its Pulsar at `v=1.26-3.83` against a mex-up at
5.9-8.9 (`t=2321` of walk, build and displaced eco) until the cover/role
hoists lift it at 15-19 min. His 09-18 ruling: T1 hands fill the shortfall with their best gun
(`def.ownfill`), the pull's slot shape no longer scales the demand, the
T1 discount keys on the asking hand's own options. Defence metal placed in
minutes 10-20: control 92/1092/3440/184, his game 180; treated (seeds
41-44) 190/1692/9500/9160. Two of four still thin -- open until his watch.

### BIG FRAMES STILL LEAVE THE TURRET RING AT THE COMMIT (2026-09-18)

His watch (8-player Glacier Pass, eco seat): every AFUS in one rear column
with 2-14 turrets in reach while base spots had 40-52; "a gantry with all
advanced converters behind it". `audit.py` now says it per game
(`tN-big-builds-at-the-lathe`, `tN-converters-off-the-plant-ring`;
expect.py `big builds stand at the lathe`). Fixed 09-18: reactors sited by
LatheSite (fit-scored), converter yards at the core's rear edge, LatticeFit
and the LatheSite cache ask the DLL's own `CanPlaceCell`, a big frame's cell
is reserved in the blocking map at request time (S36). The audit still reads
RED on the last four seeds (72-75: 12/17, 4/6, 1/2, 2/7 starved). What the
`apex: cell-refused` line shows is left: (1) a second AFUS request asks the
cell where an AFUS frame ALREADY STANDS (asked and refused 0.1 min after the
first was placed there; `Take`'s cover/`JoinBigEnergy` should have folded
it); (2) an old task re-executed at 28-31 min for a cell a fusion took at
18 min (its position is not in any `energy-site` line of the last ten
minutes), so every adopting hand walks it to bare ground. Read those two
before touching the siting again; the siting itself now answers the ring.

### THE FRONT-LINE CONTRACT HAS BEEN FAILING UNREAD (2026-09-18)

`frontline_check.py` and three other `[BARAI_POS]` readers matched
`n=(\d+) (\S*)` after the census started shipping `part=a/b` (31eca356),
so `test_frontline.py` scored zero mexes and zero towers for every team
since then. Readers fixed 09-18; the first honest runs: control (his tree,
`fl-ctl`) guard 2/6, line unscored; treated (`fl-defgap`) guard 1/6, line
2/5 -- both FAIL the 75% contract. Nobody has looked at this instrument's
verdict since it broke; the contract needs re-reading before it is trusted
either way (expect.py's thresholds date from a different placement model).


### THE LINE (team front, docs/32): built through step 5; what is open (2026-09-15)

Status and numbers: `docs/32-defence-plan.md`. Open there: the shield and
support-row nano fire rarely; defence is 16% of spend against BARb's 8% now
that the target is met (the target's question). Residues folded in from older
entries, none re-measured under the team front:

- **Half of defence builds died before framing** (2026-09-07, 12 Comet games:
  33 of 67 and 39 of 73 wins; `armllt done=2 abort=8`, aborts with
  `workers=1 builderToSite=398`). Defence lost on the walk, not in the
  auction -- S14 re-election mid-walk is the suspect; the abort's caller was
  never traced.
- **Reach is paid as area.** `PfStakeIn` buckets our economy at the candidate's
  own range (protect_field.as:337/501), so a 1220-reach gun is credited 6.5x a
  480-reach one; a turret shoots one thing at a time.
- **The post-T2 line stays T1** (2026-09-02): `xT1late` 0.02 x
  `apex_wall_efficient` on the only candidate left; T2 hands price their own
  gun through `xWallEff=0.141`. Both discounts still in `protect_want.as`.
- **`stopped` prices a single tower at ~0 against an army** (his T2 con's
  Cerberus at threat 6180 read `val=0.0000`, 2026-08-30). The front row is now
  soak-valued and a slot's stake is the team metal behind its gap; whether the
  mains row still zeroes on contested ground is unread.
- **Early defence on a quiet map.** `TUNE_RISK_FLOOR` is 0 since 09-11 (the
  blind prior is the siege prior alone). Setting it to 0 measured Greenest
  +44% and Isthmus -27% (3 seeds, minute-30 metal) because the first Isthmus
  raid lands at minute 5 with nothing standing; not re-measured under the
  wave prior on walkable bearings.

### LEGION CONFIG: every Legion tower carries zero threat (2026-09-12)

`config/standard/behaviour_leg.json` (stock stub): `threat: {air:0, surf:0,
water:0, default:0}` on 40 defs -- `legmg`, `legrl`, `legbastion`, `leglrpc`,
every T2 Legion defence. The DLL applies it as `ModSurfThreat(0)`: an enemy
Legion tower is walked into as harmless and our own reads as no cover. The
navy stub was removed 09-12; the towers were not. `legnavyfrigate` /
`legnavysub` still read water-only (`badtargetcategory NOTSUB` stripped by
`CircuitDef.cpp`), so the shipyard never orders the frigate.

## EXPANSION AND THE OPENING

### THE MID MEXES ARE LOST IN TRANSIT: THEIR RAIDERS KILL OUR CONS (2026-09-22)

96-game control (`ol-ctl96`, 8-min games, Glacier 2v2 +100%). Before
minute 4 we lose 1.3 finished cons and 0.9 mexes a game; they lose 0.1 and
0.3. Killers of those 212 con/mex deaths: pawn 120, tick 60, rover 22.
The first die at ~90 s (frame 2800), to ticks and rovers.

Along the home->enemy axis (f 0 home, 0.5 mid) at minute 4: home mexes
(f <= 0.1) are at parity, 5.2 ours vs 5.4 theirs. The gap is mid (f 0.4-0.5),
0.7 ours vs 1.75 theirs, and our cons die at f 0.2-0.4, on the walk out.
BARb puts guns forward: at minute 4 they have 1.9 towers at f >= 0.3
against our 0.6, and at minute 6 4.2 against 0.8. We build MORE towers
(6.6 vs 5.0), but at home (mean f 0.04 vs 0.22).

The escort bid could not fire in the opening: production.as only offers it
when `!ecoGrowing`, and even then it is one ticket in the draw
(`escort-diag` at 1.3 min: short=2 paired=0). Built 2026-09-22 on his
ruling: the ESCORT FLOOR, one escort per exposed con while the free raider
army is worth less than the metal at risk, strongest worthy unit (a tick
escort loses to the pawns that do most of the killing).

Raid blind-target + scouts on the intel gap, 96 paired games: inert on
their mexes (7.7 -> 7.7 at minute 4) and ours; +220 standing army metal.

Full length with the escort floor (`t30-escort-s5-16`, speed 5): 3-13. A
mex lead at minute 4 in 7 of 16, but it does not survive to minute 6
(t010 +4 -> -1, t008 +2 -> -2), and a lead at 4 won 2 of 7.

### GLACIER PASS FAVOURS THE LEFT BOX, FOR BOTH AIs (2026-09-22)

Minute-4 mexes by our start box (96 openloop games, and 48 full games):
from the LEFT we have 7.0 against their 6.8; from the RIGHT 5.4 against
their 8.7. Whoever starts left gains ~1.7 mexes. Full games: 6/24 from the
left, 0/24 from the right. So the "minute-4 gap" was a box effect; on
equal footing we are level on mexes, and the left-box losses (18 of 24)
are lost with mex parity and ~700 less army at minutes 4 and 6.
`scratchpad bybox.py` is the read; read L and R separately from now on.

Defence-army fix (T2 switch keeps our share of their shown army; danger
and hold read group metal), 16 full games: 1-15 (control 3-13, not
separable at n=16). Home structures lost min 4-14 in losses 6,150 -> 4,400.

### THE LEAD IS LOST AT HOME, MINUTES 4-14 (2026-09-22)

Same batch. Metal of our finished STRUCTURES lost on our own ground
(f < 0.3), minutes 4-14, per game: losses ~6,150, wins ~950. BARb in our
losses loses ~2,770 of its own. Victims: the T2 lab (906/game), solars,
nano turrets, advanced solars, cons, winds, mexes. Attackers are their main
T1 army (warrior 19%, rocketeer 13%, pawn 12%, fido 10%, hammer 10%), not
raiders. t014: ahead 8-6 on mexes at minute 6; at minute 8 our army is at
f 0.53 while 1,450 metal dies at home, then 2,865 at home by minute 10.
docs/24 already says "if our base is being pushed, defence is the priority".

Mechanism (diagnosis agent, verified in code): our army is at home and
loses there, 1.6:1 on our ground. It is too small because the T2 switch
zeroed the army target from frame 0 for every non-seat player (a 2v2 has
no seat): `targets army=X/0` in 581 of 700 lines, `nanowant army=0.0`
2,448 of 2,450. His 2026-09-21 ruling was "enough army for a normal
defence, THEN stop"; the first half was never built. The valve back
(EcoDangerNear) compared `GetEnemyCostAt` -- a UNIT COUNT -- with 250
METAL, so it never armed (637 `on`, 0 `danger`). HoldNeedM read the same
count (needM 23-150 while foeMass averaged 8,286). Fixed together
2026-09-22: switch target = our share of their shown army, capped at the
full target; both readers use enemy group metal.

Still reading the count as if it were metal: guards.as WorkerEnemyM (escort
sizing), coverage.as:715, protect_fill.as:513, protect_senseprice.as:43/176,
safety.as:261, and two more with a 250 bar near home.

### THE 2v2 IS DECIDED BY MINUTE 4, AND MINUTE 4 IS EXPANSION (2026-09-22)

His rule that produced it: "analyze each game minute by minute rather than
just by the end state... if you're losing you're going to make less metal
because you're being bossed around the entire game and starved". Averages
over a batch report the consequence as the cause. `tools/perminute.py` is
the per-game read; `spendtable.py` is second.

Pooled over 96 games of six arms, at MINUTE 4, ours minus theirs:

    we lead on mexes      n=36   win rate 44%   (mex +1.2, army  -626)
    we are behind         n=60   win rate  5%   (mex -1.8, army -1565)

Everything I chased all night -- the 12-24 minute trade, the defence share,
the plant mix, the record -- sits downstream of that. In the games we win
our opening is level with BARb's; in the games we lose we are 2-6 spots
behind before either side has lost anything worth counting (first blood
is minute 1-2 and under 300 metal a side at minute 4).

Both our seats are equally behind (1.2 and 1.3 mexes at 4 min against
their 1.7 and 1.6), so it is not placement or a seat asymmetry.

The window is minutes 2-4: we finish 0.29 mexes a player there, BARb 2.8.
The hands exist (3 cons a factory-sample, same as theirs), they are not
refused (ecoFar 0.0, ecoQuiet 0.0, deathWalk 1.5 per sample) and 7.1
spots are priced per sample -- the claims lose the draw, and at 3.2 min
the ETA ladder itself picks the T2 lab over the spot (`eta-pick tech:
armalab eta=425 over mex:armmex eta=486`). 73 of 80 games start T2 before
minute 6.

The predictor holds inside a single arm as well as across them: in the
feed-bounded-walk arm (t30, 2-14) the two games we won were +3.0 mexes at
minute 4 and the fourteen we lost were -1.5; every game where we were
behind at minute 4 was a loss (0 of 9).

TARGET for the next session, stated as a number: +1.5 mexes by minute 4.
The instrument is `runtime/mex4_vs_result.py` (win rate by minute-4 mex
lead) and `tools/perminute.py` on one win and one loss.

### 2v2 GLACIER PASS +100% (his regime): 1-19 at HEAD, 8-15 after the opening and commander fixes; the game is now lost at 16-24 min (2026-09-21, night)

His ask: beat BARb stable hard reliably in his 2v2 (Armada both, +100%
both, 0.2 lr boxes). Control `tournaments/20260921-202615-ctl2v2-gp` 0-8
and `20260921-200959-*` 1-11 (0.38 boxes). Three agents read the losses
independently; the census and their corrections:

- Fixed in d726331a (measured per arm in its message): one commander had no
  plant for 2-7 min in 7 of 11 losses; the commander walked out and died in
  3 of the 4 shortest losses (engagements at 2-33x his strength, a leash
  along a base axis that ran perpendicular to the enemy, a retreat hold on
  the influence field); the ladder's spot claim lost the draw nine times in
  ten. After: second plant 0.0 min, first commander death median ~10 -> ~29
  min, income and army lead at 16 min (126 vs 93, 10.9k vs 8.8k over 16
  games, `20260921-212544-t4b-ladder-claim-16`).
- OPEN, the 16-24 window: their income doubles (93 -> 236 at 24) on 4.0
  advanced converters and 2.4 fusions per side to our 0.3 / 0.3 while our
  energy bank is full and 300-959 e/s spill (`convwhy wasted=959`,
  `convprice armmmkr v=4.86 gain=9.55` losing to metal v=14 and the
  metalfirst assist v=1000). The ETA ladder carries energy at the
  conversion anchor and has no conversion rung, so it buys fusions and
  never the converter. A conversion rung (spill less in-flight capacity)
  is written and deployed to the winrate lane, unmeasured.
- OPEN, the spot gap is FORWARD spots only: home band 5.2 vs 5.0, forward
  1.3 vs 6.0 at 12 min. It forms in the 10-12 window: they finish 23 mexes
  to our 8 while we finish 13 mohos to their 4 (we tech first: T2DONE 8.2
  vs 11.5 min). "Our mexes die 4x" was wrong -- `atk=?` deaths at home are
  moho upgrades; raider kills are ~2x ours early, parity after 12 min.
- OPEN, where the army stands: ours at front 0.18 (60% of units under
  0.2), theirs 0.23 -> 0.38 with a quarter past the midpoint. The regroup
  anchor is pulled back behind our forward-most tower
  (`TUNE_LANE_BEHIND_GUNS`) and our towers stand on the base rim, so the
  forward band -- where all the spot gap is and 45% of our losses fall --
  is theirs uncontested. Patch (the pull-back skipped when the lane is our
  own perimeter) in the session scratchpad, unmeasured.
- OPEN, the fights: trades are even through 18 min and 2.3:1 after. Our
  damage efficiency is >= 1.0 ([BARAI_DMG]) yet the same T1 types trade
  ~3x worse in our hands (pw 0.54 vs 1.47, ham 0.48 vs 2.01, fido 0.72 vs
  2.84); our Hounds die from >450 elmo to Bulldogs, Mannis, Snipers and
  Fatboys at 660-760. Damage does not convert to kills (they absorb 10-12
  damage per metal lost, we 7.6-8.7). The track record reads Hound 1.19-1.46
  by damage dealt, blind to damage repaired away.
- WHERE THE DEFENCE SHARE ACTUALLY GOES, measured per 6-minute bucket per
  side (t12, 16 games): light towers, us 4.31 / 0.38 / 0.06 / 0.06 against
  BARb's 8.88 / 4.81 / 1.69 / 3.00. Ours stop dead the moment an advanced
  hand exists -- that is `T1Tower(d) && CeilingConsOwned() > 0` in
  protect_want.as:492, HIS 2026-09-19 rule ("no basic tower at all once an
  advanced hand exists"). BARb keeps building 85-metal LLTs all game and
  its mexes are 78% covered to our 45%. We answer with Beamers (2.9 in
  minutes 6-12) and then nothing until Ambushers at 12-18. THIS is the
  defence-share gap, it is a rule and not a defect, and it is his to
  revisit -- the price fix above proves the auction is not what stops us.
  ...AND THE RULE IS EXONERATED: put behind `apex_t1_tower_late` (default
  1 = his behaviour) and measured with it off, light towers moved only
  4.31/0.38/0.06/0.06 -> 4.56/0.56/0.19/0.25 per 6-min bucket against
  BARb's 9.31/3.75/2.00/3.62, mexes lost before 24 min were unchanged
  (19.9 vs their 19.4) and the arm read 2-14. Neither the price nor the
  rule holds the towers down. What is left is the SITES and the HANDS:
  `slot.nopull` refuses 44-66% of wall slots and `site.interior` 33-49%,
  and the two uncounted `continue`s at protect_want.as:475-495 hide 320
  of 418 candidates a game. That is the next thing to instrument.
  INSTRUMENTED (b46f9ae6 + the two new gates, `def.obsolete` and
  `def.t1late`, six-game probe `t22-defgates-probe`, cumulative over both
  our players): the defence funnel is
    cand.class   7526/11278 (67%)   -- the def is not this line class
    cand.avail   1510/12788 (12%)
    cand.half     2599/3752 (69%)
    def.obsolete  1693/3517 (48%)   -- dominated on reach AND kill by
                                       something affordable now
    def.nosite    2091/5608 (37%)
    def.t1late     355/1824 (19%)   -- his rule, the smallest of them
    slot.nopull  45397/120004 (37%) -- wall slots with no pull
    fill.framecap 3482/4825 (72%)   -- the per-frame work cap
    def.targetfill/teampower/zerogain  0 refused
  So nothing downstream of the price refuses anything (targetfill,
  teampower and zerogain are all 0/1469-3630), and the biggest single
  defence-side refusal is `def.obsolete` at 48%: a tower is dropped when
  something we can afford RIGHT NOW dominates it on reach and kill --
  which on this map is the Beamer and then the Ambusher, i.e. the rule
  that makes us buy few expensive guns instead of many cheap ones. That,
  plus `fill.framecap` at 72%, is where the next work goes.
  TESTED: comparing the two towers PER METAL instead of absolutely (a
  Beamer outkills an LLT and costs 2.2x; two LLTs guard two mexes) does
  what it says -- light towers per game 4.8 -> 9.6, beamers 5.2, the
  whole tower count roughly doubled -- and it does NOT close the gap:
  BARb still fields 20.3 LLTs to our 9.6 and 40 towers to our 18, mex
  coverage 31% to our 18%, arm 2-14. Reverted. The refusals are real but
  the binding constraint is further up: we do not have the HANDS or the
  METAL at the time the towers are wanted (def spend 629/644/1312 per
  4-min bucket from 8 to 16 min against their 815/1601/4141), which is
  the same opening deficit every other arm of the night ran into.
- DEFENCE IS PRICED THE OPPOSITE WAY TO ARMY, and fixing that does not
  help here. The army want multiplies a unit's price by `1 + deficit *
  (assets+army)/target * apex_stake_weight` capped at 8 (production.as
  stakeMul), so being below target makes army dearer; defence had only
  `TargetFill`, bounded at 1, so 96% unmet priced within 5% of met. Given
  the army's own formula (same tunable, same cap) the multiplier fires
  hard -- `defwhy ... xFill=5.10`, gain 18.2 where it was 1-4 -- and the
  realised defence row does NOT move: 0.11 of a 0.29 target against the
  control's 0.13 of 0.27, and the arm reads 1-15. So the defence row is
  not held down by its price: the towers win their own auction and the
  metal still goes elsewhere, which points at the executor and the hands
  (`defsite`/`site.*` gates, DefObsoleteOnArrival and the T1-tower refusal
  at protect_want.as:475-495 are uncounted `continue`s), not at pricing.
  Reverted.
- THE MINUTE 2-4 STALL IS THE COMMANDER'S LEASH, and it is mine: after
  the radial half-leash (dee01107) `apex: mexdiag` reads comFar=63 refused
  spot claims per sample in minutes 2-4, more than every other mex
  refusal combined (priced 7.1, noOpen 2.9, claimed 2.2, deathWalk 1.5),
  and our claims in that window are 0.29 a player against BARb's 2.8.
  He is the biggest lathe we own there. Widening the WORK radius back to
  the full leash (the chase keeps its own 0.5-leash bound in safety.as)
  ran 3 of 16 games before the batch was stopped for system memory:
  mexes at 8 min 6.1 -> 7.7 and at 12 min 6.1 -> 9.3, army at 4 min 1974
  against their 1817 (ahead for the first time all night), and 0-3 with
  9.3k of losses in the 8-12 bucket. RE-RUN over 16 games (t27b, four
  workers): 2-14, mexes at 8 min 5.4 and at 12 min 5.7 -- no better than
  the tree with the tight leash -- and comFar still refuses 47.2 claims a
  sample, because most of them are the RIM test, not the radius. The
  three-game signal was noise. The leash is not the stall either; what
  refuses the claims is `PfCoreRimDist > 400` plus the forward-fraction
  test on ground the hull has not reached, i.e. the commander may not
  claim anything past his own buildings. Reverted.
  ...AND RELAXING THE RIM DOES NOT HELP EITHER (t28, 16 games): allowing
  claims past the rim on REARWARD ground, with his forward guard intact,
  read 3-13 and mexes 3.8/6.1/6.6 at 4/8/12 min -- no better -- while
  comFar rose to 76.3 a sample because the refusals simply move to the
  forward test. Both halves of the commander leash are now measured and
  neither is the expansion stall. What the census actually says is that
  the commander is refused and THE CONS ARE NOT (ecoFar 0.0, ecoQuiet
  0.0, deathWalk 1.5, priced 7.1): the spots are priced for the hands
  that can take them and lost to assist and energy in the draw. That is
  the same wall as every other arm, from the other side.
- THE WALK IS PRICED TWO WAYS, and fixing it changes nothing either.
  `ValueOf` charges a walk at `WalkRateWith` (what the lathe would have
  built in those seconds: 34 s cost a mex claim 609 metal) while the
  assist want charged plain `Wage` (the same 34 s, 37 metal) -- one
  builder, one walk, 13x. Charging both the same way (t29, 16 games):
  3-13, buildpower's share of constructor elections 24% -> 17% and
  metal's 13% -> 7% (it fell: the hands went to energy and defence, not
  to spots), mexes 3.9/5.9/6.4 at 4/8/12 min. Reverted. Six separate
  reallocations of the opening have now been measured -- ladder claim,
  mex-before-plant, claim-over-assist, both leash halves, and this --
  and the only one that helped was the first.
- NOR IN THE ELECTION MIX. The `metalfirst` assist hoist takes 29% of
  constructor elections and sits above the draw, so it also outranks the
  ladder's spot claim; letting the claim win when the ladder's own first
  move is a claim moved the opening a little (mexes at 4 min 3.9 -> 4.2,
  at 12 min 6.1 with their lead down from 11.9 to 11.0) and the game not
  at all (2-14). Reverted. Three separate ways of spending the opening on
  spots -- the ladder claim (kept, it was the 4-4 arm), mex-before-plant,
  and claim-over-assist -- all land in the same place: we can move WHICH
  of our 4,300 metal by minute 4 goes where, and BARb still arrives with
  5.4 mexes and 2,450 of army to our 4.2 and 1,220 because it finishes
  3,639 metal in that window against our 4,286 AND has more of it on the
  map. The remaining difference is not allocation, it is that a third of
  our opening metal is still in flight when theirs is standing.
- THE OPENING IS NOT LOST IN THE ENERGY MIX EITHER, though the mix is
  lopsided: by 4 min we finish 1,683 metal of generators (6.7 solars, 9.1
  winds) to BARb's 782 (15.6 winds, 0.9 solars) -- on Glacier Pass wind is
  40 metal for 11 E/s and solar 155 for 20, so wind pays 2.1x per metal.
  Most of ours come from his rule `apex_stall_solar_e` (300): while hard
  e-stalled under 300 E/s the want is restricted to zero-energy-cost
  generators, and at +100% we do not pass 300 E/s until minute 6-8, so
  162 of 168 stall generators were solars. Swept to 0 (16 games): solars
  by 4 min 8.0 -> 6.7, generator metal 2,964 -> 1,683, and the game did
  not move (3-13, income at 4 min 23 vs their 32). The rule costs ~900
  metal of opening and buying it back is not what we are missing.
- THE BASELINE, measured at the same setting as everything else and not
  before (2026-09-22, `c3-pre-session-s5-16`): e0ecbb21, the tree that was
  on his slot when the night began, reads 1-15 at pinned --speed 5 with
  six workers. The night's committed tree (dee01107) reads 6-10 there.
  That is the only honest comparison of the two, and it is the one that
  says the session bought something: 4-min army 472 -> 1250, 8-min mexes
  6.2 -> 6.6 against their 9-10, 12-min income 62 -> 75.
- THE SIM SPEED IS PART OF THE RESULT. One worker runs ~15x, eight ~5.6x,
  pinned `--speed 5` with six ~4.4x. BARb's opening is far stronger at
  honest speed (2.1k army and 9.4 mexes at 8 min vs 5.2k/6.9 at 15x); his
  games run at 1x. The same tree read 9-7 at 15x and 4-12 at 4.4x. Every
  number below is at pinned speed 5 unless said otherwise.
- Standing after the night (dee01107, on his slot): at 4.4x rung+anchor
  6-10 vs rung-only 4-12 vs d726331a (no rung) 3-13 at 15x; at 15x
  rung 9-7 vs 3-13. Not the >50% he asked for at honest speed.
- Measured inert and reverted: the plant-assist want carrying the unmet
  army share (`drain * TargetFill(ArmyValue, ArmyTargetFull)`): 3-13,
  hands on the plant 0.00 -> 0.03 of samples (BARb 0.28-0.31). The
  assist is a transient order the next election replaces, and the estall
  hoist pulls the commander to solars in minutes 1-3 (two labs plus his
  lathe outrun the early energy). What would move it: the assist held as
  a job across elections while the army is short, and energy that keeps
  pace with the plant instead of stalling behind it.
- Also inert (2-14, hands on the plant 0.05): the same term with the guard
  held for gap/drain seconds instead of ten. The gate is upstream:
  `isAssistRequired` (economy.as, BARb's rule: metal > 20% storage AND not
  energy-stalling) is false through most of our opening at honest speed
  because the energy stalls from minute 1 -- 4 facguard bids in three
  minutes. BARb's cons put up ~9 winds per player by 8 min (ours 2.8 winds
  + 4.2 solars) while its commander lathes the factory. The opening lever
  is energy that keeps pace with two labs, then the assist gate opens by
  itself.
- Third try, also inert (4-12, hands on the plant 0.05): the guard's own
  `CountQueued <= 0` gate refused a working lab (the read lags sends and
  the line orders one unit at a time; fixed to read the line's pending
  ledger), and with gain + held stint restored the commander's guard still
  never bid in minutes 1-3 -- `isAssistRequired` is false while the energy
  stalls, and that gate is right (build power on an E-starved lab makes
  nothing). What decides the 4-min army (2.1k vs 1.2k) is the lab's
  effective build rate: 28% of BARb's con-time is on its factory, 5% of
  ours, and our con floor spends the lab's first 600 metal on three cons
  that then go to nanos, mexes and towers. The lever is the opening energy
  (the stall hoist fires at 1.0, 1.2, 2.1 min every game) and cons that
  lathe the lab before they leave it -- BARb's opener interleaves builder,
  raider, builder, raider.
- The 4-minute army, measured to the unit (1d2ad405): cons per lab are
  equal (2.9 vs 3.0 per factory-sample), nanos per plant are equal once
  the caretaker gate is stock's, energy income is equal; the labs' output
  is ~5.4 m/s of units to their ~6.8, and a quarter of ours is rez bots
  (1.3-2 per player by minute 4, before any wreck) plus fleas. Their bot
  lab's queue is 64% combat; ours 45%. The early rez bots are the medic
  share of the squad doctrine bought ahead of any army; that and the lab
  rate (energy pacing) are the two remaining levers, both his.
- The medic share without the round-up (the next rez bot only when 12% of
  the army covers it) was inert too (3-13, 4-min army 1107). What is left
  is one number: at 4 min their labs have each produced 14.7 units to our
  9.4, with equal cons, equal nanos on average and equal energy income; a
  100-BP lab cannot make 14.7 units in 240 s after three constructors, so
  theirs runs at 2-3x nameplate in minutes 0-4 and ours at nameplate. The
  next step is an instrument, not a change: per-lab units and buildtime
  per minute, both sides, from [BARAI_DUTY]/[BARAI_ARMY], to say whether
  it is nano timing, con time on the factory or the resource throttle.
- The instrument is `tools/labrate.py` (buildtime produced per
  factory-sample, both sides, per 2 min). It says the opening gap is the
  LINE'S RATE, not what the line chooses: 0-2 min BARb 46.5 to our 14.1,
  4 min 71 to 41, 8 min 75 to 58. But the same read on the arm that won
  its regime (t5-conv-rung, 9-7 at one worker) is 20.0 to 2.4 at 2 min and
  17.5 to 15.8 at 4 -- a WIDER early gap on the winning arm, so the
  2-minute rate does not decide the game either.
- Putting the commander's 300 BP on the plant while the army is short:
  0-16, the worst arm of the night. The rate moved as intended (14.1 ->
  16.5 at 2 min, 40.7 -> 43.8 at 4) and everything else collapsed with it
  (mexes 5.8 vs 12.0 at 16 min, income 113 vs 174): the commander's
  lathe-seconds in minutes 1-4 are worth more as mexes and energy than as
  units, which is the market's own answer and it was right.
- So the ranking of causes for the loss at 4.4x, on fourteen 16-game arms:
  nothing in the opening PRODUCTION is the lever -- cons, nanos, medics,
  the plant guard, the con floor's spare reading and the lab's rate were
  each moved and each lost ground or nothing. The two things that did move
  the win count are the CONVERSION rung (+6 games at one worker) and the
  commander's survival (median first death 10 -> 29 min). What is still
  untried: the army's own quality after 16 min (same T1 types trade ~3x
  worse in our hands; the record credits damage dealt, theirs is repaired
  away) and the forward spots (we hold 5.8 to their 12.0 at 16 min while
  losing 2x the metal to raids).
- WHAT THE 12-24 MINUTE METAL BUYS, per side (t12, 16 games): we spend
  12.2k on army+defence structures to their 21.9k, and 35% of ours is
  Ambushers to their 14%; they put 20% into a Shipyard-class gantry
  (armshltx) and 22% into Annihilators. Our mobile losses in the same
  window are 531k: Hounds 17%, Hammers 11%, Pawns 10% -- 21% of the Hound
  losses to Fatboys (1400 metal, outranges a 285-metal Hound) and 19% to
  Snipers. We are answering their T2 heavies with T1 and light T2 while
  they build the heavies; the record's class bar cannot see it because it
  ranks a Hound against other Hounds.
- THE RECORD CANNOT BITE, and two arms proved it. (a) Settling the matrix
  METAL FOR METAL ON DEATHS instead of on damage -- his 09-16 ruling taken
  literally, and the defect it answers is real (the record read Hound
  1.19-1.46 while the tournament exchange was 0.72, because damage a
  repair pad undoes was still credited): 5-11, every type's multiplier
  still inside 0.85-1.27, trade 1.72:1 against us. (b) The reason: the
  prior is `apex_record_prior` (10) times the unit's COST IN METAL on both
  sides of the ratio -- 2,850 metal for a Hound -- which swamps a game's
  real exchange, so every multiplier sits at ~1.00 all game. Dropping it
  to 2 spread them only to 0.82-0.94 and read 2-14, trade 1.94:1. Both
  reverted. If the record is meant to steer composition it needs a prior
  in the units of the evidence (a few fights), not ten unit-costs.
- So the 12-24 minute trade is NOT fixable through the unit-worth model as
  it stands. What is left untried: the plants themselves (we build 1.94
  T2 bot labs and 0.25 vehicle plants per game, they 1.19 and 1.12, and
  their Fatboys/Bulldogs are what kill our Hounds), and static defence
  (they spend 21.9k to our 12.2k on army+defence structures 12-24 min,
  22% of theirs on Annihilators).
- THE PLANT PRICE IS ONE-SIDED, and the fix is a tunable that already
  exists. `TUNE_LINE_TERRAIN` is 1 and `TUNE_LINE_QUALITY` is 0
  (tunables.as:1858, :1884), so a plant's price carries the map-coverage
  penalty against vehicles (armavp reads 57.6% of the map to armalab's
  83.5, `apex: line-terrain`) with nothing speaking for what the line
  FIELDS -- while the disabled census says the vehicle line is the better
  one here (`line-quality armavp=0.69(q1.00 t0.58) armalab=0.40(q0.40
  t0.84)`). Coverage is `percentOfMap` of the largest connected component
  for the move class (InitScript.cpp:629-644), every cell counted the
  same, corners included.
  Turning it on (the documented 09-12 control arm) IS wired -- plantcand
  reads `line0.90` for armvp against armlab's 1.00 -- and moves the
  opening: T1 vehicle plants 0.25 -> 0.81 per game, and the 12-24 minute
  mobile trade from 1.72-1.94:1 against us to 1.37:1, the best of the
  night. The win count did not follow (2-13): the vehicle line arrives
  but the T2 vehicle plant still does not (armavp 0.12 vs their 1.19),
  because our T2 bot con cannot build it -- `unitdef.py armavp` lists
  armacv/armbeaver/armch/armcv/armhacv/armsacv, not armck, so the T2
  vehicle plant is reachable only through a T1 vehicle plant we rarely
  keep. That is the next defect, and it is upstream of every unit-mix
  question.
- HANDS ARE NOT FUNGIBLE, and the con floor (ConsNeedAny) treats them as
  one pool, so a vehicle plant never makes a vehicle hand once bot hands
  stand. Built as a capability floor -- a hand that is the only way to
  reach a plant no owned hand can build is worth one of itself, the shape
  of the existing air-con floor (production.as, `opens a plant no hand of
  ours can build`, fired 74 times in 16 games). It WORKS mechanically:
  advanced vehicle plants 0.12 -> 0.44 a game and T1 vehicle plants 0.81
  -> 1.44. The win count did not follow (3-13) and the 12-24 trade went
  BACK to 1.91:1 from the 1.37:1 that line-quality alone bought -- the
  second plant and its hands are paid for out of the same opening, and on
  this map that opening is already the thing we are losing. Kept in the
  tree only if a later arm shows it pays; reverted for now.
- Towers: LLTs 10.1 vs 2.6 per side at 16 min; their mexes 78% covered by a
  tower within 350, ours 45%. Tower orders do land near spots (58/130
  beamer orders within 350 of a spot) but the standing set at 12 min is 11%
  near a mex vs their 24%.

### THE T2 TRANSITION IN 2v2: ahead at 8 min, tripled at 12 (2026-09-19, evening)

Red Comet seed 5 after the day's fixes: at 8 min army 6.2k to their 4.8k,
income 73 to 81; at 12 min 4.9k to 13.2k and 72 to 185. Their T2 units
(snipers, Bulls) and mohos arrive at 10-12; our T1 lab keeps 68 of 92
units decided 9-16 min (6.8k of 18.5k metal) and its pawns die at home
4:1, the army gap grows, the market answers the gap with more T1, and
eco spend halves (2,912 -> 1,859 per 4 min) while theirs rises (3,425 ->
4,150). His doctrine: defending at home takes near parity, "we need
time to build the army to match rather than continuously letting units
die". docs/33 8 (cohesion 0.11 vs 0.44) is the same finding from the
other side. Not a wrong number; the next campaign. Tried the same
evening: an attack group containing a static gun always faces the power
test (no influence exemption) in CAttackTask::FindTarget -- metal lost to
towers on the same seed 1,230 -> 1,160, the deaths moved to home against
Bulls at 10-12 min; reverted. The turn is their T2 vehicles at 10 min
against our T1 line, not the wall.

### OPENING MEXES in 2v2: 10 to their 15 at minute 4, then no growth to minute 8 (2026-09-19, night)

Red Comet 2v2 seed 5, +100 vs BARb hard, one game per change at --speed 20
(uncapped, two games in a row crippled BOTH AIs to 1 mex at 4 min -- run
capped). Before: 7-8 mexes to their 13-15 at minute 4 in every 2v2 today;
the commander's claim was refused by ComFar 4-11 times before minute 5 (the
core rim is three buildings at minute one) and each refusal's eco fallback
bought a solar or converter; a scout car in the base set the risk axis so
every home spot read risk 0.78; the nano floor took two cons at 13 m/s.
After the six fixes in the 2026-09-19 night commit: 10 to 15 at minute 4.
Still open: from minute 4 the sweep reads 9-16 of 40 spots hot (their army
sits on the middle) and cand=0-1, so we stay at 10 while they reach 22 by
minute 8; and the cons build 4-5 basic converters by minute 4 (E surplus off
five solars) where BARb's commander alone claims six mexes. Instrument:
`apex: mexprice` (sampled 10 s, every factor of the top rung) and
`mexdiag ... comFar= ... sweep Nhot`.

### OPENING in 2v2: their army is 1.4x ours by minute 4-6 and the middle is theirs (2026-09-19)

2026-09-19 night, Red Comet 2v2 seed 5 after the opening fixes: armies at
parity by minute 5-6 (2,319 to 2,565; 2,671 to 3,259) and mexes 11 to 13
at minute 4 -- and our army front stays 0.20-0.32 while theirs holds 0.50
over its cons, so the middle is theirs by minute 8 (7 mexes to 26). Read:
`mass want=48-64` against `own=12-19` at 5-6 min (the floor's meet term
is the enemy's group power over AllyCount, above one player's whole army,
so no pool promotes until minute 7); capping the want at the player's own
power (tried, one game) promoted the pools but the front did not move --
`hold ... attack=` counts BaseUnderAttack true almost continuously with a
scout in the base, and recall-home reads the same. The 2v2 posture --
two allied pools that never combine, a hold that a 23-metal flea can arm
-- is the next campaign; docs/33 section 8.

story.py on 2v2 x8 per arm (Comet Catcher Remake + Glacier Pass, +100 vs
BARb hard): our combat metal over theirs at 4 min reads 0.69-0.96 by arm,
and by minute 6 their army stands at front 0.50 while ours stays at
0.22-0.27; they hold the mid mexes from minute 6 and the income lead flips
by minute 8-10. Equal lab busy (92%) and lab power; our two labs' first
four minutes are ~22% non-combat (cons, rez, scouts) and the rest pawns,
theirs 21 combat units from one lab with the cons assisting it. Our
commander's first five minutes: energy x127, mex x39, converters x37,
towers x23 over eight games. The army target reads 2,090 against 110
standing at 2.4 min -- the gap is known; the lab is its only supplier.
Tried and measured the same day: holding the mid mexes at parity (inert,
never at parity); screen axis off (no change); rez bots priced on the
core ratio (early rez 23 -> 4, ratio @4 0.69 -> 0.96, kept); the
commander assisting the lab on the army gap (assists 1 -> 29, ratio @4
0.96 -> 0.73, 0-6-2, reverted -- the commander's mexes and solars are
what feeds the lab). Open: what the lab should make in the first four
minutes (a con floor of 2.7 fires at t=0) and whether the T1 con walks
to a solar or stands at the lab; test_earlyfight.py is the harness.

### T2 IN 8v8 COMES AT 9-17 MIN: the ETA ladder keeps choosing mexes the cons die reaching (2026-09-19)

Isthmus 8v8 replays (seed 5, +100): our T2 starts 8.9-16.5 min against
BARb's 4.4-11.7; `apex: eta` for a late player reads the mex rung ahead of
the T2 lab every sample from minute 5 to 14 (mex 459-711 s, tech 684-938)
while the market's cons walk 5,000 elmo to those spots and die (his game:
25 T1 cons of one player). The mex rung's survival is TechSurvival(home),
so a far spot prices as safe as the base. Tried: a spot-hazard survival
for the mex rungs (HazardAt(spot) with the unscouted prior) -- inert, the
ladder still read mex 711 against tech 938 at 8 min, because the risk
field knows nothing about ground no unit of ours has seen. Reverted. The
death count at those spots is the evidence the field lacks (deaths.py /
story.py have it); the ladder does not read it.

### OPENING: the first factory comes late in half the games (2026-09-11, 09-15)

Comet 1v1 vs BARb hard, six games per build (`tournaments/20260915-081342-
ctl7f26-Comet`, `*trt-d9b6-Comet`): three of six have the first constructor at
5-13 min and 4-14k built at 25 against 25-50k -- same rate before and after
the team front. Worst case: the commander's lab task aborted by the stuck
watch three times (`held corlab progress=0.00 toSite=700 ... no engine
order`, `latency corlab dropped=10`), then mex-claiming across the map with
no factory until minute 12; in others `firstplant=3.2m` is simply late.
Greenest 2v2 batteries (09-11): 5 of 20 player-games with the first factory
after minute 19, the same `armcom held armlab progress=0.00 ... no engine
order, re-electing` loop 50 times. A known corner on Comet (start 1460,2976;
site x 2450-3000, z 1750-2350) has the commander in range of his own site
and not building for minutes (seeds 2 and 6 of `fl-*`). The stuck watch was
rewritten 09-15 (`ccf28df7`: reach + approach, not nearness + wiggle; Ford
2v2: no unreached-site stall over 75 s) -- the Comet rate is not re-measured
on it. Read the engine-order drop first (S13, S27: the engine discards a
build order on a blocked square with no idle event) before the election.

### 1v1 vs BARb HARD: 3-15 and 1-18, outbuilt 2-3x by minute 15 (2026-09-18)

Tournaments, four maps x 6, +100 both, 30 min: HEAD 3-15 (6 timeouts), his
slot 1-18. Every decided game ends on a commander kill at 12-23 min with
our metal built at a third to a half of theirs (Comet 32k vs 112k, Glacier
11k vs 41k). Constructors held at peak 9 vs 33 (T1) and 6 vs 16 (T2), mex
upgrades 8 vs 15, army (real) 10.6% of spend vs 30.3%, static defence 7.6%
vs 15.6%. Read from the Glacier 1v1s:
- A walking constructor was re-elected every 3 s with a fresh draw; the
  DLL hides its assignment so the script's hold never saw it (S14). Fixed
  09-18: the incumbent job is kept while en route unless an emergency
  hoist fires or a drawn challenger beats its value (`apex: keep-job`,
  70-104 keeps per 20-minute game). `why=nanofloor` alone had pulled cons
  off their walks 61 times a game.
- The constructor is never bought by the auction: v=0.12-1.3 (x1000)
  against a Pawn at 9,000-1,000,000 -- the army side's ppc carries
  quality x line-bite x speed x coverage multipliers (p=15 for a pawn)
  that no economic gain has. Only the con FLOOR (apex_con_base +
  income/44) produces builders: 5-7 T1 cons a game to BARb's 16-22. The
  feed-room gate zeroed even the floor's excess (room=0 all game once a
  few turrets stood; fixed: a con's claim value is not gated on room, and
  overflow floors the room whatever the target). What a constructor is
  worth against a pawn in one currency is his call: the plan says seconds
  off the target, and a claimed mex streams for the game while a pawn
  closes 55 metal of a gap once.
  09-19: the multipliers are measured (`prodrank ... p,pc`): a pawn's
  core is pc=0.8 of the line's best and its final p=46; the whole excess
  is the SCREEN axis (sight x dash / cost against the tree-wide mean
  cost, so a 35-metal unit reads 40x). Normalised to the line's best it
  read p=3 -- and lost 1-7 where the same tree without it won 6-2 (every
  1v1 ends on a commander kill; ours at 9.4-9.6 min in two). Reverted;
  docs/27 TUNE_SCREEN_WORTH. The pawn flood is what wins the opening, so
  the con currency cannot be fixed by deflating the army side alone.
- Mex tasks die at arrival: `unreach armmex gap=16 range=154 threat=1.7/
  0.0` -- the DLL's CanReachAtSafe refuses a fixed site the script's
  MexHeat accepted, on a threat reading barely above the 1.0 floor; 3-15
  per game on Comet, `nopath` 100+ on Carrot (cliffs).

### 1v1 ON SMALL MAPS: 4-43 across three handicaps, lost in the first eight minutes (2026-09-21)

Eight small maps (Altair, Avalanche, Geyser Plains, Hotstepper, Wanderlust,
Red Comet, Copper Hill, TitanDuel) x 2 sides, BARb hard, 40 min, `--speed 8`:
+0 0-16, +50 3-12 (1 draw), +100 1-15 (`tournaments/20260921-17*-wr-h*`).
Hotstepper is lava and not data (both commanders die to the map). At minute
4 we hold 4.4 mexes to 6.2 and 5.6 armed units to 12.6; at minute 8, 4.8 to
10.3 and 12.7 to 28.1 (+0 means; +50/+100 the same shape with the mexes level
at 4 and half theirs at 8). Read per mechanism (`tools/opening_ab.py <tournament> 4,8`, `tools/fallthrough.py`,
`tools/comm_engage.py` are the census scripts):
- LAB THROUGHPUT, not the lab's timing. BARb has MORE constructors than us
  at minute 4 (4.2 to 2.2 at +0, 7.6 to 5.3 at +100) and twice the army:
  its commander guards the lab between builds (stock
  CheckMobileAssistRequired), so the lab runs at 300-450 BP to our 150.
  Our factory-guard floor (`ProposeFactoryGuard`, his "OK" of 09-11) priced
  at v~1 against mexes at 10-30 and fired 5 times in 16 games before minute
  5. Repriced 09-21 at the overflow rate while the bank is pinned (the nano
  want's own law): +50 armed at 8 min 24.5 -> 31.8 (theirs 32.2), win rate
  unchanged (1-15). `apex: facguard` is the instrument; bids are rare
  because `isAssistRequired` needs bank > 20% and no e-stall.
- THE CON FLOOR TAKES THE LAB'S FIRST TWO MINUTES: 3.6 constructors per game
  from the first lab before minute 5 (60% of its lathe) while the commander
  never assists it. `need=2..3` from `apex_con_base + inc/25 + HandsShort`,
  and HandsShort keeps asking because the bank is full -- but the bank is
  full because the lab is the bottleneck, not the hands (+100: bank 87-100%
  from minute 2 to 8). A con from the lab is the slowest lathe there is
  (34 s of lab time for 80 BP); a nano is 200 BP for none. The con-vs-army
  currency is his call (see 1v1 vs BARb HARD above), unchanged.
- THE COMMANDER WALKS INTO T1 GROUPS OF 2-35x HIS STRENGTH: 6 of 43 losses
  end on `commander engaging -- T1 x9..13 ... str 0.09-0.24 vs his 0.01-0.02`
  (Geyser +0 4.5x, Altair +50 2.0x at 5.5 min, Wanderlust +50 24x and 35x).
  His 09-20 ruling made T1 at the base his to kill with no strength gate;
  the stake in those cases was 155-842 metal, not the base. Ruled 09-21:
  the LAST commander on the side is careful, a commander with allied
  commanders standing may be spent. Built (safety.as `LastCommander`,
  allies publish `comalive`; an ally that never publishes counts as
  holding one): the last commander keeps the T2 bar's strength and health
  halves against T1. 8 games +50: every engagement tagged `last`, no
  fatal engagement above parity, 0-7 -- the base is overrun at 15-27 min
  either way. `tools/comm_engage.py` is the instrument.
- THE RISK MODEL CEDES THE MIDDLE: Avalanche +50, 19 spots, we hold 4-7 all
  game to their 11-16; `mexdiag` reads 11 of 19 risky by minute 5, then
  `deathWalk=140` refusals at minute 10, while their army stands on the
  spots (front 0.3-0.47 to our 0.22). Expansion is army-gated and the army
  is at home.
- FIXED 09-21, measured inert on the outcome: the mex-guard gun the executor
  refuses as interior was proposed and cover-pushed every election, and the
  fallthrough bought converters and wind (19 refusals and 15 fallthroughs
  per game before minute 10 -> 1.6 and 8.4; converters before 10 min 6.0 ->
  3.9; +0 mexes at 8 min 4.8 -> 6.1, 0-16 -> 0-16). A crewless first-plant
  frame counted as in flight and deferred the only ask that re-adopts it
  (TitanDuel +50: 96% built at 2.0 min, rotted to 3.6, no lab until 4.9).
  The stall interrupt's "cheaper to finish" test was two ANDed currencies
  and every T1 generator's 0 E made it never hold. The first nano of the
  game went to the wall whatever bought it and stood idle (`idle=17.5`
  from minute 4, +100 Wanderlust).

### NUKES FIRE AT GROUND NOBODY REMEMBERS (2026-09-18)

His 3x-economy game, won late by one nuke: the silo log reads `nuke ground
confirmed -- forgot 0 remembered enemies at the impact` x30 and `nuke intel
spent -- 0 remembered enemies need re-sighting` x23 against 5+4 launches
that forgot 2-4 remembered enemies. Most warheads went to ground with no
remembered enemy on it; the one that won hit their base. `nukes saving 0/1
for a target worth 30000 behind 1 antinukes` x7: one silo, stock 0. His
lens: what a human would do is mass nukes on scouted targets. The reads:
ai-nukes (target memory and the antinuke count), the scout task (eyes kept
alive over their base), and a second silo at that economy.

### THE COMMANDER FIGHTS T2 (2026-09-18)

His watch: "the commander is still being frontline rambo when enemy is
attacking with T2 -- he can't compete with that". In that game's log the
commander's samples read fwd=-0.3..-1.2, home=700-2400, far=0 -- behind
the anchor and inside his leash -- so the fight was the raid reaching him,
not him reaching the front: the DLL's commander fight/D-gun behaviour
engages whatever comes in range regardless of its tier. The ai-commander
skill and the StrRatio ruling ("Strength, not metal") are the reads; the
question is what he does when the strength ratio says he loses.

### ALTORED 1v1: the commander dies claiming outer mexes (2026-09-18)

Altored Divide +100 vs BARb hard, `--speed 10`, seeds 21-24: three of four
games end on a commander death at 7.6, 16.4 and 24.0 min (`unit-destroyed
armcom ... at=2622,1071 thr=22.76`, `at=708,2926 thr=46.62`, `at=575,624`).
Every game, his three of 09-18 included, elects the commander to mexes at
x=2288-3056 on an 8192-wide map (`exec armcom mex:armmex at=2656,1008`,
walk charged `t=904` and still `v=7.11` over a radar at 3.26); in his it
walked back alive, in mine the retreat started at hp=0.60 with `walk=2016`
and lost the race. The mex-guard ruling (guns on the mexes outside the
base, more the further out) and `con-retreat`'s trigger are the two reads
to make before pricing the commander's walk any differently: a mex claim
two thousand elmo out is worth its income only if the claimer comes home.

### COMET 8v8: level at minute 8, then the mexes go to T1 raids and the army trades 1:3 -- no eco decision moved it (2026-09-16/17)

Comet Catcher Remake 8v8 +100% vs BARb hard, seed 1, four runs of the
same seed. Control (0ace8c67): mexes 29 -> 18 -> 9 at 8/16/24 min against
32 -> 45 -> 55; metal 418k vs 856k; K/D 0.38 vs 1.54. Three eco variants
on top (converters hoisted above the draw + no generator while wasting;
that plus the honest ladder ticket; the ticket alone): 339k / 335k metal,
mexes 5 / 3 at 24 min, K/D 0.24-0.29 -- none better, one seed each. Our
mexes die from minute 8 to peewees and hammers (`BARAI_DEATH atk=armpw`),
54 a game; our T1 army dies 3-4 to 1. His watched 4v4 on the same map had
the same curve (29 -> 6). The eco market is not the binding constraint on
this map; holding the mexes past minute 8 is (docs/32 frontier, ARMY
SHARE, RAIDS). The converter hoist experiment is recorded in docs/27
(`apex_convert_push` -- not built as a tunable; the flag is a constant).

### SCARCITY: at no resource bonus an 8v8 is lost outright -- 122k metal to their 416k, 48 mexes to 128, every seat wiped (2026-09-16)

His hypothesis ("we do really good when we are wealthy, but as soon as
there's a limitation in resources we do much worse") measured on Supreme
Isthmus v2.1 8v8 vs BARb hard, seed 1, lane gridsnap at 6ff77c96:

| | +100% both (32 min) | +0 (30 min) |
|---|---|---|
| metal produced, ours / theirs | 1,909k / 2,426k | 122k / 416k |
| mexes held at end, ours / theirs | 88 / 136 | 48 / 128 |
| T2 mexes | 32 / 57 | 5 / 31 |
| per-seat metal, ours | 58k .. 793k (one seat 41%) | 5k .. 26k |
| per-seat metal, theirs | 161k .. 434k | 34k .. 82k |
| outcome | no winner at cap, 1 seat wiped | all 8 seats wiped |

By minute 14 the two sides are level (7-15k per seat each); the collapse
is minutes 14-30, where they keep claiming and we do not. It is INCOME, not
spend: at +0 the whole team averaged 8 m/s per seat. Three mechanisms read
off the +0 log (`matches/20260916-222751-*`):

1. **Elections go to insurance, not income.** Team-wide: energy 772, airdef
   556, sense 327, metal 275, buildpower 262, defence 100. A 100-metal AA
   tower priced v=12-38 (gain 11-16 m/s of "cover" against the 63
   Bladewings BARb flew) over a mex at v=4-10 in 101 head-to-heads; 212
   times over energy at v=1. At 8 m/s income the insurance rate outbids the
   only thing that raises income.
2. **Most of those elections are churn.** 556 AA wins became 167
   executions, 29 new requests, 26 towers; the same site executed 52, 34,
   21 times. A hand whose election the executor refuses is idle again next
   tick and elects the same want (the livelock shape, memory
   `election-livelock`). Under scarcity the hands' time is the scarce
   thing and it goes here.
3. **Mex tasks die.** 135 `task-die cormex` (110 with a crew and no build
   failure) against 53 finished; 54 mexes destroyed. The claim-to-mex
   conversion problem of TEAM GAMES below, now with the bonus off.

Later 09-16, three changes measured on the same seed (one seed: a
progression, not a proof), metal ours/theirs and outcome:
122k/416k wiped -> 159k/320k lost (TOTAL in-flight cap: past what the
income feeds, a new site is not opened, the asker helps finish one; per DEF
it had licensed 2 of everything) -> 215k/355k no winner (orphans first in
that fold: the first plant sat unmanned 322 s) -> 257k/343k no winner (a
spot hotter than our guns' influence is not offered -- the executor's own
bar asked at choice time; 3,995 spots refused, mex task deaths 213 still).
`tools/mexeco.py` reads the shape that remains: our extractor count PEAKS
AT MINUTE 8-12 (33-35) and falls to 11-16 by minute 28 while theirs climbs
28 -> 64-77; three front seats hold zero mexes from minute 16 and lose their
commanders at 15-26 min. We build half their constructors and a sixth of
their rez bots (40 vs 244 necros; reclaim 267 vs 1,055). His 09-16 read:
in 8v8 there are too few spots per player for mex-led income; the
economy (energy, converters) has to carry it, and we make army instead.
At +100 the converters do carry us (1,118 m/s at 32 min vs their 893); at
+0 there is no energy to convert. The next lever is the frontier: the
seats that lose their spots are the ones the wall (docs/32) should be
standing in front of.

Also the +100 game's own shape: one seat made 41% of the team's metal (the
eco seat, 793k) while three front seats made 58-90k in 32 minutes with 4-8
mexes each -- the bonus hides that the front is starved. The lever is the
price of income under scarcity against the insurance rates (AA, energy
ladder, sense), and the executor refusing an election it cannot site; the
army share (ARMY SHARE above) is downstream of both.

### TEAM GAMES: per-player expansion collapses with player count (2026-09-13)

Twelve harness games 09-12/13, all +100% both sides: 1v1 Comet 27 mexes at
8 min vs BARb 13; 4v4 Comet 7/8/12/6 per player vs 8/12/8/10; claims that
became mexes by minute 16: 1v1 55-90%, 4v4 12-37%, 8v8 7-37%. Two causes:

1. **The chooser and the executor disagreed.** `PickSpot` priced a contested
   spot with a threat ceiling of 99; `IBuilderTask::UpdatePath` killed the task
   when threat at the spot exceeded the builder's power (~0), so every
   `unreach armmex` read `threat=0.1..5.4/0.0` (106 mex tasks dead in the
   Comet 4v4). CHANGED 09-15 (`f4017fe5`): an economy site's bar is our own
   guns' influence there (`GetAllyDefendInflAt`, floored at THREAT_MIN).
   Frozen Ford 2v2 seed 5: spots held 3-8 -> 12, refusals 91 -> 47. Not
   re-measured on the Comet 4v4.
2. **Allies do not see each other's claims until the mex STANDS**
   (`MetalManager::SetOpenSpot` runs from the finished-unit scan; `IsZoneAlly`
   marks only ground next to an ally building): 16 of 39 spots in the Comet
   4v4 opening were claimed by two or more of our own players. Open.

Also: pre-contact `FoeAnchor` is the mirror of home (1900 elmo off on
Geyser Plains); the enemy start BOX centre is the honest anchor and needs a
binding (`CSetupData` has the boxes). Runs that decide it:

    python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
        --maps "Comet Catcher Remake" --games 6 --per-side 4 --minutes 16 --handicap 100
    # claim->mex conversion and `unreach armmex` per player vs the 09-13 numbers

### A dead mex is not rebuilt quickly (his sixth report 2026-09-05)

`tools/rebuild_lag.py`, six 6-game arms on Geyser Plains: median lag 0.4-1.2
min, never-rebuilt 3-15 of 24-43, no ordering by arm; n=6 cannot resolve it.
The price is consistent now (units count as cover, survival over delivery
time); what remains is structural -- a v=4 mex gets one ticket in three
against energy/sense/buildpower and every con is busy 20-60 s. A
"rebuild what just died" hoist was tried and REVERTED (took a contested v=2
mex over a v=13 generator, one spot rebuilt and lost three times). A
preemption is a rule -- his call.

## ECONOMY AND BUILDERS

### Normal seats do not scale; only the eco seat does (2026-10-02)

Supreme Isthmus 8v8 +100%, 4 seeds at 8f924aba: at minute 24 the seven
normal seats make 4-220 m/s each (the eco seat 551-745); BARb's seats make
~200-250 each. Our normal seats hold 12-13 T2 cons like BARb's but raise 0-5
advanced converters to BARb's 5-14. Each spends 30-55k on army; its energy
is drawn to 90-99% by production, so the converter want sees little waste
and prices a converter at 0.1-15 m/s, and pending mex upgrades charge it
the stream it delays (convprice `rest=` 630-3500 against walk/build terms
under 100). Their T2 hands go to mexup (77 of 184 jobs), field defence (58),
Bertha and sensors. Open: the army/economy split on a normal seat; what a
converter is worth when the bank is pinned but not spilling.

**Measured 2026-10-02 night** (Supreme Isthmus 8v8 +100% vs BARb hard, 20 min,
4-game batches, `tools/seats.py`, `mexflow.py`, `mexguard.py`, `mexdeaths.py`,
`jobfate.py`). Per normal seat:

- Standing extractors stay at 4 from minute 8 to 20; BARb's go 4 -> 7-8.
  (`[BARAI_STATS] mex=` only counts UP -- it is extractors built, not held.)
- From minute 8 we build 0.5-1.4 extractors per 4 min and lose 0.9-1.9;
  BARb builds 1.1-2.3 and loses 0.1-0.5. 84% of our claim jobs are dropped:
  `hot-road` (the 09-21 road bar: any square hotter than our influence at the
  destination blocks the path) 142/game, no note 94.
- Our extractors die AT HOME: 18-22 a game in the home band (11-14 with no
  gun in 450), killed by Pawns, Pincers, Rovers, Flashes. BARb loses 0-1 at
  home. Home extractors guarded: ours 61-71%, BARb 94-99%. Mid-map: BARb
  holds 1.0-1.3 (77-88% guarded) and 0.3-1.2 in our half; we hold ~0.1.
- Guns by minute 20: LLT 1.7-2.9 vs BARb 6.3-6.9, Beamer 0.5-1.7 vs 3.0-3.6,
  HLT 0.6-1.3 vs 1.6-2.1; missile AA 3.4-4.6 vs 2.4. Defence spend 2.5-3.6k vs
  4.8-5.1k. DefenceTarget = (assets + army) x TargetShare(DEFENCE), floored at
  one light tower per extractor (MexFloorFactor) -- the target is the limit.
- Equal income at minute 12 (53 vs 56 m/s), then minutes 12-16 we put ~13% of
  spend into eco, BARb ~40%. Army lost by minute 16: 47% of built vs 32%.
- Energy half of BARb's (1.7k vs 3.8-4.2k E/s at 20): fewer fusions and
  advanced converters, which follow income, which follows extractors.

Fixed tonight, correct and income-neutral (8 games each, minute 20, normal
seat / eco seat m/s: baseline 75 / 343, fixes 73 / 357): the displacement
charge billed every build for a spot per builder (`OpenSpotStream`, 110-216
m/s on seats making 76-146); an upgrade FRAME dying deleted the ledger row of
the T1 extractor under it; allied extractors read as open claims (55
refusals a minute, support never called); energy sent to allies (the 0.95
share level) never read as waste and `EnergyPinned` waited for 98%; a
passing squad switched off the unguarded-mex hazard floor.

Measured and dropped: offering an ally's extractor only when that ally has
no T2 con (84% of our upgrade picks were allies', most dropped at the site
because BAR hands the moho frame to the ally the instant it starts) cut
normal seats to 58 m/s. Helping allies upgrade pays even with the aborts.

Open, his calls: the defence share / per-mex floor size, the road bar for
claims (`hot-road`), the army split on a normal seat.

### Every builder is priced as if the map's spots were ours to claim (2026-09-27)

`ClaimableSpots` (want_mex.as) excludes only OUR ledger and spots with a
VISIBLE enemy, so allies' mexes and the unscouted enemy half count as open. His
8v8 on a 320-spot map read 298 claimable with 13 held, so `share =
open/(claimers+1)` stays 1 and every new builder's claim term is a full spot
stream (a Butler read `claim711.5` at `room0.05`). The C++ metal manager already
marks ally-held spots (`CMetalManager::IsOpenSpot`, set from ally mexes) but no
script binding reads it. Fix: bind it, use it in `ClaimableSpots`. The assist
units were taken out of the claim draw separately; constructors still read the
inflated count.

### BAR's builder priority cannot carry the split: the shipped gadget barely throttles (2026-09-21)

His proposal for the scarcity split: "everybody building this thing gets
high priority, and the other people set themselves to low priority" -- the
game's own `unit_builder_priority.lua` (CMD 34571, 0 = low). Built and
measured: `CmdBARPriority(float)` bound to the script (kept), a pass that set
every builder's flag from what it builds (economy frames high; towers,
sensors, the labs and the nanos on them low), and `passive=`/`passiveBusy=`
on `[BARAI_STATS]` (kept). The flag took (labs read passive) and the split
did not move (Isthmus 8v8 seed 1: army 278k vs 280k, eco 82k vs 70k at 24 min),
because the passive builders kept lathing: 17 of 26, 26 of 35 busy with the
bank at 8-46 metal and pull at or over income. The gadget in game 2026.07.04
computes the metal a passive builder may draw as `cur - max(inc*0.2,
stor*0.01) - 1 + interval*(nonPassiveExpense + inc + rec - sent)/simSpeed`
-- the non-passive builders' expense is ADDED as if it were income -- so a
passive builder pauses only when the bank is under a fifth of a second of
income. Synced Lua, so not ours to fix (multiplayer is the target). The pass
was removed; the C++ stock toggle is back as it was. The split still has no
lever but build-power pull.

### The 8v8 allies' mohos are metal-bound, not hand-bound (2026-09-21)

Allies stand 2.4 mohos to BARb's 5.0 at minute 16 (live Isthmus 8v8). The
role census gave metal no target gap (`CatGapFrac` reads 0 for CAT_METAL) so
the defence gap (0.89-0.95 on every ally) took the roled hands, T2 cons
included: 6% of their decisions a moho, `role=defence` the reason. Giving
metal the ladder's gap (spots + servable upgrades over the growth still owed)
moved the decision -- metal gap 0.00 -> 0.32, quota 0.7 -> 1.5, T2-con
first picks airdef -> mexup -- and moved nothing else: mohos per ally at 16
2.5/1.7/2.9 -> 2.9/1.6/2.4, at 24 4.0/2.0/3.3 -> 4.0/3.2/3.4, starts
69 -> 65, ally income unchanged (3 seeds, `tournaments/*-roles8`). Reverted.
A moho takes 48-78 s of a 620-metal bill at 40-60 income with the bank at
zero: the T2 con already starts them; the lab's pull (its own 300 BP plus
the nanos) takes the metal first. The constraint is the army/eco split under
scarcity, not who holds the role.

Same game, the defence side of it (his 09-21 report: their mexes are always
better defended, ours lightly): towers per player at 16 min 9.2 (a third of
them AA) to BARb's 15.9, defence metal 2.0k to 6.3k, no HLT to their 2.1.
The defence role held quota 8-27 of the roled hands with 0-1 filled
(`fell=59-125`: the protect want refused at execution, the role released,
re-assigned next tick) -- so the hands stood roled to towers that were not
placed while the mohos waited. Why the protect executions fall is the next
instrument (`apex: prot-exec` streaks, `defsite` trace).

### The walled-plant move fired on a gantry 11% enclosed (2026-09-21)

His Isthmus 8v8 (`matches/_engine`, 01:35): the seat's gantry #25347 stood
`enc=0.11` -- its least-filled side 11% full, i.e. open -- and the rule of
09-17 ("a plant the core has swallowed moves to the rim, new one first") bought
a twin at 23.3m and reclaimed it at 29.5m (`apex: plant-walled ... reclaim
v=0.038 best=0.000`). He watched it: "our gantry get reclaimed... we made an
AFUS instead." The reclaim's gain counted the plant's own 7,900 metal as a
gain (removed 09-21, `want_reclaim.as`: a transfer, not a gain), but the move
still prices positive at any enclosure because `room` is linear in `enc` and a
seat's cell is worth thousands, and it wins whenever nothing else on the seat
prices at all. OPEN, his call: what counts as swallowed -- the doorway (the
side units leave by) closed, or every side?

### A crewless frame is only re-adopted by a same-def ask; it should be a priced want (2026-09-20)

His Ring Atoll game `matches/20260921-045243`: a fusion emptied at 95% by the
nano-fed peel, then during the e-stall at 25.3m both T2 cons founded a NEW
fusion 150 elmos from it (`request new armfus inFlight=2`). The peel no longer
empties a site (the founder stays, `peel.as`), and `Requests::Take` now hands a
crewless frame of the asked def to the asker (`adopt-empty`). What is still
missing: a frame nobody asks for by def -- an advanced solar rotting while
the market elects fusions, a converter frame while it elects mexups -- competes
in no election. Lane run `20260921-051803` (interim build): armadvsol at
1376,6016 emptied at 96% decayed to 81% over 80 s, `adopt-empty` 0, because no
con asked for an advsol in that window; `IdleFloor` would take it only when
nothing else prices above the floor. The right shape is a finish want: the
def's own gain over the REMAINING bill, so a 95% fusion is the cheapest energy
on the map. `ValueOf` prices a def from scratch and would need a remaining
fraction; not built. `apex: frame-stalled` and audit `no frame left to rot` are
the instrument.


### THE OPENING ON ALTORED: T2 lab done a minute after BARb's, four fewer mexes at minute 4 (2026-09-17)

Measured at --speed 10 (full speed stalls this map, docs/25 S34), +100, six
seeds, 14 min, against BARb hard, after 8de2c695 and the assist/ladder
repricing that followed it. Where we stand versus the control (his slot at
816cd437): mexes at minute 8 7.8 -> 10.0-10.8 (BARb 10.3-10.7), metal/s at
minute 8 44.8 -> 57-71, army at minute 12 14.2k -> 16.6k. What is left:
- The T2 lab starts at 6.8-6.9 and stands at 8.9-9.0; BARb's stands at 7-8.
  The ETA ladder picks it when its ETA beats the best eco rung; giving the
  tier's rungs the fleet's assist share did not move the pick (6.8/8.9 with,
  6.9/9.0 without). The start-to-stand gap is ~2 min of which the walk is
  most (latency start=25-98 s) -- the asker is whichever hand won the draw,
  not the nearest.
- The gantry stands at 25-27 min against BARb's 15.5-17.8 (30-min games,
  seeds 11-12). Its want first appears at 16-19.5 min: the host income gate
  `apex_gantry_host_inc` = 150 m/s of STRUCTURAL income (reclaim rate
  subtracted, 60-s EMA) is his 2026-08-30 ruling ("push back to 150 or
  later"), and his 09-17 brief ("take a really long time to even start the
  gantry") pulls the other way -- his call. Once wanted, the frame took
  522 s on one hand while 83 turrets went to the lines beside it: the sink
  branch life-scaled a plant's frame like a converter's; fixed (a plant's
  frame is its ring), 57-203 s after.
- Minute 4: 5.3-5.5 mexes against BARb's 7-8. The commander's LLT at 0.5-
  0.8 min (his mex-guard ruling) and the nano floor's turret at 1.7-2.1 min
  (his 09-11 ruling) sit in the window; the next open spots are a 60-100 s
  walk; the roulette still draws v=1-4 winds over v=5-9 mexes one election
  in three.

### ECO SEAT GANTRIES: two gantries, a full bank, 1,300 m/s of idle nano lathe, and the turrets went to the line and to towers (2026-09-16)

His watched Supreme Isthmus 8v8 (`matches/_engine`, seat t7 at 10150,597):
at 32 min `nanowant ... idle=1347-1662 bank=4966/5000`, both gantries at
`depth 2+2/592s`, `facqueue idle coraap/corap: no-candidate`. The seat's nano
executions: 122 at the team line 3,669 elmos away (`nano-to-line`), then
`nano-to-sink` cordoom 101, cormmkr 87, corfmd 48, corfus 29 -- the gantries
(`corgant` at 10124,682 and 12080,384) are not sinks in that list and the
cells within 300 of them saw 10-36 attempts. He: "two gantries and only a
small number of nano turrets around them... good income, not able to produce
units. This is an issue that we have very often." NeediestLine read the
gantry line at 0-58 m/s of need while its queue held 592 s of work; a
gantry's line should be the hungriest thing on the seat.

Found 09-16 (later): `LineUnserved` subtracted the lathe standing at a
working line from its share of the FREE flow -- but busy lathe is already
inside the pull that FreeMetalFlow nets off, so the line's need read zero
whenever its standing lathe exceeded the unspent flow's share, however much
overflowed. Removed (sites.as). One 32-min 8v8 seed: the eco seat's line
term moved 0-5 -> 11-59 m/s at 15-25 min and its turret count 113 -> 176,
but waste at the seat was 10-116 either way; no gantry stood on that seat
in either run, so the gantry case itself is still unmeasured. Its labs
make constructors, and a con line is not nano demand by his 09-14 ruling,
so the remaining waste is the seat's factory capacity (plant-glut, TODO
"never an idle factory"), not its lathe.

Found 09-17 (eco-only Altored): a turret handed a reclaim by the pile-on
(`NanoReclaimAssist`) stood IDLE afterwards for the rest of the game -- its
patrol was the one command in its queue and the reclaim replaced it. Fixed
(re-patrolled when its queue empties); the "lots of idle nano turrets" he
saw at the eco seat may have been partly this. Unmeasured at the seat.

Found 09-17 (1v1, Altored): the pack walk's 96-cell slice ran out inside a
full block before reaching a free cell -- the gantry asked 318 turrets over
66 walks, got 95, 49 walks out of budget -- and every walk restarted from
the same rings. PackSlots now resumes where the last slice stopped
(`PackResume`); after, 48/48 and 0 walks out. The eco-seat 8v8 case is
still unmeasured with it.

### ECO SEAT DEFENCES: bought late, inside the base, with walk gaps that block the farm (2026-09-16)

Same game: t7's Bulwarks (`cordoom`) executed 20 times within 1,000 elmos of
its anchor and 30 claws (`cormaw`) within 1,000, i.e. inside the eco block,
with the 6-cell `_default_` yard around each (dropped to flush in ad3aa4bc).
He: they "block useful construction of a lot of other things". The eco seat's
guns belong on its rim (defence-wall paradigm), not in its rows.

Found 09-16 (later): two buyers. (1) The DEFENCE role hoist took the seat's
best defence want whatever its price -- `why=role role=defence` at v=0.09
over assist at v=52; in a 32-min 8v8, 211 of 338 defence-role hoists were
under a tenth of the alternative. Fixed (roles.as `RoleWorthDoing`): a role
holds only while the category's sharpened draw ticket would win at least
one of the R roled elections; after: 0 hoists under a tenth, 5 under half.
(2) `why=draw over nothing`: a hand whose only candidate is a ~0-valued claw
or Bulwark on the home hull takes it -- 108 such elections on the eco seat
in one game, 11 guns within 1,000 of its anchor. Whether an idle hand should
build a worthless gun rather than wait is his call; not changed.

### LATTICE RESIDUE: 4-6% of nano turrets stand off the lattice, hugging a fixed site; mixed pitches leave 1-3 square strips (2026-09-16)

`tools/tiling.py` on the eco-only board (`matches/20260916-082921-*`,
`-083637-*`): 641/667 and 623/660 aligned, every miss a nano. The ring walk
(8 rings / 200 probes) finds nothing in a full block; the wide search then
returns a hole that is not a lattice cell (`apex: off-lattice ... taken=25`),
which is a hole beside a mex, tower or radar -- fixed sites are not on the
turret's lattice. Those turrets are flush with what they hug, so this may be
what he wants; if not, the walk should resume from ring 8 on the next
Execute instead of falling to the square search. Separately FOREIGN gaps of
1-3 squares (20-30% of structures) are where two defs of different pitch
meet: on one global lattice a solar (80) and a converter (48) share an edge
line only every 240 elmos. Flush everywhere would need a per-neighbour
placement (a cell chosen against the neighbour's edge), not a lattice.

### SEAT CORNERS: a farm past a cliff still kills an eco seat; a full yard falls to the probe ring (2026-09-14)

Supreme Isthmus seeds 3 and 5 (Armada): the rear seat's farm rear point and
lattice rings sit past a cliff; reach marks cut `unreach` 1,751 -> 40-100 on
seed 4 but seeds 3/5 still read 700-1,100 and the seat is overrun by minute
24 with income under 40. `FarmSlot`'s rear point walks back toward the anchor
until reachable (sites.as `EcoSiteFor`); the yards and lattice rings do not --
FarmSlot should test reach from home the way `CanDefReach` does. Separately a
full converter yard has one ask refused 20-40 times at the same point and
`ProbedSite` puts it on the 700-elmo ring: `audit.py ring-scatter` 14-28% on
the seat, 2-7% on Carrot; the yard should step to the next block
(`GroupAnchor` already knows it) before the ring places it.

### CONVERTERS: the T2 hands do not ask for the advanced converter, so the basics cannot retire (2026-09-12, still true 09-15)

Greenest 2v2 seed 10 (`tournaments/probe-reclobs2/3-greenest-s10`): T2 cons
elected 42 wants in 30 min, ZERO converters, 77-85 basics beside 1-3
advanced, waste 10-25%. Still the shape today: `def8/ford-D10-s5` t1 at 24
min `convwhy surplus=-63 excess=0 ema=536 inflight=600 standing=2870
bank%=96 v=0.000`. `eSurplus` carries the fleet's potential ask (the same
contamination the reclaim gate had) and reads negative while the bank is
pinned; the pinned branch prices the next advanced converter at
`capacity - ConvCapInFlight()` = 0 while one crawls. Tried: pricing at the
engine's measured excess (09-11, lost on both maps, reverted); T1 converters
retired by ratio (`TUNE_OBSOLETE_RATIO`, reverted for starving conversion at
the T2 transition); the reclaim gate now demands the denser hands FREE to
convert (`DenserHandsCover`, 09-14, unmeasured). `ConvUpDemand` reads zero
once the basic fleet's capacity covers income (want_energy.as:809), so on a
no-mex map nothing asks for the advanced plant; counting outclassed energy
measured worse on both maps. The seat's 13k E/s wasted with 84 cloakable
fusions and no converters (09-13) and "two Legion players at 59 advanced
solars" are this entry. `apex: convprice` prints the terms.

### REACTORS: no advanced fusion in an 8v8 at 733 income (2026-09-13)

His Carrot 8v8: fusions 5-16 per player, zero AFUS in 34 minutes. `ebig
mkt=legafus eta=legfus`: the ETA re-ranks on build power for a never-built
def taken as the class mean; recency-weighted 09-13 and "AFUS when the pool
has grown" (`2b4a838c`) landed -- no 8v8 read since. If it still never comes,
price the AFUS on the crew it would GET (`CostCrew` x con BP + nano lathe in
reach), which is what the market side already does.

### BUILD POWER: hands are still bought while hands stand idle (2026-09-11, changed 09-14)

His Greenest 2v2 (`matches/_engine`, 58 min): 482 mobile constructors, 14
factories, `bpgap gap=515 tgt=2425 cap=6745 net=-4319 blog=515 rawM=30936
bank%=94`. The backlog term (`blTerm = rawBl / apex_bp_backlog_s`,
want_energy.as:1077) still reads ordered-not-framed rows as a hands
shortage. `feedRoom` is lathe-based since 09-14 (`45403a65`); the seat's
~120 T2 cons now come from the T2-con FLOOR `2 + income/25` (his 2026-08-23
"at 100 m/s at least 5", scaled) -- `expect.py` "eco seat hands are turrets"
is RED on the con count; whether the ratio holds at 1k income is his call.
`Utilization()` (army.as:1439) counts busy constructors and never a factory;
the plant copy waiver was fixed separately (09-13), the term is still wrong.
`want_assist.as` bounds a hand's drain by `FreeMetalFlow()` (:125, :246) --
unspent income -- so with every metal committed the assist dies and a big
build runs at one lathe; `WorthJoiningSite` (09-11) joins by time saved, and
the T2 lab's crew has not been read since ("we get to T2 behind our
enemies", 09-08: 3.8 min at ~11 m/s with 12 cons alive).

### GANTRIES idle at 1,000 m/s; basic converters at 1,000 m/s (his 2026-09-12/13 reports)

Team 7 of his Carrot 8v8: five gantries 80% idle, bank pinned at 13.5k for
four minutes, every T3 candidate `gap0` because 245 Pawns + 140 Favs built
for escort duty filled the army target; a queued Korgoth + Juggernaut (49k)
booked as army held; 163 basic converters finished in minutes 24-28 beside
11 fusions. Fixes 09-12/13 (`PendArmyMWithin`, `RichArmyGapM` live again,
escorts by risk, copy waiver needs every line working, hands verdict) --
unverified in a watched game. `FacYardWatch` (`apex: facyard jammed`) reads
a blocked plant; nothing yet says what blocked HIS gantry.

Third report 2026-09-16, Isthmus 8v8: the eco player stood ~10 advanced air
labs, often idle, while spending about half of income. His infolog from that
game is unread; the first thing to read from it is what the auction offered
those labs per minute.

### ECONOMY LADDER: what stage 1 left open (2026-09-11)

Stage 1 (the generator chosen by the ladder, the tech want asking the
simulator, measured effective lathe per def) shipped 09-11 and moved both
maps up. Open, in the order the game says it costs:

- The tech want's PLANT choice and the mex/nano/plant proposers still use the
  market's def pick; only energy asks the simulator per def.
- Stage 2: the target carries holdings shares (his N%) and army in strength.
  This is where "a T2 lab while the front is being lost" (seed 17: `tech:
  armalab` drawn at 8.5 and 11.4 min with `leash need=38-58 sent_pw=29-35`)
  enters -- the tech price carries no army-share term.
- Two ladder reorders (build time in the key; the measured 17 s
  decision-to-ground wait in the key) each gave Isthmus +23-47% and Greenest
  -17..-35% through the constructor count. Which of `LadderRun`,
  `EtaEcoPick`, `EtaHandsShare` starves the no-mex map is the open question;
  until answered no ladder reorder is shippable.
- Greenest still ends on ~92 basic converters and 12 advanced solars against
  BARb's 8 advsol (CONVERTERS above).
- HOME READS LIKE THE FRONT once their army dwarfs ours: the siege term
  is foe/(foe+ourArmy+cover)/tau x shortfall, and at 10x it saturates to
  1/tau everywhere, so only local cover separates a mex behind the start
  from one at the wall's foot (0.545 flat, gate games 2026-09-15; p25 of
  home readings 0.545 in every loss band). The interior-as-worst-hole rule
  (gGapShort) helps only when every walkable bearing carries guns. What is
  missing is DEPTH: the rate at which a siege reaches a point should fall
  with the ground of ours it must cross first (the raid gradient against
  the line's own gradient), not with the guns beside the point.
- The base ETA is NOISY at the scale of its own decisions: his Comet 1v1
  (2026-09-15, 15.1-16.4 min) read `base=545, 7119, 1333, 7839, 9300, 1875`
  at P=178-247 -- a 17x swing inside 80 s with the same pool -- and a fusion
  was drawn at v=1.33 over a mexup at v=13.36 because the ladder read the
  moho as SLOWER than doing nothing (9315 vs base 9300). Which input jumps
  (bank, eAvail, the pool's `n`, StepSec at a dry feed) is unread; until it
  is, the merged eco ticket is a lottery on noise.
- Two rules from those sessions: an eco change measured only on the canon
  board is not measured (the board rewards not building infrastructure);
  the canon at `--speed 5` is not deterministic (700/771/845 m/s at minute
  20 for one tree) -- four runs per arm is the floor.

### ROOM: the crowding measure falls as the base fills (2026-09-09)

`PfCrowd()` is footprint over the area inside the rim, and the rim is the
furthest thing we own per bearing, so it read 0.01 from minute 7 while he
could see the base squeezed; every `apex_room_worth` charge (generator,
converter, reclaim; want_energy.as:1242, protect_want.as:193) is inert late.
`PfCrowdAt(pos, r)` reads 0.17 against 0.02 at minute 25 but feeding it in at
the old weight was a regression (299k -> 175k produced): the charge has to
be bounded by what the ground is worth to the next building. Not derived.

### ROLES and SENSE: a role is released when its category is refused, and sense is refused most (2026-09-08, mitigated 09-14)

`roles-h100-t`: 2,775 sense wins, 84 executed, `corarad done=3 abort=21`;
his 09-13 8v8 team 7: 2,459 sense wins, 32 builds. Each refusal drops the
hand's role and the draw re-elects it into sense (`fell=2718..4799` against
`roled=3..11`). Since 09-14 a fallen category is not handed out for 30 s
(roles.as:27); `def8/ford-D10-s5` at 24 min reads `exec-refused sense=170`
-- smaller, not read at 8v8. Couplings law 3 stands: the sense want passes
`GATE_RADAR_GAP/_FRONT/_HOT` on a site the request layer refuses; read
`Requests::gLastWhat` on the refusal before pricing anything.

### REZ: the fleet is sized to a stream it does not convert (2026-09-06, 09-13)

16-AI hour `matches/20260906-105022`: 35 bots per AI at minute 54, nominal 83
m/s, realised `mReclaim` 0.45 m/s; `unmet = stream - have x cap` has no
realised-output term and lowering `TUNE_REZ_UTIL` demands MORE bots. Rez
priced on the unmet wreck/retire stream where the army form is zero (09-13)
-- unverified. Rez BOATS: the stream is map-wide (`Military::WreckRateM`,
deathledger.as:141), so a shipyard buys rez boats off land wrecks and no
navy (his 09-13 report); split by movetype domain unbuilt. Early fleet 2.7
at 12 min against his 4-5 (`RezWorkM` pricing). The back-away envelope reads
only enemies we SEE (`GetEnemyReachSlack` skips hidden ones).
09-19, his Isthmus 1v1 (`matches/20260919-055126`): 14,716 `apex: nopath ?
by armrectr` and 3,160 `unreach ? bt=16` -- the rez chain hands land bots
reclaim tasks up to 6,965 elmo away across water, the DLL aborts each at the
path test, 6 a second for 40 minutes. `EnqueueWreckReclaim` tests
`NearBlocked` and threat but never `ReachableBy`; the RezzerChain path is
unchecked. Con-idle samples count these bots, so the 43% idle figure is
partly them.

### NAVY: no bot con can reach a shipyard from the Isthmus start; the T2 con sub never elects (2026-08-31, 09-12)

Legion 1v1 Isthmus seeds 1-2: every wet site is 260 elmos from ground a
`legck` stands on against 182 reach (`apex: unreach legsy gap=260`,
`wet-unreach` every minute); the shipyard is elected by the first air con
(18.7 min) or never. The commander (amphibious) could at minute 5; the
08-28 ban on commanders at water plants was removed 2026-09-28 at his call,
so it now may. Downstream (Nine Metal Islands
4v4, 08-31): the advanced construction sub is produced and never takes a
job -- `acsub` appears only as a shipyard producing one, `uwmme` elected zero
times. Find where a submerged builder falls out of the builder market
(`gWorkers`, `OnMap`/reach guards, an execute path with no water case)
before pricing anything. Not re-read since.

### ECO SEAT: big builds land away from the nanos; rich team still overflows (2026-09-28, Supreme Isthmus 8v8)

His watch: the eco seat (t6) sited its AFUS at ring BP 2,400 while its fusions
stood at 7,200 and 6,400 (`apex: energy-site`): LatheSite scores only where the
footprint FITS, and the dense nano blocks are packed with earlier fusions and
converters, so the AFUS fit only at the block's edge. Open: keep room in the
block for the next big build, or send nanos to the big frame on its first
tick. The team ended at 114k metal excess to BARb's 3.1k -- overflow is shared
automatically, so EVERY player was full: spend capacity, not sharing. The eco
seat's air cons: 20 destroyed, replacements held by `:conidle` from idle ground
cons (fixed: the idle test is per kind, air vs ground).

### NAVY: water maps after ReachDead -- thin early army, navy kills us at home (2026-09-27, Coast To Coast 4v4)

`ReachDead` (want_plant.as) drops units that cannot reach the enemy from the
army, the escort pick and the line price. 6 seeds per arm, `matches/water-{ctl,
treat3}-s1..6`: at 15 min our army is thinner (6-16k vs 10-20k control),
because the first labs are land labs and their output now reads dead. The
losses at home are BARb's `corsub`/`corpship`/`corroy` in both arms.
Shipyards finished 12 -> 20 and were destroyed 15 -> 17. 17 of 20 `corvp` tasks
died `no-site`, and 34 of 38 `corhp` in his game did too. The first plant is
still the commander's `corvp`; the vp line reads 0 but the opening does not ask.

Water economy, per game per side (`matches/water-navy-s1..6`, dev_stats
allBuilt): navy 530 vs BARb 105,905; tidal 0 vs ~7,200; underwater
fusion/moho 0 vs ~11,000; naval cons 567 vs 13,317. Causes found:
- `ProposeEnergy` and `ProposeConvert` skip every floater ("land-base v1"),
  and execute.as re-sites energy onto the land farm. A per-rung wet site
  (want_energy + execute) builds tidals.
- Shipyards die within a minute of finishing (threat 23-188 at our shore);
  BARb's fleet holds the middle by minute 7 (mapframe).
- Warships read `:losing` from the carried-over record (corpship n=15 raw
  0.92 < bar 1.00 at minute 3): lone ships die outnumbered, the record
  says ships lose, no fleet is built. A domain with no alternative is shut.
- `concap` 40/40 is spent on land cons; no naval con, so no T2 yard and no
  underwater eco.
c913e855 (yard per seat, land/navy budgets, filters opened) took our navy
530 -> 18,343 a game at inc30 552 vs 603 -- still ~1/4 of BARb's. Open: yards
die (up to 25/24 a game) because BARb's water seat opens its yard at minute 2
and holds our shore before ours stand; T1 ships read `:losing` off records
learned from outnumbered losses; amphibious tanks walk across the enemy fleet
(docs/24); water eco (tidal) still unbuilt.
Arms tried on top of the ship Outgrown fix and not kept (inc30, wiped of 6):
navy fix alone 603, 0; + every seat and the commander may build a shipyard
after the first plant 318, 2; + tidal 345, 1. Diffs in the session scratchpad
are not durable -- rebuild from this description.

## AIR

### The 09-29/30 air rework is unmeasured (2026-09-30)

Everything air from those two nights was seen only in his multiplayer games
(Ascendancy 8v8, Supreme Isthmus), never in a lane batch, and he is "not
confident about it". Unverified, each with its log line:
- decoy fighters lead a wave, the rest guard (`air vanguard decoys=N of M`);
  in his 09-30 game every wave read `decoys=0 of 0` before the finished-plane
  fix, so the split itself has never been seen working at scale;
- waves wait for their escort (`EscortWant`), any bomber-holder buys it
  (`escortf`), releases count finished planes only;
- hunters take fighters past the escort to the stock AA task (`air hunt`);
- no unarmed scouts while their fighters fly (`ScoutsDie`), scout flight only
  with a raid, bought by the scout seat once bombers stand;
- wing target switches to their front when throughput < 0.5 (`air target
  front|deep` -- logs on no-change too: no bombers read throughput 0);
- bombers keep their aims (`bomb spread ... keep= retarget=`).
Test on Carrot Mountains (his air map) against BARb before trusting any of it.

Loose ends: the scout flight can still take fighters the escort needs; the
support-call `worth` is in the wrong units (spot income is not m/s -- read
926,855 per spot) and is now only a log value since the army no longer reads
it; army in flight (`PendArmyMWithin`) is still nameplate, not metal-fed.

### A T3 nuclear bomber reaches the base (2026-09-15)

His 1v1 (54 min, lost to a Ragnarok): one enemy nuclear bomber got through
at ~33 min and took 43 nano turrets and a share of the eco with it
(`unit-destroyed armnanotc` 43 in 30-35 min; workers 40 -> 15). What the
AA layer reads against a T3 flyer, and whether the air-defence want prices
one plane's payload against the base it flies over, is unread. The army
then went passive on the massing law (`stance -> passive`, foeMass 188k
against ours 73k) -- outmassed 2.5:1 at +100%, which is the ARMY SHARE
issue, not timidity.

### BOMBERS: the wing flies at the deadline into the AA and dies whole; the seat's bombing output is unread (2026-09-12, 09-14)

`tournaments/20260912-141649-scouts2`, Greenest 2v2: every strike died to the
last plane -- `deadline bombers=12 fighters=8 enemyAA=10200` then `run scored
sent=11 home=0 surv=0.00 dmg/bomber=0`; "deadline" is a clock
(`AIR_DEADLINE`, `DeadlineBombBar` 12) overruling a model that says the run
will not pay. "Wing at its worth" re-released six times in five minutes as
each wave died (`A-s4`). Since then: the bomber bids in the army's currency
(`a13edb2f`; wings of 10-17 mass, `sent=17 home=17 dmg/bomber=412`), the
wing is weighed by cost (`9abf16ae`: nine Tyrannus counted as nine of a bar
of 22), the losing-ground hold-off is gone (`7f2649c1`), the ex-seat is a
second assassin. His ask stands until a watched game shows the raids: read
`apex: wing` and `facqueue` for the seat after it turns. The non-lead
`apex_air_home_wave` bar (update.as:510) was never given the frozen snapshot
the lead's has.

2026-09-20, his Frozen Ford game (`matches/_engine`, t0) and lane seed 1: a
run ends before it arrives. `ReArm` ends the run when what was built since
is the bigger force (`held <= have` fails), and a four-plane wave has that
the moment one plane finishes at home -- `air strike -- deadline bombers=4`
at 28.2m, `air strike over -- 2 of the wave home, 3 built since` at 28.8m,
36 seconds later, planes still en route; `RecallWave`'s move is then
overridden by the bomb task they already hold, and they died at the map's
far edge one by one (the Liche among them, at 29.1m). The rule needs the
wave to have ARRIVED before "the bigger force is at home" can be read.

## INSTRUMENTS, PERF, TREE

### PERF: a hover plant whose units cannot leave reads "open" and is re-checked ~10x/s (2026-09-26)

His live Carrot Mountains 4v4, team 11: `corhp` at 11472,4655 logged
`plant-walled ... enc=0.04 v=0.002 best=0.000` 2,305 times in ~4 game-minutes,
and its `corsh` hovers logged `movefail-unit ... n=25` over and over. He
watched units stuck in the plant. `PlantEnclosure` measures only the building
crowd on three sides (`PfCrowdAt`), so it cannot see terrain or a water edge at
the exit, and nothing tests whether a fresh unit can actually path out. Units
that fail to path re-request paths, which costs every client. Open: a
per-plant exit test (does its own product path out?), and rate-limit the
`plant-walled` line.

### PERF: 16 AIs hold 1x to ~5,600 units; order volume unread since the revert (2026-09-06)

8v8 Isthmus seed 1 on a 5800X3D: 32.5 ms/frame at 5,492 units, breaks at
5,869, 47.7 ms at 6,998 (minute 59); the AI is 18-19% of the frame, 0.567
ms/AI against the 0.417 target; the engine alone crosses 33 ms at ~6,400
units, so the late minutes are simulation cost. `apex: order-src` read
~4,400 orders/min for 276 units (one per unit every 3.8 s; escort
contradicting itself 99% of repeats) BEFORE the 09-07 fight revert;
`tools/orders.py --unit N --pairs` (`apex_order_trace=1`) has never been
pointed at a game. `ai-performance` skill owns the procedure.

### CONSOLE: the log leaves the chat; the hour-scale effect is unverified (2026-09-12)

The AI writes `apex-t<team>.log` and `run_match` merges it back
(`tools/apexlog.py`). Not verified: that a 60-minute 8v8 no longer reaches
LuaUI's emergency collect (`grep "Emergency garbage"` in the next long
infolog; the 09-12 benchmark hit 606 ms/frame at minute 58).

### Cull not done: `policy.as` is 16 dead accessors and 26 unread tunables (2026-08-31)

One call site tree-wide (`Policy::AntinukeIncome`, want_super.as:504); the
other 16 accessors, their `TUNE_` constants and `dev_tunables.lua` entries
are live modoptions wired to nothing. `python tools/as_scope.py --dead` lists
them and 91 unreachable functions. `TUNE_CON_LOG_*` are drawn by the
dashboard and `apex_t2_metal` lives on as `T2_BAR = 30` in `audit.py:848` --
both his call. The one real issue under it: `want_super.as` stacks an income
floor on the antinuke because `afford` rewards being cheap by construction.

### Tools still blind to units under 120 metal (2026-09-05)

`dev_stats_export.lua` diverts defs cheaper than `SPAM_COST=120` into
`cheapBuilt=`; `tools/army_mix.py` reads `top=` only (the top four),
`tools/expected_units.py:117` reads `allBuilt=` only. `composition.py` was
fixed; the other two produced the false "Cortex builds no rocket bots"
finding (corstorm is 110 metal, armrock 120).

### The repo DLL is the 2026-09-06 build (S3 family)

`ai/Unstable/engine-side/SkirmishAI.dll` was last committed `af2a266e`
(09-06); every C++ binding since (`GroundConnected`, `GetAllyDefences`,
`GetThreatAt`, `GetAllyDefendInflAt`, `KeepsExit`, `NoteUnsafeSite`) exists
only in lane/vendor builds. `deploy_ai.py` prefers the local build when one
exists and says "(repo copy -- no local build in vendor/)" otherwise -- a
deploy from a fresh checkout ships a script that cannot compile against it.

### `ExecuteWant` throws inside `CmdMoveTo` on a condemned reclaim target, intermittently (2026-09-06)

execute.as:418, the WK_RECLAIM branch: `tgt` is null-checked and its def
read, so the throw is inside the binding -- the target dying between the
check and the order (S13). 1x and 4x in two 16-AI hours, absent in four
others. The exception aborts the election, so the reclaim silently does not
happen.

### THE STANDING OBLIGATION IS MEASURED AND THEN DISCARDED (2026-09-22)

`docs/23` names one obligation: army and defence hold their share of the
economy we have built. `budget.as` computes it correctly and then throws it
away -- its own header says so: "BudgetMult IS READ BY THE LOG AND NOTHING
ELSE ... the constructor floors in production.as return before anything is
priced."

The log it writes into, one baseline game of the 2v2 regime:

  f=0      army=0.00/0.23  def=0.00/0.21  eco=0.00/0.35  bp=0.00/0.16
  f=5400   army=0.07/0.18  def=0.18/0.20  eco=0.38/0.42  bp=0.37/0.15
  f=10800  army=0.43/0.17  def=0.10/0.27  eco=0.31/0.35  bp=0.16/0.16

At minute 3 army is at a third of its target and build power at 2.5x its own;
by minute 6 defence is at 0.10 against 0.27. `BudgetMult(ARMY)` sits pinned at
its 2.00 ceiling throughout. Nothing reads it.

Why the earlier wiring read inert: 56% of opening decisions never reach the
priced draw. Over 20 games, decisions before minute 4 by `why=`: draw 487,
estall 277, role 151, nanofloor 82, ladder 57, cover 47, firstplant 40. A
multiplier on the draw's ticket odds can only touch the 44%.

Why it matters more than anything else measured this session: army
differential is the only opening metric that predicts the win within a start
box (AUC 0.682 at minute 4, 0.704 at minute 6, against 0.528 for our own
minute-4 extractor count -- `tools/predict.py`), and every arm run today
carries the same deficit, -1,180 at minute 4 and -1,924 at minute 6,
untouched by any of the eleven levers in docs/33.

Not attempted here. It is a decision about what outranks what, which is his.

### MEX GUNS: 57% COVERED AGAINST BARb'S 84% AT MINUTE 6 (2026-09-22)

His complaint, and it is not that we never try. Defence IS elected -- 715
times against metal/mex's 263 over 20 games -- and the funnel is healthy
(`apex: defwhy` reads `WIN armllt`). Two things eat it:

- The e-stall hoist takes the hand off `defence/protect` 95 times and off
  `metal/mex` 180 times per 20 games. `ISSUES` already concluded "the defence
  hole is the e-stall's shadow", and bounding the e-stall's fabricated demand
  (TUNE_E_FEED_BOUND, docs/27) cut its firings 13.9 -> 9.7 a game and changed
  no outcome. So that is not the whole story.
- Guarded share: 3.1 of 6.3 extractors at minute 4 (BARb 5.0 of 8.1), 3.4 of
  6.0 at minute 6 (BARb 7.8 of 9.3). BARb adds 2.8 guarded mexes between
  minute 4 and 6; we add 0.3.

Untested: `apex_cover_push_s` (10 s of economic power) is the affordability
bar on the mex-cover queue jump and has never been swept. `tools/mexkill.py`
is the outcome instrument -- we lose 1.41 extractors a game by minute 6 and
0.67 more killed mid-build, against BARb's 0.95 and 0.03.

### NANO BLOBS: 53 TURRETS ON ONE AIR PLANT, 21k METAL (2026-09-22)

His read, watching: "sometimes we make huge nano blobs for little reason."
`tools/nanoblob.py` on the gate set, our side at 28 minutes:

  frozenfo-s5  101 turrets in 8 groups -- 85 in ONE group, 53 of them within
               350 elmo of a single armaap
  frozenfo-s6   84 turrets in 11 groups, one group of 14 sitting 2,937 elmo
               from the nearest plant at all

At 210 metal each that is ~21,200 metal in s5, and 53 turrets is ~10,600
build power on one advanced air plant that cannot consume a tenth of it.

It is NOT the SITE feedback he suspected. The priced want subtracts the lathe
already standing at the site (`ringEat` + the site's crew, want_nano.as), so
each turret makes the next worth less; and `FactoryNanoShort` is hard-capped
at 9 per plant for tier 3, 4 for tier 2, 2 for tier 1, so the floor cannot
reach 53 either. The `sink` term reads 0.0-2.3 m/s after minute 15 in all
four seats.

**It is the LINE term, and the answer to his question is yes.** Tabulating
`apex: nanowant`, the `line` term (NeediestLine) is what `over` equals in
62-81% of samples in every seat, and after minute 15 it averages 22-322 m/s
while `feed` (FreeMetalFlow) averages 3.9-19.3 and `idle` (nano lathe with
nothing to lathe) averages 290-496. `LineUnserved` cannot exceed `feed`, so
the excess is entirely `NeediestLine`'s shift term,
`LowerLinesEat(f) - LineEat(f)`. Reconstructing that from the final
`[BARAI_POS]` snapshot reproduces the logged numbers exactly:

  s5 t0  armaap  ring 39  eat 306.6  lowerEat 356.2  shift  +49.6   (log 42.9)
  s6 t1  armshltx ring 7  eat 153.0  lowerEat1007.0  shift +854.0   (log 724.1)

Two mis-measurements make it grow with itself:

1. **Shared lathe is counted once per lower line and subtracted once.** The
   85-group has armlab, armap, armalab and armaap inside 632 elmo, and a
   turret reaches 400, so one turret sits in several rings. Per turret added
   in reach of {armlab, armap, armaap} the aap's own shift rises by
   `200*(.0643+.0224-.0383)` = **+9.7 m/s**; for the T3 gantry over four
   lower plants it is **+20.3**. Building a turret raises the demand for the
   next one. De-duplicating (only lathe the asker cannot already reach is
   shiftable) turns every T2 case negative: s5 t0 armaap +49.6 -> -57.8,
   armalab +42.9 -> -98.6; s6 t0 armalab +41.2 -> -114.8.
2. **A capacity is read as a flow.** `LineEat` is BP times density -- what
   the ring WOULD eat. s6 t1 claims 1007 m/s shiftable on a team whose whole
   game averaged 86 m/s built (`mBuiltReal` 154,467 / 30 min), with 496 m/s
   of that lathe measured idle at the same instant.

Both are fixed in `sites.as` (de-duplicate, and bound the shift by
`MetalMoved()` = min(pull, income + bank/60)). Untested -- see the commit.

**The groups far from any plant are not a bug, they are his fortress.** The
extended `nanoblob.py` splits every group by what it rings, and there is no
group ringing nothing:

  s6  group of 14 @2386,3425  GUN   rings: armanni x1        (nearest plant 2937)
  s6  group of 15 @1701,5880  GUN   rings: armamb x1, armsolar x1

`armanni` IS the Pulsar. This is his 2026-09-22 complaint from the other
side: one gun, a ton of nanoturrets around it. Two things put them there and
neither is priced:

- `BigEcoDef` is `gCostM >= 2500 || gMakeE >= 400`, so the Pulsar (3500) and
  the Rattlesnake (2500) are "big eco frames". That exempts them from the
  remaining-life scaling in want_nano.as (their turrets are treated as
  working forever after completion, the exemption written for a reactor
  cluster), and it wins them execute.as's last sink branch over a served
  line.
- That branch is **silent and unpriced**: it takes the first matching live
  task in `Requests::gLive` order, logs nothing, and sets `sited`. 65 of
  t0's 84 turrets in s6 carry an `apex: nano-to-line` line; the rest do not.

Do NOT answer this by cutting the ring at the gun -- docs/24: where the
turrets are massed, that ground is worth fortifying. The open work is the
fortress (more guns, a shield on that ground), plus pricing that execute
branch so it is a decision rather than a fallthrough.

### SCAV MODE: EPIC STATS BEAT AN EMPTY TRADE RECORD (2026-09-22)

His read: with scav units on we buy drone carriers and Epic Tumbleweeds, and
then cannot stop Titans and Thors.

The mechanism is not that the worth model ignores scav units -- it is that it
stops ignoring them. `worth.as` scores a combat unit on RANGE/DAMAGE/HP
normalised over the field, and it deliberately restricts that field to defs
reachable from OUR OWN commander, precisely because scavenger units otherwise
poisoned the means ("corblackhy at 21,000 metal still ranked 5th"). With
`scavunitsforplayers=1` those defs BECOME reachable, so they re-enter the
yardstick and are buyable -- and an epic's stats are enormous.

The corrective that should catch it is his own unit-track-record ruling, and
it cannot: `record.py` over his live 154 KB `apex-record.txt` lists no scav
unit at all. Every scav matchup therefore has zero history and prices at its
prior, so the stats win by default and keep winning -- we buy the unit, it
trades badly, and the loss lands on a pair the matrix has no row for.

`behaviour_scav_units.json` exists but covers only six T3 eco buildings; it
says nothing about any scav combat unit.

Do not answer this with a hand-set `apex_worth_armvadert4`. The derived form
is the one the matrix already uses for pairs (`RecordRatioVs` shrinks a
matchup with no history toward its tier read): a unit whose stats are far
above the field AND which has no exchange history of its own is a unit the
model has no evidence about, and should be priced toward its class rather
than at its stats. Unmeasured; his call on whether that is the shape.

### WE REACH T2 FIRST AND THEN WAIT EIGHT MINUTES TO BUILD A FUSION (2026-09-22)

His read: "we're definitely not focusing on economy enough... it looks like a
player who doesn't care that much about expanding their economy."

Measured over the 21-game Glacier Pass arm, per SIDE (tools/ecoside.py, which
sums teams 0+1 as ours -- a per-team table labels our own second AI as the
enemy, S16):

  first T2 plant   us  8.0 min (21/21)    them  8.6 min (21/21)
  first fusion     us 16.2 min (16/21)    them  9.7 min (21/21)
  fusions built    us  2.5 avg            them  6.2 avg

We tech FIRST and then sit on it for 8.2 minutes; they convert in 1.1. In five
of 21 games we never build a fusion at all.

What we buy instead, one game's energy elections: armwin 48, armadvsol 14,
armsolar 11, armfus 3. Standing generators per side at minute 20: ours 45.5
small / 2.0 big, theirs 16.2 small / 4.6 big -- and their SMALL count falls
from 28.7 at minute 8 while ours climbs from 30.4.

Metal invested in economy diverges at the same moment the fusions do:
minute 12 us 6,621 them 7,721; minute 16 us 11,032 them 19,191; minute 20 us
18,061 them 30,709. Metal income minute 20: us 152, them 302.

Note before pricing anything: on raw energy-per-metal wind is not worse than
fusion (wind ~0.275 E/s per metal, fusion ~0.23), so a rung chosen on that
ratio alone will keep choosing wind and is arguably choosing correctly. The
question this raises -- and it is not answered here -- is what wind costs that
the ratio does not price: 45 scattered buildings against 16, the ground they
occupy, and the build power spent walking between them.

### THE T2 SWITCH SUPPRESSES ARMY AND NOTHING PULLS THE FUSION THROUGH (2026-09-22)

Follow-on from the entry above, and it names the mechanism.

His 2026-09-21 ruling, quoted in army.as: "make enough army for a normal
defence of ourselves and then stop making army to focus on the switch to a
good T2 economy -- upgraded mexes, fusions, advanced converters."

`apex: t2switch` in a baseline game reads `on` from frame 18 and stays on,
carrying `NOFUS NOCONV` the whole time -- the switch knows a fusion is
missing, continuously, from minute 0. The first fusion still lands at minute
16.2, eight minutes after our first T2 plant at 8.0.

What the switch does is take the army's share OUT of the target. That is the
whole of it. The metal it frees is then handed to the ordinary draw, and the
ordinary draw buys wind: one game's energy elections read armwin 48,
armadvsol 14, armsolar 11, armfus 3.

So the switch is a permission, not a pull. The thing it exists to buy is
named in his ruling and is exactly the thing that does not get bought.

Same shape as the budget entry above: a signal computed correctly and then
read by nothing that decides.

Untested candidate: while the switch is on and the fusion is the missing
piece, a fusion want in the ranked list is TAKEN rather than sampled -- the
same shape as every other floor in decide.as. That is arguably implementing
his ruling rather than inventing policy, since the ruling names fusions as
the switch's purpose, but it is his call and it is unmeasured.

### HANDS CHANGE THEIR MINDS MID-WALK: 23% OF JOB CHANGES INSIDE 5 SECONDS (2026-09-22)

His read, watching one unit: "it's almost like he can't make up his mind, what
is important... if I was to pick a constructor, like the first constructor
that comes out of a lab and just analyze what that constructor does, that
would probably be very telling."

`tools/onehand.py` follows one hand through its whole working life. The first
constructor of one game, six elections in 6.4 minutes:

  0.9m  energy/energy:armsolar     why=estall
  1.6m* metal/mex:armmex           why=ladder
  2.6m* defence/protect:armbeamer  why=cover
  3.7m  defence/protect:armbeamer  why=cover
  5.7m* energy/energy:armadvsol    why=draw
  7.3m* energy/energy:armwin       why=draw

Four of six elections changed the job. Across 8 games, 44-65% of every
constructor election changes what that hand is doing.

A change is not automatically churn -- a hand re-elected after finishing is
correct. The discriminator is time, and it is damning: of 2,025 job changes,
**23% land within 5 seconds of the previous election and 30% within 10**,
median gap 25 s. Nothing can be walked to and finished in five seconds, so
those are hands redirected before they could accomplish anything -- about 57 a
game.

The repo already says why this is possible: stuck.as records that "the engine
only re-elects a builder while it is AWAY from its build position", so every
re-election lands on a hand mid-walk.

And the existing guard does NOT cover it. `expect.py`'s "builders finish their
walks" counts only `apex: stuck --` aborts, i.e. hands the STUCK WATCH freed;
a hand the MARKET moved is invisible to it. That check reads OK at 11-18 per
30 min while this is running at ~57 a game.

Not fixed. The shape of a fix is a pricing one and needs care: abandoning a
job should cost what has already been walked and built toward it, and nothing
in the election charges that today. A dwell time would be a threshold and is
the wrong answer.

### SEEDING THE UNIT RECORD FROM HIS LIVE GAME COLLAPSES OUR ARMY SPEND (2026-09-22)

A harness change landed mid-day: every Apex AI in every batch is seeded from
`matches/_engine/.../apex-record.txt` before each match, so each game starts
from the evidence his own games built.

It is not neutral. `wr-round2` (seeded) and `wr-noseed16` (--no-record-seed)
run IDENTICAL code on the same regime and differ only in this:

  our metal            seeded      unseeded     BARb
  army (real)            1.3%         12.8%     24-26%
  constructors           0.6%          2.9%       8.5%

The earlier seeded arm `wr-fixes32` agrees: army 2.2%, constructors 0.6%.

Win rate moves the same way -- 2/32 (6.2%) seeded against 2/16 (12.5%)
unseeded, with this morning's 551 unseeded games at 17.6% -- but both arms
hold only two wins, so the win rate is not what carries this. The composition
split is, and it is a factor of ten on identical code.

Mechanism, consistent with what the scav work found separately: the record is
a metal-for-metal exchange matrix and a unit with a bad remembered exchange is
priced down. His live record is out of distribution for this regime -- other
maps, other team sizes, other factions, and scav games (it carries
`armvadert4` at 54 metal dealt against 35,105 taken). Seeded with enough bad
rows, every unit looks bad and almost no army is bought.

Two consequences:
- Every arm run after the change is polluted, including the ones used this
  evening to judge the nano fix and the fusion timing. This morning's 551 are
  not.
- The army deficit measured all day (-1,180 at minute 4, -1,924 at minute 6)
  is real in the morning data but was AMPLIFIED by the harness in the evening
  data.

Not reverted here: the change belongs to another session working in this
checkout. `--no-record-seed` exists on run_match and run_tournament so any arm
can be run without it.

### FIVE HOVER PLANTS, ZERO HOVER UNITS (2026-09-22)

His complaint: "we almost always make hovers at some point in our games --
even when there's no water on the map, and often late in the game past T2.
Hovers are only T1 units."

Measured over the 16-game Glacier Pass control arm (tools/plantuse.py):

  armhp (Hovercraft Platform, 750 metal) built 5 times
  armch/armsh/armanac/armah/armmh produced:  ZERO

Five plants, 3,750 metal, no unit ever came out of any of them. Median first
build: minute 29 -- a T1 factory started half an hour into a game.

It is not only hovers. Plants per game and when the first one lands:

  armlab   2.38   1,188 m   4 min      armshltx 0.31  2,469 m  32 min
  armalab  2.06   5,981 m  11 min      armaap   0.25    800 m  30 min
  armap    1.25     888 m  24 min      armavp   0.19    544 m  38 min
  armvp    0.69     406 m  19 min      armhp    0.31    234 m  29 min

About 12,500 metal a game goes into plants, and the late T1 ones (air at 24,
vehicle at 19, hover at 29) are capacity bought after the tier it serves
stopped mattering.

This is his general form of it: "these plants should only be built if we
actually desire to create something out of it. If we don't genuinely want one
of the units it can produce, then we should not be making it."

Blocking a fix: THERE IS NO PER-PLANT OUTPUT LOG. `plantuse.py` had to infer
production by counting the unit types a plant can build, because no line says
which factory a unit came from. A `fac=` field on the unit-finished line
would make "was this plant worth it" directly readable and is the first thing
to add here.

### A QUARTER OF OUR METAL IS SPENT ON UNCONTESTED WANTS (2026-09-22)

Over 8 games of his 2v2 regime, summing `m=` on every `apex: decide` line and
splitting by whether the line reads `over nothing`:

  decided metal            3,303 k
  chosen with NO rival       718 k   22%

  energy/energy   225 k     defence/protect  71 k
  buildpower/nano 161 k     airdef/airdef    56 k
  produce/plant    86 k     sense/sense      38 k

For that 22% the hand had exactly one executable want and took it. There is
no auction, no comparison, and therefore nothing a price can change.

This is the structural reason four separately-correct pricing fixes each
moved their own metric and left the outcome alone, and it is why the plant
work concluded "discounting cannot remove them, only an exact zero can" -- an
uncontested want wins at any price above zero.

It also puts a ceiling on the budget lever: it scales want VALUES, so it can
only steer the 78% that is contested. Measured with it on, defence share rose
0.16 -> 0.23 and economy did not move at all -- economy is the category most
often decided with no rival (225 k of the 718 k).

The question this raises is not "what should these wants be worth". It is why
a constructor standing in our own base has ONE thing it can propose. Whether
that is the per-hand filtering (can-build, site found, reachable), the refusal
memo, or genuinely empty ground is not established here.

### WHY A HAND'S ONLY OFFER IS ENERGY (2026-09-23, partly open)

Follow-on from the 22%-uncontested entry. The new `apex: offers` census says
hands are not generally starved of choice -- mean 3.1-4.3 wants an election,
13-16% of elections have at most one -- but the lone want is most often
ENERGY, and energy is the biggest slice of the uncontested metal (225 k of
718 k).

The extractor side is what goes missing. `want_mex.as:577`: a candidate spot
already in our own request ledger is skipped (`++gMexClaimed`), and the search
gives up after `TUNE_MEX_TRIES` (10) ranked candidates. So a hand whose ten
best spots are all claimed proposes NO extractor, and whatever else it can
build wins with no rival.

NOT ESTABLISHED, and it matters: `claimed=415..653` in a diag window counts
REFUSALS, not distinct spots. Glacier Pass has 34 spots and we hold 10-14, so
most of those refusals are probably many hands repeatedly hitting the same few
spots we are already correctly building -- which would make this benign. The
measurement that settles it is distinct claimed spot IDs per window against
the number of free spots, and it has not been made.

If it is NOT benign, the shape of the problem is that a claim blocks every
other hand regardless of how far away or how slow the claimant is -- a hand
600 elmo from a spot cannot take it from one 3,000 elmo away. That is a
serialisation, not a price, which is consistent with the finding that pricing
fixes do not reach this 22%.

#### Resolved: the claim ledger is NOT it, on his map

Measured on Glacier Pass (his regime), not Frozen Ford (the gate map the
earlier numbers came from):

  mexdiag mapSpots=19 held=0..3 | noOpen=11..16 claimed=0 deathWalk=6..14 priced=0

`claimed=0`. The ledger blocks nothing here, so the serialisation theory above
is dead for this regime. The refusals are `noOpen` and `deathWalk` -- the walk
to the spot crosses ground the model judges lethal -- and `priced=0` means not
one spot reaches a price in those windows.

Note the map difference that produced the wrong lead: Glacier Pass has 19
spots, Frozen Ford 34. The `claimed=415..653` figures quoted earlier are the
GATE map and do not describe his 2v2.

What it means: late in these games we hold 0-3 of 19 spots and decline to take
more because the journey is fatal. That is not an economy fault and no price
can fix it -- expansion is gated on territory we do not hold. It is the same
conclusion the minute-4 work reached from the other end, and it points at the
army/defence share obligation rather than at any want's pricing.

### THE SHARE OBLIGATION CANNOT BE ENFORCED FROM THE CONSTRUCTOR SIDE (2026-09-23)

Three attempts tonight, all measured, all failed the same way.

1. Scale want VALUES by BudgetMult (target/actual). Defence share 0.16 ->
   0.23, economy unmoved, 32 games at 3.1% against 48 at 12.5%. Shipped off.
2. Make the nano FLOOR yield while buildpower is over target, so the election
   falls through to the priced draw. Shares, minute 12+, 8 games an arm:

     off   army 0.35/0.19  def 0.14/0.33  eco 0.24/0.27  bp 0.27/0.14
     on    army 0.43/0.19  def 0.17/0.34  eco 0.17/0.27  bp 0.23/0.14

   The floor stood down as designed. Buildpower fell. The freed metal went to
   ARMY -- already at twice its target -- and ECONOMY got WORSE. 1/16 both
   arms.

The reason is the same one budget.as states in its own header and I read past:
army is bought at the FACTORY, on the produce path, and "the constructor
floors in production.as return before anything is priced". Every lever tried
tonight acts on the constructor market. Taking metal away from build power
there simply hands it to the factory, which is the category already over.

So the obligation is not enforceable from this side at all. Whatever enforces
it has to act where army is actually bought. That is the next session's
starting point, and it is a narrower question than "wire up BudgetMult":
production.as, the floors that return before pricing, and whether a factory
should keep producing while army sits at 2-3x its share.

### THE LOOP: BLOCKED EXPANSION BECOMES ARMY, AND THE ARMY DOES NOT UNBLOCK IT (2026-09-23)

This is what the three failed obligation attempts were really hitting, and it
is not a bug in any one term.

`production.as:788-816` -- armyGap is the MAX of three demands: the army
target gap, the coverage need, and `richGap`, under the comment "METAL WE FAIL
TO SPEND IS ARMY DEMAND (his standing law: the economy is for spending; waste
is free army)".

So:

  1. expansion is refused -- Glacier Pass reads `noOpen=11..16 deathWalk=6..14
     claimed=0 priced=0`, i.e. the walk to a spot is judged lethal
  2. metal cannot go to economy
  3. by the standing law, unspendable metal becomes ARMY demand
  4. army runs 0.35-0.48 against a 0.17-0.19 target; defence sits at
     0.09-0.17 against 0.29-0.34
  5. that army is coverage and spillover, so it does not take ground
  6. ground stays unheld, the walk stays lethal, back to 1

The army overshoot is therefore a SYMPTOM, not a fault, and rebalancing shares
attacks it from the wrong end -- which is exactly what the floor-yield arm
measured: buildpower stood down and the freed metal went to army (0.35 ->
0.43) while economy FELL (0.24 -> 0.17). The law did what it says.

What this rules out: every share-based lever on the constructor side. What it
leaves is one question, and it is a military one, not an economic one -- why
does an army at two to three times its own target not take and hold the ground
that would let us expand? `deathWalk` is the gate that says the ground is not
ours; nothing in tonight's work asked what it would take to change that
answer.

### THE BINDING CONSTRAINT IS THE TRADE RATIO, NOT THE ECONOMY (2026-09-23)

The loop above terminates here, and this is the number the whole session was
looking for. Our side, 8 games of his 2v2 regime:

  minute   army metal   killed   lost    kill/lost
    12        9,051      2,017   6,065      0.33
    20       21,776      9,340  19,359      0.48

We destroy a third to a half of what we lose. An army trading at 0.48 cannot
take ground at any size -- it dissolves faster than it gains, so the ground
stays theirs, the walk stays lethal, expansion stays refused, and the metal
that cannot be spent becomes more army by the standing law. That is the whole
loop, and the trade ratio is what closes it.

It also inverts the session's premise. We are not weak because we are poor. We
make about half BARb's metal AND trade at about half efficiency, and those
multiply: an economy fix alone buys more units that die at a loss. That is
consistent with every result tonight -- six mechanisms measured, four fixes
shipped, every one of them moving its own metric and none moving the outcome,
because all of them were on the buying side.

Where to go, and it is NOT this file's usual territory: docs/24-how-units-fight.md
(his directives), the fight-analysis skill, tools/deaths.py, tools/battles.py,
tools/fight1v1.py. His own standing note is already there -- trades are damage
efficiency (D%), not K/D -- and ISSUES already records "WE ENGAGE AT WORSE ODDS
THAN STOCK: thr_mod attack [1,1] / defence [1,1] vs stock hard [0.6,0.8] /
[0.3,0.5]" from 2026-09-20, unresolved. That entry and this number are probably
the same problem, and it was sitting in this file the whole time.

### WE LOSE 1.81 COMMANDERS A GAME; BARb LOSES 0.38 (2026-09-23)

The single most decisive number measured this session. 16 games of his 2v2
regime, both our teams counted:

  our commanders lost   1.81 per game
  their commanders lost 0.38 per game
  median minute ours dies  21.7

We field two. We lose nearly both, every game, at 4.8x their rate. In BAR a
commander death is catastrophic, and the median at 21.7 min is exactly where
these games are decided.

It also explains the trade ratio above without any combat-efficiency theory:
`armcom` is 48,600 metal of our mobile losses over 10 games, the sixth
largest line, and a commander lost is also the build power, the D-gun and the
rebuild capacity gone at once.

The thread back to the start of the session: this is his opening complaint --
the commander walking away and doing nothing -- and `expect.py`'s "commander
stays home" ran RED for most of the night. docs/33 records `1bf6732c` ("a
forward commander takes the work around him") as the one change that helped
the minute-4 extractor metric, measured on a metric later shown to be a coin
flip (AUC 0.528). That change keeps the commander forward. Forward is where
he dies.

FIRST TEST FOR THE NEXT SESSION, and it is cheap: does reverting or gating
1bf6732c drop commander deaths, and does that beat the extractor it was
bought for? Nothing has measured the commander's survival against the work he
does while exposed.

#### The 100%/0% split is definitional -- the RATE is not

Across 80 full-length games: 0 commanders lost -> 9 games, 9 wins; 1 lost ->
1 game, 1 win; 2 lost -> 70 games, 0 wins. Perfect separation.

That is almost certainly the win CONDITION, not a finding: the start script
sets no deathmode, so BAR's default applies and the game ends when a side's
commanders are gone. "We lose when we lose both commanders" is a tautology and
must not be quoted as a discovery.

What is NOT tautological is the rate: 1.81 a game against BARb's 0.38, at the
same stage of the same games. BARb keeps its commanders and we do not.

And that has a design consequence worth stating plainly. If commander survival
IS the win condition, then the objective in docs/23 -- fastest path to a named
army/economy state -- has no term for the one thing that decides the game. The
model prices extractors, energy, army share and build power. Nothing prices
the commander staying alive, and `conRiskM` (want_mex.as:634) charges his
exposure only to the mex want he is walking to, not to the plan as a whole.

Our win rate is 12.5%. We keep a commander in 10 of 80 games, which is 12.5%.
Those are the same number.

#### Where the commander actually dies: at home, to the main line

117 commander deaths over 64 full-length games:

  median distance from his own start   605 elmo   (p25 399, p75 932)
  killed by  armfboy 16%  armfido 12%  armsnipe 9%  armbull 7%

He dies IN OUR OWN BASE, killed by BARb's main battle line -- not forward, and
not by raiders. That weakens the "forward commander dies" reading of
1bf6732c that this entry started with, and it points somewhere else entirely:
BARb's army arrives at our base around minute 21 and there is nothing there.

Which joins the two halves of this file. Defence runs at 0.09-0.17 against a
target of 0.29-0.34 all game, we stand on 4.3 light towers to BARb's 9.3,
57% of our extractors have a gun nearby against their 84%, and the commander
dies at home to the army that walks in. His mex-guard ruling (2026-09-17) and
his fortress ruling (2026-09-22) are both about exactly this ground.

So the objective gap named above is narrower than "nothing prices the
commander staying alive": nothing prices HOLDING THE GROUND HE STANDS ON.

### DEFENCE IS ELECTED AND THEN THE HAND IS PULLED OFF IT (2026-09-23)

The missing link between "defence IS elected" and "the base is empty when
their army arrives". 8 games of his regime:

  defence elections -> towers built     725 -> 116   (16%)

  of 982 defence elections with a following decision by the same hand:
    stayed on defence          443   45%
    pulled to something else   539   55%
      of those pulled: 29% within 5 SECONDS, 49% within 15 s, median 16 s

A hand is elected to build a tower and more than half the time it is
reassigned, a third of those before it could have walked anywhere. So the
defence share cannot rise no matter what defence is priced at, and the two
levers aimed at the price both failed for that reason: the budget multiplier
(3.1% against 12.5%) and the cover-push bar (fired twice as often, built FEWER
towers).

This is the general abandonment measured earlier -- 23% of ALL job changes
land within 5 s of the previous election, ~57 a game -- hitting defence harder
than average.

THE FIX, and it is a pricing correction rather than a rule: switching forfeits
the walk already spent toward the current site, and nothing in the election
charges it, so every challenger looks cheaper than it is. The walk invested is
known. A minimum dwell time would be a threshold and is the wrong answer.

Not implemented: it is a change to the core election and this session has
already shown what an untested change to that path costs. It is the first
thing to build next, and the chain it closes is complete -- charge
abandonment -> hands finish defence jobs -> the base is held -> the commander
lives -> the game is not lost by minute 21.

#### Correction: it is not abandonment pricing, the want VANISHES

Of 337 pulls off defence, what the winning want beat:

  over nothing            124   37%
  over defence/protect     46   14%
  over defence/teeth       26    8%
  over buildpower/assist   33   10%
  over energy/convert      24    7%

In 37% of pulls the runner-up was NOTHING -- defence was not in the ranked
list at all that tick. The hand was not out-bid; it was left holding one
unrelated want and took it. Only 22% lost a straight comparison to another
defence want.

So the abandonment-cost fix proposed above is aimed wrong: you cannot charge a
challenger for displacing a want that is not on offer. The defence want is
TRANSIENT -- it exists on the tick that elects the hand and is gone a few
seconds later, which is also why 29% of the pulls land within 5 s.

The question is therefore why `ProposeProtect` stops proposing between ticks.
The defence funnel already names its own gates (`apex: defwhy`, Gate() with
def.obsolete, def.t1late, cover, fill, teampow), and one of them is presumably
flipping. That funnel is already instrumented, so the next step is to read
`defwhy` on the tick BEFORE a pull and see which gate closed -- no new
instrument needed.

Third time this session a measurement stopped the wrong fix being built: the
budget lever (it steers values, and 22% of metal has no rival), the deathwalk
gate (loosening it lost more extractors), and now this.

#### The gate that closes: the model values a tower at zero

Read straight off `apex: defwhy`'s own gate census, one game, our side:

  def.nosite    8,078      no candidate site scored a POSITIVE gain
  def.obsolete  7,819      the tower would be obsolete on arrival
  def.t1late    1,426
  def.zerogain     54      everything else negligible

`GATE_DEF_NOSITE` is `bestGain <= 0` (protect_want.as:392) -- not "no room",
but "no site is worth a tower". So the want vanishes because the model
evaluates defence as worthless at every candidate site, most ticks. That is
the terminal answer to why 37% of pulls off defence had no defence want to
compare against.

It is NOT the T2-never-built failure repeating: we do build T2 towers.
Per game, our side, 16 games: armllt 5.75, armbeamer 5.62, armamb 1.56,
armanni 1.00, armguard 0.69, armhlt 0.31 -- about 15 towers. BARb builds 9.31
LIGHT towers in the first six-minute bucket alone (docs/27, TUNE_T1_TOWER_LATE).

So the chain ends at a valuation, and the whole session's failures follow from
it: every lever tried scaled or reordered a want that the model had already
decided was worth zero. The question for the next session is what `prev` (the
metal a tower is credited with preventing) is reading at a site where BARb
would put a gun, and why it comes out non-positive there.

#### The number the whole chain reduces to: 86% of what we build is destroyed

16 games of his regime, our side, finished structures only:

  built      1,047,987 metal
  destroyed    905,238 metal      86%

We do not have an economy problem in the sense of building too little. We
build over a million metal of structures and lose almost all of it. Every
extractor, generator, plant and turret in the ISSUES entries above is inside
that 86%.

It also reframes the defence valuation directly above. A tower is credited
with preventing `stake x hz`, and the hz on a winning tower line reads
0.00833 -- while the realised outcome is that 86% of the stake dies. I am NOT
claiming a clean ratio between those: hz is a per-second rate and the gain
integrates it over a horizon, so comparing it to a per-game fraction needs the
formula, which I did not work out. What is certain is the 86%.

For the next session, the shortest statement of the problem: we build a
million metal of structures, 86% of it is destroyed, and the model's own site
valuation concludes there is nowhere worth putting a gun (def.nosite 8,078).
Those two facts cannot both be right.

#### Ruled out: hazard is not blind to our losses

`HazardWith` (coverage.as:775) computes `p = LossRateAt(pos) * gRkTau / stake`
-- it already learns from metal actually lost near the point, and takes the
max of that against the foe-mass gradient and the approach term. So the
zero-valued towers are NOT caused by the model failing to notice that our
buildings die.

That narrows the next session's question to one line: `prev` in
protect_want.as is the MARGINAL reduction in expected loss from adding this
tower, and at 8,078 sites it computes as <= 0 while 86% of the stake
eventually dies. Either the marginal term is wrong, or a tower genuinely does
not reduce the loss -- and if the second is true then towers are not the
answer to the 86% and the whole defence thread above is misdirected.

That is a question about one computation, with both outcomes actionable, and
it is where a fresh session should start. It is NOT a question about hazard
inputs, want pricing, floors, shares, claims or expansion gates -- all of
those are measured and ruled out in the entries above.

#### Do towers actually reduce the 86%? Not established

Correlation over 35 full-length games, our side, by tower count quartile:

  12-14 towers   89% of structure metal lost
  14-17          102%
  17-19          101%
  19-36           76%

The top quartile loses less and the middle two do not, so the relationship is
not monotonic, n is 8-11 a bucket, and it is confounded in both directions --
a longer game builds more towers AND has more time to lose things.

So the question the chain ends on is still open, and it is the RIGHT question:
before building anything to make towers cheaper or more available, run a
controlled arm that changes tower count alone and read structure metal lost.
If towers do not move that number, the whole defence thread in these entries
is misdirected and the 86% is caused by something else -- most likely that we
lose the field army and everything static follows.

Do not take the 76% as evidence for towers. It is a correlation with an
obvious confound and it is recorded here so nobody quotes it as a result.

#### Towers DO reduce the 86%, and his no-basic-tower rule is what holds them down

The controlled arm the entry above asked for. `apex_t1_tower_late` 1 vs 0,
16 games each, nothing else changed:

                          towers/game   structure metal lost   wins
  =1 (his rule, default)      14.4            101%             1/16
  =0                          18.3             77%             3/16

The knob moved tower count by 27%, so the arm tested something, and structure
loss fell 24 points. That is a continuous per-game measure and it is the
quantity the 86% question is about -- unlike the win count, it is resolvable
at this sample size.

So towers DO reduce the loss and the defence chain above is pointed the right
way: `prev`, the marginal gain credited to a tower (protect_want.as), is
under-valuing them, which is why def.nosite fires 8,078 times.

THIS IS HIS OWN RULING (2026-09-19, no basic tower once an advanced hand
exists) and docs/27 records it as "measured innocent". That earlier test
counted LIGHT towers in 6-minute buckets and read 4.31 -> 4.56 with mexes lost
unchanged. Measured over the whole game against structure metal lost it looks
expensive. The two tests do not contradict each other; they measure different
things, and the later one measures the thing that matters.

His call, not a default to flip unasked. A 32-game confirmation is running;
the 18.8% win figure in particular must not be quoted until it replicates,
because an identical-looking 18.8% failed to replicate earlier tonight.

#### Why prev is zero: it is gated on VISIBLE threat, while hazard learns from losses

protect_want.as:264 states the rule outright: gain is "the stake standing in
its reach, times how often lethal force arrives there, times the share of the
local threat it newly stops", and "once standing cover already exceeds the
threat, the next turret prevents nothing and prices itself out".

That last clause is the whole of def.nosite's 8,078 firings. Cover >= threat
-> prev = 0 -> no want -> the hand is pulled away -> no tower.

And the threat it compares against is what we can SEE. The repo's own standing
trap applies exactly here: gates keyed on visible enemy strength read "safe"
precisely when we are blind. BARb's army masses out of sight, cover looks
sufficient against the nothing we can see, no gun is bought, and then the army
arrives and takes 86% of what we built.

The asymmetry is the tell: HazardWith already learns from metal actually lost
(LossRateAt, coverage.as:775), so one half of the defence valuation is
evidence-based and the other half is line-of-sight. A tower's prevention
should be measured against the force that ACTUALLY arrives -- which the AI
already records -- not against what is visible at the moment of the election.

That is the fix, it is a mis-measurement rather than a policy, and it would
let towers arrive on their own merit instead of by switching off his
no-basic-tower rule. Not built: it is a change to the core defence valuation
and this session has shown three times what an untested change there costs.

##### Correction: the "cover exceeds threat" mechanism is NOT established

The entry above took protect_want.as:264's own comment as the explanation for
def.nosite. Checking it against the logs does not support it and cannot refute
it either:

  778 defwhy samples carrying threat/cover
    standing cover >= threat :   0   (0%)
    cover <  threat          : 778 (100%)   typical: threat 255-270, cover 0 -> 210

So in every sampled election a tower DID have threat to stop. But `apex:
defwhy` is emitted only where a tower WON (`SAMPLE 1of1wins`), so these are
the successes. The 8,078 def.nosite refusals are not sampled and nothing here
says why they failed.

What stands: def.nosite is `bestGain <= 0` over candidate SITES
(protect_want.as:392), it fires 8,078 times, and towers demonstrably reduce
structure loss (101% -> 77% at +27% towers). What does NOT stand: my claim
that the cause is cover already exceeding visible threat. That was the code
comment's account, not a measurement.

The instrument needed is one line: log the refused sites' gain components at
the moment `bestGain <= 0`, the way defwhy logs the winners. Until that
exists, the cause of the single largest defence refusal in the game is
unknown.

##### Confirmation: the tower effect is real but much smaller than the first arm

32-game confirmation of `apex_t1_tower_late=0`:

                        towers/game   structure lost   wins
  =1 (his rule, 16g)       14.4          101%          1/16
  =0        (16g)          18.3           77%          3/16
  =0 CONFIRM (32g)         15.7           86%          4/32  12.5%

Neither headline from the 16-game arm replicated: 77% came back at 86%, and
18.8% came back at 12.5%. Pooled over 48 games, =0 gives ~83% structure loss
and 14.6% wins against a 16-game control at 101% and 6.2%.

The direction survives -- more towers, less structure lost -- and the
magnitude does not. The control is also only 16 games, so the 101% figure is
itself thin. This is NOT grounds to flip his no-basic-tower ruling.

Second time tonight a 16-game arm produced a headline that a 32-game
confirmation erased (the other was the three-fix bundle, 18.8% -> 9.4%). At a
12.5% base rate, 16 games resolves nothing about win rate, and evidently not
much about structure loss either. Anything claimed from a 16-game arm in this
file should be read with that in mind.

##### ANSWERED: def.nosite fires because the candidate site list is EMPTY

The diagnostic ran (after the modoption had to be whitelisted -- S8 again, my
second time tonight). 90 refusals in one 20-minute game, and every single one
reads the same way:

  nosite armclaw  sites=0 negative=0 bestPrev=0.0000 gap=324 wallPull=2.7018 lineN=0
  nosite armguard sites=0 ...
  all 90 lines: sites=0

  by def: armguard 34, armclaw 29, armhlt 15, armanni 12

`gDsPrev[d]` is EMPTY. The gate is not "no site scored a positive gain" -- it
is "no candidate site was generated at all", and it happens for the heavy and
T2 defences specifically, while `gap` says a shortfall exists (94-456) and
`wallPull` is positive.

So the model never evaluates a place to put a heavy tower. That is why we
stand on 1.00 armanni, 0.69 armguard and 0.31 armhlt a game.

This REDIRECTS the whole defence thread above. The cause is site GENERATION
(whatever populates gDsPrev / DefSiteFill for a def), not the prevention
value, not hazard, not visible threat, not cover, and not the budget share --
all of which were probed tonight and none of which is reached, because the
loop that would use them never has a site to score.

The next session starts here, and it is a narrow question: why does the site
builder produce zero candidates for armguard/armclaw/armhlt/armanni while
producing them for armllt/armbeamer?

##### The mechanism behind sites=0: the one-fill-per-frame throttle

`DefSiteFill` (protect_fill.as) has three exits in order:

  1. GATE_FILL_CACHE  -- fresh cache (4 s), returns and SERVES the cached arrays
  2. GATE_FILL_FRAME  -- `gDsFillN >= 1`, one fill per frame, returns WITHOUT
                         filling anything
  3. the fill itself, which assigns gDsPrev[d] at the end

Exit 2 is the one that produces `sites=0`: a def that has never been filled and
loses the per-frame race returns leaving `gDsPrev[d]` empty, and the caller
then reads an empty array and raises def.nosite. The throttle is there for a
real reason (each fill is ~5.5 ms once the base is large, and two per frame is
an 11 ms frame from this source alone).

NOT ESTABLISHED: why the losers are ALWAYS armguard/armclaw/armhlt/armanni
rather than rotating. With a 4 s cache (120 frames) and one fill a frame there
is capacity for every def many times over, so a naive reading says they should
take turns. They do not -- 90 of 90 refusals in one game were those four.

That is the next question and it needs one counter: how many frames pass
between a given def winning the fill slot. If the answer is "never for these
four", the throttle's ordering starves the heavy guns permanently and the fix
is to rotate the slot rather than give it to whoever asks first.

This is a PERFORMANCE THROTTLE deciding the AI's defence composition, which is
the kind of coupling CLAUDE.md's "spread work across frames" rule exists to
prevent -- the work is spread, but the same def wins every time.

### STATIC DEFENCE DOES NOT SAVE THE COMMANDER (2026-09-23)

The session's chain broke at its last link, and the break is measured.

`apex_fill_firstpass` fixed a real defect -- a frame throttle returned an
empty site list and the caller read it as "nowhere worth a gun" -- and it
works: heavy towers 0.8 -> 5.3 a game (6.6x, replicated over 48 games),
structure lost 19 points better, games 26% longer.

Commander deaths: 1.94 against a 1.81 baseline. Unmoved. Wins 4/48 = 8.3%
against a 12.5% baseline. Unmoved.

So more guns make the base survive longer and the commander still dies, to the
same main line (armfboy/armfido/armsnipe/armbull), at the same rate, a median
605 elmo from his own start. The proposed chain -- towers -> base held ->
commander lives -> game won -- is false at the last step.

What that leaves, and it is now the sharpest open question in this file:
what actually kills the commander, given a base with five times the heavy
guns? Either the guns are in the wrong PLACE (the site list is now non-empty,
but nothing has checked whether those sites are near him), or the commander is
somewhere the guns are not when the line arrives, or static defence simply
loses to a T2/T3 push regardless of count.

The instrument for the first of those is one line: the distance from each
commander death to the nearest standing gun of ours. That has never been
measured and it separates "wrong place" from "wrong idea".

#### Answered: static defence does not keep the commander alive (see CORRECTION below)

The number that separates the three explanations, measured on the 32-game arm
that carries 5.3 heavy towers a game:

  62 commander deaths with a standing-tower sample
  distance to our NEAREST gun: median 644  p25 466  p75 1016  min 102
    within  300 elmo: 15%
    within  600 elmo: 42%
    within 1000 elmo: 73%
  nearest gun type: armanni 21, armllt 13, armguard 8, armamb 7, armhlt 6

A light tower reaches ~230-280 elmo and a Sentry ~450, so at a median 644 the
commander dies outside the cover of the short-ranged guns that make up most of
our count. He also dies a median 605 from his own START, so this is not him
wandering: the guns are simply not where he is.

CAVEAT, and it matters: 21 of the 62 nearest guns were Annihilators, which
reach ~1100 and at 644 elmo could have been covering him. For that third,
presence was not the problem and the gun did not save him -- which is the
third explanation (static defence loses to the push) surviving alongside the
first.

So the answer is mostly WRONG PLACE and partly WRONG IDEA, and the two need
separating by range: measure the distance to the nearest gun THAT REACHES
(distance <= that def's own range) rather than to the nearest gun of any kind.
That is a one-line change to the query above and it is the next thing to run.

His fortress ruling (docs/24, 2026-09-22) is the same observation from the
other side: build up the ground where our things already stand.

##### CORRECTION to the entry above, same day

The entry above weighed "the tower reach must be weighed before claiming
this" and then did not weigh it. Weighed, it reverses the conclusion.
Distance to the nearest gun OF ANY KIND conflates a Sentry (430) with an
Annihilator (1400). Asking instead whether ANY gun's own range covered the
spot he died on:

  62 commander deaths with a standing-tower sample
    INSIDE a gun's range when he died: 39 (63%)
      that gun: armanni 19, armguard 10, armamb 6, armhlt 2
    OUTSIDE every gun's range:         23 (37%)
      elmo beyond the nearest envelope: median 371  p25 100  p75 1006
      nearest (still short) gun: armllt 8, armanni 6, armhlt 4, armamb 2

So it is mostly WRONG IDEA, not wrong place. Nearly two thirds of the time a
gun of ours could already shoot the ground he was standing on, and he died
anyway -- to armfboy/armfido/armsnipe/armbull, which one long-range turret
does not stop. That is exactly consistent with the result that motivated the
question: 5.3 heavy towers a game instead of 0.8 moved structure loss 19
points and did NOT move commander deaths (1.94 vs 1.81). More guns, or guns
in better places, is not the lever for commander survival.

The lever left is his own exposure -- he dies a median 605 elmo from home,
and the question is why he is there at all, not what is standing near him.
That is the same thing apexearth has reported from watching: the commander
walks all over the map and cannot make up his mind.

Method note for whoever reads this next: "distance to the nearest X" is
almost never the right instrument when the Xs differ in reach. Ask whether
one of them covered the point. tools/comguard.py is eight lines different
from the first version and says the opposite thing.

### The deploy gate is noise-dominated at 2 games

2026-09-23. Ran `gate.py run` twice on the SAME commit (ea75891c), same map,
same two seeds, nothing rebuilt or redeployed between them:

  run 1: RED (3) -- refused plant-copy livelock (frozenfo-s5 x97),
                    home ground is not discounted (12 readings),
                    commander never penned or frozen (frozenfo-s6)
  run 2: GREEN, no red flags

Same commit. Opposite verdicts. This is the known harness trap -- the same
seed does not reproduce here -- meeting a 2-game sample, and it means a gate
verdict carries roughly no information about the commit: a green run does not
say the change is safe and a red run does not say it is not. Every "gate
green" in this repo's commit messages should be read with that in mind.

It matters more than a normal noisy metric because the gate is the
AUTHORIZATION for deploying to the slot apexearth watches. As it stands the
gate mostly gates on luck, and the honest use of it is: a RED is worth
reading for WHICH check tripped (the plant-copy livelock below is a real
behaviour, found this way), not as a verdict.

Fixing it means more games per gate, which costs wall time on every deploy,
or scoring the checks over a rolling window of recent gate runs rather than
the last one. That is a decision about how much a deploy should cost and it
is apexearth's to make, not a session's.

Two of the three reds are worth chasing on their own evidence regardless:
  - a plant copy elected 97 times in one game that the executor refuses each
    time, with hands falling to their second pick -- that is the "want
    forwarding"/refused-election path and it is burning elections
  - median survival 0.57 for a home mex at hazard 0: home ground is being
    priced as risky when it is not

#### Third run, same content: RED (2)

Ran a third time (sha a630d0fe, ai/ and cpp/ byte-identical to the two runs
above -- only ISSUES.md changed between them):

  run 3: RED (2) -- home ground is not discounted (0.59, 13 readings),
                    commander never penned or frozen (BOTH seeds this time)

So RED(3), GREEN, RED(2) on the same AI. The entry above stands and is
stronger than when it was written.

Two checks recur in 2 of the 3 runs and are probably NOT noise -- they sit
near their boundary rather than flipping across it:
  - home ground is not discounted (0.57 then 0.59, both runs that read it)
  - commander never penned or frozen (1 seed, then 2 seeds)
Those two are the ones to chase. The plant-copy livelock appeared once at
x97, which is a large enough count in the one game it appeared in to be
worth a look on its own.

Note for the mechanism: the gate keys on the repo HEAD sha, so a docs-only
commit invalidates a green record and forces a re-run. Keying on a hash of
the DEPLOYED set (ai/ + cpp/) instead would make a gate record survive the
commit that writes up its own result.

The shared deploy apexearth asked for is therefore NOT done: it needs
`--allow-red`, which is his call. Re-running the gate until it comes up
green would be result-shopping, and given the three runs above it would
have meant nothing.

### 95% of every extractor proposal is refused at a gate, and the commander's leash is 40% of it

2026-09-23, 32-game arm. `want_mex.as` already counts every mex refusal at its
own gate and prints them as `apex: mexdiag`. Nobody had summed them. Over
93,578 proposals:

  comFar     37652  40.2%     <- the commander's leash
  noOpen     30122  32.2%
  deathWalk  13917  14.9%
  claimed     7285   7.8%
  priced      4602   4.9%

  minute  held    noOpen  claimed  deathWalk   comFar   priced
   0-3     2.0      2.5%     0.1%       0.8%    89.1%     7.4%
   4-7     4.3     15.4%     7.2%      22.5%    49.1%     5.8%
   8-11    3.6     28.7%     7.1%      26.9%    31.5%     5.8%
  12-15    3.4     36.8%     1.6%      23.9%    33.9%     3.9%

The commander's leash refuses 89% of every extractor proposal in minutes 0-3.
That is the window the game is decided in: BARb reaches 7.9 extractors by
minute 4 and 10.8 by minute 8, while we go 6.2 -> 5.7, and by minute 20 we
hold 4.8 to their 11.6. Our income flatlines at 126 against their 331.

Why this gate and not the others: it is the biggest, it bites earliest, and
it is the only one of the five whose stated purpose is measurably NOT being
served. The leash exists to keep the commander alive. He dies 1.94 times a
game to BARb's 0.38, a median 703 elmo from home, with 58% of those deaths
inside what this very leash calls home (tools/compos.py, tools/comguard.py).
It is charging the whole early economy for a protection it does not deliver.

The code one line above it already states the right principle -- "the trip
risk is a PRICE, not a veto, and ranks the spot below a safer one of equal
yield" -- and then applies ComFar as a veto. `apex_com_mex_price` makes it a
price. Default 0 keeps the veto exactly.

NOT yet established: that pricing it wins games. A 16-game pair moved income
at minute 12 from 73 to 91 and extractors from 5.1 to 5.9, but this session
has twice watched an effect that size evaporate at n=32.

### The energy ladder never climbs: wind wins half of every energy election at every income

2026-09-23, same 32-game arm, `ecoladder.py --kind energy`. Bucketed by eco
power, the def that WON each energy election:

   20-30 m/s   armwin 57%  armadvsol 26%  armsolar 15%  armfus 0%
   80-90       armwin 50%  armadvsol 33%  armfus 6%
  100-110      armwin 52%  armadvsol 35%  armfus 7%
  130-140      armwin 51%  armadvsol 37%  armafus 5%  armfus 4%
  170-180      armwin 55%  armadvsol 23%  armfus 8%

Wind takes about half of every energy election from 20 m/s all the way to 180.
At 170 m/s of eco power we are still mostly building wind.

What that costs, per side, us against BARb:

  min    our fusions   theirs   our small gens   theirs
   12       0.4         1.9         36.6          29.0
   16       1.1         3.2         39.4          21.3
   20       2.0         5.0         36.5          14.9

They tear the small generators DOWN as they climb -- 28.7 at minute 8 to 14.9
at minute 20 -- while their big reactors go 0.8 to 5.0. We add small ones (29
to 36.5) and reach 2 reactors. A solar is 20 energy and a fusion is 1000.

This is the second half of why income flatlines: ours goes 93 -> 121 -> 126
across minutes 16-24 while theirs compounds 160 -> 265 -> 331. It is also what
apexearth asked for directly on 2026-09-22: "we also do need to get started on
making fusions. Pretty soon."

NOT yet diagnosed: WHY wind wins. want_energy.as has long history here
(a reactor is priced on delta-ETA and a cheap fast rung beats a slow big one
on that measure), and three reactor tunables -- TUNE_FUSION_MIN_ENERGY,
TUNE_T2_ENERGY, TUNE_T2_ENERGY_REACTOR -- look live and are not. Each HAS a
GetTunable call, inside an accessor in policy.as (T2Energy(),
T2EnergyReactor(), FusionMinEnergy()) that NOTHING CALLS -- grep finds the
call and you conclude it is wired. It sets nothing today. Whoever
takes this should start there rather than adding a fourth.

#### The fusion lever is already built, already authorised, and still off

`TUNE_T2_FUSION_PULL` (decide.as:1722) takes a fusion from the ranked list
instead of drawing it, while the T2 switch is on and no advanced generator
stands. Its own comment records the failure it was written for: the switch
frees metal for fusions and "the freed metal went to the draw, which bought
wind 48 times to the fusion's 3 while the switch read NOFUS from frame 18."
That is the same thing `ecoladder.py` now measures across a whole arm.

It is default 0. USER-FEEDBACK.md's FUSIONS START SOON entry records that it
was left off waiting for apexearth's ruling on overriding the price, and that
he gave it on 2026-09-22: "soon". So it is authorised and untested.

Measured before testing it, so a null is not misread: the T2 switch fires in
32/32 control games, but only 12/32 ever reach the state where the pull would
trigger (` fus ` in the t2switch line). A 32-game arm is therefore n=12
treated, and anything smaller cannot resolve it at all.

#### The real baseline in his regime is 0 of 32, not 12.5%

2026-09-23. A 45-minute, 32-game arm at stock settings on Glacier Pass 1.2,
2v2, Armada v Armada, +100% both, 0.2 boxes, left/right, vs BARb stable hard:
32 of 32 decided, ZERO wins, no timeouts.

The ~12.5% that this session and earlier notes kept quoting came from arms
with different settings. Against the regime he actually watches and actually
asked about, the AI wins nothing. Any future claim of improvement should be
measured against 0/32, and note that a floor of zero gives a win-rate test
almost no power -- mechanism metrics (income, extractors held, commander
deaths, games lost inside N minutes) are what can resolve a change at these
sample sizes.

### VERIFIED: ArmyTarget() returns literally zero for ~80% of the game, and the commit that says it was fixed never touched the file

2026-09-23, found by an unbiased code survey and then verified directly.

  army.as:1499    if (T2SwitchOn())
                          return 0.f;

Not reduced, not deferred. Zero. It feeds production.as's `armyGap`, which is
the factory's entire army demand, plus want_nano, want_plant, want_tech and
want_mex's army-opportunity charge.

The valve that is supposed to restore it, EcoDangerNear (army.as:1156),
compares `GetEnemyCostAt(...)` -- a unit COUNT (S28) -- against
TUNE_ECO_DANGER_M, which is declared in METAL and set to 250 ("two T1
raiders' worth"). It needs ~250 visible enemy units within 2500 elmos held
for 30 s. It never arms.

How long the zero holds, one 45-minute game of the control arm: the switch
reads `on` at FRAME 18 and DONE at frame 42,593 -- minute 0.01 to minute
23.7 of a 29.4-minute game.

THE SILENT FAILURE. ISSUES.md's own ARMY SHARE entry says "Fixed together
2026-09-22: switch target = our share of their shown army". Commit 02f6a6c7,
which carries that message, has a two-file diff: ISSUES.md and
military/massing.as. army.as IS NOT IN IT. Only HoldNeedM() got the
group-metal read; `return 0.f` was never edited, and the measured result
quoted in that commit came from a build carrying half the described change.

WHAT IS *NOT* ESTABLISHED, and the survey overstated this. The impact claim
leans on "army 10% of spend vs BARb's 23-32%", which is from Comet 1v1 on
2026-09-06 -- a different map, date and codebase. On the arms measured TODAY
in his regime, our army spend share is ~48% against BARb's ~47%: comparable.
So the dead target is NOT currently collapsing army spend. What buys our army
instead is CoverNeedM() and RichArmyGapM() -- cover reactions and a
spare-metal EMA. Our army buying is REACTIVE, not TARGETED: it never asks
"how much army do they have", only "what is left over". With half their
economy, leftovers are half as big, which is consistent with a similar share
and half the absolute army.

So: the defect is real and verified, its size is unknown, and the honest test
is whether a live target changes absolute army and wins -- not whether it
changes the share.

### CORRECTION: the 0/32 baseline was my own broken win counter, and it inverts the com_mex_price result

2026-09-23, found by an unbiased red-team of this session's own analysis.

`result.json` pretty-prints the winner field:

    "winner_specs": [
      "BARb-stable-hard"
    ],

I counted wins with `grep -o '"winner_specs":[^]]*]'`. grep works line by
line, the closing bracket is on the NEXT line, so the pattern never matched
anything and `grep -q Apex` was false for every game in every arm. It read
ZERO WINS regardless of what happened. Parsed as JSON (`tools/wins.py`):

  45-min, apex_com_mex_price=0    (control)    32 decided, 4 wins  (12.5%)
  45-min, apex_com_mex_price=0.35 (treatment)  26 decided, 0 wins  ( 0.0%)
  fp-conf32 (earlier arm)                      32 decided, 2 wins  ( 6.2%)

TWO THINGS I PUBLISHED ARE WRONG AND ARE NOW WRONG IN THIS FILE ABOVE:

1. "The real baseline in his regime is 0 of 32, not 12.5%." Backwards. The
   baseline IS about 12.5% (4/32 here, 2/32 on fp-conf32). The 12.5% figure I
   spent the session trying to correct was right all along.

2. "apex_com_mex_price does not convert to wins, and the win test had no
   power." The test was not powerless and it did not come back neutral. It
   came back 4/32 -> 0/26, which points AGAINST the change. Fisher two-sided
   p = 0.120, so it does not resolve -- but the point estimate is a loss of
   every win, not a wash, and I recommended turning it on off the back of a
   number that did not exist.

The mechanism results (income +38% at minute 12, commander deaths 37->20,
games lost inside 20 min 12/32 -> 4/32 at p=0.041) were computed by different
code and are not affected by this bug. So the change does what it says to the
economy and may still cost games. It stays default 0, and the recommendation
to enable it is WITHDRAWN pending an arm that resolves wins.

Lesson worth more than the result: never count a JSON field with grep. Every
win count in this repo's session notes that was taken that way should be
re-read with tools/wins.py.

### It is a HOLDING failure, not an acquisition failure, and that retires the direction I spent today on

2026-09-23, from two independent unbiased reviews, cross-checked against my
own numbers.

Glacier Pass 1.2 has **19** metal spots, not the 34 CLAUDE.md claimed (the
AI's own `mexdiag mapSpots=19`, 53 samples in one game; 34 is Frozen Ford).
CLAUDE.md is corrected.

On a 19-spot map the two sides hold 6.4 + 8.1 = 14.5 of 19 by minute 4 and
17.8 of 19 by minute 12. **After about minute 8 there is no free ground.**
Every further extractor has to be taken off them.

And we already pay for the whole map: we BUILD ~18.5 extractors a game and
STAND 5. They build ~30.8 and stand 11. My own mexkill numbers agree -- 11.5
lost by minute 20 against 4.8 standing.

That retires the whole class of fix I worked on today. `apex_com_mex_price`
makes the commander PROPOSE more spots. There are no more spots, and the
election-level log says so: `noOpen` is the dominant refusal once the map
fills. It is consistent with the win result going the wrong way (4/32 -> 0/26).

Where our things actually are, measured per side against the home->enemy axis
(3,480 elmo; f=1 is their spawn):

  min 12   extractors mean r / fwd f      defences mean r / fwd f
  us          385 / 0.038                    569 / 0.010
  them       1055 / 0.229                   1102 / 0.235

We build a symmetric ~500-elmo bubble around the spawn and never leave it.
Our defences at f=0.010 are not "at home", they are DIRECTIONLESS -- a ring
with no bias toward the enemy at all. Theirs sit ~765 elmo up the attack
axis. Territory goes as r-squared, so their disc is ~4.4x ours, which IS the
10-vs-5 extractor split. The count is the territory ratio, not an
independent fact. The deepest spot we have ever held reads depth 0.04.

Two more things that are not in any note and change the picture:

- Our army is 53% of everything we build and trades at 0.49; theirs is 43%
  and trades at 1.63. mKillStatic is DEAD LEVEL (20,098 vs 19,995) while
  mKillMobile is 0.43. We kill buildings as well as they do and lose every
  unit fight.
- So the stale ARMY SHARE entry at the top of this file ("we put ~10% of
  metal into army, BARb 23-32%") is wrong for this regime by a mile and
  points the wrong way: acting on it enlarges the thing already killing us.
  It is from Comet 1v1, 2026-09-06. RE-SCOPED, do not act on it here.

### THE BALANCE ONLY WORKS ONE WAY: army is not on the scale

2026-09-23, apexearth's steer ("our target would be like 0.35 and we would
only be at 0.12; I don't think we ever managed to balance that out"). He is
right, and the reason is structural, not a tuning miss.

`tools/budgetgap.py` over the 32-game 45-minute control arm, 1,640 samples:

  cat    held   target    gap     mult   railed at the 2.0 clamp
  army   0.320  0.202   +0.118    0.82      14%
  def    0.142  0.288   -0.147    1.75      59%
  aa     0.003  0.059   -0.057    1.98      97%
  eco    0.238  0.302   -0.065    1.39      26%
  bp     0.259  0.148   +0.110    0.79       5%

Defence sits at half its target for the whole game (0.06 -> 0.18 while the
target climbs 0.26 -> 0.31) and never converges. Its corrector is pinned at
the clamp 59% of the time; AA's 97%.

WHY IT CANNOT CONVERGE. `BudgetMult = target/have`, clamped [0.35, 2.0], and
it is applied in ONE place: decide.as:1235, on the ranked list of what
CONSTRUCTORS build. Army does not come from there. Army comes out of
factories through production.as, and production.as contains NO reference to
BudgetMult, ShareOf or TargetShare -- verified by grep. Its army demand is

    RichArmyGapM() = gMSpareEma * 180s

spare metal times three minutes. So every metal the steered categories fail
to absorb becomes army automatically, whatever the army row says. The
corrector can amplify a starved category to at most 2x; it has no way at all
to reduce the overfed one, because the overfed one is not on the scale.

That is also why raising defence has failed repeatedly: defence's ticket is
already at its rail, and the metal it does not win is not returned to the
pool, it is converted into army by a floor that no target bounds.

CHANGE, default OFF: `apex_army_budget_damp` multiplies the spare-metal army
floor by the ARMY row's own budget multiplier. At the measured shares that is
0.202/0.320 = 0.63, so the floor asks for 37% less and the metal is available
to the categories the corrector is already straining to fill. Untested.

### Two instruments that resolve changes where the win rate cannot

2026-09-23. At a 12.5% base rate a 32-game arm cannot resolve a win-rate
change, but both of these are metal quantities summed over every fight of
every game, and both are stable across arms.

`tools/trade.py` -- metal killed against metal lost, 32-game arms:

                 us trade   them trade   static killed us/them
  control          0.49       1.63         643,150 / 639,841
  damp arm         0.50       1.82         540,617 / 306,478

Our trade is 0.49-0.50 in every arm measured. We kill STRUCTURES as well as
they do -- 643k against 640k, dead level -- and lose every unit fight by a
factor of 3.3. That gap is larger than any economic gap in this file.

`tools/mexguard.py` -- when one of our extractors died forward (>800 elmo
from home, moho-upgrade phantoms excluded):

  had a gun within 600 elmo:  36 (27%)
  had NO gun:                 95 (73%)
  median distance with a gun: 1505;  with none: 1968

So his mex-guard ruling (2026-09-17, guns on the mexes outside the base, more
the further out) is implemented -- MexGunsWanted scales one light tower at
home to four at the doorstep -- and does not reach the forward spots: three
in four die unguarded, and the unguarded ones are the further out. The floor
is computed over STANDING mex rows, so the gun is only demanded once the mex
exists, which is after the thing that kills it has arrived.

### ABOUT HALF THE FIGHTING GAP IS OUR OWN ASSIGNMENT LAYER

2026-09-23. `apex_stock_army=1` hands every armed ground unit to BARb's own
task pools and switches off our withdraw orders. It is the A/B the tunable
was declared for and it had never been run. 32 games an arm, 45 min, his
regime, read on `tools/trade.py`:

                        us trade   them trade   ratio   our mobile kills
  our layer (control)     0.49       1.63       0.30      1,251,167
  BARb's layer            0.66       1.12       0.59      2,309,788

Our driving costs us 35% of our own trade AND hands BARb 0.5 of theirs: the
relative gap nearly doubles when we stop steering. Median game length is
unchanged (24.9 -> 26.0 min), so this is not a longer-game artifact -- our
kills nearly double at the same clock.

Wins went 4/32 -> 1/30, Fisher p = 0.355: UNRESOLVED. This does not say ship
stock army, and stock army is not a fix -- it is a measurement. What it
establishes is where the 3.3x fighting gap lives: roughly half of it is in
how we DRIVE the army, not in what we BUILD. Composition work should not be
the first thing anyone tries.

The tunable switches off two things at once -- our task pools and our
withdraw orders -- so the next split is which of the two owns the gain.
TUNE_RETREAT_COST_SECS is already recorded as harmful (K/D 0.33 -> 0.11) and
his standing rule is that "retreat is never the answer, look at the action
before it", so withdraw is the first suspect and the cheaper half to test.

### WE ABANDON 37% OF EVERY BUILD WE START, AND ALMOST 100% OF THE BIG ONES

2026-09-23, `tools/aborts.py` over the 32-game 45-minute control arm. The AI
already logs every ended builder task as done= or abort= (`apex: task-gone`);
nobody had summed it.

  def            done   abort   abort share
  armwin         1404      55      4%
  armmakr        1553     328     17%
  armnanotc      1228     386     24%
  armmoho          68      74     52%
  armrad          105     207     66%
  armmex          392     936     70%
  armmmkr          83     389     82%
  armalab           4      64     94%
  armlab            2      48     96%
  armaap            1      23     96%
  armgeo            5     282     98%
  armap             2     101     98%
  armvp             0      59    100%
  armageo           0      71    100%

  ALL DEFS       5295    3144     37%      (165.5 finished, 98.2 abandoned/game)

THE SHAPE IS THE FINDING: what is cheap and fast completes, what is expensive
and slow is abandoned. Wind aborts 4% and geo 98%. We are not choosing wind
over fusion because wind is priced better -- we CHOOSE the big build, walk to
it, and drop it, over and over, and wind is simply the only rung short enough
to survive our own re-election.

This is one mechanism under at least three things this file diagnoses
separately:
  - the energy ladder that "never climbs" (34 windmills, 2 reactors)
  - the extractor shortfall (70% of mex tasks abandoned; 12.3 finished a game)
  - the missing advanced converters (82%), where BARb runs 10.3 to our 3.9
  - every factory: armlab 96%, armvp 100%, armap 98%, armalab 94%

It is also exactly what apexearth reported from watching, twice: "he walks
all over the damn place... it's almost like he can't make up his mind", and
"we're like a crazy cancer virus that spreads all around the map but we lack
any good organization to do this craziness efficiently."

RELATED, already in this file and now explained: 23% of constructor job
changes land within 5 s of the last one; 55% of defence elections are
abandoned; S14 records that AiMakeTask is a RE-ELECTION, so every tick can
drop work in progress.

NOT YET ESTABLISHED: why. `abort=N(nopos 0)` says these are not
position failures. The candidates are re-election dropping a live task, the
site becoming invalid, or the hand being peeled. The fix direction that
follows from this repo's own paradigm is that a task with sunk progress
should carry that progress as VALUE in the next election -- a half-built
fusion is worth more than an unstarted one, and today the auction cannot see
the difference.

#### ...and the cause: the walk has to survive a re-election every tick, and 54-65% of them change the job

Same arm, `tools/abortwhy.py` (the AI's own `apex: abort` line) and
`tools/onehand.py --all`:

  67% of aborts had a WORKER STILL ON THE TASK -- these are not unattended
  tasks being tidied away. The task died under an active builder.

  median walk STILL REMAINING when the task died:
      armmex 1790    armgeo 2400    armalab 605    armrad 815
      armmoho 159    armhlt 158     armguard 147

  constructor elections that CHANGED the job: 54% (t000), 65% (t002)
  changed TO: assist, nano, energy, convert  -- the cheap, near things

Put together: we elect a site 1,790-2,400 elmo away, the hand sets off, and
more than half of every subsequent election moves it somewhere else, so it
never arrives. The builds that complete are the ones already underfoot
(median 147-159 elmo remaining). Wind survives at 4% because it finishes
inside one election window; a geo at 2,400 elmo never does.

That is the whole of it: THE PROBABILITY A BUILD COMPLETES DECAYS WITH ITS
WALK, because every tick is a fresh auction and sunk progress is worth
nothing in it. S14 already records that AiMakeTask is a re-election; what was
missing was that the re-election rate is 54-65% and the walk is long.

It explains, with one mechanism, every separate "we never build X" in this
file: fusions and geo (98-100% abort), every factory (94-100%), advanced
converters (82%), forward extractors (70%) -- and it explains why four
successive PRICING fixes each moved their own metric and left the result
alone. The price was never the problem. We price it correctly, set off, and
stop.

FIX DIRECTION, in this repo's own paradigm rather than a cap: a task already
walked toward should carry what has been spent on it as VALUE at the next
election. The auction today cannot tell a build with 1,700 elmo of walk
already paid from an identical one not yet started, so it keeps picking the
nearer thing forever. Note there is already a keep-job notion in the peel
path (S37); this is the same idea applied to the walk.

#### THE KEEP-JOB MECHANISM HAS NEVER FIRED. keeps=0 in 32 games, 7,370 incumbencies discarded

2026-09-23. decide.as:1830-1880 holds a hand on the job it is already walking
to -- written for exactly the failure measured above, and its comment says so:
"constructors go on long journeys, get to the other side and turn around...
The incumbent's walk is partly paid, so its value only rises en route."

Summed over the 32-game arm from the AI's own election log:

    keeps = 0        offCrew (incumbent forgotten) = 7,370      -> 100%

It has never fired. Not once in 32 games. Every single re-election takes the
`!onCrew` branch, nulls gIncTask and forgets the incumbent.

WHY, and it is in the mechanism's own comment three lines up: "C++ hides the
unit's assignment before every re-election, so the hold in maketask.as never
sees it". The engine detaches the unit from the task BEFORE MakeTask runs, so
`inc.GetUnits()` cannot contain this unit and `onCrew` is structurally false
every time. The guard was added to stop handing a PEELED hand back to the job
it was peeled from (S37) -- correct intent -- but it cannot distinguish
"peeled away" from "detached by the engine a microsecond ago, as happens on
every election", so it fires on both and the incumbency never survives.

That closes the chain end to end:

  keep-job dead  ->  every tick is a blank auction  ->  54-65% of elections
  change the job  ->  a build 1,790-2,400 elmo away never survives the walk
  ->  37% of all builds abandoned, 98-100% of the big/distant ones
  ->  no fusions, no factories, no forward extractors, no advanced converters
  ->  half the economy BARb has, and an army bought as cover reaction

It is this repo's named bug class -- the silent no-op -- sitting under the
single biggest behavioural complaint apexearth has made about this AI.

THE FIX has to separate the two removals. A peel is ours and recorded
(PeelSurplus + RemoveUnit); the pre-election detach is the engine's and
happens to every hand every time. Testing `onCrew` conflates them. Something
that marks a hand at the moment WE peel it, and tests that instead, restores
the mechanism without re-attaching peeled hands.

## The budget cannot balance while builds are abandoned (2026-09-23)

Defence holds 0.13 of spend against a 0.29 target with `BudgetMult` railed at
2.0 for 61% of samples. The corrector is not the constraint: defence already
wins 85 of 548 constructor elections (15.5%) and still books only 10.9% of
spend, because what it wins is abandoned before it is paid for.

Abort share tracks walk distance and build time, not category:

| def | metal | abort |
|---|---|---|
| armwin | 40 | 6% |
| armsolar | 155 | 24% |
| armmex | 26, forward | 70% |
| armgeo | 560 | 99% |
| armanni | 3500 | 69% |

Anything cheap and at home completes; anything far or slow does not. 36% of
all builds are abandoned. Freeing metal from army does not reach defence --
`apex_army_rich_balance=1` moved army 0.308 -> 0.289 and defence 0.127 ->
0.109, with the difference going to economy. Fix the aborts first.

`apex_keep_job_peel` + `apex_keep_walk_paid` reach only 434 keeps against
5,935 off-crew events (7%): the peel marker catches peels, but most off-crew
cases are the engine's pre-election detach, which we still cannot distinguish.

## Most of the army metal we lose dies running away (2026-09-23)

`deaths.py` on a Glacier Pass 2v2, our side: 59% of all metal lost had
`retreat` as its last action (500 units, avg forward depth 0.35); on team 0
alone it is 81% at depth 0.49. Exactly one unit died with `fight:attack` as
its last action. Units are not dying in fights they should not have taken --
they are dying on the walk home from fights they did take.

Our `behaviour.json` sets 78 retreat thresholds, 40 of them at 0.6 and 24 at
0.8. Stock BARb sets 26, and its distribution reaches down to 0.1 and 0.
A unit pulled out at 0.8 hp runs the whole way home being shot while dealing
nothing back, which is also the shape of the trade gap: we trade at 0.49
against BARb's 1.63.

`apex_retreat_scale` (posture.as, default 1 = the config value) scales every
def's threshold for an A/B. NOT YET MEASURED.

This is the likeliest single cause of the army row reading over target: the
budget counts SPEND, so army killed on the retreat is charged to army again
every time it is rebuilt -- we lose 1.22x the army we build, BARb loses 0.52x.

## Our benchmark regime is not his game (2026-09-23)

apexearth plays with the scavenger pack on: his start scripts carry
`experimentalextraunits=1` and `scavunitsforplayers=1`. Those put the `*t3`
units in the player pool -- `armafust3` (Epic Fusion: 90,000 metal, 2,500,000
buildtime), `armannit3`, `armmmkrt3`, `armapt3`.

Every arm run before this date omitted both, so the unit pool differed from
his. A behaviour he watched could not appear in our games at all: his Epic
Fusion complaint was invisible to a 32-game arm, and the fix for it measured
flat because the unit was never a candidate.

Pass both modoptions for anything meant to reflect his regime, and grep the
arm for `*t3` defs before trusting a null result.

## The scavenger pack costs us a third of the economy (2026-09-23)

Eco board, Comet Catcher Remake 1.8, +50%, vs NullAI, eco-only, 6 seeds an
arm. The only difference is `experimentalextraunits=1 scavunitsforplayers=1`,
which apexearth plays with:

  minute      8      10      12      14      16
  pack off  117     250     436     501     693
  pack on    79     192     298     361     431
  cost     -32%    -23%    -32%    -28%    -38%

The `*t3` units are better per metal AND per build time than their T2
equivalents, so nothing in the pricing refuses them -- and they are enormous
lumps (armafust3: 90,000 metal, 2,500,000 buildtime, nothing delivered until
it finishes). With the pack on, the AI reaches for them and the economy stops
compounding. This is apexearth's watched complaint of this date, reproduced as
a number.

It also means every arm run WITHOUT those two modoptions overstates our
economy against his real games by about a third, and any change measured in
one regime must be re-measured in the other: apex_bp_vs_lathe gave +37% at
minute 16 with the pack on and is INERT with it off.

## We keep paying for capacity we cannot use (2026-09-23)

Three watched complaints, one defect family. In every case the AI prices a
unit's NAMEPLATE and nothing bounds it by what the economy can actually feed:

  Epic Fusion (armafust3)     90,000 m, 2,500,000 buildtime. Gain was 200x a
      fusion's for 30x the energy, because the growth premium is multiplied by
      the generator's own share of the economy and saturates at the full 9x
      for anything bigger than the whole economy.
  Epic Energy Converter       9,000 m, eats 6,000 e/s. Bought at 2,000 e/s of
      (armmmkrt3)             income and 80 m/s of metal. When the energy bank
      is pinned the chew is set to the def's full capacity, and nothing caps
      it by energy income.
  Drone carrier               1,250 m each, sixteen of them. Its drones are
      (armdronecarryland)     its weapons, so it reads as unarmed, carries
      radar, and fills a "one radar per squad" slot a 60-metal Radar Tower
      covers.

The shape is always the same: a quantity the def declares is taken as the
quantity we will realize. The scavenger pack makes it acute because its t3
units declare enormous numbers -- and it costs a third of our economy.

apex_energy_growth_flat, apex_conv_feed_cap and apex_support_per_metal each
close one of the three. None is measured in a real game yet.
