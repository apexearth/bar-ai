namespace Market {

// COUNTER MIX (apex_counter_mix, his 2026-10-16: "production answers what they field"; Thugs fight the Janus,
// Pawns and Grunts go round it for their economy; Grunts are good against plenty, not against splash).
// Each ground army candidate's draw value is multiplied by its fight value against the enemy mobile army we
// have seen, and the army candidates are renormalised so the army's ticket against constructors is unchanged.
// Pair a (ours) vs b (theirs), equal metal, square law, from catalog stats, cached per pair:
//   e_ab   = dps_a x cov(aoe_a, b's clump spacing) x min(1, hp_b / alpha_a)
//            cov = 1 + max(0, pi aoe^2 / s^2 - 1) / 3   (the blast's linear falloff, a third over its disc)
//            s = two footprints of b (a body and a body's gap)
//   closing: the outranged side loses f = e x (range gap / its speed) x its cost / (its hp x their cost)
//   Rs     = (e_ab / hp_b) ((1 - f_a) / c_a)^2 / ((e_ba / hp_a) ((1 - f_b) / c_b)^2);  V = 2 Rs / (1 + Rs)
//   a winner slower than b: V = 1 + (V - 1) x v_a / v_b (it cannot catch what it beats)
//   alpha_b >= hp_a: V = 0 (a unit does not engage what kills it in one hit)
// Role split: where a outruns b it can go round b to their economy instead: V' = max(V, 2 rho),
//   rho = R / (R + A), R = max(0, their known economy metal - our metal in units this model sends raiding),
//   A = their army metal in the mix. Factor = sum_b w_b V'_ab.
// The mix: every armed ground mobile foemem holds, at its metal, fading linearly to nothing over the memory's
// own horizon (apex_ghost_stale_min); plus one pseudo-unit of the prior: the ground fighters of every basic land
// plant that builds something of theirs we have seen (all of them before we have seen any), equal shares.
// Refreshed every 5 s; elections read the cache.

bool gCmOn = false;
int gCmOnAt = -1;

bool CounterMixOn()
{
	if (gCmOnAt != ai.frame) {
		gCmOnAt = ai.frame;
		gCmOn = ai.GetTunable("apex_counter_mix", TUNE_COUNTER_MIX) > 0.f;
	}
	return gCmOn;
}

// ---- the pair table ----
array<int> gCmIx;                 // def -> compact index + 1
array<int> gCmIxDef;
array<array<float>> gCmRow;       // [ia][ib], -1 = not taken

bool CmGround(int d)
{
	return Catalog::ValidId(d) && Catalog::gMobile[d] && !Catalog::gFlyer[d] && !Catalog::gBuilder[d]
		&& !Catalog::gKamikaze[d] && (Catalog::gSurfDps[d] > 0.f) && (Catalog::gSurfT[d] > 0.f)
		&& (Catalog::gLandRange[d] > 0.f) && (Catalog::gHealth[d] > 0.f) && (Catalog::gCostM[d] > 0.f)
		&& !Military::CfIsCom(d);
}

int CmIndex(int d)
{
	if (int(gCmIx.length()) <= d)
		gCmIx.resize(d + 1);
	if (gCmIx[d] == 0) {
		gCmIxDef.insertLast(d);
		gCmRow.insertLast(array<float>());
		gCmIx[d] = int(gCmIxDef.length());
	}
	return gCmIx[d] - 1;
}

float CmEff(int x, int y)
{
	float foot = float((Catalog::gFootX[y] > Catalog::gFootZ[y]) ? Catalog::gFootX[y] : Catalog::gFootZ[y]) * 16.f;
	if (foot < 8.f)
		foot = 8.f;
	const float s = 2.f * foot;
	const float r = Catalog::gAoe[x];
	float cov = 3.14159265f * r * r / (s * s) - 1.f;
	cov = 1.f + ((cov > 0.f) ? cov / 3.f : 0.f);
	float e = Catalog::gSurfDps[x] * cov;
	const float al = Catalog::gSurfAlpha[x];
	if (al > Catalog::gHealth[y])
		e *= Catalog::gHealth[y] / al;
	return e;
}

float CmClose(float eFoe, float gap, float spd, float c, float h, float cFoe)
{
	if (gap <= 0.f)
		return 0.f;
	if (spd <= 0.f)
		return 1.f;
	const float f = eFoe * (gap / spd) * c / (h * cFoe);
	return (f > 1.f) ? 1.f : f;
}

float CmPairCalc(int a, int b)
{
	const float ha = Catalog::gHealth[a], hb = Catalog::gHealth[b];
	if (Catalog::gSurfAlpha[b] >= ha)
		return 0.f;
	const float ca = Catalog::gCostM[a], cb = Catalog::gCostM[b];
	const float eab = CmEff(a, b), eba = CmEff(b, a);
	if (eab <= 0.f)
		return 0.f;
	if (eba <= 0.f)
		return 2.f;
	const float va = Catalog::gSpeed[a], vb = Catalog::gSpeed[b];
	const float ra = Catalog::gLandRange[a], rb = Catalog::gLandRange[b];
	const float fa = CmClose(eba, rb - ra, va, ca, ha, cb);
	const float fb = CmClose(eab, ra - rb, vb, cb, hb, ca);
	const float na = (1.f - fa) / ca, nb = (1.f - fb) / cb;
	const float sB = (eba / ha) * nb * nb;
	if (sB <= 0.f)
		return 2.f;
	const float rs = (eab / hb) * na * na / sB;
	float v = 2.f * rs / (1.f + rs);
	if ((rs > 1.f) && (vb > va) && (vb > 0.f))
		v = 1.f + (v - 1.f) * va / vb;
	return v;
}

float CmPair(int a, int b)
{
	const int ia = CmIndex(a), ib = CmIndex(b);
	array<float>@ row = gCmRow[ia];
	if (int(row.length()) <= ib) {
		const uint was = row.length();
		row.resize(ib + 1);
		for (uint k = was; k < row.length(); ++k)
			row[k] = -1.f;
	}
	if (row[ib] < 0.f)
		row[ib] = CmPairCalc(a, b);
	return row[ib];
}

// ---- the enemy mix ----
array<int> gCmMixDef;
array<float> gCmMixW;            // shares, summing to 1
float gCmSeenM = 0.f, gCmPriorM = 0.f, gCmArmyM = 0.f;
array<bool> gCmEver;             // defs of theirs ever seen
array<int> gCmPlants;            // basic land plants
bool gCmPlantsSet = false;
int gCmAt = -999999;
int gCmStamp = 0;
float gCmRho = 0.f, gCmEcoM = 0.f, gCmRaidSup = 0.f;
int gCmPriorPlants = 0;
// their economy, swept from the registry in two halves
int gCmScanI = 0, gCmScanTotal = 0;
float gCmEcoAcc = 0.f;

void CmPlantsFill()
{
	if (gCmPlantsSet)
		return;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || (PlantTier(d) != 1) || (PlantClass(d) != PC_LAND))
			continue;
		const array<int>@ pr = Catalog::gBuildsList[d];
		bool any = false;
		for (uint q = 0; (q < pr.length()) && !any; ++q)
			any = CmGround(pr[q]);
		if (any)
			gCmPlants.insertLast(d);
	}
	gCmPlantsSet = gCmPlants.length() > 0;
}

