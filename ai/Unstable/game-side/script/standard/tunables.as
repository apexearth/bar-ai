// ONE PLACE FOR EVERY DEFAULT.
//
// apexearth 2026-08-21: "I would like to reference them by a config module
// or something like that so that there's just one file that I can go to in
// order to modify all of our defaults. Then I can see myself and tweak
// things without needing to ask you for help on tiny little tweaks."
//
// EDIT A NUMBER HERE, run `python tools/deploy_ai.py deploy apex`, done.
// Every ai.GetTunable call in the AI passes one of these as its default, so
// this file IS the shipped behaviour. A live dev game can still override any
// of them per match (modoption -> dev_tunables.lua -> rules param), which is
// what the names are for; the value here is what applies when nothing does.
//
// Included FIRST in main.as: AngelScript resolves globals in declaration
// order, so every consumer must be compiled after this file.
//
// Naming: TUNE_<NAME> mirrors the tunable "apex_<name>" exactly.
//
// One line per entry: its units where the name implies them, then what the
// knob does. The reasoning behind a default -- the measurement, the A/B that
// failed, the ruling -- is in docs/27-tunable-rationale.md under the same
// TUNE_ name; "See docs/27" on an entry means there is more there. Where the
// knob is READ is not written down, because it rots: grep the apex_ name, or
// read the dashboard's Balance tab, which derives it from the source tree.
//
// WHAT IS NOT HERE: build RATIOS. The army/economy/defence split lives in
// targets.as (SPEND_ARMY, SPEND_ECONOMY, ... -- five columns, one per build
// phase, normalized against each other), and unit mixes per factory live in
// config/standard/factory.json. "Build less army" is targets.as; "when
// is a fusion allowed" is here.

// ---------------------------------------------------------------------------
// Economy — energy, fusion, converters, reclaim
// ---------------------------------------------------------------------------
// [toggle 0/1] -- ADVANCED SOLARS ARE STRICTLY SERIAL, whatever the bank.
const float TUNE_ADVSOL_SERIAL = 0.f;   // leaf-era decree off: the wealth cap (dup_bank) bounds parallels; serial refusals churned 8.6k decides at 500 m/s

// [ratio] -- Duplicate in-flight orders of the same building the bank
//   justifies: one extra copy per (its cost x this) of banked metal.
const float TUNE_DUP_BANK = 1.f;

// Build energy while income < pull * this.
const float TUNE_ENERGY_HEADROOM = 1.35f;

// [toggle 0/1] -- THE ECONOMY-ONLY ETA OBJECTIVE. 0 changes nothing; 1 lets the
//   ETA re-rank wants WITHIN the four economic categories. See docs/27.
const float TUNE_ETA = 1.f;

// [switch] -- economy-only benchmark: no army products, no defence, AA or
//   superweapon wants. For measuring how fast the economy alone scales against
//   an inactive opponent (apexearth's canon scenario, 2026-09-08). See docs/27.
const float TUNE_ECO_ONLY = 0.f;

// [toggle 0/1] -- The `apex: eta` shadow log with the ETA layer OFF. One line
//   costs a full ladder simulation per ranked want; on when apex_eta is.
const float TUNE_ETA_LOG = 0.f;

// [metal or metal/s] -- Energy per metal: the grid target follows METAL income
//   (energy.pull is throttled demand and self-reports "fine" while starving...
const float TUNE_E_PER_METAL = 20.f;

// [metal or metal/s] -- A fusion costs ~21,000 ENERGY to construct: starting
//   one on a small grid drains it -- the lathe plus a producing T2 lab stalls...
const float TUNE_FUSION_MIN_ENERGY = 1000.f;

// [energy/s] -- energy income below which winds and advanced solars are never
//   reclaimed (apexearth: ">2000 reclaim wind and advanced solar"); wind's cliff
//   additionally scales down on bad-wind maps.
const float TUNE_RECLAIM_GEN_E = 2000.f;

// [ratio] -- PADDING: a victim is only eligible while the grid AFTER eating it
//   still clears pull by this factor.
const float TUNE_RECLAIM_PAD = 1.5f;

// Income cliffs below which a generator tier is never eaten (apexearth
//   2026-08-15: solars ~500, wind/advsol ~2000, wind scaled...
const float TUNE_RECLAIM_SOLAR_E = 500.f;

// [metal/s] -- Metal income required before committing to T2 (techlead.as
//   RushReady, and the rear plant-siting rule reads the same knob). See docs/27.
const float TUNE_T2_METAL = 30.f;

// [energy/s] -- Energy income required before starting T2 (techlead.as
//   RushReady), and the lower bar once a reactor already stands.
const float TUNE_T2_ENERGY = 1200.f;

// [metal/s] -- NOT a T2 permission knob: the metal income from which the
//   energy-buildup lane starts enforcing its pre-T2 energy floor (building the
//   grid FOR T2, ahead of the decision itself).
const float TUNE_T2_ENERGY_FROM = 12.f;

// [energy/s] -- The lower T2 energy bar once a reactor already stands
//   (apex_t2_energy is the bar without one).
const float TUNE_T2_ENERGY_REACTOR = 400.f;

// ---------------------------------------------------------------------------
// Constructors, build power, nanos
// ---------------------------------------------------------------------------
// [toggle 0/1] -- The conservative stance (hold rather than attack while
//   behind) is allowed; 0 removes it.
const float TUNE_CONSERVATIVE_HOLD = 1.f;

// [curve] -- T1 constructor curve slope: cons wanted = A x ln(income) + B. At
//   A=4.6/B=-6.55 that is ~4 cons at 10 m/s, ~14 at 100. See docs/27.
const float TUNE_CON_LOG_T1_A = 4.6f;

// [curve] -- T1 constructor curve intercept -- see apex_con_log_t1_a.
const float TUNE_CON_LOG_T1_B = -6.55f;

// [curve] -- T2 constructor curve slope: cons wanted = A x ln(income) + B.
const float TUNE_CON_LOG_T2_A = 6.0f;

// [curve] -- T2 constructor curve intercept -- see apex_con_log_t2_a.
const float TUNE_CON_LOG_T2_B = -16.0f;

// [ratio] -- Outmassed reads true while enemy massing threat exceeds our team
//   army value times this; being outmassed suspends cheap-constructor growth.
const float TUNE_CON_OUTMASSED = 1.f;

// A PASSIVE read of the enemy licenses a bigger builder fleet.
const float TUNE_GREED_CONS = 1.7f;

// [metal] -- Workers allowed on one build site: one more per this much of the
//   building's cost -- past that another pair of hands beats opening the next
//   site less.
const float TUNE_SITE_COST_PER_WORKER = 300.f;

// Buildtime per worker -- the other arm of the site crew, taken as a MAX with
//   the cost arm so it only ever raises the cap. See docs/27.
const float TUNE_SITE_BT_PER_WORKER = 4700.f;

// ---------------------------------------------------------------------------
// Expansion — mexes, upgrades, claims
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Build phases (manager/factory/phase.as ComputePhase)
//
// BUILD_PHASE 0-7 gates WHICH one-off structures are allowed; it is recomputed
// every update from live state and never latched, so losing a fusion or a
// gantry drops the phase back down. Phases 3-4 and 6-7 are decided by tech
// (RushReady / owning an advanced plant / a gantry), not by these numbers.
// The army-vs-economy RATIO is a separate system -- see targets.as.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Factories, tech, quotas
// ---------------------------------------------------------------------------
// [ratio] -- The advanced air plant waits until army spend reaches this
//   fraction of its target share -- a luxury while the army is starved, unless
//   the enemy actually flies.
const float TUNE_EXTRA_PLANT_ARMY = 0.85f;

// [ratio] -- How deep the facqueue keeps each driven line, as a multiple of
//   the line's re-election gap, measured in that line's own build seconds. See
//   docs/27.
const float TUNE_FAC_QUEUE = 1.5f;

// [toggle 0/1] -- The Brain drives every factory line (quota-based orders,
//   factory.json bypassed); 0 returns the lines to stock CircuitAI.
const float TUNE_FAC_QUEUE_BRAIN = 1.f;

// [power] -- Attack quota set while the killing blow is on -- concentrate the
//   push, do not disperse. See docs/27.
const float TUNE_KILL_QUOTA = 300.f;

// [ratio] -- During a T1 commit, all-in push once our army is this multiple of
//   the enemy's massed value (wide hysteresis so fog wobble cannot flap it).
const float TUNE_T1_PUSH_EDGE = 1.2f;

// WIDE hysteresis, or it is not "all or nothing".
const float TUNE_T1_PUSH_OFF = 0.5f;

// [toggle 0/1] -- Hold the aggressive posture while still short of the T1 army
//   the advanced plant is gated on; closes itself once T2 exists.
const float TUNE_T2_ARMY_HOLD = 1.f;

// ---------------------------------------------------------------------------
// Military — stance, engagement, squads
// ---------------------------------------------------------------------------
// [influence] -- Enemy influence at our own base above which the base counts
//   as under attack (converter placement pauses).
const float TUNE_BASE_ATTACK_INFL = 10.f;

// [ratio] -- How hard bleeding forward (dying on their ground) raises the
//   engage caution -- multiplies the same margin personality uses.
const float TUNE_BLEED_ENGAGE = 2.f;

// [ratio] -- How much enemy STATIC defence counts when deciding to leave home
//   (0 = ignore porc when judging their mobile mass; it still counts fully for
//   attacking into it).
const float TUNE_FEED_STATIC_W = 0.f;

// [ratio] -- The forward-suppression lifts when our massed pool outweighs the
//   enemy actually defending the ground it stands on by this factor -- that is a
//   fight we are winning.
const float TUNE_LOCAL_EDGE = 1.3f;

// [toggle 0/1] -- Enable the local-edge exception above; 0 keeps the
//   suppression unconditional.
const float TUNE_LOCAL_EDGE_ON = 1.f;

// [elmos] -- What is actually defending the ground we stand on: enemy group
//   value within reach of the lane, not every enemy on the map.
const float TUNE_LOCAL_EDGE_R = 2200.f;

// [ratio] -- How hard loss pressure (army eaten faster than it eats back)
//   tilts the budget toward ARMY.
const float TUNE_LOSS_ARMY = 2.f;

// [ratio] -- Cap on the loss-pressure army tilt, so a massacre cannot starve
//   the economy that pays for the rebuild.
const float TUNE_LOSS_ARMY_CAP = 1.7f;

// [ratio] -- The ceiling scales with the floor: a flat MASS_CAP of 48 sits
//   BELOW the army-scaled floor past ~14k of standing army, which...
const float TUNE_MASS_CAP_MULT = 2.5f;

// [ratio] -- Commit partway toward the cap, NOT at the floor: expiring
//   straight to the floor sent a 20%-of-army group into the exact mass...
const float TUNE_MASS_COMMIT_FRAC = 0.5f;

// [power] -- Degenerate-case floor on the massing bar (~2 Pawns) for an army
//   of nearly nothing; the real size is the share of standing army.
const float TUNE_MASS_FLOOR = 5.f;

// [seconds] -- Bound the hold.
const float TUNE_MASS_HOLD_SECS = 240.f;  // 120 expired into under-strength commits ('committing at 29'); patient pools trade better

// [ratio] -- The massing floor is also bounded below by the biggest enemy
//   group we can see, times this -- a pool that cannot meet it does not go.
const float TUNE_MASS_MEET_FRAC = 1.3f;   // meet the biggest seen group with EDGE: 1.0 sent even fights that lost (K/D 0.43, easy ladder)

