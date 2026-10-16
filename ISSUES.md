# Open issues — what is wrong with this AI right now

Each entry: what is wrong, the evidence (one run, one number), what was tried.
An entry is DELETED when its fix is measured; the measurement goes in the
commit message. `USER-FEEDBACK.md` is what he asked for, `TODO.md` the named
plays. `git log -p -- ISSUES.md` has every deleted entry with its provenance.

The October entries are below in full; the September ones are compressed at the end
(2026-10-15), full text in git. The custom C++ fight layer was reverted to stock BARb on
2026-09-07 (`7a1a9895`).

The fight layer is stock since 09-07; "unverified" below means a fix landed
and no game since has been read for it.

## VALIDATION LIST: WHAT 10-14/10-15 CHANGED AND NO GAME HAS PROVEN (2026-10-15)

His 10-15: "a lot of what you've tried to implement hasn't really worked". Every item stays here until a
game log shows the DECISION moved (the instrument named), not just that the code ran. Status: BROKEN =
seen failing in his game; INERT = applied but the behaviour did not change; FIRES = the code path logs,
effect unmeasured; UNTESTED = never ran in a game. "watch/v0.2.5" = on in his slot and the release.

| # | What he asked for | Change | Instrument | Status |
|---|---|---|---|---|
| 1 | Bombers stop bombing ticks; Dragons keep advancing | fliers never get the fight-travel order (MoveAction.cpp) | `fight-travel flier-kept`; watch a strike | FIRES -- dev 4v4 10-15: 51 Thunder fight orders kept as moves (`flier-kept`). Not yet in v0.2.5 |
| 2 | Gunships spread, not one point | attack squads give fliers a grid (AttackTask AssignFlierSlots) | `squad air-formation`; mapframe | PARTLY -- grid works on travel (seed 89: air-formation n=5 spacing=140). BROKEN at the target (his 10-15): a committed raid near its target re-ordered every gunship onto the mex (OrdSrc OTHER, no offset). Fixed 4146db49 (fliers use TRAVEL/FWALK there); UNTESTED in a game. Lone-gunship raids still stack |
| 3 | Late game: economy + T3, T2 ground mostly useless | tmix head 0.1 (watch/v0.2.5) | `nnval head=tmix` reads 0.1 in 828/830; produce: by tier after min 30 | INERT, cause found -- tmix only scales a lower line once a BETTER line (T3 gantry) is up. His 10-15 8v8: gantries started 18-30 min in every seat, ~150 T3 units by 55 min; after 30 min the volume was T1 rez bots (row 27), T1 air cons, T1 scouts, fighters |
| 4 | No T1 hover AA late | none yet | `produce:armah/corah` | BROKEN -- his 10-15 8v8: T1 hover AA from min 27 to 54 in 6 of 8 seats, after hover plants went up at 17-35 min |
| 5 | Late towers T2/T3, not T1.5 | TUNE_DEF_TEAM_OBSOLETE (watch/v0.2.5) | `advobs-stat` cut=6427/6482; tower tally by tier after min 30 | PARTLY -- with TUNE_ASSIST_ECO too (same-seed 4v4 Carrot 10-15, both off vs both on): T1 towers min 10-20 ~150 -> ~93, min 20-30 ~211 -> ~163; metal income min 30 953 -> 1,092; assisteco 98 offered/75 taken (energy). One pair; search A/Bs 154-157 queued |
| 6 | No dragon's teeth | TUNE_TEETH=0 (default, watch, v0.2.5) | defence/teeth wants = 0 | VERIFIED -- his 10-15 8v8: 0 teeth decisions in 8 seats over 55 min |
| 7 | Commander not reckless | COM_BOLD off on watch, COM_STEP on | commander deaths and where; `comstat step=` | UNVERIFIED |
| 8 | T2 air plant and T3 gantry get built | tech head NOW 0.8 (watch/v0.2.5) | `nntech` chosen; plant start minute per seat | BACKFIRED -- the tech head NOW bias (v0.2.6 network) applies to every tier step: his 10-15 online 6v5 on a 3v3 map, all 5 seats ordered their T2 lab at 2.0-3.3 min. Removed from his watch slot (tech follows the rule); v0.2.7 replaces it with time-to-contact tech pricing + one tech seat handing out T2 cons |
| 9 | Big bombing raids, more air | AIR_PAYOFF=1, factory head to market | bombers built; `nnair-stat` go vs launched | WEAK -- his 10-15 8v8: 0-8 strikes per seat, air mostly fighters (hawk/vamp/fig); T2 bombers 0-7 per seat |
| 10 | Hunt what matters, not spam | apex_target_value=1 (watch/v0.2.5) | `target-stat` asgM/nearM, kill classes | FIRES -- effect on fights unmeasured; needs A/B |
| 11 | Don't walk into packs on move orders | apex_fight_travel=1 (watch/v0.2.5) | fights won/lost; same-seed A/B | 1 game only; it broke air (#1) |
| 12 | Odds: willingness to attack | odds head 2.0 (watch/v0.2.5) | `nnval head=odds`; trade per fight | FIRES -- same-seed control lost too; not shown better |
| 13 | Mexes upgraded once T2 (his maroon seat) | TUNE_T2CON_UNLOCK, UPGRADE_FIRST, MEXUP_HORIZON (off) | `mexup-stat`, `why=uphand`, prodrank `,up` | FIRES -- three switches compiled (dev 8v8 10-15: mexup-stat unlock priced, horizon priced). Search A/Bs at 3-4 pairs: unlock -0.25, upgrade_first +0.28, horizon +0.10 (noise) |
| 14 | An eco player in 8v8 | `TUNE_ECO_SEAT_STRICT` (ecoseat.as): while growing, hands and labs take economy only | `ecoseat-stat` P vs target, towerM/armyM, refused | PARTLY -- strict + assist + crew on, same-seed 8v8 Comet 10-15: eco seat P 117 -> 167 of 500 at 35 min, towers/army 0, hands on nanos/assist/mexup; but the team's income at 30 min was 233 off vs 179 on and mexes 31 vs 22 (opponents differed too). Not shown better for the team |
| 15 | No late-game lag | none yet | lagcurve: wall s/min vs moves, nopath, builders | CREW ELECT INERT -- same-seed 8v8: shared 1-2 of 49-68 elections, crew 1.0; hands rarely line up by def+place. Election cost at min 34: maketask.builder 2.4 s/min over 8 seats, single elections to 20 ms |
| 16 | AA when bombed | TUNE_TEAM_AIRLOSS (watch/v0.2.5) | AA built within 2 min of air losses | UNVERIFIED |
| 17 | Refill towers where they died | TUNE_DEF_REFILL (watch/v0.2.5) | `refill-stat`, deflag.py | FIRES; lag not re-measured |
| 18 | Guard the flanks | TUNE_FLANK_GUARD (watch/v0.2.5) | `flank-stat`, flankstat.py | UNVERIFIED |
| 19 | Some hands always on economy | TUNE_ECO_HAND (watch/v0.2.5) | roles `ecoHand` kept/lent; fusion gap | FIRES; minutes with no eco build unread |
| 20 | Army fills line gap | TUNE_LINE_ARMY_GAP (watch/v0.2.5) | nano batch `armyGap` | UNVERIFIED |
| 21 | Fewer defences, more units; radar not 10-13% | 5 defence price switches (off; all-five A/B -1.28) | spend shares | OPEN, worse -- his 10-15 8v8: towers were 19-47% of ordered metal in every seat (decide lines, re-elections inflate), 117-251 tower jobs per seat; per-switch A/Bs not run |
| 22 | Air scouts find armies in jammers | lost-army looks branch | `lost-stat` | UNMERGED (worktree-agent-a9165e14d9953e66b) |
| 23 | Energy and converters, always | proposal only | converter count, e-waste | OPEN -- 430-500 e/s wasted in watched games |
| 24 | Early army share | none | army spend 24% vs 32% target | OPEN |
| 25 | Siege fortifications | TUNE_SIEGE (off) | siege.py | OFF; never A/B'd after the fixes |
| 26 | One big army | TUNE_ONE_ARMY (off) | armyheads.py | OFF; lost 25%->10% unmeasured once |
| 27 | (seen 10-15) Rez bots | none | `produce:armrectr/cornecro`, `rezwant` | FIX BUILT -- TUNE_REZ_LIFE (off): price = reclaim over expected life minus cost. Dev 8v8: priced 78, cut 56; loss rate small there (44 rez deaths/8 seats), so life rarely binds; needs his 8v8 scale |
| 28 | (seen 10-15) Late base lost to long-range plasma | none | `shelled ... by=corint`, deaths of gantries/coms | OPEN -- his 10-15 8v8: from min 47 our gantries then commanders died, several to corint (range 4,950), while our army stood ~3x theirs |
| 29 | (10-16) Small maps: go really hard into military, starve their mexes, commander at the factory | TUNE_SMALL_HARD (path contact, strength at arrival, mex denial, factory guard) | `smallhard-stat` k/rho/floor/mix | FIRES -- cand-5 vs v0.2.6 small 9-0-3; raider count still ~0, untested whether he sees "really hard" |
| 30 | (10-16) Army gets its share; fewer floor-built cons | TUNE_BUDGET_HOLD (floors/hoists yield while army is under its share) | `budgethold-stat` actual/target, skipped/asked | FIRES -- smoke: conFloor 0/1 skipped; effect on cons count not yet read |
| 31 | (10-15) Hold at least half the map before eco | TUNE_MAP_SHARE | `mapshare` gap | FIRES -- cand-2 mid 11-1-0, cand-5 all sizes ahead; watch slot on |
| 32 | (10-16) Small maps: commander supports the factory, is not lost to their commander | TUNE_COM_HOME (off): time off the lab priced as army, guard earns it; no D-gun kill on a commander; their commanders are a base attack; walk-ins price seen guns | `comhome-stat` jobS assist, fwdS, guard/won, alt, walk no | UNTESTED -- cand-5 small-s504 t2: assist=0 every minute, guard v 11 vs mex 155, 13 FIGHT/RETREAT swaps 2.0-3.8m, 0 com-ship lines while a corcom took 1730 m of base |

