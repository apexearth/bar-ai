/*
 * TerrainManager.h
 *
 *  Created on: Dec 6, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TERRAIN_TERRAINMANAGER_H_
#define SRC_CIRCUIT_TERRAIN_TERRAINMANAGER_H_

#include "terrain/BlockingMap.h"
#include "unit/CoreUnit.h"
#include "unit/CircuitDef.h"

#include "AIFloat3.h"

#include <unordered_map>
#include <deque>
#include <functional>

namespace terrain {
	struct SArea;
	struct SMobileType;
	struct SImmobileType;
	struct SAreaSector;
	struct SSector;
	struct SAreaData;
}

namespace circuit {

class CCircuitAI;
class IBlockMask;
class IPathQuery;
class CPathInfo;
class CCircuitUnit;

class CTerrainManager final {  // <=> RAI's cBuilderPlacement
public:
	using TerrainPredicate = std::function<bool (const springai::AIFloat3& p)>;

	CTerrainManager(CCircuitAI* circuit, terrain::CTerrainData* terrainData);
	~CTerrainManager();

	// Ground held for one footprint (apex): his turret strips. A building of another footprint that overlaps a
	// zone is refused by every site search (his 10-21: slots are typed by size, an anti-nuke where a converter fits).
	void AddZone(float x1, float z1, float x2, float z2, int allowId);
	void ClearZones() { zones.clear(); }
	int GetZoneCount() const { return (int)zones.size(); }
	bool ZoneRefuses(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing) const;
private:
	struct SZone { float x1, z1, x2, z2; int allowId; int allowX, allowZ; };
	std::vector<SZone> zones;
public:

	void InitAnalyzer();
private:
	CCircuitAI* circuit;
	void ReadConfig();

public:
	static inline int GetTerrainWidth() { return springai::AIFloat3::maxxpos; }
	static inline int GetTerrainHeight() { return springai::AIFloat3::maxzpos; }
	static inline float GetTerrainDiagonal() {
		return sqrtf(SQUARE(springai::AIFloat3::maxxpos) + SQUARE(springai::AIFloat3::maxzpos));
	}
	static inline springai::AIFloat3 GetTerrainCenter() {
		return springai::AIFloat3(GetTerrainWidth() / 2, 0, GetTerrainHeight() / 2);
	}

	void Init();
	void AddBlocker(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing, bool isOffset = false);
	void DelBlocker(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing, bool isOffset = false);
	// apex: which of `near` refuse cdef at pos/facing, by the cell tests FindBuildSiteByMask makes
	// apex: which test refuses cdef at exactly pos/facing: "engine", "threat", "area", "zone", "map:<struct mask>", or "ok"
	std::string PlaceWhy(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing);
	bool GroundTakes(CCircuitDef* cdef, const springai::AIFloat3& pos);
	bool Reserved(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing);
	std::vector<CCircuitUnit*> BlockersOf(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing,
			const std::vector<CCircuitUnit*>& nearby, int frame);
	bool IsObstruct(const springai::AIFloat3& pos) const;
//	springai::AIFloat3 CheckObstruct(CCircuitUnit* unit) const;
	void AddBusPath(CCircuitUnit* unit, const springai::AIFloat3& toPos, CCircuitDef* mobileDef);
	void DelBusPath(CCircuitUnit* unit);
	springai::AIFloat3 GetBusPos(CCircuitDef* facDef, const springai::AIFloat3& pos, int& outFacing);
	void ResetBuildFrame() { markFrame = -FRAMES_PER_SEC; markVersion = -1; }
	// TODO: Use IsInBounds test and Bound operation only if mask or search offsets (endr) are out of bounds
	// TODO: Based on map complexity use BFS or circle to calculate build offset
	// TODO: Consider abstract task position (any area with builder) and task for certain unit-pos-area
	springai::AIFloat3 FindBuildSite(CCircuitDef* cdef,
									 const springai::AIFloat3& pos,
									 float searchRadius,
									 int facing,
									 bool isIgnore = false,
									 bool isHighRes = false);
	springai::AIFloat3 FindBuildSite(CCircuitDef* cdef,
									 const springai::AIFloat3& pos,
									 float searchRadius,
									 int facing,
									 TerrainPredicate& predicate,
									 bool isIgnore = false,
									 bool isHighRes = false);
//	springai::AIFloat3 FindSpringBuildSite(CCircuitDef* cdef, const springai::AIFloat3& pos, float searchRadius, int facing);
	void DoLineOfDef(const springai::AIFloat3& start, const springai::AIFloat3& end, CCircuitDef* buildDef,
			std::function<void (const springai::AIFloat3& pos, CCircuitDef* buildDef)> exec) const;  // FillRowOfBuildPos

	const SBlockingMap& GetBlockingMap();
	bool IsZoneAlly(const springai::AIFloat3& pos) const;
	void AddZoneOwn(const springai::AIFloat3& pos) { MarkZoneOwn(pos, true); }
	void DelZoneOwn(const springai::AIFloat3& pos) { MarkZoneOwn(pos, false); }
	float SetAllyZoneRange(float range);  // range/radius in elmos

	bool ResignAllyBuilding(CCircuitUnit* unit);

	void ApplyAuthority();

private:
	int markFrame;
	int markVersion = -1;  // apex: the friendly-list version last merged
	struct SStructure {
		ICoreUnit::Id unitId;
		CCircuitDef* cdef;
		springai::AIFloat3 pos;
		int facing;
	};
	std::deque<SStructure> markedAllies;  // sorted by insertion
	void MarkAllyBuildings();

	struct SSearchOffset {
		int dx, dy;
		int qdist;  // dx*dx + dy*dy
	};
	using SearchOffsets = std::vector<SSearchOffset>;
	struct SSearchOffsetLow {
		SearchOffsets ofs;
		int dx, dy;
		int qdist;  // dx*dx + dy*dy
	};
	using SearchOffsetsLow = std::vector<SSearchOffsetLow>;
	static const SearchOffsets& GetSearchOffsetTable(int radius);
	static const SearchOffsetsLow& GetSearchOffsetTableLow(int radius);
	springai::AIFloat3 FindBuildSiteLow(CCircuitDef* cdef,
										const springai::AIFloat3& pos,
										float searchRadius,
										int facing,
										TerrainPredicate& predicate);
	springai::AIFloat3 FindBuildSiteByMask(CCircuitDef* cdef,
										   const springai::AIFloat3& pos,
										   float searchRadius,
										   int facing,
										   IBlockMask* mask,
										   TerrainPredicate& predicate);
	// NOTE: Low-resolution build site is 40-80% faster on fail and 20-50% faster on success (with large objects). But has lower precision.
	springai::AIFloat3 FindBuildSiteByMaskLow(CCircuitDef* cdef,
											  const springai::AIFloat3& pos,
											  float searchRadius,
											  int facing,
											  IBlockMask* mask,
											  TerrainPredicate& predicate);

	int allyZoneCells;  // side of a square
	SBlockingMap blockingMap;
	std::unordered_map<CCircuitDef::Id, IBlockMask*> blockInfos;  // owner
	void MarkBlockerByMask(const SStructure& building, bool block, IBlockMask* mask);
	void MarkBlocker(const SStructure& building, bool block);
	// apex: the cells a building's mask covers at pos/facing (1 = yard, 2 = body), its notIgnore and type mask
	void MaskCells(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing,
			std::vector<std::pair<int2, char>>& out, int& notIgnore, int& typeMask);
	void MarkZoneAlly(const springai::AIFloat3& pos, bool block);
	void MarkZoneOwn(const springai::AIFloat3& pos, bool block);

	struct FactoryPathQuery {
		std::shared_ptr<IPathQuery> query;
		const CCircuitDef* mobileDef;
		springai::AIFloat3 startPos;
		springai::AIFloat3 endPos;
		IndexVec targets;
	};
	struct WidePathInfo {
		std::shared_ptr<CPathInfo> pPath;
		int howWide;
		springai::AIFloat3 busStart = -RgtVector;  // apex: the door point and the bus end it was asked for
		springai::AIFloat3 busEnd = -RgtVector;
		const CCircuitDef* busDef = nullptr;
	};
	std::map<CCircuitUnit*, WidePathInfo> busPath;
	std::map<CCircuitUnit*, FactoryPathQuery> busQueries;
	// apex: our teammates' (other bots in this process) factory exit paths, as TERRA in our map: team id ->
	// (their version, the cells we marked)
	std::map<int, std::pair<int, std::vector<int2>>> busApplied;
	void BusCells(const CPathInfo* pathInfo, int howWide, std::vector<int2>& out);
	void PublishBus();
	void SyncAllyBus();
	void NoteExitHit(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing, bool standing);
	void NotePathOnStructs(CCircuitUnit* fac, const std::vector<int2>& cells);
public:
	// apex: by the engine's own pathing, how far short of `goal` a unit leaving fac's door stops; -1 unknown
	float ExitGap(CCircuitUnit* fac, const springai::AIFloat3& goal, springai::AIFloat3& outDoor, springai::AIFloat3& outStop);
	// apex: every friendly structure (ours or an ally's) whose body stands on this bot's own factory exit cells, as
	// (x, z, def, id, team) quintuples
	void ExitPathBlockers(std::vector<float>& out);
	// apex: cdef's body at pos on any exit path of this ally team's bots, ours included
	bool OnTeamExitPath(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing);
	// apex: from the door a factory facDef would have at pos, a unit it makes gets nearer `goal` than the door
	bool DoorEscapes(CCircuitDef* facDef, CCircuitDef* mobileDef, const springai::AIFloat3& pos, int facing,
			const springai::AIFloat3& goal);
	// apex: from start, how near goal a unit of mobileDef can get over ground no structure body stands on, by a flood
	// of the blocking map (host-local memory only: the engine path this replaced ran on the host alone and desynced)
	springai::AIFloat3 FloodStop(CCircuitDef* mobileDef, const springai::AIFloat3& start, const springai::AIFloat3& goal,
			int* outCells = nullptr);
private:
	void MarkBusPath();
	void FillParentBusNodes(CPathInfo* pathInfo);

public:
	int GetConvertStoP() const { return terrainData->convertStoP; }
	int GetSectorXSize() const { return terrainData->sectorXSize; }
	int GetSectorZSize() const { return terrainData->sectorZSize; }
	static void CorrectPosition(springai::AIFloat3& position) { terrain::CTerrainData::CorrectPosition(position); }
	static springai::AIFloat3 CorrectPosition(const springai::AIFloat3& pos, const springai::AIFloat3& dir, float& len) {
		return terrain::CTerrainData::CorrectPosition(pos, dir, len);
	}
	static void SnapPosition(springai::AIFloat3& position);
	static springai::AIFloat3 Pos2BuildPos(CCircuitDef* cdef, const springai::AIFloat3& position, int facing);

	std::pair<terrain::SArea*, bool> GetCurrentMapArea(CCircuitDef* cdef, const springai::AIFloat3& position);
	std::pair<terrain::SArea*, bool> GetCurrentMapArea(CCircuitDef* cdef, const int indexSector);
	int GetSectorIndex(const springai::AIFloat3& position) const { return terrainData->GetSectorIndex(position); }
	bool CanMoveToPos(terrain::SArea* area, const springai::AIFloat3& destination);
	// apex: false for an area outside this AI's buffer (logged): a task holding a dead pointer
	bool IsAreaLive(const terrain::SArea* area, const char* where);
	springai::AIFloat3 GetBuildPosition(CCircuitDef* cdef, const springai::AIFloat3& position);
	springai::AIFloat3 GetMovePosition(terrain::SArea* sourceArea, const springai::AIFloat3& position);
	springai::AIFloat3 ShiftPos(CCircuitDef* cdef, const springai::AIFloat3& position, float range, bool isOrtho = false);
	springai::AIFloat3 ShiftPos(CCircuitDef* cdef, const springai::AIFloat3& position, int clusterId, float range, bool isOrtho = false);
private:
	std::vector<terrain::SAreaSector>& GetSectorList(terrain::SArea* sourceArea = nullptr);
	terrain::SAreaSector* GetClosestSectorWithAltitude(terrain::SArea* sourceArea, const int destinationSIndex, const int altitude);
	terrain::SAreaSector* GetClosestSector(terrain::SArea* sourceArea, const int destinationSIndex);
	terrain::SSector* GetClosestSector(terrain::SImmobileType* sourceIT, const int destinationSIndex);
	// TODO: Refine brute-force algorithms
	terrain::SAreaSector* GetAlternativeSector(terrain::SArea* sourceArea, const int sourceSIndex, terrain::SMobileType* destinationMT);
	terrain::SSector* GetAlternativeSector(terrain::SArea* destinationArea, const int sourceSIndex, terrain::SImmobileType* destinationIT); // can return 0
	const terrain::SSector& GetSector(int sIndex) const { return areaData->sector[sIndex]; }
public:
	// apex: how far the nearest ground this area holds is from pos -- the
	// distance CanMobileReachAt tests against a builder's range.
	float ReachGap(terrain::SArea* area, const springai::AIFloat3& pos) {
		const int iS = GetSectorIndex(pos);
		if ((area == nullptr) || !terrainData->IsSectorValid(iS) || !IsAreaLive(area, "gap")) {
			return -1.f;
		}
		const terrain::SAreaSector* closest = GetClosestSector(area, iS);
		return (closest == nullptr) ? -1.f : closest->S->position.distance2D(pos);
	}
	const std::vector<terrain::SMobileType>& GetMobileTypes() const {
		return areaData->mobileType;
	}
	terrain::SMobileType* GetMobileType(CCircuitDef::Id unitDefId) const {
		return GetMobileTypeById(terrainData->udMobileType[unitDefId]);
	}
	terrain::SMobileType::Id GetMobileTypeId(CCircuitDef::Id unitDefId) const {
		return terrainData->udMobileType[unitDefId];
	}
	terrain::SMobileType* GetMobileTypeById(terrain::SMobileType::Id id) const {
		return (id < 0) ? nullptr : &areaData->mobileType[id];
	}
	const std::vector<terrain::SImmobileType>& GetImmobileTypes() const {
		return areaData->immobileType;
	}
	terrain::SImmobileType* GetImmobileType(CCircuitDef::Id unitDefId) const {
		return GetImmobileTypeById(terrainData->udImmobileType[unitDefId]);
	}
	terrain::SImmobileType::Id GetImmobileTypeId(CCircuitDef::Id unitDefId) const {
		return terrainData->udMobileType[unitDefId];
	}
	terrain::SImmobileType* GetImmobileTypeById(terrain::SImmobileType::Id id) const {
		return (id < 0) ? nullptr : &areaData->immobileType[id];
	}

	// position must be valid
	bool CanBeBuiltAt(CCircuitDef* cdef, const springai::AIFloat3& position, const float range);  // NOTE: returns false if the area was too small to be recorded
	bool CanBeBuiltAt(CCircuitDef* cdef, const springai::AIFloat3& position);
	bool CanBeBuiltAtSafe(CCircuitDef* cdef, const springai::AIFloat3& position);
	// The engine calls an unclaimed metal or geo spot legal ground; the blocking
	// map does not. True when the footprint at pos/facing covers a spot blocker
	// or a standing structure.
	bool FootprintOnSpot(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing) const;
	// One and two footprints out of the door, the product's own move type stands
	// in one connected area. True when the def makes nothing that walks.
	bool FactoryExitOpen(CCircuitDef* cdef, const springai::AIFloat3& pos, int facing) const;
	bool CanReachAt(CCircuitUnit* unit, const springai::AIFloat3& destination, const float range);
	bool CanReachAtSafe(CCircuitUnit* unit, const springai::AIFloat3& destination, const float range, const float threat = THREAT_MIN);
	bool CanReachAtSafe2(CCircuitUnit* unit, const springai::AIFloat3& destination, const float range);
	bool CanMobileReachAt(terrain::SArea* area, const springai::AIFloat3& destination, const float range);
	bool CanMobileReachAtSafe(terrain::SArea* area, const springai::AIFloat3& destination, const float range, const float threat = THREAT_MIN);

	float GetLandPercent() const { return areaData->percentLand; }
	float GetMinLandPercent() const { return minLandPercent; }
	bool IsWaterAVoid() const { return terrainData->waterIsAVoid; }
	bool IsWaterMap() const { return !IsWaterAVoid() && GetLandPercent() < GetMinLandPercent(); }
	bool IsWaterSector(const springai::AIFloat3& position) const { return IsWaterSector(GetSectorIndex(position)); }
	bool IsWaterSector(const int sIndex) const { return areaData->sector[sIndex].isWater; }

	const bwem::CArea* GetTAArea(const springai::AIFloat3& pos) const;
	const std::vector<bwem::CChokePoint*>& GetTAChokePoints() const { return terrainData->GetChokePoints(); }
	const int GetTAMinAltitude(const springai::AIFloat3& pos) const {
		return terrainData->GetTASector(terrainData->GetSectorIndex(pos)).GetMinAltitude();
	}

	terrain::SAreaData* GetAreaData() const { return areaData; }
	void UpdateAreaUsers(int interval);
	void OnAreaUsersUpdated() { terrainData->OnAreaUsersUpdated(); }

	bool IsEnemyInArea(terrain::SArea* area) const {
		return enemyAreas.find(area) != enemyAreas.end();
	}

private:
	terrain::SAreaData* areaData;
	terrain::CTerrainData* terrainData;

	float minLandPercent;

	std::unordered_set<const terrain::SArea*> enemyAreas;
	int staleAreaN = 0;

#ifdef DEBUG_VIS
private:
	int dbgTextureId;
	uint32_t sdlWindowId;
	float* dbgMap;
	bool isWidgetDrawing = false;
	void UpdateVis();
public:
	void ToggleVis();
	void ToggleWidgetDraw();
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_TERRAIN_TERRAINMANAGER_H_
