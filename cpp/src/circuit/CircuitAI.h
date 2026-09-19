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
#include <algorithm>
#include <limits>
#include <set>
#include <vector>
#include <chrono>
#include <mutex>
#include <cstdio>

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
// apex: the engine's log call feeds the infolog AND the in-game chat widget,
// which keeps every line forever (S31); ordinary lines go to our own file next
// to the infolog and the harness merges them back by frame. LOG_ENGINE is for
// what must be seen without the merge: compile errors, exceptions, the path.
#define LOG(fmt, ...)	LogLine(utils::string_format(std::string(fmt), ##__VA_ARGS__).c_str())
#define LOG_ENGINE(fmt, ...)	GetLog()->DoLog(utils::string_format(std::string(fmt), ##__VA_ARGS__).c_str())

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
class IRefCounter;
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
	// apex: enrol/release in the set-target holder census. See tgtHeld.
	void TgtHoldAdd(CCircuitUnit* unit) { tgtHeld.insert(unit); }
	void TgtHoldDel(CCircuitUnit* unit) { tgtHeld.erase(unit); }
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
	float GetFieldWorkAt(const springai::AIFloat3& pos, float radius);
	springai::AIFloat3 GetBestRezPos(const springai::AIFloat3& pos, float radius, float minCost);  // resurrectable wreck worth the most as a unit  // rez bot work: a resurrectable wreck at its unit's cost, else its reclaim metal
	// apex: per-featureDef constants, resolved once. See GetFeatDefInfo.
	struct SFeatDefInfo {
		float metal;      // FeatureDef contained metal; < 0 means "not resolved yet"
		float rezCostM;   // the unit this corpse rezzes into, by cost; < 0 if none
	};
	const SFeatDefInfo& GetFeatDefInfo(int featureDefId);
	bool IsCommanderWreckId(int rezDefId);
	// apex: nearest commander corpse inside the circle, -RgtVector if none.
	springai::AIFloat3 GetCommanderWreckPos(const springai::AIFloat3& pos, float radius);
	int GetMetalResId();
	// Track record: damage each unit type dealt against its own health,
	// carried across games in the AI's data dir. Fodder and fighters are the
	// script's business; this only measures.
	void RecordDealt(ICoreUnit::Id attacker, float damage);
	void RecordFold(CCircuitUnit* unit, bool died);
	float RecordRatio(CCircuitDef* cdef) const;
	int RecordCount(CCircuitDef* cdef) const;
	// Recent kills/losses by metal value; see NoteTrade in the .cpp.
	void NoteTrade(bool isKill, CCircuitDef* cdef);
	// WHERE we are losing units, cost-weighted and decaying. The AI had no
	// location for incoming attacks at all -- ApproachThreat() is a global
	// scalar -- so defence was placed by geometry alone.
	void NoteLossAt(const springai::AIFloat3& pos, float costM);
	bool GetAttackHotspot(springai::AIFloat3& outPos, float& outWeight);
	// One place we are being hit. Several fights run at once, so the losses are
	// kept as a small set of spots rather than one centroid: two breaches
	// averaged to a point between them that was neither.
	struct SHotSpot {
		springai::AIFloat3 pos = ZeroVector;
		float weight = .0f;
	};
	// Decayed as a side effect, exactly as GetAttackHotspot is.
	const std::vector<SHotSpot>& GetHotSpots();
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
	// Ground height, bounds-guarded. SAreaData::GetElevationAt indexes its
	// heightmap straight from the position with no check, same hazard as above.
	float GetElevationAt(const springai::AIFloat3& pos) const;
	// Read a file from the VFS (game archive, map archive). Empty on failure.
	// The one door onto content the engine does not otherwise hand an AI --
	// used to read a map's lava schedule rather than learn it a crest at a time.
	static const int MAX_VFS_READ = 1 << 20;
	std::string ReadVfsFile(const std::string& name) const;
	// THE LAVA TIDE. BAR's map_lava gadget publishes its current surface height
	// as the public game rules param "lavaLevel" -- the very number it damages
	// against -- and removes itself entirely on a map without lava, so the
	// param never appears and this stays at NO_LAVA. Cached per frame: the site
	// predicate asks it per candidate cell.
	//
	// Script owns the interesting half (how fast it climbs, when it gets here,
	// what that does to a build's price -- manager/lava.as). This is only the
	// hard floor: ground that is under the surface RIGHT NOW takes damage per
	// second, and nothing may be sited there.
	static constexpr float NO_LAVA = -99998.f;
	float GetLavaLevel() const;
	bool HasLava() const { return GetLavaLevel() > NO_LAVA; }
	bool IsUnderLava(const springai::AIFloat3& pos, CCircuitDef* def) const;
	// The tide's proven high-water mark, handed down from script the same way
	// the front line and the base grid are -- the level a climb reached and
	// held, which script learns by watching and C++ has no way to derive.
	// NO_LAVA until a crest has been seen (or the behaviour is switched off).
	// The farm site search prefers ground above it: a solar drowned every
	// seven minutes is a solar bought seven times.
	void SetLavaCrest(float y) { lavaCrest = y; }
	float GetLavaCrest() const { return lavaCrest; }
	bool AboveLavaCrest(const springai::AIFloat3& pos) const {
		return (lavaCrest <= NO_LAVA) || (GetElevationAt(pos) > lavaCrest);
	}
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
	bool SnapToBaseGrid(const springai::AIFloat3& pos, springai::AIFloat3& outPos,
			CCircuitDef* def = nullptr, int facing = UNIT_NO_FACING) const;
	// The lattice cell (i across, j deeper) from a snapped position, in the
	// def's own strides; false outside the base. The neighbour of a taken
	// slot is the next slot, never the next build square.
	bool LatticeNeighbour(const springai::AIFloat3& snapped, CCircuitDef* def, int facing,
			int i, int j, springai::AIFloat3& outPos) const;
	// The def's lattice in world axes: pitch and the corner phase from (0,0).
	void LatticeOf(CCircuitDef* def, int facing, float& px, float& pz, float& ox, float& oz) const;
	void LatticeCell(const springai::AIFloat3& pos, CCircuitDef* def, int facing,
			springai::AIFloat3& outPos) const;
	void LatticePoint(const springai::AIFloat3& cell, CCircuitDef* def, int facing,
			springai::AIFloat3& outPos) const;
	// Is this ground one of the published walkways? The snap alone only keeps a
	// street clear while the slot it snapped to is free; a base whose slots are
	// all taken falls back to a 3200-elmo site search that lands wherever it
	// likes, and that base is the one that seals its own units in.
	bool IsInBaseLane(const springai::AIFloat3& pos) const;
	// Cardinal facing along the published axis for a position inside the base,
	// or UNIT_NO_FACING when the grid does not apply. Factories use it so their
	// exit apron opens onto the road to the front instead of the map centre.
	int GetBaseGridFacing(const springai::AIFloat3& pos) const;
	// In-game map markers, for watching what the AI believes. These are ordinary
	// map points/lines: allies and spectators see them, so anything using these
	// must stay off by default outside a debug watch.
	void DrawPoint(const springai::AIFloat3& pos, const std::string& label);
	void DrawLine(const springai::AIFloat3& from, const springai::AIFloat3& to);
	void DrawErase(const springai::AIFloat3& pos);
	// apex: territory (0 nobody, 1 ours, 2 theirs) from the influence map's
	// derived mask, and the versions the script keys its refreshes on.
	int GetTerritoryAt(const springai::AIFloat3& pos) const;
	int GetTerritoryVersion() const;
	int GetWreckFieldVersion() const;
	float GetAllyInflAt(const springai::AIFloat3& pos) const;
	float GetAllyDefendInflAt(const springai::AIFloat3& pos) const;
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
	// The commit's own question: does the def's lattice cell at pos hold it
	// right now -- the cell exactly, the engine's footprint test at the
	// facing the task will use, the blocking map with every reservation.
	bool CanPlaceCell(CCircuitDef* def, const springai::AIFloat3& pos, springai::AIFloat3& outCell);
	void SetCommitted(bool v) { isCommitted = v; }
	bool IsCommitted() const { return isCommitted; }
	// A large building could not be placed. Reported, not acted on: what to
	// clear out of the way is a policy question and lives in AngelScript.
	void NoteBuildBlocked(const springai::AIFloat3& pos, const CCircuitDef* def = nullptr);
	// Sites a builder refused as unsafe (CanReachAtSafe), newest last: the
	// ground raids keep us off, for the script's defence pricing.
	void NoteUnsafeSite(const springai::AIFloat3& pos);
	const std::vector<std::pair<springai::AIFloat3, int>>& GetUnsafeSites() const { return unsafeSites; }
	bool GetBlockedBuildPos(springai::AIFloat3& outPos);
	// The def that failed to place there, -1 when the mark carries none.
	int GetBlockedBuildDef() const { return blockedBuildDef; }
	// Our own units of `def` within radius of pos. The script can see a def's
	// count but has no way to reach the instances.
	std::vector<CCircuitUnit*> GetOwnUnitsOfDef(CCircuitDef* def, const springai::AIFloat3& pos, float radius);
	// Every finished structure of ours near pos, whatever its def. A name list
	// cannot answer "what of ours is standing in the way" -- it only answers it
	// for the factions someone remembered to list.
	std::vector<CCircuitUnit*> GetOwnStructsNear(const springai::AIFloat3& pos, float radius);
	// apex: same sweep, caller-owned buffer -- the by-value form heap-allocates
	// a vector per call and both military callers run it inside a loop.
	void GetOwnStructsNear(const springai::AIFloat3& pos, float radius, std::vector<CCircuitUnit*>& out);
	// apex: the existence question, without building the list to ask it.
	bool HasOwnStructNear(const springai::AIFloat3& pos, float radius);
	// Our own damaged MOBILE units near pos, whatever their def. BuilderManager
	// never registers a damagedHandler for ordinary combat unit defs (only for
	// builders/rez-bots themselves and for static structures), so nothing ever
	// creates a REPAIR task for a hurt tank standing in the field -- the script
	// has to find one itself.
	std::vector<CCircuitUnit*> GetOwnDamagedNear(const springai::AIFloat3& pos, float radius);
	// Engine path length for this unit's move type, or -1 when there is no path.
	// CircuitAI's own areas come from CTerrainData and are terrain-only, so a
	// pocket walled in by BUILDINGS is invisible to CanMoveToPos. The engine's
	// path manager reads the synced blocking map, structures included, which is
	// the only oracle here that can see one.
	float GetPathLength(CCircuitUnit* unit, const springai::AIFloat3& to);
	float GetEnemyCostAt(const springai::AIFloat3& pos, float radius) const;
	// How close the nearest enemy is to being able to shoot this spot: the
	// smallest (distance - its weapon reach - `reactS` seconds of its own
	// walking) over every enemy we can see. Negative means something already
	// covers the spot. `foeOut`, when given, receives that enemy's position.
	float GetEnemyReachSlack(const springai::AIFloat3& pos, float reactS,
			springai::AIFloat3* foeOut = nullptr);
	void RebuildReachCache();
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
	mutable float lavaLevel = NO_LAVA;   // see GetLavaLevel
	mutable int lavaFrame = -1;
	float lavaCrest = NO_LAVA;           // see SetLavaCrest

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

	// Dedupe: a unit listed twice is reaped twice on death -- double delete,
	// double task->Release, and the heap corruption that took Lua down with
	// it (cushion-trap stack: UpdateActions -> ~CCircuitUnit -> Release).
	void AddActionUnit(CCircuitUnit* unit) {
		if (std::find(actionUnits.begin(), actionUnits.end(), unit) == actionUnits.end()) {
			actionUnits.push_back(unit);
		}
	}