## A SITE MOVED AFTER PRICING IS A WALK NOBODY PRICED (2026-10-15)

His watch game (army-smoke wdwatch1, t0, home 7600,4897): at 8.51 min `com-selfgun` hoisted an
LLT at 7801,5336, ~480 elmos from the commander (`decide ... why=comself`, v=6.10, t=34). In the
executor the defence-site net drew WALL (`nndefsite` p: WALL 0.734, RULE 0.147), the best wall slot
on the map, 11968,3776 -- 4,450 elmos from the priced site. No `site-far` line, so the C++ search did
not move it; `stuck-com dSite=4585` six seconds later. He walked 2.3 min, built the LLT at 10.9 min
(`placed armllt at=11968,3776`) while the base fell (armvp 10.3 min, mexes/solars 11.4-11.9), and
`rehome` then made that corner home. Two holes: (1) `DefSitePick` relocates after `ValueOf`, and its
features carry the distance from the rule's site but not the asker's walk; (2) the commander leash in
the decide loop (`ComFar(ranked[i].pos)`) tests the priced pos, not the executed one, so a moved site
escapes it. A self-defence gun is defined by where he stands; whether the site net may move one, and
how far, is his call. The 8.3-min shipyard decide (v=72.8) never walked: the leash refused it and he
built a converter at home.

