/*
 * CircuitUnit.cpp
 *
 *  Created on: Sep 2, 2014
 *      Author: rlcevg
 */

#include "unit/CircuitUnit.h"
#include "task/UnitTask.h"  // full type for the counted task reference
#include "unit/action/DGunAction.h"
#include "unit/action/TravelAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "module/TaskModule.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"  // Only for CorrectPosition
#include "CircuitAI.h"
#include "util/Utils.h"
#include "Log.h"  // complete springai::Log for the LOG macro (REFTRAP diagnostic)
#ifdef DEBUG_VIS
#include "task/UnitTask.h"
#endif

#include "AISCommands.h"
#include "Sim/Units/CommandAI/Command.h"
#include "WrappCurrentCommand.h"
#include "Weapon.h"
#include "WrappWeaponMount.h"

namespace circuit {

using namespace springai;

CCircuitUnit::CCircuitUnit(CCircuitAI* circuit, Id unitId, Unit* unit, CCircuitDef* cdef)
		: CAllyUnit(unitId, unit, cdef)
		, taskFrame(-1)
		, taskState(ETaskState::NONE)
		, manager(nullptr)
		, area(nullptr)
		, dgunAct(nullptr)
		, travelAct(nullptr)
		, moveFails(0)
		, failFrame(-1)
		, damagedFrame(-1)
		, electFrame(-1)
		, damagedDir(ZeroVector)
		, dodgeFrame(-1)
		, execFrame(-1)
		, disarmFrame(-1)
		, ammoFrame(-1)
		, priority(-1.f)
		, isDead(false)
		, isStuck(false)
		, isFinished(false)
		, isDisarmed(false)
		, isWeaponReady(true)
		, isMorphing(false)
		, isSelfD(false)
		, isAllowedToJump(false)
		, dgunDef(nullptr)
		, dgun(nullptr)
		, target(nullptr)
		, targetTile(-1)
		, attr(cdef->GetAttributes())
{
	command = springai::WrappCurrentCommand::GetInstance(unit->GetSkirmishAIId(), id, 0);

	WeaponMount* wpMnt;
	if (!circuitDef->IsAttrNoDGun()) {
//		if (cdef->IsRoleComm()) {
//			for (int num = 1; num < 3; ++num) {
//				std::string str = utils::int_to_string(num, "comm_weapon_manual_%i");
//				if (unit->GetRulesParamFloat(str.c_str(), -1) <= 0.f) {
//					continue;
//				}
//				str = utils::int_to_string(num, "comm_weapon_num_%i");
//				int mntId = CWeaponDef::WeaponIdFromLua(int(unit->GetRulesParamFloat(str.c_str(), -1)));
//				if (mntId < 0) {
//					continue;
//				}
//				wpMnt = WrappWeaponMount::GetInstance(unit->GetSkirmishAIId(), cdef->GetId(), mntId);
//				if (wpMnt == nullptr) {
//					continue;
//				}
//				dgun = unit->GetWeapon(wpMnt);
//				WeaponDef* wd = dgun->GetDef();
//				dgunDef = circuit->GetWeaponDef(wd->GetWeaponDefId());
//				delete wd;
//				delete wpMnt;
//				break;
//			}
//		} else {
			wpMnt = cdef->GetDGunMount();
			dgun = (wpMnt == nullptr) ? nullptr : unit->GetWeapon(wpMnt);
			dgunDef = cdef->GetDGunDef();
//		}
	}
	wpMnt = cdef->GetWeaponMount();
	weapon = (wpMnt == nullptr) ? nullptr : unit->GetWeapon(wpMnt);
	wpMnt = cdef->GetShieldMount();
	shield = (wpMnt == nullptr) ? nullptr : unit->GetWeapon(wpMnt);
}

CCircuitUnit::~CCircuitUnit()
{
	if (task != nullptr) {
		task->Release();  // the counted reference SetTask holds
	}
	delete command;
	delete dgun;
	delete weapon;
	delete shield;
}

void CCircuitUnit::SetTask(IUnitTask* task)
{
	// The unit's task pointer holds a COUNTED reference: engine events
	// (UnitMoveFailed, UnitIdle, UnitDamaged) read unit->GetTask() at
	// arbitrary times, and a task freed by a script-side Release while a unit
	// still pointed at it crashed live at 63 game-minutes (2026-08-15, AV in
	// UnitMoveFailed -> GetTask()->GetType()). Same cure as buildTasks
	// membership: a pointer somebody may dereference owns a reference.
	if (this->task != task) {
		if (task != nullptr) {
			task->AddRef();
		}
		// CRASH DIAGNOSTIC (temporary): a nil/idle/player singleton about to
		// be released with no other holder means THIS release is the refcount
		// imbalance -- dump full context before the RefCounter trap fires.
		if ((this->task != nullptr) && this->task->IsPermanent() && (this->task->GetRefCount() <= IRefCounter::kCushion + 1)) {
			CCircuitAI* c = (manager != nullptr) ? manager->GetCircuit() : nullptr;
			if (c != nullptr) {
				c->LOG("apex REFTRAP: unit=%d def=%d oldType=%d oldMgr=%p newType=%d newMgr=%p unitMgr=%p refs=%d",
						(int)GetId(), (int)circuitDef->GetId(),
						(int)this->task->GetType(), (void*)this->task->GetManager(),
						(task != nullptr) ? (int)task->GetType() : -1,
						(task != nullptr) ? (void*)task->GetManager() : nullptr,
						(void*)manager, this->task->GetRefCount());
			}
		}
		if (this->task != nullptr) {
			// DEFERRED: dropping the old task's reference here can be the LAST
			// one (a dead task kept alive only by this unit), and Release()
			// would delete it while ITS OWN RemoveAssignee/Stop is still on
			// the stack -- symbolized live twice (AssignTask path, then the
			// OnUnitDestroyed path). The release runs at the next safe point.
			if (manager != nullptr) {
				manager->GetCircuit()->DeferRelease(this->task);
			} else {
				this->task->Release();
			}
		}
		this->task = task;
	}
	SetTaskFrame(manager->GetCircuit()->GetLastFrame());
	taskState = ETaskState::NONE;
}

void CCircuitUnit::ClearAct()
{
	CActionList::Clear();
	dgunAct = nullptr;
	travelAct = nullptr;
}

void CCircuitUnit::PushDGunAct(CDGunAction* action)
{
	PushBack(action);
	dgunAct = action;
}

void CCircuitUnit::PushTravelAct(ITravelAction* action)
{
	PushBack(action);
	travelAct = action;
}

bool CCircuitUnit::IsMoveFailed(int frame)
{
	if (frame - failFrame >= FRAMES_PER_SEC * 3) {
		moveFails = 0;
	}
	failFrame = frame;
	isStuck = ++moveFails > TASK_RETRIES * 2;
	return isStuck;
}

static unsigned sWakeArm = 0, sWakeReact = 0, sWakeRecon = 0;
static unsigned sWakeAsks = 0, sWakeRefused = 0;
static int sWakeLogAt = 0;

void CCircuitUnit::ForceUpdate(int frame, Wake w)
{
	++sWakeArm;
	if (w == Wake::RECONSIDER) { ++sWakeRecon; } else { ++sWakeReact; }
	if (execFrame < 0) {
		execFrame = frame;
		execWake = w;
	} else if (int(w) > int(execWake)) {
		execWake = w;  // a pending wake only ever gets more urgent
	}
}

bool CCircuitUnit::IsForceUpdate(int frame, Wake want)
{
	if ((execFrame > 0) && (execFrame <= frame)) {
		const Wake w = execWake;
		execFrame = -1;  // consumed either way; an unaccepted wake must not linger
		++sWakeAsks;
		const bool accept = (int(w) >= int(want))
				|| (manager->GetCircuit()->GetTunable("apex_wake_split", 1.f) <= 0.f);
		if (!accept) {
			++sWakeRefused;
		}
		// Unconditional census: "refused=0" only means something next to the
		// number of times anyone asked.
		if (frame >= sWakeLogAt) {
			sWakeLogAt = frame + FRAMES_PER_SEC * 60;
			manager->GetCircuit()->LOG("apex: wake armed=%u react=%u recon=%u asks=%u refused=%u",
					sWakeArm, sWakeReact, sWakeRecon, sWakeAsks, sWakeRefused);
		}
		return accept;
	}
	return false;
}

void CCircuitUnit::ManualFire(CEnemyInfo* target, int timeout)
{
	if (circuitDef->HasDGun() && (dgun != nullptr)) {
		dgunHoldUntil = timeout;
		dgunHoldReload = dgun->GetReloadFrame();
		++dgunOrders;
	}
	NoteAct("dgn", (manager != nullptr) ? manager->GetCircuit()->GetLastFrame() : timeout);
	TRY_UNIT(manager->GetCircuit(), this,
		if (circuitDef->HasDGun()) {
			if (target->GetUnit()->IsCloaked()) {  // los-cheat related
				unit->DGunPosition(target->GetPos(), UNIT_COMMAND_OPTION_ALT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY, timeout);
			} else {
				unit->DGun(target->GetUnit(), UNIT_COMMAND_OPTION_ALT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY, timeout);
			}
		} else {
			if (circuitDef->IsPlane()) {
				CmdAirManualFire(target->GetPos(), 0, timeout);
			} else {
				AIFloat3 leadPos = target->GetPos() + target->GetVel() * FRAMES_PER_SEC * 2;
				CTerrainManager::CorrectPosition(leadPos);
				CmdMoveTo(leadPos, UNIT_COMMAND_OPTION_ALT_KEY, timeout, OrdSrc::MANUAL);
				CmdManualFire(UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);  // Krow
			}
		}
	)
}

bool CCircuitUnit::IsDGunHigh() const
{
	return dgunDef->IsHighTrajectory();
}

bool CCircuitUnit::IsDisarmed(int frame)
{
	if (disarmFrame != frame) {
		disarmFrame = frame;
		isDisarmed = unit->GetRulesParamFloat("disarmed", 0) > 0.f;
	}
	return isDisarmed;
}

bool CCircuitUnit::IsWeaponReady(int frame)
{
	if (ammoFrame != frame) {
		ammoFrame = frame;
		if (circuitDef->IsPlane()) {
			isWeaponReady = unit->GetRulesParamFloat("noammo", 0) < 1.f;
		} else {
			isWeaponReady = (weapon == nullptr) ? false : weapon->GetReloadFrame() <= frame;
		}
	}
	return isWeaponReady;
}

bool CCircuitUnit::IsDGunHeld(int frame)
{
	if ((frame >= dgunHoldUntil) || (dgun == nullptr)) {
		return false;
	}
	// The shot went off: the reload frame moved on.
	if (dgun->GetReloadFrame() > dgunHoldReload) {
		return false;
	}
	// apex: every Cmd* consults this as an early-return guard, so a true here
	// is an order the engine never got and nothing ever retries. One mark a
	// second -- the ring holds ten, and a flood erases the trace it is for.
	if (frame - dgunHoldNoteAt >= FRAMES_PER_SEC) {
		dgunHoldNoteAt = frame;
		NoteAct("hld", frame);
	}
	return true;
}

float CCircuitUnit::GetDGunCostE() const
{
	return (dgunDef != nullptr) ? dgunDef->GetCostE() : 0.f;
}

int CCircuitUnit::GetDGunReloadFrame() const
{
	return (dgun != nullptr) ? dgun->GetReloadFrame() : 0;
}

bool CCircuitUnit::IsDGunReady(int frame, float energy)
{
	return (dgun->GetReloadFrame() <= frame) && (dgunDef->GetCostE() <= energy)
		&& (!dgunDef->IsStockpile() || (unit->GetStockpile() > 0));
}

bool CCircuitUnit::IsShieldCharged(float percent)
{
	return shield->GetShieldPower() > circuitDef->GetMaxShield() * percent;
}

bool CCircuitUnit::IsJumpReady()
{
	return circuitDef->IsAbleToJump() && !(unit->GetRulesParamFloat("jumpReload", 1) < 1.f);
}

bool CCircuitUnit::IsJumping()
{
	return isAllowedToJump && (unit->GetRulesParamFloat("is_jumping", 0) > 0.f);
}

bool CCircuitUnit::IsInvisible()
{
	// FIXME: lua can Spring.SetUnitStealth()
	return circuitDef->IsStealth() && unit->IsCloaked();
}

float CCircuitUnit::GetDamage()
{
	float dmg = circuitDef->GetPwrDamage();
	if (dmg < 1e-3f) {
		return 0.f;
	}
	if (unit->IsParalyzed() || IsDisarmed(manager->GetCircuit()->GetLastFrame())) {
		return 0.01f;
	}
	// TODO: Mind the slow down: dps * WeaponDef->GetReload / Weapon->GetReloadTime;
	return dmg;
}

float CCircuitUnit::GetShieldPower()
{
	if (shield != nullptr) {
		return shield->GetShieldPower();
	}
	return 0.f;
}

float CCircuitUnit::GetBuildSpeed()
{
	return circuitDef->GetBuildSpeed() * unit->GetRulesParamFloat("buildpower_mult", 1.f);
}

float CCircuitUnit::GetWorkerTime()
{
	return circuitDef->GetWorkerTime() * unit->GetRulesParamFloat("buildpower_mult", 1.f);
}

float CCircuitUnit::GetDGunRange()
{
	return dgun->GetRange() * unit->GetRulesParamFloat("comm_range_mult", 1.f);
}

float CCircuitUnit::GetHealthPercent()
{
	// apex: script handles are NOCOUNT and death is deferred (the garbage
	// list collects one unit per update), so a script call can land on a
	// unit marked dead whose engine wrapper no longer answers -- crashed a
	// live watched game 2026-08-28 (AV in this frame via CallX64, script
	// Progress() reading a joined task's just-killed nanoframe). Dead reads
	// as 0% -- every caller treats that as "no progress / retreat now".
	if (isDead) {
		return 0.f;
	}
	const float maxHealth = unit->GetMaxHealth();
	if (maxHealth <= 0.f) {
		return 0.f;
	}
	return unit->GetHealth() / maxHealth - unit->GetCaptureProgress() * 16.f;
}

/*
 * UNIT_COMMAND_OPTION_ALT_KEY - remove by commandId, otherwise - by tag
 * UNIT_COMMAND_OPTION_CONTROL_KEY - remove from factory queue
 */
void CCircuitUnit::CmdRemove(std::vector<float>&& params, short options)
{
	unit->ExecuteCustomCommand(CMD_REMOVE, params, options);
}

// Records the order, and marks it a suppression candidate when re-sending it
// provably changes nothing: bit-identical to the last order of its kind, sent
// with nothing else in between, and not shortening or letting the command's
// window lapse (the refresh point is half the command's OWN timeout).
// Bit-identical is the bar because CGroundMoveType::IsMovingTowards -- the
// guard CMobileCAI::ExecuteMove puts in front of SetGoal -- is exact float
// equality on goalPos; a destination off by a fraction of an elmo re-paths.
// Candidates are counted either way and dropped only under apex_order_dedupe.
// apex: names for CCircuitUnit::OrdSrc, in enum order. Kept beside the enum
// rather than at the log site so the census and the per-unit trace cannot
// disagree about which call site an index means.
// retreat > dodge > standoff > guard is apexearth's standing ruling; the rest
// follow the same principle and his max-range rule. The derivation and what
// it is for are in docs/24-how-units-fight.md.
//
// TRAVEL and FWALK are deliberately UNRANKED (-1): the unit-action layer
// executes whatever was decided, so blocking it would freeze the very
// retreat it is carrying out. SETTGT moves nothing.
int CCircuitUnit::OrdSrcPrio(int src)
{
	switch (static_cast<OrdSrc>(src)) {
		case OrdSrc::MANUAL:                        return 100;
		case OrdSrc::RETREAT:                       return 90;
		case OrdSrc::DODGE:                         return 80;
		case OrdSrc::STANDOFF: case OrdSrc::RING:
		case OrdSrc::SNIPER:                        return 70;
		case OrdSrc::ENGAGE:   case OrdSrc::ATTACK:
		case OrdSrc::COMBAT:                        return 60;
		case OrdSrc::REGROUP:  case OrdSrc::RALLY:
		case OrdSrc::ESCORT:                        return 50;
		case OrdSrc::POST:     case OrdSrc::GUARD:  return 40;
		case OrdSrc::PATROL:   case OrdSrc::SCOUT:
		case OrdSrc::BUILD:                         return 30;
		case OrdSrc::SCRIPT:                        return 20;
		case OrdSrc::SETTGT:                        return -1;  // sets a target, moves nothing
		case OrdSrc::TRAVEL:   case OrdSrc::FWALK:  return -1;  // executes, does not decide
		default:                                    return 10;
	}
}

const char* CCircuitUnit::OrdSrcName(int src)
{
	static const char* names[] = {"other", "ring", "travel", "dodge",
			"standoff", "post", "retreat", "build", "scout", "settgt",
			"attack", "patrol", "engage", "regroup", "escort", "sniper",
			"manual", "script", "fightwalk", "combat", "guard", "rally"};
	static_assert(sizeof(names) / sizeof(names[0])
			== static_cast<size_t>(CCircuitUnit::OrdSrc::_SIZE),
			"OrdSrcName is out of step with OrdSrc");
	return ((src >= 0) && (src < static_cast<int>(OrdSrc::_SIZE))) ? names[src] : "?";
}

bool CCircuitUnit::NoteOrder(OrdKind kind, short options, const AIFloat3& pos, int id, int timeout,
		OrdSrc src)
{
	if (manager == nullptr) {
		return false;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	SOrdShadow& s = ordLast[static_cast<int>(kind)];
	const int gap = frame - s.frame;

	int bucket = -1;
	bool suppress = false;
	// Only while the previous one is plausibly still running: every re-issue
	// loop in this AI ticks at 1s, so 3s covers them and excludes a new journey.
	if ((gap >= 0) && (gap <= FRAMES_PER_SEC * 3) && (s.opts == options) && (s.id == id)) {
		const float dx = pos.x - s.x;
		const float dz = pos.z - s.z;
		const float sq = dx * dx + dz * dz;
		bucket = (sq <= 0.f) ? 0
				: (sq < SQUARE(float(SQUARE_SIZE))) ? 1
				: (sq < SQUARE(float(SQUARE_SIZE * 4))) ? 2
				: (sq < SQUARE(float(SQUARE_SIZE * 16))) ? 3 : 4;
		suppress = (bucket == 0) && (s.seq == ordSeq) && (timeout >= s.timeout)
				&& ((s.timeout == INT_MAX) || (gap * 2 < s.timeout - s.frame));
	}
	circuit->NoteOrder(static_cast<int>(kind), bucket, suppress, static_cast<int>(src));
	// apex: PER-UNIT ORDER TRACE. The census says how much churn there is and
	// which call site made it, then throws away who it happened to. `jump` is
	// the distance from this unit's last order OF THE SAME KIND and `gap` the
	// frames since, so a contradiction reads as a large jump at a small gap.
	// Off by default: one line per order.
	if (circuit->GetTunable("apex_order_trace", 0.f) > 0.f) {
		static const char* kindName[static_cast<int>(OrdKind::_SIZE)] = {
				"move", "fight", "patrol", "attack", "target"};
		const IUnitTask* task = GetTask();
		float jump = -1.f;
		if (s.frame > 0) {
			const float dx = pos.x - s.x;
			const float dz = pos.z - s.z;
			jump = sqrtf(dx * dx + dz * dz);
		}
		// q=1 is a SHIFT order: APPENDED to the unit's queue, not a
		// replacement. Without it a queued path waypoint is indistinguishable
		// from a centre overriding the order, and MoveAction deliberately
		// queues a lookahead waypoint every step -- 1,528 of them in one 20
		// minute game, which read as contradictions until this was logged.
		circuit->LOG("apex: ord t=%i u=%i %s f=%i src=%s kind=%s to=%.0f,%.0f"
				" tgt=%i jump=%.0f gap=%i task=%i/%i dup=%i q=%i",
				circuit->GetTeamId(), (int)GetId(),
				(circuitDef != nullptr) ? circuitDef->GetDef()->GetName() : "?",
				frame, OrdSrcName(static_cast<int>(src)),
				kindName[static_cast<int>(kind)], pos.x, pos.z, id, jump,
				(s.frame > 0) ? (frame - s.frame) : -1,
				(task != nullptr) ? static_cast<int>(task->GetType()) : -1,
				GetTaskFrame(), suppress ? 1 : 0,
				((options & UNIT_COMMAND_OPTION_SHIFT_KEY) != 0) ? 1 : 0);
	}
	// Counted whether or not it is dropped, so one run with the switch OFF says
	// exactly what turning it on would buy. Default off: the engine's own move
	// state is provably unchanged (above), but the dropped order also skips the
	// extra UnitIdle the engine raises when it finishes a move the unit has
	// already arrived at, and that event stream is not proven identical.

	// THE ARBITER. OFF by default: it refuses ~450 orders a game and no
	// measurement showed that helping. A centre ranked below the one whose
	// decision the unit is
	// still carrying out does not get to overwrite it. Without this the last
	// writer won, which is why a corrected standoff ring measured perfect and
	// changed nothing visible: the unit was re-ordered before it ever arrived.
	// The window is the same 3s the census uses to call a re-send a repeat --
	// bounded, so a unit can never be held longer than one decision's life.
	const int prio = OrdSrcPrio(static_cast<int>(src));
	if ((prio >= 0) && (circuit->GetTunable("apex_order_arbiter", 0.f) > 0.f)) {
		const int hold = int(circuit->GetTunable("apex_intent_hold", 3.f) * FRAMES_PER_SEC);
		const int age = frame - intentFrame;
		if ((intentPrio > prio) && (age >= 0) && (age < hold)) {
			circuit->NoteOrderRefused(static_cast<int>(src), intentPrio);
			return true;   // refused: the standing higher-ranked order keeps running
		}
		intentPrio = prio;
		intentFrame = frame;
	}
	if (suppress) {
		suppress = circuit->GetTunable("apex_order_dedupe", 0.f) > 0.f;
	}

	if (!suppress) {  // a suppressed order leaves the standing one in place
		s.x = pos.x;
		s.z = pos.z;
		s.id = id;
		s.opts = options;
		s.frame = frame;
		s.timeout = timeout;
		++ordSeq;
		s.seq = ordSeq;
	}
	return suppress;
}

static unsigned sFormAsks = 0, sFormApplied = 0;

// Only the orders that move a squad AS a squad get a slot. A build site, a
// retreat point, the standoff ring and an attack position all carry their own
// geometry and must land exactly where they were aimed.
AIFloat3 CCircuitUnit::InFormation(const AIFloat3& p, OrdSrc src) const
{
	switch (src) {
		case OrdSrc::TRAVEL: case OrdSrc::FWALK:
		case OrdSrc::REGROUP: case OrdSrc::RALLY:
			break;
		default:
			return p;
	}
	++sFormAsks;
	if (formLateral == 0.f) {
		return p;
	}
	AIFloat3 dir = formDir;
	if (!utils::is_valid(dir) || (dir.SqLength2D() < 1.f)) {
		// No squad heading yet (a gather with nobody having travelled): face the
		// way we are about to walk, so the slots still open into a line abreast
		// rather than a column.
		dir = p - GetLastPos();
		dir.y = 0.f;
		if (dir.SqLength2D() < 1.f) {
			return p;
		}
	}
	dir.Normalize2D();
	AIFloat3 out(p.x - dir.z * formLateral, p.y, p.z + dir.x * formLateral);
	CTerrainManager::CorrectPosition(out);
	++sFormApplied;
	return out;
}

void CCircuitUnit::CmdMoveTo(const AIFloat3& p0, short options, int timeout, OrdSrc src)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	const AIFloat3 pos = InFormation(p0, src);
	if (NoteOrder(OrdKind::MOVE, options, pos, 0, timeout, src)) {
		return;
	}
	NoteAct("mov", timeout);
	assert(utils::is_in_map(pos));
	NoteSniperOrder(CCircuitDef::SniperOrder::MOVE);
	unit->MoveTo(pos, options, timeout);
//	unit->ExecuteCustomCommand(CMD_RAW_MOVE, {pos.x, pos.y, pos.z}, options, timeout);
}

// A factory set to repeat re-queues what it finishes, so it keeps producing
// without waiting to be handed the next task.
void CCircuitUnit::CmdRepeat(bool repeat, short options, int timeout)
{
	unit->SetRepeat(repeat, options, timeout);
}

void CCircuitUnit::CmdJumpTo(const AIFloat3& pos, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
//	assert(utils::is_in_map(pos));
//	unit->ExecuteCustomCommand(CMD_JUMP, {pos.x, pos.y, pos.z}, options, timeout);
}

void CCircuitUnit::CmdFightTo(const AIFloat3& p0, short options, int timeout, OrdSrc src)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	// A sniper never fight-walks: CMobileCAI::ExecuteFight stops it on the
	// first thing a weapon bears on. Every travel/regroup/fallback path funnels
	// through here, so the swap covers all of them.
	if (circuitDef->IsSniper()) {
		CmdMoveTo(p0, options, timeout, src);  // InFormation applies there
		return;
	}
	const AIFloat3 pos = InFormation(p0, src);
	NoteAct("fgt", timeout);
	assert(utils::is_in_map(pos));
	NoteSniperOrder(CCircuitDef::SniperOrder::FIGHT);
	if (NoteOrder(OrdKind::FIGHT, options, pos, 0, timeout, src)) {
		return;
	}
	unit->Fight(pos, options, timeout);
}

