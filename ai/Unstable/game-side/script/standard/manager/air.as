#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"

// namespace Air, split across air/. THE ORDER BELOW IS LOAD-BEARING -- see
// builder.as for why.
#include "air/state.as"     // the assassination plan and everything it counts
#include "air/election.as"  // resolve the faction's air defs, elect the air player
#include "air/wing.as"      // wing strength, whether we are armed and massed
#include "air/wave.as"      // the roster one strike owns, and what stays home
#include "air/cover.as"     // fighters that fly with a look, a post or a strike

#include "air/update.as"    // holding units back, releasing them, re-arming
#include "air/station.as"     // spread the wing, spend obsolete fighters
#include "air/atomic.as"      // the atomic bomber: a strike by itself
