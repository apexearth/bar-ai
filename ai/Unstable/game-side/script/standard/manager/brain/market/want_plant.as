namespace Market {
// A RETIREMENT IS A DECISION, NOT A VACANCY. Reclaiming a structure and
// re-buying the same def minutes later is the market arguing with itself
// (14 of 15 T2 bot labs in one 1v1 died to our own reclaim; the next game
// did it to Ambushers and converters); a def we chose to retire keeps a
// discount for a window so the retirement can mean something. Noted at
// reclaim EXECUTION, and only for the OBSOLETE proposer's wants -- eating a
// wall that pens a unit says nothing about wanting the def again.
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
		&& (aiEconomyMgr.energy.income
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

// A plant's future output discounts by its own LATENCY (temporal
// consistency, same law as EPriceAt): the pipeline delivers its first con
// at lab-build + con-build seconds, and value that far out is worth
// horizon/(horizon+latency) of value now. This is what makes the natural
// opening (mex, mex, solar, THEN lab) emerge without a scripted order --
// at frame zero the lab's 70s latency halves it below the immediate mex.
// Seconds from deciding on a plant to its first constructor existing: the
// plant itself, then the cheapest builder it makes. Both the latency discount
// and the survival discount are built from this one number.
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
int gNextWetCheck = 0;

AIFloat3 WetPlantSite(CCircuitDef@ plant, const AIFloat3& in anchor)
{
	if (ai.frame < gNextWetCheck)
		return gWetPlantSite;
	gNextWetCheck = ai.frame + 10 * SECOND;
	const float near = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	const AIFloat3 wet = ai.FindBuildSiteNear(plant, anchor, near);
	gWetPlantSite = (OnMap(wet) && (wet.distance2D(anchor) <= near))
			? wet : AIFloat3(-1.f, 0.f, -1.f);
	return gWetPlantSite;
}

// A plant's DOMAIN: land, air or water. Two plants are parallel capacity only
// within one domain -- a shipyard is the only door into the water, so land
// lines neither price it out nor divide its value.
const int PC_LAND = 0;
const int PC_AIR = 1;
const int PC_WATER = 2;

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

// A plant's expansion stream is only the spots ITS OWN constructors can walk
// to. A shipyard's cons reach the water spots and nothing else, so on a map
// whose metal is ashore its expansion term collapses and the land line wins;
// where the metal is in the water it is the land line that is worth little.
// LAND-LOCKED is the sharper of the two: ground this plant's cons reach and
// the ASKER cannot. Where water splits a map that is the half of the economy
// no land line will ever touch, whatever the water share of the map says.
// Sector-area lookups, cached on a slow tick.
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
	const float foe = Military::EnemyCostOf(Unit::Role::SUB.type);
	if (foe <= 0.f)
		return 1.f;
	const float ours = ArmyValue();
	return 1.f / (1.f + foe / ((ours > 1.f) ? ours : 1.f));
}

int OwnedWaterPlants()
{
	int n = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[int(d)]
			|| (Catalog::gBuildsList[int(d)].length() == 0))
			continue;
		if (PlantClass(int(d)) == PC_WATER)
			n += gOwnCount[d];
	}
	return n;
}

// A plant's TIER, in the only currency that separates a T1 lab from its
// advanced version: the best extractor its own constructors can reach.
// A plant's own tier, from its attribute rather than from its extraction reach
// -- the enemy comparison is about what the LINE fields, not what its
// constructors dig.
// A SECOND LINE IS THE DEAR WAY TO BUY THROUGHPUT.
//
// apexearth 2026-08-27: "2900 metal buys 300bp and the ability to build T2
// units. 1 nano turret adds 200bp to that factory for just ~200 metal. So the
// right choice is to add more nanos to the lab instead of making another lab.
// You'd only want a second lab if you ran out of room to make nanos."
//
// Read off the defs rather than his numbers: an advanced lab is 300 workertime
// for 2900 metal, a construction turret 200 for 210 -- 0.103 against 0.952 BP
// per metal, so the turret is NINE TIMES the build power for the same spend.
// A duplicate line's production half is exactly that purchase, and it was
// priced as if the cheaper way to buy it did not exist. Returned as the ratio
// between the two, so nothing is forbidden and no number is chosen: the second
// lab wins whenever the substitute genuinely is not available.
int gNextPlantDupLog = 0;

