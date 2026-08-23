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
// Each entry is annotated with the FILE that reads it, its units where the
// name implies them, and the first line of the explanation already sitting at
// the call site. When a comment reads like a slogan ("SIEGE FEARS PROXIMITY")
// the full reasoning -- usually a measurement or a direct quote -- is in that
// file at the GetTunable call. Anything unannotated is read from more than one
// place; grep the name to see them all.
//
// WHAT IS NOT HERE: build RATIOS. The army/economy/defence split lives in
// targets.as (SPEND_ARMY, SPEND_ECONOMY, ... -- five columns, one per build
// phase, normalized against each other), and unit mixes per factory live in
// config/standard/factory.json. "Build less army" is targets.as; "when
// is a fusion allowed" is here.

// ---------------------------------------------------------------------------
// Economy — energy, fusion, converters, reclaim
// ---------------------------------------------------------------------------
// manager/builder/fusion.as [energy/s] -- no advanced solar below this energy
//   income.
// manager/builder/requests.as [elmos] -- BEHIND THE BASE, NOT WHEREVER THE
//   ASKER STOOD.
// manager/builder/mexguard.as [metal] -- Generators at least this expensive
//   count as advanced-solar class and pack shoulder-to-shoulder next to the
//   last one instead of scattering on the band.
// manager/builder/mexguard.as [elmos] -- Search radius around the standing
//   pack for the next advanced solar's site.
// manager/builder/requests.as [toggle 0/1] -- ADVANCED SOLARS ARE STRICTLY
//   SERIAL, whatever the bank.
const float TUNE_ADVSOL_SERIAL = 0.f;   // leaf-era decree off: the wealth cap (dup_bank) bounds parallels; serial refusals churned 8.6k decides at 500 m/s
// manager/builder/fusion.as [energy/s] -- Advanced solars stop once energy
//   income reaches this and T2 stands; past that point the next buy is the
//   fusion, not another panel.
// manager/builder/mexguard.as [toggle 0/1] -- Keep one energy build always
//   underway: with none in flight, claim a builder for the next generator. 0
//   disables the rule.
// manager/builder/mexguard.as [metal/s] -- One parallel always-eco build per
//   this much metal income (minimum one): the floor under energy scaling,
//   above which the deficit forecast opens more.
// manager/builder/obsolete.as [metal/s] -- Metal income at which the economy
//   counts as big for the cleanup rules (reclaiming obsolete buildings); also
//   treated as big whenever the game is lagging.
// manager/builder/mexguard.as [energy/s] -- Energy drain a new converter is
//   assumed to add; one is only placed while spare energy clears this plus the
//   reserve.
// manager/brain.as [ratio] -- Discount on the converter Want while no energy
//   is actually being wasted -- a converter with nothing spare to eat produces
//   nothing.
// manager/builder/converter.as -- TILE, don't spiral: FindBuildSiteNear
//   returns any legal site, which stepped the pack diagonally with half-cell
//   offsets...
// manager/builder/converter.as -- apexearth: "5% chance to place one in a new
//   spot...
// manager/builder/converter.as [elmos] -- How tight a new converter packs next
//   to the latest one (95% adjacent, 5% fresh spot).
// manager/builder/converter.as [energy/s] -- One additional converter allowed
//   per this much spare energy income.
// manager/builder/mexguard.as [energy/s] -- Spare energy kept in hand above a
//   new converter's assumed drain before placing it.
// manager/brain.as -- The election TIME budget in maketask.as is the governor
//   now; this count is only a runaway backstop, set far above normal bursts.
// manager/builder/requests.as [ratio] -- Duplicate in-flight orders of the
//   same building the bank justifies: one extra copy per (its cost x this) of
//   banked metal.
const float TUNE_DUP_BANK = 1.f;
// manager/brain.as [ratio] -- Floor on the economy-overspend deferral:
//   reactor-class buys are slowed by at most this factor, never stopped.
// manager/brain.as [metal] -- Only economy buys at least this expensive defer
//   while the eco share overruns its target; mexes, mex upgrades and cheap
//   generators are exempt.
// manager/factory/mexhold.as [toggle 0/1] -- The eco lead keeps farming even
//   while an ally is dying (aid flows as EcoAid metal instead); 0 restores
//   standing the role down.
// manager/builder/maketask.as [ratio] -- Economy lanes yield their builders
//   once actual eco spend exceeds its target share by this factor; they resume
//   when back under.
// manager/builder/mexguard.as [toggle 0/1] -- Any constructor may answer the
//   home-energy rule; 0 restores it to the HOME crew only.
// manager/builder/mexguard.as [toggle 0/1] -- Prefer planting generators
//   inside a defence turret's reach when one is near; 0 always uses the
//   ordinary layout.
// manager/builder/mexguard.as [ratio] -- Fraction of the covering turret's
//   range that counts as protected ground for generator placement.
// policy.as -- Build energy while income < pull * this.
const float TUNE_ENERGY_HEADROOM = 1.35f;
// manager/builder/mexguard.as [energy/s] -- panic solar panels only while
//   energy income is below this; a bigger economy answers a stall with the
//   ladder's fusion instead.
// manager/builder/maketask.as [toggle 0/1] -- Allow the engine's ENERGY-
//   storage offers; 0 refuses them outright (metal storage untouched) --
//   storage is rarely right without a superweapon to charge.
// policy.as [metal or metal/s] -- Energy per metal: the grid target follows
//   METAL income (energy.pull is throttled demand and self-reports "fine"
//   while starving...
const float TUNE_E_PER_METAL = 20.f;
// manager/builder/fusion.as [count] -- T2 mexes that license the first fusion
//   as the alternative to the income bar; after the first reactor neither bar
//   applies.
// manager/builder/fusion.as [metal/s] -- Metal income below which the first
//   fusion is refused unless the moho count clears it.
// policy.as [metal or metal/s] -- A fusion costs ~21,000 ENERGY to construct:
//   starting one on a small grid drains it -- the lathe plus a producing T2
//   lab stalls...
const float TUNE_FUSION_MIN_ENERGY = 1000.f;
// manager/builder/mexguard.as [metal/s] -- From this income a wasteful grid is
//   answered with a fusion rather than another small generator.
// manager/factory/factorydefs.as [energy/s] -- one gantry allowed per this
//   much energy income. A building gantry draws 460-620 energy/s on its own,
//   and the metal-income rungs above say nothing about that...
// manager/builder/mexguard.as [energy/s] -- Energy income before geothermal
//   counts as affordable: the 13,000-energy build price drains a small
//   economy (commanders never take the geo job -- level-1/2 cannot build it).
// Energy horizon for EcoAffordableE (ecomath.as): seconds of energy income a
// build's costE may claim. 52 makes a 13,000-E geo clear at 250 e/s -- the
// bar apexearth stated -- so the derived gate reproduces his number and then
// scales with def cost and grid size instead of being pinned to either.
// manager/builder/statics.as [ratio] -- Share of energy income that may go to
//   jammer upkeep; sets how many jammers the grid supports.
// manager/brain/nukes.as [seconds] -- How long a defensive volley waits for
//   its silos to pool enough stockpile before the volley lapses.
// manager/brain/nukes.as [count] -- Extra missiles a volley budgets per
//   SIGHTED antinuke covering the target (the first missile is eaten).
// manager/brain/nukes.as [metal] -- A defensive volley adds one missile per
//   this much enemy army value spread beyond the first blast (at most 3
//   extra).
// manager/builder/opening.as -- THE OPENING SEQUENCE: 1.
// policy.as [energy/s] -- energy income below which winds and advanced
//   solars are never reclaimed (apexearth: ">2000 reclaim wind and advanced
//   solar"); wind's cliff additionally scales down on bad-wind maps.
const float TUNE_RECLAIM_GEN_E = 2000.f;
// policy.as [ratio] -- PADDING: a victim is only eligible while the grid
//   AFTER eating it still clears pull by this factor.
const float TUNE_RECLAIM_PAD = 1.5f;
// policy.as -- Income cliffs below which a generator tier is never eaten
//   (apexearth 2026-08-15: solars ~500, wind/advsol ~2000, wind scaled...
const float TUNE_RECLAIM_SOLAR_E = 500.f;
// manager/brain/facqueue.as [metal/s] -- One T1 core combat unit wanted per
//   this much metal income (scaled up under army pressure).
// manager/brain/facqueue.as [metal/s] -- One T2 core combat unit wanted per
//   this much metal income (scaled up under army pressure).
// policy.as [metal/s] -- Metal income required before committing to T2
//   (techlead.as RushReady, and the rear plant-siting rule reads the same
//   knob). apexearth 2026-08-21: "30 m/s is a good number". The T2 decision
//   is this pair: apex_t2_metal AND apex_t2_energy.
const float TUNE_T2_METAL = 30.f;
// manager/factory/techlead.as [toggle 0/1] -- The T2 commit's losing-ground/
//   contested safety veto; 0 techs through pressure (the choke-map escape).
// policy.as [energy/s] -- Energy income required before starting T2
//   (techlead.as RushReady), and the lower bar once a reactor already stands.
const float TUNE_T2_ENERGY = 1200.f;
// policy.as [metal/s] -- NOT a T2 permission knob: the metal income from
//   which the energy-buildup lane starts enforcing its pre-T2 energy floor
//   (building the grid FOR T2, ahead of the decision itself).
const float TUNE_T2_ENERGY_FROM = 12.f;
// policy.as [energy/s] -- The lower T2 energy bar once a reactor already
//   stands (apex_t2_energy is the bar without one).
const float TUNE_T2_ENERGY_REACTOR = 400.f;

