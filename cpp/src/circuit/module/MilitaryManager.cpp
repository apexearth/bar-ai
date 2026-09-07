/*
 * MilitaryManager.cpp
 *
 *  Created on: Sep 5, 2014
 *      Author: rlcevg
 */

#include "module/MilitaryManager.h"
#include "module/BuilderManager.h"
#include "module/EconomyManager.h"
#include "module/FactoryManager.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "resource/MetalManager.h"
#include "scheduler/Scheduler.h"
#include "script/MilitaryScript.h"
#include "setup/SetupManager.h"
#include "setup/DefenceData.h"
#include "task/UnitTask.h"
#include "task/NilTask.h"
#include "task/IdleTask.h"
#include "task/RetreatTask.h"
#include "task/builder/DefenceTask.h"
#include "task/fighter/FighterTask.h"
#include "task/fighter/RallyTask.h"
#include "task/fighter/GuardTask.h"
#include "task/fighter/DefendTask.h"
#include "task/fighter/ScoutTask.h"
#include "task/fighter/RaidTask.h"
#include "task/fighter/AttackTask.h"
#include "task/fighter/BombTask.h"
#include "task/fighter/ArtilleryTask.h"
#include "task/fighter/AntiAirTask.h"
#include "task/fighter/AntiHeavyTask.h"
#include "task/fighter/SupportTask.h"
#include "task/static/SuperTask.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/enemy/EnemyUnit.h"
#include <algorithm>
#include "CircuitAI.h"
#include "util/GameAttribute.h"
#include "util/Utils.h"
#include "util/Profiler.h"
#include "json/json.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Drawer.h"
#include "Log.h"

namespace circuit {

using namespace springai;
using namespace terrain;

CMilitaryManager::CMilitaryManager(CCircuitAI* circuit)
		: ITaskModule(circuit, new CMilitaryScript(circuit->GetScriptManager(), this))
		, defenceIdx(0)
		, defStand(-RgtVector)
		, defStandFrame(-1)
		, isEnemyFound(false)
		, armyCost(0.f)
		, bigGunDef(nullptr)
{
	circuit->GetScheduler()->RunOnInit(CScheduler::GameJob(&CMilitaryManager::Init, this));

	defence = circuit->GetAllyTeam()->GetDefenceData().get();

	fightTasks.resize(static_cast<IFighterTask::FT>(IFighterTask::FightType::_SIZE_));
}

CMilitaryManager::~CMilitaryManager()
{
}

#if CIRCUIT_TASK_REGISTRY
namespace {
// True when `task` is not a live object, in which case the caller must avoid
// EVERY dereference of it -- the vtable fetch is the fault. Nothing here reads
// *task: the names come from what the registry recorded while it was alive.
bool IsTaskStale(CCircuitAI* circuit, CCircuitUnit* unit, const IUnitTask* task,
		const char* at)
{
	const IUnitTask::SLiveness live = IUnitTask::Probe(task);
	if (live.live) {
		return false;
	}
	static int staleHits = 0;  // AI event path is single-threaded
	const int n = ++staleHits;
	if ((n <= 20) || (n % 100 == 0)) {
		const int frame = circuit->GetLastFrame();
		circuit->LOG("apex STALETASK: at=%s unit=%s id=%i taskFrame=%i frame=%i"
				" age=%i task=%p lastType=%s/%s known=%i hits=%i",
				at, unit->GetCircuitDef()->GetDef()->GetName(), unit->GetId(),
				unit->GetTaskFrame(), frame, frame - unit->GetTaskFrame(),
				(const void*)task, IUnitTask::TypeName(live.type),
				(live.type == IUnitTask::Type::FIGHTER)
						? IFighterTask::FightTypeName(live.sub) : "-",
				int(live.known), n);
	}
	return true;
}
} // namespace
#endif

void CMilitaryManager::InitHandlers()
{
	/*
	 * Attacker handlers
	 */
	auto attackerCreatedHandler = [this](CCircuitUnit* unit, CCircuitUnit* builder) {
		if (unit->GetTask() == nullptr) {
			unit->SetManager(this);
			nilTask->AssignTo(unit);
			this->circuit->AddActionUnit(unit);
		}
	};
	auto attackerFinishedHandler = [this](CCircuitUnit* unit) {
		if (unit->GetTask() == nullptr) {
			unit->SetManager(this);
			this->circuit->AddActionUnit(unit);
		}
		nilTask->RemoveAssignee(unit);
		idleTask->AssignTo(unit);

		army.insert(unit);
		AddArmyCost(unit);

		TRY_UNIT(this->circuit, unit,
			if (unit->GetCircuitDef()->IsAbleToFly()) {
				if (unit->GetCircuitDef()->IsAttrNoStrafe()) {
					unit->CmdAirStrafe(0);
				}
				if (unit->GetCircuitDef()->IsRoleMine()) {
					unit->GetUnit()->SetIdleMode(1);
				}
			}
			if (unit->GetCircuitDef()->IsAttrStock()) {
				unit->GetUnit()->Stockpile(UNIT_COMMAND_OPTION_SHIFT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY);
				unit->CmdMiscPriority(2);
				stockpilers.insert(unit);
			}
		)

		UnitAdded(unit, UseAs::COMBAT);
	};
	auto attackerIdleHandler = [this](CCircuitUnit* unit) {
		// NOTE: Avoid instant task reassignment, though it may be not relevant for attackers
		if (this->circuit->GetLastFrame() > unit->GetTaskFrame()/* + FRAMES_PER_SEC*/) {
			IUnitTask* task = unit->GetTask();
#if CIRCUIT_TASK_REGISTRY
			if (IsTaskStale(this->circuit, unit, task, "idle")) {
				return;  // survive and keep logging, instead of faulting on the vtable
			}
#endif
			task->OnUnitIdle(unit);
		}
	};
	auto attackerDamagedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		IUnitTask* task = unit->GetTask();
#if CIRCUIT_TASK_REGISTRY
		if (IsTaskStale(this->circuit, unit, task, "damaged")) {
			return;  // nothing to unwind here; the handler only forwards
		}
#endif
		task->OnUnitDamaged(unit, attacker);
	};
	auto attackerDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		IUnitTask* task = unit->GetTask();
#if CIRCUIT_TASK_REGISTRY
		if (IsTaskStale(this->circuit, unit, task, "destroyed")) {
			// Skip the two task calls and the NIL test -- all three read *task.
			// The accounting below still has to run: attackerCreatedHandler
			// already did AddArmyCost/army.insert for this unit, and the NIL
			// branch only fires when OnUnitDestroyed changed the task, which
			// cannot have happened when it was never called. Returning early
			// instead would leave army cost inflated for the rest of the game.
			DelArmyCost(unit);
			army.erase(unit);
			if (unit->GetCircuitDef()->IsAttrStock()) {
				stockpilers.erase(unit);
			}
			UnitRemoved(unit, UseAs::COMBAT);
			return;
		}
#endif
		task->OnUnitDestroyed(unit, attacker);  // can change task
		unit->GetTask()->RemoveAssignee(unit);  // Remove unit from IdleTask

		if (task->GetType() == IUnitTask::Type::NIL) {
			return;
		}

		DelArmyCost(unit);
		army.erase(unit);

		if (unit->GetCircuitDef()->IsAttrStock()) {
			stockpilers.erase(unit);
		}

		UnitRemoved(unit, UseAs::COMBAT);
	};

	/*
	 * Regular defence handlers: for units not in STOCK or SUPER but with FENCE attribute
	 */
	auto fenceFinishedHandler = [this](CCircuitUnit* unit) {
		fencePos[unit] = unit->GetPos(this->circuit->GetLastFrame());
		defStandFrame = -1;
		UnitAdded(unit, UseAs::FENCE);
	};
	auto fenceDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		fencePos.erase(unit);
		defStandFrame = -1;
		UnitRemoved(unit, UseAs::FENCE);
	};

	/*
	 * Stockpile handlers: for units with STOCK attribute but not SUPER
	 */
	auto stockFinishedHandler = [this](CCircuitUnit* unit) {
		TRY_UNIT(this->circuit, unit,
			unit->GetUnit()->Stockpile(UNIT_COMMAND_OPTION_SHIFT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY);
			stockpilers.insert(unit);
		)

		UnitAdded(unit, UseAs::STOCK);
	};
	auto stockDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		stockpilers.erase(unit);

		UnitRemoved(unit, UseAs::STOCK);
	};

	/*
	 * Superweapon handlers
	 */
	auto superCreatedHandler = [this](CCircuitUnit* unit, CCircuitUnit* builder) {
		if (unit->GetTask() == nullptr) {
			unit->SetManager(this);
			nilTask->AssignTo(unit);
			this->circuit->AddActionUnit(unit);
		}
	};
	auto superFinishedHandler = [this](CCircuitUnit* unit) {
		if (unit->GetTask() == nullptr) {
			unit->SetManager(this);
			this->circuit->AddActionUnit(unit);
		}
		nilTask->RemoveAssignee(unit);
		idleTask->AssignTo(unit);

		TRY_UNIT(this->circuit, unit,
			unit->GetUnit()->SetTrajectory(1);
			if (unit->GetCircuitDef()->IsAttrStock()) {
				unit->GetUnit()->Stockpile(UNIT_COMMAND_OPTION_SHIFT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY);
				unit->CmdMiscPriority(2);
				stockpilers.insert(unit);
			}
		)

		UnitAdded(unit, UseAs::SUPER);
	};
	auto superDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		IUnitTask* task = unit->GetTask();
		task->OnUnitDestroyed(unit, attacker);  // can change task
		unit->GetTask()->RemoveAssignee(unit);  // Remove unit from IdleTask

		if (unit->GetCircuitDef()->IsAttrStock()) {
			stockpilers.erase(unit);
		}

		UnitRemoved(unit, UseAs::SUPER);
	};

	/*
	 * Defend buildings handler
	 */
//	auto structDamagedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
//		const std::set<IFighterTask*>& tasks = GetTasks(IFighterTask::FightType::DEFEND);
//		if (tasks.empty()) {
//			return;
//		}
//		int frame = this->circuit->GetLastFrame();
//		const AIFloat3& pos = unit->GetPos(frame);
//		CTerrainManager* terrainMgr = this->circuit->GetTerrainManager();
//		CDefendTask* defendTask = nullptr;
//		float minSqDist = std::numeric_limits<float>::max();
//		for (IFighterTask* task : tasks) {
//			CDefendTask* dt = static_cast<CDefendTask*>(task);
//			const float sqDist = pos.SqDistance2D(dt->GetPosition());
//			if ((minSqDist <= sqDist) || !terrainMgr->CanMoveToPos(dt->GetLeader()->GetArea(), pos)) {
//				continue;
//			}
//			if ((dt->GetTarget() == nullptr) ||
//				(dt->GetTarget()->GetPos().SqDistance2D(dt->GetLeader()->GetPos(frame)) > sqDist))
//			{
//				minSqDist = sqDist;
//				defendTask = dt;
//			}
//		}
//		if (defendTask != nullptr) {
//			defendTask->SetPosition(pos);
//			defendTask->SetWantedTarget(attacker);
//		}
//	};

	// NOTE: IsRole used below
	ReadConfig();

	const Json::Value& root = circuit->GetSetupManager()->GetConfig();
	const Json::Value& retreat = root["retreat"]["fighter"];
	const float minRet = retreat.get((unsigned)0, 0.5f).asFloat();
	const float maxRet = retreat.get((unsigned)1, 0.5f).asFloat();
	const float fighterRet = (float)rand() / RAND_MAX * (maxRet - minRet) + minRet;
	const float retMod = retreat.get((unsigned)2, 1.0f).asFloat();
	const float commMod = root["quota"]["thr_mod"].get("comm", 1.f).asFloat();
	std::vector<CCircuitDef*> builders;

	for (CCircuitDef& cdef : circuit->GetCircuitDefs()) {
		if (cdef.IsBuilder()) {
			builders.push_back(&cdef);
		}

		CCircuitDef::Id unitDefId = cdef.GetId();
		if (cdef.IsRoleComm()) {
			cdef.ModDefThreat(commMod);
			for (CCircuitDef::RoleT role = 0; role < CMaskHandler::GetMaxMasks(); ++role) {
				cdef.ModThreatMod(role, commMod);
			}
			cdef.ModPower(commMod);
		}
		if (cdef.GetDef()->IsBuilder() && (cdef.IsBuilder() || cdef.IsAbleToResurrect())) {
//			damagedHandler[unitDefId] = structDamagedHandler;
			continue;
		}
		const std::map<std::string, std::string>& customParams = cdef.GetDef()->GetCustomParams();
		auto it = customParams.find("is_drone");
		if ((it != customParams.end()) && (utils::string_to_int(it->second) == 1)) {
			continue;
		}
		if (cdef.IsMobile()) {
			createdHandler[unitDefId] = attackerCreatedHandler;
			finishedHandler[unitDefId] = attackerFinishedHandler;
			idleHandler[unitDefId] = attackerIdleHandler;
			damagedHandler[unitDefId] = attackerDamagedHandler;
			destroyedHandler[unitDefId] = attackerDestroyedHandler;

			cdef.SetRetreat((cdef.GetRetreat() < 0.f) ? fighterRet : cdef.GetRetreat() * retMod);
		} else {
//			damagedHandler[unitDefId] = structDamagedHandler;
			if (cdef.IsRoleSuper()) {
				if (cdef.IsAttacker()) {
					createdHandler[unitDefId] = superCreatedHandler;
					finishedHandler[unitDefId] = superFinishedHandler;
					destroyedHandler[unitDefId] = superDestroyedHandler;
				}
			} else if (cdef.IsAttrStock()) {
				finishedHandler[unitDefId] = stockFinishedHandler;
				destroyedHandler[unitDefId] = stockDestroyedHandler;
			} else if (cdef.IsAttrFence()) {
				finishedHandler[unitDefId] = fenceFinishedHandler;
				destroyedHandler[unitDefId] = fenceDestroyedHandler;
			}
			if (cdef.GetDef()->GetRadarRadius() > 1.f) {
				radarDefs.AddDef(&cdef);
				cdef.SetIsRadar(true);
			}
			if (cdef.GetDef()->GetJammerRadius() > 1.f) {
				cdef.SetIsJammer(true);
			}
			if (cdef.GetDef()->GetSonarRadius() > 1.f) {
				sonarDefs.AddDef(&cdef);
				cdef.SetIsSonar(true);
			}
		}
	}

	InitEconomyScores(std::move(builders));
}