## THE COMMANDER STANDS WITH A JOB AND NO ENGINE ORDER IN THE OPENING (2026-10-11)

1v1 Comet vs BARb, watch net, after the 9e0b00ba commander fixes (he now chooses WORK in every
decision without a threat): 3 of 20 games placed under 10 buildings in the first 3 min and lost by
6-14 min -- the commander, holding a build task, logs `stuck -- armcom ... held <def> progress=0.00
... still 10s ... q=0 -- no engine order, re-electing` (stuck.as) again and again, and drifts toward
ever farther sites until something kills him (seed 116: dead at 6.0 min, 1,706 from home, after 7
such stalls). His action ring reads `mov>mov>mov` with q=0. Ruled out: the D-gun hold
(IsDGunHeld drops every Cmd*, but s116 has no dgn/hld marks), the 3 s NoteOrder dedupe, the
commander net (all WORK). Happens in 0-7 of 10 games per arm in any arm, so every A/B in 1v1 so far
was dominated by it (a "formation off: 0.5 of 10" result flipped on re-run). Identical seeds do not
reproduce a game; next: apex_order_trace=1 across a batch until one stalls, then read what cleared
his queue.

## ARMY AND AA ACROSS THE T3 SWITCH (2026-10-10, open after the tmix/aa commit)

- **Static AA sited forward dies unbuilt.** 175106 watch game: armflak framed at
  fwd=0.80 (RimGapSite pushed 0.8 range outward / the held line), frame-stalled
  idle 20-68 s with ring=0, decayed and was killed at done=0.2; 27 AA frames
  died unbuilt over 9 air games on 10-10. protect_senseprice.as PROT_AA siting.
- **PendArmyMWithin counts queued gantry work at nameplate BP** (facqueue.as
  PendArmyMWithin -> LineBuildPower): shared nanos count for every plant in reach,
  so queued T3 reads as army landing inside the fill window and closes every
  line's gap early. Same overcount the yield had (nameplate 306 m/s vs 78 m/s
  delivered, long game min 27).