void CmMixAdd(array<int>& defs, array<float>& w, int d, float m)
{
	const int i = defs.find(d);
	if (i < 0) {
		defs.insertLast(d);
		w.insertLast(m);
	} else {
		w[i] += m;
	}
}

void CmEcoStep()
{
	if (gCmScanI == 0) {
		gCmScanTotal = aiEnemyMgr.GetEnemyUnitTotal();
		gCmEcoAcc = 0.f;
	}
	const int chunk = gCmScanTotal / 2 + 1;
	const int end = (gCmScanI + chunk < gCmScanTotal) ? gCmScanI + chunk : gCmScanTotal;
	for (int i = gCmScanI; i < end; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if (!Catalog::ValidId(d))
			continue;
		const bool eco = (!Catalog::gMobile[d] && ((Catalog::gExtractsM[d] > 0.f) || (Catalog::gMakeE[d] > 0.f)
				|| (Catalog::gConvCapacity[d] > 0.f)))
			|| (Catalog::gBuilder[d] && Catalog::gMobile[d] && !Military::CfIsCom(d));
		if (!eco)
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (4 | 8 | 32 | 64)) != 0))
			continue;
		gCmEcoAcc += Catalog::gCostM[d];
	}
	gCmScanI = end;
	if (gCmScanI < gCmScanTotal)
		return;
	gCmScanI = 0;
	gCmEcoM = gCmEcoAcc;
}

