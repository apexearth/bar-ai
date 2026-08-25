/*
 * EnemyManager.cpp
 *
 *  Created on: Dec 25, 2019
 *      Author: rlcevg
 */

#include "unit/enemy/EnemyManager.h"
#include "unit/enemy/EnemyUnit.h"
#include "map/MapManager.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "scheduler/Scheduler.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"
#include "util/Profiler.h"
#include "json/json.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "WrappUnit.h"
#include "Cheats.h"

#include <limits>

namespace circuit {

using namespace springai;
using namespace terrain;

CEnemyManager::CEnemyManager(CCircuitAI* circuit)
		: circuit(circuit)
		, enemyIterator(0)
		, dyingFrame(-1)
		, pGroupData(&groupData0)
		, enemyGroups(groupData0.enemyGroups)
		, minThreatGroupIdx(0)
		, preMaxThreatGroupIdx(0)
		, maxThreatGroupIdx(0)
		, isUpdating(false)
		, enemyMobileCost(0.f)
		, mobileThreat(0.f)
		, staticThreat(0.f)
		, isAreaUpdated(true)
{
	enemyInfos.fill({0.f, 0.f});
	freshInfos.fill({0.f, 0.f});
	freshFrames = FRAMES_PER_SEC * 60;

	enemyPos = circuit->GetTerrainManager()->GetTerrainCenter();
	enemyGroups.push_back(SEnemyGroup(enemyPos));
}

CEnemyManager::~CEnemyManager()
{
//	for (CEnemyUnit* enemy : enemyDying) {
//		enemy->SetDead();
//	}
//	enemyDying.clear();
	for (CEnemyUnit* enemy : enemyUpdates) {
		if (enemy->IsDead() || enemy->IsDying()) {  // instance is not in enemyUnits
			delete enemy;
		}
	}
//	enemyUpdates.clear();
	for (auto& kv : enemyUnits) {
		delete kv.second;
	}
//	enemyUnits.clear();
	for (CEnemyFake* enemy : enemyFakes) {
		delete enemy;
	}
//	enemyFakes.clear();
}

void CEnemyManager::ApplyAuthority(CCircuitAI* authority)
{
	circuit = authority;

	for (auto& kv : enemyUnits) {
		CEnemyUnit* enemy = kv.second;
		delete enemy->GetUnit();
		enemy->unit = WrappUnit::GetInstance(authority->GetSkirmishAIId(), enemy->GetId());
		if (enemy->GetCircuitDef() != nullptr) {
			enemy->SetCircuitDef(authority->GetCircuitDef(enemy->GetCircuitDef()->GetId()));
		}
	}
	for (CEnemyUnit* enemy : enemyDying) {
		delete enemy->GetUnit();
		enemy->unit = WrappUnit::GetInstance(authority->GetSkirmishAIId(), enemy->GetId());
		if (enemy->GetCircuitDef() != nullptr) {
			enemy->SetCircuitDef(authority->GetCircuitDef(enemy->GetCircuitDef()->GetId()));
		}
	}
	for (CEnemyFake* ef : enemyFakes) {
		if (ef->GetCircuitDef() != nullptr) {
			// NOTE: Can't use CEnemyUnit::SetCircuitDef: unit==nullptr
			ef->data.cdef = authority->GetCircuitDef(ef->GetCircuitDef()->GetId());
		}
	}
}

CEnemyUnit* CEnemyManager::GetEnemyUnit(ICoreUnit::Id unitId) const
{
	auto it = enemyUnits.find(unitId);
	return (it != enemyUnits.end()) ? it->second : nullptr;
}

void CEnemyManager::UpdateEnemyDatas(CQuadField& quadField)
{
//	static std::vector<CEnemyUnit*> batchUpdate;

	if (enemyIterator >= enemyUpdates.size()) {
		enemyIterator = 0;
	}
	if (dyingFrame < circuit->GetLastFrame() - 1) {
		for (CEnemyUnit* enemy : enemyDying) {
			enemy->SetDead();
		}
		enemyDying.clear();
	}

	// stagger the Update's
	// -1 is for threat-draw and k-means frame
	unsigned int n = (enemyUpdates.size() / (THREAT_UPDATE_RATE - 1)) + 1;

	const int maxFrame = circuit->GetLastFrame() - FRAMES_PER_SEC * 60 * 20;
	while ((enemyIterator < enemyUpdates.size()) && (n != 0)) {
		CEnemyUnit* enemy = enemyUpdates[enemyIterator];
		if (enemy->IsDying()) {
			++enemyIterator;
			continue;
		}

		if (enemy->IsDead()) {
			DeleteEnemyUnit(enemy);
			continue;
		}

		int frame = enemy->GetLastSeen();
		if ((frame != -1) && (maxFrame >= frame)) {
			DyingEnemy(enemy);
			++enemyIterator;
			continue;
		}

		// Freshness: what we can see now, plus what we saw within freshFrames.
		// GetEnemyCost() itself never forgets a unit once registered.
		if (enemy->GetCircuitDef() != nullptr) {
			const int lastFrame = circuit->GetLastFrame();
			if (enemy->IsInRadarOrLOS()) {
				enemy->SetSeenFrame(lastFrame);
				if (!enemy->IsFresh()) {
					enemy->SetFresh();
					ModFresh(enemy, +1);
				}
			} else if (enemy->IsFresh()
					&& (enemy->IsHidden() || (lastFrame - enemy->GetSeenFrame() > freshFrames)))
			{
				ModFresh(enemy, -1);
				enemy->ClearFresh();
			}
		}

		if (enemy->IsInRadarOrLOS()) {
			const AIFloat3& pos = enemy->GetUnit()->GetPos();
			if (CTerrainData::IsNotInBounds(pos)) {  // NOTE: Unit id validation. No EnemyDestroyed sometimes apparently
				DyingEnemy(enemy);
				++enemyIterator;
				continue;
			}

			enemy->UpdateInRadarData(pos);
			quadField.MovedEnemyUnit(enemy);

			if (enemy->IsInLOS()) {
				// NOTE: batch-reading hack
//				batchUpdate.push_back(enemy);
				enemy->UpdateInLosData();  // heavy on engine calls
			}
		}

		++enemyIterator;
		--n;
	}

//	if (!circuit->IsCheating()) {
//		// AI knows what units are in los, hence reduce the amount of useless
//		// engine InLos checks for each single param of the enemy unit
//		circuit->GetCheats()->SetEnabled(true);
//	}
//
//	for (CEnemyUnit* enemy : batchUpdate) {
//		enemy->UpdateInLosData();  // heavy on engine calls
//	}
//	batchUpdate.clear();
//
//	if (!circuit->IsCheating()) {
//		circuit->GetCheats()->SetEnabled(false);
//	}
}

void CEnemyManager::PrepareUpdate()
{
	CMapManager* mapMgr = circuit->GetMapManager();

	hostileDatas.clear();
	hostileDatas.reserve(mapMgr->GetHostileUnits().size() + mapMgr->GetEnemyFakes().size());
	for (auto& kv : mapMgr->GetHostileUnits()) {
		CEnemyUnit* e = kv.second;

		if (!mapMgr->HostileInLOS(e)) {
			continue;
		}

		hostileDatas.push_back(e->GetData());
	}

	const int frame = circuit->GetLastFrame();
	std::vector<CEnemyFake*> deadFakes;
	for (CEnemyFake* e : mapMgr->GetEnemyFakes()) {
		if (/*mapMgr->IsInRadar(e->GetPos()) || */mapMgr->IsInLOS(e->GetPos()) || (frame >= e->GetTimeout())) {
			deadFakes.push_back(e);
		} else {
			hostileDatas.push_back(e->GetData());
		}
	}
	for (CEnemyFake* e : deadFakes) {
		circuit->GetAllyTeam()->UnregisterEnemyFake(e);
	}

	peaceDatas.clear();
	peaceDatas.reserve(mapMgr->GetPeaceUnits().size());
	for (auto& kv : mapMgr->GetPeaceUnits()) {
		CEnemyUnit* e = kv.second;

		if (!mapMgr->PeaceInLOS(e)) {
			continue;
		}

		peaceDatas.push_back(e->GetData());
	}
}

void CEnemyManager::EnqueueUpdate()
{
//	if (isUpdating) {
//		return;
//	}
	isUpdating = true;

	circuit->GetScheduler()->RunPriorityJob(CScheduler::WorkJob(&CEnemyManager::Update, this));
}

bool CEnemyManager::UnitInLOS(CEnemyUnit* data)
{
	CCircuitDef::Id unitDefId = circuit->GetCallback()->Unit_GetDefId(data->GetId());
	if (unitDefId == -1) {  // doesn't work with globalLOS
		return false;
	}
	if ((data->GetCircuitDef() == nullptr) || data->GetCircuitDef()->GetId() != unitDefId) {
		return UnitInLOS(data, unitDefId);
	}
	return true;
}

bool CEnemyManager::UnitInLOS(CEnemyUnit* data, CCircuitDef::Id unitDefId)
{
	CCircuitDef* cdef = circuit->GetCircuitDef(unitDefId);
	data->SetCircuitDef(cdef);
	data->SetCost(data->GetUnit()->GetRulesParamFloat("comm_cost", data->GetCost()));
	(cdef->IsIgnore() || (data->GetUnit()->GetRulesParamFloat("ignoredByAI", 0.f) > 0.f)) ? data->SetIgnore() : data->ClearIgnore();
	return !data->IsIgnore();
}

std::pair<CEnemyUnit*, bool> CEnemyManager::RegisterEnemyUnit(ICoreUnit::Id unitId, bool isInLOS)
{
	// NOTE: Authority change issue: EnemyUnit already registered by oldOwner,
	//       may result in consecutive RegisterEnemyUnit call
	CEnemyUnit* data = GetEnemyUnit(unitId);
	if (data != nullptr) {
		if (!isInLOS || UnitInLOS(data)) {
			return std::make_pair(data, true);
		}
		return std::make_pair(nullptr, true);  // error, maybe globalLOS
	}

	Unit* e = WrappUnit::GetInstance(circuit->GetSkirmishAIId(), unitId);
	if (e == nullptr) {
		return std::make_pair(nullptr, true);  // true error
	}
	bool isIgnore = e->GetRulesParamFloat("ignoredByAI", 0.f) > 0.f;

	CCircuitDef* cdef = nullptr;
	if (isInLOS) {
		CCircuitDef::Id unitDefId = circuit->GetCallback()->Unit_GetDefId(unitId);
		if (unitDefId == -1) {  // doesn't work with globalLOS
			delete e;
			return std::make_pair(nullptr, false);
		}
		cdef = circuit->GetCircuitDef(unitDefId);
		isIgnore |= cdef->IsIgnore();
	}
	data = new CEnemyUnit(unitId, e, cdef);  // TODO: Use std::shared_ptr

	enemyUnits[unitId] = data;
	enemyUpdates.push_back(data);

	if (isIgnore) {
		data->SetIgnore();
	}

	return std::make_pair(data, true);
}

CEnemyUnit* CEnemyManager::RegisterEnemyUnit(Unit* e)
{
	const ICoreUnit::Id unitId = e->GetUnitId();
	CEnemyUnit* data = GetEnemyUnit(unitId);
	CCircuitDef::Id unitDefId = circuit->GetCallback()->Unit_GetDefId(unitId);
	bool isIgnore = e->GetRulesParamFloat("ignoredByAI", 0.f) > 0.f;

	if (data != nullptr) {
		if ((data->GetCircuitDef() == nullptr) || data->GetCircuitDef()->GetId() != unitDefId) {
			CCircuitDef* cdef = circuit->GetCircuitDef(unitDefId);
			data->SetCircuitDef(cdef);
			data->SetCost(data->GetUnit()->GetRulesParamFloat("comm_cost", data->GetCost()));
			isIgnore |= cdef->IsIgnore();
		}
		if (isIgnore) {
			data->SetIgnore();
		}
		delete e;
		return data;
	}

	CCircuitDef* cdef = circuit->GetCircuitDefSafe(unitDefId);
	if (cdef != nullptr) {
		isIgnore |= cdef->IsIgnore();
	}
	data = new CEnemyUnit(unitId, e, cdef);

	enemyUnits[unitId] = data;
	enemyUpdates.push_back(data);

	if (isIgnore) {
		data->SetIgnore();
	}

	return data;
}

CEnemyFake* CEnemyManager::RegisterEnemyFake(CCircuitDef::Id unitDefId, const AIFloat3& pos, int timeout)
{
	CEnemyFake* data = new CEnemyFake(circuit->GetCircuitDef(unitDefId), pos, timeout);
	enemyFakes.insert(data);
	return data;
}

void CEnemyManager::UnregisterEnemyFake(CEnemyFake* data)
{
	enemyFakes.erase(data);
	delete data;
}

void CEnemyManager::UnregisterEnemyUnit(CEnemyUnit* data)
{
	enemyUnits.erase(data->GetId());
	data->SetDying();
}

void CEnemyManager::DyingEnemy(CEnemyUnit* enemy, int frame)
{
	dyingFrame = frame;
	DyingEnemy(enemy);
}

// apex: GHOSTS ONLY GROW. A unit killed out of LOS never sends
// EnemyDestroyed, so its entry lives forever -- by minute 60 of an 8v8 the
// registry holds every enemy that ever existed, and every consumer that
// walks it (PrepareUpdate, per-def scans, the stock BombTask) pays a cost
// proportional to game AGE, not to the live world; measured as the AI-C++
// 6->9 s/min late-game creep. A ghost hidden and unseen for maxAgeFrames
// dies through the SAME DyingEnemy pipeline a real death uses, so every
// counter and per-circuit view stays consistent. Re-sighting a purged spot
// re-registers the unit fresh -- behaviour preserved, memory bounded. The
// deliberate cost: GetEnemyCost pessimism decays past the purge age, which
// is also what stopped the repeat-nuking of long-dead ground.
// Two tiers (apexearth: "a ten minute timeout is not good enough... if you
// are viewing an area that had information... and you now have a different
// set of things there, you replace the past registry information"):
// HIDDEN is exactly that reconciliation -- CMapManager::HostileInLOS sets it
// the moment our vision covers an entry's last-known ground and the unit is
// not there -- so a hidden entry is VISION-CONFIRMED stale and earns only a
// short fuse (it may have slipped into adjacent fog; the sizing pessimism
// keeps it that long and no longer). An entry whose ground we NEVER
// re-viewed is a genuine unknown -- the pessimism the massing sizing relies
// on -- and keeps the long fuse.
// apex: enemy AIR value near a point, on the same guarded walk the purge uses
// -- the circuit-level enemyInfos map holds wrappers whose data dies before the
// deferred per-circuit erase, and iterating THAT from script crashed at every
// commander blast (2026-08-18, seeds 120/121/123).
// apex: THE COSTLIEST MOBILE THEY HAVE SHOWN US -- a tier reading the script
// cannot otherwise take. CEnemyManager exposes only per-ROLE aggregates, and
// role does not separate a T1 assault bot from a T2 one, so the old
// Factory::gEnemyT2Seen sense had no replacement when it died with the leaf
// rules. Unit cost is what actually scales across tiers, so the script can ask
// whether their best outclasses ours without naming a tier or a number.
//
// Same guarded walk the air survey uses: the circuit-level map holds wrappers
// whose data dies before the deferred erase, and iterating it from script
// crashed at every commander blast.
float CEnemyManager::GetEnemyMaxMobileCostM() const
{
	float best = 0.f;
	for (CEnemyUnit* e : enemyUpdates) {
		if ((e == nullptr) || e->IsDying()) {
			continue;
		}
		CCircuitDef* cdef = e->GetCircuitDef();
		// BUILDERS EXCLUDED, COMMANDER ABOVE ALL. It is mobile and costs 2700,
		// so it outranks every T1 combat unit and made this read 2700 from
		// frame one -- a permanent 'they are ahead' that says nothing about
		// tier. The caller's own side excludes builders too; comparing the
		// two on different bases is the mismatch this whole reading exists
		// to avoid.
		if ((cdef == nullptr) || !cdef->IsMobile() || cdef->IsBuilder()) {
			continue;
		}
		const float c = cdef->GetCostM();
		if (c > best) {
			best = c;
		}
	}
	return best;
}

float CEnemyManager::GetEnemyAirCostNear(const springai::AIFloat3& pos, float radius) const
{
	float sum = 0.f;
	const float sq = radius * radius;
	for (CEnemyUnit* e : enemyUpdates) {
		if ((e == nullptr) || e->IsDying()) {
			continue;
		}
		CCircuitDef* cdef = e->GetCircuitDef();
		if ((cdef == nullptr) || !cdef->IsAbleToFly()) {
			continue;
		}
		if (pos.SqDistance2D(e->GetPos()) > sq) {
			continue;
		}
		sum += e->GetCost();
	}
	return sum;
}

// apex: the longest weapon range among a group's known members. The danger a
// standing group poses depends on what it can SHELL, not where it walks --
// artillery reaches ~1500 and must read dangerous from that far out.
float CEnemyManager::GetEnemyGroupRange(int idx) const
{
	if ((idx < 0) || (idx >= (int)enemyGroups.size())) {
		return 0.f;
	}
	float range = 0.f;
	for (const ICoreUnit::Id eId : enemyGroups[idx].units) {
		CEnemyUnit* enemy = GetEnemyUnit(eId);
		if (enemy == nullptr) {
			continue;
		}
		CCircuitDef* cdef = enemy->GetCircuitDef();
		if (cdef != nullptr) {
			range = std::max(range, cdef->GetMaxRange());
		}
	}
	return range;
}

void CEnemyManager::PurgeStaleGhosts(int frame, int confirmedAgeFrames, int unknownAgeFrames)
{
	for (CEnemyUnit* e : enemyUpdates) {
		if ((e == nullptr) || e->IsDying()) {
			continue;
		}
		const int seen = e->GetSeenFrame();
		if (seen < 0) {
			continue;
		}
		const int age = frame - seen;
		if (e->IsHidden()) {
			// A STATIC cannot slip into fog: hidden means we saw its tile and
			// the building was gone -- it is dead, delete now (apexearth:
			// "why not have the ghosts die immediately?"). MOBILES keep the
			// short fuse: hidden often just means it walked behind a hill,
			// and its cost is the sizing pessimism -- plus battle vision
			// flickers, and instant deletion would thrash delete/re-register.
			CCircuitDef* ecdef = e->GetCircuitDef();
			const bool isStatic = (ecdef != nullptr) && !ecdef->IsMobile();
			if (isStatic || (age > confirmedAgeFrames)) {
				DyingEnemy(e, frame);
			}
		} else if (e->NotInRadarAndLOS() && (age > unknownAgeFrames)) {
			DyingEnemy(e, frame);
		}
	}
}

void CEnemyManager::DyingEnemy(CEnemyUnit* enemy)
{
	DelEnemyCost(enemy);   // a purged ghost must stop counting
	enemyDying.insert(enemy);
	UnregisterEnemyUnit(enemy);
}

void CEnemyManager::DeleteEnemyUnit(CEnemyUnit* data)
{
	enemyUpdates[enemyIterator] = enemyUpdates.back();
	enemyUpdates.pop_back();

	delete data;
}

void CEnemyManager::ModCost(const CEnemyUnit* e, int sign, SEnemyInfo* infos,
		float& mobCost, float& mobThr)
{
	CCircuitDef* cdef = e->GetCircuitDef();
	assert(cdef != nullptr);

	const float cost = e->GetCost();
	const float threat = cdef->GetDefThreat();

	const CCircuitDef::RoleT roleSize = CCircuitDef::GetRoleNames().size();
	for (CCircuitDef::RoleT type = 0; type < roleSize; ++type) {
		if (cdef->IsEnemyRoleAny(CCircuitDef::GetMask(type))) {
			SEnemyInfo& info = infos[type];
			if (sign > 0) {
				info.cost   += cost;
				info.threat += threat;
			} else {
				info.cost   = std::max(info.cost   - cost,   0.f);
				info.threat = std::max(info.threat - threat, 0.f);
			}
		}
	}
	if (cdef->IsMobile()) {
		if (sign > 0) {
			mobThr  += threat * initThrMod.inMobile;
			mobCost += cost;
		} else {
			mobThr  = std::max(mobThr  - threat * initThrMod.inMobile, 0.f);
			mobCost = std::max(mobCost - cost, 0.f);
		}
	}
}

// staticThreat has no fresh counterpart -- a turret we saw once is still there.
void CEnemyManager::ModStatic(const CEnemyUnit* e, int sign)
{
	CCircuitDef* cdef = e->GetCircuitDef();
	assert(cdef != nullptr);
	if (cdef->IsMobile()) {
		return;
	}
	const float d = cdef->GetDefThreat() * initThrMod.inStatic;
	staticThreat = (sign > 0) ? (staticThreat + d) : std::max(staticThreat - d, 0.f);
}

void CEnemyManager::ModFresh(const CEnemyUnit* e, int sign)
{
	if (e->IsIgnore()) {
		return;
	}
	ModCost(e, sign, freshInfos.data(), freshMobileCost, freshMobileThreat);
}

// apex: BALANCED AND IDEMPOTENT. These were free-running: the ghost purge
// deletes an entry without ever refunding its cost, and re-sighting the same
// LIVE unit re-registers it (the new CEnemyUnit's knownFrame is -1), so
// EnemyEnterLOS returns !wasKnown and adds the full cost again. With the
// hidden fuse at 90s a skirmishing unit does that repeatedly and GetEnemyCost
// only ratchets up -- it comes down solely for deaths inside allied LOS or
// radar. Everything downstream reads it: ArmyTarget (and so the T2 discount),
// SiegeExpect, ThreatM, HazardAt -- all biased toward a bigger enemy the
// longer a game runs (measured ghost share 0 -> 22 -> 47 -> 60% in one game).
//
// The counted flag makes the pair exact -- what Add put in is what Del takes
// out, once -- so DyingEnemy can refund a purged ghost without the double
// subtract a second refund would cause on the real-death path.
//
// It keys off `counted` rather than IsIgnore(): a unit that became ignored
// after registration used to return early here and leak its cost.
//
// Fresh totals are NOT touched here any more. The FRESH flag is their single
// owner via ModFresh, and adding on IsFresh() double counted whenever the
// freshness pass had already set the flag before this event arrived.
void CEnemyManager::AddEnemyCost(CEnemyUnit* e)
{
	if (e->IsIgnore() || e->IsCounted()) {
		return;
	}

	ModCost(e, +1, enemyInfos.data(), enemyMobileCost, mobileThreat);
	ModStatic(e, +1);
	e->SetCounted();
}

void CEnemyManager::DelEnemyCost(CEnemyUnit* e)
{
	if (!e->IsCounted()) {
		return;
	}

	ModCost(e, -1, enemyInfos.data(), enemyMobileCost, mobileThreat);
	ModStatic(e, -1);
	if (e->IsFresh()) {
		ModFresh(e, -1);
		e->ClearFresh();
	}
	e->ClearCounted();
}

void CEnemyManager::SetFreshSeconds(float seconds)
{
	freshFrames = std::max(int(seconds * FRAMES_PER_SEC), int(FRAMES_PER_SEC));
}

void CEnemyManager::UpdateAreaUsers(CCircuitAI* ai)
{
	if (isAreaUpdated) {
		return;
	}
	isAreaUpdated = true;

	enemyAreas.clear();
	CTerrainManager* terrainMgr = ai->GetTerrainManager();
	const std::vector<SMobileType>& mobileTypes = terrainMgr->GetMobileTypes();
	for (const CEnemyManager::SEnemyGroup& group : enemyGroups) {
		const int iS = terrainMgr->GetSectorIndex(group.pos);
		for (const SMobileType& mt : mobileTypes) {
			const SArea* area = mt.sector[iS].area;
			if (area != nullptr) {
				enemyAreas.insert(area);
			}
		}
	}
}

void CEnemyManager::ReadConfig()
{
	const Json::Value& root = circuit->GetSetupManager()->GetConfig();
	const Json::Value& quotas = root["quota"];
	const Json::Value& qthrMod = quotas["thr_mod"];

	initThrMod.inMobile = qthrMod.get("mobile", 1.f).asFloat();
	initThrMod.inStatic = qthrMod.get("static", 0.f).asFloat();

	const Json::Value& aathr = quotas["aa_threat"];
	const float size0 = aathr[0].get((unsigned)0, 8.f).asFloat();
	const float size1 = aathr[1].get((unsigned)0, 24.f).asFloat();
	const float thr0 = aathr[0].get((unsigned)1, 42.f).asFloat();
	const float thr1 = aathr[1].get((unsigned)1, 420.f).asFloat();
	// NOTE: instead of map-area consider min(width, height)
	const float mapSize = (circuit->GetMap()->GetWidth() / 64) * (circuit->GetMap()->GetHeight() / 64);
	maxAAThreat = (thr1 - thr0) / (SQUARE(size1) - SQUARE(size0)) * (mapSize - SQUARE(size0)) + thr0;
}

/*
 * 2d only, ignores y component.
 * @see KAIK/AttackHandler::KMeansIteration for general reference
 */
void CEnemyManager::KMeansIteration()
{
	SGroupData& groupData = *GetNextGroupData();

	// calculate a new K. change the formula to adjust max K, needs to be 1 minimum.
	constexpr int KMEANS_BASE_MAX_K = 32;
	const auto enemySize = hostileDatas.size() + peaceDatas.size();
	int newK = std::min(KMEANS_BASE_MAX_K, 1 + (int)sqrtf(enemySize));

	// change the number of means according to newK
	assert(newK > 0/* && enemyGoups.size() > 0*/);
	// add a new means, just use one of the positions
	AIFloat3 newMeansPosition = hostileDatas.empty()
			? (peaceDatas.empty() ? enemyPos : peaceDatas.begin()->pos)
			: hostileDatas.begin()->pos;
//	newMeansPosition.y = circuit->GetMap()->GetElevationAt(newMeansPosition.x, newMeansPosition.z) + K_MEANS_ELEVATION;
	groupData1.enemyGroups.resize(newK, SEnemyGroup(newMeansPosition));

	// check all positions and assign them to means, complexity n*k for one iteration
	std::vector<int> unitsClosestMeanID(enemySize, -1);
	std::vector<int> numUnitsAssignedToMean(newK, 0);

	{
		int i = 0;
		for (const std::vector<SEnemyData>& datas : {hostileDatas, peaceDatas}) {
			for (const SEnemyData& enemy : datas) {
				float closestDistance = std::numeric_limits<float>::max();
				int closestIndex = -1;

				for (int m = 0; m < newK; m++) {
					const AIFloat3& mean = groupData1.enemyGroups[m].pos;
					float distance = enemy.pos.SqDistance2D(mean);

					if (distance < closestDistance) {
						closestDistance = distance;
						closestIndex = m;
					}
				}

				// position i is closest to the mean at closestIndex
				unitsClosestMeanID[i++] = closestIndex;
				numUnitsAssignedToMean[closestIndex]++;
			}
		}
	}

	// change the means according to which positions are assigned to them
	// use meanAverage for indexes with 0 pos'es assigned
	// make a new means list
//	std::vector<AIFloat3> newMeans(newK, ZeroVector);
	std::vector<SEnemyGroup>& newMeans = groupData1.enemyGroups;
	for (unsigned i = 0; i < newMeans.size(); i++) {
		SEnemyGroup& eg = newMeans[i];
		eg.units.clear();
		eg.units.reserve(numUnitsAssignedToMean[i]);
		eg.pos = ZeroVector;
		std::fill(eg.roleCosts.begin(), eg.roleCosts.end(), 0.f);
		eg.cost = 0.f;
		eg.influence = 0.f;
	}

	{
		int i = 0;
		for (const std::vector<SEnemyData>& datas : {hostileDatas, peaceDatas}) {
			for (const SEnemyData& enemy : datas) {
				int meanIndex = unitsClosestMeanID[i++];
				SEnemyGroup& eg = newMeans[meanIndex];

				// don't divide by 0
				float num = std::max(1, numUnitsAssignedToMean[meanIndex]);
				eg.pos += enemy.pos / num;

				if (!enemy.IsFake()) {
					eg.units.push_back(enemy.id);
				}

				if (enemy.cdef != nullptr) {
					eg.roleCosts[enemy.cdef->GetMainRole()] += enemy.cost;
					if (!enemy.cdef->IsMobile() || enemy.IsInRadarOrLOS()) {
						eg.cost += enemy.cost;
					}
					eg.influence += enemy.influence * (enemy.cdef->IsMobile() ? initThrMod.inMobile : initThrMod.inStatic);
				} else {
					eg.influence += enemy.influence;
				}
			}
		}
	}

	// do a check and see if there are any empty means and set the height
	groupData.enemyPos = ZeroVector;
	std::vector<int> indices(newK);
	for (int i = 0; i < newK; i++) {
		indices[i] = i;
		// if a newmean is unchanged, set it to the new means pos instead of (0, 0, 0)
		if (newMeans[i].pos == ZeroVector) {
			newMeans[i] = SEnemyGroup(newMeansPosition);
		} else {
			// get the proper elevation for the y-coord
//			newMeans[i].pos.y = circuit->GetMap()->GetElevationAt(newMeans[i].pos.x, newMeans[i].pos.z) + K_MEANS_ELEVATION;
		}
		groupData.enemyPos += newMeans[i].pos;
		newMeans[i].vagueMetric = (newMeans[i].influence + 1.f) / (newMeans[i].cost + DIV0_SLACK);
	}
	groupData.enemyPos /= newK;

	std::sort(indices.begin(), indices.end(), [&newMeans](int idxA, int idxB) {
		return newMeans[idxA].influence < newMeans[idxB].influence;
	});
	groupData.minThreatGroupIdx = indices.front();
	groupData.preMaxThreatGroupIdx = indices[std::max(0, newK - 2)];
	groupData.maxThreatGroupIdx = indices.back();

//	return newMeans;
}

void CEnemyManager::Prepare()
{
	groupData1.enemyGroups = groupData0.enemyGroups;
}

std::shared_ptr<IMainJob> CEnemyManager::Update()
{
	ZoneScopedN(__PRETTY_FUNCTION__);

	Prepare();

	KMeansIteration();

	return CScheduler::GameJob(&CEnemyManager::Apply, this);
}

void CEnemyManager::Apply()
{
	SwapBuffers();
	isUpdating = false;
}

void CEnemyManager::SwapBuffers()
{
	pGroupData = GetNextGroupData();
	SGroupData& groupData = *pGroupData.load();
	enemyGroups.swap(groupData1.enemyGroups);  // groupData0.enemyGroups.swap(groupData1.enemyGroups);
	enemyPos = groupData.enemyPos;
	minThreatGroupIdx = groupData.minThreatGroupIdx;
	preMaxThreatGroupIdx = groupData.preMaxThreatGroupIdx;
	maxThreatGroupIdx = groupData.maxThreatGroupIdx;
}

} // namespace circuit