// [ratio] -- Feeding guard: while enemy mobile mass exceeds ours by this
//   factor (and no local edge), the pool holds instead of trickling into them.
const float TUNE_MASS_NO_COMMIT_RATIO = 2.f;

// [ratio] -- Massing bar as a share of our own standing army (metal to power);
//   0.012 is ~70% of the army per group -- one force that wins its fight, not
//   two that lose.
const float TUNE_MASS_PER_ARMY = 0.012f;

// [toggle 0/1] -- Sized against what the group can actually kill, not against
//   the enemy's whole army: comparing to their total army answers "can...
const float TUNE_MASS_VS_ARMY = 1.f;

// [ratio] -- While ahead, the massing bar also rises to this fraction of
//   per-ally enemy mobile threat.
const float TUNE_MASS_VS_ENEMY = 0.5f;

// [elmos/s] -- How fast an enemy group must be closing on the base to count as
//   an incoming push.
const float TUNE_INCOMING_CLOSING = 150.f;

// [metal] -- Minimum enemy group value to register as an incoming push.
const float TUNE_INCOMING_COST = 2500.f;

// [metal] -- An enemy group at least this expensive inside its own range (plus
//   pad) of our fence is the danger signal.
const float TUNE_INCOMING_DANGER_COST = 800.f;

// [elmos] -- Padding added to the enemy group's own weapon range when testing
//   whether it already threatens the base edge.
const float TUNE_INCOMING_DANGER_PAD = 500.f;

// [ratio] -- Team army advantage that KEEPS a running push alive (hysteresis
//   under apex_push_team_ratio, so one trade at the line does not flap it).
const float TUNE_PUSH_KEEP = 1.25f;

// [elmos] -- Radius around the base within which enemy groups are evaluated as
//   a possible incoming push.
const float TUNE_INCOMING_NOTICE_R = 4500.f;

// RAID_MIN_EARLY=45 was "hold them home" made permanent: ~2,600 metal of
//   raiders had to pool before ONE raid could leave pre-T2,...
const float TUNE_RAID_PACK = 8.f;

// [ratio] -- Raid packs grow with the economy: pack power is the base plus
//   income times this, so packs form instead of never reaching a fixed bar.
const float TUNE_RAID_PER_INCOME = 0.2f;

// RAID_ASK [0/1] -- 1 = the raid director ASKS for a raid: it finds enemy
//   ground nothing is holding, sizes a pack against what does hold it, and
//   pulls units out of their current tasks to make it. 0 = the stock pool
//   only, which waits for raiders to trickle in and merge. See docs/27.
const float TUNE_RAID_ASK = 1.f;

// [seconds] -- EXPERIMENT, default off. A no-retreat bar at units cheaper
//   than this many seconds of income measured army K/D 0.33 to 0.11 (retreat is
//   also disengage-and-repair).
const float TUNE_RETREAT_COST_SECS = 0.f;

// [toggle 0/1] -- Use the explicit siege latch for dig-in decisions; 0 falls
//   back to BaseContested.
const float TUNE_SIEGE = 0.f;

// [toggle 0/1] -- Stance (aggressive/passive) moves the budget shares; 0 lets
//   stance read but never act, for isolation A/Bs.
const float TUNE_STANCE = 1.f;

// [ratio] -- ARMY share multiplier while the stance is AGGRESSIVE (base being
//   hit or pressured).
const float TUNE_STANCE_AGGRO_ARMY = 0.75f;

// [ratio] -- DEFENCE share multiplier while AGGRESSIVE.
const float TUNE_STANCE_AGGRO_DEF = 1.3f;

// [ratio] -- ECONOMY share multiplier while AGGRESSIVE (below 1: guns before
//   growth while under attack).
const float TUNE_STANCE_AGGRO_ECO = 1.0f;

// [ratio] -- ARMY share multiplier while PASSIVE (enemy visibly quiet): greed
//   trims army to grow faster.
const float TUNE_STANCE_GREED_ARMY = 0.85f;

// [ratio] -- ECONOMY share multiplier while PASSIVE.
const float TUNE_STANCE_GREED_ECO = 1.3f;

// [pressure] -- Raid pressure above which the stance turns AGGRESSIVE even
//   without base contact.
const float TUNE_STANCE_PRESSURE = 1.2f;

// [ratio] -- 1v1 only: freshly seen enemy army above ours times this reads as
//   an aggressive rival (in teams, only threat to OUR ground counts).
const float TUNE_STANCE_RIVAL = 0.7f;

// SPLIT THRESHOLDS, or the boundary lives inside fog noise: one 60m game
//   flapped 47 times at a single 0.2 bar.
const float TUNE_STANCE_SEEN_HI = 0.25f;

// [ratio] -- Fresh enemy sighting below this fraction of the seen-peak reads
//   as their army having died off (exits PASSIVE).
const float TUNE_STANCE_SEEN_LO = 0.08f;

// [metal] -- Absolute floor on what counts as seeing the enemy army: passive
//   requires eyes on a SQUAD, not one scout flickering through LOS.
const float TUNE_STANCE_SEEN_MIN = 300.f;

// [metal] -- Mobile non-flying units at least this expensive get a super
//   escort (guards travel with them) even without the SUPER role.
const float TUNE_SUPER_COST = 7000.f;

// [toggle 0/1] -- Supers travel with an escort instead of stock's one solo
//   attack task each; 0 is the control arm.
const float TUNE_SUPER_GUARD = 1.f;

// [ratio] -- Held supers stop waiting for an army once they ARE this share of
//   our whole army value -- two titans by a hill are the army.
const float TUNE_SUPER_SELF_FRAC = 0.4f;

// [ratio] -- Kill/loss ratio below which we are trading badly enough to change
//   posture.
const float TUNE_TRADE_BAD = 0.6f;

// [seconds] -- Recent losses must be worth this many seconds of income before
//   the trade ratio is trusted at all.
const float TUNE_TRADE_VOL = 20.f;

// [toggle 0/1] -- ATTACK/RAID squads reform on the chokepoint behind our front
//   while the base is under attack and no killing blow is committed, instead of
//   continuing to roam; 0 disables the recall (they keep fighting wherever their
//   task sends them).
const float TUNE_RECALL_HOME = 1.f;

// [fraction 0-1] -- Only squads this far past our own territory
//   (ForwardFraction) are recalled -- units already fighting near home need no
//   order, they are already where they are needed. See docs/27.
const float TUNE_RECALL_HOME_FWD = 0.5f;

// [toggle 0/1] -- ForwardFraction takes its bearing from the REMEMBERED enemy
//   centre and its scale from the deepest separation seen, so enemies inside our
//   base cannot move the axis they are measured on; 0 restores the live-centroid
//   reading.
const float TUNE_FWD_STABLE = 1.f;

// [seconds] -- Half-life of that high-water separation, so a front that
//   genuinely moves is eventually re-normalised.
const float TUNE_FWD_SPAN_HALFLIFE = 300.f;

// [toggle 0/1] -- Units on clearly-lost ground pull back behind the nearest
//   fence tower; 0 disables the withdraw system.
const float TUNE_WITHDRAW = 1.f;

// [elmos] -- Radius in which allied power counts toward a unit's local odds
//   when judging whether to withdraw.
const float TUNE_WITHDRAW_ALLY_R = 600.f;

// [elmos] -- How far behind the sheltering tower (toward home) a withdrawing
//   unit stands.
const float TUNE_WITHDRAW_BEHIND = 220.f;

// [influence] -- Ground counts as clearly losing when net influence (ally
//   minus enemy) is below minus this.
const float TUNE_WITHDRAW_INFL = 1.f;

// Already behind the guns: nothing to do but fight.
const float TUNE_WITHDRAW_NEAR = 300.f;

// [ratio] -- Withdraw when local enemy threat exceeds our local strength times
//   this.
const float TUNE_WITHDRAW_ODDS = 1.5f;

// [seconds] -- A withdrawing unit's pull-back order is re-issued at most once
//   per this interval.
const float TUNE_WITHDRAW_REISSUE = 6.f;

// [seconds] -- How far back the local-trade ledger looks: combat deaths older
//   than this no longer say who is winning the spot.
const float TUNE_TRADE_WINDOW = 15.f;

// [ratio] -- The trade trigger: pull back when our combat metal dead nearby
//   exceeds theirs times this (0 disables via the floor).
const float TUNE_LOSING_TRADE = 3.f;

// [metal] -- Ignore the trade trigger until at least this much of OUR combat
//   metal died nearby -- one cheap death is noise, not a verdict.
const float TUNE_LOSING_FLOOR = 250.f;

// [toggle 0/1] -- Abort a losing ATTACK/RAID task outright so the squad
//   re-pools together. See docs/27.
const float TUNE_FIGHT_ABORT = 0.f;

// [ratio] -- metal-vs-metal army ratio (ours/theirs) at which the massed pool
//   starts attacking; 1.0 is true parity, below it we attack while slightly
//   behind.
const float TUNE_ATTACK_EDGE = 0.95f;

// [metal] -- units at or under this cost are fodder: exempt from massing,
//   always sent forward (their job is vision and pulled fire). See docs/27.
const float TUNE_FODDER_COST = 100.f;

// [ratio] -- killing blow: once OUR TEAM's army value is this multiple of
//   theirs, attack continuously and release any turtle -- even a partial
//   commitment outnumbers everything they field.
const float TUNE_KILL_EDGE = 1.8f;

// [fraction] -- The blow disarms below KILL_EDGE times this. See docs/27.
const float TUNE_KILL_OFF_FRAC = 0.35f;

// [seconds] -- killing blow: earliest the normal (non-T1-commit) gate may arm.
//   See docs/27.
const float TUNE_KILL_FROM = 900.f;

// [seconds] -- half-life of gSeenPeak, the largest enemy massing threat ever
//   seen at once. See docs/27.
const float TUNE_SEEN_HALFLIFE = 300.f;

// [toggle 0/1] -- evaluate the SPEND_* target curves against live income (1)
//   or against the frame-0 column (0). See docs/27.
const float TUNE_BUDGET_LIVE = 0.f;

// [metal] -- killing blow needs at least this much enemy army value on the
//   books; ratios off a tiny sample are noise.
const float TUNE_KILL_FLOOR = 20000.f;

// [ratio] -- enemy/our army ratio at or above which we stop attacking entirely
//   and let them come to the defences.
const float TUNE_MASS_HOLD_RATIO = 1.5f;

// [power] -- ceiling on the massing bar so "wait for a bigger group" cannot
//   postpone attacking forever.
const float TUNE_MASS_CAP = 48.f;

// [ratio] -- odds multiplier while the team push is on; 0.55 roughly halves
//   the surplus the engage test demands.
const float TUNE_PUSH_BOOST = 0.55f;

// [power] -- attack quota while pushing; keeps the push concentrated instead
//   of dribbling in.
const float TUNE_PUSH_QUOTA = 200.f;

// [metal] -- no team push below this much own army value; a "ratio" over two
//   scouts means nothing.
const float TUNE_PUSH_MIN_ARMY = 2500.f;

// [ratio] -- team army advantage that STARTS the all-in push. See docs/27.
const float TUNE_PUSH_TEAM_RATIO = 1.6f;

