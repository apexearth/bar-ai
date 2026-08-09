/*
 * FighterTask.cpp
 *
 *  Created on: Aug 31, 2015
 *      Author: rlcevg
 */

#include "task/fighter/FighterTask.h"
#include "task/RetreatTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/BuilderManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "unit/action/RearmAction.h"
#include "unit/action/DGunAction.h"
#include "unit/action/TravelAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

namespace circuit {

using namespace springai;

F3Vec IFighterTask::urgentPositions;  // NOTE: micro-opt
F3Vec IFighterTask::enemyPositions;  // NOTE: micro-opt

IFighterTask::IFighterTask(ITaskModule* mgr, FightType type, float powerMod, int timeout)
		: IUnitTask(mgr, Priority::NORMAL, Type::FIGHTER, timeout)
		, fightType(type)
		, position(-RgtVector)
		, attackPower(.0f)
		, powerMod(powerMod)
		, attackFrame(-1)
		, target(nullptr)
{
}

IFighterTask::~IFighterTask()
{
	if (target != nullptr) {
		target->UnbindTask(this);
	}
}

void IFighterTask::AssignTo(CCircuitUnit* unit)
{
	IUnitTask::AssignTo(unit);

	CCircuitDef* cdef = unit->GetCircuitDef();
	attackPower += cdef->GetPower();
	if (unit->HasShield()) {
		shields.insert(unit);
	}

	if (cdef->IsAttrRearm()) {
		unit->PushBack(new CRearmAction(unit));
	}

	if (unit->HasDGun()) {
		const float range = std::max(unit->GetDGunRange() * 1.1f, cdef->GetLosRadius());
		unit->PushDGunAct(new CDGunAction(unit, range));
	}
}

void IFighterTask::RemoveAssignee(CCircuitUnit* unit)
{
	IUnitTask::RemoveAssignee(unit);

	attackPower -= unit->GetCircuitDef()->GetPower();
	cowards.erase(unit);
	if (unit->HasShield()) {
		shields.erase(unit);
	}
}

void IFighterTask::Update()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const float minShield = circuit->GetSetupManager()->GetEmptyShield();
	decltype(units) tmpUnits = shields;
	for (CCircuitUnit* unit : tmpUnits) {
		if (!unit->IsShieldCharged(minShield)) {
			CRetreatTask* task = manager->EnqueueRetreat();
			manager->AssignTask(unit, task);
		}
	}
}

void IFighterTask::OnUnitIdle(CCircuitUnit* unit)
{
	auto it = cowards.find(unit);
	if (it != cowards.end()) {
		cowards.erase(it);
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
	} else {
		unit->SetTaskFrame(manager->GetCircuit()->GetLastFrame());
	}
}

// Repairing a damaged unit MID-FIGHT was gated on IsRoleHeavy(), which in this
// config is essentially T3 plus armfboy -- so for a normal army the repair path
// was nearly dead, and a unit only ever got repaired after it had already given
// up and retreated. apexearth: "if constructors are also helping to heal us
// while we fight, all these things can really help us to turn things around."
//
// Cost is the filter instead of role: repairing a 42-metal Grunt is not worth a
// constructor's walk, repairing a 665-metal Tiger plainly is.
// 150 made this "every damaged unit in the army", each enqueued at Priority::NOW,
// which preempts construction: constructors left the base to chase damaged units
// into the fight. Build power is the economy, so this was paid for out of it.
#define REPAIR_WORTH_COST	900.f

static inline bool IsWorthRepair(CCircuitDef* cdef)
{
	return (cdef->GetCostM() >= REPAIR_WORTH_COST) && !cdef->IsRoleComm();
}

void IFighterTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CCircuitDef* cdef = unit->GetCircuitDef();
	unit->ForceUpdate(frame + THREAT_UPDATE_RATE);

	// FIXME: comm kamikaze
	if (cdef->IsRoleComm() && (target != nullptr) && target->IsInLOS() && target->GetCircuitDef()->IsRoleComm()) {
		return;
	}

	// Committed push: do not peel off. apexearth: "Need to ensure the units
	// don't suddenly say 'oh lets regroup somewhere safe!' because their purpose
	// is to kill bases, and they probably can't get away on larger maps."
	// Retreating mid-breakthrough is worse than dying in it -- a unit that turns
	// around is killed anyway on the walk home AND gives up the gap it opened.
	// Commanders still retreat: losing one loses the game, which is a different
	// trade entirely.
	if (circuit->IsCommitted() && !cdef->IsRoleComm()) {
		return;
	}

	const float healthPerc = unit->GetHealthPercent();

	if (unit->HasShield()) {
		const float minShield = circuit->GetSetupManager()->GetEmptyShield();
		if ((healthPerc > cdef->GetRetreat()) && unit->IsShieldCharged(minShield)) {
			if (IsWorthRepair(cdef) && (healthPerc < 0.9f) && !unit->IsAttrNoRepair()) {
				circuit->GetBuilderManager()->Enqueue(TaskB::Repair(IBuilderTask::Priority::NOW, unit));
			}
			return;
		}
	} else if ((healthPerc > cdef->GetRetreat()) && !unit->IsDisarmed(frame)) {
		if (IsWorthRepair(cdef) && (healthPerc < 0.9f) && !unit->IsAttrNoRepair()) {
			circuit->GetBuilderManager()->Enqueue(TaskB::Repair(IBuilderTask::Priority::NOW, unit));
		}
		if (healthPerc < cdef->GetSelfDHP()) {
			unit->CmdSelfD(true);
		}
		return;
	} else if (healthPerc < 0.2f) {  // stuck units workaround: they don't shoot and don't see distant threat
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
		return;
	}

	CThreatMap* threatMap = circuit->GetThreatMap();
	const float range = cdef->GetMaxRange();
	if ((target == nullptr) || !target->IsInLOS()) {
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
		return;
	}
	const AIFloat3& pos = unit->GetPos(frame);
	if ((target->GetPos().SqDistance2D(pos) > SQUARE(range)) ||
		(threatMap->GetThreatAt(unit, pos) * 2 > threatMap->GetUnitPower(unit)))
	{
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
		return;
	}
	cowards.insert(unit);
}

void IFighterTask::OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	RemoveAssignee(unit);
}

void IFighterTask::SetTarget(CEnemyInfo* enemy)
{
	if (target != nullptr) {
		target->UnbindTask(this);
	}
	if (enemy != nullptr) {
		enemy->BindTask(this);
	}
	target = enemy;
}

void IFighterTask::Attack(CCircuitUnit* unit, const int frame)
{
	assert((unit->GetTravelAct() != nullptr) && (GetTarget() != nullptr));

	if (unit->Blocker() != nullptr) {
		return;  // Do not interrupt current action
	}
	unit->GetTravelAct()->StateWait();

	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& tPos = GetTarget()->GetPos();
	const int targetTile = circuit->GetInflMap()->Pos2Index(tPos);
	const bool isRepeatAttack = (frame >= attackFrame + FRAMES_PER_SEC * 3);
	attackFrame = isRepeatAttack ? frame : attackFrame;

	if (!isRepeatAttack
		&& (unit->GetTarget() == GetTarget())
		&& (unit->GetTargetTile() == targetTile))
	{
		return;
	}

	CCircuitDef* cdef = unit->GetCircuitDef();
	AIFloat3 dir = unit->GetPos(frame) - tPos;
	if (cdef->IsPlane() || (std::fabs(dir.y) > cdef->GetMaxRange() * 0.5f)) {
		unit->Attack(GetTarget(), GetTarget()->GetUnit()->IsCloaked(), frame + FRAMES_PER_SEC * 60);
		return;
	}
	dir.Normalize2D();

	CCircuitDef* edef = GetTarget()->GetCircuitDef();
	const bool isStatic = (edef != nullptr) && !edef->IsMobile();

	// Same fix as ISquadTask::AssignTo/RemoveAssignee (SquadTask.cpp): a
	// multi-weapon unit's GetMinRange() is its SHORTEST weapon's range, not
	// its real engagement distance. GetMaxRange() matches what the rest of
	// this codebase's combat logic already treats as "how close this unit
	// needs to get."
	const float range = std::min(cdef->GetMaxRange(), cdef->GetLosRadius()) * RANGE_MOD;
	AIFloat3 newPos(tPos.x + range * dir.x, tPos.y, tPos.z + range * dir.z);
	CTerrainManager::CorrectPosition(newPos);
	unit->Attack(newPos, GetTarget(), targetTile, GetTarget()->GetUnit()->IsCloaked(), isStatic, frame + FRAMES_PER_SEC * 60);
}

#ifdef DEBUG_VIS
void IFighterTask::Log()
{
	IUnitTask::Log();

	CCircuitAI* circuit = manager->GetCircuit();
	circuit->GetDrawer()->AddPoint(position, "position");
	circuit->LOG("fightType: %i | attackPower: %f | powerMod: %f", fightType, attackPower, powerMod);
	if (target != nullptr) {
		circuit->GetDrawer()->AddPoint(target->GetPos(), "target");
	}
}
#endif

} // namespace circuit
