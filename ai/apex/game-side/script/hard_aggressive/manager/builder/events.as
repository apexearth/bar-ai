namespace Builder {

// The first T2 mex is what pays for everything after it, so put the commander on
// it until it is up. The script cannot address the nanoframe directly -- IUnitTask
// exposes only the build position, and a MEXUP task carries a spot id we cannot
// read -- so this is a positional REPAIR, which in Spring is exactly what
// assisting a nanoframe is. Same shape as the wreck reclaim above, which already
// enqueues a positional task with no buildDef.
AIFloat3 gMexUpPos;
bool gMexUpActive = false;
int  gCommAssistNext = 0;

void AiTaskAdded(IUnitTask@ task)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	const int bt = task.GetBuildType();
	Requests::Register(task);
	// Paired with the energy-task-removed log below: same def+position lets
	// the two be matched up in a trace to read a reactor's actual lifespan
	// (added-frame to removed-frame) rather than inferring it from gaps.
	if ((bt == int(Task::BuildType::ENERGY)) && (task.buildDef !is null)
		&& (task.buildDef.costM >= 2000.f))
	{
		const AIFloat3 at = task.GetBuildPos();
		AiLog(Factory::T() + "apex: energy-task-added " + task.buildDef.GetName()
			+ " at=" + int(at.x) + "," + int(at.z));
	}
	if (bt == Task::BuildType::MEXUP) {
		gMexUpPos = task.GetBuildPos();
		gMexUpActive = true;
	} else if (bt == Task::BuildType::MEX) {
		gMexTasks.insertLast(task);
	} else if (bt == Task::BuildType::DEFENCE) {
		gDefTasks.insertLast(task);
	} else if (bt == Task::BuildType::REPAIR) {
		CCircuitUnit@ hurt = task.target;
		if (hurt !is null) {
			if (hurt.circuitDef.IsMobile()) {
				gArmyRepairs.insertLast(task);
			} else {
				gStructRepair.insertLast(task);
				gStructRepairId.insertLast(hurt.id);
			}
		}
	} else if (bt == Task::BuildType::RECLAIM) {
		// Feature reclaims carry no target and are not registered.
		CCircuitUnit@ doomed = task.target;
		if (doomed !is null) {
			gDoomedTask.insertLast(task);
			gDoomedId.insertLast(doomed.id);
		}
	}
// 	if (task.GetType() != Task::Type::BUILDER)
// 		return;
// 	switch (task.GetBuildType()) {
// 	case Task::BuildType::ENERGY: {
// 		if (gPauseCnt == 0) {
// 			string name = task.GetBuildDef().GetName();
// 			if ((name == "armfus") || (name == "armafus") || (name == "corfus") || (name == "corafus")) {
// 				AiPause(true, "energy");
// 				++gPauseCnt;
// 			}
// 			AiAddPoint(task.GetBuildPos(), name);
// 		}
// 	} break;
// 	case Task::BuildType::FACTORY:
// 	case Task::BuildType::NANO:
// 	case Task::BuildType::STORE:
// 	case Task::BuildType::PYLON:
// 	case Task::BuildType::GEO:
// 	case Task::BuildType::GEOUP:
// 	case Task::BuildType::DEFENCE:
// 	case Task::BuildType::BUNKER:
// 	case Task::BuildType::BIG_GUN:
// 	case Task::BuildType::RADAR:
// 	case Task::BuildType::SONAR:
// 	case Task::BuildType::CONVERT:
// 	case Task::BuildType::MEX:
// 	case Task::BuildType::MEXUP:
// 		AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 		break;
// 	case Task::BuildType::REPAIR:
// 		AiAddPoint(task.GetBuildPos(), "rep");
// 		break;
// 	case Task::BuildType::RECLAIM:
// 		AiAddPoint(task.GetBuildPos(), "rec");
// 		break;
// 	case Task::BuildType::RESURRECT:
// 		AiAddPoint(task.GetBuildPos(), "res");
// 		break;
// 	case Task::BuildType::TERRAFORM:
// 		AiAddPoint(task.GetBuildPos(), "ter");
// 		break;
// 	default:
// 		break;
// 	}
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	const int bt = task.GetBuildType();
	// WAS THIS FINISHED, OR ABANDONED MID-BUILD? `done` says which; `target`
	// (set only once the nanoframe exists, IBuilderTask::SetTarget) says
	// whether it ever got that far at all. apexearth: still seeing multiple
	// reactors "built" (started) at once -- if most of them are actually
	// getting cancelled here with done=false and no nanoframe, the visible
	// symptom is scattered half-started sites, not real duplicate completion.
	// Scoped to the expensive reactor tier only; this fires often enough on
	// cheap defs (solar, wind) to be noise there.
	if ((bt == int(Task::BuildType::ENERGY)) && (task.buildDef !is null)
		&& (task.buildDef.costM >= 2000.f))
	{
		array<CCircuitUnit@>@ had = task.GetUnits();
		const AIFloat3 at = task.GetBuildPos();
		const bool hasWorker = (had !is null) && (had.length() > 0) && (had[0] !is null);
		AiLog(Factory::T() + "apex: energy-task-removed " + task.buildDef.GetName()
			+ " done=" + (done ? "1" : "0")
			+ " hadNanoframe=" + ((task.target !is null) ? "1" : "0")
			+ " workers=" + ((had !is null) ? had.length() : 0)
			+ " unit=" + (hasWorker ? int(had[0].id) : -1)
			+ " at=" + int(at.x) + "," + int(at.z));
	}
	Requests::Forget(task);
	if (bt == Task::BuildType::MEXUP) {
		gMexUpActive = false;
	} else if (bt == Task::BuildType::DEFENCE) {
		// THE REGISTER LEAKED. Defence tasks were added here and removed only
		// under the MEX branch, comparing against tasks that can never be in this
		// array -- so nothing ever left it. DefenceTaskNear then answered "already
		// ordered" for every point the Brain had EVER asked for, which retires the
		// whole front curve after one pass along it.
		for (uint i = 0; i < gDefTasks.length(); ++i) {
			if (gDefTasks[i] is task) {
				gDefTasks.removeAt(i);
				break;
			}
		}
	} else if (bt == Task::BuildType::MEX) {
		for (uint i = 0; i < gMexTasks.length(); ++i) {
			if (gMexTasks[i] is task) {
				gMexTasks.removeAt(i);
				break;
			}
		}
	} else if (bt == Task::BuildType::REPAIR) {
		// By identity, not by target: the target may already be dead here.
		for (uint i = 0; i < gArmyRepairs.length(); ++i) {
			if (gArmyRepairs[i] is task) {
				gArmyRepairs.removeAt(i);
				break;
			}
		}
		for (uint i = 0; i < gStructRepair.length(); ++i) {
			if (gStructRepair[i] is task) {
				gStructRepair.removeAt(i);
				gStructRepairId.removeAt(i);
				break;
			}
		}
	} else if (bt == Task::BuildType::RECLAIM) {
		for (uint i = 0; i < gDoomedTask.length(); ++i) {
			if (gDoomedTask[i] is task) {
				gDoomedTask.removeAt(i);
				gDoomedId.removeAt(i);
				break;
			}
		}
	}
// 	if (task.GetType() != Task::Type::BUILDER)
// 		return;
// 	switch (task.GetBuildType()) {
// 	case Task::BuildType::FACTORY:
// 	case Task::BuildType::NANO:
// 	case Task::BuildType::STORE:
// 	case Task::BuildType::PYLON:
// 	case Task::BuildType::ENERGY:
// 	case Task::BuildType::GEO:
// 	case Task::BuildType::GEOUP:
// 	case Task::BuildType::DEFENCE:
// 	case Task::BuildType::BUNKER:
// 	case Task::BuildType::BIG_GUN:
// 	case Task::BuildType::RADAR:
// 	case Task::BuildType::SONAR:
// 	case Task::BuildType::CONVERT:
// 	case Task::BuildType::MEX:
// 	case Task::BuildType::MEXUP:
// 	case Task::BuildType::REPAIR:
// 	case Task::BuildType::RECLAIM:
// 	case Task::BuildType::RESURRECT:
// 	case Task::BuildType::TERRAFORM:
// 		AiDelPoint(task.GetBuildPos());
// 		break;
// 	default:
// 		break;
// 	}
}

