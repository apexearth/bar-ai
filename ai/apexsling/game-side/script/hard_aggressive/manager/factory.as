#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "economy.as"


namespace Factory {

// Team tech coordination. Measured in a 4v4: stock has none -- each instance
// decides independently, so 0 of 4 teched on the losing side and 2 of 4 on the
// winner, essentially at random. Humans designate one player to tech and share
// advanced constructors out; everyone else follows once eco supports it.
bool gHaveT2 = false;   // set once we own an advanced factory
// The real trigger is energy, not metal: take the nearby mexes, reach roughly
// 500 energy/sec, then commit to T2. That lands around 5 minutes, and T2 should
// exist before 10. Gating on metal income 12 held the rusher on T1 until minute
// 12 and the plant only finished at 20 -- later than stock reached it unaided.
const float RUSH_ENERGY_TARGET = 150.f;      // measured: BARb hits this ~5.5 min
const float RUSH_ENERGY_FLOOR  = 90.f;       // fallback: reached before 4 min
const int   RUSH_LATEST        = 5 * MINUTE; // T2 should exist before 10 min

bool IsTechLead()
{
	return ai.teamId == ai.GetLeadTeamId();
}

const float FOLLOWER_TECH_INCOME = 28.f;   // followers wait for a running economy
const int   FOLLOWER_TECH_FRAME  = 13 * MINUTE;  // ...but never past this


enum Attr {
	T1 = 0x0001, T2 = 0x0002, T3 = 0x0004, T4 = 0x0008
}

class SUserData {
	SUserData(int a) {
		attr = a;
	}
	SUserData() {}
	int attr = 0;
}

// Example of userData per UnitDef
array<SUserData> userData(ai.GetDefCount() + 1);

string armlab  ("armlab");
string armalab ("armalab");
string armvp   ("armvp");
string armavp  ("armavp");
string armsy   ("armsy");
string armasy  ("armasy");
string armap   ("armap");
string armaap  ("armaap");
string armshltx("armshltx");

string corlab  ("corlab");
string coralab ("coralab");
string corvp   ("corvp");
string coravp  ("coravp");
string corsy   ("corsy");
string corasy  ("corasy");
string corap   ("corap");
string coraap  ("coraap");
string corgant ("corgant");

string leglab  ("leglab");
string legalab ("legalab");
string legvp   ("legvp");
string legavp  ("legavp");
string legsy   ("legsy");
string legap   ("legap");
string legaap  ("legaap");
string leggant ("leggant");

int switchInterval = MakeSwitchInterval();

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	return aiFactoryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0)
		gHaveT2 = true;
//	if (!factories.empty() || (this->circuit->GetBuilderManager()->GetWorkerCount() > 2)) return;
	if (usage != Unit::UseAs::FACTORY)
		return;

	const CCircuitDef@ facDef = unit.circuitDef;
	if (userData[facDef.id].attr & Attr::T3 != 0) {
		// if (ai.teamId != ai.GetLeadTeamId()) then this change affects only target selection,
		// while threatmap still counts "ignored" here units.
// 		AiLog("ignore newly created armpw, corak, armflea, armfav, corfav");
		array<string> spam = {"armpw", "corak", "armflea", "armfav", "corfav", "leggob", "legscout"};
		for (uint i = 0; i < spam.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(spam[i]);
			if (cdef !is null)
				cdef.SetIgnore(true);
		}
	}

	const array<Opener::SO>@ opener = Opener::GetOpener(facDef);
	if (opener is null)
		return;

	const AIFloat3 pos = unit.GetPos(ai.frame);
	for (uint i = 0, icount = opener.length(); i < icount; ++i) {
		CCircuitDef@ buildDef = aiFactoryMgr.GetRoleDef(facDef, opener[i].role);
		if ((buildDef is null) || !buildDef.IsAvailable(ai.frame))
			continue;

		Task::Priority priority;
		Task::RecruitType recruit;
		if (opener[i].role == Unit::Role::BUILDER.type) {
			priority = Task::Priority::NORMAL;
			recruit  = Task::RecruitType::BUILDPOWER;
		} else {
			priority = Task::Priority::HIGH;
			recruit  = Task::RecruitType::FIREPOWER;
		}
		for (uint j = 0, jcount = opener[i].count; j < jcount; ++j)
			aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, buildDef, pos, 64.f));
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * New factory switch condition; switch event is also based on eco + caretakers.
 */
