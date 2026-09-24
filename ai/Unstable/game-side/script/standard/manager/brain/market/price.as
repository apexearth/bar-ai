namespace Market {
//------------------------------------------------------------------------------
// The currency's two live prices.
//------------------------------------------------------------------------------

// LATCHED, NOT CACHED. CCircuitAI::GetTunable freezes a value on first read and
// never re-reads it, so holding it here is the SAME number -- no staleness
// trade. Every one of these sits on the per-candidate path: ValueOf prices each
// def of each want through them, so the string and the keyed lookup were paid
// once per candidate per election. Same latch coverage.as already applies to
// its own two (CwTuneFill).
bool  gPrTuneSet = false;
float gPrSpaceM = 0.f;
float gPrPaybackH = 0.f;
float gPrLockup = 0.f;
bool  gPrLateBuild = false;
float gPrAssistShare = 0.f;
float gPrEResponse = 0.f;
bool  gPrEBillOn = false;
float gPrEHeadroom = 0.f;
float gPrELookahead = 0.f;
bool  gPrERealizeOn = false;
float gPrEWasteWorth = 0.f;
bool  gPrMRealizeOn = false;
float gPrMWasteWorth = 0.f;
void PrTuneFill()
{
	if (gPrTuneSet)
		return;
	gPrTuneSet = true;
	gPrSpaceM = ai.GetTunable("apex_space_m", TUNE_SPACE_M);
	gPrPaybackH = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
	gPrLockup = ai.GetTunable("apex_lockup", TUNE_LOCKUP);
	gPrLateBuild = ai.GetTunable("apex_late_build", TUNE_LATE_BUILD) > 0.f;
	gPrAssistShare = ai.GetTunable("apex_assist_share", TUNE_ASSIST_SHARE);
	gPrEResponse = ai.GetTunable("apex_e_response", TUNE_E_RESPONSE);
	gPrEBillOn = ai.GetTunable("apex_e_bill_share", TUNE_E_BILL_SHARE) > 0.f;
	gPrEHeadroom = ai.GetTunable("apex_e_headroom", TUNE_E_HEADROOM);
	gPrELookahead = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
	gPrERealizeOn = ai.GetTunable("apex_e_realize", TUNE_E_REALIZE) > 0.f;
	gPrEWasteWorth = ai.GetTunable("apex_e_waste_worth", TUNE_E_WASTE_WORTH);
	gPrMRealizeOn = ai.GetTunable("apex_m_realize", TUNE_M_REALIZE) > 0.f;
	gPrMWasteWorth = ai.GetTunable("apex_m_waste_worth", TUNE_M_WASTE_WORTH);
}

// The wage of one builder-second: the metal flow each working builder carries.
// A choice that occupies a builder longer forgoes more of this.
float Wage()
{
	const int workers = int(aiBuilderMgr.GetWorkerCount());
	return Eco::MInc() / float(workers < 1 ? 1 : workers);
}

// WHAT A SECOND OF THIS BUILDER'S WALK COSTS. apexearth 2026-09-02, watching
// a commander build one tower at the front, walk 2,600 elmos back to guard a
// mex and 2,600 back to the front: "I'd guess we're not treating walks as
// expensive as they should be treated." Wage is the fleet's average earning
// per hand; a walking builder forgoes its OWN output, which for a 300-BP
// commander is three times a con's. The rate is what this lathe converts
// per second when building the faction's light tower -- the same yardstick
// the wall prices in -- and never below the wage it stood in for.
// The yardstick is metal per BP-second on the light tower, which is constant --
// latched, because SideDef3 is a def lookup BY NAME and this is priced into
// every Want's tCost. Zero until the def table answers, and never latched off
// a miss (the same law as BestConvRatio).
float gWalkTowerM = 0.f;
float gWalkTowerBT = 0.f;

// Wage is an engine worker-count query plus two economy reads, and ValueOf
// wanted it twice on one line -- here and again for the build's own seconds.
float WalkRateWith(float builderBP, float wage)
{
	if (builderBP <= 0.f)
		return wage;
	if (gWalkTowerBT <= 1.f) {
		CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
		if (light is null)
			return wage;
		const int ld = int(light.id);
		if (!Catalog::ValidId(ld) || (Catalog::gBuildTime[ld] <= 1.f))
			return wage;
		gWalkTowerM = Catalog::gCostM[ld];
		gWalkTowerBT = Catalog::gBuildTime[ld];
	}
	const float own = gWalkTowerM * builderBP / gWalkTowerBT;
	return (own > wage) ? own : wage;
}

float WalkRate(float builderBP)
{
	return WalkRateWith(builderBP, Wage());
}

// A builder's walk to a site, in seconds. Straight-line: no path cost query
// reaches script (CircuitAI's QueryCostMap is unbound), so blocked ground
// reads as free.
float WalkSecTo(CCircuitUnit@ unit, const AIFloat3& in to)
{
	if ((unit is null) || !OnMap(to))
		return 0.f;
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	if (speed <= 1.f)
		return 60.f;
	return unit.GetPos(ai.frame).distance2D(to) / speed;
}

// The floor exchange rate for energy: what a standing E/s is worth in metal
// once the converter that realizes it is paid for.
float gEPriceFloor = -1.f;
int gEFloorAt = 0;
// Smoothed energy-pull growth, E/s per second.
float gEPullPrev = -1.f;
int gEPullPrevAt = 0;
float gEPullGrowth = 0.f;
float gESurplusEma = 0.f;
float gEExcessEma = 0.f;   // the engine's own excess, smoothed like the surplus
float gEDemandPk = 0.f;
void TrackEPull()
{
	if (ai.frame < gEPullPrevAt + 5 * SECOND)
		return;
	const float pull = Eco::EPull();
	if (gEPullPrev >= 0.f) {
		const float dt = float(ai.frame - gEPullPrevAt) / float(SECOND);
		const float g = (pull - gEPullPrev) / ((dt > 1.f) ? dt : 1.f);
		gEPullGrowth = 0.7f * gEPullGrowth + 0.3f * g;
	}
	gEPullPrev = pull;
	gEPullPrevAt = ai.frame;
	// Slow EMA of the E surplus: converters must price the DURABLE surplus,
	// not a spike (a T1 converter outbidding a mex walk, watched -- the
	// third appearance of the temporal-consistency law).
	const float sur = Eco::EInc() - Eco::EPull();
	gESurplusEma = 0.9f * gESurplusEma + 0.1f * ((sur > 0.f) ? sur : 0.f);
	// ...AND WHAT IS ACTUALLY THROWN AWAY. Pull spikes with every build
	// burst, so income - pull read 3-33 E/s while the engine's own excess
	// read 600-1,000 and the bank sat at 80-99% (gate games, 13 min of
	// waste with converters at gain 0.07). The converter prices the larger
	// of the two, both smoothed the same way.
	const float exc = aiEconomyMgr.energy.excess;
	gEExcessEma = 0.9f * gEExcessEma + 0.1f * ((exc > 0.f) ? exc : 0.f);
	// REAL DEMAND, WHICH PULL UNDERSTATES. Pull is throttled demand and it
	// also dips to nothing whenever the fleet is between jobs -- read raw, it
	// called a working economy's whole generation wasted one tick and starving
	// the next. Rises instantly, decays slowly, so a lull does not erase what
	// the fleet was drawing a minute ago. Converters are excluded: they are
	// the sink for what nothing else wants, not a consumer to supply.
	const float dem = Eco::EPull() - ConvUseE();
	const float d0 = (dem > 0.f) ? dem : 0.f;
	gEDemandPk = (d0 > gEDemandPk) ? d0 : (0.97f * gEDemandPk + 0.03f * d0);
}

// The metal twin of the block above. Nothing is excluded from the demand here:
// a converter is a metal SOURCE, not a draw on it.
float gMPullPrev = -1.f;
int gMPullPrevAt = 0;
float gMPullGrowth = 0.f;
float gMDemandPk = 0.f;
void TrackMPull()
{
	if (ai.frame < gMPullPrevAt + 5 * SECOND)
		return;
	const float pull = Eco::MPull();
	if (gMPullPrev >= 0.f) {
		const float dt = float(ai.frame - gMPullPrevAt) / float(SECOND);
		const float g = (pull - gMPullPrev) / ((dt > 1.f) ? dt : 1.f);
		gMPullGrowth = 0.7f * gMPullGrowth + 0.3f * g;
	}
	gMPullPrev = pull;
	gMPullPrevAt = ai.frame;
	// Rises instantly, decays slowly -- the same temporal-consistency law the
	// energy side needed: metal pull dips to nothing between jobs.
	const float md0 = (pull > 0.f) ? pull : 0.f;
	gMDemandPk = (md0 > gMDemandPk) ? md0 : (0.97f * gMDemandPk + 0.03f * md0);
}

// A conversion ratio is not a price until a converter stands (apexearth:
// "we have to have a converter for that to even be true"). Per 1 E/s of
// throughput we own 1/cap of a converter, so its metal, its own energy bill
// and its build time amortize against the metal it makes over apex_conv_horizon
// seconds. Solved for P directly because the converter's energy cost is
// denominated in the price being computed:
//
//   P = (eff*cap*H - costM - buildSec*wage) / (cap*H + costE)
//
// Restricted to converters something we own can actually place -- the naive
// max over the catalog anchored the floor on the T2 converter (0.01724) and
// the scavenger units above it from frame zero.
float EPriceFloor()
{
	if ((gEPriceFloor >= 0.f) && (ai.frame < gEFloorAt))
		return gEPriceFloor;
	gEFloorAt = ai.frame + 30 * SECOND;
	const float H = ai.GetTunable("apex_conv_horizon", TUNE_CONV_HORIZON);
	const float h = (H > 1.f) ? H : 600.f;
	const float wage = Wage();
	float bp = EffBP(0.f);
	if (bp < 100.f)
		bp = 100.f;   // frame zero has no fleet; a solo con's order of magnitude
	float best = 0.f;      // among converters we can place
	float bestAny = 0.f;   // fallback: any converter in the catalog
	float bestRaw = 0.f;   // the undiscounted ratio of whichever def wins
	int bestId = 0;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		const float cap = Catalog::gConvCapacity[i];
		if (!Catalog::gAvailable[i] || (Catalog::gConvRatio[i] <= 0.f) || (cap <= 0.f))
			continue;
		const float bs = Catalog::BuildSecondsAt(i, bp);
		const float num = Catalog::gConvRatio[i] * cap * h
				- Catalog::gCostM[i] - bs * wage;
		const float den = cap * h + Catalog::gCostE[i];
		if ((num <= 0.f) || (den <= 0.f))
			continue;
		const float net = num / den;
		if (net > bestAny) {
			bestAny = net;
			if (best <= 0.f) {
				bestRaw = Catalog::gConvRatio[i];
				bestId = i;
			}
		}
		if (CanBuildEver(i) && (net > best)) {
			best = net;
			bestRaw = Catalog::gConvRatio[i];
			bestId = i;
		}
	}
	gEPriceFloor = (best > 0.f) ? best : bestAny;
	if (ai.GetTunable("apex_efloor_diag", 0.f) > 0.f) {
		AiLog("apex: efloor t=" + ai.teamId
			+ " floor=" + formatFloat(gEPriceFloor, "", 0, 5)
			+ " raw=" + formatFloat(bestRaw, "", 0, 5)
			+ " def=" + ((bestId > 0) ? Catalog::Def(bestId).GetName() : "-")
			+ " owned=" + ((best > 0.f) ? 1 : 0)
			+ " bp=" + formatFloat(bp, "", 0, 0)
			+ " wage=" + formatFloat(wage, "", 0, 2)
			+ " eInc=" + formatFloat(Eco::EInc(), "", 0, 0)
			+ " ePull=" + formatFloat(Eco::EPull(), "", 0, 0)
			+ " convUse=" + formatFloat(ConvUseE(), "", 0, 0)
			+ " convCap=" + formatFloat(ConvCapE(), "", 0, 0)
			+ " realize=" + formatFloat(ERealizeShare(20.f, 30.f), "", 0, 2)
			+ " fleetAsk=" + formatFloat(FleetAskE(), "", 0, 0)
			+ " bpCap=" + formatFloat(BPCapacity(), "", 0, 1)
			+ " mInc=" + formatFloat(Eco::MInc(), "", 0, 1)
			+ " mCur=" + formatFloat(Eco::MCur(), "", 0, 0));
	}
	return gEPriceFloor;
}