// ---------------------------------------------------------------------------
// Constructors, build power, nanos
// ---------------------------------------------------------------------------
// manager/brain.as [seconds] -- Assumed arrival window of an enemy nuke
//   volley; antinukes wanted = one interceptor per reload that fits in this
//   window, per enemy silo.
// manager/assist.as [ratio] -- The factory line asks for more hands while
//   actual army spend is under its target share times this -- the shortfall is
//   the signal, not spare metal.
// manager/assist.as [seconds] -- One fallback-assist offer per bot per this
//   many seconds; between offers the bot waits instead of re-running the
//   election ladder.
// manager/assist.as [toggle 0/1] -- Constructors may stack on the factory line
//   to speed army production; 0 disables line assist entirely.
// manager/assist.as [ratio] -- Lathes allowed on a factory line: the economy-
//   scaled guard stack times this -- the line is the one lead whose speed is
//   directly army production.
// manager/assist.as [ratio] -- At most this share of the constructor pool may
//   be factory helpers at once, so the line cannot take every builder.
// manager/builder/nano.as [toggle 0/1] -- A factory asking for hands may get a
//   permanent nano turret instead of a walking guard; 0 always sends the
//   constructor.
// manager/builder/obsolete.as [metal/s] -- One mobile assist bot allowed per
//   this much metal income (plus 2); turrets are the preferred build- power
//   sink.
// manager/assist.as [ratio] -- Spare income (income minus pull) above this
//   fraction of income also counts as the line wanting help.
// manager/builder/nano.as [ratio] -- Nano-turret burst on a deep bank: one
//   extra turret queued per this many turret- costs of banked metal.
// manager/military/massing.as [toggle 0/1] -- The conservative stance (hold
//   rather than attack while behind) is allowed; 0 removes it.
const float TUNE_CONSERVATIVE_HOLD = 1.f;
// manager/builder/share.as [ratio] -- Floor on the constructor-want deferral
//   while build power overruns its share and army is under its own: slowed to
//   at most this factor, never zero.
// manager/builder/share.as [ratio] -- Constructor want multiplier while the
//   metal bank is empty -- an empty bank is not a build-power shortage.
// manager/brain/facqueue.as [ratio] -- Constructor cap multiplier while the
//   metal surplus is real (bank full AND the grid healthy) -- more hands to
//   spend it.
// policy.as [curve] -- T1 constructor curve slope: cons wanted = A x
//   ln(income) + B. At A=4.6/B=-6.55 that is ~4 cons at 10 m/s, ~14 at 100.
//   The dashboard edits this as anchor points.
const float TUNE_CON_LOG_T1_A = 4.6f;
// policy.as [curve] -- T1 constructor curve intercept -- see
//   apex_con_log_t1_a.
const float TUNE_CON_LOG_T1_B = -6.55f;
// policy.as [curve] -- T2 constructor curve slope: cons wanted = A x
//   ln(income) + B.
const float TUNE_CON_LOG_T2_A = 6.0f;
// policy.as [curve] -- T2 constructor curve intercept -- see
//   apex_con_log_t2_a.
const float TUNE_CON_LOG_T2_B = -16.0f;
// manager/brain/facqueue.as -- apexearth: a floor of 3 T1 cons; beyond that,
//   more only on surplus metal, and never while the enemy army outweighs ours
//   -- an...
// manager/military/massing.as [ratio] -- Outmassed reads true while enemy
//   massing threat exceeds our team army value times this; being outmassed
//   suspends cheap-constructor growth.
const float TUNE_CON_OUTMASSED = 1.f;
// manager/builder/share.as -- The curve answers "how many could we support",
//   not "how many have work".
// policy.as -- A PASSIVE read of the enemy licenses a bigger builder fleet.
const float TUNE_GREED_CONS = 1.7f;
// manager/assist.as [metal/s] -- Shadow constructors one lead builder may
//   hold: one more per this much metal income, never a flat cap.
// manager/assist.as [toggle 0/1] -- Idle non-commander builders fall back to
//   assisting nearby work; 0 leaves them to the engine's own offers.
// manager/assist.as [elmos] -- THE TERMINAL RUNG SEARCHES WIDE: a walk beats
//   standing idle for the rest of the game, which is what 2,434 idle-still
//   samples...
// manager/builder/obsolete.as [seconds] -- A fresh nano turret is exempt from
//   the useless-cluster reclaim check for this long, so a cluster still being
//   seeded is not eaten.
// manager/builder/nano.as -- NOT the 24-elmo footprint: the engine grid
//   (Pos2BuildPos) only lets an odd-footprint centre sit every 16 elmos, so a
//   24 pitch...
// manager/builder/nano.as [metal/s] -- No nano turrets below this metal
//   income; below it they measured as taking metal from the expansion that
//   would pay for more of them.
// manager/builder/nano.as [elmos] -- Search radius around the existing block's
//   centre for the next nano turret's site.
// manager/builder/nano.as [metal] -- A structure must cost at least this much
//   to count as the big build that justifies siting a nano next to it.
// manager/builder/nano.as [elmos] -- With another turret within this range, a
//   new nano snaps to its cardinal neighbour slot at footprint pitch so blocks
//   form a perfect grid.
// manager/builder/nano.as [metal] -- Reachable non-turret structure value that
//   must stand within a nano's reach before one is built -- by value, not
//   existence.
// manager/builder/statics.as [fraction 0-1] -- A nano cluster at least this
//   far forward (base->enemy) attracts pulsars built at lathe speed beside it;
//   rear clusters fall through to front-line siting.
// manager/builder/requests.as [metal] -- Workers allowed on one build site:
//   one more per this much of the building's cost -- past that another pair of
//   hands beats opening the next site less.
const float TUNE_SITE_COST_PER_WORKER = 300.f;

// ---------------------------------------------------------------------------
// Expansion — mexes, upgrades, claims
// ---------------------------------------------------------------------------
// manager/builder/mexwork.as [elmos] -- Radius around home in which T1 mexes
//   count as home mexes still awaiting their Moho upgrade.
// manager/brain.as [metal/s] -- Below this income a pending mex upgrade
//   outranks every other advanced-constructor want; past it the ranking
//   decides (one upgrade still always runs).
// manager/builder/rules_optional.as [elmos] -- Mex chaining only applies to
//   builders at least this far from home; near home the normal ladder is fine.
// manager/builder/rules_optional.as [elmos] -- A just-finished mex chains
//   straight into the next open spot only within this range -- a far spot is a
//   new decision.
// manager/brain.as [seconds] -- After finding no reachable open mex spot, the
//   mex want stays quiet for this long before scanning again.
// manager/builder/rules_commander.as [toggle 0/1] -- The commander plants
//   most of the early mexes; MexGuard (inside the !isComm block below) does
//   not cover it, so this handles ANY...
// manager/brain.as [ratio] -- Mex want multiplier at a drained bank (under 5%
//   of storage) -- a drained bank is the strongest case for more income.
// manager/brain.as [threat] -- Enemy threat a mex spot may carry and still be
//   claimed -- the same bar a constructor is already allowed to walk to work
//   at.
// manager/builder/maketask.as [elmos] -- A mex offer farther than this is
//   swapped for a nearer open spot at election time; the far spot returns to
//   the pool for whoever is close.
// manager/builder/opening.as [elmos] -- Bounds the post-opening factory-
//   rebuild mex fallback in rules_commander.as (a mex must be genuinely close
//   to be worth taking...
// manager/builder/rules_offer.as [toggle 0/1] -- Take the engine's own mex
//   offer before any optional want gets a turn; 0 restores the old ordering.
// manager/builder/rules_hold.as [toggle 0/1] -- A builder walking past an
//   unclaimed mex spot swings through it first when the detour is short; 0
//   disables.

// ---------------------------------------------------------------------------
// Build phases (manager/factory/phase.as ComputePhase)
//
// BUILD_PHASE 0-7 gates WHICH one-off structures are allowed; it is recomputed
// every update from live state and never latched, so losing a fusion or a
// gantry drops the phase back down. Phases 3-4 and 6-7 are decided by tech
// (RushReady / owning an advanced plant / a gantry), not by these numbers.
// The army-vs-economy RATIO is a separate system -- see targets.as.
// ---------------------------------------------------------------------------
// manager/factory/phase.as [metal/s] -- phase 1 "expand": the economy exists
// manager/factory/phase.as [metal/s] -- phase 2 "build up": ~four T1 mexes
// manager/factory/phase.as [metal/s] -- phase 5 "pre-T3" without a fusion yet

