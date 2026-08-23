namespace Market {

//------------------------------------------------------------------------------
// THE BUILDER MARKET, prototype 1 (docs/20-brain-overhaul.md, value-paradigm
// skill). Every choice is a priced Want in one currency:
//
//   value = gain / (mCost + tCost)          [ (metal/s) per metal = 1/s ]
//   gain  = metal/s-equivalent return once standing
//   mCost = costM + costE priced at the conversion floor
//   tCost = (walk + build) seconds x the wage of a builder-second
//
// Proposers are pure; Decide() is the only spender. Every decision logs its
// arithmetic. Modeled terms (not read from defs) are marked MODEL -- they are
// where tuning lives, one named quantity each.
//------------------------------------------------------------------------------

const int WK_NONE = 0;
const int WK_MEX = 1;
const int WK_ENERGY = 2;
const int WK_PLANT = 3;
const int WK_GEO = 4;
const int WK_CONVERT = 5;
const int WK_STORE = 6;
const int WK_MEXUP = 7;
const int WK_TECH = 8;
const int WK_NANO = 9;
const int WK_RECLAIM = 10;
const int WK_ASSIST = 11;
const int WK_PROTECT = 12;

class Want {
	int kind = WK_NONE;
	CCircuitDef@ def;
	AIFloat3 pos;
	int spotId = -1;
	float gain = 0.f;
	float mCost = 0.f;
	float tCost = 0.f;
	float value = 0.f;
}

string KindName(int k)
{
	if (k == WK_MEX) return "mex";
	if (k == WK_ENERGY) return "energy";
	if (k == WK_PLANT) return "plant";
	if (k == WK_GEO) return "geo";
	if (k == WK_CONVERT) return "convert";
	if (k == WK_STORE) return "store";
	if (k == WK_MEXUP) return "mexup";
	if (k == WK_TECH) return "tech";
	if (k == WK_NANO) return "nano";
	if (k == WK_RECLAIM) return "reclaim";
	if (k == WK_ASSIST) return "assist";
	if (k == WK_PROTECT) return "protect";
	return "none";
}

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

// The floor exchange rate for energy: the game's own converters set what a
// standing E/s is worth in metal at worst (best conv ratio in the catalog).
float gEPriceFloor = -1.f;
// Smoothed energy-pull growth, E/s per second.
float gEPullPrev = -1.f;
int gEPullPrevAt = 0;
float gEPullGrowth = 0.f;
float gESurplusEma = 0.f;
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
}

float EPriceFloor()
{
	if (gEPriceFloor >= 0.f)
		return gEPriceFloor;
	float best = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (Catalog::gAvailable[i] && (Catalog::gConvRatio[i] > best))
			best = Catalog::gConvRatio[i];
	}
	gEPriceFloor = best;
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
	float ePull = aiEconomyMgr.energy.pull;
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
	const float ePull = aiEconomyMgr.energy.pull;
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
float EPriceCostAt(float buildSec)
{
	if (aiEconomyMgr.isEnergyFull
		&& (aiEconomyMgr.energy.income > aiEconomyMgr.energy.pull))
	{
		return 0.f;
	}
	const float fl = EPriceFloor();
	const float spot = ECostSpot();
	const float resp = ai.GetTunable("apex_e_response", TUNE_E_RESPONSE);
	float k = ((resp > 1.f) ? resp : 45.f) / ((buildSec > 1.f) ? buildSec : 1.f);
	if (k > 1.f)
		k = 1.f;
	return fl + (spot - fl) * k;
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

float ValueOf(int defId, float gain, float walkSec, float builderBP, Want@ w)
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
			const float feedSec = (Catalog::gCostM[defId] - mBank * 0.5f) / mInc;
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
				displacedM = UpDemand() * feedSec
						* ((Catalog::gExtractsM[defId] > 0.f) ? 0.f : 1.f);
			}
		}
	}
	w.gain = gain;
	// The E bill at what it actually forgoes (duration-priced, forgiven in
	// overflow) -- pricing it at the spot spike structurally banned every
	// big-E build (advsol, fusion) exactly when they were wanted.
	// The SPACE bill: ground is finite; footprint is paid per cell. MODEL:
	// a flat metal-per-cell price (apex_space_m) until base-crowding senses
	// price it dynamically. This is what makes dense energy (advsol) beat a
	// field of solars at equal payback.
	w.mCost = Catalog::gCostM[defId] * MCostScale()
			+ Catalog::gCostE[defId] * EPriceCostAt(buildSec)
			+ float(Catalog::gAreaCells[defId])
				* ai.GetTunable("apex_space_m", TUNE_SPACE_M);
	w.tCost = (walkSec + buildSec) * Wage() + displacedM;
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

//------------------------------------------------------------------------------
// Proposers -- pure, one Want each, value <= 0 means "not now".
//------------------------------------------------------------------------------

// Whether the last mex probe found open ground; the production market reads
// this as its demand signal for more claiming capacity.
bool gMexOpen = false;
float gAvgWalkDist = 600.f;   // smoothed claim walk, seeds at a near spot
// Rolling value of EXECUTED builder wants -- what a unit of spend is
// actually earning right now; the factory lines' opportunity floor.
float gWantEmaV = 0.f;
int gSupportDiagAt = 0;

// The rear-specialist election's enemy reference (ally centroid mirrored
// through map center), kept for the quiet rear's reach filter.
float gEcoRefX = -1.f;
float gEcoRefZ = -1.f;

// A constructor's mobility, as cycle speed on the CURRENT map's walks. Air
// cons fly the straight line and ignore blockage/pathing -- in a packed
// nano farm they are often the only realistic builder (apexearth
// 2026-08-23). MODEL: the flyer shortcut fraction.
float MobilityMult(int defId)
{
	const float speed = Catalog::gSpeed[defId];
	if (speed <= 1.f)
		return 1.f;
	float dist = gAvgWalkDist;
	if (Catalog::gFlyer[defId])
		dist *= ai.GetTunable("apex_fly_short", TUNE_FLY_SHORT);
	const float cycle = dist / speed + 12.f;   // walk + a claim's build
	float mob = 60.f / ((cycle > 1.f) ? cycle : 1.f);
	if (mob < 0.5f)
		mob = 0.5f;
	if (mob > 2.5f)
		mob = 2.5f;
	return mob;
}

// The last probed open spot's real yield (income x extraction); the tunable
// is only the pre-probe fallback. This was a MODEL term until the
// GetMexSpotIncome binding landed.
float gLastSpotM = -1.f;
float SpotM()
{
	return (gLastSpotM > 0.f) ? gLastSpotM
			: ai.GetTunable("apex_spot_m", TUNE_SPOT_M);
}

//------------------------------------------------------------------------------
// The claimed-spot ledger: which spots are ours, at what standing extraction.
// Fed by our own decisions and the finished/destroyed events; upgrade demand
// (and through it the tech want) is computed from this.
//------------------------------------------------------------------------------

array<int> gLSpot;
array<AIFloat3> gLPos;
array<float> gLIncome;    // the spot's raw income (extraction 1.0)
array<float> gLExtract;   // standing extraction; 0 until a mex FINISHES here
array<int> gLClaimAt;     // frame of the claim; unfinished claims expire
int LedgerFind(int spotId)
{
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLSpot[i] == spotId)
			return int(i);
	}
	return -1;
}
void LedgerClaim(int spotId, const AIFloat3& in pos, float income)
{
	if (LedgerFind(spotId) >= 0)
		return;
	gLSpot.insertLast(spotId);
	gLPos.insertLast(pos);
	gLIncome.insertLast(income);
	gLExtract.insertLast(0.f);
	gLClaimAt.insertLast(ai.frame);
}
// A claim that never finished releases its spot for re-proposal; without
// this, an aborted mex task left its ledger entry blocking the spot (and
// with it, the 21-decides-per-second churn cycling the same ground).
void LedgerSweep()
{
	for (uint i = 0; i < gLSpot.length(); ) {
		if ((gLExtract[i] <= 0.f) && (ai.frame - gLClaimAt[i] > 120 * SECOND)) {
			gLSpot.removeAt(i);
			gLPos.removeAt(i);
			gLIncome.removeAt(i);
			gLExtract.removeAt(i);
			gLClaimAt.removeAt(i);
			continue;
		}
		++i;
	}
}
int LedgerNearest(const AIFloat3& in pos)
{
	int best = -1;
	float bestD = 150.f;   // a mex stands on its spot; anything further is not it
	for (uint i = 0; i < gLPos.length(); ++i) {
		const float dd = pos.distance2D(gLPos[i]);
		if (dd < bestD) {
			bestD = dd;
			best = int(i);
		}
	}
	return best;
}
array<int> gOwnCount;   // finished units we own, by def id
void OwnAdd(int defId, int delta)
{
	if (gOwnCount.length() == 0)
		gOwnCount.resize(Catalog::gDefCount + 1);
	if ((defId >= 1) && (defId < int(gOwnCount.length()))) {
		gOwnCount[defId] += delta;
		if (gOwnCount[defId] < 0)
			gOwnCount[defId] = 0;
	}
}

// The extraction our standing capability can already reach: any owned mobile
// builder directly, or any owned factory through the builders it can make.
// This is what the tech want measures unlock against -- the ASKER's own
// reach read a T1 con as needing a T2 lab we already had three of.
float OwnedCeil()
{
	float ceil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		if (Catalog::gMobile[int(d)]) {
			for (uint i = 0; i < builds.length(); ++i) {
				if (Catalog::gExtractsM[builds[i]] > ceil)
					ceil = Catalog::gExtractsM[builds[i]];
			}
		} else {
			// A standing factory reaches what its producible builders reach.
			for (uint i = 0; i < builds.length(); ++i) {
				const int pd = builds[i];
				if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
					continue;
				const array<int>@ pb = Catalog::gBuildsList[pd];
				for (uint q = 0; q < pb.length(); ++q) {
					if (Catalog::gExtractsM[pb[q]] > ceil)
						ceil = Catalog::gExtractsM[pb[q]];
				}
			}
		}
	}
	return ceil;
}

// Mobile builders we own whose reach hits the game's extraction ceiling --
// the fleet already serving upgrade demand.
int ServingCons()
{
	int nServing = 0;
	const float ceilX = BestExtract();
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)] || !Catalog::gBuilder[int(d)])
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		for (uint i = 0; i < builds.length(); ++i) {
			if (Catalog::gExtractsM[builds[i]] >= ceilX) {
				nServing += gOwnCount[d];
				break;
			}
		}
	}
	return nServing;
}

// The costliest mobile unit our standing factories can produce.
float OwnedProdCostCeil()
{
	float ceil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[int(d)])
			continue;
		const array<int>@ pb = Catalog::gBuildsList[int(d)];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gMobile[pb[q]] && (Catalog::gCostM[pb[q]] > ceil))
				ceil = Catalog::gCostM[pb[q]];
		}
	}
	return (ceil > 1.f) ? ceil : 1.f;
}

float OwnedMobileCeil()
{
	float ceil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		for (uint i = 0; i < builds.length(); ++i) {
			if (Catalog::gExtractsM[builds[i]] > ceil)
				ceil = Catalog::gExtractsM[builds[i]];
		}
	}
	return ceil;
}

// Own standing generators, for the obsolete-reclaim want. NOCOUNT handles:
// every entry MUST leave via NoteDead.
array<CCircuitUnit@> gOwnGen;
array<Id> gOwnGenIds;
// High-value structures (labs, fusions, gantries...): each deserves its
// own turret ring (apexearth: "so shit at protecting important buildings
// like T2 -- 2700 metal investment dying").
array<CCircuitUnit@> gOwnBig;
array<Id> gOwnBigIds;

// The protection ledger: what stands where, per coverage class, plus the
// total structure value at risk. PROT_* index the class arrays.
const int PROT_RADAR = 0;
const int PROT_JAM = 1;
const int PROT_ANTINUKE = 2;
const int PROT_TARGFAC = 3;
const int PROT_DEF = 4;
const int PROT_SHIELD = 5;
const int PROT_N = 6;
array<array<AIFloat3>> gProtPos(PROT_N);
array<array<Id>> gProtIds(PROT_N);
array<array<CCircuitUnit@>> gProtUnit(PROT_N);
array<array<int>> gProtDefId(PROT_N);
float gAssetsM = 0.f;   // summed costM of standing structures

int ProtClassOf(int defId)
{
	if (Catalog::gShield[defId] && !Catalog::gMobile[defId]) return PROT_SHIELD;
	if (Catalog::gAntiNuke[defId]) return PROT_ANTINUKE;
	if (Catalog::gTargFac[defId]) return PROT_TARGFAC;
	if (Catalog::gRadar[defId]) return PROT_RADAR;
	if (Catalog::gJammer[defId]) return PROT_JAM;
	if ((Catalog::gMaxRange[defId] > 1.f) && !Catalog::gMobile[defId]
		&& !Catalog::gBuilder[defId] && (Catalog::gBuildsList[defId].length() == 0)
		&& (Catalog::gSurfT[defId] > 0.5f * Catalog::gAirT[defId]))
		return PROT_DEF;   // AA never counts as ground coverage (watched: AA at mexes)
	return -1;
}

void NoteFinished(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int defId = int(unit.circuitDef.id);
	OwnAdd(defId, 1);
	if (!Catalog::gMobile[defId] && (Catalog::gMakeE[defId] > 1.f)
		&& !Catalog::gNeedGeo[defId])
	{
		gOwnGen.insertLast(unit);
		gOwnGenIds.insertLast(unit.id);
	}
	if (!Catalog::gMobile[defId])
		gAssetsM += Catalog::gCostM[defId];
	if (!Catalog::gMobile[defId] && (Catalog::gCostM[defId] >= 1200.f)) {
		gOwnBig.insertLast(unit);
		gOwnBigIds.insertLast(unit.id);
	}
	const int pc = ProtClassOf(defId);
	if (pc >= 0) {
		gProtPos[pc].insertLast(unit.GetPos(ai.frame));
		gProtIds[pc].insertLast(unit.id);
		gProtUnit[pc].insertLast(unit);
		gProtDefId[pc].insertLast(defId);
	}
	if (Catalog::gExtractsM[defId] <= 0.f)
		return;
	const int i = LedgerNearest(unit.GetPos(ai.frame));
	if (i >= 0)
		gLExtract[i] = Catalog::gExtractsM[defId];
}
// Fallback anchor: the first finished nano, only if no plan latched first.
array<AIFloat3> gOwnNanoPos;
array<Id> gOwnNanoIds;

void NoteFarm(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int d = int(unit.circuitDef.id);
	// A finished FACTORY reserves its apron: three posts of open ground in
	// front so units can get out (apexearth -- the walled-in vehicle lab).
	if (!Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0)
		&& Base::gAxisSet)
	{
		const AIFloat3 fp0 = unit.GetPos(ai.frame);
		for (int ap = 1; ap <= 3; ++ap)
			Base::ReserveSite(fp0 + Base::gFwd * (80.f * float(ap)));
	}
	if (Catalog::gMobile[d] || (Catalog::gBuildPower[d] <= 0.f)
		|| (Catalog::gBuildsList[d].length() > 0))
	{
		return;
	}
	// A nano without a patrol order does NOTHING (apexearth 2026-08-23:
	// "give them a patrol order after they are created. Then they will do
	// work" -- the player's 'stop' shortcut). Patrol to a nearby point;
	// auto-assist/repair/reclaim in range follows.
	AIFloat3 p = unit.GetPos(ai.frame);
	p.x += 48.f;
	p.z += 48.f;
	unit.CmdPatrolTo(p);
	gOwnNanoPos.insertLast(unit.GetPos(ai.frame));
	gOwnNanoIds.insertLast(unit.id);
	if (gFarmSet)
		return;
	gFarmPos = unit.GetPos(ai.frame);
	gFarmSet = true;
	AiLog("apex: nano farm anchored at "
		+ formatFloat(gFarmPos.x, "", 0, 0) + "," + formatFloat(gFarmPos.z, "", 0, 0));
}
void NoteDead(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	WorkerGone(unit.id);
	EscortGone(unit.id);
	LossNote(int(unit.circuitDef.id));
	for (uint gi = 0; gi < gOwnGenIds.length(); ++gi) {
		if (gOwnGenIds[gi] == unit.id) {
			gOwnGen.removeAt(gi);
			gOwnGenIds.removeAt(gi);
			break;
		}
	}
	if (!Catalog::gMobile[int(unit.circuitDef.id)])
		gAssetsM -= Catalog::gCostM[int(unit.circuitDef.id)];
	for (uint bb = 0; bb < gOwnBigIds.length(); ++bb) {
		if (gOwnBigIds[bb] == unit.id) {
			gOwnBig.removeAt(bb);
			gOwnBigIds.removeAt(bb);
			break;
		}
	}
	for (uint nn = 0; nn < gOwnNanoIds.length(); ++nn) {
		if (gOwnNanoIds[nn] == unit.id) {
			gOwnNanoPos.removeAt(nn);
			gOwnNanoIds.removeAt(nn);
			break;
		}
	}
	for (int pcl = 0; pcl < PROT_N; ++pcl) {
		for (uint pi = 0; pi < gProtIds[pcl].length(); ++pi) {
			if (gProtIds[pcl][pi] == unit.id) {
				gProtPos[pcl].removeAt(pi);
				gProtIds[pcl].removeAt(pi);
				gProtUnit[pcl].removeAt(pi);
				gProtDefId[pcl].removeAt(pi);
				break;
			}
		}
	}
	OwnAdd(int(unit.circuitDef.id), -1);
	if (Catalog::gExtractsM[int(unit.circuitDef.id)] <= 0.f)
		return;
	const int i = LedgerNearest(unit.GetPos(ai.frame));
	if (i < 0)
		return;
	gLSpot.removeAt(i);
	gLPos.removeAt(i);
	gLIncome.removeAt(i);
	gLExtract.removeAt(i);
	gLClaimAt.removeAt(i);
}

