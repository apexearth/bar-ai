/*
 * PatrolTask.cpp
 *
 *  Created on: Dec 15, 2025
 *      Author: rlcevg
 */

#include "task/static/PatrolTask.h"
#include "unit/CircuitUnit.h"
#include "unit/action/DGunAction.h"
//#include "unit/action/CaptureAction.h"
#include "util/Utils.h"

namespace circuit {

using namespace springai;

CSPatrolTask::CSPatrolTask(ITaskModule* mgr, Priority priority,
						   const AIFloat3& position,
						   int timeout)
		: IPatrolTask(mgr, priority, position, timeout)
{
}

CSPatrolTask::~CSPatrolTask()
{
}

void CSPatrolTask::AssignTo(CCircuitUnit* unit)
{
	IPatrolTask::AssignTo(unit);

	if (unit->HasDGun()) {
		unit->PushDGunAct(new CDGunAction(unit, unit->GetDGunRange()));
	}
//	if (unit->GetCircuitDef()->IsAbleToCapture()) {
//		unit->PushBack(new CCaptureAction(unit, unit->GetCircuitDef()->GetBuildDistance()));
//	}
}

void CSPatrolTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	if (unit->GetHealthPercent() < unit->GetCircuitDef()->GetSelfDHP()) {
		unit->CmdSelfD(true);
	}
}

} /* namespace circuit */