// ---------------------------------------------------------------------------
// Factories, tech, quotas
// ---------------------------------------------------------------------------
// manager/air/factory.as [metal/s] -- One T2 air constructor recruited per
//   this much metal income -- a count that scales, never a cap (air cons have
//   no ground hitbox to crowd the base).
// manager/brain.as [metal] -- Enemy T3/heavy value that doubles the weight of
//   our counters (bombers, pulsars, own titans) in the ranking; more enemy T3
//   keeps scaling it.
// manager/builder/mexguard.as [metal/s] -- Metal income from which heavy-
//   defence picks include the T2 popup (Gauntlet/Viper class) -- shot density
//   spread over several guns, not one alpha target.
// manager/builder/mexguard.as [metal/s] -- Metal income from which the big
//   guns (Doomsday class) enter the heavy-defence pick, each still requiring
//   its popup escort first.
// manager/air/wing.as [ratio] -- The advanced air plant waits until army spend
//   reaches this fraction of its target share -- a luxury while the army is
//   starved, unless the enemy actually flies.
const float TUNE_EXTRA_PLANT_ARMY = 0.85f;
// manager/brain/facqueue.as [count] -- Orders the facqueue keeps queued ahead
//   on each driven factory line.
// manager/factory/hooks.as [count] -- Recruit tasks allowed in flight per
//   factory before the queue counts as full (CircuitAI's own number, exposed
//   for A/B).
const float TUNE_FAC_QUEUE = 2.f;
// manager/brain/facqueue.as [toggle 0/1] -- The Brain drives every factory
//   line (quota-based orders, factory.json bypassed); 0 returns the lines to
//   stock CircuitAI.
const float TUNE_FAC_QUEUE_BRAIN = 1.f;
// manager/builder/statics.as [metal/s] -- No front-line pulsar fortresses
//   below this metal income.
// manager/builder/statics.as [metal/s] -- One front-line pulsar wanted per
//   this much metal income (plus one).
// manager/military/posture.as [power] -- Attack quota set while the killing
//   blow is on -- concentrate the push, do not disperse. Skipped for the eco
//   lead, whose army is deliberately tiny.
const float TUNE_KILL_QUOTA = 300.f;
// manager/brain/mix.as [ratio] -- Scales how far the SEEN enemy composition
//   pulls our role mix toward its counters; 0 keeps the targets.as table
//   fixed.
// manager/brain/facqueue.as [toggle 0/1] -- The facqueue includes scouts in
//   its per-line quota when a scout is worth it; 0 removes scouts from the
//   quota.
// manager/factory/choose.as [curve] -- T1 plant-count curve intercept: plants
//   wanted = A + B x ln(income), floor 1.
// manager/factory/choose.as [curve] -- T1 plant-count curve slope -- see
//   apex_plants_t1_a.
// manager/factory/choose.as [curve] -- T2 plant-count curve intercept: plants
//   wanted = A + B x ln(income), floor 1. At -5.8/1.737 the second T2 line
//   clears at ~90 m/s, the third at ~160.
// manager/factory/choose.as [curve] -- T2 plant-count curve slope -- see
//   apex_plants_t2_a.
// manager/factory/choose.as -- 100, was 150: apexearth 2026-08-15, on losing
//   long 8v8s with a T3 deficit (751k vs 1.3M fielded): "we're probably
//   losing just...
// manager/factory/choose.as -- A PHANTOM DIES FAST.
// manager/factory/choose.as [seconds] -- A plant request expires after this
//   long un-started (its builder likely died) so the tech path is not dammed
//   forever.
// manager/brain/facqueue.as [ratio] -- Per-def quota multiplier for the Legion
//   Goblin (below 1 = fewer than the role share would give).
// manager/brain/facqueue.as [ratio] -- Per-def quota multiplier for the Legion
//   Lobber (above 1 = more than the role share would give).
// manager/brain/facqueue.as [metal] -- Cost normalizer for core-unit quotas:
//   wants are metal shares, so a unit's count target is (core wanted x this /
//   its cost).
// manager/brain/facqueue.as -- The cut PHASES IN with the T2 army actually
//   fielded, not the plant standing: apexearth, watching the transition --
//   "we end up...
// manager/brain/facqueue.as [ratio] -- Weight every T1 combat want keeps once
//   a gantry stands. Not zero on purpose: T1 chaff screens the slow T3 era.
// manager/brain/facqueue.as [ratio] -- Weight every T2 combat want keeps once
//   a gantry stands.
// manager/brain/facqueue.as [ratio 0..1] -- Army mix the designated tech/eco
//   lead's lines keep, per tier. 0 = the lead plays TECH like a human: no
//   army, its own and the slung metal all go to economy (apexearth
//   2026-08-22). Team games only; air lines exempt.
// manager/military/defenceline.as + builder/requests.as [toggle] -- May the
//   eco/tech role holder build defence? 0 = none (his call: it sits safely
//   in the back); sensors are exempt.
// manager/builder/share.as [count] -- Adv cons the lead keeps for itself
//   while teammates still lack theirs. 1 = deliver the paid-for cons first.
// manager/builder/share.as [income multiplier] -- At or above this handicap
//   multiplier (1.5 = +50) the lead gifts NO cons: bonused teammates afford
//   their own, and the lead's build power is its scaling.
// manager/factory/choose.as + builder/requests.as [count] -- Fusions the eco
//   role must own before it may rebuild a T1 plant (his call: eat both T1
//   labs at the T2 plant, recreate one only after the second fusion).
// manager/brain/facqueue.as [metal/s per con] -- Pre-T2 the eco role's con
//   want is one per this much steady income (7 = one lathe's pull), so con
//   bodies never outrun the metal that feeds them.
// manager/factory/techlead.as [e/s] -- Energy bar for the eco role's T2
//   commit. Below the follower bar (600): the critical path to 2-fusions-by-10
//   is lab-done -> adv con -> 4300-metal build (~3.1m measured). 450 was
//   tried and measured WORSE (tech 8.4m vs 6.8/7.0 at 600, seed-47): a lab
//   started on a thinner grid E-stalls the mohos that follow it. 600 stands.
// manager/role.as [fraction] -- The build-power controller's target:
//   standing lathe (metal/s) tracks income x this. Slightly above 1 so the
//   bank drains instead of pooling. The controller's ONLY policy numbers
//   are this and the trim slack -- everything else is unit physics.
// manager/role.as [fraction] -- BP above target x this is excess; the
//   land-con retirement sweep keys on it (post-fusion-2 stage).
// manager/role.as [fraction] -- The role's fusion bar as a fraction of
//   apex_fusion_prefer_income. 0.6 x 50 = 30 m/s steady: the reactor starts
//   while a fighting player would still be buying army.
// manager/builder/rules_hold.as [count] -- Extra same-def builds SHIFT-queued
//   behind a started cheap ENERGY/CONVERT build. DEFAULT OFF: measured
//   2026-08-22 (seed-37 paired, 3 on-runs vs 1 off-control), the off-control
//   out-ecoed every on-run (46.1k vs 32.4-40.3k) -- ring-picked sites and
//   election holds cost more than the think-gaps saved. The binding and rule
//   stay for a placement-aware retry.
// manager/builder/rules_hold.as [metal] -- Only defs at or under this cost
//   chain (wind 43, solar 155, advsol 350, converter 380).
// manager/factory/techlead.as [toggle 0/1] -- Default ON since 2026-08-20:
//   paired same-seed A/Bs on Altair (trade 0.31->0.52) and Comet Catcher
//   (0.43->0.76, produced...
// manager/factory/techlead.as [map units] -- T1-commit (skip T2, end the game
//   at T1) only arms on 1v1 duels on maps up to this area (Comet Catcher is
//   192, Prismatic 256).
// manager/factory/techlead.as [metal/s] -- An economy at this income did not
//   end the game at T1 -- the T1 commit expires and normal teching resumes.
// manager/factory/choose.as [count] -- Land plants the T1 commit may hold
//   before the freed metal belongs to units, not more plants (air labs never
//   join a commit).
// manager/brain/facqueue.as [count] -- Floor on T1 core combat units counted
//   as protected, whatever the income.
// manager/brain/facqueue.as [ratio] -- Weight T1 core wants keep once T2
//   exists -- late Thug-class T1 is expensive and not worthwhile; the trimmed
//   metal flows to T2 army and rezbots.
// manager/factory/techlead.as [ratio] -- The T1 commit reads its economy as
//   plateaued when income has not grown past peak times this within the
//   plateau window.
// manager/factory/techlead.as [seconds] -- How long income may sit below the
//   growth bar before the T1 commit converts to normal teching -- the trigger
//   is the economy's own derivative, not a clock.
// manager/military/killingblow.as [ratio] -- During a T1 commit, all-in push
//   once our army is this multiple of the enemy's massed value (wide
//   hysteresis so fog wobble cannot flap it).
const float TUNE_T1_PUSH_EDGE = 1.2f;
// manager/military/killingblow.as -- WIDE hysteresis, or it is not "all or
//   nothing".
const float TUNE_T1_PUSH_OFF = 0.5f;
// manager/factory/techlead.as [metal] -- Seeing a mobile enemy unit at least
//   this expensive (T2-class; never the commander) releases the T1 commit.
// manager/military/posture.as [toggle 0/1] -- Hold the aggressive posture
//   while still short of the T1 army the advanced plant is gated on; closes
//   itself once T2 exists.
const float TUNE_T2_ARMY_HOLD = 1.f;
// manager/factory/techlead.as [ratio] -- T1 army value required before the
//   advanced plant, as a multiple of metal income (per-instance persona bias
//   so allies do not all tech at once).
// manager/brain/facqueue.as [count] -- Floor on T2 core combat units counted
//   as protected, whatever the income.
// manager/builder/rules_optional.as [toggle 0/1] -- Site the first advanced
//   plant at the protected rear of the base; 0 leaves siting to the ordinary
//   search.
// manager/builder/rules_optional.as [elmos] -- How far behind the base centre
//   the rear-sited advanced plant stands.
// manager/factory/choose.as [seconds] -- A T2 transition with no nanoframe
//   standing re-orders its plant after this long -- one re-order per window.
// manager/factory/factorydefs.as [metal or metal/s] -- T3 is this variant's
//   declared win condition -- hold cheaply, out-eco behind the wall, then
//   finish with T3.
// manager/factory/factorydefs.as -- Metal income above which the gTurtle and
//   army-ratio vetoes stop applying, so a gantry gets placed even while we
//   are losing --...

