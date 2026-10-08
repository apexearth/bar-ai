namespace Market {

// THE TEAM'S WAY TO WIN (his 2026-10-07, after six of us probed a 37k-metal
// tower line one 4k squad at a time: mass T3, missiles and banked nukes, many
// LRPCs -- and allies who know what each other build). One plan per ally
// team on the shared board, held NG_HOLD_S; whoever decides logs an nnplan
// row (an explorer always decides, so discovery leads its team). The rule is
// NORMAL; the net learns which plan ends which game soonest. His 2026-10-07:
// the spontaneity he wants is strategies -- mass air, an early all-in, greed
// against a passive enemy, defences against one that is massing -- so those
// are plans too, drawn by the net, never rolled behind its back.
const string NNG_PLAN = "foeStaticM,foeArmyM,ourArmyM,breachM,mInc,eInc,gantries,silos,lrpcs,tacticals,bankFill,minute,stance,raidPressure,foeFreshM";
const int NG_NORMAL = 0, NG_T3 = 1, NG_MISSILE = 2, NG_ARTY = 3, NG_MASS = 4;
const int NG_AIR = 5, NG_RUSH = 6, NG_GREED = 7, NG_TURTLE = 8, NG_GREED_DEEP = 9, NG_N = 10;
const array<string> NG_NAMES = {"NORMAL", "T3", "MISSILE", "ARTY", "MASS", "AIR", "RUSH", "GREED", "TURTLE", "GREED_DEEP"};
const float NG_MUL = 4.f;
const int NG_HOLD_S = 480;   // a gantry or a battery takes longer than 4 min to pay off
const int BOARD_PLAN = 1, BOARD_PLAN_UNTIL = 2;
int gPlan = NG_NORMAL;
int gPlanNextAt = 0;
int gPlanMineUntil = 0;
bool gPlanHeader = false;

string NgName(int o)
{
	return ((o >= 0) && (o < NG_N)) ? NG_NAMES[o] : "NORMAL";
}

// GREED and TURTLE stay home; every other plan pushes as a team.
bool PlanPushes()
{
	return (gPlan != NG_NORMAL) && !PlanGreedy() && (gPlan != NG_TURTLE);
}

bool PlanGreedy()
{
	return (gPlan == NG_GREED) || (gPlan == NG_GREED_DEEP);
}

// The army we mean to hold. Greed (his 2026-10-07: below their army is fine,
// the net decides how far) holds only while we SEE them passive -- blind or
// under attack, the full army comes back.
float PlanArmyMult()
{
	if (gPlan == NG_RUSH)
		return 2.f;
	if (!PlanGreedy() || (Military::Stance() != int(Military::S_PASSIVE)))
		return 1.f;
	return (gPlan == NG_GREED_DEEP) ? 0.25f : 0.5f;
}

// The budget rows (Brain::Cat: 0 ARMY, 1 DEFENCE, 2 AIRDEF, 3 ECONOMY), on the
// contract Persona::ShareMult uses: normalisation pays for a raise out of the rest.
float PlanShareMult(int c)
{
	if ((gPlan == NG_RUSH) && (c == 0))
		return NG_MUL;
	if ((gPlan == NG_TURTLE) && ((c == 1) || (c == 2)))
		return NG_MUL;
	if (PlanGreedy() && (c == 3))
		return NG_MUL;
	return 1.f;
}

float PlanAirMult()
{
	return (gPlan == NG_AIR) ? NG_MUL : 1.f;
}

float PlanMul(int sc)
{
	if ((gPlan == NG_T3) && (sc == SC_GANTRY))
		return NG_MUL;
	if ((gPlan == NG_MISSILE) && ((sc == SC_SILO) || (sc == SC_TACTICAL) || (sc == SC_JUNO)))
		return NG_MUL;
	if ((gPlan == NG_ARTY) && (sc == SC_LRPC))
		return NG_MUL;
	if ((gPlan == NG_AIR) && (sc == SC_AIRPLANT))
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
	const float flat = explore ? 1.f : 0.f;   // an explorer tries whole plans, each equally often
	if (!gPlanHeader) {
		gPlanHeader = true;
		AiLog("apex: nnplan-schema v4 state=" + NN_STATE + " plan=" + NNG_PLAN + " opt=name,w,p opts=NORMAL,T3,MISSILE,ARTY,MASS,AIR,RUSH,GREED,TURTLE,GREED_DEEP");
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
	f.insertLast(float(Military::Stance()));
	f.insertLast(Military::RaidPressure());
	f.insertLast(Military::FreshMassingThreat());
	array<float> w(NG_N, NE2_EPS);
	w[NG_NORMAL] = 1.f;
	const float trust = NnHeadScore(NNG_ON, NNG_STATE, NNG_PLAN, NNG_S, NNG_O, NNG_H, NNG_XM, NNG_XS,
		NNG_W1, NNG_B1, NNG_W2, NNG_B2, NNG_WO, NNG_BO, NNG_TRUST, st, f, w);
	array<float> p(NG_N);
	gPlan = EcoDraw(NG_NORMAL, trust, w, p, flat);
	const int force = int(ai.GetTunable("apex_plan_force", TUNE_PLAN_FORCE));
	if ((force >= 0) && (force < NG_N)) {
		gPlan = force;
		for (int o = 0; o < NG_N; ++o)
			p[o] = (o == force) ? 1.f : 0.f;
	}
	ai.SetTeamBoard(BOARD_PLAN, float(gPlan));
	ai.SetTeamBoard(BOARD_PLAN_UNTIL, float(gPlanMineUntil));
	AiLog(EcoLine("nnplan", "NORMAL", explore, trust, st, f, NG_NAMES, w, p, gPlan));
}

// THE TEAM PUSH, under every plan but NORMAL: the plan's owner posts the
// turret line our army dies to; each ally's attack squads gather short of it
// (AttackTask), and when the team's gathered power beats the strongest group
// there -- the test a lone squad applies to itself -- all go together.
const int BOARD_FOCUS_X = 3, BOARD_FOCUS_Z = 4, BOARD_FOCUS_R = 5, BOARD_GO_UNTIL = 6;
const int BOARD_GATHER = 100, BOARD_GATHER_AT = 200;
const float PUSH_STAND = 256.f;
int gPushNextAt = 0;
int gPushLogAt = 0;
int gPushGoes = 0;

void TeamPush()
{
	if (ai.frame < gPushNextAt)
		return;
	gPushNextAt = ai.frame + 5 * SECOND;
	if (!PlanPushes()) {
		aiMilitaryMgr.SetFocus(AIFloat3(0.f, 0.f, 0.f), 0.f, 0.f, false, -1);
		return;
	}
	// A breach holds until it is broken: re-reading the turret target every 5 s
	// moved it across the front and the squads never gathered at any of them.
	const float hr = ai.GetTeamBoard(BOARD_FOCUS_R, -1.f);
	const bool holding = (hr >= 0.f) && (aiMilitaryMgr.GetEnemyInflNear(
		AIFloat3(ai.GetTeamBoard(BOARD_FOCUS_X, 0.f), 0.f, ai.GetTeamBoard(BOARD_FOCUS_Z, 0.f)), hr + PUSH_STAND) > 0.f);
	if ((ai.frame < gPlanMineUntil) && !holding) {
		AIFloat3 at;
		float r = 0.f, m = 0.f;
		if (Military::TurretTarget(at, r, m)) {
			r = Military::TurretLineReach();
			const float ox = ai.GetTeamBoard(BOARD_FOCUS_X, -1.f);
			const float oz = ai.GetTeamBoard(BOARD_FOCUS_Z, -1.f);
			if ((ox < 0.f) || (AIFloat3(ox, 0.f, oz).distance2D(at) > r))
				ai.SetTeamBoard(BOARD_GO_UNTIL, -1.f);
			ai.SetTeamBoard(BOARD_FOCUS_X, at.x);
			ai.SetTeamBoard(BOARD_FOCUS_Z, at.z);
			ai.SetTeamBoard(BOARD_FOCUS_R, r);
		} else {
			ai.SetTeamBoard(BOARD_FOCUS_R, -1.f);
		}
	}
	const float r = ai.GetTeamBoard(BOARD_FOCUS_R, -1.f);
	if (r < 0.f) {
		aiMilitaryMgr.SetFocus(AIFloat3(0.f, 0.f, 0.f), 0.f, 0.f, false, -1);
		return;
	}
	AIFloat3 fp(ai.GetTeamBoard(BOARD_FOCUS_X, 0.f), 0.f, ai.GetTeamBoard(BOARD_FOCUS_Z, 0.f));
	fp.y = ai.GetElevationAt(fp);
	const float mine = aiMilitaryMgr.GetGatheredPower();   // squads standing at their own threat-clear stage
	ai.SetTeamBoard(BOARD_GATHER + ai.teamId, mine);
	ai.SetTeamBoard(BOARD_GATHER_AT + ai.teamId, float(ai.frame));
	float team = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (float(ai.frame) - ai.GetTeamBoard(BOARD_GATHER_AT + t, -1e9f) < float(15 * SECOND))
			team += ai.GetTeamBoard(BOARD_GATHER + t, 0.f);
	}
	const float foe = aiMilitaryMgr.GetEnemyInflNear(fp, r + PUSH_STAND);
	bool go = ai.GetTeamBoard(BOARD_GO_UNTIL, -1.f) > float(ai.frame);
	if (!go && (team > 0.f) && (team > foe)) {
		go = true;
		++gPushGoes;
		ai.SetTeamBoard(BOARD_GO_UNTIL, float(ai.frame + 90 * SECOND));
		AiLog("apex: push go t=" + ai.teamId + " plan=" + NgName(gPlan) + " at=" + int(fp.x) + "," + int(fp.z)
			+ " foe=" + NnF(foe, 1) + " team=" + NnF(team, 1) + " mine=" + NnF(mine, 1));
	}
	aiMilitaryMgr.SetFocus(fp, r, team, go, ai.frame + 10 * SECOND);
	if (ai.frame >= gPushLogAt) {
		gPushLogAt = ai.frame + 30 * SECOND;
		AiLog("apex: push t=" + ai.teamId + " plan=" + NgName(gPlan) + " at=" + int(fp.x) + "," + int(fp.z)
			+ " r=" + int(r) + " foe=" + NnF(foe, 1) + " team=" + NnF(team, 1) + " mine=" + NnF(mine, 1)
			+ " all=" + NnF(aiMilitaryMgr.GetAttackPower(), 1) + " go=" + (go ? 1 : 0) + " goes=" + gPushGoes);
	}
}

// Where the team's push is going in, while its go stands.
bool PushGoAt(AIFloat3 &out at, float &out r)
{
	if (!PlanPushes() || (ai.GetTeamBoard(BOARD_GO_UNTIL, -1.f) <= float(ai.frame)))
		return false;
	r = ai.GetTeamBoard(BOARD_FOCUS_R, -1.f);
	if (r < 0.f)
		return false;
	at = AIFloat3(ai.GetTeamBoard(BOARD_FOCUS_X, 0.f), 0.f, ai.GetTeamBoard(BOARD_FOCUS_Z, 0.f));
	at.y = ai.GetElevationAt(at);
	return true;
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