// Commander safety, issued as a raw move order rather than a task.
//
// A task returned from AiMakeTask replaces everything the commander would
// have built, since that hook is the ONLY place it gets work. CmdMoveTo
// issues the order directly and leaves the task slot alone, so the commander
// keeps its job and simply walks away from the danger first.
CCircuitUnit@ gComm = null;
AIFloat3 gHomePos;
bool gHomeSet = false;
const float COM_DANGER_RADIUS = 800.f;
const float COM_DANGER_FOES   = 3.f;   // a lone scout reads 1; a raid is 3+
int gNextComMove = 0;

// UpdateCommanderSafety() REMOVED, not merely disabled: it crashed the engine
// (exit -1003). Unsafe is one of CmdMoveTo issued outside a task context, or
// GetEnemyCostAt's GetEnemyUnitsIn walk. Both bindings remain registered but
// nothing calls them, so no script path can reach either; isolate and test
// one at a time before depending on them again.

// Diagnostic only: ai.GetBuilderThreatAt reads the engine's own per-position
// threat map, logged where the commander actually is so a retreat threshold
// can be set from measurement rather than invented.
//
// Commander retreat is triggered on HEALTH rather than position threat: the
// position threat map reads LOWER than baseline right up until the commander
// dies, because a shooter at range leaves the victim's own tile reading
// clean. Health loss is unambiguous regardless of the shooter's range.
//
// 0.85: at a lower bar the commander stays until it has lost a large share of
// health, by which point it is already inside an army; this leaves on the
// first real damage instead, since a commander under fire should stop
// building rather than finish the job.
const float COM_RETREAT_HEALTH = 0.85f;
int gNextRetreatLog = 0;

