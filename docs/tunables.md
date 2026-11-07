# Tunables: why a default is what it is

Defaults live in `ai/Unstable/game-side/script/standard/tunables.as` (`TUNE_<NAME>` = modoption
`apex_<name>`); where this file disagrees, tunables.as wins. One line per knob that has a
measurement or a ruling behind it: `grep TUNE_X docs/tunables.md`. No entry = no recorded result.
The long form (seeds, tables, earlier tries) is in git: `git log -p docs/tunables.md` (older: `docs/27-tunable-rationale.md`).
A tunable is the last resort (`working.md`); a proven change deletes its gate and constant. An
override reaches a game only through the deployed `dev_tunables.lua` gadget (S8).

## Economy -- energy, fusion, converters, reclaim

- `TUNE_ETA` = 1. Carrot 1v1 vs BARb, 12 games: income at 30 min 188 -> 236 m/s, mexes 69 -> 100, losses 0-3 -> none. Cost: 48 constructors at 30 min (BARb 19).
- `TUNE_ECO_ONLY` = 0. Benchmark only, never on in play. His canon reference: 2,032 m/s and 103k E/s at 16:15 on Comet Catcher +50%.
- `TUNE_ETA_LOG` = 0. One line costs a full ladder simulation (measured 5% of script time).

## Constructors, build power, nanos

- `TUNE_WALK_FORGONE` = 0. 10-20, eco +0 air-first, 4 seeds, 28 min: income min 8-26 -14% (0/4); the commander spent 81% of min 5-10 on far extractors (49% off) and stopped assisting. Stays off.
- `TUNE_SITE_COST_PER_WORKER` = 215.8. Set by the 10-04 valuation search (300 -> 215.8; see TUNE_CONV_HORIZON).
- `TUNE_SITE_BT_PER_WORKER` = 4700. Derived from a fusion (70,000 bt / 4,700 = its ~15 hands); moves the advanced converter from 2 hands to 8. Unswept.
- `TUNE_NANO_EARLY` = 1. His 10-17: nanos go up while the gantry is built. His game: the first leggant had 2 cons and 0 nanos for 4+ min, abandoned at 65%, because plant nano demand read only finished plants. On since v0.3.2; no A/B.

## Factories, tech, quotas

