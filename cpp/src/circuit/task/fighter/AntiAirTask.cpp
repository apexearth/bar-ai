/*
 * AntiAirTask.cpp
 *
 *  Created on: Jan 6, 2016
 *      Author: rlcevg
 */

#include <algorithm>
#include "task/fighter/AntiAirTask.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/action/FightAction.h"
#include "unit/action/MoveAction.h"
#include "unit/enemy/EnemyManager.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "AISCommands.h"

// Fighters were sent the moment they rolled off the pad, so a squad of one flew
// at an enemy flight of four or five. apexearth: "we just go in with one. We
// should be saving up an equal or greater number of fighters as the enemy has
// and then attacking."
//
// Held at home until the squad's own cost matches this share of the enemy's
// known air, then released. Below the floor there is nothing worth massing
// against and the squad flies as before, so early interception is unaffected.
// GetEnemyCost(AIR) is every enemy air unit ever registered, across every enemy
// player, dead ones included -- not the flight in front of us. One squad's metal
// never reaches parity with it, so at 1.0 the hold never released.
#define AA_MASS_RATIO   0.25f
#define AA_MASS_FLOOR   400.f   // metal of enemy air below which we do not wait
// Enemy air this close to the ground we defend is not a flight to be out-massed,
// it is a raid in progress. The hold above is measured against the enemy's TOTAL
// air cost, which a single heavy gunship exceeds on its own, so without this the
// squad waits for a parity it cannot reach while the raider shoots the line.
#define AA_RAID_RADIUS  2600.f


namespace circuit {

using namespace springai;
using namespace terrain;

CAntiAirTask::CAntiAirTask(ITaskModule* mgr, float powerMod)
		: ISquadTask(mgr, FightType::AA, powerMod)
{
	CCircuitAI* circuit = manager->GetCircuit();
	float x = rand() % circuit->GetTerrainManager()->GetTerrainWidth();
	float z = rand() % circuit->GetTerrainManager()->GetTerrainHeight();
	position = AIFloat3(x, circuit->GetMap()->GetElevationAt(x, z), z);
}

CAntiAirTask::~CAntiAirTask()
{
}

bool CAntiAirTask::CanAssignTo(CCircuitUnit* unit) const
{
	if (!unit->GetCircuitDef()->IsRoleAA()) {
		return false;
	}
	// apex: was `unit->GetCircuitDef() != leader->GetCircuitDef()`, i.e. only the
	// identical unit type could join. Use the same speed-compatibility rule
	// CAttackTask applies to ground instead, so mixed AA/fighter types can mass.
	float speedLeader = leader->GetCircuitDef()->GetSpeed();
	float speedUnit = unit->GetCircuitDef()->GetSpeed();
	if (speedLeader > speedUnit) {
		std::swap(speedLeader, speedUnit);
	}
	if (speedLeader * 1.5f < speedUnit) {
		return false;
	}
	const int frame = manager->GetCircuit()->GetLastFrame();
	// apex: was SQUARE(1000.f). Aircraft cover that in seconds, so newly built
	// bombers were always out of range and formed solo tasks instead.
	if (leader->GetPos(frame).SqDistance2D(unit->GetPos(frame)) > SQUARE(4000.f)) {
		return false;
	}
	return true;
}

void CAntiAirTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);

	int squareSize = manager->GetCircuit()->GetPathfinder()->GetSquareSize();
	CCircuitDef* cdef = unit->GetCircuitDef();
	ITravelAction* travelAction;
	if (cdef->IsAttrSiege() && (manager->GetCircuit()->GetTunable("apex_siege_fight", 1.f) > 0.f)) {
		travelAction = new CFightAction(unit, squareSize);
	} else {
		travelAction = new CMoveAction(unit, squareSize);
	}
	unit->PushTravelAct(travelAction);
	travelAction->StateWait();
	unit->SetAllowedToJump(cdef->IsAbleToJump() && cdef->IsAttrJump());
}

void CAntiAirTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	if (leader == nullptr) {
		manager->AbortTask(this);
	}
}

void CAntiAirTask::Start(CCircuitUnit* unit)
{
	if ((State::REGROUP == state) || (State::ENGAGE == state)) {
		return;
	}
	if (!pPath->posPath.empty()) {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetPath(pPath, lowestSpeed);
		}
	}
}

