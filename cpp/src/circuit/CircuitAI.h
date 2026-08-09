/*
 * Circuit.h
 *
 *  Created on: Aug 9, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_CIRCUIT_H_
#define SRC_CIRCUIT_CIRCUIT_H_

#include "unit/CircuitDef.h"
#include "unit/CircuitWDef.h"
#include "unit/ally/AllyTeam.h"
#include "util/Defines.h"

#include <memory>
#include <unordered_map>
#include <map>
#include <set>
#include <vector>

struct SSkirmishAICallback;

namespace circuit {

#define ERROR_UNKNOWN			200
#define ERROR_INIT				(ERROR_UNKNOWN + EVENT_INIT)
#define ERROR_RELEASE			(ERROR_UNKNOWN + EVENT_RELEASE)
#define ERROR_UPDATE			(ERROR_UNKNOWN + EVENT_UPDATE)
#define ERROR_UNIT_CREATED		(ERROR_UNKNOWN + EVENT_UNIT_CREATED)
#define ERROR_UNIT_FINISHED		(ERROR_UNKNOWN + EVENT_UNIT_FINISHED)
#define ERROR_UNIT_IDLE			(ERROR_UNKNOWN + EVENT_UNIT_IDLE)
#define ERROR_UNIT_MOVE_FAILED	(ERROR_UNKNOWN + EVENT_UNIT_MOVE_FAILED)
#define ERROR_UNIT_DAMAGED		(ERROR_UNKNOWN + EVENT_UNIT_DAMAGED)
#define ERROR_UNIT_DESTROYED	(ERROR_UNKNOWN + EVENT_UNIT_DESTROYED)
#define ERROR_UNIT_GIVEN		(ERROR_UNKNOWN + EVENT_UNIT_GIVEN)
#define ERROR_UNIT_CAPTURED		(ERROR_UNKNOWN + EVENT_UNIT_CAPTURED)
#define ERROR_ENEMY_ENTER_LOS	(ERROR_UNKNOWN + EVENT_ENEMY_ENTER_LOS)
#define ERROR_ENEMY_LEAVE_LOS	(ERROR_UNKNOWN + EVENT_ENEMY_LEAVE_LOS)
#define ERROR_ENEMY_ENTER_RADAR	(ERROR_UNKNOWN + EVENT_ENEMY_ENTER_RADAR)
#define ERROR_ENEMY_LEAVE_RADAR	(ERROR_UNKNOWN + EVENT_ENEMY_LEAVE_RADAR)
#define ERROR_ENEMY_DAMAGED		(ERROR_UNKNOWN + EVENT_ENEMY_DAMAGED)
#define ERROR_ENEMY_DESTROYED	(ERROR_UNKNOWN + EVENT_ENEMY_DESTROYED)
#define ERROR_LOAD				(ERROR_UNKNOWN + EVENT_LOAD)
#define ERROR_SAVE				(ERROR_UNKNOWN + EVENT_SAVE)
#define ERROR_ENEMY_CREATED		(ERROR_UNKNOWN + EVENT_ENEMY_CREATED)
#define LOG(fmt, ...)	GetLog()->DoLog(utils::string_format(std::string(fmt), ##__VA_ARGS__).c_str())

class CGameAttribute;
class CSetupManager;
class CEnemyManager;
class CMapManager;
class CThreatMap;
class CInfluenceMap;
class CPathFinder;
class CTerrainManager;
class CBuilderManager;
class CFactoryManager;
class CEconomyManager;
class CMilitaryManager;
class CScriptManager;
class CInitScript;
class CScheduler;
class IModule;
class CCircuitUnit;
class CEnemyInfo;
class COOAICallback;
class CEngine;
class CMap;
#ifdef DEBUG_VIS
class CDebugDrawer;
#endif

extern const char version[];

class CException: public std::exception {
public:
	CException(const char* r) : std::exception(), reason(r) {}
	virtual const char* what() const throw() {
		return reason;
	}
	const char* reason;
};

class CCircuitAI {
public:
	CCircuitAI(springai::OOAICallback* callback);
	virtual ~CCircuitAI();

// >>> AI Event handler ---- BEGIN
public:
	int HandleEvent(int topic, const void* data);
	void NotifyGameEnd();
	void NotifyResign();
	void Resign(int newTeamId);
	void MobileSlave(int newTeamId);
private:
	typedef int (CCircuitAI::*EventHandlerPtr)(int topic, const void* data);
	int HandleGameEvent(int topic, const void* data);
	int HandleEndEvent(int topic, const void* data);
	int HandleResignEvent(int topic, const void* data);
	EventHandlerPtr eventHandler;

	int ownerTeamId;
	springai::Economy* economy;
	springai::Resource* metalRes;
	springai::Resource* energyRes;
// <<< AI Event handler ---- END

private:
	std::string ValidateMod();
	void CheatPreload();
	int Init(int skirmishAIId, const struct SSkirmishAICallback* sAICallback);
	int Release(int reason);
	int Update(int frame);
	int Message(int playerId, const char* message);
	int UnitCreated(CCircuitUnit* unit, CCircuitUnit* builder);
	int UnitFinished(CCircuitUnit* unit);
	int UnitIdle(CCircuitUnit* unit);
	int UnitMoveFailed(CCircuitUnit* unit);
	int UnitDamaged(CCircuitUnit* unit, ICoreUnit::Id attackerId, int weaponId, springai::AIFloat3 dir);
	int UnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker);
	int UnitGiven(ICoreUnit::Id unitId, int oldTeamId, int newTeamId);
	int UnitCaptured(ICoreUnit::Id unitId, int oldTeamId, int newTeamId);
	int EnemyEnterLOS(CEnemyInfo* enemy);
	int EnemyLeaveLOS(CEnemyInfo* enemy);
	int EnemyEnterRadar(CEnemyInfo* enemy);
	int EnemyLeaveRadar(CEnemyInfo* enemy);
	int EnemyDamaged(CEnemyInfo* enemy);
	int EnemyDestroyed(CEnemyInfo* enemy);
	int PlayerCommand(const std::vector<CCircuitUnit*>& units);
//	int CommandFinished(CCircuitUnit* unit, int commandTopicId, springai::Command* cmd);
	int Load(std::istream& is);
	int Save(std::ostream& os);
	int LuaMessage(const char* inData);

	bool InitSide();
public:
	void SetSide(const std::string& name);

// >>> Units ---- BEGIN
public:
	using Units = std::map<ICoreUnit::Id, CCircuitUnit*>;
private:
	CCircuitUnit* GetOrRegTeamUnit(ICoreUnit::Id unitId);
	CCircuitUnit* RegisterTeamUnit(ICoreUnit::Id unitId);
	CCircuitUnit* RegisterTeamUnit(ICoreUnit::Id unitId, springai::Unit* u);
	void UnregisterTeamUnit(CCircuitUnit* unit);
	void DeleteTeamUnit(CCircuitUnit* unit);
public:
	void GiveUnits(std::vector<CCircuitUnit*>&& units, int newTeamId);
	// apex: send metal/energy to an allied team. The engine command has always
	// existed (COMMAND_SEND_RESOURCES) and CircuitAI already uses it when
	// resigning, but it was never reachable from AngelScript -- so a team of
	// AIs had no way to pool resources behind one player. Enables "slinging":
	// feed one commander so it reaches T2 far sooner than four independent
	// economies would.
	void SendResources(float metal, float energy, int toTeamId);
	// How full another team's metal storage is, 0..1. Needed so a feeder can
	// tell whether the player it is slinging to actually needs the metal --
	// sending to someone already near cap just wastes it.
	float GetTeamMetalFill(int otherTeamId) const;
	float GetTeamMetalIncome(int otherTeamId) const;

	// --- experiment tunables ---------------------------------------------
	// A combat constant read from a game rules param instead of a #define, so
	// one DLL can serve every arm of an A/B run and the arm is chosen by a
	// modoption on the match command line. Rebuilding to change a constant made
	// each measurement a Docker build; the arena resolves a 2v2 matchup in about
	// a minute, so the build dominated the experiment.
	//
	// The default is returned whenever the publishing gadget is absent, which is
	// every non-harness game, so behaviour off the bench is unchanged. Values
	// are cached on first read: this sits inside the per-unit attack loop.
	float GetTunable(const char* name, float defVal) const;

	// --- in-process team coordination -----------------------------------
	// Every AI the host adds lives in ONE process (AIExport.cpp keeps them in
	// `myAIs`, and CGameAttribute::GetCircuits() hands out the live set), so
	// instances can read each other directly. That matters because the only
	// other channel -- game rules params published by a synced gadget -- cannot
	// ship to a multiplayer game: synced Lua must exist on every client.
	// These replace that channel. Policy stays in AngelScript; C++ supplies only
	// the facts a script cannot otherwise reach.

	// Highest build progress among OUR units of `def`, 0..1, or -1 when we own
	// none. Counts nanoframes, which is the point: the tech lead is whoever has
	// committed to an advanced plant, not whoever has finished one.
	float GetDefBuildProgress(CCircuitDef* def) const;
	// Shared blackboard, keyed (teamId, key), written under our own teamId.
	// Plain floats, and they never leave this process.
	void PublishTeamValue(const std::string& key, float value);
	float ReadTeamValue(int otherTeamId, const std::string& key, float defVal) const;
	springai::AIFloat3 GetBestWreckPos(const springai::AIFloat3& pos, float radius, float minMetal);
	float GetWreckValueAt(const springai::AIFloat3& pos, float radius);
	bool IsCommanderWreck(springai::Feature* f);
	// Recent kills/losses by metal value; see NoteTrade in the .cpp.
	void NoteTrade(bool isKill, CCircuitDef* cdef);
	// WHERE we are losing units, as a cost-weighted decaying centroid. The AI
	// had no location for incoming attacks at all -- ApproachThreat() is a
	// global scalar -- so defence was placed by geometry alone.
	void NoteLossAt(const springai::AIFloat3& pos, float costM);
	bool GetAttackHotspot(springai::AIFloat3& outPos, float& outWeight);
	// BWEM chokepoints. Computed every game by CGridAnalyzer and, until now,
	// reachable from nowhere: DefenceData pushes them into defPoints but every
	// consumer selects via GetDefIndices(cluster), which only ever indexes the
	// metal-cluster points, and the search-tree path that could reach them is
	// commented out behind a FIXME.
	int GetChokePointCount() const;
	springai::AIFloat3 GetChokePointPos(int idx) const;
	// Width of the gap, i.e. |end1 - end2|. CChokePoint keeps this as a private
	// `size`; only IsSmall() (< 300) is public, so recompute from the ends.
	float GetChokePointWidth(int idx) const;
	bool GetChokePointEnds(int idx, springai::AIFloat3& outEnd1, springai::AIFloat3& outEnd2) const;
	// The two areas this chokepoint joins; -1 if absent.
	int GetChokePointArea(int idx, int which) const;
	// Influence at a position. CInfluenceMap::PosToXZ does NO bounds checking --
	// it indexes enemyInfl[z * width + x] straight from the raw position, the
	// same unchecked pattern that made GetBuilderThreatAt kill the engine at
	// frame 3 on an off-map read. These guard; the raw ones must never be bound.
	bool IsPosOnMap(const springai::AIFloat3& pos) const;
	// The front line, handed down from script. Army positions were selected
	// exclusively from metal-cluster defPoints, so squads had no position that
	// meant "the line" and orbited bases instead of holding ground.
	void SetFrontPos(const springai::AIFloat3& pos) { frontPos = pos; }
	const springai::AIFloat3& GetFrontPos() const { return frontPos; }
	bool HasFrontPos() const { return frontPos.x >= 0.f; }
	// The base layout, handed down from script the same way the front line is.
	//
	// Every structure placement was a position plus a shake radius, and Execute
	// jittered the position anywhere inside that radius before searching. There
	// was no footprint, no rows and no lanes, so the radius could only trade
	// sprawl against self-walling. Script owns the frame; this snaps to it.
	void SetBaseGrid(const springai::AIFloat3& anchor, const springai::AIFloat3& fwd,
			float cell, float lanePitch, float laneHalf, float range);
	bool SnapToBaseGrid(const springai::AIFloat3& pos, springai::AIFloat3& outPos) const;
	// In-game map markers, for watching what the AI believes. These are ordinary
	// map points/lines: allies and spectators see them, so anything using these
	// must stay off by default outside a debug watch.
	void DrawPoint(const springai::AIFloat3& pos, const std::string& label);
	void DrawLine(const springai::AIFloat3& from, const springai::AIFloat3& to);
	void DrawErase(const springai::AIFloat3& pos);
	float GetAllyInflAt(const springai::AIFloat3& pos) const;
	float GetEnemyInflAt(const springai::AIFloat3& pos) const;
	float GetNetInflAt(const springai::AIFloat3& pos) const;
	float GetRecentTradeRatio();
	// Multiplier on the engage margin, set from AngelScript. 1.0 = unchanged.
	// Below 1 the AI accepts worse odds; this is how a coordinated team push
	// is expressed, since the margin itself lives in C++.
	void SetEngageBoost(float v) { engageBoost = (v > 0.05f) ? v : 0.05f; }
	float GetEngageBoost() const { return engageBoost; }
	// Committed: the team is punching through a line and units must NOT peel off
	// to heal or regroup. apexearth: "they need to commit AND be successful...
	// if we back off we certainly won't succeed." Read by IFighterTask's retreat
	// check. Kept as a plain strategic flag rather than a per-unit override so
	// script can express "we are all-in now" in one call.
	// A position `def` can ACTUALLY be built on, near `pos`, or -RgtVector.
	// Script defence positions come from raw geometry and 9 of 10 defence tasks
	// died having never resolved a build site; this lets the script ask the
	// engine the same question CBFactoryTask asks, before enqueuing.
	springai::AIFloat3 FindBuildSiteNear(CCircuitDef* def, const springai::AIFloat3& pos, float radius);
	void SetCommitted(bool v) { isCommitted = v; }
	bool IsCommitted() const { return isCommitted; }
	// A large building could not be placed. Reported, not acted on: what to
	// clear out of the way is a policy question and lives in AngelScript.
	void NoteBuildBlocked(const springai::AIFloat3& pos);
	bool GetBlockedBuildPos(springai::AIFloat3& outPos);
	// Our own units of `def` within radius of pos. The script can see a def's
	// count but has no way to reach the instances.
	std::vector<CCircuitUnit*> GetOwnUnitsOfDef(CCircuitDef* def, const springai::AIFloat3& pos, float radius);
	// Every finished structure of ours near pos, whatever its def. A name list
	// cannot answer "what of ours is standing in the way" -- it only answers it
	// for the factions someone remembered to list.
	std::vector<CCircuitUnit*> GetOwnStructsNear(const springai::AIFloat3& pos, float radius);
	// Engine path length for this unit's move type, or -1 when there is no path.
	// CircuitAI's own areas come from CTerrainData and are terrain-only, so a
	// pocket walled in by BUILDINGS is invisible to CanMoveToPos. The engine's
	// path manager reads the synced blocking map, structures included, which is
	// the only oracle here that can see one.
	float GetPathLength(CCircuitUnit* unit, const springai::AIFloat3& to);
	float GetEnemyCostAt(const springai::AIFloat3& pos, float radius) const;
	float GetBuilderThreatAt(const springai::AIFloat3& pos) const;
	float GetUnitThreatAt(CCircuitUnit* unit, const springai::AIFloat3& pos) const;
	void Garbage(CCircuitUnit* unit, const char* reason);
	CCircuitUnit* GetTeamUnit(ICoreUnit::Id unitId) const;
	const Units& GetTeamUnits() const { return teamUnits; }

	void UpdateFriendlyUnits() { allyTeam->UpdateFriendlyUnits(); }
	CAllyUnit* GetFriendlyUnit(springai::Unit* u) const;
	CAllyUnit* GetFriendlyUnit(ICoreUnit::Id unitId) const { return allyTeam->GetFriendlyUnit(unitId); }
	const CAllyTeam::AllyUnits& GetFriendlyUnits() const { return allyTeam->GetFriendlyUnits(); }
	std::pair<CAllyUnit*, bool> GetTeamOrAllyUnit(springai::Unit* u) const;

	using EnemyInfos = std::map<ICoreUnit::Id, CEnemyInfo*>;
private:
	mutable std::map<std::string, float> tunables;  // see GetTunable

	std::pair<CEnemyInfo*, bool> RegisterEnemyInfo(ICoreUnit::Id unitId, bool isInLOS = false);
	CEnemyInfo* RegisterEnemyInfo(springai::Unit* e);
	void UnregisterEnemyInfo(CEnemyInfo* enemy);
	void CreateFakeEnemy(int weaponId, const springai::AIFloat3& startPos, const springai::AIFloat3& dir);
	void CheckDecoy(CEnemyInfo* enemy, int weaponId);
public:
	CEnemyInfo* GetEnemyInfo(ICoreUnit::Id unitId) const;
	const EnemyInfos& GetEnemyInfos() const { return enemyInfos; }

	CAllyTeam* GetAllyTeam() const { return allyTeam; }

	bool UnitControl(CCircuitUnit* unit, bool isEnable);
	bool UnitControl(ICoreUnit::Id unitId, bool isEnable) { return UnitControl(GetTeamUnit(unitId), isEnable); }

	void AddActionUnit(CCircuitUnit* unit) { actionUnits.push_back(unit); }

private:
	void UpdateActions();

	Units teamUnits;  // owner
	EnemyInfos enemyInfos;  // owner
	CAllyTeam* allyTeam;
	bool isAllyTeamInit;

	std::vector<CCircuitUnit*> actionUnits;
	unsigned int actionIterator;

	std::set<CCircuitUnit*> garbage;
// <<< Units ---- END

// >>> AIOptions.lua ---- BEGIN
public:
	bool IsCheating() const { return isCheating; }
	bool IsAllyAware() const { return isAllyAware; }  // mark ally buildings, check taken mexes
	bool IsCommMerge() const { return isCommMerge; }
	bool IsAllyBaseAvoid() const { return isAllyBaseAvoid; }  // avoid building in allied bases
private:
	std::string InitOptions();
	bool isCheating;
	bool isAllyAware;
	bool isCommMerge;
	bool isAllyBaseAvoid;
// <<< AIOptions.lua ---- END

// >>> Recent trade record ---- BEGIN
private:
	#define TRADE_DECAY_PERIOD	(FRAMES_PER_SEC * 30)
	#define TRADE_DECAY			0.75f   // ~2 min half-life at the period above
	#define TRADE_MIN_SAMPLE	600.f   // metal traded before the ratio means anything
	float tradeKilled = .0f;
	float tradeLost = .0f;
	int tradeDecayFrame = 0;
	// Where a large building last failed to find a site, and when. Expires so
	// the script never acts on a stale report.
	#define BLOCKED_BUILD_TTL	(FRAMES_PER_SEC * 30)
	springai::AIFloat3 blockedBuildPos = -RgtVector;
	int blockedBuildFrame = -1000000;
	// def id -> engine pathType. UnitDef::GetMoveData() allocates a wrapper the
	// caller must delete, so the lookup is done once per def.
	std::map<int, int> pathTypes;
	float engageBoost = 1.f;
	springai::AIFloat3 frontPos = -RgtVector;
	// Base grid, published by script. cell <= 0 means "no grid yet".
	springai::AIFloat3 gridAnchor = -RgtVector;
	springai::AIFloat3 gridFwd = ZeroVector;
	float gridCell = .0f;
	float gridLanePitch = .0f;
	float gridLaneHalf = .0f;
	float gridRange = .0f;
	#define HOT_DECAY_PERIOD	(FRAMES_PER_SEC * 20)
	#define HOT_DECAY			0.80f   // ~1 min half-life
	#define HOT_MIN_WEIGHT		250.f   // metal lost before the spot means anything
	springai::AIFloat3 hotSum = ZeroVector;   // cost-weighted position sum
	float hotWeight = .0f;
	int hotDecayFrame = 0;
	bool isCommitted = false;
// <<< Recent trade record ---- END

// >>> UnitDefs ---- BEGIN
public:
	using CircuitDefs = std::vector<CCircuitDef>;  // UnitDefId=0 is not valid, @see rts/Sim/Units/UnitDefHandler.h
	using NamedDefs = std::map<const char*, CCircuitDef*, cmp_str>;

	/*const */CircuitDefs& GetCircuitDefs() /*const */{ return defsById; }
	CCircuitDef* GetCircuitDef(const char* name);
	bool IsValidUnitDefId(CCircuitDef::Id unitDefId) const {
		return /*(unitDefId > 0) && */((size_t)unitDefId < defsById.size());
	}
	CCircuitDef* GetCircuitDef(CCircuitDef::Id unitDefId) {
		return &defsById[unitDefId - 1];
	}
	CCircuitDef* GetCircuitDefSafe(CCircuitDef::Id unitDefId) {
		return IsValidUnitDefId(unitDefId) ? &defsById[unitDefId - 1] : nullptr;
	}
	int GetDefCount() const { return defsById.size(); }
	void BindRole(CCircuitDef::RoleT role, CCircuitDef::RoleT actAsRole) {
		roleBind[role] = actAsRole;
	}
	CCircuitDef::RoleT GetBindedRole(CCircuitDef::RoleT role) const {
		return roleBind[role];
	}
