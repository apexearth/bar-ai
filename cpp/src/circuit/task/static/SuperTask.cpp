/*
 * SuperTask.cpp
 *
 *  Created on: Aug 12, 2016
 *      Author: rlcevg
 */

#include "task/static/SuperTask.h"
#include "task/fighter/SquadTask.h"
#include "map/InfluenceMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/ally/AllyUnit.h"
#include "unit/CircuitDef.h"
#include "unit/CircuitUnit.h"
#include "unit/CircuitWDef.h"

#include "Damage.h"
#include "WeaponDef.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Log.h"
#include "Lua.h"

#include <algorithm>

namespace circuit {

using namespace springai;

#define TARGET_DELAY	(FRAMES_PER_SEC * 10)
// apex: fraction of a group's cost that must be STATIC before the group counts as
// a base rather than an army passing through neutral ground.
#define STATIC_SHARE	0.5f
// apex: how much a group's static content is worth relative to its raw cost when
// choosing between targets. A base does not move, cannot retreat out of the blast
// and does not rebuild in the ten seconds it takes the missile to land, so it is
// worth strictly more than an equal pile of units.
#define STATIC_WEIGHT	1.0f
// apex: metal of MOBILE enemy in one group that counts as "a huge mass of army".
#define ARMY_MASS_MIN	4000.f
// apex: how much a massed army standing on ground we hold is worth beyond its raw
// cost. Above 1.0 it outranks a base of equal metal, which is the point: the base
// will still be there next reload, the push will be inside us.
#define ARMY_MASS_WEIGHT	2.0f
// apex: multiple of our own metal inside the blast that the enemy mass must beat
// before we fire onto our own ground.
#define BLAST_TRADE	3.0f

static inline float MobileCost(const CEnemyManager::SEnemyGroup& group)
{
	return std::max(0.f, group.cost - group.roleCosts[ROLE_TYPE(STATIC)]);
}

// apex: a massed enemy army standing where our own influence reaches -- the push
// on our border. GetAllyInflAt is nonzero only within range of our own armed
// units and defences, so this is literally "they are on top of our line".
static inline bool IsBorderMass(const CEnemyManager::SEnemyGroup& group, CInfluenceMap* inflMap,
		float massMin)
{
	return (MobileCost(group) >= massMin)
		&& (inflMap->GetAllyInflAt(group.pos) > INFL_EPS);
}

// apex: score a candidate. Raw cost picks the biggest blob on the map; this tips
// the choice toward the densest STATIC target of comparable value, and above that
// toward an army massed on our own ground -- and above THAT, one massed at our
// base. apexearth: "when enemy armies are close to our base we should prioritize
// nuking the army (if they're big enough)" -- the base target keeps for the next
// reload, the army at the wall does not.
static inline float GroupScore(const CEnemyManager::SEnemyGroup& group, CInfluenceMap* inflMap,
		float massMin, const springai::AIFloat3& basePos, float sqHomeRange, float homeWeight)
{
	float score = group.cost + STATIC_WEIGHT * group.roleCosts[ROLE_TYPE(STATIC)];
	if (IsBorderMass(group, inflMap, massMin)) {
		float w = ARMY_MASS_WEIGHT;
		if (basePos.SqDistance2D(group.pos) < sqHomeRange) {
			w += homeWeight;
		}
		score += w * MobileCost(group);
	}
	return score;
}

// apex: our own metal standing inside the blast. Firing onto our own ground is
// only worth it as a trade, and the influence map cannot price one -- it carries
// range-weighted danger, not cost.
static float FriendlyCostIn(CCircuitAI* circuit, const AIFloat3& pos, float radius)
{
	circuit->UpdateFriendlyUnits();
	auto& units = circuit->GetCallback()->GetFriendlyUnitsIn(pos, radius);
	float cost = 0.f;
	for (Unit* u : units) {
		CAllyUnit* au = circuit->GetFriendlyUnit(u);
		if ((au != nullptr) && (au->GetCircuitDef() != nullptr)) {
			cost += au->GetCircuitDef()->GetCostM();
		}
	}
	utils::free(units);
	return cost;
}

CSuperTask::CSuperTask(ITaskModule* mgr)
		: IFighterTask(mgr, IFighterTask::FightType::SUPER, 1.f)
		, targetFrame(0)
		, targetPos(-RgtVector)
{
}

CSuperTask::~CSuperTask()
{
}

bool CSuperTask::CanAssignTo(CCircuitUnit* unit) const
{
	return false;
}

void CSuperTask::RemoveAssignee(CCircuitUnit* unit)
{
	IFighterTask::RemoveAssignee(unit);
	if (units.empty()) {
		manager->AbortTask(this);
	}
}

void CSuperTask::Start(CCircuitUnit* unit)
{
	const int frame = manager->GetCircuit()->GetLastFrame();
	targetFrame = frame - TARGET_DELAY;
	position = unit->GetPos(frame);
}

void CSuperTask::Update()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CCircuitUnit* unit = *units.begin();

