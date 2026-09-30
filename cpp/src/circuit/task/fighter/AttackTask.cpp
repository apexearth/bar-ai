/*
 * AttackTask.cpp
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#include "task/fighter/AttackTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/action/FightAction.h"
#include "unit/action/MoveAction.h"
#include "unit/action/SupportAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "AISCommands.h"

namespace circuit {

using namespace springai;
using namespace terrain;

CAttackTask::CAttackTask(ITaskModule* mgr, float minPower, float powerMod)
		: ISquadTask(mgr, FightType::ATTACK, powerMod)
		, minPower(minPower)
{
	CCircuitAI* circuit = manager->GetCircuit();
	float x = rand() % circuit->GetTerrainManager()->GetTerrainWidth();
	float z = rand() % circuit->GetTerrainManager()->GetTerrainHeight();
	position = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
}

CAttackTask::~CAttackTask()
{
}

bool CAttackTask::CanAssignTo(CCircuitUnit* unit) const
{
	assert(leader != nullptr);

	float speedLeader = leader->GetCircuitDef()->GetSpeed();
	float speedUnit = unit->GetCircuitDef()->GetSpeed();
	if (speedLeader > speedUnit) {
		std::swap(speedLeader, speedUnit);
	}
	if (speedLeader * 1.5f < speedUnit) {
		return false;
	}

	const int frame = manager->GetCircuit()->GetLastFrame();
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(1000.f)) {
		return false;
	}
	if (!SameClimb(manager->GetCircuit(), leader->GetCircuitDef(), unit->GetCircuitDef())) {
		return false;
	}
	if ((leader->GetCircuitDef()->IsAbleToFly() && unit->GetCircuitDef()->IsAbleToFly())
		|| (leader->GetCircuitDef()->IsAmphibious() && unit->GetCircuitDef()->IsAmphibious())
		|| (leader->GetCircuitDef()->IsSurfer() && unit->GetCircuitDef()->IsSurfer())
		|| (leader->GetCircuitDef()->IsSubmarine() && unit->GetCircuitDef()->IsSubmarine())
		|| (leader->GetCircuitDef()->IsLander() && unit->GetCircuitDef()->IsLander())
		|| (leader->GetCircuitDef()->IsFloater() && unit->GetCircuitDef()->IsFloater()))
	{
		return true;
	}
	return false;
}

void CAttackTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);
	CCircuitDef* cdef = unit->GetCircuitDef();
	highestRange = std::max(highestRange, cdef->GetLosRadius());

	if (cdef->IsRoleSupport()) {
		unit->PushBack(new CSupportAction(unit));
	}

	int squareSize = manager->GetCircuit()->GetPathfinder()->GetSquareSize();
	ITravelAction* travelAction;
	if (cdef->IsAttrSiege()) {
		travelAction = new CFightAction(unit, squareSize);
	} else {
		travelAction = new CMoveAction(unit, squareSize);
	}
	unit->PushTravelAct(travelAction);
	travelAction->StateWait();
	unit->SetAllowedToJump(cdef->IsAbleToJump() && cdef->IsAttrJump());
}

void CAttackTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	if ((attackPower < minPower) || (leader == nullptr)) {
		manager->AbortTask(this);
	} else {
		highestRange = std::max(highestRange, leader->GetCircuitDef()->GetLosRadius());
	}
}

void CAttackTask::Start(CCircuitUnit* unit)
{
	if ((State::REGROUP == state) || (State::ENGAGE == state)) {
		return;
	}
	if (!pPath->posPath.empty()) {
		unit->GetTravelAct()->SetPath(pPath, lowestSpeed);
	}
}

void CAttackTask::Update()
{
	++updCount;

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if (task != nullptr) {
		task->Merge(this);
		units.clear();
		// TODO: Deal with cowards?
		manager->AbortTask(this);
		return;
	}

	/*
	 * Regroup if required
	 */
	bool wasRegroup = (State::REGROUP == state);
	bool mustRegroup = IsMustRegroup();
	if (State::REGROUP == state) {
		if (mustRegroup) {
			CCircuitAI* circuit = manager->GetCircuit();
			int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
			for (CCircuitUnit* unit : units) {
				unit->GetTravelAct()->StateWait();
				unit->Gather(groupPos, frame);
			}
		}
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	bool isExecute = (updCount % 4 == 2);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame);
		}
		if (!isExecute) {
			if (wasRegroup && !pPath->posPath.empty()) {
				ActivePath(lowestSpeed);
			}
			return;
		}
	} else {
		ISquadTask::Update();
		if (leader == nullptr) {  // task aborted
			return;
		}
	}

	const AIFloat3& startPos = leader->GetPos(frame);
//	if (circuit->GetInflMap()->GetInfluenceAt(startPos) < -INFL_EPS) {
//		SetTarget(nullptr);  // FIXME: back-forths group
//	} else {
		FindTarget();
