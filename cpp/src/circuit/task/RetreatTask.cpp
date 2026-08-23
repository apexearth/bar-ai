/*
 * RetreatTask.cpp
 *
 *  Created on: Jan 18, 2015
 *      Author: rlcevg
 */

#include "task/RetreatTask.h"
#include "map/ThreatMap.h"
#include "map/InfluenceMap.h"
#include "module/BuilderManager.h"
#include "module/EconomyManager.h"
#include "module/FactoryManager.h"
#include "module/MilitaryManager.h"
#include "resource/MetalManager.h"
#include "setup/SetupManager.h"
#include "unit/enemy/EnemyManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryCostMap.h"
#include "terrain/TerrainManager.h"
#include "unit/action/DGunAction.h"
#include "unit/action/MoveAction.h"
#include "unit/action/FightAction.h"
#include "CircuitAI.h"
#include <limits>
#include "util/Utils.h"

#include "AISCommands.h"
#include "Log.h"   // circuit->LOG in the heal-post diagnostic below

namespace circuit {

using namespace springai;

CRetreatTask::CRetreatTask(ITaskModule* mgr, int timeout)
		: IUnitTask(mgr, Priority::NORMAL, Type::RETREAT, timeout)
		, repairer(nullptr)
{
}

CRetreatTask::~CRetreatTask()
{
}

void CRetreatTask::ClearRelease()
{
	costQuery = nullptr;
	IUnitTask::ClearRelease();
}

void CRetreatTask::AssignTo(CCircuitUnit* unit)
{
	IUnitTask::AssignTo(unit);

	if (unit->HasDGun()) {
		unit->PushDGunAct(new CDGunAction(unit, unit->GetDGunRange() * 0.9f));
	}

	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitDef* cdef = unit->GetCircuitDef();
	TRY_UNIT(circuit, unit,
		unit->CmdSetFireState(cdef->IsAttrRetHold() ? CCircuitDef::FireType::HOLD : CCircuitDef::FireType::OPEN);
	)
	if (cdef->IsAttrBoost()) {
		unit->SetTaskFrame(circuit->GetLastFrame());  // avoid UnitIdle on find_pad
		const int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
		TRY_UNIT(circuit, unit,
			if (cdef->IsPlane()) {
				unit->CmdFindPad(frame);
			}
			unit->CmdManualFire(UNIT_COMMAND_OPTION_ALT_KEY, frame);
		)
		return;
	}

	int squareSize = circuit->GetPathfinder()->GetSquareSize();
	ITravelAction* travelAction;
	if (cdef->IsAttrRetFight()) {
		travelAction = new CFightAction(unit, squareSize);
	} else {
		travelAction = new CMoveAction(unit, squareSize);
	}
	unit->PushTravelAct(travelAction);
	unit->SetAllowedToJump(cdef->IsAbleToJump() && !cdef->IsAttrNoJump());

	// CLOAKING ON RETREAT IS NOT FREE, AND FOR A COMMANDER IT IS NOT AFFORDABLE.
	//
	// This cloaked unconditionally, and armcom's cloakcostmoving is 1000 energy
	// per second -- so a retreating commander switched on a drain no early
	// economy can pay. UpdateCommCloak (military watchdog) and Update() below
	// then both re-decide with IsCommCloakWanted, see it is unaffordable and
	// switch it straight back off, and the next retreat re-assignment turns it on
	// again. apexearth, twice, watching: "commander still 'running to safety' and
	// cloaking..." -- one event, not two.
	//
	// Ordinary cloakers keep the old behaviour: for them it is cheap and hiding
	// while wounded is the point. Only the commander consults affordability, via
	// the same predicate the watchdog uses, so the two cannot disagree.
	if (unit->GetCircuitDef()->IsAbleToCloak()) {
		const bool wantCloak = !cdef->IsRoleComm()
				|| circuit->GetMilitaryManager()->IsCommCloakWanted(unit);
		TRY_UNIT(manager->GetCircuit(), unit,
			unit->CmdCloak(wantCloak);
			unit->CmdSetFireState(CCircuitDef::FireType::RETURN);
		)
	}

	// Mobile repair
	if (!cdef->IsAbleToFly() && !unit->IsAttrNoRepair()) {
		circuit->GetBuilderManager()->Enqueue(TaskB::Repair(IBuilderTask::Priority::HIGH, unit));
	}
}

void CRetreatTask::RemoveAssignee(CCircuitUnit* unit)
{
	IUnitTask::RemoveAssignee(unit);
	if (units.empty()) {
		manager->DoneTask(this);
	}

	TRY_UNIT(manager->GetCircuit(), unit,
		unit->CmdSetFireState(unit->GetCircuitDef()->GetFireState());
	)
}

void CRetreatTask::Start(CCircuitUnit* unit)
{
	if ((unit->GetTravelAct() == nullptr) || unit->GetTravelAct()->IsFinished()) {
		return;
	}

	if (!IsQueryReady(unit)) {
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CPathFinder* pathfinder = circuit->GetPathfinder();
	const AIFloat3& startPos = unit->GetPos(frame);
	AIFloat3 endPos;
	float range;

	if (unit->GetTravelAct()->GetPath() == nullptr) {
		std::shared_ptr<CPathInfo> pPath = std::shared_ptr<CPathInfo>(new CPathInfo());
		pPath->PushPos(startPos, pathfinder);
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetPath(pPath);
		}
	}

	bool isNoEndPos = true;
	if (repairer != nullptr) {
		endPos = repairer->GetPos(frame);
		isNoEndPos = circuit->GetInflMap()->GetInfluenceAt(endPos) < INFL_EPS;
		if (!isNoEndPos) {
			range = pathfinder->GetSquareSize();
		}
	}
	if (isNoEndPos) {
		CFactoryManager* factoryMgr = circuit->GetFactoryManager();
		endPos = factoryMgr->GetClosestHaven(unit);
		if (!utils::is_valid(endPos)) {
			endPos = circuit->GetSetupManager()->GetBasePos();

			// Check home safety, find new one otherwise
			if (circuit->GetInflMap()->GetInfluenceAt(endPos) < INFL_SAFE) {
				circuit->GetSetupManager()->FindNewBase(unit);
				endPos = circuit->GetSetupManager()->GetBasePos();
			}
		}
		const AIFloat3 rally = GetRallyPos(unit);
		endPos = utils::is_valid(rally) ? rally : GetRearHaven(unit, endPos);
		range = factoryMgr->GetAssistRange() * 0.6f + pathfinder->GetSquareSize();

		// apexearth: "sometimes our retreat logic takes us into new threats.
		// Any way we can check where we're retreating to and recompute
		// sometimes?" GetClosestHaven picks by distance only and never
		// re-checks threat, and neither GetRallyPos nor GetRearHaven look at
		// enemy influence either -- a haven or rally point that fell to the
		// enemy after it was registered stays the answer every time this is
		// called. Start() already re-runs every other Update() tick per
		// retreating unit (updCount toggling below), so this check gets a
		// fresh answer on the same cadence rather than only running once at
		// task assignment. Falls back to the base -- itself already
		// threat-checked above -- rather than to nothing, so a rejected
		// haven/rally never leaves endPos unvalidated.
		if (circuit->GetInflMap()->GetEnemyInflAt(endPos) >= INFL_EPS) {
			AIFloat3 fallback = circuit->GetSetupManager()->GetBasePos();
			if (circuit->GetInflMap()->GetInfluenceAt(fallback) < INFL_SAFE) {
				circuit->GetSetupManager()->FindNewBase(unit);
				fallback = circuit->GetSetupManager()->GetBasePos();
			}
			endPos = fallback;
		}

		// apexearth 2026-08-22: "our retreats are often ALL THE WAY BACK TO THE
		// BASE, but if we have rezbots we can just step behind the main army's
		// attack a little bit and get healed." Havens are only registered where
		// assistants park next to factories, so a retreat without an assigned
		// repairer is a walk across the map -- and the walk is what kills:
		// measured 2026-08-22, 1062 units and 228k metal died a median 1s after
		// switching to retreat. The medics hold station behind the lane, so a
		// short step to the rear of the front lands the wounded in repair reach.
		//
		// Placed AFTER the threat re-check above on purpose: that check rewrites
		// endPos to the base whenever it sees ANY enemy influence, so a heal post
		// chosen before it was simply overwritten. And the test here is NET
		// influence, not INFL_EPS -- ground 900 behind our own front nearly
		// always carries some enemy influence, and demanding essentially zero
		// rejected every candidate.
		bool healPost = false;
		const float behind = circuit->GetTunable("apex_retreat_behind", 0.f);
		if (behind > 0.f) {
			const AIFloat3& front = circuit->GetFrontPos();
			const AIFloat3& home = circuit->GetSetupManager()->GetBasePos();
			if (utils::is_valid(front)) {
				AIFloat3 dir = home - front;
				dir.y = 0.f;
				const float len = dir.Length2D();
				if (len > 1.f) {
					dir /= len;
					AIFloat3 spot = front + dir * behind;
					CTerrainManager::CorrectPosition(spot);
					const AIFloat3& here = unit->GetPos(frame);
					const float ours = circuit->GetInflMap()->GetInfluenceAt(spot);
					const float foe = circuit->GetInflMap()->GetEnemyInflAt(spot);
					const bool ourGround = (ours > foe);
					const bool nearer =
							here.SqDistance2D(spot) < here.SqDistance2D(endPos);
					if (ourGround && nearer
						&& circuit->GetTerrainManager()->CanMoveToPos(unit->GetArea(), spot))
					{
						endPos = spot;
						healPost = true;
					} else if (circuit->GetTunable("apex_retreat_log", 0.f) > 0.f) {
						circuit->LOG("apex: heal-post refused ourInfl=%.2f foeInfl=%.2f nearer=%d",
								ours, foe, (int)nearer);
					}
				}
			}
		}
		// Retreats were the biggest source of unexplained movement on the map:
		// every other mover pings its intent, so the wounded walk must too.
		IntentPing(unit->GetPos(frame), healPost ? "RET heal" : "RET home");

		// apexearth: "when we're retreating to safe havens, it seems we
		// clump up into a tight ball, which makes us even more likely to
		// die... we should spread out more evenly, forming a line against
		// the threat." Every unit on this task computes the same endPos
		// independently and paths to that exact point -- a squad that
		// pulled back healthy converges onto one AOE-sized spot, which is
		// no safer than standing still once it arrives. Offset along the
		// line perpendicular to the enemy direction, same idea as
		// ISquadTask::Attack's row spacing, keyed by this unit's rank among
		// the task's OTHER assignees so the line forms without any unit
		// needing to know where the others are headed.
		if (units.size() > 1) {
			const AIFloat3& foe = circuit->GetEnemyManager()->GetEnemyPos();
			AIFloat3 dir = endPos - foe;
			const float len = dir.Length2D();
			if (len > 1.f) {
				const AIFloat3 perp(-dir.z / len, 0.f, dir.x / len);
				int index = 0;
				for (CCircuitUnit* u : units) {
					if (u == unit) {
						break;
					}
					++index;
				}
				const float spacing = SQUARE_SIZE * 24;
				const float lineOffset = (index - (units.size() - 1) * 0.5f) * spacing;
				AIFloat3 spread = endPos + perp * lineOffset;
				CTerrainManager::CorrectPosition(spread);
				if (circuit->GetTerrainManager()->CanMoveToPos(unit->GetArea(), spread)) {
					endPos = spread;
				}
			}
		}
	}

//	const float minThreat = circuit->GetThreatMap()->GetUnitThreat(unit) * 0.125f;
	// apex: a WOUNDED unit weighted threat at the neutral 1.0 -- LESS than a
	// healthy attacking squad's 2.0 -- so retreats beelined home through the
	// enemy: measured live 2026-08-19, RETREAT tasks were the largest mobile
	// combat death bucket, 39.4k metal / 371 units in one 20m game ("solo
	// dudes walking into enemy groups"). High mod, no ceiling: the path bends
	// hard around danger but can never fail to exist.
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			unit, circuit->GetThreatMap(),
			startPos, endPos, range, nullptr,
			std::numeric_limits<float>::max(), false,
			circuit->GetTunable("apex_retreat_threat_mod", 4.f));
	pathQueries[unit] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyPath(static_cast<const CQueryPathSingle*>(query));
	});
}

