namespace Factory {

// The pending recruit queue, mirrored in script. CFactoryManager's own list
// (factoryTasks) and its throttle (CanEnqueueTask) are not bound to
// FactoryScript.cpp -- only DefaultMakeTask, Enqueue, GetRoleDef and
// GetFactoryCount are -- so every Enqueue our rules make is blind and appends
// unconditionally, with no dedup or cap. These two hooks are the only view of
// that list available from here, so the register is rebuilt from them.
array<IUnitTask@> gQTask;

void AiTaskAdded(IUnitTask@ task)
{
	if ((task is null) || (task.GetType() != Task::Type::FACTORY))
		return;
	if (task.GetBuildType() != Task::BuildType::RECRUIT)
		return;
	gQTask.insertLast(task);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	for (uint i = 0; i < gQTask.length(); ++i) {
		if (gQTask[i] is task) {
			gQTask.removeAt(i);
			return;
		}
	}
}

uint QueueDepth()
{
	return gQTask.length();
}

// Stock's own throttle, reimplemented because it is not bound. Two pending per
// factory is deep enough that a line never idles waiting for the next decision
// and shallow enough that the queue cannot accumulate -- it is CircuitAI's
// number, not one invented here; apex_fac_queue exposes it for an A/B.
bool QueueHasRoom()
{
	const int fac = aiFactoryMgr.GetFactoryCount();
	if (fac <= 0)
		return true;
	const float per = ai.GetTunable("apex_fac_queue", TUNE_FAC_QUEUE);
	return float(gQTask.length()) < float(fac) * per;
}

// How many pending recruits nobody has started yet. A queue that is deep in
// UNSTARTED orders is the accumulation this register exists to detect.
uint QueueUnstarted()
{
	uint n = 0;
	for (uint i = 0; i < gQTask.length(); ++i) {
		array<CCircuitUnit@>@ on = gQTask[i].GetUnits();
		if ((on is null) || (on.length() == 0))
			++n;
	}
	return n;
}

// The lead's own T1 lab, kept so it can be fed back into the T2 plant.
// gT1Reclaimed is declared with the other rush state above, because
// RushLeadTeamId() clears it on a handover and AngelScript resolves globals in
// declaration order.
CCircuitUnit@ gT1FacUnit = null;

// How many factories THIS instance currently has standing, of any kind or
// tier. See HaveAnyFactory() and its use in the commander branch below.
int gFactoryCount = 0;
// Every live factory, not just the base-plan anchor. The nano band is latched to
// the FIRST factory for the whole game, so every plant built after it -- and the
// whole base once that one is reclaimed -- had no way to ask for a caretaker.
array<CCircuitUnit@> gFacUnits;

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// T1-COMMIT ENFORCEMENT, at the only place every plant passes. The C++
	// side enqueues factories without consulting AiGetFactoryToBuild (the
	// unattributed entrance ISSUES.md tracks -- measured under the commit:
	// three T2 plants with zero "plant approved" lines), so the hold must
	// catch the nanoframe: reclaim it before real metal sinks in, and skip
	// the gHaveT2 latch or the frame would retire the T1 lines it exists to
	// protect.
	if ((usage == Unit::UseAs::FACTORY)
		&& ((userData[unit.circuitDef.id].attr & (Attr::T2 | Attr::T3)) != 0)
		&& T1Commit())
	{
		AiLog(T() + "apex: T1 commit reclaims unapproved "
			+ unit.circuitDef.GetName());
		aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, unit));
		return;
	}
	// THE T1 CAP, enforced at the same only-place-every-plant-passes. The gate
	// in AiGetFactoryToBuild holds duplicates to one until the reactor, but the
	// C++ side's unattributed entrance builds labs without asking it -- 21/24
	// benchmark games still stood a second T1 lab pre-fusion with the gate
	// refusing every ask (2026-08-21). Same cure as the T1-commit block above:
	// catch the surplus nanoframe and reclaim it before real metal sinks in.
	// Air plants are exempt (the air strategy carries its own income-scaled
	// counts); shipyards are not in the land-plant list and pass untouched.
	if ((usage == Unit::UseAs::FACTORY)
		&& IsLandT1Plant(unit.circuitDef)
		&& !IsAirFactory(unit.circuitDef)
		&& (T1PlantCount() >= 2)
		&& T1CapHolds())
	{
		AiLog(T() + "apex: T1 cap reclaims surplus "
			+ unit.circuitDef.GetName() + " (" + T1PlantCount()
			+" standing, cap one until the reactor)");
		aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, unit));
		return;
	}
	Brain::NoteSpend(unit, usage);
	if (usage == Unit::UseAs::FACTORY) {
		++gFactoryCount;
		gFacUnits.insertLast(unit);
	}
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0)
		gHaveT2 = true;
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T3) != 0)
		gHaveT3 = true;
	if ((usage == Unit::UseAs::FACTORY)
		// A GANTRY IS NOT THE T1 LAB. This tested T2 only, so a T3 plant fell
		// through and became the base-plan anchor and the commander's repair
		// target.
		&& ((Factory::userData[unit.circuitDef.id].attr
			& (Factory::Attr::T2 | Factory::Attr::T3)) == 0))
	{
		@gT1FacUnit = unit;
		AiLog(T() + "apex: T1 lab on field: " + unit.circuitDef.GetName());
	}
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

	if (Air::SuppressesOpener(facDef))
		return;

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
	if (usage == Unit::UseAs::FACTORY) {
		--gFactoryCount;
		// NOCOUNT: the handle is not nulled when the engine frees the unit, so
		// this must be removed here or ThinnestFactory reads freed memory.
		for (uint i = 0; i < gFacUnits.length(); ++i) {
			if (gFacUnits[i] is unit) {
				gFacUnits.removeAt(i);
				break;
			}
		}
	}
	// CCircuitUnit is registered NOCOUNT, so a handle is not nulled when the
	// engine destroys the unit and `is null` stays false on freed memory.
	// Leaving this unset crashed UpdateRushReclaim's Enqueue (0xc0000005).
	if (gT1FacUnit is unit)
		@gT1FacUnit = null;
	// A dead factory must not keep its ownership claim: ids are reused, and the
	// next unit to take this one would silently inherit "the Brain owns this
	// line" without the Brain ever having decided that.
	if (usage == Unit::UseAs::FACTORY)
		Brain::ReleaseFactory(unit.id);
}

