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
// failed, the ruling -- is in docs/tunables.md under the same
// TUNE_ name; "See docs/tunables.md" on an entry means there is more there. Where the
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
//   ETA re-rank wants WITHIN the four economic categories. See docs/tunables.md.
const float TUNE_ETA = 1.f;

// [switch] -- economy-only benchmark: no army products, no defence, AA or
//   superweapon wants. For measuring how fast the economy alone scales against
//   an inactive opponent (apexearth's canon scenario, 2026-09-08). See docs/tunables.md.
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
//   RushReady, and the rear plant-siting rule reads the same knob). See docs/tunables.md.
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
//   A=4.6/B=-6.55 that is ~4 cons at 10 m/s, ~14 at 100. See docs/tunables.md.
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
const float TUNE_SITE_COST_PER_WORKER = 215.8f;

// Buildtime per worker -- the other arm of the site crew, taken as a MAX with
//   the cost arm so it only ever raises the cap. See docs/tunables.md.
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
//   docs/tunables.md.
const float TUNE_FAC_QUEUE = 1.5f;

// [toggle 0/1] -- The Brain drives every factory line (quota-based orders,
//   factory.json bypassed); 0 returns the lines to stock CircuitAI.
const float TUNE_FAC_QUEUE_BRAIN = 1.f;

// [toggle 0/1] -- Hold the aggressive posture while still short of the T1 army
//   the advanced plant is gated on; closes itself once T2 exists.
const float TUNE_T2_ARMY_HOLD = 1.f;

// ---------------------------------------------------------------------------
// Military — stance, engagement, squads
// ---------------------------------------------------------------------------
// [toggle 0/1] -- Siege a fortification on purpose (nnsiege.as). Off until the
//   siege squad is fixed (his 10-14: search on the one-army code, siege off).
const float TUNE_SIEGE = 0.f;

// [toggle 0/1] -- One army: ground attack squads walk to and follow the main
//   army, which stages short of each new target (AttackTask ArmyStep). Off: the
//   search measured 4/41 on it vs 12/48 without (his 10-14: back to old code).
const float TUNE_ONE_ARMY = 0.f;

// [toggle 0/1] -- The economy hand: with two constructors or more, one always
//   holds the energy role (generators, converters) and is never released by the
//   draw's ticket share (roles.as EcoHandOn). His 10-14; A/B before default.
const float TUNE_ECO_HAND = 0.f;

// [toggle 0/1] -- One election per crew: a hand of the same def and crew side near a hand that
//   just ran the market takes its job or the next want of its list (crewelect.as). His 10-15.
const float TUNE_CREW_ELECT = 0.f;

// [toggle 0/1] -- AA counts what the whole side loses to aircraft, not only this
//   seat (deathledger.as TeamAirLossRate). His 10-14; A/B before default.
const float TUNE_TEAM_AIRLOSS = 1.f;

// [toggle 0/1] -- A policy network's output 0 plays each continuous head at the
//   rule's value (policy.as PnValueRule), not the log-middle of its range (aa
//   0.63x, gunp 0.45x, mass 1.22x). His 10-14; A/B before default.
const float TUNE_PN_RULE_CENTRE = 0.f;

// [toggle 0/1] -- A raid answer counts every unit that arrives before the raiders
//   clear our structures in their reach (raidanswer.as), not only units within one
//   building's lifetime of travel. His 10-14; A/B before default.
const float TUNE_RAID_ANSWER_REACH = 1.f;

// [toggle 0/1] -- Flank guards (flankguard.as): groups from the home pools stand
//   on stock GUARD tasks at the economy's approaches no tower covers. His 10-14;
//   A/B before default.
const float TUNE_FLANK_GUARD = 1.f;

// [toggle 0/1] -- Tower refill (protect_refill.as): a finished gun an enemy killed
//   is offered back on its gap, priced by the stake behind the breach at the
//   exposure window's rate while the loss is fresh, exempt from the in-flight
//   cap. His 10-14; A/B before default.
const float TUNE_DEF_REFILL = 1.f;

// [toggle 0/1] -- A basic hand's tower is outdated against the guns our ADVANCED
//   hands can build and afford, not only its own list: beaten on reach and kill
//   by one, it keeps that share of its price. His 10-14; A/B before default.
const float TUNE_DEF_TEAM_OBSOLETE = 1.f;

// [toggle 0/1] -- A lower plant's combat unit keeps the share of per-metal worth
//   the best unit of its role (AA, bomber, other) from a higher plant we own and
//   can afford delivers; the rest of its ticket defers to that line. His 10-15.
const float TUNE_LINE_OBSOLETE = 1.f;

// [toggle 0/1] -- Under measured lag every mobile unit a factory orders pays a slot
//   price (lag x team metal per body / (1 - team bodies / team maxunits)); its draw
//   weight keeps cost/(cost+price), the rest orders nothing. His 10-15.
const float TUNE_UNIT_UPKEEP = 1.f;

// [toggle 0/1] -- A rez bot is priced by the wreck stream it banks over its
//   expected life (fleet metal / the fleet's death rate), net of its cost,
//   instead of over the whole payback horizon. His 10-15.
const float TUNE_REZ_LIFE = 1.f;
const float TUNE_T2CON_UNLOCK = 1.f;     // an advanced con is priced by the mex upgrades it brings forward (UpgradeUnlockM), not the room
const float TUNE_UPGRADE_FIRST = 0.f;    // the oldest advanced hands UpgradeHandsWant licenses take the best upgrade, not guns (roles.as)
const float TUNE_MEXUP_HORIZON = 1.f;    // a mex upgrade's walk and build cost their share of apex_payback_h, not gain x seconds
const float TUNE_ECO_HORIZON = 1.f;     // energy and converters priced on the payback-horizon share, not gain x late seconds (his 10-15 eco seat: fusions at v=0.00)
const float TUNE_ASSIST_ECO = 1.f;       // an assist on an economy frame is priced at the frame's gain x the seconds this hand saves it (want_assist.as)
const float TUNE_WALK_FORGONE = 0.f;     // a builder's walk and build seconds cost its own BP at what the economy can feed per BP-second, not income / worker count (price.as BuilderRate)

// [toggle 0/1] -- A factory line's unserved spend counts the army's budget
//   shortfall (target share - actual share) x metal income, so nanos are bought
//   for the lines when the eco spends all the free flow (sites.as LineUnserved).
//   His 10-14; A/B before default.
const float TUNE_LINE_ARMY_GAP = 1.f;

// [toggle 0/1] -- Against T1 the commander takes any fight his estimate says he
//   ends above 0.2 of his health (comdecide.as ComBar). His 10-14; A/B first.
const float TUNE_COM_BOLD = 0.f;

// [toggle 0/1] -- A withdrawing commander steps back to the nearest ground the
//   threat no longer reaches, not the back of the base (comdecide.as
//   ComSafePoint). His 10-14; A/B first.
const float TUNE_COM_STEP = 1.f;

// [influence] -- Enemy influence at our own base above which the base counts
//   as under attack (converter placement pauses).
const float TUNE_BASE_ATTACK_INFL = 10.f;

// [ratio] -- How hard bleeding forward (dying on their ground) raises the
//   engage caution -- multiplies the engage margin.
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

// [seconds] -- Bound the hold. A pool commits when it reaches its want or a
//   killing blow opens, never on a clock: the expiry sent under-strength
//   pushes into the enemy's T2 wave ("committing at 78" of 110 wanted, then
//   the army halved in two minutes). See docs/tunables.md.
const float TUNE_MASS_HOLD_SECS = 100000.f;

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
//   only, which waits for raiders to trickle in and merge. See docs/tunables.md.
const float TUNE_RAID_ASK = 1.f;

// [seconds] -- EXPERIMENT, default off. A no-retreat bar at units cheaper
//   than this many seconds of income measured army K/D 0.33 to 0.11 (retreat is
//   also disengage-and-repair).
const float TUNE_RETREAT_COST_SECS = 0.f;

// [toggle 0/1] -- Stance (aggressive/passive) moves the budget shares; 0 lets
//   stance read but never act, for isolation A/Bs.
const float TUNE_STANCE = 1.f;

// [ratio] -- ARMY share multiplier while the stance is AGGRESSIVE (base being
//   hit or pressured).
const float TUNE_STANCE_AGGRO_ARMY = 1.0f;

// [ratio] -- DEFENCE share multiplier while AGGRESSIVE.
const float TUNE_STANCE_AGGRO_DEF = 1.0f;

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
//   order, they are already where they are needed. See docs/tunables.md.
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

// [flag] -- A unit standing within its own range of a mex spot we hold or could
//   claim ignores the influence and incoming-group withdrawals while the odds
//   are not against it; the outgunned, losing-trade, leash and base-attacked
//   pull-backs still apply. 0 restores the withdrawals. See docs/tunables.md.
const float TUNE_HOLD_MEX_GROUND = 0.f;

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
//   re-pools together. See docs/tunables.md.
const float TUNE_FIGHT_ABORT = 0.f;

// [ratio] -- metal-vs-metal army ratio (ours/theirs) at which the massed pool
//   starts attacking; 1.0 is true parity, below it we attack while slightly
//   behind.
const float TUNE_ATTACK_EDGE = 0.95f;

// [metal] -- units at or under this cost are fodder: exempt from massing,
//   always sent forward (their job is vision and pulled fire). See docs/tunables.md.
const float TUNE_FODDER_COST = 100.f;

// [seconds] -- half-life of gSeenPeak, the largest enemy massing threat ever
//   seen at once. See docs/tunables.md.
const float TUNE_SEEN_HALFLIFE = 300.f;

// [toggle 0/1] -- evaluate the SPEND_* target curves against live income (1)
//   or against the frame-0 column (0). See docs/tunables.md.
const float TUNE_BUDGET_LIVE = 0.f;

// [ratio] -- enemy/our army ratio at or above which we stop attacking entirely
//   and let them come to the defences.
const float TUNE_MASS_HOLD_RATIO = 1.5f;

// [power] -- ceiling on the massing bar so "wait for a bigger group" cannot
//   postpone attacking forever.
const float TUNE_MASS_CAP = 48.f;

// [power] -- early-game floor for raiders held home on defence.
const float TUNE_RAID_MIN_EARLY = 45.f;

// [seconds] -- how long a raid stays "current" in the raid-pressure memory; a
//   raid is current, not history.
const float TUNE_RAID_TAU = 60.f;

// [ratio] -- how much enemy STATIC defence counts in the massing decision, per
//   metal. See docs/tunables.md.
const float TUNE_STATIC_DEFENSE_WEIGHT = 0.5f;

// ---------------------------------------------------------------------------
// Defence, towers, AA, insurance
// ---------------------------------------------------------------------------
// [metal or metal/s] -- Antinukes and shield domes are INSURANCE: real once
//   the threat class exists, premature at eco-opening scale (apexearth...
const float TUNE_ANTINUKE_INCOME = 60.f;

// [light towers] -- MINIMUM PROTECTION PER MEX, per gun the spot earns
//   (MexGunsWanted): 1.0 is one light tower's cover per wanted gun. A mex
//   nothing has attacked yet reads a wave of zero and was skipped outright
//   until something came for it. See docs/tunables.md.
const float TUNE_MEX_COVER_FLOOR = 1.0f;

// [metal] -- Fielded army value at which the mobile screen, not per-mex
//   towers, takes over answering leaks. See docs/tunables.md.
const float TUNE_LEAK_SCREEN_M = 800.f;

// [ratio] -- A choke-gate site's threat floor as a multiple of the arriving
//   wave: the gate keeps deepening until its cover OVERWHELMS the push, not
//   merely matches it ("Have an unusual amount of tower at some spots. See
//   docs/tunables.md.
const float TUNE_GATE_DEPTH = 2.f;

// [toggle 0/1] -- The teeth line: one wall piece per election across the
//   strongest defended gate's span, a step enemy-ward of the doorway ("slow them
//   down with some walls outside"). See docs/tunables.md.
const float TUNE_TEETH = 0.f;   // his 10-14: "lets stop making walls, we make too many"

// [ratio] -- HOW HARD A BUILDER PREFERS THE GROUND IT IS ALREADY STANDING ON.
//   See docs/tunables.md.
const float TUNE_DEF_SITE_WALK = 1.f;

// [toggle 0/1] -- COVER WHAT YOU JUST BUILT. The category draw is
//   proportional, not argmax, so a tower worth twice the mex beside it still
//   loses the roll about half the time -- which is what "we don't immediately
//   make the light tower" looks like from the outside (apexearth, twice). See
//   docs/tunables.md.
const float TUNE_COVER_PUSH = 1.f;

// [metal] -- Bombers join home-base defence only while seen enemy AA value is
//   below this -- against flak trucks they would just die.
const float TUNE_BOMB_DEFEND_AA = 1000.f;

// [toggle 0/1] -- Chargers (beeline supers) defend home instead of striking
//   while the base is being hit; 0 lets them keep charging.
const float TUNE_DEFEND_HOME = 1.f;

// [fraction 0-1] -- A DEFEND-task unit farther forward than this (on losing
//   ground) is recalled first -- it is in the wrong place by the task's own
//   meaning. See docs/tunables.md.
const float TUNE_DEFEND_LEASH = 0.55f;

