/*
 * PatrolTask.h
 *
 *  Created on: Dec 15, 2025
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_STATIC_PATROLTASK_H_
#define SRC_CIRCUIT_TASK_STATIC_PATROLTASK_H_

#include "task/common/PatrolTask.h"

namespace circuit {

class CSPatrolTask: public IPatrolTask {
public:
	CSPatrolTask(ITaskModule* mgr, Priority priority,
				 const springai::AIFloat3& position,
				 int timeout);
	virtual ~CSPatrolTask();

	virtual void AssignTo(CCircuitUnit* unit) override;

	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
};

} /* namespace circuit */

#endif /* SRC_CIRCUIT_TASK_STATIC_PATROLTASK_H_ */
