namespace Market {
//------------------------------------------------------------------------------
// THE ETA OBJECTIVE, ECONOMY-ONLY (docs/23-the-plan.md, the `eta-objective`
// skill).
//
// The market prices ONE STEP: gain per metal-second, compared now. A per-instant
// price cannot say "worse this minute, sooner to the goal", which is the whole
// difference between ranking options and reaching a target. This file names a
// TARGET -- a level of economic power -- and answers the plan's question
// instead: which first move reaches it soonest.
//
// The ladder is the entire model. Growth investments are sorted by PAYBACK, and
// the ladder takes the shortest-payback growth still standing until the target
// is reached. Mexes before tech, upgrades after tech, and the switch to reactors
// once the ground is claimed are consequences of the pool EMPTYING; there is no
// ordering rule, no threshold and no cap anywhere in this file.
//------------------------------------------------------------------------------

// Reach this multiple of today's economic power. A target has to be far enough
// away that a long build's delay is felt and near enough that the ladder still
// terminates: 4x is about one era of this game, an opening economy to a mid one.
const float ETA_TARGET_MUL = 4.f;
const int   ETA_MAX_STEPS = 64;
const float ETA_BIG = 1.0e9f;
// The generator tail is inexhaustible, so it is closed in geometric chunks
// rather than one panel at a time -- each chunk grows the economy by this much.
// (A closed form would want a logarithm, which this AngelScript has no binding
// for.) At 4x the target this converges in about seven chunks.
const float ETA_CHUNK = 0.25f;
const int   ETA_INF_N = 1000000;

// One rung of the growth ladder: a thing we could build, what it costs, what it
// adds to economic power, and how many of them the map still has in it.
class Pool {
	array<int> def;
	array<float> cost;
	array<float> gain;
	array<int> n;
	array<bool> mob;   // only MOBILE hands can build it: a spot is where it is
	array<float> costE;   // its energy bill: a rung is fed in BOTH currencies
	array<float> makeE;   // and what it adds to the energy feed once it stands
}

Pool@ gPoolNow;
Pool@ gPoolTech;
int gPoolAt = -999999;

float ConvRate()
{
	const float own = OwnConvCeil();
	return (own > 0.f) ? own : BestConvRatio();
}

// Sorted insert by payback. Feed-bound steps have rate dI*P/cost, so ranking by
// cost/dI is EXACT and P-independent while metal is the binding constraint --
// which is what lets the ladder walk the pool in order instead of re-scanning it
// at every step.
// Metal per energy at the feeds as they stand: the pool is ordered by payback
// in both currencies, so a rung's energy bill counts at what it costs to feed.
// Metal alone put a 5,000 E advanced solar ahead of a zero-E solar with the
// bank full and every lathe energy-throttled.
float gPoolMPerE = 0.f;
float PoolEq(float cost, float costE)
{
	return cost + costE * gPoolMPerE;
}

void PoolInsert(Pool@ p, int d, float cost, float gain, int n, bool mob)
{
	if ((p is null) || (cost <= 1.f) || (gain <= 0.0001f) || (n <= 0))
		return;
	const float pb = PoolEq(cost, Catalog::gCostE[d]) / gain;
	uint at = 0;
	while ((at < p.def.length()) && ((PoolEq(p.cost[at], p.costE[at]) / p.gain[at]) <= pb))
		++at;
	p.def.insertAt(at, d);
	p.cost.insertAt(at, cost);
	p.gain.insertAt(at, gain);
	p.n.insertAt(at, n);
	p.mob.insertAt(at, mob);
	p.costE.insertAt(at, Catalog::gCostE[d]);
	p.makeE.insertAt(at, Catalog::gMakeE[d]);
}

// anyTier ignores who can build it: that is the world AFTER an advanced plant,
// and comparing the two pools is how "is T2 worth it yet" gets answered by
// arithmetic instead of by a bar.
int BestExtractDef(bool anyTier)
{
	int best = 0;
	float bx = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= 0.f))
			continue;
		if (!anyTier && !CanBuildEver(d))
			continue;
		if (Catalog::gExtractsM[d] > bx) {
			bx = Catalog::gExtractsM[d];
			best = d;
		}
	}
	return best;
}