int gNextThreatLog = 0;

// There is no AiUnitDestroyed hook in this script -- the engine warns
// "Script: 'void AiUnitDestroyed(CCircuitUnit@)' not found!" at every match
// start -- so the only way to see a commander's last moments from the
// infolog is the gap between this heartbeat's last line and the point it
// stops. Logging health here turns that gap into "health was still N%" or
// "already retreating", distinguishing a sudden death from a failed retreat.
void LogCommanderThreat(CCircuitUnit@ unit)
{
	if (ai.frame < gNextThreatLog)
		return;
	gNextThreatLog = ai.frame + 30 * SECOND;
	const AIFloat3 here = unit.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: comm threat=" + formatFloat(ai.GetBuilderThreatAt(here), "", 0, 2)
		+ " hp=" + formatFloat(unit.GetHealthPercent() * 100.f, "", 0, 0)
		+ " frame=" + ai.frame);
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
	// Before every early return below, or a fusion finishing while some other
	// branch claims the unit is never recorded.
	if (IsFusion(unit.circuitDef))
		gFusions.insertLast(unit);
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask) && (gComm is null)) {
		@gComm = unit;
		gHomePos = unit.GetPos(ai.frame);
		gHomeSet = true;
	}
	// ai.GiveUnits unregisters the unit and fires its removal event from inside
	// the call, so once it returns true this unit is already gone. Recording it
	// below would park a foreign unit in an energizer slot whose AiUnitRemoved
	// has been and gone, wedging that slot for the rest of the game.
	// Anything advanced-constructor sized that we KEEP means we are covered.
	// Tracked separately from gGotAdvCon, which only records a gift arriving: a
	// player that built its own is equally covered and must not build more.
	if ((usage == Unit::UseAs::BUILDER)
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		&& (unit.circuitDef.costM >= ADV_CON_COST))
	{
		gHaveAdvCon = true;
	}
	if (ShareAdvCon(unit, usage))
		return;   // handed to an ally; it is not ours to count
	if ((usage == Unit::UseAs::BUILDER)
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		&& (unit.circuitDef.costM >= ADV_CON_COST))
	{
		++gAdvConCount;
	}

	// A constructor sealed into a pocket is the same failure as a walled-in
	// squad, and the one that strands work half-built. See military/unblock.as.
	if ((usage == Unit::UseAs::BUILDER) || (usage == Unit::UseAs::REZZER))
		Military::NotePenned(unit);

	if (usage == Unit::UseAs::REZZER) {
		const int rid = unit.circuitDef.id;
		if ((rid >= 0) && (uint(rid) < gRezzerDefs.length()) && !gRezzerDefs[rid]) {
			gRezzerDefs[rid] = true;
			gRezzerIds.insertLast(rid);
		}
		return;
	}

	const CCircuitDef@ cdef = unit.circuitDef;
	if (usage != Unit::UseAs::BUILDER || cdef.IsRoleAny(Unit::Role::COMM.mask))
		return;

	// Give it a standing job before anything else claims it.
	Crew::Enlist(unit);

	// A gifted advanced constructor materialises where it stood, in the lead's
	// base, and the receiving AI then picks its own work -- observed live, an
	// ally used one to start a mex on the front line. Nothing on the giving side
	// can prevent that: the whole binding surface has no way to move, order or
	// otherwise steer a unit, ai.GiveUnits takes no position, and the receiver's
	// UnitGiven issues CmdStop on arrival anyway.
	//
	// The receiver runs this same script, though, and it can tell the unit was a
	// gift: with no advanced factory of our own we cannot have built an advanced
	// constructor. Unit::Attr::BASE is the one lever that changes what it then
	// does. DefaultMakeTask routes a BASE unit to MakeEnergizerTask, which walks
	// task types in a fixed order instead of picking purely by distance -- energy,
	// storage, factory and nano first, then MEXUP ahead of MEX -- caps everything
	// after those four to 2000 elmos of the unit and of base, and drops any
	// position under enemy influence outright, where the ordinary builder path
	// only drops it when threat and influence and low build-power all coincide.
	// Upgrading the mexes we already hold is what the gift was for; opening a new
	// spot at the front is what it was not.
	if (!Factory::gHaveT2 && (cdef.costM >= ADV_CON_COST)) {
		unit.AddAttribute(Unit::Attr::BASE.type);
		AiLog(Factory::T() + "apex: received adv con " + cdef.GetName()
			+ " -- holding it to base work");
		return;
	}

	// constructor with BASE attribute is assigned to tasks near base
	if (cdef.costM < 200.f) {
		if (energizer1 is null
			&& (uint(cdef.count) > aiMilitaryMgr.GetGuardTaskNum() || cdef.IsAbleToFly()))
		{
			@energizer1 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	} else if (cdef.costM < ADV_CON_COST) {
		// Never an ADVANCED constructor. Attr::BASE routes a unit to
		// CBuilderManager::MakeEnergizerTask for the rest of its life, and that
		// function has no CreateBuilderTask -- it can only pick up work that
		// already exists, within 2000 elmos, in a fixed type order that puts
		// ENERGY/STORE/FACTORY/NANO ahead of MEXUP, and it returns nullptr
		// outright once the unit is on a GUARD task. Nothing ever calls
		// DelAttribute, so this branch would otherwise pin the one unit that can
		// upgrade a mex to a rule that cannot create that task.
		if (energizer2 is null) {
			@energizer2 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Crew::Discharge(unit);
	if ((usage == Unit::UseAs::BUILDER) || (usage == Unit::UseAs::REZZER))
		Military::ForgetPenned(unit.id);
	// Losing one has to re-open the slot, or a player that loses its advanced
	// constructors never replaces them.
	if ((usage == Unit::UseAs::BUILDER)
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		&& (unit.circuitDef.costM >= ADV_CON_COST)
		&& (gAdvConCount > 0))
	{
		--gAdvConCount;
	}
	if (energizer1 is unit)
		@energizer1 = null;
	else if (energizer2 is unit)
		@energizer2 = null;
	// Same NOCOUNT hazard as gT1FacUnit: a dangling handle reads as non-null.
	if (gComm is unit) {
		// A commander is never a gift candidate (ShareAdvCon excludes
		// Role::COMM), so this removal IS a death signal -- the real one this
		// file has lacked. "comm threat=... hp=..." (LogCommanderThreat) only
		// samples every 30s and cannot tell "died suddenly" from "log just
		// went quiet because nothing needed reevaluating"; this fires exactly
		// once, at the actual removal.
		AiLog(Factory::T() + "apex: COMMANDER LOST frame=" + ai.frame
			+ " hp=" + formatFloat(unit.GetHealthPercent() * 100.f, "", 0, 0));
		@gComm = null;
	}
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i] is unit) {
			gFusions.removeAt(i);
			break;
		}
	}
}

