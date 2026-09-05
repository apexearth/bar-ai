/*
 * FighterTask.cpp
 *
 *  Created on: Aug 31, 2015
 *      Author: rlcevg
 */

#include "task/fighter/FighterTask.h"
#include "task/fighter/SquadTask.h"  // OUTRANGED_SAFETY_MARGIN
#include "task/RetreatTask.h"
#include "map/InfluenceMap.h"
#include "spring/SpringMap.h"
#include "map/ThreatMap.h"
#include "module/BuilderManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "unit/action/RearmAction.h"
#include "unit/action/DGunAction.h"
#include "unit/action/TravelAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/enemy/EnemyManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"
#include "Log.h"

namespace circuit {

// Retreat-source telemetry: four rounds of retreat-bleed fixes moved nothing
// (44-47% of lost metal, four audited games) while the collective vote fired
// zero times -- so which branch actually creates the retreats has never been
// observed, only assumed. One process-wide line, rate-limited.
struct SRetreatSrc {
	int stuck = 0, los = 0, range = 0, shield = 0, idleCoward = 0,
		squadStand = 0, squadVote = 0, homeStand = 0;
	int lastLog = -1000000;
};
static SRetreatSrc sRetreatSrc;

static void LogRetreatSrc(CCircuitAI* circuit)
{
	if (circuit->GetLastFrame() < sRetreatSrc.lastLog + FRAMES_PER_SEC * 30) {
		return;
	}
	sRetreatSrc.lastLog = circuit->GetLastFrame();
	circuit->LOG("apex: retreat-src stuck=%d los=%d range=%d shield=%d"
			" idleCoward=%d squadStand=%d squadVote=%d homeStand=%d",
			sRetreatSrc.stuck, sRetreatSrc.los, sRetreatSrc.range,
			sRetreatSrc.shield, sRetreatSrc.idleCoward,
			sRetreatSrc.squadStand, sRetreatSrc.squadVote,
			sRetreatSrc.homeStand);
}

using namespace springai;

F3Vec IFighterTask::urgentPositions;  // NOTE: micro-opt
F3Vec IFighterTask::enemyPositions;  // NOTE: micro-opt

IFighterTask::IFighterTask(ITaskModule* mgr, FightType type, float powerMod, int timeout)
		: IUnitTask(mgr, Priority::NORMAL, Type::FIGHTER, timeout)
		, fightType(type)
		, position(-RgtVector)
		, attackPower(.0f)
		, powerMod(powerMod)
		, attackFrame(-1)
		, target(nullptr)
{
#if CIRCUIT_TASK_REGISTRY
	// Recorded HERE, not in IUnitTask's ctor: the derived part does not exist
	// yet at that point. Registering the subtype while the object is alive is
	// what lets a stale-pointer report name the task without reading freed
	// memory.
	IUnitTask::NoteSubtype(this, int(type));
#endif
}

const char* IFighterTask::FightTypeName(int ft)
{
	static const char* NAMES[] = {
		"RALLY", "GUARD", "DEFEND", "SCOUT", "RAID", "ATTACK", "BOMB",
		"MELEE", "ARTY", "AA", "AH", "SUPPORT", "SUPER"
	};
	// Unlike script/task.as's hand-maintained copy of this enum, this table is
	// checked: add or reorder a FightType and the build stops here.
	static_assert(sizeof(NAMES) / sizeof(NAMES[0]) == size_t(FightType::_SIZE_),
			"FightTypeName table is out of step with FightType");
	if ((ft < 0) || (ft >= int(FightType::_SIZE_))) {
		return "-";
	}
	return NAMES[ft];
}

IFighterTask::~IFighterTask()
{
	if (target != nullptr) {
		target->UnbindTask(this);
	}
}

AIFloat3 IFighterTask::RoamPos(CCircuitUnit* unit) const
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 pos;
	if ((circuit->GetTunable("apex_roam_front", 1.f) > 0.f) && circuit->HasFrontPos()) {
		const int r = (int)circuit->GetTunable("apex_roam_r", 1200.f);
		const AIFloat3& fp = circuit->GetFrontPos();
		float x = fp.x + (float)(rand() % (2 * r)) - (float)r;
		float z = fp.z + (float)(rand() % (2 * r)) - (float)r;
		x = utils::clamp(x, 0.f, (float)terrainMgr->GetTerrainWidth() - 1.f);
		z = utils::clamp(z, 0.f, (float)terrainMgr->GetTerrainHeight() - 1.f);
		pos = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
	} else {
		float x = rand() % terrainMgr->GetTerrainWidth();
		float z = rand() % terrainMgr->GetTerrainHeight();
		pos = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
	}
	return terrainMgr->GetMovePosition(unit->GetArea(), pos);
}

