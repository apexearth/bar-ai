namespace Market {

// STATIC DEFENCE AS TWO RECORDED DECISIONS (apexearth 2026-10-08: "If we don't
// have a NN governing defense count and placement - we need one. Enemies often
// find ways into the sensitive parts of our base."). AMOUNT: every 60 s a
// multiplier on DefenceTarget, rule D1. PLACEMENT: when a ground gun is about
// to be sited, the rule's site against the best slot of each kind the site
// generators already offer, plus a site on the recent leak path; rule = the
// rule's site. A LEAK is a building of ours an enemy ground unit killed.
const string NND_DEF = "defV,defT0,defFly,fill,leak5M,leakSens5M,leakIn5M,leakN5,raidM,foeArmy,"
	+ "armyHome,armyAway,awayFrac,postUncov,coverHome,threatHome,hazHome,push,wallFill,closure,"
	+ "assets,ecoPow,mult,minute";
const string NNU_SITE = "defM,reach,leak5M,leakSens5M,nCand,minute,"
	+ "ru_on,ru_prev,ru_stake,ru_leak,ru_cosFoe,ru_cover,ru_threat,ru_haz,ru_fwd,ru_rimD,ru_bp,ru_guns,ru_dRule,"
	+ "wa_on,wa_prev,wa_stake,wa_leak,wa_cosFoe,wa_cover,wa_threat,wa_haz,wa_fwd,wa_rimD,wa_bp,wa_guns,wa_dRule,"
	+ "mx_on,mx_prev,mx_stake,mx_leak,mx_cosFoe,mx_cover,mx_threat,mx_haz,mx_fwd,mx_rimD,mx_bp,mx_guns,mx_dRule,"
	+ "fr_on,fr_prev,fr_stake,fr_leak,fr_cosFoe,fr_cover,fr_threat,fr_haz,fr_fwd,fr_rimD,fr_bp,fr_guns,fr_dRule,"
	+ "fl_on,fl_prev,fl_stake,fl_leak,fl_cosFoe,fl_cover,fl_threat,fl_haz,fl_fwd,fl_rimD,fl_bp,fl_guns,fl_dRule,"
	+ "fo_on,fo_prev,fo_stake,fo_leak,fo_cosFoe,fo_cover,fo_threat,fo_haz,fo_fwd,fo_rimD,fo_bp,fo_guns,fo_dRule,"
	+ "lk_on,lk_prev,lk_stake,lk_leak,lk_cosFoe,lk_cover,lk_threat,lk_haz,lk_fwd,lk_rimD,lk_bp,lk_guns,lk_dRule";
const array<float> DA_MULT = {0.5f, 1.f, 2.f};
const int DA_RULE = 1;
const int DS_RULE = 0, DS_WALL = 1, DS_MEXG = 2, DS_FRONT = 3, DS_FLANK = 4, DS_FORT = 5, DS_LEAK = 6, DS_N = 7;
const int LEAK_WIN = 300 * SECOND;     // the recent leak window the features and sites read
const int DS_WATCH_S = 300;            // the placement label's horizon
const int DS_HOLD = 90 * SECOND;       // a site decision holds for re-elections of the same want

// The leak ring: our buildings killed by enemy ground units, newest last.
array<int> gLkF;
array<float> gLkX;
array<float> gLkZ;
array<float> gLkM;
array<bool> gLkSens;
array<bool> gLkIn;   // inside the hull or at its rim
int gLkN = 0, gLkSensN = 0, gLkLogAt = 0;
float gLkAllM = 0.f, gLkSensM = 0.f, gLkInM = 0.f, gLkRimM = 0.f, gLkOutM = 0.f;
float gLkFrontM = 0.f, gLkFlankM = 0.f, gLkRearM = 0.f, gLkLoneM = 0.f;

int gDaPick = 1;   // DA_RULE
int gDaNextAt = -1;
bool gDaHeader = false;
int gDaDecN = 0, gDaOvN = 0;

bool gDsHeader = false;
int gDsDecN = 0, gDsOvN = 0, gDsMemoN = 0, gDsLogAt = 0;
float gDsUs = 0.f;
array<int> gDsMemoDef;
array<AIFloat3> gDsMemoRule;
array<AIFloat3> gDsMemoAt;
array<int> gDsMemoUntil;
int gDsNanoAt = -999999;
AIFloat3 gDsNanoP(-1.f, 0.f, -1.f);

// Placement outcome watchers: every decision, either pick.
array<int> gBwF;
array<int> gBwOpt;
array<AIFloat3> gBwPos;
array<float> gBwR;
array<float> gBwM;
array<float> gBwKill;
array<float> gBwLost;
array<float> gBwPre;
array<float> gBwBase0;
array<int> gBwTag;   // 0 the site head, 1 the gun-class head (protect_nntype.as)

float DefAmountMult()
{
	return DA_MULT[gDaPick];
}

string LeakCls(int d)
{
	if (Catalog::gExtractsM[d] > 0.f)
		return "mex";
	if (IsPlantDef(d))
		return "lab";
	if (NanoDefLike(d))
		return "nano";
	if ((Catalog::gMaxRange[d] > 1.f) && ((Catalog::gSurfT[d] > 0.01f) || (Catalog::gAirT[d] > 0.01f)))
		return "gun";
	if ((Catalog::gMakeE[d] > 0.f) || (Catalog::gMakeM[d] > 0.f) || (Catalog::gConvCapacity[d] > 0.f)
		|| (Catalog::gStoreM[d] > 0.f) || (Catalog::gStoreE[d] > 0.f))
		return "eco";
	return "util";
}

float BearingCos(const AIFloat3& in p, const AIFloat3& in toward)
{
	const float vx = p.x - gPfMid.x, vz = p.z - gPfMid.z;
	const float ex = toward.x - gPfMid.x, ez = toward.z - gPfMid.z;
	const float nv = sqrt(vx * vx + vz * vz), ne = sqrt(ex * ex + ez * ez);
	if ((nv < 1.f) || (ne < 1.f))
		return 0.f;
	return (vx * ex + vz * ez) / (nv * ne);
}

void LeakPrune()
{
	int cut = 0;
	while ((cut < int(gLkF.length())) && (ai.frame - gLkF[cut] > 2 * LEAK_WIN))
		++cut;
	if (cut <= 0)
		return;
	gLkF.removeRange(0, cut);
	gLkX.removeRange(0, cut);
	gLkZ.removeRange(0, cut);
	gLkM.removeRange(0, cut);
	gLkSens.removeRange(0, cut);
	gLkIn.removeRange(0, cut);
}

// Leak metal within r of p since `from` (sens: eco, nanos, labs only).
float LeakNear(const AIFloat3& in p, float r, int from, int to, bool sensOnly)
{
	float m = 0.f;
	for (uint i = 0; i < gLkF.length(); ++i) {
		if ((gLkF[i] < from) || (gLkF[i] >= to) || (sensOnly && !gLkSens[i]))
			continue;
		const float dx = gLkX[i] - p.x, dz = gLkZ[i] - p.z;
		if (dx * dx + dz * dz <= r * r)
			m += gLkM[i];
	}
	return m;
}

void LeakSums(float& out all, float& out sens, float& out inner, int& out n)
{
	all = 0.f;
	sens = 0.f;
	inner = 0.f;
	n = 0;
	for (uint i = 0; i < gLkF.length(); ++i) {
		if (ai.frame - gLkF[i] > LEAK_WIN)
			continue;
		all += gLkM[i];
		++n;
		if (gLkSens[i])
			sens += gLkM[i];
		if (gLkIn[i])
			inner += gLkM[i];
	}
}

// A building of ours an enemy ground unit killed (main.as UnitDestroyedByInner).
void DefNoteLeak(const AIFloat3& in at, int d, CCircuitDef@ by)
{
	if (!OnMap(at) || !Catalog::ValidId(d))
		return;
	const string cls = LeakCls(d);
	const float m = Catalog::gCostM[d];
	const bool sens = (cls == "eco") || (cls == "nano") || (cls == "lab");
	const float depth = gPfRimOk ? -PfRimDist(at) : -99999.f;
	const string zone = !gPfRimOk ? "?" : ((depth >= 150.f) ? "in" : ((depth >= -250.f) ? "rim" : "out"));
	string dir = "?";
	AIFloat3 foeP;
	if (gPfRimOk && FoeRef(foeP)) {
		const float c = BearingCos(at, foeP);
		dir = (c > 0.5f) ? "front" : ((c > -0.5f) ? "flank" : "rear");
	}
	float gunD = 99999.f;
	int guns6 = 0;
	for (uint i = 0; i < gPfTwPos.length(); ++i) {
		const float gd = gPfTwPos[i].distance2D(at);
		if (gd < gunD)
			gunD = gd;
		if (gd <= 600.f)
			++guns6;
	}
	const bool inner = (zone == "in") || (zone == "rim");
	gLkF.insertLast(ai.frame);
	gLkX.insertLast(at.x);
	gLkZ.insertLast(at.z);
	gLkM.insertLast(m);
	gLkSens.insertLast(sens);
	gLkIn.insertLast(inner);
	LeakPrune();
	++gLkN;
	gLkAllM += m;
	if (zone == "in")
		gLkInM += m;
	else if (zone == "rim")
		gLkRimM += m;
	else
		gLkOutM += m;
	if (sens && inner) {
		++gLkSensN;
		gLkSensM += m;
		if (dir == "front")
			gLkFrontM += m;
		else if (dir == "flank")
			gLkFlankM += m;
		else if (dir == "rear")
			gLkRearM += m;
		if (guns6 <= 1)
			gLkLoneM += m;
	}
	DefSiteNoteLoss(at, m);
	KoNoteLeak(at, m);
	AiLog(Factory::T() + "apex: leak t=" + ai.teamId + " def=" + Catalog::Def(d).GetName() + " cls=" + cls
		+ " m=" + int(m) + " at=" + int(at.x) + "," + int(at.z) + " depth=" + int(depth) + " zone=" + zone
		+ " dir=" + dir + " nearestGunD=" + int(gunD) + " guns600=" + guns6
		+ " by=" + ((by !is null) ? by.GetName() : "?"));
}

// The nano mass: the standing nano with the most others within 400 of it.
AIFloat3 NanoMassAt()
{
	if (ai.frame - gDsNanoAt < 30 * SECOND)
		return gDsNanoP;
	gDsNanoAt = ai.frame;
	gDsNanoP = AIFloat3(-1.f, 0.f, -1.f);
	int best = 1;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		int k = 0;
		for (uint j = 0; j < gOwnNanoPos.length(); ++j) {
			if (gOwnNanoPos[i].distance2D(gOwnNanoPos[j]) <= 400.f)
				++k;
		}
		if (k > best) {
			best = k;
			gDsNanoP = gOwnNanoPos[i];
		}
	}
	return gDsNanoP;
}

