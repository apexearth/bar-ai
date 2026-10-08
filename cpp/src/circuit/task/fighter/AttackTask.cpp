/*
 * AttackTask.cpp
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#include <chrono>
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
#include "unit/ally/AllyUnit.h"
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
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->SetPath(pPath, lowestSpeed);
		}
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
	// AN OUTGUNNED FALL-BACK IS FINISHED BEFORE THE SQUAD RECONSIDERS: re-picking
	// a target every few updates walked it back into the group it had just left.
	// Only arrival ends it -- a retreat with them on its heels is hit constantly,
	// and units fire on the move anyway.
	if (fallBackActive) {
		if (!pPath->posPath.empty()
			&& (startPos.SqDistance2D(fallBackTo) > SQUARE(DEFAULT_SLACK * 4))) {
			return;
		}
		fallBackActive = false;
	}
//	if (circuit->GetInflMap()->GetInfluenceAt(startPos) < -INFL_EPS) {
//		SetTarget(nullptr);  // FIXME: back-forths group
//	} else {
		const auto tFt0 = std::chrono::steady_clock::now();
		FindTarget();
		manager->PerfAdd(21, std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - tFt0).count());
//	}
	RepairBreak(frame);

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

	atStage = false;
	if ((GetTarget() == nullptr) && circuit->GetMilitaryManager()->IsFocus(frame)
		&& !circuit->GetMilitaryManager()->IsFocusGo())
	{
		// Stage short of the line's reach, then back toward home until the threat
		// map is clear for this squad: inside the threat no path ends there, and a
		// squad standing in it is shot while it waits.
		CMilitaryManager* mm = circuit->GetMilitaryManager();
		const AIFloat3& fp = mm->GetFocusPos();
		const AIFloat3& home = circuit->GetSetupManager()->GetBasePos();
		const AIFloat3 dir = (home - fp).Normalize2D();
		const float back = fp.distance2D(home);
		float d = mm->GetFocusR() + DEFAULT_SLACK * 4;
		AIFloat3 stage = fp + dir * d;
		CThreatMap* tm = circuit->GetThreatMap();
		for (int k = 0; (k < 40) && (d + DEFAULT_SLACK * 2 < back) && (tm->GetThreatAt(leader, stage) > THREAT_MIN); ++k) {
			d += DEFAULT_SLACK * 2;
			stage = fp + dir * d;
		}
		CTerrainManager::CorrectPosition(stage);
		if (startPos.SqDistance2D(stage) < SQUARE(DEFAULT_SLACK * 4)) {
			atStage = true;
			return;
		}
		position = stage;
	} else if (GetTarget() == nullptr) {
		forEco = !outgunned && MarchEnemyBox();
		if (!forEco) {
			if (outgunned && (frame >= nextFrontLog)) {
				nextFrontLog = frame + FRAMES_PER_SEC * 10;
				circuit->LOG("apex: atk-front t=%i lead=%s n=%i pow=%.1f at=%.0f,%.0f",
						circuit->GetTeamId(), leader->GetCircuitDef()->GetDef()->GetName(), (int)units.size(),
						attackPower * powerMod, startPos.x, startPos.z);
			}
			FallbackFrontPos();
		}
		return;
	}

	const AIFloat3& endPos = position;
	CPathFinder* pathfinder = circuit->GetPathfinder();
	const float eps = pathfinder->GetSquareSize();
	// to a staging point (no target) the squad walks to the point, not to weapon range of it
	const float pathRange = (GetTarget() == nullptr) ? DEFAULT_SLACK : std::max(highestRange - eps, eps);

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
	float bestInfl = 0.f;
	bool bestThreat = false;
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
	// apex: the team push (script plannet.as). Gathering, only a threat to the
	// base is taken; on the go, the breach wins the choice and is weighed
	// against the team's gathered power, not this squad's.
	CMilitaryManager* milMgr = circuit->GetMilitaryManager();
	const bool focusOn = milMgr->IsFocus(frame);
	const bool focusGo = focusOn && milMgr->IsFocusGo();
	const AIFloat3 focusPos = milMgr->GetFocusPos();
	const float sqFocusR = SQUARE(milMgr->GetFocusR() + highestRange);
	auto atFocus = [&](const AIFloat3& p) {
		return focusGo && (p.SqDistance2D(focusPos) < sqFocusR);
	};
	struct SSelf { AIFloat3 pos; float r; float power; };
	std::vector<SSelf> selfUnits;
	selfUnits.reserve(units.size());
	for (CCircuitUnit* u : units) {
		const CCircuitDef* ud = u->GetCircuitDef();
		int cells = ud->GetThreatRange(CCircuitDef::ThreatType::SURF);
		if (ud->GetMaxRange() > 1000.f) {
			cells /= 2;
		}
		const float r = float(cells) * inflCell;
		if (r > 0.f) {
			selfUnits.push_back({u->GetPos(frame), r, ud->GetPower()});
		}
	}
	auto selfInflAt = [&](const AIFloat3& p) {
		float s = 0.f;
		for (const SSelf& su : selfUnits) {
			const float d = su.pos.distance2D(p);
			if (d < su.r) {
				s += su.power * (1.f - d / su.r);
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
	int skippedSpam = 0;
	int ignoredSmall = 0;
	int refusedStrong = 0;
	float prevScore = -1.f;
	const AIFloat3 foeBase = circuit->GetSetupManager()->GetEnemyBoxCentre();
	const bool pushing = utils::is_valid(foeBase);
	// apex: why an armed enemy next to the squad is not its target (atk-near).
	const float sqNear = SQUARE(highestRange + 300.f);
	enum { NR_OVERP, NR_STRONG, NR_REACH, NR_HIDDEN, NR_VEL, NR_CAT, NR_SPAM, NR_IGN, NR_HOME, NR_CAND, NR_N };
	int nearWhy[NR_N] = {0};
	bool outgunnedNear = false;
	auto isNear = [&](CEnemyInfo* e) {
		return (e != nullptr) && (e->GetCircuitDef() != nullptr) && e->GetCircuitDef()->IsMobile()
				&& e->GetCircuitDef()->IsAttacker() && (pos.SqDistance2D(e->GetPos()) < sqNear);
	};
	auto countGroupNear = [&](const CEnemyManager::SEnemyGroup& g, int why) {
		for (const ICoreUnit::Id eId : g.units) {
			if (isNear(circuit->GetEnemyInfo(eId))) {
				++nearWhy[why];
			}
		}
	};

	// THE GROUP THAT OUTGUNNED US IS REMEMBERED: tracked within the squad's own
	// reach twice over while it stays stronger; until then no target lies at or
	// beyond its distance from our base. Re-targeting past it walked the squad
	// back into it after every fall-back (advance, drop, fall back, advance).
	if (strongMem) {
		bool still = false;
		const float track = SQUARE(2.f * highestRange);
		for (const CEnemyManager::SEnemyGroup& g : groups) {
			if ((g.pos.SqDistance2D(strongPos) < track) && (maxPower <= g.influence)) {
				strongPos = g.pos;
				still = true;
				break;
			}
		}
		strongMem = still;
	}
	const float sqStrongBase = strongMem ? strongPos.SqDistance2D(basePos) : 0.f;

	for (unsigned i = 0; i < groups.size(); ++i) {
		const CEnemyManager::SEnemyGroup& group = groups[i];
		if (focusOn && !focusGo && !isThreat[i]) {
			continue;
		}
		if (strongMem && !atFocus(group.pos) && (group.pos.SqDistance2D(basePos) >= sqStrongBase)) {
			countGroupNear(group, NR_STRONG);
			continue;
		}
		const bool isOverpowered = maxPower * 0.125f > group.influence;
		if (hasGoodTarget && isOverpowered) {
			countGroupNear(group, NR_OVERP);
			continue;
		}
		// apex: squared over squared, as upstream CircuitAI. The fork base divided
		// a distance by a squared distance, so scale was ~0 anywhere past a few
		// hundred elmos from base and squads picked groups up to 20x their power.
		const float sqBEDist = group.pos.SqDistance2D(basePos);  // Base to Enemy distance
		const float scale = std::min(sqBEDist / std::max(sqOBDist, 1.f), 1.f);
		const float effPower = atFocus(group.pos) ? std::max(maxPower, milMgr->GetFocusPow()) : maxPower;
		if ((effPower <= group.influence * scale) && (inflMap->GetInfluenceAt(group.pos) < INFL_SAFE)) {
			++refusedStrong;
			countGroupNear(group, NR_STRONG);
			for (const ICoreUnit::Id eId : group.units) {
				CEnemyInfo* e = outgunnedNear ? nullptr : circuit->GetEnemyInfo(eId);
				CCircuitDef* ed = (e != nullptr) ? e->GetCircuitDef() : nullptr;
				if ((ed != nullptr) && ed->IsMobile() && ed->IsAttacker()
					&& (pos.SqDistance2D(e->GetPos()) < SQUARE(float(ed->GetThreatRange(CCircuitDef::ThreatType::SURF)) * inflCell)))
				{
					outgunnedNear = true;
					strongMem = true;
					strongPos = group.pos;
				}
			}
			continue;
		}
		if (!terrainMgr->CanMobileReachAt(area, group.pos, highestRange)) {
			countGroupNear(group, NR_REACH);
			continue;
		}

		for (const ICoreUnit::Id eId : group.units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			const bool nearE = isNear(enemy);
			if ((enemy == nullptr) || enemy->IsHidden()/* || (enemy->GetTasks().size() > 2)*/) {
				nearWhy[NR_HIDDEN] += nearE ? 1 : 0;
				continue;
			}
			const AIFloat3& ePos = enemy->GetPos();
			const AIFloat3& eVel = enemy->GetVel();
			if ((eVel.SqLength2D() >= maxSpeed)/* && (eVel.dot2D(pos - ePos) < 0)*/) {  // speed and direction
				nearWhy[NR_VEL] += nearE ? 1 : 0;
				continue;
			}

			const float elevation = circuit->GetElevationAt(ePos);
			const bool IsInWater = cdef->IsPredictInWater(elevation);
			CCircuitDef* edef = enemy->GetCircuitDef();
			if (edef != nullptr) {
				if (((edef->GetCategory() & canTargetCat) == 0)
					|| ((edef->GetCategory() & noChaseCat) != 0)
					|| (isAntiStatic && edef->IsMobile())
					|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()  // NOTE: groups are created by leader, ignore flags could be different
					|| (edef->IsAbleToFly() && !cdef->IsAirHunter(IsInWater)))  // notAA
				{
					nearWhy[NR_CAT] += nearE ? 1 : 0;
					continue;
				}
				if (edef->IsInWater(elevation, ePos.y)) {
					if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater())) {  // notAW
						nearWhy[NR_CAT] += nearE ? 1 : 0;
						continue;
					}
				} else {
					if (!(IsInWater ? cdef->HasSubToLand() : cdef->HasSurfToLand())) {  // notAL
						nearWhy[NR_CAT] += nearE ? 1 : 0;
						continue;
					}
				}
				if ((ePos.y - elevation > weaponRange)
					/*|| enemy->IsBeingBuilt()*/)
				{
					nearWhy[NR_CAT] += nearE ? 1 : 0;
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
			if (atFocus(ePos)) {
				pull *= 100.f;
			}
			// NEAR OUR OWN BASE, squared like the leader term (apexearth
			// 2026-09-28): stock's linear distBE let every ally's army walk to
			// the same far structure. Floored at our range so enemies inside
			// the base still rank by leader distance and pull.
			const float rawSqBE = ePos.SqDistance2D(basePos);
			// apex: the pull is toward THEIR base, not ours
			// (apexearth 2026-09-30: "We need to be pushing... there's no
			// significant threat that we can see. So why don't we just keep going?").
			// A real army (visible, not a speck) is fought wherever it is: the
			// nearest one wins, with no pull toward either base -- the push
			// ranked their army at our gate below their solars.
			const bool realArmy = (edef != nullptr) && edef->IsMobile() && !isOverpowered;
			const float sqBE = realArmy ? SQUARE(weaponRange)
					: std::max(pushing ? ePos.SqDistance2D(foeBase) : rawSqBE, SQUARE(weaponRange));
			// apex: no chasing ghosts (apexearth 2026-09-30: "we're moving around
			// not pushing at the enemy"). A unit we cannot see or hear is not
			// where it was; and a group under an eighth of our power is shot on
			// the way if it stands in our path, never walked to.
			if ((edef != nullptr) && edef->IsMobile()
				&& (!enemy->IsInRadarOrLOS()
					|| (isOverpowered && (pos.SqDistance2D(ePos) > SQUARE(highestRange * 1.5f)))))
			{
				++skippedSpam;
				nearWhy[NR_SPAM] += nearE ? 1 : 0;
				continue;
			}
			// apex: on the way to their buildings, an army under half ours is shot
			// on the move and never turned for (apexearth 2026-09-30, and his
			// "armies ignore enemies less than half their strength unless
			// defending the home base"): Titans swung between a geothermal behind
			// their base and a Titan blinking in and out of radar for minutes.
			if (forEco && (edef != nullptr) && edef->IsMobile() && !isThreat[i]
				&& (group.influence * 2.f < maxPower))
			{
				++ignoredSmall;
				nearWhy[NR_IGN] += nearE ? 1 : 0;
				continue;
			}
			const float sqOEDist = group.vagueMetric * pos.SqDistance2D(ePos) * sqBE / pull;  // Own to Enemy distance
			if (enemy == prevTarget) {
				prevScore = sqOEDist;
			}
			if (canGoHome && !isThreat[i]) {
				const float dHome = std::sqrt(rawSqBE);
				if ((dHome > threatD) && (dHome / ourSpeed > threatS)) {
					++refusedHome;
					nearWhy[NR_HOME] += nearE ? 1 : 0;
					continue;
				}
			}
			nearWhy[NR_CAND] += nearE ? 1 : 0;
			if (minSqDist > sqOEDist) {
				minSqDist = sqOEDist;
				bestTarget = enemy;
				bestPull = pull;
				bestSup = sup;
				bestInfl = group.influence;
				bestThreat = isThreat[i];
				hasGoodTarget |= !isOverpowered;
			}
		}
	}

	// apex: keep the target we are walking to unless another is twice as good
	// (apexearth: consistent orders, no flip-flop). prevScore is set only when
	// the old target was seen alive in this very pass.
	CEnemyInfo* const scoredBest = bestTarget;
	if ((prevScore >= 0.f) && (bestTarget != prevTarget) && (minSqDist * 2.f > prevScore)) {
		bestTarget = prevTarget;
	}
	// A stronger group that can already hit us is not walked past to a target
	// beyond it (docs/24: never throw the army at a superior force; concentrate).
	CEnemyInfo* const dropped = outgunnedNear ? bestTarget : nullptr;
	if (outgunnedNear) {
		bestTarget = nullptr;
		if (frame >= nextDropLog) {
			nextDropLog = frame + FRAMES_PER_SEC * 10;
			CCircuitDef* ddef = (dropped != nullptr) ? dropped->GetCircuitDef() : nullptr;
			circuit->LOG("apex: atk-drop t=%i lead=%s n=%i pow=%.1f drop=%s dDrop=%.0f strong=%i at=%.0f,%.0f",
					circuit->GetTeamId(), cdef->GetDef()->GetName(), (int)units.size(), maxPower,
					(ddef != nullptr) ? ddef->GetDef()->GetName() : "-",
					(dropped != nullptr) ? pos.distance2D(dropped->GetPos()) : -1.f,
					refusedStrong, pos.x, pos.z);
		}
	}
	outgunned = (refusedStrong > 0);
	{
		int nearAll = 0;
		for (int k = 0; k < NR_N; ++k) {
			nearAll += nearWhy[k];
		}
		const bool tgtNear = (bestTarget != nullptr) && (pos.SqDistance2D(bestTarget->GetPos()) < sqNear);
		if ((nearAll > 0) && !tgtNear && (frame >= nextNearLog)) {
			nextNearLog = frame + FRAMES_PER_SEC * 10;
			CCircuitDef* tdef = (bestTarget != nullptr) ? bestTarget->GetCircuitDef() : nullptr;
			circuit->LOG("apex: atk-near t=%i lead=%s n=%i pow=%.1f tgt=%s dTgt=%.0f sticky=%i near=%i"
					" overp=%i strong=%i reach=%i hidden=%i vel=%i cat=%i spam=%i ign=%i home=%i cand=%i",
					circuit->GetTeamId(), cdef->GetDef()->GetName(), (int)units.size(), maxPower,
					(tdef != nullptr) ? tdef->GetDef()->GetName() : "-",
					(bestTarget != nullptr) ? pos.distance2D(bestTarget->GetPos()) : -1.f,
					(scoredBest != bestTarget) ? 1 : 0, nearAll,
					nearWhy[NR_OVERP], nearWhy[NR_STRONG], nearWhy[NR_REACH], nearWhy[NR_HIDDEN], nearWhy[NR_VEL],
					nearWhy[NR_CAT], nearWhy[NR_SPAM], nearWhy[NR_IGN], nearWhy[NR_HOME], nearWhy[NR_CAND]);
		}
	}

	// A FIGHT OUR SIDE IS ALREADY IN (apexearth 2026-10-08: squads walk across
	// the map to a fight that is won or lost before they arrive). A new target
	// with our units or an ally's already engaged there is the script's call --
	// a net scored on whether the squad arrived while it still raged. A refusal
	// holds for 30 s so the same target is not asked again every update.
	if ((bestTarget != nullptr) && (bestTarget != prevTarget)) {
		const AIFloat3& tp = bestTarget->GetPos();
		if ((bestTarget == joinRefused) && (frame < joinRefusedUntil)) {
			bestTarget = nullptr;
		} else {
			const float fightR = std::max(cdef->GetLosRadius(), 400.f) * 2.f;
			float allyPow = 0.f;
			for (const auto& kv : circuit->GetFriendlyUnits()) {
				CAllyUnit* au = kv.second;
				if ((au == nullptr) || (au->GetCircuitDef() == nullptr) || !au->GetCircuitDef()->IsMobile()
					|| (au->GetCircuitDef()->GetPower() <= 1.f) || (au->GetTask() == this))
				{
					continue;
				}
				if (au->GetPos(frame).SqDistance2D(tp) <= SQUARE(fightR)) {
					allyPow += au->GetCircuitDef()->GetPower();
				}
			}
			const float foePow = circuit->GetMilitaryManager()->GetEnemyInflNear(tp, fightR);
			if ((allyPow > 0.f) && (foePow > 0.f)) {
				const float travelS = pos.distance2D(tp) / ourSpeed;
				if (!circuit->GetMilitaryManager()->AskJoinFight(tp, travelS, allyPow, foePow, maxPower, leader->GetId())) {
					joinRefused = bestTarget;
					joinRefusedUntil = frame + FRAMES_PER_SEC * 30;
					bestTarget = nullptr;
				}
			}
		}
	}

	const bool wasEco = forEco;
	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		position = GetTarget()->GetPos();
		CCircuitDef* bdef = bestTarget->GetCircuitDef();
		forEco = (bdef != nullptr) && !bdef->IsMobile();
		if (bestTarget != prevTarget) {
			circuit->LOG("apex: atktgt t=%i lead=%s def=%s at=%.0f,%.0f dBase=%.0f dLead=%.0f pull=%.2f n=%i"
				" backS=%.0f deadlineS=%.0f threatD=%.0f refused=%i home=%i sup=%.0f spam=%i push=%i"
				" eco=%i ign=%i lid=%i grp=%.1f pow=%.1f thr=%i strong=%i",
				circuit->GetTeamId(), cdef->GetDef()->GetName(),
				(bdef != nullptr) ? bdef->GetDef()->GetName() : "-",
				position.x, position.z, position.distance2D(basePos), position.distance2D(pos),
				bestPull, (int)units.size(), position.distance2D(basePos) / ourSpeed,
				(threatS < std::numeric_limits<float>::max()) ? threatS : -1.f, threatD, refusedHome,
				canGoHome ? 1 : 0, bestSup, skippedSpam, pushing ? 1 : 0,
				wasEco ? 1 : 0, ignoredSmall, leader->GetId(), bestInfl, maxPower, bestThreat ? 1 : 0,
				refusedStrong);
		}
	} else if ((refusedStrong > 0) && (frame >= nextStrongLog)) {
		nextStrongLog = frame + FRAMES_PER_SEC * 30;
		circuit->LOG("apex: atk-wait t=%i lead=%s n=%i pow=%.1f strong=%i groups=%i at=%.0f,%.0f dBase=%.0f",
			circuit->GetTeamId(), cdef->GetDef()->GetName(), (int)units.size(), maxPower,
			refusedStrong, (int)groups.size(), pos.x, pos.z, pos.distance2D(basePos));
	}
	// Return: target, startPos=leader->pos, endPos=position
}

