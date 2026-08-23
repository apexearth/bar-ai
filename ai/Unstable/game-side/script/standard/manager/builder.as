#include "../../unit.as"

// namespace Builder, split across builder/. THE ORDER BELOW IS LOAD-BEARING:
// AngelScript has no forward declaration for globals, and CScriptBuilder adds
// each section before walking its own includes, depth-first in listed order --
// so this list is exactly the order the compiler sees the declarations in. A
// global used by an earlier file than the one declaring it will not compile.
// Functions are visible module-wide regardless of file, so only globals,
// consts and types constrain where code may move.
//
// KILL PHASE (docs/20-brain-overhaul.md): every leaf spending rule is removed.
// What remains is senses, the Requests plumbing, rez-bot unit thoughts, and
// the hollowed ladder.
#include "builder/reclaim.as"     // wreck valuation, rez bots, reclaim-vs-resurrect
#include "builder/sitesafety.as"  // OnMap, front fractions, ThreatFor, veto logging
#include "builder/requests.as"    // namespace Requests: one queue for what we ask to be built
#include "builder/rules_rezzer.as"     // rez bots flee, salvage and pre-empt
#include "builder/maketask.as"    // AiMakeTask: holds -> Brain::Decide -> idle
#include "builder/events.as"      // task/unit hooks, save/load, diagnostics
