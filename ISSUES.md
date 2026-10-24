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
| 33 | (10-16) Small maps: a ball of Pawns/Grunts early, sent together; a few air scouts; grunts cover more ground | TUNE_EARLY_BALL (off, needs small_hard): fast cheap units priced by the base a ball razes, pool bar = that ball, field watch per metal, scouts not patrol, air scout by unseen metal swept | `earlyball-stat` ord/worth/best N/bar/gathered/sent/killM; `earlyball-ppc` | UNTESTED -- cand-5 small first 6 min/side: armpw 1.5, corak 5.5, heavier 12; armpw pc 0.231 = the cost exponent (one division); patrol miss 0 at 2.8m from 2 Ticks; air scout first at 14-21 min |
| 34 | (10-16) When ahead, the team goes massive air, gathers it and strikes together | TUNE_TEAM_AIR (off): leader prices AIR vs NORMAL (square-law ground with/without the hold's spend + one air sortie), rally behind our lines, joint launch at the need | `teamair-stat` vAir/vNorm, plan; `teamair-go`, `teamair-settled` sent/killed/lost | UNTESTED -- cand-5 vs v0.2.6, 48 games: nnplan rule=NORMAL in 161/161 rows, never AIR |
| 35 | (10-16) Labs open with raiders where they reach them in time; no idle lab in a stall; stop chasing ticks | TUNE_OPEN_RACE (off, race needs small_hard): con floor order raced against the best fighter per metal on one clock; e-stall priced by feed share; hold counts ordered units; DefendTask/GuardTask skip targets fleeing faster than they close, guards skip aircraft they cannot shoot (C++) | `openrace-stat` con/fighter r and winner; `openrace-sum`; `chase-stat` fast/sec/dist/refused | UNTESTED -- barb-open s1/s2: 25 of 40 first lab orders cons, 9 e-stall idles; units nearest a faster foe 144/378 and 164/399 samples, 25 and 37 km walked closing on them; guards engaged corshad 255 times |
| 36 | (10-16, found) smallhard latches gSmhMps (metal per strength) once at start, on a different scale than UnitStrength later: openrace read every fighter as str=2 metal (Pawn, Centurion, Janus alike) until it converted at call time; smallhard's enemy-commander metal (arrive, com=) still uses the latched rate | none yet | `smallhard-stat com=`, `openrace-stat str=` | BROKEN in smallhard (cand-5 baseline); fixed in openrace |
| 37 | (10-16) Pawns/grunts not lost straight to their commander; groups fight what they beat and push, never stand in a fight they lose | TUNE_COM_FIGHT (off): per-group focus-fire estimate (army, towers, commander with D-gun and heal, splash on our clump) every second; win: fight-walk onto the nearest armed enemy; lose: walk to the nearest group/tower/home whose pooled estimate wins; commander in base: pool all base groups or hold home; a no-go sets a keep-out ring until the composition changes; units a mobile threat one-shots or beats head-on split off to raid eco round it; committed raids path around threat (C++ ScriptMove/KeepOut, needs DLL) | `comfight-stat` engage/fall/merged/base, ring set/kept/lifted/dither, split/released/oneShot/ecoKilled, predLost vs lost, comKills, move still/retreat/advance, lostBy com/tower/splash | UNTESTED -- cand11 barbab-c9: 834 of 1128 mobile deaths before 10 min on RAID tasks, 98% standing still; 18,078 m to commanders, 84% on RAID; killers com 19.7% / towers 18.2% / splash 16.5%; BARb dies 54% still, 23% retreating. cand12: 1W 1D 8L; predicted loss 3.5x real was mostly the instrument (base pulls 89,247 of 119,015 predicted); now calibrated + stake-priced fall-back + band hysteresis + one assembly point + hunts + calibrated raid pack size (`comfight-cal`, `comfight-dec`) -- UNTESTED |
| 38 | (10-16) A committed group sets its targets together and kills what deals the damage first (HLLT, MLT, their riot); 10-20 grunts take a mex area with an HLLT and MLT in it | TUNE_FOCUS_FIRE (off, C++): in contact each squad sets targets by their dps on us over our kill time, lethal doses, one-shot members on the next; set-target only, nobody moved; unarmed after armed; with TUNE_COM_FIGHT a group in contact keeps fighting until the estimate pulls it out | `focus-stat`: first=tower/com/riot share and firstArmedS on vs off; lostIn per fight on vs off | UNTESTED (needs DLL) |
| 39 | (10-16) No free damage to their air: AA promptly where their air hurts us; a tower and a bot resist it | TUNE_AA_THREAT (off): places where their air was seen over our buildings or killed ours; static AA sited and priced there at the catalog exchange rate; panic ends only on finished/manned AA (his watch game: an unmanned order held it off 3.5-8.5 min on 3 seats); lab orders a ground AA bot and it guards the army the air is killing; AIRDEF row from the air share / exchange rate | `aathreat-stat` lat per place, bare, withAA, ordered static/mobile, killAir on vs off; `aathreat-aa latS` | UNTESTED |
| 40 | (10-16) Nothing joins a squad once it has launched -- not an attack, a raid or a bombing run; a unit that missed it waits for the next | TUNE_GATHER (off) now also closes the join window for every fighter squad at its launch (C++ IFighterTask JoinOpen at AssignTask, Merge, every election; script launches admit only their claimed roster for 10 s) | `joinwin-stat late=` 0 with the gate on vs the off arm's count; `refused` by kind; deaths alone (gather-stat) | UNTESTED -- needs the DLL rebuilt |
| 41 | (10-16) No unit fed one at a time into work already under way where it arrives too late (non-squad joins) | TUNE_JOIN_ARRIVE (off): one helper (requests/joinarrive.as) for defjoin/unlock, priced assist + idle floor, JoinBig + Take's lab fork, commander rescue, army gift, nano lift, WorthJoiningSite; work left at arrival x the job's worth less trip risk; check.py holds the call sites | `joinarrive-stat` late per path (on vs off), refusals, useS | UNTESTED |
| 42 | (10-16) Con turrets support our labs instead of tons of towers | TUNE_LAB_NANO (off): a lab turret priced by the army m/s it adds, min(turret drain, income/labs - ring) x the feed share a stall gives it (market/labnano.as); was spare-metal only, so a spent economy priced zero (watch: feed=0, floor=0, 0 nano wins vs 50 defence) | `labnano-stat` turrets/lab, beat/both, won vs towerWon; `nanowant lab=` | UNTESTED |
| 43 | (found 10-16) Pawn/grunt carry attribute "scout", which the loader adds as a role, so every IsRoleAny(SCOUT.mask) test treats them as scouts: fixed in PatrolFodder (early ball) and the squad claim (army.as SqDef, main role); STILL in air/state.as:733, market/army.as:694 (scout fleet), guards.as:582, production.as:702/1166, smallhard.as:351, worth.as:355, hooks.as:349 | one helper (main role == SCOUT) for all + a check.py rule forbidding IsRoleAny(SCOUT.mask) | grep IsRoleAny(Unit::Role::SCOUT.mask) | OPEN -- changes v0.2.7 pricing, needs its own A/B |
| 44 | Why so many amphibious units? (10-16; armamph 29 vs armzeus 30 over 12 games, prodrank p=0.360 top) | TUNE_SURF_DPS: land valuations read surface dps/alpha and LAND range, AA ones air dps/range (catalog gSurfDps/gAirDps/gLandRange/gAirRange; C++ DpsVs/RangeVs in SquadTask, GuardTask); dps was not the cause (armamph 109/109/63), range is (600 missile vs 275 laser); needs the rebuilt DLL | `apex: surfdps` (armamph range old vs land); produce: armamph vs armzeus/armfido; prodrank armamph p | UNTESTED |
| 45 | Every seat eventually makes air; air reacts to enemy air with fighters (10-16; v0.2.8 online: 1 air plant in 4 seats at min 28, t10 wing `go=0 held=3`, fliers IDLE=5) | TUNE_AIR_EVERY: air plant priced per seat (bars gone), wing GO at cells the planes at home beat, fighters priced on their air and hunting as whole flights | `apex: airevery-stat` seats=, plantV/altV, wing=, small=, foeAir/ourFtrM/ftrWant/ftrPend, hunt=; his test: 1v1 Carrot Mountains, our plant answers their air with fighters | UNTESTED |
| 46 | Bastions against enemy T3, especially when rich (10-17, v0.2.8 Legion vs BARb: 0 Bastions; defrank legbastion kill=83 vs legapopupdef 480, enemy T3 129,745 m at 26 min) | the game renamed sweepfire to sweepfire_firetime/_reloadtime, so 0331ca7f went silent; CircuitDef reads the new keys as common/weapons.lua does (legbastion 25 shots/3 s = 1,292 dps, was 52) and logs any sweepfire key it does not read (trap S58) | `apex: sweepfire` / `sweepfire-unread`; defrank legbastion kill=; placed legbastion | FIRES -- sweep-s60 reads all 5 sweepfire defs; no game read for Bastion builds yet |
| 47 | A lost or abandoned lab/gantry is rebuilt in a rush (10-17, v0.2.8 Cortex vs BARb: coralab order left by its builder 2 s after exec, `latency coralab dropped=300 workers=0`, re-asked at 18.1 min) | TUNE_ORDER_RELEASE: an order with no worker and no frame stops counting in LiveOfDef, T2LabComing, SuperCensus, LiveCountOf and the plant unlock reads; the re-ask adopts it or aborts and founds afresh. The builder is pulled by the C++ con guard (UpdateRezGuard), untouched | `apex: order-release` by=left then adopt/refound with age= in seconds; `latency <lab> dropped=` should vanish | UNTESTED |
| 48 | Nanos go up while the gantry is being built (10-17) | TUNE_NANO_EARLY: T2+ plant frames join GantryShortSite and the nano floor | `nanowant gantry=frame:N/M`, `frames=` | FIRES -- ab3 on-arm (Legion vs BARb Carrot, seeds 71-74): 13-17 frame readings a game; watch lane on |
| 49 | The gantry goes up alongside a nuke/anti-nuke/cannon, not behind it (10-17) | TUNE_GANTRY_OWN_SLOT | `gantry-why` super-in-flight count; gantry finish minute | FIRES -- ab3 seeds 71-74: gantry finished in 4/4 on (21.9, 25.4, 26.4, 31.2 min) vs 1/4 off (34.4); super-in-flight 0 on vs 12-24 off. Games: on 1W 3D, off 3W 1D, no losses -- not resolved; on-s72 eco behind from min 10 (34 vs 66 m/s) before any gantry. Watch lane on |
| 50 | Commanders walk out into space on a space map (10-17, his online v0.2.9 game on Project SD-129: 6 of 8 commanders evading from 20.1 min at hp=100 toward `to=14183,8093 d=600`, `com-still 30.0s` 3-9 times each) | ComWalks: ComEvadePos, the ComSafePoint step-back, the ship trap and the low-hp flee ask `CanDefReachAt` from where he stands, not only `OnMap` | `com-retreat ... voids=N`; `com-still 30.0s` with site@>=400 | FIRES -- west seat seed 81: voids 28-65 per commander, no far stall on an evade. Not reproduced vs BARb: east seats seed 82, control 0 far evade stalls, fix voids=0. Unverified until a space-map game against people |
| 51 | Bombed for minutes with no ground AA; fighters no longer protect allies; their gunships do tons of damage (10-17, his v0.2.9 SD-129 game: aathreat places hurt with `static=0`, lat up to 393 s; first `intercepting for ally` at 34.2 of 54 min; legfort read as a fighter, 57,498 of 57,608 m of their air) | `EvSnapFoeAir` counts a plane that hits the ground as strike too; TUNE_ALLY_AIR flies interceptors to the ally's worst air-damage place; TUNE_AA_THREAT (built 10-16) | `aathreat-aa latS`, AA towers placed, `intercepting for ally ... at=` | AA_THREAT FIRES -- 6 pairs Red Comet 4v4 vs Apex v0.2.9 (s91-96, two with their plan forced to AIR and +50%): AA towers on/off 17/3, 33/19, 26/23, 18/19, 20/6, 25/2, results identical in every pair; air loss per minute higher on in 5/6, confounded (the on arm lived longer into their T2 air); only T1 rocket towers. ALLY_AIR never fired (no spare fighters: fighter want reads only air seen now, 120-640 m) |
| 52 | Same complaint, the second pass: fighters against the air that hurt us, and AA that is not always the T1 rocket tower | TUNE_AIR_ANSWER: fighter want from the remembered raid over our ground; AA exchange rate times the reach share against their stand-off; killers join the reference; a loss under standing AA raises the place's air; a plant owed fighters is not all-quiet | `airanswer-stat` (want mem vs now, ordered, held; aa=[def:v/tr/re/st/sat/top]); fighters built; AA defs placed; air loss per minute | UNTESTED |
| 53 | A counter for the unseen threat players attack with: jammer-supported armies (10-17, after online games) | TUNE_JAM_SIGHT: suspected places from radar contacts vanishing inside our coverage, jammers seen, our losses to unseen shooters; their metal in ThreatAt/HazardWith/TripRisk and raid/escort sizing; a camera tower or a scout look over them priced by the loss they threaten | `jamsight-stat` (places, vanish, hit/hitT, orders, looked, revealed); `sightpost` | UNTESTED |
| 54 | Fusions and upgraded mexes first, so the economy scales and air is affordable (10-17) | TUNE_T2_ECO: the next-tier rule reads the ladder's lab pick at its funded share; the super push and next-tier hoist yield a ceiling hand to its upgrades | `t2eco-stat` (`etaOnly`, `superYield`, fus/up won); T2 lab finish minute; mohos and fusions by minute 20 | UNTESTED |
| 55 | No factory unless we strongly want its products; no market-value override; never two advanced labs at once (10-18, +100 scav) | nntech NOW hoist removed, gantry not super-pushed, TUNE_ADV_LAB_WAIT reads TreeTier (7eb4b133); TUNE_INFLIGHT_HOLD (bcd454c0) | aacount.py advPlantPicks/overlaps; `why=nntech|super` on plants = 0 ; 10-18 his normal 2v2 (watch-1018e) still raised two advanced labs per seat at ~40 m/s, the second in the tech market at half the unlock: TUNE_UNLOCK_ONCE now zeroes the unlock beside a standing or ordered kin, TUNE_HANDS_ONCE prices the second as a line | FIRES -- lane seeds 31-33 his setup: picks 132/201/98 -> 35/45/49, overlaps 24/53/18 -> 8/5/13; not yet in his game |
| 56 | Less AA bots, more AA static when they have little air (10-18) | mobile AA answer x AnswerShare() (bcd454c0) | aacount.py aaBots/aaTowers | FIRES -- lane seeds 31-33: bots 88/125/57 -> 18/50/16, towers 32/22/17 -> 47/40/26; not yet in his game |
| 57 | Buildings too spread out, we waste room (10-18) | TUNE_LATHE_CONCENTRATE (bcd454c0, off) | layout.py clusters/seat, ground used | UNTESTED -- A/B running; baseline ~35-37 clusters/seat, 29% ground used at min 15 |
| 59 | We build Pawn Launchers but do not use them (10-18) | a stockpile weapon that spawns units is an LRPC-class buy, not a silo (4454012b), and gets the super-weapon aiming task | `apex: super fire armbotrail`; armbotrail built per game (was 23-28) | UNTESTED -- in watch-1018c and aocab |
| 60 | Rich and overflowing but we cannot spend it: more nanos, more units, mass T1 (10-18 2v2) | while the bank overflows (MetalWasting) the :losing, :outgrown and T1-air-mute drops stand down, as the yield rule already did, and the metal con role is not worth doing | prodrank :losing/:outgrown while bank full; bank-full minutes; decide why=role role=metal while wasting | UNTESTED (apex_m_realize: extraction and converter metal priced by the spendable share, no headroom at a full bank, floor = ordered build power share) -- his 2v2 seat t1: 105-408 m/s, bank 1620/1700, vehicle plant all :losing, bot lab :losing/:outgrown, cons hoisted onto extractors at v=102 over nanos v=34. The :outgrown and T1-air lifts were taken back 10-19 (row 61) |
| 61 | Fewer, stronger units; reclaim idle nanos and unneeded labs (10-19) | a full bank no longer lifts the outgrown T1 tier (apex_spill_outgrown 0); an idle nano turret is a priced reclaim victim (apex_reclaim_idle_nano 1) | late army by def; nano turrets late; units at min 40; frame ms | PARTLY -- his Odderon: Parrow/Vamp top the army, nanos 817 -> 551, units -7-10%; clean A/B (matches/hispair) running |
| 62 | A teammate with no commander, no base and no income kept getting our units (10-19) | a seat asks for gifted army only while its standing economy plus a living commander outweighs the gap (TUNE_GIFT_STAKE, off) | `apex: gift-stake`; gift metal to a seat after its commander dies | UNTESTED -- his watch games: single gifts of 111 units / 62k m and 123 units / 91k m |
| 63 | Not enough anti-nukes while the enemy launches a lot of nukes (10-19; "about 6 at once... ~10 nukes all on your base you WILL die") | survive their worst salvo by arithmetic: every seen silo full (its stockpilelimit), fired together, / TUNE_ANTI_AT_ONCE (6) = antis each target needs -- the core and any cluster worth more than those antis; launches seen floor the salvo for unseen silos and lift the income floor | `apex: nukemath facts` (startup: armamd=20/90s armsilo=10/120s corsilo=10/180s), `apex: nukepress`; antis over the core vs ceil(salvo/6) | BUILT -- math checked against the unit files; no game test (his 10-19: "you can get it all through math") |
| 64 | No T1 lab in an ally's open lane (10-22) | apex_fac_lanes (lab sites refuse any base lane, ours or an ally's, and a friendly lab's door), apex_lane_reclaim (an idle plant in a lane priced for reclaim) | `fac-site-moved ... others=0`, `plant-in-lane` | FIRES -- check games 10-22: 1 site refused (Isthmus), 2 idle lane labs reclaimed |
| 65 | Air not sent at an underwater mex (10-22) | BombTask uses IsInWater; NaSnapEnemy drops submerged eco from the prize (5a3df3a1) | `bomb ... nPower` skips; strike cells on a water map | UNTESTED -- no water map run |
| 66 | Stop sending air into heavy AA (10-22) | apex_air_obs_evidence: a scored run weighs by bombers sent over the wing planned (5a3df3a1) | `air run scored ... plan= w=`, bombers bought after failed runs | FIRES -- 10-23 games log plan/w; no game yet with mass failed runs |
| 67 | One con looping on a far lab, hot road (his 10-23 game, 74 orders) | apex_hot_road_memo: the refused road's hottest square read live at the next election (5a3df3a1) | `elec-slice hotRoad=`, repeats of `task-die ... why=hot-road` per unit | FIRES -- per-hand memo: 11 different cons still walked into one refused road (Isthmus 10-23), so it is shared by the team; a reach test joined it (two ship cons re-elected an inland gun, and the floor guarded land bosses 154 times in 35 s). Isthmus unreach-safe aborts per game: 302/216 off, 29-55 on. Eco (ours, 25 min vs BARb hard): off 30/23/19/19k, on 19/25/20/20/24/21k -- no cost seen |
| 68 | APM under control (10-22) | apex_keep_route (649374e6) | `apex: cmds` army per unit-minute | OFF -- vs BARb hard (3 pairs) travel orders per army unit fell (31->27, 47->24) with no harm seen, but on Starwatcher vs v0.3.5 (1v1 +50) c9 went 6-13 with it on and 5-3 with it off (10-23): off until a larger big-map run says otherwise |
| 69 | Basic mex defence: one LLT covers one or more mexes, with a raider-range buffer (10-23) | apex_mex_basic (8db03f05), released v0.3.7 | mexes lost before minute 12 (mexdef/mexcover scripts), `cover-push` | VERIFIED -- 24 games vs v0.3.6: 18-6 (CI 55-88%); mexes lost before 12 min 9.1 vs 18.0, light towers 16.3 vs 7.8 |
| 70 | Rich seats make more air (10-23) | apex_air_rich, shipped in v0.3.8 as a TRIAL (TUNE_TRIAL_AIR_RICH: a coin per seat) | `python tools/trial_report.py` after his multiplayer games | TRIAL RUNNING -- 16 2v2 games vs v0.3.7: 7-6, +26% bombers. Decide at 8+ paired games (sign test), then set the switch, end the trial, delete the coin |
| 71 | Air bought on price, no income bar (10-23, "i do like things priced") | apex_air_eco_priced, shipped in v0.3.9 as a TRIAL (TUNE_TRIAL_AIR_ECO_PRICED, its own coin) | `python tools/trial_report.py` after his multiplayer games | TRIAL RUNNING -- 24 1v1 games vs v0.3.8: 12-10 (+2 cap); gunships 6.7 a seat vs 0.7, peak income 589 vs 520. Decide at 8+ paired games |
| 72 | T3 units not trapped by allies' turrets at clustered gantries (10-24) | apex_door_clear (ce04801c), released v0.4.0 | `doorRefused=` per minute; his hosted games with clustered gantries | FIRES -- 192/733 refusals a 2v2 game; the trap itself not reproduced in tests: watch his games |
| 73 | Gunships don't hover in AA; remembered pain points (10-23) | apex_gun_refuse, apex_aa_dwell, start-box guess (74cc5616), released v0.4.0 | `raid-refused`, `nnair-refused`, `gun run scored` | FIRES -- scenarios: refusals recall the wing; the release air net still overrides WAIT (his call: net decides, targeted training next) |

## TURRET PILES: THE KNOT RULE, LEFT FOR NOW (2026-10-24)

His must-fix "large concentrations of defenses all in one tiny area" had two causes in the 8v8 Starwatcher +65 runs.
The doorway/interior-waiver one is fixed (apex_mex_cover_site). The other is the knot rule (protect_knot.as): a gun
beside standing guns is priced up (kappa ~2) until the knot's cover beats the wave expected there -- seat 2 put 10
turrets (~2.6k: 3 HLT, 2 Pit Bull, 2 Beamer, 3 LLT) at a front/wall site over minutes 16-24 (matches/clust0). Working
as designed; if the wave estimate is inflated the knot keeps growing. His 10-24: "unsure about the knot rule, leave
for now". Watch his games for it (`apex: defplace ... knot= kappa=`, `tools` defclust on a match).

## OUR LONG-RANGE GUN ORDERS DIE: ~85-90% NEVER FINISH (2026-10-24)

His ask: our own LRPC massing (he won Canis River with ~17; ours stop at 0-8 a seat). Measured, 2v2 +100 vs v0.4.0,
Starwatcher + FolsomDamR, four 8-game runs (`tournaments/20261024-0239*`, `-0330*`, `-0411*`, `-0450*`):
- Orders are not the limit: 613 gun orders in one run. Tasks are: 2-25% of gun tasks end in a finished gun per run,
  in BOTH versions (pooled ~11%). Deaths: frames killed (`target-killed`), `unreach-safe` (C++ refuses the road for
  threat), `hurt-retreat`. 85-95% of elected sites stood >3000 from the seat's start; the guns built stood at 150-2300.
- The site is the heavy defence's (`SuperSite(SC_HEAVY)`): a gate, the edge of the ground the team holds -- in a 2v2
  the hull of both allies (Starwatcher allies start ~6,000 apart). From home the gun reaches nothing on these maps
  (reach gain 11-17 vs 127-252 at gates): standing forward is right; surviving there is the problem.
- THE DEFECT: the risk model reads those gate sites at survival 0.44-0.50 over the build (`StreamSurvivalOver`) while
  ~4% of tasks begun there finish. Killed frames never entered the loss field (only `WasFinished` deaths do); adding
  them (cost x progress) moved gate survival 0.50 -> 0.44 only. Three site changes were measured and reverted
  (26af972c / e39762ca): none moved completion.
- In his hosted games the failure differs: no `unreach-safe`; frames killed even near base, and early the
  affordability gate (bill > a minute of income).
- His 10-24 answer: build there; if it fails, porc up and defend the area. Tried (b55b9eec / 9bc6be2b, reverted):
  a failed gun site as stake (turrets near failed sites 44 vs v0.4.0's 45), then also as a defence site (16 vs 52).
  The defence market will not buy at those sites -- its PRICE there (stake vs the forward threat, the target
  already met) is the next thing to read, with a defprice line for those sites. Also open: a realized-completion
  price on the gun itself. Unstable still carries apex_lrpc_prize (1c52e5a4, on): neutral, 2-2.

## A T1 LAB IN AN ALLY'S OPEN LANE (2026-10-22)

His hosted game, 10-22 (v0.3.5): our AI put an unused T1 lab right in an ally's open lane, which is not supposed to
be blocked. Unmeasured -- pull the replay of that game. Two parts: (1) the plant site keeps off our own lanes
(IsInBaseLane) and allies' factory doorways (OffAllyExit), but no check guards an ally's movement lanes; (2) an
idle plant standing in a lane is not priced to move. The reclaim market already prices a plant our own turrets
walled in (plant-walled, PlantEnclosure); a lane it blocks for an ally belongs in the same price -- the ally's
blocked traffic against a lab producing nothing.

Audit (10-22, read-only agent): NO path checks an ally's open lanes before placing a factory. (1) C++ commit:
FACTORY is IsFixedSite (BuilderTask.cpp:67), so SitePredicate's IsInBaseLane (1795) never runs for labs -- not
even our own or in-process allies' TeamLanes; Execute snaps/re-origins the site (609-628); CBFactoryTask's handed-
site test (FactoryTask.cpp:164-172) checks footprint, zones, spots and its OWN door only, no block map; the
fallback spiral (186-245, up to 1600) checks reach, clearance, own door. (2) InteriorSite (sites.as:1348-1396)
sets most labs sideways across our axis, ReachableBy only. (3) Gantry/air-plant branch (execute.as:843-851):
spots + our plants only; air plant doorway=false in LatheSiteRaw (sites.as:878); the forced T1 air plant
(want_super.as:1214-1250). (4) FirstPlantSite (execute.as:1675-1766): no AllyLaneHit/OffFactoryExit/
OffAllyBuildings. (5) PlantNudge's second ProbedSite returned unchecked (execute.as:1770-1802). (6) Site caches
reused unchecked (sites.as:797, 815-829, 1634-1640); ally list 5 s. Existing ally guards: AllyLaneHit (doorways
220x100, execute.as:143-189), OffAllyBuildings (defence and lifts only), block-map aprons (engine searches only);
the ally_base option feeds SetAllyZoneRange, never called (main.as:45 commented out); Base::InLaneAt has no callers.
Fix: one chokepoint in CBFactoryTask::TryBuildSite (handed site and spiral) refusing our lanes, in-process allies'
lanes, any ally factory door or apron and allied bases; one script PlantSiteOk for FirstPlantSite, PlantNudge's
last result and the gantry/air-plant branch.

## TURRET APM AND BUILDER ELECTIONS LATE (2026-10-22)

His 10-22: "one thing that lags me is probably all the con turrets... throttle it so APM doesn't go out of control."
Measured in the v0.3.5/v0.3.4 4v4s (Supreme Isthmus, 50 min), ms per AI per frame after minute 30: the turrets'
own idle job facIdle 0.031/0.032 -- cheap; the constructors' idle job bldIdle 0.337 (v0.3.4) / 0.414 (v0.3.5),
nearly the 0.417 budget alone. Command volume is NOT measured: `apex: orders`/`order-src` count army orders only;
repair/assist/reclaim/guard commands to turrets and constructors are uncounted. Every idle unit is re-asked each
15 frames (CIdleTask, apex_idle_ask_f), so hundreds of idle turrets could issue hundreds of commands a second --
network and sim cost on every client in a hosted game, invisible to the AI's own timing. Next: count commands by
unit kind in the C++ command wrappers; then wake a turret only when work enters its reach (a frame, a damaged
unit, a wreck) instead of re-asking it on a clock; then slice the builder elections (ai-performance procedure).

Measured 10-22/23 with the new `apex: cmds` counter (2v2 vs BARb hard, Comet/Isthmus, 30 min), commands per minute
per AI at the peak: turrets 32-52, constructors 326-560, army 700-1,012 (moves). So turrets are NOT the flood; the
army is, ~33 commands per army unit per minute -- one every 2 s. Repeats within 3 s are ~7% of moves, bit-identical
ones (apex_order_dedupe's candidates) 1-6 a minute: the dedupe would buy <1%. Travel (waypoint steps) is ~2/3 of
moves, but doubling the waypoint spacing (apex_travel_step 2, reverted) cut travel per unit only 15% and all army
commands 6%: the orders come from units being handed fresh paths (each new TravelAction issues at once), a
carrot re-set every couple of seconds, not from reaching waypoints. Next: find who re-paths every ~2 s (squad
update / AttackTask / regroup) and hold a unit's order while its goal has not moved enough to change its route.

10-23: traced (apex_order_trace, 20-min 2v2): 20,125 route changes, builders 55% (115 per builder), retreats 15%,
scouts 13%, raids 9%; 70-90% of them moved the goal under 64 elmos. apex_keep_route (on, 649374e6) keeps the
route being walked when the new one ends within 64 of it: 15-27k routes kept a game, army commands per army unit
per minute 16-20 in three of four games against 25-33 before (the fourth, 31, was a game lost early). What is
left is mostly units near enemies, which the lean path deliberately re-orders every second.
apex_travel_samestep (off) measured on four games: Comet -34%, Isthmus +20% -- noise, left off.
OPEN: apex_keep_route is on with one outcome pair (keep0 vs keep1, 25 min, we lost more with it, 29k vs 18k);
needs ~8 paired games for the result before it is kept.

## TOO AFRAID OF STATIC DEFENCES (2026-10-23)

A player's feedback via him, 10-22. Not the attack choice. Scenarios (tools/scenarios/
tower_light, tower_heavy, tower_line) all PASS on the stock army: 10 Centurions kill 3 LLTs or 2 HLTs and
their mexes, 16 break a line of 8 LLT + 2 HLT, 0-3 lost. His hosted v0.3.5 games keep 50-74% of the army on
ATTACK from minute 5 to 35. Stock StockFindTarget still divides a distance by a squared distance (the fork bug
AttackTask.cpp fixed for our path), which shrinks a group's influence toward 0 away from base -- reckless, not
afraid. Untested: the threat-aware route walking around tower cover, and the retreat thresholds near towers.
Needs what the player actually saw.

## GUNSHIPS GO IN AND OUT (2026-10-23)

His watch: a 40-gunship wing lingered over their base under AA and never committed. Two causes, measured with
tools/scenarios/gunship_aa_hidden (12 Brawlers vs 6 light AA + a flak, normal LOS):
- THE GUESS IS WRONG: the unseen-base cell (nnair.as, kind 1) is our start MIRRORED; on a map whose starts are not
  point-symmetric it is empty. The wing flew GO -> arrive -> WAIT -> GO at (2629,347), worth 13-20 metal, ten
  times in four minutes; their base was at (3708,2220). The army press had the same bug (fixed with the nearest
  enemy start box, CSetupManager::GetNearestEnemyBox).
- AT THE REAL BASE IT HOVERS: a committed air raid keeps the threat test (RaidTask FindTarget), refuses every
  target under the AA and stays (`raid-commit ... target=- aaSet=24`).
Tried: never recall a committed wing + fight inside the goal without the threat test (apex_gun_commit) -- WORSE on
the hidden scenario, 7 Brawlers (2,170 m) lost for 440 m killed, against 0 lost off. Removed.
Next: the unseen cell from the enemy start box; a committed wing that finds nothing it can take at its goal leaves
at once and the cell's AA is remembered as a pain point, so it is not priced cheap again until the wing can take
it (TODO: pain points).
10-23 later: built (74cc5616: apex_gun_refuse, apex_aa_dwell, the start-box guess; 8f907f1b: `gun run scored`,
not yet run). 24 1v1 +50 games vs v0.3.9: 12-11 (+1 cap), CI 33-71%, 0 errors; 15 refusals recalled a wing.
NOT RELEASED -- no measured gain. What still sends wings into AA: the release's air net picking GO over the rule's
WAIT (GO weight 0.90-0.98). His call: the net keeps deciding; next is targeted training on scored gunship runs.

## AIR ATTACKS AN UNDERWATER EXTRACTOR (2026-10-22)

His watch, 10-22: air units trying to attack a mex underwater. Aircraft that cannot hit a submerged target were
sent at one, a wasted strike. Unmeasured: find the target choice (C++ attack/bomb tasks or the script's strike
target) and whether it checks the weapon can reach a target below the water line. The fix belongs in the pricing
of the target (a strike that cannot land is worth nothing), not a filter added on top.
10-23: CBombTask skipped only targets below y=-40; a building on a shallow seabed passed. Now IsInWater, and the
strike planner's prize leaves submerged economy out (validation #65).

## ECO AT HALF HIS CURVE; WHAT 10-21/10-22 MEASURED (2026-10-22)

At +50 like for like (his ask: "Test at +50 to match"; 8 seeds, b50-base-s3100..3107): minute 4 we stand 11-13
extractors, 3-4 basic solars, 0 turrets to his 15 / 11 / 7; T2 at 8.0-9.3 to his 6; 0 mohos at minute 8 to his 6;
0-2 mohos and 8-23 turrets at minute 10 to his 15 and 62; 531-879 m/s at minute 16 to his 1,570. Extractors are
close throughout -- the gap is energy and build power from minute 2 (his: "focusing too much on metal extractors,
not enough on energy and build power"). The first five minutes are extractors by the ladder and solars only under
a stall; the T2 plant is built by one hand for ~220 s (seed 2913: ordered 4.0, standing 7.75, cap 11).

Run-to-run noise: identical settings and seeds read -20.4% and +6.3% (6 seeds); 12 seeds flipped sign twice.
Score on the mean of minutes 16-20 over 24 paired seeds. Measured and removed (commit messages have the detail):
zone stack -16.8% (12; code kept, off); eco turret energy density +1.0% (12); bot opening +0.3% (24); stall race
counting energy payback ~0 (24); spend-capped ETA ladder with turret steps -10.7% (24); forced canon pattern
(solars only on short energy) stalled the economy (smoke, reverted); ETA energy output at the bills' rate -4.9%
(24); hands-only crew record and band crew (only inside the zone stack); a big generator's crew from current
capacity plus the market's room price in the ladder -0.5% (24; AFUS within 2-8% of the fusion in the ETA, still
1 AFUS and 12 fusions at minute 20). Each moved its decision; none moved income. The zone stack is deleted (his
10-22: his rectangles are a UI aid for human APM, not a layout for the AI); the C++ zone hooks (ZoneRefuses,
ReserveZone/ClearZones) are inert and left for the next DLL build to drop.

His own +0 air game, replayed (matches/_replay-his0, his 10-22): 869 m/s at 20:02, 4,100 at 30. Level with us to
minute 10 (we waste 14-18 m/s at minutes 6-8, he none); from minute 12 he stops small eco at 53 extractors / 11
solars / 18 advanced solars and builds only mohos, AFUS, advanced converters and turrets -- minute 20: 10 AFUS,
2 fusions, 48 converters, 238 turrets to our 0 / 12 / 6 / 141. Target since 10-22: 750+ m/s reliably.

v0.3.5 AGAINST v0.3.4 (released 10-22, his call to ship): 20 games, no crashes/errors/desyncs. 1v1 small maps 4-3
(1 capped); 2v2 Comet Catcher 2-0 (2 capped, split), Greenest Fields 4 capped and even (no metal spots there). 4v4
Supreme Isthmus 4 capped: v0.3.5 eco -7%, army -9%, behind on eco in 3 of 4, 50% more turrets (60 to 40 per AI),
AI time +7% mean and +22% on worst minutes (more units: +10%), both versions well over the 0.417 ms budget there.
The eco tuning ran with no enemy army; the 4v4 gap is the lead to follow.

WHERE THE METAL GOES (his replay vs the median of 24 base games, tmp spend.py): by minute 10 both made 23.3k metal;
he spent 20.4k and wasted 0, we spent 16.0k and wasted 3.8k (16%, the bank full from ~5.5 min). By 14: 66k spent
to our 45k. His T2 air plant at 8.34 (ours 9.25 median, 8.1-11.3), a T2 constructor every ~18 s from 8.64 (ours
every 24-36 s from 9.78): 5 by minute 10 to our 1, so 8 mohos at 12 to our 2. Basic air constructors are level.
Also measured and removed: a big generator priced with its turret ring (no decision moved: fusion won 51/51);
turret demand from the ladder's lathe/feed ratio -35.1% over 24 seeds (turrets at his count, 30 at minute 12, but
extractors 38 to 55 and mohos 6 to 20 at 16 -- turrets cannot claim spots). The ladder's tBuild/tFeed reads 4-12x
all game because P counts unconverted energy as metal; it is not a turret signal as it stands.

## HIS +100 SCAV 8v8 FAILS THE FRAME BUDGET 4.3x (2026-10-18)

**10-19: the 16-AI benchmark passes again** (Greenest Fields, 8 Apex per side, +100, seed 1, solo, his watch-lane
switches): 0.334 ms per AI per frame at the worst minute (34), peaking at 3,363 units (matches/perfbench-1019c).
Earlier the same day it failed at 0.528 ms (min 35, 3,200-3,400 units, 4.1-4.2 ms per unit-minute); now 2.5-2.9
at the same size. The late cost was elections ending in aborts: radar sites an ally covers (2,111 aborts) and
reclaim under threat (683), fixed in 1dfb106f. His +100 scav 8v8 (income x2, ~4,500 units) still fails, 1.5-1.7
ms; the engine is 75-85% of the late frame there and in the benchmark (34-51 ms a frame at ~3,000 units).

Solo run, nothing else on the machine (matches/perfsolo/base-s32; 8 Apex vs 8 BARb hard, Comet Catcher
Remake, +100, income x2, scav units, flush placement on): 1.771 ms per AI per frame at min 20, 4,537
units. The 16-Apex Greenest Fields benchmark passes (0.403); this setup does not. Builder elections are
~55%: hk.maketask.builder 155 s, job:bldIdle 143 s, bld.decide 40,581 decisions at 2.6 ms; elec-slice
asks 3-4 ms a frame (sliceUs) for 50-60 constructors a seat, oppFlips ~1,000 a minute on one seat.
Levers measured so far: TUNE_CON_USE (a third fewer cons, eco not better, off); TUNE_HOIST_WAITS and the
four price switches in A/B (matches/hpab). Next: fewer flips per con, cheaper decisions (memo misses:
mc.protect 7,878 of 15,561 asks).

Memo census (memo.m.*, 18-min solo run of his setup, matches/memocensus-w4): 30,293 hits against 41,366
misses -- ownership/position 25,336, empty or evicted 11,896, age 2,500, stall/full flags 1,634. A
proposer's key carries the asker's cell, and hands move between elections, so most misses are the same
hand one cell on. Widening the rows 4 -> 16 traded own misses for empty ones (20,051 / 16,906) with no
gain. The fix is structural: memo the asker-independent part of a proposal (candidate scan, site search
-- pw.cands, prot.loop, plant.lathesite, sense.*) and re-price only the walk per asker on a hit. Biggest
first: want.protect 17.6 s, want.plant 17.6 s, want.sense 13.2 s, want.nano 12.4 s of a 27-min game.
Constructor count is the other half: decisions scale with hands (40-60 a seat), see TUNE_CON_PRICED.

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

### WHERE PERFORMANCE STANDS, AND WHAT IS LEFT (2026-10-18)

16-Apex 8v8 (Delta Siege Dry, 40 min, seed 1): 0.404 ms/AI/frame at the worst minute with
~3,000 units (c9-ds16-final2, ce0bd570; session start 0.433 at 2,500). Slow update over
10 ms in 0 of 641 player-minutes (was 155); elections over 10 ms 40 of 620 (was 210); idle
builder gap 36.5 -> 29 frames. Canonical Greenest Fields vs 8 BARb: 0.298 PASS, but those
games end at 30-32 min (lost), so equal-unit minutes are the comparison (10-25% lower). Open:
- The AiFrame hook is in the fork (d8b9b93a on barbarian-apex) and in release/v0.3.2
  (worktree ../bar-ai-rel032, not merged, pushed or tagged): it reaches his games only when
  that release ships. The shared slot's BARb tree is behind the fork by that commit.
- `sync_cpp.py pull` finds no merge base between barbarian-apex and apex/barbarian since the
  10-16 restore, and 0003-cumulative.patch is stale.
- Per election ~2.7 ms in the late game: want.protect, want.sense (the jammer price is ~0.3 ms,
  its coverage checks and engine site search), nn.policy ~0.55. The young-return backoff makes
  ~20% more elections than the flat 2 s gate did; that is the responsiveness bought.
- Every allied seat walks the same enemy registry in FoeMemStep (~0.45 ms a tick, 1,500
  enemies); sharing it within an ally team is the next large cut.
- Benchmarks here read machine stalls as AI cost (c9-ds16-frame min 35 doubled every section,
  C++ jobs included). Read the C++ job rows before believing a FAIL.

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
