/*
 * AttackTask.cpp
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#include "task/fighter/AttackTask.h"
#include "map/InfluenceMap.h"
#include "map/MapManager.h"
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

#include "AISCommands.h"
#include "Drawer.h"
#include "Log.h"

namespace circuit {

using namespace springai;
using namespace terrain;

// How much more an attack path pays for threatened ground than any other path.
//
// maxThreat is only a CEILING -- it refuses tiles above it, and a strong squad
// gets a high one, so the cheapest route stays the short one straight up the
// middle. What decides the shape of the route is the per-tile cost, which is a
// flat 2x threat for every other query in the AI.
//
// 4 -> 2 on 2026-08-07. At 4 an attack paid so much for defended ground that a
// long quiet route round the map edge beat the short one through the middle --
// the previous comment here predicted exactly that and treated it as the point.
// Watched live, apexearth judged the result: "I see purple and teal sending
// army around the back edge of the map rather than towards the front line...
// wasteful movement."
//
// The detour is not free even when it avoids damage: the army is out of
// position for the whole walk, arrives piecemeal, and on a large map may never
// arrive at all. Back to the AI-wide 2, so defended ground still costs more
// than open ground without the edge run being cheaper than the fight.
static constexpr float ATTACK_THREAT_MOD = 2.f;

// Multiplier on the path's threat CEILING (see the query in Update()). The
// ceiling decides which tiles exist for the pathfinder at all, so it, not the
// cost above, is what produces map-edge detours when it is tight.
static constexpr float ATTACK_CEILING_MOD = 3.f;

// Chosen so CheckMergeTask's own MAX_TRAVEL_SEC * speed budget (~2700 elmos for
// a T1 bot) becomes the binding limit instead of this. The air tasks were raised
// from the same 1000 for the same reason.
#define ASSIGN_RADIUS	3000.f
// A squad moves at its SLOWEST member's speed, so this decides how far apart
// two units may be in speed before they are made to fight separately.
//
// 1.5 by apexearth's call, 2026-08-19, watching a squad stalled in the backline
// keeping pace with a Behemoth. The previous 3.5 was set to let Legion's
// legstr 84 / leginc 24 pair squad together; at 1.5 that pair splits again and
// leginc fights alone. The slow-heavy stall was judged the worse of the two.
#define SQUAD_SPEED_RATIO	1.5f

// Target-preference multipliers. The selection metric is a squared distance, so
// 4.0 means an artillery piece is preferred over a closer ordinary unit until it
// is about twice as far away.
// How far ahead we must be before committing. The test was `maxPower <=
// influence * scale`, i.e. a 1% edge sent the whole squad -- so anything not yet
// seen flipped the outcome AFTER the commitment, and a slow-turning squad paid
// for the reversal on the way out. apexearth: "We realize we're in danger too
// late on our units... we head in ... panic... turn around... die", and earlier,
// "if you take any fight you're gonna lose, then you probably did the wrong
// thing". Applies to CAttackTask only: raids are meant to trade units for
// economy and keep their own thresholds.
// Extra distance at which a squad switches from travelling to formation, so it
// unfolds out of column before the enemy's guns bear. Roughly a T2 weapon range.
#define DEPLOY_SLACK		700.f

// 1.80 -> 1.35 on 2026-08-07, from apexearth's live multiplayer game.
//
// 1.80 demanded 80% more power than whatever was defending a target. Measured
// in that game (map Project SD-129, 10 Apex AIs, 27 min): 492 engage decisions,
// every one reporting TAKE -- but 3,973 candidate groups refused as too strong
// first, a mean of 8 per decision and up to 26 in a single one. Every sample
// logged edge=0.00, which means the target finally accepted had essentially no
// defending influence at all.
//
// So the AI was not choosing bad fights, it was refusing all of them and
// attacking empty ground. apexearth: "we aren't aggressive enough vs humans
// early on, and we tend to run when we really shouldn't." Against a human who
// masses and pushes, never contesting a defended position loses by default.
//
// Not dropped to 1.0: the history in this file records that the original test
// was effectively margin 1.0 and engaged on a coin flip, which is its own
// failure. 1.35 still asks for a real edge, roughly halving the surplus
// demanded rather than removing it.
#define ENGAGE_MARGIN		1.35f
// The bar to CONTINUE a fight, against ENGAGE_MARGIN's bar to start one.
// Deliberately below 1.0: once contact is made the damage already dealt is sunk,
// and TradeScaledMargin's inputs are generated BY this fight -- our losses land
// before our kills, so the trade term tightens at exactly the moment finishing
// is the right call. Measured: 13 of 13 engagements in one game were authorised
// against need=0 enemy influence, then re-tested at 1 Hz against a real army.
#define CONTINUE_MARGIN		0.85f
// How far a joining unit may be from the squad leader before it is told to close
// on the squad rather than take the squad's route to the enemy. Roughly one
// screen: nearer than this and it is already part of the group.
#define JOIN_RALLY_DIST		600.f
// A target this far gone is worth finishing rather than trading away.
#define FINISH_HP_FRAC		0.35f
#define FINISH_PRIORITY		3.0f

// How much harder the engage test gets when we are losing trades.
//
// apexearth: "if our recent k/d is low we stop attacking so much, we start to
// be more careful and require greater odds to attack." The margin below is a
// fixed 1.80 regardless of whether the last ten fights went well or badly --
// this scales it by the recent kill/loss ratio (CCircuitAI::GetRecentTradeRatio,
// by metal value, decayed). Ratio 1.0 leaves the margin exactly as it was, so
// an even game behaves identically to before; the clamps stop a streak either
// way from running away with it.
//
// Deliberately asymmetric. Winning trades relaxes the demand only slightly
// (down to 0.9x) because "we are winning" is the state where overreach is
// cheapest to punish; losing tightens it up to 1.6x, which is the behaviour
// actually asked for. This is a MULTIPLIER on a margin, not a new rule that
// spends anything -- it only ever changes which fights get refused.
#define TRADE_MARGIN_MIN	0.90f
// THE PASSIVE HALF IS GONE. At 1.60 this was not feedback, it was a constant:
// the windowed trade ratio sat below 0.63 from minute 16 to 38 of a measured
// game, so 1/ratio pinned at the ceiling and the bar to start any fight sat at
// ENGAGE_MARGIN * 1.60 = 2.16. We demanded better than 2:1 odds, all game.
//
// Worse, it is a spiral in the wrong direction: losing trades raises the bar,
// the higher bar refuses fights, refusing fights cedes ground and loses more.
// And the no-data branch above returns ENGAGE_MARGIN * TRADE_MARGIN_MAX -- so
// before a single trade had happened, at game start, we were already at maximum
// caution.
//
// At 1.0 the ratio can only ever make us MORE aggressive (TRADE_MARGIN_MIN 0.90
// still applies when we are trading well) and never more passive. The useful
// direction is kept, the spiral is deleted, and "no information" now means
// neutral instead of maximally afraid.
// apexearth: "we are too cowardly against attacking some enemy bases.... we
// totally could win and we backoff" and "maybe we need to ditch that thing that
// makes us more passive?"
#define TRADE_MARGIN_MAX	1.00f

static inline float TradeScaledMargin(circuit::CCircuitAI* circuit)
{
	const float ratio = circuit->GetRecentTradeRatio();
	if (ratio <= 0.f) {
		return ENGAGE_MARGIN * TRADE_MARGIN_MAX;
	}
	// Demand scales with 1/ratio: trading at 0.5 asks for twice the odds
	// before the clamp, trading at 2.0 asks for a little less than before.
	float scale = 1.f / ratio;
	if (scale < TRADE_MARGIN_MIN) scale = TRADE_MARGIN_MIN;
	if (scale > TRADE_MARGIN_MAX) scale = TRADE_MARGIN_MAX;
	// Team push multiplier, set from script (Military::UpdateTeamPush). A
	// coordinated all-in is the one time accepting worse odds is correct: the
	// whole ally team commits at once, so the local odds understate what is
	// actually arriving.
	return ENGAGE_MARGIN * scale * circuit->GetEngageBoost();
}

// Radius around a target within which OTHER enemy groups count as defending it.
// Measured at 1800: 1,738 target groups refused against 29 engagements taken in
// a single 4v4 game -- on a 16x12 map that radius sweeps most of the board, so
// every target looked defended by the entire enemy army and squads fell back
// home having found nothing acceptable. apexearth: "purple retreated its
// entire army back into its base". 800 is one T2 weapon range: close enough
// that the army really is covering the target.
#define NEARBY_ENEMY_DIST	800.f

#define ARTY_PRIORITY		4.0f
#define LONG_RANGE_PRIORITY	2.0f
#define LONG_RANGE_MULT		1.3f   // "outranges us" -- 30% past our own reach

// A target faster than the squad by this much is treated as uncatchable, and
// its preference is multiplied by the penalty below. Not a veto: it still gets
// shot if it comes to us.
#define CHASE_SPEED_RATIO	1.15f
#define UNCATCHABLE_PENALTY	0.25f
// apex: an undefended enemy structure that cannot shoot back is the best trade a
// raid can make -- it removes income permanently and costs nothing to take. The
// metric below is a DISTANCE, so a target with no priority competes on nearness
// alone, and the enemy army in the middle is always nearer than the mex behind
// it. apexearth: "we have an opportunity to freely kill an enemy mex and we walk
// away in favor of fighting enemy army in the middle... thats how bad we are at
// raiding."
#define FREE_ECO_PRIORITY	5.0f
// apex: the other half of the same doctrine. A static gun cannot be caught out of
// position, never stops shooting, and gives nothing back when it dies -- so
// walking a squad into the enemy's defensive line is the worst trade on the
// board, and it competed on distance like everything else because their wall
// sits between us and their base. apexearth: "we send them at the enemy wall to
// fight.... why do we do that? this makes no sense. We should be attacking their
// mexes, their economy... and DEFENDING against their army."
// A penalty, not a veto -- a gun shelling our own ground still dies, via isHome.
#define ENEMY_WALL_PENALTY	0.2f
// apex: metal denied per hitpoint, above which an undefended structure counts as
// a SOFT target and is worth going out of the way for. Read from the defs rather
// than guessed: converter 380m/445hp = 0.85, fusion 4300/4450 = 0.97, solar
// 155/340 = 0.46, advanced solar 350/1130 = 0.31. So this cleanly separates the
// things that die in a raid pass from the things that soak one.
#define SOFT_ECO_DENSITY	0.50f
#define SOFT_ECO_BONUS		2.0f
// apex: THE DIVE. A squad already standing in the enemy's own influence is past
// their wall -- from there a fat unarmed structure (advanced converter, fusion,
// AFUS) outranks every military target, guarded or not, and the local-army
// refusal is waived for it: the dive is a commitment, the same shape as the
// juggernaut charge. apexearth: "If we know we are near the enemy base, we
// should dive straight into it and prioritize targetting their economy. Don't
// get distracted by military or towers if an advanced converter or afus is in
// range." Cost floor is a tunable; 350 clears the advanced converter (380) and
// everything above it while leaving solars and plain mexes to the ordinary
// free-eco ordering.
#define DIVE_ECO_PRIORITY	8.0f
// apex: how much better a new candidate must look before a squad abandons the
// target it already chose. FindTarget re-runs every pass and scores purely on
// the CURRENT geometry, so as the squad moved the ordering churned and it
// changed its mind repeatedly -- walking a few steps toward one target, then
// another, then back -- which reads exactly as indecision and covers no ground.
// apexearth: "it wants to go run around the enemy, but then its like nahhh ill
// go back to my base... nah ill attack this guy.... nah ill go behind them all!
// ... totally screws up its effectiveness as it can't make up its mind and just
// runs in circles on the spot."
// The metric is a distance and lower wins, so a bonus to the incumbent is a
// DIVISOR on it. Commitment, not blindness: something 40% better still wins.
#define TARGET_STICKY		1.4f

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
	// Cortex ground speeds run 37.5 (Sumo) to 54 (Banisher) against the Mammoth's
	// 22.5, so at 1.5 the Mammoth fails against every one of them and can only
	// ever hold a task of its own. Same for the other slow heavies. The squad
	// still moves at the pace of its slowest member either way; the choice this
	// makes is whether the heavy walks in with company or by itself.
	if (speedLeader * SQUAD_SPEED_RATIO < speedUnit) {
		return false;
	}

	const int frame = manager->GetCircuit()->GetLastFrame();
	// This bounds both joining and MERGING -- CheckMergeTask calls
	// candidate->CanAssignTo(leader), so it, not the MAX_TRAVEL_SEC budget there,
	// is what decides whether two squads may combine. At 1000 a unit leaving a
	// factory could not join a squad already at the front on any large map, and
	// two squads a short walk apart could not merge; both had to fight alone.
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(ASSIGN_RADIUS)) {
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

	// A UNIT THAT CAN SHOOT WHAT THE SQUAD SHOOTS FIGHTS IN THE FORMATION; ONLY
	// AN ESCORT THAT CANNOT FOLLOWS THE LEADER.
	//
	// CSupportAction is blocking, and ISquadTask::Attack and ActivePath both skip
	// a unit whose Blocker() is set, so attaching it hands the unit's position to
	// the action -- and the action has no position logic for anything armed:
	// `reach` is only ever set inside its own `!IsAttacker()` branch, leaving
	// `pos = leaderPos` and a 64-elmo stop radius.
	//
	// IsRoleSupport() is the role MASK, and CCircuitDef::AddRole ORs in the
	// BINDED role, so it is true for the "support" ATTRIBUTE and for every custom
	// role bound to SUPPORT -- not just for things that escort.
	//
	// HasSurfToLand() rather than IsAttacker(): pure AA still has DPS, and an AA
	// escort put on the arc of a ground fight it cannot join would be standing on
	// the front rank for nothing.
	if (cdef->IsRoleSupport() && !cdef->HasSurfToLand()) {
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
	// A UNIT JOINS THE SQUAD, NOT THE TARGET.
	//
	// This did one of two things and neither was joining. While the squad was
	// REGROUP or ENGAGE it returned immediately, leaving the new unit standing
	// wherever it was built -- inside enemy fire if the fight had moved there.
	// Otherwise it handed the unit the squad's OWN path to the enemy, which the
	// unit then walked alone, arriving at the objective by itself and dying
	// there. apexearth: "after I see some other units get to the place where we
	// were attacking (lingering join order?) and they get picked off one by one
	// a bit... we stand within enemy fire and are super indecisive."
	//
	// Send it to the leader instead. One move order, no path query -- the squad
	// logic takes over on the next Update once it is close enough to count as
	// part of the group, and this is exactly the case IsMustRegroup is measuring.
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	if ((leader != nullptr) && (unit != leader)) {
		const AIFloat3& leaderPos = leader->GetPos(frame);
		// ...unless it is standing on OUR ground with an enemy on it. Rallying is
		// "go join the squad", and if home is being attacked, marching away from
		// the attack to reach a squad somewhere else is the worst answer
		// available. apexearth: "imagine an enemy is attacking our base... is this
		// logic making our army actively abandon our base?" -- a fair question
		// about a change I had just made, and the answer was yes.
		// GetAllyDefendInflAt is fed by our own buildings, so it means "we live
		// here"; enemy influence on the same tile means they are here too. Leave
		// the unit unordered: the defend machinery re-evaluates it next pass,
		// which is what should own a unit standing in a fight at home.
		CInfluenceMap* inflMap = circuit->GetInflMap();
		const AIFloat3& here = unit->GetPos(frame);
		const bool homeUnderAttack = (inflMap->GetAllyDefendInflAt(here) > INFL_EPS)
				&& (inflMap->GetEnemyInflAt(here) > INFL_EPS);
		if (homeUnderAttack) {
			return;
		}
		if (here.SqDistance2D(leaderPos) > SQUARE(JOIN_RALLY_DIST)) {
			TRY_UNIT(circuit, unit,
				unit->CmdMoveTo(leaderPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY,
						frame + FRAMES_PER_SEC * 60);
			)
			return;
		}
	}
	if ((State::REGROUP == state) || (State::ENGAGE == state)) {
		return;
	}
	if (!pPath->posPath.empty()) {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
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
	 * apex: THE ATTACK CLOSES WHEN IT FAILS. Health-based withdrawal cannot
	 * see a lost fight -- the survivors of a wiped squad are often at full HP,
	 * read "healthy", and keep pressing. When the task holds a fraction of the
	 * power it ever held, the fight is over: abort, so the survivors re-pool
	 * at home and leave with the next real group (the massing bar holds them
	 * there while the enemy out-masses us). Chargers deliver by arriving, and
	 * a declared team push is committed; both keep pressing.
	 */
	{
		CCircuitAI* circuit = manager->GetCircuit();
		peakPower = std::max(peakPower, attackPower);
		const CCircuitDef* ldef = (leader != nullptr) ? leader->GetCircuitDef() : nullptr;
		const bool isCharger = (ldef != nullptr) && ldef->IsCharger();
		if (!isCharger && !circuit->IsCommitted() && (peakPower > 1.f)
			&& (attackPower < peakPower * circuit->GetTunable("apex_attack_break", 0.4f)))
		{
			circuit->LOG("apex: attack broken -- power %.0f of peak %.0f, survivors re-pool",
					attackPower, peakPower);
			if ((leader != nullptr) && (circuit->GetTunable("apex_ping", 0.f) > 0.f)) {
				circuit->GetDrawer()->AddPoint(leader->GetLastPos(), "ATK broken");
			}
			manager->AbortTask(this);
			return;
		}
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
	// Captured BEFORE FindTarget, which clears the target, and before `state` is
	// reset to ROAM below -- ENGAGE is not latched, it is re-derived every pass.
	const bool wasEngagedThisPass = (State::ENGAGE == state);
//	if (circuit->GetInflMap()->GetInfluenceAt(startPos) < -INFL_EPS) {
//		SetTarget(nullptr);  // FIXME: back-forths group
//	} else {
		FindTarget();
//	}

	state = State::ROAM;
	if (GetTarget() != nullptr) {
		// DEPLOY BEFORE CONTACT. ENGAGE is what calls Attack(), which is the only
		// thing that spreads the squad into range-keyed arcs. Triggering it at
		// weapon range + 100 means the squad is still in line-ahead on its path
		// when it enters the enemy's range: they are already in line-abreast with
		// every gun bearing, we arrive as a column with only the leaders able to
		// fire. apexearth: "if your spot is shaped like a line, and then they're
		// shaped like the t on our line, like, in naval battles, you know, the
		// whole crossing the t concept, that's the kind of stuff I see."
		//
		// DEPLOY_SLACK buys the distance to unfold from column into line first.
		// It only changes WHEN the existing formation code runs, not its shape --
		// the arc widths and per-row ranges are untouched.
		const float base = (circuit->GetInflMap()->GetAllyDefendInflAt(position) > INFL_EPS) ? 300.f : 100.f;
		const float slack = base + DEPLOY_SLACK;
		if (position.SqDistance2D(startPos) < SQUARE(highestRange + slack)) {
			int xs, ys, xe, ye;
			circuit->GetPathfinder()->Pos2PathXY(startPos, &xs, &ys);
			circuit->GetPathfinder()->Pos2PathXY(position, &xe, &ye);
			if (GetHitTest()(int2(xs, ys), int2(xe, ye))) {
				// apex: ASSEMBLE BEFORE THE FIGHT STARTS. DEPLOY_SLACK unfolds
				// the column into a line, but ENGAGE keys on the LEADER's
				// distance -- units strung back along the path get their arc
				// slots and trickle into a fight already lost by the front.
				// apexearth: "you need to organize your units so that all of
				// them enter the fight at about the same time." Hold the
				// units already in formation (StateWait) while stragglers
				// close to the same cohesion bound IsMustRegroup uses; a
				// bounded budget and an under-fire test keep this from
				// dithering: standing in enemy threat means the fight has
				// already started, and waiting in it is worse than engaging.
				const CCircuitDef* ldef = leader->GetCircuitDef();
				const bool skipAssemble = (units.size() < 3)
						|| ldef->IsPlane() || ldef->IsCharger()
						|| (circuit->GetTunable("apex_assemble", 1.f) <= 0.f);
				if (!skipAssemble) {
					CThreatMap* threatMap = circuit->GetThreatMap();
					threatMap->SetThreatType(leader);
					const bool underFire = threatMap->GetThreatAt(startPos) >= THREAT_MIN;
					const float bound = std::max<float>(
							SQUARE_SIZE * 8 * units.size(), highestRange);
					float worstSq = 0.f;
					for (CCircuitUnit* unit : units) {
						worstSq = std::max(worstSq,
								startPos.SqDistance2D(unit->GetPos(frame)));
					}
					// apex: size the cohesion bound from DATA. The gate fired
					// zero times in four smoke games, and this line says
					// whether that is because squads genuinely arrive tight
					// or because the bound above is looser than real stretch.
					if (frame >= lastEngageLog + FRAMES_PER_SEC * 20) {
						lastEngageLog = frame;
						circuit->LOG("apex: engage-stretch n=%d stretch=%.0f "
								"bound=%.0f underfire=%d",
								(int)units.size(), std::sqrt(worstSq), bound,
								underFire ? 1 : 0);
					}
					const bool stretched = worstSq > SQUARE(bound);
					if (stretched && !underFire) {
						if (assembleUntil < 0) {
							assembleUntil = frame + FRAMES_PER_SEC
									* (int)circuit->GetTunable("apex_assemble_secs", 8.f);
							circuit->LOG("apex: assembling before contact -- "
									"stretch %.0f over bound %.0f, %d units",
									std::sqrt(worstSq), bound, (int)units.size());
							if (circuit->GetTunable("apex_ping", 0.f) > 0.f) {
								circuit->GetDrawer()->AddPoint(startPos,
										utils::string_format("ASSEMBLE n=%d", (int)units.size()).c_str());
							}
						}
						if (frame < assembleUntil) {
							const float sqBound = SQUARE(bound);
							for (CCircuitUnit* unit : units) {
								if (unit->Blocker() != nullptr) {
									continue;
								}
								// In formation: stand. Stragglers: keep coming.
								if ((startPos.SqDistance2D(unit->GetPos(frame)) <= sqBound)
									&& (unit->GetTravelAct() != nullptr))
								{
									unit->GetTravelAct()->StateWait();
								}
							}
							return;
						}
					} else {
						assembleUntil = -1;
					}
				}
				assembleUntil = -1;
				if (circuit->GetTunable("apex_ping", 0.f) > 0.f) {
					circuit->GetDrawer()->AddPoint(startPos,
							utils::string_format("ATK engage n=%d", (int)units.size()).c_str());
				}
				state = State::ENGAGE;
				Attack(frame);
				return;
			}
		}
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (GetTarget() == nullptr) {
		// Do NOT issue a walk-to-the-front order out of a fight we were in one
		// tick ago -- that is the visible "turn around and run away".
		if (wasEngagedThisPass) {
			return;
		}
		FallbackFrontPos();
		return;
	}

	// apex: A SHARE OF ATTACKS GO AROUND THE SIDE. Every squad pathed the
	// cheapest line to its target, which at equal threat is the middle --
	// apexearth 2026-08-19: "I don't see us trying to attack the enemy from
	// around the side... always straight up the middle. 0 strategy in that."
	// Rolled once per task like the charge: a flanking squad first walks a
	// waypoint offset perpendicular from the midpoint of its approach, then
	// turns onto the real target. Chargers never flank (distance is their
	// whole budget), and the via is dropped once reached or once engaged.
	if (flankRoll < 0) {
		const int pct = (int)circuit->GetTunable("apex_flank_pct", 35.f);
		flankRoll = (rand() % 100 < pct) ? ((rand() % 2 == 0) ? 1 : 2) : 0;
	}
	AIFloat3 endPos = position;
	if (flankRoll > 0) {
		if (!utils::is_valid(flankVia)) {
			AIFloat3 dir = position - startPos;
			const float dist = sqrtf(dir.SqLength2D());
			if (dist > circuit->GetTunable("apex_flank_min_dist", 1200.f)) {
				dir.SafeNormalize2D();
				const AIFloat3 perp = (flankRoll == 1)
						? AIFloat3(-dir.z, 0.f, dir.x)
						: AIFloat3(dir.z, 0.f, -dir.x);
				AIFloat3 via = (startPos + position) * 0.5f
						+ perp * (dist * circuit->GetTunable("apex_flank_frac", 0.45f));
				CTerrainManager::CorrectPosition(via);
				flankVia = via;
			}
		}
		if (utils::is_valid(flankVia)) {
			if (startPos.SqDistance2D(flankVia) < SQUARE(500.f)) {
				flankVia = AIFloat3(-RgtVector);  // via reached: turn onto the target
				flankRoll = 0;
			} else {
				endPos = flankVia;
			}
		}
	}
	CPathFinder* pathfinder = circuit->GetPathfinder();
	const float eps = pathfinder->GetSquareSize();
	const float pathRange = std::max(highestRange - eps, eps);

	// maxThreat is a CEILING: tiles above it are impassable, not merely
	// expensive. Set from the squad's own power, a modest squad forbids most of
	// the direct route and the pathfinder takes whatever is left -- which is the
	// long way round the map edge. apexearth, watching live: "I see purple and
	// teal sending army around the back edge of the map rather than towards the
	// front line... they were going, like, twenty times the distance they needed
	// to around enemy defenses."
	//
	// A detour that size is not caution, it is removal: the army is out of
	// position for the whole walk, arrives piecemeal, and on a big map may never
	// arrive. ATTACK_CEILING_MOD widens what a squad will path THROUGH. The
	// engage test still decides whether to actually take the fight when it gets
	// there -- that judgement belongs there, not in the pathfinder silently
	// making the short route non-existent.
	//
	// A CHARGER ignores both. See IsChargeDef: a Behemoth is 20,000 metal of
	// walking bomb that delivers its value by ARRIVING, and it walks at ~16
	// elmos/s -- the slowest thing we field. A route that trades distance for
	// safety is the one trade it can never afford, and the threat it is dodging
	// is threat it is built to eat. apexearth: "these are extremely powerful
	// units which should be braver than usual and attack enemy bases... the
	// attack around the edge of the map strategy is normally good but behemoths
	// are terribly slow so its less good for them."
	//
	// threatMod 0 makes the cost pure distance (see CPathFinder::GetThreatFun)
	// and the ceiling is out of reach of any real tile, so the route is the
	// short one through the front. CHARGE_DIRECT_PCT leaves a minority still
	// going round, which is the "small allotment to that side attack" -- rolled
	// once per task, so the squad commits to one route rather than oscillating.
	if (chargeRoll < 0) {
		chargeRoll = (rand() % 100 < CHARGE_DIRECT_PCT) ? 1 : 0;
	}
	// The killing blow (script blackboard "kill") turns EVERY squad into a
	// charger: with the enemy clearly beaten, threat-detour pathing is what an
	// enormous army orbiting a doomsday gun's range ring looks like -- the
	// caution the ceiling buys is for games still in doubt.
	const bool overrun = circuit->ReadTeamValue(circuit->GetTeamId(), "kill", 0.f) > 0.f;
	const bool isCharge = overrun || ((chargeRoll == 1)
			&& ISquadTask::IsChargeDef(leader->GetCircuitDef()));
	// Each risk level halves the threat cost and doubles the ceiling -- more
	// accepted risk, never zero care (that stays the chargers' privilege).
	const float riskDiv = float(1 << riskLevel);
	const float threatCeiling = isCharge
			? CHARGE_THREAT_CEILING
			: (ATTACK_CEILING_MOD * riskDiv * attackPower
					/ circuit->GetMilitaryManager()->GetRangeUnitCountCompensatorScale());
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, endPos, pathRange, GetHitTest(),
			threatCeiling,
			false, isCharge
					// apex: NOT quite zero. A Behemoth's D-gun one-shots even a
					// charging T3, and Behemoths walk at ~16 elmos/s -- the one
					// threat a charger should not eat is also the cheapest to
					// walk around. The script doubles corjugg's threat kernel,
					// so at a small mod an enemy Behemoth bends the route a few
					// hundred elmos while ordinary porc leaves it straight.
					? circuit->GetTunable("apex_charge_threat_mod", 0.1f)
					: (ATTACK_THREAT_MOD / riskDiv));
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CAttackTask::OnUnitIdle(CCircuitUnit* unit)
{
	ISquadTask::OnUnitIdle(unit);
	if (units.empty()) {
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
	// Only reroll the objective when there is nothing here to shoot. A unit that
	// finishes its standoff move while the target lives is idle by design now
	// that the move is the whole order, and it stands within lowestRange of the
	// objective by construction -- which is this test.
	if ((GetTarget() == nullptr)
		&& (position.SqDistance2D(leader->GetPos(circuit->GetLastFrame())) < SQUARE(maxDist)))
	{
		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		position = RoamPos(leader);
	}

	if (units.find(unit) != units.end()) {
		Start(unit);  // NOTE: Not sure if it has effect
	}
}

// attackPower is a sum of CCircuitDef::GetPower(), a per-TYPE constant, so it
// falls only when a unit dies -- a squad at a tenth of its health rates itself
// exactly as high as a fresh one. The enemy side of the same comparison is not
// paper: CThreatMap weights by current health. Weighting our own power by health
// makes the two sides symmetric.
void CAttackTask::FindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	CThreatMap* threatMap = circuit->GetThreatMap();
	threatMap->SetThreatType(leader);
	CMapManager* mapMgr = circuit->GetMapManager();
	// 1.0 == today's behaviour exactly. A tunable, not a hardcoded policy number --
	// this ships as a no-op and is turned down only after measuring the LOS
	// coverage this discount actually has to work with.
	const float unseenEco = circuit->GetTunable("apex_eco_unseen", 1.0f);
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const int frame = circuit->GetLastFrame();
	const AIFloat3& pos = leader->GetPos(frame);
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const bool isAntiStatic = cdef->IsAttrAntiStat();
	const float maxSpeed = SQUARE(highestSpeed * 1.01f / FRAMES_PER_SEC);
	// Computed once: each of these walks the whole squad, and FindTarget runs per
	// task per update.
	const float healthScale = GetHealthScale();
	const float spread = GetSpreadRadius();
	const float cohesion = (spread <= COHESION_MAX_SPREAD)
			? 1.f
			: std::max(COHESION_MIN_SCALE, COHESION_MAX_SPREAD / spread);
	const float maxPower = attackPower * powerMod * healthScale * cohesion;
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();

	CEnemyInfo* bestTarget = nullptr;
	bool bestDive = false;
	diveCommit = false;
	// Tuning inputs. Every metric in the stats export is an OUTCOME; to choose a
	// number for the cohesion cap or a strength margin we need what the decision
	// actually saw, at the moment it was made.
	float bestInfl = .0f;
	float bestNear = .0f;
	float bestScale = .0f;
	int bestSeen = 0;  // was the chosen target's ground in current LOS, or only remembered
	bool bestHome = false;  // chosen target stands on our own ground (odds waived)
	float bestRefused = .0f;  // strongest strength-test refusal, as power/need
	// A juggernaut IS the attack. corjugg (Behemoth, 20,000 metal), armbanth
	// (Titan), corkorg (Korgoth) and armraz all carry role heavy + attribute
	// melee, and all of them detonate on death -- so the value is delivered by
	// ARRIVING, and a walking bomb that refuses a defended target has thrown
	// its whole cost away. apexearth: "if we make juggernauts the biggest goal
	// with them is to just walk straight into an enemy base (because they
	// explode when they die)", and separately "i see a lot of our T3 units just
	// hangin out and not fighting".
	//
	// heavy+melee is exactly those four in the shipped configs -- checked, not
	// assumed. It deliberately excludes corroach/corsktl, which are also melee
	// bombs but assault-role T1/T2 chaff whose behaviour is not in question here.
	// CCircuitUnit::Attack already walks a melee unit onto its target rather
	// than firing from range, so only the DECISION needed changing.
	const bool isJuggernaut = (cdef != nullptr) && cdef->IsCharger();
	// apex: see DIVE_ECO_PRIORITY. Enemy influence at the SQUAD's own position
	// is "we are standing on their ground" -- the same field isHome reads from
	// the other side.
	const bool inTheirBase = inflMap->GetEnemyInflAt(pos) >= INFL_SAFE;
	const float diveCost = circuit->GetTunable("apex_dive_eco_cost", 350.f);
	// Observable, or it cannot be validated -- same rule as the juggernaut line.
	if (inTheirBase && (frame >= lastEngageLog + FRAMES_PER_SEC * 10)) {
		lastEngageLog = frame;
		circuit->LOG("apex: eco dive -- squad on enemy ground, fat eco outranks all");
	}
	// Observable, or it cannot be validated. A behaviour with no log line is a
	// behaviour nobody can prove ever ran -- which is how this repo has shipped
	// dead code more than once. Rate limited per task, not per call.
	if (isJuggernaut && (frame >= lastEngageLog + FRAMES_PER_SEC * 10)) {
		circuit->LOG("apex: juggernaut charge %s -- ignoring engage margin",
				cdef->GetDef()->GetName());
	}
	// A squad worn below press health on enemy ground stops pressing the fight:
	// with no target chosen, the no-target path (FallbackFrontPos, next pass)
	// walks the WHOLE group back to our own front, so hurt members travel
	// escorted instead of peeling off solo through contested ground. Fat
	// economy is the exception -- next to advanced converters or a fusion the
	// kill is worth the squad's life -- so a worn squad still scans, but only
	// dive-qualified eco targets may hold it forward.
	const bool wornOut = !isJuggernaut && inTheirBase
			&& (healthScale < circuit->GetTunable("apex_press_health", 0.6f));
	if (wornOut && (frame >= lastWithdrawLog + FRAMES_PER_SEC * 10)) {
		lastWithdrawLog = frame;
		circuit->LOG("apex: squad worn hp=%.2f -- dive targets only", healthScale);
	}
	int skippedWeak = 0;
	// LINEAR, not squared. `scale` below divides a linear distance by this, and
	// with a squared denominator the ratio collapses the moment the squad leaves
	// home: at 100 elmos out scale is ~0.30, at 1000 it is ~0.003, at 2000 it is
	// ~0.00075. Since scale multiplies the enemy influence we require ourselves
	// to exceed, that zeroed the strength test entirely and the squad attacked
	// anything at any odds once it was off the doorstep.
	const float obDist = std::max(pos.distance2D(basePos), 1.f);  // Own to Base distance
	float minSqDist = std::numeric_limits<float>::max();
	bool hasGoodTarget = false;

	CEnemyInfo* prevTarget = GetTarget();  // compared only, never dereferenced
	const bool wasEngaged = (State::ENGAGE == state);
	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	const std::vector<CEnemyManager::SEnemyGroup>& groups = circuit->GetEnemyManager()->GetEnemyGroups();
	for (unsigned i = 0; i < groups.size(); ++i) {
		const CEnemyManager::SEnemyGroup& group = groups[i];
		const bool isOverpowered = maxPower * 0.125f > group.influence;
		if (hasGoodTarget && isOverpowered) {
			continue;
		}
		const float distBE = group.pos.distance2D(basePos);  // Base to Enemy distance
		// Both linear, so this is a real ratio: how far the enemy group sits from
		// our base against how far WE are from it. Near 1 when we are pushing as
		// deep as they are -- demand the full strength check there. Below 1 only
		// when the group is closer to our base than we are, i.e. defending home,
		// where taking a worse fight is correct.
		const float scale = std::min(distBE / obDist, 1.f);
		// No margin is demanded inside the DEFENDED PERIMETER: a defender that
		// waits for favourable odds has already lost the thing it was defending.
		// The perimeter is the defence-influence field around actual defence
		// structures, not general unit influence -- measured 2026-08-15, net
		// influence >= INFL_SAFE covered a median 85% of the base->enemy axis
		// (p75 95%), waiving the odds check on effectively the whole map and
		// feeding every under-strength squad into any fight it could see.
		// OUR GROUND OR OUR PERIMETER, either one: the defended-perimeter-only
		// scoping made the army stand aside while a push rolled through home
		// territory into the base -- apexearth, watching, 2026-08-15: "we're
		// still running from enemy army and give them free damage into our
		// base... if our base is being pushed we have to prioritize defense
		// and meet that army and destroy it." His live verdict outranks the
		// noise-floor K/D that motivated the narrow scope.
		const bool isHome = (inflMap->GetInfluenceAt(group.pos) >= INFL_SAFE)
				|| (inflMap->GetAllyDefendInflAt(group.pos) > INFL_EPS);
		const bool holdsPrev = wasEngaged && (prevTarget != nullptr)
				&& (std::find(group.units.begin(), group.units.end(), prevTarget->GetId()) != group.units.end());
		const float groupMargin = holdsPrev ? CONTINUE_MARGIN : TradeScaledMargin(circuit);
		// The dive commitment is to FAT ECONOMY, not to any fight on their
		// ground: a blanket inTheirBase waiver here let any squad -- a lone
		// survivor included -- engage towers and armies at hopeless odds the
		// moment it stood on enemy influence. A weak group inside their base is
		// still scanned, but only its unarmed fat-eco targets qualify (isDive).
		const bool groupWeak = !isJuggernaut
				&& (maxPower <= group.influence * scale * groupMargin) && !isHome;
		if (groupWeak && !inTheirBase) {
			++skippedWeak;
			continue;
		}
		if (!terrainMgr->CanMobileReachAt(area, group.pos, highestRange)) {
			continue;
		}

		for (const ICoreUnit::Id eId : group.units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if ((enemy == nullptr) || enemy->IsHidden()/* || (enemy->GetTasks().size() > 2)*/) {
				continue;
			}
			const AIFloat3& ePos = enemy->GetPos();
			const AIFloat3& eVel = enemy->GetVel();
			if ((eVel.SqLength2D() >= maxSpeed)/* && (eVel.dot2D(pos - ePos) < 0)*/) {  // speed and direction
				continue;
			}

			const float elevation = map->GetElevationAt(ePos.x, ePos.z);
			const bool IsInWater = cdef->IsPredictInWater(elevation);
			CCircuitDef* edef = enemy->GetCircuitDef();
			if (edef != nullptr) {
				if (((edef->GetCategory() & canTargetCat) == 0)
					|| ((edef->GetCategory() & noChaseCat) != 0)
					|| (isAntiStatic && edef->IsMobile())
					|| circuit->GetCircuitDef(edef->GetId())->IsIgnore()  // NOTE: groups are created by leader, ignore flags could be different
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

			// Artillery is the thing that beats a massed army without ever being
			// engaged, so it is worth crossing extra ground to reach. The metric
			// below is a distance, so dividing pulls a long-ranged target closer
			// in preference order without ignoring distance entirely -- a Shiva
			// at the far end of the map still loses to one in front of us.
			// apexearth: "they have artillery, and we get slammed by this
			// artillery, and we never seem to really disperse the artillery blob"
			// and "prioritize killing enemy long ranged units... we let them pile
			// up rather than assassinating them".
			float prio = 1.f;
			if (edef != nullptr) {
				// Finish what is nearly dead. apexearth: "we will lose half of our
				// army to a turret that was almost killed, but then we ran away.
				// And then the turret never died."
				const float maxHP = edef->GetHealth();
				if ((maxHP > 1.f) && ((enemy->GetHealth() / maxHP) < FINISH_HP_FRAC)) {
					prio *= FINISH_PRIORITY;
				}
				if (edef->IsRoleArty()) {
					prio = ARTY_PRIORITY;
				} else if (edef->GetMaxRange() > weaponRange * LONG_RANGE_MULT) {
					prio = LONG_RANGE_PRIORITY;  // outranges us even if not ARTY
				}
				// Do not chase what we cannot catch.
				//
				// apexearth, watching live: "sometimes i see entire armies
				// chasing a few light units which takes them all off the
				// frontline (pretty bad when this happens)." A target faster
				// than the squad cannot be caught in open ground -- it simply
				// leads the army away, which is what a raider is FOR. The
				// metric below is a distance, so dividing by a prio under 1
				// pushes the target down the order without forbidding it: a
				// fast unit standing next to us is still worth shooting, a fast
				// unit across the map is not worth walking to.
				//
				// Uses lowestSpeed, the pace the squad actually moves at, not
				// the leader's -- a squad travels at its slowest member.
				if ((lowestSpeed > .1f) && (edef->GetSpeed() > lowestSpeed * CHASE_SPEED_RATIO)) {
					prio *= UNCATCHABLE_PENALTY;
				}
			}
			// A group's own influence says nothing about what is standing NEXT to it.
			// Measured over two 8v8 games: 90% of engagement decisions targeted a
			// group with zero influence -- undefended economy -- so the strength
			// test never ran, and the squad walked into whatever army happened to
			// be nearby. apexearth: "We realize we're in danger too late on our
			// units... we head in ... panic... turn around... die."
			// The threat map covers each armed enemy's weapon range, so it sees the
			// army beside the target that group.influence cannot.
			// Guarded on > 0: if this layer ever reads dead, behaviour is unchanged
			// rather than broken.
			// NOT the threat map: CThreatMap::GetThreatAt read 0 at 14 of 15 target
			// positions when logged, the same dead layer as GetBuilderThreatAt.
			// Enemy GROUP influence is real data -- it is what the strength test
			// above uses -- so sum every armed group standing near this target
			// instead. That is the army beside the undefended mex.
			float localInfl = .0f;
			for (const CEnemyManager::SEnemyGroup& g : groups) {
				if (g.pos.SqDistance2D(ePos) < SQUARE(NEARBY_ENEMY_DIST)) {
					localInfl += g.influence;
				}
			}
			// THE DIVE: inside their base, a fat unarmed structure outranks
			// everything whether it is guarded or not -- see DIVE_ECO_PRIORITY.
			const bool isDive = inTheirBase && (edef != nullptr)
					&& !edef->IsMobile() && !edef->IsAttacker()
					&& (edef->GetCostM() >= diveCost);
			if (isDive) {
				prio *= DIVE_ECO_PRIORITY;
			}
			if ((groupWeak || wornOut) && !isDive) {
				++skippedWeak;
				continue;  // on their ground under-strength or worn: fat eco only
			}
			// localInfl is already the army standing beside this target. It was
			// only ever used to REFUSE a target; nothing used it to prefer a safe
			// one. A static, unarmed, undefended building is exactly that.
			if ((edef != nullptr) && !edef->IsMobile() && !edef->IsAttacker()
				&& (localInfl <= .0f))
			{
				// localInfl == 0 is "no army REMEMBERED here" (hostileDatas retains
				// anything out of current radar/LOS via CMapManager::HostileInLOS),
				// not "no army here". The structure itself is safe to remember -- it
				// cannot move. The absence of a guard next to it is not, unless we
				// have actually looked.
				prio *= mapMgr->IsInLOS(ePos) ? FREE_ECO_PRIORITY : (FREE_ECO_PRIORITY * unseenEco);
				// ...and prefer the ones that actually die in the time a raid
				// has. A converter is 380 metal behind 445 hitpoints; an
				// advanced solar is 350 behind 1130. Equal-ish metal, and only
				// one of them is coming down before the owner reacts.
				// apexearth: "I want to see us doing cheeky moves like running
				// the edge of the map and popping enemy energy converters in 1
				// or 2 hits... (they're very explosive and fragile) This kind of
				// stuff would be able to win a game."
				const float hp = std::max(edef->GetHealth(), 1.f);
				if ((edef->GetCostM() / hp) > SOFT_ECO_DENSITY) {
					prio *= SOFT_ECO_BONUS;
				}
			}
			// ...and push their defensive line to the BACK of the order. isHome
			// means it is shooting at us where we live, which still has to die.
			if ((edef != nullptr) && !edef->IsMobile() && edef->IsAttacker() && !isHome) {
				prio *= ENEMY_WALL_PENALTY;
			}
			// Stay on the target we already committed to unless something is
			// clearly better. prevTarget is what this task chose last pass.
			if (enemy == prevTarget) {
				prio *= TARGET_STICKY;
			}

			const float nearMargin = (enemy == prevTarget) ? CONTINUE_MARGIN : TradeScaledMargin(circuit);
			// apex: count the allies beside us in the strongest refusal too --
			// the fragment-vs-everything test is the structural trickle (see
			// the squadOverwhelms note in SquadTask.cpp). Sum our other
			// ATTACK/DEFEND squads standing near the TARGET, the mirror of the
			// enemy-side localInfl loop above.
			float allyPower = maxPower;
			if (circuit->GetTunable("apex_ally_aggregate", 1.f) > 0.f) {
				CMilitaryManager* mmA = static_cast<CMilitaryManager*>(manager);
				for (IFighterTask::FightType ftA : {IFighterTask::FightType::ATTACK,
				                                    IFighterTask::FightType::DEFEND}) {
					for (IFighterTask* otherA : mmA->GetTasks(ftA)) {
						if (otherA == static_cast<IFighterTask*>(this)) {
							continue;
						}
						ISquadTask* stA = static_cast<ISquadTask*>(otherA);
						CCircuitUnit* olA = stA->GetLeader();
						if ((olA == nullptr)
							|| (olA->GetPos(circuit->GetLastFrame())
								.SqDistance2D(ePos) > SQUARE(NEARBY_ENEMY_DIST)))
						{
							continue;
						}
						allyPower += otherA->GetAttackPower();
					}
				}
			}
			if (!isJuggernaut && !isDive
				&& (localInfl > .0f) && (allyPower < localInfl * nearMargin) && !isHome) {
				++skippedWeak;
				// The strongest refusal: near 1.0 means one merge or a small
				// margin change would have taken it; near 0.2 means hopeless.
				// This ratio is what decides which fix target-skipping gets.
				bestRefused = std::max(bestRefused,
						maxPower / std::max(localInfl * nearMargin, 1.f));
				continue;
			}

			const float sqOEDist = group.vagueMetric * pos.SqDistance2D(ePos) * scale / prio;  // Own to Enemy distance
			if (minSqDist > sqOEDist) {
				minSqDist = sqOEDist;
				bestTarget = enemy;
				bestDive = isDive;
				bestInfl = group.influence;
				bestNear = localInfl;
				bestScale = scale;
				bestSeen = mapMgr->IsInLOS(ePos) ? 1 : 0;
				bestHome = isHome;
				hasGoodTarget |= !isOverpowered;
			}
		}
	}

	if (bestTarget != nullptr) {
		if (bestTarget != prevTarget) {
			riskLevel = 0;   // new objective, fresh route judgement
		}
		SetTarget(bestTarget);
		position = GetTarget()->GetPos();
		diveCommit = bestDive;
	}
	// Feeds the accelerated merge check: a refusal pass this close to the bar
	// means a partner squad is the difference.
	lastRefused = (bestTarget == nullptr) ? bestRefused : .0f;

	// One line per squad per 10s, TAKE=committing to a target, SKIP=every group
	// failed the strength test. `edge` is our rated power over what we had to
	// beat: at 1.0 we engaged on a coin flip, which is what the test permits
	// today. RATE LIMITED -- a count from a grep is not a count of decisions.
	if (frame >= lastEngageLog + FRAMES_PER_SEC * 10) {
		lastEngageLog = frame;
		const float need = bestInfl * bestScale;
		// home=1 separates desperate defence of our own ground (odds waived on
		// purpose) from a bad attack -- without it a losing game's audit reads
		// every base-defence fight as a "hopeless engagement".
		circuit->LOG("apex: engage %s units=%d spread=%.0f hp=%.2f coh=%.2f "
				"power=%.0f need=%.0f edge=%.2f skipped=%d bestRef=%.2f near=%.0f seen=%d home=%d",
				(bestTarget != nullptr) ? "TAKE" : "SKIP",
				int(units.size()), spread, healthScale,
				cohesion, maxPower, need,
				(need > 1.f) ? (maxPower / need) : 0.f, skippedWeak, bestRefused,
				bestNear, bestSeen, bestHome ? 1 : 0);
	}
	// Return: target, startPos=leader->pos, endPos=position
}

void CAttackTask::ApplyTargetPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		// Whether the squad went round or straight through is otherwise invisible:
		// walked/direct near 1.0 is a charge up the middle, well above 1.0 is a
		// flank. Rate limited because attack paths are re-queried constantly.
		CCircuitAI* circuit = manager->GetCircuit();
		// Detour computed EVERY pass, not just on log ticks: it drives the
		// charge flag below. A walk this many times the straight line is not
		// a flank, it is evasion -- the army is out of position the whole
		// trip. Measured live (8v8 Isthmus): detour=4.70; apexearth: "we seem
		// to want to find safe paths way far away from enemy armies... and
		// therefore we do a pretty shit job defending ourselves." The next
		// query for this task paths charge-style (pure distance); FindTarget
		// clears the flag on a target change, so it is per-objective.
		{
			const AIFloat3& from = pPath->posPath.front();
			const AIFloat3& to = pPath->posPath.back();
			float walked = 0.f;
			for (size_t i = 1; i < pPath->posPath.size(); ++i) {
				walked += pPath->posPath[i - 1].distance2D(pPath->posPath[i]);
			}
			const float direct = from.distance2D(to);
			if (direct > 1.f) {
				const bool tooFar = (walked / direct)
						> circuit->GetTunable("apex_max_detour", 2.0f);
				if (tooFar && (riskLevel
						< int(circuit->GetTunable("apex_max_risk", 3.f)))) {
					++riskLevel;   // next query accepts more risk, stays aware
				}
				if (circuit->GetLastFrame() >= lastDetourLog + FRAMES_PER_SEC * 20) {
					lastDetourLog = circuit->GetLastFrame();
					circuit->LOG("apex: attack path walked=%.0f direct=%.0f detour=%.2f risk=%d",
							walked, direct, walked / direct, riskLevel);
				}
			}
		}
		ActivePath(lowestSpeed);
	} else {
		FallbackFrontPos();
	}
}

void CAttackTask::FallbackFrontPos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	// ADVANCE, don't retrace. apexearth, watching live: a squad kills its one
	// elected target (a lone mex), finds nothing else visible, and walks all
	// the way back to the front/base -- with the enemy now undefended. A
	// healthy squad falls onto REMEMBERED enemy positions first; the front
	// line and the base are for squads too mauled to press.
	float hp = 0.f, hpMax = 0.f;
	for (CCircuitUnit* unit : units) {
		if (unit->IsDead()) {
			continue;
		}
		hp += unit->GetUnit()->GetHealth();
		hpMax += unit->GetCircuitDef()->GetHealth();
	}
	const bool healthy = (hpMax > 1.f)
			&& (hp / hpMax >= circuit->GetTunable("apex_press_health", 0.6f));
	if (healthy) {
		const std::vector<CEnemyManager::SEnemyGroup>& groups = circuit->GetEnemyManager()->GetEnemyGroups();
		urgentPositions.clear();
		for (const CEnemyManager::SEnemyGroup& group : groups) {
			if (utils::is_valid(group.pos) && (group.cost > 1.f)) {
				urgentPositions.push_back(group.pos);
			}
		}
	}
	if (urgentPositions.empty() || !healthy) {
		circuit->GetMilitaryManager()->FillFrontPos(leader, urgentPositions);
	}
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
		}
	} else {
		FallbackBasePos();
	}
}

void CAttackTask::FallbackBasePos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CSetupManager* setupMgr = circuit->GetSetupManager();

	// apexearth, watching live: a squad that just WON its fight -- most units
	// above 80% health -- walked all the way home to stand around, handing the
	// now-undefended enemy a free rebuild. A healthy squad with nowhere
	// obvious to go should PRESS toward the enemy's centre of mass, not
	// retrace half the map; only a mauled squad earns the walk home.
	float hp = 0.f, hpMax = 0.f;
	for (CCircuitUnit* unit : units) {
		if (unit->IsDead()) {
			continue;
		}
		hp += unit->GetUnit()->GetHealth();
		hpMax += unit->GetCircuitDef()->GetHealth();
	}
	const float pressHealth = circuit->GetTunable("apex_press_health", 0.6f);
	const AIFloat3& foePos = circuit->GetEnemyManager()->GetEnemyPos();
	const bool press = (hpMax > 1.f) && (hp / hpMax >= pressHealth)
			&& utils::is_valid(foePos);

	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	const AIFloat3& endPos = press ? foePos : setupMgr->GetBasePos();
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
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