int ClaimExtractDef(bool anyTier)
{
	int best = 0;
	float bc = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= 0.f))
			continue;
		if (!anyTier && !CanBuildEver(d))
			continue;
		const float c = Catalog::gCostM[d];
		if ((c > 1.f) && ((best == 0) || (c < bc))) {
			bc = c;
			best = d;
		}
	}
	return best;
}

void PoolFill(Pool@ p, bool anyTier)
{
	if (p is null)
		return;
	p.def.resize(0);
	p.cost.resize(0);
	p.gain.resize(0);
	p.n.resize(0);
	p.mob.resize(0);
	p.costE.resize(0);
	p.makeE.resize(0);
	{
		const float pm = EcoPowerM();
		const float ea = EtaEnergyAvail();
		gPoolMPerE = ((pm > 0.5f) && (ea > 1.f)) ? (pm / ea) : 0.f;
	}
	const float rate = ConvRate();
	const float im = IncomeMult();

	// OPEN GROUND. Priced at the last probed spot yield; per-spot yields differ
	// and this carries the average, which is the model's coarsest term.
	CacheSpots();
	const int open = int(gAllSpots.length()) - int(gLSpot.length());
	const int claimDef = ClaimExtractDef(anyTier);
	if ((open > 0) && (claimDef > 0))
		PoolInsert(p, claimDef, Catalog::gCostM[claimDef], SpotM(), open, true);

	// HELD GROUND: the upgrade each standing extractor still has left in it.
	const int upDef = BestExtractDef(anyTier);
	if (upDef > 0) {
		for (uint i = 0; i < gLSpot.length(); ++i) {
			if (gLExtract[i] <= 0.f)
				continue;
			const float dI = gLIncome[i] * im
					* (Catalog::gExtractsM[upDef] - gLExtract[i]);
			if (dI > 0.f)
				PoolInsert(p, upDef, Catalog::gCostM[upDef], dI, 1, true);
		}
	}

	// THE TAIL: generation, which nothing exhausts. Energy is carried at the
	// conversion anchor, the same rate EcoPowerM values it at -- so a converter
	// is power-neutral here by construction and is not a growth rung.
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d])
			continue;
		if (!anyTier && !CanBuildEver(d))
			continue;
		if (Catalog::gNeedGeo[d])
			continue;   // vent-limited, so not a free tail
		float dI = Catalog::gMakeM[d];
		if (Catalog::gMakeE[d] > 0.f)
			dI += Catalog::gMakeE[d] * rate;
		if (dI <= 0.f)
			continue;
		PoolInsert(p, d, Catalog::gCostM[d], dI, ETA_INF_N, false);
	}
}

void PoolRefresh()
{
	if ((gPoolNow !is null) && (ai.frame - gPoolAt < 5 * SECOND))
		return;
	gPoolAt = ai.frame;
	if (gPoolNow is null) {
		Pool a;
		Pool b;
		@gPoolNow = a;
		@gPoolTech = b;
	}
	PoolFill(gPoolNow, false);
	PoolFill(gPoolTech, true);
}

// METAL FEEDS THE LATHE: a step takes the longer of what the fleet can build and
// what the economy can pay for. This is the plan's max() term, per rung.
// ...and the plan's max() has a THIRD arm: the energy bill over the energy
// that can feed it. A T2 lab is 15,000 E; at 300 e/s of income and a pull to
// match, it stood 5.6 minutes after its frame in the canon game while his,
// on 1,200 e/s, stood in one. Without this arm the ladder could not see that
// a solar shortens the lab.
float StepSec(int d, float cost, float P, float bank, float bp, float eAvail)
{
	float bt = Catalog::BuildSecondsAt(d, bp);
	if (bt < 0.1f)
		bt = 0.1f;
	float need = cost - bank;
	if (need < 0.f)
		need = 0.f;
	float feed = (P > 0.01f) ? (need / P) : ETA_BIG;
	const float costE = Catalog::gCostE[d];
	if (costE > 0.f) {
		const float feedE = costE / ((eAvail > 1.f) ? eAvail : 1.f);
		if (feedE > feed)
			feed = feedE;
	}
	return (feed > bt) ? feed : bt;
}

