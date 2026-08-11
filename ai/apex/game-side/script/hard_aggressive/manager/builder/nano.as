namespace Builder {

// Construction turrets for the eco lead, laid out as rows behind the base rather
// than piled where a constructor happens to stand.
//
// apexearth: "ideally it creates a long rectangle of nanos and builds the eco
// all around those", and separately "boost its build power or start building
// more in parallel if it's used all the nanos in one area already". A turret
// only assists what is inside its radius, so stacking them on one yard
// saturates: the tenth turret queues behind the same work as the first.
//
// apexearth: "the organization of the eco and the nanoturrets is very important
// to an efficient strategy."
string armnanotc("armnanotc"); string cornanotc("cornanotc"); string legnanotc("legnanotc");

// Nanos take the band nearest the anchor so their assist radius reaches both the
// factory and the first economy rows; reactors take the deepest band, where one
// going up does not take the rest of the base with it.
bool BandSpot(CCircuitUnit@ unit, CCircuitDef@ def, bool nano, AIFloat3& out spot)
{
	return Base::Spot(unit, def, nano ? Base::NANO : Base::HEAVY, spot);
}

// Only while metal is genuinely piling up. The eco lead's measured failure is
// income it has no capacity to spend -- over 7 sixty-minute games it PRODUCED
// 23% more metal than its teammates and BUILT 36% less, holding 12 constructors
// to their 28, and it was the only player never to reach T3. Buying the capacity
// to spend is what converts that bank into economy.
//
// Gating on the bank rather than on income is what keeps this off the list of
// rules that quietly ate the economy: when metal is tight this cannot fire at
// all, so it never displaces a mex upgrade.
const float NANO_MIN_BANK = 0.5f;   // share of metal storage standing unspent
const float NANO_RICH_BANK = 0.2f;  // ...once income alone justifies the turret
// MEASURED AGAINST INTUITION, AND INTUITION LOST HERE.
//
// apexearth: "I make nano turrets even at less than 20m/sec." Tried at 15, on
// its own, 6 games vs medium at +100: turrets FELL 15.0 -> 13.5 per player,
// army 1,811,160 -> 1,506,964, waste 1.6% -> 5.8%. Building them early appears
// to take metal from the expansion that would have paid for more of them later.
//
// That is a statement about THIS benchmark, not about his games -- a human
// places them where they are needed and keeps them busy, and the 20-minute
// +100 format rewards compounding economy over early build power. Left tunable
// so the question can be reopened cheaply.
const float NANO_INCOME_GATE_DEF = 60.f;

float NanoIncomeGate()
{
	return ai.GetTunable("apex_nano_income_gate", NANO_INCOME_GATE_DEF);
}
// Raised with the shift away from ground engineers: a turret is 210 metal and
// never walks anywhere, which is why it is the build power this player should
// hold most of. Two rows of twenty is the rectangle it fills out.
// The engine's own per-player unit limit, from the `maxunits` modoption
// (modoptions.lua: default 2000, min 500, max 32000).
//
// This is the only real ceiling there is, and it is the one worth respecting --
// apexearth: "you can detect the in-game hard unit cap (usually 2000 units per
// player) and do a proportion cap but still it should be a high cap, need lots
// of builders to make the big units... 20 titans goes a long way in a game
// and... thats just 20 units :)". Slots spent on build power buy the few slots
// that matter.
int gUnitCap = 0;

int UnitCap()
{
	if (gUnitCap > 0)
		return gUnitCap;
	gUnitCap = 2000;
	const string v = string(aiSetupMgr.GetModOptions()["maxunits"]);
	if (v != "") {
		const int n = parseInt(v);
		if (n > 0)
			gUnitCap = n;
	}
	AiLog("apex: unit cap " + gUnitCap);
	return gUnitCap;
}

int CapShare(float share)
{
	const int n = int(float(UnitCap()) * share);
	return (n < 1) ? 1 : n;
}

// Turrets wanted, from income, ceilinged by a share of the unit cap rather than
// by a number someone picked. A turret is 210 metal and 140 build power that
// never walks anywhere, so on a large economy it is the best thing a full bank
// can become.
const float NANO_PER_INCOME = 5.f;
const int   NANO_FULL_BONUS = 20;
const float NANO_CAP_SHARE  = 0.12f;

int NanoCap()
{
	int cap = 2 + int(aiEconomyMgr.metal.income / NANO_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		cap += NANO_FULL_BONUS;
	const int ceiling = CapShare(NANO_CAP_SHARE);
	return (cap > ceiling) ? ceiling : cap;
}
// HOW MANY MAY BE UNDER CONSTRUCTION AT ONCE. This, not NanoCap(), is what was
// actually limiting us. apexearth: "there are a lot of times when I'm playing and
// I need to build a lot more nanoturrets to keep up with the amount of energy and
// resources that I have. When players play, they can have hundreds of these."
//
// Measured across 6 games at +100: 533 turrets over 48 player-games -- 11 each --
// while NanoCap() allowed 42 at 100 metal/s and 102 at 400. The cap was never
// reached because only FOUR could ever be in flight, at one order per period.
// Four in flight is a trickle on an economy that can pay for twenty at once.
const int   NANO_INFLIGHT_BASE = 4;
const float NANO_INFLIGHT_PER_INCOME = 25.f;   // one more in flight per this much
const int   NANO_INFLIGHT_FULL = 12;           // extra while the bank is at the cap

int NanoInFlight()
{
	int n = NANO_INFLIGHT_BASE + int(aiEconomyMgr.metal.income / NANO_INFLIGHT_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		n += NANO_INFLIGHT_FULL;
	return n;
}
const int   NANO_STALE    = 12;   // beyond this the counter has drifted, resync
const int   NANO_PERIOD   = 15 * SECOND;
// While the bank is at the cap, order them as fast as the placement allows and
// let far more of them be in flight at once. apexearth: "in a game like that we'd
// need like a ton of nano turrets, 100s of butlers, all working to make the
// expensive stuff." A period is the wrong bound for that -- the thing that should
// stop us is running out of bank or of ground, both of which are checked anyway.
const int   NANO_FULL_PERIOD   = 1 * SECOND;
const int   NANO_FULL_INFLIGHT = 24;
int gNextNano = 0;
int gNanosAsked = 0;

CCircuitDef@ NanoDef()
{
	return SideDef3(armnanotc, cornanotc, legnanotc);
}

// Turrets we hold. aiBuilderMgr.GetWorkerCount() counts these as workers, so any
// cap meant for MOBILE constructors has to subtract them.
int NanoCount()
{
	CCircuitDef@ d = NanoDef();
	return (d is null) ? 0 : d.count;
}

// Where our construction turrets actually stand, as a centroid.
//
// apexearth: "we should try to place gantries near existing nano turrets so they
// build faster". A gantry is 8,400 metal and a Titan far more, so the difference
// between building one inside an assist field and outside it is minutes.
bool NanoCluster(AIFloat3& out spot)
{
	CCircuitDef@ d = NanoDef();
	if ((d is null) || (d.count <= 0) || !gHomeSet)
		return false;
	array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(d, gHomePos, 0.f);
	if ((have is null) || (have.length() == 0))
		return false;
	float x = 0.f, z = 0.f, n = 0.f;
	for (uint i = 0; i < have.length(); ++i) {
		if (have[i] is null)
			continue;
		const AIFloat3 at = have[i].GetPos(ai.frame);
		x += at.x; z += at.z; n += 1.f;
	}
	if (n < 1.f)
		return false;
	AIFloat3 p;
	p.x = x / n;
	p.z = z / n;
	if (!OnMap(p))
		return false;
	spot = p;
	return true;
}

// Metal is at the cap and we are not converting it into anything.
//
// apexearth: "we're totally metal full and just aren't able to spend it... If we
// are metal full we need to just keep making more gantries and more butler
// assist guys and more nano turrets."
bool MetalFull()
{
	return aiEconomyMgr.isMetalFull;
}

// A gantry, placed in the assist field of our turret rows, paid for out of a
// bank we are otherwise wasting. Advanced constructors only -- asking a T1
// constructor for a gantry is the silent no-op this repo has been bitten by.
const float GANTRY_NEAR_NANO = 700.f;
int gSurplusGantries = 0;

// How far from home to look once the tidy spots are exhausted. A gantry across
// the base beats no gantry.
const float GANTRY_SEARCH_WIDE = 2600.f;
int gNextGantryFailLog = 0;

IUnitTask@ SurplusGantry(CCircuitUnit@ unit)
{
	if (!MetalFull() || !Factory::WantMoreGantries())
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	CCircuitDef@ gant = Factory::T3Gantry();
	if ((gant is null) || !gant.IsAvailable(ai.frame))
		return null;

	// A gantry is a 16x16 footprint -- the largest thing we ever place -- and on
	// a hilly map there may be no flat square that big anywhere near the nanos.
	// This used to be ONE FindBuildSiteNear call at a fixed radius: when it
	// failed it returned null and said nothing, every call, for the whole game.
	// apexearth, on Carrot Mountains: "it has lots of hills... i think gantry
	// locations are hard to find. can you help make sure we find spots for them?"
	//
	// Widen instead of giving up. Assisting nanos are a preference, not a
	// requirement -- a gantry built across the base still builds; a gantry that
	// never gets placed does not.
	AIFloat3 near;
	const bool haveNano = NanoCluster(near);
	if (!haveNano)
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(gant, near, GANTRY_NEAR_NANO);
	if (!OnMap(site) && haveNano)                    // anywhere in the base
		site = ai.FindBuildSiteNear(gant, gHomePos, GANTRY_NEAR_NANO);
	if (!OnMap(site))                                // anywhere we can reach
		site = ai.FindBuildSiteNear(gant, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site)) {
		if (ai.frame >= gNextGantryFailLog) {
			gNextGantryFailLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: gantry NO SITE for " + gant.GetName()
				+ " nano=" + (haveNano ? "1" : "0")
				+ " tried=" + formatFloat(GANTRY_NEAR_NANO, "", 0, 0)
				+ "/" + formatFloat(GANTRY_SEARCH_WIDE, "", 0, 0));
		}
		return null;
	}
	if (ThreatFor(unit, site) > CON_THREAT_VETO)
		return null;

	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH,
			gant, site, null, 0.f));
	if (post is null)
		return null;
	++gSurplusGantries;
	AiLog(Factory::T() + "apex: surplus gantry " + gant.GetName()
		+ " by the nanos, bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0)
		+ " placed=" + gSurplusGantries);
	return post;
}

