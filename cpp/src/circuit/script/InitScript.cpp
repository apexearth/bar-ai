/*
 * InitScript.cpp
 *
 *  Created on: May 13, 2020
 *      Author: rlcevg
 */

#include "script/InitScript.h"
#include "script/SetupScript.h"
#include "script/ScriptManager.h"
#include "script/RefCounter.h"
#include "map/ThreatMap.h"
#include "map/MapManager.h"
#include "scheduler/Scheduler.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "task/builder/BuilderTask.h"
#include "task/fighter/FighterTask.h"
#include "unit/CircuitUnit.h"
#include "unit/action/DGunAction.h"
#include "CircuitAI.h"
#include "util/GameAttribute.h"
#include "util/MaskHandler.h"
#include "util/Utils.h"

#include "angelscript/include/angelscript.h"
#include "angelscript/add_on/scriptarray/scriptarray.h"
#include "angelscript/add_on/scriptdictionary/scriptdictionary.h"
// FIXME: MinGW didn't like asbind20
//#include "asbind20/asbind.hpp"
//#include "asbind20/operators.hpp"  // _this, const_this, param<T>, ->return<T>()

#include "spring/SpringMap.h"

#include "Log.h"
#include "Drawer.h"
#include "Game.h"
#include "Team.h"
#include "Lua.h"
#include "AISCommands.h"  // UNIT_COMMAND_OPTION_*, used by CmdBuildUnit below
#include "Command.h"       // springai::Command, for reading a unit's own queue

#include <chrono>          // apex: script-time accounting in Update()
#include <algorithm>
#include "Sim/Units/CommandAI/Command.h"  // CMD_INSERT

