/*
 * TaskModuleScript.cpp
 *
 *  Created on: Jan 2, 2021
 *      Author: rlcevg
 */

#include "script/TaskModuleScript.h"
#include "script/ScriptManager.h"
#include "module/TaskModule.h"
#include "util/Utils.h"
#include "CircuitAI.h"
#include "angelscript/include/angelscript.h"

#include "Log.h"           // springai::Log, completes the LOG macro's type

#include <chrono>

namespace circuit {

ITaskModuleScript::ITaskModuleScript(CScriptManager* scr, ITaskModule* mod)
		: IModuleScript(scr, mod)
{
}

ITaskModuleScript::~ITaskModuleScript()
{
}

void ITaskModuleScript::InitModule(asIScriptModule* mod)
{
	IModuleScript::InitModule(mod);
	umInfo.makeTask = script->GetFunc(mod, "IUnitTask@ AiMakeTask(CCircuitUnit@)");
	umInfo.taskAdded = script->GetFunc(mod, "void AiTaskAdded(IUnitTask@)");
	umInfo.taskRemoved = script->GetFunc(mod, "void AiTaskRemoved(IUnitTask@, bool)");
}

IUnitTask* ITaskModuleScript::MakeTask(CCircuitUnit* unit)
{
	if (umInfo.makeTask == nullptr) {
		return static_cast<ITaskModule*>(manager)->DefaultMakeTask(unit);
	}
	// apex: time every AiMakeTask election. Two instances log under the same
	// label (builder and factory); the builder is the one with thousands of
	// calls a minute.
	const auto t0 = std::chrono::steady_clock::now();
	asIScriptContext* ctx = script->PrepareContext(umInfo.makeTask);
	ctx->SetArgObject(0, unit);
	IUnitTask* result = script->Exec(ctx) ? (IUnitTask*)ctx->GetReturnObject() : nullptr;
	script->ReturnContext(ctx);
	perfUs += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t0).count();
	++perfCalls;
	CCircuitAI* circuit = static_cast<ITaskModule*>(manager)->GetCircuit();
	const int frame = circuit->GetLastFrame();
	if (frame >= perfNextLog) {
		perfNextLog = frame + 1800;   // one game-minute at 30 fps
		circuit->LOG("apex: perf AiMakeTask calls=%u totalMs=%.1f avgUs=%.0f",
				perfCalls, perfUs / 1000.f,
				(perfCalls > 0) ? float(perfUs) / float(perfCalls) : 0.f);
		perfUs = 0;
		perfCalls = 0;
	}
	return result;
}

void ITaskModuleScript::TaskAdded(IUnitTask* task)
{
	if (umInfo.taskAdded == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(umInfo.taskAdded);
	ctx->SetArgObject(0, task);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

void ITaskModuleScript::TaskRemoved(IUnitTask* task, bool done)
{
	if (umInfo.taskRemoved == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(umInfo.taskRemoved);
	ctx->SetArgObject(0, task);
	ctx->SetArgByte(1, done);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

} // namespace circuit
