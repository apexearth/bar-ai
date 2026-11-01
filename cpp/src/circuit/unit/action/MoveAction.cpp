/*
 * MoveAction.cpp
 *
 *  Created on: Jan 13, 2015
 *      Author: rlcevg
 */

#include "unit/action/MoveAction.h"
#include "unit/CircuitUnit.h"
#include "unit/enemy/EnemyManager.h"
#include "task/fighter/FighterTask.h"
#include "CircuitAI.h"
#include "terrain/TerrainManager.h"
#include "util/Utils.h"
#include "spring/SpringCallback.h"

#include "AISCommands.h"
#include "Command.h"

namespace circuit {

using namespace springai;

CMoveAction::CMoveAction(CCircuitUnit* owner, int squareSize, float speed)
		: ITravelAction(owner, Type::MOVE, squareSize, speed)
{
}

CMoveAction::CMoveAction(CCircuitUnit* owner, const std::shared_ptr<CPathInfo>& pPath,
		int squareSize, float speed)
		: ITravelAction(owner, Type::MOVE, pPath, squareSize, speed)
{
}

CMoveAction::~CMoveAction()
{
}

// His 10-14: a squad sent at a pack in our base walked straight into it on a move order. A travel
// order whose point already has an armed enemy within this unit's range is a fight order instead,
// so the unit stops at range and fights. Raids and scouts keep walking (a raid passes small stuff);
// fighting everywhere lost a same-seed 2v2 outright.
static void TravelTo(CCircuitAI* circuit, CCircuitUnit* unit, const AIFloat3& pos, short options, int timeout)
{
	if (circuit->GetFightTunable("apex_fight_travel", 0.f, circuit->IsStockFor(unit->GetCircuitDef())) > 0.f) {
		IUnitTask* task = unit->GetTask();
		bool walker = (task == nullptr) || (task->GetType() != IUnitTask::Type::FIGHTER);
		if (!walker) {
			const IFighterTask::FightType ft = static_cast<IFighterTask*>(task)->GetFightType();
			walker = (ft == IFighterTask::FightType::RAID) || (ft == IFighterTask::FightType::SCOUT);
		}
		const float range = unit->GetCircuitDef()->GetMaxRange();
		if (!walker && (range > 0.f) && (circuit->GetEnemyManager()->GetEnemyArmedCostNear(pos, range) > 0.f)) {
			// a flier on a fight order drops its load on whatever it passes (bombers on ticks, his 10-15)
			if (unit->GetCircuitDef()->IsAbleToFly()) {
				static int fliersKept = 0;
				if ((++fliersKept % 50) == 1) {
					circuit->LOG("apex: fight-travel flier-kept n=%i def=%s", fliersKept, unit->GetCircuitDef()->GetDef()->GetName());
				}
				unit->CmdMoveTo(pos, options, timeout, CCircuitUnit::OrdSrc::TRAVEL);
				return;
			}
			unit->CmdFightTo(pos, options, timeout, CCircuitUnit::OrdSrc::FWALK);
			return;
		}
	}
	unit->CmdMoveTo(pos, options, timeout, CCircuitUnit::OrdSrc::TRAVEL);
}

void CMoveAction::Update(CCircuitAI* circuit)
{
	if (lastFrame + FRAMES_PER_SEC > circuit->GetLastFrame()) {
		return;
	}
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	if (unit->IsJumping()) {
		return;
	}
	lastFrame = circuit->GetLastFrame();
	// apex: HOW LATE OUR ORDERS LAND (his 10-31: ~8 s online). A sent waypoint is looked for in the unit's queue
	// each update; the frames until it appears are one sample of the order lag.
	if (lagProbeAt >= 0) {
		if (lastFrame - lagProbeAt > FRAMES_PER_SEC * 60) {
			lagProbeAt = -1;
		} else {
			bool seen = false;
			auto commands = unit->GetUnit()->GetCurrentCommands();
			for (springai::Command* c : commands) {
				const std::vector<float> p = c->GetParams();
				if ((p.size() >= 3) && (SQUARE(p[0] - lagProbePos.x) + SQUARE(p[2] - lagProbePos.z) < SQUARE(16.f))) {
					seen = true;
					break;
				}
			}
			utils::free_clear(commands);
			if (seen) {
				// a paused travel (a bomber's pass, a wait) skips checks; past a 2 s gap the arrival is unknown
				if (lastFrame - lagProbeLast <= FRAMES_PER_SEC * 2) {
					circuit->NoteOrderLag(lastFrame - lagProbeAt);
				}
				lagProbeAt = -1;
			} else {
				lagProbeLast = lastFrame;
			}
		}
	}

	float stepSpeed;
	int pathMaxIndex = CalcSpeedStep(circuit, stepSpeed);
	switch (pathMaxIndex) {
		case -2:  // arrived
			TRY_UNIT(circuit, unit,
				TravelTo(circuit, unit, pPath->posPath.back(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60);
			)
			return;
		case -1: return;  // continue with current waypoints
		default: break;  // update waypoints
	}
	int step = pathIterator;
	// apex: A WALKING UNIT WAS RE-ORDERED EVERY SECOND -- a waypoint, a queued lookahead and a speed, three
	// network commands a second per unit whether anything changed or not (his 10-18 online 8v8: ~700 orders
	// a second from our AIs, travel the largest source). Lean: it is told LEAN_AHEAD waypoints at once and
	// re-ordered only when it nears the last of them (or the path is replaced, which resets lastQueued);
	// the speed is sent when it changes.
	constexpr int LEAN_AHEAD = 4;
	// ...only where nothing armed can reach the unit before the far waypoint does: a fight needs the
	// per-second orders (the first A/B: army held worse in 3 of 4 seeds with lean everywhere).
	bool lean = circuit->GetTunable("apex_travel_lean", 1.f) > 0.f;
	const AIFloat3& up = unit->GetPos(lastFrame);
	// ...and far enough ahead that the next order lands before the unit gets there: its speed over the order lag
	// and the update period (his 10-31: fast bombers turned around between orders in a lagging game)
	// ...only while the lag is real: a local game reads ~1-2 s (the probe's own cadence) and must travel as before
	const float lagS = circuit->GetOrderLagSec();
	const float leadD = ((circuit->GetTunable("apex_travel_lag", 1.f) > 0.f) && (lagS > CCircuitAI::ORDER_LAG_REAL_S))
			? unit->GetCircuitDef()->GetSpeed() * (lagS + 2.f) : 0.f;
	if (lean) {
		const int t0 = std::min(pathIterator + increment * LEAN_AHEAD, pathMaxIndex);
		const float r = up.distance2D(pPath->posPath[t0]) + unit->GetCircuitDef()->GetMaxRange();
		lean = circuit->GetEnemyManager()->GetEnemyArmedCostNear(up, r) <= 0.f;
		if (!lean) {
			lastQueued = -1;
			lastLeanPos.x = -1.f;
		}
	}
	if (lean && (lastQueued >= 0) && (pathIterator + increment < lastQueued)
		&& ((leadD <= 0.f) || (lastLeanPos.x < 0.f) || (up.distance2D(lastLeanPos) > leadD))) {
		return;
	}
	// ONE order, to the waypoint LEAN_AHEAD steps on; the engine paths the ground between. A replaced path
	// that still points at the same ground sends nothing: queuing the lookahead on every replacement sent
	// 2.4x the orders (smoke, travel 4,188 -> 10,048).
	if (lean && !(unit->IsAllowedToJump() && unit->IsJumpReady())) {
		int t = std::min(pathIterator + increment * LEAN_AHEAD, pathMaxIndex);
		while ((leadD > 0.f) && (t < pathMaxIndex) && (up.distance2D(pPath->posPath[t]) < 2.f * leadD)) {
			t = std::min(t + increment, pathMaxIndex);
		}
		const AIFloat3& pos = pPath->posPath[t];
		lastQueued = t;
		const bool same = (lastLeanPos.x >= 0.f) && (pos.SqDistance2D(lastLeanPos) < float(minSqDist))
				&& circuit->GetCallback()->Unit_HasCommands(unit->GetId());
		TRY_UNIT(circuit, unit,
			if (!same) {
				FaceStep(t);
				TravelTo(circuit, unit, pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60);
				lastLeanPos = pos;
				if ((lagProbeAt < 0) && (unit->GetMoveSentAt() == lastFrame)) {
					lagProbeAt = lastFrame;
					lagProbeLast = lastFrame;
					lagProbePos = unit->GetMoveSentPos();
				}
			}
			if (stepSpeed != lastWanted) {
				unit->CmdWantedSpeed(stepSpeed);
				lastWanted = stepSpeed;
			}
		)
		return;
	}
	// THE SAME WAYPOINT IS NOT A NEW ORDER (apex_travel_samestep): off the lean path the unit is re-checked
	// every second, and re-sent its waypoint, lookahead and speed even while it is still walking to the same
	// one -- our moves were 1,948 a team a minute against BARb's 982 (his 10-19 Odderon 8v8). Re-sent only once
	// the first waypoint has moved on, or the unit has no order left.
	if ((circuit->GetTunable("apex_travel_samestep", 0.f) > 0.f) && !(unit->IsAllowedToJump() && unit->IsJumpReady())) {
		const AIFloat3& sp = pPath->posPath[step];
		if ((lastStepPos.x == sp.x) && (lastStepPos.z == sp.z)
			&& circuit->GetCallback()->Unit_HasCommands(unit->GetId()))
		{
			return;
		}
		lastStepPos = sp;
	}

	TRY_UNIT(circuit, unit,
		constexpr short options = UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY;
		if (unit->IsAllowedToJump() && unit->IsJumpReady()) {
			const AIFloat3& startPos = unit->GetPos(lastFrame);
			const float range = unit->GetCircuitDef()->GetJumpRange();
			const float sqRange = SQUARE(range);
			for (; (step < pathMaxIndex) && (pPath->posPath[step].SqDistance2D(startPos) < sqRange); ++step);
			AIFloat3 jumpPos = pPath->posPath[std::max(0, step - 1)];
			const float sqJumpDist = jumpPos.SqDistance2D(startPos);
			bool isBadJump = sqJumpDist < SQUARE(range * 0.5f);
			if (!isBadJump) {
				isBadJump = SQUARE(range * 1.2f) < sqJumpDist;
				if (isBadJump) {
					jumpPos = startPos + (jumpPos - startPos).Normalize2D() * range;
				}
				unit->CmdJumpTo(jumpPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60);
			}
			if (isBadJump) {
				FaceStep(step);
				const AIFloat3& pos = pPath->posPath[step];
				TravelTo(circuit, unit, pos, options, lastFrame + FRAMES_PER_SEC * 60);
			}
		} else {
			FaceStep(step);
			const AIFloat3& pos = pPath->posPath[step];
			TravelTo(circuit, unit, pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60);
		}
		if (!lean || (stepSpeed != lastWanted)) {
			unit->CmdWantedSpeed(stepSpeed);
			lastWanted = stepSpeed;
		}

		const int ahead = lean ? (2 + LEAN_AHEAD) : 3;
		for (int i = 2; (step < pathMaxIndex) && (i < ahead); ++i) {
			step = std::min(step + increment, pathMaxIndex);
			FaceStep(step);
			const AIFloat3& pos = pPath->posPath[step];
			TravelTo(circuit, unit, pos, options, lastFrame + FRAMES_PER_SEC * 60 * i);
		}
		lastQueued = step;
	)
}

} // namespace circuit
