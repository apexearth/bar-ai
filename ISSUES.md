# Open issues — what is wrong with this AI right now

## NOTE 2026-08-22: the overhaul KILL landed -- leaf-era entries deleted

All AngelScript leaf build/production logic was removed (docs/20-brain-overhaul.md
steps 3-4); the AI is verified silent beyond its pre-placed opening. Entries that
described bugs in the deleted leaf machinery (spend rules, quota/facqueue
composition, plant gates, tier tables, role/rush machinery, eco pipelines,
commander build behaviour) were deleted per the ISSUES lifecycle -- the code they
described no longer exists. Entries about army USE, senses, the engine, the
harness, and the DLL's own native spenders (the C++ strip's census) remain.

## RESOLVED 2026-08-23 (delete after a long game confirms): the engine recruit slip and the defence trickle were the DLL's own spenders, now cut at source

Both unattributed leaks are attributed and severed in C++ (see CHANGES.md
2026-08-23). The recruit slip was `CFactoryManager::CreateFactoryTask` ->
`UpdateFirePower`/`UpdateBuildPower` (response.json recruits reachable via
the DefaultMakeTask fallback); the defence trickle was
`CMilitaryManager::MakeBaseDefence` filling `buildDefence` on first-factory
finished (FactoryManager.cpp:1261) and `UpdateDefence` enqueuing it on a
timer -- a path that never consults `AiMakeDefence`. Both now early-return.
Smoke-confirmed: 8-minute 8v8, every apex team allBuilt=armcom only, zero
recruit or defence spend. Delete this entry once a full-length game shows
the same.

## OPEN 2026-08-22: half the army attacks, half walks away — no army-level engage decision exists

apexearth: "we'll have an army that is like... 2000 metal in size next to the
enemy base. 1000 of that metal worth of army will attack and the other half
will go walk somewhere else."

Mechanism, read in `cpp/src/circuit/task/fighter/AttackTask.cpp`:

1. A mixed force is permanently 2+ squads: `CanAssignTo` refuses speed gaps
   over `SQUAD_SPEED_RATIO` (1.5, his 2026-08-19 call) and the same test
   bounds merging via `CheckMergeTask` — co-located squads of different speed
   classes can never combine.
2. Each squad's `FindTarget` prices every fight with ONLY its own members:
   `maxPower = attackPower * powerMod * healthScale * cohesion`. No allied
   term; the friendly squad on the same tile contributes zero.
3. So squad A passes the per-group margin and commits while squad B fails it
   on the same group (`skippedWeak`), elects a different group elsewhere or
   roams (`RoamPos`) — the observed walk-off. The combined force might clear
   the margin each half fails; the check punishes the split the squad rules
   impose.
4. Only the killing blow counts the whole army (`OurArmyNow` vs
   `FoeMobileMassing`), and it waives the weakness test globally while on.

Same family as the DEF-chase entry above: per-squad, value-blind election
with no shared intent. Candidate fixes (C++): (a) allied-power term in the
`groupWeak` test — count other attack squads within support range / on the
same group; (b) target gravity — a group a friendly squad already targets is
biased for nearby squads; (c) shared target across speed-split squads.
Direction not yet chosen by apexearth.

## OPEN 2026-08-22: commander D-gun chase — distracted by any enemy in LOS, wipes his queue

apexearth, watching: "commanders sometimes get distracted by enemy units, chase
after them a moment, then forget what they were originally doing afterwards."

Mechanism, read in code (stock CircuitAI, present in our DLL):

- `IBuilderTask::AssignTo` (`cpp/src/circuit/task/builder/BuilderTask.cpp:143`)
  arms `CDGunAction` with range `max(dgunRange, LOS radius)` — commander LOS
  (~700) dwarfs D-gun reach (~225), so ANY enemy the commander can see
  qualifies.
- `CDGunAction::Update` (vendor `unit/action/DGunAction.cpp`) then calls
  `ManualFire` → `unit->DGun(target, ALT|CTRL, 5s timeout)`. A unit-target
  D-gun order with no SHIFT REPLACES the commander's command queue and walks
  him toward the target until in D-gun range — that is the chase — and
  re-triggers every 4 action updates while anything stays in LOS. The build
  he was on is wiped; after the timeout he depends on the travel action / a
  re-election to resume, and the commander is excluded from
  `HoldDefenceInProgress`, so a half-built sentry is where the walk-away is
  most visible (see CHANGES 2026-08-22 mex sentries — adopt-orphan recovers
  the frame but not the commander's time).

FIX LANDED 2026-08-22 (see CHANGES same date), awaiting confirmation from a
watched game: builder-task and builder-patrol D-gun actions now arm at
`GetDGunRange()` instead of the LOS max — his direction ("Ignore those minor
threats"). Built, deployed, smoke-gated. Delete this entry once a watched
game confirms the commander stays on task with enemies in sight.


## OPEN 2026-08-22: whole army leaves the base to DEF-chase one unimportant unit; base dies

apexearth, watching live: "our entire base die[s] because our army was doing DEF
chase on a single enemy unit. Our entire army walks off to chase a very
unimportant enemy." Repeated report — see also 2026-08-21 "petty raiders" in
`DefendTask.cpp` (that fix added `apex_chase_min_ratio=0.15`, and this still
happens, so the gate has holes).

Candidate mechanisms, all in `CDefendTask::FindTarget` (cpp mirror
`cpp/src/circuit/task/fighter/DefendTask.cpp`), none yet attributed:

1. **`atUs` bypasses the ratio gate entirely.** Anything within
   `highestRange + 500` of the pool (highestRange is LOS radius, so ~1000+
   elmos) is elected regardless of worth, and the whole pool paths to it.
   A scout brushing the bubble drags the army.
2. **The threat of a lone unit is priced as its NEIGHBOURHOOD**: `eThreat`
   takes the max of the (dead) threat map and ALL enemy group influence
   within 800 of the target. A worthless unit standing near any real enemy
   group passes the 15% ratio easily — and the pool then walks at the group.
3. **Election is nearest-first and value-blind** (stated in the code), so
   among electable enemies a scout wins over the actual army.
4. Defend influence from our own buildings makes any enemy inside our base
   electable by every pool on the map (`GetAllyDefendInflAt` clause) — right
   response, but combined with (3) a fast raider circling the base can steer
   the whole army.

Instrumented 2026-08-22 rather than guessed at: the chase ping now reads
`DEF n=<size> > <unitname> <atUs|post> e=<threat>`, so one watched game
attributes which clause fired. Attribute before changing any gate.

Same day, apexearth set the rule and the ratio was raised 0.15 -> 0.5 with
the home ring exempt ("ignore enemies less than half their strength unless
we need to defend the home base"). Holes (1) atUs bypass and (2)
neighbourhood threat pricing remain by design/unattributed -- the ping's
`atUs`/`e=` fields are the attribution if it recurs.

Brief was: more aggressive, win more quickly, without sacrificing economic
scaling. Every arm below is 16 games against `BARb:stable:medium`, 2v2, +40%
handicap, 50-minute cap, four maps, side-swapped, against a matched control run
in the same window. Shipped default measured 62% at 42.1min with mex 111 and
16.5k metal/min; NOTHING beat it on both axes.

| hypothesis | verdict | evidence |
|---|---|---|
| `apex_kill_from=0` earlier killing blow | rejected | kill/loss 0.30 vs 0.44 |
| `apex_seen_halflife=180` | rejected | lost win rate + trade in two separate pairs |
| `apex_push_team_ratio=1.25` | rejected | 10W-2L-4D vs 12W-1L-3D, 2min slower, mex 89 vs 104 |
| `apex_budget_live=1` (the cached-curve bug fix) | noise | 23W-8L-9D vs 20W-10L-10D, metal rate -21% |
| live curves + army funded from defence | rejected | 44% vs 62%, 2.4min slower, mex 98 vs 111 |
| `apex_withdraw_odds=1.1` | rejected | 2.4min FASTER and trade 0.67 vs 0.63 on maps A, but 44% vs 56% and metal rate -37% on four FRESH maps; pooled 53% vs 59% |
| `apex_withdraw=0` (never withdraw) | rejected | 50% vs 62%, slower, despite the best trade of any arm (0.76) |
| `apex_gantry_per_income=75` (double the T3 commitment) | rejected | 47% vs 59% pooled over BOTH map sets; 3.1min faster on B, no change on A |

THE RESULT IS A FRONTIER, NOT A MISSING SETTING. Pooled over 32 games each,
across two independent four-map sets:

| config | record | mean win time |
|---|---|---|
| shipped default | 19W-6L-7D (59%) | 43.2 min |
| `apex_gantry_per_income=75` | 15W-7L-10D (47%) | 41.7 min |
| `apex_withdraw_odds=1.1` | 17W-9L-6D (53%) | **40.9 min** |

Every config that closes faster costs win rate, roughly 2 minutes per 6 points.
Nothing found buys speed for free, so the default ships unchanged. If a faster
finish is wanted at a known price, `apex_withdraw_odds=1.1` is the best point
measured (-2.3min for -6 points) -- and note it is map-dependent: it held win
rate on the richer map set (62%, -2.5min, economy -4.7%) and collapsed on the
small/poor one (44% vs 56%, economy -37%).

TWO METHOD TRAPS BURNED HERE, both worth not repeating:
- A 30-minute cap gave 15 draws in 16 games and read as "the AI cannot finish".
  At 50 minutes the same build wins 56-62%. Never judge closing speed on a cap
  the games do not clear.
- `mex` and `metalProduced` are CUMULATIVE, so an arm whose games end sooner
  looks economically worse for that reason alone. Compare metal/MINUTE.

WHAT THE EVIDENCE POINTS AT: army trade efficiency, stuck at 0.6 in every arm.
Not thresholds, not budget. `deaths.py` across these runs: 42-56% of lost metal
dies with curTask=retreat, 1-2s after the order, at 9-16% HP, while the
"died fighting" bucket is under 1%. Both naive readings of that were tested and
both failed (retreat sooner = O; never retreat = P), which means the fix is not a
threshold on the existing mechanism -- it is the engagement/approach machinery
itself (the threat-blind approach path and solo reinforcement trickle already
recorded above). That is a C++ build-and-measure project, not a tuning pass.

## OPEN 2026-08-21: commander stands on hot ground for minutes, then dies inside one volley

Forensics over 8 com-death losses (both 1v1 arms): SLOW EXPOSURE dominates
(4/8) -- the commander holds a build task at ~100% hp on ground reading
enemy influence 10-100+ for 5-9 MINUTES, then one volley crosses
COM_RETREAT_HEALTH (0.85) and apex_comm_flee_hp (0.55) both, dead in 2-10s.
DISTINCT BUG found in t003 (retreatfmt arm): 10+ "apex: commander leaving"
lines over 7 minutes with ZERO net displacement -- Retreat() fires but the
commander never moves; the DEAD-MAN direct CmdMoveTo is never reached while
the soft RETREAT task is held. A/B running: apex_comm_flee_hp=0.85 modoption
(arm the guaranteed move where the soft retreat already triggers). If
commLost is unchanged there, the trigger is not the bottleneck and the
class-B fix must be influence-time-based instead (leave ground that stays
hot, post-T2).
## STATE 2026-08-20 (end of the balance campaign): stance layer live and measured; commit keeps its default with the plateau valve

The eco/army balance loop closed with measurements on each leg:
1. BALANCE: army targets 0.30 (his call), eco absorbing; mexup and cheap
   generators never defer; energy race 86-113% at 10m in every audited game
   (was <50%); first-ever Prismatic wins (48m, 58m, one with mex 122v59 and
   con attrition 15v74 in our favour).
2. T1-COMMIT: keeps default-on WITH the income-plateau release (tempo while
   T1 income grows, tech the moment it flattens, latched). Paired A/B:
   commit+valve 2W-0L-4D vs always-scale 0W-0L-6D, and the commit's winners
   held MORE T2 at 20m. The trap eras (commander-release bug, unreachable
   income-80/45 expiry) are documented above and fixed.
3. STANCE (stance.as): AGGRESSIVE/PASSIVE/UNKNOWN with split thresholds +
   300-metal seen-floor (a lone scout no longer toggles the budget), 30s
   dwell, opening guard. Isolation A/B pooled over two rounds, same seeds:
   ON 3W-0L-3D vs OFF 1W-0L-5D. Blind (UNKNOWN) dwell measured at 0-2.8m
   per 35m game; the scout demand now lands on GROUND scouts (the air eyes
   floor is unreachable in duels).
Open frontiers carried forward: finishing (draws still dominate at caps),
engineer escorts (entry above), flak SPREAD placement, the T-cross C++ items
2-3, and the stance A/B is n=6/arm -- direction consistent, power modest.

## PARTIALLY LANDED 2026-08-20 (items 1 of 3): pre-contact assembly — units enter fights piecemeal; "cross the T"

STATUS: the assembly gate (item 1 below) is BUILT, DEPLOYED and crash-clean
(4 smoke games, 2W-2D, no 0xc0000005, no dup bindings) but fired ZERO times
— the cohesion bound max(SQUARE_SIZE*8*n, highestRange) appears looser than
real approach stretch, and most piecemeal arrivals are DEFEND-pool units
(item 3) which never enter attack squads at all. Next C++ session: log the
stretch distribution at every ENGAGE (one throttled line) to size the bound
from data, then the DefendTask half. Items 2 (approach speed clamp at the
default-arg ActivePath callers) and 3 remain. Code: AttackTask.cpp/h
(assembleUntil, apex_assemble/apex_assemble_secs tunables), captured in
cpp/ and 0003-cumulative.patch.


apexearth: "When you're about to get into a fight, you need to organize your
units so that all of them enter the fight at about the same time. This means
spreading your units out, crossing the t." What exists (cpp/src
SquadTask.cpp): the travel WALL (ActivePath spreads line-abreast,
per-neighbour spacing, charger D-gun gaps) and REGROUP — but regroup is
forbidden near threat (GetThreatAt >= THREAT_MIN -> ROAM), runs every 16th
update only, and never in ENGAGE, so mixed speeds shear the wall apart on
approach and the fast units arrive first. Spec, all C++:
1. ASSEMBLY GATE: when the squad target enters an approach band (~1.5x the
   squad's highest range), fast movers hold on a standoff line perpendicular
   to the enemy bearing until the slowest member reaches formation (bounded
   wait), then all commit together.
2. SPEED MATCH: clamp per-unit speed to squad-slowest inside ActivePath so
   the wall survives the approach.
3. DEFEND POOLS BYPASS EVERYTHING (existing #1 issue): CDefendTask travels
   on raw fight orders with no squad shape; most real fights are defend-pool
   fights, so most fights never see the wall at all. Needs the same
   ring/wall treatment as Attack — a plain order swap breaks can't-fire-
   on-the-move units.
Measure by arrival spread: per battle, the time between a squad's first and
last member's first contact (battles.py has deaths+snapshots; a contact
event needs either the 10s snapshot approximation or a dev-gadget damage
event). Tightness timeline (battles.py) is the standing before/after.

## OPEN, DECISION FOR APEXEARTH: personas dominate 1v1 variance — AIRBOSS/SILOIST roll into games they cannot win (2026-08-20)

Across the day's Comet Catcher batches, 3 of 8 games opened AIRBOSS (the
"advanced air plant at 16-21m of a losing ground war" games are these) and 5
of 8 adapted into SILOIST (6k+ metal of nuke silo that never fires inside a
35m benchmark cap). With `--modoption apex_persona=0` (STANDARD) on the same
4 seeds/build: 1 win, 3 draws, ZERO losses, army K/D 1.46 vs stock's 0.41 —
the mechanics out-trade stock 3.6:1 once the dice are removed. Questions for
apexearth: (a) should some personas be excluded or re-weighted in 1v1s (the
persona charter says biases-never-gates, so maybe their multipliers need a
game-size term)? (b) the eco-vs-army share fork: at benchmark scale we hold
0.36-0.46 eco share vs a 0.24-0.30 target while army sits under — cutting
eco to feed army would convert draws but trades away the compounding that
wins hosted games. Both are policy, not mechanism; the diagnostics to
measure either decision are in place (budget log, army-census, battles.py).

## PATCHED 2026-08-20, NOT YET MEASURED: the aggression gate held while we outfielded the enemy — three stacked reading biases

The army never attacked (army-census: zero f5 tasks across whole games) even
at a standing-army and economy lead, so every lead ended as a timeout. Three
mechanisms, each confirmed by the census diag before patching:
1. `EnemyMassingThreat()` counts 0.5x their STATIC defence — by mid-game more
   than half the "enemy army" was towers (foeMass 3032, foeStatic 3493).
   Patched: `FoeMobileMassing()` strips the static term (tunable
   `apex_feed_static_w`, default 0) in ConservativeStance and the feeding
   test only; MassWant still counts static for group sizing.
2. `TeamArmyCost()`/armyCost read ~40% of the field telemetry (2054 vs
   armyReal 5500). Patched: `OurArmyNow()` floors it with `gTrackedCost`,
   the live cost of the withdraw register's units.
3. With 1+2 fixed, the fog clause (`theirs < ours*0.5 -> hold`) took over:
   being 2x ahead is indistinguishable from being blind ("outmatched 2198 vs
   4567"). Patched: fog-hold requires `gSeenPeak > floorSeen` — a low reading
   is fog only if they ever showed an army that size.
Measure on: f5 tasks appearing in army-census, timeouts converting to
decisions, and battle-summary exchange — not win rate alone.

## OPEN: GetUnitLimit reads 15750 in a 1v1 — BAR's dynamic-maxunits gadget hands Gaia's leftover pool back uncapped (2026-08-20)

`maxunits=2000` is in the start script's MODOPTIONS and run_match.py has set it
since the "twenty thousand raiders" fix, yet the facqueue log in
matches/20260820-070319 shows `slots=15745 limit=15750` — exactly
(32000−500)/2. Mechanism, read in BAR.sdd
`luarules/gadgets/game_dynamic_maxunits.lua`: Initialize() collects every
team's maxunits into Gaia, deals each team its capped share (min(share,
modoption maxunits) = 2000), then hits the `gaiaCurrentMax > gaiaExpected`
branch and distributes Gaia's ~27.5k excess "fairly to all alive regular
teams" — with no cap in that branch. Small games inflate hugely (1v1 →
15750/team); a full 8v8 has no excess so stays ~2000. This is upstream BAR
behaviour, so REAL hosted small games run inflated too. Consequence for us:
`SlotsForArmy()` (facqueue.as:173) sizes every combat want off it —
armflash want 3979 — so quota "wants" are unreachable and the mix is decided
purely by deficit ratio. In the observed game the relative mix was still
share-shaped, so this is a latent distortion, not the cause of the loss; but
any logic that treats want-vs-have fill fraction as meaningful (floors,
line-quiet checks) is reading a fiction in small games. Fix candidates:
derive slots from economy instead, or clamp by the modoption read directly.

