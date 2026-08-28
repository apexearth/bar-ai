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
// the class won every ticket: measured over 54 games, Persecutor took the
// heavy-gun want 8 times and Bulwark never once. With cover now read as killing
// power rather than as a price tag, the turret auction in want_protect.as can
// reach a T3 gun on its own merits, and it does so without a class target or a
// one-frame-at-a-time gate standing in the way.)

int SuperClassOf(int d)
{
	if (!Catalog::gAvailable[d])
		return -1;
	if (Catalog::gAntiNuke[d] && !Catalog::gMobile[d])
		return SC_ANTINUKE;
	if (IsSuperWeapon(d))
		return Catalog::gStock[d] ? SC_SILO : SC_LRPC;
	if (IsGantryDef(d))
		return SC_GANTRY;
	return -1;
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
	const float inc = (gIncEma > 0.f) ? gIncEma : aiEconomyMgr.metal.income;
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
	const float inc = (gIncEma > 0.f) ? gIncEma : aiEconomyMgr.metal.income;
	float per = ai.GetTunable("apex_super_per_income", TUNE_SUPER_PER_INCOME);
	if (per < 1.f)
		per = 150.f;
	// The anti-nuke is the one whose first copy is not optional: an uncovered
	// nuke is the whole base. Silos share its spacing (apexearth 2026-08-27,
	// watching: "I like our use of nukes - we could use more"); the other
	// offensive classes double it.
	if ((sc == SC_ANTINUKE) || (sc == SC_SILO))
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
	// are all rows of the commitment ledger (flipped 2026-08-27, shadow
	// clean across the proving games).
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

// ONE STRATEGIC FRAME AT A TIME. Not a cap on how many we own -- a cap on how
// many stand half-finished at once, which is the rule the base already follows
// for everything expensive: put the build power on the one frame.
bool SuperInFlight()
{
	SuperCensus();
	return gSuperFlight > 0;
}

// Where a strategic static goes. Silos, gantries and anti-nukes go as deep in
// the base as the tech lab does -- they are the most protection-hungry things
// we own. A long-range gun and a heavy turret face the fight instead: the
// choke behind our own front if there is one, otherwise the base front.
AIFloat3 SuperSite(CCircuitUnit@ unit, int sc)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	if ((sc == SC_LRPC) || (sc == SC_HEAVY)) {
		if (Base::gAnchorSet) {
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
	return InteriorSite(here, Catalog::Def(int(unit.circuitDef.id)));
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
	// The richest thing standing outside every umbrella we own.
	float best = 0.f;
	bool found = false;
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if ((gOwnBig[i] is null) || (gOwnBig[i].circuitDef is null))
			continue;
		const AIFloat3 p = gOwnBig[i].GetPos(ai.frame);
		if (!OnMap(p) || ProtCovered(PROT_ANTINUKE, p, r))
			continue;
		const float m = Catalog::gCostM[int(gOwnBig[i].circuitDef.id)];
		if (m > best) {
			best = m;
			at = p;
			found = true;
		}
	}
	return found;
}

int gNextSuperLog = 0;

Want@ ProposeSuper(CCircuitUnit@ unit)
{
	Want w;
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
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		const int sc = SuperClassOf(d);
		if (sc < 0)
			continue;
		if (Catalog::gFloater[d] || Catalog::gSub[d])
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
			&& (DupBpSubstMul(d) < 1.f))
			continue;
		const float bill = SuperBill(d);
		if (bill >= budget)
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
						? gIncEma : aiEconomyMgr.metal.income;
				if (incNow < Policy::AntinukeIncome())
					continue;
			}
			if (!AntiNukeSite(unit, at))
				continue;
		} else {
			at = SuperSite(unit, sc);
		}
		if (!OnMap(at))
			continue;
		// AFFORDABILITY IS THE GAIN. What is left of the budget once the bill
		// is paid, as a share of it, times the slice of economic power this
		// market may speak for -- so the same structure is worth nothing at the
		// income that can barely pay for it and nearly the full slice at the
		// income that shrugs it off.
		const float afford = (budget - bill) / budget;
		float gain = power * share * afford
				* Persona::WantMult(SuperName(sc));
		// THE GANTRY IS A PRODUCTION LINE, NOT A GUN. Affordability alone
		// rewards being CHEAP -- (budget-bill)/budget is near zero for the
		// most expensive structure in the game -- so it lost every election
		// to the light classes on this list. Its return is a line's return:
		// the metal we are wasting plus the army gap only its products fill,
		// still ramped by how comfortably we can pay for it.
		if (sc == SC_GANTRY) {
			const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
			const float gapF = ArmyTargetFull() - ArmyValue();
			const float gapStream = (gapF > 0.f)
					? gapF / ((fillS > 1.f) ? fillS : 60.f) : 0.f;
			gain = (OverflowM() + gapStream) * afford
					* Persona::WantMult(SuperName(sc));
		}
		if (gain <= 0.f)
			continue;
		const float walkSec = (speed > 1.f) ? (here.distance2D(at) / speed) : 60.f;
		Want c;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_SUPER;
			@w.def = Catalog::Def(d);
			w.pos = at;
			w.spotId = sc;
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
		if ((ap !is null) && unit.circuitDef.CanBuild(ap)
			&& !Requests::LiveOfDef(ap))
		{
			const float bill = SuperBill(int(ap.id));
			if (bill < budget) {
				const AIFloat3 at3 = SuperSite(unit, SC_AIRPLANT);
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
	if ((w.def !is null) && (ai.frame >= gNextSuperLog)) {
		gNextSuperLog = ai.frame + 30 * SECOND;
		AiLog("apex: super t=" + ai.teamId + " " + SuperName(w.spotId)
			+ ":" + w.def.GetName()
			+ " bill=" + int(SuperBill(int(w.def.id)))
			+ " budget=" + int(budget)
			+ " have=" + SuperHave(w.spotId) + "/" + SuperTarget(w.spotId)
			+ " at=" + int(w.pos.x) + "," + int(w.pos.z)
			+ " v=" + formatFloat(w.value * 1000.f, "", 0, 2));
	}
	return w;
}


}  // namespace Market
