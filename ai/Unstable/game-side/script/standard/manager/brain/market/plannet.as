namespace Market {

// THE TEAM'S WAY TO WIN (his 2026-10-07, after six of us probed a 37k-metal
// tower line one 4k squad at a time: mass T3, missiles and banked nukes, many
// LRPCs -- and allies who know what each other build). One plan per ally
// team on the shared board, held NG_HOLD_S; whoever decides logs an nnplan
// row. A strategy explorer (apex_nn_plan_explore of discovery games) leads its
// team with one strategy, re-drawn only when our tech tier rises; any other
// explorer mixes the head flat into each draw (docs/how-it-works.md). The rule is
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
// contract budget.as's shares use: normalisation pays for a raise out of the rest.
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
const float NL_LO = 1.f, NL_HI = 3.f;   // his 10-11: 8 let an 8v8 bot stand up 5-8 basic air plants
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

// THE TEAM ARMY (his 10-11: mass at the front, then all attack together -- and it
// must not be able to flip-flop). One operation on the shared board, written only
// by the leader (lowest live team id), read by every seat. It only moves forward,
// MASS -> GO -> END; a new target or a re-mass is a NEW operation id, cancelling
// the old one. MASS: squads stage on one line toward the team's home centroid,
// out of the threat; GO when the gathered beat what stands there. GO ends only on
// an outcome held two reads: CLEARED (next goes straight on if still stronger) or
// SPENT (under half of them; next re-masses). The leader's hunt/strike picks the
// target; while an operation stands no seat's hunt or strike takes the focus.
const int BOARD_GATHER = 100, BOARD_GATHER_AT = 200;
const int BOARD_TA_OP = 2000, BOARD_TA_PHASE = 2001, BOARD_TA_X = 2002, BOARD_TA_Z = 2003, BOARD_TA_R = 2004;
const int BOARD_TA_HX = 2005, BOARD_TA_HZ = 2006, BOARD_TA_SINCE = 2007, BOARD_TA_KIND = 2008, BOARD_TA_STRIKES = 2009, BOARD_TA_SPENT = 2010, BOARD_TA_SEEN = 2011, BOARD_TA_NEED = 2012, BOARD_TA_ARRIVED = 2013;
const int BOARD_TA_HOMEX = 2100, BOARD_TA_HOMEZ = 2200, BOARD_TA_ATK = 2300, BOARD_TA_NEAR = 2400;
const int TA_NONE = 0, TA_MASS = 1, TA_GO = 2;
const array<string> TA_PHASES = {"NONE", "MASS", "GO"};
const array<string> TA_KINDS = {"-", "hunt", "strike", "line", "front", "expand"};
const float PUSH_STAND = 256.f;
int gPushNextAt = 0;
int gPushLogAt = 0;
int gTaOpsMade = 0;

bool TaFresh(int t)
{
	return float(ai.frame) - ai.GetTeamBoard(BOARD_GATHER_AT + t, -1e9f) < float(15 * SECOND);
}

int TaLeader()
{
	for (int t = 0; t < 64; ++t) {
		if (TaFresh(t))
			return t;
	}
	return ai.teamId;
}

int TaPhase() { return int(ai.GetTeamBoard(BOARD_TA_PHASE, 0.f)); }
int TaOp()    { return int(ai.GetTeamBoard(BOARD_TA_OP, 0.f)); }
bool TeamOpOn() { return TaPhase() != TA_NONE; }

AIFloat3 TaTarget(float &out r)
{
	r = ai.GetTeamBoard(BOARD_TA_R, 0.f);
	AIFloat3 fp(ai.GetTeamBoard(BOARD_TA_X, 0.f), 0.f, ai.GetTeamBoard(BOARD_TA_Z, 0.f));
	fp.y = ai.GetElevationAt(fp);
	return fp;
}

float TaSum(int base)
{
	float s = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (TaFresh(t))
			s += ai.GetTeamBoard(base + t, 0.f);
	}
	return s;
}

