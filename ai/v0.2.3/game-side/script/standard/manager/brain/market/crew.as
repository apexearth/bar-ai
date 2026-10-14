namespace Market {
// THE FIELD CREW AND THE HOME CREW (apexearth 2026-10-01): "dedicate a
// percentage to the moho upgrades. If we have 30 constructors, maybe only 10
// of them can go out... the guys that are going out and upgrading, I hope
// they're going to be willing to make defenses too." Every builder had been
// pulled out to the extractors while the bank overflowed at home with no nano
// turrets standing.
//
// Field crew: claim, upgrade and rebuild the extractors outside the base, and
// put guns and radar on them, reclaiming on the way. At most a third of our
// build power, and no more hands than there are field jobs open. Home crew:
// everything else, and never walks out to help a field job. Before our first
// advanced constructor there is no split -- the opening is the expansion.

array<int> gCrewOf(32001, 0);   // per unit id: 1 field, 0 home
int gCrewAt = -999999;
float gCrewFieldBP = 0.f;
float gCrewAllBP = 0.f;
int gCrewFieldN = 0;
int gCrewJobs = 0;
float gHomeR = 0.f;
int gNextCrewLog = 0;

bool CrewSplitOn()
{
	return CeilingConsOwned() > 0;
}

// How far our own base reaches: plants, generators, converters and nanos,
// plus a light tower's range. A site beyond it is field work.
void CrewRefresh()
{
	if (ai.frame - gCrewAt < 5 * SECOND)
		return;
	gCrewAt = ai.frame;
	const float tower = Brain::LightTowerRange();
	float r = tower * 2.f;
	if (Builder::gHomeSet) {
		const AIFloat3 h = Builder::gHomePos;
		for (uint i = 0; i < Factory::gFacUnits.length(); ++i)
			if (Factory::gFacUnits[i] !is null)
				r = CrewMax(r, h.distance2D(Factory::gFacUnits[i].GetPos(ai.frame)) + tower);
		for (uint i = 0; i < gOwnGen.length(); ++i)
			if (gOwnGen[i] !is null)
				r = CrewMax(r, h.distance2D(gOwnGen[i].GetPos(ai.frame)) + tower);
		for (uint i = 0; i < gOwnConv.length(); ++i)
			if (gOwnConv[i] !is null)
				r = CrewMax(r, h.distance2D(gOwnConv[i].GetPos(ai.frame)) + tower);
		for (uint i = 0; i < gOwnNano.length(); ++i)
			if (gOwnNano[i] !is null)
				r = CrewMax(r, h.distance2D(gOwnNano[i].GetPos(ai.frame)) + tower);
	}
	gHomeR = r;
	// The field jobs open: our extractors outside home below the best, and
	// open spots outside home nobody has claimed.
	CacheSpots();
	const float ceilX = BestExtract();
	const array<int>@ lidx = LedgerIdx();
	int jobs = 0;
	for (uint si = 0; si < gAllSpots.length(); ++si) {
		if (!FieldSite(gAllSpots[si]))
			continue;
		const int row = (si < lidx.length()) ? lidx[si] : LedgerFind(int(si));
		if (row >= 0) {
			if ((gLExtract[uint(row)] > 0.f) && (gLExtract[uint(row)] < ceilX))
				++jobs;
		} else if ((si < gPtState.length()) && (gPtState[si] == PT_OPEN)) {
			++jobs;
		}
	}
	gCrewJobs = jobs;
	// Who is out there now, and what the whole fleet is.
	gCrewFieldBP = 0.f;
	gCrewAllBP = 0.f;
	gCrewFieldN = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u is null) || u.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;
		const float bp = Catalog::gBuildPower[int(u.circuitDef.id)];
		gCrewAllBP += bp;
		if (CrewIsField(u)) {
			gCrewFieldBP += bp;
			++gCrewFieldN;
		}
	}
	if (ai.frame >= gNextCrewLog) {
		gNextCrewLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: crew t=" + ai.teamId + " on=" + (CrewSplitOn() ? 1 : 0)
			+ " field=" + gCrewFieldN + " bp=" + int(gCrewFieldBP) + "/" + int(gCrewAllBP)
			+ " jobs=" + gCrewJobs + " homeR=" + int(gHomeR));
	}
}

float CrewMax(float a, float b)
{
	return (a > b) ? a : b;
}

bool FieldSite(const AIFloat3& in p)
{
	return Builder::gHomeSet && OnMap(p) && (p.distance2D(Builder::gHomePos) > gHomeR);
}

bool CrewIsField(CCircuitUnit@ u)
{
	const int id = int(u.id);
	return (id >= 0) && (id < int(gCrewOf.length())) && (gCrewOf[id] == 1);
}

void CrewForget(int id)
{
	if ((id >= 0) && (id < int(gCrewOf.length())))
		gCrewOf[id] = 0;
}

bool FieldWant(Want@ w)
{
	if ((w is null) || !FieldSite(w.pos))
		return false;
	const int k = w.kind;
	return (k == WK_MEX) || (k == WK_MEXUP) || (k == WK_PROTECT) || (k == WK_SENSE)
		|| (k == WK_RECLAIM) || (k == WK_ASSIST);
}

// Join, keep or leave the field crew, then shape this hand's list. True when
// the hand is field crew and takes a field job; the list then holds only those.
bool CrewApply(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	const int id = int(unit.id);
	if ((id < 0) || (id >= int(gCrewOf.length())) || unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if (!CrewSplitOn()) {
		gCrewOf[id] = 0;
		return false;
	}
	CrewRefresh();
	bool hasField = false;
	for (uint i = 0; (i < ranked.length()) && !hasField; ++i)
		hasField = FieldWant(ranked[i]);
	const float bp = Catalog::gBuildPower[int(unit.circuitDef.id)];
	if (gCrewOf[id] == 1) {
		// Over the third, more hands than jobs, or nothing out there for it: home.
		if (!hasField || (gCrewFieldBP > gCrewAllBP / 3.f) || (gCrewFieldN > gCrewJobs)) {
			gCrewOf[id] = 0;
			gCrewFieldBP -= bp;
			--gCrewFieldN;
		}
	} else if (hasField && (gCrewFieldBP + bp <= gCrewAllBP / 3.f) && (gCrewFieldN < gCrewJobs)) {
		gCrewOf[id] = 1;
		gCrewFieldBP += bp;
		++gCrewFieldN;
	}
	if (gCrewOf[id] == 1) {
		for (uint i = 0; i < ranked.length(); ) {
			if (FieldWant(ranked[i]))
				++i;
			else
				ranked.removeAt(i);
		}
		return true;
	}
	// Home crew: field work is the field crew's. A list with nothing else in it
	// is left alone rather than idling the hand.
	array<Want@> kept;
	for (uint i = 0; i < ranked.length(); ++i)
		if (!FieldWant(ranked[i]))
			kept.insertLast(ranked[i]);
	if (kept.length() > 0) {
		ranked.resize(0);
		for (uint i = 0; i < kept.length(); ++i)
			ranked.insertLast(kept[i]);
	}
	return false;
}

}  // namespace Market
