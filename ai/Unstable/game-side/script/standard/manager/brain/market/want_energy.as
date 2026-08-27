namespace Market {
Want@ ProposeEnergy(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 eSite = EcoSiteFor(unit);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gMakeE[d] <= 1.f)
			continue;
		if (Catalog::gNeedGeo[d])
			continue;   // vents are the geo want's ground, not free placement
		Want c;
		const float bSec = Catalog::BuildSecondsAt(d, EffBP(Catalog::gBuildPower[uid]));
		float gain = Catalog::gMakeE[d] * EPriceAt(bSec);
		// ECO COMPOUNDS, AND ENERGY IS ECO (apexearth: "we are not properly
		// multiplying the benefits of a strong eco... the more we boost eco the
		// more all of our other metrics get boosted"). Decays with wealth on
		// its own, so it stops mattering once we are rich.
		// ONE CURRENCY, ONE DENOMINATOR. Measured against ENERGY income alone
		// this premium saturated: a fusion roughly doubles energy income and
		// so took the full 9x, while a moho adding 5 m/s onto 40 m/s of metal
		// took 1.6x out of the identical formula. That gap was an artefact of
		// the two economies' granularity, not a fact about the game
		// (apexearth: "all our T2 cons are going for a fusion before making
		// any T2 mexes... T2 mex is much faster, and quadruples the mex value.
		// The math MUST reflect this"). Both sides now ask one question --
		// what share of TOTAL economic power does this add -- with energy
		// carried at what a converter would actually pay for it.
		{
			const float mkM = Catalog::gMakeE[d] * BestConvRatio();
			const float base = EcoPowerM();
			gain *= 1.f + ai.GetTunable("apex_energy_growth", TUNE_ENERGY_GROWTH)
					* mkM / ((base > mkM) ? base : ((mkM > 0.f) ? mkM : 1.f));
		}
		// A DEFERRED PURCHASE IS WORTH ONLY WHAT SURVIVES TO PAY IT BACK. An
		// afus is minutes of building and more of payback, and if the base
		// falls first its gain was zero -- the energy price said nothing about
		// that, which is the same hole the tech want already closed
		// (apexearth: "we keep making AFUS and its so insanely stupid. Enemy
		// walks up to us with a tzar and just completely annihilates us. one
		// damn unit and we have nothing to defend ourselves against it").
		// Scales with the build's own latency, so cheap fast generators are
		// untouched and only the long bets are discounted; and with measured
		// hazard, so it lifts by itself once the base is actually covered.
		if (ai.GetTunable("apex_eco_survival", TUNE_ECO_SURVIVAL) > 0.f)
			gain *= TechSurvival(d, Catalog::gBuildPower[uid]);
		// INFERIOR WORK IS WORTH LESS, IT IS NOT FORBIDDEN. The same build
		// power spent through a constructor that CAN build the better
		// generator returns more energy per metal, so this one's gain carries
		// the ratio. A preference, not a veto: with nobody able to do better
		// the ratio is 1, so the opening is untouched, and a worker whose only
		// option is the inferior one still takes it when nothing else competes
		// -- it just loses to assisting the better build first.
		if (ai.GetTunable("apex_inferior_discount", TUNE_INFERIOR_DISCOUNT) > 0.f) {
			const float best = OwnedBestEPerM();
			const float mine = (Catalog::gCostM[d] > 0.f)
					? (Catalog::gMakeE[d] / Catalog::gCostM[d]) : 0.f;
			if ((best > mine) && (mine > 0.f))
				gain *= mine / best;
		}
		// AND ONLY THE PART OF IT ANYTHING WOULD USE. Generation on top of an
		// already-wasted band makes no metal until a converter chews it, so its
		// gain decays across the waste line instead of being priced as though a
		// converter were free and standing. See ERealizeShare in price.as.
		gain *= ERealizeShare(Catalog::gMakeE[d], bSec);
		if (gain <= 0.f)
			continue;
		ValueOf(d, gain, WalkSecTo(unit, eSite), Catalog::gBuildPower[uid], c);
		// Rent on the defended ground this footprint would occupy.
		{
			const float rent = SpaceRentM(eSite, Catalog::gAreaCells[d]);
			if (rent > 0.f) {
				c.mCost += rent;
				c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
			}
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_ENERGY;
			@w.def = Catalog::Def(d);
			w.pos = eSite;
		}
	}
	return w;
}

