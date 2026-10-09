namespace Military {

// TIMING WINDOWS (docs/35 nnstrike): a 12 s census of the moments attacking pays
// more -- their army away, a fight just won, theirs thinned or mid tech switch,
// ours at a peak -- and a head that picks NO (today's play) or STRIKE, which
// takes this AI's attack focus to their economy the way a hunt takes it.
const string NNS_STRIKE = "foeSeenM,foeAwayF,foeHomeM,bigM,bigAwayF,bigFwd,bigOurD,"
	+ "kill90,lost90,net90,armyLost90,foeDead90,foeDeadF,"
	+ "lnRatio,lnRatioB,trend60,peakGap,foeTier,tierUpS,"
	+ "tgtEcoM,tgtInfl,tgtNet,tgtD,ecoCells,atkPow,atkM,armyM,atkD,push,holdWhy,incoming,minute";
const int ST_NO = 0, ST_STRIKE = 1;
const float STRIKE_R = 800.f;
const float STRIKE_NEAR = 2.f * STRIKE_R;
const int STRIKE_S = 180;
const int STRIKE_LOOK = 4 * SECOND;
const int WN_EVERY = 12 * SECOND;
const int WN_BIN = 10 * SECOND;
const int WN_BINS = 12;
const int WN_SPAN = 9;          // bins summed: the last 90 s
const int WN_HIST_S = 300;      // the ratio's memory, for its trend and its local peak
const float WN_SMOOTH = 100.f;  // metal added to both sides of a ratio, so a blind 0 is not infinite

// deaths, binned by 10 s: our kills, our losses, our army's losses, their army seen dying (any killer)
array<float> gWnKill(WN_BINS, 0.f);
array<float> gWnLost(WN_BINS, 0.f);
array<float> gWnArmyLost(WN_BINS, 0.f);
array<float> gWnFoeDead(WN_BINS, 0.f);
array<int> gWnBinAt(WN_BINS, -1);
array<float> gWnHistR;
array<int> gWnHistF;
array<AIFloat3> gWnEcoP;        // their economy cells (enemy groups holding economy), as of the last census
array<float> gWnEcoM;
int gWnNextAt = -1;
int gWnAt = -1;
int gWnTierTop = 0;
int gWnTierUpAt = -1;
float gWnSeen = 0.f, gWnAwayF = 0.f, gWnHomeM = 0.f, gWnBigM = 0.f, gWnBigAwayF = 0.f, gWnBigFwd = 0.f;
float gWnBigOurD = 0.f, gWnKill90 = 0.f, gWnLost90 = 0.f, gWnArmyLost90 = 0.f, gWnFoeDead90 = 0.f;
float gWnDeadF = 0.f, gWnLnR = 0.f, gWnLnRB = 0.f, gWnTrend = 0.f, gWnPeak = 0.f, gWnTierNow = 0.f, gWnTierUpS = 0.f;

int gStNextAt = -1;
int gStLookAt = 0;
int gStLogAt = 0;
bool gStHeader = false;
bool gStOn = false;
bool gStGo = false;
int gStUntil = 0;
int gStFrom = 0;
AIFloat3 gStPos;
float gStKill = 0.f, gStLost = 0.f;
int gStDecN = 0, gStHitN = 0, gStExN = 0, gStGoN = 0, gStTimeN = 0, gStGoneN = 0, gStArmyN = 0;
int gStNoTgt = 0, gStNoArmy = 0, gStHuntOn = 0;

bool StrikeHoldsFocus() { return gStOn; }

int WnSlot()
{
	const int b = ai.frame / WN_BIN;
	const int s = b % WN_BINS;
	if (gWnBinAt[s] != b) {
		gWnBinAt[s] = b;
		gWnKill[s] = 0.f;
		gWnLost[s] = 0.f;
		gWnArmyLost[s] = 0.f;
		gWnFoeDead[s] = 0.f;
	}
	return s;
}

float WnSum(const array<float>& in a)
{
	const int b = ai.frame / WN_BIN;
	float t = 0.f;
	for (int k = 0; (k < WN_SPAN) && (b - k >= 0); ++k) {
		const int s = (b - k) % WN_BINS;
		if (gWnBinAt[s] == b - k)
			t += a[s];
	}
	return t;
}

// Both death hooks: a finished unit of ours an enemy killed, or an enemy death we saw.
void WindowNoteDeath(int d, const AIFloat3& in pos, float m, bool ours, bool byUs)
{
	if (m <= 0.f)
		return;
	const int s = WnSlot();
	if (ours) {
		gWnLost[s] += m;
		if (FmArmedGround(d))
			gWnArmyLost[s] += m;
	} else {
		if (byUs)
			gWnKill[s] += m;
		if (FmArmedGround(d))
			gWnFoeDead[s] += m;
	}
	if (gStOn && OnMap(pos) && (pos.distance2D(gStPos) <= STRIKE_NEAR)) {
		if (ours)
			gStLost += m;
		else if (byUs)
			gStKill += m;
	}
}

bool WnEcoDef(int d)
{
	return !Catalog::gMobile[d] && (Catalog::gMaxRange[d] <= 0.f)
		&& ((Catalog::gExtractsM[d] > 0.f) || (Catalog::gMakeE[d] > 0.f) || (Catalog::gMakeM[d] > 0.f)
			|| (Catalog::gConvCapacity[d] > 0.f) || (Catalog::gBuildPower[d] > 0.f));
}

// One walk of the enemy groups (LOS/radar and remembered buildings): O(units in them), every 12 s.
void WindowCensus()
{
	AIFloat3 fb = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(fb))
		fb = Front::FoeAnchor();
	const bool fbOk = OnMap(fb);
	const float baseD = fbOk ? fb.distance2D(Builder::gHomePos) : 0.f;
	const float span = (baseD > 1.f) ? baseD : 1.f;
	float seen = 0.f, awayW = 0.f, homeM = 0.f, bigM = 0.f;
	AIFloat3 bigP;
	int top = 0;
	gWnEcoP.resize(0);
	gWnEcoM.resize(0);
	const int n = aiEnemyMgr.GetEnemyGroupCount();
	for (int g = 0; g < n; ++g) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(g);
		if (!OnMap(gp))
			continue;
		float m = 0.f, eco = 0.f;
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(g);
		for (int k = 0; k < nU; ++k) {
			const int ud = aiEnemyMgr.GetEnemyGroupUnitDef(g, k);
			if ((ud <= 0) || (ud > Catalog::gDefCount))
				continue;
			if (FmArmedGround(ud)) {
				m += Catalog::gCostM[ud];
				const int tr = Market::DefTier(ud);
				if (tr > top)
					top = tr;
			} else if (WnEcoDef(ud)) {
				eco += Catalog::gCostM[ud];
			}
		}
		if (eco > 0.f) {
			gWnEcoP.insertLast(gp);
			gWnEcoM.insertLast(eco);
		}
		if (m <= 0.f)
			continue;
		seen += m;
		if (fbOk) {
			const float d = gp.distance2D(fb);
			awayW += m * d;
			if (d < 0.25f * span)
				homeM += m;
		}
		if (m > bigM) {
			bigM = m;
			bigP = gp;
		}
	}
	if (top > gWnTierTop) {
		gWnTierTop = top;
		gWnTierUpAt = ai.frame;
	}
	gWnSeen = seen;
	gWnAwayF = (fbOk && (seen > 0.f)) ? awayW / seen / span : -1.f;
	gWnHomeM = homeM;
	gWnBigM = bigM;
	gWnBigAwayF = (fbOk && (bigM > 0.f)) ? bigP.distance2D(fb) / span : -1.f;
	gWnBigFwd = (bigM > 0.f) ? ForwardFraction(bigP) : -1.f;
	gWnBigOurD = (bigM > 0.f) ? bigP.distance2D(Builder::gHomePos) / span : -1.f;
	gWnKill90 = WnSum(gWnKill);
	gWnLost90 = WnSum(gWnLost);
	gWnArmyLost90 = WnSum(gWnArmyLost);
	gWnFoeDead90 = WnSum(gWnFoeDead);
	gWnDeadF = (gWnFoeDead90 > 0.f) ? gWnFoeDead90 / (gWnFoeDead90 + seen) : 0.f;
	const float ours = TeamArmyCost();
	gWnLnR = log((ours + WN_SMOOTH) / (seen + WN_SMOOTH));
	gWnLnRB = log((ours + WN_SMOOTH) / (FoeBelievedM() + WN_SMOOTH));
	gWnHistR.insertLast(gWnLnRB);
	gWnHistF.insertLast(ai.frame);
	while ((gWnHistF.length() > 1) && (ai.frame - gWnHistF[0] > WN_HIST_S * SECOND)) {
		gWnHistF.removeAt(0);
		gWnHistR.removeAt(0);
	}
	float then = gWnLnRB, peak = gWnLnRB;
	for (uint i = 0; i < gWnHistF.length(); ++i) {
		if (ai.frame - gWnHistF[i] >= 60 * SECOND)
			then = gWnHistR[i];
		if (gWnHistR[i] > peak)
			peak = gWnHistR[i];
	}
	gWnTrend = gWnLnRB - then;
	gWnPeak = gWnLnRB - peak;
	gWnTierNow = float(top);
	const float up = (gWnTierUpAt >= 0) ? float(ai.frame - gWnTierUpAt) / float(SECOND) : Market::NN_ETA_CAP;
	gWnTierUpS = (up > Market::NN_ETA_CAP) ? Market::NN_ETA_CAP : up;
	gWnAt = ai.frame;
	AiLog(Factory::T() + "apex: window t=" + ai.teamId + " seen=" + int(seen)
		+ " away=" + Market::NnF(gWnAwayF, 2) + " home=" + int(homeM) + " big=" + int(bigM)
		+ " bigAway=" + Market::NnF(gWnBigAwayF, 2) + " bigFwd=" + Market::NnF(gWnBigFwd, 2)
		+ " bigOurD=" + Market::NnF(gWnBigOurD, 2)
		+ " kill=" + int(gWnKill90) + " lost=" + int(gWnLost90) + " net=" + int(gWnKill90 - gWnLost90)
		+ " armyLost=" + int(gWnArmyLost90) + " foeDead=" + int(gWnFoeDead90) + " deadF=" + Market::NnF(gWnDeadF, 2)
		+ " lnR=" + Market::NnF(gWnLnR, 2) + " lnRB=" + Market::NnF(gWnLnRB, 2)
		+ " trend=" + Market::NnF(gWnTrend, 2) + " peak=" + Market::NnF(gWnPeak, 2)
		+ " tier=" + top + " tierUpS=" + int(gWnTierUpS) + " eco=" + gWnEcoP.length()
		+ " strike=" + (gStOn ? 1 : 0));
}