void IFighterTask::AssignTo(CCircuitUnit* unit)
{
	IUnitTask::AssignTo(unit);

	CCircuitDef* cdef = unit->GetCircuitDef();
	attackPower += cdef->GetPower();
	if (unit->HasShield()) {
		shields.insert(unit);
	}

	if (cdef->IsAttrRearm()) {
		unit->PushBack(new CRearmAction(unit));
	}

	if (unit->HasDGun()) {
		const float range = std::max(unit->GetDGunRange() * 1.1f, cdef->GetLosRadius());
		unit->PushDGunAct(new CDGunAction(unit, range));
	}
}

void IFighterTask::RemoveAssignee(CCircuitUnit* unit)
{
	IUnitTask::RemoveAssignee(unit);

	attackPower -= unit->GetCircuitDef()->GetPower();
	cowards.erase(unit);
	if (unit->HasShield()) {
		shields.erase(unit);
	}
}

void IFighterTask::Update()
{
	CCircuitAI* circuit = manager->GetCircuit();
	// Healed rear-standers rejoin the line -- mid-fight repair exists exactly
	// so a unit comes back. Exit above 1.15x the entry bar (hysteresis, no
	// flapping at the boundary); gated on the tunable so the OFF arm keeps
	// the shipped sliver-coward behavior untouched.
	const float cowardHp = circuit->GetTunable("apex_coward_hp", 0.6f);
	if (cowardHp > 0.f) {
		const float rejoinHp = cowardHp * 1.15f;
		for (auto it = cowards.begin(); it != cowards.end(); ) {
			CCircuitUnit* u = *it;
			if ((u->GetCircuitDef() != nullptr)
				&& (u->GetHealthPercent() > rejoinHp))
			{
				it = cowards.erase(it);
			} else {
				++it;
			}
		}
	}
	const float minShield = circuit->GetSetupManager()->GetEmptyShield();
	decltype(units) tmpUnits = shields;
	for (CCircuitUnit* unit : tmpUnits) {
		if (!unit->IsShieldCharged(minShield)) {
			++sRetreatSrc.shield;
			CRetreatTask* task = manager->EnqueueRetreat();
			manager->AssignTask(unit, task);
		}
	}
}

void IFighterTask::OnUnitIdle(CCircuitUnit* unit)
{
	auto it = cowards.find(unit);
	if (it != cowards.end()) {
		// THE IDLE LEAK: a wounded member standing at its rear slot ARRIVES
		// there, goes idle, and this branch handed it a solo retreat -- home
		// alone through the fight, from as deep as fwd 1.4. Audited (Altored
		// 4v4 rematch): 599 units, 44% of lost metal, died on solo retreats
		// while the collective vote fired ZERO times -- the coward mechanism
		// was feeding its members one at a time into exactly the deaths it
		// exists to prevent. While the squad still exists and has a fight, a
		// coward stays in formation; TrySquadRetreat's vote is the only exit
		// mid-fight.
		if ((GetTarget() != nullptr) && (units.size() >= 2)) {
			unit->SetTaskFrame(manager->GetCircuit()->GetLastFrame());
			return;
		}
		cowards.erase(it);
		// A rear-stander above its own retreat bar still has a fight in it;
		// only sliver-HP cowards leave for repair when the squad's fight ends.
		if (unit->GetHealthPercent() > unit->GetCircuitDef()->GetRetreat()) {
			unit->SetTaskFrame(manager->GetCircuit()->GetLastFrame());
			return;
		}
		++sRetreatSrc.idleCoward;
		LogRetreatSrc(manager->GetCircuit());
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
	} else {
		unit->SetTaskFrame(manager->GetCircuit()->GetLastFrame());
	}
}