- `TUNE_FAC_QUEUE` = 1.5. Below 1 the plant idles by construction; the margin covers order lag.
- `TUNE_T2_ECO` = 0. His 10-17: fusions and upgraded mexes first. 20 games vs BARb hard: the ladder took the T2 lab at 8.3-12.3 min but it was ordered at 14-23 (same seed: lab 12.8 vs 25.4 min, income at 32 min 308 vs 163). Unmeasured.
- `TUNE_INFLIGHT_HOLD` = 1. His 10-18: every build started while others are in progress slows them, and the price must carry that (his game: armaap at v=2.08, armalab five frames later). On since 10-18; unmeasured.
- `TUNE_CON_PRIO` = 0 (`apex_con_prio`). His 11-06: "some cons could do work but set themselves to low priority". A constructor on a job of a kind over its spend share goes to BAR's low build priority, like turrets and factories. 2v2 vs BARb, 24 pairs: stall samples -7..-14% (t -1), army produced +266 m at 12 min, income even to 16 min. Unproven; off.
- `apex_dodge` = 0 (C++ `CMilitaryManager::DodgeUpdate`, no TUNE_ const). His 11-06 (a friend's bully AI dodges shots): a fighting ground unit in reach of a seen enemy whose shell it can outrun (time of flight x its speed >= its radius + half the splash; beams, lightning, rifles and homing missiles never) sidesteps across the line of fire in front of its orders, alternating sides. Scenario dodge_hammers, 6 pairs: trade 1.0:1 -> 1.7:1 (t ~2). 2v2 vs BARb, 24 pairs: ~340 steps a seat a game, damage efficiency 0.92-1.01 -> 0.84-0.87, losses +1.6k (t +0.5), deaths still 85% -> 83% standing, 34% -> 39% outnumbered 2:1. Our losses are fights taken outnumbered, not dodgeable shells; off.
- `TUNE_FLUSH_PLACE` = 1. His 10-18: build flush off existing buildings, no wasted gaps. 10-18, his setup, 3 seeds: structures per cluster 3.4-4.5 -> 5.7-6.0, ground used 27-29% -> 32-34%, results even. C++ (needs the DLL).
- `TUNE_HOIST_WAITS` = 1. His 10-18: cons walk far, work 2 s, walk back; 56% of such trips ended on a hoist. Alone, 3 seeds: decisions -25%, metal 1.16 -> 1.13M, losses even. On.
- `TUNE_MEMO_REPRICE` = 1. Perf. 10-18 his scav 8v8, seed 32: memo hits 28.7k -> 38.0k, a full decision 4.5 -> 4.0 ms, builder elections -9%.
- `TUNE_REELECT_TTL` = 1. Perf, C++. His scav 8v8 seed 32: full decisions 11,708 -> 6,731, election time 59 -> 36 s; results (3 seeds) W/W/W -> T/W/W.
- `TUNE_ARMY_ONE_CURRENCY` = 0. 10-20 2v2 Comet Catcher vs BARb hard +50, 3 seeds: our army at min 10 1,010/370/3,530 vs 4,580/4,200/2,220 off; two of three lost by ~20 min. Army has no honest per-metal value yet; off until it is priced as losses prevented.
- `TUNE_UNIT_LIMIT` = 0. Test only (`run_match --restrict-mex`). Off in play: `maxThisUnit` folds in behaviour.json's BARb caps; an unswitched version went 3W 2D 7L vs v0.2.9 (Red Comet, 12 games).
- `TUNE_HANDS_ONCE` = 1. His 10-17: fusions and upgraded mexes first, air once the economy carries it. v0.2.9 vs BARb hard: the advanced air plant went up 3.1-6.4 min after the T2 lab, priced on its constructors alone. On since v0.3.2; no A/B.
- `TUNE_UNLOCK_ONCE` = 1. His 10-18 2v2 (lost): both seats raised two advanced labs at ~40 m/s, the second priced at half the unlock, and metal-first put nearly every constructor on both. A/B pending.
- `TUNE_INCOME_ACCEL` = 1. His 10-18: an upgrade that makes everything else faster is valuable. His 2v2: an upgrade priced gain 4-12 against a Guardian 176-263. A/B was running (matches/normab accel-*).
- `TUNE_LAB_ASSIST` = 1. His 10-18: a T2 con was wanted but everyone assisted the gauntlet; a lab guard bid a flat floor. Smoke: guards bid 0.00-0.02, the queued T2 con carries G=24.8. A/B pending.
- `TUNE_SITE_CACHE` = 1. Perf. 10-19 his +100 scav 8v8, seed 32, 20 min: super.site 6.46 -> 3.03 s, want.super 7.32 -> 3.99 s, per unit-minute 6.12 -> 4.95 ms.
- `TUNE_COM_AIR` = 1. His 10-17: the commander retreats only when genuinely threatened; against air he can make AA. Bombed A/B (airfix s95/s96): commanders were 55% and 31% of our metal lost to air. On since v0.3.2; no A/B.
- `TUNE_ALLY_AIR` = 1. His 10-17: our fighters no longer protect allies. His v0.2.9 game on SD-129: air killed from 7.5 min, the first ally intercept came at 34.2 min. On since v0.3.2; no A/B.
- `TUNE_AIR_ANSWER` = 1. His 10-17: bombed five minutes with no ground AA. airfix s95/s96 (Legion 4v4 +50%): 14.6k/17.6k metal lost to air, 2 and 15 fighters built against their 53-74, every static AA the cheapest tower. On since v0.3.2; `apex: airanswer-stat`.
- `TUNE_ORDER_RELEASE` = 1. His 10-17: a lost or abandoned lab or gantry is rebuilt in a rush. His v0.2.8 game: a coralab order lost its hand at 12.0 min and was re-asked only at 18.1, because the empty order still counted as coming. On since v0.3.2; `apex: order-release`.

## Military -- stance, engagement, squads

- `TUNE_SIEGE` = 0. Off by his ruling until the siege squad works in test games (it formed but never marched).
- `TUNE_ECO_HAND` = 0. One canon seed 1,644 -> 1,812 m/s at minute 20; off until a paired A/B wins.
- `TUNE_CREW_ELECT` = 0. His 10-15; ~90% cheaper per shared election. Off until an A/B.
- `TUNE_TEAM_AIRLOSS` = 1. A teammate was bombed for minutes and nobody built AA. On since v0.3.2; no A/B.
- `TUNE_PN_RULE_CENTRE` = 0. Off since 10-30: v0.5.0 ships v0.4.09's net, trained without it; the 10-28 refit net with it on played even with v0.4.09 (relprofile.py). From zero weights the log-middle leans every net the same way (64 games: con cap x2.7, air cons x4.1 vs the rule).
- `TUNE_FLANK_GUARD` = 1. His "raiders walk round the towers and eat the economy": 47% of our economy deaths were on bearings no tower covered. On since v0.3.2; no A/B.
- `TUNE_DEF_REFILL` = 1. His "refill where we were hit; they come back the same way": only 10-17% of first orders after a loss went near it. On since v0.3.2; no A/B.
- `TUNE_DEF_TEAM_OBSOLETE` = 1. His 10-14: 248 HLTs past minute 30. On since v0.3.2; `apex: advobs-stat`.
- `TUNE_LINE_OBSOLETE` = 1. His 10-15: T1 hover AA in 6 of 8 seats late. On since v0.3.2; `apex: lineobs-stat`.
- `TUNE_UNIT_UPKEEP` = 1. His 10-15 online 8v8 lagged: 190 armhawk, 87 rez bots, T2 next to T3 in 40-50 min. Every client simulates every body, so a slot is priced; at L=1, B=500 a 150-metal fighter keeps ~0.2 of its draw, a 5,000-metal T3 unit ~0.9. On since v0.3.2; `apex: upkeep-stat`.
- `TUNE_REZ_LIFE` = 1. His 10-15: 404 rez bots in 55 min, fleets dying and rebuilt. On since v0.3.2; `apex: rezlife-stat`.
- `TUNE_T2CON_UNLOCK` = 1. His 10-15: 95% of T2 seats held more T1 than T2 mexes at 20 min. On since v0.3.2.
- `TUNE_UPGRADE_FIRST` = 0. His tenet: a seat with one T2 con upgrades its mexes first. Off until an A/B.
- `TUNE_ECO_HORIZON` = 1. His 10-15 eco seat: fusions priced v=0.00, one con's 772 s solo build billing the whole gain per second. On since v0.3.2.
- `TUNE_MEXUP_HORIZON` = 1. A moho 1-2 min out read below a fusion at home. On since v0.3.2.
- `TUNE_ASSIST_ECO` = 1. Basic hands' assists were priced at gain 0.00 while a fusion carried 65-86 m/s. On since v0.3.2; `apex: assisteco-stat`.
- `TUNE_LINE_ARMY_GAP` = 1. His 1v1: army 8-12k under target and no nanos at the T2 labs. On since v0.3.2.
- `TUNE_COM_BOLD` = 0. The commander's fight estimate was 27 points pessimistic at median over 2,708 episodes (he fled five T1 units he beat). Off until an A/B.
- `TUNE_COM_STEP` = 1. Walking home cost 2,800 elmos there and back on his 1v1. On since v0.3.2.
- `TUNE_MASS_HOLD_SECS` = 100000. His "no time-based cooldown": the 240 s expiry walked 78 of 110 into a T2 wave. Effectively off.
- `TUNE_RAID_ASK` = 1. The stock pool fielded 13 raiders and no raid in 16 min. 6 seeds: raid time 4.0 -> 10.8 min/game, losses -18%, metal +4%; outcome gain not established.
- `TUNE_STANCE_AGGRO_ARMY` = 1.0. His word: economy plus big mobile units, some turrets, no extremes (was 0.75 army / 1.3 defence). Not A/B'd.
- `TUNE_STANCE_AGGRO_DEF` = 1.0. See TUNE_STANCE_AGGRO_ARMY.
- `TUNE_RECALL_HOME_FWD` = 0.5. Matches sentinel's CONCERN threshold.
- `TUNE_HOLD_MEX_GROUND` = 0. His "we decided to retreat and then they kept those mexes". On 0-5-3 vs off 0-3-1: their army is 2.5-3x ours at min 2-4. Off until the opening is fixed.
- `TUNE_SEEN_HALFLIFE` = 300. 180 s lost win rate and trade in two paired runs.
- `TUNE_STATIC_DEFENSE_WEIGHT` = 0.5. Half, so a porc base cannot pin the massing quota forever. Unmeasured.

## Defence, towers, AA, insurance

- `TUNE_DEF_MEASURED` = 1. His 10-15. In a 4v4 the measured attack rate was 1-8% of the assumed one. Needs the gadget (S8). On since v0.3.2; `apex: defmeasured-stat`.
- `TUNE_LEAK_SCREEN_M` = 800. An estimate (~8 Ticks), not measured.
- `TUNE_DEF_SITE_WALK` = 1. His complaint: a con should cover the mex it just built; 0 is the distance-blind arm.
- `TUNE_DEFEND_LEASH` = 0.55. 0.35 lost more (ceded the corridor's mexes).
- `TUNE_SHIELD_COVER_FRAC` = 0.5. His "too many shields while there's still no threat". First A/B owed.
## Air eco-assassination (manager/air/state.as)

- `TUNE_AIR_AA_SOAK` = 0.05. ~20 Dragons clear 8k of AA; light bombers would need ~67 to reach half through 2.5k, and the payoff test declines that.
- `TUNE_AIR_AA_SPLIT` = 1. The whole-map AA census held a 50-bomber wing home forever.

## Commander

- `TUNE_COMM_FWD_CAP` = 0.25. Minutes forward per 6 games 10-11 -> 0. The election bound is `ComFar` now.
- `TUNE_COMM_FLEE_INFLUENCE` = 0.01. Reads the influence map, never GetBuilderThreatAt (S9).

## Air

- `TUNE_AIR_MANDATORY_INCOME` = 200. His call, raised from 60: hold off on air if we are not the air player until ~200 m/s.
- `TUNE_AIR_EVERY` = 1. His 10-16: pretty much all our players should eventually make air. His v0.2.8 game at min 28: only the air-lead seat had an air plant; headless 4v4s v0.2.3-v0.2.8 built 1-1.5 per 4 seats. Escorts are capped at what beats their fighters (39 armfig + 258 armhawk had been built against no air). On since v0.3.2; `apex: airevery-stat`.
- `TUNE_GANTRY_OWN_SLOT` = 1. His 10-17 ruling. Four Legion 1v1s: an anti-nuke or LRPC held the strategic slot 3-6 min while the gantry waited. On since v0.3.2.
- `TUNE_AIR_COVER` = 1. His ask after watching lone scouts die. Unmeasured.

## Scouting, intel, ghosts

- `TUNE_ESCORT_SQUAD_VALUE` = 2000. His number: any squad worth over 2000 metal.
- `TUNE_JAM_SIGHT` = 1. His 10-17 after online games: jammer-supported armies we never see, and builders, extractors and squads walk into them. The suspected force enters threat, hazard and trip reads; sight over it is bought as a camera post. On since v0.3.2; `apex: jamsight-stat`; no A/B.

## Base layout and placement

- `TUNE_FRONT_BAND_FRAC` = 0.35. 1.0 called half the perimeter front; 0.35 is a +/-49 degree arc.

## Diagnostics and switches

- `TUNE_MEMO_TTL` = 300. At 45 frames answers expired before the next same-def builder asked (hit 593, miss 3,135); 45 -> 150 -> 300 on 10-01 for 8v8 cost.
- `TUNE_REDECIDE_S` = 2. 16-Apex 8v8, 10-18: a flat 2 s bounced 15,591 asks a game with a mean idle gap of 36.5 frames; the backoff bounced 1,616 at 27.2.
- `TUNE_ELEC_FRAME_US` = 8000. A ceiling; the slice is derived from the queue. 10-18 16-Apex 8v8: a flat 2000 cut >10 ms elections 120 -> 2 player-minutes but raised the idle gap 36.5 -> 46.1 frames; the derived slice gives 16 and 28.7.
- `TUNE_PERF` = 0. His ruling: default 0, the harness passes it. No `frametime.py` output means it was off.
- `TUNE_DECIDE_LOG` = 1. Every harness tool parses it; costs a string build and a mutex per election, so 0 suits a live game nobody reads.
- `TUNE_NN_BLEND` = 1. His call: the nets steer in his slot and lobby games.
- `TUNE_NN_EXPLORE` = 0. His call: nothing plays random on purpose in lobby games; training passes its own share.
- `TUNE_NN_PLAN_EXPLORE` = 0.1. His "much less" whole-team strategy exploration (forced RUSH won 0/21).
- `TUNE_PLAN_EXPLORE` = 0. Lobby option 'Try strategies': draws only the team plan, so his multiplayer games teach the plan net without random builders.
- `TUNE_GUNP_RULE` = 1. 0.35x vs 1x over 24 games each was within noise; left at 1 for the head to learn.
- `TUNE_CON_RULE` = 2.5. 2.5x read eco 0.99 vs 0.69 at minute 11 against 1x, at the cost of army (0.42 vs 0.67); 1.6x gave up the eco without buying the army back.
- `TUNE_PERSONA` = 0. Off from v0.5.03 by his 11-02 choice; the lobby "Personalities" option turns it on. 11-02 Comet Catcher vs v0.5.02, 4 seeds per size: damage efficiency 22/11/11% worse at 1v1/2v2/4v4, metal by min 20 82/83/95% of off.
- `TUNE_PLANT_PIPE` = 2.0. 0.5 put lab 1 at 5.1 min (his "build the first lab a bit sooner"); 2.0 targets the ~2-min human timing.
- `TUNE_PIPE_LATENCY_H` = 78.1. 60 -> 78.1 by the 10-04 valuation search (see TUNE_CONV_HORIZON).
- `TUNE_LINE_ADAPT` = 0. At 1.0: 0-11, trade 0.37 vs 0.53-0.65 (no screen left). The direction stands, the shape is wrong.
- `TUNE_MEX_GUARD_FAR` = 3. His "the further from home the more defenses the mex needs". Comet 8v8 seed 1: metal 418k -> 559k, our mexes at 24 min 9 -> 31.
- `TUNE_RECORD_BITE` = 1. Nearly inert in practice (0.9-1.0 for a handful of units); removing the cap is his call.
- `TUNE_EVIDENCE_SHRINK` = 0. Scavenger Epic Tumbleweed read 19.3 power per metal against 0.05-0.13 and zeroed the real T3 line. A/B not run.
- `TUNE_LINE_ABS` = 1. Off made a Thud tankier than a Tzar.
- `TUNE_LINE_ALLOC` = 0. On: reach share 0.06 -> 0.12 but army metal 544k -> 60k, k/l 0.81 -> 0.12 (T1 labs yield forever to a plant that never pays the debt). Off until yielding waits on a debt actually being paid.
- `TUNE_LOCKUP` = 0.5. His "little bit extra of a penalty on top of time". Chosen.
- `TUNE_LATE_BUILD` = 1. His: the walk's cost is also the metal you would have made. An Epic at v=10.9 over an AFUS at 5.8 reads ~1.5 vs ~4.3.
- `TUNE_FARM_ROW_W` = 320. Halved from 640 on his report that the winds stood too far out.
- `TUNE_TECH_PIPE` = 2.0. A second 0.5 double-counted the pipeline delay and priced the T2 lab ~100x under a nano (zero tech decisions in 12 min of an 8v8).
- `TUNE_E_BILL_SHARE` = 1. His "it only matters when we're e-stalling": an advanced solar is unaffordable at 100 E/s, cheap at 400.
- `TUNE_CONV_HORIZON` = 417.1. 300 -> 417.1 by the 10-04 valuation search (943 games vs NullAI, +11% economy confirmed vs BARb on Carrot), with CON_BASE, CON_FEED_HEADROOM, DRAW_SHARP, JOIN_MIN_M, M_WASTE_WORTH, PIPE_LATENCY_H, SITE_COST_PER_WORKER, T2_CON_PER_M and VW_FLOW.
- `TUNE_E_FEED_BOUND` = 0. The ask fell 740 -> 317, outcomes flat over 76 games. The inflation is upstream (`BuildEnergyDensity` averages the whole catalogue).
- `TUNE_E_HEADROOM` = 1.75. 1.25 and 1.5 still under-supplied in watched games.
- `TUNE_MEX_GROWTH` = 6. Back to 6 on 10-27, his call, with the investment charges corrected. Clean eco test (threat 0, 8 seeds), mean m/s: old settings 648, premiums at 1 623, at 3 583, 6/10 corrected 617 (median 650). At 8: a mex doubling income x9, +10% x1.8.
- `TUNE_ENERGY_GROWTH` = 10. His 10-20 value, back on 10-27 with TUNE_MEX_GROWTH. At those values worth/real output read solar 7.6-11.8x, fusion 2.6x; the investment over-charges were the counterweight, so correcting either alone lost (0-4-2, 1-9-8).
- `TUNE_ENERGY_GROWTH_ARRIVE` = 0. His "we should make AFUS first": stops the Epic reactor winning for its size. Untested.
- `TUNE_M_REALIZE` = 1. First measured inert (377 of 389 samples share=1.0). 10-18 his +100 scav 2v2: a seat at 105-408 m/s with a full bank kept claiming extractors; reworked so a full bank reads no headroom. A/B pending.
- `TUNE_M_WASTE_WORTH` = 0.3753. 0.25 -> 0.3753 by the 10-04 valuation search.
- `TUNE_SCREEN_WORTH` = 0.2. Normalising the axis lost 1-7 where the inflated one won 6-2 (the pawn flood wins the opening).
- `TUNE_SCREEN_MAX` = 5. Unbounded, a T1 lab was a flea conveyor (67 built, 2 standing). His number to move.
- `TUNE_MEDIC_FRAC` = 0.12. His "3 times more rezbots" (was 0.04); bounds the wreck-stream sizing that once bought 210 rez bots in one 2v2.
- `TUNE_AA_URGENCY` = 1. The old 4 compensated a value ~50x too small; 1 once AA was priced like a ground turret.
- `TUNE_ECO_AA_MULT` = 1.5. His "~50% more anti air than your average player".
- `TUNE_JOIN_MIN_M` = 354. 500 -> 354 by the 10-04 valuation search.
- `TUNE_T2_CON_BASE` = 1. His "1 T2 con + 1 per 25 metal". Gating the overflow term cut metal 335-554k -> 165-262k on Carrot 1v1 (the extra T2 cons are the mohos); reverted.
- `TUNE_T2_CON_PER_M` = 31. His 25; 25 -> 31 by the 10-04 valuation search.
- `TUNE_CON_BASE` = 4.38. His two points (3 at 12 m/s, 5 at 100); 2.7 -> 4.38 by the 10-04 valuation search (more constructors was its one consistent signal).
- `TUNE_T1_AIR_CON_MIN` = 10. His number.
- `TUNE_NANO_SITE_SHARE` = 1. Replaced a 35 m/s clamp that left gantries on 2-5 nanos against the enemy's 38.
- `TUNE_MEX_TRIES` = 10. A bound on work, not expansion: 3 read as "no ground left".

## Strategic structures -- manager/brain/market/want_super.as

- `TUNE_SUPER_PUSH` = 1. Priced normally, strategic wants were drawn about once a game.
- `TUNE_SUPER_AFFORD_S` = 60. Anti-nuke from ~36 m/s, LRPC ~90, gantry and silo ~160 (his "at 200 m/s we should eagerly build one").
- `TUNE_SUPER_PER_INCOME` = 150. His "at least 1 usually, more if we want to be safer"; never a cap. Extra anti-nukes only once an enemy silo is seen: unseen they beat the gantry in every election.
- `TUNE_CON_FEED_HEADROOM` = 1.847. His "we make too many constructors"; 1.5 -> 1.847 by the 10-04 valuation search.
- `TUNE_UNIT_AFFORD_S` = 120. 60 -> 120 at his call ("we need more Titans or Thors"): a Thor bids from 75 m/s, a Titan from 112.
- `TUNE_ECO_ROLE` = 1. Re-armed at his ask 08-31: it names a different target (EcoRoleTargetM) instead of crushing army and defence targets.
- `TUNE_ECO_LATCH` = 1. His 10-15 "just have 1 eco": his 8v8 had moved the role t6 -> t2 at 18 min when t7 died beside t6.
- `TUNE_ECO_SEAT_STRICT` = 1. On since v0.4.06: 8v8 Carrot +50 vs BARb hard, 4 games per arm, 30 min: eco seat 531 m/s at min 28 vs 310 off (off, its hands reclaimed 42% and assisted factories 23-49%).
- `TUNE_ECO_SEATS` = 2. Strict-seat benchmark, 8v8 at min 28: 2 seats 624 m/s each, team 2,401 vs BARb 1,497 (1 seat: 531, team 1,837). His 10-25 rule (2 on bigger maps, 1 on smaller) awaits measurement.
- `TUNE_TEAM_GANTRY` = 1. His 10-31 ruling: a middle seat hosts the team's first gantry on the team's purse. Supreme Isthmus 8v8 vs BARb hard +50, 3 seeds: income at 40 min 2.4-3.1k vs 1.6-1.8k off; first T3 lab unchanged (22-26 min, BARb 16-18): the gantry's gain, not its money, holds it.
- `TUNE_ECO_SEAT2_SHARE` = 0.33. His 10-31: make the second eco seat a half eco (before: two eco seats put 9 m/s into army at min 24, BARb had the bigger army in 8 of 9). Supreme Isthmus 8v8, 3 seeds vs v0.5.0: 3 draws both; our army at min 40 431k/361k/28k vs 127k/-191k/333k.
- `TUNE_LADDER_YIELDS` = 1. His 10-26: constructors take extractors and raise the guns together. His 4v4 setup: 87 decisions a game sent a higher-priced tower to the ladder. 8 games each: 5-3 both, extractors lost 35.0 -> 30.5, cons lost 31.4 -> 28.9. On since v0.4.09.
- `TUNE_BARE_MEX_HZ` = 1. His 10-26: a guard is insurance on the extractor we walk away from. Bare extractors died at 0.0062/s against a priced ~0.0001/s (32 games: life 2.7 min bare, 18.4 guarded). 8 games each: 4-4 vs 3-4-1, extractors lost 29.9 -> 26.6; towers unchanged. On since v0.4.09.
- `TUNE_OPP_WAIT` = 1. Another hand starts the runner-up's kind in a median 10-19 s (extractors, towers, energy), 35-80 s (converters, labs), 183 s (supers). Alone, 18 seeds: 1-9-8 vs 2-5-11, income at 20 min 122 vs 193. On since 10-27 in the balanced set with TUNE_CALIB_RISK and TUNE_INFLIGHT_PS (2v2 vs BARb hard +50, 36 games: 5-8-23 vs 2-11-23, growth premiums then at 1).
- `TUNE_CALIB_RISK` = 1. The survival price read a flat 0.0020-0.0035/s against real 0.0003 (rear energy) to 0.0045/s (forward extractors). Same 18 seeds: 2-5-11 both; fusion 18.7 vs 20.3 min, T2 lab 11.7 vs 12.8; extractor risk 0.92-1.06 of real vs 0.30-1.29. On since 10-27.
- `TUNE_NANO_PAYBACK` = 1. His 10-28 T1-only game: one seat stood 631 nanos, 383 idle, and the game lagged. 4v4 White Fire T1-only +50, 8 games: on 4-0-2, off 1-1-2; turrets at min 40 418 vs 692. The idle-share half awaits a rich late game.
- `TUNE_INFLIGHT_PS` = 1. The fusion's displacement fell 74,912 -> 2,704. Alone, 1v1, 6 each: off 2-0-4, on 0-4-2; eco test 606 vs 592. On since 10-27 in the balanced set (see TUNE_OPP_WAIT), lab streams now carrying unbounded remaining cost.
- `TUNE_POLICY` = 1. Restored 10-26: neutral (with NN_BLEND 0) went 0-7-5 in 12 games, policy off 0-6-12 in 18, on 4-4-10 in 18. The net protects us somewhere the prices do not.
- `TUNE_TEAM_TECH` = 1. His 10-15: one seat goes T2 a little sooner and hands out T2 cons (a 6v5 where all 5 of our seats ordered a T2 lab at 2.0-3.3 min and lost). Needs 3+ seats. On since v0.3.2; `apex: teamtech-stat`.
- `TUNE_GANTRY_AFFORD_S` = 100. His "we can have a gantry at like 100 m/s": the ~9.3k bill clears at ~100 team m/s.
- `TUNE_GANTRY_HOST_INC` = 150. 100 -> 150 at his call. A hard skip below it left six of eight 8v8 players gantry-less at 38 min ("not ok"), so the gain scales instead.
- `TUNE_OBSOLETE_RATIO` = 4. His "much better". A team-wide basic-converter ban cut metal 704k -> 296k. Since v0.4.07 a denser generator counts only within ETA reach: eco test with the scavenger pack 388 -> 709 m/s at min 20.
- `TUNE_EXPOSE_R` = 1200. A radius-based escort rule once put a Pawn on 225 of 272 buildings' workers; exposure is the risk field and territory now.
- `TUNE_EXPOSED_LOSS_S` = 120. His "almost guaranteed". 300 claimed every spot naked and lost it; 120 flips to claim-then-guard.
- `TUNE_FRAME_RISK` = 0.0. At 1.0 metal built 38.6k -> 17.6k, head-to-head 3-21 -> 0-30 over 54 games. Off until the hazard field is not saturated everywhere.
- `TUNE_PROTECT_FIELD_S` = 15. 2 -> 8 -> 15 s: each rebuild re-keys four memos (18% of all AI time in an 8v8); a tower takes 20-60 s to build.
- `TUNE_STALL_ANSWER_MAX_E` = 400. His number; gates only the interrupt. The per-election hoist reads the deficit (700 E/s against a 1,950 deficit had stalled 12 minutes).
- `TUNE_RISK_FLOOR` = 0. At 0.15 it was the whole early tower demand (nine LLTs before min 8; his "too many early game defenses"). The blind floor is the siege prior now.
- `TUNE_HZ_APPROACH` = 0. Fires as built and changes nothing in 8 games: one tower's share of a big wave is ~0. Kept as an instrument.
- `TUNE_REZ_UTIL` = 0.35. 0.25 fielded 99-129 Rectors per player (his "turn the rezbots down a little"); 0.35 is ~30% fewer. Unmeasured.
- `TUNE_RETREAT_FLOOR` = 0.08. Stock's 0.6 lost 93% of combat metal while retreating; his "units retreat on a very low HP %". Move only with a `deaths.py` died-retreating read.

## Everything else

- `TUNE_GIFT_STAKE` = 0. His 10-19: a seat with no commander, base or income still asked to be fed units. Untested; on for his watch lane.
- `TUNE_LAB_BEST` = 0. His 10-19: a new Legion T2 lab drew an Incinerator over the T2 con at one in ten. The 08-23 argmax built 29 cons and no army. A/B pending.
- `TUNE_LAB_INHERIT` = 1. His 10-19: the lab is worth all your extractors upgraded, limited by the time to get there. Before: armalab v=0.003 against a T1 extractor's 0.06-0.2.
- `TUNE_AIR_FEED_CAP` = 1. His 10-19 Red Comet game: T2 air plants 6 min after the T2 lab at v=0.82/0.50, the yield mostly the look term (34 of 38). Since 11-05 a new air plant is capped only against the air plants standing: capped against every line's spend, a seat with ground labs spending all its metal priced its first or replacement air plant at 0 (c05-g1120: every air plant dead by minute 24.5, none rebuilt, against 693 Phoenix bombers; his 11-05: the cap's intent was "not only producing air", and late games can field 200 fighters and 100 bombers).
- `TUNE_NANO_UPGRADE` = 1. His 10-19. A rule, not a price, until the turret's lab-vs-upgrade choice is in one currency (the valuation job).
- `TUNE_DRAW_BEST` = 1. The draw moved 40-46% of builder decisions off the top want. 2v2 Comet vs BARb hard +50, 6 seeds: army at 25 min better on all six. On since 10-20.
- `TUNE_CREW_SPLIT` = 1. His 10-01. 10-20, 5 seeds with DRAW_BEST on: 3-2 for the crew, inside the noise. Stays on.
- `TUNE_NN_RECORD` = 0. ~0.3 ms an election in a hosted game nobody trains on (his Odderon game: 44,045 lines); run_match.py passes 1.
- `TUNE_AIR_PAYOFF` = 1. v0.3.2's value (the repo had 1.5); promoted with the release settings 10-19.
- `TUNE_RAID_ANSWER_REACH` = 1. v0.3.2's value; promoted with the release settings 10-19.
- `TUNE_AFLOAT_SUB_COST` = 400. Two subs once sent seven players to air plants while ground walked in.
- `TUNE_COM_MEX_PRICE` = 0. At 0.35 over 32 games: income at 12 min +38%, commander deaths 37 -> 20, early losses 12/32 -> 4/32 (p 0.04); wins unresolved at 45 min. Changes what he may do, so his call.
- `TUNE_BUDGET_AFTER` = 1. Applied to tickets after the draw's sharpening, 2x is 2x the odds; on want value the commitment exponent cancelled it.
- `TUNE_ETA_COMMIT_BONUS` = 0. AFUS orders 101 -> 18, no gain in 45-min games. Unvalidated; test in a long game.
- `TUNE_WALL_REAR` = 0.08. His concentration ruling: defend the frontline and the backline needs far fewer defences.
- `TUNE_WALL_EFFICIENT` = 1. Off, a T1 hand bought its most expensive tower for a quiet rear slot.
- `TUNE_T1_DEF_LATE` = 0.02. Keyed on the lab it priced every T1 gun at 2% from min 10 to 20 (his "nothing between 10 and 20"); now keyed on what the asking hand can build.
- `TUNE_RADAR_OVERLAP` = 0.45. Was 0.8: no redundancy, one death made a dark zone.
- `TUNE_DRAW_SHARP` = 2.903. 1 took a lower want in 34% of elections; pure argmax starved every category never #1. 2 -> 2.903 by the 10-04 valuation search.
- `TUNE_ROLE_SHARE` = 0.5. His design. 10-18 his scav 8v8, 3 seeds: roles off cost 7% metal at min 20, slower wins, +10-52% decisions. 10-20 with DRAW_BEST, 5 seeds: 3-2 for roles. Roles stand in for the switching cost the draw does not price.
- `TUNE_T2_FUSION_PULL` = 0. We tech first and then wait 8.2 min for a fusion (BARb 1.1). It overrides a price, so it waits on his ruling ("fusions ... pretty soon").
- `TUNE_REZ_FLEE_S` = 20. 90 s parked bots for a stray shell.
- `TUNE_REZ_SCAN_S` = 1. A team-wide clock left most idle bots standing.
- `TUNE_REZ_REACT_S` = 1. His "delays of more than a second are unacceptable", as distance.
- `TUNE_RAIDER_MASSING` = 0. At 1: zero raid and zero attack elections across 11 matches. Off, they raid all game as stock does.
- `TUNE_SPAM_RAIDERS` = 1. On at his call (escorts should be the fodder/spam units); judge on where they die.
- `TUNE_ECO_TARGET_BASE` = 250. His "no army and no defense until like 20 minutes", as economy (x handicap).
- `TUNE_LINE_TERRAIN` = 1. His rule: bots on hills, vehicles on flats.
- `TUNE_TEAM_LINE` = 1. His 4v4 complaint about four bot labs; a price, not exclusivity.
- `TUNE_COVER_LEAVES` = 1. His "try doing both" after 427 units sat in cover; with TUNE_COVER_BY_RAID.
- `TUNE_DEF_DOMINANCE` = 1. A price since 10-10, not a refusal (his: at -1 we would never build it and never learn its use).
- `TUNE_CONV_AFFORD_S` = 30. The bank was the wrong bound: run near empty, the burst never fired.
- `TUNE_E_COMMITTED` = 1. Without it the first energy decision came 73 s and one stall late.
- `TUNE_COVER_PUSH_S` = 10. His order (mexes and lab first). Swept to 40: fired twice as often, fewer towers.
- `TUNE_RADAR_PRICE` = 1. His 10-14 "defence as a crutch" (10-13% spent on radar). One of the switches turning a draw-bypassing rule into a priced offer, with DEFJOIN_PRICE, FIELD_PRICED, COVER_PRICED. 10-18 his scav 8v8, 6 seeds, the four on: metal at min 20 +9% (5 of 6), losses 2 -> 1; with HOIST_WAITS +19%. 1v1 Comet, 8 seeds: W-T-L 7-1-0 vs 5-2-1.
- `TUNE_DEFJOIN_PRICE` = 1. See TUNE_RADAR_PRICE.
- `TUNE_FIELD_PRICED` = 1. See TUNE_RADAR_PRICE.
- `TUNE_COVER_PRICED` = 1. See TUNE_RADAR_PRICE.
- `TUNE_MEXUP_BOOST` = 1. At 2.79 upgrades became the top want and metal built fell 863k -> 358k: they displaced the energy that pays for expansion.
- `TUNE_DUP_BP_SUBST` = 1. His "add more nanos to the lab instead of making another lab"; turrets buy the same build power nine times cheaper.
- `TUNE_REPLANT_DISCOUNT` = 0.15. 14 of 15 T2 labs in one 1v1 were reclaimed and re-bought.
- `TUNE_ASSIST_SHARE` = 0.3. Was 0.5. The 10-21 paired sweep read +17%, but the base arms then averaged ~708 m/s against ~715 over fifteen batches at 0.5: mostly seed luck, a few percent at best. 0.15 vs 0.3 -5.5% (se 5.0). Not checked against BARb.
- `TUNE_FOE_AIR_MEM` = 1. Since 11-01. 4v4 mirrors (Comet Catcher, scav units, +100): the side under air attack counted 2.4-7.1k of the 24-50k strike air built against it; with the memory 2.3-7.5k of 7.9-14.9k.
- `TUNE_FTR_TEAM` = 1. His 11-01 ruling: fighters are the team's job, bombers still compete on price. 4v4 mirrors, 3 seeds: the side losing to air held out 22.0/29.1/33.0 min against 18.7/24.3/25.2; side 1 won all six, so wins need a side-swapped test.

## ValueOf term weights

- `TUNE_VW_FLOW` = 0.6598. 1 -> 0.6598 by the 10-04 valuation search (see TUNE_CONV_HORIZON).
- `TUNE_MEX_LOSS_COVER` = 0.1. His 10-03 "queue-jump only while losses are high": ungated, half of builder decisions were guns; gated +22% eco (n.s.).
- `TUNE_BASE_FRONT` = 1. His "we protect our metal extractors, but we don't protect our base". Measured firing but starved of slots.
- `TUNE_COM_ESCORT` = 1. His idea. Even in head-to-heads vs v0.1.1/v0.1.2.
- `TUNE_COM_LAB_EARLY` = 1. His plan after mirrors stuck at 50%: constructors lost by min 10 0.9 -> 0.5. To become a price, not a queue jump.
- `TUNE_BIRTH_DEFEND` = 1. His 10-15 watch: two units out of a T2 lab under attack ran instead of defending it, and the lab died. On since v0.3.2; `apex: birth-defend-stat`.
- `TUNE_AOE_VS_BLOB` = 1. His 10-15 watch: 3 Fatboys all game against a 36k blob. The 10-13 per-unit SplashMul priced artillery ~5x a tank and was removed; this one saturates on our owned splash. On since v0.3.2; `apex: aoe-stat`.
- `TUNE_UNSTICK` = 1. His 10-15 8v8 lagged on stuck units re-pathing: 368 of 560 walls that penned units were nano turrets, 93% within 600 elmos of a lab. On since v0.3.2; `apex: unstick-stat`.
- `TUNE_RUSH_AWARE` = 1. His 10-15: humans beat us on small maps with mass grunts while we build T2 labs and constructors. On since v0.3.2; `apex: rush-stat`; no A/B.
- `TUNE_MAP_SHARE` = 1. His 10-15: hold at least our seat share of the map's extractors before focusing on economy. Economy prices untouched (the SMALL_PRESSURE lesson). On since v0.3.2; `apex: mapshare-stat`; no A/B.
- `TUNE_SMALL_HARD` = 1. His 10-16: on a really small map go hard into military and starve their extractors. mapshareab s601, min 6-9: lost 6,466 metal for 629 killed. Needs the DLL (walk binding). On since v0.3.2; `apex: smallhard-stat`.
- `TUNE_LEARNED_RISK` = 1 (`apex_learned_risk`; risk.as, weights riskweights.as from tools/risknet.py). His 11-04: a build job's risk is the learned chance its frame dies unfinished and its builder is killed on it, fitted on the job ledger (tools/ledger.py). Held out 11-04: the price expected 6.8% of jobs to fail, 22.7% did; this model AUC 0.81 frame / 0.89 builder against 0.72. Off until a paired test. On from v0.5.06 (his 11-05): model v6 from the ledger loop (60-min games vs BARb and v0.5.05); 24 1v1 pairs vs BARb hard against v0.5.05 -- constructors killed -40% (t -1.6), jobs failed -26% (t -1.6), wins 8 vs 7, nothing worse.
- `TUNE_COM_HOME_ASSIST` = 0 (`apex_com_home_assist`; decide.as). His 11-03 against WRDistilled 0.3 (Comet +0): their commander assists the plant after the opening while ours walked 2,500 out for extractors, and their army ran 5-9x ours from minute 8. On, past the first plant, a best job farther than 1,400 from home (WRDistilled's COMMANDER_WALK) sends him to the lab through the comescort hoist instead. Off by default; testing on lane-estall.
- `TUNE_EARLY_BALL` = 1. His 10-16: a ball of 10-20 Pawns can take a base. cand-5 Red Comet, first 6 min: 19 cons, 1.5 Pawns, 12 heavier units per side. Inert without TUNE_SMALL_HARD. On since v0.3.2; `apex: earlyball-stat`.
- `TUNE_BUDGET_HOLD` = 1. His 10-16: small maps hard into military, modest constructors. cand-3 Red Comet: army 0.12-0.25 of spend against a 0.32-0.37 target; all 30 of one seat's armck came from the con floor. On since v0.3.2; `apex: budgethold-stat`.
- `TUNE_TEAM_AIR` = 0. His 10-16: once ahead, the whole team goes massive air and strikes together. In 48 games the plan rule never chose AIR (161/161 NORMAL). Unmeasured.
- `TUNE_OPEN_RACE` = 1. His 10-16: time a con against a fighter and open with military when it pays. barb-open: 25 of our first 40 lab orders were cons. The first cut made 585 of 676 orders fighters; reworked with square-law strength and the spot race. On since v0.3.2; chase part is C++; `apex: openrace-stat`.
- `TUNE_COM_FIGHT` = 0. His 10-16: don't lose units straight to their commander. cand-11 Red Comet, first 10 min: 18k metal lost to commanders, 84% on RAID, 98% standing still. cand-12 1-1-8, unchanged; cand-13's prediction read loss 7.25x low (window fixed since). Needs the DLL. Unmeasured since.
- `TUNE_EXPAND_FAR` = 1. 10-16: our eco with stock army lost 4/4 to BARb hard on Supreme Isthmus 4v4, our extractors flat at ~30 from min 8 against their 54; BARb held 95% of its half, we 66%, and 61% of our mex jobs were let go within ~2 s. Check game: mex count unmoved. On since v0.3.2; C++ part needs the DLL; `apex: expand-stat`.
- `TUNE_LIVE_NOT_BAN` = 1. His 10-16, after the three-minute mex ban: no site judgement held on a clock; the audit found five. On since v0.3.2; `apex: liveban-stat`; no A/B.
- `TUNE_SURF_DPS` = 1. His 10-16: "why do we always make so many amphibious units?" armamph was joint-top T2 bot output (29 vs armzeus 30 in 12 games), its anti-air missile counted as ground dps and range. AA units read air dps (on surface fire Cortex fighters priced 0). C++ too. On since v0.3.2.
- `TUNE_ECO_RETURN` = 1. His 10-16: we no longer scale like BARb. Supreme Isthmus 4v4 per seat: metal income at min 20 39 vs 67; 30-60% of converter capacity idle from min 10 while new converters still priced at full gain. On since v0.3.2; `apex: ecoreturn-stat`.
- `TUNE_COUNTER_MIX` = 0. His 10-16 (approved): production answers the army we have seen. cand-13 Red Comet: every candidate 0-1-34 as Cortex on side B. Offline, against a Janus/Pawn mix the square law ranks Leveler and Storm over the Thug. Unmeasured.
- `TUNE_FOCUS_FIRE` = 0. His 10-16: a committed group targets their damage first. The first version walked members into range: score -1.65 vs -0.88 a game, kills before min 10 62.7k -> 54.1k; now set-target only. C++. Unmeasured.
- `TUNE_AA_THREAT` = 1. His 10-16: a seat had their air over it for minutes and made no AA. His watch game: the first AA order stood unmanned 300 s yet counted as coming, so the panic stayed off 3.5-8.5 min; 0-1 mobile AA per seat in 14 min. On since v0.3.2; `apex: aathreat-stat`.
- `TUNE_GATHER` = 0. His 10-16: grunts die one by one; fix the squad at launch, group up, then attack. 20 games: 45% of fighter metal lost had been pulled onto a pack already out; 914 of 1,418 raid packs were one unit. Also the join-window rule. Needs the DLL. Unmeasured.
- `TUNE_STOCK_ARMY` = 1. His 10-16: our economy scales better than stock BARb, our army control is worse. Replaces the 09-23 ground-only arm (trade 0.49 -> 0.66 over 32 games). Needs the DLL. On since v0.3.2.
- `TUNE_OUR_AIR` = 1. His 10-16: our coordinated bombing raids were top notch; keep them with the ground army stock. Needs the DLL. On since v0.3.2.
- `TUNE_SQUADS` = 0. His 10-16: one owner for the army (`docs/army.md`). Needs the DLL. Unmeasured.
- `TUNE_JOIN_ARRIVE` = 0. His 10-16: no unit fed into work it reaches too late, one strict rule for all. The audit found six join paths with no arrival test. Unmeasured.
- `TUNE_LAB_NANO` = 1. His 10-16 watch: tons of towers, no con turrets at our labs (0 nano wins vs 6-19 defence wins a seat; lab lathe 10 m/s nameplate, 0.6-4.1 delivered). The count falls out: one turret once income feeds it, a second past 12.8 m/s per lab. On since v0.3.2; `apex: labnano-stat`.
## C++-only options (read through `GetTunable` in the DLL)

- `TUNE_FIGHT_TRAVEL` = 1 (`apex_fight_travel`). His watch: a squad moved straight into a pack in our base. On since v0.3.2; forced 0 for stock-controlled units.
- `TUNE_TARGET_VALUE` = 1 (`apex_target_value`). 43% of our kills were under 100 metal. On since v0.3.2; forced 0 for stock-controlled units.
- `TUNE_UNIT_COVER` = 1 (`apex_unit_cover`). His ruling. Off, ~70% more defence stood and the abort rate did not move (54% -> 53%).
- `TUNE_INBASE_PATH` = 0 (`apex_inbase_path`). Removed the anomaly (119 -> 0) but not the stuck builders (21 -> 20); mexes held worse.
- `apex_hold_<unit>`. Live only while losing ground; the Behemoth 2x is his call. Unmeasured.
