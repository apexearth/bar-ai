/*
 * TaskModule.h
 *
 *  Created on: Jan 20, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_MODULE_TASKMODULE_H_
#define SRC_CIRCUIT_MODULE_TASKMODULE_H_

#include "module/Module.h"

#include <algorithm>
#include <vector>

namespace circuit {

class IUnitTask;
class CCircuitAI;
class CCircuitUnit;
class CNilTask;
class CIdleTask;
class CPlayerTask;
class CRetreatTask;

class ITaskModule: public IModule {  // CActionList; UnitManager and TaskManager
protected:
	ITaskModule(CCircuitAI* circuit, IScript* script);
public:
	virtual ~ITaskModule();

	void Init();
	void Release();

	virtual void AssignTask(CCircuitUnit* unit, IUnitTask* task);
	// Returns the task it assigned, with ONE reference transferred to the
	// caller (who must Release), or nullptr. Callers must use this return
	// value, never re-read unit->GetTask() afterwards: assignment runs script
	// (AiMakeTask, TaskAssigned), which can abort or complete tasks, leaving
	// the unit's bare task pointer dangling -- crashed live at
	// CIdleTask::Update 2026-08-15 through exactly that stale re-read.
	virtual IUnitTask* AssignTask(CCircuitUnit* unit);
protected:
	virtual void DequeueTask(IUnitTask* task, bool done = false);

public:
	virtual void FallbackTask(CCircuitUnit* unit) {}
	void AbortTask(IUnitTask* task) { DequeueTask(task, false); }
	void DoneTask(IUnitTask* task) { DequeueTask(task, true); }

public:
	// script hooks
	virtual IUnitTask* MakeTask(CCircuitUnit* unit);
	void TaskAdded(IUnitTask* task);
	void TaskRemoved(IUnitTask* task, bool done);

	// script API
	virtual IUnitTask* DefaultMakeTask(CCircuitUnit* unit) = 0;

public:
	CIdleTask* GetIdleTask() const { return idleTask; }
	virtual CRetreatTask* EnqueueRetreat() { return nullptr; }

	void AssignPlayerTask(CCircuitUnit* unit);
	void Resurrected(CCircuitUnit* unit);

	void AddMetalPull(float value) { metalPull += value; }
	void DelMetalPull(float value) { metalPull -= value; }
	float GetMetalPull() const { return metalPull; }

protected:
	void UpdateIdle();
	void Update();

	CNilTask* nilTask;
	CIdleTask* idleTask;
	CPlayerTask* playerTask;

	// CRASH DIAGNOSTIC (temporary): all pushes go through PushUpdate so a
	// duplicate listing — which the reaper would double-ClearRelease, the
	// actionUnits disease all over again — traps AT THE PUSH that creates it.
	void PushUpdate(IUnitTask* task) {
		if (std::find(updateTasks.begin(), updateTasks.end(), task) != updateTasks.end()) {
			__builtin_trap();
		}
		updateTasks.push_back(task);
	}
	std::vector<IUnitTask*> updateTasks;  // owner
	unsigned int updateIterator;

	float metalPull;
};

} // namespace circuit

#endif // SRC_CIRCUIT_MODULE_TASKMODULE_H_