private:
	void UpdateActions();

	Units teamUnits;  // owner
	// Indices over teamUnits, so the "our units near here" helpers stop walking
	// the whole team once per call. INVALIDATION CONTRACT: teamUnits is mutated
	// in exactly three places -- RegisterTeamUnit, UnregisterTeamUnit and the
	// Release() clear -- and all three maintain these. A unit's CCircuitDef is
	// fixed at construction (CCircuitUnit has no SetCircuitDef), so nothing ever
	// migrates buckets. Each vector is kept sorted by unit id, which is the order
	// a std::map walk produced, so callers see the same sequence they always did.
	std::map<int, std::vector<CCircuitUnit*>> unitsByDef;  // def id -> units
	std::vector<CCircuitUnit*> teamStatics;  // !IsMobile(), the only ones GetOwnStructsNear can return
	std::vector<CCircuitUnit*> teamMobiles;  // IsMobile(), likewise for GetOwnDamagedNear
	void IndexTeamUnit(CCircuitUnit* unit, bool isAdd);
	EnemyInfos enemyInfos;  // owner
	CAllyTeam* allyTeam;
	bool isAllyTeamInit;

	std::vector<CCircuitUnit*> actionUnits;
	unsigned int actionIterator;

	std::set<CCircuitUnit*> garbage;
	// Dead units are parked here instead of freed: task `units` sets can hold
	// stale memberships past UnitDestroyed (observed live: CSRepairTask
	// iterating a freed unit, and SetTask on freed unit memory double-releasing
	// a manager's idleTask to destruction — the Lua-heap-corruption crash
	// family). A zombie unit keeps valid memory: stale touches become inert
	// (TRY_UNIT absorbs dead-engine-unit commands) and refcounts stay honest.
	// Freed in Release(). A set so a double reap cannot park a unit twice.
	std::set<CCircuitUnit*> deadUnits;