// The richest economy cell of theirs we know of; their structures' centre if none.
bool StrikeTarget(AIFloat3& out at, float& out ecoM)
{
	ecoM = 0.f;
	int best = -1;
	for (uint i = 0; i < gWnEcoM.length(); ++i) {
		if ((best < 0) || (gWnEcoM[i] > gWnEcoM[best]))
			best = int(i);
	}
	if (best >= 0) {
		at = gWnEcoP[best];
		ecoM = gWnEcoM[best];
		return true;
	}
	at = Front::FoeAnchor();
	return OnMap(at);
}

float StrikeNnScore(const array<float>& in st, const array<float>& in f, array<float>& w)
{
	return Market::NnHeadScore(Market::NNS_ON, Market::NNS_STATE, NNS_STRIKE, Market::NNS_S, Market::NNS_O,
		Market::NNS_H, Market::NNS_XM, Market::NNS_XS, Market::NNS_W1, Market::NNS_B1, Market::NNS_W2, Market::NNS_B2,
		Market::NNS_WO, Market::NNS_BO, Market::NNS_TRUST, st, f, w);
}

void StrikeDecide()
{
	if (HuntHoldsFocus()) {
		++gStHuntOn;
		return;
	}
	if (gWnAt < 0)
		return;
	AIFloat3 tp;
	float ecoM = 0.f;
	if (!StrikeTarget(tp, ecoM)) {
		++gStNoTgt;
		return;
	}
	const float atkPow = aiMilitaryMgr.GetAttackPower();
	if (atkPow <= 0.f) {
		++gStNoArmy;
		return;
	}
	tp.y = ai.GetElevationAt(tp);
	if (!gStHeader) {
		gStHeader = true;
		AiLog("apex: nnstrike-schema v1 state=" + Market::NN_STATE + " strike=" + NNS_STRIKE + " opt=name,w,p opts=NO,STRIKE");
	}
	HuntArmyCensus(tp);
	AIFloat3 pushAt;
	float pushR = 0.f;
	array<float> st;
	Market::NnState(null, st);
	array<float> f;
	f.insertLast(gWnSeen);
	f.insertLast(gWnAwayF);
	f.insertLast(gWnHomeM);
	f.insertLast(gWnBigM);
	f.insertLast(gWnBigAwayF);
	f.insertLast(gWnBigFwd);
	f.insertLast(gWnBigOurD);
	f.insertLast(gWnKill90);
	f.insertLast(gWnLost90);
	f.insertLast(gWnKill90 - gWnLost90);
	f.insertLast(gWnArmyLost90);
	f.insertLast(gWnFoeDead90);
	f.insertLast(gWnDeadF);
	f.insertLast(gWnLnR);
	f.insertLast(gWnLnRB);
	f.insertLast(gWnTrend);
	f.insertLast(gWnPeak);
	f.insertLast(gWnTierNow);
	f.insertLast(gWnTierUpS);
	f.insertLast(ecoM);
	f.insertLast(aiMilitaryMgr.GetEnemyInflNear(tp, STRIKE_R + Market::PUSH_STAND));
	f.insertLast(ai.GetNetInflAt(tp));
	f.insertLast(Builder::gHomeSet ? tp.distance2D(Builder::gHomePos) : -1.f);
	f.insertLast(float(gWnEcoP.length()));
	f.insertLast(atkPow);
	f.insertLast(gHtAtkM);
	f.insertLast(gHtArmyM);
	f.insertLast(gHtAtkD);
	f.insertLast(Market::PushGoAt(pushAt, pushR) ? 1.f : 0.f);
	f.insertLast(float(HoldWhy()));
	f.insertLast(PushIncoming() ? 1.f : 0.f);
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> w(2, Market::NE2_EPS);
	w[ST_NO] = 1.f;
	const float trust = StrikeNnScore(st, f, w);
	array<float> p(2);
	const float flat = Market::NnHeadFlat(trust);
	const int c = Market::EcoDraw(ST_NO, trust, w, p, flat);
	array<string> names = {"NO", "STRIKE"};
	AiLog(Market::EcoLine("nnstrike", "NO", flat > 0.f, trust, st, f, names, w, p, c));
	++gStDecN;
	if (flat > 0.f)
		++gStExN;
	if (c == ST_STRIKE)
		StrikeStart(tp, ecoM);
}