//	}

	state = State::ROAM;
	if (GetTarget() != nullptr) {
		const float slack = (circuit->GetInflMap()->GetAllyDefendInflAt(position) > INFL_EPS) ? 300.f : 100.f;
		if (position.SqDistance2D(startPos) < SQUARE(highestRange + slack)) {
			int xs, ys, xe, ye;
			circuit->GetPathfinder()->Pos2PathXY(startPos, &xs, &ys);
			circuit->GetPathfinder()->Pos2PathXY(position, &xe, &ye);
			if (GetHitTest()(int2(xs, ys), int2(xe, ye))) {
				state = State::ENGAGE;
				Attack(frame);
				return;
			}
		}
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (GetTarget() == nullptr) {
		if (!MarchEnemyBox()) {
			FallbackFrontPos();
		}
		return;
	}

	const AIFloat3& endPos = position;
	CPathFinder* pathfinder = circuit->GetPathfinder();
	const float eps = pathfinder->GetSquareSize();
	const float pathRange = std::max(highestRange - eps, eps);

	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, endPos, pathRange, GetHitTest(),
			attackPower / circuit->GetMilitaryManager()->GetRangeUnitCountCompensatorScale());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
}

// NO TARGET IS NOT NO ENEMY (apexearth 2026-09-29: humans jam, and an army that
// saw nothing stayed home). Their base is in their start box -- the mirror of
// ours on a map without boxes: march there and the squad's own eyes find what
// to fight. Only at the box with nothing in sight does it fall back.
bool CAttackTask::MarchEnemyBox()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 box = circuit->GetSetupManager()->GetEnemyBoxCentre();
	if (box.x < 0.f) {
		const AIFloat3& home = circuit->GetSetupManager()->GetBasePos();
		box = AIFloat3(terrainMgr->GetTerrainWidth() - home.x, 0.f, terrainMgr->GetTerrainHeight() - home.z);
	}
	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	if ((startPos.SqDistance2D(box) < SQUARE(highestRange + DEFAULT_SLACK * 4))
		|| !terrainMgr->CanMobileReachAt(leader->GetArea(), box, highestRange))
	{
		return false;
	}
	box.y = circuit->GetMap()->GetElevationAt(box.x, box.z);
	const AIFloat3 dest = terrainMgr->GetMovePosition(leader->GetArea(), box);
	if (position.SqDistance2D(dest) > SQUARE(DEFAULT_SLACK)) {
		circuit->LOG("apex: atkbox t=%i lead=%s n=%i at=%.0f,%.0f from=%.0f",
			circuit->GetTeamId(), leader->GetCircuitDef()->GetDef()->GetName(),
			(int)units.size(), dest.x, dest.z, startPos.distance2D(dest));
	}
	position = dest;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	const float eps = pathfinder->GetSquareSize();
	const float pathRange = std::max(highestRange - eps, eps);
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, position, pathRange, GetHitTest(),
			attackPower / circuit->GetMilitaryManager()->GetRangeUnitCountCompensatorScale());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
	return true;
}

