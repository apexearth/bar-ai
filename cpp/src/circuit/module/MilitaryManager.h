/*
 * MilitaryManager.h
 *
 *  Created on: Sep 5, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_MODULE_MILITARYMANAGER_H_
#define SRC_CIRCUIT_MODULE_MILITARYMANAGER_H_

#include "module/TaskModule.h"
#include "setup/DefenceData.h"
#include "task/fighter/FighterTask.h"
#include "unit/CircuitDef.h"
#include "util/AvailList.h"

#include <vector>
#include <set>

namespace circuit {

class IMainJob;
class CBDefenceTask;
class CFGuardTask;

namespace TaskF {
	struct SFightTask {
		IFighterTask::FightType type;
		IFighterTask::FightType check;
		IFighterTask::FightType promote;
		float power;
		CCircuitUnit* vip;
	};

	static inline SFightTask Common(IFighterTask::FightType type)
	{
		SFightTask ti;
		ti.type = type;

		ti.check = type;
		ti.promote = type;
		ti.power = 0.f;
		ti.vip = nullptr;
		return ti;
	}
	static inline SFightTask Guard(CCircuitUnit* vip)
	{
		SFightTask ti;
		ti.type = IFighterTask::FightType::GUARD;
		ti.vip = vip;
		return ti;
	}
	static inline SFightTask Defend(IFighterTask::FightType promote, float power)
	{
		SFightTask ti;
		ti.type = IFighterTask::FightType::DEFEND;
		ti.check = IFighterTask::FightType::_SIZE_;  // NONE
		ti.promote = promote;
		ti.power = power;
		return ti;
	}
	static inline SFightTask Defend(IFighterTask::FightType check, IFighterTask::FightType promote, float power)
	{
		SFightTask ti;
		ti.type = IFighterTask::FightType::DEFEND;
		ti.check = check;
		ti.promote = promote;
		ti.power = power;
		return ti;
	}
} // namespace TaskF

class CMilitaryManager: public ITaskModule {
public:
	friend class CMilitaryScript;

	using BuildVector = std::vector<std::pair<CCircuitDef*, int>>;  // cdef: frame
	using SuperInfos = std::vector<std::pair<CCircuitDef*, float>>;  // cdef: weight
	struct SSideInfo {
		std::vector<CCircuitDef*> landDefenders;
		std::vector<CCircuitDef*> waterDefenders;
		BuildVector baseDefence;

		std::vector<CCircuitDef*> wallDefs;  // land and water
		std::vector<CCircuitDef*> chokeDefs;  // land and water
		CCircuitDef* defaultPorc;

		SuperInfos superInfos;
	};

	CMilitaryManager(CCircuitAI* circuit);
	virtual ~CMilitaryManager();

	void InitHandlers();
private:
	void ReadConfig();
	void InitEconomyScores(const std::vector<CCircuitDef*>&& builders);
	void Init();

public:
	virtual int UnitCreated(CCircuitUnit* unit, CCircuitUnit* builder) override;
	virtual int UnitFinished(CCircuitUnit* unit) override;
	virtual int UnitIdle(CCircuitUnit* unit) override;
	virtual int UnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	virtual int UnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;

	const std::set<IFighterTask*>& GetTasks(IFighterTask::FightType type) const {
		return fightTasks[static_cast<IFighterTask::FT>(type)];
	}

	IFighterTask* Enqueue(const TaskF::SFightTask& ti);
	virtual CRetreatTask* EnqueueRetreat() override;
private:
	virtual void DequeueTask(IUnitTask* task, bool done = false) override;

public:
	void MarkGuardUnit(CCircuitUnit* vip, CFGuardTask* task) {
		guardTasks[vip] = task;
	}

	void MakeDefence(const springai::AIFloat3& pos);
	void MakeDefence(int cluster);
	void MakeDefence(int cluster, const springai::AIFloat3& pos);
	void DefaultMakeDefence(int cluster, const springai::AIFloat3& pos);
	// Sensors only, without any of DefaultMakeDefence's tower placement. The
	// script's AiMakeDefence returns early on clusters it declines to porc, and
	// the sensor block lives at the end of DefaultMakeDefence, so those clusters
	// used to get no radar either.
	void DefaultMakeSensors(int cluster, const springai::AIFloat3& pos);
	void MarkPorc(CCircuitUnit* unit, int defPointId);
	void UnmarkPorc(CCircuitUnit* unit);
	void AbortDefence(const CBDefenceTask* task, int defPointId);
	bool HasDefence(int cluster);
	void ProcessHubDefence(CBDefenceTask* task);
	springai::AIFloat3 GetScoutPosition(CCircuitUnit* unit);
	void ClearScoutPosition(IUnitTask* task);
	bool GetGuardAnchor(springai::AIFloat3& outPos) const;
	// Per-pool anchor. `assigned` is parallel to CCircuitAI::GetHotSpots() and
	// holds the power already sent to each spot this pass, so a spot that is
	// covered stops attracting the next pool; the chosen index comes back in
	// outSpot for the caller to add to.
	bool GetGuardAnchor(const springai::AIFloat3& from, const std::vector<float>& assigned,
			springai::AIFloat3& outPos, int& outSpot) const;
	void FillFrontPos(CCircuitUnit* unit, F3Vec& outPositions);
	void FillDefencePos(CCircuitUnit* unit, F3Vec& outPositions);
	springai::AIFloat3 GetDefenceStand();
	void FillAttackSafePos(CCircuitUnit* unit, F3Vec& outPositions);
	void FillStaticSafePos(CCircuitUnit* unit, F3Vec& outPositions);
	void FillSafePos(CCircuitUnit* unit, F3Vec& outPositions);
	CCircuitUnit* GetClosestLeader(const std::vector<IFighterTask::FightType>& types, const springai::AIFloat3& position);

	IFighterTask* GetGuardTask(CCircuitUnit* unit) const;

	const std::set<CCircuitUnit*>& GetRoleUnits(CCircuitDef::RoleT type) const {
		return roleInfos[type].units;
	}
	float GetRoleCost(CCircuitDef::RoleT type) const { return roleInfos[type].cost; }
	void AddResponse(CCircuitUnit* unit);
	void DelResponse(CCircuitUnit* unit);
	float GetArmyCost() const { return armyCost; }
	float RoleProbability(const CCircuitDef* cdef) const;
	bool IsNeedBigGun(const CCircuitDef* cdef) const;
	springai::AIFloat3 GetBigGunPos(CCircuitDef* bigDef) const;
	void DiceBigGun();
	float ClampMobileCostRatio() const;
	void UpdateDefenceTasks();
	void UpdateDefence();
	void MakeBaseDefence(const springai::AIFloat3& pos);

	void AddSensorDefs(const std::set<CCircuitDef*>& buildDefs);  // add available sensor defs
	void RemoveSensorDefs(const std::set<CCircuitDef*>& buildDefs);

	const SSideInfo& GetSideInfo() const;
	const std::vector<SSideInfo>& GetSideInfos() const { return sideInfos; }

	CCircuitDef* GetBigGunDef() const { return bigGunDef; }
	CCircuitDef* GetDefaultPorc() const { return GetSideInfo().defaultPorc; }
	CCircuitDef* GetLowSonar(const CCircuitUnit* builder = nullptr) const;

	void SetBaseDefRange(float range) { defence->SetBaseRange(range); }
	float GetBaseDefRange() const { return defence->GetBaseRange(); }
	float GetCommDefRadBegin() const { return defence->GetCommRadBegin(); }
	float GetCommDefRad(float baseDist) const { return defence->GetCommRad(baseDist); }
	unsigned int GetGuardTaskNum() const { return defence->GetGuardTaskNum(); }
	unsigned int GetGuardsNum() const { return defence->GetGuardsNum(); }
	int GetGuardFrame() const { return defence->GetGuardFrame(); }

	void AddPointOfInterest(CEnemyInfo* enemy) { PointOfInterest(enemy, +3, -1); }
	void DelPointOfInterest(CEnemyInfo* enemy) { PointOfInterest(enemy, -3, +1); }

	// TODO: Create CMilitaryManager::CTargetManager and move all FindTarget variations there.
	//       CMilitaryManager must be responsible for target selection.
	CEnemyInfo* FindBCombatTarget(CCircuitUnit* unit, const springai::AIFloat3& pos,
								  float powerMod, bool isTest);

	float GetRangeUnitCountCompensatorScale();

	// apex: super-weapon target de-confliction. CSuperTask::CanAssignTo returns
	// false unconditionally, so every silo owns a separate task and every task
	// runs the same deterministic selection over the same enemy groups -- N silos
	// answer identically and fire N warheads into one crater, and a single silo
	// re-fires the same spot every reload. A warhead is 1000 metal and 125,000
	// energy, so that is the expensive part of owning a silo, not the silo.
	// Kept here rather than on the task because it must be shared BETWEEN tasks.
	void NoteSuperTarget(const springai::AIFloat3& pos, int frame);
	bool IsRecentSuperTarget(const springai::AIFloat3& pos, float sqRadius, int frame) const;

	// The one place that decides whether a commander should be cloaked.
	bool IsCommCloakWanted(CCircuitUnit* unit) const;
	// Consecutive stalling reads, updated by UpdateCommCloak -- the cloak
	// decision needs a SUSTAINED stall, not the boundary flicker of an
	// economy running used==produced (measured 23 flips in 2 minutes).
	int commCloakStallTicks = 0;

private:
	virtual IUnitTask* DefaultMakeTask(CCircuitUnit* unit) override;

	void UpdateCommCloak();
	void Watchdog();

	void AddArmyCost(CCircuitUnit* unit);
	void DelArmyCost(CCircuitUnit* unit);
	void PointOfInterest(CEnemyInfo* enemy, int start, int step);
	springai::AIFloat3 GetFrontierPos(const springai::AIFloat3& basePos);

	struct SSuperShot {
		springai::AIFloat3 pos;
		int frame;
	};
	std::vector<SSuperShot> superShots;
	bool IsStrongpoint(const springai::AIFloat3& pos) const;
	CDefenceData::SDefPoint* FindClosestDefPoint(const springai::AIFloat3& pos);
	CDefenceData::SDefPoint* FindClosestDefPoint(int cluster, const springai::AIFloat3& pos,
			std::function<bool (const CDefenceData::SDefPoint&)> predicate = nullptr);
	void MakeSensors(const springai::AIFloat3& backPos, float maxCost, float radiusMod, bool isWater);

	Handlers2 createdHandler;
	Handlers1 finishedHandler;
	Handlers1 idleHandler;
	EHandlers damagedHandler;
	EHandlers destroyedHandler;

	std::vector<std::set<IFighterTask*>> fightTasks;

	CDefenceData* defence;
	unsigned int defenceIdx;
	std::map<CCircuitUnit*, int> porcToPoint;  // unit: defPointId

	// Every FINISHED static defence we own, whoever placed it: the FENCE
	// attribute handlers below fire for build_chain porcupine, DefaultMakeDefence
	// and script-enqueued towers alike. Positions are cached rather than read per
	// query because these units never move.
	std::map<CCircuitUnit*, springai::AIFloat3> fencePos;
	springai::AIFloat3 defStand;
	int defStandFrame;

	struct SScoutPoint {
		int spotNum;  // last used spot number in cluster
		int scouted;  // times this point was scouted
		int score;
		int enemyNum;
		IUnitTask* task;
	};
	std::vector<SScoutPoint> scoutPoints;  // list of clusters, index = custerId
	std::map<IUnitTask*, int> scoutTasks;  // task: clusterId
	bool isEnemyFound;

	struct SRoleInfo {
		float cost;
		float maxPerc;
		float factor;
		std::set<CCircuitUnit*> units;
		struct SVsInfo {
			SVsInfo(CCircuitDef::RoleT t, float r, float i) : role(t), ratio(r), importance(i) {}
			CCircuitDef::RoleT role;
			float ratio;
			float importance;
		};
		std::vector<SVsInfo> vs;
	};
	std::vector<SRoleInfo> roleInfos;

	std::set<CCircuitUnit*> stockpilers;
	std::set<CCircuitUnit*> army;
	float armyCost;

	std::map<CCircuitUnit*, CFGuardTask*> guardTasks;

	struct SRaidQuota {
		float min;
		float avg;
	} raid;
	unsigned int maxScouts = 0;
	float minAttackers = 0.f;
	struct SThreatQuota {
		float min;
		float len;
	} attackMod, defenceMod;

	struct SThreatRangeScaling {
		int enemyCountPerEnemyTeamToStartScaling = 0;
		int enemyCountPerEnemyTeamToEndScaling = 1;
		float endScaleValue = 1.f;
		float scale = 1.f;  // cache per frame
		int frame = -1;
	} threatRangeScaling;

	unsigned int preventCount = 0;
	float amountFactor = 0.f;
	CCircuitDef* bigGunDef;

	std::vector<SSideInfo> sideInfos;

	struct SSensorExt {
		float radius;
	};
	CAvailList<SSensorExt> radarDefs, sonarDefs;

	std::shared_ptr<IMainJob> defend;
	std::vector<std::pair<springai::AIFloat3, BuildVector>> buildDefence;  // pos: defences
};

} // namespace circuit

#endif // SRC_CIRCUIT_MODULE_MILITARYMANAGER_H_
