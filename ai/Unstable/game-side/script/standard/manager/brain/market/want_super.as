namespace Market {

//------------------------------------------------------------------------------
// THE STRATEGIC WANT: gantries, nuke silos, anti-nukes, long-range guns and the
// best turret a faction owns.
//
// These are not priced the way the rest of the market is priced, on purpose.
// apexearth: "I prefer not to take a purely mathematical approach to this
// topic. It is more of a 'if I can afford this, I'll insert it as a want so we
// make one'." A silo returns destruction, not metal/s, so a market denominated
// in metal/s rates it below a wind turbine forever -- which is why none has
// ever been built here.
//
// So the one question asked is AFFORDABILITY: the bill, metal plus energy at
// the conversion floor, against what the economy makes in apex_super_afford_s
// seconds. That single quantity produces the ladder without a table anywhere --
// at ~160 metal/s a gantry and a silo clear it, at ~90 the long-range gun does,
// at ~36 the anti-nuke does, and below that none do.
//------------------------------------------------------------------------------

const int SC_ANTINUKE = 0;
const int SC_SILO = 1;
const int SC_LRPC = 2;
const int SC_HEAVY = 3;
const int SC_GANTRY = 4;
const int SC_AIRPLANT = 5;

string SuperName(int sc)
{
	if (sc == SC_ANTINUKE) return "antinuke";
	if (sc == SC_SILO)     return "silo";
	if (sc == SC_LRPC)     return "lrpc";
	if (sc == SC_HEAVY)    return "heavygun";
	if (sc == SC_GANTRY)   return "gantry";
	if (sc == SC_AIRPLANT) return "airplant";
	return "?";
}

// A static weapon the turret market must not touch: it out-ranges any tower by
// the same multiple that already caps a tower's usable reach. Read off the def,
// so all three factions -- and anything BAR adds later -- classify themselves.
//
// RANGE, NOT THE STOCKPILE FLAG. Stockpiling was the first test and it named
// armmercury a nuke silo (measured): the long-range AA batteries stockpile too,
// at 2,400 elmos against a silo's 72,000. The air guard below says the same
// thing a second way, because the reach cap is a tunable and 2,400 is not far
// under it.
bool IsSuperWeapon(int d)
{
	if (Catalog::gMobile[d] || Catalog::gBuilder[d] || Catalog::gAntiNuke[d])
		return false;
	if (Catalog::gBuildsList[d].length() > 0)
		return false;
	if (Catalog::gExtractsM[d] > 0.f)
		return false;
	if (Catalog::gMaxRange[d] <= 1.f)
		return false;
	if (Catalog::gAirT[d] > 2.f * Catalog::gSurfT[d])
		return false;   // an air battery is air defence, however far it reaches
	return Catalog::gMaxRange[d] > Brain::LightTowerRange()
			* ai.GetTunable("apex_def_reach_cap", TUNE_DEF_REACH_CAP);
}

// The T3 plant. Marked by name in Main::AiMain, which is where the factory
// brain already learns which plants are T3 -- a derived test ("products dwarf
// what our lines make") named the T1 bot lab a gantry in a 4v4, because with no
// plant standing the ceiling it compares against is the sentinel 1.
//
// Nothing else asks for one: a gantry builds no constructor and no converter,
// so want_tech.as Channel 3 drops it at its unlock gate before pricing. That is
// the mechanism behind "I haven't seen a Gantry".
bool IsGantryDef(int d)
{
	if (Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
		return false;
	if (Catalog::gBuildsList[d].length() == 0)
		return false;
	return (Factory::userData[Id(d)].attr & Factory::Attr::T3) != 0;
}

// The cheapest ground turret in the game, which is the yardstick the heavy-gun
// test measures against: "the best defence" is relative to a light tower rather
// than to a number, and the same on every faction. Catalog-wide and constant,
// so it is found once.
float gLightTowerM = -1.f;
float LightTowerCostM()
{
	if (gLightTowerM > 0.f)
		return gLightTowerM;
	gLightTowerM = 0.f;
	// The faction's own light tower, by the same lookup Brain::LightTowerRange
	// uses for its reach. The catalog minimum below is only the fallback: it
	// would anchor on whatever cheap armed oddity a faction ships.
	{
		CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
		if (light !is null) {
			gLightTowerM = light.costM;
			return gLightTowerM;
		}
	}
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		if (Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		if (ProtClassOf(d) != PROT_DEF)
			continue;
		if ((gLightTowerM <= 0.f) || (Catalog::gCostM[d] < gLightTowerM))
			gLightTowerM = Catalog::gCostM[d];
	}
	return gLightTowerM;
}

// (THE HEAVY-GUN CLASS IS GONE. It priced a ground turret on AFFORDABILITY --
// (budget-bill)/budget -- which falls as cost rises, so the cheapest member of
// the class won every ticket and the dearest never once. With cover now read as killing
// power rather than as a price tag, the turret auction in protect_want.as can
// reach a T3 gun on its own merits, and it does so without a class target or a
// one-frame-at-a-time gate standing in the way.)

// Memoised on the def, because everything under the availability test is
// STATIC catalog data plus Brain::LightTowerRange, which looks its tower up by
// name on every call -- and this is asked of every build option of every
// builder, every election, plus once per ledger row in SuperCensus. Only a
// def already AVAILABLE is cached: availability is frame-dependent and a "no"
// taken before the tree unlocks must never latch (the BestExtract rule).
array<int> gScoAns;
int SuperClassOf(int d)
{
	if (!Catalog::gAvailable[d])
		return -1;
	const bool memo = (d >= 0) && (d <= Catalog::gDefCount);
	if (memo && (int(gScoAns.length()) <= Catalog::gDefCount)) {
		gScoAns.resize(Catalog::gDefCount + 1);
		for (uint k = 0; k < gScoAns.length(); ++k)
			gScoAns[k] = -2;
	}
	if (memo && (gScoAns[d] != -2))
		return gScoAns[d];
	int r = -1;
	if (Catalog::gAntiNuke[d] && !Catalog::gMobile[d])
		r = SC_ANTINUKE;
	else if (IsSuperWeapon(d))
		r = Catalog::gStock[d] ? SC_SILO : SC_LRPC;
	else if (IsGantryDef(d))
		r = SC_GANTRY;
	if (memo)
		gScoAns[d] = r;
	return r;
}

// The whole bill in metal: its own metal plus its energy at the conversion
// floor. A silo is 7,700 metal and 82,000 energy, and ignoring the second
// number is how a "cheap" strategic build freezes an economy.
float SuperBill(int d)
{
	return Catalog::gCostM[d] + Catalog::gCostE[d] * EPriceFloor();
}

// What the economy makes in apex_super_afford_s seconds. Smoothed: a spike in
// income is not an economy that can carry a gantry.
float SuperBudget()
{
	TrackIncome();
	const float inc = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
	const float sec = ai.GetTunable("apex_super_afford_s", TUNE_SUPER_AFFORD_S);
	return inc * ((sec > 1.f) ? sec : 60.f);
}

// HOW MANY OF THIS CLASS THE ECONOMY WANTS STANDING. Never a cap: a count that
// rises with income, so "at least 1 usually, more if we want to be safer" (his
// words, about anti-nukes) is the same sentence for every class here -- the
// gantry included (apexearth: "if you are super wealthy, always overflowing
// metal, make more Gantries and spend that money").
int SuperTarget(int sc)
{
	TrackIncome();
	const float inc = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
	float per = ai.GetTunable("apex_super_per_income", TUNE_SUPER_PER_INCOME);
	if (per < 1.f)
		per = 150.f;
	// The anti-nuke is the one whose first copy is not optional: an uncovered
	// nuke is the whole base. Silos share its spacing (apexearth 2026-08-27,
	// watching: "I like our use of nukes - we could use more"); the other
	// offensive classes double it.
	// The gantry left the doubled spacing 2026-08-28 (apexearth: "We should
	// be more willing to make more gantries too if we're at something like
	// 500m/s - i often see us lose games because we aren't aggressive
	// enough in building in late game") -- at 500 own income the tight
	// spacing wants 4, the doubled one 2.
	// Blind to their silos, extra copies follow what we have built: one more
	// while a cluster worth more than an umbrella stands outside every one
	// (apexearth 2026-09-25: the base had grown out from under its only one).
	if ((sc == SC_ANTINUKE) && (Brain::EnemyNukeSilos() <= 0)) {
		AIFloat3 unused;
		const int have = SuperHave(sc);
		if (UncoveredClusterM(unused) > AntiNukeCostM())
			return have + 1;
		return (have > 1) ? have : 1;
	}
	if ((sc == SC_ANTINUKE) || (sc == SC_SILO) || (sc == SC_GANTRY))
		return 1 + int(inc / per);
	return 1 + int(inc / (per * 2.f));
}

// What we hold of each class, standing plus in flight, counted once a frame --
// the classifier walks the whole def table, and this is asked once per
// candidate per election.
array<int> gSuperHave(5, 0);
int gSuperFlight = 0;
int gSuperCensusAt = -1;

void SuperCensus()
{
	if (gSuperCensusAt == ai.frame)
		return;
	gSuperCensusAt = ai.frame;
	gSuperFlight = 0;
	for (uint c = 0; c < gSuperHave.length(); ++c)
		gSuperHave[c] = 0;
	// One source: standing, half-built, orphaned frame and outstanding order
	// are all rows of the commitment ledger.
	for (uint ci = 0; ci < ComLen(); ++ci) {
		const int sc = SuperClassOf(gComDef[ci]);
		if (sc < 0)
			continue;
		++gSuperHave[sc];
		if (gComState[ci] != CS_FINISHED)
			++gSuperFlight;
	}
}

int SuperHave(int sc)
{
	SuperCensus();
	return ((sc >= 0) && (sc < int(gSuperHave.length()))) ? gSuperHave[sc] : 0;
}

// STRATEGIC FRAMES AT ONCE: one, plus one per apex_super_flight_per m/s of
// structural overflow. The single-frame law is the focus rule for an economy
// that must choose; overflow is the economy saying it has nothing to focus
// FROM ("gotta go somewhere - gotta do something").
int SuperFlightCap()
{
	const float per = ai.GetTunable("apex_super_flight_per", TUNE_SUPER_FLIGHT_PER);
	return 1 + int(OverflowM() / ((per > 1.f) ? per : 140.f));
}

bool SuperInFlight()
{
	SuperCensus();
	return gSuperFlight >= SuperFlightCap();
}

// Whether decide.as's super-push will jump the queue for this def. An
// anti-nuke against no silo seen is insurance, priced in the draw, except:
// the first once a silo is possible (an interceptor stocks 90 s after the
// build, so one started at the sighting is late), and any while metal
// overflows -- the refusal exists for a starved economy, and a rich one
// should build more things at once (his rulings 2026-09-26/27).
bool SuperPushable(const CCircuitDef@ d)
{
	if ((d is null) || !Catalog::gAntiNuke[int(d.id)])
		return true;
	if (Brain::EnemyNukeSilos() > 0)
		return true;
	if ((SuperHave(SC_ANTINUKE) <= 0) && Factory::gHaveT2
		&& (Military::FoeTierAbove(1) > 0.f))
		return true;
	return WealthWaiver();
}

// Where a strategic static goes. Silos, gantries and anti-nukes go as deep in
// the base as the tech lab does -- they are the most protection-hungry things
// we own. A long-range gun and a heavy turret face the fight instead: the
// choke behind our own front if there is one, otherwise the base front.
// THE GUN GOES UP ON THE HILL (apexearth 2026-09-16: long-range cannons on
// high ground fire long distances unobstructed; the flat is allowed, hills
// are preferred). The highest legal ground within a short walk of the
// chosen site takes it -- height, then nearness on a tie.
AIFloat3 HighGroundNear(CCircuitDef@ def, const AIFloat3& in site, float r)
{
	if ((def is null) || !OnMap(site))
		return site;
	const float h0 = ai.GetElevationAt(site);
	float bestH = h0;
	float bestD = 0.f;
	AIFloat3 best = site;
	const float step = 96.f;
	for (float dz = -r; dz <= r; dz += step) {
		for (float dx = -r; dx <= r; dx += step) {
			if (dx * dx + dz * dz > r * r)
				continue;
			const AIFloat3 p = site + AIFloat3(dx, 0.f, dz);
			if (!OnMap(p))
				continue;
			const float h = ai.GetElevationAt(p);
			const float d = dx * dx + dz * dz;
			if ((h < bestH) || ((h == bestH) && (d >= bestD)))
				continue;
			const AIFloat3 s = ai.FindBuildSiteNear(def, p, 64.f);
			if (!OnMap(s) || (s.distance2D(p) > 64.f) || NearBlockedFor(s, int(def.id)))
				continue;
			bestH = h;
			bestD = d;
			best = s;
		}
	}
	return best;
}

AIFloat3 SuperSite(CCircuitUnit@ unit, int sc, CCircuitDef@ def = null)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (sc == SC_LRPC) {
		const AIFloat3 flat = SuperSite(unit, SC_HEAVY);
		return HighGroundNear(def, flat, 600.f);
	}
	if ((sc == SC_LRPC) || (sc == SC_HEAVY)) {
		if (Base::gAnchorSet) {
			// ONE GUN PER DOORWAY (apexearth 2026-09-13, his screenshot:
			// three Pulsars in the same blob while the raided flank had
			// nothing). The gate with the fewest supers already standing
			// in reach takes the next one; the old single front choke is
			// the fallback when no gate is known.
			array<AIFloat3> gates;
			if (Front::GateChokes(gates) > 0) {
				int bestN = 1 << 30;
				AIFloat3 bestAt;
				bool got = false;
				for (uint gi = 0; gi < gates.length(); ++gi) {
					AIFloat3 site;
					if (!Front::BehindChoke(gates[gi], 180.f, site))
						site = gates[gi];
					if (!OnMap(site))
						continue;
					const int n = ProtCoverCount(PROT_SUPER, site, 1200.f);
					if (n < bestN) {
						bestN = n;
						bestAt = site;
						got = true;
					}
				}
				if (got)
					return bestAt;
			}
			AIFloat3 cp;
			if (Front::FrontChoke(Base::gAnchor, cp)) {
				AIFloat3 site;
				if (!Front::BehindChoke(cp, 180.f, site))
					site = cp;
				if (OnMap(site))
					return site;
			}
			if (Base::gAxisSet) {
				const AIFloat3 p = Base::gAnchor + Base::gFwd * 300.f;
				if (OnMap(p))
					return p;
			}
		}
	}
	const AIFloat3 interior = InteriorSite(here, Catalog::Def(int(unit.circuitDef.id)));
	// A plant rises where the lathe already stands.
	if ((def !is null) && ((sc == SC_GANTRY) || (sc == SC_AIRPLANT)))
		return LatheSite(def, Catalog::Def(int(unit.circuitDef.id)), interior);
	return interior;
}

float gAntiNukeCostM = 0.f;
float AntiNukeCostM()
{
	if (gAntiNukeCostM > 0.f)
		return gAntiNukeCostM;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::ValidId(d) || !Catalog::gAvailable[d] || !Catalog::gAntiNuke[d]
				|| Catalog::gMobile[d])
			continue;
		if ((gAntiNukeCostM <= 0.f) || (Catalog::gCostM[d] < gAntiNukeCostM))
			gAntiNukeCostM = Catalog::gCostM[d];
	}
	return gAntiNukeCostM;
}