// The best extraction any AVAILABLE def in the game reaches -- the ceiling
// upgrade demand is measured against.
float gBestExtract = -1.f;
float BestExtract()
{
	if (gBestExtract >= 0.f)
		return gBestExtract;
	gBestExtract = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (Catalog::gAvailable[i] && (Catalog::gExtractsM[i] > gBestExtract))
			gBestExtract = Catalog::gExtractsM[i];
	}
	return gBestExtract;
}

// Metal/s still extractable from ground we already hold, if every standing
// mex were upgraded to the game's best extractor. The tech want's fuel.
float UpDemand()
{
	const float ceil = BestExtract();
	float d = 0.f;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLExtract[i] > 0.f)
			d += gLIncome[i] * (ceil - gLExtract[i]);
	}
	return (d > 0.f) ? d : 0.f;
}

// TWO HALF-BUILT FUSIONS ARE WORSE THAN ONE FINISHED: an expensive def
// already in progress takes the next asker as a JOINER -- doubling build
// speed on the standing frame -- instead of opening a parallel copy
// (apexearth: "not too many of the same building in parallel; assist
// should count the time saved").
IUnitTask@ JoinBig(CCircuitDef@ def)
{
	if ((def is null)
		|| (def.costM < ai.GetTunable("apex_join_min_m", TUNE_JOIN_MIN_M)))
		return null;
	return Requests::LiveTaskOf(def);
}

// THE WALK IS THE RISK, not just the destination (apexearth, after a fresh
// T2 con marched into the enemy army while 4 home mexes sat unupgraded):
// known enemy mass along the corridor above the walker's own metal cost is
// a death walk whatever the spot pays. The walker's value is the bar -- a
// 100m con risks more than a 500m one, no fixed threshold anywhere.
bool DeathWalk(CCircuitUnit@ unit, const AIFloat3& in dest)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float bar = Catalog::gCostM[int(unit.circuitDef.id)];
	for (int s = 1; s <= 2; ++s) {
		AIFloat3 p = here;
		const float f = float(s) / 2.f;
		p.x += (dest.x - here.x) * f;
		p.z += (dest.z - here.z) * f;
		if (!OnMap(p))
			continue;
		if (ai.GetEnemyCostAt(p, 900.f) > bar)
			return true;
	}
	return false;
}

Want@ ProposeMex(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 here = unit.GetPos(ai.frame);
	// Threat ceiling is generous on purpose: a contested spot is priced, not
	// hidden (the leaf era's FindOpenMexSpot went silent exactly under attack).
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, here, 99.f);
	gMexOpen = (spot >= 0);
	if (spot < 0)
		return w;
	// Already committed: someone decided this spot and its task is live (or
	// recently was) -- proposing it again is the churn, not a want.
	if (LedgerFind(spot) >= 0)
		return w;
	const AIFloat3 pos = aiEconomyMgr.GetMexSpotPos(spot);
	// SUPER RISKY GROUND IS NOT A BUILD OPTION (apexearth): a spot past the
	// front is a con's death walk whatever it pays -- and refusing it also
	// stops the market hiring more cons for ground nobody can hold.
	if (Front::FoeKnown() && Builder::PastFront(pos)) {
		gMexOpen = false;
		return w;
	}
	// Deadly for THIS walker; the spot itself stays open for a safer angle,
	// so gMexOpen is not cleared.
	if (DeathWalk(unit, pos))
		return w;
	// The quiet rear stays home: no claim meaningfully closer to the enemy
	// than its own base depth (the mirror reference works pre-contact too).
	if (EcoFar(pos)) {
		gMexOpen = false;
		return w;
	}
	if (EcoQuiet() && (gEcoRefX >= 0.f)) {
		const float sdx = pos.x - gEcoRefX;
		const float sdz = pos.z - gEcoRefZ;
		const float hdx = Builder::gHomePos.x - gEcoRefX;
		const float hdz = Builder::gHomePos.z - gEcoRefZ;
		const float f = ai.GetTunable("apex_eco_reach_frac", TUNE_ECO_REACH_FRAC);
		if (sdx * sdx + sdz * sdz < (hdx * hdx + hdz * hdz) * f * f) {
			gMexOpen = false;
			return w;
		}
	}
	const float spotIncome = aiEconomyMgr.GetMexSpotIncome(spot);
	const float speed = Catalog::gSpeed[uid];
	const float dist = here.distance2D(pos);
	gAvgWalkDist = 0.8f * gAvgWalkDist + 0.2f * dist;
	const float walkSec = (speed > 1.f) ? (dist / speed) : 60.f;
	// Every extractor this builder can place, priced; the VALUE picks the
	// def (a same-yield mex at 4.7x the cost lost the nomination it used to
	// win on raw extraction -- measured: armamex over armmex).
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= 0.f))
			continue;
		Want c;
		// RELATIVE growth: a spot worth 3.4 at 16 m/s income is a 21% raise
		// to everything downstream (apexearth's arithmetic); the same spot
		// at 200 m/s is noise. The multiplier decays with wealth, so
		// expansion prioritizes itself exactly while we are behind.
		float gain = spotIncome * Catalog::gExtractsM[d];
		{
			const float inc0 = aiEconomyMgr.metal.income;
			gain *= 1.f + ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH)
					* gain / ((inc0 > gain) ? inc0 : gain);
		}
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_MEX;
			@w.def = Catalog::Def(d);
			w.pos = pos;
			w.spotId = spot;
			gLastSpotM = gain;
		}
	}
	return w;
}

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
	const AIFloat3 here = unit.GetPos(ai.frame);
	const int spot = aiEconomyMgr.FindOpenGeoSpot(unit, here);
	if (spot < 0)
		return w;
	const AIFloat3 pos = aiEconomyMgr.GetGeoSpotPos(spot);
	if (EcoFar(pos) || (Front::FoeKnown() && Builder::PastFront(pos)))
		return w;
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f) ? (here.distance2D(pos) / speed) : 60.f;
	const float gain = Catalog::gMakeE[geoId]
			* EPriceAt(Catalog::BuildSecondsAt(geoId, EffBP(Catalog::gBuildPower[uid])));
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
float PipeLatencyMult(int plantId, float askerBP)
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
	const float H = ai.GetTunable("apex_pipe_latency_h", TUNE_PIPE_LATENCY_H);
	const float h = (H > 1.f) ? H : 60.f;
	return h / (h + labSec + conSec);
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
	const float structInc = (gIncEma > 0.f) ? gIncEma : aiEconomyMgr.metal.income;
	const int supported = 1 + int(structInc / ((per > 1.f) ? per : 50.f));
	if (Factory::gFactoryCount
			+ Requests::LiveCountOf(int(Task::BuildType::FACTORY)) >= supported)
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	// Expansion stream while ground remains, PLUS the production appetite a
	// new line would serve -- a lost lab re-prices itself from the army gap
	// even when every spot is claimed.
	const float fillS0 = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float aGap = ArmyTarget() - ArmyValue();
	const float prodTerm = (aGap > 0.f)
			? (aGap / ((fillS0 > 1.f) ? fillS0 : 180.f))
				/ float(1 + Factory::gFactoryCount)
			: 0.f;
	const float gain = ((gMexOpen ? SpotM() : 0.f) + BPGap() + prodTerm)
			* ai.GetTunable("apex_plant_pipe", TUNE_PLANT_PIPE)
			* Utilization();
	if (gain <= 0.05f)
		return w;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gBuildsList[d].length() == 0)
			continue;   // not a factory
		// A plant that cannot produce a mobile builder buys no expansion --
		// and the builder must be able to EXIST here: a shipyard's ship-cons
		// have no connected area at a land base (measured: armsy chosen on
		// Comet Catcher, a game-long placement failure).
		// The plant inherits its best product's MOBILITY: an air lab's cons
		// fly, which is what lets it compete once the base packs.
		const AIFloat3 here = unit.GetPos(ai.frame);
		float bestMob = 0.f;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int pd = prods[p];
			if (Catalog::gMobile[pd] && Catalog::gBuilder[pd]
				&& ai.CanDefReach(Catalog::Def(pd), here, here))
			{
				const float m = MobilityMult(pd);
				if (m > bestMob)
					bestMob = m;
			}
		}
		if (bestMob <= 0.f)
			continue;
		// A DUPLICATE line is only parallel capacity: value divides per
		// copy owned (watched: T1 air labs multiplying). And a plant whose
		// cons reach the extraction ceiling outranks a T1 copy -- "we want
		// multiple T2 air labs, not T1 air labs."
		float dupGain = gain / float(1 + Catalog::Def(d).count);
		{
			float prodReach = 0.f;
			for (uint pr = 0; pr < prods.length(); ++pr) {
				if (!Catalog::gMobile[prods[pr]] || !Catalog::gBuilder[prods[pr]])
					continue;
				const array<int>@ prb = Catalog::gBuildsList[prods[pr]];
				for (uint rr = 0; rr < prb.length(); ++rr) {
					if (Catalog::gExtractsM[prb[rr]] > prodReach)
						prodReach = Catalog::gExtractsM[prb[rr]];
				}
			}
			const float ceilX = BestExtract();
			if (ceilX > 0.f)
				dupGain *= 1.f + prodReach / ceilX;
		}
		// The quiet rear's expansion is AIR (apexearth: "the goal should be
		// air cons... stop making ground labs"): flying cons don't jam the
		// packed farm, and its army era is gantry-only. Ground plants stop
		// pricing once one stands; air keeps its full value.
		if (EcoQuiet() && (Factory::gFactoryCount >= 1)) {
			bool airLab = false;
			for (uint p4 = 0; p4 < prods.length(); ++p4) {
				if (Catalog::gMobile[prods[p4]] && Catalog::gBuilder[prods[p4]]
					&& Catalog::gFlyer[prods[p4]]) {
					airLab = true;
					break;
				}
			}
			if (!airLab)
				continue;
		}
		Want c;
		ValueOf(d, dupGain * bestMob * PipeLatencyMult(d, Catalog::gBuildPower[uid]),
				0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PLANT;
			@w.def = Catalog::Def(d);
			// Plants stand at the base anchor -- the middle of what we own.
			w.pos = InteriorSite(EcoSiteFor(unit));
		}
	}
	return w;
}

// Upgrade a spot we hold: gain is the extraction delta on the spot's real
// income. Pure arithmetic; capability comes free from BuildsOf.
Want@ ProposeMexUp(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	for (uint li = 0; li < gLSpot.length(); ++li) {
		if (gLExtract[li] <= 0.f)
			continue;   // not finished (or already being replaced)
		if (DeathWalk(unit, gLPos[li]))
			continue;   // a forward mex we hold can still be a lethal walk
		for (uint i = 0; i < builds.length(); ++i) {
			const int d = builds[i];
			if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= gLExtract[li]))
				continue;
			float delta = gLIncome[li] * (Catalog::gExtractsM[d] - gLExtract[li]);
			{
				const float inc1 = aiEconomyMgr.metal.income;
				delta *= 1.f + ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH)
						* delta / ((inc1 > delta) ? inc1 : delta);
			}
			const float walkSec = (speed > 1.f)
					? (here.distance2D(gLPos[li]) / speed) : 60.f;
			Want c;
			ValueOf(d, delta, walkSec, Catalog::gBuildPower[uid], c);
			if (c.value > w.value) {
				w = c;
				w.kind = WK_MEXUP;
				@w.def = Catalog::Def(d);
				w.pos = gLPos[li];
				w.spotId = gLSpot[li];
			}
		}
	}
	return w;
}

// A plant priced by what it UNLOCKS: the upgrade demand its constructor
// products could serve that no builder we own can reach. Deliberately not
// gated by the lines-per-income rule (its return is better economics, not
// more parallel production). MODEL: the pipeline discount.
int gTechDiagAt = 0;
Want@ ProposeTech(CCircuitUnit@ unit)
{
	Want w;
	const float demand = UpDemand();
	if (ai.frame >= gTechDiagAt) {
		gTechDiagAt = ai.frame + 120 * SECOND;
		AiLog("apex: tech-diag team=" + ai.teamId + " upD=" + demand
				+ " ceil=" + BestExtract() + " ownCeil=" + OwnedCeil()
				+ " spots=" + gLSpot.length() + " funded="
				+ (ArmyValue() / ((ArmyTarget() > 1.f) ? ArmyTarget() : 1.f)));
	}
	if (demand <= 0.5f)
		return w;
	// Dedup is PER DEF: a T1 rebuild in flight must not zero the T2 lab's
	// price (watched, 8v8: a team overflowing with no T2 -- any live plant
	// request blanket-blocked tech).
	const int uid = int(unit.circuitDef.id);
	const float ownCeil = OwnedCeil();
	// Best mobility among owned ceiling-reaching cons: a plant whose con
	// flies (T2 air) is an upgrade even when extraction reach ties.
	float ownMob = 0.f;
	{
		const float ceilX = BestExtract();
		for (uint dd = 1; dd < gOwnCount.length(); ++dd) {
			if ((gOwnCount[dd] <= 0) || !Catalog::gMobile[int(dd)] || !Catalog::gBuilder[int(dd)])
				continue;
			const array<int>@ bb = Catalog::gBuildsList[int(dd)];
			for (uint q = 0; q < bb.length(); ++q) {
				if (Catalog::gExtractsM[bb[q]] >= ceilX) {
					const float m0 = MobilityMult(int(dd));
					if (m0 > ownMob)
						ownMob = m0;
					break;
				}
			}
		}
	}
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float pipe = ai.GetTunable("apex_tech_pipe", TUNE_TECH_PIPE);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		if (Catalog::gBuildsList[d].length() == 0)
			continue;
		if (Requests::LiveOfDef(Catalog::Def(d)))
			continue;   // this def is already requested: help it, not double it
		// The plant's best feasible mobile builder, and the extraction IT
		// reaches; the plant unlocks only what exceeds our own ceiling.
		float prodCeil = 0.f;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int pd = prods[p];
			if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
				continue;
			if (!ai.CanDefReach(Catalog::Def(pd), here, here))
				continue;
			const array<int>@ pb = Catalog::gBuildsList[pd];
			for (uint q = 0; q < pb.length(); ++q) {
				if (Catalog::gExtractsM[pb[q]] > prodCeil)
					prodCeil = Catalog::gExtractsM[pb[q]];
			}
		}
		// Two ways a plant unlocks: reach beyond what we own, or the same
		// reach carried by a decisively more MOBILE con (the T2 air lab).
		float prodMob = 0.f;
		for (uint p2 = 0; p2 < prods.length(); ++p2) {
			const int pd2 = prods[p2];
			if (!Catalog::gMobile[pd2] || !Catalog::gBuilder[pd2])
				continue;
			const array<int>@ pb2 = Catalog::gBuildsList[pd2];
			for (uint q2 = 0; q2 < pb2.length(); ++q2) {
				if (Catalog::gExtractsM[pb2[q2]] >= BestExtract()) {
					const float m2 = MobilityMult(pd2);
					if (m2 > prodMob)
						prodMob = m2;
					break;
				}
			}
		}
		// A lab without follow-through is a statue: its price carries its
		// first constructor, and its VALUE scales with how funded the army
		// is -- an outgunned base defers tech exactly as much as it is
		// outgunned (apexearth: "we starve our army production by starting
		// a T2 lab too early... calculate the cost of making a lab's units
		// prior to making it"). No timer anywhere.
		const float aT = ArmyTarget();
		const float funded = (aT > 1.f) ? (ArmyValue() / aT) : 1.f;
		// The quiet rear is EXEMPT: its follow-through is mohos and
		// fusions, not an army -- gating its lab on the army it was told
		// not to build starved its whole mandate (measured: funded=0.024,
		// a 40x tech discount on the one player built to tech).
		float fundedMul = (funded > 1.f) ? 1.f : funded;
		if (EcoQuiet())
			fundedMul = 1.f;
		float techGain = 0.f;
		if (prodCeil > ownCeil)
			techGain = demand * pipe;
		else if ((ownMob > 0.f) && (prodMob > ownMob * 1.2f)) {
			techGain = demand * pipe * (prodMob / ownMob - 1.f);
			// The quiet rear NEEDS wings: flying cons are its whole
			// expansion plan (ground plants stop pricing), so the first
			// flying-builder unlock is a full-demand want, not a
			// mobility-delta sliver (seed 23: no air lab in 15 min).
			if (EcoQuiet()) {
				bool ownFlyingBuilder = false;
				for (uint fb = 1; fb < gOwnCount.length(); ++fb) {
					if ((gOwnCount[fb] > 0) && Catalog::gFlyer[int(fb)]
						&& Catalog::gBuilder[int(fb)] && Catalog::gMobile[int(fb)]) {
						ownFlyingBuilder = true;
						break;
					}
				}
				bool unlocksFlyer = false;
				for (uint pf = 0; pf < prods.length(); ++pf) {
					if (Catalog::gMobile[prods[pf]] && Catalog::gBuilder[prods[pf]]
						&& Catalog::gFlyer[prods[pf]]) {
						unlocksFlyer = true;
						break;
					}
				}
				if (!ownFlyingBuilder && unlocksFlyer)
					techGain = demand * pipe;
			}
		}
		// Channel 3, the GANTRY case: a plant whose products dwarf anything
		// we can currently produce is the overflow SINK -- its value is the
		// wasted income its production line would absorb.
		{
			float prodMax = 0.f;
			for (uint p3 = 0; p3 < prods.length(); ++p3) {
				if (Catalog::gMobile[prods[p3]]
					&& (Catalog::gCostM[prods[p3]] > prodMax))
					prodMax = Catalog::gCostM[prods[p3]];
			}
			if (prodMax > 2.f * OwnedProdCostCeil()) {
				// The gantry's value is PENETRATION plus the army gap that
				// ONLY its products can fill: at 250 m/s nobody built one
				// because porc-and-overflow were its only terms (watched).
				// The gap reads the FULL target -- T3 is what the eco role
				// suppressed everything else for.
				const float porc = aiEnemyMgr.GetEnemyCost(RT::STATIC);
				const float pen = (porc / 300.f) * pipe;
				const float sink = OverflowM() * pipe;
				const float fillS3 = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
				const float gapF = ArmyTargetFull() - ArmyValue();
				const float gapStream = (gapF > 0.f)
						? (gapF / ((fillS3 > 1.f) ? fillS3 : 60.f)) * pipe : 0.f;
				float g3 = (pen > sink) ? pen : sink;
				g3 += gapStream;
				if (g3 > techGain)
					techGain = g3;
			}
		}
		if (techGain <= 0.f)
			continue;
		// Overflowing metal escalates a justified tech want: the lab's
		// pipeline (mohos, fusion-building cons) is the spender the current
		// fleet lacks. Without this, 40-metal winds out-valued the 3300
		// tech bill at argmax for five straight minutes of full storage
		// (seed 23: T2 at 10.9m; seed 11's 3.3m was E-saturation luck).
		techGain += OverflowM() * pipe;
		Want c;
		ValueOf(d, techGain * fundedMul
					* PipeLatencyMult(d, Catalog::gBuildPower[uid]),
				0.f, Catalog::gBuildPower[uid], c);
		// the follow-through bill: cheapest constructor this lab produces
		{
			float conBill = 0.f;
			const array<int>@ pf = Catalog::gBuildsList[d];
			for (uint pi2 = 0; pi2 < pf.length(); ++pi2) {
				if (Catalog::gMobile[pf[pi2]] && Catalog::gBuilder[pf[pi2]]
					&& ((conBill <= 0.f) || (Catalog::gCostM[pf[pi2]] < conBill)))
					conBill = Catalog::gCostM[pf[pi2]];
			}
			if (conBill > 0.f) {
				c.mCost += conBill;
				c.value = c.gain / (c.mCost + c.tCost);
			}
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_TECH;
			@w.def = Catalog::Def(d);
			// The tech lab is the most protection-hungry building we own:
			// at the base anchor, never at a forward asker (watched).
			w.pos = InteriorSite(here);
		}
	}
	return w;
}