namespace circuit {

using namespace springai;

asITypeInfo* gUnitArrayType;  // cache

CInitScript::SInitInfo::SInitInfo(const SInitInfo& o)
{
	armor = o.armor;
	category = o.category;
	if (profile != nullptr) {
		profile->Release();
	}
	profile = o.profile;
	if (profile != nullptr) {
		profile->AddRef();
	}
}

CInitScript::SInitInfo::~SInitInfo()
{
	if (profile != nullptr) {
		profile->Release();
	}
}

static void AddAirArmor(CCircuitDef::SArmorInfo* mem, int type)
{
	mem->airTypes.push_back(type);
}

static void AddSurfaceArmor(CCircuitDef::SArmorInfo* mem, int type)
{
	mem->surfTypes.push_back(type);
}

static void AddWaterArmor(CCircuitDef::SArmorInfo* mem, int type)
{
	mem->waterTypes.push_back(type);
}

static void ConstructVec3(float3* mem)
{
	new(mem) float3();
}

static void ConstructCopyVec3(AIFloat3* mem, const AIFloat3& o)
{
	new(mem) float3(o);
}

static void ConstructVec3Val1(float3* mem, float a)
{
	new(mem) float3(a);
}

static void ConstructVec3Val3(float3* mem, float x, float y, float z)
{
	new(mem) float3(x, y, z);
}

static std::string ConvertVec3ToStr(const float3& f)
{
	return f.str();  // static_cast<const AIFloat3&>(f).ToString();
}

static void ConstructSArmorInfo(CCircuitDef::SArmorInfo* mem)
{
	new(mem) CCircuitDef::SArmorInfo();
}

static void ConstructCopySArmorInfo(CCircuitDef::SArmorInfo* mem, const CCircuitDef::SArmorInfo& o)
{
	new(mem) CCircuitDef::SArmorInfo(o);
}

static void DestructSArmorInfo(CCircuitDef::SArmorInfo *mem)
{
	mem->~SArmorInfo();
}

static CCircuitDef::SArmorInfo& AssignSArmorInfoToSArmorInfo(CCircuitDef::SArmorInfo& mem, const CCircuitDef::SArmorInfo& o)
{
	mem = o;
	return mem;
}

static void ConstructSCategoryInfo(CInitScript::SInitInfo::SCategoryInfo* mem)
{
	new(mem) CInitScript::SInitInfo::SCategoryInfo();
}

static void ConstructCopySCategoryInfo(CInitScript::SInitInfo::SCategoryInfo* mem, const CInitScript::SInitInfo::SCategoryInfo& o)
{
	new(mem) CInitScript::SInitInfo::SCategoryInfo(o);
}

static void DestructSCategoryInfo(CInitScript::SInitInfo::SCategoryInfo *mem)
{
	mem->~SCategoryInfo();
}

static CInitScript::SInitInfo::SCategoryInfo& AssignSCategoryInfoToSCategoryInfo(CInitScript::SInitInfo::SCategoryInfo& mem, const CInitScript::SInitInfo::SCategoryInfo& o)
{
	mem = o;
	return mem;
}

static void ConstructSInitInfo(CInitScript::SInitInfo* mem)
{
	new(mem) CInitScript::SInitInfo();
}

static void ConstructCopySInitInfo(CInitScript::SInitInfo* mem, const CInitScript::SInitInfo& o)
{
	new(mem) CInitScript::SInitInfo(o);
}

static void DestructSInitInfo(CInitScript::SInitInfo *mem)
{
	mem->~SInitInfo();
}

static CCircuitDef* CCircuitAI_GetCircuitDef(CCircuitAI* circuit, const std::string& name)
{
	return circuit->GetCircuitDef(name.c_str());
}

static std::string CCircuitAI_GetMapName(CCircuitAI* circuit)
{
	return circuit->GetMap()->GetName();
}

// The engine's Pos2BuildPos snap (GameHelper.cpp): every building lands on the
// 16-elmo build grid, with a half-square offset when the footprint size has
// bit 2 set, so EDGES always meet the grid. Script placement math computes
// intent in raw elmos; snapping the intent with the same rule keeps rows and
// walkway gaps exact for every footprint instead of drifting +-8 per def.
// apexearth: "can we try to ensure that we place it on a floored 2 mod grid
// of the map? ... this is for any buildings."
static springai::AIFloat3 CCircuitAI_SnapBuildPos(CCircuitAI* circuit, CCircuitDef* cdef, const springai::AIFloat3& pos)
{
	if (cdef == nullptr) {
		return pos;
	}
	constexpr float BUILD_SQ = SQUARE_SIZE * 2;
	springai::AIFloat3 out = pos;
	if (cdef->GetDef()->GetXSize() & 2) {
		out.x = std::floor(pos.x / BUILD_SQ) * BUILD_SQ + SQUARE_SIZE;
	} else {
		out.x = std::floor((pos.x + SQUARE_SIZE) / BUILD_SQ) * BUILD_SQ;
	}
	if (cdef->GetDef()->GetZSize() & 2) {
		out.z = std::floor(pos.z / BUILD_SQ) * BUILD_SQ + SQUARE_SIZE;
	} else {
		out.z = std::floor((pos.z + SQUARE_SIZE) / BUILD_SQ) * BUILD_SQ;
	}
	return out;
}

// THE UNIT LIMIT, AND WHAT WE HAVE SPENT OF IT.
//
// apexearth, on how a quota should be sized: "Take a look at your unit limit and
// divvy up your quota based on something reasonable. Let's say you have 100
// buildings, 2000 unit limit, you're in T1... then your split is on 1900
// available units."
//
// THE PER-TEAM LIMIT IS Unit_getLimit, AND IT WORKS. The comment that used to
// sit here said it "must not be used" because it indexes AI_TEAM_IDS, "the array
// declared `= {{-1}}` and never assigned". That is false in this engine:
// SSkirmishAICallbackImpl.cpp:5535 assigns
// `AI_TEAM_IDS[ai->GetSkirmishAIID()] = ai->GetTeamId()` for every AI, and
// skirmishAiCallback_Unit_getLimit:3305 is then
// `teamHandler.Team(AI_TEAM_IDS[id])->GetMaxUnits()` -- the real per-team number.
//
// Unit_getMax is the one that is wrong for this job: it returns
// unitHandler.MaxUnits(), the WHOLE MAP's cap, which is
// min(maxUnitsPerTeam * activeTeams, MAX_UNITS). Sizing a quota on it targeted
// twenty thousand raiders per bot lab.
//
// The value comes from `GAME\ModOptions\MaxUnits`. BAR's modoptions.lua declares
// it "Max Units Per Player" with def 2000, min 500, max 32000 -- so it is a real
// per-player budget that a host can change, which is what the quota divides up.
static int CCircuitAI_GetUnitLimit(CCircuitAI* circuit)
{
	// Both callbacks ignore the unit they are asked through, so any unit of ours
	// answers; borrowing one avoids constructing a wrapper for an id that may not
	// exist yet.
	for (const auto& kv : circuit->GetTeamUnits()) {
		if ((kv.second != nullptr) && (kv.second->GetUnit() != nullptr)) {
			return kv.second->GetUnit()->GetLimit();
		}
	}
	return 0;
}

static int CCircuitAI_GetUnitMax(CCircuitAI* circuit)
{
	for (const auto& kv : circuit->GetTeamUnits()) {
		if ((kv.second != nullptr) && (kv.second->GetUnit() != nullptr)) {
			return kv.second->GetUnit()->GetMax();
		}
	}
	return 0;
}

// How many units we hold, and how many of those are buildings. The split is what
// makes "slots left for army" a real number rather than a guess.
static int CCircuitAI_GetTeamUnitCount(CCircuitAI* circuit, bool staticOnly)
{
	int n = 0;
	for (const auto& kv : circuit->GetTeamUnits()) {
		const CCircuitUnit* u = kv.second;
		if ((u == nullptr) || (u->GetCircuitDef() == nullptr)) {
			continue;
		}
		if (!staticOnly || !u->GetCircuitDef()->IsMobile()) {
			++n;
		}
	}
	return n;
}

// Put a build order at the FRONT of a factory's queue without disturbing what is
// already on it -- the same CMD_INSERT the Quota Mode widget uses. CmdBuild can
// only append (SHIFT) or replace (no options), and replacing takes the unit under
// construction with it.
//
// Position 1 rather than 0 leaves whatever is being built alone; the widget does
// the same, and only drops to 0 when nothing is in progress.
static void CCircuitUnit_CmdInsertBuild(CCircuitUnit* unit, CCircuitDef* buildDef,
		bool front)
{
	if (buildDef == nullptr) {
		return;
	}
	std::vector<float> params = {
		front ? 0.f : 1.f,
		float(-buildDef->GetId()),
		float(UNIT_COMMAND_OPTION_ALT_KEY | UNIT_COMMAND_OPTION_INTERNAL_ORDER)
	};
	// TRY_UNIT needs a CCircuitAI to report a dead unit to, and ITaskModule is an
	// incomplete type in this translation unit, so the same guard is inline.
	try {
		unit->GetUnit()->ExecuteCustomCommand(CMD_INSERT, std::move(params),
				UNIT_COMMAND_OPTION_ALT_KEY | UNIT_COMMAND_OPTION_CONTROL_KEY);
	} catch (const std::exception& e) {
	}
}

static int CCircuitAI_GetLeadTeamId(CCircuitAI* circuit)
{
	return circuit->GetAllyTeam()->GetLeaderId();
}

static CScriptArray* CCircuitAI_GetTeamIds(CCircuitAI* circuit)
{
	// The type info MUST come from the calling instance's own engine: a
	// DLL-global cache held whichever engine registered LAST, so every other
	// instance built arrays with a foreign engine's type -- cross-engine heap
	// corruption that crashed at commander-blast allocation storms once a
	// caller ran hot (2026-08-18, seeds 121/123/127/130/131/132).
	asITypeInfo* idArrayType =
			asGetActiveContext()->GetEngine()->GetTypeInfoByDecl("array<Id>");
	CAllyTeam* allyTeam = circuit->GetAllyTeam();
	CScriptArray* arr = CScriptArray::Create(idArrayType, allyTeam->GetSize());
	asUINT i = 0;
	for (CAllyTeam::Id teamId : allyTeam->GetTeamIds()) {
		*(CAllyTeam::Id*)arr->At(i++) = teamId;
	}
	return arr;
}

static void CCircuitAI_GiveUnits(CCircuitAI* circuit, const CScriptArray* array, int newTeamId)
{
	std::vector<CCircuitUnit*> units;
	units.reserve(array->GetSize());
	for (asUINT i = 0; i < array->GetSize(); ++i) {
		units.push_back(*static_cast<CCircuitUnit* const*>(array->At(i)));
	}
	circuit->GiveUnits(std::move(units), newTeamId);
}

static void CCircuitUnit_CmdMoveTo(CCircuitUnit* unit, const AIFloat3& pos)
{
	unit->CmdMoveTo(pos);
}

// apex: the Brain's nuke director. Attack-ground is a netted order (safe);
// stockpile is an engine read on the host's own unit (safe).
static void CCircuitUnit_CmdAttackGround(CCircuitUnit* unit, const AIFloat3& pos)
{
	unit->CmdAttackGround(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY);
}

static void CCircuitUnit_CmdStop(CCircuitUnit* unit)
{
	try {
		unit->CmdStop();
	} catch (const std::exception& e) {
	}
}

// apex: standing patrol for construction turrets -- the engine's builder AI
// then assists/repairs/reclaims in range with no per-frame script election.
static void CCircuitUnit_CmdPatrolTo(CCircuitUnit* unit, const AIFloat3& pos)
{
	try {
		unit->CmdPatrolTo(pos);
	} catch (const std::exception& e) {
	}
}

// apex: enemy AIR value near a point, for the team interceptor pool -- each
// player publishes this at home and fighters fly to the worst-hit ally.
// Registry walk, called ~once per second per player.
static float CCircuitAI_GetEnemyAirCostNear(CCircuitAI* circuit, const springai::AIFloat3& pos, float radius)
{
	return circuit->GetEnemyManager()->GetEnemyAirCostNear(pos, radius);
}

static int CCircuitUnit_GetStockpile(CCircuitUnit* unit)
{
	// Same inline guard as CCircuitUnit_CmdPriorityBuild above: TRY_UNIT wants
	// a CCircuitAI and this wrapper has no clean path to one.
	try {
		return unit->GetUnit()->GetStockpile();
	} catch (const std::exception& e) {
	}
	return 0;
}

// apex: what we witnessed makes knowledge. Marks every REMEMBERED (currently
// unsensed) enemy within radius as hidden -- the same flag the LOS purge
// (CMapManager::HostileInLOS) sets when scouted ground shows nothing there.
// Used by the nuke director at a confirmed impact; a unit actually in radar
// or LOS is untouched. Host-local bookkeeping only.
static int CCircuitAI_ForgetEnemiesNear(CCircuitAI* circuit, const AIFloat3& pos, float radius)
{
	int n = 0;
	const float sqR = radius * radius;
	CMapManager* mapMgr = circuit->GetMapManager();
	for (const auto& units : {mapMgr->GetHostileUnits(), mapMgr->GetPeaceUnits()}) {
		for (const auto& kv : units) {
			CEnemyUnit* e = kv.second;
			if ((e == nullptr) || e->IsHidden() || !e->NotInRadarAndLOS()) {
				continue;
			}
			if (e->GetPos().SqDistance2D(pos) < sqR) {
				e->SetHidden();
				++n;
			}
		}
	}
	return n;
}

// apex: can a unit of this def WALK from `from` to `to`? The island question
// ("do not build land army when alone on an island") is exactly this asked
// about the T1 tank def from home to the enemy. Uses the terrain analysis's
// own connected-area model: the area under `from` for this def's move type,
// then CanMoveToPos to `to`. Immobile or flying defs answer true (they are
// not walled by water).
static bool CCircuitAI_CanDefReach(CCircuitAI* circuit, CCircuitDef* cdef,
		const AIFloat3& from, const AIFloat3& to)
{
	if (cdef == nullptr) {
		return false;
	}
	const int mtId = cdef->GetMobileId();
	if (mtId < 0) {
		return true;
	}
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	terrain::SAreaData* areaData = terrainMgr->GetAreaData();
	if ((areaData == nullptr) || (mtId >= (int)areaData->mobileType.size())) {
		return false;
	}
	const int si = terrainMgr->GetSectorIndex(from);
	terrain::SMobileType& mt = areaData->mobileType[mtId];
	if ((si < 0) || (si >= (int)mt.sector.size())) {
		return false;
	}
	terrain::SArea* area = mt.sector[si].area;
	if (area == nullptr) {
		return false;
	}
	return terrainMgr->CanMoveToPos(area, to);
}

// apex: how many of a given enemy def stand within radius of pos -- the
// "count the antinukes covering this spot" primitive, generic on purpose.
static int CCircuitAI_CountEnemyDefNear(CCircuitAI* circuit, int defId,
		const AIFloat3& pos, float radius)
{
	int n = 0;
	const float sqR = radius * radius;
	for (const auto& kv : circuit->GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		if ((e == nullptr) || e->IsHidden()) {
			continue;
		}
		CCircuitDef* edef = e->GetCircuitDef();
		if ((edef != nullptr) && (edef->GetId() == defId)
			&& (e->GetPos().SqDistance2D(pos) < sqR))
		{
			++n;
		}
	}
	return n;
}

// apex: the enemy cluster model, read-only. Index bounds-checked because the
// group vector changes between updates.
static int CEnemyManager_GetEnemyGroupCount(CEnemyManager* mgr)
{
	return (int)mgr->GetEnemyGroups().size();
}

static AIFloat3 CEnemyManager_GetEnemyGroupPos(CEnemyManager* mgr, int i)
{
	const auto& groups = mgr->GetEnemyGroups();
	return ((i >= 0) && (i < (int)groups.size())) ? groups[i].pos : AIFloat3(-RgtVector);
}

static float CEnemyManager_GetEnemyGroupCost(CEnemyManager* mgr, int i)
{
	const auto& groups = mgr->GetEnemyGroups();
	return ((i >= 0) && (i < (int)groups.size())) ? groups[i].cost : 0.f;
}

static float CEnemyManager_GetEnemyGroupRange(CEnemyManager* mgr, int i)
{
	return mgr->GetEnemyGroupRange(i);
}

// apex: for a script-driven D-gun raid (commander cloaks in and D-guns a
// target when energy allows -- apexearth's request). CmdCloak already exists
// on CCircuitUnit (used natively by RetreatTask's own cloak-on-retreat
// logic) but was never exposed to script. PushDGun wraps PushDGunAct +
// CDGunAction -- once pushed, CDGunAction's own Update() handles target
// selection, line-of-sight, and firing every few ticks entirely on its own
// (DGunAction.cpp), including its own energy-affordability check
// (IsDGunReady). Script only needs to get the unit close enough and push
// this once; it does not need to pick or track a target itself.
static void CCircuitUnit_CmdCloak(CCircuitUnit* unit, bool state)
{
	unit->CmdCloak(state);
}

static void CCircuitUnit_PushDGun(CCircuitUnit* unit, float range)
{
	unit->PushDGunAct(new CDGunAction(unit, range));
}

static void CCircuitUnit_CmdRepeat(CCircuitUnit* unit, bool repeat)
{
	unit->CmdRepeat(repeat);
}

// HOW MANY BUILD ORDERS THIS UNIT ALREADY HAS QUEUED, all defs or one.
//
// Without this every script-side view of a factory's queue is a guess. Nothing
// in the bound surface reads it -- CFactoryManager::GetTasks is not registered
// either -- so a quota that must not re-order what is already ordered had no
// way to tell, and each way of inferring it failed differently.
//
// A build order carries the NEGATIVE unitDefId as its command id, which is how a
// queued build is told from a move or a wait.
//
// THIS IS NOT THE WIDGET'S READ, AND THE DIFFERENCE IS THE WHOLE PROBLEM. BAR's
// Quota Mode widget runs inside the game: its Spring.GiveOrderToUnit lands
// before its next Spring.GetFactoryCommands. An AI order does not --
// CAICallback::GiveOrder only does clientNet->Send(SendAICommand(...)), so the
// order is applied when that message is consumed, and at benchmark sim speed
// that is ~45 sim-seconds later. This call answers what the engine has APPLIED,
// never what we have SENT. Anything throttling on it must keep its own count of
// what is outstanding. See docs/19-factory-through-brain.md.
// THE WHOLE COMMAND QUEUE, not just the build orders. CountQueued below filters
// to negative cmdIds, which is right for a factory and blind for a builder: a
// constructor walking to a site holds a MOVE, and a positive id is invisible to
// it. "The commander is standing around" is a claim about THIS number being
// zero, and until it was readable the claim could only be inferred from the
// synced gadget, which cannot say what the AI thought it was doing at the time.
static int CCircuitUnit_CmdQueueSize(CCircuitUnit* unit)
{
	int n = 0;
	auto commands = unit->GetUnit()->GetCurrentCommands();
	for (springai::Command* cmd : commands) {
		++n;
		delete cmd;
	}
	return n;
}

static int CCircuitUnit_CountQueued(CCircuitUnit* unit, CCircuitDef* buildDef)
{
	const int wanted = (buildDef == nullptr)
			? 0 : -buildDef->GetId();
	int n = 0;
	auto commands = unit->GetUnit()->GetCurrentCommands();
	for (springai::Command* cmd : commands) {
		const int id = cmd->GetId();
		if ((id < 0) && ((wanted == 0) || (id == wanted))) {
			++n;
		}
		delete cmd;
	}
	return n;
}

// Queue `count` of `buildDef` on a factory directly, the way a player does:
// one standing queue, appended with SHIFT, left alone to run. CRecruitTask is
// the other way -- one task per unit, and its Finish() calls Cancel(), which
// CmdRemoves every build order left on the factory. The two cannot coexist on
// the same factory: whichever unit finishes first wipes the rest of the queue.
// `replace` issues the first order with no options, which REPLACES the
// factory's queue; the rest append. That is how a player lays down a fresh
// queue, and it means no separate clear command is needed.
//
// SHIFT MULTIPLIES BY FIVE, so `count` here is 5x the units asked for.
// CFactoryCAI::GetCountMultiplierFromOptions (rts/Sim/Units/CommandAI/
// FactoryCAI.cpp:146) is `if (opts & SHIFT_KEY) ret *= 5; if (opts &
// CONTROL_KEY) ret *= 20;` and runs on every append. CmdInsertBuild carries
// neither and is the call to use; nothing calls this one.
static void CCircuitUnit_CmdBuildUnit(CCircuitUnit* unit, CCircuitDef* buildDef,
		int count, bool replace)
{
	if ((buildDef == nullptr) || (count <= 0)) {
		return;
	}
	const AIFloat3 pos = unit->GetPos(0);
	for (int i = 0; i < count; ++i) {
		const short opts = ((i == 0) && replace)
				? 0 : UNIT_COMMAND_OPTION_SHIFT_KEY;
		unit->CmdBuild(buildDef, pos, UNIT_NO_FACING, opts);
	}
}

// apex: a SHIFT-appended build order for a MOBILE builder -- the primitive a
// human's shift-queue is made of. FactoryCAI's x5 SHIFT multiplier does not
// apply to mobile CommandAI, so one call is one queued building. The caller
// owns the consequences: a non-shift order from any task Execute() wipes the
// queue, so append only after the current build has started and hold the
// unit from re-election while the queue runs (script/builder chain rule).
static void CCircuitUnit_CmdBuildQueuedAt(CCircuitUnit* unit, CCircuitDef* buildDef,
		const AIFloat3& pos)
{
	if (buildDef == nullptr) {
		return;
	}
	unit->CmdBuild(buildDef, pos, UNIT_NO_FACING, UNIT_COMMAND_OPTION_SHIFT_KEY);
}

// apex: in-game chat from script -- the same call SetupManager's welcome
// message uses. For role announcements a spectator can actually see
// (apexearth could not tell which player held the eco/tech role from
// watching; the infolog line is invisible in-game).
static void CCircuitAI_SendChat(CCircuitAI* circuit, const std::string& msg)
{
	circuit->GetGame()->SendTextMessage(msg.c_str(), 0);
}

static AIFloat3 CEnemyManager_GetEnemyPos(CEnemyManager* mgr)
{
	return mgr->GetEnemyPos();
}

static float CCircuitAI_GetUnitThreatAt(CCircuitAI* circuit, CCircuitUnit* unit, const AIFloat3& pos)
{
	return circuit->GetUnitThreatAt(unit, pos);
}

static float CCircuitAI_GetBuilderThreatAt(CCircuitAI* circuit, const AIFloat3& pos)
{
	return circuit->GetBuilderThreatAt(pos);
}

static float CCircuitAI_GetEnemyCostAt(CCircuitAI* circuit, const AIFloat3& pos, float radius)
{
	return circuit->GetEnemyCostAt(pos, radius);
}

static float CCircuitAI_GetWreckValueAt(CCircuitAI* circuit, const AIFloat3& pos, float radius)
{
	return circuit->GetWreckValueAt(pos, radius);
}

static AIFloat3 CCircuitAI_GetBestWreckPos(CCircuitAI* circuit, const AIFloat3& pos, float radius, float minMetal)
{
	return circuit->GetBestWreckPos(pos, radius, minMetal);
}

static AIFloat3 CCircuitAI_FindBuildSiteNear(CCircuitAI* circuit, CCircuitDef* def,
		const AIFloat3& pos, float radius)
{
	return circuit->FindBuildSiteNear(def, pos, radius);
}

static void CCircuitAI_SetBaseGrid(CCircuitAI* circuit, const AIFloat3& anchor,
		const AIFloat3& fwd, float cell, float lanePitch, float laneHalf, float range)
{
	circuit->SetBaseGrid(anchor, fwd, cell, lanePitch, laneHalf, range);
}

static AIFloat3 CSetupManager_GetBasePos(CSetupManager* mgr)
{
	return mgr->GetBasePos();
}

static AIFloat3 CSetupManager_GetLanePos(CSetupManager* mgr)
{
	return mgr->GetLanePos();
}

// Where the army HOLDS. CMilitaryManager::FillFrontPos picks the metal cluster
// nearest lanePos and hands back that cluster's defence points, so this is the
// one lever that decides whether the army stands at the front of the base or in
// the middle of it.
static void CSetupManager_SetLanePos(CSetupManager* mgr, const AIFloat3& pos)
{
	mgr->SetLanePos(pos);
}

static AIFloat3 CCircuitAI_GetChokePointPos(CCircuitAI* circuit, int idx)
{
	return circuit->GetChokePointPos(idx);
}

static bool CCircuitAI_GetChokePointEnds(CCircuitAI* circuit, int idx, AIFloat3& outEnd1, AIFloat3& outEnd2)
{
	return circuit->GetChokePointEnds(idx, outEnd1, outEnd2);
}

static bool CCircuitAI_GetAttackHotspot(CCircuitAI* circuit, AIFloat3& outPos, float& outWeight)
{
	return circuit->GetAttackHotspot(outPos, outWeight);
}

static bool CCircuitAI_GetBlockedBuildPos(CCircuitAI* circuit, AIFloat3& outPos)
{
	return circuit->GetBlockedBuildPos(outPos);
}

static CScriptArray* CCircuitAI_GetOwnUnitsOfDef(CCircuitAI* circuit, CCircuitDef* def,
		const AIFloat3& pos, float radius)
{
	const std::vector<CCircuitUnit*> found = circuit->GetOwnUnitsOfDef(def, pos, radius);
	CScriptArray* arr = CScriptArray::Create(gUnitArrayType, found.size());
	asUINT i = 0;
	for (CCircuitUnit* unit : found) {
		arr->SetValue(i++, &unit);
	}
	return arr;
}

static CScriptArray* CCircuitAI_GetOwnStructsNear(CCircuitAI* circuit, const AIFloat3& pos, float radius)
{
	const std::vector<CCircuitUnit*> found = circuit->GetOwnStructsNear(pos, radius);
	CScriptArray* arr = CScriptArray::Create(gUnitArrayType, found.size());
	asUINT i = 0;
	for (CCircuitUnit* unit : found) {
		arr->SetValue(i++, &unit);
	}
	return arr;
}

static CScriptArray* CCircuitAI_GetOwnDamagedNear(CCircuitAI* circuit, const AIFloat3& pos, float radius)
{
	const std::vector<CCircuitUnit*> found = circuit->GetOwnDamagedNear(pos, radius);
	CScriptArray* arr = CScriptArray::Create(gUnitArrayType, found.size());
	asUINT i = 0;
	for (CCircuitUnit* unit : found) {
		arr->SetValue(i++, &unit);
	}
	return arr;
}

static float CCircuitAI_GetPathLength(CCircuitAI* circuit, CCircuitUnit* unit, const AIFloat3& to)
{
	return circuit->GetPathLength(unit, to);
}

static float CCircuitAI_GetTeamMetalIncome(CCircuitAI* circuit, int otherTeamId)
{
	return circuit->GetTeamMetalIncome(otherTeamId);
}

static float CCircuitAI_GetTeamMetalFill(CCircuitAI* circuit, int otherTeamId)
{
	return circuit->GetTeamMetalFill(otherTeamId);
}

static float CCircuitAI_GetTunable(CCircuitAI* circuit, const std::string& name, float defVal)
{
	return circuit->GetTunable(name.c_str(), defVal);
}

// apex: monotonic microsecond clock so the script can profile its own sections.
// Host-local wall time — the AI runs only on the host, so reading it cannot
// desync; still, use it for logging only, never for a gameplay decision.
static double CCircuitAI_ClockUs(CCircuitAI* circuit)
{
	return double(std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now().time_since_epoch()).count());
}