// [power] -- early-game floor for raiders held home on defence.
const float TUNE_RAID_MIN_EARLY = 45.f;

// [seconds] -- how long a raid stays "current" in the raid-pressure memory; a
//   raid is current, not history.
const float TUNE_RAID_TAU = 60.f;

// [ratio] -- how much enemy STATIC defence counts in the massing decision, per
//   metal. See docs/27.
const float TUNE_STATIC_DEFENSE_WEIGHT = 0.5f;

// [ratio] -- engage bias while an advanced plant is under construction; above
//   1 is cautious. See docs/27.
const float TUNE_T2_HOLD_BOOST = 1.60f;

// ---------------------------------------------------------------------------
// Defence, towers, AA, insurance
// ---------------------------------------------------------------------------
// [metal or metal/s] -- Antinukes and shield domes are INSURANCE: real once
//   the threat class exists, premature at eco-opening scale (apexearth...
const float TUNE_ANTINUKE_INCOME = 60.f;

// [light towers] -- MINIMUM PROTECTION PER MEX. Every site the defence auction
//   considers is priced against the wave that has actually arrived there, and a
//   mex nothing has attacked yet reads a wave of zero -- so it was skipped
//   outright, and the economy stayed naked until something came for it. See
//   docs/27.
const float TUNE_MEX_COVER_FLOOR = 0.5f;

// [metal] -- Fielded army value at which the mobile screen, not per-mex
//   towers, takes over answering leaks. See docs/27.
const float TUNE_LEAK_SCREEN_M = 800.f;

// [ratio] -- A choke-gate site's threat floor as a multiple of the arriving
//   wave: the gate keeps deepening until its cover OVERWHELMS the push, not
//   merely matches it ("Have an unusual amount of tower at some spots. See
//   docs/27.
const float TUNE_GATE_DEPTH = 2.f;

// [toggle 0/1] -- The teeth line: one wall piece per election across the
//   strongest defended gate's span, a step enemy-ward of the doorway ("slow them
//   down with some walls outside"). See docs/27.
const float TUNE_TEETH = 1.f;

// [ratio] -- HOW HARD A BUILDER PREFERS THE GROUND IT IS ALREADY STANDING ON.
//   See docs/27.
const float TUNE_DEF_SITE_WALK = 1.f;

// [toggle 0/1] -- COVER WHAT YOU JUST BUILT. The category draw is
//   proportional, not argmax, so a tower worth twice the mex beside it still
//   loses the roll about half the time -- which is what "we don't immediately
//   make the light tower" looks like from the outside (apexearth, twice). See
//   docs/27.
const float TUNE_COVER_PUSH = 1.f;

// [metal] -- Bombers join home-base defence only while seen enemy AA value is
//   below this -- against flak trucks they would just die.
const float TUNE_BOMB_DEFEND_AA = 1000.f;

// [toggle 0/1] -- Chargers (beeline supers) defend home instead of striking
//   while the base is being hit; 0 lets them keep charging.
const float TUNE_DEFEND_HOME = 1.f;

// [fraction 0-1] -- A DEFEND-task unit farther forward than this (on losing
//   ground) is recalled first -- it is in the wrong place by the task's own
//   meaning. See docs/27.
const float TUNE_DEFEND_LEASH = 0.55f;

// apex_hold_committed: units standing on ground the enemy's guns cover are
//   never given solo pull-out orders -- the split (half fights, half runs) loses
//   the fight twice. See docs/27.
const float TUNE_HOLD_COMMITTED = 1.f;

// [ratio] -- A tower's counted reach is capped at the light tower's range
//   times this, so one big gun cannot claim the whole line is covered.
const float TUNE_DEF_REACH_CAP = 6.0f;

// [seconds] -- How long a lost fence tower stays fresh in the loss memory;
//   positions that keep eating towers score higher for replacements.
const float TUNE_FENCE_LOSS_MEMORY = 180.f;

// [metal/s] -- Metal income from which one flak is always held around the
//   base, whatever the seen air threat.
const float TUNE_FLAK_FLOOR_INCOME = 60.f;

// [metal/s] -- One further baseline flak per this much income beyond the floor
//   bar.
const float TUNE_FLAK_PER = 60.f;

// [fraction 0-1] -- While trading badly, the army's staging anchor pulls back
//   to this fraction of the way from home toward the enemy.
const float TUNE_LANE_DEFENSIVE = 0.15f;

// [ratio] -- A guard tower is obsolete once the top gun costs more than this
//   times the tower and is affordable -- big guns cover that ground instead.
const float TUNE_PORC_OBSOLETE_RATIO = 7.f;

// [seconds] -- The top gun counts as affordable for the porc-obsolete test
//   when it costs at most this many seconds of income.
const float TUNE_PORC_OBSOLETE_SECS = 20.f;

// Shield metal we aim to have standing per metal of enemy bombardment -- the
//   plasma twin of AA_COVER_FRAC, and the term that stops dome-stacking without
//   a cap or a count. See docs/27.
const float TUNE_SHIELD_COVER_FRAC = 0.5f;

// SHIELD_URGENCY: multiplier on the bombardment arrival rate, the plasma twin
//   of AA_URGENCY. Replaces an undocumented literal x4. See docs/27.
const float TUNE_SHIELD_URGENCY = 1.f;

// [toggle 0/1] -- Stuck units get an unblock nudge (reclaim/move of what pins
//   them); 0 disables.
const float TUNE_UNBLOCK = 1.f;

// ---------------------------------------------------------------------------
// Nukes (manager/brain/nukes.as) -- restored 2026-08-24 with the pre-kill
// defaults from fcbabf2^. Per-entry meaning is documented at each call site.
// ---------------------------------------------------------------------------
const float TUNE_NUKE_DEF_WINDOW = 25.f;

const float TUNE_NUKE_PER_ANTI = 8.f;

const float TUNE_NUKE_VALUE_PER = 12000.f;

const float TUNE_ANTI_COVER = 2500.f;

const float TUNE_NUKE_ASSUME_ANTIS = 1.f;

const float TUNE_NUKE_DEF_BIAS = 2.f;

const float TUNE_NUKE_DEF_MINFWD = 0.05f;

const float TUNE_NUKE_ALLY_MAX = 0.f;

const float TUNE_NUKE_ASSUME_FROM = 30.f;

const float TUNE_NUKE_BASE_VALUE = 30000.f;

const float TUNE_NUKE_EMERGENCY = 5000.f;

const float TUNE_NUKE_MIN_VALUE = 10000.f;

const float TUNE_NUKE_MISSILE_COST = 1500.f;

const float TUNE_NUKE_PAYOFF = 3.f;

const float TUNE_NUKE_REPEAT_DECAY = 0.5f;

const float TUNE_NUKE_RESIGHT_R = 1600.f;

const float TUNE_NUKE_SPREAD = 450.f;

// ---------------------------------------------------------------------------
// Air eco-assassination (manager/air/state.as)
// ---------------------------------------------------------------------------
// [elmos] -- Radius around the enemy centroid sampled for how packed their
//   base is. See docs/27.
const float TUNE_AIR_CLUSTER_R = 900.f;

// [AA metal soaked per point of bomber health] -- Wing HEALTH is what absorbs
//   AA, so a 16,700 hp Dragon soaks 25x what a 670 hp Thunder does. See docs/27.
const float TUNE_AIR_AA_SOAK = 0.05f;

// [toggle 0/1] -- The strike sizes against the enemy AA census divided by
//   their base count (mirrored from our own team size): a raid overflies ONE
//   base and static AA cannot concentrate. See docs/27.
const float TUNE_AIR_AA_SPLIT = 1.f;

// [multiple] -- Expected damage a raid must return against its own metal
//   before it is worth mounting.
const float TUNE_AIR_PAYOFF = 1.5f;

// [seconds] -- How long after a strike launches before it is scored. See
//   docs/27.
const float TUNE_AIR_SETTLE_S = 90.f;

// [weight 0-1] -- How much one scored run moves the running estimate of a
//   bomber type's survival and delivered damage.
const float TUNE_AIR_OBS_W = 0.5f;

// ---------------------------------------------------------------------------
// Commander
// ---------------------------------------------------------------------------
// [toggle 0/1] -- All commander-specific safety rules apply; 0 hands the
//   commander to stock CBuilderManager.
const float TUNE_COMM_RULES = 1.f;

// [fraction of his own cost] -- Fielded enemy HEAVY+SUPER mass at this
//   fraction of the commander's value makes him cautious. See docs/27.
const float TUNE_COMM_HEAVY_FRAC = 0.5f;

// [multiple of his own cost] -- Post-T2, enemy mobile massing at this multiple
//   of his value makes him cautious.
const float TUNE_COMM_MASS_MULT = 2.f;

// [fraction 0-1] -- A cautious commander abandons work farther forward than
//   this fraction of the way to the enemy; standing there is the mistake, not
//   the contact after it.
const float TUNE_COMM_FWD_CAP = 0.25f;
const float TUNE_STUCK_SECS = 30.f;   // build task held, still, no progress -> re-elect

// [influence] -- Enemy influence at his tile (or on the ring, while cautious)
//   above which he leaves. See docs/27.
const float TUNE_COMM_FLEE_INFLUENCE = 0.01f;

// [elmos] -- While cautious he reads the WORST influence on a ring this size
//   around him, not just at his feet.
const float TUNE_COMM_FLEE_RING = 600.f;

// [fraction 0-1] -- Below this health he is steered directly away from the
//   enemy centroid instead of given a retreat task, because the retreat haven
//   can be the ground being overrun.
const float TUNE_COMM_FLEE_HP = 0.85f;

// ---------------------------------------------------------------------------
// Air
// ---------------------------------------------------------------------------
// [metal/s] -- One advanced air plant wanted per this much metal income (the
//   per-def curve still bounds it).
const float TUNE_ADV_AIR_INCOME = 150.f;

// [toggle 0/1] -- Non-lead players hold their aircraft at the plant until the
//   wave releases them together; 0 sends them out as built.
const float TUNE_AIR_HOME_WAVE = 1.f;

// [ratio] -- Enemy AA under this fraction of our own team army counts as
//   DOMINATED: the assassin's absolute AA ceiling waives and a standing abort
//   un-latches, so a beaten enemy's leftover flak cannot veto the one weapon
//   that targets the win condition. See docs/27.
const float TUNE_AIR_DOMINANCE_AA = 0.15f;

// [ratio] -- Enemy field army under this fraction of ours counts as gone for
//   the dominance waiver.
const float TUNE_AIR_DOMINANCE_ARMY = 0.2f;

// [metal/s] -- Metal income at which the first air plant becomes mandatory for
//   a player who is NOT the air lead (the lead builds at apex_intel_air_income,
//   25). See docs/27.
const float TUNE_AIR_MANDATORY_INCOME = 200.f;

// [toggle 0/1] -- Obsolete T1 fighters are recycled once T2 fighters produce;
//   0 keeps them.
const float TUNE_AIR_RECYCLE = 1.f;

// [toggle 0/1] -- Idle fighters spread out on patrol stations instead of
//   clumping at the plant; 0 disables stationing.
const float TUNE_AIR_SPREAD = 1.f;

// [elmos] -- A fighter already within this of its station is left alone --
//   re-ordering every pass keeps it permanently in transit.
const float TUNE_AIR_STATION_NEAR = 400.f;

// [metal/s] -- The elected air lead builds its first air plant from this
//   income -- earlier than everyone else, for the team's eyes.
const float TUNE_INTEL_AIR_INCOME = 25.f;