// How far behind the haven the commander is parked. Roughly a base radius, so
// it clears the buildings the enemy is coming for without leaving the base.
#define COMM_REAR_DIST	900.f

// Where along base->lane a falling-back fighter re-forms. Our script publishes
// the front at 0.78 of that span, so this sits behind the fighting but well
// forward of home.
#define RALLY_FRAC	0.55f

// The health at which Update() below hands the unit back. Nothing else releases
// it, so the rally-point gate reads the same constant.
#define RETREAT_HEALED	0.98f

// A fighter that is not hurt falls back to ONE shared point, not to whichever
// haven happens to be nearest it. GetClosestHaven is per-unit and havens are
// factory positions, so a retreating squad fanned out to several places at the
// back of the map and then walked all the way forward again. apexearth,
// watching: "each of our units, as they pull back, it looks to me like they're
// pulling back to different locations... a perfectly healthy set of units took
// the long walk away from the front line, and now they're walking all the way
// back."
//
// Builders, the commander and anything damaged are excluded: they retreat to be
// repaired or to hide, and a rally point in front of the base serves neither.
AIFloat3 CRetreatTask::GetRallyPos(CCircuitUnit* unit) const
{
	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (cdef->IsRoleComm() || (circuit->GetBindedRole(cdef->GetMainRole()) == ROLE_TYPE(BUILDER))) {
		return -RgtVector;
	}

	// A haven is a nano turret's patrol position, so it repairs whatever stands
	// on it; the defence stand is towers and the rally point is bare ground, and
	// neither ends the retreat. Damage therefore defers to the haven, and the
	// rally point is used only when no haven is reachable.
	if ((unit->GetHealthPercent() <= RETREAT_HEALED)
		&& utils::is_valid(circuit->GetFactoryManager()->GetClosestHaven(unit)))
	{
		return -RgtVector;
	}

	// Our own static defence, when there is any: a fighter that pulls out should
	// end up beside the towers and the constructors keeping them up, not on a
	// point interpolated along a lane that may have nothing on it.
	const AIFloat3 stand = circuit->GetMilitaryManager()->GetDefenceStand();
	if (utils::is_valid(stand)
		&& circuit->GetTerrainManager()->CanMoveToPos(unit->GetArea(), stand))
	{
		return stand;
	}

	CSetupManager* setupMgr = circuit->GetSetupManager();
	const AIFloat3& basePos = setupMgr->GetBasePos();
	const AIFloat3& lanePos = setupMgr->GetLanePos();
	if (!utils::is_valid(lanePos)) {
		return -RgtVector;
	}

	AIFloat3 rally = basePos + (lanePos - basePos) * RALLY_FRAC;
	CTerrainManager::CorrectPosition(rally);
	if (!circuit->GetTerrainManager()->CanMoveToPos(unit->GetArea(), rally)) {
		return -RgtVector;
	}
	return rally;
}

