/*
 * MilitaryScript.cpp
 *
 *  Created on: Apr 4, 2019
 *      Author: rlcevg
 */

#include "script/MilitaryScript.h"
#include "script/ScriptManager.h"
#include "module/MilitaryManager.h"
#include "CircuitAI.h"
#include "unit/enemy/FortCensus.h"
#include "util/Utils.h"
#include "angelscript/include/angelscript.h"

namespace circuit {

using namespace springai;

// apex_stock_army: script overrides of stock army control are dropped and counted (InitScript.cpp StockDropUnit)
static bool StockDrop(CMilitaryManager* mgr, const char* kind)
{
	CCircuitAI* circuit = mgr->GetCircuit();
	if (!circuit->IsStockArmy()) {
		return false;
	}
	circuit->NoteStockLeak(kind);
	return true;
}

// apex_our_air: the script enqueues for aircraft; a stock-controlled unit that joins one counts (FighterTask AssignTo)
static IFighterTask* CMilitaryManager_Enqueue(CMilitaryManager* mgr, const TaskF::SFightTask& ti)
{
	if (!mgr->GetCircuit()->IsOurAir()) {
		StockDrop(mgr, "enqueue");
		return mgr->Enqueue(ti);
	}
	IFighterTask* task = mgr->Enqueue(ti);
	if ((task != nullptr) && task->GetAssignees().empty()) {
		task->SetScriptMade();
	}
	return task;
}

static unsigned int CMilitaryManager_ReleaseHoldPools(CMilitaryManager* mgr)
{
	return StockDrop(mgr, "holdpools") ? 0 : mgr->ReleaseHoldPools();
}

static unsigned int CMilitaryManager_HoldPools(CMilitaryManager* mgr)
{
	return StockDrop(mgr, "holdpools") ? 0 : mgr->HoldPools();
}

static float CMilitaryManager_HoldPoolsUpTo(CMilitaryManager* mgr, float needM)
{
	return StockDrop(mgr, "holdpools") ? 0.f : mgr->HoldPoolsUpTo(needM);
}

static void CMilitaryManager_ClearSupportSpots(CMilitaryManager* mgr)
{
	if (!StockDrop(mgr, "support")) {
		mgr->ClearSupportSpots();
	}
}

static void CMilitaryManager_AddSupportSpot(CMilitaryManager* mgr, const AIFloat3& pos, float worth)
{
	if (!StockDrop(mgr, "support")) {
		mgr->AddSupportSpot(pos, worth);
	}
}

static void CMilitaryManager_SetFocus(CMilitaryManager* mgr, const AIFloat3& pos, float radius, float teamPower, bool go, int until)
{
	if (!StockDrop(mgr, "focus")) {
		mgr->SetFocus(pos, radius, teamPower, go, until);
	}
}

static void CMilitaryManager_SetFocusHome(CMilitaryManager* mgr, const AIFloat3& pos)
{
	if (!StockDrop(mgr, "focus")) {
		mgr->SetFocusHome(pos);
	}
}

static void CMilitaryManager_NoteBirthScript(CMilitaryManager* mgr, int kind)
{
	StockDrop(mgr, "birth");
	mgr->NoteBirthScript(kind);
}

CMilitaryScript::CMilitaryScript(CScriptManager* scr, CMilitaryManager* mgr)
		: ITaskModuleScript(scr, mgr)
{
	asIScriptEngine* engine = script->GetEngine();

	int r = engine->RegisterObjectType("SFightTask", sizeof(TaskF::SFightTask), asOBJ_VALUE | asOBJ_POD); ASSERT(r >= 0);
	static_assert(sizeof(TaskF::SFightTask::type) == sizeof(char), "IFighterTask::FightType is not uint8!");
	r = engine->RegisterObjectProperty("SFightTask", "uint8 type", asOFFSET(TaskF::SFightTask, type)); ASSERT(r >= 0);  // Task::FightType
	static_assert(sizeof(TaskF::SFightTask::check) == sizeof(char), "IFighterTask::FightType is not uint8!");
	r = engine->RegisterObjectProperty("SFightTask", "uint8 check", asOFFSET(TaskF::SFightTask, check)); ASSERT(r >= 0);  // Task::FightType
	static_assert(sizeof(TaskF::SFightTask::promote) == sizeof(char), "IFighterTask::FightType is not uint8!");
	r = engine->RegisterObjectProperty("SFightTask", "uint8 promote", asOFFSET(TaskF::SFightTask, promote)); ASSERT(r >= 0);  // Task::FightType
	r = engine->RegisterObjectProperty("SFightTask", "float power", asOFFSET(TaskF::SFightTask, power)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SFightTask", "CCircuitUnit@ vip", asOFFSET(TaskF::SFightTask, vip)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("CMilitaryManager", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CMilitaryManager aiMilitaryMgr", manager); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "IUnitTask@+ DefaultMakeTask(CCircuitUnit@)", asMETHOD(CMilitaryManager, DefaultMakeTask), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "IUnitTask@+ Enqueue(const SFightTask& in)", asFUNCTION(CMilitaryManager_Enqueue), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "IUnitTask@+ EnqueueRetreat()", asMETHOD(CMilitaryManager, EnqueueRetreat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void DefaultMakeDefence(int, const AIFloat3& in)", asMETHOD(CMilitaryManager, DefaultMakeDefence), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void DefaultMakeSensors(int, const AIFloat3& in)", asMETHOD(CMilitaryManager, DefaultMakeSensors), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "uint GetGuardTaskNum() const", asMETHOD(CMilitaryManager, GetGuardTaskNum), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "uint ReleaseHoldPools()", asFUNCTION(CMilitaryManager_ReleaseHoldPools), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "uint HoldPools()", asFUNCTION(CMilitaryManager_HoldPools), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float HoldPoolsUpTo(float)", asFUNCTION(CMilitaryManager_HoldPoolsUpTo), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "bool IsBirthDefender(CCircuitUnit@) const", asMETHOD(CMilitaryManager, IsBirthDefender), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float AssetHold(CCircuitUnit@, float, AIFloat3& out)", asMETHOD(CMilitaryManager, AssetHold), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void NoteBirthScript(int)", asFUNCTION(CMilitaryManager_NoteBirthScript), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void NoteJoinWin(int, int, int)", asMETHOD(CMilitaryManager, NoteJoinScript), asCALL_THISCALL); ASSERT(r >= 0);
	// apex: the base-defence ring DefendTask's fight-at-any-odds boost and the
	// defence builder both honor -- bound so the script can DRAW the zone.
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetBaseDefRange() const", asMETHOD(CMilitaryManager, GetBaseDefRange), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void SetBaseDefRange(float)", asMETHOD(CMilitaryManager, SetBaseDefRange), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void ClearSupportSpots()", asFUNCTION(CMilitaryManager_ClearSupportSpots), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void AddSupportSpot(const AIFloat3& in, float)", asFUNCTION(CMilitaryManager_AddSupportSpot), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void SetFocus(const AIFloat3& in, float, float, bool, int)", asFUNCTION(CMilitaryManager_SetFocus), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void SetFocusHome(const AIFloat3& in)", asFUNCTION(CMilitaryManager_SetFocusHome), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "string StockArmyStat()", asMETHOD(CMilitaryManager, StockArmyStat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetAttackPower() const", asMETHOD(CMilitaryManager, GetAttackPower), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetAttackPowerNear(const AIFloat3& in, float) const", asMETHOD(CMilitaryManager, GetAttackPowerNear), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetGatheredPower() const", asMETHOD(CMilitaryManager, GetGatheredPower), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetEnemyInflNear(const AIFloat3& in, float) const", asMETHOD(CMilitaryManager, GetEnemyInflNear), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "int GetSpotWantedCount()", asMETHOD(CMilitaryManager, GetSpotWantedCount), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "AIFloat3 GetSpotWantedAt(int) const", asMETHOD(CMilitaryManager, GetSpotWantedAt), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CMilitaryManager", "const float armyCost", asOFFSET(CMilitaryManager, armyCost)); ASSERT(r >= 0);

	// NOTE: Config's "quota" scattered across CMilitaryManager, CEnemyManager, CThreatMap, CFactoryManager, CSetupManager
	r = engine->RegisterObjectType("SQuotaMilitary", 0, asOBJ_REF | asOBJ_NOCOUNT); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CMilitaryManager", "SQuotaMilitary quota", 0); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SQuotaMilitary", "uint scout", asOFFSET(CMilitaryManager, maxScouts)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SQuotaMilitary", "float attack", asOFFSET(CMilitaryManager, minAttackers)); ASSERT(r >= 0);
	r = engine->RegisterObjectType("SRaidQuota", 0, asOBJ_REF | asOBJ_NOCOUNT); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SQuotaMilitary", "SRaidQuota raid", 0); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SRaidQuota", "float min", asOFFSET(CMilitaryManager::SRaidQuota, min), asOFFSET(CMilitaryManager, raid), false); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SRaidQuota", "float avg", asOFFSET(CMilitaryManager::SRaidQuota, avg), asOFFSET(CMilitaryManager, raid), false); ASSERT(r >= 0);

	CFortCensus::RegisterScript(engine);
	// Alternative "quota" accessors:
//	r = engine->RegisterObjectProperty("CMilitaryManager", "uint quotaScout", asOFFSET(CMilitaryManager, maxScouts)); ASSERT(r >= 0);
//	r = engine->RegisterObjectProperty("CMilitaryManager", "float quotaAttack", asOFFSET(CMilitaryManager, minAttackers)); ASSERT(r >= 0);
//	r = engine->RegisterObjectProperty("CMilitaryManager", "float quotaRaidMin", asOFFSET(CMilitaryManager::SRaidQuota, min), asOFFSET(CMilitaryManager, raid), false); ASSERT(r >= 0);
//	r = engine->RegisterObjectProperty("CMilitaryManager", "float quotaRaidAvg", asOFFSET(CMilitaryManager::SRaidQuota, avg), asOFFSET(CMilitaryManager, raid), false); ASSERT(r >= 0);
}

CMilitaryScript::~CMilitaryScript()
{
}

bool CMilitaryScript::Init()
{
	asIScriptModule* mod = script->GetEngine()->GetModule(CScriptManager::mainName.c_str());
	int r = mod->SetDefaultNamespace("Military"); ASSERT(r >= 0);
	InitModule(mod);
	militaryInfo.makeDefence = script->GetFunc(mod, "void AiMakeDefence(int, const AIFloat3& in)");
	militaryInfo.joinFight = script->GetFunc(mod, "bool AiJoinFight(const AIFloat3& in, float, float, float, float, int)");
	return true;
}

// Go to a fight our side is already in? A script without the function always goes.
bool CMilitaryScript::JoinFight(const AIFloat3& at, float travelS, float allyPow, float foePow, float ownPow, int leaderId)
{
	if (militaryInfo.joinFight == nullptr) {
		return true;
	}
	asIScriptContext* ctx = script->PrepareContext(militaryInfo.joinFight);
	ctx->SetArgAddress(0, &const_cast<AIFloat3&>(at));
	ctx->SetArgFloat(1, travelS);
	ctx->SetArgFloat(2, allyPow);
	ctx->SetArgFloat(3, foePow);
	ctx->SetArgFloat(4, ownPow);
	ctx->SetArgDWord(5, leaderId);
	const bool go = !script->Exec(ctx) || (ctx->GetReturnByte() != 0);
	script->ReturnContext(ctx);
	return go;
}

void CMilitaryScript::MakeDefence(int cluster, const AIFloat3& pos)
{
	if (militaryInfo.makeDefence == nullptr) {
		static_cast<CMilitaryManager*>(manager)->DefaultMakeDefence(cluster, pos);
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(militaryInfo.makeDefence);
	ctx->SetArgDWord(0, cluster);
	ctx->SetArgAddress(1, &const_cast<AIFloat3&>(pos));
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

} // namespace circuit
