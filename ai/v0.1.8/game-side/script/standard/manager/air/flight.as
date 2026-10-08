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

// THE SCOUT SEAT (his 2026-09-29: "at least 1 ai earlier on should make some
// scout aircraft to see what the enemy is doing"). The air lead when there is
// one; before one is elected, or if none ever is, the lowest-numbered Apex ally
// that is not the eco seat -- every seat computes the same answer. Allied
// vision is shared, so one seat's look serves the team.
bool IsScoutSeat()
{
	// The eco seat's metal is the economy's, never the look's.
	const int lead = AirLeadTeamId();
	if ((lead >= 0) && (ai.ReadTeamValue(lead, Military::TV_ECOSEAT, 0.f) <= 0.5f))
		return lead == ai.teamId;
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return true;
	int pick = -1;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (ai.ReadTeamValue(t, Military::TV_ECOSEAT, 0.f) > 0.5f)
			continue;
		if ((pick < 0) || (t < pick))
			pick = t;
	}
	return (pick < 0) || (pick == ai.teamId);
}

// The cell a raid of ours or an ally's is hitting (Release publishes strike_x/z/r,
// ReArm clears strike_r).
bool StrikePoint(AIFloat3& out p, float& out r)
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		const float sr = ai.ReadTeamValue(t, "strike_r", 0.f);
		if (sr <= 0.f)
			continue;
		p = AIFloat3(ai.ReadTeamValue(t, "strike_x", -1.f), 0.f, ai.ReadTeamValue(t, "strike_z", -1.f));
		r = sr;
		if (OnMap(p))
			return true;
	}
	return false;
}

bool TeamStrikeOut()
{
	AIFloat3 p;
	float r;
	return gStrike || StrikePoint(p, r);
}

array<Id> gFlightOut;       // launched, flying to their spot
array<AIFloat3> gFlightDest;
int gFlightLaunches = 0;

// Where the i-th of n decoys goes: spread over the raid's cell.
AIFloat3 DecoyDest(const AIFloat3& in at, float r, uint i, uint n)
{
	const float ang = 6.2831853f * float(i) / float((n > 0) ? n : 1);
	AIFloat3 d = at + AIFloat3(cos(ang), 0.f, sin(ang)) * (0.5f * r);
	return OnMap(d) ? d : at;
}

// THE FIGHTERS GO IN FIRST (apexearth 2026-09-29): faster than the bombers,
// sent at the cell as the wave leaves, they draw the AA -- the expensive AA
// included -- that would otherwise meet the bombs.
void Vanguard()
{
	// Our own strike's cell: StrikePoint reads the first ally with one
	// published, which sent our fighters to an ally's older target.
	AIFloat3 at = gStrikeAt;
	float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	if (!gStrikeHas || !OnMap(at))
		return;
	array<CCircuitUnit@> go;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(fd, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] is null) || !InWave(us[k].id))
				continue;
			// A fighter sent on an earlier strike and redirected before it
			// arrived would stay on the flight list for good.
			const int old = FlightOutIdx(us[k].id);
			if (old >= 0) {
				gFlightOut.removeAt(uint(old));
				gFlightDest.removeAt(uint(old));
			}
			go.insertLast(us[k]);
		}
	}
	// ALL OF THEM, FIRST: faster than the bombers, they clear the sky over the
	// cell and draw its ground AA before the bombs arrive. A hunter is taken
	// off its hunt so the stock task cannot turn it round on the way.
	const float foeFig = FoeFighterM();
	float foeAA = EnemyAACost() - foeFig;
	if (foeAA < 0.f)
		foeAA = 0.f;
	const uint n = go.length();
	for (uint i = 0; i < n; ++i) {
		const AIFloat3 dest = DecoyDest(at, r, i, n);
		gFlightOut.insertLast(go[i].id);
		gFlightDest.insertLast(dest);
		if ((go[i].task !is null) && (go[i].task.GetType() == Task::Type::FIGHTER))
			go[i].task.RemoveUnit(go[i]);
		go[i].CmdMoveTo(dest);
	}
	AiLog(Factory::T() + "apex: air vanguard decoys=" + n + " of " + go.length()
		+ " foeAA=" + int(foeAA) + " foeFighters=" + int(foeFig)
		+ " at=" + int(at.x) + "," + int(at.z));
}

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
	return n + HeldFighters();
}