// A retreat ends at the closest haven, or at the base CENTRE when there is no
// haven -- which is the middle of the thing the enemy is attacking. The
// commander then sits there, cloaked, in the path of the fight, and its death
// takes the surrounding base with it.
//
// Push the destination directly away from the enemy centroid instead. Only for
// the commander: everything else retreats to be repaired, and a repair pad
// behind the base is no use to it.
//
// The push applies to the base-centre case ONLY. A haven is an assistant's own
// position -- GetAssistRange is that unit's build distance -- so standing on it
// is the free repair, and COMM_REAR_DIST puts the commander outside it. Update()
// will not release a commander below its own retreat threshold, so a commander
// pushed out of repair range is held until idle autoheal carries it there.
AIFloat3 CRetreatTask::GetRearHaven(CCircuitUnit* unit, const AIFloat3& haven) const
{
	CCircuitAI* circuit = manager->GetCircuit();
	if (!unit->GetCircuitDef()->IsRoleComm()) {
		return haven;
	}
	if (utils::is_valid(circuit->GetFactoryManager()->GetClosestHaven(unit))) {
		return haven;
	}

	const AIFloat3& foe = circuit->GetEnemyManager()->GetEnemyPos();
	const float len = haven.distance2D(foe);
	if (len < 1.f) {  // no enemy known yet; no direction to run in
		return haven;
	}

	AIFloat3 rear = haven;
	rear.x += (haven.x - foe.x) / len * COMM_REAR_DIST;
	rear.z += (haven.z - foe.z) / len * COMM_REAR_DIST;
	CTerrainManager::CorrectPosition(rear);

	if (!circuit->GetTerrainManager()->CanMoveToPos(unit->GetArea(), rear)) {
		return haven;  // water, cliff or off the map -- the centre beats stuck
	}
	return rear;
}