private:
	void InitRoles();
	void InitUnitDefs(const CCircuitDef::SArmorInfo& armor, float& outDcr);
	CircuitDefs defsById;  // owner
	NamedDefs defsByName;
	std::array<CCircuitDef::RoleT, CMaskHandler::GetMaxMasks()> roleBind;
// <<< UnitDefs ---- END

// >>> WeaponDefs ---- BEGIN
public:
	using WeaponDefs = std::vector<CWeaponDef>;

	bool IsValidWeaponDefId(CWeaponDef::Id weaponDefId) const {
		return (weaponDefId >= 0) && ((size_t)weaponDefId < weaponDefs.size());
	}
	CWeaponDef* GetWeaponDef(CWeaponDef::Id weaponDefId) {
		return &weaponDefs[weaponDefId];
	}
	CWeaponDef* GetWeaponDefSafe(CWeaponDef::Id weaponDefId) {
		return IsValidWeaponDefId(weaponDefId) ? &weaponDefs[weaponDefId] : nullptr;
	}
	void BindUnitToWeaponDefs(CCircuitDef::Id unitDefId, const std::set<CWeaponDef::Id>& weaponDefs, bool isMobile);
private:
	void InitWeaponDefs();
	WeaponDefs weaponDefs;  // owner
	struct SWeaponToUnitDef {
		std::set<CCircuitDef::Id> ids;
		std::set<CCircuitDef::Id> mobileIds;
		std::set<CCircuitDef::Id> staticIds;
	};
	std::vector<SWeaponToUnitDef> weaponToUnitDefs;  // weapon (id=index) to unit defs
