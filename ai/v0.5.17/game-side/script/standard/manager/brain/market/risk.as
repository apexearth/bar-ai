namespace Market {

// THE LEARNED JOB RISK (his 11-04, todo/learn-from-each-decision.md; TUNE_LEARNED_RISK). The chance a build job's frame
// dies unfinished and the chance its builder is killed on it, from what the AI knows when it prices the want, fitted on
// the outcomes of every job in the ledger (tools/risknet.py; weights in riskweights.as). On, it replaces the exposure
// charge, the trip risk and the extractor's own survival terms: the gain is worth (1 - pFrame), and the builder's worth
// times pBuilder joins the cost. Measured 11-04 on 111 held-out games: the price expected 6.8% of jobs to fail, 22.7%
// did; this model AUC 0.81 (frame) and 0.89 (builder) against 0.72 for the price.

int gRkOn = -1;
int gRkN = 0;
float gRkPF = 0.f, gRkPB = 0.f, gRkScale = 0.f;
int gRkLogAt = 3600;
int gRkXLogAt = 1800;
array<float> gRkX;

bool LearnedRiskOn()
{
	if (gRkOn < 0) {
		gRkOn = 0;
		if (ai.GetTunable("apex_learned_risk", TUNE_LEARNED_RISK) > 0.f) {
			const bool fits = (RISK_STATE == NN_STATE) && (int(RISK_MU.length()) == RISK_NK + RISK_NO + RISK_NS)
					&& (RISK_W_FRAME.length() == RISK_MU.length()) && (RISK_W_BUILDER.length() == RISK_MU.length());
			gRkOn = fits ? 1 : 0;
			AiLog("apex: risk t=" + ai.teamId + " on=" + gRkOn + (fits ? "" : " (weights do not fit this state layout)"));
		}
	}
	return gRkOn > 0;
}

array<int> gRkKindOf;
// The extractor keeps its own survival and trip pricing (want_mex.as): with it replaced, the 24-pair A/B lost 8.1 m/s
// of income at minute 8 (11-04).
int RiskKindIndex(int kind)
{
	if (kind == WK_MEX)
		return -1;
	if (gRkKindOf.length() == 0) {
		const array<string>@ ks = RISK_KINDS.split(",");
		gRkKindOf.resize(64);
		for (int k = 0; k < 64; ++k) {
			gRkKindOf[k] = -1;
			const string n = KindName(k);
			for (uint i = 0; i < ks.length(); ++i) {
				if (ks[i] == n)
					gRkKindOf[k] = int(i);
			}
		}
	}
	return ((kind >= 0) && (kind < int(gRkKindOf.length()))) ? gRkKindOf[kind] : -1;
}

float RkLog1p(float x)
{
	return log(1.f + ((x > 0.f) ? x : 0.f));
}

// The model's inputs, built as NnOptFull and NnState build the logged ones (tools/risknet.py opt_feats): the kind
// one-hot, then the option's twelve. The state's share is RkStateZ's.
bool RiskInputs(Want@ w, CCircuitUnit@ unit, array<float>& out x, int &out ki)
{
	ki = -1;
	if ((w is null) || (w.def is null) || (unit is null) || !OnMap(w.pos))
		return false;
	ki = RiskKindIndex(w.kind);
	if (ki < 0)
		return false;
	const int di = int(w.def.id);
	if (di >= int(Catalog::gCostM.length()))
		return false;
	const AIFloat3 up = unit.GetPos(ai.frame);
	x.resize(RISK_NK + RISK_NO);
	for (int i = 0; i < RISK_NK; ++i)
		x[i] = (i == ki) ? 1.f : 0.f;
	const float m = w.mCost;
	const float rate = ExpectedLossAt(w.pos, m) / ((m > 1.f) ? m : 1.f);
	int o = RISK_NK;
	x[o++] = RkLog1p(m);
	x[o++] = RkLog1p(Catalog::gCostM[di]);
	x[o++] = RkLog1p(Catalog::gCostE[di]);
	x[o++] = RkLog1p(Catalog::gBuildTime[di]);
	x[o++] = RkLog1p(w.pos.distance2D(up));
	x[o++] = DPowerOf(w, di);
	x[o++] = (di < int(gOwnCount.length())) ? float(gOwnCount[di]) : 0.f;
	x[o++] = float(DefTier(di));
	x[o++] = Military::ForwardFraction(w.pos);
	x[o++] = RkLog1p(LossRateAt(w.pos));
	x[o++] = log(((rate > 0.f) ? rate : 0.f) + 0.000001f);
	x[o++] = RkLog1p(Catalog::gCostM[int(unit.circuitDef.id)]);
	return true;
}

float RkStd(int i, float v)
{
	v = (v - RISK_MU[i]) / RISK_SD[i];
	return (v < -8.f) ? -8.f : ((v > 8.f) ? 8.f : v);
}

// The state's share of both heads, once per unit per tick (NnState refreshes on the tick).
Id gRkStUnit = Id(-1);
int gRkStTick = -1;
float gRkStF = 0.f, gRkStB = 0.f;
array<float> gRkSt;
void RkStateZ(CCircuitUnit@ unit)
{
	if ((unit.id == gRkStUnit) && (Main::gUpTick == gRkStTick))
		return;
	gRkStUnit = unit.id;
	gRkStTick = Main::gUpTick;
	NnState(unit, gRkSt);
	gRkStF = 0.f;
	gRkStB = 0.f;
	const int o = RISK_NK + RISK_NO;
	for (int i = 0; (i < RISK_NS) && (i < int(gRkSt.length())); ++i) {
		const float z = RkStd(o + i, gRkSt[i]);
		gRkStF += RISK_W_FRAME[o + i] * z;
		gRkStB += RISK_W_BUILDER[o + i] * z;
	}
}

float RkSig(float z)
{
	return 1.f / (1.f + pow(2.718282f, -z));
}

// pFrame, pBuilder for this want and this builder; false when the model does not cover the want.
bool LearnedRisk(Want@ w, CCircuitUnit@ unit, float &out pF, float &out pB)
{
	pF = 0.f;
	pB = 0.f;
	int ki;
	if (!RiskInputs(w, unit, gRkX, ki))
		return false;
	RkStateZ(unit);
	float zF = RISK_B_FRAME + RISK_W_FRAME[ki] + gRkStF;
	float zB = RISK_B_BUILDER + RISK_W_BUILDER[ki] + gRkStB;
	for (int i = RISK_NK; i < RISK_NK + RISK_NO; ++i) {
		const float z = RkStd(i, gRkX[i]);
		zF += RISK_W_FRAME[i] * z;
		zB += RISK_W_BUILDER[i] * z;
	}
	pF = RkSig(zF);
	pB = RkSig(zB);
	return true;
}

// What the builder stakes on a job: his metal, or for the commander everything we own (his death is the game).
float RiskBuilderWorth(CCircuitUnit@ unit)
{
	return unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask) ? (gAssetsM + ArmyValue())
			: Catalog::gCostM[int(unit.circuitDef.id)];
}

