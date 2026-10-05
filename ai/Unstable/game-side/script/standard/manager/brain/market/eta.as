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
final class Pool {
	array<int> def;
	array<float> cost;
	array<float> gain;
	array<int> n;
	array<bool> mob;   // only MOBILE hands can build it: a spot is where it is
	array<float> costE;   // its energy bill: a rung is fed in BOTH currencies
	array<float> makeE;   // and what it adds to the energy feed once it stands
	array<float> key;     // its place in the ladder: payback over survival
	array<int> hands;     // our mobile builders that can build it: a batch runs that wide
}

Pool@ gPoolNow;
Pool@ gPoolTech;
int gPoolAt = -999999;
float gPoolSpotWalkS = 0.f;   // mean walk home -> open spot, one hand

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

// THE LADDER AND ITS FIRST MOVE MUST AGREE. The first move runs under the
// hazard at home (EtaWithN); a pool sorted on bare payback still put the
// advanced fusion ahead of the fusion for every rung AFTER the first, so the
// two moves differed only in their opening step and the plan behind both was
// AFUS-heavy. A rung's place is its payback over its own survival.
float gPoolSurvBP = 1.f;
float gPoolMobBP = 1.f;
float gPoolP = 1.f;
void PoolInsert(Pool@ p, int d, float cost, float gain, int n, bool mob)
{
	if ((p is null) || (cost <= 1.f) || (gain <= 0.0001f) || (n <= 0))
		return;
	float surv = TechSurvival(d, gPoolSurvBP);
	if (surv < 0.05f)
		surv = 0.05f;
	int hands = 0;
	const array<int>@ bb = Catalog::gBuiltBy[d];
	for (uint q = 0; q < bb.length(); ++q) {
		if (Catalog::gMobile[bb[q]] && (bb[q] < int(gOwnCount.length())))
			hands += gOwnCount[bb[q]];
	}
	if (hands < 1)
		hands = 1;
	// Seconds per power at today's feed and lathe, not metal per power: the
	// metal order is the same for feed-bound rungs and wrong for the big
	// lathe-bound ones (an afus at 711 s ranked ahead of a fusion at 300,
	// and a moho-first path was charged a slice of that afus while the
	// fusion sat behind it).
	float tp = PoolEq(cost, Catalog::gCostE[d]) / gPoolP;
	{
		const int wide = (n < hands) ? n : hands;
		const float bt = Catalog::BuildSecondsAt(d,
				RungBP(d, mob ? gPoolMobBP : gPoolSurvBP)) / float((wide > 0) ? wide : 1);
		if (bt > tp)
			tp = bt;
	}
	const float pb = tp / gain / surv;
	uint at = 0;
	while ((at < p.def.length()) && (p.key[at] <= pb))
		++at;
	p.def.insertAt(at, d);
	p.cost.insertAt(at, cost);
	p.gain.insertAt(at, gain);
	p.n.insertAt(at, n);
	p.mob.insertAt(at, mob);
	p.costE.insertAt(at, Catalog::gCostE[d]);
	p.makeE.insertAt(at, Catalog::gMakeE[d]);
	p.key.insertAt(at, pb);
	p.hands.insertAt(at, hands);
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
	p.key.resize(0);
	p.hands.resize(0);
	{
		const float pm = EcoPowerM();
		const float ea = EtaEnergyAvail();
		gPoolMPerE = ((pm > 0.5f) && (ea > 1.f)) ? (pm / ea) : 0.f;
		const float fb = EffBP(0.f);
		gPoolSurvBP = (fb > 1.f) ? fb : 1.f;
		const float mb = gPoolSurvBP * MobileBPShare();
		gPoolMobBP = (mb > 1.f) ? mb : 1.f;
		gPoolP = (pm > 0.5f) ? pm : 0.5f;
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
	// THE OPEN SPOTS ARE WHERE THEY ARE. A claim rung walked to in the
	// fleet's order latency while the first move paid its real walk let any
	// build at the base beat every claim as the first move. The pool's
	// claim rung carries the mean walk from home to the open spots, shared
	// across the hands that walk in parallel, on top of the latency.
	gPoolSpotWalkS = 0.f;
	if ((open > 0) && (claimDef > 0) && Builder::gHomeSet) {
		float sum = 0.f;
		int cnt = 0;
		const array<int>@ lidx = LedgerIdx();
		for (uint si = 0; si < gAllSpots.length(); ++si) {
			if ((int(si) < int(lidx.length())) && (lidx[si] >= 0))
				continue;
			if (!OnMap(gAllSpots[si]))
				continue;
			sum += Builder::gHomePos.distance2D(gAllSpots[si]);
			++cnt;
		}
		float speed = 0.f;
		const array<int>@ bb = Catalog::gBuiltBy[claimDef];
		for (uint q = 0; q < bb.length(); ++q) {
			if (Catalog::gMobile[bb[q]] && (Catalog::gSpeed[bb[q]] > speed))
				speed = Catalog::gSpeed[bb[q]];
		}
		if ((cnt > 0) && (speed > 1.f))
			gPoolSpotWalkS = (sum / float(cnt)) / speed;
	}

	// HELD GROUND: the upgrade each standing extractor still has left in it.
	const int openGeo = aiEconomyMgr.OpenGeoSpotCount();
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

	// CONVERSION IS A RUNG WHILE ENERGY SPILLS. The tail below carries energy
	// at the conversion anchor, which assumes the converters exist: with the
	// bank full and 959 e/s wasted, the ladder kept buying fusions and never
	// the 380-metal converter that turns the spill into 10 m/s. What is
	// actually wasted, less what is already in flight to eat it, is the
	// rung's pool; a converter adds nothing once it is gone.
	{
		float spill = (gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma;
		spill -= ConvCapInFlight();
		int bestC = 0;
		float bestPb = 0.f;
		for (int d = 1; (spill > 1.f) && (d <= Catalog::gDefCount); ++d) {
			if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d]
				|| Catalog::gSub[d] || (Catalog::gConvCapacity[d] <= 0.f)
				|| (Catalog::gConvRatio[d] <= 0.f) || (Catalog::gCostM[d] <= 1.f))
				continue;
			if (!anyTier && !CanBuildEver(d))
				continue;
			if (Catalog::gBuiltBy[d].length() == 0)
				continue;
			const float cap = Catalog::gConvCapacity[d];
			const float chew = (spill < cap) ? spill : cap;
			const float pb = chew * Catalog::gConvRatio[d] / Catalog::gCostM[d];
			if (pb > bestPb) {
				bestPb = pb;
				bestC = d;
			}
		}
		if (bestC > 0) {
			const float cap = Catalog::gConvCapacity[bestC];
			const int n = int(spill / cap) + 1;
			const float chew = (spill < cap) ? spill : cap;
			PoolInsert(p, bestC, Catalog::gCostM[bestC],
					chew * Catalog::gConvRatio[bestC], n, false);
		}
	}
	// THE TAIL: generation, which nothing exhausts. Energy is carried at the
	// conversion anchor, the same rate EcoPowerM values it at -- so a converter
	// is power-neutral here by construction and is not a growth rung until
	// the spill above says otherwise.
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d])
			continue;
		if (!anyTier && !CanBuildEver(d))
			continue;
		// ...and nothing NOBODY builds (a free reactor no unit can place
		// read as five cheap rungs of the T2 ladder).
		if (Catalog::gBuiltBy[d].length() == 0)
			continue;
		float dI = Catalog::gMakeM[d];
		if (Catalog::gMakeE[d] > 0.f)
			dI += Catalog::gMakeE[d] * rate;
		if (dI <= 0.f)
			continue;
		// A geo is a vent-limited rung like a moho is a spot-limited one. Left
		// out, a path starting with the geo held power no other path could
		// reach, and the ladder sent T2 cons across the map for it over mohos
		// priced four times higher.
		if (Catalog::gNeedGeo[d]) {
			if (openGeo > 0)
				PoolInsert(p, d, Catalog::gCostM[d], dI, openGeo, false);
			continue;
		}
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
// One unit's share of a batch of k built `wide` at a time: the metal and
// energy feeds are charged for all k, the lathe for k/wide of them.
float StepSecWide(int d, float cost, float P, float bank, float bp, float eAvail, int k, int wide)
{
	float bt = Catalog::BuildSecondsAt(d, bp) / float(wide);
	if (bt < 0.1f)
		bt = 0.1f;
	float need = cost + Catalog::gCostE[d] * gPoolMPerE - bank / float(k);
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

float StepSec(int d, float cost, float P, float bank, float bp, float eAvail)
{
	float bt = Catalog::BuildSecondsAt(d, bp);
	if (bt < 0.1f)
		bt = 0.1f;
	// THE ENERGY BILL IS METAL THE CONVERTERS DID NOT MAKE. Charged only as a
	// wait for energy to arrive, a 69,000 E reactor on an economy that lives
	// by conversion read as cheap: the energy it eats over its build is metal
	// income the sim went on counting (apexearth: "if you're building an
	// advanced fusion then you don't have as much energy to do the
	// conversion, which makes it so you don't have as much metal"). The pool's
	// own metal-per-energy rate turns the bill into the metal it displaces.
	float need = cost + Catalog::gCostE[d] * gPoolMPerE - bank;
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
	float e = Eco::EInc() + EMakeInFlight();
	if (e < 0.f)
		e = 0.f;
	const float look = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
	e += Eco::ECur() / ((look > 1.f) ? look : 30.f);
	return (e > 1.f) ? e : 1.f;
}

// The share of the fleet's lathe that can walk to a spot. A nano turret adds
// build power the claim and upgrade rungs cannot use, and crediting it to
// them bought 14 nano turrets in the first twelve minutes of a 172-spot map
// while six constructors held the whole claim ladder (Carrot, 2026-09-08).
int   gMbsFrame = -1;
int   gMbsOwn = -1;
float gMbsVal = 1.f;
float MobileBPShare()
{
	if ((gMbsFrame == ai.frame) && (gMbsOwn == gOwnStamp))
		return gMbsVal;
	gMbsFrame = ai.frame;
	gMbsOwn = gOwnStamp;
	gMbsVal = MobileBPShareNow();
	return gMbsVal;
}

float MobileBPShareNow()
{
	float mobile = 0.f;
	float all = 0.f;
	const array<int>@ _own16 = OwnedDefs();
	for (uint _oi16 = 0; _oi16 < _own16.length(); ++_oi16) {
		const uint c = uint(_own16[_oi16]);
		const int d = int(c);
		// A nano turret is not IsBuilder() (no build options), and it is
		// the static lathe this share exists to see: gated on gBuilder it
		// read 1.0 for every team with any number of turrets standing.
		if ((gOwnCount[c] <= 0) || (Catalog::gBuildPower[d] <= 0.f))
			continue;
		if (Catalog::gMobile[d] && !Catalog::gBuilder[d])
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
		// A rung nothing we own can build yet is the new tier's: its hands
		// are the lab's first constructor and the ceiling hands we hold, not
		// the fleet (gLadderTierBP, set by the tech first move).
		const float rbp = p.mob[i]
				? ((CanBuildEver(p.def[i]) || (gLadderTierBP <= 0.f)) ? bpMob : gLadderTierBP)
				: bp;
		// k units are fed one after another but lathed side by side: 127
		// winds read 1,400 s serial when twenty hands stand them in ~70,
		// and every head that trimmed that tail by a few power -- a fusion
		// over a moho -- won the ladder on it.
		const int wide = (k < p.hands[i]) ? k : p.hands[i];
		const float stepS = StepSecWide(p.def[i], p.cost[i], P, bank,
				RungBP(p.def[i], rbp), eAvail, k, (wide > 0) ? wide : 1);
		float rlat = lat;
		if (p.mob[i] && (Catalog::gExtractsM[p.def[i]] > 0.f) && (gPoolSpotWalkS > 0.f)) {
			const int workers = int(aiBuilderMgr.GetWorkerCount());
			rlat += gPoolSpotWalkS / float((workers < 1) ? 1 : workers);
		}
		if (gLadderTrace)
			gLadderTraceS += " " + Catalog::Def(p.def[i]).GetName() + "x" + k
				+ "@" + int(stepS) + "+" + int(rlat) + "(P" + int(P) + ",bp" + int(RungBP(p.def[i], rbp)) + ")";
		// The last batch is charged for the power still needed, not for the
		// whole unit: a target 7 power past four afus read a fifth (1,392 s),
		// and that overshoot -- not the rungs -- decided fusion over moho.
		float fill = 1.f;
		if ((target > P) && (float(k) * g > target - P))
			fill = (target - P) / (float(k) * g);
		t += float(k) * (stepS + rlat) * fill;
		gLadderLatS += float(k) * rlat * fill;
		bank = 0.f;
		P += float(k) * g;
		eAvail += float(k) * p.makeE[i];
		n[i] -= k;
		++steps;
	}
	return (P >= target) ? t : ETA_BIG;
}

// THE LATHE A RUNG REALLY GETS. The fleet's whole build power is what the
// serial ladder assumes for every rung, and for a field of solars that is
// fair -- twenty hands on twenty panels. One reactor cannot use twenty hands,
// and the crew that turns up is fewer still than the cap admits: the measured
// effective lathe per def (Requests::EffBPFor) is what we have finished at,
// and once one has finished it is the number, for the first move and for
// every later rung of the same def alike.
// ...plus the lathe the first move ADDS: the cap swallowed a nano's addBP
// whole, so the ladder could never prefer a turret and the one eco ticket
// never carried it -- a wind at v=4.65 beat the nano at v=51.72, and one
// turret stood while the bank overflowed (his 8v8, 2026-09-11).
float gLadderAddBP = 0.f;
// The new tier's mobile lathe once a tech first move stands: the lab's first
// constructor plus the ceiling hands already owned. 0 = not a tech plan.
float gLadderTierBP = 0.f;
bool gLadderTrace = false;
string gLadderTraceS;
float CeilingHandsBP()
{
	float bpc = 0.f;
	const array<int>@ _own17 = OwnedDefs();
	for (uint _oi17 = 0; _oi17 < _own17.length(); ++_oi17) {
		const uint c = uint(_own17[_oi17]);
		const int d = int(c);
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[d] || !Catalog::gBuilder[d])
			continue;
		if (ReachesCeiling(d))
			bpc += float(gOwnCount[c]) * Catalog::gBuildPower[d];
	}
	return bpc;
}
// The latency the last EtaWithN plan carried: the part of its seconds that is
// a per-order guess, not lathe or feed -- the resolution two plans can be
// told apart at.
float gLadderLatS = 0.f;
float RungBP(int d, float bp)
{
	const float eff = Requests::EffBPFor(d) + gLadderAddBP;
	return ((eff > 1.f) && (eff < bp)) ? eff : bp;
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
	return EtaWithN(d, gainM, addBP, tech, 1, 0.f);
}

