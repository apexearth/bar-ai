/*
 * RaidTask.cpp
 *
 *  Created on: Jan 6, 2016
 *      Author: rlcevg
 */

#include "task/fighter/RaidTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "resource/MetalManager.h"
#include "setup/SetupManager.h"
#include "unit/enemy/EnemyManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/action/MoveAction.h"
#include "unit/action/FightAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Log.h"

#include <limits>

namespace circuit {

using namespace springai;
using namespace terrain;

// Raids are where this AI's aggression actually lives, so this is the constant
// that decides whether it goes round or straight up the middle. maxThreat is
// only a ceiling; the per-tile cost is what shapes the route, and it was a flat
// 2x threat for every query in the AI -- a builder walking to a mex valued
// danger exactly as an army walking to the enemy base. apexearth: "AI prefers to
// attack through center, and usually humans will kill AI by attacking around the
// edges slowly over time."
static constexpr float RAID_THREAT_MOD = 4.f;
// Higher than the targeted mod: with a target chosen we accept some risk to
// reach it, but while merely looking for one there is no reason to be anywhere
// costly. This is what turns "wander toward the enemy" into "work the flank".
static constexpr float RAID_ROAM_THREAT_MOD = 8.f;
// Distance discount for the target a raid party already chose. Squared where it
// is used, because the comparison is on squared distance.
static constexpr float RAID_TARGET_STICKY = 1.4f;

// Going round, rather than hoping a cost function discovers it.
//
// Weighting threat in the path cost was tried first and measured: 138 raid paths
// came back with walked/direct between 1.00 and 1.08, i.e. straight lines. The
// threat map is near-zero except right beside enemy units, so there is no
// gradient across the middle to climb and distance always wins. A flank has to be
// asked for explicitly.
//
// Pick a waypoint pushed sideways off the straight line, on whichever side is
// quieter, then raid the real targets once it is reached.
static constexpr float FLANK_MIN_DIST = 2000.f;  // shorter raids go straight
static constexpr float FLANK_OFFSET   = 1800.f;  // how far off the line to swing
static constexpr float FLANK_MARGIN   = 400.f;   // stay off the very edge
static constexpr float FLANK_REACHED  = 700.f;

// PRESS ON, rather than going back for orders.
//
// A raid party that has eaten the mexes it could see has no target left, and
// FindTarget only knows about enemies already in CCircuitAI::GetEnemyInfos --
// the next mex field, one screen further on, has never been in LOS and does not
// exist as far as the raid is concerned. The only fallback was
// CMilitaryManager::GetScoutPosition, which scores clusters that are unclaimed
// AND below THREAT_MIN, i.e. the quiet ground; failing that, a uniformly random
// map position. Both of those are, on average, behind the party.
// apexearth: "after we do an attack raid on enemy mexes we often just turn
// around and walk home to do nothing... in reality we could usually go further
// to take out many more mexes."
//
// "Onward" is measured against the enemy CENTROID, not our own base: that is the
// direction that keeps arriving at their economy whichever flank the party came
// in on, and it needs no map-side special case. The threat test per spot is what
// stops this walking a raid into the enemy army -- an undefended spot is worth
// approaching blind, a defended one is not.
static constexpr float PRESS_STEP    = 400.f;   // ground that must be gained to count as onward
static constexpr float PRESS_MAX_LEG = 4000.f;  // one hop, not a march across the map

static AIFloat3 ChooseFlankPos(CCircuitAI* circuit, const AIFloat3& from, const AIFloat3& to)
{
	if (from.distance2D(to) < FLANK_MIN_DIST) {
		return -RgtVector;
	}
	AIFloat3 dir = to - from;
	dir.y = 0.f;
	if (dir.SqLength2D() < 1.f) {
		return -RgtVector;
	}
	dir.Normalize2D();
	const AIFloat3 perp(-dir.z, 0.f, dir.x);
	const AIFloat3 mid = (from + to) * 0.5f;

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const float w = terrainMgr->GetTerrainWidth();
	const float h = terrainMgr->GetTerrainHeight();
	CThreatMap* threatMap = circuit->GetThreatMap();

	AIFloat3 best = -RgtVector;
	float bestThreat = std::numeric_limits<float>::max();
	for (int side = -1; side <= 1; side += 2) {
		AIFloat3 cand = mid + perp * (FLANK_OFFSET * float(side));
		cand.x = std::max(FLANK_MARGIN, std::min(w - FLANK_MARGIN, cand.x));
		cand.z = std::max(FLANK_MARGIN, std::min(h - FLANK_MARGIN, cand.z));
		cand.y = circuit->GetMap()->GetElevationAt(cand.x, cand.z);
		const float threat = threatMap->GetThreatAt(cand);
		if (threat < bestThreat) {
			bestThreat = threat;
			best = cand;
		}
	}
	return best;
}

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
	if (cdef->IsAttrSiege() && (manager->GetCircuit()->GetTunable("apex_siege_fight", 1.f) > 0.f)) {
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
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetPath(pPath, lowestSpeed);
		}
	}
}

