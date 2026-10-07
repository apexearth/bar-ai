namespace Market {

// THE TEAM'S WAY TO WIN (his 2026-10-07, after six of us probed a 37k-metal
// tower line one 4k squad at a time: mass T3, missiles and banked nukes, many
// LRPCs -- and allies who know what each other build). One plan per ally
// team on the shared board, held NG_HOLD_S; whoever decides logs an nnplan
// row (an explorer always decides, so discovery leads its team). The rule is
// NORMAL; the net learns which plan ends which game soonest.
const string NNG_PLAN = "foeStaticM,foeArmyM,ourArmyM,breachM,mInc,eInc,gantries,silos,lrpcs,tacticals,bankFill,minute";
const int NG_NORMAL = 0, NG_T3 = 1, NG_MISSILE = 2, NG_ARTY = 3;
const float NG_MUL = 4.f;
const int NG_HOLD_S = 240;
const int BOARD_PLAN = 1, BOARD_PLAN_UNTIL = 2;
int gPlan = NG_NORMAL;
int gPlanNextAt = 0;
int gPlanMineUntil = 0;
bool gPlanHeader = false;

string NgName(int o)
{
	return (o == NG_T3) ? "T3" : ((o == NG_MISSILE) ? "MISSILE" : ((o == NG_ARTY) ? "ARTY" : "NORMAL"));
}

float PlanMul(int sc)
{
	if ((gPlan == NG_T3) && (sc == SC_GANTRY))
		return NG_MUL;
	if ((gPlan == NG_MISSILE) && ((sc == SC_SILO) || (sc == SC_TACTICAL) || (sc == SC_JUNO)))
		return NG_MUL;
	if ((gPlan == NG_ARTY) && (sc == SC_LRPC))
		return NG_MUL;
	return 1.f;
}

void PlanNetDecide()
{
	if (ai.frame < gPlanNextAt)
		return;
	gPlanNextAt = ai.frame + 30 * SECOND;
	const bool explore = gNnExploreRolled && gNnExplore;
	const float until = ai.GetTeamBoard(BOARD_PLAN_UNTIL, -1.f);
	if ((until > float(ai.frame)) && (!explore || (ai.frame < gPlanMineUntil))) {
		const int was = gPlan;
		gPlan = int(ai.GetTeamBoard(BOARD_PLAN, 0.f));
		if (gPlan != was)
			AiLog("apex: plan t=" + ai.teamId + " follows " + NgName(gPlan));
		return;
	}
	gPlanMineUntil = ai.frame + NG_HOLD_S * SECOND;
	if (explore && (gEcoFlat < 0.f))
		gEcoFlat = float(AiRandom(0, 10000)) / 10000.f * 0.5f;
	const float flat = explore ? gEcoFlat : 0.f;
	if (!gPlanHeader) {
		gPlanHeader = true;
		AiLog("apex: nnplan-schema v1 state=" + NN_STATE + " plan=" + NNG_PLAN + " opt=name,w,p opts=NORMAL,T3,MISSILE,ARTY");
	}
	array<float> st;
	NnState(null, st);
	AIFloat3 bp;
	float bR = 0.f, bM = 0.f;
	if (!Military::TurretTarget(bp, bR, bM))
		bM = 0.f;
	array<float> f;
	f.insertLast(aiEnemyMgr.GetEnemyCost(RT::STATIC));
	f.insertLast(Military::EnemyMassingThreat());
	f.insertLast(ArmyValue());
	f.insertLast(bM);
	f.insertLast(Eco::MInc());
	f.insertLast(Eco::EInc());
	f.insertLast(float(SuperHave(SC_GANTRY)));
	f.insertLast(float(SuperHave(SC_SILO)));
	f.insertLast(float(SuperHave(SC_LRPC)));
	f.insertLast(float(SuperHave(SC_TACTICAL) + SuperHave(SC_JUNO)));
	f.insertLast((Eco::MStor() > 1.f) ? (Eco::MCur() / Eco::MStor()) : 0.f);
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> w(4, NE2_EPS);
	w[NG_NORMAL] = 1.f;
	const float trust = NnHeadScore(NNG_ON, NNG_STATE, NNG_PLAN, NNG_S, NNG_O, NNG_H, NNG_XM, NNG_XS,
		NNG_W1, NNG_B1, NNG_W2, NNG_B2, NNG_WO, NNG_BO, NNG_TRUST, st, f, w);
	array<float> p(4);
	gPlan = EcoDraw(NG_NORMAL, trust, w, p, flat);
	ai.SetTeamBoard(BOARD_PLAN, float(gPlan));
	ai.SetTeamBoard(BOARD_PLAN_UNTIL, float(gPlanMineUntil));
	array<string> names = {"NORMAL", "T3", "MISSILE", "ARTY"};
	AiLog(EcoLine("nnplan", "NORMAL", explore, trust, st, f, names, w, p, gPlan));
}

// ALLIES BUILD ONE GANTRY TOGETHER (his 2026-10-07: "why make 8 gantries in an
// 8v8 when you can notice one of your allies is making one and if it isn't far
// away you can help them make it and then support what they build"). "Not far"
// is the walk against the time our whole build power would take to raise one.
array<float> gAllyGant;   // x, z, defId, unitId, progress
int gAllyGantAt = -1;
float gOwnBpRaw = 0.f;

void AllyGantScan()
{
	if ((gAllyGantAt >= 0) && (ai.frame < gAllyGantAt + 5 * SECOND))
		return;
	gAllyGantAt = ai.frame;
	gAllyGant.resize(0);
	const array<float>@ ab = ai.GetAllyBuilds();
	for (uint i = 0; (ab !is null) && (i + 4 < ab.length()); i += 5) {
		if (!IsGantryDef(int(ab[i + 2])))
			continue;
		for (uint k = 0; k < 5; ++k)
			gAllyGant.insertLast(ab[i + k]);
	}
	gOwnBpRaw = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint oi = 0; oi < own.length(); ++oi) {
		const int d = own[oi];
		if (gOwnCount[d] > 0)
			gOwnBpRaw += float(gOwnCount[d]) * Catalog::gBuildPower[d];
	}
}