// ---------------------------------------------------------------------------
// Military — stance, engagement, squads
// ---------------------------------------------------------------------------
// manager/brain.as [ratio] -- While outfielded, army wants scale by our/their
//   army ratio, floored here so a massacre cannot zero army production.
// manager/brain/facqueue.as [ratio] -- Core-army wants multiply by this while
//   we are losing ground or the base is contested; relaxes the moment the
//   pressure clears.
// manager/builder/converter.as [influence] -- Enemy influence at our own base
//   above which the base counts as under attack (converter placement pauses).
const float TUNE_BASE_ATTACK_INFL = 10.f;
// manager/military/deathledger.as [ratio] -- How hard bleeding forward (dying
//   on their ground) raises the engage caution -- multiplies the same margin
//   personality uses.
const float TUNE_BLEED_ENGAGE = 2.f;
// manager/builder/rules_commander.as [ratio] -- With enemy T2 seen, the
//   commander hides once enemy massed threat reaches this multiple of our
//   army.
// manager/builder/events.as [elmos] -- Minimum gap kept between allied
//   commanders; a nearer ally commander steers ours away.
// manager/military/massing.as [ratio] -- How much enemy STATIC defence counts
//   when deciding to leave home (0 = ignore porc when judging their mobile
//   mass; it still counts fully for attacking into it).
const float TUNE_FEED_STATIC_W = 0.f;
// manager/military/massing.as [ratio] -- The forward-suppression lifts when
//   our massed pool outweighs the enemy actually defending the ground it
//   stands on by this factor -- that is a fight we are winning.
const float TUNE_LOCAL_EDGE = 1.3f;
// manager/military/massing.as [toggle 0/1] -- Enable the local-edge exception
//   above; 0 keeps the suppression unconditional.
const float TUNE_LOCAL_EDGE_ON = 1.f;
// manager/military/massing.as [elmos] -- What is actually defending the
//   ground we stand on: enemy group value within reach of the lane, not every
//   enemy on the map.
const float TUNE_LOCAL_EDGE_R = 2200.f;
// manager/military/deathledger.as [ratio] -- How hard loss pressure (army
//   eaten faster than it eats back) tilts the budget toward ARMY.
const float TUNE_LOSS_ARMY = 2.f;
// manager/military/deathledger.as [ratio] -- Cap on the loss-pressure army
//   tilt, so a massacre cannot starve the economy that pays for the rebuild.
const float TUNE_LOSS_ARMY_CAP = 1.7f;
// manager/military/massing.as [ratio] -- The ceiling scales with the floor: a
//   flat MASS_CAP of 48 sits BELOW the army-scaled floor past ~14k of
//   standing army, which...
const float TUNE_MASS_CAP_MULT = 2.5f;
// manager/military/massing.as [ratio] -- Commit partway toward the cap, NOT
//   at the floor: expiring straight to the floor sent a 20%-of-army group
//   into the exact mass...
const float TUNE_MASS_COMMIT_FRAC = 0.5f;
// manager/military/massing.as [power] -- Degenerate-case floor on the massing
//   bar (~2 Pawns) for an army of nearly nothing; the real size is the share
//   of standing army.
const float TUNE_MASS_FLOOR = 5.f;
// manager/military/massing.as [seconds] -- Bound the hold.
const float TUNE_MASS_HOLD_SECS = 240.f;  // 120 expired into under-strength commits ('committing at 29'); patient pools trade better
// manager/military/massing.as [ratio] -- The massing floor is also bounded
//   below by the biggest enemy group we can see, times this -- a pool that
//   cannot meet it does not go.
const float TUNE_MASS_MEET_FRAC = 1.3f;   // meet the biggest seen group with EDGE: 1.0 sent even fights that lost (K/D 0.43, easy ladder)
// manager/military/massing.as [ratio] -- Feeding guard: while enemy mobile
//   mass exceeds ours by this factor (and no local edge), the pool holds
//   instead of trickling into them.
const float TUNE_MASS_NO_COMMIT_RATIO = 2.f;
// manager/military/massing.as [ratio] -- Massing bar as a share of our own
//   standing army (metal to power); 0.012 is ~70% of the army per group -- one
//   force that wins its fight, not two that lose.
const float TUNE_MASS_PER_ARMY = 0.012f;
// manager/military/massing.as [toggle 0/1] -- Sized against what the group
//   can actually kill, not against the enemy's whole army: comparing to their
//   total army answers "can...
const float TUNE_MASS_VS_ARMY = 1.f;
// manager/military/massing.as [ratio] -- While ahead, the massing bar also
//   rises to this fraction of per-ally enemy mobile threat.
const float TUNE_MASS_VS_ENEMY = 0.5f;
// manager/builder/statics.as [ratio] -- Defences answering an incoming push
//   are sized to this fraction of the incoming metal (guns trade up, so a
//   fraction is parity).
// manager/military/basedefence.as [elmos/s] -- How fast an enemy group must be
//   closing on the base to count as an incoming push.
const float TUNE_INCOMING_CLOSING = 150.f;
// manager/military/basedefence.as [metal] -- Minimum enemy group value to
//   register as an incoming push.
const float TUNE_INCOMING_COST = 2500.f;
// manager/military/basedefence.as [metal] -- An enemy group at least this
//   expensive inside its own range (plus pad) of our fence is the danger
//   signal.
const float TUNE_INCOMING_DANGER_COST = 800.f;
// manager/military/basedefence.as [elmos] -- Padding added to the enemy
//   group's own weapon range when testing whether it already threatens the
//   base edge.
const float TUNE_INCOMING_DANGER_PAD = 500.f;
// manager/military/posture.as [ratio] -- Team army advantage that KEEPS a
//   running push alive (hysteresis under apex_push_team_ratio, so one trade at
//   the line does not flap it).
const float TUNE_PUSH_KEEP = 1.25f;
// manager/military/basedefence.as [elmos] -- Radius around the base within
//   which enemy groups are evaluated as a possible incoming push.
const float TUNE_INCOMING_NOTICE_R = 4500.f;
// manager/builder/statics.as [elmos] -- Farthest forward of home that push-
//   answer defences may stand (halfway to the attacker, capped here).
// manager/military/posture.as -- RAID_MIN_EARLY=45 was "hold them home" made
//   permanent: ~2,600 metal of raiders had to pool before ONE raid could
//   leave pre-T2,...
const float TUNE_RAID_PACK = 8.f;
// manager/military/posture.as [ratio] -- Raid packs grow with the economy:
//   pack power is the base plus income times this, so packs form instead of
//   never reaching a fixed bar.
const float TUNE_RAID_PER_INCOME = 0.2f;
// manager/builder/fusion.as [elmos] -- Chain reach between reactors: a spot
//   within this of standing reactors counts as part of the same chain.
// manager/military/posture.as [seconds] -- EXPERIMENT, default off. A no-
//   retreat bar at units cheaper than this many seconds of income measured
//   army K/D 0.33 to 0.11 (retreat is also disengage-and- repair).
const float TUNE_RETREAT_COST_SECS = 0.f;
// manager/builder/statics.as [ratio] -- Energy income must cover a shield
//   dome's regen draw times this before one is built.
// manager/builder/defcap.as [toggle 0/1] -- Use the explicit siege latch for
//   dig-in decisions; 0 falls back to BaseContested.
const float TUNE_SIEGE = 0.f;
// manager/brain.as [exponent] -- Softness of the siege-reach penalty curve on
//   distant builds while besieged (higher = sharper falloff).
// manager/military/stance.as [toggle 0/1] -- Stance (aggressive/passive) moves
//   the budget shares; 0 lets stance read but never act, for isolation A/Bs.
const float TUNE_STANCE = 1.f;
// manager/military/stance.as [ratio] -- ARMY share multiplier while the stance
//   is AGGRESSIVE (base being hit or pressured).
const float TUNE_STANCE_AGGRO_ARMY = 1.25f;
// manager/military/stance.as [ratio] -- DEFENCE share multiplier while
//   AGGRESSIVE.
const float TUNE_STANCE_AGGRO_DEF = 1.3f;
// manager/military/stance.as [ratio] -- ECONOMY share multiplier while
//   AGGRESSIVE (below 1: guns before growth while under attack).
const float TUNE_STANCE_AGGRO_ECO = 0.85f;
// manager/military/stance.as [ratio] -- ARMY share multiplier while PASSIVE
//   (enemy visibly quiet): greed trims army to grow faster.
const float TUNE_STANCE_GREED_ARMY = 0.85f;
// manager/military/stance.as [ratio] -- ECONOMY share multiplier while
//   PASSIVE.
const float TUNE_STANCE_GREED_ECO = 1.3f;
// manager/military/stance.as [pressure] -- Raid pressure above which the
//   stance turns AGGRESSIVE even without base contact.
const float TUNE_STANCE_PRESSURE = 1.2f;
// manager/military/stance.as [ratio] -- 1v1 only: freshly seen enemy army
//   above ours times this reads as an aggressive rival (in teams, only threat
//   to OUR ground counts).
const float TUNE_STANCE_RIVAL = 0.7f;
// manager/military/stance.as -- SPLIT THRESHOLDS, or the boundary lives
//   inside fog noise: one 60m game flapped 47 times at a single 0.2 bar.
const float TUNE_STANCE_SEEN_HI = 0.25f;
// manager/military/stance.as [ratio] -- Fresh enemy sighting below this
//   fraction of the seen-peak reads as their army having died off (exits
//   PASSIVE).
const float TUNE_STANCE_SEEN_LO = 0.08f;
// manager/military/stance.as [metal] -- Absolute floor on what counts as
//   seeing the enemy army: passive requires eyes on a SQUAD, not one scout
//   flickering through LOS.
const float TUNE_STANCE_SEEN_MIN = 300.f;
// manager/military/superguard.as [metal] -- Mobile non-flying units at least
//   this expensive get a super escort (guards travel with them) even without
//   the SUPER role.
const float TUNE_SUPER_COST = 7000.f;
// manager/military/superguard.as [toggle 0/1] -- Supers travel with an escort
//   instead of stock's one solo attack task each; 0 is the control arm.
const float TUNE_SUPER_GUARD = 1.f;
// manager/military/superguard.as [ratio] -- Held supers stop waiting for an
//   army once they ARE this share of our whole army value -- two titans by a
//   hill are the army.
const float TUNE_SUPER_SELF_FRAC = 0.4f;
// manager/military/deathledger.as [ratio] -- Kill/loss ratio below which we
//   are trading badly enough to change posture.
const float TUNE_TRADE_BAD = 0.6f;
// manager/military/deathledger.as [seconds] -- Recent losses must be worth
//   this many seconds of income before the trade ratio is trusted at all.
const float TUNE_TRADE_VOL = 20.f;
// manager/military/withdraw.as [toggle 0/1] -- ATTACK/RAID squads come home
//   while the base is under attack and no killing blow is committed, instead
//   of continuing to roam; 0 disables the recall (they keep fighting wherever
//   their task sends them).
const float TUNE_RECALL_HOME = 1.f;
// manager/military/withdraw.as [fraction 0-1] -- Only squads this far past
//   our own territory (ForwardFraction) are recalled -- units already fighting
//   near home need no order, they are already where they are needed. Matches
//   the threshold sentinel.as already uses to call the same thing a CONCERN.
const float TUNE_RECALL_HOME_FWD = 0.5f;
// manager/military/withdraw.as [toggle 0/1] -- Units on clearly-lost ground
//   pull back behind the nearest fence tower; 0 disables the withdraw system.
const float TUNE_WITHDRAW = 1.f;
// manager/military/withdraw.as [elmos] -- Radius in which allied power counts
//   toward a unit's local odds when judging whether to withdraw.
const float TUNE_WITHDRAW_ALLY_R = 600.f;
// manager/military/withdraw.as [elmos] -- How far behind the sheltering tower
//   (toward home) a withdrawing unit stands.
const float TUNE_WITHDRAW_BEHIND = 220.f;
// manager/military/withdraw.as [influence] -- Ground counts as clearly losing
//   when net influence (ally minus enemy) is below minus this.
const float TUNE_WITHDRAW_INFL = 1.f;
// manager/military/withdraw.as -- Already behind the guns: nothing to do but
//   fight.
const float TUNE_WITHDRAW_NEAR = 300.f;
// manager/military/withdraw.as [ratio] -- Withdraw when local enemy threat
//   exceeds our local strength times this.
const float TUNE_WITHDRAW_ODDS = 1.5f;
// manager/military/withdraw.as [seconds] -- A withdrawing unit's pull-back
//   order is re-issued at most once per this interval.
const float TUNE_WITHDRAW_REISSUE = 6.f;

// COMBAT BEHAVIOUR -- promoted from hardcoded constants 2026-08-21 so the
// engagement maths is tunable. Same defaults as the constants they replace.
//
// manager/military/roles.as [ratio] -- metal-vs-metal army ratio (ours/theirs)
//   at which the massed pool starts attacking; 1.0 is true parity, below it we
//   attack while slightly behind.
const float TUNE_ATTACK_EDGE = 0.95f;
// manager/military/posture.as [metal] -- units at or under this cost are
//   fodder: exempt from massing, always sent forward (their job is vision and
//   pulled fire). Cost AND role, so cheap AA/bombers are not swept in.
const float TUNE_FODDER_COST = 100.f;
// manager/brain/facqueue.as [metal/s] -- One standing spam unit (tick/scout
//   car class) wanted per this much metal income, post-T2: the constant
//   cheap-eyes stream that takes fire instead of the army.
// manager/brain/facqueue.as [metal] -- One mobile artillery wanted per this
//   much SEEN enemy static metal: the wall itself sizes the battery that
//   answers it. 0 disables the wall-arty demand.
// Seen enemy static metal above which the front fence escalates to the
// Punisher tier (armguard/corpun/legcluster). 0 disables the escalation.
// manager/military/massing.as [ratio] -- killing blow: once OUR TEAM's army
//   value is this multiple of theirs, attack continuously and release any
//   turtle -- even a partial commitment outnumbers everything they field.
const float TUNE_KILL_EDGE = 1.8f;
// manager/military/killingblow.as [seconds] -- killing blow: earliest the
//   normal (non-T1-commit) gate may arm. A clock, not an economy reading, and
//   the only one left in the blow -- it exists so a fog-driven army estimate
//   in the opening cannot commit the whole army. Tunable so the cost of
//   holding it can be measured against a faster finish.
const float TUNE_KILL_FROM = 900.f;
// manager/military/massing.as [seconds] -- half-life of gSeenPeak, the largest
//   enemy massing threat ever seen at once. It is the denominator of the
//   killing blow and the massing floor, so how fast it forgets decides how long
//   a destroyed enemy army keeps holding us back from committing.
//   MEASURED 2026-08-22: 180s (the 3-minute figure the old comment claimed)
//   was WORSE -- two paired 50-minute runs against medium, 16 and 8 games, both
//   lost win rate and army trade against the effectively-frozen peak. Kept
//   near-frozen as the default; the frame-based decay below is the correctness
//   fix, not a behaviour change.
const float TUNE_SEEN_HALFLIFE = 300.f;
// manager/brain/budget.as [toggle 0/1] -- evaluate the SPEND_* target curves
//   against live income (1) or against the frame-0 column (0). GetTunable
//   caches its default on first call, so passing a live curve as the default
//   froze every share at income 0 -- and SPEND_ARMY's income-0 column is 0.0,
//   which is why the ARMY budget row read zero in every game ever played.
//   Default 0 reproduces that measured behaviour; see budget.as for the runs.
const float TUNE_BUDGET_LIVE = 0.f;
// manager/military/massing.as [metal] -- killing blow needs at least this much
//   enemy army value on the books; ratios off a tiny sample are noise.
const float TUNE_KILL_FLOOR = 20000.f;
// manager/military/roles.as [ratio] -- enemy/our army ratio at or above which
//   we stop attacking entirely and let them come to the defences.
const float TUNE_MASS_HOLD_RATIO = 1.5f;
// manager/military/roles.as [power] -- ceiling on the massing bar so "wait for
//   a bigger group" cannot postpone attacking forever.
const float TUNE_MASS_CAP = 48.f;
// manager/military/posture.as [ratio] -- odds multiplier while the team push
//   is on; 0.55 roughly halves the surplus the engage test demands.
const float TUNE_PUSH_BOOST = 0.55f;
// manager/military/posture.as [power] -- attack quota while pushing; keeps the
//   push concentrated instead of dribbling in.
const float TUNE_PUSH_QUOTA = 200.f;
// manager/military/posture.as [metal] -- no team push below this much own army
//   value; a "ratio" over two scouts means nothing.
const float TUNE_PUSH_MIN_ARMY = 2500.f;
// manager/military/posture.as [ratio] -- team army advantage that STARTS the
//   all-in push. Deliberately above the per-squad engage margin: this spends
//   the whole army at once. Held while above apex_push_keep.
const float TUNE_PUSH_TEAM_RATIO = 1.6f;
// manager/military/basedefence.as [power] -- early-game floor for raiders held
//   home on defence.
const float TUNE_RAID_MIN_EARLY = 45.f;
// manager/military/basedefence.as [seconds] -- how long a raid stays "current"
//   in the raid-pressure memory; a raid is current, not history.
const float TUNE_RAID_TAU = 60.f;
// manager/military/roles.as [power] -- attack quota to hold while the team's
//   T2 rush window is open: defend and stall, not do-nothing (400 would mean
//   never attack).
// manager/military/roles.as [power] -- attack quota for the rest of the game
//   once the rush window is over; set above any realistic standing army so the
//   engage test (the odds), not the quota, decides.
// manager/military/roles.as [ratio] -- how much enemy STATIC defence counts in
//   the massing decision, per metal. Half weight: a turret cannot retreat or
//   redeploy; full weight would let a porc base pin the quota forever.
const float TUNE_STATIC_DEFENSE_WEIGHT = 0.5f;
// manager/military/posture.as [ratio] -- engage bias while an advanced plant
//   is under construction; above 1 is cautious. Raises only the bar to START
//   a fight -- fights already joined and defence are untouched.
const float TUNE_T2_HOLD_BOOST = 1.60f;