- **Constructors take as much metal as T2 army.** 15 watch games, the 6 min
  before our first gantry unit: cons 1.6-2.0k m/min vs T2 army 1.3-1.6k; 200-380
  cons a game vs BARb 50-235. TUNE_CON_RULE = 2.5 (con head's rule).
- **Gantry crawls without its ring.** 174511: armshltx lathe-site due=12 at min
  12, due=18 at 18, due=50 at 33, first unit min 39.

## SILENT BUGS FROM THE 2026-10-08 CODE REVIEW (unfixed)

Five read-only reviewers, each finding checked against the 2v2 vs BARb batch
(tournaments/20261008-054849-nn-barbtrain) and the Comet 1v1s (20261008-204630).
Already fixed from the same review: escort spare test (3a5edd03), time-capped
games labelled even (2d9d4fd0). Line numbers are as of 2d9d4fd0.

- **First constructor up to 5 min late** (production.as ~2459, budget.as 178/191).
  `armyBehind` reads 0/target when a commander building finishes before the lab's
  first order (factory spend excluded), so the YIELD con floor yields. 13 of 32
  1v1 seats got their first con at f=1918-9249 after 1-9 combat units.
- **Join-fight STAY marches the squad to the enemy box** (AttackTask.cpp 745-751
  -> 250 MarchEnemyBox). 67 of 98 STAYs (comet) were fights <1500 from home; the
  next line is `atkbox` 41/78 times. STAY drawn 6.5-10% against logged p~0.019
  (EcoDraw, joinfight.as).
- **Commander net off since 10-05** (nntrain.py ~1226 learn_head, nnlog.as 690).
  The head adopted lane keys ending `evade`; Unstable logs 29 own fields, so every
  game is skipped as "older" and NnHeadScore refuses silently. 57k rows skipped.
- **Raid net GO strips cover and hold pools** (nnraid.as 271-285); the cover/hold
  ledgers (hooks.as 96, massing.as 427) drop a unit only on death, so they read
  full. Cover blocked 251 of 564 seat-minutes (1v1).
- **Held pool promotes under MELEE and poisons every later hold** (DefendTask.cpp
  116-125, MilitaryManager.cpp 686/750/811): MELEE falls to default (rally) and is
  filed under MELEE but removed under RALLY, leaving a dead entry forever.
- **Supers never released** (superguard.as 110-118): 0 "releasing" lines in 21
  barbtrain games with 228 holds; Legion supers are keyed by cost and never count.
- **Siege ring backs out of the unit's own range** (SquadTask.cpp 553-608).
- **Constructors flee only when hit** (BuilderManager.cpp 1649 reflex covers
  rezzers only): 6,549 of 7,993 2v2 con deaths came after a con-retreat, 4,805 of
  them within 10 s.
- **Unit counts read as metal (S28)**: coverage.as 715 ThreatAt, guards.as
  149/201 WorkerEnemyM -> EscortOwedM, raid.as 268 RaidPackNeed. Live enemy
  presence never moves a spot price or escort demand.
- **PickSpot ignores the con-death mark the let-go honours** (want_mex.as 855 vs
  sitesafety.as 345, maketask.as 303-321): 898 of 6,405 let-gos re-sent to the
  same ground within 30 s; 31% of con deaths within 250 of another <3 min old.
- **Generators skipped team-wide once any hand can build fusion** (want_reclaim.as
  483-490, want_energy.as 154) -- the shape docs/tunables.md TUNE_OBSOLETE_RATIO measured
  bad for converters. Suspected.
- **Opening budget reads economy overspent** (budget.as 178-185): eco tickets at
  the 0.35 floor in 31% of min 0-2 samples; a radar/tower beat a mex 42 times in
  the first 4 min. Suspected.
- **Explorer share 54% of training team-games** (doc says 10%); explorer teams win
  34% vs 50%, and trust pairs come mostly from explorer rows.
- Smaller: raid decision acts on a 1-5 s old unit snapshot (nnraid.as ~655);
  stall hoist on a raw pull spike (guards.as 927); factory-floor EMA polluted by
  placeholder values (decide.as 2569); buffer rows lost on a kill (nntrain.py
  904/617); exposure cached at the con's position 30 s (army.as 107-136);
  GetAllyBuilds engine call per allied unit (InitScript.cpp).

## DECISIVENESS: THE TEAM PUSH AGAINST BARB (2026-10-07)

2v2 vs BARb hard, our side +75% vs +50%, forced plan, no explorer
(runtime/nn_barb2v2.sh). On the build with the strongest-group bar and the
staging walk to range (05:40): rule 6-4, wins avg 45.2 min; MASS 6-5, wins
avg 44.4 min -- a null at n=10 (95% CI 28-83%). On the threat-clear staging
build (06:59-08:44): rule 15-10 (60%, CI 41-77), wins avg 40.8 min; MASS
12-7 + 2 draws at 60 min (63%, CI 41-81), wins avg 39.0, 262 pushes trading
3.4:1 -- still a null. At 09:40 the same arms read rule 24-14-1 (63%, CI
47-77), MASS 15-13-4 (54%, CI 36-70): forcing the push from minute 0 wins no
more, ends games no sooner (wins 38.5 vs 39.0 min) and stalls four games to
the 60-min cap against one. The prior stays NORMAL; the plan net (trust 0 at
200 pairs, wcorr -0.05) is where MASS has to earn its moments. Pushes trade 2.2:1 at the
breach vs BARb and 2.7-7:1 in self-play, yet games are neither won more nor
ended sooner. Found along the way and fixed: the breach jumped every 5 s
(held now), squads stopped at weapon range of the staging point (walk to it),
the threat-map path to staging failed 224-827 times a game (walk anyway,
`apex: atk-stage-nopath`), a summed-defence bar made pushes rarer and worse
(reverted). Open: a forced plan pushes from minute 4 with 25-power teams
(early pushes into BARb's pressure); the staging point sits inside the threat
map's widened danger; the side's attack power is often small or zero.

Where the minutes go in a WON game (rule arm, Frozen Ford, won at 42 min):
income led from minute 8 and ran ~1.9x by minute 24, but trades stayed 0.3-0.6
until minute 28 (then 1.6-5.8). In minutes 12-24 we lost 28.8k: 26.7k of it
in the retreat task, at home (13.8k) and mid (11.5k) -- AK raiders cycling
defend -> guard -> raid on our own side at full health, then dying on the
retreat. A won economy closes ~15 minutes late because the army at home
bleeds against BARb's pressure; the push cannot help a side that is not
holding its own ground.

## LEAKS: ENEMY GROUND UNITS KILL OUR ECONOMY AT THE BASE EDGE (2026-10-08)

`tools/leaks.py` over the 2v2 vs BARb batch (20261008-054849, 121 games):
2.86M metal of generators/converters/nanos/labs killed by enemy ground units
inside our hull or within 250 of its edge, 61% of it outside a loss's final 5
min. Median per game: wins 4.5k, losses 8.8k, time-capped draws 22k. Almost all
at the RIM (in 20%, rim 80%); front 51%, flank 35%, rear 13%. 66% fell with at
most one gun of the team within 600 ("one gun is not a defence"); nearest gun
<300 in 31%, 300-600 38%, >600 31%. Killers: raiders (<400 m) 40%, heavies
(>1200 m) 39%; it grows with the game (min 0-10: 35k, 30+: 1.4M). Comet 1v1
(26 games, 20 min cap): 154k, rim/front 78%. The nets added the same day
(protect_nn.as, heads defamt/defsite) record against it; `apex: leak-stat` is
the live census. Unfixed until a trained head or a rule moves these numbers.

## MEX LOSSES VS BARB: THE RAIDER NEVER PAYS (2026-10-10)

`tools/mexraid.py`, 38 normal 12-min Comet 1v1s (20261010-03..): standing mexes
m5/7/9/11 us 4.7/6.8/8.2/9.8, BARb 6.6/8.9/11.0/13.6. We lose 5.1 finished +
1.3 unfinished a game, BARb 3.0 + 0.5. The enemy unit that killed one of our
mexes was alive at the end in 58% of cases (BARb's killers: 33%), and took 41
more of ours (BARb lost 14 that way). 2v2 (32 games): 51% vs 31%, mex edge
0.75 -> 0.64. raidanswer.as (2026-10-10) answers the first half; still open:
- **The gap at m5 is claims, not losses**: by m5 we have 2.4-3.5 factory cons,
  BARb 4.1-5.2; distinct spots claimed by m7 6.2-8.2 vs 9-9.8 (see "First
  constructor up to 5 min late" above). Losses explain ~1 of the 3.8-mex gap at m11.
- **35% of our mex losses are army-scale** (>=5 enemy units or >=800 m within 700):
  1.7/game vs BARb's 0.8 -- the field is lost, not a raid.
- **BARb takes the exposed spots more, not less** (21 games): builds at f>=0.4 76 vs our 40.
- **A small DEFEND pool skips a petty raider and cannot detach for it**: Detach keeps
  half the pool and one member, so a pool of 2-3 facing a raider just under half its
  power sends nothing (`apex: defend-petty ... n=2 covered=0 sent=0`, 15/22 games). C++.

## GROUND DEFENCE NEVER REACHES ITS TARGET: THE FUNNEL (2026-10-09)

Same batch, all 121 games. The defence question was ASKED in 87% / 35% / 21%
of elections at min 6-10 / 11-20 / 21-40 (perf calls of step 14 against the
never-skipped energy/assist steps): StepSkip learned it away, because 84% of
defence firsts after min 20 come from hoists (coverall 30.2k, basefront 8.3k
of 45.9k) whose Wants carry no `src`. Fixed by exempting step 14 while
DefenceShortfall() > 0 -- UNMEASURED; `apex: def-funnel` is the instrument.
Still open, read off the same funnel:
- **Executor refuses 68% of ground-gun attempts** (whole games, 43k): grave
  9.5k, takeNull 9.7k, interior 7.3k, ferry 2.8k, ok 13.8k. By source (prot-exec
  joined to its decide line): coverall 30.7k of the refusals (89.6% refused, 26k
  of them the same site again), basefront 6.4k (58%). Comet 1v1 (156 games):
  coverall = takeNull 53% / grave 33% / interior 7%; basefront = interior 52% /
  takeNull 40%; takeNull is the request verdict "covered" (a cheap gun inside
  600 of another manned request). Mechanisms and fixes (UNMEASURED, `apex:
  def-refuse`): interior was a circle at the longest ray, so a lopsided base's
  front wall slots read interior -> the hull the half-reach disc spans; sole
  cover asked only the nearest mex -> any gunless mex in reach; grave/interior
  relocate (pull back / out) while the gun still reaches the post; hoisted posts
  (coverall, basefront) fold only the same ground; coverall skips a gap whose
  gun was just refused; a ferried gun counts as cover.
- **Value at min 10-20**: when a defence want IS in a draw list the best rival
  is 6.6x it (median); draw sharpness 2.9 makes that ~1% odds. After min 20
  the ratio is 0.66 and defence wins when present (median p 0.99).
- **The gap is counted twice on pull-priced slots**: the pull is gap/180 s, and
  the want is then multiplied by TargetFill = gap/target again (protect_want.as
  `gDwFill`), so value goes as gap^2/target there.

## T2 GUNS STAND AFTER THE T2 PUSH ARRIVES, AND THEY ARE THE SLOW ONES (2026-10-09)

Same batch, per SIDE (two seats each; gadget BUILD/ARMY/DEATH lines, ground
guns only, AA and LRPC/silos apart). T2 ground guns: us 6.9 / 16.6k metal a
game, BARb 14.3 / 30.0k (T1: 43 vs 67). Our first T2 gun stands at median
min 22.4 (none in 35 of 121 games), BARb's at 18.1. Their first armed T2
ground unit comes within 1500 of a seat's core at median min 15.8; our first
T2 gun is later than that in 91 of 108 games (BARb, against ours: 44 of 74).
When 2000+ metal of their T2 is that close, we have ZERO T2 guns standing in
66 of 92 games (BARb: 19 of 54). Of our structures killed by enemy T2 ground,
27% stood under a T2 gun's reach (BARb's: 58%). Mix: we build Annihilator /
Doomsday / Legion popup (2.3/2.1/2.1 a game) and almost never the quick T2
guns (Pit Bull 0.16, Viper 0.12, Toaster 0.13, Ambusher 0.07); BARb builds
Viper 2.8, Pit Bull 1.8, Toaster 1.9, Ambusher 1.7. Wins 12.0 T2 guns, losses
1.0. Head `deftype` (protect_nntype.as) records the class choice against it.

## PERFORMANCE

### 8V8 BUILDER ELECTIONS AT 3x THE 16-AI BUDGET, MEASURED UNDER LOAD (2026-10-07)

`matches/20261007-8v8-mass` (Comet Catcher 8v8, +100%, MASS forced, 30 min)
read 1.237 ms/AI/frame at minute 28 -- but on a machine running 8 other engines
and the trainer, and the sections are wall time. hk.maketask.builder 197.7 s
total (1352 us avg, 56.6 ms max), bld.decide 2624 us avg; up.escortrecruit
1345 us avg / 17.6 ms max; up.escecontnets max 26.3 ms; up.planpush 14 us;
dec.nn 4 us (the no-trust skip, was 2.4 ms). Needs the same game on an idle
machine before any verdict, then the perf-review agent on bld.decide.
From ~07:00 the builder net earned trust on two kinds (reclaim 0.33, convert
0.14), so NnScore runs again on every election (dec.nn ~2.4 ms): it scores
all up to 24 options although only trusted kinds are tilted.

### GATE RED "HOME GROUND IS NOT DISCOUNTED" COMES FROM THE SIEGE PRIOR (2026-10-07)

Gate 0687387c (Frozen Ford 2v2 s5/s6): home mexes (homeD 261-435) read
surv 0.59-0.69 with haz=0, loss=0, grad=0. StreamRisk is max(hazard x
shortfall, siege prior x shortfall x (1+grad)); with no hazard the siege prior
alone discounts any home spot the cover reads short at. The same lines in
tonight's 2v2 self-play read surv 1.000 at home. Open: why the gate games read
home cover short (guns gone to the front, or the interior-hole rule not
reaching these spots), and whether the prior should apply inside the base at
all -- his call (the check is his ruling that home is not discounted).

2026-10-08 bisect: NOT a regression of any one change. The 20:08 green gate
(4ad808fd) was a lucky pair. Gate pairs red on home ground at survival
0.56-0.68 with: tonight's code; yesterday's scripts on tonight's DLL;
yesterday's scripts on yesterday's DLL (the exact green build); nets off
(apex_nn_blend=0); lag ladder off (apex_lag_speed=0); Docker stopped.
"First T2 con builds a moho first" flips with machine load (1-2/4 with Docker
running, 4/4 with it stopped) -- it follows the home discount through the
moho's value. The gate cannot clear any build until this is decided.

### THE LAG LADDER STARVES BUILDERS FOR MINUTES WHEN THE SIM TRAILS THE ASKED SPEED (2026-10-03)

Since 3afbf402 lag is measured against the host's asked speed. Eight headless
games at --speed 5, +100%, Comet Catcher vs NullAI
(`tournaments/cadence-fast2/games/r0-g0`): lagSev 0 to minute 14, then 3 by
minute 17; slice 8000 -> 417 us; held 624-718 elections a minute, queued
48-54, worst builder wait 70-150 s. `apex: idlegap` median 202 frames (6.7 s)
over those games against 26 at +0%, where the ladder never trips. Benchmarks
now pass apex_lag_speed=0. Open, his call: a watched game at 10-20x that the
machine cannot hold reads as host lag the same way, and the 417 us floor idles
builders for minutes rather than seconds.

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
- The 2026-10-01 perf audit (132 verified findings ranked by cost; most of the top
  fixed): `git show 6b5dcf1c:docs/34-perf-audit.md`.
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

## OLDER FINDINGS, 2026-09 (compressed 2026-10-15)

One paragraph per finding: the mechanism, the key number, its state then. Most predate the policy
net and many later fixes, so re-measure before acting on one. The full entries, with tables, seeds
and the tries that failed, are in git: `git show 6b5dcf1c:ISSUES.md`. Open items from the retired
docs are folded in at the end of this section.

Evidence runs behind these findings (`tools/prune_runs.py` keeps a run named here):
matches/20260906-105022 matches/20260916-082921 matches/20260916-222751 matches/20260918-055500
matches/20260919-055126 matches/20260921-045243 matches/20261005-013913 matches/_replay-wreason
matches/def-ctl-ff-s3 matches/water-navy-s1 matches/water-ctl-s1 matches/water-treat3-s1
tournaments/20260906-123343-fixes-on tournaments/20260912-141649-scouts2
tournaments/20260915-081342 tournaments/20260921-202615-ctl2v2-gp tournaments/20261003-222042-carrot-now
tournaments/cadence-lossgate2 tournaments/probe-reclobs2 tournaments/20260921-17

### Army and fighting

- **Our army is cheap fodder** (10-06): BARb's standing army is 2.5-3.3x ours at minute 10 on
  equal lab busy time; the record cut leaves labs offering only fodder. Pricing factory time and
  removing losing types after pricing were both tried and reverted: equal army metal still trades
  ~0.55-0.7, so the gap is how the army fights.
- **About half the fighting gap is our assignment layer** (09-23): `apex_stock_army=1` (BARb's own
  task pools, our withdraw off) moved our trade 0.49 -> 0.66 and theirs 1.63 -> 1.12 over 32 games;
  wins unresolved. Withdraw is the first suspect.
- **The binding constraint is the trade ratio** (09-23): we kill 0.33-0.48 of what we lose; we
  kill structures as well as BARb (643k vs 640k) and lose every unit fight 3.3:1. Army metal we
  lose mostly dies on the retreat (59% with `retreat` last; our `behaviour.json` sets 78 retreat
  thresholds, many at 0.6-0.8, stock 26). `apex_retreat_scale` exists for the A/B.
- **We engage at worse odds than stock** (09-20): `quota/thr_mod` neutral vs stock hard's
  attack [0.6,0.8] / defence [0.3,0.5]. Attack at stock values: more fighting, same trade
  (reverted). Defence value untested, his call.
- **Closing** (09-13): a 25-50% lead marched in waves sized to their mobile army into 17k of
  static and never ended the game; ~500 of 730 army deaths were `mov>mov>mov` oscillation between
  push and retreat. The ending wave has to be sized against what stands at the target.
- **The attack bar is per pool** (09-06): stock rewrites each pool's bar to their second-largest
  group; 3% of 507 readings reached it. Promoting pools together and judging with the side's power
  both traded worse (reverted).
- **All allies pick the same attack target** (09-28): own-base distance and a walk-home deadline
  are in the rank; with home well defended allies still converge.
- **Raids find a target in 1-3% of asks; scouting is capped at `quota.scout: 2`** (09-06).
- **The squad arc is capped in angle**, so frontage shrinks with range; past ~15 units a row
  stands shoulder to shoulder.
- **Set-targets do not land**: 1.36M `CmdSetTarget` in a 60-minute game, 1.2% of units hold one.
- **One factory order costs 8-28 ms** (`ConOrderFor` exceeds the 4 ms slice every time).
- **Supreme Isthmus 4v4** (09-29): level to minute 8, then their mexes 23 -> 53 while ours stall
  near 30; our army spend 2.7-2.9x our eco spend with the army target at 0 (cover demand, navy
  budget, spare metal were the buyers).
- **Siege** (09-30): the Paralyzer is priced and never bought; allied Junos fire at the same target;
  forward Catalyst frames die unfinished.
- **Late game, built but unverified** (09-29): rapid cannons never finished in a test; torpedo
  aircraft unconfirmed; bomber pooling hands planes back and forth.
- Residues: `ForwardFraction` runs to the NEAREST enemy, so a raider in the base breaks every "0
  home, 1 their base" reader (37 call sites); the commander's D-gun still kills 1-18 of our own
  buildings a game; `behaviour.json` "power" overrides for threat leak into production worth (22
  defs).

### Defence

- **Defence is elected and the want vanishes** (09-23): 725 defence elections became 116 towers;
  55% of the hands were pulled to something else, 37% with no defence want left to compare. The
  terminal cause found was `def.nosite` firing because the site list was EMPTY: a
  one-fill-per-frame throttle starved the heavy guns. Fixed (first-pass fill): heavy towers 0.8 ->
  5.3 a game, structure lost -19 points, commander deaths unmoved (1.94 vs 1.81).
- **Static defence does not save the commander** (09-23): 63% of commander deaths were inside a
  gun's range. He dies a median ~600 elmo from home to their main line. The lever is his exposure.
- **86% of the structure metal we build is destroyed** (09-23, 16 games). More towers (`apex_t1_tower_late=0`,
  +27%) cut structure loss 101% -> 86% over 32 games; win effect did not replicate.
- **Defence share 2-6% vs BARb's 15-18%** (09-20): roles and pricing fixes moved it ~3x, still a
  third of BARb's; a roled T2 hand's Pulsar is pulled off by the e-stall hoist; half the towers
  built die; crews at completion are ~2 hands.
- **The 10-20 minute hole** (09-18): once the team's best gun is T2, T1 hands proposed nothing;
  fixed (T1 hands fill with their best gun); two of four seeds still thin.
- **Mex guns 57% covered vs BARb's 84% at minute 6**; forward mexes die unguarded 73% of the time,
  because the gun is demanded only once the mex stands.
- **Big frames still leave the turret ring** (09-18): a second AFUS asks a cell where an AFUS frame
  already stands; an old task re-executes for a cell taken long ago.
- **The front-line contract** (`test_frontline.py`) failed unread for weeks after a log format
  change; both arms fail the 75% contract once read honestly.
- **The line** (team front): shields and support-row nanos fire rarely; half of early defence builds
  died before framing (S14 suspected); reach is paid as area; `stopped` prices a single tower near
  zero against an army.
- **Legion config**: every Legion tower in `behaviour_leg.json` carries zero threat; Legion frigate
  and sub read water-only.

### Expansion and the opening

- **Half BARb's ground constructors at every minute** (10-03): fixed to 12.7 cons at minute 10
  (was 5.3); their 23 mexes at 10 against our 15 remain.
- **The mid mexes are lost in transit** (09-22): our cons die at f 0.2-0.4 on the walk out to
  Pawns and Ticks; BARb puts guns forward (1.9 towers at f >= 0.3 vs our 0.6). Escort floor built.
- **Glacier Pass favours the left box for both AIs** (~1.7 mexes); read boxes separately.
- **The lead is lost at home, minutes 4-14** (09-22): the T2 switch zeroed the army target and its
  valve compared a unit count with metal (S28); fixed.
- **It is a holding failure, not acquisition** (09-23): on a 19-spot map there is no free ground
  after minute 8; we build ~18.5 extractors and stand 5, they build ~31 and stand 11. Our base is a
  directionless ~500-elmo bubble; theirs sits ~765 elmo up the attack axis.
- **The loop** (09-23): expansion refused (the walk is lethal) -> metal cannot go to economy ->
  spare metal becomes army by law -> that army is cover and spillover and takes no ground -> back to
  the start. Share levers on the constructor side cannot break it; the trade ratio closes it.
- **We abandon 37% of builds we start, almost 100% of the big and distant ones** (09-23): wind 4%,
  mex 70%, geo 98%, every factory 94-100%. 54-65% of elections change the job and a build 1,800+
  elmo away never survives the walk. The keep-job hold had never fired (the engine detaches the unit
  before every re-election); a peel marker reached 7%.
- **95% of extractor proposals are refused at a gate** (09-23): the commander's leash 40% (89% in
  minutes 0-3). Pricing it (`TUNE_COM_MEX_PRICE`) moved income and commander deaths the right way
  and wins the wrong way (4/32 -> 0/26, unresolved).
- **The energy ladder never climbs** (09-23): wind wins half of every energy election from 20 to
  180 m/s; we reach 2 reactors to their 5 by minute 20. Three reactor tunables have readers that
  nothing calls (`policy.as`).
- **We reach T2 first and wait eight minutes for a fusion**; the T2 switch is a permission, not a
  pull (`TUNE_T2_FUSION_PULL`, off).
- **Opening, 2v2 and 1v1** (09-18..09-22): lab throughput, the con floor taking the lab's first
  minutes, the commander walking into T1 groups, the risk model ceding the middle, and the
  commander's stuck build orders (S27) were each read and partly fixed; fourteen 16-game arms moved
  nothing in opening production; the conversion rung and commander survival did.
- **The 2v2 is decided by minute 4** was retracted: within a start box the minute-4 extractor
  count is a coin flip (AUC 0.53); army differential predicts (0.68 at minute 4).
- **Scarcity** (09-16): at +0 an 8v8 is lost outright (122k metal to 416k); elections go to
  insurance (AA, sense) over income; our extractor count peaks at minute 8-12 and falls.
- **Team games**: allies do not see each other's claims until the mex stands (16 of 39 opening
  spots claimed twice); the pre-contact enemy anchor is the mirror of home, not their start box.
- **A dead mex is not rebuilt quickly**: structural (one ticket in three, every con busy); a
  preemption would be a rule, his call.
- **Every builder is priced as if the map's spots were ours to claim** (09-27): `ClaimableSpots`
  counts allies' mexes and the unscouted enemy half as open; bind `IsOpenSpot`.
- **Navy**: no bot constructor reaches a shipyard site from the Isthmus start; the advanced
  construction sub never elects; on water maps our navy is ~1/4 of BARb's, yards die within a
  minute, warships read `:losing` off records of outnumbered losses, no tidal energy.

### Economy and builders

- **Normal seats do not scale; only the eco seat does** (10-02): per normal seat, 4 standing
  extractors from minute 8 to 20 (BARb 7-8), 84% of claim jobs dropped (`hot-road`), extractors die
  at home 18-22 a game, 0-5 advanced converters to BARb's 5-14. Open, his calls: the defence share,
  the road bar, the army split on a normal seat.
- **The budget cannot balance from the constructor side** (09-23): army is bought at the factory,
  where spare metal becomes army whatever the army row says; defence sits at half its target with
  its corrector railed. Freeing metal from army reached economy, not defence.
- **A quarter of our metal is spent on uncontested wants** (22%, mostly energy and nanos): no price
  can steer a want with no rival.
- **We keep paying for capacity we cannot use** (09-23): Epic Fusion, the Epic converter and drone
  carriers are priced on nameplate, not on what the economy can feed. The scavenger pack costs a
  third of our economy on the eco board; his games run it, so test with it.
- **Nano blobs** (09-22): 53 turrets on one air plant came from the line-shift term counting shared
  lathe once per lower line and reading a capacity as a flow; fixed in `sites.as`. Turret groups
  far from plants are his fortress (a Pulsar ringed with nanos): fortify, do not cut.
- **Hands change their minds mid-walk**: 23% of job changes land within 5 s of the last.
- **Five hover plants, zero hover units**; ~12,500 metal a game into plants, late T1 ones bought
  after their tier stopped mattering. There is no per-plant output log (`fac=` on unit-finished).
- **Converters**: T2 hands rarely ask for the advanced converter, so the basics never retire.
- **Reactors**: no AFUS in an 8v8 at 733 income; price the AFUS on the crew it would get.
- **Build power**: hands bought while hands stand idle (482 constructors in one 2v2); the assist
  dies when every metal is committed.
- **Gantries idle at 1,000 m/s** (three reports): what blocked his gantry is unread.
- **Eco seat**: two gantries starved of nanos with a full bank; its guns stand inside its rows with
  walk gaps; big builds land away from the nanos; a farm past a cliff kills the seat.
- **Economy ladder**: the base ETA swings 17x inside 80 s on the same pool; home reads like the
  front once their army dwarfs ours (no depth term).
- **Room**: the crowding measure falls as the base fills, so every room charge is inert late.
- **BAR's builder priority gadget cannot carry the split** (a passive builder pauses only below a
  fifth of a second of income; synced Lua, not ours).