// The most big-structure metal one umbrella could cover that none covers now,
// centred on one of those structures. An umbrella worth less than its own
// cost is not built.
int gUncovAt = -1;
float gUncovM = 0.f;
AIFloat3 gUncovPos;
float UncoveredClusterM(AIFloat3& out at)
{
	if (gUncovAt == ai.frame) {
		at = gUncovPos;
		return gUncovM;
	}
	gUncovAt = ai.frame;
	gUncovM = UncoveredClusterScan(gUncovPos);
	at = gUncovPos;
	return gUncovM;
}

float UncoveredClusterScan(AIFloat3& out at)
{
	const float r = ai.GetTunable("apex_antinuke_r", TUNE_ANTINUKE_R);
	array<AIFloat3> pos;
	array<float> m;
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if ((gOwnBig[i] is null) || (gOwnBig[i].circuitDef is null))
			continue;
		const AIFloat3 p = gOwnBig[i].GetPos(ai.frame);
		if (!OnMap(p) || ProtCovered(PROT_ANTINUKE, p, r))
			continue;
		pos.insertLast(p);
		m.insertLast(Catalog::gCostM[int(gOwnBig[i].circuitDef.id)]);
	}
	float best = 0.f;
	for (uint i = 0; i < pos.length(); ++i) {
		float sum = 0.f;
		for (uint j = 0; j < pos.length(); ++j)
			if (pos[i].distance2D(pos[j]) < r)
				sum += m[j];
		if (sum > best) {
			best = sum;
			at = pos[i];
		}
	}
	return best;
}

