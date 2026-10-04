namespace Market {
// A RETIREMENT IS A DECISION, NOT A VACANCY: a def we retire keeps a discount
// for a window, so the market cannot re-buy what it just reclaimed. Set at
// reclaim EXECUTION and only for the OBSOLETE proposer -- eating a wall that
// pens a unit says nothing about wanting the def again.
array<int> gDefRetiredAt;
void NoteDefRetired(int d)
{
	// resize() zero-fills, so 0 is the "never retired" sentinel.
	if (int(gDefRetiredAt.length()) <= Catalog::gDefCount)
		gDefRetiredAt.resize(uint(Catalog::gDefCount + 1));
	if ((d > 0) && (d < int(gDefRetiredAt.length())))
		gDefRetiredAt[d] = (ai.frame > 0) ? ai.frame : 1;
}
float RetiredDefMul(int d)
{
	if ((d <= 0) || (d >= int(gDefRetiredAt.length()))
		|| (gDefRetiredAt[d] <= 0))
		return 1.f;
	// A DEF WE RETIRED AS OBSOLETE IS NOT BOUGHT WHILE IT STILL IS (apexearth
	// 2026-09-14: "We keep making the same obsolete buildings we've
	// reclaimed... if it is obsolete we shouldn't be making it, need some
	// buffer in there so we aren't flipflopping"). A discount in a
	// proportional draw still wins its share; the bar is the dwarf test the
	// retirement itself ran, so it lifts only when the thing stops being
	// obsolete. The window discount below stays for everything else.
	if (((Catalog::gMakeE[d] > 0.f) && GenObsoleteOnArrival(d))
		|| ((Catalog::gConvCapacity[d] > 0.f) && ConvObsoleteOnArrival(d)))
		return 0.f;
	const float win = ai.GetTunable("apex_replant_window_s", TUNE_REPLANT_WINDOW_S);
	if (float(ai.frame - gDefRetiredAt[d]) >= win * float(SECOND))
		return 1.f;
	return ai.GetTunable("apex_replant_discount", TUNE_REPLANT_DISCOUNT);
}

// Geothermal: same shape as mex -- a def that must stand on its own spot.
Want@ ProposeGeo(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	int geoId = -1;
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || !Catalog::gNeedGeo[d])
			continue;
		if ((geoId < 0) || (Catalog::gMakeE[d] > Catalog::gMakeE[geoId]))
			geoId = d;
	}
	if (geoId < 0)
		return w;
	// The stall-solar doctrine covers vents: a geo is paid for in ENERGY
	// (armgeo: 13,000 E), and while hard-stalled under the solar bar the
	// zero-E solar is the only rung (same rule as ProposeEnergy's solarOnly).
	if ((Catalog::gCostE[geoId] > 0.f) && HardEStall()
		&& (Eco::EInc()
			< ai.GetTunable("apex_stall_solar_e", TUNE_STALL_SOLAR_E)))
		return w;
	const AIFloat3 here = unit.GetPos(ai.frame);
	const int spot = aiEconomyMgr.FindOpenGeoSpot(unit, here);
	if (spot < 0)
		return w;
	const AIFloat3 pos = aiEconomyMgr.GetGeoSpotPos(spot);
	if (EcoFar(pos) || (Front::FoeKnown() && Builder::PastFront(pos)))
		return w;
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f) ? (here.distance2D(pos) / speed) : 60.f;
	const float geoSec = Catalog::BuildSecondsAt(geoId, EffBP(Catalog::gBuildPower[uid]));
	// Only the share anything would use: a vent on top of a wasted band makes
	// no metal either (see ERealizeShare).
	const float gain = Catalog::gMakeE[geoId] * EPriceAt(geoSec)
			* ERealizeShare(Catalog::gMakeE[geoId], geoSec);
	w.kind = WK_GEO;
	@w.def = Catalog::Def(geoId);
	w.pos = pos;
	w.spotId = spot;
	ValueOf(geoId, gain, walkSec, Catalog::gBuildPower[uid], w);
	return w;
}

// A plant's output discounts by its own LATENCY (same law as EPriceAt):
// horizon/(horizon+latency), where latency is lab-build + con-build. This is
// what makes the natural opening (mex, mex, solar, THEN lab) emerge with no
// scripted order -- at frame zero the lab's 70s halves it below the mex.
float PipeLatencySec(int plantId, float askerBP)
{
	const float labSec = Catalog::BuildSecondsAt(plantId, EffBP(askerBP));
	float conSec = 45.f;
	const array<int>@ prods = Catalog::gBuildsList[plantId];
	for (uint p = 0; p < prods.length(); ++p) {
		if (Catalog::gMobile[prods[p]] && Catalog::gBuilder[prods[p]]) {
			const float cs = Catalog::BuildSecondsAt(prods[p],
					Catalog::gBuildPower[plantId]);
			if (cs < conSec)
				conSec = cs;
		}
	}
	return labSec + conSec;
}

float PipeLatencyMult(int plantId, float askerBP)
{
	const float H = ai.GetTunable("apex_pipe_latency_h", TUNE_PIPE_LATENCY_H);
	const float h = (H > 1.f) ? H : 60.f;
	return h / (h + PipeLatencySec(plantId, askerBP));
}

// BUILD POWER PER SECOND OF LINE TIME: the con half priced every line as if
// it filled the gap at one rate, and an air line delivers 55 BP per 50 s where
// a bot lab delivers 75 per 22 (measured: air openings on every wet map,
// bought for the reach of cons that arrive at a third of the rate).
float PipeRate(int plantId)
{
	float best = 0.f;
	const array<int>@ prods = Catalog::gBuildsList[plantId];
	for (uint p = 0; p < prods.length(); ++p) {
		const int pd = prods[p];
		if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
			continue;
		const float sec = Catalog::BuildSecondsAt(pd, Catalog::gBuildPower[plantId]);
		const float r = Catalog::gBuildPower[pd] / ((sec > 1.f) ? sec : 1.f);
		if (r > best)
			best = r;
	}
	return best;
}

// Relative to the best line the ASKER could start: the catalog's "tier" is
// config-attributed and puts the hard-variant plants and lootbox nanos
// beside a bot lab.
array<float> gAskRate;

float PipeRateMul(int plantId, int askerDef)
{
	if (int(gAskRate.length()) <= Catalog::gDefCount) {
		gAskRate.resize(Catalog::gDefCount + 1);
		for (uint i = 0; i < gAskRate.length(); ++i)
			gAskRate[i] = -1.f;
	}
	if (gAskRate[askerDef] < 0.f) {
		float best = 0.f;
		string row = "";
		const array<int>@ builds = Catalog::BuildsOf(askerDef);
		for (uint i = 0; i < builds.length(); ++i) {
			const int d = builds[i];
			if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
				|| Catalog::gFloater[d] || Catalog::gSub[d]
				|| (Catalog::gBuildsList[d].length() == 0))
				continue;   // a plant that stands in water is no land line's peer
			const float r = PipeRate(d);
			if (r > best)
				best = r;
			row += " " + Catalog::Def(d).GetName() + "=" + formatFloat(r, "", 0, 2);
		}
		if (best <= 0.f)
			return 1.f;   // never cache a zero
		gAskRate[askerDef] = best;
		AiLog("apex: pipe-rate t=" + ai.teamId + " " + Catalog::Def(askerDef).GetName()
			+ " best=" + formatFloat(best, "", 0, 2) + row);
	}
	const float m = PipeRate(plantId) / gAskRate[askerDef];
	return (m > 1.f) ? 1.f : m;
}

// Real water share, the same bar amphib capability is priced against: the
// engine's water flag trips on a pond, which must not buy a shipyard.
bool MapHasWater()
{
	if (aiTerrainMgr.IsWaterAVoid())
		return false;
	float lp = aiTerrainMgr.GetLandPercent();
	if (lp <= 1.5f)
		lp *= 100.f;   // scale-proof: fraction or percent
	return lp <= 100.f - ai.GetTunable("apex_water_pct", TUNE_WATER_PCT);
}

// A floating plant needs water it can actually stand in, within the same
// radius the rear prices every other build against. FindBuildSiteNear is not
// free and this is asked per builder election, so it is cached; an off-map
// result means no reachable water.
AIFloat3 gWetPlantSite(-1.f, 0.f, -1.f);
int gNextWetCheck = 149;   // phase offset -- see AiUpdate lockstep note

int gNextLakeLog = 0;
AIFloat3 WetPlantSite(CCircuitDef@ plant, const AIFloat3& in anchor)
{
	if (ai.frame < gNextWetCheck)
		return gWetPlantSite;
	gNextWetCheck = ai.frame + 10 * SECOND;
	const float near = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	const AIFloat3 wet = ai.FindBuildSiteNear(plant, anchor, near);
	gWetPlantSite = (OnMap(wet) && (wet.distance2D(anchor) <= near) && FoeSailsTo(wet))
			? wet : AIFloat3(-1.f, 0.f, -1.f);
	if (OnMap(gWetPlantSite) || !OnMap(wet))
		return gWetPlantSite;
	// The nearest water is a lake no enemy hull reaches: other water in reach.
	float bestD = 0.f;
	for (int k = 0; k < 8; ++k) {
		const float a = float(k) * 0.7853982f;
		const AIFloat3 probe(anchor.x + cos(a) * near * 0.6f, 0.f,
				anchor.z + sin(a) * near * 0.6f);
		if (!OnMap(probe))
			continue;
		const AIFloat3 w2 = ai.FindBuildSiteNear(plant, probe, near * 0.6f);
		if (!OnMap(w2) || (w2.distance2D(anchor) > near) || !FoeSailsTo(w2))
			continue;
		const float dd = w2.distance2D(anchor);
		if (!OnMap(gWetPlantSite) || (dd < bestD)) {
			gWetPlantSite = w2;
			bestD = dd;
		}
	}
	if (!OnMap(gWetPlantSite) && (ai.frame >= gNextLakeLog)) {
		gNextLakeLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: lake-yard refused t=" + ai.teamId
			+ " at=" + int(wet.x) + "," + int(wet.z));
	}
	return gWetPlantSite;
}

// ...and the water THIS ASKER can build from: the nearest wet site is the
// deep side of a beach a bot con cannot stand on, so the ring around the
// anchor is asked for a shore it can (the veto's own test, per asker).
array<AIFloat3> gWetSiteFor;
array<int> gWetSiteAt;

