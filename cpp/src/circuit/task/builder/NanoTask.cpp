/*
 * NanoTask.cpp
 *
 *  Created on: Jan 30, 2015
 *      Author: rlcevg
 */

#include "task/builder/NanoTask.h"
#include "module/TaskModule.h"
#include "map/ThreatMap.h"
#include "resource/MetalManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "AISCommands.h"

namespace circuit {

using namespace springai;

CBNanoTask::CBNanoTask(ITaskModule* mgr, Priority priority,
					   CCircuitDef* buildDef, const AIFloat3& position,
					   SResource cost, float shake, int timeout)
		: IBuilderTask(mgr, priority, buildDef, position, Type::BUILDER, BuildType::NANO, cost, shake, timeout)
{
}

CBNanoTask::CBNanoTask(ITaskModule* mgr)
		: IBuilderTask(mgr, Type::BUILDER, BuildType::NANO)
{
}

CBNanoTask::~CBNanoTask()
{
}

bool CBNanoTask::Execute(CCircuitUnit* unit)
{
	// THE BASE SEARCH, NOT A PRIVATE ONE. This override searched square by
	// square inside the turret's build distance and never touched the
	// lattice, so every turret whose packed cell was taken stood one square
	// off the block -- the "one space away" he watched (the census read 7 of
	// 12 turrets off the row).
	return IBuilderTask::Execute(unit);
}

} // namespace circuit
