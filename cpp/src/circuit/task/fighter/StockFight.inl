/*
 * StockFight.inl (included by SquadTask.cpp: a new .cpp needs a cmake re-glob)
 *
 * apex_stock_army: the stock BARb fight code these classes ran at the 2026-09-07 revert to the fork base
 * (7a1a9895, BARb 0ef36267), run in place of ours while the switch is on. Kept verbatim but for the
 * travel-action null guards and the join-gated Merge. CBombTask and CAntiAirTask were never reverted: its stock is the fork
 * base itself (engine-patches/0001-barb-apex-cpp.patch reversed).
 */

#include "task/fighter/AntiAirTask.h"
#include "task/fighter/AttackTask.h"
#include "task/fighter/BombTask.h"
#include "task/fighter/DefendTask.h"
#include "task/fighter/RaidTask.h"
#include "task/fighter/SquadTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/action/TravelAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "unit/CircuitWDef.h"
#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"

#include <cmath>

namespace circuit {

using namespace springai;
using namespace terrain;

void ISquadTask::StockAttack(const int frame, const bool isGround)
{
	const AIFloat3& tPos = GetTarget()->GetPos();
	const bool isRepeatAttack = (frame >= attackFrame + FRAMES_PER_SEC * 3);
	attackFrame = isRepeatAttack ? frame : attackFrame;

	auto it = rangeUnits.begin()->second.begin();
	std::advance(it, rangeUnits.begin()->second.size() / 2);  // TODO: Optimize
	AIFloat3 dir = (*it)->GetPos(frame) - tPos;

	if (leader->GetCircuitDef()->IsPlane() || (std::fabs(dir.y) > leader->GetCircuitDef()->GetMaxRange() * 0.5f)) {
		if (isRepeatAttack) {
			for (CCircuitUnit* unit : units) {
				if (unit->Blocker() != nullptr) {
					continue;  // Do not interrupt current action
				}
				if (unit->GetTravelAct() != nullptr) {
					unit->GetTravelAct()->StateWait();
				}

				unit->Attack(GetTarget(), isGround, frame + FRAMES_PER_SEC * 60);
			}
		}
		return;
	}

	const int targetTile = manager->GetCircuit()->GetInflMap()->Pos2Index(tPos);
	const float alpha = std::atan2(dir.z, dir.x);
	CCircuitDef* edef = GetTarget()->GetCircuitDef();
	const bool isStatic = (edef != nullptr) && !edef->IsMobile();
	// incorrect, it should check aoe in vicinity
	const float aoe = (edef != nullptr) ? edef->GetAoe() : SQUARE_SIZE;

	int row = 0;
	for (const auto& kv : rangeUnits) {
		CCircuitDef* rowDef = (*kv.second.begin())->GetCircuitDef();
		const float range = kv.first * RANGE_MOD;
		// NOTE: 1st unit in 1st row will scout, ignoring GetTarget()->IsInRadarOrLOS()
		//       as unit may wobble back and forth without firing if turret turn is slow.
		float range0 = range;
		if ((row++ == 0) && (isStatic || !GetTarget()->IsInRadarOrLOS())) {
			range0 = std::min(kv.first, rowDef->GetLosRadius()) * RANGE_MOD;
		}
		const float maxDelta = (M_PI * 0.9f) / kv.second.size();
		// NOTE: float delta = asinf(cdef->GetRadius() / range);
		//       but sin of a small angle is similar to that angle, omit asinf() call
		float delta = (3.0f * (rowDef->GetRadius() + aoe)) / (range + DIV0_SLACK);
		if (delta > maxDelta) {
			delta = maxDelta;
		}

		float beta = -delta * (kv.second.size() / 2);
		const float end1 = alpha + beta;
		const float end2 = alpha - beta;
		AIFloat3 newPos1(tPos.x + range * cosf(end1), tPos.y, tPos.z + range * sinf(end1));
		AIFloat3 newPos2(tPos.x + range * cosf(end2), tPos.y, tPos.z + range * sinf(end2));
		const AIFloat3 testPos = (*kv.second.begin())->GetPos(frame);
		if (testPos.SqDistance2D(newPos1) > testPos.SqDistance2D(newPos2)) {
			delta = -delta;
			beta = -beta;
		}

		int iterNum = 0;
		for (CCircuitUnit* unit : kv.second) {
			if (unit->Blocker() != nullptr) {
				continue;  // Do not interrupt current action
			}
			if (unit->GetTravelAct() != nullptr) {
				unit->GetTravelAct()->StateWait();
			}

			if (isRepeatAttack
				|| (unit->GetTarget() != GetTarget())
				|| (unit->GetTargetTile() != targetTile))
			{
				const float angle = alpha + beta;
				const float r = (iterNum == 0) ? range0 : range;
				AIFloat3 newPos(tPos.x + r * cosf(angle), tPos.y, tPos.z + r * sinf(angle));
				CTerrainManager::CorrectPosition(newPos);
				unit->Attack(newPos, GetTarget(), targetTile, isGround, isStatic, frame + FRAMES_PER_SEC * 60);
			}

			beta += delta;
			++iterNum;
		}
	}
}

void CAttackTask::StockUpdate()
{
	++updCount;

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if ((task != nullptr) && task->Merge(this)) {
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
				if (unit->GetTravelAct() != nullptr) {
					unit->GetTravelAct()->StateWait();
				}
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
		StockFindTarget();
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
		StockFallbackFrontPos();
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
		this->StockApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CAttackTask::StockFindTarget()
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

	CEnemyInfo* bestTarget = nullptr;
	const float sqOBDist = pos.SqDistance2D(basePos);  // Own to Base distance
	float minSqDist = std::numeric_limits<float>::max();
	bool hasGoodTarget = false;

	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	const std::vector<CEnemyManager::SEnemyGroup>& groups = circuit->GetEnemyManager()->GetEnemyGroups();
	for (unsigned i = 0; i < groups.size(); ++i) {
		const CEnemyManager::SEnemyGroup& group = groups[i];
		const bool isOverpowered = maxPower * 0.125f > group.influence;
		if (hasGoodTarget && isOverpowered) {
			continue;
		}
		const float distBE = group.pos.distance2D(basePos);  // Base to Enemy distance
		const float scale = std::min(distBE / sqOBDist, 1.f);
		// seat-local: stock BARb verbatim, the switch's whole point
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
					|| (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())))  // notAA
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

			const float sqOEDist = group.vagueMetric * pos.SqDistance2D(ePos) * scale;  // Own to Enemy distance
			if (minSqDist > sqOEDist) {
				minSqDist = sqOEDist;
				bestTarget = enemy;
				hasGoodTarget |= !isOverpowered;
			}
		}
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		position = GetTarget()->GetPos();
	}
	// Return: target, startPos=leader->pos, endPos=position
}