void CCircuitUnit::CmdPatrolTo(const AIFloat3& pos, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	assert(utils::is_in_map(pos));
	if (NoteOrder(OrdKind::PATROL, options, pos, 0, timeout, OrdSrc::PATROL)) {
		return;
	}
	unit->PatrolTo(pos, options, timeout);
}

void CCircuitUnit::CmdAttackGround(const AIFloat3& pos, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	if (circuitDef->IsSniper()) {
		CmdMoveTo(SniperHoldPos(pos), options, timeout, OrdSrc::SNIPER);
		return;
	}
	assert(utils::is_in_map(pos));
	if (NoteOrder(OrdKind::ATTACK, options, pos, -1, timeout, OrdSrc::ATTACK)) {
		return;
	}
	unit->ExecuteCustomCommand(CMD_ATTACK_GROUND, {pos.x, pos.y, pos.z}, options, timeout);
}

AIFloat3 CCircuitUnit::SniperHoldPos(const AIFloat3& tPos)
{
	const int frame = (manager != nullptr) ? manager->GetCircuit()->GetLastFrame() : 0;
	const AIFloat3& cur = GetPos(frame);
	AIFloat3 dir = cur - tPos;
	if (dir.SqLength2D() < 1.f) {
		dir = AIFloat3(1.f, 0.f, 0.f);
	}
	dir.SafeNormalize2D();
	AIFloat3 hold = tPos + dir * (circuitDef->GetMaxRange(CCircuitDef::RangeType::LAND) * 0.9f);
	CTerrainManager::CorrectPosition(hold);
	return hold;
}