// What feeds an energy bill: the whole income, as the metal arm reads the
// whole metal income -- the ladder displaces today's spending on both sides.
// Netting the pull off read ~1 e/s under any build and priced a lab at its
// energy cost in seconds.
float EtaEnergyAvail()
{
	float e = aiEconomyMgr.energy.income + EMakeInFlight();
	if (e < 0.f)
		e = 0.f;
	const float look = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
	e += aiEconomyMgr.energy.current / ((look > 1.f) ? look : 30.f);
	return (e > 1.f) ? e : 1.f;
}

// The share of the fleet's lathe that can walk to a spot. A nano turret adds
// build power the claim and upgrade rungs cannot use, and crediting it to
// them bought 14 nano turrets in the first twelve minutes of a 172-spot map
// while six constructors held the whole claim ladder (Carrot, 2026-09-08).
float MobileBPShare()
{
	float mobile = 0.f;
	float all = 0.f;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		const int d = int(c);
		if ((gOwnCount[c] <= 0) || !Catalog::gBuilder[d] || (Catalog::gBuildPower[d] <= 0.f))
			continue;
		if (!Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0))
			continue;   // a factory
		const float bpd = float(gOwnCount[c]) * Catalog::gBuildPower[d];
		all += bpd;
		if (Catalog::gMobile[d])
			mobile += bpd;
	}
	return (all > 0.f) ? (mobile / all) : 1.f;
}

float LadderRun(Pool@ p, float P, float bank, float bp, float bpMob, float eAvail, float target, int consumed)
{
	if (p is null)
		return ETA_BIG;
	array<int> n = p.n;   // the ladder eats this copy, not the cached pool
	if (consumed > 0) {
		for (uint c = 0; c < n.length(); ++c) {
			if ((p.def[c] == consumed) && (n[c] > 0) && (n[c] < ETA_INF_N)) {
				n[c] -= 1;
				break;
			}
		}
	}
	float t = 0.f;
	uint i = 0;
	int steps = 0;
	// EVERY RUNG IS WALKED TO. The first move charges its own walk; the rest of
	// the ladder arrived free, so ten winds and one advanced solar read as the
	// same time and the ladder preferred the winds (measured: 179 of 386
	// disagreements with the market were advsol -> wind). The fleet's own
	// measured wait from committing to breaking ground, spread across the hands
	// that walk in parallel -- the same way build time is already spread across
	// the fleet's lathe.
	const float lat = RungWalkS();
	// RUNGS ARE TAKEN IN BATCHES, not one at a time. A step budget spent one
	// solar or one claim at a time cannot reach a target that scales with the
	// economy: measured at P=63.6 against a target of 254.4, the walk ran out of
	// steps among the open claims and returned "unreachable", which silently
	// switched the whole objective off exactly when the economy got big. Each
	// batch is sized to grow the economy by ETA_CHUNK, so the work is bounded
	// whatever the pool holds. Priced at the batch's STARTING power, which
	// understates the speedup within a batch and so overestimates time -- the
	// conservative direction.
	while ((P < target) && (steps < ETA_MAX_STEPS)) {
		while ((i < n.length()) && (n[i] <= 0))
			++i;
		if (i >= n.length())
			return ETA_BIG;   // nothing left on the board that grows
		const float g = p.gain[i];
		float want = P * ETA_CHUNK;
		if (P + want > target)
			want = target - P;
		int k = int(want / g) + 1;
		if (k > n[i])
			k = n[i];
		t += float(k) * (StepSec(p.def[i], p.cost[i], P, bank, p.mob[i] ? bpMob : bp, eAvail) + lat);
		bank = 0.f;
		P += float(k) * g;
		eAvail += float(k) * p.makeE[i];
		n[i] -= k;
		++steps;
	}
	return (P >= target) ? t : ETA_BIG;
}

