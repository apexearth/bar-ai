/*
 * EconomyManager.cpp
 *
 *  Created on: Sep 5, 2014
 *      Author: rlcevg
 */

#include "module/EconomyManager.h"
#include "module/BuilderManager.h"
#include "module/FactoryManager.h"
#include "module/MilitaryManager.h"
#include "map/ThreatMap.h"
#include "scheduler/Scheduler.h"
#include "script/EconomyScript.h"
#include "setup/SetupManager.h"
#include "resource/MetalManager.h"
#include "resource/EnergyManager.h"
#include "resource/EnergyGrid.h"
#include "task/builder/FactoryTask.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/GameAttribute.h"
#include "util/Utils.h"
#include "util/Profiler.h"
#include "json/json.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Resource.h"
#include "Economy.h"
#include "Feature.h"
#include "FeatureDef.h"
#include "Team.h"
#include "Log.h"

namespace circuit {

// Energy bank above which an energy-bearing feature (a tree) is not worth a
// constructor-second. apexearth: "do not reclaim for energy if we are >20%
// energy".
#define RECLAIM_ENERGY_MAX	0.20f
// How far a constructor may WALK for an energy feature (a tree). Roughly one
// screen: near enough that it is picked up in passing rather than travelled to.
#define RECLAIM_ENERGY_DIST	900.f


using namespace springai;

#define PYLON_RANGE		500.0f

// Energy-condition relaxation over game time; see UpdateEnergyTasks.
#define ENERGY_GATE_FULL_SEC	600		// unchanged for the first ten minutes
#define ENERGY_GATE_LOW_SEC		1500	// fully relaxed by twenty-five
// Neutralised. Relaxing the energy condition tilted the pick toward fusion-class
// generators, and while one 4500-metal nanoframe stands the task-size formula
// allows no other energy task at all -- so energy flatlines, and every consumer
// of IsEnergyStalling (mexes, mex upgrades, nanos, new factories) is suppressed
// at once while metal keeps accruing.
#define ENERGY_GATE_FLOOR		1.0f

const char* RES_NAME_METAL = "Metal";
const char* RES_NAME_ENERGY = "Energy";

CEconomyManager::CEconomyManager(CCircuitAI* circuit)
		: IModule(circuit, new CEconomyScript(circuit->GetScriptManager(), this))
		, energyGrid(nullptr)
		, pylonDef(nullptr)
		, mexCount(0)
		, indexRes(0)
		, metalProduced(.0f)
		, metalUsed(.0f)
		, isMetalEmpty(false)
		, isMetalFull(false)
		, isEnergyStalling(false)
		, isEnergyEmpty(false)
		, isEnergyFull(false)
		, isEnergyRequired(false)
		, reclConvertEff(2.f)
		, reclEnergyEff(20.f)
		, metal(SResourceInfo {-1, .0f, .0f, .0f, .0f})
		, energy(SResourceInfo {-1, .0f, .0f, .0f, .0f})
		, metalPullCorFrame(-1)
		, metalPullCor(.0f)
		, energyPullCorFrame(-1)
		, energyPullCor(.0f)
		, airpadCount(0)
		, factoryTask(nullptr)
{
	metalRes = circuit->GetCallback()->GetResourceByName(RES_NAME_METAL);
	energyRes = circuit->GetCallback()->GetResourceByName(RES_NAME_ENERGY);
	economy = circuit->GetCallback()->GetEconomy();

	metalIncomes.resize(INCOME_SAMPLES, 1.0f);  // Init metal income
	energyIncomes.resize(INCOME_SAMPLES, 2.0f);  // Init energy income

	// TODO: Use A* ai planning... or sth... STRIPS https://ru.wikipedia.org/wiki/STRIPS
	//       https://ru.wikipedia.org/wiki/Марковский_процесс_принятия_решений

	circuit->GetScheduler()->RunOnInit(CScheduler::GameJob(&CEconomyManager::Init, this));
}

CEconomyManager::~CEconomyManager()
{
	delete metalRes;
	delete energyRes;
	delete economy;

	// Refcounted: CBuilderManager::Enqueue already fired TaskAdded, so a script
	// may still hold a handle. Release, never delete.
	if (factoryTask != nullptr) {
		factoryTask->ClearRelease();
		factoryTask = nullptr;
	}
}

void CEconomyManager::InitHandlers()
{
	/*
	 * resources
	 */
	auto energyFinishedHandler = [this](CCircuitUnit* unit) {
		const SEnergyExt* energyExt = energyDefs.GetAvailInfo(unit->GetCircuitDef());
		if (energyExt == nullptr) {
			return;
		}
		const float income = energyExt->make;
		for (int i = 0; i < INCOME_SAMPLES; ++i) {
			energyIncomes[i] += income;
		}
		energy.income += income;
		ReclaimOldEnergy(energyExt);

		UnitAdded(unit, UseAs::ENERGY);
	};
	auto energyDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		UnitRemoved(unit, UseAs::ENERGY);
	};
	auto geoFinishedHandler = [this](CCircuitUnit* unit) {
		const SGeoExt* geoExt = geoDefs.GetAvailInfo(unit->GetCircuitDef());
		if (geoExt != nullptr) {
			const float income = geoExt->make;
			for (int i = 0; i < INCOME_SAMPLES; ++i) {
				energyIncomes[i] += income;
			}
			energy.income += income;
		}

		UnitAdded(unit, UseAs::GEO);
	};
	auto geoDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		UnitRemoved(unit, UseAs::GEO);
	};
	auto mexFinishedHandler = [this](CCircuitUnit* unit) {
//		const float income = unit->GetUnit()->GetRulesParamFloat("mexIncome", 0.f);
		CMetalManager* metalMgr = this->circuit->GetMetalManager();
		int index = metalMgr->FindNearestSpot(unit->GetPos(this->circuit->GetLastFrame()));
		if (index < 0) {
			return;
		}
		const float income = metalMgr->GetSpots()[index].income * unit->GetCircuitDef()->GetExtractsM();
		for (int i = 0; i < INCOME_SAMPLES; ++i) {
			metalIncomes[i] += income;
		}
		metal.income += income;

		UnitAdded(unit, UseAs::MEX);
	};
	auto mexDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		UnitRemoved(unit, UseAs::MEX);
	};
	auto convertFinishedHandler = [this](CCircuitUnit* unit) {
		const SConvertExt* convertExt = convertDefs.GetAvailInfo(unit->GetCircuitDef());
		if (convertExt == nullptr) {
			return;
		}
		ReclaimOldConvert(convertExt);

		UnitAdded(unit, UseAs::CONVERT);
	};
	auto convertDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		UnitRemoved(unit, UseAs::CONVERT);
	};
	auto storeFinishedHandler = [this](CCircuitUnit* unit) {
		UnitAdded(unit, UseAs::STORE);
	};
	auto storeDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		UnitRemoved(unit, UseAs::STORE);
	};

	/*
	 * morph & plop
	 */
	auto comFinishedHandler = [this](CCircuitUnit* unit) {
		AddMorphee(unit);
		CSetupManager* setupMgr = this->circuit->GetSetupManager();
		if (setupMgr->GetCommander() == nullptr) {
			setupMgr->SetCommander(unit);
		}

		ICoreUnit::Id unitId = unit->GetId();
		this->circuit->GetScheduler()->RunJobAfter(CScheduler::GameJob([this, unitId]() {
			CCircuitUnit* unit = this->circuit->GetTeamUnit(unitId);
			if (unit == nullptr) {
				return;
			}
			int frame = this->circuit->GetLastFrame();
			bool isStart = (frame < FRAMES_PER_SEC * 10);
			AIFloat3 buildPos = -RgtVector;
			if (unit->GetUnit()->GetRulesParamFloat("facplop", 0) == 1) {
				// TODO: check factory's customparam ploppable=1
				const AIFloat3& pos = unit->GetPos(frame);
				CCircuitDef* facDef = this->circuit->GetFactoryManager()->GetFactoryToBuild(pos, isStart);
				if (facDef != nullptr) {
					// Enqueue factory
					CTerrainManager* terrainMgr = this->circuit->GetTerrainManager();
					const float range = std::max(facDef->GetDef()->GetXSize(), facDef->GetDef()->GetZSize())
							* SQUARE_SIZE / 2 * 1.4f + unit->GetCircuitDef()->GetRadius();
					buildPos = terrainMgr->ShiftPos(facDef, pos, range, true);
					CBuilderManager* builderMgr = this->circuit->GetBuilderManager();
					IBuilderTask* task = builderMgr->Enqueue(TaskB::Factory(IBuilderTask::Priority::NOW,
							facDef, buildPos, nullptr, SQUARE_SIZE, true, true, 0));
					builderMgr->AssignTask(unit, task);
				}
			}

			if (!isStart) {
				return;
			}
			int morphFrame = this->circuit->GetSetupManager()->GetMorphFrame(unit->GetCircuitDef());
			if (morphFrame >= 0) {
				this->circuit->GetScheduler()->RunJobAt(CScheduler::GameJob([this, unitId]() {
					// Force commander level 0 to morph
					CCircuitUnit* unit = this->circuit->GetTeamUnit(unitId);
					if ((unit != nullptr)
						&& (unit->GetTask()->GetType() != IUnitTask::Type::PLAYER))
					{
						const std::map<std::string, std::string>& customParams = unit->GetCircuitDef()->GetDef()->GetCustomParams();
						auto it = customParams.find("level");
						if ((it != customParams.end()) && (utils::string_to_int(it->second) <= 1)) {
							unit->Upgrade();  // Morph();
						}
					}
				}), morphFrame);
			}
		}), FRAMES_PER_SEC);
	};
	auto comDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		RemoveMorphee(unit);

		CSetupManager* setupMgr = this->circuit->GetSetupManager();
		CCircuitUnit* commander = setupMgr->GetCommander();
		if (commander == unit) {
			setupMgr->SetCommander(nullptr);
		}
	};

	/*
	 * Airpad counter
	 */
	auto airpadCreatedHandler = [this](CCircuitUnit* unit, CCircuitUnit* builder) {
		++airpadCount;
	};
	auto airpadFinishedHandler = [this](CCircuitUnit* unit) {
		UnitAdded(unit, UseAs::AIRPAD);
	};
	auto airpadDestroyedHandler = [this](CCircuitUnit* unit, CEnemyInfo* attacker) {
		--airpadCount;

		UnitRemoved(unit, UseAs::AIRPAD);
	};

	float minEInc;
	ReadConfig(minEInc);

	float maxAreaDivCost = .0f;
	const float avgWind = (circuit->GetMap()->GetMaxWind() + circuit->GetMap()->GetMinWind()) * 0.5f;

	for (CCircuitDef& cdef : circuit->GetCircuitDefs()) {
		const std::map<std::string, std::string>& customParams = cdef.GetDef()->GetCustomParams();

		if (!cdef.IsMobile()) {
			// pylon
			auto it = customParams.find("pylonrange");
			if (it != customParams.end()) {
				const float range = utils::string_to_float(it->second);
				float areaDivCost = M_PI * SQUARE(range) / cdef.GetCostM();
				if (maxAreaDivCost < areaDivCost) {
					maxAreaDivCost = areaDivCost;
					pylonDef = &cdef;  // armestor
					pylonRange = range;
					// Is it cdef.IncPurpose(); ?
				}
			}

			// mex
			// BA: float metalConverts = unitDef->GetMakesResource(metalRes);
			//     float metalExtracts = unitDef->GetExtractsResource(metalRes);
			//     float netMetal = unitDef->GetResourceMake(metalRes) - unitDef->GetUpkeep(metalRes);
			// FIXME: BA
//			if (((it = customParams.find("ismex")) != customParams.end()) && (utils::string_to_int(it->second) == 1)) {
//				finishedHandler[cdef.GetId()] = mexFinishedHandler;
//				mexDef = &cdef;  // cormex
//				cdef.SetIsMex(true);
//			}
			// FIXME: BA
			if (cdef.GetExtractsM() > 0.f) {
				finishedHandler[cdef.GetId()] = mexFinishedHandler;
				destroyedHandler[cdef.GetId()] = mexDestroyedHandler;
				metalDefs.AddDef(&cdef);
				cdef.SetIsMex(true);
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
				continue;  // NOTE: won't deal with spot requirement if considered as anything else.
			}
			if (((it = customParams.find("energyconv_capacity")) != customParams.end()) && (utils::string_to_float(it->second) > 0.f)
				&& ((it = customParams.find("energyconv_efficiency")) != customParams.end()) && (utils::string_to_float(it->second) > 0.f))
			{
				finishedHandler[cdef.GetId()] = convertFinishedHandler;
				destroyedHandler[cdef.GetId()] = convertDestroyedHandler;
				convertDefs.AddDef(&cdef);
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
			}

			// energy
			// BA: float netEnergy = unitDef->GetResourceMake(energyRes) - unitDef->GetUpkeep(energyRes);
			cdef.SetIsWind(cdef.GetDef()->GetWindResourceGenerator(energyRes) > minEInc);
			it = customParams.find("income_energy");
			if (((it != customParams.end()) && (utils::string_to_float(it->second) > minEInc))
				|| (cdef.GetDef()->GetResourceMake(energyRes) - cdef.GetUpkeepE() > minEInc)
				|| (cdef.IsWind() && (avgWind > minEInc))
				|| (cdef.GetDef()->GetTidalResourceGenerator(energyRes) * circuit->GetMap()->GetTidalStrength() > minEInc))
			{
				if (cdef.GetDef()->IsNeedGeo()) {
					finishedHandler[cdef.GetId()] = geoFinishedHandler;
					destroyedHandler[cdef.GetId()] = geoDestroyedHandler;
					geoDefs.AddDef(&cdef);
				} else {
					finishedHandler[cdef.GetId()] = energyFinishedHandler;
					destroyedHandler[cdef.GetId()] = energyDestroyedHandler;
					energyDefs.AddDef(&cdef);
				}
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
			}

			// storage
			// NOTE: have to manually filter spot units, as mex placement rules are re-defined in game and break in-engine validation
			if ((cdef.GetDef()->GetStorage(metalRes) >= 1000.f)/* && !cdef.IsMex()*/) {
				finishedHandler[cdef.GetId()] = storeFinishedHandler;
				destroyedHandler[cdef.GetId()] = storeDestroyedHandler;
				storeMDefs.AddDef(&cdef);
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
			}
			if ((cdef.GetDef()->GetStorage(energyRes) > 1000.f) && !cdef.GetDef()->IsNeedGeo()) {
				finishedHandler[cdef.GetId()] = storeFinishedHandler;
				destroyedHandler[cdef.GetId()] = storeDestroyedHandler;
				storeEDefs.AddDef(&cdef);
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
			}

			if (customParams.find("isairbase") != customParams.end()) {
				createdHandler[cdef.GetId()] = airpadCreatedHandler;
				finishedHandler[cdef.GetId()] = airpadFinishedHandler;
				destroyedHandler[cdef.GetId()] = airpadDestroyedHandler;
				airpadDefs.AddDef(&cdef);
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
			}

			if ((cdef.GetDef()->GetResourceMake(metalRes) - cdef.GetUpkeepM() > 0.f)
				|| cdef.GetDef()->IsBuilder())
			{
				IncPurpose(cdef.GetId());  // avoid reclaiming of multi-purpose old converter/energy
			}

		} else {

			// commander
			if (cdef.IsRoleComm()) {
				finishedHandler[cdef.GetId()] = comFinishedHandler;
				destroyedHandler[cdef.GetId()] = comDestroyedHandler;
			}

			for (const SSideInfo& sideInfo : sideInfos) {
				if (cdef.CanBuild(sideInfo.defaultDef)) {
					defaultDefs[cdef.GetId()] = sideInfo.defaultDef;
				}
			}
		}
	}

	// FIXME: BA
	for (SSideInfo& sideInfo : sideInfos) {
		if (sideInfo.mexDef == nullptr) {
			sideInfo.mexDef = sideInfo.defaultDef;
		}
		if (sideInfo.geoDef == nullptr) {
			sideInfo.geoDef = sideInfo.defaultDef;
		}
	}
	if (pylonDef == nullptr) {
		pylonDef = sideInfos[0].defaultDef;
		pylonRange = PYLON_RANGE;
	}
	// FIXME: BA
}

