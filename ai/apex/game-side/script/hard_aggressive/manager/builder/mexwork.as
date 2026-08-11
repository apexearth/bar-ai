namespace Builder {

// Live MEX build tasks, so a refused one can be traded for a colder one.
//
// The script cannot enumerate metal spots -- no CMetalManager type is registered
// -- and a MEX task built here would carry spotId -1, which CBMexTask hands
// straight to mexSpots[spotId]. AiTaskAdded is the only place a MEX task is ever
// visible. IUnitTask is refcounted, so a held handle keeps the object alive, and
// every removal funnels through DequeueTask, which calls AiTaskRemoved.
array<IUnitTask@> gMexTasks;

// How many extractor jobs are already outstanding. A function rather than a
// direct read of the array because main.as includes brain.as BEFORE builder.as,
// so a global declared here is not visible to the Brain -- functions are
// module-wide, globals are not.
//
// This is the bound on the Brain's expansion want. Without it that want, being
// the highest-value thing on the board by a factor of five, re-proposed on every
// call and enqueued 97 extractor tasks in a single game -- an unassigned task
// holds its slot for 300s and the engine's economy generator refuses new work
// above workers * 8, so the spam starves the very thing it is trying to buy.
uint OutstandingMexTasks()
{
	return gMexTasks.length();
}

// The script cannot ask whether a position is reachable, and the far side of the
// map usually is not.
const float REROUTE_RANGE = 3000.f;

// Same buildDef as the task the engine just offered this unit is the only proof
// available that the unit can build it: CCircuitDef exposes no CanBuild binding,
// and mex defs are per-constructor -- armck builds armmex, armack only armmoho.
IUnitTask@ SaferMex(CCircuitUnit@ unit, IUnitTask@ refused)
{
	const CCircuitDef@ want = refused.buildDef;
	if (want is null)
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestDist = REROUTE_RANGE;
	float bestThreat = 0.f;
	for (uint i = 0; i < gMexTasks.length(); ++i) {
		IUnitTask@ cand = gMexTasks[i];
		if ((cand is null) || (cand is refused))
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= bestDist)
			continue;
		const float heat = ThreatFor(unit, where);
		if (heat > CON_THREAT_VETO)
			continue;
		// Spreading over spots beats stacking constructors on one.
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy !is null) && (busy.length() > 0))
			continue;
		@best = cand;
		bestDist = dist;
		bestThreat = heat;
	}
	if (best is null)
		return null;
	++gConRerouted;
	if (ai.frame >= gNextRerouteLog) {
		gNextRerouteLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-reroute " + unit.circuitDef.GetName()
			+ " -> mex threat=" + formatFloat(bestThreat, "", 0, 0)
			+ " dist=" + formatFloat(bestDist, "", 0, 0)
			+ " rerouted=" + gConRerouted);
	}
	return best;
}

string armmex("armmex");
string cormex("cormex");
string legmex("legmex");

// apexearth: "we aren't doing too bad here but it feels noticeably less good
// than yesterday" -> traced (2026-08-05) to the factory-cap veto below leaving
// a refused constructor fully idle -- its own comment already says so: "CIdleTask
// assigns whatever comes back... simply leaves the unit idle until the next idle
// sweep." A timeline (analyze_stats.py) on Armada,Armada showed mex count
// dead even with stock through minute 6, then falling behind by minute 8 --
// entirely in the T1 window -- and infolog con-veto counts showed "factory-cap"
// as the dominant refusal reason for armck specifically (26 of 45 in one game,
// more than mex+mexup combined). SaferMex (above) cannot help here: it matches
// candidates by the REFUSED task's own buildDef, and a factory-cap refusal's
// buildDef is a factory, not a mex. But the basic T1 mex is buildable by every
// side's T1 constructor by design (this is what those constructors are FOR),
// so it does not need the "engine already proved buildability" trick SaferMex
// relies on for tiers that vary per-constructor (armck builds armmex, armack
// only armmoho -- see SaferMex's own comment).
IUnitTask@ FallbackMex(CCircuitUnit@ unit)
{
	const CCircuitDef@ want = SideDef3(armmex, cormex, legmex);
	if (want is null)
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestDist = REROUTE_RANGE;
	for (uint i = 0; i < gMexTasks.length(); ++i) {
		IUnitTask@ cand = gMexTasks[i];
		if (cand is null)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= bestDist)
			continue;
		if (ThreatFor(unit, where) > CON_THREAT_VETO)
			continue;
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy !is null) && (busy.length() > 0))
			continue;
		@best = cand;
		bestDist = dist;
	}
	if (best is null)
		return null;
	++gConRerouted;
	if (ai.frame >= gNextRerouteLog) {
		gNextRerouteLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-reroute " + unit.circuitDef.GetName()
			+ " -> factory-cap-fallback-mex dist=" + formatFloat(bestDist, "", 0, 0)
			+ " rerouted=" + gConRerouted);
	}
	return best;
}

}  // namespace Builder