void CAttackTask::StockApplyTargetPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
	} else {
		StockFallbackFrontPos();
	}
}

void CAttackTask::StockFallbackFrontPos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->GetMilitaryManager()->FillFrontPos(leader, urgentPositions);
	if (urgentPositions.empty()) {
		StockFallbackBasePos();
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
		this->StockApplyFrontPos(static_cast<const CQueryPathMulti*>(query));
	});
}

void CAttackTask::StockApplyFrontPos(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->path.empty()) {
		if (pPath->path.size() > 2) {
			ActivePath();
		}
	} else {
		StockFallbackBasePos();
	}
}

void CAttackTask::StockFallbackBasePos()
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
		this->StockApplyBasePos(static_cast<const CQueryPathSingle*>(query));
	});
}

void CAttackTask::StockApplyBasePos(const CQueryPathSingle* query)
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

void CDefendTask::StockUpdate()
{
	++updCount;

	/*
	 * Promote task if possible
	 */
	if (updCount % 32 == 1) {
		CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
		if ((attackPower >= maxPower) || !militaryMgr->GetTasks(check).empty()) {
			IFighterTask* task = militaryMgr->Enqueue(TaskF::Common(promote));
			decltype(units) tmpUnits = units;
			for (CCircuitUnit* unit : tmpUnits) {
				manager->AssignTask(unit, task);
			}
//			manager->DoneTask(this);  // NOTE: RemoveAssignee() will abort task
			return;
		}
	}

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if ((task != nullptr) && task->Merge(this)) {
		units.clear();
		manager->AbortTask(this);
		return;
	}

	/*
	 * No regroup
	 */
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	bool isExecute = (updCount % 16 == 2);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame);
		}
		if (!isExecute) {
			return;
		}
	} else {
		ISquadTask::Update();
		if (leader == nullptr) {  // task aborted
			return;
		}
	}

	/*
	 * Update target
	 */
	const bool isTargetsFound = StockFindTarget();

	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if ((GetTarget() != nullptr) || isTargetsFound) {
		const float slack = (circuit->GetInflMap()->GetAllyDefendInflAt(position) > INFL_EPS) ? 500.f : 300.f;
		if (position.SqDistance2D(startPos) < SQUARE(highestRange + slack)) {
			state = State::ENGAGE;
			Attack(frame);
			return;
		}
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (!isTargetsFound) {  // enemyPositions.empty()
		FallbackFrontPos();
		return;
	}

	CThreatMap* threatMap = circuit->GetThreatMap();
	const float eps = threatMap->GetSquareSize() * 2.f;
	const float pathRange = std::max(highestRange - eps, eps);

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, threatMap,
			startPos, pathRange, enemyPositions);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathMulti*>(query));
	});
}