bool IsFusion(const CCircuitDef@ cdef)
{
	if (cdef is null)
		return false;
	const string n = cdef.GetName();
	return (n == armfus) || (n == corfus) || (n == legfus)
		|| (n == armafus) || (n == corafus) || (n == legafus);
}

// Hand our newest reactor to a teammate. Returns true when one went.
//
// The unit is dropped from the list BEFORE the call: ai.GiveUnits unregisters
// the unit and fires its removal event from inside the call, so by the time it
// returns this handle is already dead -- the same re-entrancy ShareAdvCon
// documents.
bool GiveFusion(int team)
{
	while ((gFusions.length() > FUSION_KEEP) && (gFusions[gFusions.length() - 1] is null))
		gFusions.removeLast();
	if (gFusions.length() <= FUSION_KEEP)
		return false;
	CCircuitUnit@ give = gFusions[gFusions.length() - 1];
	if (give is null)
		return false;
	gFusions.removeLast();
	array<CCircuitUnit@> gift;
	gift.insertLast(give);
	ai.GiveUnits(gift, team);
	AiLog(Factory::T() + "apex: gave " + give.circuitDef.GetName()
		+ " to team " + team + " (kept " + gFusions.length() + ")");
	return true;
}

void AiLoad(IStream& istream)
{
	Id e1id = -1, e2id = -1;
	istream >> e1id >> e2id;
	@energizer1 = ai.GetTeamUnit(e1id);
	@energizer2 = ai.GetTeamUnit(e2id);
	if (energizer1 !is null)
		energizer1.AddAttribute(Unit::Attr::BASE.type);
	if (energizer2 !is null)
		energizer2.AddAttribute(Unit::Attr::BASE.type);
}

