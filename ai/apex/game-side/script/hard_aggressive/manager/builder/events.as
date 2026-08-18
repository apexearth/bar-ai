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

// Rolling per-unit task history for AiUnitDestroyed (main.as) to log on
// death. Sampled from Crew::gId rather than hooked off AiTaskAdded: a task is
// added with no worker yet (requests.as), so a unit can't be identified at
// that event -- reading each crew member's own task periodically, the same
// shape AdvConDiag already uses, is the only place unit and task are both
// known. Builder crew only: combat units never join Crew::gId and there is no
// binding to enumerate all of our units. One ";"-joined string per unit
// rather than array<array<string>>, matching this file's flat-parallel-array
// style elsewhere (gAdvId/gAdvX/gAdvZ) instead of an unproven nested type.
array<int>    gHistId;
array<string> gHistBuf;
const uint TASK_HIST_MAX = 4;          // ring size per unit
int gNextHistSample = 0;
const int HIST_SAMPLE_PERIOD = 10 * SECOND;

int HistSlot(int id)
{
	for (uint i = 0; i < gHistId.length(); ++i) {
		if (gHistId[i] == id)
			return int(i);
	}
	return -1;
}

void SampleTaskHist()
{
	if (ai.frame < gNextHistSample)
		return;
	gNextHistSample = ai.frame + HIST_SAMPLE_PERIOD;
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(Crew::gId[i]));
		if (u is null)
			continue;
		IUnitTask@ t = u.task;
		if (t is null)
			continue;
		const int tt = t.GetType();
		const int bt = (tt == Task::Type::BUILDER) ? t.GetBuildType() : -1;
		const string tag = "t" + tt + "b" + bt + "@";
		int s = HistSlot(int(u.id));
		if (s < 0) {
			gHistId.insertLast(int(u.id));
			gHistBuf.insertLast("");
			s = int(gHistId.length()) - 1;
		}
		array<string>@ parts = gHistBuf[s].split(";");
		// split("") on an empty string returns one empty element, not zero --
		// drop it so a fresh slot doesn't start with a stray blank entry.
		if ((parts.length() == 1) && (parts[0] == ""))
			parts.removeLast();
		// Record a TRANSITION, not a repeat of the same job every sample --
		// otherwise ten minutes on one mex fills the whole ring with itself.
		if ((parts.length() > 0) && (parts[parts.length() - 1].findFirst(tag) == 0))
			continue;
		parts.insertLast(tag + ai.frame);
		while (parts.length() > TASK_HIST_MAX)
			parts.removeAt(0);
		string joined = "";
		for (uint j = 0; j < parts.length(); ++j) {
			if (j > 0)
				joined += ";";
			joined += parts[j];
		}
		gHistBuf[s] = joined;
	}
}

