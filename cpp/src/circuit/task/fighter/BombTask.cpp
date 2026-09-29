/*
 * BombTask.cpp
 *
 *  Created on: Jan 6, 2016
 *      Author: rlcevg
 */

#include <algorithm>
#include "task/fighter/BombTask.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "unit/action/FightAction.h"
#include "unit/action/MoveAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "unit/CircuitWDef.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "WeaponDef.h"
#include "Damage.h"
#include "UnitDef.h"
#include "Log.h"

#include <cmath>
#include <string>

namespace circuit {

using namespace springai;

CBombTask::CBombTask(ITaskModule* mgr, float powerMod)
		: ISquadTask(mgr, FightType::BOMB, powerMod)
{
}

CBombTask::~CBombTask()
{
}

bool CBombTask::CanAssignTo(CCircuitUnit* unit) const
{
	if (!unit->GetCircuitDef()->IsRoleBomber()) {
		return false;
	}
	// apex: was an exact CircuitDef match, so only the identical unit type could
	// join. Use the speed rule CAttackTask applies to ground instead.
	float speedLeader = leader->GetCircuitDef()->GetSpeed();
	float speedUnit = unit->GetCircuitDef()->GetSpeed();
	if (speedLeader > speedUnit) {
		std::swap(speedLeader, speedUnit);
	}
	if (speedLeader * 1.5f < speedUnit) {
		return false;
	}
	const int frame = manager->GetCircuit()->GetLastFrame();
	// apex: was SQUARE(1000.f); aircraft cross that in seconds.
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(4000.f)) {
		return false;
	}
	return true;
}

void CBombTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);

	int squareSize = manager->GetCircuit()->GetPathfinder()->GetSquareSize();
	CCircuitDef* cdef = unit->GetCircuitDef();
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

void CBombTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	if (units.empty()) {
		manager->AbortTask(this);
	}
}

void CBombTask::Start(CCircuitUnit* unit)
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

void CBombTask::Update()
{
	++updCount;

	/*
	 * Check safety
	 */
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();

	if (State::DISENGAGE == state) {
		if (updCount % 32 == 1) {
			const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
			if (position.SqDistance2D(leader->GetPos(frame)) < SQUARE(maxDist)) {
				state = State::ROAM;
			} else {
				if (IsQueryReady(leader)) {
					FallbackBasePos();
				}
				return;
			}
		} else {
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
	 * Regroup if required
	 */
	bool wasRegroup = (State::REGROUP == state);
	bool mustRegroup = !committed && IsMustRegroup();
	if (State::REGROUP == state) {
		if (mustRegroup) {
			CCircuitAI* circuit = manager->GetCircuit();
			int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
			for (CCircuitUnit* unit : units) {
				if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
					unit->GetTravelAct()->StateWait();
				}
				TRY_UNIT(circuit, unit,
					unit->CmdFightTo(groupPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame, CCircuitUnit::OrdSrc::REGROUP);
				)
			}
		}
		return;
	}

	bool isExecute = (updCount % 4 == 0);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame, CCircuitUnit::Wake::RECONSIDER);
		}
		if (!isExecute) {
			if (wasRegroup && !pPath->posPath.empty()) {
				ActivePath();
			}
			return;
		}
	}

	/*
	 * Update target
	 */
	FindTarget();

	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if (GetTarget() != nullptr) {
		state = State::ENGAGE;
		if (spreadable && (units.size() > 1)) {
			AttackSpread(frame);
		} else {
			aims.clear();
			Attack(frame, GetTarget()->NotInRadarAndLOS() || (GetTarget()->GetCircuitDef() == nullptr)
				|| !GetTarget()->GetCircuitDef()->IsMobile() || circuit->IsCheating());
		}
		return;
	}

	// A path around the AA from here only turns a committed wave in circles.
	if (committed && utils::is_valid(position)) {
		Fallback();
		return;
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (!utils::is_valid(position)) {
		FallbackBasePos();
		return;
	}

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, position, pathfinder->GetSquareSize(), GetHitTest());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CBombTask::OnUnitIdle(CCircuitUnit* unit)
{
	ISquadTask::OnUnitIdle(unit);
	if (units.empty()) {
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
	if (position.SqDistance2D(leader->GetPos(circuit->GetLastFrame())) < SQUARE(maxDist)) {
		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		position = RoamPos(leader);
	}

	if (units.find(unit) != units.end()) {
		Start(unit);  // NOTE: Not sure if it has effect
	}
}

void CBombTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	if (committed && !spent) {
		return;
	}
	// Do not retreat if bomber is close to target
	if (GetTarget() == nullptr) {
		ISquadTask::OnUnitDamaged(unit, attacker);
	} else {
		const AIFloat3& pos = unit->GetPos(manager->GetCircuit()->GetLastFrame());
		if (pos.SqDistance2D(GetTarget()->GetPos()) > SQUARE(unit->GetCircuitDef()->GetLosRadius())) {
			ISquadTask::OnUnitDamaged(unit, attacker);
		}
	}
}