// TOTAL ECONOMIC POWER, in metal/s. Metal income alone is not how big the
// economy is: what pays for buildings is metal AND the energy a converter
// would turn into metal, and reading only the metal side made every
// "how big are we" question answer near zero whenever energy ran ahead.
// Measured on a map with no metal spots at all: 183 e/s of income, 46k
// energy wasted, 3 m/s of metal, BPGap pinned at zero, and so the factory
// want never cleared its own floor -- one builder, no factory and nothing
// built for a whole game, with the enemy AI stuck the same way. Only the
// surplus nothing already converts is counted; standing converters' output
// is inside metal.income already (apexearth: "if math is not prioritizing
// what would double or triple our total economic power, then the math is
// wrong").
float StandingConvCap()
{
	float cap = 0.f;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		if (gOwnCount[cd] > 0)
			cap += float(gOwnCount[cd]) * Catalog::gConvCapacity[int(cd)];
	}
	return cap;
}

// GROUND TRUTH FOR THE CONVERTER FLEET. BAR's own converter gadget
// (game_energy_conversion.lua) publishes the team's maker capacity and what
// they are actually chewing as team rules params, and it charges that draw as
// each maker's unit energy use -- which lands in the team's energy PULL. So
// pull is already net of standing converters, and anything reading a surplus
// must not subtract them a second time. Falls back to the catalog when the
// params are absent (a game without that gadget).
float ConvCapE()
{
	const float cap = ai.GetTeamRulesParam("mmCapacity", -1.f);
	return (cap >= 0.f) ? cap : StandingConvCap();
}

float ConvUseE()
{
	const float use = ai.GetTeamRulesParam("mmUse", -1.f);
	if ((use >= 0.f) && (ai.GetTunable("apex_e_realize", TUNE_E_REALIZE) > 0.f))
		return use;
	// No param: assume the fleet chews whatever surplus it can hold.
	const float sur = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
	const float cap = StandingConvCap();
	if (sur <= 0.f)
		return 0.f;
	return (sur < cap) ? sur : cap;
}

// Converter capacity ORDERED and not yet standing: not in pull, not in the
// rules params, and the only reason a second converter want should read a
// smaller surplus than the first.
float ConvCapInFlight()
{
	float cap = 0.f;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null))
			continue;
		cap += Catalog::gConvCapacity[int(t.buildDef.id)];
	}
	return cap;
}

// ENERGY WE HAVE ALREADY ORDERED AND ARE NOT YET DRAWING. energy.pull is what
// the fleet draws NOW, so the bill for work already committed is invisible
// until its frames are placed -- which is why the first energy want cannot
// price above the converter floor until the stall it should have prevented has
// already arrived (measured: first energy decision 73 seconds in, with pull
// already 2.5x income at two minutes). Same shape as ConvCapInFlight above:
// live requests, remaining cost over remaining time.
float EDrainInFlight()
{
	if (ai.GetTunable("apex_e_committed", TUNE_E_COMMITTED) <= 0.f)
		return 0.f;
	float e = 0.f;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null))
			continue;
		const int d = int(t.buildDef.id);
		if (Catalog::gCostE[d] <= 1.f)
			continue;
		float left = 1.f - Requests::Progress(t);
		if (left <= 0.f)
			continue;
		if (left > 1.f)
			left = 1.f;
		const float sec = Catalog::BuildSecondsAt(d, EffBP(0.f));
		if (sec > 1.f)
			e += Catalog::gCostE[d] * left / sec;
	}
	return e;
}

// Best metal-per-energy any converter we could actually build reaches.
float gBestConvRatio = -1.f;
float BestConvRatio()
{
	// NEVER CACHE A ZERO. Catalog::gAvailable is frame-dependent (the DLL's
	// IsAvailable(frame)), so a first call before converters unlock would latch
	// 0 forever -- and with it EcoPowerM collapses to metal income and the whole
	// no-mex-map fix goes inert. It did exactly that once the growth premium
	// started calling this from the first election onward.
	if (gBestConvRatio > 0.f)
		return gBestConvRatio;
	gBestConvRatio = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gAvailable[d] && (Catalog::gConvCapacity[d] > 0.f)
			&& (Catalog::gConvRatio[d] > gBestConvRatio))
			gBestConvRatio = Catalog::gConvRatio[d];
	}
	return gBestConvRatio;
}

