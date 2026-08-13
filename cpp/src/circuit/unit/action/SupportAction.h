/*
 * GuardAction.h
 *
 *  Created on: Jul 3, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_UNIT_ACTION_SUPPORTACTION_H_
#define SRC_CIRCUIT_UNIT_ACTION_SUPPORTACTION_H_

#include "unit/action/UnitAction.h"

#include "AIFloat3.h"

namespace circuit {

class CSupportAction: public IUnitAction {
public:
	CSupportAction(CCircuitUnit* owner);
	virtual ~CSupportAction();

	virtual void Update(CCircuitAI* circuit) override;

private:
	unsigned int updCount;
	bool isLowUpdate;

	// apex: how far behind the squad this escort may stand, as a COVERAGE
	// radius; the standoff itself is derived from it and the squad's own spread.
	// ZERO for everything that is not an unarmed sensor escort, and zero takes
	// the stock walk-to-the-leader path below unchanged -- state and all.
	float reach;
	// The slot, and the leader position it was computed from. Recomputing the
	// slot every update would make the aim point jitter (both the direction of
	// travel and the squad's spread move every frame), and an aim point that
	// jitters by more than the stop-pushing radius issues an order every update
	// forever -- including while the squad stands still, where stock converges
	// and goes quiet. Latching on leader movement bounds the order rate at
	// leaderTravel / ESCORT_RESLOT instead.
	bool hasStand;
	springai::AIFloat3 stand;
	springai::AIFloat3 standFrom;
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_ACTION_SUPPORTACTION_H_