// Repairing a damaged unit MID-FIGHT was gated on IsRoleHeavy(), which in this
// config is essentially T3 plus armfboy -- so for a normal army the repair path
// was nearly dead, and a unit only ever got repaired after it had already given
// up and retreated. apexearth: "if constructors are also helping to heal us
// while we fight, all these things can really help us to turn things around."
//
// Cost is the filter instead of role: repairing a 42-metal Grunt is not worth a
// constructor's walk, repairing a 665-metal Tiger plainly is.
// 150 made this "every damaged unit in the army", each enqueued at Priority::NOW,
// which preempts construction: constructors left the base to chase damaged units
// into the fight. Build power is the economy, so this was paid for out of it.
#define REPAIR_WORTH_COST	900.f

static inline bool IsWorthRepair(CCircuitDef* cdef)
{
	return (cdef->GetCostM() >= REPAIR_WORTH_COST) && !cdef->IsRoleComm();
}

void IFighterTask::NoteSquadStand(CCircuitAI* c) { ++sRetreatSrc.squadStand; LogRetreatSrc(c); }
void IFighterTask::NoteSquadVote(CCircuitAI* c)  { ++sRetreatSrc.squadVote;  LogRetreatSrc(c); }
void IFighterTask::NoteHomeStand(CCircuitAI* c)  { ++sRetreatSrc.homeStand;  LogRetreatSrc(c); }

void IFighterTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CCircuitDef* cdef = unit->GetCircuitDef();
	unit->ForceUpdate(frame + THREAT_UPDATE_RATE);

	// FIXME: comm kamikaze
	if (cdef->IsRoleComm() && (target != nullptr) && target->IsInLOS() && target->GetCircuitDef()->IsRoleComm()) {
		return;
	}

	// Before any retreat question: a unit that stays in the fight should not
	// stand in the stream of fire that is hitting it.
	if (!KeepRange(unit, attacker)) {
		DodgeFire(unit, attacker);
	}
	CounterBattery(unit, attacker);

	// Committed push: do not peel off. apexearth: "Need to ensure the units
	// don't suddenly say 'oh lets regroup somewhere safe!' because their purpose
	// is to kill bases, and they probably can't get away on larger maps."
	// Retreating mid-breakthrough is worse than dying in it -- a unit that turns
	// around is killed anyway on the walk home AND gives up the gap it opened.
	// Commanders still retreat: losing one loses the game, which is a different
	// trade entirely.
	// apex: THE COMMIT MUST NOT KEEP FEEDING CORPSES INTO THE PUSH. A declared
	// push/killing blow waives retreat so the attack cannot dissolve mid-swing,
	// but a unit already near death adds almost no damage and is a free kill the
	// moment the commit lifts -- measured 2026-08-22 across 16 games: retreat
	// switches happen at a median 14% hp and the unit is dead 1s later, 228k
	// metal of it. Below a fraction of its OWN threshold a unit peels out while
	// it can still make the walk; everything healthier still holds the line.
	// Default 0 keeps the waiver absolute (the behaviour every arm was measured
	// against); apex_commit_bail turns it on.
	if (circuit->IsCommitted() && !cdef->IsRoleComm()) {
		const float bail = circuit->GetTunable("apex_commit_bail", 0.f);
		if ((bail <= 0.f) || (unit->GetHealthPercent() > cdef->GetRetreat() * bail)) {
			return;
		}
	}

	// Dive commit: the task's chosen target is fat economy on their ground
	// (FindTarget's isDive). The kill pays for the squad, and a member that
	// peels off mid-dive is run down on the walk home anyway -- retreat is
	// waived for the dive's duration, an effective retreat threshold of 0.
	if (IsDiveCommit() && !cdef->IsRoleComm()) {
		return;
	}

	const float healthPerc = unit->GetHealthPercent();

	// REAR AT 60%, NOT AT THE SLIVER (apexearth: "pulling to back of the pack
	// when under 60%"). Entry to the rear ring used to coincide with the
	// retreat threshold (8-50% by cost), so a unit held the front row until it
	// was nearly dead. Marked here, the ring code screens it behind healthier
	// squadmates while it KEEPS FIGHTING; the retreat votes below still key on
	// the real thresholds. Squads only -- a lone fighter has no pack.
	if ((units.size() >= 2) && (healthPerc > cdef->GetRetreat())
		&& (healthPerc < circuit->GetTunable("apex_coward_hp", 0.6f)))
	{
		cowards.insert(unit);
	}

	if (unit->HasShield()) {
		const float minShield = circuit->GetSetupManager()->GetEmptyShield();
		if ((healthPerc > cdef->GetRetreat()) && unit->IsShieldCharged(minShield)) {
			if (IsWorthRepair(cdef) && (healthPerc < 0.9f) && !unit->IsAttrNoRepair()) {
				circuit->GetBuilderManager()->Enqueue(TaskB::Repair(IBuilderTask::Priority::NOW, unit));
			}
			return;
		}
	} else if ((healthPerc > cdef->GetRetreat()) && !unit->IsDisarmed(frame)) {
		if (IsWorthRepair(cdef) && (healthPerc < 0.9f) && !unit->IsAttrNoRepair()) {
			circuit->GetBuilderManager()->Enqueue(TaskB::Repair(IBuilderTask::Priority::NOW, unit));
		}
		if (healthPerc < cdef->GetSelfDHP()) {
			unit->CmdSelfD(true);
		}
		return;
	} else if (healthPerc < 0.2f) {  // stuck units workaround: they don't shoot and don't see distant threat
		// SQUAD FIRST. Nearly every T1 unit's retreat bar sits at 8-15%, so
		// this blanket sub-0.2 branch intercepted the whole cheap army before
		// the vote below could run -- measured retreat-src stuck=26-33 with
		// squadStand=squadVote=homeStand=0 in every game of a 12-game A/B:
		// the solo-retreat deaths the collective disengage exists to prevent
		// were all coming from here. The workaround remains the fallback for
		// units the vote does not handle.
		if (TrySquadRetreat(unit)) {
			return;
		}
		++sRetreatSrc.stuck;
		LogRetreatSrc(circuit);
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
		return;
	}

	// The squad votes before anyone runs alone: measured, 40-45% of all lost
	// metal died on solo retreats. Below the wounded-fraction bar the unit
	// stands rear with its squad (the shipped coward mechanism); above it the
	// whole squad leaves together on one retreat task. Solo retreat remains
	// for units with no squad and for the stuck-unit workaround above.
	if (TrySquadRetreat(unit)) {
		return;
	}
	CThreatMap* threatMap = circuit->GetThreatMap();
	const float range = cdef->GetMaxRange();
	if ((target == nullptr) || !target->IsInLOS()) {
		++sRetreatSrc.los;
		LogRetreatSrc(circuit);
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
		return;
	}
	const AIFloat3& pos = unit->GetPos(frame);
	if ((target->GetPos().SqDistance2D(pos) > SQUARE(range)) ||
		(threatMap->GetThreatAt(unit, pos) * 2 > threatMap->GetUnitPower(unit)))
	{
		++sRetreatSrc.range;
		LogRetreatSrc(circuit);
		CRetreatTask* task = manager->EnqueueRetreat();
		manager->AssignTask(unit, task);
		return;
	}
	cowards.insert(unit);
}