// Read and DROP a unit's history. Called exactly once, from AiUnitDestroyed,
// so the arrays stay bounded to units currently on the crew rather than
// growing for every unit built across a whole match.
string TakeHistFor(int id)
{
	const int s = HistSlot(id);
	if (s < 0)
		return "";
	const string hist = gHistBuf[s];
	gHistId.removeAt(uint(s));
	gHistBuf.removeAt(uint(s));
	return hist;
}

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
	// CONVERT was invisible here entirely -- 2026-08-14, a match showed HomeEnergy/
	// EcoConverters creating dozens of armmmkr requests (Requests::Take's own "new"
	// counter) with the def's .count staying at 0 the whole game and energyExcess
	// pinned at the storage ceiling for 12+ minutes, but no log said whether each
	// request was ever even assigned a worker before disappearing. Same shape as the
	// reactor log above, unconditional (converters have no metal floor worth gating on).
	if (bt == int(Task::BuildType::CONVERT) && (task.buildDef !is null)) {
		const AIFloat3 at = task.GetBuildPos();
		AiLog(Factory::T() + "apex: convert-task-added " + task.buildDef.GetName()
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
		// The ask dies with the TASK too: a reactor ask that never produced a
		// nanoframe leaves no unit whose death could give it back (NoteEcoGone
		// runs from AiUnitDestroyed), so asked > count wedged
		// ReactorPipelineOpen() closed for the rest of the game -- the
		// no-fusion player. A removal WITH a nanoframe keeps its ask: the
		// frame is a unit and its death routes through NoteEcoGone.
		if (!done && (task.target is null) && IsReactorDef(task.buildDef.GetName())
			&& (gFusionsAsked > 0))
		{
			--gFusionsAsked;
			AiLog(Factory::T() + "apex: reactor ask returned -- task died unstarted");
		}
	}
	// Paired with convert-task-added above; only the >=2000-metal reactor tier
	// was previously logged, leaving converters (the def actually implicated in
	// the 2026-08-14 "energy wasted, nothing converts" investigation) invisible.
	if (bt == int(Task::BuildType::CONVERT) && (task.buildDef !is null)) {
		array<CCircuitUnit@>@ cHad = task.GetUnits();
		const AIFloat3 cAt = task.GetBuildPos();
		const bool cHasWorker = (cHad !is null) && (cHad.length() > 0) && (cHad[0] !is null);
		AiLog(Factory::T() + "apex: convert-task-removed " + task.buildDef.GetName()
			+ " done=" + (done ? "1" : "0")
			+ " hadNanoframe=" + ((task.target !is null) ? "1" : "0")
			+ " workers=" + ((cHad !is null) ? cHad.length() : 0)
			+ " unit=" + (cHasWorker ? int(cHad[0].id) : -1)
			+ " at=" + int(cAt.x) + "," + int(cAt.z));
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

// Commander pack spacing -- see CommIdleAttribute's publish block.
const string TV_COMMX = "commx";
const string TV_COMMZ = "commz";
const float COMM_SPACING = 500.f;

// Is another ally commander inside chain-blast range of ours? Out-param is
// the nearest one's position, for steering away from it.
bool AllyCommNear(AIFloat3& out other)
{
	CCircuitUnit@ u = gComm;
	if (u is null)
		return false;
	const float gap = ai.GetTunable("apex_comm_spacing", COMM_SPACING);
	const AIFloat3 cp = u.GetPos(ai.frame);
	const array<int>@ teams = ai.GetTeamIds();
	float best = 1.0e18f;
	bool found = false;
	for (uint i = 0; i < teams.length(); ++i) {
		if (teams[i] == ai.teamId)
			continue;
		const float x = ai.ReadTeamValue(teams[i], TV_COMMX, -1.0e9f);
		const float z = ai.ReadTeamValue(teams[i], TV_COMMZ, -1.0e9f);
		if (x < -1.0e8f)
			continue;
		AIFloat3 p(x, 0.f, z);
		const float d = cp.distance2D(p);
		if ((d < gap) && (d < best)) {
			best = d;
			other = p;
			found = true;
		}
	}
	return found;
}
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

// main.as now implements AiUnitDestroyed and logs death directly. This
// heartbeat still earns its keep: it shows "health was still N%" or "already
// retreating" in the seconds BEFORE that one-shot line, which the death line
// alone can't.
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
	// Every commander publishes its position: a commander death explosion
	// chains at pack range, and four commanders died in ONE frame at ~280-elmo
	// spacing when their retreats converged on the same last haven (match
	// 20260815-154651, the 13-minute 8v8 loss). Spacing needs to know where
	// the OTHERS are, and this blackboard is the only cross-player channel.
	{
		const AIFloat3 cp = u.GetPos(ai.frame);
		ai.PublishTeamValue(TV_COMMX, cp.x);
		ai.PublishTeamValue(TV_COMMZ, cp.z);
	}
	// The periodic print lives HERE, not only in the commander's AiMakeTask
	// path: a commander wedged on a task it never leaves stops entering
	// AiMakeTask entirely, and the log going silent at exactly the moment it
	// wedges is what kept this class of bug invisible. Same throttle either way.
	if (ai.frame >= gNextCommDiag) {
		CommDiag();
		const AIFloat3 cp = u.GetPos(ai.frame);
		const int ty = (t is null) ? -1 : int(t.GetType());
		AiLog(Factory::T() + "apex: comm-now task=" + ty
			+ " bt" + ((ty == int(Task::Type::BUILDER)) ? int(t.GetBuildType()) : -1)
			+ " q=" + q + " pos=" + int(cp.x) + "," + int(cp.z)
			+ " hp=" + formatFloat(u.GetHealthPercent() * 100.f, "", 0, 0)
			+ " infl=" + formatFloat(ai.GetEnemyInflAt(cp), "", 0, 2));
	}
	if ((t is null) || (t.GetType() == Task::Type::IDLE)
		|| (t.GetType() == Task::Type::NIL))
	{
		++gCDNoTask;
		// CRetreatTask is not an IBuilderTask, so nothing re-evaluates it every
		// ~1s the way a builder task is -- a commander that goes idle while
		// AiUnitIdle is slow to re-fire just sits there. Measured 2026-08-15:
		// a commander under continuous enemy influence (1-99, never near zero)
		// sampled noTask on 55% of ticks over a ten-minute stretch -- "standing
		// around doing nothing" while apex: commander leaving kept logging.
		// Force it back into a task directly rather than waiting.
		// Same apex_comm_flee_influence, and the same Factory::gHaveT2 gate as
		// CommanderTask() in rules_commander.as -- this is a SEPARATE read of
		// the tunable, not shared code, and missing the gate here left the
		// commander getting force-parked into Retreat pre-T2 off any nearby
		// influence even after CommanderTask() itself was gated, since this
		// watchdog fires independently whenever the commander samples noTask.
		const float fleeInfl = Factory::gHaveT2 ? ai.GetTunable("apex_comm_flee_influence", 0.01f) : 0.f;
		if ((fleeInfl > 0.f) && (ai.GetEnemyInflAt(u.GetPos(ai.frame)) > fleeInfl)) {
			if (++gCommNoTaskStreak >= COMM_NOTASK_TICKS) {
				gCommNoTaskStreak = 0;
				IUnitTask@ fresh = Retreat(u);
				if (fresh !is null) {
					aiBuilderMgr.AssignTask(u, fresh);
					++gCommForced;
					AiLog(Factory::T() + "apex: commander forced back onto retreat, "
						+ gCDNoTask + " noTask samples (#" + gCommForced + ")");
				}
			}
		} else {
			gCommNoTaskStreak = 0;
		}
		gCommRetreatStreak = 0;
	} else if (t.GetType() == Task::Type::RETREAT) {
		++gCDOther;
		// A PACKED retreat is broken at once, not on the slow timer: the
		// haven convergence is what stacks commanders into one chain blast.
		{
			AIFloat3 packed;
			if (AllyCommNear(packed)) {
				gCommRetreatStreak = 0;
				AiLog(Factory::T() + "apex: commander leaving the pack -- ally "
					+ "commander " + int(u.GetPos(ai.frame).distance2D(packed))
					+ " elmos away");
				t.Abort();
				return;
			}
		}
		// CRetreatTask ends only at >98% health, or zero enemy influence at
		// the commander's own tile -- with enemies loitering near home neither
		// may ever arrive, and a unit holding a task is never re-elected, so a
		// pinned retreat holds the commander idle indefinitely. Abort it and
		// let the pipeline decide again; CommanderTask re-issues the flee if
		// the ground is still genuinely worth leaving.
		if (++gCommRetreatStreak >= int(ai.GetTunable("apex_comm_retreat_ticks",
				float(COMM_RETREAT_TICKS))))
		{
			gCommRetreatStreak = 0;
			++gCommRetreatCut;
			AiLog(Factory::T() + "apex: commander retreat held too long -- "
				+ "re-electing (#" + gCommRetreatCut + ")");
			t.Abort();
		}
	} else if (t.GetType() != Task::Type::BUILDER) {
		++gCDOther;
		gCommRetreatStreak = 0;
	} else if (q > 0) {
		++gCDOrdered;
		gCommStuck = 0;
		gCommRetreatStreak = 0;
	} else {
		++gCDWaiting;
		gCommRetreatStreak = 0;
		// Holding a build task with NO engine order. Briefly that is a pending
		// path query; sustained, the task is one the commander will never start,
		// and it will hold it forever because HoldWorkInProgress keeps returning
		// it. Dropping it puts the commander back through the pipeline.
		if (++gCommStuck >= int(ai.GetTunable("apex_comm_stuck", COMM_STUCK_TICKS))) {
			gCommStuck = 0;
			++gCommUnstuck;
			const AIFloat3 cp = u.GetPos(ai.frame);
			const AIFloat3 at = t.GetBuildPos();
			AiLog(Factory::T() + "apex: commander stuck on bt"
				+ t.GetBuildType() + " with no order -- dropping it (#"
				+ gCommUnstuck + ") comm=" + int(cp.x) + "," + int(cp.z)
				+ " site=" + int(at.x) + "," + int(at.z) + " def="
				+ ((t.buildDef !is null) ? t.buildDef.GetName() : "?"));
			t.Abort();
		}
	}
}

}  // namespace Builder
