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
#include "task/fighter/FighterTask.h"
#include "unit/CircuitUnit.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/enemy/EnemyManager.h"
#include "util/GameAttribute.h"
#include "util/Utils.h"
#include "util/ProcessClock.h"
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
#include "MoveData.h"
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
#include "DataDirs.h"
#include "Info.h"
#include "File.h"
//#include "WrappCurrentCommand.h"

#include <fstream>
#include <limits>
#include <chrono>
#include <algorithm>

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

	logFile = nullptr;
	{
		std::unique_ptr<Info> info(skirmishAI->GetInfo());
		const char* name = info->GetValueByKey("name");
		const char* version = info->GetValueByKey("version");
		logTag = std::string((name != nullptr) ? name : "?") + "-" + ((version != nullptr) ? version : "?");
		std::unique_ptr<DataDirs> dirs(clb->GetDataDirs());
		const char* dir = dirs->GetWriteableDir();
		if (dir != nullptr) {
			const std::string path = std::string(dir) + "apex-t" + std::to_string(teamId) + ".log";
			logFile = fopen(path.c_str(), "w");
			if (logFile != nullptr) {
				setvbuf(logFile, nullptr, _IOFBF, 1 << 16);
				logEpochNs = utils::ProcessAgeNs();
				logSteady0 = std::chrono::steady_clock::now();
				LOG_ENGINE("apex: log file %s", path.c_str());
			}
			recPath = std::string(dir) + "apex-record.txt";
		}
	}
}

void CCircuitAI::LogLine(const char* msg)
{
	if (logFile == nullptr) {
		GetLog()->DoLog(msg);
		return;
	}
	// the engine's own prefix, so every tool reads the merged file unchanged
	int64_t ns = logEpochNs + std::chrono::duration_cast<std::chrono::nanoseconds>(
			std::chrono::steady_clock::now() - logSteady0).count();
	const int hh = int(ns / 3600000000000LL); ns %= 3600000000000LL;
	const int mm = int(ns / 60000000000LL); ns %= 60000000000LL;
	const int ss = int(ns / 1000000000LL); ns %= 1000000000LL;
	std::lock_guard<std::mutex> lock(logMutex);
	fprintf(logFile, "[t=%02d:%02d:%02d.%06lld][f=%07d] Skirmish AI <%s>: %s\n",
			hh, mm, ss, (long long)(ns / 1000), (lastFrame < 0) ? -1 : lastFrame, logTag.c_str(), msg);
}

void CCircuitAI::FlushLog()
{
	if (logFile != nullptr) {
		std::lock_guard<std::mutex> lock(logMutex);
		fflush(logFile);
	}
}