// ---------------------------------------------------------------------------
// Defence, towers, AA, insurance
// ---------------------------------------------------------------------------
// manager/builder/statics.as [ratio] -- AA top-up sized to the enemy's air:
//   extra AA guns = seen enemy air value times this, divided by the gun's
//   cost.
// manager/military/defenceline.as [ratio] -- How fast the defence allowance
//   grows per unit of enemy/our army ratio beyond the trigger -- outfielded
//   means more guns.
// policy.as [metal or metal/s] -- Antinukes and shield domes are INSURANCE:
//   real once the threat class exists, premature at eco-opening scale
//   (apexearth...
const float TUNE_ANTINUKE_INCOME = 60.f;
// manager/brain/facqueue.as [metal] -- One torpedo unit wanted per this much
//   seen enemy submarine value (plus one).
// manager/brain/nukes.as [elmos] -- Radius an antinuke counts as covering
//   (2500 is the interceptor coverage radius in this game tree).
// manager/brain.as [count] -- Extra antinukes held beyond the computed need
//   once an enemy silo has actually been seen.
// manager/brain.as [seconds] -- Interceptor reload time (the def's value,
//   carried as a tunable because reload is not bound to script); antinukes
//   wanted derives from it.
// manager/air/update.as [metal] -- Bombers join home-base defence only while
//   seen enemy AA value is below this -- against flak trucks they would just
//   die.
const float TUNE_BOMB_DEFEND_AA = 1000.f;
// manager/brain.as [toggle 0/1] -- Front-line guns prefer chokepoints, placed
//   a step behind the choke so they shoot into it; 0 uses the plain line.
// manager/builder/rules_commander.as [ratio] -- The commander turns cautious
//   once seen enemy heavy/super value reaches this fraction of his own cost.
// manager/military/hooks.as [toggle 0/1] -- Chargers (beeline supers) defend
//   home instead of striking while the base is being hit; 0 lets them keep
//   charging.
const float TUNE_DEFEND_HOME = 1.f;
// manager/military/withdraw.as [fraction 0-1] -- A DEFEND-task unit farther
//   forward than this (on losing ground) is recalled first -- it is in the
//   wrong place by the task's own meaning.
const float TUNE_DEFEND_LEASH = 0.55f;
// manager/builder/statics.as [seconds] -- Front towers pick the dearest gun
//   costing at most this many seconds of metal income; the basic tower stays
//   the unconditional floor.
// manager/brain.as [metal] -- Normalizer for assets-behind in tower placement
//   value: a tower guarding this much structure value doubles its score.
// manager/brain.as [ratio] -- Weight of recently lost towers near a spot in
//   its placement value -- ground that eats towers argues for a stronger
//   answer.
// manager/military/defenceline.as [toggle 0/1] -- Being attacked raises the
//   budget; it does not remove it -- returning true outright while contested
//   switched the gate off...
// manager/brain.as [ratio] -- A tower's counted reach is capped at the light
//   tower's range times this, so one big gun cannot claim the whole line is
//   covered.
const float TUNE_DEF_REACH_CAP = 6.0f;
// manager/builder/defcap.as [ratio] -- Share of builders allowed on defence
//   work at once; 1 disables the cap.
// manager/military/defenceline.as -- apexearth's number, not a derived one.
// manager/military/hooks.as [seconds] -- How long a lost fence tower stays
//   fresh in the loss memory; positions that keep eating towers score higher
//   for replacements.
const float TUNE_FENCE_LOSS_MEMORY = 180.f;
// manager/military/airthreat.as [metal/s] -- Metal income from which one flak
//   is always held around the base, whatever the seen air threat.
const float TUNE_FLAK_FLOOR_INCOME = 60.f;
// manager/military/airthreat.as [metal/s] -- One further baseline flak per
//   this much income beyond the floor bar.
const float TUNE_FLAK_PER = 60.f;
// manager/builder/statics.as [metal/s] -- From this income flak is sited on
//   the border/front line; below it base placement remains the answer.
// manager/military/posture.as [fraction 0-1] -- While trading badly, the
//   army's staging anchor pulls back to this fraction of the way from home
//   toward the enemy.
const float TUNE_LANE_DEFENSIVE = 0.15f;
// manager/military/defenceline.as [ratio] -- In team games the designated tech
//   lead scales its defence allowance by this (its allies hold the line);
//   never applies in 1v1.
// manager/military/defenceline.as [ratio] -- Share of the defence allowance
//   reserved for LOCAL guards (mex guards, dig-ins) as opposed to holding the
// manager/military/defenceline.as [ratio] -- Multiplier on the front-line
//   defence budget share; the choke-map experiment lever (the computed share
//   is ~3.6% of spend at pressure 1 while stock wins chokes at ~25%).
// manager/brain.as [ratio] -- Thickening value scale once the front line is
//   fully covered: the fence want keeps buying DEPTH at the least-covered
//   stretch while the defence budget is under target, at this fraction of a
//   bare-line tower's value. 0 restores coverage-only fencing.
//   front line.
// manager/brain/nukes.as [count] -- Offensive targets are assumed to hide at
//   least this many antinukes once the game is old enough -- an unseen anti is
//   still an anti.
// manager/brain/nukes.as [ratio] -- Score multiplier for DEFENSIVE nuke
//   targets (enemy groups on our ground) over offensive ones.
// manager/brain/nukes.as [fraction 0-1] -- Defensive targets closer to home
//   than this forward-fraction are skipped -- do not nuke our own base.
// manager/builder/mexguard.as [ratio] -- A guard tower is obsolete once the
//   top gun costs more than this times the tower and is affordable -- big guns
//   cover that ground instead.
const float TUNE_PORC_OBSOLETE_RATIO = 7.f;
// manager/builder/mexguard.as [seconds] -- The top gun counts as affordable
//   for the porc-obsolete test when it costs at most this many seconds of
//   income.
const float TUNE_PORC_OBSOLETE_SECS = 20.f;
// manager/brain.as [ratio] -- Pulsar want multiplier while the enemy fields T3
//   and we have no gantry producing an answer.
// manager/builder/statics.as [count] -- Pulsars per block: guns pack shoulder-
//   to-shoulder until a block reaches this size, then the next block starts
//   elsewhere.
// manager/builder/statics.as [fraction 0-1] -- Only blocks at least this far
//   forward attract more guns -- T3 defence behind our own factories is left
//   alone.
// manager/builder/statics.as [elmos] -- Radius that counts as inside an
//   existing pulsar block.
// manager/builder/statics.as [count] -- Concurrent pulsar builds allowed while
//   the metal bank is full (the throttle the base cap normally applies lifts).
// manager/brain.as [ratio] -- Pulsar want multiplier at a full metal bank --
//   the surplus is what the line of guns is for.
// manager/builder/statics.as [metal/s] -- One pulsar allowed per this much
//   metal income (plus one) -- income- derived, not a flat number.
// manager/builder/statics.as [metal/s] -- One additional in-flight shield dome
//   allowed per this much income -- at LRPC-era income the pace, not the
//   count, was the bottleneck.
// policy.as [metal/s] -- Metal income before shield domes are insurance worth
//   buying (a seen threat still overrides).
const float TUNE_SHIELD_INCOME = 50.f;
// manager/builder/statics.as [seconds] -- Shield domes afforded: one plus
//   income times this over the dome's cost.
// manager/builder/statics.as [seconds] -- How long a lost dome stays fresh;
//   recent losses raise the shield want.
// manager/brain.as -- Same divided sizing as ShieldCover -- the per-gun
//   multiplier overpriced this ~3x (one dome answers every gun in reach).
// manager/brain.as [value] -- Base ranking value of a shield dome want, scaled
//   up by enemy LRPCs and recent dome losses.
// manager/military/unblock.as [toggle 0/1] -- Stuck units get an unblock nudge
//   (reclaim/move of what pins them); 0 disables.
const float TUNE_UNBLOCK = 1.f;

// ---------------------------------------------------------------------------
// Commander
// ---------------------------------------------------------------------------
// manager/builder/events.as [fraction 0-1] -- Commander health fraction below
//   which he immediately moves away from enemy influence, whatever he is
//   holding.
// manager/builder/events.as [seconds] -- A commander that sits on ground with
//   real enemy influence this long without actually moving is force-marched
//   away regardless of hp; 0 disables the anti-stall. Default 0: measured
//   2026-08-21 (24-game 1v1 A/B), 77 marches fired and commander-death losses
//   did not fall.
// manager/builder/events.as [influence] -- Tile influence that counts as hot
//   ground for the anti-stall clock.
// manager/builder/events.as -- CRetreatTask is not an IBuilderTask, so
//   nothing re-evaluates it every ~1s the way a builder task is -- a
//   commander that goes...
// manager/builder/rules_commander.as [elmos] -- While cautious, the commander
//   reads the WORST enemy influence on a ring this size around him, not just
//   at his feet.
// manager/builder/rules_commander.as [fraction 0-1] -- A cautious commander
//   abandons work farther forward than this fraction of the way to the enemy
//   -- standing there is the mistake, not the contact after it.
// manager/builder/rules_commander.as [toggle 0/1] -- All commander-specific
//   rules apply; 0 hands the commander to stock CBuilderManager for an idle-
//   time A/B.
// manager/builder/events.as -- Holding a build task with NO engine order.

// ---------------------------------------------------------------------------
// Air
// ---------------------------------------------------------------------------
// manager/air/wing.as [metal/s] -- One advanced air plant wanted per this much
//   metal income (the per-def curve still bounds it).
const float TUNE_ADV_AIR_INCOME = 150.f;
// manager/brain/facqueue.as [elmos] -- Cap on air scouts: two plus the map's
//   diagonal length divided by this -- bigger maps justify more eyes.
// manager/brain/facqueue.as [metal/s] -- One air scout wanted per this much
//   metal income (plus one); doubled while nothing fresh is seen.
// Scouts as a share of the standing fighter+bomber fleet (apexearth: "5% or
// less of our air").
// manager/air/update.as [toggle 0/1] -- Non-lead players hold their aircraft
//   at the plant until the wave releases them together; 0 sends them out as
//   built.
const float TUNE_AIR_HOME_WAVE = 1.f;
// manager/air/wing.as [ratio] -- Enemy AA under this fraction of our own team
//   army counts as DOMINATED: the assassin's absolute AA ceiling waives and a
//   standing abort un-latches, so a beaten enemy's leftover flak cannot veto
//   the one weapon that targets the win condition. 0 keeps the ceiling only.
const float TUNE_AIR_DOMINANCE_AA = 0.15f;
// manager/air/wing.as [ratio] -- Enemy field army under this fraction of ours
//   counts as gone for the dominance waiver.
const float TUNE_AIR_DOMINANCE_ARMY = 0.2f;
// manager/air/wing.as [metal/s] -- Metal income at which the first air plant
//   becomes mandatory for everyone (the air lead gets one earlier).
const float TUNE_AIR_MANDATORY_INCOME = 60.f;
// manager/air/station.as [toggle 0/1] -- Obsolete T1 fighters are recycled
//   once T2 fighters produce; 0 keeps them.
const float TUNE_AIR_RECYCLE = 1.f;
// manager/air/station.as [toggle 0/1] -- Idle fighters spread out on patrol
//   stations instead of clumping at the plant; 0 disables stationing.
const float TUNE_AIR_SPREAD = 1.f;
// manager/air/station.as [elmos] -- A fighter already within this of its
//   station is left alone -- re-ordering every pass keeps it permanently in
//   transit.
const float TUNE_AIR_STATION_NEAR = 400.f;
// manager/brain/facqueue.as [metal/s] -- One bomber wanted per this much metal
//   income (plus one).
// manager/brain/facqueue.as [metal/s] -- One fighter wanted per this much
//   metal income (plus one); raised to the per-other-aircraft floor below
//   whenever that is larger.
// manager/brain/facqueue.as [ratio] -- UNUSED as of 2026-08-21: superseded by
//   TUNE_FIGHTER_PER_OTHER, which floors on the whole non-fighter fleet
//   (bombers + scouts) instead of bombers alone. Left declared so a live
//   tunable read of the old name does not error; no code path reads it.
// manager/brain/facqueue.as [ratio] -- Fighter floor: this many fighters per
//   standing non-fighter aircraft (bombers + scouts). apexearth 2026-08-21:
//   "at least 1 fighter for every other aircraft we have -- fighters must be
//   >= 50% of the air fleet." Takes over from the income term once the fleet
//   is large enough to need it; 1.0 means fighters can reach parity with
//   everything else combined.
// manager/air/wing.as [metal/s] -- The elected air lead builds its first air
//   plant from this income -- earlier than everyone else, for the team's eyes.
const float TUNE_INTEL_AIR_INCOME = 25.f;
// manager/air/update.as [count] -- No intercept is launched with fewer
//   fighters than this; a pair feeding into flak is worse than waiting.
const float TUNE_INTERCEPT_MIN_FIGHTERS = 4.f;
// manager/air/state.as [ratio] -- One-shot bombers (Legion Martyr) get their
//   wanted count scaled by this -- they die on delivery, so a full bomber
//   count overbuys.
const float TUNE_ONESHOT_BOMBER_SCALE = 0.4f;

