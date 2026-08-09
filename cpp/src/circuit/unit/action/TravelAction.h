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

	// apex: lateral offset from the shared path, in elmos, signed. A squad walks
	// ONE path -- ISquadTask::ActivePath hands every unit the same CPathInfo --
	// so without this the whole squad files onto a single point and arrives as a
	// blob. With it each unit walks its own line parallel to the path and the
	// squad travels line-abreast, already facing the enemy when contact happens.
	// apexearth: "lots of our basic moves are still an entire squad to a single
	// point on the map... they should really be forming a wall against the enemy
	// so when the enemy comes in to attack we have that 'wall of fire' coming out
	// of all our nicely positioned units... also it helps to block enemy 'leaks'
	// (raiding parties)."
	// DEFAULTS TO ZERO and only squad tasks set it, so builders and every other
	// ITravelAction user are byte-for-byte unchanged.
	void SetLateral(float offset) { lateral = offset; }
	float GetLateral() const { return lateral; }

protected:
	int CalcSpeedStep(CCircuitAI* circuit, float& stepSpeed);

	std::shared_ptr<CPathInfo> pPath;
	float lateral = 0.f;
	float speed;
	int pathIterator;
	int increment;
	int minSqDist;
	int lastSector;  // last issued sector index
	int lastFrame;

#ifdef DEBUG_VIS
public:
	void Log(CCircuitAI* circuit);
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_ACTION_TRAVELACTION_H_