// A TURRET ON THE FRONT IS A REPAIR STATION. apexearth: "on frontlines they're
// also useful for repairing."
//
// Distinct from EcoNano below in purpose and in placement: that one buys build
// power beside the factories, this one keeps the defence line and the army
// standing by repairing them where they fight. Same 210-metal unit, and it is
// the cheapest repair in the game -- a damaged Pulsar or a mauled squad
// otherwise walks home or dies.
// Later and fewer than the first attempt: 40 metal/s and one every 20 s put
// them up while the economy was still compounding, and they cost 15% army
// alongside the gate change. A repair station is worth having once there is
// something worth repairing.
const int   FRONT_NANO_PERIOD = 45 * SECOND;
const float FRONT_NANO_INCOME = 90.f;   // a real economy, not an early one
const float FRONT_NANO_SHARE  = 0.15f;  // of NanoCap(), so it stays a minority
int gNextFrontNano = 0;

IUnitTask@ FrontNano(CCircuitUnit@ unit)
{
	if (Factory::EcoLeadActive() || (ai.frame < gNextFrontNano))
		return null;
	if (aiEconomyMgr.metal.income < FRONT_NANO_INCOME)
		return null;
	if (aiEconomyMgr.isEnergyStalling)
		return null;   // a turret is 3200 energy to raise

	CCircuitDef@ want = SideDef3(armnanotc, cornanotc, legnanotc);
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;
	// Its own share of the cap, so front repair cannot eat the whole allowance.
	if (float(want.count) >= float(NanoCap()) * (1.f + FRONT_NANO_SHARE))
		return null;

	AIFloat3 spot;
	if (!Front::FrontNear(unit.GetPos(ai.frame), spot))
		return null;
	if (!OnMap(spot))
		return null;
	// BEHIND the line, not on it. apexearth: "never send a constructor to build a
	// tower in a dangerous place."
	if (ThreatFor(unit, spot) > CON_THREAT_VETO)
		return null;

	AIFloat3 place = ai.FindBuildSiteNear(want, spot, 600.f);
	if (!OnMap(place))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::NANO,
			Task::Priority::NORMAL, want, place, 0.f));
	if (post is null)
		return null;
	gNextFrontNano = ai.frame + FRONT_NANO_PERIOD;
	return post;
}

