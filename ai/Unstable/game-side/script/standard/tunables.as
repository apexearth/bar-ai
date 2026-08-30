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
// manager/brain/facqueue.as [ratio] -- How deep the facqueue keeps each driven
//   line, as a multiple of the line's re-election gap, measured in that
//   line's own build seconds. Below 1 the plant is idle by construction; the
//   margin over 1 covers the order lag, which is a window of its own at
//   benchmark speed.
const float TUNE_FAC_QUEUE = 1.5f;
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
const float TUNE_STANCE_AGGRO_ARMY = 0.75f;
// manager/military/stance.as [ratio] -- DEFENCE share multiplier while
//   AGGRESSIVE.
const float TUNE_STANCE_AGGRO_DEF = 1.3f;
// manager/military/stance.as [ratio] -- ECONOMY share multiplier while
//   AGGRESSIVE (below 1: guns before growth while under attack).
const float TUNE_STANCE_AGGRO_ECO = 1.0f;
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
// manager/military/withdraw.as [toggle 0/1] -- ATTACK/RAID squads reform on the
//   chokepoint behind our front while the base is under attack and no killing
//   blow is committed, instead of continuing to roam; 0 disables the recall
//   (they keep fighting wherever their task sends them).
const float TUNE_RECALL_HOME = 1.f;
// manager/military/withdraw.as [fraction 0-1] -- Only squads this far past
//   our own territory (ForwardFraction) are recalled -- units already fighting
//   near home need no order, they are already where they are needed. Matches
//   the threshold sentinel.as already uses to call the same thing a CONCERN.
const float TUNE_RECALL_HOME_FWD = 0.5f;
// manager/military/territory.as [toggle 0/1] -- ForwardFraction takes its
//   bearing from the REMEMBERED enemy centre and its scale from the deepest
//   separation seen, so enemies inside our base cannot move the axis they are
//   measured on; 0 restores the live-centroid reading.
const float TUNE_FWD_STABLE = 1.f;
// manager/military/territory.as [seconds] -- Half-life of that high-water
//   separation, so a front that genuinely moves is eventually re-normalised.
const float TUNE_FWD_SPAN_HALFLIFE = 300.f;
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
// manager/military/withdraw.as [seconds] -- How far back the local-trade
//   ledger looks: combat deaths older than this no longer say who is winning
//   the spot.
const float TUNE_TRADE_WINDOW = 15.f;
// manager/military/withdraw.as [ratio] -- The trade trigger: pull back when
//   our combat metal dead nearby exceeds theirs times this (0 disables via
//   the floor).
const float TUNE_LOSING_TRADE = 3.f;
// manager/military/withdraw.as [metal] -- Ignore the trade trigger until at
//   least this much of OUR combat metal died nearby -- one cheap death is
//   noise, not a verdict.
const float TUNE_LOSING_FLOOR = 250.f;
// manager/military/withdraw.as [toggle 0/1] -- Abort a losing ATTACK/RAID
//   task outright so the squad re-pools together. Measured 1W-11L vs 4W-10L
//   with it on (winrate6): the ledger reads "losing" transiently in bloody
//   fights and mid-commitment aborts throw engaged units away. Experiment
//   arm, default off.
const float TUNE_FIGHT_ABORT = 0.f;

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
// manager/military/killingblow.as [fraction] -- The blow disarms below
//   KILL_EDGE times this. Wide enough to survive the push's own measurement
//   dip (retreating units read zero power); 0.6 flapped 15x in one game.
const float TUNE_KILL_OFF_FRAC = 0.35f;
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
// manager/brain/market/want_protect.as [light towers] -- MINIMUM PROTECTION
//   PER MEX. Every site the defence auction considers is priced against the
//   wave that has actually arrived there, and a mex nothing has attacked yet
//   reads a wave of zero -- so it was skipped outright, and the economy stayed
//   naked until something came for it. This is the wave a standing mex is
//   assumed to have to meet whatever we have seen, measured in the faction's
//   own light towers so it scales across factions and tiers rather than being
//   a metal number. It is a FLOOR and nothing more: once a mex has this much
//   cover the shortfall is zero and the next turret there prices itself out,
//   and a mex under real threat is still sized by the threat. 0 restores the
//   observed-threat-only behaviour, which is how the A/B is run. Halved
//   2026-08-29 under his concentration ruling ("Move 8 spread out defenses
//   from mexes into less choke points which overwhelm the attack") -- the
//   freed budget flows to the gate depth floor under the same DefenceTarget.
const float TUNE_MEX_COVER_FLOOR = 0.5f;
// manager/brain/market/want_protect.as [ratio] -- A choke-gate site's threat
//   floor as a multiple of the arriving wave: the gate keeps deepening until
//   its cover OVERWHELMS the push, not merely matches it ("Have an unusual
//   amount of tower at some spots. Try to deeply cover those choke points").
const float TUNE_GATE_DEPTH = 2.f;
// manager/brain/market/want_protect.as [toggle 0/1] -- The teeth line: one
//   wall piece per election across the strongest defended gate's span, a
//   step enemy-ward of the doorway ("slow them down with some walls
//   outside"). OFF at his request 2026-08-29 ("the implementation is
//   terrible") -- the knob stays so a better implementation can be A/B'd.
const float TUNE_TEETH = 0.f;
// manager/brain/market/want_protect.as [gain] -- What one tooth's share of
//   breaking a push is worth, on the auction's own value scale: winning
//   wants carry v>=3 and a tooth's costs price near 70, so 2 gave v=0.03
//   and lost every election in 24 games; 200 overshot to v~20 and had the
//   COMMANDER placing teeth at 1.8m over a mex claim. 40 lands a tooth at
//   v~4: it wins idle nearby hands and loses to real economy.
const float TUNE_TEETH_GAIN = 40.f;
// manager/brain/market/want_protect.as [ratio] -- HOW HARD A BUILDER PREFERS
//   THE GROUND IT IS ALREADY STANDING ON. The defence auction picks a site,
//   then ValueOf charges the walk to it -- so the choice never saw the cost of
//   getting there, and a constructor that had just finished a mex was sent
//   across the base to a site worth marginally more (apexearth: "units making
//   mex and then not immediately making the light tower to cover it"). This
//   weights the walk inside the site ranking, in the same two terms the price
//   uses: the builder's idle seconds and the income the tower forgoes by
//   starting late. 1 ranks sites exactly as they will be priced; 0 restores the
//   old distance-blind choice, which is how the A/B is run; above 1 makes
//   defence more local still.
const float TUNE_DEF_SITE_WALK = 1.f;
// manager/brain/market/decide.as [toggle 0/1] -- COVER WHAT YOU JUST BUILT.
//   The category draw is proportional, not argmax, so a tower worth twice the
//   mex beside it still loses the roll about half the time -- which is what
//   "we don't immediately make the light tower" looks like from the outside
//   (apexearth, twice). This lets ONE want skip the lottery: a ground-defence
//   want standing on a mex of ours that is still under apex_mex_cover_floor,
//   proposed by a builder already inside the tower's own reach of it. The same
//   queue-jump apex_super_push and the defence-panic path already use.
//   Deliberately narrow: it cannot fire away from a mex, cannot fire once the
//   mex has its floor, and cannot fire for a builder that would have to walk.
const float TUNE_COVER_PUSH = 1.f;
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
//   wrong place by the task's own meaning. 0.35 was tried against the
//   midfield-grind deaths and lost MORE (ceded the corridor's mexes).
const float TUNE_DEFEND_LEASH = 0.55f;