void CAntiAirTask::Update()
{
	++updCount;

	/*
	 * Check safety
	 */
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();

	if (State::DISENGAGE == state) {
		if (updCount % 32 == 1) {
			const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
			if (position.SqDistance2D(leader->GetPos(frame)) < SQUARE(maxDist)) {
				state = State::ROAM;
			} else {
				if (IsQueryReady(leader)) {
					FallbackDisengage();
				}
				return;
			}
		} else {
			return;
		}
	}

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if (task != nullptr) {
		task->Merge(this);
		units.clear();
		manager->AbortTask(this);
		return;
	}

	/*
	 * Regroup if required
	 */
	bool wasRegroup = (State::REGROUP == state);
	bool mustRegroup = IsMustRegroup();
	if (State::REGROUP == state) {
		if (mustRegroup) {
			CCircuitAI* circuit = manager->GetCircuit();
			int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
			for (CCircuitUnit* unit : units) {
				if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
					unit->GetTravelAct()->StateWait();
				}
				TRY_UNIT(circuit, unit,
					unit->CmdFightTo(groupPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame);
				)
			}
		}
		return;
	}

	bool isExecute = (updCount % 4 == 2);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame);
		}
		if (!isExecute) {
			if (wasRegroup && !pPath->posPath.empty()) {
				ActivePath();
			}
			return;
		}
	}

	/*
	 * Update target
	 */
	FindTarget();

	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if (GetTarget() != nullptr) {
		const float sqRange = SQUARE(lowestRange);
		if (position.SqDistance2D(startPos) < sqRange) {
			state = State::ENGAGE;
			Attack(frame);
			return;
		}
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (GetTarget() == nullptr) {
		FallbackSafePos();
		return;
	}

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, position, pathfinder->GetSquareSize(), GetHitTest());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CAntiAirTask::OnUnitIdle(CCircuitUnit* unit)
{
	ISquadTask::OnUnitIdle(unit);
	if ((leader == nullptr) || (State::DISENGAGE == state)) {
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const float maxDist = std::max<float>(lowestRange, circuit->GetPathfinder()->GetSquareSize());
	// See CAttackTask::OnUnitIdle: a standoff move completes while the target is
	// still alive, so idle no longer implies "arrived and found nothing".
	if ((GetTarget() == nullptr)
		&& (position.SqDistance2D(leader->GetPos(circuit->GetLastFrame())) < SQUARE(maxDist)))
	{
		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		position = RoamPos(leader);
	}

	if (units.find(unit) != units.end()) {
		Start(unit);  // NOTE: Not sure if it has effect
	}
}

void CAntiAirTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	ISquadTask::OnUnitDamaged(unit, attacker);

	if ((leader == nullptr) || (State::DISENGAGE == state) ||
		((attacker != nullptr) && (attacker->GetCircuitDef() != nullptr) && attacker->GetCircuitDef()->IsAbleToFly()))
	{
		return;
	}

//	if (!IsQueryReady(unit)) {
//		return;
//	}

	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	circuit->GetMilitaryManager()->FillSafePos(leader, urgentPositions);
	const float pathRange = DEFAULT_SLACK * 4;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, circuit->GetThreatMap(),
			startPos, pathRange, urgentPositions);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyDamagedPath(static_cast<const CQueryPathMulti*>(query));
	});
}

NSMicroPather::HitFunc CAntiAirTask::GetHitTest() const
{
	CCircuitDef* cdef = leader->GetCircuitDef();
	if (cdef->IsAbleToFly() || cdef->IsSurfer()) {
		return nullptr;
	}
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const std::vector<SSector>& sectors = terrainMgr->GetAreaData()->sector;
	const int sectorXSize = terrainMgr->GetSectorXSize();
	const AIFloat3& ePos = GetTarget()->GetPos();
	if (GetTarget()->GetCircuitDef()->IsInWater(circuit->GetMap()->GetElevationAt(ePos.x, ePos.z), ePos.y)) {
		return [&sectors, sectorXSize, cdef](int2 start, int2 end) {  // cdef->IsAmphibious()
			const float elevation = sectors[start.y * sectorXSize + start.x].minElevation;
			return cdef->IsPredictInWater(elevation) ? cdef->HasSubToWater() : cdef->HasSurfToWater();
		};
	}
	return [&sectors, sectorXSize, cdef](int2 start, int2 end) {  // cdef->IsAmphibious()
		const float elevation = sectors[start.y * sectorXSize + start.x].minElevation;
		return cdef->IsPredictInWater(elevation) ? cdef->HasSubToAir() : cdef->HasSurfToAir();
	};
}

void CAntiAirTask::FindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();
	const float maxPower = attackPower * powerMod * GetHealthScale();