AIFloat3 WetPlantSiteFor(CCircuitDef@ plant, const AIFloat3& in anchor,
		int askerDef, const AIFloat3& in here)
{
	if (int(gWetSiteFor.length()) <= Catalog::gDefCount) {
		gWetSiteFor.resize(Catalog::gDefCount + 1);
		gWetSiteAt.resize(Catalog::gDefCount + 1);
		for (uint i = 0; i < gWetSiteAt.length(); ++i) {
			gWetSiteAt[i] = 0;
			gWetSiteFor[i] = AIFloat3(-1.f, 0.f, -1.f);
		}
	}
	if (ai.frame < gWetSiteAt[askerDef])
		return gWetSiteFor[askerDef];
	gWetSiteAt[askerDef] = ai.frame + 10 * SECOND;
	CCircuitDef@ ask = Catalog::Def(askerDef);
	const float reach = Catalog::gBuildDist[askerDef];
	const float near = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	AIFloat3 best = WetPlantSite(plant, anchor);
	if (OnMap(best) && !NearBlockedFor(best, int(plant.id))
		&& ai.CanDefReachAt(ask, here, best, reach)) {
		gWetSiteFor[askerDef] = best;
		return best;
	}
	best = AIFloat3(-1.f, 0.f, -1.f);
	float bestD = 0.f;
	for (int k = 0; k < 8; ++k) {
		const float a = float(k) * 0.7853982f;
		const AIFloat3 probe(anchor.x + cos(a) * near * 0.6f, 0.f,
				anchor.z + sin(a) * near * 0.6f);
		if (!OnMap(probe))
			continue;
		const AIFloat3 wet = ai.FindBuildSiteNear(plant, probe, near * 0.6f);
		if (!OnMap(wet) || (wet.distance2D(anchor) > near)
			|| NearBlockedFor(wet, int(plant.id)) || !FoeSailsTo(wet))
			continue;
		if (!ai.CanDefReachAt(ask, here, wet, reach))
			continue;
		const float dd = wet.distance2D(anchor);
		if (!OnMap(best) || (dd < bestD)) {
			best = wet;
			bestD = dd;
		}
	}
	gWetSiteFor[askerDef] = best;
	return best;
}

// A plant's DOMAIN: land, air or water. Two plants are parallel capacity only
// within one domain -- a shipyard is the only door into the water, so land
// lines neither price it out nor divide its value.
const int PC_LAND = 0;
const int PC_AIR = 1;
const int PC_WATER = 2;

// -- The naval election ------------------------------------------------------
//
// apexearth 2026-08-28: "1 or 2 teams to make some navy in the game", REAL
// shipyards and not hovers. So the water mandate is HELD like the air lead:
// the closest-shore teams build, everyone else never proposes a water plant
// and never marches a commander to the beach. Deterministic from the
// blackboard (AnswerShare): each team publishes its distance, closest holds.

const string TV_NAVDIST = "navdist";
const string TV_NAVX = "navx";
const string TV_NAVZ = "navz";

// A REAL navy floats: a plant counts only if something it builds is a ship
// or a sub. The hover platform floats but its products do not -- it is the
// "oops - not what I meant".
bool PlantMakesShips(int d)
{
	const array<int>@ pr = Catalog::gBuildsList[d];
	for (uint i = 0; i < pr.length(); ++i) {
		if (Catalog::gFloater[pr[i]] || Catalog::gSub[pr[i]])
			return true;
	}
	return false;
}

// The faction's cheapest buildable real shipyard, for the site probe.
// NEVER latch a miss: gAvailable is frame-dependent (the catalog trap), so
// an empty scan re-runs on a 30s throttle instead of caching -1 forever.
int gNavShipDef = -1;
int gNavShipAt = -999999;

int NavShipyardDef()
{
	if ((gNavShipDef > 0) || (ai.frame < gNavShipAt + 30 * SECOND))
		return gNavShipDef;
	gNavShipAt = ai.frame;
	int best = -1;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| !Catalog::gFloater[d]
			|| (Catalog::gBuildsList[d].length() == 0))
			continue;
		if (!PlantMakesShips(d))
			continue;
		if ((best < 0) || (Catalog::gCostM[d] < Catalog::gCostM[best]))
			best = d;
	}
	gNavShipDef = best;
	return best;
}

// Published on the defence-line cadence (Military::PublishDefence calls this).
void NavalPublish()
{
	float dist = 1e9f;
	const int sd = NavShipyardDef();
	if ((sd > 0) && MapHasWater() && Builder::gHomeSet
		// A shore that keeps killing the order is not a usable shore: while
		// the shipyard sits in abort-backoff this team reads itself
		// ineligible and the mandate ROTATES to the next-closest. Without
		// this the elected team holds the mandate all game and builds none.
		&& !Builder::AbortBackoff(sd))
	{
		const AIFloat3 wet = WetPlantSite(Catalog::Def(sd), Builder::gHomePos);
		if (OnMap(wet)) {
			dist = Builder::gHomePos.distance2D(wet);
			ai.PublishTeamValue(TV_NAVX, wet.x);
			ai.PublishTeamValue(TV_NAVZ, wet.z);
		}
	}
	ai.PublishTeamValue(TV_NAVDIST, dist);
}

// A ship hull the yard makes, for "is that shore the same body of water".
int gNavHullDef = -1;
int NavHullDef()
{
	if (gNavHullDef > 0)
		return gNavHullDef;
	const int sd = NavShipyardDef();
	if (sd <= 0)
		return -1;
	const array<int>@ pr = Catalog::gBuildsList[sd];
	for (uint i = 0; i < pr.length(); ++i) {
		if (Catalog::gMobile[pr[i]] && Catalog::gFloater[pr[i]]) {
			gNavHullDef = pr[i];
			break;
		}
	}
	return gNavHullDef;
}

bool gNavLead = false;
int gNavLeadAt = -999999;

bool NavalLead()
{
	if (ai.frame < gNavLeadAt + 10 * SECOND)
		return gNavLead;
	gNavLeadAt = ai.frame;
	if (LandLocked()) {
		gNavLead = true;
		return gNavLead;
	}
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() <= 1)) {
		gNavLead = true;   // solo: the mandate is yours if the map has water
		return gNavLead;
	}
	// HIS NUMBER: "we really just [need] 1 or 2 teams to make some navy".
	const uint quota = (mates.length() >= 6) ? 2 : 1;
	const float mine = ai.ReadTeamValue(ai.teamId, TV_NAVDIST, 1e9f);
	if (mine >= 8e8f) {
		gNavLead = false;   // no usable shore of our own
		return gNavLead;
	}
	// PER BODY OF WATER (his 2026-09-28 on Supreme Isthmus: "two bodies of
	// water, so ideally ... one from each side"): a mate only competes for
	// the mandate when a ship could sail from its shore to ours.
	const AIFloat3 myWet(ai.ReadTeamValue(ai.teamId, TV_NAVX, -1.f), 0.f,
			ai.ReadTeamValue(ai.teamId, TV_NAVZ, -1.f));
	const int hull = NavHullDef();
	uint ahead = 0;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		const float d = ai.ReadTeamValue(t, TV_NAVDIST, 1e9f);
		if (d >= 8e8f)
			continue;
		const AIFloat3 theirWet(ai.ReadTeamValue(t, TV_NAVX, -1.f), 0.f,
				ai.ReadTeamValue(t, TV_NAVZ, -1.f));
		if ((hull > 0) && OnMap(myWet) && OnMap(theirWet)
			&& !ai.CanDefReach(Catalog::Def(hull), myWet, theirWet))
			continue;   // another lake: its own lead
		if ((d < mine) || ((d == mine) && (t < ai.teamId)))
			++ahead;
	}
	gNavLead = ahead < quota;
	return gNavLead;
}

int PlantClass(int plantId)
{
	if (Catalog::gFloater[plantId] || Catalog::gSub[plantId])
		return PC_WATER;
	const array<int>@ pr = Catalog::gBuildsList[plantId];
	for (uint i = 0; i < pr.length(); ++i) {
		if (Catalog::gMobile[pr[i]] && Catalog::gBuilder[pr[i]]
			&& Catalog::gFlyer[pr[i]])
			return PC_AIR;
	}
	return PC_LAND;
}

// A plant's expansion stream is only the spots ITS OWN constructors reach, so
// a shipyard collapses on a dry map and the land line collapses on a wet one.
// LAND-LOCKED is the sharper reading: ground this plant's cons reach and the
// ASKER cannot -- the half of the economy no land line will ever touch.
array<float> gPlantReach;    // share of open spots this plant's cons reach
array<float> gPlantLocked;   // ...and the share the asker cannot reach at all
array<int> gPlantOpenReach;  // count reached, so water can see its own ground
array<int> gPlantReachAt;

void MeasureReach(int plantId, int conId, const AIFloat3& in from,
		CCircuitUnit@ asker)
{
	if (gPlantReach.length() != Catalog::gMobile.length()) {
		gPlantReach.resize(Catalog::gMobile.length());
		gPlantLocked.resize(Catalog::gMobile.length());
		gPlantOpenReach.resize(Catalog::gMobile.length());
		gPlantReachAt.resize(Catalog::gMobile.length());
		for (uint i = 0; i < gPlantReach.length(); ++i) {
			gPlantReach[i] = 1.f;
			gPlantLocked[i] = 0.f;
			gPlantOpenReach[i] = 0;
			gPlantReachAt[i] = 0;
		}
	}
	if (ai.frame < gPlantReachAt[plantId])
		return;
	gPlantReachAt[plantId] = ai.frame + 30 * SECOND;
	CacheSpots();
	CCircuitDef@ con = Catalog::Def(conId);
	CCircuitDef@ ask = Catalog::Def(int(asker.circuitDef.id));
	const AIFloat3 askAt = asker.GetPos(ai.frame);
	int open = 0;
	int reach = 0;
	int locked = 0;
	for (uint si = 0; si < gAllSpots.length(); ++si) {
		if (LedgerFind(int(si)) >= 0)
			continue;
		if (!OnMap(gAllSpots[si]))
			continue;
		++open;
		if (!ai.CanDefReach(con, from, gAllSpots[si]))
			continue;
		++reach;
		if (!ai.CanDefReach(ask, askAt, gAllSpots[si]))
			++locked;
	}
	gPlantReach[plantId] = (open > 0) ? (float(reach) / float(open)) : 1.f;
	gPlantLocked[plantId] = (open > 0) ? (float(locked) / float(open)) : 0.f;
	gPlantOpenReach[plantId] = reach;
}

// EARLY WATER IS OWNED WATER (apexearth: "the earlier you get into the water
// the more likely you are to own it"). The premium on land-locked ground is
// full while nobody holds it and decays as the enemy's own navy appears --
// their naval cost against our army, so this is a contest reading, not a
// clock.
float WaterUncontested()
{
	// MY SHARE of their navy against MY army -- the same one-against-all
	// shape as the rest of tonight's audit.
	const float foe = Military::EnemyCostOf(Unit::Role::SUB.type)
			* AnswerShare();
	if (foe <= 0.f)
		return 1.f;
	const float ours = ArmyValue();
	return 1.f / (1.f + foe / ((ours > 1.f) ? ours : 1.f));
}

