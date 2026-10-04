/*
 * DefendTask.h
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_

#include "task/fighter/SquadTask.h"

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
	virtual void Merge(ISquadTask* task) override;
	bool FindTarget();
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
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