// apex_hold_committed: units standing on ground the enemy's guns cover are
//   never given solo pull-out orders -- the split (half fights, half runs)
//   loses the fight twice. 0 restores per-unit withdrawal everywhere.
const float TUNE_HOLD_COMMITTED = 1.f;
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
// base is. One cluster, the reach of a single bombing run.
const float TUNE_AIR_CLUSTER_R = 900.f;
// [AA metal soaked per point of bomber health] -- Wing HEALTH is what absorbs
// AA, so a 16,700 hp Dragon soaks 25x what a 670 hp Thunder does. Sets both the
// throughput curve and how fast the required strike grows with their AA; it is
// what makes "50 or 100 from different angles" the answer to a wall instead of
// standing down. At 0.05, ~20 Dragons clear 8k of AA at ~0.7 throughput while
// light bombers need ~67 to reach half through 2.5k -- and the payoff test then
// declines that as the suicide it is.
const float TUNE_AIR_AA_SOAK = 0.05f;
// manager/air/state.as [toggle 0/1] -- The strike sizes against the enemy
//   AA census divided by their base count (mirrored from our own team size):
//   a raid overflies ONE base and static AA cannot concentrate. 0 sizes
//   against the whole map's AA, which read want=125 bombers and held a
//   50-bomber wing at home forever.
const float TUNE_AIR_AA_SPLIT = 1.f;
// [multiple] -- Expected damage a raid must return against its own metal
// before it is worth mounting.
const float TUNE_AIR_PAYOFF = 1.5f;
// [seconds] -- How long after a strike launches before it is scored. Long
// enough for the wing to reach, bomb and be shot at.
const float TUNE_AIR_SETTLE_S = 90.f;
// [weight 0-1] -- How much one scored run moves the running estimate of a
// bomber type's survival and delivered damage.
const float TUNE_AIR_OBS_W = 0.5f;

