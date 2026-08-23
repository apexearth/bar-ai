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
	const float frac = aiEconomyMgr.metal.current / st;
	if (frac <= 0.8f)
		return 1.f;
	const float f = (frac - 0.8f) / 0.2f;
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

void NoteFinished(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int defId = int(unit.circuitDef.id);
	OwnAdd(defId, 1);
	if (Catalog::gExtractsM[defId] <= 0.f)
		return;
	const int i = LedgerNearest(unit.GetPos(ai.frame));
	if (i >= 0)
		gLExtract[i] = Catalog::gExtractsM[defId];
}
// Fallback anchor: the first finished nano, only if no plan latched first.
void NoteFarm(CCircuitUnit@ unit)
{
	if (gFarmSet || (unit is null))
		return;
	const int d = int(unit.circuitDef.id);
	if (Catalog::gMobile[d] || (Catalog::gBuildPower[d] <= 0.f)
		|| (Catalog::gBuildsList[d].length() > 0))
	{
		return;
	}
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
		if (!Catalog::gBuilder[int(d)] && (Catalog::gBuildPower[int(d)] <= 0.f))
			continue;
		if (Catalog::gBuildPower[int(d)] <= 0.f)
			continue;
		cap += float(gOwnCount[d]) * Catalog::gBuildPower[int(d)] * (7.f / 80.f);
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
	const float eSurplus = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
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
	const float over = OverflowM();
	if (over <= 0.5f)
		return w;
	const float horizon = ai.GetTunable("apex_store_horizon", TUNE_STORE_HORIZON);
	// Storage buys TIME, and time has a STOCK target: one horizon of income
	// banked. At a chronically full bank the empty-headroom test re-licensed
	// a store every auction (the plateau apexearth watched: storage winning
	// while fusion never came) -- structural overflow is spending's problem,
	// never storage's.
	if (aiEconomyMgr.metal.storage >= aiEconomyMgr.metal.income * horizon)
		return w;
	const float emptySec = (aiEconomyMgr.metal.storage - aiEconomyMgr.metal.current)
			/ over;
	if (emptySec >= horizon)
		return w;
	const float fill = 1.f - emptySec / ((horizon > 1.f) ? horizon : 60.f);
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

// MODEL: a plant's return is its constructor pipeline -- each con carries
// roughly one open spot's stream while expansion ground remains, plus the
// overflow the pipeline would capture (arithmetic, see OverflowM). One named
// discount (apex_plant_pipe) prices the pipeline's losses; no spot ground
// left means no plant value at all.
Want@ ProposePlant(CCircuitUnit@ unit)
{
	Want w;
	if (!gMexOpen)
		return w;
	// The MARGINAL plant: worth anything only if income supports another
	// line (~50 m/s each, apexearth's number). Not a cap -- a price of zero
	// past what the economy can feed, of any lab type.
	const float per = ai.GetTunable("apex_plant_income_per", TUNE_PLANT_INCOME_PER);
	const int supported = 1 + int(aiEconomyMgr.metal.income / ((per > 1.f) ? per : 50.f));
	if (Factory::gFactoryCount >= supported)
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const float gain = (SpotM() + BPGap())
			* ai.GetTunable("apex_plant_pipe", TUNE_PLANT_PIPE)
			* Utilization();
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
		ValueOf(d, gain * bestMob, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PLANT;
			@w.def = Catalog::Def(d);
			w.pos = EcoSiteFor(unit);
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
		else if ((ownMob > 0.f) && (prodMob > ownMob * 1.2f))
			techGain = demand * pipe * (prodMob / ownMob - 1.f);
		if (techGain <= 0.f)
			continue;
		Want c;
		ValueOf(d, techGain, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_TECH;
			@w.def = Catalog::Def(d);
			w.pos = here;
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
Want@ ProposeNano(CCircuitUnit@ unit)
{
	Want w;
	const float over = BPGap();
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

//------------------------------------------------------------------------------
// The arbiter's builder side. Called only from Brain::Decide.
//------------------------------------------------------------------------------

int gNextIdleLog = 0;
int gNextAuctionDiag = 0;

IUnitTask@ Decide(CCircuitUnit@ unit)
{
	if ((unit is null) || !unit.circuitDef.IsBuilder() || !unit.circuitDef.IsMobile())
		return null;
	WorkerSeen(unit);

	array<Want@> wants = {
		ProposeMex(unit), ProposeEnergy(unit), ProposeGeo(unit),
		ProposePlant(unit), ProposeConvert(unit), ProposeStore(unit),
		ProposeMexUp(unit), ProposeTech(unit), ProposeNano(unit)
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
		// The floor want: an idle builder's time is free, so it patrols the
		// farm and auto-assists whatever is building there. Short timeout:
		// it re-enters the market every cycle.
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
		+ " -> " + KindName(top.kind) + ":" + top.def.GetName()
		+ " v=" + formatFloat(top.value * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(top.gain, "", 0, 2)
		+ " m=" + formatFloat(top.mCost, "", 0, 0)
		+ " t=" + formatFloat(top.tCost, "", 0, 0) + ")"
		+ ((next is null) ? " over nothing"
			: (" over " + KindName(next.kind)
				+ " v=" + formatFloat(next.value * 1000.f, "", 0, 2))));

	for (uint i = 0; i < ranked.length(); ++i) {
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
	if (w.kind == WK_NANO) {
		// Tighter than the coverage circle so the reach circles overlap and
		// the farm tiles instead of scattering.
		return Requests::Take(unit, w.def, Task::BuildType::NANO,
				Task::Priority::NORMAL, w.pos, 256.f, SQUARE_SIZE * 16.f);
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
	if (w.kind == WK_ENERGY) {
		return Requests::Take(unit, w.def, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, w.pos, 600.f, SQUARE_SIZE * 32.f,
				crtd, par);
	}
	if (w.kind == WK_CONVERT) {
		return Requests::Take(unit, w.def, Task::BuildType::CONVERT,
				Task::Priority::NORMAL, w.pos, 600.f, SQUARE_SIZE * 32.f,
				crtd, par);
	}
	if (w.kind == WK_STORE) {
		return Requests::Take(unit, w.def, Task::BuildType::STORE,
				Task::Priority::NORMAL, w.pos, 600.f, SQUARE_SIZE * 32.f);
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

CCircuitDef@ ConOrderFor(CCircuitUnit@ fac, int line)
{
	if (fac is null)
		return null;
	if (!gMexOpen && (UpDemand() <= 0.5f) && (BPGap() <= 0.5f))
		return null;
	// One in flight per line: pipeline discipline, not a cap.
	if ((fac.CountQueued(null) + Brain::PendCount(line, null)) > 0)
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
	int best = -1;
	float bestV = 0.f;
	float bestGain = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || !Catalog::gBuilder[d])
			continue;
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
		if ((upD > 0.5f) && (reach >= BestExtract()))
			gain += mob * upD / float(1 + ServingCons());
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		gain += mob * ((over < drain) ? over : drain);
		if (gMexOpen && (reach > 0.f))
			gain += mob * util * SpotM();   // claims only count if cons work
		if (gain <= 0.5f)
			continue;
		const float v = gain / Catalog::gCostM[d];
		if (v > bestV) {
			bestV = v;
			best = d;
			bestGain = gain;
		}
	}
	if (best < 0)
		return null;
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
