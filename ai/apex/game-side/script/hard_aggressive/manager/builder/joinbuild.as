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
// For JoinDuplicateBuild, "already under way" means the task has an ASSIGNEE,
// not a nanoframe: IBuilderTask::AssignTo runs the moment the builder is given
// the job, and the whole walk to the site happens before a single nanoframe
// exists. A check for standing structures or for buildDef.count would miss
// exactly the window that rule is for. JoinTaskFor is a different question --
// its caller is about to ENQUEUE a second task, so a queued-but-unassigned task
// is already enough to make that enqueue a duplicate, and it takes one.

// Below this, serializing costs more in walk time than it saves. Solar 155 and
// wind 43 are meant to be built several at once; a construction turret is 210,
// a T1 lab 500.
const float JOIN_MIN_COST = 200.f;

// Same reasoning as REROUTE_RANGE: the script cannot ask whether a position is
// reachable, and a constructor on the far side of the map building its own is
// better than one walking across the map to help.
const float JOIN_RANGE = 1500.f;

// How much nearer an already-assigned task is treated as being, when choosing
// between one somebody is working and one merely sitting in the queue.
const float JOIN_ASSIGNED_BIAS = 400.f;

// How many builders one task may hold, from what the ECONOMY can feed -- never a
// flat number and never a clock.
//
// A lathe pulls a roughly constant metal/s while it is building, set by its
// buildSpeed and not by what it is building: the cost only decides how LONG the
// drain lasts. So the number of lathes an economy can keep fed is income/drain,
// and it does not depend on the building's cost at all. `cost` stays in the
// signature because JOIN_MIN_COST callers already have it and a future
// per-target rule would want it.
//
// Above this cap the extra builders are not slower, they are stalling: the
// metal is spent either way, so the only thing more lathes on one site can buy
// once income is exhausted is taking metal off everything else.
const float JOIN_BUILDER_DRAIN = 7.0f;  // metal/s one constructor pulls
const uint  JOIN_BUILDERS_MIN = 2;      // below 2 the rule could never fire

uint JoinBuilderCap(float cost)
{
	const float drain = ai.GetTunable("apex_join_drain", JOIN_BUILDER_DRAIN);
	if (drain <= 0.f)
		return JOIN_BUILDERS_MIN;
	const float want = aiEconomyMgr.metal.income / drain;
	if (want <= float(JOIN_BUILDERS_MIN))
		return JOIN_BUILDERS_MIN;
	return uint(want);
}

// How close counts as "the same ground" for SpotCollides, below. Comfortably
// bigger than any T1/T2 economy building footprint (armadvsol/armsolar are a
// few dozen elmos across) so a real second site a short walk away is untouched.
const float JOIN_COLLIDE_RANGE = 150.f;

// Is `spot` already where a queued same-class task sits, REGARDLESS of that
// task's builder cap? JoinTaskFor answers "should I help", which is capped by
// what the economy can feed; this answers "would I be building on top of
// something already ordered", which a cap must never excuse.
//
// Measured live, 2026-08-13, apexearth watching: cap=2 (income-floor) was hit
// by two builders walking to the same armadvsol before either had started the
// physical nanoframe, so ai.FindBuildSiteNear -- which only sees REAL engine
// state, not our own queued-but-not-yet-under-construction tasks -- kept
// returning the identical empty-looking coordinate to every builder refused a
// join for "nocap". Six duplicate enqueues landed on one tile in three
// real-time seconds. The cap was doing its job; nothing was stopping the
// EXCESS builders from re-discovering the same "empty" ground instead of
// either waiting or finding different ground.
bool SpotCollides(const CCircuitDef@ want, const AIFloat3& in spot)
{
	if (want is null)
		return false;
	const float sq = JOIN_COLLIDE_RANGE * JOIN_COLLIDE_RANGE;
	for (uint i = 0; i < gJoinTasks.length(); ++i) {
		IUnitTask@ cand = gJoinTasks[i];
		if (cand is null)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		if (spot.SqDistance2D(where) < sq)
			return true;
	}
	return false;
}

