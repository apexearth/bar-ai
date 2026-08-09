/*
 * SuperTask.cpp
 *
 *  Created on: Aug 12, 2016
 *      Author: rlcevg
 */

#include "task/static/SuperTask.h"
#include "task/fighter/SquadTask.h"
#include "map/InfluenceMap.h"
#include "module/MilitaryManager.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitDef.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Log.h"
#include "Lua.h"

namespace circuit {

using namespace springai;

#define TARGET_DELAY	(FRAMES_PER_SEC * 10)
// apex: fraction of a group's cost that must be STATIC before the group counts as
// a base rather than an army passing through neutral ground.
#define STATIC_SHARE	0.5f
// apex: how much a group's static content is worth relative to its raw cost when
// choosing between targets. A base does not move, cannot retreat out of the blast
// and does not rebuild in the ten seconds it takes the missile to land, so it is
// worth strictly more than an equal pile of units.
#define STATIC_WEIGHT	1.0f

// apex: score a candidate. Raw cost picks the biggest blob on the map; this tips
// the choice toward the densest STATIC target of comparable value.
static inline float GroupScore(const CEnemyManager::SEnemyGroup& group)
{
	return group.cost + STATIC_WEIGHT * group.roleCosts[ROLE_TYPE(STATIC)];
}

CSuperTask::CSuperTask(ITaskModule* mgr)
		: IFighterTask(mgr, IFighterTask::FightType::SUPER, 1.f)
		, targetFrame(0)
		, targetPos(-RgtVector)
{
}

CSuperTask::~CSuperTask()
{
}

bool CSuperTask::CanAssignTo(CCircuitUnit* unit) const
{
	return false;
}

void CSuperTask::RemoveAssignee(CCircuitUnit* unit)
{
	IFighterTask::RemoveAssignee(unit);
	if (units.empty()) {
		manager->AbortTask(this);
	}
}

void CSuperTask::Start(CCircuitUnit* unit)
{
	const int frame = manager->GetCircuit()->GetLastFrame();
	targetFrame = frame - TARGET_DELAY;
	position = unit->GetPos(frame);
}

void CSuperTask::Update()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CCircuitUnit* unit = *units.begin();

	if (unit->Blocker() != nullptr) {
		return;  // Do not interrupt current action
	}

	CCircuitDef* cdef = unit->GetCircuitDef();
	if (cdef->IsHoldFire()) {
		if (targetFrame + (cdef->GetReloadTime() + TARGET_DELAY) > frame) {
			if ((State::ENGAGE == state) && (targetFrame + TARGET_DELAY <= frame)) {
				TRY_UNIT(circuit, unit,
					unit->CmdStop();
				)
				state = State::ROAM;
			}
			return;
		}
	} else if (targetFrame + TARGET_DELAY > frame) {
		return;
	}

	CInfluenceMap* inflMap = circuit->GetInflMap();
	CMilitaryManager* militaryMgr = circuit->GetMilitaryManager();
	const float maxSqRange = SQUARE(cdef->GetMaxRange());
	const float sqAoe = SQUARE(cdef->GetAoe() * 1.25f);
	float cost = 0.f;
	int groupIdx = -1;
	const std::array<const std::set<IFighterTask*>*, 3> avoidTasks = {  // NOTE: ISquadTask only
		&militaryMgr->GetTasks(IFighterTask::FightType::ATTACK),
		&militaryMgr->GetTasks(IFighterTask::FightType::AH),
		&militaryMgr->GetTasks(IFighterTask::FightType::AA),
	};
	// apex: an enemy ECONOMY is invisible to GetInfluenceAt. CInfluenceMap is built
	// only from hostile (armed) enemies -- InfluenceMap.cpp iterates
	// GetHostileDatas(), and MapManager.cpp puts anything failing IsAttacker() into
	// peaceUnits -- so mexes, fusions, labs, nanos and converters contribute zero.
	// The K-means groups DO include them (EnemyManager.cpp clusters peaceDatas too
	// and counts their cost), so an enemy base forms a high-cost group and was then
	// rejected here for not looking dangerous. Nuking a base is the whole point of
	// owning a silo.
	// Keep the real intent of the old test -- never fire onto ground WE hold -- and
	// otherwise accept a group that is worth hitting.
	const float staticShare = STATIC_SHARE;
	auto isTargetValid = [&avoidTasks, frame, sqAoe, staticShare, inflMap, circuit](const CEnemyManager::SEnemyGroup& group) {
		if (inflMap->GetAllyInflAt(group.pos) > INFL_EPS) {
			return false;
		}
		const float statCost = group.roleCosts[ROLE_TYPE(STATIC)];
		if ((inflMap->GetInfluenceAt(group.pos) > -INFL_EPS)
			&& (statCost < group.cost * staticShare))
		{
			return false;  // not enemy ground, and not a base either
		}
		for (const std::set<IFighterTask*>* tasks : avoidTasks) {
			for (const IFighterTask* task : *tasks) {
				const AIFloat3& leaderPos = static_cast<const ISquadTask*>(task)->GetLeaderPos(frame);
				if (leaderPos.SqDistance2D(group.pos) < sqAoe) {
					return false;
				}
			}
		}
		for (const ICoreUnit::Id eId : group.units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if (enemy == nullptr) {
				continue;
			}
			CCircuitDef* edef = enemy->GetCircuitDef();
			// NOTE: groups are created by leader, ignore flags could be different
			if ((edef == nullptr) || !circuit->GetCircuitDef(edef->GetId())->IsIgnore()) {
				return true;
			}
		}
		return false;
	};