void CRetreatTask::Update()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	bool isExecute = (++updCount % 2 == 0);
	auto assignees = units;
	for (CCircuitUnit* unit : assignees) {
		const float healthPerc = unit->GetHealthPercent();
		// apexearth 2026-08-22: "units just keep walking home until they're
		// finally fully repaired". RETREAT_HEALED is 0.98 and NOTHING else
		// releases the unit, so one that pulled out at half health is out of
		// the fight until it is essentially new -- the walk home, the wait,
		// and the walk back. A unit is combat-worthy well before 98%; the
		// tunable lets it rejoin at a stated fraction instead.
		const float healed = circuit->GetTunable("apex_retreat_healed", RETREAT_HEALED);
		bool isRepaired = unit->HasShield()
				? (healthPerc > healed) && unit->IsShieldCharged(circuit->GetSetupManager()->GetFullShield())
				: healthPerc > healed;

		CCircuitDef* cdef = unit->GetCircuitDef();
		// apex: excluded the commander. isRepaired is a pure HP-percentage
		// check (RETREAT_HEALED=0.98) with NO influence/safety read at all --
		// correct for a unit that fled because it took damage, since healing
		// back up really does mean "done fleeing". The commander flees on
		// INFLUENCE (see rules_commander.as's flee-influence check), almost
		// always still near-full HP the moment it starts, so isRepaired read
		// true within 1-2 ticks of EVERY assignment regardless of whether the
		// danger that triggered the flee was still there -- ending the
		// retreat almost immediately, every time. This was the dominant cause
		// of the fire-state-toggle/never-settles symptom (the low-worker-
		// count haven shortcut fixed earlier the same night was a real but
		// secondary contributor). Falls through to the branch below instead,
		// which already gates the commander on real influence
		// (GetEnemyInflAt < INFL_EPS), not just HP.
		if (isRepaired && !unit->IsDisarmed(frame) && !cdef->IsRoleComm()) {
			Recovered(unit);
		} else if (unit->IsForceUpdate(frame) || isExecute) {
			Start(unit);
		} else if ((circuit->GetBindedRole(cdef->GetMainRole()) == ROLE_TYPE(BUILDER))
			&& (!cdef->IsRoleComm() || (healthPerc >= cdef->GetRetreat()))
			&& (circuit->GetInflMap()->GetEnemyInflAt(unit->GetPos(frame)) < INFL_EPS))
		{
			Recovered(unit);
		}
	}
}