// [count] -- No intercept is launched with fewer fighters than this; a pair
//   feeding into flak is worse than waiting.
const float TUNE_INTERCEPT_MIN_FIGHTERS = 4.f;

// [ratio] -- One-shot bombers (Legion Martyr) get their wanted count scaled by
//   this -- they die on delivery, so a full bomber count overbuys.
const float TUNE_ONESHOT_BOMBER_SCALE = 0.4f;

// ---------------------------------------------------------------------------
// Nukes and superweapons
// ---------------------------------------------------------------------------
// [toggle 0/1] -- The sentinel: the brain checks its own concepts every 45s
//   and logs a verdict per check ("apex: thought <name> CONCERN ...");
//   observer-first, each enforcement earned separately. See docs/27.
const float TUNE_BRAIN_NUKE = 1.f;

// ---------------------------------------------------------------------------
// Scouting, intel, ghosts
// ---------------------------------------------------------------------------
// [metal] -- Enemy value that must actually be SEEN before the enemy-afloat
//   detector may trust the centroid at all.
const float TUNE_AFLOAT_SEEN = 500.f;

// [ratio] -- Weight of stale (ghost) enemy sightings against fresh ones in the
//   territory model.
const float TUNE_GHOST_WEIGHT = 0.5f;

// [ratio] -- Scout wants multiply by this while the stance reads UNKNOWN --
//   silence is a scouting demand, not safety.
const float TUNE_SCOUT_BLIND_MULT = 2.f;

// [ratio] -- The sanity ceiling: a GENEROUS multiple of the most we ever saw
//   at once, never the estimate itself -- limited sensor coverage...
const float TUNE_SEEN_CAP_MULT = 2.5f;

// WE CANNOT SEE THEM MOST OF THE TIME.
const float TUNE_UNSEEN_HOLD = 0.5f;

// [ratio] -- Pre-T2, an unseen enemy is assumed to field at least our own army
//   times this, so opening groups commit at real size instead of trickling.
const float TUNE_UNSEEN_PARITY = 1.2f;

// squad metal value above which it is owed a sensor escort. See docs/27.
const float TUNE_ESCORT_SQUAD_VALUE = 2000.f;

// ---------------------------------------------------------------------------
// Base layout and placement
// ---------------------------------------------------------------------------
// Against the ring's radius on THIS position's bearing.
const float TUNE_FRONT_BAND = 0.18f;

// [ratio] -- Width of the front band as a fraction of the territory radius
//   (floored at one influence-grid cell). See docs/27.
const float TUNE_FRONT_BAND_FRAC = 0.35f;

// [elmos] -- Step size of the staging anchor's walk back toward home while the
//   ground ahead is lost.
const float TUNE_LANE_BACK_STEP = 300.f;

// [toggle 0/1] -- THE ANCHOR MUST NOT STAND FORWARD OF OUR OWN GUNS.
const float TUNE_LANE_BEHIND_GUNS = 1.f;

// [fraction 0-1] -- How far from base toward the enemy the army's staging
//   anchor sits; higher stands the army further forward on the map.
const float TUNE_LANE_FORWARD = 0.35f;

// [elmos] -- The front must move this far before the army re-stages with it;
//   below that it is jitter (~two turret ranges).
const float TUNE_LANE_STICKY = 900.f;

// ---------------------------------------------------------------------------
// Diagnostics and switches
// ---------------------------------------------------------------------------
// [frames] -- Ceiling on a memoised proposer answer. Validity is the stamps of
//   its inputs; this bounds only the per-frame prices no stamp can reach.
//   45 = what the clock alone used to be. See docs/27.
const float TUNE_MEMO_TTL = 45.f;

// [microseconds] -- What one sim frame may spend assembling builder elections.
//   The election is sliced against this between proposers, so it bounds the
//   frame it is checked on. Lower = smaller hitch, slower orders. See docs/27.
const float TUNE_ELEC_FRAME_US = 8000.f;

// [toggle 0/1] -- The perf governor (lag-severity measures and its production
//   cuts) is active; read once at startup. Off by default -- the harness passes
//   apex_perf=1.
const float TUNE_PERF = 0.f;

// [toggle 0/1] -- WHY THE ARMY IS THERE, ON THE MAP: this is the anchor
//   FillFrontPos picks the regroup cluster from, so it is the single most...
const float TUNE_PING = 0.f;

// [toggle 0/1] -- Dump every available def's catalog row at init (one log line
//   per def, parsed by tools/check_catalog.py). See docs/27.
const float TUNE_CATALOG_DUMP = 0.f;

// [toggle 0/1] -- The `apex: decide` and `apex: exec` lines, one per election
//   and per execution. On: every harness tool parses them. See docs/27.
const float TUNE_DECIDE_LOG = 1.f;

// Replace with a spot-income binding.
const float TUNE_SPOT_M = 2.0f;

// PLANT_PIPE: the constructor pipeline's return in spot-streams. See docs/27.
const float TUNE_PLANT_PIPE = 2.0f;

// Income one production line is worth: apexearth 2026-08-23, "below 50 metal
//   per second you don't want multiple T1 labs even of varying types." The
//   marginal plant's gain is zero beyond 1 + income/this -- income-derived,
//   never a count.
const float TUNE_PLANT_INCOME_PER = 50.f;

// PIPE_LATENCY_H: the horizon against which a production pipeline's delivery
//   latency discounts (h/(h+latency)) -- the temporal-consistency law applied to
//   plants; what makes mex-solar-lab the emergent opening.
const float TUNE_PIPE_LATENCY_H = 60.f;

// Discount a tech want's deferred gain by the risk borne over its pipeline.
//   See docs/27.
const float TUNE_TECH_SURVIVAL = 1.f;

// The same survival discount on the ENERGY want, so a long-payback generator
//   (afus, fusion) is priced on the base it needs to still be standing. See
//   docs/27.
const float TUNE_ECO_SURVIVAL = 1.f;

// The siege prior: what share of our OWN total economy we assume the enemy has
//   converted into army and may be walking at us right now, seen or not. See
//   docs/27.
const float TUNE_SIEGE_PRIOR = 1.f;

// ARMY COMPOSITION TARGET, shares of army metal (apexearth 2026-08-24:
//   30/25/25/20; re-ruled 2026-08-29 to 28/20/35/17 -- "build up these guys
//   [snipers/hounds/arty] in unit numbers so our army can grow very powerful",
//   "Rocket bots, artillery. See docs/27.
const float TUNE_LINE_TANK = 0.28f;

const float TUNE_LINE_MID = 0.20f;

const float TUNE_LINE_REACH = 0.35f;

const float TUNE_LINE_DPS = 0.17f;

// [ratio] -- How hard the enemy's observed STATIC share of fielded metal bends
//   the reach target up (renormalized). See docs/27.
const float TUNE_LINE_ADAPT = 0.f;

// [ratio] -- The per-mex defence floor grows with the spot's forward fraction:
//   floor * (1 + fwd * this). See docs/27.
const float TUNE_MEX_EXPOSE = 1.5f;

// [forward fraction] -- An IDLE rezzer past this retires to the haven
//   regardless of the threat read (the sensor is the documented liar); working
//   rezzers are untouched.
const float TUNE_REZZER_FWD = 0.25f;

// [elmos] -- Pre-contact consolidation: a DEFEND unit within this of a tracked
//   incoming group compares local ally metal against the pack and falls back to
//   the rally BEFORE contact.
const float TUNE_CONSOLIDATE_R = 2000.f;

// [ratio] -- Local ally metal times this must meet the tracked pack's metal or
//   the defender consolidates; 1 = meet them at even strength or from behind the
//   guns.
const float TUNE_CONSOLIDATE_EDGE = 1.f;

// The defaults below reproduce the previous gCombat/costM ranking EXACTLY --
//   dps * sqrt(alpha) * hp / cost is what power^2/cost expands to -- so the
//   first deploy is a no-op and every later setting is a clean A/B against it.
const float TUNE_WORTH_DPS = 1.f;

const float TUNE_WORTH_ALPHA = 0.5f;

const float TUNE_WORTH_HP = 1.f;

const float TUNE_WORTH_RANGE = 0.f;

const float TUNE_WORTH_AOE = 0.f;

// COST IS A CHOICE OF LANCHESTER LAW. See docs/27.
const float TUNE_WORTH_COST = 1.f;

// 1 = print the exponents and field means once; 2 = also dump the ranked
//   field. See docs/27.
const float TUNE_WORTH_DIAG = 0.f;

// What a weapon's reach is worth when it CANNOT hit a moving target -- a slow
//   un-tracked rocket. See docs/27.
const float TUNE_AIM_MISS = 1.f;

// Judge each class axis against the field MEDIAN rather than its mean. See
//   docs/27.
const float TUNE_LINE_MEDIAN = 1.f;

// Read the tank and dps axes PER BODY rather than per metal (see LineAbs in
//   market/army.as). See docs/27.
const float TUNE_LINE_ABS = 1.f;

// Exponent on the range axis of the class argmax. See docs/27.
const float TUNE_LINE_RANGE_EXP = 1.f;

// How far above the field's REFERENCE an axis must stand for a unit to count
//   as that class rather than as middle.
const float TUNE_LINE_EDGE = 1.15f;

// [0/1] -- 1 = the factory draw runs among the LINE CLASS the team owes the
//   most metal to, instead of over every candidate weighted by apex_line_bite.
//   See docs/27.
const float TUNE_LINE_ALLOC = 0.f;

const float TUNE_LINE_BITE = 1.5f;

// How much ground-covered-per-metal is worth while the fleet is short of the
//   sites it must watch. See docs/27.
const float TUNE_COVER_WORTH = 1.5f;

// Discount a mex/upgrade's income stream by the share of it we expect to still
//   be collecting over the stake horizon. See docs/27.
const float TUNE_STREAM_SURVIVAL = 1.f;

// Rent a building pays for standing on DEFENDED ground: covering turrets'
//   metal spread over the area they cover, per cell of footprint. See docs/27.
const float TUNE_SPACE_RENT = 2.f;

// A gain is credited only for the share of this horizon it will actually be
//   collecting, so a build that delivers nothing for most of it is discounted
//   against the small compounding steps that deliver now. See docs/27.
const float TUNE_PAYBACK_H = 900.f;

// the option cost of tying capital up in an unfinished frame, as a multiple of
//   (cost x duration / payback horizon). See docs/27.
const float TUNE_LOCKUP = 0.5f;

// How much sharper the category draw gets for a COMMITMENT -- added to
//   apex_draw_sharp in proportion to the candidate's cost as a share of what the
//   economy can produce over the payback horizon. See docs/27.
const float TUNE_COMMIT_SHARP = 12.f;

// elmos one farm row runs before the next stacks behind it. See docs/27.
const float TUNE_FARM_ROW_W = 320.f;

// Matches the bank clause's horizon in BPGap; 0 disables the term.
const float TUNE_BP_BACKLOG_S = 60.f;

// Offer the spaced front posts (Military::FrontBuildSpots) to the defence
//   auction alongside mexes and big structures. See docs/27.
const float TUNE_FRONT_LINE = 1.f;

// Measure turret coverage on the ring the enemy can SHOOT FROM (their observed
//   weapon range), taking the weakest bearing, instead of asking only whether a
//   turret reaches the target itself. See docs/27.
const float TUNE_STANDOFF_COVER = 1.f;

