/*
 * AttackTask.h
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_

#include "task/fighter/SquadTask.h"

namespace circuit {

class CAttackTask: public ISquadTask {
public:
	CAttackTask(ITaskModule* mgr, float minPower, float powerMod);
	virtual ~CAttackTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;

	virtual void OnUnitIdle(CCircuitUnit* unit) override;

	bool IsAtStage() const { return atStage; }  // apex: standing at the team push's gather point

private:
	bool atStage = false;
	void FindTarget();
	void ApplyTargetPath(const CQueryPathSingle* query);
	bool MarchEnemyBox();
	void FallbackFrontPos();
	void ApplyFrontPos(const CQueryPathMulti* query);
	void FallbackBasePos();
	void ApplyBasePos(const CQueryPathSingle* query);
	void Fallback();
	void RepairBreak(int frame);

	float minPower;
	// apex: the building we are hitting and how its health has moved
	int stallId = -1;
	float stallHp = 0.f;
	int stallSince = 0;
	int repairerId = -1;
	// apex: set off for their buildings; small armies on the way are shot, not chased
	bool forEco = false;
	int nextStrongLog = 0;
	int nextNearLog = 0;
	int nextDropLog = 0;
	int nextFrontLog = 0;
	int nextStageLog = 0;
	// every group in sight was refused as too strong: we are outgunned, not blind
	bool outgunned = false;
	// an outgunned fall-back in progress: kept until arrival or a hit
	bool fallBackActive = false;
	// the group that last outgunned the squad beside it, while still stronger
	bool strongMem = false;
	springai::AIFloat3 strongPos;
	springai::AIFloat3 fallBackTo;
	int joinRefused = -1;   // the enemy id of a fight the join decision refused (a pointer is reused)
	int joinRefusedUntil = 0;
	bool joinHeld = false;   // this update's target was refused: hold, don't march on their box
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_