// apex_hold_committed: units standing on ground the enemy's guns cover are
//   never given solo pull-out orders -- the split (half fights, half runs) loses
//   the fight twice. See docs/tunables.md.
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

// Shield metal we aim to have standing per metal of enemy bombardment -- the
//   plasma twin of AA_COVER_FRAC, and the term that stops dome-stacking without
//   a cap or a count. See docs/tunables.md.
const float TUNE_SHIELD_COVER_FRAC = 0.5f;

// SHIELD_URGENCY: multiplier on the bombardment arrival rate, the plasma twin
//   of AA_URGENCY. Replaces an undocumented literal x4. See docs/tunables.md.
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
const float TUNE_LAG_RECLAIM = 1.f;   // [toggle 0/1] want_reclaim.as: an idle turret's reclaim wait falls with the lag ladder (hz / (1 + gLagSev))
const float TUNE_AIR_FINISH = 1.f;   // [toggle 0/1] nnair.as: the cadence launch waits for the wing that finishes the best cell
const float TUNE_NUKE_BLIND = 1.f;   // [toggle 0/1] nukes.as: no strike on ground believed spent (cost halved per strike since the last look, under apex_nuke_min_value)

const float TUNE_NUKE_RESIGHT_R = 1600.f;

const float TUNE_NUKE_SPREAD = 450.f;

// ---------------------------------------------------------------------------
// Air eco-assassination (manager/air/state.as)
// ---------------------------------------------------------------------------
// [elmos] -- Radius around the enemy centroid sampled for how packed their
//   base is. See docs/tunables.md.
const float TUNE_AIR_CLUSTER_R = 900.f;

// [AA metal soaked per point of bomber health] -- Wing HEALTH is what absorbs
//   AA, so a 16,700 hp Dragon soaks 25x what a 670 hp Thunder does. See docs/tunables.md.
const float TUNE_AIR_AA_SOAK = 0.05f;

// [toggle 0/1] -- The strike sizes against the enemy AA census divided by
//   their base count (mirrored from our own team size): a raid overflies ONE
//   base and static AA cannot concentrate. See docs/tunables.md.
const float TUNE_AIR_AA_SPLIT = 1.f;

// [multiple] -- Expected damage a raid must return against its own metal
//   before it is worth mounting.
const float TUNE_AIR_PAYOFF = 1.f;

// [seconds] -- How long after a strike launches before it is scored. See
//   docs/tunables.md.
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
//   fraction of the commander's value makes him cautious. See docs/tunables.md.
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
//   above which he leaves. See docs/tunables.md.
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
//   that targets the win condition. See docs/tunables.md.
const float TUNE_AIR_DOMINANCE_AA = 0.15f;

// [ratio] -- Enemy field army under this fraction of ours counts as gone for
//   the dominance waiver.
const float TUNE_AIR_DOMINANCE_ARMY = 0.2f;

// [metal/s] -- Metal income at which the first air plant becomes mandatory for
//   a player who is NOT the air lead (the lead builds at apex_intel_air_income,
//   25). See docs/tunables.md.
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

// 1 = held fighters guard every scout, radar plane and bomber sent out
//   (enough to match the route's air threat, never none); 0 = they fly alone.
//   See docs/tunables.md.
const float TUNE_AIR_COVER = 1.f;

// [ratio] -- One-shot bombers (Legion Martyr) get their wanted count scaled by
//   this -- they die on delivery, so a full bomber count overbuys.
const float TUNE_ONESHOT_BOMBER_SCALE = 0.4f;

// ---------------------------------------------------------------------------
// Nukes and superweapons
// ---------------------------------------------------------------------------
// [toggle 0/1] -- The sentinel: the brain checks its own concepts every 45s
//   and logs a verdict per check ("apex: thought <name> CONCERN ...");
//   observer-first, each enforcement earned separately. See docs/tunables.md.
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

// [ratio] -- Pre-T2, an unseen enemy is assumed to field at least our own army
//   times this, so opening groups commit at real size instead of trickling.
const float TUNE_UNSEEN_PARITY = 1.2f;

// squad metal value above which it is owed a sensor escort. See docs/tunables.md.
const float TUNE_ESCORT_SQUAD_VALUE = 2000.f;

// ---------------------------------------------------------------------------
// Base layout and placement
// ---------------------------------------------------------------------------
// Against the ring's radius on THIS position's bearing.
const float TUNE_FRONT_BAND = 0.18f;

// [ratio] -- Width of the front band as a fraction of the territory radius
//   (floored at one influence-grid cell). See docs/tunables.md.
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
//   45 = what the clock alone used to be. See docs/tunables.md.
const float TUNE_MEMO_TTL = 300.f;

// [microseconds] -- What one sim frame may spend assembling builder elections.
//   The election is sliced against this between proposers, so it bounds the
//   frame it is checked on. Lower = smaller hitch, slower orders. See docs/tunables.md.
const float TUNE_ELEC_FRAME_US = 8000.f;
const float TUNE_ELEC_AVG_US = 250.f;   // [us, 0 off] the average a frame may spend on builder elections; saved credit still pays a burst up to TUNE_ELEC_FRAME_US (decide.as ElecFrameRoll; 250 = 60% of the 417 us AI budget)
const float TUNE_ELEC_AVG_ADAPT = 1.f;   // [toggle 0/1] the average election budget binds only while the host is short of time (Perf::HostShort: the server lowered the speed, the game is below 1x, or catching up); 0 = always

// [toggle 0/1] -- The perf governor (lag-severity measures and its production
//   cuts) is active; read once at startup. Off by default -- the harness passes
//   apex_perf=1.
const float TUNE_PERF = 0.f;

// [toggle 0/1] -- WHY THE ARMY IS THERE, ON THE MAP: this is the anchor
//   FillFrontPos picks the regroup cluster from, so it is the single most...
const float TUNE_PING = 0.f;

// [toggle 0/1] -- Dump every available def's catalog row at init (one log line
//   per def, parsed by tools/check_catalog.py). See docs/tunables.md.
const float TUNE_CATALOG_DUMP = 0.f;

// [toggle 0/1] -- The `apex: decide` and `apex: exec` lines, one per election
//   and per execution. On: every harness tool parses them. See docs/tunables.md.
const float TUNE_DECIDE_LOG = 1.f;
const float TUNE_NN_RECORD = 0.f;   // [toggle 0/1] the `apex: nn` training record per election; the trainer reads only harness games, so a hosted game can set 0 (nnlog.as NnRecord)
const float TUNE_GIFT_STAKE = 0.f;   // [toggle 0/1] gift.as: a seat asks for gifted army only while its standing economy plus a living commander outweighs the gap it asks to cover (his 10-19)
const float TUNE_LAB_BEST = 0.f;   // [toggle 0/1] production.as: a lab builds its best-priced unit, not a value-weighted draw (his 10-19)
const float TUNE_ANTI_AT_ONCE = 6.f;   // [count] nukes one anti stops at once (his 10-19: "about 6"); the worst salvo / this = antis a target needs
const float TUNE_LAB_INHERIT = 1.f;   // [toggle 0/1] want_tech.as: the advanced lab's gain is its upgrades at their own prices, its time a horizon share (his 10-19)
const float TUNE_AIR_FEED_CAP = 1.f;   // [toggle 0/1] want_plant.as: an air plant's production yield is capped at the metal nothing spends, as a ground line's is (his 10-19)
const float TUNE_NANO_UPGRADE = 1.f;   // [toggle 0/1] want_reclaim.as: a patrolling nano turret in reach of a rising mex upgrade guards it (his 10-19)
const float TUNE_DRAW_BEST = 1.f;   // [toggle 0/1] decide.as CategoryDraw: a builder takes its best-priced want, not a category draw (the mex ladder stays)
const float TUNE_CREW_SPLIT = 1.f;   // [toggle 0/1] crew.as: the field crew and the home crew (his 10-01); 0 lets pricing alone send hands out
const float TUNE_LAB_RATE = 0.f;   // [toggle 0/1] production.as: a constructor bids its gain rate in the lab, the army's currency, not gain per metal

// [0..2] -- How strongly the value net reweights each builder decision
//   (nnlog.as): an option the net expects to do one spread better gets
//   exp(blend) times its market value. 0 = the net only watches. See docs/how-it-works.md.
const float TUNE_NN_BLEND = 1.f;

// [0..1] -- Chance per AI that it is a DISCOVERY explorer this game: every
//   decision head mixes a uniform share into its odds. See docs/how-it-works.md.
const float TUNE_NN_EXPLORE = 0.f;
const float TUNE_NN_PLAN_EXPLORE = 0.1f;   // [0..1] of explorers, the chance it also leads its team with one drawn strategy until our tier rises
const float TUNE_PLAN_EXPLORE = 0.f;
const float TUNE_NN_EXPLORE_TEAM = -1.f;   // [team] >= 0: that team is the explorer, the other plays normally (watched self-play)
const float TUNE_GUNP_RULE = 1.f;   // [0..4] the forced-gun head's rule value (protect_nn.as); A/B 10-10
const float TUNE_CON_RULE = 2.5f;   // [0.25..8] the constructor head's rule value (econet.as); docs/tunables.md
const float TUNE_PLAN_FORCE = -1.f;   // [plan] >= 0: every team plays that plan (0 NORMAL 1 T3 2 MISSILE 3 ARTY 4 MASS); an A/B instrument
const float TUNE_TEAM_ARMY = 1.f;    // [plan] 0: no team-army operation (A/B instrument for the 10-11 team army)

// [0..2] -- How strongly constructors lean toward what BARb would build in our
//   situation (tools/imitate.py prior, NNI_*): an option of the class BARb
//   favours gets exp(imitate x log-odds) of its value. 0 = off. See docs/how-it-works.md.
const float TUNE_NN_IMITATE = 0.f;

// [toggle 0/1] -- Raiders go where the raid price (military/nnraid.as) says, as a
//   recorded WAIT/GO decision a raid net refines; 0 restores the stock raid
//   pools and the old ask director. A/B switch until judged.
const float TUNE_NNRAID = 1.f;

// Replace with a spot-income binding.
const float TUNE_SPOT_M = 2.0f;

// PLANT_PIPE: the constructor pipeline's return in spot-streams. See docs/tunables.md.
const float TUNE_PLANT_PIPE = 2.0f;

// Income one production line is worth: apexearth 2026-08-23, "below 50 metal
//   per second you don't want multiple T1 labs even of varying types." The
//   marginal plant's gain is zero beyond 1 + income/this -- income-derived,
//   never a count.
const float TUNE_PLANT_INCOME_PER = 50.f;

// PIPE_LATENCY_H: the horizon against which a production pipeline's delivery
//   latency discounts (h/(h+latency)) -- the temporal-consistency law applied to
//   plants; what makes mex-solar-lab the emergent opening.
const float TUNE_PIPE_LATENCY_H = 78.1f;

// Discount a tech want's deferred gain by the risk borne over its pipeline.
//   See docs/tunables.md.
const float TUNE_TECH_SURVIVAL = 1.f;

// The same survival discount on the ENERGY want, so a long-payback generator
//   (afus, fusion) is priced on the base it needs to still be standing. See
//   docs/tunables.md.
const float TUNE_ECO_SURVIVAL = 1.f;

// The siege prior: what share of our OWN total economy we assume the enemy has
//   converted into army and may be walking at us right now, seen or not. See
//   docs/tunables.md.
const float TUNE_SIEGE_PRIOR = 1.f;

// ARMY COMPOSITION TARGET, shares of army metal (apexearth 2026-08-24:
//   30/25/25/20; re-ruled 2026-08-29 to 28/20/35/17 -- "build up these guys
//   [snipers/hounds/arty] in unit numbers so our army can grow very powerful",
//   "Rocket bots, artillery. See docs/tunables.md.
const float TUNE_LINE_TANK = 0.28f;

const float TUNE_LINE_MID = 0.20f;

const float TUNE_LINE_REACH = 0.35f;

const float TUNE_LINE_DPS = 0.17f;

// [ratio] -- How hard the enemy's observed STATIC share of fielded metal bends
//   the reach target up (renormalized). See docs/tunables.md.
const float TUNE_LINE_ADAPT = 0.f;

// [guns] -- Light towers a mex earns beyond its first, at the enemy's
//   doorstep (forward fraction 1); linear in between, one at home. See docs/tunables.md.
const float TUNE_MEX_GUARD_FAR = 3.f;

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