void CCircuitUnit::NoteSniperOrder(CCircuitDef::SniperOrder kind) const
{
	if ((manager != nullptr) && circuitDef->IsSniper()) {
		manager->GetCircuit()->NoteSniperOrder(kind);
	}
}

void CCircuitUnit::CmdAttack(CEnemyInfo* enemy, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	// An attack order walks a sniper in and StopMoves it under fire
	// (CMobileCAI::ExecuteObjectAttack); it holds at its own range instead.
	if (circuitDef->IsSniper()) {
		CmdMoveTo(SniperHoldPos(enemy->GetPos()), options, timeout, OrdSrc::SNIPER);
		return;
	}
	NoteSniperOrder(CCircuitDef::SniperOrder::ATTACK);
	// Zero position on purpose: an attack order names a UNIT, so the enemy id
	// alone decides whether this repeats the last one. The ground variant above
	// names a point, and there the distance buckets are the measurement.
	if (NoteOrder(OrdKind::ATTACK, options, ZeroVector, enemy->GetId(), timeout, OrdSrc::ATTACK)) {
		return;
	}
	unit->Attack(enemy->GetUnit(), options, timeout);
}

void CCircuitUnit::CmdWantedSpeed(float speed)
{
//	unit->SetWantedMaxSpeed(speed / FRAMES_PER_SEC, true);
//	unit->SetWantedMaxSpeed(0.5f, true);
//	unit->ExecuteCustomCommand(CMD_WANTED_SPEED, {speed});
}