void CEconomyManager::ReadConfig(float& outMinEInc)
{
	const Json::Value& root = circuit->GetSetupManager()->GetConfig();
	const std::string& cfgName = circuit->GetSetupManager()->GetConfigName();
	const Json::Value& econ = root["economy"];
	ecoStep = econ.get("eps_step", 0.25f).asFloat();
	ecoFactor = (circuit->GetAllyTeam()->GetSize() - 1.0f) * ecoStep + 1.0f;
	metalMod = (1.f - econ.get("excess", -1.f).asFloat());
	numMexUp = econ.get("mex_up", 2).asUInt();

	{
		const Json::Value& bd = econ["build_delay"];
		float value = bd[0].get((unsigned)0, -1.f).asFloat();
		bdInfo.startDelay = (value > 0.f) ? (value * FRAMES_PER_SEC) : 0;
		bdInfo.startFrame = bd[0].get((unsigned)1, 0).asInt() * FRAMES_PER_SEC;
		value = bd[1].get((unsigned)0, -1.f).asFloat();
		bdInfo.endDelay = (value > 0.f) ? (value * FRAMES_PER_SEC) : 0;
		bdInfo.endFrame = bd[1].get((unsigned)1, 0).asInt() * FRAMES_PER_SEC;
		bdInfo.fraction = (bdInfo.endFrame != bdInfo.startFrame)
				? float(bdInfo.endDelay - bdInfo.startDelay) / (bdInfo.endFrame - bdInfo.startFrame)
				: 0.f;
		buildDelay = bdInfo.startDelay;
	}

	const Json::Value& energy = econ["energy"];
	{
		const Json::Value& factor = energy["factor"];
		efInfo.startFactor = factor[0].get((unsigned)0, 0.5f).asFloat();
		efInfo.startFrame = factor[0].get((unsigned)1, 300 ).asInt() * FRAMES_PER_SEC;
		efInfo.endFactor = factor[1].get((unsigned)0, 2.0f).asFloat();
		efInfo.endFrame = factor[1].get((unsigned)1, 3600).asInt() * FRAMES_PER_SEC;
		efInfo.fraction = (efInfo.endFrame != efInfo.startFrame)
				? (efInfo.endFactor - efInfo.startFactor) / (efInfo.endFrame - efInfo.startFrame)
				: 0.f;
		energyFactor = efInfo.startFactor;
	}

	outMinEInc = energy.get("min_income", 5.f).asFloat();
	costRatio = energy.get("cost_ratio", 0.05f).asFloat();
	ecoEMRatio = energy.get("em_ratio", 0.08f).asFloat();
	clusterRange = econ.get("cluster_range", 950.f).asFloat();
	pylonLinkInc = energy.get("link_inc", 16.0f).asFloat();

	std::string type = circuit->GetTerrainManager()->IsWaterMap() ? "water" : "land";
	const Json::Value& surf = energy[type];
	for (const std::string& engy : surf.getMemberNames()) {
		CCircuitDef* cdef = circuit->GetCircuitDef(engy.c_str());
		if (cdef == nullptr) {
			circuit->LOG("CONFIG %s: has unknown UnitDef '%s'", cfgName.c_str(), engy.c_str());
			continue;
		}
		const Json::Value& surfEngy = surf[engy];
		const int min = surfEngy[0].asInt();
		const int max = surfEngy.get(1, min).asInt();
		SEnergyCond cond;
		cond.limit = min + rand() % (max - min + 1);
		cond.metalIncome = surfEngy.get(2, -1.f).asFloat();
		cond.energyIncome = surfEngy.get(3, -1.f).asFloat();
		cond.score = surfEngy.get(4, -1.f).asFloat();
		engyLimits[cdef] = cond;
	}

	CMaskHandler& sideMasker = circuit->GetGameAttribute()->GetSideMasker();
	sideInfos.resize(sideMasker.GetMasks().size());
	const Json::Value& mex = econ["mex"];
	const Json::Value& geo = econ["geo"];
	const Json::Value& deflt = econ["default"];
	for (const auto& kv : sideMasker.GetMasks()) {
		SSideInfo& sideInfo = sideInfos[kv.second.type];

		// Mex
		const char* name = mex[kv.first].asCString();
		CCircuitDef* cdef = circuit->GetCircuitDef(name);
		if (cdef != nullptr) {
			sideInfo.mexDef = cdef;
		} else {
			circuit->LOG("CONFIG %s: has unknown mexDef '%s'", cfgName.c_str(), name);
		}

		// Geo
		name = geo[kv.first].asCString();
		cdef = circuit->GetCircuitDef(name);
		if (cdef != nullptr) {
			sideInfo.geoDef = cdef;
		} else {
			circuit->LOG("CONFIG %s: has unknown geoDef '%s'", cfgName.c_str(), name);
		}

		// Default
		// NOTE: Must have
		sideInfo.defaultDef = circuit->GetCircuitDef(deflt[kv.first].asCString());
		if (sideInfo.defaultDef == nullptr) {
			throw CException("economy.default");
		}
	}
}

void CEconomyManager::InitEconomyScores()
{
	std::vector<CCircuitDef*> builders;
	for (CCircuitDef& cdef : circuit->GetCircuitDefs()) {
		if (cdef.IsBuilder()) {
			builders.push_back(&cdef);
		}
	}

	metalDefs.Init(builders, [this](CCircuitDef* cdef, SMetalExt& data) -> float {
//		data.speed = cdef->GetExtractsM();
//		return data.speed * 1e+6f - cdef->GetCostM();
		return 1.f / cdef->GetCostM();
	});
	convertDefs.Init(builders, [this](CCircuitDef* cdef, SConvertExt& data) -> float {
		// old engine way: cdef->GetDef()->GetMakesResource(metalRes)
		auto customParams = cdef->GetDef()->GetCustomParams();
		const float ratio = utils::string_to_float(customParams.find("energyconv_efficiency")->second);  // validated on init
		data.energyUse = utils::string_to_float(customParams.find("energyconv_capacity")->second);  // validated on init
		data.make = data.energyUse * ratio;
		data.isOld = false;
		return data.make;
	});

	energyDefs.Init(builders, [this](CCircuitDef* cdef, SEnergyExt& data) -> float {
		auto customParams = cdef->GetDef()->GetCustomParams();
		auto it = customParams.find("income_energy");
		data.make = (it != customParams.end())
				? utils::string_to_float(it->second)
				: cdef->GetDef()->GetResourceMake(energyRes) - cdef->GetUpkeepE() - cdef->GetCloakCost();
		if (data.make < 1) {
			data.make = cdef->GetDef()->GetWindResourceGenerator(energyRes);
			if (data.make < 1) {
				data.make = cdef->GetDef()->GetTidalResourceGenerator(energyRes) * circuit->GetMap()->GetTidalStrength();
			} else {
				float avgWind = (circuit->GetMap()->GetMaxWind() + circuit->GetMap()->GetMinWind()) * 0.5f;
				data.make = std::min(avgWind, data.make);
			}
		}

		auto lit = engyLimits.find(cdef);
		if (lit != engyLimits.end()) {
			data.cond = lit->second;
		}
		if (data.cond.score < .0f) {
			// TODO: Instead of plain sizeX, sizeZ use AI's yardmap size
			data.cond.score = SQUARE(data.make) / ((cdef->GetCostM()/* + cdef->GetCostE() * 0.05f*/) * cdef->GetDef()->GetXSize() * cdef->GetDef()->GetZSize());
		}
		if (data.cond.metalIncome < 0.f) {
			// TODO: Select proper scale/quadratic function (x*x) and smoothing coefficient (8).
			//       МЕТОД НАИМЕНЬШИХ КВАДРАТОВ ! (income|buildPower, make/cost) - points
			//       solar       geothermal    fusion         singu           ...
			//       (10, 2/70), (15, 25/500), (20, 35/1000), (30, 225/4000), ...
			data.cond.metalIncome = sqrtf(cdef->GetCostM() * 16.0f / MAX_BUILD_SEC);
		}
		if (data.cond.energyIncome < 0.f) {
			data.cond.energyIncome = cdef->GetCostE() * costRatio;
		}

		data.isOld = false;

		return data.cond.score;
	});
	geoDefs.Init(builders, [this](CCircuitDef* cdef, SGeoExt& data) -> float {
		data.make = cdef->GetDef()->GetResourceMake(energyRes) - cdef->GetUpkeepE() - cdef->GetCloakCost();
		return data.make / cdef->GetCostM();
	});

	auto scoreFunc = [](CCircuitDef* cdef, const SStoreExt& data) {
		return data.storage / cdef->GetCostM();
	};
	storeMDefs.Init(builders, [this, scoreFunc](CCircuitDef* cdef, SStoreExt& data) -> float {
		data.storage = cdef->GetDef()->GetStorage(metalRes);
		return scoreFunc(cdef, data);
	});
	storeEDefs.Init(builders, [this, scoreFunc](CCircuitDef* cdef, SStoreExt& data) -> float {
		data.storage = cdef->GetDef()->GetStorage(energyRes);
		return scoreFunc(cdef, data);
	});

	airpadDefs.Init(builders, [](CCircuitDef* cdef, SAirpadExt& data) -> float {
		return cdef->GetBuildSpeed() / cdef->GetCostM();
	});
	assistDefs.Init(builders, [](CCircuitDef* cdef, SAssistExt& data) -> float {
		return cdef->GetBuildSpeed() / cdef->GetCostM();
	});
	factoryDefs.Init(builders, [](CCircuitDef* cdef, SFactoryExt& data) -> float {
		// FIXME: Factory sorting is not used anywhere, hence placeholder:
		return cdef->GetBuildSpeed() / cdef->GetCostM();
	});
}

void CEconomyManager::Init()
{
	energyGrid = circuit->GetAllyTeam()->GetEnergyGrid().get();

	const size_t clSize = circuit->GetMetalManager()->GetClusters().size();
	clusterInfos.resize(clSize, {nullptr, -FRAMES_PER_SEC});
	const size_t spSize = circuit->GetMetalManager()->GetSpots().size();
	mexSpots.resize(spSize, {true, false});
	geoSpots.resize(circuit->GetEnergyManager()->GetSpots().size(), {true, false});

	const Json::Value& econ = circuit->GetSetupManager()->GetConfig()["economy"];
	const Json::Value& mexCap = econ["mex_max"];
	const float mm = mexCap.get((unsigned)0, 2.f).asFloat();
	mexMax = (mm < 1.f) ? decltype(mexMax)(mm * spSize) : std::numeric_limits<decltype(mexMax)>::max();
	isAllyMexMax = mexCap.get((unsigned)1, true).asBool();

	const Json::Value& pull = econ["ms_pull"];
	mspInfos.resize(pull.size());
	mspInfos.push_back(SPullMtoS {
		.pull = pull[0].get((unsigned)0, 1.0f).asFloat(),
		.mex = (int)(pull[0].get((unsigned)1, 0.0f).asFloat() * spSize),
		.fraction = 0.f
	});
	for (unsigned i = 1; i < pull.size(); ++i) {
		SPullMtoS mspInfoEnd;
		mspInfoEnd.pull = pull[i].get((unsigned)0, 0.25f).asFloat();
		mspInfoEnd.mex = pull[i].get((unsigned)1, 0.75f).asFloat() * spSize;
		mspInfoEnd.fraction = 0.f;
		mspInfos.push_back(mspInfoEnd);
		SPullMtoS& mspInfoBegin = mspInfos[i - 1];
		mspInfoBegin.fraction = (mspInfoEnd.mex != mspInfoBegin.mex)
				? (mspInfoEnd.pull - mspInfoBegin.pull) / (mspInfoEnd.mex - mspInfoBegin.mex)
				: 0.f;
	}
	std::sort(mspInfos.begin(), mspInfos.end());
	pullMtoS = mspInfos.front().pull;

	CSetupManager::StartFunc subinit = [this](const AIFloat3& pos) {
		metalProduced = GetMetalCur() * metalMod;

		CSetupManager* setupMgr = circuit->GetSetupManager();
		if (setupMgr->GetCommander() == nullptr) {
			for (const auto& kv : circuit->GetTeamUnits()) {
				if (kv.second->GetCircuitDef()->IsRoleComm()) {
					setupMgr->SetCommander(kv.second);
					break;
				}
			}
		}

		CScheduler* scheduler = circuit->GetScheduler().get();
		CAllyTeam* allyTeam = circuit->GetAllyTeam();
		if (circuit->IsCommMerge() && !circuit->IsSavegame()) {
			allyTeam->ResetStartOnce();  // for the case when game ignores AI start positions
			const int spotId = circuit->GetMetalManager()->FindNearestSpot(pos);
			const int clusterId = (spotId < 0) ? -1 : circuit->GetMetalManager()->GetCluster(spotId);
			int ownerId = allyTeam->GetClusterTeam(clusterId).teamId;
			if (ownerId < 0) {
				allyTeam->OccupyCluster(clusterId, circuit->GetTeamId());
			} else if (ownerId != circuit->GetTeamId()) {
				circuit->Resign(ownerId);
				return;
			}

			CCircuitUnit* commander = setupMgr->GetCommander();
			if (commander == nullptr) {
				commander = circuit->GetTeamUnits().begin()->second;
			}
			ownerId = allyTeam->GetAreaTeam(commander->GetArea()).teamId;
			if (ownerId < 0) {
				allyTeam->OccupyArea(commander->GetArea(), circuit->GetTeamId());
//			} else if (ownerId != circuit->GetTeamId()) {
//				circuit->Resign(ownerId);
//				return;
			}
		}

		scheduler->RunJobAfter(CScheduler::GameJob([this]() {
			ecoFactor = (circuit->GetAllyTeam()->GetAliveSize() - 1.0f) * ecoStep + 1.0f;
		}), FRAMES_PER_SEC * 10);

		const float maxTravel = 7 + rand() % (10 - 7 + 1);  // seconds
		const int interval = allyTeam->GetSize() * FRAMES_PER_SEC;
		startFactory = CScheduler::GameJob(&CEconomyManager::StartFactoryJob, this, maxTravel);
		scheduler->RunJobEvery(startFactory, 1, circuit->GetSkirmishAIId() + 0 + 5 * FRAMES_PER_SEC);
		scheduler->RunJobEvery(CScheduler::GameJob(&CEconomyManager::UpdateStorageTasks, this),
								interval, circuit->GetSkirmishAIId() + 1 + interval / 2 + 30 * FRAMES_PER_SEC);

		scheduler->RunJobEvery(CScheduler::GameJob(&CEconomyManager::UpdateEconomy, this),
								TEAM_SLOWUPDATE_RATE, circuit->GetSkirmishAIId());
	};

	circuit->GetSetupManager()->ExecOnFindStart(subinit);
}

