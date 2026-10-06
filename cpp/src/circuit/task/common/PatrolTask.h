/*
 * PatrolTask.h
 *
 *  Created on: Jan 31, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_COMMON_PATROLTASK_H_
#define SRC_CIRCUIT_TASK_COMMON_PATROLTASK_H_

#include "task/builder/BuilderTask.h"

namespace circuit {

class IPatrolTask: public IBuilderTask {
public:
	IPatrolTask(ITaskModule* mgr, Priority priority,
				const springai::AIFloat3& position,
				int timeout);
	virtual ~IPatrolTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;  // FIXME: Remove when proper task assignment implemented

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;

	// apex: walk to the point and stand, instead of patrolling there -- a
	// patrolling builder stops for every tree and wreck on the way.
	void SetMove(bool value) { isMove = value; }
protected:
	virtual void Finish() override;
	virtual void Cancel() override;

	virtual bool Execute(CCircuitUnit* unit) override;

	bool isMove = false;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_COMMON_PATROLTASK_H_