// Our hands on an ally's unit (the guard ledger holds our own bosses only).
array<Id> gAllyGuardU;
array<int> gAllyGuardB;
int gAssistAllyId = -1;

void AllyGuardNote(CCircuitUnit@ u, int allyId)
{
	gAllyGuardU.insertLast(u.id);
	gAllyGuardB.insertLast(allyId);
}

int AllyGuardsOn(int allyId)
{
	int n = 0;
	for (uint i = 0; i < gAllyGuardU.length(); ) {
		CCircuitUnit@ u = ai.GetTeamUnit(gAllyGuardU[i]);
		if ((u is null) || (u.task is null) || (int(u.task.GetBuildType()) != int(Task::BuildType::GUARD))) {
			gAllyGuardU.removeAt(i);
			gAllyGuardB.removeAt(i);
			continue;
		}
		if (gAllyGuardB[i] == allyId)
			++n;
		++i;
	}
	return n;
}

// The ally gantry this hand should serve, or -1.
int AllyGantryFor(CCircuitUnit@ unit, AIFloat3 &out at, int &out def, float &out progress)
{
	if ((unit is null) || (unit.circuitDef is null))
		return -1;
	AllyGantScan();
	const int ud = int(unit.circuitDef.id);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[ud];
	int best = -1;
	float bestD = 0.f;
	for (uint i = 0; i + 4 < gAllyGant.length(); i += 5) {
		AIFloat3 p(gAllyGant[i], 0.f, gAllyGant[i + 1]);
		p.y = ai.GetElevationAt(p);
		const int gd = int(gAllyGant[i + 2]);
		const float d = here.distance2D(p);
		const float ownS = (gOwnBpRaw > 0.f) ? (Catalog::gBuildTime[gd] / gOwnBpRaw) : 1e9f;
		if ((speed <= 0.f) || (d / speed > ownS))
			continue;
		if (!ai.CanDefReach(Catalog::Def(ud), here, p))
			continue;
		if ((best < 0) || (d < bestD)) {
			best = int(gAllyGant[i + 3]);
			bestD = d;
			at = p;
			def = gd;
			progress = gAllyGant[i + 4];
		}
	}
	return best;
}

}  // namespace Market
