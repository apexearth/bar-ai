namespace Market {
//------------------------------------------------------------------------------
// The currency's two live prices.
//------------------------------------------------------------------------------

// The wage of one builder-second: the metal flow each working builder carries.
// A choice that occupies a builder longer forgoes more of this.
float Wage()
{
	const int workers = int(aiBuilderMgr.GetWorkerCount());
	return aiEconomyMgr.metal.income / float(workers < 1 ? 1 : workers);
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

float WalkRate(float builderBP)
{
	float r = Wage();
	if (builderBP <= 0.f)
		return r;
	if (gWalkTowerBT <= 1.f) {
		CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
		if (light is null)
			return r;
		const int ld = int(light.id);
		if (!Catalog::ValidId(ld) || (Catalog::gBuildTime[ld] <= 1.f))
			return r;
		gWalkTowerM = Catalog::gCostM[ld];
		gWalkTowerBT = Catalog::gBuildTime[ld];
	}
	const float own = gWalkTowerM * builderBP / gWalkTowerBT;
	return (own > r) ? own : r;
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
float gEDemandPk = 0.f;
void TrackEPull()
{
	if (ai.frame < gEPullPrevAt + 5 * SECOND)
		return;
	const float pull = aiEconomyMgr.energy.pull;
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
	const float sur = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
	gESurplusEma = 0.9f * gESurplusEma + 0.1f * ((sur > 0.f) ? sur : 0.f);
	// REAL DEMAND, WHICH PULL UNDERSTATES. Pull is throttled demand and it
	// also dips to nothing whenever the fleet is between jobs -- read raw, it
	// called a working economy's whole generation wasted one tick and starving
	// the next. Rises instantly, decays slowly, so a lull does not erase what
	// the fleet was drawing a minute ago. Converters are excluded: they are
	// the sink for what nothing else wants, not a consumer to supply.
	const float dem = aiEconomyMgr.energy.pull - ConvUseE();
	const float d0 = (dem > 0.f) ? dem : 0.f;
	gEDemandPk = (d0 > gEDemandPk) ? d0 : (0.97f * gEDemandPk + 0.03f * d0);
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
			+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
			+ " ePull=" + formatFloat(aiEconomyMgr.energy.pull, "", 0, 0)
			+ " convUse=" + formatFloat(ConvUseE(), "", 0, 0)
			+ " convCap=" + formatFloat(ConvCapE(), "", 0, 0)
			+ " realize=" + formatFloat(ERealizeShare(20.f, 30.f), "", 0, 2));
	}
	return gEPriceFloor;
}

// What 1 E/s of standing generation is worth in metal/s. MODEL: under stall
// pressure, energy is worth the metal throughput it unlocks (income scales
// with E when E-limited: dM/dE ~ mIncome/eIncome); in surplus it is worth
// only the conversion floor.
float EPrice()
{
	// GAIN side, anchored on the game's own exchange rate (apexearth
	// 2026-08-23: "you have the metal conversion rates from the buildings
	// currently available, that should be how energy income is priced").
	// A stall multiplies the floor -- but only pull ABOVE income is a
	// stall; the perpetuity premium that let energy outbid mohos forever
	// is gone.
	const float eInc = aiEconomyMgr.energy.income;
	// Anticipation (apexearth 2026-08-23: "we need to anticipate our coming
	// lack of energy a little better"): price against where pull is HEADED
	// within the lookahead, not where it is.
	TrackEPull();
	// ...plus what we have ORDERED and are not yet drawing: committed work is
	// invisible to energy.pull, so the price could not rise until the stall
	// had already happened.
	float ePull = aiEconomyMgr.energy.pull + EDrainInFlight();
	if (gEPullGrowth > 0.f)
		ePull += gEPullGrowth * ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
	// Supply LEADS demand (apexearth 2026-08-23: "we shouldn't even let
	// ourselves get to the point where we've run out of E"): the target is
	// income at headroom over trending pull, so a standing premium exists
	// while income merely MATCHES pull, and the bank never gets raced.
	ePull *= ai.GetTunable("apex_e_headroom", TUNE_E_HEADROOM);
	float excess = (eInc > 0.01f) ? (ePull / eInc - 1.f) : 2.f;
	if (excess > 2.f)
		excess = 2.f;
	if (excess < 0.f)
		excess = 0.f;
	const float eCur = aiEconomyMgr.energy.current;
	const float eStore = aiEconomyMgr.energy.storage;
	if ((eStore > 1.f) && (eCur < 0.25f * eStore) && (excess < 1.f))
		excess = 1.f;
	// A genuine stall throttles the fleet's whole SPENDING flow -- the
	// at-risk quantity is metal.pull, not the converter trickle (measured:
	// floor-anchored stall pricing left an E-stalled game frozen at 635
	// metal produced in 40 minutes; "we e-stalled and should have made a
	// basic solar").
	const float fl = EPriceFloor();
	const float atRisk = (eInc > 0.01f)
			? (excess * aiEconomyMgr.metal.pull / eInc) : 1.f;
	return (atRisk > fl) ? atRisk : fl;
}

// COST side: the premium on SPENDING E exists only above balance -- at
// income == pull nothing is starving, and the E bill is the floor. This is
// the asymmetry that lets advsol/fusion be bought while solar-fed: the same
// balance that makes new E supply valuable makes spending E cheap.
float ECostSpot()
{
	const float eInc = aiEconomyMgr.energy.income;
	const float ePull = aiEconomyMgr.energy.pull + EDrainInFlight() + LineDrainE();
	float excess = (eInc > 0.01f) ? (ePull / eInc - 1.f) : 2.f;
	if (excess > 2.f)
		excess = 2.f;
	if (excess < 0.f)
		excess = 0.f;
	const float eCur = aiEconomyMgr.energy.current;
	const float eStore = aiEconomyMgr.energy.storage;
	if ((eStore > 1.f) && (eCur < 0.25f * eStore) && (excess < 1.f))
		excess = 1.f;
	const float unlock = (eInc > 0.01f)
			? (excess * aiEconomyMgr.metal.income / eInc) : 1.f;
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
	if (aiEconomyMgr.isEnergyFull
		&& (aiEconomyMgr.energy.income > aiEconomyMgr.energy.pull))
	{
		return 0.f;
	}
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
	// alone. ONLY WHILE STALLED (apexearth: "it only matters when we're
	// e-stalling"): with energy in hand, what a build's E bill competes with is
	// nothing, and the build-length decay is the right price for it.
	float k;
	if ((ai.GetTunable("apex_e_bill_share", TUNE_E_BILL_SHARE) > 0.f)
		&& HardEStall() && (costE > 0.f) && (buildSec > 1.f))
	{
		const float eInc = aiEconomyMgr.energy.income;
		const float drain = costE / buildSec;
		k = (eInc > 0.01f) ? (drain / eInc) : 1.f;
	} else {
		const float resp = ai.GetTunable("apex_e_response", TUNE_E_RESPONSE);
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
	if (addE <= 0.f)
		return 1.f;
	if (ai.GetTunable("apex_e_realize", TUNE_E_REALIZE) <= 0.f)
		return 1.f;
	TrackEPull();
	float demand = aiEconomyMgr.energy.pull - ConvUseE();
	if (demand < gEDemandPk)
		demand = gEDemandPk;
	if (demand < 0.f)
		demand = 0.f;
	// Anticipation, over the build's own delivery time but never further out
	// than the price's own lookahead -- the pull EMA is not a forecast.
	if (gEPullGrowth > 0.f) {
		const float look = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
		demand += gEPullGrowth * ((buildSec < look) ? buildSec : look);
	}
	// A BANK THAT IS NOT FULL IS A REAL USE. Energy going into storage is not
	// wasted -- it is spent later, and at frame zero it is the only consumer
	// there is. Charged over the same anticipation window as everything else,
	// so it dries up exactly as the bank fills.
	float fill = 0.f;
	{
		const float look = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
		const float bankRoom = aiEconomyMgr.energy.storage - aiEconomyMgr.energy.current;
		if ((bankRoom > 0.f) && (look > 1.f))
			fill = bankRoom / look;
	}
	const float target = demand * ai.GetTunable("apex_e_headroom", TUNE_E_HEADROOM)
			+ ConvCapE() + fill;
	// NEVER ZERO. Energy in the wasted band is not worthless -- it is worth the
	// conversion floor as soon as a converter follows, and the floor price
	// already nets that converter's own cost out. What it is missing is the
	// wait, and the chance nothing ever converts it. So the band keeps a share
	// of its value and simply LOSES to the converter that would realize it
	// (apexearth: "we still should care about energy, so not zero - but we want
	// converters to be above the energy want"). Generation is never switched
	// off by an overflow, which is the standing ruling.
	const float floorShare = ai.GetTunable("apex_e_waste_worth", TUNE_E_WASTE_WORTH);
	const float room = target - aiEconomyMgr.energy.income;
	float share = (room <= 0.f) ? 0.f
			: ((room < addE) ? (room / addE) : 1.f);
	if (share < floorShare)
		share = floorShare;
	return share;
}

float EPriceAt(float buildSec)
{
	const float fl = EPriceFloor();
	const float spot = EPrice();
	const float resp = ai.GetTunable("apex_e_response", TUNE_E_RESPONSE);
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
	const float fleet = BPCapacity() * (80.f / 7.f);   // back to workertime units
	const float share = ai.GetTunable("apex_assist_share", TUNE_ASSIST_SHARE);
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
	const float st = aiEconomyMgr.metal.storage;
	if ((st <= 1.f) || (aiEconomyMgr.metal.income <= aiEconomyMgr.metal.pull))
		return 1.f;
	// A high bank is the integral of underpricing: forgiveness ramps in
	// from HALF-full (watched: 3,700 banked while outnumbered -- "we
	// certainly could afford it").
	const float frac = aiEconomyMgr.metal.current / st;
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
	float buildSec = Catalog::BuildSecondsAt(defId, EffBP(builderBP));
	// METAL FEEDS THE LATHE (apexearth: a fusion started before the mohos
	// runs at quarter feed and takes 4x longer -- "the math is bad"). A
	// build's real duration is floored by what income + the bank can pay:
	// this is what re-orders fusion AFTER the mexups, with no sequencing
	// rule anywhere -- the upgrades finish fast AND raise the feed.
	float displacedM = 0.f;
	{
		const float mInc = aiEconomyMgr.metal.income;
		const float mBank = aiEconomyMgr.metal.current;
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
				if ((share > 0.f) && (Catalog::gExtractsM[defId] <= 0.f))
					displacedM = DisplacedStreamM() * dur * share;
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
	w.gain = gain;
	w.buildSec = buildSec;
	// The E bill at what it actually forgoes (duration-priced, forgiven in
	// overflow) -- pricing it at the spot spike structurally banned every
	// big-E build (advsol, fusion) exactly when they were wanted.
	// The SPACE bill: ground is finite; footprint is paid per cell. MODEL:
	// a flat metal-per-cell price (apex_space_m) until base-crowding senses
	// price it dynamically. This is what makes dense energy (advsol) beat a
	// field of solars at equal payback.
	w.mCost = Catalog::gCostM[defId] * MCostScale()
			+ Catalog::gCostE[defId] * EPriceCostAt(buildSec, Catalog::gCostE[defId])
			+ float(Catalog::gAreaCells[defId])
				* ai.GetTunable("apex_space_m", TUNE_SPACE_M);
	w.tCost = walkSec * WalkRate(builderBP) + buildSec * Wage() + displacedM
			+ riskM;   // the builder's expected loss on the trip, see TripRisk
	// THE INCOME THE WALK ITSELF FORGOES (apexearth: "the cost in that walk
	// sec is ALSO the amount of metal you'd have lost from all that walk time
	// you'd make as metal income if you had built the closer one"). Wage above
	// charges the BUILDER's idle seconds; this charges the ASSET's late start,
	// which is the far larger number for anything that yields a rate. Scales
	// with the gain, so it decides extractor siting and is noise for a nano --
	// no per-kind distance rule anywhere.
	if (lateStart)
		w.tCost += gain * walkSec;
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
		const float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
		const float k = ai.GetTunable("apex_lockup", TUNE_LOCKUP);
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
		const float projPull = aiEconomyMgr.energy.pull + wantDrain;
		const float bankRate = aiEconomyMgr.energy.current / buildSec;
		const float unfunded = projPull - aiEconomyMgr.energy.income - bankRate;
		if ((unfunded > 0.f) && (projPull > 1.f)) {
			w.tCost += buildSec * aiEconomyMgr.metal.pull * (unfunded / projPull);
		}
	}
	w.value = gain / (w.mCost + w.tCost);
	return w.value;
}


}  // namespace Market
