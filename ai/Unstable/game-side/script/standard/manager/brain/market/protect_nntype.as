namespace Market {

// WHICH GUN, as a recorded draw (apexearth 2026-10-08: "we suck super hard at
// making T2 defenses"). When a ground gun is about to be built: the rule's gun
// against the best of each class this hand can build that the defence auction
// priced in the same proposal -- T1 quickest to stand, T1 most kill, T2+
// quickest, most kill, longest reach. Rule = the rule's gun.
const string NNN_TYPE = "ruleM,ruleTier,nOn,nPriced,foeGndM,foeT2M,foeT2Eta,foeT2D,closeT2,closeAll,"
	+ "gunT1M,gunT2M,handBP,ringBP,leak5M,minute,"
	+ "ru_on,ru_m,ru_mEq,ru_tier,ru_reach,ru_kill,ru_dps,ru_aoe,ru_hp,ru_standS,ru_valK,ru_threat,ru_hazK,ru_cover,ru_fwd,ru_rimD,ru_befM,ru_befT2M,ru_etaS,ru_own,ru_dRule,"
	+ "q1_on,q1_m,q1_mEq,q1_tier,q1_reach,q1_kill,q1_dps,q1_aoe,q1_hp,q1_standS,q1_valK,q1_threat,q1_hazK,q1_cover,q1_fwd,q1_rimD,q1_befM,q1_befT2M,q1_etaS,q1_own,q1_dRule,"
	+ "k1_on,k1_m,k1_mEq,k1_tier,k1_reach,k1_kill,k1_dps,k1_aoe,k1_hp,k1_standS,k1_valK,k1_threat,k1_hazK,k1_cover,k1_fwd,k1_rimD,k1_befM,k1_befT2M,k1_etaS,k1_own,k1_dRule,"
	+ "q2_on,q2_m,q2_mEq,q2_tier,q2_reach,q2_kill,q2_dps,q2_aoe,q2_hp,q2_standS,q2_valK,q2_threat,q2_hazK,q2_cover,q2_fwd,q2_rimD,q2_befM,q2_befT2M,q2_etaS,q2_own,q2_dRule,"
	+ "k2_on,k2_m,k2_mEq,k2_tier,k2_reach,k2_kill,k2_dps,k2_aoe,k2_hp,k2_standS,k2_valK,k2_threat,k2_hazK,k2_cover,k2_fwd,k2_rimD,k2_befM,k2_befT2M,k2_etaS,k2_own,k2_dRule,"
	+ "r2_on,r2_m,r2_mEq,r2_tier,r2_reach,r2_kill,r2_dps,r2_aoe,r2_hp,r2_standS,r2_valK,r2_threat,r2_hazK,r2_cover,r2_fwd,r2_rimD,r2_befM,r2_befT2M,r2_etaS,r2_own,r2_dRule";
const int DT_RULE = 0, DT_T1Q = 1, DT_T1K = 2, DT_T2Q = 3, DT_T2K = 4, DT_T2R = 5, DT_N = 6;
const int DT_SLOT_F = 21;

// What the last ground-defence proposal of each asker def priced that the
// asker can build: def, value, the site it was priced at.
array<array<int>@> gDtSnD;
array<array<float>@> gDtSnV;
array<array<AIFloat3>@> gDtSnAt;

// Seen armed enemy ground units, at their group's position.
array<AIFloat3> gDtFoeP;
array<float> gDtFoeSpd;
array<float> gDtFoeRng;
array<float> gDtFoeM;
array<bool> gDtFoeT2;
int gDtFoeAt = -1;

int gDtTickAt = 0, gDtPrevAt = -1;
float gDtT2D = -1.f, gDtAllD = -1.f, gDtCloseT2 = 0.f, gDtCloseAll = 0.f;

bool gDtHeader = false;
int gDtDecN = 0, gDtOvN = 0, gDtMissN = 0, gDtMemoN = 0, gDtT2N = 0, gDtRuleT2N = 0;
float gDtUs = 0.f;
int gDtArmF = -1, gDtArmIdx = -1;
array<int> gDtMemoRule;
array<AIFloat3> gDtMemoRuleAt;
array<int> gDtMemoDef;
array<AIFloat3> gDtMemoAt;
array<int> gDtMemoUntil;

void DtReset(int uid)
{
	if (uid < 0)
		return;
	if (int(gDtSnD.length()) <= uid) {
		gDtSnD.resize(uid + 1);
		gDtSnV.resize(uid + 1);
		gDtSnAt.resize(uid + 1);
	}
	if (gDtSnD[uid] is null) {
		array<int> a;
		array<float> b;
		array<AIFloat3> c;
		@gDtSnD[uid] = a;
		@gDtSnV[uid] = b;
		@gDtSnAt[uid] = c;
		return;
	}
	gDtSnD[uid].resize(0);
	gDtSnV[uid].resize(0);
	gDtSnAt[uid].resize(0);
}

void DtNote(int uid, int d, float v, const AIFloat3& in at)
{
	if ((uid < 0) || (uid >= int(gDtSnD.length())) || (gDtSnD[uid] is null))
		return;
	gDtSnD[uid].insertLast(d);
	gDtSnV[uid].insertLast(v);
	gDtSnAt[uid].insertLast(at);
}

void DtFoeSweep()
{
	if (gDtFoeAt == ai.frame)
		return;
	gDtFoeAt = ai.frame;
	gDtFoeP.resize(0);
	gDtFoeSpd.resize(0);
	gDtFoeRng.resize(0);
	gDtFoeM.resize(0);
	gDtFoeT2.resize(0);
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
		if (!OnMap(gp))
			continue;
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nU; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d]
				|| (Catalog::gPower[d] <= 1.f) || (Catalog::gSpeed[d] <= 1.f))
				continue;
			gDtFoeP.insertLast(gp);
			gDtFoeSpd.insertLast(Catalog::gSpeed[d]);
			gDtFoeRng.insertLast(Catalog::gMaxRange[d]);
			gDtFoeM.insertLast(Catalog::gCostM[d]);
			gDtFoeT2.insertLast(DefTier(d) >= 2);
		}
	}
}