	const std::vector<CEnemyManager::SEnemyGroup>& groups = circuit->GetEnemyManager()->GetEnemyGroups();
	if (cdef->IsHoldFire() || (State::ROAM == state)) {
		for (unsigned i = 0; i < groups.size(); ++i) {
			const CEnemyManager::SEnemyGroup& group = groups[i];
			const float score = GroupScore(group);
			if ((cost >= score) || (position.SqDistance2D(group.pos) >= maxSqRange)) {
				continue;
			}
			if (isTargetValid(group) && !militaryMgr->IsRecentSuperTarget(group.pos, sqAoe, frame)) {
				cost = score;
				groupIdx = i;
			}
		}
	} else {
		// TODO: Use WeaponDef::GetTurnRate() for turn-delay weight
		const AIFloat3& targetVec = (targetPos - position).Normalize2D();
		for (unsigned i = 0; i < groups.size(); ++i) {
			const CEnemyManager::SEnemyGroup& group = groups[i];
			if (position.SqDistance2D(group.pos) >= maxSqRange) {
				continue;
			}
			const AIFloat3& newVec = (group.pos - position).Normalize2D();
			const float angleMod = M_PI / (2.f * (std::acos(targetVec.dot2D(newVec)) + 1e-2f));
			const float score = GroupScore(group) * angleMod;
			if (cost >= score) {
				continue;
			}
			if (isTargetValid(group) && !militaryMgr->IsRecentSuperTarget(group.pos, sqAoe, frame)) {
				cost = score;
				groupIdx = i;
			}
		}
	}
	const float maxCost = cdef->IsAttrStock() ? cdef->GetWeaponDef()->GetCostM() : cdef->GetCostM() * 0.01f;

	if ((groupIdx < 0) || (cost < maxCost)) {
		// apex: the silent case. Nothing qualified -- either every group failed the
		// validity test or the best was worth less than one warhead.
		circuit->LOG("apex: super idle %s stock=%i groups=%i best=%.0f need=%.0f",
				cdef->GetDef()->GetName(), unit->GetUnit()->GetStockpile(),
				(int)groups.size(), cost, maxCost);
		TRY_UNIT(circuit, unit,
			unit->CmdStop();
		)
		SetTarget(nullptr);
		targetFrame = frame;
		return;
	}

	const AIFloat3& grPos = groups[groupIdx].pos;
	CEnemyInfo* bestTarget = nullptr;
	if (cdef->IsAttrStock()) {
		float minSqDist = std::numeric_limits<float>::max();
		for (const ICoreUnit::Id eId : groups[groupIdx].units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if (enemy == nullptr) {
				continue;
			}
			CCircuitDef* edef = enemy->GetCircuitDef();
			// NOTE: groups are created by leader, ignore flags could be different
			if ((edef != nullptr) && circuit->GetCircuitDef(edef->GetId())->IsIgnore()) {
				continue;
			}
			const float sqDist = grPos.SqDistance2D(enemy->GetPos());
			if ((minSqDist > sqDist) && (position.SqDistance2D(enemy->GetPos()) < maxSqRange)) {
				minSqDist = sqDist;
				bestTarget = enemy;
			}
		}
	} else {
		float maxCost = 0.f;
		for (const ICoreUnit::Id eId : groups[groupIdx].units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if (enemy == nullptr) {
				continue;
			}
			CCircuitDef* edef = enemy->GetCircuitDef();
			// NOTE: groups are created by leader, ignore flags could be different
			if ((edef != nullptr) && circuit->GetCircuitDef(edef->GetId())->IsIgnore()) {
				continue;
			}
			if ((maxCost < enemy->GetCost()) && (position.SqDistance2D(enemy->GetPos()) < maxSqRange)) {
				maxCost = enemy->GetCost();
				bestTarget = enemy;
			}
		}
	}
	SetTarget(bestTarget);
	if (GetTarget() != nullptr) {
		targetPos = GetTarget()->GetPos();
		targetPos.y = circuit->GetMap()->GetElevationAt(targetPos.x, targetPos.z);

		// apex: claim this ground before any other silo evaluates it.
		militaryMgr->NoteSuperTarget(targetPos, frame);
		// apex: CSuperTask logged nothing at all, so a silo that never fired was
		// indistinguishable from one with no target -- the reason this needed
		// reading the engine rather than grepping a log.
		const CEnemyManager::SEnemyGroup& chosen = groups[groupIdx];
		circuit->LOG("apex: super fire %s stock=%i score=%.0f cost=%.0f static=%.0f at (%.0f,%.0f)",
				cdef->GetDef()->GetName(), unit->GetUnit()->GetStockpile(), cost, chosen.cost,
				chosen.roleCosts[ROLE_TYPE(STATIC)], targetPos.x, targetPos.z);

		std::string cmd = (!cdef->IsAttrStock() || (unit->GetUnit()->GetStockpile() > 0)) ? "ai_super_fire:" : "ai_super_intention:";
		cmd += utils::int_to_string(unit->GetId()) + "/" + utils::int_to_string(targetPos.x) + "/" + utils::int_to_string(targetPos.z);
		circuit->GetLua()->CallRules(cmd.c_str(), cmd.size());

		TRY_UNIT(circuit, unit,
			if (GetTarget()->IsInRadarOrLOS() && !circuit->IsCheating()) {
				unit->GetUnit()->Attack(GetTarget()->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			} else {
				unit->CmdAttackGround(targetPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			}
		)
		targetFrame = frame;
		state = State::ENGAGE;
	}
}

} // namespace circuit