// The leader's own nets name the target; then the line our army dies to; then their front.
int TaPick(AIFloat3 &out at, float &out r)
{
	if (Military::gHtOn) {
		at = Military::gHtPos; r = Military::HUNT_R;
		return 1;
	}
	if (Military::gStOn) {
		at = Military::gStPos; r = Military::STRIKE_R;
		return 2;
	}
	if (PressExpansion(at, r))
		return 5;
	float m = 0.f;
	if (Military::TurretTarget(at, r, m)) {
		r = Military::TurretLineReach();
		return 3;
	}
	at = Front::FoeAnchor(); r = Military::HUNT_R;
	return OnMap(at) ? 4 : 0;
}

void TaOpen(int phase, const string why)
{
	AIFloat3 at;
	float r = 0.f;
	const int kind = (phase == TA_NONE) ? 0 : TaPick(at, r);
	const int op = TaOp() + 1;
	if (kind == 0)
		phase = TA_NONE;
	float hx = 0.f, hz = 0.f, hn = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (TaFresh(t) && (ai.GetTeamBoard(BOARD_TA_HOMEX + t, -1.f) >= 0.f)) {
			hx += ai.GetTeamBoard(BOARD_TA_HOMEX + t, 0.f);
			hz += ai.GetTeamBoard(BOARD_TA_HOMEZ + t, 0.f);
			hn += 1.f;
		}
	}
	ai.SetTeamBoard(BOARD_TA_X, at.x);
	ai.SetTeamBoard(BOARD_TA_Z, at.z);
	ai.SetTeamBoard(BOARD_TA_R, r);
	ai.SetTeamBoard(BOARD_TA_HX, (hn > 0.f) ? hx / hn : -1.f);
	ai.SetTeamBoard(BOARD_TA_HZ, (hn > 0.f) ? hz / hn : -1.f);
	ai.SetTeamBoard(BOARD_TA_SINCE, float(ai.frame));
	ai.SetTeamBoard(BOARD_TA_KIND, float(kind));
	ai.SetTeamBoard(BOARD_TA_STRIKES, 0.f);
	ai.SetTeamBoard(BOARD_TA_SEEN, 0.f);
	ai.SetTeamBoard(BOARD_TA_ARRIVED, 0.f);
	ai.SetTeamBoard(BOARD_TA_SPENT, 0.f);
	ai.SetTeamBoard(BOARD_TA_PHASE, float(phase));
	ai.SetTeamBoard(BOARD_TA_OP, float(op));   // last: a reader that sees the new id sees its fields
	++gTaOpsMade;
	if (kind == 5)
		++gPressExpOps;
	AiLog(Factory::T() + "apex: team-op " + op + " " + TA_PHASES[phase] + " (" + why + ") " + TA_KINDS[kind]
		+ " at=" + int(at.x) + "," + int(at.z) + " r=" + int(r) + " plan=" + NgName(gPlan));
}

void TaAdvance(int phase, const string why)
{
	ai.SetTeamBoard(BOARD_TA_PHASE, float(phase));
	ai.SetTeamBoard(BOARD_TA_SINCE, float(ai.frame));
	ai.SetTeamBoard(BOARD_TA_STRIKES, 0.f);
	ai.SetTeamBoard(BOARD_TA_SPENT, 0.f);
	float r = 0.f;
	const AIFloat3 fp = TaTarget(r);
	AiLog(Factory::T() + "apex: team-op " + TaOp() + " " + TA_PHASES[phase] + " (" + why + ") at="
		+ int(fp.x) + "," + int(fp.z));
}

// Two reads running before an outcome counts: one noisy sample ends nothing.
bool TaTwice(int slot, bool cond)
{
	if (!cond) {
		ai.SetTeamBoard(slot, 0.f);
		return false;
	}
	const float s = ai.GetTeamBoard(slot, 0.f) + 1.f;
	ai.SetTeamBoard(slot, s);
	return s >= 2.f;
}