// Standing still under fire eats every shot; a short sidestep perpendicular
// to the incoming fire makes slow projectiles (rockets, plasma) miss. The
// side alternates by unit id so a squad splits apart instead of piling onto
// one tile, and the distance scales with the unit's own speed -- a unit too
// slow to dodge barely moves. The move carries a timeout and the task's next
// update re-issues the attack, so the jink cannot strand anyone.
void IFighterTask::DodgeFire(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	CCircuitAI* circuit = manager->GetCircuit();
	if (circuit->GetTunable("apex_dodge", 1.f) <= 0.f) {
		return;
	}
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (!cdef->IsMobile() || cdef->IsAbleToFly()) {
		return;
	}
	const int frame = circuit->GetLastFrame();
	if (frame < unit->GetDodgeFrame()) {
		return;
	}
	const AIFloat3& pos = unit->GetPos(frame);
	AIFloat3 dir = unit->GetDamagedDir();  // toward the shooter
	if (attacker != nullptr) {
		const AIFloat3& ePos = attacker->GetPos();
		if (utils::is_valid(ePos)) {
			dir = ePos - pos;
		}
	}
	dir.y = 0.f;
	if (dir.SqLength2D() < 1.f) {
		return;  // no idea where the fire came from
	}
	dir.SafeNormalize2D();
	const float side = (unit->GetId() % 2 == 0) ? 1.f : -1.f;
	const AIFloat3 perp(-dir.z * side, 0.f, dir.x * side);
	const float dist = cdef->GetSpeed() * circuit->GetTunable("apex_dodge_sec", 0.75f);
	if (dist < 20.f) {
		return;
	}
	AIFloat3 dst = pos + perp * dist;
	CTerrainManager::CorrectPosition(dst);
	unit->NoteAct("DODGE", frame);
	unit->CmdMoveTo(dst, 0, frame + FRAMES_PER_SEC * 2);
	unit->SetDodgeFrame(frame + (int)(FRAMES_PER_SEC * circuit->GetTunable("apex_dodge_cd", 1.f)));
	IntentPing(dst, "DODGE");
}

// Range is money: a longer-ranged unit lets a shorter one close at its
// peril only if it BACKS UP. Hold ~95% of our own reach (apexearth's
// standing doctrine) whenever we outrange the shooter and it is inside
// that line -- a radial back-step with the dodge's lateral half folded in.
// Returns true when it moved (the dodge then skips this event).
bool IFighterTask::KeepRange(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	CCircuitAI* circuit = manager->GetCircuit();
	if (circuit->GetTunable("apex_standoff", 1.f) <= 0.f) {
		return false;
	}
	if ((attacker == nullptr) || (attacker->GetCircuitDef() == nullptr)) {
		return false;
	}
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (!cdef->IsMobile() || cdef->IsAbleToFly()) {
		return false;
	}
	const float myRange = cdef->GetMaxRange();
	if (myRange <= attacker->GetCircuitDef()->GetMaxRange() * 1.15f) {
		return false;  // no range advantage: dodge or charge instead
	}
	const int frame = circuit->GetLastFrame();
	if (frame < unit->GetDodgeFrame()) {
		return false;
	}
	const AIFloat3& ePos = attacker->GetPos();
	const AIFloat3& pos = unit->GetPos(frame);
	if (!utils::is_valid(ePos)) {
		return false;
	}
	const float hold = myRange * circuit->GetTunable("apex_standoff_frac", 0.95f);
	const float dist = pos.distance2D(ePos);
	if (dist >= hold) {
		return false;  // already at the line
	}
	AIFloat3 dir = pos - ePos;
	dir.y = 0.f;
	if (dir.SqLength2D() < 1.f) {
		return false;
	}
	dir.SafeNormalize2D();
	const float side = (unit->GetId() % 2 == 0) ? 1.f : -1.f;
	const AIFloat3 perp(-dir.z * side, 0.f, dir.x * side);
	AIFloat3 dst = ePos + dir * hold + perp * (cdef->GetSpeed() * 0.3f);
	CTerrainManager::CorrectPosition(dst);
	unit->NoteAct("STAND", frame);
	unit->CmdMoveTo(dst, 0, frame + FRAMES_PER_SEC * 2);
	unit->SetDodgeFrame(frame + (int)(FRAMES_PER_SEC
			* circuit->GetTunable("apex_dodge_cd", 1.f)));
	IntentPing(dst, "STANDOFF");
	return true;
}