// Let the commander fight while he still outclasses the field. See docs/27.
const float TUNE_COMM_FIGHT = 1.f;

// TECH_PIPE: discount on a tech plant's unlock demand. See docs/27.
const float TUNE_TECH_PIPE = 2.0f;

// E_RESPONSE: seconds for the market's own energy supply to answer a scarcity
//   spike (~one solar build); long builds earn the floor, not the spike.
const float TUNE_E_RESPONSE = 45.f;

// E_BILL_SHARE [toggle 0/1] -- WHILE E-STALLED, price a build's ENERGY bill by
//   the share of energy INCOME its own drain eats, instead of by how long the
//   build runs. See docs/27.
const float TUNE_E_BILL_SHARE = 1.f;

// STALL_SOLAR_E [energy/second] -- while HARD e-stalled below this income, the
//   energy want is restricted to generators that cost NO energy to build, i.e.
//   the basic solar (apexearth: "if we are e-stalling and we have less than 300
//   energy per second, MAKE A BASIC SOLAR"). See docs/27.
const float TUNE_STALL_SOLAR_E = 300.f;

// CHOSEN, not derived. Short on purpose (apexearth: "it pays off eventually
//   and that's fine -- by the time this stuff matters less we're on to fusions
//   and afus"): a long window credits the converter with a payback the economy
//   has already outgrown, which reads back as energy being worth more than it
//   is.
const float TUNE_CONV_HORIZON = 300.f;

// MODEL (flat until base-crowding senses drive it): what makes dense energy
//   beat a field of solars at equal payback.
const float TUNE_SPACE_M = 1.0f;

// BP_HEADROOM: lathe capacity target as a fraction of income (slightly above 1
//   so the bank drains instead of pooling) -- the closed loop's one constant, a
//   headroom fraction, never a count.
const float TUNE_BP_HEADROOM = 1.0f;

// ASSIST_SHARE: fraction of the standing lathe fleet expected to fold onto a
//   priced build (Requests::Take joins same-def askers).
const float TUNE_ASSIST_SHARE = 0.5f;

// E_STALL_BOOST: multiplier on the conversion-floor E price per unit of
//   pull-above-income (a stall doubles-to-triples what new E is worth).
const float TUNE_E_STALL_BOOST = 2.0f;

// BP_LOOKAHEAD: seconds of income GROWTH folded into the BP target -- the
//   compounding term; a flat economy adds nothing.
const float TUNE_BP_LOOKAHEAD = 60.f;

// FLY_SHORT: an air con's effective travel fraction vs the ground path --
//   straight line, no blockage, no pathfinding.
const float TUNE_FLY_SHORT = 0.6f;

// FARM_BACK: how far behind the base anchor the eco farm is planned, elmos
//   (the axis points at the front, so behind = away from threat/influence).
const float TUNE_FARM_BACK = 500.f;

// E_LOOKAHEAD: seconds of energy-pull GROWTH folded into the scarcity price --
//   anticipation, so the solar starts before the bank empties.
const float TUNE_E_LOOKAHEAD = 30.f;

// E_HEADROOM: energy income target as a multiple of trending pull -- the
//   standing reserve that keeps the bank from ever being raced to zero. See
//   docs/27.
const float TUNE_E_HEADROOM = 1.75f;   // 1.5 still read 'not that great' in a watched war game

// CON_ESCORT: exposed constructors claim one army guard each (master).
const float TUNE_CON_ESCORT = 1.f;

// ESCORT_MAX_COST: only cheap T1 takes escort duty (apexearth) -- a Bull
//   guarding a con is a Bull missing from the line.
const float TUNE_ESCORT_MAX_COST = 120.f;

// ESCORT_SPEED: an escort must CATCH a raider or be a riot unit (apexearth:
//   "we want fast or tough units on escort, rocket bots die in a 1v1 vs a
//   pawn/grunt"). See docs/27.
const float TUNE_ESCORT_SPEED = 1.f;

// A spot is worth what it RAISES us by, not what it yields (apexearth: "when a
//   mex would double our income it is very important. See docs/27.
const float TUNE_MEX_GROWTH = 8.f;

// [toggle 0/1] -- Discount a generator by how much better a one any
//   constructor we own could build instead, so a worker restricted to the
//   inferior option prefers to spend its build power on the better one. See
//   docs/27.
const float TUNE_INFERIOR_DISCOUNT = 1.f;

const float TUNE_ENERGY_GROWTH = 8.f;

// E_REALIZE [toggle 0/1]: the overflow-aware half of the energy market --
//   generation priced by the share of it anything would actually use (real
//   demand at E_HEADROOM plus standing converter capacity), the converter want
//   reading the true remaining waste, and the same eco-compounding premium on
//   both halves of the generator/converter pair. See docs/27.
const float TUNE_E_REALIZE = 1.f;

// So an overflow makes a generator LOSE to the converter that realizes it, and
//   never makes it unbuildable (apexearth 2026-08-26; his standing ruling is
//   that the generator ladder never pauses on waste). See docs/27.
const float TUNE_E_WASTE_WORTH = 0.25f;

// M_REALIZE [toggle 0/1]: the metal twin of E_REALIZE -- extraction priced by
//   the share of its metal we could actually spend. DEFAULT OFF: inert where it
//   was measured and its premise is unproven. See docs/27.
const float TUNE_M_REALIZE = 0.f;

// The unspendable band keeps this share, because demand grows and the spot is
//   still ours when it does -- the same reason E_WASTE_WORTH is not zero.
const float TUNE_M_WASTE_WORTH = 0.25f;

// Spatial threat prior: 0 at our start box, 1 at theirs. See docs/27.
const float TUNE_THREAT_GRADIENT = 1.f;

// RANGE_WORTH: standing weight of weapon reach in unit selection (reach = free
//   damage before the answer), on top of the reactive outranging term.
const float TUNE_RANGE_WORTH = 2.f;

// LOS matters beyond the unit: every danger sense we have reads zero while
//   blind, and EnemyArmyCost can read 0 for a whole game.
const float TUNE_SPEED_WORTH = 0.5f;

const float TUNE_LOS_WORTH = 1.f;

// SCREEN_WORTH: the scout/screen axis in production.as -- sight and dash per
//   metal, read INSTEAD OF combat worth when it is the larger of the two, so a
//   unit that is a hopeless soldier can still be a good screen. See docs/27.
const float TUNE_SCREEN_WORTH = 0.2f;

// MEDIC_FRAC: standing rez/repair fleet as a fraction of army value per minute
//   (apexearth: "3 times more rezbots" -- was 0.04). See docs/27.
const float TUNE_MEDIC_FRAC = 0.12f;

// ECO_REAR_MARGIN: how much farther from the enemy than the #2 ally the
//   rear-most home must be to count as "obviously" rear (distance ratio).
const float TUNE_ECO_REAR_MARGIN = 1.15f;

// ECO_SAFE_R: front distance beyond which the rear specialist skips ground
//   defense entirely -- past any raid's reach, insurance is dead money.
const float TUNE_ECO_SAFE_R = 2500.f;

// RECLAIM_AGE_S: a con must be at least this old before the surplus reclaimer
//   may eat it -- younger is churn against our own buildtime.
const float TUNE_RECLAIM_AGE_S = 180.f;

// LINE_PULL: unserved line spend (m/s) a factory needs before it pulls a nano
//   away from the farm block -- two turrets' worth of hunger.
const float TUNE_LINE_PULL = 35.f;

// NANO_SINK_BANK: bank fraction of storage above which "not empty on metal"
//   holds and live build sites compete for nano placement by their crew drain.
const float TUNE_NANO_SINK_BANK = 0.1f;

// SQUAD_M: metal value of fielded army that deserves one mobile radar and one
//   mobile jammer in support (apexearth: "support squads which are ~2k metal
//   value or higher").
const float TUNE_SQUAD_M = 2000.f;

// INTEL_RATE: fraction of a squad's value per minute that its radar/jammer
//   pair is worth -- what prices support "just behind T2 cons".
const float TUNE_INTEL_RATE = 0.1f;

// WATER_PCT: minimum real water share of the map before amphib capability is
//   worth anything -- a tiny pond must not price Platypuses (his ~15%).
const float TUNE_WATER_PCT = 15.f;

// WATER_FIRST: MODEL. What land-locked metal is worth ON TOP of its own stream
//   while the water is still uncontested -- the denial half of taking it first
//   ("the earlier you get into the water the more likely you are to own it").
//   See docs/27.
const float TUNE_WATER_FIRST = 1.0f;

// BIG_E: E/s of generation that makes a def "fusion-tier" -- packs in the deep
//   rear, earns a nano ring (fusion ~1000, afus ~3000; advsol ~75 not).
const float TUNE_BIG_E = 500.f;

// NANO_SINK_M: build cost that makes a live frame a nano-worthy site.
const float TUNE_NANO_SINK_M = 1000.f;

// FUS_BACK: how deep behind the base anchor the first fusion founds.
const float TUNE_FUS_BACK = 700.f;

// USER FIELD-REPORT MULTIPLIERS on computed unit worth (apexearth: the
// stats cannot see projectile speed or accuracy -- "in terms of unit vs
// unit damage, snipers are much better than recluse spiders"). Applied to
// power-per-cost in the army market. Edit freely; 1.0 = trust the stats.
float UnitWorthMod(const string &in name)
{
	if (name == "armsnipe") return 1.6f;   // Sharpshooter: hitscan-grade accuracy
	if (name == "armsptk") return 0.6f;    // Recluse: slow arcing rockets miss
// Thor: behaviour.json's power 0.1 is a THREAT statement ("cause of its
// paralyzer weaponry" -- paralysis doesn't kill), but UnitCore inherits
// it via PowerMod as production worth, so the push experimental priced
// at a tenth of its stats. x10 cancels it to net 1.0: trust the stats.
	if (name == "armthor") return 10.f;
	return 1.f;
}
// AA_URGENCY: multiplier on the insurance rate for anti-air. See docs/27.
const float TUNE_AA_URGENCY = 1.f;

// AA metal we are aiming to have standing per metal of enemy air we have seen
//   (apexearth: "if the enemy rolls up with 100k metal worth of air. See
//   docs/27.
const float TUNE_AA_COVER_FRAC = 0.5f;

// ECO_AA_MULT: the share of the air census the rear eco specialist answers,
//   relative to an even split. See docs/27.
const float TUNE_ECO_AA_MULT = 1.5f;

// GIFT_ARMY: master switch for back-to-front army gifting. See docs/27.
const float TUNE_GIFT_ARMY = 0.f;

// FRONT_N: how many closest-to-enemy allies count as the front line and
//   receive the team's ground army (his read of this map: 2).
const float TUNE_FRONT_N = 2.f;

// JOIN_MIN_M: def cost above which a second builder JOINS the standing build
//   instead of opening a parallel copy (fusion-and-up territory).
const float TUNE_JOIN_MIN_M = 500.f;

// ECO_LEASH: work radius of the quiet rear's builders from home -- the safe
//   radius it prices everything else against.
const float TUNE_ECO_LEASH = 2500.f;

// ECO_CON_KEEP: land T1 cons the quiet rear always keeps -- nano turrets and
//   small works still need hands (his floor-of-3 number).
const float TUNE_ECO_CON_KEEP = 3.f;