## OPEN: DEFEND pools march and hold on raw CmdFightTo — the last fight-order holdout (2026-08-19)

The agreed move+SetTarget doctrine is fully live in ISquadTask::Attack
(standoff ring, orbit, kite, threat-compared steps), but CDefendTask still
issues engine fight orders at three call sites (DefendTask.cpp:114,256,484)
and uses CFightAction as its travel action — so pool members wade toward the
nearest enemy while marching or holding, no standoff, no kite. Most fighting
deaths concentrate in DEFEND tasks (f2: 9.6k metal in the 40m baseline, 7.3k
in the 2026-08-19 live game), so this is where the "walk up close and get
creamed" losses live now that retreat pathing is fixed (a8851c6) and the kite
floor covers mid-range rows (a659a3e). Fix needs care: a plain move-march
would walk past enemies without firing (most units cannot shoot on the move),
so the march likely needs the same ring/target treatment as Attack rather
than a blind order swap. Own measured pass; check fight1v1 K/D and per-task
death buckets (tools shown in the 2026-08-19 session) before/after.

## OPEN: the hosted-MP desync netmatch is still unrun (2026-08-18)

Four DLL changes landed 2026-08-18, ending in the asPrepareMultithread fix
for host-process heap corruption — the one AI bug class that CAN desync a
host. Single-process harness games cannot test sync. Before hosting for
real: a lobby with any second client connected for 20-30 min through a
commander death. Harness has no host+join mode yet; building one is the
automation option.

## OPEN: secondary variants (ctl/ord/stk) still carry the guessed Legion names (2026-08-18)

`legamsub`/`legplat` exist in NO tree — they were guessed mirrors of
armamsub/armplat; Legion's real defs are `legamphlab` (both trees) and
`legsplab` (upstream-only). Fixed in `ai/apex` 2026-08-18; `ai/ctl`,
`ai/ord`, `ai/stk` behaviour_leg.json (and two block_map.json) still have
them. `leggantuw` is correct and deliberately kept: apexearth wants
defined-but-unavailable extra units tolerated as forward-compat, and
check.py now warns rather than errors for names the reference tree knows.

## OPEN: late-game slowdown is now ENGINE world-state buildup, not AI code (2026-08-18)

After the 12-sim perf campaign (two clean 60m 8v8 mirrors, every minute
above 1x headless), apexearth still sees 0.7x on his rendered client and
"continuously getting slower... like a memory leak." Measured in his live
90m watch game (frametime per-minute, min 34->55): total frame 24.7->40.6ms
while the AI SHARE FELL 38%->~30% -- engine sim grew ~15->28ms/frame, ~80%
growth on +45% units. Superlinear: the accumulating term is world state --
90 minutes of 16-player wreckage/debris features that never leave (each in
collision/LOS/path queries forever), unit population drift, and the enemy
ghost registry (the AI-C++ 6->9 s/min creep). Levers, all behavior-positive:
(1) rez fleet scaled to the observed wreck field, systematic sweeps -- his
standing rezbot complaint is now also the top perf fix (eaten wreck =
deleted engine object + our metal); (2) fewer-bigger-units late-game
composition (T3 shift) cuts live units and corpse rate; (3) C++ ghost purge
for hidden enemies unseen >10min (careful: GetEnemyCost pessimism relies on
remembered units -- purge must not decay the role-cost counters, or must
only purge past timescales where the pessimism no longer helps). Validate
with the existing 60m 8v8 mirror harness.

## OPEN: fighting groups stay 1-2 units at minutes 3-10 even with the quota raised (2026-08-17)

The early-bleed session (6x20m 1v1 tournaments, Comet Catcher) raised the
massing want from 5 to 15-25 power pre-T2 (`apex_unseen_parity`) — and the
`apex: squadsize` sampler still read own avg 1.6-1.9, max-mean 2.4-3.0 at
minutes 3-10, barely different from baseline. Two mechanisms sit between the
quota and the field: (1) `apex: mass hold expired, committing at 15` fires as
early as minute 2 — the hold-deadline (`gHoldSince`) trims the raised want;
(2) DEFEND pools fill one fresh unit at a time and the sampler counts them
while filling, so the bottleneck may be fill RATE (factory output split
across several pools?) rather than the promotion bar. Attribute before
touching: log per-pool fill counts, then decide. Related: the K/D plateau —
0.334 baseline rose to 0.44-0.51 across the day's three fight levers and sat
there; the remaining deficit is engagement shape (rally-before-crossing entry
below), not quota size.

## OPEN: reinforcements stream to engaged squads one at a time (2026-08-17)

apexearth, watching: "I even see us have solo units that dive into enemy
armies and die." One mechanism fixed same day (the blanket inTheirBase
strength-test waiver in AttackTask::FindTarget let any unit on enemy
influence engage at any odds — scoped to fat-eco dive targets only). The
remaining half: a unit assigned to an already-engaged attack task travels
to it ALONE through contested ground; there is no rally-then-move for
reinforcements. Fix direction: reinforcements gather at a merge point (or
attach to the nearest friendly group heading that way) before crossing the
front. Untouched — needs its own design pass in SquadTask assignment.

## OPEN: base axis 180-flips away from the enemy on corner starts (2026-08-17)