void CMilitaryManager::ReadConfig()
{
	const Json::Value& root = circuit->GetSetupManager()->GetConfig();
	const std::string& cfgName = circuit->GetSetupManager()->GetConfigName();
	CCircuitDef::RoleName& roleNames = CCircuitDef::GetRoleNames();

	const Json::Value& responses = root["response"];
	const float reImpMod = responses.get("_importance_mod_", 1.f).asFloat();
	const float teamSize = circuit->GetAllyTeam()->GetSize();
	roleInfos.resize(roleNames.size(), {.0f});
	for (const auto& pair : roleNames) {
		SRoleInfo& info = roleInfos[pair.second.type];
		const Json::Value& response = responses[pair.first];

		if (response.isNull()) {
			info.maxPerc = 1.0f;
			info.factor  = teamSize;
			continue;
		}

		info.maxPerc = response.get("max_percent", 1.0f).asFloat();
		const float step = response.get("eps_step", 1.0f).asFloat();
		info.factor  = (teamSize - 1.0f) * step + 1.0f;

		const Json::Value& vs = response["vs"];
		const Json::Value& ratio = response["ratio"];
		const Json::Value& importance = response["importance"];
		for (unsigned i = 0; i < vs.size(); ++i) {
			const std::string& roleName = vs[i].asString();
			auto it = roleNames.find(roleName);
			if (it == roleNames.end()) {
				circuit->LOG("CONFIG %s: response %s vs unknown role '%s'", cfgName.c_str(), pair.first.c_str(), roleName.c_str());
				continue;
			}
			float rat = ratio.get(i, 1.0f).asFloat();
			float imp = importance.get(i, 1.0f).asFloat() * reImpMod;
			info.vs.push_back(SRoleInfo::SVsInfo(it->second.type, rat, imp));
		}
	}

	const Json::Value& quotas = root["quota"];
	maxScouts = quotas.get("scout", 3).asUInt();
	const Json::Value& qraid = quotas["raid"];
	raid.min = qraid.get((unsigned)0, 3.f).asFloat();
	raid.avg = qraid.get((unsigned)1, 5.f).asFloat();
	minAttackers = quotas.get("attack", 8.f).asFloat();
	const Json::Value& qthrMod = quotas["thr_mod"];
	const Json::Value& qthrAtk = qthrMod["attack"];
	attackMod.min = qthrAtk.get((unsigned)0, 1.f).asFloat();
	attackMod.len = qthrAtk.get((unsigned)1, 1.f).asFloat() - attackMod.min;
	const Json::Value& qthrDef = qthrMod["defence"];
	defenceMod.min = qthrDef.get((unsigned)0, 1.f).asFloat();
	defenceMod.len = qthrDef.get((unsigned)1, 1.f).asFloat() - defenceMod.min;

	const Json::Value& adaptive_threat_range = root["adaptive_threat_range"];
	threatRangeScaling.enemyCountPerEnemyTeamToStartScaling = adaptive_threat_range.get("enemy_count_per_team_to_start_scaling", 50).asInt();
	threatRangeScaling.enemyCountPerEnemyTeamToEndScaling = adaptive_threat_range.get("enemy_count_per_team_to_end_scaling", 300).asInt();
	threatRangeScaling.endScaleValue = adaptive_threat_range.get("end_scale_value", -1.0f).asFloat();

	const Json::Value& porc = root["porcupine"];
	preventCount = porc.get("prevent", 1).asUInt();
	const Json::Value& amount = porc["amount"];
	const Json::Value& amOff = amount["offset"];
	const Json::Value& amFac = amount["factor"];
	const Json::Value& amMap = amount["map"];
	const float minOffset = amOff.get((unsigned)0, -0.2f).asFloat();
	const float maxOffset = amOff.get((unsigned)1, 0.2f).asFloat();
	const float offset = (float)rand() / RAND_MAX * (maxOffset - minOffset) + minOffset;
	const float minFactor = amFac.get((unsigned)0, 2.0f).asFloat();
	const float maxFactor = amFac.get((unsigned)1, 1.0f).asFloat();
	const float minMap = amMap.get((unsigned)0, 8.0f).asFloat();
	const float maxMap = amMap.get((unsigned)1, 24.0f).asFloat();
	const float mapSize = (circuit->GetMap()->GetWidth() / 64) * (circuit->GetMap()->GetHeight() / 64);
	amountFactor = (maxFactor - minFactor) / (SQUARE(maxMap) - SQUARE(minMap)) * (mapSize - SQUARE(minMap)) + minFactor + offset;
//	amountFactor = std::max(amountFactor, 0.f);

	CMaskHandler& sideMasker = circuit->GetGameAttribute()->GetSideMasker();
	sideInfos.resize(sideMasker.GetMasks().size());
	for (const auto& kv : sideMasker.GetMasks()) {
		SSideInfo& sideInfo = sideInfos[kv.second.type];
		const Json::Value& defs = porc["unit"][kv.first];
		std::vector<CCircuitDef*> defenderDefs;
		defenderDefs.reserve(defs.size());
		for (const Json::Value& def : defs) {
			CCircuitDef* cdef = circuit->GetCircuitDef(def.asCString());
			if (cdef == nullptr) {
				circuit->LOG("CONFIG %s: has unknown UnitDef '%s'", cfgName.c_str(), def.asCString());
			} else {
				cdef->AddAttribute(ATTR_TYPE(FENCE));
				defenderDefs.push_back(cdef);
			}
		}
		const Json::Value& land = porc["land"];
		sideInfo.landDefenders.reserve(land.size());
		for (const Json::Value& idx : land) {
			unsigned index = idx.asUInt();
			if (index < defenderDefs.size()) {
				sideInfo.landDefenders.push_back(defenderDefs[index]);
			}
		}
		const Json::Value& watr = porc["water"];
		sideInfo.waterDefenders.reserve(watr.size());
		for (const Json::Value& idx : watr) {
			unsigned index = idx.asUInt();
			if (index < defenderDefs.size()) {
				sideInfo.waterDefenders.push_back(defenderDefs[index]);
			}
		}

		const Json::Value& base = porc["base"];
		sideInfo.baseDefence.reserve(base.size());
		for (const Json::Value& pair : base) {
			unsigned index = pair.get((unsigned)0, -1).asUInt();
			if (index >= defenderDefs.size()) {
				continue;
			}
			int frame = pair.get((unsigned)1, 0).asInt() * FRAMES_PER_SEC;
			sideInfo.baseDefence.emplace_back(defenderDefs[index], frame);
		}
		auto compare = [](const std::pair<CCircuitDef*, int>& d1, const std::pair<CCircuitDef*, int>& d2) {
			return d1.second > d2.second;
		};
		std::sort(sideInfo.baseDefence.begin(), sideInfo.baseDefence.end(), compare);

		const Json::Value& super = porc["superweapon"];
		const Json::Value& items = super["unit"][kv.first];
		const Json::Value& probs = super["weight"];
		sideInfo.superInfos.reserve(items.size());
		for (unsigned i = 0; i < items.size(); ++i) {
			CCircuitDef* cdef = circuit->GetCircuitDef(items[i].asCString());
			if (cdef == nullptr) {
				circuit->LOG("CONFIG %s: has unknown UnitDef '%s'", cfgName.c_str(), items[i].asCString());
				continue;
			}
			cdef->SetMainRole(ROLE_TYPE(SUPER));  // override mainRole
			cdef->AddEnemyRole(ROLE_TYPE(SUPER));
			cdef->AddRole(ROLE_TYPE(SUPER));
			const float weight = probs.get(i, 1.f).asFloat();
			sideInfo.superInfos.emplace_back(cdef, weight);
		}

		const Json::Value& walls = porc["wall"][kv.first];
		sideInfo.wallDefs.reserve(walls.size());
		for (unsigned i = 0; i < walls.size(); ++i) {
			CCircuitDef* cdef = circuit->GetCircuitDef(walls[i].asCString());
			if (cdef == nullptr) {
				circuit->LOG("CONFIG %s: has unknown UnitDef '%s'", cfgName.c_str(), walls[i].asCString());
				continue;
			}
			sideInfo.wallDefs.push_back(cdef);
		}
		const Json::Value& chokes = porc["choke"][kv.first];
		sideInfo.chokeDefs.reserve(chokes.size());
		for (unsigned i = 0; i < chokes.size(); ++i) {
			CCircuitDef* cdef = circuit->GetCircuitDef(chokes[i].asCString());
			if (cdef == nullptr) {
				circuit->LOG("CONFIG %s: has unknown UnitDef '%s'", cfgName.c_str(), chokes[i].asCString());
				continue;
			}
			sideInfo.chokeDefs.push_back(cdef);
		}

		const std::string& defName = porc["default"].get(kv.first, "").asString();
		sideInfo.defaultPorc = circuit->GetCircuitDef(defName.c_str());
		if (sideInfo.defaultPorc == nullptr) {
			sideInfo.defaultPorc = circuit->GetEconomyManager()->GetSideInfos()[kv.second.type].defaultDef;
		}
	}
}

void CMilitaryManager::InitEconomyScores(const std::vector<CCircuitDef*>&& builders)
{
	auto scoreFunc = [](CCircuitDef* cdef, const SSensorExt& data) {
		return M_PI * SQUARE(data.radius) / cdef->GetCostM();  // area / cost
//		return data.radius - cdef->GetCostM() * 0.1f;  // absolutely no physical meaning
	};
	radarDefs.Init(builders, [scoreFunc](CCircuitDef* cdef, SSensorExt& data) {
		data.radius = cdef->GetDef()->GetRadarRadius();
		return scoreFunc(cdef, data);
	});
	sonarDefs.Init(builders, [scoreFunc](CCircuitDef* cdef, SSensorExt& data) {
		data.radius = cdef->GetDef()->GetSonarRadius();
		return scoreFunc(cdef, data);
	});
}

void CMilitaryManager::Init()
{
	CMetalManager* metalMgr = circuit->GetMetalManager();
	const CMetalData::Clusters& clusters = metalMgr->GetClusters();

	scoutPoints.resize(clusters.size(), SScoutPoint{0, 0, 0, 0, nullptr});

	CSetupManager::StartFunc subinit = [this, &clusters](const AIFloat3& pos) {
		std::vector<int> sortedIdxs;
		sortedIdxs.reserve(scoutPoints.size());
		for (unsigned int i = 0; i < scoutPoints.size(); ++i) {
			sortedIdxs.push_back(i);
		}
		std::sort(sortedIdxs.begin(), sortedIdxs.end(), [&pos, &clusters](int a, int b) {
			return pos.SqDistance2D(clusters[a].position) > pos.SqDistance2D(clusters[b].position);
		});
		for (unsigned int i = 0; i < scoutPoints.size(); ++i) {
			scoutPoints[sortedIdxs[i]].scouted = i;  // enforce scouting distant areas first
		}

		DiceBigGun();

		CScheduler* scheduler = circuit->GetScheduler().get();
		const int interval = 4;
		const int offset = circuit->GetSkirmishAIId() % interval;
		scheduler->RunJobEvery(CScheduler::GameJob(&CMilitaryManager::UpdateIdle, this), interval, offset + 0, "milIdle");
		scheduler->RunJobEvery(CScheduler::GameJob(&CMilitaryManager::Update, this), 1/*interval / 2*/, offset + 1, "milUpd");
		scheduler->RunJobEvery(CScheduler::GameJob(&CMilitaryManager::UpdateDefenceTasks, this), FRAMES_PER_SEC * 5, offset + 2, "milDef");
		scheduler->RunJobEvery(CScheduler::GameJob(&CMilitaryManager::DispatchRaids, this), FRAMES_PER_SEC * 2, offset + 3, "milRaid");

		scheduler->RunJobEvery(CScheduler::GameJob(&CMilitaryManager::Watchdog, this),
								FRAMES_PER_SEC * 60,
								circuit->GetSkirmishAIId() * WATCHDOG_COUNT + 12, "wdog");
	};

	circuit->GetSetupManager()->ExecOnFindStart(subinit);
}

int CMilitaryManager::UnitCreated(CCircuitUnit* unit, CCircuitUnit* builder)
{
	auto search = createdHandler.find(unit->GetCircuitDef()->GetId());
	if (search != createdHandler.end()) {
		search->second(unit, builder);
	}

	return 0; //signaling: OK
}

int CMilitaryManager::UnitFinished(CCircuitUnit* unit)
{
	auto search = finishedHandler.find(unit->GetCircuitDef()->GetId());
	if (search != finishedHandler.end()) {
		search->second(unit);
	}

	return 0; //signaling: OK
}

int CMilitaryManager::UnitIdle(CCircuitUnit* unit)
{
	auto search = idleHandler.find(unit->GetCircuitDef()->GetId());
	if (search != idleHandler.end()) {
		search->second(unit);
	}

	return 0; //signaling: OK
}

int CMilitaryManager::UnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	auto search = damagedHandler.find(unit->GetCircuitDef()->GetId());
	if (search != damagedHandler.end()) {
		search->second(unit, attacker);
	}

	return 0; //signaling: OK
}

