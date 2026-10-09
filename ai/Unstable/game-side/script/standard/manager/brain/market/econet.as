namespace Market {

// TWO ECONOMY NETS (his 2026-10-06: "let the network discover which is better" --
// constructors vs army, and how hard we go out for extractors). Same head shape
// as escnet/nnraid: a team decision on a 30 s clock, today's rule as the prior,
// discovery draws the others.
//
// nncon -- the constructor floor's size: C05/C1/C2/C3 multiply ConsNeedAny's
//          target. C1 is the rule (yields while the army is behind its share),
//          C05 yields too, C2/C3 hold even while the army is behind.
// nnmex -- expansion: HOLD lets the forced defence picks fire over an open mex (the rule),
//          YIELD puts an open mex first, PUSH also doubles the
//          value of every mex want before the draw.
const string NNK_CON = "cons,consNeed,armyShare,armyTarget,armyGap,mexes,openSpots,foeRaid,minute";
const string NNX_MEX = "mexes,openSpots,mexLost,mexKilledRate,defWants,armyShare,foeRaid,bankM,minute";
const int NK_C1 = 1, NK_N = 4;
const array<float> NK_MUL = {0.5f, 1.f, 2.f, 3.f};
const int NX_HOLD = 0, NX_YIELD = 1, NX_PUSH = 2;
const float NE2_EPS = 0.01f;
float gConFloorMul = 1.f;
// The constructor caps: ground pools x1/x2/x4 of the base (rule x1), the air
// pool x2/x4/x8 (rule x4: air cons take no build space).
const string NNQ_CAP = "conT1,conT2,conAir,capT1,capT2,capAir,conShare,mInc,mWasting,bankFill,idleCons,minute";
float gConCapMul = 1.f;
float gAirCapMul = 4.f;
// The late ground scout cap: x1/x2/x4 of the same base (rule x1).
const string NNS_SCOUT = "scouts,scoutCap,topTier,army,foeLos,foeRadar,screenLost,mInc,minute";
float gScoutCapMul = 1.f;
int gMexPolicy = NX_HOLD;
float gMexMul = 1.f;
int gEcoNetNextAt = 0;
bool gEcoNetHeader = false;

int IdleConCount()
{
	int n = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ w = gWorkers[i];
		if ((w !is null) && ((w.task is null) || (w.task.GetType() == Task::Type::IDLE)))
			++n;
	}
	return n;
}

string NxName(int o) { return (o == NX_HOLD) ? "HOLD" : ((o == NX_PUSH) ? "PUSH" : "YIELD"); }

int EcoDraw(int rule, float trust, array<float>& w, array<float>& p, float flat)
{
	const int n = int(w.length());
	float sum = 0.f;
	for (int o = 0; o < n; ++o)
		sum += w[o];
	for (int o = 0; o < n; ++o) {
		if (flat > 0.f)
			p[o] = (1.f - flat) * w[o] / sum + flat / float(n);
		else if (trust > 0.f)
			p[o] = w[o] / sum;
		else
			p[o] = (o == rule) ? 1.f : 0.f;
	}
	if ((trust <= 0.f) && (flat <= 0.f))
		return rule;
	float r = float(AiRandom(0, 10000)) / 10000.f;
	for (int o = 0; o < n; ++o) {
		r -= p[o];
		if (r <= 0.f)
			return o;
	}
	return rule;
}

// EcoDraw for a balance head: a held option runs with p = 1/K, the odds it was drawn at.
int EcoDrawBal(const string& in tag, int rule, float trust, array<float>& w, array<float>& p, float flat)
{
	const int n = int(w.length());
	const int held = NnBalanceHeld(tag, n);
	if (held < 0)
		return EcoDraw(rule, trust, w, p, flat);
	for (int o = 0; o < n; ++o)
		p[o] = 1.f / float(n);
	return held;
}

// game=1 on a balance head's row: the option was held all game (NnBalanceHeld).
string NnGameField(const string& in tag)
{
	return (gNnBalTag.find(tag) >= 0) ? (" game=" + (NnBalanceIsHeld(tag) ? 1 : 0)) : "";
}

string EcoLine(const string tag, const string rule, bool explore, float trust, const array<float>& in st,
	const array<float>& in f, const array<string>& in names, const array<float>& in w, const array<float>& in p, int chosen,
	const string why = "clock")
{
	string ln = "apex: " + tag + " t=" + ai.teamId + " f=" + ai.frame + " why=" + why + " rule=" + rule
		+ " ex=" + (explore ? 1 : 0) + NnGameField(tag) + " trust=" + NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < f.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(f[k], 3);
	for (uint o = 0; o < names.length(); ++o)
		ln += ((o == 0) ? " | " : " ; ") + names[o] + "," + NnF(w[o], 4) + "," + NnF(p[o], 6);
	return ln + " | chosen=" + chosen;
}