void CCircuitUnit::CmdStop(short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->Stop(options, timeout);
	// CMD_STOP is one of unit_target_on_the_move's own removal paths (we never
	// pass ctrl, so ignoreStop is false and it drops the holder outright).
	if (manager != nullptr) {
		manager->GetCircuit()->TgtHoldDel(this);
	}
}

void CCircuitUnit::CmdSetTarget(CEnemyInfo* enemy)
{
	// apex: ENABLED. This was an empty body, so both Attack() overloads ended by
	// calling a no-op and the squad had only move-and-attack orders -- which walk
	// a unit INTO its target rather than letting it shoot while manoeuvring.
	// apexearth: "we should not give specific 'attack this unit' orders, we
	// should move around within range of the unit and use 'set target'... that
	// would allow us to keep moving while shooting at that enemy."
	// Verified handled, unlike the ai_super_fire strings in SuperTask which have
	// no listener in either game tree: BAR.sdd/modules/customcommands.lua defines
	// UNIT_SET_TARGET = 34923, matching CMD_UNIT_SET_TARGET here, and
	// luarules/gadgets/unit_target_on_the_move.lua registers and handles it. The
	// gadget's name is the feature.
	if (enemy == nullptr) {
		return;
	}
	// OUT OF REACH IS NOT A TARGET (apexearth: "set target commands against
	// enemy units which are far out of range"). 5,622 of these went out in one
	// 38-minute game; unit_target_on_the_move.lua discards any it cannot reach,
	// so most were already inert -- but they showed on his screen and they lie
	// to every consumer of tgtHeldId. ISquadTask::Attack re-issues each
	// apex_standoff_s, so the target reapplies the moment we are in reach. The
	// bar is this unit's OWN max weapon range, not the squad leader's.
	if ((circuitDef != nullptr) && (circuitDef->GetMaxRange() > 0.f)) {
		const AIFloat3& ePos = enemy->GetPos();
		const AIFloat3& mPos = GetPos(manager != nullptr ? manager->GetCircuit()->GetLastFrame() : 0);
		if (ePos.SqDistance2D(mPos) > SQUARE(circuitDef->GetMaxRange())) {
			return;
		}
	}
	NoteSniperOrder(CCircuitDef::SniperOrder::SET_TARGET);
	NoteOrder(OrdKind::TARGET, 0, ZeroVector, enemy->GetId(), INT_MAX, OrdSrc::SETTGT);
	unit->ExecuteCustomCommand(CMD_UNIT_SET_TARGET, {(float)enemy->GetId()});
	// The gadget enrols only what its own validUnits table admits
	// (canAttack and maxWeaponRange > 0); counting the rest would inflate the
	// census with units it never sweeps.
	if ((manager != nullptr) && (circuitDef != nullptr) && (circuitDef->GetMaxRange() > 0.f)) {
		tgtHeldId = enemy->GetId();
		manager->GetCircuit()->TgtHoldAdd(this);
	}
}