bool AiIsSwitchTime(int lastSwitchFrame)
{
	// THE bug behind late teching: MakeSwitchInterval() is AiRandom(550,900)
	// seconds, so the AI only *considers* a factory change every 9-15 minutes.
	// The rush override was correct but never got asked -- hence T2 at 22.9m
	// instead of before 10. While the designated rusher still lacks T2, let it
	// reconsider every tick.
	if (IsTechLead() && !gHaveT2)
		return true;
	// Everyone should at least be trying for T2 by ~20 minutes.
	if (!gHaveT2 && (ai.frame > 20 * MINUTE))
		return true;
	if (lastSwitchFrame + switchInterval <= ai.frame) {
		switchInterval = MakeSwitchInterval();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	// "Defend, hold, tech up to turn the tide" -- the holding half was
	// implemented and the teching half was not, so the AI sat on banked metal
	// instead of spending it. Holding is exactly when tech should be bought:
	// the army is not being reinforced, so the stock requirement of
	// armyCost > 1.2 * facCost * facCount can never be met while turtling.
	// Followers hold on T1 until the economy can carry a second tech base;
	// the lead keeps stock behaviour and techs first.
	// Measured 4v4: this gate at income 45 left our side with 1 of 4 teched at
	// 25.4m while stock got 3 of 4 by 21m -- it was suppressing tech outright
	// rather than sequencing it. Followers now only wait until the rush window
	// has passed OR the economy is genuinely running, whichever comes first.
	// Followers were deadlocked: the gate keyed off their own metal income, but
	// slinging is what suppresses that income -- so donating blocked the tech it
	// was paying for. Release on elapsed time instead, and only hold them during
	// the pooling window.
	if (!IsTechLead() && ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& (ai.frame < FOLLOWER_TECH_FRAME))
	{
		return false;
	}
	// The designated player is rushing: buy T2 as soon as the metal is on hand,
	// without the stock army-value requirement. It is not meant to be
	// contributing T1 army at all, so that requirement can never be met.
	// Was 0.5 * factory cost banked (~1450 metal). The rusher never holds that
	// much because it spends as the slings arrive, so the plant did not start
	// until 12 min. It does not need the whole cost up front -- construction
	// draws from income, and seven feeders keep paying into it.
	if (IsTechLead() && ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& (aiEconomyMgr.metal.current > facDef.costM * 0.5f))
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = false;
		return true;
	}
	if (Military::gTurtle && (aiEconomyMgr.metal.current > facDef.costM * 0.6f)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = false;
		return true;
	}
	const bool isOK = (aiMilitaryMgr.armyCost > 1.2f * facDef.costM * aiFactoryMgr.GetFactoryCount())
		|| (aiEconomyMgr.metal.current > facDef.costM);
	aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = !isOK;
	return isOK;
}

// Composition telemetry from a lost game: we put 54k metal into T2 and still
// lost to stock's 43k, because the mix differed. We teched into the advanced
// BOT lab (corsumo -- slow, defensive) while stock teched into the advanced
// VEHICLE plant (corgol -- heavy assault). Gollums push; Sumos hold. Since we
// already out-produce, bias the T2 choice toward the assault option.
CCircuitDef@ PickAdvVehicle()
{
	string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(coravp);
	if (side == "legion")
		return ai.GetCircuitDef(legavp);
	return ai.GetCircuitDef(armavp);
}

CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	CCircuitDef@ pick = aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
	if (isStart || (pick is null))
		return pick;   // opening factory is always T1

	// The rusher builds the advanced plant directly rather than waiting for a
	// production switch that never comes.
	const bool rushReady = (aiEconomyMgr.energy.income > RUSH_ENERGY_TARGET)
			|| ((ai.frame > RUSH_LATEST) && (aiEconomyMgr.energy.income > RUSH_ENERGY_FLOOR));
	if (IsTechLead() && !gHaveT2 && rushReady) {
		CCircuitDef@ adv = PickAdvVehicle();
		if (adv !is null) {
			AiLog("apexsling: rusher building advanced plant " + adv.GetName());
			return adv;
		}
	}

	// Only redirect the T2 choice, and only away from the bot lab.
	if (Factory::userData[pick.id].attr & Factory::Attr::T2 != 0) {
		CCircuitDef@ avp = PickAdvVehicle();
		if ((avp !is null) && (avp.id != pick.id)) {
			AiLog("apexvp: T2 choice " + pick.GetName() + " -> " + avp.GetName());
			return avp;
		}
	}
	return pick;
}

/* --- Utils --- */

int MakeSwitchInterval()
{
	return AiRandom(550, 900) * SECOND;
}

}  // namespace Factory
