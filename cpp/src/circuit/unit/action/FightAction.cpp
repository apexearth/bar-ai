/*
 * FightAction.cpp
 *
 *  Created on: Jan 13, 2015
 *      Author: rlcevg
 */

#include "unit/action/FightAction.h"
#include "unit/CircuitUnit.h"
#include "unit/enemy/EnemyManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"
#include "spring/SpringCallback.h"

#include "AISCommands.h"

namespace circuit {

using namespace springai;

CFightAction::CFightAction(CCircuitUnit* owner, int squareSize, float speed)
		: ITravelAction(owner, Type::FIGHT, squareSize, speed)
{
}

CFightAction::CFightAction(CCircuitUnit* owner, const std::shared_ptr<CPathInfo>& pPath,
		int squareSize, float speed)
		: ITravelAction(owner, Type::FIGHT, pPath, squareSize, speed)
{
}

CFightAction::~CFightAction()
{
}

void CFightAction::Update(CCircuitAI* circuit)
{
	if (lastFrame + FRAMES_PER_SEC * 2 > circuit->GetLastFrame()) {
		return;
	}
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	if (unit->IsJumping()) {
		return;
	}
	lastFrame = circuit->GetLastFrame();

	float stepSpeed;
	int pathMaxIndex = CalcSpeedStep(circuit, stepSpeed);
	switch (pathMaxIndex) {
		case -2:  // arrived
			TRY_UNIT(circuit, unit,
				unit->CmdFightTo(pPath->posPath.back(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::FWALK);
			)
			return;
		case -1: return;  // continue with current waypoints
		default: break;  // update waypoints
	}
	int step = pathIterator;
	// apex: the MoveAction lean (apex_travel_lean): LEAN_AHEAD waypoints at once, re-ordered near the last.
	constexpr int LEAN_AHEAD = 4;
	// ...only where nothing armed can reach the unit before the far waypoint does: a fight needs the
	// per-second orders (the first A/B: army held worse in 3 of 4 seeds with lean everywhere).
	bool lean = circuit->GetTunable("apex_travel_lean", 0.f) > 0.f;
	if (lean) {
		const AIFloat3& up = unit->GetPos(lastFrame);
		const int t0 = std::min(pathIterator + increment * LEAN_AHEAD, pathMaxIndex);
		const float r = up.distance2D(pPath->posPath[t0]) + unit->GetCircuitDef()->GetMaxRange();
		lean = circuit->GetEnemyManager()->GetEnemyArmedCostNear(up, r) <= 0.f;
		if (!lean) {
			lastQueued = -1;
			lastLeanPos.x = -1.f;
		}
	}
	if (lean && (lastQueued >= 0) && (pathIterator + increment < lastQueued)) {
		return;
	}
	if (lean && !(unit->IsAllowedToJump() && unit->IsJumpReady())) {
		const int t = std::min(pathIterator + increment * LEAN_AHEAD, pathMaxIndex);
		const AIFloat3& pos = pPath->posPath[t];
		lastQueued = t;
		const bool same = (lastLeanPos.x >= 0.f) && (pos.SqDistance2D(lastLeanPos) < float(minSqDist))
				&& circuit->GetCallback()->Unit_HasCommands(unit->GetId());
		TRY_UNIT(circuit, unit,
			if (!same) {
				FaceStep(t);
				unit->CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::FWALK);
				lastLeanPos = pos;
			}
			if (stepSpeed != lastWanted) {
				unit->CmdWantedSpeed(stepSpeed);
				lastWanted = stepSpeed;
			}
		)
		return;
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
				unit->CmdFightTo(pos, options, lastFrame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::FWALK);
			}
		} else {
			FaceStep(step);
			const AIFloat3& pos = pPath->posPath[step];
			unit->CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, lastFrame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::FWALK);
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
			unit->CmdFightTo(pos, options, lastFrame + FRAMES_PER_SEC * 60 * i, CCircuitUnit::OrdSrc::FWALK);
		}
		lastQueued = step;
	)
}

} // namespace circuit