apexearth, watching: bottom-left player faced factories and its Doomsday
LEFT (map edge). Mechanism read from axis.as: bands grow REARWARD from the
anchor, so on a corner start the enemy-facing axis pushes the band into the
map edge, the flipped axis doubles the buildable-cell score, and the
`s > front * 2` rule takes the flip — after which every axis consumer
points backward. Facing is now decoupled (GetBaseGridFacing tracks the
enemy bearing, axis only as fallback), but the band itself still lays rear
rows TOWARD the enemy on flipped starts, and front-relative placements that
read gFwd remain suspect. Real fix: separate "band growth direction"
(terrain question) from "front direction" (enemy question) in axis.as.

## OPEN: combat conversion -- army trades at ~0.5 K/D in metal and cannot finish a 2x lead inside 30 minutes (2026-08-15)

2026-08-16, apexearth watching a Red Comet 1v1: "we really aren't good at
early game fighting. kinda feels like the [enemy] AI makes larger squads,
or maybe we were just behind" -- the same-day tournament rules out
"behind" (metal produced 1.6x stock) and matches the standing "two v six
battles" report: engagement size, not economy. Squad massing / commit
thresholds are the place to look.

Measured (Red Comet 1v1, 20260816-221919): engage-decision squad sizes
units=1 x31, units=2 x19, units=4 x28 -- the modal fighting group is 1-4
units. The engage TEST (AttackTask.cpp, margins/edge) is fine; the squads
ASKING are too small, so the fix is upstream: squad formation/merge size,
not the commit threshold.

THE strategic deficit, measured across 56 tournament games tonight: we
out-produce stock ~2x and lead 26/32 games at the 30-minute cap, but army
K/D in metal is 0.33-0.82 against stock's 0.92-1.42 (`tools/fight1v1.py`
per tournament; note the noise floor -- two IDENTICAL baseline runs
scored 0.82 and 0.59, so single-tournament K/D deltas under ~0.3 are not
signal). 28 of 32 random-map games timed out undecided.

**Vision fixed, trade unchanged.** The first mechanism found was
blindness: `apexfoe raw=0` for the first 14 minutes of the worst game
(K/D 0.10), enemy model ~500 vs a real 3000+ army at 30m, radar ~3 towers/
game -- `CMilitaryManager::DefaultMakeSensors` refuses to place radar
inside our own zone (`IsZoneAlly` early-return, MilitaryManager.cpp:1060)
and only fires at contested clusters. Landed `Builder::RadarNet`
(statics.as; ledger hooks in main.as `AiUnitFinished`/`AiUnitDestroyed`,
which were engine-looked-up but unimplemented): territory-centre-then-
border-ranks anchor ladder, standing-position ledger so dead radars
re-open their rank, coverage scales with ground held. CONFIRMED WORKING
(coverage grows, enemy model reads 1000-2300 late-game instead of ~300)
-- but the 12-game re-run's K/D was 0.33, no improvement. Vision was
necessary, not sufficient.