// A second anti-nuke belongs over ground the first one does not reach.
bool AntiNukeSite(CCircuitUnit@ unit, AIFloat3& out at)
{
	const float r = ai.GetTunable("apex_antinuke_r", TUNE_ANTINUKE_R);
	const AIFloat3 core = gFarmSet ? gFarmPos
			: (Base::gAnchorSet ? Base::gAnchor : Builder::gHomePos);
	if (OnMap(core) && !ProtCovered(PROT_ANTINUKE, core, r)) {
		at = SuperSite(unit, SC_ANTINUKE);
		return OnMap(at);
	}
	if (UncoveredClusterM(at) > AntiNukeCostM())
		return true;
	// DEPTH AT THE CORE (apexearth 2026-09-13: "in late game we may want our
	// anti nuke coverage to go from just 1 AN to ~3 AN"): a second and third
	// umbrella over the core once the economy is large -- a volley beats one
	// stockpile, and the base under it is the whole game.
	if (OnMap(core)) {
		TrackIncome();
		const float inc = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
		int depth = 1 + int(inc / 400.f);
		if (depth > 3)
			depth = 3;
		if (ProtCoverCount(PROT_ANTINUKE, core, r) < depth) {
			at = SuperSite(unit, SC_ANTINUKE);
			return OnMap(at);
		}
	}
	return false;
}

