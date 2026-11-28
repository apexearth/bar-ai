/*
 * ScriptManager.cpp
 *
 *  Created on: Apr 3, 2019
 *      Author: rlcevg
 */

#include <mutex>
#include <chrono>
#include <algorithm>
#include "script/ScriptManager.h"
#ifdef DEBUG_VIS
#include "script/Script.h"
#endif
#include "CircuitAI.h"
#include "util/FileSystem.h"
#include "util/Utils.h"
#include "util/Profiler.h"

#include "Log.h"
#include "OptionValues.h"

//#define AS_USE_STLNAMES		1

#include "angelscript/include/angelscript.h"
#include "angelscript/jit/as_jit.h"
#include "angelscript/add_on/scriptstdstring/scriptstdstring.h"
#include "angelscript/add_on/scriptarray/scriptarray.h"
#include "angelscript/add_on/scriptdictionary/scriptdictionary.h"
#include "angelscript/add_on/scriptmath/scriptmath.h"
#include "angelscript/add_on/scriptbuilder/scriptbuilder.h"
#include "angelscript/add_on/aatc/aatc.hpp"

namespace circuit {

using namespace springai;

std::string CScriptManager::initName("init");
std::string CScriptManager::mainName("main");

CScriptManager::CScriptManager(CCircuitAI* circuit)
		: circuit(circuit)
		, engine(nullptr)
		, jit(nullptr)
{
	Init();
}

CScriptManager::~CScriptManager()
{
	Release();
}

void CScriptManager::Init()
{
	// apex: AngelScript's documented contract (as_thread.cpp): call
	// asPrepareMultithread() before any other thread creates a script engine,
	// or the shared thread manager's unguarded first-AddRef races. Multiple AI
	// instances create engines on their own threads inside this one DLL; a 1v1
	// elimination could destroy the manager the surviving instance was locking
	// (2026-08-18 commander-blast crash). Once per process, never unprepared.
	static std::once_flag prepareThreads;
	std::call_once(prepareThreads, []() { asPrepareMultithread(); });
	// Create the script engine
	engine = asCreateScriptEngine(ANGELSCRIPT_VERSION);
	// Set the message callback to receive information on errors in human readable form.
	int r = engine->SetMessageCallback(asMETHOD(CScriptManager, MessageCallback), this, asCALL_THISCALL); ASSERT(r >= 0);

	r = engine->SetEngineProperty(asEP_ALLOW_UNSAFE_REFERENCES,            false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_OPTIMIZE_BYTECODE,                   true); ASSERT(r >= 0);  // Default: true
	r = engine->SetEngineProperty(asEP_COPY_SCRIPT_SECTIONS,                true); ASSERT(r >= 0);  // Default: true
	r = engine->SetEngineProperty(asEP_MAX_STACK_SIZE,                         0); ASSERT(r >= 0);  // Default: 0 (no limit)
	r = engine->SetEngineProperty(asEP_USE_CHARACTER_LITERALS,             false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_ALLOW_MULTILINE_STRINGS,             true); ASSERT(r >= 0);  //** Default: false
	r = engine->SetEngineProperty(asEP_ALLOW_IMPLICIT_HANDLE_TYPES,        false); ASSERT(r >= 0);  // Default: false
	{
		// A line cue is a SUSPEND before every statement: nothing here suspends a script, and the line table that
		// names an exception's line is built either way. Only the line callback (apex_asprof) needs them.
		const bool cues = circuit->GetTunable("apex_asprof", 0.f) > 0.f;
		r = engine->SetEngineProperty(asEP_BUILD_WITHOUT_LINE_CUES, !cues); ASSERT(r >= 0);  // Default: false
	}
	r = engine->SetEngineProperty(asEP_INIT_GLOBAL_VARS_AFTER_BUILD,        true); ASSERT(r >= 0);  // Default: true
	r = engine->SetEngineProperty(asEP_REQUIRE_ENUM_SCOPE,                 false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_SCRIPT_SCANNER,                         1); ASSERT(r >= 0);  // Default: 1 (UTF8)  // 0 - ASCII, 1 - UTF8
//	r = engine->SetEngineProperty(asEP_INCLUDE_JIT_INSTRUCTIONS,           false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_STRING_ENCODING,                        0); ASSERT(r >= 0);  // Default: 0 (UTF8)  // 0 - UTF8/ASCII, 1 - UTF16
	r = engine->SetEngineProperty(asEP_PROPERTY_ACCESSOR_MODE,                 3); ASSERT(r >= 0);  // Default: 3  // 0 - no accessors, 1 - app registered accessors, 2 - app and script created accessors, 3 - app and script created accesors, property keyword required
	r = engine->SetEngineProperty(asEP_EXPAND_DEF_ARRAY_TO_TMPL,           false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_AUTO_GARBAGE_COLLECT,                true); ASSERT(r >= 0);  // Default: true
	r = engine->SetEngineProperty(asEP_DISALLOW_GLOBAL_VARS,               false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_ALWAYS_IMPL_DEFAULT_CONSTRUCT,      false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_COMPILER_WARNINGS,                      2); ASSERT(r >= 0);  //** 0 - dismiss, 1 - emit, 2 - treat as error
	r = engine->SetEngineProperty(asEP_DISALLOW_VALUE_ASSIGN_FOR_REF_TYPE, false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_ALTER_SYNTAX_NAMED_ARGS,                0); ASSERT(r >= 0);  // Default: 0  // 0 - no change, 1 - accept = but warn, 2 - accept = without warning
	r = engine->SetEngineProperty(asEP_DISABLE_INTEGER_DIVISION,           false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_DISALLOW_EMPTY_LIST_ELEMENTS,       false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_PRIVATE_PROP_AS_PROTECTED,          false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_ALLOW_UNICODE_IDENTIFIERS,          false); ASSERT(r >= 0);  // Default: false
	r = engine->SetEngineProperty(asEP_HEREDOC_TRIM_MODE,                      1); ASSERT(r >= 0);  // Default: 1  // 0 - never trim, 1 - trim if multiple lines, 2 - always trim
	r = engine->SetEngineProperty(asEP_MAX_NESTED_CALLS,                     100); ASSERT(r >= 0);  // Default: 100
	r = engine->SetEngineProperty(asEP_GENERIC_CALL_MODE,                      1); ASSERT(r >= 0);  // Default: 1  // 0 - ignore auto handles, 1 - treat them the same way as native calling convention
	r = engine->SetEngineProperty(asEP_INIT_STACK_SIZE,                     4096); ASSERT(r >= 0);  // Default: 4096
	r = engine->SetEngineProperty(asEP_INIT_CALL_STACK_SIZE,                  10); ASSERT(r >= 0);  // Default: 10
	r = engine->SetEngineProperty(asEP_MAX_CALL_STACK_SIZE,                    0); ASSERT(r >= 0);  // Default: 0 (no limit)

#ifdef CIRCUIT_AS_JIT
	// Create the JIT Compiler. The build flags are explained below,
	// as well as in as_jit.h
	//  Faster: JIT_NO_SUSPEND | JIT_SYSCALL_FPU_NORESET | JIT_SYSCALL_NO_ERRORS | JIT_ALLOC_SIMPLE | JIT_FAST_REFCOUNT
	//  Slower: JIT_NO_SWITCHES | JIT_NO_SCRIPT_CALLS
	jit = new asCJITCompiler(JIT_FAST_REFCOUNT | JIT_SYSCALL_FPU_NORESET);
	// Enable JIT helper instructions; without these,
	// the JIT will not be invoked
	r = engine->SetEngineProperty(asEP_INCLUDE_JIT_INSTRUCTIONS, true); ASSERT(r >= 0);
	// Bind the JIT compiler to the engine
	r = engine->SetJITCompiler(jit); ASSERT(r >= 0);
#endif

	// AngelScript doesn't have a built-in string type, as there is no definite standard
	// string type for C++ applications. Every developer is free to register its own string type.
	// The SDK do however provide a standard add-on for registering a string type, so it's not
	// necessary to implement the registration yourself if you don't want to.
	RegisterStdString(engine);
	RegisterScriptArray(engine, true);
	RegisterStdStringUtils(engine);  // optional
	RegisterScriptDictionary(engine);
	RegisterScriptMath(engine);
	aatc::RegisterAllContainers(engine);

	engine->SetContextCallbacks(CScriptManager::ProvideContext, CScriptManager::StoreContext, this);
}

void CScriptManager::Release()
{
	// Clean up
	for (asIScriptContext* context : contexts) {
		context->Release();
	}
	contexts.clear();
	engine->ShutDownAndRelease();
	delete jit;
}

bool CScriptManager::Load(const char* modname, const std::string& subdir, const std::string& filename)
{
	// The CScriptBuilder helper is an add-on that loads the file,
	// performs a pre-processing pass if necessary, and then tells
	// the engine to build a script module.
	CScriptBuilder builder;
	int r = builder.StartNewModule(engine, modname);
	if (r < 0) {
		// If the code fails here it is usually because there
		// is no more memory to allocate the module
		circuit->LOG("Script: Unrecoverable error while starting a new module!");
		return false;
	}

	std::string dirname;
	OptionValues* options = circuit->GetSkirmishAI()->GetOptionValues();
	const char* value = options->GetValueByKey("game_config");
	delete options;
	// Absent from the lobby (AIOptions.lua dropped it 11-18): our game-side files, the only ones that run this AI.
	bool isGameCfg = (value == nullptr) || StringToBool(value);
	if (isGameCfg) {
		dirname = utils::GetAIDataGameDir(circuit->GetSkirmishAI(), "script") + subdir + SLASH;
		isGameCfg = utils::FileExists(circuit->GetCallback(), dirname + filename);  // Locate game-side script
		if (isGameCfg) {
			builder.SetReadFunc([this](const std::string& filename) {
				return utils::ReadFile(circuit->GetCallback(), filename);
			});
		} else {
			circuit->LOG("Game-side script: '%s' is missing!", (dirname + filename).c_str());
		}
	}
	if (!isGameCfg) {
		dirname = "script" SLASH + subdir + SLASH;
		if (!utils::LocatePath(circuit->GetCallback(), dirname)) {  // Locate AI script
			circuit->LOG("AI script: '%s' is missing!", (dirname + filename).c_str());
			return false;
		}
	}

	circuit->LOG_ENGINE("Load script: %s", (dirname + filename).c_str());
	r = builder.AddSectionFromFile((dirname + filename).c_str());
	if (r < 0) {
		// The builder wasn't able to load the string. Maybe some
		// preprocessing commands are incorrectly written.
		circuit->LOG("Script: Unable to add section!");
		return false;
	}
	r = builder.BuildModule();
	if (r < 0) {
		// An error occurred. Instruct the script writer to fix the
		// compilation errors that were listed in the output stream.
		circuit->LOG("Script: Fix compilation errors!");
		return false;
	}
	return true;
}

asIScriptFunction* CScriptManager::GetFunc(asIScriptModule* mod, const char* decl)
{
	// Find the function that is to be called.
	asIScriptFunction* func = mod->GetFunctionByDecl(decl);
	if (func == nullptr) {
		// The function couldn't be found. Instruct the script writer
		// to include the expected function in the script.
		circuit->LOG("Script: '%s' not found!", decl);
	}
	return func;
}

asIScriptContext* CScriptManager::RequestContext()
{
	return engine->RequestContext();
}

asIScriptContext* CScriptManager::PrepareContext(asIScriptFunction* func)
{
	asIScriptContext* ctx = engine->RequestContext();
	int r = ctx->Prepare(func); ASSERT(r >= 0);
	return ctx;
}

void CScriptManager::ReturnContext(asIScriptContext* ctx)
{
//	ctx->Unprepare();
	engine->ReturnContext(ctx);
}

void CScriptManager::ReleaseContext(asIScriptContext* ctx)
{
	ctx->Release();
}

bool CScriptManager::Exec(asIScriptContext* ctx)
{
#ifdef CIRCUIT_PROFILING
	ZoneScoped;
	std::string nameFunc;
	nameFunc.reserve(256);
	nameFunc.append("AS ").append(ctx->GetFunction()->GetNamespace()).append("::").append(ctx->GetFunction()->GetName());
	ZoneName(nameFunc.c_str(), nameFunc.size());
	ZoneValue(ctx->GetFunction()->GetId());
#endif

	if ((profK < 0) && (circuit->GetLastFrame() > 0)) {
		SetupFromTunables();
	}
	if (gcOwn && (execDepth++ == 0)) {
		engine->GetGCStatistics(&gcPre);
		if (circuit->GetLastFrame() >= miscNextDump) {
			if (miscNextDump > 0) {
				GcDump();
			}
			miscNextDump = circuit->GetLastFrame() + 1800;
		}
	}
	bool profThis = false;
	if (profK > 0) {
		std::lock_guard<spring::mutex> plock(profMtx);
		if (profDepth == 0) {
			if (circuit->GetLastFrame() >= profNextDump) {
				if (profNextDump > 0) {
					ProfDump();
				}
				profNextDump = circuit->GetLastFrame() + 1800;
			}
			profActive = ((profTick++ % (unsigned)profK) == 0);
		}
		++profDepth;
		profThis = profActive;
		if (profThis) {
			const int64_t now = std::chrono::duration_cast<std::chrono::nanoseconds>(
					std::chrono::steady_clock::now().time_since_epoch()).count();
			if (!profCtxStack.empty()) {
				ProfCharge(profCtxStack.back(), now);
			}
			profCtxStack.push_back(ctx);
			ProfRun& run = profRun[ctx];
			run.fn = nullptr;
			run.stack.clear();
			run.lastNs = now;
			ctx->SetLineCallback(asFUNCTION(CScriptManager::ProfLineCb), this, asCALL_CDECL);
			++profExecs;
		} else {
			ctx->ClearLineCallback();
		}
	}

	int r = ctx->Execute();

	if (profK > 0) {
		std::lock_guard<spring::mutex> plock(profMtx);
		if (profThis) {
			const int64_t now = std::chrono::duration_cast<std::chrono::nanoseconds>(
					std::chrono::steady_clock::now().time_since_epoch()).count();
			ProfCharge(ctx, now);
			profRun[ctx].fn = nullptr;
			ctx->ClearLineCallback();
			if (!profCtxStack.empty()) {
				profCtxStack.pop_back();
			}
			if (!profCtxStack.empty()) {
				profRun[profCtxStack.back()].lastNs = now;
			}
		}
		--profDepth;
	}
	if (gcOwn && (--execDepth == 0)) {
		GcAfterExec();
	}
	if (r != asEXECUTION_FINISHED) {
		// The execution didn't complete as expected. Determine what happened.
		if (r == asEXECUTION_EXCEPTION) {
			// An exception occurred, let the script writer know what happened so it can be corrected.
			std::lock_guard<spring::mutex> mlock(mtx);
			circuit->LOG_ENGINE("Script"
						 "\n  Exception: %s"
						 "\n  Function: %s"
						 "\n  Line: %i",
						 ctx->GetExceptionString(),
						 ctx->GetExceptionFunction()->GetDeclaration(),
						 ctx->GetExceptionLineNumber());
		}
		return false;
	}
	return true;
}

void CScriptManager::SetupFromTunables()
{
	profK = std::max(0, (int)circuit->GetTunable("apex_asprof", 0.f));
	gcOwn = true;
	engine->SetEngineProperty(asEP_AUTO_GARBAGE_COLLECT, false);
	circuit->LOG("apex: asvm asprof=%d", profK);
}

// AngelScript's collector steps after every Execute even when nothing new was made (441k steps in 19 min of an 8v8
// for ~650 new objects a minute an AI, 3.3 s). Here: once a frame, the one step each new object is owed (its own
// rule), and one idle step a second. A second's steps batched into one call cost a 14 ms frame, so they are not.
void CScriptManager::GcAfterExec()
{
	++execCalls;
	asUINT cur = 0;
	engine->GetGCStatistics(&cur);
	gcPendingNew += (cur > gcPre) ? (cur - gcPre) : 0;
	const int frame = circuit->GetLastFrame();
	if (frame == gcLastFrame) {
		return;
	}
	gcLastFrame = frame;
	asUINT steps;
	if (gcPendingNew > 0) {
		steps = gcPendingNew;
	} else if ((cur > 0) && (frame - gcIdleFrame >= 30)) {
		steps = 1;
	} else {
		return;
	}
	gcIdleFrame = frame;
	gcPendingNew = 0;
	const auto t0 = std::chrono::steady_clock::now();
	engine->GarbageCollect(asGC_ONE_STEP | asGC_DESTROY_GARBAGE | asGC_DETECT_GARBAGE, steps);
	const uint64_t ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
	gcNs += ns;
	gcMaxNs = std::max(gcMaxNs, ns);
	gcSteps += steps;
	++gcCalls;
}

void CScriptManager::GcDump()
{
	asUINT size = 0, destroyed = 0, detected = 0, newObjs = 0, newDestroyed = 0;
	engine->GetGCStatistics(&size, &destroyed, &detected, &newObjs, &newDestroyed);
	circuit->LOG("apex: asgc execs=%llu gcCalls=%llu steps=%llu gcMs=%.1f maxMs=%.2f size=%u destroyed=%u detected=%u new=%u newDestroyed=%u",
			(unsigned long long)execCalls, (unsigned long long)gcCalls, (unsigned long long)gcSteps,
			gcNs / 1e6, gcMaxNs / 1e6, size, destroyed, detected, newObjs, newDestroyed);
	gcNs = gcMaxNs = gcSteps = gcCalls = execCalls = 0;
}

void CScriptManager::ProfCharge(asIScriptContext* ctx, int64_t now)
{
	ProfRun& run = profRun[ctx];
	const int64_t d = now - run.lastNs;
	run.lastNs = now;
	if ((run.fn == nullptr) || (d <= 0)) {
		return;
	}
	const uint64_t key = ((uint64_t)(uint32_t)run.fn->GetId() << 20) | (uint64_t)(run.line & 0xFFFFF);
	ProfAcc& a = profLine[key];
	if (a.hits == 0) {
		profLineOf[key] = {run.fn, run.sec};
	}
	a.ns += d;
	++a.hits;
	ProfAcc& f = profSelf[run.fn];
	f.ns += d;
	++f.hits;
	for (size_t i = 0; i < run.stack.size(); ++i) {
		asIScriptFunction* fn = run.stack[i];
		bool dup = false;
		for (size_t j = 0; j < i; ++j) {
			if (run.stack[j] == fn) {
				dup = true;
				break;
			}
		}
		if (!dup) {
			profIncl[fn].ns += d;
		}
	}
	profTotalNs += d;
}

void CScriptManager::ProfLineCb(asIScriptContext* ctx, void* param)
{
	CScriptManager* mgr = static_cast<CScriptManager*>(param);
	const int64_t now = std::chrono::duration_cast<std::chrono::nanoseconds>(
			std::chrono::steady_clock::now().time_since_epoch()).count();
	std::lock_guard<spring::mutex> plock(mgr->profMtx);
	mgr->ProfCharge(ctx, now);
	ProfRun& run = mgr->profRun[ctx];
	const char* sec = nullptr;
	run.line = ctx->GetLineNumber(0, nullptr, &sec);
	run.sec = sec;
	asIScriptFunction* top = ctx->GetFunction(0);
	if (run.fn != top) {
		// Entering a function: it was called once more.
		if ((run.stack.empty()) || (ctx->GetCallstackSize() > run.stack.size())) {
			++mgr->profIncl[top].hits;
		}
	}
	run.fn = top;
	const asUINT n = ctx->GetCallstackSize();
	run.stack.resize(n);
	for (asUINT i = 0; i < n; ++i) {
		run.stack[i] = ctx->GetFunction(i);
	}
	run.lastNs = std::chrono::duration_cast<std::chrono::nanoseconds>(
			std::chrono::steady_clock::now().time_since_epoch()).count();
}

void CScriptManager::ProfDump()
{
	auto fnName = [](asIScriptFunction* fn) {
		std::string s;
		const char* ns = fn->GetNamespace();
		if ((ns != nullptr) && (*ns != '\0')) {
			s.append(ns).append("::");
		}
		const char* obj = fn->GetObjectName();
		if ((obj != nullptr) && (*obj != '\0')) {
			s.append(obj).append(".");
		}
		s.append(fn->GetName());
		return s;
	};
	auto baseName = [](const char* p) {
		if (p == nullptr) {
			return std::string("?");
		}
		const char* b = p;
		for (const char* c = p; *c != '\0'; ++c) {
			if ((*c == '/') || (*c == '\\')) {
				b = c + 1;
			}
		}
		return std::string(b);
	};
	const int TOP = 150;   // a long tail is where a 2,000-line function hides
	circuit->LOG("apex: asprof win k=%d execs=%llu totalMs=%.1f frame=%d", profK,
			(unsigned long long)profExecs, profTotalNs / 1e6, circuit->GetLastFrame());
	{
		std::vector<std::pair<uint64_t, ProfAcc>> v(profLine.begin(), profLine.end());
		std::sort(v.begin(), v.end(), [](const auto& a, const auto& b) { return a.second.ns > b.second.ns; });
		for (int i = 0; (i < TOP) && (i < (int)v.size()); ++i) {
			const auto& of = profLineOf[v[i].first];
			circuit->LOG("apex: asprof line %.2f %llu %s:%u %s", v[i].second.ns / 1e6,
					(unsigned long long)v[i].second.hits, baseName(of.second).c_str(),
					(unsigned)(v[i].first & 0xFFFFF), fnName(of.first).c_str());
		}
	}
	for (int pass = 0; pass < 2; ++pass) {
		auto& m = (pass == 0) ? profSelf : profIncl;
		std::vector<std::pair<asIScriptFunction*, ProfAcc>> v(m.begin(), m.end());
		std::sort(v.begin(), v.end(), [](const auto& a, const auto& b) { return a.second.ns > b.second.ns; });
		for (int i = 0; (i < TOP) && (i < (int)v.size()); ++i) {
			circuit->LOG("apex: asprof %s %.2f %llu %s", (pass == 0) ? "self" : "incl", v[i].second.ns / 1e6,
					(unsigned long long)v[i].second.hits, fnName(v[i].first).c_str());
		}
	}
	profLine.clear();
	profLineOf.clear();
	profSelf.clear();
	profIncl.clear();
	profTotalNs = 0;
	profExecs = 0;
}

asIScriptContext* CScriptManager::ProvideContext(asIScriptEngine* engine, void* param)
{
	CScriptManager* mgr = static_cast<CScriptManager*>(param);

	asIScriptContext* ctx;
	if (!mgr->contexts.empty()) {
		ctx = *mgr->contexts.rbegin();
		mgr->contexts.pop_back();
	} else {
		ctx = engine->CreateContext();
	}

	return ctx;
}

void CScriptManager::StoreContext(asIScriptEngine* engine, asIScriptContext* ctx, void* param)
{
	static_cast<CScriptManager*>(param)->contexts.push_back(ctx);
}

// Implement a simple message callback function
void CScriptManager::MessageCallback(const asSMessageInfo* msg, void* param)
{
	const char* type = "ERR ";
	if (msg->type == asMSGTYPE_WARNING) {
		type = "WARN";
	} else if (msg->type == asMSGTYPE_INFORMATION) {
		type = "INFO";
	}
	circuit->LOG_ENGINE("%s (%d, %d) : %s : %s", msg->section, msg->row, msg->col, type, msg->message);
}

#ifdef DEBUG_VIS
void CScriptManager::Reload()
{
	int r = engine->DiscardModule(mainName.c_str()); ASSERT(r >= 0);
	for (IScript* scr : scripts) {
		scr->Init();
	}
}
#endif

} // namespace circuit
