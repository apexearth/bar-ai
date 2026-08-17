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

class CCircuitAI;

// Fraction of a unit's OWN GetMaxRange() it stands off at. One name for both
// standoff sites -- IFighterTask::Attack and ISquadTask::Attack -- so a
// per-unit fraction cannot drift between them again. Runtime: apex_range_mod.
// apexearth: "we should aim to be at around 90% of our maximum attack range.
// We should not move any closer." 0.95 put units close enough to the edge
// that the enemy's own return fire (same range, or closing slightly) reached
// them; 0.9 leaves the margin he asked for.
#define STANDOFF_RANGE_MOD	0.90f

// A row's standoff/safe-angle caution scales with how fragile its OWN def is
// relative to the average health of whatever else is fighting alongside it
// in the same squad -- self-normalizing per engagement, not a per-unit-type
// special case. FRAGILE_STANDOFF_SCALE is the extra standoff fraction added
// at the fragility cap; FRAGILE_CAP bounds how far one glass-cannon def
// can push it. Runtime: apex_fragile_standoff_scale, apex_fragile_cap.
// Default 0: the pushback scattered the fight shape -- A/B 2026-08-16
// (fight-control vs fight-fragile0, 12 games each) measured army K/D 0.333
// with it on against 0.499 off. Rows still stand at their own weapon range,
// which is what keeps long guns behind the tanks.
#define FRAGILE_STANDOFF_SCALE	0.f
#define FRAGILE_CAP	2.0f

class CEnemyInfo;

class IFighterTask: public IUnitTask {
public:
	enum class FightType: char {RALLY = 0, GUARD, DEFEND, SCOUT, RAID, ATTACK, BOMB, MELEE, ARTY, AA, AH, SUPPORT, SUPER, _SIZE_};
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
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;

	FightType GetFightType() const { return fightType; }
	// Name for a FightType ordinal. Bounds-checked, so it is safe to call on
	// a value recovered from the task registry rather than from an object.
	static const char* FightTypeName(int ft);
	const springai::AIFloat3& GetPosition() const { return position; }

	float GetAttackPower() const { return attackPower; }
	CEnemyInfo* GetTarget() const { return target; }
	void ClearTarget() { target = nullptr; }  // Only for ~CEnemyUnit

	const std::set<CCircuitUnit*>& GetShields() const { return shields; }
	// Coward state must survive merges and DEFEND->ATTACK promotion, both of
	// which move units onto a different task instance -- without this the
	// rear-standoff resets on every merge boundary.
	void MarkCoward(CCircuitUnit* unit) { cowards.insert(unit); }
	bool IsCoward(CCircuitUnit* unit) const { return cowards.count(unit) > 0; }

	// A wounded squad member asks its SQUAD before retreating alone. Returns
	// true when the whole squad disengaged together (the asker included);
	// base tasks have no squad and always answer false.
	virtual bool TrySquadRetreat(CCircuitUnit* unit) { return false; }

	// True while the task's chosen target is a fat-economy dive (AttackTask):
	// members waive the retreat flip for its duration.
	virtual bool IsDiveCommit() const { return false; }

	// Retreat-source telemetry (implemented in FighterTask.cpp; SquadTask's
	// branches report through these).
	static void NoteSquadStand(CCircuitAI* c);
	static void NoteSquadVote(CCircuitAI* c);
	static void NoteHomeStand(CCircuitAI* c);

protected:
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

private:  // NOTE: Never assign directly, use SetTarget() to avoid access to a dead target
	CEnemyInfo* target;

#ifdef DEBUG_VIS
public:
	virtual void Log() override;
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_
