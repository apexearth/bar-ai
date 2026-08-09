#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"

// namespace Air, split across air/. THE ORDER BELOW IS LOAD-BEARING -- see
// builder.as for why.
#include "air/state.as"     // the assassination plan and everything it counts
#include "air/election.as"  // resolve the faction's air defs, elect the air player
#include "air/wing.as"      // wing strength, whether we are armed and massed
#include "air/factory.as"   // what the air plant builds next
#include "air/update.as"    // holding units back, releasing them, re-arming
