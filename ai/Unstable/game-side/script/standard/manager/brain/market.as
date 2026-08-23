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
	if (frac <= 0.5f)
		return 1.f;
	const float f = (frac - 0.5f) / 0.4f;
	return 1.f - 0.8f * ((f > 1.f) ? 1.f : f);
}

float ValueOf(int defId, float gain, float walkSec, float builderBP, Want@ w)
{
	const float buildSec = Catalog::BuildSecondsAt(defId, EffBP(builderBP));
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
	w.tCost = (walkSec + buildSec) * Wage();
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
		const float gain = spotIncome * Catalog::gExtractsM[d];
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
void TrackIncome()
{
	if (ai.frame < gIncPrevAt + 10 * SECOND)
		return;
	const float inc = aiEconomyMgr.metal.income;
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
	const float gap = futureInc * ((head > 0.f) ? head : 1.15f) - BPCapacity();
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
	const float per = ai.GetTunable("apex_plant_income_per", TUNE_PLANT_INCOME_PER);
	const int supported = 1 + int(aiEconomyMgr.metal.income / ((per > 1.f) ? per : 50.f));
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
		Want c;
		ValueOf(d, gain * bestMob * PipeLatencyMult(d, Catalog::gBuildPower[uid]),
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
		for (uint i = 0; i < builds.length(); ++i) {
			const int d = builds[i];
			if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= gLExtract[li]))
				continue;
			const float delta = gLIncome[li] * (Catalog::gExtractsM[d] - gLExtract[li]);
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
Want@ ProposeTech(CCircuitUnit@ unit)
{
	Want w;
	const float demand = UpDemand();
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
		float techGain = 0.f;
		if (prodCeil > ownCeil)
			techGain = demand * pipe;
		// A lab without follow-through is a statue: its price carries its
		// first constructor, and its VALUE scales with how funded the army
		// is -- an outgunned base defers tech exactly as much as it is
		// outgunned (apexearth: "we starve our army production by starting
		// a T2 lab too early... calculate the cost of making a lab's units
		// prior to making it"). No timer anywhere.
		const float aT = ArmyTarget();
		const float funded = (aT > 1.f) ? (ArmyValue() / aT) : 1.f;
		const float fundedMul = (funded > 1.f) ? 1.f : funded;
		else if ((ownMob > 0.f) && (prodMob > ownMob * 1.2f))
			techGain = demand * pipe * (prodMob / ownMob - 1.f);
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
				const float sink = OverflowM() * pipe;
				if (sink > techGain)
					techGain = sink;
			}
		}
		if (techGain <= 0.f)
			continue;
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
bool NearSpot(const AIFloat3& in p)
{
	CacheSpots();
	for (uint i = 0; i < gAllSpots.length(); ++i) {
		if (p.distance2D(gAllSpots[i]) < 100.f)
			return true;
	}
	return false;
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
		AIFloat3 spot = Base::gAnchor
				- Base::gFwd * ai.GetTunable("apex_farm_back", TUNE_FARM_BACK);
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
float UnservedLineSpend()
{
	float unserved = 0.f;
	const float per = LineSpend();
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.CountQueued(null) == 0))
			continue;
		int nanosNear = 0;
		const AIFloat3 fp = f.GetPos(ai.frame);
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
				++nanosNear;
		}
		const float u = per - float(nanosNear) * 17.5f;
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
	const float gap = BPGap();
	const float ovf = OverflowM();
	float over = (gap > ovf) ? gap : ovf;
	const float lineNeed = UnservedLineSpend();
	if (lineNeed > over)
		over = lineNeed;   // hot lines size their own nano ring
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
void WorkerSeen(CCircuitUnit@ u)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == u.id)
			return;
	}
	gWorkers.insertLast(u);
	gWorkerIds.insertLast(u.id);
}
void WorkerGone(Id id)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == id) {
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
	if (role == int(Unit::Role::AA.type))
		return aiEnemyMgr.GetEnemyCost(RT::AIR)
				* ai.GetTunable("apex_aa_match", TUNE_AA_MATCH);
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

void StallWatch()
{
	if (ai.frame < gNextStallSweep)
		return;
	gNextStallSweep = ai.frame + 5 * SECOND;
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
			gain = gAssetsM * rate;
		} else if (cls == PROT_JAM) {
			if (ProtCovered(PROT_JAM, core, Catalog::gJamR[d] * 0.8f))
				continue;
			gain = gAssetsM * rate * 0.5f;
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
			// The base perimeter first: the FRONT (the anchor -- in front of
			// the T1 lab) and the REAR (behind the farm) each want standing
			// ground defense (watched: no turrets at either).
			if (Base::gAnchorSet && Base::gAxisSet) {
				const AIFloat3 front = Base::gAnchor + Base::gFwd * 150.f;
				const AIFloat3 rear = gFarmPos - Base::gFwd * (gFarmDepth + 150.f);
				// The front line scales with the OBSERVED wave: reinforcing a
				// doorstep fight one unit at a time lost 19k of army at 0.008
				// K/D (ladder autopsy) -- standing power must meet the wave
				// BEFORE it lands. Gap = seen massing minus turret power here.
				float standing = 0.f;
				for (uint sd = 0; sd < gProtUnit[PROT_DEF].length(); ++sd) {
					if ((gProtUnit[PROT_DEF][sd] !is null)
						&& (gProtPos[PROT_DEF][sd].distance2D(front) < 600.f))
						standing += Catalog::gPower[gProtDefId[PROT_DEF][sd]];
				}
				const float wave = Military::FoeMobileMassing();
				const float wavePower = wave / 12.f;   // metal->power, rough T1 rate
				const float waveGap = wavePower - standing;
				if (OnMap(front)
					&& ((waveGap > 0.f) || !ProtCovered(PROT_DEF, front, 450.f)))
				{
					at = front;
					const float insure = gAssetsM * rate * 2.f;
					const float meet = (waveGap > 0.f)
							? (waveGap * 12.f / 300.f) : 0.f;   // amortized over a wave cycle
					gain = (meet > insure) ? meet : insure;
				} else if (!ProtCovered(PROT_DEF, rear, 450.f) && OnMap(rear)) {
					at = rear;
					gain = gAssetsM * rate;
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
		// Range answers arty: easy's artillery ground our LLT wall 38k:7k
		// (fight1v1) -- when their ARTY mass is seen, a turret's reach
		// multiplies its worth, so beamers/HLTs price above cheap sentries
		// exactly when short walls are food.
		if (cls == PROT_DEF) {
			const float artySeen = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type);
			if (artySeen > 100.f) {
				float rangeMul = 1.f + (Catalog::gMaxRange[d] / 500.f)
						* ((artySeen < 3000.f) ? (artySeen / 3000.f) : 1.f);
				gain *= rangeMul;
			}
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
	// A serving con actively building, else a producing factory line.
	CCircuitUnit@ boss = NextServingCon();
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

	AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
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
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, w.pos, 600.f, SQUARE_SIZE * 32.f);
	}
	if (w.kind == WK_PROTECT) {
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
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL,
				gReclaimTarget));
	}
	if (w.kind == WK_NANO) {
		// Nano placement follows the demand math: the line with the LARGEST
		// unserved spend gets the next turret (the binary has-one check
		// capped the army lab at a single nano while metal overflowed --
		// watched twice).
		AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
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
			}
		}
		return Requests::Take(unit, w.def, Task::BuildType::NANO,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 200.f, 0.f);
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
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
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
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, w.pos, 600.f, SQUARE_SIZE * 32.f);
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
			const float sinkGap = OverflowM() * ((fillS > 1.f) ? fillS : 60.f);
			const float effGap = (armyGap > sinkGap) ? armyGap : sinkGap;
			if ((effGap <= 0.f) || (Catalog::gPower[d] <= 1.f) || (linePPC <= 0.f))
				continue;
			const float ppc = Catalog::gPower[d] / Catalog::gCostM[d];
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
				// The metal mirror: a starving bank throttles army the same
				// way a stall does -- structural, so no dial can starve the
				// eco again (watched: out of metal, army still pumping).
				const float mI = aiEconomyMgr.metal.income;
				const float mP = aiEconomyMgr.metal.pull;
				const float mSt = aiEconomyMgr.metal.storage;
				if ((mP > 1.f) && (mI < mP) && (mSt > 1.f)
					&& (aiEconomyMgr.metal.current < 0.25f * mSt))
				{
					eFeedA *= mI / mP;
				}
			}
			// This unit's role fills its own NEED gap; a saturated role's
			// units price to the floor whatever their power-per-cost.
			const float rTarget = RoleTarget(Catalog::gRole[d], ArmyTarget());
			const float rGap = rTarget - RoleValue(Catalog::gRole[d]);
			float roleW = (rTarget > 1.f) ? (rGap / rTarget) : 0.f;
			if (roleW < 0.05f)
				roleW = 0.05f;   // never exactly zero: portfolio floor
			const float gainA = (effGap / ((fillS > 1.f) ? fillS : 60.f))
					* (ppc / linePPC) * roleW
					/ (1.f + have * 0.05f) * eFeedA;
			if (gainA <= 0.01f)
				continue;
			const float vA = gainA / Catalog::gCostM[d];
			candDef.insertLast(d);
			candV.insertLast(vA);
			candGain.insertLast(gainA);
			sumV += vA;
			continue;
		}
		float gain = 0.f;
		float reach = 0.f;
		const array<int>@ pb = Catalog::gBuildsList[d];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gExtractsM[pb[q]] > reach)
				reach = Catalog::gExtractsM[pb[q]];
		}
		// >= the game ceiling, not > our own: requiring the next con to
		// EXCEED what the first one reaches made a second armack impossible
		// (measured: one T2 con per game, forever).
		const float mob = MobilityMult(d);
		// Rez bots: the loss pool is recoverable value on the field; a rez
		// bot's stream is its share of it, diminishing per bot fielded.
		if (Builder::gRezzerDefs[d]) {
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
	AiLog("apex: decide " + fac.circuitDef.GetName() + " #" + fac.id
		+ " -> produce:" + Catalog::Def(best).GetName()
		+ " v=" + formatFloat(bestV * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(bestGain, "", 0, 2)
		+ " m=" + formatFloat(Catalog::gCostM[best], "", 0, 0)
		+ " serving=" + ServingCons() + ")");
	return Catalog::Def(best);
}

}  // namespace Market