void StrikeStart(const AIFloat3& in tp, float ecoM)
{
	gStOn = true;
	gStGo = false;
	gStPos = tp;
	gStFrom = ai.frame;
	gStUntil = ai.frame + STRIKE_S * SECOND;
	gStKill = 0.f;
	gStLost = 0.f;
	++gStHitN;
	AiLog(Factory::T() + "apex: strike start t=" + ai.teamId + " at=" + int(tp.x) + "," + int(tp.z)
		+ " ecoM=" + int(ecoM) + " atkPow=" + Market::NnF(aiMilitaryMgr.GetAttackPower(), 1)
		+ " away=" + Market::NnF(gWnAwayF, 2) + " net=" + int(gWnKill90 - gWnLost90) + " lnRB=" + Market::NnF(gWnLnRB, 2));
	StrikeFocus();
}

// Gather short of the cell, then go once what has gathered beats what stands there.
void StrikeFocus()
{
	AIFloat3 fp = gStPos;
	fp.y = ai.GetElevationAt(fp);
	const float foe = aiMilitaryMgr.GetEnemyInflNear(fp, STRIKE_R + Market::PUSH_STAND);
	float mine = aiMilitaryMgr.GetGatheredPower();
	if (!gStGo && (mine > 0.f) && (mine > foe)) {
		gStGo = true;
		++gStGoN;
		AiLog(Factory::T() + "apex: strike go t=" + ai.teamId + " at=" + int(fp.x) + "," + int(fp.z)
			+ " foe=" + Market::NnF(foe, 1) + " mine=" + Market::NnF(mine, 1)
			+ " s=" + ((ai.frame - gStFrom) / SECOND));
	}
	if (gStGo)
		mine = aiMilitaryMgr.GetAttackPowerNear(fp, STRIKE_NEAR);
	aiMilitaryMgr.SetFocus(fp, STRIKE_R, mine, gStGo, ai.frame + 10 * SECOND);
}