int CEconomyManager::UnitCreated(CCircuitUnit* unit, CCircuitUnit* builder)
{
	auto search = createdHandler.find(unit->GetCircuitDef()->GetId());
	if (search != createdHandler.end()) {
		search->second(unit, builder);
	}

	return 0; //signaling: OK
}

int CEconomyManager::UnitFinished(CCircuitUnit* unit)
{
	auto search = finishedHandler.find(unit->GetCircuitDef()->GetId());
	if (search != finishedHandler.end()) {
		search->second(unit);
	}

	return 0; //signaling: OK
}

int CEconomyManager::UnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	// NOTE: If more actions should be done then consider moving into damagedHandler
	if (unit->IsMorphing() && (unit->GetUnit()->GetHealth() < unit->GetUnit()->GetMaxHealth() * 0.5f)) {
		unit->StopUpgrade();  // StopMorph();
		AddMorphee(unit);
	}

	return 0; //signaling: OK
}

int CEconomyManager::UnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	auto search = destroyedHandler.find(unit->GetCircuitDef()->GetId());
	if (search != destroyedHandler.end()) {
		search->second(unit, attacker);
	}

	return 0; //signaling: OK
}

float CEconomyManager::GetMetalMake(CCircuitDef* cdef) const
{
	if (cdef->IsMex()) {
		return circuit->GetMetalManager()->GetSpotAvgIncome() * cdef->GetExtractsM();
	}
	const SConvertExt* convertExt = convertDefs.GetAvailInfo(cdef);
	return (convertExt == nullptr) ? 0.f : convertExt->make;
}

float CEconomyManager::GetEnergyMake(CCircuitDef* cdef) const
{
	if (cdef->GetDef()->IsNeedGeo()) {
		const SGeoExt* geoExt = geoDefs.GetAvailInfo(cdef);
		return (geoExt == nullptr) ? 0.f : geoExt->make;
	}
	const SEnergyExt* energyExt = energyDefs.GetAvailInfo(cdef);
	return (energyExt == nullptr) ? 0.f : energyExt->make;
}

CCircuitDef* CEconomyManager::GetLowEnergy(const AIFloat3& pos, float& outMake, const CCircuitUnit* builder) const
{
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const int frame = circuit->GetLastFrame();
	return energyDefs.GetWorstDef([frame, builder, terrainMgr, &pos, &outMake](CCircuitDef* cdef, const SEnergyExt& data) {
		if (!data.isOld && cdef->IsAvailable(frame)
			&& ((builder == nullptr) || builder->GetCircuitDef()->CanBuild(cdef))
			&& terrainMgr->CanBeBuiltAtSafe(cdef, pos))
		{
			outMake = data.make;
			return true;
		}
		return false;
	});
}

void CEconomyManager::AddEconomyDefs(const std::set<CCircuitDef*>& buildDefs)
{
	metalDefs.AddDefs(buildDefs);
	convertDefs.AddDefs(buildDefs);
	energyDefs.AddDefs(buildDefs);
	geoDefs.AddDefs(buildDefs);
	storeMDefs.AddDefs(buildDefs);
	storeEDefs.AddDefs(buildDefs);
	airpadDefs.AddDefs(buildDefs);
	assistDefs.AddDefs(buildDefs);
	factoryDefs.AddDefs(buildDefs);

	// DEBUG
//	circuit->LOG("----Metal----");
//	for (const auto& mi : metalDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | speed=%f | efficiency=%f", mi.cdef->GetDef()->GetName(),
//				mi.cdef->GetCostM(), mi.cdef->GetCostE(), mi.data.speed, mi.score);
//	}
//	circuit->LOG("----Converter----");
//	for (const auto& ci : convertDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | make=%f | efficiency=%f", ci.cdef->GetDef()->GetName(),
//				ci.cdef->GetCostM(), ci.cdef->GetCostE(), ci.data.make, ci.score);
//	}
//	circuit->LOG("----Energy----");
//	for (const auto& ei : energyDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | make=%f | efficiency=%f | limit=%i | m-income=%f | e-income=%f", ei.cdef->GetDef()->GetName(),
//				ei.cdef->GetCostM(), ei.cdef->GetCostE(), ei.data.make, ei.data.cond.score, ei.data.cond.limit, ei.data.cond.metalIncome, ei.data.cond.energyIncome);
//	}
//	circuit->LOG("----Geo----");
//	for (const auto& ci : geoDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | make=%f | efficiency=%f", ci.cdef->GetDef()->GetName(),
//				ci.cdef->GetCostM(), ci.cdef->GetCostE(), ci.data.make, ci.score);
//	}
//	std::vector<std::pair<std::string, CAvailList<SStoreExt>*>> vec = {{"Metal", &storeMDefs}, {"Energy", &storeEDefs}};
//	for (const auto& kv : vec) {
//		circuit->LOG("----%s Storage----", kv.first.c_str());
//		for (const auto& si : kv.second->GetInfos()) {
//			circuit->LOG("%s | costM=%f | costE=%f | storage=%f", si.cdef->GetDef()->GetName(),
//					si.cdef->GetCostM(), si.cdef->GetCostE(), si.data.storage);
//		}
//	}
//	circuit->LOG("----Airpad----");
//	for (const auto& pi : airpadDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | build_speed=%f | efficiency=%f", pi.cdef->GetDef()->GetName(),
//				pi.cdef->GetCostM(), pi.cdef->GetCostE(), pi.cdef->GetBuildSpeed(), pi.score);
//	}
//	circuit->LOG("----Assist----");
//	for (const auto& ni : assistDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | build_speed=%f | efficiency=%f", ni.cdef->GetDef()->GetName(),
//				ni.cdef->GetCostM(), ni.cdef->GetCostE(), ni.cdef->GetBuildSpeed(), ni.score);
//	}
//	circuit->LOG("----Factory----");
//	for (const auto& fi : factoryDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | build_speed=%f | efficiency=%f", fi.cdef->GetDef()->GetName(),
//				fi.cdef->GetCostM(), fi.cdef->GetCostE(), fi.cdef->GetBuildSpeed(), fi.score);
//	}
}

void CEconomyManager::RemoveEconomyDefs(const std::set<CCircuitDef*>& buildDefs)
{
	metalDefs.RemoveDefs(buildDefs);
	convertDefs.RemoveDefs(buildDefs);
	energyDefs.RemoveDefs(buildDefs);
	geoDefs.RemoveDefs(buildDefs);
	storeMDefs.RemoveDefs(buildDefs);
	storeEDefs.RemoveDefs(buildDefs);
	airpadDefs.RemoveDefs(buildDefs);
	assistDefs.RemoveDefs(buildDefs);
	factoryDefs.RemoveDefs(buildDefs);

	// DEBUG
//	circuit->LOG("----Remove Metal----");
//	for (const auto& mi : metalDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | speed=%f | efficiency=%f", mi.cdef->GetDef()->GetName(),
//				mi.cdef->GetCostM(), mi.cdef->GetCostE(), mi.data.speed, mi.score);
//	}
//	circuit->LOG("----Remove Converter----");
//	for (const auto& ci : convertDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | make=%f | efficiency=%f", ci.cdef->GetDef()->GetName(),
//				ci.cdef->GetCostM(), ci.cdef->GetCostE(), ci.data.make, ci.score);
//	}
//	circuit->LOG("----Remove Energy----");
//	for (const auto& ei : energyDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | make=%f | efficiency=%f | limit=%i", ei.cdef->GetDef()->GetName(),
//				ei.cdef->GetCostM(), ei.cdef->GetCostE(), ei.data.make, ei.data.cond.score, ei.data.cond.limit);
//	}
//	circuit->LOG("----Remove Geo----");
//	for (const auto& ci : geoDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | make=%f | efficiency=%f", ci.cdef->GetDef()->GetName(),
//				ci.cdef->GetCostM(), ci.cdef->GetCostE(), ci.data.make, ci.score);
//	}
//	std::vector<std::pair<std::string, CAvailList<SStoreExt>*>> vec = {{"Metal", &storeMDefs}, {"Energy", &storeEDefs}};
//	for (const auto& kv : vec) {
//		circuit->LOG("----Remove %s Storage----", kv.first.c_str());
//		for (const auto& si : kv.second->GetInfos()) {
//			circuit->LOG("%s | costM=%f | costE=%f | storage=%f", si.cdef->GetDef()->GetName(),
//					si.cdef->GetCostM(), si.cdef->GetCostE(), si.data.storage);
//		}
//	}
//	circuit->LOG("----Remove Airpad----");
//	for (const auto& pi : airpadDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | build_speed=%f | efficiency=%f", pi.cdef->GetDef()->GetName(),
//				pi.cdef->GetCostM(), pi.cdef->GetCostE(), pi.cdef->GetBuildSpeed(), pi.score);
//	}
//	circuit->LOG("----Remove Assist----");
//	for (const auto& ni : assistDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | build_speed=%f | efficiency=%f", ni.cdef->GetDef()->GetName(),
//				ni.cdef->GetCostM(), ni.cdef->GetCostE(), ni.cdef->GetBuildSpeed(), ni.score);
//	}
//	circuit->LOG("----Remove Factory----");
//	for (const auto& fi : factoryDefs.GetInfos()) {
//		circuit->LOG("%s | costM=%f | costE=%f | build_speed=%f | efficiency=%f", fi.cdef->GetDef()->GetName(),
//				fi.cdef->GetCostM(), fi.cdef->GetCostE(), fi.cdef->GetBuildSpeed(), fi.score);
//	}
}

const CEconomyManager::SSideInfo& CEconomyManager::GetSideInfo() const
{
	return sideInfos[circuit->GetSideId()];
}

float CEconomyManager::GetMetalCur()
{
	return metal.current = economy->GetCurrent(metalRes);
}

float CEconomyManager::GetMetalStore()
{
	return metal.storage = GetStorage(metalRes);
}

float CEconomyManager::GetMetalPull()
{
	if (metal.pullFrame/* + TEAM_SLOWUPDATE_RATE*/ < circuit->GetLastFrame()) {
		metal.pullFrame = circuit->GetLastFrame();
		metal.pull = economy->GetPull(metalRes) + circuit->GetTeam()->GetRulesParamFloat("extraMetalPull", 0.f);
		if (metalPullCorFrame + TEAM_SLOWUPDATE_RATE < circuit->GetLastFrame()) {
			metalPullCorFrame = -1;
			metalPullCor = 0.f;
		}
	}
	return metal.pull;
}

float CEconomyManager::GetEnergyCur()
{
	return energy.current = economy->GetCurrent(energyRes);
}

float CEconomyManager::GetEnergyStore()
{
	return energy.storage = GetStorage(energyRes);
}

float CEconomyManager::GetEnergyPull()
{
	if (energy.pullFrame/* + TEAM_SLOWUPDATE_RATE*/ < circuit->GetLastFrame()) {
		energy.pullFrame = circuit->GetLastFrame();
		float extraEnergyPull = circuit->GetTeam()->GetRulesParamFloat("extraEnergyPull", 0.f);
//		float oddEnergyOverdrive = circuit->GetTeam()->GetRulesParamFloat("OD_energyOverdrive", 0.f);
//		float oddEnergyChange = circuit->GetTeam()->GetRulesParamFloat("OD_energyChange", 0.f);
//		float extraChange = std::min(.0f, oddEnergyChange) - std::min(.0f, oddEnergyOverdrive);
//		float teamEnergyWaste = circuit->GetTeam()->GetRulesParamFloat("OD_team_energyWaste", 0.f);
//		float numAllies = circuit->GetTeam()->GetRulesParamFloat("OD_allies", 1.f);
//		if (numAllies < 1.f) {
//			numAllies = 1.f;
//		}
		energy.pull = economy->GetPull(energyRes) + extraEnergyPull/* + extraChange - teamEnergyWaste / numAllies*/;
		if (energyPullCorFrame + TEAM_SLOWUPDATE_RATE < circuit->GetLastFrame()) {
			energyPullCorFrame = -1;
			energyPullCor = 0.f;
		}
	}
	return energy.pull;
}

bool CEconomyManager::IsAllyOpenMexSpot(int spotId) const
{
	return IsOpenMexSpot(spotId) && circuit->GetMetalManager()->IsOpenSpot(spotId);
}

bool CEconomyManager::IsOpenMexSpot(int spotId) const
{
	if (!IsValidMexSpot(spotId)) {
		return false;
	}
	return mexSpots[spotId].isOpen && ((isAllyMexMax ? circuit->GetMetalManager()->GetMexCount() : mexCount) < mexMax);
}

void CEconomyManager::SetOpenMexSpot(int spotId, bool value)
{
	if (!IsValidMexSpot(spotId)) {
		return;
	}
	if (mexSpots[spotId].isOpen == value) {
		return;
	}
	mexSpots[spotId].isOpen = value;
	value ? --mexCount : ++mexCount;
}