// ONE ADVANCED PLANT AT A TIME, PER PLAYER (apexearth 2026-08-28, watching
// Purple raise a T2 vehicle plant and a T2 air lab at once: "a huge 'no
// no'"). The tech lane and the air mandate each checked only their own
// def, so neither saw the other's commitment. An advanced plant in flight
// is the tier unlock already coming; a second simultaneous one doubles the
// drain and delivers nothing sooner -- sequential is strictly faster even
// rich. Standing copies stay governed by wealth (his adv-air ruling); this
// serializes STARTS only.
int gAdvInFlightRow = -1;   // the ledger row the last true answer stood on
bool AdvPlantInFlight()
{
	gAdvInFlightRow = -1;
	for (uint ci = 0; ci < ComLen(); ++ci) {
		if (gComState[ci] == CS_FINISHED)
			continue;
		const int d = gComDef[ci];
		if (!Catalog::ValidId(d) || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0))
			continue;
		if ((Factory::userData[d].attr
			& (Factory::Attr::T2 | Factory::Attr::T3)) == 0)
			continue;
		// An order nobody is walking to is not in flight (the same clause
		// as AnyPlantInFlight): an abandoned T2 vehicle plant order
		// deferred every T2 lab ask for the five minutes it took to time
		// out (his Isthmus game, T2 at 15.7 min against their 6.5).
		if ((gComState[ci] == CS_ORDERED) && (gComTask[ci] !is null)
			&& (Requests::Workers(gComTask[ci]) == 0))
			continue;
		gAdvInFlightRow = int(ci);
		return true;
	}
	return false;
}

