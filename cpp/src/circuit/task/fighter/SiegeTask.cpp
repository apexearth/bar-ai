/*
 * SiegeTask.cpp
 *
 * apex: see SiegeTask.h. Rows, front to back (TODO.md "the anchored range
 * ladder"): the screen stands between the guns' reach and the long guns, the
 * long guns at their own range outside every known gun, radar and jammer just
 * behind them. Shields and jammers are shot first, then radars, then guns.
 */

#include "task/fighter/SiegeTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "unit/action/MoveAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/enemy/FortCensus.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "AISCommands.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace circuit {

using namespace springai;

static constexpr float SIEGE_GUN_MAX = 2500.f;  // FortCensus GUN_REACH_MAX
static constexpr float RING_STEP = 0.17f;       // SquadTask's siege-ring slide, radians
static constexpr int RING_STEPS = 9;
static constexpr float REORDER_SQ = 64.f * 64.f;

CSiegeTask::CSiegeTask(ITaskModule* mgr)
		: ISquadTask(mgr, FightType::SIEGE, 1.f)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const CFortCensus::SSiege& s = static_cast<CMilitaryManager*>(manager)->GetFortCensus()->GetSiege();
	position = s.on ? s.pos : circuit->GetSetupManager()->GetBasePos();
	fromFrame = circuit->GetLastFrame();
}

CSiegeTask::~CSiegeTask()
{
}

bool CSiegeTask::CanAssignTo(CCircuitUnit* unit) const
{
	return static_cast<CMilitaryManager*>(manager)->GetFortCensus()->GetSiege().on
			&& !unit->GetCircuitDef()->IsAbleToFly();
}

void CSiegeTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitDef* cdef = unit->GetCircuitDef();
	ITravelAction* travelAction = new CMoveAction(unit, circuit->GetPathfinder()->GetSquareSize());
	unit->PushTravelAct(travelAction);
	travelAction->StateWait();
	unit->SetAllowedToJump(cdef->IsAbleToJump() && cdef->IsAttrJump());
}

void CSiegeTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	lastOrder.erase(unit);
	if (leader == nullptr) {
		manager->AbortTask(this);
	}
}

void CSiegeTask::Start(CCircuitUnit* unit)
{
	if (!pPath->posPath.empty() && (unit->GetTravelAct() != nullptr)) {
		unit->GetTravelAct()->SetPath(pPath, lowestSpeed);
	}
}

void CSiegeTask::Update()
{
	++updCount;
	if (!static_cast<CMilitaryManager*>(manager)->GetFortCensus()->GetSiege().on) {
		manager->AbortTask(this);
		return;
	}
	if (leader == nullptr) {
		return;
	}
	const int frame = manager->GetCircuit()->GetLastFrame();
	if (frame < lastTouched + FRAMES_PER_SEC) {
		return;
	}
	lastTouched = frame;
	Execute();
}

void CSiegeTask::OnUnitIdle(CCircuitUnit* unit)
{
	IFighterTask::OnUnitIdle(unit);
	// a finished move is the unit standing where it was sent; the next execute re-checks it
	lastOrder.erase(unit);
}

// Reach by the longest weapon, as the script's claim (Catalog gMaxRange) measures it.
static float SiegeReach(CCircuitDef* cdef)
{
	return std::max(cdef->HasSurfToLand() ? cdef->GetMaxRange(CCircuitDef::RangeType::LAND) : 0.f,
			cdef->GetMaxRange());
}

CSiegeTask::Row CSiegeTask::RowOf(CCircuitUnit* unit, float reach) const
{
	CCircuitDef* cdef = unit->GetCircuitDef();
	const float r = SiegeReach(cdef);
	if (r <= 0.f) {  // not IsRoleSupport: anti_heavy_ass (the Sharpshooter) is a SUPPORT-type role (unit.as)
		return Row::SUPPORT;
	}
	return (r > reach) ? Row::CARRY : Row::SCREEN;
}