// apex: the spot queries a script can reach. Script had no way to name a metal
// spot, so a reroute could only trade between MEX tasks the engine had already
// created.
int CEconomyManager::FindOpenMexSpot(CCircuitUnit* unit, const AIFloat3& pos, float maxThreat)
{
	CMetalManager* metalMgr = circuit->GetMetalManager();
	if ((unit == nullptr) || !metalMgr->HasMetalSpots()
		|| !metalMgr->IsInitialized() || metalMgr->IsClusterizing())
	{
		return -1;
	}

	const int frame = circuit->GetLastFrame();
	std::vector<CCircuitDef*> mexDefs;
	for (CCircuitDef* mDef : metalDefs.GetBuildDefs(unit->GetCircuitDef())) {
		if (mDef->IsAvailable(frame)) {
			mexDefs.push_back(mDef);
		}
	}
	if (mexDefs.empty()) {
		return -1;
	}

	// CanReachAtSafe reads whichever threat layer was selected last. The builder
	// manager sets it before its own picks; nothing does on the script path.
	circuit->GetThreatMap()->SetThreatType(unit);

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const CMetalData::Metals& spots = metalMgr->GetSpots();
	CMap* map = circuit->GetMap();
	// apex: the threat ceiling is the CALLER's. CanReachAtSafe defaults to
	// THREAT_MIN (1.0), which hides every contested spot -- so the mex want
	// went silent exactly when the enemy was on the map and metal shortest.
	CMetalData::PointPredicate predicate = [this, &spots, map, &mexDefs, terrainMgr, unit, maxThreat](int index) {
		const AIFloat3& p = spots[index].position;
		if (IsAllyOpenMexSpot(index) && !terrainMgr->IsZoneAlly(p)
			&& terrainMgr->CanReachAtSafe(unit, p, unit->GetCircuitDef()->GetBuildDistance(), maxThreat))
		{
			for (CCircuitDef* mDef : mexDefs) {
				if (terrainMgr->CanBeBuiltAt(mDef, p)
					&& map->IsPossibleToBuildAt(mDef->GetDef(), p, UNIT_NO_FACING))
				{
					return true;
				}
			}
		}
		return false;
	};
	int idx = metalMgr->GetSpotToBuild(pos, predicate);

	// apexearth 2026-08-22: "our cons that go out and get mexes sometimes choose
	// to go to far away mexes instead of the mexes that are closest to where
	// they are." GetSpotToBuild walks the CLUSTER graph, commits to one cluster,
	// and then takes the nearest spot INSIDE it -- so an open spot in a
	// neighbouring cluster that is physically nearer is never a candidate. The
	// predicate is the same reachability/threat/buildability test, so a spot it
	// accepts is equally valid; sweep for one that is genuinely closer.
	// Spot counts are in the tens and a mex is ordered a few times a minute, so
	// the extra predicate calls are not on any hot path.
	if (circuit->GetTunable("apex_mex_nearest", 0.f) > 0.f) {
		float bestSq = (idx >= 0)
				? spots[idx].position.SqDistance2D(pos)
				: std::numeric_limits<float>::max();
		for (unsigned i = 0; i < spots.size(); ++i) {
			const float sqd = spots[i].position.SqDistance2D(pos);
			if (sqd >= bestSq) {
				continue;
			}
			if (!predicate(i)) {
				continue;
			}
			bestSq = sqd;
			idx = (int)i;
		}
	}
	return idx;
}

AIFloat3 CEconomyManager::GetMexSpotPos(int spotId) const
{
	CMetalManager* metalMgr = circuit->GetMetalManager();
	if (!metalMgr->IsValidSpot(spotId)) {
		return -RgtVector;
	}
	return metalMgr->GetSpots()[spotId].position;
}

IBuilderTask* CEconomyManager::EnqueueMexAt(CCircuitUnit* unit, int spotId)
{
	CMetalManager* metalMgr = circuit->GetMetalManager();
	if ((unit == nullptr) || !metalMgr->IsValidSpot(spotId) || !IsAllyOpenMexSpot(spotId)) {
		return nullptr;
	}

	const AIFloat3& pos = metalMgr->GetSpots()[spotId].position;
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CMap* map = circuit->GetMap();
	const int frame = circuit->GetLastFrame();
	CCircuitDef* mexDef = nullptr;
	for (CCircuitDef* mDef : metalDefs.GetBuildDefs(unit->GetCircuitDef())) {
		if (mDef->IsAvailable(frame) && terrainMgr->CanBeBuiltAt(mDef, pos)
			&& map->IsPossibleToBuildAt(mDef->GetDef(), pos, UNIT_NO_FACING))
		{
			mexDef = mDef;
			break;
		}
	}
	if (mexDef == nullptr) {
		return nullptr;
	}
	return circuit->GetBuilderManager()->Enqueue(TaskB::Spot(IBuilderTask::BuildType::MEX,
			IBuilderTask::Priority::HIGH, mexDef, pos, spotId));
}

// apex: the position of a geo spot by id, across the init-parsed shared list
// and this instance's late discoveries.
const AIFloat3& CEconomyManager::GeoSpotPos(int spotId) const
{
	const CEnergyData::Geos& geos = circuit->GetEnergyManager()->GetSpots();
	return ((size_t)spotId < geos.size()) ? geos[spotId]
			: lateGeoSpots[spotId - geos.size()];
}

// apex: re-scan for vents the init parse could not see. GetFeatures() is
// LOS-limited, and ParseGeoSpots runs once at AI birth -- before scouting --
// so vents outside the start area never existed as spots. Appends only; the
// shared CEnergyData stays untouched (other instances read it concurrently).
void CEconomyManager::RescanGeoSpots()
{
	const int frame = circuit->GetLastFrame();
	if (frame < nextGeoRescan) {
		return;
	}
	nextGeoRescan = frame + FRAMES_PER_SEC * 120;
	CCircuitDef* geoDef = GetSideInfo().geoDef;
	if (geoDef == nullptr) {
		return;
	}
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const unsigned width = circuit->GetMap()->GetWidth();
	const unsigned height = circuit->GetMap()->GetHeight();
	const int xsize = geoDef->GetDef()->GetXSize();
	const int zsize = geoDef->GetDef()->GetZSize();
	std::vector<Feature*> features = circuit->GetCallback()->GetFeatures();
	for (Feature* feature : features) {
		FeatureDef* featDef = feature->GetDef();
		const bool isGeo = featDef->IsGeoThermal();
		delete featDef;
		if (!isGeo) {
			continue;
		}
		AIFloat3 pos = feature->GetPosition();
		const unsigned x1 = int(pos.x) / SQUARE_SIZE - (xsize / 2), x2 = x1 + xsize;
		const unsigned z1 = int(pos.z) / SQUARE_SIZE - (zsize / 2), z2 = z1 + zsize;
		if (!((x1 < x2) && (x2 < width) && (z1 < z2) && (z2 < height))
			|| !terrainMgr->CanBeBuiltAt(geoDef, pos))
		{
			continue;
		}
		bool known = false;
		const CEnergyData::Geos& geos = circuit->GetEnergyManager()->GetSpots();
		for (const AIFloat3& p : geos) {
			if (utils::is_equal_pos(p, pos)) { known = true; break; }
		}
		for (size_t i = 0; !known && (i < lateGeoSpots.size()); ++i) {
			if (utils::is_equal_pos(lateGeoSpots[i], pos)) { known = true; }
		}
		if (!known) {
			lateGeoSpots.push_back(pos);
			geoSpots.push_back({true, false});
		}
	}
	utils::free_clear(features);
}

// apex: geo spot queries a script can call safely, mirroring the mex trio
// above. Deliberately no IsZoneAlly exclusion -- a geo vent at home is a
// normal HomeEnergy candidate, not a frontier-only reroute.
int CEconomyManager::FindOpenGeoSpot(CCircuitUnit* unit, const AIFloat3& pos)
{
	if (unit == nullptr) {
		return -1;
	}
	RescanGeoSpots();
	const int frame = circuit->GetLastFrame();
	std::vector<CCircuitDef*> geoCands;
	for (CCircuitDef* gDef : geoDefs.GetBuildDefs(unit->GetCircuitDef())) {
		if (gDef->IsAvailable(frame)) {
			geoCands.push_back(gDef);
		}
	}
	if (geoCands.empty()) {
		return -1;
	}

	// CanReachAtSafe reads whichever threat layer was selected last, same as
	// FindOpenMexSpot.
	circuit->GetThreatMap()->SetThreatType(unit);

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CMap* map = circuit->GetMap();
	float minDistSq = std::numeric_limits<float>::max();
	int index = -1;
	for (unsigned i = 0; i < geoSpots.size(); ++i) {
		if (!IsOpenGeoSpot(i)) {
			continue;
		}
		const AIFloat3& p = GeoSpotPos(i);
		const float distSq = p.SqDistance2D(pos);
		if (minDistSq <= distSq) {
			continue;
		}
		if (!terrainMgr->CanReachAtSafe(unit, p, unit->GetCircuitDef()->GetBuildDistance())) {
			continue;
		}
		for (CCircuitDef* gDef : geoCands) {
			if (terrainMgr->CanBeBuiltAt(gDef, p) && map->IsPossibleToBuildAt(gDef->GetDef(), p, UNIT_NO_FACING)) {
				minDistSq = distSq;
				index = i;
				break;
			}
		}
	}
	return index;
}

AIFloat3 CEconomyManager::GetGeoSpotPos(int spotId) const
{
	if (!IsValidGeoSpot(spotId)) {
		return -RgtVector;
	}
	return circuit->GetEnergyManager()->GetSpots()[spotId];
}

IBuilderTask* CEconomyManager::EnqueueGeoAt(CCircuitUnit* unit, int spotId)
{
	if ((unit == nullptr) || !IsValidGeoSpot(spotId) || !IsOpenGeoSpot(spotId)) {
		return nullptr;
	}
	const AIFloat3& pos = GeoSpotPos(spotId);
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CMap* map = circuit->GetMap();
	const int frame = circuit->GetLastFrame();
	CCircuitDef* geoDef = nullptr;
	for (CCircuitDef* gDef : geoDefs.GetBuildDefs(unit->GetCircuitDef())) {
		if (gDef->IsAvailable(frame) && terrainMgr->CanBeBuiltAt(gDef, pos)
			&& map->IsPossibleToBuildAt(gDef->GetDef(), pos, UNIT_NO_FACING))
		{
			geoDef = gDef;
			break;
		}
	}
	if (geoDef == nullptr) {
		return nullptr;
	}
	return circuit->GetBuilderManager()->Enqueue(TaskB::Spot(IBuilderTask::BuildType::GEO,
			IBuilderTask::Priority::NORMAL, geoDef, pos, spotId));
}

bool CEconomyManager::IsIgnorePull(const IBuilderTask* task) const
{
	if (mexMax != std::numeric_limits<decltype(mexMax)>::max()) {
		return false;
	}
	return ((task->GetBuildType() == IBuilderTask::BuildType::MEX) ||
			(task->GetBuildType() == IBuilderTask::BuildType::PYLON));
}

bool CEconomyManager::IsIgnoreStallingPull(const IBuilderTask* task) const
{
//	if (mexMax != std::numeric_limits<decltype(mexMax)>::max()) {
//		return false;  // NOTE: may completely block expansion
//	}
	if ((task->GetBuildType() == IBuilderTask::BuildType::MEX) ||
		(task->GetBuildType() == IBuilderTask::BuildType::PYLON))
	{
		return true;
	}
	return ((task->GetBuildType() == IBuilderTask::BuildType::ENERGY) &&
			circuit->GetEconomyManager()->IsEnergyStalling());
}

void CEconomyManager::CorrectResourcePull(float metal, float energy)
{
	metalPullCor += metal;
	if (metalPullCorFrame == -1) {
		metalPullCorFrame = circuit->GetLastFrame();
	}
	energyPullCor += energy;
	if (energyPullCorFrame == -1) {
		energyPullCorFrame = circuit->GetLastFrame();
	}
}

bool CEconomyManager::IsEnoughEnergy(IBuilderTask const* task, CCircuitDef const* conDef, float mod) const
{
	// NOTE: Doesn't count time to travel and high priority.
	//       invAvailFraction is for equal distribution.
	if (task->GetBuildType() == IBuilderTask::BuildType::ENERGY) {
		return true;
	}
	CCircuitDef const* buildDef = task->GetBuildDef();
	const float buildTime = buildDef->GetBuildTime() / conDef->GetWorkerTime();
	const float deficit = metal.current - ((GetMetalPullCor() - GetAvgMetalIncome()) * buildTime + buildDef->GetCostM());
	if (deficit >= 0.f) {
		return energy.current > (GetEnergyPullCor() - GetAvgEnergyIncome()) * buildTime + buildDef->GetCostE() * mod;
	}
	const float miRequire = buildDef->GetCostM() / buildTime;
	const float timeToDeficit = metal.current / (GetMetalPullCor() + miRequire - GetAvgMetalIncome());
	const float deficitTime = buildTime - timeToDeficit;
	const float invAvailFraction = (GetMetalPullCor() + miRequire) / GetAvgMetalIncome();
	const float eiRequire = buildDef->GetCostE() / buildTime * mod;
	return energy.current > (GetEnergyPullCor() + eiRequire - GetAvgEnergyIncome()) * timeToDeficit
			+ (GetEnergyPullCor() + eiRequire - GetAvgEnergyIncome() * invAvailFraction) * deficitTime;
}

IBuilderTask* CEconomyManager::MakeEconomyTasks(const AIFloat3& position, CCircuitUnit* unit)
{
	ZoneScoped;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask()) {
		return nullptr;
	}
	CMetalManager* metalMgr = circuit->GetMetalManager();
	int index = metalMgr->FindNearestCluster(position);
	if (index >= 0) {
		if (clusterInfos[index].metalFrame + FRAMES_PER_SEC >= circuit->GetLastFrame()) {
			return nullptr;
		}
		clusterInfos[index].metalFrame = circuit->GetLastFrame();
	}

	IBuilderTask* task = UpdateMetalTasks(position, unit);
	if (task != nullptr) {
		return task;
	}

	return task;
}