// A land plant whose whole fighting line (AA aside) crosses water: the hover
// lab. Where our land is cut off it is a way onto the water.
bool CrosserLine(int d)
{
	if (!LandLocked() || (PlantClass(d) == PC_WATER))
		return false;
	bool any = false;
	const array<int>@ prods = Catalog::gBuildsList[d];
	for (uint i = 0; i < prods.length(); ++i) {
		const int pd = prods[i];
		if (!Catalog::gAvailable[pd] || !LineCombat(pd))
			continue;
		const CCircuitDef@ cd = Catalog::Def(pd);
		if ((cd !is null) && cd.IsRoleAny(Unit::Role::AA.mask))
			continue;
		if (!SurfaceCrosser(pd) && !IsNavyDef(pd))
			return false;
		any = true;
	}
	return any;
}

int OwnedCrosserPlants()
{
	int n = 0;
	const array<int>@ _own38 = OwnedDefs();
	for (uint _oi38 = 0; _oi38 < _own38.length(); ++_oi38) {
		const uint d = uint(_own38[_oi38]);
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[int(d)]
			|| (Catalog::gBuildsList[int(d)].length() == 0))
			continue;
		if (CrosserLine(int(d)))
			n += gOwnCount[d];
	}
	return n;
}

// A hull that can get out onto the water: flies, walks the bottom, floats,
// or covers more of the map than the land is (a hover).
bool WaterReachDef(int d)
{
	if (Catalog::gFlyer[d] || Catalog::gAmphib[d] || Catalog::gFloater[d])
		return true;
	float lp = aiTerrainMgr.GetLandPercent();
	if (lp <= 1.5f)
		lp *= 100.f;
	return ai.DefMapCoverage(Catalog::Def(d)) > lp + 5.f;
}

// Does a constructor of ours (the commander aside) reach the water?
bool OwnWaterCon()
{
	const array<int>@ _own39 = OwnedDefs();
	for (uint _oi39 = 0; _oi39 < _own39.length(); ++_oi39) {
		const uint d = uint(_own39[_oi39]);
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di]
			|| Catalog::gRezzer[di])
			continue;
		const CCircuitDef@ cd = Catalog::Def(di);
		if ((cd !is null) && !cd.IsRoleAny(Unit::Role::COMM.mask) && WaterReachDef(di))
			return true;
	}
	return false;
}

// This plant makes a constructor that reaches the water (his 2026-09-28: "a
// vehicle plant or hover plant will always be able to get a con into that
// water").
bool PlantMakesWaterCon(int plant)
{
	const array<int>@ pr = Catalog::gBuildsList[plant];
	for (uint i = 0; i < pr.length(); ++i) {
		if (Catalog::gAvailable[pr[i]] && Catalog::gMobile[pr[i]] && Catalog::gBuilder[pr[i]]
			&& !Catalog::gRezzer[pr[i]] && WaterReachDef(pr[i]))
			return true;
	}
	return false;
}

int OwnedWaterPlants()
{
	int n = 0;
	const array<int>@ _own40 = OwnedDefs();
	for (uint _oi40 = 0; _oi40 < _own40.length(); ++_oi40) {
		const uint d = uint(_own40[_oi40]);
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[int(d)]
			|| (Catalog::gBuildsList[int(d)].length() == 0))
			continue;
		if (PlantClass(int(d)) == PC_WATER)
			n += gOwnCount[d];
	}
	return n;
}

// A plant's TIER, in the only currency separating a T1 lab from its advanced
// version: the best extractor its own constructors can reach. The enemy
// comparison instead uses the plant's own attribute -- that is about what the
// LINE fields, not what its constructors dig.
//
// A SECOND LINE IS THE DEAR WAY TO BUY THROUGHPUT (apexearth 2026-08-27: "the
// right choice is to add more nanos to the lab instead of making another lab.
// You'd only want a second lab if you ran out of room to make nanos"). Read
// off the defs, not his numbers: a construction turret is ~9x the BP per
// metal of an advanced lab. Returned as the RATIO between the two, so nothing
// is forbidden -- the second lab wins when the substitute is unavailable.
int gNextPlantDupLog = 0;
int gNextPlantLiftLog = 0;
int gNextPlantCandLog = 0;
int gNextWetReachLog = 0;
int gNextYardHoldLog = 0;
// When one of our water plants last died (main.as unit-destroyed).
int gYardLostAt = -999999;

float gDupNanoBp = -1.f;   // the catalog's best lathe per metal, found once
float DupBpSubstMul(int d)
{
	const float pm = Catalog::gCostM[d];
	if (pm <= 1.f)
		return 1.f;
	const float pbp = Catalog::gBuildPower[d] / pm;
	if ((gDupNanoBp < 0.f) && (Catalog::gDefCount > 0))
		gDupNanoBp = DupNanoBp();
	const float nbp = gDupNanoBp;
	if ((nbp <= 0.f) || (pbp >= nbp))
		return 1.f;
	return pbp / nbp;
}

float DupNanoBp()
{
	float nbp = 0.f;
	for (int n = 1; n <= Catalog::gDefCount; ++n) {
		if (!Catalog::gAvailable[n] || Catalog::gMobile[n])
			continue;
		// A standing lathe that builds nothing of its own: a nano, not a plant.
		if ((Catalog::gBuildPower[n] <= 0.f) || (Catalog::gCostM[n] <= 1.f)
			|| (Catalog::gBuildsList[n].length() > 0))
			continue;
		const float r = Catalog::gBuildPower[n] / Catalog::gCostM[n];
		if (r > nbp)
			nbp = r;
	}
	return nbp;
}

// THE WEALTH WAIVER. The copy ban and the one-advanced-plant-at-a-time
// serialization both argue "the cheaper substitute exists"; structural
// overflow above the drain of a whole extra line is that argument already
// falsified.
bool WealthWaiver()
{
	const float bar = ai.GetTunable("apex_copy_overflow_m", TUNE_COPY_OVERFLOW_M);
	return OverflowM() >= ((bar > 1.f) ? bar : 140.f);
}

// The waiver argues that unspent metal falsifies the nano substitute; an idle
// standing line falsifies the waiver instead -- its metal has no orders, not
// too few lathes -- so a copy of a production def needs every line working.
bool LinesAllWorking(int d)
{
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f !is null) && (int(f.circuitDef.id) == d) && !LineWorking(f))
			return false;
	}
	return true;
}

// A plant whose nano block is FULL: the last pack walk beside a plant of this
// def found no cell. Until then the copy's metal buys nanos at the standing
// line (apexearth 2026-09-13, their one gantry under 170 nanos: "fewer
// Gantries -- but to better support the gantries we have with nanos").
array<int> gNanoDryAt;

void NoteNanoDry(int d, bool dry)
{
	while (int(gNanoDryAt.length()) <= d)
		gNanoDryAt.insertLast(-1000000);
	gNanoDryAt[d] = dry ? ai.frame : -1000000;
}

bool NanoBlockFull(int d)
{
	if ((d < 0) || (d >= int(gNanoDryAt.length())))
		return false;
	return (ai.frame - gNanoDryAt[d]) < 120 * SECOND;
}

bool CopyWaived(int d)
{
	// NANOS FIRST, ALWAYS (his rule, restated 2026-09-30 after an overflow
	// waiver skipped it: "make some nanoturrets around the factories before
	// you even consider making a second factory -- you don't ever break it").
	// No copy while the standing plant's nano block has room. Once it is full,
	// overflow (or the eco seat, for the advanced air plant within its income
	// curve) buys the next line.
	if (!NanoBlockFull(d) || (GantryShort() !is null))
		return false;
	if (AirPlant(d) && (PlantTier(d) >= 2)) {
		CCircuitDef@ want = Air::IntelPlantToBuild();
		if ((want !is null) && (int(want.id) == d)
			&& (WealthWaiver() || EcoRoleActive() || gWasEcoSeat))
			return true;
	}
	return WealthWaiver() && LinesAllWorking(d);
}

// A copy bought to MOVE a walled-in plant (the reclaim market's move law):
// the twin is the vacancy's successor, not a duplicate.
array<int> gMoveWaivedAt;
void NoteMoveWaived(int d)
{
	while (int(gMoveWaivedAt.length()) <= d)
		gMoveWaivedAt.insertLast(-1000000);
	gMoveWaivedAt[d] = ai.frame;
	NoteCopyWaived(d);
}
bool MoveWaived(int d)
{
	if ((d < 0) || (d >= int(gMoveWaivedAt.length())))
		return false;
	return (ai.frame - gMoveWaivedAt[d]) < 30 * SECOND;
}

// A copy bought under the waiver is SAFE FROM THE RETIRE LAW for the replant
// window: the squeezed-economy test alone still flapped during spend bursts
// (armshltx reclaimed and rebuilt 5x/game after the first damping), because
// buying the copy is itself what drains the bank below the squeeze bar.
array<int> gCopyWaivedAt;

void NoteCopyWaived(int d)
{
	while (int(gCopyWaivedAt.length()) <= d)
		gCopyWaivedAt.insertLast(-1000000);
	gCopyWaivedAt[d] = ai.frame;
}

bool RecentCopyWaiver(int d)
{
	if ((d < 0) || (d >= int(gCopyWaivedAt.length())))
		return false;
	const float win = ai.GetTunable("apex_replant_window_s", TUNE_REPLANT_WINDOW_S);
	return (ai.frame - gCopyWaivedAt[d]) < int(((win > 1.f) ? win : 600.f) * SECOND);
}

int PlantTier(int plantId)
{
	const int at = Factory::userData[plantId].attr;
	if ((at & Factory::Attr::T3) != 0)
		return 3;
	if ((at & Factory::Attr::T2) != 0)
		return 2;
	return 1;
}

float FoeTierPlantMul(int plantId)
{
	const float k = ai.GetTunable("apex_foe_tier_fade", TUNE_FOE_TIER_FADE);
	if (k <= 0.f)
		return 1.f;
	return 1.f / (1.f + k * Military::FoeTierAbove(PlantTier(plantId)));
}

float PlantReachOf(int plantId)
{
	float best = 0.f;
	const array<int>@ prods = Catalog::gBuildsList[plantId];
	for (uint p = 0; p < prods.length(); ++p) {
		if (!Catalog::gMobile[prods[p]] || !Catalog::gBuilder[prods[p]])
			continue;
		const array<int>@ pb = Catalog::gBuildsList[prods[p]];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gExtractsM[pb[q]] > best)
				best = Catalog::gExtractsM[pb[q]];
		}
	}
	return best;
}

// The best tier a domain offers -- what a copy of an outgrown tier is being
// bought INSTEAD OF. Catalog-wide, so refreshed on a slow tick.
array<float> gDomReach(3, 0.f);
int gDomReachAt = 0;

