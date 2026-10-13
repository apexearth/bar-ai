/*
 * RaidTask.cpp
 *
 *  Created on: Jan 6, 2016
 *      Author: rlcevg
 */

#include <chrono>
#include "task/fighter/RaidTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/action/MoveAction.h"
#include "unit/action/FightAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/enemy/EnemyManager.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "AISCommands.h"

namespace circuit {

using namespace springai;
using namespace terrain;

CRaidTask::CRaidTask(ITaskModule* mgr, float maxPower, float powerMod)
		: ISquadTask(mgr, FightType::RAID, powerMod)
		, maxPower(maxPower)
{
	CCircuitAI* circuit = manager->GetCircuit();
	float x = rand() % circuit->GetTerrainManager()->GetTerrainWidth();
	float z = rand() % circuit->GetTerrainManager()->GetTerrainHeight();
	position = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
}

CRaidTask::~CRaidTask()
{
}

bool CRaidTask::CanAssignTo(CCircuitUnit* unit) const
{
	if (!unit->GetCircuitDef()->IsRoleRaider() ||
		(unit->GetCircuitDef() != leader->GetCircuitDef()))
	{
		return false;
	}
	if (attackPower > maxPower) {
		return false;
	}
	const int frame = manager->GetCircuit()->GetLastFrame();
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(1000.f)) {
		return false;
	}
	return true;
}

void CRaidTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);
	CCircuitDef* cdef = unit->GetCircuitDef();
	highestRange = std::max(highestRange, cdef->GetLosRadius());
	highestRange = std::max(highestRange, cdef->GetJumpRange());

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

void CRaidTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	if (leader == nullptr) {
		manager->AbortTask(this);
	} else {
		highestRange = std::max(highestRange, leader->GetCircuitDef()->GetLosRadius());
		highestRange = std::max(highestRange, leader->GetCircuitDef()->GetJumpRange());
	}
}

void CRaidTask::Start(CCircuitUnit* unit)
{
	if ((State::REGROUP == state) || (State::ENGAGE == state)) {
		return;
	}
	if (!pPath->posPath.empty()) {
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->SetPath(pPath);
		}
	}
}

void CRaidTask::Update()
{
	++updCount;

	/*
	 * Merge tasks if possible
	 */
	// apex: a pack sent to a priced target is not folded into another task's roam.
	ISquadTask* task = (goalR > 0.f) ? nullptr : GetMergeTask();
	if (task != nullptr) {
		task->Merge(this);
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
	const auto tFt0 = std::chrono::steady_clock::now();
	const bool isTargetsFound = FindTarget();
	manager->PerfAdd(20, std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - tFt0).count());
	if (IsCommitted() && (frame >= nextCommitLog)) {
		nextCommitLog = frame + FRAMES_PER_SEC * 20;
		const AIFloat3& lp = leader->GetPos(frame);
		circuit->LOG("apex: raid-commit t=%i %s x%i at=%.0f,%.0f goal=%.0f,%.0f d=%.0f target=%s kept=%i aaSet=%i",
				circuit->GetTeamId(), leader->GetCircuitDef()->GetDef()->GetName(), static_cast<int>(units.size()),
				lp.x, lp.z, goalPos.x, goalPos.z, lp.distance2D(goalPos),
				(GetTarget() != nullptr) && (GetTarget()->GetCircuitDef() != nullptr)
					? GetTarget()->GetCircuitDef()->GetDef()->GetName() : "-",
				keptN, aaSetN);
	}

	state = State::ROAM;
	// SHOOT WHAT SHOOTS YOU, KEEP FLYING (his 10-12): a committed gunship wing on its way to the economy
	// set-targets the nearest AA in reach -- the move order stands, so it fires going past, not stopping.
	if ((GetTarget() == nullptr) && (frame >= nextAaPick) && leader->GetCircuitDef()->IsAbleToFly() && IsCommitted()) {
		nextAaPick = frame + FRAMES_PER_SEC;
		const AIFloat3& lp = leader->GetPos(frame);
		float best = SQUARE(leader->GetCircuitDef()->GetMaxRange());
		CEnemyInfo* aa = nullptr;
		for (auto& kv : circuit->GetEnemyInfos()) {
			CEnemyInfo* e = kv.second;
			CCircuitDef* ed = e->GetCircuitDef();
			if (e->IsHidden() || !e->IsInRadarOrLOS() || (ed == nullptr) || !ed->HasSurfToAir()) {
				continue;
			}
			const float d2 = lp.SqDistance2D(e->GetPos());
			if (d2 < best) {
				best = d2;
				aa = e;
			}
		}
		if (aa != nullptr) {
			++aaSetN;
			for (CCircuitUnit* unit : units) {
				TRY_UNIT(circuit, unit,
					unit->CmdSetTarget(aa);
				)
			}
		}
	}
	if (GetTarget() != nullptr) {
		noTargetSince = -1;
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
		FallbackRaid();
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
			(IsCommitted() && !cdef->IsAbleToFly()) ? std::numeric_limits<float>::max()
				: attackPower / circuit->GetMilitaryManager()->GetRangeUnitCountCompensatorScale());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathMulti*>(query));
	});
}

