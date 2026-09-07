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
	// Raid dispatch (CMilitaryManager::DispatchRaids): this pool answers the
	// enemy group at `groupPos`, stands at `aim` -- the building on the group's
	// course -- and engages once it holds the group's worth in power itself.
	void Dispatch(const springai::AIFloat3& groupPos, const springai::AIFloat3& aim,
			float infl, int untilFrame);
	bool IsDispatched(int frame) const { return frame < dispatchUntil; }
	const springai::AIFloat3& GetDispatchPos() const { return dispatchPos; }

	// apex: which hotspot this pool was last sent to. UpdateDefenceTasks re-picks
	// from scratch every 5s with no memory of the previous answer, so two spots of
	// near-equal score swap the lead on noise and the pool is dragged between them
	// (apexearth, watching: "our squad stands in neither of the desired places").
	// This is the memory that was missing -- first to MEASURE the flapping.
	int GetGuardSpot() const { return guardSpot; }
	void SetGuardSpot(int s) { guardSpot = s; }
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
	int guardSpot = -1;
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
	void FallbackHoldPos();
	// Each member walks to its own guard post (CMilitaryManager::GetGuardPost)
	// instead of the pool sharing one stand; false when nobody has one.
	bool FallbackPosts();
	// Size the answer to a target: members within their post's reach go,
	// nearest first, until their power beats the threat there with a margin;
	// the rest stay on or return to their posts.
	void LeashPosts(const springai::AIFloat3& tgtPos);
	int lastLeashLog = -999999;
	int lastAidLog = -999999;   // aid census: what allies are fighting that we did not elect
	float leashShort = 0.f;   // need - sent at the last leash, 0 when met
	int leashAt = -999999;
	int lastHoldLog = -999999;
	std::map<int, std::pair<springai::AIFloat3, int>> postSent;   // unit id -> post ordered, frame
	int lastPostLog = -999999;
	int dispatchUntil = 0;
	springai::AIFloat3 dispatchPos;
	float dispatchInfl = 0.f;
	int lastInterceptLog = 0;
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_DEFENDTASK_H_
