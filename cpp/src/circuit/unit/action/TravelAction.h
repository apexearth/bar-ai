/*
 * TravelAction.h
 *
 *  Created on: Feb 16, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_UNIT_ACTION_TRAVELACTION_H_
#define SRC_CIRCUIT_UNIT_ACTION_TRAVELACTION_H_

#include "unit/action/UnitAction.h"
#include "terrain/path/PathInfo.h"

#include <memory>

namespace circuit {

class ITravelAction: public IUnitAction {
public:
	ITravelAction(CCircuitUnit* owner, Type type, int squareSize, float speed = NO_SPEED_LIMIT);
	ITravelAction(CCircuitUnit* owner, Type type, const std::shared_ptr<CPathInfo>& pPath,
			int squareSize, float speed = NO_SPEED_LIMIT);
	virtual ~ITravelAction();

	virtual void OnEnd() override;

	void SetPath(const std::shared_ptr<CPathInfo>& pPath, float speed = NO_SPEED_LIMIT);
	const std::shared_ptr<CPathInfo>& GetPath() const { return pPath; }


protected:
	int CalcSpeedStep(CCircuitAI* circuit, float& stepSpeed);
	// Keep the unit's formation heading square to the LOCAL direction of
	// travel, so a line stays perpendicular to the path around corners
	// instead of shearing. The offset itself is applied in CCircuitUnit's
	// command funnel; only this action knows the heading.
	void FaceStep(int idx);

	std::shared_ptr<CPathInfo> pPath;
	float speed;
	int pathIterator;
	int increment;
	int minSqDist;
	int lastSector;  // last issued sector index
	int lastQueued = -1;     // apex: the furthest path index this unit has been ordered to (apex_travel_lean)
	float lastWanted = -1.f; // apex: the wanted speed last sent
	springai::AIFloat3 lastLeanPos = springai::AIFloat3(-1.f, 0.f, -1.f);  // apex: the waypoint last ordered, kept across a path replacement
	int lastFrame;

#ifdef DEBUG_VIS
public:
	void Log(CCircuitAI* circuit);
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_ACTION_TRAVELACTION_H_
