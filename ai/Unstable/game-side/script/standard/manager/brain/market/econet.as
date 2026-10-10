namespace Market {

// THE ECONOMY NETS (his 2026-10-06: "let the network discover which is better" --
// constructors vs army, and how hard we go out for extractors). Continuous heads
// (NnValDecide), each a multiplier on today's rule value (1x), on a 30 s clock.
//
// con  -- ConsNeedAny's target x v, and the floor yields only while the army's
//         share is under its target / v (1x = the rule).
// mex  -- every mex want's value x v before the draw; above 1x an open mex also
//          comes before the forced guns (HOLD = 1x, the rule).
// cap  -- the ground constructor pools x v of the base.
// acap -- the air pool x 4v of the base (4 = the rule: air cons take no build space).
// scap -- the late ground scout cap x v of the same base.
const string NNK_CON = "cons,consNeed,armyShare,armyTarget,armyGap,mexes,openSpots,foeRaid,minute";
const string NNX_MEX = "mexes,openSpots,mexLost,mexKilledRate,defWants,armyShare,foeRaid,bankM,minute";
const string NNQ_CAP = "conT1,conT2,conAir,capT1,capT2,capAir,conShare,mInc,mWasting,bankFill,idleCons,minute";
const string NNS_SCOUT = "scouts,scoutCap,topTier,army,foeLos,foeRadar,screenLost,mInc,minute";
const float NE2_EPS = 0.01f;
const float NK_LO = 0.25f, NK_HI = 8.f;
const float NX_LO = 0.f, NX_HI = 6.f;
const float NQ_LO = 0.5f, NQ_HI = 12.f;
const float NZ_LO = 1.f, NZ_HI = 20.f;
const float NZ_RULE = 4.f;
const float NS_LO = 0.25f, NS_HI = 8.f;
float gConFloorMul = 1.f;
float gConCapMul = 1.f;
float gAirCapMul = NZ_RULE;
float gScoutCapMul = 1.f;
float gMexMul = 1.f;
// one head a second, not five in one frame: a trusted head sweeps its net
array<int> gEcoNetAt = {0, SECOND, 2 * SECOND, 3 * SECOND, 4 * SECOND};

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

string EcoLine(const string tag, const string rule, bool explore, float trust, const array<float>& in st,
	const array<float>& in f, const array<string>& in names, const array<float>& in w, const array<float>& in p, int chosen,
	const string why = "clock")
{
	string ln = "apex: " + tag + " t=" + ai.teamId + " f=" + ai.frame + " why=" + why + " rule=" + rule
		+ " ex=" + (explore ? 1 : 0) + " trust=" + NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < f.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(f[k], 3);
	for (uint o = 0; o < names.length(); ++o)
		ln += ((o == 0) ? " | " : " ; ") + names[o] + "," + NnF(w[o], 4) + "," + NnF(p[o], 6);
	return ln + " | chosen=" + chosen;
}

bool EcoNetDue(int k)
{
	if (ai.frame < gEcoNetAt[k])
		return false;
	gEcoNetAt[k] = ai.frame + 30 * SECOND;
	return true;
}

void CapFields(array<float>& qf)
{
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
}

void EcoNetDecide()
{
	if (EcoNetDue(0)) {
		array<float> st;
		NnState(null, st);
		array<float> f;
		f.insertLast(float(ConFleetHave()));
		f.insertLast(float(ConsNeedAt(false, 1.f)));
		f.insertLast((Brain::gSpentTotal > 1.f) ? Brain::ShareOf(Brain::ARMY) : 0.f);
		f.insertLast(Brain::TargetShare(Brain::ARMY));
		f.insertLast(ArmyTarget() - ArmyValue());
		f.insertLast(float(OwnMexCount()));
		f.insertLast(float(ClaimableSpots()));
		f.insertLast(FoeRaidMassM());
		f.insertLast(float(ai.frame) / 1800.f);
		gConFloorMul = NnValDecide("con", NNK_CON, NK_LO, NK_HI, 1.f, NNK_ON, NNK_STATE, NNK_S, NNK_O, NNK_H,
			NNK_XM, NNK_XS, NNK_W1, NNK_B1, NNK_W2, NNK_B2, NNK_WO, NNK_BO, NNK_TRUST, NNK_LO, NNK_HI, st, f);
	}
	if (EcoNetDue(1)) {
		array<float> st;
		NnState(null, st);
		array<float> qf;
		CapFields(qf);
		gConCapMul = NnValDecide("cap", NNQ_CAP, NQ_LO, NQ_HI, 1.f, NNQ_ON, NNQ_STATE, NNQ_S, NNQ_O, NNQ_H,
			NNQ_XM, NNQ_XS, NNQ_W1, NNQ_B1, NNQ_W2, NNQ_B2, NNQ_WO, NNQ_BO, NNQ_TRUST, NNQ_LO, NNQ_HI, st, qf);
	}
	if (EcoNetDue(2)) {
		array<float> st;
		NnState(null, st);
		array<float> qf;
		CapFields(qf);
		gAirCapMul = NZ_RULE * NnValDecide("acap", NNQ_CAP, NZ_LO, NZ_HI, 1.f, NNZ_ON, NNZ_STATE, NNZ_S, NNZ_O,
			NNZ_H, NNZ_XM, NNZ_XS, NNZ_W1, NNZ_B1, NNZ_W2, NNZ_B2, NNZ_WO, NNZ_BO, NNZ_TRUST, NNZ_LO, NNZ_HI, st, qf);
	}
	if (EcoNetDue(3)) {
		array<float> st;
		NnState(null, st);
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
		gScoutCapMul = NnValDecide("scap", NNS_SCOUT, NS_LO, NS_HI, 1.f, NNS_ON, NNS_STATE, NNS_S, NNS_O, NNS_H,
			NNS_XM, NNS_XS, NNS_W1, NNS_B1, NNS_W2, NNS_B2, NNS_WO, NNS_BO, NNS_TRUST, NNS_LO, NNS_HI, st, sf);
	}
	if (EcoNetDue(4)) {
		array<float> st;
		NnState(null, st);
		array<float> f;
		f.insertLast(float(OwnMexCount()));
		f.insertLast(float(ClaimableSpots()));
		f.insertLast(float(Military::gNrEcoLostM));
		f.insertLast(MexLossShare());
		f.insertLast(float(gDefYieldMex));
		f.insertLast((Brain::gSpentTotal > 1.f) ? Brain::ShareOf(Brain::ARMY) : 0.f);
		f.insertLast(FoeRaidMassM());
		f.insertLast(Eco::MCur());
		f.insertLast(float(ai.frame) / 1800.f);
		gMexMul = NnValDecide("mex", NNX_MEX, NX_LO, NX_HI, 1.f, NNX_ON, NNX_STATE, NNX_S, NNX_O, NNX_H,
			NNX_XM, NNX_XS, NNX_W1, NNX_B1, NNX_W2, NNX_B2, NNX_WO, NNX_BO, NNX_TRUST, NNX_LO, NNX_HI, st, f);
	}
}

// Every mex want's value x the expansion head's v before the draw, kept in nnMult
// so the builder net learns from the market's own value; floored so a value
// divided back out stays finite.
void EcoMexPush(array<Want@>@ ranked)
{
	if (gMexMul == 1.f)
		return;
	const float m = (gMexMul > 0.001f) ? gMexMul : 0.001f;
	bool any = false;
	for (uint r = 0; r < ranked.length(); ++r) {
		if (ranked[r].kind != WK_MEX)
			continue;
		ranked[r].value *= m;
		ranked[r].nnMult *= m;
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
