# Tunables: why a default is what it is

Every default lives in `ai/Unstable/game-side/script/standard/tunables.as`, one line per knob,
`TUNE_<NAME>` mirroring the modoption `apex_<name>`. This file lists only the knobs with a
measurement or a ruling behind their default, one line each, keyed by name:
`grep TUNE_YOURKNOB docs/tunables.md`. A knob absent here has no recorded result; its line in
`tunables.as` is all there is. The long-form evidence (tables, seeds, batches) is in git:
`git log -p docs/27-tunable-rationale.md`. Knobs since removed are not listed.

A tunable is the last resort (`working.md`); a proven change deletes its gate and `TUNE_` constant.
An override reaches a game only through the deployed `dev_tunables.lua` gadget (S8).

## Economy -- energy, fusion, converters, reclaim

- `TUNE_ETA` = 1. ETA re-ranks wants within the economic categories. On: Carrot 1v1 vs BARb, 12 games, income at 30 min 188 -> 236 m/s, mexes 69 -> 100, 0-3 losses -> none; the gain is the merge of the economy tickets into one draw. Cost: 48 constructors at 30 min (BARb 19).
- `TUNE_ECO_ONLY` = 0. Economy-only benchmark (no army, defence, AA or superweapons) against an inactive opponent; his canon reference: 2,032 m/s and 103k E/s at 16:15 on Comet Catcher +50%. Never on in a real game.
- `TUNE_ETA_LOG` = 0. The `apex: eta` shadow line with the ETA layer off; one line costs a full ladder simulation (measured 5% of script time), so off.
- `TUNE_T2_METAL` = 30. His number ("30 m/s is a good number") for the old T2 gate. Read only by `Policy::T2Metal()`, which nothing calls: a dead knob.

## Constructors, build power, nanos

- `TUNE_WALK_FORGONE` = 0. A builder's time is priced at its own build power x the share of fleet spend the economy can feed, not income / every worker (wage 3.4 m/s at 4 workers; commander 26 m/s under the new rate). Applies to walk and build seconds in ValueOf, OppTimeReprice and every WageOf. Off until an A/B; `apex: walkforgone-stat`.
- `TUNE_CON_LOG_T1_A` = 4.6. T1 constructor curve: cons = A x ln(income) + B, ~4 at 10 m/s, ~14 at 100; the dashboard edits it as anchor points.
- `TUNE_SITE_COST_PER_WORKER` = 215.8. 300 -> 215.8 by the 10-04 valuation search (see TUNE_CONV_HORIZON).
- `TUNE_SITE_BT_PER_WORKER` = 4700. Site crew from build time (max with the cost arm): set from a fusion (70,000 bt / 4,700 = its ~15 hands); moves the advanced converter from 2 hands to 8. Unswept.

## Factories, tech, quotas

- `TUNE_FAC_QUEUE` = 1.5. Queue depth as a multiple of the line's re-election gap; below 1 the plant idles by construction, the margin covers order lag.

## Military -- stance, engagement, squads