int CMilitaryManager::UnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	if (unit->GetCircuitDef()->IsAttrFence()) {
		UnmarkPorc(unit);
	}

	auto itgt = guardTasks.find(unit);
	if (itgt != guardTasks.end()) {
		// Drop the entry BEFORE aborting: the abort path re-enters DequeueTask,
		// and leaving the mapping live across that gave a second route to the
		// same dangling pointer.
		CFGuardTask* guard = itgt->second;
		guardTasks.erase(itgt);
		AbortTask(guard);
	}

	auto search = destroyedHandler.find(unit->GetCircuitDef()->GetId());
	if (search != destroyedHandler.end()) {
		search->second(unit, attacker);
	}

	return 0; //signaling: OK
}

IFighterTask* CMilitaryManager::Enqueue(const TaskF::SFightTask& ti)
{
	IFighterTask* task;

	switch (ti.type) {
		default:
		case IFighterTask::FightType::RALLY: {
//			CEconomyManager* economyMgr = circuit->GetEconomyManager();
//			float power = economyMgr->GetAvgMetalIncome() * economyMgr->GetEcoFactor() * 32.0f;
			task = new CRallyTask(this, /*power*/1);  // TODO: pass enemy's threat
		} break;
		case IFighterTask::FightType::GUARD: {
			auto it = guardTasks.find(ti.vip);
			if (it != guardTasks.end()) {
				return it->second;
			}
			task = new CFGuardTask(this, ti.vip, 1.0f);
		} break;
		case IFighterTask::FightType::DEFEND: {
			// The massing pool waits at this position and CDefendTask::Start sends
			// every new assignee to it. At the base centre that is the whole army
			// standing behind its own buildings; on the tower line it is the army
			// standing with them.
			AIFloat3 pos = GetDefenceStand();
			if (!utils::is_valid(pos)) {
				pos = circuit->GetSetupManager()->GetBasePos();
			}
			if (ti.check == IFighterTask::FightType::_SIZE_) {
				const float mod = (float)rand() / RAND_MAX * defenceMod.len + defenceMod.min;
				task = new CDefendTask(this, pos, ti.promote, ti.promote, ti.power, 1.0f / mod);
			} else {
				task = new CDefendTask(this, pos, ti.check, ti.promote, ti.power, 1.0f);
			}
		} break;
		case IFighterTask::FightType::SCOUT: {
			const float mod = (float)rand() / RAND_MAX * attackMod.len + attackMod.min;
			task = new CScoutTask(this, 0.75f / mod);
		} break;
		case IFighterTask::FightType::RAID: {
			const float mod = (float)rand() / RAND_MAX * attackMod.len + attackMod.min;
			task = new CRaidTask(this, raid.avg, 0.75f / mod);
		} break;
		case IFighterTask::FightType::ATTACK: {
			const float mod = (float)rand() / RAND_MAX * attackMod.len + attackMod.min;
			task = new CAttackTask(this, minAttackers, 0.8f / mod);
		} break;
		case IFighterTask::FightType::BOMB: {
			const float mod = (float)rand() / RAND_MAX * attackMod.len + attackMod.min;
			task = new CBombTask(this, 2.0f / mod);
		} break;
		case IFighterTask::FightType::ARTY: {
			task = new CArtilleryTask(this);
		} break;
		case IFighterTask::FightType::AA: {
			const float mod = (float)rand() / RAND_MAX * attackMod.len + attackMod.min;
			task = new CAntiAirTask(this, 1.0f / mod);
		} break;
		case IFighterTask::FightType::AH: {
			const float mod = (float)rand() / RAND_MAX * attackMod.len + attackMod.min;
			task = new CAntiHeavyTask(this, 2.0f / mod);
		} break;
		case IFighterTask::FightType::SUPPORT: {
			task = new CSupportTask(this);
		} break;
		case IFighterTask::FightType::SUPER: {
			task = new CSuperTask(this);
		} break;
	}

	fightTasks[static_cast<IFighterTask::FT>(ti.type)].insert(task);
	PushUpdate(task);
	TaskAdded(task);
	return task;
}

// apex: see the header for why this lives on the manager rather than the task.
// SUPER_MEMORY is a little over one Armageddon reload (120s stockpile), long
// enough that a second silo picks a different target rather than confirming the
// first one's answer.
#define SUPER_MEMORY	(FRAMES_PER_SEC * 150)

void CMilitaryManager::NoteSuperTarget(const AIFloat3& pos, int frame)
{
	for (SSuperShot& shot : superShots) {
		if (shot.frame + SUPER_MEMORY <= frame) {
			shot.pos = pos;
			shot.frame = frame;
			return;
		}
	}
	superShots.push_back(SSuperShot{pos, frame});
}

bool CMilitaryManager::IsRecentSuperTarget(const AIFloat3& pos, float sqRadius, int frame) const
{
	for (const SSuperShot& shot : superShots) {
		if ((shot.frame + SUPER_MEMORY > frame) && (shot.pos.SqDistance2D(pos) < sqRadius)) {
			return true;
		}
	}
	return false;
}

CRetreatTask* CMilitaryManager::EnqueueRetreat()
{
	CRetreatTask* task = new CRetreatTask(this);
	PushUpdate(task);
	TaskAdded(task);
	return task;
}

void CMilitaryManager::DequeueTask(IUnitTask* task, bool done)
{
	switch (task->GetType()) {
		case IUnitTask::Type::FIGHTER: {
			IFighterTask* taskF = static_cast<IFighterTask*>(task);
			fightTasks[static_cast<IFighterTask::FT>(taskF->GetFightType())].erase(taskF);
			if (taskF->GetFightType() == IFighterTask::FightType::GUARD) {
				// Erase by VALUE, not by a unit lookup. GetTeamUnit() returns
				// nullptr once the VIP has been unregistered, so erase(nullptr)
				// removed nothing and left an entry keyed by a freed
				// CCircuitUnit*. When the allocator reused that address for a
				// new unit, UnitDestroyed's guardTasks.find(unit) hit the stale
				// entry and called AbortTask on an already-deleted task --
				// task->Dead() then dispatched through a garbage vtable.
				for (auto it = guardTasks.begin(); it != guardTasks.end(); ) {
					it = (it->second == taskF) ? guardTasks.erase(it) : std::next(it);
				}
			}
		} break;
		default: break;
	}
	ITaskModule::DequeueTask(task, done);
}

void CMilitaryManager::MakeDefence(const AIFloat3& pos)
{
	int index = circuit->GetMetalManager()->FindNearestCluster(pos);
	if (index >= 0) {
		MakeDefence(index, pos);
	}
}

void CMilitaryManager::MakeDefence(int cluster)
{
	MakeDefence(cluster, circuit->GetMetalManager()->GetClusters()[cluster].position);
}

void CMilitaryManager::MakeDefence(int cluster, const AIFloat3& pos)
{
	static_cast<CMilitaryScript*>(script)->MakeDefence(cluster, pos);  // DefaultMakeDefence
}

void CMilitaryManager::DefaultMakeDefence(int cluster, const AIFloat3& pos)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return;
}

void CMilitaryManager::MakeSensors(const AIFloat3& backPos, float maxCost, float radiusMod, bool isWater)
{
	const int frame = circuit->GetLastFrame();
	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();

	auto checkSensor = [this, frame, maxCost, &backPos, builderMgr, terrainMgr](IBuilderTask::BuildType type,
			CCircuitDef* cdef, float range, std::function<bool (CCircuitDef*)> isSensor)
	{
		if (!cdef->IsAvailable(frame) || (cdef->GetCostM() > maxCost) || !terrainMgr->CanBeBuiltAt(cdef, backPos)) {
			return false;
		}
		COOAICallback* clb = circuit->GetCallback();
		const auto& friendlies = clb->GetFriendlyUnitIdsIn(backPos, range);
		for (int auId : friendlies) {
			CCircuitDef::Id defId = clb->Unit_GetDefId(auId);
			if (isSensor(circuit->GetCircuitDef(defId))) {
				return true;
			}
		}
		const float qdist = SQUARE(range);
		for (const IBuilderTask* t : builderMgr->GetTasks(type)) {
			if (backPos.SqDistance2D(t->GetTaskPos()) < qdist) {
				return true;
			}
		}
		builderMgr->Enqueue(TaskB::Common(type, IBuilderTask::Priority::NORMAL, cdef, backPos));
		return true;
	};
	// radar
	if (radarDefs.HasAvail()) {
		radarDefs.GetBestDef([&checkSensor, radiusMod](CCircuitDef* cdef, const SSensorExt& data) {
			return checkSensor(IBuilderTask::BuildType::RADAR, cdef, data.radius * radiusMod,
					[](CCircuitDef* cdef) { return cdef->IsRadar(); });
		});
	}
	// sonar
	if (isWater && sonarDefs.HasAvail()) {
		sonarDefs.GetBestDef([&checkSensor](CCircuitDef* cdef, const SSensorExt& data) {
			return checkSensor(IBuilderTask::BuildType::SONAR, cdef, data.radius,
					[](CCircuitDef* cdef) { return cdef->IsSonar(); });
		});
	}
}

void CMilitaryManager::DefaultMakeSensors(int cluster, const AIFloat3& pos)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return;
}

void CMilitaryManager::MarkPorc(CCircuitUnit* unit, int defPointId)
{
	porcToPoint[unit] = defPointId;
}

void CMilitaryManager::UnmarkPorc(CCircuitUnit* unit)
{
	auto it = porcToPoint.find(unit);
	if (it == porcToPoint.end()) {
		return;
	}
	defence->GetDefPoint(it->second)->cost -= unit->GetCircuitDef()->GetCostM();
	porcToPoint.erase(it);
}

void CMilitaryManager::AbortDefence(const CBDefenceTask* task, int defPointId)
{
	float defCost = task->GetBuildDef()->GetCostM();
	CDefenceData::SDefPoint* point = (defPointId < 0)
			? defence->GetDefPoint(task->GetPosition(), defCost)
			: defence->GetDefPoint(defPointId);
	if (point == nullptr) {
		return;
	}
	if ((task->GetTarget() == nullptr) && (point->cost >= defCost)) {
		point->cost -= defCost;
	}
	IBuilderTask* next = task->GetNextTask();
	while (next != nullptr) {
		defCost = (next->GetBuildDef() != nullptr) ? next->GetBuildDef()->GetCostM() : next->GetCostM();
		if (point->cost >= defCost) {
			point->cost -= defCost;
		}
		next = next->GetNextTask();
	}
}

bool CMilitaryManager::HasDefence(int cluster)
{
	const CDefenceData::DefPoints& points = defence->GetDefPoints();
	const CDefenceData::DefIndices& indices = defence->GetDefIndices(cluster);
	for (int idx : indices) {
		if (points[idx].cost > .5f) {
			return true;
		}
	}
	return false;
}

void CMilitaryManager::ProcessHubDefence(CBDefenceTask* task)
{
	const AIFloat3& pos = task->GetPosition();
	CDefenceData::SDefPoint* closestPoint = FindClosestDefPoint(pos);
	if ((closestPoint == nullptr) || (closestPoint->position.SqDistance2D(pos) > SQUARE(300.f))) {
		return;
	}
	closestPoint->cost += task->GetCostM();
	task->SetDefPointId(closestPoint->id);
}

AIFloat3 CMilitaryManager::GetScoutPosition(CCircuitUnit* unit)
{
	ClearScoutPosition(unit->GetTask());
	CMetalManager* metalMgr = circuit->GetMetalManager();
	const CMetalData::Clusters& clusters = metalMgr->GetClusters();
	const CMetalData::Metals& spots = metalMgr->GetSpots();
	const AIFloat3& pos = unit->GetPos(circuit->GetLastFrame());
	SArea* area = unit->GetArea();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	threatMap->SetThreatType(unit);
	auto canMoveTo = [&](const CMetalData::SCluster& cluster) {
		for (size_t idx : cluster.idxSpots) {
			if (terrainMgr->CanMoveToPos(area, spots[idx].position)
				&& threatMap->GetThreatAt(spots[idx].position) < THREAT_MIN)
			{
				return true;
			}
		}
		return false;
	};
	int bestScore = -1;
	int bestScouted = 0;
	int bestIndex = -1;
	int numToScout = 0;
	for (size_t index = 0; index < scoutPoints.size(); ++index) {
		const SScoutPoint& sp = scoutPoints[index];
		if ((sp.task != nullptr) || metalMgr->IsClusterQueued(index) || metalMgr->IsClusterFinished(index) || !canMoveTo(clusters[index])) {
			continue;
		}
		numToScout++;
		if ((bestScore < sp.score) || ((sp.score == bestScore) && (bestScouted > sp.scouted))) {
			bestScore = sp.score;
			bestIndex = index;
			bestScouted = sp.scouted;
		}
	}
	if ((numToScout <= 1) || (bestIndex == -1)) {
		return -RgtVector;
	}

	SScoutPoint& sp = scoutPoints[bestIndex];
	const CMetalData::SCluster& cluster = clusters[bestIndex];
	while (sp.spotNum < (int)cluster.idxSpots.size()) {
		const CMetalData::SMetal& spot = spots[cluster.idxSpots[sp.spotNum]];
		if (terrainMgr->CanMoveToPos(area, spot.position)
			&& threatMap->GetThreatAt(spot.position) < THREAT_MIN)
		{
			break;
		}
		++sp.spotNum;
	}
	if (sp.spotNum >= (int)cluster.idxSpots.size()) {
		sp.spotNum = 0;
		sp.scouted++;
		return -RgtVector;
	}
	const AIFloat3& spotPos = spots[cluster.idxSpots[sp.spotNum]].position;
	if (pos.SqDistance2D(spotPos) < SQUARE(threatMap->GetSquareSize() * 2)) {  // arrival condition
		++sp.spotNum %= cluster.idxSpots.size();
		if (sp.spotNum == 0) {
			sp.scouted++;
		}
	}
	sp.task = unit->GetTask();
	scoutTasks[unit->GetTask()] = bestIndex;
	return spotPos;
}

void CMilitaryManager::ClearScoutPosition(IUnitTask* task)
{
	auto it = scoutTasks.find(task);
	if (it == scoutTasks.end()) {
		return;
	}
	scoutPoints[it->second].task = nullptr;
	scoutTasks.erase(it);
}