CCircuitAI::~CCircuitAI()
{
	if (isInitialized) {
		Release(0);
	}
	if (logFile != nullptr) {
		fclose(logFile);
		logFile = nullptr;
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
	// apex: every engine event that ISN'T EVENT_UPDATE runs outside AiFrame's
	// clock, so UnitCreated/Damaged/Destroyed and EnemyEnterLOS were being
	// counted as engine time by every frame budget we have taken. Nanoseconds,
	// because a single handler rounds to zero microseconds; RAII, because
	// EVENT_INIT returns from inside the switch.
	struct SEvtClock {
		CCircuitAI* self;
		bool on;
		std::chrono::steady_clock::time_point t0;
		~SEvtClock() {
			if (!on) {
				return;
			}
			self->perfEvtNs += std::chrono::duration_cast<std::chrono::nanoseconds>(
					std::chrono::steady_clock::now() - t0).count();
			++self->perfEvtCalls;
		}
	} evtClock{this, topic != EVENT_UPDATE, std::chrono::steady_clock::now()};

	int ret = ERROR_UNKNOWN;

	switch (topic) {
		case EVENT_INIT: {
			TRACY_TOPIC("EVENT_INIT", Init);

			struct SInitEvent* evt = (struct SInitEvent*)data;
			try {
				ret = this->Init(evt->skirmishAIId, evt->callback);
			} catch (const CException& e) {
				Release(RELEASE_CORRUPTED);
				LOG_ENGINE("Exception: %s", e.what());
				NotifyGameEnd();
				ret = 0;
			} catch (const std::exception& e) {
				Release(RELEASE_CORRUPTED);
				LOG_ENGINE("Lib exception: %s", e.what());
				ret = ERROR_INIT;  // non-zero value deletes AI
			} catch (...) {
				Release(RELEASE_CORRUPTED);  // DestroyGameAttribute
				LOG_ENGINE("Unknown exception");
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
			if (evt->attacker >= 0) {
				RecordDealt(evt->attacker, evt->damage);
			}
			CEnemyInfo* enemy = GetEnemyInfo(evt->enemy);
			ret = (enemy != nullptr) ? this->EnemyDamaged(enemy) : ERROR_ENEMY_DAMAGED;
		} break;
		case EVENT_ENEMY_DESTROYED: {
			TRACY_TOPIC("EVENT_ENEMY_DESTROYED", EnemyDestroyed);

			struct SEnemyDestroyedEvent* evt = (struct SEnemyDestroyedEvent*)data;
			CEnemyInfo* enemy = GetEnemyInfo(evt->enemy);
			if (enemy != nullptr) {
				// Here, not in the deferred EnemyDestroyed: the attacker id only
				// exists in this event, and a non-(-1) attacker is by contract
				// allied with us -- ours iff it is one of our team units.
				script->EnemyDestroyed(enemy->GetCircuitDef(), enemy->GetPos(),
						GetTeamUnit(evt->attacker) != nullptr);
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
	LOG_ENGINE(version);
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
	RecordLoad();

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
			scheduler->RunJobEvery(mergeTask, FRAMES_PER_SEC, FRAMES_PER_SEC * 10, "merge");
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
			scheduler->RunJobEvery(mergeTask, FRAMES_PER_SEC, FRAMES_PER_SEC * 10, "merge");
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

	for (auto& kv : teamUnits) {
		RecordFold(kv.second, false);
	}
	RecordSave();

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

	DrainDeferredReleases();  // before the unit dtors below release into it again
	tgtHeld.clear();  // pure observation; must not outlive what it points at
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
	unitsByDef.clear();
	teamStatics.clear();
	teamMobiles.clear();
	garbage.clear();
	for (CCircuitUnit* unit : deadUnits) {
		delete unit;
	}
	deadUnits.clear();
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

void CCircuitAI::DrainDeferredReleases()
{
	// Swap first: a Release can run dtors that defer further releases.
	std::vector<IRefCounter*> drain;
	while (!deferredReleases.empty()) {
		drain.swap(deferredReleases);
		for (IRefCounter* obj : drain) {
			obj->Release();
		}
		drain.clear();
	}
}

int CCircuitAI::Update(int frame)
{
	const auto perfT0 = std::chrono::steady_clock::now();
	destroyed.clear();
	DrainDeferredReleases();
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

	const auto tAlly0 = std::chrono::steady_clock::now();
	allyTeam->Update(this);
	const auto tJobs0 = std::chrono::steady_clock::now();
	perfAllyUs += std::chrono::duration_cast<std::chrono::microseconds>(tJobs0 - tAlly0).count();

	scheduler->ProcessJobs(frame);
	perfJobsUs += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - tJobs0).count();
	// Timed separately: this is AngelScript, and outside every bucket it was
	// landing in `other`, which reads as unattributed C++ and is not.
	const auto tScr0 = std::chrono::steady_clock::now();
	if (frame % TEAM_SLOWUPDATE_RATE == skirmishAIId) {
		// NOTE: Probably should be last in ProcessJobs queue, after all income updates if it was in the same frame.
		//       Hence it is not:
		// scheduler->RunJobEvery(CScheduler::GameJob(&CInitScript::Update, script), TEAM_SLOWUPDATE_RATE, skirmishAIId);
		script->Update();
	}
	const auto tAct0 = std::chrono::steady_clock::now();
	perfScrUs += std::chrono::duration_cast<std::chrono::microseconds>(tAct0 - tScr0).count();
	UpdateActions();
	perfActUs += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - tAct0).count();

#ifdef DEBUG_VIS
	if (frame % FRAMES_PER_SEC == 0) {
		allyTeam->GetEnergyGrid()->UpdateVis();
		debugDrawer->Refresh();
	}
#endif

	// apex: squad sizes, ours against the enemy's, on one comparable line per
	// 30s. Ours = units on ATTACK/DEFEND tasks; theirs = mobile armed units per
	// enemy cluster -- the mass that actually arrives, whatever their AI calls it.
	// apex: purge stale enemy ghosts, once per ally team (the registry is
	// shared) on a slow cadence. See CEnemyManager::PurgeStaleGhosts.
	if ((frame >= ghostPurgeNext) && (enemyManager != nullptr) && (allyTeam != nullptr)
		&& (allyTeam->GetLeaderId() == skirmishAIId))
	{
		ghostPurgeNext = frame + FRAMES_PER_SEC * 30;
		const int confirmedAge = (int)(GetTunable("apex_ghost_purge_secs", 90.f)
				* FRAMES_PER_SEC);
		const int unknownAge = (int)(GetTunable("apex_ghost_stale_min", 15.f)
				* 60.f * FRAMES_PER_SEC);
		enemyManager->PurgeStaleGhosts(frame, confirmedAge, unknownAge);
	}
	if ((frame >= squadDiagNextLog) && (militaryManager != nullptr) && (enemyManager != nullptr)) {
		squadDiagNextLog = frame + 900;
		int nOwn = 0, uOwn = 0, mOwn = 0;
		for (IFighterTask::FightType t : {IFighterTask::FightType::ATTACK, IFighterTask::FightType::DEFEND}) {
			for (IFighterTask* ft : militaryManager->GetTasks(t)) {
				const int s = (int)ft->GetAssignees().size();
				if (s <= 0) {
					continue;
				}
				++nOwn;
				uOwn += s;
				mOwn = std::max(mOwn, s);
			}
		}
		int nE = 0, uE = 0, mE = 0;
		for (const CEnemyManager::SEnemyGroup& g : enemyManager->GetEnemyGroups()) {
			int s = 0;
			for (const ICoreUnit::Id eId : g.units) {
				CEnemyInfo* e = GetEnemyInfo(eId);
				if ((e != nullptr) && (e->GetCircuitDef() != nullptr)
					&& e->GetCircuitDef()->IsMobile() && e->GetCircuitDef()->IsAttacker()) {
					++s;
				}
			}
			if (s <= 0) {
				continue;
			}
			++nE;
			uE += s;
			mE = std::max(mE, s);
		}
		LOG("apex: squadsize own n=%i avg=%.1f max=%i | enemy n=%i avg=%.1f max=%i",
				nOwn, (nOwn > 0) ? float(uOwn) / nOwn : 0.f, mOwn,
				nE, (nE > 0) ? float(uE) / nE : 0.f, mE);
	}

	// apex: one holder probe per frame (see tgtCursor in the header). upper_bound
	// rather than a kept iterator: teamUnits is mutated by death every frame.
	if (!teamUnits.empty()) {
		auto it = teamUnits.upper_bound(tgtCursor);
		if (it == teamUnits.end()) {
			it = teamUnits.begin();
		}
		tgtCursor = it->first;
		CCircuitUnit* probe = it->second;
		if ((probe != nullptr) && !probe->IsDead() && (probe->GetUnit() != nullptr)) {
			const float tid = probe->GetUnit()->GetRulesParamFloat("targetID", -2.f);
			// S7 done on a unit we KNOW we enrolled. The first version of this
			// log fired at frame 0 on the commander, before any set-target had
			// ever been sent, read the -2 default and was taken to mean the
			// param is dead -- it is not, and every hold= it printed was real.
			if (!tgtRawLogged && (tgtHeld.find(probe) != tgtHeld.end())) {
				tgtRawLogged = true;
				LOG("apex: tgthold t=%i raw targetID=%.1f on an enrolled unit"
						" (-2 = param absent, -1 = released, >=0 = held)",
						teamId, tid);
			}
			++tgtSamp;
			if (tid >= 0.f) {
				++tgtHold;
			} else if (tid > -1.5f) {
				++tgtRel;
			}
		}
	}

	const uint64_t perfUs = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - perfT0).count();
	perfFrameUs += perfUs;
	perfFrameMaxUs = std::max(perfFrameMaxUs, perfUs);
	FlushLog();
	if (perfUs > 30000) {  // name any spike instantly: aligns (or not) with watched hitches
		LOG("apex: perf SPIKE frame=%d ms=%.1f", frame, perfUs / 1000.f);
	}
	++perfFrameCalls;
	if (frame >= perfFrameNextLog) {
		perfFrameNextLog = frame + 1800;   // one game-minute at 30 fps
		LOG("apex: perf AiFrame calls=%u totalMs=%.1f avgUs=%.0f maxMs=%.1f",
				perfFrameCalls, perfFrameUs / 1000.f,
				(perfFrameCalls > 0) ? float(perfFrameUs) / float(perfFrameCalls) : 0.f,
				perfFrameMaxUs / 1000.f);
		const uint64_t perfAccounted = perfAllyUs + perfJobsUs + perfActUs + perfScrUs;
		LOG("apex: perf split allyMs=%.1f jobsMs=%.1f actMs=%.1f scrMs=%.1f otherMs=%.1f"
				" evtMs=%.1f/%u",
				perfAllyUs / 1000.f, perfJobsUs / 1000.f, perfActUs / 1000.f,
				perfScrUs / 1000.f,
				(perfFrameUs > perfAccounted) ? (perfFrameUs - perfAccounted) / 1000.f : 0.f,
				perfEvtNs / 1000000.f, perfEvtCalls);
		perfEvtNs = 0;
		perfEvtCalls = 0;
		// apex: how much WORK the O(n) helpers did, not how long they took --
		// a visited count that grows faster than the unit count names the
		// quadratic helper without a clock in the hot loop.
		if (mapManager != nullptr) {
			CWreckField& wf = mapManager->GetWreckField();
			perfFeatSweep = wf.perfSweep; perfFeatCalls = wf.perfCalls;
			LOG("apex: perf wreckfield scanned=%llu items=%i version=%i",
					(unsigned long long)wf.perfScanned, wf.GetCount(), wf.GetVersion());
			wf.perfSweep = 0; wf.perfCalls = 0; wf.perfScanned = 0;
		}
		LOG("apex: perf sweep feat=%llu/%u reach=%llu/%u own=%llu/%u ecost=%llu/%u",
				(unsigned long long)perfFeatSweep, perfFeatCalls,
				(unsigned long long)perfReachSweep, perfReachCalls,
				(unsigned long long)perfOwnSweep, perfOwnCalls,
				(unsigned long long)perfEcostSweep, perfEcostCalls);
		// apex: the reach envelope itself, not its cost. worst is the deepest
		// inside-an-enemy's-reach any caller was told it stood this minute, and
		// maxReach the largest envelope in the cache: a strategic launcher
		// leaking into it reads map-scale in both.
		LOG("apex: perf reach worst=%.0f maxReach=%.0f def=%s n=%u",
				(perfReachWorst < std::numeric_limits<float>::max()) ? perfReachWorst : 0.f,
				perfReachMax,
				(perfReachMaxDef != nullptr) ? perfReachMaxDef->GetDef()->GetName() : "-",
				(unsigned)reachCache.size());
		perfReachWorst = std::numeric_limits<float>::max();
		perfReachMax = 0.f;
		perfReachMaxDef = nullptr;
		perfFeatSweep = 0; perfFeatCalls = 0;
		perfReachSweep = 0; perfReachCalls = 0;
		perfOwnSweep = 0; perfOwnCalls = 0;
		perfEcostSweep = 0; perfEcostCalls = 0;
		LOG("apex: perf sweep ownDef=%llu/%u ownStruct=%llu/%u ownDmg=%llu/%u",
				(unsigned long long)perfOwnDefSweep, perfOwnDefCalls,
				(unsigned long long)perfOwnStrSweep, perfOwnStrCalls,
				(unsigned long long)perfOwnDmgSweep, perfOwnDmgCalls);
		perfOwnDefSweep = 0; perfOwnDefCalls = 0;
		perfOwnStrSweep = 0; perfOwnStrCalls = 0;
		perfOwnDmgSweep = 0; perfOwnDmgCalls = 0;
		// apex: what we cost the ENGINE, not ourselves -- every order it has to
		// insert, run AllowCommand over, and (when the point moved at all)
		// re-path. rep* is the same unit being told the same thing inside 3s.
		// dupable = moves a re-send provably could not change; DROPPED only when
		// apex_order_dedupe is on, counted either way, so the number is what
		// turning it on would buy rather than what it bought.
		LOG("apex: orders t=%i move=%u fight=%u patrol=%u attack=%u target=%u dupable=%u",
				teamId, ordSent[0], ordSent[1], ordSent[2], ordSent[3], ordSent[4], ordSup[0]);
		LOG("apex: order-rep t=%i move same=%u lt8=%u lt32=%u lt128=%u far=%u"
				" | fight=%u attack=%u target=%u",
				teamId, ordRep[0][0], ordRep[0][1], ordRep[0][2], ordRep[0][3], ordRep[0][4],
				ordRep[1][0] + ordRep[1][1] + ordRep[1][2] + ordRep[1][3] + ordRep[1][4],
				ordRep[3][0] + ordRep[3][1] + ordRep[3][2] + ordRep[3][3] + ordRep[3][4],
				ordRep[4][0]);
		// apex: WHICH LOOP SENT THEM. sent/repeat-within-3s/far-repeat per call
		// site -- the attribution the kind census cannot give, and without which
		// every rule aimed at order volume is a guess. Order matches
		// CCircuitUnit::OrdSrc.
		{
			std::string line;
			char buf[96];
			for (int i = 0; i < ORD_SRC_N; ++i) {
				if (ordSrc[i][0] == 0) {
					continue;
				}
				snprintf(buf, sizeof(buf), " %s=%u/%u/%u",
						CCircuitUnit::OrdSrcName(i),
						ordSrc[i][0], ordSrc[i][1], ordSrc[i][2]);
				line += buf;
			}
			LOG("apex: order-src t=%i (sent/rep/far) arcflip=%u/%u units=%u/%u%s",
					teamId, arcFlip[0], arcFlip[1], arcFlipU[0], arcFlipU[1],
					line.c_str());
			std::string ref;
			for (int i = 0; i < ORD_SRC_N; ++i) {
				if (ordRefused[i] == 0) { continue; }
				snprintf(buf, sizeof(buf), " %s=%u", CCircuitUnit::OrdSrcName(i), ordRefused[i]);
				ref += buf;
				ordRefused[i] = 0;
			}
			if (!ref.empty()) {
				LOG("apex: order-refused t=%i (a lower-ranked centre tried to overwrite a live decision)%s", teamId, ref.c_str());
			}
		}
		// apex: mirror the gadget's own un-enrolments before counting, or `own`
		// only ever grows: it drops a dead target (n%5 checkTarget) and, for
		// anything but a building, one gone from radar+los (n%15
		// removeUnseenTarget, alwaysSeen = isBuilding). dead must stay 0.
		unsigned ownStale = 0, ownDead = 0, ownGone = 0;
		for (auto it = tgtHeld.begin(); it != tgtHeld.end(); ) {
			CCircuitUnit* u = *it;
			if (u->IsDead()) {
				++ownDead;
				it = tgtHeld.erase(it);
				continue;
			}
			CEnemyInfo* e = GetEnemyInfo(u->GetTgtHeldId());
			const CCircuitDef* edef = (e != nullptr) ? e->GetCircuitDef() : nullptr;
			if ((e == nullptr)
				|| ((edef != nullptr) && edef->IsMobile() && !e->IsInRadarOrLOS()))
			{
				++ownGone;
				it = tgtHeld.erase(it);
				continue;
			}
			if (u->GetTarget() == nullptr) {
				++ownStale;
			}
			++it;
		}
		LOG("apex: tgthold t=%i own=%u stale=%u dead=%u gone=%u | samp=%u hold=%u rel=%u"
				" est=%.1f units=%u",
				teamId, (unsigned)tgtHeld.size(), ownStale, ownDead, ownGone,
				tgtSamp, tgtHold, tgtRel,
				(tgtSamp > 0) ? float(tgtHold) / tgtSamp * teamUnits.size() : 0.f,
				(unsigned)teamUnits.size());
		tgtSamp = 0;
		tgtHold = 0;
		tgtRel = 0;
		for (int k = 0; k < 5; ++k) {
			ordSent[k] = 0;
			ordSup[k] = 0;
			for (int b = 0; b < 5; ++b) {
				ordRep[k][b] = 0;
			}
		}
		for (int k = 0; k < ORD_SRC_N; ++k) {
			ordSrc[k][0] = ordSrc[k][1] = ordSrc[k][2] = 0;
		}
		arcFlip[0] = arcFlip[1] = 0;
		arcFlipU[0] = arcFlipU[1] = 0;
		scheduler->LogJobPerf(this);
		scheduler->LogWorkPerf(this);
		GetAllyTeam()->LogMapPerf(this);
		perfAllyUs = 0;
		perfJobsUs = 0;
		perfActUs = 0;
		perfScrUs = 0;
		perfFrameUs = 0;
		perfFrameMaxUs = 0;
		perfFrameCalls = 0;
	}

	return 0;  // signaling: OK
}

int CCircuitAI::Message(int playerId, const char* message)
{
	// apex: EVERYTHING below is #ifdef DEBUG_VIS, which only CIRCUIT_DEBUG
	// defines -- so in every shipped build the AI parsed no chat command at all
	// and `~widraw`/`~wtdraw` silently did nothing. The widget overlays are
	// wanted in ordinary watched games (they stream to a LuaRules gadget and
	// need no SDL), so those two are handled here, unconditionally.
	{
		const char wiDraw[] = "~widraw";
		const char wtDraw[] = "~wtdraw";
		const size_t len = strlen(message);
		if ((len >= 9) && (strncmp(message, wiDraw, 7) == 0)) {
			if (teamId == atoi(&message[8])) {
				mapManager->GetInflMap()->ToggleWidgetDraw();
			}
			return 0;
		}
#ifdef DEBUG_VIS
		// The threat map's widget half is still inside its own DEBUG_VIS block;
		// split it the same way as InfluenceMap when this proves out.
		if ((len >= 9) && (strncmp(message, wtDraw, 7) == 0)) {
			if (teamId == atoi(&message[8])) {
				mapManager->GetThreatMap()->ToggleWidgetDraw();
			}
			return 0;
		}
#else
		(void)wtDraw;
#endif
	}

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
		// The commander is never written off: a permanent stuck flag swallowed
		// every idle and move-failed event after minute 6.7 while a Reclaim of
		// himself sat in the queue. The script's pen test frees him.
		if (unit->GetCircuitDef()->IsRoleComm()) {
			unit->ClearStuck();
			LOG("apex: move-failed commander #%d", unit->GetId());
			return 0;  // signaling: OK
		}
		// ROAM unsticks a fighter; on a builder it was permanent, and a
		// roaming commander is the one that chases "into the sunset".
		const bool roam = !unit->GetCircuitDef()->IsBuilder();
		TRY_UNIT(this, unit,
			unit->CmdStop();
			if (roam) {
				unit->CmdSetMoveState(CCircuitDef::MoveType::ROAM);
			}
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
	unit->SetDamagedDir(dir);  // points toward the shooter (see CreateFakeEnemy)
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
	// insert().second: this is called repeatedly for a unit already dead
	// (measured: one nano's id logged 2,350 times over three minutes, pos
	// (1,1)) -- the set existed but nothing checked it. First call only.
	const bool firstDeath = destroyed.insert(unit->GetId()).second;
	if (firstDeath) {
		NoteTrade(false, unit->GetCircuitDef());
		RecordFold(unit, true);
		// Feeds the attack hotspot: where we are losing things is the best
		// evidence available of where the enemy actually is. (Repeated calls
		// were also multiplying this and NoteTrade -- pre-existing.)
		if (unit->GetCircuitDef() != nullptr) {
			NoteLossAt(unit->GetPos(GetLastFrame()), unit->GetCircuitDef()->GetCostM());
		}
		// BEFORE the modules: their UnitDestroyed strips the unit's task
		// (task->OnUnitDestroyed -> RemoveAssignee -> reassigned idle/nil),
		// so the script hook fired after them read every death as "idle".
		// The script only does bookkeeping; it needs the task the unit
		// actually died holding.
		script->UnitDestroyed(unit);
		// Attribution rides a separate optional callback; only fired when the
		// attacker's def is actually known (see CInitScript::UnitDestroyedBy).
		if (attacker != nullptr) {
			script->UnitDestroyedBy(unit, attacker->GetCircuitDef());
		}
	}

	for (auto& module : modules) {
		module->UnitDestroyed(unit, attacker);
	}

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
			// A sudden threat appearing IS news about where to be.
			unit->ForceUpdate(lastFrame + THREAT_UPDATE_RATE, CCircuitUnit::Wake::RECONSIDER);
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

	auto slot = teamUnits.emplace(unitId, unit);
	if (!slot.second) {  // re-register: the old instance leaves the indices first
		IndexTeamUnit(slot.first->second, false);
		tgtHeld.erase(slot.first->second);
		slot.first->second = unit;
	}
	IndexTeamUnit(unit, true);
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
	IndexTeamUnit(unit, false);
	teamUnits.erase(unit->GetId());
	tgtHeld.erase(unit);  // the gadget's UnitDestroyed does the same on its side
	unit->GetCircuitDef()->Dec();

	/*(unit->GetTask() == nullptr) ? DeleteTeamUnit(unit) : */unit->SetIsDead();
}

void CCircuitAI::DeleteTeamUnit(CCircuitUnit* unit)
{
	garbage.erase(unit);
	tgtHeld.erase(unit);  // last chance before the instance is deleted
	deadUnits.insert(unit);  // deferred to Release(); see deadUnits decl
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

float CCircuitAI::GetTunable(const char* name, float defVal) const
{
	auto it = tunables.find(name);
	if (it != tunables.end()) {
		return it->second;
	}
	const float value = (game != nullptr) ? game->GetRulesParamFloat(name, defVal) : defVal;
	tunables[name] = value;
	return value;
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
	auto bucket = unitsByDef.find(def->GetId());
	if (bucket == unitsByDef.end()) {
		return best;
	}
	for (CCircuitUnit* u : bucket->second) {
		if (u->GetCircuitDef() != def) {
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

// A unit type's record. Ratio 1 = its units dealt their own health in damage;
// the prior counts as apex_record_prior units at exactly that, so one death
// cannot condemn a type, and the window keeps it a moving average over the
// last apex_record_window units rather than a lifetime verdict.
bool CCircuitAI::RecordCounts(CCircuitDef* cdef)
{
	return (cdef != nullptr) && cdef->IsMobile() && cdef->IsAttacker() && !cdef->IsRoleComm();
}

void CCircuitAI::RecordDealt(ICoreUnit::Id attacker, float damage)
{
	if ((damage <= .0f) || (GetTeamUnit(attacker) == nullptr)) {
		return;
	}
	recDealt[attacker] += damage;
}

void CCircuitAI::RecordFold(CCircuitUnit* unit, bool died)
{
	CCircuitDef* cdef = unit->GetCircuitDef();
	auto it = recDealt.find(unit->GetId());
	const float dealt = (it != recDealt.end()) ? it->second : .0f;
	if (it != recDealt.end()) {
		recDealt.erase(it);
	}
	if (!RecordCounts(cdef) || !unit->IsFinished()) {
		return;
	}
	const float hp = cdef->GetHealth();
	if (hp <= .0f) {
		return;
	}
	// Only a death is a verdict: a survivor at a time-limit end is young.
	if (died) {
		SRecord& r = recGame[cdef->GetId()];
		r.dealt += dealt;
		r.health += hp;
		r.n += 1.f;
	}
	LOG("apex: record %s %s dealt=%.0f hp=%.0f r=%.2f avg=%.2f n=%d", cdef->GetDef()->GetName(),
			died ? "died" : "alive", dealt, hp, dealt / hp, RecordRatio(cdef), RecordCount(cdef));
}

float CCircuitAI::RecordRatio(CCircuitDef* cdef) const
{
	if (!RecordCounts(cdef)) {
		return 1.f;
	}
	const float prior = GetTunable("apex_record_prior", 10.f) * cdef->GetHealth();
	float dealt = prior, health = prior;
	auto g = recGame.find(cdef->GetId());
	if (g != recGame.end()) {
		dealt += g->second.dealt;
		health += g->second.health;
	}
	auto st = recStored.find(cdef->GetId());
	if (st != recStored.end()) {
		dealt += st->second.dealt;
		health += st->second.health;
	}
	return dealt / health;
}

int CCircuitAI::RecordCount(CCircuitDef* cdef) const
{
	float n = .0f;
	auto g = recGame.find(cdef->GetId());
	if (g != recGame.end()) {
		n += g->second.n;
	}
	auto st = recStored.find(cdef->GetId());
	if (st != recStored.end()) {
		n += st->second.n;
	}
	return int(n + 0.5f);
}

static void RecordRead(const std::string& path, std::unordered_map<std::string, CCircuitAI::SRecord>& out)
{
	std::ifstream in(path);
	std::string name;
	CCircuitAI::SRecord r;
	while (in >> name >> r.dealt >> r.health >> r.n) {
		out[name] = r;
	}
}

void CCircuitAI::RecordLoad()
{
	recStored.clear();
	if (recPath.empty()) {
		return;
	}
	std::unordered_map<std::string, SRecord> byName;
	RecordRead(recPath, byName);
	for (auto& kv : byName) {
		CCircuitDef* cdef = GetCircuitDef(kv.first.c_str());
		if (cdef != nullptr) {
			recStored[cdef->GetId()] = kv.second;
		}
	}
	LOG_ENGINE("apex: record loaded %d types from %s", (int)recStored.size(), recPath.c_str());
}

// Re-read before writing: every AI in this process saves its own game onto
// whatever the file holds by then, so eight teams do not overwrite each other.
void CCircuitAI::RecordSave()
{
	if (recPath.empty() || recGame.empty()) {
		return;
	}
	std::unordered_map<std::string, SRecord> all;
	RecordRead(recPath, all);
	const float window = GetTunable("apex_record_window", 40.f);
	for (auto& kv : recGame) {
		CCircuitDef* cdef = GetCircuitDef(kv.first);
		if (cdef == nullptr) {
			continue;
		}
		SRecord& r = all[cdef->GetDef()->GetName()];
		r.dealt += kv.second.dealt;
		r.health += kv.second.health;
		r.n += kv.second.n;
		if (r.n > window) {
			const float k = window / r.n;
			r.dealt *= k;
			r.health *= k;
			r.n = window;
		}
	}
	std::ofstream out(recPath, std::ios::trunc);
	if (!out.is_open()) {
		LOG_ENGINE("apex: record NOT saved: %s", recPath.c_str());
		return;
	}
	for (auto& kv : all) {
		out << kv.first << ' ' << kv.second.dealt << ' ' << kv.second.health << ' ' << kv.second.n << std::endl;
	}
	LOG_ENGINE("apex: record saved %d types (%d this game)", (int)all.size(), (int)recGame.size());
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
	// The anchor itself must sit on the engine's 16-elmo build lattice, or every
	// frame-snapped position inherits its residue and the parity snap below can
	// move a building half a cell off the intended column.
	gridAnchor = AIFloat3(std::round(anchor.x / 16.f) * 16.f, anchor.y,
			std::round(anchor.z / 16.f) * 16.f);
	gridFwd = fwd;
	gridCell = cell;
	gridLanePitch = lanePitch;
	gridLaneHalf = laneHalf;
	gridRange = range;
}

int CCircuitAI::GetBaseGridFacing(const AIFloat3& pos) const
{
	if ((gridCell <= .0f) || !utils::is_valid(gridAnchor) || !utils::is_valid(pos)) {
		return UNIT_NO_FACING;
	}
	const float dx = pos.x - gridAnchor.x;
	const float dz = pos.z - gridAnchor.z;
	if ((dx * dx + dz * dz) > (gridRange * gridRange)) {
		return UNIT_NO_FACING;
	}
	// The ENEMY bearing, not the band axis: the axis may legally 180-flip for
	// band room (a corner start scores double the buildable cells facing away),
	// and a factory obeying the flipped axis exits into the map edge. gridFwd
	// is only the fallback while no enemy has been seen.
	float fx = gridFwd.x, fz = gridFwd.z;
	const AIFloat3& foe = enemyManager->GetEnemyPos();
	if (utils::is_valid(foe)) {
		const float ex = foe.x - gridAnchor.x;
		const float ez = foe.z - gridAnchor.z;
		if ((ex * ex + ez * ez) > 1.f) {
			fx = ex; fz = ez;
		}
	}
	if (std::fabs(fx) >= std::fabs(fz)) {
		return (fx >= 0.f) ? UNIT_FACING_EAST : UNIT_FACING_WEST;
	}
	return (fz >= 0.f) ? UNIT_FACING_SOUTH : UNIT_FACING_NORTH;
}

// Snap a build position onto the base grid, leaving the walkways empty.
//
// Returns false whenever the grid should not apply -- no frame published yet, or
// the position is outside the base entirely. Everything that must sit on a
// specific piece of ground (a metal spot, a geo vent, a tower on the front) is
// excluded by the CALLER on build type; this only knows about geometry.
// Distance from an offset on either base axis to the nearest walkway centre.
static inline float LaneGapAt(float u, float pitch)
{
	return std::fabs(u - std::round(u / pitch) * pitch);
}

// The first cell clear of the walkway, on the side the offset already sits.
static inline float PushOutOfLane(float u, float cell, float pitch, float half)
{
	const float centre = std::round(u / pitch) * pitch;
	const float gap = std::fabs(u - centre);
	if (gap >= half) {
		return u;
	}
	const float push = std::ceil((half - gap) / cell) * cell;
	return u + ((u >= centre) ? push : -push);
}

bool CCircuitAI::IsInBaseLane(const AIFloat3& pos) const
{
	if ((gridLanePitch <= .0f) || (gridLaneHalf <= .0f)
		|| !utils::is_valid(gridAnchor) || !utils::is_valid(pos))
	{
		return false;
	}
	const float dx = pos.x - gridAnchor.x;
	const float dz = pos.z - gridAnchor.z;
	if ((dx * dx + dz * dz) > (gridRange * gridRange)) {
		return false;  // not in the base; the streets are a base layout, not a map one
	}
	const float depth = -(dx * gridFwd.x + dz * gridFwd.z);
	const float lat = dx * -gridFwd.z + dz * gridFwd.x;
	if (depth > .0f) {
		return false;  // behind the anchor is the economy: no streets (script LanesApply)
	}
	return (LaneGapAt(lat, gridLanePitch) < gridLaneHalf)
		|| (LaneGapAt(depth, gridLanePitch) < gridLaneHalf);
}

// THE LATTICE IS PER DEF, IN WORLD AXES, PHASED FROM THE MAP'S CORNER.
// A def tiles on its own footprint, and each cell centre already satisfies
// the engine's parity mapping (Pos2BuildPos), so snapping is idempotent and
// script, the ring walk and the commit agree on one set of points. Edges
// fall on the build lines from (0,0), so defs whose pitches divide (6-cell
// lab, 3-cell turret) pack flush, and nothing waits on the base frame --
// which arrives after the opening solars. The frame serves only the lanes.
void CCircuitAI::LatticeOf(CCircuitDef* def, int facing, float& px, float& pz,
		float& ox, float& oz) const
{
	constexpr float BUILD_SQ = SQUARE_SIZE * 2;
	px = BUILD_SQ;
	pz = BUILD_SQ;
	ox = .0f;
	oz = .0f;
	if (def == nullptr) {
		return;
	}
	const bool swap = ((facing != UNIT_NO_FACING) && ((facing & 1) == 1));
	px = swap ? def->GetLatticeStrideZ() : def->GetLatticeStrideX();
	pz = swap ? def->GetLatticeStrideX() : def->GetLatticeStrideZ();
	if (px < BUILD_SQ) px = BUILD_SQ;
	if (pz < BUILD_SQ) pz = BUILD_SQ;
	const int fx = swap ? def->GetFootZ() : def->GetFootX();
	const int fz = swap ? def->GetFootX() : def->GetFootZ();
	// Corner on (0,0): the centre is half a footprint in from it, and a
	// stride that is a whole footprint keeps every further cell's edges on
	// the build lines.
	ox = float(fx) * SQUARE_SIZE;
	oz = float(fz) * SQUARE_SIZE;
}

// Cell centre nearest `pos` on the def's lattice, in world axes; no lane push.
void CCircuitAI::LatticeCell(const AIFloat3& pos, CCircuitDef* def, int facing, AIFloat3& outPos) const
{
	float px, pz, ox, oz;
	LatticeOf(def, facing, px, pz, ox, oz);
	const float kx = std::round((pos.x - ox) / px);
	const float kz = std::round((pos.z - oz) / pz);
	outPos = AIFloat3(ox + kx * px, pos.y, oz + kz * pz);
}

bool CCircuitAI::SnapToBaseGrid(const AIFloat3& pos, AIFloat3& outPos,
		CCircuitDef* def, int facing) const
{
	if (!utils::is_valid(pos)) {
		return false;
	}
	// EVERYWHERE, not only inside the base range, and from frame 0: a farm at
	// an expansion is the same rows, and the range once left every placement
	// past it to the square-by-square search, which is the "right and down
	// by one" he sees.
	AIFloat3 cell;
	LatticeCell(pos, def, facing, cell);
	LatticePoint(cell, def, facing, outPos);
	return utils::is_valid(outPos);
}

// A cell pushed clear of the walkways. Walkways run on BOTH axes, so a cell
// that lands in one is moved out by whole pitches, which keeps it on the
// lattice. Without this the grid packs the corridors shut, which is the
// self-walling it exists to prevent. Half the footprint is part of the gap:
// the lane test is on the centre, and a building standing with its centre
// exactly a half-lane out has half of itself in the street.
void CCircuitAI::LatticePoint(const AIFloat3& cell, CCircuitDef* def, int facing, AIFloat3& outPos) const
{
	outPos = cell;
	if ((gridLanePitch > .0f) && (gridLaneHalf > .0f) && utils::is_valid(gridAnchor)) {
		float px, pz, ox, oz;
		LatticeOf(def, facing, px, pz, ox, oz);
		const float dx = cell.x - gridAnchor.x;
		const float dz = cell.z - gridAnchor.z;
		const float depth = -(dx * gridFwd.x + dz * gridFwd.z);
		if (depth <= .0f) {  // no streets behind the anchor
			// The base axes are world axes here (the frame is a cardinal):
			// lat runs along z when the axis runs along x, and vice versa.
			const bool latIsZ = std::fabs(gridFwd.x) >= std::fabs(gridFwd.z);
			const float lat = dx * -gridFwd.z + dz * gridFwd.x;
			const float cLat = latIsZ ? pz : px;
			const float cDepth = latIsZ ? px : pz;
			const float sLat = PushOutOfLane(lat, cLat, gridLanePitch, gridLaneHalf + cLat * .5f);
			const float sDepth = PushOutOfLane(depth, cDepth, gridLanePitch, gridLaneHalf + cDepth * .5f);
			outPos.x = gridAnchor.x - gridFwd.x * sDepth + -gridFwd.z * sLat;
			outPos.z = gridAnchor.z - gridFwd.z * sDepth + gridFwd.x * sLat;
		}
	}
	CTerrainManager::CorrectPosition(outPos);
}

bool CCircuitAI::LatticeNeighbour(const AIFloat3& snapped, CCircuitDef* def, int facing,
		int i, int j, AIFloat3& outPos) const
{
	if (!utils::is_valid(snapped)) {
		return false;
	}
	float px, pz, ox, oz;
	LatticeOf(def, facing, px, pz, ox, oz);
	// (i, j) in world axes -- the callers walk rings and floods, for which
	// the axis names do not matter, only that the cells are the def's.
	AIFloat3 cell(snapped.x + float(i) * px, snapped.y, snapped.z + float(j) * pz);
	if ((cell.x < .0f) || (cell.z < .0f)
		|| (cell.x > float(CTerrainManager::GetTerrainWidth()))
		|| (cell.z > float(CTerrainManager::GetTerrainHeight())))
	{
		return false;  // off the map: open ground to the flood, nothing to the walk
	}
	LatticePoint(cell, def, facing, outPos);
	return utils::is_valid(outPos);
}

// A large building found no site. Recorded rather than acted on: deciding what
// is expendable is policy, and policy lives in AngelScript. apexearth: "when
// theres no room to build a gantry we need to reclaim older t1 buildings."
void CCircuitAI::NoteBuildBlocked(const springai::AIFloat3& pos, const CCircuitDef* def)
{
	blockedBuildPos = pos;
	blockedBuildFrame = GetLastFrame();
	blockedBuildDef = (def != nullptr) ? int(def->GetId()) : -1;
}

void CCircuitAI::NoteUnsafeSite(const springai::AIFloat3& pos)
{
	const int frame = GetLastFrame();
	// Ten minutes of memory, one entry per site: a refused site is refused
	// again every election until something changes.
	for (auto& e : unsafeSites) {
		if (e.first.SqDistance2D(pos) < 100.f * 100.f) {
			e.second = frame;
			return;
		}
	}
	unsafeSites.emplace_back(pos, frame);
	while (!unsafeSites.empty() && (frame - unsafeSites.front().second > 30 * 60 * 10)) {
		unsafeSites.erase(unsafeSites.begin());
	}
	if (unsafeSites.size() > 256) {
		unsafeSites.erase(unsafeSites.begin());
	}
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

// Keep the teamUnits indices in step. Sorted-by-id insert/erase, because a
// std::map walk hands callers ascending ids and some of them stop at the first
// hit -- a different order there is a different unit, not a faster answer.
void CCircuitAI::IndexTeamUnit(CCircuitUnit* unit, bool isAdd)
{
	if (unit == nullptr) {
		return;
	}
	CCircuitDef* cdef = unit->GetCircuitDef();
	const ICoreUnit::Id id = unit->GetId();
	auto byId = [](CCircuitUnit* a, ICoreUnit::Id b) { return a->GetId() < b; };
	auto touch = [&](std::vector<CCircuitUnit*>& vec) {
		auto it = std::lower_bound(vec.begin(), vec.end(), id, byId);
		if (isAdd) {
			if ((it == vec.end()) || ((*it)->GetId() != id)) {
				vec.insert(it, unit);
			}
		} else if ((it != vec.end()) && (*it == unit)) {
			// By pointer, not by id: a re-registered id owns a different
			// instance, and dropping that one would leave the index short of
			// a unit teamUnits still holds.
			vec.erase(it);
		}
	};
	if (cdef != nullptr) {
		touch(unitsByDef[cdef->GetId()]);
		touch(cdef->IsMobile() ? teamMobiles : teamStatics);
	}
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
	auto bucket = unitsByDef.find(def->GetId());
	if (bucket == unitsByDef.end()) {
		++perfOwnCalls;
		++perfOwnDefCalls;
		return out;
	}
	// The def filter was the whole point of the walk, so index by it instead of
	// re-deriving it: same units, same ascending-id order, without touching the
	// other several hundred.
	const std::vector<CCircuitUnit*>& mine = bucket->second;
	perfOwnSweep += mine.size();
	++perfOwnCalls;
	perfOwnDefSweep += mine.size();
	++perfOwnDefCalls;
	for (CCircuitUnit* u : mine) {
		if (u->GetCircuitDef() != def) {  // same id, foreign instance: the old test, kept
			continue;
		}
		// Distance before IsBeingBuilt: the position is cached per frame, the
		// engine's answer is not, and most of the team is out of radius.
		if ((radius > 0.f) && (u->GetPos(frame).SqDistance2D(pos) > sqRadius)) {
			continue;
		}
		if (u->GetUnit()->IsBeingBuilt()) {
			continue;
		}
		out.push_back(u);
	}
	return out;
}

std::vector<CCircuitUnit*> CCircuitAI::GetOwnStructsNear(const springai::AIFloat3& pos, float radius)
{
	std::vector<CCircuitUnit*> out;
	GetOwnStructsNear(pos, radius, out);
	return out;
}

void CCircuitAI::GetOwnStructsNear(const springai::AIFloat3& pos, float radius, std::vector<CCircuitUnit*>& out)
{
	out.clear();
	const float sqRadius = radius * radius;
	const int frame = GetLastFrame();
	perfOwnSweep += teamStatics.size();
	++perfOwnCalls;
	perfOwnStrSweep += teamStatics.size();
	++perfOwnStrCalls;
	for (CCircuitUnit* u : teamStatics) {
		if ((radius > 0.f) && (u->GetPos(frame).SqDistance2D(pos) > sqRadius)) {
			continue;
		}
		if (u->GetUnit()->IsBeingBuilt()) {
			continue;
		}
		out.push_back(u);
	}
}

bool CCircuitAI::HasOwnStructNear(const springai::AIFloat3& pos, float radius)
{
	const float sqRadius = radius * radius;
	const int frame = GetLastFrame();
	++perfOwnCalls;
	++perfOwnStrCalls;
	for (CCircuitUnit* u : teamStatics) {
		++perfOwnSweep;  // counts what was visited: this one stops early
		++perfOwnStrSweep;
		if ((radius > 0.f) && (u->GetPos(frame).SqDistance2D(pos) > sqRadius)) {
			continue;
		}
		if (u->GetUnit()->IsBeingBuilt()) {
			continue;
		}
		return true;
	}
	return false;
}

std::vector<CCircuitUnit*> CCircuitAI::GetOwnDamagedNear(const springai::AIFloat3& pos, float radius)
{
	std::vector<CCircuitUnit*> out;
	const float sqRadius = radius * radius;
	const int frame = GetLastFrame();
	perfOwnSweep += teamMobiles.size();
	++perfOwnCalls;
	perfOwnDmgSweep += teamMobiles.size();
	++perfOwnDmgCalls;
	for (CCircuitUnit* u : teamMobiles) {
		// Distance first: health percent is four engine round trips per unit
		// (health, max health, capture progress) and this is called per medic
		// and per repair election, so the team was being asked its condition
		// thousands of times a second to answer a question about one radius.
		if ((radius > 0.f) && (u->GetPos(frame).SqDistance2D(pos) > sqRadius)) {
			continue;
		}
		if (u->GetUnit()->IsBeingBuilt() || (u->GetHealthPercent() >= 1.f)) {
			continue;
		}
		out.push_back(u);
	}
	return out;
}

float CCircuitAI::GetPathLength(CCircuitUnit* unit, const springai::AIFloat3& to)
{
	if ((unit == nullptr) || (unit->GetCircuitDef() == nullptr)) {
		return -1.f;
	}
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (!cdef->IsMobile() || cdef->IsAbleToFly()) {
		return -1.f;
	}
	const int defId = cdef->GetId();
	auto it = pathTypes.find(defId);
	if (it == pathTypes.end()) {
		springai::MoveData* md = cdef->GetDef()->GetMoveData();
		if (md == nullptr) {
			it = pathTypes.emplace(defId, -1).first;
		} else {
			it = pathTypes.emplace(defId, md->GetPathType()).first;
			delete md;
		}
	}
	if (it->second < 0) {
		return -1.f;
	}
	// goalRadius 0 asks for the exact square and fails on anything standing on
	// it; SQUARE_SIZE * 8 is the granularity the estimator works at anyway.
	return GetPathing()->GetApproximateLength(unit->GetPos(GetLastFrame()), to, it->second, 64.f);
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

// SAreaData::GetElevationAt indexes heightMap straight from the position with
// no check of its own, and this build has asserts compiled out -- so the guards
// are the code. The area data is double-buffered for threading and can be
// swapped underneath a reader, hence the null test as well as the bounds one.
// READ A FILE OUT OF THE VFS -- the game archive and the map archive both.
//
// File_getContent routes to CFileHandler with none of the alliance gating that
// makes Game_getTeamResourceIncome useless (see GetTeamMetalIncome), so an AI
// can read the same configs the gadgets read. This is how the lava tide's own
// schedule becomes knowable at frame 0 instead of being learned a crest at a
// time: manager/lava.as parses it.
//
// Empty string on any failure, including a file that is not there -- callers
// must treat that as "no answer", never as "empty config".
std::string CCircuitAI::ReadVfsFile(const std::string& name) const
{
	springai::File* file = callback->GetFile();
	if (file == nullptr) {
		return std::string();
	}
	const int size = file->GetSize(name.c_str());
	if ((size <= 0) || (size > MAX_VFS_READ)) {
		return std::string();
	}
	std::string buf(size_t(size), ' ');
	if (!file->GetContent(name.c_str(), &buf[0], size)) {
		return std::string();
	}
	return buf;
}

float CCircuitAI::GetElevationAt(const AIFloat3& pos) const
{
	if (!IsPosOnMap(pos)) {
		return .0f;
	}
	CTerrainManager* terrainMgr = GetTerrainManager();
	if (terrainMgr == nullptr) {
		return .0f;
	}
	SAreaData* area = terrainMgr->GetAreaData();
	if ((area == nullptr) || area->heightMap.empty()) {
		return .0f;
	}
	const int ix = int(pos.x) / SQUARE_SIZE;
	const int iz = int(pos.z) / SQUARE_SIZE;
	const int idx = iz * area->heightMapXSize + ix;
	if ((idx < 0) || (idx >= int(area->heightMap.size()))) {
		return .0f;
	}
	return area->heightMap[idx];
}

float CCircuitAI::GetLavaLevel() const
{
	if (lavaFrame == lastFrame) {
		return lavaLevel;
	}
	lavaFrame = lastFrame;
	lavaLevel = (game != nullptr)
			? game->GetRulesParamFloat("lavaLevel", NO_LAVA - 1.f)
			: (NO_LAVA - 1.f);
	return lavaLevel;
}

// Is this ground under the lava surface right now?
//
// The gadget damages whatever's BASE position sits below the level, so a
// floating structure is judged at the waterline and a grounded one at the
// terrain under it. Fixed sites (a mex on its spot) never ask: refusing the
// spot loses the extractor rather than moving it, and that call belongs to the
// script's pricing, not to a veto here.
bool CCircuitAI::IsUnderLava(const AIFloat3& pos, CCircuitDef* def) const
{
	const float level = GetLavaLevel();
	if (level <= NO_LAVA) {
		return false;
	}
	float rest = GetElevationAt(pos);
	if ((def != nullptr) && def->IsFloater() && (rest < .0f)) {
		rest = .0f;
	}
	return rest <= level;
}

int CCircuitAI::GetTerritoryAt(const AIFloat3& pos) const
{
	return IsPosOnMap(pos) ? GetInflMap()->GetTerritoryAt(pos) : 0;
}

int CCircuitAI::GetTerritoryVersion() const
{
	return (mapManager == nullptr) ? 0 : GetInflMap()->GetTerritoryVersion();
}

int CCircuitAI::GetWreckFieldVersion() const
{
	return (mapManager == nullptr) ? 0 : mapManager->GetWreckField().GetVersion();
}

float CCircuitAI::GetAllyInflAt(const AIFloat3& pos) const
{
	return IsPosOnMap(pos) ? GetInflMap()->GetAllyInflAt(pos) : .0f;
}

// Armed units and turrets only: where our guns reach, not where a builder stands.
float CCircuitAI::GetAllyDefendInflAt(const AIFloat3& pos) const
{
	return IsPosOnMap(pos) ? GetInflMap()->GetAllyDefendInflAt(pos) : .0f;
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
//
// Kept as a small set of spots rather than one centroid: a loss merges into the
// nearest spot within apex_hot_radius, else takes a free slot, else overwrites
// the weakest. Two simultaneous breaches stay two positions, which is what lets
// separate garrisons answer separate breaches.
void CCircuitAI::NoteLossAt(const springai::AIFloat3& pos, float costM)
{
	if ((costM <= .0f) || !utils::is_valid(pos)) {
		return;
	}
	const float radius = GetTunable("apex_hot_radius", 1000.f);

	int best = -1;
	float bestSqDist = radius * radius;
	int weakest = -1;
	float weakestWeight = std::numeric_limits<float>::max();
	for (unsigned i = 0; i < hotSpots.size(); ++i) {
		const float sqDist = hotSpots[i].pos.SqDistance2D(pos);
		if (sqDist <= bestSqDist) {
			bestSqDist = sqDist;
			best = int(i);
		}
		if (hotSpots[i].weight < weakestWeight) {
			weakestWeight = hotSpots[i].weight;
			weakest = int(i);
		}
	}
	if (best >= 0) {
		SHotSpot& spot = hotSpots[best];
		const float total = spot.weight + costM;
		spot.pos = (spot.pos * spot.weight + pos * costM) / total;
		spot.weight = total;
		return;
	}
	if (hotSpots.size() < HOT_SPOT_NUM) {
		SHotSpot spot;
		spot.pos = pos;
		spot.weight = costM;
		hotSpots.push_back(spot);
		return;
	}
	if ((weakest >= 0) && (hotSpots[weakest].weight < costM)) {
		hotSpots[weakest].pos = pos;
		hotSpots[weakest].weight = costM;
	}
}

void CCircuitAI::DecayHotSpots()
{
	const int frame = GetLastFrame();
	if (frame < hotDecayFrame + HOT_DECAY_PERIOD) {
		return;
	}
	hotDecayFrame = frame;
	// A spot decayed to nothing is a fight that finished; dropping it frees the
	// slot for the next one rather than holding a stale position for the game.
	for (int i = int(hotSpots.size()) - 1; i >= 0; --i) {
		hotSpots[i].weight *= HOT_DECAY;
		if (hotSpots[i].weight < 1.f) {
			hotSpots.erase(hotSpots.begin() + i);
		}
	}
}

const std::vector<CCircuitAI::SHotSpot>& CCircuitAI::GetHotSpots()
{
	DecayHotSpots();
	return hotSpots;
}

// The heaviest single spot. Identical to the old centroid while only one fight
// is running, which is the case this used to be right for.
bool CCircuitAI::GetAttackHotspot(springai::AIFloat3& outPos, float& outWeight)
{
	DecayHotSpots();
	int best = -1;
	float bestWeight = HOT_MIN_WEIGHT;
	for (unsigned i = 0; i < hotSpots.size(); ++i) {
		if (hotSpots[i].weight >= bestWeight) {
			bestWeight = hotSpots[i].weight;
			best = i;
		}
	}
	if (best < 0) {
		return false;
	}
	outPos = hotSpots[best].pos;
	outWeight = hotSpots[best].weight;
	return true;
}

// apex: what a feature def is worth, resolved once per FEATURE DEF and kept.
// Contained metal and the "<unit>_dead" -> unit cost lookup are properties of
// the def, not of the corpse, but the sweeps below used to re-ask the engine
// (and re-parse the name, and re-hash the def map) for every corpse on every
// pass. Wrecks are what grows in a long game, so this was the cost that grew
// fastest.
const CCircuitAI::SFeatDefInfo& CCircuitAI::GetFeatDefInfo(int featureDefId)
{
	static const SFeatDefInfo empty = {0.f, -1.f};
	if (featureDefId < 0) {
		return empty;
	}
	if ((size_t)featureDefId >= featDefInfo.size()) {
		featDefInfo.resize(featureDefId + 64, {-1.f, -1.f});
	}
	SFeatDefInfo& info = featDefInfo[featureDefId];
	if (info.metal < 0.f) {
		info.metal = callback->FeatureDef_GetContainedResource(featureDefId, metalResId);
		info.rezCostM = -1.f;
		const char* raw = callback->FeatureDef_GetName(featureDefId);
		if (raw != nullptr) {
			const std::string name(raw);
			const size_t at = name.rfind("_dead");
			if (at != std::string::npos) {
				CCircuitDef* ud = GetCircuitDef(name.substr(0, at).c_str());
				if (ud != nullptr) {
					info.rezCostM = ud->GetCostM();
				}
			}
		}
	}
	return info;
}

// A commander corpse is identified by what it resurrects into. Kept per
// FEATURE (not per def): the resurrect def is a property of the corpse.
bool CCircuitAI::IsCommanderWreckId(int rezDefId)
{
	if (rezDefId < 0) {
		return false;
	}
	CCircuitDef* cdef = GetCircuitDefSafe(rezDefId);
	return (cdef != nullptr) && cdef->IsRoleComm();
}

// AN AREA RECLAIM TAKES WHATEVER IS IN THE CIRCLE, so the only way to keep a
// commander corpse out of one is to know where it is (apexearth: "make sure
// nano turrets don't reclaim dead commanders"). The per-feature filter in
// CBReclaimTask only guards the targeted search.
springai::AIFloat3 CCircuitAI::GetCommanderWreckPos(const springai::AIFloat3& pos, float radius)
{
	if ((mapManager == nullptr) || (radius <= 0.f)) {
		return springai::AIFloat3(-RgtVector);
	}
	return mapManager->GetWreckField().CommanderWreck(pos, radius);
}

springai::AIFloat3 CCircuitAI::GetBestWreckPos(const springai::AIFloat3& pos, float radius, float minMetal)
{
	if ((mapManager == nullptr) || (radius <= 0.f)) {
		return springai::AIFloat3(-RgtVector);
	}
	return mapManager->GetWreckField().BestWreck(pos, radius, minMetal);
}

springai::AIFloat3 CCircuitAI::GetBestRezPos(const springai::AIFloat3& pos, float radius, float minCost)
{
	if ((mapManager == nullptr) || (radius <= 0.f)) {
		return springai::AIFloat3(-RgtVector);
	}
	return mapManager->GetWreckField().BestRez(pos, radius, minCost);
}

float CCircuitAI::GetFieldWorkAt(const springai::AIFloat3& pos, float radius)
{
	if ((mapManager == nullptr) || (radius <= 0.f)) {
		return .0f;
	}
	return mapManager->GetWreckField().WorkAt(pos, radius);
}

// TOTAL reclaimable metal within radius, not the richest single body.
//
// GetBestWreckPos answers "is there one fat corpse here", which is the wrong
// question after a repelled push: a dozen dead T1s is several hundred metal and
// not one of them is individually large. apexearth: "often its a dozen t1 that
// just died... still its a lot of metal we should be eating".
// A commander corpse is excluded here too -- this feeds the "how rich is this
// field" total that gates whether a constructor gets sent at all, so a
// commander corpse skewing that total high would still walk a con onto it even
// if GetBestWreckPos itself never targets it directly.
float CCircuitAI::GetWreckValueAt(const springai::AIFloat3& pos, float radius)
{
	if ((mapManager == nullptr) || (radius <= 0.f)) {
		return .0f;
	}
	return mapManager->GetWreckField().ValueAt(pos, radius);
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
	// apex: the count is what the engine returns when handed no output buffer,
	// so the wrapper Unit that used to be newed and deleted per enemy here --
	// on a call the commander makes every time it re-reads its own danger --
	// bought nothing.
	const int count = callback->CountEnemyUnitsIn(pos, radius, false);
	perfEcostSweep += count;
	++perfEcostCalls;
	return float(count);
}

// HOW CLOSE THE NEAREST ENEMY IS TO BEING ABLE TO SHOOT THIS SPOT.
// apexearth 2026-09-06, on rez bots: "they should back away when enemy units
// are close to being within range of the rezbots". The margin is his own
// latency bar turned into distance -- whatever ground the enemy covers while we
// notice and start walking is ground we have to be clear of already, so the
// envelope is its weapon reach plus `reactS` seconds of its own speed.
//
// Unarmed and flying enemies are skipped: a scout is not a reason to abandon a
// corpse, and no ground bot outruns a gunship, so treating either as pressure
// only costs work.
int CCircuitAI::GetMetalResId()
{
	if ((metalResId < 0) && (callback != nullptr)) {
		springai::Resource* r = callback->GetResourceByName(RES_NAME_METAL);
		if (r != nullptr) {
			metalResId = r->GetResourceId();
			delete r;
		}
	}
	return metalResId;
}

// apex: the enemy set flattened once per frame. Every caller used to walk the
// enemyInfos hash map and chase four pointers per enemy (node -> CEnemyInfo ->
// SEnemyData -> CCircuitDef) to read two floats, and the rez guard alone runs
// this once per rez bot six times a second while site safety runs it per
// candidate site. Approximate, not exact: an enemy registered part way through
// a frame is seen by the callers after it rather than before.
static constexpr size_t REACH_LEAF = 8;  // below this the tree costs more than the scan

void CCircuitAI::RebuildReachCache()
{
	if (reachCacheFrame == lastFrame) {
		return;
	}
	reachCacheFrame = lastFrame;
	reachCache.clear();
	reachCache.reserve(enemyInfos.size());
	for (const auto& kv : enemyInfos) {
		CEnemyInfo* e = kv.second;
		if ((e == nullptr) || e->IsHidden()) {
			continue;
		}
		CCircuitDef* edef = e->GetCircuitDef();
		if ((edef == nullptr) || edef->IsAbleToFly()) {
			continue;
		}
		// Not GetMaxRange: that is the max over EVERY weapon, so a nuke silo
		// enters the cache with 72000 of "reach" and vetoes the whole map.
		const float reach = edef->GetAutoRange();
		if (reach <= 0.f) {
			continue;
		}
		if (reach > perfReachMax) {
			perfReachMax = reach;
			perfReachMaxDef = edef;
		}
		const springai::AIFloat3& p = e->GetPos();
		reachCache.push_back({p.x, p.z, reach, edef->GetSpeed(),
				(uint32_t)reachCache.size()});
	}
	reachNodes.clear();
	if (reachCache.size() > REACH_LEAF) {
		reachNodes.reserve(reachCache.size() / 2 + 2);  // leaves hold >= 4, so <= n/2 nodes
		BuildReachTree(0, (int32_t)reachCache.size());
	}
}

// apex: median-split BVH over the cache, rebuilt with it, because the flattened
// cache still cost a pass over EVERY enemy per call and `perf sweep reach` was
// the largest counter in the log.
//
// A node carries its box plus the largest reach and speed below it, so
// `boxMinDist - (maxReach + maxSpeed * reactS)` is a lower bound on every slack
// inside and a subtree that cannot beat the running best is skipped whole.
// Answers stay IDENTICAL, not approximate: the bound prunes only what it proves
// cannot win, and each enemy keeps its unsorted index so an exact tie returns
// the same enemy the linear scan did.
int32_t CCircuitAI::BuildReachTree(int32_t first, int32_t count)
{
	const int32_t self = (int32_t)reachNodes.size();
	reachNodes.emplace_back();
	float minx = std::numeric_limits<float>::max();
	float minz = minx;
	float maxx = -minx;
	float maxz = -minx;
	float maxReach = 0.f;
	float maxSpeed = 0.f;
	for (int32_t i = first; i < first + count; ++i) {
		const SReachEnemy& e = reachCache[i];
		minx = std::min(minx, e.x);  maxx = std::max(maxx, e.x);
		minz = std::min(minz, e.z);  maxz = std::max(maxz, e.z);
		maxReach = std::max(maxReach, e.reach);
		maxSpeed = std::max(maxSpeed, e.speed);
	}
	{
		SReachNode& nd = reachNodes[self];
		nd.minx = minx;  nd.minz = minz;  nd.maxx = maxx;  nd.maxz = maxz;
		nd.maxReach = maxReach;  nd.maxSpeed = maxSpeed;
		nd.first = first;  nd.count = count;  nd.right = -1;
	}
	if (count <= (int32_t)REACH_LEAF) {
		return self;
	}
	const int32_t half = count / 2;
	const auto mid = reachCache.begin() + first + half;
	if ((maxx - minx) >= (maxz - minz)) {
		std::nth_element(reachCache.begin() + first, mid, reachCache.begin() + first + count,
				[](const SReachEnemy& a, const SReachEnemy& b) { return a.x < b.x; });
	} else {
		std::nth_element(reachCache.begin() + first, mid, reachCache.begin() + first + count,
				[](const SReachEnemy& a, const SReachEnemy& b) { return a.z < b.z; });
	}
	BuildReachTree(first, half);  // lands at self + 1
	const int32_t r = BuildReachTree(first + half, count - half);
	reachNodes[self].count = 0;
	reachNodes[self].right = r;
	return self;
}

float CCircuitAI::ReachNodeMinDist(int32_t ni, float px, float pz) const
{
	const SReachNode& nd = reachNodes[ni];
	const float dx = std::max(0.f, std::max(nd.minx - px, px - nd.maxx));
	const float dz = std::max(0.f, std::max(nd.minz - pz, pz - nd.maxz));
	return sqrtf(dx * dx + dz * dz);
}

void CCircuitAI::ReachQuery(int32_t ni, float px, float pz, float reactS, float minDist,
		float& worst, uint32_t& bestIdx, const SReachEnemy*& best)
{
	const SReachNode& nd = reachNodes[ni];
	// Strict: an equal bound may still hide a tie with a lower index, and the
	// tie-break is what keeps the answer bit-identical to the old scan.
	if (minDist - (nd.maxReach + nd.maxSpeed * reactS) > worst) {
		return;
	}
	if (nd.count > 0) {
		perfReachSweep += nd.count;
		for (int32_t i = nd.first; i < nd.first + nd.count; ++i) {
			const SReachEnemy& e = reachCache[i];
			const float dx = px - e.x;
			const float dz = pz - e.z;
			const float slack = sqrtf(dx * dx + dz * dz) - (e.reach + e.speed * reactS);
			if ((slack < worst) || ((slack == worst) && (e.idx < bestIdx))) {
				worst = slack;
				bestIdx = e.idx;
				best = &e;
			}
		}
		return;
	}
	const int32_t l = ni + 1;
	const int32_t r = nd.right;
	const float dl = ReachNodeMinDist(l, px, pz);
	const float dr = ReachNodeMinDist(r, px, pz);
	if (dl <= dr) {
		ReachQuery(l, px, pz, reactS, dl, worst, bestIdx, best);
		ReachQuery(r, px, pz, reactS, dr, worst, bestIdx, best);
	} else {
		ReachQuery(r, px, pz, reactS, dr, worst, bestIdx, best);
		ReachQuery(l, px, pz, reactS, dl, worst, bestIdx, best);
	}
}

float CCircuitAI::GetEnemyReachSlack(const springai::AIFloat3& pos, float reactS,
		springai::AIFloat3* foeOut)
{
	RebuildReachCache();
	++perfReachCalls;
	float worst = std::numeric_limits<float>::max();
	uint32_t bestIdx = std::numeric_limits<uint32_t>::max();
	const SReachEnemy* best = nullptr;
	if (reachNodes.empty()) {  // too few to pay for the tree
		perfReachSweep += reachCache.size();
		for (const SReachEnemy& e : reachCache) {
			const float dx = pos.x - e.x;
			const float dz = pos.z - e.z;
			const float slack = sqrtf(dx * dx + dz * dz) - (e.reach + e.speed * reactS);
			if (slack < worst) {
				worst = slack;
				best = &e;
			}
		}
	} else {
		ReachQuery(0, pos.x, pos.z, reactS, ReachNodeMinDist(0, pos.x, pos.z),
				worst, bestIdx, best);
	}
	if ((foeOut != nullptr) && (best != nullptr)) {
		*foeOut = springai::AIFloat3(best->x, 0.f, best->z);
	}
	if (best != nullptr) {
		perfReachWorst = std::min(perfReachWorst, worst);
	}
	return worst;
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

void CCircuitAI::NoteSniperOrder(CCircuitDef::SniperOrder kind)
{
	++sniperOrders[static_cast<int>(kind)];
	if (lastFrame < sniperOrderNextLog) {
		return;
	}
	sniperOrderNextLog = lastFrame + FRAMES_PER_SEC * 30;
	LOG("apex: sniper-orders t=%i f=%i move=%i settarget=%i fight=%i attack=%i",
			teamId, lastFrame, sniperOrders[0], sniperOrders[1], sniperOrders[2], sniperOrders[3]);
	for (int& n : sniperOrders) {
		n = 0;
	}
}

void CCircuitAI::NoteOrder(int kind, int bucket, bool suppressed, int src)
{
	if (suppressed) {
		++ordSup[kind];
	} else {
		++ordSent[kind];
	}
	if (bucket >= 0) {
		++ordRep[kind][bucket];
	}
	if ((src >= 0) && (src < ORD_SRC_N)) {
		++ordSrc[src][0];
		if (bucket >= 0) {
			++ordSrc[src][1];
			if (bucket == 4) {
				++ordSrc[src][2];
			}
		}
	}
}

void CCircuitAI::NoteOrderRefused(int src, int byPrio)
{
	if ((src >= 0) && (src < ORD_SRC_N)) {
		++ordRefused[src];
	}
}

void CCircuitAI::NoteArcFlip(bool held, unsigned units)
{
	++arcFlip[held ? 1 : 0];
	arcFlipU[held ? 1 : 0] += units;
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
	std::string snipers;
	for (const CCircuitDef& cdef : GetCircuitDefs()) {
		if (cdef.IsSniper()) {
			snipers += " " + std::string(cdef.GetDef()->GetName());
		}
	}
	LOG("apex: sniper-class t=%i:%s", teamId, snipers.c_str());
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
