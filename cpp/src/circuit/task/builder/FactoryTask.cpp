/*
 * FactoryTask.cpp
 *
 *  Created on: Jan 30, 2015
 *      Author: rlcevg
 */

#include "task/builder/FactoryTask.h"
#include "module/BuilderManager.h"
#include "module/FactoryManager.h"
#include "setup/SetupManager.h"
#include "scheduler/Scheduler.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"
#include "spring/SpringMap.h"

#include "AISCommands.h"

namespace circuit {

using namespace springai;

static int opposite[] = {
	UNIT_FACING_NORTH,
	UNIT_FACING_WEST,
	UNIT_FACING_SOUTH,
	UNIT_FACING_EAST
};

CBFactoryTask::CBFactoryTask(ITaskModule* mgr, Priority priority,
							 CCircuitDef* buildDef, CCircuitDef* reprDef, const AIFloat3& position,
							 SResource cost, float shake, bool isPlop, int timeout)
		: IBuilderTask(mgr, priority, buildDef, position, Type::BUILDER, BuildType::FACTORY, cost, shake, timeout)
		, reprDef(reprDef)
		, isPlop(isPlop)
{
	manager->GetCircuit()->GetFactoryManager()->AddFactory(buildDef);
}

CBFactoryTask::CBFactoryTask(ITaskModule* mgr)
		: IBuilderTask(mgr, Type::BUILDER, BuildType::FACTORY)
		, reprDef(nullptr)
		, isPlop(false)
{
}

CBFactoryTask::~CBFactoryTask()
{
}

void CBFactoryTask::Start(CCircuitUnit* unit)
{
	if (isPlop) {
		Execute(unit);
	} else {
		IBuilderTask::Start(unit);
	}
}

void CBFactoryTask::Update()
{
	if (!isPlop) {
		IBuilderTask::Update();
	}
}

void CBFactoryTask::Cancel()
{
	IBuilderTask::Cancel();

	if (target == nullptr) {
		manager->GetCircuit()->GetFactoryManager()->DelFactory(buildDef);
	}
}

void CBFactoryTask::Activate()
{
	manager->GetCircuit()->GetFactoryManager()->ApplySwitchFrame();
	IBuilderTask::Activate();
}

void CBFactoryTask::FindBuildSite(CCircuitUnit* builder, const AIFloat3& pos, float searchRadius)
{
	CCircuitAI* circuit = manager->GetCircuit();
	// A FACTORY IS THE WORST THING TO PARK ON TOP OF ITS OWN BUILDER: the
	// biggest footprint we place, and nothing can start until whoever ordered
	// it has been pushed off the whole apron. Same rule as
	// IBuilderTask::FindBuildSite, and the same last-resort relaxation below --
	// a factory that can only stand here still stands here.
	const float selfClear = SelfClearance(builder, buildDef);
	const AIFloat3 builderPos = builder->GetPos(circuit->GetLastFrame());
	if (!TryBuildSite(builder, pos, searchRadius, selfClear, builderPos)
		&& (selfClear > 0.f))
	{
		TryBuildSite(builder, pos, searchRadius, 0.f, builderPos);
	}
}

bool CBFactoryTask::TryBuildSite(CCircuitUnit* builder, const AIFloat3& pos,
		float searchRadius, float selfBar, const AIFloat3& builderPos)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	auto clearsBuilder = [selfBar, &builderPos](const AIFloat3& p) {
		return (selfBar <= 0.f) || (p.SqDistance2D(builderPos) >= SQUARE(selfBar));
	};
	// apex: THE DOOR MUST OPEN ONTO GROUND ITS UNITS CAN DRIVE (his watched game
	// 2026-09-28: a hover lab faced into a mountain and nothing got out). The
	// footprint test below only asks whether the BUILDING could stand ahead.
	// One and two footprints out, the product's own move type must stand in
	// one connected area.
	CTerrainManager* exitTerrain = circuit->GetTerrainManager();
	const float exitStep = std::max(buildDef->GetDef()->GetXSize(), buildDef->GetDef()->GetZSize()) * SQUARE_SIZE;
	// apex: ...AND NO BUILDING OF OURS OR AN ALLY'S STANDS IN IT (his watch
	// 2026-09-28: a gantry placed facing its own two advanced solars, 128
	// elmos out). Two footprints ahead, the factory's width, at the facing
	// the engine will actually build with.
	auto laneClear = [this, circuit, exitStep](const AIFloat3& bp) {
		AIFloat3 fwd(0.f, 0.f, 0.f);
		switch (facing) {
			default:
			case UNIT_FACING_SOUTH: fwd.z = 1.f; break;
			case UNIT_FACING_EAST:  fwd.x = 1.f; break;
			case UNIT_FACING_NORTH: fwd.z = -1.f; break;
			case UNIT_FACING_WEST:  fwd.x = -1.f; break;
		}
		const float half = exitStep * 0.5f;
		const AIFloat3 mid = bp + fwd * (half + exitStep * 0.75f);
		circuit->UpdateFriendlyUnits();
		auto& units = circuit->GetCallback()->GetFriendlyUnitsIn(mid, exitStep * 1.5f + 64.f);
		bool clear = true;
		for (springai::Unit* u : units) {
			if (!clear) {
				break;
			}
			auto [cand, isTeam] = circuit->GetTeamOrAllyUnit(u);
			if (cand == nullptr) {
				continue;
			}
			CCircuitDef* cd = cand->GetCircuitDef();
			if ((cd == nullptr) || cd->IsMobile()) {
				continue;
			}
			const AIFloat3& up = cand->GetPos(circuit->GetLastFrame());
			const float uh = std::max(cd->GetDef()->GetXSize(), cd->GetDef()->GetZSize()) * SQUARE_SIZE * 0.5f;
			const float rx = up.x - bp.x;
			const float rz = up.z - bp.z;
			const float ahead = rx * fwd.x + rz * fwd.z;
			const float side = std::fabs(rx * fwd.z - rz * fwd.x);
			if ((ahead + uh > half) && (ahead - uh < 2.f * exitStep) && (side - uh < half)) {
				clear = false;
			}
		}
		utils::free(units);
		return clear;
	};
	// apex: ...AND IT STANDS IN NOBODY ELSE'S WAY (his 10-22 hosted game: an unused T1 lab in an ally's open lane).
	// The commit exempted factories from the street test every other building passes (IsFixedSite), and laneClear
	// guards only the new lab's own door. Refused: any part of the footprint on our streets or an in-process ally's
	// (IsInBaseLane, centre and corners), and the footprint over another factory's door -- ours or any ally's, two
	// of its footprints ahead at its own facing, its width. apex_fac_lanes 0 is the old commit.
	const bool othersOn = circuit->GetTunable("apex_fac_lanes", 1.f) > 0.f;
	auto othersClear = [this, circuit, othersOn](const AIFloat3& bp) {
		if (!othersOn) {
			return true;
		}
		const bool turned = (facing == UNIT_FACING_EAST) || (facing == UNIT_FACING_WEST);
		const float hx = (turned ? buildDef->GetDef()->GetZSize() : buildDef->GetDef()->GetXSize()) * SQUARE_SIZE * 0.5f;
		const float hz = (turned ? buildDef->GetDef()->GetXSize() : buildDef->GetDef()->GetZSize()) * SQUARE_SIZE * 0.5f;
		const AIFloat3 pts[5] = {bp, AIFloat3(bp.x - hx, bp.y, bp.z - hz), AIFloat3(bp.x + hx, bp.y, bp.z - hz),
				AIFloat3(bp.x - hx, bp.y, bp.z + hz), AIFloat3(bp.x + hx, bp.y, bp.z + hz)};
		for (const AIFloat3& q : pts) {
			if (circuit->IsInBaseLane(q)) {
				return false;
			}
		}
		circuit->UpdateFriendlyUnits();
		auto& units = circuit->GetCallback()->GetFriendlyUnitsIn(bp, 700.f);
		bool clear = true;
		for (springai::Unit* u : units) {
			if (!clear) {
				break;
			}
			auto [cand, isTeam] = circuit->GetTeamOrAllyUnit(u);
			if (cand == nullptr) {
				continue;
			}
			CCircuitDef* cd = cand->GetCircuitDef();
			if ((cd == nullptr) || cd->IsMobile() || !cd->IsBuilder()) {
				continue;
			}
			AIFloat3 fwd(0.f, 0.f, 0.f);
			switch (u->GetBuildingFacing()) {
				default:
				case UNIT_FACING_SOUTH: fwd.z = 1.f; break;
				case UNIT_FACING_EAST:  fwd.x = 1.f; break;
				case UNIT_FACING_NORTH: fwd.z = -1.f; break;
				case UNIT_FACING_WEST:  fwd.x = -1.f; break;
			}
			const float usz = std::max(cd->GetDef()->GetXSize(), cd->GetDef()->GetZSize()) * SQUARE_SIZE;
			const float uh = usz * 0.5f;
			const AIFloat3& up = cand->GetPos(circuit->GetLastFrame());
			const float rx = bp.x - up.x;
			const float rz = bp.z - up.z;
			const float ahead = rx * fwd.x + rz * fwd.z;
			const float side = std::fabs(rx * fwd.z - rz * fwd.x);
			const float extAhead = (fwd.x != 0.f) ? hx : hz;
			const float extSide = (fwd.x != 0.f) ? hz : hx;
			if ((ahead + extAhead > uh) && (ahead - extAhead < uh + 2.f * usz) && (side - extSide < uh)) {
				clear = false;
			}
		}
		utils::free(units);
		return clear;
	};
	auto exitOpen = [this, exitTerrain, &laneClear, &othersClear](const AIFloat3& bp) {
		return laneClear(bp) && othersClear(bp) && exitTerrain->FactoryExitOpen(buildDef, bp, facing);
	};
	// apex: ...NOR ON A TEAMMATE'S EXIT PATH, AND ITS OWN DOOR LEADS OUT (crowd8: labs and air plants placed on other
	// seats' exit paths by the handed-site branch below, which takes a site the engine accepts without the blocking
	// map; gantries placed into nano blocks with no way out). Asked once per final candidate -- the engine path is
	// dear -- not per spiral step.
	CCircuitDef* exitMobile = circuit->GetFactoryManager()->GetLargestDef(buildDef);
	const AIFloat3 exitGoal = circuit->GetSetupManager()->GetLanePos();
	auto leadsOut = [this, circuit, exitTerrain, exitMobile, &exitGoal](const AIFloat3& bp) {
		if (exitTerrain->OnTeamExitPath(buildDef, bp, facing)) {
			circuit->LOG("apex: fac-site-refused t=%i %s at=%.0f,%.0f why=exit-path", circuit->GetTeamId(),
					buildDef->GetDef()->GetName(), bp.x, bp.z);
			return false;
		}
		if ((exitMobile != nullptr) && !exitTerrain->DoorEscapes(buildDef, exitMobile, bp, facing, exitGoal)) {
			circuit->LOG("apex: fac-site-refused t=%i %s at=%.0f,%.0f why=dead-end facing=%i", circuit->GetTeamId(),
					buildDef->GetDef()->GetName(), bp.x, bp.z, facing);
			return false;
		}
		return true;
	};
	// The handed site as is -- but the engine's test passes an unclaimed metal
	// spot, which the spiral below would refuse (a corlab on its own mex spot).
	if ((facing != UNIT_NO_FACING) && clearsBuilder(pos)
		&& map->IsPossibleToBuildAt(buildDef->GetDef(), pos, facing)
		&& !exitTerrain->ZoneRefuses(buildDef, pos, facing)   // held ground (apex zones)
		&& !exitTerrain->FootprintOnSpot(buildDef, pos, facing) && exitOpen(pos) && leadsOut(pos)) {
		circuit->LOG("apex: fac-site-taken t=%i %s asked=%.0f,%.0f fails=%i at=%.0f,%.0f facing=%i",
				circuit->GetTeamId(), buildDef->GetDef()->GetName(), position.x, position.z, buildFails, pos.x, pos.z, facing);
		SetBuildPos(pos);
		return true;
	}
	if ((facing != UNIT_NO_FACING) && (selfBar > 0.f)) {
		circuit->LOG("apex: fac-site-moved t=%i %s asked=%.0f,%.0f fails=%i at=%.0f,%.0f facing=%i clears=%i possible=%i spot=%i lane=%i exit=%i others=%i",
				circuit->GetTeamId(), buildDef->GetDef()->GetName(), position.x, position.z, buildFails, pos.x, pos.z, facing,
				clearsBuilder(pos) ? 1 : 0, map->IsPossibleToBuildAt(buildDef->GetDef(), pos, facing) ? 1 : 0,
				exitTerrain->FootprintOnSpot(buildDef, pos, facing) ? 1 : 0, laneClear(pos) ? 1 : 0,
				exitTerrain->FactoryExitOpen(buildDef, pos, facing) ? 1 : 0, othersClear(pos) ? 1 : 0);
	}

