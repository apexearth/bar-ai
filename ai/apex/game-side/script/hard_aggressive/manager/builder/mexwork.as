namespace Builder {

// Live MEX build tasks, so a refused one can be traded for a colder one.
// The script cannot enumerate metal spots, so a MEX task built here carries
// spotId -1 (CBMexTask indexes mexSpots[spotId]) unless tracked from
// AiTaskAdded through to DequeueTask -> AiTaskRemoved.
array<IUnitTask@> gMexTasks;

// Function rather than a direct array read: main.as includes brain.as before
// builder.as, so a global declared here isn't visible to the Brain, but
// functions are module-wide.
//
// This bounds the Brain's expansion want: an unassigned task holds its slot
// for 300s and the engine refuses new economy work above workers * 8, so an
// unbounded want re-proposing every call starves the thing it's trying to buy.
array<IUnitTask@> gDefTasks;

uint OutstandingDefenceTasks()
{
	return gDefTasks.length();
}

// Is a defence job already ordered near here? Bound per-position rather than
// by a global count, so entries from other wants (MexGuard, Fortify) don't
// starve this one.
bool DefenceTaskNear(const AIFloat3& in pos, float radius)
{
	const float sq = radius * radius;
	for (uint i = 0; i < gDefTasks.length(); ++i) {
		if (gDefTasks[i] is null)
			continue;
		// Only a task with a builder on it counts as spoken for. An unmanned
		// order is an orphan, not cover, and treating it as cover is what
		// would stop anyone ever going back for it.
		array<CCircuitUnit@>@ on = gDefTasks[i].GetUnits();
		if ((on is null) || (on.length() == 0))
			continue;
		const AIFloat3 at = gDefTasks[i].GetBuildPos();
		if (!OnMap(at))
			continue;
		const float dx = at.x - pos.x;
		const float dz = at.z - pos.z;
		if ((dx * dx + dz * dz) < sq)
			return true;
	}
	return false;
}

// Defence already ordered here, and the dearest of it. Companion to
// Military::FenceGunsNear, which only sees finished towers (FENCE fires on
// completion, GetOwnUnitsOfDef skips IsBeingBuilt) and so reads bare ground
// for the whole build time without this.
//
// Unlike DefenceTaskNear this counts orders with nobody on them yet, since a
// queued tower is metal already committed even before a builder is elected.
uint DefenceOrdersNear(const AIFloat3& in pos, float radius, float& out topCost)
{
	topCost = 0.f;
	const float sq = radius * radius;
	uint n = 0;
	for (uint i = 0; i < gDefTasks.length(); ++i) {
		if (gDefTasks[i] is null)
			continue;
		const AIFloat3 at = gDefTasks[i].GetBuildPos();
		if (!OnMap(at))
			continue;
		const float dx = at.x - pos.x;
		const float dz = at.z - pos.z;
		if ((dx * dx + dz * dz) >= sq)
			continue;
		CCircuitDef@ d = gDefTasks[i].buildDef;
		if ((d is null) || (d.GetSurfThreat() <= 0.f))
			continue;
		++n;
		if (d.costM > topCost)
			topCost = d.costM;
	}
	return n;
}

// Surface-gun metal already ORDERED near here, manned or not -- committed
// answer that FenceGunMetalNear (finished only) cannot see.
float DefenceOrderMetalNear(const AIFloat3& in pos, float radius)
{
	float m = 0.f;
	const float sq = radius * radius;
	for (uint i = 0; i < gDefTasks.length(); ++i) {
		if (gDefTasks[i] is null)
			continue;
		const AIFloat3 at = gDefTasks[i].GetBuildPos();
		if (!OnMap(at))
			continue;
		const float dx = at.x - pos.x;
		const float dz = at.z - pos.z;
		if ((dx * dx + dz * dz) >= sq)
			continue;
		CCircuitDef@ d = gDefTasks[i].buildDef;
		if ((d !is null) && (d.GetSurfThreat() > 0.f))
			m += d.costM;
	}
	return m;
}

// Is this task still on the books? A count of standing towers can't tell
// queued-but-unbuilt from aborted; gDefTasks membership can (removal always
// funnels through DequeueTask -> AiTaskRemoved).
bool IsDefenceTaskLive(IUnitTask@ task)
{
	if (task is null)
		return false;
	for (uint i = 0; i < gDefTasks.length(); ++i) {
		if (gDefTasks[i] is task)
			return true;
	}
	return false;
}

// Orders on the books for the FRONT specifically, in metal. A budget counting
// only standing towers can never bind while front towers aren't finishing, so
// this counts in-flight orders too. Metal rather than a unit count because a
// Sentry and a Pulsar are not one unit of front line each.
float OutstandingFrontCost()
{
	float m = 0.f;
	for (uint i = 0; i < gDefTasks.length(); ++i) {
		if (gDefTasks[i] is null)
			continue;
		CCircuitDef@ d = gDefTasks[i].buildDef;
		if (d is null)
			continue;
		const AIFloat3 at = gDefTasks[i].GetBuildPos();
		if (!OnMap(at))
			continue;
		if (Military::OnBorder(at) || Military::NearFront(at))
			m += d.costM;
	}
	return m;
}

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

// A factory-cap refusal's buildDef is a factory, not a mex, so SaferMex above
// (which matches candidates by the refused task's own buildDef) can't reroute
// it. This can fall back to the plain T1 mex directly instead, since every
// side's T1 constructor can build it by design and doesn't need SaferMex's
// per-constructor buildability check.
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

// Un-upgraded T1 extractors still standing in the home patch. While any
// remain, upgrading them IS the advanced-constructor job -- apexearth
// 2026-08-19: "we should dedicate ourselves to upgrading those 3 mexes before
// we care about a fusion or anything else... the quickest path to getting more
// metal is upgrading those mexes."
uint HomeMexOutstanding()
{
	if (!gHomeSet)
		return 0;
	CCircuitDef@ mex = SideDef3(armmex, cormex, legmex);
	if ((mex is null) || (mex.count <= 0))
		return 0;
	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, gHomePos,
			ai.GetTunable("apex_mexup_home_r", 1200.f));
	return (mine is null) ? 0 : mine.length();
}

}  // namespace Builder