// [0/1] -- A fighter tasked while armed enemies engage where it stands defends that spot
//   until they are gone (C++ MakeTask), and a defender beside our structures does not
//   consolidate away from them.
const float TUNE_BIRTH_DEFEND = 1.f;
const float TUNE_AOE_VS_BLOB = 1.f;   // [toggle 0/1] factory prices ground splash units by the enemy units their shell catches in the ball they bring, and splash demand tracks their clumped army (his 2026-10-15)
const float TUNE_RUSH_AWARE = 1.f;   // [toggle 0/1] the army floor covers the enemy army that can walk in while our next tier is being paid for, and T2/T3 plants, the gantry and long energy builds are priced by the share of that rush we can hold (his 2026-10-15, small maps)
const float TUNE_SMALL_PRESSURE = 0.f;   // [toggle 0/1] where their army walks to us faster than it can outbuild our holding army: shorter payback horizon and up to 2x army target, the team's combined army decides whether the seats leave home together, the team operation contests their outer extractors, and outer extractors want fewer extra guns (his 2026-10-15, small maps)
const float TUNE_MAP_SHARE = 1.f;   // [toggle 0/1] while our team holds fewer extractor spots than its seat share of the map: army target x (1 + gap), the leave-home bar and the stance hold lean to attack, raids and the team operation go for their extractors on the ground between, and a free spot's mex is worth (1 + gap) more (his 2026-10-15)
const float TUNE_SMALL_HARD = 1.f;   // [toggle 0/1] where our pathfinder's walk to them is shorter than their time to outbuild our holding army: army floor covers their strength at arrival (seen army, their commanders, their likely extractor income x the walk), fast units priced by the income they can deny, raids and the team operation price their extractors by income denied for the rest of the horizon, the commander's lathe at the lab is army owed and his claims fear their unseen commander; mex pricing untouched (his 2026-10-16)
const float TUNE_COM_HOME = 0.f;   // [toggle 0/1] the commander's jobs away from a recruiting lab pay contact k x army gap x his lathe for the time they keep him away, and the lab guard earns it; his fight estimate stops crediting D-gun kills on commanders and lets a lone foe keep full fire; their commanders count as ground army at our base, which he defends while k x the stake there outweighs his expected death; his D-gun walk-in in peace prices the seen guns and unseen commanders where it goes (his 2026-10-16, small maps)
const float TUNE_TEAM_AIR = 0.f;   // [toggle 0/1] the team leader prices the AIR plan against NORMAL every 30 s (square-law ground fight with and without the hold's army spend, plus one air sortie through the AA we have seen); under AIR every seat builds an air plant, bombers and gunships priced on the team target's shortfall, fighters only against seen fighters, holds them at one rally behind our lines, and all launch together when the gathered wing finishes the target; the scored strikes reprice the plan (his 2026-10-16)
const float TUNE_BUDGET_HOLD = 1.f;   // [toggle 0/1] while army is under its budget share, the orders that skip the budget's draw price -- constructor floors, priced builders at the lab, and the hoisted nano, defence and defence-assist wants -- keep budget mult(row)/mult(army) of their odds or value when their row is over its share (his 2026-10-16, small maps)
const float TUNE_EARLY_BALL = 1.f;   // [toggle 0/1] on short contact (apex_small_hard's k) a fast cheap unit is priced by the enemy metal a ball of them razes before their production answers, the massing pool waits for that ball, units are priced by the ground they watch per metal until income saturates it, scouts stop counting as patrol, and an air scout is priced by the unseen enemy metal its sweep adds (his 2026-10-16)
const float TUNE_OPEN_RACE = 1.f;   // [toggle 0/1] (needs apex_small_hard) each con-floor order races a constructor's income to the horizon against the lab's best fighter's denial of their eco plus the hold it adds against their raiders, both timed from build, walk and feed share; a lab under an energy stall prices every unit by its feed share instead of ordering nothing; the budget hold counts ordered units; fight pools and escorts do not pursue a target fleeing faster than they close; on short contact a con is priced by the open spots it reaches before their cons (spotrace.as), a fighter's strength by the square law, and the team army and raiders contest their extractors, cons and raced spots at each target's local defence (his 2026-10-16)
const float TUNE_ECO_RETURN = 1.f;   // [toggle 0/1] mex, generator, converter and storage priced by metal returned per metal over the horizon at the energy actually available: a converter chews only energy no standing or ordered converter reaches, a generator counts only demand energy would unlock (a metal-bound ask is not energy demand), energy bills at no less than the conversion floor; small_hard's k, the rush floor, the map-share army nudge and the budget's army row scale by the threat arriving (their army on our edge, raids on our economy) or our odds of killing them (2026-10-16, large-map scaling)
const float TUNE_EXPAND_FAR = 1.f;   // [toggle 0/1] (C++ apex_expand_far too) a mex claim is worth its spot's income x P(we hold it) -- P(open) = their arrival over theirs plus ours, 0 under a seen enemy extractor, x (1 - the road's heat share) -- against the walk and the hand; hot spots, hot roads and death walks are priced instead of refused, a dead task's claim frees its spot at once, the extractor def is never held after aborts, a walker lets go only when its road turns riskier than it was priced, a crewless claim is adopted only when it outscores the elected spot, and the DLL walks a mex task through a hot road (2026-10-16, large-map expansion stall)
const float TUNE_COM_FIGHT = 0.f;   // [toggle 0/1] every second each ground squad with an armed enemy in reach (army, commanders, towers that reach where it stands to fight) is fought out on paper, calibrated online by the team's real-over-predicted metal lost and killed: it fights while (loss - kill) is under what falling back abandons (our metal and open spots in the threat's reach, as much as the fight would hold them, plus the walk out and back), a verdict moving only past the measured error band; losing groups fall back onto one point against their largest group; attack groups out of contact walk onto their groups they beat by more than the band; raid packs and split-off packs go only at a size that wins at the target; a commander in our base pulls the base groups onto it when they win together (his 2026-10-16)
const float TUNE_SURF_DPS = 1.f;   // [toggle 0/1] (C++ apex_surf_dps too; needs the rebuilt DLL) every ground-combat valuation reads a unit's damage against the surface alone and every anti-air one its damage against aircraft, instead of the max over both, and the same for reach (land range vs air range), so an anti-air missile is no ground gun (armamph, his 2026-10-16)
const float TUNE_COUNTER_MIX = 0.f;   // [toggle 0/1] each ground army candidate's draw value is multiplied by its square-law fight value per metal against the enemy mobile army we have seen (splash on our clumped units, one-shot units do not engage, outranged units pay the closing time, a slower winner cannot catch), where it outruns a foe it cannot fight it keeps a raid value from their known economy less our raiders, and the army candidates are renormalised so army vs eco is unchanged (his 2026-10-16)
const float TUNE_FOCUS_FIRE = 0.f;   // [toggle 0/1] (C++ apex_focus_fire) a ground group in contact sets its targets together each second: the enemy whose death removes the most of their damage per second of our fire first (towers, commander, splash over our clump), in lethal doses among members in range, units it one-shots on the next; set-target only, nobody is moved; unarmed buildings after every armed enemy in reach; with apex_com_fight a group in contact keeps fighting until the estimate pulls it out (his 2026-10-16)
const float TUNE_AA_THREAT = 1.f;   // [toggle 0/1] anti-air where their air hurts us: places are ground where their armed air was seen over our buildings or killed something of ours; static AA goes to the place where it stops the most of that air's cost at its catalog exchange rate, mobile AA guards the army their air is killing and the lab makes one when that army is short; the AA panic ends only on AA finished or with hands on it; the anti-air budget row is the air share of their force or of our losses over that exchange rate (his 2026-10-16)
const float TUNE_GATHER = 0.f;   // [toggle 0/1] (also C++ apex_gather) raid packs keep the members they launched with: the raiders gathered at home and the pack in the field are priced apart, a GO launches the gathered group whole as a new pack, a pack sent home dissolves into the pools; their army counts at the target if it can arrive while we walk and work there; pools never walk out to a launched squad, an all-raider pool never promotes itself, a goal pack paths around what beats it; every squad's join window shuts when it launches -- attacks, raids, bomber waves, gunship wings, sieges -- and nothing joins it until it is home (his 2026-10-16)
const float TUNE_JOIN_ARRIVE = 0.f;   // [toggle 0/1] one test for every hand sent into work already under way (defence/unlock joins, priced assists and the idle floor, joins onto a big build, the commander rescue, army gifts to an ally, nano lifts): it counts only the seconds the job lands sooner after the hand arrives, given the hands already on it, times the job's worth, less the trip's risk; nothing joins work that finishes before it gets there or a crew already full; a rez bot goes only to a commander nobody is raising that will not rot first; a gift goes as one wave of units that reach the ally before its fight ends (his 2026-10-16)
const float TUNE_LAB_NANO = 1.f;   // [toggle 0/1] a nano turret at a lab is priced by the army metal per second it adds there, bounded by income / labs less the turrets already there (the nanos-first ratio as an output), run at the feed share a stalled economy gives it, instead of by spare metal only (his 2026-10-16)
const float TUNE_UNSTICK = 1.f;  // [toggle 0/1] ordered combat units that do not move are nudged to open ground, pen-tested, their wall self-destructed once the trapped metal's lost service exceeds it; nanos and converters keep ground plants' door lanes and never split open ground (his 2026-10-15)
const float TUNE_AIR_EVERY = 1.f;   // [toggle 0/1] every seat's air plant is priced by what it yields (air constructors' build power and spilled metal, its bombers' and gunships' net against the AA seen, fighters against their air, the look) instead of income bars on one seat; the held wing flies at the best cell the planes at home beat; fighters are bought against the enemy air seen and hunt it as whole flights (his 2026-10-16)
const float TUNE_UNIT_LIFE = 1.f;   // [toggle 0/1] a scout or support plane is worth the work over the life it is expected to have, read from our own losses of that def (the window as the prior life), not the whole window (329 scout planes, ~28 a minute dying, in a 1v1, 2026-10-17)
const float TUNE_NANO_EARLY = 1.f;   // [toggle 0/1] a T2/T3 plant under construction (its frame, or its manned order whose site has not moved) takes the nanos its finished plant would, at its own ground: a gantry's income-derived ring takes the batch, a T2 lab or air plant its floor of 4 (his 2026-10-17: "the nano turrets should get built while the gantry is being built too")
const float TUNE_FLOW_E_BILL = 1.f;   // [toggle 0/1] with metal spilling, a factory order still pays its energy bill out of its gain (the line floor read per E bill), so a near-worthless energy-heavy unit is not built just because the line would idle (2026-10-17: armpeep at gain 0.00 built ~28 a minute)
const float TUNE_GANTRY_OWN_SLOT = 1.f;   // [toggle 0/1] the gantry does not take or wait for the one-at-a-time strategic slot (a production line, not a gun) -- his 10-17 ruling: "let the gantry go up alongside them"
const float TUNE_T2_ECO = 0.f;   // [toggle 0/1] the next-tier rule also says NOW when the ETA ladder took the plant over the best economy rung (each such election counted at the plant's funded share, NOW at one whole), and the super push and next-tier hoist yield a ceiling hand to the upgrades its list offers, an anti-nuke against a seen silo excepted (his 2026-10-17: "focus on getting the fusions and upgrading the mexes")
const float TUNE_ADV_LAB_WAIT = 0.f;   // [toggle 0/1] no second advanced (T2) lab while one stands or is under way and any extractor we hold is below the best extraction; which comes first stays the market's (his 2026-10-17 ruling)
const float TUNE_INFLIGHT_HOLD = 1.f;   // [toggle 0/1] every build pays for the returns of the projects in progress it holds up, for the share of its metal free flow cannot pay (price.as displacedM; his 2026-10-18: every simultaneous build slows the ones in progress)
const float TUNE_INCOME_ACCEL = 1.f;   // [toggle 0/1] the hold's other half: an extractor, upgrade or converter is credited the share of income it adds times the gain of the projects in flight it speeds up (floor.as IncomeAccelM; his 2026-10-18)
const float TUNE_LAB_ASSIST = 1.f;   // [toggle 0/1] a lab's order is a priced project in flight (the hold charges for delaying it, the income credit counts it) and a guard on the lab is priced by the seconds it brings that order forward (want_assist.as LabAssistGuard; his 2026-10-18)
const float TUNE_SITE_CACHE = 1.f;   // [toggle 0/1] perf: LatheSite and SuperSite answers kept one memo lifetime while our building set holds (sites.as)
const float TUNE_CATCHUP_WALL = 1.f;   // [toggle 0/1] a host running faster than the game's speed is catching up behind the server: the election budget accrues per wall-clock frame, not per frame replayed (perf.as CatchingUp; his 2026-10-19)
const float TUNE_LATHE_CONCENTRATE = 0.f;   // [toggle 0/1] LatheSite takes the richest lathe whatever is rising there, not one build beside each block (sites.as; his 2026-10-18: concentrate on what is important; we waste a lot of room)
const float TUNE_FLUSH_PLACE = 1.f;   // [toggle 0/1] (C++ apex_flush_place; needs the rebuilt DLL) a farm build takes the nearest free site flush against an edge of one of our buildings before the lattice rings (BuilderTask.cpp; his 2026-10-18: "build up down left right off one of the existing types when you can")
const float TUNE_FLUSH_KIN = 0.f;   // [toggle 0/1] (C++ apex_flush_kin; needs the rebuilt DLL) the flush pass ranks a site beside the same def, then the same footprint, ahead of any building, each rank worth two of the building's footprints of distance (his 10-20: blocks of one kind)
const float TUNE_CON_USE = 0.f;   // [toggle 0/1] constructors sized by use: the con floors honour the idle ruling, a hand on the only job offered counts as idle, spot hands never exceed open spots (production.as; his 2026-10-18: con counts too high, walking all over)
const float TUNE_HOIST_WAITS = 1.f;   // [toggle 0/1] a hoist (floor, role, field, defjoin, metalfirst...) waits while the hand is still walking to a live job; the draw and the emergencies still move it (decide.as; his 2026-10-18: cons walk far, work 2 s, walk back)
const float TUNE_DRAW_WAITS = 0.f;   // [toggle 0/1] with TUNE_HOIST_WAITS: the draw also leaves a hand on a live job it is walking to unless the drawn job outbids its walk-paid value -- drawn once per job, not per election (decide.as; the cost of switching roles stand in for)
const float TUNE_RESERVE = 0.f;   // [toggle 0/1] holding back is an option: while the army is short and no metal is spare, a drawn job worth less than 1/fill leaves the metal to the factories and the hand lathes a producing one (want_assist.as ReserveWant; his 2026-10-18)
const float TUNE_UNLOCK_ONCE = 1.f;   // [toggle 0/1] a T2/T3 plant is the metal unlock (metal-first assists, MetalPathStarved) only if its units upgrade extractors and only until such a plant stands -- the extractor rule's sibling (register.as IsMetalUnlock; his 2026-10-18); and the tech market prices the unlock once: a second plant beside a standing or ordered kin gets no unlock value (want_tech.as)
const float TUNE_CON_PRICED = 0.f;   // [toggle 0/1] the con floors yield the lab to an army under its target share as measured, not under target / the con multiplier (production.as armyBehind; his 2026-10-18: a third of their army, the lab making cons). Floored to stand down entirely, a priced con never won: army gains are in gap metal, a con's in m/s
const float TUNE_MEMO_REPRICE = 1.f;   // [toggle 0/1] position-keyed memo answers are shared over a region four cells wide and their walk re-priced per asker (decide.as MemoServe; perf, his scav 8v8 at 3.9x the frame budget)
const float TUNE_REELECT_TTL = 1.f;   // [toggle 0/1] (C++ apex_reelect_ttl; needs the rebuilt DLL) a walking builder re-confirms its job no more often than the prices refresh (apex_memo_ttl), not every 3 s; with an enemy near it keeps 3 s (BuilderTask.cpp Reevaluate; perf)
const float TUNE_NANO_PRICED = 0.f;   // [toggle 0/1] the 2/4/9 nanos-per-plant floor (siting and hoist) stands down; nanos stand on their price -- build power added to what is in reach, at what the economy can feed (want_nano.as, decide.as; his 2026-10-18)
const float TUNE_ARMY_ONE_CURRENCY = 0.f;   // [toggle 0/1] a factory product's gain is the gap its own cost fills (min(cost, gap)/fill, m/s), not the whole gap's stream: army in the builder market's currency (production.as; his 2026-10-18 balance)
const float TUNE_UNIT_LIMIT = 0.f;   // [toggle 0/1] TEST ONLY: drop a want whose def is at its unit count limit (maxThisUnit, which folds a lobby restriction with behaviour.json's limit) -- for run_match --restrict-mex games; off in play because the JSON caps are BARb's, not ours (2026-10-17)
const float TUNE_HANDS_ONCE = 1.f;   // [toggle 0/1] a plant's build-power half is divided by the finished or manned plants of ANY domain that already make a builder of at least its builder's tier: an advanced air plant beside a T2 lab making T2 cons is bought for its planes, not as second hands (his 2026-10-17)
const float TUNE_COM_AIR = 1.f;   // [toggle 0/1] the commander counts strike air: when what reaches him kills him before our AA at him kills it, he builds an AA tower where he stands if it is up in time and turns it, else he retreats (his 2026-10-17)
const float TUNE_ALLY_AIR = 1.f;   // [toggle 0/1] an ally's interceptors fly to where their air is killing our things, not only to our home: each seat publishes its worst air-damage place (aathreat) beside the air over its home (his 2026-10-17: fighters used to protect allies; their gunships do tons of damage)
const float TUNE_AIR_ANSWER = 1.f;   // [toggle 0/1] fighters are bought against the strike raid that came over our ground (the most seen there at once, or a plane that killed ours, remembered over BLEED_TAU), not only the air in sight this second; an AA def's exchange rate counts the share of their firing positions it reaches (their stand-off reach against its own), what killed us joins the air it is priced against, a loss under standing AA raises that place's air to the cover plus the plane that got through, and a plant whose fighters are owed is not all-quiet (his 2026-10-17: bombed five minutes with no AA; fighters no longer protect allies)
const float TUNE_JAM_SIGHT = 1.f;   // [toggle 0/1] a force we cannot see is suspected where contacts dropped off our radar inside its coverage, where a jammer was seen, and where our things died to a shooter nobody saw; its metal enters the threat, hazard and trip reads, and sight over it (a camera tower at our edge facing it, a scout look) is priced by the loss it threatens (his 2026-10-17: players attack us with jammer-supported armies)
const float TUNE_ORDER_RELEASE = 1.f;   // [toggle 0/1] a build order the market elected someone to that now has no worker and no frame stops counting as coming: the lab, gantry and super lanes ask for its def again, the ask adopts it on the same ground or aborts it and founds afresh, and a lab order on ground the asker cannot work is founded afresh (2026-10-17: a T2 lab order sat five minutes with zero workers after its builder was pulled off)
const float TUNE_LIVE_NOT_BAN = 1.f;   // [toggle 0/1] a site judgement is read live or priced, never held on a clock: a dead tower's site priced by its killers still in reach, a footprint refusal blocks only footprints that hold it, the stuck watch marks only unreachable ground, abort streaks price one site not the def, a dropped mex upgrade lifts when its threat is gone (his 2026-10-16)

