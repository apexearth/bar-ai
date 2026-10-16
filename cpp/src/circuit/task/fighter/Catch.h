/*
 * Catch.h
 *
 * apex_open_race: whether a pursuit can close. Out of weapon reach, a target fleeing faster than
 * we close never comes into range; slower, catching it walks gap x v / (v - flee).
 * P(reach) = reach / (reach + that walk), 1 inside reach.
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_CATCH_H_
#define SRC_CIRCUIT_TASK_FIGHTER_CATCH_H_

#include "unit/enemy/EnemyUnit.h"
#include "CircuitAI.h"
#include "util/Defines.h"
#include "util/Utils.h"

#include <algorithm>
#include <map>

namespace circuit {

inline float CatchP(const springai::AIFloat3& from, float ourSpeed, float reach, const CEnemyInfo* e)
{
	const springai::AIFloat3& ePos = e->GetPos();
	const float d = from.distance2D(ePos);
	const float r = std::max(reach, 1.f);
	if (d <= r) {
		return 1.f;
	}
	const springai::AIFloat3& vel = e->GetVel();
	const float away = std::max(((ePos.x - from.x) * vel.x + (ePos.z - from.z) * vel.z) / d * FRAMES_PER_SEC, 0.f);
	const float v = std::max(ourSpeed, 1.f);
	const float close = v - away;
	if (close <= 0.f) {
		return 0.f;
	}
	return r / (r + (d - r) * v / close);
}

struct SChaseStat {
	int picks = 0;      // targets chosen
	int fast = 0;       // ...that out-run our slowest
	float sec = 0.f;    // seconds spent on such a target
	float dist = 0.f;   // and walked meanwhile
	int unreach = 0;    // candidates fleeing faster than we close, out of reach
	int refused = 0;    // ...skipped for it (switch on)
	int air = 0;        // guards' air targets they cannot shoot, skipped (switch on)
	int logAt = 0;
};

inline SChaseStat& ChaseStat(const CCircuitAI* circuit)
{
	static std::map<const CCircuitAI*, SChaseStat> stats;
	return stats[circuit];
}

inline void ChaseStatLog(CCircuitAI* circuit, int frame)
{
	SChaseStat& cs = ChaseStat(circuit);
	if (frame < cs.logAt) {
		return;
	}
	cs.logAt = frame + FRAMES_PER_SEC * 60;
	circuit->LOG("apex: chase-stat t=%i on=%i picks=%i fast=%i sec=%.0f dist=%.0f unreach=%i refused=%i air=%i",
			circuit->GetTeamId(), (circuit->GetTunable("apex_open_race", 0.f) > 0.f) ? 1 : 0,
			cs.picks, cs.fast, cs.sec, cs.dist, cs.unreach, cs.refused, cs.air);
	const int at = cs.logAt;
	cs = SChaseStat();
	cs.logAt = at;
}

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_CATCH_H_
