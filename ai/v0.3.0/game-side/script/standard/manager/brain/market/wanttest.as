namespace Market {
// THE WANT TEST (apex_wanttest=1, driven by tools/wanttest.py). The first
// constructor that can build a fusion-class generator is kept; then, one row
// per second, the real ProposeEnergy prices every generator it can build with
// the economy POSED at that row, and the whole ladder is logged. Everything
// else -- what stands, what is in flight, the map -- is this game's own.
// A row sets the smoothed histories to the steady state of its pose, so the
// ladder does not price against the real game's past.

bool gWtRunning = false;
int gWtUnit = -1;
int gWtRow = -1;
int gWtNextAt = 0;
bool gWtDone = false;

// metal income, energy income -- one row each
const array<float> WT_M = { 100.f, 150.f, 250.f, 381.f, 600.f, 800.f, 1000.f, 1500.f };
const array<float> WT_E = { 1700.f, 2500.f, 4200.f, 6500.f, 10200.f, 13600.f, 17000.f, 25500.f };

bool WantTestOn()
{
	return ai.GetTunable("apex_wanttest", 0.f) > 0.f;
}

// Offered every election; keeps the first hand that can build a fusion-class
// generator (a def making 1000+ E/s).
void WantTestOffer(CCircuitUnit@ unit)
{
	if (gWtDone || (gWtUnit >= 0) || !WantTestOn())
		return;
	const array<int>@ b = Catalog::BuildsOf(int(unit.circuitDef.id));
	for (uint i = 0; i < b.length(); ++i) {
		if (Catalog::gAvailable[b[i]] && (Catalog::gMakeE[b[i]] >= 1000.f)) {
			gWtUnit = int(unit.id);
			gWtRow = 0;
			gWtNextAt = ai.frame + SECOND;
			AiLog("apex: wanttest begin t=" + ai.teamId + " by="
				+ unit.circuitDef.GetName() + " #" + unit.id
				+ " rows=" + (2 * WT_M.length()));
			return;
		}
	}
}

void WantTestTick()
{
	if (gWtDone || (gWtUnit < 0) || (ai.frame < gWtNextAt))
		return;
	gWtNextAt = ai.frame + SECOND;
	CCircuitUnit@ u = ai.GetTeamUnit(gWtUnit);
	if (u is null) {
		AiLog("apex: wanttest lost the hand #" + gWtUnit + " -- waiting for another");
		gWtUnit = -1;
		return;
	}
	if (gWtRow >= int(2 * WT_M.length())) {
		gWtDone = true;
		AiLog("apex: wanttest end t=" + ai.teamId);
		return;
	}
	const float m = WT_M[gWtRow / 2];
	const float e = WT_E[gWtRow / 2];
	// Odd rows: half the energy already has converters behind it; even: a tenth.
	const float conv = e * (((gWtRow % 2) == 1) ? 0.5f : 0.1f);
	const float mStor = Eco::MStor();
	const float eStor = Eco::EStor();
	// Spending all its metal, energy drawn at nine tenths, banks half full.
	const float mPull = m;
	const float ePull = 0.9f * e;

	const float sEsur = gESurplusEma, sEexc = gEExcessEma, sEpk = gEDemandPk;
	const float sMpk = gMDemandPk, sInc = gIncEma, sIncG = gIncGrowth;
	const float sEg = gEPullGrowth, sMg = gMPullGrowth, sSpare = gMSpareEma;
	Eco::Pose(m, e, 0.5f * mStor, 0.5f * eStor, mPull, ePull, mStor, eStor);
	Eco::PoseConverters(conv, conv);
	gESurplusEma = e - ePull;
	gEExcessEma = 0.f;
	gEDemandPk = ePull - ConvUseE();
	if (gEDemandPk < 0.f)
		gEDemandPk = 0.f;
	gMDemandPk = mPull;
	gIncEma = m;
	gIncGrowth = 0.f;
	gEPullGrowth = 0.f;
	gMPullGrowth = 0.f;
	gMSpareEma = 0.f;

	gWtRunning = true;
	AiLog("apex: wanttest row=" + gWtRow + " mInc=" + int(m) + " eInc=" + int(e)
		+ " conv=" + int(conv)
		+ " ecoP=" + int(EcoPowerM()));
	Want@ w = ProposeEnergy(u);
	gWtRunning = false;
	AiLog("apex: wanttest pick row=" + gWtRow + " mInc=" + int(m)
		+ " -> " + (((w !is null) && (w.def !is null)) ? w.def.GetName() : "none")
		+ " v=" + formatFloat((w !is null) ? w.value * 1000.f : 0.f, "", 0, 2));

	Eco::Clear();
	gESurplusEma = sEsur; gEExcessEma = sEexc; gEDemandPk = sEpk;
	gMDemandPk = sMpk; gIncEma = sInc; gIncGrowth = sIncG;
	gEPullGrowth = sEg; gMPullGrowth = sMg; gMSpareEma = sSpare;
	++gWtRow;
}

}  // namespace Market