// What 1 E/s of standing generation is worth in metal/s. MODEL: under stall
// pressure, energy is worth the metal throughput it unlocks (income scales
// with E when E-limited: dM/dE ~ mIncome/eIncome); in surplus it is worth
// only the conversion floor.
float EPrice()
{
	PrTuneFill();
	// GAIN side, anchored on the game's own exchange rate (apexearth
	// 2026-08-23: "you have the metal conversion rates from the buildings
	// currently available, that should be how energy income is priced").
	// A stall multiplies the floor -- but only pull ABOVE income is a
	// stall; the perpetuity premium that let energy outbid mohos forever
	// is gone.
	// Supply is income plus the generation already ORDERED, or the demand
	// side's foresight is one-eyed: measured, a wind priced at 0.50 with the
	// bank full and 359 e/s on the way, and five winds went up in one burst.
	const float eInc = Eco::EInc() + EMakeInFlight();
	// Anticipation (apexearth 2026-08-23: "we need to anticipate our coming
	// lack of energy a little better"): price against where pull is HEADED
	// within the lookahead, not where it is.
	TrackEPull();
	// ...plus what we have ORDERED and are not yet drawing: committed work is
	// invisible to energy.pull, so the price could not rise until the stall
	// had already happened.
	// ...and the lines about to run (ECostSpot already counts them; the gain
	// side did not, so a lab under construction raised the E bill of every
	// build and the worth of no generator).
	float ePull = Eco::EPull() + EDrainInFlight() + LineDrainE();
	if (gEPullGrowth > 0.f)
		ePull += gEPullGrowth * gPrELookahead;
	// Supply LEADS demand (apexearth 2026-08-23: "we shouldn't even let
	// ourselves get to the point where we've run out of E"): the target is
	// income at headroom over trending pull, so a standing premium exists
	// while income merely MATCHES pull, and the bank never gets raced.
	ePull *= gPrEHeadroom;
	// ...and never below what the hands we own ask at full speed.
	{
		const float ask = FleetAskE();
		if (ePull < ask)
			ePull = ask;
	}
	float excess = (eInc > 0.01f) ? (ePull / eInc - 1.f) : 2.f;
	if (excess > 2.f)
		excess = 2.f;
	if (excess < 0.f)
		excess = 0.f;
	const float eCur = Eco::ECur();
	const float eStore = Eco::EStor();
	if ((eStore > 1.f) && (eCur < 0.25f * eStore) && (excess < 1.f))
		excess = 1.f;
	// A genuine stall throttles the fleet's whole SPENDING flow -- the
	// at-risk quantity is metal.pull, not the converter trickle (measured:
	// floor-anchored stall pricing left an E-stalled game frozen at 635
	// metal produced in 40 minutes; "we e-stalled and should have made a
	// basic solar").
	const float fl = EPriceFloor();
	// THE DERIVATION, NOT A PREMIUM. Lathes run at the smaller of the two
	// feed shares, so one e/s is worth (the metal flow they would run) /
	// (the energy flow they need): the fleet's spend capacity, not the pull
	// the stall has already throttled, bounded by what income and the bank
	// can feed. excess*pull/income overpriced a deep stall six-fold and
	// bought an advanced solar at 64 e/s.
	float flow = BPCapacity();
	{
		const float look = (gPrELookahead > 1.f) ? gPrELookahead : 30.f;
		const float feed = Eco::MInc() + Eco::MCur() / look;
		if (flow > feed)
			flow = feed;
	}
	const float atRisk = ((eInc > 0.01f) && (excess > 0.f))
			? (flow / (eInc * (1.f + excess))) : 0.f;
	return (atRisk > fl) ? atRisk : fl;
}