// WHAT ONE POINT OF BUILD POWER IS WORTH PER SECOND, measured from the game's
// own unit tree (mean metal cost per unit of build time) rather than assumed,
// so the bomb score can price a nano farm or a constructor in metal like it
// prices a generator. Game-wide and constant, so it is computed once.
static float BuildMetalRate(CCircuitAI* circuit)
{
	static float rate = -1.f;
	if (rate < 0.f) {
		float sum = 0.f;
		int n = 0;
		for (CCircuitDef& cd : circuit->GetCircuitDefs()) {
			const float bt = cd.GetBuildTime();
			if ((bt > 1.f) && (cd.GetCostM() > 1.f)) {
				sum += cd.GetCostM() / bt;
				++n;
			}
		}
		rate = (n > 0) ? (sum / n) : 0.f;
		circuit->LOG("apex: bomb build-power rate %.4f metal per bp-second over %i defs", rate, n);
	}
	return rate;
}

static float SqDistToSegment2D(const AIFloat3& p, const AIFloat3& a, const AIFloat3& b)
{
	const float dx = b.x - a.x, dz = b.z - a.z;
	const float len2 = dx * dx + dz * dz;
	const float t = (len2 > 1.f)
			? utils::clamp(((p.x - a.x) * dx + (p.z - a.z) * dz) / len2, 0.f, 1.f) : 0.f;
	const float ex = a.x + dx * t - p.x, ez = a.z + dz * t - p.z;
	return ex * ex + ez * ez;
}

