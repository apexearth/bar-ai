/*
 * GuardTask.cpp
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#include "task/fighter/GuardTask.h"
#include "task/fighter/Catch.h"
#include "module/MilitaryManager.h"
#include "task/builder/BuilderTask.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"

namespace circuit {

using namespace springai;

CFGuardTask::CFGuardTask(ITaskModule* mgr, CCircuitUnit* vip, float maxPower)
		: IFighterTask(mgr, FightType::GUARD, 1.f)
		, vipId(vip->GetId())
		, maxPower(maxPower)
{
	static_cast<CMilitaryManager*>(mgr)->MarkGuardUnit(vip, this);
}

CFGuardTask::~CFGuardTask()
{
}

bool CFGuardTask::CanAssignTo(CCircuitUnit* unit) const
{
	CCircuitAI* circuit = manager->GetCircuit();
	unsigned int guardsNum = circuit->GetMilitaryManager()->GetGuardsNum();
	if (unit->GetCircuitDef()->IsRoleRiot()) {
		guardsNum /= 2;
	}
	if (units.size() >= guardsNum) {
		return false;
	}
	CCircuitUnit* vip = circuit->GetTeamUnit(vipId);
	if (vip == nullptr) {
		return false;
	}
	if (((unit->GetCircuitDef()->IsAmphibious() || unit->GetCircuitDef()->IsSurfer())
			&& (vip->GetCircuitDef()->IsAbleToDive() || vip->GetCircuitDef()->IsSurfer()))
		|| (vip->GetCircuitDef()->IsSubmarine() && unit->GetCircuitDef()->IsSubmarine())
		|| (vip->GetCircuitDef()->IsAbleToFly() && unit->GetCircuitDef()->IsAbleToFly())
		|| (vip->GetCircuitDef()->IsLander() && unit->GetCircuitDef()->IsLander())
		|| (vip->GetCircuitDef()->IsFloater() && unit->GetCircuitDef()->IsFloater()))
	{
		return true;
	}
	return false;
}

void CFGuardTask::Start(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitUnit* vip = circuit->GetTeamUnit(vipId);
	if (vip != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->GetUnit()->Guard(vip->GetUnit());
			unit->CmdWantedSpeed(NO_SPEED_LIMIT);
		)
	} else {
		manager->AbortTask(this);
	}
}

void CFGuardTask::Update()
{
//	if (updCount++ % 2 != 0) {
//		return;
//	}

	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitUnit* vip = circuit->GetTeamUnit(vipId);
	if (vip == nullptr) {
		manager->AbortTask(this);
		return;
	}

	CEnemyInfo* target = nullptr;
	const int frame = circuit->GetLastFrame();
	const AIFloat3& pos = vip->GetPos(frame);
	// A flying VIP's guards are fighters: what threatens it is air, and a
	// ground target would pull the escort off it for nothing.
	const bool airOnly = vip->GetCircuitDef()->IsAbleToFly();
	const std::vector<ICoreUnit::Id>& enemyIds = circuit->GetCallback()->GetEnemyUnitIdsIn(pos, vip->GetCircuitDef()->GetLosRadius() + 500.f);
	// apex_open_race: the guards' slowest speed, their reach and whether any can shoot up
	const bool catchOn = (circuit->GetTunable("apex_open_race", 0.f) > 0.f) && !IsStockTask();
	SChaseStat& chase = ChaseStat(circuit);
	float gSpeed = std::numeric_limits<float>::max();
	float gReach = 0.f;
	bool gAir = false;
	springai::AIFloat3 gPos = pos;
	for (CCircuitUnit* u : units) {
		const CCircuitDef* ud = u->GetCircuitDef();
		gSpeed = std::min(gSpeed, ud->GetSpeed());
		gReach = std::max(gReach, ud->GetMaxRange() * 0.9f);
		gAir = gAir || ud->HasSurfToAir() || ud->HasSubToAir();
		gPos = u->GetPos(frame);
	}
	// The guard answers what can reach the one it guards, nearest first: the
	// first enemy in sight pulled the escort up to a kilometre off its worker
	// for a minute (apexearth 2026-10-01: "they stopped guarding him").
	float bestD = std::numeric_limits<float>::max();
	for (ICoreUnit::Id enemyId : enemyIds) {
		CEnemyInfo* ei = circuit->GetEnemyInfo(enemyId);
		if (ei == nullptr) {
			continue;
		}
		CCircuitDef* ed = ei->GetCircuitDef();
		if (airOnly && ((ed == nullptr) || !ed->IsAbleToFly())) {
			continue;
		}
		const float d = pos.distance2D(ei->GetPos());
		const float reach = ((ed != nullptr) ? circuit->RangeVs(ed, airOnly) : 0.f) + 200.f;
		if ((d > reach) || (d >= bestD)) {
			continue;
		}
		if (!units.empty()) {
			if (!airOnly && (ed != nullptr) && ed->IsAbleToFly() && !gAir) {
				if (catchOn) {
					++chase.air;
					continue;
				}
			} else if (CatchP(gPos, gSpeed, gReach, ei) <= 0.f) {
				++chase.unreach;
				if (catchOn) {
					++chase.refused;
					continue;
				}
			}
		}
		bestD = d;
		target = ei;
	}

	if (target != nullptr) {
		if (frame < attackFrame + FRAMES_PER_SEC * 3) {
			return;
		}
		attackFrame = frame;
		{
			const CCircuitDef* td = target->GetCircuitDef();
			++chase.picks;
			if (!units.empty() && (td != nullptr) && (td->GetSpeed() > gSpeed)) {
				++chase.fast;
				if (chaseFrame >= 0) {
					chase.sec += float(frame - chaseFrame) / FRAMES_PER_SEC;
					chase.dist += gPos.distance2D(chasePos);
				}
				chaseFrame = frame;
				chasePos = gPos;
			} else {
				chaseFrame = -1;
			}
			ChaseStatLog(circuit, frame);
		}
		state = State::ENGAGE;
		if (frame >= engageLogAt) {
			engageLogAt = frame + FRAMES_PER_SEC * 10;
			CCircuitDef* td = target->GetCircuitDef();
			const char* vb = "-";
			IUnitTask* vt = vip->GetTask();
			if ((vt != nullptr) && (vt->GetType() == IUnitTask::Type::BUILDER)) {
				CCircuitDef* bd = static_cast<IBuilderTask*>(vt)->GetBuildDef();
				if (bd != nullptr) {
					vb = bd->GetDef()->GetName();
				}
			}
			circuit->LOG("apex: guard-engage vip=%s #%i job=%s guards=%u tgt=%s mobile=%i armed=%i dVip=%.0f",
					vip->GetCircuitDef()->GetDef()->GetName(), vip->GetId(), vb, (unsigned)units.size(),
					(td != nullptr) ? td->GetDef()->GetName() : "?",
					(td != nullptr) ? (int)td->IsMobile() : -1,
					(td != nullptr) ? (int)td->IsAttacker() : -1,
					pos.distance2D(target->GetPos()));
		}
		const bool isGroundAttack = target->GetUnit()->IsCloaked();
		for (CCircuitUnit* unit : units) {
			unit->Attack(target, isGroundAttack, frame + FRAMES_PER_SEC * 10);
		}
	} else if (State::ENGAGE == state) {
		state = State::ROAM;
		for (CCircuitUnit* unit : units) {
			TRY_UNIT(circuit, unit,
				unit->GetUnit()->Guard(vip->GetUnit());
			)
		}
	}
}

void CFGuardTask::OnUnitIdle(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitUnit* vip = circuit->GetTeamUnit(vipId);
	if (vip != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->GetUnit()->Guard(vip->GetUnit());
		)
	} else {
		manager->AbortTask(this);
	}
}

} // namespace circuit
