namespace Market {
Want@ ProposeEnergy(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
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
		const float gain = Catalog::gMakeE[d] * EPriceAt(bSec);
		ValueOf(d, gain, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_ENERGY;
			@w.def = Catalog::Def(d);
			w.pos = EcoSiteFor(unit);
		}
	}
	return w;
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
	gIncPrev = inc;
	gIncPrevAt = ai.frame;
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
	const float futureInc = aiEconomyMgr.metal.income
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
	// walk again (apexearth's call, twice). Overflow = surplus the E bank
	// cannot absorb; minus what standing converters already chew.
	const float eStore2 = aiEconomyMgr.energy.storage;
	if ((eStore2 > 1.f)
		&& (aiEconomyMgr.energy.current < 0.85f * eStore2))
		return w;
	float standingCap = 0.f;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		if (gOwnCount[cd] > 0)
			standingCap += float(gOwnCount[cd]) * Catalog::gConvCapacity[int(cd)];
	}
	const float eSurplus = gESurplusEma - standingCap;
	if (eSurplus <= 1.f)
		return w;
	const int uid = int(unit.circuitDef.id);
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
		ValueOf(d, chew * Catalog::gConvRatio[d], 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_CONVERT;
			@w.def = Catalog::Def(d);
			w.pos = EcoSiteFor(unit);
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
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gStoreM[d] <= Catalog::gCostM[d])
			continue;
		const float capture = fill * Catalog::gStoreM[d] / ((horizon > 1.f) ? horizon : 60.f);
		Want c;
		ValueOf(d, (over < capture) ? over : capture, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_STORE;
			@w.def = Catalog::Def(d);
			w.pos = EcoSiteFor(unit);
		}
	}
	return w;
}


}  // namespace Market