IBuilderTask* CEconomyManager::UpdateMetalTasks(const AIFloat3& position, CCircuitUnit* unit)
{
	assert(unit != nullptr);
	ZoneScoped;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask(16)) {
		return nullptr;
	}

	// NOTE: do not "improve" this by letting mex upgrades pre-empt the stall.
	// Tried exactly that -- on the reasoning that a 4x extractor is a better
	// answer than another solar -- and it lost 1-7. The short-circuit is load
	// bearing: skipping it means the stall is never fixed, and an upgrade needs
	// energy to build, so the AI stalls out with upgrades queued and no power to
	// run them. The mex/energy ordering is not the reason the tech lead fails to
	// snowball.
	if (IsEnergyStalling()) {
		return UpdateEnergyTasks(position, unit);
	}

	IBuilderTask* task = nullptr;
	const int frame = circuit->GetLastFrame();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();

	// HOW MANY UPGRADES MAY BE IN FLIGHT IS AN ECONOMY QUESTION, NOT A CONSTANT.
	//
	// apexearth: "limit on upgrades can be based on how many advanced cons we
	// have and how wealthy we are... if we don't have any upgraded mexes and
	// we're poor then wow upgrading a mex is priority #1."
	//
	// The config cap is 4, and it is the supply limit on the whole thing: only
	// an advanced constructor can build a moho, we field dozens of them with a
	// full bank, and the engine would still only ever create four upgrades.
	// Measured: T2 mexes flat at 11-13% of mexes held across three arms that
	// each changed something DOWNSTREAM of the offer.
	unsigned mexUpCap = numMexUp;
	const float mInc = GetAvgMetalIncome();
	const float perInc = circuit->GetTunable("apex_mexup_per_income", 25.f);
	if (perInc > .0f) {
		mexUpCap = std::max(mexUpCap, unsigned(mInc / perInc));
	}
	if (IsMetalFull()) {
		mexUpCap += unsigned(circuit->GetTunable("apex_mexup_full_bonus", 4.f));
	}
	// Nothing upgraded yet is the case he called priority #1: allow a burst even
	// on a poor economy, since the upgrade is what ENDS being poor.
	// "Upgraded" = we hold an extractor that is not the cheapest one available.
	// metalDefs holds every extractor def; the base tier is the least
	// extraction among them.
	float minExtract = std::numeric_limits<float>::max();
	float baseExtract = std::numeric_limits<float>::max();
	for (CCircuitDef* md : metalDefs.GetAll()) {
		if (md != nullptr) {
			baseExtract = std::min(baseExtract, md->GetExtractsM());
			minExtract = baseExtract;
		}
	}
	bool anyUpgraded = false;
	for (CCircuitDef* md : metalDefs.GetAll()) {
		if ((md != nullptr) && (md->GetCount() > 0) && (md->GetExtractsM() > baseExtract)) {
			anyUpgraded = true;
			break;
		}
	}
	if (!anyUpgraded) {
		mexUpCap = std::max(mexUpCap, unsigned(circuit->GetTunable("apex_mexup_first", 3.f)));
	}

	if ((builderMgr->GetTasks(IBuilderTask::BuildType::MEXUP).size() < mexUpCap) && (mInc > 10.f)) {
		const std::vector<CCircuitDef*>& mexDefOptions = metalDefs.GetBuildDefs(unit->GetCircuitDef());
		std::vector<std::pair<CCircuitDef*, float>> mexDefs;
		float maxRange = 0.f;
		for (auto it = mexDefOptions.begin(); it != mexDefOptions.end(); ++it) {
			CCircuitDef* mDef = *it;
			if (mDef->IsAvailable(frame)) {
				mexDefs.push_back(std::make_pair(mDef, mDef->GetExtractsM()));
				const float range = mDef->GetExtrRangeM();
				if (maxRange < range) {
					maxRange = range;
				}
			}
		}
		if (!mexDefs.empty()) {
			CMetalManager* metalMgr = circuit->GetMetalManager();
			const CMetalData::Metals& spots = metalMgr->GetSpots();
			CCircuitDef* mexDef = nullptr;
			// WHY a spot is rejected, counted. Three arms changed things downstream
			// of this predicate and moved T2 mex share by ~1 point each; nothing has
			// ever measured which clause here says no.
			int rejUpgrading = 0, rejReach = 0, rejNotOurs = 0, rejNoBetter = 0, accepted = 0;
			CMetalData::PointPredicate predicate = [this, &spots, &mexDefs, maxRange, terrainMgr, unit, &mexDef,
					&rejUpgrading, &rejReach, &rejNotOurs, &rejNoBetter, &accepted](int index) {
				const AIFloat3& pos = spots[index].position;
				if (IsUpgradingMexSpot(index)) {
					++rejUpgrading;
					return false;
				}
				if (!terrainMgr->CanReachAtSafe(unit, pos, unit->GetCircuitDef()->GetBuildDistance())) {
					++rejReach;
					return false;
				}
				{
					const auto& unitIds = circuit->GetCallback()->GetFriendlyUnitIdsIn(pos, maxRange, false);
					float curExtract = -1.f;
					for (ICoreUnit::Id unitId : unitIds) {
						// apex: OWN-team, not ally-wide. An ally's extractor
						// satisfied "a mex here yields less than what I can
						// build" -- Legion's legmex extracts 0.0008 against
						// 0.001 for arm/cormex, and any moho outyields every
						// ally T1 -- so a MEXUP task was enqueued on ground we
						// do not own. It can never complete: Execute() cannot
						// place over their extractor, and its reclaim fallback
						// resolves the occupant through GetTeamUnit(), which is
						// null for another team. The task then pins one of the
						// mex_up slots and marks the spot upgrading, so real
						// upgrades starve. Measured: MEXUP pinned at the cap of
						// 4 for 237 of 291 samples with nothing upgraded.
						CCircuitUnit* curMex = circuit->GetTeamUnit(unitId);
						if (curMex == nullptr) {
							continue;
						}
						const float extract = curMex->GetCircuitDef()->GetExtractsM();
						if (curExtract < extract) {
							curExtract = extract;
						}
					}
					if (curExtract <= 0.f) {
						++rejNotOurs;
						return false;
					}
					for (const auto& pair : mexDefs) {
						if ((curExtract < pair.second) && terrainMgr->CanBeBuiltAt(pair.first, pos)) {
							mexDef = pair.first;
							++accepted;
							return true;
						}
					}
					++rejNoBetter;
				}
				return false;
			};
//			const AIFloat3& searchPos = circuit->GetSetupManager()->GetBasePos();
			// SEARCH OUR OWN EXTRACTORS, NOT THE WHOLE MAP.
			//
			// GetSpotToUpgrade walks metal spots from `position` and asks the
			// predicate about each. Measured with the counters below, over four
			// 8v8 games and only for builders that CAN upgrade: 89.6% of spots
			// examined were rejected as notOurs, acceptance was 0.1%, and mean
			// upgrades in flight were 1.3 against a cap of 13.9. The cap was
			// never the limit -- the search almost never lands on one of ours.
			//
			// We know exactly which extractors are ours: they are in teamUnits.
			// Walk those first and take the nearest that a better def out-yields.
			int index = -1;
			{
				float bestDist = std::numeric_limits<float>::max();
				for (const auto& kv : circuit->GetTeamUnits()) {
					CCircuitUnit* u = kv.second;
					if ((u == nullptr) || (u->GetCircuitDef() == nullptr) || !u->GetCircuitDef()->IsMex()) {
						continue;
					}
					const float have = u->GetCircuitDef()->GetExtractsM();
					bool better = false;
					for (const auto& pair : mexDefs) {
						if (have < pair.second) {
							better = true;
							break;
						}
					}
					if (!better) {
						continue;
					}
					const AIFloat3& upos = u->GetPos(frame);
					const int idx = metalMgr->FindNearestSpot(upos);
					if ((idx < 0) || IsUpgradingMexSpot(idx)) {
						continue;
					}
					if (!terrainMgr->CanReachAtSafe(unit, spots[idx].position,
							unit->GetCircuitDef()->GetBuildDistance())) {
						continue;
					}
					const float d = position.SqDistance2D(spots[idx].position);
					if (d < bestDist) {
						bestDist = d;
						index = idx;
						for (const auto& pair : mexDefs) {
							if ((have < pair.second) && terrainMgr->CanBeBuiltAt(pair.first, spots[idx].position)) {
								mexDef = pair.first;
								break;
							}
						}
					}
				}
			}
			// Fall back to the map-wide search only when we own nothing worth
			// upgrading, so nothing that used to work stops working.
			if ((index == -1) || (mexDef == nullptr)) {
				index = metalMgr->GetSpotToUpgrade(/*searchPos*/position, predicate);
			}
			// ONLY COUNT BUILDERS THAT COULD UPGRADE ANYTHING. mexDefs holds the
			// extractor defs THIS unit can build; a T1 constructor's list is the
			// base tier alone, so every spot it looks at is "no better def" or
			// "not ours" and it can never succeed. Counting those buried the
			// advanced constructors' own numbers under 43,000 impossible calls.
			const bool canUpgrade = (mexDefs.size() > 1)
					|| ((mexDefs.size() == 1) && (mexDefs.front().second > minExtract));
			if (canUpgrade && (circuit->GetLastFrame() > mexUpDiagFrame)) {
				mexUpDiagFrame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
				circuit->LOG("apex: mexup-spots cap=%u inflight=%u | upgrading=%d unreach=%d notOurs=%d noBetter=%d ok=%d",
						mexUpCap, (unsigned)builderMgr->GetTasks(IBuilderTask::BuildType::MEXUP).size(),
						rejUpgrading, rejReach, rejNotOurs, rejNoBetter, accepted);
			}
			builderMgr->SetCanUpMex(unit->GetCircuitDef(), index != -1);
			if (index != -1) {
				const AIFloat3& pos = spots[index].position;
				task = builderMgr->Enqueue(TaskB::Spot(IBuilderTask::BuildType::MEXUP,
						IBuilderTask::Priority::HIGH, mexDef, pos, index));
				return task;
			}
		}
	}

	CMetalManager* metalMgr = circuit->GetMetalManager();
	CCircuitDef* mexDef = nullptr;
	const unsigned int mexTaskSize = builderMgr->GetTasks(IBuilderTask::BuildType::MEX).size();
	if (mexTaskSize < (unsigned)mexMax/*builderMgr->GetWorkerCount() * 2 + 1*/
		&& ((GetAvgMetalIncome() < 100.f) || !IsMetalFull())
		&& !builderMgr->CanUpMex(unit->GetCircuitDef()))
	{
		const std::vector<CCircuitDef*>& mexDefOptions = metalDefs.GetBuildDefs(unit->GetCircuitDef());
		std::vector<CCircuitDef*> mexDefs;
		for (CCircuitDef* mDef : mexDefOptions) {
			if (mDef->IsAvailable(frame)) {
				mexDefs.push_back(mDef);
			}
		}
		if (!mexDefs.empty()) {
			const CMetalData::Metals& spots = metalMgr->GetSpots();
			CMap* map = circuit->GetMap();
			// NOTE: threatmap type is set outside
			CMetalData::PointPredicate predicate = [this, &spots, map, &mexDefs, terrainMgr, unit, &mexDef](int index) {
				const AIFloat3& pos = spots[index].position;
				if (IsAllyOpenMexSpot(index) && !terrainMgr->IsZoneAlly(pos)
					&& terrainMgr->CanReachAtSafe(unit, pos, unit->GetCircuitDef()->GetBuildDistance()))  // hostile environment
				{
					for (CCircuitDef* mDef : mexDefs) {
						if (terrainMgr->CanBeBuiltAt(mDef, pos)
							&& map->IsPossibleToBuildAt(mDef->GetDef(), pos, UNIT_NO_FACING))
						{
							mexDef = mDef;
							return true;
						}
					}
				}
				return false;
			};
			int index = metalMgr->GetSpotToBuild(position, predicate);
			if (index != -1) {
				const AIFloat3& pos = spots[index].position;
				task = builderMgr->Enqueue(TaskB::Spot(IBuilderTask::BuildType::MEX,
						IBuilderTask::Priority::HIGH, mexDef, pos, index));
				return task;
			}
		}
	}

	if (convertDefs.HasAvail() && IsEnergyFull() && !IsMetalFull()
		&& (builderMgr->GetTasks(IBuilderTask::BuildType::CONVERT).size() < 2)
		&& ((mexTaskSize == 0) || (builderMgr->GetWorkerCount() > circuit->GetMilitaryManager()->GetGuardTaskNum() + 1)))
	{
		const AIFloat3& pos = circuit->GetSetupManager()->GetMetalBase();
		CCircuitDef* convertDef = convertDefs.GetBestDef([frame, terrainMgr, &pos](CCircuitDef* cdef, const SConvertExt& data) {
			return !data.isOld && cdef->IsAvailable(frame) && terrainMgr->CanBeBuiltAt(cdef, pos);
		});
		if (convertDef != nullptr) {
			// NOTE: Next check may prevent converters even when open mex-spot is far
			//       away in unknown territory.
//			const SConvertExt* convertExt = convertDefs.GetAvailInfo(convertDef);
//			if ((mexDef == nullptr) || (convertExt->make / convertDef->GetCostM() >= metalMgr->GetSpotAvgIncome() * mexDef->GetExtractsM() / mexDef->GetCostM())) {
				task = builderMgr->Enqueue(TaskB::Common(IBuilderTask::BuildType::CONVERT,
										   IBuilderTask::Priority::NORMAL, convertDef, pos, 0.f, true));
				return task;
//			}
		}
	}

	return UpdateReclaimTasks(position, unit);
}

IBuilderTask* CEconomyManager::UpdateReclaimTasks(const AIFloat3& position, CCircuitUnit* unit, bool isNear)
{
	ZoneScoped;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (/*!builderManager->CanEnqueueTask() || */(unit == nullptr) || !unit->GetCircuitDef()->IsAbleToReclaim()) {
		return nullptr;
	}

	bool isResurrect = unit->GetCircuitDef()->IsAbleToResurrect();  // false;
	if (IsMetalFull() || (builderMgr->GetTasks(IBuilderTask::BuildType::RECLAIM).size() >= builderMgr->GetWorkerCount() / 2)) {
//		isResurrect = unit->GetCircuitDef()->IsAbleToResurrect();
		if (!isResurrect) {
			return nullptr;
		}
	}

	std::vector<Feature*> features;
	if (isNear) {
		const float distance = unit->GetCircuitDef()->GetSpeed() * ((GetMetalPull() * 0.8f > GetAvgMetalIncome()) ? 60 : 20);
		features = std::move(circuit->GetCallback()->GetFeaturesIn(position, distance));
	} else {
		features = std::move(circuit->GetCallback()->GetFeatures());
	}
	if (features.empty()) {
		return nullptr;
	}

	COOAICallback* clb = circuit->GetCallback();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 pos;
	float cost = .0f;
	float minSqDist = std::numeric_limits<float>::max();
	for (Feature* feature : features) {
		AIFloat3 featPos = feature->GetPosition();
		CTerrainManager::CorrectPosition(featPos);  // Impulsed flying feature
		if (!terrainMgr->CanReachAtSafe2(unit, featPos, unit->GetCircuitDef()->GetBuildDistance())) {
			continue;
		}
		FeatureDef* featDef;
		if (isResurrect) {
			if (!clb->Feature_IsResurrectable(feature->GetFeatureId())) {
				continue;
			}
			featDef = feature->GetDef();
		} else {
			featDef = feature->GetDef();
			if (!featDef->IsReclaimable()) {
				delete featDef;
				continue;
			}
		}
		float reclaimValue = featDef->GetContainedResource(metalRes)/* * feature->GetReclaimLeft()*/;
		// apexearth: "do not reclaim for energy if we are >20% energy" -- watching
		// constructors chew trees while the enemy took the map. A tree is an
		// ENERGY feature; above this bank it is not worth a constructor-second,
		// and constructor time is what buys mexes.
		const float energyFeat = featDef->GetContainedResource(energyRes);
		delete featDef;
		const float eStore = GetEnergyStore();
		const float eFrac = (eStore > 0.f) ? (GetEnergyCur() / eStore) : 0.f;
		const bool isEnergyFeat = (energyFeat > reclaimValue);
		// apex: constructors are OUT of the energy-reclaim business entirely --
		// the bank-fraction gate still let them chew trees on every dip, and a
		// lathe-second on a tree is a lathe-second not spent on a mex
		// (apexearth 2026-08-21: "cut the importance of energy reclaim on con
		// bots. (rezbots can still do it)"). Resurrect-capable units keep the
		// whole feature set; apex_con_energy_reclaim=1 restores the old gate.
		if (isEnergyFeat && !isResurrect
			&& (circuit->GetTunable("apex_con_energy_reclaim", 0.f) <= 0.f)) {
			continue;
		}
		if (isEnergyFeat && (eFrac > RECLAIM_ENERGY_MAX)) {
			continue;
		}
		// ...and even when the bank IS low, do not WALK for it. The !isNear
		// branch above queries GetFeatures() -- every feature on the map -- so
		// the nearest qualifying tree could be on the far side of the board, and
		// the constructor-seconds spent reaching it dwarf the energy in it.
		// apexearth, watching a 1v1: "I saw 5 cons going far from the base and
		// reclaiming trees (energy)... waste of time... we shouldn't be doing
		// that".
		// Scoped to ENERGY-dominant features on purpose: a field of metal wrecks
		// after a repelled push is worth crossing ground for, and that is this
		// variant's whole plan. A tree is not.
		if (isEnergyFeat) {
			const float maxDist = circuit->GetTunable("apex_reclaim_energy_dist", RECLAIM_ENERGY_DIST);
			if ((maxDist > 0.f) && (position.SqDistance2D(featPos) > SQUARE(maxDist))) {
				continue;
			}
		}
		if (reclaimValue < 1.0f) {
			continue;
		}
		float sqDist = position.SqDistance2D(featPos);
		if (sqDist < minSqDist) {
			pos = featPos;
			cost = reclaimValue;
			minSqDist = sqDist;
		}
	}
	utils::free_clear(features);

	IBuilderTask* task = nullptr;
	if (minSqDist < std::numeric_limits<float>::max()) {
		task = builderMgr->GetReclaimFeatureTask(pos, 8.0f/*unit->GetCircuitDef()->GetBuildDistance()*/);
		if (task != nullptr) {
			return task;
		}
		task = builderMgr->GetResurrectTask(pos, 8.0f/*unit->GetCircuitDef()->GetBuildDistance()*/);
		if (isResurrect) {
			if (task == nullptr) {
				task = builderMgr->Enqueue(TaskB::Resurrect(IBuilderTask::Priority::HIGH, pos, cost, FRAMES_PER_SEC * 300,
										   8.0f/*unit->GetCircuitDef()->GetBuildDistance()*/));
			}
		} else if (task == nullptr) {
			task = builderMgr->Enqueue(TaskB::Reclaim(IBuilderTask::Priority::HIGH, pos, cost, FRAMES_PER_SEC * 300,
									   8.0f/*unit->GetCircuitDef()->GetBuildDistance()*/));
		} else {
			task = nullptr;
		}
	}

	return task;
}