// The nano FARM -- a PLANNED spot, not wherever the first nano landed
// (apexearth 2026-08-23: "we should ahead of time know generally some
// really good spots to build the economy... as far away from any active
// threat as we can"). The base frame's axis points at the front, so the
// farm sits BEHIND the anchor; the frame follows the frontline senses, so
// "behind" is already "away from influence".
AIFloat3 gFarmPos;
bool gFarmSet = false;

// The best available nano's reach -- the coverage circle everything in the
// farm must fit inside.
float gNanoRange = -1.f;
float NanoRange()
{
	if (gNanoRange > 0.f)
		return gNanoRange;
	float best = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::gAvailable[i] || Catalog::gMobile[i])
			continue;
		if ((Catalog::gBuildPower[i] <= 0.f) || (Catalog::gBuildsList[i].length() > 0))
			continue;
		if (Catalog::gBuildDist[i] > best)
			best = Catalog::gBuildDist[i];
	}
	// Sanity-capped: an exotic long-reach def must not widen the farm
	// (a 1000-elmo reach def once did, and the Take radius it fed collapsed
	// every eco want into one standing request -- a fleet-wide freeze).
	if (best > 500.f)
		best = 500.f;
	gNanoRange = (best > 64.f) ? best : 400.f;
	return gNanoRange;
}

// The farm's SLOT PLAN. Random shake around one anchor scattered eco in
// staggered diagonals (apexearth's screenshot, 2026-08-23: "some of the
// buildings are just slightly off"). Each def gets rows of flush slots:
// pitch = footprint rounded up to the 16-elmo lattice (odd-celled defs get
// their unavoidable half-cell gap), rows stack rearward, columns run along
// the base's across axis. The cursor never reuses a slot; a failed build
// leaves a hole, never an overlap.
const float FARM_ROW_W = 640.f;   // elmos of columns per row
array<int> gFRowDef;      // row -> def id
array<int> gFRowNext;     // row -> next column index
array<float> gFRowPitch;  // row -> slot pitch (elmos)
array<float> gFRowZ;      // row -> rearward offset of the row's center line
float gFarmDepth = 0.f;   // next free rearward offset

float PitchOf(int defId)
{
	int side = 1;
	while (side * side < Catalog::gAreaCells[defId])
		++side;
	// Odd-celled footprints cannot sit flush on the 16-lattice; round up.
	if ((side & 1) == 1)
		++side;
	return float(side) * 16.f;
}

// Every metal spot on the map, cached on first use -- planned placements
// must never stand on one (watched: buildings over mexes).
array<AIFloat3> gAllSpots;
bool gSpotsCached = false;
void CacheSpots()
{
	if (gSpotsCached)
		return;
	gSpotsCached = true;
	for (int i = 0; i < 1024; ++i) {
		const AIFloat3 sp = aiEconomyMgr.GetMexSpotPos(i);
		if (sp.x < 0.f)
			break;
		gAllSpots.insertLast(sp);
	}
}
bool NearSpotR(const AIFloat3& in p, float r)
{
	CacheSpots();
	for (uint i = 0; i < gAllSpots.length(); ++i) {
		if (p.distance2D(gAllSpots[i]) < r)
			return true;
	}
	return false;
}

bool NearSpot(const AIFloat3& in p)
{
	return NearSpotR(p, 100.f);
}

//------------------------------------------------------------------------------
// THE TEMPORAL-CONSISTENCY LAW's shared primitives (apexearth's 10 m/s
// arithmetic: com + 3 cons feeding a T2 lab while 2 safe mexes sat open).
// Every proposer that claims "my BP converts to progress" buys from
// FreeMetalFlow; every feed-bound build is charged what it postpones via
// OpenSpotStream + UpDemand. New pricing goes through these, not around.
//------------------------------------------------------------------------------

// Metal flow the economy has genuinely unspent: income above pull, plus a
// bank trickle. This is ALL the throughput another pair of hands can add
// anywhere -- marginal BP at a fed site is worth zero.
float FreeMetalFlow()
{
	const float free = (aiEconomyMgr.metal.income - aiEconomyMgr.metal.pull)
			+ aiEconomyMgr.metal.current / 60.f;
	return (free > 0.f) ? free : 0.f;
}

// Where a fusion-tier generator belongs: beside standing or building kin,
// else the deep rear of the base axis, furthest from the enemy.
AIFloat3 BigEnergySite()
{
	const float bar = ai.GetTunable("apex_big_e", TUNE_BIG_E);
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || (Catalog::gMakeE[int(d)] < bar))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(int(d)),
				Builder::gHomePos, 8000.f);
		if ((us !is null) && (us.length() > 0) && (us[us.length() - 1] !is null))
			return us[us.length() - 1].GetPos(ai.frame);
	}
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt is null) || (lt.buildDef is null))
			continue;
		if (Catalog::gMakeE[int(lt.buildDef.id)] >= bar) {
			const AIFloat3 kp = lt.GetBuildPos();
			if (OnMap(kp))
				return kp;
		}
	}
	if (Base::gAnchorSet && Base::gAxisSet) {
		AIFloat3 back = Base::gAnchor
				- Base::gFwd * ai.GetTunable("apex_fus_back", TUNE_FUS_BACK);
		if (OnMap(back))
			return back;
	}
	return Builder::gHomePos;
}


// Metal spots are sacred ground: an UNCLAIMED spot is legal terrain to the
// engine's site search, so a factory landed smack on one (watched). Intent
// positions step backward (then sideways) until the footprint clears.
AIFloat3 ClearOfSpots(const AIFloat3& in pos, float clear)
{
	if (!NearSpotR(pos, clear))
		return pos;
	for (int step = 1; step <= 8; ++step) {
		if (Base::gAxisSet) {
			AIFloat3 b = pos - Base::gFwd * (96.f * float(step));
			if (OnMap(b) && !NearSpotR(b, clear))
				return b;
			AIFloat3 l = pos + Base::gAcross * (96.f * float(step));
			if (OnMap(l) && !NearSpotR(l, clear))
				return l;
			AIFloat3 rr = pos - Base::gAcross * (96.f * float(step));
			if (OnMap(rr) && !NearSpotR(rr, clear))
				return rr;
		}
	}
	return pos;
}

AIFloat3 FarmSlot(int defId)
{
	const float pitch = PitchOf(defId);
	int row = -1;
	for (uint i = 0; i < gFRowDef.length(); ++i) {
		if ((gFRowDef[i] == defId)
			&& (float(gFRowNext[i]) * pitch < FARM_ROW_W))
		{
			row = int(i);
			break;
		}
	}
	if (row < 0) {
		gFRowDef.insertLast(defId);
		gFRowNext.insertLast(0);
		gFRowPitch.insertLast(pitch);
		gFRowZ.insertLast(gFarmDepth + pitch * 0.5f);
		row = int(gFRowDef.length()) - 1;
		gFarmDepth += pitch;
	}
	// Skip slots that would stand on a metal spot (cursor advances; the
	// hole stays a hole).
	for (int tries = 0; tries < 8; ++tries) {
		const int col = gFRowNext[row];
		gFRowNext[row] = col + 1;
		// Columns alternate outward from the axis so the block grows centered.
		const float lat = (float((col + 1) / 2) * ((col % 2 == 0) ? 1.f : -1.f)) * pitch;
		AIFloat3 p = gFarmPos + Base::gAcross * lat - Base::gFwd * gFRowZ[row];
		if (!NearSpot(p))
			return p;
	}
	return gFarmPos - Base::gFwd * gFarmDepth;
}

// Factory ground: the REAR FLANK of the farm block (apexearth: T2 labs
// "further in the back of our base area", and the vehicle lab needs room
// in front of it -- packed interior blocked its exit). Beside the farm,
// behind the base, lateral ground open for roll-out; flanks alternate.
int gPlantFlank = 0;
AIFloat3 InteriorSite(const AIFloat3& in fallback)
{
	// The first factory rises where the builder stands -- the flank plan is
	// for a base that exists (watched: a long opening walk to lab #1).
	if (Factory::gFactoryCount == 0)
		return fallback;
	if (gFarmSet && Base::gAxisSet) {
		gPlantFlank = 1 - gPlantFlank;
		const float side = (gPlantFlank == 0) ? 1.f : -1.f;
		AIFloat3 p = gFarmPos
				+ Base::gAcross * (side * (FARM_ROW_W * 0.5f + 300.f))
				- Base::gFwd * (gFarmDepth * 0.5f);
		if (OnMap(p))
			return p;
		p = gFarmPos - Base::gAcross * (side * (FARM_ROW_W * 0.5f + 300.f))
				- Base::gFwd * (gFarmDepth * 0.5f);
		if (OnMap(p))
			return p;
	}
	if (gFarmSet)
		return gFarmPos;
	return fallback;
}

AIFloat3 EcoSiteFor(CCircuitUnit@ unit)
{
	if (!gFarmSet && Base::gAnchorSet && Base::gAxisSet) {
		// Within nano reach of the anchor: the block must serve the lab AND
		// the eco builds beside it (apexearth: nanos "not even within range
		// of the T1 lab they would support").
		float back = ai.GetTunable("apex_farm_back", TUNE_FARM_BACK);
		if (back > NanoRange() * 0.8f)
			back = NanoRange() * 0.8f;
		AIFloat3 spot = Base::gAnchor - Base::gFwd * back;
		if (OnMap(spot)) {
			gFarmPos = spot;
			gFarmSet = true;
			AiLog("apex: nano farm planned at "
				+ formatFloat(spot.x, "", 0, 0) + "," + formatFloat(spot.z, "", 0, 0)
				+ " (rear of base axis, r=" + formatFloat(NanoRange(), "", 0, 0) + ")");
		}
	}
	return gFarmSet ? gFarmPos : unit.GetPos(ai.frame);
}

// Nano turrets: standing build power, priced by the BP gap it fills. A nano
// is an immobile lathe with no build options; its drain is its workertime
// at the game's metal-per-workertime rate (7 m/s per 80 WT, the T1 con's
// measured pull).
// Unabsorbed line spend across working factories: each nano near a line
// absorbs ~17.5 m/s; a hot line justifies a RING, not one turret.
// A line's fair share of the production appetite scales with what it can
// BUILD: the T2 lab making 700-metal units earns a bigger nano ring than a
// pawn line (apexearth: "need more nano turrets near our T2 lab").
float LineCostCeil(CCircuitUnit@ f)
{
	float ceil = 100.f;
	const array<int>@ pr = Catalog::BuildsOf(int(f.circuitDef.id));
	for (uint q = 0; q < pr.length(); ++q) {
		if (Catalog::gMobile[pr[q]] && (Catalog::gCostM[pr[q]] > ceil))
			ceil = Catalog::gCostM[pr[q]];
	}
	return ceil;
}

float UnservedLineSpend()
{
	float unserved = 0.f;
	const float per = LineSpend();
	float sumCeil = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if ((Factory::gFacUnits[fi] !is null)
			&& (Factory::gFacUnits[fi].CountQueued(null) > 0))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.CountQueued(null) == 0))
			continue;
		const float share = (sumCeil > 1.f)
				? (per * float(Factory::gFactoryCount) * LineCostCeil(f) / sumCeil)
				: per;
		int nanosNear = 0;
		const AIFloat3 fp = f.GetPos(ai.frame);
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
				++nanosNear;
		}
		const float u = share - float(nanosNear) * 17.5f;
		if (u > 0.f)
			unserved += u;
	}
	return unserved;
}

Want@ ProposeNano(CCircuitUnit@ unit)
{
	Want w;
	// Overflow is nano demand in its own right: a nano never walks, so it
	// absorbs overflow at face value even when the mobile fleet's paper
	// capacity looks sufficient. And a WORKING factory with no nano in
	// reach is full demand by itself -- the first lab must not build cons
	// unassisted while metal overflows (apexearth 2026-08-23, twice).
	// Raw overflow is NOT nano demand: overflow that persists after the
	// last nano proves nanos are not absorbing it (a full-metal stall
	// bought nanos at face value forever while the T2 lab priced at
	// nothing -- watched). BP demand sizes against income (BPGap) and
	// against lines with real work (UnservedLineSpend) -- the honest-
	// feedback law; overflow's buyers are converters, storage and tech.
	// NANOS SERVE FACTORIES AND BIG BUILDS ONLY (apexearth: "these nano
	// farms are just not working out... ditch that idea entirely. The
	// nanos are just for factories and expensive buildings like fusions
	// and afus"). Demand: working lines short of hands, or a fusion-tier
	// frame standing without its ring of ~3 (his read of stock's
	// caretaker logic). The income-headroom gap (BPGap) buys constructors
	// now, never farm turrets.
	const float lineNeed = UnservedLineSpend();
	float sinkNeed = 0.f;
	for (uint si = 0; si < Requests::gLive.length(); ++si) {
		IUnitTask@ st = Requests::gLive[si];
		if ((st is null) || (st.buildDef is null))
			continue;
		const int bd = int(st.buildDef.id);
		if ((Catalog::gCostM[bd] < ai.GetTunable("apex_nano_sink_m", TUNE_NANO_SINK_M))
			&& (Catalog::gMakeE[bd] < ai.GetTunable("apex_big_e", TUNE_BIG_E)))
			continue;
		const AIFloat3 sp3 = st.GetBuildPos();
		if (!OnMap(sp3))
			continue;
		int nAt = 0;
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (sp3.distance2D(gOwnNanoPos[ni]) < 350.f)
				++nAt;
		}
		if (nAt < 3) {
			const float free3 = FreeMetalFlow();
			const float need = (free3 < 35.f) ? free3 : 35.f;
			if (need > sinkNeed)
				sinkNeed = need;
		}
	}
	float over = (sinkNeed > lineNeed) ? sinkNeed : lineNeed;
	if (over <= 0.5f)
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		if ((Catalog::gBuildPower[d] <= 0.f) || (Catalog::gBuildsList[d].length() > 0))
			continue;
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		Want c;
		ValueOf(d, (over < drain) ? over : drain, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_NANO;
			@w.def = Catalog::Def(d);
			w.pos = EcoSiteFor(unit);
		}
	}
	return w;
}

// A hard stall re-opens held decisions: abort ONE non-energy build per
// sweep (the commander first) so its holder falls back into the market,
// where the stall-priced solar now wins. Held tasks are otherwise never
// re-asked -- the engine stops re-electing once a builder is in range
// (apexearth 2026-08-23: "interrupt that commander's action and switch to
// make a basic solar").
int gNextStallSweep = 0;

