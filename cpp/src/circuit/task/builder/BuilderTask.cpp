/*
 * BuilderTask.cpp
 *
 *  Created on: Sep 11, 2014
 *      Author: rlcevg
 */

#include "task/builder/BuilderTask.h"
#include "task/builder/BuildChain.h"
#include "task/builder/DefenceTask.h"  // Only for static_cast<CBDefenceTask*>
#include "task/RetreatTask.h"
#include "map/ThreatMap.h"
#include "map/InfluenceMap.h"
#include "module/EconomyManager.h"
#include "module/BuilderManager.h"
#include "module/FactoryManager.h"
#include "module/MilitaryManager.h"
#include "resource/MetalManager.h"
#include "resource/EnergyGrid.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "unit/action/DGunAction.h"
#include "unit/action/CaptureAction.h"
#include "unit/action/FightAction.h"
#include "unit/action/MoveAction.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"
#include "Log.h"
#include <cstdlib>

namespace circuit {

// Lattice rings walked before a taken slot falls to the wide site search.
static constexpr int LATTICE_RINGS = 6;


using namespace springai;

// A site the script chose and the lattice must not move: an extractor sits on
// its spot or not at all, and a turret, a factory or a pylon was placed for
// where it is. Everything else is farm and belongs on the grid.
static inline bool IsFixedSite(IBuilderTask::BuildType buildType)
{
	return (buildType == IBuilderTask::BuildType::MEX)
		|| (buildType == IBuilderTask::BuildType::MEXUP)
		|| (buildType == IBuilderTask::BuildType::GEO)
		|| (buildType == IBuilderTask::BuildType::GEOUP)
		|| (buildType == IBuilderTask::BuildType::DEFENCE)
		|| (buildType == IBuilderTask::BuildType::BUNKER)
		|| (buildType == IBuilderTask::BuildType::BIG_GUN)
		|| (buildType == IBuilderTask::BuildType::PYLON)
		|| (buildType == IBuilderTask::BuildType::FACTORY)
		|| (buildType == IBuilderTask::BuildType::TERRAFORM);
}

// A spot names its own ground: an extractor or a geo plant is built on the
// vent or not at all, so it is never moved off it to keep a builder standing.
static inline bool IsSpotSite(IBuilderTask::BuildType buildType)
{
	return (buildType == IBuilderTask::BuildType::MEX)
		|| (buildType == IBuilderTask::BuildType::MEXUP)
		|| (buildType == IBuilderTask::BuildType::GEO)
		|| (buildType == IBuilderTask::BuildType::GEOUP);
}

// A BUILDING IS NOT SITED ON THE SQUARE ITS OWN BUILDER IS STANDING ON. The
// site search reads a mobile unit as empty ground, so the nearest legal square
// to a constructor inside its own base is the one under its feet, and the order
// cannot start until the builder has been shoved off the footprint it just
// claimed (apexearth, on the commander: "it is inefficient to have to step out
// of the way for every building that you want to make"). A static builder is
// already in the blocker map, so only mobile ones are asked.
// The bar is the two half-footprints summed -- a def of N cells reaches
// N * SQUARE_SIZE from its centre -- and 0 means "keep no clearance".
float SelfClearance(CCircuitUnit* builder, CCircuitDef* buildDef)
{
	if ((builder == nullptr) || (buildDef == nullptr)
		|| !builder->GetCircuitDef()->IsMobile())
	{
		return 0.f;
	}
	CCircuitDef* bdef = builder->GetCircuitDef();
	return float(std::max(buildDef->GetFootX(), buildDef->GetFootZ())
			+ std::max(bdef->GetFootX(), bdef->GetFootZ())) * SQUARE_SIZE;
}

// DOES THE BUILDER KEEP A WAY OUT if this cell is built? A mobile builder
// standing inside the lattice it fills can wall itself in: its build range
// covers the cells around it, so it never has to move, and the last free cell
// beside it is a legal site (the commander he watched sat inside its own
// wind cluster for 37 minutes). Flood the free cells of the def's lattice
// out from the builder's cell with the candidate counted as taken; an exit
// is any cell four rings out or off the grid. Only asked when the candidate
// lands within two cells of the builder -- further away it closes nothing.
static bool KeepsExit(CCircuitAI* circuit, CTerrainManager* terrainMgr, CCircuitUnit* builder,
		CCircuitDef* buildDef, int facing, float slot, const AIFloat3& cand)
{
	if ((builder == nullptr) || !builder->GetCircuitDef()->IsMobile()) {
		return true;
	}
	constexpr int R = 4;
	const AIFloat3 self = builder->GetPos(circuit->GetLastFrame());
	int bi = 0, bj = 0;
	float bestSq = -1.f;
	for (int j = -2; j <= 2; ++j) {
		for (int i = -2; i <= 2; ++i) {
			AIFloat3 c;
			if (!circuit->LatticeNeighbour(cand, buildDef, facing, i, j, c)) {
				continue;
			}
			const float sq = c.SqDistance2D(self);
			if ((bestSq < .0f) || (sq < bestSq)) {
				bestSq = sq;
				bi = i;
				bj = j;
			}
		}
	}
	if ((bestSq < .0f) || (bestSq > SQUARE(2.f * slot))) {
		return true;   // the builder is not standing in this lattice's rings
	}
	const int W = 2 * R + 1;
	std::vector<char> state(W * W, 0);   // 0 unknown, 1 free/visited, 2 taken
	auto idx = [&](int i, int j) { return (j + R) * W + (i + R); };
	std::vector<std::pair<int, int>> queue;
	queue.emplace_back(bi, bj);
	state[idx(bi, bj)] = 1;
	state[idx(0, 0)] = 2;
	while (!queue.empty()) {
		const auto [ci, cj] = queue.back();
		queue.pop_back();
		if ((std::abs(ci) >= R) || (std::abs(cj) >= R)) {
			return true;
		}
		for (int dj = -1; dj <= 1; ++dj) {
			for (int di = -1; di <= 1; ++di) {
				const int ni = ci + di, nj = cj + dj;
				if (((di == 0) && (dj == 0)) || (std::abs(ni) > R) || (std::abs(nj) > R)
					|| (state[idx(ni, nj)] != 0))
				{
					continue;
				}
				AIFloat3 c;
				if (!circuit->LatticeNeighbour(cand, buildDef, facing, ni, nj, c)) {
					return true;   // off the grid: open ground
				}
				const AIFloat3 probe = terrainMgr->FindBuildSite(buildDef, c, slot, facing);
				const bool freeCell = utils::is_valid(probe)
						&& (probe.SqDistance2D(c) <= SQUARE(SQUARE_SIZE));
				state[idx(ni, nj)] = freeCell ? 1 : 2;
				if (freeCell) {
					queue.emplace_back(ni, nj);
				}
			}
		}
	}
	return false;
}

IBuilderTask::BuildName IBuilderTask::buildNames = {
	{"factory", IBuilderTask::BuildType::FACTORY},
	{"nano",    IBuilderTask::BuildType::NANO},
	{"store",   IBuilderTask::BuildType::STORE},
	{"pylon",   IBuilderTask::BuildType::PYLON},
	{"energy",  IBuilderTask::BuildType::ENERGY},
	{"geo",     IBuilderTask::BuildType::GEO},
	{"defence", IBuilderTask::BuildType::DEFENCE},
	{"bunker",  IBuilderTask::BuildType::BUNKER},
	{"big_gun", IBuilderTask::BuildType::BIG_GUN},
	{"radar",   IBuilderTask::BuildType::RADAR},
	{"sonar",   IBuilderTask::BuildType::SONAR},
	{"convert", IBuilderTask::BuildType::CONVERT},
	{"mex",     IBuilderTask::BuildType::MEX},
	{"mexup",   IBuilderTask::BuildType::MEXUP},
};

IBuilderTask::IBuilderTask(ITaskModule* mgr, Priority priority,
						   CCircuitDef* buildDef, const AIFloat3& position,
						   Type type, BuildType buildType, SResource cost, float shake, int timeout)
		: IUnitTask(mgr, priority, type, timeout)
		, buildType(buildType)
		, position(position)
		, shake(shake)
		, buildDef(buildDef)
		, buildPower({0.f, 0.f})
		, cost(cost)
		, target(nullptr)
		, buildPos(-RgtVector)
		, facing(UNIT_NO_FACING)
		, nextTask(nullptr)
		, initiator(nullptr)
		, buildFails(0)
		, nextCursor(nullptr)
{
	CEconomyManager* economyMgr = manager->GetCircuit()->GetEconomyManager();
	savedIncome.metal = economyMgr->GetAvgMetalIncome();
	savedIncome.energy = economyMgr->GetAvgEnergyIncome();
}

IBuilderTask::IBuilderTask(ITaskModule* mgr, Type type, BuildType buildType)
		: IUnitTask(mgr, type)
		, buildType(buildType)
		, position(-RgtVector)
		, shake(0.f)
		, buildDef(nullptr)
		, buildPower({0.f, 0.f})
		, cost({0.f, 0.f})
		, target(nullptr)
		, buildPos(-RgtVector)
		, facing(UNIT_NO_FACING)
		, nextTask(nullptr)
		, initiator(nullptr)
		, savedIncome({0.f, 0.f})
		, buildFails(0)
		, nextCursor(nullptr)
{
}

IBuilderTask::~IBuilderTask()
{
	// nextTask came from CBuilderManager::Enqueue, which fires TaskAdded, so a
	// script may hold a refcounted handle to it. Release rather than delete: the
	// object then outlives this one until the last handle goes.
	if (nextTask != nullptr) {
		nextTask->ClearRelease();
		nextTask = nullptr;
	}
}

bool IBuilderTask::CanAssignTo(CCircuitUnit* unit) const
{
	// can unit build at all
	const CCircuitDef* cdef = unit->GetCircuitDef();
	if (((target == nullptr) || !cdef->IsAbleToAssist() || unit->IsAttrSolo()) && !cdef->CanBuild(buildDef)) {
		return false;
	}
	// is extra buildpower required?
	CEconomyManager* economyMgr = manager->GetCircuit()->GetEconomyManager();
	if (cost.metal < buildPower.metal * buildDef->GetGoalBuildTime(economyMgr->GetAvgMetalIncome())) {  // upper metal bound
		return false;
	}
	// energy income check
	if ((target == nullptr) && !economyMgr->IsEnergyFull() && !economyMgr->IsEnoughEnergy(this, cdef, 0.8f)) {  // lower energy bound
		return false;
	}
	// solo/initiator check
	return !unit->IsAttrSolo() || (initiator == unit) || ((initiator == nullptr) && (target == nullptr));
}

void IBuilderTask::AssignTo(CCircuitUnit* unit)
{
	IUnitTask::AssignTo(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	ShowAssignee(unit);
	if (!utils::is_valid(position)) {
		position = unit->GetPos(circuit->GetLastFrame());
	}
	if (initiator == nullptr) {  // unit->IsAttrSolo()
		initiator = unit;
	}

	if (unit->HasDGun()) {
		// apex: dgun range only, not LOS. At LOS radius the DGun order (queue-
		// replacing, no SHIFT) walks a working commander after anything he can
		// see -- the chase-and-forget apexearth watched. Close threats his
		// regular gun already answers; the D-gun stays point-blank -- EXCEPT
		// for a target worth more than the owner itself (mayClose): a Titan
		// at laser range one-shots for the price of a short walk, and trading
		// lasers with it instead is how a commander dies with the dgun ready.
		unit->PushDGunAct(new CDGunAction(unit, unit->GetDGunRange(), true));
	}
	if (unit->GetCircuitDef()->IsAbleToCapture()) {
		unit->PushBack(new CCaptureAction(unit, 500.f));
	}

	// NOTE: only for unit->GetCircuitDef()->IsMobile()
	int squareSize = circuit->GetPathfinder()->GetSquareSize();
	CCircuitDef* cdef = unit->GetCircuitDef();
	ITravelAction* travelAction;
	if (cdef->IsAttrSiege()) {
		travelAction = new CFightAction(unit, squareSize);
	} else {
		travelAction = new CMoveAction(unit, squareSize);
	}
	unit->PushTravelAct(travelAction);
	travelAction->StateWait();
	unit->SetAllowedToJump(cdef->IsAbleToJump() && cdef->IsAttrJump());
}

bool IBuilderTask::sInReelect = false;

void IBuilderTask::RemoveAssignee(CCircuitUnit* unit)
{
	if (initiator == unit) {
		initiator = nullptr;
	}
	// apex: who strands a fresh frame -- the engine kills a nanoframe at
	// zero progress the moment no one lathes it.
	if ((target != nullptr) && (units.size() == 1) && (units.count(unit) > 0)
		&& (buildDef != nullptr) && (target->GetUnit()->GetHealth() < target->GetUnit()->GetMaxHealth() * 0.02f))
	{
		manager->GetCircuit()->LOG("apex: strand %s at=%.0f,%.0f reelect=%d dead=%d", buildDef->GetDef()->GetName(),
				buildPos.x, buildPos.z, sInReelect ? 1 : 0, IsDead() ? 1 : 0);
	}

	IUnitTask::RemoveAssignee(unit);
	traveled.erase(unit);
	executors.erase(unit);

	HideAssignee(unit);
}

// apex: where a task's first order goes missing (apex_task_trace=1). A unit
// held a build task 12 s with an empty command queue and no order sent.
static bool TaskTraceOn(CCircuitAI* circuit)
{
	static int at = -1000;
	static bool on = false;
	const int frame = circuit->GetLastFrame();
	if (frame - at >= 150) {
		at = frame;
		on = circuit->GetTunable("apex_task_trace", 0.f) > 0.f;
	}
	return on;
}

void IBuilderTask::Start(CCircuitUnit* unit)
{
	if (TaskTraceOn(manager->GetCircuit())) {
		ITravelAction* tr = unit->GetTravelAct();
		manager->GetCircuit()->LOG("apex: ttrace start #%d %s task=%p travel=%s", unit->GetId(),
				(buildDef != nullptr) ? buildDef->GetDef()->GetName() : "-", static_cast<void*>(this),
				(tr == nullptr) ? "null" : (tr->IsFinished() ? "fin" : (tr->IsWait() ? "wait" : "act")));
	}
	Update(unit);
}

void IBuilderTask::Update()
{
	decltype(traveled) tmpTraveled = traveled;
	for (CCircuitUnit* unit : tmpTraveled) {
		if (!Execute(unit)) {
			return;
		}
	}
	traveled.clear();

	CCircuitUnit* unit = GetNextAssignee();
	if (unit == nullptr) {
		return;
	}

	Update(unit);
}

void IBuilderTask::Stop(bool done)
{
	IUnitTask::Stop(done);
	traveled.clear();
	executors.clear();

	CEconomyManager* economyMgr = manager->GetCircuit()->GetEconomyManager();
	if ((buildDef != nullptr) && !economyMgr->IsIgnorePull(this)) {
		manager->DelMetalPull(buildPower.metal);
	}
	economyMgr->CorrectResourcePull(buildPower.metal, buildPower.energy);
}

void IBuilderTask::Finish()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CBuilderManager* builderMgr = circuit->GetBuilderManager();
	if (buildDef != nullptr) {
		SBuildChain* chain = builderMgr->GetBuildChain(buildType, buildDef);
		if (chain != nullptr) {
			ExecuteChain(chain);
		}

		const int buildDelay = circuit->GetEconomyManager()->GetBuildDelay();
		if (buildDelay > 0) {
			IUnitTask* task = builderMgr->Enqueue(TaskB::Wait(buildDelay));
			decltype(units) tmpUnits = units;
			for (CCircuitUnit* unit : tmpUnits) {
				manager->AssignTask(unit, task);
			}
		}
	}

	// Advance queue
	if (nextTask != nullptr) {
		builderMgr->ActivateTask(nextTask);
		nextTask = nullptr;
	}
}

void IBuilderTask::Cancel()
{
	if ((target == nullptr) && utils::is_valid(buildPos)) {
		SetBuildPos(-RgtVector);
	}

	// Destructor will take care of the nextTask queue
}

bool IBuilderTask::Execute(CCircuitUnit* unit)
{
	executors.insert(unit);
	if (TaskTraceOn(manager->GetCircuit())) {
		manager->GetCircuit()->LOG("apex: ttrace execute #%d task=%p target=%d possible=%d", unit->GetId(), static_cast<void*>(this),
				(target != nullptr) ? 1 : 0,
				(utils::is_valid(buildPos) && (buildDef != nullptr) && manager->GetCircuit()->GetMap()->IsPossibleToBuildAt(buildDef->GetDef(), buildPos, facing)) ? 1 : 0);
	}

	CCircuitAI* circuit = manager->GetCircuit();
	TRY_UNIT(circuit, unit,
		unit->CmdPriority(ClampPriority());
	)

	const int frame = circuit->GetLastFrame();
	if (target != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->CmdRepair(target, UNIT_CMD_OPTION, frame + FRAMES_PER_SEC * 60);
		)
		return true;
	}
	if (utils::is_valid(buildPos)
		&& circuit->GetMap()->IsPossibleToBuildAt(buildDef->GetDef(), buildPos, facing))
	{
		TRY_UNIT(circuit, unit,
			unit->CmdBuild(buildDef, buildPos, facing, 0, frame + FRAMES_PER_SEC * 60);
		)
		return true;
	}