// Standing in bombardment from a shooter we cannot answer from here is the
// worst state in the game: taking damage, dealing none (apexearth watched a
// held group absorb an artillery park). If the attacker OUTRANGES us and is
// reachable ground, charge it -- a unit-thought, throttled by the dodge
// cooldown's bigger sibling; ATTACK-type tasks keep their own targeting.
void IFighterTask::CounterBattery(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	CCircuitAI* circuit = manager->GetCircuit();
	if (circuit->GetTunable("apex_counter_battery", 1.f) <= 0.f) {
		return;
	}
	if ((attacker == nullptr) || (attacker->GetCircuitDef() == nullptr)) {
		return;
	}
	// MOBILE shooters only: charging a static emplacement is marching into
	// its kill zone (watched: the line walked face-first into Punishers it
	// could have shelled from outside). Statics are siege targets, not
	// charge targets.
	if (!attacker->GetCircuitDef()->IsMobile()) {
		return;
	}
	if (GetType() != Type::FIGHTER) {
		return;
	}
	// Only holding postures counter-charge; an attacking task is already busy.
	const FightType ft = GetFightType();
	if ((ft != FightType::DEFEND) && (ft != FightType::GUARD)
		&& (ft != FightType::RALLY))
	{
		return;
	}
	CCircuitDef* cdef = unit->GetCircuitDef();
	if (!cdef->IsMobile() || cdef->IsAbleToFly()) {
		return;
	}
	const int frame = circuit->GetLastFrame();
	if (frame < unit->GetDamagedFrame() + FRAMES_PER_SEC
			* (int)circuit->GetTunable("apex_counter_cd", 5.f)) {
		return;
	}
	const AIFloat3& ePos = attacker->GetPos();
	if (!utils::is_valid(ePos)) {
		return;
	}
	const AIFloat3& pos = unit->GetPos(frame);
	const float dist = pos.distance2D(ePos);
	// Charge only what OUTRANGES us (else our own attack handles it) and is
	// within a sprint (do not cross the map for one shell).
	if ((dist <= cdef->GetMaxRange() * 1.1f)
		|| (dist > cdef->GetSpeed() * circuit->GetTunable("apex_counter_sprint", 20.f))) {
		return;
	}
	unit->NoteAct("CHARGE", frame);
	unit->Attack(attacker, false, frame + FRAMES_PER_SEC * 30);
	unit->SetDamagedFrame(frame);
}

void IFighterTask::OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	RemoveAssignee(unit);
}

void IFighterTask::SetTarget(CEnemyInfo* enemy)
{
	if (target != nullptr) {
		target->UnbindTask(this);
	}
	if (enemy != nullptr) {
		enemy->BindTask(this);
	}
	target = enemy;
}

void IFighterTask::Attack(CCircuitUnit* unit, const int frame)
{
	AttackEnemy(unit, GetTarget(), frame);
}

