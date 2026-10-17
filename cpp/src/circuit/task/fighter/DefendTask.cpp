/*
 * DefendTask.cpp
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#include "task/fighter/DefendTask.h"
#include "task/fighter/Catch.h"
#include "map/InfluenceMap.h"
#include <algorithm>
#include <map>
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
#include "unit/enemy/EnemyManager.h"
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
	if ((leader != nullptr) && !manager->GetCircuit()->IsStockArmy()
		&& !SameClimb(manager->GetCircuit(), leader->GetCircuitDef(), unit->GetCircuitDef()))
	{
		return false;
	}
	if (birth || (manager->GetCircuit()->GetLastFrame() < detachUntil)) {
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
	if (birth) {
		auto it = birthJoined.find(unit);
		if (it != birthJoined.end()) {
			if (!releasing && (manager->GetCircuit()->GetLastFrame() - it->second < FRAMES_PER_SEC * 10)) {
				static_cast<CMilitaryManager*>(manager)->NoteBirthPulled(unit == damagedNow);
			}
			birthJoined.erase(it);
		}
	}
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

void CDefendTask::SetBirth(const AIFloat3& at, float reach)
{
	birth = true;
	anchor = at;
	position = at;
	birthReach = reach;
	lastThreat = manager->GetCircuit()->GetLastFrame();
}

void CDefendTask::AddBirthUnit(CCircuitUnit* unit, float reach)
{
	birthJoined[unit] = manager->GetCircuit()->GetLastFrame();
	birthReach = std::max(birthReach, reach);
}

void CDefendTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	damagedNow = unit;
	ISquadTask::OnUnitDamaged(unit, attacker);
	damagedNow = nullptr;
}

void CDefendTask::OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	birthJoined.erase(unit);
	ISquadTask::OnUnitDestroyed(unit, attacker);
}

void CDefendTask::BirthUpdate()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	if (circuit->GetEnemyManager()->GetEnemyEngagingCostNear(anchor, birthReach) > 0.f) {
		lastThreat = frame;
	} else if (frame - lastThreat >= FRAMES_PER_SEC * 5) {
		static_cast<CMilitaryManager*>(manager)->NoteBirthReleased((int)units.size());
		releasing = true;
		manager->AbortTask(this);
		return;
	}

	IFighterTask::Update();
	if (leader == nullptr) {
		return;
	}
	const bool isTargetsFound = FindTarget();
	if (leader == nullptr) {
		return;
	}
	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if ((GetTarget() != nullptr) || isTargetsFound) {
		if (position.SqDistance2D(startPos) < SQUARE(highestRange + 300.f)) {
			state = State::ENGAGE;
			Attack(frame);
			return;
		}
	}
	if (!IsQueryReady(leader)) {
		return;
	}
	if (!isTargetsFound) {
		position = anchor;
		if (anchor.SqDistance2D(startPos) > SQUARE(DEFAULT_SLACK * 2)) {
			Fallback();
		}
		return;
	}
	PathToEnemies(frame);
}

void CDefendTask::PathToEnemies(int frame)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& startPos = leader->GetPos(frame);
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

void CDefendTask::Update()
{
	if (manager->GetCircuit()->IsStockArmy()) {
		StockUpdate();
		return;
	}
	++updCount;
	if (birth) {
		BirthUpdate();
		return;
	}
	if (ScriptMoveUpdate()) {
		return;
	}
	const bool hunting = manager->GetCircuit()->GetLastFrame() < detachUntil;
	// a sortie back home is a pool again
	if (!hunting && IsJoinCommitted() && (leader != nullptr)) {
		CCircuitAI* c = manager->GetCircuit();
		CMilitaryManager* mm = c->GetMilitaryManager();
		const float sqR = SQUARE(mm->GetBaseDefRange());
		const AIFloat3& lp = leader->GetPos(c->GetLastFrame());
		const AIFloat3 stand = mm->GetDefenceStand();
		if ((lp.SqDistance2D(c->GetSetupManager()->GetBasePos()) < sqR)
			|| (utils::is_valid(stand) && (lp.SqDistance2D(stand) < sqR)))
		{
			JoinReopen();
		}
	}

	/*
	 * Promote task if possible
	 */
	// apex_gather: a pool never walks out to a squad already launched, and an all-raider pool leaves only when
	// nnraid.as launches it whole on its fight estimate (gather.as)
	const bool gather = manager->GetCircuit()->GetTunable("apex_gather", 0.f) > 0.f;
	bool scriptLaunch = false;
	if (gather && (promote == FightType::RAID) && (manager->GetCircuit()->GetTunable("apex_nnraid", 1.f) > 0.f)) {
		scriptLaunch = true;
		for (CCircuitUnit* unit : units) {
			scriptLaunch = scriptLaunch && unit->GetCircuitDef()->IsRoleRaider();
		}
	}
	if (!hunting && !scriptLaunch && (updCount % 32 == 1)) {
		CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
		// JOIN THE SQUAD, NOT THE TARGET (docs/doctrine.md; his 10-13: "We make 1 fuckin unit and are
		// charging out to meet these guys on our doorstep", Tzars sent alone): under its bar a
		// pool walks to the strongest live squad of its kind; only a full bar opens a new one.
		if (!gather && (attackPower < maxPower) && !units.empty() && !militaryMgr->GetTasks(check).empty()) {
			IFighterTask* best = militaryMgr->BestSquadToJoin(check, *units.begin(), this);
			if (best != nullptr) {
				static std::map<const CCircuitAI*, std::pair<int, int>> joined;   // count, next log frame
				CCircuitAI* circuit = manager->GetCircuit();
				auto& j = joined[circuit];
				j.first += (int)units.size();
				if (circuit->GetLastFrame() >= j.second) {
					j.second = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
					circuit->LOG("apex: pool-joins-squad n=%i pool=%.1f bar=%.1f squad=%.1f", j.first,
							attackPower, maxPower, best->GetAttackPower());
				}
				decltype(units) tmpUnits = units;
				for (CCircuitUnit* unit : tmpUnits) {
					manager->AssignTask(unit, best);
				}
				return;
			}
		}
		if (attackPower >= maxPower) {
			IFighterTask* task = militaryMgr->Enqueue(TaskF::Common(promote));
			decltype(units) tmpUnits = units;
			for (CCircuitUnit* unit : tmpUnits) {
				manager->AssignTask(unit, task);
			}
			task->JoinCommit(0);
//			manager->DoneTask(this);  // NOTE: RemoveAssignee() will abort task
			return;
		}
	}

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = hunting ? nullptr : GetMergeTask();
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

	if (FocusHold(frame)) {
		state = State::ENGAGE;
		Attack(frame);
		return;
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

	PathToEnemies(frame);
}