	// FIXME: Move to Reevaluate
	circuit->GetThreatMap()->SetThreatType(unit);
	// FIXME: Replace const 1000.f with build time?
	if (circuit->IsAllyAware() && (cost.metal > 1000.f)) {
		circuit->UpdateFriendlyUnits();
		const float dist = std::min(cost.metal, 1000.f);
		auto& friendlies = circuit->GetCallback()->GetFriendlyUnitsIn(position, dist);
		CAllyUnit* alu = FindSameAlly(unit, friendlies);
		utils::free(friendlies);
		if (alu != nullptr) {
			TRY_UNIT(circuit, unit,
				unit->CmdRepair(alu, UNIT_CMD_OPTION, frame + FRAMES_PER_SEC * 60);
			)
			return true;
		}
	}

	// Onto the base grid where there is one, otherwise the old jitter.
	//
	// Excluded types have to stand on a particular piece of ground and would be
	// ruined by being moved: MEX/MEXUP on the metal spot, GEO/GEOUP on the vent,
	// DEFENCE/BUNKER/BIG_GUN on the line they were sited to cover, PYLON on the
	// grid link it was placed to make. FACTORY is excluded too, but for the
	// opposite reason -- packing labs into the lattice is what leaves no room to
	// tech up, and the point of the lattice is to keep that room free for them.
	AIFloat3 pos;
	const bool isFixed = IsFixedSite(buildType);
	// Facing first (FindBuildSite recomputes it identically): the parity snap
	// needs it because the engine swaps xsize/zsize for east/west.
	FindFacing(position);
	// A RETRY MUST PICK A NEW SPOT.
	//
	// FindBuildSite is deterministic from `position`, so a site the builder
	// cannot actually reach was handed back identically on every retry: the con
	// took the order, never moved, went idle, and did it again until the task
	// aborted -- measured with the builder parked at the SAME distance across
	// consecutive aborts (685, 685, 685) while its site stayed put (659 from
	// home), 362 aborted advanced labs and none built. Walk the search origin
	// out on each failure so a later attempt looks at different ground.
	//
	// RANDOM, not a fixed walk. The same task is handed back to the same
	// constructor after each failure (OnUnitIdle re-Executes, then the orphan
	// is re-adopted by whoever asks -- usually the same con, since it is the
	// one electing), so a deterministic offset means every retry repeats the
	// previous attempt's behaviour. apexearth: "we keep retrying with the same
	// cons that fail... add more variation". A random bearing at a radius that
	// widens with each failure explores instead of repeating, and two cons
	// failing the same task diverge instead of colliding.
	AIFloat3 origin = position;
	if (buildFails > 0) {
		const float foot = std::max(buildDef->GetFootX(), buildDef->GetFootZ())
				* SQUARE_SIZE * 2;
		origin = utils::get_radial_pos(position, foot * float(buildFails));
		CTerrainManager::CorrectPosition(origin);
	}
	const bool onGrid = !isFixed && circuit->SnapToBaseGrid(origin, pos, buildDef, facing);
	if (!onGrid) {
		pos = (shake > .0f) ? utils::get_near_pos(origin, shake) : origin;
	}
	CTerrainManager::CorrectPosition(pos);