- **A crewless frame is re-adopted only by a same-def ask**: it should be a finish want priced on
  the remaining bill.
- **The walled-plant move fired on a gantry 11% enclosed**: what counts as swallowed is his call.
- **Lattice residue**: 4-6% of nanos stand off the lattice, hugging fixed sites; mixed pitches leave
  1-3 square strips.
- **Rez**: bots now leave base (10-04 pathfinder fix); ~20-29 of ~50 bots on repair; rez boats are
  bought off land wrecks; the rez chain sends land bots to wrecks across water.
- **Roles and sense**: a refused category releases the role and the draw re-elects into sense.

### Air

- **The 09-29/30 air rework is unmeasured** (decoys, escorts, hunters, scout rules, target
  switch): test on Carrot Mountains against BARb.
- **A T3 nuclear bomber reached the base** and took 43 nanos; what the AA layer prices against one
  T3 flyer is unread.
- **Bombers**: the deadline clock flew wings into AA (since replaced); a run can end before it
  arrives (`ReArm` reads "the bigger force is home" one plane after launch).

### Instruments, performance, tree

- **A hover plant whose units cannot leave reads "open"** and is re-checked ~10x/s; no per-plant
  exit test.
- **16 AIs hold 1x to ~5,600 units**; the engine alone crosses 33 ms at ~6,400.
- **The console log left the chat**; that an hour-scale 8v8 no longer hits LuaUI's emergency collect
  is unverified.