float DsPrevAt(int d, const AIFloat3& in s, float dflt)
{
	if ((uint(d) >= gDsPrev.length()) || (gDsPrev[d] is null))
		return dflt;
	const array<float>@ pv = gDsPrev[d];
	const array<float>@ xs = gDsX[d];
	const array<float>@ zs = gDsZ[d];
	for (uint i = 0; i < pv.length(); ++i) {
		const float dx = xs[i] - s.x, dz = zs[i] - s.z;
		if (dx * dx + dz * dz <= 64.f * 64.f)
			return pv[i];
	}
	return dflt;
}

bool DsTaken(const array<AIFloat3>& in at, const array<bool>& in on, const AIFloat3& in s)
{
	for (uint k = 0; k < at.length(); ++k) {
		if (on[k] && (at[k].distance2D(s) < 200.f))
			return true;
	}
	return false;
}

// Every candidate site, one per kind, from the def's cached site list.
void DsCandidates(int d, const AIFloat3& in ruleAt, float reach, array<AIFloat3>& at, array<bool>& on,
	array<float>& prev)
{
	at.resize(DS_N);
	on.resize(DS_N);
	prev.resize(DS_N);
	for (int k = 0; k < DS_N; ++k) {
		at[k] = AIFloat3(-1.f, 0.f, -1.f);
		on[k] = false;
		prev[k] = 0.f;
	}
	at[DS_RULE] = ruleAt;
	on[DS_RULE] = true;
	prev[DS_RULE] = DsPrevAt(d, ruleAt, 0.f);
	const bool have = (uint(d) < gDsPrev.length()) && (gDsPrev[d] !is null);
	const float cost = Catalog::gCostM[d];
	// the leak-weighted bearing and the heaviest leak point of the window
	float lx = 0.f, lz = 0.f, lm = 0.f, heavy = 0.f;
	AIFloat3 heavyP(-1.f, 0.f, -1.f);
	for (uint i = 0; i < gLkF.length(); ++i) {
		if (ai.frame - gLkF[i] > LEAK_WIN)
			continue;
		lx += gLkX[i] * gLkM[i];
		lz += gLkZ[i] * gLkM[i];
		lm += gLkM[i];
		const AIFloat3 lp(gLkX[i], 0.f, gLkZ[i]);
		const float around = LeakNear(lp, 600.f, ai.frame - LEAK_WIN, ai.frame + 1, false);
		if (around > heavy) {
			heavy = around;
			heavyP = lp;
		}
	}
	const AIFloat3 leakC = (lm > 0.f) ? AIFloat3(lx / lm, 0.f, lz / lm) : AIFloat3(-1.f, 0.f, -1.f);
	const AIFloat3 nanoP = NanoMassAt();
	if (have) {
		const array<float>@ pv = gDsPrev[d];
		const array<float>@ xs = gDsX[d];
		const array<float>@ zs = gDsZ[d];
		const array<bool>@ fr = gDsFront[d];
		const array<bool>@ rg = gDsRing[d];
		const array<bool>@ wl = gDsWall[d];
		const array<int>@ kp = null;
		if (uint(d) < gDsKeep.length())
			@kp = gDsKeep[d];
		float bW = -1.f, bM = -1.f, bF = -1.f, bFl = -2.f, bFo = 1e9f;
		int iW = -1, iM = -1, iF = -1, iFl = -1, iFo = -1;
		for (uint i = 0; i < pv.length(); ++i) {
			if (pv[i] < 0.f)
				continue;
			const AIFloat3 s(xs[i], 0.f, zs[i]);
			if (wl[i]) {
				if (pv[i] > bW) { bW = pv[i]; iW = int(i); }
			} else if (fr[i]) {
				if (pv[i] > bF) { bF = pv[i]; iF = int(i); }
			} else if (!rg[i] && ((kp is null) || (i >= kp.length()) || (kp[i] < 0))) {
				if (pv[i] > bM) { bM = pv[i]; iM = int(i); }
			}
			if (gPfRimOk && (lm > 0.f)) {
				const float c = BearingCos(s, leakC);
				if (c > bFl) { bFl = c; iFl = int(i); }
			}
			if (OnMap(nanoP)) {
				const float nd = s.distance2D(nanoP);
				if ((nd < 1000.f) && (nd < bFo)) { bFo = nd; iFo = int(i); }
			}
		}
		const array<int> idx = {-1, iW, iM, iF, iFl, iFo};
		for (int k = DS_WALL; k <= DS_FORT; ++k) {
			if (idx[k] < 0)
				continue;
			at[k] = AIFloat3(xs[idx[k]], 0.f, zs[idx[k]]);
			prev[k] = pv[idx[k]];
		}
	}
	if (OnMap(heavyP)) {
		AIFloat3 lp = heavyP;
		if (gPfRimOk) {
			AIFloat3 dirL = heavyP - gPfMid;
			const float dl = sqrt(dirL.SqLength2D());
			if (dl > 1.f) {
				dirL.SafeNormalize2D();
				const float rimR = dl - PfRimDist(heavyP);
				lp = gPfMid + dirL * (rimR + 0.25f * reach);
			}
		}
		at[DS_LEAK] = lp;
		prev[DS_LEAK] = DsPrevAt(d, lp, 0.f);
	}
	for (int k = DS_WALL; k < DS_N; ++k) {
		const AIFloat3 s = at[k];
		if (!OnMap(s) || DsTaken(at, on, s) || InteriorGunSite(d, s) || TowerGraveNear(s, cost))
			continue;
		on[k] = true;
	}
}