IBuilderTask* CEconomyManager::UpdateEnergyTasks(const AIFloat3& position, CCircuitUnit* unit)
{
	ZoneScoped;

	// DISABLED 2026-08-14: a second, uncoordinated def-picker for energy
	// (economy.json-driven, randomized per-def limits) competing with the
	// AngelScript ladder in HomeEnergy/EnergyValuePerMetal. See CHANGES.md.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask(32)) {
		return nullptr;
	}

	// check energy / metal ratio
	float metalIncome = GetAvgMetalIncome();
	float energyIncome = GetAvgEnergyIncome();
	bool isEnergyStalling = IsEnergyStalling();
	// TODO: e-stalling needs separate array of energy-defs sorted by cost

	// Select proper energy UnitDef to build
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CCircuitDef* bestDef = nullptr;
	CCircuitDef* hopeDef = nullptr;
	metalIncome = std::min(metalIncome, energyIncome) * energyFactor;
	const float buildPower = std::min(builderMgr->GetBuildPower(), metalIncome);
	const int taskSize = builderMgr->GetTasks(IBuilderTask::BuildType::ENERGY).size();
	energyIncome *= isEnergyStalling ? 0.5f : 1.f;
	isEnergyStalling |= isEnergyRequired;
	bool isLastHope = isEnergyStalling;
	const int frame = circuit->GetLastFrame();
	float bestResDist = std::numeric_limits<float>::max();

	// The default energy condition is GetCostE() * costRatio, which for a fusion
	// demands more energy income than the fusion itself produces (corfus: 1300
	// required against ~1000 made) -- so the reason to build one disqualifies it.
	// The metal is the real commitment: corfus is 4500 metal against 26,000
	// energy spread over a 75,400 buildtime, i.e. tens of e/s of actual drain.
	//
	// It cannot simply be lowered. Only a few energy tasks are allowed at once
	// (taskSize below), so an early fusion blocks all other energy for the
	// minutes it takes to finish; dropping this bar to a flat 300 halved metal
	// production and killed the AI at 28 minutes. So relax it with game time
	// instead: unchanged early, when the economy cannot carry the bet, and low
	// later, when build power finishes it quickly and the energy is genuinely
	// needed. apexearth: "diminishing requirements over time perhaps may help".
	const int gateSec = frame / FRAMES_PER_SEC;
	float engyGate = 1.f;
	if (gateSec >= ENERGY_GATE_LOW_SEC) {
		engyGate = ENERGY_GATE_FLOOR;
	} else if (gateSec > ENERGY_GATE_FULL_SEC) {
		const float t = float(gateSec - ENERGY_GATE_FULL_SEC)
				/ float(ENERGY_GATE_LOW_SEC - ENERGY_GATE_FULL_SEC);
		engyGate = 1.f - t * (1.f - ENERGY_GATE_FLOOR);
	}

	const auto& infos = energyDefs.GetInfos();
	const float curWind = circuit->GetMap()->GetCurWind();
	auto checkWind = [curWind, terrainMgr, position, metalIncome, energyIncome, &infos](unsigned i) {
		int lowerIdx = -1;
		for (unsigned j = i + 1; j < infos.size(); ++j) {
			if ((infos[j].data.cond.metalIncome < metalIncome)
				&& (infos[j].data.cond.energyIncome < energyIncome)
				&& terrainMgr->CanBeBuiltAtSafe(infos[j].cdef, position))
			{
				lowerIdx = j;
				break;
			}
		}
		return (lowerIdx < 0) || (SQUARE(curWind) / SQUARE(infos[i].data.make) * infos[i].score > infos[lowerIdx].score);
	};

	for (unsigned i = 0; i < infos.size(); ++i) {  // sorted by high-tech first
		const auto& engy = infos[i];
		if (engy.data.isOld || !engy.cdef->IsAvailable(frame)
			|| !terrainMgr->CanBeBuiltAtSafe(engy.cdef, position))
		{
			continue;
		}

		if (engy.cdef->GetCount() < engy.data.cond.limit) {
			isLastHope = false;
			if (taskSize < (int)(buildPower / engy.cdef->GetCostM() * 4 + 1)) {
				if (engy.cdef->IsWind() && !checkWind(i)) {
					continue;
				}
				if ((engy.data.cond.metalIncome < metalIncome) && (engy.data.cond.energyIncome * engyGate < energyIncome)) {
					bestDef = engy.cdef;
					break;
				} else {
					const float resDist = ((engy.data.cond.metalIncome < metalIncome) ? 0.f : (engy.data.cond.metalIncome - metalIncome))
							+ ((engy.data.cond.energyIncome * engyGate < energyIncome) ? 0.f : GetEcoEM() * (engy.data.cond.energyIncome * engyGate - energyIncome));
					if (bestResDist > resDist) {
						bestResDist = resDist;
						bestDef = engy.cdef;
					}
				}
			} else if ((engy.data.cond.metalIncome < metalIncome)
				&& (engy.data.cond.energyIncome < energyIncome))
			{
				bestDef = nullptr;
				break;
			}
		} else if (!isEnergyStalling) {
			bestDef = nullptr;
			break;
		} else if (hopeDef == nullptr) {
			hopeDef = engy.cdef;
			isLastHope = isLastHope && (taskSize < (int)(buildPower / engy.cdef->GetCostM() * 4 + 1));
		}
	}

	if (isLastHope) {
		bestDef = hopeDef;
	}
	if (bestDef == nullptr) {
		return UpdateGeoTasks(position, unit);
	}

	// Find place to build
	// TODO: Add place finder
	// 1) at very this position
	// 2) near mex
	// 3) at resource base (separate metal / energy)
	// 4) at production base
	CSetupManager* setupMgr = circuit->GetSetupManager();
	AIFloat3 buildPos = -RgtVector;
	if (!bestDef->IsAttrBase()) {
		if (terrainMgr->IsZoneAlly(position)
			|| ((circuit->GetFactoryManager()->GetFactoryCount() > 0) && (position.SqDistance2D(setupMgr->GetSmallEnergyPos()) < SQUARE(600.f))
				&& ((unit == nullptr) || !unit->GetCircuitDef()->IsRoleComm())))  // TODO: instead of isComm check isFast
		{
			buildPos = setupMgr->GetSmallEnergyPos();
		} else {
			buildPos = position + (position - terrainMgr->GetTerrainCenter()).Normalize2D() * (bestDef->GetRadius() + SQUARE_SIZE * 6);  // utils::get_radial_pos(position, bestDef->GetRadius() + SQUARE_SIZE * 6);
		}
		CTerrainManager::CorrectPosition(buildPos);
	} else {
		buildPos = (bestDef->GetCostM() < 1000.0f) ? setupMgr->GetEnergyBase() : setupMgr->GetEnergyBase2();
		CCircuitDef* bdef = (unit == nullptr) ? bestDef : unit->GetCircuitDef();
		buildPos = circuit->GetTerrainManager()->GetBuildPosition(bdef, buildPos);
	}

	if (utils::is_valid(buildPos) && terrainMgr->CanBeBuiltAtSafe(bestDef, buildPos) &&
		((unit == nullptr) || terrainMgr->CanReachAtSafe(unit, buildPos, unit->GetCircuitDef()->GetBuildDistance())))
	{
		IBuilderTask::Priority priority = isEnergyStalling
				? (IsEnergyEmpty() ? IBuilderTask::Priority::NOW : IBuilderTask::Priority::HIGH)
				: IBuilderTask::Priority::NORMAL;
		IBuilderTask* task = builderMgr->Enqueue(TaskB::Common(IBuilderTask::BuildType::ENERGY,
												 priority, bestDef, buildPos, 0.f, true));
		if ((unit == nullptr) || unit->GetCircuitDef()->CanBuild(bestDef)) {
			return task;
		}
	}

	return nullptr;
}

IBuilderTask* CEconomyManager::UpdateGeoTasks(const AIFloat3& position, CCircuitUnit* unit)
{
	ZoneScoped;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask(32) || !builderMgr->GetTasks(IBuilderTask::BuildType::GEO).empty() || !geoDefs.HasAvail()) {
		return nullptr;
	}

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CMap* map = circuit->GetMap();
	CCircuitDef* geoDef = geoDefs.GetFirstDef();
	float minDistSq = std::numeric_limits<float>::max();
	int index = -1;
	for (unsigned i = 0; i < geoSpots.size(); ++i) {
		const AIFloat3& gp = GeoSpotPos(i);
		const float distSq = gp.SqDistance2D(position);
		if (IsOpenGeoSpot(i) && (minDistSq > distSq)
			&& !terrainMgr->IsZoneAlly(gp) && terrainMgr->CanBeBuiltAtSafe(geoDef, gp)
			&& map->IsPossibleToBuildAt(geoDef->GetDef(), gp, UNIT_NO_FACING))  // lazy check for allies
		{
			minDistSq = distSq;
			index = i;
		}
	}
	if (index == -1) {
		return nullptr;
	}

	float metalIncome = GetAvgMetalIncome();
	const float energyIncome = GetAvgEnergyIncome();
	metalIncome = std::min(metalIncome, energyIncome) * energyFactor;
	const float maxCostM = metalIncome * builderMgr->GetGoalExecTime();
	const float maxCostE = energyIncome * builderMgr->GetGoalExecTime();

	const AIFloat3& pos = GeoSpotPos(index);
	const int frame = circuit->GetLastFrame();
	geoDef = geoDefs.GetBestDef([frame, terrainMgr, &pos, maxCostM, maxCostE](CCircuitDef* cdef, const SGeoExt& data) {
		return cdef->IsAvailable(frame) && (cdef->GetCostM() < maxCostM) && (cdef->GetCostE() < maxCostE)
				&& terrainMgr->CanBeBuiltAt(cdef, pos);
	});
	if (geoDef == nullptr) {
		return nullptr;
	}

	return builderMgr->Enqueue(TaskB::Spot(IBuilderTask::BuildType::GEO, IBuilderTask::Priority::NORMAL, geoDef, pos, index));
}

IBuilderTask* CEconomyManager::UpdateFactoryTasks(const AIFloat3& position, CCircuitUnit* unit)
{
	ZoneScoped;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask(64) || isEnergyRequired) {
		return nullptr;
	}

	/*
	 * check air pads
	 */
	{
		IBuilderTask* task = nullptr;
		if (CheckAirpadRequired(position, unit, task)) {
			return task;
		}
	}

	/*
	 * check assist
	 */
	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	const bool isSwitchTime = factoryMgr->IsSwitchTime();
	if (!isSwitchTime) {
		IBuilderTask* task = nullptr;
		if (CheckAssistRequired(position, unit, task)) {
			return task;
		}
	}

	/*
	 * check factory
	 */
	if (!builderMgr->GetTasks(IBuilderTask::BuildType::FACTORY).empty()) {
		return nullptr;
	}

	const bool isStart = (factoryMgr->GetFactoryCount() == 0);
	// apex: RE-ASK THE GATE FOR A HELD PICK. PickNextFactory consults the
	// script's plant gate ONCE, then parks the choice in factoryTask as an
	// inactive task. Activation below is gated on income, not on the gate, so a
	// def approved while we owned no lab was still built minutes later once
	// income crossed miRequire -- which is why a second T1 lab appeared at a
	// consistent ~30 metal/s no matter how often the gate itself was fixed
	// (apexearth, a few dozen reports; ISSUES.md "a sixth gate entrance").
	// The pick is re-validated here so a stale approval cannot outlive the
	// conditions that granted it.
	if (factoryTask != nullptr) {
		CCircuitDef* heldDef = factoryTask->GetBuildDef();
		if ((heldDef != nullptr)
			&& (factoryMgr->GetFactoryToBuild(position, isStart) != heldDef))
		{
			builderMgr->AbortTask(factoryTask);
			factoryTask->ClearRelease();
			factoryTask = nullptr;
		}
	}
	if ((factoryTask == nullptr) && (PickNextFactory(position, isStart) == nullptr)) {
		return nullptr;
	}
	CCircuitDef* facDef = factoryTask->GetBuildDef();
	CCircuitDef* reprDef = factoryTask->GetReprDef();

	/*
	 * check metal and energy levels
	 */
