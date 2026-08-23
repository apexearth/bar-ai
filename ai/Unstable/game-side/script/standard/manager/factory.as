#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "economy.as"

// namespace Factory, split across factory/. THE ORDER BELOW IS LOAD-BEARING --
// see builder.as for why. Functions may move freely between these files;
// globals, consts and types may not move earlier than their first use.
//
// KILL PHASE (docs/20-brain-overhaul.md): production rules, plant choice and
// the quota machinery are removed. What remains is senses (income, phase,
// election, enemy-tech sightings), the gQTask bookkeeping the facqueue's
// recruit abort needs, and stubs for the three engine-looked-up choice hooks.
#include "factory/state.as"        // shared flags, team-value keys
#include "factory/defs.as"         // factory def names, userData
#include "factory/maketask.as"     // AiMakeTask: the facqueue holds every line
#include "factory/hooks.as"        // task/unit hooks, save/load, T()
#include "factory/choose.as"       // engine-hook stubs: no plant choice, no switch
