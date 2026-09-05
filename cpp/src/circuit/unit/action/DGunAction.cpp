/*
 * DGunAction.cpp
 *
 *  Created on: Jul 29, 2015
 *      Author: rlcevg
 */

#include "unit/action/DGunAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "module/EconomyManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "Drawer.h"
#include "Log.h"

namespace circuit {

using namespace springai;

CDGunAction::CDGunAction(CCircuitUnit* owner, float range, bool mayClose)
		: IUnitAction(owner, Type::DGUN)
		, range(range)
		, mayClose(mayClose)
		, updCount(0)
{
}

CDGunAction::~CDGunAction()
{
}

void CDGunAction::Update(CCircuitAI* circuit)
{
	if (updCount++ % 4 != 0) {
		return;
	}
	isBlocking = false;
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	const int frame = circuit->GetLastFrame();
	// Sampled trace of the gates, once per unit per 10 s while any enemy is
	// in reach: which of them holds the shot is otherwise invisible.
	const bool trace = (circuit->GetTunable("apex_dgun_log", 0.f) > 0.f)
			&& (frame >= logFrame + FRAMES_PER_SEC * 10);
	const float eCur = circuit->GetEconomyManager()->GetEnergyCur();
	const AIFloat3& pos = unit->GetPos(frame);
	// NOTE: Paralyzer doesn't increase ReloadFrame beyond currentFrame, but disarmer does.
	//       Also checking disarm is more expensive (because of UnitRulesParam).
	// apex: the whole bank, not 90% of it. A commander stores 500 energy and
	// the shot costs 500, so at 90% the D-gun could never fire before an
	// energy storage stood.
	if (!unit->IsDGunReady(frame, eCur)
		|| unit->GetUnit()->IsParalyzed()/* || unit->IsDisarmed(frame)*/)
	{
		if (trace && !circuit->GetCallback()->GetEnemyUnitIdsIn(pos, range).empty()) {
			logFrame = frame;
			circuit->LOG("apex: dgun %s hold: ready=0 e=%.0f cost=%.0f reload=%d",
					unit->GetCircuitDef()->GetDef()->GetName(), eCur, unit->GetDGunCostE(),
					unit->GetDGunReloadFrame() - frame);
		}
		return;
	}
	// apex: THE DGUN SCAN ONLY SAW WHAT WAS ALREADY IN RANGE, and a fighting
	// commander stands at his LASER range, which is longer -- so he traded
	// laser-vs-laser with a Titan and died with the dgun ready (apexearth,
	// watched: "our commander decided to 1v1 a titan *without d-gun*"). The
	// engine's DGun order on a unit target walks into range, so a target
	// worth more than the owner itself may be picked slightly beyond range
	// and walked to. Opt-in per task (mayClose).
	const float closeMult = mayClose
			? std::max(1.f, circuit->GetTunable("apex_dgun_close_mult", 2.f)) : 1.f;
	auto& enemies = circuit->GetCallback()->GetEnemyUnitIdsIn(pos, range * closeMult);
	if (enemies.empty()) {
		return;
	}
	int nHid = 0, nWeak = 0, nCat = 0, nRay = 0, nFar = 0;

	CMap* map = circuit->GetMap();
	CCircuitDef* cdef = unit->GetCircuitDef();
	const int canTargetCat = cdef->GetTargetCategoryDGun();
	const bool isRoleComm = cdef->IsRoleComm();
	const bool IsInWater = cdef->IsInWater(map->GetElevationAt(pos.x, pos.z), pos.y);
	const bool isLowTraj = !unit->IsDGunHigh();
	const bool notByCost = !unit->GetCircuitDef()->IsAttrDGCost();
	const float sqRange = SQUARE(range);
	// The walk-in used to be bought only for a target worth the owner; apexearth:
	// "he should just spam d-guns at enemies so long as he has power", so the
	// bar is zero unless swept back up.
	const float worthBar = cdef->GetCostM()
			* std::max(0.f, circuit->GetTunable("apex_dgun_close_worth", 0.f));
	CEnemyInfo* bestTarget = nullptr;
	float maxScore = 0.f;
	CEnemyInfo* bestFar = nullptr;
	float maxFar = 0.f;

	for (int eId : enemies) {
		CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
		if ((enemy == nullptr) || enemy->NotInRadarAndLOS()) {
			++nHid;
			continue;
		}
		if (notByCost && (enemy->GetInfluence() < THREAT_MIN)) {
			++nWeak;
			continue;
		}
		CCircuitDef* edef = enemy->GetCircuitDef();
		if ((edef == nullptr)
			|| ((edef->GetCategory() & canTargetCat) == 0)
			|| (isRoleComm && edef->IsRoleComm()))  // NOTE: BAR, comm kamikaze
		{
			++nCat;
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		if (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAirDGun() : cdef->HasSurfToAirDGun())) {  // notAA
			continue;
		}
		if (edef->IsInWater(elevation, ePos.y)) {
			if (!(IsInWater ? cdef->HasSubToWaterDGun() : cdef->HasSurfToWaterDGun())) {  // notAW
				continue;
			}
		} else {
			if (!(IsInWater ? cdef->HasSubToLandDGun() : cdef->HasSurfToLandDGun())) {  // notAL
				continue;
			}
		}

		const bool inRange = pos.SqDistance2D(ePos) <= sqRange;
		if (!inRange && (edef->GetCostM() < worthBar)) {
			++nFar;
			continue;
		}
		// The ray is only meaningful from where the shot would be taken; a
		// walk-in changes the geometry, so it is checked in range only.
		if (isLowTraj && inRange) {
			AIFloat3 dir = enemy->GetPos() - pos;
			float rayRange = dir.LengthNormalize();
			// NOTE: TraceRay check is mostly to ensure shot won't go into terrain.
			//       Doesn't properly work with standoff weapons.
			//       C API also returns rayLen.
			ICoreUnit::Id hitUID = circuit->GetDrawer()->TraceRay(pos, dir, rayRange, unit->GetUnit(), 0);
			if (hitUID != enemy->GetId()) {
				++nRay;
				continue;
			}
		}

		const float defScore = notByCost ? edef->GetPower() : edef->GetCostM();
		if (inRange) {
			if (maxScore < defScore) {
				maxScore = defScore;
				bestTarget = enemy;
			}
		} else if (maxFar < defScore) {
			maxFar = defScore;
			bestFar = enemy;
		}
	}

	// An in-range shot always outranks a walk; the walk gets a longer command
	// timeout to cover the approach.
	int timeout = frame + FRAMES_PER_SEC * 5;
	if (bestTarget == nullptr) {
		bestTarget = bestFar;
		timeout = frame + FRAMES_PER_SEC * 10;
	}
	if (trace) {
		logFrame = frame;
		circuit->LOG("apex: dgun %s e=%.0f cost=%.0f range=%.0f enemies=%d hid=%d weak=%d cat=%d far=%d ray=%d fire=%d",
				unit->GetCircuitDef()->GetDef()->GetName(), eCur, unit->GetDGunCostE(), range, (int)enemies.size(),
				nHid, nWeak, nCat, nFar, nRay, (bestTarget != nullptr) ? 1 : 0);
	}
	if (bestTarget != nullptr) {
		unit->ManualFire(bestTarget, timeout);
		unit->ClearTarget();
		isBlocking = true;
	}
}

} // namespace circuit