float EcoPowerM()
{
	TrackEPull();
	// ALL the energy we make, not just the part we are wasting (apexearth:
	// "it's not just the converter from T2 that matters, it's the units, the
	// energy, many things"). Every unit and every building costs energy as
	// well as metal, so energy the economy is usefully SPENDING is economic
	// power too -- counting only the surplus said an economy running hot on
	// energy had no energy value at all, which is backwards. What standing
	// converters chew is subtracted because their metal output is already
	// inside metal.income; the rest is carried at the conversion anchor, the
	// game's own exchange rate and the floor price of energy everywhere else
	// in this market.
	float p = aiEconomyMgr.metal.income;
	// Subtract what converters ACTUALLY chew, not their nameplate capacity.
	// Converters run on surplus and idle when energy is tight, so subtracting
	// full capacity erased real energy income -- with capacity above income it
	// valued all of our energy at zero, which is the opposite of the intent.
	// The gadget publishes the draw itself; the surplus-vs-capacity estimate
	// under it is the fallback (ConvUseE).
	const float chewed = ConvUseE();
	// And at a rate we can actually REALIZE: the game's best converter is no
	// use if nothing we own can place it.
	const float own = OwnConvCeil();
	const float rate = (own > 0.f) ? own : BestConvRatio();
	const float eNet = aiEconomyMgr.energy.income - chewed;
	if (eNet > 0.f)
		p += eNet * rate;
	return p;
}

// WHAT TIER UNLOCKS ON THE ENERGY SIDE. The tech want's whole demand is
// UpDemand -- the mex-upgrade stream -- so on a map with no metal spots it is
// identically zero and ProposeTech returns before pricing anything. No T2 lab
// is ever proposed, which means no advanced converter and no AFUS, and the
// economy has no way to grow at all (apexearth: "T1 lab -> t1 con -> t2 lab ->
// fusion/afus + advanced converter, absolutely good right???" -- yes, and we
// could not express it).
//
// Same shape as UpDemand, in the same currency: the extra metal per second a
// better conversion ratio would make from the energy we already have. Zero
// once we own the best converter in the game, exactly like the upgrade stream
// goes to zero once every spot is mohoed.
float ConvRatioReach(const array<int>@ builds)
{
	float best = 0.f;
	if (builds is null)
		return best;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (Catalog::gAvailable[d] && (Catalog::gConvCapacity[d] > 0.f)
			&& (Catalog::gConvRatio[d] > best))
			best = Catalog::gConvRatio[d];
	}
	return best;
}

// The best ratio anything we already own can place.
float OwnConvCeil()
{
	float best = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		const float r = ConvRatioReach(Catalog::gBuildsList[di]);
		if (r > best)
			best = r;
	}
	return best;
}

// Energy nothing is already converting -- what a better ratio would act on.
float ConvertibleE()
{
	const float e = aiEconomyMgr.energy.income - StandingConvCap();
	return (e > 0.f) ? e : 0.f;
}

float ConvUpDemand()
{
	const float gapR = BestConvRatio() - OwnConvCeil();
	if (gapR <= 0.f)
		return 0.f;
	return ConvertibleE() * gapR;
}

// The BP closed loop: the fleet's standing lathe capacity vs what income
// can feed. Idle builders do not PULL, so "overflow" reads high exactly
// when parked BP is the problem -- capacity is the honest measure
// (measured: 18 assist bots bought against overflow their own idleness
// sustained).
float BPCapacity()
{
	float cap = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		if (Catalog::gBuildPower[int(d)] <= 0.f)
			continue;
		float unitCap = float(gOwnCount[d]) * Catalog::gBuildPower[int(d)] * (7.f / 80.f);
		// A walking con is not a lathe: mobile BP spends much of its life in
		// transit, so it counts at a discount -- full-weight counting read
		// 40 road-bound cons as 280 m/s of build power and starved the nano
		// farm while metal overflowed (apexearth: "the solution is nano
		// turrets").
		if (Catalog::gMobile[int(d)])
			unitCap *= ai.GetTunable("apex_mobile_bp_eff", TUNE_MOBILE_BP_EFF);
		cap += unitCap;
	}
	return cap;
}

