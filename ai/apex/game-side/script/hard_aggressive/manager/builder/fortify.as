namespace Builder {

// A constructor that keeps getting shot will not expand, whatever the threat map
// says at the instant we ask. apexearth: "if a con has to retreat too much in its
// recent history it should just go into safety and make defenses. Because at that
// point it's unable to expand due to threats."
//
// History rather than prediction, because prediction demonstrably misses:
// ContestDefence above fires off ThreatFor at the build site, and in a watched
// 20-minute game constructors died with con-veto firing ZERO times -- the shooter
// is outside the tile being tested. Losing health is not a forecast.
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

IUnitTask@ Fortify(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	const int i = ConSlot(unit);
	if (ai.frame < gConNextDig[i])
		return null;
	CCircuitDef@ tower = ContestTower(unit);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	AIFloat3 spot;
	if (!StandoffPos(unit, unit.GetPos(ai.frame), spot))
		return null;
	// The bound. Without it this is the version that was reverted -- but the bar
	// now rises with how hard this spot is being contested.
	if (!AreaNeedsDefence(spot, FenceWanted(gConHits[i])))
		return null;
	// ...and the same policy every other placement answers to. A constructor
	// being shot at says WHERE trouble is; it does not say we can afford another
	// tower, nor that this spot is the front. See Military::DefenceAllowedAt.
	if (!Military::DefenceAllowedAt(spot))
		return null;
	// Dig-ins place where the constructor is standing, which is the other half of
	// the heap the blob audit keeps flagging. See Builder::TooCrowded.
	if (TooCrowded(spot))
		return null;
	IUnitTask@ dig = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, spot, DEF_SHAKE));
	if (dig is null)
		return null;
	NoteDigOrder(spot);
	gConNextDig[i] = ai.frame + FORTIFY_PERIOD;
	++gConFortified;
	if (ai.frame >= gNextFortifyLog) {
		gNextFortifyLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-dig " + unit.circuitDef.GetName()
			+ " hits=" + gConHits[i] + " -> " + tower.GetName()
			+ " fence=" + Military::FenceCountNear(spot, DIG_AREA)
			+ " here=" + DefenceAround(spot)
			+ " fortified=" + gConFortified);
	}
	return dig;
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
		if (t is null) {
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

}  // namespace Builder
