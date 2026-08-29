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
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Log.h"

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
	bool mustRegroup = IsMustRegroup();
	if (State::REGROUP == state) {
		if (mustRegroup) {
			CCircuitAI* circuit = manager->GetCircuit();
			int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
			for (CCircuitUnit* unit : units) {
				if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
					unit->GetTravelAct()->StateWait();
				}
				TRY_UNIT(circuit, unit,
					unit->CmdFightTo(groupPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame);
				)
			}
		}
		return;
	}

	bool isExecute = (updCount % 4 == 0);
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

	/*
	 * Update target
	 */
	FindTarget();

	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if (GetTarget() != nullptr) {
		state = State::ENGAGE;
		Attack(frame, GetTarget()->NotInRadarAndLOS() || (GetTarget()->GetCircuitDef() == nullptr)
			|| !GetTarget()->GetCircuitDef()->IsMobile() || circuit->IsCheating());
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
	const float maxPower = attackPower * scale * powerMod;
//	const float maxAltitude = cdef->GetAltitude();
	const float speed = cdef->GetSpeed() / 1.75f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
//	const float range = std::max(unit->GetUnit()->GetMaxRange() + threatMap->GetSquareSize(),
//								 cdef->GetLosRadius()) * 2;
	const float sqRange = (GetTarget() != nullptr) ? pos.SqDistance2D(GetTarget()->GetPos()) + 1.f : SQUARE(2000.0f);
	float minHealth = std::numeric_limits<float>::max();
	float bestScore = 0.f;

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
	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden()) {
			continue;
		}
		const AIFloat3& ePos = enemy->GetPos();
		float power = threatMap->GetThreatAt(ePos)/*- enemy->GetThreat(ROLE_TYPE(BOMBER))*/;
		if ((maxPower <= power) ||
			(notAW && (ePos.y < -SQUARE_SIZE * 5)))
		{
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
				continue;
			}
			targetCat = edef->GetCategory();
			if ((targetCat & canTargetCat) == 0) {
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
			float score = (value / std::max(health, 1.f)) / (1.f + dist / distScale);
			if (value < minValue) {
				score *= 0.1f;   // still allowed, but only if nothing else offers
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
						score *= disc + (1.f - disc) * (sinceS / revisitS);
					}
				}
			}
			if (score > bestScore) {
				bestScore = score;
				minHealth = health;
				if (sqDist < sqRange) {
					bestTarget = enemy;
				} else {
					position = ePos;
					bestTarget = nullptr;
				}
			}
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
			circuit->LOG("apex: bomb-commit id=%d def=%s last=%d",
					bestTarget->GetId(),
					(bd != nullptr) ? bd->GetDef()->GetName() : "?",
					milMgr->LastBombFrame(bestTarget->GetId()));
		}
		milMgr->NoteBombTarget(bestTarget->GetId(), circuit->GetLastFrame());
	}
	// Return: target, startPos=leader->pos, endPos=position
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
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
