namespace Air {

//------------------------------------------------------------------------------
// THE SCOUT FLIGHT (apexearth 2026-09-29: "mass scouts or radar planes, just get
// a whole ton of them and then just launch them towards the enemy territory,
// and then inform you where you should be attacking"). Humans jam, so the army,
// the cannons and the bombers see nothing and nothing happens. Air scouts and
// unarmed radar planes hold at home until the flight is full, then leave
// together, one to each metal spot on the enemy half -- where their economy
// stands -- and are handed to stock scouting there, where they also draw the
// few-shot T2 anti-air (docs/24). The single bomber look is untouched.
//------------------------------------------------------------------------------

array<Id> gFlightOut;       // launched, flying to their spot
array<AIFloat3> gFlightDest;
int gFlightLaunches = 0;

bool IsFlightDef(int d)
{
	if (IsLookDef(d))
		return true;
	return (d > 0) && Catalog::gAvailable[d] && Catalog::gMobile[d]
		&& Catalog::gFlyer[d] && !Catalog::gBuilder[d] && !Catalog::gKamikaze[d]
		&& (Catalog::gPower[d] <= 1.f) && (Catalog::gRadarR[d] > 0.f);
}

// One plane per spot on their half we have not seen anything at (the ground
// scout's own "one per unknown spot"), under his flat cap (2026-09-26/27).
int gFlightWant = 0;
int gFlightWantAt = -999999;
int FlightWant()
{
	if (ai.frame < gFlightWantAt + 10 * SECOND)
		return gFlightWant;
	gFlightWantAt = ai.frame;
	int n = 0;
	for (uint s = 0; s < Market::gAllSpots.length(); ++s) {
		const AIFloat3 sp = Market::gAllSpots[s];
		if ((Military::ForwardFraction(sp) > 0.5f)
			&& (aiEnemyMgr.GetEnemyStructCostAt(sp, 600.f) <= 1.f))
			++n;
	}
	const int cap = Market::RezFleetCap();
	gFlightWant = (n < cap) ? n : cap;
	return gFlightWant;
}

int FlightHave()
{
	int n = 0;
	for (uint d = 1; d < Market::gOwnCount.length(); ++d) {
		if (IsFlightDef(int(d)))
			n += Market::gOwnCount[d] + Brain::PendAnyOf(int(d));
	}
	return n;
}

// What seeing their base is worth: the economy the mirror says they have that
// we have not seen, fading as it is looked at.
float FlightWorth()
{
	const float unseen = MirrorPrize() - aiEnemyMgr.GetEnemyStructCost();
	return (unseen > 0.f) ? unseen * LookStale() : 0.f;
}

// The production draw's price for one more plane of the flight: its share of
// the worth, while the flight is short.
float FlightGainFor(int d, float fillSec)
{
	if (!IsFlightDef(d) || (FlightHave() >= FlightWant()))
		return 0.f;
	return FlightWorth() / ((fillSec > 1.f) ? fillSec : 180.f) / float(FlightWant());
}

int FlightOutIdx(Id id)
{
	for (uint i = 0; i < gFlightOut.length(); ++i) {
		if (gFlightOut[i] == id)
			return int(i);
	}
	return -1;
}

// Hold at home until launched; hold on the way out; release on arrival.
bool FlightHolds(CCircuitUnit@ unit)
{
	const int id = int(unit.circuitDef.id);
	if (!IsFlightDef(id) || (int(unit.id) == gLookScout))
		return false;
	const int k = FlightOutIdx(unit.id);
	if (k < 0)
		return !FlightArrived(unit.id);
	return unit.GetPos(ai.frame).distance2D(gFlightDest[uint(k)]) > 400.f;
}

// Planes that reached their spot are stock's from then on.
array<Id> gFlightDone;
bool FlightArrived(Id id)
{
	return InList(gFlightDone, id);
}

// Every slow update: prune, land arrivals, and launch a full flight.
void FlightWatch()
{
	array<CCircuitUnit@> home;
	array<Id> alive;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!IsFlightDef(d))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ u = us[i];
			if ((u is null) || (int(u.id) == gLookScout))
				continue;
			alive.insertLast(u.id);
			const int k = FlightOutIdx(u.id);
			if (k >= 0) {
				if (u.GetPos(ai.frame).distance2D(gFlightDest[uint(k)]) <= 400.f) {
					gFlightDone.insertLast(u.id);
					gFlightOut.removeAt(uint(k));
					gFlightDest.removeAt(uint(k));
				}
			} else if (!FlightArrived(u.id)) {
				home.insertLast(u);
			}
		}
	}
	for (uint i = 0; i < gFlightOut.length(); ) {
		if (!InList(alive, gFlightOut[i])) {
			gFlightOut.removeAt(i);
			gFlightDest.removeAt(i);
		} else {
			++i;
		}
	}
	for (uint i = 0; i < gFlightDone.length(); ) {
		if (!InList(alive, gFlightDone[i]))
			gFlightDone.removeAt(i);
		else
			++i;
	}
	if (home.length() == 0)
		return;
	// Full, or nothing left unseen (then they go as fodder): together, never
	// one at a time.
	const int want = FlightWant();
	if ((want > 0) && (int(home.length()) < want))
		return;
	array<AIFloat3> spots;
	for (uint s = 0; s < Market::gAllSpots.length(); ++s) {
		if (Military::ForwardFraction(Market::gAllSpots[s]) > 0.5f)
			spots.insertLast(Market::gAllSpots[s]);
	}
	if (spots.length() == 0) {
		const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
		if (OnMap(box))
			spots.insertLast(box);
		else
			return;
	}
	for (uint i = 0; i < home.length(); ++i) {
		const AIFloat3 dest = spots[(uint(gFlightLaunches) + i) % spots.length()];
		home[i].CmdMoveTo(dest);
		gFlightOut.insertLast(home[i].id);
		gFlightDest.insertLast(dest);
	}
	AiLog(Factory::T() + "apex: air flight launch n=" + home.length()
		+ " want=" + FlightWant() + " spots=" + spots.length()
		+ " worth=" + int(FlightWorth()));
	gFlightLaunches += int(home.length());
}

}  // namespace Air