void CCircuitUnit::CmdCloak(bool state)
{
	unit->ExecuteCustomCommand(CMD_WANT_CLOAK, {state ? 1.f : 0.f});  // personal
//	unit->ExecuteCustomCommand(CMD_CLOAK_SHIELD, {state ? 1.f : 0.f});  // area
//	unit->Cloak(state);
}

void CCircuitUnit::CmdFireAtRadar(bool state)
{
//	unit->ExecuteCustomCommand(CMD_DONT_FIRE_AT_RADAR, {state ? 0.f : 1.f});
}

void CCircuitUnit::CmdFindPad(int timeout)
{
//	unit->ExecuteCustomCommand(CMD_FIND_PAD, {}, 0, timeout);
	unit->ExecuteCustomCommand(CMD_LAND_AT_AIRBASE, {}, 0, timeout);
}

void CCircuitUnit::CmdManualFire(short options, int timeout)
{
//	unit->ExecuteCustomCommand(CMD_ONECLICK_WEAPON, {}, options, timeout);
}

void CCircuitUnit::CmdAirManualFire(const AIFloat3& pos, short options, int timeout)
{
//	unit->ExecuteCustomCommand(CMD_AIR_MANUALFIRE, {pos.x, pos.y, pos.z}, options, timeout);
}

