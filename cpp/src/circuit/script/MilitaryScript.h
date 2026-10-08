/*
 * MilitaryScript.h
 *
 *  Created on: Apr 4, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SCRIPT_MILITARYSCRIPT_H_
#define SRC_CIRCUIT_SCRIPT_MILITARYSCRIPT_H_

#include "script/TaskModuleScript.h"

namespace springai {
	class AIFloat3;
}

namespace circuit {

class CMilitaryManager;

class CMilitaryScript: public ITaskModuleScript {
public:
	CMilitaryScript(CScriptManager* scr, CMilitaryManager* mgr);
	virtual ~CMilitaryScript();

	virtual bool Init() override;

public:
	void MakeDefence(int cluster, const springai::AIFloat3& pos);
	bool JoinFight(const springai::AIFloat3& at, float travelS, float allyPow, float foePow, float ownPow, int leaderId);

private:
	struct SScriptInfo {
		asIScriptFunction* makeDefence = nullptr;
		asIScriptFunction* joinFight = nullptr;
	} militaryInfo;
};

} // namespace circuit

#endif // SRC_CIRCUIT_SCRIPT_MILITARYSCRIPT_H_
