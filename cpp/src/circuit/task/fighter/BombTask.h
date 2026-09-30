/*
 * BombTask.h
 *
 *  Created on: Jan 6, 2016
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_BOMBTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_BOMBTASK_H_

#include "task/fighter/SquadTask.h"
#include "unit/CoreUnit.h"

#include <map>
#include <vector>

namespace circuit {

class CCircuitDef;

class CBombTask: public ISquadTask {
public:
	CBombTask(ITaskModule* mgr, float powerMod);
	virtual ~CBombTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;

	virtual void OnUnitIdle(CCircuitUnit* unit) override;
	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;

private:
	void FindTarget();
	void ApplyTargetPath(const CQueryPathSingle* query);
	void FallbackBasePos();
	void ApplyBasePos(const CQueryPathSingle* query);
	void Fallback();
	void CheckCommit(const springai::AIFloat3& pos, const springai::AIFloat3& focusPos, float focusR);
	void AttackSpread(int frame);
	void IssueAims(int frame);
	void PlanSpread(int frame);

	struct SpreadCand {
		ICoreUnit::Id id;
		springai::AIFloat3 pos;
		float value, health;
		CCircuitDef* edef;
	};
	std::vector<SpreadCand> spreadCands;  // this tick's targets around the primary
	bool spreadable = false;
	std::map<ICoreUnit::Id, ICoreUnit::Id> aims;  // our bomber -> the enemy it drops on
	// The order each bomber is flying: a re-issued attack restarts its run.
	std::map<ICoreUnit::Id, std::pair<ICoreUnit::Id, int>> issued;
	int nRetarget = 0;

	// Past the point where going home costs more AA than reaching the cell.
	bool committed = false;
	bool spent = false;  // committed, and the cell has nothing left to bomb
	springai::AIFloat3 commitPos;
	float commitR = 0.f;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_BOMBTASK_H_
