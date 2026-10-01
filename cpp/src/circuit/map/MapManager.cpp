/*
 * MapManager.cpp
 *
 *  Created on: Dec 21, 2019
 *      Author: rlcevg
 */

#include "map/MapManager.h"
#include "map/ThreatMap.h"
#include "map/InfluenceMap.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "Mod.h"

#include <algorithm>
#include <limits>

namespace circuit {

using namespace springai;

void CWreckField::Init(float mapWidth, float mapHeight)
{
	nx = std::max(1, int(mapWidth / cell) + 1);
	nz = std::max(1, int(mapHeight / cell) + 1);
	cur.assign(nx * nz, {});
	next.assign(nx * nz, {});
	pending.clear();
	cursor = 0;
	count = 0;
	nextCount = 0;
}

// A slice of the rebuild: a new pass starts at most once a second, reads the
// whole feature id list once, and works through it at a rate that finishes in
// well under that second; the finished grid replaces the live one whole.
void CWreckField::UpdateSlice(CCircuitAI* ai, int frame)
{
	if ((ai == nullptr) || (nx <= 0)) {
		return;
	}
	COOAICallback* cb = ai->GetCallback();
	if ((cb == nullptr) || (ai->GetMetalResId() < 0)) {
		return;
	}
	if (cursor >= pending.size()) {
		if (!pending.empty()) {
			cur.swap(next);
			// apex: a pass over an unchanged field is not new information;
			// idle rez bots re-ran their whole chain on every pass.
			if ((nextHash != curHash) || (nextCount != count)) {
				++version;
			}
			curHash = nextHash;
			count = nextCount;
			pending.clear();
		}
		if (frame - lastStart < FRAMES_PER_SEC) {
			return;
		}
		lastStart = frame;
		const int n = cb->GetFeatureIds();
		const int* ids = cb->GetFeatureIdBuf();
		pending.assign(ids, ids + n);
		cursor = 0;
		nextCount = 0;
		nextHash = 0;
		for (auto& bucket : next) {
			bucket.clear();
		}
		if (pending.empty()) {
			cur.swap(next);
			if (count != 0) {
				++version;
			}
			count = 0;
			curHash = 0;
			return;
		}
	}
	const size_t slice = std::max<size_t>(64, pending.size() / 20 + 1);
	const size_t end = std::min(pending.size(), cursor + slice);
	for (; cursor < end; ++cursor) {
		const int fId = pending[cursor];
		++perfScanned;
		const int defId = cb->Feature_GetDefId(fId);
		if (defId < 0) {
			continue;
		}
		const CCircuitAI::SFeatDefInfo& info = ai->GetFeatDefInfo(defId);
		if ((info.metal <= 0.f) && (info.rezCostM < 0.f)) {
			continue;   // nothing any query can want from it
		}
		const int rezDefId = cb->Feature_GetResurrectDefId(fId);
		const AIFloat3 fp = cb->Feature_GetPosition(fId);
		SItem it;
		it.x = fp.x;
		it.z = fp.z;
		it.metal = info.metal;
		it.value = info.metal * cb->Feature_GetReclaimLeft(fId);
		it.rezCostM = info.rezCostM;
		it.rezzable = (rezDefId >= 0);
		it.comm = ai->IsCommanderWreckId(rezDefId);
		int cx = int(fp.x / cell);
		int cz = int(fp.z / cell);
		cx = std::min(std::max(cx, 0), nx - 1);
		cz = std::min(std::max(cz, 0), nz - 1);
		next[cz * nx + cx].push_back(it);
		++nextCount;
		nextHash += (unsigned long long)(unsigned)fId * 0x9E3779B97F4A7C15ull;
	}
}

template<typename F>
void CWreckField::ForEachIn(const AIFloat3& pos, float radius, F&& f)
{
	if ((nx <= 0) || (radius <= 0.f)) {
		return;
	}
	++perfCalls;
	const float r2 = radius * radius;
	const int cx0 = std::max(0, int((pos.x - radius) / cell));
	const int cx1 = std::min(nx - 1, int((pos.x + radius) / cell));
	const int cz0 = std::max(0, int((pos.z - radius) / cell));
	const int cz1 = std::min(nz - 1, int((pos.z + radius) / cell));
	for (int cz = cz0; cz <= cz1; ++cz) {
		for (int cx = cx0; cx <= cx1; ++cx) {
			for (const SItem& it : cur[cz * nx + cx]) {
				++perfSweep;
				const float dx = it.x - pos.x;
				const float dz = it.z - pos.z;
				if (dx * dx + dz * dz <= r2) {
					f(it);
				}
			}
		}
	}
}

AIFloat3 CWreckField::BestWreck(const AIFloat3& pos, float radius, float minMetal)
{
	AIFloat3 best(-RgtVector);
	float bestMetal = minMetal;
	ForEachIn(pos, radius, [&](const SItem& it) {
		if (!it.comm && (it.value > bestMetal)) {
			bestMetal = it.value;
			best = AIFloat3(it.x, 0.f, it.z);
		}
	});
	return best;
}

AIFloat3 CWreckField::BestRez(const AIFloat3& pos, float radius, float minCost)
{
	AIFloat3 best(-RgtVector);
	float bestCost = minCost;
	ForEachIn(pos, radius, [&](const SItem& it) {
		if (!it.rezzable || it.comm) {
			return;
		}
		const float v = std::max(it.metal, it.rezCostM);
		if (v > bestCost) {
			bestCost = v;
			best = AIFloat3(it.x, 0.f, it.z);
		}
	});
	return best;
}

float CWreckField::WorkAt(const AIFloat3& pos, float radius)
{
	float total = 0.f;
	ForEachIn(pos, radius, [&](const SItem& it) {
		if (it.comm) {
			return;
		}
		float v = it.value;
		if (it.rezzable) {
			v = std::max(v, it.rezCostM);
		}
		total += v;
	});
	return total;
}

float CWreckField::ValueAt(const AIFloat3& pos, float radius)
{
	float total = 0.f;
	ForEachIn(pos, radius, [&](const SItem& it) {
		if (!it.comm) {
			total += it.value;
		}
	});
	return total;
}

AIFloat3 CWreckField::CommanderWreck(const AIFloat3& pos, float radius)
{
	AIFloat3 best(-RgtVector);
	float bestSqd = std::numeric_limits<float>::max();
	ForEachIn(pos, radius, [&](const SItem& it) {
		if (!it.comm) {
			return;
		}
		const float dx = it.x - pos.x;
		const float dz = it.z - pos.z;
		const float sqd = dx * dx + dz * dz;
		if (sqd < bestSqd) {
			bestSqd = sqd;
			best = AIFloat3(it.x, 0.f, it.z);
		}
	});
	return best;
}

void CMapManager::TerritoryRay(const AIFloat3& from, const AIFloat3& dir,
		float step, int n, float maxD, float bar, bool stopAtOursEnd,
		float& edge, float& safe, float& metAt, int& flags) const
{
	edge = 0.f;
	safe = 0.f;
	metAt = 0.f;
	flags = 0;
	const float w = float(CTerrainManager::GetTerrainWidth());
	const float h = float(CTerrainManager::GetTerrainHeight());
	float safeCand = 0.f;
	for (int i = 1; i <= n; ++i) {
		const float d = step * i;
		if (d > maxD) {
			break;
		}
		const AIFloat3 p = from + dir * d;
		if ((p.x < 0.f) || (p.z < 0.f) || (p.x >= w) || (p.z >= h)) {
			flags |= 2;
			break;
		}
		if (threatMap->GetBuilderThreatAt(p) <= bar) {
			safeCand = d;
		}
		const int t = inflMap->GetTerritoryAt(p);
		if (t == 2) {
			flags |= 1;
			metAt = d;
			if (!stopAtOursEnd) {
				safe = safeCand;
			}
			break;
		}
		if (t == 1) {
			edge = d;
			safe = safeCand;
			continue;
		}
		if (stopAtOursEnd) {
			break;
		}
		safe = safeCand;
	}
}

CMapManager::CMapManager(CCircuitAI* circuit, float decloakRadius)
		: circuit(circuit)
{
	CMap* map = circuit->GetMap();
	int mapWidth = map->GetWidth();
	Mod* mod = circuit->GetCallback()->GetMod();
	int losMipLevel = mod->GetLosMipLevel();
	int radarMipLevel = mod->GetRadarMipLevel();
	delete mod;

//	map->GetRadarMap(radarMap);
	radarWidth = mapWidth >> radarMipLevel;
	map->GetSonarMap(sonarMap);
	radarResConv = SQUARE_SIZE << radarMipLevel;
	map->GetLosMap(losMap);
	losWidth = mapWidth >> losMipLevel;
	losResConv = SQUARE_SIZE << losMipLevel;

	threatMap = new CThreatMap(this, decloakRadius);
	inflMap = new CInfluenceMap(this);
	wreckField.Init(float(CTerrainManager::GetTerrainWidth()), float(CTerrainManager::GetTerrainHeight()));
}

CMapManager::~CMapManager()
{
	delete threatMap;
	delete inflMap;
}

void CMapManager::InitMaps()
{
	threatMap->ReadConfig();
	inflMap->ReadConfig();
}

void CMapManager::PrepareUpdate()
{
//	circuit->GetMap()->GetRadarMap(radarMap);
	circuit->GetMap()->GetSonarMap(sonarMap);
	circuit->GetMap()->GetLosMap(losMap);
}

void CMapManager::EnqueueUpdate()
{
	threatMap->EnqueueUpdate();
	inflMap->EnqueueUpdate();
}

bool CMapManager::IsUpdating() const
{
	return threatMap->IsUpdating() || inflMap->IsUpdating();
}

bool CMapManager::HostileInLOS(CEnemyUnit* enemy)
{
	if (enemy->IsHidden()) {
		return false;
	}

	if (enemy->NotInRadarAndLOS() && IsInLOS(enemy->GetPos())) {
		enemy->SetHidden();
		return false;
	}

	if (enemy->IsInLOS()) {
		threatMap->SetEnemyUnitThreat(enemy);
	}

	return true;
}

bool CMapManager::PeaceInLOS(CEnemyUnit* enemy)
{
	if (enemy->IsHidden()) {
		return false;
	}

	if (enemy->NotInRadarAndLOS() && IsInLOS(enemy->GetPos())) {
		enemy->SetHidden();
		return false;
	}

	return true;
}

bool CMapManager::IsSuddenThreat(CEnemyUnit* enemy) const
{
	return !enemy->IsKnown(circuit->GetLastFrame())
			|| (!enemy->IsInRadar() && enemy->GetCircuitDef()->IsMobile());
}

bool CMapManager::EnemyEnterLOS(CEnemyUnit* enemy)
{
	// Possible cases:
	// (1) Unknown enemy that has been detected for the first time
	// (2) Unknown enemy that was only in radar enters LOS
	// (3) Known enemy that already was in LOS enters again

	const bool wasKnown = enemy->IsKnown(circuit->GetLastFrame());
	enemy->SetInLOS();

	if (!enemy->IsAttacker()) {
		if (enemy->GetInfluence() > .0f) {  // (2)
			// threat prediction failed when enemy was unknown
			if (enemy->IsHidden()) {
				enemy->ClearHidden();
			}
			hostileUnits.erase(enemy->GetId());
			peaceUnits[enemy->GetId()] = enemy;
			enemy->ClearThreat();
			threatMap->SetEnemyUnitRange(enemy);
		} else if (peaceUnits.find(enemy->GetId()) == peaceUnits.end()) {
			peaceUnits[enemy->GetId()] = enemy;
			threatMap->SetEnemyUnitRange(enemy);
		} else if (enemy->IsHidden()) {
			enemy->ClearHidden();
		}

		enemy->UpdateInRadarData(enemy->GetUnit()->GetPos());
		enemy->UpdateInLosData();
		enemy->SetKnown(circuit->GetLastFrame());

		return !wasKnown;
	}

	if (hostileUnits.find(enemy->GetId()) == hostileUnits.end()) {
		hostileUnits[enemy->GetId()] = enemy;
	} else if (enemy->IsHidden()) {
		enemy->ClearHidden();
	}

	enemy->UpdateInRadarData(enemy->GetUnit()->GetPos());
	enemy->UpdateInLosData();
	threatMap->SetEnemyUnitRange(enemy);
	threatMap->SetEnemyUnitThreat(enemy);
	enemy->SetKnown(circuit->GetLastFrame());

	return !wasKnown;
}

void CMapManager::EnemyLeaveLOS(CEnemyUnit* enemy)
{
	enemy->ClearInLOS();
}

void CMapManager::EnemyEnterRadar(CEnemyUnit* enemy)
{
	// Possible cases:
	// (1) Unknown enemy wanders at radars
	// (2) Known enemy that once was in los wandering at radar
	// (3) EnemyEnterRadar invoked right after EnemyEnterLOS in area with no radar

	enemy->SetLastSeen(-1);
	enemy->SetInRadar();

	if (enemy->IsInLOS()) {  // (3)
		return;
	}

	if (!enemy->IsAttacker()) {  // (2)
		if (enemy->IsHidden()) {
			enemy->ClearHidden();
		}

		enemy->UpdateInRadarData(enemy->GetUnit()->GetPos());

		return;
	}

	bool isNew = false;
	auto it = hostileUnits.find(enemy->GetId());
	if (it == hostileUnits.end()) {  // (1)
		std::tie(it, isNew) = hostileUnits.emplace(enemy->GetId(), enemy);
	} else if (enemy->IsHidden()) {
		enemy->ClearHidden();
	}

	enemy->UpdateInRadarData(enemy->GetUnit()->GetPos());
	if (isNew) {  // unknown enemy enters radar for the first time
		threatMap->NewEnemy(enemy);
	}
}

void CMapManager::EnemyLeaveRadar(CEnemyUnit* enemy)
{
	enemy->SetLastSeen(circuit->GetLastFrame());
	enemy->ClearInRadar();
}

bool CMapManager::EnemyDestroyed(CEnemyUnit* enemy)
{
	const bool isKnown = enemy->IsKnown(circuit->GetLastFrame());

	auto it = hostileUnits.find(enemy->GetId());
	if (it == hostileUnits.end()) {
		peaceUnits.erase(enemy->GetId());
		return isKnown;
	}

	hostileUnits.erase(it);
	return isKnown;
}

void CMapManager::AddFakeEnemy(CEnemyFake* enemy)
{
	enemyFakes.insert(enemy);
	threatMap->SetEnemyUnitRange(enemy);
	threatMap->SetEnemyUnitThreat(enemy);
}

void CMapManager::DelFakeEnemy(CEnemyFake* enemy)
{
	enemyFakes.erase(enemy);
}

bool CMapManager::IsInLOS(const AIFloat3& pos) const
{
	// res = 1 << Mod->GetLosMipLevel();
	// the value for the full resolution position (x, z) is at index ((z * width + x) / res)
	// the last value, bottom right, is at index (width/res * height/res - 1)

	// FIXME: @see rts/Sim/Objects/SolidObject.cpp CSolidObject::UpdatePhysicalState
	//        for proper "underwater" implementation
	if (pos.y < -SQUARE_SIZE * 5) {  // Mod->GetRequireSonarUnderWater() = true
		const int x = (int)pos.x / radarResConv;
		const int z = (int)pos.z / radarResConv;
		if (sonarMap[z * radarWidth + x] <= 0) {
			return false;
		}
	}
	// convert from world coordinates to losmap coordinates
	const int x = (int)pos.x / losResConv;
	const int z = (int)pos.z / losResConv;
	return losMap[z * losWidth + x] > 0;
}

//bool CMapManager::IsInRadar(const AIFloat3& pos) const
//{
//	// the value for the full resolution position (x, z) is at index ((z * width + x) / res)
//	// the last value, bottom right, is at index (width/res * height/res - 1)
//
//	// convert from world coordinates to radarmap coordinates
//	const int x = (int)pos.x / radarResConv;
//	const int z = (int)pos.z / radarResConv;
//	return ((pos.y < -SQUARE_SIZE * 5) ? sonarMap : radarMap)[z * radarWidth + x] > 0;
//}

} // namespace circuit
