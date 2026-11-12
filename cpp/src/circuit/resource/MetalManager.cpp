/*
 * MetalManager.cpp
 *
 *  Created on: Dec 9, 2014
 *      Author: rlcevg
 */

#include "resource/MetalManager.h"

#include <algorithm>
#include <regex>
#include "map/ThreatMap.h"
#include "module/EconomyManager.h"
#include "setup/SetupManager.h"  // Only for json
#include "scheduler/Scheduler.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/GameAttribute.h"
#include "util/math/RagMatrix.h"
#include "util/math/Region.h"
#include "util/Utils.h"
#include "json/json.h"

#include "spring/SpringMap.h"

#include "Game.h"
#include "MoveData.h"
#include "Pathing.h"

namespace circuit {

using namespace springai;

class CMetalManager::SafeCluster : public lemon::MapBase<ClusterGraph::Node, bool> {
public:
	SafeCluster(CThreatMap* tm, const CMetalData::Clusters& cs)
		: threatMap(tm)
		, clusters(cs)
	{}
	Value operator[](Key k) const {
		return (*this)[CMetalData::ClusterGraph::id(k)];
	}
	Value operator[](int u) const {
		return threatMap->GetThreatAt(clusters[u].position) <= THREAT_MIN;
	}
private:
	CThreatMap* threatMap;
	const CMetalData::Clusters& clusters;
};

class CMetalManager::BuildCluster : public lemon::MapBase<ClusterGraph::Node, bool> {
public:
	BuildCluster(CMetalManager* mgr, CMetalData::PointPredicate& pred, std::vector<int>& outIdxs)
		: manager(mgr)
		, predicate(pred)
		, indices(outIdxs)
	{}
	Value operator[](Key k) const {
		const int u = CMetalData::ClusterGraph::id(k);
		if (manager->IsClusterQueued(u) || manager->IsClusterFinished(u)) {
			return false;
		}
		for (int index : manager->GetClusters()[u].idxSpots) {
			if (predicate(index)) {
				indices.push_back(index);
			}
		}
		return !indices.empty();
	}
private:
	CMetalManager* manager;
	CMetalData::PointPredicate predicate;
	std::vector<int>& indices;
};

class CMetalManager::UpgradeCluster : public lemon::MapBase<ClusterGraph::Node, bool> {
public:
	UpgradeCluster(CMetalManager* mgr, CMetalData::PointPredicate& pred, std::vector<int>& outIdxs)
		: manager(mgr)
		, predicate(pred)
		, indices(outIdxs)
	{}
	Value operator[](Key k) const {
		const int u = CMetalData::ClusterGraph::id(k);
		for (int index : manager->GetClusters()[u].idxSpots) {
			if (predicate(index)) {
				indices.push_back(index);
			}
		}
		return !indices.empty();
	}
private:
	CMetalManager* manager;
	CMetalData::PointPredicate predicate;
	std::vector<int>& indices;
};

std::vector<int> CMetalManager::indices;

CMetalManager::CMetalManager(CCircuitAI* circuit, CMetalData* metalData)
		: circuit(circuit)
		, metalData(metalData)
		, markFrame(-1)
		, threatFilter(nullptr)
		, filteredGraph(nullptr)
		, shortPath(nullptr)
{
	circuit->GetScheduler()->RunOnInit(CScheduler::GameJob(&CMetalManager::Init, this));

	if (!metalData->IsInitialized()) {
		// TODO: Add metal zone and no-metal-spots maps support
		ParseMetalSpots();
	}
	metalInfos.resize(metalData->GetSpots().size(), {true, -1});
	DetectMetalField();
}

// A METAL FIELD (his 11-10: "you should treat the metal extractors almost in the same way you treat building any energy
// building ... It's just a building"): most of the ground holds metal, so an extractor stands wherever a building fits
// and yields what the median spot does. The script places it like a converter (want_mex.as).
void CMetalManager::DetectMetalField()
{
	ShortVec fm;
	circuit->GetMap()->GetResourceMap(circuit->GetEconomyManager()->GetMetalRes(), fm);
	size_t rich = 0;
	for (short v : fm) {
		if (v > 0) {
			++rich;
		}
	}
	// normal maps read 0-1% (metal only at spots), metal maps 48-100% (SpeedMetal 0.48, FMP and Nine Metal Islands 1.00):
	// a fifth sits in the gap
	isMetalField = !fm.empty() && (rich * 5 > fm.size());
	const CMetalData::Metals& spots = metalData->GetSpots();
	if (isMetalField && !spots.empty()) {
		std::vector<float> fi;
		fi.reserve(spots.size());
		for (const CMetalData::SMetal& s : spots) {
			fi.push_back(s.income);
		}
		std::nth_element(fi.begin(), fi.begin() + fi.size() / 2, fi.end());
		fieldIncome = fi[fi.size() / 2];
	}
	circuit->LOG("apex: metal-field rich=%.2f field=%i inc=%.4f", fm.empty() ? 0.f : float(rich) / float(fm.size()),
			isMetalField ? 1 : 0, fieldIncome);
}

CMetalManager::~CMetalManager()
{
	delete threatFilter;
	delete filteredGraph;
	delete shortPath;
}

void CMetalManager::Init()
{
	clusterInfos.resize(GetClusters().size(), {0});
	for (unsigned i = 0; i < clusterInfos.size(); ++i) {
		for (int idx : GetClusters()[i].idxSpots) {
			metalInfos[idx].clusterId = i;
		}
	}

	threatFilter = new SafeCluster(circuit->GetThreatMap(), GetClusters());
	filteredGraph = new ClusterGraph(GetClusterGraph(), *threatFilter);
	shortPath = new ShortPath(*filteredGraph, GetClusterEdgeCosts());
}

void CMetalManager::ParseMetalSpots()
{
	Game* game = circuit->GetGame();
	std::vector<CMetalData::SMetal> spots;

	const Json::Value& root = circuit->GetSetupManager()->GetConfig();
	const bool calcMex = root["economy"].get("calc_mex", false).asBool();

	int mexCount = game->GetRulesParamFloat("mex_count", -1);
	if (calcMex || (mexCount <= 0)) {
		// FIXME: Replace metal-map workaround by own grid-spot generator
		CMap* map = circuit->GetMap();
		Resource* metalRes = circuit->GetEconomyManager()->GetMetalRes();
		F3Vec spotsPos;
		metalData->AnalyzeMap(circuit, map, metalRes, &circuit->GetGameAttribute()->GetTerrainData(), spotsPos);
		// NOTE: Ignores spots with income less than ~20% (50/255) of max spot
//		map->GetResourceMapSpotsPositions(metalRes, spotsPos);
		metalData->MakeResourcePoints(map, metalRes, spotsPos);
		const unsigned width = map->GetWidth();
		const unsigned height = map->GetHeight();
		const float mapSize = (width / 64) * (height / 64);
		const float offset = (float)rand() / RAND_MAX * 50.f - 25.f;
		//  8x8  ~  80 spots +-25
		// 24x24 ~ 240 spots +-25
		unsigned mCount = (240.f - 80.f) / (SQUARE(24.f) - SQUARE(8.f)) * (mapSize - SQUARE(8.f)) + 80.f + offset;
		// apex: AN EXTRACTOR GOES ANYWHERE THE GROUND HOLDS METAL (apex_metal_full; his 11-10: "on the metal maps ... you
		// can make a metal extractor anywhere. But we always just put them in whatever the designated spots are"). The
		// finder tiles the whole map (147,712 spots on Full Metal Plate, reach 24), then the thinning below keeps ~80-240
		// spread evenly, so the ground beside our base stood empty. Keeping 3,000 of them doubled income at 15 min (464
		// vs 190) and cost 4x the AI frame time. A player packs the ground AROUND HIS BASE: each start box gets a lattice
		// one extractor apart (a lane between, so units still pass), up to apex_metal_box_n spots; the thinned sample
		// stays for the rest of the map.
		const size_t found = spotsPos.size();
		const auto& boxes = circuit->GetGameAttribute()->GetSetupData().GetStartBoxes();
		if ((circuit->GetTunable("apex_metal_full", 0.f) > 0.f) && !boxes.empty() && (found > 0)) {
			std::vector<float> incs;
			incs.reserve(found);
			for (const AIFloat3& p : spotsPos) {
				incs.push_back(p.y);
			}
			std::nth_element(incs.begin(), incs.begin() + incs.size() / 2, incs.end());
			const float medInc = incs[incs.size() / 2];
			ShortVec mm;
			map->GetResourceMap(metalRes, mm);
			const int mw = width / 2, mh = height / 2;
			CCircuitDef* mdef = circuit->GetEconomyManager()->GetSideInfo().mexDef;
			const float foot = std::max(mdef->GetDef()->GetXSize(), mdef->GetDef()->GetZSize()) * SQUARE_SIZE;
			const float pitch = std::max(2.f * map->GetExtractorRadius(metalRes), foot);   // edge to edge (his 11-10: "right next to each other")
			const float boxN = std::max(circuit->GetTunable("apex_metal_box_n", 400.f), 16.f);
			const float budget = 2.f * boxN;   // lattice spots in all, shared by every base: the elections walk the list
			const float mapW = width * SQUARE_SIZE, mapH = height * SQUARE_SIZE;
			// where the bases are: the script's fixed start positions when it names them (a square round each); else
			// every start box whole, at a pitch wide enough to keep its count (positions are picked after this runs)
			std::vector<utils::SBox> dense;
			std::vector<float> pitches;
			{
				const std::string script = circuit->GetGame()->GetSetupScript();
				std::regex px("startposx=([0-9.]+);", std::regex::ECMAScript | std::regex::icase);
				std::regex pz("startposz=([0-9.]+);", std::regex::ECMAScript | std::regex::icase);
				std::vector<float> xs, zs;
				for (std::sregex_iterator it(script.begin(), script.end(), px), e; it != e; ++it) {
					xs.push_back(std::stof((*it)[1].str()));
				}
				for (std::sregex_iterator it(script.begin(), script.end(), pz), e; it != e; ++it) {
					zs.push_back(std::stof((*it)[1].str()));
				}
				if (!xs.empty() && (xs.size() == zs.size())) {
					for (size_t i = 0; i < xs.size(); ++i) {
						const float side = std::sqrt(std::max(budget / float(xs.size()), 16.f)) * pitch;
						dense.push_back(utils::SBox(xs[i] - 0.5f * side, xs[i] + 0.5f * side, zs[i] - 0.5f * side, zs[i] + 0.5f * side));
						pitches.push_back(pitch);
					}
				} else {
					for (const auto& kv : boxes) {
						const utils::SBox& b = kv.second.GetBox();
						const float m = 4.f * pitch;
						const utils::SBox sq(b.left - m, b.right + m, b.top - m, b.bottom + m);
						const float area = (sq.right - sq.left) * (sq.bottom - sq.top);
						dense.push_back(sq);
						pitches.push_back(std::max(pitch, std::sqrt(std::max(area, 1.f) * float(boxes.size()) / budget)));
					}
				}
			}
			int lattice = 0;
			for (size_t di = 0; di < dense.size(); ++di) {
				const utils::SBox& sq = dense[di];
				const float pt = pitches[di];
				for (float z = sq.top; z <= sq.bottom; z += pt) {
					for (float x = sq.left; x <= sq.right; x += pt) {
						if ((x < foot) || (z < foot) || (x > mapW - foot) || (z > mapH - foot)) {
							continue;
						}
						const int ix = int(x) / (SQUARE_SIZE * 2), iz = int(z) / (SQUARE_SIZE * 2);
						if ((ix < 0) || (iz < 0) || (ix >= mw) || (iz >= mh) || (mm[iz * mw + ix] <= 0)) {
							continue;
						}
						spots.push_back({medInc, AIFloat3(x, map->GetElevationAt(x, z), z)});
						++lattice;
					}
				}
			}
			// the thinned sample, outside the lattices
			std::vector<AIFloat3> rest;
			for (const AIFloat3& p : spotsPos) {
				bool in = false;
				for (const utils::SBox& sq : dense) {
					if ((p.x >= sq.left - pitch) && (p.x <= sq.right + pitch) && (p.z >= sq.top - pitch) && (p.z <= sq.bottom + pitch)) {
						in = true;
						break;
					}
				}
				if (!in) {
					rest.push_back(p);
				}
			}
			spotsPos.swap(rest);
			circuit->LOG("apex: metal-spots found=%i lattice=%i bases=%i pitch=%.0f rest=%i reach=%.0f", (int)found,
					lattice, (int)dense.size(), pitch, (int)spotsPos.size(), map->GetExtractorRadius(metalRes));
		} else {
			circuit->LOG("apex: metal-spots found=%i kept~%u reach=%.0f", (int)found, mCount,
					map->GetExtractorRadius(metalRes));
		}
		unsigned inc;
		if (spotsPos.size() > mCount) {
			inc = spotsPos.size() / mCount;
			spots.reserve(mCount);
		} else {
			inc = 1;
			spots.reserve(spotsPos.size());
		}
		CCircuitDef* mexDef = circuit->GetEconomyManager()->GetSideInfo().mexDef;
//		const float extrRange = SQUARE_SIZE * 2;  // map->GetExtractorRadius(metalRes) / 2;  // mexDef->GetExtrRangeM();
//		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		const int xsize = mexDef->GetDef()->GetXSize();
		const int zsize = mexDef->GetDef()->GetZSize();
		for (unsigned i = 0; i < spotsPos.size(); i += inc) {
			AIFloat3& pos = spotsPos[i];
			// move position closer to center
//			pos.x += extrRange;  // xsize * SQUARE_SIZE / 2;
//			pos.z += extrRange;  // zsize * SQUARE_SIZE / 2;
//			CTerrainManager::SnapPosition(pos);  // IBuilderTask::SetBuildPos uses CTerrainManager::Pos2BuildPos(cdef, position)
			const unsigned x1 = int(pos.x) / SQUARE_SIZE - (xsize / 2), x2 = x1 + xsize;
			const unsigned z1 = int(pos.z) / SQUARE_SIZE - (zsize / 2), z2 = z1 + zsize;
			if ((x1 < x2) && (x2 < width) && (z1 < z2) && (z2 < height)
				/*&& terrainMgr->CanBeBuiltAt(mexDef, pos)*/)  // FIXME: Water def?
			{
				const float y = map->GetElevationAt(pos.x, pos.z);
				spots.push_back({pos.y, AIFloat3(pos.x, y, pos.z)});
			}
		}

	} else {

		mexCount = std::min(mexCount, 1000);  // safety measure
		spots.resize(mexCount);
		for (int i = 0; i < mexCount; ++i) {
			std::string param;
			param = utils::int_to_string(i + 1, "mex_x%i");
			spots[i].position.x = game->GetRulesParamFloat(param.c_str(), 0.f);
			param = utils::int_to_string(i + 1, "mex_y%i");
			spots[i].position.y = game->GetRulesParamFloat(param.c_str(), 0.f);
			param = utils::int_to_string(i + 1, "mex_z%i");
			spots[i].position.z = game->GetRulesParamFloat(param.c_str(), 0.f);
			param = utils::int_to_string(i + 1, "mex_metal%i");
			spots[i].income = game->GetRulesParamFloat(param.c_str(), 0.f);
//			CTerrainManager::SnapPosition(spots[i].position);  // IBuilderTask::SetBuildPos uses CTerrainManager::Pos2BuildPos(cdef, position)
		}
	}

	metalData->Init(std::move(spots));
}

void CMetalManager::ClusterizeMetal(CCircuitDef* commDef)
{
	metalData->SetClusterizing(true);

	const float maxDistance = circuit->GetEconomyManager()->GetClusterRange();
	const CMetalData::Metals& spots = metalData->GetSpots();
	int nrows = spots.size();

	CRagMatrix<float> distmatrix(nrows);
	if (nrows <= 300) {
		MoveData* moveData = commDef->GetDef()->GetMoveData();
		int pathType = moveData->GetPathType();
		delete moveData;
		Pathing* pathing = circuit->GetPathing();
		for (int i = 1; i < nrows; i++) {
			for (int j = 0; j < i; j++) {
				float geomLength = spots[i].position.distance2D(spots[j].position);
				if (geomLength > 4 * maxDistance) {
					distmatrix(i, j) = geomLength;
				} else {
					float pathLength = pathing->GetApproximateLength(spots[i].position, spots[j].position, pathType, 0.0f);
					distmatrix(i, j) = (geomLength * 1.4f < pathLength) ? pathLength : geomLength;
				}
			}
		}
	} else {
		for (int i = 1; i < nrows; i++) {
			for (int j = 0; j < i; j++) {
				distmatrix(i, j) = spots[i].position.distance2D(spots[j].position);
			}
		}
	}

	metalData->Clusterize(maxDistance, distmatrix);
	metalData->Statistics();
}

void CMetalManager::FindWithinRangeSpots(const AIFloat3& posFrom, const AIFloat3& posTo,
										 CMetalData::IndicesDists& outIndices) const
{
	const AIFloat3 pos = (posFrom + posTo) / 2;
	const float radius = posFrom.distance2D(posTo) / 2;
	CMetalData::IndicesDists indices;
	FindSpotsInRadius(pos, radius, indices);
	const CMetalData::Metals& spots = GetSpots();
	const utils::SBox box(posFrom.x, posTo.x, posFrom.z, posTo.z);
	for (auto& kv : indices) {
		if (box.ContainsPoint(spots[kv.first].position)) {
			outIndices.push_back(kv);
		}
	}
}

void CMetalManager::SetOpenSpot(int index, bool value)
{
	if (!IsValidSpot(index)) {
		return;
	}
	if (metalInfos[index].isOpen != value) {
		metalInfos[index].isOpen = value;
		// clusterId stays -1 until clusterization assigns it.
		const int clusterId = metalInfos[index].clusterId;
		if ((clusterId >= 0) && ((size_t)clusterId < clusterInfos.size())) {
			clusterInfos[clusterId].queuedCount += value ? -1 : 1;
		}
	}
}

void CMetalManager::SetOpenSpot(const springai::AIFloat3& pos, bool value)
{
	int index = FindNearestSpot(pos);
	if (index != -1) {
		SetOpenSpot(index, value);
	}
}

bool CMetalManager::IsOpenSpot(const springai::AIFloat3& pos) const
{
	int index = FindNearestSpot(pos);
	if (index != -1) {
		return IsOpenSpot(index);
	}
	return false;
}

void CMetalManager::MarkAllyMexes()
{
	if (markFrame /*+ FRAMES_PER_SEC*/ >= circuit->GetLastFrame()) {
		return;
	}

	circuit->UpdateFriendlyUnits();
	// apex: same list, same marks -- the list only changes on a refresh pass
	const int ver = circuit->GetAllyTeam()->GetFriendlyVersion();
	if (ver == markVersion) {
		return;
	}
	markVersion = ver;
	const CAllyTeam::AllyUnits& friendlies = circuit->GetFriendlyUnits();
	static std::vector<CAllyUnit*> tmpMexes;  // NOTE: micro-opt
//	tmpMexes.reserve(friendlies.size());
	for (auto& kv : friendlies) {
		CAllyUnit* unit = kv.second;
		if (unit->GetCircuitDef()->IsMex()) {
			tmpMexes.push_back(unit);
		}
	}

	MarkAllyMexes(tmpMexes);

	tmpMexes.clear();
}

void CMetalManager::MarkAllyMexes(const std::vector<CAllyUnit*>& mexes)
{
	if (markFrame /*+ FRAMES_PER_SEC*/ >= circuit->GetLastFrame()) {
		return;
	}
	markFrame = circuit->GetLastFrame();

	decltype(markedMexes) prevUnits = std::move(markedMexes);
	markedMexes.clear();
	auto first1  = mexes.begin();
	auto last1   = mexes.end();
	auto first2  = prevUnits.begin();
	auto last2   = prevUnits.end();
	auto d_first = std::back_inserter(markedMexes);
	auto addMex = [&d_first, this](CAllyUnit* unit) {
		SMex mex;
		mex.index = FindNearestSpot(unit->GetPos(this->circuit->GetLastFrame()));
		if (mex.index != -1) {
			mex.unitId = unit->GetId();
			*d_first++ = mex;
			clusterInfos[metalInfos[mex.index].clusterId].finishedCount++;
			SetOpenSpot(mex.index, false);  // circuit->IsAllyAware()?
		}
	};
	auto delMex = [this](const SMex& mex) {
		clusterInfos[metalInfos[mex.index].clusterId].finishedCount--;
		SetOpenSpot(mex.index, true);  // circuit->IsAllyAware()?
	};

	// @see std::set_symmetric_difference + std::set_intersection
	while (first1 != last1) {
		if (first2 == last2) {
			addMex(*first1);  // everything else in first1..last1 is new units
			while (++first1 != last1) {
				addMex(*first1);
			}
			break;
		}

		if ((*first1)->GetId() < first2->unitId) {
			addMex(*first1);  // new unit
			++first1;  // advance mexes
		} else {
			if (first2->unitId < (*first1)->GetId()) {
				delMex(*first2);  // dead unit
			} else {
				*d_first++ = *first2;  // old unit
				++first1;  // advance mexes
			}
			++first2;  // advance prevUnits
		}
	}
	while (first2 != last2) {  // everything else in first2..last2 is dead units
		delMex(*first2++);
	}
}

bool CMetalManager::IsMexInFinished(int index) const
{
	// NOTE: finishedCount updated on lazy MarkAllyMexes call, thus can be invalid
	int idx = metalInfos[index].clusterId;
	return clusterInfos[idx].finishedCount >= GetClusters()[idx].idxSpots.size();
}

int CMetalManager::GetSpotToBuild(const AIFloat3& pos, CMetalData::PointPredicate& predicate)
{
	BuildCluster goal(this, predicate, indices);
	return GetSpotToDo(pos, predicate, [&goal](ShortPath* shortPath) {
		return shortPath->start(goal);
	});
}

int CMetalManager::GetSpotToUpgrade(const AIFloat3& pos, CMetalData::PointPredicate& predicate)
{
	UpgradeCluster goal(this, predicate, indices);
	return GetSpotToDo(pos, predicate, [&goal](ShortPath* shortPath) {
		return shortPath->start(goal);
	});
}

bool CMetalManager::IsSpotValid(int index, const AIFloat3& pos) const
{
	if ((index < 0) || ((size_t)index >= GetSpots().size())) {
		return false;
	}
	return utils::is_equal_pos(GetSpots()[index].position, pos);
}

int CMetalManager::GetSpotToDo(const AIFloat3& pos, CMetalData::PointPredicate& predicate,
		std::function<CMetalData::ClusterGraph::Node (ShortPath* shortPath)>&& doGoal)
{
	int index = FindNearestCluster(pos);
	if (index < 0 || !(*threatFilter)[index]) {
		return -1;
	}
	MarkAllyMexes();

	shortPath->init();
	shortPath->addSource(filteredGraph->nodeFromId(index));
	CMetalData::ClusterGraph::Node target = doGoal(shortPath);

	int result = -1;
	if (target != lemon::INVALID) {
		float sqMinDist = std::numeric_limits<float>::max();
		for (int index : indices) {
			float sqDist = GetSpots()[index].position.SqDistance2D(pos);
			if (sqDist < sqMinDist) {
				sqMinDist = sqDist;
				result = index;
			}
		}
	}
	indices.clear();
	return result;
}

} // namespace circuit