// <<< WeaponDefs ---- END

public:
	bool IsInitialized() const { return isInitialized; }
	bool IsSavegame() const { return isSavegame; }
	bool IsLoadSave() const { return isLoadSave; }
	CGameAttribute* GetGameAttribute() const { return gameAttribute.get(); }
	const std::shared_ptr<CScheduler>& GetScheduler() { return scheduler; }
	int GetLastFrame()    const { return lastFrame; }
	int GetSkirmishAIId() const { return skirmishAIId; }
	int GetTeamId()       const { return teamId; }
	int GetAllyTeamId()   const { return allyTeamId; }
	SideType GetSideId()             const { return sideId; }
	const std::string& GetSideName() const { return sideName; }

	COOAICallback*        GetCallback()   const { return callback.get(); }
	CEngine*              GetEngine()     const { return engine.get(); }
	springai::Cheats*     GetCheats()     const { return cheats.get(); }
	springai::Log*        GetLog()        const { return log.get(); }
	springai::Game*       GetGame()       const { return game.get(); }
	CMap*                 GetMap()        const { return map.get(); }
	springai::Lua*        GetLua()        const { return lua.get(); }
	springai::Pathing*    GetPathing()    const { return pathing.get(); }
	springai::Drawer*     GetDrawer()     const { return drawer.get(); }
	springai::SkirmishAI* GetSkirmishAI() const { return skirmishAI.get(); }
	springai::Team*       GetTeam()       const { return team.get(); }
	CScriptManager*   GetScriptManager()   const { return scriptManager.get(); }
	CSetupManager*    GetSetupManager()    const { return setupManager.get(); }
	CEnemyManager*    GetEnemyManager()    const { return enemyManager.get(); }
	CMetalManager*    GetMetalManager()    const { return metalManager.get(); }
	CEnergyManager*   GetEnergyManager()   const { return energyManager.get(); }
	CMapManager*      GetMapManager()      const { return mapManager.get(); }
	CThreatMap*       GetThreatMap()       const;
	CInfluenceMap*    GetInflMap()         const;
	CPathFinder*      GetPathfinder()      const { return pathfinder.get(); }
	CTerrainManager*  GetTerrainManager()  const { return terrainManager.get(); }
	CBuilderManager*  GetBuilderManager()  const { return builderManager.get(); }
	CFactoryManager*  GetFactoryManager()  const { return factoryManager.get(); }
	CEconomyManager*  GetEconomyManager()  const { return economyManager.get(); }
	CMilitaryManager* GetMilitaryManager() const { return militaryManager.get(); }

	int GetAirCategory()    const { return category.air; }
	int GetLandCategory()   const { return category.land; }
	int GetWaterCategory()  const { return category.water; }
	int GetBadCategory()    const { return category.bad; }
	int GetGoodCategory()   const { return category.good; }

	bool IsSlave() const { return isSlave; }

	int GetEnemyTeamSize() const;