void StrikeEnd(const string why)
{
	gStOn = false;
	aiMilitaryMgr.SetFocus(AIFloat3(0.f, 0.f, 0.f), 0.f, 0.f, false, -1);
	if (why == "gone")
		++gStGoneN;
	else if (why == "army")
		++gStArmyN;
	else
		++gStTimeN;
	AiLog(Factory::T() + "apex: strike end t=" + ai.teamId + " why=" + why + " go=" + (gStGo ? 1 : 0)
		+ " s=" + ((ai.frame - gStFrom) / SECOND) + " kill=" + int(gStKill) + " lost=" + int(gStLost));
}

// A cell still standing holds the strike; once it is gone the nearest other cell
// of theirs is next -- a strike stays in their back lines, it does not roam home.
void StrikeLook()
{
	if (ai.frame >= gStUntil) {
		StrikeEnd("time");
		return;
	}
	if (aiMilitaryMgr.GetAttackPower() <= 0.f) {
		StrikeEnd("army");
		return;
	}
	int near = -1;
	float nd = 0.f;
	for (uint i = 0; i < gWnEcoP.length(); ++i) {
		const float d = gWnEcoP[i].distance2D(gStPos);
		if ((near < 0) || (d < nd)) {
			near = int(i);
			nd = d;
		}
	}
	if (near < 0) {
		StrikeEnd("gone");
		return;
	}
	gStPos = gWnEcoP[near];
	StrikeFocus();
}