// ANY tier. T1 starts had no serialization at all, and his watched loss
// bought plant:armlab and plant:armhp EIGHT FRAMES apart at 16.7 min while
// losing -- the same "huge no no" one tier down. Same law, same waiver.
bool AnyPlantInFlight()
{
	for (uint ci = 0; ci < ComLen(); ++ci) {
		if (gComState[ci] == CS_FINISHED)
			continue;
		const int d = gComDef[ci];
		if (!Catalog::ValidId(d) || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0))
			continue;
		// An order nobody is walking to is not in flight; it is the orphan
		// the next plant ask adopts (Requests::Take's fork test).
		if ((gComState[ci] == CS_ORDERED) && (gComTask[ci] !is null)
			&& (Requests::Workers(gComTask[ci]) == 0))
			continue;
		// Nor is a crewless frame: counted, it deferred the only ask that
		// re-adopts it, and the frame rotted.
		if (ComIsOrphan(ci))
			continue;
		return true;
	}
	return false;
}

int gNextAdvDeferLog = 0;
void AdvDeferLog(const string& in what)
{
	if (ai.frame < gNextAdvDeferLog)
		return;
	gNextAdvDeferLog = ai.frame + 30 * SECOND;
	string row = "";
	if ((gAdvInFlightRow >= 0) && (gAdvInFlightRow < int(ComLen()))) {
		const uint r = uint(gAdvInFlightRow);
		row = " " + Catalog::Def(gComDef[r]).GetName() + " state=" + gComState[r]
			+ " at=" + int(gComPos[r].x) + "," + int(gComPos[r].z)
			+ " task=" + ((gComTask[r] is null) ? "none" : "live")
			+ " workers=" + ((gComTask[r] is null) ? 0 : Requests::Workers(gComTask[r]));
	}
	AiLog("apex: adv-plant defer t=" + ai.teamId + " " + what
		+ " -- an advanced plant is already in flight:" + row);
}

int gNextSuperLog = 0;
int gNextLrpcLog = 0;
float gLrpcInReach = 0.f;