void CmRefresh()
{
	gCmAt = ai.frame;
	++gCmStamp;
	CmPlantsFill();
	if (int(gCmEver.length()) <= Catalog::gDefCount)
		gCmEver.resize(Catalog::gDefCount + 1);
	array<int> defs;
	array<float> w;
	const float staleS = ai.GetTunable("apex_ghost_stale_min", 15.f) * 60.f;
	float seen = 0.f;
	for (uint s = 0; s < Military::gFmId.length(); ++s) {
		if (Military::gFmId[s] < 0)
			continue;
		const int d = Military::gFmDef[s];
		if (!CmGround(d))
			continue;
		gCmEver[d] = true;
		float k = 1.f;
		if (!Military::gFmLive[s]) {
			const float age = float(ai.frame - Military::gFmSeen[s]) / float(SECOND);
			k = (staleS > 0.f) ? 1.f - age / staleS : 0.f;
		}
		if (k <= 0.f)
			continue;
		CmMixAdd(defs, w, d, Catalog::gCostM[d] * k);
		seen += Catalog::gCostM[d] * k;
	}
	// the prior: their basic plants, as far as what we have seen tells them apart
	array<int> pDefs;
	array<float> pW;
	int nPl = 0;
	for (int pass = 0; (pass < 2) && (nPl == 0); ++pass) {
		for (uint p = 0; p < gCmPlants.length(); ++p) {
			const array<int>@ pr = Catalog::gBuildsList[gCmPlants[p]];
			bool match = pass == 1;
			for (uint q = 0; (q < pr.length()) && !match; ++q)
				match = (pr[q] < int(gCmEver.length())) && gCmEver[pr[q]];
			if (!match)
				continue;
			int nP = 0;
			for (uint q = 0; q < pr.length(); ++q) {
				if (CmGround(pr[q]))
					++nP;
			}
			if (nP == 0)
				continue;
			++nPl;
			for (uint q = 0; q < pr.length(); ++q) {
				if (CmGround(pr[q]))
					CmMixAdd(pDefs, pW, pr[q], 1.f / float(nP));
			}
		}
	}
	gCmPriorPlants = nPl;
	float pM = 0.f, pN = 0.f;
	for (uint i = 0; i < pDefs.length(); ++i) {
		pM += pW[i] * Catalog::gCostM[pDefs[i]];
		pN += pW[i];
	}
	const float prior = (pN > 0.f) ? pM / pN : 0.f;
	for (uint i = 0; i < pDefs.length(); ++i)
		CmMixAdd(defs, w, pDefs[i], prior * pW[i] / pN);
	float tot = 0.f;
	for (uint i = 0; i < w.length(); ++i)
		tot += w[i];
	if (tot > 0.f) {
		for (uint i = 0; i < w.length(); ++i)
			w[i] /= tot;
	}
	gCmMixDef = defs;
	gCmMixW = w;
	gCmSeenM = seen;
	gCmPriorM = (pN > 0.f) ? prior : 0.f;
	gCmArmyM = tot;
	// our metal this model sends round them, at the last refresh's rho
	float sup = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int a = own[i];
		if ((gOwnCount[a] <= 0) || !CmGround(a))
			continue;
		float fight, raid;
		CmFactorParts(a, fight, raid);
		const float tot2 = fight + raid;
		if (tot2 > 0.f)
			sup += float(gOwnCount[a]) * Catalog::gCostM[a] * raid / tot2;
	}
	gCmRaidSup = sup;
	const float R = (gCmEcoM > sup) ? gCmEcoM - sup : 0.f;
	gCmRho = (R + gCmArmyM > 0.f) ? R / (R + gCmArmyM) : 0.f;
}

// The factor's two halves: fight value where a fights b, raid value where a goes round b instead.
void CmFactorParts(int a, float& out fight, float& out raid)
{
	fight = 0.f;
	raid = 0.f;
	const float rv = 2.f * gCmRho;
	for (uint i = 0; i < gCmMixDef.length(); ++i) {
		const int b = gCmMixDef[i];
		const float v = CmPair(a, b);
		if ((Catalog::gSpeed[a] > Catalog::gSpeed[b]) && (rv > v))
			raid += gCmMixW[i] * rv;
		else
			fight += gCmMixW[i] * v;
	}
}

array<int> gCmFacAt;
array<float> gCmFac;
array<float> gCmFacRaid;

// The candidate's multiplier; 1 when it is no ground fighter or nothing is known of them.
float CounterMixFactor(int d)
{
	if (!CmGround(d) || Catalog::gFloater[d] || Catalog::gSub[d] || (gCmMixDef.length() == 0))
		return 1.f;
	if (int(gCmFacAt.length()) <= d) {
		gCmFacAt.resize(d + 1);
		gCmFac.resize(d + 1);
		gCmFacRaid.resize(d + 1);
	}
	if (gCmFacAt[d] != gCmStamp) {
		gCmFacAt[d] = gCmStamp;
		float fight, raid;
		CmFactorParts(d, fight, raid);
		gCmFac[d] = fight + raid;
		gCmFacRaid[d] = raid;
	}
	return gCmFac[d];
}

// ---- the minute line ----
array<int> gCmCandDef;
array<int> gCmCandAt;
array<int> gCmOrdDef;
array<int> gCmOrdN;
int gCmApplied = 0, gCmSkipped = 0;
float gCmShiftSum = 0.f;
int gCmLogAt = 1800;

