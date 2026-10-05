/*
 * ReclaimTask.cpp
 *
 *  Created on: Mar 31, 2015
 *      Author: rlcevg
 */

#include "task/static/ReclaimTask.h"
#include "module/BuilderManager.h"
#include "module/EconomyManager.h"
#include "module/FactoryManager.h"
#include "unit/action/DGunAction.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"

namespace circuit {

using namespace springai;

CSReclaimTask::CSReclaimTask(ITaskModule* mgr, Priority priority,
							 const AIFloat3& position,
							 SResource cost, int timeout, float radius)
		: IReclaimTask(mgr, priority, Type::FACTORY, position, cost, timeout, radius)
{
}

CSReclaimTask::CSReclaimTask(ITaskModule* mgr, Priority priority, CCircuitUnit* target, int timeout)
		: IReclaimTask(mgr, priority, Type::FACTORY, target, timeout)
{
}

bool CSReclaimTask::CanAssignTo(CCircuitUnit* unit) const
{
	return (target != nullptr) ? unit->GetCircuitDef()->IsAbleToReclaim() : IReclaimTask::CanAssignTo(unit);
}

CSReclaimTask::~CSReclaimTask()
{
}

void CSReclaimTask::AssignTo(CCircuitUnit* unit)
{
	IUnitTask::AssignTo(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	ShowAssignee(unit);
	if (!utils::is_valid(position)) {
		position = unit->GetPos(circuit->GetLastFrame());
	}

	if (unit->HasDGun()) {
		unit->PushDGunAct(new CDGunAction(unit, unit->GetDGunRange()));
	}

	lastTouched = circuit->GetLastFrame();
}

void CSReclaimTask::Start(CCircuitUnit* unit)
{
	Execute(unit);
}

void CSReclaimTask::Update()
{
	// A targeted eat is not traded for a repair job: that trade is what kept a
	// door blocker standing (repaired by the turrets sent to eat it).
	if (target != nullptr) {
		return;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	// A full bank used to abort this task -- and at a hosted game's +100%
	// the bank is pinned full, so nano reclaim never ran at all ("nano
	// turrets were able to reclaim prior..."). Space reclaim matters most
	// exactly when metal is worthless; the emergency metal read is only the
	// stock behavior at apex_nano_space_reclaim=0.
	if (circuit->GetEconomyManager()->IsMetalFull()
		&& (circuit->GetTunable("apex_nano_space_reclaim", 1.f) < 0.5f)) {
		manager->AbortTask(this);
	} else if ((++updCount % 4 == 0) && !units.empty()) {
		// Check for damaged units
		CBuilderManager* builderMgr = circuit->GetBuilderManager();
		CAllyUnit* repairTarget = nullptr;
		circuit->UpdateFriendlyUnits();
		auto& us = circuit->GetCallback()->GetFriendlyUnitsIn(position, radius * 0.9f);
		for (Unit* u : us) {
			auto [cand, isTeam] = circuit->GetTeamOrAllyUnit(u);
			if ((cand == nullptr)  // no self-check
				|| builderMgr->IsReclaimUnit(cand)
				|| (isTeam ? static_cast<CCircuitUnit*>(cand)->IsAttrNoRepair() : cand->GetCircuitDef()->IsAttrNoRepair()))
			{
				continue;
			}
			if (!u->IsBeingBuilt() && (u->GetHealth() < u->GetMaxHealth())) {
				repairTarget = cand;
				break;
			}
		}
		utils::free(us);
		if (repairTarget != nullptr) {
			// Repair task
			IUnitTask* task = circuit->GetFactoryManager()->Enqueue(TaskS::Repair(
					IBuilderTask::Priority::NORMAL, repairTarget));
			decltype(units) tmpUnits = units;
			for (CCircuitUnit* unit : tmpUnits) {
				manager->AssignTask(unit, task);
			}
			manager->AbortTask(this);
		}
	}
}

void CSReclaimTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	if (unit->GetHealthPercent() < unit->GetCircuitDef()->GetSelfDHP()) {
		unit->CmdSelfD(true);
	}
}

} // namespace circuit