void DsSiteFeatures(int d, const AIFloat3& in s, bool present, float pv, const AIFloat3& in ruleAt,
	float reach, array<float>& f)
{
	if (!present) {
		for (int k = 0; k < 13; ++k)
			f.insertLast(0.f);
		return;
	}
	AIFloat3 foeP;
	const bool foeOk = gPfRimOk && FoeRef(foeP);
	f.insertLast(1.f);
	f.insertLast(pv);
	f.insertLast(PfStakeAt(s, reach));
	f.insertLast(LeakNear(s, reach + 200.f, ai.frame - LEAK_WIN, ai.frame + 1, false));
	f.insertLast(foeOk ? BearingCos(s, foeP) : 0.f);
	f.insertLast(CoverAt(s));
	f.insertLast(ThreatM(s));
	f.insertLast(HazardAt(s));
	f.insertLast(Military::ForwardFraction(s));
	f.insertLast(PfRimDist(s));
	f.insertLast(RingBPAt(s));
	f.insertLast(PfTowerKillNear(s, reach));
	f.insertLast(s.distance2D(ruleAt));
}

// The site this ground gun goes to: the rule's unless the head draws another.
AIFloat3 DefSitePick(Want@ w, CCircuitUnit@ unit)
{
	if ((w.def is null) || (w.kind != WK_PROTECT) || !Builder::gHomeSet)
		return w.pos;
	const int d = int(w.def.id);
	if ((ProtClassOf(d) != PROT_DEF) || (Catalog::gSurfT[d] <= 0.01f) || !OnMap(w.pos))
		return w.pos;
	for (int i = int(gDsMemoDef.length()) - 1; i >= 0; --i) {
		if (ai.frame >= gDsMemoUntil[i]) {
			gDsMemoDef.removeAt(i);
			gDsMemoRule.removeAt(i);
			gDsMemoAt.removeAt(i);
			gDsMemoUntil.removeAt(i);
			continue;
		}
		if ((gDsMemoDef[i] == d) && (gDsMemoRule[i].distance2D(w.pos) < 300.f)) {
			++gDsMemoN;
			return (gDsMemoAt[i].distance2D(gDsMemoRule[i]) < 1.f) ? w.pos : gDsMemoAt[i];
		}
	}
	const double t0 = ai.ClockUs();
	const double tp = Perf::T0();
	const float reach = (Catalog::gMaxRange[d] > 1.f) ? Catalog::gMaxRange[d] : 500.f;
	array<AIFloat3> at;
	array<bool> on;
	array<float> prev;
	DsCandidates(d, w.pos, reach, at, on, prev);
	int nOn = 0;
	for (int k = 0; k < DS_N; ++k)
		nOn += on[k] ? 1 : 0;
	if (!gDsHeader) {
		gDsHeader = true;
		AiLog("apex: nndefsite-schema v1 state=" + NN_STATE + " defsite=" + NNU_SITE
			+ " opt=name,w,p opts=RULE,WALL,MEXG,FRONT,FLANK,FORT,LEAK");
	}
	float la = 0.f, ls = 0.f, li = 0.f;
	int ln = 0;
	LeakSums(la, ls, li, ln);
	array<float> st;
	NnState(unit, st);
	array<float> f;
	f.insertLast(Catalog::gCostM[d]);
	f.insertLast(reach);
	f.insertLast(la);
	f.insertLast(ls);
	f.insertLast(float(nOn));
	f.insertLast(float(ai.frame) / 1800.f);
	for (int k = 0; k < DS_N; ++k)
		DsSiteFeatures(d, at[k], on[k], prev[k], w.pos, reach, f);
	array<float> wt(DS_N, NE2_EPS);
	wt[DS_RULE] = 1.f;
	const float trust = NnHeadScore(NNU_ON, NNU_STATE, NNU_SITE, NNU_S, NNU_O, NNU_H, NNU_XM, NNU_XS,
		NNU_W1, NNU_B1, NNU_W2, NNU_B2, NNU_WO, NNU_BO, NNU_TRUST, st, f, wt);
	const float flat = NnHeadFlat(trust);
	float sum = 0.f;
	for (int k = 0; k < DS_N; ++k) {
		if (!on[k])
			wt[k] = 0.f;
		sum += wt[k];
	}
	array<float> p(DS_N, 0.f);
	for (int k = 0; k < DS_N; ++k) {
		if (!on[k])
			continue;
		if (flat > 0.f)
			p[k] = (1.f - flat) * wt[k] / sum + flat / float(nOn);
		else if (trust > 0.f)
			p[k] = wt[k] / sum;
		else
			p[k] = (k == DS_RULE) ? 1.f : 0.f;
	}
	int c = DS_RULE;
	if ((trust > 0.f) || (flat > 0.f)) {
		float r = float(AiRandom(0, 10000)) / 10000.f;
		for (int k = 0; k < DS_N; ++k) {
			if (!on[k])
				continue;
			c = k;
			r -= p[k];
			if (r <= 0.f)
				break;
		}
	}
	array<string> names = {"RULE", "WALL", "MEXG", "FRONT", "FLANK", "FORT", "LEAK"};
	AiLog(EcoLine("nndefsite", "RULE", flat > 0.f, trust, st, f, names, wt, p, c, "exec"));
	++gDsDecN;
	if (c != DS_RULE)
		++gDsOvN;
	const AIFloat3 site = at[c];
	KoNoteSited(site);
	gDsMemoDef.insertLast(d);
	gDsMemoRule.insertLast(w.pos);
	gDsMemoAt.insertLast(site);
	gDsMemoUntil.insertLast(ai.frame + DS_HOLD);
	gBwF.insertLast(ai.frame);
	gBwOpt.insertLast(c);
	gBwPos.insertLast(site);
	gBwR.insertLast(reach + 200.f);
	gBwM.insertLast(Catalog::gCostM[d]);
	gBwKill.insertLast(0.f);
	gBwLost.insertLast(0.f);
	gBwPre.insertLast(LeakNear(site, reach + 200.f, ai.frame - DS_WATCH_S * SECOND, ai.frame + 1, false));
	gBwBase0.insertLast(gLkAllM);
	gBwTag.insertLast(0);
	gDsUs += float(ai.ClockUs() - t0);
	Perf::Add("dec.defsite", tp);
	return site;
}