void TaLead()
{
	const int phase = TaPhase();
	const bool pushes = PlanPushes() || ((gPlan == NG_NORMAL) && PressShort());
	if (!pushes || (ai.GetTunable("apex_team_army", TUNE_TEAM_ARMY) <= 0.f)) {
		if (phase != TA_NONE)
			TaOpen(TA_NONE, "plan holds");
		return;
	}
	if (phase == TA_NONE) {
		TaOpen(TA_MASS, "plan pushes");
		return;
	}
	// a hunted army moves: the operation follows it while the leader's hunt lasts,
	// and that hunt ending is what ends it -- a position update, never a new phase
	const bool hunting = (int(ai.GetTeamBoard(BOARD_TA_KIND, 0.f)) == 1);
	if (hunting && Military::gHtOn) {
		ai.SetTeamBoard(BOARD_TA_X, Military::gHtPos.x);
		ai.SetTeamBoard(BOARD_TA_Z, Military::gHtPos.z);
	}
	float r = 0.f;
	const AIFloat3 fp = TaTarget(r);
	const float foe = aiMilitaryMgr.GetEnemyInflNear(fp, r + PUSH_STAND);
	// an unscouted target is unknown, not gone: only ground once seen held can clear
	const bool occupied = (foe > 0.f) || (aiEnemyMgr.GetEnemyStructCostAt(fp, r) > 0.f);
	if (occupied)
		ai.SetTeamBoard(BOARD_TA_SEEN, 1.f);
	const bool gone = hunting ? !Military::gHtOn
			: (!occupied && (ai.GetTeamBoard(BOARD_TA_SEEN, 0.f) > 0.f));
	if (phase == TA_MASS) {
		if (TaTwice(BOARD_TA_STRIKES, gone)) {
			TaOpen(TA_MASS, "target gone");
			return;
		}
		// what stands there, or their strongest group anywhere -- what can meet us at once (unknown is not small)
		// Only a group nearer the target than we are can meet us there: their strongest anywhere
		// (base defence included) held a strike on 84 at need 1,100 for five minutes, army at home.
		const float hx = ai.GetTeamBoard(BOARD_TA_HX, -1.f);
		const float reach = (hx >= 0.f) ? fp.distance2D(AIFloat3(hx, 0.f, ai.GetTeamBoard(BOARD_TA_HZ, 0.f))) : 1e7f;
		const float strongest = aiMilitaryMgr.GetEnemyInflNear(fp, reach);
		const float need = (foe > strongest) ? foe : strongest;
		ai.SetTeamBoard(BOARD_TA_NEED, need);
		// A squad with a target never stands at the stage, so gathered read 0 all game: the army counts.
		const float gath = TaSum(BOARD_GATHER);
		const float atk = TaSum(BOARD_TA_ATK);
		const float team = (gath > atk) ? gath : atk;
		if ((team > 0.f) && (team > need))
			TaAdvance(TA_GO, "gathered " + int(team) + " > " + int(need) + " (there " + int(foe) + ")");
		return;
	}
	// GO: an outcome, never a timer -- judged on the army AT the target, not the team's total
	// (3v3 tests: the total kept the go alive while squads trickled in and traded 0.25-0.39)
	const float atk = TaSum(BOARD_TA_ATK);
	const float near = TaSum(BOARD_TA_NEAR);
	if (near > 0.f)
		ai.SetTeamBoard(BOARD_TA_ARRIVED, 1.f);
	const bool arrived = ai.GetTeamBoard(BOARD_TA_ARRIVED, 0.f) > 0.f;
	// or our army stands on it and nothing of theirs is there: an empty box is cleared too
	if (TaTwice(BOARD_TA_STRIKES, gone || (!occupied && (near > 0.f)))) {
		AIFloat3 nx;
		float nr = 0.f;
		TaPick(nx, nr);
		const float nextFoe = aiMilitaryMgr.GetEnemyInflNear(nx, nr + PUSH_STAND);
		TaOpen((near > nextFoe) ? TA_GO : TA_MASS, "cleared, there " + int(near) + " vs next " + int(nextFoe));
		return;
	}
	// spent: what reached the target is under half of what stands there (before arrival, only the
	// whole team falling under half can say so -- the army dying on the way)
	if (TaTwice(BOARD_TA_SPENT, arrived ? (near * 2.f < foe) : (atk * 2.f < foe)))
		TaOpen(TA_MASS, "spent, there " + int(near) + " team " + int(atk) + " vs " + int(foe));
}