// Fighters at home fly the look too, and come back to the wing after.
bool FlightFighter(CCircuitUnit@ u)
{
	return (u !is null) && IsFighterDef(int(u.circuitDef.id))
		&& !Covering(u.id) && !InWave(u.id) && (FlightOutIdx(u.id) < 0);
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
	// Bought by the scout seat when there are bombers to use the look: before
	// the wing stands the planes only hover at home.
	if (!IsScoutSeat() || (TeamWingHeld() <= 0.f)
		|| (ScoutsDie() && !IsFighterDef(d)))
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
	if (int(unit.id) == gLookScout)
		return false;
	const int k = FlightOutIdx(unit.id);
	if (k >= 0)
		return unit.GetPos(ai.frame).distance2D(gFlightDest[uint(k)]) > 400.f;
	return IsFlightDef(id) && !FlightArrived(unit.id);
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
	const array<int>@ owned = Market::OwnedDefs();
	for (uint oi = 0; oi < owned.length(); ++oi) {
		const int d = owned[oi];
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
					gLookAt = ai.frame;   // eyes on their ground: a look delivered
					gFlightOut.removeAt(uint(k));
					gFlightDest.removeAt(uint(k));
				}
			} else if (!FlightArrived(u.id)) {
				home.insertLast(u);
			}
		}
	}
	array<CCircuitUnit@> fighters;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(fd, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ u = us[i];
			if (u is null)
				continue;
			const int k = FlightOutIdx(u.id);
			if (k < 0) {
				if (FlightFighter(u))
					fighters.insertLast(u);
				continue;
			}
			alive.insertLast(u.id);
			if (u.GetPos(ai.frame).distance2D(gFlightDest[uint(k)]) <= 400.f) {
				gLookAt = ai.frame;
				gFlightOut.removeAt(uint(k));
				gFlightDest.removeAt(uint(k));
				// A vanguard fighter stays over the cell and fights.
				if (Builder::gHomeSet && !(gStrike && InWave(u.id)))
					u.CmdMoveTo(Builder::gHomePos);
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
	// Only with a raid: a look with no bombers behind it shows them our air
	// and buys their AA before the first bomb (apexearth).
	if (!TeamStrikeOut())
		return;
	// What stands goes with the raid, together, over the raid's cell: the look
	// and the decoys ahead of the bombs. Fighters fill it while there is
	// something to see.
	const int want = FlightWant();
	int nf = 0;
	for (uint i = 0; (i < fighters.length()) && (int(home.length()) < want); ++i) {
		home.insertLast(fighters[i]);
		++nf;
	}
	if (home.length() == 0)
		return;
	AIFloat3 cell;
	float cellR = 0.f;
	const bool onCell = StrikePoint(cell, cellR);
	array<AIFloat3> spots;
	if (!onCell) {
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
	}
	for (uint i = 0; i < home.length(); ++i) {
		const AIFloat3 dest = onCell ? DecoyDest(cell, cellR, i, home.length())
				: spots[(uint(gFlightLaunches) + i) % spots.length()];
		home[i].CmdMoveTo(dest);
		gFlightOut.insertLast(home[i].id);
		gFlightDest.insertLast(dest);
	}
	AiLog(Factory::T() + "apex: air flight launch n=" + home.length() + " fighters=" + nf
		+ " want=" + FlightWant() + " spots=" + spots.length()
		+ " worth=" + int(FlightWorth()));
	gFlightLaunches += int(home.length());
}

}  // namespace Air