float DupBpSubstMul(int d)
{
	const float pm = Catalog::gCostM[d];
	if (pm <= 1.f)
		return 1.f;
	const float pbp = Catalog::gBuildPower[d] / pm;
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
	if ((nbp <= 0.f) || (pbp >= nbp))
		return 1.f;
	return pbp / nbp;
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

// MODEL: a plant's return is its constructor pipeline -- each con carries
// roughly one open spot's stream while expansion ground remains, plus the
// overflow the pipeline would capture (arithmetic, see OverflowM). One named
// discount (apex_plant_pipe) prices the pipeline's losses; no spot ground
// left means no plant value at all.
Want@ ProposePlant(CCircuitUnit@ unit)
{
	Want w;
	// The MARGINAL plant: worth anything only if income supports another
	// line (~50 m/s each, apexearth's number). Not a cap -- a price of zero
	// past what the economy can feed, of any lab type.
	TrackIncome();
	const float per = ai.GetTunable("apex_plant_income_per", TUNE_PLANT_INCOME_PER);
	// Metal nothing is spending counts as spare line capacity on top of the
	// income estimate: it is the direct proof the lines we hold cannot eat
	// what we make (apexearth: "if you are super wealthy, always overflowing
	// metal, make more Gantries... or adv air labs too").
	const float structInc = ((gIncEma > 0.f) ? gIncEma : aiEconomyMgr.metal.income)
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
	if (overLine && !(MapHasWater() && (OwnedWaterPlants() == 0)))
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
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gSub[d])
			continue;   // submerged plants have no placement model
		if (Catalog::gBuildsList[d].length() == 0)
			continue;   // not a factory
		const int dClass = PlantClass(d);
		if (waterOnly && (dClass != PC_WATER))
			continue;
		const AIFloat3 here = unit.GetPos(ai.frame);
		// A floating plant stands in water, not at the base anchor, and is
		// worth nothing on a map without real water to stand in.
		AIFloat3 site(-1.f, 0.f, -1.f);
		if (Catalog::gFloater[d]) {
			if (!MapHasWater())
				continue;
			site = WetPlantSite(Catalog::Def(d),
					Builder::gHomeSet ? Builder::gHomePos : here);
			if (!OnMap(site))
				continue;
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
				? ai.GetTunable("apex_water_first", TUNE_WATER_FIRST)
					* WaterUncontested()
				: 0.f;
		const float expTerm = anyOpen
				? stream * (gPlantReach[d] + gPlantLocked[d] * first) : 0.f;
		// NOTE: dupSubst is applied to the BUILD-POWER half below, not just to
		// production -- see the duplicate block. Expansion is not substitutable
		// (a nano claims no ground), so only pipeTerm is.
		const float conHalf = pipeTerm + expTerm;
		// Only the PRODUCTION half is a tier question against THEM: what this
		// line would field is worth less while they field a tier above it. Its
		// constructor half buys mohos and build power, which their tier does
		// not devalue -- so a T2 lab is still bought for its cons.
		const float prodOwn = prodHalf * FoeTierPlantMul(d);
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
		// dedups the site), and counting it priced the resume as a
		// duplicate -- measured seed 8, both opening factories unreachable
		// for 11 minutes.
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
		const bool inflOn =
				(ai.GetTunable("apex_plant_inflight", TUNE_PLANT_INFLIGHT) > 0.f);
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
		// cheaper way to buy the same build power (his arithmetic: 300 BP for
		// 2,900 vs 200 BP for 210). Whether that throughput is NEEDED is the
		// demand terms' question (pipeTerm, prodOwn); this price used to be
		// gated on a momentary NeediestLine read, so every flicker to zero
		// let a copy price at full gain -- backwards, since no line short of
		// hands means the copy has even less to do. A plant that UNLOCKS
		// products no nano can deliver keeps the old rule -- substituted only
		// while an existing line is short of hands (feed the starving line
		// before founding a new domain) -- because nanos on a T1 lab cannot
		// make what a first T2 lab would. DupBpSubstMul already returns 1
		// when no nano def exists to substitute, the one case a second line
		// is the only way to buy throughput.
		const bool isCopy = (reachKin > 0) && !UnlocksProduct(d);
		// HIS RULING (2026-08-27): a copy of a lab we already run is
		// INELIGIBLE, not discounted -- "the want ... should come out as 0
		// ... we forward our want over to the nano." A zero never enters the
		// ranking, so neither the roulette's residual ticket nor the
		// executor's same-frame fall-through can buy it. The kin must be
		// FINISHED or have hands on it: an unmanned order or frame is manned
		// BY this def's own want (the fold/adoption path), so zeroing on it
		// strangles the very build it defers to -- measured seed 8, both
		// opening factories ordered and then unreachable for 11 minutes.
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
		if (isCopy && dupUsable && (DupBpSubstMul(d) < 1.f)) {
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
		if (ai.GetTunable("apex_dup_bp_subst", TUNE_DUP_BP_SUBST) > 0.f) {
			AIFloat3 nlp;
			if (isCopy || (NeediestLine(nlp) > 0.f))
				dupSubst = DupBpSubstMul(d);
		}
		// A DIFFERENT LAB IS NOT A COPY. The divisor counted every same-reach
		// plant of the domain, so a T2 vehicle lab was halved by a standing T2
		// bot lab despite fielding entirely different units -- and a SECOND T2
		// bot lab, which fields nothing new, was halved by exactly the same
		// amount. Nothing preferred the variety; which one got built was a coin
		// flip. apexearth 2026-08-27: a second lab of a type we already run is
		// the bad buy ("1 lab = 300 build power, 1 nano = 200... you can back 1
		// lab with 14 nanos... a second T2 lab gives you 600 total" -- a fifth
		// of the production for the same metal), while a lab that opens new
		// units "would be OK". So only a plant that fields nothing new pays the
		// parallel-capacity divisor; the BP-substitution price below is what
		// keeps the real duplicate honest.
		const int dupKin = isCopy ? reachKin : 0;
		// BUILD POWER IS THE HALF THE NANO ACTUALLY REPLACES, and it was the
		// half left undiscounted: dupSubst only touched production, while
		// pipeTerm (BPGap) went in at full price. So a duplicate lab was the
		// market's answer to a build-power shortfall -- and with nano demand
		// clamped at 35 m/s there was no other answer available, which is how
		// five T2 bot labs stand with four nanos between them (apexearth
		// 2026-08-27, and his arithmetic: "1 lab = 300 build power, 1 nano =
		// 200... you can back 1 lab with 14 nanos for a total of 3100 build
		// power. To spend about the same metal on a second T2 lab would give
		// you 600" -- a fifth of the throughput). A COPY's expansion half is
		// substituted too: the cons claim the ground, not the plant, and
		// nanos on the standing kin deliver the same cons cheaper. A new
		// capability keeps its expansion at full value.
		const float conSub = pipeTerm * subMul * dupSubst
				+ expTerm * subMul * (isCopy ? dupSubst : 1.f);
		float dupGain = (conSub + prodOwn * dupSubst)
				/ float(1 + dupKin);
		if (liveOther > 0)
			dupGain /= float(1 + liveOther);
		// The duplicate decision, in one line, so the audit can assert it
		// rather than infer it from two labs standing.
		if ((reachKin > 0) && (ai.frame >= gNextPlantDupLog)) {
			gNextPlantDupLog = ai.frame + 30 * SECOND;
			AIFloat3 nlp2;
			AiLog(Factory::T() + "apex: plantdup " + Catalog::Def(d).GetName()
				+ " kin=" + reachKin
				+ " dupKin=" + dupKin
				+ " unlocks=" + (UnlocksProduct(d) ? 1 : 0)
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
		const AIFloat3 lands = OnMap(site) ? site
				: InteriorSite(EcoSiteFor(unit), Catalog::Def(int(unit.circuitDef.id)));
		Want c;
		ValueOf(d, dupGain * bestMob * PipeLatencyMult(d, Catalog::gBuildPower[uid]),
				WalkSecTo(unit, lands), Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PLANT;
			@w.def = Catalog::Def(d);
			w.pos = lands;
		}
	}
	return w;
}


}  // namespace Market