// The first move taken k times over. A single wind against a single advanced
// solar is not a comparison: the ladder's cheap rungs make up the difference in
// power at almost no cost, so the smaller first step always won on step cost
// alone and the economy was told to build winds. Candidates are compared at the
// ladder's own batch size -- enough of each to grow the economy by ETA_CHUNK --
// so twenty winds pay twenty walks, twenty cells and twenty energy bills
// against one advanced solar's (apexearth: "concentrated efforts on advsol
// might look even better").
// firstBP: the lathe that will actually stand on the first move -- the crew the
// request layer will admit plus the nano turrets in reach -- when the caller
// knows it. The fleet's whole build power put an advanced fusion up in 104 s in
// the simulator; two T2 constructors took 15 minutes over it in the game.
float EtaWithN(int d, float gainM, float addBP, bool tech, int k, float firstBP)
{
	double _tE = Perf::T0();
	PoolRefresh();
	Perf::Add("et.pool", _tE);
	_tE = Perf::T0();
	float P = EcoPowerM();
	if (P < 0.5f)
		P = 0.5f;
	const float target = P * ETA_TARGET_MUL;
	float bank = Eco::MCur();
	float bp = EffBP(0.f);
	if (bp < 1.f)
		bp = 1.f;
	float bpMob = bp * MobileBPShare();
	if (bpMob < 1.f)
		bpMob = 1.f;
	float eAvail = EtaEnergyAvail();
	float t = 0.f;
	gLadderAddBP = 0.f;
	gLadderLatS = 0.f;
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
		float bp1 = (Catalog::gExtractsM[d] > 0.f) ? bpMob : bp;
		if ((firstBP > 1.f) && (firstBP < bp1))
			bp1 = firstBP;
		bp1 = RungBP(d, bp1);
		for (int u = 0; u < k; ++u) {
			t += StepSec(d, Catalog::gCostM[d], P, bank, bp1, eAvail) / surv;
			if (u > 0) {
				t += lat;   // the first unit's walk is the asker's own, charged by the caller
				gLadderLatS += lat;
			}
			bank = 0.f;
			if (gainM > 0.f)
				P += gainM;
			if (addBP > 0.f) {
				bp += addBP;
				gLadderAddBP += addBP;
			}
			if (Catalog::gMakeE[d] > 0.f)
				eAvail += Catalog::gMakeE[d];
		}
		// THE LAB IS NOT THE TIER. Its rungs are built by the constructor it
		// makes: the cheapest builder it fields is the next step, at the
		// lab's own lathe, and the tier's mobile rungs then run on that hand
		// (plus any ceiling hands we hold), not on the whole fleet.
		if (tech) {
			int conD = -1;
			const array<int>@ fp = Catalog::gBuildsList[d];
			for (uint pi = 0; pi < fp.length(); ++pi) {
				if (Catalog::gMobile[fp[pi]] && Catalog::gBuilder[fp[pi]]
					&& ((conD < 0) || (Catalog::gCostM[fp[pi]] < Catalog::gCostM[conD])))
					conD = fp[pi];
			}
			if (conD > 0) {
				const float labBP = Catalog::gBuildPower[d];
				t += StepSec(conD, Catalog::gCostM[conD], P, bank,
						(labBP > 1.f) ? labBP : 1.f, eAvail);
				bank = 0.f;
				// ...with the fleet ASSISTING it, at the share EffBP grants
				// every build: a T1 hand cannot start a moho, but it can lathe
				// the frame the T2 hand opened.
				const float tier = Catalog::gBuildPower[conD] + CeilingHandsBP()
						+ bpMob * ai.GetTunable("apex_assist_share", TUNE_ASSIST_SHARE);
				gLadderTierBP = (tier > 1.f) ? tier : 1.f;
			}
		}
	}
	Perf::Add("et.head", _tE);
	_tE = Perf::T0();
	const float eta = t + LadderRun(tech ? gPoolTech : gPoolNow, P, bank, bp, bpMob, eAvail, target, d);
	Perf::Add("et.ladder", _tE);
	gLadderAddBP = 0.f;
	gLadderTierBP = 0.f;
	return eta;
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
		// THE START LATENCY IS NOT HANDS. It is the wait from order to
		// breaking ground, and more constructors do not shorten it -- they
		// lengthen it, and this read it as build time: a hundred hands at
		// 1,142 income said tBuild=1578 against tFeed=242 over 500 cheap
		// rungs and bought 147 more advanced constructors (his watched eco
		// seat: "we have like 100 advanced bot cons, way too many").
		tBuild += float(k) * bt;
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
//
// A hands shortage is a fleet that cannot lathe the income; the switch alone
// made the statement unconditional and idled full gantries beside a full bank.
bool OverflowBuysHands()
{
	if (!EtaOn())
		return false;
	return BPCapacity() < Eco::MInc();
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
		const float inc = Eco::MInc();
		float f = 0.f;
		if (inc > 0.1f) {
			const float slack = inc - Eco::MPull();
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
			|| (w.kind == WK_GEO) || (w.kind == WK_NANO) || (w.kind == WK_TECH)
			|| (w.kind == WK_CONVERT);
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
	if (w.kind == WK_CONVERT) {
		// The spill it eats, not its nameplate: the tail's rung is the same.
		float spill = (gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma;
		spill -= ConvCapInFlight();
		const float cap = Catalog::gConvCapacity[d];
		const float chew = (spill < cap) ? spill : cap;
		return (chew > 0.f) ? chew * Catalog::gConvRatio[d] : 0.f;
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
		// The RUNGS' best, not the merged categories': a converter is
		// CAT_ENERGY without a rung, so its price was handed to the ladder's
		// pick as that pick's ticket -- a fusion at v=2 drew level with the
		// converter at v=10 while 2,000 e/s was thrown away (his 8v8,
		// 2026-09-16: 41 fusion elections to 42 converter ones).
		if (!EtaRanks(ranked[i]))
			continue;
		if (ranked[i].value > best)
			best = ranked[i].value;
	}
	return best;
}

// The tech lab that reaches the target soonest, or -1. Tech sits in
// CAT_PRODUCE, outside the merge, so the economy pick never saw it; the
// draw compares the two ETAs and lets the lab be the economy's answer.
int EtaTechPick(array<Want@>@ ranked)
{
	if (ranked is null)
		return -1;
	int bestAt = -1;
	float bestEta = ETA_BIG;
	for (uint i = 0; i < ranked.length(); ++i) {
		if (ranked[i].kind != WK_TECH)
			continue;
		const float e = EtaOfWant(ranked[i]) * pow(2.7182818f, -ranked[i].nnTilt);
		if (e < bestEta) {
			bestEta = e;
			bestAt = int(i);
		}
	}
	return bestAt;
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
		// a trusted net verdict (nnlog.as) shortens or stretches the time to target
		const float e = EtaOfWant(ranked[i]) * pow(2.7182818f, -ranked[i].nnTilt);
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