void CBombTask::FindTarget()
{
	// TODO: 1) Bombers should constantly harass undefended targets and not suicide.
	//       2) Fat target getting close to base should gain priority and be attacked by group if high AA threat.
	//       3) Avoid RoleAA targets.
	CCircuitAI* circuit = manager->GetCircuit();
	CThreatMap* threatMap = circuit->GetThreatMap();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const bool isAntiStatic = cdef->IsAttrAntiStat();
	const bool notAW = !cdef->HasSurfToWater();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const float scale = (cdef->GetMinRange() > 300.0f) ? 4.0f : 1.0f;
	// apex: a released wave hunts inside the STRIKE FOCUS only -- the cell of
	// enemy economy the script chose, published on the team blackboard as
	// strike_x/z/r/p (no new binding, so an older DLL simply ignores it) --
	// and the AA it will accept is judged against the whole mass: one plane's
	// power vetoed every target under a single flak, so a wave of ninety found
	// nothing. Home defence (ANTI_STAT off) is not the strike.
	const int myTeam = circuit->GetTeamId();
	float focusR = circuit->ReadTeamValue(myTeam, "strike_r", 0.f);
	AIFloat3 focusPos(circuit->ReadTeamValue(myTeam, "strike_x", -1.f), 0.f,
			circuit->ReadTeamValue(myTeam, "strike_z", -1.f));
	// A committed run keeps its cell after the script calls the strike off.
	if (committed) {
		focusR = commitR;
		focusPos = commitPos;
	}
	const bool focused = (focusR > 0.f) && isAntiStatic && !spent;
	const float focusPower = focused ? circuit->ReadTeamValue(myTeam, "strike_p", 0.f) : 0.f;
	const float maxPower = focused
			? std::max(attackPower * scale * powerMod, focusPower)
			: attackPower * scale * powerMod;
	if (focused && !committed) {
		CheckCommit(pos, focusPos, focusR);
	}
	const float sqFocusR = SQUARE(focusR);
	static bool focusLogged = false;
	if (focused && !focusLogged) {
		focusLogged = true;
		circuit->LOG("apex: bomb focus at %.0f,%.0f r=%.0f power=%.1f", focusPos.x, focusPos.z, focusR, focusPower);
	}
	// apex: OVER the cell the wave is committed -- the AA is paid on the way
	// out whether it drops or not, so nothing inside the cell is vetoed on
	// threat; the veto still shapes the approach.
	const bool overFocus = focused && (pos.SqDistance2D(focusPos) <= sqFocusR);
	int nHidden = 0, nPower = 0, nMobile = 0, nCat = 0, nSeen = 0;
	float worstPower = 0.f;
//	const float maxAltitude = cdef->GetAltitude();
	const float speed = cdef->GetSpeed() / 1.75f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
//	const float range = std::max(unit->GetUnit()->GetMaxRange() + threatMap->GetSquareSize(),
//								 cdef->GetLosRadius()) * 2;
	const float sqRange = (GetTarget() != nullptr) ? pos.SqDistance2D(GetTarget()->GetPos()) + 1.f : SQUARE(2000.0f);
	float minHealth = std::numeric_limits<float>::max();
	float bestScore = 0.f;
	float bestValue = 0.f;
	bool bestOnRoute = false;

	COOAICallback* callback = circuit->GetCallback();
	const float trueAoe = cdef->GetAoe() + SQUARE_SIZE;
	const float allyAoe = std::min(trueAoe, DEFAULT_SLACK * 2.f);
	std::function<bool (const AIFloat3& pos)> noAllies = [](const AIFloat3& pos) {
		return true;
	};
	if (allyAoe > SQUARE_SIZE * 2) {
		noAllies = [callback, allyAoe](const AIFloat3& pos) {
			return !callback->IsFriendlyUnitsIn(pos, allyAoe);
		};
	}

	CEnemyInfo* curTarget = GetTarget();  // exempt from the revisit discount below
	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	CEnemyInfo* bestTarget = nullptr;
	position = -RgtVector;
	struct Cand {
		CEnemyInfo* enemy;
		AIFloat3 pos;
		float raw, score, value, health, sqDist;
	};
	std::vector<Cand> routeCands;
	std::vector<Cand> allCands;
	spreadCands.clear();
	spreadable = focused;
	float bestCellRaw = 0.f;
	auto consider = [&](const Cand& c, bool onRoute) {
		if (c.score > bestScore) {
			bestScore = c.score;
			bestValue = c.value;
			bestOnRoute = onRoute;
			minHealth = c.health;
			if (c.sqDist < sqRange) {
				bestTarget = c.enemy;
			} else {
				position = c.pos;
				bestTarget = nullptr;
			}
		}
	};
	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		const AIFloat3& ePos = enemy->GetPos();
		// Judged after the loop against the cell's best: a wave flew over a
		// fusion on its way in and never looked at it (apexearth).
		const bool onRoute = focused && (ePos.SqDistance2D(focusPos) > sqFocusR);
		if (enemy->IsHidden()) {
			++nHidden;
			continue;
		}
		float power = threatMap->GetThreatAt(ePos)/*- enemy->GetThreat(ROLE_TYPE(BOMBER))*/;
		if (focused) {
			++nSeen;
			if (power > worstPower) worstPower = power;
		}
		if ((!overFocus && !committed && (maxPower <= power)) ||
			(notAW && (ePos.y < -SQUARE_SIZE * 5)))
		{
			++nPower;
			continue;
		}

		int targetCat;
		float health;
//		float altitude;
		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			// apex: ANTI_STAT skipped every mobile enemy, which excluded
			// constructors -- the highest-value target for an eco raid. Builders
			// and commanders stay eligible; other mobiles are still skipped --
			// EXCEPT the Behemoth class: a heavy-role mobile above
			// apex_bomb_fat_mobile metal is a walking reactor, and bombers are
			// one of its three direct counters (apexearth). The value-per-HP
			// scoring then ranks it against static eco on its own merits.
			const bool fatMobile = edef->IsRoleHeavy()
					&& (edef->GetCostM() >= circuit->GetTunable("apex_bomb_fat_mobile", 4000.f));
			const bool skipMobile = isAntiStatic && edef->IsMobile()
					&& !edef->IsRoleBuilder() && !edef->IsRoleComm() && !fatMobile;
			if ((edef->GetSpeed() > speed)
				|| skipMobile
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore())
			{
				++nMobile;
				continue;
			}
			targetCat = edef->GetCategory();
			if ((targetCat & canTargetCat) == 0) {
				++nCat;
				continue;
			}
			health = enemy->GetHealth();
//			altitude = edef->GetAltitude();
		} else {
//			targetCat = ~noChaseCat;
//			altitude = 0.f;
			continue;
		}

		if (/*enemy->IsInRadarOrLOS() && */((targetCat & noChaseCat) == 0)
			/*&& (altitude < maxAltitude)*/
			&& noAllies(ePos))
		{
//			float cost = 0.f;
//			auto enemies = circuit->GetCallback()->GetEnemyUnitIdsIn(ePos, trueAoe);
//			for (int enemyId : enemies) {
//				CEnemyInfo* ei = circuit->GetEnemyInfo(enemyId);
//				if (ei == nullptr) {
//					continue;
//				}
//				// FIXME: Finish
//                if (near.getHealth() > damage * (1 - near.distanceTo(e.getPos()) * falloff)) {
//                    metalKilled += 0.33 * near.getMetalCost() * damage * (1 - near.distanceTo(e.getPos()) * falloff) / near.getDef().getHealth();
//                } else {
//                    metalKilled += near.getMetalCost();
//                }
//				cost += ei->GetCost();
//			}
			// VALUE, NOT SOFTNESS. Stock picks the lowest-HEALTH target, which is
			// why bombers cross the map for a metal extractor and then die to AA
			// on the way home. apexearth: "we are not focusing on attacking the
			// enemy home base with the air. We don't wanna attack a lot of the
			// small mex emplacements and because we're air we fly a huge arc
			// after hitting a low-value target and usually die to AA."
			//
			// Score = metal per hitpoint, discounted by distance, so a lab or a
			// reactor beats an extractor and a near target beats a far one of
			// equal worth. The floor stops a bomber committing to anything under
			// apex_bomb_min_value metal while something better exists.
			float value = (edef != nullptr) ? edef->GetCostM() : 0.f;
			// apex: KILLING ENERGY IS WORTH MORE THAN THE BUILDING (apexearth
			// 2026-08-29: "Killing energy economy is even better than
			// metal"). A dead generator costs them its metal PLUS the stream
			// it was making, capitalized over apex_bomb_eco_h seconds at the
			// game's ~70:1 conversion -- a fusion's +1000 E/s adds ~4,300 to
			// its price at the 300s default, doubling it against any tower of
			// equal armor. Derived from the def's own make rate; no class
			// list.
			if (edef != nullptr) {
				const float ecoH = circuit->GetTunable("apex_bomb_eco_h", 300.f);
				value += edef->GetMakeE() * (ecoH / 70.f);
				// THE OTHER TWO WAYS A BUILDING FEEDS THEM, in the same
				// currency (apexearth: "find where the enemy converters, build
				// power, energy production is and bomb that"). A T1 converter
				// costs ONE metal, so cost alone priced their whole conversion
				// farm at nothing. Build power is a metal rate too.
				value += (edef->GetMakeM()
						+ edef->GetConvertCapacity() * edef->GetConvertRatio()) * ecoH;
				value += edef->GetBuildSpeed() * BuildMetalRate(circuit) * ecoH;
			}
			// A NANOFRAME IS NOT THE BUILDING. GetCostM prices the finished
			// def, and a frame's low health then made it the best-looking
			// target on the map -- apexearth, watching a raid: "we bombed the
			// one being built which doesn't explode when killed!" Worth only
			// the invested share: approximate by health fraction of the def's
			// full health, which also kills the low-health score inflation
			// (value and health shrink together). The finished AFUS beside it
			// keeps its full price and its death blast.
			if ((edef != nullptr) && enemy->IsBeingBuilt()) {
				value *= health / std::max(edef->GetHealth(), 1.f);
			}
			const float sqDist = pos.SqDistance2D(ePos);
			const float minValue = circuit->GetTunable("apex_bomb_min_value", 200.f);
			const float distScale = circuit->GetTunable("apex_bomb_dist_scale", 4000.f);
			const float dist = math::sqrt(sqDist);
			float raw = value / std::max(health, 1.f);
			if (value < minValue) {
				raw *= 0.1f;   // still allowed, but only if nothing else offers
			}
			// TARGET VARIANCE (apexearth: "our air tends to repeatedly try
			// bombing the same thing"). A target another squad committed to
			// within apex_bomb_revisit_s is discounted, fading back to full
			// score linearly -- it is still alive, so the last run failed, and
			// the AA that beat it is still there. The task's OWN target is
			// exempt: a run in progress must never swerve off its own note.
			if (enemy != curTarget) {
				const int lastF = circuit->GetMilitaryManager()->LastBombFrame(kv.first);
				if (lastF >= 0) {
					const float revisitS = circuit->GetTunable("apex_bomb_revisit_s", 90.f);
					const float sinceS = float(circuit->GetLastFrame() - lastF) / float(FRAMES_PER_SEC);
					if ((revisitS > 1.f) && (sinceS < revisitS)) {
						const float disc = circuit->GetTunable("apex_bomb_revisit_disc", 0.2f);
						raw *= disc + (1.f - disc) * (sinceS / revisitS);
					}
				}
			}
			const Cand c{enemy, ePos, raw, raw / (1.f + dist / distScale), value, health, sqDist};
			if (focused && (value >= minValue)) {
				allCands.push_back(c);
			}
			if (onRoute) {
				if (value >= minValue) {
					routeCands.push_back(c);
				}
				continue;
			}
			bestCellRaw = std::max(bestCellRaw, raw);
			consider(c, false);
		}
	}

	// ON THE WAY: off the cell, a target is taken only if it is worth at least
	// the best the cell offers on its own merits -- the detour is then pure
	// gain -- and it lies within sight of the route the wave actually flies
	// (the threat-routed path, not the straight line).
	if (!routeCands.empty()) {
		const float sqReach = SQUARE(cdef->GetLosRadius());
		const F3Vec& path = pPath->posPath;
		size_t from = 0;
		float sqNear = std::numeric_limits<float>::max();
		for (size_t i = 0; i < path.size(); ++i) {
			const float d = pos.SqDistance2D(path[i]);
			if (d < sqNear) {
				sqNear = d;
				from = i;
			}
		}
		for (const Cand& c : routeCands) {
			if (c.raw < bestCellRaw) {
				continue;
			}
			bool onPath = (c.sqDist <= sqReach);
			for (size_t i = from; !onPath && (i + 1 < path.size()); ++i) {
				onPath = (SqDistToSegment2D(c.pos, path[i], path[i + 1]) <= sqReach);
			}
			if (onPath) {
				consider(c, true);
			}
		}
	}

	if (committed && overFocus && (bestTarget == nullptr) && !utils::is_valid(position)) {
		committed = false;
		spent = true;
		circuit->LOG("apex: bomb run spent over %.0f,%.0f units=%d -- nothing left in the cell, home",
				focusPos.x, focusPos.z, (int)units.size());
	} else if (focused && (bestTarget == nullptr) && !utils::is_valid(position)) {
		position = focusPos;   // nothing scored yet: fly to the cell as one and look again there
		static int nextNoTargetLog = 0;
		if (overFocus && (circuit->GetLastFrame() >= nextNoTargetLog)) {
			nextNoTargetLog = circuit->GetLastFrame() + FRAMES_PER_SEC * 5;
			circuit->LOG("apex: bomb no-target over %.0f,%.0f seen=%d hidden=%d power=%d mobile=%d cat=%d maxPower=%.1f worst=%.1f units=%d",
					focusPos.x, focusPos.z, nSeen, nHidden, nPower, nMobile, nCat, maxPower, worstPower, (int)units.size());
		}
	}
	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		position = bestTarget->GetPos();
		CMilitaryManager* milMgr = circuit->GetMilitaryManager();
		// Fresh commits only: FindTarget re-runs through a sortie, and logging
		// the re-pick of the task's own target would read as fixation.
		if (bestTarget != curTarget) {
			const CCircuitDef* bd = bestTarget->GetCircuitDef();
			// worth= is the priced value, mob= says whether the run went at
			// something that walks: an eco raid reading mob=1 is the doctrine
			// failing, and that cannot be seen from the def name alone.
			circuit->LOG("apex: bomb-commit id=%d def=%s worth=%.0f mob=%d antistat=%d last=%d route=%d",
					bestTarget->GetId(),
					(bd != nullptr) ? bd->GetDef()->GetName() : "?",
					bestValue,
					((bd != nullptr) && bd->IsMobile()) ? 1 : 0,
					isAntiStatic ? 1 : 0,
					milMgr->LastBombFrame(bestTarget->GetId()),
					bestOnRoute ? 1 : 0);
		}
		milMgr->NoteBombTarget(bestTarget->GetId(), circuit->GetLastFrame());
		if (focused) {
			const AIFloat3& bPos = bestTarget->GetPos();
			for (const Cand& c : allCands) {
				if (c.pos.SqDistance2D(bPos) <= sqFocusR) {
					spreadCands.push_back({c.enemy->GetId(), c.pos, c.value, c.health, c.enemy->GetCircuitDef()});
				}
			}
		}
	}
	// Return: target, startPos=leader->pos, endPos=position
}