// A lone tower is not somewhere to make a stand, so a position only counts as
// one once it has company. That also keeps the answer near where constructors
// are working, since towers accumulate where they are being built.
#define STAND_RADIUS	700.f
#define STAND_MIN_FENCE	2u
#define STAND_PERIOD	(FRAMES_PER_SEC * 5)

bool CMilitaryManager::IsStrongpoint(const AIFloat3& pos) const
{
	unsigned int count = 0;
	for (const auto& kv : fencePos) {
		if ((pos.SqDistance2D(kv.second) < SQUARE(STAND_RADIUS))
			&& (++count >= STAND_MIN_FENCE))
		{
			return true;
		}
	}
	return false;
}

void CMilitaryManager::FillDefencePos(CCircuitUnit* unit, F3Vec& outPositions)
{
	outPositions.clear();

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	SArea* area = unit->GetArea();
	for (const auto& kv : fencePos) {
		if (IsStrongpoint(kv.second) && terrainMgr->CanMoveToPos(area, kv.second)) {
			outPositions.push_back(kv.second);
		}
	}
}

// The one place a falling-back squad re-forms: our own static defence closest to
// the lane, i.e. the forward end of the tower line rather than the middle of the
// base. Invalid until two towers stand together somewhere.
AIFloat3 CMilitaryManager::GetDefenceStand()
{
	const int frame = circuit->GetLastFrame();
	if ((defStandFrame >= 0) && (frame < defStandFrame + STAND_PERIOD)) {
		return defStand;
	}
	defStandFrame = frame;
	defStand = -RgtVector;

	CSetupManager* setupMgr = circuit->GetSetupManager();
	const AIFloat3& lanePos = setupMgr->GetLanePos();
	const AIFloat3 ref = utils::is_valid(lanePos) ? lanePos : setupMgr->GetBasePos();
	float minSqDist = std::numeric_limits<float>::max();
	for (const auto& kv : fencePos) {
		const float sqDist = ref.SqDistance2D(kv.second);
		if ((minSqDist > sqDist) && IsStrongpoint(kv.second)) {
			minSqDist = sqDist;
			defStand = kv.second;
		}
	}
	return defStand;
}

// Where a squad with nothing to shoot should be standing: where we are actually
// being hit, else the line, else nothing.
//
// Both are single positions and the priority is STRICT. Handing the pathfinder a
// set of candidates makes it pick the cheapest one to walk to, and our own tower
// cluster is always cheaper to walk to than the front -- which is how a squad
// ends up garrisoning the base while a border base burns.
bool CMilitaryManager::GetGuardAnchor(AIFloat3& outPos) const
{
	// A leak behind the line outranks the line. GetAttackHotspot is the heaviest
	// of OUR OWN decaying loss spots, so it points at the fighting rather than at
	// geometry. That spot can be an army dying on the far side of the map, so it
	// is only followed where we are not the weaker side -- otherwise the garrison
	// marches into the enemy base to defend it.
	AIFloat3 hot;
	float weight;
	if (circuit->GetAttackHotspot(hot, weight) && circuit->IsPosOnMap(hot)
		&& (circuit->GetInflMap()->GetInfluenceAt(hot) > -INFL_EPS))
	{
		outPos = hot;
		return true;
	}
	if (circuit->HasFrontPos()) {
		outPos = circuit->GetFrontPos();
		return true;
	}
	return false;
}

// apex: the same score for a NAMED spot, so a pool can be asked what the place
// it is already walking to is worth right now. GetGuardAnchor answers only
// 'which is best', which is why the re-pick had nothing to compare against.
float CMilitaryManager::GuardSpotScore(const AIFloat3& from, int idx) const
{
	const std::vector<CCircuitAI::SHotSpot>& spots = circuit->GetHotSpots();
	if ((idx < 0) || (idx >= int(spots.size())) || !utils::is_valid(from)) {
		return .0f;
	}
	const CCircuitAI::SHotSpot& spot = spots[idx];
	if ((spot.weight < HOT_MIN_WEIGHT) || !circuit->IsPosOnMap(spot.pos)) {
		return .0f;
	}
	if (circuit->GetInflMap()->GetInfluenceAt(spot.pos) <= -INFL_EPS) {
		return .0f;
	}
	CThreatMap* threatMap = circuit->GetThreatMap();
	const float remaining = threatMap->GetThreatAt(spot.pos);
	if (remaining <= .0f) {
		return .0f;
	}
	return remaining / (from.distance2D(spot.pos) + float(threatMap->GetSquareSize()));
}

// The same question asked from ONE pool's position: which unanswered breach is
// worth this pool walking to. Spots are scored by the threat still standing on
// them minus what has already been sent, over the distance to get there, so two
// pools take two breaches instead of both taking the heaviest one.
bool CMilitaryManager::GetGuardAnchor(const AIFloat3& from, const std::vector<float>& assigned,
		AIFloat3& outPos, int& outSpot) const
{
	outSpot = -1;
	if (!utils::is_valid(from)) {
		return false;
	}
	const std::vector<CCircuitAI::SHotSpot>& spots = circuit->GetHotSpots();
	if (spots.empty()) {
		return false;
	}
	CThreatMap* threatMap = circuit->GetThreatMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	const float squareSize = float(threatMap->GetSquareSize());

	float bestScore = .0f;
	for (unsigned i = 0; i < spots.size(); ++i) {
		const CCircuitAI::SHotSpot& spot = spots[i];
		if ((spot.weight < HOT_MIN_WEIGHT) || !circuit->IsPosOnMap(spot.pos)) {
			continue;
		}
		// Same gate as the single-anchor version: a spot on ground we do not hold
		// is a fight we are losing elsewhere, not a breach to garrison.
		if (inflMap->GetInfluenceAt(spot.pos) <= -INFL_EPS) {
			continue;
		}
		const float already = (i < assigned.size()) ? assigned[i] : .0f;
		const float remaining = threatMap->GetThreatAt(spot.pos) - already;
		if (remaining <= .0f) {
			continue;
		}
		const float score = remaining / (from.distance2D(spot.pos) + squareSize);
		if (score > bestScore) {
			bestScore = score;
			outSpot = int(i);
		}
	}
	if (outSpot < 0) {
		return false;
	}
	outPos = spots[outSpot].pos;
	return true;
}

void CMilitaryManager::FillFrontPos(CCircuitUnit* unit, F3Vec& outPositions)
{
	outPositions.clear();

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	SArea* area = unit->GetArea();
	AIFloat3 anchor;
	// Both callers reach here with no target of their own, so an ATTACK squad
	// rallies on the same per-pool anchor a garrison does. A squad that HAS a
	// target never comes through here.
	int spot = -1;
	const std::vector<float> none;
	// GetThreatAt reads whichever layer was selected last; select this unit's.
	circuit->GetThreatMap()->SetThreatType(unit);
	const bool hasAnchor = GetGuardAnchor(unit->GetPos(circuit->GetLastFrame()), none, anchor, spot)
			|| GetGuardAnchor(anchor);
	if (hasAnchor && terrainMgr->CanMoveToPos(area, anchor)) {
		outPositions.push_back(anchor);
		return;
	}

	// Then our own towers. Both callers reach here because the squad found no
	// target it could beat, which is exactly the moment it should fall back onto
	// static defence instead of onto whichever metal cluster is nearest the lane.
	FillDefencePos(unit, outPositions);
	if (!outPositions.empty()) {
		return;
	}

	outPositions.clear();

	CInfluenceMap* inflMap = circuit->GetInflMap();
	CMetalManager* metalMgr = circuit->GetMetalManager();
	const CMetalData::Clusters& clusters = metalMgr->GetClusters();

	CMetalData::PointPredicate predicate = [inflMap, metalMgr, terrainMgr, area, clusters](const int index) {
		return ((inflMap->GetInfluenceAt(clusters[index].position) > -INFL_EPS)
			&& (metalMgr->IsClusterQueued(index) || metalMgr->IsClusterFinished(index))
			&& terrainMgr->CanMoveToPos(area, clusters[index].position));
	};

	CSetupManager* setupMgr = circuit->GetSetupManager();
	int index = metalMgr->FindNearestCluster(setupMgr->GetLanePos(), predicate);

	if (index >= 0) {
		const CDefenceData::DefPoints& points = defence->GetDefPoints();
		const CDefenceData::DefIndices& indices = defence->GetDefIndices(index);
		for (int idx : indices) {
			outPositions.push_back(points[idx].position);
		}
	}
}

void CMilitaryManager::FillAttackSafePos(CCircuitUnit* unit, F3Vec& outPositions)
{
	outPositions.clear();

	// The FRONT first. Every position below comes from GetDefIndices(cluster),
	// i.e. metal-cluster points only, which is why squads orbited bases and mexes
	// and never held a line -- there was no position in the system that meant
	// "the edge of our territory". Script computes one now; it goes in ahead of
	// the clusters so a squad rallies on the line and falls back to clusters only
	// when the front is still unknown.
	if (circuit->HasFrontPos()) {
		outPositions.push_back(circuit->GetFrontPos());
	}

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const int frame = circuit->GetLastFrame();

	SArea* area = unit->GetArea();

	const std::array<IFighterTask::FightType, 2> types = {IFighterTask::FightType::ATTACK, IFighterTask::FightType::DEFEND};
	for (IFighterTask::FightType type : types) {
		const std::set<IFighterTask*>& atkTasks = GetTasks(type);
		for (IFighterTask* task : atkTasks) {
			const AIFloat3& ourPos = static_cast<ISquadTask*>(task)->GetLeaderPos(frame);
			if (terrainMgr->CanMoveToPos(area, ourPos)) {
				outPositions.push_back(ourPos);
			}
		}
	}
}

void CMilitaryManager::FillStaticSafePos(CCircuitUnit* unit, F3Vec& outPositions)
{
	outPositions.clear();

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const int frame = circuit->GetLastFrame();

	const AIFloat3& startPos = unit->GetPos(frame);
	SArea* area = unit->GetArea();

	CDefenceData* defDat = defence;
	const CDefenceData::DefPoints& points = defence->GetDefPoints();
	CMetalData::PointPredicate predicate = [defDat, terrainMgr, area, &points](const int index) {
		const CDefenceData::DefIndices& indices = defDat->GetDefIndices(index);
		for (int idx : indices) {
			if ((points[idx].cost > 100.0f) && terrainMgr->CanMoveToPos(area, points[idx].position)) {
				return true;
			}
		}
		return false;
	};

	CMetalManager* metalMgr = circuit->GetMetalManager();
	int index = metalMgr->FindNearestCluster(startPos, predicate);

	if (index >= 0) {
		const CDefenceData::DefIndices& indices = defence->GetDefIndices(index);
		for (int idx : indices) {
			outPositions.push_back(points[idx].position);
		}
	}
}

void CMilitaryManager::FillSafePos(CCircuitUnit* unit, F3Vec& outPositions)
{
	outPositions.clear();

	// The FRONT first. Every position below comes from GetDefIndices(cluster),
	// i.e. metal-cluster points only, which is why squads orbited bases and mexes
	// and never held a line -- there was no position in the system that meant
	// "the edge of our territory". Script computes one now; it goes in ahead of
	// the clusters so a squad rallies on the line and falls back to clusters only
	// when the front is still unknown.
	if (circuit->HasFrontPos()) {
		outPositions.push_back(circuit->GetFrontPos());
	}

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const int frame = circuit->GetLastFrame();

	const springai::AIFloat3& pos = unit->GetPos(frame);
	SArea* area = unit->GetArea();

	const std::array<IFighterTask::FightType, 2> types = {IFighterTask::FightType::ATTACK, IFighterTask::FightType::DEFEND};
	for (IFighterTask::FightType type : types) {
		const std::set<IFighterTask*>& atkTasks = GetTasks(type);
		for (IFighterTask* task : atkTasks) {
			const AIFloat3& ourPos = static_cast<ISquadTask*>(task)->GetLeaderPos(frame);
			if (terrainMgr->CanMoveToPos(area, ourPos)) {
				outPositions.push_back(ourPos);
			}
		}
		if (!outPositions.empty()) {
			return;
		}
	}

	CDefenceData* defDat = defence;
	const CDefenceData::DefPoints& points = defence->GetDefPoints();
	CMetalData::PointPredicate predicate = [defDat, terrainMgr, area, &points](const int index) {
		const CDefenceData::DefIndices& indices = defDat->GetDefIndices(index);
		for (int idx : indices) {
			if ((points[idx].cost > 100.0f) && terrainMgr->CanMoveToPos(area, points[idx].position)) {
				return true;
			}
		}
		return false;
	};
	CMetalManager* metalMgr = circuit->GetMetalManager();
	int index = metalMgr->FindNearestCluster(pos, predicate);
	if (index >= 0) {
		const CDefenceData::DefIndices& indices = defence->GetDefIndices(index);
		for (int idx : indices) {
			outPositions.push_back(points[idx].position);
		}
	}

	if (outPositions.empty()) {
		outPositions.push_back(circuit->GetSetupManager()->GetBasePos());
	}
}

CCircuitUnit* CMilitaryManager::GetClosestLeader(const std::vector<IFighterTask::FightType>& types, const AIFloat3& position)
{
	IFighterTask* task = nullptr;
	float sqMinDist = std::numeric_limits<float>::max();
	for (IFighterTask::FightType type : types) {
		const std::set<IFighterTask*>& tasks = GetTasks(type);
		for (IFighterTask* t : tasks) {
			const float sqDist = t->GetPosition().SqDistance2D(position);
			if (sqMinDist > sqDist) {
				sqMinDist = sqDist;
				task = t;
			}
		}
		if (task != nullptr) {
			break;
		}
	}
	if ((task == nullptr) || task->GetAssignees().empty()) {
		return nullptr;
	}
	return (task->GetAssignees().size() > 1)
			? static_cast<ISquadTask*>(task)->GetLeader()
			: *task->GetAssignees().begin();
}