// The best constructor reach among plants we OWN or have ordered, per domain.
// The tier discount compares against this: the catalog's best (below) says
// what the game offers, not what we field.
array<float> gOwnDomReach(3, 0.f);
int gOwnDomReachAt = -1;
float OwnedDomainReach(int dClass)
{
	if (ai.frame >= gOwnDomReachAt) {
		gOwnDomReachAt = ai.frame + 10 * SECOND;
		for (uint c = 0; c < gOwnDomReach.length(); ++c)
			gOwnDomReach[c] = 0.f;
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if ((f is null) || (f.circuitDef is null))
				continue;
			const int fd = int(f.circuitDef.id);
			const float r = PlantReachOf(fd);
			const int c = PlantClass(fd);
			if (r > gOwnDomReach[c])
				gOwnDomReach[c] = r;
		}
		for (uint li = 0; li < Requests::gLive.length(); ++li) {
			IUnitTask@ t = Requests::gLive[li];
			if ((t is null) || t.IsDead() || (t.buildDef is null))
				continue;
			const int td = int(t.buildDef.id);
			if (Catalog::gMobile[td] || (Catalog::gBuildsList[td].length() == 0))
				continue;
			const float r = PlantReachOf(td);
			const int c = PlantClass(td);
			if (r > gOwnDomReach[c])
				gOwnDomReach[c] = r;
		}
	}
	return ((dClass >= 0) && (dClass < int(gOwnDomReach.length())))
			? gOwnDomReach[dClass] : 0.f;
}

float BestDomainReach(int dClass)
{
	if (ai.frame >= gDomReachAt) {
		gDomReachAt = ai.frame + 30 * SECOND;
		for (uint c = 0; c < gDomReach.length(); ++c)
			gDomReach[c] = 0.f;
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			if (!Catalog::gAvailable[d] || Catalog::gMobile[d])
				continue;
			if (Catalog::gBuildsList[d].length() == 0)
				continue;
			const float r = PlantReachOf(d);
			const int c = PlantClass(d);
			if (r > gDomReach[c])
				gDomReach[c] = r;
		}
	}
	return ((dClass >= 0) && (dClass < int(gDomReach.length())))
			? gDomReach[dClass] : 0.f;
}

// Does this plant make anything no plant we own can make? The flexibility
// case (apexearth: "you're a vehicle producer but want access to rezbots").
// A line that only repeats what we already offer is a pure duplicate.
bool UnlocksProduct(int plantId)
{
	// A product is made if any of its producers is in the commitment ledger
	// in any state -- standing, half-built, orphaned frame or on order
	// (flipped 2026-08-27, shadow clean across the proving games).
	const array<int>@ prods = Catalog::gBuildsList[plantId];
	for (uint p = 0; p < prods.length(); ++p) {
		bool made = false;
		const array<int>@ by = Catalog::gBuiltBy[prods[p]];
		for (uint b = 0; b < by.length(); ++b) {
			if (ComAny(by[b], CS_ANY)) {
				made = true;
				break;
			}
		}
		if (!made)
			return true;
	}
	return false;
}

// A PLANT UNLOCKS WHAT WE WANT, NOT WHAT WE LACK (apexearth 2026-09-22: "these
// plants should only be built if we actually desire to create something out of
// it"). UnlocksProduct above is a capability test, so the hover platform read
// unlocks=1 all game and kept the copy exemption -- full expansion value and an
// escape from the copy ban -- while every unit it could make was worth less
// than what our standing lines already field. This is the same question asked
// in worth: the best NEW combat unit this line would add, over the best one we
// already produce. Against what we OWN, never the catalog -- nothing is
// outgrown before its better exists, and with nothing standing every line is
// an unlock (which is what leaves the opening alone).
float gUnlockOwnBest = 0.f;
int gUnlockOwnAt = -999999;

float OwnedBestUnitWorth()
{
	if (ai.frame < gUnlockOwnAt + 10 * SECOND)
		return gUnlockOwnBest;
	gUnlockOwnAt = ai.frame;
	float best = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gMobile[d] || (Catalog::gBuildsList[d].length() == 0)
			|| !ComAny(d, CS_ANY))
			continue;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			if (!Catalog::gAvailable[prods[p]] || !LineCombat(prods[p]))
				continue;
			const float v = LineUnitWorth(prods[p]);
			if (v > best)
				best = v;
		}
	}
	gUnlockOwnBest = best;
	return best;
}

float UnlockWorth(int plantId)
{
	const float own = OwnedBestUnitWorth();
	if (own <= 0.f)
		return 1.f;
	float best = 0.f;
	const array<int>@ prods = Catalog::gBuildsList[plantId];
	for (uint p = 0; p < prods.length(); ++p) {
		const int pd = prods[p];
		if (!Catalog::gAvailable[pd] || !LineCombat(pd))
			continue;
		bool made = false;
		const array<int>@ by = Catalog::gBuiltBy[pd];
		for (uint b = 0; b < by.length(); ++b) {
			if (ComAny(by[b], CS_ANY)) {
				made = true;
				break;
			}
		}
		if (made)
			continue;
		float v = LineUnitWorth(pd);
		// AN UNLOCK WE CANNOT AFFORD TO USE IS NOT AN UNLOCK. The worth of a
		// plant is the products we will actually order out of it, and this
		// asked only whether the product is BETTER, never whether the bill for
		// the plant plus one unit is reachable -- so an Experimental Aircraft
		// Plant at 8,500 metal was bought at 80 metal/s and never built a
		// thing (apexearth, watching). Saturating, so a cheap unlock is
		// untouched and only the far bets are discounted.
		if (ai.GetTunable("apex_unlock_afford", TUNE_UNLOCK_AFFORD) > 0.f) {
			const float horU = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
			const float reachU = EcoPowerM() * ((horU > 1.f) ? horU : 180.f);
			const float billU = Catalog::gCostM[plantId] + Catalog::gCostM[pd];
			if ((reachU > 0.f) && (billU > 0.f))
				v *= reachU / (reachU + billU);
		}
		if (v > best)
			best = v;
	}
	return best / own;
}

// MODEL: a plant's return is its constructor pipeline -- each con carries
// roughly one open spot's stream while expansion ground remains, plus the
// overflow the pipeline would capture (arithmetic, see OverflowM). One named
// discount (apex_plant_pipe) prices the pipeline's losses; no spot ground
// left means no plant value at all.
int gNextPlantParLog = 0;

// HOW MUCH OF THE MAP THIS LINE'S ARMY CAN MOVE AROUND IN, relative to the
// best any line offers (apexearth 2026-09-01: "If we're on a mostly flat map
// then we should be picking tanks... Reach and speed are what matter").
//
// Reach is ai.DefMapCoverage -- the engine's own per-movement-type partition,
// so nothing here samples heights or picks a slope bar. Speed is already in
// the price through MobilityMult. PRODUCTION half only: the constructor half
// self-corrects through MeasureReach's CanDefReach.
array<float> gLineCov;
float gLineCovBest = -1.f;

float LineCoverage(int plantDef)
{
	if (int(gLineCov.length()) <= Catalog::gDefCount)
		gLineCov.resize(Catalog::gDefCount + 1);
	if (gLineCov[plantDef] > 0.f)
		return gLineCov[plantDef];
	// THE MEDIAN PRODUCT, NOT THE BEST ONE. Taking the max meant a single
	// all-terrain product spoke for the whole line: measured on three maps,
	// armalab read 100.0 everywhere while armavp read 73-95, which is not
	// terrain truth, it is one outlier in the T2 bot lab's build list. The
	// median is what the line will actually mass.
	array<float> cov;
	const array<int>@ prods = Catalog::gBuildsList[plantDef];
	for (uint i = 0; i < prods.length(); ++i) {
		const int pd = prods[i];
		if (!Catalog::gMobile[pd] || Catalog::gBuilder[pd]
			|| (Catalog::gPower[pd] <= 1.f))
			continue;
		cov.insertLast(ai.DefMapCoverage(Catalog::Def(pd)));
	}
	if (cov.length() == 0) {
		gLineCov[plantDef] = 1.f;
		return 1.f;
	}
	cov.sortAsc();
	gLineCov[plantDef] = cov[cov.length() / 2];
	if (gLineCov[plantDef] <= 0.f)
		gLineCov[plantDef] = 1.f;
	return gLineCov[plantDef];
}

int gLineCovLogAt = 0;
float LineTerrainMul(int plantDef)
{
	if (ai.GetTunable("apex_line_terrain", TUNE_LINE_TERRAIN) <= 0.f)
		return 1.f;
	if (gLineCovBest < 0.f) {
		gLineCovBest = 0.f;
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
				|| (Catalog::gBuildsList[d].length() == 0))
				continue;
			const float c = LineCoverage(d);
			if (c > gLineCovBest)
				gLineCovBest = c;
		}
	}
	if (gLineCovBest <= 0.f)
		return 1.f;
	const float m = LineCoverage(plantDef) / gLineCovBest;
	// ONE CENSUS, not a rate-limited sample. A per-120s line shows whichever
	// plant happened to ask and cannot answer the only question this measure
	// exists for -- does the map discriminate between the lines at all.
	if (gLineCovLogAt == 0) {
		gLineCovLogAt = 1;
		string row = "";
		for (int d2 = 1; d2 <= Catalog::gDefCount; ++d2) {
			if (!Catalog::gAvailable[d2] || Catalog::gMobile[d2]
				|| (Catalog::gBuildsList[d2].length() == 0))
				continue;
			const float c2 = LineCoverage(d2);
			row += " " + Catalog::Def(d2).GetName()
					+ "=" + formatFloat(c2, "", 0, 1);
		}
		AiLog("apex: line-terrain t=" + ai.teamId
			+ " best=" + formatFloat(gLineCovBest, "", 0, 1) + row);
	}
	return (m > 1.f) ? 1.f : m;
}

// WHAT THE LINE IS WORTH HERE: its units times the ground they can cross.
// apexearth 2026-09-12: "we just make bots almost all the time. So in maps
// where vehicles are obviously more powerful, we don't do quite as well" and
// "if the map is mostly flat with just some hills then we want vehicles but
// if it is full of hills all over the place then we might want bots". The
// units' worth is the median product on the yardstick production buys single
// units with (UnitPPC, speed, sight); the ground is the pathfinder's own
// reach for the line (LineCoverage). Their product, against the best line of
// the class and tier, multiplies the WHOLE plant price -- the opening plant
// is bought at minute 1 for its constructor, and a production-half term
// moved nothing there (docs/27).
array<float> gLineQual;
array<float> gLineMulV;
int gLineQualAt = -999999;

// The dry-map x0 the UNIT market already applies (production.as's amphib test,
// same shape), asked where the LINE is priced -- a plant bought for products
// production.as will refuse is bought for nothing.
bool AmphibDead(int pd)
{
	if (!Catalog::gAmphib[pd] || MapHasWater())
		return false;
	const CCircuitDef@ cd = Catalog::Def(pd);
	if ((cd !is null) && cd.IsRoleAny(Unit::Role::AA.mask))
		return false;
	return UnitCore(pd) < 1.f;
}

// A unit that cannot get to the enemy is worth nothing (his ruling 2026-09-27,
// Coast To Coast): towers guard our shore. AA is exempt, the air comes to it;
// a def that cannot stand at home (a ship) is not judged from there.
array<int> gReachAt;
array<bool> gReachDead;
bool gReachProbeLogged = false;

