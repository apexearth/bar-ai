/*
 * FactoryTask.cpp
 *
 *  Created on: Jan 30, 2015
 *      Author: rlcevg
 */

#include "task/builder/FactoryTask.h"
#include "module/BuilderManager.h"
#include "module/FactoryManager.h"
#include "scheduler/Scheduler.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

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
	CMap* map = circuit->GetMap();
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
	if ((facing != UNIT_NO_FACING) && clearsBuilder(pos)
		&& map->IsPossibleToBuildAt(buildDef->GetDef(), pos, facing)) {
		SetBuildPos(pos);
		return true;
	}

	FindFacing(pos);

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CTerrainManager::TerrainPredicate predicate;
	if (reprDef == nullptr) {
		predicate = [terrainMgr, builder, clearsBuilder](const AIFloat3& p) {
			return clearsBuilder(p)
					&& terrainMgr->CanReachAtSafe(builder, p, builder->GetCircuitDef()->GetBuildDistance());
		};
	} else {
		CCircuitDef* reprDef = this->reprDef;
		predicate = [terrainMgr, builder, reprDef, clearsBuilder](const AIFloat3& p) {
			return clearsBuilder(p)
					&& terrainMgr->CanReachAtSafe(builder, p, builder->GetCircuitDef()->GetBuildDistance())
					&& terrainMgr->CanBeBuiltAt(reprDef, p);
		};
	}
	const float testSize = std::max(buildDef->GetDef()->GetXSize(), buildDef->GetDef()->GetZSize()) * SQUARE_SIZE;
	auto checkFacing = [this, map, terrainMgr, testSize, &predicate, &pos, searchRadius]() {
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
		if (map->IsPossibleToBuildAt(buildDef->GetDef(), posOffset, facing)) {
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
		circuit->NoteBuildBlocked(pos);
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
