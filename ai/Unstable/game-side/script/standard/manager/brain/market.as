//------------------------------------------------------------------------------
// THE BUILDER MARKET, prototype 1 (docs/how-it-works.md, value-paradigm
// skill). Every choice is a priced Want in one currency:
//
//   value = gain / (mCost + tCost)          [ (metal/s) per metal = 1/s ]
//   gain  = metal/s-equivalent return once standing
//   mCost = costM + costE priced at the conversion floor
//   tCost = (walk + build) seconds x the wage of a builder-second
//
// Proposers are pure; Decide() is the only spender. Every decision logs its
// arithmetic. Modeled terms (not read from defs) are marked MODEL -- they are
// where tuning lives, one named quantity each.
//------------------------------------------------------------------------------

// namespace Market, split across market/. THE ORDER BELOW IS LOAD-BEARING --
// see manager/builder.as for why. Senses and ledgers come first, then the
// Want proposers, then the two spenders (Decide, ExecuteWant), then the
// production side.
#include "market/kinds.as"          // the Want record, the kind ids, their names
#include "market/ecodef.as"         // defence as a crutch: the five pricing switches and their stat line
#include "market/worth.as"          // what a combat unit is worth: the golden metrics
#include "market/price.as"          // the two live prices, and ValueOf
#include "market/ledger.as"         // spot-value senses; the claimed-spot ledger
#include "market/census.as"         // what we own: counts, protection classes, unit events
#include "market/commit.as"         // the commitment ledger: ordered/framed/finished structures
#include "market/coverage.as"       // measured risk: what reaches an asset, what is dying
#include "market/protect_measured.as" // the measured attack rate defence is valued on (apex_def_measured)
#include "market/splash.as"         // splash against the enemy ball: extra hits a tower's blast catches
#include "market/protect_field.as"  // what we own, what guards it, where a guard could go
#include "market/want_mex.as"       // upgrade demand, walk safety, the mex Want
#include "market/want_energy.as"    // energy/convert/store Wants; the BP senses behind them
#include "market/want_plant.as"     // geothermal and factory-plant Wants
#include "market/want_tech.as"      // mex upgrade and tech-plant Wants
#include "market/plot.as"           // room for a gantry: spare labs reclaimed, the ground held for it
#include "market/sites.as"          // where a build goes: farm rows, spot clearance, eco sites
#include "market/nanopack.as"       // where an ASSIST nano stands: the packed lattice
#include "market/labnano.as"        // apex_lab_nano: a turret at a lab priced by the army it adds there
#include "market/want_nano.as"      // the nano Want
#include "market/guards.as"         // stall sweep, guard/escort ledger, worker ledger
#include "market/escnet.as"         // escort strength net, existing raiders recruited to escort
#include "market/econet.as"         // constructor-floor and expansion nets
#include "market/armynet.as"        // tier-mix and anti-air heads
#include "market/plannet.as"        // the team plan net; allies build one gantry together
#include "market/joinnet.as"        // join a same-def site already rising, or open a new one
#include "market/army.as"           // the army model, eco role, targets, StallWatch
#include "market/rush.as"           // their army racing a big investment of ours: floor and tech price
#include "market/pressure.as"       // short contact: shorter horizon, team push, contest their expansions
#include "market/mapshare.as"       // under our share of the extractor spots: army nudge, aggression, claim value
#include "market/smallhard.as"      // short path contact: army to their strength at arrival, starve their extractors
#include "market/earlyball.as"      // short contact: the cheap fast ball priced by the base it razes, sent whole; field watch; air scouts
#include "market/openrace.as"       // the lab's con floor against its best fighter on one clock; stalls priced, not idled
#include "market/countermix.as"     // the army draw priced by fight value against the army we have seen; raid value round what it cannot fight
#include "market/spotrace.as"       // open spots by who reaches them first: a con's marginal claims, the army's contest targets
#include "market/expandfar.as"      // apex_expand_far: a claim priced by P(we hold it), no threat bar refuses it
#include "market/ecoreturn.as"      // apex_eco_return: eco builds by return at the energy available; army extras follow the threat
#include "market/liveban.as"        // apex_live_not_ban: site judgements read live or priced, never held on a clock
#include "market/ecoseat.as"        // the strict eco seat: what its hands and labs may take while it grows
#include "market/teamtech.as"       // one seat techs and hands out advanced cons; the others price their own lab down
#include "market/stuck.as"          // the stuck-builder watchdog: no progress, no movement
#include "market/floor.as"          // the job ledger, the value ranking, the never-idle floor
// want_protect, split (order load-bearing -- see manager/builder.as):
#include "market/protect_census.as"     // the gate census, the decomposition log, tower counters
#include "market/protect_sense.as"      // edge/crowd/radar/jammer senses, closure, the class halves
#include "market/protect_target.as"     // the mex floor, DefenceValue/DefenceTarget, TargetFill
#include "market/protect_shelled.as"    // the shelled census: long-range fire on our statics, and the jammer under it
#include "market/protect_knot.as"       // knots of mutual support, and the bearing they face
#include "market/protect_fill.as"       // DefSiteFill: every site's prevented loss, cached per def
#include "market/protect_teeth.as"      // the choke-teeth Want
#include "market/protect_senseprice.as" // radar/jam/shield/AA/targfac prices
#include "market/aathreat.as"       // apex_aa_threat: AA sized and sited where their air hurts us
#include "market/protect_refill.as"     // a gun the enemy killed: the same gun back on its gap
#include "market/jamsight_want.as"      // apex_jam_sight: a sight post over a force we suspect
#include "market/protect_want.as"       // ProposeProtectHalf: the defence election itself
#include "market/protect_choke.as"  // the choke: the narrowest crossing the line stands on
#include "market/protect_team.as"   // the team hull and its gaps: where they can walk in
#include "market/protect_wall.as"   // the wall: perimeter slots ground defence fills
#include "market/want_super.as"     // the strategic Want: gantry, silo, anti-nuke, big guns
#include "market/want_assist.as"    // the assist Want
#include "market/want_reclaim.as"   // the obsolete-reclaim Want
#include "market/lift.as"           // idle turrets flown to the short line
#include "market/lift_ferry.as"     // front towers built at home and flown up
#include "market/safety.as"        // commander self-preservation, ahead of the auction
#include "market/rehome.as"        // a lost base is left: home moves to the safest ground we can reach
#include "market/eta.as"            // the economy-only ETA target and its ladder
#include "market/roles.as"          // constructor roles: the split of need, who holds which
#include "market/crew.as"           // the field crew and the home crew
#include "market/defrole.as"        // advanced hands held on advanced guns while that gap is open
#include "market/nnweights.as"      // the value net, written by tools/nntrain.py into the deployed copy
#include "market/nnlog.as"          // the decision record a value net trains on
#include "market/policydata.as"      // the policy net's layout and best weights, written by tools/neuro.py
#include "market/policy.as"          // the policy net: one evolved network decides every head
#include "market/comdecide.as"      // the commander's situation and answer, recorded for a commander net
#include "market/comship.as"        // the base dying with its defence beaten: he steps in, never runs
#include "market/comhome.as"        // small maps: his time away from the lab priced as army, the base he defends, his walk-ins
#include "market/nntech.as"         // the T2 decision: now or wait, recorded for a T2 net
#include "market/t2eco.as"          // apex_t2_eco: the ladder's evidence for the next tier; upgrades before the strategic hoists
#include "market/protect_nn.as"     // leaks, and static defence's amount and site as recorded draws
#include "market/protect_nntype.as" // which gun class a ground-defence want builds, as a recorded draw
#include "market/protect_keepout.as" // keep-out census: the alliance perimeter's gaps, and who closes each
#include "market/opennet.as"        // the opening order: one recorded draw, followed until the plant
#include "market/decide.as"      // the arbiter: rank the Wants, pick one
#include "market/execute.as"        // turning a won Want into a task
#include "market/crewelect.as"      // one election per crew: nearby hands of a def share its answer
#include "market/lineobs.as"        // a lower line's unit against the best line we own and can afford
#include "market/upkeep.as"         // a mobile body's slot price while the sim lags
#include "market/production.as"     // the production market: con orders, batch demand
#include "market/wanttest.as"       // apex_wanttest: the energy ladder under posed economies