void CCircuitUnit::CmdPriority(float value)
{
//	unit->ExecuteCustomCommand(CMD_PRIORITY, {value});
}

void CCircuitUnit::CmdMiscPriority(float value)
{
//	unit->ExecuteCustomCommand(CMD_MISC_PRIORITY, {value});
}

void CCircuitUnit::CmdAirStrafe(float value)
{
//	unit->ExecuteCustomCommand(CMD_AIR_STRAFE, {value});
}

void CCircuitUnit::CmdBARPriority(float value)
{
	if (priority == value) {
		return;
	}
	priority = value;
	unit->ExecuteCustomCommand(CMD_BAR_PRIORITY, {value});
}

void CCircuitUnit::CmdTerraform(std::vector<float>&& params)
{
//	unit->ExecuteCustomCommand(CMD_TERRAFORM_INTERNAL, params);
}

void CCircuitUnit::CmdSelfD(bool state)
{
	if (isSelfD != state) {
		unit->SelfDestruct();
		isSelfD = state;
	}
}

void CCircuitUnit::CmdWait(bool state)
{
	if (state != (command->GetId() == CMD_WAIT)) {
		unit->Wait();
	}
}

void CCircuitUnit::RemoveWait()
{
	CmdRemove({CMD_WAIT}, UNIT_COMMAND_OPTION_ALT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY);
}

bool CCircuitUnit::IsWaiting() const
{
	return command->GetId() == CMD_WAIT;
}

void CCircuitUnit::CmdRepair(CAllyUnit* target, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->Repair(target->GetUnit(), options, timeout);
	taskState = ETaskState::EXECUTE;
}