// ---------------------------------------------------------------------------
// Nukes and superweapons
// ---------------------------------------------------------------------------
// manager/brain/nukes.as [toggle 0/1] -- The nuke director runs (multi-volley
// manager/brain/sentinel.as [toggle 0/1] -- The sentinel: the brain checks
//   its own concepts every 45s and logs a verdict per check ("apex: thought
//   <name> CONCERN ..."); observer-first, each enforcement earned separately.
//   logistics, target ranking); 0 leaves silos to stock behaviour.
const float TUNE_BRAIN_NUKE = 1.f;
// manager/brain/nukes.as [influence] -- A defensive volley is called off once
//   net influence at the target reaches this -- our own army has closed to
//   that ground.
// manager/brain/nukes.as [minutes] -- Game age from which unseen antinukes are
//   assumed at offensive targets.
// manager/brain/nukes.as [metal] -- Assumed worth of the enemy base at our
//   mirrored start position, used as the standing offensive target before
//   anything better is sighted.
// manager/brain/nukes.as [metal] -- A defensive strike onto ground our own
//   army holds is only allowed against an enemy force worth at least this --
//   past it, losing some of our units to the blast beats losing the base.
// manager/brain/nukes.as -- 10k floor (apexearth: "filter the metal to target
//   areas of 10k metal or more if possible") -- with no qualifying target
//   the...
// manager/brain/nukes.as [metal or metal/s] -- A defensive strike pays once
//   the army is worth several missiles.
// manager/brain/nukes.as [ratio] -- A defensive strike pays once the target
//   army is worth this many missiles.
// manager/brain/nukes.as -- The repeat-strike dampener: halved per prior
//   volley on this ground.
// manager/brain/nukes.as [elmos] -- A point within this of an active volley's
//   target counts as already served -- no second volley onto the same ground.
// manager/brain/nukes.as [elmos] -- Lateral step between missiles of one
//   volley, so a salvo blankets the army instead of stacking on one point.

// ---------------------------------------------------------------------------
// Scouting, intel, ghosts
// ---------------------------------------------------------------------------
// manager/military/territory.as [metal] -- Enemy value that must actually be
//   SEEN before the enemy-afloat detector may trust the centroid at all.
const float TUNE_AFLOAT_SEEN = 500.f;
// manager/military/territory.as [ratio] -- Weight of stale (ghost) enemy
//   sightings against fresh ones in the territory model.
const float TUNE_GHOST_WEIGHT = 0.5f;
// manager/builder/statics.as [count] -- Candidate points tried on the
//   territory ring when picking the least- covered spot for the next jammer.
// manager/military/stance.as [ratio] -- Scout wants multiply by this while the
//   stance reads UNKNOWN -- silence is a scouting demand, not safety.
const float TUNE_SCOUT_BLIND_MULT = 2.f;
// manager/military/massing.as [ratio] -- The sanity ceiling: a GENEROUS
//   multiple of the most we ever saw at once, never the estimate itself --
//   limited sensor coverage...
const float TUNE_SEEN_CAP_MULT = 2.5f;
// manager/military/massing.as -- WE CANNOT SEE THEM MOST OF THE TIME.
const float TUNE_UNSEEN_HOLD = 0.5f;
// manager/military/massing.as [ratio] -- Pre-T2, an unseen enemy is assumed to
//   field at least our own army times this, so opening groups commit at real
//   size instead of trickling.
const float TUNE_UNSEEN_PARITY = 1.2f;
// manager/military/hooks.as -- squad metal value above which it is owed a
//   sensor escort. apexearth 2026-08-20: "any squad worth over 2000 metal".
const float TUNE_ESCORT_SQUAD_VALUE = 2000.f;

// ---------------------------------------------------------------------------
// Base layout and placement
// ---------------------------------------------------------------------------
// manager/brain.as [elmos] -- How far behind a chokepoint the choke gun
//   stands, so it shoots into the gap instead of standing in it.
// manager/military/territory.as -- Against the ring's radius on THIS
//   position's bearing.
const float TUNE_FRONT_BAND = 0.18f;
// manager/frontline.as [ratio] -- Width of the front band as a fraction of the
//   territory radius (floored at one influence- grid cell).
const float TUNE_FRONT_BAND_FRAC = 1.0f;
// manager/brain.as [ratio] -- Site-search radius for a front tower as a
//   fraction of its counted reach (min 400 elmos).
// manager/military/posture.as [elmos] -- Step size of the staging anchor's
//   walk back toward home while the ground ahead is lost.
const float TUNE_LANE_BACK_STEP = 300.f;
// manager/military/posture.as [toggle 0/1] -- THE ANCHOR MUST NOT STAND
//   FORWARD OF OUR OWN GUNS.
const float TUNE_LANE_BEHIND_GUNS = 1.f;
// manager/military/posture.as [fraction 0-1] -- How far from base toward the
//   enemy the army's staging anchor sits; higher stands the army further
//   forward on the map.
const float TUNE_LANE_FORWARD = 0.35f;
// manager/military/posture.as [elmos] -- The front must move this far before
//   the army re-stages with it; below that it is jitter (~two turret ranges).
const float TUNE_LANE_STICKY = 900.f;

// ---------------------------------------------------------------------------
// Diagnostics and switches
// ---------------------------------------------------------------------------
// perf.as [toggle 0/1] -- The perf governor (lag-severity measures and its
//   production cuts) is active; read once at startup.
const float TUNE_PERF = 1.f;
// manager/military/posture.as [toggle 0/1] -- WHY THE ARMY IS THERE, ON THE
//   MAP: this is the anchor FillFrontPos picks the regroup cluster from, so
//   it is the single most...
const float TUNE_PING = 0.f;
// manager/catalog.as [toggle 0/1] -- Dump every available def's catalog row at
//   init (one log line per def, parsed by tools/check_catalog.py). Off by
//   default: it is ~1000 lines of infolog that only a verification run reads.
const float TUNE_CATALOG_DUMP = 0.f;

