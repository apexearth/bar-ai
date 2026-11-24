/*
 * ScriptManager.h
 *
 *  Created on: Apr 3, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SETUP_SCRIPTMANAGER_H_
#define SRC_CIRCUIT_SETUP_SCRIPTMANAGER_H_

#include "System/Threading/SpringThreading.h"

#include <vector>
#include <string>
#include <unordered_map>
#include <cstdint>

class asIScriptEngine;
class asIScriptModule;
class asIScriptFunction;
class asIScriptContext;
class asSMessageInfo;
class asCJITCompiler;

namespace circuit {

class CCircuitAI;
#ifdef DEBUG_VIS
class IScript;
#endif

class CScriptManager {
public:
	static std::string initName;
	static std::string mainName;

	CScriptManager(CCircuitAI* circuit);
	virtual ~CScriptManager();

private:
	void Init();
	void Release();
public:
	bool Load(const char* modname, const std::string& subdir, const std::string& filename);
	asIScriptEngine* GetEngine() const { return engine; }
	asIScriptFunction* GetFunc(asIScriptModule* mod, const char* decl);
	asIScriptContext* RequestContext();  // thread
	asIScriptContext* PrepareContext(asIScriptFunction* func);
	void ReturnContext(asIScriptContext* ctx);
	void ReleaseContext(asIScriptContext* ctx);
	bool Exec(asIScriptContext* ctx);

private:
	CCircuitAI* circuit;
	asIScriptEngine* engine;
	// Our pool of script contexts. This is used to avoid allocating
	// the context objects all the time. The context objects are quite
	// heavy weight and should be shared between function calls.
	std::vector<asIScriptContext*> contexts;
	asCJITCompiler* jit;
	spring::mutex mtx;

	static asIScriptContext* ProvideContext(asIScriptEngine*, void*);
	static void StoreContext(asIScriptEngine*, asIScriptContext*, void*);

	void MessageCallback(const asSMessageInfo *msg, void *param);

	// apex_asprof=K: one Exec in K runs under a line callback that charges each script line its own
	// wall time (self), and every function on the stack the same time once (inclusive). Dumped as
	// "apex: asprof" lines once a game-minute; tools/asprof.py reads them. Off (0) costs one branch.
	struct ProfAcc { uint64_t ns = 0; uint64_t hits = 0; };
	struct ProfRun { int64_t lastNs = 0; asIScriptFunction* fn = nullptr; int line = 0; const char* sec = nullptr;
			std::vector<asIScriptFunction*> stack; };
	// The garbage collector is ours from the first frame (GcAfterExec). Script classes have no destructors, so
	// when garbage is freed is invisible to the script.
	bool gcOwn = false;
	int execDepth = 0;
	unsigned gcPre = 0;
	unsigned gcPendingNew = 0;
	int gcLastFrame = -1;
	int gcIdleFrame = -1;
	uint64_t gcNs = 0, gcMaxNs = 0, gcSteps = 0, gcCalls = 0, execCalls = 0;
	int miscNextDump = 0;
	void SetupFromTunables();
	void GcAfterExec();
	void GcDump();
	int profK = -1;
	bool profActive = false;
	spring::mutex profMtx;
	std::vector<asIScriptContext*> profCtxStack;
	unsigned profTick = 0;
	int profNextDump = 0;
	int profDepth = 0;
	std::unordered_map<asIScriptContext*, ProfRun> profRun;
	std::unordered_map<uint64_t, ProfAcc> profLine;   // (fn id << 20) | line
	std::unordered_map<asIScriptFunction*, ProfAcc> profSelf;
	std::unordered_map<asIScriptFunction*, ProfAcc> profIncl;
	std::unordered_map<uint64_t, std::pair<asIScriptFunction*, const char*>> profLineOf;
	uint64_t profTotalNs = 0;
	uint64_t profExecs = 0;
	static void ProfLineCb(asIScriptContext* ctx, void* param);
	void ProfCharge(asIScriptContext* ctx, int64_t now);
	void ProfDump();

#ifdef DEBUG_VIS
public:
	void AddScript(IScript* scr) { scripts.push_back(scr); }
	void Reload();

private:
	std::vector<IScript*> scripts;
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_SETUP_SCRIPTMANAGER_H_