bool CDefendTask::StockFindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const float maxPower = attackPower * powerMod;
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();

	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const float baseRange = circuit->GetMilitaryManager()->GetBaseDefRange();
	const float sqBaseRange = SQUARE(baseRange);

	CEnemyInfo* bestTarget = nullptr;
	float minSqDist = std::numeric_limits<float>::max();

	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	enemyPositions.clear();
	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden() || (enemy->GetTasks().size() > 2)) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		if ((inflMap->GetAllyDefendInflAt(ePos) < INFL_EPS)
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		const float sqEBDist = basePos.SqDistance2D(ePos);
		float checkPower = maxPower;
		if (sqEBDist < sqBaseRange) {
			checkPower *= 4.0f - 3.0f / baseRange * sqrtf(sqEBDist);  // 400% near base
		}
		if (checkPower <= threatMap->GetThreatAt(ePos)) {
			continue;
		}

		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			if (((edef->GetCategory() & canTargetCat) == 0)
				|| ((edef->GetCategory() & noChaseCat) != 0)
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()
				|| (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())))  // notAA
			{
				continue;
			}
			float elevation = map->GetElevationAt(ePos.x, ePos.z);
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

		float sqDist = pos.SqDistance2D(ePos);
		if (minSqDist > sqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
		enemyPositions.push_back(ePos);
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		position = GetTarget()->GetPos();
	}
	if (enemyPositions.empty()) {
		return false;
	}

	return true;
	// Return: target, startPos=leader->pos, enemyPositions
}

void CRaidTask::StockUpdate()
{
	++updCount;

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if ((task != nullptr) && task->Merge(this)) {
		units.clear();
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
				if (unit->GetTravelAct() != nullptr) {
					unit->GetTravelAct()->StateWait();
				}
				unit->Gather(groupPos, frame);
			}
		}
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	bool isExecute = (updCount % 2 == 0) && (frame >= lastTouched + FRAMES_PER_SEC);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame);
		}
		if (!isExecute) {
			if (wasRegroup && !pPath->posPath.empty()) {
				ActivePath();
			}
			return;
		}
	}
	lastTouched = frame;

	/*
	 * Update target
	 */
	const bool isTargetsFound = StockFindTarget();

	state = State::ROAM;
	if (GetTarget() != nullptr) {
		state = State::ENGAGE;
		position = GetTarget()->GetPos();
		circuit->GetMilitaryManager()->ClearScoutPosition(this);
		if (leader->GetCircuitDef()->IsAbleToFly()) {
			if (GetTarget()->GetUnit()->IsCloaked()) {
				for (CCircuitUnit* unit : units) {
					if (unit->Blocker() != nullptr) {
						continue;  // Do not interrupt current action
					}
					if (unit->GetTravelAct() != nullptr) {
						unit->GetTravelAct()->StateWait();
					}

					const AIFloat3& pos = GetTarget()->GetPos();
					TRY_UNIT(circuit, unit,
						unit->CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
					)
				}
			} else {
				for (CCircuitUnit* unit : units) {
					if (unit->Blocker() != nullptr) {
						continue;  // Do not interrupt current action
					}
					if (unit->GetTravelAct() != nullptr) {
						unit->GetTravelAct()->StateWait();
					}

					TRY_UNIT(circuit, unit,
						unit->GetUnit()->Attack(GetTarget()->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
						unit->CmdSetTarget(GetTarget());
					)
				}
			}
		} else {
			// FIXME: check hitTest
			Attack(frame);
		}
		return;
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (!isTargetsFound) {  // urgentPositions.empty() && enemyPositions.empty()
		StockFallbackRaid();
		return;
	}

	CCircuitDef* cdef = leader->GetCircuitDef();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& startPos = leader->GetPos(frame);
	const float pathRange = std::max(std::min(cdef->GetMaxRange(), cdef->GetLosRadius()), (float)threatMap->GetSquareSize());

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, threatMap,
			startPos, pathRange, !urgentPositions.empty() ? urgentPositions : enemyPositions, GetHitTest(), true,
			attackPower / circuit->GetMilitaryManager()->GetRangeUnitCountCompensatorScale());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->StockApplyTargetPath(static_cast<const CQueryPathMulti*>(query));
	});
}