// COST side: the premium on SPENDING E exists only above balance -- at
// income == pull nothing is starving, and the E bill is the floor. This is
// the asymmetry that lets advsol/fusion be bought while solar-fed: the same
// balance that makes new E supply valuable makes spending E cheap.
float ECostSpot()
{
	PrTuneFill();
	const float eInc = Eco::EInc() + EMakeInFlight();
	const float ePull = Eco::EPull() + EDrainInFlight() + LineDrainE();
	float excess = (eInc > 0.01f) ? (ePull / eInc - 1.f) : 2.f;
	if (excess > 2.f)
		excess = 2.f;
	if (excess < 0.f)
		excess = 0.f;
	const float eCur = Eco::ECur();
	const float eStore = Eco::EStor();
	if ((eStore > 1.f) && (eCur < 0.25f * eStore) && (excess < 1.f))
		excess = 1.f;
	// The same derivation and the same flow as EPrice: spending E throttles
	// the same lathes. Priced off metal INCOME (7 m/s) while the gain side
	// read the fleet's flow (47), a 5,000-E advanced solar billed 167.
	float flow = BPCapacity();
	{
		const float look = (gPrELookahead > 1.f) ? gPrELookahead : 30.f;
		const float feed = Eco::MInc() + Eco::MCur() / look;
		if (flow > feed)
			flow = feed;
	}
	const float unlock = ((eInc > 0.01f) && (excess > 0.f))
			? (flow / (eInc * (1.f + excess))) : 0.f;
	const float fl = EPriceFloor();
	return (unlock > fl) ? unlock : fl;
}