// ---------------------------------------------------------------------------
// Commander
// ---------------------------------------------------------------------------
// manager/brain/market/safety.as [toggle 0/1] -- All commander-specific
// safety rules apply; 0 hands the commander to stock CBuilderManager.
const float TUNE_COMM_RULES = 1.f;
// manager/brain/market/safety.as [fraction of his own cost] -- Fielded enemy
// HEAVY+SUPER mass at this fraction of the commander's value makes him
// cautious. Scaled to his cost so it tracks the game, not a number.
const float TUNE_COMM_HEAVY_FRAC = 0.5f;
// manager/brain/market/safety.as [multiple of his own cost] -- Post-T2, enemy
// mobile massing at this multiple of his value makes him cautious.
const float TUNE_COMM_MASS_MULT = 2.f;
// manager/brain/market/safety.as [fraction 0-1] -- A cautious commander
// abandons work farther forward than this fraction of the way to the enemy;
// standing there is the mistake, not the contact after it.
const float TUNE_COMM_FWD_CAP = 0.25f;
// manager/brain/market/safety.as [influence] -- Enemy influence at his tile
// (or on the ring, while cautious) above which he leaves. Uses the influence
// map, never ai.GetBuilderThreatAt, which reads clean until he is dead.
const float TUNE_COMM_FLEE_INFLUENCE = 0.01f;
// manager/brain/market/safety.as [elmos] -- While cautious he reads the WORST
// influence on a ring this size around him, not just at his feet.
const float TUNE_COMM_FLEE_RING = 600.f;
// manager/brain/market/safety.as [fraction 0-1] -- Below this health he is
// steered directly away from the enemy centroid instead of given a retreat
// task, because the retreat haven can be the ground being overrun.
const float TUNE_COMM_FLEE_HP = 0.85f;

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
//   territory radius (floored at one influence-grid cell). The arc it keeps is
//   acos(1 - frac) each side of the enemy bearing: 1.0 was +/-90 degrees --
//   HALF the perimeter read as front, every game (band=R in every frontline
//   log line), which is a "front" through the middle of the base. 0.35 is a
//   +/-49 degree arc.
const float TUNE_FRONT_BAND_FRAC = 0.35f;
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
// Discount a tech want's deferred gain by the risk borne over its pipeline.
// 0 disables it, which is how the A/B control is run.
const float TUNE_TECH_SURVIVAL = 1.f;
// The same survival discount on the ENERGY want, so a long-payback generator
// (afus, fusion) is priced on the base it needs to still be standing. Cheap
// fast generators are untouched by construction. 0 disables it.
const float TUNE_ECO_SURVIVAL = 1.f;
// The siege prior: what share of our OWN total economy we assume the enemy
// has converted into army and may be walking at us right now, seen or not.
// 1.0 = they had our start and our minutes and spent it all on units. Used
// only by the survival discount on long builds, never to size production.
const float TUNE_SIEGE_PRIOR = 1.f;
// ARMY COMPOSITION TARGET, shares of army metal (apexearth 2026-08-24:
// 30/25/25/20; re-ruled 2026-08-29 to 28/20/35/17 -- "build up these guys
// [snipers/hounds/arty] in unit numbers so our army can grow very
// powerful", "Rocket bots, artillery... they get free shots sometimes so
// we should leverage that"). tank = health per metal, reach = weapon
// range, dps = damage per metal, mid = nothing clearly dominant. Classes
// are read off unit data against the game's own mobile combat units; see
// army.as.
const float TUNE_LINE_TANK = 0.28f;
const float TUNE_LINE_MID = 0.20f;
const float TUNE_LINE_REACH = 0.35f;
const float TUNE_LINE_DPS = 0.17f;
// manager/brain/market/army.as [ratio] -- How hard the enemy's observed
//   STATIC share of fielded metal bends the reach target up (renormalized).
//   MEASURED WORSE at 1.0 (winrate14: 0W-11L, trade 0.372 vs 0.53-0.65
//   refs) -- reach at ~48% left no screen and corridors deny it standoff
//   room. Experiment arm, default off; his adapting-composition ruling
//   stands as direction, this term's shape or scale is wrong.
const float TUNE_LINE_ADAPT = 0.f;
// manager/brain/market/want_protect.as [ratio] -- The per-mex defence floor
//   grows with the spot's forward fraction: floor * (1 + fwd * this). His
//   ruling: "the closer our mex is to the enemy and furthest from our army,
//   the stronger the defenses should be."
const float TUNE_MEX_EXPOSE = 1.5f;
// manager/builder/rules_rezzer.as [forward fraction] -- An IDLE rezzer past
//   this retires to the haven regardless of the threat read (the sensor is
//   the documented liar); working rezzers are untouched.
const float TUNE_REZZER_FWD = 0.25f;
// manager/military/withdraw.as [elmos] -- Pre-contact consolidation: a
//   DEFEND unit within this of a tracked incoming group compares local ally
//   metal against the pack and falls back to the rally BEFORE contact.
const float TUNE_CONSOLIDATE_R = 2000.f;
// manager/military/withdraw.as [ratio] -- Local ally metal times this must
//   meet the tracked pack's metal or the defender consolidates; 1 = meet
//   them at even strength or from behind the guns.
const float TUNE_CONSOLIDATE_EDGE = 1.f;
// WHAT A COMBAT UNIT IS WORTH -- the exponent on each golden metric
// (apexearth 2026-08-25: "RANGE, DAMAGE, HP... perhaps we can try a variety of
// algorithms"). Read in manager/brain/market/worth.as; each metric is
// normalised by the game field's own mean, so these are scale-free.
// The defaults below reproduce the previous gCombat/costM ranking EXACTLY --
// dps * sqrt(alpha) * hp / cost is what power^2/cost expands to -- so the
// first deploy is a no-op and every later setting is a clean A/B against it.
const float TUNE_WORTH_DPS = 1.f;
const float TUNE_WORTH_ALPHA = 0.5f;
const float TUNE_WORTH_HP = 1.f;
const float TUNE_WORTH_RANGE = 0.f;
const float TUNE_WORTH_AOE = 0.f;
// COST IS A CHOICE OF LANCHESTER LAW. The caller divides by cost once more, so
// the total power of cost is 1 + this: at 1 that is cost^2, the LINEAR law
// where bodies trade one for one and cheap chaff wins the draw; at 0 it is
// cost^1, the SQUARE law where a massed army fires at once and quality wins
// superlinearly. Tzar-and-Banisher armies are the square-law case; 0.5 is the
// middle. 1 is what this AI has always priced under.
const float TUNE_WORTH_COST = 1.f;
// 1 = print the exponents and field means once; 2 = also dump the ranked
// field. Costs no games to learn what an arm actually prefers.
const float TUNE_WORTH_DIAG = 0.f;
// What a weapon's reach is worth when it CANNOT hit a moving target -- a slow
// un-tracked rocket. 1 = the reach counts in full, as it always has; 0.5 would
// say half of it only ever lands on buildings. The DLL's own IsAlwaysHit does
// the detecting (see EffRange in market/worth.as); this is what it costs.
const float TUNE_AIM_MISS = 1.f;
// Judge each class axis against the field MEDIAN rather than its mean. 0 = as
// it always was; see LineRef in market/army.as for why the mean cannot work.
const float TUNE_LINE_MEDIAN = 1.f;
// Read the tank and dps axes PER BODY rather than per metal (see LineAbs in
// market/army.as). 0 = as it always was, which made a Thud tankier than a Tzar.
const float TUNE_LINE_ABS = 1.f;
// Exponent on the range axis of the class argmax. 1 = as it always was.
const float TUNE_LINE_RANGE_EXP = 1.f;
// How far above the field's REFERENCE an axis must stand for a unit to count as
// that class rather than as middle.
const float TUNE_LINE_EDGE = 1.15f;
// How hard a class below its target share is favoured. Proportional to the
// shortfall; 0 disables the composition target entirely.
const float TUNE_LINE_BITE = 1.5f;
// How much ground-covered-per-metal is worth while the fleet is short of the
// sites it must watch. Buys cheap fast bodies early and fades as they arrive;
// 0 disables the coverage term.
const float TUNE_COVER_WORTH = 1.5f;
// Discount a mex/upgrade's income stream by the share of it we expect to still
// be collecting over the stake horizon. A tower within reach of the spot raises
// it directly, so cover makes the next claim beside it worth more. 0 disables,
// which is how the A/B control is run.
const float TUNE_STREAM_SURVIVAL = 1.f;
// Rent a building pays for standing on DEFENDED ground: covering turrets'
// metal spread over the area they cover, per cell of footprint. Makes dense
// beat sprawling inside the perimeter and costs nothing outside it. 0 disables.
const float TUNE_SPACE_RENT = 2.f;
// manager/brain/market/price.as -- seconds over which a purchase must earn.
// A gain is credited only for the share of this horizon it will actually be
// collecting, so a build that delivers nothing for most of it is discounted
// against the small compounding steps that deliver now. Scales itself with
// build power: more lathes shorten buildSec and restore the big build's
// value. 0 disables, which is how the A/B control is run.
const float TUNE_PAYBACK_H = 900.f;
// manager/brain/market/price.as -- the option cost of tying capital up in an
// unfinished frame, as a multiple of (cost x duration / payback horizon).
// apexearth's "little bit extra of a penalty on top of time". 0 disables.
const float TUNE_LOCKUP = 0.5f;
// How much sharper the category draw gets for a COMMITMENT -- added to
// apex_draw_sharp in proportion to the candidate's cost as a share of what the
// economy can produce over the payback horizon. Large values make an expensive
// want effectively winner-takes-all while cheap wants keep their sampling.
const float TUNE_COMMIT_SHARP = 12.f;
// manager/brain/market/sites.as -- elmos one farm row runs before the next
// stacks behind it. Halved from 640 on apexearth's watched report that the
// winds sat too far out on both sides: the same slots in a narrower row form
// a block instead of a line, so the next slot is adjacent to the last.
const float TUNE_FARM_ROW_W = 320.f;
// Seconds over which committed-but-unbuilt work counts as build-power demand.
// Matches the bank clause's horizon in BPGap; 0 disables the term.
const float TUNE_BP_BACKLOG_S = 60.f;
// Offer the spaced front posts (Military::FrontBuildSpots) to the defence
// auction alongside mexes and big structures. 0 disables, for the A/B.
const float TUNE_FRONT_LINE = 1.f;
// Measure turret coverage on the ring the enemy can SHOOT FROM (their
// observed weapon range), taking the weakest bearing, instead of asking
// only whether a turret reaches the target itself. 0 restores the old test.
const float TUNE_STANDOFF_COVER = 1.f;
// Let the commander fight while he still outclasses the field. CommCaution is
// the "heavies are out" sense, so this only ever fires before that. 0 = the
// old flee-only commander.
const float TUNE_COMM_FIGHT = 1.f;
// TECH_PIPE: discount on a tech plant's unlock demand. The pipeline DELAY
// is priced by PipeLatencyMult -- a second 0.5 here double-counted it and,
// stacked with the funded discount, priced the T2 lab ~100x under a nano
// (measured 8v8: zero tech decides in 12 min, all eight players).
const float TUNE_TECH_PIPE = 2.0f;
// E_RESPONSE: seconds for the market's own energy supply to answer a
// scarcity spike (~one solar build); long builds earn the floor, not the
// spike.
const float TUNE_E_RESPONSE = 45.f;
// E_BILL_SHARE [toggle 0/1] -- WHILE E-STALLED, price a build's ENERGY bill by
//   the share of energy INCOME its own drain eats, instead of by how long the
//   build runs. Inert with energy in hand: outside a stall the bill competes
//   with nothing (apexearth: "it only matters when we're e-stalling").
//   costE/buildSec against income: an advanced solar's 5,000 E is 63 E/s, most
//   of a 100 E/s economy and a sixth of a 400 E/s one, so the same building is
//   unaffordable at the first and cheap at the second (apexearth: "an advanced
//   solar is hardly affordable at 100e/s income. And it costs a lot of energy
//   to make. So income restrictions must apply"). The scarcity premium is
//   still zero while the economy is healthy, so this only bites in a stall.
//   0 restores the build-length decay (apex_e_response), which was blind to
//   income and priced a 5,000 E bill at the conversion floor.
const float TUNE_E_BILL_SHARE = 1.f;
// STALL_SOLAR_E [energy/second] -- while HARD e-stalled below this income, the
//   energy want is restricted to generators that cost NO energy to build, i.e.
//   the basic solar (apexearth: "if we are e-stalling and we have less than 300
//   energy per second, MAKE A BASIC SOLAR"). His number, stated as a rule, not
//   derived: an advanced solar's 5,000 E bill and wind's 175 are both paid out
//   of an economy that has none. 0 disables the rule and leaves the ladder to
//   the auction.
const float TUNE_STALL_SOLAR_E = 300.f;
// CONV_HORIZON: seconds of operation a converter is assumed to amortize its
// own metal, energy and build time over, when netting the energy floor price.
// CHOSEN, not derived. Short on purpose (apexearth: "it pays off eventually
// and that's fine -- by the time this stuff matters less we're on to fusions
// and afus"): a long window credits the converter with a payback the economy
// has already outgrown, which reads back as energy being worth more than it is.
const float TUNE_CONV_HORIZON = 300.f;
// SPACE_M: metal-equivalent price of one 16-elmo build cell of ground.
// MODEL (flat until base-crowding senses drive it): what makes dense energy
// beat a field of solars at equal payback.
const float TUNE_SPACE_M = 1.0f;
// BP_HEADROOM: lathe capacity target as a fraction of income (slightly
// above 1 so the bank drains instead of pooling) -- the closed loop's one
// constant, a headroom fraction, never a count.
const float TUNE_BP_HEADROOM = 1.0f;
// 1.5 was set because 1.15 "lacked build power" in watch after watch. Against
// BARb in the same games it bought 29.5% of our metal as build power to their
// 17.8%, and 18.5% to their 9.9% in the first ten minutes; 1.0 moved mex 14->17
// (12 games each). apexearth: "the bp budget may be too high and we need more
// eco budget, but even in that eco budget we need more mex budget."
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
// ESCORT_SPEED: an escort must CATCH a raider or be a riot unit (apexearth:
// "we want fast or tough units on escort, rocket bots die in a 1v1 vs a
// pawn/grunt"). A multiple of the ground field's own mean speed, so 1.0 means
// "above average", and no number here is about a particular unit. Lower it to
// let slower units guard.
const float TUNE_ESCORT_SPEED = 1.f;
// MEX_GROWTH: weight of a spot's RELATIVE income boost (gain/income) on
// top of its absolute stream -- growth is worth more to the poor.
// A spot is worth what it RAISES us by, not what it yields (apexearth: "when
// a mex would double our income it is very important... if it boosts our
// income only 1% then its not too important"). At 8: doubling x9, +10% x1.8,
// +1% x1.08 -- 3 gave x4 / x1.3 / x1.03, too flat to express that ordering.
const float TUNE_MEX_GROWTH = 8.f;
// The same compounding premium for ENERGY, measured against energy income.
// It had none at all, which is why eco stagnated while mex was boosted.
// manager/brain/market/want_energy.as [toggle 0/1] -- Discount a generator by
//   how much better a one any constructor we own could build instead, so a
//   worker restricted to the inferior option prefers to spend its build power
//   on the better one. 0 restores flat per-def pricing.
const float TUNE_INFERIOR_DISCOUNT = 1.f;
const float TUNE_ENERGY_GROWTH = 8.f;
// E_REALIZE [toggle 0/1]: the overflow-aware half of the energy market --
// generation priced by the share of it anything would actually use (real
// demand at E_HEADROOM plus standing converter capacity), the converter want
// reading the true remaining waste, and the same eco-compounding premium on
// both halves of the generator/converter pair. 0 restores pricing every E/s
// at the conversion floor whether or not a converter exists to realize it,
// and is the control arm.
const float TUNE_E_REALIZE = 1.f;
// E_WASTE_WORTH: the share of its price that generation KEEPS once nothing
// would use its output. Not zero -- energy in the wasted band is worth the
// conversion floor the moment a converter follows, and that converter's cost
// is already inside the floor; what is missing is only the wait and the risk.
// So an overflow makes a generator LOSE to the converter that realizes it, and
// never makes it unbuildable (apexearth 2026-08-26; his standing ruling is
// that the generator ladder never pauses on waste). Default chosen, not
// derived -- measure it.
const float TUNE_E_WASTE_WORTH = 0.25f;
// Spatial threat prior: 0 at our start box, 1 at theirs. 0 disables it and
// threat goes spatially flat, which is the control arm.
const float TUNE_THREAT_GRADIENT = 1.f;
// RANGE_WORTH: standing weight of weapon reach in unit selection (reach =
// free damage before the answer), on top of the reactive outranging term.
const float TUNE_RANGE_WORTH = 2.f;
// Speed and sight as intrinsic unit value, same shape as range above.
// LOS matters beyond the unit: every danger sense we have reads zero while
// blind, and EnemyArmyCost logged 0 for entire games (2026-08-24).
const float TUNE_SPEED_WORTH = 0.5f;
const float TUNE_LOS_WORTH = 1.f;
// SCREEN_WORTH: the scout/screen axis in production.as -- sight and dash per
//   metal, read INSTEAD OF combat worth when it is the larger of the two, so a
//   unit that is a hopeless soldier can still be a good screen. 0 disables it.
//   0.2 is calibrated, not derived: it puts a Tick modestly ahead of a Pawn at
//   a half-covered patrol shortfall while the Pawn still wins on combat.
const float TUNE_SCREEN_WORTH = 0.2f;
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
// RECLAIM_AGE_S: a con must be at least this old before the surplus
// reclaimer may eat it -- younger is churn against our own buildtime.
const float TUNE_RECLAIM_AGE_S = 180.f;
// LINE_PULL: unserved line spend (m/s) a factory needs before it pulls a
// nano away from the farm block -- two turrets' worth of hunger.
const float TUNE_LINE_PULL = 35.f;
// NANO_SINK_BANK: bank fraction of storage above which "not empty on metal"
// holds and live build sites compete for nano placement by their crew drain.
const float TUNE_NANO_SINK_BANK = 0.1f;
// SQUAD_M: metal value of fielded army that deserves one mobile radar and
// one mobile jammer in support (apexearth: "support squads which are ~2k
// metal value or higher").
const float TUNE_SQUAD_M = 2000.f;
// INTEL_RATE: fraction of a squad's value per minute that its radar/jammer
// pair is worth -- what prices support "just behind T2 cons".
const float TUNE_INTEL_RATE = 0.1f;
// WATER_PCT: minimum real water share of the map before amphib capability
// is worth anything -- a tiny pond must not price Platypuses (his ~15%).
const float TUNE_WATER_PCT = 15.f;
// WATER_FIRST: MODEL. What land-locked metal is worth ON TOP of its own
// stream while the water is still uncontested -- the denial half of taking it
// first ("the earlier you get into the water the more likely you are to own
// it"). 1.0 prices denial equal to the gain; decays with the enemy's navy.
const float TUNE_WATER_FIRST = 1.0f;
// BIG_E: E/s of generation that makes a def "fusion-tier" -- packs in the
// deep rear, earns a nano ring (fusion ~1000, afus ~3000; advsol ~75 not).
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
// AA_URGENCY: multiplier on the insurance rate for anti-air. CHOSEN, matching
// the shield branch's x4 -- air arrives faster than ground and a bombing run
// is over before a reactive build finishes, so it is priced above ordinary
// insurance. Divided by the towers already standing, so it self-limits.
// 4 was compensating for a value that came out ~50x too small (an insurance
// rate on min(their air, our base)); with AA priced like a ground turret the
// multiplier is 1 and the knob still scales it.
const float TUNE_AA_URGENCY = 1.f;
// AA metal we are aiming to have standing per metal of enemy air we have seen
// (apexearth: "if the enemy rolls up with 100k metal worth of air... then I'd
// hope we add at least 50k of AA"). This is what makes the AA want price
// itself out: once cover reaches the target the next tower stops nothing.
// 0.5 reproduces the old apex_def_trade=2 saturation point, now named.
const float TUNE_AA_COVER_FRAC = 0.5f;
// ECO_AA_MULT: the share of the air census the rear eco specialist answers,
// relative to an even split. It holds the team's economy, builds no ground
// defence and keeps no army at home, so it draws more of the air that gets
// through than its headcount share (apexearth: "~50% more anti air than your
// average player").
const float TUNE_ECO_AA_MULT = 1.5f;
// GIFT_ARMY: master switch for back-to-front army gifting. DEFAULT OFF
// (apexearth 2026-08-24: "we are doing the share logic to send units to
// teammates. We should disable that by default. It only is appropriate on
// certain maps"). Handing an army away is only right where the map makes one
// player's front the whole team's front; everywhere else it disarms us.
const float TUNE_GIFT_ARMY = 0.f;
// FRONT_N: how many closest-to-enemy allies count as the front line and
// receive the team's ground army (his read of this map: 2).
const float TUNE_FRONT_N = 2.f;
// JOIN_MIN_M: def cost above which a second builder JOINS the standing
// build instead of opening a parallel copy (fusion-and-up territory).
const float TUNE_JOIN_MIN_M = 500.f;
// ECO_LEASH: work radius of the quiet rear's builders from home -- the
// safe radius it prices everything else against.
const float TUNE_ECO_LEASH = 2500.f;
// ECO_CON_KEEP: land T1 cons the quiet rear always keeps -- nano turrets
// and small works still need hands (his floor-of-3 number).
const float TUNE_ECO_CON_KEEP = 3.f;
// T2_CON_BASE / T2_CON_PER_M: how many cons able to build the game's best
// extractor we always want standing -- BASE plus one per PER_M of metal
// income (apexearth 2026-08-23: "1 T2 con + 1 per 25 metal ... at 100 metal
// per second we should have at least 5"). Under that count a factory line
// orders one outright instead of pricing it against the army draw, which it
// loses whenever the army gap is open -- which is nearly always.
const float TUNE_T2_CON_BASE = 1.f;
const float TUNE_T2_CON_PER_M = 25.f;
// manager/brain/market/production.as [count] -- constructors of ANY TIER the
//   line orders before the draw, the plain "how many hands" floor. The block
//   above is narrower than its name suggests: it counts only cons that reach
//   BestExtract(), which scans every available def and so means the MOHO, so
//   no T1 con and no commander ever satisfied it. 2.7 + inc/44 is apexearth's
//   own two points: 3 at 12 metal/s, 5 at 100. A floor, not a cap.
const float TUNE_CON_BASE = 2.7f;
// manager/brain/market/production.as [metal/s per extra constructor]
const float TUNE_CON_PER_M = 44.f;
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
// manager/brain/market/want_reclaim.as [multiplier] -- How much more a reclaim
//   is worth in the hands of a dedicated reclaimer (rezbot: builds nothing, so
//   it has no expansion to be pulled off) than in the hands of a constructor
//   that could be claiming open ground instead. A PREFERENCE, applied both ways
//   around 1: the con still reclaims when its list holds nothing better, and
//   the penalty lifts entirely once no metal spot is open. 1 disables.
const float TUNE_RECLAIM_REZ_BIAS = 3.f;
// manager/brain/market/want_nano.as [share] -- How much of the metal nothing is
//   spending one build site may claim as nano demand. Replaced a bare 35 m/s
//   clamp that two turrets saturated at any income, which is why factories and
//   gantries stood on 2-5 nanos while an enemy gantry ran 38. Demand still nets
//   off the crew and the turrets already there, so the count self-limits.
const float TUNE_NANO_SITE_SHARE = 1.f;
// manager/brain/market/want_mex.as [count] -- Ranked metal spots offered to the
//   engine per election before extraction gives up for that tick. Was a bare 3:
//   a builder whose three best spots were all claimed proposed no mex want at
//   all, which reads as "no ground left". A bound on WORK (one engine probe
//   each), never on how far we may expand.
const float TUNE_MEX_TRIES = 10.f;
// manager/brain/market/want_reclaim.as [multiplier] -- What the ROOM under an
//   obsolete building is worth, as a multiple of (base fill x metal per build
//   cell x the building's own cells). SpaceRentM prices ground by the turret
//   cover over it and reads ~0 in a lightly defended base, so nothing charged a
//   wind farm for the space it occupied. 0 disables scarcity pricing.
const float TUNE_ROOM_WORTH = 1.f;
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
// ---------------------------------------------------------------------------
// Strategic structures -- manager/brain/market/want_super.as
// ---------------------------------------------------------------------------
// SUPER_WANT: master switch for the strategic want (gantry, nuke silo,
//   anti-nuke, long-range gun). 0 disables it.
const float TUNE_SUPER_WANT = 1.f;
// SUPER_PUSH: 1 = an affordable strategic want skips the category lottery
//   rather than taking a proportional share of it. Off, these are priced
//   normally and drawn about once a game.
const float TUNE_SUPER_PUSH = 1.f;
// SUPER_AFFORD_S [seconds] -- the whole affordability test: the bill (metal
//   plus energy at the conversion floor) must be smaller than what the economy
//   makes in this many seconds. 60 puts the anti-nuke at ~36 metal/s, the
//   long-range gun at ~90 and the gantry and silo at ~160 -- his "at 200 m/s
//   we should eagerly build one".
const float TUNE_SUPER_AFFORD_S = 60.f;
// SUPER_PER_INCOME [metal/s] -- income per additional anti-nuke; the offensive
//   classes (silo, long-range gun) space at twice this. Never a cap: the count
//   rises with the economy, which is his "at least 1 usually, more if we want
//   to be safer".
const float TUNE_SUPER_PER_INCOME = 150.f;
// SUPER_SHARE: the slice of total economic power the strategic market may
//   claim as a want's gain. Scaled by how much budget is left after the bill.
const float TUNE_SUPER_SHARE = 0.25f;
// SUPER_FLIGHT_PER [metal/s of overflow] -- one strategic frame may stand
//   half-built per this much structural overflow, on top of the base one.
//   The single-frame focus law is for an economy that must choose; one
//   throwing metal away has already chosen.
const float TUNE_SUPER_FLIGHT_PER = 140.f;
// COPY_OVERFLOW_M [metal/s] -- the wealth waiver: overflow above this lifts
//   the plant-copy ban and the one-advanced-plant-at-a-time serialization
//   ("make more nanos around our gantry and if we can't do that then make
//   another gantry"; "multiple adv air are ok if we are crazy wealthy").
const float TUNE_COPY_OVERFLOW_M = 140.f;
// BLAST_AISLE [elmos] -- gap between a BIG generator's own clusters, so one
//   death explosion cannot chain the whole farm ("better if only half our
//   economy blows up"). Chosen, not derived from the defs' blast radii.
const float TUNE_BLAST_AISLE = 500.f;
// CON_FEED_HEADROOM -- how many hands the production draw may price toward,
//   as a multiple of income/apex_request_drain (the hands income keeps fed).
//   A new con's gain scales with the room left under that line; at 1.5 a
//   52 m/s economy stops paying for its eleventh builder ("I have a hunch
//   we make too many constructors").
const float TUNE_CON_FEED_HEADROOM = 1.5f;
// UNIT_AFFORD_S [seconds of income] -- a mobile unit's bid fades as its cost
//   approaches this much income, dying at the full bill (mass first, T3 from
//   surplus -- the supers' 60s affordability bar applied to units). His call
//   2026-08-29 ("we need more Titans or Thors so we can push"): 60 -> 120,
//   so a Thor bids from 75 m/s and a Titan from 112 instead of 150/225,
//   while mass still out-prices them at any income that can't spare the bill.
const float TUNE_UNIT_AFFORD_S = 120.f;
// DEF_SETBACK [elmos] -- front defence sites step this far back from the
//   contested edge toward home, so the frame survives building; most tower
//   ranges (430+) still cover the edge it stepped back from.
const float TUNE_DEF_SETBACK = 250.f;
// SCOUT_OVER_S [seconds] -- one idle cheap air scout is sent across the
//   enemy position this often ("I don't see any scouts flying over their
//   base"). 0 disables the overflight and stock mex-cluster scouting is all
//   that remains.
const float TUNE_SCOUT_OVER_S = 45.f;
// ECO_ROLE -- master switch for the rear-specialist election and everything
//   behind it (army suppression, quality bias). OFF by his ruling
//   2026-08-29: "it does *not* work"; 1 re-arms the experiment.
const float TUNE_ECO_ROLE = 0.f;
// GANTRY_AFFORD_S [seconds] -- the gantry's affordability horizon, over TEAM
//   income: one shared line the whole team's nanos man, so one team purse.
//   At 100s the ~9.3k bill clears right at ~100 team metal/s, his stated
//   mark ("we can have a gantry at like 100 m/s").
const float TUNE_GANTRY_AFFORD_S = 100.f;
// GANTRY_INSURE: the gantry's capability-insurance gain as a share of team
//   income ("if the enemy comes at us with a Behemoth and we do not have one
//   we are in big trouble") -- the answer to enemy T3 is worth this even with
//   no army gap and no overflow on the books.
const float TUNE_GANTRY_INSURE = 0.5f;
// GANTRY_HOST_INC [metal/s] -- the proposing player's OWN income at which the
//   gantry gain is whole; below it the gain scales by (own/anchor)^2. The team
//   purse makes the case, the host's feed times it (apexearth, watching green
//   start one at 50 m/s: "that is too early").
const float TUNE_GANTRY_HOST_INC = 100.f;
// OFFENSE_DEF_FLOOR: the share of its gain an offensive super (silo, LRPC)
//   keeps at ZERO standing defence; the rest scales in with the defence
//   target's fill ("we consistently make Basilisk before T3 or even T2
//   defense"). 1 disables the coupling.
const float TUNE_OFFENSE_DEF_FLOOR = 0.1f;
// ANTINUKE_R [elmos] -- an anti-nuke's assumed umbrella, for deciding whether
//   ground is already covered by one we own.
const float TUNE_ANTINUKE_R = 2000.f;
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
// FRAME_RISK: weight on the loss expected DURING a build, charged at the same
// hazard rate as a standing asset but across the build's own duration. 1.0 is
// "a nanoframe is exactly as likely to be lost per second as the finished
// thing"; higher says a defenceless frame is worse than that. This is the only
// term that separates a slow expensive structure from a fast cheap one.
// DEFAULT 0 -- the mechanism is wired but priced out. At 1.0 it suppressed
// building outright rather than reordering it: total metal built fell 38.6k ->
// 17.6k and the head-to-head went 3-21 to 0-30 over 54 paired games. The charge
// is a full standing expected-loss multiplied by buildSec/120, which for a
// several-hundred-second structure exceeds its whole gain. Re-enable only with
// a hazard field that is not saturated everywhere (see the front-geometry
// entry in ISSUES.md).
const float TUNE_FRAME_RISK = 0.0f;
// DEF_TRADE: metal of enemy wave a standing turret is expected to stop, per
// metal of its own cost. The exchange rate that puts coverage and threat in
// one currency so a shortfall can be subtracted.
const float TUNE_DEF_TRADE = 3.f;
// DEF_TTD_H: the window a turret has to be STANDING in to be worth its gain.
// A defence is discounted by H/(H+buildSec), so a slow turret keeps only the
// share of the threat window it will actually cover. Defaults to the same 120 s
// EXPOSED_LOSS_S uses -- a turret that takes as long to build as the asset it
// guards takes to die is worth half of one that lands instantly. LOWER means
// sharper pressure toward quick defences (a Guard at 2500 buildtime over an
// Agitator at 17400); 0 restores the old behaviour, where build time reached
// the price only through the builder's wage.
const float TUNE_DEF_TTD_H = 120.f;