// market.as MODEL terms (value-paradigm skill: one named quantity each).
// SPOT_M: metal/s a T1 spot yields at extraction 0.001 -- the one number the
// script cannot read per-spot yet; typical BAR land spots sit near 2.0.
// Replace with a spot-income binding.
const float TUNE_SPOT_M = 2.0f;
// PLANT_PIPE: the constructor pipeline's return in spot-streams. Early cons
// each carry a full open-spot stream and compound; 0.5 measured lab 1 at
// 5.1m (too late, apexearth 2026-08-23: "try building the first lab a bit
// sooner"); 2.0 targets the ~2m human timing. Labs 2+ are gated by
// PLANT_INCOME_PER, not this.
const float TUNE_PLANT_PIPE = 2.0f;
// Income one production line is worth: apexearth 2026-08-23, "below 50 metal
// per second you don't want multiple T1 labs even of varying types." The
// marginal plant's gain is zero beyond 1 + income/this -- income-derived,
// never a count.
const float TUNE_PLANT_INCOME_PER = 50.f;
// PIPE_LATENCY_H: the horizon against which a production pipeline's
// delivery latency discounts (h/(h+latency)) -- the temporal-consistency
// law applied to plants; what makes mex-solar-lab the emergent opening.
const float TUNE_PIPE_LATENCY_H = 60.f;
// STORE_HORIZON: seconds over which a storage's volume counts as captured
// overflow (its gain = min(overflow, storeM/horizon)).
const float TUNE_STORE_HORIZON = 60.f;
// TECH_PIPE: discount on a tech plant's unlock demand. The pipeline DELAY
// is priced by PipeLatencyMult -- a second 0.5 here double-counted it and,
// stacked with the funded discount, priced the T2 lab ~100x under a nano
// (measured 8v8: zero tech decides in 12 min, all eight players).
const float TUNE_TECH_PIPE = 1.0f;
// E_RESPONSE: seconds for the market's own energy supply to answer a
// scarcity spike (~one solar build); long builds earn the floor, not the
// spike.
const float TUNE_E_RESPONSE = 45.f;
// SPACE_M: metal-equivalent price of one 16-elmo build cell of ground.
// MODEL (flat until base-crowding senses drive it): what makes dense energy
// beat a field of solars at equal payback.
const float TUNE_SPACE_M = 1.0f;
// BP_HEADROOM: lathe capacity target as a fraction of income (slightly
// above 1 so the bank drains instead of pooling) -- the closed loop's one
// constant, a headroom fraction, never a count.
const float TUNE_BP_HEADROOM = 1.5f;   // 1.15 read "lacked build power" in watch after watch; supply leads demand, the E lesson again
// ASSIST_SHARE: fraction of the standing lathe fleet expected to fold onto
// a priced build (Requests::Take joins same-def askers).
const float TUNE_ASSIST_SHARE = 0.5f;
// E_STALL_BOOST: multiplier on the conversion-floor E price per unit of
// pull-above-income (a stall doubles-to-triples what new E is worth).
const float TUNE_E_STALL_BOOST = 2.0f;
// BP_LOOKAHEAD: seconds of income GROWTH folded into the BP target -- the
// compounding term; a flat economy adds nothing.
const float TUNE_BP_LOOKAHEAD = 60.f;
// FLY_SHORT: an air con's effective travel fraction vs the ground path --
// straight line, no blockage, no pathfinding.
const float TUNE_FLY_SHORT = 0.6f;
// FARM_BACK: how far behind the base anchor the eco farm is planned, elmos
// (the axis points at the front, so behind = away from threat/influence).
const float TUNE_FARM_BACK = 500.f;
// E_LOOKAHEAD: seconds of energy-pull GROWTH folded into the scarcity
// price -- anticipation, so the solar starts before the bank empties.
const float TUNE_E_LOOKAHEAD = 30.f;
// E_HEADROOM: energy income target as a multiple of trending pull -- the
// standing reserve that keeps the bank from ever being raced to zero.
// 1.25 still under-supplied in watched games ("definite pattern now").
const float TUNE_E_HEADROOM = 1.75f;   // 1.5 still read 'not that great' in a watched war game
// CON_ESCORT: exposed constructors claim one army guard each (master).
const float TUNE_CON_ESCORT = 1.f;
// ESCORT_MAX_COST: only cheap T1 takes escort duty (apexearth) -- a Bull
// guarding a con is a Bull missing from the line.
const float TUNE_ESCORT_MAX_COST = 120.f;
// MEX_GROWTH: weight of a spot's RELATIVE income boost (gain/income) on
// top of its absolute stream -- growth is worth more to the poor.
const float TUNE_MEX_GROWTH = 3.f;
// RANGE_WORTH: standing weight of weapon reach in unit selection (reach =
// free damage before the answer), on top of the reactive outranging term.
const float TUNE_RANGE_WORTH = 0.6f;
// MEDIC_FRAC: standing rez/repair fleet as a fraction of army value per
// minute (apexearth: "3 times more rezbots" -- was 0.04). Named _FRAC:
// a legacy TUNE_MEDIC_SHARE with other semantics survives at the bottom.
const float TUNE_MEDIC_FRAC = 0.12f;
// ECO_REAR_MARGIN: how much farther from the enemy than the #2 ally the
// rear-most home must be to count as "obviously" rear (distance ratio).
const float TUNE_ECO_REAR_MARGIN = 1.15f;
// ECO_ARMY_MUL: the rear specialist's military production as a fraction of
// normal -- applied to the army target AND the overflow sink, rez and
// support branches. Near-zero: the freed spend compounds through the eco
// ladder; 3% of a monster late economy is still a gantry stream.
const float TUNE_ECO_ARMY_MUL = 0.03f;
// ECO_SAFE_R: front distance beyond which the rear specialist skips ground
// defense entirely -- past any raid's reach, insurance is dead money.
const float TUNE_ECO_SAFE_R = 2500.f;
// JOIN_MIN_M: def cost above which a second builder JOINS the standing
// build instead of opening a parallel copy (fusion-and-up territory).
const float TUNE_JOIN_MIN_M = 500.f;
// ECO_LEASH: work radius of the quiet rear's builders from home -- the
// safe radius it prices everything else against.
const float TUNE_ECO_LEASH = 2500.f;
// ECO_CON_KEEP: land T1 cons the quiet rear always keeps -- nano turrets
// and small works still need hands (his floor-of-3 number).
const float TUNE_ECO_CON_KEEP = 3.f;
// LINE_FLOOR: a factory order must be worth at least this fraction of the
// rolling executed-want value, unless metal is overflowing (idle is free).
const float TUNE_LINE_FLOOR = 0.25f;
// ECO_DANGER_M: enemy cost inside the safe radius that counts as "base
// close to being under attack" -- two T1 raiders' worth (2 x ~110).
const float TUNE_ECO_DANGER_M = 250.f;
// ECO_REACH_FRAC: the quiet rear claims no spot whose enemy distance is
// under this fraction of its own -- it expands sideways/back, never forward.
const float TUNE_ECO_REACH_FRAC = 0.7f;
// ECO_ARMY_MIN_M: quiet-rear army floor -- the cheapest gantry-tier assault
// (corshiva 1550, defs 2026-07-30); below it, army money is ladder money.
const float TUNE_ECO_ARMY_MIN_M = 1500.f;
// RECLAIM_AMORT: seconds a one-shot reclaim refund is spread over when it
// competes with perpetual streams (the market's typical payback scale).
const float TUNE_RECLAIM_AMORT = 300.f;
// MOBILE_BP_EFF: fraction of a mobile builder's workertime that is real
// lathing rather than transit; nanos and other statics count at 1.0.
const float TUNE_MOBILE_BP_EFF = 0.6f;
// INSURE_RATE: protection value per metal of covered assets, per second --
// the one modeled risk quantity for eyes and turrets. 0.00005 prices a
// radar at ~v5 on a 100k base.
const float TUNE_INSURE_RATE = 0.0003f;   // was 5e-5: radar lost to marginal solars until assets were huge (watched)
// NUKE_RISK: the anti-nuke's own rate; higher, because an uncovered nuke
// is total loss. Timing emerges from assets x rate.
const float TUNE_NUKE_RISK = 0.0005f;
// TARGFAC_WANT: pinpointers wanted (apexearth 2026-08-23: "3 wanted max").
const float TUNE_TARGFAC_WANT = 3.f;
// OBSOLETE_RATIO: how many times better the best standing alternative must
// be (per cell for generators, in power for defences) before a building is
// scrap -- his "much better".
const float TUNE_OBSOLETE_RATIO = 4.f;
// EXPOSE_R: elmos from the core at which a structure counts fully exposed
// (a walk away from where the army lives).
const float TUNE_EXPOSE_R = 1200.f;
// EXPOSED_LOSS_S: seconds over which a fully exposed, unguarded asset is
// expected to be lost against a real opponent -- his "almost guaranteed".
// 300 priced sentries below the NEXT mex claim, so every spot was claimed
// naked and died to BARb inside the window; 120 flips to claim-then-guard.
const float TUNE_EXPOSED_LOSS_S = 120.f;
// GUARD_RATE: standing army value as a fraction of structure assets -- the
// insurance floor that also covers census blindness.
const float TUNE_GUARD_RATE = 0.15f;
// ENEMY_PRIOR: pre-contact estimate of enemy army as a share of OUR total
// value (symmetric start); the observed census replaces it once larger.
const float TUNE_ENEMY_PRIOR = 0.25f;   // 0.35 + a continuous line drained the bank into army (watched: out of metal)
// MATCH_RATIO: army fielded per metal of enemy army SEEN.
const float TUNE_MATCH_RATIO = 1.2f;
// ARMY_FILL_S: seconds over which an army-value gap counts as a stream.
const float TUNE_ARMY_FILL_S = 180.f;   // the 120 compensation was fighting the Wait throttle, not the price; with the line continuous, 180 shares honestly
// REZ_HORIZON: seconds to recover the field's wreck pool; rez production
// scales with losses and diminishes per bot.
const float TUNE_REZ_HORIZON = 120.f;
// AA_MATCH: our AA value per metal of enemy air seen.
const float TUNE_AA_MATCH = 0.7f;
// RETREAT_COST_SCALE: metal at which a unit's retreat threshold reaches
// ~+0.33 over the 0.08 floor (retreat = 0.08 + cost/this, cap 0.5) -- cheap
// units fight to the end, expensive ones preserve.
const float TUNE_RETREAT_COST_SCALE = 3000.f;
// STAKE_WEIGHT: how strongly an army DEFICIT borrows urgency from the
// total value at risk (expected loss = everything x defeat probability).
const float TUNE_STAKE_WEIGHT = 1.f;
// STATIC_GUARD: how much a metal of CORE static defense counts toward the
// army when computing the stake -- under 1 because towers cannot chase.
const float TUNE_STATIC_GUARD = 0.7f;
// WAVE_MEET: metal of standing front turrets per metal of observed enemy
// massing (both sides in metal -- the power conversion bought dozens).
const float TUNE_WAVE_MEET = 0.4f;

// manager/frontline.as [toggle 0/1] -- Draw the computed front line. Allies and
//   spectators see every map overlay below, so each ships off unless someone
//   deliberately turned it on.
const float TUNE_DRAW_FRONT = 1.f;
// manager/frontline.as [toggle 0/1] -- Draw the defense zone on the map: the
//   inner ring is the C++ base-defence range (the army fights at any odds
//   inside it), the outer ring the incoming-push alarm radius. Off by
//   default because it ships; the harness opts in with apex_draw_defzone=1.
const float TUNE_DRAW_DEFZONE = 0.f;
// manager/frontline/draw_diag.as [toggle 0/1] -- Draw one line per claimed mex
//   task, constructor to spot: shows a con walking past a near extractor to a
//   far one. Off by default because this ships.
// manager/frontline/draw_diag.as [toggle 0/1] -- Draw the army's staging anchor
//   and, when apex_medic_setback is set, the medic station behind it plus the
//   step between them. Off by default because this ships.
const float TUNE_DRAW_LANE = 0.f;
// manager/frontline/draw_diag.as [toggle 0/1] -- Cross every extractor past the
//   mid fraction toward the enemy, larger past the forward fraction: the same
//   FrontT classification the guard count and guard tier both read. Off by
//   default because this ships.
// manager/frontline/draw_diag.as [toggle 0/1] -- Ping the heal post: the exact
//   point CRetreatTask sends wounded units to (front + apex_retreat_behind
//   toward home). A ping rather than a line because there is only one of them.
const float TUNE_DRAW_HEAL = 0.f;