void CCircuitUnit::CmdBuild(CCircuitDef* buildDef, const AIFloat3& buildPos, int facing, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->Build(buildDef->GetDef(), buildPos, facing, options, timeout);
	taskState = ETaskState::EXECUTE;
}

void CCircuitUnit::CmdReclaimEnemy(CEnemyInfo* enemy, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->ReclaimUnit(enemy->GetUnit(), options, timeout);
}

void CCircuitUnit::CmdReclaimUnit(CAllyUnit* toReclaim, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->ReclaimUnit(toReclaim->GetUnit(), options, timeout);
	taskState = ETaskState::EXECUTE;
}

void CCircuitUnit::CmdReclaimInArea(const AIFloat3& pos, float radius, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->ReclaimInArea(pos, radius, options, timeout);
}

void CCircuitUnit::CmdResurrectInArea(const AIFloat3& pos, float radius, short options, int timeout)
{
	if ((manager != nullptr) && IsDGunHeld(manager->GetCircuit()->GetLastFrame())) {
		return;
	}
	unit->ResurrectInArea(pos, radius, options, timeout);
}

void CCircuitUnit::CmdSetFireState(CCircuitDef::FireT state)
{
	unit->SetFireState(state);
}

void CCircuitUnit::TrySetFireState(CCircuitDef::FireT state)
{
	assert(manager != nullptr);
	TRY_UNIT(manager->GetCircuit(), this,
		CmdSetFireState(state);
	)
}

void CCircuitUnit::CmdSetMoveState(CCircuitDef::MoveT state)
{
	unit->SetMoveState(state);
}

void CCircuitUnit::TrySetMoveState(CCircuitDef::MoveT state)
{
	assert(manager != nullptr);
	TRY_UNIT(manager->GetCircuit(), this,
		CmdSetMoveState(state);
	)
}