float RungWalkS()
{
	const int workers = int(aiBuilderMgr.GetWorkerCount());
	return Requests::StartLatencyS() / float((workers < 1) ? 1 : workers);
}

// Seconds to the target if we start by building def d (0 = follow the ladder as
// it stands). addBP is how a lathe helps: it buys HANDS, not income, and shows
// its value only where the ladder is build-bound rather than feed-bound.
float EtaWith(int d, float gainM, float addBP, bool tech)
{
	return EtaWithN(d, gainM, addBP, tech, 1);
}

// The first move taken k times over. A single wind against a single advanced
// solar is not a comparison: the ladder's cheap rungs make up the difference in
// power at almost no cost, so the smaller first step always won on step cost
// alone and the economy was told to build winds. Candidates are compared at the
// ladder's own batch size -- enough of each to grow the economy by ETA_CHUNK --
// so twenty winds pay twenty walks, twenty cells and twenty energy bills
// against one advanced solar's (apexearth: "concentrated efforts on advsol
// might look even better").
float EtaWithN(int d, float gainM, float addBP, bool tech, int k)
{
	PoolRefresh();
	float P = EcoPowerM();
	if (P < 0.5f)
		P = 0.5f;
	const float target = P * ETA_TARGET_MUL;
	float bank = aiEconomyMgr.metal.current;
	float bp = EffBP(0.f);
	if (bp < 1.f)
		bp = 1.f;
	float bpMob = bp * MobileBPShare();
	if (bpMob < 1.f)
		bpMob = 1.f;
	float eAvail = EtaEnergyAvail();
	float t = 0.f;
	if (d > 0) {
		if (k < 1)
			k = 1;
		const float lat = RungWalkS();
		// A PLAN THAT DIES BEFORE IT PAYS ARRIVES LATER, NOT NEVER: what is lost
		// is rebuilt, so a first move that survives its own build with
		// probability s costs 1/s of its time in expectation. TechSurvival is
		// that s, from the measured hazard at home over the build's latency and
		// pay time. Without it the ladder on Greenest Fields put the advanced
		// fusion 200 s ahead of the fusion and watched it die half-built.
		float surv = TechSurvival(d, bp);
		if (surv < 0.05f)
			surv = 0.05f;
		for (int u = 0; u < k; ++u) {
			t += StepSec(d, Catalog::gCostM[d], P, bank, (Catalog::gExtractsM[d] > 0.f) ? bpMob : bp, eAvail) / surv;
			if (u > 0)
				t += lat;   // the first unit's walk is the asker's own, charged by the caller
			bank = 0.f;
			if (gainM > 0.f)
				P += gainM;
			if (addBP > 0.f)
				bp += addBP;
			if (Catalog::gMakeE[d] > 0.f)
				eAvail += Catalog::gMakeE[d];
		}
	}
	return t + LadderRun(tech ? gPoolTech : gPoolNow, P, bank, bp, bpMob, eAvail, target, d);
}

// How many of def d make one of the ladder's batches from power P.
int EtaBatchN(float gainM, float P)
{
	if (gainM <= 0.0001f)
		return 1;
	const int k = int(P * ETA_CHUNK / gainM) + 1;
	return (k < 1) ? 1 : k;
}

