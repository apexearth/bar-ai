namespace Market {

// THE TEAM'S WAY TO WIN (his 2026-10-07, after six of us probed a 37k-metal
// tower line one 4k squad at a time: mass T3, missiles and banked nukes, many
// LRPCs -- and allies who know what each other build). One plan per ally
// team on the shared board, held NG_HOLD_S; whoever decides logs an nnplan
// row. A strategy explorer (apex_nn_plan_explore of discovery games) leads its
// team with one strategy, re-drawn only when our tech tier rises; any other
// explorer mixes the head flat into each draw (docs/35). The rule is
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
const int BOARD_PLAN = 1, BOARD_PLAN_UNTIL = 2, BOARD_PLAN_LEAD = 7;   // LEAD: explorer's engine team + 1, 0 none
// A trusted net's own odds, half flat so a rare plan is still tried.
const float NG_EX_FLAT = 0.5f;
int gPlan = NG_NORMAL;
int gPlanNextAt = 0;
int gPlanMineUntil = 0;
int gPlanExAt = -1;     // when the explorer last drew its strategy
int gPlanExTier = 1;    // our top tier then
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

// The army we mean to hold. Greed may go below their army, and holds only
// while we SEE them passive -- blind or under attack, the full army returns.
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

void PlanBoardWrite(bool leads)
{
	ai.SetTeamBoard(BOARD_PLAN, float(gPlan));
	ai.SetTeamBoard(BOARD_PLAN_UNTIL, float(gPlanMineUntil));
	ai.SetTeamBoard(BOARD_PLAN_LEAD, leads ? float(ai.teamId + 1) : 0.f);
}

void PlanNetDecide()
{
	if (ai.frame < gPlanNextAt)
		return;
	gPlanNextAt = ai.frame + 30 * SECOND;
	NnExploreRoll();
	// A strategy explorer, or a bot set to try strategies (a lobby option for
	// his multiplayer games), draws ONE strategy and leads its team with it;
	// a second explorer on the team follows the first.
	const bool explore = gNnPlanExplore || (ai.GetTunable("apex_plan_explore", TUNE_PLAN_EXPLORE) > 0.f);
	const bool live = ai.GetTeamBoard(BOARD_PLAN_UNTIL, -1.f) > float(ai.frame);
	const int lead = int(ai.GetTeamBoard(BOARD_PLAN_LEAD, 0.f)) - 1;
	const bool leads = explore && (!live || (lead < 0) || (lead == ai.teamId));
	if (live && !leads) {
		const int was = gPlan;
		gPlan = int(ai.GetTeamBoard(BOARD_PLAN, 0.f));
		if (gPlan != was)
			AiLog("apex: plan t=" + ai.teamId + " follows " + NgName(gPlan));
		if (explore)
			NnExploreSay(NgName(gPlan), "led by explorer team " + lead);
		return;
	}
	gPlanMineUntil = ai.frame + NG_HOLD_S * SECOND;
	// The explorer's strategy stands until our top tier rises, and at least one
	// hold; renewing the lease keeps allies on it, and it lapses if we die.
	const int tier = (OwnTopTier() > 1) ? OwnTopTier() : 1;
	if (leads && (gPlanExAt >= 0)
		&& ((tier <= gPlanExTier) || (ai.frame < gPlanExAt + NG_HOLD_S * SECOND))) {
		PlanBoardWrite(true);
		return;
	}
	const string why = !leads ? "clock" : ((gPlanExAt < 0) ? "first" : "tier");
	if (leads) {
		gPlanExAt = ai.frame;
		gPlanExTier = tier;
	}
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
	// An untrusted net's odds are only the NORMAL prior: the explorer then draws evenly.
	// a whole-team plan is strategy exploration: only its own roll draws one (his 10-09)
	const float flat = leads ? ((trust > 0.f) ? NG_EX_FLAT : 1.f) : 0.f;
	array<float> p(NG_N);
	gPlan = EcoDraw(NG_NORMAL, trust, w, p, flat);
	const int force = int(ai.GetTunable("apex_plan_force", TUNE_PLAN_FORCE));
	const bool forced = (force >= 0) && (force < NG_N);
	if (forced) {
		gPlan = force;
		for (int o = 0; o < NG_N; ++o)
			p[o] = (o == force) ? 1.f : 0.f;
	}
	PlanBoardWrite(leads);
	AiLog(EcoLine("nnplan", "NORMAL", (flat > 0.f) && !forced, trust, st, f, NG_NAMES, w, p, gPlan, why));
	if (!leads)
		return;
	AiLog("apex: nn-explore-plan t=" + ai.teamId + " plan=" + NgName(gPlan) + " p=" + NnF(p[gPlan], 3)
		+ " why=" + why + " tier=" + tier + " trust=" + NnF(trust, 2) + " flat=" + NnF(flat, 2)
		+ " discovery=" + (gNnPlanExplore ? 1 : 0));
	if (!gNnPlanExplore)
		return;
	if (why == "first")
		NnExploreSay(NgName(gPlan), "drawn at " + int(100.f * p[gPlan] + 0.5f) + "% odds, held until our tech tier rises");
	else
		ai.SendChat("Team " + ai.teamId + " discovery: tier " + tier + " reached, strategy now " + NgName(gPlan));
}

// HOW MANY AIR PLANTS while the plan is AIR: a continuous head, an absolute count
// (the rule's is 1), taken up to the next whole plant where it is used.
const string NNL_PLANT = "airPlants,mInc,eInc,bankFill,foeAirM,foeFighterM,foeAAM,ourBombers,ourFighters,minute";
const float NL_LO = 1.f, NL_HI = 8.f;
float gAirPlantMax = 1.f;
int gAirPlantNextAt = 0;

void AirPlantNetDecide()
{
	if ((gPlan != NG_AIR) || (ai.frame < gAirPlantNextAt))
		return;
	gAirPlantNextAt = ai.frame + 30 * SECOND;
	array<float> st;
	NnState(null, st);
	array<float> f;
	f.insertLast(float(Air::Have(Air::gPlant1) + Air::Have(Air::gPlant2)));
	f.insertLast(Eco::MInc());
	f.insertLast(Eco::EInc());
	f.insertLast((Eco::MStor() > 1.f) ? (Eco::MCur() / Eco::MStor()) : 0.f);
	f.insertLast(aiEnemyMgr.GetEnemyCostFresh(RT::AIR));
	f.insertLast(Air::FoeFighterM());
	f.insertLast(Air::StrikeAACost());
	f.insertLast(float(Air::Bombers()));
	f.insertLast(float(Air::Fighters()));
	f.insertLast(float(ai.frame) / 1800.f);
	gAirPlantMax = NnValDecide("aplant", NNL_PLANT, NL_LO, NL_HI, 1.f, NNL_ON, NNL_STATE, NNL_S, NNL_O, NNL_H,
		NNL_XM, NNL_XS, NNL_W1, NNL_B1, NNL_W2, NNL_B2, NNL_WO, NNL_BO, NNL_TRUST, NNL_LO, NNL_HI, st, f);
}

// Another basic air plant is owed: the plan is AIR and we stand short of the net's count.
bool AirPlantOwed(int d)
{
	return (gPlan == NG_AIR) && AirPlant(d) && (PlantTier(d) == 1)
		&& (ComCountOf(d, CS_FINISHED) + ComCountManned(d, CS_FRAMED | CS_ORDERED) < int(ceil(gAirPlantMax)));
}

// WHICH AI IS PLAYING, said once per team in chat and by every bot in its log.
const int BOARD_BANNER = 300;
bool gVersionLogged = false;
void VersionBanner()
{
	if (!gVersionLogged) {
		gVersionLogged = true;
		AiLog("apex: version t=" + ai.teamId + " " + ai.GetAiVersion() + " nets=" + NNW_GAMES + " script=" + APEX_SCRIPT);
	}
	if ((ai.frame < 3 * SECOND) || (ai.GetTeamBoard(BOARD_BANNER, -1.f) >= 0.f))
		return;
	ai.SetTeamBoard(BOARD_BANNER, float(ai.frame));
	ai.SendChat("Apex " + ai.GetAiVersion() + " - scripts " + APEX_SCRIPT + " - nets " + NNW_GAMES);
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
	// a hunt or a strike (military/nnhunt.as, nnstrike.as) owns this AI's focus while it lasts
	const bool held = Military::HuntHoldsFocus() || Military::StrikeHoldsFocus();
	if (!PlanPushes()) {
		if (!held)
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
		if (!held)
			aiMilitaryMgr.SetFocus(AIFloat3(0.f, 0.f, 0.f), 0.f, 0.f, false, -1);
		return;
	}
	AIFloat3 fp(ai.GetTeamBoard(BOARD_FOCUS_X, 0.f), 0.f, ai.GetTeamBoard(BOARD_FOCUS_Z, 0.f));
	fp.y = ai.GetElevationAt(fp);
	const float mine = held ? 0.f : aiMilitaryMgr.GetGatheredPower();   // squads standing at their own threat-clear stage
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
	if (!held)
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