void TeamPush()
{
	if (ai.frame < gPushNextAt)
		return;
	gPushNextAt = ai.frame + 5 * SECOND;
	const int phase = TaPhase();
	ai.SetTeamBoard(BOARD_GATHER + ai.teamId, (phase == TA_MASS) ? aiMilitaryMgr.GetGatheredPower() : 0.f);
	ai.SetTeamBoard(BOARD_GATHER_AT + ai.teamId, float(ai.frame));
	ai.SetTeamBoard(BOARD_TA_ATK + ai.teamId, aiMilitaryMgr.GetAttackPower());
	{
		float tr = 0.f;
		const AIFloat3 tp = TaTarget(tr);
		ai.SetTeamBoard(BOARD_TA_NEAR + ai.teamId, (phase != TA_NONE)
				? aiMilitaryMgr.GetAttackPowerNear(tp, tr + PUSH_STAND) : 0.f);
	}
	if (Builder::gHomeSet) {
		ai.SetTeamBoard(BOARD_TA_HOMEX + ai.teamId, Builder::gHomePos.x);
		ai.SetTeamBoard(BOARD_TA_HOMEZ + ai.teamId, Builder::gHomePos.z);
	}
	if (TaLeader() == ai.teamId)
		TaLead();
	const int now = TaPhase();
	if (now == TA_NONE) {
		aiMilitaryMgr.SetFocusHome(AIFloat3(-1.f, 0.f, 0.f));
		if (!Military::HuntHoldsFocus() && !Military::StrikeHoldsFocus())
			aiMilitaryMgr.SetFocus(AIFloat3(0.f, 0.f, 0.f), 0.f, 0.f, false, -1);
		return;
	}
	float r = 0.f;
	const AIFloat3 fp = TaTarget(r);
	const float team = TaSum(BOARD_GATHER);
	const float hx = ai.GetTeamBoard(BOARD_TA_HX, -1.f);
	aiMilitaryMgr.SetFocusHome((hx >= 0.f) ? AIFloat3(hx, 0.f, ai.GetTeamBoard(BOARD_TA_HZ, 0.f)) : AIFloat3(-1.f, 0.f, 0.f));
	aiMilitaryMgr.SetFocus(fp, r, team, now == TA_GO, ai.frame + 10 * SECOND);
	if (ai.frame >= gPushLogAt) {
		gPushLogAt = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: team-army t=" + ai.teamId + " op=" + TaOp() + " " + TA_PHASES[now]
			+ " " + TA_KINDS[int(ai.GetTeamBoard(BOARD_TA_KIND, 0.f))] + " at=" + int(fp.x) + "," + int(fp.z)
			+ " r=" + int(r) + " foe=" + NnF(aiMilitaryMgr.GetEnemyInflNear(fp, r + PUSH_STAND), 1)
			+ " gathered=" + NnF(team, 1) + " need=" + NnF(ai.GetTeamBoard(BOARD_TA_NEED, 0.f), 1)
			+ " mine=" + NnF(aiMilitaryMgr.GetGatheredPower(), 1)
			+ " teamAtk=" + NnF(TaSum(BOARD_TA_ATK), 1) + " lead=" + TaLeader()
			+ " age=" + int((float(ai.frame) - ai.GetTeamBoard(BOARD_TA_SINCE, 0.f)) / float(SECOND)) + "s");
	}
}

// Where the team army is going in, while its operation is in GO.
bool PushGoAt(AIFloat3 &out at, float &out r)
{
	if (TaPhase() != TA_GO)
		return false;
	at = TaTarget(r);
	return r > 0.f;
}

// The id of the operation in GO, or -1: the air strikes with the land army (his 10-11).
int TeamGoOp()
{
	return (TaPhase() == TA_GO) ? TaOp() : -1;
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
