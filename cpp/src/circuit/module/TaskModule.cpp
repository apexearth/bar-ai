/*
 * TaskModule.cpp
 *
 *  Created on: Jan 20, 2015
 *      Author: rlcevg
 */

#include "module/TaskModule.h"
#include "script/TaskModuleScript.h"
#include "task/NilTask.h"
#include "task/IdleTask.h"
#include "task/PlayerTask.h"
#include "task/RetreatTask.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Profiler.h"

namespace circuit {

ITaskModule::ITaskModule(CCircuitAI* circuit, IScript* script)
		: IModule(circuit, script)
		, nilTask(nullptr)
		, idleTask(nullptr)
		, playerTask(nullptr)
		, updateIterator(0)
		, metalPull(0.f)
{
	Init();
}

ITaskModule::~ITaskModule()
{
	delete nilTask;
	delete idleTask;
	delete playerTask;

	for (IUnitTask* task : updateTasks) {
		task->ClearRelease();
	}
}

void ITaskModule::Init()
{
	nilTask = new CNilTask(this);
	idleTask = new CIdleTask(this);
	playerTask = new CPlayerTask(this);
}

void ITaskModule::Release()
{
	// NOTE: Release expected to be called on CCircuit::Release.
	//       It doesn't stop scheduled GameTasks for that reason.
	for (IUnitTask* task : updateTasks) {
		AbortTask(task);
		// NOTE: Do not delete task as other AbortTask may ask for it
	}
	for (IUnitTask* task : updateTasks) {
		task->ClearRelease();
	}
	updateTasks.clear();
}

void ITaskModule::AssignTask(CCircuitUnit* unit, IUnitTask* task)
{
	// Same guard as DequeueTask below: task->Start(unit) can run script
	// (Start() dispatches through the task hierarchy, and several task types
	// call into script-visible state from there), and RemoveAssignee/AssignTo
	// give script two more chances to drop a reference before Start() runs.
	// Hold our own across the whole sequence.
	task->AddRef();
	unit->GetTask()->RemoveAssignee(unit);
	task->AssignTo(unit);
	task->Start(unit);
	task->Release();
}

void ITaskModule::AssignTask(CCircuitUnit* unit)
{
	// MakeTask(unit) runs the script's AiMakeTask top to bottom -- confirmed
	// live as a second instance of the DequeueTask bug (same
	// IRefCounter::Release() -> delete this signature, this call chain
	// instead): whatever script does while computing an answer can drop the
	// last reference to some OTHER tracked task, and if the returned task
	// itself is affected the same way, AssignTo(unit) below dereferences it
	// freed. AddRef the moment we have it, for the same reason DequeueTask
	// does.
	IUnitTask* task = MakeTask(unit);
	if (task != nullptr) {
		task->AddRef();
		task->AssignTo(unit);
		task->Release();
	}
}

void ITaskModule::DequeueTask(IUnitTask* task, bool done)
{
	// TaskRemoved() runs the script's AiTaskRemoved callback, which can hold
	// the only remaining AngelScript-side reference to this task (e.g. the
	// last element removed from a tracking array). IUnitTask is asOBJ_REF
	// with intrusive refcounting (RefCounter.cpp) -- if that callback drops
	// the last script reference, Release() deletes the object right there,
	// and task->Stop(done) below becomes a use-after-free on this function's
	// own raw pointer. Confirmed live: symbolized crash at exactly this line
	// (IRefCounter::Release() -> delete this, reached through the script
	// callback, native frame resuming into the freed object). Holding our
	// own reference across the callback is the same guarantee AngelScript's
	// own handle assignment already gives every other caller.
	task->AddRef();
	task->Dead();
	TaskRemoved(task, done);
	task->Stop(done);
	task->Release();
}

IUnitTask* ITaskModule::MakeTask(CCircuitUnit* unit)
{
	return static_cast<ITaskModuleScript*>(script)->MakeTask(unit);  // DefaultMakeTask
}

void ITaskModule::TaskAdded(IUnitTask* task)
{
	static_cast<ITaskModuleScript*>(script)->TaskAdded(task);
}

void ITaskModule::TaskRemoved(IUnitTask* task, bool done)
{
	static_cast<ITaskModuleScript*>(script)->TaskRemoved(task, done);
}

void ITaskModule::AssignPlayerTask(CCircuitUnit* unit)
{
	AssignTask(unit, playerTask);
}

void ITaskModule::Resurrected(CCircuitUnit* unit)
{
	CRetreatTask* task = EnqueueRetreat();
	if (task != nullptr) {
		AssignTask(unit, task);
	}
}

void ITaskModule::UpdateIdle()
{
	ZoneScoped;

	idleTask->Update();
}

void ITaskModule::Update()
{
	ZoneScoped;

	if (updateIterator >= updateTasks.size()) {
		updateIterator = 0;
	}

	int lastFrame = GetCircuit()->GetLastFrame();
	// stagger the Update's
	unsigned int n = (updateTasks.size() / TEAM_SLOWUPDATE_RATE) + 1;

	while ((updateIterator < updateTasks.size()) && (n != 0)) {
		IUnitTask* task = updateTasks[updateIterator];
		if (task->IsDead()) {
			updateTasks[updateIterator] = updateTasks.back();
			updateTasks.pop_back();
			task->ClearRelease();  // delete task;
		} else {
			// NOTE: IFighterTask.timeout = 0
			int frame = task->GetLastTouched();
			int timeout = task->GetTimeout();
			if ((frame != -1) && (timeout > 0) && (lastFrame - frame >= timeout)) {
				AbortTask(task);
			} else {
				task->Update();
			}
			++updateIterator;
			n--;
		}
	}
}

} // namespace circuit
