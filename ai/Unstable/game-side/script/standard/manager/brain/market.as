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
	const float eInc = aiEconomyMgr.energy.income;
	const float ePull = aiEconomyMgr.energy.pull;
	float pressure = (eInc > 0.01f) ? (ePull / eInc) : 3.f;
	if (pressure > 3.f)
		pressure = 3.f;
	if (pressure < 0.f)
		pressure = 0.f;
	// A drained bank is a stall already happening, whatever the flow says.
	const float eCur = aiEconomyMgr.energy.current;
	const float eStore = aiEconomyMgr.energy.storage;
	if ((eStore > 1.f) && (eCur < 0.25f * eStore))
		pressure = (pressure < 1.f) ? 1.f : pressure;
	const float unlock = (eInc > 0.01f)
			? (pressure * aiEconomyMgr.metal.income / eInc) : 1.f;
	const float fl = EPriceFloor();
	return (unlock > fl) ? unlock : fl;
}

//------------------------------------------------------------------------------
// Pricing.
//------------------------------------------------------------------------------

float ValueOf(int defId, float gain, float walkSec, float builderBP, Want@ w)
{
	const float buildSec = Catalog::BuildSecondsAt(defId, builderBP);
	w.gain = gain;
	// The E bill is paid at TODAY's scarcity: an E-hungry build during a
	// stall costs what that energy would have unlocked, not the floor.
	w.mCost = Catalog::gCostM[defId] + Catalog::gCostE[defId] * EPrice();
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

// The last probed open spot's real yield (income x extraction); the tunable
// is only the pre-probe fallback. This was a MODEL term until the
// GetMexSpotIncome binding landed.
float gLastSpotM = -1.f;
float SpotM()
{
	return (gLastSpotM > 0.f) ? gLastSpotM
			: ai.GetTunable("apex_spot_m", TUNE_SPOT_M);
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
	const float walkSec = (speed > 1.f) ? (here.distance2D(pos) / speed) : 60.f;
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
	const float ePrice = EPrice();
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d])
			continue;
		if (Catalog::gMakeE[d] <= 1.f)
			continue;
		if (Catalog::gNeedGeo[d])
			continue;   // vents are the geo want's ground, not free placement
		Want c;
		const float gain = Catalog::gMakeE[d] * ePrice;
		ValueOf(d, gain, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_ENERGY;
			@w.def = Catalog::Def(d);
			w.pos = unit.GetPos(ai.frame);
		}
	}
	return w;
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
	const float gain = Catalog::gMakeE[geoId] * EPrice();
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
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const float gain = (SpotM() + OverflowM())
			* ai.GetTunable("apex_plant_pipe", TUNE_PLANT_PIPE);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d])
			continue;
		if (Catalog::gBuildsList[d].length() == 0)
			continue;   // not a factory
		// A plant that cannot produce a mobile builder buys no expansion --
		// and the builder must be able to EXIST here: a shipyard's ship-cons
		// have no connected area at a land base (measured: armsy chosen on
		// Comet Catcher, a game-long placement failure).
		const AIFloat3 here = unit.GetPos(ai.frame);
		bool makesCon = false;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int pd = prods[p];
			if (Catalog::gMobile[pd] && Catalog::gBuilder[pd]
				&& ai.CanDefReach(Catalog::Def(pd), here, here))
			{
				makesCon = true;
				break;
			}
		}
		if (!makesCon)
			continue;
		Want c;
		ValueOf(d, gain, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PLANT;
			@w.def = Catalog::Def(d);
			w.pos = unit.GetPos(ai.frame);
		}
	}
	return w;
}

//------------------------------------------------------------------------------
// The arbiter's builder side. Called only from Brain::Decide.
//------------------------------------------------------------------------------

int gNextIdleLog = 0;

IUnitTask@ Decide(CCircuitUnit@ unit)
{
	if ((unit is null) || !unit.circuitDef.IsBuilder() || !unit.circuitDef.IsMobile())
		return null;

	array<Want@> wants = {
		ProposeMex(unit), ProposeEnergy(unit), ProposeGeo(unit), ProposePlant(unit)
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
	if (top is null) {
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
		return aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEX,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
	}
	if (w.kind == WK_GEO) {
		return aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::GEO,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
	}
	if (w.kind == WK_ENERGY) {
		return Requests::Take(unit, w.def, Task::BuildType::ENERGY,
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
	if ((fac is null) || !gMexOpen)
		return null;
	// One in flight per line: pipeline discipline, not a cap.
	if ((fac.CountQueued(null) + Brain::PendCount(line, null)) > 0)
		return null;
	const int fid = int(fac.circuitDef.id);
	const array<int>@ prods = Catalog::BuildsOf(fid);
	int best = -1;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || !Catalog::gBuilder[d])
			continue;
		if ((best < 0) || (Catalog::gCostM[d] < Catalog::gCostM[best]))
			best = d;
	}
	if (best < 0)
		return null;
	// Priced in the same currency; factory time is free while the line idles.
	const float v = SpotM() / Catalog::gCostM[best];
	AiLog("apex: decide " + fac.circuitDef.GetName() + " #" + fac.id
		+ " -> produce:" + Catalog::Def(best).GetName()
		+ " v=" + formatFloat(v * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(SpotM(), "", 0, 2)
		+ " m=" + formatFloat(Catalog::gCostM[best], "", 0, 0) + ")");
	return Catalog::Def(best);
}

}  // namespace Market