bool ReachDead(int pd)
{
	// A ship holds the water and shells the shore; whether it can sail to
	// their base is not its job (his 2026-09-28: T2 warships read :reach).
	if (!Catalog::gMobile[pd] || Catalog::gFlyer[pd] || !Builder::gHomeSet
		|| Catalog::gFloater[pd] || Catalog::gSub[pd])
		return false;
	if (int(gReachAt.length()) <= Catalog::gDefCount) {
		const uint was = gReachAt.length();
		gReachAt.resize(Catalog::gDefCount + 1);
		gReachDead.resize(Catalog::gDefCount + 1);
		for (uint i = was; i < gReachAt.length(); ++i) {
			gReachAt[i] = -999999;
			gReachDead[i] = false;
		}
	}
	if (ai.frame < gReachAt[pd] + MINUTE)
		return gReachDead[pd];
	gReachAt[pd] = ai.frame;
	CCircuitDef@ cd = Catalog::Def(pd);
	// The start point itself can sit on a sector the pathfinder gives this
	// def no area for (half the seats on Coast To Coast), so take the nearest
	// ground around it that it can stand on.
	AIFloat3 home = Builder::gHomePos;
	bool stands = false;
	for (int ring = 0; (ring <= 8) && !stands && (cd !is null); ++ring) {
		const int n = (ring == 0) ? 1 : 8;
		for (int k = 0; (k < n) && !stands; ++k) {
			const float a = 6.2831853f * float(k) / float(n);
			const AIFloat3 p(Builder::gHomePos.x + 128.f * ring * cos(a), 0.f,
					Builder::gHomePos.z + 128.f * ring * sin(a));
			if (OnMap(p) && ai.CanDefReach(cd, p, p)) {
				home = p;
				stands = true;
			}
		}
	}
	bool dead = false;
	if (!gReachProbeLogged && (cd !is null) && !Catalog::gAmphib[pd]) {
		gReachProbeLogged = true;
		const AIFloat3 fa = Front::FoeAnchor();
		const AIFloat3 bx = aiSetupMgr.GetEnemyBoxCentre();
		AiLog("apex: reach-probe t=" + ai.teamId + " " + cd.GetName()
			+ " home=" + int(home.x) + "," + int(home.z) + " off=" + int(home.distance2D(Builder::gHomePos)) + " stands=" + (stands ? 1 : 0)
			+ " anchor=" + int(fa.x) + "," + int(fa.z) + ":" + (ai.CanDefReachAt(cd, home, fa, 256.f) ? 1 : 0)
			+ " box=" + int(bx.x) + "," + int(bx.z) + ":" + (ai.CanDefReachAt(cd, home, bx, 256.f) ? 1 : 0));
	}
	if ((cd !is null) && !cd.IsRoleAny(Unit::Role::AA.mask) && stands)
	{
		float r = Catalog::gMaxRange[pd];
		if (r < 256.f)
			r = 256.f;
		array<AIFloat3> foe;
		foe.insertLast(Front::FoeAnchor());
		foe.insertLast(aiSetupMgr.GetEnemyBoxCentre());
		foe.insertLast(AIFloat3(float(AiTerrainWidth()) - home.x, 0.f,
				float(AiTerrainHeight()) - home.z));
		dead = true;
		for (uint i = 0; i < foe.length(); ++i) {
			if (OnMap(foe[i]) && ai.CanDefReachAt(cd, home, foe[i], r)) {
				dead = false;
				break;
			}
		}
	}
	if (dead != gReachDead[pd])
		AiLog("apex: reach-dead t=" + ai.teamId + " " + cd.GetName()
			+ " dead=" + (dead ? 1 : 0) + " r=" + int(Catalog::gMaxRange[pd]));
	gReachDead[pd] = dead;
	return dead;
}

// A line with no combat unit to judge (AA answers only what flies to it)
// reaches by default.
bool LineReaches(int plantDef)
{
	bool any = false;
	const array<int>@ prods = Catalog::gBuildsList[plantDef];
	for (uint i = 0; i < prods.length(); ++i) {
		const int pd = prods[i];
		if (!Catalog::gAvailable[pd] || !LineCombat(pd))
			continue;
		const CCircuitDef@ cd = Catalog::Def(pd);
		if ((cd is null) || cd.IsRoleAny(Unit::Role::AA.mask))
			continue;
		if (!ReachDead(pd))
			return true;
		any = true;
	}
	return !any;
}

// A T1 ground line of ours cannot reach the enemy: the island start, where
// the water has to be taken early (his ruling 2026-09-27).
bool gLandLocked = false;
int gLandLockedAt = -999999;

bool LandLocked()
{
	if (ai.frame < gLandLockedAt + 10 * SECOND)
		return gLandLocked;
	gLandLockedAt = ai.frame;
	const bool was = gLandLocked;
	gLandLocked = false;
	int by = -1;
	for (int d = 1; (d <= Catalog::gDefCount) && !gLandLocked; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0) || (LineTier(d) != 1)
			|| (PlantClass(d) != PC_LAND) || !Producible(d))
			continue;
		gLandLocked = !LineReaches(d);
		if (gLandLocked)
			by = d;
	}
	if (gLandLocked != was)
		AiLog("apex: landlocked t=" + ai.teamId + " " + (gLandLocked ? 1 : 0)
			+ " by=" + ((by > 0) ? Catalog::Def(by).GetName() : "-"));
	return gLandLocked;
}

float LineUnitWorth(int pd)
{
	if (AmphibDead(pd) || ReachDead(pd))
		return 0.f;
	const float tFoeSpeed = FoeSpeedCap();
	float v = UnitPPC(pd) * WaterFightMul(pd);
	if (tFoeSpeed > 0.f)
		v *= 1.f + (Catalog::gSpeed[pd] / tFoeSpeed)
				* ai.GetTunable("apex_speed_worth", TUNE_SPEED_WORTH);
	v *= 1.f + (Catalog::gLosR[pd] / 1000.f)
			* ai.GetTunable("apex_los_worth", TUNE_LOS_WORTH);
	return v;
}

// The lines a commander's tree reaches, and their tier by unlock depth --
// Factory::userData only tiers the configured plants, so the underwater
// gantry read T1 and the scavenger labs (built by scavenger cons) ranked at all.
array<int> gLineTier;   // 0 = not in any commander's tree

int LineTier(int d)
{
	if (int(gLineTier.length()) <= Catalog::gDefCount) {
		gLineTier.resize(Catalog::gDefCount + 1);
		for (int i = 0; i <= Catalog::gDefCount; ++i)
			gLineTier[i] = 0;
		array<int> frontier;
		for (int i = 1; i <= Catalog::gDefCount; ++i) {
			const CCircuitDef@ cd = Catalog::Def(i);
			if ((cd !is null) && cd.IsRoleAny(Unit::Role::COMM.mask)) {
				gLineTier[i] = 1;
				frontier.insertLast(i);
			}
		}
		// a builder's tier is the tier of the plant that made it; a plant's
		// tier is its builder's
		while (frontier.length() > 0) {
			array<int> next;
			for (uint f = 0; f < frontier.length(); ++f) {
				const int b = frontier[f];
				const array<int>@ made = Catalog::gBuildsList[b];
				for (uint m = 0; m < made.length(); ++m) {
					const int d2 = made[m];
					if (gLineTier[d2] != 0)
						continue;
					if (Catalog::gMobile[d2]) {
						if (!Catalog::gBuilder[d2])
							continue;
						gLineTier[d2] = gLineTier[b];          // con of this tier
					} else if (Catalog::gBuildsList[d2].length() > 0) {
						// commanders are expanded first, so every plant a
						// commander places is T1; a con places the tier above
						gLineTier[d2] = (gLineTier[b] == 1 && Catalog::Def(b).IsRoleAny(Unit::Role::COMM.mask))
								? 1 : (gLineTier[b] + 1);
					} else {
						continue;
					}
					next.insertLast(d2);
				}
			}
			frontier = next;
		}
	}
	return (d >= 0 && d < int(gLineTier.length())) ? gLineTier[d] : 0;
}

// THE MEDIAN UNIT, NOT THE BEST ONE, as LineCoverage: the best is one
// outlier speaking for the line (the T1 hover plant read 5x the bot lab on
// the Halberd alone); the median is what the line will actually mass.
float LineBestWorth(int plantDef)
{
	array<float> w;
	const array<int>@ prods = Catalog::gBuildsList[plantDef];
	for (uint i = 0; i < prods.length(); ++i) {
		if (!Catalog::gAvailable[prods[i]] || !LineCombat(prods[i]))
			continue;
		w.insertLast(LineUnitWorth(prods[i]));
	}
	// -1 is "no combat line here", which the census has no opinion about; 0 is
	// a combat line whose every unit prices at nothing, which is a verdict.
	if (w.length() == 0)
		return -1.f;
	w.sortAsc();
	return w[w.length() / 2];
}

// ShieldShare and the worth means move, so the census is re-read per minute;
// the log line is the instrument -- what OUR model thinks of each line here.
float LineQualityMul(int plantDef)
{
	if (int(gLineQual.length()) <= Catalog::gDefCount) {
		gLineQual.resize(Catalog::gDefCount + 1);
		gLineMulV.resize(Catalog::gDefCount + 1);
	}
	if (ai.frame >= gLineQualAt + MINUTE) {
		gLineQualAt = ai.frame;
		array<float> bestOf(12, 0.f);   // class*4 + tier
		array<float> bestMul(12, 0.f);
		array<float> own(Catalog::gDefCount + 1, -1.f);
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			// a plant is a line only if a mobile builder can place it: the
			// scavenger lootbox "plants" build things no line ever will
			if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
				|| (Catalog::gBuildsList[d].length() == 0) || (LineTier(d) == 0)
				|| !Producible(d))   // OUR tree: against the other faction's best
				continue;            // a whole faction's plants would price at 0.66
			own[d] = LineBestWorth(d);
			if (own[d] < 0.f) {
				own[d] = -1.f;
				continue;
			}
			const int k = PlantClass(d) * 4 + ((LineTier(d) > 3) ? 3 : LineTier(d));
			if (own[d] > bestOf[k])
				bestOf[k] = own[d];
			const float m = own[d] * LineTerrainMul(d);
			if (m > bestMul[k])
				bestMul[k] = m;
		}
		string row = "";
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			gLineQual[d] = 1.f;
			gLineMulV[d] = 1.f;
			if (own[d] < 0.f)
				continue;
			const int k = PlantClass(d) * 4 + ((LineTier(d) > 3) ? 3 : LineTier(d));
			if (bestOf[k] <= 0.f)
				continue;
			gLineQual[d] = own[d] / bestOf[k];
			gLineMulV[d] = (bestMul[k] > 0.f) ? (own[d] * LineTerrainMul(d) / bestMul[k]) : 1.f;
			if (PlantClass(d) == PC_LAND)
				row += " " + Catalog::Def(d).GetName() + "=" + formatFloat(gLineMulV[d], "", 0, 2)
						+ "(q" + formatFloat(gLineQual[d], "", 0, 2)
						+ " t" + formatFloat(LineTerrainMul(d), "", 0, 2) + ")";
		}
		AiLog("apex: line-quality t=" + ai.teamId + row);
	}
	if (ai.GetTunable("apex_line_quality", TUNE_LINE_QUALITY) <= 0.f)
		return 1.f;
	return gLineQual[plantDef];
}