void CAttackTask::ApplyTargetPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
		return;
	}
	// apex: no threat-clear path to the team's staging point -- walk there anyway;
	// the front fallback sent gathering squads anywhere but the gather.
	CCircuitAI* circuit = manager->GetCircuit();
	CMilitaryManager* mm = circuit->GetMilitaryManager();
	const int frame = circuit->GetLastFrame();
	if ((GetTarget() == nullptr) && mm->IsFocus(frame) && !mm->IsFocusGo() && (leader != nullptr)) {
		if (frame >= nextStageLog) {
			nextStageLog = frame + FRAMES_PER_SEC * 10;
			const AIFloat3& lp = leader->GetPos(frame);
			circuit->LOG("apex: atk-stage-nopath t=%i lead=%s n=%i at=%.0f,%.0f to=%.0f,%.0f",
				circuit->GetTeamId(), leader->GetCircuitDef()->GetDef()->GetName(), (int)units.size(),
				lp.x, lp.z, position.x, position.z);
		}
		for (CCircuitUnit* u : units) {
			TRY_UNIT(circuit, u,
				u->CmdMoveTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::RALLY);
			)
		}
		return;
	}
	FallbackFrontPos();
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
			if (outgunned && !pPath->posPath.empty()) {
				fallBackActive = true;
				fallBackTo = pPath->posPath.back();
			}
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
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