bool CRaidTask::StockFindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const bool isAntiStatic = cdef->IsAttrAntiStat();
	const bool hadTarget = GetTarget() != nullptr;
	const float maxSpeed = SQUARE(highestSpeed * 0.8f / FRAMES_PER_SEC);
	const float maxPower = attackPower * powerMod * (hadTarget ? 1.f / 0.75f : 1.f);
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
	const float range = std::max(leader->GetUnit()->GetMaxRange(), cdef->GetLosRadius()) + 200.f;
	float minSqDist = SQUARE(range);
	float maxThreat = 0.f;
	float minPower = maxPower;

	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const float baseRange = circuit->GetMilitaryManager()->GetBaseDefRange();
	const float sqBaseRange = SQUARE(baseRange);
	const bool isDefender = basePos.SqDistance2D(pos) < sqBaseRange;

	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	CEnemyInfo* bestTarget = nullptr;
	CEnemyInfo* worstTarget = nullptr;
	urgentPositions.clear();
	enemyPositions.clear();
	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden() || (enemy->GetTasks().size() > 1)) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		const bool isEnemyUrgent = isDefender && (inflMap->GetAllyDefendInflAt(ePos) > INFL_EPS);
		if ((!isEnemyUrgent && !urgentPositions.empty())
			|| !terrainMgr->CanMobileReachAt(area, ePos, highestRange))
		{
			continue;
		}

		const float sqEBDist = basePos.SqDistance2D(ePos);
		float checkPower = maxPower;
		float checkSpeed = maxSpeed;
		if (sqEBDist < sqBaseRange) {
			checkPower *= 2.0f - 1.0f / baseRange * sqrtf(sqEBDist);  // 200% near base
			checkSpeed *= 2.f;
		}
		const float power = threatMap->GetThreatAt(ePos);
		if (checkPower <= power) {
			continue;
		}
		const AIFloat3& eVel = enemy->GetVel();
		if ((eVel.SqLength2D() >= checkSpeed) && (eVel.dot2D(pos - ePos) < 0)) {
			continue;
		}

		int targetCat;
		float defThreat;
		bool isBuilder;
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			targetCat = edef->GetCategory();
			if (((targetCat & canTargetCat) == 0)
				|| (isAntiStatic && edef->IsMobile())
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()
				|| (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())))  // notAA
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
			if (ePos.y - elevation > weaponRange) {
				continue;
			}
			defThreat = enemy->GetInfluence();
			isBuilder = edef->IsEnemyRoleAny(CCircuitDef::RoleMask::BUILDER | CCircuitDef::RoleMask::COMM);
		} else {
			if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater()) && (ePos.y < -SQUARE_SIZE * 5)) {  // notAW
				continue;
			}
			targetCat = UNKNOWN_CATEGORY;
			defThreat = enemy->GetInfluence();
			isBuilder = false;
		}

		float sqDist = pos.SqDistance2D(ePos);
		if ((minPower > power) && (minSqDist > sqDist)) {
			if (enemy->IsInRadarOrLOS()) {
				if (((targetCat & noChaseCat) == 0) && !enemy->IsBeingBuilt()) {
					if (isBuilder) {
						bestTarget = enemy;
						minSqDist = sqDist;
						maxThreat = std::numeric_limits<float>::max();
					} else if (maxThreat <= defThreat) {
						bestTarget = enemy;
//						minSqDist = sqDist;
						maxThreat = defThreat;
					}
//					minPower = power;
				} else if (bestTarget == nullptr) {
					worstTarget = enemy;
				}
			}
			continue;
		}

		if (isEnemyUrgent) {
			urgentPositions.push_back(ePos);
		} else {
			enemyPositions.push_back(ePos);
		}
	}
	if (bestTarget == nullptr) {
		bestTarget = worstTarget;
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		return true;
	}

	return !urgentPositions.empty() || !enemyPositions.empty();
	// Return: target, startPos=leader->pos, urgentPositions and enemyPositions
}

void CRaidTask::StockApplyTargetPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		position = pPath->posPath.back();
		ActivePath();
	} else {
		StockFallbackRaid();
	}
}