// ---------------------------------------------------------------------------
// Everything else
// ---------------------------------------------------------------------------
// manager/military/territory.as [percent] -- On maps with at most this much
//   land, a water-borne enemy centroid may read as the enemy living afloat.
const float TUNE_AFLOAT_LAND_PCT = 85.f;
// manager/military/territory.as -- Tight: the enemy's mass must sit ON the
//   water's edge, not a screen from a lake -- 900 bought shipyards against a
//   land army...
const float TUNE_AFLOAT_NEAR = 350.f;
// manager/military/territory.as [count] -- Consecutive positive reads before
//   the enemy-afloat answer latches -- one jittering centroid sample must not
//   flip the reaction.
const float TUNE_AFLOAT_STREAK = 3.f;
// manager/military/territory.as [metal] -- Seen enemy submarine value that
//   reads as the enemy afloat immediately, whatever the land fraction.
const float TUNE_AFLOAT_SUB_COST = 400.f;
// manager/military/defenceline.as [ratio] -- Enemy/our army ratio at which the
//   outfielded defence boost starts.
// manager/military/defenceline.as [ratio] -- Cap on the outfielded defence
//   boost.
// manager/military/defenceline.as [seconds] -- Only ally tower losses fresher
//   than this summon defence aid.
const float TUNE_AID_FRESH = 60.f;
// manager/military/defenceline.as [metal] -- Minimum fresh ally loss value
//   before defence aid moves.
const float TUNE_AID_MIN_LOSS = 300.f;
// manager/military/defenceline.as [elmos] -- How far defence aid will travel;
//   -1 follows the measured base separation live (a fixed default would freeze
//   before home is set).
const float TUNE_AID_REACH = -1.f;
// main.as [ratio] -- Threat-map multiplier on the Behemoth's def power, so
//   squads respect it; our own read stronger too (they are chargers and ignore
//   the margin anyway).
const float TUNE_BEHEMOTH_THREAT = 2.f;
// manager/builder/mexguard.as [ratio] -- Each big gun requires this many
//   popups standing per (big guns + 1) -- a ratio between the tiers, not a cap
//   on either.
// manager/military/deathledger.as [ratio] -- Cap on the forward-bleed engage
//   caution.
const float TUNE_BLEED_CAP = 1.6f;
// manager/brain/budget.as [toggle 0/1] -- The Brain's category budget scales
//   wants by target-vs-actual share; 0 turns budget shaping off.
const float TUNE_BUDGET = 1.f;
// manager/military/territory.as [toggle 0/1] -- THE SAFE GROUND CLOSEST TO
//   THE LINE: the FURTHEST workable sample, not the first threatened one.
const float TUNE_BUILD_THREAT_BAR = 1.f;
// manager/military/hooks.as [toggle 0/1] -- T3 CHARGERS GO FOR THE BASE.
const float TUNE_CHARGER_STRIKE = 1.f;
// manager/builder/obsolete.as -- A perf bound, not policy: each pick walks
//   full unit lists, and an unbounded sweep burned 277-475ms single frames
//   (seed 200,...
// manager/builder/obsolete.as [metal/s] -- Obsolete-reclaim picks per pass:
//   one plus income divided by this (a perf bound -- each pick walks full unit
//   lists).
// manager/frontline.as [toggle 0/1] -- The base-defence ring follows the
//   BUILT base (farthest finished rear structure plus the pad) instead of
//   the frozen map-diagonal formula; 0 keeps the static C++ ring.
const float TUNE_DEFZONE_DYNAMIC = 1.f;
// manager/frontline.as [elmos] -- Padding added to the built extent when the
//   dynamic ring is applied (roughly two T1 tower ranges of approach ground).
const float TUNE_DEFZONE_PAD = 400.f;
// manager/builder/maketask.as [milliseconds] -- Election-time budget per
//   frame; past it further builder elections defer to the next frame (lag
//   guard).
// manager/brain.as [metal/s] -- Above this income the front-defence want is
//   recomputed every 5s instead of every 1s -- rich games have more fence to
//   walk.
const float TUNE_ELECT_RICH_INCOME = 150.f;
// manager/crew.as [ratio] -- A builder joins the FRONT crew when its distance
//   to the line is under this times its distance to home; below 1 it must be
//   CLEARLY forward.
// manager/brain.as -- Before any factory exists there is exactly one builder
//   in the game -- the commander -- so this gate stops the opening builder...
// manager/military/territory.as [ratio] -- Minimum forward reach of a
//   territory ray for it to yield a front spot.
const float TUNE_FRONT_MIN_REACH = 0.5f;
// manager/brain.as [toggle 0/1] -- PRIORITY IS WHAT DECIDES WHETHER ANYONE IS
//   EVER SENT.
// manager/brain.as -- OVERLAP, DON'T JUST TOUCH.
// manager/builder/mexguard.as [toggle 0/1] -- ON by default -- apexearth: "I
//   never see us making the scorpion style defense turrets...
// manager/brain.as [elmos] -- How far from the builder the front-defence want
//   will look for fence work.
// manager/military/territory.as [toggle 0/1] -- NOTHING BEHIND US IS FRONT.
const float TUNE_FRONT_REAR_ARC = 0.f;
// manager/military/territory.as [toggle 0/1] -- Front spots are pulled back to
//   the safe side of the influence edge; 0 uses the raw edge.
const float TUNE_FRONT_SAFE_EDGE = 1.f;
// manager/military/territory.as [fraction 0-1] -- How far back from the
//   influence edge the front line is drawn.
const float TUNE_FRONT_SETBACK = 0.12f;
// manager/brain.as [ratio] -- Gantry want multiplier while the enemy fields T3
//   and we have no gantry producing -- the answer to titans is our own.
// manager/builder/maketask.as [seconds] -- A builder holding a guard task is
//   exempt from re-election for this long, so guards actually guard instead of
//   churning.
// manager/builder/rules_hold.as [toggle 0/1] -- Keep working a threatened
//   front-line build instead of abandoning it (the fence gun defends itself);
//   0 abandons on threat.
// manager/military/posture.as [toggle 0/1] -- A HOLD MUST NEVER STOP US
//   DEFENDING OUR OWN GROUND.
const float TUNE_HOLD_RELEASE = 1.f;
// manager/builder/maketask.as [seconds] -- Base idle-election backoff per
//   strike: a builder that keeps electing nothing waits strikes x this before
//   asking again.
// manager/builder/maketask.as [count] -- Cap on the idle-backoff strike
//   counter.
// manager/builder/maketask.as [seconds] -- An idle builder gets a homeward
//   patrol leg (crossing the base's work) at most once per this interval.
// manager/brain.as [metal/s] -- Income the Want values were calibrated at;
//   wants scale by ref/income so a rich economy is not overexcited by small
//   absolute gains.
// manager/air/update.as [metal] -- Minimum enemy air value over an ally's home
//   before the team intercept flies.
const float TUNE_INTERCEPT_MIN = 500.f;
// manager/air/update.as [elmos] -- Radius around each home in which enemy air
//   value is measured for the intercept decision.
const float TUNE_INTERCEPT_R = 1400.f;
// perf.as -- THE SEVERITY LADDER (apexearth: "keep cutting back until we've
//   caught up"): every window still under the bar climbs it, every...
const float TUNE_LAG_SPEED = 0.98f;
// perf.as [severity] -- How much lag severity rises per slow-speed sample;
//   higher cuts kick in at severity 1, 2 and 3.
const float TUNE_LAG_STEP = 0.34f;
// manager/factory/switch.as [toggle 0/1] -- Spare unspent income may grant an
//   extra factory line; 0 disables the spare-metal branch.
// manager/factory/switch.as [ratio] -- Spare income above this fraction of
//   income counts as feeding another line.
// manager/builder/mexguard.as [count] -- Dragon's teeth placed around a
//   cloaked maw (popup trap) to hide its footprint.
// manager/brain/mix.as [toggle 0/1] -- The composition mixer adjusts factory
//   role draws toward counters; 0 leaves the plain quota.
// manager/builder/obsolete.as [seconds] -- A structure already asked for
//   reclaim is not re-asked for this long.
// manager/builder/opening.as -- FAILSAFE, deliberately redundant with
//   everything above: this gate holds the single most important unlock in the
//   game, and it...
// manager/builder/opening.as [toggle 0/1] -- The scripted opening yields to
//   economy repair whenever factory or mex readings collapse; 0 runs the
//   opening unconditionally.
// manager/builder/opening.as [metal/s] -- Metal income below which the opening
//   still counts as needing economy.
// manager/builder/obsolete.as [fraction 0-1] -- A tower is outgrown when a
//   much bigger gun stands at least this much farther forward -- the line
//   moved past it.
// manager/builder/obsolete.as [ratio] -- The bigger gun must cost at least
//   this times the tower for the outgrown test.
// manager/brain/facqueue.as [ratio] -- Overflow production (build past quota
//   rather than waste) starts once the bank passes this fraction of storage.
// manager/persona.as [index] -- Force a specific personality kind for every
//   instance (-1 = roll normally). For A/Bs.
const float TUNE_PERSONA = -1.f;
// manager/builder/rules_optional.as [toggle 0/1] -- Reactors site at the
//   protected rear of the base; 0 leaves siting to the ordinary search.
// manager/builder/rules_optional.as [elmos] -- How far behind the base centre
//   the rear reactor spot sits.
// manager/builder/fusion.as [toggle 0/1] -- Outstanding bound.
// manager/builder/fusion.as [elmos] -- Search radius for chaining a new
//   reactor tight against the existing batch.
// manager/builder/requests.as [metal/s] -- In-flight build requests allowed
//   per this much metal income (min 2) -- the governor on parallel sites.
const float TUNE_REQUEST_DRAIN = 7.0f;
// manager/factory/airsupport.as [ratio] -- Rezbots wanted per unit of steady
//   income (or per visible wreck value, whichever asks for more).
// Fraction of the rez want held as a FLOOR on the bot-lab line (the rest
// stays a ratio entry). 0 restores pure-ratio; 1 is the old conveyor bug.
// Knee of the sublinear rez curve: want = slope*knee*ln(1+income/knee).
// One ENERGY and one METAL constructor dedicate per this many enlisted
// T1/adv cons. 0 disables dedicated roles. Was 3, which locked 2/3 of the
// fleet into the two eco roles -- measured live (85 cons: energy=33
// metal=26, 24 free) while the brain's other wants starved for electors;
// apexearth: "we need enough remaining cons to be able to choose the
// various other buildings we want to make."
// Advanced-con dedication ratio: one ENERGY and one METAL dedicate per this
// many enlisted advanced cons. Was 2 (every adv con dedicated); 3 leaves a
// third of them free for the adv-only wants (gantry, pulsar, silo).
// Hard share ceiling: ENERGY+METAL together may hold at most this fraction
// of a tier's cons, whatever the per-N ratios say (apexearth: "not more
// than 50% of our total con count", split per tier).
// Assisters beyond a site's ETA-derived worker count fall back into the
// auction instead of being held to completion. 0 restores the glue.
const float TUNE_ASSIST_RELEASE = 1.f;
// Eco builds (energy, converter, mex, moho) keep this multiple of the
// ETA-derived crew before the peeler calls them over-staffed -- income
// finishing fast outranks a perfectly even build-power spread.
const float TUNE_PEEL_ECO_KEEP = 2.f;
// manager/brain/facqueue.as [metal/s] -- One T1 air constructor wanted per
// this much metal income (plus one), on the air line's floor.
// manager/factory/choose.as [metal/s] -- Steady income past which the
// extra-plant discipline (afus+pulsar+army-fed) stops vetoing additional
// T2 plants of any kind.
// Roulette dominance cap: one want may score at most this multiple of all
// other wants combined (1.5 => at most ~60% of the draw). 0 disables.
// Balance multipliers on the mex/mexup auction values (apexearth: "we might
// need to turn up mex and mexup"), and how many upgrades the always-running
// lane keeps in flight.
// apexearth's normal numbers: one gantry per this much steady income; three
// pinpointers once income clears the late-game bar; pulsar value grows by
// income/norm.
// Seconds of steady income that let an extra advanced plant bypass the
// afus/pulsar/army milestones outright -- at 500 m/s a 900-metal lab is 2s.
// Workers a big eco build deserves: 1 + costM/this (BigBuildWorkersWanted).
// Cost floor for the big-build assist scan.
// manager/builder/rules_rezzer.as [ratio] -- share of the rez fleet that
//   serves as battlefield medics: they stay with the army's staging anchor,
//   repair the wounded during fights and reclaim the aftermath there. The
//   rest work the corpse geometry as before. 0 disables medics.
const float TUNE_MEDIC_SHARE = 0.4f;
// manager/builder/rules_rezzer.as [elmos] -- how far around the staging
//   anchor a medic looks for wounded units, and how close it holds station.
const float TUNE_MEDIC_R = 1200.f;
// manager/builder/rules_rezzer.as [elmos] -- how far BEHIND the lane a medic
//   holds station. The lane is where the army is fighting; a medic parked on it
//   is in the fight. 0 keeps the old on-the-lane behaviour.
const float TUNE_MEDIC_SETBACK = 0.f;
// manager/builder/mexguard.as [toggle 0/1] -- a mex past MEX_GUARD_FWD_FRAC of
//   the way to the enemy gets a heavy gun rather than the light/mid sentry.
//   The tier then scales with exposure the same way the guard COUNT already
//   does. 0 keeps the light/mid-only cap.
// manager/military/posture.as [toggle 0/1] -- Once T2 exists, cheap suicidal
//   spam (ticks etc.) routes as spam -- forward always; 0 treats them as
//   normal army.
const float TUNE_SPAM_SUICIDAL = 1.f;
// manager/military/unblock.as [seconds] -- A stuck unit already asked for
//   unblocking is not re-asked for this long.
const float TUNE_STUCK_RETRY = 120.f;
// manager/builder/rules_offer.as [toggle 0/1] -- Default OFF: the refusal
//   this addresses is not the binding one -- see IBuilderTask::FindBuildSite.
// manager/brain.as [metal] -- Diminishing-returns normalizer: a Want's value
//   divides by (1 + invested/this), so sunk metal argues against more of the
//   same.
// manager/builder/mexguard.as [metal/s] -- From this income dragon's-teeth
//   walls are obsolete: stop building them and start reclaiming them.