// Smoothed income growth rate, m/s per second -- the compounding signal.
float gIncPrev = -1.f;
int gIncPrevAt = 0;
float gIncGrowth = 0.f;
float gIncEma = -1.f;
float gMSpareEma = 0.f;
void TrackIncome()
{
	if (ai.frame < gIncPrevAt + 10 * SECOND)
		return;
	const float inc = aiEconomyMgr.metal.income;
	// Structural income: a reclaim burst is a spike, not a standard of
	// living -- labs must not be licensed off it (apexearth).
	gIncEma = (gIncEma < 0.f) ? inc : (0.85f * gIncEma + 0.15f * inc);
	if (gIncPrev >= 0.f) {
		const float dt = float(ai.frame - gIncPrevAt) / float(SECOND);
		const float g = (inc - gIncPrev) / ((dt > 1.f) ? dt : 1.f);
		gIncGrowth = 0.7f * gIncGrowth + 0.3f * g;
	}
	// Metal nothing is already spending, smoothed. Raw pull dips to nothing
	// whenever the fleet is between jobs, so an instantaneous read calls a
	// fully committed economy idle one tick and starving the next -- the same
	// trap TrackEPull documents on the energy side.
	const float sur = inc - aiEconomyMgr.metal.pull;
	gMSpareEma = 0.85f * gMSpareEma + 0.15f * ((sur > 0.f) ? sur : 0.f);
	gIncPrev = inc;
	gIncPrevAt = ai.frame;
}

// The metal rate a NEW consumer could actually be fed at: what nothing is
// spending, plus what we are already throwing away.
float SpareMetalRate()
{
	return gMSpareEma + OverflowM();
}

// Lathe capacity still worth buying: income x headroom minus the fleet --
// plus the income the compounding economy will have within the lookahead
// (apexearth 2026-08-23: idle cons were "not valuing the forward-looking
// compounding effect" of standing build power).
// WORK WE HAVE COMMITTED TO AND NOT BUILT, in metal. Live requests priced at
// what is left of them, so a queue of unstarted frames reads as demand for
// hands rather than as nothing at all.
float BacklogM()
{
	float m = 0.f;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null))
			continue;
		const float left = 1.f - Requests::Progress(t);
		if (left <= 0.f)
			continue;
		m += Catalog::gCostM[int(t.buildDef.id)] * left;
	}
	return m;
}

float BPGap()
{
	TrackIncome();
	const float head = ai.GetTunable("apex_bp_headroom", TUNE_BP_HEADROOM);
	const float ahead = ai.GetTunable("apex_bp_lookahead", TUNE_BP_LOOKAHEAD);
	const float futureInc = EcoPowerM()
			+ ((gIncGrowth > 0.f) ? gIncGrowth * ahead : 0.f);
	float gap = futureInc * ((head > 0.f) ? head : 1.15f) - BPCapacity();
	// A bank climbing past half storage is deferred spend the standing
	// lathe already failed to serve (measured: 9.4k banked at 234 m/s
	// income with ~30 nanos - the income target alone reads "satisfied"
	// exactly when the backlog is worst).
	const float bank = aiEconomyMgr.metal.current;
	const float st2 = aiEconomyMgr.metal.storage;
	if ((st2 > 1.f) && (bank > 0.5f * st2))
		gap += (bank - 0.5f * st2) / 60.f;
	// AND THE WORK ALREADY ORDERED. Income headroom alone cannot see a queue:
	// order fifteen turrets and this number does not move, so the turrets come
	// out of expansion's hands instead of buying their own (apexearth: "we'll
	// need some more constructors built... ideally the brain is in charge of
	// detecting whether or not we have a proper balance"). Same horizon as the
	// bank clause above, and distinct from it -- bank is metal nothing spent,
	// backlog is work nothing built. Self-limiting: BPCapacity is subtracted
	// above, so the gap closes as the hands arrive.
	const float bl = ai.GetTunable("apex_bp_backlog_s", TUNE_BP_BACKLOG_S);
	if (bl > 1.f)
		gap += BacklogM() / bl;
	return (gap > 0.f) ? gap : 0.f;
}

// Metal income nothing is spending: the arithmetic case for more build
// capacity. A new builder's return includes the overflow it would capture --
// this is the closed-loop build-power term, not a model.
float OverflowM()
{
	const float over = aiEconomyMgr.metal.income - aiEconomyMgr.metal.pull;
	if (over <= 0.f)
		return 0.f;
	// Only real once the bank is filling; a draining bank absorbs the gap.
	const float st = aiEconomyMgr.metal.storage;
	if ((st > 1.f) && (aiEconomyMgr.metal.current < 0.8f * st))
		return 0.f;
	return over;
}