void AiSave(OStream& ostream)
{
	ostream << Id(energizer1 !is null ? energizer1.id : -1)
			<< Id(energizer2 !is null ? energizer2.id : -1);
}

// LOG ONLY. Enqueues nothing, returns nothing, changes no decision.
//
// Sampled from AiUpdate rather than from AiMakeTask, because the question is
// whether a parked advanced constructor reaches AiMakeTask at all: a builder
// that has arrived at its site is put into engine WAIT by IBuilderTask::
// Reevaluate, and one holding a task of the same build type is never re-offered
// work. Neither state is visible from inside the hook that would have to fix it.
array<int>   gAdvId;
array<float> gAdvX;
array<float> gAdvZ;
array<int>   gAdvStill;
int gNextAdvDiag = 0;

const float ADV_STILL_DIST    = 48.f;          // a con at work jitters more than this
const int   ADV_DIAG_PERIOD   = 15 * SECOND;
const int   ADV_STILL_SAMPLES = 4;             // ~1 minute parked before it is news
const uint  ADV_TRACK_MAX     = 128;

int AdvSlot(int id)
{
	for (uint i = 0; i < gAdvId.length(); ++i) {
		if (gAdvId[i] == id)
			return int(i);
	}
	// Dead constructors are never removed one by one; the arrays are pure
	// scratch, so dropping the lot is cheaper than tracking removals.
	if (gAdvId.length() >= ADV_TRACK_MAX) {
		gAdvId.resize(0);
		gAdvX.resize(0);
		gAdvZ.resize(0);
		gAdvStill.resize(0);
	}
	gAdvId.insertLast(id);
	gAdvX.insertLast(0.f);
	gAdvZ.insertLast(0.f);
	gAdvStill.insertLast(-1);
	return int(gAdvId.length()) - 1;
}