// Every 10 s: how fast their ground metal, and their T2+ metal, closes on home.
void DefTypeTick()
{
	if (ai.frame < gDtTickAt)
		return;
	gDtTickAt = ai.frame + 10 * SECOND;
	DtFoeSweep();
	const AIFloat3 home = Builder::gHomePos;
	float m2 = 0.f, d2 = 0.f, ma = 0.f, da = 0.f;
	for (uint i = 0; i < gDtFoeP.length(); ++i) {
		const float dd = gDtFoeP[i].distance2D(home);
		ma += gDtFoeM[i];
		da += gDtFoeM[i] * dd;
		if (gDtFoeT2[i]) {
			m2 += gDtFoeM[i];
			d2 += gDtFoeM[i] * dd;
		}
	}
	const float nT2 = (m2 > 0.f) ? d2 / m2 : -1.f;
	const float nAll = (ma > 0.f) ? da / ma : -1.f;
	if (gDtPrevAt >= 0) {
		const float dt = float(ai.frame - gDtPrevAt) / float(SECOND);
		gDtCloseT2 = ((gDtT2D >= 0.f) && (nT2 >= 0.f) && (dt > 0.f)) ? (gDtT2D - nT2) / dt : 0.f;
		gDtCloseAll = ((gDtAllD >= 0.f) && (nAll >= 0.f) && (dt > 0.f)) ? (gDtAllD - nAll) / dt : 0.f;
	}
	gDtPrevAt = ai.frame;
	gDtT2D = nT2;
	gDtAllD = nAll;
}