private:
	bool isInitialized : 1;
	bool isSavegame : 1;
	bool isLoadSave : 1;
	bool isResigned : 1;
	bool isSlave : 1;
	int lastFrame;
	int skirmishAIId;
	int teamId;
	int allyTeamId;
	SideType sideId;
	std::string sideName;
	std::shared_ptr<IMainJob> mergeTask;

	std::unique_ptr<COOAICallback>        callback;
	std::unique_ptr<CEngine>              engine;
	std::unique_ptr<springai::Cheats>     cheats;
	std::unique_ptr<springai::Log>        log;
	std::unique_ptr<springai::Game>       game;
	std::unique_ptr<CMap>                 map;
	std::unique_ptr<springai::Lua>        lua;
	std::unique_ptr<springai::Pathing>    pathing;
	std::unique_ptr<springai::Drawer>     drawer;
	std::unique_ptr<springai::SkirmishAI> skirmishAI;
	std::unique_ptr<springai::Team>       team;

	static std::unique_ptr<CGameAttribute> gameAttribute;
	static unsigned int gaCounter;
	void CreateGameAttribute();
	void DestroyGameAttribute();
	std::shared_ptr<CScheduler> scheduler;
	std::shared_ptr<CScriptManager> scriptManager;
	std::shared_ptr<CSetupManager> setupManager;
	std::shared_ptr<CEnemyManager> enemyManager;
	std::shared_ptr<CMetalManager> metalManager;
	std::shared_ptr<CEnergyManager> energyManager;
	std::shared_ptr<CMapManager> mapManager;
	std::shared_ptr<CPathFinder> pathfinder;
	std::shared_ptr<CTerrainManager> terrainManager;
	std::shared_ptr<CBuilderManager> builderManager;
	std::shared_ptr<CFactoryManager> factoryManager;
	std::shared_ptr<CEconomyManager> economyManager;
	std::shared_ptr<CMilitaryManager> militaryManager;
	std::vector<std::shared_ptr<IModule>> modules;

	friend class CInitScript;
	CInitScript* script;  // owner
	struct SCategoryInfo {
		int air;  // over surface
		int land;  // on surface
		int water;  // under surface
		int bad;
		int good;
	} category;  // TODO: Move into GameAttribute? Or use locally

public:
	void PrepareAreaUpdate();

#ifdef DEBUG_VIS
private:
	std::shared_ptr<CDebugDrawer> debugDrawer;
public:
	std::shared_ptr<CDebugDrawer>& GetDebugDrawer() { return debugDrawer; }
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_CIRCUIT_H_