void CRaidTask::Update()
{
	++updCount;

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
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
				if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
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
	const bool isTargetsFound = FindTarget();

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
					if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
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
					if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
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

	const F3Vec& realTargets = !urgentPositions.empty() ? urgentPositions : enemyPositions;
	F3Vec flankTargets;
	const F3Vec* targets = &realTargets;
	if (!flankDone && !realTargets.empty()) {
		if (!flankSet) {
			flankPos = ChooseFlankPos(circuit, startPos, realTargets.front());
			flankSet = true;
			if (!utils::is_valid(flankPos)) {
				flankDone = true;  // too close to be worth going round
			}
		}
		if (!flankDone) {
			if (startPos.SqDistance2D(flankPos) < SQUARE(FLANK_REACHED)) {
				flankDone = true;  // out on the flank; turn in
			} else {
				flankTargets.push_back(flankPos);
				targets = &flankTargets;
				// The detour ratio cannot show this: the leg TO the waypoint is
				// itself a straight path, so walked/direct stays ~1.0 while the
				// journey as a whole goes round. Log the decision instead.
				if (circuit->GetLastFrame() >= lastFlankLog + FRAMES_PER_SEC * 20) {
					lastFlankLog = circuit->GetLastFrame();
					const AIFloat3& tgt = realTargets.front();
					circuit->LOG("apex: raid flank via (%.0f,%.0f) instead of straight to (%.0f,%.0f), lateral=%.0f",
							flankPos.x, flankPos.z, tgt.x, tgt.z, startPos.distance2D(flankPos));
				}
			}
		}
	}

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, threatMap,
			startPos, pathRange, *targets, GetHitTest(), true,
			attackPower / circuit->GetMilitaryManager()->GetRangeUnitCountCompensatorScale(),
			false, RAID_THREAT_MOD);
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
	if (position.SqDistance2D(leader->GetPos(circuit->GetLastFrame())) < SQUARE(maxDist)) {
		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		// Roam mex line to mex line, not to a random map point: after a kill
		// the nearest metal spot on enemy-influenced ground is the next stop.
		// The random point remains the fallback when no such spot is known.
		int best = -1;
		if (circuit->GetTunable("apex_raid_mexline", 1.f) > 0.f) {
			CMetalManager* metalMgr = circuit->GetMetalManager();
			CInfluenceMap* inflMap = circuit->GetInflMap();
			const AIFloat3& lp = leader->GetPos(circuit->GetLastFrame());
			const CMetalData::Metals& spots = metalMgr->GetSpots();
			float bestSq = std::numeric_limits<float>::max();
			for (unsigned i = 0; i < spots.size(); ++i) {
				const AIFloat3& sp = spots[i].position;
				const float sq = sp.SqDistance2D(lp);
				if (sq < SQUARE(maxDist)) {
					continue;  // the ground we just cleared
				}
				if ((sq >= bestSq) || (inflMap->GetEnemyInflAt(sp) <= 0.f)) {
					continue;
				}
				best = (int)i;
				bestSq = sq;
			}
			if (best >= 0) {
				position = terrainMgr->GetMovePosition(leader->GetArea(), spots[best].position);
			}
		}
		if (best < 0) {
			position = RoamPos(leader);
		}
	}

	if (units.find(unit) != units.end()) {
		Start(unit);  // NOTE: Not sure if it has effect
	}
}

bool CRaidTask::FindTarget()
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
	const float maxPower = attackPower * powerMod * GetHealthScale() * (hadTarget ? 1.f / 0.75f : 1.f);
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
		// Same commitment the attack squads now get. This picks weakest-and-
		// nearest off the CURRENT geometry every pass, so a raid party changed
		// its mind as it moved and ended up oscillating between two structures
		// instead of killing either. Flattering the incumbent's distance keeps
		// it committed unless something is genuinely closer.
		// apexearth: "it can't make up its mind and just runs in circles."
		if (enemy == GetTarget()) {
			sqDist /= SQUARE(RAID_TARGET_STICKY);
		}
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

