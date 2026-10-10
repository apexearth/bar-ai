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
{
}

CDGunAction::~CDGunAction()
{
}

void CDGunAction::Update(CCircuitAI* circuit)
{
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	const int frame = circuit->GetLastFrame();
	// An order not yet fired keeps the hands: re-picking each update flipped
	// a walk-in between targets.
	if ((frame < reissueAt) && unit->IsDGunHeld(frame)) {
		isBlocking = true;
		return;
	}
	isBlocking = false;
	CCircuitDef* cdef = unit->GetCircuitDef();
	const bool isRoleComm = cdef->IsRoleComm();
	const bool trace = (frame >= logFrame + FRAMES_PER_SEC * 5)
			&& (isRoleComm || (circuit->GetTunable("apex_dgun_log", 0.f) > 0.f));
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
		if (trace && (unit->GetDGunReloadFrame() <= frame)
			&& !circuit->GetCallback()->GetEnemyUnitIdsIn(pos, range).empty())
		{
			logFrame = frame;
			circuit->LOG("apex: dgun held t=%i %s why=%s e=%.0f cost=%.0f",
					circuit->GetTeamId(), cdef->GetDef()->GetName(),
					unit->GetUnit()->IsParalyzed() ? "paralyzed" : "energy", eCur, unit->GetDGunCostE());
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
	const float closeMult = (mayClose && unit->IsDGunCloseOk())
			? std::max(1.f, circuit->GetTunable("apex_dgun_close_mult", 2.f)) : 1.f;
	// A COPY, NOT THE REFERENCE. GetEnemyUnitIdsIn and GetFriendlyUnitIdsIn
	// both return the callback's single `unitIds` member (SpringCallback.cpp),
	// so the friendly sweep below would resize the vector this loop is walking.
	const std::vector<int> enemies = circuit->GetCallback()->GetEnemyUnitIdsIn(pos, range * closeMult);
	if (enemies.empty()) {
		return;
	}
	int nHid = 0, nWeak = 0, nCat = 0, nComm = 0, nAir = 0, nRay = 0, nFar = 0, nFF = 0;

	CMap* map = circuit->GetMap();

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
	// One sweep per update, and only once a candidate reaches the test: a
	// callback per candidate is both the buffer hazard above and needless cost.
	// A building is its footprint, not its centre: the disc is far narrower
	// than a lab, and the beam killed one it missed by that test.
	std::vector<float> ffX, ffZ, ffR;
	bool ffBuilt = false;
	auto buildFF = [&]() {
		ffBuilt = true;
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
			CCircuitDef* fdef = f->GetCircuitDef();
			ffR.push_back((fdef != nullptr) ? fdef->GetRadius() : 0.f);
		}
	};
	// True when firing from `fx,fz` along the unit 2D heading `dx,dz` would put
	// one of ours inside the beam's disc anywhere along its travel.
	auto beamHitsOwn = [&](float fx, float fz, float dx, float dz, float len) {
		for (size_t i = 0; i < ffX.size(); ++i) {
			const float rx = ffX[i] - fx;
			const float rz = ffZ[i] - fz;
			const float t = rx * dx + rz * dz;
			const float reach = wAoe + ffR[i];
			if ((t < -reach) || (t > len + reach)) {
				continue;   // beside the muzzle or past the end of travel
			}
			const float px = rx - dx * t;
			const float pz = rz - dz * t;
			if (px * px + pz * pz <= reach * reach) {
				return true;
			}
		}
		return false;
	};

	const int canTargetCat = cdef->GetTargetCategoryDGun();
	const bool IsInWater = cdef->IsInWater(map->GetElevationAt(pos.x, pos.z), pos.y);
	// BAR's D-gun hugs the ground (unit_dgun_behaviour.lua) and passes through
	// wrecks and units, so the terrain ray only refused shots: it hit a bump,
	// a feature, the enemy in front, or read nothing for a radar-only target.
	const bool isLowTraj = !unit->IsDGunHigh() && !isRoleComm;
	const bool notByCost = !cdef->IsAttrDGCost();
	// Valued by power, as he values himself (docs/24); metal only orders the
	// unarmed below every armed unit, so a lone builder still draws a shot.
	const float costTie = notByCost ? 0.f : 1e-4f;
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

	// THE BEAM KILLS EVERYTHING IT CROSSES, and a raider that sidesteps during
	// the flight is missed: a shot is worth what stands in its corridor, each
	// member discounted by how far it can move sideways before the beam
	// arrives.
	const float pSpeed = (dgDef != nullptr) ? dgDef->GetDef()->GetProjectileSpeed() : 0.f;  // elmos/frame
	struct SCorr { float x, z, vx, vz, value, r; };
	std::vector<SCorr> corr;
	corr.reserve(enemies.size());
	for (int eId : enemies) {
		CEnemyInfo* e = circuit->GetEnemyInfo(eId);
		if ((e == nullptr) || e->NotInRadarAndLOS()) {
			continue;
		}
		CCircuitDef* ed = e->GetCircuitDef();
		if ((ed == nullptr) || ed->IsAbleToFly() || (isRoleComm && ed->IsRoleComm())) {
			continue;
		}
		const AIFloat3& ep = e->GetPos();
		const AIFloat3& ev = e->GetVel();
		corr.push_back({ep.x, ep.z, ev.x, ev.z, ed->GetPower() + ed->GetCostM() * costTie, ed->GetRadius()});
	}
	int bestN = 0;
	float bestLat = 0.f;
	// Value in the beam fired from `fx,fz` toward `tx,tz`.
	auto beamValue = [&](float fx, float fz, float tx, float tz, int& nIn, float& tgtLat) {
		float dx = tx - fx, dz = tz - fz;
		const float d = std::sqrt(dx * dx + dz * dz);
		nIn = 0;
		tgtLat = 0.f;
		if (d < 1.f) {
			return 0.f;
		}
		dx /= d;
		dz /= d;
		float sum = 0.f;
		for (const SCorr& c : corr) {
			const float rx = c.x - fx, rz = c.z - fz;
			const float t = rx * dx + rz * dz;
			const float reach = wAoe + c.r;
			if ((t < -reach) || (t > wRange + reach)) {
				continue;
			}
			const float px = rx - dx * t, pz = rz - dz * t;
			if (px * px + pz * pz > reach * reach) {
				continue;
			}
			const float vLat = std::fabs(c.vx * -dz + c.vz * dx);
			const float slip = (pSpeed > 0.f) ? vLat * std::max(t, 0.f) / pSpeed : 0.f;
			sum += c.value * ((slip > reach) ? reach / slip : 1.f);
			++nIn;
			if (std::fabs(c.x - tx) + std::fabs(c.z - tz) < 1.f) {
				tgtLat = slip;
			}
		}
		return sum;
	};

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
		if ((edef == nullptr) || ((edef->GetCategory() & canTargetCat) == 0)) {
			++nCat;
			continue;
		}
		if (isRoleComm && edef->IsRoleComm()) {  // NOTE: BAR, comm kamikaze; the D-gun does 0 to commanders
			++nComm;
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		if (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAirDGun() : cdef->HasSurfToAirDGun())) {  // notAA
			++nAir;
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
		// No walk-in after what outruns him: that is the scout chase, with a
		// mex claim queued behind it.
		if (!inRange && (edef->GetSpeed() > cdef->GetSpeed())) {
			++nFar;
			continue;
		}
		// Nor into a gun that outranges the beam: it fires the whole walk.
		if (!inRange && !edef->IsMobile() && edef->IsAttacker()
			&& (edef->GetMaxRange(CCircuitDef::RangeType::LAND) >= wRange))
		{
			++nFar;
			continue;
		}
		// The terrain ray, only in range and only for a beam that does not hug
		// the ground (see isLowTraj).
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
			if (!ffBuilt) {
				buildFF();
			}
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

		int nIn = 0;
		float tLat = 0.f;
		float defScore;
		if (inRange) {
			defScore = beamValue(pos.x, pos.z, ePos.x, ePos.z, nIn, tLat);
		} else {
			const float ex = ePos.x - pos.x, ez = ePos.z - pos.z;
			const float d = std::sqrt(ex * ex + ez * ez);
			const float back = (d > wRange) ? (d - wRange) / d : 0.f;
			defScore = beamValue(pos.x + ex * back, pos.z + ez * back, ePos.x, ePos.z, nIn, tLat);
		}
		if (inRange) {
			if (maxScore < defScore) {
				maxScore = defScore;
				bestTarget = enemy;
				bestN = nIn;
				bestLat = tLat;
			}
		} else if (maxFar < defScore) {
			maxFar = defScore;
			bestFar = enemy;
		}
	}

	// An in-range shot outranks a walk, unless the bank holds one shot and the
	// walk's beam is worth more: one charge goes on the heaviest (docs/24).
	const bool oneShot = eCur < 2.f * unit->GetDGunCostE();
	const char* why = "range";
	if ((bestFar != nullptr) && ((bestTarget == nullptr) || (oneShot && (maxFar > maxScore)))) {
		why = (bestTarget == nullptr) ? "walk" : "walk-heavier";
		bestTarget = bestFar;
		maxScore = maxFar;
		bestN = 0;
		bestLat = 0.f;
	}
	const bool walk = (why[0] == 'w');
	if (bestTarget == nullptr) {
		if (trace) {
			logFrame = frame;
			const char* names[] = {"hidden", "weak", "category", "commander", "air", "far", "terrain", "friendly"};
			const int counts[] = {nHid, nWeak, nCat, nComm, nAir, nFar, nRay, nFF};
			int top = -1;
			for (int i = 0; i < 8; ++i) {
				if ((counts[i] > 0) && ((top < 0) || (counts[i] > counts[top]))) {
					top = i;
				}
			}
			circuit->LOG("apex: dgun held t=%i %s why=%s e=%.0f enemies=%d hid=%d weak=%d cat=%d comm=%d air=%d far=%d ray=%d ff=%d own=%d",
					circuit->GetTeamId(), cdef->GetDef()->GetName(), (top < 0) ? "none" : names[top], eCur,
					(int)enemies.size(), nHid, nWeak, nCat, nComm, nAir, nFar, nRay, nFF, (int)ffX.size());
		}
		return;
	}
	if ((isRoleComm || trace) && (frame >= fireLogFrame + FRAMES_PER_SEC)) {
		fireLogFrame = frame;
		CCircuitDef* tdef = bestTarget->GetCircuitDef();
		circuit->LOG("apex: dgun fired t=%i %s -> %s why=%s pow=%.2f d=%.0f inBeam=%d score=%.2f slip=%.0f e=%.0f orders=%d",
				circuit->GetTeamId(), cdef->GetDef()->GetName(),
				(tdef != nullptr) ? tdef->GetDef()->GetName() : "?", why,
				(tdef != nullptr) ? tdef->GetPower() : 0.f, pos.distance2D(bestTarget->GetPos()),
				bestN, maxScore, bestLat, eCur, unit->GetDGunOrders() + 1);
	}
	reissueAt = frame + FRAMES_PER_SEC * (walk ? 3 : 1);
	unit->ManualFire(bestTarget, frame + FRAMES_PER_SEC * (walk ? 10 : 5));
	unit->ClearTarget();
	isBlocking = true;
}

} // namespace circuit