IFighterTask* CMilitaryManager::GetGuardTask(CCircuitUnit* unit) const
{
	auto it = guardTasks.find(unit);
	return (it != guardTasks.end()) ? it->second : nullptr;
}

void CMilitaryManager::AddResponse(CCircuitUnit* unit)
{
	const CCircuitDef* cdef = unit->GetCircuitDef();
	const float cost = cdef->GetCostM();
	const CCircuitDef::RoleT roleSize = CCircuitDef::GetRoleNames().size();
	assert(roleInfos.size() == (size_t)roleSize);
	for (CCircuitDef::RoleT type = 0; type < roleSize; ++type) {
		if (cdef->IsRespRoleAny(CCircuitDef::GetMask(type))) {
			roleInfos[type].cost += cost;
			roleInfos[type].units.insert(unit);
		}
	}
}

void CMilitaryManager::DelResponse(CCircuitUnit* unit)
{
	const CCircuitDef* cdef = unit->GetCircuitDef();
	const float cost = cdef->GetCostM();
	const CCircuitDef::RoleT roleSize = CCircuitDef::GetRoleNames().size();
	assert(roleInfos.size() == (size_t)roleSize);
	for (CCircuitDef::RoleT type = 0; type < roleSize; ++type) {
		if (cdef->IsRespRoleAny(CCircuitDef::GetMask(type))) {
			float& metal = roleInfos[type].cost;
			metal = std::max(metal - cost, .0f);
			roleInfos[type].units.erase(unit);
		}
	}
}

float CMilitaryManager::RoleProbability(const CCircuitDef* cdef) const
{
	CEnemyManager* enemyMgr = circuit->GetEnemyManager();
	const SRoleInfo& info = roleInfos[cdef->GetMainRole()];
	float maxProb = 0.f;
	for (const SRoleInfo::SVsInfo& vs : info.vs) {
		const float enemyMetal = enemyMgr->GetEnemyCost(vs.role);
		const float prob = enemyMetal / (info.cost + 1.f) * vs.importance;
		if ((prob > maxProb) &&
			(enemyMetal * vs.ratio >= info.cost * info.factor) &&
			(info.cost + cdef->GetCostM() <= (armyCost + cdef->GetCostM()) * info.maxPerc))
		{
			maxProb = prob;
		}
	}
	return maxProb;
}

bool CMilitaryManager::IsNeedBigGun(const CCircuitDef* cdef) const
{
	return armyCost * circuit->GetEconomyManager()->GetEcoFactor() > cdef->GetCostM();
}

AIFloat3 CMilitaryManager::GetBigGunPos(CCircuitDef* bigDef) const
{
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 pos = circuit->GetSetupManager()->GetBasePos();
	if (bigDef->GetMaxRange() < std::max(terrainMgr->GetTerrainWidth(), terrainMgr->GetTerrainHeight())) {
		CMetalManager* metalMgr = circuit->GetMetalManager();
		const CMetalData::Clusters& clusters = metalMgr->GetClusters();
		unsigned size = 1;
		for (unsigned i = 0; i < clusters.size(); ++i) {
			if (metalMgr->IsClusterFinished(i)) {
				pos += clusters[i].position;
				++size;
			}
		}
		pos /= size;
	}
	return pos;
}

void CMilitaryManager::DiceBigGun()
{
	const SuperInfos& superInfos = GetSideInfo().superInfos;
	if (superInfos.empty()) {
		return;
	}

	SuperInfos candidates;
	candidates.reserve(superInfos.size());
	float magnitude = 0.f;
	for (auto& info : superInfos) {
		if (info.first->IsAvailable(circuit->GetLastFrame())) {
			candidates.push_back(info);
			magnitude += info.second;
		}
	}
	if ((magnitude == 0.f) || candidates.empty()) {
		bigGunDef = superInfos[0].first;
		return;
	}

	unsigned choice = 0;
	float dice = (float)rand() / RAND_MAX * magnitude;
	for (unsigned i = 0; i < candidates.size(); ++i) {
		dice -= candidates[i].second;
		if (dice < 0.f) {
			choice = i;
			break;
		}
	}
	bigGunDef = candidates[choice].first;
}

float CMilitaryManager::ClampMobileCostRatio() const
{
	const float enemyMobileCost = circuit->GetEnemyManager()->GetEnemyMobileCost();
	return (enemyMobileCost > armyCost) ? (armyCost / enemyMobileCost) : 1.f;
}

void CMilitaryManager::UpdateDefenceTasks()
{
	/*
	 * Stockpile
	 */
	for (CCircuitUnit* unit : stockpilers) {
		TRY_UNIT(circuit, unit,
			unit->GetUnit()->Stockpile(UNIT_COMMAND_OPTION_SHIFT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY);
		)
	}

	/*
	 * Defend expansion
	 */
	const std::set<IFighterTask*>& tasks = GetTasks(IFighterTask::FightType::DEFEND);
	CMetalManager* mm = circuit->GetMetalManager();
//	CEconomyManager* em = circuit->GetEconomyManager();
//	CTerrainManager* tm = circuit->GetTerrainManager();
//	const CMetalData::Metals& spots = mm->GetSpots();
	const CMetalData::Clusters& clusters = mm->GetClusters();
//	const std::vector<CEnemyManager::SEnemyGroup>& enemyGroups = circuit->GetEnemyManager()->GetEnemyGroups();
	// A DEFEND task takes its stand position ONCE, in Enqueue, from
	// GetDefenceStand() -- the tower cluster nearest our lane at the moment the
	// task happened to be created. It was never revised afterwards, so a garrison
	// formed in minute 5 was still holding minute 5's ground at minute 40, and
	// every unit built into it was sent there by CDefendTask::Start. apexearth:
	// "the enemy is attacking one of our frontline bases and our huge army isn't
	// there to protect it."
	//
	// Re-anchored to the same thing a squad with no target walks to, so the two
	// agree: where we are being hit, else the front. Only while the task has no
	// target of its own -- an engaged task writes its target into position and
	// must not be pulled off it.
	//
	// PER POOL, not one anchor for all of them. Every garrison used to be sent to
	// the single heaviest point, so two breaches at once pulled the whole army to
	// one of them (or, when it was a centroid, to a point between them that was
	// neither). Heaviest pool picks first and its power is subtracted from that
	// spot's demand, so the next pool prefers the next-worst breach. With one
	// fight running there is one spot and this is the old behaviour exactly.
	std::vector<CDefendTask*> defTasks;
	defTasks.reserve(tasks.size());
	for (IFighterTask* task : tasks) {
		defTasks.push_back(static_cast<CDefendTask*>(task));
	}
	std::sort(defTasks.begin(), defTasks.end(), [](const CDefendTask* a, const CDefendTask* b) {
		return a->GetAttackPower() > b->GetAttackPower();
	});
	std::vector<float> assigned(circuit->GetHotSpots().size(), .0f);
	AIFloat3 fallback;
	const bool hasFallback = GetGuardAnchor(fallback);
	const int frame = circuit->GetLastFrame();
	for (CDefendTask* dt : defTasks) {
		if ((dt->GetTarget() == nullptr) && !dt->IsDispatched(frame)) {
			CCircuitUnit* leader = dt->GetLeader();
			const AIFloat3& from = (leader != nullptr) ? dt->GetLeaderPos(frame) : dt->GetPosition();
			if (leader != nullptr) {
				// GetThreatAt reads whichever layer was selected last.
				circuit->GetThreatMap()->SetThreatType(leader);
			}
			AIFloat3 anchor;
			int spot = -1;
			++guardPicks;
			if (GetGuardAnchor(from, assigned, anchor, spot)) {
				// MEASURE ONLY -- nothing is refused here yet. How often does a pool
				// get sent somewhere new, how far, and how much better was the new
				// spot than the one it was already walking to? A switch whose scores
				// are near-equal is noise winning, not a decision.
				const int held = dt->GetGuardSpot();
				if ((held >= 0) && (held != spot)) {
					++guardFlips;
					const float sNew = GuardSpotScore(from, spot);
					const float sOld = GuardSpotScore(from, held);
					if (sNew <= sOld * 1.25f) {
						++guardFlipsMarginal;
					}
					guardFlipDist += anchor.distance2D(dt->GetPosition());
					if (circuit->GetLastFrame() >= guardFlipLogAt) {
						guardFlipLogAt = circuit->GetLastFrame() + FRAMES_PER_SEC * 30;
						circuit->LOG("apex: guardflip t=%i spot %i->%i moved=%.0f"
								" scoreOld=%.4f scoreNew=%.4f power=%.0f flips=%u marginal=%u meanMove=%.0f",
								circuit->GetTeamId(), held, spot,
								anchor.distance2D(dt->GetPosition()), sOld, sNew,
								dt->GetAttackPower(), guardFlips, guardFlipsMarginal,
								guardFlipDist / float(guardFlips));
					}
				}
				dt->SetGuardSpot(spot);
				dt->SetPosition(anchor);
				if (spot < int(assigned.size())) {
					assigned[spot] += dt->GetAttackPower();
				}
			} else if (hasFallback) {
				dt->SetPosition(fallback);
			}
		}
//		STerrainMapArea* area = dt->GetLeader()->GetArea();
//		CMetalData::PointPredicate predicate = [em, tm, area, &spots, &clusters](const int index) {
//			const CMetalData::MetalIndices& idcs = clusters[index].idxSpots;
//			for (int idx : idcs) {
//				if (!em->IsOpenSpot(idx) && tm->CanMoveToPos(area, spots[idx].position)) {
//					return true;
//				}
//			}
//			return false;
//		};
//		AIFloat3 center = tm->GetTerrainCenter();
//		int index = mm->FindNearestCluster(center, predicate);
//		if (index >= 0) {
//			dt->SetPosition(clusters[index].position);
//		}

		if (dt->GetPromote() != IFighterTask::FightType::ATTACK) {
			continue;
		}
//		int groupIdx = -1;
//		float minSqDist = std::numeric_limits<float>::max();
//		const AIFloat3& position = dt->GetPosition();
//		for (unsigned i = 0; i < enemyGroups.size(); ++i) {
//			const CEnemyManager::SEnemyGroup& group = enemyGroups[i];
//			const float sqDist = position.SqDistance2D(group.pos);
//			if (sqDist < minSqDist) {
//				minSqDist = sqDist;
//				groupIdx = i;
//			}
//		}
//		if (groupIdx >= 0) {
//			dt->SetMaxPower(std::max(minAttackers, enemyGroups[groupIdx].threat));
//		}
		dt->SetMaxPower(std::max(minAttackers, circuit->GetEnemyManager()->GetPreMaxGroupThreat()));
	}

	// apex: printed EVERY 30s whether or not anything flipped. A zero flip count
	// and a dead code path look identical without the denominator -- the first
	// version of this instrument logged nothing all game and could not tell me
	// which of the two I was looking at.
	if (circuit->GetLastFrame() >= guardSumLogAt) {
		guardSumLogAt = circuit->GetLastFrame() + FRAMES_PER_SEC * 30;
		circuit->LOG("apex: guardsum t=%i pools=%i picks=%u flips=%u marginal=%u meanMove=%.0f",
				circuit->GetTeamId(), (int)defTasks.size(), guardPicks, guardFlips,
				guardFlipsMarginal,
				(guardFlips > 0) ? (guardFlipDist / float(guardFlips)) : 0.f);
	}

	/*
	 * Split: a breach no defend pool can answer peels a matched slice out of
	 * the biggest attack squad. apexearth 2026-08-22: "There'll be an army
	 * killing our base and our army is off fighting some other army, winning
	 * that fight, but our base is dead." Demand is measured on live enemy
	 * GROUP influence (the threat map reads ~0 almost everywhere), answered
	 * at a margin, taken fastest-first so the response can arrive in time;
	 * the rest of the squad keeps its fight.
	 */
	if (circuit->GetTunable("apex_army_split", 1.f) > 0.f) {
		const int frame = circuit->GetLastFrame();
		if (frame >= splitFrame) {
			const std::vector<CCircuitAI::SHotSpot>& spots = circuit->GetHotSpots();
			CInfluenceMap* inflMap = circuit->GetInflMap();
			const std::vector<CEnemyManager::SEnemyGroup>& groups =
					circuit->GetEnemyManager()->GetEnemyGroups();
			int bestSpot = -1;
			float bestDemand = .0f;
			for (unsigned i = 0; i < spots.size(); ++i) {
				if ((spots[i].weight < HOT_MIN_WEIGHT) || !circuit->IsPosOnMap(spots[i].pos)) {
					continue;
				}
				// A spot on ground we do not hold is a fight lost elsewhere,
				// not a breach -- same gate as GetGuardAnchor.
				if (inflMap->GetInfluenceAt(spots[i].pos) <= -INFL_EPS) {
					continue;
				}
				float live = .0f;
				for (const CEnemyManager::SEnemyGroup& g : groups) {
					if (g.pos.SqDistance2D(spots[i].pos) < SQUARE(800.f)) {
						live += g.influence;
					}
				}
				// apexearth 2026-08-22: "If the base has enough defenses to
				// handle what's attacking it then we don't need to send our
				// army to it." The guns already standing at the breach count
				// against the demand, same radius as the enemy measure.
				float standing = .0f;
				static std::vector<CCircuitUnit*> nearStructs;  // NOTE: micro-opt, one sweep per hot spot
				circuit->GetOwnStructsNear(spots[i].pos, 800.f, nearStructs);
				for (CCircuitUnit* s : nearStructs) {
					CCircuitDef* sdef = s->GetCircuitDef();
					if (sdef->IsAttacker() && !sdef->IsRoleAA()) {
						standing += sdef->GetPower();
					}
				}
				const float already = (i < assigned.size()) ? assigned[i] : .0f;
				const float demand = live - already - standing;
				if (demand > bestDemand) {
					bestDemand = demand;
					bestSpot = (int)i;
				}
			}
			CAttackTask* src = nullptr;
			if (bestSpot >= 0) {
				for (IFighterTask* t : GetTasks(IFighterTask::FightType::ATTACK)) {
					CAttackTask* at = static_cast<CAttackTask*>(t);
					if ((at->GetLeader() == nullptr) || at->GetAssignees().empty()) {
						continue;
					}
					if ((src == nullptr) || (at->GetAttackPower() > src->GetAttackPower())) {
						src = at;
					}
				}
			}
			const AIFloat3& spotPos = (bestSpot >= 0) ? spots[bestSpot].pos : ZeroVector;
			// Only when the squad is too far to answer by itself -- nearby it
			// already elects the breach as a target.
			if ((src != nullptr)
				&& (src->GetLeaderPos(frame).SqDistance2D(spotPos)
					> SQUARE(circuit->GetTunable("apex_split_min_dist", 1600.f))))
			{
				const float want = bestDemand * circuit->GetTunable("apex_split_margin", 1.3f);
				std::vector<CCircuitUnit*> order(src->GetAssignees().begin(), src->GetAssignees().end());
				std::sort(order.begin(), order.end(), [](CCircuitUnit* a, CCircuitUnit* b) {
					return a->GetCircuitDef()->GetSpeed() > b->GetCircuitDef()->GetSpeed();
				});
				float got = .0f;
				unsigned take = 0;
				while ((take < order.size()) && (got < want)) {
					got += order[take]->GetCircuitDef()->GetPower();
					++take;
				}
				if ((take > 0) && (got >= want * 0.5f)) {  // enough to matter, even if it is the whole squad
					CDefendTask* dt2 = static_cast<CDefendTask*>(Enqueue(TaskF::Defend(
							IFighterTask::FightType::ATTACK, IFighterTask::FightType::ATTACK, got)));
					dt2->SetPosition(spotPos);
					dt2->HoldPromote(frame + FRAMES_PER_SEC
							* (int)circuit->GetTunable("apex_split_hold", 40.f));
					for (unsigned i = 0; i < take; ++i) {
						AssignTask(order[i], dt2);
					}
					splitFrame = frame + FRAMES_PER_SEC
							* (int)circuit->GetTunable("apex_split_cd", 30.f);
					circuit->LOG("apex: SPLIT %d units (%.0f power) answer breach (%.0f,%.0f) demand=%.0f (net of pools+guns), %d stay",
							(int)take, got, spotPos.x, spotPos.z, bestDemand,
							(int)(order.size() - take));
					if (circuit->GetTunable("apex_ping", 0.f) > 0.f) {
						circuit->GetDrawer()->AddPoint(spotPos, utils::string_format(
								"SPLIT n=%d demand=%d", (int)take, (int)bestDemand).c_str());
					}
				}
			}
		}
	}

	/*
	 * Porc update
	 */
	decltype(defenceIdx) prevIdx = defenceIdx;
	while (defenceIdx < clusters.size()) {
		int index = defenceIdx++;
		if (mm->IsClusterQueued(index) || mm->IsClusterFinished(index)) {
			MakeDefence(index);
			return;
		}
	}
	defenceIdx = 0;
	while (defenceIdx < prevIdx) {
		int index = defenceIdx++;
		if (mm->IsClusterQueued(index) || mm->IsClusterFinished(index)) {
			MakeDefence(index);
			return;
		}
	}
}