//	const float metalIncome = std::min(GetAvgMetalIncome(), GetAvgEnergyIncome());  // FIXME: ZK
	float miRequire;
	float eiRequire;
	if (isStart && (unit != nullptr)) {
		const float startBuildTime = facDef->GetBuildTime() / unit->GetCircuitDef()->GetWorkerTime();
		miRequire = facDef->GetCostM() / startBuildTime * 0.25f;
		eiRequire = facDef->GetCostE() / startBuildTime;  // * 0.85f;
	} else {
		const float buildTime = reprDef->GetBuildTime() / facDef->GetWorkerTime();
		miRequire = reprDef->GetCostM() / buildTime * factoryMgr->GetNewFacModM();
		eiRequire = reprDef->GetCostE() / buildTime * factoryMgr->GetNewFacModE();
	}
	eiRequire += facDef->GetUpkeepE();
	const float metalFactor = GetAvgMetalIncome() - miRequire/* - builderMgr->GetBuildPower() * 0.2f*/;
	const float engyFactor = (GetAvgEnergyIncome() - eiRequire) * GetEcoEM()/* - builderMgr->GetBuildPower() * 0.2f*/;
	const int nanoQueued = builderMgr->GetTasks(IBuilderTask::BuildType::NANO).size();
	const float factoryPower = factoryMgr->GetMetalRequire() * factoryMgr->GetFacModM() + nanoQueued * factoryMgr->GetAssistSpeed();
	const float energyPower = factoryMgr->GetEnergyRequire() * factoryMgr->GetFacModE() * GetEcoEM() + nanoQueued * factoryMgr->GetAssistSpeed();
	if ((metalFactor < factoryPower) && !isSwitchTime && (isStart || (facDef->GetCostM() > GetMetalCur()))) {
		return nullptr;
	}
	if ((engyFactor < energyPower) || IsEnergyStalling()) {
		isEnergyRequired = true;  // enough metal, request energy
		UpdateEnergyTasks(utils::is_valid(position) ? position : circuit->GetSetupManager()->GetBasePos(), unit);
		return nullptr;
	}
	if (!isStart && !circuit->IsSlave() && !factoryMgr->IsSwitchAllowed(facDef)) {
		return nullptr;
	}

	// desired position
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 buildPos;
	if (factoryTask->IsPlop()) {
		buildPos = -RgtVector;
	} else {
		const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
		const AIFloat3& enemyPos = circuit->GetEnemyManager()->GetEnemyPos();
		float offset = 200.0f;
		if (isStart) {
			buildPos = basePos;
		} else if (facDef->IsRoleSupport()) {
			if (facDef->GetMobileId() < 0) {  // air factory
				buildPos = basePos;
				offset = -200.0f;
			} else {
				int facing;
				buildPos = terrainMgr->GetBusPos(facDef, basePos, facing);
				factoryTask->SetFacing(facing);
				offset = 0.f;
			}
		} else {
			CMetalManager* metalMgr = circuit->GetMetalManager();
			AIFloat3 pos(basePos);
			AIFloat3 center = (pos + enemyPos) * 0.5f;
			float minSqDist = std::numeric_limits<float>::max();
			const CMetalData::Clusters& clusters = metalMgr->GetClusters();
			for (unsigned i = 0; i < clusters.size(); ++i) {
				if (!metalMgr->IsClusterFinished(i)) {
					continue;
				}
				const float sqDist = center.SqDistance2D(clusters[i].position);
				if (minSqDist > sqDist) {
					minSqDist = sqDist;
					pos = clusters[i].position;
				}
			}

			CMetalData::PointPredicate predicate = [this, facDef, terrainMgr, &clusters](const int index) {
				return (clusterInfos[index].factory == nullptr) && !terrainMgr->IsZoneAlly(clusters[index].position)
						&& terrainMgr->CanBeBuiltAtSafe(facDef, clusters[index].position);
			};
			int index = metalMgr->FindNearestCluster(pos, predicate);
			if (index < 0) {
				return nullptr;
			}
			buildPos = clusters[index].position;

			const float sqStartDist = enemyPos.SqDistance2D(basePos);
			const float sqBuildDist = enemyPos.SqDistance2D(buildPos);
			offset = (sqStartDist > sqBuildDist) ? -200.0f : 200.0f;  // std::max(facUDef->GetXSize(), facUDef->GetZSize()) * SQUARE_SIZE;
		}

		if (factoryTask->GetFacing() != UNIT_NO_FACING) {
			factoryTask->SetBuildPos(buildPos);
		} else {
			buildPos.x += (buildPos.x > enemyPos.x) ? -offset : offset;
			buildPos.z += (buildPos.z > enemyPos.z) ? -offset : offset;

			CTerrainManager::CorrectPosition(buildPos);
			buildPos = terrainMgr->GetBuildPosition(reprDef, buildPos);
		}
	}

	// GetBuildPosition above snaps to a sector centre chosen for reprDef, the
	// factory's MOBILE representative; the test below is against facDef's
	// IMMOBILE type. The two accept different sectors, so the snapped site can
	// fail it. Without this the task is discarded and nothing is ever placed.
	if (!factoryTask->IsPlop() && (factoryTask->GetFacing() == UNIT_NO_FACING)
		&& !terrainMgr->CanBeBuiltAtSafe(facDef, buildPos))
	{
		const AIFloat3& homePos = circuit->GetSetupManager()->GetBasePos();
		if (terrainMgr->CanBeBuiltAtSafe(facDef, homePos)) {
			buildPos = homePos;
		}
	}

	factoryTask->SetPosition(buildPos);

	if (factoryTask->IsPlop()
		|| (terrainMgr->CanBeBuiltAtSafe(facDef, buildPos)
			&& ((unit == nullptr) || terrainMgr->CanReachAtSafe(unit, buildPos, unit->GetCircuitDef()->GetBuildDistance()))))
	{
//		if (factoryMgr->GetNoT1FacCount() == 0) {  // FIXME
//			CCircuitUnit* reclFac = factoryMgr->GetClosestFactory(buildPos);
//			if (reclFac != nullptr) {
////				factoryMgr->DisableFactory(reclFac);
//				builderMgr->EnqueueTask(TaskB::Reclaim(IBuilderTask::Priority::NOW, reclFac));
//			}
//		}
		builderMgr->ActivateTask(factoryTask);
		IBuilderTask* task = factoryTask;
		factoryTask = nullptr;
		return task;
	} else {
		// PickNextFactory enqueues this task INACTIVE, so it is not in
		// updateTasks and the module will never free it -- but Enqueue has
		// already fired TaskAdded, so AngelScript may hold a refcounted handle
		// to it. AbortTask runs the normal teardown: TaskRemoved lets the script
		// drop its handle, and CBFactoryTask::Cancel undoes the AddFactory its
		// ctor did (allFactories[].count is the primary sort key in
		// CFactoryData::GetFactoryToBuild). ClearRelease then drops the module's
		// own reference instead of deleting under the script's.
		builderMgr->AbortTask(factoryTask);
		factoryTask->ClearRelease();
		factoryTask = nullptr;
	}

	return nullptr;
}

IBuilderTask* CEconomyManager::UpdateFactoryTasks()
{
	return UpdateFactoryTasks(circuit->GetSetupManager()->GetBasePos());
}

IBuilderTask* CEconomyManager::UpdateStorageTasks()
{
	ZoneScoped;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask(32)) {
		return nullptr;
	}

	if (!builderMgr->GetTasks(IBuilderTask::BuildType::STORE).empty()) {
		return UpdatePylonTasks();
	}

	CCircuitDef* storeDef = nullptr;
	if (storeMDefs.HasAvail()) {
		storeDef = storeMDefs.GetFirstDef();

		if (!storeDef->IsAvailable(circuit->GetLastFrame())
//			|| (GetMetalStore() > 60 * GetAvgMetalIncome())
			|| !IsMetalFull())
		{
			storeDef = nullptr;
		}
	}

	if ((storeDef == nullptr) && storeEDefs.HasAvail()) {
		storeDef = storeEDefs.GetFirstDef();

		if (!storeDef->IsAvailable(circuit->GetLastFrame())
			|| (GetEnergyStore() > 5 * GetAvgEnergyIncome())
			|| IsEnergyEmpty())
		{
			storeDef = nullptr;
		}
	}

	if (storeDef != nullptr) {
		AIFloat3 buildPos = circuit->GetSetupManager()->GetBasePos();
		return builderMgr->Enqueue(TaskB::Common(IBuilderTask::BuildType::STORE,
								   IBuilderTask::Priority::HIGH, storeDef, buildPos));
	}

	return UpdatePylonTasks();
}

IBuilderTask* CEconomyManager::UpdatePylonTasks()
{
	return nullptr;
	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!builderMgr->CanEnqueueTask()) {
		return nullptr;
	}

	const float energyIncome = GetAvgEnergyIncome();
	const float metalIncome = std::min(GetAvgMetalIncome(), energyIncome);
	if (metalIncome < pylonLinkInc) {
		return nullptr;
	}

	const float cost = pylonDef->GetCostM();
	unsigned count = builderMgr->GetBuildPower() / cost * 8 + 1;
	if (builderMgr->GetTasks(IBuilderTask::BuildType::PYLON).size() >= count) {
		return nullptr;
	}

	energyGrid->SetAuthority(circuit);
	energyGrid->Update();

	CCircuitDef* buildDef;
	AIFloat3 buildPos;
	IGridLink* link = energyGrid->GetLinkToBuild(buildDef, buildPos);
	if ((link == nullptr) || (buildDef == nullptr)) {
		return nullptr;
	}

	if (utils::is_valid(buildPos)) {
		IBuilderTask::Priority priority = metalIncome < 40 ? IBuilderTask::Priority::NORMAL : IBuilderTask::Priority::HIGH;
		return builderMgr->Enqueue(TaskB::Pylon(priority, buildDef, buildPos, link, buildDef->GetCostM()));
	} else {
		link->SetValid(false);
		energyGrid->SetForceRebuild(true);
		// TODO: Optimize: when invalid link appears start watchdog gametask
		//       that will traverse invalidLinks vector and enable link on timeout.
		//       When invalidLinks is empty remove watchdog gametask.
		circuit->GetScheduler()->RunJobAfter(CScheduler::GameJob([link](CEnergyGrid* energyGrid) {
			link->SetValid(true);
			energyGrid->SetForceRebuild(true);
		}, energyGrid), FRAMES_PER_SEC * 120);
	}

	return nullptr;
}

IBuilderTask* CEconomyManager::CheckMobileAssistRequired(const AIFloat3& position, CCircuitUnit* unit)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return nullptr;
	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (!factoryMgr->IsAssistRequired() || !builderMgr->HasFreeAssists(unit)
		|| factoryMgr->GetTasks().empty() || factoryMgr->GetTasks().front()->GetAssignees().empty())
	{
		return nullptr;
	}
	CRecruitTask* recrTask = factoryMgr->GetTasks().front();
	CCircuitUnit* vip = *recrTask->GetAssignees().begin();
	if (vip->GetPos(circuit->GetLastFrame()).SqDistance2D(position) > SQUARE(600.f)) {
		return nullptr;
	}
	constexpr int SEC = 10;  // are there enough resources for 8-10 seconds?
	CCircuitDef* recrDef = recrTask->GetBuildDef();
	const float buildTime = recrDef->GetBuildTime() / unit->GetCircuitDef()->GetWorkerTime();
	const float miRequire = recrDef->GetCostM() / buildTime;  // + recrTask->GetBuildPowerM();
	const float eiRequire = recrDef->GetCostE() / buildTime;  // + recrTask->GetBuildPowerE();
	if ((metal.current > (metal.pull + miRequire - GetAvgMetalIncome()) * (SEC - 2))
		&& (energy.current > (energy.pull + eiRequire - GetAvgEnergyIncome()) * (SEC - 2)))
	{
		return builderMgr->EnqueueB(TaskB::Guard(IBuilderTask::Priority::HIGH, vip, false, FRAMES_PER_SEC * SEC));
	}
	return nullptr;
}

void CEconomyManager::StartFactoryJob(const float seconds)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	// Unschedule self; also never schedules the recurring UpdateFactoryTasks job.
	circuit->GetScheduler()->RemoveJob(startFactory);
	startFactory = nullptr;
	return;

	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	if ((factoryMgr->GetFactoryCount() == 0) && circuit->GetBuilderManager()->GetTasks(IBuilderTask::BuildType::FACTORY).empty()) {
		CCircuitUnit* comm = circuit->GetSetupManager()->GetCommander();
		const AIFloat3 pos = (comm != nullptr) ? comm->GetPos(circuit->GetLastFrame()) : AIFloat3(-RgtVector);
		if (!factoryMgr->IsSwitchTime() && (comm != nullptr) && (comm->GetTask()->GetType() == IUnitTask::Type::BUILDER)) {
			IBuilderTask* taskB = static_cast<IBuilderTask*>(comm->GetTask());
			const float maxDist = comm->GetCircuitDef()->GetBuildDistance() + comm->GetCircuitDef()->GetSpeed() * seconds;
			if (taskB->GetPosition().SqDistance2D(pos) > SQUARE(maxDist)) {
				factoryMgr->RaiseSwitchTime();
			}
			// FIXME: Alternative WIP
//			IBuilderTask* taskB = static_cast<IBuilderTask*>(comm->GetTask());
//			const float dist = taskB->GetPosition().distance2D(pos) - comm->GetCircuitDef()->GetBuildDistance();
//			const float moveETA = dist / comm->GetCircuitDef()->GetSpeed();
//			const float moveMetal = GetMetalCur() + GetAvgMetalIncome() * (moveETA + 1);  // 1 seconds - buffer
//			const float store = GetMetalStore();
//			if (moveMetal >= store) {
//				factoryMgr->RaiseSwitchTime();
//			} else {
//				const float buildTime = taskB->GetBuildDef()->GetBuildTime() / comm->GetCircuitDef()->GetWorkerTime();
//				const float pull = GetAvgMetalIncome() * buildTime - taskB->GetBuildDef()->GetCostM();
//				if (moveMetal + pull >= store) {
//					factoryMgr->RaiseSwitchTime();
//				}
//			}
			// FIXME
		}
		IBuilderTask* factoryTask = UpdateFactoryTasks(pos, comm);
		if (factoryTask == nullptr) {
//			if (isEnergyRequired) {
//				if (comm != nullptr) {
//					UpdateEnergyTasks(pos, comm);
//				}
//			}
			return;
		}
//		if (comm != nullptr) {
//			circuit->GetBuilderManager()->AssignTask(comm, factoryTask);
//		}
	}

	CScheduler* scheduler = circuit->GetScheduler().get();
	scheduler->RemoveJob(startFactory);
	startFactory = nullptr;

	const int interval = circuit->GetAllyTeam()->GetSize() * FRAMES_PER_SEC;
	auto update = static_cast<IBuilderTask* (CEconomyManager::*)(void)>(&CEconomyManager::UpdateFactoryTasks);
	scheduler->RunJobEvery(CScheduler::GameJob(update, this),
							interval, circuit->GetSkirmishAIId() + 0 + 10 * interval);
}

CBFactoryTask* CEconomyManager::PickNextFactory(const AIFloat3& position, bool isStart)
{
	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	CCircuitDef* facDef = factoryMgr->GetFactoryToBuild(position, isStart);
	if (facDef == nullptr) {
		return nullptr;
	}
	CCircuitDef* reprDef = factoryMgr->GetRepresenter(facDef);
	if (reprDef == nullptr) {  // identify area to build by factory representatives
		return nullptr;
	}
	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	IBuilderTask::Priority priority = (builderMgr->GetWorkerCount() <= 2)
									  ? IBuilderTask::Priority::NOW
									  : IBuilderTask::Priority::HIGH;
	const bool isPlop = (factoryMgr->GetFactoryCount() <= 0);
	// hold selected facDef - create non-active task
	factoryTask = static_cast<CBFactoryTask*>(builderMgr->Enqueue(TaskB::Factory(priority,
			facDef, -RgtVector, reprDef, SQUARE_SIZE, isPlop, false, FRAMES_PER_SEC * 120)));
	return factoryTask;
}