// The defaults below reproduce the previous gCombat/costM ranking EXACTLY --
//   dps * sqrt(alpha) * hp / cost is what power^2/cost expands to -- so the
//   first deploy is a no-op and every later setting is a clean A/B against it.
const float TUNE_WORTH_DPS = 1.f;

const float TUNE_WORTH_ALPHA = 0.5f;

const float TUNE_WORTH_HP = 1.f;

const float TUNE_WORTH_RANGE = 0.f;

const float TUNE_WORTH_AOE = 0.f;

// COST IS A CHOICE OF LANCHESTER LAW. See docs/tunables.md.
const float TUNE_WORTH_COST = 1.f;

// 1 = print the exponents and field means once; 2 = also dump the ranked
//   field. See docs/tunables.md.
const float TUNE_WORTH_DIAG = 0.f;

// 1 = a unit type's measured damage-dealt/health record discounts its price
//   (fodder and fighters exempt); 0 = record only. See docs/tunables.md.
const float TUNE_RECORD_BITE = 1.f;

// How hard a def scoring outside its line class's own spread, with no exchange
//   record of its own, is priced back toward that class. 0 = off. See docs/tunables.md.
const float TUNE_EVIDENCE_SHRINK = 0.f;

// What a weapon's reach is worth when it CANNOT hit a moving target -- a slow
//   un-tracked rocket. See docs/tunables.md.
const float TUNE_AIM_MISS = 1.f;

// Judge each class axis against the field MEDIAN rather than its mean. See
//   docs/tunables.md.
const float TUNE_LINE_MEDIAN = 1.f;

// Read the tank and dps axes PER BODY rather than per metal (see LineAbs in
//   market/army.as). See docs/tunables.md.
const float TUNE_LINE_ABS = 1.f;

// Exponent on the range axis of the class argmax. See docs/tunables.md.
const float TUNE_LINE_RANGE_EXP = 1.f;

// How far above the field's REFERENCE an axis must stand for a unit to count
//   as that class rather than as middle.
const float TUNE_LINE_EDGE = 1.15f;

// [0/1] -- 1 = the factory draw runs among the LINE CLASS the team owes the
//   most metal to, instead of over every candidate weighted by apex_line_bite.
//   See docs/tunables.md.
const float TUNE_LINE_ALLOC = 0.f;

const float TUNE_LINE_BITE = 1.5f;

// How much ground-covered-per-metal is worth while the fleet is short of the
//   sites it must watch. See docs/tunables.md.
const float TUNE_COVER_WORTH = 1.5f;

// Discount a mex/upgrade's income stream by the share of it we expect to still
//   be collecting over the stake horizon. See docs/tunables.md.
const float TUNE_STREAM_SURVIVAL = 1.f;

// Rent a building pays for standing on DEFENDED ground: covering turrets'
//   metal spread over the area they cover, per cell of footprint. See docs/tunables.md.
const float TUNE_SPACE_RENT = 2.f;

// A gain is credited only for the share of this horizon it will actually be
//   collecting, so a build that delivers nothing for most of it is discounted
//   against the small compounding steps that deliver now. See docs/tunables.md.
const float TUNE_PAYBACK_H = 900.f;

// the option cost of tying capital up in an unfinished frame, as a multiple of
//   (cost x duration / payback horizon). See docs/tunables.md.
const float TUNE_LOCKUP = 0.5f;

// [toggle 0/1] -- the late-start charge (gain x seconds before the asset pays)
//   counts the BUILD as well as the walk. See docs/tunables.md.
const float TUNE_LATE_BUILD = 1.f;

// How much sharper the category draw gets for a COMMITMENT -- added to
//   apex_draw_sharp in proportion to the candidate's cost as a share of what the
//   economy can produce over the payback horizon. See docs/tunables.md.
const float TUNE_COMMIT_SHARP = 12.f;

// elmos one farm row runs before the next stacks behind it. See docs/tunables.md.
const float TUNE_FARM_ROW_W = 320.f;

// Matches the bank clause's horizon in BPGap; 0 disables the term.
const float TUNE_BP_BACKLOG_S = 60.f;

// Offer the spaced front posts (Military::FrontBuildSpots) to the defence
//   auction alongside mexes and big structures. See docs/tunables.md.
const float TUNE_FRONT_LINE = 1.f;

// Measure turret coverage on the ring the enemy can SHOOT FROM (their observed
//   weapon range), taking the weakest bearing, instead of asking only whether a
//   turret reaches the target itself. See docs/tunables.md.
const float TUNE_STANDOFF_COVER = 1.f;

// Let the commander fight while he still outclasses the field. See docs/tunables.md.
const float TUNE_COMM_FIGHT = 1.f;

// TECH_PIPE: discount on a tech plant's unlock demand. See docs/tunables.md.
const float TUNE_TECH_PIPE = 2.0f;

// E_RESPONSE: seconds for the market's own energy supply to answer a scarcity
//   spike (~one solar build); long builds earn the floor, not the spike.
const float TUNE_E_RESPONSE = 45.f;

// E_BILL_SHARE [toggle 0/1] -- WHILE E-STALLED, price a build's ENERGY bill by
//   the share of energy INCOME its own drain eats, instead of by how long the
//   build runs. See docs/tunables.md.
const float TUNE_E_BILL_SHARE = 1.f;

// CHOSEN, not derived. Short on purpose (apexearth: "it pays off eventually
//   and that's fine -- by the time this stuff matters less we're on to fusions
//   and afus"): a long window credits the converter with a payback the economy
//   has already outgrown, which reads back as energy being worth more than it
//   is.
const float TUNE_CONV_HORIZON = 417.1f;

// MODEL (flat until base-crowding senses drive it): what makes dense energy
//   beat a field of solars at equal payback.
const float TUNE_SPACE_M = 1.0f;

// BP_HEADROOM: lathe capacity target as a fraction of income (slightly above 1
//   so the bank drains instead of pooling) -- the closed loop's one constant, a
//   headroom fraction, never a count.
const float TUNE_BP_HEADROOM = 1.0f;

// ASSIST_SHARE: fraction of the standing lathe fleet expected to fold onto a
//   priced build (Requests::Take joins same-def askers).
const float TUNE_ASSIST_SHARE = 0.3f;

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

// E_FEED_BOUND: 1 = the standing fleet's energy ask is bounded by the metal
//   feed that would actually run those hands, the same bound EPrice already
//   puts on the same fleet. 0 = the ask stands at full nominal speed (the
//   behaviour before 2026-09-22). Measured flat and left OFF; see docs/tunables.md.
const float TUNE_E_FEED_BOUND = 0.f;

// E_HEADROOM: energy income target as a multiple of trending pull -- the
//   standing reserve that keeps the bank from ever being raced to zero. See
//   docs/tunables.md.
const float TUNE_E_HEADROOM = 1.75f;   // 1.5 still read 'not that great' in a watched war game

// CON_ESCORT: exposed constructors claim one army guard each (master).
const float TUNE_CON_ESCORT = 1.f;

// STOCK_ARMY: 1 hands every combat unit (ground, air, AA) to stock BARb: its
// DefaultMakeTask and fight code; our army layers stand down. See docs/tunables.md.
const float TUNE_STOCK_ARMY = 1.f;

// OUR_AIR: 1 (with STOCK_ARMY 1) keeps aircraft under our air control; the ground army stays stock. See docs/tunables.md.
const float TUNE_OUR_AIR = 1.f;

