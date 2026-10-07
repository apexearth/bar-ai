/*
 * GuardTask.cpp
 *
 *  Created on: Jul 13, 2016
 *      Author: rlcevg
 */

#include "task/builder/GuardTask.h"
#include "module/BuilderManager.h"
#include "terrain/TerrainManager.h"  // Only for CorrectPosition
#include "CircuitAI.h"
#include "util/Utils.h"

#include "AISCommands.h"

namespace circuit {

CBGuardTask::CBGuardTask(ITaskModule* mgr, Priority priority, CCircuitUnit* vip, bool isInterrupt, int timeout)
		: IBuilderTask(mgr, priority, nullptr, vip->GetPos(mgr->GetCircuit()->GetLastFrame()),
					   Type::BUILDER, BuildType::GUARD, {0.f, 0.f}, 0.f, timeout)
		, vipId(vip->GetId())
		, isInterrupt(isInterrupt)
		, isFrame(!vip->IsFinished())
		, vipTask(vip->GetTask())
{
}

CBGuardTask::CBGuardTask(ITaskModule* mgr, Priority priority,
		ICoreUnit::Id allyId, const AIFloat3& pos, int timeout)
		: IBuilderTask(mgr, priority, nullptr, pos, Type::BUILDER, BuildType::GUARD, {0.f, 0.f}, 0.f, timeout)
		, vipId(allyId)
		, isAlly(true)
		, isInterrupt(false)
		, isFrame(false)
		, vipTask(nullptr)
{
	CAllyUnit* vip = Vip();
	isFrame = (vip != nullptr) && vip->GetUnit()->IsBeingBuilt();
}

CAllyUnit* CBGuardTask::Vip() const
{
	CCircuitAI* circuit = manager->GetCircuit();
	return isAlly ? circuit->GetFriendlyUnit(vipId) : circuit->GetTeamUnit(vipId);
}

CBGuardTask::~CBGuardTask()
{
}

bool CBGuardTask::CanAssignTo(CCircuitUnit* unit) const
{
	return true;
}

void CBGuardTask::AssignTo(CCircuitUnit* unit)
{
	IBuilderTask::AssignTo(unit);

	CCircuitDef* cdef = unit->GetCircuitDef();
	if (IsTargetBuilder()) {
		if (cdef->IsAbleToAssist()) {
			static_cast<CBuilderManager*>(manager)->IncGuardCount();
		}
	} else if (cdef->IsBuilder()) {
		// not testing IsAbleToAssist as AddBuildPower applied only to IsBuilder in CBuilderManager
		static_cast<CBuilderManager*>(manager)->DelBuildPower(unit);
	}

	if (!isInterrupt) {
		lastTouched = manager->GetCircuit()->GetLastFrame();
	}
}

void CBGuardTask::RemoveAssignee(CCircuitUnit* unit)
{
	IBuilderTask::RemoveAssignee(unit);
	if (units.empty()) {
		manager->AbortTask(this);
	}

	CCircuitDef* cdef = unit->GetCircuitDef();
	if (IsTargetBuilder()) {
		if (cdef->IsAbleToAssist()) {
			static_cast<CBuilderManager*>(manager)->DecGuardCount();
		}
	} else if (cdef->IsBuilder()) {
		static_cast<CBuilderManager*>(manager)->AddBuildPower(unit);
	}
}

void CBGuardTask::Stop(bool done)
{
	const bool isVIPBuilder = IsTargetBuilder();
	for (CCircuitUnit* unit : units) {
		CCircuitDef* cdef = unit->GetCircuitDef();
		if (isVIPBuilder) {
			if (cdef->IsAbleToAssist()) {
				static_cast<CBuilderManager*>(manager)->DecGuardCount();
			}
		} else if (cdef->IsBuilder()) {
			static_cast<CBuilderManager*>(manager)->AddBuildPower(unit);
		}
	}

	IBuilderTask::Stop(done);
}

// A guard taken on a nanoframe is a build, and it ends when the frame does.
// Nothing else ends it: a Guard has no target, so the base class never sees
// completion, and a hold sized for one pair of hands outlived a many-handed
// afus by twenty minutes (apexearth 2026-09-08).
void CBGuardTask::Update()
{
	CAllyUnit* ally = Vip();
	CCircuitUnit* vip = isAlly ? nullptr : static_cast<CCircuitUnit*>(ally);
	if (isAlly) {
		if ((ally == nullptr) || (isFrame && !ally->GetUnit()->IsBeingBuilt())) {
			manager->AbortTask(this);
			return;
		}
	} else if (isFrame) {
		if ((vip == nullptr) || vip->IsFinished()) {
			manager->AbortTask(this);
			return;
		}
	} else if ((vip == nullptr)
		|| (vip->GetCircuitDef()->IsMobile() && (vip->GetTask() != vipTask)))
	{
		// A guard on a CONSTRUCTOR was priced for the job it was raising;
		// when that con moves to its next job the assist follows it across
		// the base for the rest of the stint (apexearth 2026-09-14: "once we
		// start to guard a constructor, we rarely consider stopping that
		// guard action"). The job ending ends the guard. A FACTORY's job is
		// producing and its task rolls over with every unit it finishes, so
		// the same test cut every plant assist to one unit's build time.
		manager->AbortTask(this);
		return;
	}
	IBuilderTask::Update();
}

bool CBGuardTask::Execute(CCircuitUnit* unit)
{
	executors.insert(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	CAllyUnit* vip = Vip();
	if (vip != nullptr) {
		const int frame = circuit->GetLastFrame();
		const AIFloat3& vipPos = vip->GetPos(frame);
		const AIFloat3& unitPos = unit->GetPos(frame);
		TRY_UNIT(circuit, unit,
			unit->CmdPriority(ClampPriority());
			short options = UNIT_CMD_OPTION;
			// FIXME: it's not "Smooth area" and is broken when waterlevel is changed
//			if (unit->GetCircuitDef()->IsAbleToRestore()) {
//				unit->GetUnit()->RestoreArea(vip->GetPos(circuit->GetLastFrame()), 128.f);
//				options = UNIT_COMMAND_OPTION_SHIFT_KEY;
//			}
			if ((unit->GetCircuitDef()->GetBuildDistance() > 80.f) && (vipPos.SqDistance2D(unitPos) < SQUARE(48.f))) {
				AIFloat3 pos = vipPos + (unitPos - vipPos).Normalize2D() * 64.f;
				CTerrainManager::CorrectPosition(pos);
				unit->CmdMoveTo(pos, options | UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::GUARD);
				options = UNIT_COMMAND_OPTION_SHIFT_KEY;
			}
			unit->GetUnit()->Guard(vip->GetUnit(), options);
		)
	} else {
		manager->AbortTask(this);
		return false;
	}
	return true;
}

void CBGuardTask::OnUnitIdle(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CAllyUnit* vip = Vip();
	if (vip != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->GetUnit()->Guard(vip->GetUnit());
		)
	} else {
		manager->AbortTask(this);
	}
}

bool CBGuardTask::Reevaluate(CCircuitUnit* unit)
{
	if (!isInterrupt) {
		return true;
	}
	return IBuilderTask::Reevaluate(unit);
}

bool CBGuardTask::IsTargetBuilder() const
{
	CAllyUnit* vip = Vip();
	return (vip != nullptr) && vip->GetCircuitDef()->IsBuilder();
}

} // namespace circuit
