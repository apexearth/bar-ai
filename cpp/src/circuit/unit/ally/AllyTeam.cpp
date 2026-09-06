/*
 * AllyTeam.cpp
 *
 *  Created on: Apr 7, 2015
 *      Author: rlcevg
 */

#include "unit/ally/AllyTeam.h"
#include "unit/FactoryData.h"
#include "map/MapManager.h"
#include "map/ThreatMap.h"
#include "resource/MetalManager.h"
#include "resource/EnergyManager.h"
#include "resource/EnergyGrid.h"
#include "scheduler/Scheduler.h"
#include "setup/DefenceData.h"
#include "setup/SetupManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/TerrainData.h"
#include "terrain/TerrainManager.h"  // Only for ApplyAuthority
#include "CircuitAI.h"
#include "util/math/RayBox.h"
#include "util/GameAttribute.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AIFloat3.h"
#include "Team.h"
#include "Log.h"

#include <algorithm>
#include <chrono>

namespace circuit {

using namespace springai;
using namespace terrain;

CAllyTeam::CAllyTeam(const TeamIds& tids, const utils::CRegion& sb)
		: circuit(nullptr)
		, teamIds(tids)
		, startBox(sb)
		, initCount(0)
		, resignSize(0)
		, lastUpdate(-1)
		, isResetStart(true)
		, uEnemyMark(0)
{
}

CAllyTeam::~CAllyTeam()
{
	if (initCount > 0) {
		initCount = 1;
		Release();
	}
}

const CAllyTeam::Id CAllyTeam::GetLeaderId() const
{
	return circuit->GetTeamId();
}

void CAllyTeam::Init(CCircuitAI* circuit, float decloakRadius)
{
	if (initCount++ > 0) {
		mapManager->GetThreatMap()->CopyDefs(circuit);
		return;
	}

	this->circuit = circuit;

	quadField.Init(int2(circuit->GetMap()->GetWidth(), circuit->GetMap()->GetHeight()), CQuadField::BASE_QUAD_SIZE);

	int boxId = circuit->GetTeam()->GetRulesParamFloat("start_box_id", -1);
	if (boxId >= 0) {
		startBox = circuit->GetGameAttribute()->GetSetupData().GetStartBox(boxId);
	}

	mapManager = std::make_shared<CMapManager>(circuit, decloakRadius);
	mapManager->InitMaps();
	enemyManager = std::make_shared<CEnemyManager>(circuit);
	enemyManager->ReadConfig();

	uEnemyMark = circuit->GetSkirmishAIId() % THREAT_UPDATE_RATE;

	metalManager = std::make_shared<CMetalManager>(circuit, &circuit->GetGameAttribute()->GetMetalData());
	if (metalManager->HasMetalSpots() && !metalManager->HasMetalClusters() && !metalManager->IsClusterizing()) {
		metalManager->ClusterizeMetal(circuit->GetSetupManager()->GetCommChoice());
	}

	energyManager = std::make_shared<CEnergyManager>(circuit, &circuit->GetGameAttribute()->GetEnergyData());
	energyGrid = std::make_shared<CEnergyGrid>(circuit);
	energyGrid->ReadConfig();
	defence = std::make_shared<CDefenceData>(circuit);
	defence->ReadConfig(circuit);
	pathfinder = std::make_shared<CPathFinder>(&circuit->GetGameAttribute()->GetTerrainData(), circuit->GetScheduler()->GetMaxWorkThreads());
	factoryData = std::make_shared<CFactoryData>();

	releaseTask = CScheduler::GameJob(&CAllyTeam::DelegateAuthority, this);
	circuit->GetScheduler()->RunOnRelease(releaseTask);
}

void CAllyTeam::NonDefaultThreats(std::set<CCircuitDef::RoleT>&& modRoles, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	mapManager->GetThreatMap()->Init(circuit->GetGameAttribute()->GetRoleMasker().GetMasks().size(), std::move(modRoles));
}

void CAllyTeam::InitThreatRanges(CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	mapManager->GetThreatMap()->InitRanges();
}

void CAllyTeam::Release()
{
	resignSize++;
	if (--initCount > 0) {
		return;
	}

	for (auto& kv : friendlyUnits) {
		delete kv.second;
	}
	friendlyUnits.clear();

	mapManager = nullptr;
	metalManager = nullptr;
	energyManager = nullptr;
	energyGrid = nullptr;
	defence = nullptr;
	pathfinder = nullptr;
	factoryData = nullptr;

	quadField.Kill();
}

// apex: the throttle below must not defeat the force -- jump clear of it.
void CAllyTeam::ForceUpdateFriendlyUnits()
{
	lastUpdate = -1000000;
	UpdateFriendlyUnits();
}

void CAllyTeam::UpdateFriendlyUnits()
{
	// FIXME: Works bad because of circuit->GetCircuitDef(unitDefId) inside allyTeam:
	//   If resigned ai updated the list then all teammates will have broken links to CCircuitDef*.
	// Options:
	//   1) save CCircuitDef::Id instead of pointer. But u->GetCircuitDef() is too spread out to fix it now.
	//   2) Move friendlyUnits from CAllyTeam level to CCircuitAI (and eat more memory and cpu on updates for each ai instance).
	// apex: half a second of tolerance, not one frame -- measured 630
	// rebuilds a minute at 1,151 units (1.8s of every game-minute) because
	// any task update may demand the list. Consumers already tolerate
	// intra-frame staleness (a death after the frame's rebuild dangles
	// until the next one); this is the same contract, wider.
	// ForceUpdateFriendlyUnits stays the exact path.
	constexpr int FRIENDLY_REFRESH_FRAMES = 15;
	if (circuit->GetLastFrame() - lastUpdate < FRIENDLY_REFRESH_FRAMES) {
		return;
	}

	const auto tFr0 = std::chrono::steady_clock::now();
	COOAICallback* clb = circuit->GetCallback();
	// apex: diff the map by unit id instead of tearing it down. The rebuild
	// cost three heap round trips per unit per pass (WrappUnit, CAllyUnit, map
	// node) and the map was re-grown from empty every time, so it scaled with
	// the whole army rather than with what changed.
	friendlyIds = clb->GetFriendlyUnitIds();
	std::sort(friendlyIds.begin(), friendlyIds.end());
	friendlyIds.erase(std::unique(friendlyIds.begin(), friendlyIds.end()), friendlyIds.end());

	auto it = friendlyUnits.begin();
	size_t i = 0;
	while ((it != friendlyUnits.end()) && (i < friendlyIds.size())) {
		if (it->first < friendlyIds[i]) {  // gone since the last pass
			delete it->second;
			it = friendlyUnits.erase(it);
			++perfFrDel;
		} else if (it->first > friendlyIds[i]) {  // never seen
			const ICoreUnit::Id unitId = friendlyIds[i++];
			const CCircuitDef::Id unitDefId = clb->Unit_GetDefId(unitId);
			friendlyUnits.emplace_hint(it, unitId,
					new CAllyUnit(unitId, clb->WrapUnit(unitId), circuit->GetCircuitDef(unitDefId)));
			++perfFrAdd;
		} else {  // same unit: the def is still re-read, a morph changes it
			const CCircuitDef::Id unitDefId = clb->Unit_GetDefId(it->first);
			it->second->SetAllyCircuitDef(circuit->GetCircuitDef(unitDefId));
			++it;
			++i;
		}
	}
	while (it != friendlyUnits.end()) {
		delete it->second;
		it = friendlyUnits.erase(it);
		++perfFrDel;
	}
	for (; i < friendlyIds.size(); ++i) {
		const ICoreUnit::Id unitId = friendlyIds[i];
		const CCircuitDef::Id unitDefId = clb->Unit_GetDefId(unitId);
		friendlyUnits.emplace_hint(friendlyUnits.end(), unitId,
				new CAllyUnit(unitId, clb->WrapUnit(unitId), circuit->GetCircuitDef(unitDefId)));
		++perfFrAdd;
	}

	lastUpdate = circuit->GetLastFrame();
	perfFrUs += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - tFr0).count();
	++perfFrCalls;
	if (lastUpdate >= perfFrNextLog) {
		perfFrNextLog = lastUpdate + 1800;
		circuit->LOG("apex: perf friendly calls=%u totalMs=%.1f units=%i add=%u del=%u",
				perfFrCalls, perfFrUs / 1000.f, (int)friendlyUnits.size(), perfFrAdd, perfFrDel);
		perfFrUs = 0;
		perfFrCalls = 0;
		perfFrAdd = 0;
		perfFrDel = 0;
	}
}

