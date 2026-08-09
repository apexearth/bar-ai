#include "../../unit.as"

// namespace Builder, split across builder/. THE ORDER BELOW IS LOAD-BEARING:
// AngelScript has no forward declaration for globals, and CScriptBuilder adds
// each section before walking its own includes, depth-first in listed order --
// so this list is exactly the order the compiler sees the declarations in. A
// global used by an earlier file than the one declaring it will not compile.
// Functions are visible module-wide regardless of file, so only globals,
// consts and types constrain where code may move.
#include "builder/share.as"       // hand advanced constructors to the team
#include "builder/reclaim.as"     // wreck valuation, rez bots, reclaim-vs-resurrect
#include "builder/sitesafety.as"  // OnMap, front fractions, ThreatFor, veto logging
#include "builder/mexwork.as"     // reroute a refused mex to a colder spot
#include "builder/mexowner.as"    // which mexes are ours, and the ally-mexup veto
#include "builder/joinbuild.as"   // help the identical building already started
#include "builder/digin.as"       // fence/jammer area bookkeeping
#include "builder/converter.as"   // energy converters, rear positions
#include "builder/nano.as"        // nano turrets, unit-cap shares, surplus gantry
#include "builder/fusion.as"      // reactors and the affordability test
#include "builder/statics.as"     // AA, pulsar, shield, deterrent, nuke silo
#include "builder/mexguard.as"    // mex turrets, home energy ladder, contest towers
#include "builder/obsolete.as"    // reclaiming our own outdated buildings
#include "builder/fortify.as"     // per-constructor strike history and dig-in
#include "builder/rules_rezzer.as"     // rez bots flee, salvage and pre-empt
#include "builder/rules_hold.as"       // keep, or abandon, work already started
#include "builder/rules_commander.as"  // the commander's own safety and vetoes
#include "builder/rules_optional.as"   // the optional cluster ahead of expansion
#include "builder/rules_offer.as"      // screening DefaultMakeTask's offer
#include "builder/rules_scavenge.as"   // wrecks, and the last-resort jobs
#include "builder/maketask.as"    // AiMakeTask: the rule pipeline
#include "builder/events.as"      // task/unit hooks, save/load, diagnostics