void DtSlotFeatures(int d, const AIFloat3& in s, bool present, float v, float standS, const AIFloat3& in ruleAt,
	array<float>& f)
{
	if (!present) {
		for (int k = 0; k < DT_SLOT_F; ++k)
			f.insertLast(0.f);
		return;
	}
	float bef = 0.f, bef2 = 0.f, eta = -1.f;
	for (uint i = 0; i < gDtFoeP.length(); ++i) {
		float g = gDtFoeP[i].distance2D(s) - gDtFoeRng[i];
		if (g < 0.f)
			g = 0.f;
		const float e = g / gDtFoeSpd[i];
		if ((eta < 0.f) || (e < eta))
			eta = e;
		if (e <= standS) {
			bef += gDtFoeM[i];
			if (gDtFoeT2[i])
				bef2 += gDtFoeM[i];
		}
	}
	f.insertLast(1.f);
	f.insertLast(Catalog::gCostM[d]);
	f.insertLast(TowerCostEq(d));
	f.insertLast(float(DefTier(d)));
	f.insertLast(Catalog::gMaxRange[d]);
	f.insertLast(PfTowerKill(d));
	f.insertLast(Catalog::gDps[d]);
	f.insertLast(Catalog::gAoe[d]);
	f.insertLast(Catalog::gHealth[d]);
	f.insertLast(standS);
	f.insertLast(v * 1000.f);
	f.insertLast(ThreatM(s));
	f.insertLast(HazardAt(s) * 1000.f);
	f.insertLast(CoverAt(s));
	f.insertLast(Military::ForwardFraction(s));
	f.insertLast(PfRimDist(s));
	f.insertLast(bef);
	f.insertLast(bef2);
	f.insertLast(eta);
	f.insertLast((uint(d) < gOwnCount.length()) ? float(gOwnCount[d]) : 0.f);
	f.insertLast(s.distance2D(ruleAt));
}

