/*
 * IdleTask.cpp
 *
 *  Created on: Jan 13, 2015
 *      Author: rlcevg
 */

#include "task/IdleTask.h"
#include "task/RetreatTask.h"
#include "map/InfluenceMap.h"
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

		// Zombies (deferred-deleted dead units, CCircuitAI::deadUnits) can
		// arrive here through stale task memberships; drain them, never
		// hand them to MakeTask.
		if (ass->IsDead()) {
			units.erase(ass);
			it = updateUnits.erase(it);
			continue;
		}

		// get rid of delayed by engine UnitIdle event from previous task
		if (frame < ass->GetTaskFrame() + 20) {
			++it;
			continue;
		}

		it = updateUnits.erase(it);

		// The task comes back from AssignTask itself, with a reference
		// transferred -- never re-read ass->GetTask() here: AssignTask runs
		// script (AiMakeTask, TaskAssigned) which can abort or complete
		// tasks, and the unit's bare task pointer is not refcounted. The
		// previous AddRef bracket around a re-read pointer still crashed
		// (2026-08-15, frame 47331, null vtable call at Start): AddRef on an
		// already-freed object protects nothing.
		IUnitTask* task = manager->AssignTask(ass);  // should RemoveAssignee() on AssignTo()
		if (task != nullptr) {
			if (!task->IsDead()) {
				task->Start(ass);
			}
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
		// AT HOME, A FIGHTER STANDS. Units touch IDLE constantly between task
		// assignments, and one hit under the (high, 0.5-0.85) retreat bar sent
		// each on a solo retreat THROUGH its own base -- the audited fwd~0.15
		// retreat deaths that persisted after both squad-level fixes. The
		// militia pool re-tasks an idle unit within a second; running is what
		// killed them. Builders keep the retreat: their job is not fighting.
		CCircuitAI* circuit = manager->GetCircuit();
		// Defend influence (buildings only) -- ally influence includes nearby
		// mobile army and read "home" in the open field. See TrySquadRetreat.
		if (unit->GetCircuitDef()->IsAttacker()
			&& (circuit->GetInflMap()->GetAllyDefendInflAt(
					unit->GetPos(circuit->GetLastFrame())) > INFL_EPS)) {
			return;
		}
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
