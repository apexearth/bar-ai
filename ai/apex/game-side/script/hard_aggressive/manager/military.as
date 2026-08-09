#include "../../define.as"
#include "../../unit.as"

// namespace Military, split across military/. THE ORDER BELOW IS LOAD-BEARING
// -- see builder.as for why.
#include "military/state.as"        // posture flags and the constants behind them
#include "military/roles.as"        // rush/eco roles, quotas, metal slinging
#include "military/massing.as"      // how much army to hold back and mass
#include "military/killingblow.as"  // committing everything to finish a player
#include "military/basedefence.as"  // approach threat, porcupines, line jammers
#include "military/posture.as"      // raid caution, persona, team push, corridors
#include "military/hooks.as"        // AiMakeTask, task/unit hooks, save/load
#include "military/territory.as"    // what we hold, where the border and front are
#include "military/defenceline.as"  // the front gun and AiMakeDefence
#include "military/airthreat.as"    // enemy air scaling and heavy AA caps