// HOW MANY BUILDERS, TOTAL ACROSS EVERY SITE OF ONE DEF, may be working AT
// THE SAME TIME -- the same JoinBuilderCap formula (income/drain) already
// verified tonight for a SINGLE site, now applied as a TEAM-WIDE ceiling
// instead. SpotCollides only refused a second building on the SAME ground;
// nothing stopped a capped-out site from handing its next idle builder a
// BRAND NEW site instead of making it wait, because per-site capping alone
// has no memory of how many OTHER sites of the same def already exist.
// apexearth, watching live, on the build that already shipped SpotCollides:
// "6 advanced solars being made at the same time... they start making more
// while others are obviously already in progress." Measured in that same
// running game: team t2 stood 6 armadvsol at once, team t7 stood 8 -- all at
// genuinely different tiles, so SpotCollides never saw a reason to refuse
// any single one of them.
//
// This is the exact "K items in parallel land at KT/B, nothing pays until
// then" argument from tonight's reactor fix, generalized past reactors: an
// economy that can usefully feed `income/drain` LATHES on one kind of
// building cannot usefully feed more than that spread across five buildings
// instead of one. Below the cap, a second (or third) site is free to open --
// the ladder's own distance/bias preference decides whether that is more
// efficient than piling every builder onto the first. Above it, a new site
// is not more economy, it is the same builders arriving later.
uint BusyOnDef(const CCircuitDef@ want)
{
	if (want is null)
		return 0;
	uint total = 0;
	for (uint i = 0; i < gJoinTasks.length(); ++i) {
		IUnitTask@ cand = gJoinTasks[i];
		if ((cand is null) || (cand.buildDef is null) || (cand.buildDef.id != want.id))
			continue;
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if (busy !is null)
			total += busy.length();
	}
	return total;
}

int gSiteBlockedByCap = 0;
int gSiteBlockedByGround = 0;
int gNextSiteBlockLog = 0;

// One call for the whole "should a NEW site of this def start" question:
// combines the team-wide builder ceiling above with SpotCollides's ground
// check, so every caller asks one thing instead of two in a particular
// order.
bool SiteBlocked(const CCircuitDef@ want, const AIFloat3& in spot)
{
	if (want is null)
		return true;
	const uint busy = BusyOnDef(want);
	const uint cap = JoinBuilderCap(want.costM);
	if (busy >= cap) {
		++gSiteBlockedByCap;
		if (ai.frame >= gNextSiteBlockLog) {
			gNextSiteBlockLog = ai.frame + 10 * SECOND;
			AiLog(Factory::T() + "apex: site-blocked " + want.GetName()
				+ " busy=" + busy + " cap=" + cap
				+ " byCap=" + gSiteBlockedByCap + " byGround=" + gSiteBlockedByGround);
		}
		return true;
	}
	if (SpotCollides(want, spot)) {
		++gSiteBlockedByGround;
		return true;
	}
	return false;
}

array<IUnitTask@> gJoinTasks;
int gConJoined = 0;
int gNextJoinLog = 0;

