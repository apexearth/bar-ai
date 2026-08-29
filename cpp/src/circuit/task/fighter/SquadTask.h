/*
 * SquadTask.h
 *
 *  Created on: Jan 23, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_SQUADTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_SQUADTASK_H_

#include "task/fighter/FighterTask.h"
#include "terrain/path/MicroPather.h"

#include <memory>

namespace circuit {

class CCircuitDef;

// Elmos of mean distance-from-centroid a squad may have and still count as a
// single fighting force. Roughly 1.5x a T1 weapon range, so a squad inside it
// can bring most of its guns to bear on the same target.
#define COHESION_MAX_SPREAD	700.f
// A strung-out squad is not worth nothing -- it still trickles damage in -- so
// the derating bottoms out rather than reaching zero.
#define COHESION_MIN_SCALE	0.35f

// Fraction of a full circle a single range-row may wrap around its target.
// 0.9 packs a squad into a half circle; 1.2 is a broad crescent. NOT a ring --
// apexearth: "we don't organize into balls, we organize into curves/lines".
#define ARC_SPAN		0.9f
// apexearth: "some units easily die on the first hit... if i am just 10% out
// of range of that enemy unit, i absolutely must move away from them." Used
// when the current target outranges a row's own weapon: stand at the
// TARGET's range plus this margin, not our own (shorter) range, so a
// mismatched engagement never puts us inside a reach we cannot answer.
#define OUTRANGED_SAFETY_MARGIN	1.1f
// apexearth: "our thug style units are afraid of rocket bots because they
// have more range. thugs/maces are more powerful than rocket bots so that's
// unfortunate." A row whose own CCircuitDef::GetPower() (damage*sqrt(health),
// precomputed per def -- see CircuitDef.cpp) beats the target's by this
// ratio trusts its own range instead of kiting off the target's longer one.
// NOT cost: checked corthud/armham/armrock (Thug/Mace/Rocketeer) via
// tools/unitdef.py and they are 140/130/120 metal -- similar T1 bot costs
// that cannot tell a brawler from a skirmisher apart.
//
// 1.15, not the first-guess 1.5: the outrange-power-diag log this ships with
// caught the first value red-handed -- Mace vs Rocketeer, the exact reported
// matchup, is only a 1.27x power ratio, and Thug vs Storm sits at 1.33x. Both
// need to read as dominant. Every confirmed non-dominant sample in the same
// data topped out at 0.86x (Thug vs a defense turret), so 1.15 clears both
// real cases with margin while keeping a large gap above genuinely-even or
// losing matchups.
//
// Known limitation, not yet worth the restructuring: GetPower() is a
// TYPE-level constant off max health, not live health. A row standing at
// 10% HP still reads as dominant over a full-health target it can no longer
// actually out-trade. CThreatMap::GetUnitPower does the live-health version
// of this same formula for our own units; the target only has CEnemyInfo's
// last-seen health, which is enough to notice but adds complexity this
// specific report does not need yet.
#define POWER_DOMINANCE_RATIO	1.15f
// apex: radians per second the standoff ring precesses around its target. At a
// 500-elmo standoff that is ~90 elmos/second of lateral travel -- under the
// speed of the mobile units that use this formation, so orbiting never costs a
// unit its slot in the arc, and slow enough to read as circling rather than
// spinning. Halved from a first guess of 0.35 after doing that arithmetic: 0.35
// would have demanded ~175 elmos/s, above several T1 bots.
#define ORBIT_RATE				0.18f
// apex: lateral spacing between neighbouring units when a squad travels, and the
// widest the line may get. 96 elmos is roughly two build squares -- enough that
// units are not shouldering each other into the terrain, tight enough that the
// line is a wall rather than a picket. The cap keeps a 20-unit squad from
// spreading across 1900 elmos and arriving as two separate fights.
#define SQUAD_FILE_SPACING		96.f
#define SQUAD_FILE_MAX_WIDTH	768.f
// apex: how far apart a CHARGER stands from its neighbour, travelling and in
// formation. The commander D-gun carries `noexplode = true` and range 262 (read
// from CORCOM.lua), so the projectile does not stop at the first thing it hits
// -- it keeps flying, and everything on that line dies to one shot. Two
// Behemoths inside 262 elmos of each other are therefore one target, not two.
// 360 clears that with margin without breaking the squad into separate fights.
// apexearth: "they should spread out and not be too close which would allow
// multiple of them to be d-gunned together in a single shot."
#define CHARGE_SPACING			360.f
// Share of charger squads that take the straight route. The rest keep the
// ordinary threat-aware path, which is the flank -- "can still do a small
// allotment to that side attack sometimes".
#define CHARGE_DIRECT_PCT		80
// A threat ceiling no real tile reaches, so the charger's route is decided by
// distance alone. CMicroPather compares `threatArray[i] > maxThreat`, so any
// large finite value works and avoids infinities in the cost arithmetic.
#define CHARGE_THREAT_CEILING	1e9f
// Spacing between neighbours on a regroup line, in elmos.
#define LINE_SPACING		110.f
// apexearth: "best would be if the hurt guys just move towards the back of
// the pack." A unit IFighterTask::OnUnitDamaged marks a "coward" (health at
// or below its retreat threshold, but still safely in the fight -- in LOS,
// in range, threat tolerable) is not sent home; it stays in the squad and is
// simply stood further out on its row's standoff ring than its healthy
// squadmates, who are between it and the target on most bearings. Runtime:
// apex_coward_rear_mod.
#define COWARD_REAR_MOD		1.35f

class ISquadTask: public IFighterTask {
protected:
	// apex: the squad's sticky "finish the wounded" target id (0 = none).
	int finishId = 0;
	ISquadTask(ITaskModule* mgr, FightType type, float powerMod);
public:
	virtual ~ISquadTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Merge(ISquadTask* task);
	virtual bool TrySquadRetreat(CCircuitUnit* unit) override;
	bool TryAllLowFallback();

	// The last FindTarget pass's strongest strength-test refusal, as
	// power/need. Measured (2026-08-16): median 0.82, 69% of refusal passes
	// >= 0.7 -- squads walk away from fights one merge would win, and the
	// merge check only ran every 32nd update. A near-miss accelerates it.
	float lastRefused = .0f;

	const std::map<float, std::set<CCircuitUnit*>>& GetRangeUnits() const { return rangeUnits; }

	CCircuitUnit* GetLeader() const { return leader; }
	const springai::AIFloat3& GetLeaderPos(int frame) const;
	// Public because CSupportAction sizes an escort's standoff off it, and the
	// action is not a member of the task.
	float GetSpreadRadius() const;

	// role heavy + attribute melee: corjugg (Behemoth), corkorg (Juggernaut),
	// armbanth (Titan), armraz. All of them detonate on death, so the value is
	// delivered by arriving. CAttackTask::FindTarget already keys the
	// ignore-the-engage-margin charge off the same pair.
	static bool IsChargeDef(const CCircuitDef* cdef);

private:
	void FindLeader(decltype(units)::iterator itBegin, decltype(units)::iterator itEnd);

	bool IsMergeSafe() const;
	ISquadTask* CheckMergeTask();

protected:
	ISquadTask* GetMergeTask();
	springai::AIFloat3 LinePos(CCircuitUnit* unit, const springai::AIFloat3& centre) const;
	float GetCohesionScale() const;
	bool IsMustRegroup();
	void ActivePath(float speed = NO_SPEED_LIMIT);
	// apex: live power fraction -- attackPower is DEF power and never sees
	// damage, so a mauled squad evaluated fights as if fresh (apexearth: "I
	// still see us take on fights where we're outgunned"). Power-weighted
	// health, 1.0 for a fresh squad. Promoted from CAttackTask so DEFEND and
	// RAID odds use the same truth.
	float GetHealthScale() const;
	NSMicroPather::HitFunc GetHitTest() const;
	void Attack(const int frame);
	void Attack(const int frame, const bool isGround);

	float lowestRange;
	float highestRange;
	float lowestSpeed;
	float highestSpeed;
	// NOTE: Using unit instead of area directly may save from processing UpdateAreaUsers
	CCircuitUnit* leader;  // slowest, weakest unit, true leader
	springai::AIFloat3 groupPos;
	springai::AIFloat3 prevGroupPos;
	std::shared_ptr<CPathInfo> pPath;

	std::map<float, std::set<CCircuitUnit*>> rangeUnits;

	int groupFrame;
	int attackFrame;

#ifdef DEBUG_VIS
public:
	virtual void Log() override;
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_SQUADTASK_H_