// Converters: worth exactly the energy surplus they would chew, at their own
// ratio. Pure catalog arithmetic, no model.
Want@ ProposeConvert(CCircuitUnit@ unit)
{
	Want w;
	TrackEPull();
	// Converters recycle OVERFLOW only: the conversion ratio IS the energy
	// floor price, so converting non-overflowing E is value-neutral by our
	// own definitions -- a converter never outbids a slightly-longer mex
	// walk again (apexearth's call, twice). Overflow = the surplus the E bank
	// cannot absorb.
	const float eStore2 = aiEconomyMgr.energy.storage;
	if ((eStore2 > 1.f)
		&& (aiEconomyMgr.energy.current < 0.85f * eStore2))
		return w;
	// Energy pull ALREADY carries what standing converters draw (see ConvCapE
	// above), so the surplus EMA is net of them; subtracting their capacity a
	// second time hid a saturated fleet's remaining waste entirely and is why
	// capacity stopped growing while energy overflowed. What is NOT in pull is
	// the capacity we have already ordered.
	const bool realize = ai.GetTunable("apex_e_realize", TUNE_E_REALIZE) > 0.f;
	const float eSurplus = realize
			? (gESurplusEma - ConvCapInFlight())
			: (gESurplusEma - StandingConvCap());
	if (eSurplus <= 1.f)
		return w;
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 cSite = EcoSiteFor(unit);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gConvCapacity[d] <= 0.f)
			continue;
		const float chew = (eSurplus < Catalog::gConvCapacity[d])
				? eSurplus : Catalog::gConvCapacity[d];
		Want c;
		// THE SAME ECO-COMPOUNDING PREMIUM THE GENERATOR GETS. A generator is
		// priced as though its energy were already metal and then multiplied by
		// what that adds to total economic power; the converter that actually
		// makes that metal was the only half of the pair paying flat, so the
		// pair could never be bought in the order that realizes it.
		float cGain = chew * Catalog::gConvRatio[d];
		if (realize) {
			const float base = EcoPowerM();
			cGain *= 1.f + ai.GetTunable("apex_energy_growth", TUNE_ENERGY_GROWTH)
					* cGain / ((base > cGain) ? base : ((cGain > 0.f) ? cGain : 1.f));
		}
		ValueOf(d, cGain, WalkSecTo(unit, cSite),
				Catalog::gBuildPower[uid], c);
		// SPACE IS WHAT THE ADVANCED CONVERTER BUYS. Ratio alone says T1 is
		// nearly as good and far cheaper; what T2 actually buys is ten times
		// the throughput behind the same guns, and a body that does not die to
		// one hit (apexearth). The rent prices the first; the second is the
		// stream's own survival, which cover already raises.
		{
			const float rent = SpaceRentM(cSite, Catalog::gAreaCells[d]);
			if (rent > 0.f) {
				c.mCost += rent;
				c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
			}
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_CONVERT;
			@w.def = Catalog::Def(d);
			w.pos = cSite;
		}
	}
	return w;
}

// Storage. MODEL: a store captures overflow up to its volume spread over a
// horizon (apex_store_horizon seconds) -- overflow beyond a full bank is
// lost forever, so the store's return is the loss it absorbs while spending
// catches up. Only defs whose storage dominates their cost propose here;
// incidental storage on other defs is not double-counted.
Want@ ProposeStore(CCircuitUnit@ unit)
{
	Want w;
	// Storage exists ONLY to enable a planned expensive reclaim that will
	// not fit in current headroom (apexearth 2026-08-23, final form: "not
	// important unless we're about to reclaim something expensive"). No
	// overflow purchases, no stock target.
	if ((gReclaimTarget is null) || (gReclaimTarget.circuitDef is null))
		return w;
	const float refund = Catalog::gCostM[int(gReclaimTarget.circuitDef.id)];
	const float headroom = aiEconomyMgr.metal.storage - aiEconomyMgr.metal.current;
	if (refund <= headroom)
		return w;
	const float horizon = ai.GetTunable("apex_store_horizon", TUNE_STORE_HORIZON);
	const float fill = 1.f;
	const float over = (refund - headroom) / ((horizon > 1.f) ? horizon : 60.f);
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 sSite = EcoSiteFor(unit);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gStoreM[d] <= Catalog::gCostM[d])
			continue;
		const float capture = fill * Catalog::gStoreM[d] / ((horizon > 1.f) ? horizon : 60.f);
		Want c;
		ValueOf(d, (over < capture) ? over : capture, WalkSecTo(unit, sSite),
				Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_STORE;
			@w.def = Catalog::Def(d);
			w.pos = sSite;
		}
	}
	return w;
}


}  // namespace Market
