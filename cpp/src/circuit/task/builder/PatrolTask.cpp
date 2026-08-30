/*
 * PatrolTask.cpp
 *
 *  Created on: Dec 15, 2025
 *      Author: rlcevg
 */

#include "task/builder/PatrolTask.h"
#include "unit/CircuitUnit.h"
#include "unit/action/DGunAction.h"
//#include "unit/action/CaptureAction.h"
#include "util/Utils.h"

namespace circuit {

using namespace springai;

CBPatrolTask::CBPatrolTask(ITaskModule* mgr, Priority priority,
						   const AIFloat3& position,
						   int timeout)
		: IPatrolTask(mgr, priority, position, timeout)
{
}

CBPatrolTask::~CBPatrolTask()
{
}

void CBPatrolTask::AssignTo(CCircuitUnit* unit)
{
	IPatrolTask::AssignTo(unit);

	if (unit->HasDGun()) {
		// apex: dgun range only, not LOS -- same as BuilderTask; a patrolling
		// builder must not pursue everything in sight. mayClose: a target
		// worth more than the owner is the one exception (see BuilderTask).
		unit->PushDGunAct(new CDGunAction(unit, unit->GetDGunRange(), true));
	}
//	if (unit->GetCircuitDef()->IsAbleToCapture()) {
//		unit->PushBack(new CCaptureAction(unit, 500.f));
//	}
}

} /* namespace circuit */