**MEASURED 2026-08-15: the isHome exemption covers the map, which is why
nothing else moves the needle.** `CAttackTask::FindTarget` waives the odds
check entirely wherever net influence >= INFL_SAFE (2.0). The `home-edge`
sampler (massing.as, 60s cadence) across the 12-game engage-neutral
tournament: median **85%** of the base->enemy axis reads as "home"
(p25 67%, p75 95%, n=294). Every odds-related fix so far (scale-units bug,
trade-scaled margins, thrMod 0.6-0.8 -> 1.0 neutral, radar-net vision)
sits BEHIND this bypass on the ground where most fights actually happen --
measured K/D across four tournaments: 0.82 / 0.59 / 0.33 / 0.48, all
noise-band, no fix moved it. **Scoping fix LANDED 2026-08-15, apexearth-approved** ("Sounds like the
right fix"): `isHome = inflMap->GetAllyDefendInflAt(group.pos) > INFL_EPS`
(AttackTask.cpp) -- the defence-influence field around actual defence
structures instead of anywhere our units have walked. First 12-game
measurement (`tournaments/20260814-233602-ishome-scope-check`): K/D 0.635
-- best of the last four same-map runs (0.59/0.33/0.48) but still inside
the two-identical-baselines noise band (0.59-0.82), so NOT yet claimable
as an improvement; 8/12 games decided (6-2), the most decisive run of the
night, zero crashes. Needs either a large batch or apexearth watching to
close. Also landed this pass: army-scaled squad floor
(`Military::MassFloor`, `apex_mass_per_army` 0.0017, binds at hosted-game
scale, benchmark unchanged) and quota.attack now tracks want both ways
(the up-only ratchet would have wedged after losing a scaled-up army).

**Where the deficit actually lives, still open:** which fights get taken.
The army bleeds continuously (army value FALLING minute-over-minute while
the enemy's rises, e.g. 1870->937 over minutes 18-21 of t012) rather than
dying in a few big pushes -- piecemeal engagement, not one bad battle.
Next investigation belongs to military-engagement: massing/attack-quota
behaviour with a material lead, and the still-unmeasured standoff/
fragility passes in the entries below. A watched game is the right next
instrument -- the benchmark's noise floor cannot rank engagement changes.

Related fixes landed the same night (both STOP-class, measured firing):
rez bots (no buildoptions at all) routed out of the build pipeline
(maketask.as -- was 1443 blocked tasks/game); `GuardBuildCapability` no
longer nulls REPAIR/RECLAIM/RESURRECT tasks, whose buildDef is the
TARGET's def, not a construction (was silently killing commander assists,
291/game). Blocked-task log: 497 -> 11 per game.

What is broken or missing, with the evidence for it. `CHANGES.md` says what was
done; `USER-FEEDBACK.md` is the standing brief; this file is the live list.

---

## PATCHED, NOT YET MEASURED: commander lost with a clean threat sample 930 frames before death -- flee-influence tunable turned on (2026-08-14)

apexearth watched a match live and reported "our commander was being too brave."
Confirmed against that same match,
`matches/20260814-233416-Apex-apex-hard_aggressive_vs_BARb-stable-hard/infolog.txt`:
`COMMANDER LOST frame=27675 hp=-2`, and the last `apex: comm threat=` sample
before it, 930 frames (~31s, one sample period) earlier at frame 26745, read
`threat=0.00 hp=100`. The commander died alongside a cluster of other units
sharing its build task (`armrectr` x3, `armwar` x2, `armck`, `armjeth`,
`armmex`) all at the same position, all destroyed in the same tick -- a
sudden local strike, not a slow attrition the periodic threat sample could
have caught. Not offensive risk-taking (the commander has no combat/attack
logic and is excluded from `Fortify`/squad combat) and not a rule sending it
somewhere dangerous (its last accepted task, `mexup`, was ~900 elmos from the
death site). This is trap #2 from `commander-opening`'s domain notes,
reproduced: local threat reads clean right up to death.

**Patch:** `manager/builder/rules_commander.as`'s `apex_comm_flee_influence`
tunable already existed for exactly this (enemy INFLUENCE at the commander's
own tile, which is not fooled by a killer at range the way the threat map
is) but shipped compiled-default 0 (off), "no measured threshold." Turned on
at 0.01 -- the same "any nonzero `GetEnemyInflAt` reading = attacked"
calibration `BaseUnderAttack()` (`converter.as`) already uses, not a new
invented number. **Not deployed or re-run** by this pass (out of scope for
the agent that made it). Confirm on the next watched/tournament run: does
`commLost` improve, and does `apex: commander leaving, enemy influence`
actually fire before a death instead of after. Delete this entry once
measured.

---

## FIXED 2026-08-19, BATCH PENDING: the army fed itself to a superior enemy

apexearth, watching a 4v4: "we're so often leaving the base with smaller numbers
of units than the enemy, and our guys just die, and the enemy keeps building up
a stronger and stronger army... we act like we're all tough and take on enemy
armies twice our size."

Measured end-state of that game (`matches/20260820-024449-...`):

```
apex: mass want=299  floor=5  army=570  enemyArmy=104580  ratio=183.47
apex: squadsize own n=0 avg=0.0 max=0 | enemy n=11 avg=8.4 max=26
apex: budget army=0.13/0.29 bp=0.37/0.20 ... raw army=38049
```

38,049 metal of army BUILT, 570 standing. Production was never the failure --
we fed it in. Three mechanisms, all self-reinforcing:

1. `MassFloor()` is a share of OUR OWN standing army, so as the army dies the
   floor falls (it read **5**, one or two units), smaller groups leave, they die
   faster, the floor falls further. Nothing pushed back.
2. The `apex_mass_hold_secs` deadline force-commits a group after 120s of
   holding "so the ratio can change". At 183:1 the ratio cannot change. It
   **fired 55 times in one game**, each firing a group handed over.
3. Nothing asked whether we were the aggressor. We were below our own army
   spend target (0.13 against 0.29) while they out-fielded us 183:1, and still
   attacked.

Fixes (`military/massing.as`, `military/hooks.as`):

- `EnemyGroupPower()` -- the biggest enemy group we can see, as power. `MassFloor`
  is now bounded BELOW by it (`apex_mass_meet_frac`), so the floor cannot follow
  our army down. If we cannot reach it we do not go, which is the point.
- The deadline is suppressed while outmatched (`apex_mass_no_commit_ratio`) or
  while `ConservativeStance()` holds. Holding forever beats feeding; the
  outmatched branch releases by itself as the pool rebuilds.
- `ConservativeStance()` -- apexearth's doctrine: below our own army spend target
  while they out-field us means we chose economy and they chose offence, so the
  army we bought is for holding. It routes new units into the MELEE-promoting
  pool that never leaves, the same mechanism the defend-home branch already used.

Measured, same map/seed/settings, 4v4 32min:

| | before | after |
|---|---|---|
| our standing army | 570 | **16,212** |
| enemy standing army | 104,580 | **27,685** |
| army:enemy ratio | 183.5 | **1.71** |
| our squads | n=0 | n=2, avg 3.5-4.5 |
| mass floor | 5 | 225 |
| army spend share | 0.13/0.29 | 0.32/0.30 |
| build power share | 0.37/0.20 | 0.18/0.20 |
| players reaching T2 | 0 | 4 |

Both sides of the army ratio moved, which is the tell: we stopped feeding, so we
accumulated AND they stopped growing on our losses. Single seed at this point --
6-game batch running. Re-check before deleting this entry.

## FIXED 2026-08-19: the chokepoint logic was computed and never called

apexearth: "I think we have some 'chokepoint' logic somewhere. We should identify
where the chokepoint is and make defenses right behind it."

`Front::FrontChoke` (`frontline.as:462`) existed, was fully implemented, and had
**zero call sites** -- the engine's chokepoint bindings were gathered every game
(`frontline gathered 8/8 usable chokepoints`) and consumed by nothing.

Wired as a RANKING TERM in the Brain's existing front-defence want, not as a new
spend rule: the same towers, sited better. `Front::ChokeAt` marks a front spot as
a doorway and `Front::BehindChoke` steps the position back toward home by
`apex_choke_back` so the gun shoots INTO the gap rather than standing in it. A
choke spot outranks a barer stretch of open line. 12 placements in the first
4v4; no measured displacement (defence share 0.09-0.12 against a 0.08 target).

## FIXED 2026-08-19, NOT YET COMPOSITION-MEASURED: the under-attack trigger never fired

`BaseContested()` (`territory.as:1132`) is `GetNetInflAt(gHomePos) < 0` -- net
influence at our START POSITION, which our own buildings dominate. Measured from
the `defcap` log line across five runs: `contested=0%` of samples in four of
them, never above 9%. Every escalation meant to answer an invasion hung on it --
`PanicBuild()` (defcap.as), `pressureAllow` and the `ForwardFraction < 0` rear
exemption (defenceline.as), plus the army's own responses. An enemy could walk
in, kill a T2 lab and leave without it ever reading true (apexearth, watching:
"they killed our T2 lab and then we did not build any defenses").

Separately, `AiUnitDestroyed` already carried the position and cost of every
structure we lose and nothing consumed them -- the combat ledger filters to
`IsMobile()`.

Fix: `Military::NoteStructureLoss` / `BaseRaided` / `RaidPressure`
(`military/basedefence.as`) -- finished immobile losses at `ForwardFraction <=
FWD_HOME`, decayed over 60s, feeding the SAME incoming signal the approach
sensor sets, so `Builder::PushAnswer` answers with the tier, siting and metal
sizing it already had. `RaidPressure` is graduated (lost metal against a minute
of income), which also closes the "boolean, not graduated" complaint below.

Confirmed firing, `matches/20260820-023454-...`: six raid windows out of a
possible 54, ~11% duty cycle (defcap's own bar for "is this an exception" is
20%), escalating 60 -> 1508 metal, one `push answer armclaw` at 615/1136 metal
vs 2840 incoming -- in a game where `contested` read 0-4% throughout. NOT yet
judged on composition: run `tools/composition.py` against a control before
calling it good.

Still open underneath it: the local/rear branch of `DefenceAllowedAt` clamps to
`min(income budget, mexCount * 1.5 + 1)`, so base-interior defence is bounded by
a MEX COUNT that pressure cannot lift -- `pressureAllow` is multiplied into
`budget` and then thrown away by the `min`. Suspected second cause of the same
complaint; not touched in this pass.

## SUPERSEDED by the above: defence's under-attack escalation is a boolean, not graduated by severity (2026-08-14)

apexearth wanted excess con power redirected into defence during a sustained
attack. That mechanism already exists and was firing correctly in the match
that prompted the request (`defenceline.as:422`, `pressureAllow = (gTurtle ||
BaseContested()) ? 2.f : 1.f` — doubles the front-line metal budget;
`BaseContested()`, `territory.as:1041`, reads live net influence at home, not
economy). See `changes/2026-08-14.md` for the full telemetry from
`matches/20260814-225550-...` — `mDefence` climbed through the loss window and
requests (`armllt`/`armbeamer`) kept firing at rising cap right to shutdown;
the base was lost to total overrun in the final ~60-90s, not to defence being
undervalued or under-requested.

Left open only because the escalation term itself is coarse: a flat 2x that
trips only once the enemy already holds net influence at home (late), rather
than scaling with how badly we're losing (`EnemyArmyCost()/armyCost`,
`GetAttackHotspot` weight, or recent-loss rate as a leading indicator). No
patch proposed — one match showed the pipeline working, not failing, so
tightening this without a match that shows genuine under-firing would be
tuning on impatience rather than evidence (see CLAUDE.md "Ask before inventing
policy" / "Economy over static numbers"). Re-open with real evidence of
under-request before touching `pressureAllow`.

## OPEN: rez-bot repair fix lands only after a DLL rebuild+deploy -- not yet live-confirmed (2026-08-14)

apexearth, live: "we have a lot of rezbots standing around doing nothing while
units next to them need to be repaired." Root cause and fix in
`changes/2026-08-14.md`: `CBuilderManager` never registers a `damagedHandler`
for ordinary mobile combat units (only for builders/rez-bots' own damage and
for static structures), so no REPAIR task is ever created for a hurt unit in
the field. Added `CCircuitAI::GetOwnDamagedNear` (C++,
`cpp/src/circuit/CircuitAI.cpp`/`.h` + `InitScript.cpp` binding) and
`Builder::RezzerRepairNearby` (AngelScript, `manager/builder/rules_rezzer.as`,
wired into `manager/builder/maketask.as`). **This needs a `SkirmishAI.dll`
rebuild (`docs/06-building-the-dll.md`) and `deploy_ai.py deploy apex` before
it does anything** -- the AngelScript half is inert until the new
`ai.GetOwnDamagedNear` binding actually exists in the running engine. Delete
this entry once a rebuilt/deployed run shows rez bots picking up REPAIR tasks
on damaged field units.

**2026-08-14 follow-up:** apexearth reported (after this landed, watching a
fresh game) "our rezbots still don't repair fast enough." Found and fixed a
real bug in the same rule: `RezzerRepairNearby`'s throttle (`gNextRezRepair`)
was a single global frame counter shared by every rez bot on the team, so at
most one bot on the whole side could be handed a new repair target per
`REZ_WRECK_PERIOD` (1s) no matter how many were idle. Changed to a per-bot
gate (`gConNextRepair[ConSlot(unit)]`, `manager/builder/fortify.as` +
`rules_rezzer.as`) -- see `changes/2026-08-14.md` for the full writeup,
including why the engine's native area-repair `CMD_REPAIR` (4-param) order
apexearth suggested is not a clean fit here (no C++ binding exists for it, and
wiring it in bypasses CircuitAI's whole task-tracking model). The residual
one-task-one-target-to-completion model is real and NOT fixed by this --
would need new C++ to change. Not deployed/measured this pass.

---

## OPEN: commander and rez bot both idle beside a damaged HLT under fire -- not yet live-confirmed (2026-08-14)

apexearth, live, a DIFFERENT match than the mobile-unit rez-bot fix above: "Our
HLT turret is being shot and the commander and rezbot nearby didn't try to heal
it -- they just sat idle." Distinct mechanism from the mobile-unit case:
`CBuilderManager` DOES register a `damagedHandler` for static structures
(`buildingDamagedHandler`, `BuilderManager.cpp` `InitHandlers`) and it
unconditionally enqueues a HIGH-priority `TaskB::Repair` the instant one takes
damage -- the task exists. Two separate native reasons nobody ever gets it:

1. `CBuilderManager::MakeTask`/`MakeCommTask`'s own ranking loop
   (`BuilderManager.cpp` ~line 1074) skips any task at NOT-`NOW` priority
   (repair is `HIGH`) sitting on ANY negative influence at all --
   `inflMap->GetInfluenceAt(testPos) < -INFL_EPS`, a bare boolean, not a graded
   threat check -- so a structure actively being shot at is by definition never
   offered via `DefaultMakeTask` to anyone.
2. `CBRepairTask::CanAssignTo` (`task/builder/RepairTask.cpp:37-39`) hard-excludes
   `IsRoleComm()` from ANY repair task, structure or mobile, at the native
   ranking layer -- independent of (1), so the commander specifically could
   never take one even from a safe distance.

**Fix (Layer 2 only, no DLL rebuild):** `AssignTask` (`TaskModule.cpp:70-76`)
never re-checks `CanAssignTo` when the script hands back a task directly -- the
same property tonight's `RezzerRepairNearby` already relies on for the
mobile-unit gap. Added `Builder::RepairStructureNearby` (`manager/builder/
fortify.as`), which scans the existing `gStructRepair` registry (already
populated by `AiTaskAdded`, previously used only to abort doomed repairs in
`obsolete.as`) for an unclaimed target within `REPAIR_REACH` passing the same
`ThreatFor <= CON_THREAT_VETO` graded check every other reflex in this file
uses, and enqueues that exact target directly -- bypassing both native gates at
once. Wired into `rules_optional.as` (ahead of `RepairNear`, same reflexive/
ungated slot, non-commander builders) and `rules_commander.as` (right after
`HomeTower`, which only ever builds a MISSING tower and is silent once one
already exists and is merely damaged).

Reasoned from `vendor/circuitai` C++ and existing script patterns, not yet
run. Delete this entry once a match shows a con or the commander taking a
REPAIR task on a damaged structure while it is under fire (`apex: ` log line
would need adding if this needs to be traced explicitly -- none was added this
pass to keep the change minimal).

---

## FIXED (deploy + measure pending): advanced converter/fusion handed to constructors that cannot build them -- 100% failure, not combat losses (2026-08-14)

Root cause isolated from the diagnostic added earlier tonight. New match
`matches/20260814-222654-...`, apexearth live: "we sit at full metal and
aren't building any more energy 15m into the game... stopped making more
energy at around 1200 energy."

**`hadNanoframe` settles it: every single removal is `hadNanoframe=0`.** 24/24
`convert-task-removed armmmkr` and 21/21 `energy-task-removed armfus` events
in this match read `hadNanoframe=0` -- the task never got far enough to place
a nanoframe, let alone lose one to combat. `done=0` on all of them too. Not
combat losses. `manager/builder/events.as:144-149`,
`manager/builder/events.as:130-135`.

**Mechanism:** `tools/unitdef.py armmmkr --builders` / `armfus --builders` --
both are built by `armaca/armack/armacv/armcomlvl5-10/armhaca/armhack/armhacv/
armsack/armsacv` only. **Never `armck`, the ordinary T1 constructor.** But
`Builder::HomeEnergy` (`manager/builder/mexguard.as`) picked `BigConvDef(unit)`
(armmmkr) whenever `EnergyWasting()` was true, and `fus` (armfus/armafus) by
pure energy-per-metal ranking, for **whatever constructor reached the rule** --
no capability check on `unit` at all. `Builder::EcoConverters`
(`manager/builder/converter.as:185-195`) had a matching bug: its `advBuilder`
gate had a bypass, `gHaveAdvCon && SmallConvCount(unit) >= ADV_CONV_AFTER`,
that let a plain T1 con request the advanced converter "on the theory nothing
claims it if it can't build it" -- but `Requests::Take`/`Create` binds the
ASKING unit to the task it just created (`aiBuilderMgr.Enqueue(TaskB::Common(
..., unit, ...))`), so the incapable unit gets attached as a worker
immediately, and the engine drops the task again a few frames later. Same
shape as the already-documented `IsAdvConDef` comment at
`mexguard.as:59-68` ("only armcomlvl4+ can build the advanced towers -- asking
a level-1 commander for one is a silent no-op") -- this bug is that exact
class, just on the reactor and advanced-converter rungs of `HomeEnergy`, which
had never had the same guard applied.

Log evidence, `matches/20260814-222654-...`/infolog.txt: e.g. lines
1993-2021 show the same worker (`unit=20146`) handed a fresh armmmkr task at
five different grid cells in under 20 seconds (2384,3184 / 2192,2800 /
2144,3424 / 2128,2800 / 2000,3184 / 2256,2736), every single one removed
within 2-96 frames (0.07-3s), `hadNanoframe=0` each time. Confirmed with
`[BARAI_STATS]`: `conT2=0` (zero advanced constructors) through frame 14400
(8 minutes), yet armfus/armmmkr requests started at frame 25 (game start,
handed to the commander, itself likely below the armcomlvl5 threshold) and
continued through the whole 0-10 minute window before any unit capable of
building either def existed.

**This also explains "stopped making more energy at ~15m":** once
`EnergyWasting()`/`isEnergyFull` goes true, `HomeEnergy`'s `isConv` branch
takes over exclusively -- it does NOT fall through to the solar/advsol/wind
branch that would add more generators (by design: more generation is
pointless while spilling). With the converter target unbuildable, every
constructor reaching `HomeEnergy` funneled into a doomed armmmkr request and
nothing else, so BOTH more generation and the converter that would have used
the spare energy stopped at once -- not `HaveReactor()` blocking new
generators (that gate is working as intended), and not a real "want stopped
scaling with income" bug.

**PATCH:** `manager/builder/mexguard.as` -- `HomeEnergy`'s converter branch
now uses `IsAdvConDef(unit) ? BigConvDef(unit) : null` (falls through to
`SmallConvDef`, armmakr, which `armck` CAN build) instead of unconditional
`BigConvDef(unit)`; the fusion branch now gates `fus` on
`Factory::HaveAnyFactory() && IsAdvConDef(unit)`. `manager/builder/
converter.as` -- `EcoConverters`' `advBuilder` bypass clause removed; only a
genuine advanced constructor (cost-based proxy, same as `IsAdvConDef`,
excluding the commander for the same unknowable-level reason) may request
`BigConvDef`.

**COST:** none new -- this removes spend on a task class that was never
completing, and lets `SmallConvDef` (armmakr, buildable by the T1 cons that
were being wasted on the broken path) absorb spare energy instead once a
T1 con reaches the rule.
**CONFIDENCE:** high on the mechanism (verified builder lists via
`tools/unitdef.py`, 45/45 `hadNanoframe=0` across both defs in this match,
`conT2=0` through the whole window the earliest failed requests occurred in).
**Not yet deployed or measured** per instruction -- next step is deploy +
watch/`composition.py` to confirm armmmkr/armfus actually complete and
`energyExcess` stops pinning at the storage ceiling.

---

## FIXED (mechanism confirmed live) but SYMPTOM NOT YET RESOLVED: solo tower-dive via LOS-confirmation fallback (2026-08-14)

apexearth, watching, same session as the fragility fix below: "I'll have one
hound standing outside range shooting at a tower, then the next will walk
into range of that tower and shoot at it and die." Root cause in
`CCircuitUnit::Attack(pos, enemy, isGround, isStatic, timeout)`,
`cpp/src/circuit/unit/CircuitUnit.cpp:530-575`: when `enemy->IsInLOS()`
reads false (common for a unit correctly holding standoff at its own weapon
range, which routinely exceeds its sight range -- Hound 650 vs ~400), the
function queues `CmdFightTo(enemy->GetPos())`, walking the unit to the
target's OWN position rather than the standoff ring. Intended for mobile
radar-only ghosts; fires just as often against static towers, whose
position needs no LOS to confirm. Fixed by exempting `isStatic` targets
from the LOS requirement (`CircuitUnit.cpp:551-552`).

**This was built, deployed and watched (DLL timestamp confirmed built and
deployed before the match started), and the symptom was reported again in
that exact watch**: "I see rocket bots walk into turrets and die too...
they out range these things but walk into their death... hounds still make
this mistake." So this fix is real and live, but was not the only cause --
see the next entry for the second mechanism found and patched. Do not
re-diagnose THIS mechanism; the LOS-reissue path is confirmed fixed. Delete
this entry once a watch confirms the second fix (below) closes the symptom.

## PATCHED, NOT YET LIVE-CONFIRMED: standoff margin could land inside a near-parity tower's range (2026-08-14)

Second mechanism behind the same "Hound/rocket bot walks into tower range and
dies" report, found AFTER the LOS-confirmation fix above was already live and
still reproduced. In `ISquadTask::Attack`, `SquadTask.cpp:744-746` (before
this fix): when a row genuinely out-ranges its target (`!outranged` branch),
`standoff` was set to the row's OWN weapon range with no reference to the
target's range at all, then shrunk 10% by `STANDOFF_RANGE_MOD`. Any target
whose range sits within 90-100% of the row's own range then reads as
"outranged" while the shrunk stand-off lands inside its reach anyway --
confirmed with `tools/unitdef.py`: Hound (`armfido`, 650 range) vs `corhlt`
(Warden tower, 620 range): 650*0.9=585 < 620. Fixed by flooring the computed
range at the target's own range (`OUTRANGED_SAFETY_MARGIN`, 1.1x) whenever
this "we out-range them" branch applies and none of the intentional-dive
exemptions (`isArty`/`powerDominant`/`glassCannon`) do.
`cpp/src/circuit/task/fighter/SquadTask.cpp:744-763`. Rebuilt clean via
docker, `sync_cpp.py status` confirms `cpp/`/`vendor` match. **Not deployed,
no match run** -- a watch game was in progress. Delete this entry once a
watched game with Hounds/Rocketeers vs towers shows standoff holding outside
tower range and the "walk in and die" report stops recurring. If it recurs a
THIRD time, check whether Hound/Rocketeer squads route through
`ISquadTask::Attack` at all (task-type assignment in `behaviour.json`) before
patching this file again.

## THIRD PASS, SAME REPORT: re-audited standoff/order path end-to-end, found no bypass for `CAttackTask` -- one narrower, real gap fixed in the SOLO path (2026-08-14)

apexearth pushed back on the pass-2 fix above before it was even deployed:
"that's probably not the real cause because I see them walk much closer than
what you're talking about" -- the 35-elmo band pass 2 closed is far smaller
than what he describes. Also clarified intent: `STANDOFF_RANGE_MOD=0.90` is
deliberate (a buffer against range-flicker), not a bug to relax.

Re-read `ISquadTask::Attack` end to end and `CCircuitUnit::Attack`'s non-melee
branches (`SquadTask.cpp:576-943`, `CircuitUnit.cpp:530-582`) looking for an
ORDER PATH that bypasses the ring position entirely, not another formula
error:
- For a static target, non-ground, non-melee (Hound/Rocketeer vs. a tower):
  `prefer` is unconditionally true (the pass-1 fix), so `CCircuitUnit::Attack`
  issues ONLY `CmdMoveTo(pos)` with `pos` = the ring standoff point computed in
  `SquadTask.cpp`. No `unit->Attack(enemy->GetUnit())`, no `CmdFightTo(enemy->
  GetPos())` reaches the engine for this exact case -- confirmed by re-reading
  the branch, not assumed.
- No AngelScript path issues a raw attack-move at a tower's own position:
  grepped `manager/military/**/*.as` for `Attack(`/`FightTo`/`MoveTo` --
  the only hits are `unblock.as` (stuck-unit deconfliction, unrelated) and
  `posture.as`/`hooks.as` (no direct order issuance). No "siege a defended
  position" task type exists at script level; `killingblow.as` only sets
  posture, never issues unit orders.
- `CMilitaryManager::DefaultMakeTask` (`MilitaryManager.cpp:2049-2126`) routes
  every unit with role `assault` (armfido/Hound, armrock/Rocketeer both are)
  to `IFighterTask::FightType::ATTACK` -> `CAttackTask` -- the SAME squad path
  already audited. `CScoutTask` is reachable only via `IsRoleScout()`, which
  neither unit has.
- The travel-phase path BEFORE `ENGAGE` triggers (`CAttackTask::Update`,
  `AttackTask.cpp:452-546`) already stops at `pathRange = highestRange - eps`
  from the target and is threat-weighted (`ATTACK_THREAT_MOD`, `threatCeiling`
  from squad power) -- consistent with "stop outside range," not a dive.

**Found one real, additional gap, but in the wrong task for this report.**
`IFighterTask::Attack` (`FighterTask.cpp:225-277`, the SOLO/scout standoff
path used only by `CScoutTask`) computed `range = cdef->GetMaxRange() *
rangeMod` with **no reference to the target's range at all** -- not even the
90-100% band pass 2 fixed in the squad path, but ANY degree of outranging.
Fixed to mirror the squad path's outrange floor (`FighterTask.cpp:267-276`,
reuses `OUTRANGED_SAFETY_MARGIN` from `SquadTask.h`). This is real and worth
keeping, but Hound/Rocketeer are role `assault`, not `scout`, so they never
go through this function -- **this fix does not explain the reported
symptom** and should not be presented as pass 3's answer to it.

**No third mechanism found in `CAttackTask`'s own path with the confidence of
passes 1-2.** Two honest possibilities left, neither confirmed:
1. apexearth's comment may describe the pre-pass-1/2 symptom from memory/
   general impression rather than a fresh observation against a build with
   both fixes deployed -- pass 2 was explicitly not yet deployed when he made
   the remark. Needs a genuinely fresh watch with both fixes live before
   concluding there IS a third bug.
2. If it recurs after that watch: the travel-phase pathfinding query
   (`AttackTask.cpp:536-540`) is threat-weighted, not threat-blocked below its
   ceiling -- on a map with a narrow approach (Altair_Crossing was the map in
   play), the shortest-cost route to the correct, far standoff point could
   legitimately pass transiently closer to a tower than the final position,
   which would look identical to "walked into range" on screen even though
   the unit does not linger there. Add a one-shot LOG of `curPos` distance
   to target the first frame `ENGAGE` triggers to distinguish "stood at the
   wrong distance" from "passed through on the way to the right one."

Built via docker (`FighterTask.cpp.obj` recompiled, linked clean). **Not
deployed, no match run** per instruction. Delete this entry, and the pass-2
entry above, only once a watch with both live shows Hounds/Rocketeers holding
outside tower range with no dive.

## PATCHED, NOT YET LIVE-CONFIRMED: fragile-unit standoff/angle scaling (2026-08-14)

apexearth, watching, after the standoff/LOS-floor/ring-safety fix already
landed the same night: "Hounds still walk much too close to enemies. They
aren't tough - they really need to be more careful with themselves...
certain lower hp units have to be way more careful than high hp units."
Confirmed no separate kiting/skirmisher code path exists that the earlier fix
missed -- everything funnels through `ISquadTask::Attack`
(`SquadTask.cpp`)/`IFighterTask::Attack`, the same place already touched --
but the standoff margin (`STANDOFF_RANGE_MOD`) and the ring-safety threat
threshold were both FLAT constants, identical for a glass-cannon Hound and a
tanky Mammoth. `GetRetreat()` is per-unit-def but hand-set in JSON, not
derived from HP.

Added a `fragility` ratio per row (`avgSquadHealth / rowDef->GetHealth()`,
squad-relative baseline, clamped `[1, FRAGILE_CAP]`) applied to both the
standoff distance and the ring-safety threshold in `ISquadTask::Attack`.
Compiled clean via the docker toolchain, `sync_cpp.py status` confirms
`cpp/`/`vendor` match. **Not deployed, no match run** (explicit instruction --
a watch game may have been running). Needs: deploy once the console is free,
then a self-play test with Armada (Hound actually in the roster) confirming
(a) `fragility` actually deviates from 1 in real mixed squads rather than
squads usually being HP-uniform by weapon-range grouping, and (b) K/D/static-
kills move the same direction as the earlier standoff fix did. See
`changes/2026-08-14.md` for the full mechanism and formula.

## ABANDONED: Linux/ASan harness for the buildTasks crash (2026-08-14) -- back to Windows addr2line

Built a native Linux + AddressSanitizer build (`vendor/engine/build-amd64-linux/`,
docker's `recoil-build-amd64-linux` image) specifically to catch the
still-unresolved `MakeBuilderTask`/`buildTasks` dangling-pointer crash (see the
"IRefCounter" entry below), since MinGW's cross-toolchain has no `-fsanitize=
address`. It never got there: two different scenario configs each hit a
DIFFERENT crash during AI **init**, before the game even starts --

- 8v8 +70 handicap: null `CEnemyManager*` in `CEnemyManager_GetEnemyPos`
  (`InitScript.cpp:383`), at literally frame 0. Tried gating the one unguarded
  `aiEnemyMgr.GetEnemyPos()` call site (`baseplan/axis.as`) behind
  `Builder::gHomeSet` to match every other caller -- no effect; `gHomeSet` is
  already true by frame 0 (set on the commander's own `AiUnitFinished`, and the
  commander is a starting unit), so nothing was actually gated.
- 2v2 follow-up: null `CCircuitDef*` in `CMetalManager::ClusterizeMetal`
  during `CAllyTeam::Init`.

Neither reproduces on the shipped Windows build. Read as init-order fragility
in the hand-assembled Linux build itself (a partial `cmake --install` was
worked around by manually copying `.so`s into place, not a clean full
build+install), not a real player-facing bug. apexearth's call: not worth
the effort relative to the cost (~40 min per docker run to find out). The
three sites already fixed this session were all found the other way -- a real
Windows crash symbolized via `addr2line` against the `ImageBase`-adjusted
offset -- so that pipeline is what continues to be used as further crashes
surface. `vendor/engine/build-amd64-linux/` and the `asan_*` logs/writedirs
are left in place in case it's worth revisiting later; nothing further
planned there.

## NEW: heap corruption at shutdown in CCircuitAI::DestroyGameAttribute (2026-08-14, found via Application Verifier)

Not the crash apexearth is watching for -- caught incidentally while hunting
the one below. Windows Application Verifier's Heaps check, enabled for
`spring-headless.exe` (no rebuild needed, just `appverif -enable Heaps -for
spring-headless.exe`, reversible via `-disable`), flagged a heap violation at
the exact moment a match ends and `CCircuitAI::Release()` tears down --
resolved via `addr2line` against the unstripped build:

    circuit::CCircuitAI::DestroyGameAttribute()          CircuitAI.cpp:2591
    (deallocating a std::unordered_set<CCircuitAI*> node, which chains into
    releasing a shared_ptr whose deleter frees a terrain::SAreaSector via an
    std::_Rb_tree node deallocation)

Only observed at game-end teardown so far, in one repro. Not yet determined
whether this is harmless (process exits right after anyway) or corrupts
something that matters for multi-restart scenarios (a hosted lobby playing
several games without restarting the process). Needs its own pass: read
`DestroyGameAttribute` and whatever owns the `SAreaSector`/area-sector map to
find the double-free/use-after-free, independent of the mid-game crash below.

## PARTIALLY FIXED: the recurring "IRefCounter::Release() -> delete this" crash (2026-08-14)

**Overnight tally, 2026-08-15 (running):** after counted `buildTasks`
membership, the AssignTask reference-transfer, the ring-clamp, and finally
a counted `unit->task` pointer (`CCircuitUnit::SetTask` AddRef/Release,
crash #7 at 63 game-minutes in `UnitMoveFailed` was the finder), the soak
rotation has run Glitters 97m + Glitters 47m + Comet 41m + Ascendancy 41m
+ Adamantium 57m + Glitters 37m crash-free, with the two crashes found en
route (ring-clamp at ~35m, unit->task at 63m) each fixed and the loop
continued. The class dies one uncounted pointer at a time.

**Morning tally (06:30):** ~20 long 8v8 soaks over the night across
Glitters/Comet/Ascendancy/Adamantium. FIVE crash mechanisms found and
fixed in sequence, each surfacing only after the previous fix let games
run deeper: (1) counted buildTasks membership (freed candidate in the
MakeCommDangerTask iteration, ~35m); (2) AssignTask reference-transfer
(stale unit->GetTask() re-read in IdleTask); (3) ring-angle threat
sampling clamped on-map (watched game, ~30m); (4) counted unit->task
pointer (UnitMoveFailed on a freed task, 63m); (5) aux target maps
(repairUnits et al) erased unconditionally on dequeue + repair tasks
resolving their target LIVE by id instead of a cached pointer that a
one-slot-map eviction left dangling (85m and 48m finders). After fix (5):
soak #29 Comet 47m crash-free; #30 running at report time. Every fix is
committed individually with its mechanism.

**8v8 win-rate is the morning's gameplay item:** overnight record roughly
4W/16L by gameover; every loss is a full 8-commander wipe in the 25-45m
window while the economy leads -- commander survival in the late-game
grind, not economy, decides these. The 1v1 benchmark (12-0) does not
transfer to 8v8.

**2026-08-15, SIXTH crash, and it exposed why the AddRef brackets are not
enough.** apexearth's watched 8v8 crashed at frame 47331; addr2line (docker
image toolchain, `x86_64-w64-mingw32-addr2line`, ImageBase+offset) resolved
it to `CIdleTask::Update` at the `task->Start(ass)` INSIDE the existing
AddRef bracket, with a null-vtable call (exception address 0x0). The
bracket cannot help when `ass->GetTask()` returns an ALREADY-dangling
pointer: `manager->AssignTask(ass)` one line earlier runs the whole script
pipeline (AiMakeTask, then CBuilderManager's TaskAssigned hook), either of
which can abort/complete tasks, and `CCircuitUnit::SetTask` is a bare
assignment -- AddRef on freed memory protects nothing. **Fix, landed and
rebuilt:** `ITaskModule::AssignTask(CCircuitUnit*)` now RETURNS the task it
assigned with one reference transferred to the caller (TaskModule.h/.cpp,
BuilderManager.h/.cpp override), and `CIdleTask::Update` uses that return
value -- never re-reading the unit's task pointer -- guarded by `IsDead()`
before Start and Released after. 12 tournament games + a 25-min smoke on
the new DLL: zero crashes. Same caveat as every previous entry here: only a
long watched game closes it.

**apexearth, watching several more windowed games (+70 handicap):** "we are
still crashing," repeated after each of the two fixes below. This is the same
bug documented (and never fully fixed) in `changes/2026-08-09.md`, and it has
now been confirmed at FIVE different call sites across the session
(`CIdleTask::Update`, `MakeBuilderTask`, `MakeCommDangerTask`,
`CBuilderManager::UnitIdle`, `ITaskModule::AssignTask`) — the varying surface
location is why it looked like several different bugs and evaded manual
auditing for two sessions, and why fixing one confirmed site (below) was not
the same as fixing the disease.

**Status: two confirmed sites fixed (`DequeueTask`, `AssignTask`); a genuine
fifth crash after the first fix proves the pattern has more instances than
were found by reading alone.** Do not treat "fixed" as final until a long
watched game actually goes without one — this entry has been wrong about that
twice already tonight.

Windows Application Verifier's Heaps check (`appverif -enable Heaps -for
spring-headless.exe`, no rebuild needed, reversible via `-disable`) didn't
catch it directly — it's not raw OS heap corruption — but running under it
still eventually produced a crash whose stack pointed straight at the actual
bug: `ITaskModule::DequeueTask` (`TaskModule.cpp:78-83`):

    void ITaskModule::DequeueTask(IUnitTask* task, bool done)
    {
        task->Dead();
        TaskRemoved(task, done);   // <-- fires AiTaskRemoved (our script)
        task->Stop(done);          // <-- crash: use-after-free
    }

`IUnitTask` derives `IRefCounter`, registered `asOBJ_REF` with intrusive
refcounting (`RefCounter.cpp`: `Release()` calls `delete this` at refcount 0).
`TaskRemoved` runs the AngelScript `AiTaskRemoved` callback with a bare native
pointer and no extra reference held. If that callback happens to drop the
*last* AngelScript-side reference to the task (e.g. the last array element
removed from `Requests::gLive`, or any other tracked handle going out of
scope), AngelScript's own `Release()` legitimately deletes the object right
there — and `task->Stop(done)` one line later is now dereferencing freed
memory, from whichever native call chain happened to trigger it that time
(hence four different-looking crash sites for the same root cause).

**Fix**: bracket the callback with the object's own `AddRef()`/`Release()` --
the same guarantee AngelScript already gives every other holder of a handle:

    task->AddRef();
    task->Dead();
    TaskRemoved(task, done);
    task->Stop(done);
    task->Release();

Rebuilt via docker, deployed, verified clean on a fresh test (no AS compile
errors, opening timing unregressed).

**It crashed again anyway, ~26 minutes into the very next watched game**
(`matches/20260814-174501-*`), same `IRefCounter::Release()` signature, a
DIFFERENT call chain: `CBuilderManager::AssignTask(unit)` (the single-arg,
"auto-assign" overload) -> `ITaskModule::AssignTask(CCircuitUnit*)`
(`TaskModule.cpp:70-76`) -> `MakeTask(unit)` (runs `AiMakeTask`, our whole
script pipeline) -> `task->AssignTo(unit)`. Identical shape to the first
fix -- a raw pointer used again after a call into script that can drop
references -- just a different function that never went through
`DequeueTask` at all. Same fix pattern applied to both `AssignTask`
overloads in `TaskModule.cpp` (the two-arg version's `task->Start(unit)`
also runs script by the same reasoning, guarded too even though it hasn't
crashed yet -- same shape, same fix, no reason to wait for a sixth crash to
apply it):

    IUnitTask* task = MakeTask(unit);
    if (task != nullptr) {
        task->AddRef();
        task->AssignTo(unit);
        task->Release();
    }

Rebuilt, redeployed, clean compile.

**Crashed a THIRD time**, a 40-minute background repro this time
(`matches/20260814-175707-*`, 29 minutes in), same signature, back at
`CIdleTask::Update` -- but not the same line as the first `IdleTask.cpp` fix.
This one is `task->Start(ass)` at the tail of the loop (`IdleTask.cpp:79`
before this fix): `ass->GetTask()` fetches the unit's current task via a bare
native pointer -- `CCircuitUnit::SetTask` does a plain `this->task = task;`
with no `AddRef`, confirming native ownership of a unit's current task was
never reference-counted from the engine's own side, it relies entirely on
`buildTasks`/`updateTasks` membership and explicit `DequeueTask`/`AbortTask`
calls -- and `Start()` on it can run script exactly like `AssignTo`/
`TaskRemoved` do. My earlier fix to this same function only null-checked the
result; it never guarded against USE-AFTER-FREE, only against the task
never having existed. Same bracket applied:

    IUnitTask* task = ass->GetTask();
    if (task != nullptr) {
        task->AddRef();
        task->Start(ass);
        task->Release();
    }

Rebuilt, redeployed, clean compile, clean 5-minute sanity test. A fourth
40-minute background repro is running. **Given the pattern (three real sites
found by three separate crashes, all the exact same shape, none found by
reading alone until a crash pointed at them) treat this whole class as
UNVERIFIED until a genuinely long watched game goes without one** -- do not
report this as fixed again without that.

**Structurally similar but NOT yet fixed**: `TaskAdded(task); return task;`
in `CBuilderManager::Enqueue` (both overloads), `CFactoryManager::Enqueue`,
`CMilitaryManager::Enqueue` (`BuilderManager.cpp:741,766,774`,
`FactoryManager.cpp:820,849`, `MilitaryManager.cpp:742,778`) has the same
"script call, then native code still uses the raw pointer" shape, but the
"use" here is just returning the pointer to an arbitrary caller further up
the stack -- an AddRef-then-Release bracket INSIDE `Enqueue` would not
actually protect the caller (releasing before `return` just moves the
deletion to the instant before the caller gets the pointer). Protecting this
shape properly needs the guard to outlive the function, which is a bigger
change than the two fixed so far. Not confirmed as a real crash site, but
the same audit that found the first two sites should check this one before
declaring the disease cured.

Also found and documented, not yet fixed: `IBuilderTask::Reevaluate`
(`BuilderTask.cpp:472-480`, unmodified upstream) self-aborts any task costing
over 1000 metal with no nanoframe yet if average income drops under 60% of a
saved baseline. Plausible explanation for the separate "fusion reactors take
many attempts to complete" finding (armfus is 4300 metal; BAR income swings
40%+ routinely) — not yet confirmed as THE mechanism, a real lead for next
time.

**2026-08-15 (midday): the disease is ONE refcount imbalance on a task-module
SINGLETON, and it corrupts the whole process.** Symbolized with the release
dbgsym archive (`recoil_2026.07.04_amd64-windows-dbgsym.tar.zst`,
`addr2line -j .text` with section-relative offsets): the watched-game
crashes that looked like drawing/ping problems are Lua-heap corruption —
`sweeplist` (lgc.cpp:412) in the GC, and `luaV_equalval` under
`CBuilder::SetRepairTarget` — Lua is the victim. Headless reproduces at
~11-14 game-min on Glitters 8v8 +50 handicap in most games (post-09:59
builds, the first where the counted `unit->task` bracket actually linked:
crash rate jumped ~15% → ~90%, i.e. the bracket did not add the bug, it
converts a pre-existing imbalance into visible frees). Diagnostics built in
sequence, each landing one step closer:
(a) poison + underflow trap in `IRefCounter` — corruption still surfaced in
Lua first;
(b) guard-page allocator (`IRefCounter::operator new/delete` on VirtualAlloc,
delete decommits but keeps the address reserved) — faulted at
`CIdleTask::Update` reading `this->updateSlice`: **a manager's own idleTask
singleton was deleted mid-Update**;
(c) `SetPermanent()` on nil/idle/player singletons with a trap on the
release-to-zero — fired at frame 21290 under
`UnitFinished → AbortTask(reclaim) → IUnitTask::Stop → idle AssignTo →
CCircuitUnit::SetTask releasing a singleton with NO other holder` — an
over-release against zero holders, but of WHICH singleton and whose manager
the stack cannot say;
(d) REFTRAP context log in `SetTask` showed the drained singleton is always
an IDLE task with zero holders left — the born ref was stolen earlier;
(e) the 1M-reference CUSHION on singletons finally trapped the thief at the
call itself: `CCircuitAI::UpdateActions → DeleteTeamUnit → ~CCircuitUnit →
task->Release()` — **a unit sat in `actionUnits` TWICE, was reaped twice,
and `delete`d twice.** The second dtor ran on freed memory: its stale `task`
field still read the idleTask pointer, so idle was released once per
double-reap (the drain), and the double `delete` itself is the malloc-heap
corruption that killed Lua GC sweeps, unit LuaScript calls, and both AI
DLLs at random.

**FIX (2026-08-15, deployed, verification loop running):** three layers in
the DLL — (1) `AddActionUnit` dedupes (root cause: duplicate listing);
(2) `DeleteTeamUnit` defers the actual `delete` to `Release()` via a
`deadUnits` set (zombie units keep valid memory, so ANY remaining stale
task-set membership — CSRepairTask iterating a dead nano was observed live —
becomes inert instead of use-after-free; the set also makes a double reap
harmless); (3) `CIdleTask::Update` drains dead units instead of handing
them to MakeTask. Also fixed en route: the script binding
`AssignTask(CCircuitUnit@, IUnitTask@)` leaked one task reference per call
(plain `@` param = VM passes +1 the callee must release; now `@+`).
Diagnostics kept in the build until the loop proves it clean: refcount
poison/underflow traps, guard-page allocator for refcounted objects,
singleton cushion trap.

**2026-08-15 (afternoon): SECOND writer found and fixed — `unit->Clear()`
left `dgunAct`/`travelAct` dangling.** After the double-free fix, Apex-vs-
stock headless went clean but the Apex mirror still crashed 10/10 (so the
residual was ours, load-scaled; victims were always small malloc blocks —
Lua GC objects, the GetTunable string map). Guard-paging IAction caught it:
`IUnitTask::RemoveAssignee`/`Stop` and `CNilTask::RemoveAssignee` called the
inherited `CActionList::Clear()`, which deletes the unit's actions but
cannot null `CCircuitUnit`'s `dgunAct`/`travelAct` caches. Every later read
through those was the null-vtable crash family; `StateWait()` through them
wrote a byte into freed small blocks — the heap corruption. Upstream-latent;
our Reevaluate-heavy reassignment flow widened the exposure window
enormously. Fix (`1684a98`): call sites use `ClearAct()` and `CCircuitUnit`
shadows `Clear()` so the unsafe base version is unreachable.

**CLOSED 2026-08-15 evening — verification complete.** After the last three
fixes (dangling action caches `1684a98`, null travel-action guards `3a526c8`,
deferred task release + zombie-task refusal `70eb66d`/`9aac471`):
mirror tournament **12/12 clean**, prior null-guard tournament 14/14 clean
partial, apexearth's watched 4v4 ran 51 min clean AND WON, Greenhaven 4v4
33 min clean. Full-day progression on the mirror reproducer: 10/10 crashed →
3/12 → 2/5 → 3/16 → 0/12. Nine-plus distinct mechanisms found and fixed,
all upstream-latent lifecycle bugs amplified by our usage. DIAGNOSTICS STILL
IN THE BUILD (guard pages on tasks/units/enemy-infos/actions/path-queries,
refcount poison+cushion traps, PushUpdate dupe trap): address-space cost only
(~2-4GB reserved per long 8v8, one engine measured 6.4GB resident in a 32-min
game) — STRIP after one more overnight soak proves the fixes hold at scale;
keep the cheap traps (poison, cushion, PushUpdate) longer.

## NEW: late-game air-economy directives (2026-08-15, apexearth watching)

Two standing asks, not yet implemented:
1. **Advanced construction aircraft in the late game** — once the economy is
   large, eco building should shift to air constructors for mobility ("rely on
   more advanced construction aircraft to efficiently move around and build
   eco"). Air domain: factory selection + builder role weighting by era.
2. **Thick fighter screen** — his number: "in an 8v8 that means ~100 or more
   fighters ALIVE and flying over your base." Scale with economy/team size,
   not a flat cap; this is an air-lead/AA-baseline sizing question.

Same session, already landed: obsolete-ask TTL (rezbots deadlocked idle on a
never-expiring reclaim ledger — his twice-repeated report), bank-inclusive
reactor concurrency ("0 delay" between fusions when metal-full), and
build-side obsolescence (never build a def obsolete.as would reclaim).

## NEW: composition should answer REACHABILITY (2026-08-15, AcidicQuarry watching)

apexearth: "imagine if this was a map where theres water between us and the
enemy, we wouldn't want a large land army in such a map." The general rule:
before investing in a land army, ask whether our ground movetypes' connected
terrain area CONTAINS the enemy — the engine's terrain analysis already knows
(CTerrainManager areas, CanMobileReachAt), it just isn't bound to script.
Sketch: bind `bool GroundCanReach(from, to)` (compare area ids for a
representative ground movetype); at start and on factory switches, if the
enemy is unreachable by ground, shift factory choice and army budget to
air/naval. Air-map curated list (AcidicQuarry) landed as the cheap special
case; he explicitly de-prioritized deep work on rare hazard maps.

## NEW: route AROUND super-heavies; don't feed them (2026-08-15, watching)

apexearth: "If an enemy behemoth is around we should walk around it... we
don't have to fight something that much more powerful than us... at the least
don't get within range of it, it does crazy damage." Squad logic needs a
per-super-heavy avoidance disc: when a single enemy unit's power dwarfs the
squad's, treat its weapon range as terrain (path around, keep attacking the
base beyond it) instead of engaging or standing in reach. Distinct from the
squad-vs-static commit rule — a Behemoth chases.

## NEW: Armada T3 loses to Cortex T3 as used (2026-08-15, watching)

apexearth, losing a T3 endgame: "our Armada T3 is inferior to Cortex T3 (at
least with how we're using it)." Armada T3 skews artillery/sniper (Vanguard,
Marauder) needing standoff use; Cortex's (Behemoth, Juggernaut) rewards the
brawl our squads default to. Either faction-aware T3 unit selection or
role-aware T3 handling (keep Vanguards at range behind the line). Needs a
composition look at gantry output per faction.

## NEW: not enough anti-swarm shot density in defences (2026-08-15, Greenhaven loss)

apexearth: "we lacked land defenses to block enemy mass grunt assaults. If we
don't have enough shots (fast firing stuff to kill bulk low hp units) then we
get overwhelmed." The porcupine/defence chooser should weight FAST-FIRING
towers (LLT/beamer class) up when the enemy composition is cheap-swarm (low
average unit cost / high armyCheap), instead of the current threat-value
draw that favours big single-shot towers equally against everything. Not yet
implemented — needs the enemy-composition signal wired into PorcToBuild.

## NEW: anti-air coverage is lacking (2026-08-13, watching)

**apexearth, watching the windowed 8v8:** "We lack anti air coverage."

Not yet investigated. In `matches/20260813-222958-*`, `corflak` (Cortex AA)
appears only 9 times across the whole log for an 8-player team, and no
`armflak`/`armjuno`/`corjuno` at all — but this is a raw grep, not a proper
count of built-vs-requested-vs-lost, and doesn't separate "AA was never
requested" from "AA was requested and refused" from "AA died and was never
replaced". Needs a proper pass — likely air-warfare's factory ratio /
`CheapAA`/`HeavyAA` selection, or static-defence's `AAOrder`
(`builder/statics.as`) gate, or both.

## NEW: the defensive front line is spread thin instead of massed on a line (2026-08-13, watching)

**apexearth, watching the same game:** "Our defensive frontline is too thick,
towers spread out instead of on a good straighter line that allows many more
of them to fire at the same time."

Not yet investigated. Candidate mechanism: `Brain::TowerReach`/`FrontCurve`/
`FrontLineSpots` (frontline.as, defenceline.as) place towers along a computed
curve rather than a straight line, or space them by the per-tower crowd check
landed today (`CrowdAllows`, `defenceline.as`) rather than by a firing-arc
overlap rule. Also worth checking against today's tower-crowding cap
(`apex_fence_crowd`) — that change caps how many towers cluster in ONE spot,
which is a different axis from "are they arranged so they mass fire," and
could in principle be making this specific complaint worse rather than better
if towers are now being pushed to spread out to avoid the crowd penalty
instead of lining up.

## 0a. OUR PICTURE OF THE ENEMY NEVER EXPIRES — and it is worst against humans

**FIX LANDED 2026-08-13, NOT YET MEASURED AND SHIPPED AS A NO-OP.** Both halves
landed: a fresh-cost C++ binding (`GetEnemyCostFresh`/`freshMobileThreat`)
blended into `EnemyArmyCost`/`EnemyFieldCost` via `apex_ghost_weight` (default
1.0 — bit-identical to before, by design), and the radar-tower sensor unblock
(`DefaultMakeSensors`). See CHANGES.md for both. Neither is measured yet:
`apex_ghost_weight` needs the `GhostDiag()` ghost-fraction telemetry from a
real run before it's worth turning down, and radar count needs a fresh 10x
6v6 batch against the 1/player-vs-2.4/player baseline below. Both smoke-tested
clean (no compile errors, no crash, DLL rebuilt).

**apexearth, 2026-08-13, after losing a real multiplayer 6v6 to HUMANS:** "just
20m in we're dying a lot and we already need spam to get vision on the humans, or
air scouts."

`CEnemyManager::Update` (`unit/enemy/EnemyManager.cpp:129`) retires a sighting
only after `FRAMES_PER_SEC * 60 * 20` — **twenty game-minutes** unseen.
`CAllyTeam::AddEnemyCost` increments on `EnemyEnterLOS` and decrements only on
`EnemyDestroyed`. And **no script anywhere reads recency**: a whole-tree grep for
`lastSeen`/`stale`/freshness returns only *level* reads of `GetEnemyCost`, never
a recency test.

So at minute 20 our model of the enemy is the **union of everything ever seen,
undecayed** — and every consumer acts on it: `brain/mix.as`, `military/posture.as`,
`builder/sitesafety.as`, `airthreat.as`, `military/defenceline.as`.

**Why this is a humans-specific defect.** Against stock BARb it is nearly
harmless: stock's army does not retreat, so what we saw is still there and mostly
dies where we saw it. Humans move, retreat, re-position and hide — so the model is
systematically wrong, it is wrong in the direction of *overestimating* what is in
front of us, and it is worst exactly when we are scouting least. Any "do we have
enough to attack" comparison against that number gets monotonically harder.

`EnemyManager`'s `lastSeen` is **not bound to AngelScript**. Adding the binding is
a C++ change and the prerequisite for any fix here.

Measured alongside it, same runs (10x 6v6 Aethermoor Creek, `--handicap 50`):
**radar towers ~1 per player per game for us against BARb's ~2.4** (`armrad` 5-11
per side of six, `armarad` 0-1). No script rule builds a radar tower at all — the
only two `Enqueue(BuildType::RADAR)` sites build a *jammer* and a *targeting
facility*. Towers come solely from CircuitAI's `DefaultMakeDefence` sensor block
(`MilitaryManager.cpp:885-916`), which our own `AiMakeDefence` gates out of most
of the map: every early return in `military/defenceline.as:408-503` skips
`DefaultMakeDefence`, and the sensor block sits inside it.

Scouts themselves are NOT the gap — armflea 58-177, armfav 38-54, armpeep 7-40,
armawac 5-13 per side. We look; we do not remember correctly, and we hold almost
no permanent coverage.

## 3. Stealth and sight are not used to set up attacks

**PARTIAL FIX LANDED 2026-08-13, NOT YET MEASURED AND SHIPPED AS A NO-OP.**
`CAttackTask::FindTarget`'s 5x free-eco raid bonus is now discounted unless
`CMapManager::IsInLOS` confirms the target ground, via `apex_eco_unseen`
(default 1.0 — bit-identical to before). This addresses only the "target
scoring trusts memory, not current vision" half — the corrected diagnosis is
that targets ARE re-scored continuously, but the safety check reads
`hostileDatas`, which retains anything out of current LOS/radar, so unseen
reads as confirmed-clear. See CHANGES.md. Everything below about
`apex_scout_threat` and escort-based scouting-ahead-of-a-push is still
untouched — deliberately out of scope for this pass; land and measure the
target-scoring fix first.

**apexearth:** "Maybe some better use of the stealth units to provide sight would
help AI be even more cheeky/evil to players."

Nothing today pairs a scout, radar or cloaked unit with an attack party to see
what it is walking into. `apex_scout_threat` exists (how hot a metal cluster may
be and still be scoutable) and has never been enabled or measured at 8v8. The
mobile radar escort (`factory/eyes.as`, 2026-08-09) follows the army for
targeting, not for reconnaissance ahead of a push.

Untouched: cloaked units as spotters, and using vision to pick a target that is
undefended *right now* rather than one that scored well when the task was made.

---

## 4. The late game produces no moments

See `docs/16-big-plays.md` for the full plan. Summary: nukes fire one at a time
the instant they are ready (`super fire armsilo stock`, 427 launches in one
hosted game), which one anti-nuke absorbs forever. Fifteen simultaneous launches
need fifteen silos, because a silo reloads in 30 s and an interceptor re-fires
every 2 s.

Stage 0 of that plan — actually building the silos — has not started.

---

## 5. Unblock's escape direction can pick a lane that stays blocked

From the 2026-08-09 hosted game: `armbeaver #9079` needed **six** clearing
orders, eating a nano turret each time and staying stuck. Detection is right
(9 firings, no false positives, one unit had 86 of our buildings ringed around
it); the direction heuristic picks the thinnest wall by structure count, which is
not the same as the way out.

Also, 86 of our own buildings around one unit is the base-sprawl complaint in
`USER-FEEDBACK.md` showing up as a number.

## NEXT: come to an ally's aid (2026-08-11)

apexearth: "its 4 different AI right so this is just ally defense forces coming
to aid (so long as the distance is not too great)", and on naming: "You don't
need to label this as 'pincer' or anything like that. It's simply coming to an
ally's aid so label it as something like that."

The converging-from-three-sides effect is what it LOOKS like when four players
each defend their own side. Nothing coordinates it, so it is not a manoeuvre and
must not be named as one -- call it ally aid.

The signal already exists and is ours: `CCircuitAI::GetAttackHotspot`
(cpp/src/circuit/CircuitAI.cpp), a cost-weighted centroid of where we have been
losing units, with a decay so it tracks the current fight rather than averaging
the game. It is PER-AI: `NoteLossAt` accumulates only our own losses, so a player
cannot see an ally being overrun.

Make it ally-wide with the mechanism already carrying the front-tower budget and
the AA count -- PublishTeamValue/ReadTeamValue, three keys (x, z, weight). Each
player then picks the heaviest fight within reach and sends its massing pool.
"Not too great a distance" is the existing reach bound.

Also fixes: `BaseUnderAttack()` fired twice in six games because it asks about
enemy influence at our own start position; a loss-weighted hotspot is a far
better "we are being attacked" trigger. And it gives the Brain's defence wants a
second position source -- the one porc+ had, deleted with it.

Before touching the army: add army-position telemetry to dev_stats_export.lua
(each side's army centroid and its distance from its own base). [BARAI_POS]
records BUILDINGS ONLY, so "our armies run away when the base is attacked" cannot
currently be measured at all, only watched.

## The base layout axis is the exact 180-degree reversal in half of all games

Measured 2026-08-12 over 442 `apex: base frame` latches in `matches/2026081*`:

```
axis kept front-facing 221 | axis REPLACED 223
fwd points AWAY from enemy (bands grow toward enemy) 221
fwd sideways 2 | fwd toward enemy (bands grow rear) 221
```

Every one of the 223 replacements was the exact 180-degree flip, not some other
orientation. `baseplan/axis.as:76-93` probes four right-angle orientations and
takes any that "more than doubles the front-derived score"; candidate `t == 1` is
`(-f.x, -f.z)`. Bands are then laid out as `gAnchor - gFwd * depth`, so when the
axis flips the whole stack grows TOWARD the enemy and the DEEPEST band -- the one
`baseplan/state.as:75-76` reserves for heavy energy, "where a fusion going up does
not take the rest of the base with it" -- is the most exposed ground we own.

Example: team 3, run `20260812-211651`, `anchor=809,706 fwd=-0.81,-0.58`, enemy
centroid ~(6436, 2751), dot = -0.96.

This is not a reactor bug. It moves every building the base plan places, which is
why it is recorded here rather than fixed alongside the AFUS placement work --
that change routes around it (`Base::AxisIsRearward`) for reactors only.

## The AI crashes in SkirmishAI.dll at roughly 1 percent of runs

4 of 371 runs on 2026-08-12 ended `Spring 2026.07.04 has crashed`. Stack is four
frames deep inside our own DLL:

```
(0) SkirmishAI.dll [0x59edf]
(1) SkirmishAI.dll [0x5aaf6]
(2) SkirmishAI.dll [0x11850]
(3) SkirmishAI.dll [0x23e2]
(4) spring.exe ...
```

Predates the 2026-08-12 obsolete.as and rules_optional.as changes -- run
`20260812-210421` crashed before either was deployed, so do NOT attribute it to
them without a repro. Observed once at frame 54707 (30.4 game-minutes), well into
a game, with nothing unusual in the preceding AI log lines.

The deployed `SkirmishAI.dll` is a 208 MB unstripped build, so those offsets are
resolvable with addr2line against the matching build if this gets worse. Nobody
has done that yet. Not reproduced on demand.

## Air transports are unused: badly-placed con turrets stay badly placed

apexearth 2026-08-15: "you can use air transports to move con turrets that are
not in good spots." A nano is 300+ metal of build power that becomes dead
weight when its factory is reclaimed or the build cluster moves; the game's
answer is an air transport (armatlas/corvalk/legatrans), and this AI never
builds or commands one. Needs C++ (a load-move-unload task; nothing in the
bound surface issues transport orders). Candidate trigger: a standing nano
whose lathe reach covers no live factory, no build site and no repair target
for N minutes, moved to the current nano-band anchor. Not started.

## Water on mixed maps is ignored (Supreme Isthmus)

apexearth 2026-08-16, watching the 8v8: "this map has water in it and we
don't seem to care about water. Might be worth checking our water
configuration and our desire to expand into water." Supreme Isthmus carries
underwater mexes and water lanes; nothing amphibious or naval was built.
IsWaterMap presumably reads the map as land (min_land 75) and every naval
path stays cold. Naval-water domain: check whether water-START detection vs
map-share detection is the gate, and whether amphib cons/underwater mexes
have any path on a mostly-land map.
PARTIAL 2026-08-16: `Military::EnemyAfloat()` (territory.as) now triggers the
shipyard escape branch and an air/adv-air want when the OBSERVED enemy lives
on water (subs seen >= apex_afloat_sub_cost, or enemy centroid beside
floatable water on a <=85%-land map), and enemy subs put a torpedo-bomber
(RT::AS) floor on air lines. Our OWN desire to expand into quiet water on a
mostly-land map (underwater mexes with no enemy there) is still unaddressed.
MEASURED 2026-08-16 (Jade Empress 1.41, 8 games across two builds): we lose
the map on ECONOMY, not composition -- post-massing-fix run produced 0.72x
stock's metal there (1-2 decided) while shipyards ARE built (2-5 per game via
the mixed-map branch). The open question is water expansion: whether we take
the underwater mexes stock takes. Land maps same day: produced 1.7-2.7x.

## Base sprawl at 8v8 scale: organized construction

apexearth 2026-08-16, 8v8 Isthmus: "our buildings are terribly spread out.
We need to do much better about organized construction." Long-standing
USER-FEEDBACK theme; at 8v8 the 40-57-advsol farms amplified it badly. The
advsol stop (apex_advsol_stop, 1k energy with T2) removes the worst sprawl
driver; what remains is baseplan-domain: whether Base::Spot's bands hold at
8-player density and why eco placement escapes to FindBuildSiteNear fallbacks
(the audited "obsolete-junk standing" numbers say the grid is not packing).

## Widening-search siting should be the general placement pattern (2026-08-21)
apexearth, after GantryAtRear's doubling radius: "We have to do this with most
things, you can't predict what the map will be like." Most placement paths use
one fixed FindBuildSiteNear radius and fail silently when it finds nothing.
Related: reclaim-to-make-room -- "If you see something not useful could be
reclaimed to make room for something useful then we should do the reclaim, or
reposition things." Valid, not urgent.


## Market runaway at high income (2026-08-23, open)

45m vs NullAI seed 1 (matches/20260823-06*): 41 driven factory lines (23 T1
labs + 15 air plants) against a 1 + income/50 support rule that should cap
~5-9 -- either Factory::gFactoryCount lags the request pipeline (many plant
requests licensed before any factory STANDS) or the gate reads stale income.
Same run: 58,203 mex decides (21/sec churn -- tasks created and dying
instantly at 40+ workers; suspect CBMexTask spot-close/reopen cycling), 3,519
moho decides for 3 standing. Both only appear at 100+ m/s income; the 30m
runs at ~60 m/s are clean. Diagnose with apex_auction_diag=1 plus a decide
-> task-outcome trace before touching prices; the in-flight-plant window
(requests not yet standing don't count toward gFactoryCount) is the first
suspect for the labs.

## AFUS decided, never completed (2026-08-23, open)

armacks correctly pick energy:armafus (v=15) the moment moho ground runs out
(~25m), but a 16.6k-metal build started that late never lands inside the
window even fleet-assisted. Either fine (longer games) or the fleet should
converge on the mega-build (priority/assist focus). Check completion in a
60m run before designing anything.

## Feature gaps vs stock BARb (2026-08-23 survey, for the market rebuild)

Stock configs cover, and our market does not yet price: LRPC/offensive
statics (12 config files -- Pulsar-class siege is a stock staple), shields
(5 files; counters the arty that keeps killing our labs), transports (11
files; logistics, low priority), naval/sonar (whole domain, deferred --
benchmark maps are land), Juno (parked by apexearth until an identity
signal). Stock has NO nuke offense (0 files) -- a potential advantage for
us later, our anti-nuke defense already exists. Priority order when the
ladder baseline is in: shields (defends the tech core), LRPC (late-game
siege sink), then naval as its own project.

## THE blocker: army trades at 0.22 K/D (2026-08-23, the ladder's verdict)

Across 8 games at 45m vs easy: 311,470 metal of army lost to kill 68,715
(K/D 0.22); the 2.5:1 eco lead at 30m decays to 1.05 by 45m paying for the
bleed. Our squads average 2 units against their 4.8-6.0 (max 11-15) --
units still reach fights in dribs despite pool floors (meet 1.3x, hold
240s: no measurable change at these samples). Wins come EARLY off the eco
lead (20-34m); every long game is lost to trades. Medium: 0-6. This is the
kept legacy military-use layer's domain (engage odds, squad merge, group
travel) -- apexearth's design input wanted before surgery, per the unit-
thoughts boundary. The market side is NOT the constraint anymore: eco,
composition, protection, and production all measure healthy.

## Military design session, opening doctrine (apexearth 2026-08-23, watched)

"Our army ran off to chase some enemy raiders and while it was away the
enemy destroyed much of our base with their main army." Rule for the
session: respond PROPORTIONALLY -- break off a detachment sized to the
raid (~raider mass x margin), the main force holds against the main
threat. Lives in the attack/defend task target selection (C++ AttackTask
FindTarget + the massing pool); do not implement without his input.

## Military dossier: travel thrash (apexearth 2026-08-23, watched)

"Our army runs back and forth not sure which way to get around a hill"
while the T2 lab died. Target/stand reselection oscillates the group's
path around terrain. C++ travel/target logic (DefendTask stand + AttackTask
FindTarget rethink cadence); session item, alongside proportional response.

## Military dossier additions (apexearth 2026-08-23, watched)

- Attack from multiple ANGLES: "our army feeds in from only one direction";
  approach-vector diversity is squad-level design (session item).
- ~10s periodic lag spike: script exonerated (perf max 13ms/frame); the
  spike is C++/engine-side periodic work (threat map, path graph, enemy
  clustering are the suspects). Needs a C++ profiling pass; consider
  chunking the guilty job across frames.

## Naval: the next feature block (apexearth 2026-08-23)

"We should try to gain control of the water regions -- a big metric for
success." The market currently EXCLUDES floaters/submerged everywhere (the
armsy/armfmkr lessons). Minimal viable navy needs: (1) water senses the
script lacks (map water fraction, is-water-at, water mex spots) -- likely
one small DLL binding round; (2) shipyard plants allowed when water value
justifies, sited at the shore; (3) ship production through the existing
army market (roles/power already generic); (4) water spot claiming by ship
cons (engine reachability already per-unit). Scoped, not started.