// apex: THE RAID DISPATCHER. apexearth: "We should look at the trajectory of
// enemy units (if we can) and intercept them. The goal should be to intercept
// them before they get to our buildings"; "if 5 raiders attack us, we have 10
// units". Every pass, each enemy group whose course crosses our buildings
// inside DISPATCH_HORIZON_S takes the nearest home-guard units until they
// hold DISPATCH_COVER times its worth, soonest arrival first. Those units are
// moved into one CDefendTask per group, which stands at the building on the
// group's course and engages once it is the group's worth itself. A pool
// keeps its group between passes and is released when the group is gone.
// Inbound units are read one by one and clustered here, and the guard is
// every squad standing at home, whatever pool it sits in.
// This is an allocation, not an election: a pool that merged before the raid
// is split here, and a lone unit is not sent at a clump.
static constexpr float DISPATCH_HORIZON_S = 30.f;
static constexpr float DISPATCH_COVER = 2.f;
static constexpr float DISPATCH_STICK_R = 700.f;
static constexpr float DISPATCH_CLUSTER_R = 450.f;   // inbound units this close are one raid
static constexpr float DISPATCH_NOTICE = 2.f;        // x base range: a raider this near home is inbound unless leaving
static constexpr int DISPATCH_TTL = FRAMES_PER_SEC * 6;

void CMilitaryManager::SetGuardPost(CCircuitUnit* unit, const AIFloat3& pos, float reach)
{
	if (unit != nullptr) {
		guardPosts[unit->GetId()] = {pos, reach};
	}
}

bool CMilitaryManager::GetGuardPost(const CCircuitUnit* unit, AIFloat3& outPos, float& outReach) const
{
	if (unit == nullptr) {
		return false;
	}
	auto it = guardPosts.find(unit->GetId());
	if (it == guardPosts.end()) {
		return false;
	}
	outPos = it->second.pos;
	outReach = it->second.reach;
	return true;
}

void CMilitaryManager::DispatchRaids()
{
	// OFF by default: three measured cuts (2026-09-04) fired and left level-5
	// buildings lost inside noise while level 1 lost 13-15 buildings per 32
	// waves against 0. See ISSUES.md; the switch stays for the next cut.
	if (circuit->GetTunable("apex_intercept", 0.f) <= 0.f) {
		return;
	}
	const int frame = circuit->GetLastFrame();
	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const float baseR = GetBaseDefRange() * 1.25f;
	CInfluenceMap* inflMap = circuit->GetInflMap();

	// Inbound enemies, one by one: k-means groups put their centre between
	// raiders coming from different angles, so the raid is clustered here from
	// the units themselves.
	struct SInbound {
		AIFloat3 pos;
		AIFloat3 aim;
		float infl;
		int eta;
	};
	std::vector<SInbound> in;
	int still = 0, nearN = 0, tracked = 0;
	// Forget contacts not seen for a while.
	for (auto it = raidTrack.begin(); it != raidTrack.end();) {
		if (frame - it->second.frame > FRAMES_PER_SEC * 20) {
			it = raidTrack.erase(it);
		} else {
			++it;
		}
	}
	for (const auto& kv : circuit->GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		if (e->IsHidden()) {
			continue;
		}
		CCircuitDef* ed = e->GetCircuitDef();
		if ((ed != nullptr) && (!ed->IsMobile() || !ed->IsAttacker())) {
			continue;
		}
		const float infl = (ed != nullptr) ? ed->GetPower() : e->GetInfluence();
		if (infl <= .0f) {
			continue;
		}
		const AIFloat3& ePos = e->GetPos();
		if (!circuit->IsPosOnMap(ePos)) {
			continue;
		}
		SInbound s;
		s.pos = ePos;
		s.aim = ePos;
		s.infl = infl;
		s.eta = -1;
		// Velocity: the engine's, else the contact's own track (radar blips
		// read zero), else none.
		AIFloat3 v = e->GetVel();
		bool moving = (v.x * v.x + v.z * v.z) > 1e-4f;
		auto tr = raidTrack.find(e->GetId());
		if (!moving && (tr != raidTrack.end()) && (frame - tr->second.frame >= FRAMES_PER_SEC / 2)) {
			const float dt = (float)(frame - tr->second.frame);
			v = AIFloat3((ePos.x - tr->second.pos.x) / dt, .0f, (ePos.z - tr->second.pos.z) / dt);
			moving = (v.x * v.x + v.z * v.z) > 1e-4f;
			if (moving) {
				++tracked;
			}
		}
		if ((tr == raidTrack.end()) || (frame - tr->second.frame >= FRAMES_PER_SEC / 2)) {
			raidTrack[e->GetId()] = {ePos, frame};
		}
		if (!moving) {
			++still;
		}
		const float dBase = basePos.distance2D(ePos);
		// Where its course first crosses ground our buildings hold: that is
		// the building it is going for, inside the ring or out.
		bool crossed = false;
		if (moving) {
			for (int k = 1; k <= 6; ++k) {
				const float dt = FRAMES_PER_SEC * DISPATCH_HORIZON_S * k / 6.f;
				AIFloat3 pp(ePos.x + v.x * dt, ePos.y, ePos.z + v.z * dt);
				CTerrainManager::CorrectPosition(pp);
				if (inflMap->GetAllyDefendInflAt(pp) > INFL_EPS) {
					s.eta = (int)dt;
					s.aim = pp;
					crossed = true;
					break;
				}
			}
		}
		if (dBase < baseR) {
			s.eta = 0;
			if (!crossed) {
				// No course to read: it is going for the nearest of ours.
				CCircuitUnit* nearest = nullptr;
				float bestSq = SQUARE(1500.f);
				static std::vector<CCircuitUnit*> nearStructs;  // NOTE: micro-opt, one sweep per inbound enemy
				circuit->GetOwnStructsNear(ePos, 1500.f, nearStructs);
				for (CCircuitUnit* st : nearStructs) {
					const float sq = st->GetPos(frame).SqDistance2D(ePos);
					if (sq < bestSq) {
						bestSq = sq;
						nearest = st;
					}
				}
				if (nearest != nullptr) {
					s.aim = nearest->GetPos(frame);
				}
			}
		}
		if ((s.eta < 0) && (dBase < baseR * DISPATCH_NOTICE)) {
			// Near home and not walking away: inbound, ETA by the straight
			// line. Radar contacts with no velocity reading land here too.
			const float closing = moving
					? -(v.x * (ePos.x - basePos.x) + v.z * (ePos.z - basePos.z)) / std::max(dBase, 1.f)
					: .0f;
			if (closing >= -0.05f) {
				const float speed = (ed != nullptr) ? std::max(ed->GetSpeed(), 1.f) : 60.f;
				s.eta = (int)((dBase - baseR) / speed * FRAMES_PER_SEC);
				++nearN;
			}
		}
		if (s.eta >= 0) {
			in.push_back(s);
		}
	}
	if (in.empty()) {
		return;   // dispatches expire on their own (DISPATCH_TTL)
	}

	struct SRaid {
		AIFloat3 pos;
		AIFloat3 aim;
		float infl;
		int eta;
		int n;
		float got;
		CDefendTask* host;
		std::vector<CCircuitUnit*> units;
	};
	std::vector<SRaid> raids;
	for (const SInbound& s : in) {
		SRaid* into = nullptr;
		for (SRaid& r : raids) {
			if (r.pos.SqDistance2D(s.pos) < SQUARE(DISPATCH_CLUSTER_R)) {
				into = &r;
				break;
			}
		}
		if (into == nullptr) {
			raids.push_back({s.pos, s.aim, s.infl, s.eta, 1, .0f, nullptr, {}});
			continue;
		}
		// Running centroid; the earliest arrival names the building.
		into->pos.x = (into->pos.x * into->n + s.pos.x) / (into->n + 1);
		into->pos.z = (into->pos.z * into->n + s.pos.z) / (into->n + 1);
		into->infl += s.infl;
		if (s.eta < into->eta) {
			into->eta = s.eta;
			into->aim = s.aim;
		}
		++into->n;
	}
	std::sort(raids.begin(), raids.end(), [](const SRaid& a, const SRaid& b) {
		return a.eta < b.eta;
	});

	// The home guard: every unit in a DEFEND pool, plus any squad standing at
	// home -- the units the pin or the factory produced are in ATTACK or RALLY
	// pools as often as in DEFEND ones.
	struct SGuard {
		CCircuitUnit* unit;
		CDefendTask* task;   // null unless a DEFEND pool
		float power;
		AIFloat3 pos;
		bool taken;
	};
	std::vector<SGuard> guard;
	for (IFighterTask* t : GetTasks(IFighterTask::FightType::DEFEND)) {
		CDefendTask* dt = static_cast<CDefendTask*>(t);
		for (CCircuitUnit* u : dt->GetAssignees()) {
			guard.push_back({u, dt, u->GetCircuitDef()->GetPower(), u->GetPos(frame), false});
		}
	}
	// RAID and SCOUT too: measured, 13 of 18 army units sat in RAID pools
	// during a level-5 raid and the dispatcher saw a guard of 4.
	for (IFighterTask::FightType ft : {IFighterTask::FightType::ATTACK, IFighterTask::FightType::RALLY,
	                                   IFighterTask::FightType::RAID, IFighterTask::FightType::SCOUT}) {
		for (IFighterTask* t : GetTasks(ft)) {
			for (CCircuitUnit* u : t->GetAssignees()) {
				const AIFloat3& up = u->GetPos(frame);
				if (basePos.SqDistance2D(up) <= SQUARE(baseR * 1.5f)) {
					guard.push_back({u, nullptr, u->GetCircuitDef()->GetPower(), up, false});
				}
			}
		}
	}
	if (guard.empty()) {
		return;
	}
	// A unit already dispatched to a group stays with it -- up to the need,
	// so a pool that outgrew its group frees the rest for the others.
	for (SRaid& r : raids) {
		const float need = r.infl * DISPATCH_COVER;
		for (SGuard& g : guard) {
			if (r.got >= need) {
				break;
			}
			if (!g.taken && (g.task != nullptr) && g.task->IsDispatched(frame)
				&& (g.task->GetDispatchPos().SqDistance2D(r.pos) < SQUARE(DISPATCH_STICK_R)))
			{
				g.taken = true;
				r.units.push_back(g.unit);
				r.got += g.power;
				if (r.host == nullptr) {
					r.host = g.task;
				}
			}
		}
	}
	// Then the nearest free units, until the group is covered at 2:1.
	for (SRaid& r : raids) {
		const float need = r.infl * DISPATCH_COVER;
		if (r.got >= need) {
			continue;
		}
		std::vector<int> free;
		for (unsigned i = 0; i < guard.size(); ++i) {
			if (!guard[i].taken) {
				free.push_back((int)i);
			}
		}
		const AIFloat3 aim = r.aim;
		std::sort(free.begin(), free.end(), [&guard, &aim](int a, int b) {
			return guard[a].pos.SqDistance2D(aim) < guard[b].pos.SqDistance2D(aim);
		});
		for (int i : free) {
			if (r.got >= need) {
				break;
			}
			guard[i].taken = true;
			r.units.push_back(guard[i].unit);
			r.got += guard[i].power;
		}
	}
	// One pool per group. The host is the DEFEND pool holding most of the
	// group's units, unless another group took it first; then a new pool.
	std::set<CDefendTask*> hosts;
	for (SRaid& r : raids) {
		if (r.units.empty()) {
			continue;
		}
		if ((r.host == nullptr) || (hosts.find(r.host) != hosts.end())) {
			std::map<CDefendTask*, int> count;
			for (const SGuard& g : guard) {
				if (g.taken && (g.task != nullptr) && (hosts.find(g.task) == hosts.end())
					&& (std::find(r.units.begin(), r.units.end(), g.unit) != r.units.end()))
				{
					++count[g.task];
				}
			}
			r.host = nullptr;
			int best = 0;
			for (const auto& kv : count) {
				if (kv.second > best) {
					best = kv.second;
					r.host = kv.first;
				}
			}
		}
		if (r.host == nullptr) {
			r.host = static_cast<CDefendTask*>(Enqueue(TaskF::Defend(
					IFighterTask::FightType::ATTACK, IFighterTask::FightType::ATTACK,
					r.infl * DISPATCH_COVER)));
		}
		hosts.insert(r.host);
	}
	// Moves last: AssignTask can abort an emptied pool, so no task pointer
	// read above may follow one.
	int moved = 0, sent = 0, pools = 0;
	for (SRaid& r : raids) {
		if (r.units.empty() || (r.host == nullptr)) {
			continue;
		}
		r.host->Dispatch(r.pos, r.aim, r.infl, frame + DISPATCH_TTL);
		for (CCircuitUnit* u : r.units) {
			if (u->GetTask() != r.host) {
				AssignTask(u, r.host);
				++moved;
			}
		}
		sent += (int)r.units.size();
		++pools;
	}
	if (frame >= dispatchLogFrame + FRAMES_PER_SEC * 5) {
		dispatchLogFrame = frame;
		const SRaid& f = raids.front();
		circuit->LOG("apex: dispatch raids=%d inbound=%d still=%d tracked=%d near=%d baseR=%.0f guard=%d sent=%d moved=%d pools=%d first: n=%d infl=%.1f eta=%ds need=%.1f got=%.1f aim=(%.0f,%.0f)",
				(int)raids.size(), (int)in.size(), still, tracked, nearN, baseR, (int)guard.size(), sent, moved, pools,
				f.n, f.infl, f.eta / FRAMES_PER_SEC, f.infl * DISPATCH_COVER, f.got, f.aim.x, f.aim.z);
	}
}

