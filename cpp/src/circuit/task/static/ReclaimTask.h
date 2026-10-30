/*
 * ReclaimTask.h
 *
 *  Created on: Mar 31, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_STATIC_RECLAIMTASK_H_
#define SRC_CIRCUIT_TASK_STATIC_RECLAIMTASK_H_

#include "task/common/ReclaimTask.h"

namespace circuit {

class CSReclaimTask: public IReclaimTask {
public:
	CSReclaimTask(ITaskModule* mgr, Priority priority,
				  const springai::AIFloat3& position,
				  SResource cost, int timeout, float radius = .0f);
	CSReclaimTask(ITaskModule* mgr, Priority priority, CCircuitUnit* target, int timeout);
	virtual ~CSReclaimTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;

	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
};

// apex: TURRETS EAT A TEAMMATE'S BUILDING THEMSELVES (his 10-30: "why ask a teammate to reclaim when we can do it
// ourselves?" -- BAR lets a player reclaim an ally's building, and our own turrets stand in our lanes). Held by unit id
// and looked up each time, never by pointer: an ally's unit object is freed with the unit (the repair task's
// 2026-08-15 crash). The task ends when the building is gone.
class CSReclaimAllyTask: public CSReclaimTask {
public:
	CSReclaimAllyTask(ITaskModule* mgr, Priority priority, ICoreUnit::Id allyId, const springai::AIFloat3& position,
					  int timeout);
	virtual ~CSReclaimAllyTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void Update() override;
	virtual void OnUnitIdle(CCircuitUnit* unit) override;

protected:
	virtual bool Execute(CCircuitUnit* unit) override;

private:
	ICoreUnit::Id allyId;
	int updN = 0;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_STATIC_RECLAIMTASK_H_