// How often the protection field is rebuilt, in game seconds. It walks every
// team unit once and every defence price reads it, so this is the knob between
// a stale stake and a stalled sim -- want.protect was measured at 9.2 ms per
// call and growing before the field existed.
const float TUNE_PROTECT_FIELD_S = 2.f;

// How often the energy-stall answer re-asks which worker should drop what it is
// doing. Split from the 5-second housekeeping tick it used to share: a stall
// costs income every second it holds, so the answer wants the fast cadence,
// while the retreat table and the guard sweep do not. The scan stops at the
// first worker whose top want is energy (commander first), so a faster tick
// costs less per call rather than more.
const float TUNE_STALL_ANSWER_S = 1.f;

// Energy income above which the stall answer stops asking at all. apexearth's
// number: past this the economy is big enough that an energy stall is a
// transient in the pull rather than something worth pulling a constructor off
// its task for. 0 disables the gate and asks at every income.
const float TUNE_STALL_ANSWER_MAX_E = 400.f;

// WHAT A BUILDING IS WORTH WHILE NOTHING GUARDS IT (apexearth: "give buildings
// a ~20% reduced value when they are unprotected. And the more powerful we
// create defense around those buildings the more they become worth"). The share
// of a structure's worth that is withheld over ground our cover does not beat
// the local wave on, and that a turret covering it gives back.
const float TUNE_UNPROT_DISCOUNT = 0.20f;