// T2_CON_BASE / T2_CON_PER_M: how many cons able to build the game's best
//   extractor we always want standing -- BASE plus one per PER_M of metal income
//   (apexearth 2026-08-23: "1 T2 con + 1 per 25 metal . See docs/27.
const float TUNE_T2_CON_BASE = 1.f;

const float TUNE_T2_CON_PER_M = 25.f;

// [count] -- constructors of ANY TIER the line orders before the draw, the
//   plain "how many hands" floor. See docs/27.
const float TUNE_CON_BASE = 2.7f;

// [metal/s per extra constructor] --
const float TUNE_CON_PER_M = 44.f;

// LINE_FLOOR: a factory order must be worth at least this fraction of the
//   rolling executed-want value, unless metal is overflowing (idle is free).
const float TUNE_LINE_FLOOR = 0.25f;

// ECO_DANGER_M: enemy cost inside the safe radius that counts as "base close
//   to being under attack" -- two T1 raiders' worth (2 x ~110).
const float TUNE_ECO_DANGER_M = 250.f;

// ECO_REACH_FRAC: the quiet rear claims no spot whose enemy distance is under
//   this fraction of its own -- it expands sideways/back, never forward.
const float TUNE_ECO_REACH_FRAC = 0.7f;

// ECO_ARMY_MIN_M: quiet-rear army floor -- the cheapest gantry-tier assault;
// below it, army money is ladder money.
const float TUNE_ECO_ARMY_MIN_M = 1500.f;

// RECLAIM_AMORT: seconds a one-shot reclaim refund is spread over when it
//   competes with perpetual streams (the market's typical payback scale).
const float TUNE_RECLAIM_AMORT = 300.f;

// [multiplier] -- How much more a reclaim is worth in the hands of a dedicated
//   reclaimer (rezbot: builds nothing, so it has no expansion to be pulled off)
//   than in the hands of a constructor that could be claiming open ground
//   instead. See docs/27.
const float TUNE_RECLAIM_REZ_BIAS = 3.f;

// [share] -- How much of the metal nothing is spending one build site may
//   claim as nano demand. See docs/27.
const float TUNE_NANO_SITE_SHARE = 1.f;

// [count] -- Ranked metal spots offered to the engine per election before
//   extraction gives up for that tick. See docs/27.
const float TUNE_MEX_TRIES = 10.f;

// [multiplier] -- What the ROOM under an obsolete building is worth, as a
//   multiple of (base fill x metal per build cell x the building's own cells).
//   See docs/27.
const float TUNE_ROOM_WORTH = 1.f;

// MOBILE_BP_EFF: fraction of a mobile builder's workertime that is real
//   lathing rather than transit; nanos and other statics count at 1.0.
const float TUNE_MOBILE_BP_EFF = 0.6f;

// INSURE_RATE: protection value per metal of covered assets, per second -- the
//   one modeled risk quantity for eyes and turrets. See docs/27.
const float TUNE_INSURE_RATE = 0.0003f;   // was 5e-5: radar lost to marginal solars until assets were huge (watched)

// NUKE_RISK: the anti-nuke's own rate; higher, because an uncovered nuke is
//   total loss. See docs/27.
const float TUNE_NUKE_RISK = 0.0005f;

// TARGFAC_WANT: pinpointers wanted (apexearth 2026-08-23: "3 wanted max").
const float TUNE_TARGFAC_WANT = 3.f;

// ---------------------------------------------------------------------------
// Strategic structures -- manager/brain/market/want_super.as
// ---------------------------------------------------------------------------
// SUPER_WANT: master switch for the strategic want (gantry, nuke silo,
//   anti-nuke, long-range gun). See docs/27.
const float TUNE_SUPER_WANT = 1.f;

// SUPER_PUSH: 1 = an affordable strategic want skips the category lottery
//   rather than taking a proportional share of it. See docs/27.
const float TUNE_SUPER_PUSH = 1.f;

// SUPER_AFFORD_S [seconds] -- the whole affordability test: the bill (metal
//   plus energy at the conversion floor) must be smaller than what the economy
//   makes in this many seconds. See docs/27.
const float TUNE_SUPER_AFFORD_S = 60.f;

// SUPER_PER_INCOME [metal/s] -- income per additional anti-nuke; the offensive
//   classes (silo, long-range gun) space at twice this. See docs/27.
const float TUNE_SUPER_PER_INCOME = 150.f;

// SUPER_SHARE: the slice of total economic power the strategic market may
//   claim as a want's gain. See docs/27.
const float TUNE_SUPER_SHARE = 0.25f;

// SUPER_FLIGHT_PER [metal/s of overflow] -- one strategic frame may stand
//   half-built per this much structural overflow, on top of the base one. See
//   docs/27.
const float TUNE_SUPER_FLIGHT_PER = 140.f;

// COPY_OVERFLOW_M [metal/s] -- the wealth waiver: overflow above this lifts
//   the plant-copy ban and the one-advanced-plant-at-a-time serialization ("make
//   more nanos around our gantry and if we can't do that then make another
//   gantry"; "multiple adv air are ok if we are crazy wealthy").
const float TUNE_COPY_OVERFLOW_M = 140.f;

// BLAST_AISLE [elmos] -- gap between a BIG generator's own clusters, so one
//   death explosion cannot chain the whole farm ("better if only half our
//   economy blows up"). See docs/27.
const float TUNE_BLAST_AISLE = 500.f;

// CON_FEED_HEADROOM -- how many hands the production draw may price toward, as
//   a multiple of income/apex_request_drain (the hands income keeps fed). See
//   docs/27.
const float TUNE_CON_FEED_HEADROOM = 1.5f;

// UNIT_AFFORD_S [seconds of income] -- a mobile unit's bid fades as its cost
//   approaches this much income, dying at the full bill (mass first, T3 from
//   surplus -- the supers' 60s affordability bar applied to units). See docs/27.
const float TUNE_UNIT_AFFORD_S = 120.f;

// DEF_SETBACK [elmos] -- front defence sites step this far back from the
//   contested edge toward home, so the frame survives building; most tower
//   ranges (430+) still cover the edge it stepped back from.
const float TUNE_DEF_SETBACK = 250.f;

// SCOUT_OVER_S [seconds] -- one idle cheap air scout is sent across the enemy
//   position this often ("I don't see any scouts flying over their base"). See
//   docs/27.
const float TUNE_SCOUT_OVER_S = 45.f;

// RE-ARMED 2026-08-31 on his ask, with the mechanism replaced. See docs/27.
const float TUNE_ECO_ROLE = 1.f;

// GANTRY_AFFORD_S [seconds] -- the gantry's affordability horizon, over TEAM
//   income: one shared line the whole team's nanos man, so one team purse. See
//   docs/27.
const float TUNE_GANTRY_AFFORD_S = 100.f;

// GANTRY_INSURE: the gantry's capability-insurance gain as a share of team
//   income ("if the enemy comes at us with a Behemoth and we do not have one we
//   are in big trouble") -- the answer to enemy T3 is worth this even with no
//   army gap and no overflow on the books.
const float TUNE_GANTRY_INSURE = 0.5f;

// GANTRY_HOST_INC [metal/s] -- the proposing player's OWN income at which the
//   gantry gain is whole; below it the gain scales by (own/anchor)^2. See
//   docs/27.
const float TUNE_GANTRY_HOST_INC = 150.f;

// OFFENSE_DEF_FLOOR: the share of its gain an offensive super (silo, LRPC)
//   keeps at ZERO standing defence; the rest scales in with the defence target's
//   fill ("we consistently make Basilisk before T3 or even T2 defense"). See
//   docs/27.
const float TUNE_OFFENSE_DEF_FLOOR = 0.1f;

// ANTINUKE_R [elmos] -- an anti-nuke's assumed umbrella, for deciding whether
//   ground is already covered by one we own.
const float TUNE_ANTINUKE_R = 2000.f;

// OBSOLETE_RATIO: how many times better the best standing alternative must be
//   (per cell for generators, in power for defences) before a building is scrap
//   -- his "much better".
const float TUNE_OBSOLETE_RATIO = 4.f;

// EXPOSE_R: elmos from the core at which a structure counts fully exposed (a
//   walk away from where the army lives).
const float TUNE_EXPOSE_R = 1200.f;

// EXPOSED_LOSS_S: seconds over which a fully exposed, unguarded asset is
//   expected to be lost against a real opponent -- his "almost guaranteed". See
//   docs/27.
const float TUNE_EXPOSED_LOSS_S = 120.f;

// DEFAULT 0 -- the mechanism is wired but priced out. See docs/27.
const float TUNE_FRAME_RISK = 0.0f;

// DEF_TRADE: metal of enemy wave a standing turret is expected to stop, per
//   metal of its own cost. See docs/27.
const float TUNE_DEF_TRADE = 3.f;

// A defence is discounted by H/(H+buildSec), so a slow turret keeps only the
//   share of the threat window it will actually cover. See docs/27.
const float TUNE_DEF_TTD_H = 120.f;

// How often the protection field is rebuilt, in game seconds. See docs/27.
const float TUNE_PROTECT_FIELD_S = 2.f;

// How often the energy-stall answer re-asks which worker should drop what it
//   is doing. See docs/27.
const float TUNE_STALL_ANSWER_S = 1.f;

// Energy income above which the stall answer stops asking at all. See docs/27.
const float TUNE_STALL_ANSWER_MAX_E = 400.f;

// WHAT A BUILDING IS WORTH WHILE NOTHING GUARDS IT (apexearth: "give buildings
//   a ~20% reduced value when they are unprotected. See docs/27.
const float TUNE_UNPROT_DISCOUNT = 0.20f;

// A TURRET ONLY SHOOTS WHILE IT IS ALIVE. See docs/27.
const float TUNE_DEF_ALPHA_W = 1.f;

// ECO_RAID_TAU: seconds of memory in the structure-loss field. See docs/27.
const float TUNE_ECO_RAID_TAU = 180.f;

// THREAT_R: radius the enemy-mass prior is sampled over. See docs/27.
const float TUNE_THREAT_R = 900.f;

// STAKE_HORIZON_S: seconds of a mex's stream that count as the stake standing
//   on it. See docs/27.
const float TUNE_STAKE_HORIZON_S = 300.f;

// RISK_FLOOR: a flat hazard every asset carries whether or not anything has
//   been seen. 0 since 2026-09-11: the blind floor is the siege prior, a
//   mirror of our own army, so it is an output. See docs/27.
const float TUNE_RISK_FLOOR = 0.f;

// HZ_APPROACH [weight]: hazard floor from enemy formations WALKING at this
//   ground -- horizon/ETA, weighed by their metal against what defends it.
//   Measured (LOS-slaved) and a floor only, so it never fires where nothing
//   was seen. See docs/27.
const float TUNE_HZ_APPROACH = 0.f;

// ENEMY_PRIOR: pre-contact estimate of enemy army as a share of OUR total
//   value (symmetric start); the observed census replaces it once larger.
const float TUNE_ENEMY_PRIOR = 0.25f;   // 0.35 + a continuous line drained the bank into army (watched: out of metal)

// MATCH_RATIO: army fielded per metal of enemy army SEEN.
const float TUNE_MATCH_RATIO = 1.2f;

// ALLY_SHARE: 1 = scale the SEEN census in ArmyTarget by our income share of
//   the team (the census is side-wide; the answer is split by the roster). See
//   docs/27.
const float TUNE_ALLY_SHARE = 1.f;

