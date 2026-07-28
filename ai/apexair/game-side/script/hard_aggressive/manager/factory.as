#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "economy.as"


namespace Factory {

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
	if (lastSwitchFrame + switchInterval <= ai.frame) {
		switchInterval = MakeSwitchInterval();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	const bool isOK = (aiMilitaryMgr.armyCost > 1.2f * facDef.costM * aiFactoryMgr.GetFactoryCount())
		|| (aiEconomyMgr.metal.current > facDef.costM);
	aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = !isOK;
	return isOK;
}

//------------------------------------------------------------------------------
// apex4: randomized porc-then-air strategy.
//
// Opening with air loses a 1v1 -- it has to be a *transition*, after a normal
// ground opening and behind static defence. In a team game at most one player
// should take it, so eligibility is gated on skirmishAIId rather than rolled
// independently by every AI (4 simultaneous air players would be suicide).
//
// State lives in this namespace, initialised lazily: global initialisers run at
// module load, before `ai` is necessarily usable.
//------------------------------------------------------------------------------
bool gAirInit    = false;
bool gAirStrat   = false;
int  gAirPivotAt = 0;
int  gAirBuilt   = 0;

void EnsureAirStrat()
{
	if (gAirInit)
		return;
	gAirInit = true;
	// apexair: unconditional. This variant exists to test one hypothesis --
	// stock BARb caps anti-air at 50% of army and its aa_threat thresholds look
	// nearly unreachable, so a committed air force may face an opponent that
	// structurally under-responds. Not a good 1v1 opening, hence still a pivot.
	gAirStrat   = true;
	gAirPivotAt = AiRandom(9, 12) * MINUTE;
	if (gAirStrat)
		AiLog("apexair: AIR pivot scheduled, pivot at " + (gAirPivotAt / MINUTE) + " min");
}

CCircuitDef@ PickAirPlant()
{
	string side = ai.GetSideName();
	CCircuitDef@ d = null;
	if (side == "cortex") {
		@d = ai.GetCircuitDef(coraap);
		if (d is null) @d = ai.GetCircuitDef(corap);
	} else if (side == "legion") {
		@d = ai.GetCircuitDef(legaap);
		if (d is null) @d = ai.GetCircuitDef(legap);
	} else {
		@d = ai.GetCircuitDef(armaap);
		if (d is null) @d = ai.GetCircuitDef(armap);
	}
	return d;
}

CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	EnsureAirStrat();

	// Never on the opening factory, and cap the pivot at two air plants so the
	// AI transitions rather than abandoning ground entirely.
	if (gAirStrat && !isStart && (ai.frame >= gAirPivotAt) && (gAirBuilt < 3)) {
		CCircuitDef@ air = PickAirPlant();
		if (air !is null) {
			++gAirBuilt;
			AiLog("apexair: air pivot -> " + air.GetName() + " (#" + gAirBuilt + ")");
			return air;
		}
	}
	return aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
}

/* --- Utils --- */

int MakeSwitchInterval()
{
	return AiRandom(550, 900) * SECOND;
}

}  // namespace Factory