//	const CCircuitDef::RoleT role = cdef->GetMainRole();

	// Do not go hunting one at a time. Our own cost, not attackPower, because
	// attackPower is a sum of per-type constants and the comparison is against
	// an enemy COST from the enemy manager.
	// The ground we are defending: the held line if we have one, else the base.
	AIFloat3 homeRef = circuit->GetMilitaryManager()->GetDefenceStand();
	if (!utils::is_valid(homeRef)) {
		homeRef = circuit->GetSetupManager()->GetBasePos();
	}
	bool isRaid = false;
	for (auto& kv : circuit->GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		if (e->IsHidden()) {
			continue;
		}
		CCircuitDef* ed = e->GetCircuitDef();
		if ((ed != nullptr) && ed->IsAbleToFly()
			&& (homeRef.SqDistance2D(e->GetPos()) < SQUARE(AA_RAID_RADIUS)))
		{
			isRaid = true;
			break;
		}
	}

	const float enemyAir = circuit->GetEnemyManager()->GetEnemyCost(ROLE_TYPE(AIR));
	if (!isRaid && (enemyAir > AA_MASS_FLOOR)) {
		float ourAir = .0f;
		for (CCircuitUnit* u : units) {
			ourAir += u->GetCircuitDef()->GetCostM();
		}
		if (ourAir < enemyAir * AA_MASS_RATIO) {
			SetTarget(nullptr);
			return;   // keep gathering; ISquadTask merging runs while we hold
		}
	}

	CEnemyInfo* bestTarget = nullptr;
	float minSqDist = std::numeric_limits<float>::max();
	CEnemyInfo* bestRaid = nullptr;
	float minSqRaid = std::numeric_limits<float>::max();

	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden()) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		const bool isHomeTgt = (homeRef.SqDistance2D(ePos) < SQUARE(AA_RAID_RADIUS));
		if ((!isHomeTgt && (maxPower <= threatMap->GetThreatAt(ePos)/* - enemy->GetThreat(role)*/))
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		CCircuitDef* edef = enemy->GetCircuitDef();
		if ((edef == nullptr)  // TODO: for edef == nullptr check elevation and speed
			|| ((edef->GetCategory() & canTargetCat) == 0)
			|| ((edef->GetCategory() & noChaseCat) != 0)
			|| circuit->GetCircuitDef(edef->GetId())->IsIgnore())
		{
			continue;
		}
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool IsInWater = cdef->IsPredictInWater(elevation);
		if (edef->IsInWater(elevation, ePos.y)) {
			if (!(IsInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater())) {  // notAW
				continue;
			}
		} else if (edef->IsAbleToFly()) {
			if (!(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir())) {  // notAA
				continue;
			}
		} else {
			if (!(IsInWater ? cdef->HasSubToLand() : cdef->HasSurfToLand())) {  // notAL
				continue;
			}
		}

		const float sqDist = pos.SqDistance2D(ePos);
		if (isHomeTgt) {
			if (minSqRaid > sqDist) {
				minSqRaid = sqDist;
				bestRaid = enemy;
			}
		} else if (minSqDist > sqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
	}

	// Whatever is over our own ground outranks whatever is merely closest.
	SetTarget((bestRaid != nullptr) ? bestRaid : bestTarget);
	if (GetTarget() != nullptr) {
		position = GetTarget()->GetPos();
	}
	// Return: target, startPos=leader->pos, endPos=position
}

void CAntiAirTask::FallbackDisengage()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, circuit->GetThreatMap(),
			startPos, position, pathfinder->GetSquareSize());
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyDisengagePath(static_cast<const CQueryPathSingle*>(query));
	});
}

void CAntiAirTask::ApplyDisengagePath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->path.empty()) {
		if (pPath->path.size() > 2) {
			ActivePath();
		}
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdMoveTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		)
	}
	state = State::ROAM;
}

void CAntiAirTask::ApplyTargetPath(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath();
	} else {
		Fallback();
	}
}

void CAntiAirTask::FallbackSafePos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->GetMilitaryManager()->FillSafePos(leader, urgentPositions);
	if (urgentPositions.empty()) {
		FallbackCommPos();
		return;
	}

	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	const float pathRange = DEFAULT_SLACK * 4;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, circuit->GetThreatMap(),
			startPos, pathRange, urgentPositions);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplySafePos(static_cast<const CQueryPathMulti*>(query));
	});
}

void CAntiAirTask::ApplySafePos(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		position = pPath->posPath.back();
		ActivePath();
	} else {
		FallbackCommPos();
	}
}

void CAntiAirTask::FallbackCommPos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CCircuitUnit* commander = circuit->GetSetupManager()->GetCommander();
	if ((commander != nullptr) &&
		circuit->GetTerrainManager()->CanMoveToPos(leader->GetArea(), commander->GetPos(frame)))
	{
		// ApplyCommPos
		for (CCircuitUnit* unit : units) {
			if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
				unit->GetTravelAct()->StateWait();
			}
			unit->Guard(commander, frame + FRAMES_PER_SEC * 60);
		}
		return;
	}

	Fallback();
}

void CAntiAirTask::Fallback()
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateWait();
		}
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
		)
	}
}

void CAntiAirTask::ApplyDamagedPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		position = pPath->posPath.back();
		ActivePath();
		state = State::DISENGAGE;
	} else {
		position = manager->GetCircuit()->GetSetupManager()->GetBasePos();
		Fallback();
	}
}

} // namespace circuit
