# Open issues — what is wrong with this AI right now

## 2026-08-30 — the wall revamp: LANDED (75b2d97), residue open

His ask: towers blobbed at the start area; he wants a wall wrapping the
base, joining allied walls, advancing with expansion, rear towers
reclaimed, tiers rising — explicitly NOT built on the front-line or
base-border models. Landed as `apex_wall` (default on): perimeter slots on
the building rim (protect_wall.as), the open-slot target pull, and the
held-ahead stranded retirement. Measured across the exercise loop (45-min
vs BARb medium, `apex_mass_hold_ratio=0.05` so defence is isolated):
baseline 10 towers 9 interior rimDAvg −507 → final iteration 19 towers 18
standing, 0 self-reclaims, rimDAvg −204, wall closure 0.58 vs 0.20.
`tools/wall_check.py <match>` is the instrument. Open residue:

1. **Displacement: battery row 20260830-100042 read, no alarm, watch the
   next rows.** vs pre-wall row 092154: trade 0.30→0.24 / 0.30→0.59 /
   0.37→0.58 (up on two of three maps), mex@15 13→11 / 24→18 / 5→6 (down
   a little on two), t2 median mixed (17.7→14.1, 10.7→16.2, 18.0→14.8).
   All within one row of historical spread — directional only. In the
   battery's own normal-play Comet games the wall held: Apex 10–25 towers
   per game, on-wall share median ~48% vs the baseline blob's 36%, NN
   spacing 125–600 (bands, not a clump).
2. **Front::GateChokes returned ZERO candidates in every 1v1 exercise game**
   (`lineSpots=0` all game). The concentration-doctrine gates are inert in
   these matchups, so the wall carries everything. Pre-existing, now
   load-bearing.
3. **Towers finish ~200 elmos inside the wall** — the wall steps outward
   during the builder's walk+build. Harmless at one quantum; the at-build
   rim/core split reads worse than election siting (election wallD≈0).
4. **Tier progression on the wall is untested** at high economy — the
   T1-late ×0.15 discount on T1 cons plus full pull on T2 cons should put
   T2 guns on the wall late; verify in a long game before trusting.
5. **Ally-join is smoke-tested only** (2v2: candidates priced, no
   exceptions, no crash) — no visual confirmation that two Apex walls
   actually meet.
6. The closure-ring candidates (`apex_def_ring`, entry below) are OFF-path
   while `apex_wall=1`; that entry's "awaiting measurement" is superseded.