// Who the market sent to assist what. A guard on an IDLE factory is a
// locked builder doing nothing while mexes sit open (apexearth 2026-08-23);
// the sweep releases them the moment the boss has no work.
array<CCircuitUnit@> gGuardUnit;
array<CCircuitUnit@> gGuardBoss;
void GuardNote(CCircuitUnit@ u, CCircuitUnit@ boss)
{
	gGuardUnit.insertLast(u);
	gGuardBoss.insertLast(boss);
}
// Constructor escorts (apexearth 2026-08-23: "we need to escort our
// constructors with at least 1 grunt or better"). The market knows which
// workers are exposed; the military election asks here before pooling a
// unit. One escort per worker; entries drop when either party dies or the
// escort's task ends.
array<Id> gEscWorker;
array<Id> gEscUnit;
CCircuitUnit@ EscortNeeded(CCircuitUnit@ mil)
{
	if ((mil is null) || !gFarmSet)
		return null;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if ((wkr is null) || (wkr.task is null))
			continue;
		if (Catalog::gFlyer[int(wkr.circuitDef.id)])
			continue;   // air cons outrun ground escorts
		if (wkr.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;   // the commander is his own escort (apexearth)
		const float expo = wkr.GetPos(ai.frame).distance2D(gFarmPos)
				/ ((expoR > 1.f) ? expoR : 1200.f);
		if (expo < 0.5f)
			continue;
		bool has = false;
		for (uint e = 0; e < gEscWorker.length(); ++e) {
			if (gEscWorker[e] == wkr.id) {
				has = true;
				break;
			}
		}
		if (has)
			continue;
		// Only a NEARBY unit takes the duty: a cross-map death march
		// delivered 16 of 63 army losses as lone escorts (ladder autopsy).
		// A far worker's escort comes from the next unit produced closer,
		// or from its own raider demand (EscortShortfall).
		const float ms = Catalog::gSpeed[int(mil.circuitDef.id)];
		if ((ms > 1.f)
			&& (mil.GetPos(ai.frame).distance2D(wkr.GetPos(ai.frame)) / ms > 45.f))
			continue;
		gEscWorker.insertLast(wkr.id);
		gEscUnit.insertLast(mil.id);
		return wkr;
	}
	return null;
}
void EscortGone(Id id)
{
	for (uint e = 0; e < gEscWorker.length(); ) {
		if ((gEscWorker[e] == id) || (gEscUnit[e] == id)) {
			gEscWorker.removeAt(e);
			gEscUnit.removeAt(e);
			continue;
		}
		++e;
	}
}

void GuardSweep()
{
	for (uint i = 0; i < gGuardUnit.length(); ) {
		CCircuitUnit@ u = gGuardUnit[i];
		CCircuitUnit@ b = gGuardBoss[i];
		bool drop = (u is null) || (b is null) || (u.task is null)
			|| (int(u.task.GetBuildType()) != int(Task::BuildType::GUARD));
		if (!drop) {
			// A factory boss with nothing queued (and nothing in flight) is
			// idle: release the guard into the market.
			const bool bossIsFac = !b.circuitDef.IsMobile();
			if (bossIsFac && (b.CountQueued(null) == 0)) {
				u.task.Abort();
				drop = true;
			}
			// A mobile boss that stopped building releases its guards too.
			if (!bossIsFac && ((b.task is null)
					|| (b.task.GetType() != Task::Type::BUILDER))) {
				u.task.Abort();
				drop = true;
			}
		}
		if (drop) {
			gGuardUnit.removeAt(i);
			gGuardBoss.removeAt(i);
			continue;
		}
		++i;
	}
}

bool HardEStall()
{
	const float eInc = aiEconomyMgr.energy.income;
	const float eCur = aiEconomyMgr.energy.current;
	const float eStore = aiEconomyMgr.energy.storage;
	return (aiEconomyMgr.energy.pull > eInc)
		&& (eStore > 1.f) && (eCur < 0.25f * eStore);
}

// Builders known to the market: upserted as they pass through Decide (the
// commander included), dropped on death. CCircuitUnit is NOCOUNT -- every
// handle here MUST be removed by NoteDead or it dangles on freed memory.
array<CCircuitUnit@> gWorkers;
array<Id> gWorkerIds;
array<int> gWorkerBorn;   // first-seen frame: the age gate for reclaim
void WorkerSeen(CCircuitUnit@ u)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == u.id)
			return;
	}
	gWorkers.insertLast(u);
	gWorkerIds.insertLast(u.id);
	gWorkerBorn.insertLast(ai.frame);
}
void WorkerGone(Id id)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == id) {
			gWorkerBorn.removeAt(i);
			gWorkers.removeAt(i);
			gWorkerIds.removeAt(i);
			return;
		}
	}
}

//------------------------------------------------------------------------------
// THE ARMY MODEL -- one modeled quantity (value-paradigm): the army value
// worth standing. Insurance on what we own, plus matching what the enemy
// has been SEEN to field (a blind census reads low; the guard term is the
// floor that covers blindness).
//------------------------------------------------------------------------------

// Army value held in one role -- the portfolio sense. An army is role
// COVERAGE (apexearth: only ticks, pawns, rovers -- "where's the rest?");
// each next unit's gain diminishes by its role's share, so raiders
// saturate and the empty roles win the auction.
float RoleValue(int role)
{
	float v = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f))
			continue;
		if (Catalog::gRole[int(d)] == role)
			v += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
	return v;
}

// Role TARGETS from what the enemy fields (apexearth 2026-08-23: "balance
// the army based on our needs" -- siege wants range, soak wants HP, air
// wants AA). BAR's counter mechanics, priced: AA tracks enemy air, riot
// tracks enemy raiders, skirm/arty track enemy static, assault carries the
// general line. A uniform baseline keeps a portfolio before contact.
// Exposed workers without an escort -- each is standing demand for one
// cheap raider (apexearth: "a *need* is cheap escorts for cons").
int EscortShortfall()
{
	if (!gFarmSet)
		return 0;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	int n = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if ((wkr is null) || (wkr.task is null))
			continue;
		if (Catalog::gFlyer[int(wkr.circuitDef.id)])
			continue;
		if (wkr.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;   // the commander is his own escort
		if (wkr.GetPos(ai.frame).distance2D(gFarmPos)
				/ ((expoR > 1.f) ? expoR : 1200.f) < 0.5f)
			continue;
		bool has = false;
		for (uint e = 0; e < gEscWorker.length(); ++e) {
			if (gEscWorker[e] == wkr.id) {
				has = true;
				break;
			}
		}
		if (!has)
			++n;
	}
	return n;
}

float RoleTarget(int role, float armyTarget)
{
	// AA is a PURE COUNTER: it has no value without enemy air, so it gets
	// no baseline share (watched: AA against a ground-only 1v1 enemy).
	if (role == int(Unit::Role::AA.type)) {
		// FRESH air only (GetEnemyCost never forgets a plane once seen --
		// 25k of AA vs an enemy that quit flying, watched 8v8), and OUR
		// SHARE of the team's counter: the census sums all enemies while
		// every ally instance would otherwise build the full answer.
		const float team = Military::TeamArmyCost();
		const float mine = aiMilitaryMgr.armyCost;
		const float share = (team > mine && team > 1.f) ? (mine / team) : 1.f;
		return aiEnemyMgr.GetEnemyCostFresh(RT::AIR)
				* ai.GetTunable("apex_aa_match", TUNE_AA_MATCH) * share;
	}
	const float base = armyTarget / 6.f;   // maximum-entropy prior over combat roles
	float counter = 0.f;
	if (role == int(Unit::Role::RAIDER.type))
		counter = float(EscortShortfall()) * 60.f   // ~ one cheap escort each
			+ (Military::EnemyCostOf(Unit::Role::SKIRM.type)
				+ Military::EnemyCostOf(Unit::Role::ARTY.type)) * 0.6f;
			// rocket bots die to what closes fast (apexearth's counter-chain)
	else if (role == int(Unit::Role::RIOT.type))
		counter = Military::EnemyCostOf(Unit::Role::RAIDER.type);
	else if ((role == int(Unit::Role::SKIRM.type))
			|| (role == int(Unit::Role::ARTY.type)))
		counter = aiEnemyMgr.GetEnemyCost(RT::STATIC) * 0.5f;
	else if (role == int(Unit::Role::ASSAULT.type))
		counter = Military::EnemyCostOf(Unit::Role::ASSAULT.type);
	return base + counter;
}

// The production appetite one standing line carries, metal/s -- what a
// factory's existence is WORTH beyond expansion, what its nano ring must
// absorb, and what an assist bid against it can earn. (Watched: a lab
// killed by artillery never rebuilt -- the plant want only priced open
// spots; and hot lines ran on one nano with no help.)
float LineSpend()
{
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float gap = ArmyTarget() - ArmyValue();
	float s = (gap > 0.f) ? (gap / ((fillS > 1.f) ? fillS : 180.f)) : 0.f;
	const float ovf = OverflowM();
	if (ovf > s)
		s = ovf;
	const int lines = (Factory::gFactoryCount > 0) ? Factory::gFactoryCount : 1;
	return s / float(lines);
}

float ArmyValue()
{
	float v = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f)
			|| Catalog::gKamikaze[int(d)])
			continue;
		v += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
	return v;
}

// THE REAR SPECIALIST (apexearth 2026-08-23): in a big team game one
// player starts obviously farther from the enemy than everyone else.
// Fighting from there wastes walk time; scaling from there compounds.
// That player suppresses the army market -- the freed spend rides the
// existing eco ladder to fusions/AFUS/gantry -- and its late army budget
// carries a QUALITY bias so it buys the biggest units its labs offer
// (T3, heavy air) instead of T1/T2 it would never deliver in time.
// Election: allies' homes off the team blackboard; the enemy reference is
// the ally centroid mirrored through map center (symmetric starts, no
// sighting needed). Rear-most wins only with a clear margin over #2.
bool gEcoRole = false;
bool gEcoDiagDone = false;
int gEcoRoleAt = -999999;
bool EcoRoleActive()
{
	if (ai.frame < gEcoRoleAt + 10 * SECOND)
		return gEcoRole;
	gEcoRoleAt = ai.frame;
	EcoStatusLog();
	const bool was = gEcoRole;
	gEcoRole = false;
	if (!Builder::gHomeSet)
		return false;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 4))
		return false;
	array<float> hx, hz;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const float x = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float z = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		hx.insertLast(x);
		hz.insertLast(z);
		cx += x;
		cz += z;
	}
	if (hx.length() < 4)
		return false;
	cx /= float(hx.length());
	cz /= float(hx.length());
	const float ex = float(AiTerrainWidth()) - cx;
	const float ez = float(AiTerrainHeight()) - cz;
	gEcoRefX = ex;
	gEcoRefZ = ez;
	array<float> ds;
	float d1 = 0.f;
	for (uint i = 0; i < hx.length(); ++i) {
		const float dx = hx[i] - ex;
		const float dz = hz[i] - ez;
		const float dd = dx * dx + dz * dz;
		ds.insertLast(dd);
		if (dd > d1)
			d1 = dd;
	}
	ds.sortAsc();
	const float dmed = ds[ds.length() / 2];
	const float mx = Builder::gHomePos.x - ex;
	const float mz = Builder::gHomePos.z - ez;
	const float mine = mx * mx + mz * mz;
	const float margin = ai.GetTunable("apex_eco_rear_margin", TUNE_ECO_REAR_MARGIN);
	gEcoRole = (mine >= d1) && (dmed > 1.f) && (mine >= dmed * margin * margin);
	if (!gEcoDiagDone) {
		gEcoDiagDone = true;
		AiLog("apex: rear-elect homes=" + hx.length() + " mine=" + sqrt(mine)
				+ " far=" + sqrt(d1) + " median=" + sqrt(dmed));
	}
	if (gEcoRole != was) {
		AiLog("apex: rear-specialist " + (gEcoRole ? "ON" : "off")
				+ " team=" + ai.teamId
				+ " mine=" + sqrt(mine) + " median=" + sqrt(dmed));
		// A chat line survives on screen; log lines scroll away (apexearth).
		ai.SendChat(gEcoRole
				? ("I am the eco specialist (team " + ai.teamId
					+ ", rear position): scaling economy, no army until T3.")
				: ("Eco specialist role off (team " + ai.teamId + ")."));
	}
	return gEcoRole;
}

// The specialist's exemption ends when the war reaches it: a KNOWN front
// inside the safe radius restores every normal response.
// Danger is ENEMY AT THE DOOR, not geometry: front-line distance read
// structurally true in a packed team box (audited: the exempted specialist
// built 8.6k army, 510 defence, teched LAST -- quiet mode never engaged).
// Sustained presence arms danger; one clear read disarms. A single plane
// overflight flipped quiet mode for one refresh and bought dragon-claw
// towers at 13m (audited flicker -- danger=0 at every 2-min sample).
int gEcoDangerStreak = 0;
int gEcoDangerTickAt = 0;
bool gEcoDangerArmed = false;
bool EcoDangerNear()
{
	if (!Builder::gHomeSet)
		return false;
	// The streak ticks on a CLOCK, not per call -- EcoQuiet runs many
	// times per decide sweep, so a per-call streak armed in one frame off
	// a single overflight (claw at 4.8m with danger=0 at every sample).
	if (ai.frame >= gEcoDangerTickAt) {
		gEcoDangerTickAt = ai.frame + 10 * SECOND;
		const bool hot = ai.GetEnemyCostAt(Builder::gHomePos,
					ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R))
				> ai.GetTunable("apex_eco_danger_m", TUNE_ECO_DANGER_M);
		gEcoDangerStreak = hot ? (gEcoDangerStreak + 1) : 0;
		const bool armed = gEcoDangerStreak >= 3;   // 30s sustained
		if (armed != gEcoDangerArmed)
			AiLog("apex: eco-danger " + (armed ? "ARMED" : "cleared")
					+ " team=" + ai.teamId + " f=" + ai.frame);
		gEcoDangerArmed = armed;
	}
	return gEcoDangerArmed;
}

bool EcoQuiet()
{
	return EcoRoleActive() && !EcoDangerNear();
}

// The specialist works from home: any job farther than the leash is
// someone else's (apexearth: "keep our eco cons at home... not walking
// across the map").
bool EcoFar(const AIFloat3& in p)
{
	return EcoQuiet() && Builder::gHomeSet
		&& (p.distance2D(Builder::gHomePos)
			> ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH));
}

int gEcoStatusAt = 0;
void EcoStatusLog()
{
	if (!gEcoRole || (ai.frame < gEcoStatusAt))
		return;
	gEcoStatusAt = ai.frame + 120 * SECOND;
	AiLog("apex: eco-status team=" + ai.teamId
			+ " danger=" + (EcoDangerNear() ? 1 : 0)
			+ " foeNear=" + ai.GetEnemyCostAt(Builder::gHomePos,
					ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R))
			+ " bank=" + aiEconomyMgr.metal.current
			+ " inc=" + aiEconomyMgr.metal.income);
}

float ArmyTarget()
{
	// The SYMMETRIC PRIOR: pre-contact the census is blind, and blind read
	// as safe lost the first BARb game with three army units built. The
	// enemy's economy mirrors ours from the same start, so expect their
	// army to be a share of OUR total value until seen otherwise; the
	// observed census takes over as it grows past the prior.
	const float ourTotal = gAssetsM + ArmyValue();
	const float prior = ourTotal * ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	const float seen = Military::EnemyArmyCost();
	const float expectedEnemy = (seen > prior) ? seen : prior;
	const float t = gAssetsM * ai.GetTunable("apex_guard_rate", TUNE_GUARD_RATE)
		+ expectedEnemy * ai.GetTunable("apex_match_ratio", TUNE_MATCH_RATIO);
	return EcoRoleActive()
			? (t * ai.GetTunable("apex_eco_army_mul", TUNE_ECO_ARMY_MUL)) : t;
}

// The target with NO role suppression: what the war actually asks for.
// The gantry want reads this one -- T3 is exactly what the eco role is FOR.
float ArmyTargetFull()
{
	const float ourTotal = gAssetsM + ArmyValue();
	const float prior = ourTotal * ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	const float seen = Military::EnemyArmyCost();
	const float expectedEnemy = (seen > prior) ? seen : prior;
	return gAssetsM * ai.GetTunable("apex_guard_rate", TUNE_GUARD_RATE)
		+ expectedEnemy * ai.GetTunable("apex_match_ratio", TUNE_MATCH_RATIO);
}

// Own combat losses, decaying -- wrecks on the field are rez-bot demand.
float gLossPool = 0.f;
int gLossDecayAt = 0;
void LossNote(int defId)
{
	if (Catalog::gMobile[defId] && !Catalog::gBuilder[defId]
		&& (Catalog::gPower[defId] > 1.f))
	{
		gLossPool += Catalog::gCostM[defId];
	}
}
void LossDecay()
{
	if (ai.frame < gLossDecayAt + 10 * SECOND)
		return;
	gLossDecayAt = ai.frame;
	gLossPool *= 0.95f;   // wrecks get reclaimed, rezzed, or destroyed
}

// Round-robin over owned ceiling-reaching cons, for the guard floor-want.
uint gServeIdx = 0;
CCircuitUnit@ NextServingCon()
{
	const float ceilX = BestExtract();
	array<CCircuitUnit@> serving;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if (u is null)
			continue;
		const array<int>@ b = Catalog::BuildsOf(int(u.circuitDef.id));
		for (uint q = 0; q < b.length(); ++q) {
			if (Catalog::gExtractsM[b[q]] >= ceilX) {
				serving.insertLast(u);
				break;
			}
		}
	}
	if (serving.length() == 0)
		return null;
	gServeIdx = (gServeIdx + 1) % serving.length();
	return serving[gServeIdx];
}

// Fraction of known workers actually holding work. Idle cons mean labs and
// more cons are OVER-valued -- capability nobody uses is not capability
// (apexearth 2026-08-23: "we have cons we aren't even using so the value of
// making labs is over-estimated").
float Utilization()
{
	if (gWorkers.length() == 0)
		return 1.f;
	int busy = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u !is null) && (u.task !is null))
			++busy;
	}
	return float(busy) / float(gWorkers.length());
}