// After the draw's own renormalisation: the ground army candidates at idx take their factor, and are scaled back
// so their total is what it was.
void CounterMixApply(array<float>& candV, array<float>& candGain, const array<int>@ candDef, const array<uint>@ idx)
{
	if (idx.length() == 0)
		return;
	float before = 0.f, after = 0.f;
	array<float> f(idx.length());
	for (uint i = 0; i < idx.length(); ++i) {
		const uint k = idx[i];
		f[i] = CounterMixFactor(candDef[k]);
		before += candV[k];
		after += candV[k] * f[i];
		const int d = candDef[k];
		const int j = gCmCandDef.find(d);
		if (j < 0) {
			gCmCandDef.insertLast(d);
			gCmCandAt.insertLast(ai.frame);
		} else {
			gCmCandAt[j] = ai.frame;
		}
	}
	if ((before <= 0.f) || (after <= 0.f)) {
		++gCmSkipped;
		return;
	}
	const float norm = before / after;
	float shift = 0.f;
	for (uint i = 0; i < idx.length(); ++i) {
		const uint k = idx[i];
		const float nv = candV[k] * f[i] * norm;
		shift += abs(nv - candV[k]);
		candGain[k] *= f[i] * norm;
		candV[k] = nv;
	}
	++gCmApplied;
	gCmShiftSum += shift / before;
}

void CounterMixNoteOrder(const CCircuitDef@ o)
{
	if (!CounterMixOn() || (o is null) || Catalog::gBuilder[int(o.id)])
		return;
	const int d = int(o.id);
	const int i = gCmOrdDef.find(d);
	if (i < 0) {
		gCmOrdDef.insertLast(d);
		gCmOrdN.insertLast(1);
	} else {
		++gCmOrdN[i];
	}
}

void CounterMixUpdate()
{
	if (!CounterMixOn())
		return;
	CmEcoStep();
	if (ai.frame >= gCmAt + 5 * SECOND)
		CmRefresh();
	if (ai.frame < gCmLogAt)
		return;
	gCmLogAt = ai.frame + 60 * SECOND;
	string mix = "";
	{
		array<bool> used(gCmMixDef.length(), false);
		for (int n = 0; n < 5; ++n) {
			int bi = -1;
			for (uint i = 0; i < gCmMixDef.length(); ++i) {
				if (!used[i] && ((bi < 0) || (gCmMixW[i] > gCmMixW[bi])))
					bi = int(i);
			}
			if (bi < 0)
				break;
			used[bi] = true;
			mix += " " + Catalog::Def(gCmMixDef[bi]).GetName() + ":" + int(gCmMixW[bi] * gCmArmyM) + "m";
		}
	}
	string ours = "";
	{
		array<int> live;
		for (uint i = 0; i < gCmCandDef.length(); ++i) {
			if (ai.frame - gCmCandAt[i] <= 60 * SECOND)
				live.insertLast(gCmCandDef[i]);
		}
		array<bool> used(live.length(), false);
		for (int n = 0; n < 5; ++n) {
			int bi = -1;
			for (uint i = 0; i < live.length(); ++i) {
				if (!used[i] && ((bi < 0) || (CounterMixFactor(live[i]) > CounterMixFactor(live[bi]))))
					bi = int(i);
			}
			if (bi < 0)
				break;
			used[bi] = true;
			const int d = live[bi];
			const float fct = CounterMixFactor(d);
			const float rd = (int(gCmFacRaid.length()) > d) ? gCmFacRaid[d] : 0.f;
			ours += " " + Catalog::Def(d).GetName() + ":" + NnF(fct, 2) + "(fight " + NnF(fct - rd, 2)
				+ " raid " + NnF(rd, 2) + ")";
		}
	}
	string ord = "";
	for (uint i = 0; i < gCmOrdDef.length(); ++i)
		ord += " " + Catalog::Def(gCmOrdDef[i]).GetName() + "=" + gCmOrdN[i];
	AiLog(Factory::T() + "apex: countermix-stat t=" + ai.teamId
		+ " seenM=" + int(gCmSeenM) + " priorM=" + int(gCmPriorM) + " plants=" + gCmPriorPlants
		+ " eco=" + int(gCmEcoM) + " raidSup=" + int(gCmRaidSup) + " rho=" + NnF(gCmRho, 2)
		+ " pairs=" + gCmIxDef.length() + " applied=" + gCmApplied + " skipped=" + gCmSkipped
		+ " shift=" + NnF((gCmApplied > 0) ? gCmShiftSum / float(gCmApplied) : 0.f, 2)
		+ " | mix:" + mix + " | ours:" + ours + " | ord:" + ord);
	gCmOrdDef.resize(0);
	gCmOrdN.resize(0);
	gCmApplied = 0;
	gCmSkipped = 0;
	gCmShiftSum = 0.f;
}

}  // namespace Market