// Any factory at all, of any kind or tier -- not just the T1 opener. See the
// commander branch in builder.as, which is the only place this matters: any
// other builder that could have used this is, by definition of the state
// being checked, already dead.
bool HaveAnyFactory()
{
	return gFactoryCount > 0;
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
// Log prefix: game time AND team id. Every AI instance on the map writes to
// one infolog behind the same shared prefix, so without the team id, four
// players' lines are indistinguishable. tools/trace_flow.py parses this.
string T()
{
	return "[" + formatFloat(float(ai.frame) / float(MINUTE), "", 0, 1) + "m t"
		+ ai.teamId + "] ";
}

// Periodic dump of every input the rush decision reads, so a slow tech can be
// attributed to a specific gate rather than guessed at. One line per 30s.
// The T1 lab is ~600-900 metal standing idle -- the rush already stops it
// producing, so it is pure banked metal doing nothing. Feed it into the plant it
// is being replaced by; a T1 lab can be rebuilt later once T2 economy is up.
// Above this banked metal the T1 lab is worth more as a factory than as scrap.
const float RECLAIM_LAB_BANK = 1500.f;

void UpdateRushReclaim()
{
	// TEAM ONLY: the rusher may eat its T1 lab because allies cover the gap;
	// solo, the T1 lab is the only army source during the most dangerous
	// window (IsTechLead is true for a solo player by fallback, so this fired
	// in duels). apexearth 2026-08-20: no tech-lead behaviour in a 1v1.
	if (!TeamPlay())
		return;
	if (gT1Reclaimed || gHaveT2 || !IsTechLead() || !RushWindowOpen())
		return;
	if (gT1FacUnit is null)
		return;
	// Only when the metal is actually wanted: the rule exists to unstick a rush
	// that cannot afford the plant; with a full bank it is destroying a working
	// factory to bank metal that is already spilling.
	if (aiEconomyMgr.isMetalFull || (aiEconomyMgr.metal.current > RECLAIM_LAB_BANK))
		return;
	// The advanced plant must EXIST, not merely have been chosen.
	// AiGetFactoryToBuild returning it is a preference; placement came minutes
	// later. Eating the T1 lab in that gap leaves the lead with no factory, and
	// CircuitAI answers by building a fresh T1 one -- observed live: vehicle lab
	// reclaimed, bot lab built, T2 plant only minutes after that.
	// CCircuitDef::count is incremented in RegisterTeamUnit, which runs for the
	// nanoframe, so this is true as soon as construction actually starts.
	CCircuitDef@ adv = AdvCounterpart();
	if ((adv is null) || (adv.count <= 0))
		return;
	gT1Reclaimed = true;
	AiLog(T() + "apex: reclaiming T1 lab " + gT1FacUnit.circuitDef.GetName()
		+ " into the advanced plant");
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, gT1FacUnit));
}