// WHAT A LINE'S UNITS HAVE ACTUALLY TRADED (his ruling 2026-09-22: "per-unit
// performance absolutely should feed into factory selection"). Per unit, the
// exchange record from both sides of the matrix: our copies' record, and the
// enemy's copies of the same def against us -- in a mirror their Janus is
// evidence for a vehicle plant we have never built. The line reads its median
// combat unit; the plant is priced against the best line of its class and
// tier, so the order moves and the class's total does not.
array<float> gRecLine;
int gRecLineAt = -999999;
// Against its own line class's bar, as RecordRaw reads it: "a tank is judged
// as a tank" (his 2026-09-19). Read raw, a vehicle plant's tanks scored under a
// bot lab's skirmishers by construction and no seat ever opened vehicles.
float UnitRecordAny(int d)
{
	const CCircuitDef@ cd = Catalog::Def(d);
	const float bar = RecordBar(LineClassOf(d));
	return 0.5f * (ai.RecordRatio(cd, -1) + ai.RecordFoeRatio(cd, null))
			/ ((bar > 0.01f) ? bar : 1.f);
}

float RecordLineMul(int plantDef)
{
	if (int(gRecLine.length()) <= Catalog::gDefCount)
		gRecLine.resize(Catalog::gDefCount + 1);
	if (ai.frame >= gRecLineAt + MINUTE) {
		gRecLineAt = ai.frame;
		array<float> own(Catalog::gDefCount + 1, 0.f);
		array<float> best(12, 0.f);
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			gRecLine[d] = 1.f;
			if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
				|| (Catalog::gBuildsList[d].length() == 0) || (LineTier(d) == 0)
				|| !Producible(d))
				continue;
			array<float> r;
			const array<int>@ prods = Catalog::gBuildsList[d];
			for (uint i = 0; i < prods.length(); ++i) {
				if (Catalog::gAvailable[prods[i]] && LineCombat(prods[i]))
					r.insertLast(UnitRecordAny(prods[i]));
			}
			if (r.length() == 0)
				continue;
			r.sortAsc();
			own[d] = r[r.length() / 2];
			const int k = PlantClass(d) * 4 + ((LineTier(d) > 3) ? 3 : LineTier(d));
			if (own[d] > best[k])
				best[k] = own[d];
		}
		string row = "";
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			if (own[d] <= 0.f)
				continue;
			const int k = PlantClass(d) * 4 + ((LineTier(d) > 3) ? 3 : LineTier(d));
			gRecLine[d] = own[d] / best[k];
			if (PlantClass(d) == PC_LAND)
				row += " " + Catalog::Def(d).GetName() + "=" + formatFloat(gRecLine[d], "", 0, 2)
						+ "(" + formatFloat(own[d], "", 0, 2) + ")";
		}
		AiLog("apex: record-line t=" + ai.teamId + row);
	}
	return gRecLine[plantDef];
}

// The line factor on the whole plant: units x ground, best line of the class
// and tier = 1. With the tunable off the terrain term alone applies, on the
// production half, as before.
float LineMul(int plantDef)
{
	LineQualityMul(plantDef);
	if (ai.GetTunable("apex_line_quality", TUNE_LINE_QUALITY) <= 0.f)
		return 1.f;
	return gLineMulV[plantDef];
}

// WHAT THE TEAM ALREADY FIELDS.
//
// apexearth, watching a 4v4 on Comet Catcher 2026-09-01: "I'm still seeing us
// start with 4 bot labs on comet catcher. Enemy seems to have done 2 bot labs,
// 1 vehicle, and 1 air."
//
// Four players, one map, one valuation, no coordination -- so all four compute
// the same answer and all four build it. The duplicate-line rule right below
// this reads ComLen(), OUR OWN commitment ledger, so it cannot see a teammate's
// lab at all; the only team-aware thing in the whole plant want is the naval
// lead's distance. BARb ends up with 2 bots, a vehicle and an air plant and so
// has answers we do not.
//
// A teammate's line is NOT a duplicate of mine -- their build power does not
// claim my ground and their cons do not serve my sites. What it does cover is
// the PRODUCTION half: the unit types that line fields exist on the team
// whether I built it or not. So this discounts prodOwn only, exactly where
// FoeTierPlantMul and LineTerrainMul already apply, and leaves conHalf whole.
//
// Not exclusivity: nothing forbids a fourth bot lab. It simply prices below the
// first vehicle plant once three teammates already field bots, which is the
// difference between a rule and a value.
int gTeamPlantAt = -999999;
array<int> gTeamPlantN;

void TeamPlantRefresh()
{
	// Every seat elects its first lab in the same opening seconds; read on a
	// 10 s clock, all eight saw an empty team and all eight opened bots.
	if ((ai.frame - gTeamPlantAt < 10 * SECOND) && (Factory::gFactoryCount > 0))
		return;
	gTeamPlantAt = ai.frame;
	if (int(gTeamPlantN.length()) <= Catalog::gDefCount)
		gTeamPlantN.resize(Catalog::gDefCount + 1);
	for (int i = 0; i <= Catalog::gDefCount; ++i)
		gTeamPlantN[i] = 0;
	// Publish what WE hold, so every mate can read it.
	for (uint ci = 0; ci < ComLen(); ++ci) {
		const int cd = gComDef[ci];
		if (Catalog::gBuildsList[cd].length() == 0)
			continue;
		if ((gComState[ci] != CS_FINISHED)
			&& ((gComTask[ci] is null)
				|| (Requests::Workers(gComTask[ci]) == 0)))
			continue;
		ai.PublishTeamValue("plant" + cd, 1.f);
	}
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0))
			continue;
		int n = 0;
		for (uint m = 0; m < mates.length(); ++m) {
			const int t = int(mates[m]);
			if (t == ai.teamId)
				continue;   // our own copies are the duplicate rule's job
			if (ai.ReadTeamValue(t, "plant" + d, 0.f) > 0.5f)
				++n;
		}
		gTeamPlantN[d] = n;
	}
}

// The production half's discount for a line the team already fields. 1.0 when
// nobody has it; falling as mates take it up, never to zero -- a fourth copy
// still produces, it is just no longer the team's best use of the metal.
float TeamLineMul(int d)
{
	if (ai.GetTunable("apex_team_line", TUNE_TEAM_LINE) <= 0.f)
		return 1.f;
	TeamPlantRefresh();
	if (int(gTeamPlantN.length()) <= d)
		return 1.f;
	const float w = ai.GetTunable("apex_team_line", TUNE_TEAM_LINE);
	return 1.f / (1.f + w * float(gTeamPlantN[d]));
}

