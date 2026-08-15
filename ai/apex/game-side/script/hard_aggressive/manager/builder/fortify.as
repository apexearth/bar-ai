namespace Builder {

// A constructor that keeps getting shot will not expand, whatever the threat map
// says at the instant we ask. History rather than prediction: ThreatFor tests
// the build site itself, and a constructor can be struck by something outside
// that tile. Losing health is not a forecast.
// (declared above FenceWanted, which needs it)
const int   TROUBLE_WINDOW  = 90 * SECOND;   // quiet for this long and the count clears
const int   FORTIFY_TIME    = 120 * SECOND;  // how long a struck con stays dug in
const int   FORTIFY_PERIOD  = 20 * SECOND;   // one tower per con per this
const float TROUBLE_HP_DROP = 0.02f;
const uint  CON_TRACK_MAX   = 48;
const int   CON_TRACK_STALE = 3 * MINUTE;

array<int>   gConId;
array<int>   gConHits;
array<int>   gConHurtAt;
array<float> gConHp;
array<int>   gConDigUntil;
array<int>   gConNextDig;
array<int>   gConTouch;
array<int>   gConNextRepair;   // per-bot gate for RezzerRepairNearby -- see there
int gConFortified = 0;
int gNextFortifyLog = 0;

// AiUnitRemoved does not fire for every tracked constructor, so dead ones are
// dropped by staleness rather than on death.
int ConSlot(CCircuitUnit@ unit)
{
	const int id = unit.id;
	for (uint i = 0; i < gConId.length(); ++i) {
		if (gConId[i] == id) {
			gConTouch[i] = ai.frame;
			return int(i);
		}
	}
	if (gConId.length() >= CON_TRACK_MAX) {
		for (int i = int(gConId.length()) - 1; i >= 0; --i) {
			if (ai.frame - gConTouch[i] > CON_TRACK_STALE) {
				gConId.removeAt(i);
				gConHits.removeAt(i);
				gConHurtAt.removeAt(i);
				gConHp.removeAt(i);
				gConDigUntil.removeAt(i);
				gConNextDig.removeAt(i);
				gConTouch.removeAt(i);
				gConNextRepair.removeAt(i);
			}
		}
	}
	gConId.insertLast(id);
	gConHits.insertLast(0);
	gConHurtAt.insertLast(0);
	gConHp.insertLast(unit.GetHealthPercent());
	gConDigUntil.insertLast(0);
	gConNextDig.insertLast(0);
	gConTouch.insertLast(ai.frame);
	gConNextRepair.insertLast(0);
	return int(gConId.length()) - 1;
}

void ConStrikeAt(int i)
{
	++gConHits[i];
	gConHurtAt[i] = ai.frame;
	if ((gConHits[i] >= TROUBLE_HITS) && (ai.frame >= gConDigUntil[i]))
		gConDigUntil[i] = ai.frame + FORTIFY_TIME;
}

// Being refused a site counts the same as being shot at it: both say this
// constructor is not getting to expand here.
void ConStrike(CCircuitUnit@ unit)
{
	ConStrikeAt(ConSlot(unit));
}

bool ConDugIn(CCircuitUnit@ unit)
{
	const int i = ConSlot(unit);
	if ((gConHits[i] > 0) && (ai.frame - gConHurtAt[i] > TROUBLE_WINDOW))
		gConHits[i] = 0;
	const float hp = unit.GetHealthPercent();
	if (hp < gConHp[i] - TROUBLE_HP_DROP)
		ConStrikeAt(i);
	gConHp[i] = hp;
	return ai.frame < gConDigUntil[i];
}

// Wounded units already have repair tasks waiting; the constructors were busy
// buying economy.
//
// Two engine paths raise them, both for units we own: CRetreatTask::AssignTo
// enqueues TaskB::Repair(HIGH) for every non-air unit that starts retreating,
// and IFighterTask::OnUnitDamaged enqueues one at NOW for a `heavy` under 90%.
// Both land in CBuilderManager's REPAIR queue, and the ONLY way a constructor is
// ever elected onto one is aiBuilderMgr.DefaultMakeTask -- which sits below the
// optional economy rules in AiMakeTask, so an idle constructor reaches the
// converter first and the queue is never read.
//
// AiTaskAdded is the only place a repair task is visible from here: nothing
// enumerates the task queue and nothing enumerates friendly units. IUnitTask is
// refcounted so a held handle keeps the object alive, and every removal funnels
// through DequeueTask, which calls AiTaskRemoved -- the same contract gMexTasks
// relies on. CBuilderManager::Enqueue returns the existing task for a target
// that already has one, before TaskAdded, so a target cannot be listed twice.
//
// MOBILE targets only. Damaged buildings raise a repair task constantly, and
// including them would hold the gate open for the whole game.
array<IUnitTask@> gArmyRepairs;

// Only constructors near the casualty stand down; the rest of the base keeps
// building. Far enough to cover a fight the constructor is working behind,
// short enough that the walk is not the cost.
const float REPAIR_REACH = 1200.f;
int gRepairHeld = 0;
int gNextRepairLog = 0;

// EXPANSION DIAGNOSTIC. Every claim about why we stop expanding has so far been
// inferred. This reports, for one representative constructor, the three facts
// that decide it: whether the engine can still offer us a mex spot at all, what
// the bank is doing, and how many workers exist to take it.
int gNextExpandLog = 0;
void ExpandDiag()
{
	if (ai.frame < gNextExpandLog)
		return;
	gNextExpandLog = ai.frame + 30 * SECOND;
	CCircuitDef@ mex = SideDef3(armmex, cormex, legmex);
	int spot = -2;
	AIFloat3 probe = gHomeSet ? gHomePos : AIFloat3(0, 0, 0);
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(Crew::gId[i]));
		if (u is null)
			continue;
		spot = aiEconomyMgr.FindOpenMexSpot(u, u.GetPos(ai.frame));
		probe = u.GetPos(ai.frame);
		break;
	}
	// What every tracked builder is actually holding. "Full bank, spots open,
	// nothing built" has three different causes -- no task, a task it cannot
	// progress, or a task that is not economic -- and they are indistinguishable
	// from the outside.
	int idle = 0, onMex = 0, onOther = 0;
	string kinds = "";
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Crew::gId[i]));
		if (c is null)
			continue;
		IUnitTask@ t = c.task;
		// CCircuitUnit::task points at the shared CIdleTask singleton for a builder
		// with nothing to do, so it is never null and `t is null` cannot count an
		// idle unit. AskingForNewWork is the same IDLE/NIL/WAIT test the ladder
		// itself gates on.
		if ((t is null) || Brain::AskingForNewWork(c)) {
			++idle;
			continue;
		}
		// A task with no build SITE is not the same as no task -- reclaim, guard
		// and patrol all have none. Counting them together hid which of the two
		// was happening.
		const string k = SiteBuildName(t);
		if (k == "") {
			++onOther;
			if (kinds.length() < 60)
				kinds += "bt" + t.GetBuildType() + " ";
			continue;
		}
		if (t.GetBuildType() == Task::BuildType::MEX) {
			++onMex;
		} else {
			++onOther;
			if (kinds.length() < 60)
				kinds += k + " ";
		}
	}
	// FACTORY0 NANO1 STORE2 PYLON3 ENERGY4 GEO5 GEOUP6 DEFENCE7 -- census of the
	// pool, so an unworked backlog can be told apart by what it is made of.
	string census = "";
	const array<string> tn = {"fac","nano","store","pylon","energy","geo","geoup","def",
			"t8","t9","t10","t11","t12","t13","t14","t15"};
	for (int t = 0; t < 16; ++t) {
		const uint c = aiBuilderMgr.GetTaskCountOf(t);
		if (c > 0)
			census += tn[t] + "=" + c + " ";
	}
	AiLog(Factory::T() + "apex: expand-diag pool[" + census + "] idle=" + idle
		+ " onMex=" + onMex + " onOther=" + onOther + " [" + kinds + "]"
		+ " spot=" + spot
		+ " tasks=" + aiBuilderMgr.GetBuildTaskCount()
		+ " canEnq=" + (aiBuilderMgr.CanEnqueueTask(8) ? "1" : "0")
		+ " mex=" + ((mex is null) ? -1 : mex.count)
		+ " workers=" + aiBuilderMgr.GetWorkerCount()
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0)
		+ " full=" + (aiEconomyMgr.isMetalFull ? "1" : "0")
		+ " phase=" + Factory::gLastPhase
		+ " haveT2=" + (Factory::gHaveT2 ? "1" : "0"));
}