void CMilitaryManager::UpdateDefence()
{
	ZoneScoped;

	const int frame = circuit->GetLastFrame();
	decltype(buildDefence)::iterator ibd = buildDefence.begin();
	while (ibd != buildDefence.end()) {
		const auto& defElem = ibd->second.back();
		if (frame >= defElem.second) {
			CCircuitDef* buildDef = defElem.first;
			if (buildDef->IsAvailable(frame)) {
				// A gun placed at the base is a gun that never shoots. Anything that
				// shoots ground goes to the forward edge of held territory instead;
				// AA, anti-nuke and the sensor towers stay where the value is.
				const AIFloat3 pos = (buildDef->IsAttacker() && !buildDef->IsRoleAA() && !buildDef->IsRoleSuper())
						? GetFrontierPos(ibd->first) : ibd->first;
				circuit->GetBuilderManager()->Enqueue(TaskB::Common(IBuilderTask::BuildType::DEFENCE,
						IBuilderTask::Priority::NORMAL, buildDef, pos, 0.f, true, 0));
			}
			ibd->second.pop_back();
		}
		if (ibd->second.empty()) {
			ibd = buildDefence.erase(ibd);
		} else {
			++ibd;
		}
	}
	if (buildDefence.empty()) {
		circuit->GetScheduler()->RemoveJob(defend);
		defend = nullptr;
	}
}

// The forward edge of the territory this side holds: of the metal clusters our
// side has taken, the one nearest the enemy that is not inside an ally's zone.
// Never further from the enemy than the position handed in, so it can only ever
// move a structure forward.
AIFloat3 CMilitaryManager::GetFrontierPos(const AIFloat3& basePos)
{
	CMetalManager* mm = circuit->GetMetalManager();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const CMetalData::Clusters& clusters = mm->GetClusters();
	const AIFloat3 enemyPos = circuit->GetEnemyManager()->GetEnemyPos();

	const AIFloat3* best = nullptr;
	float bestDist = basePos.SqDistance2D(enemyPos);
	for (unsigned i = 0; i < clusters.size(); ++i) {
		const int index = (int)i;
		if (!mm->IsClusterFinished(index) && !mm->IsClusterQueued(index)) {
			continue;
		}
		const AIFloat3& pos = clusters[i].position;
		if (terrainMgr->IsZoneAlly(pos)) {
			continue;  // an ally's ground; DefaultMakeDefence declines these too
		}
		const float dist = pos.SqDistance2D(enemyPos);
		if (dist < bestDist) {
			bestDist = dist;
			best = &pos;
		}
	}
	return (best == nullptr) ? basePos : *best;
}

void CMilitaryManager::MakeBaseDefence(const AIFloat3& pos)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	// buildDefence stays empty, so UpdateDefence() enqueues nothing.
	return;
}

void CMilitaryManager::AddSensorDefs(const std::set<CCircuitDef*>& buildDefs)
{
	radarDefs.AddDefs(buildDefs);
	sonarDefs.AddDefs(buildDefs);

	// DEBUG
//	std::vector<std::pair<std::string, CAvailList<SSensorExt>*>> vec = {{"Radar", &radarDefs}, {"Sonar", &sonarDefs}};
//	for (const auto& kv : vec) {
//		circuit->LOG("----%s Sensor----", kv.first.c_str());
//		for (const auto& si : kv.second->GetInfos()) {
//			circuit->LOG("%s | costM=%f | costE=%f | radius=%f | efficiency=%f", si.cdef->GetDef()->GetName(),
//					si.cdef->GetCostM(), si.cdef->GetCostE(), si.data.radius, si.score);
//		}
//	}
}

void CMilitaryManager::RemoveSensorDefs(const std::set<CCircuitDef*>& buildDefs)
{
	radarDefs.RemoveDefs(buildDefs);
	sonarDefs.RemoveDefs(buildDefs);

	// DEBUG
//	std::vector<std::pair<std::string, CAvailList<SSensorExt>*>> vec = {{"Radar", &radarDefs}, {"Sonar", &sonarDefs}};
//	for (const auto& kv : vec) {
//		circuit->LOG("----Remove %s Sensor----", kv.first.c_str());
//		for (const auto& si : kv.second->GetInfos()) {
//			circuit->LOG("%s | costM=%f | costE=%f | radius=%f | efficiency=%f", si.cdef->GetDef()->GetName(),
//					si.cdef->GetCostM(), si.cdef->GetCostE(), si.data.radius, si.score);
//		}
//	}
}

const CMilitaryManager::SSideInfo& CMilitaryManager::GetSideInfo() const
{
	return sideInfos[circuit->GetSideId()];
}

CCircuitDef* CMilitaryManager::GetLowSonar(const CCircuitUnit* builder) const
{
	const int frame = circuit->GetLastFrame();
	return sonarDefs.GetWorstDef([frame, builder](CCircuitDef* cdef, const SSensorExt& data) {
		return cdef->IsAvailable(frame) && ((builder == nullptr) || builder->GetCircuitDef()->CanBuild(cdef));
	});
}

CEnemyInfo* CMilitaryManager::FindBCombatTarget(CCircuitUnit* unit, const AIFloat3& pos,
		float powerMod, bool isTest)
{
	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	if (pos.SqDistance2D(basePos) > SQUARE(GetBaseDefRange())) {
		return nullptr;
	}

	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	SArea* area = unit->GetArea();
	CCircuitDef* cdef = unit->GetCircuitDef();
	const float maxSpeed = SQUARE(cdef->GetSpeed() / FRAMES_PER_SEC);
	const float maxPower = threatMap->GetUnitPower(unit) * powerMod;
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
	const float sqCommRadBegin = SQUARE(GetCommDefRadBegin());
	float minSqDist = SQUARE(GetCommDefRad(pos.distance2D(basePos)));

	CEnemyInfo* bestTarget = nullptr;
	CEnemyInfo* worstTarget = nullptr;
	threatMap->SetThreatType(unit);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		// TODO: check how close is another task, and its movement vector
		if (enemy->IsHidden() || (enemy->GetTasks().size() > 1)) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		const float sqDist = pos.SqDistance2D(ePos);
		if ((basePos.SqDistance2D(ePos) > sqCommRadBegin) && (sqDist > minSqDist)) {
			continue;
		}

		const float power = threatMap->GetThreatAt(ePos);
		if ((maxPower <= power)
			|| (inflMap->GetAllyDefendInflAt(ePos) < INFL_EPS)
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		const AIFloat3& eVel = enemy->GetVel();
		if (eVel.SqLength2D() >= maxSpeed) {  // speed
			const AIFloat3 uVec = pos - ePos;
			const float dotProduct = eVel.dot2D(uVec);
//			if (dotProduct < 0) {  // direction (angle > 90 deg)
//				continue;
//			}
			if (dotProduct < SQRT_3_2 * sqrtf(eVel.SqLength2D() * uVec.SqLength2D())) {  // direction (angle > 30 deg)
				continue;
			}
		}

		int targetCat;
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			targetCat = edef->GetCategory();
			if (((targetCat & canTargetCat) == 0)
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()
				|| (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())))  // notAA
			{
				continue;
			}
			float elevation = map->GetElevationAt(ePos.x, ePos.z);
			if (edef->IsInWater(elevation, ePos.y)) {
				if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater())) {  // notAW
					continue;
				}
			} else {
				if (!(IsInWater ? cdef->HasSubToLand() : cdef->HasSurfToLand())) {  // notAL
					continue;
				}
			}
			if (ePos.y - elevation > weaponRange) {
				continue;
			}
		} else {
			if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater()) && (ePos.y < -SQUARE_SIZE * 5)) {  // notAW
				continue;
			}
			targetCat = UNKNOWN_CATEGORY;
		}

		if (enemy->IsInRadarOrLOS()) {
			if (isTest) {
				return enemy;
			}
			if ((targetCat & noChaseCat) == 0) {
				bestTarget = enemy;
				minSqDist = sqDist;
			} else if (bestTarget == nullptr) {
				worstTarget = enemy;
			}
		}
	}
	if (bestTarget == nullptr) {
		bestTarget = worstTarget;
	}

	return bestTarget;
}

float CMilitaryManager::GetRangeUnitCountCompensatorScale()
{
	if (threatRangeScaling.frame < circuit->GetLastFrame()) {
		threatRangeScaling.frame = circuit->GetLastFrame() + TEAM_SLOWUPDATE_RATE - 1;
		const int enemyTeamSize = circuit->GetEnemyTeamSize();
		const int totalEnemies = circuit->GetEnemyInfos().size();
		const int enemyCountMinToStartScaling = threatRangeScaling.enemyCountPerEnemyTeamToStartScaling * enemyTeamSize;
		const int enemyCountForMaxScale = threatRangeScaling.enemyCountPerEnemyTeamToEndScaling * enemyTeamSize;
		const float rateAdjPerUnit = 1.0f / (float)(enemyCountForMaxScale - enemyCountMinToStartScaling);
		threatRangeScaling.scale = std::min(1.0f, std::max(threatRangeScaling.endScaleValue, 1.0f - (totalEnemies - enemyCountMinToStartScaling) * rateAdjPerUnit));
//		circuit->LOG("getRangeUnitCountCompensatorScale: %f, totalEnemies %i, minEnemyCountBeforeScaling %i, rateAdjPerUnit %f",
//				threatRangeScaling.scale, totalEnemies, enemyCountMinToStartScaling, rateAdjPerUnit);
	}
	return threatRangeScaling.scale;
}