// The learned price on one want: gain x (1 - pF) x (m + t) / (m + t + pB x worth). Returns false when not covered.
bool ApplyLearnedRisk(Want@ c, CCircuitUnit@ unit)
{
	float pF, pB;
	if (!LearnedRisk(c, unit, pF, pB))
		return false;
	const float mt = c.mCost + c.tCost;
	if (mt <= 0.f)
		return true;
	const float scale = (1.f - pF) * mt / (mt + pB * RiskBuilderWorth(unit));
	c.gain *= scale;
	c.rkScale = scale;
	c.value = (c.gain > 0.f) ? (c.gain / mt) : 0.f;
	++gRkN;
	gRkPF += pF;
	gRkPB += pB;
	gRkScale += scale;
	if (ai.frame >= gRkXLogAt) {
		// one want's raw inputs and answer, so tools/risknet.py check can recompute it (the export is exact or it is wrong)
		gRkXLogAt = ai.frame + 30 * SECOND;
		string xs = "";
		for (uint i = 0; i < gRkX.length(); ++i)
			xs += ((i > 0) ? "," : "") + formatFloat(gRkX[i], "", 0, 5);
		for (uint i = 0; i < gRkSt.length(); ++i)
			xs += "," + formatFloat(gRkSt[i], "", 0, 5);
		AiLog("apex: risk-x t=" + ai.teamId + " p=" + formatFloat(pF, "", 0, 5) + "," + formatFloat(pB, "", 0, 5) + " | " + xs);
	}
	if (ai.frame >= gRkLogAt) {
		gRkLogAt = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: risk-stat t=" + ai.teamId + " n=" + gRkN
			+ " pFrame=" + formatFloat(gRkPF / float(gRkN), "", 0, 3) + " pBuilder=" + formatFloat(gRkPB / float(gRkN), "", 0, 3)
			+ " scale=" + formatFloat(gRkScale / float(gRkN), "", 0, 3));
		gRkN = 0;
		gRkPF = gRkPB = gRkScale = 0.f;
	}
	return true;
}

}  // namespace Market
