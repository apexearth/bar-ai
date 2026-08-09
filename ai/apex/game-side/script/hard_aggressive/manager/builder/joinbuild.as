namespace Builder {

// Two constructors starting the SAME building at the same moment.
//
// Nothing in the engine stops this. CBuilderManager::MakeBuilderTask picks the
// cheapest-to-reach candidate out of the queue, and the queue can legitimately
// hold several tasks for one buildDef (MakeEconomyTasks and the build chains
// both enqueue independently). Two idle constructors evaluated a few frames
// apart therefore take two DIFFERENT tasks for the same def and each walks off
// to its own site. IBuilderTask::CanAssignTo would have refused the second
// builder on ONE task once it had enough build power -- it has no opinion at all
// about a second task.
//
// Joining the one already under way is a serialization, not a cancellation: the
// duplicate task stays in the queue and gets built later, by whoever is idle
// then. Nothing is enqueued here and no constructor time is created, so this is
// a STOP in the sense of CHANGES.md 2026-08-01 -- it only redirects an offer the
// engine already made.
//
// "Already under way" means the task has an ASSIGNEE, not a nanoframe:
// IBuilderTask::AssignTo runs the moment the builder is given the job, and the
// whole walk to the site happens before a single nanoframe exists. A check for
// standing structures or for buildDef.count would miss exactly the window this
// rule is for.

// Below this, serializing costs more in walk time than it saves. Solar 155 and
// wind 43 are meant to be built several at once; a construction turret is 210,
// a T1 lab 500.
const float JOIN_MIN_COST = 200.f;

// Same reasoning as REROUTE_RANGE: the script cannot ask whether a position is
// reachable, and a constructor on the far side of the map building its own is
// better than one walking across the map to help.
const float JOIN_RANGE = 1500.f;

// How many builders one task may hold, from how cheap the building is relative
// to what we earn -- never a flat number and never a clock.
//
// cost/income is the seconds of our WHOLE income the building costs. A rich
// player pays that off quickly and is limited by build power, so more lathes on
// it is free speed; a poor player is limited by metal, and extra builders just
// stand there sharing the same trickle. So builders fall as that ratio rises:
//
//   builders = JOIN_AFFORD_SECONDS / (cost / income)
//
// apexearth: "if something is 3000 metal to create and we make ~100 metal per
// second then probably we'd be happy to put 5 or more builders on it" -- 3000
// at 100/s is 30 income-seconds, and 150/30 is 5. At the benchmark's 10/s the
// same building is 300 income-seconds and gets the floor of 2.
const float JOIN_AFFORD_SECONDS = 150.f;
const uint  JOIN_BUILDERS_MIN = 2;   // below 2 the rule could never fire
const uint  JOIN_BUILDERS_MAX = 8;

uint JoinBuilderCap(float cost)
{
	if (cost < 1.f)
		return JOIN_BUILDERS_MIN;
	const float want = JOIN_AFFORD_SECONDS * aiEconomyMgr.metal.income / cost;
	if (want <= float(JOIN_BUILDERS_MIN))
		return JOIN_BUILDERS_MIN;
	if (want >= float(JOIN_BUILDERS_MAX))
		return JOIN_BUILDERS_MAX;
	return uint(want);
}

array<IUnitTask@> gJoinTasks;
int gConJoined = 0;
int gNextJoinLog = 0;

// Deliberately not MEX/MEXUP/GEO/GEOUP -- those are per-spot, two of them are
// two different spots, and stacking constructors on one is the opposite of what
// expansion wants (see SaferMex). Not DEFENCE either: two towers at two places
// on the front are both wanted. What is left is the set where a second one
// started at the same time is redundancy rather than coverage.
bool JoinEligibleType(int bt)
{
	return (bt == Task::BuildType::FACTORY)
		|| (bt == Task::BuildType::NANO)
		|| (bt == Task::BuildType::ENERGY)
		|| (bt == Task::BuildType::CONVERT)
		|| (bt == Task::BuildType::STORE)
		|| (bt == Task::BuildType::BUNKER)
		|| (bt == Task::BuildType::BIG_GUN)
		|| (bt == Task::BuildType::RADAR)
		|| (bt == Task::BuildType::SONAR);
}

// Same pattern as gMexTasks: AiTaskAdded is the only place a live task handle is
// visible, IUnitTask is refcounted so a held handle stays valid, and every
// removal funnels through DequeueTask -> AiTaskRemoved.
void JoinRegister(IUnitTask@ task)
{
	if (!JoinEligibleType(task.GetBuildType()))
		return;
	const CCircuitDef@ def = task.buildDef;
	if ((def is null) || (def.costM < JOIN_MIN_COST))
		return;
	gJoinTasks.insertLast(task);
}

void JoinForget(IUnitTask@ task)
{
	for (uint i = 0; i < gJoinTasks.length(); ++i) {
		if (gJoinTasks[i] is task) {
			gJoinTasks.removeAt(i);
			return;
		}
	}
}

IUnitTask@ JoinDuplicateBuild(CCircuitUnit@ unit, bool isComm, IUnitTask@ offer)
{
	if (isComm || (offer is null) || (offer.GetType() != Task::Type::BUILDER))
		return null;
	if (!JoinEligibleType(offer.GetBuildType()))
		return null;

	// Matching on the OFFERED def's id is the only proof available that this
	// unit can build the thing at all -- CCircuitDef exposes no CanBuild
	// binding. Same trick, and the same reason, as SaferMex.
	const CCircuitDef@ want = offer.buildDef;
	if ((want is null) || (want.costM < JOIN_MIN_COST))
		return null;

	array<CCircuitUnit@>@ mine = offer.GetUnits();
	if ((mine !is null) && (mine.length() > 0))
		return null;  // this offer is the one under way; joining it is the default

	const uint cap = JoinBuilderCap(want.costM);
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestDist = JOIN_RANGE;
	for (uint i = 0; i < gJoinTasks.length(); ++i) {
		IUnitTask@ cand = gJoinTasks[i];
		if ((cand is null) || (cand is offer))
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy is null) || (busy.length() == 0) || (busy.length() >= cap))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= bestDist)
			continue;
		if (ThreatFor(unit, where) > CON_THREAT_VETO)
			continue;
		@best = cand;
		bestDist = dist;
	}
	if (best is null)
		return null;

	++gConJoined;
	if (ai.frame >= gNextJoinLog) {
		gNextJoinLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-join " + unit.circuitDef.GetName()
			+ " -> " + want.GetName()
			+ " dist=" + formatFloat(bestDist, "", 0, 0)
			+ " cap=" + cap
			+ " joined=" + gConJoined);
	}
	return best;
}

}  // namespace Builder