void UpdateStrike()
{
	if (!Builder::gHomeSet)
		return;
	if (gWnNextAt < 0) {
		gWnNextAt = 30 * SECOND + (ai.teamId % 12) * SECOND;
		gStNextAt = 75 * SECOND + (ai.teamId % 15) * 2 * SECOND;
	}
	if (ai.frame >= gWnNextAt) {
		gWnNextAt = ai.frame + WN_EVERY;
		WindowCensus();
	}
	if (gStOn && (ai.frame >= gStLookAt)) {
		gStLookAt = ai.frame + STRIKE_LOOK;
		StrikeLook();
	}
	if (!gStOn && (ai.frame >= gStNextAt)) {
		gStNextAt = ai.frame + 30 * SECOND;
		StrikeDecide();
	}
	if (ai.frame >= gStLogAt) {
		gStLogAt = ai.frame + 60 * SECOND;
		if (gStDecN + gStNoTgt + gStNoArmy + gStHuntOn > 0)
			AiLog(Factory::T() + "apex: strike-stat t=" + ai.teamId + " dec=" + gStDecN + " ex=" + gStExN
				+ " strike=" + gStHitN + " go=" + gStGoN + " time=" + gStTimeN + " gone=" + gStGoneN
				+ " army=" + gStArmyN + " noTgt=" + gStNoTgt + " noArmy=" + gStNoArmy + " huntOn=" + gStHuntOn
				+ " on=" + (gStOn ? 1 : 0));
	}
}

}  // namespace Military
