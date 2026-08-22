# What this AI does that stock BARb does not

One AI, built on BARb (CircuitAI). Everything here is a deliberate difference
from `BARb/stable`; anything not listed behaves as stock.

| variant | shortName | intent | best measured result |
|---|---|---|---|
| **apex** | `Apex` | team T2 rush in team games; stock behaviour with no allies | **1v1 vs `BARb:stable:hard`: 56-57 over 113 decided games (49.6%)**, 2026-08-10 |

`apexdef` ("hold ground, out-eco, finish with T3", 4-3 over 10 clean games) was
merged into apex and no longer exists as a separate variant.

`ai/ctl` (`ApexCtl`) and `ai/stk` (`ApexStk`) are measurement fixtures, not AIs
being developed: a frozen control for self-play A/B, and stock config + stock
script on the apex DLL to isolate what the DLL itself changes.

The 8v8 numbers that used to sit here (16-0 vs medium, 8-0 vs hard) were taken
on the `hard_aggressive` config base, which is no longer what apex ships. They
are not withdrawn, they are simply no longer about this build.


## 2026-08-21: ALTAIR chapter 4 -- campaign conclusions after 13 hypotheses

- 2v2 shares the signature exactly (0-12, trades 0.36): the weakness is the
  map's combat regime, not scale. Solving 1v1 solves the ladder.
- H13 arty retest (justified by new evidence: the wall named, hot-lane +
  aggregation infrastructure in place): NULL AGAIN -- the 0.06/0.08 weights
  field ONE Wolverine (170 metal); a counter-siege is a behavior, not a
  ratio. Weights reverted; do not re-propose as a ratio nudge.
CONCLUSIONS. Kept from the campaign: fence DEPTH, HOT-LANE fencing, ally
AGGREGATION (all mechanism-true generally). Confirmed load-bearing by
removal: the T2 safety veto, the coverage caution. The two REQUIRED BUILDS
the evidence names: (1) TERRAIN-AWARE STANDOFF -- overlays-off was the best
trade arm (0.45 vs 0.26-0.42), our flat-geometry standoff holds ground
where the target is unhittable on ramp/ridge maps; (2) COUNTER-SIEGE -- the
enemy creep wall advances monotonically and is never treated as a target
class (needs massed arty behind our line, or committed wall-breaking).
Neither is a knob. The watched-game request to apexearth stands.

## 2026-08-21: ALTAIR chapter 3 -- the geometry named, the micro implicated, the wall stands

SPATIAL RECONSTRUCTION (BARAI_POS, 3 losses, coordinates in the agent
report): stock porc-creeps ONE lane at 150-250 elmos/min behind an
LLT->Punisher/HLT/Maw wall (24 towers, fusions behind), reaching our base
by ~26m; our deaths scatter across ALL THREE crossings; our 3-9 towers
cluster in the NORTH CORNER (base-band axis artifact); 75% of our mobile
metal died at home. The one near-draw had forward, spread towers.
- H11 HOT-LANE FENCING (kept, brain.as): stretch selection ranks enemy
  presence above least-covered -- towers mass on the pressed lane.
  Geometry moved decisively (home-death share 75% -> 23%) -- W/L 0-11.
  Containment broken, fights lost forward instead.
- H12 combat overlays OFF (los_standoff, range_mod, fragility, withdraw):
  kill/loss 0.45, BEST of any Altair arm (from 0.26-0.42) -- our micro
  costs real trades on this terrain map -- but still under half, 2-8.
INVARIANT after 12 hypotheses: the trade deficit vs stock's creep-wall
composition survives every posture, budget, tech timing, geometry and
micro configuration. The remaining axis is COMPOSITION vs the wall
(their corgol+porc; our thud-mix has no answer that outranges it) and
TERRAIN-AWARE standoff (stand only where the target is hittable) -- both
are builds, not knobs. 2v2 baseline running (the team machinery may not
share the 1v1 weakness). NEXT per house rule: a watched game -- twelve
remote hypotheses is the point where his eyes beat the thirteenth.

## 2026-08-21: ALTAIR CAMPAIGN chapter 2 -- knob-space exhausted, the failure is structural

- H6 ally aggregation (C++, SquadTask squadOverwhelms + AttackTask
  nearMargin): co-located ATTACK/DEFEND squads count as their joint force
  (apex_ally_aggregate, default on). Trades climbed 0.26->0.38->0.42 across
  the stack. KEPT (mechanism-true everywhere, not just Altair).
- H7 tech-race posture (army share 1): REFUTED and revealing -- fusion metal
  ZERO; the fusion pipeline is income-gated, not budget-driven, so freed
  metal had nowhere to go.
- H8 scarcity thresholds (fusion bar 12): STILL blocked -- the cascade roots
  at the T2 ENERGY bar (400-800 e/s), unreachable at Altair's ~200-300;
  measured income 14-17 m/s at minute 15 with `asked=0` and energy WASTING.
- H9 energy gate off (+metal 10, fusion 10): the one strong arm -- 4 wins,
  kill/loss 0.61, fusions exist. REPLICATE: 1-12, 0.26, fusions 0 -- the win
  signal was noise; pooled H9-config 5-19/32.
- H10 tech-safety veto off: REFUTED HARD (2-12, 0.28) -- the LosingGround/
  BaseContested veto on the T2 commit is load-bearing; teching through
  pressure collapses. apex_t2_safety stays default 1.
Ten hypotheses: every mechanism metric improved (defence 0.38->0.62, trades
0.26->0.42, depth exists, fusions possible), W/L never left the noise band.
Conclusion: the Altair failure is STRUCTURAL/SPATIAL -- a geometry
reconstruction from BARAI_POS snapshots is running (do we split lanes while
stock masses one; does stock porc-creep the choke unanswered; are we
contained). The threat-blind middle-lane pathing remains the standing
unaddressed suspect.

