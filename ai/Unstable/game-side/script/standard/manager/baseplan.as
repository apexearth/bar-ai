// namespace Base, split across baseplan/. THE ORDER BELOW IS LOAD-BEARING --
// see builder.as for why.
#include "baseplan/state.as"    // the one layout every placement rule shares
#include "baseplan/grid.as"     // columns, walkways and slot geometry
#include "baseplan/axis.as"     // latching the anchor and the enemy-facing axis
#include "baseplan/reserve.as"  // band coordinates, cell reservations, growth
#include "baseplan/spot.as"     // resolve a def to a buildable cell