void CRetreatTask::Finish()
{
	Cancel();
}

void CRetreatTask::Cancel()
{
	if (repairer != nullptr) {
		IUnitTask* repairerTask = repairer->GetTask();
		repairerTask->GetManager()->AbortTask(repairerTask);
	}
}

void CRetreatTask::OnUnitIdle(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();

	CCircuitDef* cdef = unit->GetCircuitDef();
	if (cdef->IsAbleToFly()) {
		// NOTE: unit considered idle after boost and find_pad
		if (State::REGROUP == state) {
			state = State::ROAM;
			return;
		}
		if (unit->GetTravelAct() != nullptr) {
			if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
				unit->GetTravelAct()->StateFinish();
			}
		}

		unit->SetTaskFrame(frame);  // avoid UnitIdle on find_pad
		TRY_UNIT(circuit, unit,
			unit->CmdFindPad(frame + FRAMES_PER_SEC * 60);
		)
		state = State::REGROUP;
		return;
	}

	CFactoryManager* factoryMgr = circuit->GetFactoryManager();
	AIFloat3 haven = (repairer != nullptr) ? repairer->GetPos(frame) : factoryMgr->GetClosestHaven(unit);
	if (!utils::is_valid(haven)) {
		haven = circuit->GetSetupManager()->GetBasePos();
	}
	if (repairer == nullptr) {  // nobody is waiting to repair it -- re-form instead
		const AIFloat3 rally = GetRallyPos(unit);
		haven = utils::is_valid(rally) ? rally : GetRearHaven(unit, haven);
	}

	const float maxDist = factoryMgr->GetAssistRange();
	const AIFloat3& unitPos = unit->GetPos(frame);

	// Cloak is switched on once, when the unit finishes (CircuitAI.cpp), and
	// nothing there ever switches it off -- so re-decide it here too rather than
	// waiting up to a minute for the military manager's watchdog. Same predicate
	// as the watchdog, so the two cannot fight over the state.
	// Only issued on a change; IsCloaked() is the current state.
	if (cdef->IsRoleComm() && cdef->IsAbleToCloak()) {
		const bool wantCloak = circuit->GetMilitaryManager()->IsCommCloakWanted(unit);
		if (wantCloak != unit->GetUnit()->IsCloaked()) {
			TRY_UNIT(circuit, unit,
				unit->CmdCloak(wantCloak);
			)
		}
	}

	// apexearth: "sometimes it is hard to repair while they're moving." A unit
	// that keeps walking drags the repair out -- the repairer chases instead of
	// working. Once a repairer is assigned and in reach, stand still and let it
	// finish; the release check above puts the unit back in the fight.
	if ((repairer != nullptr)
		&& (circuit->GetTunable("apex_retreat_stand", 0.f) > 0.f)
		&& (unitPos.SqDistance2D(repairer->GetPos(frame))
			< SQUARE(circuit->GetTunable("apex_retreat_stand", 0.f))))
	{
		return;
	}

	if (unitPos.SqDistance2D(haven) > SQUARE(maxDist)) {
		// TODO: push MoveAction into unit? to avoid enemy fire
		TRY_UNIT(circuit, unit,
			unit->CmdMoveTo(haven, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 1);
		)
		// TODO: Add fail counter?
	} else {
		// apex: excluded the commander. This shortcut ends a retreat the
		// moment a builder is merely near its haven, if the team has 2 or
		// fewer workers left -- "we can't afford an idle builder, get back to
		// work" -- with no check that the haven is actually safe. For the
		// commander that fights directly against the script's own flee-
		// influence watchdog (rules_commander.as/events.as): forced back onto
		// retreat, travels near haven, immediately Recovered() here
		// regardless of danger, goes idle, re-forced ~3s later by the
		// watchdog, repeat -- measured 2026-08-15 firing continuously for a
		// full 28-minute match (noTask climbing in lockstep with the forced
		// counter, never settling). A low worker count is exactly when the
		// commander is most likely to BE one of only a few builders left,
		// so this condition is trivially satisfied in the scenario that
		// matters most.
		if (!cdef->IsRoleComm()
			&& (circuit->GetBindedRole(cdef->GetMainRole()) == ROLE_TYPE(BUILDER))
			&& (circuit->GetBuilderManager()->GetWorkerCount() <= 2))
		{
			Recovered(unit);
			return;
		}

		// TODO: push WaitAction into unit
		// CmdPatrolTo below is a one-point patrol: a there-and-back shuttle
		// that loops until something else claims the unit. Commanders are
		// excluded -- AiMakeTask's isComm section picks them up when idle,
		// same as GetRallyPos/GetRearHaven already carve them out here.
		if (!cdef->IsRoleComm() && /*cdef->GetDef()->IsAbleToAssist() || */cdef->IsAbleToRepair()) {
			AIFloat3 pos = unitPos;
			if (unit->GetUnit()->IsCloaked()) {
				pos += AIFloat3(SQUARE_SIZE * 2, 0, SQUARE_SIZE * 2);  // don't move, but assist if required
				CTerrainManager::CorrectPosition(pos);
			} else {
				const float size = SQUARE_SIZE * 16;
				CTerrainManager* terrainMgr = circuit->GetTerrainManager();
				float centerX = terrainMgr->GetTerrainWidth() / 2;
				float centerZ = terrainMgr->GetTerrainHeight() / 2;
				pos.x += (pos.x > centerX) ? size : -size;
				pos.z += (pos.z > centerZ) ? size : -size;
				AIFloat3 oldPos = pos;
				CTerrainManager::CorrectPosition(pos);
				if (oldPos.SqDistance2D(pos) > SQUARE_SIZE * SQUARE_SIZE) {
					pos = unitPos;
					pos.x += (pos.x > centerX) ? -size : size;
					pos.z += (pos.z > centerZ) ? -size : size;
				}
				CTerrainManager::TerrainPredicate predicate = [unitPos](const AIFloat3& p) {
					return unitPos.SqDistance2D(p) > SQUARE(SQUARE_SIZE * 8);
				};
				AIFloat3 freePos = terrainMgr->FindBuildSite(cdef, pos, maxDist, UNIT_NO_FACING, predicate, true);
//				AIFloat3 freePos = terrainMgr->FindSpringBuildSite(cdef, pos, maxDist, UNIT_NO_FACING, predicate);
				pos = utils::is_valid(freePos) ? freePos : pos;
			}
			TRY_UNIT(circuit, unit,
//				unit->CmdPriority(0);
				unit->CmdPatrolTo(pos);
			)
		}

		if (unit->GetTravelAct() != nullptr) {
			if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
				unit->GetTravelAct()->StateFinish();
			}
		}
		state = State::REGROUP;
	}
}

void CRetreatTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	if (State::REGROUP != state) {
		return;
	}
	state = State::ROAM;

	if (unit->GetTravelAct() == nullptr) {
		// NOTE: IsAttrBoost units don't get travel action on AssignTo
		int squareSize = manager->GetCircuit()->GetPathfinder()->GetSquareSize();
		CCircuitDef* cdef = unit->GetCircuitDef();
		ITravelAction* travelAction;
		if (cdef->IsAttrRetFight()) {
			travelAction = new CFightAction(unit, squareSize);
		} else {
			travelAction = new CMoveAction(unit, squareSize);
		}
		unit->PushTravelAct(travelAction);
		unit->SetAllowedToJump(cdef->IsAbleToJump() && !cdef->IsAttrNoJump());
	}
	if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
		unit->GetTravelAct()->StateActivate();
	}

	Start(unit);
}

void CRetreatTask::OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	RemoveAssignee(unit);
}

void CRetreatTask::CheckRepairer(CCircuitUnit* newRep)
{
	// A repair executor can reach this through IRepairTask::Execute while the
	// retreat has already shed its last assignee (DoneTask pending) --
	// *units.begin() on an empty set dereferenced end() and crashed a watched
	// game at 19:49 (2026-08-15, inlined IsRoleComm on garbage).
	if (units.empty()) {
		return;
	}
	CCircuitUnit* unit = *units.begin();
	if (unit->GetCircuitDef()->IsRoleComm()) {
		return;
	}

	if ((costQuery != nullptr) && (costQuery->GetState() != IPathQuery::State::READY)) {  // not ready
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& startPos = unit->GetPos(circuit->GetLastFrame());

	CPathFinder* pathfinder = circuit->GetPathfinder();
	costQuery = pathfinder->CreateCostMapQuery(
			unit, circuit->GetThreatMap(), startPos);

	CCircuitUnit::Id newRepId = newRep->GetId();
	pathfinder->RunQuery(circuit->GetScheduler().get(), costQuery, [this, newRepId](const IPathQuery* query) {
		CCircuitUnit* newRep = this->ValidateNewRepairer(query, newRepId);
		if (newRep != nullptr) {
			this->ApplyCostMap(static_cast<const CQueryCostMap*>(query), newRep);
		}
	});
}

void CRetreatTask::Dead()
{
	costQuery = nullptr;
	IUnitTask::Dead();
}

void CRetreatTask::Recovered(CCircuitUnit* unit)
{
	TRY_UNIT(manager->GetCircuit(), unit,
		if (unit->GetCircuitDef()->IsAbleToCloak()
			&& unit->GetCircuitDef()->GetCloakCost() > manager->GetCircuit()->GetEconomyManager()->GetAvgEnergyIncome() * 0.1f)
		{
			unit->CmdCloak(false);
		}
		unit->CmdSetFireState(unit->GetCircuitDef()->GetFireState());
	)

	RemoveAssignee(unit);
}

void CRetreatTask::ApplyPath(const CQueryPathSingle* query)
{
	const std::shared_ptr<CPathInfo>& pPath = query->GetPathInfo();
	CCircuitUnit* unit = query->GetUnit();
	// The query completed AFTER the unit's actions were cleared (task switch
	// or death): GetTravelAct() is null and SetPath through it crashed three
	// identical tournament games (2026-08-15). The path is simply unwanted.
	if ((unit == nullptr) || (unit->GetTravelAct() == nullptr)) {
		return;
	}

	if (pPath->posPath.empty()) {
		pPath->PushPos(query->GetEndPos(), manager->GetCircuit()->GetPathfinder());
	}
	if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
		unit->GetTravelAct()->SetPath(pPath);
	}
}