	FindFacing(pos);

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CTerrainManager::TerrainPredicate predicate;
	if (reprDef == nullptr) {
		predicate = [terrainMgr, builder, clearsBuilder, &exitOpen](const AIFloat3& p) {
			return clearsBuilder(p)
					&& terrainMgr->CanReachAtSafe(builder, p, builder->GetCircuitDef()->GetBuildDistance())
					&& exitOpen(p);
		};
	} else {
		CCircuitDef* reprDef = this->reprDef;
		predicate = [terrainMgr, builder, reprDef, clearsBuilder, &exitOpen](const AIFloat3& p) {
			return clearsBuilder(p)
					&& terrainMgr->CanReachAtSafe(builder, p, builder->GetCircuitDef()->GetBuildDistance())
					&& terrainMgr->CanBeBuiltAt(reprDef, p)
					&& exitOpen(p);
		};
	}
	const float testSize = std::max(buildDef->GetDef()->GetXSize(), buildDef->GetDef()->GetZSize()) * SQUARE_SIZE;
	auto checkFacing = [this, map, terrainMgr, testSize, &predicate, &pos, searchRadius, &exitOpen, &leadsOut]() {
		AIFloat3 bp = terrainMgr->FindBuildSite(buildDef, pos, searchRadius, facing, predicate);
		if (!utils::is_valid(bp)) {
			return false;
		}

		// decides if a factory should face the opposite direction due to bad terrain
		AIFloat3 posOffset = bp;
		switch (facing) {
			default:
			case UNIT_FACING_SOUTH: {  // z++
				posOffset.z += testSize;
			} break;
			case UNIT_FACING_EAST: {  // x++
				posOffset.x += testSize;
			} break;
			case UNIT_FACING_NORTH: {  // z--
				posOffset.z -= testSize;
			} break;
			case UNIT_FACING_WEST: {  // x--
				posOffset.x -= testSize;
			} break;
		}
		if (map->IsPossibleToBuildAt(buildDef->GetDef(), posOffset, facing) && exitOpen(bp) && leadsOut(bp)) {
			SetBuildPos(bp);
			return true;
		}
		return false;
	};

