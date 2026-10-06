/*
 * BuilderScript.cpp
 *
 *  Created on: Apr 4, 2019
 *      Author: rlcevg
 */

#include "script/BuilderScript.h"
#include "script/ScriptManager.h"
#include "module/BuilderManager.h"
#include "resource/MetalManager.h"
#include "terrain/TerrainManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"
#include "angelscript/include/angelscript.h"

namespace circuit {

using namespace springai;

static void ConstructSResourceVal(SResource* mem, float m, float e)
{
	new(mem) SResource{m, e};
}

// apex: order a mex upgrade from script.
//
// apexearth: "it seems weird that we cannot control telling one of our advanced
// construction bots to upgrade a mex. I as a player can do that, so the AI must
// have that same capability." It always could -- CEconomyManager does exactly
// this internally -- there was simply no binding, so no rule of ours could ask.
// A MEXUP task carries a metal-spot INDEX as well as a position, which is why
// the generic SBuildTask path cannot express it.
//
// Returns null when there is no spot near `pos`, when an upgrade is already in
// flight there, or when `def` cannot be built on it.
static IUnitTask* CBuilderManager_EnqueueMexUp(CBuilderManager* mgr, const AIFloat3& pos, CCircuitDef* def)
{
	if (def == nullptr) {
		return nullptr;
	}
	CCircuitAI* circuit = mgr->GetCircuit();
	CMetalManager* metalMgr = circuit->GetMetalManager();
	const int index = metalMgr->FindNearestSpot(pos);
	if (index < 0) {
		return nullptr;
	}
	const CMetalData::Metals& spots = metalMgr->GetSpots();
	const AIFloat3& spotPos = spots[index].position;
	if (!circuit->GetTerrainManager()->CanBeBuiltAt(def, spotPos)) {
		return nullptr;
	}
	return mgr->Enqueue(TaskB::Spot(IBuilderTask::BuildType::MEXUP,
			IBuilderTask::Priority::HIGH, def, spotPos, index));
}

CBuilderScript::CBuilderScript(CScriptManager* scr, CBuilderManager* mgr)