	// A LATTICE SLOT IS A DECISION, NOT A HINT.
	//
	// The search below reaches 1600 elmos, so a slot blocked by one building
	// becomes a building up to 1600 elmos away. That is the sprawl, and it is
	// also why rows never tiled: the spiral steps by ONE build square, so a
	// nudged placement leaves the lattice phase, overlaps the neighbouring slot,
	// and the neighbour is nudged in turn. On the grid, try the slot alone first
	// and take the wide search only when the slot genuinely cannot be had --
	// recording it, so script can decide whether to reclaim what stands there.
	// Never worse than the wide search; exact whenever the slot is free.
	// The slot is PROBED read-only first. FindBuildSite commits through
	// SetBuildPos, which registers a blocker at whatever it settles on, so
	// calling it twice makes the second search step around the first call's own
	// reservation.
	float searchRadius = 200 * SQUARE_SIZE;
	if (onGrid) {
		const float slot = std::max(buildDef->GetFootX(), buildDef->GetFootZ())
				* SQUARE_SIZE * 2;
		CTerrainManager* terrainMgr = manager->GetCircuit()->GetTerrainManager();
		const AIFloat3 probe = terrainMgr->FindBuildSite(buildDef, pos, slot, facing);
		const bool free = utils::is_valid(probe)
				&& (probe.SqDistance2D(pos) <= SQUARE(SQUARE_SIZE));
		// A slot the builder is itself standing in is not a slot that is taken:
		// widening lets the search step to the neighbouring one instead of the
		// builder stepping aside, and the ground is NOT reported blocked --
		// script would then avoid it for as long as the mark lives.
		const float clear = SelfClearance(unit, buildDef);
		const bool keepsExit = !free
				|| KeepsExit(circuit, terrainMgr, unit, buildDef, facing, slot, probe);
		if (!keepsExit) {
			circuit->LOG("apex: exit-kept %s by %s at=%.0f,%.0f", buildDef->GetDef()->GetName(),
					unit->GetCircuitDef()->GetDef()->GetName(), probe.x, probe.z);
		}
		if (free && keepsExit && (probe.SqDistance2D(unit->GetPos(frame)) >= SQUARE(clear))) {
			searchRadius = slot;   // the slot is free: hold the task to it
		} else {
			// THE NEXT SLOT, NOT THE NEXT SQUARE. A taken slot fell straight
			// to the wide search, which steps by one build square and lands
			// the building a few squares off the row (apexearth: "a converter
			// only builds up, left, down, or right. not up and slightly to the
			// side. snap to a grid of the building's own size"). Rings of the
			// def's own lattice, nearest first; the wide search only when no
			// ring within reach has a free slot.
			const AIFloat3 self = unit->GetPos(frame);
			const AIFloat3 snapped = pos;
			bool found = false;
			for (int ring = 1; (ring <= LATTICE_RINGS) && !found; ++ring) {
				float bestSq = -1.f;
				AIFloat3 best;
				for (int j = -ring; j <= ring; ++j) {
					for (int i = -ring; i <= ring; ++i) {
						if ((std::abs(i) != ring) && (std::abs(j) != ring)) {
							continue;
						}
						AIFloat3 cell;
						if (!circuit->LatticeNeighbour(snapped, buildDef, facing, i, j, cell)) {
							continue;
						}
						const float sq = cell.SqDistance2D(snapped);
						if ((bestSq >= .0f) && (sq >= bestSq)) {
							continue;
						}
						const AIFloat3 p2 = terrainMgr->FindBuildSite(buildDef, cell, slot, facing);
						if (!utils::is_valid(p2) || (p2.SqDistance2D(cell) > SQUARE(SQUARE_SIZE))
							|| (p2.SqDistance2D(self) < SQUARE(clear))
							|| !KeepsExit(circuit, terrainMgr, unit, buildDef, facing, slot, cell))
						{
							continue;
						}
						bestSq = sq;
						best = cell;
					}
				}
				if (bestSq >= .0f) {
					pos = best;
					searchRadius = slot;
					found = true;
				}
			}
			// Blocked ground is ground with no free slot on ANY ring: marked
			// on the first taken cell, the script's probe ring took over the
			// placement it was meant to back up (ring-scatter 20% on the
			// seat the day the grid came back).
			if (!found && !free) {
				circuit->NoteBuildBlocked(pos);   // script decides whether to clear it
			}
		}
	}
	FindBuildSite(unit, pos, searchRadius);

