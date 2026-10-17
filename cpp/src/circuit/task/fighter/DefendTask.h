/*
 * DefendTask.h
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_

#include "task/fighter/SquadTask.h"

#include <map>

namespace circuit {

class CEnemyInfo;

class CDefendTask: public ISquadTask {
public:
	CDefendTask(ITaskModule* mgr, const springai::AIFloat3& position,
				FightType check, FightType promote, float maxPower, float powerMod);
	virtual ~CDefendTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;
	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;

	// apex_birth_defend: hold `at` against what engages it, released once nothing has for a few seconds.
	void SetBirth(const springai::AIFloat3& at, float reach);
	void AddBirthUnit(CCircuitUnit* unit, float reach);
	bool IsBirth() const { return birth; }
	const springai::AIFloat3& GetAnchor() const { return anchor; }
	float GetBirthReach() const { return birthReach; }

	void SetPosition(const springai::AIFloat3& pos) { position = pos; }
	void SetMaxPower(float power) { maxPower = power * powerMod; }
//	void SetWantedTarget(CEnemyInfo* enemy) { SetTarget(enemy); }

	FightType GetPromote() const { return promote; }
	// A hold pool (promote MELEE) is a state, not a capture: the script
	// releases it to stock's exit when the hold no longer applies.
	void SetPromote(FightType type) { check = type; promote = type; }

protected:
	float GetMaxPower() const { return maxPower; }

private:
	virtual void MergeFrom(ISquadTask* task) override;
	bool FindTarget();
	void StockUpdate();  // apex_stock_army (StockFight.inl)
	bool StockFindTarget();
	void ApplyTargetPath(const CQueryPathMulti* query);
	void FallbackFrontPos();
	void ApplyFrontPos(const CQueryPathMulti* query);
	void FallbackBasePos();
	void ApplyBasePos(const CQueryPathSingle* query);
	void Fallback();

	FightType check;
	FightType promote;
	float maxPower;
	int pettyLogAt = 0;
	int leashLogAt = 0;   // apex: the defend-leash line, at most every 30 s per task
	int detachUntil = 0;  // apex: a squad split off for one raider; no merge, no promote, no recruits
	int Detach(CEnemyInfo* enemy, float threat);

	void BirthUpdate();
	void PathToEnemies(int frame);
	bool birth = false;
	bool releasing = false;
	springai::AIFloat3 anchor;
	float birthReach = 0.f;
	int lastThreat = 0;
	CCircuitUnit* damagedNow = nullptr;
	std::map<CCircuitUnit*, int> birthJoined;
	int chaseFrame = -1;   // apex: chase-stat, the last pick of a target faster than us
	springai::AIFloat3 chasePos;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
