#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "economy.as"

// namespace Factory, split across factory/. THE ORDER BELOW IS LOAD-BEARING --
// see builder.as for why. Functions may move freely between these files;
// globals, consts and types may not move earlier than their first use.
#include "factory/state.as"        // rush thresholds, team-value keys, shared flags
#include "factory/armypush.as"     // catch-up army production, hurt tracking
#include "factory/airsupport.as"   // radar planes, rez bots, assist bots
#include "factory/election.as"     // who is the tech lead this game
#include "factory/phase.as"        // BUILD_PHASE and the team-value publish
#include "factory/mexhold.as"      // extractor share, expansion stall, allies hurting
#include "factory/ecolead.as"      // the eco-lead role and its air plant
#include "factory/techlead.as"     // T2 mex, rush readiness, follower gating
#include "factory/defs.as"         // factory def names, userData, fodder
#include "factory/maketask.as"     // AiMakeTask: what a factory builds next
#include "factory/hooks.as"        // task/unit hooks, save/load, T(), rush logging
#include "factory/switch.as"       // AiIsSwitchTime / AiIsSwitchAllowed
#include "factory/factorydefs.as"  // plant tables, water/air maps, T3 worth
#include "factory/choose.as"       // AiGetFactoryToBuild
