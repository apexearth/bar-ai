/*
 * MapManager.h
 *
 *  Created on: Dec 21, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_MAP_MAPMANAGER_H_
#define SRC_CIRCUIT_MAP_MAPMANAGER_H_

#include "unit/enemy/EnemyManager.h"

#include <vector>
#include <cstdint>

namespace circuit {

class CCircuitAI;
class CThreatMap;
class CInfluenceMap;

// apex: the wrecks the ally team can see, bucketed by cell and rebuilt about
// once a second in slices on the main thread (feature reads are engine
// callbacks, so they cannot run on a worker). Every wreck question is a walk
// of the cells under its circle instead of an engine feature query per ask;
// the answer is at most one rebuild old. Lives in this file because the build
// does not re-glob new sources.
class CWreckField {
public:
	struct SItem {
		float x, z;
		float metal;     // the def's contained metal
		float value;     // reclaim metal left: metal x reclaim fraction
		float rezCostM;  // cost of the unit this corpse rezzes into, < 0 if none
		bool rezzable;   // the engine says it resurrects
		bool comm;       // a commander corpse: never reclaimed, never rezzed by us
	};

	void Init(float mapWidth, float mapHeight);
	void UpdateSlice(CCircuitAI* ai, int frame);
	int GetVersion() const { return version; }
	int GetCount() const { return count; }

	springai::AIFloat3 BestWreck(const springai::AIFloat3& pos, float radius, float minMetal);
	springai::AIFloat3 BestRez(const springai::AIFloat3& pos, float radius, float minCost);
	float ValueAt(const springai::AIFloat3& pos, float radius);
	float WorkAt(const springai::AIFloat3& pos, float radius);
	springai::AIFloat3 CommanderWreck(const springai::AIFloat3& pos, float radius);

	uint64_t perfSweep = 0;   // items visited by queries
	uint32_t perfCalls = 0;
	uint64_t perfScanned = 0; // features read by the rebuild

private:
	template<typename F> void ForEachIn(const springai::AIFloat3& pos, float radius, F&& f);

	float cell = 512.f;
	int nx = 0, nz = 0;
	std::vector<std::vector<SItem>> cur, next;
	std::vector<int> pending;
	size_t cursor = 0;
	int lastStart = -1000000;
	int version = 0;
	int count = 0;
	int nextCount = 0;
};

class CMapManager {
public:
	CMapManager(CCircuitAI* circuit, float decloakRadius);
	virtual ~CMapManager();

	void InitMaps();

	void SetAuthority(CCircuitAI* authority) { circuit = authority; }
	CCircuitAI* GetCircuit() const { return circuit; }

	CThreatMap* GetThreatMap() const { return threatMap; }
	CInfluenceMap* GetInflMap() const { return inflMap; }
	CWreckField& GetWreckField() { return wreckField; }

	// apex: one ray over the territory mask and the builder threat map.
	// Samples from + dir * step * i, i = 1..n, stopping past maxD, off the map,
	// on a cell that is theirs (met), or -- when stopAtOursEnd -- on the first
	// cell that is not ours. edge is the last sample that was ours; safe the
	// last sample with builder threat <= bar (inside edge when stopAtOursEnd,
	// anywhere walked otherwise); metAt the distance they were met at.
	// flags: 1 met, 2 left the map.
	void TerritoryRay(const springai::AIFloat3& from, const springai::AIFloat3& dir,
			float step, int n, float maxD, float bar, bool stopAtOursEnd,
			float& edge, float& safe, float& metAt, int& flags) const;

	const CEnemyManager::EnemyUnits& GetHostileUnits() const { return hostileUnits; }
	const CEnemyManager::EnemyUnits& GetPeaceUnits() const { return peaceUnits; }
	const CEnemyManager::EnemyFakes& GetEnemyFakes() const { return enemyFakes; }

	void PrepareUpdate();
	void EnqueueUpdate();
	bool IsUpdating() const;
	bool HostileInLOS(CEnemyUnit* enemy);
	bool PeaceInLOS(CEnemyUnit* enemy);

	bool IsSuddenThreat(CEnemyUnit* enemy) const;

	bool EnemyEnterLOS(CEnemyUnit* enemy);
	void EnemyLeaveLOS(CEnemyUnit* enemy);
	void EnemyEnterRadar(CEnemyUnit* enemy);
	void EnemyLeaveRadar(CEnemyUnit* enemy);
	bool EnemyDestroyed(CEnemyUnit* enemy);

	void AddFakeEnemy(CEnemyFake* enemy);
	void DelFakeEnemy(CEnemyFake* enemy);

	bool IsInLOS(const springai::AIFloat3& pos) const;
//	bool IsInRadar(const springai::AIFloat3& pos) const;

private:
	CCircuitAI* circuit;

	CThreatMap* threatMap;
	CInfluenceMap* inflMap;
	CWreckField wreckField;

	CEnemyManager::EnemyUnits hostileUnits;
	CEnemyManager::EnemyUnits peaceUnits;
	CEnemyManager::EnemyFakes enemyFakes;

//	IntVec radarMap;
	IntVec sonarMap;
	IntVec losMap;

	int radarWidth;
	int radarResConv;
	int losWidth;
	int losResConv;
};

} // namespace circuit

#endif // SRC_CIRCUIT_MAP_MAPMANAGER_H_