// ARMY_FILL_S: seconds over which an army-value gap counts as a stream.
const float TUNE_ARMY_FILL_S = 180.f;   // the 120 compensation was fighting the Wait throttle, not the price; with the line continuous, 180 shares honestly

// REZ_HORIZON: seconds over which the army's REPAIR backlog is closed. New
//   wrecks are a measured rate (Military::WreckRateM) and need no horizon.
const float TUNE_REZ_HORIZON = 120.f;

// [ratio] -- Share of a rez bot's work rate it actually delivers (the rest is
//   walking between wrecks). See docs/27.
const float TUNE_REZ_UTIL = 0.35f;

// REZ_RICH_M [metal]: a corpse at least this rich is RESURRECTED whatever the
//   pre-AFUS eat-the-field doctrine says -- a unit for the rez cost ("we
//   shouldn't be reclaiming something like that", on a Vanguard corpse).
const float TUNE_REZ_RICH_M = 900.f;

// AA_MATCH: our AA value per metal of enemy air seen.
const float TUNE_AA_MATCH = 0.7f;

// RETREAT_COST_SCALE: metal at which a unit's retreat threshold reaches ~+0.33
//   over the floor (retreat = floor + cost/this, cap 0.5) -- cheap units fight
//   to the end, expensive ones preserve.
const float TUNE_RETREAT_COST_SCALE = 3000.f;

// RETREAT_FLOOR: the HP fraction where the cheapest unit starts to flee. See
//   docs/27.
const float TUNE_RETREAT_FLOOR = 0.08f;

// STAKE_WEIGHT: how strongly an army DEFICIT borrows urgency from the total
//   value at risk (expected loss = everything x defeat probability).
const float TUNE_STAKE_WEIGHT = 1.f;

// STATIC_GUARD: how much a metal of CORE static defense counts toward the army
//   when computing the stake -- under 1 because towers cannot chase.
const float TUNE_STATIC_GUARD = 0.7f;

// WAVE_MEET: metal of standing front turrets per metal of observed enemy
//   massing (both sides in metal -- the power conversion bought dozens).
const float TUNE_WAVE_MEET = 0.4f;

// [toggle 0/1] -- Draw the computed front line. Allies and spectators see
//   every map overlay below, so each ships off unless someone deliberately
//   turned it on.
const float TUNE_DRAW_FRONT = 0.f;

// [toggle 0/1] -- Draw the defense zone on the map: the inner ring is the C++
//   base-defence range (the army fights at any odds inside it), the outer ring
//   the incoming-push alarm radius. See docs/27.
const float TUNE_DRAW_DEFZONE = 0.f;

// [toggle 0/1] -- Draw the army's staging anchor and, when apex_medic_setback
//   is set, the medic station behind it plus the step between them. See docs/27.
const float TUNE_DRAW_LANE = 0.f;

// [toggle 0/1] -- Ping the heal post: the exact point CRetreatTask sends
//   wounded units to (front + apex_retreat_behind toward home). See docs/27.
const float TUNE_DRAW_HEAL = 0.f;

// ---------------------------------------------------------------------------
// Everything else
// ---------------------------------------------------------------------------
// [percent] -- On maps with at most this much land, a water-borne enemy
//   centroid may read as the enemy living afloat.
const float TUNE_AFLOAT_LAND_PCT = 85.f;

// Tight: the enemy's mass must sit ON the water's edge, not a screen from a
//   lake -- 900 bought shipyards against a land army...
const float TUNE_AFLOAT_NEAR = 350.f;

// [count] -- Consecutive positive reads before the enemy-afloat answer latches
//   -- one jittering centroid sample must not flip the reaction.
const float TUNE_AFLOAT_STREAK = 3.f;

// [metal] -- Seen enemy submarine value that reads as the enemy afloat
//   immediately, whatever the land fraction.
const float TUNE_AFLOAT_SUB_COST = 400.f;

// [seconds] -- Only ally tower losses fresher than this summon defence aid.
const float TUNE_AID_FRESH = 60.f;

// [metal] -- Minimum fresh ally loss value before defence aid moves.
const float TUNE_AID_MIN_LOSS = 300.f;

// AID_RESPOND [metal lost at an ally's hotspot] -- above this the staging lane
//   moves to that fight (clamped to contested ground). See docs/27.
const float TUNE_AID_RESPOND = 1000.f;

// [elmos] -- How far defence aid will travel; -1 follows the measured base
//   separation live (a fixed default would freeze before home is set).
const float TUNE_AID_REACH = -1.f;

// [toggle 0/1] -- Mobile artillery masses into the squad pool (long-range back
//   row, allied vision, kite/set-target) instead of soloing on CArtilleryTask,
//   which only elects static targets and walks in blind (weapon range exceeds
//   own sight for the whole family).
const float TUNE_ARTY_MASS = 1.f;

// [ratio] -- Threat-map multiplier on the Behemoth's def power, so squads
//   respect it; our own read stronger too (they are chargers and ignore the
//   margin anyway).
const float TUNE_BEHEMOTH_THREAT = 2.f;

// [ratio] -- Cap on the forward-bleed engage caution.
const float TUNE_BLEED_CAP = 1.6f;

// [toggle 0/1] -- The Brain's category budget scales wants by target-vs-actual
//   share; 0 turns budget shaping off.
const float TUNE_BUDGET = 1.f;

// [toggle 0/1] -- THE SAFE GROUND CLOSEST TO THE LINE: the FURTHEST workable
//   sample, not the first threatened one.
const float TUNE_BUILD_THREAT_BAR = 1.f;

// [toggle 0/1] -- T3 CHARGERS GO FOR THE BASE.
const float TUNE_CHARGER_STRIKE = 1.f;

// [toggle 0/1] -- Every gate of our held territory (choke with our side ours,
//   far side not) is a defence-site candidate, priced by what it shields; 0
//   keeps only the near-anchor choke.
const float TUNE_CHOKE_GATES = 1.f;

// [toggle 0/1] -- Every OPEN bearing of the closure ring (approach angles no
//   standing gun covers, map edges count as walls) offers a defence-site
//   candidate, so flanks and the rear are for sale at every angle; 0 leaves only
//   asset/gate/front candidates.
const float TUNE_DEF_RING = 1.f;

// [toggle 0/1] -- A defence site prices against the enemy's whole fielded army
//   (capped by the stake behind the site), not a per-site share of it: their
//   mass all takes one approach, and the rate term already says how often. See
//   docs/27.
const float TUNE_WAVE_CONC = 1.f;

// [toggle 0/1] -- Ground defence sites are slots along the WALL: the rim of
//   our own buildings plus a standoff, sampled at tower pitch so filled slots
//   form a contiguous line that grows with the base. See docs/27.
const float TUNE_WALL = 1.f;

// [fraction of light-tower range] -- How far outside the outermost building on
//   each bearing the wall stands, so the guns meet the approach before it
//   reaches what they guard.
const float TUNE_WALL_STANDOFF = 0.5f;

// [fraction of light-tower range] -- Arc spacing between wall slots. At or
//   below 2.0 adjacent light towers' fields overlap; lower is a denser wall.
const float TUNE_WALL_PITCH = 1.2f;

// [count] -- guns per wall CLUSTER. The wall's slots are grouped this many at
//   a time, tight enough to cover each other, with the saved space taken as a
//   gap before the next cluster. 1 restores the old even spread. See docs/27.
const float TUNE_WALL_CLUSTER = 3.f;
// [ratio of the pitch] -- how tightly a cluster's guns pack. See docs/27.
const float TUNE_WALL_CLUSTER_TIGHT = 0.5f;

// [ratio] -- Cap on how far one bearing's buildings can drag the wall, as a
//   multiple of the worth-weighted RMS radius of everything we own. See docs/27.
const float TUNE_WALL_REACH = 2.5f;

// [ratio] -- Share of the wall pull a slot DIRECTLY BEHIND the base keeps
//   (enemy-facing slots get the full pull, tapering by bearing). See docs/27.
const float TUNE_WALL_REAR = 0.08f;

// [ratio] -- The front LINE's pull relative to the ring: his completeness
//   ruling (a wall the enemy can walk around is useless) makes an extending
//   section worth more than a redundant deepening. See docs/27.
const float TUNE_WALL_LINE_W = 2.f;

// [fraction of tower reach] -- Asset guard sites stand this far enemy-ward of
//   the asset centroid, between the buildings and the approach; 0 sites the gun
//   amid the buildings.
const float TUNE_GUARD_FORWARD = 0.5f;

// [0/1] -- 1 = a WALL slot, whose gain is the def-independent unmet-target
//   pull, ranks candidate towers by cover per metal. See docs/27.
const float TUNE_WALL_EFFICIENT = 1.f;

const float TUNE_DEF_OUTRANGE = 1.f;

// [0/1] -- Cap a defence site's stake at the metal of attackers the candidate
//   turret can actually destroy over apex_exposed_loss_s. See docs/27.
const float TUNE_DEF_KILL_CAP = 1.f;

// [0/1] -- Price a turret's cover on its SURFACE DPS (linear) instead of the
//   engine's sqrt(dps)-compressed threat. See docs/27.
const float TUNE_DEF_DPS_LINEAR = 1.f;

// [ratio] -- A T1 tower's gain once our own advanced lab stands; 1 prices
//   tiers equally. See docs/27.
const float TUNE_T1_DEF_LATE = 0.02f;

// [fraction of radar radius] -- A gap must sit outside this share of every
//   standing radar's reach before a new mast is blocked; lower = more
//   overlapping radars, sturdier intel. See docs/27.
const float TUNE_RADAR_OVERLAP = 0.45f;

// [toggle 0/1] -- The base-defence ring follows the BUILT base (farthest
//   finished rear structure plus the pad) instead of the frozen map-diagonal
//   formula; 0 keeps the static C++ ring.
const float TUNE_DEFZONE_DYNAMIC = 1.f;

// [elmos] -- Padding added to the built extent when the dynamic ring is
//   applied (roughly two T1 tower ranges of approach ground).
const float TUNE_DEFZONE_PAD = 400.f;

// [metal/s] -- Above this income the front-defence want is recomputed every 5s
//   instead of every 1s -- rich games have more fence to walk.
const float TUNE_ELECT_RICH_INCOME = 150.f;

// [ratio] -- Minimum forward reach of a territory ray for it to yield a front
//   spot.
const float TUNE_FRONT_MIN_REACH = 0.5f;

// [toggle 0/1] -- NOTHING BEHIND US IS FRONT. 1 is the ESCAPE HATCH -- the
//   full ring, for a genuinely surrounded base. See docs/27.
const float TUNE_FRONT_REAR_ARC = 0.f;

// [toggle 0/1] -- Front spots are pulled back to the safe side of the
//   influence edge; 0 uses the raw edge.
const float TUNE_FRONT_SAFE_EDGE = 1.f;

// [fraction 0-1] -- How far back from the influence edge the front line is
//   drawn.
const float TUNE_FRONT_SETBACK = 0.12f;

// [toggle 0/1] -- A HOLD MUST NEVER STOP US DEFENDING OUR OWN GROUND.
const float TUNE_HOLD_RELEASE = 1.f;

// [metal] -- Minimum enemy air value over an ally's home before the team
//   intercept flies.
const float TUNE_INTERCEPT_MIN = 500.f;