void DefSiteNoteLoss(const AIFloat3& in at, float m)
{
	for (uint i = 0; i < gBwF.length(); ++i) {
		if (gBwPos[i].distance2D(at) <= gBwR[i])
			gBwLost[i] += m;
	}
}

// An enemy ground unit died (main.as AiEnemyDestroyed).
void DefSiteNoteKill(const AIFloat3& in at, float m)
{
	if (gBwF.length() == 0)
		return;
	for (uint i = 0; i < gBwF.length(); ++i) {
		if (gBwPos[i].distance2D(at) <= gBwR[i])
			gBwKill[i] += m;
	}
}

void DefSiteWatch()
{
	for (int i = int(gBwF.length()) - 1; i >= 0; --i) {
		if (ai.frame < gBwF[i] + DS_WATCH_S * SECOND)
			continue;
		const float k = gBwKill[i], l = gBwLost[i];
		const float score = (k - l) / (k + l + gBwM[i] + 1.f);
		AiLog("apex: " + ((gBwTag[i] == 1) ? "nndeftype" : "nndefsite") + "-done t=" + ai.teamId + " f=" + gBwF[i] + " opt=" + gBwOpt[i]
			+ " done=" + NnF(score, 4) + " kill=" + int(k) + " lost=" + int(l) + " pre=" + int(gBwPre[i])
			+ " base=" + int(gLkAllM - gBwBase0[i]) + " m=" + int(gBwM[i])
			+ " at=" + int(gBwPos[i].x) + "," + int(gBwPos[i].z));
		gBwF.removeAt(i);
		gBwOpt.removeAt(i);
		gBwPos.removeAt(i);
		gBwR.removeAt(i);
		gBwM.removeAt(i);
		gBwKill.removeAt(i);
		gBwLost.removeAt(i);
		gBwPre.removeAt(i);
		gBwBase0.removeAt(i);
		gBwTag.removeAt(i);
	}
}