- **Dead accessors**: `policy.as` holds accessors nothing calls (`T2Metal`, `T2Energy`,
  `T2EnergyReactor`, `FusionMinEnergy`...), so their tunables set nothing; `as_scope.py --dead`
  lists them.
- **Tools blind to units under 120 metal**: `army_mix.py`, `expected_units.py`.
- **The repo DLL is the 2026-09-06 build**; a deploy without a local build is refused (S26).
- **`ExecuteWant` throws inside `CmdMoveTo` on a condemned reclaim target**, intermittently.
- **The deploy gate is noise at 2 games**: the same commit read RED(3), GREEN, RED(2); read a RED
  for which check tripped, not as a verdict.
- **Never count a JSON field with grep** (a pretty-printed `winner_specs` read zero wins for a
  whole session); use `tools/wins.py`.
- **Seeding the unit record from his live game** collapsed army spend 12.8% -> 1.3% on identical
  code; `--no-record-seed` exists.

### Folded in from the retired docs (2026-10-15)

- **Exceptions still to become prices** (his 10-04 "start turning them into prices"): the
  extractor-gun queue jump while losses run high (`apex_mex_loss_cover`), the base-front lasers
  (`apex_base_front`), the commander at the lab while escorts are owed (`apex_com_escort`,
  `apex_com_lab_early`), escorts per constructor and their cap. Each should become the price of what
  it prevents; judged against the release that carries the rule, 24+ games, plus the mechanism.
- **Only one builder stops to make energy in a stall**: the hoist fires only while
  `EMakeInFlight() <= 0`. He asks for more builders on MORE solars; more builders on one solar
  measured bad.
- **The 2026-10-01 performance audit** (132 verified findings ranked by cost, most of the top
  fixed) is in git: `git show 6b5dcf1c:docs/34-perf-audit.md`.