void CRaidTask::ApplyTargetPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (pPath->posPath.empty() && !flankDone) {
		flankDone = true;  // cannot reach the flank point; go straight rather than stall
	}
	if (!pPath->posPath.empty()) {
		// walked/direct near 1.0 is a charge up the middle; well above 1.0 is a
		// flank. Without this the route shape is invisible in a log.
		CCircuitAI* circuit = manager->GetCircuit();
		if (circuit->GetLastFrame() >= lastDetourLog + FRAMES_PER_SEC * 20) {
			lastDetourLog = circuit->GetLastFrame();
			float walked = 0.f;
			for (size_t i = 1; i < pPath->posPath.size(); ++i) {
				walked += pPath->posPath[i - 1].distance2D(pPath->posPath[i]);
			}
			const float direct = pPath->posPath.front().distance2D(pPath->posPath.back());
			if (direct > 1.f) {
				circuit->LOG("apex: raid path walked=%.0f direct=%.0f detour=%.2f",
						walked, direct, walked / direct);
			}
		}
		if (leader != nullptr) {
			CEnemyInfo* tgt = GetTarget();
			const char* tname = ((tgt != nullptr) && (tgt->GetCircuitDef() != nullptr))
					? tgt->GetCircuitDef()->GetDef()->GetName() : "spot";
			IntentPing(leader->GetLastPos(),
					utils::string_format("RAID n=%d > %s", (int)units.size(), tname));
		}
		position = pPath->posPath.back();
		ActivePath();
	} else {
		FallbackRaid();
	}
}

void CRaidTask::FallbackRaid()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const AIFloat3& threatPos = leader->GetTravelAct()->IsActive() ? position : pos;
	const char* why = "roam";
	if (attackPower * powerMod * GetHealthScale() <= threatMap->GetThreatAt(leader, threatPos)) {
		AIFloat3 nextPos = circuit->GetMilitaryManager()->GetScoutPosition(leader);
		if (utils::is_equal_pos(nextPos, pos)) {
			return;
		} else {
			position = nextPos;
			why = "outgunned";
		}
	} else {
		// Nothing in front of us is beating us, so there is no reason to be
		// heading anywhere but further in.
		const AIFloat3 onward = FindOnwardSpot();
		if (utils::is_valid(onward)) {
			if (!utils::is_equal_pos(onward, position)
				&& (circuit->GetLastFrame() >= lastPressLog + FRAMES_PER_SEC * 20))
			{
				lastPressLog = circuit->GetLastFrame();
				circuit->LOG("apex: raid presses on to (%.0f,%.0f), %.0f further in",
						onward.x, onward.z, pos.distance2D(onward));
			}
			position = onward;
			why = "press on";
		}
	}

	if (!utils::is_valid(position)) {
		position = RoamPos(leader);
	}
	IntentPing(pos, utils::string_format("RAID n=%d %s", (int)units.size(), why));

	CPathFinder* pathfinder = circuit->GetPathfinder();
	// RAID THE EDGES. This is the ROAMING query -- how a raid party moves when it
	// has no target yet -- and it passed no threatMod, so it took the default of
	// 1.0 and routed straight through the middle, into the enemy army, while the
	// TARGETED query twenty lines up has used RAID_THREAT_MOD = 4 all along. Half
	// the raid's movement avoided threat and half walked into it.
	// With RAID_ROAM_THREAT_MOD the quiet ground is cheap and the contested
	// centre is expensive, so a raid party works its way round the outside on its
	// own -- no waypoint list, no map-edge special case, just a cost function
	// that makes the flank the shortest path.
	// apexearth: "I want to see us doing cheeky moves like running the edge of
	// the map and popping enemy energy converters."
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, threatMap,
			pos, position, pathfinder->GetSquareSize(),
			nullptr, std::numeric_limits<float>::max(), false, RAID_ROAM_THREAT_MOD);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyRaidPath(static_cast<const CQueryPathSingle*>(query));
	});
}

springai::AIFloat3 CRaidTask::FindOnwardSpot() const
{
	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& foe = circuit->GetEnemyManager()->GetEnemyPos();
	if (!utils::is_valid(foe)) {
		return -RgtVector;  // nothing seen yet; no direction to press in
	}
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const float ourDist = pos.distance2D(foe);
	if (ourDist <= PRESS_STEP) {
		return -RgtVector;  // already on top of them
	}

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	threatMap->SetThreatType(leader);
	const float power = attackPower * powerMod * GetHealthScale();
	SArea* area = leader->GetArea();

	const CMetalData::Metals& spots = circuit->GetMetalManager()->GetSpots();
	AIFloat3 best = -RgtVector;
	float bestSqDist = SQUARE(PRESS_MAX_LEG);
	for (const CMetalData::SMetal& spot : spots) {
		if (foe.distance2D(spot.position) > ourDist - PRESS_STEP) {
			continue;  // no deeper than we already stand
		}
		const float sqDist = pos.SqDistance2D(spot.position);
		if (sqDist >= bestSqDist) {
			continue;
		}
		if (!terrainMgr->CanMoveToPos(area, spot.position)
			|| (threatMap->GetThreatAt(spot.position) >= power))
		{
			continue;
		}
		bestSqDist = sqDist;
		best = spot.position;
	}
	return best;
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
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		)
	}
}

} // namespace circuit
