/*
 * SquadTask.cpp
 *
 *  Created on: Jan 23, 2016
 *      Author: rlcevg
 */

#include "task/fighter/SquadTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/BuilderManager.h"
#include "module/MilitaryManager.h"
#include "unit/enemy/EnemyManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryLineMap.h"
#include "unit/action/TravelAction.h"
#include "CircuitAI.h"
#include "util/Utils.h"
#include "Log.h"

#include <cmath>
#include <vector>

namespace circuit {

using namespace springai;
using namespace terrain;

ISquadTask::ISquadTask(ITaskModule* mgr, FightType type, float powerMod)
		: IFighterTask(mgr, type, powerMod)
		, lowestRange(std::numeric_limits<float>::max())
		, highestRange(.0f)
		, lowestSpeed(std::numeric_limits<float>::max())
		, highestSpeed(.0f)
		, leader(nullptr)
		, groupPos(-RgtVector)
		, prevGroupPos(-RgtVector)
		, pPath(std::make_shared<CPathInfo>())
		, groupFrame(0)
		, attackFrame(-1)
{
}

ISquadTask::~ISquadTask()
{
}

bool ISquadTask::IsChargeDef(const CCircuitDef* cdef)
{
	return (cdef != nullptr) && cdef->IsRoleHeavy() && cdef->IsAttrMelee();
}

void ISquadTask::AssignTo(CCircuitUnit* unit)
{
	IFighterTask::AssignTo(unit);

	CCircuitDef* cdef = unit->GetCircuitDef();
	// apexearth: "focus on getting to 50% with legion". Traced via a fresh-
	// context agent's finding that Legion trades combat significantly worse
	// than Cortex/Armada despite comparable economy (K/D log-ratio t=-2.16
	// to -2.23 across two independent tournaments), and nine prior
	// composition/unit-weight fix attempts across two sessions all failing
	// to close it -- pointing at combat POSITIONING, not army composition.
	//
	// Squad rows are grouped by range so a row can stand at one shared
	// distance from the target (see Attack() below). This used to group by
	// GetMinRange() -- for a single-weapon unit that equals GetMaxRange(),
	// no difference, which is why this was invisible for Cortex/Armada's
	// mostly single-weapon rosters. But GetMinRange() is literally the
	// SHORTEST range among ALL of a unit's weapon mounts (CircuitDef.cpp:
	// minRange = std::min(minRange, range) across every mount). Legion's
	// defining trait is multi-weapon units -- legkark (Karkinos, "Medium
	// Dual-Weapon Infantry Bot") carries HEAT_RAY at range 360 and
	// LEGION_SHOTGUN at range 251 (confirmed in units/Legion/Bots/
	// legkark.lua's weapondefs). Grouped by min range, a legkark row was
	// ordered to close to ~238 elmos (251 * ATTACK_RANGE_MOD) from every
	// target -- needlessly inside its own better weapon's reach, and inside
	// any enemy with range 251-360 that it never needed to engage that
	// close. GetMaxRange() is what the outranged-safety-margin standoff
	// logic already treats as "this row's real engagement range" elsewhere
	// in this same file; grouping should agree with it.
	const float range = cdef->GetMaxRange();
	rangeUnits[range].insert(unit);

	if (leader == nullptr) {
		lowestRange  = cdef->GetMaxRange();
		highestRange = cdef->GetMaxRange();
		lowestSpeed  = cdef->GetSpeed();
		highestSpeed = cdef->GetSpeed();
		leader = unit;
	} else {
		lowestRange  = std::min(lowestRange,  cdef->GetMaxRange());
		highestRange = std::max(highestRange, cdef->GetMaxRange());
		lowestSpeed  = std::min(lowestSpeed,  cdef->GetSpeed());
		highestSpeed = std::max(highestSpeed, cdef->GetSpeed());
		if (cdef->IsRoleSupport()) {
			return;
		}
		if ((leader->GetArea() == nullptr) ||
			leader->GetCircuitDef()->IsRoleSupport() ||
			((unit->GetArea() != nullptr) && (unit->GetArea()->percentOfMap < leader->GetArea()->percentOfMap)))
		{
			leader = unit;
		}
	}
}

void ISquadTask::RemoveAssignee(CCircuitUnit* unit)
{
	IFighterTask::RemoveAssignee(unit);

	CCircuitDef* cdef = unit->GetCircuitDef();
	const float range = cdef->GetMaxRange();  // must match AssignTo's key
	std::set<CCircuitUnit*>& setUnits = rangeUnits[range];
	setUnits.erase(unit);
	if (setUnits.empty()) {
		rangeUnits.erase(range);
	}

	leader = nullptr;
	lowestRange = lowestSpeed = std::numeric_limits<float>::max();
	highestRange = highestSpeed = .0f;

	if (units.empty()) {
		return;
	}

	FindLeader(units.begin(), units.end());
}

void ISquadTask::Merge(ISquadTask* task)
{
	const std::set<CCircuitUnit*>& rookies = task->GetAssignees();
	IAction::State state = leader->GetTravelAct()->GetState();
	const std::shared_ptr<CPathInfo>& lPath = leader->GetTravelAct()->GetPath();
	for (CCircuitUnit* unit : rookies) {
		unit->SetTask(this);
		if (unit->GetCircuitDef()->IsRoleSupport()) {
			continue;
		}
		unit->GetTravelAct()->SetPath(lPath);
		unit->GetTravelAct()->SetState(state);
	}
	units.insert(rookies.begin(), rookies.end());
	attackPower += task->GetAttackPower();
	const std::set<CCircuitUnit*>& sh = task->GetShields();
	shields.insert(sh.begin(), sh.end());

	const std::map<float, std::set<CCircuitUnit*>>& rangers = task->GetRangeUnits();
	for (const auto& kv : rangers) {
		rangeUnits[kv.first].insert(kv.second.begin(), kv.second.end());
	}

	FindLeader(rookies.begin(), rookies.end());
}

const AIFloat3& ISquadTask::GetLeaderPos(int frame) const
{
	return (leader != nullptr) ? leader->GetPos(frame) : GetPosition();
}

void ISquadTask::FindLeader(decltype(units)::iterator itBegin, decltype(units)::iterator itEnd)
{
	if (leader == nullptr) {
		for (; itBegin != itEnd; ++itBegin) {
			CCircuitUnit* ass = *itBegin;
			lowestRange  = std::min(lowestRange,  ass->GetCircuitDef()->GetMaxRange());
			highestRange = std::max(highestRange, ass->GetCircuitDef()->GetMaxRange());
			lowestSpeed  = std::min(lowestSpeed,  ass->GetCircuitDef()->GetSpeed());
			highestSpeed = std::max(highestSpeed, ass->GetCircuitDef()->GetSpeed());
			if (!ass->GetCircuitDef()->IsRoleSupport()) {
				leader = ass;
				++itBegin;
				break;
			}
		}
	}
	for (; itBegin != itEnd; ++itBegin) {
		CCircuitUnit* ass = *itBegin;
		lowestRange  = std::min(lowestRange,  ass->GetCircuitDef()->GetMaxRange());
		highestRange = std::max(highestRange, ass->GetCircuitDef()->GetMaxRange());
		lowestSpeed  = std::min(lowestSpeed,  ass->GetCircuitDef()->GetSpeed());
		highestSpeed = std::max(highestSpeed, ass->GetCircuitDef()->GetSpeed());
		if (ass->GetCircuitDef()->IsRoleSupport() || (ass->GetArea() == nullptr)) {
			continue;
		}
		if ((leader->GetArea() == nullptr) ||
			leader->GetCircuitDef()->IsRoleSupport() ||
			(ass->GetArea()->percentOfMap < leader->GetArea()->percentOfMap))
		{
			leader = ass;
		}
	}
}

bool ISquadTask::IsMergeSafe() const
{
	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	return (circuit->GetInflMap()->GetInfluenceAt(pos) > -INFL_EPS);
}

ISquadTask* ISquadTask::CheckMergeTask()
{
	const ISquadTask* task = nullptr;

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	const AIFloat3& pos = leader->GetPos(frame);
	SArea* area = leader->GetArea();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const float sqMaxDistCost = SQUARE(MAX_TRAVEL_SEC * lowestSpeed);
	float metric = std::numeric_limits<float>::max();

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<CQueryLineMap> query = std::static_pointer_cast<CQueryLineMap>(
			pathfinder->CreateLineMapQuery(leader, circuit->GetThreatMap(), pos));

	const std::set<IFighterTask*>& tasks = static_cast<CMilitaryManager*>(manager)->GetTasks(fightType);
	for (const IFighterTask* candidate : tasks) {
		if ((candidate == this)
			|| (candidate->GetAttackPower() < attackPower)
			|| !candidate->CanAssignTo(leader))
		{
			continue;
		}
		const ISquadTask* candy = static_cast<const ISquadTask*>(candidate);

		const AIFloat3& tp = candy->GetLeaderPos(frame);
		const AIFloat3& taskPos = utils::is_valid(tp) ? tp : pos;

		if (!terrainMgr->CanMoveToPos(area, taskPos)) {  // ensure that path always exists
			continue;
		}

		if (!query->IsSafeLine(pos, taskPos)) {  // ensure safe passage
			continue;
		}

		// Check time-distance to target
		float sqDistCost = pos.SqDistance2D(taskPos);
		if ((sqDistCost < metric) && (sqDistCost < sqMaxDistCost)) {
			task = candy;
			metric = sqDistCost;
		}
	}

	return const_cast<ISquadTask*>(task);
}

ISquadTask* ISquadTask::GetMergeTask()
{
	if (updCount % 32 == 1) {
		return IsMergeSafe() ? CheckMergeTask() : nullptr;
	}
	return nullptr;
}

// A slot on a curved line facing the enemy, rather than the centre point itself.
//
// Regrouping sent every unit to ONE position, which is how a squad becomes a
// ball -- and a ball is a single AOE footprint. apexearth: "units should be
// organized into curved lines against the general area of influence of the
// enemy. we don't organize into balls, we organize into curves/lines."
//
// The line runs perpendicular to enemy-influence direction, so it presents a
// front rather than a column. It bows slightly forward at the centre, which is
// what makes it a curve: the flanks trail, so the shape wraps toward the enemy
// instead of being a flat wall.
AIFloat3 ISquadTask::LinePos(CCircuitUnit* unit, const AIFloat3& centre) const
{
	if (units.size() < 2) {
		return centre;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& foe = circuit->GetEnemyManager()->GetEnemyPos();
	float fx = foe.x - centre.x;
	float fz = foe.z - centre.z;
	const float flen = sqrtf(fx * fx + fz * fz);
	if (flen < 1.f) {
		return centre;
	}
	fx /= flen;
	fz /= flen;

	// Stable slot per unit: iteration order of `units` is by pointer and does not
	// churn between updates, so a unit keeps its place instead of swapping.
	int idx = 0;
	for (CCircuitUnit* u : units) {
		if (u == unit) {
			break;
		}
		++idx;
	}
	const int n = int(units.size());
	const float off = (float(idx) - float(n - 1) * 0.5f) * LINE_SPACING;

	// Perpendicular to the enemy direction.
	AIFloat3 pos = centre;
	pos.x += -fz * off;
	pos.z +=  fx * off;
	// Bow: the centre stands forward of the flanks by up to a third of the span.
	const float half = float(n - 1) * 0.5f * LINE_SPACING;
	const float bow = (half > 1.f) ? (1.f - (off * off) / (half * half)) : 0.f;
	pos.x += fx * bow * LINE_SPACING;
	pos.z += fz * bow * LINE_SPACING;

	CTerrainManager::CorrectPosition(pos);
	return pos;
}

// Mean distance from the squad's centroid. apexearth: "take all their locations
// and calculate the overall positional radius averaged.... if they're all spread
// out then you do NOT have a strong fighting force."
float ISquadTask::GetSpreadRadius() const
{
	if (units.empty()) {
		return .0f;
	}
	const float count = float(units.size());
	AIFloat3 centroid = ZeroVector;
	for (CCircuitUnit* unit : units) {
		centroid += unit->GetLastPos();
	}
	centroid /= count;

	float sum = .0f;
	for (CCircuitUnit* unit : units) {
		sum += centroid.distance2D(unit->GetLastPos());
	}
	return sum / count;
}

// Derate the squad's rated power by how strung out it is. Twenty units spanning
// the map are not twenty units in a fight -- they arrive a few at a time and are
// beaten in detail.
float ISquadTask::GetCohesionScale() const
{
	const float spread = GetSpreadRadius();
	if (spread <= COHESION_MAX_SPREAD) {
		return 1.f;
	}
	return std::max(COHESION_MIN_SCALE, COHESION_MAX_SPREAD / spread);
}

bool ISquadTask::IsMustRegroup()
{
	if ((State::ENGAGE == state) || (updCount % 16 != 15)) {
		return false;
	}

	// apex: ground squads may now regroup outside friendly influence. Refusing
	// to re-cohere in contested ground is what makes them arrive piecemeal.
	if (!leader->GetCircuitDef()->IsAbleToFly() ? false : !IsMergeSafe()) {
		state = State::ROAM;
		return false;
	}

	static std::vector<CCircuitUnit*> validUnits;  // NOTE: micro-opt
//	validUnits.reserve(units.size());
	CCircuitAI* circuit = manager->GetCircuit();
	CThreatMap* threatMap = circuit->GetThreatMap();
	threatMap->SetThreatType(leader);
	const int frame = circuit->GetLastFrame();
	const AIFloat3& leadPos = leader->GetPos(frame);
	CCircuitUnit* bestPlace = leader;
	float minSqDist = std::numeric_limits<float>::max();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();;
	for (CCircuitUnit* unit : units) {
		const AIFloat3& unitPos = unit->GetPos(frame);
		if (!unit->GetCircuitDef()->IsPlane() &&
			terrainMgr->CanMoveToPos(unit->GetArea(), unitPos))
		{
			validUnits.push_back(unit);
			if ((State::REGROUP == state) || (threatMap->GetThreatAt(leadPos) >= THREAT_MIN)) {
				continue;
			}
			const float sqDist = unitPos.SqDistance2D(leadPos);
			if (minSqDist > sqDist) {
				minSqDist = sqDist;
				bestPlace = unit;
			}
		}
	}
	if (validUnits.empty()) {
		state = State::ROAM;
		return false;
	}

	if (State::REGROUP != state) {
		groupPos = bestPlace->GetLastPos();
		groupFrame = frame;
	} else if (frame >= groupFrame + FRAMES_PER_SEC * 60) {
		// eliminate buggy units
		const float sqMaxDist = SQUARE(std::max<float>(SQUARE_SIZE * 8 * validUnits.size(), highestRange));
		for (CCircuitUnit* unit : units) {
			if (unit->GetCircuitDef()->IsPlane()) {
				continue;
			}
			const AIFloat3& pos = unit->GetLastPos();
			const float sqDist = groupPos.SqDistance2D(pos);
			if ((sqDist > sqMaxDist) &&
				((unit->GetTaskFrame() < groupFrame) || !terrainMgr->CanMoveToPos(unit->GetArea(), pos)))
			{
				TRY_UNIT(circuit, unit,
					unit->CmdStop();
					unit->CmdSetMoveState(CCircuitDef::MoveType::ROAM);
				)
				circuit->Garbage(unit, "stuck");
//				circuit->GetBuilderManager()->EnqueueTask(TaskB::Reclaim(IBuilderTask::Priority::HIGH, unit));
			}
		}

		validUnits.clear();
		state = State::ROAM;
		return false;
	}

	// Back to upstream THREAT_MIN. Widening this to 8x for ground let the block
	// below run while the squad was in contact, and that block ends in
	// Garbage(leader), which routes to UnitDestroyed + UnregisterTeamUnit: the AI
	// drops a LIVE unit from its own records and never orders it again.
	if (threatMap->GetThreatAt(groupPos) >= THREAT_MIN) {
		validUnits.clear();
		state = State::ROAM;
		return false;
	}

	bool wasRegroup = (State::REGROUP == state);
	state = State::ROAM;

	// Back to upstream's count-scaled spread. Capping it at an absolute 700 while
	// CanAssignTo admits units up to ASSIGN_RADIUS 3000 apart made REGROUP the
	// squad's normal state: it could not satisfy cohesion it was assembled to
	// violate, so it gathered instead of fighting, and fed the block below.
	const float spread = SQUARE_SIZE * 8 * validUnits.size();
	const float sqMaxDist = SQUARE(std::max<float>(spread, highestRange));
	for (CCircuitUnit* unit : validUnits) {
		const float sqDist = groupPos.SqDistance2D(unit->GetLastPos());
		if (sqDist > sqMaxDist) {
			state = State::REGROUP;
			break;
		}
	}

	if (!wasRegroup && (State::REGROUP == state)) {
		if (utils::is_equal_pos(prevGroupPos, groupPos)) {
			TRY_UNIT(circuit, leader,
				leader->CmdStop();
				leader->CmdSetMoveState(CCircuitDef::MoveType::ROAM);
			)
			circuit->Garbage(leader, "stuck");
//			circuit->GetBuilderManager()->EnqueueTask(TaskB::Reclaim(IBuilderTask::Priority::HIGH, leader));
		}
		prevGroupPos = groupPos;
	}

	validUnits.clear();
	return State::REGROUP == state;
}

void ISquadTask::ActivePath(float speed)
{
	// TRAVEL LINE-ABREAST, not single file. Every unit gets the same path, so
	// without a per-unit offset the squad walks onto one point and meets contact
	// as a column with only the leaders able to fire. Spread them perpendicular
	// to the path instead: the squad arrives as a wall, every gun bearing, and a
	// wall is also what stops raiders leaking between units.
	// apexearth: "they should really be forming a wall against the enemy so when
	// the enemy comes in to attack we have that 'wall of fire' coming out of all
	// our nicely positioned units... also it helps to block enemy 'leaks'."
	//
	// Centred on the path, so the squad's centre of mass still follows the route
	// the pathfinder chose and nothing about target or route selection changes.
	// Width is bounded: a line wider than this stops being one fight.
	//
	// The gap is per-NEIGHBOUR-PAIR, not one width shared out, because a charger
	// needs CHARGE_SPACING from whatever stands next to it while the ordinary
	// units either side of it stay at SQUAD_FILE_SPACING. Sharing one uniform
	// step would either pack the chargers into one D-gun line or blow the whole
	// squad apart to keep them separated.
	const int n = int(units.size());
	std::vector<float> offset;
	offset.reserve(n);
	float span = 0.f;
	float cap = SQUAD_FILE_MAX_WIDTH;
	const CCircuitDef* prevDef = nullptr;
	for (CCircuitUnit* unit : units) {
		const CCircuitDef* cdef = unit->GetCircuitDef();
		const bool isCharge = IsChargeDef(cdef);
		if (prevDef != nullptr) {
			span += (isCharge || IsChargeDef(prevDef)) ? CHARGE_SPACING : SQUAD_FILE_SPACING;
		}
		if (isCharge) {
			// A charger squad is allowed to be wider than one fight: its units
			// each survive alone, which is the whole reason to separate them.
			cap = std::max(cap, CHARGE_SPACING * float(n));
		}
		offset.push_back(span);
		prevDef = cdef;
	}
	const float scale = (span > cap) ? (cap / span) : 1.f;
	const float half = span * scale * 0.5f;
	int i = 0;
	for (CCircuitUnit* unit : units) {
		unit->GetTravelAct()->SetPath(pPath, speed);
		unit->GetTravelAct()->SetLateral((n > 1) ? (offset[i] * scale - half) : 0.f);
		++i;
	}
}

NSMicroPather::HitFunc ISquadTask::GetHitTest() const
{
	CTerrainManager* terrainMgr = manager->GetCircuit()->GetTerrainManager();
	const std::vector<SSector>& sectors = terrainMgr->GetAreaData()->sector;
	const int sectorXSize = terrainMgr->GetSectorXSize();
	const int convert = terrainMgr->GetConvertStoP();
	const float aimLift = leader->GetCircuitDef()->GetHeight() * 0.5f;  // TODO: Use aim-pos of attacker and enemy
	const float maxHeight = leader->GetCircuitDef()->GetMaxRange() * 0.4f;
	return [&sectors, sectorXSize, aimLift, maxHeight, convert](int2 start, int2 end) {  // losTest
		const float startHeight = sectors[start.y * sectorXSize + start.x].maxElevation + aimLift;
		const float diffHeight = sectors[end.y * sectorXSize + end.x].maxElevation + SQUARE_SIZE - startHeight;
		// check vertical angle
		const float absDiffHeight = std::fabs(diffHeight);
		if (absDiffHeight > maxHeight) {
			const float dirX = (end.x - start.x) * convert;
			const float dirY = (end.y - start.y) * convert;
			const float len = std::sqrt(SQUARE(dirX) + SQUARE(dirY) + SQUARE(absDiffHeight));
			if (absDiffHeight > SQRT_3_2 * len) {  // cos(a) > sqrt(3)/2; a < 30 deg
				return false;
			}
		}
		// All octant line draw
		const int dx =  abs(end.x - start.x), sx = start.x < end.x ? 1 : -1;
		const int dy = -abs(end.y - start.y), sy = start.y < end.y ? 1 : -1;
		int err = dx + dy;  // error value e_xy
		for (int x = start.x, y = start.y;;) {
			const int e2 = 2 * err;
			if (e2 >= dy) {  // e_xy + e_x > 0
				if (x == end.x) break;
				err += dy; x += sx;
			}
			if (e2 <= dx) {  // e_xy + e_y < 0
				if (y == end.y) break;
				err += dx; y += sy;
			}

			const float t = std::fabs((dx > -dy) ? float(x - start.x) / dx : float(y - start.y) / dy);
			if (sectors[y * sectorXSize + x].maxElevation > diffHeight * t + startHeight) {
				return false;
			}
		}
		return true;
	};
}

void ISquadTask::Attack(const int frame)
{
	Attack(frame, GetTarget()->GetUnit()->IsCloaked());
}

void ISquadTask::Attack(const int frame, const bool isGround)
{
	const AIFloat3& tPos = GetTarget()->GetPos();
	// apexearth: "keeping our units close to their maximum range against
	// enemies, and to almost always stay moving. standing still leads to
	// death much quicker." Previously 3s: a squad reaches its computed
	// standoff position (below) and then holds it -- moving only when the
	// target's tile/range bucket changes -- for up to 3 full seconds even
	// though the target is very likely drifting the whole time. Shortened
	// to 1s so position re-evaluates roughly 3x more often, without going
	// so low it fights the engine's own per-frame unit AI or spams orders.
	const bool isRepeatAttack = (frame >= attackFrame + FRAMES_PER_SEC * 1);
	attackFrame = isRepeatAttack ? frame : attackFrame;

	// One direction per task, derived from its identity rather than randomly, so
	// it is stable across passes and two neighbouring squads do not orbit the
	// same way into each other.
	const float orbitDir = ((reinterpret_cast<uintptr_t>(this) >> 4) & 1u) ? 1.f : -1.f;

	auto it = rangeUnits.begin()->second.begin();
	std::advance(it, rangeUnits.begin()->second.size() / 2);  // TODO: Optimize
	AIFloat3 dir = (*it)->GetPos(frame) - tPos;

	if (leader->GetCircuitDef()->IsPlane() || (std::fabs(dir.y) > leader->GetCircuitDef()->GetMaxRange() * 0.5f)) {
		if (isRepeatAttack) {
			for (CCircuitUnit* unit : units) {
				if (unit->Blocker() != nullptr) {
					continue;  // Do not interrupt current action
				}
				unit->GetTravelAct()->StateWait();

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
		// Each row stands at ITS OWN weapon range. RANGE_MOD 0.8 walked every row
		// 20% inside its reach, which throws away the whole point of keeping the
		// long-ranged units in an outer row -- a Banisher at 800 was standing at
		// 640, inside the tanks it was supposed to shoot over.
		//
		// apexearth: "some units easily die on the first hit... if enemies are
		// within 900 [of my 1000 range] i absolutely have to move away from
		// them... if i am just 10% out of range of that enemy unit, i absolutely
		// must move away from them." When the CURRENT TARGET outranges this row's
		// own weapon (edef->GetMaxRange() > kv.first), standing at our own range
		// puts us inside theirs -- exactly backwards, we would be standing still
		// getting hit while unable to answer. Stand at their range plus a safety
		// margin instead, so we are never inside a reach we cannot match.
		//
		// EXCEPT indirect fire. apexearth: "some enemies are indirect fire --
		// like rocket launcher units. We can be within range of those as long as
		// we keep moving and avoid wherever their missile is going... Arbiters
		// [corhrk, role="artillery" -> IsRoleArty()] have very long range but are
		// super vulnerable if you get up close." Retreating from a dodgeable,
		// close-range-weak target is backwards for the same reason standing
		// still inside a direct-fire weapon's range is -- so arty targets keep
		// the normal own-range standoff instead of backing off to theirs.
		// Restored: bisection (armada-bisect-outrange-revert-8) crashed the
		// native DLL in all 8 games at ~1.2 minutes, but that batch also
		// carried a real bug in the jammer-veto AngelScript path (called
		// GetBuildPos() on a non-BUILDER task, same crash signature) that was
		// new in that same deploy and this change was not. The prior 0-8 read
		// (armada-unitdistance-check-8) that prompted the bisection ran to
		// completion with no crash -- a real loss, but indistinguishable from
		// this session's established small-batch noise until re-tested clean.
		const bool isArty = (edef != nullptr) && edef->IsRoleArty();
		// apexearth, watching live: "our thug style units are afraid of
		// rocket bots because they have more range. thugs/maces are more
		// powerful than rocket bots so that's unfortunate." A rocket bot
		// (armrock/corrock) is direct-fire, not IsRoleArty(), so it was
		// getting the same kite-away treatment as a real long-range threat
		// even though a heavy assault bot standing at its own range shrugs
		// off rocket fire and wins the trade -- kiting away just throws that
		// advantage out for no reason.
		//
		// First attempt used cost as the "who wins" proxy and was wrong:
		// checked against tools/unitdef.py, corthud (Thug) is 140 metal,
		// armham (Mace) 130, armrock (Rocketeer) 120 -- all similar T1 bot
		// costs, nowhere near a dominance ratio. GetPower() is the right
		// signal instead: CCircuitDef precomputes damage*sqrt(health) per
		// def (CircuitDef.cpp), the same formula CThreatMap::GetUnitPower
		// uses for live units, and it is what the threat map itself is
		// already built from -- Thug/Mace's low range but high alpha and
		// health should score well above Rocketeer's glass-cannon poke
		// (its own description: "good vs. static defenses") on this metric
		// even though cost alone could not tell them apart.
		const bool powerDominant = (edef != nullptr) && (rowDef != nullptr)
				&& (rowDef->GetPower() > edef->GetPower() * POWER_DOMINANCE_RATIO);
		// TEMPORARY diagnostic, apexearth: "remember good diagnostics and
		// instrumentation are important!" GetPower() at the def level is
		// unverified for this exact matchup -- log both sides' power whenever
		// a row actually outranges its target, so a smoke test can confirm
		// powerDominant fires true for Thug/Mace vs Rocketeer specifically
		// before trusting the mechanism. Time-rate-limited rather than
		// call-count-capped: a 60-call cap exhausted in the first 30 seconds
		// of a 15-minute smoke test and never got another sample, so it
		// never actually saw a Thug/Mace-vs-Rocketeer pairing at all.
		static int sLastPowerDiagFrame = -1000000;
		const int diagFrame = manager->GetCircuit()->GetLastFrame();
		if ((edef != nullptr) && (rowDef != nullptr) && (edef->GetMaxRange() > kv.first)
			&& (diagFrame >= sLastPowerDiagFrame + FRAMES_PER_SEC * 5))
		{
			sLastPowerDiagFrame = diagFrame;
			manager->GetCircuit()->GetLog()->DoLog(utils::string_format(
				std::string("apex: outrange-power-diag row=%s (pwr=%.1f hp=%.0f) target=%s (pwr=%.1f hp=%.0f) dominant=%d glass=%d"),
				rowDef->GetDef()->GetName(), rowDef->GetPower(), rowDef->GetHealth(),
				edef->GetDef()->GetName(), edef->GetPower(), edef->GetHealth(),
				powerDominant, (edef->GetHealth() < rowDef->GetHealth())).c_str());
		}
		// A target that outranges us AND is more fragile than we are loses the
		// race the moment we close, so backing off to its range hands it a free
		// win -- it simply keeps shooting and we never arrive. apexearth: "we
		// stop when we are afraid of sniper-like units... we need to dive in and
		// ignore that 'stay at range' strat if we really want to commit to
		// killing/engaging them."
		//
		// Keyed on HEALTH rather than the role or the "siege" attribute, both of
		// which were checked against the configs and are wrong for this. Read
		// from the pinned tree: Sharpshooter (armsnipe, the actual sniper) has
		// 580 health against a Mace's 1000 -- fragile, dive it. But role
		// anti_heavy also covers Starlight (2800) and Arquebus (2200), and the
		// siege attribute covers Vanguard, kamikazes, ships and subs; exempting
		// either group would send squads diving into things that comfortably win
		// the close fight. Health separates them cleanly and needs no list to
		// maintain.
		const bool glassCannon = (edef != nullptr) && (rowDef != nullptr)
				&& (edef->GetHealth() < rowDef->GetHealth());
		const bool outranged = !isArty && !powerDominant && !glassCannon
				&& (edef != nullptr) && (edef->GetMaxRange() > kv.first);
		const float standoff = outranged ? (edef->GetMaxRange() * OUTRANGED_SAFETY_MARGIN) : kv.first;
		const float range = standoff * ATTACK_RANGE_MOD;
		// NOTE: 1st unit in 1st row will scout, ignoring GetTarget()->IsInRadarOrLOS()
		//       as unit may wobble back and forth without firing if turret turn is slow.
		float range0 = range;
		if ((row++ == 0) && (isStatic || !GetTarget()->IsInRadarOrLOS())) {
			range0 = std::min(kv.first, rowDef->GetLosRadius()) * ATTACK_RANGE_MOD;
		}
		// The arc a row may occupy. At 0.9*PI a squad packs into a half circle on
		// one side of the target, which is a single AOE footprint -- and the wider
		// the squad, the tighter the packing, because this is divided by the unit
		// count. apexearth: "if we had a whole bunch of tiger tanks, we would
		// surround the enemy units, form a circle... ideally... our banishers
		// would stay at a distance." Rows are already keyed by weapon range, so
		// the second half of that is done; this is the first half.
		const float maxDelta = (M_PI * ARC_SPAN) / kv.second.size();
		// NOTE: float delta = asinf(cdef->GetRadius() / range);
		//       but sin of a small angle is similar to that angle, omit asinf() call
		float delta = (3.0f * (rowDef->GetRadius() + aoe)) / (range + DIV0_SLACK);
		if (delta > maxDelta) {
			delta = maxDelta;
		}
		// A charger row gets a FLOOR on its spacing, applied after the cap so
		// the cap cannot take it back: maxDelta shrinks with the unit count, so
		// the more Behemoths arrive the tighter they were packing -- exactly
		// backwards for the one thing a commander can kill them with. Bounded so
		// the arc can close into a full ring but never wrap over itself.
		if (IsChargeDef(rowDef)) {
			const float minDelta = std::min(CHARGE_SPACING / (range + DIV0_SLACK),
					float(2.0 * M_PI) / float(kv.second.size()));
			if (delta < minDelta) {
				delta = minDelta;
			}
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
			unit->GetTravelAct()->StateWait();

			if (isRepeatAttack
				|| (unit->GetTarget() != GetTarget())
				|| (unit->GetTargetTile() != targetTile))
			{
				// KEEP MOVING. The slot is already a point on a circle of this
				// row's weapon range around the target -- but the angle came
				// only from the CURRENT bearing, so a unit walked to its slot
				// and then stood there until the target moved. Standing at the
				// right distance is still standing still.
				//
				// Precess the whole ring instead. Every unit keeps its own arc
				// slot relative to its neighbours, so the formation holds, while
				// the ring rotates slowly around the target: units strafe
				// laterally at constant range, changing heading continuously.
				// Projectiles lead their target, so a unit that never holds a
				// heading eats fewer of them -- and the standoff distance, which
				// is the point of the arc, is unchanged because rotation is
				// perpendicular to it.
				//
				// This is only useful because CmdSetTarget is now live: before
				// that a move order meant not shooting, so orbiting would have
				// traded damage for evasion. Now it is free.
				// apexearth: "our units could kinda circle around the enemies
				// they want to shoot at... staying on the move, boosting their
				// evasion when they keep changing their movement direction."
				//
				// Rate is per-task and constant, so the squad turns as one body
				// rather than scattering. The existing threat check below still
				// vetoes any step into worse ground, so this cannot orbit a unit
				// into a second enemy.
				const float orbit = ORBIT_RATE * (frame / (float)FRAMES_PER_SEC) * orbitDir;
				const float angle = alpha + beta + orbit;
				const float r = (iterNum == 0) ? range0 : range;
				AIFloat3 newPos(tPos.x + r * cosf(angle), tPos.y, tPos.z + r * sinf(angle));
				CTerrainManager::CorrectPosition(newPos);

				// apexearth: "sometimes our retreat logic takes us into new
				// threats... it specifically appears to be the logic where we
				// keep our distance from enemies we're actively fighting."
				// newPos is computed purely from THIS target's range and this
				// row's arc slot -- it never checks whether stepping there
				// walks the unit into a second enemy's range it wasn't
				// already in. Compare threat at the candidate standoff spot
				// against threat where the unit already stands; if backing
				// off would make things worse rather than better, hold
				// position (still attack-move there, at 0 distance, so the
				// engine's own turret tracking keeps firing) instead of
				// stepping into the hotter spot. Small multiplicative
				// tolerance so a unit doesn't flip-flop between two tiles of
				// near-identical threat every isRepeatAttack tick.
				CThreatMap* threatMap = manager->GetCircuit()->GetThreatMap();
				const AIFloat3& curPos = unit->GetPos(frame);
				if (threatMap->GetThreatAt(unit, newPos) > threatMap->GetThreatAt(unit, curPos) * 1.5f) {
					newPos = curPos;
				}

				unit->Attack(newPos, GetTarget(), targetTile, isGround, isStatic, frame + FRAMES_PER_SEC * 60);
			}

			beta += delta;
			++iterNum;
		}
	}
}

#ifdef DEBUG_VIS
void ISquadTask::Log()
{
	IFighterTask::Log();

	CCircuitAI* circuit = manager->GetCircuit();
	circuit->LOG("pPath: %i | size: %i | TravelAct: %i", pPath.get(), pPath ? pPath->posPath.size() : 0,
			leader->GetTravelAct()->GetState());
	if (leader != nullptr) {
		circuit->GetDrawer()->AddPoint(leader->GetPos(circuit->GetLastFrame()), leader->GetCircuitDef()->GetDef()->GetName());
	}
}
#endif

} // namespace circuit
