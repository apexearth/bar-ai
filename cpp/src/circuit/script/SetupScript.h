/*
 * SetupScript.h
 *
 *  Created on: Jan 18, 2025
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SCRIPT_SETUPSCRIPT_H_
#define SRC_CIRCUIT_SCRIPT_SETUPSCRIPT_H_

#include "script/Script.h"

class CScriptDictionary;

namespace circuit {

class CSetupManager;

class CSetupScript: public IScript {
public:
	CSetupScript(CScriptManager* scr, CSetupManager* mgr);
	virtual ~CSetupScript();

	virtual bool Init() override { return true; }

	CScriptDictionary* GetModOptions();

private:
	CSetupManager* manager;
};

} /* namespace circuit */

#endif /* SRC_CIRCUIT_SCRIPT_SETUPSCRIPT_H_ */