// HOW MUCH OF THE NEXT STEP IS WAITING FOR HANDS. 1: the next rung is
// build-bound (more lathe shortens it); 0: it is fed-bound (more lathe
// changes nothing). Sizes constructors and nano turrets by the ladder
// instead of by unspent metal, which bought 470 constructors in twenty
// minutes of the economy-only canon (2026-09-08).
int gHandsLogAt = 0;
float EtaHandsShare()
{
	PoolRefresh();
	Pool@ p = gPoolNow;
	if (p is null)
		return 1.f;
	float P = EcoPowerM();
	if (P < 0.5f)
		P = 0.5f;
	float bp = EffBP(0.f);
	if (bp < 1.f)
		bp = 1.f;
	const float bpMob = (bp * MobileBPShare() > 1.f) ? (bp * MobileBPShare()) : 1.f;
	// The WHOLE walk to the target, not one rung: at 700 m/s a 26-metal mex is
	// fed in 0.04 s and no fleet lathes it faster, so rung by rung every step
	// read as hands-bound and the factories never stopped (209 air cons).
	// Summed, the lathe time and the feed time over the same batches say
	// which of the two the target is actually waiting on.
	const float target = P * ETA_TARGET_MUL;
	float eAvail = EtaEnergyAvail();
	const float lat = RungWalkS();
	float tBuild = 0.f;
	float tFeed = 0.f;
	uint i = 0;
	int steps = 0;
	array<int> n = p.n;
	while ((P < target) && (steps < ETA_MAX_STEPS)) {
		while ((i < n.length()) && (n[i] <= 0))
			++i;
		if (i >= n.length())
			break;
		const float g = p.gain[i];
		float want = P * ETA_CHUNK;
		if (P + want > target)
			want = target - P;
		int k = int(want / g) + 1;
		if (k > n[i])
			k = n[i];
		float bt = Catalog::BuildSecondsAt(p.def[i], p.mob[i] ? bpMob : bp);
		if (bt < 0.1f)
			bt = 0.1f;
		tBuild += float(k) * (bt + lat);
		tFeed += float(k) * p.cost[i] / P;
		P += float(k) * g;
		eAvail += float(k) * p.makeE[i];
		n[i] -= k;
		++steps;
	}
	if (ai.frame >= gHandsLogAt) {
		gHandsLogAt = ai.frame + 30 * SECOND;
		AiLog("apex: hands t=" + ai.teamId + " tBuild=" + int(tBuild) + " tFeed=" + int(tFeed)
			+ " bp=" + int(bp) + " bpMob=" + int(bpMob) + " P=" + int(P) + " steps=" + steps
			+ " first=" + ((p.def.length() > 0) ? Catalog::Def(p.def[0]).GetName() : "-"));
	}
	if ((tBuild <= 0.f) || (tFeed >= tBuild))
		return 0.f;
	return 1.f - tFeed / tBuild;
}

bool EtaOn()
{
	return ai.GetTunable("apex_eta", TUNE_ETA) > 0.f;
}

// OVERFLOW BUYS HANDS, NOT ARMY.
//
// This used to be EcoOnly() and it used to zero ArmyTarget outright, because
// the target named economy and nothing else. Army now has a target of its own
// -- a share of the economy we have built, ArmyTarget in army.as -- so the
// suppression is gone and what is left is the narrower statement that outlived
// it: metal we are failing to spend is a shortage of BUILD POWER, not evidence
// that we need soldiers. That is the same thing the ladder's max() says when a
// step is build-bound rather than feed-bound, and it is why the three
// production floors that dump overflow into units still ask.
//
// Army is bought against its target, at its price, like everything else.
bool OverflowBuysHands()
{
	return EtaOn();
}

// THE SHARE OF OUR INCOME NOTHING IS SPENDING.
//
// Storage-independent on purpose. OverflowM() only reports once the bank is
// past 80% of storage, which is a LATE report of a fact available immediately
// -- measured on the economy-only board, the bank pegged at its cap around
// minute 5 and the AI first "noticed" it had too few hands at minute 6, having
// already thrown away 792 metal (apexearth: "relying on storage is lazy --
// make sure spend the metal. (need more build power)").
//
// income - pull is the same fact with no buffer in the way. Smoothed because
// pull dips to nothing whenever the fleet is between jobs, so the raw tick
// reads "wasting everything" several times a minute in a perfectly busy base.
float gSlackEma = 0.f;
int gSlackAt = -999999;
float SlackFrac()
{
	if (ai.frame - gSlackAt >= SECOND) {
		gSlackAt = ai.frame;
		const float inc = aiEconomyMgr.metal.income;
		float f = 0.f;
		if (inc > 0.1f) {
			const float slack = inc - aiEconomyMgr.metal.pull;
			if (slack > 0.f)
				f = slack / inc;
		}
		if (f > 1.f)
			f = 1.f;
		gSlackEma = 0.9f * gSlackEma + 0.1f * f;
	}
	return gSlackEma;
}