// The ring point at r round tPos, nearest the bearing to `from`, that no known gun reaches.
bool CSiegeTask::FreeStand(const AIFloat3& tPos, const AIFloat3& from, float r, AIFloat3& out) const
{
	const CFortCensus* census = static_cast<CMilitaryManager*>(manager)->GetFortCensus();
	const float alpha = std::atan2(from.z - tPos.z, from.x - tPos.x);
	out = AIFloat3(tPos.x + r * std::cos(alpha), tPos.y, tPos.z + r * std::sin(alpha));
	if (census->GunHDAt(out) <= 0.f) {
		return true;
	}
	for (int k = 1; k <= RING_STEPS; ++k) {
		for (int sgn = -1; sgn <= 1; sgn += 2) {
			const float a = alpha + sgn * k * RING_STEP;
			const AIFloat3 p(tPos.x + r * std::cos(a), tPos.y, tPos.z + r * std::sin(a));
			if (census->GunHDAt(p) <= 0.f) {
				out = p;
				return true;
			}
		}
	}
	return false;
}

CEnemyInfo* CSiegeTask::PickTarget(const AIFloat3& goal, float area, const AIFloat3& from, float carryR, int& cls)
{
	CCircuitAI* circuit = manager->GetCircuit();
	struct SCand { CEnemyInfo* e; int cls; float sq; };
	std::vector<SCand> cands;
	for (const auto& kv : circuit->GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		if (e->IsHidden()) {
			continue;
		}
		CCircuitDef* edef = e->GetCircuitDef();
		if ((edef == nullptr) || edef->IsMobile() || (e->GetPos().SqDistance2D(goal) > SQUARE(area))) {
			continue;
		}
		const float landR = edef->HasSurfToLand() ? edef->GetMaxRange(CCircuitDef::RangeType::LAND) : 0.f;
		int c = -1;
		if (edef->IsShieldDef()) {
			c = 0;
		} else if ((edef->GetJammerRadius() > 0.f) && (edef->GetMaxRange() <= 0.f)) {
			c = 1;
		} else if ((edef->GetRadarRadius() > 0.f) && (edef->GetMaxRange() <= 0.f)) {
			c = 2;
		} else if ((landR > 0.f) && (landR <= SIEGE_GUN_MAX)) {
			c = 3;
		}
		if (c >= 0) {
			cands.push_back(SCand{e, c, e->GetPos().SqDistance2D(from)});
		}
	}
	if (cands.empty()) {
		cls = -1;
		return nullptr;
	}
	std::sort(cands.begin(), cands.end(), [](const SCand& a, const SCand& b) {
		return (a.cls != b.cls) ? (a.cls < b.cls) : (a.sq < b.sq);
	});
	CEnemyInfo* cur = GetTarget();
	int curIdx = -1;
	for (size_t i = 0; i < cands.size(); ++i) {
		if (cands[i].e == cur) {
			curIdx = (int)i;
			break;
		}
	}
	const float standR = 0.5f * (static_cast<CMilitaryManager*>(manager)->GetFortCensus()->GetSiege().reach + carryR);
	AIFloat3 stand;
	int best = -1;
	for (size_t i = 0; i < cands.size(); ++i) {
		if (FreeStand(cands[i].e->GetPos(), from, standR, stand)) {
			best = (int)i;
			break;
		}
	}
	if (best < 0) {
		// nothing can be stood off: commit to the current target, else the nearest of the highest class
		++nCommit;
		best = (curIdx >= 0) ? curIdx : 0;
	} else if ((curIdx >= 0) && (curIdx != best) && (cands[best].cls >= cands[curIdx].cls)
		&& FreeStand(cur->GetPos(), from, standR, stand))
	{
		best = curIdx;  // the current target holds against anything not of a higher class
	}
	cls = cands[best].cls;
	return cands[best].e;
}