// One bomber's salvo on one building in one pass. The bombs fall in a line along
// the track, so only the stretch over the footprint plus the splash radius lands.
static float PassDamage(CCircuitDef* bdef, CCircuitDef* edef)
{
	CWeaponDef* cw = bdef->GetWeaponDef();
	if ((cw == nullptr) || (edef == nullptr)) {
		return 0.f;
	}
	WeaponDef* wd = cw->GetDef();
	static std::map<int, std::vector<float>> dmgOf;
	static std::map<int, int> armorOf;
	auto it = dmgOf.find(wd->GetWeaponDefId());
	if (it == dmgOf.end()) {
		Damage* damage = wd->GetDamage();
		it = dmgOf.emplace(wd->GetWeaponDefId(), damage->GetTypes()).first;
		delete damage;
	}
	auto ia = armorOf.find(edef->GetId());
	if (ia == armorOf.end()) {
		ia = armorOf.emplace(edef->GetId(), edef->GetDef()->GetArmorType()).first;
	}
	const std::vector<float>& dm = it->second;
	if (dm.empty()) {
		return 0.f;
	}
	const float perBomb = ((ia->second >= 0) && (ia->second < (int)dm.size())) ? dm[ia->second] : dm[0];
	const int salvo = std::max(1, wd->GetSalvoSize());
	const int shots = salvo * std::max(1, wd->GetProjectilesPerShot());
	const float track = (salvo - 1) * wd->GetSalvoDelay() * bdef->GetSpeed();
	const float width = 0.5f * (edef->GetFootX() + edef->GetFootZ()) * 16.f + cw->GetAoe();
	const float hit = (track > width) ? (width / track) : 1.f;
	return perBomb * shots * hit;
}

