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

#include <map>
#include <memory>
#include <vector>

namespace circuit {

class CCircuitAI;
class CCircuitDef;
class CEnemyInfo;

class ISquadTask: public IFighterTask {
protected:
	ISquadTask(ITaskModule* mgr, FightType type, float powerMod);
public:
	virtual ~ISquadTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	// apex: the one way a squad folds into another; refused when either join window is closed
	bool Merge(ISquadTask* task);
protected:
	virtual void MergeFrom(ISquadTask* task);
public:
	virtual bool PurgeStrays() override;
	// apex: a ground member of a squad of two or more does not walk home alone
	virtual bool AllowRetreat(CCircuitUnit* unit) override;

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
	void StockAttack(const int frame, const bool isGround);  // StockFight.inl
	// one task update (1 s) plus the turn to walk away
	static constexpr float DGUN_REACT_S = 2.f;
	static float DGunKeepOut(const CCircuitAI* circuit, CCircuitDef* u, CCircuitDef* t, float& hold);
	bool IsInsideDGun(int frame);
	bool dgunNear = false;  // the last Attack() had a D-gun carrier to keep out of

	// apex_target_value: an enemy's worth in metal to this squad -- its cost, plus for a mobile
	// one the metal of ours it destroys while it lives (horizonS, longer when it outranges us)
	struct SFire { float dpsSurf = 0.f, dpsAir = 0.f, mph = 0.f, ownPow = 1.f, armedRange = 0.f; bool air = false; };
	SFire SquadFire() const;
	static float FireAt(const SFire& f, const CCircuitDef* edef);
	static float EnemyHp(CEnemyInfo* e);
	float TargetWorth(const SFire& f, CEnemyInfo* e, float horizonS) const;
	void AllocateFire(int frame, const springai::AIFloat3& tPos, bool apply);
	bool FireStale() const;
	void AssignFlierSlots(int frame);
	float flierSplash = 0.f;
	int flierSplashAt = -1;
	int flierLogAt = 0;
	std::map<int, int> fireAt;  // member -> the enemy its dose goes to
	int engTgt = -1;
	int allocFrame = -1;
public:
	static void NoteTargetKill(CCircuitAI* circuit, CCircuitDef* edef);
	static void NoteTargetPick(CCircuitAI* circuit, float pickM, float nearM);

	// apex_focus_fire: in contact, each member's fire goes to the enemy whose death removes the most of
	// their damage per second of ours, in lethal doses; what deals us no damage comes last
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	bool IsFocusFight() const;
	static void NoteFocusKill(CCircuitAI* circuit, CCircuitUnit* killer, CEnemyInfo* enemy);
protected:
	virtual void FocusScript(int frame) override;
	bool FocusTick(int frame, bool issue);
	bool FocusHold(int frame);
	bool FocusLive(int frame) const;
	std::map<int, int> focusAt;  // member -> enemy
	std::vector<int> focusOrder;
	int focusNext = -1;
	int focusSeen = -1;
	int focusEp = -1;
	int focusKillN = 0;
	bool focusArmedKilled = false;
	bool focusOn = false;
	bool focusOrdered = false;
protected:

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