IUnitTask@ EcoNano(CCircuitUnit@ unit)
{
	// Turrets are for the eco lead OR for anyone whose bank is full: a player at
	// the metal cap is wasting income, and build power is the thing that turns it
	// back into units.
	// BUILD POWER SHOULD TRACK INCOME, NOT ONLY A FULL BANK.
	//
	// The old gate was "eco lead, or metal is FULL". Measured after raising the
	// in-flight limit: 576 turrets across 48 player-games, 12 each, on economies
	// running 100-400 metal/s -- because a full bank is a rare instant, not a
	// state. apexearth: "I need to build a lot more nanoturrets to keep up with
	// the amount of energy and resources that I have. When players play, they can
	// have hundreds of these."
	//
	// A turret is 210 metal for 140 build power that never walks anywhere. At
	// NANO_INCOME_GATE metal/second the income alone pays for one every few
	// seconds, so the bank check below is what should decide, not a cap event.
	const bool richEnough = (aiEconomyMgr.metal.income >= NanoIncomeGate());
	// Three independent reasons, not a role gate: the eco lead builds them as its
	// job, anyone at the metal cap needs the sink, and any real income justifies
	// the build power. Solo reaches this through the last two.
	if ((!Factory::EcoLeadActive() && !MetalFull() && !richEnough) || (ai.frame < gNextNano))
		return null;
	// Half the bank while poor, a fifth once the income itself justifies it.
	const float bankNeed = richEnough ? NANO_RICH_BANK : NANO_MIN_BANK;
	if (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * bankNeed)
		return null;
	// A turret costs 3200 energy to put up; buying build power on a grid that
	// cannot pay for it stalls both.
	if (aiEconomyMgr.isEnergyStalling)
		return null;

	CCircuitDef@ want = SideDef3(armnanotc, cornanotc, legnanotc);
	if ((want is null) || !want.IsAvailable(ai.frame) || (want.count >= NanoCap()))
		return null;

	// Bound what is OUTSTANDING, not just what stands. want.count sees finished
	// turrets only and Enqueue does not dedup, so the cap alone let this run to
	// asked=40 against standing=11 in one 20-minute stretch -- ordering a fresh
	// turret every period while thirty were already queued. Same failure the
	// rush constructor cap hit, and spacing alone does not fix it.
	//
	// The counter is resynced rather than trusted forever: a turret that dies
	// leaves asked permanently ahead of count, which would otherwise wedge this
	// rule shut for the rest of the game.
	int outstanding = gNanosAsked - want.count;
	if (outstanding > NANO_STALE) {
		gNanosAsked = want.count;
		outstanding = 0;
	}
	if (outstanding >= NanoInFlight())
		return null;

	AIFloat3 here;
	if (!BandSpot(unit, want, true, here))
		return null;

	// Nanos go TIGHT, right next to each other, on a grid pitch that leaves the
	// walkways clear. apexearth: "nano's should be placed right next to each
	// other usually." Spreading them was the earlier fix for a naval builder
	// walling itself in, and it was the wrong trade -- it bought walkability with
	// sprawl. Tight rows plus lanes is what buys both.
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::NANO,
			Task::Priority::NORMAL, want, here, 0.f));
	if (post is null)
		return null;
	gNextNano = ai.frame + NANO_PERIOD;
	++gNanosAsked;
	AiLog(Factory::T() + "apex: eco nano " + want.GetName()
		+ " standing=" + want.count + " asked=" + gNanosAsked
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0));
	return post;
}

}  // namespace Builder