// The E price a build DELIVERING IN buildSec seconds earns: the scarcity
// premium decays toward the floor over the market's own supply-response time
// (about one solar's build). A 7,000-second AFUS priced at today's stall
// premium froze our only T2 con for a whole game (measured, 2026-08-23).
// What spending E during this build actually FORGOES. While the E bank is
// full and income exceeds pull, the spent energy was being wasted -- its
// cost is forgiven outright (apexearth 2026-08-23: "you can forgive cost
// when we have extra of something like energy").
float EPriceCostAt(float buildSec, float costE)
{
	PrTuneFill();
	const float fl = EPriceFloor();
	const float spot = ECostSpot();
	// AN E BILL IS A DRAIN, AND WHAT MAKES IT AFFORDABLE IS INCOME. The
	// build-length decay below knows only how long the build runs, so a 5,000 E
	// advanced solar was charged at ~the conversion floor whatever the economy
	// earned -- and the market bought one while stalled at 100 E/s, where its
	// 63 E/s of draw is most of everything we make (apexearth: "an advanced
	// solar is hardly affordable at 100e/s income. And it costs a lot of energy
	// to make. So income restrictions must apply"). Charge the share of income
	// the build's own drain eats at the scarcity price, the rest at the floor:
	// the same building is cheap at 400 E/s and unaffordable at 100, on income
	// alone. While stalled (apexearth: "it only matters when we're
	// e-stalling") -- and while the build would CAUSE one: its drain is known
	// before the order exists, and if income plus the bank cannot carry it
	// for the whole build it stalls us, so it is billed as if we were.
	float k;
	bool eBill = gPrEBillOn && (costE > 0.f) && (buildSec > 1.f);
	if (eBill && !HardEStall()) {
		const float drain = costE / buildSec;
		const float over = (Eco::EPull() + EDrainInFlight() + drain)
				- Eco::EInc() - EMakeInFlight();
		eBill = (over > 0.f) && (over * buildSec > Eco::ECur());
	}
	// Forgiven only when the build does NOT drain the bank and income also
	// covers the lines about to run. Forgiven on the full bank alone, three
	// 3,200-E nano turrets priced at zero energy in one minute and emptied it.
	// ...and when the surplus itself carries this build's drain, bank full
	// or not: with income 1,700 over a pull of 700 and the bank swinging
	// 76-100%, a one-metal converter was billed 110-160 metal of energy and
	// priced below the overflow it would eat (gate game, 19 min of waste).
	// Energy neither stored nor used has no price.
	if (!eBill) {
		const float spare = Eco::EInc() + EMakeInFlight()
				- Eco::EPull() - LineDrainE();
		const float drain = (buildSec > 1.f) ? (costE / buildSec) : costE;
		if ((aiEconomyMgr.isEnergyFull && (spare > 0.f)) || (spare >= drain))
			return 0.f;
	}
	if (eBill) {
		const float eInc = Eco::EInc();
		const float drain = costE / buildSec;
		k = (eInc > 0.01f) ? (drain / eInc) : 1.f;
	} else {
		const float resp = gPrEResponse;
		k = ((resp > 1.f) ? resp : 45.f) / ((buildSec > 1.f) ? buildSec : 1.f);
	}
	if (k > 1.f)
		k = 1.f;
	return fl + (spot - fl) * k;
}

