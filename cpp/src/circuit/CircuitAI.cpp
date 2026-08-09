/*
 * Circuit.cpp
 *
 *  Created on: Aug 9, 2014
 *      Author: rlcevg
 */

#include "CircuitAI.h"
#include "scheduler/Scheduler.h"
#include "script/ScriptManager.h"
#include "script/InitScript.h"
#include "setup/SetupManager.h"
#include "map/MapManager.h"
#include "map/ThreatMap.h"
#include "module/BuilderManager.h"
#include "module/FactoryManager.h"
#include "module/EconomyManager.h"
#include "module/MilitaryManager.h"
#include "resource/MetalManager.h"
#include "terrain/TerrainManager.h"
#include "map/GridAnalyzer.h"
#include "map/InfluenceMap.h"   // unconditionally: the DEBUG_VIS include below is gated
#include "terrain/path/PathFinder.h"
#include "task/PlayerTask.h"
#include "unit/CircuitUnit.h"
#include "unit/enemy/EnemyUnit.h"
#include "util/GameAttribute.h"
#include "util/Utils.h"
#include "util/Profiler.h"
#ifdef DEBUG_VIS
#include "map/ThreatMap.h"
#include "resource/EnergyGrid.h"
#endif  // DEBUG_VIS

#include "spring/SpringCallback.h"
#include "spring/SpringEngine.h"
#include "spring/SpringMap.h"

#include "AISEvents.h"
#include "AISCommands.h"
#include "Log.h"
#include "Game.h"
#include "Lua.h"
#include "Pathing.h"
#include "Drawer.h"
#include "Economy.h"
#include "Resource.h"
#include "Feature.h"
#include "Unit.h"
#include "UnitDef.h"
#include "FeatureDef.h"
#include "SkirmishAI.h"
#include "WrappUnit.h"
#include "WrappTeam.h"
#include "OptionValues.h"
//#include "Info.h"
#include "Mod.h"
#include "Cheats.h"
//#include "WrappCurrentCommand.h"

#include <fstream>