	// WHY A TASK NEVER BECOMES A BUILDING. Everything upstream is logged --
	// the want, the price, the request -- and this step, where the site search
	// fails and the builder is handed back to FallbackTask, was silent. A team
	// opened 145 advanced-lab requests and started zero nanoframes with no line
	// anywhere saying so.
	if (!utils::is_valid(buildPos)) {
		circuit->LOG("apex: site-fail t=%i %s bt=%i want=%.0f,%.0f snapped=%.0f,%.0f r=%.0f",
				circuit->GetTeamId(),
				(buildDef != nullptr) ? buildDef->GetDef()->GetName() : "?",
				int(buildType), position.x, position.z, pos.x, pos.z, searchRadius);
	}

	if (utils::is_valid(buildPos)) {
		if (TaskTraceOn(circuit)) {
			const AIFloat3& up = unit->GetPos(frame);
			circuit->LOG("apex: ttrace site #%d task=%p %s at=%.0f,%.0f unit=%.0f,%.0f facing=%d enginePossible=%d held=%d reach=%d",
					unit->GetId(), static_cast<void*>(this), buildDef->GetDef()->GetName(), buildPos.x, buildPos.z, up.x, up.z, facing,
					circuit->GetMap()->IsPossibleToBuildAt(buildDef->GetDef(), buildPos, facing) ? 1 : 0,
					unit->IsDGunHeld(frame) ? 1 : 0,
					circuit->GetTerrainManager()->CanReachAt(unit, buildPos, unit->GetCircuitDef()->GetBuildDistance()) ? 1 : 0);
		}
		TRY_UNIT(circuit, unit,
			unit->CmdBuild(buildDef, buildPos, facing, 0, frame + FRAMES_PER_SEC * 60);
		)
	} else {
		if (circuit->GetSetupManager()->GetBasePos().SqDistance2D(position) < SQUARE(searchRadius)) {  // base must be full
			circuit->GetSetupManager()->FindNewBase(unit);
		}

		// Fallback to Guard/Assist/Patrol
		SetDeathNote("no-site");
		manager->FallbackTask(unit);
		return false;
	}
	return true;
}

void IBuilderTask::OnUnitIdle(CCircuitUnit* unit)
{
	if (++buildFails <= 2) {  // Workaround due to engine's ability randomly disregard orders
		Execute(unit);
	} else if (buildFails <= TASK_RETRIES) {
		RemoveAssignee(unit);
	} else if (target == nullptr) {
		SetDeathNote("retries");
		// ABORTING NO LONGER POISONS THE GROUND.
		//
		// Upstream stamped a permanent blocker at buildPos here, with its own
		// FIXME asking for a timer. Nothing ever removed it, so ONE failure made
		// that spot unbuildable for the rest of the game -- and since the next
		// attempt sites further out, fails, and blocks that too, the buildable
		// area shrinks without bound. Measured on Supreme Isthmus 8v8: a player
		// aborted 635 advanced-lab tasks and built none, its chosen site walking
		// steadily away from home (642 -> 768) as the ground was consumed, while
		// its cheap farm builds went up fine throughout.
		//
		// A genuinely unbuildable spot is already refused by FindBuildSite (which
		// logs apex: site-fail), so the blocker was insuring against a case the
		// site search answers on its own.
		SetDeathNote("build-failed");
		manager->AbortTask(this);
	}
}

void IBuilderTask::OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	CCircuitDef* cdef = unit->GetCircuitDef();
	const float healthPerc = unit->GetHealthPercent();
	if ((healthPerc > cdef->GetRetreat()) && !unit->IsDisarmed(frame)) {
		if (healthPerc < cdef->GetSelfDHP()) {
			unit->CmdSelfD(true);
		}
		return;
	}

	// apex: STAND AND HEAL (apexearth: "a T1 con started a nano but then
	// walked away from it to go try to heal a nano which was built in one of
	// his allies bases... long walk for no big gain"). Retreat's destination
	// is the crow-flies-closest haven -- a nano cluster, possibly across the
	// map -- but a wounded builder already inside a cluster's assist reach is
	// standing in the repair bay: the nanos heal it while it keeps building.
	// Floored at apex_con_stand_floor: below it the fight here is being lost
	// and retreat is about survival, not convenience (0.5 is the config's own
	// fighter retreat line).
	if (!cdef->IsRoleComm()
		&& (circuit->GetTunable("apex_con_stand_heal", 1.f) > 0.5f)
		&& (healthPerc > circuit->GetTunable("apex_con_stand_floor", 0.5f)))
	{
		CFactoryManager* facMgr = circuit->GetFactoryManager();
		const AIFloat3& pos = unit->GetPos(frame);
		const AIFloat3 hav = facMgr->GetClosestHaven(pos);
		if (utils::is_valid(hav)
			&& (pos.SqDistance2D(hav) < SQUARE(facMgr->GetAssistRange() * 0.9f)))
		{
			static int standLogFrame = 0;
			if (frame >= standLogFrame) {
				standLogFrame = frame + FRAMES_PER_SEC * 10;
				circuit->LOG("apex: con-stand t=%i %s hp=%.2f -- healing where it works",
						circuit->GetTeamId(), cdef->GetDef()->GetName(), healthPerc);
			}
			return;
		}
	}

	// apex: THREAT-GATED SCRATCH RETREAT (apexearth ruling 2026-08-29, after
	// 43 con-retreats in one Glacier game -- corck at hp 0.81 walking 2400-2900
	// elmos while 42 mex elections became 12 mexes): above the stand floor a
	// builder leaves only where danger is actually READ -- the known attacker's
	// gun genuinely reaches this spot, or the threat map says something covers
	// it. A stray splash or a ghost shell on safe own ground is not a reason
	// to walk home. At or below the floor survival wins and it always goes.
	if (!cdef->IsRoleComm()
		&& (circuit->GetTunable("apex_con_scratch_gate", 1.f) > 0.5f)
		&& (healthPerc > circuit->GetTunable("apex_con_stand_floor", 0.5f)))
	{
		const AIFloat3& pos = unit->GetPos(frame);
		bool danger = false;
		if ((attacker != nullptr) && (attacker->GetCircuitDef() != nullptr)
			&& attacker->GetCircuitDef()->IsAttacker())
		{
			const float reach = attacker->GetCircuitDef()->GetMaxRange() + 300.f;
			danger = attacker->GetPos().SqDistance2D(pos) < SQUARE(reach);
		}
		if (!danger) {
			danger = circuit->GetThreatMap()->GetThreatAt(unit, pos) > THREAT_MIN;
		}
		if (!danger) {
			static int scratchLogFrame = 0;
			if (frame >= scratchLogFrame) {
				scratchLogFrame = frame + FRAMES_PER_SEC * 10;
				circuit->LOG("apex: con-scratch t=%i %s hp=%.2f -- no danger read, working on",
						circuit->GetTeamId(), cdef->GetDef()->GetName(), healthPerc);
			}
			return;
		}
	}

	CRetreatTask* task = manager->EnqueueRetreat();
	manager->AssignTask(unit, task);
	// apex: the walk is now visible -- one line per switch, with how far the
	// chosen haven is, so "are we doing this a lot" reads from the infolog.
	{
		const AIFloat3& pos = unit->GetPos(frame);
		const AIFloat3 hav = circuit->GetFactoryManager()->GetClosestHaven(pos);
		// Position and the def under construction ride along so the audit can
		// join this against the army snapshots: a build abandoned to damage
		// with idle allied combat in reach is the misstep he wants flagged.
		circuit->LOG("apex: con-retreat t=%i %s hp=%.2f walk=%.0f at=%.0f,%.0f job=%s",
				circuit->GetTeamId(), cdef->GetDef()->GetName(), healthPerc,
				utils::is_valid(hav) ? sqrtf(pos.SqDistance2D(hav)) : -1.f,
				pos.x, pos.z,
				(buildDef != nullptr) ? buildDef->GetDef()->GetName() : "-");
	}

	if (target == nullptr) {
		SetDeathNote("hurt-retreat");
		manager->AbortTask(this);  // Doesn't call RemoveAssignee
	}
}