- `TUNE_SIEGE` = 0. Siege a fortification on purpose (nnsiege, CSiegeTask, fort census). Off by his ruling until the siege squad works in test games (it formed but never marched).
- `TUNE_ONE_ARMY` = 0. One army: every ground squad walks to the strongest and shares its target (his "default to one big army"). In the search the centre net went 10% vs 25% before; he returned the search to the old behaviour while each piece is A/B'd. Off.
- `TUNE_ECO_HAND` = 0. Roles keep an energy hand when energy is starved (his watch: minutes with nobody building economy); one canon seed 1,644 -> 1,812 m/s at minute 20. Off until a paired A/B wins.
- `TUNE_CREW_ELECT` = 0. One election per crew (his 10-15): same-def hands near a leader take its job or the next want of its list; breaks off on danger or role. ~90% cheaper per shared election. Off until an A/B; `apex: crew-elect-stat`.
- `TUNE_TEAM_AIRLOSS` = 0. Every seat prices AA on the team's air losses, not only its own (a teammate bombed for minutes, nobody built AA). Off until an A/B.
- `TUNE_PN_RULE_CENTRE` = 0. Map policy output 0 to the rule value instead of the range's log-middle (aa sat at 0.63x, acap 4.47x). Shifts every trained network, so off until an A/B.
- `TUNE_FLANK_GUARD` = 0. His "raiders walk round the towers and eat the economy": guard groups out of defend pools stand at open, uncovered economy bearings, sized to the raid wave. 47% of our economy deaths were on such bearings. Off pending A/B.
- `TUNE_DEF_REFILL` = 0. His "refill where we were hit; they come back the same way": a dead gun's gap is priced by the corridor behind it and offered back for a while. Today 10-17% of first orders after a loss go near it. Off pending A/B.
- `TUNE_DEF_TEAM_OBSOLETE` = 0. A basic hand's tower is outdated against what our advanced hands can build and afford (his 10-14: 248 HLTs past minute 30). Also routes the field crew, defence role, base-front and refill through the cut. Off until an A/B; `apex: advobs-stat`, `t1tower-path`.
- `TUNE_LINE_OBSOLETE` = 0. A lower plant's unit keeps only the share of worth the best same-role unit of a higher owned plant delivers; the rest defers to that line (his 10-15: T1 hover AA in 6 of 8 seats late). Off until an A/B; `apex: lineobs-stat`.
- `TUNE_REZ_LIFE` = 0. Price a rez bot over its expected life, net of its cost (his 10-15: 404 rez bots in 55 min, fleets dying and rebuilt). Off until an A/B; `apex: rezlife-stat`.
- `TUNE_T2CON_UNLOCK` = 0. Price an advanced constructor by the mex upgrades it brings forward (his 10-15: T2 seats with T1 mexes; 95% of T2 seats held more T1 than T2 mexes at 20 min). Also fixes the upgrade-hand walk. Off until an A/B.
- `TUNE_UPGRADE_FIRST` = 0. His tenet "a seat with one T2 con upgrades its mexes first": the oldest advanced hands hoist the best upgrade over guns, sensors and roles while T1 extractors wait. Off until an A/B.
- `TUNE_ECO_HORIZON` = 0. Energy and converter wants use the same horizon-share pricing (his 10-15 eco seat: `ewant corfus v=0.00 gain=66.5 t=17254` of which late=14431 -- one con's 772 s solo build billed the whole gain per second). Off until an A/B.
- `TUNE_MEXUP_HORIZON` = 0. Charge a mex upgrade's walk and build as their share of the payback horizon, not gain x seconds (a moho 1-2 min out read below a fusion at home). Off until an A/B.
- `TUNE_ASSIST_ECO` = 0. Price an assist on an economy frame at the frame's gain x the seconds this hand saves it; basic hands' assists priced at gain 0.00 while a fusion carried 65-86 m/s. Off until an A/B; `apex: assisteco-stat`.
- `TUNE_LINE_ARMY_GAP` = 0. A line short of nanos reads the army gap, not only free metal flow (his 1v1: army 8-12k under target, no nanos at the T2 labs). Off until an A/B.
- `TUNE_COM_BOLD` = 0. The commander's fight estimate gets a 0.2 buffer: it was 27 points pessimistic at median over 2,708 episodes (he fled five T1 units he beat). T2+ keep the old bar. Off until an A/B.
- `TUNE_COM_STEP` = 0. A withdrawing commander steps to the nearest threat-free point instead of walking home (2,800 elmos home and back on his 1v1). Off until an A/B.
- `TUNE_MASS_HOLD_SECS` = 100000. A massing pool commits on its want, never on a clock (his "No time-based cooldown"): the 240 s expiry walked 78 of 110 into a T2 wave. Effectively off.
- `TUNE_RAID_ASK` = 1. The raid director asks for raids instead of waiting for the stock pool (13 raiders, no raid in 16 min). Gated on the worker's own cover: raids 4.0 -> 10.8 min/game over 6 seeds, losses -18%, metal +4%; outcome gain not established.
- `TUNE_STANCE_AGGRO_ARMY` = 1.0. Army/defence scaling under an aggressive stance, now 1.0/1.0 (were 0.75/1.3) on his word: economy plus big mobile units, some turrets, no extremes. Not A/B'd.
- `TUNE_STANCE_AGGRO_DEF` = 1.0. See TUNE_STANCE_AGGRO_ARMY.
- `TUNE_RECALL_HOME_FWD` = 0.5. Only squads this far forward of our territory are recalled; matches sentinel's CONCERN threshold.
- `TUNE_HOLD_MEX_GROUND` = 0. Units within range of a mex spot ignore influence/incoming withdrawals while the odds hold (his "we decided to retreat and then they kept those mexes"). Measured 0-5-3 vs 0-3-1: their army is 2.5-3x ours at minutes 2-4. Off until the opening is fixed.
- `TUNE_FIGHT_ABORT` = 0. Abort a losing attack outright: 1-11 vs 4-10 with it on (the ledger reads losing in every bloody fight). Off.
- `TUNE_FODDER_COST` = 100. Units at or under this cost (and of a fodder role) are fodder: never massed, always sent forward.
- `TUNE_SEEN_HALFLIFE` = 300. Half-life of the largest enemy mass ever seen; 180 s lost win rate and trade in two paired runs, so kept near-frozen.
- `TUNE_BUDGET_LIVE` = 0. SPEND_* curves read live income (1) or the frame-0 column (0). Live: 23-8-9 vs 20-10-10 (noise) and metal rate -21%, so off until the curves are re-tuned.
- `TUNE_STATIC_DEFENSE_WEIGHT` = 0.5. Enemy static defence counts half per metal in the massing decision, so a porc base cannot pin the quota forever.

## Defence, towers, AA, insurance

- `TUNE_DEF_MEASURED` = 0. Defence demand from the MEASURED attack rate near each site (seen armed arrivals + our structure losses, decayed) instead of the 1/120 s mex prior, the siege prior and the share-of-economy target (his 10-15). In a 4v4 the measured rate was 1-8% of the assumed one. Off until an A/B; `apex: defmeasured-stat`. Needs the gadget deployed (S8).
- `TUNE_MEX_COVER_FLOOR` = 1.0. Minimum cover per wanted mex gun, in light towers, so a never-attacked mex is not left naked; 0 is the observed-threat-only A/B arm.
- `TUNE_LEAK_SCREEN_M` = 800. Army value at which the mobile screen, not per-mex towers, answers leaks; an estimate (~8 Ticks), not measured.
- `TUNE_GATE_DEPTH` = 2. A choke gate deepens until its cover overwhelms the wave (his "deeply cover those choke points").
- `TUNE_TEETH` = 0. The teeth line in front of the wall's front row. Off at his call 10-14: "lets stop making walls, we make too many".
- `TUNE_DEF_SITE_WALK` = 1. Weights the builder's walk inside the defence site ranking, so a con covers the mex it just built (his complaint); 0 is the distance-blind A/B arm.
- `TUNE_COVER_PUSH` = 1. One want skips the lottery: the first gun at a mex of ours, proposed by a builder already in reach (his "we don't immediately make the light tower", twice).
- `TUNE_DEFEND_LEASH` = 0.55. A DEFEND unit forward of this on losing ground is recalled first; 0.35 lost more (ceded the corridor's mexes).
- `TUNE_HOLD_COMMITTED` = 1. Units on ground the enemy's guns cover get no solo pull-out orders: half fighting, half running loses twice.
- `TUNE_SHIELD_COVER_FRAC` = 0.5. Shield twins of the AA pair (cover per metal of their artillery, urgency): self-limiting dome by dome, his "too many shields while there's still no threat". First A/B still owed.
- `TUNE_SHIELD_URGENCY` = 1. See TUNE_SHIELD_COVER_FRAC; replaced an undocumented x4.

## Air eco-assassination (manager/air/state.as)

- `TUNE_AIR_CLUSTER_R` = 900. Radius of one bombing run's cluster around their base centroid.
- `TUNE_AIR_AA_SOAK` = 0.05. Wing health soaks AA (a Dragon 25x a Thunder): ~20 Dragons clear 8k of AA; light bombers need ~67 to reach half through 2.5k, and the payoff test declines that.
- `TUNE_AIR_AA_SPLIT` = 1. Strike sized against their AA divided by their base count: the whole-map census held a 50-bomber wing home forever.
- `TUNE_AIR_SETTLE_S` = 90. Seconds before a strike is scored: long enough to reach, bomb and be shot at.

## Commander

- `TUNE_COMM_HEAVY_FRAC` = 0.5. Enemy heavy+super mass at this fraction of the commander's own cost makes him cautious; scales with the game.
- `TUNE_COMM_FWD_CAP` = 0.25. Forward fraction beyond which a cautious commander is run home (minutes forward per 6 games 10-11 -> 0). The election bound is `ComFar` now.
- `TUNE_COMM_FLEE_INFLUENCE` = 0.01. Enemy influence at his tile above which he leaves; reads the influence map, never GetBuilderThreatAt (S9).

## Air

- `TUNE_AIR_DOMINANCE_AA` = 0.15. Enemy AA under this share of our army is dominated: the assassin's AA ceiling waives so leftover flak cannot veto it.
- `TUNE_AIR_MANDATORY_INCOME` = 200. Income at which a non-air-lead player must have an air plant. Raised 60 -> 200 at his call ("hold off on making air if we're not the air player until we have ~200m/s+").
- `TUNE_AIR_COVER` = 1. Held fighters guard every scout, radar plane and bomber sent out, matched to the route's air threat, never none (his ask after watching lone scouts die). Unmeasured.

## Nukes and superweapons

- `TUNE_BRAIN_NUKE` = 1. The nuke director (logistics, target ranking); 0 leaves silos to stock.

## Scouting, intel, ghosts

- `TUNE_ESCORT_SQUAD_VALUE` = 2000. Squad metal above which it is owed a radar/jammer escort; his number ("any squad worth over 2000 metal").

## Base layout and placement

- `TUNE_FRONT_BAND_FRAC` = 0.35. Front band width as a fraction of territory radius: 1.0 called half the perimeter front; 0.35 is a +/-49 degree arc.

## Diagnostics and switches

- `TUNE_MEMO_TTL` = 300. Ceiling on a memoised proposer answer: 45 expired before the next same-def builder asked (hit 593, miss 3,135); 45 -> 150 -> 300 on 10-01 for 8v8 cost.
- `TUNE_ELEC_FRAME_US` = 8000. Microseconds one frame may spend on builder elections, sliced between proposer steps; trades hitch size for order latency. Unswept: read `apex: elec-slice` worstWaitS first.
- `TUNE_PERF` = 0. Per-section profiler and the lag governor's cuts; off by his ruling ("Default to 0, harness passes it explicitly"). No `frametime.py` output means this was off.
- `TUNE_CATALOG_DUMP` = 0. Dump every def's catalog row at init for `check_catalog.py`; ~1,000 lines, so off.
- `TUNE_DECIDE_LOG` = 1. The `apex: decide`/`exec` lines every harness tool parses; on. Costs a string build and a mutex per election, so 0 suits a live game nobody reads.
- `TUNE_NN_BLEND` = 1. His call: the nets steer in his slot and lobby games (with no modoption).
- `TUNE_NN_EXPLORE` = 0. His call: nothing plays random on purpose in lobby games; training passes its own share.
- `TUNE_NN_PLAN_EXPLORE` = 0.1. Share of explorers that also lead their team with one drawn plan: his "much less" whole-team strategy exploration (forced RUSH won 0/21).
- `TUNE_PLAN_EXPLORE` = 0. Per-bot lobby option ('Try strategies'): draw only the team plan, so his multiplayer games teach the plan net without random builders.
- `TUNE_GUNP_RULE` = 1. The forced-gun head's rule value. 0.35x vs 1x over 24 games each was within noise; left at 1 for the head to learn.
- `TUNE_CON_RULE` = 2.5. The constructor head's rule value: 2.5x read eco 0.99 vs 0.69 at minute 11 against 1x, at the cost of army (0.42 vs 0.67); 1.6x gave up the eco without buying the army back. Kept 2.5.
- `TUNE_PLAN_FORCE` = -1. Test switch: every team plays one plan all game, for an A/B without explorer noise. -1 lets the plan net choose.
- `TUNE_PLANT_PIPE` = 2.0. The constructor pipeline's return in spot-streams: 0.5 put lab 1 at 5.1 min (his "build the first lab a bit sooner"); 2.0 targets the ~2-min human timing.
- `TUNE_PIPE_LATENCY_H` = 78.1. 60 -> 78.1 by the 10-04 valuation search (see TUNE_CONV_HORIZON).
- `TUNE_TECH_SURVIVAL` = 1. Discount a tech want's deferred gain by the risk over its pipeline; 0 is the A/B control.
- `TUNE_ECO_SURVIVAL` = 1. The same survival discount on long-payback generators (fusion, afus); 0 disables.
- `TUNE_SIEGE_PRIOR` = 1. Share of our own economy assumed turned into enemy army walking at us, seen or not; used only by the survival discount, never to size production.
- `TUNE_LINE_TANK` = 0.28. Army composition target by line class: his 28/20/35/17 (tank/mid/reach/dps; re-ruled 08-29 for more snipers, hounds and artillery).
- `TUNE_LINE_ADAPT` = 0. Bend the reach target up by the enemy's static share: 0-11 and trade 0.37 vs 0.53-0.65 at 1.0 (no screen left). Off; the direction stands, the shape is wrong.
- `TUNE_MEX_GUARD_FAR` = 3. His "the further from home the more defenses the mex needs": a mex earns 1 + far x forward-fraction towers. Comet 8v8 seed 1: metal 418k -> 559k, our mexes at 24 min 9 -> 31.
- `TUNE_WORTH_COST` = 1. Cost exponent as a choice of Lanchester law: 1 = linear (chaff wins the draw), 0 = square (quality wins); 1 is what this AI has always priced.
- `TUNE_WORTH_DIAG` = 0. Print the worth exponents and field means (2 = the ranked field).
- `TUNE_RECORD_BITE` = 1. The unit track record prices units: an exchange matrix (our type x their type, metal destroyed each way) kept across games in `apex-record.txt`, judged against the unit's own line class, normalised over the buildable army; fodder and fighters exempt, disabled under tweakdefs. Nearly inert in practice (0.9-1.0 for a handful of units); removing the cap is his call.
- `TUNE_EVIDENCE_SHRINK` = 0. Price a def scoring far outside its line class, with no record of its own, back toward the class (scavenger Epic Tumbleweed read 19.3 power per metal against 0.05-0.13 and zeroed the real T3 line). Off; A/B not run.
- `TUNE_AIM_MISS` = 1. What reach is worth for a weapon that cannot hit a moving target; 1 counts it in full.
- `TUNE_LINE_MEDIAN` = 1. Judge each class axis against the field median, not the mean (an outlier sets the mean).
- `TUNE_LINE_ABS` = 1. Read the tank and dps axes per body, not per metal; off made a Thud tankier than a Tzar.
- `TUNE_LINE_RANGE_EXP` = 1. Exponent on the range axis of the class argmax; 1 is the original.
- `TUNE_LINE_ALLOC` = 0. Factory draw runs only within the line class owed most metal. On: reach share 0.06 -> 0.12 but army metal 544k -> 60k and k/l 0.81 -> 0.12: T1 labs yield forever to a plant that never pays the debt. Off until yielding waits on a debt actually being paid.
- `TUNE_COVER_WORTH` = 1.5. Worth of ground covered per metal while the fleet is short of sites to watch; buys cheap fast bodies early, fades as they arrive.
- `TUNE_STREAM_SURVIVAL` = 1. Discount a mex stream by the share still collected over the stake horizon; a tower in reach raises it. 0 is the A/B control.
- `TUNE_SPACE_RENT` = 2. Rent for standing on defended ground (covering guns' metal per cell), so dense beats sprawl inside the perimeter.
- `TUNE_PAYBACK_H` = 900. Credit a gain only for the share of this horizon it is collecting, against the small steps that deliver now; build power shortens it.
- `TUNE_LOCKUP` = 0.5. Option cost of capital tied up in an unfinished frame; his "little bit extra of a penalty on top of time".
- `TUNE_LATE_BUILD` = 1. The late-start charge counts the build as well as the walk (his "the cost in that walk sec is ALSO the amount of metal you'd have lost"): an Epic at v=10.9 over an AFUS at 5.8 reads ~1.5 vs ~4.3.
- `TUNE_COMMIT_SHARP` = 12. Draw sharpening added for an expensive commitment, in proportion to its cost against the horizon's output: big wants near winner-takes-all, cheap ones keep sampling.
- `TUNE_FARM_ROW_W` = 320. Length of one farm row; halved from 640 on his report that the winds stood too far out.
- `TUNE_FRONT_LINE` = 1. Offer the spaced front posts to the defence auction; 0 is the A/B arm.
- `TUNE_STANDOFF_COVER` = 1. Measure turret cover on the ring the enemy shoots from (their seen range), weakest bearing.
- `TUNE_COMM_FIGHT` = 1. The commander may fight while he still outclasses the field (before heavies are out).
- `TUNE_TECH_PIPE` = 2.0. Discount on a tech plant's unlock demand; a second 0.5 double-counted the pipeline delay and priced the T2 lab ~100x under a nano (zero tech decisions in 12 min of an 8v8).
- `TUNE_E_BILL_SHARE` = 1. While e-stalled, price a build's energy bill by the share of income its drain eats (his "it only matters when we're e-stalling"; an advanced solar is unaffordable at 100 E/s, cheap at 400).
- `TUNE_CONV_HORIZON` = 417.1. From the 10-04 valuation search (943 games vs NullAI, +11% economy confirmed against BARb on Carrot): 300 -> 417.1, with CON_BASE, CON_FEED_HEADROOM, DRAW_SHARP, JOIN_MIN_M, M_WASTE_WORTH, PIPE_LATENCY_H, SITE_COST_PER_WORKER, T2_CON_PER_M and VW_FLOW.
- `TUNE_E_FEED_BOUND` = 0. Bound the standing fleet's energy ask by the metal feed that would run it: the ask fell 740 -> 317, outcomes flat over 76 games. Off; the inflation is upstream (`BuildEnergyDensity` averages the whole catalogue).
- `TUNE_E_HEADROOM` = 1.75. Energy income target as a multiple of trending pull; 1.25 and 1.5 still under-supplied in watched games.
- `TUNE_ESCORT_SPEED` = 1. An escort must catch a raider or be a riot unit (his "rocket bots die in a 1v1 vs a pawn"); a multiple of the field's mean speed.
- `TUNE_MEX_GROWTH` = 8. A spot is worth what it raises us by (his "when a mex would double our income it is very important"): at 8, doubling x9, +10% x1.8, +1% x1.08.
- `TUNE_INFERIOR_DISCOUNT` = 1. Discount a generator by how much better one another constructor of ours could build, so a restricted worker spends its time on the better one.
- `TUNE_ENERGY_GROWTH_ARRIVE` = 0. Charge the energy growth premium only on the share of the plan horizon a generator pays over, so the Epic reactor stops winning for its size (his "we should make AFUS first ... the algorithm smart enough to have chosen this"). Off; untested.
- `TUNE_E_REALIZE` = 1. Price generation by the share anything would use (demand at headroom plus converter capacity); 0 is the control.
- `TUNE_E_WASTE_WORTH` = 0.25. Overflow makes a generator lose to the converter, never unbuildable (his ruling: the generator ladder never pauses on waste). Chosen, not derived.
- `TUNE_M_REALIZE` = 0. Price extraction by the share of its metal we could spend. Inert where measured (377 of 389 samples share=1.0, also at +50%); left off. `LatheRealizedFrac` answers the overflow instead.
- `TUNE_M_WASTE_WORTH` = 0.3753. What a spot is still worth when its metal would only overflow; never 0, demand grows. Unmeasured. 0.25 -> 0.3753 by the 10-04 valuation search.
- `TUNE_THREAT_GRADIENT` = 1. Spatial threat prior, 0 at our start box to 1 at theirs; 0 is the flat control.
- `TUNE_SCREEN_WORTH` = 0.2. Sight and dash per metal, read instead of combat worth when larger. Normalising the axis lost 1-7 where the inflated one won 6-2 (the pawn flood wins the opening); reverted.
- `TUNE_SCREEN_MAX` = 5. Standing screen units (the Tick class) a player keeps; unbounded, a T1 lab was a flea conveyor (67 built, 2 standing). His number to move.
- `TUNE_MEDIC_FRAC` = 0.12. Rez/repair fleet as a fraction of army value (his "3 times more rezbots", was 0.04); bounds the wreck-stream sizing that once bought 210 rez bots in one 2v2.
- `TUNE_WATER_FIRST` = 1.0. Denial worth of land-locked water metal on top of its stream while the water is uncontested (his "the earlier you get into the water the more likely you are to own it"); decays with their navy.
- `TUNE_AA_URGENCY` = 1. Multiplier on the AA insurance rate; 4 compensated a value ~50x too small, so 1 once AA was priced like a ground turret.
- `TUNE_AA_COVER_FRAC` = 0.5. AA metal standing per metal of enemy air seen; his "100k of air ... at least 50k of AA".
- `TUNE_ECO_AA_MULT` = 1.5. The eco seat answers more of the air census than its headcount share; his "~50% more anti air than your average player".
- `TUNE_JOIN_MIN_M` = 354. 500 -> 354 by the 10-04 valuation search (see TUNE_CONV_HORIZON).
- `TUNE_T2_CON_BASE` = 1. T2 constructors always wanted: base plus one per T2_CON_PER_M of income (his "1 T2 con + 1 per 25 metal"). Gating the overflow term cut metal 335-554k -> 165-262k on Carrot 1v1 (the extra T2 cons are the mohos); reverted.
- `TUNE_T2_CON_PER_M` = 31. His "1 T2 con + 1 per 25 metal"; 25 -> 31 by the 10-04 valuation search.
- `TUNE_CON_BASE` = 4.38. Constructors of any tier ordered before the draw: his two points (3 at 12 m/s, 5 at 100). `HandsShort` adds hands at the working hands' real spend: minute-8 metal per player 8.1k -> 11.6k on Comet. 2.7 -> 4.38 by the 10-04 valuation search (more constructors was its one consistent signal).
- `TUNE_T1_AIR_CON_MIN` = 10. Basic air constructors kept once an air lab stands, one queued at a time so other air keeps coming; his number (ten).
- `TUNE_RECLAIM_REZ_BIAS` = 3. A reclaim is worth more to a rez bot than to a constructor that could be claiming ground; lifts once no spot is open.
- `TUNE_NANO_SITE_SHARE` = 1. Share of unspent metal one site may claim as nano demand; replaced a 35 m/s clamp that left gantries on 2-5 nanos against the enemy's 38.
- `TUNE_MEX_TRIES` = 10. Ranked spots offered to the engine per election; a bound on work, not on expansion (3 read as "no ground left").
- `TUNE_ROOM_WORTH` = 1. Worth of the room under an obsolete building, so a wind farm pays for the space it holds.
- `TUNE_INSURE_RATE` = 0.0003. Protection value per metal of covered assets per second, the one risk quantity for eyes and turrets; 5e-5 lost every radar to marginal solars.

## Strategic structures -- manager/brain/market/want_super.as

- `TUNE_SUPER_WANT` = 1. Master switch for the strategic want (gantry, silo, anti-nuke, LRPC).
- `TUNE_SUPER_PUSH` = 1. An affordable strategic want skips the category lottery; priced normally they are drawn about once a game.
- `TUNE_SUPER_AFFORD_S` = 60. A strategic bill must be under this many seconds of output: anti-nuke from ~36 m/s, LRPC ~90, gantry and silo ~160 (his "at 200 m/s we should eagerly build one").
- `TUNE_SUPER_PER_INCOME` = 150. Income per extra anti-nuke, twice that for silos and LRPCs; never a cap (his "at least 1 usually, more if we want to be safer"). Extra anti-nukes only once an enemy silo is seen: unseen, they beat the gantry in every election.
- `TUNE_SUPER_SHARE` = 0.25. Slice of economic power the strategic market may claim as gain, scaled by budget left after the bill.
- `TUNE_SUPER_FLIGHT_PER` = 140. One more strategic frame may stand half-built per this much structural overflow.
- `TUNE_CON_FEED_HEADROOM` = 1.847. Hands the production draw prices toward, as a multiple of the hands income keeps fed (his "we make too many constructors"). 1.5 -> 1.847 by the 10-04 valuation search.
- `TUNE_UNIT_AFFORD_S` = 120. A unit's bid fades as its cost nears this many seconds of income: 60 -> 120 at his call ("we need more Titans or Thors"), a Thor bids from 75 m/s, a Titan from 112.
- `TUNE_SCOUT_OVER_S` = 45. One idle cheap air scout crosses the enemy position this often (his "I don't see any scouts flying over their base").
- `TUNE_ECO_ROLE` = 1. The eco role, re-armed at his ask 08-31 with the mechanism replaced: it names a different target (EcoRoleTargetM) instead of crushing army and defence targets.
- `TUNE_ECO_FORCE` = 0. Force this AI to be the eco seat (his ask): the value is the share of the eco target it grows to before army and defence return. A modoption seats every Apex AI in the game.
- `TUNE_ECO_LATCH` = 1. His ruling 10-15 ("just have 1 eco"): the eco seat is elected once and keeps the role while its heartbeat (team board `ecohb`) lives. Before it, his 8v8 moved the role t6 -> t2 at 18 min when t7 died beside t6.
- `TUNE_ECO_SEAT_STRICT` = 0. While the eco seat grows, its hands and labs take only economy (plus AA while air kills us); the seat held 4 mexes all game in his 10-15 8v8. Off until an A/B; `apex: ecoseat-stat`.
- `TUNE_GANTRY_AFFORD_S` = 100. Gantry affordability over team income: the ~9.3k bill clears at ~100 team m/s (his "we can have a gantry at like 100 m/s").
- `TUNE_GANTRY_HOST_INC` = 150. The proposer's own income at which the gantry gain is whole, scaling (own/anchor)^2 below: 100 -> 150 at his call; a hard skip below it left six of eight 8v8 players gantry-less at 38 min ("not ok"), so the scale was restored.
- `TUNE_OFFENSE_DEF_FLOOR` = 0.1. Share of an offensive super's gain kept at zero standing defence; the rest scales with defence fill (his "we consistently make Basilisk before T3 or even T2 defense").
- `TUNE_OBSOLETE_RATIO` = 4. How many times better the best alternative must be before a building is scrap (his "much better"). A team-wide basic-converter ban cut metal 704k -> 296k (the advanced ones never replaced them); the per-hand test `DenserHandsCover` serves his "even at 1000 metal per second we're still making basic converters".
- `TUNE_EXPOSE_R` = 1200. Reach inside which enemy metal near a worker counts as escort demand; exposure itself is the risk field and territory now (the radius once put a Pawn on 225 of 272 buildings' workers).
- `TUNE_EXPOSED_LOSS_S` = 120. Seconds over which a fully exposed asset is expected lost (his "almost guaranteed"); 300 claimed every spot naked and lost it, 120 flips to claim-then-guard.
- `TUNE_FRAME_RISK` = 0.0. Charge an unfinished frame's expected loss: at 1.0 metal built 38.6k -> 17.6k, head-to-head 3-21 -> 0-30 over 54 games. Off until the hazard field is not saturated everywhere.
- `TUNE_DEF_TRADE` = 3. Metal of enemy wave a turret stops per metal of its cost: the exchange rate putting cover and threat in one currency.
- `TUNE_DEF_TTD_H` = 120. A defence keeps H/(H+buildSec) of its value, so slow turrets cover less of the threat window; 0 restores wage-only build time.
- `TUNE_PROTECT_FIELD_S` = 15. Protection field rebuild period: 2 -> 8 -> 15 s, as each rebuild re-keys four memos (18% of all AI time in an 8v8); a tower takes 20-60 s to build.
- `TUNE_STALL_ANSWER_S` = 1. How often the energy-stall answer re-asks which worker should drop its task.
- `TUNE_STALL_ANSWER_MAX_E` = 400. His number: above this energy income a stall no longer pulls a builder off its task. Gates only the interrupt; the per-election hoist reads the deficit (700 E/s against a 1,950 deficit had stalled 12 minutes). His: "would be fixed if we just had constructors consistently creating energy buildings".
- `TUNE_UNPROT_DISCOUNT` = 0.20. His "give buildings a ~20% reduced value when they are unprotected"; cover gives it back.
- `TUNE_DEF_ALPHA_W` = 1. A turret's cover weighted by hp/(hp+alpha) of their biggest unit's punch: separates a Twin Guard from a Bulwark once they field heavies.
- `TUNE_ECO_RAID_TAU` = 180. Memory of the structure-loss field; matches the death ledger's.
- `TUNE_THREAT_R` = 900. Radius of the enemy-mass prior sample (the DeathWalk corridor's).
- `TUNE_STAKE_HORIZON_S` = 300. Seconds of a mex's stream that count as the stake on it.
- `TUNE_RISK_FLOOR` = 0. Flat hazard on every asset; at 0.15 it was the whole early tower demand (nine LLTs before minute 8; his "too many early game defenses"). The blind floor is now the siege prior, an output.
- `TUNE_HZ_APPROACH` = 0. Hazard from enemy formations walking at our ground. Fires as built (4x the floor) and changes nothing in 8 games: one tower's share of a big wave (`stopped`) is ~0, so the price is a product with a zero. Kept as an instrument, off.
- `TUNE_ALLY_SHARE` = 1. Scale the seen enemy census by our income share of the team, so the side answers once, not every player in full.
- `TUNE_REZ_HORIZON` = 120. Seconds over which the repair backlog is read as a rate; measured in steady state (backlog/120 is the arrival rate), left alone.
- `TUNE_REZ_UTIL` = 0.35. Share of a rez bot's work rate delivered; 0.25 fielded 99-129 Rectors per player (his "wow we have a lot... turn the rezbots down a little"), 0.35 is ~30% fewer. Unmeasured.
- `TUNE_RETREAT_FLOOR` = 0.08. HP fraction where the cheapest unit starts to flee; set against stock's 0.6 (93% of combat metal died retreating) and his "units retreat on a very low HP %". Move only with a `deaths.py` died-retreating read beside it.
- `TUNE_T1_TOWER_LATE` = 0. Off since 10-13 by his ruling (towers compete on kills per metal, splash counted). Was: no basic tower once an advanced hand exists; with it off towers were still a tenth of BARb's, so the rule was never the defence gap.
- `TUNE_PLANT_COPY` = 0. His ruling: a copy of a line we already run is ineligible; the want goes to a nano. Letting copies compete measured worse (minute-4 extractors -0.67 over 96 games). Kept.
- `TUNE_DRAW_DEFZONE` = 0. Draw the base-defence and push-alarm rings on the map; the harness opts in.
- `TUNE_DRAW_LANE` = 0. Draw the army's staging anchor (and the medic station); off because it ships.
- `TUNE_DRAW_HEAL` = 0. Ping the heal post wounded units retreat to.

## Everything else

- `TUNE_AFLOAT_SUB_COST` = 400. Seen sub value that reads "the enemy lives on water", only when it outweighs their land army: two subs once sent seven players to air plants while ground walked in.
- `TUNE_BUDGET` = 1. Gates `BudgetMult` itself, so `apex: budget` prints real multipliers with the lever off.
- `TUNE_BUDGET_LEVER` = 0. Budget target/actual multiplies want values (his "we whip things back into shape"): moved defence and army shares as asked and won 3.1% of 32 against 12.5% of 48 off; 22% of metal is chosen with no rival to steer toward. Off.
- `TUNE_DEATHWALK_PRICE` = 0. Price a spot whose walk crosses hot ground instead of refusing it: 1-16 vs 2-16, fewer mexes held at 20 min. The refusal is right. Off.
- `TUNE_COM_MEX_PRICE` = 0. Price a spot outside the commander's leash instead of vetoing it. At 0.35 over 32 games: income at 12 min +38%, commander deaths 37 -> 20, early losses 12/32 -> 4/32 (p 0.04); the 45-min test could not resolve wins. 0.35 was not swept; turning it on changes what he may do, so it is his call. Off.
- `TUNE_ARMY_RICH_BALANCE` = 0. Offer the spare-metal army floor only while army is under target: army share 51% -> 40%, economy 19% -> 27%, but 2/32 vs 6/32 wins. On at his ask 09-23, off 09-24 after army starved at 10x their income (his ruling: extra metal to build power or army, never army starved while rich).
- `TUNE_BUDGET_AFTER` = 1. Applies the budget's target/actual correction to each category's ticket after the draw's sharpening, where 2x is 2x the odds; on want value the commitment exponent cancelled it.
- `TUNE_ETA_COMMIT_BONUS` = 0. The market must beat the ETA ladder by a share of the extra fleet time a bigger reactor locks up: afus orders 101 -> 18, no gain in 45-min games. Off as unvalidated; test in a long game.
- `TUNE_WAVE_CONC` = 1. A defence site prices against their whole army (capped by the stake behind it): their mass takes one approach. Lets a Pulsar out-bid a carpet of cheap towers.
- `TUNE_WALL` = 1. Ground defence sites are slots along the wall (our rim plus standoff, at tower pitch); 0 restores the old candidate set.
- `TUNE_WALL_REACH` = 2.5. Cap on how far one bearing's buildings drag the wall, in RMS radii: a lone far mex stays outside.
- `TUNE_WALL_REAR` = 0.08. Pull a slot directly behind the base keeps; low is his concentration ruling ("if we just focus on defending our frontline we don't have to build so many defenses all around our backline").
- `TUNE_WALL_LINE_W` = 2. The front line's pull over the ring: his completeness ruling (a wall they can walk around is useless).
- `TUNE_WALL_EFFICIENT` = 1. A wall slot ranks towers by cover per metal; otherwise a T1 hand buys its most expensive tower for a quiet rear slot.
- `TUNE_DEF_KILL_CAP` = 1. Cap a site's stake at the attacker metal the turret can kill in the exposure window, so reach is bounded by rate of fire.
- `TUNE_DEF_DPS_LINEAR` = 1. Price cover on surface DPS, not the engine's sqrt-compressed threat; rate of fire was the under-weighted term.
- `TUNE_T1_DEF_LATE` = 0.02. A T1 tower's gain when the asking hand can build better; keyed on the lab it priced every T1 gun at 2% from minute 10 to 20 (his "nothing between 10 and 20").
- `TUNE_RADAR_OVERLAP` = 0.45. Share of radar radius a gap must clear before a new mast; was 0.8 (no redundancy, one death a dark zone).
- `TUNE_FRONT_REAR_ARC` = 0. Escape hatch: the full ring as front for a surrounded base. It shipped on once, so the rear exclusion never ran.
- `TUNE_ASSIST_RELEASE` = 1. Assisters beyond a site's derived crew return to the auction.
- `TUNE_NANO_FED_S` = 15. Refuse a join when standing nanos alone clear the site's bill within the walk plus this; the freed constructor founds a new frame.
- `TUNE_DRAW_SHARP` = 2.903. How sharply the category draw follows value, odds (value/leader)^this: 1 took a lower want in 34% of elections; pure argmax starved every category never #1. 2 -> 2.903 by the 10-04 valuation search.
- `TUNE_ROLE_SHARE` = 0.5. His design: a share of constructors hold a role (one category until the split says otherwise), the rest stay open; the split is the draw's ticket share floored by each category's target gap (his "builder roles from target gaps"), averaged over TUNE_ROLE_TAU. `apex: roles` is the instrument.
- `TUNE_T2_FUSION_PULL` = 0. While the T2 switch is on and no advanced generator stands, take a fusion from the list rather than draw it: we tech first and then wait 8.2 min for a fusion (BARb 1.1). Overrides a price (wind is not worse per metal), so a tunable. Off; his "fusions ... pretty soon" is the ruling it waited for.
- `TUNE_BUDGET_TAU` = 240. How far back realised spend is averaged; lifetime totals read the commander as 100% build power. A diagnostic until something reads BudgetMult again.
- `TUNE_MEDIC_SHARE` = 0.4. Share of the rez fleet serving as medics at the army's staging anchor.
- `TUNE_MEDIC_SETBACK` = 0. How far behind the lane a medic holds station; 0 is on the lane.
- `TUNE_REZ_FLEE_S` = 20. How long one hit keeps a rez bot retreating; 90 s parked bots for a stray shell.
- `TUNE_REZ_SCAN_S` = 1. Spacing of one bot's own wreck scans; a team-wide clock left most idle bots standing.
- `TUNE_REZ_REACT_S` = 1. His latency bar ("delays of more than a second are unacceptable") turned into distance: rez bots back away while the enemy is this long from firing range; the DLL guard and the election read it alike.
- `TUNE_RAIDER_MASSING` = 0. Raiders join the massing pool once our advanced lab stands; at 1, zero raid and zero attack elections across 11 matches. Off: they raid all game, as stock does.
- `TUNE_SPAM_RAIDERS` = 1. Cheap raiders go to solo scout tasks in the spam phase. On at his call ("All these escorts should instead be the fodder/spam guys ... if raider-spam works correctly then yes"): judge on where they die, not the flag.
- `TUNE_AISLE_GROW` = 1. A growing cluster keeps the aisle to a foreign def, so growth does not seal units in.
- `TUNE_CLUSTER_N` = 16. Same-def buildings per cluster before a new one starts elsewhere (a 4x4 block).
- `TUNE_RECLAIM_BLOCKER` = 0. Reclaim our own building standing in a lattice slot the DLL could not place: metal built 17,978 -> 12,417 over 8 paired seeds, tiling worse too. Off.
- `TUNE_DEF_OFF` = 0. The no-turret test: no ground or AA turret at all, so units are the whole defence; `test_earlyfight.py` sets it.
- `TUNE_ECO_TARGET_BASE` = 250. Economy the rear specialist names before spending on war, at no bonus (x handicap): his "no army and no defense until like 20 minutes" as economy.
- `TUNE_ECO_TARGET_BASE_8` = 500. The eco seat's target on an 8-player team: his "go full military and normal behavior at 1k metal" (500 x the +100% bonus). Zero defence and no army while it grows (his ruling); the raid valve still ends the growth.
- `TUNE_AIR_ECO_BASE` = 100. Economy (x handicap) before a bomber raid is worth mounting: his "200 m/s" at +100% and "we don't want to make air too early". Replaced an 11-minute timer.
- `TUNE_LINE_TERRAIN` = 1. Weigh a production line by the map share its army can move on: his rule for picking bots on hills, vehicles on flats.
- `TUNE_SCREEN_GAP` = 200. Read by nothing since the 09-07 fight revert. Was how far in front of the long guns a short row holds (his "tanks stand in front of the sheldons"); 96 lost to 200 three ways.
- `TUNE_TEAM_LINE` = 1. A team's second copy of a line prices at half, the third a third (his 4v4 complaint about four bot labs); not exclusivity.
- `TUNE_COVER_LEAVES` = 1. A full cover pool promotes to attack like stock's massing pool, and cover metal is bounded by the raider metal they field (his "try doing both" after 427 units sat in cover).
- `TUNE_COVER_BY_RAID` = 1. Cover metal bounded by our share of the raider metal they field; see TUNE_COVER_LEAVES.
- `TUNE_LINE_QUALITY` = 0. Weigh a plant by its units' army per metal times the ground they cross (his "in maps where vehicles are obviously more powerful, we don't do quite as well"). Measured inert, then worse: the plant is bought for its constructor and a 17% factor never decides it. Off.
- `TUNE_DEF_DOMINANCE` = 1. A tower beaten on reach and kill by an affordable gun keeps kill/dominator-kill of its gain (his "why build something that so quickly becomes outdated?"); a price since 10-10, not a refusal (his "At -1 we'd never build it and would never learn its usefulness").
- `TUNE_DEF_AFFORD_S` = 30. A defence counts as affordable under this many seconds of economic power, so an unaffordable Pulsar does not obsolete every tower.
- `TUNE_CONV_AFFORD_S` = 30. Seconds of economic power the converter burst may commit; the bank was the wrong bound (run near empty, the burst never fired).
- `TUNE_E_COMMITTED` = 1. Count ordered work's energy draw in the pull that prices energy; without it the first energy decision came 73 s and one stall late.
- `TUNE_E_PARALLEL` = 0. Let a stall open parallel energy sites: metal 25,500 -> 19,555, mexes 42 -> 33 for a smaller stall; against his rule to focus build power on one building. Off.
- `TUNE_PLANT_INFLIGHT` = 1. Discount a plant want by other domains' plants in flight, so bot/vehicle/air frames do not split the income and finish none.
- `TUNE_COVER_PUSH_S` = 10. The mex-cover queue jump fires only below this many seconds of economic power: his order (mexes and lab first). Swept 10 -> 40: fired twice as often, fewer towers (a jump reorders, it adds no demand). Stays 10.
- `TUNE_RADAR_PRICE` = 0. Defence as a crutch (his: "how the hell are we spending 10 to 13% on radar"): price radar by the army and buildings it newly watches, not a share of everything. One of five switches that turn a draw-bypassing rule into a priced offer; each A/B'd alone; `apex: ecodef-stat`.
- `TUNE_DEFJOIN_PRICE` = 0. Defence as a crutch: a free hand joins a tower in flight at the gain its build power brings forward, in the draw, not at v=1000.
- `TUNE_FIELD_PRICED` = 0. Defence as a crutch: a field-crew hand whose top job is a tower or radar keeps its whole list and goes to the draw.
- `TUNE_COVER_PRICED` = 0. Defence as a crutch: the uncovered-mex tower and the base-front gun bid at the def's going rate instead of a placeholder that skips the draw.
- `TUNE_DEF_DANGER` = 0. Defence as a crutch: the economic share of the defence target is scaled by the share of the danger our army (and allies near) cannot meet. Its decay horizon is borrowed, not derived.
- `TUNE_MEXUP_BOOST` = 1. Thumb on mex upgrades over the arithmetic. At 2.79 upgrades became the top want and the outcome was worse (metal built 863k -> 358k): it displaced the energy that pays for expansion. Left at 1.
- `TUNE_DUP_BP_SUBST` = 1. Price a duplicate lab against the turrets that buy the same build power (nine times per metal; his "add more nanos to the lab instead of making another lab"), while the line is short of hands.
- `TUNE_REPLANT_DISCOUNT` = 0.15. A plant def we reclaimed on purpose prices at this while the window runs: 14 of 15 T2 labs in one 1v1 were reclaimed and re-bought.
- `TUNE_REPLANT_WINDOW_S` = 600. How long that retirement memory holds; chosen to outlive the ~90 s walk-and-rebuild cycle.
- `TUNE_FOE_TIER_FADE` = 1. A unit's and a line's value fades with the share of enemy metal above its tier, 1/(1 + this x share); chosen, not measured.
- `TUNE_OWN_TIER_FADE` = 0.8. The same fade against our own top tier (his "in late game, aside from spam we should mostly only be putting our resources into T3 units and advanced air").
- `TUNE_DEF_PRIOR_SHARE` = 0.35. Share of a mirror enemy assumed able to reach our base before anything is seen; without it the defence target is zero until attacked.

## ValueOf term weights

- `TUNE_VW_FLOW` = 0.6598. 1 -> 0.6598 by the 10-04 valuation search (see TUNE_CONV_HORIZON).
- `TUNE_MEX_LOSS_COVER` = 0.1. Extractor gun queue-jump while measured extractor losses run high (his "queue-jump only while losses are high"); half of builder decisions were guns, gated +22% eco (n.s.). The `mexg` head divides it.
- `TUNE_BASE_FRONT` = 1. His "we protect our metal extractors, but we don't protect our base": medium/heavy lasers on base-edge slots facing the enemy while out-massed, sized to max(their seen army, ours). Measured firing but starved of slots.
- `TUNE_COM_ESCORT` = 1. While constructors are owed escorts, the commander assists the nearest lab (his idea); far hands always take the extractor-gun push. Even in head-to-heads vs v0.1.1/v0.1.2.
- `TUNE_COM_LAB_EARLY` = 1. The commander supports the lab early (his plan after mirrors stuck at 50%): constructors lost by minute 10 0.9 -> 0.5. To become a price, not a queue jump.
- `TUNE_ESCORT_CAP` = 8. Escorts at once; the 1x base of the `ecap` head. `EscortShortfall` still stops at the flat rez-bot cap.
- `TUNE_ESCORTS_PER_CON` = 2. Escorts per exposed constructor (his plan for fewer constructor deaths); the `esc` head scales it.
- `TUNE_BIRTH_DEFEND` = 0 (`apex_birth_defend`, also read in C++). His 10-15 watch: two units out of a T2 lab under attack ran instead of defending it, and the lab died. A fighter tasked while seen armed ground enemies engage its spot (its reach plus theirs) defends there unless the influence odds are past `apex_withdraw_odds`, released 5 s after nothing engages it; a defender beside our structures counts their guns and the labs' output before the pack arrives, and regroups at them instead of a rally. `apex: birth-defend-stat`. Unmeasured.
- `TUNE_AOE_VS_BLOB` = 0 (`apex_aoe_vs_blob`). His 10-15 watch: 3 Fatboys all game against a 36k blob; the T2 lab ranked it at the role floor (r0.05). `splash.as` reads, every 10 s, each seen or remembered enemy armed ground unit's neighbours by distance; `h(r)` = extra enemies a shell of radius r catches, linear falloff. A ground unit that hits the surface with `gAoe > 0` gets `ppc *= (1+h)^apex_worth_dps` (damage x (1+h), priced as worth.as prices damage), and its role weight blends `sW + (1-sW)·roleW` with `sW = s·max(0, (T-V)/T)`, `s = h/(1+h)`, `T = min(seenEnemyM · AnswerShare · s, armyTarget)`, `V` = our owned splash units' metal times their own `s`. Same shape as the coverage blend. The 10-13 `SplashMul` on every unit (no exponent, no target) priced artillery ~5x a tank and was removed; this keeps the target saturating on owned splash. `apex: aoe-stat` (minute): biggest enemy group metal/count, seen metal, density per 1000 elmo² and hits at 64/128/256, top 3 splash units with multiplier, owed metal, role weight and value with/without. Unmeasured.

## C++-only options (read through `GetTunable` in the DLL; no `TUNE_` constant)

- `apex_fight_travel`. Attack and defend tasks travel with fight orders instead of moves (his watch: a squad moved straight into a pack in our base). Off pending A/B.
- `apex_target_value`. Value-based targeting: groups by worth per second of walk and fire, fire allocated in lethal doses to the lowest kill time (his doctrine on targets). 43% of our kills are under 100 metal. Off pending A/B.
- `apex_unit_cover`. Mobile units count as cover for buildings (his ruling). With it off ~70% more defence stood and the abort rate did not move (54% -> 53%). Left at 1.
- `apex_inbase_path`. Path in-base hops instead of skipping pathing: removed the anomaly (119 -> 0) and not the stuck builders (21 -> 20), mexes held worse. Off.
- `apex_hold_<unit>`. What a unit is good for when ground is lost: the Behemoth 2x is his call ("the best thing to do in this situation is to make a Behemoth"). Live only while losing ground. Unmeasured.