Want@ ProposeSuper(CCircuitUnit@ unit)
{
	Want w;
	Want wIns;
	if (ai.GetTunable("apex_super_want", TUNE_SUPER_WANT) <= 0.f)
		return w;
	if (SuperInFlight())
		return w;
	const float budget = SuperBudget();
	if (budget <= 0.f)
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	const float share = ai.GetTunable("apex_super_share", TUNE_SUPER_SHARE);
	const float power = EcoPowerM();
	// NO GANTRY BEFORE THE MILITARY IT FEEDS (apexearth 2026-09-13: "We need
	// to make sure we do not make a gantry until we intend to make military
	// -- nothing non military comes out of there"). The rear specialist's
	// army target is zero while it grows, so its gantry's is too.
	const bool noLines = EcoRoleGrowing();
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		const int sc = SuperClassOf(d);
		if (sc < 0)
			continue;
		// ...and no big gun or heavy turret either: they are the military
		// ("makes no military, focusing on economy"). The anti-nuke stays,
		// priced on the enemy's silos as before -- and the SILO comes in with
		// the seat's ramp (his "some nuclear missile launchers" from half the
		// target), scaled below.
		if (noLines && (sc != SC_ANTINUKE) && !((sc == SC_SILO) && (EcoRoleRamp() > 0.f)))
			continue;
		if (Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		// AFFORDABILITY IS TWO ARRAY READS; the tests under it walk the live
		// register and the whole commitment ledger. Same test as the one
		// below, taken first for every class whose budget IS the plain one --
		// the gantry's team purse is computed further down and keeps its
		// place.
		if ((sc != SC_GANTRY) && (SuperBill(d) >= budget))
			continue;
		if (Requests::LiveOfDef(Catalog::Def(d)))
			continue;
		if (SuperHave(sc) >= SuperTarget(sc))
			continue;
		// HIS RULING, the same law as the plant and tech lanes: a super that
		// is a PRODUCTION LINE (gantry, advanced air plant) and already
		// stands manned gets nanos, not a twin -- this lane kept electing a
		// second armshltx into the door 155 times in one 44-minute game.
		// GUNS (nukes, annihilators, big berthas) are untouched: owning more
		// of those is legitimate scaling, and SuperTarget already governs it.
		if ((Catalog::gBuildsList[d].length() > 0)
			&& ((ComCountOf(d, CS_FINISHED)
				+ ComCountManned(d, CS_FRAMED | CS_ORDERED)) >= 1)
			&& (DupBpSubstMul(d) < 1.f)
			&& !CopyWaived(d))
			continue;
		const float bill = SuperBill(d);
		// ONE LINE, THE TEAM'S PURSE (apexearth 2026-08-28: "I saw a team
		// with 400m/s income and no gantry -- we can have a gantry at like
		// 100 m/s"). The copy law keeps the gantry one per side and ally
		// nanos man it, so its affordability reads the TEAM's income over
		// its own horizon -- the per-player budget needed ~155 m/s EACH,
		// which a 4v4 sharing 400 never reaches (measured same day: first
		// corgant election 27.8-28.6 min, gain 6-9.5, none ever finished).
		float teamInc = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
		float classBudget = budget;
		float hostMul = 1.f;
		if (sc == SC_GANTRY) {
			if (AdvPlantInFlight() && !WealthWaiver()) {
				AdvDeferLog("gantry");
				continue;
			}
			// Below the host anchor the gain scales by (own/anchor)^2, as the
			// tunable says: a hard skip left most of an 8v8 at 60-130 m/s
			// with no gantry at 38 minutes (apexearth 2026-09-27).
			{
				const float own = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
				const float anchor = ai.GetTunable("apex_gantry_host_inc", TUNE_GANTRY_HOST_INC);
				if ((anchor > 0.f) && (own < anchor))
					hostMul = (own * own) / (anchor * anchor);
			}
			// OUR OWN PURSE, not the team's: since every player keeps a gantry
			// (09-27) each pays for its own, and the team sum licensed one at
			// 50 m/s in an 8v8 (his 2026-09-28: "some of them started a gantry
			// at like 50 metal income. It's just not enough").
			teamInc = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
			const float gsec = ai.GetTunable("apex_gantry_afford_s",
					TUNE_GANTRY_AFFORD_S);
			classBudget = teamInc * ((gsec > 1.f) ? gsec : 100.f);
		}
		if (bill >= classBudget)
			continue;   // cannot afford it; nothing else about it matters
		AIFloat3 at;
		if (sc == SC_ANTINUKE) {
			// INSURANCE HAS AN INCOME FLOOR, and the queue-jump below is what
			// made it the first strategic build of every game: the anti-nuke is
			// the cheapest class here, so it clears the affordability test long
			// before a gantry or a silo and took every super-push. A SEEN enemy
			// silo overrides the bar -- being poor does not make the warhead
			// cheaper.
			if (Brain::EnemyNukeSilos() <= 0) {
				TrackIncome();
				const float incNow = (gIncEma > 0.f)
						? gIncEma : Eco::MInc();
				if (incNow < Policy::AntinukeIncome())
					continue;
			}
			if (!AntiNukeSite(unit, at))
				continue;
		} else {
			at = SuperSite(unit, sc, Catalog::Def(d));
		}
		at = ProbedSite(Catalog::Def(d), Catalog::Def(int(unit.circuitDef.id)), at);
		if (!OnMap(at))
			continue;
		// AFFORDABILITY IS THE GAIN. What is left of the budget once the bill
		// is paid, as a share of it, times the slice of economic power this
		// market may speak for -- so the same structure is worth nothing at the
		// income that can barely pay for it and nearly the full slice at the
		// income that shrugs it off.
		const float afford = (classBudget - bill) / classBudget;
		float gain = power * share * afford
				* Persona::WantMult(SuperName(sc));
		if (noLines)
			gain *= EcoRoleRamp();   // the seat's war comes in with its ramp
		// THE GANTRY IS A PRODUCTION LINE, NOT A GUN. Affordability alone
		// rewards being CHEAP -- (budget-bill)/budget is near zero for the
		// most expensive structure in the game -- so it lost every election
		// to the light classes on this list. Its return is a line's return:
		// the metal we are wasting plus the army gap only its products fill,
		// still ramped by how comfortably we can pay for it.
		if (sc == SC_GANTRY) {
			const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
			// TEAM GAP for the one team-scoped want: the ally-share division
			// that fixed the 4v4 economy reads each player its slice of the
			// census, but ONE shared line answers the census whole -- full
			// enemy army at match ratio against the team's whole standing.
			float gapF = Military::EnemyArmyCost()
					* ai.GetTunable("apex_match_ratio", TUNE_MATCH_RATIO)
					- Military::TeamArmyCost();
			if (gapF < 0.f)
				gapF = 0.f;
			const float gapStream = gapF / ((fillS > 1.f) ? fillS : 60.f);
			gain = (OverflowM() + gapStream) * afford
					* Persona::WantMult(SuperName(sc));
			// CAPABILITY INSURANCE (apexearth: "If the enemy comes at us
			// with a Behemoth and we do not have one we are in big
			// trouble"): the answer to enemy T3 has to exist BEFORE one is
			// seen -- a gantry plus its first heavy is minutes of build
			// time nothing can compress once the Behemoth is already on the
			// lawn. Worth a share of the team income that could field T3,
			// even with no gap and no waste on the books.
			// Insurance keyed to the HOST's own structural income, not the
			// team's: 0.5x a team of eight read 150+ gain at minute five and
			// out-bid everything the moment the host gate opened ("making it
			// at 80m/s - it is too early now"). The team purse still decides
			// affordability above; the host's economy sizes the urgency.
			const float insure = ((gIncEma > 0.f)
						? gIncEma : Eco::MInc())
					* ai.GetTunable("apex_gantry_insure", TUNE_GANTRY_INSURE)
					* afford * Persona::WantMult(SuperName(sc));
			if (insure > gain)
				gain = insure;
			gain *= hostMul;
		}
		// DEFENCE BEFORE THE BIG GUN (apexearth 2026-08-28: "We consistently
		// make Basilisk before T3 or even T2 defense - we need better
		// defense esp when we're losing"). An offensive super is a luxury a
		// covered base earns: its gain scales with the fill of the standing
		// defence target, which sinks exactly when we are losing (towers
		// dying faster than they are replaced). A discount, never a gate --
		// at zero standing defence the gun keeps the floor share -- and the
		// antinuke (insurance) and gantry (production) are untouched.
		if ((sc == SC_SILO) || (sc == SC_LRPC)) {
			const float dt = DefenceTarget();
			float fill = 1.f;
			if (dt > 1.f) {
				fill = DefenceValue() / dt;
				if (fill > 1.f)
					fill = 1.f;
			}
			const float dfloor = ai.GetTunable("apex_offense_def_floor",
					TUNE_OFFENSE_DEF_FLOOR);
			gain *= dfloor + (1.f - dfloor) * fill;
		}
		// A GUN IS WORTH WHAT IT CAN REACH (apexearth: "I would rather it be
		// a nuke silo"). Affordability alone made the cheaper class the first
		// strategic build; a warhead reaches their base wherever it is, a gun
		// only what stands inside its range. Same discount shape as the
		// defence fill above, never a gate.
		// REMEMBERED STRUCTURE METAL, not ai.GetEnemyCostAt: that one is a
		// count of enemies visible right now, which at a gun site behind our
		// own line is zero all game (inReach=0.00 in every reading).
		if (sc == SC_LRPC) {
			const float reach = Catalog::gMaxRange[d];
			const float ref = ai.GetTunable("apex_nuke_base_value", TUNE_NUKE_BASE_VALUE);
			float inReach = (reach > 1.f) && (ref > 1.f)
					? (aiEnemyMgr.GetEnemyStructCostAt(at, reach) / ref) : 0.f;
			if (inReach > 1.f)
				inReach = 1.f;
			const float dfloor = ai.GetTunable("apex_offense_def_floor",
					TUNE_OFFENSE_DEF_FLOOR);
			gain *= dfloor + (1.f - dfloor) * inReach;
			gLrpcInReach = inReach;
		}
		if (gain <= 0.f)
			continue;
		const float walkSec = (speed > 1.f) ? (here.distance2D(at) / speed) : 60.f;
		Want c;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if ((sc == SC_LRPC) && (ai.frame >= gNextLrpcLog)) {
			gNextLrpcLog = ai.frame + 30 * SECOND;
			AiLog("apex: lrpc t=" + ai.teamId + " " + Catalog::Def(d).GetName()
				+ " bill=" + int(bill) + " budget=" + int(budget)
				+ " have=" + SuperHave(sc) + "/" + SuperTarget(sc)
				+ " defFill=" + formatFloat((DefenceTarget() > 1.f)
					? (DefenceValue() / DefenceTarget()) : 1.f, "", 0, 2)
				+ " inReach=" + formatFloat(gLrpcInReach, "", 0, 2)
				+ " at=" + int(at.x) + "," + int(at.z)
				+ " gain=" + formatFloat(gain, "", 0, 2)
				+ " m=" + int(c.mCost) + " t=" + int(c.tCost)
				+ " v=" + formatFloat(c.value * 1000.f, "", 0, 2)
				+ " best=" + ((w.def is null) ? "none" : (SuperName(w.spotId) + ":" + w.def.GetName()))
				+ " bestV=" + formatFloat(w.value * 1000.f, "", 0, 2));
		}
		// A candidate the push refuses may not hide one it would take: a
		// second anti-nuke outranked the gantry for nine minutes, the push
		// skipped it, the draw never picked it, and nothing was built.
		Want@ slot = wIns;
		if (SuperPushable(Catalog::Def(d)))
			@slot = w;
		if (c.value > slot.value) {
			slot = c;
			slot.kind = WK_SUPER;
			@slot.def = Catalog::Def(d);
			slot.pos = at;
			slot.spotId = sc;
		}
	}
	// THE AIR MANDATE HAS NO OTHER BUYER. Air::IntelPlantToBuild carries
	// apexearth's whole ruling -- one basic plant past the mandatory income,
	// advanced plants scaling one per apex_adv_air_income, army-fed gate --
	// and the Brain overhaul left it with ZERO consumers: a watched 8v8 had a
	// player at 2,168 metal/s with two T1 air labs and no advanced plant.
	// Priced here as what it is, a strategic line the economy can carry, on
	// the same affordability shape as the rest of this market.
	{
		CCircuitDef@ ap = Air::IntelPlantToBuild();
		// An ADVANCED air plant waits its turn behind any advanced plant
		// already in flight -- see AdvPlantInFlight above (Purple's
		// simultaneous T2 vehicle + T2 air, "a huge 'no no'").
		if ((ap !is null)
			&& ((Factory::userData[int(ap.id)].attr
				& (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
			&& AdvPlantInFlight() && !WealthWaiver())
		{
			AdvDeferLog("air:" + ap.GetName());
			@ap = null;
		}
		if ((ap !is null) && unit.circuitDef.CanBuild(ap)
			&& !Requests::LiveOfDef(ap) && !PlantCopyRefusable(int(ap.id)))
		{
			const float bill = SuperBill(int(ap.id));
			if (bill < budget) {
				const AIFloat3 at3 = ProbedSite(ap,
						Catalog::Def(int(unit.circuitDef.id)),
						SuperSite(unit, SC_AIRPLANT, ap));
				if (OnMap(at3)) {
					const float afford = (budget - bill) / budget;
					const float gain = power * share * afford
							* Persona::WantMult(SuperName(SC_AIRPLANT));
					if (gain > 0.f) {
						const float wSec3 = (speed > 1.f)
								? (here.distance2D(at3) / speed) : 60.f;
						Want c3;
						ValueOf(int(ap.id), gain, wSec3,
								Catalog::gBuildPower[uid], c3);
						if (c3.value > w.value) {
							w = c3;
							w.kind = WK_SUPER;
							@w.def = ap;
							w.pos = at3;
							w.spotId = SC_AIRPLANT;
						}
					}
				}
			}
		}
	}
	if ((w.def is null) && (wIns.def !is null))
		w = wIns;
	if ((w.def !is null) && (ai.frame >= gNextSuperLog)) {
		gNextSuperLog = ai.frame + 30 * SECOND;
		AiLog("apex: super t=" + ai.teamId + " " + SuperName(w.spotId)
			+ ":" + w.def.GetName()
			+ " bill=" + int(SuperBill(int(w.def.id)))
			+ " budget=" + int((w.spotId == SC_GANTRY)
				? (Military::TeamSum(Military::TV_MINC_NET,
						Eco::MInc())
					* ai.GetTunable("apex_gantry_afford_s", TUNE_GANTRY_AFFORD_S))
				: budget)
			+ " have=" + SuperHave(w.spotId) + "/" + SuperTarget(w.spotId)
			+ " at=" + int(w.pos.x) + "," + int(w.pos.z)
			+ " v=" + formatFloat(w.value * 1000.f, "", 0, 2));
	}
	return w;
}


}  // namespace Market