// WHAT THE ETA CAN HONESTLY PRICE. Economic power is extraction plus generation,
// so those are the only first moves whose worth this objective can state. A
// factory's return is army, a converter's and a store's return is already inside
// EcoPowerM's own valuation of energy, and assist adds no def at all -- all four
// keep their market price rather than being ranked by a target that cannot see
// what they are for.
bool EtaRanks(Want@ w)
{
	if ((w is null) || (w.def is null))
		return false;
	return (w.kind == WK_MEX) || (w.kind == WK_MEXUP) || (w.kind == WK_ENERGY)
			|| (w.kind == WK_GEO) || (w.kind == WK_NANO) || (w.kind == WK_TECH);
}

// The first move's contribution to ECONOMIC POWER, read from the catalog rather
// than from the want's market gain. The two are not the same number: a market
// gain carries scarcity premiums, survival discounts and stated preferences,
// and feeding those into the ladder inflates the economy with income that will
// never arrive (measured on the first probe -- a vehicle plant's capability gain
// entered as metal/s and reached the target in 83s against a mex's 280).
float DPowerOf(Want@ w, int d)
{
	if (w.kind == WK_MEX)
		return (w.gain > 0.f) ? w.gain : SpotM();
	if (w.kind == WK_MEXUP) {
		const int li = LedgerFind(w.spotId);
		if ((li >= 0) && (gLExtract[li] > 0.f))
			return gLIncome[li] * IncomeMult()
					* (Catalog::gExtractsM[d] - gLExtract[li]);
		return 0.f;
	}
	float dI = Catalog::gMakeM[d];
	if (Catalog::gMakeE[d] > 0.f)
		dI += Catalog::gMakeE[d] * ConvRate();
	return (dI > 0.f) ? dI : 0.f;
}

// The first move is walked to: a 26-metal claim two minutes down the road is
// not a 5-second rung, and priced as one it sent every hand across the map
// while the bank sat full.
float EtaOfWant(Want@ w)
{
	if (!EtaRanks(w))
		return ETA_BIG;
	const int d = int(w.def.id);
	if (w.kind == WK_NANO)
		return w.walkSec + EtaWith(d, 0.f, Catalog::gBuildPower[d], false);
	if (w.kind == WK_TECH)
		return w.walkSec + EtaWith(d, 0.f, 0.f, true);
	return w.walkSec + EtaWith(d, DPowerOf(w, d), 0.f, false);
}

// ONE ECONOMIC QUESTION, ONE ANSWER. Extraction, generation and build power are
// three ways of buying the same thing -- a bigger economy sooner -- so they are
// one question and the ladder answers it. As four separate draw tickets they
// were sampled four times against everything else, which is the same imbalance
// the kinds-to-categories merge already fixed one level down.
//
// CAT_PRODUCE is deliberately NOT in the merge: a factory's return is army,
// which this target does not name, so plants keep their own ticket and their
// market ordering. Tech is priced and logged, but does not steer yet.
bool EtaMergedCat(int c)
{
	return (c == CAT_METAL) || (c == CAT_ENERGY) || (c == CAT_BP);
}