// SQUADS: 1 (with STOCK_ARMY 1) hands the ground army to Army/Squad (military/army/). See docs/tunables.md.
const float TUNE_SQUADS = 0.f;

// ESCORT_MAX_COST: only cheap T1 takes escort duty (apexearth) -- a Bull
//   guarding a con is a Bull missing from the line.
const float TUNE_ESCORT_MAX_COST = 120.f;

// ESCORT_SPEED: an escort must CATCH a raider or be a riot unit (apexearth:
//   "we want fast or tough units on escort, rocket bots die in a 1v1 vs a
//   pawn/grunt"). See docs/tunables.md.
const float TUNE_ESCORT_SPEED = 1.f;

// A spot is worth what it RAISES us by, not what it yields (apexearth: "when a
//   mex would double our income it is very important. See docs/tunables.md.
const float TUNE_MEX_GROWTH = 6.f;

// [toggle 0/1] -- Discount a generator by how much better a one any
//   constructor we own could build instead, so a worker restricted to the
//   inferior option prefers to spend its build power on the better one. See
//   docs/tunables.md.

const float TUNE_ENERGY_GROWTH = 10.f;

// [toggle 0/1] DEFAULT OFF -- charge the energy growth premium above on the
//   share of the plan's own horizon a generator would actually be paying over,
//   so a reactor that lands after the target is due stops out-valuing one that
//   lands before it. See docs/tunables.md.
const float TUNE_ENERGY_GROWTH_ARRIVE = 0.f;

// E_REALIZE [toggle 0/1]: the overflow-aware half of the energy market --
//   generation priced by the share of it anything would actually use (real
//   demand at E_HEADROOM plus standing converter capacity), the converter want
//   reading the true remaining waste, and the same eco-compounding premium on
//   both halves of the generator/converter pair. See docs/tunables.md.
const float TUNE_E_REALIZE = 1.f;

// So an overflow makes a generator LOSE to the converter that realizes it, and
//   never makes it unbuildable (apexearth 2026-08-26; his standing ruling is
//   that the generator ladder never pauses on waste). See docs/tunables.md.
const float TUNE_E_WASTE_WORTH = 0.25f;

// M_REALIZE [toggle 0/1]: the metal twin of E_REALIZE -- extraction priced by
//   the share of its metal we could actually spend. DEFAULT OFF: inert where it
//   was measured and its premise is unproven. Also gates the rich seat spending: while the bank
//   overflows, the :losing/:outgrown drops (one tier below the top) and the metal con role stand down; the T1 air mute holds. See docs/tunables.md.
const float TUNE_M_REALIZE = 1.f;

// The unspendable band keeps this share, because demand grows and the spot is
//   still ours when it does -- the same reason E_WASTE_WORTH is not zero.
const float TUNE_M_WASTE_WORTH = 0.3753f;

// Spatial threat prior: 0 at our start box, 1 at theirs. See docs/tunables.md.
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
//   unit that is a hopeless soldier can still be a good screen. See docs/tunables.md.
const float TUNE_SCREEN_WORTH = 0.2f;

// [count] -- Standing units of a screen class (power at the Tick floor) a
//   player fields at once; the screen axis stops buying past it. See docs/tunables.md.
const float TUNE_SCREEN_MAX = 5.f;

// MEDIC_FRAC: standing rez/repair fleet as a fraction of army value per minute
//   (apexearth: "3 times more rezbots" -- was 0.04). See docs/tunables.md.
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
//   See docs/tunables.md.
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

// WHAT A UNIT IS GOOD FOR when the ground is being lost (apexearth
// 2026-09-16, Cortex losing Supreme Isthmus: "the best thing to do in this
// situation is to make a Behemoth. They're super duper defensive"). Applied
// on top of UnitWorthMod only while Military::LosingGround() or the base is
// contested; 1.0 = no opinion.
float UnitHoldMod(const string &in name)
{
	if (name == "corjugg") return 2.f;     // Behemoth: the answer when losing
	return 1.f;
}
// AA_URGENCY: multiplier on the insurance rate for anti-air. See docs/tunables.md.
const float TUNE_AA_URGENCY = 1.f;

// AA metal we are aiming to have standing per metal of enemy air we have seen
//   (apexearth: "if the enemy rolls up with 100k metal worth of air. See
//   docs/tunables.md.
const float TUNE_AA_COVER_FRAC = 0.5f;

// ECO_AA_MULT: the share of the air census the rear eco specialist answers,
//   relative to an even split. See docs/tunables.md.
const float TUNE_ECO_AA_MULT = 1.5f;

// JOIN_MIN_M: def cost above which a second builder JOINS the standing build
//   instead of opening a parallel copy (fusion-and-up territory).
const float TUNE_JOIN_MIN_M = 354.f;

// ECO_LEASH: work radius of the quiet rear's builders from home -- the safe
//   radius it prices everything else against.
const float TUNE_ECO_LEASH = 2500.f;

// ECO_CON_KEEP: land T1 cons the quiet rear always keeps -- nano turrets and
//   small works still need hands (his floor-of-3 number).
const float TUNE_ECO_CON_KEEP = 3.f;

// T2_CON_BASE / T2_CON_PER_M: how many cons able to build the game's best
//   extractor we always want standing -- BASE plus one per PER_M of metal income
//   (apexearth 2026-08-23: "1 T2 con + 1 per 25 metal . See docs/tunables.md.
const float TUNE_T2_CON_BASE = 1.f;

const float TUNE_T2_CON_PER_M = 31.f;

// [count] -- constructors of ANY TIER the line orders before the draw, the
//   plain "how many hands" floor. See docs/tunables.md.
const float TUNE_CON_BASE = 4.38f;

// [count] -- basic air constructors kept once an air lab stands, one in the
//   queue at a time so the other air keeps coming. See docs/tunables.md.
const float TUNE_T1_AIR_CON_MIN = 10.f;

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
//   instead. See docs/tunables.md.
const float TUNE_RECLAIM_REZ_BIAS = 3.f;

// [share] -- How much of the metal nothing is spending one build site may
//   claim as nano demand. See docs/tunables.md.
const float TUNE_NANO_SITE_SHARE = 1.f;

// [count] -- Ranked metal spots offered to the engine per election before
//   extraction gives up for that tick. See docs/tunables.md.
const float TUNE_MEX_TRIES = 10.f;

// [multiplier] -- What the ROOM under an obsolete building is worth, as a
//   multiple of (base fill x metal per build cell x the building's own cells).
//   See docs/tunables.md.
const float TUNE_ROOM_WORTH = 1.f;

// MOBILE_BP_EFF: fraction of a mobile builder's workertime that is real
//   lathing rather than transit; nanos and other statics count at 1.0.
const float TUNE_MOBILE_BP_EFF = 0.6f;

// INSURE_RATE: protection value per metal of covered assets, per second -- the
//   one modeled risk quantity for eyes and turrets. See docs/tunables.md.
const float TUNE_INSURE_RATE = 0.0003f;   // was 5e-5: radar lost to marginal solars until assets were huge (watched)

// TARGFAC_WANT: pinpointers wanted (apexearth 2026-08-23: "3 wanted max").
const float TUNE_TARGFAC_WANT = 3.f;

// ---------------------------------------------------------------------------
// Strategic structures -- manager/brain/market/want_super.as
// ---------------------------------------------------------------------------
// SUPER_WANT: master switch for the strategic want (gantry, nuke silo,
//   anti-nuke, long-range gun). See docs/tunables.md.
const float TUNE_SUPER_WANT = 1.f;

// SUPER_PUSH: 1 = an affordable strategic want skips the category lottery
//   rather than taking a proportional share of it. See docs/tunables.md.
const float TUNE_SUPER_PUSH = 1.f;

// SUPER_AFFORD_S [seconds] -- the whole affordability test: the bill (metal
//   plus energy at the conversion floor) must be smaller than what the economy
//   makes in this many seconds. See docs/tunables.md.
const float TUNE_SUPER_AFFORD_S = 60.f;

// SUPER_PER_INCOME [metal/s] -- income per additional anti-nuke; the offensive
//   classes (silo, long-range gun) space at twice this. See docs/tunables.md.
const float TUNE_SUPER_PER_INCOME = 150.f;

// SUPER_SHARE: the slice of total economic power the strategic market may
//   claim as a want's gain. See docs/tunables.md.
const float TUNE_SUPER_SHARE = 0.25f;

// SUPER_FLIGHT_PER [metal/s of overflow] -- one strategic frame may stand
//   half-built per this much structural overflow, on top of the base one. See
//   docs/tunables.md.
const float TUNE_SUPER_FLIGHT_PER = 140.f;

// COPY_OVERFLOW_M [metal/s] -- the wealth waiver: overflow above this lifts
//   the plant-copy ban and the one-advanced-plant-at-a-time serialization ("make
//   more nanos around our gantry and if we can't do that then make another
//   gantry"; "multiple adv air are ok if we are crazy wealthy").
const float TUNE_COPY_OVERFLOW_M = 140.f;

// CON_FEED_HEADROOM -- how many hands the production draw may price toward, as
//   a multiple of income/apex_request_drain (the hands income keeps fed). See
//   docs/tunables.md.
const float TUNE_CON_FEED_HEADROOM = 1.847f;

// UNIT_AFFORD_S [seconds of income] -- a mobile unit's bid fades as its cost
//   approaches this much income, dying at the full bill (mass first, T3 from
//   surplus -- the supers' 60s affordability bar applied to units). See docs/tunables.md.
const float TUNE_UNIT_AFFORD_S = 120.f;

// DEF_SETBACK [elmos] -- front defence sites step this far back from the
//   contested edge toward home, so the frame survives building; most tower
//   ranges (430+) still cover the edge it stepped back from.
const float TUNE_DEF_SETBACK = 250.f;

// SCOUT_OVER_S [seconds] -- one idle cheap air scout is sent across the enemy
//   position this often ("I don't see any scouts flying over their base"). See
//   docs/tunables.md.
const float TUNE_SCOUT_OVER_S = 45.f;

// RE-ARMED 2026-08-31 on his ask, with the mechanism replaced. See docs/tunables.md.
const float TUNE_ECO_ROLE = 1.f;

// [toggle 0/1] -- The eco seat is elected once and keeps the role until its heartbeat stops (his
//   10-15: "just have 1 eco"). See docs/tunables.md.
const float TUNE_ECO_LATCH = 1.f;

// [toggle 0/1] -- Team games (3+ of our seats): one seat, elected once, takes its advanced lab
//   at the normal time and hands out advanced constructors in proportion to the allies'
//   uncovered upgrade hands; the others price their own first advanced lab down by the share
//   of those hands the handouts cover. His 10-15. See docs/tunables.md.
const float TUNE_TEAM_TECH = 1.f;

// [0..1 of the eco target] -- FORCE THIS AI TO PLAY THE ECO PLAYER. 0 leaves
//   the ordinary seat election alone. Above 0 it takes the seat whatever
//   the team's size or shape, and the value is how FAR it grows before army
//   and defence come back: 1 the whole eco target, 0.5 half of it, so half the
//   eco phase. See docs/tunables.md.
const float TUNE_ECO_FORCE = 0.f;
const float TUNE_ECO_SEAT_STRICT = 0.f;  // the growing eco seat's hands and labs take only economy (+AA while air kills us); see docs/tunables.md

// GANTRY_AFFORD_S [seconds] -- the gantry's affordability horizon, over TEAM
//   income: one shared line the whole team's nanos man, so one team purse. See
//   docs/tunables.md.
const float TUNE_GANTRY_AFFORD_S = 100.f;

// GANTRY_INSURE: the gantry's capability-insurance gain as a share of team
//   income ("if the enemy comes at us with a Behemoth and we do not have one we
//   are in big trouble") -- the answer to enemy T3 is worth this even with no
//   army gap and no overflow on the books.
const float TUNE_GANTRY_INSURE = 0.5f;

// GANTRY_HOST_INC [metal/s] -- the proposing player's OWN income at which the
//   gantry gain is whole; below it the gain scales by (own/anchor)^2. See
//   docs/tunables.md.
const float TUNE_GANTRY_HOST_INC = 150.f;

// OFFENSE_DEF_FLOOR: the share of its gain an offensive super (silo, LRPC)
//   keeps at ZERO standing defence; the rest scales in with the defence target's
//   fill ("we consistently make Basilisk before T3 or even T2 defense"). See
//   docs/tunables.md.
const float TUNE_OFFENSE_DEF_FLOOR = 0.1f;

// ANTINUKE_R [elmos] -- an anti-nuke's assumed umbrella, for deciding whether
//   ground is already covered by one we own.
const float TUNE_ANTINUKE_R = 2000.f;

// OBSOLETE_RATIO: how many times better the best standing alternative must be
//   (per cell for generators, in power for defences) before a building is scrap
//   -- his "much better".
const float TUNE_OBSOLETE_RATIO = 4.f;

// LATHE_OBSOLETE: 1 = a construction turret a denser one per cell of ground
//   replaces is obsolete on arrival and a candidate for retirement; 0 = the
//   basic turret is built and kept forever. See docs/tunables.md.