void CAttackTask::OnUnitIdle(CCircuitUnit* unit)
{
	ISquadTask::OnUnitIdle(unit);
	if (units.empty()) {
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
	if (position.SqDistance2D(leader->GetPos(circuit->GetLastFrame())) < SQUARE(maxDist)) {
		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		float x = rand() % terrainMgr->GetTerrainWidth();
		float z = rand() % terrainMgr->GetTerrainHeight();
		position = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
		position = terrainMgr->GetMovePosition(leader->GetArea(), position);
	}

	if (units.find(unit) != units.end()) {
		Start(unit);  // NOTE: Not sure if it has effect
	}
}

void CAttackTask::FindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const bool isAntiStatic = cdef->IsAttrAntiStat();
	const float maxSpeed = SQUARE(highestSpeed * 1.01f / FRAMES_PER_SEC);
	const float maxPower = attackPower * powerMod;
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();

	CEnemyInfo* const prevTarget = GetTarget();
	CEnemyInfo* bestTarget = nullptr;
	float bestPull = 0.f;
	float bestSup = 0.f;
	const auto& supSpots = circuit->GetMilitaryManager()->GetSupportSpots();
	const float sqOBDist = pos.SqDistance2D(basePos);  // Own to Base distance
	float minSqDist = std::numeric_limits<float>::max();
	bool hasGoodTarget = false;
	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	const std::vector<CEnemyManager::SEnemyGroup>& groups = circuit->GetEnemyManager()->GetEnemyGroups();

	// HOME MUST STAY REACHABLE (apexearth 2026-09-28: every ally piling onto one
	// weak spot makes our own). A ground army stronger than every friendly force
	// on its walk to our base sets a deadline -- that walk at its slowest
	// member's speed -- and a target we could not walk home from before then is
	// refused, unless it belongs to such an army: the enemy across from us.
	// Allies and statics block it; this squad does not, since it is what leaves
	// (counting it let the squad out, then refused it once away: a flap).
	const float ourSpeed = std::max(lowestSpeed, 1.f);
	// Only a squad that can come home can defend it: boats off an inland base
	// were held to our shore by a walk they could never make.
	const bool canGoHome = terrainMgr->CanMobileReachAt(area, basePos, highestRange);
	const float inflCell = float(terrainMgr->GetConvertStoP() * 4);
	const int frame = circuit->GetLastFrame();
	auto selfInflAt = [&](const AIFloat3& p) {
		float s = 0.f;
		for (CCircuitUnit* u : units) {
			const CCircuitDef* ud = u->GetCircuitDef();
			int cells = ud->GetThreatRange(CCircuitDef::ThreatType::SURF);
			if (ud->GetMaxRange() > 1000.f) {
				cells /= 2;
			}
			const float r = float(cells) * inflCell;
			const float d = u->GetPos(frame).distance2D(p);
			if ((r > 0.f) && (d < r)) {
				s += ud->GetPower() * (1.f - d / r);
			}
		}
		return s;
	};
	auto blockingFrom = [&](const AIFloat3& from) {
		float best = 0.f;
		for (int k = 0; k < 4; ++k) {
			const AIFloat3 p = basePos + (from - basePos) * (float(k) / 4.f);
			best = std::max(best, inflMap->GetAllyInflAt(p) - selfInflAt(p));
		}
		return best;
	};
	float threatS = std::numeric_limits<float>::max();
	float threatD = 0.f;
	std::vector<bool> isThreat(groups.size(), false);
	for (unsigned i = 0; i < groups.size(); ++i) {
		const CEnemyManager::SEnemyGroup& group = groups[i];
		float slowest = std::numeric_limits<float>::max();
		for (const ICoreUnit::Id eId : group.units) {
			CEnemyInfo* e = circuit->GetEnemyInfo(eId);
			CCircuitDef* d = (e != nullptr) ? e->GetCircuitDef() : nullptr;
			if ((d == nullptr) || !d->IsMobile() || d->IsAbleToFly() || !d->IsAttacker()
				|| (d->GetSpeed() <= 0.f))
			{
				continue;
			}
			slowest = std::min(slowest, d->GetSpeed());
		}
		if ((slowest == std::numeric_limits<float>::max())
			|| (group.influence <= blockingFrom(group.pos)))
		{
			continue;
		}
		isThreat[i] = true;
		const float d = group.pos.distance2D(basePos);
		if (d / slowest < threatS) {
			threatS = d / slowest;
			threatD = d;
		}
	}
	int refusedHome = 0;

	for (unsigned i = 0; i < groups.size(); ++i) {
		const CEnemyManager::SEnemyGroup& group = groups[i];
		const bool isOverpowered = maxPower * 0.125f > group.influence;
		if (hasGoodTarget && isOverpowered) {
			continue;
		}
		const float distBE = group.pos.distance2D(basePos);  // Base to Enemy distance
		const float scale = std::min(distBE / sqOBDist, 1.f);
		if (((maxPower <= group.influence * scale) && (inflMap->GetInfluenceAt(group.pos) < INFL_SAFE))
			|| !terrainMgr->CanMobileReachAt(area, group.pos, highestRange))
		{
			continue;
		}

		for (const ICoreUnit::Id eId : group.units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if ((enemy == nullptr) || enemy->IsHidden()/* || (enemy->GetTasks().size() > 2)*/) {
				continue;
			}
			const AIFloat3& ePos = enemy->GetPos();
			const AIFloat3& eVel = enemy->GetVel();
			if ((eVel.SqLength2D() >= maxSpeed)/* && (eVel.dot2D(pos - ePos) < 0)*/) {  // speed and direction
				continue;
			}

			const float elevation = map->GetElevationAt(ePos.x, ePos.z);
			const bool IsInWater = cdef->IsPredictInWater(elevation);
			CCircuitDef* edef = enemy->GetCircuitDef();
			if (edef != nullptr) {
				if (((edef->GetCategory() & canTargetCat) == 0)
					|| ((edef->GetCategory() & noChaseCat) != 0)
					|| (isAntiStatic && edef->IsMobile())
					|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()  // NOTE: groups are created by leader, ignore flags could be different
					|| (edef->IsAbleToFly() && !cdef->IsAirHunter(IsInWater)))  // notAA
				{
					continue;
				}
				if (edef->IsInWater(elevation, ePos.y)) {
					if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater())) {  // notAW
						continue;
					}
				} else {
					if (!(IsInWater ? cdef->HasSubToLand() : cdef->HasSurfToLand())) {  // notAL
						continue;
					}
				}
				if ((ePos.y - elevation > weaponRange)
					/*|| enemy->IsBeingBuilt()*/)
				{
					continue;
				}
			} else {
				if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater()) && (ePos.y < -SQUARE_SIZE * 5)) {  // notAW
					continue;
				}
			}

			// METAL KILLED PER THREAT FACED, not the nearest thing. Nearest-first
			// walks the squad into the enemy's outer towers and it dies there
			// with the economy behind them untouched; the doctrine is to kill
			// the economy and leave the wall alone when a path exists. A
			// target's pull is its cost over its power (plus our leader's own,
			// so a toothless mex is not infinitely attractive); a mex 3x the
			// distance of a tower still wins. The overpower gates above are
			// unchanged: a group we cannot beat is still refused.
			float pull = 1.f;
			float sup = 0.f;
			if (edef != nullptr) {
				const float ownPow = std::max(cdef->GetPower(), 1.f);
				// An enemy whose threat covers a mex spot we asked support for
				// also carries that spot's worth.
				if (!supSpots.empty()) {
					const float reach = float(edef->GetThreatRange(CCircuitDef::ThreatType::SURF)) * inflCell;
					for (const auto& s : supSpots) {
						if (ePos.SqDistance2D(s.first) < SQUARE(reach)) {
							sup = std::max(sup, s.second);
						}
					}
				}
				pull = std::max(enemy->GetCost() + sup, 1.f) / (edef->GetPower() + ownPow);
			}
			// NEAR OUR OWN BASE, squared like the leader term (apexearth
			// 2026-09-28): stock's linear distBE let every ally's army walk to
			// the same far structure. Floored at our range so enemies inside
			// the base still rank by leader distance and pull.
			const float rawSqBE = ePos.SqDistance2D(basePos);
			const float sqBE = std::max(rawSqBE, SQUARE(weaponRange));
			const float sqOEDist = group.vagueMetric * pos.SqDistance2D(ePos) * sqBE / pull;  // Own to Enemy distance
			if (canGoHome && !isThreat[i]) {
				const float dHome = std::sqrt(rawSqBE);
				if ((dHome > threatD) && (dHome / ourSpeed > threatS)) {
					++refusedHome;
					continue;
				}
			}
			if (minSqDist > sqOEDist) {
				minSqDist = sqOEDist;
				bestTarget = enemy;
				bestPull = pull;
				bestSup = sup;
				hasGoodTarget |= !isOverpowered;
			}
		}
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		position = GetTarget()->GetPos();
		if (bestTarget != prevTarget) {
			CCircuitDef* bdef = bestTarget->GetCircuitDef();
			circuit->LOG("apex: atktgt t=%i lead=%s def=%s at=%.0f,%.0f dBase=%.0f dLead=%.0f pull=%.2f n=%i"
				" backS=%.0f deadlineS=%.0f threatD=%.0f refused=%i home=%i sup=%.0f",
				circuit->GetTeamId(), cdef->GetDef()->GetName(),
				(bdef != nullptr) ? bdef->GetDef()->GetName() : "-",
				position.x, position.z, position.distance2D(basePos), position.distance2D(pos),
				bestPull, (int)units.size(), position.distance2D(basePos) / ourSpeed,
				(threatS < std::numeric_limits<float>::max()) ? threatS : -1.f, threatD, refusedHome,
				canGoHome ? 1 : 0, bestSup);
		}
	}
	// Return: target, startPos=leader->pos, endPos=position
}

