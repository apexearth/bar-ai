namespace Market {

// THE ESCORT NET (his 2026-10-06: "fix the escorts so existing raiders guard
// constructors, ensure the strength on that is hooked up to the NN"). How much
// escort a constructor is owed -- half, the rule's owed metal, or double -- is a
// team decision on a 30 s clock in the generic head shape (nncom/nnraid), with
// discovery games drawing the others; EscortOwedM reads the multiplier.
const string NNE_ESC = "workers,short,paired,risk,foeRaid,freeRaid,army,conLost,minute";
const int NE_LIGHT = 0, NE_MATCH = 1, NE_HEAVY = 2, NE_N = 3;
const float NE_EPS = 0.01f;
float gEscMul = 1.f;
int gEscNow = NE_MATCH;
int gEscNextAt = 0;
bool gEscHeader = false;
float gEscFlat = -1.f;

string NeName(int o) { return (o == NE_LIGHT) ? "LIGHT" : ((o == NE_HEAVY) ? "HEAVY" : "MATCH"); }
float NeMul(int o) { return (o == NE_LIGHT) ? 0.5f : ((o == NE_HEAVY) ? 2.f : 1.f); }
// The cap on escorts at once scales with the net's strength too: MATCH keeps his 8.
uint EscortCap() { return uint(ai.GetTunable("apex_escort_cap", TUNE_ESCORT_CAP) * gEscMul + 0.5f); }

void EscNetDecide()
{
	if (ai.frame < gEscNextAt)
		return;
	gEscNextAt = ai.frame + 30 * SECOND;
	ExposeRefresh();
	const int rule = NE_MATCH;
	const bool explore = gNnExploreRolled && gNnExplore;
	if (explore && (gEscFlat < 0.f))
		gEscFlat = float(AiRandom(0, 10000)) / 10000.f * 0.5f;
	array<float> st;
	NnState(null, st);
	array<float> ef;
	ef.insertLast(float(gWorkers.length()));
	ef.insertLast(float(gExpoN));
	ef.insertLast(float(gEscWorker.length()));
	ef.insertLast(gExpoM);
	ef.insertLast(FoeRaidMassM());
	ef.insertLast(RoleValue(int(Unit::Role::RAIDER.type)));
	ef.insertLast(ArmyValue());
	ef.insertLast(Military::gNrEcoLostM);
	ef.insertLast(float(ai.frame) / 1800.f);
	array<float> w(NE_N);
	for (int o = 0; o < NE_N; ++o)
		w[o] = (o == rule) ? 1.f : NE_EPS;
	const float trust = NnHeadScore(NNE_ON, NNE_STATE, NNE_ESC, NNE_S, NNE_O, NNE_H, NNE_XM, NNE_XS,
		NNE_W1, NNE_B1, NNE_W2, NNE_B2, NNE_WO, NNE_BO, NNE_TRUST, st, ef, w);
	float sum = 0.f;
	for (int o = 0; o < NE_N; ++o)
		sum += w[o];
	const float flat = explore ? gEscFlat : 0.f;
	array<float> p(NE_N);
	for (int o = 0; o < NE_N; ++o) {
		if ((trust > 0.f) || (flat > 0.f))
			p[o] = (1.f - flat) * w[o] / sum + flat / float(NE_N);
		else
			p[o] = (o == rule) ? 1.f : 0.f;
	}
	int chosen = rule;
	if ((trust > 0.f) || (flat > 0.f)) {
		float r = float(AiRandom(0, 10000)) / 10000.f;
		for (int o = 0; o < NE_N; ++o) {
			r -= p[o];
			if (r <= 0.f) {
				chosen = o;
				break;
			}
		}
	}
	gEscNow = chosen;
	gEscMul = NeMul(chosen);
	if (!gEscHeader) {
		gEscHeader = true;
		AiLog("apex: nnesc-schema v1 state=" + NN_STATE + " esc=" + NNE_ESC + " opt=name,w,p opts=LIGHT,MATCH,HEAVY");
	}
	string ln = "apex: nnesc t=" + ai.teamId + " f=" + ai.frame + " why=clock rule=" + NeName(rule)
		+ " ex=" + (explore ? 1 : 0) + " trust=" + NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < ef.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(ef[k], 3);
	for (int o = 0; o < NE_N; ++o)
		ln += ((o == 0) ? " | " : " ; ") + NeName(o) + "," + NnF(w[o], 4) + "," + NnF(p[o], 6);
	ln += " | chosen=" + chosen;
	AiLog(ln);
}

// EXISTING RAIDERS TAKE THE DUTY, not only a unit fresh from the factory. One
// pass, one unit: the most exposed worker still owed escort, the nearest free
// escort-worthy unit in walking reach of it is pulled off its pool or squad and
// re-elects into the escort hook. Raid packs, retreats and units in a fight are
// left alone.
int gEscRecruitN = 0;
int gEscRecruitLogAt = 0;
bool EscortRecruitable(CCircuitUnit@ c)
{
	IUnitTask@ t = c.task;
	if ((t is null) || (t.GetType() != Task::Type::FIGHTER))
		return false;
	const int ft = int(t.GetFightType());
	// a cheap fast scout is what an escort buy produces, and the engine
	// hands it a scout task the recruiter never looked in
	return (ft == int(Task::FightType::DEFEND)) || (ft == int(Task::FightType::RALLY))
		|| (ft == int(Task::FightType::ATTACK)) || (ft == int(Task::FightType::SCOUT));
}

int gEscCensusLogAt = 0;
void EscortSpareCensus()
{
	int n = 0;
	array<int> byType(16, 0);
	int noTask = 0;
	const array<int>@ own = OwnedDefs();
	for (uint k = 0; k < own.length(); ++k) {
		const int d = own[k];
		if (!EscortWorthy(d) || Catalog::gFlyer[d] || (Catalog::gSpeed[d] <= 1.f))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), Builder::gHomePos, 0.f);
		for (uint u = 0; (us !is null) && (u < us.length()); ++u) {
			CCircuitUnit@ c = us[u];
			if (c is null)
				continue;
			if ((c.task is null) || (c.task.GetType() != Task::Type::FIGHTER)) {
				++noTask;
			} else {
				const int ft = int(c.task.GetFightType());
				if ((ft >= 0) && (ft < 16))
					++byType[ft];
			}
			if (!EscortRecruitable(c) || (int(c.task.GetFightType()) == int(Task::FightType::ATTACK)))
				continue;
			bool paired = false;
			for (uint e = 0; (e < gEscUnit.length()) && !paired; ++e)
				paired = (gEscUnit[e] == c.id);
			if (!paired)
				++n;
		}
	}
	gEscSpare = n;
	if (ai.frame >= gEscCensusLogAt) {
		gEscCensusLogAt = ai.frame + 60 * SECOND;
		string ln = "apex: escort-census t=" + ai.teamId + " spare=" + n + " notask=" + noTask;
		for (int k = 0; k < 16; ++k)
			if (byType[k] > 0)
				ln += " ft" + k + "=" + byType[k];
		AiLog(ln);
	}
}