// The gun this want builds: the rule's unless the head draws another class.
Want@ DefTypePick(Want@ w, CCircuitUnit@ unit)
{
	if ((w.def is null) || (w.kind != WK_PROTECT) || !Builder::gHomeSet || !OnMap(w.pos))
		return w;
	const int d0 = int(w.def.id);
	if ((ProtClassOf(d0) != PROT_DEF) || (Catalog::gSurfT[d0] <= 0.01f))
		return w;
	for (int i = int(gDtMemoRule.length()) - 1; i >= 0; --i) {
		if (ai.frame >= gDtMemoUntil[i]) {
			gDtMemoRule.removeAt(i);
			gDtMemoRuleAt.removeAt(i);
			gDtMemoDef.removeAt(i);
			gDtMemoAt.removeAt(i);
			gDtMemoUntil.removeAt(i);
			continue;
		}
		if ((gDtMemoRule[i] == d0) && (gDtMemoRuleAt[i].distance2D(w.pos) < 300.f)) {
			++gDtMemoN;
			if ((gDtMemoDef[i] == d0) || !unit.circuitDef.CanBuild(Catalog::Def(gDtMemoDef[i])))
				return w;
			Want@ mw = WantCopy(w);
			@mw.def = Catalog::Def(gDtMemoDef[i]);
			mw.pos = gDtMemoAt[i];
			return mw;
		}
	}
	const int uid = int(unit.circuitDef.id);
	if ((uid >= int(gDtSnD.length())) || (gDtSnD[uid] is null)) {
		++gDtMissN;
		return w;
	}
	const array<int>@ sd = gDtSnD[uid];
	const array<float>@ sv = gDtSnV[uid];
	const array<AIFloat3>@ sa = gDtSnAt[uid];
	int ri = -1;
	for (uint i = 0; (i < sd.length()) && (ri < 0); ++i) {
		if ((sd[i] == d0) && (sa[i].distance2D(w.pos) < 1.f))
			ri = int(i);
	}
	if (ri < 0) {
		++gDtMissN;
		return w;
	}
	const double t0 = ai.ClockUs();
	const double tp = Perf::T0();
	DtFoeSweep();
	const float handBP = EffBP(Catalog::gBuildPower[uid]);
	array<float> stand(sd.length(), 0.f);
	array<int> pick(DT_N, -1);
	pick[DT_RULE] = ri;
	float bQ1 = 1e9f, bK1 = -1.f, bQ2 = 1e9f, bK2 = -1.f, bR2 = -1.f;
	for (uint i = 0; i < sd.length(); ++i) {
		const int d = sd[i];
		if (Catalog::gSurfT[d] <= 0.01f)
			continue;
		stand[i] = Catalog::BuildSecondsAt(d, handBP + RingBPAt(sa[i]));
		const float kill = PfTowerKill(d);
		if (T1Tower(d)) {
			if (stand[i] < bQ1) { bQ1 = stand[i]; pick[DT_T1Q] = int(i); }
			if (kill > bK1) { bK1 = kill; pick[DT_T1K] = int(i); }
		} else {
			if (stand[i] < bQ2) { bQ2 = stand[i]; pick[DT_T2Q] = int(i); }
			if (kill > bK2) { bK2 = kill; pick[DT_T2K] = int(i); }
			if (Catalog::gMaxRange[d] > bR2) { bR2 = Catalog::gMaxRange[d]; pick[DT_T2R] = int(i); }
		}
	}
	array<bool> on(DT_N, false);
	on[DT_RULE] = true;
	int nOn = 1;
	for (int k = DT_T1Q; k < DT_N; ++k) {
		if (pick[k] < 0)
			continue;
		bool dup = false;
		for (int j = 0; (j < k) && !dup; ++j)
			dup = on[j] && (sd[pick[j]] == sd[pick[k]]);
		if (dup)
			continue;
		on[k] = true;
		++nOn;
	}
	if (!gDtHeader) {
		gDtHeader = true;
		AiLog("apex: nndeftype-schema v1 state=" + NN_STATE + " deftype=" + NNN_TYPE
			+ " opt=name,w,p opts=RULE,T1Q,T1K,T2Q,T2K,T2R");
	}
	float la = 0.f, ls = 0.f, li = 0.f;
	int ln = 0;
	LeakSums(la, ls, li, ln);
	float gunT1 = 0.f, gunT2 = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const int gd = gProtDefId[PROT_DEF][i];
		if (T1Tower(gd))
			gunT1 += Catalog::gCostM[gd];
		else
			gunT2 += Catalog::gCostM[gd];
	}
	const AIFloat3 home = Builder::gHomePos;
	float foeAll = 0.f, foeT2 = 0.f, t2Eta = -1.f;
	for (uint i = 0; i < gDtFoeP.length(); ++i) {
		foeAll += gDtFoeM[i];
		if (!gDtFoeT2[i])
			continue;
		foeT2 += gDtFoeM[i];
		float g = gDtFoeP[i].distance2D(home) - gDtFoeRng[i];
		if (g < 0.f)
			g = 0.f;
		const float e = g / gDtFoeSpd[i];
		if ((t2Eta < 0.f) || (e < t2Eta))
			t2Eta = e;
	}
	array<float> st;
	NnState(unit, st);
	array<float> f;
	f.insertLast(Catalog::gCostM[d0]);
	f.insertLast(float(DefTier(d0)));
	f.insertLast(float(nOn));
	f.insertLast(float(sd.length()));
	f.insertLast(foeAll);
	f.insertLast(foeT2);
	f.insertLast(t2Eta);
	f.insertLast(gDtT2D);
	f.insertLast(gDtCloseT2);
	f.insertLast(gDtCloseAll);
	f.insertLast(gunT1);
	f.insertLast(gunT2);
	f.insertLast(handBP);
	f.insertLast(RingBPAt(w.pos));
	f.insertLast(la);
	f.insertLast(float(ai.frame) / 1800.f);
	for (int k = 0; k < DT_N; ++k) {
		const int i = pick[k];
		if (on[k])
			DtSlotFeatures(sd[i], sa[i], true, sv[i], stand[i], w.pos, f);
		else
			DtSlotFeatures(d0, w.pos, false, 0.f, 0.f, w.pos, f);
	}
	array<float> wt(DT_N, NE2_EPS);
	wt[DT_RULE] = 1.f;
	const float trust = NnHeadScore(NNN_ON, NNN_STATE, NNN_TYPE, NNN_S, NNN_O, NNN_H, NNN_XM, NNN_XS,
		NNN_W1, NNN_B1, NNN_W2, NNN_B2, NNN_WO, NNN_BO, NNN_TRUST, st, f, wt);
	const float flat = NnHeadFlat(trust);
	float sum = 0.f;
	for (int k = 0; k < DT_N; ++k) {
		if (!on[k])
			wt[k] = 0.f;
		sum += wt[k];
	}
	array<float> p(DT_N, 0.f);
	for (int k = 0; k < DT_N; ++k) {
		if (!on[k])
			continue;
		if (flat > 0.f)
			p[k] = (1.f - flat) * wt[k] / sum + flat / float(nOn);
		else if (trust > 0.f)
			p[k] = wt[k] / sum;
		else
			p[k] = (k == DT_RULE) ? 1.f : 0.f;
	}
	int c = DT_RULE;
	if ((trust > 0.f) || (flat > 0.f)) {
		float r = float(AiRandom(0, 10000)) / 10000.f;
		for (int k = 0; k < DT_N; ++k) {
			if (!on[k])
				continue;
			c = k;
			r -= p[k];
			if (r <= 0.f)
				break;
		}
	}
	array<string> names = {"RULE", "T1Q", "T1K", "T2Q", "T2K", "T2R"};
	AiLog(EcoLine("nndeftype", "RULE", flat > 0.f, trust, st, f, names, wt, p, c, "exec"));
	const int dc = sd[pick[c]];
	const AIFloat3 at = sa[pick[c]];
	++gDtDecN;
	if (dc != d0)
		++gDtOvN;
	if (!T1Tower(dc))
		++gDtT2N;
	if (!T1Tower(d0))
		++gDtRuleT2N;
	gDtMemoRule.insertLast(d0);
	gDtMemoRuleAt.insertLast(w.pos);
	gDtMemoDef.insertLast(dc);
	gDtMemoAt.insertLast(at);
	gDtMemoUntil.insertLast(ai.frame + DS_HOLD);
	const float reach = (Catalog::gMaxRange[dc] > 1.f) ? Catalog::gMaxRange[dc] : 500.f;
	gBwF.insertLast(ai.frame);
	gBwOpt.insertLast(c);
	gBwPos.insertLast(at);
	gBwR.insertLast(reach + 200.f);
	gBwM.insertLast(Catalog::gCostM[dc]);
	gBwKill.insertLast(0.f);
	gBwLost.insertLast(0.f);
	gBwPre.insertLast(LeakNear(at, reach + 200.f, ai.frame - DS_WATCH_S * SECOND, ai.frame + 1, false));
	gBwBase0.insertLast(gLkAllM);
	gBwTag.insertLast(1);
	gDtArmF = ai.frame;
	gDtArmIdx = int(gBwF.length()) - 1;
	gDtUs += float(ai.ClockUs() - t0);
	Perf::Add("dec.deftype", tp);
	if (dc == d0)
		return w;
	Want@ cw = WantCopy(w);
	@cw.def = Catalog::Def(dc);
	cw.pos = at;
	cw.value = sv[pick[c]];
	return cw;
}

// The site the gun was finally sent to: the type label is watched there.
AIFloat3 DefTypeSited(const AIFloat3& in s)
{
	if ((gDtArmF == ai.frame) && (gDtArmIdx >= 0) && (gDtArmIdx < int(gBwF.length()))
		&& (gBwTag[gDtArmIdx] == 1) && (gBwF[gDtArmIdx] == ai.frame))
		gBwPos[gDtArmIdx] = s;
	gDtArmF = -1;
	return s;
}

string DefTypeStat()
{
	return " typeDec=" + gDtDecN + " typeOv=" + gDtOvN + " typeT2=" + gDtT2N + " typeRuleT2=" + gDtRuleT2N
		+ " typeMiss=" + gDtMissN + " typeMemo=" + gDtMemoN
		+ " typeUs=" + int((gDtDecN > 0) ? gDtUs / float(gDtDecN) : 0.f);
}

}  // namespace Market