void IBuilderTask::OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker)
{
	RemoveAssignee(unit);
	// NOTE: AbortTask usually does not call RemoveAssignee for each unit
	if (((target == nullptr) || units.empty()) && !unit->IsMorphing()) {
		SetDeathNote("builder-gone");
		manager->AbortTask(this);
	}
}

void IBuilderTask::OnTravelEnd(CCircuitUnit* unit)
{
	traveled.insert(unit);
}

void IBuilderTask::Activate()
{
	lastTouched = manager->GetCircuit()->GetLastFrame();
}

void IBuilderTask::Deactivate()
{
	lastTouched = -1;
}

void IBuilderTask::SetBuildPos(const AIFloat3& pos)
{
	CTerrainManager* terrainMgr = manager->GetCircuit()->GetTerrainManager();
	if (utils::is_valid(buildPos)) {
		terrainMgr->DelBlocker(buildDef, buildPos, facing);
	}
	if (utils::is_valid(pos)) {
		buildPos = CTerrainManager::Pos2BuildPos(buildDef, pos, facing);
		terrainMgr->AddBlocker(buildDef, buildPos, facing);
	} else {
		buildPos = pos;
	}
}

void IBuilderTask::SetTarget(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	if (utils::is_valid(buildPos)) {
		terrainMgr->DelBlocker(buildDef, buildPos, facing);
	}
	target = unit;
	if (unit != nullptr) {
		facing = unit->GetUnit()->GetBuildingFacing();
		buildDef = unit->GetCircuitDef();
		buildPos = unit->GetPos(circuit->GetLastFrame()) + buildDef->GetMidPosOffset(facing);
	} else {
		buildPos = -RgtVector;
	}
	if (utils::is_valid(buildPos)) {
		terrainMgr->AddBlocker(buildDef, buildPos, facing);
	}
}

void IBuilderTask::UpdateTarget(CCircuitUnit* unit)
{
	// NOTE: unit->GetPos() may differ from buildPos
	SetTarget(unit);

	CCircuitAI* circuit = manager->GetCircuit();
	int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
	for (CCircuitUnit* ass : units) {
		TRY_UNIT(circuit, ass,
			ass->CmdRepair(unit, UNIT_CMD_OPTION, frame);
		)
	}
}

bool IBuilderTask::IsEqualBuildPos(CCircuitUnit* unit) const
{
	AIFloat3 pos = unit->GetPos(manager->GetCircuit()->GetLastFrame());
	pos += unit->GetCircuitDef()->GetMidPosOffset(unit->GetUnit()->GetBuildingFacing());
	// NOTE: Unit's position is affected by collisionVolumeOffsets, and there is no way to retrieve it.
	//       Hence absurdly large error slack, @see factoryship.lua
	return utils::is_equal_pos(pos, buildPos, SQUARE_SIZE * 2);
}

CCircuitUnit* IBuilderTask::GetNextAssignee()
{
	if (units.empty()) {
		return nullptr;
	}
	auto it = (nextCursor == nullptr) ? units.begin() : units.upper_bound(nextCursor);
	if (it == units.end()) {
		it = units.begin();
	}
	nextCursor = *it;
	return nextCursor;
}

void IBuilderTask::Update(CCircuitUnit* unit)
{
	const bool re = Reevaluate(unit);
	if (TaskTraceOn(manager->GetCircuit())) {
		ITravelAction* tr = unit->GetTravelAct();
		manager->GetCircuit()->LOG("apex: ttrace update #%d task=%p re=%d travel=%s traveled=%d exec=%d q=%d", unit->GetId(),
				static_cast<void*>(this), re ? 1 : 0,
				(tr == nullptr) ? "null" : (tr->IsFinished() ? "fin" : (tr->IsWait() ? "wait" : "act")),
				static_cast<int>(traveled.count(unit)), static_cast<int>(executors.count(unit)),
				manager->GetCircuit()->GetCallback()->Unit_HasCommands(unit->GetId()) ? 1 : 0);
	}
	if (re) {
		// Reevaluate runs the script pipeline, which can REASSIGN the unit to
		// a different task -- RemoveAssignee clears its actions, so the travel
		// act read here can be null. Crashed a watched game at 3 minutes the
		// moment the assist-fallback made mid-reevaluation reassignment common.
		ITravelAction* travel = unit->GetTravelAct();
		if ((travel != nullptr) && !travel->IsFinished()) {
			UpdatePath(unit);  // Execute(unit) within OnTravelEnd
		}
	}
}