CAllyUnit* CAllyTeam::GetFriendlyUnit(ICoreUnit::Id unitId) const
{
	decltype(friendlyUnits)::const_iterator it = friendlyUnits.find(unitId);
	return (it != friendlyUnits.end()) ? it->second : nullptr;
}

bool CAllyTeam::EnemyInLOS(CEnemyUnit* data, CCircuitAI* ai)
{
	if (circuit != ai) {
		return !data->IsIgnore();
	}

	return enemyManager->UnitInLOS(data);
}

std::pair<CEnemyUnit*, bool> CAllyTeam::RegisterEnemyUnit(ICoreUnit::Id unitId, bool isInLOS, CCircuitAI* ai)
{
	if (circuit != ai) {
		return std::make_pair(enemyManager->GetEnemyUnit(unitId), true);
	}

	return enemyManager->RegisterEnemyUnit(unitId, isInLOS);
}

CEnemyUnit* CAllyTeam::RegisterEnemyUnit(Unit* e, CCircuitAI* ai)
{
	if (circuit != ai) {
		const ICoreUnit::Id unitId = e->GetUnitId();
		delete e;
		return enemyManager->GetEnemyUnit(unitId);
	}

	return enemyManager->RegisterEnemyUnit(e);
}

void CAllyTeam::UnregisterEnemyUnit(CEnemyUnit* data, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	enemyManager->UnregisterEnemyUnit(data);
}

