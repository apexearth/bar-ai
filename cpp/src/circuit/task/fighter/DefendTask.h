/*
 * DefendTask.h
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_

#include "task/fighter/SquadTask.h"

namespace circuit {

class CDefendTask: public ISquadTask {
public:
	CDefendTask(ITaskModule* mgr, const springai::AIFloat3& position,
				FightType check, FightType promote, float maxPower, float powerMod);
	virtual ~CDefendTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;

	void SetPosition(const springai::AIFloat3& pos) { position = pos; }
	void SetMaxPower(float power) { maxPower = power * powerMod; }
//	void SetWantedTarget(CEnemyInfo* enemy) { SetTarget(enemy); }

	FightType GetPromote() const { return promote; }

public:
	// A pool split off the attack blob to answer a breach must not promote
	// straight back into ATTACK on its first update -- attackPower starts at
	// maxPower by construction, so without the hold the split would dissolve
	// before it arrived.
	void HoldPromote(int untilFrame) { noPromoteUntil = untilFrame; }

protected:
	float GetMaxPower() const { return maxPower; }

private:
	virtual void Merge(ISquadTask* task) override;
	bool FindTarget();
	void ApplyTargetPath(const CQueryPathMulti* query);
	void FallbackFrontPos();
	void ApplyFrontPos(const CQueryPathMulti* query);
	void FallbackBasePos();
	void ApplyBasePos(const CQueryPathSingle* query);
	void Fallback();

	FightType check;
	FightType promote;
	float maxPower;
	// Why FindTarget came up empty this pass, for the intent ping: the walk
	// back reads "back:hid"/"back:small"/... instead of an unexplained U-turn.
	std::string noTgtWhy;
	// How the current target got elected (atUs contact vs post election, and
	// the threat it was priced at) -- the chase ping carries it, so an army
	// dragged off by one scout shows which clause let it through.
	std::string tgtWhy;
	int noPromoteUntil = 0;              // see HoldPromote
	// FindTarget refused an enemy at home (or on top of us) on odds this
	// pass; the no-target fallback musters at base instead of the front.
	bool refusedHomeOdds = false;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