	if (unit->Blocker() != nullptr) {
		return;  // Do not interrupt current action
	}

	CCircuitDef* cdef = unit->GetCircuitDef();
	// apex: STOCKPILE supers (nuke silos) belong to the Brain's nuke director
	// (script, brain/nukes.as): it saves volleys and sizes them against the
	// antinukes covering a target, which this per-group scorer cannot see.
	// Stockpiling itself continues (MilitaryManager's finished-handler orders
	// it); only the targeting is ceded. Non-stock supers (LRPC) stay here.
	if (cdef->IsAttrStock()) {
		if (launcher == Launcher::UNKNOWN) {
			CWeaponDef* cwd = cdef->GetWeaponDef();
			springai::WeaponDef* wd = (cwd != nullptr) ? cwd->GetDef() : nullptr;
			if ((wd == nullptr) || (wd->GetTargetable() != 0)) {
				launcher = Launcher::NUKE;
			} else if (wd->IsParalyzer()) {
				launcher = Launcher::EMP;
			} else {
				springai::Damage* damage = wd->GetDamage();
				const std::vector<float>& damages = damage->GetTypes();
				float most = 0.f;
				for (float v : damages) {
					most = std::max(most, v);
				}
				delete damage;
				// the Juno's kill is a gadget; its warhead does 1 damage
				launcher = (most <= 1.f) ? Launcher::JUNO : Launcher::TACTICAL;
				shotDmg = most;
			}
			if (wd != nullptr) {
				const std::map<std::string, std::string> params = wd->GetCustomParams();
				auto it = params.find("stockpilelimit");
				if (it != params.end()) {
					stockCap = std::max(1, utils::string_to_int(it->second));
				}
			}
		}
		if (launcher != Launcher::NUKE) {
			AimLauncher(unit, frame);
			return;
		}
		if (circuit->GetTunable("apex_brain_nuke", 1.f) > 0.f) {
			return;
		}
	}
	if (cdef->IsHoldFire()) {
		if (targetFrame + (cdef->GetReloadTime() + TARGET_DELAY) > frame) {
			if ((State::ENGAGE == state) && (targetFrame + TARGET_DELAY <= frame)) {
				TRY_UNIT(circuit, unit,
					unit->CmdStop();
				)
				state = State::ROAM;
			}
			return;
		}
	} else if (targetFrame + TARGET_DELAY > frame) {
		return;
	}

	// apex: a cannon shoots buildings, never units (apexearth 2026-09-30).
	if (!cdef->IsAttrStock()) {
		AimAtStructure(unit, frame);
		return;
	}