// Retreat pays only if the survivor gets HEALED: thresholds rise with the
// rez/repair fleet (apexearth: "we stay in the fight until death" + "rez
// bots heal our troops -- they make a big difference" -- the two are one
// design). Refreshed here as the fleet changes.
int gNextRetreatRefresh = 0;
void RetreatRefresh()
{
	if (ai.frame < gNextRetreatRefresh)
		return;
	gNextRetreatRefresh = ai.frame + 15 * SECOND;
	int rezzers = 0;
	for (uint d2 = 1; d2 < gOwnCount.length(); ++d2) {
		if ((gOwnCount[d2] > 0) && Catalog::gRezzer[int(d2)])
			rezzers += gOwnCount[d2];
	}
	float healBonus = 0.05f * float(rezzers);
	if (healBonus > 0.25f)
		healBonus = 0.25f;
	const float scale = ai.GetTunable("apex_retreat_cost_scale", TUNE_RETREAT_COST_SCALE);
	for (Id rd = 1; rd <= Id(Catalog::gDefCount); ++rd) {
		const int ri = int(rd);
		if (!Catalog::gMobile[ri] || Catalog::gBuilder[ri]
			|| (Catalog::gPower[ri] <= 1.f) || Catalog::gKamikaze[ri]
			|| Catalog::gRezzer[ri])
			continue;
		CCircuitDef@ rdef = ai.GetCircuitDef(rd);
		if (rdef is null)
			continue;
		float rt = 0.08f + Catalog::gCostM[ri] / ((scale > 1.f) ? scale : 3000.f)
				+ healBonus;
		if (rt > 0.55f)
			rt = 0.55f;
		rdef.SetRetreat(rt);
	}
}

void StallWatch()
{
	if (ai.frame < gNextStallSweep)
		return;
	gNextStallSweep = ai.frame + 5 * SECOND;
	RetreatRefresh();
	GuardSweep();
	if (!HardEStall())
		return;
	CCircuitUnit@ pick = null;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if (u is null)
			continue;
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::BUILDER))
			continue;
		if (int(t.GetBuildType()) == int(Task::BuildType::ENERGY))
			continue;
		// (guard/patrol holders pass straight through: their work is worth
		// ~nothing mid-stall, so the dry-run below decides.)
		// Only interrupt a unit that could actually answer with energy.
		bool canE = false;
		const array<int>@ mine = Catalog::BuildsOf(int(u.circuitDef.id));
		for (uint b = 0; b < mine.length(); ++b) {
			if (Catalog::gMakeE[mine[b]] > 1.f) {
				canE = true;
				break;
			}
		}
		if (!canE)
			continue;
		// Dry-run the market (proposers are pure): interrupt only a unit
		// whose TOP want right now is energy -- a blind abort thrashed 73
		// times in one game, re-deciding the same mex it left.
		Want@ e = ProposeEnergy(u);
		if ((e is null) || (e.value <= 0.f))
			continue;
		Want@ mx = ProposeMex(u);
		if ((mx !is null) && (mx.value > e.value))
			continue;
		@pick = u;
		if (u.circuitDef.GetName() == "armcom" || u.circuitDef.GetName() == "corcom")
			break;   // the commander first when present
	}
	if (pick is null)
		return;
	AiLog("apex: STALL interrupt -- " + pick.circuitDef.GetName() + " #" + pick.id
		+ " leaves its build to answer the energy stall");
	pick.task.Abort();
}

// Obsolete generators price their own metal back into the market: when the
// E economy is structurally in surplus (removing the candidate keeps it so)
// and the bank has room for the burst, a weak generator's banked metal
// beats its trickle. Weakest first (lowest makeE per metal).
CCircuitUnit@ gReclaimTarget = null;
CCircuitUnit@ gAssistTarget = null;

// Standing defense metal near a point -- the crowding divisor that makes
// a 247-LLT carpet impossible (apexearth's screenshot: the whole eco lost
// to in-base turret sprawl).
float DefCrowdM(const AIFloat3& in pos, float r)
{
	float m = 0.f;
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		if (gProtPos[PROT_DEF][i].distance2D(pos) < r)
			m += Catalog::gCostM[gProtDefId[PROT_DEF][i]];
	}
	return m;
}

bool ProtCovered(int cls, const AIFloat3& in pos, float r)
{
	for (uint i = 0; i < gProtPos[cls].length(); ++i) {
		if (pos.distance2D(gProtPos[cls][i]) < r)
			return true;
	}
	return false;
}

// Insurance pricing: protection is worth a fraction of the assets it
// covers, per second of exposure. ONE modeled rate for eyes and turrets,
// one for the nuke risk (value-paradigm: a single named quantity each).
// Timing EMERGES: at 5k assets an anti-nuke prices at ~0.4 and loses; at
// 100k it prices at ~8 and wins.
Want@ ProposeProtect(CCircuitUnit@ unit)
{
	Want w;
	if (!gFarmSet || (gAssetsM < 1.f))
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const float rate = ai.GetTunable("apex_insure_rate", TUNE_INSURE_RATE);
	const float nukeRate = ai.GetTunable("apex_nuke_risk", TUNE_NUKE_RISK);
	const AIFloat3 core = gFarmPos;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		const int cls = ProtClassOf(d);
		if (cls < 0)
			continue;
		float gain = 0.f;
		AIFloat3 at = core;
		if (cls == PROT_RADAR) {
			if (ProtCovered(PROT_RADAR, core, Catalog::gRadarR[d] * 0.8f))
				continue;
			// Eyes for the army too: blind units chase shadows (apexearth:
			// "build radars so our units have intelligence").
			gain = (gAssetsM + ArmyValue()) * rate;
		} else if (cls == PROT_JAM) {
			// Tower concentrations want jamming first (apexearth): find a
			// cluster of >=3 defenses with no jammer in reach.
			AIFloat3 jat = core;
			bool found = false;
			for (uint jd = 0; jd < gProtPos[PROT_DEF].length() && !found; ++jd) {
				int nearDef = 0;
				for (uint jk = 0; jk < gProtPos[PROT_DEF].length(); ++jk) {
					if (gProtPos[PROT_DEF][jd].distance2D(gProtPos[PROT_DEF][jk]) < 300.f)
						++nearDef;
				}
				if ((nearDef >= 3)
					&& !ProtCovered(PROT_JAM, gProtPos[PROT_DEF][jd],
							Catalog::gJamR[d] * 0.8f))
				{
					jat = gProtPos[PROT_DEF][jd];
					found = true;
				}
			}
			if (!found && ProtCovered(PROT_JAM, core, Catalog::gJamR[d] * 0.8f))
				continue;
			at = found ? jat : core;
			gain = gAssetsM * rate * (found ? 0.8f : 0.5f);
		} else if (cls == PROT_ANTINUKE) {
			if (ProtCovered(PROT_ANTINUKE, core, 2000.f))
				continue;
			gain = gAssetsM * nukeRate;
		} else if (cls == PROT_SHIELD) {
			// Shields answer bombardment: worth the arty mass they blank,
			// covering the interior (the stock feature our gap survey ranked
			// first; their arty ground our statics 38k:7k).
			const float artyS = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f;
			if (artyS < 200.f)
				continue;
			// ...and only when a threat is actually NEAR: a global arty
			// census bought shield stacks in a base nothing could reach
			// (apexearth: "too many shields while theres still no threat
			// very close"). The bombardier must be within twice its reach
			// of what the shield would cover.
			if (ai.GetEnemyCostAt(core, 1800.f) < 200.f)
				continue;
			if (ProtCovered(PROT_SHIELD, core, 400.f))
				continue;
			gain = ((artyS < gAssetsM) ? artyS : gAssetsM) * rate * 4.f;
		} else if (cls == PROT_TARGFAC) {
			// apexearth's spec: three wanted, diminishing.
			const int have = int(gProtPos[PROT_TARGFAC].length());
			const int want3 = int(ai.GetTunable("apex_targfac_want", TUNE_TARGFAC_WANT));
			if (have >= want3)
				continue;
			gain = gAssetsM * rate * float(want3 - have) / float(want3);
		} else if (cls == PROT_DEF) {
			// The quiet rear needs none of this (apexearth: "loads of
			// defence buildings -- none of which we needed").
			if (EcoQuiet())
				continue;
			// AN UNCOVERED HIGH-VALUE STRUCTURE FIRST: its whole investment
			// is the stake, wherever it stands.
			{
				CCircuitUnit@ big = null;
				float bigV = 0.f;
				for (uint bg = 0; bg < gOwnBig.length(); ++bg) {
					CCircuitUnit@ b2 = gOwnBig[bg];
					if (b2 is null)
						continue;
					const float bv = Catalog::gCostM[int(b2.circuitDef.id)];
					if ((bv > bigV)
						&& !ProtCovered(PROT_DEF, b2.GetPos(ai.frame), 420.f))
					{
						bigV = bv;
						@big = b2;
					}
				}
				if (big !is null) {
					at = big.GetPos(ai.frame);
					const float lossH3 = ai.GetTunable("apex_exposed_loss_s",
							TUNE_EXPOSED_LOSS_S);
					gain = bigV * 0.6f / ((lossH3 > 1.f) ? lossH3 : 120.f);
				}
			}
			if (gain > 0.f) {
				Want cb;
				const float spb = Catalog::gSpeed[uid];
				const float wkb = (spb > 1.f)
						? (unit.GetPos(ai.frame).distance2D(at) / spb) : 60.f;
				ValueOf(d, gain, wkb, Catalog::gBuildPower[uid], cb);
				if (cb.value > w.value) {
					w = cb;
					w.kind = WK_PROTECT;
					@w.def = Catalog::Def(d);
					w.pos = at;
					w.spotId = cls;
				}
				continue;
			}
			// THE FRONTLINE CHOKE is the primary defense destination
			// (apexearth: "defend the enemy pathway to us, not so much
			// within our base" -- 247 in-base LLTs lost the eco war). The
			// wave-meet target lives just BEHIND the choke lip; crowding
			// divides so the line matures instead of carpeting.
			if (Base::gAnchorSet) {
				AIFloat3 cp;
				if (Front::FrontChoke(Base::gAnchor, cp)) {
					AIFloat3 site;
					if (!Front::BehindChoke(cp, 180.f, site))
						site = cp;
					if (OnMap(site)) {
						const float standingM = DefCrowdM(site, 500.f);
						const float meetM = Military::FoeMobileMassing()
								* ai.GetTunable("apex_wave_meet", TUNE_WAVE_MEET)
								+ gAssetsM * rate * 300.f;
						const float gapM = meetM - standingM;
						if (gapM > 0.f) {
							gain = (gapM / 300.f)
									/ (1.f + DefCrowdM(site, 350.f) / 500.f);
							at = site;
						}
					}
				}
			}
			if (gain > 0.f) {
				const float rr2 = (Catalog::gMaxRange[d] < 900.f)
						? Catalog::gMaxRange[d] : 900.f;
				const float rn2 = rr2 / 500.f;
				gain *= Catalog::gPower[d] * (1.f + rn2 * rn2 * 0.5f)
						/ ((Catalog::gCostM[d] > 1.f) ? Catalog::gCostM[d] : 1.f)
						* 12.f;
				Want cf;
				const float spf = Catalog::gSpeed[uid];
				const float wkf = (spf > 1.f)
						? (unit.GetPos(ai.frame).distance2D(at) / spf) : 60.f;
				ValueOf(d, gain, wkf, Catalog::gBuildPower[uid], cf);
				if (cf.value > w.value) {
					w = cf;
					w.kind = WK_PROTECT;
					@w.def = Catalog::Def(d);
					w.pos = at;
					w.spotId = cls;
				}
				continue;
			}
			// EXPOSED NAKED MEXES FIRST: they die on a 120s clock while the
			// home cluster grew DOZENS of turrets (watched) -- the old
			// metal->power conversion never closed the wave gap. Everything
			// below is in METAL on both sides.
			int nakedFirst = -1;
			float worstExpoF = 0.f;
			for (uint lf = 0; lf < gLSpot.length(); ++lf) {
				if (gLExtract[lf] <= 0.f)
					continue;
				if (ProtCovered(PROT_DEF, gLPos[lf], 400.f))
					continue;
				const float exR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
				float ex = gLPos[lf].distance2D(core) / ((exR > 1.f) ? exR : 1200.f);
				if (ex > 1.f)
					ex = 1.f;
				if ((ex > 0.5f) && (ex > worstExpoF)) {
					worstExpoF = ex;
					nakedFirst = int(lf);
				}
			}
			if (nakedFirst >= 0) {
				at = gLPos[nakedFirst];
				const float lossH2 = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
				gain = (620.f + Catalog::gCostM[d]) * worstExpoF
						/ ((lossH2 > 1.f) ? lossH2 : 120.f);
			} else if (Base::gAnchorSet && Base::gAxisSet) {
				const AIFloat3 front = Base::gAnchor + Base::gFwd * 150.f;
				const AIFloat3 rear = gFarmPos - Base::gFwd * (gFarmDepth + 150.f);
				float standingM = 0.f;
				for (uint sd = 0; sd < gProtUnit[PROT_DEF].length(); ++sd) {
					if ((gProtUnit[PROT_DEF][sd] !is null)
						&& (gProtPos[PROT_DEF][sd].distance2D(front) < 600.f))
						standingM += Catalog::gCostM[gProtDefId[PROT_DEF][sd]];
				}
				const float waveGapM = Military::FoeMobileMassing()
						* ai.GetTunable("apex_wave_meet", TUNE_WAVE_MEET) - standingM;
				if (OnMap(front) && !ProtCovered(PROT_DEF, front, 450.f)) {
					at = front;
					gain = gAssetsM * rate
							/ (1.f + DefCrowdM(front, 350.f) / 500.f);
				} else if (!ProtCovered(PROT_DEF, rear, 450.f) && OnMap(rear)) {
					at = rear;
					gain = gAssetsM * rate * 0.7f
							/ (1.f + DefCrowdM(rear, 350.f) / 500.f);
				}
			}
			if (gain > 0.f) {
				Want c0;
				const float sp0 = Catalog::gSpeed[uid];
				const float wk0 = (sp0 > 1.f)
						? (unit.GetPos(ai.frame).distance2D(at) / sp0) : 60.f;
				ValueOf(d, gain, wk0, Catalog::gBuildPower[uid], c0);
				if (c0.value > w.value) {
					w = c0;
					w.kind = WK_PROTECT;
					@w.def = Catalog::Def(d);
					w.pos = at;
					w.spotId = cls;
				}
				continue;
			}
			// A standing mex without a turret in reach: insure the ground,
			// priced by EXPOSURE (apexearth 2026-08-23: against a real
			// opponent an unguarded outlying mex "is almost guaranteed to
			// die"; the core sits under implicit army cover). The most
			// exposed naked spot is the want.
			int naked = -1;
			float worstExpo = 0.f;
			for (uint li = 0; li < gLSpot.length(); ++li) {
				if (gLExtract[li] <= 0.f)
					continue;
				if (ProtCovered(PROT_DEF, gLPos[li], 400.f))
					continue;
				const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
				float expo = gLPos[li].distance2D(core)
						/ ((expoR > 1.f) ? expoR : 1200.f);
				if (expo > 1.f)
					expo = 1.f;
				if (expo < 0.2f)
					expo = 0.2f;   // even the core is not free
				if (expo > worstExpo) {
					worstExpo = expo;
					naked = int(li);
				}
			}
			if (naked < 0)
				continue;
			at = gLPos[naked];
			// Expected loss stream: the asset's value over the loss horizon,
			// scaled by exposure. One modeled horizon.
			const float lossH = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
			gain = (620.f + Catalog::gCostM[d]) * worstExpo
					/ ((lossH > 1.f) ? lossH : 300.f);
		}
		if (gain <= 0.f)
			continue;
		// TURRET QUALITY: "range is the difference between whether or not
		// you can get sieged" (apexearth) -- a static cannot reposition, so
		// reach IS survival. Quality = power x (1 + (reach/500)^2 * 0.5),
		// reach capped at the 900 band (the Ragnarok lesson); the flat
		// insurance gain scales by quality-per-best, so beamers and HLTs
		// outbid massed LLTs on the raw numbers.
		if (cls == PROT_DEF) {
			// The SECOND pass ran unguarded: exposed-mex insurance kept
			// buying claws on the quiet rear after every first-pass gate
			// (the recurring 340-680 audit fail, finally attributed).
			if (EcoQuiet())
				continue;
			const float rr = (Catalog::gMaxRange[d] < 900.f)
					? Catalog::gMaxRange[d] : 900.f;
			const float rn = rr / 500.f;
			float qual = Catalog::gPower[d] * (1.f + rn * rn * 0.5f);
			const float artySeen = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type);
			if (artySeen > 100.f) {
				qual *= 1.f + (rr / 500.f)
						* ((artySeen < 3000.f) ? (artySeen / 3000.f) : 1.f);
			}
			gain *= qual / ((Catalog::gCostM[d] > 1.f) ? Catalog::gCostM[d] : 1.f)
					* 12.f;   // normalize: T1-turret power/cost ~ 1/12
		}
		Want c;
		const float speed = Catalog::gSpeed[uid];
		const float walkSec = (speed > 1.f)
				? (unit.GetPos(ai.frame).distance2D(at) / speed) : 60.f;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PROTECT;
			@w.def = Catalog::Def(d);
			w.pos = at;
			w.spotId = cls;
		}
	}
	return w;
}