void DefAmountDecide()
{
	const float mult = DefAmountMult();
	const float defT0 = DefenceTarget() / mult;
	const float defV = DefenceValue();
	if (!gDaHeader) {
		gDaHeader = true;
		AiLog("apex: nndefamt-schema v1 state=" + NN_STATE + " defamt=" + NND_DEF + " opt=name,w,p opts=D05,D1,D2");
	}
	float la = 0.f, ls = 0.f, li = 0.f;
	int ln = 0;
	LeakSums(la, ls, li, ln);
	const AIFloat3 home = Builder::gHomePos;
	const float aw = Military::gArmyFieldM, ah = Military::gArmyHomeM;
	array<float> st;
	NnState(null, st);
	array<float> f;
	f.insertLast(defV);
	f.insertLast(defT0);
	f.insertLast(DefenceInFlightM());
	f.insertLast((defT0 > 1.f) ? defV / defT0 : 0.f);
	f.insertLast(la);
	f.insertLast(ls);
	f.insertLast(li);
	f.insertLast(float(ln));
	f.insertLast(FoeRaidMassM());
	f.insertLast(Military::EnemyArmyCost());
	f.insertLast(ah);
	f.insertLast(aw);
	f.insertLast((aw + ah > 1.f) ? aw / (aw + ah) : 0.f);
	f.insertLast((Military::gPostTotal > 1.f) ? Military::gPostUncovered / Military::gPostTotal : 0.f);
	f.insertLast(CoverAt(home));
	f.insertLast(ThreatM(home));
	f.insertLast(HazardAt(home));
	f.insertLast(Military::PushIncoming() ? 1.f : 0.f);
	f.insertLast(WallLineFill());
	f.insertLast(WallClosureFrac());
	f.insertLast(gAssetsM);
	f.insertLast(EcoPowerM());
	f.insertLast(mult);
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> wt(3, NE2_EPS);
	wt[DA_RULE] = 1.f;
	const float trust = NnHeadScore(NND_ON, NND_STATE, NND_DEF, NND_S, NND_O, NND_H, NND_XM, NND_XS,
		NND_W1, NND_B1, NND_W2, NND_B2, NND_WO, NND_BO, NND_TRUST, st, f, wt);
	array<float> p(3);
	const float flat = NnHeadFlat(trust);
	const int c = EcoDraw(DA_RULE, trust, wt, p, flat);
	array<string> names = {"D05", "D1", "D2"};
	AiLog(EcoLine("nndefamt", "D1", flat > 0.f, trust, st, f, names, wt, p, c));
	++gDaDecN;
	if (c != DA_RULE)
		++gDaOvN;
	gDaPick = c;
}