## 2026-08-21: THE ALTAIR CAMPAIGN (goal: 60%+), and 248 dead modoption knobs found

Goal-driven hypothesis chain on the one map every fix bounced off (15%
pooled, n=48). Map-paired discriminants (Altair vs Comet, same arms):
conT1 6 vs 16.5, defence spend 0.35x stock, kill/loss 0.31 vs 0.79,
commander idle 40%, tech 19m -- a constructor/defence famine loop.
- H1 allowance gate 3x: REFUTED, 0-10, spend frozen 0.38 -- gate not binding.
- H2 budget share 3x: REFUTED, 0-12, spend frozen again -- because...
- H3 the model cannot buy DEPTH: found in source -- the fence want's value
  is `uncovered * ...`, zero at full coverage, so both knobs were
  structurally inert. Fix: coverage saturation converts the want to
  THICKENING at the least-covered stretch (picker already prefers
  chokepoints) valued by the UNSPENT defence share (apex_fence_depth 0.5)
  -- the budget knob finally governs depth. First arm: first 2 Altair wins
  of the campaign, +1000 defence metal, but orders still ~4/game -- capped
  by the con famine itself (6 cons cannot issue more builds).
- H5 (running): break the famine circle at the constructor floor
  (apex_t1_core_min=10 + share 6 + depth).

INFRASTRUCTURE: H5's first arm was INVALID -- apex_t1_core_min was not in
dev_tunables.lua's NAMES list, the third silent-dead-modoption incident.
Swept the whole class: 248 OF 462 GetTunable names were unpublished (every
A/B that used one tested nothing). The gadget now carries all 462, synced
mechanically from the actual GetTunable calls in script+cpp. Any past arm
whose modoption is on the missing list is suspect.

## 2026-08-21: watched-game batch -- trees, the abandoned mex, the frozen commander

Three live reports, one session:
- TREES AT FULL ENERGY, twice reported: first the area-sweep fix (a con sent
  for one metal rock vacuumed every tree in the 320-elmo circle; the circle
  tightens to the wreck's footprint while energy is full), then his
  categorical rule when trees persisted: constructors are OUT of the
  energy-reclaim business entirely (C++ UpdateReclaimTasks; the 20%-bank
  gate still let them graze on every dip). Rezbots keep the full feature
  set. apex_con_energy_reclaim=1 restores the old gate.
- THE ABANDONED FRESH MEX: the guard rule existed but PassingMex outranked
  it -- the commander claimed the next mex and walked away from a radar
  contact standing over the one he just built. A THREATENED bare mex now
  jumps the queue: CommanderMexGuard's urgent pass (enemy visible within
  the 500-elmo ring) sits above the next-mex claim; peaceful ground keeps
  the old order.