namespace circuit {

using namespace springai;
using namespace terrain;

#define ACTION_UPDATE_RATE	32
#define RELEASE_RESIGN		100
#define RELEASE_SIDE		200
#define RELEASE_CONFIG		201
#define RELEASE_SCRIPT		202
#define RELEASE_COMMANDER	203
#define RELEASE_CORRUPTED	204
#ifdef CIRCUIT_PROFILING
	#define TRACY_TOPIC(txt, topic)	\
		ZoneScopedN(txt);	\
		ZoneName(profiler.GetEvent ## topic ## Name(skirmishAIId), profiler.GetEvent ## topic ## Size(skirmishAIId))
	#define TRACY_TOPIC_UNIT(txt, topic, unit)	\
		TRACY_TOPIC(txt, topic);	\
		ZoneValue(unit)
#else
	#define TRACY_TOPIC(txt, topic)
	#define TRACY_TOPIC_UNIT(txt, topic, unit)
#endif

/*
 * Почему-то всегда
 * Так незыблемы цели:
 * Разрушать города,
 * Видеть в братьях мишени...
 */
constexpr char version[]{"1.6.24"};
constexpr uint32_t VERSION_SAVE = 4;

std::unique_ptr<CGameAttribute> CCircuitAI::gameAttribute(nullptr);
unsigned int CCircuitAI::gaCounter = 0;
// HAX to fix event sequence UnitCreated=>UnitDestroyed=>UnitFinished within single frame
std::set<ICoreUnit::Id> destroyed;  // in current frame, between Update events

CCircuitAI::CCircuitAI(OOAICallback* clb)
		: eventHandler(&CCircuitAI::HandleGameEvent)
		, economy(nullptr)
		, metalRes(nullptr)
		, energyRes(nullptr)
		, allyTeam(nullptr)
		, isAllyTeamInit(false)
		, actionIterator(0)
		, isCheating(false)
		, isAllyAware(true)
		, isCommMerge(true)
		, isAllyBaseAvoid(true)
		, isInitialized(false)
		, isSavegame(false)
		, isLoadSave(false)
		, isResigned(false)
		, isSlave(false)
		// NOTE: assert(lastFrame != -1): CCircuitUnit initialized with -1
		//       and lastFrame check will misbehave until first update event.
		, lastFrame(-2)
		, skirmishAIId(clb->GetSkirmishAIId())
		, sideId(0)
		, callback(std::unique_ptr<COOAICallback>(new COOAICallback(clb)))
		, engine(nullptr)
		, cheats(std::unique_ptr<Cheats>(clb->GetCheats()))
		, log(std::unique_ptr<Log>(clb->GetLog()))
		, game(std::unique_ptr<Game>(clb->GetGame()))
		, map(nullptr)
		, lua(std::unique_ptr<Lua>(clb->GetLua()))
		, pathing(std::unique_ptr<Pathing>(clb->GetPathing()))
		, drawer(nullptr)
		, skirmishAI(std::unique_ptr<SkirmishAI>(clb->GetSkirmishAI()))
		, script(nullptr)
		, category({0})
#ifdef DEBUG_VIS
		, debugDrawer(nullptr)
#endif
{
	ownerTeamId = teamId = skirmishAI->GetTeamId();
	team = std::unique_ptr<Team>(WrappTeam::GetInstance(skirmishAIId, teamId));
	allyTeamId = game->GetMyAllyTeam();
}

CCircuitAI::~CCircuitAI()
{
	if (isInitialized) {
		Release(0);
	}
}

int CCircuitAI::HandleEvent(int topic, const void* data)
{
	return (this->*eventHandler)(topic, data);
}

void CCircuitAI::NotifyGameEnd()
{
	eventHandler = &CCircuitAI::HandleEndEvent;
}

void CCircuitAI::NotifyResign()
{
	economy = callback->GetEconomy();
	metalRes = callback->GetResourceByName(RES_NAME_METAL);
	energyRes = callback->GetResourceByName(RES_NAME_ENERGY);
	eventHandler = &CCircuitAI::HandleResignEvent;
}

void CCircuitAI::Resign(int newTeamId)
{
	std::vector<Unit*> migrants;
	auto allTeamUnits = callback->GetTeamUnits();
	for (Unit* u : allTeamUnits) {
		migrants.push_back(u);
	}
	economy->SendUnits(migrants, newTeamId);
	utils::free_clear(allTeamUnits);
	allyTeam->ForceUpdateFriendlyUnits();

	ownerTeamId = newTeamId;
	isResigned = true;
}

void CCircuitAI::MobileSlave(int newTeamId)
{
	std::vector<Unit*> migrants;
	std::vector<CCircuitUnit*> clean;
	for (auto& kv : teamUnits) {
		CCircuitUnit* unit = kv.second;
		// NOTE: springai::Economy::SendUnits won't send unfinished nanoframes,
		//       and it does cause issues when UnitFinished arrives
		//       but UnitDestroyed already cleaned its data.
		if (unit->GetCircuitDef()->IsMobile()
			&& !unit->GetCircuitDef()->IsRoleBuilder()
			&& !unit->GetUnit()->IsBeingBuilt())
		{
			migrants.push_back(unit->GetUnit());
			clean.push_back(unit);
		}
	}
	economy->SendUnits(migrants, newTeamId);
	// NOTE: How to check actually sent units? see note above why it matters.
	for (CCircuitUnit* unit : clean) {
		UnitDestroyed(unit, nullptr);
		UnregisterTeamUnit(unit);
	}
	allyTeam->ForceUpdateFriendlyUnits();

	ownerTeamId = newTeamId;
	isSlave = true;
}

int CCircuitAI::HandleGameEvent(int topic, const void* data)
{
	int ret = ERROR_UNKNOWN;

	switch (topic) {
		case EVENT_INIT: {
			TRACY_TOPIC("EVENT_INIT", Init);

			struct SInitEvent* evt = (struct SInitEvent*)data;
			try {
				ret = this->Init(evt->skirmishAIId, evt->callback);
			} catch (const CException& e) {
				Release(RELEASE_CORRUPTED);
				LOG("Exception: %s", e.what());
				NotifyGameEnd();
				ret = 0;
			} catch (const std::exception& e) {
				Release(RELEASE_CORRUPTED);
				LOG("Lib exception: %s", e.what());
				ret = ERROR_INIT;  // non-zero value deletes AI
			} catch (...) {
				Release(RELEASE_CORRUPTED);  // DestroyGameAttribute
				LOG("Unknown exception");
				ret = ERROR_INIT;  // non-zero value deletes AI
			}
			return ret;
		} break;
		case EVENT_RELEASE: {
			TRACY_TOPIC("EVENT_RELEASE", Release);

			struct SReleaseEvent* evt = (struct SReleaseEvent*)data;
			ret = this->Release(evt->reason);
		} break;
		case EVENT_UPDATE: {
			FrameMarkNamed(profiler.GetEventUpdateName(skirmishAIId));
			TRACY_TOPIC("EVENT_UPDATE", Update);

			struct SUpdateEvent* evt = (struct SUpdateEvent*)data;
			ret = this->Update(evt->frame);
		} break;
		case EVENT_MESSAGE: {
			TRACY_TOPIC("EVENT_MESSAGE", Message);

			struct SMessageEvent* evt = (struct SMessageEvent*)data;
			ret = this->Message(evt->player, evt->message);
		} break;
		case EVENT_UNIT_CREATED: {
			struct SUnitCreatedEvent* evt = (struct SUnitCreatedEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_CREATED", UnitCreated, evt->unit);

			CCircuitUnit* builder = GetTeamUnit(evt->builder);
			CCircuitUnit* unit = GetOrRegTeamUnit(evt->unit);
			ret = (unit != nullptr) ? this->UnitCreated(unit, builder) : ERROR_UNIT_CREATED;
		} break;
		case EVENT_UNIT_FINISHED: {
			struct SUnitFinishedEvent* evt = (struct SUnitFinishedEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_FINISHED", UnitFinished, evt->unit);

			if (destroyed.find(evt->unit) == destroyed.end()) {  // prevents UnitCreated=>UnitDestroyed=>UnitFinished
				// Lua might call SetUnitHealth within eventHandler.UnitCreated(this, builder);
				// and trigger UnitFinished before eoh->UnitCreated(*this, builder);
				// @see rts/Sim/Units/Unit.cpp CUnit::PostInit
				CCircuitUnit* unit = GetOrRegTeamUnit(evt->unit);
				ret = (unit != nullptr) ? this->UnitFinished(unit) : ERROR_UNIT_FINISHED;
			} else {
				ret = 0;
			}
		} break;
		case EVENT_UNIT_IDLE: {
			struct SUnitIdleEvent* evt = (struct SUnitIdleEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_IDLE", UnitIdle, evt->unit);

			CCircuitUnit* unit = GetTeamUnit(evt->unit);
			ret = (unit != nullptr) ? this->UnitIdle(unit) : ERROR_UNIT_IDLE;
		} break;
		case EVENT_UNIT_MOVE_FAILED: {
			struct SUnitMoveFailedEvent* evt = (struct SUnitMoveFailedEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_MOVE_FAILED", UnitMoveFailed, evt->unit);

			CCircuitUnit* unit = GetTeamUnit(evt->unit);
			ret = (unit != nullptr) ? this->UnitMoveFailed(unit) : ERROR_UNIT_MOVE_FAILED;
		} break;
		case EVENT_UNIT_DAMAGED: {
			struct SUnitDamagedEvent* evt = (struct SUnitDamagedEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_DAMAGED", UnitDamaged, evt->unit);

			CCircuitUnit* unit = GetTeamUnit(evt->unit);
			ret = (unit != nullptr)
					? this->UnitDamaged(unit, evt->attacker, evt->weaponDefId, AIFloat3(evt->dir_posF3))
					: ERROR_UNIT_DAMAGED;
		} break;
		case EVENT_UNIT_DESTROYED: {
			struct SUnitDestroyedEvent* evt = (struct SUnitDestroyedEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_DESTROYED", UnitDestroyed, evt->unit);

			CEnemyInfo* attacker = GetEnemyInfo(evt->attacker);
			CCircuitUnit* unit = GetTeamUnit(evt->unit);
			if (unit != nullptr) {
				ret = this->UnitDestroyed(unit, attacker);
				UnregisterTeamUnit(unit);
			} else {
				ret = ERROR_UNIT_DESTROYED;
			}
		} break;
		case EVENT_UNIT_GIVEN: {
			struct SUnitGivenEvent* evt = (struct SUnitGivenEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_GIVEN", UnitGiven, evt->unitId);

			ret = this->UnitGiven(evt->unitId, evt->oldTeamId, evt->newTeamId);
		} break;
		case EVENT_UNIT_CAPTURED: {
			struct SUnitCapturedEvent* evt = (struct SUnitCapturedEvent*)data;
			TRACY_TOPIC_UNIT("EVENT_UNIT_CAPTURED", UnitCaptured, evt->unitId);

			ret = this->UnitCaptured(evt->unitId, evt->oldTeamId, evt->newTeamId);
		} break;
		case EVENT_ENEMY_ENTER_LOS: {
			TRACY_TOPIC("EVENT_ENEMY_ENTER_LOS", EnemyEnterLOS);

			struct SEnemyEnterLOSEvent* evt = (struct SEnemyEnterLOSEvent*)data;
			CEnemyInfo* enemy;
			bool isReal;
			std::tie(enemy, isReal) = RegisterEnemyInfo(evt->enemy, true);
			ret = isReal
					? (enemy != nullptr) ? this->EnemyEnterLOS(enemy) : ERROR_ENEMY_ENTER_LOS
					: 0;
		} break;
		case EVENT_ENEMY_LEAVE_LOS: {
			TRACY_TOPIC("EVENT_ENEMY_LEAVE_LOS", EnemyLeaveLOS);

			if (isCheating) {
				ret = 0;
			} else {
				struct SEnemyLeaveLOSEvent* evt = (struct SEnemyLeaveLOSEvent*)data;
				CEnemyInfo* enemy = GetEnemyInfo(evt->enemy);
				ret = (enemy != nullptr) ? this->EnemyLeaveLOS(enemy) : ERROR_ENEMY_LEAVE_LOS;
			}
		} break;
		case EVENT_ENEMY_ENTER_RADAR: {
			TRACY_TOPIC("EVENT_ENEMY_ENTER_RADAR", EnemyEnterRadar);

			struct SEnemyEnterRadarEvent* evt = (struct SEnemyEnterRadarEvent*)data;
			CEnemyInfo* enemy;
			bool isReal;
			std::tie(enemy, isReal) = RegisterEnemyInfo(evt->enemy, false);
			ret = isReal
					? (enemy != nullptr) ? this->EnemyEnterRadar(enemy) : ERROR_ENEMY_ENTER_RADAR
					: 0;
		} break;
		case EVENT_ENEMY_LEAVE_RADAR: {
			TRACY_TOPIC("EVENT_ENEMY_LEAVE_RADAR", EnemyLeaveRadar);

			if (isCheating) {
				ret = 0;
			} else {
				struct SEnemyLeaveRadarEvent* evt = (struct SEnemyLeaveRadarEvent*)data;
				CEnemyInfo* enemy = GetEnemyInfo(evt->enemy);
				ret = (enemy != nullptr) ? this->EnemyLeaveRadar(enemy) : ERROR_ENEMY_LEAVE_RADAR;
			}
		} break;
		case EVENT_ENEMY_DAMAGED: {
			TRACY_TOPIC("EVENT_ENEMY_DAMAGED", EnemyDamaged);

			struct SEnemyDamagedEvent* evt = (struct SEnemyDamagedEvent*)data;
			CEnemyInfo* enemy = GetEnemyInfo(evt->enemy);
			ret = (enemy != nullptr) ? this->EnemyDamaged(enemy) : ERROR_ENEMY_DAMAGED;
		} break;
		case EVENT_ENEMY_DESTROYED: {
			TRACY_TOPIC("EVENT_ENEMY_DESTROYED", EnemyDestroyed);

			struct SEnemyDestroyedEvent* evt = (struct SEnemyDestroyedEvent*)data;
			CEnemyInfo* enemy = GetEnemyInfo(evt->enemy);
			if (enemy != nullptr) {
				allyTeam->DyingEnemy(enemy->GetData(), lastFrame);
				ret = 0;
			} else {
				ret = ERROR_ENEMY_DESTROYED;
			}
		} break;
		case EVENT_WEAPON_FIRED: {
			TRACY_TOPIC("EVENT_WEAPON_FIRED", WeaponFired);

			ret = 0;
		} break;
		case EVENT_PLAYER_COMMAND: {
			TRACY_TOPIC("EVENT_PLAYER_COMMAND", PlayerCommand);

			struct SPlayerCommandEvent* evt = (struct SPlayerCommandEvent*)data;
			std::vector<CCircuitUnit*> units;
			units.reserve(evt->unitIds_size);
			for (int i = 0; i < evt->unitIds_size; i++) {
				units.push_back(GetTeamUnit(evt->unitIds[i]));
			}
			ret = this->PlayerCommand(units);
		} break;
		case EVENT_SEISMIC_PING: {
			TRACY_TOPIC("EVENT_SEISMIC_PING", SeismicPing);

			ret = 0;
		} break;
		case EVENT_COMMAND_FINISHED: {
			TRACY_TOPIC("EVENT_COMMAND_FINISHED", CommandFinished);

			// FIXME: commandId always == -1, no use
//			struct SCommandFinishedEvent* evt = (struct SCommandFinishedEvent*)data;
//			CCircuitUnit* unit = GetTeamUnit(evt->unitId);
//			springai::Command* command = WrappCurrentCommand::GetInstance(skirmishAIId, evt->unitId, evt->commandId);
//			this->CommandFinished(unit, evt->commandTopicId, command);
//			delete command;
			ret = 0;
		} break;
		case EVENT_LOAD: {
			TRACY_TOPIC("EVENT_LOAD", Load);

			struct SLoadEvent* evt = (struct SLoadEvent*)data;
			std::ifstream loadFileStream;
			loadFileStream.open(evt->file, std::ios::binary);
			ret = loadFileStream.is_open() ? this->Load(loadFileStream) : ERROR_LOAD;
			loadFileStream.close();
			return ret;
		} break;
		case EVENT_SAVE: {
			TRACY_TOPIC("EVENT_SAVE", Save);

			struct SSaveEvent* evt = (struct SSaveEvent*)data;
			std::ofstream saveFileStream;
			saveFileStream.open(evt->file, std::ios::binary);
			ret = saveFileStream.is_open() ? this->Save(saveFileStream) : ERROR_SAVE;
			saveFileStream.close();
			return ret;
		} break;
		case EVENT_ENEMY_CREATED: {
			TRACY_TOPIC("EVENT_ENEMY_CREATED", EnemyCreated);

			// @see Cheats::SetEventsEnabled
			// FIXME: Can't query enemy data with globalLOS
			struct SEnemyCreatedEvent* evt = (struct SEnemyCreatedEvent*)data;
			CEnemyInfo* unit;
			bool isReal;
			std::tie(unit, isReal) = RegisterEnemyInfo(evt->enemy, true);
			ret = isReal
					? (unit != nullptr) ? this->EnemyEnterLOS(unit) : EVENT_ENEMY_CREATED
					: 0;
		} break;
		case EVENT_ENEMY_FINISHED: {
			TRACY_TOPIC("EVENT_ENEMY_FINISHED", EnemyFinished);

			// @see Cheats::SetEventsEnabled
			ret = 0;
		} break;
		case EVENT_LUA_MESSAGE: {
			TRACY_TOPIC("EVENT_LUA_MESSAGE", LuaMessage);

			struct SLuaMessageEvent* evt = (struct SLuaMessageEvent*)data;
			ret = this->LuaMessage(evt->inData);
		} break;
		default: {
			LOG("%i WARNING unrecognized event: %i", skirmishAIId, topic);
			ret = 0;
		} break;
	}

#ifndef DEBUG_LOG
	ret = 0;
#endif
	return ret;
}

int CCircuitAI::HandleEndEvent(int topic, const void* data)
{
	if (topic == EVENT_RELEASE) {
		TRACY_TOPIC("EVENT_RELEASE::END", ReleaseEnd);

		struct SReleaseEvent* evt = (struct SReleaseEvent*)data;
		return this->Release(evt->reason);
	}
	return 0;
}

int CCircuitAI::HandleResignEvent(int topic, const void* data)
{
	switch (topic) {
		case EVENT_RELEASE: {
			TRACY_TOPIC("EVENT_RELEASE::RESIGN", ReleaseResign);

			struct SReleaseEvent* evt = (struct SReleaseEvent*)data;
			return this->Release(evt->reason);
		} break;
		case EVENT_UPDATE: {
			FrameMarkNamed(profiler.GetEventUpdateName(skirmishAIId));
			TRACY_TOPIC("EVENT_UPDATE::RESIGN", UpdateResign);

			struct SUpdateEvent* evt = (struct SUpdateEvent*)data;
			if (evt->frame % (TEAM_SLOWUPDATE_RATE * INCOME_SAMPLES) == 0) {
				const int mId = metalRes->GetResourceId();
				const int eId = energyRes->GetResourceId();
				float m = game->GetTeamResourceStorage(ownerTeamId, mId) - HIDDEN_STORAGE - game->GetTeamResourceCurrent(ownerTeamId, mId);
				float e = game->GetTeamResourceStorage(ownerTeamId, eId) - HIDDEN_STORAGE - game->GetTeamResourceCurrent(ownerTeamId, eId);
				m = std::min(economy->GetCurrent(metalRes), std::max(0.f, 0.8f * m));
				e = std::min(economy->GetCurrent(energyRes), std::max(0.f, 0.2f * e));
				economy->SendResource(metalRes, m, ownerTeamId);
				economy->SendResource(energyRes, e, ownerTeamId);
			}
		} break;
		default: break;
	}
	return 0;
}

std::string CCircuitAI::ValidateMod()
{
	const int minEngineVer = 105;
	const char* engineVersion = engine->GetVersionMajor();
	int ver = atoi(engineVersion);
	if (ver < minEngineVer) {
		LOG("Engine must be %i or higher! (Current: %s)", minEngineVer, engineVersion);
		return "";
	}

	Mod* mod = callback->GetMod();
	const char* name = mod->GetShortName();
	delete mod;
	if (name == nullptr) {
		LOG("Can't get name of the game. Aborting!");  // NOTE: Sign of messed up spring/AI installation
		return "";
	}

	return name;
}

void CCircuitAI::CheatPreload()
{
	auto& enemies = callback->GetEnemyUnits();
	for (Unit* e : enemies) {
		CEnemyInfo* enemy = RegisterEnemyInfo(e);
		if (enemy != nullptr) {
			this->EnemyEnterLOS(enemy);
		}
	}
}

int CCircuitAI::Init(int skirmishAIId, const struct SSkirmishAICallback* sAICallback)
{
	LOG(version);
	this->skirmishAIId = skirmishAIId;
	callback->Init(sAICallback);
	engine = std::unique_ptr<CEngine>(new CEngine(sAICallback, skirmishAIId));
	map = std::unique_ptr<CMap>(new CMap(sAICallback, callback->GetMap()));
	drawer = std::unique_ptr<Drawer>(map->GetDrawer());
	const std::string modName = ValidateMod();
	if (modName.empty()) {
		return ERROR_INIT;
	}

#ifdef DEBUG_VIS
	debugDrawer = std::unique_ptr<CDebugDrawer>(new CDebugDrawer(this, sAICallback));
	if (debugDrawer->Init() != 0) {
		return ERROR_INIT;
	}
#endif

	CreateGameAttribute();
	scheduler = std::make_shared<CScheduler>();
	scheduler->Init(scheduler);

	InitRoles();  // core c++ implemented roles
	const std::string profile = InitOptions();  // Inits GameAttribute
	scriptManager = std::make_shared<CScriptManager>(this);
	setupManager = std::make_shared<CSetupManager>(this, &gameAttribute->GetSetupData());
	script = new CInitScript(GetScriptManager(), this);  // partially registers CSetupManager
	std::vector<std::string> cfgParts;
	CCircuitDef::SArmorInfo armor;
	if (!script->InitConfig(profile, cfgParts, armor)) {
		Release(RELEASE_SCRIPT);
		return ERROR_INIT;
	}

	if (!InitSide()) {
		Release(RELEASE_SIDE);
		return ERROR_INIT;
	}

	InitWeaponDefs();
	float decloakRadius;
	InitUnitDefs(armor, decloakRadius);  // Inits TerrainData

	setupManager->DisabledUnits();
	if (!setupManager->OpenConfig(profile, cfgParts)) {
		Release(RELEASE_CONFIG);
		return ERROR_INIT;
	}
	setupManager->ReadConfig();
//	if (!setupManager->PickCommander()) {
//		Release(RELEASE_COMMANDER);
//		return ERROR_INIT;
//	}

	// Repair allyTeamId before GetAllyTeam() indexes with it. The constructor
	// took it from game->GetMyAllyTeam(), which returns 0 for every instance,
	// so every AI believed it was in ally team 0 -- GetTeamIds() then answered
	// with ally 0's roster for everyone, and any rule keyed on team size or
	// team membership was reading the wrong team's data.
	{
		const int realAlly = setupManager->FindAllyTeamOf(teamId);
		if (realAlly >= 0) {
			allyTeamId = realAlly;
		}
	}
	allyTeam = setupManager->GetAllyTeam();
	// TODO: isAllyTeamInit is a workaround: when config has issues and exception is thrown between
	// allyTeam assignment and allyTeam->Init() call then allyTeam->Release() is invoked.
	// Assignment and Init() should be simultaneous, but it has dependency on data from
	// terrainManager and economyManager and vice versa. Instead terrainManager and economyManager could
	// receive temporary structs with required info (seems only team size required).
	isAllyTeamInit = false;
	isAllyAware &= allyTeam->GetSize() > 1;

	terrainManager = std::make_shared<CTerrainManager>(this, &gameAttribute->GetTerrainData());
	terrainManager->InitAnalyzer();
	economyManager = std::make_shared<CEconomyManager>(this);
	// NOTE: ReadConfig() on bad json throws exception and leaks allocations in between.
	// Hence user input processing must never be inside class constructor.
	economyManager->InitHandlers();
	economy = callback->GetEconomy();

	isAllyTeamInit = true;
	allyTeam->Init(this, decloakRadius);
	mapManager = allyTeam->GetMapManager();
	enemyManager = allyTeam->GetEnemyManager();
	metalManager = allyTeam->GetMetalManager();
	energyManager = allyTeam->GetEnergyManager();
	pathfinder = allyTeam->GetPathfinder();

	// FIXME: CanChooseStartPos = false, finish start factory and position selection
//	if (setupManager->HasStartBoxes() && setupManager->CanChooseStartPos()) {
//		const CSetupManager::StartPosType spt = metalManager->HasMetalSpots() ?
//												CSetupManager::StartPosType::METAL_SPOT :
//												CSetupManager::StartPosType::RANDOM;
//		setupManager->PickStartPos(spt);
//	}

	factoryManager = std::make_shared<CFactoryManager>(this);
	factoryManager->InitHandlers();
	builderManager = std::make_shared<CBuilderManager>(this);
	builderManager->InitHandlers();
	militaryManager = std::make_shared<CMilitaryManager>(this);
	militaryManager->InitHandlers();

	// TODO: Remove EconomyManager from module (move abilities to BuilderManager).
	modules.push_back(militaryManager);
	modules.push_back(builderManager);
	modules.push_back(factoryManager);  // NOTE: Contains special last-module unit handlers.
	modules.push_back(economyManager);  // NOTE: Uses unit's manager != nullptr, thus must be last.

	terrainManager->Init();
	economyManager->InitEconomyScores();

	script->RegisterMgr();
	if (!script->Init()) {
		Release(RELEASE_SCRIPT);
		return ERROR_INIT;
	}

	// Delay threat ranges initialization from allyTeam->Init()
	// so cdef.SetRange() in AiMain() could make an effect.
	allyTeam->InitThreatRanges(this);

	for (auto& module : modules) {
		if (!module->InitScript()) {
			Release(RELEASE_SCRIPT);
			return ERROR_INIT;
		}
	}

	if (isCheating) {
		cheats->SetEnabled(true);
		cheats->SetEventsEnabled(true);
		scheduler->RunJobAt(CScheduler::GameJob(&CCircuitAI::CheatPreload, this), skirmishAIId + 1);
	}

	if (isCommMerge) {
		if ((GetEnemyTeamSize() < allyTeam->GetAliveSize() / 2.f)/* || (allyTeam->GetAliveSize() > 4)*/) {
			mergeTask = CScheduler::GameJob([this] {
#if 1
				if (allyTeam->GetLeaderId() == teamId) {
					scheduler->RemoveJob(mergeTask);
				} else if (factoryManager->GetFactoryCount() > 0) {
					MobileSlave(allyTeam->GetLeaderId());
					scheduler->RemoveJob(mergeTask);
				}
#else
				// Complete resign by area
				if (allyTeam->GetLeaderId() == teamId) {
					scheduler->RemoveJob(mergeTask);
				} else if (factoryManager->GetFactoryCount() > 0) {
					CCircuitUnit* commander = setupManager->GetCommander();
					if (commander == nullptr) {
						commander = teamUnits.begin()->second;
					}
					int ownerId = allyTeam->GetAreaTeam(commander->GetArea()).teamId;
					if ((ownerId != teamId) && (ownerId >= 0)) {
						Resign(ownerId);
					}
				}
#endif
			});
			scheduler->RunJobEvery(mergeTask, FRAMES_PER_SEC, FRAMES_PER_SEC * 10);
#if 0
		} else if (allyTeam->GetAliveSize() > 2) {
			// FIXME: Follower AI shares all its mobile non-builder-role units to Leader AI.
			// Results in constantly building scouts or anti-air due to highest importance in response
			// and having them always 0 due to sharing.
			mergeTask = CScheduler::GameJob([this] {
				if (allyTeam->GetLeaderId() == teamId) {
					scheduler->RemoveJob(mergeTask);
				} else if (factoryManager->GetNoT1FacCount() > 0) {
					MobileSlave(allyTeam->GetLeaderId());
					scheduler->RemoveJob(mergeTask);
				}
			});
			scheduler->RunJobEvery(mergeTask, FRAMES_PER_SEC, FRAMES_PER_SEC * 10);
#endif
		}
	}

	scheduler->ProcessInit();  // Init modules: allows to manipulate units on gadget:Initialize
	setupManager->Welcome();

	setupManager->CloseConfig();
	isInitialized = true;

	return 0;  // signaling: OK
}

int CCircuitAI::Release(int reason)
{
	delete economy, delete metalRes, delete energyRes;
	economy = nullptr;
	metalRes = energyRes = nullptr;

	if (!isInitialized && (reason < RELEASE_SIDE)) {
		return 0;
	}

	scheduler->ProcessRelease();
	scheduler = nullptr;

	delete script;  // NOTE: Threaded scripts, hence destroy contexts after scheduler
	script = nullptr;

	if (reason == RELEASE_RESIGN) {
		factoryManager->Release();
		builderManager->Release();
		militaryManager->Release();
	}

	if (reason == 1) {  // @see SReleaseEvent
		gameAttribute->SetGameEnd(true);
	}
	if (terrainManager != nullptr) {
		terrainManager->OnAreaUsersUpdated();
	}

	weaponDefs.clear();
	defsById.clear();
	defsByName.clear();

	modules.clear();
	scriptManager = nullptr;
	militaryManager = nullptr;
	economyManager = nullptr;
	factoryManager = nullptr;
	builderManager = nullptr;
	terrainManager = nullptr;
	metalManager = nullptr;
	energyManager = nullptr;
	pathfinder = nullptr;
	setupManager = nullptr;
	enemyManager = nullptr;
	mapManager = nullptr;

	for (CCircuitUnit* unit : actionUnits) {
		if (unit->IsDead()) {  // instance is not in teamUnits
			delete unit;
		}
	}
	actionUnits.clear();
	for (auto& kv : teamUnits) {
		delete kv.second;
	}
	teamUnits.clear();
	garbage.clear();
	for (auto& kv : enemyInfos) {
		delete kv.second;
	}
	enemyInfos.clear();
	if (allyTeam != nullptr && isAllyTeamInit) {
		allyTeam->Release();
		allyTeam = nullptr;
//		isAllyTeamInit = false;
	}

	DestroyGameAttribute();

#ifdef DEBUG_VIS
	debugDrawer = nullptr;
#endif

	isInitialized = false;

	return 0;  // signaling: OK
}

int CCircuitAI::Update(int frame)
{
	destroyed.clear();
	lastFrame = frame;
	if (isResigned) {
		Release(RELEASE_RESIGN);
		NotifyResign();
		return 0;
	}

	if (!garbage.empty()) {
		CCircuitUnit* unit = *garbage.begin();
		UnitDestroyed(unit, nullptr);
		UnregisterTeamUnit(unit);
		garbage.erase(unit);  // NOTE: UnregisterTeamUnit may erase unit
	}

	for (const CEnemyUnit* data : allyTeam->GetDyingEnemies()) {
		CEnemyInfo* enemy = GetEnemyInfo(data->GetId());
		if (enemy != nullptr) {  // EnemyDestroyed right after UpdateEnemyDatas but before this Update
			EnemyDestroyed(enemy);
			UnregisterEnemyInfo(enemy);
		}
	}

	allyTeam->Update(this);

	scheduler->ProcessJobs(frame);
	if (frame % TEAM_SLOWUPDATE_RATE == skirmishAIId) {
		// NOTE: Probably should be last in ProcessJobs queue, after all income updates if it was in the same frame.
		//       Hence it is not:
		// scheduler->RunJobEvery(CScheduler::GameJob(&CInitScript::Update, script), TEAM_SLOWUPDATE_RATE, skirmishAIId);
		script->Update();
	}
	UpdateActions();

#ifdef DEBUG_VIS
	if (frame % FRAMES_PER_SEC == 0) {
		allyTeam->GetEnergyGrid()->UpdateVis();
		debugDrawer->Refresh();
	}
#endif

	return 0;  // signaling: OK
}

int CCircuitAI::Message(int playerId, const char* message)
{
#ifdef DEBUG_VIS
	const char cmdBreak[]   = "~break";
	const char cmdReload[]  = "~reload";

	const char cmdPos[]     = "~стройсь\0";
	const char cmdSelfD[]   = "~Згинь, нечистая сила!\0";

	const char cmdBlock[]   = "~block";
	const char cmdWBlock[]  = "~wbdraw";  // widget block draw

	const char cmdArea[]    = "~area";
	const char cmdPath[]    = "~path";
	const char cmdKnn[]     = "~knn";
	const char cmdLog[]     = "~log";
	const char cmdBTask[]   = "~btask";
	const char cmdChoke[]   = "~choke";
	const char cmdMetal[]   = "~metal";

	const char cmdThreat[]  = "~threat";
	const char cmdWTDraw[]  = "~wtdraw";  // widget threat draw
	const char cmdWTDiv[]   = "~wtdiv";
	const char cmdWTPrint[] = "~wtprint";

	const char cmdInfl[]    = "~infl";
	const char cmdWIDraw[]  = "~widraw";  // widget influence draw
	const char cmdWIDiv[]   = "~widiv";
	const char cmdWIPrint[] = "~wiprint";

	const char cmdGrid[]    = "~grid";
	const char cmdNode[]    = "~node";
	const char cmdLink[]    = "~link";

	const char cmdName[]    = "~name";
	const char cmdEnd[]     = "~end";

	if (message[0] != '~') {
		return 0;
	}

	auto selfD = [this]() {
		auto units = callback->GetTeamUnits();
		for (Unit* u : units) {
			u->SelfDestruct();
			delete u;
		}
	};

	size_t msgLength = strlen(message);

	if (strncmp(message, cmdBreak, 6) == 0) {
		__asm__("int3");
	}
	else if (strncmp(message, cmdReload, 7) == 0) {
		game->SetPause(true, "reload");
		scriptManager->Reload();
	}

	else if ((msgLength == strlen(cmdPos)) && (strcmp(message, cmdPos) == 0)) {
		setupManager->PickStartPos(CSetupManager::StartPosType::RANDOM);
	}
	else if ((msgLength == strlen(cmdSelfD)) && (strcmp(message, cmdSelfD) == 0)) {
		selfD();
	}

	else if (strncmp(message, cmdBlock, 6) == 0) {
		terrainManager->ToggleVis();
	}
	else if (strncmp(message, cmdWBlock, 7) == 0) {
		if (teamId == atoi((const char*)&message[8])) {
			terrainManager->ToggleWidgetDraw();
		}
	}

	else if (strncmp(message, cmdArea, 5) == 0) {
		gameAttribute->GetTerrainData().ToggleVis(lastFrame);
	}
	else if (strncmp(message, cmdPath, 5) == 0) {
		pathfinder->ToggleVis(this);
	}
	else if (strncmp(message, cmdKnn, 4) == 0) {
		const AIFloat3 dbgPos = map->GetMousePos();
		int index = metalManager->FindNearestCluster(dbgPos);
		drawer->AddPoint(metalManager->GetClusters()[index].position, "knn");
	}
	else if (strncmp(message, cmdLog, 4) == 0) {
		auto selection = callback->GetSelectedUnits();
		for (Unit* u : selection) {
			CCircuitUnit* unit = GetTeamUnit(u->GetUnitId());
			if (unit != nullptr) {
				unit->Log();
			}
		}
		utils::free_clear(selection);
	}
	else if (strncmp(message, cmdBTask, 6) == 0) {
		if (teamId == atoi((const char*)&message[7])) {
			builderManager->Log();
		}
	}
	else if (strncmp(message, cmdChoke, 6) == 0) {
		gameAttribute->GetTerrainData().ToggleTAVis(lastFrame);
	}
	else if (strncmp(message, cmdMetal, 6) == 0) {
		gameAttribute->GetMetalData().ToggleTAVis(lastFrame);
	}

	else if (strncmp(message, cmdThreat, 7) == 0) {
		mapManager->GetThreatMap()->ToggleSDLVis();
	}
	else if (strncmp(message, cmdWTDraw, 7) == 0) {
		if (teamId == atoi((const char*)&message[8])) {
			mapManager->GetThreatMap()->ToggleWidgetDraw();
		}
	}
	else if (strncmp(message, cmdWTDiv, 6) == 0) {
		std::string s(message);
		auto start = s.rfind(" ");
		std::string layer = (start != std::string::npos) ? s.substr(start + 1) : "";
		mapManager->GetThreatMap()->SetMaxThreat(atof((const char*)&message[7]), layer);
	}
	else if (strncmp(message, cmdWTPrint, 8) == 0) {
		if (teamId == atoi((const char*)&message[9])) {
			mapManager->GetThreatMap()->ToggleWidgetPrint();
		}
	}

	else if (strncmp(message, cmdInfl, 5) == 0) {
		mapManager->GetInflMap()->ToggleSDLVis();
	}
	else if (strncmp(message, cmdWIDraw, 7) == 0) {
		if (teamId == atoi((const char*)&message[8])) {
			mapManager->GetInflMap()->ToggleWidgetDraw();
		}
	}
	else if (strncmp(message, cmdWIDiv, 6) == 0) {
		mapManager->GetInflMap()->SetMaxThreat(atof((const char*)&message[7]));
	}
	else if (strncmp(message, cmdWIPrint, 8) == 0) {
		if (teamId == atoi((const char*)&message[9])) {
			mapManager->GetInflMap()->ToggleWidgetPrint();
		}
	}

	else if (strncmp(message, cmdGrid, 5) == 0) {
		auto selection = callback->GetSelectedUnits();
		if (!selection.empty()) {
			if (selection[0]->GetAllyTeam() == allyTeamId) {
				allyTeam->GetEnergyGrid()->ToggleVis();
			}
			utils::free_clear(selection);
		} else if (allyTeam->GetEnergyGrid()->IsVis()) {
			allyTeam->GetEnergyGrid()->ToggleVis();
		}
	}
	else if (strncmp(message, cmdNode, 5) == 0) {
		const AIFloat3 dbgPos = map->GetMousePos();
		economyManager->GetEnergyGrid()->DrawNodePylons(dbgPos);
	}
	else if (strncmp(message, cmdLink, 5) == 0) {
		const AIFloat3 dbgPos = map->GetMousePos();
		economyManager->GetEnergyGrid()->DrawLinkPylons(dbgPos);
	}

	else if (strncmp(message, cmdName, 5) == 0) {
		pathfinder->SetDbgDef(GetCircuitDef(message[6]));
		pathfinder->SetDbgPos(map->GetMousePos());
		const AIFloat3& dbgPos = pathfinder->GetDbgPos();
		LOG("%f, %f, %f, %i", dbgPos.x, dbgPos.y, dbgPos.z, pathfinder->GetDbgDef());
	}
	else if (strncmp(message, cmdEnd, 4) == 0) {
		pathfinder->SetDbgType(atoi((const char*)&message[5]));
		AIFloat3 endPos = map->GetMousePos();
		std::shared_ptr<IPathQuery> query = pathfinder->CreateDbgPathQuery(GetThreatMap(),
				endPos, pathfinder->GetSquareSize());
		if (query != nullptr) {
			pathfinder->SetDbgQuery(query);
			pathfinder->RunQuery(scheduler.get(), query);
		}
		LOG("%f, %f, %f, %i", endPos.x, endPos.y, endPos.z, pathfinder->GetDbgType());
	}
#endif

	return 0;  // signaling: OK
}

int CCircuitAI::UnitCreated(CCircuitUnit* unit, CCircuitUnit* builder)
{
	for (auto& module : modules) {
		module->UnitCreated(unit, builder);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::UnitFinished(CCircuitUnit* unit)
{
	if (unit->GetUnit()->IsBeingBuilt() || (unit->GetTask() == nullptr)) {
		// NOTE: unit->GetTask()=nullptr in case of UnitCreated=>UnitDestroyed=>UnitFinished sequence
		// and unit->GetUnit()->IsBeingBuilt() when spawned full health by gadget UnitFinished=>UnitCreated
		return 0;
	}
	unit->SetIsFinished();  // TODO: Investigate rezz, plop and capture

	// NOTE: "response" structure and limits are per AI
	if (isSlave
		&& unit->GetCircuitDef()->IsMobile()
		&& !unit->GetCircuitDef()->IsRoleBuilder())
	{
		economy->SendUnits({unit->GetUnit()}, allyTeam->GetLeaderId());
		if (unit->GetTask() != nullptr) {  // NOTE: Won't send nanoframes but UnregisterTeamUnit may be already called.
			UnitDestroyed(unit, nullptr);
		}
		// BAR on SendUnits invokes EVENT_UNIT_CAPTURED, no need for:
		UnregisterTeamUnit(unit);
		return 0;
	}

	// FIXME: Random-Side workaround
	// Faction data used before UnitFinished reaches EconomyManager where it sets side if commander is null.
	// Option: remove faction specific lists and make common by economy type list with all water/underwater/factions units.
	// Cons: iterating over full list.
	if (unit->GetCircuitDef()->IsRoleComm() && (setupManager->GetCommander() == nullptr)) {
		setupManager->SetCommander(unit);
	}

	unit->GetCircuitDef()->AdjustSinceFrame(lastFrame);
	TRY_UNIT(this, unit,
		unit->CmdFireAtRadar(true);
		unit->GetUnit()->SetAutoRepairLevel(0);
		unit->GetUnit()->SetOn(unit->GetCircuitDef()->IsOn());
		if (unit->GetCircuitDef()->IsAbleToCloak()
			&& unit->GetCircuitDef()->GetCloakCost() < economyManager->GetAvgEnergyIncome() * 0.1f)
		{
			unit->CmdCloak(true);
		}
	)

	for (auto& module : modules) {
		module->UnitFinished(unit);
	}

	if (!unit->IsDead()  // AiUnitAdded script can give away unit by now
		&& (unit->GetTask()->GetType() != IUnitTask::Type::NIL)
		&& (unit->GetUnit()->GetRulesParamFloat("resurrected", 0.f) != 0.f))
	{
		unit->GetTask()->GetManager()->Resurrected(unit);
	}

	// FIXME: Experimental. Remove?
	if (!IsLoadSave()) {
		script->UnitFinished(unit);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::UnitIdle(CCircuitUnit* unit)
{
	if (unit->IsStuck()) {
		return 0;  // signaling: OK
	}

	for (auto& module : modules) {
		module->UnitIdle(unit);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::UnitMoveFailed(CCircuitUnit* unit)
{
	if (unit->IsStuck()) {
		return 0;  // signaling: OK
	}

	if (unit->IsMoveFailed(lastFrame)) {
		TRY_UNIT(this, unit,
			unit->CmdStop();
			unit->CmdSetMoveState(CCircuitDef::MoveType::ROAM);
		)
//		Garbage(unit, "stuck");
		GetBuilderManager()->Enqueue(TaskB::Reclaim(IBuilderTask::Priority::NORMAL, unit));
	} else if (unit->GetTask()->GetType() != IUnitTask::Type::NIL) {
		unit->GetTask()->OnUnitMoveFailed(unit);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::UnitDamaged(CCircuitUnit* unit, ICoreUnit::Id attackerId, int weaponId, AIFloat3 dir)
{
	unit->SetDamagedFrame(lastFrame);
	CEnemyInfo* attacker = GetEnemyInfo(attackerId);

	if (IsValidWeaponDefId(weaponId)) {
		if (attacker != nullptr) {
			CheckDecoy(attacker, weaponId);
		} else if ((dir != ZeroVector) && (GetFriendlyUnit(attackerId) == nullptr)) {
			CreateFakeEnemy(weaponId, unit->GetPos(lastFrame), dir);  // currently only for threatmap
		}
	}

	for (auto& module : modules) {
		module->UnitDamaged(unit, attacker);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::UnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	destroyed.insert(unit->GetId());
	NoteTrade(false, unit->GetCircuitDef());
	// Feeds the attack hotspot: where we are losing things is the best evidence
	// available of where the enemy actually is.
	if (unit->GetCircuitDef() != nullptr) {
		NoteLossAt(unit->GetPos(GetLastFrame()), unit->GetCircuitDef()->GetCostM());
	}
	for (auto& module : modules) {
		module->UnitDestroyed(unit, attacker);
	}

	// FIXME: Experimental. Remove?
	script->UnitDestroyed(unit);

	return 0;  // signaling: OK
}

int CCircuitAI::UnitGiven(ICoreUnit::Id unitId, int oldTeamId, int newTeamId)
{
	CEnemyInfo* enemy = GetEnemyInfo(unitId);
	if (enemy != nullptr) {
		allyTeam->DyingEnemy(enemy->GetData(), lastFrame);
	}

	// it might not have been given to us! Could have been given to another team
	if (teamId != newTeamId) {
		return 0;  // signaling: OK
	}

	CCircuitUnit* unit = GetOrRegTeamUnit(unitId);
	if (unit == nullptr) {
		return ERROR_UNIT_GIVEN;
	}

	TRY_UNIT(this, unit,
		unit->CmdStop();
		unit->CmdFireAtRadar(true);
		unit->GetUnit()->SetAutoRepairLevel(0);
		unit->GetUnit()->SetOn(true);
		if (unit->GetCircuitDef()->IsAbleToCloak()
			&& unit->GetCircuitDef()->GetCloakCost() < economyManager->GetAvgEnergyIncome() * 0.1f)
		{
			unit->CmdCloak(true);
		}
	)
	for (auto& module : modules) {
		module->UnitGiven(unit, oldTeamId, newTeamId);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::UnitCaptured(ICoreUnit::Id unitId, int oldTeamId, int newTeamId)
{
	// it might not have been captured from us! Could have been captured from another team
	if (teamId != oldTeamId) {
		return 0;  // signaling: OK
	}

	CCircuitUnit* unit = GetTeamUnit(unitId);
	if (unit == nullptr) {
		return ERROR_UNIT_CAPTURED;
	}

	for (auto& module : modules) {
		module->UnitCaptured(unit, oldTeamId, newTeamId);
	}

	UnregisterTeamUnit(unit);

	return 0;  // signaling: OK
}

int CCircuitAI::EnemyEnterLOS(CEnemyInfo* enemy)
{
	bool isSuddenThreat = mapManager->IsSuddenThreat(enemy->GetData());

	allyTeam->EnemyEnterLOS(enemy->GetData(), this);

	if (!isSuddenThreat) {
		return 0;  // signaling: OK
	}
	// Force unit's reaction
	auto& friendlies = callback->GetFriendlyUnitIdsIn(enemy->GetPos(), 1000.0f);
	if (friendlies.empty()) {
		return 0;  // signaling: OK
	}
	for (int fId : friendlies) {
		CCircuitUnit* unit = GetTeamUnit(fId);
		if ((unit != nullptr) && (unit->GetTask()->GetType() != IUnitTask::Type::NIL)) {
			unit->ForceUpdate(lastFrame + THREAT_UPDATE_RATE);
		}
	}

	militaryManager->AddPointOfInterest(enemy);

	return 0;  // signaling: OK
}

int CCircuitAI::EnemyLeaveLOS(CEnemyInfo* enemy)
{
	allyTeam->EnemyLeaveLOS(enemy->GetData(), this);

	return 0;  // signaling: OK
}

int CCircuitAI::EnemyEnterRadar(CEnemyInfo* enemy)
{
	allyTeam->EnemyEnterRadar(enemy->GetData(), this);

	return 0;  // signaling: OK
}

int CCircuitAI::EnemyLeaveRadar(CEnemyInfo* enemy)
{
	allyTeam->EnemyLeaveRadar(enemy->GetData(), this);

	return 0;  // signaling: OK
}

int CCircuitAI::EnemyDamaged(CEnemyInfo* enemy)
{
	// NOTE: Whole threat map updates in a fraction of a second, through polling
	return 0;  // signaling: OK
}

int CCircuitAI::EnemyDestroyed(CEnemyInfo* enemy)
{
	NoteTrade(true, enemy->GetCircuitDef());
	allyTeam->EnemyDestroyed(enemy->GetData(), this);

	militaryManager->DelPointOfInterest(enemy);

	return 0;  // signaling: OK
}

int CCircuitAI::PlayerCommand(const std::vector<CCircuitUnit*>& units)
{
	for (CCircuitUnit* unit : units) {
		if ((unit != nullptr)
			&& (unit->GetTask()->GetType() != IUnitTask::Type::NIL)  // ignore orders to nanoframes
			&& (unit->GetTask()->GetType() != IUnitTask::Type::PLAYER))
		{
			unit->GetTask()->GetManager()->AssignPlayerTask(unit);
		}
	}

	return 0;  // signaling: OK
}

//int CCircuitAI::CommandFinished(CCircuitUnit* unit, int commandTopicId, springai::Command* cmd)
//{
//	for (auto& module : modules) {
//		module->CommandFinished(unit, commandTopicId);
//	}
//
//	return 0;  // signaling: OK
//}

int CCircuitAI::Load(std::istream& is)
{
	isSavegame = true;
	isLoadSave = true;

//	if (mergeTask != nullptr) {
//		scheduler->RemoveJob(mergeTask);
//	}

	uint32_t versionLoad;
	utils::binary_read(is, versionLoad);
	if (versionLoad != VERSION_SAVE) {
		return ERROR_LOAD;
	}
	utils::binary_read(is, lastFrame);
	utils::binary_read(is, sideId);

	auto units = callback->GetTeamUnits();
	for (Unit* u : units) {
		ICoreUnit::Id unitId = u->GetUnitId();
		if (GetTeamUnit(unitId) != nullptr) {
			delete u;
			continue;
		}
		CCircuitUnit* unit = RegisterTeamUnit(unitId, u);
		UnitCreated(unit, nullptr);  // NOTE: NIL task assigned only on UnitCreated
		if (!u->IsBeingBuilt()) {
			UnitFinished(unit);
		}
	}
	for (auto& kv : teamUnits) {
		CCircuitUnit* unit = kv.second;
		if (unit->GetUnit()->GetRulesParamFloat("disableAiControl", 0) > 0.f) {
			UnitControl(unit, false);
		}
	}

	auto& enemies = callback->GetEnemyUnits();
	for (Unit* e : enemies) {
		if (GetEnemyInfo(e->GetUnitId()) != nullptr) {
			delete e;
			continue;
		}
		CEnemyInfo* enemy = RegisterEnemyInfo(e);
		if (enemy != nullptr) {
			EnemyEnterRadar(enemy);
			if (enemy->GetCircuitDef() != nullptr) {
				EnemyEnterLOS(enemy);
			}
		}
	}
#ifdef DEBUG_SAVELOAD
	LOG("%s | versionLoad=%i | lastFrame=%i | sideId=%i | defs=%i | units=%i | enemies=%i", __PRETTY_FUNCTION__,
			versionLoad, lastFrame, sideId, GetCircuitDefs().size(), teamUnits.size(), enemyInfos.size());
#endif

	for (auto& module : modules) {
		is >> *module;
	}
	for (auto& module : modules) {
		module->LoadScript(is);
	}

	isLoadSave = false;
	return 0;  // signaling: OK
}

int CCircuitAI::Save(std::ostream& os)
{
	utils::binary_write(os, VERSION_SAVE);
	utils::binary_write(os, lastFrame);
	utils::binary_write(os, sideId);
#ifdef DEBUG_SAVELOAD
	LOG("%s | VERSION_SAVE=%i | lastFrame=%i | sideId=%i | defs=%i", __PRETTY_FUNCTION__, VERSION_SAVE, lastFrame, sideId, GetCircuitDefs().size());
#endif

	for (auto& module : modules) {
		os << *module;
	}
	for (auto& module : modules) {
		module->SaveScript(os);
	}

	return 0;  // signaling: OK
}

int CCircuitAI::LuaMessage(const char* inData)
{
	script->LuaMessage(inData);
	return 0;  // signaling: OK
}

bool CCircuitAI::InitSide()
{
	sideName = game->GetTeamSide(teamId);
	if (!gameAttribute->GetSideMasker().HasType(sideName)) {
		sideName = gameAttribute->GetSideMasker().GetName(0);
		if (sideName.empty()) {
			return false;
		}
	}
	sideId = gameAttribute->GetSideMasker().GetType(sideName);
	return true;
}

void CCircuitAI::SetSide(const std::string& name)
{
	const CMaskHandler::MaskName& masks = gameAttribute->GetSideMasker().GetMasks();
	auto it = masks.find(name);
	if (it != masks.end()) {
		sideName = name;
		sideId = it->second.type;
	}
}

CCircuitUnit* CCircuitAI::GetOrRegTeamUnit(ICoreUnit::Id unitId)
{
	CCircuitUnit* unit = GetTeamUnit(unitId);
	if (unit != nullptr) {
		return unit;
	}

	return RegisterTeamUnit(unitId);
}

CCircuitUnit* CCircuitAI::RegisterTeamUnit(ICoreUnit::Id unitId)
{
	Unit* u = WrappUnit::GetInstance(skirmishAIId, unitId);
	if (u == nullptr) {
		return nullptr;
	}

	return RegisterTeamUnit(unitId, u);
}

CCircuitUnit* CCircuitAI::RegisterTeamUnit(ICoreUnit::Id unitId, Unit* u)
{
	CCircuitDef* cdef = GetCircuitDef(GetCallback()->Unit_GetDefId(unitId));
	CCircuitUnit* unit = new CCircuitUnit(this, unitId, u, cdef);

	SArea* area;
	bool isValid;
	std::tie(area, isValid) = terrainManager->GetCurrentMapArea(cdef, unit->GetPos(lastFrame));
	unit->SetArea(area);

	teamUnits[unitId] = unit;
	cdef->Inc();

	// FIXME: Sometimes area where factory is placed is not suitable for its units.
	//        There Garbage() can cause infinite start-cancel loop.
//	if (!isValid) {
//		Garbage(unit, "useless");
//	}
	return unit;
}

void CCircuitAI::UnregisterTeamUnit(CCircuitUnit* unit)
{
	teamUnits.erase(unit->GetId());
	unit->GetCircuitDef()->Dec();

	/*(unit->GetTask() == nullptr) ? DeleteTeamUnit(unit) : */unit->SetIsDead();
}

void CCircuitAI::DeleteTeamUnit(CCircuitUnit* unit)
{
	garbage.erase(unit);
	delete unit;
}

float CCircuitAI::GetTeamMetalFill(int otherTeamId) const
{
	if ((otherTeamId < 0) || (game == nullptr) || (metalRes == nullptr)) {
		return 0.f;
	}
	const int mId = metalRes->GetResourceId();
	const float storage = game->GetTeamResourceStorage(otherTeamId, mId);
	// The engine does not report another team's storage to us -- it comes back
	// as 0, and the old code read that as "full" and withheld every transfer,
	// silently disabling slinging entirely. Treat unknown as "needs it": the
	// caller is only ever sending surplus it has already decided to give away.
	if (storage <= 0.f) {
		return 0.f;
	}
	return game->GetTeamResourceCurrent(otherTeamId, mId) / storage;
}

// Metal income of any team, read from a game rules param published by the
// dev_team_income gadget.
//
// The obvious API does not work. Game_getTeamResourceIncome and every sibling
// route through aiGetTeamResource() in SSkirmishAICallbackImpl.cpp, which gates
// on AI_TEAM_IDS[skirmishAIId]. That array is declared
//     static std::array<int, MAX_AIS> AI_TEAM_IDS = {{-1}};
// and is never assigned anywhere in the engine, so element 0 holds -1 and the
// rest hold 0; the alliance check then fails and the call returns -1.0.
// Confirmed live: an AI asking for its OWN team's income got -1.0 back, for all
// eight allied teams, every tick.
//
// Game_getRulesParamFloat has no such gate, so synced Lua publishes the numbers
// and we read them here. Returns -1 when the gadget is absent, which callers
// must treat as "unknown" rather than "poor".
// Prefer the ally instance's own figure. Every AI the host adds shares this
// process, so a teammate's CEconomyManager already holds the exact smoothed
// income -- no gadget, no round trip, and it works in a hosted multiplayer game
// where synced Lua cannot be shipped. The rules param stays as a fallback so a
// local run with dev_team_income.lua still answers for non-AI teams.
float CCircuitAI::GetTeamMetalIncome(int otherTeamId) const
{
	if (otherTeamId < 0) {
		return -1.f;
	}
	for (CCircuitAI* peer : GetGameAttribute()->GetCircuits()) {
		if ((peer != nullptr) && (peer->GetTeamId() == otherTeamId)
			&& (peer->GetEconomyManager() != nullptr))
		{
			return peer->GetEconomyManager()->GetAvgMetalIncome();
		}
	}
	if (game == nullptr) {
		return -1.f;
	}
	const std::string key = "ai_minc_" + utils::int_to_string(otherTeamId);
	return game->GetRulesParamFloat(key.c_str(), -1.f);
}

// Highest build progress among our own units of `def`, or -1 if we hold none.
//
// teamUnits carries nanoframes as well as finished units -- other call sites
// here filter them out with IsBeingBuilt(), which is what makes this usable:
// "has committed to an advanced plant" is the question the tech-lead election
// actually asks, and a plant that is 5% built already answers it yes.
float CCircuitAI::GetDefBuildProgress(CCircuitDef* def) const
{
	if (def == nullptr) {
		return -1.f;
	}
	float best = -1.f;
	for (const auto& kv : teamUnits) {
		CCircuitUnit* u = kv.second;
		if ((u == nullptr) || (u->GetCircuitDef() != def)) {
			continue;
		}
		const float p = u->GetUnit()->GetBuildProgress();
		if (p > best) {
			best = p;
		}
	}
	return best;
}

// Shared blackboard. Process-wide, so it reaches exactly the AIs this host is
// running and nobody else's -- which is the whole scope the team strategy has.
//
// Unguarded. Both accessors are only reached from AngelScript, which runs inside
// the AI's event handlers; those appeared to be serialised in every run so far
// (four instances logged elections 1 frame apart, never interleaved). That is an
// observation, not a proof -- this DLL is multithreaded elsewhere. If a torn
// read ever shows up here, a mutex is the fix; the map is tiny and cold.
static std::map<std::pair<int, std::string>, float> teamValues;

void CCircuitAI::PublishTeamValue(const std::string& key, float value)
{
	teamValues[std::make_pair(teamId, key)] = value;
}

float CCircuitAI::ReadTeamValue(int otherTeamId, const std::string& key, float defVal) const
{
	auto it = teamValues.find(std::make_pair(otherTeamId, key));
	return (it == teamValues.end()) ? defVal : it->second;
}

// Position of the most valuable reclaimable wreck within radius, or -RgtVector
// if there is nothing worth the trip.
//
// Area reclaim (CmdReclaimInArea, which is what a RECLAIM task issues) takes
// whatever happens to be inside the circle, so a builder sent to a battlefield
// is as likely to eat a 12-metal tree as a dead Gollum. Winning a fight and
// then eating the field is a large metal swing, and it only pays if we aim at
// the bodies. So: find the richest wreck, and let the caller centre the reclaim
// circle on it.
//
// Unlike the Game_getTeamResource* family, the features API is not gated on the
// broken AI_TEAM_IDS array -- its non-cheating path goes through CAICallback,
// which holds a real team id. Verified in SSkirmishAICallbackImpl.cpp.
//
// Deliberately does NOT use the CCircuitAI::metalRes member: that one is only
// ever assigned inside NotifyResign(), so for every team that has not resigned
// it stays null and both this function and GetWreckValueAt returned zero
// unconditionally, for the whole game, every time -- confirmed by a rate-limited
// log at the top of GetWreckValueAt showing metalRes=0x0 from frame 18 through
// frame 17769 of a 10-minute game. EconomyManager keeps its own separately-
// initialized metalRes (EconomyManager.cpp, set from Init()) which is why
// income/storage/sling all work fine off the same underlying resource. Resolve
// it fresh here instead of trusting the member.
// Any commander corpse, not only ours: the Feature API exposes no per-feature
// team-ownership accessor, only GetResurrectDef() (what this corpse would
// become), and a rez bot can resurrect any of them under its own control.
// Recent trade record, by metal value, over a decaying window.
//
// apexearth: "if our recent k/d is low we stop attacking so much, we start to
// be more careful and require greater odds to attack." Value, not unit count --
// trading ten Fleas for a Titan is a win and a raw count calls it a loss.
//
// Decayed rather than a ring buffer of timestamps: one multiply on a fixed
// cadence, no allocation, and it answers "lately" without a hard window edge
// where a single old fight drops out and flips the posture.
//
// Only mobile, armed units count on our side. A reclaimed wreck, a bombed mex
// or a lost nano turret says nothing about whether our ARMY is trading well,
// and folding them in made a player that was being eco-raided read as though
// its army were losing fights it never had.
void CCircuitAI::NoteTrade(bool isKill, CCircuitDef* cdef)
{
	if (cdef == nullptr) {
		return;
	}
	if (!isKill && (!cdef->IsMobile() || cdef->IsRoleComm())) {
		return;
	}
	const float v = cdef->GetCostM();
	if (isKill) {
		tradeKilled += v;
	} else {
		tradeLost += v;
	}
}

// Kills over losses, lately. 1.0 means even. Returns 1.0 until enough has
// happened to mean anything -- an unproven ratio must not tighten the engage
// test, or the opening (no fights yet, or one dead scout) reads as a collapse.
float CCircuitAI::GetRecentTradeRatio()
{
	const int frame = GetLastFrame();
	if (frame >= tradeDecayFrame + TRADE_DECAY_PERIOD) {
		tradeDecayFrame = frame;
		tradeKilled *= TRADE_DECAY;
		tradeLost *= TRADE_DECAY;
	}
	if ((tradeKilled + tradeLost) < TRADE_MIN_SAMPLE) {
		return 1.f;
	}
	if (tradeLost < 1.f) {
		return 2.f;  // killing without dying; the cap keeps this bounded
	}
	return tradeKilled / tradeLost;
}

void CCircuitAI::SetBaseGrid(const AIFloat3& anchor, const AIFloat3& fwd,
		float cell, float lanePitch, float laneHalf, float range)
{
	gridAnchor = anchor;
	gridFwd = fwd;
	gridCell = cell;
	gridLanePitch = lanePitch;
	gridLaneHalf = laneHalf;
	gridRange = range;
}

// Snap a build position onto the base grid, leaving the walkways empty.
//
// Returns false whenever the grid should not apply -- no frame published yet, or
// the position is outside the base entirely. Everything that must sit on a
// specific piece of ground (a metal spot, a geo vent, a tower on the front) is
// excluded by the CALLER on build type; this only knows about geometry.
bool CCircuitAI::SnapToBaseGrid(const AIFloat3& pos, AIFloat3& outPos) const
{
	if ((gridCell <= .0f) || !utils::is_valid(gridAnchor) || !utils::is_valid(pos)) {
		return false;
	}
	const float dx = pos.x - gridAnchor.x;
	const float dz = pos.z - gridAnchor.z;
	if ((dx * dx + dz * dz) > (gridRange * gridRange)) {
		return false;  // not in the base; leave it where the rule wanted it
	}

	// Into the base frame: `depth` runs backward from the anchor, `lat` across.
	const float depth = -(dx * gridFwd.x + dz * gridFwd.z);
	const float lat = dx * -gridFwd.z + dz * gridFwd.x;

	float sLat = std::round(lat / gridCell) * gridCell;
	const float sDepth = std::round(depth / gridCell) * gridCell;

	// Walkways are defined on the lateral axis, so a snapped column that lands in
	// one is pushed sideways to the first cell clear of it. Without this the grid
	// packs the corridors shut, which is the self-walling it exists to prevent.
	if (gridLanePitch > .0f) {
		const float laneCentre = std::round(sLat / gridLanePitch) * gridLanePitch;
		const float gap = std::fabs(sLat - laneCentre);
		if (gap < gridLaneHalf) {
			const float push = std::ceil((gridLaneHalf - gap) / gridCell) * gridCell;
			sLat += (sLat >= laneCentre) ? push : -push;
		}
	}

	outPos = AIFloat3(gridAnchor.x - gridFwd.x * sDepth + -gridFwd.z * sLat,
					  pos.y,
					  gridAnchor.z - gridFwd.z * sDepth + gridFwd.x * sLat);
	CTerrainManager::CorrectPosition(outPos);
	return true;
}

// A large building found no site. Recorded rather than acted on: deciding what
// is expendable is policy, and policy lives in AngelScript. apexearth: "when
// theres no room to build a gantry we need to reclaim older t1 buildings."
void CCircuitAI::NoteBuildBlocked(const springai::AIFloat3& pos)
{
	blockedBuildPos = pos;
	blockedBuildFrame = GetLastFrame();
}

bool CCircuitAI::GetBlockedBuildPos(springai::AIFloat3& outPos)
{
	if (GetLastFrame() > blockedBuildFrame + BLOCKED_BUILD_TTL) {
		return false;
	}
	if (!utils::is_valid(blockedBuildPos)) {
		return false;
	}
	outPos = blockedBuildPos;
	return true;
}

// Our own live units of one def near a position. Deliberately NOT filtered by
// what is "obsolete" -- that is the caller's judgement, and keeping it out of
// here is what stops this becoming a second place where policy hides.
// Skips anything still being built: reclaiming our own nanoframe is just
// burning the metal we already committed.
std::vector<CCircuitUnit*> CCircuitAI::GetOwnUnitsOfDef(CCircuitDef* def, const springai::AIFloat3& pos, float radius)
{
	std::vector<CCircuitUnit*> out;
	if (def == nullptr) {
		return out;
	}
	const float sqRadius = radius * radius;
	const int frame = GetLastFrame();
	for (auto& kv : teamUnits) {
		CCircuitUnit* u = kv.second;
		if ((u == nullptr) || (u->GetCircuitDef() != def)) {
			continue;
		}
		if (u->GetUnit()->IsBeingBuilt()) {
			continue;
		}
		if ((radius > 0.f) && (u->GetPos(frame).SqDistance2D(pos) > sqRadius)) {
			continue;
		}
		out.push_back(u);
	}
	return out;
}

// Ask the terrain manager for a site `def` can be placed on near `pos`.
//
// The script picks defence positions by arithmetic -- walk back from a hot
// spot, offset from home -- and never asks whether anything can stand there.
// Measured: 9 of 10 script defence tasks were cancelled having never resolved a
// build position, even with a 256 elmo search inside the task. Stock CircuitAI
// does not have this problem because its defence comes from real defence-point
// clusters. This exposes the same lookup CBFactoryTask::FindBuildSite uses, so
// a script rule can validate a spot BEFORE it enqueues work against it.
springai::AIFloat3 CCircuitAI::FindBuildSiteNear(CCircuitDef* def, const springai::AIFloat3& pos, float radius)
{
	if ((def == nullptr) || (radius <= 0.f) || !utils::is_valid(pos)) {
		return -RgtVector;
	}
	CTerrainManager* tm = GetTerrainManager();
	if (tm == nullptr) {
		return -RgtVector;
	}
	return tm->FindBuildSite(def, pos, radius, UNIT_NO_FACING);
}

// --- BWEM chokepoints, exposed to script -------------------------------------
//
// Read-only plumbing. The analysis already runs; nothing here changes it.

static const bwem::CChokePoint* GetChoke(CCircuitAI* circuit, int idx)
{
	const std::vector<bwem::CChokePoint*>& chokes =
			circuit->GetTerrainManager()->GetTAChokePoints();
	if ((idx < 0) || (idx >= (int)chokes.size())) {
		return nullptr;
	}
	return chokes[idx];
}

int CCircuitAI::GetChokePointCount() const
{
	return (int)GetTerrainManager()->GetTAChokePoints().size();
}

springai::AIFloat3 CCircuitAI::GetChokePointPos(int idx) const
{
	const bwem::CChokePoint* cp = GetChoke(const_cast<CCircuitAI*>(this), idx);
	return (cp == nullptr) ? AIFloat3(-RgtVector) : cp->GetCenter();
}

float CCircuitAI::GetChokePointWidth(int idx) const
{
	const bwem::CChokePoint* cp = GetChoke(const_cast<CCircuitAI*>(this), idx);
	return (cp == nullptr) ? .0f : cp->GetEnd1().distance2D(cp->GetEnd2());
}

bool CCircuitAI::GetChokePointEnds(int idx, AIFloat3& outEnd1, AIFloat3& outEnd2) const
{
	const bwem::CChokePoint* cp = GetChoke(const_cast<CCircuitAI*>(this), idx);
	if (cp == nullptr) {
		return false;
	}
	outEnd1 = cp->GetEnd1();
	outEnd2 = cp->GetEnd2();
	return true;
}

int CCircuitAI::GetChokePointArea(int idx, int which) const
{
	const bwem::CChokePoint* cp = GetChoke(const_cast<CCircuitAI*>(this), idx);
	if (cp == nullptr) {
		return -1;
	}
	const bwem::CArea* area = (which == 0) ? cp->GetAreas().first : cp->GetAreas().second;
	return (area == nullptr) ? -1 : area->GetId();
}

void CCircuitAI::DrawPoint(const AIFloat3& pos, const std::string& label)
{
	if ((drawer != nullptr) && IsPosOnMap(pos)) {
		drawer->AddPoint(pos, label.c_str());
	}
}

void CCircuitAI::DrawLine(const AIFloat3& from, const AIFloat3& to)
{
	if ((drawer != nullptr) && IsPosOnMap(from) && IsPosOnMap(to)) {
		drawer->AddLine(from, to);
	}
}

void CCircuitAI::DrawErase(const AIFloat3& pos)
{
	if ((drawer != nullptr) && IsPosOnMap(pos)) {
		drawer->DeletePointsAndLines(pos);
	}
}

// Influence lookups, bounds-guarded. See the header comment: the underlying
// CInfluenceMap accessors index an array from an unchecked position.
bool CCircuitAI::IsPosOnMap(const AIFloat3& pos) const
{
	CTerrainManager* terrainMgr = GetTerrainManager();
	return (pos.x >= .0f) && (pos.z >= .0f)
			&& (pos.x < terrainMgr->GetTerrainWidth())
			&& (pos.z < terrainMgr->GetTerrainHeight());
}

float CCircuitAI::GetAllyInflAt(const AIFloat3& pos) const
{
	return IsPosOnMap(pos) ? GetInflMap()->GetAllyInflAt(pos) : .0f;
}

float CCircuitAI::GetEnemyInflAt(const AIFloat3& pos) const
{
	return IsPosOnMap(pos) ? GetInflMap()->GetEnemyInflAt(pos) : .0f;
}

float CCircuitAI::GetNetInflAt(const AIFloat3& pos) const
{
	return IsPosOnMap(pos) ? GetInflMap()->GetInfluenceAt(pos) : .0f;
}

// Where our losses are happening, cost-weighted and decaying.
//
// The AI could say HOW MUCH enemy army exists (ApproachThreat is just
// EnemyArmyCost) but never WHERE it was hitting us, so defence went to a
// geometric border point and the army had nothing to converge on. apexearth:
// "do we have a way of detecting where enemies are attacking us from? and
// placing towers and defenses there... or at least moving our army there to act
// as a wall?"
//
// Cost-weighted so a dead constructor or a dead tank moves it and a dead scout
// barely does. Decayed so it tracks the CURRENT attack rather than accumulating
// every fight of the game into a meaningless average.
void CCircuitAI::NoteLossAt(const springai::AIFloat3& pos, float costM)
{
	if ((costM <= .0f) || !utils::is_valid(pos)) {
		return;
	}
	hotSum += pos * costM;
	hotWeight += costM;
}

bool CCircuitAI::GetAttackHotspot(springai::AIFloat3& outPos, float& outWeight)
{
	const int frame = GetLastFrame();
	if (frame >= hotDecayFrame + HOT_DECAY_PERIOD) {
		hotDecayFrame = frame;
		hotSum *= HOT_DECAY;
		hotWeight *= HOT_DECAY;
	}
	if (hotWeight < HOT_MIN_WEIGHT) {
		return false;
	}
	outPos = hotSum / hotWeight;
	outWeight = hotWeight;
	return true;
}

bool CCircuitAI::IsCommanderWreck(springai::Feature* f)
{
	if (f == nullptr) {
		return false;
	}
	springai::UnitDef* rezDef = f->GetResurrectDef();
	if (rezDef == nullptr) {
		return false;
	}
	const int id = rezDef->GetUnitDefId();
	delete rezDef;
	CCircuitDef* cdef = GetCircuitDefSafe(id);
	return (cdef != nullptr) && cdef->IsRoleComm();
}

springai::AIFloat3 CCircuitAI::GetBestWreckPos(const springai::AIFloat3& pos, float radius, float minMetal)
{
	springai::AIFloat3 best(-RgtVector);
	if ((callback == nullptr) || (radius <= 0.f)) {
		return best;
	}
	springai::Resource* metal = callback->GetResourceByName(RES_NAME_METAL);
	if (metal == nullptr) {
		return best;
	}

	float bestMetal = minMetal;
	const std::vector<springai::Feature*> feats = callback->GetFeaturesIn(pos, radius, false);
	for (springai::Feature* f : feats) {
		if (f == nullptr) {
			continue;
		}
		if (IsCommanderWreck(f)) {
			delete f;
			continue;
		}
		springai::FeatureDef* fd = f->GetDef();
		if (fd != nullptr) {
			// Reclaim left is a fraction of the def's contained metal; a wreck
			// someone else is already half way through is worth less to us.
			const float value = fd->GetContainedResource(metal) * f->GetReclaimLeft();
			if (value > bestMetal) {
				bestMetal = value;
				best = f->GetPosition();
			}
			delete fd;
		}
		delete f;
	}
	delete metal;
	return best;
}

// TOTAL reclaimable metal within radius, not the richest single body.
//
// GetBestWreckPos answers "is there one fat corpse here", which is the wrong
// question after a repelled push: a dozen dead T1s is several hundred metal and
// not one of them is individually large. apexearth: "often its a dozen t1 that
// just died... still its a lot of metal we should be eating".
// Same Feature::GetDef ownership rule as above -- that def IS ours to delete,
// unlike Unit::GetDef. See GetBestWreckPos's comment for why this resolves the
// metal resource locally instead of using the CCircuitAI::metalRes member,
// and its comment on IsCommanderWreck for why a commander corpse is excluded
// here too -- this feeds the "how rich is this field" total that gates
// whether a constructor gets sent at all, so a commander corpse skewing that
// total high would still walk a con onto it even if GetBestWreckPos itself
// never targets it directly.
float CCircuitAI::GetWreckValueAt(const springai::AIFloat3& pos, float radius)
{
	if ((callback == nullptr) || (radius <= 0.f)) {
		return .0f;
	}
	springai::Resource* metal = callback->GetResourceByName(RES_NAME_METAL);
	if (metal == nullptr) {
		return .0f;
	}
	float total = .0f;
	const std::vector<springai::Feature*> feats = callback->GetFeaturesIn(pos, radius, false);
	for (springai::Feature* f : feats) {
		if (f == nullptr) {
			continue;
		}
		if (IsCommanderWreck(f)) {
			delete f;
			continue;
		}
		springai::FeatureDef* fd = f->GetDef();
		if (fd != nullptr) {
			total += fd->GetContainedResource(metal) * f->GetReclaimLeft();
			delete fd;
		}
		delete f;
	}
	delete metal;
	return total;
}

// Count of visible enemy units within radius of a position.
//
// The first version summed metal value via u->GetDef()->GetCost(metalRes) and
// deleted the UnitDef. That crashed at +0x2f3326 within ~8400 frames and
// returned 0 throughout: unlike Feature::GetDef(), Unit::GetDef() hands back a
// pointer that is not ours to free. A count needs no defs at all, so there is
// nothing to get wrong -- and "how many enemies are on top of me" is the signal
// the commander actually needs.
float CCircuitAI::GetEnemyCostAt(const springai::AIFloat3& pos, float radius) const
{
	if ((callback == nullptr) || (radius <= 0.f)) {
		return 0.f;
	}
	const std::vector<springai::Unit*> foes = callback->GetEnemyUnitsIn(pos, radius, false);
	const float count = float(foes.size());
	for (springai::Unit* u : foes) {
		delete u;
	}
	return count;
}

// Threat at a position, from the engine-maintained threat map.
//
// This is what the earlier attempts were reaching for and missing. mobileThreat
// is a global scalar with no location, and GetEnemyCostAt counted units in a
// radius (and crashed). CThreatMap is a real per-position map the AI already
// maintains, and GetBuilderThreatAt asks precisely "how dangerous is this spot
// for something being built here" -- the question behind both bad factory
// placement and commander deaths.
float CCircuitAI::GetBuilderThreatAt(const springai::AIFloat3& pos) const
{
	CMapManager* mm = GetMapManager();
	if (mm == nullptr) {
		return 0.f;
	}
	CThreatMap* tm = mm->GetThreatMap();
	return (tm == nullptr) ? 0.f : tm->GetBuilderThreatAt(pos);
}

// Threat for THIS unit's movement type. GetBuilderThreatAt reads the surface
// layer only, so AddEnemyUnit routing HasSurfToAir enemies into the air layer
// means an AA turret contributes zero to it -- air constructors cannot see what
// kills them. CThreatMap picks the layer from the unit itself.
float CCircuitAI::GetUnitThreatAt(CCircuitUnit* unit, const springai::AIFloat3& pos) const
{
	CMapManager* mm = GetMapManager();
	if ((unit == nullptr) || (mm == nullptr)) {
		return 0.f;
	}
	CThreatMap* tm = mm->GetThreatMap();
	return (tm == nullptr) ? 0.f : tm->GetThreatAt(unit, pos);
}

void CCircuitAI::SendResources(float metal, float energy, int toTeamId)
{
	// Crashed at frame 1 when called before the economy interface was ready, or
	// with a team id the engine had not resolved yet. Validate everything.
	if ((toTeamId < 0) || (toTeamId == teamId)
		|| (economy == nullptr) || (metalRes == nullptr) || (energyRes == nullptr))
	{
		return;
	}
	// Never send more than is actually held, or the command is a no-op that
	// still costs a callback.
	if (metal > 0.f) {
		const float have = economy->GetCurrent(metalRes);
		if (have > 0.f) {
			economy->SendResource(metalRes, std::min(metal, have), toTeamId);
		}
	}
	if (energy > 0.f) {
		const float have = economy->GetCurrent(energyRes);
		if (have > 0.f) {
			economy->SendResource(energyRes, std::min(energy, have), toTeamId);
		}
	}
}

void CCircuitAI::GiveUnits(std::vector<CCircuitUnit*>&& units, int newTeamId)
{
	// NOTE: See notes in MobileSlave or other economy->SendUnits places
	std::vector<Unit*> migrants;
	migrants.reserve(units.size());
	for (CCircuitUnit* unit : units) {
		migrants.push_back(unit->GetUnit());
		// Units only marked for deletion, should be safe
		UnitDestroyed(unit, nullptr);
		UnregisterTeamUnit(unit);
	}
	economy->SendUnits(migrants, newTeamId);
}

void CCircuitAI::Garbage(CCircuitUnit* unit, const char* reason)
{
	// NOTE: Happens because engine can send EVENT_UNIT_FINISHED after EVENT_UNIT_DESTROYED.
	//       Engine should not send events with isDead units.
	garbage.insert(unit);
#ifdef DEBUG_LOG
	LOG("AI: %i | Garbage unit: %i | reason: %s", skirmishAIId, unit->GetId(), reason);
#endif
}

CCircuitUnit* CCircuitAI::GetTeamUnit(ICoreUnit::Id unitId) const
{
	auto it = teamUnits.find(unitId);
	return (it != teamUnits.end()) ? it->second : nullptr;
}

CAllyUnit* CCircuitAI::GetFriendlyUnit(Unit* u) const
{
	if (u->GetTeam() == teamId) {
		return GetTeamUnit(u->GetUnitId());
	} else if (u->GetAllyTeam() == allyTeamId) {
		return allyTeam->GetFriendlyUnit(u->GetUnitId());
	}

	return nullptr;
}

std::pair<CAllyUnit*, bool> CCircuitAI::GetTeamOrAllyUnit(springai::Unit* u) const
{
	if (u->GetTeam() == teamId) {
		return std::make_pair(GetTeamUnit(u->GetUnitId()), true);
	} else if (u->GetAllyTeam() == allyTeamId) {
		return std::make_pair(allyTeam->GetFriendlyUnit(u->GetUnitId()), false);
	}

	return std::make_pair(nullptr, false);
}

std::pair<CEnemyInfo*, bool> CCircuitAI::RegisterEnemyInfo(ICoreUnit::Id unitId, bool isInLOS)
{
	CEnemyInfo* unit = GetEnemyInfo(unitId);
	if (unit != nullptr) {
		if (isInLOS && !allyTeam->EnemyInLOS(unit->GetData(), this)) {
			return std::make_pair(nullptr, false);
		}
		return std::make_pair(unit, true);
	}

	CEnemyUnit* data;
	bool isReal;
	std::tie(data, isReal) = allyTeam->RegisterEnemyUnit(unitId, isInLOS, this);
	if (data == nullptr) {
		return std::make_pair(nullptr, isReal);
	}

	unit = new CEnemyInfo(data);
	enemyInfos[unitId] = unit;

	return std::make_pair(unit, true);
}

CEnemyInfo* CCircuitAI::RegisterEnemyInfo(Unit* e)
{
	CEnemyUnit* data = allyTeam->RegisterEnemyUnit(e, this);
	if (data == nullptr) {
		return nullptr;
	}

	CEnemyInfo* unit = new CEnemyInfo(data);
	enemyInfos[unit->GetId()] = unit;

	return unit;
}

void CCircuitAI::UnregisterEnemyInfo(CEnemyInfo* enemy)
{
	allyTeam->UnregisterEnemyUnit(enemy->GetData(), this);
	enemyInfos.erase(enemy->GetId());
	delete enemy;
}

void CCircuitAI::CreateFakeEnemy(int weaponId, const AIFloat3& startPos, const AIFloat3& dir)
{
	const SWeaponToUnitDef& wuDef = weaponToUnitDefs[weaponId];
	if (wuDef.ids.empty()) {
		return;
	}
	float range = weaponDefs[weaponId].GetRange();
	const AIFloat3 enemyPos = CTerrainManager::CorrectPosition(startPos, dir, range);  // range adjusted
	CEnemyUnit* enemy = allyTeam->GetEnemyOrFakeIn(startPos, dir, range, enemyPos, range * 0.2f, wuDef.ids);
	if (enemy == nullptr) {
		int timeout = lastFrame;
		CCircuitDef::Id defId;
		if (wuDef.mobileIds.empty()) {  // static
			timeout += FRAMES_PER_SEC * 60 * 20;
			defId = *wuDef.staticIds.begin();
		} else {
			timeout += FRAMES_PER_SEC * 60 * 1;
			defId = *wuDef.mobileIds.begin();
		}
		allyTeam->RegisterEnemyFake(defId, enemyPos, timeout);
	} else if (enemy->IsBeingBuilt()) {
		enemy->SetBeingBuilt(false);
		enemy->SetHealth(enemy->GetCircuitDef()->GetHealth());
		GetThreatMap()->SetEnemyUnitThreat(enemy);
	}
}

void CCircuitAI::CheckDecoy(CEnemyInfo* enemy, int weaponId)
{
	CCircuitDef* edef = enemy->GetCircuitDef();
	if ((edef != nullptr) && edef->IsDecoy()) {
		const SWeaponToUnitDef& wuDef = weaponToUnitDefs[weaponId];
		if (!wuDef.ids.empty()) {
			allyTeam->UpdateInLOS(enemy->GetData(), *wuDef.ids.begin());
		}
	}
}

CEnemyInfo* CCircuitAI::GetEnemyInfo(ICoreUnit::Id unitId) const
{
	auto it = enemyInfos.find(unitId);
	return (it != enemyInfos.end()) ? it->second : nullptr;
}

bool CCircuitAI::UnitControl(CCircuitUnit* unit, bool isEnable)
{
	if ((unit == nullptr)/* || (unit->GetTask()->GetType() == IUnitTask::Type::NIL)*/) {
		return false;
	}
	if (isEnable) {
		if (unit->GetTask()->GetType() != IUnitTask::Type::PLAYER) {
			return false;
		}
		unit->GetTask()->RemoveAssignee(unit);
	} else {
		ITaskModule* mgr = unit->GetTask()->GetManager();
		mgr->AssignTask(unit, new CPlayerTask(mgr));
	}
	return true;
}

void CCircuitAI::UpdateActions()
{
	if (actionIterator >= actionUnits.size()) {
		actionIterator = 0;
	}

	// stagger the Update's
	unsigned int n = (actionUnits.size() / ACTION_UPDATE_RATE) + 1;

	while ((actionIterator < actionUnits.size()) && (n != 0)) {
		CCircuitUnit* unit = actionUnits[actionIterator];
		if (unit->IsDead()) {
			actionUnits[actionIterator] = actionUnits.back();
			actionUnits.pop_back();
			DeleteTeamUnit(unit);
		} else {
			if (unit->GetTask()->GetType() != IUnitTask::Type::PLAYER) {
				unit->Update(this);
				--n;
			}
			++actionIterator;
		}
	}
}

std::string CCircuitAI::InitOptions()
{
	OptionValues* options = skirmishAI->GetOptionValues();
	const char* value;

	value = options->GetValueByKey("cheating");
	if (value != nullptr) {
		isCheating = StringToBool(value);
	}

	value = options->GetValueByKey("comm_merge");
	if (value != nullptr) {
		isCommMerge = StringToBool(value);
	}

	value = options->GetValueByKey("ally_base");
	if (value != nullptr) {
		isAllyBaseAvoid = StringToBool(value);
	}

	if (!gameAttribute->IsInitialized()) {
		value = options->GetValueByKey("random_seed");
		unsigned int seed = (value != nullptr) ? StringToInt(value) : time(nullptr);
		gameAttribute->Init(seed);
	}

	value = options->GetValueByKey("profile");
	std::string profile = ((value != nullptr) && strlen(value) > 0) ? value : "";

	delete options;
	return profile;
}

CCircuitDef* CCircuitAI::GetCircuitDef(const char* name)
{
	auto it = defsByName.find(name);
	// NOTE: For the sake of AI's health it should not return nullptr
	return (it != defsByName.end()) ? it->second : nullptr;
}

void CCircuitAI::InitRoles()
{
	for (const auto& kv : CCircuitDef::GetRoleNames()) {
		BindRole(kv.second.type, kv.second.type);
	}
}

void CCircuitAI::InitUnitDefs(const CCircuitDef::SArmorInfo& armor, float& outDcr)
{
	gameAttribute->GetTerrainData().Init(this);

	Resource* resM = callback->GetResourceByName(RES_NAME_METAL);
	Resource* resE = callback->GetResourceByName(RES_NAME_ENERGY);
	outDcr = 0.f;

	auto unitDefs = callback->GetUnitDefs();
	defsById.reserve(unitDefs.size());

	for (UnitDef* ud : unitDefs) {
		auto options = ud->GetBuildOptions();
		std::unordered_set<CCircuitDef::Id> opts;
		for (UnitDef* buildDef : options) {
			opts.insert(buildDef->GetUnitDefId());
			delete buildDef;
		}
		// new CCircuitDef(this, ud, opts, resM, resE, armor);
		defsById.emplace_back(this, ud, opts, resM, resE, armor);

		defsByName[ud->GetName()] = &defsById.back();

		const float dcr = ud->GetDecloakDistance();
		if (outDcr < dcr) {
			outDcr = dcr;
		}
	}

	delete resM;
	delete resE;

	for (CCircuitDef& cdef : GetCircuitDefs()) {
		cdef.Init(this);
	}
}

void CCircuitAI::BindUnitToWeaponDefs(CCircuitDef::Id unitDefId, const std::set<CWeaponDef::Id>& weaponDefs, bool isMobile)
{
	if (isMobile) {
		for (CWeaponDef::Id weaponDefId : weaponDefs) {
			SWeaponToUnitDef& wuDef = weaponToUnitDefs[weaponDefId];
			wuDef.mobileIds.insert(unitDefId);
			wuDef.ids.insert(unitDefId);
		}
	} else {
		for (CWeaponDef::Id weaponDefId : weaponDefs) {
			SWeaponToUnitDef& wuDef = weaponToUnitDefs[weaponDefId];
			wuDef.staticIds.insert(unitDefId);
			wuDef.ids.insert(unitDefId);
		}
	}
}

void CCircuitAI::InitWeaponDefs()
{
	Resource* resM = callback->GetResourceByName(RES_NAME_METAL);
	Resource* resE = callback->GetResourceByName(RES_NAME_ENERGY);
	auto weapDefs = callback->GetWeaponDefs();
	weaponDefs.reserve(weapDefs.size());
	for (WeaponDef* wd : weapDefs) {
		// new CWeaponDef(wd, resM, resE);
		weaponDefs.emplace_back(wd, resM, resE);
	}
	delete resM;
	delete resE;
	weaponToUnitDefs.resize(weapDefs.size());
}

CThreatMap* CCircuitAI::GetThreatMap() const
{
	return mapManager->GetThreatMap();
}

CInfluenceMap* CCircuitAI::GetInflMap() const
{
	return mapManager->GetInflMap();
}

int CCircuitAI::GetEnemyTeamSize() const
{
	return callback->GetEnemyTeamSize();
}

void CCircuitAI::CreateGameAttribute()
{
	if (gameAttribute == nullptr) {
		gameAttribute = std::unique_ptr<CGameAttribute>(new CGameAttribute());
		CCircuitDef::InitStatic(this, &gameAttribute->GetRoleMasker(), &gameAttribute->GetAttrMasker());
	}
	gaCounter++;
	gameAttribute->RegisterAI(this);
}

void CCircuitAI::DestroyGameAttribute()
{
	gameAttribute->UnregisterAI(this);
	if (gaCounter <= 1) {
		if (gameAttribute != nullptr) {
			gameAttribute = nullptr;  // deletes singleton here;
		}
		gaCounter = 0;
	} else {
		gaCounter--;
	}
}

void CCircuitAI::PrepareAreaUpdate()
{
	GetPathfinder()->SetAreaUpdated(false);  // one pathfinder for few allies
	GetEnemyManager()->SetAreaUpdated(false);  // one enemy manager for few allies
}

} // namespace circuit
