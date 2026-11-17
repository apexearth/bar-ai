// namespace Military, the territory model, split across territory/. THE ORDER
// BELOW IS LOAD-BEARING -- see manager/builder.as for why. It is the order the
// file had before the split; nothing moved between parts.
#include "territory/holdings.as"    // what we hold: defence gating, sites, border, forward fraction
#include "territory/front.as"       // the front line as a CURVE: lanes, rays, the ring
#include "territory/frontspots.as"  // where the line sits, and the build spots along it
#include "territory/enemy.as"       // what the enemy fields, and whether we are losing ground
