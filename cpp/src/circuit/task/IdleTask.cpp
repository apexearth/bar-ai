/*
 * IdleTask.cpp
 *
 *  Created on: Jan 13, 2015
 *      Author: rlcevg
 */

#include "task/IdleTask.h"
#include "task/RetreatTask.h"
#include "module/TaskModule.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

namespace circuit {

CIdleTask::CIdleTask(ITaskModule* mgr)
		: IUnitTask(mgr, Priority::NORMAL, Type::IDLE, -1)
		, updateSlice(0)
{
}

CIdleTask::~CIdleTask()
{
}

void CIdleTask::AssignTo(CCircuitUnit* unit)
{
	unit->SetTask(this);
	units.insert(unit);
}

void CIdleTask::RemoveAssignee(CCircuitUnit* unit)
{
	if (units.erase(unit) > 0) {  // double call of this function is OK
		updateUnits.erase(unit);
	}

	unit->ClearAct();
}

void CIdleTask::Start(CCircuitUnit* unit)
{
	// NOTE: may happen when PathRequest wasn't finished in time,
	//       then manager->AssignTask(ass) won't do anything and this->Start() is invoked.
	//       @see CBuilderManager::DefaultMakeTask => return nullptr;
//	assert(false);
}

void CIdleTask::Update()
{
	if (updateUnits.empty()) {
		updateUnits = units;  // copy units
		updateSlice = updateUnits.size() / TEAM_SLOWUPDATE_RATE;
	}

	const int frame = manager->GetCircuit()->GetLastFrame();
	auto it = updateUnits.begin();
	unsigned int i = 0;
	while (it != updateUnits.end()) {
		CCircuitUnit* ass = *it;

		// get rid of delayed by engine UnitIdle event from previous task
		if (frame < ass->GetTaskFrame() + 20) {
			++it;
			continue;
		}

		it = updateUnits.erase(it);

		manager->AssignTask(ass);  // should RemoveAssignee() on AssignTo()
		// AssignTask can legitimately leave the unit taskless -- Start()'s own
		// comment above documents the case (a pending PathRequest making
		// AssignTask() a no-op) -- and this dereferenced it unconditionally.
		// Traced live via addr2line against a debug build: three access
		// violations here across the session, all with this exact frame.
		// unit->task is a bare native pointer (CCircuitUnit::SetTask does no
		// AddRef -- native ownership is tracked separately, via buildTasks/
		// updateTasks membership and explicit DequeueTask/AbortTask), so
		// nothing protects it from the same script-drops-last-reference race
		// as DequeueTask/AssignTask once Start() itself runs script. Hold our
		// own reference across the call, same fix, same reason.
		IUnitTask* task = ass->GetTask();
		if (task != nullptr) {
			task->AddRef();
			task->Start(ass);
			task->Release();
		}

		if (++i >= updateSlice) {
			break;
		}
	}
}

void CIdleTask::Stop(bool done)
{
	// NOTE: Should not be ever called, except on AI termination
	assert(false);
	units.clear();
	updateUnits.clear();
}

void CIdleTask::OnUnitIdle(CCircuitUnit* unit)
{
	// Do nothing. Unit is already idling.
}

void CIdleTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	const float healthPerc = unit->GetHealthPercent();
	if (healthPerc < unit->GetCircuitDef()->GetRetreat()) {
		CRetreatTask* task = manager->EnqueueRetreat();
		if (task != nullptr) {
			task->AssignTo(unit);
			task->Start(unit);
		}
	} else if (healthPerc < unit->GetCircuitDef()->GetSelfDHP()) {
		unit->CmdSelfD(true);
	}
}

void CIdleTask::OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
}

} // namespace circuit
