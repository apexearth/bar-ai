/*
 * DGunAction.cpp
 *
 *  Created on: Jul 29, 2015
 *      Author: rlcevg
 */

#include "unit/action/DGunAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "unit/CircuitWDef.h"
#include "unit/ally/AllyUnit.h"
#include "module/EconomyManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "Drawer.h"
#include "Log.h"

#include <cmath>
#include <vector>

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
	// A COPY, NOT THE REFERENCE. GetEnemyUnitIdsIn and GetFriendlyUnitIdsIn
	// both return the callback's single `unitIds` member (SpringCallback.cpp),
	// so the friendly sweep below would resize the vector this loop is walking.
	const std::vector<int> enemies = circuit->GetCallback()->GetEnemyUnitIdsIn(pos, range * closeMult);
	if (enemies.empty()) {
		return;
	}
	int nHid = 0, nWeak = 0, nCat = 0, nRay = 0, nFar = 0, nFF = 0;

	CMap* map = circuit->GetMap();
	CCircuitDef* cdef = unit->GetCircuitDef();

	// THE BEAM IS A CORRIDOR, NOT A LINE. The D-gun is noexplode: it does not
	// stop at the target, it runs to the WEAPON's own range damaging a disc of
	// GetAoe() the whole way, and avoidfriendly is false so the engine will not
	// spare us. The old check traced a zero-width ray to the target, which saw
	// neither the width nor most of the travel.
	CWeaponDef* dgDef = cdef->GetDGunDef();
	const float wRange = (dgDef != nullptr) ? dgDef->GetRange() : range;
	const float wAoe = (dgDef != nullptr) ? dgDef->GetAoe() : 0.f;
	const bool ffOn = (circuit->GetTunable("apex_dgun_ff", 1.f) > 0.f)
			&& (dgDef != nullptr) && (wAoe > 0.f) && (wRange > 1.f);
	// One sweep per update, positions cached: the friendly set does not vary
	// with which enemy is being scored, and a callback per candidate is both
	// the buffer hazard above and needless cost.
	std::vector<float> ffX, ffZ;
	if (ffOn) {
		const float qR = range * closeMult + wRange + wAoe;
		const std::vector<int> mine = circuit->GetCallback()->GetFriendlyUnitIdsIn(pos, qR);
		ffX.reserve(mine.size());
		ffZ.reserve(mine.size());
		for (int fId : mine) {
			if (fId == unit->GetId()) {
				continue;
			}
			CAllyUnit* f = circuit->GetFriendlyUnit(fId);
			if (f == nullptr) {
				continue;
			}
			const AIFloat3& fp = f->GetPos(frame);
			ffX.push_back(fp.x);
			ffZ.push_back(fp.z);
		}
	}
	// True when firing from `fx,fz` along the unit 2D heading `dx,dz` would put
	// one of ours inside the beam's disc anywhere along its travel.
	auto beamHitsOwn = [&](float fx, float fz, float dx, float dz, float len) {
		const float aoe2 = wAoe * wAoe;
		for (size_t i = 0; i < ffX.size(); ++i) {
			const float rx = ffX[i] - fx;
			const float rz = ffZ[i] - fz;
			const float t = rx * dx + rz * dz;
			if ((t < 0.f) || (t > len)) {
				continue;   // beside the muzzle or past the end of travel
			}
			const float px = rx - dx * t;
			const float pz = rz - dz * t;
			if (px * px + pz * pz <= aoe2) {
				return true;
			}
		}
		return false;
	};

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
		// The terrain ray still applies, and only in range: a shot into a
		// hillside is wasted whatever else is true. The old second trace --
		// for what stands BEHIND the target -- is gone: it read an
		// uninitialised out-param as a unit id on any clean ray (the C bridge
		// only writes it on a hit in LOS), and it looked along a line the
		// beam is far wider than. The corridor test below replaces it.
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
		// OURS IN THE BEAM -- checked in range AND on the walk-in, which had no
		// check of any kind. The walk is scored from where the shot would
		// actually be taken: the point on the approach at which the target
		// first enters weapon range.
		if (ffOn) {
			const float ex = ePos.x - pos.x;
			const float ez = ePos.z - pos.z;
			const float d2 = ex * ex + ez * ez;
			if (d2 > 1.f) {
				const float d = std::sqrt(d2);
				const float dx = ex / d;
				const float dz = ez / d;
				const float back = (d > wRange) ? (d - wRange) : 0.f;
				if (beamHitsOwn(pos.x + dx * back, pos.z + dz * back, dx, dz, wRange)) {
					++nFF;
					continue;
				}
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
		circuit->LOG("apex: dgun %s e=%.0f cost=%.0f range=%.0f wrange=%.0f aoe=%.0f enemies=%d hid=%d weak=%d cat=%d far=%d ray=%d ff=%d own=%d fire=%d",
				unit->GetCircuitDef()->GetDef()->GetName(), eCur, unit->GetDGunCostE(), range, wRange, wAoe,
				(int)enemies.size(), nHid, nWeak, nCat, nFar, nRay, nFF, (int)ffX.size(),
				(bestTarget != nullptr) ? 1 : 0);
	}
	if (bestTarget != nullptr) {
		unit->ManualFire(bestTarget, timeout);
		unit->ClearTarget();
		isBlocking = true;
	}
}

} // namespace circuit
