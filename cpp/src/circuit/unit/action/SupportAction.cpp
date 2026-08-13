/*
 * GuardAction.cpp
 *
 *  Created on: Jul 3, 2016
 *      Author: rlcevg
 */

#include "unit/action/SupportAction.h"
#include "unit/CircuitUnit.h"
#include "task/fighter/SquadTask.h"
#include "unit/enemy/EnemyManager.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "AISCommands.h"

#include <algorithm>

namespace circuit {

using namespace springai;

// apex: clearance between the back of the squad and the escort standing behind
// it -- one build square of slack, so the escort is off the rear rank rather
// than inside it.
#define ESCORT_TRAIL_PAD	(SQUARE_SIZE * 8)
// How far the leader must move before the escort's slot is recomputed. Also the
// shortest baseline from which a direction of travel is trusted: closer than
// this, normalising it turns a metre of leader drift into a large swing of the
// slot. See the latch note in the header.
#define ESCORT_RESLOT		(SQUARE_SIZE * 16)

CSupportAction::CSupportAction(CCircuitUnit* owner)
		: IUnitAction(owner, Type::SUPPORT)
		, updCount(0)
		, reach(0.f)
		, hasStand(false)
{
	isBlocking = true;
	CCircuitDef* cdef = owner->GetCircuitDef();
	isLowUpdate = cdef->IsAttrMelee() || (cdef->GetReloadTime() >= FRAMES_PER_SEC * 5);
	// ONLY AN UNARMED SENSOR ESCORT TRAILS. IsRoleSupport(), which is what
	// decides whether this action exists at all, is the role MASK -- so it is
	// also true for corsumo, cormort, armsam and cormist, which carry "support"
	// as an ATTRIBUTE and are meant to be in the fight. Those keep reach 0 and
	// the stock behaviour exactly.
	if (!cdef->IsAttacker()) {
		if (cdef->GetJammerRadius() > 1.f) {
			// A jammer only hides what stands inside its radius.
			reach = cdef->GetJammerRadius();
		} else if (cdef->GetRadarRadius() > 1.f) {
			// A mobile radar carries far more radar than sight, and sight is what
			// turns a contact into something the squad's guns can be aimed at, so
			// the sight radius is the one that has to still cover the squad.
			reach = cdef->GetLosRadius();
		}
	}
}

CSupportAction::~CSupportAction()
{
}

void CSupportAction::Update(CCircuitAI* circuit)
{
	if ((updCount++ % 2 != 0) ||
		(isLowUpdate && (updCount % 4 != 1)))
	{
		return;
	}

	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	ISquadTask* squad = static_cast<ISquadTask*>(unit->GetTask());
	CCircuitUnit* leader = squad->GetLeader();
	if (leader == nullptr) {
		return;
	}
	const int frame = circuit->GetLastFrame();
	const AIFloat3& leaderPos = leader->GetPos(frame);
	AIFloat3 pos = leaderPos;

	// AT THE BACK OF THE SQUAD, NOT ON ITS LEADER.
	//
	// apexearth: "have them stay towards the back of the squad if you can", and
	// on what it is worth: "we have sheldons and we just move them stupidly in a
	// tight ball... with a radar and a jammer these guys are super good."
	//
	// "Back" is measured against the squad's DIRECTION OF TRAVEL -- its task's
	// own destination -- because that is what the squad is walking into. Once
	// the two coincide the enemy centroid stands in for it, the same reference
	// ISquadTask::LinePos uses; if that is degenerate too the slot is the leader
	// and this is stock.
	//
	// The standoff is one squad-radius plus a build square, capped by what the
	// escort still covers from there. That cap is the binding one: every mobile
	// jammer in the game carries radardistancejam 450, so a jammer trailing
	// further than (450 - spread) is hiding nobody. On a squad that has sprawled
	// wider than its escort's reach the term goes to zero and the escort closes
	// back up -- coverage beats position.
	if (reach > 0.f) {
		if (!hasStand || (leaderPos.SqDistance2D(standFrom) > SQUARE(ESCORT_RESLOT))) {
			AIFloat3 slot = leaderPos;
			AIFloat3 dir = squad->GetPosition() - leaderPos;
			dir.y = 0.f;
			if (dir.SqLength2D() < SQUARE(ESCORT_RESLOT)) {
				dir = circuit->GetEnemyManager()->GetEnemyPos() - leaderPos;
				dir.y = 0.f;
			}
			if (dir.SqLength2D() >= SQUARE(ESCORT_RESLOT)) {
				dir.Normalize2D();
				const float spread = squad->GetSpreadRadius();
				const float back = std::min(spread + ESCORT_TRAIL_PAD,
						std::max(0.f, reach - spread));
				slot = leaderPos - dir * back;
				CTerrainManager::CorrectPosition(slot);
				// A slot the escort cannot reach is an order it re-issues on every
				// update for as long as the squad stands there. CorrectPosition
				// only clamps to the map, so it does not rule that out -- water
				// and cliffs behind the squad both survive it. Fall back to the
				// leader, which is stock, rather than push at a wall.
				if (!circuit->GetTerrainManager()->CanMoveToPos(unit->GetArea(), slot)) {
					slot = leaderPos;
				}
			}
			stand = slot;
			standFrom = leaderPos;
			hasStand = true;
		}
		pos = stand;
	}

	if (pos.SqDistance2D(unit->GetPos(frame)) < SQUARE(SQUARE_SIZE * 8)) {
		return;  // stop pushing
	}
	TRY_UNIT(circuit, unit,
		if (unit->GetCircuitDef()->IsAttrMelee()) {
			unit->GetUnit()->Guard(leader->GetUnit());
		} else {
			unit->CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		}
	)
}

} // namespace circuit
