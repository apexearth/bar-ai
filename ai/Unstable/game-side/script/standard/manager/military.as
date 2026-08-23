#include "../../define.as"
#include "../../unit.as"

// namespace Military, split across military/. THE ORDER BELOW IS LOAD-BEARING
// -- see builder.as for why.
#include "military/state.as"        // posture flags and the constants behind them
#include "military/roles.as"        // rush/eco roles, quotas, metal slinging
#include "military/deathledger.as"  // where our metal dies, fed back into caution
#include "military/massing.as"      // how much army to hold back and mass
#include "military/killingblow.as"  // committing everything to finish a player
#include "military/basedefence.as"  // approach threat, porcupines, line jammers
#include "military/stance.as"       // the enemy's stance; budget answer + scout demand
#include "military/posture.as"      // raid caution, persona, team push, corridors
#include "military/superguard.as"   // T3 heavies hold the defence line
#include "military/unblock.as"      // units walled in by our own buildings
#include "military/hooks.as"        // AiMakeTask, task/unit hooks, save/load
#include "military/withdraw.as"   // pull a losing squad back under our guns
#include "military/territory.as"    // what we hold, where the border and front are
#include "military/defenceline.as"  // the front gun and AiMakeDefence
#include "military/airthreat.as"    // enemy air scaling and heavy AA caps
