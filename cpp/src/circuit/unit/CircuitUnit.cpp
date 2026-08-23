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

void CCircuitUnit::ForceUpdate(int frame)
{
	if (execFrame < 0) {
		execFrame = frame;
	}
}

bool CCircuitUnit::IsForceUpdate(int frame)
{
	if (execFrame > 0) {
		if (execFrame <= frame) {
			execFrame = -1;
			return true;
		}
	}
	return false;
}

void CCircuitUnit::ManualFire(CEnemyInfo* target, int timeout)
{
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
				CmdMoveTo(leadPos, UNIT_COMMAND_OPTION_ALT_KEY, timeout);
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

bool CCircuitUnit::IsDGunReady(int frame, float energy)
{
	return (dgun->GetReloadFrame() <= frame) && (dgunDef->GetCostE() < energy)
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
	return unit->GetHealth() / unit->GetMaxHealth() - unit->GetCaptureProgress() * 16.f;
}

/*
 * UNIT_COMMAND_OPTION_ALT_KEY - remove by commandId, otherwise - by tag
 * UNIT_COMMAND_OPTION_CONTROL_KEY - remove from factory queue
 */
void CCircuitUnit::CmdRemove(std::vector<float>&& params, short options)
{
	unit->ExecuteCustomCommand(CMD_REMOVE, params, options);
}

void CCircuitUnit::CmdMoveTo(const AIFloat3& pos, short options, int timeout)
{
	assert(utils::is_in_map(pos));
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
//	assert(utils::is_in_map(pos));
//	unit->ExecuteCustomCommand(CMD_JUMP, {pos.x, pos.y, pos.z}, options, timeout);
}

void CCircuitUnit::CmdFightTo(const AIFloat3& pos, short options, int timeout)
{
	assert(utils::is_in_map(pos));
	unit->Fight(pos, options, timeout);
}

void CCircuitUnit::CmdPatrolTo(const AIFloat3& pos, short options, int timeout)
{
	assert(utils::is_in_map(pos));
	unit->PatrolTo(pos, options, timeout);
}

void CCircuitUnit::CmdAttackGround(const AIFloat3& pos, short options, int timeout)
{
	assert(utils::is_in_map(pos));
	unit->ExecuteCustomCommand(CMD_ATTACK_GROUND, {pos.x, pos.y, pos.z}, options, timeout);
}

void CCircuitUnit::CmdWantedSpeed(float speed)
{
//	unit->SetWantedMaxSpeed(speed / FRAMES_PER_SEC, true);
//	unit->SetWantedMaxSpeed(0.5f, true);
//	unit->ExecuteCustomCommand(CMD_WANTED_SPEED, {speed});
}

void CCircuitUnit::CmdStop(short options, int timeout)
{
	unit->Stop(options, timeout);
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
	unit->ExecuteCustomCommand(CMD_UNIT_SET_TARGET, {(float)enemy->GetId()});
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
	unit->Repair(target->GetUnit(), options, timeout);
	taskState = ETaskState::EXECUTE;
}

void CCircuitUnit::CmdBuild(CCircuitDef* buildDef, const AIFloat3& buildPos, int facing, short options, int timeout)
{
	unit->Build(buildDef->GetDef(), buildPos, facing, options, timeout);
	taskState = ETaskState::EXECUTE;
}

void CCircuitUnit::CmdReclaimEnemy(CEnemyInfo* enemy, short options, int timeout)
{
	unit->ReclaimUnit(enemy->GetUnit(), options, timeout);
}

void CCircuitUnit::CmdReclaimUnit(CAllyUnit* toReclaim, short options, int timeout)
{
	unit->ReclaimUnit(toReclaim->GetUnit(), options, timeout);
	taskState = ETaskState::EXECUTE;
}

void CCircuitUnit::CmdReclaimInArea(const AIFloat3& pos, float radius, short options, int timeout)
{
	unit->ReclaimInArea(pos, radius, options, timeout);
}

void CCircuitUnit::CmdResurrectInArea(const AIFloat3& pos, float radius, short options, int timeout)
{
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
	target = enemy;
	TRY_UNIT(manager->GetCircuit(), this,
		const AIFloat3& pos = enemy->GetPos();
		if (circuitDef->IsAttrMelee()) {
			if (IsJumpReady()) {
				CmdJumpTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
				if (isGround) {  // los-cheat related
					CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				} else {
					unit->Attack(enemy->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				}
			} else {
				CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
				if (isGround) {  // los-cheat related
					CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				} else {
					unit->Attack(enemy->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				}
			}
		} else {
			if (isGround) {  // los-cheat related
				CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			} else {
				unit->Attack(enemy->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			}
		}
		CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);  // los-cheat related
		CmdWantedSpeed(NO_SPEED_LIMIT);
		CmdSetTarget(target);
	)
}

void CCircuitUnit::Attack(const AIFloat3& pos, CEnemyInfo* enemy, bool isGround, bool isStatic, int timeout)
{
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
	// Three cases keep the old orders, because set-target cannot express them:
	// a cloaked target must be attacked as ground, a contact held on radar only
	// is dropped by the gadget within 15 frames and the fight order IS the
	// walk-in that gains LOS, and melee delivers its damage by arriving.
	// A static target's position never changes, so it needs no fresh LOS to
	// stay accurate the way a mobile radar-only contact does -- the "walk to
	// its actual position to confirm it" fallback below exists for ghosts,
	// not towers. A weapon range that exceeds sight radius (e.g. Hound: 650
	// range, ~400 sight -- see the squad-path fix in SquadTask.cpp) reads
	// IsInLOS()==false while correctly holding standoff, so without this the
	// fallback sent the unit walking to the tower's own ground position,
	// straight past the standoff ring it had just reached.
	const bool prefer = (manager->GetCircuit()->GetTunable("apex_prefer_target", 1.f) > 0.f)
			&& !isGround && !circuitDef->IsAttrMelee() && (isStatic || enemy->IsInLOS());
	TRY_UNIT(manager->GetCircuit(), this,
		if (circuitDef->IsAttrMelee() && IsJumpReady()) {
			CmdJumpTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
			CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
		} else {
			CmdMoveTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
		}
		if (!prefer) {
			if (isGround) {  // los-cheat related
				CmdAttackGround(enemy->GetPos(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
				CmdFightTo(enemy->GetPos(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);  // los-cheat related
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
				unit->Attack(enemy->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY | UNIT_COMMAND_OPTION_SHIFT_KEY, timeout);
			}
		}
		CmdWantedSpeed(NO_SPEED_LIMIT);
		CmdSetTarget(target);
		if (circuitDef->IsAttrOnOff()) {
			unit->SetOn(isStatic == circuitDef->IsOnSlow());
		}
	)
}

void CCircuitUnit::Attack(const AIFloat3& position, CEnemyInfo* enemy, int tile, bool isGround, bool isStatic, int timeout)
{
	target = enemy;
	targetTile = tile;
	Attack(position, enemy, isGround, isStatic, timeout);
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
		CmdMoveTo(groupPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
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