// WHAT A NEW E/s WOULD ACTUALLY TURN INTO METAL. Energy nothing spends and
// no converter chews makes no metal at all, so a generator added on top of a
// wasted band is worth nothing until the converter that realizes it stands
// (apexearth: "if we're already overflowing energy we should understand that
// adding more energy will not add the metal value"). Demand is pull MINUS
// what our own converters draw -- a converter is a sink of last resort, not a
// consumer to lead by a headroom factor -- plus the converter fleet's whole
// capacity, which is the part of an overflow that does become metal. The
// share above that line decays to zero, which is what makes the market buy
// the converter first and the next generator after it; it lifts by itself the
// moment capacity or real demand rises, so nothing is forbidden.
float ERealizeShare(float addE, float buildSec)
{
	PrTuneFill();
	if (addE <= 0.f)
		return 1.f;
	if (!gPrERealizeOn)
		return 1.f;
	TrackEPull();
	float demand = Eco::EPull() - ConvUseE();
	if (demand < gEDemandPk)
		demand = gEDemandPk;
	if (demand < 0.f)
		demand = 0.f;
	// Anticipation, over the build's own delivery time but never further out
	// than the price's own lookahead -- the pull EMA is not a forecast.
	if (gEPullGrowth > 0.f) {
		const float look = gPrELookahead;
		demand += gEPullGrowth * ((buildSec < look) ? buildSec : look);
	}
	// A BANK THAT IS NOT FULL IS A REAL USE. Energy going into storage is not
	// wasted -- it is spent later, and at frame zero it is the only consumer
	// there is. Charged over the same anticipation window as everything else,
	// so it dries up exactly as the bank fills.
	float fill = 0.f;
	{
		const float look = gPrELookahead;
		const float bankRoom = Eco::EStor() - Eco::ECur();
		if ((bankRoom > 0.f) && (look > 1.f))
			fill = bankRoom / look;
	}
	float target = demand * gPrEHeadroom
			+ ConvCapE() + fill;
	// ...and never below the standing fleet's full-speed ask.
	{
		const float ask = FleetAskE() + ConvCapE() + fill;
		if (target < ask)
			target = ask;
	}
	// NEVER ZERO. Energy in the wasted band is not worthless -- it is worth the
	// conversion floor as soon as a converter follows, and the floor price
	// already nets that converter's own cost out. What it is missing is the
	// wait, and the chance nothing ever converts it. So the band keeps a share
	// of its value and simply LOSES to the converter that would realize it
	// (apexearth: "we still should care about energy, so not zero - but we want
	// converters to be above the energy want"). Generation is never switched
	// off by an overflow, which is the standing ruling.
	// ...AND THE CONVERTER MUST ACTUALLY BE FOLLOWING. The flat floor kept
	// buying reactors at 62k e/s income with 21k wasted and 27k of converter
	// standing (his seat, minute 28): the band's worth is the share of the
	// waste a converter already ordered will eat, never more than the
	// floor, never quite zero.
	float floorShare = gPrEWasteWorth;
	{
		const float wasteE = Eco::EInc() - Eco::EPull();
		if (wasteE > 1.f) {
			float follow = ConvCapInFlight() / wasteE;
			if (follow > 1.f)
				follow = 1.f;
			floorShare = gPrEWasteWorth * follow;
			if (floorShare < 0.02f)
				floorShare = 0.02f;
		}
	}
	const float room = target - Eco::EInc() - EMakeInFlight();
	float share = (room <= 0.f) ? 0.f
			: ((room < addE) ? (room / addE) : 1.f);
	if (share < floorShare)
		share = floorShare;
	return share;
}