void EscortRecruit()
{
	EscortSpareCensus();
	if (ai.GetTunable("apex_con_escort", TUNE_CON_ESCORT) <= 0.f)
		return;
	if (gEscWorker.length() >= EscortCap())
		return;
	if (EscortShortfall() <= 0)
		return;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	CCircuitUnit@ wk = null;
	float wkExpo = 0.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ w = gWorkers[i];
		if (!EscortableWorker(w, false))
			continue;
		const float e = WorkerExposure(w);
		if (e > wkExpo) {
			wkExpo = e;
			@wk = w;
		}
	}
	if ((wk is null) || (wkExpo < 0.5f))
		return;
	const AIFloat3 wAt = wk.GetPos(ai.frame);
	CCircuitUnit@ best = null;
	float bestD = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint k = 0; k < own.length(); ++k) {
		const int d = own[k];
		if (!EscortWorthy(d) || Catalog::gFlyer[d])
			continue;
		const float spd = Catalog::gSpeed[d];
		if (spd <= 1.f)
			continue;
		const float reach = spd * 45.f;
		const float needM = EscortOwedM(wk, wkExpo, Catalog::gCostM[d], expoR, false);
		if (needM - EscortMetalOn(wk.id) < 0.5f * Catalog::gCostM[d])
			continue;
		array<CCircuitUnit@>@ near = ai.GetOwnUnitsOfDef(Catalog::Def(d), wAt, reach);
		if (near is null)
			continue;
		for (uint u = 0; u < near.length(); ++u) {
			CCircuitUnit@ c = near[u];
			if (!EscortRecruitable(c))
				continue;
			if (ai.frame - c.GetDamagedFrame() < 10 * SECOND)
				continue;
			bool paired = false;
			for (uint e = 0; (e < gEscUnit.length()) && !paired; ++e)
				paired = (gEscUnit[e] == c.id);
			if (paired)
				continue;
			const float dd = c.GetPos(ai.frame).distance2D(wAt);
			if ((best is null) || (dd < bestD)) {
				@best = c;
				bestD = dd;
			}
		}
	}
	if (best is null)
		return;
	best.task.RemoveUnit(best);
	++gEscRecruitN;
	if (ai.frame >= gEscRecruitLogAt) {
		gEscRecruitLogAt = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: escort-recruit t=" + ai.teamId + " " + best.circuitDef.GetName() + " #" + best.id
			+ " for " + wk.circuitDef.GetName() + " #" + wk.id + " d=" + int(bestD)
			+ " expo=" + NnF(wkExpo, 2) + " mul=" + NnF(gEscMul, 1) + " n=" + gEscRecruitN);
	}
}

}  // namespace Market
