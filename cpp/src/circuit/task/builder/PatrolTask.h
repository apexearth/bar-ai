/*
 * PatrolTask.h
 *
 *  Created on: Dec 15, 2025
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_BUILDER_PATROLTASK_H_
#define SRC_CIRCUIT_TASK_BUILDER_PATROLTASK_H_

#include "task/common/PatrolTask.h"

namespace circuit {

class CBPatrolTask: public IPatrolTask {
public:
	CBPatrolTask(ITaskModule* mgr, Priority priority,
				 const springai::AIFloat3& position,
				 int timeout);
	virtual ~CBPatrolTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
};

} /* namespace circuit */

#endif /* SRC_CIRCUIT_TASK_BUILDER_PATROLTASK_H_ */