// apexearth 2026-09-28: eighty bombers all dropped on one building. Each bomber
// gets its own aim: the primary gets the bombers that kill it after the wave's
// expected losses, the rest go to the neighbours worth the most metal per bomber
// needed, and aims are matched to planes across the approach so the drops land
// on a line instead of in one crater.
void CBombTask::PlanSpread(int frame)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CEnemyInfo* primary = GetTarget();
	CCircuitDef* bdef = leader->GetCircuitDef();
	const int n = (int)units.size();
	const float surv = utils::clamp(circuit->ReadTeamValue(circuit->GetTeamId(), "strike_s", 1.f),
			1.f / n, 1.f);
	struct Aim {
		ICoreUnit::Id id;
		AIFloat3 pos;
		float value, pass, health;
		int need, got;
		CCircuitDef* edef;
	};
	auto sizeAim = [&](Aim& a) {
		a.pass = PassDamage(bdef, a.edef);
		a.need = (a.pass > 0.f) ? std::max(1, (int)std::ceil(a.health / (a.pass * surv))) : n;
	};
	Aim prim{primary->GetId(), primary->GetPos(), 0.f, 0.f, primary->GetHealth(), 0, 0, primary->GetCircuitDef()};
	sizeAim(prim);
	std::vector<Aim> cands;
	for (const SpreadCand& c : spreadCands) {
		if (c.id == prim.id) {
			prim.value = c.value;
			continue;
		}
		Aim a{c.id, c.pos, c.value, 0.f, c.health, 0, 0, c.edef};
		sizeAim(a);
		cands.push_back(a);
	}
	std::sort(cands.begin(), cands.end(), [](const Aim& a, const Aim& b) {
		return a.value / a.need > b.value / b.need;
	});
	std::vector<Aim> plan;
	int left = n;
	prim.got = std::min(prim.need, left);
	left -= prim.got;
	plan.push_back(prim);
	for (Aim& a : cands) {
		if (left <= 0) {
			break;
		}
		if (a.need > left) {
			continue;
		}
		a.got = a.need;
		left -= a.need;
		plan.push_back(a);
	}
	for (size_t i = 0; left > 0; i = (i + 1) % plan.size()) {
		++plan[i].got;
		--left;
	}

	float mx = 0.f, mz = 0.f;
	for (CCircuitUnit* u : units) {
		const AIFloat3& p = u->GetPos(frame);
		mx += p.x;
		mz += p.z;
	}
	float dx = prim.pos.x - mx / n, dz = prim.pos.z - mz / n;
	const float len = std::max(math::sqrt(dx * dx + dz * dz), 1.f);
	dx /= len;
	dz /= len;
	auto lateral = [&](const AIFloat3& p) { return (p.x - prim.pos.x) * -dz + (p.z - prim.pos.z) * dx; };
	std::vector<std::pair<float, size_t>> slots;
	float lo = 0.f, hi = 0.f, deep = 0.f;
	for (size_t i = 0; i < plan.size(); ++i) {
		const float l = lateral(plan[i].pos);
		lo = std::min(lo, l);
		hi = std::max(hi, l);
		deep = std::max(deep, std::fabs((plan[i].pos.x - prim.pos.x) * dx + (plan[i].pos.z - prim.pos.z) * dz));
		for (int k = 0; k < plan[i].got; ++k) {
			slots.push_back({l, i});
		}
	}
	std::vector<std::pair<float, CCircuitUnit*>> planes;
	for (CCircuitUnit* u : units) {
		planes.push_back({lateral(u->GetPos(frame)), u});
	}
	std::sort(slots.begin(), slots.end());
	std::sort(planes.begin(), planes.end());
	aims.clear();
	for (size_t k = 0; k < planes.size() && k < slots.size(); ++k) {
		aims[planes[k].second->GetId()] = plan[slots[k].second].id;
	}

	CMilitaryManager* milMgr = circuit->GetMilitaryManager();
	std::string rest;
	for (size_t i = 0; i < plan.size(); ++i) {
		milMgr->NoteBombTarget(plan[i].id, frame);
		if (i > 0) {
			rest += utils::string_format("%s:%d/%d ",
					(plan[i].edef != nullptr) ? plan[i].edef->GetDef()->GetName() : "?", plan[i].got, plan[i].need);
		}
	}
	circuit->LOG("apex: bomb spread units=%d aims=%d surv=%.2f bomber=%s primary=%s hp=%.0f pass=%.0f need=%d got=%d width=%.0f depth=%.0f cands=%d rest=%s",
			n, (int)plan.size(), surv, bdef->GetDef()->GetName(),
			(prim.edef != nullptr) ? prim.edef->GetDef()->GetName() : "?",
			prim.health, prim.pass, prim.need, prim.got, hi - lo, deep, (int)spreadCands.size(), rest.c_str());
}

