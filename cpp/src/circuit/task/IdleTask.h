/*
 * IdleTask.h
 *
 *  Created on: Jan 13, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_IDLETASK_H_
#define SRC_CIRCUIT_TASK_IDLETASK_H_

#include "task/UnitTask.h"

#include <vector>

namespace circuit {

class CIdleTask: public IUnitTask {
public:
	CIdleTask(ITaskModule* mgr);
	virtual ~CIdleTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;
	virtual void Stop(bool done) override;

	virtual void OnUnitIdle(CCircuitUnit* unit) override;
	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;

private:
	std::set<CCircuitUnit*> updateUnits;
	unsigned int updateSlice;
	float sliceCredit = 0.f;
	std::vector<int> gapFrames;   // apex: idle-to-task waits of mobile builders, logged per minute
	int refusedAsks = 0;
	int nextGapLog = 0;
	float askFrames = 0.f;     // apex_idle_ask_f, read once
	int settleFrames = 20;     // apex_idle_settle_f
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_IDLETASK_H_