// A standoff point is pushed out of the reach of every visible enemy this
// unit outranges, not only its target's (apexearth: "units like that should
// always want to keep a safe distance"). Enemies it does not outrange are
// the odds election's business; artillery is met, not kept from (docs/24).
AIFloat3 IFighterTask::SafeStandoff(CCircuitUnit* unit, const AIFloat3& want,
		const AIFloat3& tPos, const int frame) const
{
	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitDef* cdef = unit->GetCircuitDef();
	if ((circuit->GetTunable("apex_standoff", 1.f) <= 0.f) || cdef->IsAbleToFly()) {
		return want;
	}
	const float myRange = cdef->GetMaxRange();
	static constexpr float GROUP_SCAN = 1500.f;
	AIFloat3 pos = want;
	bool moved = false;
	for (int pass = 0; pass < 2; ++pass) {
		bool passMoved = false;
		for (const CEnemyManager::SEnemyGroup& g : circuit->GetEnemyManager()->GetEnemyGroups()) {
			if (g.pos.SqDistance2D(pos) > SQUARE(GROUP_SCAN)) {
				continue;
			}
			for (const ICoreUnit::Id eId : g.units) {
				CEnemyInfo* e = circuit->GetEnemyInfo(eId);
				if ((e == nullptr) || e->IsHidden() || !e->IsInRadarOrLOS()) {
					continue;
				}
				CCircuitDef* ed = e->GetCircuitDef();
				if ((ed == nullptr) || !ed->IsAttacker() || ed->IsAbleToFly() || ed->IsRoleArty()) {
					continue;
				}
				const float eRange = ed->GetMaxRange();
				if (myRange <= eRange * 1.15f) {
					continue;  // same bar as KeepRange: no range edge, not ours to kite
				}
				const float keep = eRange * OUTRANGED_SAFETY_MARGIN;
				const AIFloat3& ePos = e->GetPos();
				if (pos.SqDistance2D(ePos) >= SQUARE(keep)) {
					continue;
				}
				AIFloat3 dir = pos - ePos;
				dir.y = 0.f;
				if (dir.SqLength2D() < 1.f) {
					dir = pos - tPos;
					dir.y = 0.f;
					if (dir.SqLength2D() < 1.f) {
						continue;
					}
				}
				dir.SafeNormalize2D();
				pos = ePos + dir * keep;
				passMoved = true;
			}
		}
		if (!passMoved) {
			break;
		}
		moved = true;
	}
	if (moved) {
		CTerrainManager::CorrectPosition(pos);
		unit->NoteAct("SAFE", frame);
	}
	return pos;
}

// Where a moving target will be when we get there (apexearth: "we tend to
// chase directly towards the enemy instead of in the direction they're
// heading"). Capped so a far target is not led off the map.
static constexpr float STATIC_STANDOFF_SLACK = 20.f;  // elmos past a static target's reach

AIFloat3 IFighterTask::LeadPos(CCircuitUnit* unit, CEnemyInfo* enemy, const int frame) const
{
	static constexpr float LEAD_MAX_SEC = 6.f;
	AIFloat3 tPos = enemy->GetPos();
	CCircuitDef* edef = enemy->GetCircuitDef();
	if ((edef == nullptr) || !edef->IsMobile()) {
		return tPos;
	}
	const AIFloat3& vel = enemy->GetVel();  // elmos per frame
	const float spdF = unit->GetCircuitDef()->GetSpeed() / FRAMES_PER_SEC;
	if ((spdF < 0.01f) || (vel.SqLength2D() < 0.01f)) {
		return tPos;
	}
	float leadF = unit->GetPos(frame).distance2D(tPos) / spdF;
	leadF = std::min(leadF, FRAMES_PER_SEC * LEAD_MAX_SEC);
	tPos += vel * leadF;
	CTerrainManager::CorrectPosition(tPos);
	return tPos;
}

