/*
 * PatrolTask.cpp
 *
 *  Created on: Jan 31, 2015
 *      Author: rlcevg
 */

#include "task/common/PatrolTask.h"
#include "module/TaskModule.h"
#include "terrain/TerrainManager.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "Map.h"

namespace circuit {

using namespace springai;

IPatrolTask::IPatrolTask(ITaskModule* mgr, Priority priority,
						 const AIFloat3& position,
						 int timeout)
		: IBuilderTask(mgr, priority, nullptr, position, Type::BUILDER, BuildType::PATROL, {0.f, 0.f}, 0.f, timeout)
{
}

IPatrolTask::~IPatrolTask()
{
}

void IPatrolTask::AssignTo(CCircuitUnit* unit)
{
	IUnitTask::AssignTo(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	ShowAssignee(unit);
	const float size = SQUARE_SIZE * 100;
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	if (!utils::is_valid(position)) {
		AIFloat3 pos = unit->GetPos(circuit->GetLastFrame());
		pos.x += (pos.x > terrainMgr->GetTerrainWidth() / 2) ? -size : size;
		pos.z += (pos.z > terrainMgr->GetTerrainHeight() / 2) ? -size : size;
		CTerrainManager::CorrectPosition(pos);
		position = pos;
	}

	lastTouched = circuit->GetLastFrame();
}

void IPatrolTask::RemoveAssignee(CCircuitUnit* unit)
{
	IBuilderTask::RemoveAssignee(unit);

	manager->AbortTask(this);
}

void IPatrolTask::Start(CCircuitUnit* unit)
{
	Execute(unit);
}

void IPatrolTask::Update()
{
}

void IPatrolTask::Finish()
{
}

void IPatrolTask::Cancel()
{
}

bool IPatrolTask::Execute(CCircuitUnit* unit)
{
	executors.insert(unit);

	CCircuitAI* circuit = manager->GetCircuit();

	TRY_UNIT(circuit, unit,
		unit->CmdPriority(0);
		unit->CmdPatrolTo(position);
	)
	return true;
}

} // namespace circuit