void CCircuitUnit::Attack(CEnemyInfo* enemy, bool isGround, int timeout)
{
	NoteAct("atk", timeout);
	target = enemy;
	// A sniper takes only the hold move and the target: the queued fight
	// order below would walk it in.
	if (circuitDef->IsSniper()) {
		TRY_UNIT(manager->GetCircuit(), this,
			CmdAttack(enemy, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			CmdSetTarget(target);
		)
		return;
	}
	TRY_UNIT(manager->GetCircuit(), this,
		const AIFloat3& pos = enemy->GetPos();
		if (circuitDef->IsAttrMelee()) {
			if (IsJumpReady()) {
				CmdJumpTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
				if (isGround) {  // los-cheat related
					CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				} else {
					CmdAttack(enemy, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				}
			} else {
				CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout, OrdSrc::RING);
				if (isGround) {  // los-cheat related
					CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				} else {
					CmdAttack(enemy, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				}
			}
		} else {
			if (isGround) {  // los-cheat related
				CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			} else {
				CmdAttack(enemy, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			}
		}
		CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout, OrdSrc::RING);  // los-cheat related
		CmdWantedSpeed(NO_SPEED_LIMIT);
		CmdSetTarget(target);
	)
}

void CCircuitUnit::Attack(const AIFloat3& pos, CEnemyInfo* enemy, bool isGround, bool isStatic, int timeout, bool hold)
{
	NoteAct("atkp", timeout);
	// `pos` is a standoff point on a ring of this unit's own weapon range, and
	// the orders that used to follow it threw it away. CMD_FIGHT re-acquires the
	// CLOSEST enemy within maxRange + 100*moveState^2 and pushes its own
	// CMD_ATTACK to the front of the queue (CMobileCAI::ExecuteFight), and
	// CMD_ATTACK calls StopMove() the moment a weapon bears
	// (CMobileCAI::ExecuteObjectAttack). Either one discards both the distance
	// and the target chosen here.
	//
	// Move plus set-target instead. The move order ends at the ring;
	// unit_target_on_the_move re-applies the preference every 5 frames on its
	// own, so no repeat order is needed and weapons fire while the unit walks.
	// Anything else in range is still answered by engine auto-targeting, which
	// yields to a user target only while that target can actually be hit
	// (CWeapon::AllowWeaponAutoTarget).
	//
	// Two cases keep the old orders, because set-target cannot express them:
	// a cloaked target must be attacked as ground, and melee delivers its
	// damage by arriving. A radar-only contact does NOT need them: the gadget
	// drops a set-target only when the contact leaves radar AND los
	// (unit_target_on_the_move's removeUnseenTarget: los % 4 == 0), so it
	// tracks the dot on its own and the engine fires at it from the ring.
	// The engine-attack fallback below survives only for a fully dark ghost,
	// and only for a unit whose own sight covers its weapon reach: a long gun
	// (range > sight -- Hound 650/400, Sharpshooter 900/455) cannot gain its
	// own los without standing inside enemy fire, so it holds the ring at the
	// last known position and waits for allied vision instead of chasing.
	const bool longGun = circuitDef->GetMaxRange() > circuitDef->GetLosRadius();
	// A sniper takes move + set-target unconditionally, cloaked target included:
	// the attack-ground fallback is an order that halts it under fire.
	// `hold`: the point keeps it out of a D-gun's reach, and any queued attack
	// or fight order would walk it back in (a Titan is tagged melee).
	const bool prefer = hold || circuitDef->IsSniper()
			|| ((manager->GetCircuit()->GetTunable("apex_prefer_target", 1.f) > 0.f)
			&& !isGround && !circuitDef->IsAttrMelee()
			&& (isStatic || enemy->IsInRadarOrLOS() || longGun));
	TRY_UNIT(manager->GetCircuit(), this,
		if (!hold && circuitDef->IsAttrMelee() && IsJumpReady()) {
			CmdJumpTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout, OrdSrc::RING);
		} else {
			CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout, OrdSrc::RING);
		}
		if (!prefer) {
			if (isGround) {  // los-cheat related
				CmdAttackGround(enemy->GetPos(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				CmdFightTo(enemy->GetPos(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout, OrdSrc::RING);  // los-cheat related
			} else {
				// NO queued CmdFightTo here: a fight order re-acquires the
				// closest enemy and stops all movement the moment a weapon
				// bears (CMobileCAI::ExecuteFight), which cancelled the
				// spacing move for every unit whose weapon out-ranges its
				// sight -- a Hound (650 range, ~400 sight) reads !IsInLOS on
				// nearly every properly-held standoff target, so its kite
				// point died to this constantly (apexearth, watching: "when
				// our hound style unit wants to run away or get spacing it
				// uses a fight command"). The queued ATTACK already closes
				// distance if the blip is genuinely out of reach, which was
				// the fight order's whole job.
				CmdAttack(enemy, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
			}
		}
		CmdWantedSpeed(NO_SPEED_LIMIT);
		CmdSetTarget(target);
		if (circuitDef->IsAttrOnOff()) {
			unit->SetOn(isStatic == circuitDef->IsOnSlow());
		}
	)
}

void CCircuitUnit::Attack(const AIFloat3& position, CEnemyInfo* enemy, int tile, bool isGround, bool isStatic, int timeout, bool hold)
{
	target = enemy;
	targetTile = tile;
	Attack(position, enemy, isGround, isStatic, timeout, hold);
}

void CCircuitUnit::Guard(CCircuitUnit* target, int timeout)
{
	TRY_UNIT(manager->GetCircuit(), this,
//		unit->ExecuteCustomCommand(CMD_ORBIT, {(float)target->GetId(), 300.0f}, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
		unit->Guard(target->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
//		CmdWantedSpeed(NO_SPEED_LIMIT);
	)
}

void CCircuitUnit::Gather(const AIFloat3& groupPos, int timeout)
{
//	const AIFloat3& pos = utils::get_radial_pos(groupPos, SQUARE_SIZE * 8);
	TRY_UNIT(manager->GetCircuit(), this,
		CmdMoveTo(groupPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout, OrdSrc::REGROUP);
		CmdWantedSpeed(NO_SPEED_LIMIT);
//		CmdPatrolTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
	)
}

void CCircuitUnit::Morph()
{
	isMorphing = true;
	TRY_UNIT(manager->GetCircuit(), this,
		unit->ExecuteCustomCommand(CMD_MORPH, {});
		CmdMiscPriority(1);
	)
}

void CCircuitUnit::StopMorph()
{
	isMorphing = false;
	TRY_UNIT(manager->GetCircuit(), this,
		unit->ExecuteCustomCommand(CMD_MORPH_STOP, {});
		CmdMiscPriority(1);
	)
}

bool CCircuitUnit::IsUpgradable()
{
	unsigned level = unit->GetRulesParamFloat("comm_level", 0.f);
	assert(manager != nullptr);
	return manager->GetCircuit()->GetSetupManager()->HasModules(circuitDef, level);
}

void CCircuitUnit::Upgrade()
{
	isMorphing = true;
	/*
	 * @see
	 * gui_chili_commander_upgrade.lua
	 * unit_morph.lua
	 * unit_commander_upgrade.lua
	 * dynamic_comm_defs.lua
	 *
	 * Level = params[1]
	 * Chassis = params[2]
	 * AlreadyCount = params[3]
	 * NewCount = params[4]
	 * OwnedModules = params[5..N]
	 * NewModules = params[N+1..M]
	 */

	float level = unit->GetRulesParamFloat("comm_level", 0.f);
	float chassis = unit->GetRulesParamFloat("comm_chassis", 0.f);
	float alreadyCount = unit->GetRulesParamFloat("comm_module_count", 0.f);

	assert(manager != nullptr);
	const std::vector<float>& newModules = manager->GetCircuit()->GetSetupManager()->GetModules(circuitDef, level);

	std::vector<float> upgrade;
	upgrade.push_back(level);
	upgrade.push_back(chassis);
	upgrade.push_back(alreadyCount);
	upgrade.push_back(newModules.size());

	for (int i = 1; i <= alreadyCount; ++i) {
		std::string modId = utils::int_to_string(i, "comm_module_%i");
		float value = unit->GetRulesParamFloat(modId.c_str(), -1.f);
		if (value != -1.f) {
			upgrade.push_back(value);
		}
	}

	upgrade.insert(upgrade.end(), newModules.begin(), newModules.end());

	TRY_UNIT(manager->GetCircuit(), this,
		unit->ExecuteCustomCommand(CMD_MORPH_UPGRADE_INTERNAL, upgrade);
		CmdMiscPriority(1);
	)
}

void CCircuitUnit::StopUpgrade()
{
	isMorphing = false;
	TRY_UNIT(manager->GetCircuit(), this,
		unit->ExecuteCustomCommand(CMD_UPGRADE_STOP, {});
		CmdMiscPriority(1);
	)
}

ICoreUnit::Id CCircuitUnit::GetUnitIdReclaim() const
{
	if (command->GetId() != CMD_RECLAIM) {
		return -1;
	}
	auto params = command->GetParams();
	return (params.size() == 1) ? params[0] : -1;
}

#ifdef DEBUG_VIS
void CCircuitUnit::Log()
{
	if (task != nullptr) {
		task->Log();
	}
	CCircuitAI* circuit = manager->GetCircuit();
	if (travelAct != nullptr) {
		travelAct->Log(circuit);
	}
	GetPos(circuit->GetLastFrame());
	circuit->LOG("unit: %lx | id: %i | %f, %f, %f | %s", this, id, position.x, position.y, position.z, circuitDef->GetDef()->GetName());
	auto commands = unit->GetCurrentCommands();
	for (springai::Command* c : commands) {
		circuit->LOG("command: %i | type: %i | id: %i", c->GetCommandId(), c->GetType(), c->GetId());
	}
	utils::free_clear(commands);
}
#endif

} // namespace circuit