void AdvConDiag()
{
	if (ai.frame < gNextAdvDiag)
		return;
	gNextAdvDiag = ai.frame + ADV_DIAG_PERIOD;
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Crew::gId[i]));
		if ((c is null) || (c.circuitDef.costM < ADV_CON_COST))
			continue;
		const AIFloat3 here = c.GetPos(ai.frame);
		if (!OnMap(here))
			continue;
		const int s = AdvSlot(int(c.id));
		const float dx = here.x - gAdvX[s];
		const float dz = here.z - gAdvZ[s];
		const bool moved = (gAdvStill[s] < 0)
				|| ((dx * dx + dz * dz) > (ADV_STILL_DIST * ADV_STILL_DIST));
		gAdvStill[s] = moved ? 0 : (gAdvStill[s] + 1);
		gAdvX[s] = here.x;
		gAdvZ[s] = here.z;
		if (gAdvStill[s] < ADV_STILL_SAMPLES)
			continue;
		IUnitTask@ t = c.task;
		int tt = -1;
		int bt = -1;
		uint on = 0;
		if (t !is null) {
			tt = t.GetType();
			if (tt == Task::Type::BUILDER) {
				bt = t.GetBuildType();
				array<CCircuitUnit@>@ crew = t.GetUnits();
				if (crew !is null)
					on = crew.length();
			}
		}
		AiLog(Factory::T() + "apex: advcon-idle " + c.circuitDef.GetName()
			+ " still=" + gAdvStill[s]
			+ " base=" + (c.IsAttrAny(Unit::Attr::BASE.mask) ? "1" : "0")
			+ " type=" + tt + " build=" + bt + " on=" + on
			+ " role=" + Crew::RoleOf(c)
			+ " mEmpty=" + (aiEconomyMgr.isMetalEmpty ? "1" : "0")
			+ " eEmpty=" + (aiEconomyMgr.isEnergyEmpty ? "1" : "0")
			+ " eStall=" + (aiEconomyMgr.isEnergyStalling ? "1" : "0"));
	}
}

// WHY THE COMMANDER IS STANDING THERE. Buckets declared in rules_commander.as,
// sampled here because gComm is declared in this file and the shim includes it
// last. Called once per AiUpdate; see CommDiag for what the numbers mean.
void CommIdleAttribute()
{
	// gComm is cleared in AiUnitRemoved -- CCircuitUnit is NOCOUNT, so a stored
	// handle stays non-null on freed memory and must never be read after death.
	CCircuitUnit@ u = gComm;
	if (u is null)
		return;
	++gCDSamples;
	IUnitTask@ t = u.task;
	const int q = u.CmdQueueSize();
	if ((t is null) || (t.GetType() == Task::Type::IDLE)
		|| (t.GetType() == Task::Type::NIL))
	{
		++gCDNoTask;
	} else if (t.GetType() != Task::Type::BUILDER) {
		++gCDOther;
	} else if (q > 0) {
		++gCDOrdered;
		gCommStuck = 0;
	} else {
		++gCDWaiting;
		// Holding a build task with NO engine order. Briefly that is a pending
		// path query; sustained, the task is one the commander will never start,
		// and it will hold it forever because HoldWorkInProgress keeps returning
		// it. Dropping it puts the commander back through the pipeline.
		if (++gCommStuck >= int(ai.GetTunable("apex_comm_stuck", COMM_STUCK_TICKS))) {
			gCommStuck = 0;
			++gCommUnstuck;
			AiLog(Factory::T() + "apex: commander stuck on bt"
				+ t.GetBuildType() + " with no order -- dropping it (#"
				+ gCommUnstuck + ")");
			t.Abort();
		}
	}
}

}  // namespace Builder
