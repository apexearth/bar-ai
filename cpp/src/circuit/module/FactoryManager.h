/*
 * FactoryManager.h
 *
 *  Created on: Dec 1, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_MODULE_FACTORYMANAGER_H_
#define SRC_CIRCUIT_MODULE_FACTORYMANAGER_H_

#include "module/TaskModule.h"
#include "task/static/RecruitTask.h"
#include "unit/CircuitUnit.h"

#include <map>

namespace circuit {

class CEconomyManager;
class CFactoryData;
class CSRepairTask;

namespace TaskS {
	struct SRecruitTask {
		CRecruitTask::RecruitType type;
		CRecruitTask::Priority priority;
		CCircuitDef* buildDef;
		springai::AIFloat3 position;
		float radius;
	};

	struct SServSTask {
		IBuilderTask::BuildType type;
		IBuilderTask::Priority priority;
		springai::AIFloat3 position;
		CAllyUnit* target;
		float radius;
		bool stop;
		int timeout;
	};

	static inline SRecruitTask Recruit(CRecruitTask::RecruitType type,
			CRecruitTask::Priority priority, CCircuitDef* buildDef,
			const springai::AIFloat3& position, float radius)
	{
		SRecruitTask ti;
		ti.type = type;
		ti.priority = priority;
		ti.buildDef = buildDef;
		ti.position = position;
		ti.radius = radius;
		return ti;
	}

	static inline SServSTask Repair(IBuilderTask::Priority priority, CAllyUnit* target)
	{
		SServSTask ti;
		ti.type = IBuilderTask::BuildType::REPAIR;
		ti.priority = priority;
		ti.target = target;
		return ti;
	}
	static inline SServSTask Reclaim(IBuilderTask::Priority priority,
			const springai::AIFloat3& position, float radius, int timeout = 0)
	{
		SServSTask ti;
		ti.type = IBuilderTask::BuildType::RECLAIM;
		ti.priority = priority;
		ti.position = position;
		ti.radius = radius;
		ti.timeout = timeout;
		ti.target = nullptr;
		return ti;
	}
	// A turret eating one unit of ours, held off every other task until it is gone.
	static inline SServSTask ReclaimUnit(IBuilderTask::Priority priority, CCircuitUnit* target, int timeout)
	{
		SServSTask ti;
		ti.type = IBuilderTask::BuildType::RECLAIM;
		ti.priority = priority;
		ti.target = target;
		ti.radius = 0.f;
		ti.timeout = timeout;
		return ti;
	}
	static inline SServSTask Patrol(IBuilderTask::Priority priority,
			const springai::AIFloat3& position, int timeout)
	{
		SServSTask ti;
		ti.type = IBuilderTask::BuildType::PATROL;
		ti.priority = priority;
		ti.position = position;
		ti.timeout = timeout;
		return ti;
	}
	static inline SServSTask Wait(bool stop, int timeout)
	{
		SServSTask ti;
		ti.type = IBuilderTask::BuildType::WAIT;
		ti.stop = stop;
		ti.timeout = timeout;
		return ti;
	}
} // namespace TaskS

class CFactoryManager: public ITaskModule {
public:
	friend class CFactoryScript;

	struct SSideInfo {
		CCircuitDef* assistDef;
	};
	struct SFactoryDef {
		using Tiers = std::map<unsigned, std::vector<float>>;  // tier: probs

		SFactoryDef()
			: startImp(0.f)
			, switchImp(0.f)
			, mapSpeedPerc(0.f)
			, isT1(false)
			, landDef(nullptr)
			, waterDef(nullptr)
			, isRequireEnergy(false)
			, nanoCount(0)
		{}

		// >>> FactoryData ---- BEGIN
		float startImp;  // importance[0]
		float switchImp;  // importance[1]
		float mapSpeedPerc;
		bool isT1;  // FIXME: DEBUG Silly t1 detection
		// <<< FactoryData ---- END

		std::vector<CCircuitDef*> buildDefs;
		Tiers airTiers;
		Tiers landTiers;
		Tiers waterTiers;
		CCircuitDef* landDef;
		CCircuitDef* waterDef;
		std::vector<float> incomes;
		bool isRequireEnergy;
		unsigned int nanoCount;
	};
	using FactoryDefs = std::unordered_map<CCircuitDef::Id, SFactoryDef>;

	CFactoryManager(CCircuitAI* circuit);
	virtual ~CFactoryManager();

	void InitHandlers();
private:
	void ReadConfig();
	void Init();

public:
	virtual int UnitCreated(CCircuitUnit* unit, CCircuitUnit* builder) override;
	virtual int UnitFinished(CCircuitUnit* unit) override;
	virtual int UnitIdle(CCircuitUnit* unit) override;
	virtual int UnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;

	CRecruitTask* Enqueue(const TaskS::SRecruitTask& ti);
	IUnitTask* Enqueue(const TaskS::SServSTask& ti);
private:
	virtual void DequeueTask(IUnitTask* task, bool done = false) override;

public:
	void MarkRepairUnit(ICoreUnit::Id targetId, CSRepairTask* task) {
		repairUnits[targetId] = task;
	}

	int GetFactoryCount() const { return factories.size(); }
	int GetNoT1FacCount() const { return noT1FacCount; }
	float GetMetalRequire() const { return metalRequire; }
	float GetEnergyRequire() const { return energyRequire; }
	float GetNewFacModM() const { return newFacModM; }
	float GetNewFacModE() const { return newFacModE; }
	float GetFacModM() const { return facModM; }
	float GetFacModE() const { return facModE; }
	bool CanEnqueueTask() const { return factoryTasks.size() < factories.size() * 2; }
	const std::vector<CRecruitTask*>& GetTasks() const { return factoryTasks; }
	bool IsAssistRequired() const { return isAssistRequired; }
	void ApplySwitchFrame();
	bool IsSwitchTime();
	void RaiseSwitchTime() { isSwitchTime = true; }
	bool IsSwitchAllowed(CCircuitDef* facDef) const;
	CCircuitUnit* NeedUpgrade(unsigned int nanoQueued);
	CCircuitUnit* GetClosestFactory(const springai::AIFloat3& position);
//	CCircuitDef* GetClosestDef(springai::AIFloat3& position, CCircuitDef::RoleT role);

	springai::AIFloat3 GetClosestHaven(CCircuitUnit* unit) const;
	springai::AIFloat3 GetClosestHaven(const springai::AIFloat3& position) const;

	const SSideInfo& GetSideInfo() const;
	const std::vector<SSideInfo>& GetSideInfos() const { return sideInfos; }

	CRecruitTask* UpdateBuildPower(CCircuitUnit* builder, bool isActive);
	CRecruitTask* UpdateFirePower(CCircuitUnit* builder, bool isActive);
	bool IsHighPriority(CAllyUnit* unit) const;

	CCircuitDef* GetFactoryToBuild(springai::AIFloat3 position = -RgtVector,
								   bool isStart = false, bool isReset = false);
	void AddFactory(const CCircuitDef* cdef);
	void DelFactory(const CCircuitDef* cdef);
	bool IsT1Factory(const CCircuitDef* cdef);
	CCircuitDef* GetRoleDef(const CCircuitDef* facDef, CCircuitDef::RoleT role) const;
	CCircuitDef* GetLandDef(const CCircuitDef* facDef) const;
	CCircuitDef* GetWaterDef(const CCircuitDef* facDef) const;
	CCircuitDef* GetRepresenter(const CCircuitDef* facDef) const;
	CCircuitDef* GetLargestDef(const CCircuitDef* facDef) const;

	float GetAssistSpeed() const { return GetSideInfo().assistDef->GetBuildSpeed(); }
	float GetAssistRange() const { return GetSideInfo().assistDef->GetBuildDistance(); }

	const FactoryDefs& GetFactoryDefs() const { return factoryDefs; }
	unsigned int GetNoAirNum() const { return noAirNum; }
	float GetAirMapPerc() const { return airMapPerc; }
	float GetMinOffset() const { return minOffset; }
	float GetLenOffset() const { return lenOffset; }

	void UnitRelocated(CCircuitUnit* unit, const springai::AIFloat3& from);

private:
	void AttachAssist(CCircuitUnit* unit, const springai::AIFloat3& assPos, int frame);
	void DetachAssist(CCircuitUnit* unit, const springai::AIFloat3& assPos);
	CCircuitDef* DefaultGetFactoryToBuild(const springai::AIFloat3& position, bool isStart, bool isReset);
	void EnableFactory(CCircuitUnit* unit);
	void DisableFactory(CCircuitUnit* unit);
	virtual IUnitTask* DefaultMakeTask(CCircuitUnit* unit) override;
	IUnitTask* CreateFactoryTask(CCircuitUnit* unit);
	IUnitTask* CreateAssistTask(CCircuitUnit* unit);

	void Watchdog();

	// Release one nano turret per tick from a building when a factory it can
	// reach is producing (apexearth 2026-09-06); see the definitions.
	void PullNanoOffBuilding();
	bool HasFactoryOutputInRange(CCircuitUnit* nano);
	// (round-robin index removed: the whole assist set is swept each pass)
	int nanoPulled = 0;
	int nanoPullLogAt = 0;
	int nanoSeen = 0, nanoOnRepair = 0, nanoOnStatic = 0, nanoHasOut = 0;

	Handlers2 createdHandler;
	Handlers1 finishedHandler;
	Handlers1 idleHandler;
	EHandlers destroyedHandler;

	std::map<CAllyUnit*, IBuilderTask*> unfinishedUnits;
	std::vector<CRecruitTask*> factoryTasks;  // order matters
	float metalRequire;
	float energyRequire;
	float newFacModM = 0.f;
	float newFacModE = 0.f;
	float facModM = 0.f;
	float facModE = 0.f;

	std::vector<SSideInfo> sideInfos;

	struct SAssistToFactory {
		std::set<CCircuitUnit*> factories;
		float metalRequire = 0.f;
		float energyRequire = 0.f;
	};
	std::map<CCircuitUnit*, SAssistToFactory> assists;  // nano 1:n factory
	std::vector<springai::AIFloat3> havens;  // position behind factory
	std::map<ICoreUnit::Id, CSRepairTask*> repairUnits;

	CFactoryData* factoryData;
	struct SAssistant {
		std::set<CCircuitUnit*> units;
		float incomeMod;
	};
	struct SFactory {
		SFactory(CCircuitUnit* u, const std::map<CCircuitDef*, SAssistant>& n, unsigned int ns, unsigned int w, CCircuitDef* b,
				 float mi, float ei, float mit, float eit)
			: unit(u), nanos(n), nanoSize(ns), weight(w), builder(b)
			, miRequire(mi), eiRequire(ei), miRequireTotal(mit), eiRequireTotal(eit)
		{}
		CCircuitUnit* unit;
		std::map<CCircuitDef*, SAssistant> nanos;
		unsigned int nanoSize;
		unsigned int weight;
		CCircuitDef* builder;
		float miRequire;
		float eiRequire;
		float miRequireTotal;
		float eiRequireTotal;
	};
	std::vector<SFactory> factories;  // factory 1:n nano
	std::set<CCircuitUnit*> validAir;
	bool isAssistRequired;
	bool isSwitchTime;
	int lastSwitchFrame;
	int noT1FacCount;

	FactoryDefs factoryDefs;
	// >>> FactoryData ---- BEGIN
	unsigned int noAirNum = 0;
	float airMapPerc = 0.f;
	float minOffset = 0.f;
	float lenOffset = 0.f;
	// <<< FactoryData ---- END
	float bpRatio;
	float reWeight;

	struct SFireDef {
		CCircuitDef* cdef;
		const std::vector<float>* probs;
		bool isResponse;
		int buildCount;
	};
	int numBatch = 0;
	std::map<CCircuitDef::Id, SFireDef> lastFireDef;  // factory: SFireDef
	void SetLastRequiredDef(CCircuitDef::Id facId, CCircuitDef* cdef,
							const std::vector<float>& probs, bool isResp);
	std::pair<CCircuitDef*, bool> GetLastRequiredDef(CCircuitDef::Id facId,
			const std::vector<float>& probs, const std::function<bool (CCircuitDef*)>& isAvailable);

	struct SRecruitDef {
		CCircuitDef::Id id;
		CRecruitTask::Priority priority;
	};
	SRecruitDef RequiredFireDef(CCircuitUnit* builder, bool isActive);

	const std::vector<float>& GetFacTierProbs(const SFactoryDef& facDef) const;
	CCircuitDef* GetFacRoleDef(CCircuitDef::RoleT role, const SFactoryDef& facDef) const;
};

} // namespace circuit

#endif // SRC_CIRCUIT_MODULE_FACTORYMANAGER_H_