- THE FROZEN COMMANDER: the ladder's panic-solar was unreachable mid-build
  (a commander in build range holds its task; a stalled builder parks on
  WAIT). The watchdog sampler now places the solar directly and the held
  nanoframe returns via the normal re-offer. FIRST CUT TOO TWITCHY: 8
  fires/game on opening blips, arm 6-11 (day's worst) -- now it never
  interrupts a FACTORY build and requires an 8s persistent stall.

Also: the comm-panic arm extended the soft-arm run to three since the
eco/spam/mexup batch (6-8, 6-9, 6-11) -- if the calmed batch stays soft,
the eco batch is the isolation target. The SENTINEL entry above carries
the observer whose thoughts now watch all of this.

## 2026-08-21: THE SENTINEL -- the brain checks its own concepts, out loud (his design)

apexearth: "Our brain needs to be smart enough to know all these concepts
and prioritize them... report in the log our brain thoughts and assertions
... the guard that helps us tweak/tune the proper behavior in all our 'leaf
logic'." Built as manager/brain/sentinel.as: every 45s, seven named checks
each log a verdict with the numbers that produced it --
  energy (income vs the 12:1 lead) / metal (GROWTH over a 3m window) /
  army (spend share vs budget target; standing vs enemy seen-peak) /
  spam (standing fodder vs the stream want) / labs (T1 count vs the
  one-until-reactor policy) / fusion (age of an unbuilt ask) /
  recall (losses at home or enemy influence ON home, with the lane forward)
plus one "thoughts ok:" line so silence is never ambiguous. OBSERVER-FIRST
by design: each concern line names the leaf logic responsible; enforcement
is earned per-check (the 2026-08-01 twelve-silent-rules lesson). Tunable
apex_brain_thoughts. First live sessions already earned their keep by
flagging TWO false positives in the sentinel itself, both fixed same hour:
the energy check judged the opening by an established-economy ratio, and
recall trusted BaseContested, which reads negative on a 90-second-old base
(now: real losses at home, or enemy influence physically on it).
grep "apex: thought" is now the AI's own self-assessment.

Also this block: the eco/spam/mexup batch replicate read 6-9-9, agreeing
with 6-8-10 -- the batch is draw-leaning on the BENCHMARK (thin economies
feel the moho slowdown; the fusion speed it buys is what hosted games
need). Isolation levers per member are in place if a measurement is wanted.

## 2026-08-21: home odds 1.2x, escort standoff, spam stream, eco scaling, mexup cap

HOME ODDS (his number): the defend home-fight allowance 4x -> 1.2x
(apex_defend_home_odds), and the odds test now reads live group influence
(the old threat-map read was ~0, so NOTHING was ever refused -- the
trickle-into-the-grinder was ungated, not mistuned). Refusals fall back to
the defence posts where pools merge and re-elect at 1.2x. Measured:
11W-6L-7D, 64.7% decided -- best arm of the project; Comet 7-0-1 and
Avalanche 3-0-5 UNDEFEATED.

ESCORT STANDOFF: weaponless radar/jammer keyed squad row 0 ("stand at your
own range" = stand ON the target), which is why sensors died first. They now
hold behind the squad's longest row on the enemy-away axis
(apex_escort_standoff, 240 past highestRange). Measured on top: 10W-5L-9D,
66.7% decided -- second consecutive best-ever.

SPAM STREAM (his spec, "attack the fog of war"): the no-squad fog-scout
routing existed (IsFodder + SpamPhase per-unit SCOUT tasks); production did
not -- the raider share fades with income so the quota stopped buying ticks
late. A RATIO entry (not a floor: the rez-conveyor lesson) keeps one
standing spam unit per apex_spam_per_income (5 m/s), post-T2, ground lines.
Verified live: armfav quota 4/4 -> 11/11 met.

ALWAYS-ECO actually always: was "at most one eco build at a time"; now one
parallel build per apex_always_eco_per (30 m/s) income, minimum one.

MEXUP CAP (his diagnosis): while the fusion is asked and no reactor stands,
mex upgrades hold at most HALF the adv-con fleet; the refused con falls to
the fusion request. Measured: fusion asked->standing median 2.0 MINUTES
(was ~11 in the documented starvation); cap fired 14 times in 24 games.
The combined arm read 6W-8L-10D (draws up -- watch this; replicate running).

## 2026-08-21: the T2 gate is one pair -- apex_t2_metal (30) + apex_t2_energy; strict post kept; ring -20%

T2 KNOBS: apex_rush_min_metal (14, "Tunable for A/B testing") renamed to
apex_t2_metal at 30 (his number) as the metal half of the T2 permission;
apex_t2_income RETIRED -- it was a second private 30 m/s gate on the same
decision inside the rear plant-siting rule, which now reads Policy::T2Metal()
(two knobs on one decision drift the first time one is tuned).
apex_t2_energy_from's doc now states it is NOT a permission knob (it starts
the pre-T2 energy-floor lane). A/B of the 14->30 bar: 7W-9L-8D, T2 median
18.7m (no later than before -- the 800 e/s energy bar binds first at
benchmark income), no-T2 games 6/24 (normal). Benchmark-neutral; the bar
will bind in richer hosted games, which is the stated intent.

STRICT POST (same arm series): election is post-relative ONLY -- the first
post cut kept proximity-to-squad as self-defense and a won fight advanced
the squad into the next election ("victorious march to death", watched).
Units still auto-fire in weapon range; the task never re-targets off its own
advanced ground. Very-deep defend deaths (>3000): 20% -> 5% across the
campaign; Comet went 5-0-3 then 5-1-2 in the last two arms. Ring shrunk 20%
on his call: base_rad [800,1400] -> [640,1120], defzone pad 500 -> 400.
Altair is 0-5/0-6 in EVERY arm today -- its failure is not these mechanisms.

## 2026-08-21: defence is a post, not a pursuit -- kept (apexearth's design ruling)

apexearth, on the measured 71%-outside-the-ring defend deaths: "How are we
defending outside of our defense zone? That seems like totally inappropriate
logic. if the enemy has fled or left, why are we still attacking them as if
it is defense?" Mechanism found in source: CDefendTask::FindTarget rewrote
`position` (the pool's post) to every elected target, so each chase re-based
the pool on newly-taken ground and the next election reached further --
candidates were accepted relative to the CREPT squad (atUs), never the
assigned post. Defence creep, one fled enemy at a time.

Fix (apex_defend_post, default 1): the anchor never follows the target;
candidates must be within weapon reach of the ASSIGNED post (or on our
defended ground); a unit actively shooting the squad is still fought
wherever it stands; with nothing electable the existing fallback walks the
pool back to a front post.

Validation, fourth arm of the day's series (same benchmark): defend deaths
outside the ring 79% -> 71% -> 65% across the campaign, very-deep share
20% -> 9%, median depth 0.65 -> 0.56 -- monotone improvement on every
mechanism metric. W/L 7-10 (noise band; Altair 0-6 again -- Altair's
problem is not this mechanism). The ~65% still outside is substantially
the LANE force: defend pools posted at front points, legitimately beyond
the base ring. Getting that to zero is the defend/lane split design
question, recorded as open. The muster clamp and solo-deep gate remain as
defense-in-depth beneath this.

## 2026-08-21: the single-unit attack stream -- two-iteration fix, kept (watched-game verdict pending)

apexearth, watching Geyser Plains: "suddenly we just started doing single
unit attacks into the enemy... well outside our base defense range." His
game's transitions table agreed exactly: 73% of combat metal died on DEFEND
at fwd ~0.7, disengaging at 9-15% hp, dead ~1s later.

Iteration 1 (muster clamp, DefendTask Merge/Start): rookies and fresh units
no longer walk solo to an anchor/leader beyond 1.25x the base-defence ring
-- they muster at the lane instead. Validated INSUFFICIENT alone: pooled
defend->retreat share flat (33->35%), median depth 0.65->0.60, W/L 6-10.
Root cause deeper: the manager spawns 1-unit defend pools that chase deep
targets as their own leader.

Iteration 2 (solo-deep gate, DefendTask FindTarget): a pool of ONE may not
elect a target beyond 1.25x the ring -- it fights whatever is on top of it
or inside the ring; travelling deep needs company. Narrow by design (solo
TRAVEL only), unlike the shelved broad engage gate that traded losses for
timeout draws. apex_defend_muster=0 / apex_defend_solo_deep=1 restore old
behavior.

Validation across the three same-day arms: median defend->retreat depth
0.65 -> 0.60 -> 0.57, deep (fwd>0.85) share 20% -> 17% -> 17%, W/L
6-10 -> 9-7 (best recent arm) with NO draw inflation. Direction consistent,
power modest (n=24/arm) -- the acceptance test is whether apexearth still
SEES single-unit streams in a watched game. STILL OPEN, next in queue: the
middle-lane bias (threat-blind approach paths take the direct lane into the
best-defended ground; flanks never considered).

## 2026-08-21: geothermals exist now -- three stacked defects, all fixed and verified

apexearth: "we don't build geo... maybe you can check?" The value ranking was
innocent; three independent defects stacked so geo could NEVER be built:
1. C++: ParseGeoSpots runs ONCE at AI birth and GetFeatures() is LOS-limited
   -- vents outside the start area never became spots, on any map, forever
   (geo-diag: spot=-1 for a whole 30m game on Death Valley with the income
   gate floored). Fix: RescanGeoSpots -- a 120s-throttled per-instance
   feature rescan appends newly-seen vents (lateGeoSpots) without mutating
   the shared CEnergyData other AI threads read; all geo paths (script query,
   EnqueueGeoAt, stock's own geo task) read through GeoSpotPos.
2. Script: EnergyReclaimable's "no successor to wait for" fallthrough classed
   geo reclaimable (cliff fallthrough 0), so EnergyValuePerMetal priced it -1
   ALWAYS -- vent found, value=-1, advsol picked (measured on Geyser Plains).
   Fix: geothermals never obsolete, stated explicitly at the predicate top.
3. Gate: apex_geo_min_income 300 -> 250 e/s (his call, same session), and
   the tunable's doc said metal/s while the code reads ENERGY income.
Verified end-to-end on Geyser Plains BAR v1.2.1 (his suggested vent-rich
map): three "home energy armgeo geo spot=N" picks at 16.5-18.5m as energy
income crossed 250-336, geo standing in the final tally, late diag reading
spot=-1 only once every vent was claimed. The geo-diag line (60s throttle)
stays for future attribution. Geo economics: 300 e/s for 560 metal = 0.54
e/s per metal, 2.5x the advanced solar -- the ranking now sees it.

## 2026-08-21: escorts ungated, the T1 cap enforced at the nanoframe, advsols behind the base

Three watched-game reports, each attributed and fixed the same day:

ESCORTS (radar+jammer): the want was wired twice -- a maketask rule that has
NEVER fired (sits below the driven-line early-return; left as dead code, note
here) and the real quota floor, whose blanket Outmassed gate suppressed it in
301/616 diag samples. apexearth overrode the 2026-08-19 jammer caution
outright: "We need 1 jammer and 1 radar on all the expensive squads... It
allows us to shoot at enemies before they can see us." Gate removed for BOTH
defs. Measured: in every benchmark game where a squad cleared the 2000-metal
bar, exactly 1+1 were built -- the chain works. The live bottleneck is the
bar vs real squad sizes (fragmented squads ~1500 metal; peak qualifying
squads 0 in most 40m benchmark games). apex_escort_squad_value is the knob;
the once-a-minute "apex: escort-diag" line prints squads/outmassed/counts
for attribution in hosted games.

T1 CAP: the gate held but the C++ unattributed entrance built labs without
asking it. Def-pin added in choose.as (gT1Def, with a 20s nothing-backs-it
re-point after the plain pin wedged a smoke opening outright -- zero
factories for 12 minutes; do not re-propose a pin without the escape), plus
nanoframe enforcement in hooks.as (same pattern as the T1-commit reclaim):
a surplus land T1 plant appearing while adv-con/T2-mex/reactor are missing
is reclaimed before metal sinks in. Measured: 2nd ground T1 pre-fusion
2/24 games (metric note: count GROUND labs only -- the air intel plant is
exempt by design and polluted the first read as "21/24").

ADVSOLS: "behind the base" was a radius, not a direction -- a forward panel
within apex_advsol_home_r seeded the pack toward the enemy, and the FIRST
panel skipped the block entirely (count>0 gate). Both fixed: founders route
through the rear band, and a seed forward of the base anchor (Base::Coords
depth < 0) is refused. Benchmark-ambiguous (noise band); acceptance is
watched placement.

All arms in today's noise band (7W-7L to 8W-10L on the 24-game benchmark);
compile gates clean throughout.

## 2026-08-21: lab discipline -- the join bug and the double-T2 transition, fixed (kept)

apexearth, watching (Death Valley, 76 m/s): "3 t1 labs, and 2 t2 labs...
started making the second T2 like 15 minutes in... we wasted too much metal
on labs and still don't have our first fusion." Attributed to two defects
in his game's log:
1. JOIN BUG: the commander's "joining the standing factory request" branch
   passed its OWN preferred lab def to Requests::Take -- the standing request
   was armlab, the "join" created an armvp beside it (same frame in the log:
   join line + "request new armvp"). Fixed: Requests::LiveFactoryDef() looks
   up the def actually asked; joining now joins.
2. DOUBLE-T2: the "first fusion before a second T2 line" rule exists, but
   the plant-ask ledger's phantom fuse cleared armalab's ask during its
   walk-and-place gap, and armavp's query 36s later was approved as another
   "first" T2. Fixed with a def pin (choose.as gT2Def): the transition's
   chosen def rebuilds freely through every recovery path; a DIFFERENT T2
   def is an extra and meets the afus+pulsar+army discipline. A plain
   boolean latch was tried first and MEASURABLY WEDGED TECH (83 stuck-
   reopens, 9 no-T2 games, 5W-13L-6D) -- do not re-propose the boolean form.

Measured (24-game 3-map benchmark): v2 is 7W-7L-10D vs the 11W-8L-5D
control -- within noise, tech health equal (stuck 6 vs 8, T2 median 23.8 vs
20.7). The TARGET failures are rare at benchmark income (double-advanced
1/24 games in BOTH arms; the join bug fires in low-income openings), so the
benchmark can only show no harm -- the benefit case is his watched game
class. Confirm by watching: the opening should build ONE T1 lab, and no
second T2 def before a fusion stands.

STILL OPEN (next single change): the fusion itself -- asked on time at
13.7m, starved on execution for 10+ minutes with advCon=1 while mohos
monopolized the only T2 con (ISSUES.md, candidate: floor the adv-con want
at 2 while a fusion request is standing).

## 2026-08-21: air assassin dominance waiver -- landed, NOT yet exercised (watch for "BACK ON")

The drawn 40m games' finisher analysis (two adversarial agents, cross-
examined): the bombers are the ONLY weapon in the stack that targets the
enemy commander -- the win condition -- and t007 stood them down permanently
at the ABSOLUTE AIR_AA_CEILING (2500) against a beaten enemy we out-armied
12:1. Ground AttackTask has no commander case at all; a freed army shoots
the wall, not the win condition. Fix (wing.as AADominated + update.as
un-latch): the ceiling waives and a latched gAbort clears when the enemy
field army is under apex_air_dominance_army (0.2) of ours AND their AA under
apex_air_dominance_aa (0.15) of ours. A/B ran 8W-8L-8D (within noise of the
10-6-8 control) with ZERO aborts latched in 24 games -- the state is rare;
the change is dormant until it recurs. Verify in any future long draw:
grep "STANDING DOWN" then "BACK ON".

Sibling finding left OPEN (ISSUES.md): late-game squads average 3.2 units
and BOTH C++ engage gates (AttackTask groupWeak/nearMargin, SquadTask
squadOverwhelms) test the lone fragment against the whole porc cluster --
40k mobile metal died killing 3.8k of statics in one draw. Proposed fix
(unbuilt): a nearby-ALLY power sum, symmetric to the enemy-side localInfl
aggregation. Also unbuilt: a corsilo request sat inFlight for 10 minutes
with no builder (silo execution, t007).

## 2026-08-21: commander anti-stall -- tried, measured, DEFAULT OFF (apex_comm_hot_secs)

The t003 stall (commander "leaving" 10+ times over 7 minutes, zero
displacement, retreat destination = the hot base it stood in) got a direct
countermeasure: sustained influence at the commander's own tile with no
displacement forces the steered CmdMoveTo, hp-independent, post-T2
(events.as anti-stall block). A/B vs the flee-85 control (10W-6L-8D):
8W-9L-7D, 77 marches fired, commander-death losses 4/6 -> 7/9 -- the march
fires and the commander dies anyway (or the yanking off tasks hurts).
Default 0; the code and tunable stay for experiments. The stall's ROOT --
RetreatTask's destination being the already-hot base -- remains open in
ISSUES.md.

## 2026-08-21: commander DEAD-MAN arms at 0.85 (was 0.55) -- measured direction-positive, kept

Forensics over 8 com-death 1v1 losses: SLOW EXPOSURE dominates -- the
commander holds a build task at ~100% hp on influence-hot ground for 5-9
minutes, then one volley crosses the soft retreat (0.85) and the DEAD-MAN
(0.55) in 2-10s, faster than either produces movement. Fix: arm the
guaranteed CmdMoveTo at the same 0.85 where the soft retreat already logs.
A/B (modoption, 24-game 3-map benchmark vs the 11W-8L-5D control):
10W-6L-8D, DEAD-MAN fires 51 -> 215, losses ending in commander death
7/8 -> 4/6. Power is modest (n=24, W/L within noise) but the mechanism
metric and the loss count both moved the intended way at near-zero cost
(the trigger still requires influence at the commander's own tile).
STILL OPEN from the same forensics (ISSUES.md): a commander that logs
"leaving" 10+ times over 7 minutes with zero net displacement -- the soft
Retreat() path produces no movement while a RETREAT task is held.

## 2026-08-21: T1 arty reweight -- tried, measured, REVERTED (do not re-propose without new evidence)

Hypothesis (adversarial panel round 4): choke maps are lost for want of
artillery -- corwolv is weighted 0.00 below 25 m/s income in factory.json's
corvp block and legbar 0.00 at every tier, so duel-income games cannot answer
a Punisher wall. Tried corwolv tier0/1 at 0.06/0.08 and a legbar floor.
Measured, same 24-game 3-map benchmark: 7W-10L-7D against 11W-8L-5D without
it, with Altair -- the map it was aimed at -- going 2-5-1 -> 1-5-2. Wolverines
were built (composition confirmed the path fired) and the economy stayed
ahead of stock's; the results still went the wrong way. Reverted whole.
The cross-examination had already weakened the evidence: the zero-arty games
were the SHORT losses, i.e. low income explained by early defeat, not defeat
by missing arty. The Altair discriminator that survives is mT2=0 in 4/5
losses, and the economy tracer cleared expansion (mex parity in 4/5 losses;
ownBuilders collapse and structure deaths say the fights reach the base) --
Altair is a fight-quality problem with no room to absorb it, not a
composition or mex problem.

## 2026-08-21: DefendTask engage gate -- built, measured, DEFAULT OFF (do not re-propose as-is)

Mechanism (real, verified in source): a defend pool's only strength gate is
checkPower*4 <= ThreatMap::GetThreatAt(ePos), and that layer reads ~0 almost
everywhere -- a Punisher wall rates as empty ground; the approach path's
threat cost collapses to distance; one-shot units never trigger the squad
retreat vote (needs WOUNDED voters); Merge/Start send reinforcements solo
CmdMoveTo to the dying leader. The localInfl safety massing.as promises
exists only in CAttackTask.

Fix tried: port the group-influence refusal into CDefendTask::FindTarget
(apex_defend_engage_margin), scoped off atUs/base-ring. Measured on the
24-game 3-map 1v1 benchmark, both margins vs the no-gate arm (11W-8L-5D):
margin 1.0 -> 6W-7L-11D, margin 0.6 -> 8W-7L-9D. The gate converts losses
into timeout draws (draws 5 -> 9-11) without adding wins; finishing is
already the weak axis, so refusal-shaped safety is the wrong currency here.
Kept in the DLL behind the tunable, default 0. The UNTRIED half of the
diagnosis remains open in ISSUES.md: threat-aware approach PATHS and gating
the solo reinforcement trickle, which stop the bleed without forbidding the
fight.

## 2026-08-21: retreat config was rolling a per-game army timidity dice -- fixed, 1v1 benchmark 3W -> 11W

behaviour.json still carried the pre-migration 2-element retreat form
("fighter": [0.50, 1.0], comment "[<default>, <modifier>]"). The current DLL
parses index 0/1 as MIN/MAX (MilitaryManager.cpp:314-317) and rolls ONE
uniform threshold per game: our whole army's retreat point was drawn from
50-100% hp (builders 85-100%), so about half of all games were played by an
army that fled at three-quarters health, back turned, released only at 98%.
Stock's shipped hard profile has the same stale lines, so the roll was
symmetric -- what it explains is not the old losses but this benchmark's
NOISE (unchanged-AI swings): each side flips its own timidity coin per game.
Fix: the 3-element form upstream's hard_aggressive already uses
([0.50, 0.55, 1.0] / [0.80, 0.89, 1.0]).

Measured, 24-game 3-map 1v1 vs BARb:stable:hard, same maps/seeds as the
baseline (tournaments/20260821-012258-1v1-baseline-3maps vs
20260821-*-1v1-retreatfmt-fix): 3W-15L-6D -> 11W-8L-5D. Comet 2-6 -> 6-2,
Avalanche 0-3-5 -> 3-1-4, Altair 2-5-1 (choke map, still losing -- the
DefendTask porc story). Death profile moved the intended way: fight:defend
deaths went from ~0 to a leading bucket (units die fighting, not fleeing).

Found by the adversarial 1v1 panel (retreat-mechanics agent), cross-examined
against the battle-reconstruction agent whose "engagement, not retreat"
verdict also stands: both shared this root cause.

## Change log

Full detail moved to `changes/<date>.md`, one file per day, newest first. This index lists each day's entry titles; open the day file for the mechanism, evidence, and measurement.

Older reference/appendix material with no date of its own (binding tables, config tables, known-not-done lists): `changes/reference.md`.

### 2026-08-14

- 2026-08-14: opening-sequence income gate made economy-only, no time cap
- 2026-08-14: many DIFFERENT sites of the same building opened at once — VERIFIED

Full detail: `changes/2026-08-14.md`

### 2026-08-13

- 2026-08-13/14: the army answers one breach at a time, not all of them at once
- 2026-08-13/14: generator tier selection is one energy-per-metal ranking — VERIFIED
- 2026-08-13: duplicate energy buildings landed on the identical tile — VERIFIED
- 2026-08-13: defence budget is a share of metal, not a count of towers
- 2026-08-13: duplicate energy builds were checked against the wrong position
- 2026-08-13: radar towers were placed only where a wall also went up
- 2026-08-13: the enemy model never forgot, and raids never checked
- 2026-08-13: reactors started in parallel and never finished
- 2026-08-13: the front-hold gate skipped the merge, so the army could never mass
- 2026-08-13: rez bots had a hard cap of 8, and two of them
- 2026-08-13: a rezbot and a con turret fought each other over a windmill forever
- 2026-08-13: a T1 constructor was blocked by a job only a T2 one can do

Full detail: `changes/2026-08-13.md`

### 2026-08-12

- 2026-08-12: ally aid — the signal was already there, the response needs the DLL
- 2026-08-12: Fight is the wrong primitive -- move, and set-target the preference
- 2026-08-12: the standoff was silently reverted by a factory commit, and the ring leaked
- 2026-08-12 (night): five mechanisms, all found by agents from a watched game
- 2026-08-12 (evening): six things apexearth saw in one watched game
- 2026-08-12 (later still): the budget counted solar collectors as defence
- 2026-08-12 (later): the quota was building nothing but constructors, and the benchmark was hiding it
- 2026-08-12: factories run our own standing queue, not one CRecruitTask per unit

Full detail: `changes/2026-08-12.md`

### 2026-08-11

- 2026-08-11: three rules deleted, one real bug fixed, and a pattern banned
- 2026-08-11: the tower blobs were ONE rule, and its throttle was never wired
- 2026-08-11 (corrected): the safe ground exists, and it is EARLY
- 2026-08-11: there is no ground forward that a builder is allowed to work on
- 2026-08-11: WHY the front orders are never filled -- the site search refuses
- 2026-08-11: the front line is aimed correctly and almost never built

Full detail: `changes/2026-08-11.md`

### 2026-08-10

- 2026-08-10: the Brain — rules propose Wants, one ranking decides
- 2026-08-10: where the 1v1 ended up
- 2026-08-10: the 1v1 win rate is 1/66, and the 20-minute cap was hiding it
- 2026-08-10: `hard_aggressive` is a STALE stock profile, and apex was forked from it
- 2026-08-10: the fighter-task C++ delta costs 12 points, and is reverted
- 2026-08-10: apex stands aside when it has no allies, and moves onto the `hard` base
- 2026-08-10 (NEGATIVE): switching the T2 rush off in small teams changes nothing

Full detail: `changes/2026-08-10.md`

### 2026-08-09

- 2026-08-09: Behemoths charge the front instead of walking round the map
- 2026-08-09: units walled in by our own buildings get a way out
- 2026-08-09: the AI desynced multiplayer by asking the engine for a path
- 2026-08-09: the AI crashed the engine because C++ deleted tasks the script held
- 2026-08-09: the front line gets per-player sectors, and defenders stop garrisoning minute 5
- 2026-08-09: a raid that runs out of targets presses on instead of walking home
- 2026-08-09: T3 heavies hold the defence line instead of walking out alone
- 2026-08-09: keep building silos while both banks are over 80%
- 2026-08-09: nuke the army massed on our own border
- 2026-08-09: help the identical building already started, instead of starting a second
- 2026-08-09: mobile AA is all-or-nothing, and it never travels with the army
- 2026-08-09: long guns stand at 90% of their range instead of 40%
- 2026-08-09: The ally-mex upgrade also CLOGGED the mex_up slots — fixed in C++
- 2026-08-09: A crash in AiTaskRemoved — a dangling task handle, not the mex work
- 2026-08-09: Constructors walked into an ally's base to upgrade a mex that was not ours
- 2026-08-09: A mobile radar travels with the army
- 2026-08-09: A defensive posture buys artillery and fodder, not Bulls
- 2026-08-09: Jammers are placed deliberately instead of by chain accident
- 2026-08-09: Pinpointers are capped at three for the whole TEAM
- 2026-08-09: mex defence scales with how close the mex is to the enemy
- 2026-08-09: the AngelScript was split up (pure refactor, no behaviour change)
- 2026-08-09: found while refactoring, NOT fixed
- 2026-08-09: we never attacked, and the group size was the reason
- 2026-08-09: solar was chosen over wind on essentially every map
- 2026-08-09: the T2 rush is a TEAM strategy running in 1v1
- 2026-08-09: every 24-game arm, and what actually survived
- 2026-08-09 (SETTLED): trade caution is HARMFUL at proper sample size
- 2026-08-09: constructors walk the whole map for trees
- 2026-08-09 (CORRECTION): the army-trade metric has a 30% noise floor at n=8
- 2026-08-09: adaptive caution improves the army trade 47%; a blanket bar makes it worse
- 2026-08-09 (CORRECTED): the 25% close-range deficit was contamination
- 2026-08-09 (WITHDRAWN, see above): we lose close-range fights by 25%

Full detail: `changes/2026-08-09.md`

### 2026-08-08

- 2026-08-08: the bank is empty, not full — the fraction-of-storage gates are dead
- 2026-08-08: the gantry cap WAS the T3 constraint
- 2026-08-08: measured -- the six changes are a net win
- 2026-08-08: the constraint is build power, not space
- 2026-08-08: one base layout, replacing position-plus-shake

Full detail: `changes/2026-08-08.md`

### 2026-08-07

- 2026-08-07: naval response was switched off entirely
- 2026-08-07: front vs back, and the front starts UNKNOWN
- 2026-08-07: the front is our own perimeter, not a seam
- 2026-08-07: the front line is not at the chokepoints
- 2026-08-07: BWEM chokepoints exist, and were unreachable
- 2026-08-07: constructors no longer pre-empt themselves into reclaim
- 2026-08-07: RESULTS BELOW WERE VOID -- read this first
- 2026-08-07: the aggression session (RESULTS VOID, SEE ABOVE)
- The metal-full fallback was buying Pit Bulls — 2026-08-07
- Commander idling at a haven patrolled back and forth forever

Full detail: `changes/2026-08-07.md`

### 2026-08-02

- How the AI judges a fight — four defects found 2026-08-02
- Defence towers were always the cheapest one — FIXED, unmeasured
- Rez bots died to all-or-nothing resurrects — FIXED, unmeasured
- Metal converters may be eating the expansion gap — NOT ACTED ON

Full detail: `changes/2026-08-02.md`

### 2026-08-03

- Gating CDefendTask promotion — TRIED, REVERTED 2026-08-03
- Squad join radius 1000 -> 3000 — squad size FIXED, win effect UNPROVEN
- Naval players built no energy at all — 2026-08-03
- Range: no tower we build can answer enemy artillery
- The army loses; the towers do not carry us — measured 2026-08-03
- ENGAGE_MARGIN works at 25 minutes and not at 40
- Reclaim cannot see the bodies

Full detail: `changes/2026-08-03.md`

### 2026-08-06

- Three fixes from one live session — 2026-08-06
- Three more, same session, from watching two windowed games back to back
- The tech-lead election was a one-way trip past 15 minutes

Full detail: `changes/2026-08-06.md`


### 2026-08-21

Tunables audit (git-history-verified per item), all compile-gated clean:

- `factory/buildpower.as` REMOVED — factory build-power requests, apexearth's
  own 2026-08-19 idea, but measured hurting (K/D 0.86 -> 0.48 paired seed),
  default-off since, and its problem statement is now solved by the assist
  path's army-shortfall gate (`apex_assist_army_frac`). Four knobs went with
  it (`fac_demand`, `fac_ask_hold`, `fac_help_mult`, `fac_spare_frac`).
- Jammer gate merged: `apex_jammer_upkeep_margin` deleted;
  `JammersAfforded` no longer grants a free first jammer (`1 + int(...)` ->
  `int(...)`), so the count formula is also the gate. First jammer now needs
  income >= upkeep/share (10x upkeep at the 0.10 default) vs 4x before —
  slightly later on small grids, unchanged at scale.
- `apex_t2_energy_floor` (700) deleted — the pre-T2 energy forecast now
  builds to `apex_t2_energy` (800) itself, so the grid the forecast builds is
  the grid the rush bar demands.
- `apex_reclaim_advsol_e` + `apex_reclaim_wind_e` (both 2000) merged into
  `apex_reclaim_gen_e` — one number in apexearth's own statement
  (">2000 reclaim wind and advanced solar"); wind's map-wind scaling kept.
- Incoming-push DETECTION renamed `apex_push_*` -> `apex_incoming_*`
  (notice_r, cost, closing, danger_pad, danger_cost, answer_frac, stand) —
  the prefix had collided with the team-push family.

KEPT, verified against history (do not re-propose):

- `ArmyPressureMod` is NOT redundant with the budget's `LossArmyMult`/stance
  multipliers: the budget never reaches facqueue army production (targets.as
  2026-08-16 warning), so it is the only adaptive army-count response.
- The three outnumbered predicates (`Outmassed`, `ConservativeStance`,
  `mass_no_commit_ratio`) differ deliberately in ratio, fog policy and
  consumer; fog-flooring `Outmassed` would suppress constructor growth while
  blind, which is the wrong direction for the economy.

### 2026-08-21 (later)

- `apex_rez_per_income` 0.1 -> 0.2 — double the rez fleet, still income-scaled.
- BATTLEFIELD MEDICS (`rules_rezzer.as` RezzerMedic, apexearth request): a
  tunable share of rez bots (`apex_medic_share` 0.4) stays with the army's
  staging anchor — repairs wounded mobiles near it (`apex_medic_r` 1200),
  holds station by area-reclaiming the aftermath there. Flee rule still wins;
  threat at the anchor holds the medic home. Compile-gated clean.
- FORMATION TRAVEL (C++, AttackTask+DefendTask, apexearth: enemy "uses the
  synchronized move speed fight orders... we give spread out move orders"):
  ground squads now travel on CFightAction (CmdFightTo waypoints +
  CmdWantedSpeed at the squad's lowestSpeed) instead of per-unit CMoveAction.
  Previously only SIEGE-attr units (32 defs) fought-travelled. Flyers keep
  MOVE; RaidTask untouched (raiders bypass fights). Wounded pull-back is
  unchanged: RetreatTask swaps the travel act out, which IS dropping the
  fight order; the standoff/kite ring still owns distance in the engagement
  phase. Tunable `apex_fight_travel` (default 1, in dev_tunables.lua) for the
  A/B. NOT yet judged on a watched game.

### 2026-08-21 (watched-opening batch, Altair campaign)

Five watched-game reports, each traced to a mechanism, fixed, and measured on
Altair (16-game arms, apex_share_defence=4, vs BARb stable):

- BASE AXIS 180-FLIP REMOVED (`baseplan/axis.as`): a start near a map edge
  scored the true rear 0 (probe off-map) and the flip then won on any count,
  laying the whole eco band TOWARD the enemy (watched: solars at fwd 0.36-0.39,
  log `axis front=0 kept=44`). Perpendiculars remain the fallback; energy now
  lands home-side (fwd ~0).
- FIRST LAB PLANNED AT HOME (`rules_commander.as`): the factory request used to
  carry the commander's wander position; now `FindBuildSiteNear(home)`. With the
  home-anchored opening-mex bound in `brain.as` (per-jump bound could not stop a
  chain of hops), the lab commit moved from ~1.8-2.3m to 0.7-0.8m and the
  metal-full walk is gone.
- NEAR-PASS MEX SENTRY (`rules_commander.as` nearOnly + maketask slot above
  PassingMex): the mex a builder just finished gets its turret before the
  builder walks away. Sentry #1 now ~2.2-2.5m (was ~6m or never). On Geyser the
  pass correctly declines: the home LLT already covers the start mexes.
- PANIC/WIND MATH + TIDAL (`mexguard.as`): the panic-stall branch hardcoded
  solar and had put 5 panels down on a wind 12-27 map before the ranking ran;
  it now compares EnergyValuePerMetal and takes wind when bank+5s of income
  covers costE. Tidal (armtide/cortide/legtide) enters the T1 ranking on
  water/mixed maps, gated on a placeable site near home.
- RECALL HOME OR COMMIT (`military/withdraw.as`, apex_recall_home/_fwd): while
  BaseUnderAttack() and no killing blow armed, ATTACK/RAID squads past fwd 0.5
  are ordered to gHomePos (not the nearest tower) to mass over the contested
  ground; gKilling still exempts a committed push. Smoke: recall fired 11.4m,
  squads walked home.

Altair 1v1 ladder: baseline 2/16 (12.5%) -> opening fixes 3/16 (18.8%) ->
+recall 5/16 (31.2%, CI includes 50%). H15 wall-arty was a null (2-11): a few
Wolverines do not answer the porc-creep; entry stays until superseded.

Harness note: a 6-worker tournament froze all engines at the same second once
(cause unknown, not RAM); killed and relaunched clean. Watch for repeats.

### 2026-08-21 (evening, live-game batch)

Fixes traced from apexearth's watched/hosted games, each with the measured
mechanism (details in the commit messages 8be6c90..ba85b52):

- Second-T1-lab fork closed at Requests::Take; in-flight factories counted
  as pool + MANNED registry (the engine's held placeholder wedged the
  opening when counted -- facCount=0 at 10m until Workers()>0 separated it).
- Commander: stuck-breaker decays instead of resetting (191s phantom-task
  stands), cloak hysteresis (23 flips/2min at used==produced).
- Economy: converter urgency = spare/600 (27k produced vs 8.4k used, live);
  extra advanced plant bypasses milestones at 8s of income (his 150 m/s
  bar); gantry sited by us with a doubling radius; big-build assist gives
  frames a cost-scaled worker floor; JoinFor reach scales with the build's
  income impact.
- Brain: no want may exceed 1.5x all others in the roulette (gantry=80 vs
  silo=3.5 starved nukes/antinuke); crew ENERGY/METAL roles with fleet-ratio
  slots and demotion (roles-off A/B read them ~neutral); rez log curve +
  floor split; rez may buy the bot lab post-reactor.
- Escorts: native guard system uncapped [12,1,100000]; air scouts excluded
  from fodder/spam.
- Home-stand strength gate: NULL at both ratios, reverted (ISSUES.md).
- tools/units.py: per-team built-units dump, counts + metal share.

Arms (16-game Altair 1v1 unless noted): batch3 4-12, tonight (no
modoptions) 3-13, cycle9 4-12 -- stable 19-31% band vs 12.5% session start.
2v2 cycle9: 1-11, the campaign's first 2v2 win (prior 0-11, 0-12).
share_defence=4 is the shipped default. The standing bottleneck is
unchanged: trade 0.29-0.49, engagement selection (ISSUES.md).