void UpdateDefNet()
{
	if (!Builder::gHomeSet)
		return;
	if (gDaNextAt < 0)
		gDaNextAt = 90 * SECOND + (ai.teamId % 15) * 2 * SECOND;
	if (ai.frame >= gDaNextAt) {
		gDaNextAt = ai.frame + 60 * SECOND;
		DefAmountDecide();
	}
	DefTypeTick();
	DefSiteWatch();
	if (ai.frame >= gLkLogAt) {
		gLkLogAt = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: leak-stat t=" + ai.teamId + " n=" + gLkN + " m=" + int(gLkAllM)
			+ " in=" + int(gLkInM) + " rim=" + int(gLkRimM) + " out=" + int(gLkOutM)
			+ " sensN=" + gLkSensN + " sens=" + int(gLkSensM) + " front=" + int(gLkFrontM)
			+ " flank=" + int(gLkFlankM) + " rear=" + int(gLkRearM) + " lone=" + int(gLkLoneM)
			+ " amt=" + names3(gDaPick) + " amtDec=" + gDaDecN + " amtOv=" + gDaOvN
			+ " siteDec=" + gDsDecN + " siteOv=" + gDsOvN + " memo=" + gDsMemoN
			+ " siteUs=" + int((gDsDecN > 0) ? gDsUs / float(gDsDecN) : 0.f) + " watch=" + gBwF.length() + DefTypeStat());
	}
}

string names3(int c)
{
	return (c == 0) ? "D05" : ((c == 2) ? "D2" : "D1");
}

}  // namespace Market