Want@ ProposePlant(CCircuitUnit@ unit)
{
	Want w;
	// ONE PLANT START AT A TIME, ANY TIER (his watched loss: armlab and
	// armhp elected 8 frames apart at 16.7m; only T2/T3 were serialized).
	// Starts only -- standing copies stay governed by wealth, and the
	// waiver lifts this exactly like the advanced rule.
	if (AnyPlantInFlight()) {
		if (!WealthWaiver()) {
			AdvDeferLog("plant-any");
			return w;
		}
		// Logged so the audit can tell a sanctioned parallel start from the
		// simultaneous-start bug it hunts (non-copy starts print no 'copy
		// waived' line).
		if (ai.frame >= gNextPlantParLog) {
			gNextPlantParLog = ai.frame + 30 * SECOND;
			AiLog("apex: plant-par waived t=" + ai.teamId
				+ " overflow=" + int(OverflowM()));
		}
	}
	// The MARGINAL plant: worth anything only if income supports another
	// line (~50 m/s each, apexearth's number). Not a cap -- a price of zero
	// past what the economy can feed, of any lab type.
	TrackIncome();
	const float per = ai.GetTunable("apex_plant_income_per", TUNE_PLANT_INCOME_PER);
	// Metal nothing is spending counts as spare line capacity on top of the
	// income estimate: it is the direct proof the lines we hold cannot eat
	// what we make (apexearth: "if you are super wealthy, always overflowing
	// metal, make more Gantries... or adv air labs too").
	const float structInc = ((gIncEma > 0.f) ? gIncEma : Eco::MInc())
			+ OverflowM();
	const int supported = 1 + int(structInc / ((per > 1.f) ? per : 50.f));
	const bool overLine = (Factory::gFactoryCount
			+ Requests::LiveCountOf(int(Task::BuildType::FACTORY)) >= supported);
	// ...except the FIRST way into the water. A shipyard is not a second copy
	// of a land line -- it is the only production that reaches water mexes and
	// the water half of the map, so owning a T1 lab must not price it out
	// (apexearth). A second shipyard is parallel capacity like anything else,
	// and pays the marginal-line price again.
	const bool waterOnly = overLine;
	// The first-way-into-the-water exemption belongs to the NAVAL LEAD only:
	// per-player it marched eight commanders to eight beaches.
	if (overLine && !(MapHasWater() && (OwnedWaterPlants() == 0) && NavalLead()))
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	// Expansion stream while ground remains, PLUS the production appetite a
	// new line would serve -- a lost lab re-prices itself from the army gap
	// even when every spot is claimed.
	const float fillS0 = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float aGap = ArmyTarget() - ArmyValue();
	const int lines0 = (Factory::gFactoryCount > 0) ? Factory::gFactoryCount : 0;
	float prodTerm = (aGap > 0.f)
			? (aGap / ((fillS0 > 1.f) ? fillS0 : 180.f))
				/ float(1 + lines0)
			: 0.f;
	// A LINE WE CANNOT FEED ADDS NO THROUGHPUT (apexearth: "no point buying a
	// new lab if we cannot fully utilize the first one"). The army gap above
	// is DEMAND, and demand alone was the whole production case for another
	// plant -- so the further behind we fell, the more attractive a second lab
	// became, even while the lines we owned were already spending every metal
	// we made. What a new line can actually serve is bounded by metal nothing
	// is spending; at zero spare it is a slower copy of the queue we have.
	{
		const float spare = SpareMetalRate();
		if (prodTerm > spare)
			prodTerm = spare;
	}
	const float pipe = ai.GetTunable("apex_plant_pipe", TUNE_PLANT_PIPE)
			* Utilization();
	// The expansion half is per-plant: it is worth the share of open ground
	// this plant's own cons can reach (MeasureReach, applied below).
	const float stream = SpotM() * pipe;
	// The two halves are priced apart because only one of them is a TIER
	// question: the pipeline half (build power and expansion) is worth what
	// this plant's constructors reach, while the production half is worth
	// what the line can put on the field whatever tier it is.
	const float pipeTerm = BPGap() * pipe;
	const float prodHalf = prodTerm * pipe;
	if (stream + pipeTerm + prodHalf <= 0.05f)
		return w;
	// None of these varies with the candidate plant; the two flags and the
	// denial premium were re-read per rung, and the fallback anchor -- a base
	// interior probe -- was re-derived for every rung whose own site was unset.
	const float waterFirstK = ai.GetTunable("apex_water_first", TUNE_WATER_FIRST);
	const bool inflOn = ai.GetTunable("apex_plant_inflight", TUNE_PLANT_INFLIGHT) > 0.f;
	const bool substOn = ai.GetTunable("apex_dup_bp_subst", TUNE_DUP_BP_SUBST) > 0.f;
	AIFloat3 homeAnchor;
	bool homeAnchorSet = false;
	AIFloat3 upAnchor;
	bool upAnchorOk = false;
	// The opening plant, term by term: the decide line names only the winner.
	const bool candLog = (Factory::gFactoryCount == 0)
			&& (ai.frame >= gNextPlantCandLog);
	string cand = "";
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gSub[d])
			continue;   // submerged plants have no placement model
		if (Catalog::gBuildsList[d].length() == 0)
			continue;   // not a factory
		const int dClass = PlantClass(d);
		if (waterOnly && (dClass != PC_WATER))
			continue;
		// A naval lead with no hand that can reach its water buys the plant
		// that makes one before any other land plant.
		if ((dClass == PC_LAND) && MapHasWater() && NavalLead()
			&& (OwnedWaterPlants() == 0) && !OwnWaterCon() && !PlantMakesWaterCon(d))
			continue;
		// Hovers AND ships (his call 2026-09-28): once a yard stands, the next
		// land plant is the hover lab, whose cons build the land economy too.
		if (LandLocked() && (OwnedWaterPlants() > 0) && (OwnedCrosserPlants() == 0)
			&& (dClass == PC_LAND) && !CrosserLine(d))
			continue;
		// Cut off from the enemy, the first plant is a way onto the water: a
		// yard or a hover lab (his standing call, restated 2026-09-28).
		if (LandLocked() && (Factory::gFacUnits.length() == 0) && !AnyPlantInFlight()
			&& (dClass != PC_WATER) && !CrosserLine(d))
			continue;
		// An air line for a player who is neither the air lead nor the eco
		// seat waits for his mandatory-air income, the same bar the air
		// mandate keeps: this market bought one at 30 income for half a
		// team because air cons reach the whole of a cliff map, and the
		// team fielded air where the enemy walked in with ground.
		// A 1v1's lone player is the air lead by default and waits the same (his
		// 2026-10-03: "we shouldn't be making an air lab early at all").
		if ((dClass == PC_AIR) && (!Air::IsAirLead() || ((Military::AllyCount() <= 1.f) && !LandLocked()))
			&& !gEcoRole && !Military::EnemyAfloat()
			&& (Eco::MInc()
				< ai.GetTunable("apex_air_mandatory_income", TUNE_AIR_MANDATORY_INCOME)))
			continue;
		// ...and a FRONT seat of a team with a rear builds ground (apexearth
		// 2026-10-02: "they're the first to die to enemies and need strong
		// ground army and defense to survive").
		{
			AIFloat3 smh;
			if ((dClass == PC_AIR) && !Air::IsAirLead() && !gEcoRole
				&& (ShelterMate(smh) < 0) && Military::TeamHasSheltered())
				continue;
		}
		if (DuelAirTechHeld(d))
			continue;
		// FOCUS: ONE T1 LINE UNTIL T2 (apexearth 2026-10-03: "focusing on the
		// factories is good. Later on in the game, you can have multiple types"
		// -- 5-7 plants a seat against BARb's 4-5). Before our first advanced
		// plant a second T1 plant is not offered, unless it is the water
		// mandate or the air lead's air line; the spare goes to nanos and eco.
		// The eco seat spilling metal takes its air line too: air cons are the
		// hands it lacks, and they reach a site faster (his 2026-10-03).
		if ((PlantTier(d) < 2) && (TopOwnPlantTier() < 2) && (dClass != PC_WATER)
			&& !((dClass == PC_AIR) && Air::IsAirLead())
			&& !((dClass == PC_AIR) && gEcoRole && MetalWasting())
			&& ((Factory::gFacUnits.length() > 0) || AnyPlantInFlight()))
			continue;
		// The water mandate is held and ships-only -- see the naval election
		// above. The commander may place it (the old ban on commanders at
		// water plants was removed at his call 2026-09-28). The backoff kills
		// the elect-order-abort churn for every def alike.
		if (Builder::AbortBackoff(d))
			continue;
		if (dClass == PC_WATER) {
			if (!NavalLead())
				continue;
			if (!PlantMakesShips(d) && (NavShipyardDef() > 0))
				continue;   // a hover platform is not a navy
		}
		const AIFloat3 here = unit.GetPos(ai.frame);
		// A floating plant stands in water, not at the base anchor, and is
		// worth nothing on a map without real water to stand in.
		AIFloat3 site(-1.f, 0.f, -1.f);
		if (Catalog::gFloater[d]) {
			if (!MapHasWater())
				continue;
			// A bot con elected to a beach it cannot build from re-elects
			// the same site forever (unreach-safe x6, no shipyard in 20 min).
			site = WetPlantSiteFor(Catalog::Def(d),
					Builder::gHomeSet ? Builder::gHomePos : here, uid, here);
			if (!OnMap(site)) {
				if (ai.frame >= gNextWetReachLog) {
					gNextWetReachLog = ai.frame + 60 * SECOND;
					AiLog("apex: wet-unreach t=" + ai.teamId + " " + unit.circuitDef.GetName()
						+ " " + Catalog::Def(d).GetName());
				}
				continue;
			}
			// A YARD JUST SUNK IS NOT REBUILT INTO THE SAME FLEET (his
			// 2026-09-28: the south lake's yards died as they finished).
			// While the loss is fresh the next yard waits for a water gun
			// covering its shore; the water-defence want sites one there.
			if ((dClass == PC_WATER) && (ai.frame - gYardLostAt < 3 * MINUTE)
				&& !WaterGunCovers(site, 500.f)) {
				if (ai.frame >= gNextYardHoldLog) {
					gNextYardHoldLog = ai.frame + 30 * SECOND;
					AiLog(Factory::T() + "apex: yard-hold t=" + ai.teamId + " "
						+ Catalog::Def(d).GetName() + " at=" + int(site.x) + ","
						+ int(site.z) + " -- guns first");
				}
				continue;
			}
		}
		// A plant that cannot produce a mobile builder buys no expansion --
		// and the builder must be able to EXIST where the plant will stand: a
		// shipyard's ship-cons have no connected area at a land base (measured:
		// armsy chosen on Comet Catcher, a game-long placement failure).
		// The plant inherits its best product's MOBILITY: an air lab's cons
		// fly, which is what lets it compete once the base packs.
		const AIFloat3 at = OnMap(site) ? site : here;
		float bestMob = 0.f;
		int bestCon = -1;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int pd = prods[p];
			if (Catalog::gMobile[pd] && Catalog::gBuilder[pd]
				&& ai.CanDefReach(Catalog::Def(pd), at, at))
			{
				const float m = MobilityMult(pd);
				if (m > bestMob) {
					bestMob = m;
					bestCon = pd;
				}
			}
		}
		if (bestMob <= 0.f)
			continue;
		MeasureReach(d, bestCon, at, unit);
		// gMexOpen is the LAND asker's own probe and cannot see water ground,
		// so a water line asks its own reach whether any is open.
		const bool anyOpen = (dClass == PC_WATER)
				? (gPlantOpenReach[d] > 0) : gMexOpen;
		// Land-locked ground pays its stream AND a denial premium: taking it
		// first is also the enemy not taking it. Water only -- a shipyard's
		// ships hold the ground they claim, where air cons hold nothing.
		const float first = (dClass == PC_WATER)
				? waterFirstK * WaterUncontested()
				: 0.f;
		const float expTerm = anyOpen
				? stream * (gPlantReach[d] + gPlantLocked[d] * first) : 0.f;
		// NOTE: dupSubst is applied to the BUILD-POWER half below, not just to
		// production -- see the duplicate block. Expansion is not substitutable
		// (a nano claims no ground), so only pipeTerm is.
		const float rateMul = PipeRateMul(d, uid);
		const float conHalf = (pipeTerm + expTerm) * rateMul;
		// Only the PRODUCTION half is a tier question against THEM: what this
		// line would field is worth less while they field a tier above it. Its
		// constructor half buys mohos and build power, which their tier does
		// not devalue -- so a T2 lab is still bought for its cons.
		const bool lineOn = ai.GetTunable("apex_line_quality", TUNE_LINE_QUALITY) > 0.f;
		const float prodOwn = prodHalf * FoeTierPlantMul(d)
				* (lineOn ? 1.f : LineTerrainMul(d)) * TeamLineMul(d) * RecordLineMul(d);
		const float gain = conHalf + prodOwn;
		if (gain <= 0.05f)
			continue;
		// A DUPLICATE line is only parallel capacity: value divides per
		// copy owned (watched: T1 air labs multiplying). And a plant whose
		// cons reach the extraction ceiling outranks a T1 copy -- "we want
		// multiple T2 air labs, not T1 air labs."
		// ...and a "copy" is any plant of the SAME REACH from the same
		// DOMAIN (land/air/water), not the same def -- a T2 bot lab and a T2
		// vehicle lab are parallel capacity of one tier (watched: both
		// bought when one was barely affordable), while a shipyard beside a
		// bot lab is not a copy of anything.
		const float myReach = PlantReachOf(d);
		// A LINE ORDERED IS A LINE, whoever remembers it -- one ledger read
		// (flipped 2026-08-27, shadow-measured first), one membership rule:
		// FINISHED, or hands on it. A builder walking to the site is
		// assigned, so the walk window (no frame yet, engine count 0) still
		// counts -- that was the second-copy hole. An UNMANNED order or
		// frame does not: its manning path is this def's own want (the fold
		// dedups the site), and counting it prices the resume as a duplicate
		// -- which strands the opening factories it was meant to protect.
		int reachKin = 0;
		for (uint ci = 0; ci < ComLen(); ++ci) {
			const int rd = gComDef[ci];
			if (Catalog::gBuildsList[rd].length() == 0)
				continue;
			if ((rd != d)
				&& ((PlantReachOf(rd) < myReach) || (PlantClass(rd) != dClass)))
				continue;
			if ((gComState[ci] != CS_FINISHED)
				&& ((gComTask[ci] is null)
					|| (Requests::Workers(gComTask[ci]) == 0)))
				continue;
			++reachKin;
		}
		// A LINE UNDER CONSTRUCTION IS A COMMITMENT WHATEVER ITS DOMAIN.
		// reachKin is a parallel-CAPACITY question and so is rightly per
		// domain, which left the rotation apexearth watched wide open: a bot
		// lab, then a vehicle plant, then an AIR plant, each one a different
		// class and so each priced as though nothing were in flight. Splitting
		// the same income across three unfinished frames finishes none of
		// them. Counted separately from reachKin because this is about the
		// FEED, not about capacity -- and it is a divisor, not a veto, so a
		// genuinely wanted air line still wins once it is worth twice a
		// half-built ground one.
		int liveOther = 0;
		for (uint fo = 0; inflOn && (fo < Requests::gLive.length()); ++fo) {
			IUnitTask@ ot = Requests::gLive[fo];
			if ((ot is null) || ot.IsDead() || (ot.buildDef is null))
				continue;
			const int od = int(ot.buildDef.id);
			if ((od == d) || Catalog::gMobile[od]
				|| (Catalog::gBuildsList[od].length() == 0))
				continue;
			if (PlantClass(od) != dClass)
				++liveOther;
		}
		// A COPY OF A TIER WE HAVE OUTGROWN buys the outgrown tier's
		// pipeline, not the one we would get for the same metal. apexearth:
		// "T1 air labs are mostly only useful for creating T1 air
		// constructors... we shouldn't want more than 1 of them. If our
		// economy is big enough to support multiple T1 air labs, we're better
		// off making T2 aircraft instead" -- and the same for T1 labs
		// generally. So the second line in a domain prices its CONSTRUCTOR
		// half at the share of the domain's best tier its own cons deliver,
		// which is what makes the money go to the advanced plant. Its
		// PRODUCTION half is untouched: a cheap line is still a line, and
		// what it puts on the field is the market's question, not the tier's.
		// Exempt while it unlocks a product nothing we own can make.
		// The tier discount applies to the CON half of EVERY plant, unlock or
		// not: a hover platform's cons are still T1 cons beside a standing T2
		// lab, whatever its products unlock. The unlock exemption stays where
		// it belongs -- on dupKin and the replant memory, the terms about
		// being a COPY. (One watched 1v1 bought 16 plants of ten different
		// defs in 24 minutes; every def change dodged every discount.)
		//
		// Against what we OWN or have in flight, never the catalog:
		// gAvailable is not tier-gated, so the catalog's T2 reach is "best"
		// from frame zero and comparing against it priced the OPENING lab at
		// a third -- first factory at minute nine, a floating hover plant
		// (seed 31). Nothing is outgrown before its better exists.
		float subMul = 1.f;
		{
			const float bestOwn = OwnedDomainReach(dClass);
			if ((myReach > 0.f) && (bestOwn > myReach))
				subMul = myReach / bestOwn;
		}
		// ...and the throughput half of a COPY is ALWAYS priced against the
		// nano substitute, never gated on a momentary NeediestLine read: a
		// line short of hands makes the copy LESS useful, not more. A plant
		// that UNLOCKS products no nano can deliver keeps the old rule --
		// substituted only while an existing line is short of hands -- and
		// DupBpSubstMul returns 1 when no nano def exists to substitute.
		const bool unlockCap = UnlocksProduct(d);
		// asked only where it can decide anything; logged below either way
		const float unlockW = (unlockCap && (reachKin > 0)) ? UnlockWorth(d) : 1.f;
		const bool isCopy = (reachKin > 0)
				&& !(unlockCap && (unlockW >= 1.f));
		// HIS RULING (2026-08-27): a copy of a lab we already run is
		// INELIGIBLE, not discounted -- "the want ... should come out as 0
		// ... we forward our want over to the nano." A zero never enters the
		// ranking, so neither the roulette's residual ticket nor the
		// executor's same-frame fall-through can buy it. The kin must be
		// FINISHED or have hands on it: an unmanned order is manned BY this
		// def's own want, so zeroing on it strangles the build it defers to.
		// The other escape is a substitute that cannot exist
		// (DupBpSubstMul == 1).
		bool dupUsable = false;
		for (uint ci = 0; isCopy && (ci < ComLen()); ++ci) {
			if (gComDef[ci] != d)
				continue;
			if ((gComState[ci] == CS_FINISHED)
				|| ((gComTask[ci] !is null)
					&& (Requests::Workers(gComTask[ci]) > 0)))
			{
				dupUsable = true;
				break;
			}
		}
		if (isCopy && dupUsable && (DupBpSubstMul(d) < 1.f)
			&& (ai.GetTunable("apex_plant_copy", TUNE_PLANT_COPY) <= 0.f)) {
			if (ai.frame >= gNextPlantDupLog) {
				gNextPlantDupLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: plantdup " + Catalog::Def(d).GetName()
					+ " kin=" + reachKin + " copy=1 dupGain=0 forwarded-to-nano");
			}
			continue;
		}
		// (No finished-factory guard: a copy of a lab still in its nanoframe
		// is the earliest and cheapest moment to refuse the duplicate.)
		float dupSubst = 1.f;
		if (substOn) {
			AIFloat3 nlp;
			if (isCopy || (NeediestLine(nlp) > 0.f))
				dupSubst = DupBpSubstMul(d);
		}
		// A DIFFERENT LAB IS NOT A COPY. The divisor counted every same-reach
		// plant of the domain, so a T2 vehicle lab was halved by a standing T2
		// bot lab that fields entirely different units -- by the same amount
		// as a second bot lab, which fields nothing new. Nothing preferred the
		// variety. His ruling: a second lab of a type we run is the bad buy,
		// one that opens new units "would be OK". So only a plant that fields
		// nothing new pays the parallel-capacity divisor; the BP-substitution
		// price below keeps the real duplicate honest.
		const int dupKin = isCopy ? reachKin : 0;
		// BUILD POWER IS THE HALF THE NANO ACTUALLY REPLACES, and it was the
		// half left undiscounted: dupSubst only touched production while
		// pipeTerm (BPGap) went in at full price, so a duplicate lab was the
		// market's answer to a build-power shortfall. A COPY's expansion half
		// is substituted too -- the cons claim the ground, not the plant, and
		// nanos on the standing kin deliver the same cons cheaper. A new
		// capability keeps its expansion at full value.
		const float conSub = (pipeTerm * subMul * dupSubst
				+ expTerm * subMul * (isCopy ? dupSubst : 1.f)) * rateMul;
		float dupGain = (conSub + prodOwn * dupSubst)
				/ float(1 + dupKin);
		if (liveOther > 0)
			dupGain /= float(1 + liveOther);
		// the value below is built from dupGain, not gain: the line factor
		// has to land here or it decides nothing (8 games said so)
		dupGain *= LineMul(d);
		// The duplicate decision, in one line, so the audit can assert it
		// rather than infer it from two labs standing.
		if ((reachKin > 0) && (ai.frame >= gNextPlantDupLog)) {
			gNextPlantDupLog = ai.frame + 30 * SECOND;
			AIFloat3 nlp2;
			AiLog(Factory::T() + "apex: plantdup " + Catalog::Def(d).GetName()
				+ " kin=" + reachKin
				+ " dupKin=" + dupKin
				+ " unlocks=" + (unlockCap ? 1 : 0)
				+ " unlockW=" + formatFloat(unlockW, "", 0, 2)
				+ " liveOther=" + liveOther
				+ " subst=" + formatFloat(dupSubst, "", 0, 3)
				+ " lineNeed=" + formatFloat(NeediestLine(nlp2), "", 0, 2)
				+ " prod=" + formatFloat(prodOwn, "", 0, 2)
				+ " con=" + formatFloat(conHalf, "", 0, 2)
				+ " dupGain=" + formatFloat(dupGain, "", 0, 2));
		}
		{
			const float ceilX = BestExtract();
			if (ceilX > 0.f)
				dupGain *= 1.f + myReach / ceilX;
		}
		// The quiet rear's expansion is AIR (apexearth: "the goal should be
		// air cons... stop making ground labs"): flying cons don't jam the
		// packed farm, and its army era is gantry-only. GROUND plants stop
		// pricing once one stands; air and water keep their full value --
		// neither one's cons compete for the packed farm's ground.
		if (EcoQuiet() && (Factory::gFactoryCount >= 1) && (dClass == PC_LAND))
			continue;
		// Plants stand at the base anchor -- the middle of what we own;
		// a floating one stands at the water it was priced against. Priced
		// against the walk THERE, not from where the asker happens to stand.
		if (!OnMap(site) && !homeAnchorSet) {
			homeAnchorSet = true;
			homeAnchor = InteriorSite(EcoSiteFor(unit),
					Catalog::Def(int(unit.circuitDef.id)));
			upAnchorOk = UpgradeAnchor(Catalog::Def(int(unit.circuitDef.id)), upAnchor);
		}
		// ...beside the lathe that will raise it, when any stands.
		const AIFloat3 lands = OnMap(site) ? site
				: LatheSite(Catalog::Def(d), Catalog::Def(int(unit.circuitDef.id)),
					(upAnchorOk && MakesUpgradeHands(d)) ? upAnchor : homeAnchor);
		Want c;
		const float plantG = dupGain * bestMob * PipeLatencyMult(d, Catalog::gBuildPower[uid]);
		const float liftG = PlantLiftGain(d);
		if ((liftG > 0.f) && (ai.frame >= gNextPlantLiftLog)) {
			gNextPlantLiftLog = ai.frame + 30 * SECOND;
			AiLog("apex: plant-lift t=" + ai.teamId + " " + Catalog::Def(d).GetName()
					+ " plant=" + formatFloat(plantG, "", 0, 3)
					+ " lift=" + formatFloat(liftG, "", 0, 3));
		}
		ValueOf(d, plantG + liftG,
				WalkSecTo(unit, lands), Catalog::gBuildPower[uid], c);
		if (candLog) {
			cand += " " + Catalog::Def(d).GetName()
				+ "=" + formatFloat(c.value, "", 0, 2)
				+ "(con" + formatFloat(conHalf, "", 0, 2)
				+ ",prod" + formatFloat(prodOwn, "", 0, 2)
				+ ",reach" + formatFloat(gPlantReach[d], "", 0, 2)
				+ ",terr" + formatFloat(LineTerrainMul(d), "", 0, 2)
				+ ",line" + formatFloat(LineMul(d), "", 0, 2)
				+ ",rec" + formatFloat(RecordLineMul(d), "", 0, 2)
				+ ",rate" + formatFloat(rateMul, "", 0, 2)
				+ ",mob" + formatFloat(bestMob, "", 0, 2)
				+ ",lat" + formatFloat(PipeLatencyMult(d, Catalog::gBuildPower[uid]), "", 0, 2)
				+ ")";
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PLANT;
			@w.def = Catalog::Def(d);
			w.pos = lands;
		}
	}
	if (candLog && (cand.length() > 0)) {
		gNextPlantCandLog = ai.frame + 20 * SECOND;
		AiLog("apex: plantcand t=" + ai.teamId + " " + unit.circuitDef.GetName()
			+ " stream=" + formatFloat(stream, "", 0, 2)
			+ " pipe=" + formatFloat(pipeTerm, "", 0, 2)
			+ " prodHalf=" + formatFloat(prodHalf, "", 0, 2) + cand);
	}
	return w;
}


}  // namespace Market