CCircuitUnit* CRetreatTask::ValidateNewRepairer(const IPathQuery* query, int newRepId) const
{
	CCircuitUnit* newRep = manager->GetCircuit()->GetTeamUnit(newRepId);
	if (newRep == nullptr) {
		return nullptr;
	}
	if (newRep->GetTask()->GetType() != IUnitTask::Type::BUILDER) {
		return nullptr;
	}
	IBuilderTask* taskB = static_cast<IBuilderTask*>(newRep->GetTask());
	if ((taskB->GetBuildType() != IBuilderTask::BuildType::REPAIR) || (taskB->GetTarget() != query->GetUnit())) {
		return nullptr;
	}
	return newRep;
}

void CRetreatTask::ApplyCostMap(const CQueryCostMap* query, CCircuitUnit* newRep)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CPathFinder* pathfinder = circuit->GetPathfinder();
	CCircuitUnit* unit = query->GetUnit();
	// The query completed AFTER the unit's actions were cleared (task switch
	// or death): GetTravelAct() is null and SetPath through it crashed three
	// identical tournament games (2026-08-15). The path is simply unwanted.
	if ((unit == nullptr) || (unit->GetTravelAct() == nullptr)) {
		return;
	}
	AIFloat3 endPos;
	float range;

	bool isRepairer = (repairer != nullptr);
	if (isRepairer) {
		endPos = repairer->GetPos(frame);
		range = pathfinder->GetSquareSize();
	} else {
		CFactoryManager* factoryMgr = circuit->GetFactoryManager();
		endPos = factoryMgr->GetClosestHaven(unit);
		if (!utils::is_valid(endPos)) {
			endPos = circuit->GetSetupManager()->GetBasePos();
		}
		range = factoryMgr->GetAssistRange() * 0.6f + pathfinder->GetSquareSize();
	}

	float prevCost = query->GetCostAt(endPos, range);
	if (isRepairer && repairer->GetCircuitDef()->IsMobile()) {
		prevCost /= 2;
	}

	endPos = unit->GetPos(frame);
	float nextCost = query->GetCostAt(endPos, range);
	if (unit->GetCircuitDef()->IsMobile()) {
		nextCost /= 2;
	}

	if (prevCost > nextCost) {
		SetRepairer(newRep);
	}
}

} // namespace circuit