// THE ECO ROLE EATS EVERY T1 PLANT once its advanced plant stands
// (apexearth 2026-08-22, watching the +100 validation: "at 11m in we only
// have a t1 bot and air lab... we should be making the T2 lab, and
// reclaiming both the T1 labs. For this role we only really want to
// recreate the T1 lab once we have our second fusion"). The sweep runs only
// below two fusions: past that a rebuilt T1 lab is legitimate (the plant
// gate in PlantApproved/Take opens at the same bar) and must not be eaten.
array<int> gEcoAteIds;

// THE T2 LAB IS EATEN TOO, once its job is done (apexearth 2026-08-22: "That
// T2 lab has a lot of metal - hope we're reclaiming it once we have made
// enough t2 cons"). Its job: the adv-con fleet (plus gifts where owed).
// Gates, each his: fleet at AdvConsWanted and no gifts owed; both fusions
// standing (the same bar every role transition keys on); and STORAGE
// HEADROOM for the reclaim burst ("You need to ensure you have enough
// storage to store that much metal and not overflow/waste it"). The latch
// stops the tech logic re-buying the lab it just ate; the fleet collapsing
// below half the want re-opens the rebuild (PlantApproved reads the latch).
bool gT2LabEaten = false;

void EcoRoleEatT2Lab()
{
	if (gT2LabEaten || !TeamPlay() || !IsEcoLead() || !gHaveT2)
		return;
	if (Builder::gFusions.length() < 2)
		return;
	if (Builder::OwesAdvCons() || Builder::NeedsAdvCon())
		return;
	// Literal list, not T2_FAC: factorydefs.as is included AFTER this file,
	// and a global read before its declaration kills the whole variant.
	// Ground adv plants only -- the air plant is the role's late con source.
	array<string> advPlants = {"armalab", "armavp",
	                           "coralab", "coravp",
	                           "legalab", "legavp"};
	for (uint i = 0; i < advPlants.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(advPlants[i]);
		if ((d is null) || (d.count <= 0))
			continue;
		if (aiEconomyMgr.metal.storage - aiEconomyMgr.metal.current < d.costM)
			return;   // the burst would overflow; wait for headroom
		array<CCircuitUnit@>@ own = ai.GetOwnUnitsOfDef(d, Builder::gHomePos,
				AiTerrainWidth() + AiTerrainHeight());
		if ((own is null) || (own.length() == 0))
			continue;
		for (uint u = 0; u < own.length(); ++u) {
			if (own[u] is null)
				continue;
			AiLog(T() + "apex: eco role eats " + advPlants[i]
				+ " -- adv-con fleet complete, " + Builder::AdvConCount()
				+ " cons standing");
			aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, own[u]));
		}
		gT2LabEaten = true;
	}
}