IUnitTask* CMilitaryManager::DefaultMakeTask(CCircuitUnit* unit)
{
	// FIXME: Make central task assignment system.
	//        MilitaryManager should decide what tasks to merge.
	static const std::map<CCircuitDef::RoleT, IFighterTask::FightType> types = {
		{ROLE_TYPE(SCOUT),   IFighterTask::FightType::SCOUT},
		{ROLE_TYPE(RAIDER),  IFighterTask::FightType::RAID},
		{ROLE_TYPE(RIOT),    IFighterTask::FightType::DEFEND},
		{ROLE_TYPE(ARTY),    IFighterTask::FightType::ARTY},
		{ROLE_TYPE(AA),      IFighterTask::FightType::AA},
		{ROLE_TYPE(AH),      IFighterTask::FightType::AH},
		{ROLE_TYPE(BOMBER),  IFighterTask::FightType::BOMB},
		{ROLE_TYPE(SUPPORT), IFighterTask::FightType::SUPPORT},
		{ROLE_TYPE(MINE),    IFighterTask::FightType::SCOUT},  // FIXME
		{ROLE_TYPE(SUPER),   IFighterTask::FightType::SUPER},
	};
	CEnemyManager* enemyMgr = circuit->GetEnemyManager();
	IFighterTask* task = nullptr;
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (cdef->IsRoleScout() && (GetTasks(IFighterTask::FightType::SCOUT).size() < maxScouts)) {
		task = Enqueue(TaskF::Common(IFighterTask::FightType::SCOUT));
	} else if (cdef->IsRoleSupport()) {
		if (/*cdef->IsAttacker() && */GetTasks(IFighterTask::FightType::ATTACK).empty() && GetTasks(IFighterTask::FightType::DEFEND).empty()) {
			task = Enqueue(TaskF::Defend(IFighterTask::FightType::ATTACK, IFighterTask::FightType::SUPPORT, minAttackers));
		} else {
			task = Enqueue(TaskF::Common(IFighterTask::FightType::SUPPORT));
		}
	} else {
		auto it = types.find(circuit->GetBindedRole(cdef->GetMainRole()));
		if (it != types.end()) {
			switch (it->second) {
				case IFighterTask::FightType::RAID: {
					// apex: A RAIDER'S FIRST JOB IS TO RAID. This scanned GUARD
					// tasks FIRST and joined any that would take the unit, so
					// with guard duty available a raid pool never formed at
					// all: measured 2026-09-01, guard peaked at 19 tasks while
					// raid peaked at ONE task holding 260 metal, in a game
					// apexearth watched us take none of the openings the enemy
					// took every time ("We 100% have opportunities. The enemy
					// takes the opportunities - we never do").
					//
					// The raid pool is offered the unit first; guard duty still
					// gets it when no raid can be formed, which is the case the
					// original order was protecting.
					const bool raidFirst = circuit->GetTunable("apex_raid_first", 1.f) > 0.f;
					if (raidFirst) {
						task = Enqueue(TaskF::Defend(IFighterTask::FightType::RAID, raid.min));
					}
					if (task == nullptr) {
						const std::set<IFighterTask*>& guards = GetTasks(IFighterTask::FightType::GUARD);
						for (IFighterTask* t : guards) {
							if (t->CanAssignTo(unit)) {
								task = t;
								break;
							}
						}
					}
					if (task == nullptr) {
//						if (GetTasks(IFighterTask::FightType::RAID).empty()
//							|| enemyMgr->IsEnemyNear(unit->GetPos(circuit->GetLastFrame())))
//						{
							task = Enqueue(TaskF::Defend(IFighterTask::FightType::RAID, raid.min));
//						}
					}
				} break;
				case IFighterTask::FightType::AH: {
					if (!cdef->IsRoleMine() && (enemyMgr->GetEnemyCost(ROLE_TYPE(HEAVY)) < 1.f)) {
						task = Enqueue(TaskF::Common(IFighterTask::FightType::ATTACK));
					}
				} break;
				case IFighterTask::FightType::DEFEND: {
					const std::set<IFighterTask*>& guards = GetTasks(IFighterTask::FightType::GUARD);
					for (IFighterTask* t : guards) {
						if (t->CanAssignTo(unit)) {
							task = t;
							break;
						}
					}
					if (task == nullptr) {
						// apex: A BAR WE CANNOT REACH IS NOT CAUTION, IT IS
						// PARALYSIS. This was max(minAttackers,
						// GetPreMaxGroupThreat()) -- the influence of the
						// enemy's single LARGEST group -- so a defence pool
						// could only ever promote to ATTACK by matching their
						// biggest blob. Measured 2026-09-01 (4v4 vs BARb hard,
						// Comet Catcher): their largest group reached 48 units
						// and 39,257 army against our whole army of 1,786, and
						// the AI created ZERO attack tasks in twenty minutes
						// while building 60,547 metal of army. It is also
						// self-locking: the mayReinforce escape in DefendTask
						// needs an ATTACK task to already exist, and none can
						// exist until someone clears the full bar.
						//
						// apexearth: "If we see a large enemy army at one
						// place, then we know where their army is. we can
						// defend against that army at home, and take 1/3rd of
						// our army to kill the enemy base." That is the right
						// question -- is there something we can beat -- and it
						// is not answered by their largest concentration. So
						// the bar is also capped by a share of OUR OWN army: a
						// pool holding that share is a real force and goes,
						// whatever they have massed elsewhere.
						// IN THE SAME CURRENCY. The first version of this cap
						// used GetArmyCost(), which is METAL, against
						// GetPreMaxGroupThreat(), which is INFLUENCE -- so the
						// cap never bit and attack stayed at 0 tasks on the
						// re-run. attackPower on a fighter task is summed from
						// GetPower(), the same quantity the enemy groups are
						// measured in, so our own army's power is the sum over
						// our fighter pools.
						float ourPower = 0.f;
						for (IFighterTask::FightType ft : {IFighterTask::FightType::ATTACK,
						                                   IFighterTask::FightType::DEFEND,
						                                   IFighterTask::FightType::RAID,
						                                   IFighterTask::FightType::GUARD}) {
							for (IFighterTask* t : GetTasks(ft)) {
								ourPower += t->GetAttackPower();
							}
						}
						const float ourShare = ourPower
								* circuit->GetTunable("apex_attack_share", 0.34f);
						float power = enemyMgr->GetPreMaxGroupThreat();
						if ((ourShare > 0.f) && (ourShare < power)) {
							power = ourShare;
						}
						power = std::max(minAttackers, power);
						task = Enqueue(TaskF::Defend(IFighterTask::FightType::ATTACK, power));
					}
				} break;
				case IFighterTask::FightType::SUPER: {
					task = Enqueue(TaskF::Common(cdef->IsMobile() ? IFighterTask::FightType::ATTACK : it->second));
				} break;
				default: break;
			}
			if (task == nullptr) {
				task = Enqueue(TaskF::Common(it->second));
			}
		} else {
//			const bool isDefend = GetTasks(IFighterTask::FightType::ATTACK).empty() || enemyMgr->IsEnemyNear(unit->GetPos(circuit->GetLastFrame()));
			const float power = std::max(minAttackers, enemyMgr->GetPreMaxGroupThreat());
			task = /*isDefend ? */Enqueue(TaskF::Defend(IFighterTask::FightType::ATTACK, power))
							/*: EnqueueTask(IFighterTask::FightType::ATTACK)*/;
		}
	}

	return task;
}

// Share of energy income the commander's cloak may consume.
#define COMM_CLOAK_SHARE_DEF	0.5f

// The moving cost is what bites: corcom is 100 e/s standing and 1000 e/s moving,
// and CCircuitDef takes the max of the two, so cloak is affordable only above
// 10,000 e/s of income. Below that the commander must show itself; above it,
// the energy is not worth thinking about and it stays hidden all the time --
// a visible commander is the first thing an enemy aims at.
// apexearth: "one of our commanders is just walking back and forth while trying
// to stay cloaked. 1000 energy to move while cloaked... He has no energy now and
// still cloaked." / "when it is late game and we are very rich our commanders
// should always stay cloaked."
bool CMilitaryManager::IsCommCloakWanted(CCircuitUnit* unit) const
{
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (!cdef->IsAbleToCloak()) {
		return false;
	}
	CEconomyManager* economyMgr = circuit->GetEconomyManager();
	// apex: the share is the whole rule, and 0.1 against the MOVING cost put
	// the bar at 10,000 e/s -- an income most games never reach, so "always
	// cloaked when rich" never happened and commanders stayed visible.
	// Half our energy income is the bar instead: at 2,000 e/s a corcom's
	// 1,000 e/s moving cloak is affordable, which is the state apexearth means
	// by late game. The stall guard above is what stops a poor commander
	// walking around cloaked on an empty bank -- that half still holds.
	const float share = circuit->GetTunable("apex_comm_cloak_share",
			COMM_CLOAK_SHARE_DEF);
	// apex: HYSTERESIS ON BOTH TERMS. An economy running used==produced sits
	// exactly on the stall boundary and flapped this answer 23 times in two
	// minutes (commCloakFlips 6->29, watched live) -- each flap re-issued by
	// the watchdog and the retreat task in good faith. Dropping the cloak
	// needs a SUSTAINED stall (ticks counted in UpdateCommCloak); the cost
	// bar keeps a margin band keyed on the current state so the affordable
	// edge cannot flicker either.
	const bool cloaked = unit->GetUnit()->IsCloaked();
	const float mult = cloaked ? 1.25f : 0.75f;
	const bool stalled = cloaked ? (commCloakStallTicks >= 3)
	                             : economyMgr->IsEnergyStalling();
	return !stalled
			&& (cdef->GetCloakCost() < economyMgr->GetAvgEnergyIncome() * share * mult);
}

// Cloak is switched on once when a unit finishes and nothing outside a retreat
// task ever reconsiders it, so without this the state drifts in both directions:
// a poor commander walks around cloaked with an empty bank, and a rich one that
// was uncloaked once stays visible for the rest of the game.
void CMilitaryManager::UpdateCommCloak()
{
	CCircuitUnit* comm = circuit->GetSetupManager()->GetCommander();
	if ((comm == nullptr) || comm->IsDead() || !comm->GetCircuitDef()->IsAbleToCloak()) {
		return;
	}
	commCloakStallTicks = circuit->GetEconomyManager()->IsEnergyStalling()
			? (commCloakStallTicks + 1) : 0;
	const bool wantCloak = IsCommCloakWanted(comm);
	if (wantCloak != comm->GetUnit()->IsCloaked()) {
		TRY_UNIT(circuit, comm,
			comm->CmdCloak(wantCloak);
		)
	}
}

void CMilitaryManager::Watchdog()
{
	ZoneScopedN(__PRETTY_FUNCTION__);

	UpdateCommCloak();

	for (CCircuitUnit* unit : army) {
		if (unit->GetTask()->GetType() == IUnitTask::Type::PLAYER) {
			continue;
		}
		if (!circuit->GetCallback()->Unit_HasCommands(unit->GetId())) {
			UnitIdle(unit);
		}
	}
}

void CMilitaryManager::AddArmyCost(CCircuitUnit* unit)
{
	AddResponse(unit);
	armyCost += unit->GetCircuitDef()->GetCostM();
}

void CMilitaryManager::DelArmyCost(CCircuitUnit* unit)
{
	DelResponse(unit);
	armyCost = std::max(armyCost - unit->GetCircuitDef()->GetCostM(), .0f);
}

void CMilitaryManager::PointOfInterest(CEnemyInfo* enemy, int start, int step)
{
	if ((enemy->GetCircuitDef() == nullptr)
		|| (!enemy->GetCircuitDef()->IsMex() && (isEnemyFound || enemy->GetCircuitDef()->IsMobile())))
	{
		return;
	}

	CMetalManager* metalMgr = circuit->GetMetalManager();
	int clusterId = metalMgr->FindNearestCluster(enemy->GetPos());
	if (clusterId < 0) {
		return;
	}

	SScoutPoint& sp = scoutPoints[clusterId];
	sp.scouted = 0;
	if (!isEnemyFound) {
		isEnemyFound = true;
		sp.score++;
		if (!enemy->GetCircuitDef()->IsMex()) {
			return;
		}
	}
	sp.enemyNum += (start > 0) ? 1 : -1;
	if ((sp.enemyNum != ((start > 0) ? 1 : 0))) {
		return;
	}

	std::set<int> visited{clusterId};
	std::vector<std::pair<int, int>> toVisit{std::make_pair(clusterId, start)};  // clusterId, level
	const CMetalData::ClusterGraph& clusterGraph = metalMgr->GetClusterGraph();

	while (!toVisit.empty()) {
		std::pair<int, int> q = toVisit.back();
		toVisit.pop_back();

		SScoutPoint& sp = scoutPoints[q.first];
		sp.scouted = 0;
		sp.score += q.second;

		if (q.second + step == 0) {
			continue;
		}
		CMetalData::ClusterGraph::Node node = clusterGraph.nodeFromId(q.first);
		CMetalData::ClusterGraph::IncEdgeIt edgeIt(clusterGraph, node);
		for (; edgeIt != lemon::INVALID; ++edgeIt) {
			const int childId = clusterGraph.id(clusterGraph.oppositeNode(node, edgeIt));
			if (visited.find(childId) == visited.end()) {
				visited.insert(childId);
				toVisit.emplace_back(childId, q.second + step);
			}
		}
	}
#if 0
	if (circuit->GetTeamId() == 0) {
		for (size_t index = 0; index < scoutPoints.size(); ++index) {
			circuit->GetDrawer()->DeletePointsAndLines(metalMgr->GetClusters()[index].position);
		}
		circuit->GetScheduler()->RunJobAfter(CScheduler::GameJob([this]() {
			for (size_t index = 0; index < scoutPoints.size(); ++index) {
				const SScoutPoint& sp = scoutPoints[index];
				if (sp.score > 0) {
					circuit->GetDrawer()->AddPoint(circuit->GetMetalManager()->GetClusters()[index].position, utils::int_to_string(sp.score).c_str());
				}
			}
		}), FRAMES_PER_SEC);
	}
#endif
}

CDefenceData::SDefPoint* CMilitaryManager::FindClosestDefPoint(const AIFloat3& pos)
{
	int cluster = circuit->GetMetalManager()->FindNearestCluster(pos);
	return (cluster < 0) ? nullptr : FindClosestDefPoint(cluster, pos);
}

CDefenceData::SDefPoint* CMilitaryManager::FindClosestDefPoint(int cluster, const AIFloat3& pos,
		std::function<bool (const CDefenceData::SDefPoint& pnt)> predicate)
{
	if (predicate == nullptr) {
		predicate = [](const CDefenceData::SDefPoint&) { return true; };
	}
	CDefenceData::SDefPoint* closestPoint = nullptr;
	float minDist = std::numeric_limits<float>::max();
	const CDefenceData::DefPoints& points = defence->GetDefPoints();
	const CDefenceData::DefIndices& indices = defence->GetDefIndices(cluster);
	for (int idx : indices) {
		if (!predicate(points[idx])) {
			continue;
		}
		float dist = points[idx].position.SqDistance2D(pos);
		if ((closestPoint == nullptr) || (dist < minDist)) {
			closestPoint = const_cast<CDefenceData::SDefPoint*>(&points[idx]);
			minDist = dist;
		}
	}
	return closestPoint;
}

} // namespace circuit
