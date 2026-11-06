namespace Market {

// THE FORECAST (his 10-21: "we should be able to forecast our metal, energy, and build power needs a certain amount
// ahead of time"; "so they're ready when we need them"). Every building coming (the ledger's ordered and framed
// rows) finishes at its remaining build time over the hands on it -- the crew of its request and the turrets that
// reach it, slowed by an energy stall -- and on finishing adds what it makes: energy, converter capacity, build
// power, extraction. Fc*(h) answers "what will income and build power be h seconds from now". Proven before any want
// reads it: every 2 s the 60-second forecast is stored and, a minute later, held against what happened, beside the
// error of assuming nothing changes.

const float FC_STEP_S = 2.f;
const float FC_HORIZON_S = 60.f;

array<float> gFcEta;     // per coming row: seconds to finish, -1 never
array<int> gFcDef;
array<float> gFcEtaRow;  // the same, indexed by ledger row (rows shift between refreshes: at most 2 s stale)
int gFcAt = -999999;
float gFcMetalPerX = 0.f;   // metal a second per unit of extractsMetal we stand on

float FcRowEta(uint i)
{
	const int d = gComDef[i];
	if (!Catalog::ValidId(d) || (Catalog::gBuildTime[d] <= 1.f))
		return -1.f;
	float bp = 0.f;
	IUnitTask@ t = gComTask[i];
	if (t !is null) {
		array<CCircuitUnit@>@ crew = t.GetUnits();
		if (crew !is null)
			for (uint c = 0; c < crew.length(); ++c)
				if ((crew[c] !is null) && (crew[c].circuitDef !is null))
					bp += Catalog::gBuildPower[int(crew[c].circuitDef.id)];
	}
	// the turrets free to help: one at work elsewhere is not this row's crew (every turret in reach read as crew
	// over-forecast build power 75% once, twelve turrets that did not come)
	if (OnMap(gComPos[i]))
		bp += IdleNanoLatheNear(gComPos[i]) * (80.f / 7.f);
	if (bp <= 1.f)
		return -1.f;
	// An energy stall shares income across every build.
	float k = 1.f;
	if ((Eco::ECur() < 0.05f * Eco::EStor()) && (Eco::EPull() > Eco::EInc()) && (Eco::EPull() > 1.f))
		k = Eco::EInc() / Eco::EPull();
	if (k < 0.05f)
		k = 0.05f;
	return Catalog::gBuildTime[d] * (1.f - ComProgress(i)) / (bp * k);
}

void FcRefresh()
{
	if (ai.frame - gFcAt < int(FC_STEP_S * float(SECOND)))
		return;
	gFcAt = ai.frame;
	gFcEta.resize(0);
	gFcDef.resize(0);
	gFcEtaRow.resize(ComLen());
	for (uint i = 0; i < ComLen(); ++i) {
		gFcEtaRow[i] = 1e9f;
		if ((gComState[i] & CS_COMING) == 0)
			continue;
		const float eta = FcRowEta(i);
		gFcEta.insertLast(eta);
		gFcDef.insertLast(gComDef[i]);
		gFcEtaRow[i] = (eta < 0.f) ? 1e9f : eta;
	}
	// What one unit of extractsMetal yields here, off what our extractors make now: income less what the
	// converters chew.
	float x = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint oi = 0; oi < own.length(); ++oi) {
		const int d = own[oi];
		if ((gOwnCount[d] > 0) && (Catalog::gExtractsM[d] > 0.f))
			x += float(gOwnCount[d]) * Catalog::gExtractsM[d];
	}
	float mex = Eco::MInc() - ConvUseE() * BestConvRatio();
	if (mex < 0.f)
		mex = 0.f;
	gFcMetalPerX = (x > 0.f) ? (mex / x) : 0.f;
}

// Seconds to finish of ledger row i as of the last refresh; a row the refresh has not seen is far off.
float FcEtaOf(uint i)
{
	return (i < gFcEtaRow.length()) ? gFcEtaRow[i] : 1e9f;
}

// The basic extractor's rate: an upgrade adds only what it extracts beyond it. Found once.
float gFcBaseX = -1.f;
float FcBaseX()
{
	if (gFcBaseX > 0.f)
		return gFcBaseX;
	for (int d = 1; d <= Catalog::gDefCount; ++d)
		if (Catalog::gAvailable[d] && !Catalog::gMobile[d] && (Catalog::gExtractsM[d] > 0.f)
			&& ((gFcBaseX <= 0.f) || (Catalog::gExtractsM[d] < gFcBaseX)))
			gFcBaseX = Catalog::gExtractsM[d];
	return (gFcBaseX > 0.f) ? gFcBaseX : 0.f;
}

