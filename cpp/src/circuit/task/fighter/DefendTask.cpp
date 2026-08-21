/*
 * DefendTask.cpp
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#include "task/fighter/DefendTask.h"
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
#include "unit/enemy/EnemyManager.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "OOAICallback.h"
#include "AISCommands.h"
#include "Drawer.h"

namespace circuit {

// How close a DEFEND task must be to the front to count as holding it, and how
// far past its own maxPower it must get before it may leave anyway. Above that
// the squad is surplus and is better spent attacking than standing still.
#define FRONT_HOLD_RANGE	1800.0f
// A DEFENCE POOL MUST BE ABLE TO REACH THE BAR IT IS HELD TO.
//
// CanAssignTo above stops a pool accepting units at maxPower, and this held it
// until attackPower >= maxPower * FRONT_HOLD_POWER -- so at 2.0 the release was
// unreachable except by merging two full pools, and every pool passes the
// `onFront` test by construction because UpdateDefenceTasks writes the anchor
// into `position` and this compares `position` against that same anchor.
// apexearth, watching a 400 metal/s player: "we have 257 of them and they all
// just stay in our base... none of them leave."
// At 1.0 the release matches the cap: a pool that is full is a pool that may go.
#define FRONT_HOLD_POWER	1.0f


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
	return (attackPower < maxPower) && (static_cast<CDefendTask*>(unit->GetTask())->GetPromote() == promote);
}

void CDefendTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);
	CCircuitDef* cdef = unit->GetCircuitDef();
	highestRange = std::max(highestRange, cdef->GetLosRadius());

	// See CAttackTask::AssignTo: only an escort that cannot join the squad's
	// fight follows the leader.
	if (cdef->IsRoleSupport() && !cdef->HasSurfToLand() && (leader != unit)) {
		unit->PushBack(new CSupportAction(unit));
	}

	int squareSize = manager->GetCircuit()->GetPathfinder()->GetSquareSize();
	ITravelAction* travelAction;
	// Formation travel (apexearth 2026-08-21): the whole ground squad marches on
	// synchronized-speed FIGHT orders, not per-unit moves -- engage together en
	// route, hold the line together. Wounded still leave: RetreatTask swaps the
	// travel act out (dropping the fight order), and the engagement standoff
	// ring still owns distance-keeping once fighting starts. Flyers keep MOVE.
	if ((cdef->IsAttrSiege() && (manager->GetCircuit()->GetTunable("apex_siege_fight", 1.f) > 0.f))
		|| (!cdef->IsAbleToFly()
			&& (manager->GetCircuit()->GetTunable("apex_fight_travel", 1.f) > 0.f)))
	{
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
	// apex: same solo-walk clamp as Merge -- a chase rewrites this task's
	// anchor to the target, and a fresh unit starting alone toward a deep
	// anchor is the single-unit attack stream. Deep anchors are approached
	// from the lane muster instead.
	AIFloat3 anchor = position;
	if (circuit->GetTunable("apex_defend_muster", 1.f) > 0.f) {
		const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
		const float deepR = circuit->GetMilitaryManager()->GetBaseDefRange() * 1.25f;
		const AIFloat3& front = circuit->GetFrontPos();
		if (utils::is_valid(front)
			&& (basePos.SqDistance2D(anchor) > SQUARE(deepR))
			&& (basePos.SqDistance2D(front) < basePos.SqDistance2D(anchor)))
		{
			anchor = front;
		}
	}
	AIFloat3 pos = utils::get_radial_pos(anchor, SQUARE_SIZE * 32);
	CTerrainManager::CorrectPosition(pos);
	AIFloat3 freePos = terrainMgr->FindBuildSite(unit->GetCircuitDef(), pos, 300.0f, UNIT_NO_FACING, true);
//	AIFloat3 freePos = terrainMgr->FindSpringBuildSite(unit->GetCircuitDef(), pos, 300.0f, UNIT_NO_FACING);
	pos = utils::is_valid(freePos) ? freePos : pos;

	// apex: transit is a MOVE, not a fight-walk. A fight order stops the unit
	// to trade with whatever it meets on the way, alone -- the measured DEFEND
	// death bucket. Engaged fighting is Attack()'s ring; the walk there should
	// not wade (apexearth: "using a fight order was incorrect. We need to be
	// using move commands along with set target").
	TRY_UNIT(circuit, unit,
		unit->CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, circuit->GetLastFrame() + FRAMES_PER_SEC * 60);
		unit->CmdWantedSpeed(NO_SPEED_LIMIT);
	)
}

void CDefendTask::Update()
{
	++updCount;

	/*
	 * Promote task if possible
	 */
	if (updCount % 32 == 1) {
		CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
		// Hold a share of the defenders ON the line. A DEFEND task promotes its
		// whole squad into an ATTACK the moment it is strong enough, which is
		// exactly what turns a garrison back into a roaming blob -- apexearth:
		// "the way that AI seems to work is it has these squads, and the squads
		// move around like blobs on the map, they don't necessarily have any
		// responsibility to cover any specific area".
		//
		// Only defenders sitting on the front are held; a DEFEND task somewhere
		// in the rear has nothing to cover and should still promote.
		CCircuitAI* circuitAI = manager->GetCircuit();
		const bool onFront = circuitAI->HasFrontPos()
				&& (position.SqDistance2D(circuitAI->GetFrontPos()) < SQUARE(FRONT_HOLD_RANGE));
		// THE HOLD MUST NOT SKIP THE MERGE BELOW. Returning here jumped over
		// GetMergeTask(), and merging is the ONLY way a defence pool can grow:
		// CMilitaryManager::Enqueue builds a fresh one-unit CDefendTask for every
		// unit, and DefaultMakeTask scans GUARD tasks only. So a pool whose units
		// were individually weaker than the bar could never combine to reach it
		// and stood in base for the rest of the game, while anything already over
		// the bar promoted and left alone.
		const bool held = onFront && (attackPower < maxPower * FRONT_HOLD_POWER);
		// The any-attack-exists shortcut fed solos: each promotion CREATES an
		// attack task, so after the first real squad -- alive or already dead --
		// every fresh 1-unit pool saw "an attack exists" and left alone, a
		// self-sustaining one-by-one stream (measured first-10m squad avg 1.3
		// vs enemy 2.6). Reinforcements now leave only at a real fraction of
		// the current quota, which tracks the living army.
		const float reinforceFrac = circuitAI->GetTunable("apex_reinforce_frac", 0.5f);
		const bool mayReinforce = !militaryMgr->GetTasks(check).empty()
				&& (attackPower >= maxPower * reinforceFrac);
		if (!held && ((attackPower >= maxPower) || mayReinforce)) {
			IFighterTask* task = militaryMgr->Enqueue(TaskF::Common(promote));
			decltype(units) tmpUnits = units;
			for (CCircuitUnit* unit : tmpUnits) {
				// Read BEFORE AssignTask: RemoveAssignee erases coward state.
				const bool coward = IsCoward(unit);
				manager->AssignTask(unit, task);
				if (coward) {
					task->MarkCoward(unit);
				}
			}
//			manager->DoneTask(this);  // NOTE: RemoveAssignee() will abort task
			return;
		}
	}

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

	// apex: a rookie must not walk SOLO to a leader already deep in enemy
	// ground -- that stream of single-unit arrivals was the top death bucket
	// of a watched game (73% of combat metal on DEFEND at fwd ~0.7, each dead
	// ~1s after disengaging at 9-15% hp). A deep pool takes reinforcements at
	// the army's lane anchor instead; the pool collects them when it moves as
	// a body.
	AIFloat3 musterPos = leadPos;
	if (circuit->GetTunable("apex_defend_muster", 1.f) > 0.f) {
		const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
		const float deepR = circuit->GetMilitaryManager()->GetBaseDefRange() * 1.25f;
		const AIFloat3& front = circuit->GetFrontPos();
		if (utils::is_valid(front)
			&& (basePos.SqDistance2D(leadPos) > SQUARE(deepR))
			&& (basePos.SqDistance2D(front) < basePos.SqDistance2D(leadPos)))
		{
			musterPos = front;
		}
	}

	const std::set<CCircuitUnit*>& rookies = task->GetAssignees();
	for (CCircuitUnit* unit : rookies) {
		unit->SetTask(this);

		// apex: rookies RUN to the group instead of fight-walking -- the
		// fight order made every merge a stream of solo engagements en route.
		TRY_UNIT(circuit, unit,
			unit->CmdMoveTo(musterPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame);
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
	const float maxPower = attackPower * powerMod * GetHealthScale();
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
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden() || (enemy->GetTasks().size() > 2)) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		// A DEFENCE SQUAD MUST FIGHT WHAT IS ON TOP OF IT. GetAllyDefendInflAt is
		// written only by our BUILDINGS -- CInfluenceMap::AddStaticArmed and
		// AddUnarmed; AddMobileArmed feeds drawAllyInfl and never this one -- so a
		// squad held away from the base is blind to whatever is shooting it.
		// `atUs` is the same reach Update() uses to decide ENGAGE.
		const bool atUs = (pos.SqDistance2D(ePos) < SQUARE(highestRange + 500.f));
		// apex: DEFENCE IS A POST, NOT A PURSUIT. Election is measured from
		// the ASSIGNED position only -- the first cut of this kept atUs
		// (proximity to the squad) as a self-defense clause, and it was the
		// remaining creep vector: a won fight advances the squad, the next
		// enemy falls inside its bubble, gets elected as "self-defense", and
		// the chain marched a victorious pool deeper until it died (watched
		// 2026-08-21). Units still auto-fire at whatever enters weapon range;
		// the TASK never re-targets off its own advanced ground.
		const bool postMode = circuit->GetTunable("apex_defend_post", 1.f) > 0.f;
		const bool electable = postMode
			? (position.SqDistance2D(ePos) < SQUARE(highestRange + 500.f))
			: atUs;
		if ((!electable && (inflMap->GetAllyDefendInflAt(ePos) < INFL_EPS))
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		const float sqEBDist = basePos.SqDistance2D(ePos);
		// apex: the home-fight allowance was 4x, PER FRAGMENT -- every fresh
		// unit off the factory took its own 4:1 fight against the intruder and
		// died, so under attack the army trickled into the grinder and never
		// rebuilt (apexearth: "we just continuously let them die... we need
		// time to build up our army to match what's up there. 1.2x"). At 1.2
		// a pool engages only near parity; refusals fall back to the front
		// posts, which is where the pool accumulates until it matches.
		float checkPower = maxPower;
		if ((sqEBDist < sqBaseRange) || atUs) {
			checkPower *= circuit->GetTunable("apex_defend_home_odds", 1.2f);
		}
		// The threat map reads ~0 almost everywhere, so the old
		// `checkPower <= GetThreatAt` test never refused anything and the
		// multiplier was decorative. Enemy GROUP influence is the live layer.
		float eThreat = threatMap->GetThreatAt(ePos);
		{
			float localInfl = .0f;
			const std::vector<CEnemyManager::SEnemyGroup>& groups =
					circuit->GetEnemyManager()->GetEnemyGroups();
			for (const CEnemyManager::SEnemyGroup& g : groups) {
				if (g.pos.SqDistance2D(ePos) < SQUARE(800.f)) {
					localInfl += g.influence;
				}
			}
			eThreat = std::max(eThreat, localInfl);
		}
		if (checkPower <= eThreat) {
			continue;
		}
		// PROPORTIONAL RESPONSE. Line 355 below rewrites this task's anchor to
		// the chosen target, so chasing is the WHOLE pool walking there -- and
		// the nearest-first choice is value-blind, so a two-raider ping in the
		// rear pulled every massed pool off the line (apexearth: "I see us move
		// our entire army way in the back to chase down some petty raiders...
		// then the enemy just walks into our base and crushes us"). A pool only
		// walks for a threat worth a real fraction of its own strength; fresh
		// small pools still pass this gate and peel off to handle intruders,
		// and anything already in contact (atUs) is always fought.
		if (!atUs && (eThreat < attackPower
				* circuit->GetTunable("apex_chase_min_ratio", 0.15f)))
		{
			continue;
		}
		// A SOLO POOL DOES NOT CHASE DEEP. The manager spawns fresh 1-unit
		// defend tasks, and after the muster clamp brings one to the lane it
		// is its own leader -- a lone unit electing a target past the deep
		// ring IS the single-unit attack stream (watched 2026-08-21: 73% of
		// combat metal, defend at fwd ~0.7, dead 1s after disengage). It
		// still fights whatever is on top of it (atUs) or inside the ring;
		// travelling deep needs company. apex_defend_solo_deep=1 restores
		// the old behavior.
		if (!atUs && (units.size() <= 1)
			&& (circuit->GetTunable("apex_defend_solo_deep", 0.f) <= 0.f))
		{
			const AIFloat3& basePos2 = circuit->GetSetupManager()->GetBasePos();
			const float deepR = circuit->GetMilitaryManager()->GetBaseDefRange() * 1.25f;
			if (basePos2.SqDistance2D(ePos) > SQUARE(deepR)) {
				continue;
			}
		}
		// The eThreat gate above reads the surf threat map, which measures ~0
		// almost everywhere -- a Punisher line rates as empty ground and the
		// pool walks into it. Enemy GROUP influence is the live layer (the same
		// data AttackTask's strength test reads), so this can refuse walking
		// the pool at ground whose standing groups outweigh it. Scoped away
		// from home: what is on top of us (atUs) or inside the base ring is
		// fought regardless. DEFAULT OFF: at margins 1.0 and 0.6 it traded
		// losses for timeout draws without winning more (see CHANGES.md
		// 2026-08-21); the lever stays for experiments.
		const float engageMargin = circuit->GetTunable("apex_defend_engage_margin", 0.f);
		if ((engageMargin > 0.f) && !atUs && (sqEBDist >= sqBaseRange)) {
			float localInfl = .0f;
			const std::vector<CEnemyManager::SEnemyGroup>& groups =
					circuit->GetEnemyManager()->GetEnemyGroups();
			for (const CEnemyManager::SEnemyGroup& g : groups) {
				if (g.pos.SqDistance2D(ePos) < SQUARE(800.f)) {
					localInfl += g.influence;
				}
			}
			if ((localInfl > .0f) && (maxPower < localInfl * engageMargin)) {
				continue;
			}
		}

		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			if (((edef->GetCategory() & canTargetCat) == 0)
				|| ((edef->GetCategory() & noChaseCat) != 0)
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()
				|| (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())))  // notAA
			{
				continue;
			}
			float elevation = map->GetElevationAt(ePos.x, ePos.z);
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
		if (minSqDist > sqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
		enemyPositions.push_back(ePos);
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		// apex: the anchor does NOT follow the target. This rewrite advanced
		// the post to every elected enemy, so each chase re-based the pool on
		// its new ground and the next election reached further -- the creep
		// that turned defense into pursuit. The post stays where it was
		// assigned; when the enemy flees past reach, the no-target fallback
		// walks the pool back to a front post instead of following.
		if (circuit->GetTunable("apex_defend_post", 1.f) <= 0.f) {
			position = GetTarget()->GetPos();
		}
	}
	if (enemyPositions.empty()) {
		return false;
	}

	return true;
	// Return: target, startPos=leader->pos, enemyPositions
}

void CDefendTask::ApplyTargetPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		// apex: intent pings for the watching player (apexearth: "Can we have
		// our squads ping on the map so that I can understand what they're
		// thinking when they're moving?"). apex_ping=1 only; throttled by the
		// path grant, which fires on decision, not per tick.
		CCircuitAI* circuit = manager->GetCircuit();
		if (circuit->GetTunable("apex_ping", 0.f) > 0.f) {
			circuit->GetDrawer()->AddPoint(leader->GetLastPos(),
					utils::string_format("DEF chase n=%d", (int)units.size()).c_str());
		}
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
			// apex: the pool marches TOGETHER. Uncapped, the fast units reach
			// the front first and fight alone -- apexearth: "we often have our
			// faster units running in and engaging the enemy army first, they
			// die, then the slower units in the back either fight and die, or
			// are already running away... move at the speed of the slowest
			// unit in the group. This helps them to all stay together."
			CCircuitAI* circuit = manager->GetCircuit();
			if (circuit->GetTunable("apex_ping", 0.f) > 0.f) {
				circuit->GetDrawer()->AddPoint(leader->GetLastPos(),
						utils::string_format("DEF march n=%d", (int)units.size()).c_str());
			}
			ActivePath(lowestSpeed);
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
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdMoveTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