// Assisting T2+ work is a PRICED want, not an idleness fallback (apexearth
// 2026-08-23: "T1 cons are still not assisting T2 cons, helping build T2+
// buildings, or assisting factories"). A joiner transfers its whole drain
// into a build the market already values at clearing rates; the bill is
// the walk and the occupied time. That beats a marginal solar and loses to
// a fresh mex -- the right ordering by construction.
Want@ ProposeAssist(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	// Only lesser cons assist upward; ceiling cons do the T2 work itself.
	float myCeil = 0.f;
	const array<int>@ mine = Catalog::BuildsOf(uid);
	for (uint i = 0; i < mine.length(); ++i) {
		if (Catalog::gExtractsM[mine[i]] > myCeil)
			myCeil = Catalog::gExtractsM[mine[i]];
	}
	if (myCeil >= BestExtract())
		return w;
	// A worker BUILDING BUILD POWER is the best boss there is: BP
	// compounds, and the first nano crawling up under one lathe delays
	// everything behind it (apexearth). Then serving cons, then factories.
	CCircuitUnit@ boss = null;
	// A worker raising a FACTORY outranks everything -- one con on the T2
	// plant was the measured bottleneck (apexearth: "we are more efficient
	// when we assist building some things").
	for (uint bf = 0; bf < gWorkers.length(); ++bf) {
		CCircuitUnit@ wf = gWorkers[bf];
		if ((wf is null) || (wf.task is null) || (wf.id == unit.id))
			continue;
		if (EcoFar(wf.GetPos(ai.frame)))
			continue;
		if ((wf.task.GetType() == Task::Type::BUILDER)
			&& (int(wf.task.GetBuildType()) == int(Task::BuildType::FACTORY))) {
			@boss = wf;
			break;
		}
	}
	for (uint bi = 0; (boss is null) && (bi < gWorkers.length()); ++bi) {
		CCircuitUnit@ wb = gWorkers[bi];
		if ((wb is null) || (wb.task is null) || (wb.id == unit.id))
			continue;
		if (EcoFar(wb.GetPos(ai.frame)))
			continue;
		if (wb.task.GetType() != Task::Type::BUILDER)
			continue;
		if (int(wb.task.GetBuildType()) == int(Task::BuildType::NANO)) {
			@boss = wb;
			break;
		}
	}
	if (boss is null)
		@boss = NextServingCon();
	if ((boss !is null) && ((boss.task is null)
			|| (boss.task.GetType() != Task::Type::BUILDER)))
		@boss = null;
	if (boss is null) {
		for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
			CCircuitUnit@ f = Brain::gFQFac[i];
			if ((f !is null) && (f.CountQueued(null) > 0)) {
				@boss = f;
				break;
			}
		}
	}
	if (boss is null)
		return w;
	// A lathe cannot draw without energy: assist delivers its drain TIMES
	// what the E economy can feed it (measured stall: lab -> mex -> assist
	// while solar lost the auction at a drained bank; the assist was
	// worthless and blocking the fix).
	float eFeed = 1.f;
	if (HardEStall()) {
		eFeed = 0.1f;
	} else {
		const float eInc = aiEconomyMgr.energy.income;
		const float ePull = aiEconomyMgr.energy.pull;
		if ((ePull > 1.f) && (eInc < ePull))
			eFeed = eInc / ePull;
	}
	float myDrain = Catalog::gBuildPower[uid] * (7.f / 80.f) * eFeed;
	// THE METAL TWIN of eFeed above, and the missing half of the temporal
	// law: an assist delivers at most the flow the economy has unspent.
	// gain=myDrain at mCost=1 bid in the hundreds at a fed site, which is
	// how com + 3 cons all fed a 5-minute T2 lab while 2 safe mexes sat
	// open (apexearth's 10 m/s arithmetic). At zero free flow the want
	// dies and the mex claims win the room.
	{
		const float mFree = FreeMetalFlow();
		if (mFree < myDrain)
			myDrain = mFree;
	}
	if (myDrain <= 0.05f)
		return w;
	// Against a factory boss the bid is bounded by what the line actually
	// leaves unserved -- and floored at a trickle so SOME help arrives.
	if ((boss !is null) && !boss.circuitDef.IsMobile()) {
		const float u = UnservedLineSpend();
		if (u < myDrain)
			myDrain = (u > 1.f) ? u : 1.f;
	}
	const AIFloat3 bp = boss.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(bp) / speed) : 60.f;
	w.kind = WK_ASSIST;
	w.pos = bp;
	w.spotId = int(boss.id);
	w.gain = myDrain;
	w.mCost = 1.f;
	w.tCost = (walkSec + 60.f) * Wage();   // one guard stint
	w.value = w.gain / (w.mCost + w.tCost);
	@gAssistTarget = boss;
	return w;
}

Want@ ProposeReclaimObsolete(CCircuitUnit@ unit)
{
	Want w;
	// SURPLUS CONS (apexearth: "made too many t1 cons... we should reclaim
	// them"): the quiet rear with no claimable safe ground and no BP
	// deficit turns constructor metal back into ladder money. Only a con a
	// standing factory could re-make (never the commander), cheapest
	// first; BPGap turning positive stops the next one -- self-balancing.
	// ...and only once the SUCCESSOR fleet exists: reclaiming the claim
	// fleet before any ceiling con stands starved the ladder that was
	// supposed to replace it (seed 23: cons cut to the floor by 10m, T2
	// lab at 12.3m). Same law as generator reclaim -- obsolescence is
	// RELATIVE efficiency, and nothing is obsolete before its better.
	if (EcoQuiet() && !gMexOpen && (BPGap() <= 0.f) && (ServingCons() > 0)) {
		// Only a LESSER con spends its time on this: a ceiling con
		// reclaiming T1s traded scaling time for tidying (watched --
		// "T2 cons immediately try reclaiming T1 cons").
		bool lesser = true;
		{
			const array<int>@ mine0 = Catalog::BuildsOf(int(unit.circuitDef.id));
			for (uint mi = 0; mi < mine0.length(); ++mi) {
				if (Catalog::gExtractsM[mine0[mi]] >= BestExtract()) {
					lesser = false;
					break;
				}
			}
		}
		CCircuitUnit@ rc = null;
		int rcDef = -1;
		int landCons = 0;
		for (uint wi = 0; lesser && (wi < gWorkers.length()); ++wi) {
			CCircuitUnit@ wu = gWorkers[wi];
			if ((wu is null) || (wu is unit))
				continue;
			const int wd = int(wu.circuitDef.id);
			// Air cons are exempt: no pathing cost, no placement blocking
			// (apexearth) -- and land cons below the keep-floor stay for
			// nano work. A JUST-BUILT con is never eaten: reclaiming what
			// we paid buildtime for minutes ago is churn, not tidying.
			if (Catalog::gFlyer[wd])
				continue;
			if ((wi < gWorkerBorn.length()) && (ai.frame - gWorkerBorn[wi]
					< int(ai.GetTunable("apex_reclaim_age_s", TUNE_RECLAIM_AGE_S)) * SECOND))
				continue;
			bool remake = false;
			for (uint fi = 0; fi < Factory::gFacUnits.length() && !remake; ++fi) {
				if (Factory::gFacUnits[fi] is null)
					continue;
				const array<int>@ fb = Catalog::BuildsOf(
						int(Factory::gFacUnits[fi].circuitDef.id));
				for (uint q = 0; q < fb.length(); ++q) {
					if (fb[q] == wd) {
						remake = true;
						break;
					}
				}
			}
			if (!remake)
				continue;
			++landCons;
			if ((rcDef < 0) || (Catalog::gCostM[wd] < Catalog::gCostM[rcDef])) {
				@rc = wu;
				rcDef = wd;
			}
		}
		if ((rc !is null)
			&& (float(landCons) > ai.GetTunable("apex_eco_con_keep", TUNE_ECO_CON_KEEP))) {
			const float hz0 = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
			w.kind = WK_RECLAIM;
			@w.def = Catalog::Def(rcDef);
			w.pos = rc.GetPos(ai.frame);
			w.spotId = int(rc.id);
			w.gain = Catalog::gCostM[rcDef] / ((hz0 > 1.f) ? hz0 : 300.f);
			w.mCost = 1.f;
			w.tCost = (Catalog::gCostM[rcDef] / 90.f) * Wage();
			w.value = w.gain / (w.mCost + w.tCost);
			@gReclaimTarget = rc;
			return w;
		}
	}
	// PADDING (apexearth 2026-08-23): reclaim when both banks have cushion
	// -- rich enough that the trickle is noise, with room for the refund
	// burst. Obsolescence is RELATIVE efficiency: for generators the metric
	// is E per CELL of ground (his ladder: solar 1.25, advsol 3, fusion
	// ~20, AFUS ~37 -- "eventually we need physical space"); for defences
	// it is the def's power under a far stronger neighbor's umbrella.
	const float st = aiEconomyMgr.metal.storage;
	if (st <= 1.f)
		return w;
	const float bankFrac = aiEconomyMgr.metal.current / st;
	if ((bankFrac < 0.3f) || (bankFrac > 0.85f))
		return w;
	const float ratio = ai.GetTunable("apex_obsolete_ratio", TUNE_OBSOLETE_RATIO);
	const float eFree = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
	CCircuitUnit@ best = null;
	int bestDef = -1;
	float bestScore = 1e9f;
	// Generators, worst E-per-cell first, only when dwarfed by the best.
	float ownBestEcell = 0.f;
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null)
			continue;
		const int d = int(gOwnGen[i].circuitDef.id);
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ec > ownBestEcell)
			ownBestEcell = ec;
	}
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		CCircuitUnit@ g = gOwnGen[i];
		if (g is null)
			continue;
		const int d = int(g.circuitDef.id);
		// Removing it must LEAVE a surplus -- reclaim never causes a stall.
		if (eFree - Catalog::gMakeE[d] <= 0.1f * aiEconomyMgr.energy.income)
			continue;
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ownBestEcell < ratio * ec)
			continue;   // not dwarfed: still pulling its weight per cell
		if (ec < bestScore) {
			bestScore = ec;
			@best = g;
			bestDef = d;
		}
	}
	// Defences: dominated by a much stronger one covering the same ground.
	for (uint i = 0; i < gProtUnit[PROT_DEF].length(); ++i) {
		CCircuitUnit@ g = gProtUnit[PROT_DEF][i];
		if (g is null)
			continue;
		const int d = gProtDefId[PROT_DEF][i];
		bool dominated = false;
		for (uint j = 0; j < gProtUnit[PROT_DEF].length(); ++j) {
			if (i == j)
				continue;
			const int d2 = gProtDefId[PROT_DEF][j];
			if ((Catalog::Def(d2) !is null)
				&& (Catalog::Def(d2).power >= ratio * Catalog::Def(d).power)
				&& (gProtPos[PROT_DEF][i].distance2D(gProtPos[PROT_DEF][j]) < 400.f))
			{
				dominated = true;
				break;
			}
		}
		if (!dominated)
			continue;
		// Dominated defence outranks a weak generator at equal ground value.
		const float ec = Catalog::gCostM[d] * 0.001f;
		if (ec < bestScore) {
			bestScore = ec;
			@best = g;
			bestDef = d;
		}
	}
	// GROUND LABS RETIRE FOR THE QUIET REAR once an owned AIR lab fields
	// flying cons of equal reach (apexearth: "reclaim the T1 and T2 labs,
	// go for T1 and T2 air labs... then make the huge T3"). Successor-first,
	// same law as everything else here: nothing is obsolete before its
	// better is standing.
	if (EcoQuiet()) {
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if (f is null)
				continue;
			const int fd = int(f.circuitDef.id);
			float fReach = 0.f;
			bool fFlies = false;
			const array<int>@ fp = Catalog::gBuildsList[fd];
			for (uint q = 0; q < fp.length(); ++q) {
				if (!Catalog::gMobile[fp[q]] || !Catalog::gBuilder[fp[q]])
					continue;
				if (Catalog::gFlyer[fp[q]])
					fFlies = true;
				const array<int>@ fpb = Catalog::gBuildsList[fp[q]];
				for (uint r = 0; r < fpb.length(); ++r) {
					if (Catalog::gExtractsM[fpb[r]] > fReach)
						fReach = Catalog::gExtractsM[fpb[r]];
				}
			}
			if (fFlies)
				continue;   // air labs are the successors, never the retired
			bool succeeded = false;
			// A strictly deeper-reaching plant, standing OR under
			// construction, retires this one (apexearth: "reclaiming the
			// T1 lab while building the T2 lab").
			for (uint gi2 = 0; gi2 < Factory::gFacUnits.length() && !succeeded; ++gi2) {
				CCircuitUnit@ g3 = Factory::gFacUnits[gi2];
				if ((g3 is null) || (g3 is f))
					continue;
				float g3Reach = 0.f;
				const array<int>@ g3p = Catalog::gBuildsList[int(g3.circuitDef.id)];
				for (uint q3 = 0; q3 < g3p.length(); ++q3) {
					if (!Catalog::gMobile[g3p[q3]] || !Catalog::gBuilder[g3p[q3]])
						continue;
					const array<int>@ g3b = Catalog::gBuildsList[g3p[q3]];
					for (uint r3 = 0; r3 < g3b.length(); ++r3) {
						if (Catalog::gExtractsM[g3b[r3]] > g3Reach)
							g3Reach = Catalog::gExtractsM[g3b[r3]];
					}
				}
				if (g3Reach > fReach)
					succeeded = true;
			}
			for (uint gi = 0; gi < Factory::gFacUnits.length() && !succeeded; ++gi) {
				CCircuitUnit@ g2 = Factory::gFacUnits[gi];
				if ((g2 is null) || (g2 is f))
					continue;
				const array<int>@ gp = Catalog::gBuildsList[int(g2.circuitDef.id)];
				for (uint q2 = 0; q2 < gp.length(); ++q2) {
					if (!Catalog::gMobile[gp[q2]] || !Catalog::gBuilder[gp[q2]]
						|| !Catalog::gFlyer[gp[q2]])
						continue;
					float gReach = 0.f;
					const array<int>@ gpb = Catalog::gBuildsList[gp[q2]];
					for (uint r2 = 0; r2 < gpb.length(); ++r2) {
						if (Catalog::gExtractsM[gpb[r2]] > gReach)
							gReach = Catalog::gExtractsM[gpb[r2]];
					}
					if (gReach >= fReach) {
						succeeded = true;
						break;
					}
				}
			}
			if (succeeded && (Catalog::gCostM[fd] * 0.001f < bestScore)) {
				bestScore = Catalog::gCostM[fd] * 0.001f;
				@best = f;
				bestDef = fd;
			}
		}
	}
	if (best is null)
		return w;
	// One-shot metal amortized at the market's payback scale -- 60s priced a
	// single refund like a perpetual stream and it outbid every mex.
	const float horizon = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float gain = Catalog::gCostM[bestDef] / ((horizon > 1.f) ? horizon : 300.f);
	const AIFloat3 gp = best.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(gp) / speed) : 60.f;
	w.kind = WK_RECLAIM;
	@w.def = Catalog::Def(bestDef);
	w.pos = gp;
	w.spotId = int(best.id);
	w.gain = gain - Catalog::gMakeE[bestDef] * EPriceFloor();
	w.mCost = 1.f;
	w.tCost = (walkSec + Catalog::gCostM[bestDef] / 90.f) * Wage();
	w.value = (w.gain > 0.f) ? (w.gain / (w.mCost + w.tCost)) : 0.f;
	@gReclaimTarget = best;
	return w;
}

//------------------------------------------------------------------------------
// The arbiter's builder side. Called only from Brain::Decide.
//------------------------------------------------------------------------------

int gNextIdleLog = 0;
int gNextAuctionDiag = 0;
array<int> gLastDecideAt(32001, -30000);   // per-unit-id, Spring ids cap at 32k