7a. **Frontier line landed** (his "walk to halfway capping mexes, then
   wall" meta): the line anchors at the furthest capped mex along the
   enemy axis, midline-bounded; armed builders (commander) may creep
   slots their own guns cover, and the commander's 400-elmo ban excepts
   wall work behind the wall. Best game yet: win, 30 towers, 1 lost,
   lineFill 0.75. OPEN: the commander never actually elected defence
   (eco wants outbid the pull) — permitted but not price-favoured; ask
   him whether the commander should carry an explicit early-wall
   preference before nudging. wall_check's on-wall band still measures
   the building hull, so frontier towers misread there — lineFill and
   wall_map are the instruments.
7. **His 2v2 expectation — "a clear line of towers across the map" — is
   NOT met yet, and the blocker is the army, not the placement.** After
   the line rework (slots across the lane, joined to ally lanes, full
   pull, enemy-cost safety gate) the machinery sites correctly: 1v1
   hold-0.3 win with 26 towers 69% enemy-side; 2v2 team 0 stood 19
   towers at closure 0.33 by minute 20. But three 2v2s vs BARb medium
   lost in a row on army/eco, so the front collapses to the base corner
   and the wall honestly concentrates THERE — which reads on screen as
   "towers in the middle of our base like always". A midfield line
   requires the midfield held; that is the standing team-game gap (8v8
   entry below), not a defence-siting defect. Re-show him a 2v2 after
   the team-fight work moves.

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

## 2026-08-29 (late) — deploy_ai.py exits 0 when it REFUSES to deploy (harness trap)

"Close BAR (and any running match) and retry" prints and the process still
exits 0, so `deploy && run` guards do not guard: a repro game launched
against the stale build tonight and would have been read as "the change
did nothing." Check the output text ("Harness spec" = success) until the
exit code is fixed.

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

## 2026-08-29 (night) — FIGHT-LOGIC CHAPTER CLOSED (arena campaign)

The stack, each landed with its own commit and A/B arm: hold-committed
(no solo pull-outs under fire; deaths-with-W 38% -> 5-9%), dry-kite
cancelled (apex_brawl_stand: no backstep to where our own guns are dry),
armmar threat surf 0.5 -> 1.0 (Marauders counted as half in every
strength sum), runner-discount (retreating/ordered-back allies count
zero in OutgunnedHere), wrap-edge at ring placement (apex_wrap_arc;
fires in EVERY fight task -- the FindTarget version fired zero times in
104 rounds). Verification game 710: 0 compile errors, 33 wrap-arc
fires, zero contaminated rounds. Watch-game survival edges: pre-fix
-0.09 (his damage-efficiency read) -> +0.013 -> +0.039 -> -0.005
(single-game sigma ~0.04; pooled paired arms remain the instrument).
Arena instrument final form: ranked formations, 2-6 defs x 6-20, no AA,
no kamikaze (selfDCountdown==0 excluded), rez adoption, neverend,
60-min x 3-seed x both-orientation arms.

His verdict watching a real tournament: "it was clear at this point our
fighting was not our downfall -- it was a lack of nano turrets around
our gantries." The gantry-nano saga is EXPLICITLY off-limits without a
fresh ask (see memory gantry-nano-saga): ~2 dozen failed in-the-box
attempts; needs a design change, proposed before patched.

## 2026-08-29 (night) — nano saga root-caused and fixed, MEASURED (commits 045fa22, 3d4a147, 885305c)

The fresh ask (Archsimkats +100% 1v1: "35+ nanos on their gantry, ~6 on
ours, not affordability, we can't produce enough military"). THREE
mechanisms lied to each other and equilibrated at a starved gantry:
1. facqueue LineBuildPower used a fleet-average assist share, blind to
   the actual ring — a ringed gantry's "15s" queue drained in ~6s and
   the line sat dry until the next 10s Wait ("the labs weren't making
   anything" while the bank pegged 84-99% full).
2. The nano demand laws priced every standing nano at a flat 17.5 m/s
   absorb; a Vanguard line runs 7.3, so the ledger said "served" at
   half the ring the line needed.
3. ConOrderFor's HardEStall mute emptied every queue for 29-50% of
   late-game samples while metal overflowed, and the muted lines
   stopped pulling E — hiding the demand the energy market sizes
   generators against.

Proof (A+B+C, both proof seeds WON where control lost or froze):
duty 83-95% sustained, army production compounding to 356/502 m/s,
waste 9%/5%, nanos-at-best-factory 20v8 and 59v12 (control loss read
10v71), mid-game e-stall 0-2%. Commit messages carry the full numbers.
NOT yet re-measured in his hosted games — his eyes are the closing test.

STILL OPEN — frames abandoned on contested ground: armnanotc fell 333
-> 67/113 per game, but armmex (36-48/game), armrad and armdrag frames
still rot where they were founded; task-die why=unreach-safe. The
fights/defence campaign owns the killed half; the founder-walks-away
half is ours. Instrument: [BARAI_DUTY] + finish-before-founding audit.

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

## 2026-08-29 — THE ARENA SURVEY: close-fight micro is engine-bound at parity

His instrument (dev_arena pure/random), his +15% target, six mechanisms
measured in paired ~90-round arms (noise floor sigma~0.05/run, calibrated
on identical-logic arms reading -0.055 and +0.035):
- kiting OFF: -0.123 (kiting earns its keep; the only clear signal)
- range_mod 1.0 / kite pad 40: ~+0.05 each, at one-sigma -- unproven
- focus-fire v1 (lowest abs HP): harmful; v2 (+sticky, fraction): harmful
  (-0.068 paired, 3/3); v3 (set-target only, lethal-dose portions, his
  refinement): neutral mean, strikingly low variance
- brawl passthrough (no orders without a range edge): neutral (default 0)
- fist vs arc (apex_arc_span 0.3 vs 0.9): +0.012 net -- unresolved
- no-control diagnostic: units STRIPPED of our orders beat stock
  consistently (+0.047); commanded units same mean, wilder variance

CONCLUSION: mirrored equal-army fights at mutual LOS are decided by the
engine; the AI order layer (ours or stock's) moves the outcome at most
~±0.02. The +15% arena margin cannot come from order tweaks. Where an
edge that size CAN come from: information (radar), arrival concentration
(operational, not tactical), composition (reach vs their mix), and the
economy behind the army. The arena's standing role: a REGRESSION GUARD --
fight logic must never fall below parity -- not a gain mine.

## 2026-08-29 — THE CONVERSION FAILURE: a 3.5x economy loses the 1v1 anyway

Measured on decision-length games (50m caps, 8 per map, winrate-comet /
winrate-glacier): decided results 2-10 vs stock overall. On Comet we led
the mex race 18v14 @15m, 45v29 @25m, 102v29 @35m — three and a half times
their economy — and went 2-6. Five of those six losses ended with OUR
COMMANDER dying at fwd 0.00-0.18 (AT HOME) between 18.7m and 32.7m: the
economy never killed them, the game ran long, and one breach decapitated
us. The eco lead converts into mexes, not into finishing power or into
commander safety. Suspects, unattributed: the killing blow not firing or
not finishing on a won economy; home defence + army-at-home losing to the
late push despite wealth; overflow (12% metal wasted flag) meaning the
lead is partly paper. This is the next campaign; do not chase it with
6-game arms — use decision-length games and the death ledger.

Glacier is a SEPARATE disease: eco dead-even (5v5 @15m, 14v17 @35m), 0-4
decided, and two commander deaths at fwd 0.99 and 0.71 — a commander deep
in ENEMY territory at 27-31m. Either the flee destination sent him the
wrong way ("toward home only if home is safer" picking the enemy side) or
a job election walked him there. One game's fhist would attribute it.

TEAM CONFIRMATION (first --teams battery, 2026-08-29): 0W-9L decided
across 2v2/4v4/8v8, trade 0.22-0.25 everywhere, mex parity-to-lead
(30v26 in 4v4). The death ledgers name the shape in both team sizes
sampled: the army barely dies ATTACKING — it dies RETREATING (36%/28% of
lost metal, 374-400 units per game), and the rest is structures and
nanoframes at deep-rear forward fractions (4v4: 55% at fwd -0.2; 8v8:
structures 37% at fwd -0.99, idle deaths at -0.84). The enemy is inside
our base in every format while our units flee-and-die on our own ground.
The campaign's two fronts, in order: (1) retreat deaths — the flee
threshold/haven walk turns damaged units into free kills mid-map ("look
at the action before the retreat"); (2) the rear is reachable — the
perimeter/gate defence work has not yet turned this ledger. Instrument:
decision-length games + deaths.py fhist, never 6-game win counts.

Action-before-fatal-retreat, decoded (one 4v4, fhist tags before R):
W=54 (our own withdraw order preceded the death — too late, or the walk
is the exposure), bomb=50 (air domain), scout=47 (spam-phase fodder
rides SCOUT tasks), guard=21 (escorts), aa=16. Front (1)'s first target
is the W->R->death chain: the pull-back's timing and its route, not the
existence of pulling back.

CAMPAIGN LOG:
- Iter 1 (rearward-only W destinations + T2-floored comm caution): W-death
  metric UNMOVED (40% wrong-way vs 34% baseline, 701 deaths), decided W-L
  3-9. Verdict: the W order is one-shot and the task fights it every tick;
  order-level fixes cannot win. Next front-1 shape: TASK-level abort on
  trade-loss (IUnitTask::Abort is bound; superguard proves it) for
  ATTACK/RAID only — designed, held until iter 2 reads out.
- Iter 2 (apex_def_eco_s 30 -> 120): the reframing find — apex army share
  was FINE (43%); the deficit was DEFENCE, stock 11.7k-52k standing vs our
  0.6k-18k, because 30s of eco budgets 750 metal of towers at benchmark
  income (the tunable's own comment said "not derived -- measure it").
  Explains front-sites-won-26x-built-0. Measurement: winrate3 arms.
- Iter 2 verdict: defence CONVERTED (9.6k standing median) but W-L stayed
  2-11. Necessary, not sufficient. The trail it opened: apex income 46-50
  vs stock 160-192 in the same losses; the mex counters that said we led
  were CUMULATIVE builds, flattered by our mexes dying.
- Iter 3 (Front::FoeAnchor): PastFront's axis endpoint was the k-means
  centroid of enemy PRESENCE — their army in our half collapsed the axis
  and vetoed the map (pastFront=225/sweep, held 4-6 of 80). Re-anchored on
  the structure-dominated gFoeMid. Smoke: held 17-18 at 20m. This is also
  the mechanism that let the day's fight-caution changes read as a mex
  regression with no single culprit: deeper enemy presence, earlier,
  shrank the claimable world. Measurement: winrate4 arms.
- Iter 4 (apex_radar_overlap 0.45): WORKED — seen army doubled (11.8k),
  trades day-best (0.43-0.60), 4W-10L.
- Iter 5 (fight-abort): measured 1W-11L, Glacier trade 0.60->0.35 with 37
  aborts — reverted to opt-in (apex_fight_abort=0).
- Iter 6 (static always kiteable): tower-fed deaths -19% (48.6k->39.4k),
  trades held. Kept (his "we don't want to tower dive" endorsement).
- INSTRUMENT NOTE: W-L at 12-14 decided games swings ±3 on nothing (1-11
  vs 4-10 across arms with identical trades). Steer on mechanism metrics
  (trades, tower-death share, income@fixed-time, wdeaths); read W-L only
  at 20+ decided or on a compounding effect. Arms widened to 12/map.
- Iter 7 (concentration part 1: apex_gate_depth=2 floor, mex spread floor
  halved): his ruling verbatim in USER-FEEDBACK. Measurement: winrate8.
  Queued: teeth line across the gate span; long-range free-shot posting.
- Iter 8 (teeth + bomber energy pricing): bombers killed 25k of Glacier's
  generators in one arm (the energy ruling delivers); teeth needed a FOUR
  step attribution (ignore flag, tower deadlock, gain 3 orders low, gain
  overshot) and now elect at v~16 but complete ZERO -- the walk-churn
  abandonment (velocity plan territory). 8 of 24 games reached the cap
  with the commander alive; Comet's cap games were TRUNCATED WINS
  (income 479-vs-4).
- Iter 9 (apex_kill_off_frac 0.35): the blow flapped 15x in one game
  because the push's own casualties retreat and read zero power, halving
  OurArmyNow into the 0.6 disarm band. Widened.
- Iter 10 verdict (winrate11): COMET FLIPPED -- 6W-4L + 2 ahead-at-cap,
  trade 0.867. Glacier 1-8 (trade 0.648, its day-best): the corridor
  grind is the open 1v1 front, then 2v2 per his ladder. t010's shape
  (rich but out-massed 27k-59k, blow never armed) is the other open
  thread: high-income army conversion.
- Iter 11 -- FULL LADDER CHECKPOINT (winrate16 x2 + battery --teams-only,
  2026-08-29 night, all defaults: focus_finish=0 brawl_pass=0 line_adapt=0):
  1v1 Comet 5W-6L(1T) trade 0.72 -- parity holds. 1v1 Glacier 1W-8L(3T)
  trade 0.44. 2v2 0-1(3T) trade 0.459. 4v4 0-4 trade 0.289. 8v8 0-2(2T)
  trade 0.199. Every team trade roughly DOUBLED from pre-doctrine
  (2v2 was 0.248) and 5 of 7 team games now reach the cap undecided --
  survival landed, wins have not. Glacier death anatomy MOVED: rear
  structure loss down to 17%; fight:defend 34% + retreat 28% of lost
  metal, BOTH at fwd 0.59 -- the war is now lost grinding the corridor
  MIDFIELD past center while gate towers (standing 83% of samples) fight
  nothing. Commander death 23-41m still ends every decided loss.
- Iter 12 (defend leash 0.55 -> 0.35): FAILED -- winrate17-glacier
  1W-10L(1T) trade 0.53. Trade improved (0.44 -> 0.53) but wins fell:
  holding defenders home cedes the corridor's middle mexes. REVERTED to
  0.55. Lesson pairs with the fight-abort result: on Glacier, declining
  the midfield in EITHER direction loses; the corridor demands winning
  the grind, not avoiding it.
- ARENA REBUILT BIGGER (his ruling, 2026-08-29 night: "Try letting the
  battles last longer. Try having more units in them. Trying to have more
  columns of units." + "you are not running long enough tests"): random
  rosters k 2-6 defs x 6-20 each (was 1-4 x 3-10), rez 2-5, round cap
  1800 -> 5400 frames, and spawns are RANKED FORMATIONS (rowW ~
  sqrt(2.5*total), later ranks stack behind the front along the away
  axis) instead of one thin 64-pitch line. A/B arms now run 60
  game-minutes x 3 seeds x both orientations. Baseline: arena-bigbase-*.

## 2026-08-29 — perf spikes attributed: the builder election, protect stack inside it

His standing complaint ("We still have performance spikes in the game which
we need to fix"), measured on the 43-min Isthmus win (20260829-161430):
`hk.maketask.builder` 107.4s total, WORST SINGLE CALL 126ms (a visible
hitch); inside it the protect stack sums ~66s (want.protect 30.2s +
prot.loop 16.2s + prot.sites 10.2s + prot.slot 9.8s). DefSiteFill runs per
tower def with RiskFill each pass, and the 2026-08-29 choke-gate and
guard-forward candidates feed this exact path. Optimization is its own
session: candidates are memoizing RiskFill across defs in one pass, and
capping DefSiteFill's per-tick def count. Do not add more candidate
generators to the protect stack before this.

2026-08-30: the two prescribed optimizations LANDED (RiskFill/RiskFillSiege
frame memos, ClosurePrep memoized on the field stamp, DefSiteFill capped at
two fresh fills per frame) — see the commit. Worst single call on a 12-min
smoke: 12ms; the 126ms baseline was a 43-min base, so the entry stays OPEN
until re-measured at that scale (the closure-ring candidates added on top of
the cap are bounded by it, ≤16 sites per fill).

## 2026-08-30 — all-angle defence: closure-ring candidates (LANDED, awaiting measurement)

His ask: "We often suffer hard from enemy flank attacks to our side... at
the late game we'll have enough base defenses to guard ourselves properly
at all angles", and "on some maps you might be completely surrounded. So
our angle of defense has to be really flexible." The mechanism found: the
closure ring (ClosureAdds) already PAYS a post for every approach bearing
it newly closes, but no candidate ever stood on a cold bearing — asset
guard sites hug our metal and are shifted toward the enemy centroid
(apex_guard_forward), FrontBuildSpots offers only RayFacesFront (hot)
bearings, and the two all-angle generators that exist (ShieldArcSpots,
NetSpots in territory.as) have ZERO callers. So the flank credit existed
and nothing could collect it. Fix (apex_def_ring): DefSiteFill now offers
one candidate per OPEN closure-ring bearing, pulled inward so the def's own
reach still covers the ring point (rS = ring − reach×0.8); map-edge
bearings are walls and are never offered. No arc constant — a surround
makes every on-map bearing a candidate, priced individually. Read it via
`apex: defsite ... ring=N bestRingGain=` (auction wins) and
`apex: fronttowers ... closure=` (share of bearings covered; should trend
up late game). Verify on a long high-economy game, not a 15-min benchmark —
at low income DefenceTarget is a handful of light towers and ring sites
correctly lose to mex floors.

The first deploy of this SHIPPED A CRASH apexearth caught live ("seems the
actionscript wasn't running"): the loop's sStake read kept its old
`isFront ? ... : PfSiteStake(si)` guard, a ring site is not front, and
PfSiteStake indexed the asset slot cache past its end — 797-1,024 "Index
out of bounds" exceptions per game, each aborting the whole builder
election. The AI looked dead while the script loaded fine: mex@15m 2 vs a
healthy 12, zero towers, no T2 (battery rows 190146/190716 are this bug,
not a behaviour read). The compile-error grep reads CLEAN on this failure
mode — review.py's ran-gate now counts runtime `Exception:` lines too.
Fixed (all slot-cache reads gated on `cached`), redeployed, verified:
0 exceptions, held=11, ring=13 auction wins, closure=0.69 at 23 min.

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

## 2026-08-29 — Callisto mex@15m regression: bisected to "distributed", ruled kept

Full bisect story (all Callisto 1v1 25m, apex-vs-stock mex@15m medians):
last night 21v16 | today all-off 16v12 | all-on 11v12 and 11v9 (n=10, with
the eco fixes) | each single member off 11-12 | fight-caution pair off
12v8. No single member of {arty_mass, losing_floor, choke_gates,
guard_forward} explains the ~5-mex gap; each costs ~1-2 inside a noise
floor of +/-3. Exonerated by direct measurement: protect-stack perf
(0.3-0.4ms/election both arms), army forward position (0.17 vs 0.16),
defence spend share (6.5% vs 5.8%). Correlated but insufficient: techStart
2m later on-arm (16.3 -> 18.3m). Trade ratio runs the OTHER way: all-off
0.36, all-on 0.41, defence-only 0.52 -- the features buy better trades.

apexearth's ruling 2026-08-29: "Keep all on" -- the survival/defence gains
are what he watched working; grind the map-control cost down mechanism by
mechanism. Next instrument is the fixed battery trend (proper N across
days), NOT more one-off arms; stop re-litigating this with 6-game medians.

## 2026-08-28 (night) — THE OVERFLOW CAMPAIGN: his goal list, status ledger

Goal set tonight: "Fix and validate (through auditing) the mentioned issues
until all the ones I've mentioned are complete." Status after four waves
(commits 709e550, 1d1f1b8, 224a8c4, 6bb4561):

1. **Super sites never relocate** -- LANDED + MEASURED. ProbedSite ring
   search + blocked-ground feedback; site-widen fired 34-67x/game, s106
   rerun super-site-stuck quiet. Residue: armaap/armamsub still stick
   occasionally (facing/exit test invisible to the probe; the blocked-pos
   note now breaks the repeats).
2. **Strategic market too serial when rich** -- LANDED + MEASURED.
   SuperFlightCap = 1 + overflow/140. wealth-unspent audit OK in all four
   validation games (pre-fix: 46% thrown away); team metal-wasted 34->17%.
3. **The overflow ladder (nanos -> second gantry -> supers)** -- LANDED +
   MEASURED. WealthWaiver; 13-14 gantries + silo fleets fielded per 2v2;
   the retire law keeps waiver-bought copies unless the economy is
   squeezed, plus a per-def no-retire window for apex_replant_window_s
   after a waived buy (the squeeze test alone flapped: armshltx rebuilds
   7 -> 5 -> 0 in s45/s107 with the window).
4. **T1 air army after T2** -- LANDED + MEASURED. t1-air-after-t2 audit OK
   in every game since.
5. **Front towers / mex guards** -- THE SILENT KILLER IS FIXED; the next
   face is now visible. Pre-fix every bt=7 task death was
   why=unreach-safe (OnTravelEnd's safe-reach veto refuses threatened
   ground -- exactly where a tower is wanted; s43: 960 front elections
   won, 0 built, all defence task deaths unreach-safe).
   DEFENCE/BUNKER/BIG_GUN now test pure reachability. Post-fix (s45, a
   contested 2v2 loss): guard-tower FRAMES now start at the front --
   armguard=54 in finish-before-founding, hurt-retreat=42 -- and die to
   enemy fire, with Take's ThreatFor veto refusing to re-man a hot frame.
   So the family's mechanical half is closed and the remaining half is
   POLICY: how far forward towers are sited and whether their builders
   get escorts. That is a design question for apexearth, not a bug.
   Mex-guard tower share of orders rose 32% -> 67% (s43 -> s44).
6. **The 156x exec loop** -- ROOT-CAUSED + FIXED. His "bug in some core
   mechanism" was IBuilderTask::OnTravelEnd aborting BEFORE Execute (no
   site-fail, fails=0) on CanReachAtSafe, with a deterministic site
   re-elected into the veto forever. Fixed by feedback (NoteBuildBlocked
   + ProbedSite skip + plant/tech lanes probed). s106 rerun: plant exec
   loops 21 -> 2.
7. **Eco player AFK** -- FIXED BY #6, awaiting his eyes. t5 (the rear
   pocket): income 13.2 -> 114.6 m/s, factories 0 -> 3, worst commIdle
   36% -> 16%.
8. **Nano turret reclaim** -- LANDED + FIRING. C++: metal-full abort and
   metal-empty gate behind apex_nano_space_reclaim (default on; engine
   truth checked -- area reclaim eats features only, META_KEY not
   CONTROL_KEY takes units); CmdReclaimUnit bound; script NanoReclaimAssist
   piles idle nanos onto claimed reclaim victims (nano-assist x38 in s43).
9. **Eco cluster split** -- LANDED, AWAITING s44: big generators cap their
   cluster at half their standing fleet and part clusters by
   apex_blast_aisle (500).

ArmyTarget ally-share: CONFIRMED FIXED by him tonight ("our game
performances did a lot better") -- entry deleted per the lifecycle rule.

AFTER HIS WATCHED LOSS (2026-08-29 late, matches/20260829-045437) two
more mechanisms landed (commit d3fe925): AnyPlantInFlight serializes
plant STARTS at every tier (armlab+armhp had been elected 8 frames
apart), and feedRoom scales a constructor's priced gain by the hands
income can feed (armacv v=146 at 52 m/s income; more metal stood in
cons than in living army at his game's end). Audits: con-glut +
all-tier adv-plant-overlap (flags his loss 6x).

s46 (57.9m loss, the wave-6 validation) then localized what remains:
- Tower COMPLETION is fixed (47 towers finished, 4 bt=7 deaths all
  game) -- the front-towers flag now measures SITING only: elections
  win front sites, towers land rear/mid. That is the pending policy
  ruling (siting depth / escorts), not a bug.
- t0 spent 267,850 metal on T3 UNITS (vs 76k defence, 55k eco) while
  BARb massed cheaper and won -- the T3-pacing entry's prediction
  verbatim, at 2% waste. The spend PLUMBING is done; WHAT the overflow
  may buy mid-game is his reserved composition decision (affordability
  ramp on T3 unit bids: mass first, T3 from surplus).
- Audit gap CLOSED (860e8f0): plant-par waived logs + audit exemption.

BOTH RESERVED RULINGS TAKEN AND LANDED (2026-08-29, 860e8f0):
- T3 pacing: "Ramp T3 bids" -- apex_unit_afford_s (60s of income) fades
  every unit bid toward zero at the full bill, no tier table. Validated
  s47 (won): armyReal 124k/159k standing (vs 97k/0.4k in the s46 loss),
  T3 fielded only by 390-1055 m/s economies, overlap pairs 16 -> 2.
- Front towers: "Both" -- apex_def_setback (250) steps front sites back
  toward home inside tower range; escorts already cover tower builders
  (EscortShortfall counts every worker away from the farm). s47 landed
  its first standing front tower; a DEFENSIVE game or his watching is
  the real proof -- wins generate little front pressure to measure.

Open residue, this campaign:
- armmex unreach-safe churn (156-228/game): mex claims elected at spots
  the walker cannot safely reach. Correct refusals, wasteful elections --
  election-side threat pricing is the lever if it grows.
- s43 (a loss) abandoned 719 nanoframes vs 87-312 elsewhere -- a losing
  base abandons everything; do not read it as a regression without a
  same-outcome control.
- The task-die why= distribution is the family's instrument now; any new
  face shows up there first.
- armmakr (T1 converter) reclaim-rebuild loop, 11-16/game: the converter
  obsolete law eats makers the convert want then re-buys. Same shape the
  plant retire law had; needs its own waiver/window pass.
- Radar at the front still dies why=unreach-safe (sense-churn 290 execs
  for 29 radars) -- deliberately NOT exempted: walking a builder into
  fire for an unarmed radar is a real loss. If forward intel matters
  more than that, it is a pricing question.

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

## 2026-08-28 (late) — army TRADING, not army production, on the 15m tell

s103: apex mArmy 76.5k vs barb 77.5k (equal spend) but standing army
32.4k vs 40.3k -- we lose more of what we build. s104 reversed it (59.8k
vs 34.2k standing on equal spend), so it is seed-noisy; watch the pair on
every future tell before believing either direction. His "we aren't
making as much army" reads as TRADING variance at this horizon, not a
production deficit -- production and mArmy share track BARb.

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

## 2026-08-27 (late night) -- the commitment-ledger campaign, in flight

The approved velocity plan (plan file `okay-i-want-you-partitioned-toucan.md`,
summarized in the bar-ai-velocity-plan memory) is mid-execution. Session 1
(ledger plumbing + census fix) is landing now. Open halves:

- **Shadow reads accumulate until the flip.** ProtAnyComing/ProtCovered,
  SuperCensus, UnlocksProduct and reachKin each log `apex: ledger shadow`
  on disagreement with the ledger. Flip each to ledger-only ONLY when its
  shadow is clean across several games including one of his; a mismatching
  one flips as its own measured change. First smoke: shadow=0.
- **reachkin flip note (from seed-6 shadow data, 25 mismatches, all
  reachkin; the other three spellings were clean over two games)**: the
  persistent `old=1 new=0` arm is an UNMANNED held order gLive counts but
  the ledger's manned rule skips. For DUPLICATE-detection the flip must
  count unmanned same-def ORDERED rows too (a commitment is a commitment);
  the manned rule stays only for parallel-capacity counting. The `old=0
  new=1` arm is the walk window -- the ledger is right and the old read is
  the duplicate-lab hole.
- **armmex `why=unit-gone` drift, ~1/game, sweep-corrected in <=5s**: a
  framed mex vanished without its death event reaching the ledger. Under
  observation; if it grows, hunt the removal path (mexup replacement is the
  suspect).
- **Session 3 carries his headline ruling**: copy-plant wants price 0 (not
  discounted) with demand forwarded to nanos, plus the `apex: INVARIANT`
  door guard and audit-on-his-games observability (auto-audit + persisted
  audit.json + un-gating audit.py's income-sensitive checks).
- **decide.as:82-123 is unreachable dead code** (maketask.as:48-50 returns
  any held BUILDER task first, so the 0.01-progress hold and the whole
  gApproach* machinery never run; the effective hold is unconditional at any
  progress). Deletion scheduled Session 5 — do NOT build on it meanwhile.
- **The AA "interrupt the job" promise may be dead code's casualty.** The
  aaEmerg election hold-breaker in decide.as was unreachable (deleted
  Session 5); the maketask.as hold returns a working builder's task before
  any election, so aaEmerg only reorders FREE builders' elections. Whether
  a WORKING builder is ever interrupted for the first AA tower (his
  explicit ask) is unverified — check AA PANIC behavior in a game with
  enemy air while all builders are busy. If nothing interrupts, the fix is
  an explicit Abort like StallWatch's, not a revival of the dead hold.
- **gOwnCount immobile reads not yet routed through the ledger**
  (Session 5's optional half, consciously deferred): gOwnCount is correct
  now (WasFinished guard) and equivalence with ledger FINISHED is watched
  by the engine cross-check; wholesale rerouting of ~30 read sites is churn
  without a driving bug. Revisit if `enginediff` ever grows steadily.
- **`enginediff` in the ledger summary is log-only** — it counts
  ledger-vs-Def().count disagreement (gifts/captures legitimate); if it
  grows steadily in a game with no gifts, hunt a ledger writer hole.

## 2026-08-27 (night) -- open residue from the watch-list session

Fixes for the night's list are in CHANGES.md; these are the halves NOT yet
closed, each with its measurement:

- **The stock DLL stall-WAIT (pause) is now tunable-gated OFF but only
  smoke-validated.** `BuilderTask.cpp` Reevaluate answered an empty E bank by
  CmdWait-parking every non-energy builder in build range; parked units pull
  nothing, which is why the fleet "stands around" through a stall
  (apexearth: "Our units instead pause what they're doing and stand around
  doing nothing"). Gated behind `apex_stock_stall_wait` (default 0; the same
  call now actively releases a unit still holding a Wait). Closing
  measurement: his next watched Supreme Isthmus 1v1 -- during an e-stall,
  builders keep lathing and a basic solar goes down; nobody idles with a
  wait icon.
- **The stock DLL stall-abort is now tunable-gated OFF but unvalidated.** If
  heavy turrets still die unfinished with `apex_stock_stall_abort=0`, the
  next suspect is the same Reevaluate's reassignment path. Audit:
  `front-towers` + frame-waste by def.
- **Front-tower completion past the panic fix**: the DEF-panic claim and the
  600-elmo fold stop the same-frame task churn, but nothing yet proves a
  2,000-elmo walk to a front site completes. Audit: `front-towers`.
- **Wind/converter reclaim PACE** (apexearth: "the pace of reclaim is
  probably far too low"): the buy-side room rent stops the REMAKING; the
  standing stock still drains one obsolete-reclaim election at a time.
  If `t1-eco-with-afus` keeps flagging with rebuilds at zero, pace is the
  half to tune (apex_reclaim_amort / rez bias / more rezbots).
- **"Walk AROUND defenses" for colossi** is only as good as the existing
  charger risk-tier pathing; not re-measured. His eyes are the test.
- **Nano latency on POOR teams**: median 0.8m team-pooled hides the thin
  tail he watched (t0 owned 7 nanos at minute 40 vs t5's 148). The demand
  law scales with income by design; whether the floor for a working factory
  should be higher at low income is an OPEN pricing question, not wired.
- **8v8 pooled audit thresholds are first guesses** (nanos-standing,
  t1-eco-with-afus divide by team count crudely); tighten once two or three
  8v8 games exist.

## 2026-08-27 (evening) -- the churn session: root causes behind his complaint list

Evidence run: `matches/20260827-234730-...` (his own 16:47 Supreme Isthmus
+100% 1v1, 44 min, lost to BARb). What it showed, and what landed against
each. Every fix below is LANDED, NOT MEASURED -- `tools/audit.py` grew a
STRUCTURES / GEOMETRY / PERF section whose checks are the closing measurement
for each one; run it on his next game.

- **15 T2 bot labs, 12 T2 veh, 7 T2 air, 13 T1 veh built (144,510 metal into
  plants); 14 of the 15 armalabs died `built=1` ~30s after our own reclaim
  elections.** The loop: nanos won 1,350 elections and finished ZERO in 44
  minutes, so the build-power gap (`plantdup ... con=89`) could only be
  answered by duplicate labs; duplicates make each other "covered", reclaim
  retires one, plant re-buys. Landed: (1) ExecuteWant's orphan/frame adoption
  hoisted to the TOP for every static kind -- it sat below the early-return
  branches, so its WK_NANO and WK_TECH entries were dead code and mex, mexup,
  sense and protect never reached it at all (armrad 48, armmex 43, armmoho 35,
  armnanotc 24 orphans, none adopted); (2) `apex_dup_bp_subst` defaulted ON
  (the one bad game that turned it off predates nano completion); (3) a
  replant memory: a plant def we reclaimed on purpose prices at
  `apex_replant_discount` (0.15) for `apex_replant_window_s` (600s), noted at
  reclaim EXECUTION in execute.as. Audit: `reclaim-rebuild loop`,
  `plant-count`, `nanos-standing`.
- **31 metal storages (15,690m).** ProposeStore was gated on `gReclaimTarget`
  -- a global set by every reclaim PROPOSAL, so the lab churn kept it armed
  forever. His ruling "Stop making storage" -- ProposeStore now proposes
  nothing; the global and `TUNE_STORE_HORIZON` are deleted. Audit:
  `no-storage`.
- **Fusion/AFUS before mex upgrades.** `GetMexSpotIncome` returns the MAP's
  raw spot income with no handicap anywhere in CircuitAI, while energy prices
  off real (doubled) income and pull -- at his +100% every extraction gain
  read HALF its true value. `dev_team_income.lua` already published
  `ai_handicap_<team>`; `IncomeMult()` (ledger.as) now multiplies the five
  extraction read sites (UpDemand, mexup delta, PickSpot, ProposeMex gain,
  protect stake). Hosted games without the gadget read 1 and price as before.
  Audit: existing mexup checks + t2Mex.
- **2,069 sense elections, 33 radars finished, 84 radar frames died.** Radar
  gap sites are now vetoed past the front and on hot ground (same rule as
  every other static build); orphan adoption finishes the frames. The
  wealth-scaled insurance gain `(assets+army)*rate*unseen` is UNTOUCHED and
  still suspect -- if `sense-churn` keeps flagging, price is the next lever.
- **band=R in every frontline line** -- the near-enemy trim was still inert
  (`apex_front_band_frac` 1.0 = a +/-90 degree arc; front 45-52% of
  perimeter all game). Defaulted to 0.35 (+/-49 degrees). The ISSUES caution
  about closeMine predates territory being stamped from structures. Audit:
  `front-band`.
- **0 front towers finished all game vs 27 rear (rimDAvg -1366).** Not
  directly fixed; adoption + radar vetoes should help the con-death half
  (220 cons lost vs their 85). Audit: `front-towers` -- if it still flags,
  the walk distance to front sites is the next suspect.
- **28% of the game's wall clock inside hk.maketask.builder (194s of 686s,
  single calls to 69ms).** The defence site auction (prot.loop, 61s) now
  fills a per-def cache at most every 2s (DefSiteFill; arithmetic unchanged,
  the election keeps only the walk-weighted argmax); StreamSurvival memoized
  on a 256-elmo/3s grid. Totals fell (194s -> 37-56s per game) but a SINGLE
  ELECTION still spikes: `exec.want` (new timer around ExecuteWant) hit 271ms
  then 424ms in the validation games -- something inside execution, not
  pricing. The nano `FindBuildSiteNear` probe is instrumented separately
  (`exec.nanoprobe`) to convict or clear it; if it is not the probe, suspect
  the Requests::Take scan chain. Audit: `ai-time`.
- **The decide line lies about execution** -- it prints the drawn ranked[0]
  even when the executor refuses it and the runner-up runs. New
  `apex: exec t=.. kind:def pick=N` line records what actually became a task;
  the new audit checks count THOSE. Also fixed: the `duplicate line over
  nanos` audit regex never matched the real plantdup line (dead check).

Known-NOT-addressed from the same complaint list, still open below/elsewhere:
the strategic market buying the cheapest LRPC (want_super affordability
pricing), the grid's 42% touching (`grid-tightness` now measures it; the
`apex: base` module logs all zeros -- one of the two placement systems is
dead and needs its own session), and the sense insurance price itself.

## 2026-08-27 -- the stall answer is too SMALL, and serializing it is not why

apexearth, watching: "when we run out of energy we'll make 1 or 2 more wind...
and we keep running out of energy."

The obvious suspect was the request fold -- energy asks join one standing
request unless the bank overflows, and during a stall it never does, so a
300/s deficit is answered 35/s at a time. Opening parallel sites while ordered
generation fails to cover the shortfall was tried and MEASURED WORSE, three
paired 20-minute Carrot Mountains seeds, medians:

    parallel OFF   built 25,500   mex 42   eStall 444
    parallel ON    built 19,555   mex 33   eStall 352

It buys the smaller stall with a quarter of the economy, by splitting build
power across several frames at once -- the same thing this AI penalises a
second lab for, and against his own rule to "focus as much build power as we
can on just the one building". `apex_e_parallel` is defaulted OFF. The fold is
that focus rule working; it is not the bug.

**So the complaint is unexplained.** If one generator at a time is right, the
answer to a large deficit is a BIGGER generator, and the question is why the
market keeps picking small ones. `apex_inferior_discount` already scales a
generator's gain by its energy-per-metal against the best one we could build
(`want_energy.as`, OwnedBestEPerM) -- it is supposed to do exactly this job.
Either it is not biting at the moment the stall lands, or the gain
`gMakeE * EPriceAt(bSec)` favours the cheap fast build through the build-time
term. Not investigated.

Worth carrying into that investigation: of the energy-side changes tried this
session, the ACCOUNTING fixes survived measurement (counting committed draw,
counting in-flight lines) and every attempt to change POLICY did not (parallel
sites; the 2.79x mex-upgrade boost). Suspect the model, not the ordering.


## 2026-08-27 -- "always be expanding the economy" HAS BEEN LOST AGAIN

`grep -rn "always_eco\|AlwaysEco" ai/` returns NOTHING, in any variant. The
rule apexearth set early, lost once, and had restored on 2026-08-21 -- with
the explicit instruction "treat any future gate that can silence ALL eco lanes
at once as a violation of this rule" -- did not survive the Brain overhaul.
USER-FEEDBACK.md still documents it as a STANDING RULE.

What that looks like in a game, Carrot Mountains, Cortex, from the opening
decision trace:

    f=25    mex        v=210   (over produce/plant v=28)
    f=313   LLT        v=21    at walk=119, on a mex
    f=633   mex        v=59
    f=873   mex        v=31
    f=1289  lab        v=39    (mex had finally decayed to v=14)
    f=2185  FIRST ENERGY, 73 seconds in

By minute 2 the economy pulls 114 energy against 45 income, and `eStall`
climbs from there for the rest of the game. apexearth, watching: "we are
walking out to make a mex and a turret far away before we even make our first
lab... when we run out of energy we need to do the e-stall logic to make
energy. but it seems like these mechanisms are just stepping on each other."

They are, and this is the order: nothing buys energy in the opening, so the
stall machinery runs permanently, and the stall's answer is to ABORT a
builder's task -- which is where the 890 abandoned nanoframes come from. The
stall interrupt is now much cheaper (it takes a walker before anyone
mid-build, measured 69 of 74) and abandoned frames are adopted rather than
re-founded, but both are treatments. The cause is that energy is never bought
until it is already too late.

The fix is NOT another ladder rule -- the overhaul mandate says every build is
a priced Want. It is that energy's value must not be able to read ~zero while
nothing energy-side is in flight. That is a design decision about the eco
pricing and has not been made.


## 2026-08-27 -- 890 nanoframes abandoned in one game, and nothing adopts them

`tools/audit.py`'s new "finish before founding" check, first run: **890**
abandoned nanoframes in one 60-minute Carrot Mountains game, 32 defs abandoned
more than once -- cormex 206, cornanotc 144, corrad 86, cormoho 78.

apexearth reported the visible tip of it: "when we e-stall we think to do
something else... instead of choosing to finish the original lab afterwards we
just start making a new one." The plant half is FIXED (WK_PLANT and WK_TECH
were missing from the position-independent orphan adoption in execute.as, and
an abort leaves a frame with no request at all, which now redirects the new
request onto the frame). The other 800 are not, and this is the same metal as
the standing "27-45% of everything we lose dies as an unfinished nanoframe"
entry -- they are one problem seen from two ends.

## 2026-08-27 -- boosting mex-upgrade priority makes FEWER mex upgrades

apexearth: "We need to boost the priority on building upgraded metal
extractors." The audit measured the gap precisely -- of 10,139 decisions by
cons that could upgrade a mex, 505 (5%) were upgrades, and 785 times an
upgrade ranked second and lost, 394 of those to energy at a median value ratio
of 2.79.

Setting `apex_mexup_boost` to that measured 2.79 does exactly what it says and
is WORSE: upgrades rise to 33% of advanced-con decisions and become the
most-chosen want, while upgrades actually standing fall 94 -> 69, mexes held
243 -> 182, metal built 863k -> 358k and income 1001 -> 377. It displaces the
energy that pays for expansion, so fewer mexes exist to upgrade.

Left at 1. The open question is the one this does not answer: whether energy is
overpriced against extraction, which would be a fix to energy's gain rather
than a thumb on extraction's. One game per arm, so treat the direction only.

**And a warning about the audit itself:** the "advanced cons upgrade mexes"
check went GREEN in the arm that performed worse. A decision share is not an
outcome; read it against t2Mex.


## 2026-08-27 -- the strategic market buys whatever is CHEAPEST, and that is the LRPC

apexearth, watching: "I see we make the LRPC cannons - but those are not great
for defense, they're more like long range offense."

`ProposeSuper` prices every strategic structure as AFFORDABILITY:
`gain = EcoPowerM * share * (budget - bill) / budget`. That term falls as cost
rises, so the cheapest member of the list wins the CAT_SUPER ticket every time,
whatever it does. Confirmed on Carrot Mountains: `apex: super fire corint` --
an Intimidator, at 246 super elections in one game.

The file's own comment already identifies this defect and fixed it for ONE
class: the gantry was given a real return (overflow + the army gap its
products fill) precisely because affordability "rewards being CHEAP". The same
correction was never made for the LRPC, the silo, or the anti-nuke, so three of
the five classes are still bought for being affordable rather than for what
they do.

NOT the reason heavy turrets lose, and worth saying so: `CoverWith` sums only
`gProtPos[PROT_DEF]`, so an LRPC is never credited as base cover and never
suppresses a real turret. It is a separate category with its own ticket. What
it costs is metal and constructor time.

An LRPC's honest return is the enemy metal it destroys at range without
exposure. Pricing it that way is a four-class job and was deliberately not
bundled into the defence session.

## 2026-08-27 -- we never reach T3 at all, at 880 metal/s

Carrot Mountains, 60 minutes, Cortex self-play: 959,380 metal built, 880
metal/s income, 218 mexes -- and `mT3 = 0`. The word "gantry" appears NINE
times in the whole infolog. No gantry means no T3 units, which is a different
problem from the T3 DEFENCES (cordoom/armanni need only an advanced
constructor, no gantry).

Also from that game, unexamined and large: `buildpower/nano` won **10,291**
elections, more than every other want combined, against `metal/mex` 349 and
`metal/mexup` 380. `cornanotc` was historically the single largest metal sink
in this AI and this looks like the same shape returning.


## 2026-08-27 -- static defence share jumped 7% -> 13-23% and is UNTUNED

`apex_def_eco_s` (30 seconds of EcoPowerM) is the whole size of the standing
defence holding since DefenceTarget was rebased on the economy. It was chosen
to let one heavy gun clear at hosted-game income, not derived.

Measured consequence: defence share of metal built 7.1% -> 13.4% against
BARb, and **22.6% in self-play**, where `armguard` at 15,000 metal was the
single largest sink in the game -- larger than fusions, larger than any unit.
That is the same shape as the old `cornanotc` finding. Three Pulsars and a Big
Bertha also appear, which is the thing that was asked for, so this is a real
trade and not obviously wrong -- but nobody has measured where the number
should sit.

Attributed, by reading defence share off each step's own run: the site
wave-threat floor did NOT do it (8.1%, inside the 7.1-9.4% baseline range);
the target rebase did (13.4%).

**`apex_def_eco_s` is only half the knob.** A/B at 30s vs 10s over four seeds
moved defence share 14.2% -> 13.3%, i.e. barely, because `DefenceTarget` takes
the MAX of the economic hold and the per-mex floor -- and with 27-47 mexes the
floor is the binding term at both settings. Anyone tuning defence down has to
move `apex_mex_cover_floor` as well, or nothing happens. (Those four seeds
also showed built 37.8k -> 65.4k and mex 24 -> 30 at 10s, but two of the 30s
games collapsed early and this bench cannot resolve that at n=4.)

## 2026-08-27 -- the enemy-tier fade has never actually fired on T3

`apex: foetier` reads `t3=0` in every game measured: BARb fields no T3 on this
bench and self-play did not reach it in 44 minutes. The T1 half works (T1
share of unit metal, median 45.9% -> 33.0% over three paired seeds), but the
half apexearth asked for -- fewer T2 units and labs when the enemy has T3 --
is wired and unobserved. It also learns only from the two death hooks, so it
reads zero until we meet them; there is no per-def enemy enumeration binding
to fix that without a DLL change.

## 2026-08-27 -- front-line towers are still barely built

The new `apex: fronttowers` counter says what `defsite` could not: over an
18.7-minute 1v1, 104 defence wants were WON at front sites and **zero towers
finished there**. Later runs reach 1-4. Every other defence structure lands
behind the line. Front sites are proposed constantly and almost never become a
standing gun -- builder killed, site blocked, or re-elected away mid-walk
(walks of 700-3,400 elmos are logged). Not investigated.


## 2026-08-26 (2) -- front line FIXED; defence mix improved; win rate did not move

Five paired 54-game runs, same three small 1v1 maps (Altair Crossing, Red Comet,
Avalanche), Apex vs BARb:stable:hard, 30 min cap.

| run | head-to-head | front-geometry fires | Agitator share of defence metal | quick turrets |
|---|---|---|---|---|
| baseline | 3-21 | 26/54 | 32% | 48% |
| plant fix | 2-18 | 28/54 | 27% | 62% |
| front fix | 1-23 | **0/54** | 33% | 55% |
| + TTD (absolute) | 1-23 | 0/54 | **24%** | 57% |
| + TTD (normalised) | 0-27 | 3/54 | 38% | 46% |

**The front line is fixed.** `frontline.as` now stamps territory from our own
buildings (`ai.GetOwnStructsNear`, already bound -- no DLL rebuild) instead of
from the influence map, which fed mobile army into it. TerritoryRadius fell
2673 -> ~1000 (a real base rather than most of the map), `ourMid` is stable, the
front/back split went from front~=back to 19 front against 87 back, and the
band trim became active for the first time. The `front-geometry` check fires in
**0 of 54** games, from 26.

**TTD works, in its absolute form.** A defence's gain is discounted by
`H/(H+buildSec)` (`apex_def_ttd_h`, default 120 s = the same window
`apex_exposed_loss_s` uses). Agitator share of defence metal 32% -> 24%,
Dragon's Maw +46%, Warden +47%.

**Normalising it BACKFIRED and is reverted.** Dividing every defence by the
quickest buildable turret's multiplier -- so the category paid no tax and only
the internal ordering moved -- raised defence share (def/built 0.077 -> 0.089)
but bought MORE Agitators, not fewer (24% -> 38%). The within-defence ordering
is mathematically unchanged by a common factor, so this is a second-order effect
of defence winning more auctions overall; not chased further.

**Win rate did not improve and this benchmark cannot resolve it.** 3-21, 2-18,
1-23, 1-23, 0-27 across ~24 decided games each: every interval overlaps, and
CLAUDE.md already records this bench swinging 60% -> 10% on an unchanged AI. We
lose ~90% of these games in every configuration. Judge these changes on the
composition columns, which are the same answer in every game; do not read the
head-to-head column as a ranking.

**CORRECTION to the 2026-08-26 frame-waste entry:** the per-game "e.g." lines
printed by `diagnose.py --agg` are the FIRST game of the run, not a summary.
Reading them as a trend suggested nanoframe waste fell 45% -> 29% across these
runs. Pooled over all 54 games it did not: 27%, 30%, 31%, 34%, 33%. Nanoframe
waste is unchanged. Always pool before claiming a trend.


## 2026-08-26 -- the front line is drawn through enemy territory

apexearth, watching: "During my games I see lines drawn through enemy
territory. Is that where we think the frontline is?" It is, and it is wrong.

`tools/diagnose.py` reports it over any run. Measured over 54 paired 1v1 games
on three small maps, and again over a 10-game Comet Catcher set: the mean FRONT
edge sits at **0.87-0.96 of the distance from our own territory centroid to the
enemy's**, and in 33% of samples it is PAST their centroid entirely (max 3.15x).

Mechanism, `manager/frontline.as`:

1. **The near-them trim never trims.** `FrontBand()` is
   `TerritoryRadius() * apex_front_band_frac`, and `apex_front_band_frac` is
   **1.0**, so the band equals the mean radius of our whole perimeter -- larger
   than the distance to the enemy in **97% of samples**. The trim at line 352
   (`dist(cell, foeMid) > ref + band -> BACK`) therefore demotes nothing, and
   every enemy-facing perimeter cell is FRONT regardless of how far back it is.
2. **Territory follows the army, not our holdings.** `ours[]` (line ~236) is
   `av >= gPresAlly && av > fv` where `av` is `GetAllyInflAt`, and CircuitAI's
   `CInfluenceMap::Apply` feeds that from `AddMobileArmed` as well as
   structures. `TERRITORY_FRAC` is **0.03** -- three percent of peak ally
   influence counts as ours -- against `FOE_FRAC` **0.10** for theirs. The
   asymmetry plus mobile influence paints ground our army is merely standing on
   as our territory. Centroids fully collapse in only 2% of samples, so this is
   secondary to (1), but it is why our territory radius exceeds the distance to
   the enemy at all.

Everything downstream inherits it: `Military::LanePos()` (where the army is told
to stage), `Builder::PastFront()` (the eco veto), and defence siting. Consistent
with `deep-deaths` firing in 32/54 games -- 41-56% of army metal dying past the
halfway line.

**Not yet fixed.** `apex_front_band_frac` is already a tunable and already in
`dev_tunables.lua`, so the trim can be tightened with a modoption and no code
change; `TERRITORY_FRAC` is a bare const and would need one adding. Untested
either way -- tightening the band alone may make it WORSE, because the trim is
relative to `closeMine`, the closest front cell to the enemy: if that cell is
one our army is standing on inside their base, a tight band keeps only cells
near THAT and discards our real border.

## 2026-08-26 -- 27-45% of everything we lose dies as an unfinished nanoframe

`tools/diagnose.py`'s `frame-waste` check fires in **54/54** games. Pooled over
that run, 235,962 of 877,704 metal lost (27%) died before the building finished;
per-game the median share is 45%. By def, share of that def's losses that were
still nanoframes:

    corfus     58500m over 13   100%      corfmd     9000m over  6  100%
    corpun     22100m over 17    94%      cortoast   7500m over  3  100%
    coralab    20300m over  7    58%      corhlt     4320m over  9  100%
    corgeo     15660m over 29    71%      cormoho   14080m over 22   81%

`corpun` is the Agitator, 1300 metal against a light tower's ~450, and it is
apexearth's own report: "I see us trying to make Gauntlet defense a lot... it
takes too long to build and enemies usually shut down the build attempt."

Cause identified: `decide.as` charged `ExpectedLossAt` only to NON-protect
wants, and never scaled it by how long the thing spends as a defenceless frame.
So build duration carried no risk at all, and defence carried none whatsoever.

**A fix was implemented, measured, and priced out.** `apex_frame_risk` charges
`exposed * buildSec / apex_exposed_loss_s` to every want including protect.
At 1.0 it made things clearly worse -- head-to-head 3-21 -> **0-30**, total
metal built 38.6k -> 17.6k -- because the charge is a whole standing
expected-loss multiplied by buildSec/120, which for a several-hundred-second
structure exceeds the want's entire gain. It suppresses building instead of
reordering it. **Default is now 0** (mechanism wired, inert). Likely
precondition: a hazard field that is not saturated everywhere, which is the
front-geometry entry above.

## 2026-08-26 -- defence share does not respond to its own price

def/built is **0.071-0.095 against stock BARb's 0.210-0.237** in every run
measured, alongside kill/loss **0.30-0.35 against their 1.23-1.46**. This is the
same gap recorded on 2026-08-24 and it has not moved.

Raising `apex_def_trade` from 3 to 8 -- nearly tripling the metal a turret is
credited with stopping -- moved def/built only **0.071 -> 0.087** and cut total
metal built from 38.8k to 22.4k (54 paired games). **Defence is not gated by its
price in the auction.** Whatever holds it down is upstream of the credit: the
category lottery, or a protect gain that reads near-zero because observed threat
is zero at a position nobody has attacked yet. Do not sweep `apex_def_trade`
again without first establishing which.


## STATUS 2026-08-25 -- read this first

### CORRECTION: the compounding argument for apex_payback_h does NOT hold

Claimed to apexearth and written into a commit message: at 300 build power the
advsol+converter route compounds as I(t)=I0*e^(t/371), giving 19.3x income over
the 1097 s an afus takes, against the afus's 3.1x. A Fable review checked it and
the raw numbers are right (corafus 9700/329200/3000E; coradvsol 370/8150/75E;
cormakr 1/2680/70->1; BuildSecondsAt = buildtime/BP) but the model is wrong:

- The exponential ignores BUILD POWER, which the increments saturate at once.
  One increment is 10,830 buildtime units, so 300 BP adds at most 0.028 m/s per
  second. dI/dt = I/371 exceeds that above I = 10.3 m/s, and the 3.1x figure
  implies I0 = 20.5 -- above the cap from t=0. The increment route is therefore
  LATHE-bound and LINEAR: +30 m/s over 1097 s, about 2.5x, which LOSES to the
  afus's 3.1x.
- The 371 s constant omits the increment's energy bill (5250 E ~ 75 metal at the
  70:1 floor); with it the constant is ~446. Per unit of rate the afus is
  actually cheaper in energy, widening its per-metal advantage.

apex_payback_h is KEPT: "a rate that has not started is not income" is sound on
its own, and the term self-corrects on build power and income. But the SIZE of
the discount was never derived and the arithmetic offered for it was wrong. It
is an unmeasured tunable, not a proven number.


A sweep of everything below, because entries were accumulating faster than they
were being closed (apexearth: "sometimes I don't notice when you defer things or
add to ISSUES.md - we should take some time to see what is unsettled").

**Closed by measurement today; the entries below them are stale:**

- *"every T2 lab is bought by a want the arbiter priced 6-17x too low"* -- this
  was the category draw weighting tickets by raw value. Measured at 34% of all
  elections taking a lower-valued want, worst case a mex at 594 losing to a wind
  generator at 99. The draw now goes as `(value/leader)^apex_draw_sharp`.
- *"we barely build defence at all"* / *"the outstanding gap: static defence"* --
  was 3.5-5.1% against BARb's 17-18%. After SiegeRisk was wired into the protect
  gain: defence at minute 10 **360 vs their 135**, at minute 15 **1050 vs 818**,
  ahead of stock early for the first time. Still behind at minute 25 (3232 vs
  4150), so this narrows rather than closes.
- *"threat magnitude is still too low at home"* -- SiegeRisk gives home a threat
  that does not depend on seeing anything.
- *"unscouted still reads as safe outside the tech price"* -- the siege prior now
  reaches energy and defence, not tech alone. Fixed as PRICING; scouting itself
  is still untouched, see below.

**Still open, in the order they now matter:**

1. **`conT2` is 0.** Median peak T2 constructors across 24 paired games is zero,
   which is why `t2Mex` is also always zero, and why apexearth's report that "all
   our T2 cons are going for a fusion" cannot be reproduced on this benchmark at
   all -- there are no T2 cons to misdirect. Everything downstream of T2 (mex
   upgrades, the quadrupled yield the math was just changed to respect) is
   unreachable here. This is now the top blocker.
2. **We never scout.** `Military::EnemyArmyCost()` reads 0 for entire games while
   the enemy fields thousands of metal. SiegeRisk routes PRICING around it, but
   `ArmyTarget`, the commander's engage test and AA still read a zero, and
   nothing raises scout production when intel is stale.
3. **Late army collapses.** Early army is now near parity (ratio 0.72 at minute
   10, 0.59 at 15, after the coverage term) and falls to **0.21 by minute 25**.
   Economy is at parity throughout, so this is production and trade, not income.
4. **A cheap want that needs a walk can never complete** -- 38 radar decides, a
   live request, zero radars built; re-election abandons the approach.
5. **Duplicate plants** -- `ProposePlant` dedups on FINISHED plants only, and the
   tech want's mobility channel buys a second same-tier plant on speed alone.
6. **The displacement charge exempts the builds that displace most** -- it fires
   only inside `if (feedSec > buildSec)`, so a def with a huge buildtime never
   pays it. The eco survival discount narrows this without closing it; it is the
   remaining half of apexearth's AFUS build-power point.
7. **Air work is unmeasurable here** (`AIR_MIN_INCOME` 40 m/s vs ~22 on bench).

**Unresolved judgement call:** `EcoPowerM` reads as a mild drag on Altair across
two independent 12-game batches, and is kept anyway because without it there is a
total bootstrap deadlock on maps with no metal spots (1 builder, 0 factories, 0
army for a whole game). Not a measured win -- a chosen trade.


Restarted 2026-08-24. The previous file (1,767 lines) was written almost
entirely before the Brain overhaul of 2026-08-22/23 and described leaf-era
mechanisms that no longer exist. Recover it with `git show HEAD:ISSUES.md` if
an old entry turns out to matter.

**Rule for this file:** every entry names the run it came from and the log line
that shows it. No entry survives on reasoning alone. Delete an entry once a
measurement confirms the fix — not when the fix lands.

Evidence below is from `matches/20260824-021933-...` (4-team, Altair, "before")
and `matches/20260824-024703-...` (1v1, Altair, "after the category change").
These are different setups, so treat magnitudes as indicative and the log lines
as the real evidence.

---

## OPEN: every T2 lab is bought by a want the arbiter priced 6-17x too low

The category draw in `market/decide.as` gives `produce` one ticket per
election. When that ticket wins, the drawn want is bought regardless of how
far below the best want it was priced.

```
f=13865  produce/tech:armalab  v=5.94  over buildpower/assist v=33.97   ( 5.7x)
f=16977  produce/tech:armalab  v=3.44  over energy/energy     v=44.03   (12.8x)
f=23273  produce/tech:armalab  v=5.16  over energy/energy     v=88.84   (17.2x)
```

All three landed before the first mex upgrade (f=30217). Same shape in the
before-run: `coralab v=6.09 over 17.75`, `coravp v=0.58 over 8.66`,
`armalab v=1.46 over 5.43` — three of the four tech decides were upsets.

The stakes are asymmetric and the ticket does not know it. Losing a wind draw
costs 43 metal and 15 builder-seconds; winning a lab draw commits 2,900 metal
and then `JoinBig` pulls the fleet onto it for minutes. Overall upset rate
(winner priced below the runner-up) is 91/295 decides.

The draw itself is deliberate — winner-takes-all previously starved every want
that never ranked first. What is missing is any relationship between ticket
size and how irreversible the purchase is.

## OPEN: the overhaul kill removed 23,511 lines; some of it has no replacement

`fcbabf2` ("Overhaul kill") deleted 23,511 lines across 77 files, 26 of them
entirely. Most was correctly superseded by the Brain market -- `statics.as`,
`nano.as`, `fusion.as`, `converter.as`, `assist.as` all have `want_*` successors.
Three areas do NOT:

**Nukes -- RESTORED 2026-08-24.** `manager/brain/nukes.as` (536 lines) is back
verbatim from `fcbabf2^`; it had only three external dependencies
(`Builder::gHomePos`, `Factory::T`, `Military::ForwardFraction`), all still
present. `Brain::UpdateNukes()` is wired into `AiUpdate` and
`Brain::NoteSiloFinished` into `AiUnitFinished`, matching the pre-kill call
sites. 17 `TUNE_NUKE_*`/`TUNE_ANTI_COVER` consts restored with pre-kill
defaults (`TUNE_BRAIN_NUKE` already existed -- a duplicate const is a
`Name conflict` that disables the whole variant, caught in smoke test).
Compile-clean over a 21-minute game. NOT EXERCISED: a 1v1 at this income never
reaches a silo, so the director ran dormant. Validation needs a long,
high-income game.

**Commander safety -- gone.** See the entry above.

**Air eco-assassination -- doctrine REPRICED 2026-08-24, production still
ORPHANED.** apexearth 2026-08-24 on what this is for: "we build up a sufficient
airforce to do a raid and try to kill enemy home base economy (ie blow up their
AFUS to cause a huge chain reaction)."

Surviving (905 lines in `manager/air/`): the doctrine and its gates in
`air/state.as` (`AIR_FROM` 11 min, `AIR_MIN_INCOME` 40, `AIR_AA_CEILING` 2500,
`ScaledBombers()` scaling the strike with income), the per-ally-team election in
`air/election.as`, and `update.as`/`wing.as`/`station.as`.

Deleted and not replaced: `manager/air/factory.as` -- `NextAirDef`,
`EnqueueBatch`, `MakeFactoryTask`, the code that actually queued the bombers --
and `manager/factory/airsupport.as`.

The break is total, and verified two ways:
- `grep` for `ScaledBombers|gAssassin|IsAssassin` outside `manager/air/`
  returns NOTHING. No consumer reads the assassin's demand.
- `grep -niE "air|bomber|fighter"` over `manager/brain/facqueue.as`, which now
  owns ALL factory production, returns one unrelated comment.

So the assassin can be elected and then nothing builds its airforce. Note also
that the election never fires on the standard benchmark: the log reads
`no air assassin, best ally income 22/40` -- `AIR_MIN_INCOME` is deliberately
above benchmark income, so this can only be judged in a hosted game.

**Landed 2026-08-24** (compile-clean, 22.7-minute game):
- `AIR_AA_CEILING` is no longer a veto. apexearth: "if there is AA we can still
  sometimes overwhelm them... 50 or 100 bombers coming in from different angles,
  some will likely get through." `Armed()` and the mid-buildup abort now consult
  `StrikeWorth()`; AA enters as a price, never a wall.
- `EcoDensity()` -- enemy cost sampled in one cluster radius around their
  centroid, the proxy for how packed their base is.
- `Throughput(n)` -- wing HEALTH soaks AA, so mass dilutes it: `soak/(soak+aa)`,
  never zero.
- `ScaledBombers()` grows with enemy AA and lost its flat `AIR_BOMBERS_MAX` cap.
- Heavy bomber tier `gBomberH` added to the election, which previously could not
  reach it at all: `corcrwh` Dragon (16,700 hp / 5,100 m), `legfort` Tyrannus
  (16,700 / 5,600), `armblade` Hornet (3,000 / 1,250).
  **`corcrw` is built by NOBODY** -- it is the legacy twin of the buildable
  `corcrwh`, identical stats, and requesting it would have been silently
  dropped. Caught by `tools/unitdef.py corcrw --builders`; check every new def
  that way.
- Atomic bomber tier `gBomberN`: `armliche` Liche (2,300 hp / 2,200 m),
  Armada only -- Cortex and Legion have no atomic bomber and get the heavy hull
  instead. apexearth: "light bombers are the best choice for Armada oftentimes.
  Nuke bombers can get thrown into the mix too - sometimes that's a huge pain
  for players to deal with a mix of threats." The mix needs no special term: the
  production draw is proportional, not winner-take-all, so every tier carrying
  positive gain gets bought in proportion to it.
- `Bombers()` now counts all four tiers. It counted only the original two, which
  would have left the wing permanently short of `ScaledBombers()` and never
  reading as massed.

**Armada has no true heavy** -- a real faction asymmetry, and the reason its mix
is light bombers plus Liches rather than Dragons.

**Production wired 2026-08-24.** `Air::StrikeGainFor(def, fillSec)` prices one
more bomber of a given type against the whole raid that type would need, and
`Market::ConOrderFor` enters it as an ordinary candidate in the proportional
draw. Not a gate: a raid that does not pay returns zero gain and the line builds
army as before.

**RESOLVED by measurement, not by modelling.** The HP-soak prior ranks cheap
bombers above heavies: Worked at 8k enemy AA, 40k eco density:

| | needed | throughput | strike cost | return on cost |
|---|---|---|---|---|
| Archaic Dragon (16,700 hp, 5,100 m) | ~20 | 0.70 | 102,000 | 0.27 |
| Hailstorm (1,520 hp, 310 m) | ~120 | 0.53 | 37,200 | **0.57** |

Light bombers win because BAR prices hp/metal in their favour (4.9 vs 3.27), and
`dmg = EcoDensity x Throughput` caps damage at what the cluster holds regardless
of who delivers it -- so cheap mass always looks better. apexearth's read is the
opposite: "20 of those and the enemy will definitely have a hard time."

That prior is CORRECT as a prior. apexearth: "I would certainly try a hailstorm
bombing run first... they're also faster moving. If you were able to gauge the
success of a bombing run then that tells you if hailstorms are viable. Sometimes
you don't know until you try."

So the fix is a feedback loop, not a better guess. `NoteStrikeLaunched()` records
the type, the count sent and the target cluster's value; `SettleStrike()` scores
the run `apex_air_settle_s` (90s) later from the drop in cluster value and how
many bombers came home, and EMAs both into `gObsSurv`/`gObsDmg` per def.
`Throughput()` and `StrikeGainFor()` prefer the measured numbers over the prior
the moment a type has been scored once -- so flak splash, interception and the
flight home are all counted without any of them being modelled.

The behaviour that falls out is the one described: fly a cheap Hailstorm probe
first, and if it dies for nothing, its measured survival collapses and Dragons
win the next draw. Log line: `apex: air run scored def=... sent=... home=...
surv=... dmg/bomber=...`.

Both estimates are crude -- the cluster also loses units to our ground army, and
reinforcements refill it -- which is why they smooth rather than replace.

**102 tunables in `tunables.as` now document files that do not exist:**

| dead file | orphaned tunables |
|---|---|
| mexguard.as | 21 |
| statics.as | 19 |
| nukes.as | 18 |
| assist.as | 9 |
| nano.as | 8 |
| obsolete.as | 8 |
| fusion.as | 7 |
| rules_commander.as | 6 |
| converter.as | 5 |
| crew.as | 1 |

This matters more than dead code usually would: `tunables.as` exists BECAUSE
apexearth asked for one file he could tweak without asking (its own header says
so). ~102 of its entries are knobs that now change nothing, with comments
confidently describing behaviour that was deleted. Either the readers come back
or the entries go.

Recovery is `git show d95e06e:<path>` -- the pre-kill tree is intact in history.

## LANDED 2026-08-24, benchmark CANNOT validate it: commander self-preservation restored

apexearth 2026-08-24, watching: "our commander was getting shot by enemies and
he did *nothing* to protect himself."

He is right that nothing runs. The cause is NOT that it was never written --
it was written, evolved over several commits, and deleted with the rest of the
leaf rules in `fcbabf2` ("Overhaul kill"). `ai/ord/.../builder/rules_commander.as`
at `d95e06e` carries three working behaviours, none of them ported to the Brain:

1. **Health retreat** -- below `COM_RETREAT_HEALTH`, and only while
   `ThreatFor(here) > CON_THREAT_VETO`, call `aiBuilderMgr.EnqueueRetreat()`.
   The local-threat condition exists because firing on health alone left him
   "cowering at the back at 50% health" (apexearth, watched); once safe it falls
   through to the DLL's own `MakeCommPeaceTask`/`MakeCommDangerTask`.
2. **Back-wall hide** -- on `BaseUnderAttack()`, relocate by taking a job at
   `RearPos` (a solar), or `EnqueueRetreat()` outright when energy is full.
3. **Abandon a hot site** -- if the held task's build position reads
   `ThreatFor > CON_THREAT_VETO`, retreat instead of standing there building.

**The safe primitive is `aiBuilderMgr.EnqueueRetreat()`, NOT `CmdMoveTo`.** The
original `UpdateCommanderSafety` used `CmdMoveTo` and "correlated with 14-17
engine aborts per 20-game run"; it was replaced for that reason, and the
commented-out call at `posture.as:628` is the corpse of that FIRST version, not
of the working one. Do not read that comment as "retreat crashes the engine".

Current state, verified by direct search of the whole `ai/Unstable` tree:

- `manager/military/posture.as:628` -- the only commander safety hook is a
  COMMENTED-OUT call: `// Builder::UpdateCommanderSafety();`, with the note
  "DISABLED: engine aborts (exit -1003) jumped sharply the moment this landed.
  Either CmdMoveTo issued outside a task context or GetEnemyCostAt's
  GetEnemyUnitsIn walk is unsafe here." Grepping the tree for that symbol
  returns ONLY this commented line -- no definition exists anywhere. There is
  nothing to re-enable.
- `misc/commander.as` -- `Commander::UpdateCaution()` runs every tick but is
  telemetry only: it sets `gCautious` and logs it. `gCautious` is written at
  lines 29/36/37 and read at line 52 (the log string). Nothing acts on it.
- `misc/commander.as:196+` -- the entire `Hide` namespace (threat/air-based
  hiding) is inside a `/* */` block comment and is not compiled.
- `tunables.as` documents a commander retreat health fraction, a force-march
  clock and a hiding ring, all attributed to `manager/builder/rules_commander.as`
  -- a file that does not exist in this variant. Orphaned documentation for
  logic deleted in the Brain overhaul and never ported.
- The one surviving commander rule (`market/decide.as`) only refuses to SITE a
  new build want more than 400 elmos forward of the base anchor. It never looks
  at his health and does nothing once he is under fire on an existing task.

**Restored** as `manager/brain/market/safety.as` (`Market::CommanderSafety`),
called from `Decide` BEFORE the finish-what's-started early return -- a
commander with progress on a frame would otherwise never reach it, which is
exactly the state he dies in. Carries the caution test (fielded HEAVY+SUPER at
half his cost, or post-T2 mobile massing at 2x), the forward-work refusal, the
influence flee (ring-sampled while cautious), and the low-HP retreat with the
critical-HP raw steer. Seven `TUNE_COMM_*` tunables restored with their original
defaults; `apex_comm_rules` is the master toggle and is modoption-tunable.

Two deliberate omissions from the original: pack-spreading (needs `AllyCommNear`
and `SolarDef`, both deleted -- matters for 8v8 chained commander explosions,
not for 1v1) and `Factory::gEnemyT2Seen` (sense deleted; the caution test uses
our own `Factory::gHaveT2` as the progression split instead).

**A/B, 6 seeds, master toggle on vs off, same build:**

| | comm deaths | mBuiltReal | mex | t2Mex | flee lines |
|---|---|---|---|---|---|
| safety ON | 0/6 | 14,350 | 12.5 | 0.0 | 1 |
| safety OFF | 0/6 | 15,235 | 14.5 | 0.5 | 0 |

**The commander does not die in either arm, so this benchmark cannot measure the
thing the feature exists to prevent.** What it can measure is the cost: about 6%
of metal and 2 mexes, inside a spread of 5,810-26,110. Judge this from a watched
hosted game, not from here. Do not "tune" it against these numbers.

## OPEN: ProposePlant dedups on FINISHED plants only -- two of the same plant get bought seconds apart

apexearth 2026-08-24, watching Altair_Crossing_V4.1: "we often make two t1 labs".
Confirmed in `matches/20260824-043712-...` (seed 4), which built
`armap:1420, armlab:500` -- TWO Aircraft Plants (710 each) plus a Bot Lab:

```
f=24369 con#393   produce/plant:armap v=284.49
f=24449 con#8485  produce/plant:armap v=292.34     <- 80 frames later, different con
```

Two constructors 2.7 seconds apart each elected to build an Aircraft Plant.
Neither divided its gain, because `ProposePlant`'s `reachKin` counts only
FINISHED plants -- `Catalog::Def(d).count` and `gOwnCount` -- and no armap had
finished yet. This is the async-order window the `async-sim-orders` skill
covers: the read lies during the walk phase.

`ProposeTech` already guards exactly this, two ways: `Requests::LiveOfDef(def)`
skips a def that is already requested, and `liveKin` counts live kin plants in
`Requests::gLive` and divides the demand among them. `ProposePlant` has neither.
The only live-aware check it has is the top-level
`Factory::gFactoryCount + Requests::LiveCountOf(FACTORY) >= supported` gate,
which bounds the TOTAL factory count, not copies of one def.

Second, separate cause of "two T1 labs": `reachKin` only counts a plant as a
duplicate when `kReach >= myReach && kAir == myAir`, so a ground Bot Lab and an
Aircraft Plant are never duplicates of each other and each prices as if it were
the first plant. That air/ground split is deliberate (the comment reads "we want
multiple T2 air labs, not T1 air labs"), but its side effect is that the first
air plant is never deduped against the ground lab it duplicates in the T1 role.
Seen in 2 of 6 recent runs as `armap:710, armlab:500`.

Same bug SHAPE as the tech channel-2 entry below: dedup logic that ignores work
already in flight, or that partitions on an attribute the duplicate does not
share.

## OPEN: the tech want's mobility channel buys a second same-tier plant on speed alone

`ProposeTech` channel 2 fires when a plant's constructor is >1.2x as mobile as
anything owned (`prodMob > ownMob * 1.2`). BAR's T2 vehicle constructor is 1.5x
the T2 bot constructor's speed (`coracv` 49.5 vs `corack` 33), and
`MobilityMult` = 60/(walk/speed + 12), so the ratio lands 1.23-1.36 across walk
distances of 500-1500 -- the gate clears essentially always. Once a T2 bot lab
stands, the T2 vehicle plant prices itself in, unlocking no new reach.

Unlike channel 1, **channel 2 has no kin division**. Channel 1 divides its gain
by `(1 + liveKin)` so demand splits among the pipes already serving it; channel 2
prices the mobility delta against the ENTIRE upgrade demand no matter how many
plants already work that stream.

Confirmed against `matches/20260824-021933-...`: `tech:coravp gain=2.66` at
f=32449 with `upD=15.76` matches `15.76 x pipe(2.0) x (1.30-1) x funded(0.50) x
latency(~0.5) = 2.4`. Channel 1 would have produced 31.5, an order of magnitude
more, so the mobility channel is the source.

It nonetheless priced LOW and was bought by the draw anyway (`v=0.58 over 8.66`,
a 15x upset), so the kin division is the smaller half of this. Fixing channel 2
makes the want weaker; the draw would keep buying it.

NOTE: at the current default this is not currently firing -- all four sweep runs
built exactly ONE T2 plant (`allBuilt` shows `armalab:2900`, one lab). Two plants
appeared in the 021933 baseline (`coralab:2900, coravp:2800`). Judge this on
`allBuilt`, never on the `produce/tech` decide count -- a decide can be a
re-election, and reading decides as buildings produced a wrong "2 labs" report
2026-08-24.

## OPEN: the displacement charge exempts exactly the builds that displace most

`ValueOf` in `market/price.as` charges an expensive build for the mex-upgrade
stream it postpones, but only inside `if (feedSec > buildSec)` — i.e. only when
metal income cannot keep the build fed. A def with a huge buildtime has a
`buildSec` so long that income always keeps up, so the gate never fires and the
charge is zero.

Two fusion decides 66 seconds apart, before-run:

```
f=15929  energy:corafus  m=9736  t=1348   (buildtime 329,200)
f=17601  energy:corfus   m=4973  t=6925   (buildtime  75,400)
```

The cheaper, faster building was charged 5x more builder-time. Pure walk+build
time for corfus should be roughly a quarter of corafus's at the same fleet, so
`displacedM` is ~6,600 on the fusion and ~0 on the AFUS — while `tech-diag`
reported `upD=39.5` m/s of unserved upgrade demand at that moment.

A build that occupies the fleet for ~900 seconds displaces more, not less. The
gate should key on occupation, not on which of two durations is larger.

## LANDED 2026-08-24: the energy floor now nets out the converter that realizes it

`EPriceFloor()` treated a conversion ratio as a free exchange rate. It is not
(apexearth: "we have to have a converter for that to even be true"). The floor
now amortizes the converter's metal, its own energy bill and its build time
against the metal it makes over `apex_conv_horizon` (600s, a CHOSEN number, not
derived), solved directly for P since the converter's cost is denominated in the
price being computed.

Two bugs fixed together: the floor was also taken from the best converter in the
whole catalog -- the T2 converter at 0.01724, above the T1 at 0.01429, from
frame zero -- with no check that anything we own could place one. Now restricted
via `CanBuildEver`.

Four runs after (`matches/20260824-0323*` .. `-032616`), all compile-clean:
T2 labs 1/1/1/1 (was 3 in the run before), zero AFUS decides in any run,
mex upgrades 25/6/13/1. Not attributed -- the AI is multithreaded and the
before-side is a single run.

`apex_conv_horizon` is 300s -- short on purpose (apexearth: "it pays off
eventually and that's fine; by the time this stuff matters less we're on to
fusions and afus"). Measured with `--modoption apex_efloor_diag=1`
(`matches/20260824-033449-...`):

| phase | floor | E-per-metal |
|---|---|---|
| early, build power scarce | 0.01209 - 0.01256 | **80:1 - 83:1** |
| late, build power plentiful | 0.01327 - 0.01333 | **75:1** |

Against the flat 0.01724 (58:1) the old code used from frame zero. The penalty
is largest exactly when build power is scarce, which is correct and is where it
decides wind-vs-moho.

It does not reach 80:1 late because the arithmetic honestly says a T1 converter
IS nearly free at high build power -- 2,600 buildtime against a 1,400-BP fleet
is under 2 seconds, so its net approaches the raw ratio. Getting late-game into
range needs a utilization term (nameplate `energyconv_capacity` is never fully
chewed), not a shorter horizon.

Minor: the winning def logs as `armfmkr`, the SEA converter, because its cost
and ratio are identical to the land `armmakr` and it sorts first. Harmless here;
it would misprice if a faction ever shipped a cheaper water-only converter,
since `CanBuildEver` does not ask whether the site is placeable.

**This does not touch the wind spam.** `EPrice()` returns `max(premium, floor)`
and the premium is ~0.093 against a floor of ~0.0148, so the floor never binds
for a wind turbine: mean `corwin` bid moved 33.9 -> 31.9. The floor binds only
where `EPriceAt` has decayed the premium away, i.e. on long builds -- which is
why the AFUS decides disappeared and the wind decides did not.

## TESTED 2026-08-24, DO NOT SIMPLY LOWER: energy's permanent scarcity premium

`EPrice()` multiplies energy pull by `apex_e_headroom` (1.75) before measuring
shortage, so `excess` reads 0.75 even when energy income exactly equals pull.
Energy is then priced as if permanently in shortage. The premium cannot be
cleared: building energy raises income, the fleet it feeds raises pull, and the
multiplier is applied to pull.

Measured against BAR's own exchange rate (`energyconv_efficiency = 0.01429`
M per E):

```
corwin   mean v=33.92  (gain 2.32 on windgenerator 25)  -> implied 0.093 M/E  =  6.5x floor
corfus   f=18457 gain=250.11 on 1100 E/s                -> implied 0.227 M/E  = 15.9x floor
```

Consequence in the before-run: 672 of 682 energy decides were `corwin`, a
43-metal wind turbine, against 1 mex upgrade all game. Priced at the converter
floor, wind bids v≈5.1 — below the moho's 9.05. The premium alone inverts the
order.

**A/B run 2026-08-24, 4 seeds each, same build, headroom varied by modoption
so nothing else differs. Lowering it is worse on every measure:**

| headroom | t2Mex | mex | mBuiltReal | wind decides | mexup | tech |
|---|---|---|---|---|---|---|
| 1.75 (default) | **1.0** | 19.0 | **18,365** | 234 | 9 | 2 |
| 1.0 | **0.0** | 17.5 | 16,690 | **320** | 6 | 4 |

T2 mexes appeared in 3 of 4 games at 1.75 and 0 of 4 at 1.0. Wind decides went
UP when energy was made cheaper -- the tell for a feedback loop: under-priced
energy means less of it gets built, we actually run dry, the
`eCur < 0.25*eStore` clause spikes `excess` to emergency levels, and wind gets
panic-bought anyway from a worse position. Same failure already recorded at the
`EPrice` call site ("we e-stalled and should have made a basic solar").

So the premium is real AND load-bearing. The mechanism description above stands;
the obvious fix does not. Anything that touches this must keep supply leading
demand -- the honest lever is probably the anticipation term
(`gEPullGrowth * apex_e_lookahead`) carrying the intent instead of a flat
multiplier, but that is untested and the flat multiplier currently wins.

Variance is high (wind decides ranged 139-814 within one setting), so n=4
medians are weak. Do not re-open this on a single run.

## LANDED 2026-08-24, needs a controlled measurement: wants compete by category

`market/kinds.as` now groups the 12 want kinds into 6 categories
(metal/energy/produce/buildpower/defence/reclaim). One lottery ticket per
category, weighted by that category's best want; argmax inside the winner.

Confirmed working in the after-run: mex upgrades went 1 -> 5 decides, and 4 of
the 5 won on price rather than on a draw (`armmoho v=12.58 over energy v=2.80`).
AFUS now lands after the first moho (f=35249 vs f=30217) instead of before it.

Not yet confirmed: the projected drop in energy's share of decides did not
appear (56% -> 60%, uncontrolled comparison). `geo` and `store` almost never
propose and `convert` fired 11 times in the before-run, so energy held about
two tickets, not four — the de-duplication was smaller than projected. Needs a
same-setup control before the entry is deleted.

## OPEN: none of the air assassination work can be measured on this benchmark

`AIR_MIN_INCOME` is 40 metal/s and deliberately "out of reach of the 4v4
benchmark" (its own comment). Benchmark logs read `no air assassin, best ally
income 22/40`, so the elector never fires, no wing is built, no run is scored,
and the feedback loop never gets its first sample. Everything landed 2026-08-24
is compile-clean over full games and DORMANT here.

It can only be judged in a hosted game. First thing to look for is the
`apex: air run scored` line -- until one appears, the loop is running on its
prior and the assassin will prefer the cheap fast bomber.

## LANDED 2026-08-24: AA was unbuyable, army gifting defaulted on, Juno bought as a turret

Three from one watched game (apexearth).

**Static AA could not be bought at all.** `ProtClassOf` files every static
defence into a protection class; its last test was `gSurfT > 0.5 * gAirT`, a
ground-shooting weapon. An anti-air tower fails that and fell through to
`return -1` -- no class, so `ProposeProtect` skipped it every time, and there was
no AA branch to reach anyway. No amount of being bombed could produce a tower.
The air-threat SENSE was fine (`AirThreatNow()` updates from `posture.as:622`);
what died with the leaf rules was its consumer -- `HeavyAAWant()` still sits in
`airthreat.as` with no caller.

Fixed: new `PROT_AA` class, and a protect branch priced off `AirThreatNow()`
(this tick's reading, not the 240s EMA, so a raid is answered as it develops).
Gain is the value at risk capped by the air they actually field, divided by the
towers already standing -- coverage scales with their air and stops on its own,
no count and no cap. `apex_aa_urgency` (4.0, CHOSEN, matching the shield
branch's multiplier) prices air above ordinary insurance.

Measured, 33-minute 4v4 where BARb fielded `corshad`/`corhurc`/`corvamp`: Apex
teams built `mDefAA` 80/480/1120 and 21 AA units. A 1v1 where neither side flew
built none -- correct silence, not a dead path. NO A/B: there is no toggle for
the branch, so the "zero before" claim rests on reading the code path.

**Army gifting now defaults OFF.** `apex_gift_army` already existed and simply
defaulted to 1. apexearth: "we should disable that by default. It only is
appropriate on certain maps." Confirmed silent over a 33-minute 4v4.

**Juno blocked.** A Juno is a one-shot area weapon against radar, jammers and
minefields; it carries a weapon and has no build options, so `ProtClassOf` filed
it as ground defence and the protect want bought it as a turret. 640 metal in one
measured 4v4. Blocked in `Catalog::BlockedDef` -- the single `gAvailable`
chokepoint every want already checks, so no proposer needed changing. Lift with
`apex_allow_juno=1`. Verified 0 metal into Juno after.

**Tactical missile silos blocked (2026-08-25).** apexearth: "I need to ask for
the tactical missile launcher too. We need special logic before we should be
making buildings like that." `cortron` (Catalyst, 1200m/14000e) and `armemp`
(Paralyzer, 1600m/29000e) reach the protect want by the same route as the Juno --
weapon, no build options, so `ProtClassOf` files them as ground defence -- but
they are operator-aimed: a silo that is never given a target order is pure
displaced constructor time. Same chokepoint, lift with `apex_allow_tacmissile=1`.
Legion ships no equivalent. OPEN: the real fix is a director that picks and
commits targets (the nuke director is the shape to copy), after which the block
comes off; until then no proposer should buy any weapon it cannot aim.

## 2026-08-24 — danger pricing, forward defence, sensors

### OPEN: a cheap want that needs a walk can never complete
`decide.as` re-elects every 2s and only holds a task with `Progress > 0.01` or a
site within 600 elmos. Combined with the category roulette, any LOW-value want
whose site needs a walk is abandoned mid-approach and re-bid forever.
Measured: 38 `sense/sense:armrad` decides and a created request
(`request new armrad inFlight=1`) in one 28-minute 4v4 — **zero radars built**.
Radar was not special; it is the cheapest distant want, so it shows the effect
first. Suspect the same mechanism starves other cheap-and-distant work.
Not yet fixed. A hysteresis on re-election (only switch if the new top is
meaningfully better than the held want) is the obvious candidate, but it is a
change to the core arbiter and needs its own measurement.

### FIXED-PENDING-CONFIRMATION: sensors never competed
All seven protection classes argmaxed for ONE `WK_PROTECT` slot, so ground
defence — whose gain is loss prevented outright — beat radar/jammer/targeting
every time. Measured across twelve 4v4 games: **zero sensors of any kind built**.
Split into `WK_SENSE`/`CAT_SENSE` so seeing and shooting draw separate tickets
(the same rule already applied to energy). Jammers now build; radar is still
blocked by the walk-abandonment issue above.

### FIXED-PENDING-CONFIRMATION: radar coverage was a boolean at one point
`want_protect.as` skipped the radar class if any radar stood within
`gRadarR[CANDIDATE] * 0.8` of the farm, and never varied the position from the
farm — so a 60-metal armrad permanently blocked the 3500-range armarad, and
coverage never followed the front. Now tested against each STANDING radar's own
range, sited at the nearest unwatched front post or mex, and priced by the
unseen share so it self-limits.

### MEASURED: our own base is uncovered by our own guns
`home[short=...]` in the `apex: risk` line read **1.00 in 42 of 64 samples** —
i.e. standing turret coverage stops none of the local threat at home. This is
the measured form of "our defenses don't seem good enough", and it is also why
the tech survival discount cannot yet discriminate: danger is high *always*, so
the discount is close to a constant factor rather than a signal.

### NEGATIVE RESULT: tech survival discount is unmeasurable on this benchmark
`TechSurvival` (gain discounted by `HazardAt * ShortfallAt` over the pipeline
latency plus affordability time) is wired and compile-clean, gated by
`apex_tech_survival`. A/B of 6+6 games showed **no detectable effect**: first-T2
4.8-10.0 min treated vs 4.3-8.7 control, fully overlapping. Expected — see the
uncovered-base finding above. Left on by default; re-measure once forward
defence produces variance in home coverage.

## 2026-08-24 (2) — the danger sense read zero at home

### FIXED: our own base was the safest place on the map, by construction
`ExposureAt(pos)` is `distance(pos, home) / apex_expose_r`, so it is **exactly 0
at home**. It multiplied two things:
- `ThreatM`'s cold-start baseline (`EnemyCostOf(RAIDER) * ExposureAt`) → the
  expected wave size at home was 0.
- `HazardAt`'s arrival term (`ExposureAt * foe/(foe+defended)`) → home hazard sat
  on `apex_risk_floor` all game (measured: 1.25/ks, the floor exactly).

Consequences, both measured and both reported by apexearth while watching:
- `ShortfallAt(home) = 0` ⇒ every turret's gain at home is `stake * hazard * 0`
  ⇒ **no base defence is ever worth buying** ("2 enemy units just destroyed our
  entire base. We made 0 defenses").
- `TechSurvival = 1/(1 + hazard*shortfall*T)` with shortfall 0 is **exactly 1.0**
  ⇒ the tech discount never fired at all ("we made a T2 lab REALLY EARLY and
  were working on that while our base was completely destroyed").

Fix: removed the `ExposureAt` factor from both. Wave SIZE is the same wherever
it goes; how OFTEN it arrives is `HazardAt`'s job, and position still enters
there through `CoverAt`. This is what `coverage.as`'s own header already said.

Measured, 6+6 games, 1v1 Altair Crossing, Apex vs BARb stable hard:

| | before | after |
|---|---|---|
| metal produced | 14,012 | **32,897** |
| mex | 12 | **18** |
| mDefence | 368 | **1,930** |
| army (real) | 140 | **545** |
| metal wasted | 2,779 | **1,604** |
| games lost | 6/6 | 4/6 (2 survived to the time limit) |

### OPEN: threat magnitude is still too low at home
Even after the fix, `home short=0.00` persists. `ThreatM`'s baseline is
`EnemyCostOf(RAIDER)` only — measured at 84-147 metal in a 1v1 — while one
`corhllt` contributes `600 * apex_def_trade(2) = 1200` of "wave stopped". So a
SINGLE tower saturates coverage at home and no second one is ever bought.
Two candidate levers, neither yet tested:
- the baseline should reflect what can actually concentrate on the base (their
  mobile mass), not just the raider role;
- `apex_def_trade = 2` claims a turret stops twice its own cost in attackers.

### OPEN: `covered=N` in the risk log was a boolean and lied
It counted "some turret's range reaches this mex", so one HLLT printed
`covered=3` while all three mexes died (apexearth: "the 3 mexes were not
covered, theres no way"). The line now also reports `meanShort=`, the share of
the local wave our guns do NOT stop, which is the number the gain math uses.

### OPEN: constructor over-investment in 1v1
1v1 baseline showed 10 constructors / 1,320 metal in cons against 140 metal of
army, with 2,779 metal wasted. Suspect the new `BacklogM` term in `BPGap`
(landed today) since `BPGap` also gates factory con-orders. NOT yet A/B'd --
`apex_bp_backlog_s=0` disables it.

## 2026-08-24 (3) — the arbiter was thrashing, not building

### FIXED: builders abandoned every walk, so distant work never happened
`decide.as` re-elected every 2s and only held a task with `Progress > 0.01` or a
site within 600 elmos. A builder electing anything further away walked, re-rolled
mid-walk, and abandoned. Measured in ONE 1v1 game:
**461 decisions to build a `corllt`, 21 requests created, ZERO defences standing
at the end** -- and defence was winning 46% of all constructor elections (579 of
1266). Constructor time, which is the economy, went almost entirely into walking
away from the previous decision.

Fix: a builder that is genuinely CLOSING on its site holds it. One that has
stopped closing (blocked, or the site moved) re-elects as before. Per-unit last
distance in `gApproachD`.

Measured, 6+6 games, 1v1 Altair:

| | thrashing | committed |
|---|---|---|
| metal produced | 19,970 | **27,444** |
| defence metal | 1,305 | **2,445** |
| army | 210 | **540** |
| metal wasted | 1,661 | **1,089** |
| `corllt` decides | 461 | **38** |
| defences standing | none | cortron/corhlt/cormaw/corhllt |

### FIXED: enemy standoff was ignored in coverage
`CoverAt` asked whether a turret reaches the TARGET. The attacker never stands on
the target -- it stands at its own weapon range and shoots in, so a turret that
barely reaches a mex denies nothing (apexearth: "an enemy can just stand right
next to that mex and still shoot it, while staying outside the range of the
turret"). Coverage is now measured on the ring the enemy can shoot from, valued
at the WEAKEST bearing, using `Military::FoeReach()` (max observed enemy group
weapon range, decayed). `apex_standoff_cover=0` restores the old test; measured
worse with it off (defence 90 vs 1305, army 0 vs 210).

### FIXED: the T2 lab was sited at the constructor's feet
`InteriorSite` fell back to `here` -- the asker's own position -- whenever no
nano farm existed. A con that had walked forward to claim a mex therefore put the
T2 lab on the front line (apexearth: "we just started T2 lab in a dangerous area
... off to the side is a smarter location than in the direct path"). Now falls
back to a rear FLANK of the anchor, which also removes the builder-in-its-own-way
inefficiency he noted.

### OPEN: unscouted still reads as safe outside the tech price
`Front::FoeKnown()` now forces shortfall to 1.0 inside `TechSurvival` only. The
same prior applied globally inside `HazardAt` repriced every want and cost 87% of
standing army (measured, 6 games) -- reverted. Scouting itself is untouched:
apexearth asked for scouts ("if we don't know the enemy strength then we
shouldn't be making a T2 lab... we need scouts") and nothing yet raises scout
production when intel is stale.

### OPEN: army production is starved by constructor orders
In 1v1, 80 of 137 factory orders were constructors (corck 42, corch 38) against
43 army units. Not caused by the new `BacklogM` term -- A/B'd with
`apex_bp_backlog_s=0`: metal 20,754 vs 19,970, army 140 vs 210, neutral.

## 2026-08-24 (4) — THE BENCHMARK CANNOT RESOLVE THESE CHANGES

Ran the SAME build twice, 6 games each, 1v1 Altair:

| | run A | run B |
|---|---|---|
| metal produced | 16,065 | 18,786 |
| defence metal | 180 | **682** |
| constructors | 12 | **6** |
| army | 145 | 210 |
| metal wasted | 1,357 | **3,070** |

Defence swings 3.8x and constructor count 2x on UNCHANGED CODE. That is the
same magnitude as most deltas reported earlier today, including the "net
regression" (27,444 -> 14,910) that caused `apex_def_net` to be defaulted off.
**Those economic medians were noise and should not have been reported as
results.** Judge these changes on log-level mechanism counts instead -- decides
vs things actually built, positions, shortfall readings -- which are direct
observations and were the findings that held up.

### LANDED, each verified by log evidence rather than by medians
- Commander FIGHTS (`safety.as`): he was never handed a fight task anywhere;
  `Role::COMM` appears in the whole military layer only in unblock code. Now,
  while `CommCaution` is false (i.e. before heavies are fielded), he goes at the
  nearest enemy group on our own half that he outweighs AND that is worth more
  than the round trip costs at `Wage()`. First cut chased a 1-metal scout six
  times; with the wage test it engages a 120-metal raid. `apex_comm_fight=0`
  restores the flee-only commander.
- Jammer gated on enemy INDIRECT FIRE (arty + half skirm >= 200). It was priced
  on total assets and won an early sense ticket ahead of sentries and mexes
  (apexearth: "we're making a jammer long before it would ever provide value").
- `apex_def_net` defaulted OFF pending a bounded site list -- see the noise
  caveat above; the regression that motivated this may not be real.

### OPEN AND NOW THE BLOCKER: we never scout
`Military::EnemyArmyCost()` logged as **0 for entire games** while the enemy
fielded 3000 metal of army. Everything that should respond to enemy strength --
`ArmyTarget`, `fundedMul` on the tech price, the commander's engage test, AA,
the danger model -- is reading a zero. apexearth, watching: "if we don't know
the enemy strength then we shouldn't be making a T2 lab... we need scouts."
Nothing in the variant raises scout production when intel is stale.

## 2026-08-24 (5) — defences were landing BEHIND the base

apexearth, watching: "we are more likely to build towers behind our base than in
front of our base. So the enemy just drives right up and kills all our energy
easily, nothings really protecting it."

Measured with a new `apex: defplace` line (tower position vs anchor, both as
ForwardFraction). Confirmed: `front=0` on 12 of 12 placements -- the front-post
branch never won a single auction -- and towers repeatedly landed behind the
anchor (-0.73 vs -0.47, -0.95 vs -0.57).

Two causes, both fixed:
- **Energy was never a candidate SITE.** Only structures over 1200 metal enter
  `gOwnBig`, so a solar field could never have a tower proposed at it however
  much `StakeAt` valued it. `gOwnGen` positions are now offered.
- **Every candidate sat ON something we own**, so a tower there meets the raider
  only after it has already arrived. Added `ShieldArcSpots`: the base's
  metal-weighted mass centre (`BaseCentroid`), an arc toward the enemy wrapping
  +/-110 degrees to cover both flanks, at one denied radius outside the measured
  base edge, spaced by what each turret actually denies. His spec verbatim.

After: `front=1` on 6 of 10 placements, and towers forward of the anchor in most
(e.g. -0.34 vs anchor -0.81).

Bound worth noting: the arc caps at 12 posts. That is a bound on WORK per
election, not on how much defence we may own -- the auction still buys as many
towers as the prices justify.

## 2026-08-24 (6) — THE ANSWER: we lose on combat, not economy

60 games, today's builds only, 1v1 Altair, Apex vs BARb stable hard. Paired
(both sides measured in the SAME game, which cancels map/seed noise).

| min | our metal | their metal | our army | their army | our def | their def |
|---|---|---|---|---|---|---|
| 10 | 4,755 | 4,990 | 140 | 450 | 0 | 90 |
| 20 | 16,457 | 15,898 | 720 | 2,618 | 555 | 1,845 |
| 25 | 19,843 | 22,252 | **215** | **4,040** | 555 | 3,288 |

At game end:

| | us | them | ratio |
|---|---|---|---|
| army standing | 215 | 4,040 | **0.05** |
| defence | 555 | 3,288 | 0.17 |
| metal LOST | **13,370** | 3,320 | **4.03** |
| metal KILLED | 1,620 | **12,038** | **0.13** |
| factories | 3,390 | 3,370 | 1.01 |
| constructors | 1,610 | 2,600 | 0.62 |

**Economy is at parity (0.89-1.04 all game). Trade ratio is 0.12 against their
3.63 -- roughly 30x worse.** `mT1` is 10,345, so we DO build army; it dies
immediately and kills almost nothing. Every symptom reported while watching
(no defences, no army, base overrun by two units) is downstream of this, not of
production. Factories are level; we run FEWER constructors than BARb.

Deaths are `by[stat/air/mob] = 76/0/1048` -- we die to mobile units in straight
fights, not to turrets.

### Lead, not yet confirmed as the cause
`apex: mass want=154 floor=61 army=1920 enemyArmy=5205 ratio=2.71` followed by
`apex: mass hold expired, committing at 108`. The no-commit suppressor
(`apex_mass_no_commit_ratio = 2`) SHOULD have fired at 2.71 -- so `localEdge`
(local superiority within 2200, `apex_local_edge = 1.3`) overrode it. Commits
fire 4-7 times per game against 4-12 suppressions. Whether the local-edge
override is what feeds the army in piecemeal is NOT yet established.

### METHOD NOTE -- a mistake that produced a wrong report today
An earlier version of this analysis globbed `tournaments/*1v1-*` and pulled in
732 games from PREVIOUS SESSIONS running different code, which produced a
confident and completely wrong conclusion (that we out-produce them 1.16x and
overspend 5.9x on factories). Always restrict the glob to the dated runs of the
build under test.

## 2026-08-24 (7) — where the metal actually goes, paired

apexearth's new destination telemetry (mEco/mBP/mArmy/mOther, commit 1b5f033),
12 games, 1v1 Altair, both sides measured in the same games.

At 10 minutes:

| bucket | us | them |
|---|---|---|
| BP | **18.5%** | 9.9% |
| defence | **0.8%** | 5.1% |
| eco | 14.3% | 11.1% |
| army | 65.3% | 73.9% |

At game end:

| bucket | us | share | them | share |
|---|---|---|---|---|
| eco | 2,416 | 16.3% | 2,969 | 14.1% |
| BP | 4,378 | **29.5%** | 3,750 | 17.8% |
| army | 6,605 | 44.5% | 9,852 | 46.8% |
| defence | 1,095 | **7.4%** | 4,068 | **19.3%** |
| mex count | 14 | | 17 | |

- **BP over-budgeted**, confirming his read: 1.7x their share, ~2x early.
- **Eco SHARE is already ahead of theirs** (16.3 vs 14.1) -- what is short inside
  it is mexes, 14 vs 17. "More eco" is not supported; "more mex within eco" is.
- **Defence is the largest gap and neither of us named it first**: they spend a
  fifth of their metal on defence, we spend a fourteenth.
- `mBP` is CUMULATIVE spend: 4,378 bought against 1,365 standing, so a large
  part of it is replacing constructors that died.

`apex_bp_headroom` 1.5 -> 1.0 moved mex 14 -> 17 and BP share 29.5% -> 27.2%
(12 games each). NOTE this reverses an earlier watched call recorded in the
tunable's own comment ("1.15 read 'lacked build power' in watch after watch").
The BP share barely moved for a 33% headroom cut, so BPGap's headroom term is
NOT the main driver of BP demand -- the rest is elsewhere (nano demand,
constructor production, and loss replacement).

## 2026-08-24 (8) — unprotected build power priced as the write-off it is

apexearth's value math: "a con outside of our home safe territory immediately
has 0 value and making the cheap pawn would add the pawns value + the
constructor value back."

- `EscortMetalAtRisk()` -- the metal of exposed, unescorted workers. Escort
  demand in `RoleTarget(RAIDER)` was a flat `count * 60`; it is now this, so an
  escort is worth the CONSTRUCTOR IT RESTORES.
- `BPProtectedFrac()` multiplies what a new constructor is worth, so buying
  more hands to walk out alone buys less than it costs. It lifts by itself once
  escorts exist, and both sides of the trade read the same metal.
- Escort ASSIGNMENT now excludes SKIRM and ARTY roles ("we make rocket bots and
  use those as protection (they're not good for that)").
- Unit value gained SPEED and LOS terms, plus an affordability term
  (`fillS / (fillS + costM/income)`) so cheap-now beats strong-later while we
  are poor -- "pawns are good early game when we cannot afford much stronger
  things". The affordability term is an economy ratio, not a clock: as income
  grows the same unit costs fewer seconds and the discount fades.

Measured, 12 games each, paired against BARb:

| bucket | before | after | BARb |
|---|---|---|---|
| BP | 29.5% | **22.9%** | 18.2% |
| army | 44.5% | **55.4%** | 51.1% |
| defence | 7.4% | 5.1% | 13.5% |
| constructors built | 1,290 | **940** | |

Grunts (`corak`, 42 metal -- the unit he named) now get ordered; they were
absent before. 2 of 12 games survived to the time limit.

### STILL OPEN
Defence share fell to 5.1% against their 13.5% -- the largest remaining
allocation gap, and it moved the wrong way. Constructors and rez bots still
take 65 of ~94 production decisions.

## 2026-08-24 (9) — mex capture: the probe bug and the value shape

apexearth: "our largest problem is still that we are not making enough mexes.
If we aren't capturing half the map worth of mexes in a 1v1 then we're losing."

Instrumented every refusal gate in `ProposeMex` (`apex: mexdiag`). Altair
Crossing has **30 spots**; we held **3-5**. The gates were NOT the reason --
`pastFront=0 deathWalk=0 ecoFar=0 ecoQuiet=0` throughout.

Two real causes:

1. **The probe gave up after one answer.** `FindOpenMexSpot` returns a single
   spot from one reference position; when that spot was already in our ledger
   the proposer returned NO WANT AT ALL -- 48 such refusals in one 60s window
   while ~25 spots stood open. Now it re-probes from home, both flanks, the
   rear and the map centre before giving up. Held 3-5 -> 8-10.
2. **Value shape was too flat.** `apex_mex_growth` 3 -> 8, so relative income
   boost dominates as he described: doubling x9, +10% x1.8, +1% x1.08 (was
   x4 / x1.3 / x1.03). "When a mex would double our income it is very
   important... if it boosts our income only 1% then its not too important."

Measured, 12 games paired: mex **13 -> 16, level with BARb's 16** (was 13 vs
20), and 4 of 12 games now survive to the time limit (was 2).

`held` also oscillates DOWNWARD during a game (5 -> 4 -> 5 -> 3), so we are
capturing spots and losing them, which is the defence problem below.

### THE OUTSTANDING GAP: static defence
apexearth's early-game priority order: energy income -> protect mexes (llt) ->
capture mexes -> army. Defence is his #2 and it is our worst number by far:
**3.5% of our metal against BARb's 18.5%**, and it has FALLEN this session
(7.4% -> 5.1% -> 3.3% -> 3.5%) as budget moved into army. BARb spends nearly a
fifth of its metal on static defence, and trades at 3.63 against our 0.12.

## 2026-08-24 (10) — WHY defences landed behind the base

apexearth: "we're still making defenses in the back of our base instead of in
front... they're made behind everything important we want to protect. Thus they
protect hardly anything."

Three causes, all introduced earlier the same day, all verified from logs:

1. **The shield arc switched itself off permanently.** It was called as
   `ShieldArcSpots(arc, reach - Military::FoeReach())` and opens with
   `if (denyR < 1.f) return false`. `FoeReach` is the longest enemy weapon range
   observed, so the first time BARb fielded anything out-ranging our towers the
   arc vanished for the rest of the game: `lineSpots` 22 -> 21 -> **0**, with
   `front` wins frozen at 7 while `asset` climbed to 1,496. Now sized by the
   turret's OWN reach; whether a post still helps against a standoff attacker is
   `CoverAt`'s question and it already asks it.

2. **`StakeAt` was side-blind -- the deep one.** A tower's gain is
   `stake x hazard x Dshortfall`, and `StakeAt` counted every asset inside the
   turret's weapon range REGARDLESS OF WHICH SIDE it sat on. A tower at the back
   of the base was therefore credited with the entire base standing in front of
   it, which the enemy reaches first. Added `FrontedStakeAt`: an asset counts
   only if the post stands between it and the enemy, measured on the true enemy
   bearing rather than the cardinal-snapped base axis.

3. **A forward post is priced on a thin strip.** On empty ground `StakeAt` is 0
   and only the narrow `ShieldedStakeAt` corridor applies, so asset sites won on
   raw stake: `bestAssetGain=112` against `bestFrontGain=17`. Unfixed.

Result: tower placement went from almost entirely behind the anchor to **51%
forward of it** (110 vs 107 over 12 games).

### STILL THE BIGGEST GAP: we barely build defence at all
Defence share **4.2% against BARb's 17.4%**. Placement is now roughly right;
QUANTITY is not. This is a separate problem from siting and is the largest
remaining allocation gap in the AI, matching apexearth's stated #2 priority
(protect mexes with llt) and the 0.12-vs-3.63 trade ratio.

## 2026-08-24 (11) — enemy reach as a power-weighted mean

apexearth: "we can perhaps average out all the enemy ranges we see. If they only
have a few things outranging those defenses then we can still make them...
per_unit(power * range) / totalPower"

`Military::FoeReach()` took the MAXIMUM observed enemy group weapon range, which
is an outlier statistic: one artillery piece spoke for their whole army. Now the
cost-weighted mean over enemy groups (group cost is the power proxy the enemy
model exposes). Measured in game: foeReach reads **294-413** instead of the
artillery maximum, and the shield arc stops collapsing (`lineSpots` holds at 5-6
rather than falling to 0).

Alongside it, `ShieldedStakeAt` was still testing "is this asset behind me"
against `Base::gFwd`, which is SNAPPED TO A CARDINAL -- so on a map where the
enemy sits diagonally it was wrong by up to 45 degrees and rejected the entire
base. Forward posts priced at exactly **0.00 gain** and could never win. Now on
the true enemy bearing, like `FrontedStakeAt`.

Measured, 12 games paired:

| | before | after |
|---|---|---|
| tower placement forward of anchor | 51% | **96%** (216 vs 10) |
| median bestFrontGain vs bestAssetGain | 0.0 vs 112 | **10.5 vs 19.5** |
| defence share | 4.2% | **6.4%** (theirs 14.6%) |
| games surviving to time limit | 2/12 | 3/12 |

Defence quantity is still short of theirs and remains the largest gap; their mex
count also pulled ahead (24 vs our 15) in this batch.

## 2026-08-24 (12) — the commander went on tour

apexearth: "we won that game because our commander rushed the other base for
some reason and gained enough experience to 1v1 the enemy commander. we left our
base completely undefended though which was pretty bad."

The commander-fight rule added earlier today gated targets on
`ForwardFraction(gp) < 0.5` -- "our half of the map". That is not a leash: he
walked to the midpoint, chained the next target from there, and ended up
duelling their commander in their base with ours empty. Winning that game is not
evidence the rule was right.

The bar is now our own property: `StakeAt(gp, apex_threat_r) > 0`, so something
of ours must be standing within the raider's reach. There is nothing of ours at
their base, so there is nothing to chase toward -- and no map fraction is
invented anywhere.

Measured, 12 games: engagements occur in 10 of 12 games against real raids (235,
455, 355 metal against his 2,700) rather than tours. Win/loss unchanged.

## 2026-08-24 (13) — emergencies, and a stake shape that finally works

Three shapes were tried for what a defence post's STAKE is:

1. **Side test** ("is the post between this asset and the enemy") -- right for a
   distant intercepting post, wrong for a tower inside the base, because half
   the base is in front of any home tower. Home priced to nothing and raiders
   walked in (apexearth: "we leave the home base completely undefended so the
   tiny enemy raiders totally kill it easily").
2. **Standoff-subtracted distance** (`reach - FoeReach`) -- demanded a post deny
   EVERY firing position: 450 reach against 300 standoff leaves 150 elmos, so
   almost nothing qualified. **Defence collapsed to 1.9% of our metal and we
   lost 12/12.** Standoff is CoverAt's question; charging it in the stake too is
   double counting.
3. **Plain distance within reach**, plus `ShieldedStakeAt` for what a forward
   post intercepts beyond its own range. Distance alone does the work the side
   test was reaching for -- a tower at the back of the base simply cannot reach
   a mex 800 elmos forward.

Plus two EMERGENCIES, both with measured two-part triggers, both skipping the
category lottery rather than taking a share of it:
- **AA panic**: zero AA standing AND metal actually being lost to aircraft now.
  UNTESTED -- BARb built no air in any of 24 games on this map, so it has never
  fired. Do not claim it works.
- **DEF panic**: zero ground defence standing AND structures dying at home.
  Fires in 5 of 12 games.

Measured, 12 games paired (shape 2 -> shape 3 + emergencies):

| | shape 2 | shape 3 |
|---|---|---|
| defence share | 1.9% | **9.1%** (theirs 17.4%) |
| mex | 12 | **19** (level with theirs) |
| army | 6,433 | 9,138 |
| metal produced | 11,596 | 19,206 |
| games surviving | 0/12 | **3/12** |
| home shortfall 0.00 | ~never | 104 of 216 samples |

## 2026-08-24 (14) — energy had NO compounding premium at all

apexearth: "we are not properly multiplying the benefits of a strong eco because
we stagnated that game. The more we boost eco the more all of our other metrics
get boosted."

He was right and the asymmetry was stark: the relative-growth compounding term
existed ONLY in `want_mex.as` and the mex-upgrade path. `ProposeEnergy` was a
flat `gain = makeE * EPriceAt(buildSec)` with no growth premium whatsoever. So a
doubling mex was worth x9 while a generator that doubled our energy income was
worth x1 -- half the economy priced with no compounding.

Now the same shape, measured against ENERGY income (what an energy build
actually raises), `apex_energy_growth = 8` to match `apex_mex_growth`.

Measured, 12 games paired:

| | before | after |
|---|---|---|
| **games surviving to time limit** | 3/12 | **6/12** |
| metal produced | 19,206 | **24,064** |
| army | 9,138 | **12,706** (theirs 12,804 -- level) |
| defence | 1,740 (9.1%) | **2,400 (10.0%)** |
| mex | 19 | 20 |
| BP share | 28.4% | 23.0% |

Half the games are no longer losses, from 0/12 surviving three iterations ago.
Still 0 wins. Our eco SHARE reads lower (12.2% vs their 26.7%) only because our
total grew into army; theirs also grew because the games now run long.

## 2026-08-24 (15) — the start-box threat gradient

apexearth: "preload some measure of threat at a gradient towards the enemy's
side of the map. Our start box centerpoint compared to their starbox centerpoint
and a gradient of safe to unsafe."

Needed more than it looked: after `ExposureAt` was removed from the danger model
that morning, there was NO spatial gradient left at all -- a tile in our base and
a tile outside their factory read identical threat, with position entering only
through our own turret coverage.

`ThreatGradient(pos)`: 0 at our start, 1 at theirs, on the home->enemy
projection, falling back to the MIRRORED start before contact because the enemy
centroid is noise then. It feeds two places:
- `ThreatM`'s prior now interpolates between two MEASURED magnitudes -- a raid
  at our end, their whole mobile army at theirs -- floored by the symmetric
  prior so an unscouted enemy is not assumed absent.
- `HazardAt`'s arrival term scales with it: their strength says how badly it
  goes, the gradient says how often it happens at all.

A/B, 12 games each, `apex_threat_gradient`:

| | ON | OFF |
|---|---|---|
| games surviving to limit | **5/12** | 3/12 |
| defence share | **9.3%** | 5.3% |
| mex | 20 | 20 |
| metal | 20,716 | 20,906 |

### REVERTED: the holdability veto
His actual goal was "stop our initial constructors from taking... mexes or geos
in the center of the map - highly contested areas". Pricing cannot do it: the
risk charge on a deep spot is ~4 m/s against a mex gain of ~17 (mex gain carries
the x9 relative-growth premium). A holdability test -- refuse spots past the
midpoint unless our fieldable army outweighs the local threat -- DID clean up
the opening (depthMax held at 0.07 for five minutes instead of jumping to 1.00)
but cost far more than it saved: **1 of 12 games surviving against 5-6**, metal
15,092 against 19,878-24,064, defence back to 5.8%. Reverted.

Note for whoever tries again: `OurArmyNow()` counts the commander's 2,700 metal,
so a first attempt at that test never fired once (`deep=0`). `ArmyValue()`
excludes builders and is the fieldable-army number.

**The goal remains unmet.** Early constructors still reach depth 1.00 sometimes.

## 2026-08-24 (16) — "beamers in the back": an armed MEX was 75% of our defence

apexearth: "I see us making beamers in the back of our base again. Why are we
doing that?"

Dominant cause, and it is a misclassification, not a placement fault:
**`corexp` is the "Exploiter", an Armed Metal Extractor.** It has a weapon, no
build options and does not move, so `ProtClassOf` filed it as ground defence and
the protect market bought it as a turret -- **299 of 397 defence placements** in
a 12-game batch, sited by defence value instead of on a metal spot. Same family
as the Juno bug. `ProtClassOf` now returns -1 for anything that extracts metal:
an extractor is the mex want's business.

Measured, 12 games paired, before -> after:

| | before | after |
|---|---|---|
| games surviving | 5/12 | **6/12** |
| metal produced | 20,716 | **27,828** |
| army | 9,730 | **13,402** |
| eco | 3,628 | **4,725** |
| defence | 1,928 (9.3%) | **2,805 (10.1%)** |
| defs chosen | corexp 299, corllt 92 | corhllt 280, corllt 86 |

### The remaining rear placements are CORRECT, and the cause is elsewhere
73% of towers now sit forward of the anchor. The 27% that do not are only
marginally behind it (median fwd -0.36 against anchor -0.30) and they are
defending real value: we deliberately put the expensive economy in the deep rear
-- `apex_farm_back = 500`, `apex_fus_back = 700`, so the nano farm sits 500
elmos behind the anchor and the fusion pack 700. `FrontedStakeAt` is plain
distance (the side test was reverted because it zeroed home defence), so a tower
by the fusion pack correctly reads high stake.

So the tower is not misplaced relative to its stake; **the STAKE is in the back
because we put it there.** If rear towers are unwanted, the lever is where the
economy is built, not where defence is sited.
