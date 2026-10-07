/*
 * GuardTask.h
 *
 *  Created on: Jul 13, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_BUILDER_GUARDTASK_H_
#define SRC_CIRCUIT_TASK_BUILDER_GUARDTASK_H_

#include "task/builder/BuilderTask.h"
#include "unit/CircuitUnit.h"

namespace circuit {

class CBGuardTask: public IBuilderTask {
public:
	CBGuardTask(ITaskModule* mgr, Priority priority,
				CCircuitUnit* vip, bool isInterrupt, int timeout);
	// apex: an ALLY's unit -- assist its frame or its factory.
	CBGuardTask(ITaskModule* mgr, Priority priority,
				ICoreUnit::Id allyId, const springai::AIFloat3& pos, int timeout);
	virtual ~CBGuardTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Stop(bool done) override;
	virtual void Update() override;

protected:
	virtual bool Execute(CCircuitUnit* unit) override;

public:
	virtual void OnUnitIdle(CCircuitUnit* unit) override;

protected:
	virtual bool Reevaluate(CCircuitUnit* unit);

private:
	bool IsTargetBuilder() const;
	CAllyUnit* Vip() const;

	ICoreUnit::Id vipId;
	bool isAlly = false;
	bool isInterrupt;
	bool isFrame;  // vip was a nanoframe when taken; the guard ends with it
	IUnitTask* vipTask;  // a mobile vip's job when taken; the guard ends when it changes
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_BUILDER_GUARDTASK_H_