// A TURRET ONLY SHOOTS WHILE IT IS ALIVE. Weights each turret's cover by
// hp/(hp+alpha) against the punch of the biggest mobile unit the enemy fields,
// derived through our own unit table. Near 1 for everything while they field
// raiders; it is what separates a 1,670-hp Twin Guard from a 9,400-hp Bulwark
// once they field something that erases the former in one pass. 0 disables it.
const float TUNE_DEF_ALPHA_W = 1.f;
// ECO_RAID_TAU: seconds of memory in the structure-loss field. Matches the
// death ledger's BLEED_TAU so both risk senses forget at the same speed.
const float TUNE_ECO_RAID_TAU = 180.f;
// THREAT_R: radius the enemy-mass prior is sampled over. DeathWalk's own
// corridor sample, reused rather than re-invented.
const float TUNE_THREAT_R = 900.f;
// STAKE_HORIZON_S: seconds of a mex's stream that count as the stake standing
// on it. What makes a producing mex worth more to lose than its build cost.
const float TUNE_STAKE_HORIZON_S = 300.f;
// RISK_FLOOR: pressure a never-attacked asset still carries, so cold start
// insures something before the first loss teaches us. His "combination of
// enemy aggression and how well defended we are" -- this is the floor half.
const float TUNE_RISK_FLOOR = 0.15f;
// GUARD_RATE: standing army value as a fraction of structure assets -- the
// insurance floor that also covers census blindness.
const float TUNE_GUARD_RATE = 0.2f;
// ENEMY_PRIOR: pre-contact estimate of enemy army as a share of OUR total
// value (symmetric start); the observed census replaces it once larger.
const float TUNE_ENEMY_PRIOR = 0.25f;   // 0.35 + a continuous line drained the bank into army (watched: out of metal)
// MATCH_RATIO: army fielded per metal of enemy army SEEN.
const float TUNE_MATCH_RATIO = 1.2f;
// ALLY_SHARE: 1 = scale the SEEN census in ArmyTarget by our income share of
// the team (the census is side-wide; the answer is split by the roster).
// 0 = every player answers the whole enemy team (the pre-2026-08-28 form).
const float TUNE_ALLY_SHARE = 1.f;
// ARMY_FILL_S: seconds over which an army-value gap counts as a stream.
const float TUNE_ARMY_FILL_S = 180.f;   // the 120 compensation was fighting the Wait throttle, not the price; with the line continuous, 180 shares honestly
// REZ_HORIZON: seconds to recover the field's wreck pool; rez production
// scales with losses and diminishes per bot.
const float TUNE_REZ_HORIZON = 120.f;
// REZ_RICH_M [metal]: a corpse at least this rich is RESURRECTED whatever
// the pre-AFUS eat-the-field doctrine says -- a unit for the rez cost
// ("we shouldn't be reclaiming something like that", on a Vanguard corpse).
const float TUNE_REZ_RICH_M = 900.f;
// AA_MATCH: our AA value per metal of enemy air seen.
const float TUNE_AA_MATCH = 0.7f;
// RETREAT_COST_SCALE: metal at which a unit's retreat threshold reaches
// ~+0.33 over the floor (retreat = floor + cost/this, cap 0.5) -- cheap
// units fight to the end, expensive ones preserve.
const float TUNE_RETREAT_COST_SCALE = 3000.f;
// RETREAT_FLOOR: the HP fraction where the cheapest unit starts to flee.
// 0.08 was set against stock's 0.6 (93% of combat metal died retreating);
// his 2026-08-28 report is the other rail ("units retreat on a very low
// HP %" -- a sliver-HP flee dies anyway). Raise only with a deaths.py
// died-retreating measurement beside it.
const float TUNE_RETREAT_FLOOR = 0.08f;
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
// AID_RESPOND [metal lost at an ally's hotspot] -- above this the staging
//   lane moves to that fight (clamped to contested ground). 0 disables the
//   response and leaves the hotspot publish-only, as it was.
const float TUNE_AID_RESPOND = 1000.f;
// manager/military/defenceline.as [elmos] -- How far defence aid will travel;
//   -1 follows the measured base separation live (a fixed default would freeze
//   before home is set).
const float TUNE_AID_REACH = -1.f;
// manager/military/hooks.as [toggle 0/1] -- Mobile artillery masses into the
//   squad pool (long-range back row, allied vision, kite/set-target) instead
//   of soloing on CArtilleryTask, which only elects static targets and walks
//   in blind (weapon range exceeds own sight for the whole family).
const float TUNE_ARTY_MASS = 1.f;
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
// manager/brain/market/want_protect.as [toggle 0/1] -- Every gate of our held
//   territory (choke with our side ours, far side not) is a defence-site
//   candidate, priced by what it shields; 0 keeps only the near-anchor choke.
const float TUNE_CHOKE_GATES = 1.f;
// manager/brain/market/want_protect.as [toggle 0/1] -- Every OPEN bearing of
//   the closure ring (approach angles no standing gun covers, map edges count
//   as walls) offers a defence-site candidate, so flanks and the rear are for
//   sale at every angle; 0 leaves only asset/gate/front candidates.
const float TUNE_DEF_RING = 1.f;
// manager/brain/market/want_protect.as [toggle 0/1] -- A defence site prices
//   against the enemy's whole fielded army (capped by the stake behind the
//   site), not a per-site share of it: their mass all takes one approach, and
//   the rate term already says how often. This is what lets a Pulsar-class
//   gun out-bid a carpet of cheap towers once the enemy fields real weight.
const float TUNE_WAVE_CONC = 1.f;
// manager/brain/market/protect_wall.as [toggle 0/1] -- Ground defence sites
//   are slots along the WALL: the rim of our own buildings plus a standoff,
//   sampled at tower pitch so filled slots form a contiguous line that grows
//   with the base. Replaces the asset-cluster, front-line and closure-ring
//   candidates (gates and the ally-front post stay); 0 restores the old set.
const float TUNE_WALL = 1.f;
// manager/brain/market/protect_wall.as [fraction of light-tower range] -- How
//   far outside the outermost building on each bearing the wall stands, so
//   the guns meet the approach before it reaches what they guard.
const float TUNE_WALL_STANDOFF = 0.5f;
// manager/brain/market/protect_wall.as [fraction of light-tower range] -- Arc
//   spacing between wall slots. At or below 2.0 adjacent light towers' fields
//   overlap; lower is a denser wall.
const float TUNE_WALL_PITCH = 1.2f;
// manager/brain/market/protect_wall.as [ratio] -- Cap on how far one bearing's
//   buildings can drag the wall, as a multiple of the worth-weighted RMS
//   radius of everything we own. A lone far mex stays outside the wall; a
//   real expansion moves the RMS and the wall follows.
const float TUNE_WALL_REACH = 2.5f;
// manager/brain/market/protect_field.as [fraction of tower reach] -- Asset
//   guard sites stand this far enemy-ward of the asset centroid, between the
//   buildings and the approach; 0 sites the gun amid the buildings.
const float TUNE_GUARD_FORWARD = 0.5f;
// manager/brain/market/want_protect.as [ratio] -- A T1 tower's gain once any
//   standing advanced builder can produce ground defence; 1 prices tiers
//   equally.
const float TUNE_T1_DEF_LATE = 0.15f;
// manager/brain/market/want_protect.as [fraction of radar radius] -- A gap
//   must sit outside this share of every standing radar's reach before a new
//   mast is blocked; lower = more overlapping radars, sturdier intel. Was a
//   hardcoded 0.8 (no redundancy; one death = a dark zone mid-fight).
const float TUNE_RADAR_OVERLAP = 0.45f;
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
//   1 is the ESCAPE HATCH -- the full ring, for a genuinely surrounded base.
//   It shipped as the default, so the rear exclusion the ring scan was written
//   around had never once run: measured rays=24/24 with the enemy on one
//   bearing, which is the ring closing on itself that its own comment warns of.
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
// NANO_FED_S [seconds] -- a join is refused when standing-nano lathe alone
// clears the site's remaining bill within the joiner's walk plus this many
// seconds; the freed constructor founds a new frame instead (a nano can
// assist a frame but never place one). Sized to the walk-and-found time of
// the next ring spoke. 0 disables the gate.
const float TUNE_NANO_FED_S = 15.f;
// manager/brain/market/decide.as -- how sharply the category draw follows
// value. Odds go as (value/leader)^this: 1 is the old straight-proportional
// draw, 2 makes a six-fold value gap one election in thirty-six, large
// approaches argmax. Never a threshold, so nothing starves outright.
const float TUNE_DRAW_SHARP = 2.f;
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
// manager/builder/rules_rezzer.as [seconds] -- how long one hit keeps a rez bot
//   retreating. A rez bot cannot dig in, only leave, but the hold was 90s: one
//   stray shell parked it for a minute and a half. Lower works sooner and eats
//   more chip damage; the threat vetoes still refuse hot work on the way back.
const float TUNE_REZ_FLEE_S = 20.f;
// manager/builder/rules_rezzer.as [seconds] -- spacing on ONE bot's own wreck
//   and resurrect scans. Was a single team-wide clock, so with several bots
//   idle most of them lost the race every period and stood still. Lower is
//   more responsive and costs one feature query per bot per period.
const float TUNE_REZ_SCAN_S = 1.f;
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
// manager/brain/market/sites.as [count] -- Lattice slots offered to the engine
//   before a placement gives up on growing a cluster and seeds a new one. A
//   bound on WORK per placement: each try is one FindBuildSiteNear.
const float TUNE_SLOT_TRIES = 12.f;
// manager/brain/market/sites.as [toggle 0/1] -- A GROW slot must keep the
//   cluster aisle to a foreign def, not just avoid touching it. Rule 3 parted
//   clusters by an aisle on the SEED only, so growth filled the street back in
//   and sealed units into the pocket. Trades against sprawl: a cluster that
//   cannot grow toward its neighbour seeds another one further out.
const float TUNE_AISLE_GROW = 1.f;
// manager/lattice.as [count] -- How many of one def stand together before the
//   next starts a fresh cluster elsewhere, so the whole economy is not in one
//   spot. 16 is a 4x4 block; the aisle between clusters is derived from the
//   widest unit we field, not tuned here.
const float TUNE_CLUSTER_N = 16.f;
// manager/brain/market/sites.as [count] -- Rows of lattice the farm scan walks
//   rearward before giving up. A bound on WORK per placement, not on the base.
const float TUNE_FARM_ROWS = 28.f;
// manager/brain/market/want_reclaim.as [toggle 0/1] -- Reclaim one of our own
//   economy buildings that is standing in a lattice slot C++ could not place
//   on. DEFAULT OFF: measured 2026-08-25, 8 paired seeds, it cost more
//   constructor time than the ground was worth -- metal built median 17,978
//   with it off against 12,417 with it on, eco 5,436 against 3,869, and even
//   the tiling it exists to improve fell (47% touching to 39%). The pricing
//   and the C++ blocked-slot signal stay for a cheaper retry: the want has to
//   compete against a mex, and clearing ground is not worth a mex.
const float TUNE_RECLAIM_BLOCKER = 0.f;
// manager/brain/market/want_protect.as [seconds] -- HOW MUCH STATIC DEFENCE WE
//   MAY OWN, as seconds of total economic power (EcoPowerM, metal/s incl.
//   realizable energy). The whole basis of DefenceTarget: at 40 metal/s this
//   is ~1,200 metal, a handful of light towers; at 400 it is ~12,000, enough
//   to carry a Pulsar. Replaced (expected wave - our own army) / trade, which
//   collapsed the target to a mex floor exactly as the army grew. 30 was
//   chosen to clear one heavy gun at hosted-game income and starved the low
//   end: at benchmark's ~25 m/s it budgeted 750 metal of defence for a whole
//   game while stock stood 11,700-17,800 in the same matches -- the naked
//   rear the death ledgers measured everywhere. 120 is the measured
//   recalibration, still far under the pre-target 175%-of-eco runaway.
const float TUNE_DEF_ECO_S = 120.f;
// manager/brain/market/want_energy.as, price.as [toggle 0/1] -- Count the
//   energy draw of work already ORDERED into the pull that prices energy.
//   Not a magnitude: the quantity added is arithmetic off the catalog
//   (remaining E cost over remaining build seconds), exactly as
//   ConvCapInFlight already does for converter capacity. 0 is the control arm,
//   pricing on realized pull alone -- which is where the first energy decision
//   lands 73 seconds and one full stall after pull passed income.
const float TUNE_E_COMMITTED = 1.f;
// manager/brain/market/want_energy.as, execute.as [toggle 0/1] -- Let a STALL
//   open parallel energy sites, not only an overflowing bank. Energy asks fold
//   onto one standing request unless the bank spills, and during a stall it
//   never does -- so a 300/s deficit was answered 35/s at a time, serially.
//   Opens exactly while ordered generation still fails to cover the shortfall.
//
//   MEASURED AND DEFAULTED OFF. Three paired 20-minute Carrot Mountains seeds:
//   with it on, metal built 25,500 -> 19,555 and mexes 42 -> 33, for a stall
//   reduction of 444 -> 352. It buys the smaller stall by splitting build
//   power across several frames at once -- which is the same thing this AI
//   penalises a second lab for, and against apexearth's own rule to "focus as
//   much build power as we can on just the one building". The serialized fold
//   is not the bug; it is that focus rule working.
const float TUNE_E_PARALLEL = 0.f;
// manager/brain/market/want_plant.as [toggle 0/1] -- Discount a plant want by
//   the plants of ANOTHER domain already under construction. reachKin is per
//   domain, so bot -> vehicle -> air rotated freely: each new class priced as
//   though nothing were in flight, and the same income split across three
//   frames finishes none of them.
const float TUNE_PLANT_INFLIGHT = 1.f;
// manager/brain/market/decide.as [seconds of economic power] -- The mex-cover
//   QUEUE JUMP only fires once the tower costs less than this many seconds of
//   total economic power. The jump overrides the auction outright (measured:
//   an LLT priced 0.03 built ahead of a mex priced 88.17), so at opening
//   income it buys sentries before there is a base. 10s means a 90-metal light
//   tower waits until roughly 9 metal/s of economic power -- past the first
//   mexes and the first lab, which is the order apexearth asked for -- while a
//   1,250-metal Gauntlet has to wait for 125. Below the bar the tower still
//   competes on price like anything else.
const float TUNE_COVER_PUSH_S = 10.f;
// manager/brain/market/want_tech.as [multiplier] -- What a mex UPGRADE'S extra
//   metal stream is worth, over its honest arithmetic. 2.79 is the measured
//   median ratio by which energy was beating mex upgrades head to head when
//   an upgrade ranked second (394 such losses in one 60-minute game), so at
//   this value the two are level at the median rather than extraction always
//   losing. 1 is the arithmetic with no thumb on it.
//
//   MEASURED AT 2.79 AND LEFT AT 1. Paired 60-minute Carrot Mountains games:
//   the boost does exactly what it claims -- mex upgrades go from 7% of
//   advanced-con decisions to 33% and become the most-chosen want -- and the
//   OUTCOME is worse. Upgrades actually standing fell 94 -> 69, mexes held
//   243 -> 182, metal built 863k -> 358k, income 1001 -> 377. It displaces the
//   energy that pays for expansion, so there are fewer mexes left to upgrade.
//   One game per arm on a bench that does not reproduce, so treat the
//   direction and not the size -- but nothing here supports shipping it above
//   1 (apexearth's own rule: validate outcomes, not log lines).
const float TUNE_MEXUP_BOOST = 1.f;
// manager/brain/market/want_plant.as [toggle 0/1] -- Price a DUPLICATE line's
//   throughput against the cheaper way to buy the same build power. An
//   advanced lab is 300 workertime for 2900 metal and a construction turret
//   200 for 210, so the turret is nine times the build power per metal
//   (apexearth: "the right choice is to add more nanos to the lab instead of
//   making another lab"). Applied only while a line is actually short of
//   hands, which is his "unless you ran out of room" clause. The one bad game
//   that got this defaulted off predates nano frames actually completing --
//   with nanos never finishing, this discount removed the only build-power
//   purchase that ever completed. 0 is the control arm.
const float TUNE_DUP_BP_SUBST = 1.f;
// manager/brain/market/want_plant.as [multiplier] -- What a plant def we
//   RECLAIMED ON PURPOSE prices at while the window below runs. 14 of 15 T2
//   bot labs in one 1v1 died to our own reclaim and were re-bought; a
//   retirement the market can immediately reverse decides nothing. 1 disables.
const float TUNE_REPLANT_DISCOUNT = 0.15f;
// manager/brain/market/want_plant.as [seconds] -- How long the retirement
//   memory above holds. Chosen, not derived -- long enough to outlive the
//   walk-and-rebuild cycle it exists to break (~90s), short enough that a
//   genuinely needed line returns inside a game phase.
const float TUNE_REPLANT_WINDOW_S = 600.f;
// manager/brain/market/worth.as, want_plant.as [ratio] -- How fast a unit's --
//   and a plant's PRODUCTION -- value fades as the share of identified enemy
//   metal above its own tier rises. Priced as 1/(1 + this * shareAbove): at 1
//   an enemy fielding nothing but a higher tier halves what a lower-tier unit
//   or line is worth. Never zero, because a fielded T1 still shoots; 0 is the
//   control arm. Chosen, not derived -- measure it.
const float TUNE_FOE_TIER_FADE = 1.f;
// manager/brain/market/worth.as [ratio] -- The same fade against OUR OWN
//   fielded tier: once a T2 lab or gantry stands, lower-tier units lose
//   1/(1+this*tiersBelow) of their worth ("in late game, aside from spam we
//   should mostly only be putting our resources into T3 units and advanced
//   air"). 0 disables.
const float TUNE_OWN_TIER_FADE = 0.8f;
// manager/brain/market/worth.as [metal] -- Units cheaper than this are SPAM
//   and exempt from the own-tier fade (his ruling names spam as the late-game
//   exception). Chosen, not derived: Pawn 54, Rascal 30, Flash ~110.
const float TUNE_SPAM_COST = 150.f;
// manager/brain/market/want_protect.as [ratio] -- The rear eco specialist's
//   defence and army targets, as a share of a normal player's. Its threat is
//   already near zero by position, so this only holds the tail down; it is a
//   how-much, never a whether -- if something starts killing it, ThreatM at
//   its home rises and the target rises with it.
const float TUNE_ECO_DEF_MUL = 0.f;
// manager/brain/market/coverage.as [metal per unit of ally influence] -- What a
//   teammate holding this ground is worth as cover, in the same currency as
//   our own towers. 0 restores the own-towers-only reading, in which a rear
//   player behind four allies prices as the most dangerous ground on the map.
const float TUNE_ALLY_COVER = 400.f;
// manager/brain/market/want_protect.as [ratio] -- Share of the SYMMETRIC
//   enemy expectation that the defence target assumes could arrive at our own
//   base before anything has been seen. Without it the target is zero until
//   something actually arrives, which is a strategy of having no defence.
const float TUNE_DEF_PRIOR_SHARE = 0.35f;