// The metal twin of ERealizeShare: extraction priced by the share of its metal
// we could actually spend. Energy has always had to prove something would
// absorb it and extraction never did, so a mex held full price while the bank
// spilled. Orthogonal to apex_mexup_boost, which still decides extraction
// against energy whenever the metal can be spent at all. The horizon knobs are
// the energy side's on purpose -- a lookahead is a property of the question,
// not of the resource. See docs/27.
int gMRealLogAt = 0;
float MRealizeShare(float addM, float buildSec)
{
	PrTuneFill();
	if (addM <= 0.f)
		return 1.f;
	if (!gPrMRealizeOn)
		return 1.f;
	// NO INCOME, NO WASTE. At frame zero the bank is FULL from the starting
	// grant with income and pull both nothing, so the arithmetic below reads
	// "we cannot spend a thing" and discounts the opening mex to the floor --
	// measured, share=0.250 on the first sample of a fresh game. A resource
	// that is not flowing yet cannot be spilling; the peak-held demand covers
	// every later lull on its own.
	if (Eco::MInc() <= 0.f)
		return 1.f;
	TrackMPull();
	float demand = Eco::MPull();
	if (demand < gMDemandPk)
		demand = gMDemandPk;
	if (demand < 0.f)
		demand = 0.f;
	if (gMPullGrowth > 0.f) {
		const float look = gPrELookahead;
		demand += gMPullGrowth * ((buildSec < look) ? buildSec : look);
	}
	// A bank that is not full is a real use, exactly as on the energy side --
	// and at frame zero it is the only consumer there is.
	float fill = 0.f;
	{
		const float look = gPrELookahead;
		const float bankRoom = Eco::MStor() - Eco::MCur();
		if ((bankRoom > 0.f) && (look > 1.f))
			fill = bankRoom / look;
	}
	const float target = demand * gPrEHeadroom + fill;
	// NEVER ZERO, for the reason the energy floor is not zero: demand grows, and
	// a spot claimed now is still ours when it does. The band loses the wait,
	// not the metal.
	const float floorShare = gPrMWasteWorth;
	const float room = target - Eco::MInc();
	float share = (room <= 0.f) ? 0.f
			: ((room < addM) ? (room / addM) : 1.f);
	if (share < floorShare)
		share = floorShare;
	if (ai.frame >= gMRealLogAt) {
		gMRealLogAt = ai.frame + 30 * SECOND;
		const float mst = Eco::MStor();
		AiLog("apex: mrealize t=" + ai.teamId
			+ " share=" + formatFloat(share, "", 0, 3)
			+ " addM=" + formatFloat(addM, "", 0, 2)
			+ " mInc=" + int(Eco::MInc())
			+ " mPull=" + int(Eco::MPull())
			+ " pk=" + int(gMDemandPk)
			+ " growth=" + formatFloat(gMPullGrowth, "", 0, 2)
			+ " target=" + int(target)
			+ " bank%=" + int((mst > 1.f) ? (100.f * Eco::MCur() / mst) : -1.f));
	}
	return share;
}

// HOW MUCH LONGER AN ENERGY-COSTING BUILD REALLY TAKES WHILE ENERGY IS SHORT.
// A lathe gets the share of income its drain is of the pull, so the build
// runs at income/pull speed: a 90-second advanced solar is minutes in a
// stall while a zero-E solar keeps its nine seconds (apexearth, watching:
// "when we're stalling right now then fixing that stalling sooner should
// look much more attractive").
float EStretch(float costE, float buildSec)
{
	if ((costE <= 1.f) || (buildSec <= 1.f))
		return 1.f;
	const float drain = costE / buildSec;
	const float need = Eco::EPull() + EDrainInFlight() + drain;
	// In-flight generators are not feed: their output arrives when they
	// finish, and they finish on the same starved surplus. Counted, every
	// crawling frame made the next one price as if it already ran.
	const float have = Eco::EInc()
			+ Eco::ECur() / buildSec;
	if ((have <= 0.01f) || (need <= have))
		return 1.f;
	return need / have;
}

float EPriceAt(float buildSec)
{
	PrTuneFill();
	const float fl = EPriceFloor();
	const float spot = EPrice();
	const float resp = gPrEResponse;
	float k = ((resp > 1.f) ? resp : 45.f) / ((buildSec > 1.f) ? buildSec : 1.f);
	if (k > 1.f)
		k = 1.f;
	return fl + (spot - fl) * k;
}

//------------------------------------------------------------------------------
// Pricing.
//------------------------------------------------------------------------------

// Builds run at fleet-assisted speed, not the asker's solo lathe:
// Requests::Take folds same-def askers onto a site, so a share of the
// standing fleet shows up. Solo pricing made a 99s advsol lose to fast
// solars for every T1 con forever -- the capability multiplier is real
// (apexearth 2026-08-23). MODEL: the share that assists.
float EffBP(float builderBP)
{
	PrTuneFill();
	const float fleet = BPCapacity() * (80.f / 7.f);   // back to workertime units
	const float share = gPrAssistShare;
	if (fleet <= builderBP)
		return builderBP;
	return builderBP + (fleet - builderBP) * share;
}

// The metal mirror of the E forgiveness: a full, still-filling bank means
// the metal bill forgoes almost nothing (measured: 104k excess while
// fusion #3 lost auctions priced in a currency being wasted). A floor
// keeps relative ordering by cost.
float MCostScale()
{
	const float st = Eco::MStor();
	if ((st <= 1.f) || (Eco::MInc() <= Eco::MPull()))
		return 1.f;
	// A high bank is the integral of underpricing: forgiveness ramps in
	// from HALF-full (watched: 3,700 banked while outnumbered -- "we
	// certainly could afford it").
	// NET OF WHAT IS ALREADY PROMISED. Read raw, the same full bank was handed
	// to every claimant in the same instant and each one discounted itself
	// against metal the others had already spoken for (see Market::MOrderedM).
	float bank = Eco::MCur() - MOrderedM();
	if (bank < 0.f)
		bank = 0.f;
	const float frac = bank / st;
	if (frac <= 0.35f)
		return 1.f;
	const float f = (frac - 0.35f) / 0.45f;
	return 1.f - 0.8f * ((f > 1.f) ? 1.f : f);
}


