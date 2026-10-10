/*
 * SquadTask.cpp
 *
 *  Created on: Jan 23, 2016
 *      Author: rlcevg
 */

#include <map>
#include <array>
#include "task/fighter/SquadTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/BuilderManager.h"
#include "module/MilitaryManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryLineMap.h"
#include "unit/action/TravelAction.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include <cmath>

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

void ISquadTask::AssignTo(CCircuitUnit* unit)
{
	IFighterTask::AssignTo(unit);

	CCircuitDef* cdef = unit->GetCircuitDef();
	const float range = cdef->GetMinRange();
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
	const float range = cdef->GetMinRange();
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
	// a unit cleared to an idle task has no travel action (null after ClearAct)
	ITravelAction* lTravel = leader->GetTravelAct();
	const IAction::State state = (lTravel != nullptr) ? lTravel->GetState() : IAction::State::WAIT;
	const std::shared_ptr<CPathInfo> lPath = (lTravel != nullptr) ? lTravel->GetPath() : nullptr;
	for (CCircuitUnit* unit : rookies) {
		unit->SetTask(this);
		if (unit->GetCircuitDef()->IsRoleSupport()) {
			continue;
		}
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->SetPath(lPath);
			unit->GetTravelAct()->SetState(state);
		}
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

// All-terrain walkers never share a squad with units that cannot climb: the
// leader is the least mobile member, so a Vanguard beside a tank walked the
// tank's road (apexearth 2026-09-26). The pathfinder's own spider test.
bool ISquadTask::SameClimb(CCircuitAI* circuit, CCircuitDef* a, CCircuitDef* b)
{
	static std::set<CCircuitDef::Id> logged;
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	auto climbs = [&](CCircuitDef* d) {
		const SMobileType* mt = terrainMgr->GetMobileType(d->GetId());
		const bool c = (mt != nullptr) && (mt->maxSlope > 0.99f);
		if (logged.insert(d->GetId()).second) {
			circuit->LOG("apex: climb %s allterrain=%i maxSlope=%.3f", d->GetDef()->GetName(),
					c ? 1 : 0, (mt != nullptr) ? mt->maxSlope : -1.f);
		}
		return c;
	};
	return climbs(a) == climbs(b);
}

ISquadTask* ISquadTask::GetMergeTask()
{
	if (updCount % 32 == 1) {
		return IsMergeSafe() ? CheckMergeTask() : nullptr;
	}
	return nullptr;
}

bool ISquadTask::IsMustRegroup()
{
	if ((State::ENGAGE == state) || (updCount % 16 != 15)) {
		return false;
	}

	if (!IsMergeSafe()) {  // (circuit->GetInflMap()->GetEnemyInflAt(leader->GetPos(frame)) > INFL_EPS) ?
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
		// apex: the squad gathers at its FRONT, the member nearest the target
		// (apexearth 2026-09-30: "have the squad stay up towards the front and
		// wait for the reinforcements to come up").
		CCircuitUnit* front = bestPlace;
		if (utils::is_valid(position)) {
			float frontSq = std::numeric_limits<float>::max();
			for (CCircuitUnit* unit : validUnits) {
				const float sq = unit->GetPos(frame).SqDistance2D(position);
				if (sq < frontSq) {
					frontSq = sq;
					front = unit;
				}
			}
		}
		groupPos = front->GetLastPos();
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

	if (threatMap->GetThreatAt(groupPos) >= THREAT_MIN) {
		validUnits.clear();
		state = State::ROAM;
		return false;
	}

	bool wasRegroup = (State::REGROUP == state);
	state = State::ROAM;

	// apex: wait only while less than half the squad's power stands together at
	// the front; one reinforcement walking up is not worth stopping for
	// (apexearth: "10 units turning into 11 -- are you really going to wait?").
	const float sqMaxDist = SQUARE(std::max<float>(SQUARE_SIZE * 8 * validUnits.size(), highestRange));
	float powNear = 0.f, powAll = 0.f;
	bool anyOut = false;
	for (CCircuitUnit* unit : validUnits) {
		const float p = std::max(unit->GetCircuitDef()->GetPower(), 1.f);
		powAll += p;
		if (groupPos.SqDistance2D(unit->GetLastPos()) > sqMaxDist) {
			anyOut = true;
		} else {
			powNear += p;
		}
	}
	if (anyOut && (powNear * 2.f < powAll)) {
		state = State::REGROUP;
	}
	{
		struct Tally { int hold = 0, go = 0, logAt = 0; };
		static std::map<const CCircuitAI*, Tally> tally;
		Tally& t = tally[circuit];
		if (anyOut) {
			++((State::REGROUP == state) ? t.hold : t.go);
		}
		if (frame >= t.logAt) {
			t.logAt = frame + FRAMES_PER_SEC * 60;
			circuit->LOG("apex: regroup held=%i kept-going=%i", t.hold, t.go);
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
	for (CCircuitUnit* unit : units) {
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->SetPath(pPath, speed);
		}
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

// How far `u` keeps from an enemy of def `t`; 0 when it cannot outrange the
// D-gun or outrun its owner, -1 when it is fodder: the metal of `t` it destroys
// before it dies pays for itself. `hold` is the ring it stands on, midway
// between their reach and ours.
float ISquadTask::DGunKeepOut(CCircuitDef* u, CCircuitDef* t, float& hold)
{
	const float reach = t->GetDGunReach();
	if ((reach <= 0.f) || u->IsAbleToFly() || (t->GetSpeed() >= u->GetSpeed())) {
		return 0.f;
	}
	const float keep = reach + t->GetSpeed() * DGUN_REACT_S + u->GetRadius();
	const float ours = u->GetAutoRange(CCircuitDef::RangeType::LAND);
	if (ours <= keep) {
		return 0.f;
	}
	const float shot = t->GetDGunShotAt(u->GetArmorType());
	const float alive = (shot >= u->GetHealth())
			? t->GetDGunReload()
			: u->GetHealth() / std::max(t->GetRawDps(), 1.f);
	const float worth = u->GetRawDps() * alive * t->GetCostM() / std::max(t->GetHealth(), 1.f);
	if (worth >= u->GetCostM()) {
		return -1.f;
	}
	hold = 0.5f * (keep + ours);
	return keep;
}

bool ISquadTask::IsInsideDGun(int frame)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const std::vector<SDGunThreat>& dts = circuit->GetDGunThreats();
	for (const SDGunThreat& d : dts) {
		CCircuitDef* tdef = circuit->GetCircuitDefSafe(d.defId);
		if (tdef == nullptr) {
			continue;
		}
		for (CCircuitUnit* unit : units) {
			const AIFloat3& p = unit->GetPos(frame);
			const float sqD = SQUARE(p.x - d.x) + SQUARE(p.z - d.z);
			if (sqD > SQUARE(highestRange)) {
				continue;
			}
			float hold;
			const float keep = DGunKeepOut(unit->GetCircuitDef(), tdef, hold);
			if ((keep > 0.f) && (sqD < SQUARE(keep))) {
				return true;
			}
		}
	}
	return false;
}

void ISquadTask::Attack(const int frame)
{
	Attack(frame, GetTarget()->GetUnit()->IsCloaked());
}

void ISquadTask::Attack(const int frame, const bool isGround)
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

	// A LONG GUN STANDS OUTSIDE EVERY TURRET IT KNOWS OF (apexearth 2026-10-08:
	// an Ambassador outranges most T2 turrets; kept at range, with scouts to see
	// for it, it need not die). The ring point slides round the target until no
	// known enemy static reaches it, else backs off along its bearing. Turrets
	// whose reach covers half the map (LRPC) cannot be stood outside of.
	CCircuitAI* circuit = manager->GetCircuit();
	std::vector<std::pair<AIFloat3, float>> guns;
	bool gunsBuilt = false;
	auto buildGuns = [&]() {
		gunsBuilt = true;
		const float reachSq = SQUARE(highestRange + 2000.f);
		for (const auto& ekv : circuit->GetEnemyInfos()) {
			CEnemyInfo* e = ekv.second;
			CCircuitDef* gd = e->GetCircuitDef();
			if ((gd == nullptr) || gd->IsMobile() || !gd->HasSurfToLand()) {
				continue;
			}
			const float gr = gd->GetMaxRange(CCircuitDef::RangeType::LAND);
			if ((gr <= 0.f) || (gr > 2500.f) || (e->GetPos().SqDistance2D(tPos) > reachSq)) {
				continue;
			}
			guns.push_back(std::make_pair(e->GetPos(), gr + 100.f));
		}
	};
	auto safeAt = [&](const AIFloat3& p) {
		for (const auto& g : guns) {
			if (p.SqDistance2D(g.first) < SQUARE(g.second)) {
				return false;
			}
		}
		return true;
	};
	if (!GetTarget()->IsInRadarOrLOS()) {
		for (const auto& kv : rangeUnits) {
			CCircuitDef* d0 = (*kv.second.begin())->GetCircuitDef();
			if (d0->IsAttrSiege() || (d0->GetMaxRange() > d0->GetLosRadius())) {
				circuit->GetMilitaryManager()->NoteSpotWanted(tPos, frame);
				break;
			}
		}
	}
	static std::map<int, std::array<int, 4>> ringN;  // per team: ok, slid, back, none
	static std::map<int, int> ringLogAt;
	std::array<int, 4>& rn = ringN[circuit->GetTeamId()];

	// D-GUN CARRIERS ARE KEPT OUT OF (apexearth 2026-10-10: Titans walked up to
	// Behemoths and died; held at range they kill it). A unit that outranges and
	// outruns one near the target stands outside its reach (DGunKeepOut).
	struct SFear { float x, z; CCircuitDef* tdef; };
	std::vector<SFear> fears;
	for (const SDGunThreat& d : circuit->GetDGunThreats()) {
		CCircuitDef* tdef = circuit->GetCircuitDefSafe(d.defId);
		if (tdef == nullptr) {
			continue;
		}
		const float relR = highestRange + tdef->GetDGunReach() + tdef->GetSpeed() * DGUN_REACT_S + DEFAULT_SLACK;
		if (SQUARE(d.x - tPos.x) + SQUARE(d.z - tPos.z) < SQUARE(relR)) {
			fears.push_back({d.x, d.z, tdef});
		}
	}
	dgunNear = !fears.empty();
	std::vector<std::pair<float, float>> keepHold(fears.size());
	static std::map<int, std::array<int, 3>> fearN;  // per team: hold, backoff, fodder
	static std::map<int, int> fearLogAt;
	std::array<int, 3>& fn = fearN[circuit->GetTeamId()];
	int& fearLog = fearLogAt[circuit->GetTeamId()];
	std::string fearEx;

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

			bool feared = false;
			bool inside = false;
			bool fodder = false;
			int exI = -1;
			const AIFloat3 uPos = unit->GetPos(frame);
			for (size_t i = 0; i < fears.size(); ++i) {
				float h = 0.f;
				const float keep = DGunKeepOut(unit->GetCircuitDef(), fears[i].tdef, h);
				keepHold[i] = std::make_pair(keep, h);
				fodder |= (keep < 0.f);
				if (keep > 0.f) {
					feared = true;
					if (SQUARE(uPos.x - fears[i].x) + SQUARE(uPos.z - fears[i].z) < SQUARE(keep)) {
						inside = true;
						exI = (int)i;
					}
				}
			}

			if (isRepeatAttack
				|| inside
				|| (unit->GetTarget() != GetTarget())
				|| (unit->GetTargetTile() != targetTile))
			{
				const float angle = alpha + beta;
				const float r = (iterNum == 0) ? range0 : range;
				AIFloat3 newPos(tPos.x + r * cosf(angle), tPos.y, tPos.z + r * sinf(angle));
				CCircuitDef* udef = unit->GetCircuitDef();
				if ((udef->IsAttrSiege() || (udef->GetMaxRange() > udef->GetLosRadius())) && !udef->IsAttrMelee()) {
					if (!gunsBuilt) {
						buildGuns();
					}
					if (safeAt(newPos)) {
						++rn[0];
					} else {
						bool found = false;
						for (int k = 1; (k <= 9) && !found; ++k) {
							for (int sgn = -1; (sgn <= 1) && !found; sgn += 2) {
								const float a2 = angle + sgn * k * 0.17f;
								const AIFloat3 p(tPos.x + r * cosf(a2), tPos.y, tPos.z + r * sinf(a2));
								if (safeAt(p)) {
									newPos = p;
									found = true;
								}
							}
						}
						if (found) {
							++rn[1];
						} else {
							float rr = r;
							for (int k = 0; (k < 12) && !found; ++k) {
								rr += 100.f;
								const AIFloat3 p(tPos.x + rr * cosf(angle), tPos.y, tPos.z + rr * sinf(angle));
								newPos = p;
								found = safeAt(p);
							}
							++rn[found ? 2 : 3];
						}
					}
				}
				bool pushed = false;
				for (size_t i = 0; feared && (i < fears.size()); ++i) {
					const float keep = keepHold[i].first;
					const float h = keepHold[i].second;
					if (keep <= 0.f) {
						continue;
					}
					float ax = newPos.x - fears[i].x;
					float az = newPos.z - fears[i].z;
					float d = std::sqrt(ax * ax + az * az);
					if (d >= h) {
						continue;
					}
					if (d < 1.f) {
						ax = uPos.x - fears[i].x;
						az = uPos.z - fears[i].z;
						d = std::sqrt(ax * ax + az * az);
						if (d < 1.f) {
							ax = cosf(alpha);
							az = sinf(alpha);
							d = 1.f;
						}
					}
					newPos.x = fears[i].x + ax * h / d;
					newPos.z = fears[i].z + az * h / d;
					pushed = true;
					exI = (exI < 0) ? (int)i : exI;
				}
				if ((exI >= 0) && fearEx.empty() && (frame >= fearLog)) {
					fearEx = utils::string_format("unit=%s threat=%s ourR=%.0f theirR=%.0f keep=%.0f hold=%.0f act=%s",
							udef->GetDef()->GetName(), fears[exI].tdef->GetDef()->GetName(),
							udef->GetAutoRange(CCircuitDef::RangeType::LAND), fears[exI].tdef->GetDGunReach(),
							keepHold[exI].first, keepHold[exI].second, inside ? "backoff" : "hold");
				}
				fn[0] += (pushed && !inside) ? 1 : 0;
				fn[1] += inside ? 1 : 0;
				fn[2] += fodder ? 1 : 0;
				CTerrainManager::CorrectPosition(newPos);
				unit->Attack(newPos, GetTarget(), targetTile, isGround, isStatic, frame + FRAMES_PER_SEC * 60, feared);
			}

			beta += delta;
			++iterNum;
		}
	}
	int& logAt = ringLogAt[circuit->GetTeamId()];
	if ((frame >= logAt) && (rn[1] + rn[2] + rn[3] > 0)) {
		logAt = frame + FRAMES_PER_SEC * 60;
		circuit->LOG("apex: siege-ring t=%i ok=%i slid=%i back=%i none=%i guns=%i",
				circuit->GetTeamId(), rn[0], rn[1], rn[2], rn[3], (int)guns.size());
	}
	if (!fearEx.empty()) {
		fearLog = frame + FRAMES_PER_SEC * 20;
		circuit->LOG("apex: dgun-fear t=%i %s n_hold=%i n_back=%i n_fodder=%i",
				circuit->GetTeamId(), fearEx.c_str(), fn[0], fn[1], fn[2]);
	}
}

#ifdef DEBUG_VIS
void ISquadTask::Log()
{
	IFighterTask::Log();

	CCircuitAI* circuit = manager->GetCircuit();
	circuit->LOG("pPath: %i | size: %i | TravelAct: %i", pPath.get(), pPath ? pPath->posPath.size() : 0,
			((leader != nullptr) && (leader->GetTravelAct() != nullptr)) ? int(leader->GetTravelAct()->GetState()) : -1);
	if (leader != nullptr) {
		circuit->GetDrawer()->AddPoint(leader->GetPos(circuit->GetLastFrame()), leader->GetCircuitDef()->GetDef()->GetName());
	}
}
#endif

// Kept across the fight revert for AntiAirTask/AntiHeavyTask, which size their
// odds with it. The apex version also zeroed a retreating unit's power
// (apexearth: "A retreating unit should have 0 power"), but that read the
// coward set, which went back to stock with the rest of the squad behaviour.
// Health-weighted power is the half the surviving callers use.
float ISquadTask::GetHealthScale() const
{
	float total = .0f;
	float alive = .0f;
	for (CCircuitUnit* unit : units) {
		const float power = unit->GetCircuitDef()->GetPower();
		total += power;
		float hp = unit->GetHealthPercent();
		hp = std::max(.0f, std::min(1.f, hp));  // capture progress drives it negative
		alive += power * hp;
	}
	return (total > .0f) ? (alive / total) : 1.f;
}

// Kept across the fight revert: SupportAction reads it to decide how far an
// escort trails its squad, and escorts are staying (apexearth kept the 2 radar
// / 2 jammer cap as a build rule).
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

} // namespace circuit