IUnitTask@ Decide(CCircuitUnit@ unit)
{
	if ((unit is null) || !unit.circuitDef.IsBuilder() || !unit.circuitDef.IsMobile())
		return null;
	// A unit whose task keeps dying young re-enters every frame; 2s per
	// unit caps the global decide rate without touching legit elections
	// (a successful decide holds its task far longer than this).
	if ((int(unit.id) >= 0) && (int(unit.id) < int(gLastDecideAt.length()))) {
		if (ai.frame - gLastDecideAt[int(unit.id)] < 2 * SECOND)
			return null;
		gLastDecideAt[int(unit.id)] = ai.frame;
	}
	WorkerSeen(unit);
	LedgerSweep();

	array<Want@> wants = {
		ProposeMex(unit), ProposeEnergy(unit), ProposeGeo(unit),
		ProposePlant(unit), ProposeConvert(unit), ProposeStore(unit),
		ProposeMexUp(unit), ProposeTech(unit), ProposeNano(unit),
		ProposeReclaimObsolete(unit), ProposeAssist(unit),
		ProposeProtect(unit)
	};
	// Highest value first; a want the executor refuses (ground taken, request
	// standing, join out of reach) falls out and the runner-up is tried --
	// a builder never idles while a positive want remains executable.
	array<Want@> ranked;
	for (uint i = 0; i < wants.length(); ++i) {
		Want@ c = wants[i];
		if ((c is null) || (c.value <= 0.f))
			continue;
		uint at = 0;
		while ((at < ranked.length()) && (ranked[at].value >= c.value))
			++at;
		ranked.insertAt(at, c);
	}
	// PROPORTIONAL DRAW here too, not argmax (apexearth, watching: "a ton
	// of nanos and no T2 lab... is it just winner takes all?"). It was:
	// team 3 bought nanos at v=20-275 for 8 straight minutes while the T2
	// lab bid 16.7 once and never won -- the same starvation the old
	// Brain's roulette fix carved into project memory, re-grown between
	// want KINDS. Weight by value, seeded like the produce draw; the
	// ranked order still serves as the executor-refusal fallback.
	if (ranked.length() > 1) {
		float sumV2 = 0.f;
		for (uint ri = 0; ri < ranked.length(); ++ri)
			sumV2 += ranked[ri].value;
		uint h2 = uint(ai.frame) * 2654435761 + uint(unit.id) * 40503;
		h2 ^= (h2 >> 13);
		float roll2 = float(h2 % 10000) / 10000.f * sumV2;
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			roll2 -= ranked[ri].value;
			if (roll2 <= 0.f) {
				if (ri > 0) {
					Want@ drawn = ranked[ri];
					ranked.removeAt(ri);
					ranked.insertAt(0, drawn);
				}
				break;
			}
		}
	}
	Want@ top = (ranked.length() > 0) ? ranked[0] : null;
	Want@ next = (ranked.length() > 1) ? ranked[1] : null;
	// Auction dump for T2-capable builders, one per 30s, tunable-gated.
	if ((ai.GetTunable("apex_auction_diag", 0.f) > 0.f) && (ai.frame >= gNextAuctionDiag)) {
		bool t2able = false;
		const array<int>@ mm = Catalog::BuildsOf(int(unit.circuitDef.id));
		for (uint z = 0; z < mm.length(); ++z) {
			if (Catalog::gCostM[mm[z]] > 3000.f) {
				t2able = true;
				break;
			}
		}
		if (t2able) {
			gNextAuctionDiag = ai.frame + 30 * SECOND;
			string ln = "apex: auction " + unit.circuitDef.GetName() + " #" + unit.id + " |";
			for (uint z = 0; z < ranked.length(); ++z) {
				ln += " " + KindName(ranked[z].kind) + ":"
					+ ((ranked[z].def is null) ? "?" : ranked[z].def.GetName())
					+ " v=" + formatFloat(ranked[z].value * 1000.f, "", 0, 2)
					+ " (g=" + formatFloat(ranked[z].gain, "", 0, 1)
					+ " m=" + formatFloat(ranked[z].mCost, "", 0, 0)
					+ " t=" + formatFloat(ranked[z].tCost, "", 0, 0) + ")";
			}
			AiLog(ln);
		}
	}
	if (top is null) {
		// Floor want 1: a lesser con GUARDS a ceiling-reaching con -- guard
		// auto-assists whatever its target does, so 50 idle T1s (air cons
		// included) become T2 build power (apexearth 2026-08-23). Round-
		// robin spreads the guards.
		if (BestExtract() > 0.f) {
			float myCeil = 0.f;
			const array<int>@ mine = Catalog::BuildsOf(int(unit.circuitDef.id));
			for (uint i = 0; i < mine.length(); ++i) {
				if (Catalog::gExtractsM[mine[i]] > myCeil)
					myCeil = Catalog::gExtractsM[mine[i]];
			}
			if (myCeil < BestExtract()) {
				CCircuitUnit@ boss = NextServingCon();
				if (boss !is null) {
					if (ai.frame >= gNextIdleLog) {
						gNextIdleLog = ai.frame + 30 * SECOND;
						AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
							+ " -> guard:" + boss.circuitDef.GetName() + " #" + boss.id
							+ " (assist its work)");
					}
					IUnitTask@ gt2 = aiBuilderMgr.Enqueue(TaskB::Guard(
							Task::Priority::LOW, boss, false, 60 * SECOND));
					if (gt2 !is null)
						GuardNote(unit, boss);
					return gt2;
				}
			}
		}
		// Floor want 2: patrol the farm and auto-assist whatever builds there.
		if (gFarmSet) {
			if (ai.frame >= gNextIdleLog) {
				gNextIdleLog = ai.frame + 30 * SECOND;
				AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
					+ " -> assist (farm patrol; no positive want)");
			}
			return aiBuilderMgr.Enqueue(TaskB::Patrol(Task::Priority::LOW,
					gFarmPos, 20 * SECOND));
		}
		if (ai.frame >= gNextIdleLog) {
			gNextIdleLog = ai.frame + 30 * SECOND;
			AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
				+ " -> idle (no positive want)");
		}
		return null;
	}

	gWantEmaV = (gWantEmaV <= 0.f) ? top.value
			: (0.9f * gWantEmaV + 0.1f * top.value);
	AiLog("apex: decide t=" + ai.teamId + " " + unit.circuitDef.GetName() + " #" + unit.id
		+ " -> " + KindName(top.kind) + ":" + ((top.def is null) ? "-" : top.def.GetName())
		+ " v=" + formatFloat(top.value * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(top.gain, "", 0, 2)
		+ " m=" + formatFloat(top.mCost, "", 0, 0)
		+ " t=" + formatFloat(top.tCost, "", 0, 0) + ")"
		+ ((next is null) ? " over nothing"
			: (" over " + KindName(next.kind)
				+ " v=" + formatFloat(next.value * 1000.f, "", 0, 2))));

	// THE COMMANDER NEVER TAKES EXPOSED WORK: his death is the game, so a
	// want's exposure is a cost HE pays at game-loss scale (measured: com
	// died at 15:00 building an LLT at a naked forward mex, medium anchor
	// t000 -- the insurance priced the mex's risk and forgot the asker's).
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	for (uint i = 0; i < ranked.length(); ++i) {
		// FORWARD of the anchor is what kills commanders; the farm-distance
		// radius also banned the rear-flank PLANT site and the commander --
		// early game's only builder -- never made a factory (watched, and it
		// poisoned a 20-game medium anchor). Behind the anchor is safe by
		// the grid's own construction.
		if (isComm && Base::gAnchorSet && Base::gAxisSet) {
			const AIFloat3 rel = ranked[i].pos - Base::gAnchor;
			const float fwdDist = rel.x * Base::gFwd.x + rel.z * Base::gFwd.z;
			// 400: the base-front turret post sits at anchor+150 and the old
			// 150 cutoff banned the commander from it -- mDefence read 0.0
			// for a whole game (apexearth: "in early game he can provide a
			// good defense"). Beyond 400 is the con-and-escort frontier.
			if (fwdDist > 400.f)
				continue;
		}
		IUnitTask@ t = ExecuteWant(unit, ranked[i]);
		if (t !is null)
			return t;
	}
	return null;
}

IUnitTask@ ExecuteWant(CCircuitUnit@ unit, Want@ w)
{
	if (w.kind == WK_MEX) {
		// TaskB::Spot, not Common: CBMexTask::Execute refuses to issue the
		// build order unless IsOpenSpot(spotId) holds, and Common leaves
		// spotId at -1 (measured: one decide, then a game-long freeze).
		IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEX,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
		if (t !is null)
			LedgerClaim(w.spotId, w.pos, aiEconomyMgr.GetMexSpotIncome(w.spotId));
		return t;
	}
	if (w.kind == WK_MEXUP) {
		return aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEXUP,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
	}
	if (w.kind == WK_TECH) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, ClearOfSpots(w.pos, 180.f), 256.f,
				SQUARE_SIZE * 16.f);
	}
	if (w.kind == WK_PROTECT) {
		// THE chokepoint, not the proposers: three separate PROT_DEF gain
		// branches each carried their own ValueOf-and-continue, and gating
		// two of them still let claws through (measured three times).
		// Whatever proposes, nothing EXECUTES ground defence on the quiet
		// rear.
		// Classify by the DEF, not spotId: the defence branches store the
		// CLUSTER id in spotId, so a PROT_DEF compare only caught cluster 4
		// -- claws sailed past this gate on every other cluster (three
		// "airtight" runs, measured 2026-08-23). A ground-shooting weapon
		// is ground defence wherever it points; AA (air-only threat) stays
		// allowed, matching the audit's mDefAA split.
		const bool groundDef = (w.def !is null)
				&& (Catalog::gSurfT[int(w.def.id)] > 0.01f);
		if (groundDef && EcoQuiet())
			return null;
		if (groundDef)
			AiLog("apex: prot-exec t=" + ai.teamId + " def=" + w.def.GetName()
					+ " role=" + (gEcoRole ? 1 : 0)
					+ " danger=" + (EcoDangerNear() ? 1 : 0)
					+ " streak=" + gEcoDangerStreak);
		const int bt = (w.spotId == PROT_RADAR) ? int(Task::BuildType::RADAR)
				: ((w.spotId == PROT_DEF) || (w.spotId == PROT_SHIELD))
					? int(Task::BuildType::DEFENCE)
				: (w.spotId == PROT_ANTINUKE) ? int(Task::BuildType::BIG_GUN)
				: int(Task::BuildType::ENERGY);
		return Requests::Take(unit, w.def, Task::BuildType(bt),
				Task::Priority::NORMAL, w.pos, 300.f, SQUARE_SIZE * 16.f);
	}
	if (w.kind == WK_ASSIST) {
		if ((gAssistTarget is null) || (int(gAssistTarget.id) != w.spotId))
			return null;
		IUnitTask@ gt = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::LOW,
				gAssistTarget, false, 60 * SECOND));
		if (gt !is null)
			GuardNote(unit, gAssistTarget);
		return gt;
	}
	if (w.kind == WK_RECLAIM) {
		if ((gReclaimTarget is null) || (int(gReclaimTarget.id) != w.spotId))
			return null;
		// A condemned unit stands for it -- walking away made the reclaimer
		// chase it across the base (apexearth).
		if (gReclaimTarget.circuitDef.IsMobile())
			gReclaimTarget.CmdMoveTo(unit.GetPos(ai.frame));
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL,
				gReclaimTarget));
	}
	if (w.kind == WK_NANO) {
		// Nano placement follows the demand math: the line with the LARGEST
		// unserved spend gets the next turret (the binary has-one check
		// capped the army lab at a single nano while metal overflowed --
		// watched twice).
		// The FARM BLOCK is the default home (apexearth: "nanos go in
		// zones of future construction, not just where they're needed
		// presently" -- eco builds already site at the farm, so coverage
		// there is coverage of everything about to exist). A factory line
		// pulls a nano away only when its unserved spend clears a real
		// bar, not merely being the hungriest.
		// The FARM BLOCK IS DEAD (apexearth: nanos only beside factories
		// and expensive builds): the hungriest line or big frame takes the
		// turret; failing either, it parks beside any working factory.
		AIFloat3 slot = w.pos;
		bool sited = false;
		const float per = LineSpend();
		float worst = 0.f;
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if ((f is null) || (f.CountQueued(null) == 0))
				continue;
			const AIFloat3 fp = f.GetPos(ai.frame);
			int nanosNear = 0;
			for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
				if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
					++nanosNear;
			}
			const float u = per - float(nanosNear) * 17.5f;
			if (u > worst) {
				worst = u;
				slot = fp;
				sited = true;
			}
		}
		// NEAR THE METAL SINKS (apexearth: "if we are not empty on metal...
		// build nano turrets near the things that are currently spending
		// metal"): a live build site's pull is its assigned crew's drain;
		// the biggest uncovered sink competes under the same bar as the
		// lines. Bank-gated -- at an empty bank the lathe already outruns
		// income and pre-positioning BP at a sink serves nothing.
		const float mSt = aiEconomyMgr.metal.storage;
		if ((mSt > 1.f) && (aiEconomyMgr.metal.current > mSt
				* ai.GetTunable("apex_nano_sink_bank", TUNE_NANO_SINK_BANK))) {
			for (uint li = 0; li < Requests::gLive.length(); ++li) {
				IUnitTask@ lt = Requests::gLive[li];
				if ((lt is null) || (lt.buildDef is null))
					continue;
				array<CCircuitUnit@>@ crew = lt.GetUnits();
				if ((crew is null) || (crew.length() == 0))
					continue;
				const AIFloat3 sp = lt.GetBuildPos();
				if (!OnMap(sp))
					continue;
				float drain = 0.f;
				for (uint ci = 0; ci < crew.length(); ++ci) {
					if (crew[ci] !is null)
						drain += Catalog::gBuildPower[int(crew[ci].circuitDef.id)]
								* (7.f / 80.f);
				}
				int nanosAt = 0;
				for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
					if (sp.distance2D(gOwnNanoPos[ni]) < 350.f)
						++nanosAt;
				}
				const float u2 = drain - float(nanosAt) * 17.5f;
				if (u2 > worst) {
					worst = u2;
					slot = sp;
					sited = true;
					AiLog("apex: nano-to-sink t=" + ai.teamId + " at "
							+ lt.buildDef.GetName()
							+ " drain=" + formatFloat(u2, "", 0, 1));
				}
			}
		}
		// Bare big frames (no crew yet) are sites too: "if you're making
		// these fusions or afus somewhere, just go ahead and make nanos
		// beside them."
		if (!sited) {
			for (uint li = 0; li < Requests::gLive.length(); ++li) {
				IUnitTask@ lt2 = Requests::gLive[li];
				if ((lt2 is null) || (lt2.buildDef is null))
					continue;
				const int bd2 = int(lt2.buildDef.id);
				if ((Catalog::gCostM[bd2] < ai.GetTunable("apex_nano_sink_m", TUNE_NANO_SINK_M))
					&& (Catalog::gMakeE[bd2] < ai.GetTunable("apex_big_e", TUNE_BIG_E)))
					continue;
				const AIFloat3 sp4 = lt2.GetBuildPos();
				if (OnMap(sp4)) {
					slot = sp4;
					sited = true;
					break;
				}
			}
		}
		if (!sited) {
			for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
				CCircuitUnit@ f2 = Factory::gFacUnits[fi];
				if (f2 !is null) {
					slot = f2.GetPos(ai.frame);
					sited = true;
					break;
				}
			}
		}
		if (!sited)
			return null;
		// PARALLEL on purpose: the default Take folds every nano ask onto
		// the one standing request -- "burst=1 forever" (requests.as's own
		// measurement) -- the root of every "not enough nanos" report. Each
		// decider opens its OWN slot; FarmSlot's rows make the block
		// rectangular; the income-derived InFlight cap still bounds it.
		bool made = false;
		return Requests::Take(unit, w.def, Task::BuildType::NANO,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 64.f, 0.f,
				made, true);
	}
	if (w.kind == WK_GEO) {
		return aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::GEO,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
	}
	// An overflowing bank opens PARALLEL sites: the serialized default folds
	// every asker onto one standing request, and one fusion at a time was
	// the 45%-excess bottleneck. parallel skips the fold; the wealth cap
	// (EffectiveCap) still bounds it.
	bool par = (MCostScale() < 1.f);
	bool crtd = false;
	// Finish before founding: any unmanned unfinished site of this def is
	// THE want, wherever it stands (slot cursors never reuse ground, so an
	// abandoned frame would otherwise be orphaned forever).
	if ((w.kind == WK_ENERGY) || (w.kind == WK_CONVERT)
		|| (w.kind == WK_STORE) || (w.kind == WK_NANO))
	{
		IUnitTask@ orph = Requests::OrphanOf(w.def);
		if (orph !is null)
			return orph;
	}
	if (w.kind == WK_ENERGY) {
		// Fusion-tier generators pack together in the DEEP REAR
		// (apexearth: "place those next to each other... fusions belong
		// in the back of the map, furthest from the enemy").
		const bool bigE = Catalog::gMakeE[int(w.def.id)]
				>= ai.GetTunable("apex_big_e", TUNE_BIG_E);
		if (bigE)
			w.pos = BigEnergySite();
		const AIFloat3 slot = bigE ? w.pos
				: (gFarmSet ? FarmSlot(int(w.def.id)) : w.pos);
		{
			IUnitTask@ jt = JoinBig(w.def);
			if (jt !is null)
				return jt;
		}
		if (Catalog::gCostM[int(w.def.id)] > 500.f)
			w.pos = ClearOfSpots(w.pos, 150.f);
		return Requests::Take(unit, w.def, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 96.f, 0.f,
				crtd, par);
	}
	if (w.kind == WK_CONVERT) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::CONVERT,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 96.f, 0.f,
				crtd, par);
	}
	if (w.kind == WK_STORE) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::STORE,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 96.f, 0.f);
	}
	if (w.kind == WK_PLANT) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, ClearOfSpots(w.pos, 180.f), 256.f,
				SQUARE_SIZE * 16.f);
	}
	return null;
}

//------------------------------------------------------------------------------
// The production market's first Want: one constructor at a time while open
// expansion ground remains. Serialized by the sent-ledger, never by a count.
//------------------------------------------------------------------------------

// Deep demand check for the facqueue's lookahead batch: six more of this
// def must still be justified by the gap (or the overflow sink).
bool BatchWorthy(CCircuitDef@ d)
{
	if ((d is null) || d.IsBuilder())
		return false;   // builders stay single: their demand saturates fast
	const int di = int(d.id);
	const float need = ArmyTarget() - ArmyValue();
	const float sink = OverflowM() * 60.f;
	const float deep = (need > sink) ? need : sink;
	return deep > 6.f * Catalog::gCostM[di];
}

