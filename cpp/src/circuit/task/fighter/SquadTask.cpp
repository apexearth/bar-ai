/*
 * SquadTask.cpp
 *
 *  Created on: Jan 23, 2016
 *      Author: rlcevg
 */

#include "task/fighter/SquadTask.h"
#include "task/RetreatTask.h"
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
		, pPath(std::shared_ptr<CPathInfo>(new CPathInfo()))
		, groupFrame(0)
		, attackFrame(-1)
{
}

ISquadTask::~ISquadTask()
{
}

bool ISquadTask::IsChargeDef(const CCircuitDef* cdef)
{
	return (cdef != nullptr) && cdef->IsCharger();
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
	// ordered to close to ~238 elmos (251 * STANDOFF_RANGE_MOD) from every
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
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetPath(lPath);
		}
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetState(state);
		}
	}
	units.insert(rookies.begin(), rookies.end());
	attackPower += task->GetAttackPower();
	const std::set<CCircuitUnit*>& sh = task->GetShields();
	shields.insert(sh.begin(), sh.end());
	// Coward (wounded, standing rear) state was dropped on every merge -- the
	// TODO above AttackTask's merge path acknowledged it. Same hierarchy, so
	// the protected set is reachable directly.
	cowards.insert(task->cowards.begin(), task->cowards.end());

	const std::map<float, std::set<CCircuitUnit*>>& rangers = task->GetRangeUnits();
	for (const auto& kv : rangers) {
		rangeUnits[kv.first].insert(kv.second.begin(), kv.second.end());
	}

	FindLeader(rookies.begin(), rookies.end());
}

