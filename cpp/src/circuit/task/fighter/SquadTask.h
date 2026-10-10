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

class ISquadTask: public IFighterTask {
protected:
	ISquadTask(ITaskModule* mgr, FightType type, float powerMod);
public:
	virtual ~ISquadTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Merge(ISquadTask* task);

	const std::map<float, std::set<CCircuitUnit*>>& GetRangeUnits() const { return rangeUnits; }

	CCircuitUnit* GetLeader() const { return leader; }
	const springai::AIFloat3& GetLeaderPos(int frame) const;

	static bool SameClimb(CCircuitAI* circuit, CCircuitDef* a, CCircuitDef* b);

private:
	void FindLeader(decltype(units)::iterator itBegin, decltype(units)::iterator itEnd);

	bool IsMergeSafe() const;
	ISquadTask* CheckMergeTask();

protected:
	ISquadTask* GetMergeTask();
	bool IsMustRegroup();
	void ActivePath(float speed = NO_SPEED_LIMIT);
	NSMicroPather::HitFunc GetHitTest() const;
	void Attack(const int frame);
	void Attack(const int frame, const bool isGround);
	// one task update (1 s) plus the turn to walk away
	static constexpr float DGUN_REACT_S = 2.f;
	static float DGunKeepOut(CCircuitDef* u, CCircuitDef* t, float& hold);
	bool IsInsideDGun(int frame);
	bool dgunNear = false;  // the last Attack() had a D-gun carrier to keep out of

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

	// Kept across the fight revert: AntiAirTask and AntiHeavyTask size their
	// odds with it, and neither is being reverted.
public:
	float GetHealthScale() const;
	float GetSpreadRadius() const;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_SQUADTASK_H_