void EcoNetDecide()
{
	if (ai.frame < gEcoNetNextAt)
		return;
	gEcoNetNextAt = ai.frame + 30 * SECOND;
	array<float> st;
	NnState(null, st);
	const float aShare = (Brain::gSpentTotal > 1.f) ? Brain::ShareOf(Brain::ARMY) : 0.f;
	const float aTgt = Brain::TargetShare(Brain::ARMY);
	if (!gEcoNetHeader) {
		gEcoNetHeader = true;
		AiLog("apex: nncon-schema v2 state=" + NN_STATE + " con=" + NNK_CON + " opt=name,w,p opts=C05,C1,C2,C3");
		AiLog("apex: nnmex-schema v1 state=" + NN_STATE + " mex=" + NNX_MEX + " opt=name,w,p opts=HOLD,YIELD,PUSH");
		AiLog("apex: nncap-schema v1 state=" + NN_STATE + " cap=" + NNQ_CAP + " opt=name,w,p opts=X1,X2,X4");
		AiLog("apex: nnacap-schema v1 state=" + NN_STATE + " acap=" + NNQ_CAP + " opt=name,w,p opts=A2,A4,A8");
		AiLog("apex: nnscap-schema v1 state=" + NN_STATE + " scap=" + NNS_SCOUT + " opt=name,w,p opts=S1,S15,S2");
	}
	{
		array<float> f;
		f.insertLast(float(ConFleetHave()));
		f.insertLast(float(ConsNeedAt(false, 1.f)));
		f.insertLast(aShare);
		f.insertLast(aTgt);
		f.insertLast(ArmyTarget() - ArmyValue());
		f.insertLast(float(OwnMexCount()));
		f.insertLast(float(ClaimableSpots()));
		f.insertLast(FoeRaidMassM());
		f.insertLast(float(ai.frame) / 1800.f);
		array<float> w(NK_N, NE2_EPS);
		w[NK_C1] = 1.f;
		const float trust = NnHeadScore(NNK_ON, NNK_STATE, NNK_CON, NNK_S, NNK_O, NNK_H, NNK_XM, NNK_XS,
			NNK_W1, NNK_B1, NNK_W2, NNK_B2, NNK_WO, NNK_BO, NNK_TRUST, st, f, w);
		array<float> p(NK_N);
		const float flat = NnHeadFlat();
		const int c = EcoDrawBal("nncon", NK_C1, trust, w, p, flat);
		gConFloorMul = NK_MUL[c];
		array<string> names = {"C05", "C1", "C2", "C3"};
		AiLog(EcoLine("nncon", "C1", flat > 0.f, trust, st, f, names, w, p, c));
	}
	{
		array<float> qf;
		qf.insertLast(float(ConPoolHave(0)));
		qf.insertLast(float(ConPoolHave(1)));
		qf.insertLast(float(ConPoolHave(2)));
		qf.insertLast(float(ConPoolCap(0)));
		qf.insertLast(float(ConPoolCap(1)));
		qf.insertLast(float(ConPoolCap(2)));
		qf.insertLast(ConShare());
		qf.insertLast(Eco::MInc());
		qf.insertLast(NnB(MetalWasting()));
		qf.insertLast((Eco::MStor() > 1.f) ? (Eco::MCur() / Eco::MStor()) : 0.f);
		qf.insertLast(float(IdleConCount()));
		qf.insertLast(float(ai.frame) / 1800.f);
		array<float> qw(3, NE2_EPS);
		qw[0] = 1.f;
		const float qtrust = NnHeadScore(NNQ_ON, NNQ_STATE, NNQ_CAP, NNQ_S, NNQ_O, NNQ_H, NNQ_XM, NNQ_XS,
			NNQ_W1, NNQ_B1, NNQ_W2, NNQ_B2, NNQ_WO, NNQ_BO, NNQ_TRUST, st, qf, qw);
		array<float> qp(3);
		const float qflat = NnHeadFlat();
		const int c = EcoDrawBal("nncap", 0, qtrust, qw, qp, qflat);
		gConCapMul = (c == 1) ? 2.f : ((c == 2) ? 4.f : 1.f);
		array<string> qnames = {"X1", "X2", "X4"};
		AiLog(EcoLine("nncap", "X1", qflat > 0.f, qtrust, st, qf, qnames, qw, qp, c));
		array<float> w2(3, NE2_EPS);
		w2[1] = 1.f;
		const float trust2 = NnHeadScore(NNZ_ON, NNZ_STATE, NNQ_CAP, NNZ_S, NNZ_O, NNZ_H, NNZ_XM, NNZ_XS,
			NNZ_W1, NNZ_B1, NNZ_W2, NNZ_B2, NNZ_WO, NNZ_BO, NNZ_TRUST, st, qf, w2);
		array<float> p2(3);
		const float flat2 = NnHeadFlat();
		const int c2 = EcoDrawBal("nnacap", 1, trust2, w2, p2, flat2);
		gAirCapMul = (c2 == 0) ? 2.f : ((c2 == 2) ? 8.f : 4.f);
		array<string> names2 = {"A2", "A4", "A8"};
		AiLog(EcoLine("nnacap", "A4", flat2 > 0.f, trust2, st, qf, names2, w2, p2, c2));
	}
	{
		array<float> sf;
		sf.insertLast(float(ScoutFleetHave()));
		sf.insertLast(float(ScoutFleetCap()));
		sf.insertLast(float(TopOwnPlantTier()));
		sf.insertLast(ArmyValue());
		sf.insertLast(float(Military::gFmNLos));
		sf.insertLast(float(Military::gFmNRadar));
		sf.insertLast(Military::ScreenLostM());
		sf.insertLast(Eco::MInc());
		sf.insertLast(float(ai.frame) / 1800.f);
		array<float> sw(3, NE2_EPS);
		sw[0] = 1.f;
		const float strust = NnHeadScore(NNS_ON, NNS_STATE, NNS_SCOUT, NNS_S, NNS_O, NNS_H, NNS_XM, NNS_XS,
			NNS_W1, NNS_B1, NNS_W2, NNS_B2, NNS_WO, NNS_BO, NNS_TRUST, st, sf, sw);
		array<float> sp(3);
		const float sflat = NnHeadFlat();
		const int sc = EcoDrawBal("nnscap", 0, strust, sw, sp, sflat);
		gScoutCapMul = (sc == 1) ? 1.5f : ((sc == 2) ? 2.f : 1.f);   // x4 was 160 scouts an AI: a frame-budget risk at 16 AIs
		array<string> snames = {"S1", "S15", "S2"};
		AiLog(EcoLine("nnscap", "S1", sflat > 0.f, strust, st, sf, snames, sw, sp, sc));
	}
	{
		array<float> f;
		f.insertLast(float(OwnMexCount()));
		f.insertLast(float(ClaimableSpots()));
		f.insertLast(float(Military::gNrEcoLostM));
		f.insertLast(MexLossShare());
		f.insertLast(float(gDefYieldMex));
		f.insertLast(aShare);
		f.insertLast(FoeRaidMassM());
		f.insertLast(Eco::MCur());
		f.insertLast(float(ai.frame) / 1800.f);
		array<float> w(3, NE2_EPS);
		w[NX_HOLD] = 1.f;
		const float trust = NnHeadScore(NNX_ON, NNX_STATE, NNX_MEX, NNX_S, NNX_O, NNX_H, NNX_XM, NNX_XS,
			NNX_W1, NNX_B1, NNX_W2, NNX_B2, NNX_WO, NNX_BO, NNX_TRUST, st, f, w);
		array<float> p(3);
		const float flat = NnHeadFlat();
		gMexPolicy = EcoDrawBal("nnmex", NX_HOLD, trust, w, p, flat);
		gMexMul = (gMexPolicy == NX_PUSH) ? 2.f : 1.f;
		array<string> names = {"HOLD", "YIELD", "PUSH"};
		AiLog(EcoLine("nnmex", "HOLD", flat > 0.f, trust, st, f, names, w, p, gMexPolicy));
	}
}

// PUSH: every mex want counts double before the draw, kept in nnMult so the
// builder net learns from the market's own value.
void EcoMexPush(array<Want@>@ ranked)
{
	if (gMexMul == 1.f)
		return;
	bool any = false;
	for (uint r = 0; r < ranked.length(); ++r) {
		if (ranked[r].kind != WK_MEX)
			continue;
		ranked[r].value *= gMexMul;
		ranked[r].nnMult *= gMexMul;
		any = true;
	}
	if (!any)
		return;
	for (uint r = 1; r < ranked.length(); ++r) {
		Want@ w = ranked[r];
		uint at = r;
		while ((at > 0) && (ranked[at - 1].value < w.value)) {
			@ranked[at] = ranked[at - 1];
			--at;
		}
		@ranked[at] = w;
	}
}

}  // namespace Market