void CDefendTask::MergeFrom(ISquadTask* task)
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
	// defending the home base" (docs/doctrine.md). A raider under half the pool is left
	// to our guns where they outgun it, and otherwise to a squad of its own size
	// split off for it (apexearth 2026-10-02: "create a squad of an appropriate
	// size to chase the little amphibious tanks... if you have defense over
	// there, then you should just assume that it'll be fine").
	const int frame = circuit->GetLastFrame();
	const bool detached = frame < detachUntil;
	const float pettyBar = attackPower * .5f;
	int pettySkipped = 0;
	int leashSkipped = 0;
	float sqLeash = -1.f;
	{
		const float leash = circuit->GetTunable("apex_pool_leash", 0.f);
		if ((leash > 0.f) && !detached && circuit->HasFrontPos()) {
			sqLeash = SQUARE(basePos.distance2D(circuit->GetFrontPos()) + leash);
		}
	}
	int pettyCovered = 0;
	CEnemyInfo* detachFor = nullptr;
	float detachSq = std::numeric_limits<float>::max();
	// apex_target_value: worth over the time to reach and kill it, as AttackTask weighs a group
	const bool tv = circuit->GetTunable("apex_target_value", 0.f) > 0.f;
	const SFire fire = tv ? SquadFire() : SFire();
	const float ourSpeed = std::max(lowestSpeed, 1.f);
	const float threatSq = (float)threatMap->GetSquareSize();
	float detachThreat = .0f;
	const bool catchOn = (circuit->GetTunable("apex_open_race", 0.f) > 0.f) && !circuit->IsStockArmy();
	SChaseStat& chase = ChaseStat(circuit);
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden() || (enemy->GetTasks().size() > 2)) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		if (InKeepOut(ePos)) {
			continue;
		}
		if (birth) {
			// the odds were read when the unit was given the task; here only who engages the anchor
			const CCircuitDef* ed = enemy->GetCircuitDef();
			const float r = birthReach + ((ed != nullptr) ? ed->GetThreatRange(CCircuitDef::ThreatType::SURF) * threatSq : 0.f);
			if ((anchor.SqDistance2D(ePos) > SQUARE(r)) || !terrainMgr->CanMoveToPos(area, ePos)) {
				continue;
			}
		} else if ((inflMap->GetAllyDefendInflAt(ePos) < INFL_EPS)
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		const float sqEBDist = basePos.SqDistance2D(ePos);
		// apex_pool_leash: a gathering pool does not chase past its own staging line
		// (his "units must not trickle"): 79% of the army lost on their side died in this task.
		if (!birth && (sqLeash > 0.f) && (sqEBDist >= sqBaseRange) && (sqEBDist > sqLeash)) {
			++leashSkipped;
			continue;
		}
		float checkPower = maxPower;
		if (sqEBDist < sqBaseRange) {
			checkPower *= 4.0f - 3.0f / baseRange * sqrtf(sqEBDist);  // 400% near base
		}
		const float eThreat = threatMap->GetThreatAt(ePos);
		if (!birth && (checkPower <= eThreat)) {
			continue;
		}
		const bool petty = !birth && !detached && (units.size() > 1)
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

		const float catchP = CatchP(pos, ourSpeed, weaponRange, enemy);
		if (catchP <= 0.f) {
			++chase.unreach;
			if (catchOn) {
				++chase.refused;
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
		float score = sqDist;
		if (tv && (edef != nullptr) && (FireAt(fire, edef) > 0.f)) {
			const float killS = EnemyHp(enemy) / FireAt(fire, edef);
			score = SQUARE((std::sqrt(sqDist) + killS * ourSpeed) / std::max(TargetWorth(fire, enemy, killS), 1.f));
		}
		if (catchOn) {
			score /= SQUARE(catchP);
		}
		if (minSqDist > score) {
			minSqDist = score;
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
	if ((leashSkipped > 0) && (frame >= leashLogAt)) {
		leashLogAt = frame + FRAMES_PER_SEC * 30;
		circuit->LOG("apex: defend-leash t=%i lead=%s n=%u skipped=%i", circuit->GetTeamId(),
				cdef->GetDef()->GetName(), (unsigned)units.size(), leashSkipped);
	}
	{
		const CCircuitDef* bd = (bestTarget != nullptr) ? bestTarget->GetCircuitDef() : nullptr;
		chase.picks += (bestTarget != nullptr) ? 1 : 0;
		if ((bd != nullptr) && (bd->GetSpeed() > ourSpeed)) {
			++chase.fast;
			if (chaseFrame >= 0) {
				chase.sec += float(frame - chaseFrame) / FRAMES_PER_SEC;
				chase.dist += pos.distance2D(chasePos);
			}
			chaseFrame = frame;
			chasePos = pos;
		} else {
			chaseFrame = -1;
		}
		ChaseStatLog(circuit, frame);
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
// at home-defence parity (his 1.2x, docs/doctrine.md), keeping at least half the pool.
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
	det->JoinCommit(0);
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
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
