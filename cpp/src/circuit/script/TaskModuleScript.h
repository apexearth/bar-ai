/*
 * TaskModuleScript.h
 *
 *  Created on: Jan 2, 2021
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SCRIPT_TASKMODULESCRIPT_H_
#define SRC_CIRCUIT_SCRIPT_TASKMODULESCRIPT_H_

#include "script/ModuleScript.h"

#include <cstdint>

class asIScriptModule;
class asIScriptFunction;

namespace circuit {

class ITaskModule;
class IUnitTask;
class CCircuitUnit;

class ITaskModuleScript: public IModuleScript {
public:
	ITaskModuleScript(CScriptManager* scr, ITaskModule* mod);
	virtual ~ITaskModuleScript();

protected:
	void InitModule(asIScriptModule* mod);

public:
	IUnitTask* MakeTask(CCircuitUnit* unit);
	void TaskAdded(IUnitTask* task);
	void TaskRemoved(IUnitTask* task, bool done);

protected:
	struct SScriptInfo {
		asIScriptFunction* makeTask = nullptr;
		asIScriptFunction* taskAdded = nullptr;
		asIScriptFunction* taskRemoved = nullptr;
	} umInfo;

	// apex: script-time accounting for AiMakeTask -- the host runs every AI's
	// script, and "it makes me lag" needs a number before an optimization.
	uint64_t perfUs = 0;
	unsigned perfCalls = 0;
	int perfNextLog = 0;
};

} // namespace circuit

#endif // SRC_CIRCUIT_SCRIPT_TASKMODULESCRIPT_H_