	CInfluenceMap* inflMap = circuit->GetInflMap();
	CMilitaryManager* militaryMgr = circuit->GetMilitaryManager();
	const float maxSqRange = SQUARE(cdef->GetMaxRange());
	const float sqAoe = SQUARE(cdef->GetAoe() * 1.25f);
	// apex: the army-priority knobs, tunable. homeRange bounds "close to our
	// base"; inside it the mass bonus grows by homeWeight.
	const float massMin = circuit->GetTunable("apex_nuke_army_min", ARMY_MASS_MIN);
	const float homeWeight = circuit->GetTunable("apex_nuke_home_weight", 4.f);
	const float blastTrade = circuit->GetTunable("apex_nuke_trade", BLAST_TRADE);
	const AIFloat3 basePos = circuit->GetSetupManager()->GetBasePos();
	const float sqHomeRange = SQUARE(militaryMgr->GetBaseDefRange() * 1.5f);
	float cost = 0.f;
	int groupIdx = -1;
	const std::array<const std::set<IFighterTask*>*, 3> avoidTasks = {  // NOTE: ISquadTask only
		&militaryMgr->GetTasks(IFighterTask::FightType::ATTACK),
		&militaryMgr->GetTasks(IFighterTask::FightType::AH),
		&militaryMgr->GetTasks(IFighterTask::FightType::AA),
	};
	// apex: an enemy ECONOMY is invisible to GetInfluenceAt. CInfluenceMap is built
	// only from hostile (armed) enemies -- InfluenceMap.cpp iterates
	// GetHostileDatas(), and MapManager.cpp puts anything failing IsAttacker() into
	// peaceUnits -- so mexes, fusions, labs, nanos and converters contribute zero.
	// The K-means groups DO include them (EnemyManager.cpp clusters peaceDatas too
	// and counts their cost), so an enemy base forms a high-cost group and was then
	// rejected here for not looking dangerous. Nuking a base is the whole point of
	// owning a silo.
	// Keep the real intent of the old test -- never fire onto ground WE hold -- and
	// otherwise accept a group that is worth hitting.
	const float staticShare = STATIC_SHARE;
	const float aoe = cdef->GetAoe();
	// apex: a huge enemy army standing on our own line used to be the one thing a
	// silo could never shoot -- any ally influence at all vetoed the group, and our
	// own squads defending that line sat inside the blast radius, vetoing it again.
	// Both vetoes are replaced for that case by a value trade: our metal in the
	// blast against theirs. Everything else keeps the old, stricter rules.
	auto isTargetValid = [&avoidTasks, frame, sqAoe, aoe, staticShare, inflMap, circuit,
			massMin, blastTrade](const CEnemyManager::SEnemyGroup& group) {
		const bool isMass = IsBorderMass(group, inflMap, massMin);
		if (!isMass && (inflMap->GetAllyInflAt(group.pos) > INFL_EPS)) {
			return false;
		}
		const float statCost = group.roleCosts[ROLE_TYPE(STATIC)];
		if (!isMass && (inflMap->GetInfluenceAt(group.pos) > -INFL_EPS)
			&& (statCost < group.cost * staticShare))
		{
			return false;  // not enemy ground, and not a base either
		}
		if (isMass) {
			const float ours = FriendlyCostIn(circuit, group.pos, aoe);
			if (MobileCost(group) < ours * blastTrade) {
				return false;  // too much of us standing in it
			}
		} else {
			for (const std::set<IFighterTask*>* tasks : avoidTasks) {
				for (const IFighterTask* task : *tasks) {
					const AIFloat3& leaderPos = static_cast<const ISquadTask*>(task)->GetLeaderPos(frame);
					if (leaderPos.SqDistance2D(group.pos) < sqAoe) {
						return false;
					}
				}
			}
		}
		for (const ICoreUnit::Id eId : group.units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if (enemy == nullptr) {
				continue;
			}
			CCircuitDef* edef = enemy->GetCircuitDef();
			// NOTE: groups are created by leader, ignore flags could be different
			if ((edef == nullptr) || !circuit->GetCircuitDef(edef->GetId())->IsIgnore()) {
				return true;
			}
		}
		return false;
	};

	const std::vector<CEnemyManager::SEnemyGroup>& groups = circuit->GetEnemyManager()->GetEnemyGroups();
	if (cdef->IsHoldFire() || (State::ROAM == state)) {
		for (unsigned i = 0; i < groups.size(); ++i) {
			const CEnemyManager::SEnemyGroup& group = groups[i];
			const float score = GroupScore(group, inflMap, massMin, basePos, sqHomeRange, homeWeight);
			if ((cost >= score) || (position.SqDistance2D(group.pos) >= maxSqRange)) {
				continue;
			}
			if (isTargetValid(group) && !militaryMgr->IsRecentSuperTarget(group.pos, sqAoe, frame)) {
				cost = score;
				groupIdx = i;
			}
		}
	} else {
		// TODO: Use WeaponDef::GetTurnRate() for turn-delay weight
		const AIFloat3& targetVec = (targetPos - position).Normalize2D();
		for (unsigned i = 0; i < groups.size(); ++i) {
			const CEnemyManager::SEnemyGroup& group = groups[i];
			if (position.SqDistance2D(group.pos) >= maxSqRange) {
				continue;
			}
			const AIFloat3& newVec = (group.pos - position).Normalize2D();
			const float angleMod = M_PI / (2.f * (std::acos(targetVec.dot2D(newVec)) + 1e-2f));
			const float score = GroupScore(group, inflMap, massMin, basePos, sqHomeRange, homeWeight) * angleMod;
			if (cost >= score) {
				continue;
			}
			if (isTargetValid(group) && !militaryMgr->IsRecentSuperTarget(group.pos, sqAoe, frame)) {
				cost = score;
				groupIdx = i;
			}
		}
	}
	const float maxCost = cdef->IsAttrStock() ? cdef->GetWeaponDef()->GetCostM() : cdef->GetCostM() * 0.01f;