void CRaidTask::Stop(bool done)
{
	manager->GetCircuit()->GetMilitaryManager()->ClearScoutPosition(this);
	ISquadTask::Stop(done);
}

void CRaidTask::OnUnitIdle(CCircuitUnit* unit)
{
	ISquadTask::OnUnitIdle(unit);
	if (units.empty()) {
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
	if ((goalR <= 0.f) && (position.SqDistance2D(leader->GetPos(circuit->GetLastFrame())) < SQUARE(maxDist))) {
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

// A raid sent at a target off our home ground commits (his 2026-10-12, docs/24 Raids): it goes for the
// economy, takes the damage on the way, and nobody walks home to be repaired.
bool CRaidTask::IsCommitted() const
{
	if (goalR <= 0.f) {
		return false;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	if (commitAt == frame) {
		return commitVal;
	}
	commitAt = frame;
	commitVal = false;
	// 1: every raid -- the RAID posture puts the main army in raid tasks too, and it lost. 2: only raiders.
	const float mode = circuit->GetTunable("apex_raid_commit", 2.f);
	if (mode <= 0.f) {
		return false;
	}
	// A gunship raid commits too (his 10-12: gunships traded with their defences for nothing).
	if ((mode >= 2.f) && ((leader == nullptr) || !leader->GetCircuitDef()->IsAbleToFly())) {
		for (CCircuitUnit* u : units) {
			if (!u->GetCircuitDef()->IsRoleRaider() && !u->GetCircuitDef()->IsCharger()) {
				return false;
			}
		}
	}
	const float baseRange = circuit->GetMilitaryManager()->GetBaseDefRange();
	commitVal = circuit->GetSetupManager()->GetBasePos().SqDistance2D(goalPos) > SQUARE(baseRange);
	return commitVal;
}

// ...but aircraft still go to the pad: a repaired gunship comes back for the price of the trip.
bool CRaidTask::AllowRetreat(CCircuitUnit* unit)
{
	if (IsCommitted() && !unit->GetCircuitDef()->IsAbleToFly()) {
		++keptN;
		return false;
	}
	return true;
}

bool CRaidTask::FindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const bool committed = IsCommitted();
	const bool flies = leader->GetCircuitDef()->IsAbleToFly();
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
		if (!isEnemyUrgent && !urgentPositions.empty()) {
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
		if (!(committed && !flies) && (checkPower <= power)) {
			continue;
		}
		const AIFloat3& eVel = enemy->GetVel();
		if ((eVel.SqLength2D() >= checkSpeed) && (eVel.dot2D(pos - ePos) < 0)) {
			continue;
		}

		int targetCat;
		float defThreat;
		bool isBuilder;
		const float elevation = circuit->GetElevationAt(ePos);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			targetCat = edef->GetCategory();
			if (((targetCat & canTargetCat) == 0)
				|| (isAntiStatic && edef->IsMobile())
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()
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
			if (ePos.y - elevation > weaponRange) {
				continue;
			}
			defThreat = enemy->GetInfluence();
			isBuilder = edef->IsEnemyRoleAny(CCircuitDef::RoleMask::BUILDER | CCircuitDef::RoleMask::COMM);
			// Committed: the economy only. Their army and their guns are walked past (shot in passing).
			if (committed && (edef->IsEnemyRoleAny(CCircuitDef::RoleMask::COMM)
				|| (!isBuilder && (edef->IsMobile()
					|| (edef->IsAttacker() && !edef->IsAttrStock())))))
			{
				continue;
			}
		} else {
			if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater()) && (ePos.y < -SQUARE_SIZE * 5)) {  // notAW
				continue;
			}
			targetCat = UNKNOWN_CATEGORY;
			defThreat = enemy->GetInfluence();
			isBuilder = false;
			if (committed && (goalPos.SqDistance2D(ePos) > SQUARE(goalR))) {
				continue;
			}
		}
		// apex: the area test last -- every enemy reached it first, before the
		// threat, speed and category tests that reject most of them.
		if (!terrainMgr->CanMobileReachAt(area, ePos, highestRange)) {
			continue;
		}

		float sqDist = pos.SqDistance2D(ePos);
		if (((committed && !flies) || (minPower > power)) && (minSqDist > sqDist)) {
			if (enemy->IsInRadarOrLOS()) {
				if (((targetCat & noChaseCat) == 0) && !enemy->IsBeingBuilt()) {
					if (committed) {
						bestTarget = enemy;   // the nearest piece of economy in reach
						minSqDist = sqDist;
					} else if (isBuilder) {
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

		// apex: with a goal, only what stands at the goal is worth walking to;
		// anything in reach on the way is still fought above.
		if ((goalR > 0.f) && (goalPos.SqDistance2D(ePos) > SQUARE(goalR))) {
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

void CRaidTask::ApplyTargetPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		noTargetSince = -1;
		position = pPath->posPath.back();
		ActivePath();
	} else {
		FallbackRaid();
	}
}

// A raid with nothing it can reach for a minute joins the army instead of
// wandering the map edges: on a narrow isthmus land raiders found no way in
// and trickled into the choke (apexearth 2026-09-26). Amphibious raiders keep
// raiding -- the water is their way round.
bool CRaidTask::GiveUpRaid()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	if (noTargetSince < 0) {
		noTargetSince = frame;
		return false;
	}
	if ((leader == nullptr) || leader->GetCircuitDef()->IsAmphibious() || leader->GetCircuitDef()->IsSurfer()
		|| leader->GetCircuitDef()->IsAbleToFly() || (frame < noTargetSince + FRAMES_PER_SEC * 60))
	{
		return false;
	}
	CMilitaryManager* militaryMgr = circuit->GetMilitaryManager();
	IFighterTask* task = militaryMgr->Enqueue(TaskF::Defend(IFighterTask::FightType::ATTACK,
			std::max(1.f, circuit->GetEnemyManager()->GetPreMaxGroupThreat())));
	if (task == nullptr) {
		return false;
	}
	circuit->LOG("apex: raid-giveup %s x%i -> army pool", leader->GetCircuitDef()->GetDef()->GetName(),
			static_cast<int>(units.size()));
	decltype(units) tmpUnits = units;
	for (CCircuitUnit* unit : tmpUnits) {
		manager->AssignTask(unit, task);
	}
	return true;
}

void CRaidTask::FallbackRaid()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const bool hasGoal = goalR > 0.f;
	if (!hasGoal && GiveUpRaid()) {
		return;
	}
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const AIFloat3& threatPos = ((leader->GetTravelAct() != nullptr) && leader->GetTravelAct()->IsActive()) ? position : pos;
	if (hasGoal) {
		position = terrainMgr->GetMovePosition(leader->GetArea(), goalPos);
	} else if (attackPower * powerMod <= threatMap->GetThreatAt(leader, threatPos)) {
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
		this->ApplyRaidPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CRaidTask::ApplyRaidPath(const CQueryPathSingle* query)
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
			if (IsCommitted()) {
				unit->CmdMoveTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			} else {
				unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			}
		)
	}
}

} // namespace circuit