void CAllyTeam::RegisterEnemyFake(CCircuitDef::Id unitDefId, const AIFloat3& pos, int timeout)
{
	CEnemyFake* data = enemyManager->RegisterEnemyFake(unitDefId, pos, timeout);
	mapManager->AddFakeEnemy(data);
	quadField.MovedEnemyFake(data);
}

void CAllyTeam::UnregisterEnemyFake(CEnemyFake* data)
{
	quadField.RemoveEnemyFake(data);
	mapManager->DelFakeEnemy(data);
	enemyManager->UnregisterEnemyFake(data);
}

void CAllyTeam::EnemyEnterLOS(CEnemyUnit* enemy, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	if (mapManager->EnemyEnterLOS(enemy)) {
		enemyManager->AddEnemyCost(enemy);
	}
}

void CAllyTeam::EnemyLeaveLOS(CEnemyUnit* enemy, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	mapManager->EnemyLeaveLOS(enemy);
}

void CAllyTeam::EnemyEnterRadar(CEnemyUnit* enemy, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	mapManager->EnemyEnterRadar(enemy);
}

void CAllyTeam::EnemyLeaveRadar(CEnemyUnit* enemy, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	mapManager->EnemyLeaveRadar(enemy);
}

void CAllyTeam::EnemyDestroyed(CEnemyUnit* enemy, CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	if (mapManager->EnemyDestroyed(enemy)) {
		enemyManager->DelEnemyCost(enemy);
	}

	quadField.RemoveEnemyUnit(enemy);
}

void CAllyTeam::UpdateInLOS(CEnemyUnit* data, CCircuitDef::Id unitDefId)
{
	enemyManager->DelEnemyCost(data);
	enemyManager->UnitInLOS(data, unitDefId);
	mapManager->EnemyEnterLOS(data);
	enemyManager->AddEnemyCost(data);
}

void CAllyTeam::Update(CCircuitAI* ai)
{
	if (circuit != ai) {
		return;
	}

	if (circuit->GetLastFrame() % THREAT_UPDATE_RATE == uEnemyMark) {
		EnqueueUpdate();
	} else {
		enemyManager->UpdateEnemyDatas(quadField);
	}
}

void CAllyTeam::EnqueueUpdate()
{
	if (enemyManager->IsUpdating() || mapManager->IsUpdating()) {
		return;
	}

	mapManager->PrepareUpdate();
	enemyManager->PrepareUpdate();

	mapManager->EnqueueUpdate();
	enemyManager->EnqueueUpdate();
}