bool IBuilderTask::Reevaluate(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();

	// FIXME: Replace const 1000.0f with build time?
	// apex: default OFF. Stock aborts any >1000-metal task without a started
	// frame the moment average income dips to 60% of its creation-time read
	// during a stall -- which is every expensive walk in a spiky economy, and
	// exactly why heavy front turrets never finished while 85-metal LLTs did.
	// The script market already prices stalls (MCostScale, EPriceCostAt); a
	// second, hidden veto underneath it is the AI fighting itself.
	CEconomyManager* ecoMgr = circuit->GetEconomyManager();
	if ((circuit->GetTunable("apex_stock_stall_abort", 0.f) > 0.f)
		&& (cost.metal > 1000.f)
		&& (target == nullptr)
		&& (((ecoMgr->GetAvgMetalIncome() < savedIncome.metal * 0.6f) && (ecoMgr->GetAvgMetalIncome() * 2.0f < ecoMgr->GetMetalPull()))
			|| ((ecoMgr->GetAvgEnergyIncome() < savedIncome.energy * 0.6f) && (ecoMgr->GetAvgEnergyIncome() * 2.0f < ecoMgr->GetEnergyPull())))
		)
	{
		SetDeathNote("stall-abort");
		manager->AbortTask(this);
		return false;
	}

	/*
	 * Reassign task if required
	 */
	const int frame = circuit->GetLastFrame();
	const AIFloat3& pos = unit->GetPos(frame);
	const float sqDist = pos.SqDistance2D(GetPosition());
	if (sqDist <= SQUARE(unit->GetCircuitDef()->GetBuildDistance() + circuit->GetPathfinder()->GetSquareSize())
		&& (circuit->GetInflMap()->GetInfluenceAt(pos) > -INFL_EPS))
	{
//		if (unit->GetCircuitDef()->IsRoleComm()) {  // FIXME: or any other builder-attacker
//			if (circuit->GetInflMap()->GetEnemyInflAt(circuit->GetSetupManager()->GetBasePos()) < INFL_EPS) {
//				return true;
//			}
//		} else {
//			return true;
//		}

		// NOTE: helps with obstructed factory, but not with blocked building plan.
		//       @see CTerrainManager::CheckObstruct and its issues.
		if ((unit->GetCircuitDef()->GetMobileId() >= 0) && circuit->GetTerrainManager()->IsObstruct(pos)) {
			if ((unit->GetTaskFrame() + FRAMES_PER_SEC * 5 < frame) && (unit->GetUnit()->GetVel().SqLength2D() < 1e-3f)) {
				unit->SetTaskFrame(frame);  // re-use taskFrame
				TRY_UNIT(circuit, unit,
					AIFloat3 awayPos = utils::get_radial_pos(pos, 64.f);
					CTerrainManager::CorrectPosition(awayPos);
					unit->CmdMoveTo(awayPos, UNIT_CMD_OPTION, frame + FRAMES_PER_SEC * 60, CCircuitUnit::OrdSrc::BUILD);
				)
			}
			return true;
		}

		if ((buildType != BuildType::GUARD)
			&& ((executors.size() < 2) || !unit->IsAttrBase()))
		{
			// apex: default OFF. Stock answers an empty E bank by parking every
			// non-energy builder in range on a literal Wait order; the parked
			// fleet stops pulling, so from outside the stall reads "healthy"
			// while nothing builds. The script market prices the stall and
			// answers it with a zero-E solar instead (want_energy.as); with the
			// gate off this same call actively releases any unit still waiting.
			const bool stallWait = (circuit->GetTunable("apex_stock_stall_wait", 0.f) > 0.f)
					&& ecoMgr->IsEnergyEmpty() && (buildType != BuildType::ENERGY) && (buildType != BuildType::GEO)
					&& (buildType != BuildType::STORE) && (buildType != BuildType::RECLAIM);
			TRY_UNIT(circuit, unit,
				const bool prio = !ecoMgr->IsEnergyStalling() || (buildType == BuildType::ENERGY) || (buildType == BuildType::GEO);
				unit->CmdBARPriority(prio ? 1.f : 0.f);
				if (unit->GetTravelAct()->IsFinished()) {
					unit->CmdWait(stallWait);
				}
			)
			return true;
		}
	} else {
		// Remove wait if unit was pushed away from build position
		TRY_UNIT(circuit, unit,
			unit->CmdWait(false);
		)
	}
	// apex: a walking builder's re-election is a CONFIRMATION, not a request
	// for work -- measured 3,047 hook calls a minute at 647 builders with
	// only ~318 electing anything new, each confirmation paying the script
	// crossing plus the ladder preamble (~1s of every game-minute). Ask the
	// market again at most every few seconds; a finished or aborted task
	// still elects immediately through the idle path. Commanders keep every
	// update (their safety check lives inside the election) and so do rez
	// bots (their flee does too).
	{
		constexpr int REELECT_FRAMES = 3 * FRAMES_PER_SEC;
		CCircuitDef* rdef = unit->GetCircuitDef();
		if ((rdef != nullptr) && !rdef->IsRoleComm() && !rdef->IsAbleToResurrect()
			&& (frame - unit->GetElectFrame() < REELECT_FRAMES))
		{
			return true;
		}
		unit->SetElectFrame(frame);
	}
	HideAssignee(unit);
	sInReelect = true;   // apex: strand census (see RemoveAssignee)
	IUnitTask* task = manager->MakeTask(unit);
	sInReelect = false;
	ShowAssignee(unit);
	if ((task != nullptr)
		&& ((task->GetType() != IUnitTask::Type::BUILDER)
			|| (static_cast<IBuilderTask*>(task)->GetBuildType() != buildType)))
	{
		manager->AssignTask(unit, task);
		return false;
	}
	return true;
}

void IBuilderTask::UpdatePath(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	// TODO: Check IsForceUpdate, shield charge and retreat

	CCircuitDef* cdef = unit->GetCircuitDef();
	// The engine builds from buildDistance + the buildee's radius (CBuilder);
	// testing the bare distance to a shipyard's CENTRE refused every shore
	// site a bot con could actually build from.
	const float range = cdef->GetBuildDistance()
			+ ((buildDef != nullptr) ? buildDef->GetRadius() : 0.f);
	const AIFloat3& endPos = GetPosition();
	// A DEFENCE IS BUILT INTO THE THREAT IT ANSWERS. The safe-reach veto
	// killed every front tower task ever created (s43: all bt=7 deaths
	// why=unreach-safe; 960 front elections won, 0 towers built) -- the
	// ground a tower is for is exactly the ground this refused. Defence
	// types test pure reachability; everything else keeps the threat term.
	const bool intoThreat = (buildType == BuildType::DEFENCE)
			|| (buildType == BuildType::BUNKER)
			|| (buildType == BuildType::BIG_GUN);
	// THE BAR FOR ECONOMY IS NOT THE BUILDER'S OWN POWER. A constructor's power
	// is ~0, so a site was refused at threat 0.1 -- the residue of a raider
	// that passed minutes ago -- and on a raided map the cons built nothing
	// at all (Frozen Ford 2v2, watched: 3 of 34 spots held at 30 min, 21 of
	// 26 mex tasks refused at threats of 0.1-3). The bar is OUR OWN GUNS'
	// influence at the site, the same power scale as the threat: ground our
	// towers reach is built under them, ground they do not is refused while
	// it is hot -- and that gap is what the defence market prices first.
	float safeBar = cdef->GetPower();
	if (!intoThreat) {
		safeBar = std::max(safeBar, std::max(THREAT_MIN, circuit->GetAllyDefendInflAt(endPos)));
	}
	if ((target == nullptr)
		&& !(intoThreat
			? circuit->GetTerrainManager()->CanReachAt(unit, endPos, range)
			: circuit->GetTerrainManager()->CanReachAtSafe(unit, endPos, range, safeBar)))
	{
		// The chooser tested reachability from HOME (CanDefReach); this
		// stricter per-unit test disagreeing is exactly the loop where a
		// deterministic site is re-elected and aborted forever (t5's no-lab
		// pocket, SI 8v8 s106). Mark the ground so ProbedSite steps around
		// it on the next election.
		circuit->NoteBuildBlocked(endPos);
		{
			const float gap = circuit->GetTerrainManager()->ReachGap(unit->GetArea(), endPos);
			circuit->LOG("apex: unreach %s bt=%i by %s at=%.0f,%.0f gap=%.0f range=%.0f threat=%.1f/%.1f",
					(buildDef != nullptr) ? buildDef->GetDef()->GetName() : "?", int(buildType),
					cdef->GetDef()->GetName(), endPos.x, endPos.z, gap, range,
					circuit->GetThreatMap()->GetThreatAt(endPos), cdef->GetPower());
		}
		SetDeathNote("unreach-safe");
		if (!intoThreat) {
			circuit->NoteUnsafeSite(endPos);
		}
		manager->AbortTask(this);
		return;
	}

	const AIFloat3& startPos = unit->GetPos(circuit->GetLastFrame());

	// NO PATH IS COMPUTED FOR AN IN-BASE BUILD. That is right when the builder
	// is at the site and wrong when it is 700 elmos away with a 145 build
	// range -- it is told nothing and stands there until the stuck watchdog
	// aborts the task. baseDefRange is terrainDiagonal * 0.3, so most of the
	// map can qualify. Counted before anything is changed: `inRange` is the
	// legitimate case, `farInBase` is the suspect one, and their ratio is the
	// whole question.
	const bool inRange = startPos.SqDistance2D(endPos) < SQUARE(range);
	const bool bothInBase =
			(circuit->GetSetupManager()->GetBasePos().SqDistance2D(startPos) < SQUARE(circuit->GetMilitaryManager()->GetBaseDefRange()))
			&& (circuit->GetSetupManager()->GetBasePos().SqDistance2D(endPos) < SQUARE(circuit->GetMilitaryManager()->GetBaseDefRange()));
	// A BUILDER IS ONLY EXCUSED FROM PATHING WHEN IT CAN ALREADY REACH THE JOB.
	// The in-base shortcut excused it whenever builder AND site were inside
	// baseDefRange -- a 1,120-elmo radius, so a 2,240-elmo disc -- and 69% of
	// the time it fired the builder was NOT in build range: measured
	// inRange=29 farInBase=66, worst 1,952 elmos against a 112 build range.
	// Those builders are handed no path, no move, and nothing to do; they
	// stand where they are until the stuck watchdog aborts the task at 30s.
	// Every stuck builder measured sat 500-1,175 elmos from its site with
	// progress 0.00 and no move failure, because no move was ever ordered.
	// Pathing every in-base build was measured and bought nothing; the pathless
	// builders are not the parked ones. Off by default, table in docs/27.
	const bool skipPath = inRange || (bothInBase
			&& (circuit->GetTunable("apex_inbase_path", 0.f) <= 0.f));
	if (TaskTraceOn(circuit)) {
		circuit->LOG("apex: ttrace path #%d task=%p skip=%d inRange=%d", unit->GetId(), static_cast<void*>(this), skipPath ? 1 : 0, inRange ? 1 : 0);
	}
	if (skipPath) {
		static unsigned sInRange = 0, sFarInBase = 0, sFarWorst = 0;
		static int sPathSkipLogAt = 0;
		if (inRange) {
			++sInRange;
		} else {
			++sFarInBase;
			const unsigned d = (unsigned)sqrtf(startPos.SqDistance2D(endPos));
			if (d > sFarWorst) { sFarWorst = d; }
		}
		const int f = circuit->GetLastFrame();
		if (f >= sPathSkipLogAt) {
			sPathSkipLogAt = f + FRAMES_PER_SEC * 60;
			circuit->LOG("apex: pathskip t=%i inRange=%u farInBase=%u worst=%u range=%.0f baseR=%.0f",
					circuit->GetTeamId(), sInRange, sFarInBase, sFarWorst, range,
					circuit->GetMilitaryManager()->GetBaseDefRange());
		}
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateFinish();
		}
		return;
	}

	if (!IsQueryReady(unit)) {
		return;
	}

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			unit, circuit->GetThreatMap(),
			startPos, endPos, range);
	pathQueries[unit] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyPath(static_cast<const CQueryPathSingle*>(query));
	});
}