void CBombTask::AttackSpread(int frame)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const ICoreUnit::Id pid = GetTarget()->GetId();
	bool replan = true;
	for (const auto& kv : aims) {
		if (kv.second == pid) {
			replan = false;
			break;
		}
	}
	// A dead plane does not re-plan: its loss is already in the allotment.
	for (CCircuitUnit* u : units) {
		if (replan) {
			break;
		}
		auto it = aims.find(u->GetId());
		replan = (it == aims.end()) || (circuit->GetEnemyInfo(it->second) == nullptr);
	}
	if (!replan && (frame < attackFrame + FRAMES_PER_SEC * 3)) {
		return;
	}
	attackFrame = frame;
	if (replan) {
		PlanSpread(frame);
	}
	for (CCircuitUnit* u : units) {
		if (u->Blocker() != nullptr) {
			continue;
		}
		auto it = aims.find(u->GetId());
		CEnemyInfo* e = (it != aims.end()) ? circuit->GetEnemyInfo(it->second) : nullptr;
		if (e == nullptr) {
			e = GetTarget();
		}
		const bool isGround = e->NotInRadarAndLOS() || (e->GetCircuitDef() == nullptr)
				|| !e->GetCircuitDef()->IsMobile() || circuit->IsCheating();
		if (u->GetTravelAct() != nullptr) {
			u->GetTravelAct()->StateWait();
		}
		u->Attack(e, isGround, frame + FRAMES_PER_SEC * 60);
	}
}