static float CCircuitAI_GetDefBuildProgress(CCircuitAI* circuit, CCircuitDef* def)
{
	return circuit->GetDefBuildProgress(def);
}

static void CCircuitAI_PublishTeamValue(CCircuitAI* circuit, const std::string& key, float value)
{
	circuit->PublishTeamValue(key, value);
}

static float CCircuitAI_ReadTeamValue(CCircuitAI* circuit, int otherTeamId, const std::string& key, float defVal)
{
	return circuit->ReadTeamValue(otherTeamId, key, defVal);
}

static void CCircuitAI_SendResources(CCircuitAI* circuit, float metal, float energy, int toTeamId)
{
	circuit->SendResources(metal, energy, toTeamId);
}

static std::string CCircuitAI_CallRules(CCircuitAI* circuit, const std::string& data)
{
	return circuit->GetLua()->CallRules(data.c_str(), data.size());
}

static std::string CCircuitAI_CallUI(CCircuitAI* circuit, const std::string& data)
{
	return circuit->GetLua()->CallUI(data.c_str(), data.size());
}

static float CCircuitAI_GetGameRulesParamFloat(CCircuitAI* circuit, const std::string& key, float defVal)
{
	return circuit->GetGame()->GetRulesParamFloat(key.c_str(), defVal);
}

static std::string CCircuitAI_GetGameRulesParamString(CCircuitAI* circuit, const std::string& key, const std::string& defVal)
{
	return circuit->GetGame()->GetRulesParamString(key.c_str(), defVal.c_str());
}

static float CCircuitAI_GetTeamRulesParamFloat(CCircuitAI* circuit, const std::string& key, float defVal)
{
	return circuit->GetTeam()->GetRulesParamFloat(key.c_str(), defVal);
}

static std::string CCircuitAI_GetTeamRulesParamString(CCircuitAI* circuit, const std::string& key, const std::string& defVal)
{
	return circuit->GetTeam()->GetRulesParamString(key.c_str(), defVal.c_str());
}

static const std::string CCircuitDef_GetName(CCircuitDef* cdef)
{
	return cdef->GetDef()->GetName();
}

static float CCircuitUnit_GetRulesParamFloat(CCircuitUnit* unit, const std::string& key, float defVal)
{
	return unit->GetUnit()->GetRulesParamFloat(key.c_str(), defVal);
}

static std::string CCircuitUnit_GetRulesParamString(CCircuitUnit* unit, const std::string& key, const std::string& defVal)
{
	return unit->GetUnit()->GetRulesParamString(key.c_str(), defVal.c_str());
}

// Which kind of fight a task is. The script keeps its own register of fighter
// tasks (Military::gSquads) but could not tell an attack squad from a raid,
// scout, guard or support task, so anything counting "squads" counted all of
// them. Returns FightType::_SIZE_ for a task that is not a fighter task at all,
// rather than downcasting blind the way the GetBuildType binding below does.
static int IUnitTask_GetFightType(IUnitTask* task)
{
	return (task->GetType() == IUnitTask::Type::FIGHTER)
			? int(static_cast<IFighterTask*>(task)->GetFightType())
			: int(IFighterTask::FightType::_SIZE_);
}

static CScriptArray* IUnitTask_GetUnits(IUnitTask* task)
{
	// Without caching arrayType can be extracted by:
//	asIScriptEngine* engine = asGetActiveContext()->GetEngine(); // Get engine from active context
//	asITypeInfo* arrayType = engine->GetTypeInfoByDecl("array<CCircuitUnit@>");
	CScriptArray* arr = CScriptArray::Create(gUnitArrayType, task->GetAssignees().size());
	asUINT i = 0;
	for (CCircuitUnit* unit : task->GetAssignees()) {
		arr->SetValue(i++, &unit);
	}
	return arr;
}