// WHY A JOIN WAS REFUSED. Only successes were logged, so a duplicate reactor
// could not be attributed to any of the three conditions below; per-reason
// totals are what let ONE game answer that, since the line itself is sampled.
int gConJoinMiss = 0;
int gMissNoCap = 0;       // the task already holds its builder cap
int gMissFar = 0;         // nearest candidate sits beyond JOIN_RANGE
int gMissUnassigned = 0;  // same-class OTHER def queued, and nobody is on it
int gMissNone = 0;        // no task for this def at all -- the ordinary case
int gNextJoinMissLog = 0;

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
//
// NO cost floor here. JOIN_MIN_COST says "not worth walking across the map to
// ASSIST a cheap building" -- JoinTaskFor and JoinDuplicateBuild still apply it
// themselves. Registration is a different question: is this task ON THE BOARD
// AT ALL for SpotCollides to check literal position collisions against.
// Measured live, 2026-08-13: armsolar (155 metal, under the old 200 floor here)
// piled up to 6 duplicates on ONE TILE within 56 frames, because a task that
// was never registered could never be found colliding with anything.
void JoinRegister(IUnitTask@ task)
{
	if (!JoinEligibleType(task.GetBuildType()))
		return;
	if (task.buildDef is null)
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

// The same search, for rules that ENQUEUE rather than screen an offer. Returns
// the best existing task for `want` within JOIN_RANGE and under its builder
// cap, or null if there is none. A task nobody has been given yet still counts:
// the caller's alternative is a SECOND task for the same thing.
//
// `spot` is the SITE the caller is about to build at, not the unit's current
// position. apexearth, watching, at two different games: "I am actively seeing
// us build 5 AFUS at the same time" and "I still see multiple advanced solars
// being built... a single team going off making ~4 of them all at the same
// time." Measured in matches/20260813-222958: five idle constructors scattered
// around one base each called this with THEIR OWN position, found nothing
// within JOIN_RANGE of themselves, and each then independently computed a spot
// via the same pack/band logic -- landing the five spots within ~200 elmos of
// each other despite the five builders not being near each other at all. The
// question this function answers is "is the SITE I am about to build a
// duplicate", which only the site's own position can answer; the builder's
// distance from it is a walk-cost concern for a caller with no spot yet, not
// this one.
IUnitTask@ JoinTaskFor(const CCircuitDef@ want, CCircuitUnit@ unit, const AIFloat3& in spot)
{
	if ((want is null) || (want.costM < JOIN_MIN_COST) || (unit is null))
		return null;
	const uint cap = JoinBuilderCap(want.costM);
	const AIFloat3 here = spot;
	IUnitTask@ best = null;
	float bestDist = 0.f;
	float bestScore = JOIN_RANGE;
	// The refusal of the NEAREST candidate we could not take. bestScore only
	// shrinks once `best` is set, so while best is null every "far" rejection
	// really is beyond JOIN_RANGE rather than merely second-nearest.
	string why = "none";
	float whyDist = 0.f;
	uint whyBusy = 0;
	bool whySet = false;
	for (uint i = 0; i < gJoinTasks.length(); ++i) {
		IUnitTask@ cand = gJoinTasks[i];
		if (cand is null)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if (has is null)
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		const uint nbusy = (busy is null) ? 0 : busy.length();
		// Same reactor CLASS counts as the same job. HomeEnergy re-ranks fus
		// against afus every call, so each rung was blind to the other rung's
		// in-progress work and both got started. Only a task somebody is
		// ALREADY on may match across defs: assisting a live nanoframe needs no
		// build option, but starting one does, and a commander that can build
		// armfus cannot build armafus.
		if (has.id != want.id) {
			if (!IsFusion(has) || !IsFusion(want))
				continue;
			if (nbusy == 0) {
				const float d = here.distance2D(where);
				if (!whySet || (d < whyDist)) {
					whySet = true;
					why = "unassigned";
					whyDist = d;
					whyBusy = 0;
				}
				continue;
			}
		}
		const float dist = here.distance2D(where);
		// An assigned task is worth joining over an unassigned one at a similar
		// distance: somebody is already walking to it, so the metal starts
		// flowing sooner. Treating it as JOIN_ASSIGNED_BIAS nearer keeps that a
		// preference rather than an override -- a much closer queued site still
		// wins.
		const float score = (nbusy > 0) ? (dist - JOIN_ASSIGNED_BIAS) : dist;
		string bad = "";
		if (nbusy >= cap)
			bad = "nocap";
		else if (dist >= JOIN_RANGE)
			bad = "far";
		else if (score >= bestScore)
			bad = "far";
		if (bad != "") {
			if (!whySet || (dist < whyDist)) {
				whySet = true;
				why = bad;
				whyDist = dist;
				whyBusy = nbusy;
			}
			continue;
		}
		@best = cand;
		bestScore = score;
		bestDist = dist;
	}
	if (best !is null) {
		++gConJoined;
		if (ai.frame >= gNextJoinLog) {
			gNextJoinLog = ai.frame + 5 * SECOND;
			AiLog(Factory::T() + "apex: con-join(direct) " + unit.circuitDef.GetName()
				+ " -> " + want.GetName() + " dist=" + formatFloat(bestDist, "", 0, 0)
				+ " cap=" + cap + " joined=" + gConJoined);
		}
		return best;
	}
	++gConJoinMiss;
	if (why == "nocap")
		++gMissNoCap;
	else if (why == "far")
		++gMissFar;
	else if (why == "unassigned")
		++gMissUnassigned;
	else
		++gMissNone;
	if (ai.frame >= gNextJoinMissLog) {
		gNextJoinMissLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-join-miss " + unit.circuitDef.GetName()
			+ " -> " + want.GetName() + " why=" + why
			+ " dist=" + formatFloat(whyDist, "", 0, 0)
			+ " cap=" + cap + " busy=" + whyBusy
			+ " cost=" + formatFloat(want.costM, "", 0, 0)
			+ " miss=" + gConJoinMiss
			+ " nocap=" + gMissNoCap + " far=" + gMissFar
			+ " unassigned=" + gMissUnassigned + " none=" + gMissNone);
	}
	return null;
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
		// Same reactor class counts as the same job; the assignee this loop
		// already demands below is what makes a cross-def join safe (assisting
		// a nanoframe needs no build option, starting one does).
		if ((has is null)
			|| ((has.id != want.id) && !(IsFusion(has) && IsFusion(want))))
		{
			continue;
		}
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