void IBuilderTask::ApplyPath(const CQueryPathSingle* query)
{
	const std::shared_ptr<CPathInfo>& pPath = query->GetPathInfo();
	CCircuitUnit* unit = query->GetUnit();
	// The query completed AFTER the unit's actions were cleared (task switch
	// or death): GetTravelAct() is null and SetPath through it crashed three
	// identical tournament games (2026-08-15). The path is simply unwanted.
	if ((unit == nullptr) || (unit->GetTravelAct() == nullptr)) {
		return;
	}

	if (TaskTraceOn(manager->GetCircuit())) {
		manager->GetCircuit()->LOG("apex: ttrace applypath #%d task=%p size=%d", unit->GetId(), static_cast<void*>(this), static_cast<int>(pPath->path.size()));
	}
	if (pPath->path.size() > 2) {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->SetPath(pPath);
		}
	} else {
		if (unit->GetTravelAct() != nullptr) {  // null after ClearAct: path unwanted
			unit->GetTravelAct()->StateFinish();
		}
	}
}

void IBuilderTask::HideAssignee(CCircuitUnit* unit)
{
	CEconomyManager* economyMgr = manager->GetCircuit()->GetEconomyManager();
	if (buildDef == nullptr) {
		const float buildSpeed = unit->GetBuildSpeed();
		buildPower.metal -= buildSpeed;
		buildPower.energy -= buildSpeed * economyMgr->GetEcoEM();
	} else {
		const float buildTime = buildDef->GetBuildTime() / unit->GetWorkerTime();
		const float metalRequire = buildDef->GetCostM() / buildTime;
		const float energyRequire = buildDef->GetCostE() / buildTime;
		buildPower.metal -= metalRequire;
		buildPower.energy -= energyRequire;
		if (!economyMgr->IsIgnorePull(this)) {
			manager->DelMetalPull(metalRequire);
		}
	}
}

void IBuilderTask::ShowAssignee(CCircuitUnit* unit)
{
	CEconomyManager* economyMgr = manager->GetCircuit()->GetEconomyManager();
	if (buildDef == nullptr) {
		const float buildSpeed = unit->GetBuildSpeed();
		buildPower.metal += buildSpeed;
		buildPower.energy += buildSpeed * economyMgr->GetEcoEM();
	} else {
		const float buildTime = buildDef->GetBuildTime() / unit->GetWorkerTime();
		const float metalRequire = buildDef->GetCostM() / buildTime;
		const float energyRequire = buildDef->GetCostE() / buildTime;
		buildPower.metal += metalRequire;
		buildPower.energy += energyRequire;
		if (!economyMgr->IsIgnorePull(this)) {
			manager->AddMetalPull(metalRequire);
		}
	}
}

CAllyUnit* IBuilderTask::FindSameAlly(CCircuitUnit* builder, const std::vector<Unit*>& friendlies)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	const int frame = circuit->GetLastFrame();

	for (Unit* au : friendlies) {
		CAllyUnit* alu = circuit->GetFriendlyUnit(au);
		if (alu == nullptr) {
			continue;
		}
		if ((*alu->GetCircuitDef() == *buildDef) && au->IsBeingBuilt()) {
			const AIFloat3& pos = alu->GetPos(frame);
			if (terrainMgr->CanReachAtSafe(builder, pos, builder->GetCircuitDef()->GetBuildDistance())) {
				return alu;
			}
		}
	}
	return nullptr;
}