// NANO_SHIFT_IDLE [share] -- how much of the lathe standing with nothing to
//   lathe is netted off a line's shift demand. 0 = the shift is bid whole.
//   See docs/tunables.md.

// EXPOSE_R: elmos from the core at which a structure counts fully exposed (a
//   walk away from where the army lives).
const float TUNE_EXPOSE_R = 1200.f;

// EXPOSED_LOSS_S: seconds over which a fully exposed, unguarded asset is
//   expected to be lost against a real opponent -- his "almost guaranteed". See
//   docs/tunables.md.
const float TUNE_EXPOSED_LOSS_S = 120.f;

// DEFAULT 0 -- the mechanism is wired but priced out. See docs/tunables.md.
const float TUNE_FRAME_RISK = 0.0f;

// DEF_TRADE: metal of enemy wave a standing turret is expected to stop, per
//   metal of its own cost. See docs/tunables.md.
const float TUNE_DEF_TRADE = 3.f;

// A defence is discounted by H/(H+buildSec), so a slow turret keeps only the
//   share of the threat window it will actually cover. See docs/tunables.md.
const float TUNE_DEF_TTD_H = 120.f;

// How often the protection field is rebuilt, in game seconds. See docs/tunables.md.
const float TUNE_PROTECT_FIELD_S = 15.f;

// How often the energy-stall answer re-asks which worker should drop what it
//   is doing. See docs/tunables.md.
const float TUNE_STALL_ANSWER_S = 1.f;

// Energy income above which the stall answer stops asking at all. See docs/tunables.md.
const float TUNE_STALL_ANSWER_MAX_E = 400.f;

// WHAT A BUILDING IS WORTH WHILE NOTHING GUARDS IT (apexearth: "give buildings
//   a ~20% reduced value when they are unprotected. See docs/tunables.md.
const float TUNE_UNPROT_DISCOUNT = 0.20f;

// A TURRET ONLY SHOOTS WHILE IT IS ALIVE. See docs/tunables.md.
const float TUNE_DEF_ALPHA_W = 1.f;

// ECO_RAID_TAU: seconds of memory in the structure-loss field. See docs/tunables.md.
const float TUNE_ECO_RAID_TAU = 180.f;

// THREAT_R: radius the enemy-mass prior is sampled over. See docs/tunables.md.
const float TUNE_THREAT_R = 900.f;

// STAKE_HORIZON_S: seconds of a mex's stream that count as the stake standing
//   on it. See docs/tunables.md.
const float TUNE_STAKE_HORIZON_S = 300.f;

// RISK_FLOOR: a flat hazard every asset carries whether or not anything has
//   been seen. 0 since 2026-09-11: the blind floor is the siege prior, a
//   mirror of our own army, so it is an output. See docs/tunables.md.
const float TUNE_RISK_FLOOR = 0.f;

// HZ_APPROACH [weight]: hazard floor from enemy formations WALKING at this
//   ground -- horizon/ETA, weighed by their metal against what defends it.
//   Measured (LOS-slaved) and a floor only, so it never fires where nothing
//   was seen. See docs/tunables.md.
const float TUNE_HZ_APPROACH = 0.f;

// ENEMY_PRIOR: pre-contact estimate of enemy army as a share of OUR total
//   value (symmetric start); the observed census replaces it once larger.
const float TUNE_ENEMY_PRIOR = 0.25f;   // 0.35 + a continuous line drained the bank into army (watched: out of metal)

// MATCH_RATIO: army fielded per metal of enemy army SEEN.
const float TUNE_MATCH_RATIO = 1.2f;

// ALLY_SHARE: 1 = scale the SEEN census in ArmyTarget by our income share of
//   the team (the census is side-wide; the answer is split by the roster). See
//   docs/tunables.md.
const float TUNE_ALLY_SHARE = 1.f;

// ARMY_FILL_S: seconds over which an army-value gap counts as a stream.
const float TUNE_ARMY_FILL_S = 180.f;   // the 120 compensation was fighting the Wait throttle, not the price; with the line continuous, 180 shares honestly

// REZ_HORIZON: seconds over which the army's REPAIR backlog is closed. New
//   wrecks are a measured rate (Military::WreckRateM) and need no horizon.
const float TUNE_REZ_HORIZON = 120.f;

// [ratio] -- Share of a rez bot's work rate it actually delivers (the rest is
//   walking between wrecks). See docs/tunables.md.
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
//   docs/tunables.md.
const float TUNE_RETREAT_FLOOR = 0.08f;

// STAKE_WEIGHT: how strongly an army DEFICIT borrows urgency from the total
//   value at risk (expected loss = everything x defeat probability).
const float TUNE_STAKE_WEIGHT = 1.f;

// [toggle 0/1] -- Keep his 2026-09-19 rule: once an advanced hand exists, no
//   basic tower at all. 1 is his behaviour and the default; 0 is the arm that
//   measures what the rule costs against an enemy that laps the map in
//   85-metal turrets. See docs/tunables.md.
const float TUNE_T1_TOWER_LATE = 0.f;

// [toggle 0/1] -- His 2026-08-27 ruling: a copy of a line we already run is
//   INELIGIBLE and the want forwards to a nano at the standing lab. 0 is that
//   ruling and the default; 1 lets the copy compete on price, which is the arm
//   that measures what the ruling costs in the opening (BARb stands on ~1.5
//   plants per player at minute 4, we stand on 1). See docs/tunables.md.
const float TUNE_PLANT_COPY = 0.f;

// STATIC_GUARD: how much a metal of CORE static defense counts toward the army
//   when computing the stake -- under 1 because towers cannot chase.
const float TUNE_STATIC_GUARD = 0.7f;

// [toggle 0/1] -- Draw the computed front line. Allies and spectators see
//   every map overlay below, so each ships off unless someone deliberately
//   turned it on.
const float TUNE_DRAW_FRONT = 0.f;

// [toggle 0/1] -- Draw the defense zone on the map: the inner ring is the C++
//   base-defence range (the army fights at any odds inside it), the outer ring
//   the incoming-push alarm radius. See docs/tunables.md.
const float TUNE_DRAW_DEFZONE = 0.f;

// [toggle 0/1] -- Draw the army's staging anchor and, when apex_medic_setback
//   is set, the medic station behind it plus the step between them. See docs/tunables.md.
const float TUNE_DRAW_LANE = 0.f;

// [toggle 0/1] -- Ping the heal post: the exact point CRetreatTask sends
//   wounded units to (front + apex_retreat_behind toward home). See docs/tunables.md.
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
//   immediately, whatever the land fraction -- when it also outweighs the
//   seen land army.
const float TUNE_AFLOAT_SUB_COST = 400.f;

// [toggle 0/1] -- Mobile artillery masses into the squad pool (long-range back
//   row, allied vision, kite/set-target) instead of soloing on CArtilleryTask,
//   which only elects static targets and walks in blind (weapon range exceeds
//   own sight for the whole family).
const float TUNE_ARTY_MASS = 1.f;

// [ratio] -- Threat-map multiplier on the Behemoth's def power, so squads
//   respect it; our own read stronger too (they are chargers and ignore the
//   margin anyway).
const float TUNE_BEHEMOTH_THREAT = 2.f;
const float TUNE_COM_BERTH = 3.f;
const float TUNE_AA_FIGHTER_SHARE = 0.5f;

// [ratio] -- Cap on the forward-bleed engage caution.
const float TUNE_BLEED_CAP = 1.6f;

// [toggle 0/1] -- The Brain's category budget scales wants by target-vs-actual
//   share; 0 turns budget shaping off.
const float TUNE_BUDGET = 1.f;

// [toggle 0/1] -- Whether the category budget's target/actual multiplier
//   actually SCALES wants, as opposed to only being logged. Measured off:
//   32 games with it on won 3.1% against 48 games off at 12.5%. See docs/tunables.md.
const float TUNE_BUDGET_LEVER = 0.f;

// [toggle 0/1] -- A category FLOOR stands down while its own category is
//   already above its target share, so the election falls through to the
//   priced draw. The budget multiplier scaled want VALUES and could not reach
//   the hoists, which is where the floors decide.
const float TUNE_FLOOR_YIELD = 0.f;

// [toggle 0/1] -- A spot whose straight-line walk crosses hot ground is
//   PRICED through TripRisk rather than refused outright. The refusal is a
//   binary gate on four samples and contradicts the loop's own comment that a
//   contested spot is priced, not hidden. See docs/tunables.md.
const float TUNE_DEATHWALK_PRICE = 0.f;

// [toggle 0/1] -- A commander already outside his leash finishes the work
//   around him (1bf6732c) instead of walking home for it. 1 is the behaviour
//   since 2026-09-22; forward is also where he dies. See docs/tunables.md.

// [0..1] -- What an extractor spot outside the commander's leash is WORTH to
//   him, as a multiplier on its score. 0 keeps the veto (the behaviour before
//   2026-09-23); 0.35 ranks a far spot below a near one of equal yield instead
//   of hiding it. The veto is the largest single refuser of extraction and
//   does not keep the commander alive. See docs/tunables.md.
const float TUNE_COM_MEX_PRICE = 0.f;

// [multiplier] -- What the army target is while the T2 switch is on. 0 is the
//   behaviour since 8aef73b1: literally zero, for ~80% of the game. 1 holds
//   the defensive need (Military::HoldNeedM) instead, capped at the full
//   target. The switch's stated purpose is a defensive army, not a stand-down.
const float TUNE_T2_ARMY_FLOOR = 0.f;

// [toggle 0/1] -- The spare-metal army floor is damped by the ARMY row's own
//   budget multiplier. 0 is the behaviour before 2026-09-23: production.as
//   never consults the budget at all, so every metal the other categories fail
//   to absorb becomes army regardless of the army target, and the corrector
//   can only ever amplify the starved side. See docs/tunables.md.
const float TUNE_ARMY_RICH_BALANCE = 0.f;
const float TUNE_BUDGET_AFTER = 1.f;
const float TUNE_RETREAT_SCALE = 1.f;
const float TUNE_ETA_COMMIT_BONUS = 0.f;
const float TUNE_BP_VS_LATHE = 1.f;
const float TUNE_BP_TRAVEL = 0.f;
const float TUNE_LIFT_TURRETS = 1.f;   // [toggle 0/1] lift.as: with no line short of lathe a transport is priced on the idle turrets it can fly to the frame furthest from done, and eco-only mode may build it (his 10-20)
const float TUNE_LIFT_HANDS = 1.f;   // [toggle 0/1] lift.as: a ground builder walking to a far job is flown when the seconds saved at its own lathe beat the AA risk on the route times plane and cargo (the commander: everything we own) (his 10-20)
const float TUNE_NANO_FLUSH = 0.f;   // [toggle 0/1] nanopack.as: a turret the packed ring cannot hold goes flush against a standing turret
const float TUNE_BIG_NEAR = 0.f;   // [toggle 0/1] sites.as: a big generator probed half a reach into the turret block; room only for turrets short
const float TUNE_ARMY_PRESS = 1.f;   // [toggle 0/1] StockFight.inl: an attack squad with nothing in sight walks to the nearest remembered group it outweighs, else the mirrored start
const float TUNE_HOT_ROAD_MEMO = 1.f;   // [toggle 0/1] decide.as ChargeTrip: a want on a road C++ refused for heat, still hot, is worth 0 to that hand
const float TUNE_AIR_OBS_EVIDENCE = 1.f;   // [toggle 0/1] state.as SettleStrike: a strike run weighs by bombers sent over the wing planned
const float TUNE_KEEP_ROUTE = 1.f;   // [toggle 0/1] TravelAction.cpp: a new route ending within 64 of the one being walked keeps it (no reset, no order)
const float TUNE_FAC_LANES = 1.f;   // [toggle 0/1] FactoryTask.cpp: the lab site test refuses lanes and other factories' doors
const float TUNE_LANE_RECLAIM = 1.f;   // [toggle 0/1] want_reclaim.as: an idle plant on a street or in an ally's factory door is priced for reclaim
const float TUNE_FORECAST_LOG = 0.f;   // [toggle 0/1] forecast.as: log the 60-second forecast's error outside eco-only games too
const float TUNE_ENERGY_GROWTH_FLAT = 1.f;
const float TUNE_SUPPORT_PER_METAL = 1.f;
const float TUNE_CONV_FEED_CAP = 1.f;
const float TUNE_UNLOCK_AFFORD = 1.f;

// [toggle 0/1] -- The keep-job hold tests the removals that are OURS (peel,
//   consolidate, con-letgo) instead of crew membership. The engine detaches a
//   hand before every re-election, so the crew test is false every time and
//   the hold has never fired: keeps=0 against offCrew=7,370 over 32 games.
//   See docs/tunables.md.

// [0..1] -- A hand already this fraction of the way to its site KEEPS the job
//   even when the site reads hot. 0 is the behaviour before 2026-09-23: any
//   hot site drops the incumbency, which is every contested site, which is
//   where 70-99% of our builds are abandoned mid-walk. 0.6 = past 60% of the
//   original walk. See docs/tunables.md.