// The collective disengage. Measured (tools/deaths.py, four games 2026-08-16):
// 40-45% of all lost metal died on solo RETREAT tasks, each unit peeling off
// alone at its health bar and run down mid-map -- while CRetreatTask's own
// line-spread logic sat dead because EnqueueRetreat news a one-unit task per
// caller. When the squad's wounded (coward) power crosses apex_squad_retreat
// of its total, everyone leaves TOGETHER on ONE retreat task: group pathing,
// the line-spread finally live, no lone stragglers donating metal.
bool ISquadTask::TrySquadRetreat(CCircuitUnit* unit)
{
	if ((unit == nullptr) || (units.size() < 2) || (attackPower <= 1.f)) {
		return false;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	// AT HOME THERE IS NOWHERE TO RUN: a squad voting to retreat inside its
	// own base is run down among its own buildings -- measured (Altored 4v4):
	// 871 units, 40% of lost metal, dying on RETREAT at fwd 0.18 with
	// fight-task deaths near zero. On our own ground the wounded stand rear
	// with the squad and the squad fights; same influence test as the attack
	// odds waiver. Defending is the one trade at home that favors us.
	// GetAllyDefendInflAt, NOT GetAllyInflAt: ally influence counts our own
	// mobile army, so a squad always stood on its own influence and this
	// branch read "home" EVERYWHERE -- measured homeStand=3843 against
	// squadVote=0 in one game; the vote below was unreachable. Defend
	// influence is written only by our BUILDINGS, the real "at home".
	if ((leader != nullptr) && (circuit->GetInflMap()->GetAllyDefendInflAt(
			leader->GetPos(circuit->GetLastFrame())) > INFL_EPS)) {
		cowards.insert(unit);
		NoteHomeStand(circuit);
		return true;
	}
	float woundedPower = unit->GetCircuitDef()->GetPower();
	for (CCircuitUnit* u : cowards) {
		if ((u != unit) && (u->GetCircuitDef() != nullptr)) {
			woundedPower += u->GetCircuitDef()->GetPower();
		}
	}
	const float frac = circuit->GetTunable("apex_squad_retreat", 0.35f);
	if (woundedPower < attackPower * frac) {
		cowards.insert(unit);  // stands rear (COWARD_REAR_MOD) until the vote passes
		NoteSquadStand(circuit);
		return true;  // handled: stay with the squad rather than run alone
	}
	CRetreatTask* task = manager->EnqueueRetreat();
	if (task == nullptr) {
		return false;
	}
	NoteSquadVote(circuit);
	circuit->LOG("apex: squad retreat units=%d wounded=%.0f/%.0f",
			(int)units.size(), woundedPower, attackPower);
	decltype(units) tmpUnits = units;
	for (CCircuitUnit* u : tmpUnits) {
		manager->AssignTask(u, task);
	}
	return true;
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

	// A garrison anchored to one breach must not merge back into one anchored to
	// another -- CMilitaryManager::UpdateDefenceTasks gives each DEFEND pool the
	// worst breach still unanswered, and a merge undoes that split immediately.
	// Same radius the loss spots themselves are merged at, so "a different spot"
	// means the same thing on both sides.
	const bool isSplitAnchor = (fightType == FightType::DEFEND) && utils::is_valid(position);
	const float anchorRadius = isSplitAnchor ? circuit->GetTunable("apex_hot_radius", 1000.f) : .0f;

	const std::set<IFighterTask*>& tasks = static_cast<CMilitaryManager*>(manager)->GetTasks(fightType);
	for (const IFighterTask* candidate : tasks) {
		if ((candidate == this)
			|| (candidate->GetAttackPower() < attackPower)
			|| !candidate->CanAssignTo(leader))
		{
			continue;
		}
		if (isSplitAnchor && utils::is_valid(candidate->GetPosition())
			&& (position.distance2D(candidate->GetPosition()) > anchorRadius))
		{
			continue;
		}
		const ISquadTask* candy = static_cast<const ISquadTask*>(candidate);

		const AIFloat3& tp = candy->GetLeaderPos(frame);
		const AIFloat3& taskPos = utils::is_valid(tp) ? tp : pos;

		if (!terrainMgr->CanMoveToPos(area, taskPos)) {  // ensure that path always exists
			continue;
		}

		// apex: passage tolerance scales with the COMBINED squad -- the whole
		// point of merging is that together they can walk ground neither dares
		// alone. THREAT_MIN (any-threat-refuses) kept 1-2 unit squads separate
		// on every contested map; see QueryLineMap::IsSafeLine.
		const float mergeThreat = std::max(THREAT_MIN,
				(attackPower + candidate->GetAttackPower())
						* circuit->GetTunable("apex_merge_threat", 0.5f));
		if (!query->IsSafeLine(pos, taskPos, mergeThreat)) {  // ensure safe passage
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
	// A squad that just refused a target it nearly qualified for hunts a
	// partner at 4x the normal cadence instead of wandering for another
	// half-minute -- the near-miss fix picked by the bestRef distribution.
	const bool nearMiss = (lastRefused >= manager->GetCircuit()
			->GetTunable("apex_nearmiss_merge", 0.7f)) && (updCount % 8 == 5);
	// apex: every 8th update, not every 32nd -- at 32 a small squad crossed
	// half the map between merge attempts, and stayed small for the fight
	// that killed it. Tunable so the cadence can be measured, not argued.
	const int every = std::max(2, (int)manager->GetCircuit()
			->GetTunable("apex_merge_every", 8.f));
	if ((updCount % every == 1) || nearMiss) {
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
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetPath(pPath, speed);
		}
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetLateral((n > 1) ? (offset[i] * scale - half) : 0.f);
		}
		++i;
	}
}

float ISquadTask::GetHealthScale() const
{
	float total = .0f;
	float alive = .0f;
	for (CCircuitUnit* unit : units) {
		const float power = unit->GetCircuitDef()->GetPower();
		total += power;
		// apexearth: "A retreating unit should have 0 power. It is no longer
		// fighting." A coward stands rear by design; whatever HP it keeps, it
		// contributes nothing to the fight being sized.
		if (cowards.find(unit) != cowards.end()) {
			continue;
		}
		float hp = unit->GetHealthPercent();
		hp = std::max(.0f, std::min(1.f, hp));  // capture progress drives it negative
		alive += power * hp;
	}
	return (total > .0f) ? (alive / total) : 1.f;
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
				if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
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

	const float rangeMod = manager->GetCircuit()->GetTunable("apex_range_mod", STANDOFF_RANGE_MOD);
	const bool losStandoff = manager->GetCircuit()->GetTunable("apex_los_standoff", 1.f) > 0.f;

	// apexearth: "certain lower hp units have to be way more careful than
	// high hp units." Baseline is THIS squad's own average health, not a
	// global constant -- whatever mix of units is actually fighting together
	// sets its own reference point, so a Hound reads as fragile next to
	// Mammoths without a per-unit-type special case, and the same code path
	// covers any low-HP def on any faction.
	float squadHealthSum = 0.f;
	float squadPowerSum = 0.f;
	int squadUnitCount = 0;
	for (const auto& kv : rangeUnits) {
		CCircuitDef* def = (*kv.second.begin())->GetCircuitDef();
		if (def != nullptr) {
			squadHealthSum += def->GetHealth() * kv.second.size();
			squadPowerSum += def->GetPower() * kv.second.size();
			squadUnitCount += (int)kv.second.size();
		}
	}
	// apexearth, watching live: a raider squad of Pawns hovered at "110%" of a
	// tower's range -- unable to shoot, trickle-dying to pathing jitter -- when
	// they could easily overwhelm it. A STATIC cannot chase, so standing at its
	// range is never useful: either the squad wins the dive and must commit, or
	// the target should not be pressed from here at all. The per-row
	// powerDominant test cannot see this: one Pawn loses the trade, eight win
	// it, so the test is squad AGGREGATE power against the target.
	CCircuitDef* atkDef = (GetTarget() != nullptr) ? GetTarget()->GetCircuitDef() : nullptr;
	// Against the LOCAL threat at the target, not the lone target's power: the
	// ground a static stands on is covered by everything beside it, and reading
	// only the target made a squad "overwhelm" one tower in a row of five and
	// dive through the rest -- apexearth, after 41% of lost metal died in
	// attack tasks at 0.72 forward: "We have some false belief that we are
	// overwhelming something that is superior." GetThreatAt sums every armed
	// enemy covering the spot, on the same power scale as GetPower().
	bool squadOverwhelms = false;
	if ((atkDef != nullptr) && !atkDef->IsMobile() && (leader != nullptr)) {
		const float localThreat = manager->GetCircuit()->GetThreatMap()
				->GetThreatAt(leader, GetTarget()->GetPos());
		squadOverwhelms = squadPowerSum > std::max(localThreat, atkDef->GetPower())
				* manager->GetCircuit()->GetTunable("apex_static_commit", POWER_DOMINANCE_RATIO);
	}
	const float avgSquadHealth = (squadUnitCount > 0) ? (squadHealthSum / squadUnitCount) : 1.f;
	const float fragileCap = manager->GetCircuit()->GetTunable("apex_fragile_cap", FRAGILE_CAP);
	const float fragileScale = manager->GetCircuit()->GetTunable("apex_fragile_standoff_scale", FRAGILE_STANDOFF_SCALE);

	int row = 0;
	for (const auto& kv : rangeUnits) {
		CCircuitDef* rowDef = (*kv.second.begin())->GetCircuitDef();
		// >1 only when this row is below the squad's own average health;
		// clamped at 1 so an above-average (tankier) row is never given LESS
		// caution than the flat baseline -- this only ever adds standoff, it
		// never removes it.
		const float fragility = (rowDef != nullptr)
				? std::min(std::max(avgSquadHealth / std::max(rowDef->GetHealth(), 1.f), 1.f), fragileCap)
				: 1.f;
		// Each row stands at ITS OWN weapon range. A fraction of 0.8 walked every row
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
		const bool outranged = !isArty && !powerDominant && !glassCannon && !squadOverwhelms
				&& (edef != nullptr) && (edef->GetMaxRange() > kv.first);
		const float standoff = outranged ? (edef->GetMaxRange() * OUTRANGED_SAFETY_MARGIN) : kv.first;
		// A fragile row (below the squad's own average health) stands further
		// out on top of the normal 90% margin -- e.g. fragility==2 (half the
		// squad's average HP) at the default scale adds 25% more standoff.
		float range = standoff * rangeMod * (1.f + (fragility - 1.f) * fragileScale);
		// apexearth, watching, same night as the LOS-static fix: "I see rocket
		// bots walk into turrets and die too... hounds still make this
		// mistake" -- reported AFTER that fix was live, so this is a second,
		// distinct cause. When `!outranged` (our row's raw range >= the
		// target's), standoff is OUR OWN range with no reference to theirs, and
		// rangeMod then shrinks it by 10% unconditionally. A target whose range
		// sits within that 10% band -- corhlt 620 vs Hound's 650, 650*0.9=585 --
		// reads as "outranged=false" (we do out-range it) yet the shrunk
		// standoff (585) lands INSIDE its 620 reach. Floor at the target's own
		// range only in this genuinely-outranging branch; the intentional dives
		// (isArty/powerDominant/glassCannon, which route standoff through
		// kv.first for the opposite reason -- closing on purpose) are
		// unaffected because none of those leave `weOutrange` true without also
		// being a real range edge.
		const bool weOutrange = !outranged && (edef != nullptr) && (edef->GetMaxRange() <= kv.first)
				&& !isArty && !powerDominant && !glassCannon;
		if (weOutrange) {
			range = std::max(range, edef->GetMaxRange() * OUTRANGED_SAFETY_MARGIN);
		}
		// NOTE: 1st unit in 1st row will scout, ignoring GetTarget()->IsInRadarOrLOS()
		//       as unit may wobble back and forth without firing if turret turn is slow.
		// Floored at `range`. apexearth, watching Hounds (650 weapon range,
		// 400 sight -- see the 2026-08-09 EyesForTheGuns note): "I see our
		// hound units running much too deep into enemy territory while
		// fighting enemies from too close up." min(kv.first, losRadius) is
		// exactly sight radius whenever sight is the smaller of the two --
		// true by construction for any unit this scouting behaviour was
		// meant to matter for -- so the scout used to walk in to 400 on a
		// 650-range gun, well inside the safe standoff. The mobile-radar
		// escort (EyesForTheGuns) is the intended fix for a blind gun now;
		// this block should never send the gun itself in closer than the
		// standoff it would otherwise hold. For any row whose sight already
		// reaches past its own standoff distance, min(...)*rangeMod already
		// equals `range`, so the max() below is a no-op there.
		float range0 = range;
		if ((row++ == 0) && losStandoff && (isStatic || !GetTarget()->IsInRadarOrLOS())) {
			range0 = std::max(range, std::min(kv.first, rowDef->GetLosRadius()) * rangeMod);
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
		// A ring end around a target near the map border lands off-map, and
		// GetThreatAt indexes the threat array UNCHECKED (its bounds assert is
		// compiled out in release) -- crashed a live watched game 2026-08-15
		// (frame ~0x, AV in CThreatMap::GetThreatAt from this exact call).
		// Same clamp the per-unit standoff path below already applies.
		CTerrainManager::CorrectPosition(newPos1);
		CTerrainManager::CorrectPosition(newPos2);
		CCircuitUnit* testUnit = *kv.second.begin();
		const AIFloat3 testPos = testUnit->GetPos(frame);
		// apexearth: "we should try to choose safer angles." The two ring ends
		// are geometrically equivalent (same range, mirrored arc); which one this
		// row actually walks toward used to be picked on distance alone -- purely
		// "which side is less travel," with no regard for what is on that side.
		// Reuses the same GetThreatAt this function already calls per-unit below
		// for the standoff veto, just sampled once per row on the two candidate
		// ends instead of the one position a unit is already walking to. Distance
		// stays the tiebreak when neither side is meaningfully more dangerous, so
		// a squad does not zigzag between two near-identical tiles.
		CThreatMap* angleThreatMap = manager->GetCircuit()->GetThreatMap();
		const float threat1 = angleThreatMap->GetThreatAt(testUnit, newPos1);
		const float threat2 = angleThreatMap->GetThreatAt(testUnit, newPos2);
		// A fragile row needs a smaller threat gap to prefer the safer side --
		// same 10% baseline, tightened by the row's own fragility so a Hound
		// picks the safer angle more decisively than a Mammoth on the same pair
		// of candidate spots.
		const float threatSpread = std::max(threat1, threat2) * (0.1f / fragility);
		const bool flipForSafety = (std::fabs(threat1 - threat2) > threatSpread) && (threat2 < threat1);
		const bool flipForDistance = (std::fabs(threat1 - threat2) <= threatSpread)
				&& (testPos.SqDistance2D(newPos1) > testPos.SqDistance2D(newPos2));
		if (flipForSafety || flipForDistance) {
			delta = -delta;
			beta = -beta;
		}

		// apex: KITING. The ring above is anchored to the current TARGET only --
		// nothing here reacted when a DIFFERENT enemy closed on the row, and with
		// the fragility pushback defaulted off a rocketbot row stood still trading
		// into a shrinking gap ("rocketbots stand still firing... without trying
		// to keep their distance"). If the nearest armed enemy group has closed
		// well inside this row's own standoff, each unit's slot moves away from
		// that enemy to re-open the gap. Charge/melee rows and short-ranged rows
		// keep closing -- kiting is a long-gun move -- and a squad committed to
		// overwhelming a static does not back off mid-dive.
		AIFloat3 kiteFoe = -RgtVector;
		float kiteFoeRange = 0.f;
		// 250, was 400: the 400 floor excluded every mid-range riot/skirm row
		// (~300 range) from kiting entirely -- apexearth 2026-08-19: "us walk
		// up close with units like thugs and maces, and they just get
		// absolutely creamed." Melee/charge rows are already excluded by role.
		const float kiteMin = manager->GetCircuit()->GetTunable("apex_kite_min_range", 250.f);
		const float kiteFrac = manager->GetCircuit()->GetTunable("apex_kite_frac", 0.7f);
		if ((kiteFrac > 0.f) && (kv.first >= kiteMin)
			&& !IsChargeDef(rowDef) && !squadOverwhelms)
		{
			// Individual armed enemies, NOT group centroids -- but never a
			// walk of the whole enemy registry: ghosts of units killed out
			// of LOS are never unregistered, so that map grows with game AGE
			// and a per-row full scan compounded into the worst-frame spikes
			// apexearth reported ("performance continuously gets worse";
			// spikeMs 5 -> 78 over 28 minutes with unit count flat). Coarse
			// pass over the bounded cluster list finds the one nearby group;
			// the per-unit pass runs only inside it. A Behemoth beside the
			// row is in whatever cluster is nearest, so the original blind
			// spot (centroid far, unit close) stays covered at cluster cost.
			float bestSq = SQUARE(kv.first);
			CCircuitAI* kc = manager->GetCircuit();
			const CEnemyManager::SEnemyGroup* nearGroup = nullptr;
			float bestGroupSq = SQUARE(kv.first * 3.f);
			for (const CEnemyManager::SEnemyGroup& g : kc->GetEnemyManager()->GetEnemyGroups()) {
				const float sq = g.pos.SqDistance2D(testPos);
				if ((g.influence > 0.f) && (sq < bestGroupSq)) {
					bestGroupSq = sq;
					nearGroup = &g;
				}
			}
			if (nearGroup != nullptr) {
				for (const ICoreUnit::Id eId : nearGroup->units) {
					CEnemyInfo* e = kc->GetEnemyInfo(eId);
					if ((e == nullptr) || e->IsHidden()) {
						continue;
					}
					CCircuitDef* ed = e->GetCircuitDef();
					if ((ed == nullptr) || !ed->IsAttacker() || ed->IsAbleToFly()) {
						continue;
					}
					const float sq = e->GetPos().SqDistance2D(testPos);
					if (sq < bestSq) {
						bestSq = sq;
						kiteFoe = e->GetPos();
						kiteFoeRange = ed->GetMaxRange();
					}
				}
			}
		}

		int iterNum = 0;
		for (CCircuitUnit* unit : kv.second) {
			if (unit->Blocker() != nullptr) {
				continue;  // Do not interrupt current action
			}
			if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
				unit->GetTravelAct()->StateWait();
			}

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
				float r = (iterNum == 0) ? range0 : range;
				// Screened, not withdrawn: a coward stands further out on the
				// same ring instead of leaving the fight, so healthier
				// squadmates on the same bearing sit between it and the
				// target. This is not the reverted "never retreat" change --
				// that forced EVERY unit to fight to the death in place; this
				// only repositions a unit that OnUnitDamaged already judged
				// safe enough not to need a full retreat.
				if (cowards.find(unit) != cowards.end()) {
					r *= manager->GetCircuit()->GetTunable("apex_coward_rear_mod", COWARD_REAR_MOD);
				}
				AIFloat3 newPos(tPos.x + r * cosf(angle), tPos.y, tPos.z + r * sinf(angle));
				CTerrainManager::CorrectPosition(newPos);
				// The kite step overrides the ring slot: distance to the closing
				// enemy is restored to this row's own standoff, along the line
				// away from it. The threat veto below still applies.
				if (utils::is_valid(kiteFoe)) {
					const AIFloat3& kcur = unit->GetPos(frame);
					const float sqFoe = kcur.SqDistance2D(kiteFoe);
					// apex: THE TRIGGER IS THEIR RANGE, NOT A FRACTION OF OURS.
					// "they need to be smart enough to back up when enemies are
					// close to getting in range to fire back" (apexearth,
					// 2026-08-19, on siege). A row backs off when the closing
					// enemy is within its own weapon range plus a pad -- and
					// re-opens to outside that reach, never closer than its own
					// standoff. The old our-range-fraction stays as the floor
					// for short-armed chasers.
					const float foeReach = kiteFoeRange
							+ manager->GetCircuit()->GetTunable("apex_kite_foe_pad", 120.f);
					// apex: SIEGE FEARS PROXIMITY. apexearth 2026-08-20: "In
					// general siege should be afraid of enemy units getting
					// too close to it." A siege row's fear radius is nearly
					// its whole weapon range (not the 70% default), it
					// reopens to FULL range, and the anti-yo-yo guard relaxes
					// to its own reach -- backing off inside one's own range
					// is always the right move for a unit that wins at arm's
					// length and dies in anyone else's.
					const bool siegeRow = (rowDef != nullptr) && rowDef->IsAttrSiege();
					const float rowFrac = siegeRow
							? manager->GetCircuit()->GetTunable("apex_siege_fear_frac", 0.9f)
							: kiteFrac;
					const float openTo = siegeRow ? kv.first : (kv.first * rangeMod);
					const float trigger = std::max(kv.first * rowFrac, foeReach);
					const bool mayKite = siegeRow
							? (foeReach < kv.first)
							: (trigger < kv.first * rangeMod);
					if ((sqFoe < SQUARE(trigger)) && mayKite) {
						AIFloat3 away = kcur - kiteFoe;
						if (away.SqLength2D() > 1.f) {
							away.SafeNormalize2D();
							const float open = std::max(openTo, foeReach);
							newPos = kcur + away * (open - sqrtf(sqFoe));
							CTerrainManager::CorrectPosition(newPos);
						}
					}
				}

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
				//
				// Gated on already being in range. The candidate ring point sits
				// at THIS unit's own weapon range of the target, which is by
				// construction inside (or adjacent to) the target's own threat
				// radius -- so for a unit still closing distance, newPos reads
				// higher threat than curPos on essentially every step, and the
				// veto held it at curPos forever: CmdSetTarget still went out
				// below, so the unit showed a target with no move ever following
				// it. Only a unit already standing within its own standoff range
				// (i.e. already trading fire, which is what the comment above
				// describes) should be offered the choice to hold instead of
				// stepping into a hotter spot.
				CThreatMap* threatMap = manager->GetCircuit()->GetThreatMap();
				const AIFloat3& curPos = unit->GetPos(frame);
				const bool alreadyInRange = (curPos.SqDistance2D(tPos) <= SQUARE(r * 1.05f));
				if (alreadyInRange
					&& (threatMap->GetThreatAt(unit, newPos) > threatMap->GetThreatAt(unit, curPos) * 1.5f))
				{
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
			if (leader->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
				leader->GetTravelAct()->GetState());
			}
	if (leader != nullptr) {
		circuit->GetDrawer()->AddPoint(leader->GetPos(circuit->GetLastFrame()), leader->GetCircuitDef()->GetDef()->GetName());
	}
}
#endif

} // namespace circuit