		: ITaskModuleScript(scr, mgr)
{
	asIScriptEngine* engine = script->GetEngine();

	int r = engine->RegisterObjectType("SResource", sizeof(SResource), asOBJ_VALUE | asOBJ_POD | asGetTypeTraits<SResource>()); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SResource", asBEHAVE_CONSTRUCT, "void f(float, float)", asFUNCTION(ConstructSResourceVal), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SResource", "float metal", asOFFSET(SResource, metal)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SResource", "float energy", asOFFSET(SResource, energy)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("SBuildTask", sizeof(TaskB::SBuildTask), asOBJ_VALUE | asOBJ_POD); ASSERT(r >= 0);
	static_assert(sizeof(TaskB::SBuildTask::type) == sizeof(char), "IBuilderTask::BuildType is not uint8!");
	r = engine->RegisterObjectProperty("SBuildTask", "uint8 type", asOFFSET(TaskB::SBuildTask, type)); ASSERT(r >= 0);  // Task::BuildType
	static_assert(sizeof(TaskB::SBuildTask::priority) == sizeof(char), "IBuilderTask::Priority is not uint8!");
	r = engine->RegisterObjectProperty("SBuildTask", "uint8 priority", asOFFSET(TaskB::SBuildTask, priority)); ASSERT(r >= 0);  // Task::Priority
	r = engine->RegisterObjectProperty("SBuildTask", "CCircuitDef@ buildDef", asOFFSET(TaskB::SBuildTask, buildDef)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "AIFloat3 position", asOFFSET(TaskB::SBuildTask, position)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "SResource cost", asOFFSET(TaskB::SBuildTask, cost)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "CCircuitDef@ reprDef", asOFFSET(TaskB::SBuildTask, ref.reprDef)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "CCircuitUnit@ target", asOFFSET(TaskB::SBuildTask, ref.target)); ASSERT(r >= 0);
//	r = engine->RegisterObjectProperty("SBuildTask", "IGridLink@ link", asOFFSET(TaskB::SBuildTask, ref.link)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "int pointId", asOFFSET(TaskB::SBuildTask, i.pointId)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "int spotId", asOFFSET(TaskB::SBuildTask, i.spotId)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "float shake", asOFFSET(TaskB::SBuildTask, f.shake)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "float radius", asOFFSET(TaskB::SBuildTask, f.radius)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "bool isPlop", asOFFSET(TaskB::SBuildTask, b.isPlop)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "bool isMetal", asOFFSET(TaskB::SBuildTask, b.isMetal)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "bool isActive", asOFFSET(TaskB::SBuildTask, isActive)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "int timeout", asOFFSET(TaskB::SBuildTask, timeout)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("SServBTask", sizeof(TaskB::SServBTask), asOBJ_VALUE | asOBJ_POD); ASSERT(r >= 0);
	static_assert(sizeof(TaskB::SServBTask::type) == sizeof(char), "IBuilderTask::BuildType is not uint8!");
	r = engine->RegisterObjectProperty("SServBTask", "uint8 type", asOFFSET(TaskB::SServBTask, type)); ASSERT(r >= 0);  // Task::BuildType
	static_assert(sizeof(TaskB::SServBTask::priority) == sizeof(char), "IBuilderTask::Priority is not uint8!");
	r = engine->RegisterObjectProperty("SServBTask", "uint8 priority", asOFFSET(TaskB::SServBTask, priority)); ASSERT(r >= 0);  // Task::Priority
	r = engine->RegisterObjectProperty("SServBTask", "AIFloat3 position", asOFFSET(TaskB::SServBTask, position)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "CCircuitUnit@ target", asOFFSET(TaskB::SServBTask, target)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "float powerMod", asOFFSET(TaskB::SServBTask, powerMod)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "bool isInterrupt", asOFFSET(TaskB::SServBTask, isInterrupt)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "bool isMove", asOFFSET(TaskB::SServBTask, isMove)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "int timeout", asOFFSET(TaskB::SServBTask, timeout)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("CBuilderManager", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CBuilderManager aiBuilderMgr", manager); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ DefaultMakeTask(CCircuitUnit@)", asMETHOD(CBuilderManager, DefaultMakeTask), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ Enqueue(const SBuildTask& in)", asMETHODPR(CBuilderManager, Enqueue, (const TaskB::SBuildTask&), IBuilderTask*), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ Enqueue(const SServBTask& in)", asMETHODPR(CBuilderManager, Enqueue, (const TaskB::SServBTask&), IUnitTask*), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ EnqueueRetreat()", asMETHOD(CBuilderManager, EnqueueRetreat), asCALL_THISCALL); ASSERT(r >= 0);
	// apex: force-assign a just-created task to a specific unit instead of
	// waiting for the engine's own idle callback to pick it up. Added for the
	// commander noTask watchdog (events.as CommIdleAttribute) -- a commander
	// under sustained influence was measured sampling literally no task
	// (Task::Type::NIL/IDLE) for the majority of ticks in a danger window,
	// because CRetreatTask is not an IBuilderTask and so never gets the
	// periodic ~1s Reevaluate() every builder task receives; nothing proactively
	// re-tasks it once it goes idle except the engine's own AiUnitIdle
	// callback, which this measurement shows is not prompt enough under
	// sustained threat.
	// @+ on the task: the VM passes handle params with +1 that the callee must
	// release; the native AssignTask never does, so plain @ leaked a reference
	// per call. Auto-handle makes the engine drop the +1 after the call.
	r = engine->RegisterObjectMethod("CBuilderManager", "void AssignTask(CCircuitUnit@, IUnitTask@+)", asMETHODPR(CBuilderManager, AssignTask, (CCircuitUnit*, IUnitTask*), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ EnqueueMexUp(const AIFloat3& in, CCircuitDef@)", asFUNCTION(CBuilderManager_EnqueueMexUp), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "uint GetWorkerCount() const", asMETHOD(CBuilderManager, GetWorkerCount), asCALL_THISCALL); ASSERT(r >= 0);
	// apex: see BuilderManager.h -- lets script report the task budget that gates
	// mex creation, instead of inferring it.
	r = engine->RegisterObjectMethod("CBuilderManager", "uint GetBuildTaskCount() const", asMETHOD(CBuilderManager, GetBuildTaskCount), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "bool CanEnqueueTask(uint) const", asMETHOD(CBuilderManager, CanEnqueueTask), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "uint GetTaskCountOf(int) const", asMETHOD(CBuilderManager, GetTaskCountOf), asCALL_THISCALL); ASSERT(r >= 0);
}

CBuilderScript::~CBuilderScript()
{
}

bool CBuilderScript::Init()
{
	asIScriptModule* mod = script->GetEngine()->GetModule(CScriptManager::mainName.c_str());
	int r = mod->SetDefaultNamespace("Builder"); ASSERT(r >= 0);
	InitModule(mod);
	builderInfo.taskAssigned = script->GetFunc(mod, "void AiTaskAssigned(CCircuitUnit@)");
	return true;
}

void CBuilderScript::TaskAssigned(CCircuitUnit* unit)
{
	if (builderInfo.taskAssigned == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(builderInfo.taskAssigned);
	ctx->SetArgObject(0, unit);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

} // namespace circuit