public:
	// Deferred reference drops: CCircuitUnit::SetTask parks the old task's
	// Release here instead of running it inline, because the unit's reference
	// can be the task's LAST and inline Release deletes the task while its own
	// RemoveAssignee/Stop is still executing. Drained at the top of Update().
	void DeferRelease(circuit::IRefCounter* obj) { deferredReleases.push_back(obj); }
private:
	void DrainDeferredReleases();
	std::vector<circuit::IRefCounter*> deferredReleases;
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

// >>> Unit track record ---- BEGIN
public:
	struct SRecord { float dealt = .0f; float health = .0f; float n = .0f; };
private:
	std::unordered_map<ICoreUnit::Id, float> recDealt;      // this game, per unit
	std::unordered_map<CCircuitDef::Id, SRecord> recGame;   // this game, per def
	std::unordered_map<CCircuitDef::Id, SRecord> recStored; // from the file
	std::string recPath;
	void RecordLoad();
	void RecordSave();
	static bool RecordCounts(CCircuitDef* cdef);
// <<< Unit track record ---- END

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
	int blockedBuildDef = -1;
	std::vector<std::pair<springai::AIFloat3, int>> unsafeSites;
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
	#define HOT_SPOT_NUM		8
	std::vector<SHotSpot> hotSpots;
	int hotDecayFrame = 0;
	void DecayHotSpots();
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
	// apex: census of engine orders sent to sniper-class units, by kind,
	// logged every 30s so the move-only rule for that class is measurable.
	void NoteSniperOrder(CCircuitDef::SniperOrder kind);
	// apex: census of every engine order this AI sends, by kind, with the ones
	// that repeat what the same unit was already told. See CCircuitUnit::NoteOrder.
	void NoteOrder(int kind, int bucket, bool suppressed, int src = 0);
	// apex: orders the arbiter refused, per call site -- what a centre TRIED to
	// do while a higher-ranked decision was still running.
	void NoteOrderRefused(int src, int byPrio);
	// apex: the arc-side tiebreak that a sticky side would have held. Counted
	// with apex_arc_sticky OFF too, so one run says what turning it on buys.
	void NoteArcFlip(bool held, unsigned units);
	int GetSkirmishAIId() const { return skirmishAIId; }
	int GetTeamId()       const { return teamId; }
	int GetAllyTeamId()   const { return allyTeamId; }
	SideType GetSideId()             const { return sideId; }
	const std::string& GetSideName() const { return sideName; }

	COOAICallback*        GetCallback()   const { return callback.get(); }
	CEngine*              GetEngine()     const { return engine.get(); }
	springai::Cheats*     GetCheats()     const { return cheats.get(); }
	springai::Log*        GetLog()        const { return log.get(); }
	void LogLine(const char* msg);
	void FlushLog();
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
	// apex: whole-AI frame cost (scheduler jobs, threat/infl maps, task
	// reevaluation, actions) as one bucket beside the script-only timers.
	uint64_t perfFrameUs = 0;
	uint64_t perfFrameMaxUs = 0;
	unsigned perfFrameCalls = 0;
	int perfFrameNextLog = 0;
	// apex: the frame's cost split into its four top-level calls, so the
	// non-script remainder stops being one opaque bucket.
	uint64_t perfAllyUs = 0;
	uint64_t perfJobsUs = 0;
	uint64_t perfActUs = 0;
	uint64_t perfScrUs = 0;   // script->Update(): AngelScript, not unattributed C++
	// apex: the engine events, which run OUTSIDE AiFrame -- not part of the
	// split's total, and until now counted as engine time. See HandleGameEvent.
	uint64_t perfEvtNs = 0;
	unsigned perfEvtCalls = 0;
	// apex: a census, not a clock -- how many elements the O(n) helpers walked
	// this minute. Increments only, so measuring costs nothing; a helper whose
	// visited count grows faster than the unit count is the quadratic one.
	uint64_t perfFeatSweep = 0;   // features visited by the four wreck sweeps
	unsigned perfFeatCalls = 0;
	uint64_t perfReachSweep = 0;  // enemies visited by GetEnemyReachSlack
	unsigned perfReachCalls = 0;
	// ...and what it ANSWERED, because a wrong envelope costs nothing to walk.
	float perfReachWorst = std::numeric_limits<float>::max();
	float perfReachMax = 0.f;
	CCircuitDef* perfReachMaxDef = nullptr;
	uint64_t perfOwnSweep = 0;    // own units visited by GetOwn*Near/OfDef
	unsigned perfOwnCalls = 0;
	// ...split four ways, because "own" named a helper family, not a helper, and
	// the next session needs to know which of them is the one that costs.
	uint64_t perfOwnDefSweep = 0;    unsigned perfOwnDefCalls = 0;
	uint64_t perfOwnStrSweep = 0;    unsigned perfOwnStrCalls = 0;
	uint64_t perfOwnDmgSweep = 0;    unsigned perfOwnDmgCalls = 0;
	mutable uint64_t perfEcostSweep = 0;  // enemies visited by GetEnemyCostAt
	mutable unsigned perfEcostCalls = 0;
	// apex: orders sent, orders dropped as provable no-ops, and the repeats
	// bucketed by how far the commanded point moved: [0] bit-identical,
	// [1] < SQUARE_SIZE (the goal radius our move orders carry), [2] < 4,
	// [3] < 16 squares, [4] further. Everything past [0] re-paths.
	unsigned ordSent[5] = {0, 0, 0, 0, 0};
	unsigned ordSup[5] = {0, 0, 0, 0, 0};
	unsigned ordRep[5][5] = {{0}};
	// apex: the same census split by CALL SITE (CCircuitUnit::OrdSrc), because
	// the kind/distance one cannot say which loop is generating the churn.
	// [0] sent, [1] re-sends within 3s, [2] the far ones among those.
	static constexpr int ORD_SRC_N = 22;
	unsigned ordRefused[ORD_SRC_N] = {0};
	unsigned ordSrc[ORD_SRC_N][3] = {{0}};
	unsigned arcFlip[2] = {0, 0};   // [0] side changed, [1] a sticky side held it
	unsigned arcFlipU[2] = {0, 0};  // units re-slotted by those
	// apex: SET-TARGET HOLDER CENSUS. unit_target_on_the_move.lua blocks
	// CMD_UNIT_SET_TARGET in AllowCommand, so the order looks free -- but it
	// enrols the unit, and the gadget's GameFrame then re-applies every
	// holder's target every 5 frames (weapon TryTarget per weapon under
	// CallAsTeam, SetUnitTarget, four SetUnitRulesParam). That cost scales
	// with HOLDERS, not with our send rate, and it is billed to the engine.
	// Two independent counts, because either alone can be doubted. `tgtHeld` is
	// ours: every unit we sent a set-target to and have not stopped, so it is an
	// UPPER bound -- the gadget also drops a holder by itself when the target
	// dies (n%5 checkTarget) or leaves radar+los (n%15 removeUnseenTarget), and
	// we do not see those. The sampled half reads the gadget's own
	// unitRulesParam "targetID", one unit per frame with the cursor walked by
	// id, and is the lower-side check on it.
	std::set<CCircuitUnit*> tgtHeld;
	ICoreUnit::Id tgtCursor = -1;
	unsigned tgtSamp = 0;   // units probed this minute
	unsigned tgtHold = 0;   // ...of which the gadget still holds a target for
	unsigned tgtRel = 0;    // ...of which it holds none but once did (param == -1)
	bool tgtRawLogged = false;  // S7: prove the callback is not silently dead
	// apex: featureDef -> its constants, filled on first sight. See GetFeatDefInfo.
	std::vector<SFeatDefInfo> featDefInfo;
	int metalResId = -1;
	// apex: GetEnemyReachSlack's input, flattened once per frame. See its .cpp comment.
	struct SReachEnemy {
		float x, z, reach, speed;
		uint32_t idx;  // position in the unsorted cache: keeps the tie-break exact
	};
	std::vector<SReachEnemy> reachCache;
	// apex: bounding-volume tree over reachCache, rebuilt with it. See BuildReachTree.
	struct SReachNode {
		float minx, minz, maxx, maxz;
		float maxReach, maxSpeed;  // envelope bound for everything below
		int32_t first, count;      // count > 0: leaf range; count == 0: inner node
		int32_t right;             // inner: right child; the left child is self + 1
	};
	std::vector<SReachNode> reachNodes;
	int32_t BuildReachTree(int32_t first, int32_t count);
	float ReachNodeMinDist(int32_t ni, float px, float pz) const;
	void ReachQuery(int32_t ni, float px, float pz, float reactS, float minDist,
			float& worst, uint32_t& bestIdx, const SReachEnemy*& best);
	int reachCacheFrame = -1;
	int squadDiagNextLog = 0;
	int ghostPurgeNext = 0;
	std::array<int, static_cast<int>(CCircuitDef::SniperOrder::_SIZE_)> sniperOrders{};
	int sniperOrderNextLog = 0;
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
	FILE* logFile;
	std::string logTag;
	int64_t logEpochNs;   // process age when logSteady0 was taken
	std::chrono::steady_clock::time_point logSteady0;
	std::mutex logMutex;
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