	if (checkFacing()) {
		return true;
	}
	facing = opposite[facing];
	if (checkFacing()) {
		return true;
	}
	++facing %= 4;
	if (checkFacing()) {
		return true;
	}
	facing = opposite[facing];
	if (checkFacing()) {
		return true;
	}

	// All four facings failed: there is genuinely nowhere here to put this.
	// Only reported for LARGE footprints -- an ordinary lab failing to place is
	// usually a bad search origin, whereas a gantry-sized building failing is
	// what a base packed with old T1 clutter looks like. The script decides
	// whether anything nearby is worth clearing; see CCircuitAI::NoteBuildBlocked.
	// Not while we are only holding ground clear for our own builder: that pass
	// falls through to the relaxed one, which reports for it.
	if ((selfBar <= 0.f) && (testSize >= SQUARE_SIZE * 8)) {
		circuit->NoteBuildBlocked(pos, buildDef);
	}
	return false;
}

#define SERIALIZE(stream, func)	\
	utils::binary_##func(stream, reprDefId);		\
	utils::binary_##func(stream, isPlop);

bool CBFactoryTask::Load(std::istream& is)
{
	CCircuitDef::Id reprDefId;

	IBuilderTask::Load(is);
	SERIALIZE(is, read)

	CCircuitAI* circuit = manager->GetCircuit();
	reprDef = circuit->GetCircuitDefSafe(reprDefId);

	circuit->GetFactoryManager()->AddFactory(buildDef);
	Activate();  // circuit->GetFactoryManager()->ApplySwitchFrame();
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | reprDefId=%i | isPlop=%i | lastTouched=%i", __PRETTY_FUNCTION__, reprDefId, isPlop, lastTouched);
#endif
	return true;
}

void CBFactoryTask::Save(std::ostream& os) const
{
	CCircuitDef::Id reprDefId = (reprDef != nullptr) ? reprDef->GetId() : -1;

	IBuilderTask::Save(os);
	SERIALIZE(os, write)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | reprDefId=%i | isPlop=%i", __PRETTY_FUNCTION__, reprDefId, isPlop);
#endif
}

} // namespace circuit