void CAttackTask::ApplyTargetPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
	} else {
		FallbackFrontPos();
	}
}

void CAttackTask::FallbackFrontPos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->GetMilitaryManager()->FillFrontPos(leader, urgentPositions);
	if (urgentPositions.empty()) {
		FallbackBasePos();
		return;
	}

	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	const float pathRange = DEFAULT_SLACK * 4;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, circuit->GetThreatMap(),
			startPos, pathRange, urgentPositions);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyFrontPos(static_cast<const CQueryPathMulti*>(query));
	});
}

void CAttackTask::ApplyFrontPos(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->path.empty()) {
		if (pPath->path.size() > 2) {
			ActivePath();
		}
	} else {
		FallbackBasePos();
	}
}

void CAttackTask::FallbackBasePos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CSetupManager* setupMgr = circuit->GetSetupManager();

	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	const AIFloat3& endPos = setupMgr->GetBasePos();
	const float pathRange = DEFAULT_SLACK * 4;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, endPos, pathRange);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyBasePos(static_cast<const CQueryPathSingle*>(query));
	});
}

void CAttackTask::ApplyBasePos(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->path.empty()) {
		if (pPath->path.size() > 2) {
			ActivePath();
		}
	} else {
		Fallback();
	}
}

void CAttackTask::Fallback()
{
	// should never happen
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		unit->GetTravelAct()->StateWait();
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
