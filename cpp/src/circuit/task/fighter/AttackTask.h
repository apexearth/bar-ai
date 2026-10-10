/*
 * AttackTask.h
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_

#include "task/fighter/SquadTask.h"

#include <vector>

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
	// apex: the bearing (unit vector from `at`) this squad will hit `at` from
	bool GetArrivalDir(const springai::AIFloat3& at, int key, int frame, springai::AIFloat3& dir) const;

private:
	bool atStage = false;
	struct SFoePt { springai::AIFloat3 pos; float reach; float power; };
	void ChooseFlank(const springai::AIFloat3& tgtPos, int key, int tgtGroup, const std::vector<SFoePt>& foes,
			const springai::AIFloat3& sideSum, const char* tgtName);
	bool FlankStep(const springai::AIFloat3& tgtPos, int key, int frame, springai::AIFloat3& via);
	springai::AIFloat3 SideArrivals(const springai::AIFloat3& at, int key, float nearR) const;
	void FindTarget();
	void ApplyTargetPath(const CQueryPathSingle* query, bool viaPath = false);
	bool MarchEnemyBox();
	springai::AIFloat3 EnemyBoxPos() const;
	void HoldForward(int frame);
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
	// a group stronger than our side there can reach us: hold, don't march
	bool outgunned = false;
	// an outgunned fall-back in progress: kept until arrival or a hit
	bool fallBackActive = false;
	// the group that last outgunned the squad beside it, while still stronger
	bool strongMem = false;
	springai::AIFloat3 strongPos;
	float strongR = 0.f;
	springai::AIFloat3 fallBackTo;
	// the target is kept until commitUntil unless gone, too strong or unreachable
	int commitUntil = 0;
	int targetSince = 0;
	int heldCount = 0;
	// a refused squad waiting forward, and the order last given for it
	bool holding = false;
	bool holdWas = false;
	springai::AIFloat3 holdPos;
	int holdFrame = 0;
	int holdN = 0;
	int joinRefused = -1;   // the enemy id of a fight the join decision refused (a pointer is reused)
	int joinRefusedUntil = 0;
	bool joinHeld = false;   // this update's target was refused: hold, don't march on their box
	// apex: the side approach -- walk to a turn-in point off the direct line, then in
	springai::AIFloat3 flankDir;  // unit vector from the target to the turn-in point
	float flankR = 0.f;
	float flankOff = 0.f;  // degrees off the direct bearing
	int flankKey = -1;     // the target's id, or FLANK_BOX for their start box
	int flankUntil = 0;
	bool flankDone = true;
	static constexpr int FLANK_BOX = -2;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_ATTACKTASK_H_
