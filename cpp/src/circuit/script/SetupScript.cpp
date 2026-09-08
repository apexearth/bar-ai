/*
 * SetupScript.cpp
 *
 *  Created on: Jan 18, 2025
 *      Author: rlcevg
 */

#include "script/SetupScript.h"
#include "script/ScriptManager.h"
#include "setup/SetupManager.h"

#include "angelscript/add_on/scriptdictionary/scriptdictionary.h"

namespace circuit {

CSetupScript::CSetupScript(CScriptManager* scr, CSetupManager* mgr)
		: IScript(scr)
		, manager(mgr)
{
}

CSetupScript::~CSetupScript()
{
}

CScriptDictionary* CSetupScript::GetModOptions()
{
	/*
	 * dictionary@ mo = aiSetupMgr.GetModOptions();
	 * if (mo.exists("chicken_queendifficulty"))
	 *     AiLog(string(mo["chicken_queendifficulty"]));
	 */
	CScriptDictionary* dict = CScriptDictionary::Create(script->GetEngine());
	int typeId = script->GetEngine()->GetTypeIdByDecl("string");
	const CSetupData::ModOptions& modoptions = manager->GetModOptions();
	for (const auto& kv : modoptions) {
		dict->Set(kv.first, (void*)&kv.second, typeId);
	}
	// Not holding reference to dict and no auto-handles, so
	// dict->Release() is in script's scope.
	return dict;
}

} /* namespace circuit */
