/*
 * CircuitUnit.h
 *
 *  Created on: Sep 2, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_UNIT_CIRCUITUNIT_H_
#define SRC_CIRCUIT_UNIT_CIRCUITUNIT_H_

#include "unit/ally/AllyUnit.h"
#include "unit/CircuitDef.h"
#include "util/ActionList.h"
#include "util/Defines.h"

namespace springai {
	class Command;
	class Weapon;
}

namespace terrain {
	struct SArea;
}

namespace circuit {

#define TRY_UNIT(c, u, x)	try { x } catch (const std::exception& e) { c->Garbage(u, e.what()); }

#define UNIT_CMD_OPTION				0

#define CMD_ATTACK_GROUND			20
#define CMD_RETREAT_ZONE			10001
#define CMD_ORBIT					13923
#define CMD_ORBIT_DRAW				13924
#define CMD_CLOAK_SHIELD			31101
#define CMD_RAW_MOVE				31109
#define CMD_MORPH_UPGRADE_INTERNAL	31207
#define CMD_UPGRADE_STOP			31208
#define CMD_MORPH					31210
#define CMD_MORPH_STOP				32210
#define CMD_FIND_PAD				33411
#define CMD_PRIORITY				34220
#define CMD_MISC_PRIORITY			34221
#define CMD_RETREAT					34223
#define CMD_UNIT_SET_TARGET			34923
#define CMD_UNIT_CANCEL_TARGET		34924
#define CMD_ONECLICK_WEAPON			35000
#define CMD_WANT_CLOAK				37382
#define CMD_DONT_FIRE_AT_RADAR		38372
#define CMD_JUMP					38521
#define CMD_AIR_MANUALFIRE			38571
#define CMD_WANTED_SPEED			38825
#define CMD_AIR_STRAFE				39381
#define CMD_TERRAFORM_INTERNAL		39801

// FIXME: BA
#define CMD_AUTOMEX				31143
#define CMD_BAR_PRIORITY		34571
#define CMD_LAND_AT_AIRBASE		35430
// FIXME: BA

class CEnemyInfo;
class CWeaponDef;
class ITaskModule;
class CDGunAction;
class ITravelAction;

class CCircuitUnit: public CAllyUnit, public CActionList {
public:
	friend class CInitScript;

	enum class ETaskState: char {NONE = 0, ASSIGN, START, TRAVEL, EXECUTE, STOP};

	CCircuitUnit(const CCircuitUnit& that) = delete;
	CCircuitUnit& operator=(const CCircuitUnit&) = delete;
	CCircuitUnit(CCircuitAI* circuit, Id unitId, springai::Unit* unit, CCircuitDef* cdef);
	virtual ~CCircuitUnit();

	void SetTask(IUnitTask* task);
	void SetTaskFrame(int frame) { taskFrame = frame; }
	int GetTaskFrame() const { return taskFrame; }

	void SetManager(ITaskModule* mgr) { manager = mgr; }
	ITaskModule* GetManager() const { return manager; }

	void SetArea(terrain::SArea* area) { this->area = area; }
	terrain::SArea* GetArea() const { return area; }

	void ClearAct();
	// Shadows the inherited CActionList::Clear: the base deletes the actions
	// but cannot null this class's dgunAct/travelAct caches, leaving them
	// dangling at freed memory -- every later read is a UAF and StateWait()
	// through them was a heap-corrupting write. Through a CCircuitUnit*,
	// clearing MUST go through ClearAct.
	void Clear() { ClearAct(); }
	void PushDGunAct(CDGunAction* action);
	CDGunAction* GetDGunAct() const { return dgunAct; }
	void PushTravelAct(ITravelAction* action);
	ITravelAction* GetTravelAct() const { return travelAct; }

	void SetIsFinished() { isFinished = true; }
	bool IsFinished() const { return isFinished; }

	void SetAllowedToJump(bool value) { isAllowedToJump = value; }
	bool IsAllowedToJump() const { return isAllowedToJump; }

	bool IsMoveFailed(int frame);
	bool IsStuck() const { return isStuck; }
	void ClearStuck() { isStuck = false; moveFails = 0; }

	// A WAKE SAYS WHAT HAPPENED, NOT "RE-DECIDE EVERYTHING".
	//
	// ForceUpdate used to be one undifferentiated signal, so a unit taking a
	// single hit re-opened its whole squad's destination question -- 0.33s
	// later, per unit, OR'd across the squad. A squad in contact therefore
	// re-elected where to go several times a second and closed ~0% of the
	// distance to any of them (tools/goals.py, 2026-09-06). The damage
	// reaction itself never needed this: OnUnitDamaged does KeepRange, dodge,
	// counter-battery, coward-marking and the retreat vote inline, before the
	// task ever runs.
	//
	// So the waker declares the level and the consumer declares what it will
	// accept. REACT is "something hit us" -- per-unit business. RECONSIDER is
	// "the world changed shape" (a sudden threat appearing), the only kind of
	// news that should be allowed to move a squad's destination.
	enum class Wake : int { REACT = 0, RECONSIDER = 1 };
	void ForceUpdate(int frame, Wake w = Wake::REACT);
	bool IsForceUpdate(int frame, Wake want = Wake::REACT);

	void SetIsDead() { isDead = true; }
	bool IsDead() const { return isDead; }

	// The BLACK BOX: last actions before death, for the deaths.py forensics
	// (apexearth: "need to see the last ~N actions before a unit's death").
	void NoteAct(const char* tag, int frame) {
		actRing[actHead % 10] = std::to_string(frame / 30) + tag;
		++actHead;
	}
	std::string GetActTrace() const {
		std::string out;
		const int n = (actHead < 10) ? actHead : 10;
		for (int i = actHead - n; i < actHead; ++i) {
			if (!out.empty()) out += ">";
			out += actRing[i % 10];
		}
		return out;
	}
	// apex: ORDER CENSUS. Every engine order this AI sends leaves through one of
	// the Cmd* below, and every one of them costs the ENGINE a command insert, a
	// Lua AllowCommand pass and (for a move whose goal actually changed) a fresh
	// path request -- cost that is billed to the engine, not to our own frame
	// time. NoteOrder records what was last sent to this unit so a re-send of
	// the same thing can be counted, and returns true when the re-send is a
	// provable no-op AND apex_order_dedupe is on; CmdMoveTo then drops it.
	enum class OrdKind: int { MOVE = 0, FIGHT, PATROL, ATTACK, TARGET, _SIZE };
	// WHICH CALL SITE sent it. The kind/distance census says how much churn
	// there is, never where it comes from, so every rule aimed at it has been
	// a guess. Defaulted, so an unlabelled site lands in OTHER rather than
	// being mis-attributed -- every site is now named, so a nonzero `other` in
	// the order-src line means a NEW one was added without a tag.
	enum class OrdSrc: int { OTHER = 0, RING, TRAVEL, DODGE, STANDOFF, POST,
		RETREAT, BUILD, SCOUT, SETTGT, ATTACK, PATROL, ENGAGE, REGROUP, ESCORT,
		SNIPER, MANUAL, SCRIPT, FWALK, COMBAT, GUARD, RALLY, _SIZE };
	bool NoteOrder(OrdKind kind, short options, const springai::AIFloat3& pos, int id, int timeout,
			OrdSrc src = OrdSrc::OTHER);
	// One source of truth for the call-site names: the order census in
	// CircuitAI and the per-unit trace in NoteOrder both read it, so a new
	// OrdSrc cannot be named in one place and left numeric in the other.
	static const char* OrdSrcName(int src);
	// ORDER ARBITRATION. Sixteen call sites move units and the last writer won,
	// so a threat-aware path from one was overwritten seconds later by a centre
	// that decided under different assumptions -- measured 2026-09-06, one
	// armham took 322 orders in 14 minutes from 9 sources, 30% of them replacing
	// the previous order with a point 128+ elmos away inside 3s.
	// apexearth's ranking: "retreat > dodge > standoff > guard".
	static int OrdSrcPrio(int src);
	const springai::AIFloat3& GetTravelGoal() const { return travelGoal; }
	int GetTravelGoalFrame() const { return travelGoalFrame; }
	// DO UNITS ACTUALLY GET CLOSER TO WHERE WE SEND THEM? apexearth: "we keep
	// trying to move a unit between two fronts... they never get to either and
	// hover in between". Every other measure here asks which order was sent;
	// this asks whether the unit ever arrived. distStart is the gap when the
	// goal was set, distMin the closest it ever came.
	// Only restart the measurement when the destination actually MOVES. The
	// median goal-jump is 0 -- most calls re-set the SAME place while the unit
	// is still walking to it -- so resetting on every call zeroed the progress
	// counter and made every task read 'closed 0%'.
	void SetTravelGoal(const springai::AIFloat3& p, int frame) {
		// travelGoal starts at -RgtVector, so a negative x means 'none yet'.
		const bool moved = (travelGoal.x < 0.f) || (travelGoal.distance2D(p) > 128.f);
		if (moved || (goalDistStart < 0.f)) {
			goalDistStart = -1.f; goalDistMin = -1.f;
			travelGoalFrame = frame;
		}
		travelGoal = p;
	}
	float GetGoalDistStart() const { return goalDistStart; }
	float GetGoalDistMin() const { return goalDistMin; }
	void NoteGoalDist(float d) {
		if (goalDistStart < 0.f) { goalDistStart = d; }
		if ((goalDistMin < 0.f) || (d < goalDistMin)) { goalDistMin = d; }
	}

	void SetDamagedFrame(int frame) { damagedFrame = frame; }
	int GetDamagedFrame() const { return damagedFrame; }
	void SetDamagedWeapon(int weaponDefId) { damagedWeapon = weaponDefId; }
	int GetDamagedWeapon() const { return damagedWeapon; }
	void SetDamagedDir(const springai::AIFloat3& dir) { damagedDir = dir; }
	const springai::AIFloat3& GetDamagedDir() const { return damagedDir; }
	void SetDodgeFrame(int frame) { dodgeFrame = frame; }
	int GetDodgeFrame() const { return dodgeFrame; }
	// apex: last frame this unit's builder task ran the script re-election
	// (IBuilderTask::Reevaluate) -- the throttle that keeps a walking
	// builder from re-running the whole market every task update.
	void SetElectFrame(int frame) { electFrame = frame; }
	int GetElectFrame() const { return electFrame; }

	bool HasDGun() const { return dgun != nullptr; }
	bool HasWeapon() const { return weapon != nullptr; }
	bool HasShield() const { return shield != nullptr; }
	void ManualFire(CEnemyInfo* target, int timeout);
	bool IsDGunHigh() const;
	bool IsDisarmed(int frame);
	bool IsWeaponReady(int frame);
	bool IsDGunReady(int frame, float energy);
	float GetDGunCostE() const;
	int GetDGunReloadFrame() const;
	// apex: the script's commander decision says whether a D-gun may walk him
	// in on a target beyond range; a withdrawing commander must not walk back.
	void SetDGunClose(bool v) { dgunMayClose = v; }
	bool IsDGunCloseOk() const { return dgunMayClose; }
	int GetDGunOrders() const { return dgunOrders; }
	// A D-gun order stands until the shot is fired or its window passes: any
	// other order in that window would replace it in the engine's queue (measured:
	// every manual-fire order was followed by a move and a stop in the same
	// frame, and no shot ever landed).
	// NOT const: a held frame is an order the engine never got, and the black
	// box has to say so -- a silent drop is invisible in every other log.
	bool IsDGunHeld(int frame);
	bool IsShieldCharged(float percent);
	bool IsJumpReady();
	bool IsJumping();
	bool IsInvisible();
	float GetDamage();
	float GetShieldPower();
	float GetBuildSpeed();
	float GetWorkerTime();
	float GetDGunRange();
	float GetHealthPercent();

	void CmdRemove(std::vector<float>&& params, short options = 0);
	void CmdMoveTo(const springai::AIFloat3& pos, short options = 0, int timeout = INT_MAX,
			OrdSrc src = OrdSrc::OTHER);
	void CmdRepeat(bool repeat, short options = 0, int timeout = INT_MAX);
	void CmdJumpTo(const springai::AIFloat3& pos, short options = 0, int timeout = INT_MAX);
	void CmdFightTo(const springai::AIFloat3& pos, short options = 0, int timeout = INT_MAX,
			OrdSrc src = OrdSrc::OTHER);
	void CmdPatrolTo(const springai::AIFloat3& pos, short options = 0, int timeout = INT_MAX);
	void CmdAttackGround(const springai::AIFloat3& pos, short options = 0, int timeout = INT_MAX);
	void CmdWantedSpeed(float speed = NO_SPEED_LIMIT);
	void CmdStop(short options = 0, int timeout = INT_MAX);
	void CmdSetTarget(CEnemyInfo* enemy);
	// The one engine attack order; callers set the target themselves. A sniper
	// gets a move to SniperHoldPos instead.
	void CmdAttack(CEnemyInfo* enemy, short options = 0, int timeout = INT_MAX);
	// Where a sniper stands to fire on tPos: its own surface range back along
	// its current bearing, so a fight/attack order can be replaced by a move.
	springai::AIFloat3 SniperHoldPos(const springai::AIFloat3& tPos);
	void NoteSniperOrder(CCircuitDef::SniperOrder kind) const;
	void CmdCloak(bool state);
	void CmdFireAtRadar(bool state);
	void CmdFindPad(int timeout = INT_MAX);
	void CmdManualFire(short options = 0, int timeout = INT_MAX);
	void CmdAirManualFire(const springai::AIFloat3& pos, short options = 0, int timeout = INT_MAX);
	void CmdPriority(float value);
	void CmdMiscPriority(float value);
	void CmdAirStrafe(float value);
	void CmdBARPriority(float value);
	void CmdTerraform(std::vector<float>&& params);
	void CmdSelfD(bool state);
	bool IsInSelfD() const { return isSelfD; }
	void CmdWait(bool state);
	void RemoveWait();
	bool IsWaiting() const;
	void CmdRepair(CAllyUnit* target, short options = 0, int timeout = INT_MAX);
	void CmdBuild(CCircuitDef* buildDef, const springai::AIFloat3& buildPos, int facing, short options = 0, int timeout = INT_MAX);
	void CmdReclaimEnemy(CEnemyInfo* enemy, short options = 0, int timeout = INT_MAX);
	void CmdReclaimUnit(CAllyUnit* toReclaim, short options = 0, int timeout = INT_MAX);
	void CmdReclaimInArea(const springai::AIFloat3& pos, float radius, short options = 0, int timeout = INT_MAX);
	void CmdResurrectInArea(const springai::AIFloat3& pos, float radius, short options = 0, int timeout = INT_MAX);
	void CmdSetFireState(CCircuitDef::FireT state);
	void TrySetFireState(CCircuitDef::FireT state);  // safe CmdSetFireState
	void CmdSetMoveState(CCircuitDef::MoveT state);
	void TrySetMoveState(CCircuitDef::MoveT state);  // safe CmdSetMoveState

	void Attack(CEnemyInfo* enemy, bool isGround, int timeout);
	void Attack(const springai::AIFloat3& position, CEnemyInfo* enemy, bool isGround, bool isStatic, int timeout);
	void Attack(const springai::AIFloat3& position, CEnemyInfo* enemy, int tile, bool isGround, bool isStatic, int timeout);
	void Guard(CCircuitUnit* target, int timeout);
	void Gather(const springai::AIFloat3& groupPos, int timeout);

	// A UNIT'S PLACE IN ITS SQUAD -- a property of the unit, not of one action.
	//
	// It used to live on ITravelAction, where only CMoveAction's mid-path
	// waypoints ever read it. Every other way a squad is told where to go
	// handed EVERY member the identical point: CFightAction's waypoints, both
	// travel actions' arrival waypoint, CCircuitUnit::Gather, and the merge
	// muster. Five leaks, and the squad balled up precisely on arrival and on
	// regroup -- the moments the formation is worth having. apexearth, twice:
	// "a squad should never have all of its units move to a single point".
	//
	// Held here and applied in the two command funnels below, so a call site
	// cannot forget it -- there is no call site to forget.
	void SetFormSlot(float lat, const springai::AIFloat3& dir) { formLateral = lat; formDir = dir; }
	void SetFormDir(const springai::AIFloat3& dir) { formDir = dir; }
	void ClearFormSlot() { formLateral = 0.f; formDir = -RgtVector; }
	float GetFormLateral() const { return formLateral; }
	springai::AIFloat3 InFormation(const springai::AIFloat3& p, OrdSrc src) const;

	void Morph();
	void StopMorph();
	bool IsUpgradable();
	void Upgrade();
	void StopUpgrade();
	bool IsMorphing() const { return isMorphing; }

	void SetTaskState(ETaskState value) { taskState = value; }
	ETaskState GetTaskState() const { return taskState; }

	Id GetUnitIdReclaim() const;

	void ClearTarget() { target = nullptr; }
	CEnemyInfo* GetTarget() const { return target; }
	// apex: what we last set-targeted, by id -- census only, see CCircuitAI::tgtHeld.
	Id GetTgtHeldId() const { return tgtHeldId; }
	void SetTgtHeldId(Id id) { tgtHeldId = id; }
	int GetTargetTile() const { return targetTile; }

	void AddAttribute(CCircuitDef::AttrType type) { attr |= CCircuitDef::GetMask(static_cast<CCircuitDef::AttrT>(type)); }
	void DelAttribute(CCircuitDef::AttrType type) { attr &= ~CCircuitDef::GetMask(static_cast<CCircuitDef::AttrT>(type)); }
	void TglAttribute(CCircuitDef::AttrType type) { attr ^= CCircuitDef::GetMask(static_cast<CCircuitDef::AttrT>(type)); }
	bool IsAttrAny(CCircuitDef::AttrM value) const { return (attr & value) != 0; }
	bool IsAttrSolo()     const { return attr & CCircuitDef::AttrMask::SOLO; }
	bool IsAttrBase()     const { return attr & CCircuitDef::AttrMask::BASE; }
	bool IsAttrNoRepair() const { return attr & CCircuitDef::AttrMask::NO_REPAIR; }

private:
	// NOTE: taskFrame assigned on task change and OnUnitIdle to workaround idle spam.
	//       Proper fix: do not issue any commands OnUnitIdle, delay them until next frame?
	int taskFrame;
	// The live movement intent: whose decision the unit is carrying out, and
	// when it was taken. A lower-ranked centre may not overwrite it while it is
	// still running (apex_intent_hold).
	int intentFrame = 0;
	int intentPrio = -1;
	// apex: the unit's actual GOAL, not the waypoint it is walking to. Kept on
	// the UNIT rather than the travel action so it survives a task change --
	// being handed to a new task IS the redirection we want to measure.
	springai::AIFloat3 travelGoal = -RgtVector;
	int travelGoalFrame = 0;
	float goalDistStart = -1.f;
	float goalDistMin = -1.f;
	ETaskState taskState;
	ITaskModule* manager;
	terrain::SArea* area;  // = nullptr if a unit flies

	CDGunAction* dgunAct;
	ITravelAction* travelAct;

	int moveFails;
	int failFrame;
	std::string actRing[10];
	int actHead = 0;
	// apex: the last order of each kind sent to this unit. See NoteOrder.
	struct SOrdShadow {
		float x = -1e9f;
		float z = -1e9f;
		int id = -1;
		int frame = -1000000;  // when it was sent
		int timeout = 0;       // the frame the engine drops it
		unsigned seq = 0;      // ordSeq when it was sent
		short opts = 0;
	};
	SOrdShadow ordLast[static_cast<int>(OrdKind::_SIZE)];
	unsigned ordSeq = 0;  // orders of any kind sent to this unit
	int damagedFrame;
	int damagedWeapon = -1;
	int electFrame;
	springai::AIFloat3 damagedDir;
	int dodgeFrame;
	int execFrame;  // TODO: Replace by CExecuteAction?
	Wake execWake = Wake::REACT;  // what the pending wake is FOR
	float formLateral = 0.f;      // signed slot offset across the squad's front
	springai::AIFloat3 formDir = -RgtVector;  // the squad's direction of travel
	int disarmFrame;
	int ammoFrame;

	float priority;

	// ---- Bit fields ---- BEGIN
	bool isDead : 1;
	bool isStuck : 1;
	bool isFinished : 1;
	bool isDisarmed : 1;
	bool isWeaponReady : 1;
	bool isMorphing : 1;
	bool isSelfD : 1;
	bool isAllowedToJump : 1;
	// ---- Bit fields ---- END

	springai::Command* command;  // current top command
	CWeaponDef* dgunDef;
	springai::Weapon* dgun;
	int dgunHoldUntil = 0;
	int dgunHoldReload = 0;
	int dgunHoldNoteAt = -1;
	int dgunOrders = 0;
	bool dgunMayClose = true;
	springai::Weapon* weapon;  // main weapon
	springai::Weapon* shield;

	CEnemyInfo* target;
	Id tgtHeldId = -1;
	int targetTile;

	CCircuitDef::AttrM attr;

#ifdef DEBUG_VIS
public:
	void Log();
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_CIRCUITUNIT_H_