void CEconomyManager::AddMorphee(CCircuitUnit* unit)
{
	if (!unit->IsUpgradable() || (unit->GetTask()->GetType() == IUnitTask::Type::NIL)) {
		return;
	}
	morphees.insert(unit);
	if (morph == nullptr) {
		morph = CScheduler::GameJob(&CEconomyManager::UpdateMorph, this);
		circuit->GetScheduler()->RunJobEvery(morph, FRAMES_PER_SEC * 10);
	}
}

void CEconomyManager::UpdateMorph()
{
	ZoneScoped;

	if (morphees.empty()) {
		circuit->GetScheduler()->RemoveJob(morph);
		morph = nullptr;
		return;
	}

	const float energyIncome = GetAvgEnergyIncome();
	const float metalIncome = std::min(GetAvgMetalIncome(), energyIncome);
	if ((metalIncome < 10) || !IsExcessed() || !IsMetalFull() || (GetMetalPull() * 0.8f > metalIncome)) {
		return;
	}

	auto it = morphees.begin();
	while (it != morphees.end()) {
		CCircuitUnit* unit = *it;
		if ((unit->GetTask()->GetType() == IUnitTask::Type::PLAYER) ||
			(unit->GetUnit()->GetHealth() < unit->GetUnit()->GetMaxHealth() * 0.8f))
		{
			++it;
		} else {
			unit->Upgrade();  // Morph();
			it = morphees.erase(it);
			break;  // one unit at a time
		}
	}
}

void CEconomyManager::AddFactoryInfo(CCircuitUnit* unit)
{
	const int index = circuit->GetMetalManager()->FindNearestCluster(unit->GetPos(circuit->GetLastFrame()));
	if (index >= 0) {
		clusterInfos[index].factory = unit;
	}
}

void CEconomyManager::DelFactoryInfo(CCircuitUnit* unit)
{
	for (auto& info : clusterInfos) {
		if (info.factory == unit) {
			info.factory = nullptr;
		}
	}
}

bool CEconomyManager::CheckAirpadRequired(const AIFloat3& position, CCircuitUnit* unit, IBuilderTask*& outTask)
{
	outTask = nullptr;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return false;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	CMilitaryManager* militaryMgr = circuit->GetMilitaryManager();
	const unsigned airpadFactor = SQUARE((airpadCount + builderMgr->GetTasks(IBuilderTask::BuildType::FACTORY).size() + 1) * 3);
	if (militaryMgr->GetRoleUnits(ROLE_TYPE(AIR)).size() <= airpadFactor) {
		return false;
	}

	const int frame = circuit->GetLastFrame();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 buildPos = position;
	CCircuitDef* airpadDef = nullptr;
	if (unit == nullptr) {
		airpadDef = airpadDefs.GetBestDef([frame, terrainMgr, &buildPos](CCircuitDef* cdef, const SAirpadExt& data) {
			return cdef->IsAvailable(frame) && terrainMgr->CanBeBuiltAt(cdef, buildPos);
		});
	} else {
		const std::vector<CCircuitDef*>& padDefOptions = airpadDefs.GetBuildDefs(unit->GetCircuitDef());
		for (CCircuitDef* apDef : padDefOptions) {
			if (apDef->IsAvailable(frame) && terrainMgr->CanBeBuiltAt(apDef, buildPos)) {
				airpadDef = apDef;
				break;
			}
		}
	}
	if (airpadDef == nullptr) {
		return false;
	}

	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	CCircuitDef* bdef;
	if (unit == nullptr) {
		bdef = airpadDef;
		buildPos = factoryMgr->GetClosestHaven(circuit->GetSetupManager()->GetBasePos());
	} else {
		bdef = unit->GetCircuitDef();
		buildPos = factoryMgr->GetClosestHaven(unit);
	}
	if (!utils::is_valid(buildPos)) {
		buildPos = circuit->GetSetupManager()->GetBasePos();
	}
	buildPos = terrainMgr->GetBuildPosition(bdef, buildPos);

	if (terrainMgr->CanBeBuiltAtSafe(airpadDef, buildPos) &&
		((unit == nullptr) || terrainMgr->CanReachAtSafe(unit, buildPos, unit->GetCircuitDef()->GetBuildDistance())))
	{
		outTask = builderMgr->Enqueue(TaskB::Factory(IBuilderTask::Priority::NORMAL, airpadDef, buildPos, nullptr));
		return true;
	}

	return false;
}

bool CEconomyManager::CheckAssistRequired(const AIFloat3& position, CCircuitUnit* unit, IBuilderTask*& outTask)
{
	outTask = nullptr;
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return false;

	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	const int nanoQueued = builderMgr->GetTasks(IBuilderTask::BuildType::NANO).size();
	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	CCircuitUnit* factory = factoryMgr->NeedUpgrade(nanoQueued);
	if (factory == nullptr) {
		return false;
	}

	const int frame = circuit->GetLastFrame();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 buildPos = factory->GetPos(frame);
	CCircuitDef* assistDef = assistDefs.GetBestDef([frame, terrainMgr, &buildPos](CCircuitDef* cdef, const SAssistExt& data) {
		return cdef->IsAvailable(frame) && terrainMgr->CanBeBuiltAt(cdef, buildPos);
	});
	if (assistDef == nullptr) {
		return true;
	}

	/*
	 * check metal and energy
	 */
//	const float metalIncome = std::min(GetAvgMetalIncome(), GetAvgEnergyIncome());  // FIXME: ZK
	float miRequire;
	float eiRequire;
	CCircuitDef* facDef = factory->GetCircuitDef();
	CCircuitDef* reprDef = factoryMgr->GetRepresenter(facDef);
	if (reprDef == nullptr) {
		miRequire = assistDef->GetBuildSpeed();
		eiRequire = miRequire / GetEcoEM();
	} else {
		const float buildTime = reprDef->GetBuildTime() / assistDef->GetWorkerTime();
		miRequire = reprDef->GetCostM() / buildTime;
		eiRequire = reprDef->GetCostE() / buildTime;
	}
	miRequire *= factoryMgr->GetNewFacModM();
	eiRequire *= factoryMgr->GetNewFacModE();
	eiRequire += assistDef->GetUpkeepE();
	// FIXME: Mex and other buildings have energy upkeep that's not counted.
	//        It also doesn't count mobile buildpower
	if (GetAvgMetalIncome() < factoryMgr->GetMetalRequire() * factoryMgr->GetFacModM() + (nanoQueued + 1) * miRequire) {
		return true;
	}
	if ((GetAvgEnergyIncome() < factoryMgr->GetEnergyRequire() * factoryMgr->GetFacModE() + (nanoQueued + 1) * eiRequire)
		|| IsEnergyStalling())
	{
		isEnergyRequired = true;  // enough metal, request energy
		UpdateEnergyTasks(position, unit);
		return true;
	}

	switch (factory->GetUnit()->GetBuildingFacing()) {
		default:
		case UNIT_FACING_SOUTH:
			buildPos.z -= 64.0f;  // def->GetZSize() * SQUARE_SIZE * 2;
			break;
		case UNIT_FACING_EAST:
			buildPos.x -= 64.0f;  // def->GetXSize() * SQUARE_SIZE * 2;
			break;
		case UNIT_FACING_NORTH:
			buildPos.z += 64.0f;  // def->GetZSize() * SQUARE_SIZE * 2;
			break;
		case UNIT_FACING_WEST:
			buildPos.x += 64.0f;  // def->GetXSize() * SQUARE_SIZE * 2;
			break;
	}
	CTerrainManager::CorrectPosition(buildPos);
	CCircuitDef* bdef = (unit == nullptr) ? facDef : unit->GetCircuitDef();
	buildPos = terrainMgr->GetBuildPosition(bdef, buildPos);

	if (terrainMgr->CanBeBuiltAtSafe(assistDef, buildPos)
		&& ((unit == nullptr) || terrainMgr->CanReachAtSafe(unit, buildPos, unit->GetCircuitDef()->GetBuildDistance())))
	{
		outTask = builderMgr->Enqueue(TaskB::Common(IBuilderTask::BuildType::NANO, IBuilderTask::Priority::HIGH,
									  assistDef, buildPos, SQUARE_SIZE * 8, true));
		return true;
	}
	return false;
}

float CEconomyManager::GetStorage(Resource* res)
{
	return economy->GetStorage(res) - HIDDEN_STORAGE;
}

void CEconomyManager::UpdateResourceIncome()
{
	float oddEnergyIncome = circuit->GetTeam()->GetRulesParamFloat("OD_energyIncome", 0.f);
	float oddEnergyChange = circuit->GetTeam()->GetRulesParamFloat("OD_energyChange", 0.f);

	energyIncomes[indexRes] = economy->GetIncome(energyRes) + oddEnergyIncome - std::max(.0f, oddEnergyChange);
	metalIncomes[indexRes] = economy->GetIncome(metalRes) + economy->GetReceived(metalRes);
	++indexRes %= INCOME_SAMPLES;

	metal.income = .0f;
	for (int i = 0; i < INCOME_SAMPLES; i++) {
		metal.income += metalIncomes[i];
	}
	metal.income /= INCOME_SAMPLES;

	energy.income = .0f;
	for (int i = 0; i < INCOME_SAMPLES; i++) {
		energy.income += energyIncomes[i];
	}
	energy.income /= INCOME_SAMPLES;

	metalProduced += metal.income * metalMod;
	metalUsed += economy->GetUsage(metalRes);
}

void CEconomyManager::UpdateEconomy()
{
	ZoneScoped;

	UpdateResourceIncome();

	int ecoFrame = circuit->GetLastFrame();

	/*const float curMetal = */GetMetalCur();
	/*const float storMetal = */GetMetalStore();
	/*const float incMetal = */GetAvgMetalIncome();
	/*const float pullMetal = */GetMetalPull();

	/*const float curEnergy = */GetEnergyCur();
	/*const float storEnergy = */GetEnergyStore();
	/*const float incEnergy = */GetAvgEnergyIncome();
	/*const float pullEnergy = */GetEnergyPull();

	// Update isMetalEmpty, isMetalFull, isEnergyEmpty, isEnergyStalling
	static_cast<CEconomyScript*>(script)->UpdateEconomy();

	if (ecoFrame <= efInfo.startFrame) {
		energyFactor = efInfo.startFactor;
	} else if (ecoFrame >= efInfo.endFrame) {
		energyFactor = efInfo.endFactor;
	} else {
		energyFactor = efInfo.fraction * (ecoFrame - efInfo.startFrame) + efInfo.startFactor;
	}

	if (ecoFrame <= bdInfo.startFrame) {
		buildDelay = bdInfo.startDelay;
	} else if (ecoFrame >= bdInfo.endFrame) {
		buildDelay = bdInfo.endDelay;
	} else {
		buildDelay = int(bdInfo.fraction * (ecoFrame - bdInfo.startFrame)) + bdInfo.startDelay;
	}

	if (mexCount <= mspInfos.front().mex) {
		pullMtoS = mspInfos.front().pull;
	} else if (mexCount >= mspInfos.back().mex) {
		pullMtoS = mspInfos.back().pull;
	} else {
		auto it = std::lower_bound(mspInfos.cbegin(), mspInfos.cend(), mexCount, SPullMtoS());
		const SPullMtoS& mspInfo = *--it;
		pullMtoS = mspInfo.fraction * (mexCount - mspInfo.mex) + mspInfo.pull;
	}
	pullMtoS *= circuit->GetMilitaryManager()->ClampMobileCostRatio();
}

void CEconomyManager::IncPurpose(const CCircuitDef::Id defId)
{
	auto it = purposes.find(defId);
	if (it == purposes.end()) {
		purposes[defId].count = 1;
	} else {
		++it->second.count;
	}
}

void CEconomyManager::DecPurpose(const CCircuitDef::Id defId)
{
	assert(purposes.find(defId) != purposes.end());
	--purposes[defId].count;
}

bool CEconomyManager::HasNoPurpose(const CCircuitDef::Id defId) const
{
	auto it = purposes.find(defId);
	assert(it != purposes.end());
	return (it == purposes.end()) || (it->second.count <= 0);
}

void CEconomyManager::ReclaimOldConvert(const SConvertExt* convertExt)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return;
	if (circuit->IsLoadSave() || (reclConvertEff <= 0.f) || (IsEnergyFull() && !IsEnergyStalling())) {
		return;
	}
	float energyNet = GetAvgEnergyIncome() - GetEnergyPull();
	auto ids = circuit->GetCallback()->GetFriendlyUnitIdsIn(circuit->GetSetupManager()->GetMetalBase(), 1000.f, false);
	for (int id : ids) {
		CCircuitUnit* unit = circuit->GetTeamUnit(id);
		if (unit == nullptr) {
			continue;
		}
		CCircuitDef* cdef = unit->GetCircuitDef();
		if (!convertDefs.IsAvail(cdef)) {
			continue;
		}
		auto info = convertDefs.GetAvailInfo(cdef);
		if (convertExt->make > info->make * reclConvertEff) {
			if (!info->isOld) {
				const_cast<SConvertExt*>(info)->isOld = true;
				DecPurpose(cdef->GetId());
			}
		} else {
			if (info->isOld) {
				const_cast<SConvertExt*>(info)->isOld = false;
				IncPurpose(cdef->GetId());
			}
		}
		if (HasNoPurpose(cdef->GetId())) {
			circuit->GetBuilderManager()->Enqueue(TaskB::Reclaim(IUnitTask::Priority::HIGH, unit, FRAMES_PER_SEC * 1200));
			energyNet += convertExt->energyUse;
			if (energyNet > 0) {
				break;
			}
		}
	}
}

void CEconomyManager::ReclaimOldEnergy(const SEnergyExt* energyExt)
{
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	return;
	float energyIncome = GetAvgEnergyIncome();
	if (circuit->IsLoadSave() || (reclEnergyEff <= 0.f) || (energyIncome < energyExt->cond.energyIncome)) {
		return;
	}
	auto ids = circuit->GetCallback()->GetFriendlyUnitIdsIn(circuit->GetSetupManager()->GetBasePos(), 1000.f, false);
	for (int id : ids) {
		CCircuitUnit* unit = circuit->GetTeamUnit(id);
		if (unit == nullptr) {
			continue;
		}
		CCircuitDef* cdef = unit->GetCircuitDef();
		if (!energyDefs.IsAvail(cdef)) {
			continue;
		}
		auto info = energyDefs.GetAvailInfo(cdef);
		if (energyExt->cond.score > info->cond.score * reclEnergyEff) {
			if (!info->isOld) {
				const_cast<SEnergyExt*>(info)->isOld = true;
				DecPurpose(cdef->GetId());
			}
		} else {
			if (info->isOld) {
				const_cast<SEnergyExt*>(info)->isOld = false;
				IncPurpose(cdef->GetId());
			}
		}
		if (HasNoPurpose(cdef->GetId())) {
			energyIncome -= info->make;
			if (energyIncome < energyExt->cond.energyIncome) {
				break;
			}
			circuit->GetBuilderManager()->Enqueue(TaskB::Reclaim(IUnitTask::Priority::HIGH, unit, FRAMES_PER_SEC * 1200));
		}
	}
}

} // namespace circuit