// What finishes within h seconds adds, by kind. Cached until the rows refresh: a want asking three times an
// election costs one pass.
float gFcE, gFcConv, gFcBP, gFcM;
float gFcSumH = -1.f;
int gFcSumAt = -1;
void FcSum(float h)
{
	FcRefresh();
	if ((gFcSumAt == gFcAt) && (gFcSumH == h))
		return;
	gFcSumAt = gFcAt;
	gFcSumH = h;
	gFcE = 0.f; gFcConv = 0.f; gFcBP = 0.f; gFcM = 0.f;
	const float base = FcBaseX();
	for (uint i = 0; i < gFcEta.length(); ++i) {
		if ((gFcEta[i] < 0.f) || (gFcEta[i] > h))
			continue;
		const int d = gFcDef[i];
		gFcE += Catalog::gMakeE[d];
		gFcConv += Catalog::gConvCapacity[d];
		if (Catalog::gBuildPower[d] > 0.f)
			gFcBP += Catalog::gBuildPower[d];
		if (Catalog::gExtractsM[d] > 0.f)
			gFcM += ((Catalog::gExtractsM[d] > base) ? (Catalog::gExtractsM[d] - base) : Catalog::gExtractsM[d]) * gFcMetalPerX;
	}
}

float FcEInc(float h) { FcSum(h); return Eco::EInc() + gFcE; }
float FcBP(float h) { FcSum(h); return BPCapacity() * (80.f / 7.f) + gFcBP; }
float FcMInc(float h)
{
	FcSum(h);
	// a converter coming makes metal only from energy spare to feed it
	float conv = gFcConv;
	const float spare = Eco::EInc() + gFcE - Eco::EPull();
	if (conv > spare)
		conv = (spare > 0.f) ? spare : 0.f;
	return Eco::MInc() + gFcM + conv * BestConvRatio();
}

// -- is it right ----------------------------------------------------------------------------------------------------
array<int> gFcLogAt;
array<float> gFcPredE, gFcPredM, gFcPredB, gFcNowE, gFcNowM, gFcNowB;
float gFcErrE = 0.f, gFcErrM = 0.f, gFcErrB = 0.f, gFcBaseE = 0.f, gFcBaseM = 0.f, gFcBaseB = 0.f;
int gFcErrN = 0, gFcLogNext = 0, gFcStoreAt = -999999;

float FcRel(float pred, float act) { return abs(pred - act) / ((act > 1.f) ? act : 1.f); }

void ForecastStep()
{
	if (!EcoOnly() && (ai.GetTunable("apex_forecast_log", TUNE_FORECAST_LOG) <= 0.f))
		return;
	if (ai.frame - gFcStoreAt >= int(FC_STEP_S * float(SECOND))) {
		gFcStoreAt = ai.frame;
		gFcLogAt.insertLast(ai.frame + int(FC_HORIZON_S * float(SECOND)));
		gFcPredE.insertLast(FcEInc(FC_HORIZON_S));
		gFcPredM.insertLast(FcMInc(FC_HORIZON_S));
		gFcPredB.insertLast(FcBP(FC_HORIZON_S));
		gFcNowE.insertLast(Eco::EInc());
		gFcNowM.insertLast(Eco::MInc());
		gFcNowB.insertLast(BPCapacity() * (80.f / 7.f));
	}
	while ((gFcLogAt.length() > 0) && (ai.frame >= gFcLogAt[0])) {
		const float ae = Eco::EInc(), am = Eco::MInc(), ab = BPCapacity() * (80.f / 7.f);
		gFcErrE += FcRel(gFcPredE[0], ae); gFcBaseE += FcRel(gFcNowE[0], ae);
		gFcErrM += FcRel(gFcPredM[0], am); gFcBaseM += FcRel(gFcNowM[0], am);
		gFcErrB += FcRel(gFcPredB[0], ab); gFcBaseB += FcRel(gFcNowB[0], ab);
		++gFcErrN;
		gFcLogAt.removeAt(0); gFcPredE.removeAt(0); gFcPredM.removeAt(0); gFcPredB.removeAt(0);
		gFcNowE.removeAt(0); gFcNowM.removeAt(0); gFcNowB.removeAt(0);
	}
	if ((ai.frame >= gFcLogNext) && (gFcErrN > 0)) {
		gFcLogNext = ai.frame + 60 * SECOND;
		const float n = float(gFcErrN);
		FcSum(FC_HORIZON_S);
		AiLog("apex: forecast t=" + ai.teamId + " h=60 err% e=" + int(100.f * gFcErrE / n) + " (flat " + int(100.f * gFcBaseE / n)
			+ ") m=" + int(100.f * gFcErrM / n) + " (flat " + int(100.f * gFcBaseM / n)
			+ ") bp=" + int(100.f * gFcErrB / n) + " (flat " + int(100.f * gFcBaseB / n) + ") n=" + gFcErrN
			+ " | next60 e+" + int(gFcE) + " conv+" + int(gFcConv) + " bp+" + int(gFcBP) + " m+" + formatFloat(gFcM, "", 0, 1)
			+ " rows=" + gFcEta.length());
		gFcErrE = 0.f; gFcErrM = 0.f; gFcErrB = 0.f; gFcBaseE = 0.f; gFcBaseM = 0.f; gFcBaseB = 0.f;
		gFcErrN = 0;
	}
}

}  // namespace Market
