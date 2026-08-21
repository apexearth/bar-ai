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

	virtual bool IsDiveCommit() const override { return diveCommit; }

private:
	void FindTarget();
	void ApplyTargetPath(const CQueryPathSingle* query);
	void FallbackFrontPos();
	void ApplyFrontPos(const CQueryPathMulti* query);
	void FallbackBasePos();
	void ApplyBasePos(const CQueryPathSingle* query);
	void Fallback();

	float minPower;
	int lastDetourLog = -1000000;
	int lastEngageLog = -1000000;
	int lastWithdrawLog = -1000000;
	// apex: most power this task ever held; the failure break compares against it.
	float peakPower = 0.f;
	// The chosen target is fat economy on their ground: members waive retreat
	// while it holds (see IFighterTask::OnUnitDamaged).
	bool diveCommit = false;
	// -1 until rolled, then 0 = threat-aware route, 1 = straight in. Rolled once
	// per task so a squad does not change its mind about the route mid-walk.
	int chargeRoll = -1;
	// apex: flanking. Rolled once per task; a flanking squad walks via a
	// lateral waypoint before turning onto its target.
	int flankRoll = -1;

	// apex: pre-contact assembly budget. -1 = not assembling; otherwise the
	// frame past which the squad engages regardless of stragglers.
	int assembleUntil = -1;
	springai::AIFloat3 flankVia = springai::AIFloat3(-1.f, 0.f, 0.f);
	// Risk escalation, not a charge flip: each time the threat-aware route
	// comes back past apex_max_detour times the straight line, this steps up
	// one -- halving the per-tile threat cost and doubling the ceiling on the
	// next query -- until the route is acceptable or apex_max_risk is hit.
	// The path stays threat-aware at every level (apexearth: "wish we could
	// just choose to accept more risk in our path, not just turn all our
	// careful logic off"). Reset on a target change in FindTarget.
	int riskLevel = 0;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_
