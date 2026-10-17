/*
 * FighterTask.h
 *
 *  Created on: Aug 31, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_

#include "task/UnitTask.h"
#include "util/Defines.h"

namespace circuit {

#define RANGE_MOD	0.8f

class CEnemyInfo;

class IFighterTask: public IUnitTask {
public:
	enum class FightType: char {RALLY = 0, GUARD, DEFEND, SCOUT, RAID, ATTACK, BOMB, MELEE, ARTY, AA, AH, SUPPORT, SUPER, SIEGE, _SIZE_};
	using FT = std::underlying_type<FightType>::type;

protected:
	IFighterTask(ITaskModule* mgr, FightType type, float powerMod, int timeout = 0);
public:
	virtual ~IFighterTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Update() override;

	virtual void OnUnitIdle(CCircuitUnit* unit) override;
	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	// apex: false keeps a damaged unit in the task where it would retreat; everything else still runs.
	virtual bool AllowRetreat(CCircuitUnit* unit) { return true; }
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	// apex: true when dropping members that are dead or tasked elsewhere left the task empty.
	virtual bool PurgeStrays() { return false; }

	FightType GetFightType() const { return fightType; }
	const springai::AIFloat3& GetPosition() const { return position; }

	float GetAttackPower() const { return attackPower; }
	CEnemyInfo* GetTarget() const { return target; }
	void ClearTarget() { target = nullptr; }  // Only for ~CEnemyUnit

	const std::set<CCircuitUnit*>& GetShields() const { return shields; }

	// apex: THE JOIN WINDOW (docs/doctrine.md): OPEN while the squad forms, COMMITTED from the moment it
	// launches until it is home again (JoinReopen). Under apex_gather a committed task takes only the roster
	// admitted at its commit, for admitFrames; everything else is refused at the join paths that ask JoinOpen.
	// ATTACK, RAID and BOMB tasks are launched by being made: they commit on their first update.
	virtual bool JoinOpen(const CCircuitUnit* unit) const override final;
	virtual void JoinTick() override final;
	bool IsJoinClosed() const;
	bool IsJoinCommitted() const { return joinCommitted; }
	int GetJoinCommitFrame() const { return joinCommitted ? joinCommitFrame : -1; }
	void JoinAdmit(int unitId) { if (!joinCommitted) { joinAdmit.insert(unitId); } }
	void JoinCommit(int admitFrames);
	void JoinReopen();
	void NoteJoinMerged(int n);

	// apex (comfight.as, apex_com_fight): the script's fight verdict for the group. Until `until` every member
	// walks (fight false) or fight-walks (fight true) to pos, and the task's own targeting and travel wait.
	void SetScriptMove(const springai::AIFloat3& pos, int until, bool fight);
	bool ScriptMoveActive() const;
	// ...and the defended point it decided not to take: targets inside the ring are not picked until `until`
	void SetKeepOut(const springai::AIFloat3& pos, float r, int until) { keepPos = pos; keepR = r; keepUntil = until; }
	bool InKeepOut(const springai::AIFloat3& p) const;

protected:
	bool ScriptMoveUpdate();
	// apex_focus_fire (ISquadTask): set targets during a fight-walk
	virtual void FocusScript(int frame) {}
	springai::AIFloat3 scriptPos;
	int scriptUntil = -1;
	int scriptIssued = -1;
	bool scriptFight = false;
	springai::AIFloat3 keepPos;
	float keepR = 0.f;
	int keepUntil = -1;

	void SetTarget(CEnemyInfo* enemy);
	void Attack(CCircuitUnit* unit, const int frame);

	FightType fightType;
	springai::AIFloat3 position;  // attack/scout position

	float attackPower;
	float powerMod;

	std::set<CCircuitUnit*> cowards;
	std::set<CCircuitUnit*> shields;

	static F3Vec urgentPositions;  // NOTE: micro-opt
	static F3Vec enemyPositions;  // NOTE: micro-opt

	int attackFrame;

private:
	bool JoinAdmitted(const CCircuitUnit* unit) const;
	bool joinCommitted = false;
	bool joinTicked = false;
	int joinAdmitUntil = -1;
	int joinCommitFrame = -1;
	std::set<int> joinAdmit;

private:  // NOTE: Never assign directly, use SetTarget() to avoid access to a dead target
	CEnemyInfo* target;

#ifdef DEBUG_VIS
public:
	virtual void Log() override;
#endif

	// KEPT ACROSS THE FIGHT REVERT (2026-09-08). The fight classes went back to
	// stock; these two did not, because code that is NOT being reverted still
	// calls them: RoamPos from AntiAirTask, AntiHeavyTask and ArtilleryTask,
	// FightTypeName from MilitaryManager and the stale-task crash log.
public:
	springai::AIFloat3 RoamPos(CCircuitUnit* unit) const;
	static const char* FightTypeName(int ft);
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_
