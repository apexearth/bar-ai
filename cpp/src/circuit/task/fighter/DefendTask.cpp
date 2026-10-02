/*
 * DefendTask.cpp
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#include "task/fighter/DefendTask.h"
#include "map/InfluenceMap.h"
#include <algorithm>
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

#include "OOAICallback.h"
#include "AISCommands.h"

namespace circuit {

using namespace springai;
using namespace terrain;

CDefendTask::CDefendTask(ITaskModule* mgr, const AIFloat3& position,
						 FightType check, FightType promote, float maxPower, float powerMod)
		: ISquadTask(mgr, FightType::DEFEND, powerMod)
		, check(check)
		, promote(promote)
		, maxPower(maxPower * powerMod)
{
	this->position = position;
}

CDefendTask::~CDefendTask()
{
}

bool CDefendTask::CanAssignTo(CCircuitUnit* unit) const
{
	if ((leader != nullptr)
		&& !SameClimb(manager->GetCircuit(), leader->GetCircuitDef(), unit->GetCircuitDef()))
	{
		return false;
	}
	if (manager->GetCircuit()->GetLastFrame() < detachUntil) {
		return false;
	}
	return (attackPower < maxPower) && (static_cast<CDefendTask*>(unit->GetTask())->GetPromote() == promote);
}

void CDefendTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);
	CCircuitDef* cdef = unit->GetCircuitDef();
	highestRange = std::max(highestRange, cdef->GetLosRadius());

	if (cdef->IsRoleSupport() && (leader != unit)) {
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

void CDefendTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	if (leader == nullptr) {
		manager->AbortTask(this);
	}
}

void CDefendTask::Start(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 pos = utils::get_radial_pos(position, SQUARE_SIZE * 32);
	CTerrainManager::CorrectPosition(pos);
	AIFloat3 freePos = terrainMgr->FindBuildSite(unit->GetCircuitDef(), pos, 300.0f, UNIT_NO_FACING, true);
//	AIFloat3 freePos = terrainMgr->FindSpringBuildSite(unit->GetCircuitDef(), pos, 300.0f, UNIT_NO_FACING);
	pos = utils::is_valid(freePos) ? freePos : pos;

	TRY_UNIT(circuit, unit,
		unit->CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, circuit->GetLastFrame() + FRAMES_PER_SEC * 60);
		unit->CmdWantedSpeed(NO_SPEED_LIMIT);
	)
}

void CDefendTask::Update()
{
	++updCount;
	const bool hunting = manager->GetCircuit()->GetLastFrame() < detachUntil;

	/*
	 * Promote task if possible
	 */
	if (!hunting && (updCount % 32 == 1)) {
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
	ISquadTask* task = hunting ? nullptr : GetMergeTask();
	if (task != nullptr) {
		task->Merge(this);
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
	const bool isTargetsFound = FindTarget();
	if (leader == nullptr) {
		return;
	}

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

void CDefendTask::Merge(ISquadTask* task)
{
	CCircuitAI* circuit = manager->GetCircuit();
	int frame = circuit->GetLastFrame();
	const AIFloat3& leadPos = leader->GetPos(frame);
	frame += FRAMES_PER_SEC * 60;

	const std::set<CCircuitUnit*>& rookies = task->GetAssignees();
	for (CCircuitUnit* unit : rookies) {
		unit->SetTask(this);

		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(leadPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame);
		)
	}
	units.insert(rookies.begin(), rookies.end());
	maxPower = std::max(maxPower, static_cast<CDefendTask*>(task)->GetMaxPower());
	attackPower += task->GetAttackPower();
	const std::set<CCircuitUnit*>& sh = task->GetShields();
	shields.insert(sh.begin(), sh.end());

	const std::map<float, std::set<CCircuitUnit*>>& rangers = task->GetRangeUnits();
	for (const auto& kv : rangers) {
		rangeUnits[kv.first].insert(kv.second.begin(), kv.second.end());
	}
}

bool CDefendTask::FindTarget()
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
	// apex: "armies ignore enemies less than half their strength unless
	// defending the home base" (docs/24). A raider under half the pool is left
	// to our guns where they outgun it, and otherwise to a squad of its own size
	// split off for it (apexearth 2026-10-02: "create a squad of an appropriate
	// size to chase the little amphibious tanks... if you have defense over
	// there, then you should just assume that it'll be fine").
	const int frame = circuit->GetLastFrame();
	const bool detached = frame < detachUntil;
	const float pettyBar = attackPower * .5f;
	int pettySkipped = 0;
	int pettyCovered = 0;
	CEnemyInfo* detachFor = nullptr;
	float detachSq = std::numeric_limits<float>::max();
	float detachThreat = .0f;
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
		const float eThreat = threatMap->GetThreatAt(ePos);
		if (checkPower <= eThreat) {
			continue;
		}
		const bool petty = !detached && (units.size() > 1)
				&& (sqEBDist >= sqBaseRange) && (eThreat < pettyBar);

		const float elevation = circuit->GetElevationAt(ePos);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			if (((edef->GetCategory() & canTargetCat) == 0)
				|| ((edef->GetCategory() & noChaseCat) != 0)
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()
				|| (edef->IsAbleToFly() && !cdef->IsAirHunter(IsInWater)))  // notAA
			{
				continue;
			}
			float elevation = circuit->GetElevationAt(ePos);
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
		if (petty) {
			++pettySkipped;
			if (inflMap->GetAllyStaticInflAt(ePos) >= eThreat) {
				++pettyCovered;
			} else if (enemy->GetTasks().empty() && (sqDist < detachSq)) {
				detachSq = sqDist;
				detachFor = enemy;
				detachThreat = eThreat;
			}
			continue;
		}
		if (minSqDist > sqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
		enemyPositions.push_back(ePos);
	}

	if (detached && (bestTarget != nullptr)) {
		detachUntil = std::max(detachUntil, frame + FRAMES_PER_SEC * 10);
	}
	int sent = 0;
	if (detachFor != nullptr) {
		sent = Detach(detachFor, detachThreat);
	}
	if (((pettySkipped > 0) || (sent > 0)) && (frame >= pettyLogAt)) {
		pettyLogAt = frame + FRAMES_PER_SEC * 30;
		circuit->LOG("apex: defend-petty t=%i lead=%s at=%.0f,%.0f n=%u skipped=%i covered=%i power=%.0f sent=%i for=%s target=%s",
				circuit->GetTeamId(), cdef->GetDef()->GetName(), pos.x, pos.z, (unsigned)units.size(),
				pettySkipped, pettyCovered, attackPower, sent,
				(detachFor != nullptr) && (detachFor->GetCircuitDef() != nullptr)
					? detachFor->GetCircuitDef()->GetDef()->GetName() : "-",
				(bestTarget != nullptr) && (bestTarget->GetCircuitDef() != nullptr)
					? bestTarget->GetCircuitDef()->GetDef()->GetName() : "-");
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

// apex: split off the members nearest the raider until they carry its threat
// at home-defence parity (his 1.2x, docs/24), keeping at least half the pool.
int CDefendTask::Detach(CEnemyInfo* enemy, float threat)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	const AIFloat3 ePos = enemy->GetPos();
	const float need = std::max(threat * 1.2f, 1.f);
	// Only fighters go, and one always stays: a squad's leader is never a
	// support unit, so a pool left with only those has no leader at all.
	std::vector<std::pair<float, CCircuitUnit*>> byDist;
	for (CCircuitUnit* unit : units) {
		if (!unit->GetCircuitDef()->IsRoleSupport()) {
			byDist.push_back(std::make_pair(unit->GetPos(frame).SqDistance2D(ePos), unit));
		}
	}
	std::sort(byDist.begin(), byDist.end(),
			[](const std::pair<float, CCircuitUnit*>& a, const std::pair<float, CCircuitUnit*>& b) {
				return a.first < b.first;
			});
	std::vector<CCircuitUnit*> pick;
	float got = .0f;
	float left = attackPower;
	for (const auto& du : byDist) {
		if (got >= need) {
			break;
		}
		const float p = du.second->GetCircuitDef()->GetPower();
		if ((left - p < attackPower * .5f) || (pick.size() + 1 >= byDist.size())) {
			break;
		}
		pick.push_back(du.second);
		got += p;
		left -= p;
	}
	if (pick.empty() || (got < need)) {
		return 0;
	}
	CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
	CDefendTask* det = static_cast<CDefendTask*>(militaryMgr->Enqueue(TaskF::Defend(check, promote, got)));
	det->position = ePos;
	det->detachUntil = frame + FRAMES_PER_SEC * 30;
	for (CCircuitUnit* unit : pick) {
		manager->AssignTask(unit, det);
	}
	return int(pick.size());
}

void CDefendTask::ApplyTargetPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
	} else {
		Fallback();
	}
}

void CDefendTask::FallbackFrontPos()
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

void CDefendTask::ApplyFrontPos(const CQueryPathMulti* query)
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

void CDefendTask::FallbackBasePos()
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

void CDefendTask::ApplyBasePos(const CQueryPathSingle* query)
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

void CDefendTask::Fallback()
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
