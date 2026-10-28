namespace Market {

// LINE YIELD (his 10-27: price every lab, the gantry included, by what its units actually kill per metal against what
// our labs deliver; factory agnostic). Per combat type: enemy metal our copies destroyed (any target -- the record's
// matrix keeps armed pairs only, and a bomber's work is their economy) over metal finished, this game plus the stored
// games (C++ YieldDealt/YieldSpent). A type or line with little evidence reads the army's own yield, weighted as
// apex_record_prior of its units. Not scaled by LineUnitWorth: that is the lab's draw price, map-dependent and not
// comparable across tiers (the smoke game read the gantry 0.4 of the army and the vehicle plant 0.00).

bool YieldOn()
{
	return ai.GetTunable("apex_line_yield", TUNE_LINE_YIELD) > 0.f;
}

array<float> gYdUnit;     // per type, shrunk
array<float> gYdLine;     // per plant, shrunk
array<float> gYdD;        // per type, metal destroyed (game + stored)
array<float> gYdS;        // per type, metal spent
float gYdArmy = 1.f;
int gYdAt = -999999;

float YdPriorW(int d)
{
	return ai.GetTunable("apex_record_prior", 10.f) * Catalog::gCostM[d];
}

void YieldRefresh()
{
	if (ai.frame < gYdAt + MINUTE)
		return;
	gYdAt = ai.frame;
	gYdIncHist.insertLast(YdIncNow());
	if (gYdIncHist.length() > 4)
		gYdIncHist.removeAt(0);
	const int n = Catalog::gDefCount + 1;
	if (int(gYdUnit.length()) < n) {
		gYdUnit.resize(n);
		gYdLine.resize(n);
		gYdD.resize(n);
		gYdS.resize(n);
	}
	float sumD = 0.f, sumS = 0.f, sumK = 0.f;
	for (int d = 1; d < n; ++d) {
		gYdD[d] = 0.f;
		gYdS[d] = 0.f;
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		const CCircuitDef@ cd = Catalog::Def(d);
		gYdD[d] = ai.YieldDealt(cd, true) + ai.YieldDealt(cd, false);
		gYdS[d] = ai.YieldSpent(cd, true) + ai.YieldSpent(cd, false);
		if (gYdS[d] <= 0.f)
			continue;
		sumD += gYdD[d];
		sumS += gYdS[d];
		sumK += YdPriorW(d);
	}
	gYdArmy = ((sumS + sumK) > 0.f) ? ((sumD + sumK) / (sumS + sumK)) : 1.f;
	for (int d = 1; d < n; ++d) {
		gYdUnit[d] = gYdArmy;
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		const float k = YdPriorW(d);
		gYdUnit[d] = (gYdD[d] + k * gYdArmy) / (gYdS[d] + k);
	}
	string row = "";
	for (int p = 1; p < n; ++p) {
		gYdLine[p] = gYdArmy;
		if (!Catalog::gAvailable[p] || Catalog::gMobile[p] || (Catalog::gBuildsList[p].length() == 0)
				|| (LineTier(p) == 0) || !Producible(p))
			continue;
		float dl = 0.f, sl = 0.f;
		array<float> costs;
		const array<int>@ prods = Catalog::gBuildsList[p];
		for (uint i = 0; i < prods.length(); ++i) {
			const int d = prods[i];
			if (!Catalog::gAvailable[d] || !LineCombat(d))
				continue;
			dl += gYdD[d];
			sl += gYdS[d];
			costs.insertLast(Catalog::gCostM[d]);
		}
		if (costs.length() == 0)
			continue;
		costs.sortAsc();
		const float k = ai.GetTunable("apex_record_prior", 10.f) * costs[costs.length() / 2];
		gYdLine[p] = (dl + k * gYdArmy) / (sl + k);
		row += " " + Catalog::Def(p).GetName() + "=" + NnF(gYdLine[p], 2) + "(" + int(dl) + "/" + int(sl) + ")";
	}
	AiLog("apex: yield t=" + ai.teamId + " army=" + NnF(gYdArmy, 2) + row);
}

// what a metal of this type is expected to destroy, against what a metal of our army does
float UnitYieldMul(int d)
{
	if (!YieldOn() || !LineCombat(d))
		return 1.f;
	YieldRefresh();
	return (gYdArmy > 0.f) ? (gYdUnit[d] / gYdArmy) : 1.f;
}

float LineYield(int plantDef)
{
	YieldRefresh();
	return ((plantDef > 0) && (plantDef < int(gYdLine.length()))) ? gYdLine[plantDef] : 1.f;
}

float LineYieldMul(int plantDef)
{
	if (!YieldOn())
		return 1.f;
	return (gYdArmy > 0.f) ? (LineYield(plantDef) / gYdArmy) : 1.f;
}

// measured against the stats: a line's yield over the army's, 1 until it has fought
float LineYieldCorr(int plantDef)
{
	YieldRefresh();
	return (gYdArmy > 0.f) ? (LineYield(plantDef) / gYdArmy) : 1.f;
}

// the best line we stand, stats times what it has shown
float OwnBestLineQY()
{
	float best = 0.f;
	for (uint i = 0; i < Factory::gFacUnits.length(); ++i) {
		CCircuitUnit@ f = Factory::gFacUnits[i];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int d = int(f.circuitDef.id);
		const float q = LineBestWorth(d);
		if (q <= 0.f)
			continue;
		const float v = q * LineYieldCorr(d);
		if (v > best)
			best = v;
	}
	return best;
}

// a line whose stats times its record beat the best line we stand
bool BetterLine(int d)
{
	if (!YieldOn())
		return false;
	const float q = LineBestWorth(d);
	return (q > 0.f) && (q * LineYieldCorr(d) > OwnBestLineQY());
}

// WHEN IT IS READY (his 10-27: "when this thing is ready what will my eco be? how many nanos do i expect to have?").
// Income from its measured trend over the last minutes (the in-flight ledger's gains carry the growth premiums),
// carried to the moment the line can produce; the line then takes what the army spends, never more than its share
// of that economy -- the share NanosDueFor puts nanos on.
array<float> gYdIncHist;   // one sample a minute, oldest first
float gYdFlow = 0.f, gYdReadyS = 0.f, gYdIncT = 0.f;

float YdIncNow()
{
	return (gIncEma > 0.f) ? gIncEma : Eco::MInc();
}

float YdIncomeAt(float sec)
{
	const float inc = YdIncNow();
	const uint n = gYdIncHist.length();
	if (n < 2)
		return inc;
	const float slope = (gYdIncHist[n - 1] - gYdIncHist[0]) / (float(n - 1) * 60.f);
	const float proj = inc + slope * sec;
	return (proj > 0.f) ? proj : 0.f;
}

float LineFlowAtReady(int d, float askerBP)
{
	YieldRefresh();
	const float inc = YdIncNow();
	const float build = Catalog::BuildSecondsAt(d, EffBP(askerBP));
	const float feed = Catalog::gCostM[d] / ((inc > 1.f) ? inc : 1.f);
	gYdReadyS = (build > feed) ? build : feed;
	gYdIncT = YdIncomeAt(gYdReadyS);
	const float armyT = gYdIncT * Brain::TargetShare(Brain::ARMY);
	const float ceil = LineCostCeilOf(d);
	const float lineT = EcoPowerM() * ((inc > 1.f) ? (gYdIncT / inc) : 1.f) * ceil / (LineCeilSum() + ceil);
	gYdFlow = (armyT < lineT) ? armyT : lineT;
	return gYdFlow;
}

}  // namespace Market