CInitScript::CInitScript(CScriptManager* scr, CCircuitAI* ai)
		: IScript(scr)
		, circuit(ai)
{
	asIScriptEngine* engine = script->GetEngine();

	// RegisterSpringai
	static_assert(std::is_base_of<float3, AIFloat3>::value, "AIFloat3 must be a subclass of float3!");
	static_assert(sizeof(AIFloat3) == sizeof(float3), "Memory layout of AIFloat3 must be same as float3");
	// FIXME: MinGW didn't like asbind20
//	asbind20::value_class<float3>(
//		engine,
//		"AIFloat3",
//		// value_class is asOBJ_VALUE. Other flags will be automatically set using asGetTypeTraits<T>()
//		asOBJ_POD | asOBJ_APP_CLASS_ALLFLOATS | asOBJ_APP_CLASS_MORE_CONSTRUCTORS
//	)
//		.behaviours_by_traits()
//		.constructor<float>("float", asbind20::use_explicit)
//		.constructor_function("float, float, float", &ConstructVec3Val)
//		.property("float x", &float3::x)
//		.property("float y", &float3::y)
//		.property("float z", &float3::z)
//		.opAdd()                                             // float3 operator+ (const float3& f) const
//		.use(asbind20::const_this + asbind20::param<float>)  // float3 operator+ (const float f) const
//		.opAddAssign()                                       // float3& operator+= (const float3& f)
//		.opSub()                                             // float3 operator- (const float3& f) const
//		.use(asbind20::const_this - asbind20::param<float>)  // float3 operator- (const float f) const
//		.method("void opSubAssign(const AIFloat3& in)", &float3::operator-=)  // bad opSubAssign in float3
//		.opNeg()                                             // constexpr float3 operator- () const
//		.opMul()                                             // float3 operator* (const float3& f) const
//		.use(asbind20::const_this * asbind20::param<float>)  // float3 operator* (const float f) const
////		.use(asbind20::param<float> * asbind20::const_this)  // inline float3 operator*(float f, const float3& v)
//		.method("void opMulAssign(const AIFloat3& in)", asbind20::overload_cast<float>(&float3::operator*=))  // bad opMulAssign in float3
//		.use(asbind20::_this *= asbind20::param<float>)      // float3& operator*= (float f)
//		.opDiv()                                             // float3 operator/ (const float3& f) const
//		.use(asbind20::const_this / asbind20::param<float>)  // float3 operator/ (const float f) const
//		.method("void opDivAssign(const AIFloat3& in)", asbind20::overload_cast<const float3&>(&float3::operator/=))  // bad opDivAssign in float3
//		.method("void opDivAssign(const float)", asbind20::overload_cast<float>(&float3::operator/=))  // void operator/= (const float f)
//		.opEquals()                                          // bool operator== (const float3& f) const
//		.use(asbind20::_this[asbind20::param<int>])          // float& operator[] (const int t)
//		.use(asbind20::const_this[asbind20::param<int>])     // const float& operator[] (const int t) const
//		.method("bool equals(const AIFloat3& in, const AIFloat3& in) const", &float3::equals)
//		.method("bool same(const AIFloat3& in) const", &float3::same)
//		.method("bool binarySame(const AIFloat3& in) const", &float3::binarySame)
//		.method("float dot(const AIFloat3& in) const", &float3::dot)
//		.method("float dot2D(const AIFloat3& in) const", &float3::dot2D)
//		.method("AIFloat3 cross(const AIFloat3& in) const", &float3::cross)
//		.method("AIFloat3 rotate(float, const AIFloat3& in) const", &float3::rotate<false>)
//		.method("AIFloat3 rotateByUpVector(const AIFloat3& in, const AIFloat3& in) const", &float3::rotateByUpVector)
//		.method("AIFloat3 rotate2D(const AIFloat3& in) const", &float3::rotate2D)
//		.method("AIFloat3 snapToAxis() const", &float3::snapToAxis)
//		.method("float distance(const AIFloat3& in) const", &float3::distance)
//		.method("float distance2D(const AIFloat3& in) const", asbind20::overload_cast<const float3&>(&float3::distance2D, asbind20::const_))
//		.method("float SqDistance(const AIFloat3& in) const", &float3::SqDistance)
//		.method("float SqDistance2D(const AIFloat3& in) const", asbind20::overload_cast<const float3&>(&float3::SqDistance2D, asbind20::const_))
//		.method("float Length() const", &float3::Length)
//		.method("float Length2D() const", &float3::Length2D)
//		.method("float SqLength() const", &float3::SqLength)
//		.method("float SqLength2D() const", &float3::SqLength2D)
//		.method("float LengthNormalize()", &float3::LengthNormalize)
//		.method("float LengthNormalize2D()", &float3::LengthNormalize2D)
//		.method("AIFloat3& Normalize()", &float3::Normalize)
//		.method("AIFloat3& Normalize2D()", &float3::Normalize2D)
//		.method("AIFloat3& SafeNormalize()", &float3::SafeNormalize)
//		.method("AIFloat3& SafeNormalize2D()", &float3::SafeNormalize2D)
//		.method("AIFloat3 PickNonParallel() const", &float3::PickNonParallel)
//		.method("bool Normalized() const", &float3::Normalized)
//		.method("bool CheckNaNs() const", &float3::CheckNaNs)
//		.method("bool IsInMap() const", &float3::IsInMap)
//		.method("void ClampInMap()", &float3::ClampInMap)
//		.method("string str() const", &float3::str)
//		.method("string ToString() const", &AIFloat3::ToString)  // HAX
//		.method("string opImplConv() const", [](const float3& f) {
//			return f.str();  // static_cast<const AIFloat3&>(f).ToString();
//		});
//	// NOTE: ".use(asbind20::param<float> * asbind20::const_this)" makes IDE go "Syntax error" (but compiles)
//	int r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opMul_r(float) const", asFUNCTIONPR(operator*, (float, const float3&), float3), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
//	asbind20::global(engine)
//		.function("AIFloat3 AiMin(const AIFloat3, const AIFloat3)", &float3::min)
//		.function("AIFloat3 AiMax(const AIFloat3, const AIFloat3)", &float3::max)
//		.function("AIFloat3 AiFabs(const AIFloat3)", &float3::fabs)
//		.function("AIFloat3 AiSign(const AIFloat3)", &float3::sign);
	int r = engine->RegisterObjectType("AIFloat3", sizeof(float3),
			asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_ALLFLOATS | asOBJ_APP_CLASS_MORE_CONSTRUCTORS | asGetTypeTraits<float3>()); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("AIFloat3", asBEHAVE_CONSTRUCT, "void f()", asFUNCTION(ConstructVec3), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("AIFloat3", asBEHAVE_CONSTRUCT, "void f(const AIFloat3& in)", asFUNCTION(ConstructCopyVec3), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("AIFloat3", asBEHAVE_CONSTRUCT, "void f(float)", asFUNCTION(ConstructVec3Val1), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("AIFloat3", asBEHAVE_CONSTRUCT, "void f(float, float, float)", asFUNCTION(ConstructVec3Val3), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("AIFloat3", "float x", asOFFSET(float3, x)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("AIFloat3", "float y", asOFFSET(float3, y)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("AIFloat3", "float z", asOFFSET(float3, z)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opAdd(const AIFloat3& in) const", asMETHODPR(float3, operator+, (const float3&) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opAdd(float) const", asMETHODPR(float3, operator+, (const float) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3& opAddAssign(const AIFloat3& in)", asMETHOD(float3, operator+=), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opSub(const AIFloat3& in) const", asMETHODPR(float3, operator-, (const float3&) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opSub(float) const", asMETHODPR(float3, operator-, (const float) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "void opSubAssign(const AIFloat3& in)", asMETHOD(float3, operator-=), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opNeg() const", asMETHODPR(float3, operator-, () const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opMul(const AIFloat3& in) const", asMETHODPR(float3, operator*, (const float3&) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opMul(float) const", asMETHODPR(float3, operator*, (const float) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opMul_r(float) const", asFUNCTIONPR(operator*, (float, const float3&), float3), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "void opMulAssign(const AIFloat3& in)", asMETHODPR(float3, operator*=, (const float3&), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3& opMulAssign(float)", asMETHODPR(float3, operator*=, (float), float3&), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opDiv(const AIFloat3& in) const", asMETHODPR(float3, operator/, (const float3&) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 opDiv(float) const", asMETHODPR(float3, operator/, (const float) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "void opDivAssign(const AIFloat3& in)", asMETHODPR(float3, operator/=, (const float3&), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "void opDivAssign(float)", asMETHODPR(float3, operator/=, (const float), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool opEquals(const AIFloat3& in) const", asMETHOD(float3, operator==), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float& opIndex(int)", asMETHODPR(float3, operator[], (const int), float&), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "const float& opIndex(int) const", asMETHODPR(float3, operator[], (const int) const, const float&), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool equals(const AIFloat3& in, const AIFloat3& in) const", asMETHOD(float3, equals), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool same(const AIFloat3& in) const", asMETHOD(float3, same), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool binarySame(const AIFloat3& in) const", asMETHOD(float3, binarySame), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float dot(const AIFloat3& in) const", asMETHOD(float3, dot), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float dot2D(const AIFloat3& in) const", asMETHOD(float3, dot2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 cross(const AIFloat3& in) const", asMETHOD(float3, cross), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 rotate(float, const AIFloat3& in) const", asMETHODPR(float3, rotate<false>, (float angle, const float3& axis) const, float3), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 rotateByUpVector(const AIFloat3& in, const AIFloat3& in) const", asMETHOD(float3, rotateByUpVector), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 rotate2D(const AIFloat3& in) const", asMETHOD(float3, rotate2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 snapToAxis() const", asMETHOD(float3, snapToAxis), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float distance(const AIFloat3& in) const", asMETHOD(float3, distance), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float distance2D(const AIFloat3& in) const", asMETHODPR(float3, distance2D, (const float3&) const, float), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float SqDistance(const AIFloat3& in) const", asMETHOD(float3, SqDistance), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float SqDistance2D(const AIFloat3& in) const", asMETHODPR(float3, SqDistance2D, (const float3&) const, float), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float Length() const", asMETHOD(float3, Length), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float Length2D() const", asMETHOD(float3, Length2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float SqLength() const", asMETHOD(float3, SqLength), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float SqLength2D() const", asMETHOD(float3, SqLength2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float LengthNormalize()", asMETHOD(float3, LengthNormalize), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "float LengthNormalize2D()", asMETHOD(float3, LengthNormalize2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3& Normalize()", asMETHOD(float3, Normalize), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3& Normalize2D()", asMETHOD(float3, Normalize2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3& SafeNormalize()", asMETHOD(float3, SafeNormalize), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3& SafeNormalize2D()", asMETHOD(float3, SafeNormalize2D), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "AIFloat3 PickNonParallel() const", asMETHOD(float3, PickNonParallel), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool Normalized() const", asMETHOD(float3, Normalized), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool CheckNaNs() const", asMETHOD(float3, CheckNaNs), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "bool IsInMap() const", asMETHOD(float3, IsInMap), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "void ClampInMap()", asMETHOD(float3, ClampInMap), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "string str() const", asMETHOD(float3, str), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("AIFloat3", "string ToString() const", asMETHOD(AIFloat3, ToString), asCALL_THISCALL); ASSERT(r >= 0);  // HAX
	r = engine->RegisterObjectMethod("AIFloat3", "string opImplConv() const", asFUNCTION(ConvertVec3ToStr), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("AIFloat3 AiMin(const AIFloat3, const AIFloat3)", asFUNCTION(float3::min), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("AIFloat3 AiMax(const AIFloat3, const AIFloat3)", asFUNCTION(float3::max), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("AIFloat3 AiFabs(const AIFloat3)", asFUNCTION(float3::fabs), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("AIFloat3 AiSign(const AIFloat3)", asFUNCTION(float3::sign), asCALL_CDECL); ASSERT(r >= 0);

	// RegisterUtils
//	asbind20::global(engine)
//		.function("void AiLog(const string& in)", &CInitScript::Log, asbind20::auxiliary(this));
	r = engine->RegisterGlobalFunction("void AiLog(const string& in)", asMETHOD(CInitScript, Log), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("void AiAddPoint(const AIFloat3& in, const string& in)", asMETHOD(CInitScript, AddPoint), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("void AiDelPoint(const AIFloat3& in)", asMETHOD(CInitScript, DelPoint), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("void AiPause(bool, const string& in)", asMETHOD(CInitScript, Pause), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("int AiDice(const array<float>@+)", asMETHOD(CInitScript, Dice), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("int AiMin(int, int)", asMETHODPR(CInitScript, Min<int>, (int, int) const, int), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("float AiMin(float, float)", asMETHODPR(CInitScript, Min<float>, (float, float) const, float), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("int AiMax(int, int)", asMETHODPR(CInitScript, Max<int>, (int, int) const, int), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("float AiMax(float, float)", asMETHODPR(CInitScript, Max<float>, (float, float) const, float), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("int AiRandom(int, int)", asMETHOD(CInitScript, Random), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("void AiSendMessage(const string& in, int = -1)", asMETHOD(CInitScript, SendMessage), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterFuncdef("void AiOnFinish(dictionary@+)"); ASSERT(r >= 0);
	r = engine->RegisterFuncdef("AiOnFinish@+ AiExec(dictionary@+)"); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("void AiRun(AiExec@+, dictionary@)", asMETHOD(CInitScript, Run), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("void AiSleep(uint64)", asFUNCTION(utils::sleep), asCALL_CDECL); ASSERT(r >= 0);

	r = engine->RegisterObjectType("IStream", sizeof(std::istream), asOBJ_REF | asOBJ_NOCOUNT); ASSERT(r >= 0);
	r = engine->RegisterObjectType("OStream", sizeof(std::ostream), asOBJ_REF | asOBJ_NOCOUNT); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(bool& out)", asFUNCTION(utils::binary_read<bool>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(int8& out)", asFUNCTION(utils::binary_read<int8_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(int16& out)", asFUNCTION(utils::binary_read<int16_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(int& out)", asFUNCTION(utils::binary_read<int32_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(int64& out)", asFUNCTION(utils::binary_read<int64_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(uint8& out)", asFUNCTION(utils::binary_read<uint8_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(uint16& out)", asFUNCTION(utils::binary_read<uint16_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(uint& out)", asFUNCTION(utils::binary_read<uint32_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(uint64& out)", asFUNCTION(utils::binary_read<uint64_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(float& out)", asFUNCTION(utils::binary_read<float>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IStream", "IStream& opShr(double& out)", asFUNCTION(utils::binary_read<double>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const bool& in)", asFUNCTION(utils::binary_write<bool>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const int8& in)", asFUNCTION(utils::binary_write<int8_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const int16& in)", asFUNCTION(utils::binary_write<int16_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const int& in)", asFUNCTION(utils::binary_write<int32_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const int64& in)", asFUNCTION(utils::binary_write<int64_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const uint8& in)", asFUNCTION(utils::binary_write<uint8_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const uint16& in)", asFUNCTION(utils::binary_write<uint16_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const uint& in)", asFUNCTION(utils::binary_write<uint32_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const uint64& in)", asFUNCTION(utils::binary_write<uint64_t>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const float& in)", asFUNCTION(utils::binary_write<float>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("OStream", "OStream& opShl(const double& in)", asFUNCTION(utils::binary_write<double>), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);

	r = engine->RegisterObjectMethod("string", "string toLower() const", asFUNCTION(utils::StringToLower), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("string", "string toUpper() const", asFUNCTION(utils::StringToUpper), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);

	// RegisterCircuitAI
	r = engine->RegisterTypedef("Id", "int"); ASSERT(r >= 0);

	r = engine->RegisterObjectType("TypeMask", sizeof(CMaskHandler::TypeMask), asOBJ_VALUE | asOBJ_POD | asGetTypeTraits<CMaskHandler::TypeMask>()); ASSERT(r >= 0);
	r = engine->RegisterTypedef("Type", "int"); ASSERT(r >= 0);
	r = engine->RegisterTypedef("Mask", "uint"); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("TypeMask", "Type type", asOFFSET(CMaskHandler::TypeMask, type)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("TypeMask", "Mask mask", asOFFSET(CMaskHandler::TypeMask, mask)); ASSERT(r >= 0);

//	r = engine->SetDefaultNamespace("Task"); ASSERT(r >= 0);
//	r = engine->RegisterEnum("RecruitType"); ASSERT(r >= 0);
//	r = engine->RegisterEnumValue("RecruitType", "BUILDPOWER", static_cast<int>(CRecruitTask::RecruitType::BUILDPOWER)); ASSERT(r >= 0);
//	r = engine->RegisterEnumValue("RecruitType", "FIREPOWER", static_cast<int>(CRecruitTask::RecruitType::FIREPOWER)); ASSERT(r >= 0);
//	r = engine->SetDefaultNamespace(""); ASSERT(r >= 0);

	r = engine->RegisterObjectType("CCircuitAI", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CCircuitAI ai", circuit); ASSERT(r >= 0);

	r = engine->RegisterObjectType("CCircuitDef", 0, asOBJ_REF | asOBJ_NOCOUNT); ASSERT(r >= 0);
	r = engine->RegisterObjectType("CCircuitUnit", 0, asOBJ_REF | asOBJ_NOCOUNT); ASSERT(r >= 0);
	r = engine->RegisterObjectType("IUnitTask", 0, asOBJ_REF); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("IUnitTask", asBEHAVE_ADDREF, "void f()", asMETHODPR(IRefCounter, AddRef, (), int), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("IUnitTask", asBEHAVE_RELEASE, "void f()", asMETHODPR(IRefCounter, Release, (), int), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "int GetRefCount() const", asMETHODPR(IRefCounter, GetRefCount, () const, int), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "Type GetType() const", asMETHODPR(IUnitTask, GetType, () const, IUnitTask::Type), asCALL_THISCALL); ASSERT(r >= 0);
	// Script ledgers remember tasks across frames; without this they cannot
	// drop dead ones, and a remembered dead task returned from AiMakeTask is
	// refused by AssignTask -- the unit idles forever on a stale handle.
	r = engine->RegisterObjectMethod("IUnitTask", "bool IsDead() const", asMETHODPR(IUnitTask, IsDead, () const, bool), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "Type GetBuildType() const", asMETHODPR(IBuilderTask, GetBuildType, () const, IBuilderTask::BuildType), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "const AIFloat3& GetBuildPos() const", asMETHODPR(IBuilderTask, GetPosition, () const, const AIFloat3&), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("IUnitTask", "CCircuitDef@ const buildDef", asOFFSET(IBuilderTask, buildDef)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("IUnitTask", "CCircuitUnit@ const target", asOFFSET(IBuilderTask, target)); ASSERT(r >= 0);
	gUnitArrayType = engine->GetTypeInfoByDecl("array<CCircuitUnit@>");
	r = engine->RegisterObjectMethod("IUnitTask", "array<CCircuitUnit@>@ GetUnits() const", asFUNCTION(IUnitTask_GetUnits), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "void RemoveUnit(CCircuitUnit@)", asMETHOD(IUnitTask, RemoveAssignee), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "int GetFightType() const", asFUNCTION(IUnitTask_GetFightType), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "void Abort()", asMETHOD(IUnitTask, Abort), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("IUnitTask", "void Done()", asMETHOD(IUnitTask, Done), asCALL_THISCALL); ASSERT(r >= 0);

	r = engine->RegisterObjectProperty("CCircuitAI", "const int frame", asOFFSET(CCircuitAI, lastFrame)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitAI", "const int skirmishAIId", asOFFSET(CCircuitAI, skirmishAIId)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitAI", "const int teamId", asOFFSET(CCircuitAI, teamId)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitAI", "const int allyTeamId", asOFFSET(CCircuitAI, allyTeamId)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "CCircuitDef@ GetCircuitDef(const string& in)", asFUNCTION(CCircuitAI_GetCircuitDef), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "CCircuitDef@ GetCircuitDef(Id)", asMETHODPR(CCircuitAI, GetCircuitDef, (CCircuitDef::Id), CCircuitDef*), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetDefCount() const", asMETHOD(CCircuitAI, GetDefCount), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "CCircuitUnit@ GetTeamUnit(Id)", asMETHOD(CCircuitAI, GetTeamUnit), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "string GetMapName() const", asFUNCTION(CCircuitAI_GetMapName), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "AIFloat3 SnapBuildPos(CCircuitDef@, const AIFloat3& in) const", asFUNCTION(CCircuitAI_SnapBuildPos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetEnemyTeamSize() const", asMETHOD(CCircuitAI, GetEnemyTeamSize), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int CountEnemyDefNear(int, const AIFloat3& in, float)", asFUNCTION(CCircuitAI_CountEnemyDefNear), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool CanDefReach(CCircuitDef@, const AIFloat3& in, const AIFloat3& in)", asFUNCTION(CCircuitAI_CanDefReach), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int ForgetEnemiesNear(const AIFloat3& in, float)", asFUNCTION(CCircuitAI_ForgetEnemiesNear), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool IsLoadSave() const", asMETHOD(CCircuitAI, IsLoadSave), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "Type GetBindedRole(Type) const", asMETHOD(CCircuitAI, GetBindedRole), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetLeadTeamId() const", asFUNCTION(CCircuitAI_GetLeadTeamId), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// Sizing a quota: the unit limit, and what we are already holding of it.
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetUnitLimit() const", asFUNCTION(CCircuitAI_GetUnitLimit), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetUnitMax() const", asFUNCTION(CCircuitAI_GetUnitMax), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetTeamUnitCount(bool) const", asFUNCTION(CCircuitAI_GetTeamUnitCount), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "Type GetSideId() const", asMETHOD(CCircuitAI, GetSideId), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "const string& GetSideName() const", asMETHOD(CCircuitAI, GetSideName), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "array<Id>@ GetTeamIds() const", asFUNCTION(CCircuitAI_GetTeamIds), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void GiveUnits(const array<CCircuitUnit@>@+, int)", asFUNCTION(CCircuitAI_GiveUnits), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void SendResources(float, float, int)", asFUNCTION(CCircuitAI_SendResources), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void SendChat(const string& in)", asFUNCTION(CCircuitAI_SendChat), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetTeamMetalFill(int) const", asFUNCTION(CCircuitAI_GetTeamMetalFill), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetTeamMetalIncome(int) const", asFUNCTION(CCircuitAI_GetTeamMetalIncome), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// In-process team coordination, replacing the synced-gadget rules params.
	// A hosted multiplayer game cannot carry synced Lua, but every AI the host
	// adds shares this process, so they can simply read each other.
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetDefBuildProgress(CCircuitDef@) const", asFUNCTION(CCircuitAI_GetDefBuildProgress), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetTunable(const string &in, float) const", asFUNCTION(CCircuitAI_GetTunable), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "double ClockUs() const", asFUNCTION(CCircuitAI_ClockUs), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void PublishTeamValue(const string& in, float)", asFUNCTION(CCircuitAI_PublishTeamValue), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float ReadTeamValue(int, const string& in, float) const", asFUNCTION(CCircuitAI_ReadTeamValue), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "AIFloat3 GetBestWreckPos(const AIFloat3& in, float, float) const", asFUNCTION(CCircuitAI_GetBestWreckPos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetWreckValueAt(const AIFloat3& in, float) const", asFUNCTION(CCircuitAI_GetWreckValueAt), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool GetBlockedBuildPos(AIFloat3& out)", asFUNCTION(CCircuitAI_GetBlockedBuildPos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void SetEngageBoost(float)", asMETHOD(CCircuitAI, SetEngageBoost), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void SetCommitted(bool)", asMETHOD(CCircuitAI, SetCommitted), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool GetAttackHotspot(AIFloat3& out, float& out)", asFUNCTION(CCircuitAI_GetAttackHotspot), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetChokePointCount() const", asMETHOD(CCircuitAI, GetChokePointCount), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "AIFloat3 GetChokePointPos(int) const", asFUNCTION(CCircuitAI_GetChokePointPos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetChokePointWidth(int) const", asMETHOD(CCircuitAI, GetChokePointWidth), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool GetChokePointEnds(int, AIFloat3& out, AIFloat3& out)", asFUNCTION(CCircuitAI_GetChokePointEnds), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "int GetChokePointArea(int, int) const", asMETHOD(CCircuitAI, GetChokePointArea), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void SetFrontPos(const AIFloat3& in)", asMETHOD(CCircuitAI, SetFrontPos), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void SetBaseGrid(const AIFloat3& in, const AIFloat3& in, float, float, float, float)", asFUNCTION(CCircuitAI_SetBaseGrid), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool IsPosOnMap(const AIFloat3& in) const",asMETHOD(CCircuitAI, IsPosOnMap), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetAllyInflAt(const AIFloat3& in) const", asMETHOD(CCircuitAI, GetAllyInflAt), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetEnemyInflAt(const AIFloat3& in) const", asMETHOD(CCircuitAI, GetEnemyInflAt), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetNetInflAt(const AIFloat3& in) const", asMETHOD(CCircuitAI, GetNetInflAt), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void DrawPoint(const AIFloat3& in, const string& in)", asMETHOD(CCircuitAI, DrawPoint), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void DrawLine(const AIFloat3& in, const AIFloat3& in)", asMETHOD(CCircuitAI, DrawLine), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "void DrawErase(const AIFloat3& in)", asMETHOD(CCircuitAI, DrawErase), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "AIFloat3 FindBuildSiteNear(CCircuitDef@, const AIFloat3& in, float)", asFUNCTION(CCircuitAI_FindBuildSiteNear), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetEngageBoost() const", asMETHOD(CCircuitAI, GetEngageBoost), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "array<CCircuitUnit@>@ GetOwnUnitsOfDef(CCircuitDef@, const AIFloat3& in, float)", asFUNCTION(CCircuitAI_GetOwnUnitsOfDef), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "array<CCircuitUnit@>@ GetOwnStructsNear(const AIFloat3& in, float)", asFUNCTION(CCircuitAI_GetOwnStructsNear), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "array<CCircuitUnit@>@ GetOwnDamagedNear(const AIFloat3& in, float)", asFUNCTION(CCircuitAI_GetOwnDamagedNear), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetPathLength(CCircuitUnit@, const AIFloat3& in)", asFUNCTION(CCircuitAI_GetPathLength), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetEnemyCostAt(const AIFloat3& in, float) const", asFUNCTION(CCircuitAI_GetEnemyCostAt), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetBuilderThreatAt(const AIFloat3& in) const", asFUNCTION(CCircuitAI_GetBuilderThreatAt), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetUnitThreatAt(CCircuitUnit@, const AIFloat3& in) const", asFUNCTION(CCircuitAI_GetUnitThreatAt), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool UnitControl(CCircuitUnit@, bool)", asMETHODPR(CCircuitAI, UnitControl, (CCircuitUnit*, bool), bool), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "bool UnitControl(Id, bool)", asMETHODPR(CCircuitAI, UnitControl, (ICoreUnit::Id, bool), bool), asCALL_THISCALL); ASSERT(r >= 0);
	// Lua<-->AI communications [in Spring 0.83+]
	r = engine->RegisterObjectMethod("CCircuitAI", "string CallRules(const string& in)", asFUNCTION(CCircuitAI_CallRules), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "string CallUI(const string& in)", asFUNCTION(CCircuitAI_CallUI), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// RulesParams accessors on AI (game/team)
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetGameRulesParam(const string& in, float) const", asFUNCTION(CCircuitAI_GetGameRulesParamFloat), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "string GetGameRulesParam(const string& in, const string& in) const", asFUNCTION(CCircuitAI_GetGameRulesParamString), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetTeamRulesParam(const string& in, float) const", asFUNCTION(CCircuitAI_GetTeamRulesParamFloat), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "string GetTeamRulesParam(const string& in, const string& in) const", asFUNCTION(CCircuitAI_GetTeamRulesParamString), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);

	CMaskHandler* sideMasker = &circuit->GetGameAttribute()->GetSideMasker();
	CMaskHandler* roleMasker = &circuit->GetGameAttribute()->GetRoleMasker();
	CMaskHandler* attrMasker = &circuit->GetGameAttribute()->GetAttrMasker();
	r = engine->RegisterObjectType("CMaskHandler", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CMaskHandler aiSideMasker", sideMasker); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CMaskHandler aiRoleMasker", roleMasker); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CMaskHandler aiAttrMasker", attrMasker); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMaskHandler", "TypeMask GetTypeMask(const string& in)", asMETHOD(CMaskHandler, GetTypeMask), asCALL_THISCALL); ASSERT(r >= 0);

	r = engine->RegisterGlobalFunction("TypeMask AiAddRole(const string& in, Type)", asMETHOD(CInitScript, AddRole), asCALL_THISCALL_ASGLOBAL, this); ASSERT(r >= 0);

	r = engine->RegisterObjectMethod("CCircuitDef", "void SetMainRole(Type)", asMETHOD(CCircuitDef, SetMainRole), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "Type GetMainRole() const", asMETHOD(CCircuitDef, GetMainRole), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsRespRoleAny(Mask) const", asMETHOD(CCircuitDef, IsRespRoleAny), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsRoleAny(Mask) const", asMETHOD(CCircuitDef, IsRoleAny), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void AddAttribute(Type)", asMETHOD(CCircuitDef, AddAttribute), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void DelAttribute(Type)", asMETHOD(CCircuitDef, DelAttribute), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void TglAttribute(Type)", asMETHOD(CCircuitDef, TglAttribute), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsAttrAny(Mask) const", asMETHOD(CCircuitDef, IsAttrAny), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "const string GetName() const", asFUNCTION(CCircuitDef_GetName), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const Id id", asOFFSET(CCircuitDef, id)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsAvailable(int)", asMETHODPR(CCircuitDef, IsAvailable, (int) const, bool), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const int count", asOFFSET(CCircuitDef, count)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float health", asOFFSET(CCircuitDef, health)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float speed", asOFFSET(CCircuitDef, speed)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float losRadius", asOFFSET(CCircuitDef, losRadius)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float sonarRadius", asOFFSET(CCircuitDef, sonarRadius)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float costM", asOFFSET(CCircuitDef, costM)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float costE", asOFFSET(CCircuitDef, costE)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float threat", asOFFSET(CCircuitDef, defThreat)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float power", asOFFSET(CCircuitDef, power)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float defDmg", asOFFSET(CCircuitDef, defThrDmg)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float pwrDmg", asOFFSET(CCircuitDef, pwrDmg)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float airThrDmg", asOFFSET(CCircuitDef, airThrDmg)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float surfThrDmg", asOFFSET(CCircuitDef, surfThrDmg)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float waterThrDmg", asOFFSET(CCircuitDef, waterThrDmg)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "const float minRange", asOFFSET(CCircuitDef, minRange)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetMaxRange(Type) const", asMETHODPR(CCircuitDef, GetMaxRange, (CCircuitDef::RangeType) const, float), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetMaxRange() const", asMETHODPR(CCircuitDef, GetMaxRange, () const, float), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetRange(Type, float)", asMETHODPR(CCircuitDef, SetRange, (CCircuitDef::RangeType, float), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetRange(float)", asMETHODPR(CCircuitDef, SetRange, (float), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetAirThreat() const", asMETHOD(CCircuitDef, GetAirThreat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetSurfThreat() const", asMETHOD(CCircuitDef, GetSurfThreat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetWaterThreat() const", asMETHOD(CCircuitDef, GetWaterThreat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsAbleToFly() const", asMETHOD(CCircuitDef, IsAbleToFly), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsMobile() const", asMETHOD(CCircuitDef, IsMobile), asCALL_THISCALL); ASSERT(r >= 0);
	// BUILD RANGE IS NOT A CONSTANT. apexearth: "players can tweak game settings
	// which increase build range." Reading the def's own value is the only way a
	// placement rule can stay correct under a modoption that changes it.
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetBuildDistance() const", asMETHOD(CCircuitDef, GetBuildDistance), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsMex() const", asMETHOD(CCircuitDef, IsMex), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsBuilder() const", asMETHOD(CCircuitDef, IsBuilder), asCALL_THISCALL); ASSERT(r >= 0);
	// Def-property senses for the Catalog (docs/20-brain-overhaul.md step 0).
	// costM/costE/health/speed/power are already object properties above.
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetBuildTime() const", asMETHOD(CCircuitDef, GetBuildTime), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetBuildSpeed() const", asMETHOD(CCircuitDef, GetBuildSpeed), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetWorkerTime() const", asMETHOD(CCircuitDef, GetWorkerTime), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetExtractsM() const", asMETHOD(CCircuitDef, GetExtractsM), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetUpkeepM() const", asMETHOD(CCircuitDef, GetUpkeepM), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetUpkeepE() const", asMETHOD(CCircuitDef, GetUpkeepE), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "int GetReloadTime() const", asMETHOD(CCircuitDef, GetReloadTime), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsWind() const", asMETHOD(CCircuitDef, IsWind), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetMakeM() const", asMETHOD(CCircuitDef, GetMakeM), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetMakeE() const", asMETHOD(CCircuitDef, GetMakeE), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetStoreM() const", asMETHOD(CCircuitDef, GetStoreM), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetStoreE() const", asMETHOD(CCircuitDef, GetStoreE), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetConvertCapacity() const", asMETHOD(CCircuitDef, GetConvertCapacity), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetConvertRatio() const", asMETHOD(CCircuitDef, GetConvertRatio), asCALL_THISCALL); ASSERT(r >= 0);
	// Native buildOptions lookup (an unordered_set::find), already computed for
	// CircuitAI's own task assignment -- exposing it lets script guard a task
	// against the "no constructor of ours can build this" silent no-op instead
	// of approximating capability from cost or name (see IsAdvConDef).
	r = engine->RegisterObjectMethod("CCircuitDef", "bool CanBuild(CCircuitDef@) const", asMETHODPR(CCircuitDef, CanBuild, (const CCircuitDef*) const, bool), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "int maxThisUnit", asOFFSET(CCircuitDef, maxThisUnit)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "int sinceFrame", asOFFSET(CCircuitDef, sinceFrame)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitDef", "int cooldown", asOFFSET(CCircuitDef, cooldown)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetIgnore(bool)", asMETHOD(CCircuitDef, SetIgnore), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsIgnore() const", asMETHOD(CCircuitDef, IsIgnore), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetThreatKernel(float)", asMETHOD(CCircuitDef, SetThreatKernel), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetFireState(int)", asMETHOD(CCircuitDef, SetFireState), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "int GetFireState() const", asMETHOD(CCircuitDef, GetFireState), asCALL_THISCALL); ASSERT(r >= 0);
	// CCircuitDef is owned per CCircuitAI, so this scopes to one instance --
	// unlike behaviour.json's retreat, which applies to every player.
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetRetreat(float)", asMETHOD(CCircuitDef, SetRetreat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "float GetRetreat() const", asMETHOD(CCircuitDef, GetRetreat), asCALL_THISCALL); ASSERT(r >= 0);
	// Rule a def out entirely. IsAvailable() is maxThisUnit > count, so zero makes
	// every availability check fail wherever it is asked -- factory weights, build
	// chains, role lookups -- rather than needing each of them taught a new rule.
	r = engine->RegisterObjectMethod("CCircuitDef", "void SetMaxThisUnit(int)", asMETHOD(CCircuitDef, SetMaxThisUnit), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "int GetMaxThisUnit() const", asMETHOD(CCircuitDef, GetMaxThisUnit), asCALL_THISCALL); ASSERT(r >= 0);
	// Surface class, so script can ask what a unit needs water FOR. Hover is
	// isSurfer, not isAmphibious -- CircuitDef::fillSurface carries a standing
	// FIXME that it cannot filter hover out, and classifies it by elevation range
	// instead: below water and high above it.
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsAmphibious() const", asMETHOD(CCircuitDef, IsAmphibious), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsFloater() const", asMETHOD(CCircuitDef, IsFloater), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsSurfer() const", asMETHOD(CCircuitDef, IsSurfer), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitDef", "bool IsSubmarine() const", asMETHOD(CCircuitDef, IsSubmarine), asCALL_THISCALL); ASSERT(r >= 0);

	r = engine->RegisterObjectProperty("CCircuitUnit", "const Id id", asOFFSET(CCircuitUnit, id)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitUnit", "const CCircuitDef@ circuitDef", asOFFSET(CCircuitUnit, circuitDef)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "const AIFloat3& GetPos(int)", asMETHODPR(CCircuitUnit, GetPos, (int), const AIFloat3&), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void AddAttribute(Type)", asMETHOD(CCircuitUnit, AddAttribute), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void DelAttribute(Type)", asMETHOD(CCircuitUnit, DelAttribute), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void TglAttribute(Type)", asMETHOD(CCircuitUnit, TglAttribute), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "bool IsAttrAny(Mask) const", asMETHOD(CCircuitUnit, IsAttrAny), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void SetFireState(int)", asMETHOD(CCircuitUnit, TrySetFireState), asCALL_THISCALL); ASSERT(r >= 0);
	// Issue a move order DIRECTLY, bypassing the task system. Expressing commander
	// retreat as a task returned from AiMakeTask lost 0-20 with metal at 6,631:
	// AiMakeTask is the only place the commander gets work, so substituting a
	// retreat task substitutes for everything it would otherwise build. A raw
	// command moves the unit without consuming its task slot.
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdMoveTo(const AIFloat3& in)", asFUNCTION(CCircuitUnit_CmdMoveTo), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdAttackGround(const AIFloat3& in)", asFUNCTION(CCircuitUnit_CmdAttackGround), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "int GetStockpile()", asFUNCTION(CCircuitUnit_GetStockpile), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdStop()", asFUNCTION(CCircuitUnit_CmdStop), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdPatrolTo(const AIFloat3& in)", asFUNCTION(CCircuitUnit_CmdPatrolTo), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitAI", "float GetEnemyAirCostNear(const AIFloat3& in, float)", asFUNCTION(CCircuitAI_GetEnemyAirCostNear), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// apex: for the commander D-gun raid want -- see CCircuitUnit_PushDGun's
	// own comment for why script only needs to get close and push once.
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdCloak(bool)", asFUNCTION(CCircuitUnit_CmdCloak), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void PushDGun(float)", asFUNCTION(CCircuitUnit_PushDGun), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// A factory told to repeat re-queues what it finishes, so a spam lab keeps
	// producing instead of waiting to be handed each unit as a separate task.
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdRepeat(bool)", asFUNCTION(CCircuitUnit_CmdRepeat), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// Build orders straight to a factory, bypassing CRecruitTask entirely. The
	// two schemes cannot share a factory: CRecruitTask::Finish() calls Cancel(),
	// which CmdRemoves every build order still queued, so the first completion
	// under the task scheme wipes a standing queue.
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdBuildUnit(CCircuitDef@, int, bool)", asFUNCTION(CCircuitUnit_CmdBuildUnit), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdBuildQueuedAt(CCircuitDef@, const AIFloat3& in)", asFUNCTION(CCircuitUnit_CmdBuildQueuedAt), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// Reading the factory's own queue. Pass null to count every build order on it.
	r = engine->RegisterObjectMethod("CCircuitUnit", "int CmdQueueSize()", asFUNCTION(CCircuitUnit_CmdQueueSize), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "int CountQueued(CCircuitDef@)", asFUNCTION(CCircuitUnit_CountQueued), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// Jump the queue without clearing it -- how an advanced constructor gets built
	// first when the tier changes.
	r = engine->RegisterObjectMethod("CCircuitUnit", "void CmdInsertBuild(CCircuitDef@, bool)", asFUNCTION(CCircuitUnit_CmdInsertBuild), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	// Health is the missing half of "is this risky". Threat alone said commanders
	// die where the map reads ZERO, because the killer is often at range -- the
	// last plasma shots landing on a commander already running. Health loss is
	// unambiguous and fires whether the shooter is adjacent or far away.
	r = engine->RegisterObjectMethod("CCircuitUnit", "float GetHealthPercent()", asMETHOD(CCircuitUnit, GetHealthPercent), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void SetMoveState(int)", asMETHOD(CCircuitUnit, TrySetMoveState), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "void SelfDestruct(bool)", asMETHOD(CCircuitUnit, CmdSelfD), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CCircuitUnit", "IUnitTask@ const task", asOFFSET(CCircuitUnit, task)); ASSERT(r >= 0);
	// RulesParams accessor on Unit
	r = engine->RegisterObjectMethod("CCircuitUnit", "float GetRulesParam(const string& in, float) const", asFUNCTION(CCircuitUnit_GetRulesParamFloat), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CCircuitUnit", "string GetRulesParam(const string& in, const string& in) const", asFUNCTION(CCircuitUnit_GetRulesParamString), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);

	CSetupManager* setupMgr = circuit->GetSetupManager();
	r = engine->RegisterObjectType("CSetupManager", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CSetupManager aiSetupMgr", setupMgr); ASSERT(r >= 0);
	// AS docs / "Registering object methods" / "Composite members"
	r = engine->RegisterObjectMethod("CSetupManager", "dictionary@ GetModOptions()", asMETHOD(CSetupScript, GetModOptions), asCALL_THISCALL, 0, asOFFSET(CSetupManager, script), true); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CSetupManager", "AIFloat3 GetBasePos() const", asFUNCTION(CSetupManager_GetBasePos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CSetupManager", "void SetLanePos(const AIFloat3& in)", asFUNCTION(CSetupManager_SetLanePos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CSetupManager", "AIFloat3 GetLanePos() const", asFUNCTION(CSetupManager_GetLanePos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
}

CInitScript::~CInitScript()
{
	for (auto& kv : takenContexts) {
		if (kv.second) {
			kv.second->Release();  // dictionary param
		}
		script->ReleaseContext(kv.first);
	}
}

bool CInitScript::InitConfig(const std::string& profile,
		std::vector<std::string>& outCfgParts, CCircuitDef::SArmorInfo& outArmor)
{
	asIScriptEngine* engine = script->GetEngine();
	// FIXME: asASSERT( refCount == 0 ); at lib/angelscript/source/as_configgroup.cpp:157
	//        on exit
//	int r = engine->BeginConfigGroup(CScriptManager::initName.c_str()); ASSERT(r >= 0);
	int r = engine->RegisterObjectType("SArmorInfo", sizeof(CCircuitDef::SArmorInfo), asOBJ_VALUE | asGetTypeTraits<CCircuitDef::SArmorInfo>()); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SArmorInfo", asBEHAVE_CONSTRUCT, "void f()", asFUNCTION(ConstructSArmorInfo), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SArmorInfo", asBEHAVE_CONSTRUCT, "void f(const SArmorInfo& in)", asFUNCTION(ConstructCopySArmorInfo), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SArmorInfo", asBEHAVE_DESTRUCT, "void f()", asFUNCTION(DestructSArmorInfo), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("SArmorInfo", "SArmorInfo &opAssign(const SArmorInfo &in)", asFUNCTION(AssignSArmorInfoToSArmorInfo), asCALL_CDECL_OBJFIRST); assert( r >= 0 );
	r = engine->RegisterObjectMethod("SArmorInfo", "void AddAir(int)", asFUNCTION(AddAirArmor), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("SArmorInfo", "void AddSurface(int)", asFUNCTION(AddSurfaceArmor), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("SArmorInfo", "void AddWater(int)", asFUNCTION(AddWaterArmor), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectType("SCategoryInfo", sizeof(SInitInfo::SCategoryInfo), asOBJ_VALUE | asGetTypeTraits<SInitInfo::SCategoryInfo>()); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SCategoryInfo", asBEHAVE_CONSTRUCT, "void f()", asFUNCTION(ConstructSCategoryInfo), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SCategoryInfo", asBEHAVE_CONSTRUCT, "void f(const SCategoryInfo& in)", asFUNCTION(ConstructCopySCategoryInfo), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SCategoryInfo", asBEHAVE_DESTRUCT, "void f()", asFUNCTION(DestructSCategoryInfo), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("SCategoryInfo", "SCategoryInfo &opAssign(const SCategoryInfo &in)", asFUNCTION(AssignSCategoryInfoToSCategoryInfo), asCALL_CDECL_OBJFIRST); assert( r >= 0 );
	r = engine->RegisterObjectProperty("SCategoryInfo", "string air", asOFFSET(SInitInfo::SCategoryInfo, air)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SCategoryInfo", "string land", asOFFSET(SInitInfo::SCategoryInfo, land)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SCategoryInfo", "string water", asOFFSET(SInitInfo::SCategoryInfo, water)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SCategoryInfo", "string bad", asOFFSET(SInitInfo::SCategoryInfo, bad)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SCategoryInfo", "string good", asOFFSET(SInitInfo::SCategoryInfo, good)); ASSERT(r >= 0);
	r = engine->RegisterObjectType("SInitInfo", sizeof(SInitInfo), asOBJ_VALUE | asGetTypeTraits<SInitInfo>()); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SInitInfo", asBEHAVE_CONSTRUCT, "void f()", asFUNCTION(ConstructSInitInfo), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SInitInfo", asBEHAVE_CONSTRUCT, "void f(const SInitInfo& in)", asFUNCTION(ConstructCopySInitInfo), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SInitInfo", asBEHAVE_DESTRUCT, "void f()", asFUNCTION(DestructSInitInfo), asCALL_CDECL_OBJLAST); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SInitInfo", "SArmorInfo armor", asOFFSET(SInitInfo, armor)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SInitInfo", "SCategoryInfo category", asOFFSET(SInitInfo, category)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SInitInfo", "array<string>@ profile", asOFFSET(SInitInfo, profile)); ASSERT(r >= 0);
//	r = engine->EndConfigGroup(); ASSERT(r >= 0);

	folderName = profile;
	if (!script->Load(CScriptManager::initName.c_str(), folderName, CScriptManager::initName + ".as")) {
		return false;
	}
	asIScriptModule* mod = script->GetEngine()->GetModule(CScriptManager::initName.c_str());
	r = mod->SetDefaultNamespace("Init"); ASSERT(r >= 0);
	asIScriptFunction* init = script->GetFunc(mod, "SInitInfo AiInit()");

	if (init != nullptr) {
		asIScriptContext* ctx = script->PrepareContext(init);
		SInitInfo* result = script->Exec(ctx) ? (SInitInfo*)ctx->GetReturnObject() : nullptr;
		if (result != nullptr) {
			outArmor = result->armor;
			if (outArmor.airTypes.empty()) {
				outArmor.airTypes.push_back(0);  // default
			}
			if (outArmor.surfTypes.empty()) {
				outArmor.surfTypes.push_back(0);  // default
			}
			if (outArmor.waterTypes.empty()) {
				outArmor.waterTypes.push_back(0);  // default
			}

			Game* game = circuit->GetGame();
			circuit->category.air = game->GetCategoriesFlag(result->category.air.c_str());
			circuit->category.land = game->GetCategoriesFlag(result->category.land.c_str());
			circuit->category.water = game->GetCategoriesFlag(result->category.water.c_str());
			circuit->category.bad = game->GetCategoriesFlag(result->category.bad.c_str());
			circuit->category.good = game->GetCategoriesFlag(result->category.good.c_str());

			if (result->profile != nullptr) {
				for (unsigned j = 0; j < result->profile->GetSize(); ++j) {
					outCfgParts.push_back(*(std::string*)result->profile->At(j));
				}
			}
		}
		// NOTE: Init context shouldn't be used again, hence release;
		//       assuming it contains references to unused types.
		script->ReleaseContext(ctx);
	}

	mod->Discard();
	// NOTE: destroys "array<T>". "main" should be registered and loaded first,
	//       then "array<T>" will be in defaultGroup. But main-first is not a viable option.
	//       And re-creating CScriptManager is not worth the effort.
//	r = script->GetEngine()->RemoveConfigGroup(CScriptManager::initName.c_str()); ASSERT(r >= 0);
	return true;
}

void CInitScript::RegisterMgr()
{
	asIScriptEngine* engine = script->GetEngine();

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	int r = engine->RegisterObjectType("CTerrainManager", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CTerrainManager aiTerrainMgr", terrainMgr); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("int AiTerrainWidth()", asFUNCTION(CTerrainManager::GetTerrainWidth), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("int AiTerrainHeight()", asFUNCTION(CTerrainManager::GetTerrainHeight), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("float AiTerrainDiagonal()", asFUNCTION(CTerrainManager::GetTerrainDiagonal), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterGlobalFunction("AIFloat3 AITerrainCenter()", asFUNCTION(CTerrainManager::GetTerrainCenter), asCALL_CDECL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CTerrainManager", "bool IsWaterAVoid() const", asMETHOD(CTerrainManager, IsWaterAVoid), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CTerrainManager", "float GetLandPercent() const", asMETHOD(CTerrainManager, GetLandPercent), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CTerrainManager", "float SetAllyZoneRange(float)", asMETHOD(CTerrainManager, SetAllyZoneRange), asCALL_THISCALL); ASSERT(r >= 0);

	r = engine->RegisterObjectProperty("CSetupManager", "const CCircuitDef@ commChoice", asOFFSET(CSetupManager, commChoice)); ASSERT(r >= 0);

	CEnemyManager* enemyMgr = circuit->GetEnemyManager();
	r = engine->RegisterObjectType("CEnemyManager", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CEnemyManager aiEnemyMgr", enemyMgr); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "float GetEnemyThreat(Type) const", asMETHODPR(CEnemyManager, GetEnemyThreat, (CCircuitDef::RoleT) const, float), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CEnemyManager", "const float mobileThreat", asOFFSET(CEnemyManager, mobileThreat)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "float GetEnemyCost(Type) const", asMETHOD(CEnemyManager, GetEnemyCost), asCALL_THISCALL); ASSERT(r >= 0);
	// GetEnemyCost never forgets: a raider seen once still counts an hour later.
	// The Fresh variants count only what was seen within SetFreshSeconds().
	r = engine->RegisterObjectMethod("CEnemyManager", "float GetEnemyCostFresh(Type) const", asMETHOD(CEnemyManager, GetEnemyCostFresh), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CEnemyManager", "const float freshMobileThreat", asOFFSET(CEnemyManager, freshMobileThreat)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "void SetFreshSeconds(float)", asMETHOD(CEnemyManager, SetFreshSeconds), asCALL_THISCALL); ASSERT(r >= 0);
	// Centroid of the enemy groups we can see. Noisy by nature -- raiders in our
	// own base pull it backwards -- so it suits a rally point, not a facing.
	r = engine->RegisterObjectMethod("CEnemyManager", "AIFloat3 GetEnemyPos() const", asFUNCTION(CEnemyManager_GetEnemyPos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "int GetEnemyGroupCount() const", asFUNCTION(CEnemyManager_GetEnemyGroupCount), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "AIFloat3 GetEnemyGroupPos(int) const", asFUNCTION(CEnemyManager_GetEnemyGroupPos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "float GetEnemyGroupCost(int) const", asFUNCTION(CEnemyManager_GetEnemyGroupCost), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CEnemyManager", "float GetEnemyGroupRange(int) const", asFUNCTION(CEnemyManager_GetEnemyGroupRange), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CEnemyManager", "float maxAAThreat", asOFFSET(CEnemyManager, maxAAThreat)); ASSERT(r >= 0);

	CThreatMap* thrMap = circuit->GetThreatMap();
	r = engine->RegisterObjectType("CThreatMap", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CThreatMap aiThreat", thrMap); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CThreatMap", "void ApplyRange(CCircuitDef@)", asMETHOD(CThreatMap, ApplyRange), asCALL_THISCALL); ASSERT(r >= 0);
}

bool CInitScript::Init()
{
	if (!script->Load(CScriptManager::mainName.c_str(), folderName, CScriptManager::mainName + ".as")) {
		return false;
	}

	asIScriptModule* mod = script->GetEngine()->GetModule(CScriptManager::mainName.c_str());
	int r = mod->SetDefaultNamespace("Main"); ASSERT(r >= 0);
	mainInfo.update = script->GetFunc(mod, "void AiUpdate()");
	mainInfo.luaMessage = script->GetFunc(mod, "void AiLuaMessage(const string& in)");
	mainInfo.receiveMessage = script->GetFunc(mod, "void AiMessage(const string& in, int)");
	mainInfo.unitFinished = script->GetFunc(mod, "void AiUnitFinished(CCircuitUnit@)");
	mainInfo.unitDestroyed = script->GetFunc(mod, "void AiUnitDestroyed(CCircuitUnit@)");
	mainInfo.unitDestroyedBy = script->GetFunc(mod, "void AiUnitDestroyedBy(CCircuitUnit@, CCircuitDef@)");
	mainInfo.enemyDestroyed = script->GetFunc(mod, "void AiEnemyDestroyed(CCircuitDef@, const AIFloat3& in, bool)");
	asIScriptFunction* main = script->GetFunc(mod, "void AiMain()");
	if (main == nullptr) {
		return false;
	}

	asIScriptContext* ctx = script->PrepareContext(main);
	script->Exec(ctx);
	script->ReturnContext(ctx);
	return true;
}

void CInitScript::Update()
{
	if (mainInfo.update == nullptr) {
		return;
	}
	// apex: the host runs every AI's script -- "it makes me lag" gets a number
	// before it gets an optimization. One line per game-minute per player.
	const auto t0 = std::chrono::steady_clock::now();
	asIScriptContext* ctx = script->PrepareContext(mainInfo.update);
	script->Exec(ctx);
	script->ReturnContext(ctx);
	const uint64_t us = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t0).count();
	perfUpdateUs += us;
	perfUpdateMaxUs = std::max(perfUpdateMaxUs, us);
	++perfUpdateCalls;
	const int frame = circuit->GetLastFrame();
	if (frame >= perfNextLog) {
		perfNextLog = frame + 1800;   // one game-minute at 30 fps
		circuit->LOG("apex: perf AiUpdate calls=%u totalMs=%.1f avgUs=%.0f maxMs=%.1f",
				perfUpdateCalls, perfUpdateUs / 1000.f,
				(perfUpdateCalls > 0) ? float(perfUpdateUs) / float(perfUpdateCalls) : 0.f,
				perfUpdateMaxUs / 1000.f);
		perfUpdateUs = 0;
		perfUpdateMaxUs = 0;
		perfUpdateCalls = 0;
	}
}

void CInitScript::LuaMessage(const char* inData)
{
	if (mainInfo.luaMessage == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(mainInfo.luaMessage);
	std::string data(inData);
	ctx->SetArgAddress(0, &data);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

void CInitScript::UnitFinished(CCircuitUnit* unit)
{
	if (mainInfo.unitFinished == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(mainInfo.unitFinished);
	ctx->SetArgObject(0, unit);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

void CInitScript::UnitDestroyed(CCircuitUnit* unit)
{
	if (mainInfo.unitDestroyed == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(mainInfo.unitDestroyed);
	ctx->SetArgObject(0, unit);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

void CInitScript::UnitDestroyedBy(CCircuitUnit* unit, CCircuitDef* attackerDef)
{
	if ((mainInfo.unitDestroyedBy == nullptr) || (unit == nullptr) || (attackerDef == nullptr)) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(mainInfo.unitDestroyedBy);
	ctx->SetArgObject(0, unit);
	ctx->SetArgObject(1, attackerDef);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

void CInitScript::EnemyDestroyed(CCircuitDef* edef, const springai::AIFloat3& pos, bool byUs)
{
	if ((mainInfo.enemyDestroyed == nullptr) || (edef == nullptr)) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(mainInfo.enemyDestroyed);
	ctx->SetArgObject(0, edef);
	ctx->SetArgAddress(1, &const_cast<springai::AIFloat3&>(pos));
	ctx->SetArgByte(2, byUs ? 1 : 0);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

CMaskHandler::TypeMask CInitScript::AddRole(const std::string& name, int actAsRole)
{
	CMaskHandler::TypeMask result = circuit->GetGameAttribute()->GetRoleMasker().GetTypeMask(name);
	if (result.type < 0) {
		return result;
	}
	circuit->BindRole(result.type, actAsRole);
	return result;
}

void CInitScript::Log(const std::string& msg) const
{
	std::lock_guard<spring::mutex> mlock(mtx);
	circuit->LOG("%s", msg.c_str());
}

void CInitScript::AddPoint(const AIFloat3& pos, const std::string& msg) const
{
	circuit->GetDrawer()->AddPoint(pos, msg.c_str());
}

void CInitScript::DelPoint(const AIFloat3& pos) const
{
	circuit->GetDrawer()->DeletePointsAndLines(pos);
}

void CInitScript::Pause(bool enable, const std::string& msg) const
{
	circuit->GetGame()->SetPause(enable, msg.c_str());
}

int CInitScript::Dice(const CScriptArray* array) const
{
	float magnitude = 0.f;
	for (asUINT i = 0; i < array->GetSize(); ++i) {
		magnitude += *static_cast<const float*>(array->At(i));
	}
	float dice = (float)rand() / RAND_MAX * magnitude;
	for (asUINT i = 0; i < array->GetSize(); ++i) {
		dice -= *static_cast<const float*>(array->At(i));
		if (dice < 0.f) {
			return i;
		}
	}
	return -1;
}

void CInitScript::SendMessage(const std::string& msg, int toTeamId)
{
	// NOTE: Can access ai->script because of "friend class CInitScript;"
	if (toTeamId < 0) {
		for (CCircuitAI* ai : circuit->GetGameAttribute()->GetCircuits()) {
			if (ai->IsInitialized()
				&& (ai->GetTeamId() != circuit->GetTeamId())
				&& (ai->GetAllyTeamId() == circuit->GetAllyTeamId())
				&& ai->script->mainInfo.receiveMessage != nullptr)
			{
				int fromTeamId = circuit->GetTeamId();
				ai->GetScheduler()->RunJobAfter(CScheduler::GameJob([ai, msg, fromTeamId]() {
					ai->script->ReceiveMessage(msg, fromTeamId);
				}));
			}
		}
	} else {
		for (CCircuitAI* ai : circuit->GetGameAttribute()->GetCircuits()) {
			if (ai->IsInitialized()
				&& (ai->GetTeamId() == toTeamId)
				&& (ai->GetAllyTeamId() == circuit->GetAllyTeamId())
				&& ai->script->mainInfo.receiveMessage != nullptr)
			{
				int fromTeamId = circuit->GetTeamId();
				ai->GetScheduler()->RunJobAfter(CScheduler::GameJob([ai, msg, fromTeamId]() {
					ai->script->ReceiveMessage(msg, fromTeamId);
				}));
				return;
			}
		}
	}
}

void CInitScript::ReceiveMessage(const std::string& msg, int fromTeamId)
{
	// NOTE: Check done in CInitScript::SendMessage
//	if (mainInfo.receiveMessage == nullptr) {
//		return;
//	}
	asIScriptContext* ctx = script->PrepareContext(mainInfo.receiveMessage);
	ctx->SetArgAddress(0, &const_cast<std::string&>(msg));
	ctx->SetArgDWord(1, fromTeamId);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

void CInitScript::Run(asIScriptFunction* exec, CScriptDictionary* arg)
{
	// NOTE: If engines created in threads:
	// asPrepareMultithread, asUnprepareMultithread, asThreadCleanup, asGetThreadManager;
	// asAtomicInc, asAtomicDec, asAcquireExclusiveLock, asReleaseExclusiveLock, asAcquireSharedLock, asReleaseSharedLock;
	// ensure garbage collection behaviours are thread safe.
	if (exec == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->RequestContext();  // in main thread to avoid mutexes
	takenContexts[ctx] = arg;
	circuit->GetScheduler()->RunParallelJob(CScheduler::WorkJob([this, ctx, exec, arg]() {
		int r = ctx->Prepare(exec); ASSERT(r >= 0);
		ctx->SetArgObject(0, arg);
		script->Exec(ctx);
		asIScriptFunction* finish = (asIScriptFunction*)ctx->GetReturnObject();
		if (finish != nullptr) {
			r = ctx->Prepare(finish); ASSERT(r >= 0);
			ctx->SetArgObject(0, arg);
		}
		return CScheduler::GameJob([this, ctx, finish, arg]() {
			takenContexts.erase(ctx);
			if (finish != nullptr) {
				script->Exec(ctx);
			}
			if (arg) {
				arg->Release();
			}
			script->ReturnContext(ctx);
		});
	}));
}

} // namespace circuit