// apex: a building we cannot bring down is being repaired (apexearth
// 2026-09-30): after 10 s engaged with its health not falling, the squad
// switches to the enemy builder standing within build range of it, and stays
// on it until it dies or is lost.
void CAttackTask::RepairBreak(int frame)
{
	CCircuitAI* circuit = manager->GetCircuit();
	if (repairerId >= 0) {
		CEnemyInfo* rep = circuit->GetEnemyInfo(repairerId);
		if ((rep != nullptr) && !rep->IsHidden()
			&& (leader->GetPos(frame).SqDistance2D(rep->GetPos()) < SQUARE(highestRange + 1000.f)))
		{
			SetTarget(rep);
			position = rep->GetPos();
			return;
		}
		repairerId = -1;
	}
	CEnemyInfo* t = GetTarget();
	CCircuitDef* tdef = (t != nullptr) ? t->GetCircuitDef() : nullptr;
	const AIFloat3& lead = leader->GetPos(frame);
	if ((tdef == nullptr) || tdef->IsMobile()
		|| (lead.SqDistance2D(t->GetPos()) > SQUARE(highestRange + 300.f)))
	{
		stallId = -1;
		return;
	}
	const float hp = t->GetHealth();
	if ((t->GetId() != stallId) || (hp < stallHp * 0.95f)) {
		stallId = t->GetId();
		stallHp = hp;
		stallSince = frame;
		return;
	}
	if (frame < stallSince + FRAMES_PER_SEC * 10) {
		return;
	}
	const AIFloat3& tp = t->GetPos();
	CEnemyInfo* best = nullptr;
	float bestSq = std::numeric_limits<float>::max();
	for (auto& kv : circuit->GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		CCircuitDef* edef = e->GetCircuitDef();
		if ((e == t) || (edef == nullptr) || e->IsHidden() || !edef->IsBuilder()
			|| (edef->GetBuildDistance() <= 0.f))
		{
			continue;
		}
		const float reach = edef->GetBuildDistance() + tdef->GetRadius();
		if (e->GetPos().SqDistance2D(tp) > SQUARE(reach)) {
			continue;
		}
		const float sq = e->GetPos().SqDistance2D(lead);
		if (sq < bestSq) {
			bestSq = sq;
			best = e;
		}
	}
	stallSince = frame;
	if (best == nullptr) {
		return;
	}
	repairerId = best->GetId();
	circuit->LOG("apex: repair-break %s held %.0f hp for 10s -> %s",
			tdef->GetDef()->GetName(), hp, best->GetCircuitDef()->GetDef()->GetName());
	SetTarget(best);
	position = best->GetPos();
}

} // namespace circuit