void IBuilderTask::FindBuildSite(CCircuitUnit* builder, const AIFloat3& pos, float searchRadius)
{
	FindFacing(pos);

	CTerrainManager* terrainMgr = manager->GetCircuit()->GetTerrainManager();
	// A DEFENCE TASK MAY STAND ON GROUND THAT IS NOT PERFECTLY QUIET.
	//
	// apexearth: "Maybe we need to be OK with building under some level of
	// threat..." -- said after watching constructors idle in the early game while
	// the front line went unbuilt, and after "their base basically IS on the
	// frontline."
	//
	// The engine already contradicts itself here. UpdatePath, thirty lines up,
	// decides whether the builder may TRAVEL to the site with
	// CanReachAtSafe(unit, endPos, range, cdef->GetPower()) -- threat up to the
	// builder's own power. This predicate omits the argument and so takes the
	// default, THREAT_MIN (1.0, util/Defines.h). We are permitted to walk there
	// and then refused anywhere to stand.
	//
	// Measured from the script side before this changed: front-defence orders were
	// not aborted and not unreachable, they were alive and unstaffed -- 48-105 per
	// player per game against 1-18 aborted -- because FindBuildSite returned
	// nothing and Execute fell through to FallbackTask, releasing the builder.
	//
	// Only DEFENCE. An extractor or a reactor placed in a threatened cell is a
	// building that dies; a turret placed there is the entire point of the turret.
	// The bar is the TURRET'S power, not the builder's. A constructor's power is
	// ~0, so keying on it made this stricter than the default it replaced and
	// measured flat: 0% of defences forward against 5% before. What a defence
	// task should tolerate is what the thing being built can answer -- a Beamer
	// belongs exactly where a Beamer's worth of threat is.
	float threatBar = THREAT_MIN;
	if ((buildType == BuildType::DEFENCE) && (buildDef != nullptr)) {
		threatBar = std::max(THREAT_MIN, buildDef->GetPower());
	}
	// THE STREETS ARE A RULE HERE, NOT ONLY AT THE SNAP.
	//
	// SnapToBaseGrid pushes a placement out of a walkway, and then this search
	// runs -- at 3200 elmos whenever the slot it snapped to was taken, which in
	// a filling base is most of the time. Every one of those searches was free
	// to settle in a corridor, so the lanes held early and quietly closed as the
	// base packed. Measured over 657 matches: 414 units walled in by our own
	// buildings, and the wall was the eco farm (solar 133, wind 98, converter 58,
	// nano 69) rather than anything on the line.
	//
	// A FIXED task is exempt: a mex sits on its spot or not at all, and refusing
	// the spot loses the mex rather than moving it.
	CCircuitAI* circuit = manager->GetCircuit();
	const bool keepLanes = !IsFixedSite(buildType);
	// NOTHING IS BUILT UNDER LAVA. The rising-tide maps flood a basin over a
	// couple of minutes and everything standing in it burns down; a nanoframe
	// raised there is metal handed to the map. This catches the farm -- the
	// generators, converters and nanos the lattice is free to move. It shares
	// the lanes' exemption for a FIXED site, which is one the script chose
	// deliberately (an extractor's spot, a turret's slot, a factory's apron);
	// those are filtered where they are chosen instead, in manager/lava.as.
	// Costs nothing off a lava map -- HasLava is one cached compare.
	const bool dryOnly = keepLanes && circuit->HasLava();
	CCircuitDef* siteDef = buildDef;
	// NOT ON THE BUILDER'S OWN FEET (see SelfClearance): the search reads a
	// mobile unit as empty ground and hands back the square it is standing on,
	// which cannot be started until the builder has been pushed clear of it.
	// A spot site is exempt -- it is that vent or nothing.
	const float selfClear = IsSpotSite(buildType) ? 0.f : SelfClearance(builder, buildDef);
	const AIFloat3 builderPos = builder->GetPos(circuit->GetLastFrame());
	// Each pass gets its OWN predicate with everything captured BY VALUE. An
	// earlier version flipped one captured-by-reference flag between the two
	// passes; FindBuildSite takes the predicate by non-const reference and the
	// AI crashed with an access violation on two of twelve games. Nothing here
	// outlives this frame now.
	auto makePredicate = [terrainMgr, builder, threatBar, circuit, keepLanes, dryOnly, siteDef, builderPos](bool aboveCrest, float selfBar) {
		return CTerrainManager::TerrainPredicate([terrainMgr, builder, threatBar, circuit, keepLanes, dryOnly, siteDef, aboveCrest, builderPos, selfBar](const AIFloat3& p) {
			if ((selfBar > 0.f) && (p.SqDistance2D(builderPos) < SQUARE(selfBar))) {
				return false;
			}
			if (keepLanes && circuit->IsInBaseLane(p)) {
				return false;
			}
			if (dryOnly && circuit->IsUnderLava(p, siteDef)) {
				return false;
			}
			if (aboveCrest && !circuit->AboveLavaCrest(p)) {
				return false;
			}
			return terrainMgr->CanReachAtSafe(builder, p,
					builder->GetCircuitDef()->GetBuildDistance(), threatBar);
		});
	};
	// ABOVE THE HIGH-WATER MARK FIRST. The submerged veto only refuses ground
	// the tide is on RIGHT NOW, so at low tide the whole basin reads dry and
	// the farm fills it, to burn on the next climb. The crest is the mark it
	// has proven it reaches; the farm takes ground over that when any exists,
	// and falls back to the ordinary search when none does -- returning
	// nothing here releases the builder to a FallbackTask, which is how
	// forward defence quietly went unstaffed once already.
	auto search = [&](float selfBar) {
		CTerrainManager::TerrainPredicate predicate = makePredicate(dryOnly, selfBar);
		AIFloat3 s = terrainMgr->FindBuildSite(buildDef, pos, searchRadius, facing, predicate);
		if (dryOnly && !utils::is_valid(s)) {
			CTerrainManager::TerrainPredicate wet = makePredicate(false, selfBar);
			s = terrainMgr->FindBuildSite(buildDef, pos, searchRadius, facing, wet);
		}
		return s;
	};
	AIFloat3 site = search(selfClear);
	// Nowhere in reach BUT under our own feet: take it and step aside, exactly
	// as before. Returning nothing here releases the builder to a FallbackTask,
	// which is how forward defence quietly went unstaffed once already.
	if ((selfClear > 0.f) && !utils::is_valid(site)) {
		site = search(0.f);
	}
	SetBuildPos(site);
}

void IBuilderTask::FindFacing(const springai::AIFloat3& pos)
{
	// apex: inside the published base frame, face the axis (the road to the
	// front) rather than the map centre, so a factory's exit apron opens onto
	// ground the grid keeps clear. FactoryTask still rotates through all four
	// facings if this one cannot place.
	const int gridFacing = manager->GetCircuit()->GetBaseGridFacing(pos);
	if (gridFacing != UNIT_NO_FACING) {
		facing = gridFacing;
		return;
	}
	CTerrainManager* terrainMgr = manager->GetCircuit()->GetTerrainManager();

//	facing = UNIT_NO_FACING;
	float terWidth = terrainMgr->GetTerrainWidth();
	float terHeight = terrainMgr->GetTerrainHeight();
	if (std::fabs(terWidth - 2 * pos.x) > std::fabs(terHeight - 2 * pos.z)) {
		facing = (2 * pos.x > terWidth) ? UNIT_FACING_WEST : UNIT_FACING_EAST;
	} else {
		facing = (2 * pos.z > terHeight) ? UNIT_FACING_NORTH : UNIT_FACING_SOUTH;
	}
}

void IBuilderTask::ExecuteChain(SBuildChain* chain)
{
	assert(chain != nullptr);
	// Brain overhaul 2026-08-22: the DLL originates no economy/build decisions; the script Brain does.
	// build_chain.json hubs are dead for apex.
	return;
}

#define SERIALIZE(stream, func)	\
	utils::binary_##func(stream, positionF3);			\
	utils::binary_##func(stream, shake);				\
	utils::binary_##func(stream, bdefId);				\
	utils::binary_##func(stream, cost.metal);			\
	utils::binary_##func(stream, cost.energy);			\
	utils::binary_##func(stream, targetId);				\
	utils::binary_##func(stream, buildPosF3);			\
	utils::binary_##func(stream, facing);				\
	utils::binary_##func(stream, savedIncome.metal);	\
	utils::binary_##func(stream, savedIncome.energy);	\
	utils::binary_##func(stream, buildFails);

bool IBuilderTask::Load(std::istream& is)
{
	CCircuitDef::Id bdefId;
	CCircuitUnit::Id targetId;
	float positionF3[3];
	float buildPosF3[3];

	IUnitTask::Load(is);
	SERIALIZE(is, read)

	CCircuitAI* circuit = manager->GetCircuit();
	buildDef = circuit->GetCircuitDefSafe(bdefId);
	target = circuit->GetTeamUnit(targetId);
	position = AIFloat3(positionF3);
	buildPos = AIFloat3(buildPosF3);

	if ((target != nullptr) && (buildType != BuildType::REPAIR) && (buildType != BuildType::RECLAIM)) {
		circuit->GetBuilderManager()->MarkUnfinishedUnit(target, this);
	}
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | position=%f,%f,%f | shake=%f | bdefId=%i | costM=%f | costE=%f | targetId=%i | buildPos=%f,%f,%f | facing=%i | savedIncomeM=%f | savedIncomeE=%f | buildFails=%i | buildDef=%p | target=%p",
			__PRETTY_FUNCTION__, position.x, position.y, position.z, shake, bdefId, cost.metal, cost.energy, targetId, buildPos.x, buildPos.y, buildPos.z, facing, savedIncome.metal, savedIncome.energy, buildFails, buildDef, target);
#endif
	return true;
}

void IBuilderTask::Save(std::ostream& os) const
{
	CCircuitDef::Id bdefId = (buildDef != nullptr) ? buildDef->GetId() : -1;
	CCircuitUnit::Id targetId = (target != nullptr) ? target->GetId() : -1;
	float positionF3[3];
	float buildPosF3[3];
	position.LoadInto(positionF3);
	buildPos.LoadInto(buildPosF3);

	IUnitTask::Save(os);
	SERIALIZE(os, write)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | positionF3=%f,%f,%f | shake=%f | bdefId=%i | costM=%f | costE=%f | targetId=%i | buildPosF3=%f,%f,%f | facing=%i | savedIncomeM=%f | savedIncomeE=%f | buildFails=%i",
			__PRETTY_FUNCTION__, positionF3[0], positionF3[1], positionF3[2], shake, bdefId, cost.metal, cost.energy, targetId, buildPosF3[0], buildPosF3[1], buildPosF3[2], facing, savedIncome.metal, savedIncome.energy, buildFails);
#endif
}

#ifdef DEBUG_VIS
void IBuilderTask::Log()
{
	IUnitTask::Log();
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->LOG("buildType: %i", buildType);
	circuit->GetDrawer()->AddPoint(GetPosition(), (buildDef != nullptr) ? buildDef->GetDef()->GetName() : "task");
}
#endif

} // namespace circuit