// [elmos] -- Radius around each home in which enemy air value is measured for
//   the intercept decision.
const float TUNE_INTERCEPT_R = 1400.f;

// THE SEVERITY LADDER (apexearth: "keep cutting back until we've caught up"):
//   every window still under the bar climbs it, every...
const float TUNE_LAG_SPEED = 0.98f;

// [severity] -- How much lag severity rises per slow-speed sample; higher cuts
//   kick in at severity 1, 2 and 3.
const float TUNE_LAG_STEP = 0.34f;

// [ratio] -- Each personality trait (eco, def, army, t3, air, nuke, lrpc) is
//   rolled log-uniform in [1, 1+s] per instance -- up only, never below
//   neutral; 0 = every instance identical (the A/B arm). See docs/27.
const float TUNE_PERSONA_SPREAD = 0.35f;

// [metal/s] -- In-flight build requests allowed per this much metal income
//   (min 2) -- the governor on parallel sites.
const float TUNE_REQUEST_DRAIN = 7.0f;

// Assisters beyond a site's ETA-derived worker count fall back into the
//   auction instead of being held to completion. See docs/27.
const float TUNE_ASSIST_RELEASE = 1.f;

// Eco builds (energy, converter, mex, moho) keep this multiple of the
//   ETA-derived crew before the peeler calls them over-staffed -- income
//   finishing fast outranks a perfectly even build-power spread.
const float TUNE_PEEL_ECO_KEEP = 2.f;

// NANO_FED_S [seconds] -- a join is refused when standing-nano lathe alone
//   clears the site's remaining bill within the joiner's walk plus this many
//   seconds; the freed constructor founds a new frame instead (a nano can assist
//   a frame but never place one). See docs/27.
const float TUNE_NANO_FED_S = 15.f;

// how sharply the category draw follows value. See docs/27.
const float TUNE_DRAW_SHARP = 2.f;

// [ratio] -- share of the constructors that hold a ROLE (elect inside one
//   category until the split says otherwise); the rest stay open. 0 is off.
//   See docs/27.
const float TUNE_ROLE_SHARE = 0.5f;
// [seconds] -- how far back the split of need is averaged. See docs/27.
const float TUNE_ROLE_TAU = 120.f;

// [seconds] -- how far back the SPEND budget's realised share is averaged
//   (brain/budget.as). Lifetime totals compare a whole game against a
//   steady-state target, so the opening reads 100% build power. See docs/27.
const float TUNE_BUDGET_TAU = 240.f;

// [ratio] -- share of the rez fleet that serves as battlefield medics: they
//   stay with the army's staging anchor, repair the wounded during fights and
//   reclaim the aftermath there. See docs/27.
const float TUNE_MEDIC_SHARE = 0.4f;

// [elmos] -- how far around the staging anchor a medic looks for wounded
//   units, and how close it holds station.
const float TUNE_MEDIC_R = 1200.f;

// [elmos] -- how far BEHIND the lane a medic holds station. See docs/27.
const float TUNE_MEDIC_SETBACK = 0.f;

// [seconds] -- how long one hit keeps a rez bot retreating. See docs/27.
const float TUNE_REZ_FLEE_S = 20.f;

// [seconds] -- spacing on ONE bot's own wreck and resurrect scans. See
//   docs/27.
const float TUNE_REZ_SCAN_S = 1.f;

// [seconds] -- how much of the enemy's own walking counts as being in range
//   already: a rez bot backs away while the nearest enemy is still this long
//   short of its firing envelope, and refuses work inside it. See docs/27.
const float TUNE_REZ_REACT_S = 1.f;

// [0/1] -- 1 = raiders join the massing pool once our advanced lab stands and
//   fight as line army (the pre-2026-08-30 behaviour). See docs/27.
const float TUNE_RAIDER_MASSING = 0.f;

// [0/1] -- 1 = cheap RAIDER-role units are routed to solo scout tasks in spam
//   phase, spreading over unscouted clusters. See docs/27.
const float TUNE_SPAM_RAIDERS = 1.f;

const float TUNE_SPAM_SUICIDAL = 1.f;

// [seconds] -- A stuck unit already asked for unblocking is not re-asked for
//   this long.
const float TUNE_STUCK_RETRY = 120.f;

// [count] -- Lattice slots offered to the engine before a placement gives up
//   on growing a cluster and seeds a new one. See docs/27.
const float TUNE_SLOT_TRIES = 12.f;

// [toggle 0/1] -- A GROW slot must keep the cluster aisle to a foreign def,
//   not just avoid touching it. See docs/27.
const float TUNE_AISLE_GROW = 1.f;

// [count] -- How many of one def stand together before the next starts a fresh
//   cluster elsewhere, so the whole economy is not in one spot. See docs/27.
const float TUNE_CLUSTER_N = 16.f;

// [count] -- Rows of lattice the farm scan walks rearward before giving up.
//   See docs/27.
const float TUNE_FARM_ROWS = 28.f;

// [toggle 0/1] -- Reclaim one of our own economy buildings that is standing in
//   a lattice slot C++ could not place on. See docs/27.
const float TUNE_RECLAIM_BLOCKER = 0.f;

// [seconds] -- HOW MUCH STATIC DEFENCE WE MAY OWN, as seconds of total
//   economic power (EcoPowerM, metal/s incl. See docs/27.
// SUPERSEDED 2026-09-09 -- DefenceTarget is now the budget's defence row
//   times standing power. Kept so a config naming it still parses. See docs/27.
const float TUNE_DEF_ECO_S = 120.f;

// [toggle 0/1] -- THE NO-TURRET TEST (docs/24-how-units-fight.md): 1 proposes
//   no ground or AA turret at all, so radar and units are the whole defence. See
//   docs/27.
const float TUNE_DEF_OFF = 0.f;

// Personality moves it (Persona::Trait(T_ARMY)); this is the neutral baseline.
const float TUNE_ARMY_ECO_S = 66.f;

// The economy the rear specialist names before it spends anything on war, in
//   metal/s of economic power AT NO BONUS -- EcoRoleTargetM multiplies by the
//   game's own handicap, so 250 here is 500 in a +100% game. See docs/27.
const float TUNE_ECO_TARGET_BASE = 250.f;

// The same economy for an EIGHT-player team, where the rear seat is far enough
//   from the war to spend the whole early game on it. 2026-09-14: "just let
//   it go full military and normal behavior at 1k metal instead of 2k" --
//   500 x the +100% handicap is his 1k. See docs/27.
const float TUNE_ECO_TARGET_BASE_8 = 500.f;

// Economic power, at NO-BONUS scale, before the bomber raid is worth mounting
//   at all -- the game's handicap multiplies it, so 100 here is apexearth's "200
//   m/s" in a +100% game. See docs/27.
const float TUNE_AIR_ECO_BASE = 100.f;

// Weigh a production line by how much of the map its ARMY can move around in
//   (ai.DefMapCoverage, the engine's own per-movement-type partition). See
//   docs/27.
const float TUNE_LINE_TERRAIN = 1.f;

// How far IN FRONT of the squad's longest row a short-range row holds, elmos.
//   This number is the dive depth; 96 measured worse three ways. See docs/27.
const float TUNE_SCREEN_GAP = 200.f;

// The production half is divided by (1 + this * matesWithIt), so at 1.0 the
//   second team copy is worth half and the third a third. See docs/27.
const float TUNE_TEAM_LINE = 1.f;

// [toggle 0/1] -- A cover pool promotes to ATTACK like stock's massing pool, so
//   a full pool leaves and home keeps what is still filling. 0: the pool never
//   converts (the pre-2026-09-12 hold). See docs/27.
const float TUNE_COVER_LEAVES = 1.f;

// [toggle 0/1] -- No more metal is posted to cover than our share of the raider
//   metal they have fielded (the AA counter's answer law). 0: the coverage
//   need alone decides, which at scale never closed. See docs/27.
const float TUNE_COVER_BY_RAID = 1.f;

// [toggle 0/1] -- Weigh a production line, on its WHOLE price and in the tech
//   want, by its units (median army-per-metal) times the ground they can cross
//   (LineCoverage), against the best line of its class and tier. 0 restores
//   the old pricing: terrain on the production half only. Measured worse
//   2026-09-12 (docs/27); off until the line factor is strong enough to be
//   the decision rather than a 17% nudge under the plant's own cost.
const float TUNE_LINE_QUALITY = 0.f;

// A defence slot holds ONE building, so a tower beaten on BOTH reach and
//   killing power by a gun we can afford right now is not a cheaper option, it
//   is stranded metal (apexearth: "why build something that so quickly becomes
//   outdated?"). See docs/27.
const float TUNE_DEF_DOMINANCE = 1.f;

// Seconds of total economic power a defence building may cost and still count
//   as affordable -- the guard that stops a Pulsar we cannot pay for making
//   every tower obsolete and leaving us with nothing. See docs/27.
const float TUNE_DEF_AFFORD_S = 30.f;

// Seconds of economic power the converter burst may commit at once. See
//   docs/27.
const float TUNE_CONV_AFFORD_S = 30.f;

// [toggle 0/1] -- Count the energy draw of work already ORDERED into the pull
//   that prices energy. See docs/27.
const float TUNE_E_COMMITTED = 1.f;

// [toggle 0/1] -- Let a STALL open parallel energy sites, not only an
//   overflowing bank. See docs/27.
const float TUNE_E_PARALLEL = 0.f;

// [toggle 0/1] -- Discount a plant want by the plants of ANOTHER domain
//   already under construction. See docs/27.
const float TUNE_PLANT_INFLIGHT = 1.f;

// [seconds of economic power] -- The mex-cover QUEUE JUMP only fires once the
//   tower costs less than this many seconds of total economic power. See
//   docs/27.
const float TUNE_COVER_PUSH_S = 10.f;

// [multiplier] -- What a mex UPGRADE'S extra metal stream is worth, over its
//   honest arithmetic. See docs/27.
const float TUNE_MEXUP_BOOST = 1.f;

// [toggle 0/1] -- Price a DUPLICATE line's throughput against the cheaper way
//   to buy the same build power. See docs/27.
const float TUNE_DUP_BP_SUBST = 1.f;

// [multiplier] -- What a plant def we RECLAIMED ON PURPOSE prices at while the
//   window below runs. See docs/27.
const float TUNE_REPLANT_DISCOUNT = 0.15f;

// [seconds] -- How long the retirement memory above holds. See docs/27.
const float TUNE_REPLANT_WINDOW_S = 600.f;

// [ratio] -- How fast a unit's -- and a plant's PRODUCTION -- value fades as
//   the share of identified enemy metal above its own tier rises. See docs/27.
const float TUNE_FOE_TIER_FADE = 1.f;

// [ratio] -- The same fade against OUR OWN fielded tier: once a T2 lab or
//   gantry stands, lower-tier units lose 1/(1+this*tiersBelow) of their worth
//   ("in late game, aside from spam we should mostly only be putting our
//   resources into T3 units and advanced air"). See docs/27.
const float TUNE_OWN_TIER_FADE = 0.8f;

// [metal per unit of ally influence] -- What a teammate holding this ground is
//   worth as cover, in the same currency as our own towers. See docs/27.
const float TUNE_ALLY_COVER = 400.f;

// [ratio] -- Share of the SYMMETRIC enemy expectation that the defence target
//   assumes could arrive at our own base before anything has been seen. See
//   docs/27.
const float TUNE_DEF_PRIOR_SHARE = 0.35f;