void CSiegeTask::Execute()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
	const CFortCensus* census = militaryMgr->GetFortCensus();
	const CFortCensus::SSiege& s = census->GetSiege();
	const int frame = circuit->GetLastFrame();
	const float reach = s.reach;
	const float area = s.radius + s.reach;

	AIFloat3 from = ZeroVector;
	float carryR = std::numeric_limits<float>::max();
	int n = 0;
	nCarry = nScreen = nSupport = 0;
	for (CCircuitUnit* unit : units) {
		from += unit->GetPos(frame);
		++n;
		switch (RowOf(unit, reach)) {
			case Row::CARRY: {
				++nCarry;
				carryR = std::min(carryR, SiegeReach(unit->GetCircuitDef()));
			} break;
			case Row::SCREEN: {
				++nScreen;
			} break;
			case Row::SUPPORT: {
				++nSupport;
			} break;
		}
	}
	if (n == 0) {
		return;
	}
	from /= (float)n;
	if (nCarry == 0) {
		carryR = reach + 2.f * DEFAULT_SLACK;  // no long gun yet: hold just outside the guns
	}

	// one long gun walked out alone dies on the way: the squad gathers at our front until it can win
	if (!s.ready) {
		++nGather;
		AIFloat3 rally = circuit->GetFrontPos();
		if (rally == ZeroVector) {
			rally = leader->GetPos(frame);
		}
		CTerrainManager::CorrectPosition(rally);
		if (IsJoinCommitted() && (leader->GetPos(frame).SqDistance2D(rally) < SQUARE(DEFAULT_SLACK * 4))) {
			JoinReopen();
		}
		for (CCircuitUnit* unit : units) {
			if (unit->Blocker() == nullptr) {
				Order(unit, rally, nullptr, false, frame);
			}
		}
		if (frame >= logAt) {
			logAt = frame + FRAMES_PER_SEC * 30;
			std::string who;
			for (CCircuitUnit* unit : units) {
				const Row row = RowOf(unit, reach);
				who += std::string(" ") + unit->GetCircuitDef()->GetDef()->GetName()
						+ ((row == Row::CARRY) ? ":c" : (row == Row::SCREEN) ? ":s" : ":p");
			}
			circuit->LOG("apex: siege-squad t=%i n=%i carry=%i screen=%i support=%i gather=%i rallyD=%.0f s=%i |%s",
					circuit->GetTeamId(), n, nCarry, nScreen, nSupport, nGather,
					std::sqrt(from.SqDistance2D(rally)), (frame - fromFrame) / FRAMES_PER_SEC, who.c_str());
		}
		return;
	}
	JoinCommit(0);

	int cls = -1;
	CEnemyInfo* tgt = PickTarget(s.pos, area, from, carryR, cls);
	if (tgt != GetTarget()) {
		SetTarget(tgt);
		targetCls = cls;
	}
	const AIFloat3 tPos = (tgt != nullptr) ? tgt->GetPos() : s.pos;
	position = tPos;
	const bool dark = (tgt != nullptr) && !tgt->IsInRadarOrLOS();
	if (dark || ((tgt != nullptr) && !tgt->IsInLOS())) {
		militaryMgr->NoteSpotWanted(tPos, frame);
	}

	const float carryStand = 0.5f * (reach + carryR);
	const float screenStand = std::max(reach + DEFAULT_SLACK, 0.5f * (reach + carryStand));

	// far away: walk the threat-aware path to the carry row's stand, at the slowest member's pace
	const AIFloat3& leadPos = leader->GetPos(frame);
	const float travelR = carryStand + leader->GetCircuitDef()->GetMaxRange() + DEFAULT_SLACK * 4;
	if (leadPos.SqDistance2D(tPos) > SQUARE(travelR)) {
		if (!IsQueryReady(leader)) {
			return;
		}
		AIFloat3 stand;
		FreeStand(tPos, leadPos, carryStand, stand);
		CTerrainManager::CorrectPosition(stand);
		CPathFinder* pathfinder = circuit->GetPathfinder();
		std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
				leader, circuit->GetThreatMap(), leadPos, stand, pathfinder->GetSquareSize());
		pathQueries[leader] = query;
		pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
			this->ApplyTravel(static_cast<const CQueryPathSingle*>(query));
		});
		lastOrder.clear();
		return;
	}

	CThreatMap* threatMap = circuit->GetThreatMap();
	int nFearNow = 0, nSlidNow = 0;
	for (CCircuitUnit* unit : units) {
		if (unit->Blocker() != nullptr) {
			continue;
		}
		const Row row = RowOf(unit, reach);
		AIFloat3 pos;
		if (row == Row::CARRY) {
			const float ur = SiegeReach(unit->GetCircuitDef());
			float d = 0.5f * (reach + ur);
			// their mobiles closing on a long gun: it steps back as far behind its stand as the screen stands ahead
			const AIFloat3& uPos = unit->GetPos(frame);
			threatMap->SetThreatType(unit);
			if ((threatMap->GetThreatAt(uPos) > THREAT_MIN) && (census->GunHDAt(uPos) <= 0.f)) {
				d += std::max(d - screenStand, 0.f);
				++nFearNow;
			}
			if (!FreeStand(tPos, from, d, pos)) {
				const float edge = ur * 0.95f;
				if ((edge <= d) || !FreeStand(tPos, from, edge, pos)) {
					FreeStand(tPos, from, d, pos);
					++nSlidNow;  // inside some gun's reach wherever it stands: committed
				}
			}
		} else if (row == Row::SCREEN) {
			const float alpha = std::atan2(from.z - tPos.z, from.x - tPos.x);
			pos = AIFloat3(tPos.x + screenStand * std::cos(alpha), tPos.y, tPos.z + screenStand * std::sin(alpha));
		} else {
			const float alpha = std::atan2(from.z - tPos.z, from.x - tPos.x);
			const float d = carryStand + DEFAULT_SLACK;
			pos = AIFloat3(tPos.x + d * std::cos(alpha), tPos.y, tPos.z + d * std::sin(alpha));
		}
		CTerrainManager::CorrectPosition(pos);
		Order(unit, pos, (row == Row::CARRY) ? tgt : nullptr, dark, frame);
	}
	nFear += nFearNow;
	nSlid += nSlidNow;
	nDark += dark ? 1 : 0;

	if (frame >= logAt) {
		logAt = frame + FRAMES_PER_SEC * 30;
		circuit->LOG("apex: siege-squad t=%i n=%i carry=%i screen=%i support=%i tgt=%s cls=%i dark=%i"
				" tDist=%.0f goalD=%.0f carryR=%.0f reach=%.0f hdHere=%.0f fear=%i exposed=%i darkN=%i commit=%i s=%i",
				circuit->GetTeamId(), n, nCarry, nScreen, nSupport,
				(tgt != nullptr) ? tgt->GetCircuitDef()->GetDef()->GetName() : "-", cls, dark ? 1 : 0,
				std::sqrt(from.SqDistance2D(tPos)), std::sqrt(from.SqDistance2D(s.pos)), carryR, reach,
				census->GunHDAt(from), nFear, nSlid, nDark, nCommit, (frame - fromFrame) / FRAMES_PER_SEC);
	}
}

