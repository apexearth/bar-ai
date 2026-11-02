/*
 * RaidTask.h
 *
 *  Created on: Jan 6, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_RAIDTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_RAIDTASK_H_

#include "task/fighter/SquadTask.h"

namespace circuit {

class CRaidTask: public ISquadTask {
public:
	CRaidTask(ITaskModule* mgr, float maxPower, float powerMod);
	virtual ~CRaidTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;
	virtual void Stop(bool done);

	virtual void OnUnitIdle(CCircuitUnit* unit) override;
	virtual bool AllowRetreat(CCircuitUnit* unit) override;

	// apex: the script's priced raid target (nnraid.as). r <= 0 clears it.
	void SetGoal(const springai::AIFloat3& pos, float r) { goalPos = pos; goalR = r; goalRefused = false; refuseSince = -1; }
	bool IsGoalRefused() const { return goalRefused; }
	float GetGoalR() const { return goalR; }

private:
	bool IsCommitted() const;
	// apex_raid_side: the friendly army already in the fight at ePos (within reach of it), 0 when off or out of reach
	float FightSideAt(const springai::AIFloat3& ePos, const springai::AIFloat3& pos, float reach) const;
	bool FindTarget();
	void ApplyTargetPath(const CQueryPathMulti* query);
	void FallbackRaid();
	void ApplyRaidPath(const CQueryPathSingle* query);
	bool GiveUpRaid();
	// apex_stock_army (StockFight.inl)
	void StockUpdate();
	bool StockFindTarget();
	void StockApplyTargetPath(const CQueryPathMulti* query);
	void StockFallbackRaid();
	void StockApplyRaidPath(const CQueryPathSingle* query);

	float maxPower;
	int noTargetSince = -1;
	springai::AIFloat3 goalPos;
	float goalR = 0.f;
	int refuseSince = -1;      // apex: a committed air wing at its goal with nothing it would take, since
	bool goalRefused = false;
	int keptN = 0;          // retreats a committed raid did not take
	int blockedSince = -1;   // apex_gather: frame the bounded path to the goal first failed
	int nextCommitLog = 0;
	int nextAaPick = 0;      // a committed gunship wing re-aims at the nearest AA once a second
	int aaSetN = 0;          // AA set-targets issued (raid-commit log)
	mutable int commitAt = -1;   // IsCommitted is asked per damage event: once a frame
	int dropLogAt = -1;
	int lookLogAt = -1;
	static constexpr float RAID_SIDE_R = 2200.f;  // = CAttackTask::SIDE_R, the army beside us
	mutable bool commitVal = false;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_RAIDTASK_H_
