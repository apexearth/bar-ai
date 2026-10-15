namespace Air {

//------------------------------------------------------------------------------
// FIGHTERS STAND SPREAD OUT, AND OLD ONES ARE SPENT RATHER THAN PARKED.
//
// apexearth 2026-08-19: "can we get our aircraft fighters to spread themselves
// out more in our bases so that they'll be able to react to enemy attacks more
// evenly?" and "late game it needs to be T2 fighters, not T1. You can throw away
// T1 fighters into the enemy base as a free scouting mission when you want to
// replace them with T2."
//
// Held fighters get no orders at all (Air::HoldsUnit returns null from
// AiMakeTask), so every one of them sits on top of the plant that built it. One
// pile answers one attack; the same metal spread over the base answers whichever
// corner is hit, and the flight time to any of them is shorter.
//------------------------------------------------------------------------------

int gNextStation = 7;   // phase offset -- see AiUpdate lockstep note
int gNextStationLog = 0;
int gRecycled = 0;
int gNextRecycle = 23;   // phase offset -- see AiUpdate lockstep note
int gNextRecycleLog = 0;

// WHERE A FIGHTER STANDS. Our own guns are already placed where attacks come
// from -- the fence ledger is the base's real shape, better than a circle drawn
// around the start position. Falls back to a ring at home in the opening, before
// anything is built.
// Rebuilt once per pass, not once per fighter: the first version copied the
// whole fence ledger for every aircraft, which on a mature base is thousands of
// array appends a pass for an answer that does not change between them.
array<AIFloat3> gStations;

void RebuildStations()
{
	gStations.resize(0);
	for (uint i = 0; i < Military::gFencePos.length(); ++i) {
		if (OnMap(Military::gFencePos[i]))
			gStations.insertLast(Military::gFencePos[i]);
	}
}

bool StationFor(uint idx, AIFloat3& out at)
{
	if (!Builder::gHomeSet)
		return false;
	if (gStations.length() > 0) {
		at = gStations[idx % gStations.length()];
		return true;
	}
	// A ring around home: evenly spaced by index so consecutive fighters do not
	// stack, at a radius that grows with what we hold rather than a constant.
	const float r = 1600.f;   // the old crew home radius
	const float ang = 6.2831853f * float(idx % 8) / 8.f;
	at = Builder::gHomePos;
	at.x += cos(ang) * r;
	at.z += sin(ang) * r;
	return OnMap(at);
}

void UpdateFighterStations()
{
	if ((ai.frame < gNextStation) || !ApexActive())
		return;
	gNextStation = ai.frame + 10 * SECOND;
	if (ai.GetTunable("apex_air_spread", TUNE_AIR_SPREAD) <= 0.f)
		return;
	// An intercept owns the wing while it runs -- standing them back down would
	// fight the code that sent them. A strike does NOT: it owns only its own
	// roster, and the fighters held back for the next wave still have a base to
	// cover in the meantime.
	if ((gInterceptTarget >= 0) || !Builder::gHomeSet)
		return;

	RebuildStations();
	uint idx = 0;
	int moved = 0;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ wings = ai.GetOwnUnitsOfDef(fd, Builder::gHomePos, 0.f);
		if (wings is null)
			continue;
		for (uint i = 0; i < wings.length(); ++i) {
			CCircuitUnit@ w = wings[i];
			if ((w is null) || InWave(w.id))
				continue;   // out on a strike; those orders are not ours
			AIFloat3 at;
			if (!StationFor(idx, at)) {
				++idx;
				continue;
			}
			++idx;
			// Already on station: leave it alone, or the re-order every pass
			// keeps it permanently in transit and never fighting.
			const AIFloat3 p = w.GetPos(ai.frame);
			if (!OnMap(p) || (p.distance2D(at) < ai.GetTunable("apex_air_station_near", TUNE_AIR_STATION_NEAR)))
				continue;
			// Patrol, not move: a patrolling fighter engages what enters its
			// circle instead of parking nose-down over one spot.
			w.CmdPatrolTo(at);
			++moved;
		}
	}
	if ((moved > 0) && (ai.frame >= gNextStationLog)) {
		gNextStationLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: fighters spread -- " + moved
			+ " restationed over " + idx + " on " + Military::gFencePos.length()
			+ " guarded spots");
	}
}

// SPEND THE OBSOLETE ONES. A T1 fighter kept at home once the T2 line is running
// is 73 metal of nothing; flown at their base it is vision we do not otherwise
// buy, and anything it trades with on the way is profit. Only ever while the
// advanced fighter is actually being produced, and never the last of them --
// they are still the answer if their air arrives before ours is replaced.
void RecycleOldFighters()
{
	if ((ai.frame < gNextRecycle) || !ApexActive())
		return;
	gNextRecycle = ai.frame + 20 * SECOND;
	if (ai.GetTunable("apex_air_recycle", TUNE_AIR_RECYCLE) <= 0.f)
		return;
	if ((gFighter is null) || (gFighter1 is null) || !gFighter.IsAvailable(ai.frame))
		return;
	// Replacement has to be real before the old ones are thrown away: at least
	// as many advanced fighters standing as basic ones we are about to spend.
	const int adv = int(gFighter.count);
	const int old = int(gFighter1.count);
	if ((adv <= 0) || (old <= 0) || (adv < old))
		return;

	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe) || !Builder::gHomeSet)
		return;
	array<CCircuitUnit@>@ wings = ai.GetOwnUnitsOfDef(gFighter1, Builder::gHomePos, 0.f);
	if ((wings is null) || (wings.length() == 0))
		return;
	// One per pass, so the escort thins gradually instead of the whole basic
	// wing leaving at once.
	for (uint i = 0; i < wings.length(); ++i) {
		CCircuitUnit@ w = wings[i];
		if ((w is null) || Covering(w.id))
			continue;
		w.CmdMoveTo(foe);
		++gRecycled;
		if (ai.frame >= gNextRecycleLog) {
			gNextRecycleLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: spending an obsolete "
				+ gFighter1.GetName() + " on a look at their base -- "
				+ adv + " advanced standing, " + old + " basic, n=" + gRecycled);
		}
		return;
	}
}

}  // namespace Air