	if ((groupIdx < 0) || (cost < maxCost)) {
		// apex: the silent case. Nothing qualified -- either every group failed the
		// validity test or the best was worth less than one warhead.
		circuit->LOG("apex: super idle %s stock=%i groups=%i best=%.0f need=%.0f",
				cdef->GetDef()->GetName(), unit->GetUnit()->GetStockpile(),
				(int)groups.size(), cost, maxCost);
		TRY_UNIT(circuit, unit,
			unit->CmdStop();
		)
		SetTarget(nullptr);
		targetFrame = frame;
		return;
	}

	const AIFloat3& grPos = groups[groupIdx].pos;
	CEnemyInfo* bestTarget = nullptr;
	if (cdef->IsAttrStock()) {
		float minSqDist = std::numeric_limits<float>::max();
		for (const ICoreUnit::Id eId : groups[groupIdx].units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if (enemy == nullptr) {
				continue;
			}
			CCircuitDef* edef = enemy->GetCircuitDef();
			// NOTE: groups are created by leader, ignore flags could be different
			if ((edef != nullptr) && circuit->GetCircuitDef(edef->GetId())->IsIgnore()) {
				continue;
			}
			const float sqDist = grPos.SqDistance2D(enemy->GetPos());
			if ((minSqDist > sqDist) && (position.SqDistance2D(enemy->GetPos()) < maxSqRange)) {
				minSqDist = sqDist;
				bestTarget = enemy;
			}
		}
	} else {
		float maxCost = 0.f;
		for (const ICoreUnit::Id eId : groups[groupIdx].units) {
			CEnemyInfo* enemy = circuit->GetEnemyInfo(eId);
			if (enemy == nullptr) {
				continue;
			}
			CCircuitDef* edef = enemy->GetCircuitDef();
			// NOTE: groups are created by leader, ignore flags could be different
			if ((edef != nullptr) && circuit->GetCircuitDef(edef->GetId())->IsIgnore()) {
				continue;
			}
			if ((maxCost < enemy->GetCost()) && (position.SqDistance2D(enemy->GetPos()) < maxSqRange)) {
				maxCost = enemy->GetCost();
				bestTarget = enemy;
			}
		}
	}
	SetTarget(bestTarget);
	if (GetTarget() != nullptr) {
		targetPos = GetTarget()->GetPos();
		targetPos.y = circuit->GetMap()->GetElevationAt(targetPos.x, targetPos.z);

		// apex: claim this ground before any other silo evaluates it.
		militaryMgr->NoteSuperTarget(targetPos, frame);
		// apex: CSuperTask logged nothing at all, so a silo that never fired was
		// indistinguishable from one with no target -- the reason this needed
		// reading the engine rather than grepping a log.
		const CEnemyManager::SEnemyGroup& chosen = groups[groupIdx];
		circuit->LOG("apex: super fire %s stock=%i score=%.0f cost=%.0f static=%.0f mobile=%.0f border=%i at (%.0f,%.0f)",
				cdef->GetDef()->GetName(), unit->GetUnit()->GetStockpile(), cost, chosen.cost,
				chosen.roleCosts[ROLE_TYPE(STATIC)], MobileCost(chosen),
				IsBorderMass(chosen, inflMap, massMin) ? 1 : 0, targetPos.x, targetPos.z);

		std::string cmd = (!cdef->IsAttrStock() || (unit->GetUnit()->GetStockpile() > 0)) ? "ai_super_fire:" : "ai_super_intention:";
		cmd += utils::int_to_string(unit->GetId()) + "/" + utils::int_to_string(targetPos.x) + "/" + utils::int_to_string(targetPos.z);
		circuit->GetLua()->CallRules(cmd.c_str(), cmd.size());

		TRY_UNIT(circuit, unit,
			if (GetTarget()->IsInRadarOrLOS() && !circuit->IsCheating()) {
				unit->GetUnit()->Attack(GetTarget()->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			} else {
				unit->CmdAttackGround(targetPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			}
		)
		targetFrame = frame;
		state = State::ENGAGE;
	}
}

// apex: a shield is worth the structures under it, because every shell aimed at
// them lands on it first.
void CSuperTask::AimAtStructure(CCircuitUnit* unit, int frame)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitDef* cdef = unit->GetCircuitDef();
	const float maxSqRange = SQUARE(cdef->GetMaxRange());
	targetFrame = frame;

	auto isStructure = [circuit](CEnemyInfo* e) {
		CCircuitDef* edef = e->GetCircuitDef();
		return (edef != nullptr) && !edef->IsMobile() && !e->IsHidden()
			&& !circuit->GetCircuitDef(edef->GetId())->IsIgnore();
	};

	CEnemyInfo* keep = GetTarget();
	if ((keep != nullptr) && isStructure(keep) && (position.SqDistance2D(keep->GetPos()) < maxSqRange)) {
		if (frame < orderFrame + FRAMES_PER_SEC * 50) {
			return;  // the order stands; a turret re-aimed mid-volley wastes the volley
		}
	} else {
		keep = nullptr;
	}

	std::vector<CEnemyInfo*> structs;
	std::vector<std::pair<float, CEnemyInfo*>> cands;
	for (auto& kv : circuit->GetEnemyInfos()) {
		if (isStructure(kv.second)) {
			structs.push_back(kv.second);
		}
	}
	CEnemyInfo* best = keep;
	float bestCover = 0.f;
	if (best == nullptr) {
		for (CEnemyInfo* e : structs) {
			if (position.SqDistance2D(e->GetPos()) >= maxSqRange) {
				continue;
			}
			float score = e->GetCost();
			const float r = e->GetCircuitDef()->GetShieldRadius();
			if (e->GetCircuitDef()->IsShieldDef() && (r > 0.f)) {
				const float sqR = SQUARE(r);
				for (CEnemyInfo* o : structs) {
					if ((o != e) && (e->GetPos().SqDistance2D(o->GetPos()) < sqR)) {
						score += o->GetCost();
					}
				}
			}
			cands.push_back(std::make_pair(score, e));
		}
		std::sort(cands.begin(), cands.end(), [](const std::pair<float, CEnemyInfo*>& a,
				const std::pair<float, CEnemyInfo*>& b) { return a.first > b.first; });
		const float aoe = cdef->GetAoe() * 1.25f;
		for (unsigned i = 0; (i < cands.size()) && (i < 4); ++i) {
			if (FriendlyCostIn(circuit, cands[i].second->GetPos(), aoe) <= 0.f) {
				best = cands[i].second;
				bestCover = cands[i].first - best->GetCost();
				break;
			}
		}
	}

	if (best == nullptr) {
		if (GetTarget() != nullptr || State::ENGAGE == state) {
			circuit->LOG("apex: lrpc idle %s structs=%i inRange=%i",
					cdef->GetDef()->GetName(), (int)structs.size(), (int)cands.size());
			TRY_UNIT(circuit, unit,
				unit->CmdStop();
			)
			SetTarget(nullptr);
			state = State::ROAM;
		}
		return;
	}

	const bool kept = (best == keep);
	SetTarget(best);
	targetPos = best->GetPos();
	targetPos.y = circuit->GetMap()->GetElevationAt(targetPos.x, targetPos.z);
	circuit->LOG("apex: lrpc aim %s -> %s cost=%.0f cover=%.0f shield=%i keep=%i structs=%i inRange=%i at (%.0f,%.0f)",
			cdef->GetDef()->GetName(), best->GetCircuitDef()->GetDef()->GetName(), best->GetCost(),
			bestCover, best->GetCircuitDef()->IsShieldDef() ? 1 : 0, kept ? 1 : 0,
			(int)structs.size(), (int)cands.size(), targetPos.x, targetPos.z);
	TRY_UNIT(circuit, unit,
		if (best->IsInRadarOrLOS() && !circuit->IsCheating()) {
			unit->GetUnit()->Attack(best->GetUnit(), UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		} else {
			unit->CmdAttackGround(targetPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		}
	)
	orderFrame = frame;
	state = State::ENGAGE;
}

// apex: what the Juno kills is a name list in unit_juno_damage.lua, not a stat:
// an advanced air plant carries a radar and took five Junos (his Glacier 2v2).
static bool IsJunoKill(const std::string& name)
{
	static const char* const kills[] = {
		"armarad", "armaser", "armason", "armeyes", "armfrad", "armjam", "armjamt", "armmark",
		"armrad", "armseer", "armsjam", "armsonar", "armveil", "corarad", "corason", "coreter",
		"coreyes", "corfrad", "corjamt", "corrad", "legjam", "legrad", "corshroud", "corsjam",
		"corsonar", "corspec", "corvoyr", "corvrad", "legarad", "legajam", "legavrad", "legavjam",
		"legaradk", "legajamk", "legfrad",
		"armmine1", "armmine2", "armmine3", "armfmine3", "cormine1", "cormine2", "cormine3",
		"cormine4", "corfmine3", "legmine1", "legmine2", "legmine3"};
	for (const char* k : kills) {
		if (name == k) {
			return true;
		}
	}
	return false;
}

// apex: tactical and EMP launchers go at the turrets, the Juno at radar and
// jammers (apexearth 2026-09-30). A paralysis wears off, so an EMP is spent only
// where one of our squads is inside the turret's reach or about to be.
void CSuperTask::AimLauncher(CCircuitUnit* unit, int frame)
{
	if (targetFrame + TARGET_DELAY > frame) {
		return;
	}
	targetFrame = frame;
	CCircuitAI* circuit = manager->GetCircuit();
	CCircuitDef* cdef = unit->GetCircuitDef();
	const int stock = unit->GetUnit()->GetStockpile();
	if (stock <= 0) {
		if (frame >= orderFrame + FRAMES_PER_SEC * 60) {
			orderFrame = frame;
			circuit->LOG("apex: launch wait %s stock=0", cdef->GetDef()->GetName());
		}
		return;
	}
	CMilitaryManager* militaryMgr = circuit->GetMilitaryManager();
	const float maxSqRange = SQUARE(cdef->GetMaxRange());
	const float aoe = std::max(cdef->GetAoe(), 64.f);
	const float sqAoe = SQUARE(aoe);

	std::vector<CEnemyInfo*> pool;
	for (auto& kv : circuit->GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		CCircuitDef* edef = e->GetCircuitDef();
		if ((edef == nullptr) || e->IsHidden() || circuit->GetCircuitDef(edef->GetId())->IsIgnore()
			|| (position.SqDistance2D(e->GetPos()) >= maxSqRange))
		{
			continue;
		}
		bool want;
		if (launcher == Launcher::JUNO) {
			want = IsJunoKill(edef->GetDef()->GetName());
		} else {
			want = !edef->IsMobile() && edef->IsAttacker();
		}
		if (want) {
			pool.push_back(e);
		}
	}

	std::vector<std::pair<AIFloat3, float>> squads;
	if (launcher == Launcher::EMP) {
		for (IFighterTask::FightType ft : {IFighterTask::FightType::ATTACK, IFighterTask::FightType::AH}) {
			for (const IFighterTask* task : militaryMgr->GetTasks(ft)) {
				const ISquadTask* sq = static_cast<const ISquadTask*>(task);
				if (sq->GetLeader() == nullptr) {
					continue;
				}
				squads.push_back(std::make_pair(sq->GetLeaderPos(frame),
						sq->GetLeader()->GetCircuitDef()->GetMaxRange()));
			}
		}
	}

	// CWeaponDef prices a stockpile weapon per second of stocking; a missile is
	// that times the stock time, its energy at the converter rate (60 E per M)
	float shotM = 0.f;
	if (CWeaponDef* cwd = cdef->GetWeaponDef()) {
		const float stockS = cwd->GetDef()->GetStockpileTime() / FRAMES_PER_SEC;
		shotM = (cwd->GetCostM() + cwd->GetCostE() / 60.f) * stockS;
	}
	// missiles in the silo are paid for; a growing stock lowers the bar
	const float bar = shotM / stock;

	// apex: a missile that cannot kill its target alone goes as a volley that
	// can (apexearth 2026-09-30). Targets are ranked on value per missile; the
	// best one waits for its volley while the stock is still growing.
	auto missilesFor = [this](CEnemyInfo* e) {
		if ((launcher != Launcher::TACTICAL) || (shotDmg <= 0.f)) {
			return 1;
		}
		const float hp = (e->GetHealth() > 0.f) ? e->GetHealth() : e->GetCircuitDef()->GetHealth();
		return std::max(1, (int)std::ceil(hp / shotDmg));
	};
	CEnemyInfo* best = nullptr;
	CEnemyInfo* bestNow = nullptr;
	float bestScore = 0.f, bestPer = 0.f, nowScore = 0.f, nowPer = 0.f;
	int bestNeed = 1, nowNeed = 1;
	for (CEnemyInfo* c : pool) {
		const AIFloat3& cp = c->GetPos();
		if (launcher == Launcher::EMP) {
			const float reach = c->GetCircuitDef()->GetMaxRange();
			bool engaged = false;
			for (auto& sq : squads) {
				if (sq.first.SqDistance2D(cp) <= SQUARE(reach + sq.second)) {
					engaged = true;
					break;
				}
			}
			if (!engaged) {
				continue;
			}
		}
		float score = 0.f;
		for (CEnemyInfo* o : pool) {
			if (cp.SqDistance2D(o->GetPos()) < sqAoe) {
				score += o->GetCost();
			}
		}
		const int need = missilesFor(c);
		if ((need > stockCap) || (score < bar * need)
			|| militaryMgr->IsRecentSuperTarget(cp, sqAoe, frame)
			|| (FriendlyCostIn(circuit, cp, aoe * 1.25f) > 0.f))
		{
			continue;
		}
		const float per = score / need;
		if (per > bestPer) {
			bestPer = per;
			bestScore = score;
			bestNeed = need;
			best = c;
		}
		if ((need <= stock) && (per > nowPer)) {
			nowPer = per;
			nowScore = score;
			nowNeed = need;
			bestNow = c;
		}
	}
	const char* kind = (launcher == Launcher::JUNO) ? "juno" : (launcher == Launcher::EMP) ? "emp" : "tactical";
	if ((best != nullptr) && (bestNeed > stock) && (stock < stockCap)) {
		if (frame >= orderFrame + FRAMES_PER_SEC * 60) {
			orderFrame = frame;
			circuit->LOG("apex: launch saving %s %s for %s need=%i stock=%i/%i",
					kind, cdef->GetDef()->GetName(), best->GetCircuitDef()->GetDef()->GetName(),
					bestNeed, stock, stockCap);
		}
		return;
	}
	if ((best == nullptr) || (bestNeed > stock)) {
		best = bestNow;
		bestScore = nowScore;
		bestNeed = nowNeed;
	}
	if (best == nullptr) {
		if (frame < orderFrame + FRAMES_PER_SEC * 60) {
			return;
		}
		orderFrame = frame;
		circuit->LOG("apex: launch idle %s %s stock=%i pool=%i squads=%i bar=%.0f",
				kind, cdef->GetDef()->GetName(), stock, (int)pool.size(), (int)squads.size(), bar);
		return;
	}
	AIFloat3 at = best->GetPos();
	at.y = circuit->GetMap()->GetElevationAt(at.x, at.z);
	militaryMgr->NoteSuperTarget(at, frame);
	circuit->LOG("apex: launch %s %s -> %s score=%.0f need=%i bar=%.0f stock=%i pool=%i at (%.0f,%.0f)",
			kind, cdef->GetDef()->GetName(), best->GetCircuitDef()->GetDef()->GetName(),
			bestScore, bestNeed, bar, stock, (int)pool.size(), at.x, at.z);
	// the order lasts the volley: held longer it empties the stock onto one spot
	const int reload = std::max(cdef->GetReloadTime(), FRAMES_PER_SEC / 2);
	const int timeout = frame + reload * bestNeed - reload / 2;
	TRY_UNIT(circuit, unit,
		unit->CmdAttackGround(at, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, timeout);
	)
}

} // namespace circuit