void CSiegeTask::ApplyTravel(const CQueryPathSingle* query)
{
	if (leader == nullptr) {
		return;
	}
	pPath = query->GetPathInfo();
	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
		return;
	}
	// no threat-free path: the engine's own
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		if (unit->GetTravelAct() != nullptr) {
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdMoveTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::TRAVEL);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

void CSiegeTask::Order(CCircuitUnit* unit, const AIFloat3& pos, CEnemyInfo* target, bool dark, int frame)
{
	const int tid = (target != nullptr) ? target->GetId() : -1;
	auto it = lastOrder.find(unit);
	if ((it != lastOrder.end()) && (it->second.targetId == tid) && (it->second.pos.SqDistance2D(pos) < REORDER_SQ)) {
		return;
	}
	lastOrder[unit] = SLast{pos, tid};

	if (unit->GetTravelAct() != nullptr) {
		unit->GetTravelAct()->StateWait();
	}
	CCircuitAI* circuit = manager->GetCircuit();
	const int timeout = frame + FRAMES_PER_SEC * 60;
	if ((target != nullptr) && !dark) {
		const int tile = circuit->GetInflMap()->Pos2Index(target->GetPos());
		unit->Attack(pos, target, tile, false, true, timeout, true);
		return;
	}
	TRY_UNIT(circuit, unit,
		if (target != nullptr) {
			// a jammed or unseen building is shot where we last saw it
			unit->CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout, CCircuitUnit::OrdSrc::STANDOFF);
			unit->CmdAttackGround(target->GetPos(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
		} else if (unit->GetCircuitDef()->HasSurfToLand()) {
			unit->CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout, CCircuitUnit::OrdSrc::STANDOFF);
		} else {
			unit->CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout, CCircuitUnit::OrdSrc::STANDOFF);
		}
		unit->CmdWantedSpeed(NO_SPEED_LIMIT);
	)
}

} // namespace circuit