// THE MERGED TICKET'S WEIGHT IS THE ECONOMY'S BEST MARKET VALUE, not the value
// of whichever want the ladder chose. Taking the pick's own value made the ETA
// quietly shrink how much economy competes against defence at all -- the ladder
// often prefers a want the per-instant price rates lower, which is the entire
// point of it, and charging the economy's draw odds for that turns a better
// choice into fewer economy elections. What the ladder decides is WHICH want;
// how loudly economy speaks is not its business.
float EtaEcoWeight(array<Want@>@ ranked)
{
	if (ranked is null)
		return -1.f;
	float best = -1.f;
	for (uint i = 0; i < ranked.length(); ++i) {
		if (!EtaMergedCat(CategoryOf(ranked[i].kind)))
			continue;
		if (ranked[i].value > best)
			best = ranked[i].value;
	}
	return best;
}

// The index in `ranked` of the economy want that reaches the target soonest, or
// -1 when nothing in the merged categories can be priced.
int EtaEcoPick(array<Want@>@ ranked)
{
	if (ranked is null)
		return -1;
	int bestAt = -1;
	float bestEta = ETA_BIG;
	for (uint i = 0; i < ranked.length(); ++i) {
		if (!EtaMergedCat(CategoryOf(ranked[i].kind)) || !EtaRanks(ranked[i]))
			continue;
		const float e = EtaOfWant(ranked[i]);
		if (e < bestEta) {
			bestEta = e;
			bestAt = int(i);
		}
	}
	return bestAt;
}

// THE SHADOW READ. Runs whether or not the layer steers, so the two can be
// compared on the same game: what the market's price put first, what the ETA
// would have put first, and the two ETAs side by side.
int gEtaLogAt = 0;
void EtaLog(array<Want@>@ ranked, CCircuitUnit@ unit)
{
	// The shadow read compares two layers. With the ETA layer off
	// (apex_eta=0) there is nothing to compare against, and the ladder run
	// is ~15 ms of simulation per log line.
	if (!EtaOn() && (ai.GetTunable("apex_eta_log", TUNE_ETA_LOG) <= 0.f))
		return;
	if ((ranked is null) || (ranked.length() == 0) || (ai.frame < gEtaLogAt))
		return;
	gEtaLogAt = ai.frame + 15 * SECOND;
	PoolRefresh();
	const float P = EcoPowerM();
	int bestAt = -1;
	float bestEta = ETA_BIG;
	// The market's best answer to the SAME question. `ranked` is value-sorted,
	// so the first steerable want in it IS the market's pick; comparing against
	// ranked[0] compared the two layers on different questions (it is often a
	// turret, which this objective does not price at all).
	int mktAt = -1;
	string parts = "";
	for (uint i = 0; i < ranked.length(); ++i) {
		if (!EtaRanks(ranked[i]))
			continue;
		if ((mktAt < 0) && EtaMergedCat(CategoryOf(ranked[i].kind)))
			mktAt = int(i);
		const float e = EtaOfWant(ranked[i]);
		if (e < bestEta) {
			bestEta = e;
			bestAt = int(i);
		}
		if (e < ETA_BIG) {
			parts += " " + KindName(ranked[i].kind) + ":"
				+ ranked[i].def.GetName() + "="
				+ formatFloat(e, "", 0, 0);
		}
	}
	// How much cheap growth the map still owes us -- the quantity that ends a
	// regime in the plan, and the one a threshold used to stand in for.
	const float cheap = ServableUpDemand() + OpenSpotStream();
	AiLog(Factory::T() + "apex: eta t=" + ai.teamId
		+ " P=" + formatFloat(P, "", 0, 1)
		+ " tgt=" + formatFloat(P * ETA_TARGET_MUL, "", 0, 1)
		+ " cheap=" + formatFloat(cheap, "", 0, 2)
		+ " base=" + formatFloat(EtaWith(0, 0.f, 0.f, false), "", 0, 0)
		+ " mkt=" + ((mktAt < 0) ? "-"
			: (KindName(ranked[mktAt].kind) + ":"
				+ ranked[mktAt].def.GetName()))
		+ " eta=" + ((bestAt < 0) ? "-"
			: (KindName(ranked[bestAt].kind) + ":"
				+ ranked[bestAt].def.GetName()
				+ "=" + formatFloat(bestEta, "", 0, 0)))
		+ " |" + parts);
}

}  // namespace Market