// [toggle 0/1] -- A defence def that has NEVER had its site list built gets one
//   extra fill slot per frame, until it has been filled once. Without it the
//   one-fill-per-frame throttle returns an empty site array and the caller
//   reads it as "nowhere worth a gun". See docs/tunables.md.

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
//   docs/tunables.md.
const float TUNE_WAVE_CONC = 1.f;

// [toggle 0/1] -- Ground defence sites are slots along the WALL: the rim of
//   our own buildings plus a standoff, sampled at tower pitch so filled slots
//   form a contiguous line that grows with the base. See docs/tunables.md.
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
//   gap before the next cluster. 1 restores the old even spread.
const float TUNE_WALL_CLUSTER = 3.f;
// [ratio of the pitch] -- how tightly a cluster's guns pack.
const float TUNE_WALL_CLUSTER_TIGHT = 0.5f;

// [ratio] -- Cap on how far one bearing's buildings can drag the wall, as a
//   multiple of the worth-weighted RMS radius of everything we own. See docs/tunables.md.
const float TUNE_WALL_REACH = 2.5f;

// [ratio] -- Share of the wall pull a slot DIRECTLY BEHIND the base keeps
//   (enemy-facing slots get the full pull, tapering by bearing). See docs/tunables.md.
const float TUNE_WALL_REAR = 0.08f;

// [ratio] -- The front LINE's pull relative to the ring: his completeness
//   ruling (a wall the enemy can walk around is useless) makes an extending
//   section worth more than a redundant deepening. See docs/tunables.md.
const float TUNE_WALL_LINE_W = 2.f;

// [fraction of tower reach] -- Asset guard sites stand this far enemy-ward of
//   the asset centroid, between the buildings and the approach; 0 sites the gun
//   amid the buildings.
const float TUNE_GUARD_FORWARD = 0.5f;

// [0/1] -- 1 = a WALL slot, whose gain is the def-independent unmet-target
//   pull, ranks candidate towers by cover per metal. See docs/tunables.md.
const float TUNE_WALL_EFFICIENT = 1.f;

const float TUNE_DEF_OUTRANGE = 1.f;

// [0/1] -- Cap a defence site's stake at the metal of attackers the candidate
//   turret can actually destroy over apex_exposed_loss_s. See docs/tunables.md.
const float TUNE_DEF_KILL_CAP = 1.f;

// [0/1] -- Price a turret's cover on its SURFACE DPS (linear) instead of the
//   engine's sqrt(dps)-compressed threat. See docs/tunables.md.
const float TUNE_DEF_DPS_LINEAR = 1.f;

// [ratio] -- A T1 tower's gain once our own advanced lab stands; 1 prices
//   tiers equally. See docs/tunables.md.
const float TUNE_T1_DEF_LATE = 0.02f;

// [fraction of radar radius] -- A gap must sit outside this share of every
//   standing radar's reach before a new mast is blocked; lower = more
//   overlapping radars, sturdier intel. See docs/tunables.md.
const float TUNE_RADAR_OVERLAP = 0.45f;

// [toggle 0/1] -- The base-defence ring follows the BUILT base (farthest
//   finished rear structure plus the pad) instead of the frozen map-diagonal
//   formula; 0 keeps the static C++ ring.
const float TUNE_DEFZONE_DYNAMIC = 1.f;

// [elmos] -- Padding added to the built extent when the dynamic ring is
//   applied (roughly two T1 tower ranges of approach ground).
const float TUNE_DEFZONE_PAD = 400.f;

// [ratio] -- Minimum forward reach of a territory ray for it to yield a front
//   spot.
const float TUNE_FRONT_MIN_REACH = 0.5f;

// [toggle 0/1] -- NOTHING BEHIND US IS FRONT. 1 is the ESCAPE HATCH -- the
//   full ring, for a genuinely surrounded base. See docs/tunables.md.
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

// [metal/s] -- In-flight build requests allowed per this much metal income
//   (min 2) -- the governor on parallel sites.
const float TUNE_REQUEST_DRAIN = 7.0f;

// Assisters beyond a site's ETA-derived worker count fall back into the
//   auction instead of being held to completion. See docs/tunables.md.
const float TUNE_ASSIST_RELEASE = 1.f;

// Eco builds (energy, converter, mex, moho) keep this multiple of the
//   ETA-derived crew before the peeler calls them over-staffed -- income
//   finishing fast outranks a perfectly even build-power spread.
const float TUNE_PEEL_ECO_KEEP = 2.f;

// NANO_FED_S [seconds] -- a join is refused when standing-nano lathe alone
//   clears the site's remaining bill within the joiner's walk plus this many
//   seconds; the freed constructor founds a new frame instead (a nano can assist
//   a frame but never place one). See docs/tunables.md.
const float TUNE_NANO_FED_S = 15.f;

// how sharply the category draw follows value. See docs/tunables.md.
const float TUNE_DRAW_SHARP = 2.903f;

// [ratio] -- share of the constructors that hold a ROLE (elect inside one
//   category until the split says otherwise); the rest stay open. 0 is off.
//   See docs/tunables.md.
const float TUNE_ROLE_SHARE = 0.5f;

// T2_FUSION_PULL: [toggle 0/1] -- while the T2 switch is on and no advanced
//   generator stands, a fusion in the ranked list is TAKEN rather than drawn.
//   The switch already names fusions as its purpose and only removes army from
//   the target. 0 = the behaviour before 2026-09-22. See docs/tunables.md.
const float TUNE_T2_FUSION_PULL = 0.f;
// [seconds] -- how far back the split of need is averaged. See docs/tunables.md.
const float TUNE_ROLE_TAU = 120.f;

// [seconds] -- how far back the SPEND budget's realised share is averaged
//   (brain/budget.as). Lifetime totals compare a whole game against a
//   steady-state target, so the opening reads 100% build power. See docs/tunables.md.
const float TUNE_BUDGET_TAU = 240.f;

// [ratio] -- share of the rez fleet that serves as battlefield medics: they
//   stay with the army's staging anchor, repair the wounded during fights and
//   reclaim the aftermath there. See docs/tunables.md.
const float TUNE_MEDIC_SHARE = 0.4f;

// [elmos] -- how far around the staging anchor a medic looks for wounded
//   units, and how close it holds station.
const float TUNE_MEDIC_R = 1200.f;

// [elmos] -- how far BEHIND the lane a medic holds station. See docs/tunables.md.
const float TUNE_MEDIC_SETBACK = 0.f;

// [seconds] -- how long one hit keeps a rez bot retreating. See docs/tunables.md.
const float TUNE_REZ_FLEE_S = 20.f;

// [seconds] -- spacing on ONE bot's own wreck and resurrect scans. See
//   docs/tunables.md.
const float TUNE_REZ_SCAN_S = 1.f;

// [seconds] -- how much of the enemy's own walking counts as being in range
//   already: a rez bot backs away while the nearest enemy is still this long
//   short of its firing envelope, and refuses work inside it. See docs/tunables.md.
const float TUNE_REZ_REACT_S = 1.f;

// [0/1] -- 1 = raiders join the massing pool once our advanced lab stands and
//   fight as line army (the pre-2026-08-30 behaviour). See docs/tunables.md.
const float TUNE_RAIDER_MASSING = 0.f;

// [0/1] -- 1 = cheap RAIDER-role units are routed to solo scout tasks in spam
//   phase, spreading over unscouted clusters. See docs/tunables.md.
const float TUNE_SPAM_RAIDERS = 1.f;

const float TUNE_SPAM_SUICIDAL = 1.f;

// [seconds] -- A stuck unit already asked for unblocking is not re-asked for
//   this long.
const float TUNE_STUCK_RETRY = 120.f;

// [toggle 0/1] -- A GROW slot must keep the cluster aisle to a foreign def,
//   not just avoid touching it. See docs/tunables.md.
const float TUNE_AISLE_GROW = 1.f;

// [count] -- How many of one def stand together before the next starts a fresh
//   cluster elsewhere, so the whole economy is not in one spot. See docs/tunables.md.
const float TUNE_CLUSTER_N = 16.f;

// [toggle 0/1] -- Reclaim one of our own economy buildings that is standing in
//   a lattice slot C++ could not place on. See docs/tunables.md.
const float TUNE_RECLAIM_BLOCKER = 0.f;

// [toggle 0/1] -- THE NO-TURRET TEST (docs/doctrine.md): 1 proposes
//   no ground or AA turret at all, so radar and units are the whole defence. See
//   docs/tunables.md.
const float TUNE_DEF_OFF = 0.f;

const float TUNE_ARMY_ECO_S = 66.f;

// The economy the rear specialist names before it spends anything on war, in
//   metal/s of economic power AT NO BONUS -- EcoRoleTargetM multiplies by the
//   game's own handicap, so 250 here is 500 in a +100% game. See docs/tunables.md.
const float TUNE_ECO_TARGET_BASE = 250.f;

// The same economy for an EIGHT-player team, where the rear seat is far enough
//   from the war to spend the whole early game on it. 2026-09-14: "just let
//   it go full military and normal behavior at 1k metal instead of 2k" --
//   500 x the +100% handicap is his 1k. See docs/tunables.md.
const float TUNE_ECO_TARGET_BASE_8 = 500.f;

// Economic power, at NO-BONUS scale, before the bomber raid is worth mounting
//   at all -- the game's handicap multiplies it, so 100 here is apexearth's "200
//   m/s" in a +100% game. See docs/tunables.md.
const float TUNE_AIR_ECO_BASE = 100.f;

// Weigh a production line by how much of the map its ARMY can move around in
//   (ai.DefMapCoverage, the engine's own per-movement-type partition). See
//   docs/tunables.md.
const float TUNE_LINE_TERRAIN = 1.f;

// How far IN FRONT of the squad's longest row a short-range row holds, elmos.
//   This number is the dive depth; 96 measured worse three ways. See docs/tunables.md.
const float TUNE_SCREEN_GAP = 200.f;

// The production half is divided by (1 + this * matesWithIt), so at 1.0 the
//   second team copy is worth half and the third a third. See docs/tunables.md.
const float TUNE_TEAM_LINE = 1.f;

// [toggle 0/1] -- A cover pool promotes to ATTACK like stock's massing pool, so
//   a full pool leaves and home keeps what is still filling. 0: the pool never
//   converts (the pre-2026-09-12 hold). See docs/tunables.md.
const float TUNE_COVER_LEAVES = 1.f;

// [toggle 0/1] -- No more metal is posted to cover than our share of the raider
//   metal they have fielded (the AA counter's answer law). 0: the coverage
//   need alone decides, which at scale never closed. See docs/tunables.md.
const float TUNE_COVER_BY_RAID = 1.f;

// [toggle 0/1] -- Weigh a production line, on its WHOLE price and in the tech
//   want, by its units (median army-per-metal) times the ground they can cross
//   (LineCoverage), against the best line of its class and tier. 0 restores
//   the old pricing: terrain on the production half only. Measured worse
//   2026-09-12 (docs/tunables.md); off until the line factor is strong enough to be
//   the decision rather than a 17% nudge under the plant's own cost.
const float TUNE_LINE_QUALITY = 0.f;

// A new line escapes the copy ban only while the best combat unit it would ADD
//   is worth at least this share of the best one we already produce, and a
//   product the unit market refuses on this map (the amphib x0) prices its line
//   at nothing. 1 is parity with what we field; 0 restores the old test, which
//   asked only whether the product was new. See docs/tunables.md.

// A defence slot holds ONE building, so a tower beaten on BOTH reach and
//   killing power by a gun we can afford right now is not a cheaper option, it
//   is stranded metal (apexearth: "why build something that so quickly becomes
//   outdated?"). See docs/tunables.md.
const float TUNE_DEF_DOMINANCE = 1.f;

// Seconds of total economic power a defence building may cost and still count
//   as affordable -- the guard that stops a Pulsar we cannot pay for making
//   every tower obsolete and leaving us with nothing. See docs/tunables.md.
const float TUNE_DEF_AFFORD_S = 30.f;

// Seconds of economic power the converter burst may commit at once. See
//   docs/tunables.md.
const float TUNE_CONV_AFFORD_S = 30.f;

// [toggle 0/1] -- Count the energy draw of work already ORDERED into the pull
//   that prices energy. See docs/tunables.md.
const float TUNE_E_COMMITTED = 1.f;

// [toggle 0/1] -- Let a STALL open parallel energy sites, not only an
//   overflowing bank. See docs/tunables.md.
const float TUNE_E_PARALLEL = 0.f;

// [toggle 0/1] -- Discount a plant want by the plants of ANOTHER domain
//   already under construction. See docs/tunables.md.
const float TUNE_PLANT_INFLIGHT = 1.f;

// [seconds of economic power] -- The mex-cover QUEUE JUMP only fires once the
//   tower costs less than this many seconds of total economic power. See
//   docs/tunables.md.
const float TUNE_COVER_PUSH_S = 10.f;

