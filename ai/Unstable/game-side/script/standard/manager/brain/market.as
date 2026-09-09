//------------------------------------------------------------------------------
// THE BUILDER MARKET, prototype 1 (docs/20-brain-overhaul.md, value-paradigm
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
#include "market/worth.as"          // what a combat unit is worth: the golden metrics
#include "market/price.as"          // the two live prices, and ValueOf
#include "market/ledger.as"         // spot-value senses; the claimed-spot ledger
#include "market/census.as"         // what we own: counts, protection classes, unit events
#include "market/commit.as"         // the commitment ledger: ordered/framed/finished structures
#include "market/coverage.as"       // measured risk: what reaches an asset, what is dying
#include "market/protect_field.as"  // what we own, what guards it, where a guard could go
#include "market/want_mex.as"       // upgrade demand, walk safety, the mex Want
#include "market/want_energy.as"    // energy/convert/store Wants; the BP senses behind them
#include "market/want_plant.as"     // geothermal and factory-plant Wants
#include "market/want_tech.as"      // mex upgrade and tech-plant Wants
#include "market/sites.as"          // where a build goes: farm rows, spot clearance, eco sites
#include "market/nanopack.as"       // where an ASSIST nano stands: the packed lattice
#include "market/want_nano.as"      // the nano Want
#include "market/guards.as"         // stall sweep, guard/escort ledger, worker ledger
#include "market/army.as"           // the army model, eco role, targets, StallWatch
#include "market/stuck.as"          // the stuck-builder watchdog: no progress, no movement
#include "market/floor.as"          // the job ledger, the value ranking, the never-idle floor
// want_protect, split (order load-bearing -- see manager/builder.as):
#include "market/protect_census.as"     // the gate census, the decomposition log, tower counters
#include "market/protect_sense.as"      // edge/crowd/radar/jammer senses, closure, the class halves
#include "market/protect_target.as"     // the mex floor, DefenceValue/DefenceTarget, TargetFill
#include "market/protect_fill.as"       // DefSiteFill: every site's prevented loss, cached per def
#include "market/protect_teeth.as"      // the choke-teeth Want
#include "market/protect_senseprice.as" // radar/jam/shield/AA/targfac prices
#include "market/protect_want.as"       // ProposeProtectHalf: the defence election itself
#include "market/protect_choke.as"  // the choke: the narrowest crossing the line stands on
#include "market/protect_wall.as"   // the wall: perimeter slots ground defence fills
#include "market/want_super.as"     // the strategic Want: gantry, silo, anti-nuke, big guns
#include "market/want_assist.as"    // the assist Want
#include "market/want_reclaim.as"   // the obsolete-reclaim Want
#include "market/safety.as"        // commander self-preservation, ahead of the auction
#include "market/eta.as"            // the economy-only ETA target and its ladder
#include "market/roles.as"          // constructor roles: the split of need, who holds which
#include "market/decide.as"         // the arbiter: rank the Wants, pick one
#include "market/execute.as"        // turning a won Want into a task
#include "market/production.as"     // the production market: con orders, batch demand