// TOO MANY CONS? THEY PAY FOR THE LAB (apexearth: "Have too many cons?
// reclaim them to pay for the T2 lab"). While the objective is T2LAB and
// the bank cannot cover the plant, surplus T1 cons above the demand bound
// are reclaimed, newest first would churn the workforce -- one per sweep,
// so the reclaim keeps pace with the shortfall without gutting the hands
// that still have queued work.
int gNextConPay = 0;

void EcoRoleConsPayForLab()
{
	if (!TeamPlay() || (Role::Objective() != Role::Obj::T2LAB))
		return;
	if (ai.frame < gNextConPay)
		return;
	gNextConPay = ai.frame + 5 * SECOND;
	CCircuitDef@ lab = AdvCounterpart();
	if ((lab is null)
		|| (aiEconomyMgr.metal.current >= lab.costM))
		return;   // the bank covers it; no need to eat hands
	CCircuitDef@ con = SideDef3("armck", "corck", "legck");
	if (con is null)
		return;
	const float per = ai.GetTunable("apex_con_tasks_each", TUNE_CON_TASKS_EACH);
	const int demand = (per > 0.f)
			? int(float(aiBuilderMgr.GetBuildTaskCount()) / per) + 1 : 6;
	if (int(con.count) <= demand)
		return;
	array<CCircuitUnit@>@ own = ai.GetOwnUnitsOfDef(con, Builder::gHomePos,
			AiTerrainWidth() + AiTerrainHeight());
	if ((own is null) || (own.length() == 0))
		return;
	CCircuitUnit@ pick = own[own.length() - 1];
	if (pick is null)
		return;
	AiLog(T() + "apex: role reclaims a surplus con toward the T2 lab ("
		+ con.count + " standing, demand ~" + demand + ")");
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, pick));
}

void EcoRoleEatT1Labs()
{
	if (!TeamPlay() || !IsEcoLead() || !gHaveT2)
		return;
	if (Builder::gFusions.length() >= 2)
		return;
	array<string> plants = {"armlab", "armvp", "armap", "armhp",
	                        "corlab", "corvp", "corap", "corhp",
	                        "leglab", "legvp", "legap", "leghp"};
	for (uint i = 0; i < plants.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(plants[i]);
		if ((d is null) || (d.count <= 0))
			continue;
		// Explicit map-spanning radius: radius 0 missed a lab standing away
		// from home (armlab still driven at 16.5m while "eats" fired once).
		array<CCircuitUnit@>@ own = ai.GetOwnUnitsOfDef(d, Builder::gHomePos,
				AiTerrainWidth() + AiTerrainHeight());
		if (own is null)
			continue;
		for (uint u = 0; u < own.length(); ++u) {
			if (own[u] is null)
				continue;
			const int id = int(own[u].id);
			if (gEcoAteIds.find(id) >= 0)
				continue;
			gEcoAteIds.insertLast(id);
			AiLog(T() + "apex: eco role eats " + plants[i]
				+ " -- the T2 line carries everything now");
			aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, own[u]));
		}
	}
}

int gNextRushLog = 0;
void LogRushState()
{
	if (ai.frame < gNextRushLog)
		return;
	gNextRushLog = ai.frame + 30 * SECOND;

	const bool lead = IsTechLead();
	if (!lead && gHaveT2)
		return;   // followers that already teched are not interesting

	const bool rushReady = RushReady();
	CCircuitDef@ adv = AdvCounterpart();
	const float advCost = (adv is null) ? 0.f : adv.costM;

	AiLog(T() + "rush team=" + ai.teamId + (lead ? " LEAD" : " follower")
		+ " haveT2=" + (gHaveT2 ? "1" : "0")
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
		+ "/" + formatFloat(Policy::T2Energy(), "", 0, 0)
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(advCost * 0.5f, "", 0, 0)
		+ " rushReady=" + (rushReady ? "1" : "0")
		+ " facs=" + aiFactoryMgr.GetFactoryCount()
		+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0));
}

int gNextSwitchProbe = 0;
int gNextConLog = 0;
const int T3_MAX_PROBES = 4;   // bounded: enough to place one gantry, never a pile
int gT3Probes = 0;
int gNextT3Probe = 0;

}  // namespace Factory