// apex: the point of no return -- once the way home crosses more AA than the way
// to the cell, turning back buys nothing, so the wave presses on (docs/24).
static float LineThreat(CThreatMap* threatMap, CCircuitUnit* unit, const AIFloat3& a, const AIFloat3& b)
{
	const float w = CTerrainManager::GetTerrainWidth();
	const float h = CTerrainManager::GetTerrainHeight();
	float sum = 0.f;
	for (int i = 1; i <= 6; ++i) {
		AIFloat3 p = a + (b - a) * (float(i) / 6.f);
		p.x = utils::clamp(p.x, 0.f, w - 1.f);
		p.z = utils::clamp(p.z, 0.f, h - 1.f);
		sum += std::max(threatMap->GetThreatAt(unit, p), 0.f);
	}
	return sum;
}

void CBombTask::CheckCommit(const AIFloat3& pos, const AIFloat3& focusPos, float focusR)
{
	if (spent || !utils::is_valid(focusPos)) {
		return;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& home = circuit->GetSetupManager()->GetBasePos();
	const float back = LineThreat(threatMap, leader, pos, home);
	const float on = LineThreat(threatMap, leader, pos, focusPos);
	if (back > on) {
		committed = true;
		commitPos = focusPos;
		commitR = focusR;
		circuit->LOG("apex: bomb commit -- way home %.1f AA vs way on %.1f, %i planes at %.0f,%.0f pressing on to %.0f,%.0f",
				back, on, (int)units.size(), pos.x, pos.z, focusPos.x, focusPos.z);
	}
}

void CBombTask::ApplyTargetPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
	} else {
		FallbackBasePos();
	}
}

void CBombTask::FallbackBasePos()
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

void CBombTask::ApplyBasePos(const CQueryPathSingle* query)
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

void CBombTask::Fallback()
{
	// should never happen
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::ENGAGE);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