void CRaidTask::StockFallbackRaid()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const AIFloat3& threatPos = ((leader->GetTravelAct() != nullptr) && leader->GetTravelAct()->IsActive()) ? position : pos;
	if (attackPower * powerMod <= threatMap->GetThreatAt(leader, threatPos)) {
		AIFloat3 nextPos = circuit->GetMilitaryManager()->GetScoutPosition(leader);
		if (utils::is_equal_pos(nextPos, pos)) {
			return;
		} else {
			position = nextPos;
		}
	}

	if (!utils::is_valid(position)) {
		float x = rand() % terrainMgr->GetTerrainWidth();
		float z = rand() % terrainMgr->GetTerrainHeight();
		position = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
		position = terrainMgr->GetMovePosition(leader->GetArea(), position);
	}

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, threatMap,
			pos, position, pathfinder->GetSquareSize());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->StockApplyRaidPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CRaidTask::StockApplyRaidPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (pPath->path.size() > 2) {
//		position = path.back();
		ActivePath();
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		)
	}
}

bool CBombTask::StockCanAssignTo(CCircuitUnit* unit) const
{
	if (!unit->GetCircuitDef()->IsRoleBomber() ||
		(unit->GetCircuitDef() != leader->GetCircuitDef()))
	{
		return false;
	}
	const int frame = manager->GetCircuit()->GetLastFrame();
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(1000.f)) {
		return false;
	}
	return true;
}

void CBombTask::StockUpdate()
{
	++updCount;

	/*
	 * Check safety
	 */
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();

	if (State::DISENGAGE == state) {
		if (updCount % 32 == 1) {
			const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
			if (position.SqDistance2D(leader->GetPos(frame)) < SQUARE(maxDist)) {
				state = State::ROAM;
			} else {
				if (IsQueryReady(leader)) {
					FallbackBasePos();
				}
				return;
			}
		} else {
			return;
		}
	}

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if ((task != nullptr) && task->Merge(this)) {
		units.clear();
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
				if (unit->GetTravelAct() != nullptr) {
					unit->GetTravelAct()->StateWait();
				}
				TRY_UNIT(circuit, unit,
					unit->CmdFightTo(groupPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame);
				)
			}
		}
		return;
	}

	bool isExecute = (updCount % 4 == 0);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame);
		}
		if (!isExecute) {
			if (wasRegroup && !pPath->posPath.empty()) {
				ActivePath();
			}
			return;
		}
	}

	/*
	 * Update target
	 */
	StockFindTarget();

	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if (GetTarget() != nullptr) {
		state = State::ENGAGE;
		Attack(frame, GetTarget()->NotInRadarAndLOS() || (GetTarget()->GetCircuitDef() == nullptr)
			|| !GetTarget()->GetCircuitDef()->IsMobile() || circuit->IsCheating());
		return;
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (!utils::is_valid(position)) {
		FallbackBasePos();
		return;
	}

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, position, pathfinder->GetSquareSize(), GetHitTest());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CBombTask::StockFindTarget()
{
	// TODO: 1) Bombers should constantly harass undefended targets and not suicide.
	//       2) Fat target getting close to base should gain priority and be attacked by group if high AA threat.
	//       3) Avoid RoleAA targets.
	CCircuitAI* circuit = manager->GetCircuit();
	CThreatMap* threatMap = circuit->GetThreatMap();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const bool isAntiStatic = cdef->IsAttrAntiStat();
	const bool notAW = !cdef->HasSurfToWater();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const float scale = (cdef->GetMinRange() > 300.0f) ? 4.0f : 1.0f;
	const float maxPower = attackPower * scale * powerMod;
//	const float maxAltitude = cdef->GetAltitude();
	const float speed = cdef->GetSpeed() / 1.75f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
//	const float range = std::max(unit->GetUnit()->GetMaxRange() + threatMap->GetSquareSize(),
//								 cdef->GetLosRadius()) * 2;
	const float sqRange = (GetTarget() != nullptr) ? pos.SqDistance2D(GetTarget()->GetPos()) + 1.f : SQUARE(2000.0f);
	float minHealth = std::numeric_limits<float>::max();

	COOAICallback* callback = circuit->GetCallback();
	const float trueAoe = cdef->GetAoe() + SQUARE_SIZE;
	const float allyAoe = std::min(trueAoe, DEFAULT_SLACK * 2.f);
	std::function<bool (const AIFloat3& pos)> noAllies = [](const AIFloat3& pos) {
		return true;
	};
	if (allyAoe > SQUARE_SIZE * 2) {
		noAllies = [callback, allyAoe](const AIFloat3& pos) {
			return !callback->IsFriendlyUnitsIn(pos, allyAoe);
		};
	}

	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	CEnemyInfo* bestTarget = nullptr;
	position = -RgtVector;
	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden()) {
			continue;
		}
		const AIFloat3& ePos = enemy->GetPos();
		float power = threatMap->GetThreatAt(ePos)/*- enemy->GetThreat(ROLE_TYPE(BOMBER))*/;
		if ((maxPower <= power) ||
			(notAW && (ePos.y < -SQUARE_SIZE * 5)))
		{
			continue;
		}

		int targetCat;
		float health;