// `lateStart`: whether the walk also delays a STREAM worth `gain` a second
// (an extractor's income, a generator's E). A defence want's gain is the
// demand pull -- a target gap amortised over the exposure window, not a flow
// that starts when the gun stands -- and the site election has already
// priced its walk against that window; charging it again here at the pull
// rate put a line slot's tCost at 600-900 against a mex's 100-300 and priced
// the front out of every draw.
float ValueOf(int defId, float gain, float walkSec, float builderBP, Want@ w,
		bool lateStart = true, float riskM = 0.f)
{
	PrTuneFill();
	float buildSec = Catalog::BuildSecondsAt(defId, EffBP(builderBP));
	// METAL FEEDS THE LATHE (apexearth: a fusion started before the mohos
	// runs at quarter feed and takes 4x longer -- "the math is bad"). A
	// build's real duration is floored by what income + the bank can pay:
	// this is what re-orders fusion AFTER the mexups, with no sequencing
	// rule anywhere -- the upgrades finish fast AND raise the feed.
	float displacedM = 0.f;
	{
		const float mInc = Eco::MInc();
		const float mBank = Eco::MCur();
		if (mInc > 0.1f) {
			// (An affordability multiplier of (cost+committedDebt)/cost was
			// tried here and REVERTED same day: a debt ledger is not a
			// flow commitment -- three seeds wasted 3.5-8.7k and pushed T2
			// past 20m while metal overflowed, which is proof the income
			// was never actually spoken for. The affordability that works
			// is on the GAIN side: unserved demand divides among the pipes
			// in flight.)
			const float feedSec = (Catalog::gCostM[defId] - mBank * 0.5f) / mInc;
			// WHAT IT POSTPONES, WHETHER OR NOT IT IS FEED-BOUND. This charge
			// used to live entirely inside the feed-bound branch, so a def with
			// a huge BUILDTIME -- an afus above all -- had a buildSec long
			// enough that income always kept up, the gate never fired, and it
			// paid nothing at all for the upgrade stream it delays (apexearth:
			// "AFUS value should have been heavily diminished because of how
			// long it would have taken us to create it"; measured, the same
			// afus priced at t=15319 and t=904 in one game, a 17x swing from an
			// all-or-nothing charge). What actually matters is the share of our
			// income the build consumes across its own duration: at share 1 it
			// eats everything and the old feed-bound formula is recovered
			// exactly, and a cheap quick build charges near nothing.
			{
				const float dur = (buildSec > 1.f) ? buildSec : 1.f;
				float share = Catalog::gCostM[defId] / (mInc * dur);
				if (share > 1.f)
					share = 1.f;
				// Upgrades AND claims: both are extraction this build defers.
				// See OpenSpotStream in want_mex.as.
				// Bounded by the hands that could actually SERVE the stream:
				// gAvailable is not tier-gated, so BestExtract names the moho
				// from frame zero and UpDemand counted a stream no builder we
				// own can perform -- taxing every T1 solar and tower for
				// upgrades nobody could have done. OpenSpotStream already
				// bounds itself this way.
				// A build that returns more per second than the stream it
				// holds up displaces nothing: the advanced converter at 16 m/s
				// was charged 500-2,200 s of "rest" for the mex upgrades its
				// own metal would fund, and priced below them while 5k E/s
				// was thrown away on a metal-starved map.
				if ((share > 0.f) && (Catalog::gExtractsM[defId] <= 0.f)) {
					float held = DisplacedStreamM() - ((gain > 0.f) ? gain : 0.f);
					if (held < 0.f)
						held = 0.f;
					displacedM = held * dur * share;
				}
			}
			if (feedSec > buildSec) {
				buildSec = feedSec;
				// A feed-bound build eats the whole income for its duration
				// -- so it CHARGES the upgrade stream it postpones. This is
				// the second half of the fusion-before-mohos math: pricing
				// its own slowness narrowed the race (10.06 vs 12.99,
				// measured); pricing what it displaces ends it. A moho's
				// own displacement is trivial, a fusion's is decisive.
				// Charged for FEED COMPETITORS only: streams whose own
				// builds need this income (mohos, 620m each). Open T1
				// claims are ~50m and happen in parallel on freed hands --
				// charging them here double-counted the same income and
				// priced T2 out of a whole 25-minute game (A/B, seed 5:
				// mex 30 and techStart=-1). The pile-on itself is what
				// FreeMetalFlow kills, on the assist side.
				// Do NOT overwrite the charge computed above. Recomputing it
				// here from UpDemand alone dropped the open-spot term at the
				// feed boundary, so a marginally slower build paid LESS
				// displacement than one just under the line -- a step down
				// exactly where the charge should be rising.
			}
		}
	}
	// A RATE THAT HAS NOT STARTED IS NOT INCOME. gain is metal/s and nothing
	// above asks WHEN that rate begins, so a build delivering nothing for
	// eighteen minutes priced almost like one delivering in thirty-six seconds.
	// tCost charges the builder's seconds at Wage, which for an afus is ~3300
	// against a 9700 metal bill: real, but far too small to separate them.
	//
	// A gain is therefore credited only for the share of apex_payback_h it will
	// actually be collecting. Self-correcting on build power and on income --
	// the same afus lands in 110 seconds at 3000 BP and keeps nearly all its
	// value -- so a rich economy buys one and a poor one does not, with no rule
	// saying so. (The size of that gap is NOT settled: see CHANGES.md; a
	// compounding argument for it was checked and does not hold at fixed build
	// power, where the small-step route is lathe-bound and grows linearly.)
	// The stall's throttle, on the build's own energy bill.
	buildSec *= EStretch(Catalog::gCostE[defId], buildSec);
	w.gain = gain;
	w.buildSec = buildSec;
	w.walkSec = (walkSec > 0.f) ? walkSec : 0.f;
	// The E bill at what it actually forgoes (duration-priced, forgiven in
	// overflow) -- pricing it at the spot spike structurally banned every
	// big-E build (advsol, fusion) exactly when they were wanted.
	// The SPACE bill: ground is finite; footprint is paid per cell. MODEL:
	// a flat metal-per-cell price (apex_space_m) until base-crowding senses
	// price it dynamically. This is what makes dense energy (advsol) beat a
	// field of solars at equal payback.
	// A GENERATOR REPAYS ITS OWN ENERGY BILL, so that bill is priced at the
	// conversion floor, never at the stall premium: priced at the premium an
	// economy short of energy could never afford the thing that makes it
	// and bought T1 solars instead all game (20 solars and 4 advanced ones
	// against their 9 and 13 at minute 8, four 2v2s). The build itself is
	// still stretched by the stall above; that part is physical.
	const float ePriceE = (Catalog::gMakeE[defId] > 0.f)
			? EPriceFloor()
			: EPriceCostAt(buildSec, Catalog::gCostE[defId]);
	w.mCost = Catalog::gCostM[defId] * MCostScale()
			+ Catalog::gCostE[defId] * ePriceE
			+ float(Catalog::gAreaCells[defId])
				* gPrSpaceM;
	const float wageNow = Wage();
	w.tCost = walkSec * WalkRateWith(builderBP, wageNow) + buildSec * wageNow
			+ displacedM
			+ riskM;   // the builder's expected loss on the trip, see TripRisk
	// THE INCOME THE WALK ITSELF FORGOES (apexearth: "the cost in that walk
	// sec is ALSO the amount of metal you'd have lost from all that walk time
	// you'd make as metal income if you had built the closer one"). Wage above
	// charges the BUILDER's idle seconds; this charges the ASSET's late start,
	// which is the far larger number for anything that yields a rate. Scales
	// with the gain, so it decides extractor siting and is noise for a nano --
	// no per-kind distance rule anywhere.
	// The build delays the stream exactly as the walk does: a nine-minute
	// reactor paid one builder's wage for its build and outbid a fusion that
	// would have been producing for eight of those minutes.
	if (lateStart)
		w.tCost += gain * (walkSec + (gPrLateBuild ? buildSec : 0.f));
	// THE OPTIONS A LONG BUILD COSTS YOU. apexearth: "during that entire time
	// you're making an AFUS you can afford military better and protect
	// yourself. You're giving yourself options... you can put a little bit
	// extra of a penalty on top of 'time' in these things - that works as the
	// 'lack of options' doing that causes."
	//
	// Metal committed to a frame is metal that cannot answer anything for as
	// long as the frame stands, so the cost is the CAPITAL times the fraction
	// of the horizon it is locked for -- superlinear in duration, because both
	// the amount and the wait grow together. A moho at 640 metal and 47 seconds
	// pays ~17; an afus at 9700 and 1097 pays thousands. Nothing is forbidden:
	// the same afus at high build power is short and pays little.
	{
		const float H = gPrPaybackH;
		const float k = gPrLockup;
		if ((H > 1.f) && (k > 0.f))
			w.tCost += Catalog::gCostM[defId] * (buildSec / H) * k;
	}
	// The FLOW bill (apexearth 2026-08-23): this build's E drain is a rate,
	// costE/buildSec, and any part of it that income + the bank cannot fund
	// across the build throttles EVERY lathe (pull 300 on income 50 = 1/6th
	// build speed fleet-wide). The inflicted slowdown is charged here as
	// lost fleet throughput -- arithmetic, not a model.
	if ((Catalog::gCostE[defId] > 1.f) && (buildSec > 1.f)) {
		const float wantDrain = Catalog::gCostE[defId] / buildSec;
		const float projPull = Eco::EPull() + wantDrain;
		const float bankRate = Eco::ECur() / buildSec;
		const float unfunded = projPull - Eco::EInc() - bankRate;
		if ((unfunded > 0.f) && (projPull > 1.f)) {
			w.tCost += buildSec * Eco::MPull() * (unfunded / projPull);
		}
	}
	w.value = gain / (w.mCost + w.tCost);
	return w.value;
}


}  // namespace Market