// [toggle 0/1] x5 -- Defence as a crutch (his 10-14): each prices one rule that
//   bypassed the draw. 0 = before. See docs/tunables.md; counted on `apex: ecodef-stat`.
const float TUNE_RADAR_PRICE = 1.f;    // radar worth what the eyes give our army and the ground it holds
const float TUNE_DEFJOIN_PRICE = 1.f;  // the defence assist offered to the draw at its price, not hoisted
const float TUNE_FIELD_PRICED = 1.f;   // the field crew's towers and radar go to the draw
const float TUNE_COVER_PRICED = 1.f;   // the coverall and base-front towers go to the draw
const float TUNE_DEF_DANGER = 0.f;     // the defence target follows the danger our army cannot meet
const float TUNE_DEF_MEASURED = 1.f;   // [toggle 0/1] defence demand on the measured attack rate, not the 1/120 s prior (his 10-15); docs/tunables.md

// [multiplier] -- What a mex UPGRADE'S extra metal stream is worth, over its
//   honest arithmetic. See docs/tunables.md.
const float TUNE_MEXUP_BOOST = 1.f;

// [toggle 0/1] -- Price a DUPLICATE line's throughput against the cheaper way
//   to buy the same build power. See docs/tunables.md.
const float TUNE_DUP_BP_SUBST = 1.f;

// [multiplier] -- What a plant def we RECLAIMED ON PURPOSE prices at while the
//   window below runs. See docs/tunables.md.
const float TUNE_REPLANT_DISCOUNT = 0.15f;

// [seconds] -- How long the retirement memory above holds. See docs/tunables.md.
const float TUNE_REPLANT_WINDOW_S = 600.f;

// [ratio] -- How fast a unit's -- and a plant's PRODUCTION -- value fades as
//   the share of identified enemy metal above its own tier rises. See docs/tunables.md.
const float TUNE_FOE_TIER_FADE = 1.f;

// [ratio] -- The same fade against OUR OWN fielded tier: once a T2 lab or
//   gantry stands, lower-tier units lose 1/(1+this*tiersBelow) of their worth
//   ("in late game, aside from spam we should mostly only be putting our
//   resources into T3 units and advanced air"). See docs/tunables.md.
const float TUNE_OWN_TIER_FADE = 0.8f;

// [ratio] -- Share of the SYMMETRIC enemy expectation that the defence target
//   assumes could arrive at our own base before anything has been seen. See
//   docs/tunables.md.
const float TUNE_DEF_PRIOR_SHARE = 0.35f;

// ---------------------------------------------------------------------------
// ValueOf term weights -- search scaffolding for tools/ecoclimb.py. Every
// default reproduces the unweighted formula; delete each once a value is kept.
// ---------------------------------------------------------------------------
const float TUNE_VW_WALK = 1.f;        // builder wage over the walk
const float TUNE_VW_BUILD = 1.f;       // builder wage over the build
const float TUNE_VW_DISP = 1.f;        // upgrade stream the build postpones
const float TUNE_VW_LATE = 1.f;        // the asset's own late start (gain x walk/build); 0 measured +14% eco at minute 20 but -12% army / -14% metal vs BARb (10-21), so the build half is tested alone (TUNE_LATE_BUILD)
const float TUNE_VW_FLOW = 0.6598f;        // fleet throttle from an unfunded E drain
const float TUNE_VW_ECOST = 1.f;       // the energy bill
const float TUNE_VW_FEED_BANK = 0.5f;  // share of the metal bank counted toward a build's feed
const float TUNE_VW_MCS_FROM = 0.35f;  // bank fill where metal-cost forgiveness starts
const float TUNE_VW_MCS_SPAN = 0.45f;  // bank fill over which it ramps to full
const float TUNE_VW_MCS_DEPTH = 0.8f;  // forgiveness at full ramp (cost x (1 - this))
const float TUNE_REDECIDE_S = 2.f;     // [seconds] cap on the wait after repeated young returns (the first re-decides at once) (C++ twins: apex_idle_ask_f 15, apex_idle_settle_f 20 frames)
const float TUNE_MEX_LOSS_COVER = 0.1f;  // [share] extractors killed recently / (standing + killed) at which every extractor's gun jumps the queue (his 2026-10-03)
const float TUNE_BASE_FRONT = 1.f;      // [toggle 0/1] while the enemy is aggressive, medium/heavy lasers on the base's enemy-facing rim rank with the forward line (his 2026-10-04)
const float TUNE_BF_DANGER = 0.f;       // [toggle 0/1] base-front guns sized by Military::DangerGap (their strength arriving vs home strength) instead of out-massed/aggressive stance and seen army (his 2026-10-05); A/B switch, delete once judged
const float TUNE_COM_ESCORT = 1.f;      // [toggle 0/1] while constructors are owed escorts the commander assists the nearest lab with a queue (his 2026-10-04)
const float TUNE_COM_LAB_EARLY = 1.f;    // [toggle 0/1] before our first T2 lab, while the army is under its target, the commander assists the lab with a queue (his 2026-10-04)
const float TUNE_ESCORT_CAP = 8.f;       // [count] escorts on duty at once, across all exposed constructors (stock 3; his 2026-10-04 "more escorts")
const float TUNE_ESCORTS_PER_CON = 2.f;  // [count] guards each exposed constructor is owed (was 1)

// SETTINGS ONLY THE C++ READS. Same rule as everything above: the value here is the default of apex_<name>
// (InitScript.cpp hands every TUNE_ constant to CCircuitAI::SetScriptDefaults); the comment names the read.
const float TUNE_AIR_FORM = 1.f;   // C++ only: task/fighter/BombTask.cpp:117
const float TUNE_ATTACK_SHARE = 0.34f;   // C++ only: module/MilitaryManager.cpp:2435
const float TUNE_BOMB_DIST_SCALE = 4000.f;   // C++ only: task/fighter/BombTask.cpp:784
const float TUNE_BOMB_ECO_H = 300.f;   // C++ only: task/fighter/BombTask.cpp:577
const float TUNE_BOMB_ENROUTE = 0.f;   // C++ only: task/fighter/BombTask.cpp:320
const float TUNE_BOMB_FAT_MOBILE = 4000.f;   // C++ only: task/fighter/BombTask.cpp:700
const float TUNE_BOMB_MIN_VALUE = 200.f;   // C++ only: task/fighter/BombTask.cpp:783
const float TUNE_BOMB_REVISIT_DISC = 0.2f;   // C++ only: task/fighter/BombTask.cpp:802
const float TUNE_BOMB_REVISIT_S = 90.f;   // C++ only: task/fighter/BombTask.cpp:799
const float TUNE_CON_SCRATCH_GATE = 1.f;   // C++ only: task/builder/BuilderTask.cpp:996
const float TUNE_CON_STAND_FLOOR = 0.5f;   // C++ only: task/builder/BuilderTask.cpp:970
const float TUNE_CON_STAND_HEAL = 1.f;   // C++ only: task/builder/BuilderTask.cpp:969
const float TUNE_DGUN_CLOSE_MULT = 2.f;   // C++ only: unit/action/DGunAction.cpp:84
const float TUNE_DGUN_CLOSE_WORTH = 0.f;   // C++ only: unit/action/DGunAction.cpp:168
const float TUNE_DGUN_FF = 1.f;   // C++ only: unit/action/DGunAction.cpp:104
const float TUNE_DGUN_LOG = 0.f;   // C++ only: unit/action/DGunAction.cpp:55
const float TUNE_FIGHT_TRAVEL = 1.f;   // C++ only: unit/action/MoveAction.cpp:44
const float TUNE_GHOST_PURGE_SECS = 90.f;   // C++ only: CircuitAI.cpp:1089
const float TUNE_GHOST_STALE_MIN = 15.f;   // C++ only: CircuitAI.cpp:1091
const float TUNE_HOT_RADIUS = 1000.f;   // C++ only: CircuitAI.cpp:3753
const float TUNE_IDLE_ASK_F = 15.f;   // C++ only: task/IdleTask.cpp:62
const float TUNE_IDLE_SETTLE_F = 20.f;   // C++ only: task/IdleTask.cpp:63
const float TUNE_INBASE_PATH = 0.f;   // C++ only: task/builder/BuilderTask.cpp:1444
const float TUNE_INTENT_HOLD = 3.f;   // C++ only: unit/CircuitUnit.cpp:532
const float TUNE_MEX_NEAREST = 0.f;   // C++ only: module/EconomyManager.cpp:1054
const float TUNE_NANO_SPACE_RECLAIM = 1.f;   // C++ only: module/FactoryManager.cpp:1526
const float TUNE_NUKE_HOME_WEIGHT = 4.f;   // C++ only: task/static/SuperTask.cpp:219
const float TUNE_ORDER_ARBITER = 0.f;   // C++ only: unit/CircuitUnit.cpp:531
const float TUNE_ORDER_DEDUPE = 0.f;   // C++ only: unit/CircuitUnit.cpp:542
const float TUNE_ORDER_TRACE = 0.f;   // C++ only: unit/CircuitUnit.cpp:490
const float TUNE_POOL_LEASH = 0.f;   // C++ only: task/fighter/DefendTask.cpp:421
const float TUNE_PREFER_TARGET = 1.f;   // C++ only: unit/CircuitUnit.cpp:1066
const float TUNE_RAID_COMMIT = 2.f;   // C++ only: task/fighter/RaidTask.cpp:338
const float TUNE_RAID_FIRST = 1.f;   // C++ only: module/MilitaryManager.cpp:2359
const float TUNE_REACH_ORDERS = 0.f;   // C++ only: unit/CircuitUnit.cpp:609
const float TUNE_RECORD_LOAD = 1.f;   // C++ only: CircuitAI.cpp:2827
const float TUNE_RECORD_PRIOR = 10.f;   // C++ only: CircuitAI.cpp:2619
const float TUNE_RECORD_WINDOW = 40.f;   // C++ only: CircuitAI.cpp:2858
const float TUNE_RETREAT_BEHIND = 600.f;   // C++ only: task/RetreatTask.cpp:218
const float TUNE_RETREAT_LOG = 0.f;   // C++ only: task/RetreatTask.cpp:258
const float TUNE_RETREAT_STAND = 0.f;   // C++ only: task/RetreatTask.cpp:611
const float TUNE_RETREAT_THREAT_MOD = 4.f;   // C++ only: task/RetreatTask.cpp:327
const float TUNE_ROAM_FRONT = 1.f;   // C++ only: task/fighter/FighterTask.cpp:381
const float TUNE_ROAM_R = 1200.f;   // C++ only: task/fighter/FighterTask.cpp:382
const float TUNE_SIDE_WITH = 1.f;   // C++ only: task/fighter/AttackTask.cpp:1024
const float TUNE_SIEGE_FIGHT = 1.f;   // C++ only: task/fighter/AntiAirTask.cpp:111
const float TUNE_SQUAD_FORM = 1.f;   // C++ only: task/fighter/AttackTask.cpp:121
const float TUNE_STOCK_STALL_ABORT = 0.f;   // C++ only: task/builder/BuilderTask.cpp:1206
const float TUNE_STOCK_STALL_WAIT = 0.f;   // C++ only: task/builder/BuilderTask.cpp:1258
const float TUNE_TARGET_VALUE = 1.f;   // C++ only: task/fighter/AttackTask.cpp:1073
const float TUNE_TASK_TRACE = 0.f;   // C++ only: task/builder/BuilderTask.cpp:446
const float TUNE_TRAVEL_LEAN = 1.f;   // C++ only: unit/action/FightAction.cpp:63
const float TUNE_TRAVEL_SAMESTEP = 0.f;   // C++ only: unit/action/FightAction.cpp:97
const float TUNE_WAKE_SPLIT = 1.f;   // C++ only: unit/CircuitUnit.cpp:210

// SETTINGS THAT WERE READ WITH A LITERAL DEFAULT (moved here 10-19 so the file holds every value).
const float TUNE_AUCTION_DIAG = 0.f;   // script: manager/brain/market/decide.as
const float TUNE_DEF_TEAMPOW_AFFORD = 1.f;   // script: manager/brain/market/protect_want.as
const float TUNE_EFLOOR_DIAG = 0.f;   // script: manager/brain/market/price.as
const float TUNE_ETA_TRACE = 0.f;   // script: manager/brain/market/decide.as
const float TUNE_FIRST_LAB = 0.f;   // script: manager/brain/market/want_plant.as
const float TUNE_GUARD_POSTS = 1.f;   // script: manager/military/guardposts.as
const float TUNE_MSTALL_PREM = 1.f;   // script: manager/brain/market/price.as
const float TUNE_NOSITE_DIAG = 0.f;   // script: manager/brain/market/protect_want.as
const float TUNE_PN_POST = 1.f;   // script: manager/military/nnpost.as
const float TUNE_POLICY = 1.f;   // script: manager/brain/market/policy.as
const float TUNE_RECLAIM_IDLE_NANO = 1.f;   // script: manager/brain/market/want_reclaim.as
const float TUNE_ROLE_FLOOR_ZERO = 1.f;   // script: manager/brain/market/production.as
const float TUNE_SPILL_OUTGROWN = 0.f;   // script: manager/brain/market/production.as
const float TUNE_TECHCAND_DIAG = 0.f;   // script: manager/brain/market/want_tech.as
const float TUNE_UNIT_COVER = 1.f;   // script: manager/brain/market/coverage.as
const float TUNE_WANTTEST = 0.f;   // script: manager/brain/market/wanttest.as