//		float altitude;
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			if ((edef->GetSpeed() > speed)
				|| (isAntiStatic && edef->IsMobile())
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore())
			{
				continue;
			}
			targetCat = edef->GetCategory();
			if ((targetCat & canTargetCat) == 0) {
				continue;
			}
			health = enemy->GetHealth();
//			altitude = edef->GetAltitude();
		} else {
//			targetCat = ~noChaseCat;
//			altitude = 0.f;
			continue;
		}

		if (/*enemy->IsInRadarOrLOS() && */((targetCat & noChaseCat) == 0)
			/*&& (altitude < maxAltitude)*/
			&& noAllies(ePos))
		{
//			float cost = 0.f;
//			auto enemies = circuit->GetCallback()->GetEnemyUnitIdsIn(ePos, trueAoe);
//			for (int enemyId : enemies) {
//				CEnemyInfo* ei = circuit->GetEnemyInfo(enemyId);
//				if (ei == nullptr) {
//					continue;
//				}
//				// FIXME: Finish
//                if (near.getHealth() > damage * (1 - near.distanceTo(e.getPos()) * falloff)) {
//                    metalKilled += 0.33 * near.getMetalCost() * damage * (1 - near.distanceTo(e.getPos()) * falloff) / near.getDef().getHealth();
//                } else {
//                    metalKilled += near.getMetalCost();
//                }
//				cost += ei->GetCost();
//			}
			if (minHealth > health) {
				minHealth = health;
				const float sqDist = pos.SqDistance2D(ePos);
				if (sqDist < sqRange) {
					bestTarget = enemy;
				} else {
					position = ePos;
					bestTarget = nullptr;
				}
			}
		}
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		position = bestTarget->GetPos();
	}
	// Return: target, startPos=leader->pos, endPos=position
}

bool CAntiAirTask::StockCanAssignTo(CCircuitUnit* unit) const
{
	if (!unit->GetCircuitDef()->IsRoleAA() ||
		(unit->GetCircuitDef() != leader->GetCircuitDef()))
	{
		return false;
	}
	const int frame = manager->GetCircuit()->GetLastFrame();
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(1000.f)) {
		return false;
	}
	return true;
}

void CAntiAirTask::StockFindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
	const float maxPower = attackPower * powerMod;
//	const CCircuitDef::RoleT role = cdef->GetMainRole();

	CEnemyInfo* bestTarget = nullptr;
	float minSqDist = std::numeric_limits<float>::max();

	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden()) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		if ((maxPower <= threatMap->GetThreatAt(ePos)/* - enemy->GetThreat(role)*/)
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		CCircuitDef* edef = enemy->GetCircuitDef();
		if ((edef == nullptr)  // TODO: for edef == nullptr check elevation and speed
			|| ((edef->GetCategory() & canTargetCat) == 0)
			|| ((edef->GetCategory() & noChaseCat) != 0)
			|| circuit->GetCircuitDef(edef->GetId())->IsIgnore())
		{
			continue;
		}
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		if (edef->IsInWater(elevation, ePos.y)) {
			if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater())) {  // notAW
				continue;
			}
		} else if (edef->IsAbleToFly()) {
			if (!(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())) {  // notAA
				continue;
			}
		} else {
			if (!(IsInWater ? cdef->HasSubToLand() : cdef->HasSurfToLand())) {  // notAL
				continue;
			}
		}

		const float sqDist = pos.SqDistance2D(ePos);
		if (minSqDist > sqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
	}

	SetTarget(bestTarget);
	if (bestTarget != nullptr) {
		position = GetTarget()->GetPos();
	}
	// Return: target, startPos=leader->pos, endPos=position
}

} // namespace circuit