bool RepairNear(CCircuitUnit@ unit)
{
	if (gArmyRepairs.length() == 0)
		return false;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return false;
	for (uint i = 0; i < gArmyRepairs.length(); ++i) {
		IUnitTask@ cand = gArmyRepairs[i];
		if (cand is null)
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where) || (here.distance2D(where) > REPAIR_REACH))
			continue;
		// Somebody is already on it. Self-limiting: the first constructor to take
		// the task closes the gate for everyone else.
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy is null) || (busy.length() == 0))
			return true;
	}
	return false;
}

// A damaged STATIC structure (e.g. an HLT under fire) already gets a native
// REPAIR task -- CBuilderManager::InitHandlers' buildingDamagedHandler enqueues
// one unconditionally on damage, unlike the mobile-unit case RezzerRepairNearby
// exists for. But nobody ever picks it up: CBuilderManager::MakeTask's own
// ranking skips any non-NOW-priority task sitting on ANY negative influence at
// all (a bare boolean, not a graded threat check), so a structure actively being
// shot at is never OFFERED via DefaultMakeTask -- and separately, RepairTask.cpp's
// CanAssignTo hard-excludes IsRoleComm() from repair tasks, so the commander
// could not take it even when reachable. AssignTask (TaskModule.cpp) never
// re-checks CanAssignTo when the script hands back a task directly, so -- same as
// RezzerRepairNearby -- enqueuing the SAME target explicitly bypasses both.
IUnitTask@ RepairStructureNearby(CCircuitUnit@ unit)
{
	if (gStructRepair.length() == 0)
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return null;
	CCircuitUnit@ best = null;
	float bestDist = REPAIR_REACH;
	for (uint i = 0; i < gStructRepair.length(); ++i) {
		IUnitTask@ cand = gStructRepair[i];
		if (cand is null)
			continue;
		CCircuitUnit@ target = cand.target;
		if (target is null)
			continue;
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy !is null) && (busy.length() > 0))
			continue;                       // already claimed
		const AIFloat3 where = target.GetPos(ai.frame);
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= bestDist)
			continue;
		// Same graded threshold every other reflex in this file uses -- repairing
		// a structure we already committed to is judged the same as answering any
		// other "something happening now", not a fresh investment into danger.
		if (ThreatFor(unit, where) > CON_THREAT_VETO)
			continue;
		bestDist = dist;
		@best = target;
	}
	if (best is null)
		return null;
	return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::HIGH, best));
}

}  // namespace Builder