CCircuitDef@ ConOrderFor(CCircuitUnit@ fac, int line)
{
	if (fac is null)
		return null;
	// Production pays the E-flow discipline too: a factory pumping pawns
	// through a stall both causes it and starves the opening (watched:
	// hard e-stall, a minute without a mex).
	if (HardEStall())
		return null;
	if (!gMexOpen && (UpDemand() <= 0.5f) && (BPGap() <= 0.5f)
		&& (ArmyTarget() - ArmyValue() <= 0.5f))
		return null;
	// Two in flight per line: one building, one queued, so production is
	// continuous (one-at-a-time left the line idle between orders).
	if ((fac.CountQueued(null) + Brain::PendCount(line, null)) > 1)
		return null;
	const int fid = int(fac.circuitDef.id);
	const array<int>@ prods = Catalog::BuildsOf(fid);
	// Each product priced, best value ordered. A constructor's gain: the
	// tier-unique upgrade demand it unlocks, at DIMINISHING returns per con
	// already serving (the binary version stopped at exactly one T2 con);
	// plus its worth as mobile build power (overflow capture at its drain);
	// plus the open-spot stream if ground remains to claim.
	const float util = Utilization();
	const float over = BPGap() * util;
	const float upD = UpDemand();
	const float mobileCeil = OwnedMobileCeil();
	LossDecay();
	const float armyGap = ArmyTarget() - ArmyValue();
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	float roleMul = EcoRoleActive()
			? ai.GetTunable("apex_eco_army_mul", TUNE_ECO_ARMY_MUL) : 1.f;
	if ((roleMul < 1.f) && EcoDangerNear())
		roleMul = 1.f;
	// THE STAKE (apexearth 2026-08-23): "all the value we have built up will
	// be lost if we have insufficient army." Under-matched, a unit's worth
	// scales with EVERYTHING we own -- expected loss = total value x defeat
	// probability -- tapering to normal at parity. One modeled weight.
	float stakeMul = 1.f;
	{
		const float aT0 = ArmyTarget();
		if ((aT0 > 1.f) && (armyGap > 0.f)) {
			// Towers lighten the stake, but only LOCALLY (apexearth): static
			// defense standing in the core counts toward the army at an
			// immobility discount; a remote mex sentry defends its patch,
			// not the base.
			float coreStaticM = 0.f;
			if (gFarmSet) {
				for (uint sd2 = 0; sd2 < gProtUnit[PROT_DEF].length(); ++sd2) {
					if (gProtUnit[PROT_DEF][sd2] is null)
						continue;
					const AIFloat3 sp2 = gProtPos[PROT_DEF][sd2];
					if ((sp2.distance2D(gFarmPos) < 1200.f)
						|| (Base::gAnchorSet && (sp2.distance2D(Base::gAnchor) < 1200.f)))
						coreStaticM += Catalog::gCostM[gProtDefId[PROT_DEF][sd2]];
				}
			}
			const float lightened = armyGap - coreStaticM
					* ai.GetTunable("apex_static_guard", TUNE_STATIC_GUARD);
			const float effGapS = (lightened > 0.f) ? lightened : 0.f;
			const float deficit = effGapS / aT0;
			stakeMul = 1.f + deficit
					* ((gAssetsM + ArmyValue()) / aT0)
					* ai.GetTunable("apex_stake_weight", TUNE_STAKE_WEIGHT);
			if (stakeMul > 8.f)
				stakeMul = 8.f;
		}
	}
	// Best power-per-cost this line can produce, for normalizing army bids.
	float linePPC = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d]
			|| Catalog::gBuilder[d] || (Catalog::gPower[d] <= 1.f)
			|| Catalog::gKamikaze[d])
			continue;
		const float ppc = Catalog::gPower[d] / Catalog::gCostM[d];
		if (ppc > linePPC)
			linePPC = ppc;
	}
	// PROPORTIONAL DRAW, not argmax: a persistent 10% price edge under
	// winner-take-all became 29 cons and zero army from a vehicle lab
	// (measured, ladder t001) -- the same lesson the old Brain's roulette
	// carved into project memory. Candidates weight by value.
	array<int> candDef;
	array<float> candV;
	array<float> candGain;
	float sumV = 0.f;
	int best = -1;
	float bestV = 0.f;
	float bestGain = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d])
			continue;
		// SUPPORT: mobile eyes and static-cover. One radar and one jammer
		// per ~squad's worth of fielded army (apexearth: "ideally we attach
		// 1 of each to each squad"); attachment is the military layer's,
		// production is ours.
		if (Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (Catalog::gRadar[d] || Catalog::gJammer[d]))
		{
			const int haveS = (int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0;
			if (ai.frame >= gSupportDiagAt) {
				gSupportDiagAt = ai.frame + 120 * SECOND;
				AiLog("apex: support-diag t=" + ai.teamId + " def="
					+ Catalog::Def(d).GetName() + " have=" + haveS
					+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
					+ " land=" + formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 2));
			}
			// One radar + one jammer per squad's worth of army (apexearth:
			// "those should have boosted priority... support squads which
			// are ~2k metal value or higher"). A pair's worth is a fraction
			// of the squad value it serves per minute -- which prices them
			// just behind constructors, scaling with the army, no caps.
			const float squadM = ai.GetTunable("apex_squad_m", TUNE_SQUAD_M);
			const float squads = ArmyValue() / ((squadM > 1.f) ? squadM : 2000.f);
			if (float(haveS) < squads) {
				const float gainS = (squads - float(haveS)) * squadM
						* ai.GetTunable("apex_intel_rate", TUNE_INTEL_RATE)
						/ 60.f * roleMul;
				const float vS = gainS / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vS);
				candGain.insertLast(gainS);
				sumV += vS;
			}
			continue;
		}
		// ARMY: fill the gap, best power-per-cost first, diminishing per
		// copy owned so the mix diversifies by arithmetic, not by table.
		// Overflowing metal keeps the line running past the target: idle
		// factory time is free, and army beats waste (watched: "way too
		// much idle time on our T1 lab").
		if (!Catalog::gBuilder[d]) {
			// A suicide unit's power is one detonation -- ammunition, not
			// standing army ("we're just making tumbleweeds", watched 8v8).
			// It never enters the army market; a munitions want can price
			// it honestly later if ever wanted.
			if (Catalog::gKamikaze[d])
				continue;
			// REZ BOTS classify as non-builders (empty build list), so they
			// land HERE, not the builder branch -- which is why none were
			// ever made (watched, twice). Their gain: the recoverable loss
			// pool plus a standing medic share of the army.
			if (Catalog::gRezzer[d]) {
				const int haveRz = (int(d) < int(gOwnCount.length()))
						? gOwnCount[d] : 0;
				const float medic = ArmyValue()
						* ai.GetTunable("apex_medic_frac", TUNE_MEDIC_FRAC) / 60.f;
				const float gainRz = (gLossPool
						/ ai.GetTunable("apex_rez_horizon", TUNE_REZ_HORIZON)
						+ medic) / (1.f + float(haveRz) * 0.33f) * roleMul;
				if (gainRz > 0.05f) {
					const float vRz = gainRz / Catalog::gCostM[d];
					candDef.insertLast(d);
					candV.insertLast(vRz);
					candGain.insertLast(gainRz);
					sumV += vRz;
				}
				continue;
			}
		// Until T3-grade units, the quiet rear builds NO army (apexearth);
			// the bar is the cheapest gantry-tier assault (corshiva 1550,
			// read from the defs 2026-07-30). FIGHTERS are the exception
			// once an air lab stands ("we *do* want fighters"): they guard
			// the air-con fleet, sized by the AA target below.
			const bool airGuard = Catalog::gFlyer[d] && (Catalog::gAirT[d] > 0.f);
			if ((roleMul < 1.f) && !airGuard && (Catalog::gCostM[d]
					< ai.GetTunable("apex_eco_army_min_m", TUNE_ECO_ARMY_MIN_M)))
				continue;
			const float sinkGap = OverflowM() * ((fillS > 1.f) ? fillS : 60.f) * roleMul;
			const float effGap = (armyGap > sinkGap) ? armyGap : sinkGap;
			if ((effGap <= 0.f) || (Catalog::gPower[d] <= 1.f) || (linePPC <= 0.f))
				continue;
			float ppc = Catalog::gPower[d] / Catalog::gCostM[d];
			// FIELD REPORTS OVERRIDE STATS where the stats cannot see the
			// mechanism (projectile speed, accuracy): the user table in
			// tunables.as. And amphibious capability is dead weight on a
			// dry map -- the price paid for swimming buys nothing here.
			ppc *= UnitWorthMod(Catalog::Def(d).GetName());
			// x0 ON DRY MAPS (apexearth: "amphib should be x0" -- and a
			// tiny pond flips the engine's water flag, so the bar is real
			// water share of the map, ~15%).
			if (Catalog::gAmphib[d]) {
				float lp = aiTerrainMgr.GetLandPercent();
				if (lp <= 1.5f)
					lp *= 100.f;   // scale-proof: fraction or percent
				if (aiTerrainMgr.IsWaterAVoid()
					|| (lp > 100.f - ai.GetTunable("apex_water_pct", TUNE_WATER_PCT)))
					continue;
			}
			// The rear specialist buys quality: weight by unit size so the
			// draw lands on the biggest thing the lab offers, not spam that
			// arrives late or never.
			if (EcoRoleActive()) {
				float qual = Catalog::gCostM[d] / 1000.f;
				if (qual < 0.1f)
					qual = 0.1f;
				if (qual > 5.f)
					qual = 5.f;
				ppc *= qual;
			}
			// RANGE IS INTRINSIC VALUE (apexearth: "more strongly value
			// range"): reach means free damage before the enemy answers, in
			// every fight, not only against skirm pressure. A standing
			// preference on top of the reactive term below.
			ppc *= 1.f + (Catalog::gMaxRange[d] / 1000.f)
					* ai.GetTunable("apex_range_worth", TUNE_RANGE_WORTH);
			// RANGE ANSWERS RANGE (apexearth: banishers outranged and killed
			// our T1 too easily; snipers/fatboys came too late). Enemy skirm
			// and arty mass is outranging pressure: reach above 500 gains by
			// it, reach below fades toward the raider-spam share the role
			// portfolio already grants. T1 obsolescence emerges from the
			// same term.
			{
				const float outP = (Military::EnemyCostOf(Unit::Role::SKIRM.type)
						+ Military::EnemyCostOf(Unit::Role::ARTY.type)) / 3000.f;
				const float oP = (outP > 1.f) ? 1.f : outP;
				if (oP > 0.05f) {
					const float rNorm = (Catalog::gMaxRange[d] - 500.f) / 500.f;
					float rMul = 1.f + rNorm * oP * 1.2f;
					if (rMul < 0.3f)
						rMul = 0.3f;
					if (rMul > 2.5f)
						rMul = 2.5f;
					ppc *= rMul;
				}
			}
			const float have = float((int(d) < int(gOwnCount.length()))
					? gOwnCount[d] : 0);
			// The gap is a STREAM the line fills; clamping the gain to one
			// unit's cost made a Pawn bid 0.6 against any gap size and army
			// never outbid a constructor (two straight BARb losses).
			float eFeedA = 1.f;
			{
				const float eI = aiEconomyMgr.energy.income;
				const float eP = aiEconomyMgr.energy.pull;
				if ((eP > 1.f) && (eI < eP))
					eFeedA = eI / eP;
				// (the metal-feed throttle is gone: a zero bank spending its
				// whole income is PERFECT efficiency, not danger -- apexearth:
				// "'out of metal' is simply failing to spend... we need to
				// spend more." Builds at an empty bank slow to income speed
				// by the engine's own physics, which is the correct state.)
			}
			// This unit's role fills its own NEED gap; a saturated role's
			// units price to the floor whatever their power-per-cost.
			const float rTarget = RoleTarget(Catalog::gRole[d], ArmyTarget());
			const float rGap = rTarget - RoleValue(Catalog::gRole[d]);
			float roleW = (rTarget > 1.f) ? (rGap / rTarget) : 0.f;
			if (roleW < 0.05f)
				roleW = 0.05f;   // never exactly zero: portfolio floor
			float gainA = (effGap / ((fillS > 1.f) ? fillS : 60.f))
					* (ppc / linePPC) * roleW * stakeMul
					/ (1.f + have * 0.05f) * eFeedA;
			// The quiet rear's fighters ignore the suppressed army gap and
			// price straight off their own AA gap -- the air census is not
			// role-suppressed, so the guard fleet tracks REAL enemy air.
			if ((roleMul < 1.f) && airGuard) {
				gainA = ((rGap > 0.f) ? rGap : 0.f)
						/ ((fillS > 1.f) ? fillS : 60.f)
						* (ppc / linePPC) / (1.f + have * 0.05f) * eFeedA;
			}
			if (gainA <= 0.01f)
				continue;
			const float vA = gainA / Catalog::gCostM[d];
			candDef.insertLast(d);
			candV.insertLast(vA);
			candGain.insertLast(gainA);
			sumV += vA;
			continue;
		}
		// An ARMED producible builder is a decoy-class unit: it pays for a
		// gun and a disguise nobody asked for (apexearth: "do not want
		// them; maybe useful for later logic").
		if (Catalog::gSurfT[d] + Catalog::gAirT[d] > 0.01f)
			continue;
		float gain = 0.f;
		float reach = 0.f;
		const array<int>@ pb = Catalog::gBuildsList[d];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gExtractsM[pb[q]] > reach)
				reach = Catalog::gExtractsM[pb[q]];
		}
		// The quiet rear caps LAND con production at its keep-fleet (+2 for
		// attrition): the bank-driven BP gap must buy nanos and air cons,
		// not a walking crowd the reclaimer eats back (watched churn; conT1
		// hit 24 at 15m on the bank term).
		if (EcoQuiet() && !Catalog::gFlyer[d]
			&& (reach < BestExtract())) {
			int landT1 = 0;
			for (uint lc = 1; lc < gOwnCount.length(); ++lc) {
				if ((gOwnCount[lc] > 0) && Catalog::gMobile[int(lc)]
					&& Catalog::gBuilder[int(lc)] && !Catalog::gFlyer[int(lc)]) {
					const array<int>@ lb = Catalog::gBuildsList[int(lc)];
					bool ceil2 = false;
					for (uint lq = 0; lq < lb.length(); ++lq) {
						if (Catalog::gExtractsM[lb[lq]] >= BestExtract()) {
							ceil2 = true;
							break;
						}
					}
					if (!ceil2)
						landT1 += gOwnCount[lc];
				}
			}
			if (float(landT1) >= ai.GetTunable("apex_eco_con_keep", TUNE_ECO_CON_KEEP) + 2.f)
				continue;
		}
		// >= the game ceiling, not > our own: requiring the next con to
		// EXCEED what the first one reaches made a second armack impossible
		// (measured: one T2 con per game, forever).
		const float mob = MobilityMult(d);
		// Rez bots: the loss pool is recoverable value on the field; a rez
		// bot's stream is its share of it, diminishing per bot fielded.
		// From def DATA, not ownership: the owned-rezzer flag was a
		// bootstrap deadlock (production waited for a rezzer we could
		// never have ordered).
		if (Catalog::gRezzer[d]) {
			const int haveRez = (int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0;
			gain += gLossPool
					/ ai.GetTunable("apex_rez_horizon", TUNE_REZ_HORIZON)
					/ float(1 + haveRez);
		}
		if ((upD > 0.5f) && (reach >= BestExtract()))
			gain += mob * upD / float(1 + ServingCons());
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		gain += mob * ((over < drain) ? over : drain);
		if (gMexOpen && (reach > 0.f)) {
			// A con claims spot after spot -- a stream of STREAMS -- but the
			// STREAMS ARE FINITE: 37 cons once chased 13 spots and easy BARb
			// walked over an armyless base (measured, ladder game 1). The
			// claim gain divides by claimers per open spot -- the unserved-
			// demand law, fourth application.
			CacheSpots();
			const float open = float(int(gAllSpots.length()) - int(gLSpot.length()));
			float claimers = 0.f;
			for (uint cd2 = 1; cd2 < gOwnCount.length(); ++cd2) {
				if ((gOwnCount[cd2] > 0) && Catalog::gMobile[int(cd2)]
					&& Catalog::gBuilder[int(cd2)])
					claimers += float(gOwnCount[cd2]);
			}
			float share = (open > 0.f) ? (open / (claimers + 1.f)) : 0.f;
			if (share > 1.f)
				share = 1.f;
			gain += mob * util * SpotM() * (((fillS > 1.f) ? fillS : 180.f) / 60.f)
					* share;
		}
		if (gain <= 0.5f)
			continue;
		const float v = gain / Catalog::gCostM[d];
		candDef.insertLast(d);
		candV.insertLast(v);
		candGain.insertLast(gain);
		sumV += v;
	}
	if ((candDef.length() == 0) || (sumV <= 0.f))
		return null;
	// Deterministic weighted pick: seeded from frame+line so replays hold.
	uint h = uint(ai.frame) * 2654435761 + uint(fac.id) * 40503;
	h ^= (h >> 13);
	float roll = float(h % 10000) / 10000.f * sumV;
	uint pick = 0;
	for (uint ci = 0; ci < candV.length(); ++ci) {
		roll -= candV[ci];
		if (roll <= 0.f) {
			pick = ci;
			break;
		}
	}
	best = candDef[pick];
	bestV = candV[pick];
	bestGain = candGain[pick];
	// Priced in the same currency; factory time is free while the line idles.
	// OPPORTUNITY FLOOR: the draw compares a line's candidates only against
	// each other, so a saturated line kept producing v=1.2 cons while
	// fusion money earned v=30+ outside (measured: 22 armacks, 1 fusion).
	// With metal NOT overflowing, an order must beat a fraction of what
	// executed wants actually earn; overflow keeps idle time free.
	if ((OverflowM() <= 0.5f) && (gWantEmaV > 0.f)
		&& (bestV < gWantEmaV
			* ai.GetTunable("apex_line_floor", TUNE_LINE_FLOOR)))
		return null;
	AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName() + " #" + fac.id
		+ " -> produce:" + Catalog::Def(best).GetName()
		+ " v=" + formatFloat(bestV * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(bestGain, "", 0, 2)
		+ " m=" + formatFloat(Catalog::gCostM[best], "", 0, 0)
		+ " serving=" + ServingCons() + ")");
	return Catalog::Def(best);
}

}  // namespace Market
