/*
 * DGunAction.h
 *
 *  Created on: Jul 29, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_UNIT_ACTION_DGUNACTION_H_
#define SRC_CIRCUIT_UNIT_ACTION_DGUNACTION_H_

#include "unit/action/UnitAction.h"

namespace circuit {

class CDGunAction: public IUnitAction {
public:
	// mayClose: the owner may WALK to a target beyond dgun range when that
	// target is worth more than the owner itself (see Update). Only tasks
	// where the owner is free to step out (build/patrol) pass true; a
	// retreating unit must never turn back for a shot.
	CDGunAction(CCircuitUnit* owner, float range, bool mayClose = false);
	virtual ~CDGunAction();

	virtual void Update(CCircuitAI* circuit) override;

private:
	float range;
	bool mayClose;
	unsigned int updCount;
	int logFrame = -999999;   // sampled gate trace, see Update
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_ACTION_DGUNACTION_H_
