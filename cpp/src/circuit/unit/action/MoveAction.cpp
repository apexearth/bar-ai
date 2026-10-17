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

#include "AISCommands.h"

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
		unit->CmdWantedSpeed(stepSpeed);

		for (int i = 2; (step < pathMaxIndex) && (i < 3); ++i) {
			step = std::min(step + increment, pathMaxIndex);
			FaceStep(step);
			const AIFloat3& pos = pPath->posPath[step];
			TravelTo(circuit, unit, pos, options, lastFrame + FRAMES_PER_SEC * 60 * i);
		}
	)
}

} // namespace circuit