CEnemyUnit* CAllyTeam::GetEnemyOrFakeIn(const AIFloat3& startPos, const AIFloat3& dir, float length,
		const AIFloat3& enemyPos, float radius, const std::set<CCircuitDef::Id>& unitDefIds)
{
	QuadFieldQuery qfQuery(quadField);
	quadField.GetEnemyAndFakes(qfQuery, enemyPos, radius);  // TODO: predicate
	for (CEnemyUnit* e : *qfQuery.enemyUnits) {
		CCircuitDef* edef = e->GetCircuitDef();
		if ((edef != nullptr) && (unitDefIds.find(edef->GetId()) != unitDefIds.end())) {
			return e;
		}
	}
	for (CEnemyFake* e : *qfQuery.enemyFakes) {
		CCircuitDef* edef = e->GetCircuitDef();
		if (unitDefIds.find(edef->GetId()) != unitDefIds.end()) {
			return e;
		}
	}

	const CRay ray(startPos, dir);
	const AIFloat3 offset(SQUARE_SIZE * 8, SQUARE_SIZE * 8, SQUARE_SIZE * 8);
	// WARNING: Do not reuse QuadFieldQuery within same scope. Otherwise cached vector may stuck in limbo.
	//   In this particular case it looks safe because quadField.GetEnemyAndFakes reserves enemyUnits and enemyFakes,
	//   while quadField.GetQuadsOnRay reserves quads only.
	quadField.GetQuadsOnRay(qfQuery, startPos, dir, length - radius);
	for (const int quadIdx: *qfQuery.quads) {
		const CQuadField::Quad& quad = quadField.GetQuad(quadIdx);

		for (CEnemyUnit* e : quad.enemyUnits) {
			CCircuitDef* edef = e->GetCircuitDef();
			if ((edef != nullptr) && (unitDefIds.find(edef->GetId()) != unitDefIds.end())
				&& CAABBox(e->GetPos() - offset, e->GetPos() + offset).Intersection(ray))
			{
				return e;
			}
		}
		for (CEnemyFake* e : quad.enemyFakes) {
			CCircuitDef* edef = e->GetCircuitDef();
			if (unitDefIds.find(edef->GetId()) != unitDefIds.end()
				&& CAABBox(e->GetPos() - offset, e->GetPos() + offset).Intersection(ray))
			{
				return e;
			}
		}
	}

	return nullptr;
}

void CAllyTeam::OccupyCluster(int clusterId, int teamId)
{
	auto it = occupants.find(clusterId);
	if (it != occupants.end()) {
		it->second.count++;
	} else {
		occupants.insert(std::make_pair(clusterId, SClusterTeam(teamId, 1)));
	}
}

CAllyTeam::SClusterTeam CAllyTeam::GetClusterTeam(int clusterId)
{
	auto it = occupants.find(clusterId);
	if (it != occupants.end()) {
		return it->second;
	}
	return SClusterTeam(-1);
}

void CAllyTeam::OccupyArea(SArea* area, int teamId)
{
	auto it = habitants.find(area);
	if (it == habitants.end()) {
		habitants.insert(std::make_pair(area, SAreaTeam(teamId)));
	}
}

CAllyTeam::SAreaTeam CAllyTeam::GetAreaTeam(SArea* area)
{
	auto it = habitants.find(area);
	if (it != habitants.end()) {
		return it->second;
	}
	return SAreaTeam(-1);
}

void CAllyTeam::ResetStartOnce()
{
	if (isResetStart) {
		occupants.clear();
		habitants.clear();
	}
	isResetStart = false;
}

void CAllyTeam::SetAuthority(CCircuitAI* authority)
{
	// FIXME: Authority should be first one who gets message from the engine.
	//        Remove method, commented in SetupManager
	if (circuit == authority) {
		return;
	}
	circuit->GetScheduler()->RemoveReleaseJob(releaseTask);
	ApplyAuthority(authority);
}

void CAllyTeam::DelegateAuthority()
{
	std::map<Id, CCircuitAI*> teamAIs;
	for (CCircuitAI* newOwner : circuit->GetGameAttribute()->GetCircuits()) {
		if (newOwner->IsInitialized() && (newOwner != circuit) && (newOwner->GetAllyTeamId() == circuit->GetAllyTeamId())) {
			teamAIs[newOwner->GetSkirmishAIId()] = newOwner;
		}
	}
	if (!teamAIs.empty()) {
		ApplyAuthority(teamAIs.begin()->second);
	}
}

void CAllyTeam::ApplyAuthority(CCircuitAI* newOwner)
{
	this->circuit = newOwner;
	mapManager->SetAuthority(newOwner);
	metalManager->SetAuthority(newOwner);
	energyManager->SetAuthority(newOwner);
	energyGrid->SetAuthority(newOwner);

	UpdateFriendlyUnits();
	enemyManager->ApplyAuthority(newOwner);
	for (CCircuitAI* ai : circuit->GetGameAttribute()->GetCircuits()) {
		// TODO: Is updating oldOwner desired?
		if (ai->GetAllyTeamId() == circuit->GetAllyTeamId()) {
			ai->GetTerrainManager()->ApplyAuthority();
		}
	}

	releaseTask = CScheduler::GameJob(&CAllyTeam::DelegateAuthority, this);
	newOwner->GetScheduler()->RunOnRelease(releaseTask);
}

} // namespace circuit
