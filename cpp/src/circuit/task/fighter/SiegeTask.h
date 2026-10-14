/*
 * SiegeTask.h
 *
 * apex: a squad that exists for one enemy fortification (docs/24 "Siege a
 * fortification on purpose"). The goal lives in CFortCensus; the task ends
 * when the script clears it.
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_SIEGETASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_SIEGETASK_H_

#include "task/fighter/SquadTask.h"

#include <map>

namespace circuit {

class CQueryPathSingle;

class CSiegeTask: public ISquadTask {
public:
	CSiegeTask(ITaskModule* mgr);
	virtual ~CSiegeTask();

	virtual bool CanAssignTo(CCircuitUnit* unit) const override;
	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Start(CCircuitUnit* unit) override;
	virtual void Update() override;

	virtual void OnUnitIdle(CCircuitUnit* unit) override;

private:
	enum class Row: char {CARRY = 0, SCREEN, SUPPORT};
	Row RowOf(CCircuitUnit* unit, float reach) const;
	CEnemyInfo* PickTarget(const springai::AIFloat3& goal, float area, const springai::AIFloat3& from,
			float carryR, int& cls);
	bool FreeStand(const springai::AIFloat3& tPos, const springai::AIFloat3& from, float r,
			springai::AIFloat3& out) const;
	void Execute();
	void ApplyTravel(const CQueryPathSingle* query);
	void Order(CCircuitUnit* unit, const springai::AIFloat3& pos, CEnemyInfo* target, bool dark, int frame);

	struct SLast {
		springai::AIFloat3 pos;
		int targetId;
	};
	std::map<CCircuitUnit*, SLast> lastOrder;
	int targetCls = -1;
	int fromFrame = -1;
	int logAt = 0;
	int nCarry = 0, nScreen = 0, nSupport = 0, nFear = 0, nDark = 0, nSlid = 0, nCommit = 0, nGather = 0;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_SIEGETASK_H_
