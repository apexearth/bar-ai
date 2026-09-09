/*
 * ReclaimTask.cpp
 *
 *  Created on: Sep 4, 2016
 *      Author: rlcevg
 */

#include "task/common/ReclaimTask.h"
#include "module/TaskModule.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "AISCommands.h"
#include "Log.h"

namespace circuit {

using namespace springai;

IReclaimTask::IReclaimTask(ITaskModule* mgr, Priority priority, Type type,
						   const AIFloat3& position,
						   SResource cost, int timeout, float radius, bool isMetal)
		: IBuilderTask(mgr, priority, nullptr, position, type, BuildType::RECLAIM, cost, 0.f, timeout)
		, radius(radius)
		, isMetal(isMetal)
{
}

IReclaimTask::IReclaimTask(ITaskModule* mgr, Priority priority, Type type,
						   CCircuitUnit* target,
						   int timeout)
		: IBuilderTask(mgr, priority, nullptr, -RgtVector, type, BuildType::RECLAIM, {1000.f, 0.f}, 0.f, timeout)
		, radius(0.f)
		, isMetal(false)
{
	SetTarget(target);
}

IReclaimTask::IReclaimTask(ITaskModule* mgr, Type type)
		: IBuilderTask(mgr, type, BuildType::RECLAIM)
		, radius(0.f)
		, isMetal(false)
{
}

IReclaimTask::~IReclaimTask()
{
}

bool IReclaimTask::CanAssignTo(CCircuitUnit* unit) const
{
	return unit->GetCircuitDef()->IsAbleToReclaim() && (cost.metal > buildPower.metal * MAX_BUILD_SEC);
}

void IReclaimTask::RemoveAssignee(CCircuitUnit* unit)
{
	IBuilderTask::RemoveAssignee(unit);
	if (units.empty()) {
		manager->AbortTask(this);
	}
}

void IReclaimTask::Finish()
{
}

void IReclaimTask::Cancel()
{
}

// Elmos of daylight left between a reclaim circle and a commander corpse.
static constexpr float COM_CORPSE_CLEAR = 96.f;

bool IReclaimTask::Execute(CCircuitUnit* unit)
{
	executors.insert(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	TRY_UNIT(circuit, unit,
		unit->CmdPriority(ClampPriority());
	)

	const int frame = circuit->GetLastFrame();
	if (target != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->CmdReclaimUnit(target, UNIT_CMD_OPTION, frame + FRAMES_PER_SEC * 60);
		)
		return true;
	}

	AIFloat3 pos;
	float reclRadius;
	if ((radius == .0f) || !utils::is_valid(position)) {
		pos = circuit->GetTerrainManager()->GetTerrainCenter();
		reclRadius = pos.Length2D();
	} else {
		pos = position;
		reclRadius = radius;
	}
	// apex: A COMMANDER CORPSE IS NEVER FOOD (apexearth: "make sure nano
	// turrets don't reclaim dead commanders"). The per-feature filter in
	// CBReclaimTask guards only the targeted search; an area command takes
	// whatever is inside the circle, and a nano turret's circle is its own
	// base -- exactly where our commander falls. Aim at the richest wreck
	// that is not the corpse and pull the circle in short of it; if that
	// leaves nothing to eat, there is no reclaim to do here.
	const AIFloat3 comPos = circuit->GetCommanderWreckPos(pos, reclRadius);
	if (utils::is_valid(comPos)) {
		const AIFloat3 body = circuit->GetBestWreckPos(pos, reclRadius, 1.f);
		if (!utils::is_valid(body)) {
			return false;   // idle: OnUnitIdle retires the task
		}
		pos = body;
		const float clear = pos.distance2D(comPos) - COM_CORPSE_CLEAR;
		if (clear < COM_CORPSE_CLEAR) {
			return false;
		}
		if (reclRadius > clear) {
			reclRadius = clear;
		}
		circuit->LOG("apex: corpse-guard t=%i r=%.0f -- reclaim circle pulled off a commander corpse",
				circuit->GetTeamId(), reclRadius);
	}
	TRY_UNIT(circuit, unit,
		// NOTE: CONTROL_KEY enables special mode that ignores autoreclaimable value
		unit->CmdReclaimInArea(pos, reclRadius, UNIT_COMMAND_OPTION_CONTROL_KEY, frame + FRAMES_PER_SEC * 60);
	)
	return true;
}

void IReclaimTask::OnUnitIdle(CCircuitUnit* unit)
{
	manager->AbortTask(this);
}

void IReclaimTask::SetTarget(CCircuitUnit* unit)
{
	target = unit;
	buildPos = (unit != nullptr) ? unit->GetPos(manager->GetCircuit()->GetLastFrame()) : AIFloat3(-RgtVector);
}

bool IReclaimTask::IsInRange(const AIFloat3& pos, float range) const
{
	return position.SqDistance2D(pos) <= SQUARE(radius + range);
}

#define SERIALIZE(stream, func)	\
	utils::binary_##func(stream, radius);		\
	utils::binary_##func(stream, isMetal);

bool IReclaimTask::Load(std::istream& is)
{
	IBuilderTask::Load(is);
	SERIALIZE(is, read)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | radius=%f | isMetal=%i", __PRETTY_FUNCTION__, radius, isMetal);
#endif
	return true;
}

void IReclaimTask::Save(std::ostream& os) const
{
	IBuilderTask::Save(os);
	SERIALIZE(os, write)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | radius=%f | isMetal=%i", __PRETTY_FUNCTION__, radius, isMetal);
#endif
}

} // namespace circuit