void IFighterTask::AttackEnemy(CCircuitUnit* unit, CEnemyInfo* enemy, const int frame)
{
	assert((unit->GetTravelAct() != nullptr) && (enemy != nullptr));

	if (unit->Blocker() != nullptr) {
		return;  // Do not interrupt current action
	}
	if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
		unit->GetTravelAct()->StateWait();
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3 tPos = LeadPos(unit, enemy, frame);
	const int targetTile = circuit->GetInflMap()->Pos2Index(tPos);
	const bool isRepeatAttack = (frame >= attackFrame + FRAMES_PER_SEC * 3);
	attackFrame = isRepeatAttack ? frame : attackFrame;

	if (!isRepeatAttack
		&& (unit->GetTarget() == enemy)
		&& (unit->GetTargetTile() == targetTile))
	{
		return;
	}

	CCircuitDef* cdef = unit->GetCircuitDef();
	AIFloat3 dir = unit->GetPos(frame) - tPos;
	if (cdef->IsPlane() || (std::fabs(dir.y) > cdef->GetMaxRange() * 0.5f)) {
		unit->Attack(enemy, enemy->GetUnit()->IsCloaked(), frame + FRAMES_PER_SEC * 60);
		return;
	}
	dir.Normalize2D();

	CCircuitDef* edef = enemy->GetCircuitDef();
	const bool isStatic = (edef != nullptr) && !edef->IsMobile();

	// Same fix as ISquadTask::AssignTo/RemoveAssignee (SquadTask.cpp): a
	// multi-weapon unit's GetMinRange() is its SHORTEST weapon's range, not
	// its real engagement distance. GetMaxRange() matches what the rest of
	// this codebase's combat logic already treats as "how close this unit
	// needs to get."
	//
	// The losRadius clamp only applies while the target cannot be seen: a gun
	// that outranges its own eyes must close to acquire, but once the target is
	// in radar or LOS there is nothing left to walk towards.
	const float rangeMod = circuit->GetTunable("apex_range_mod", STANDOFF_RANGE_MOD);
	const bool seesTarget = (circuit->GetTunable("apex_los_standoff", 1.f) > 0.f)
			&& !isStatic && enemy->IsInRadarOrLOS();
	// Same gap ISquadTask::Attack had before the 2026-08-14 outrange-margin fix
	// (SquadTask.cpp), but wider here: this path had no reference to the
	// target's own range AT ALL, so a lone/scout unit facing anything within
	// (or above) its own weapon range -- not just the 90-100% band -- shrunk
	// straight past its target's reach with nothing to stop it.
	// Artillery is met at our own range, never kept from at theirs (docs/24).
	const bool outranged = (edef != nullptr) && !edef->IsRoleArty()
			&& (edef->GetMaxRange() > cdef->GetMaxRange());
	float range = (outranged ? edef->GetMaxRange() * OUTRANGED_SAFETY_MARGIN : cdef->GetMaxRange()) * rangeMod;
	if (!outranged && (edef != nullptr)) {
		if (isStatic) {
			// Outside ITS reach, inside ours: 0.9x of a 475 rocket stood at 427
			// against a 435 turret (apexearth: "died to a T1 turret which it
			// outranges"), and the old 1.15x margin put it past its own gun.
			range = std::min(std::max(range, edef->GetMaxRange() + STATIC_STANDOFF_SLACK),
					cdef->GetMaxRange() * 0.98f);
		} else {
			range = std::max(range, edef->GetMaxRange() * OUTRANGED_SAFETY_MARGIN);
		}
	}
	if (!seesTarget) {
		range = std::min(range, cdef->GetLosRadius() * rangeMod);
	}
	AIFloat3 newPos(tPos.x + range * dir.x, tPos.y, tPos.z + range * dir.z);
	CTerrainManager::CorrectPosition(newPos);
	newPos = SafeStandoff(unit, newPos, tPos, frame);
	unit->Attack(newPos, enemy, targetTile, enemy->GetUnit()->IsCloaked(), isStatic, frame + FRAMES_PER_SEC * 60);
}

#ifdef DEBUG_VIS
void IFighterTask::Log()
{
	IUnitTask::Log();

	CCircuitAI* circuit = manager->GetCircuit();
	circuit->GetDrawer()->AddPoint(position, "position");
	circuit->LOG("fightType: %i | attackPower: %f | powerMod: %f", fightType, attackPower, powerMod);
	if (target != nullptr) {
		circuit->GetDrawer()->AddPoint(target->GetPos(), "target");
	}
}
#endif

} // namespace circuit
