/*
 * InfluenceMap.h
 *
 *  Created on: Oct 20, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TERRAIN_INFLUENCEMAP_H_
#define SRC_CIRCUIT_TERRAIN_INFLUENCEMAP_H_

#include "unit/enemy/EnemyUnit.h"

#include <vector>
#include <atomic>
#include <cstdint>
#ifdef DEBUG_VIS
#include <stdint.h>
#endif

namespace springai {
	class AIFloat3;
	class Feature;
}

namespace circuit {

#define INFL_BASE		0.f
#define INFL_EPS		0.01f
#define INFL_SAFE		2.f

class CEnemyManager;
class CMapManager;
class CAllyUnit;
class IMainJob;

class CInfluenceMap {
public:
	CInfluenceMap(CMapManager* manager);
	~CInfluenceMap();

	void ReadConfig();
	void EnqueueUpdate();
	bool IsUpdating() const { return isUpdating; }

	float GetEnemyInflAt(const springai::AIFloat3& position) const;
	float GetAllyInflAt(const springai::AIFloat3& position) const;
	float GetAllyDefendInflAt(const springai::AIFloat3& position) const;
	// apex: armed static defence alone -- the guns a raider walks into.
	float GetAllyStaticInflAt(const springai::AIFloat3& position) const;
	float GetInfluenceAt(const springai::AIFloat3& position) const;

	int Pos2Index(const springai::AIFloat3& pos) const;

	// apex: Update() paints the enemy half on a worker; Apply() paints the ALLY
	// half of the whole ally team on the main thread inside job:finish. Split
	// so the two halves can be compared before moving either. Relaxed atomics:
	// the halves never run concurrently (isUpdating serialises them) but the
	// main thread clears what a worker wrote, and no ordering is required.
	std::atomic<uint64_t> perfEnemyCells{0};
	std::atomic<uint64_t> perfAllyCells{0};
	std::atomic<uint64_t> perfFills{0};
	std::atomic<uint64_t> perfApplyUs{0};
	std::atomic<uint32_t> perfEnemies{0};
	std::atomic<uint32_t> perfFriendlies{0};
	std::atomic<uint32_t> perfApplies{0};
	int GetMapSize() const { return mapSize; }

	// apex: territory, derived from the finished map at the end of every
	// Apply: 0 nobody's, 1 ours (ally influence at or above its bar and not
	// dominated), 2 theirs (enemy influence at or above its bar and above
	// ours). The bars are shares of the map-wide peaks, floored at 1. The front
	// is the edge of this; the script rays over it instead of the raw fields.
	int GetTerritoryAt(const springai::AIFloat3& position) const;
	int GetTerritoryVersion() const { return terrVersion; }
	void SetTerritoryBars(float allyFrac, float foeFrac) { terrAllyFrac = allyFrac; terrFoeFrac = foeFrac; }
	float GetTerritoryAllyBar() const { return terrAllyBar; }
	float GetTerritoryFoeBar() const { return terrFoeBar; }
	int GetTerritoryEdgeCount() const { return (int)terrEdge.size(); }
	int GetTerritoryOursCount() const { return terrOurs; }

private:
	void DeriveTerritory();
	std::vector<uint8_t> terr;
	std::vector<int> terrEdge;   // cell indices of ours with a 4-neighbour not ours
	int terrVersion = 0;
	int terrOurs = 0;
	float terrAllyFrac = 0.03f;
	float terrFoeFrac = 0.10f;
	float terrAllyBar = 1.f;
	float terrFoeBar = 1.f;

	struct SInfluenceData {
		FloatVec enemyInfl;
		FloatVec allyInfl;
		FloatVec allyDefendInfl;
		FloatVec allyStaticInfl;
		FloatVec influence;
//		FloatVec tension;
//		FloatVec vulnerability;
//		FloatVec featureInfl;
	};

	CMapManager* manager;

	int GetUnitRange(CAllyUnit* u) const;

	void AddMobileArmed(CAllyUnit* u);
	void AddStaticArmed(CAllyUnit* u);
	void AddUnarmed(CAllyUnit* u);
	void AddEnemy(const SEnemyData& e);
//	void AddFeature(springai::Feature* f);
	inline void PosToXZ(const springai::AIFloat3& pos, int& x, int& z) const;

	void Prepare(SInfluenceData& inflData);
	std::shared_ptr<IMainJob> Update(CEnemyManager* enemyMgr);
	void Apply();
	void SwapBuffers();
	SInfluenceData* GetNextInflData() {
		return (pInflData.load() == &inflData0) ? &inflData1 : &inflData0;
	}

	int squareSize;
	int width;
	int height;
	int mapSize;

//	float vulnMax;

	SInfluenceData inflData0, inflData1;  // Double-buffer for threading
	std::atomic<SInfluenceData*> pInflData;
	float* drawEnemyInfl;
	float* drawAllyInfl;
	float* drawAllyDefendInfl;
	float* drawAllyStaticInfl;
	float* drawInfluence;
//	float* drawTension;
//	float* drawVulnerability;
//	float* drawFeatureInfl;
	bool isUpdating;

	float* enemyInfl;
	float* allyInfl;
	float* allyDefendInfl;
	float* allyStaticInfl;
	float* influence;
//	float* tension;
//	float* vulnerability;
//	float* featureInfl;

	float rangeScale = 1.f;  // thread var
	float defRadius = 0.f;

// apex: the WIDGET half of the debug visualisation is not a debug build feature.
// It streams the grid to a LuaRules gadget over CallRules and needs no SDL, but
// it lived inside DEBUG_VIS -- which only CIRCUIT_DEBUG defines, and which also
// drags in SDL2 -- so `~widraw` did nothing in every shipped build. Only the
// SDL-window view below stays gated.
private:
	bool isWidgetDrawing = false;
	bool isWidgetPrinting = false;
	void UpdateWidgetVis();
public:
	void ToggleWidgetDraw();
	void ToggleWidgetPrint();

#ifdef DEBUG_VIS
private:
	std::vector<std::pair<uint32_t, float*>> sdlWindows;
	void UpdateVis();
public:
	void ToggleSDLVis();
	void SetMaxThreat(float maxThreat);
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_TERRAIN_INFLUENCEMAP_H_
