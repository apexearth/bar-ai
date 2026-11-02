namespace Market {
// THE TEAM'S STYLE (his 11-01): one committed way to play for every Apex seat on an ally team, drawn hidden from the
// styles this game allows, leaning its key prices STYLE_AMP^(c * fit) -- fit in [0, 1] read off unit stats (range and
// speed full at 1.5x their tier's mean), c the team's commitment. c starts at 1 and is multiplied each minute by
// the worse of two readings, each with apex_trade_vol seconds of team income on both sides so a skirmish is no
// verdict: the trade (our kills over our losses, the death ledger's decayed metal summed over the team's seats) and
// the army estimate (our ground army with allies plus our seats' air over theirs believed, against that ratio when the
// style was drawn: a style is judged on what it did to the balance it inherited). Below break-even it fades toward
// balanced; once the style's lean is no larger than one seat's own flavour (STYLE_AMP^c <= PERS_SEAT_AMP) the team
// draws a style it has not tried. Log only, never chat.
const int ST_BALANCED = 0, ST_ARTY = 1, ST_STEALTH = 2, ST_AIR = 3, ST_FAST = 4, ST_T3 = 5, ST_NUKE = 6;
const int ST_SHIELD = 7, ST_SCOUT = 8, ST_N = 9;
const array<string> ST_NAMES = {"BALANCED", "ARTY", "STEALTH", "AIR", "FAST", "T3", "NUKE", "SHIELD", "SCOUT"};
const array<int> ST_PLAN = {-1, NG_ARTY, -1, NG_AIR, -1, NG_T3, NG_MISSILE, NG_MASS, -1};
const array<int> ST_KEY = {-1, PD_CLASS + LC_REACH, -1, PD_AIR, PD_FAST, PD_TECH, PD_TECH, PD_CLASS + LC_TANK, PD_SCOUT};
const array<float> ST_DRAW_W = {2.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f};
const float STYLE_AMP = 3.5f;
const float PERS_PRESSURE = 1.5f;
const int PB_STYLE = 9200, PB_GEN = 9201, PB_C = 9202, PB_USED = 9203, PB_AT = 9204, PB_R = 9205, PB_RT = 9206, PB_RA = 9207, PB_RA0 = 9208;
const int PB_AVAIL = 9300, PB_FORCE = 9400, PB_SEEN = 9500, PB_KILL = 9600, PB_LOSS = 9700, PB_INC = 9800, PB_AIRM = 9900;
const int PB_BAD = 9209;   // bad minutes in a row for the current style
const int PS_HOLD = 10 * MINUTE;
const int PS_BAD_RUN = 3;
const int PS_DRAW_AT = 3 * SECOND;
const int PS_FRESH = 90 * SECOND;

int gStyle = -1, gStyleGen = 0;
float gStyleC = 1.f, gStyleCLogged = 1.f;
int gPsForce = -2;
int gPsAvail = -1;
int gPsPubAt = -999999, gPsLeadAt = -999999, gPsStatAt = -999999;
array<float> gPsFit;
array<float> gPsSpd;
array<int> gPsPlantAt;
array<float> gPsPlant;
int gPsPlantKey = -1;
float gPsLostStyle = 0.f, gPsLostAll = 0.f;

string StName(int s) { return ((s >= 0) && (s < ST_N)) ? ST_NAMES[s] : "-"; }

int PsForce()
{
	if (gPsForce == -2) {
		const int f = int(ai.GetTunable("apex_persona_force", TUNE_PERSONA_FORCE));
		gPsForce = ((f >= 0) && (f < ST_N)) ? f : -1;
	}
	return gPsForce;
}

bool PsModOpt(const string &in key)
{
	const string v = string(aiSetupMgr.GetModOptions()[key]);
	return (v == "1") || (v == "true");
}

int gPsBlk = -1;
bool gBlkAir = false, gBlkNuke = false, gBlkTac = false, gBlkLrpc = false, gBlkT2 = false, gBlkT3 = false;
// BAR's unit_restrictions_* block a def by customParams the script cannot read; their reach here is from stats
bool PsBlocked(int d)
{
	if (gPsBlk < 0) {
		gPsBlk = 1;
		gBlkAir = PsModOpt("unit_restrictions_noair");
		gBlkNuke = PsModOpt("unit_restrictions_nonukes");
		gBlkTac = PsModOpt("unit_restrictions_notacnukes");
		gBlkLrpc = PsModOpt("unit_restrictions_nolrpc") || PsModOpt("unit_restrictions_noendgamelrpc");
		gBlkT2 = PsModOpt("unit_restrictions_notech2");
		gBlkT3 = PsModOpt("unit_restrictions_notech3");
	}
	if (gBlkAir && (Catalog::gFlyer[d] || (!Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0) && (PlantClass(d) == PC_AIR))))
		return true;
	const int sc = SuperClassOf(d);
	if (gBlkNuke && (sc == SC_SILO))
		return true;
	if (gBlkTac && (sc == SC_TACTICAL))
		return true;
	if (gBlkLrpc && (sc == SC_LRPC))
		return true;
	if (gBlkT3 && (IsGantryDef(d) || PsGantryMade(d)))
		return true;
	if (gBlkT2 && IsAdvancedDef(d))
		return true;
	return false;
}

bool PsGantryMade(int d)
{
	const array<int>@ by = Catalog::gBuiltBy[d];
	for (uint i = 0; i < by.length(); ++i)
		if (IsGantryDef(by[i]))
			return true;
	return false;
}

bool PsIsScout(int d)
{
	return IsLateScout(d) || Air::IsLookDef(d);
}

// the shape CircuitDef::IsSniper reads (C++, not bound): a far surface gun on a thin body
bool PsIsSniper(int d)
{
	return Catalog::gMobile[d] && !Catalog::gFlyer[d] && !Catalog::gFloater[d] && !Catalog::gSub[d]
		&& !Catalog::gBuilder[d] && (Catalog::gSurfT[d] > 0.01f) && (Catalog::gLandRange[d] >= 800.f)
		&& (Catalog::gHealth[d] <= 800.f) && (Catalog::gHealth[d] <= Catalog::gCostM[d] * 1.2f);
}

float PsClamp(float x, float lo, float hi) { return (x < lo) ? lo : ((x > hi) ? hi : x); }

// a unit is long or fast against its own tier and domain: a T1 rocket bot against T1 land units, not a T3 gun or a ship
int PsTier(int d)
{
	return DefTier(d) + ((Catalog::gFloater[d] || Catalog::gSub[d]) ? 4 : 0);
}

uint PsN() { return uint(Catalog::gDefCount + 1); }

float PsFit(int s, int d)
{
	if ((s < 0) || (s >= ST_N) || (d <= 0) || (uint(d) >= PsN()) || (gPsFit.length() < uint(ST_N) * PsN()))
		return 0.f;
	return gPsFit[uint(s) * PsN() + uint(d)];
}

float PsSpeedAxis(int d)
{
	return ((d > 0) && (uint(d) < gPsSpd.length())) ? gPsSpd[d] : 0.f;
}

bool PsFitsReady()
{
	if (gPsFit.length() == uint(ST_N) * PsN())
		return true;
	LineMeans();
	if ((gLMeanHpm <= 0.f) || (gLMeanR <= 0.f))
		return false;
	const uint n = PsN();
	array<float> spdSum(8, 0.f), rngSum(8, 0.f), tierN(8, 0.f);
	for (uint u = 1; u < n; ++u) {
		const int d = int(u);
		if (Catalog::gAvailable[d] && LineCombat(d) && !Catalog::gFlyer[d] && Producible(d)) {
			const int t = PsTier(d);
			spdSum[t] += Catalog::gSpeed[d];
			rngSum[t] += ClassRange(d);
			tierN[t] += 1.f;
		}
	}
	gPsSpd.resize(n);
	gPsFit.resize(uint(ST_N) * n);
	for (uint i = 0; i < gPsFit.length(); ++i)
		gPsFit[i] = 0.f;
	for (uint u = 1; u < n; ++u) {
		const int d = int(u);
		gPsSpd[d] = 0.f;
		if (!Catalog::gAvailable[d])
			continue;
		const bool combat = LineCombat(d);
		const bool ground = combat && !Catalog::gFlyer[d];
		const int sc = Catalog::gMobile[d] ? -1 : SuperClassOf(d);
		const int t = PsTier(d);
		if (ground && (spdSum[t] > 0.f))
			gPsSpd[d] = PsClamp(Catalog::gSpeed[d] * tierN[t] / spdSum[t] - 1.f, -1.f, 1.f);
		if (ground && (rngSum[t] > 0.f))
			gPsFit[ST_ARTY * n + u] = PsClamp(2.f * (ClassRange(d) * tierN[t] / rngSum[t] - 1.f), 0.f, 1.f);
		if (sc == SC_LRPC)
			gPsFit[ST_ARTY * n + u] = 1.f;
		if (PsIsSniper(d) || (Catalog::gJammer[d] && !Catalog::gBuilder[d]))
			gPsFit[ST_STEALTH * n + u] = 1.f;
		if (combat && Catalog::gFlyer[d])
			gPsFit[ST_AIR * n + u] = 1.f;
		if (ground)
			gPsFit[ST_FAST * n + u] = PsClamp(2.f * gPsSpd[d], 0.f, 1.f);
		if ((combat && PsGantryMade(d)) || (sc == SC_GANTRY))
			gPsFit[ST_T3 * n + u] = 1.f;
		if ((sc == SC_SILO) || (sc == SC_TACTICAL) || (sc == SC_JUNO))
			gPsFit[ST_NUKE * n + u] = 1.f;
		// SHIELDS ARE AN AFFINITY FOR SHIELD GENERATORS AND A STRONG DEFENSIVE LAYER (his 11-01; no faction has a
		// mobile shield, so the style was never drawn): the domes fully, armed static defence and tanks half
		if (Catalog::gShield[d] && !Catalog::gFlyer[d] && !Catalog::gBuilder[d])
			gPsFit[ST_SHIELD * n + u] = 1.f;
		else if (!Catalog::gMobile[d] && (Catalog::gMaxRange[d] > 1.f) && (Catalog::gBuildsList[d].length() == 0)
				&& (Catalog::gPower[d] > 1.f))
			gPsFit[ST_SHIELD * n + u] = 0.5f;
		else if (ground && (LineClassOf(d) == LC_TANK))
			gPsFit[ST_SHIELD * n + u] = 0.5f;
		if (PsIsScout(d) || (!Catalog::gMobile[d] && Catalog::gRadar[d] && (Catalog::gBuildsList[d].length() == 0)
				&& !Catalog::gAntiNuke[d] && (Catalog::gMaxRange[d] <= 1.f)))
			gPsFit[ST_SCOUT * n + u] = 1.f;
	}
	return true;
}

// a style is open when something its key fit names is in our own build tree and the game allows it
int PsAvailMask()
{
	int mask = 1 << ST_BALANCED;
	const uint n = PsN();
	for (int s = 1; s < ST_N; ++s) {
		for (uint u = 1; u < n; ++u) {
			const int d = int(u);
			if ((PsFit(s, d) < 0.5f) || !Producible(d) || PsBlocked(d))
				continue;
			if ((s == ST_STEALTH) && !PsIsSniper(d))
				continue;
			if ((s == ST_T3) && !IsGantryDef(d))
				continue;
			if ((s == ST_NUKE) && (SuperClassOf(d) == SC_JUNO))
				continue;
			if ((s == ST_SHIELD) && !Catalog::gShield[d])
				continue;
			if ((s == ST_SCOUT) && !Catalog::gMobile[d])
				continue;
			mask |= 1 << s;
			break;
		}
	}
	return mask;
}

// the plan already carries this lean: no second copy on top of it
bool PsPlanCovers(int d)
{
	if ((gPlan == NG_AIR) && Catalog::gFlyer[d] && Catalog::gMobile[d])
		return true;
	if (Catalog::gMobile[d])
		return false;
	const int sc = SuperClassOf(d);
	return (sc >= 0) && (PlanMul(sc) > 1.f);
}

float PsLean(float fit)
{
	return (fit > 0.f) ? pow(STYLE_AMP, gStyleC * fit) : 1.f;
}

float PsUnitLean(int d)
{
	if ((gStyle <= ST_BALANCED) || PsPlanCovers(d))
		return 1.f;
	return PsLean(PsFit(gStyle, d));
}

float PsSuperLean(int d)
{
	return PsUnitLean(d);
}

float PsSenseLean(int d)
{
	return PsUnitLean(d);
}

float PsTechLean()
{
	return ((gStyle == ST_T3) || (gStyle == ST_NUKE)) ? PsLean(0.5f) : 1.f;
}

float PsArmyLean()
{
	return (gStyle == ST_FAST) ? pow(PERS_PRESSURE, gStyleC) : 1.f;
}

float PsScoutCapLean()
{
	return (gStyle == ST_SCOUT) ? PsLean(1.f) : 1.f;
}

float PsLineLean(int cls)
{
	if ((gStyle == ST_ARTY) && (cls == LC_REACH))
		return PsLean(1.f);
	if ((gStyle == ST_SHIELD) && (cls == LC_TANK))
		return PsLean(0.5f);
	return 1.f;
}

// a plant by the best lean among what it fields, over the mean of every plant we can raise: plants against each
// other, not the labs against the economy
float PsPlantLean(int p)
{
	if ((gStyle <= ST_BALANCED) || !Catalog::ValidId(p))
		return 1.f;
	const int key = gStyleGen * 1000 + int(gStyleC * 100.f) * 10 + gPlan;
	if ((key != gPsPlantKey) || (gPsPlant.length() != PsN())) {
		gPsPlantKey = key;
		gPsPlant.resize(PsN());
		float sum = 0.f;
		int cnt = 0;
		for (uint u = 1; u < PsN(); ++u) {
			const int q = int(u);
			gPsPlant[u] = 0.f;
			if (Catalog::gMobile[q] || !Catalog::gAvailable[q] || (Catalog::gBuildsList[q].length() == 0) || !Producible(q))
				continue;
			float best = 0.f;
			const array<int>@ pr = Catalog::gBuildsList[q];
			for (uint i = 0; i < pr.length(); ++i) {
				const int d = pr[i];
				if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gBuilder[d])
					continue;
				const float l = PsUnitLean(d);
				if (l > best)
					best = l;
			}
			if (best <= 0.f)
				continue;
			gPsPlant[u] = best;
			sum += best;
			++cnt;
		}
		const float mean = (cnt > 0) ? (sum / float(cnt)) : 1.f;
		for (uint u = 1; u < PsN(); ++u)
			gPsPlant[u] = (gPsPlant[u] > 0.f) ? (gPsPlant[u] / mean) : 1.f;
	}
	return gPsPlant[p];
}

void PersNoteLoss(int d, float costM)
{
	if (!PersOn())
		return;
	gPsLostAll += costM;
	if (PsUnitLean(d) > 1.05f)
		gPsLostStyle += costM;
}

int PsLeader()
{
	for (int t = 0; t < 100; ++t) {
		const float seen = ai.GetTeamBoard(PB_SEEN + t, 0.f);
		if ((seen > 0.f) && (float(ai.frame) - (seen - 1.f) <= float(PS_FRESH)))
			return t;
	}
	return -1;
}

int PsDraw(int avoid, int used, int mask)
{
	float tot = 0.f;
	for (int s = 0; s < ST_N; ++s)
		if (((mask & (1 << s)) != 0) && (s != avoid) && ((used & (1 << s)) == 0))
			tot += ST_DRAW_W[s];
	if (tot <= 0.f) {
		used = 0;
		for (int s = 0; s < ST_N; ++s)
			if (((mask & (1 << s)) != 0) && (s != avoid))
				tot += ST_DRAW_W[s];
	}
	if (tot <= 0.f)
		return ST_BALANCED;
	float roll = float(AiRandom(0, 1000000)) / 1000000.f * tot;
	for (int s = 0; s < ST_N; ++s) {
		if (((mask & (1 << s)) == 0) || (s == avoid) || ((used & (1 << s)) != 0))
			continue;
		roll -= ST_DRAW_W[s];
		if (roll <= 0.f)
			return s;
	}
	return ST_BALANCED;
}

void PsSetStyle(int s, int used, float ra0, const string &in why)
{
	const int gen = int(ai.GetTeamBoard(PB_GEN, 0.f)) + 1;
	ai.SetTeamBoard(PB_STYLE, float(s + 1));
	ai.SetTeamBoard(PB_GEN, float(gen));
	ai.SetTeamBoard(PB_C, 1.f);
	ai.SetTeamBoard(PB_RA0, ra0);
	ai.SetTeamBoard(PB_USED, float(used | (1 << s)));
	ai.SetTeamBoard(PB_AT, float(ai.frame));
	ai.SetTeamBoard(PB_BAD, 0.f);
	AiLog("apex: persona-team t=" + ai.teamId + " ally=" + ai.allyTeamId + " style=" + StName(s) + " gen=" + gen
		+ " why=" + why + " used=" + (used | (1 << s)));
	const int plan = ST_PLAN[s];
	if ((ai.GetTunable("apex_plan_force", TUNE_PLAN_FORCE) < 0.f) && !PlanFromPriceOn()) {
		if (plan >= 0)
			PlanSet(plan, "team style");
		else if ((gPlan != NG_NORMAL) && (gen > 1))
			PlanSet(NG_NORMAL, "team style");
	}
}

void PsPublish()
{
	ai.SetTeamBoard(PB_SEEN + ai.teamId, float(ai.frame + 1));
	if (gPsAvail < 0) {
		if (ai.frame < SECOND || !PsFitsReady())
			return;
		gPsAvail = PsAvailMask();
		ai.SetTeamBoard(PB_AVAIL + ai.teamId, float(gPsAvail + 1));
		ai.SetTeamBoard(PB_FORCE + ai.teamId, float(PsForce() + 1));
	}
	ai.SetTeamBoard(PB_KILL + ai.teamId, Military::gKillAll);
	ai.SetTeamBoard(PB_LOSS + ai.teamId, Military::gLossAll);
	ai.SetTeamBoard(PB_INC + ai.teamId, Eco::MInc());
	if (ai.frame < gPsPubAt + 10 * SECOND)
		return;
	gPsPubAt = ai.frame;
	float air = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (Catalog::ValidId(d) && Catalog::gFlyer[d] && LineCombat(d))
			air += float(gOwnCount[d]) * Catalog::gCostM[d];
	}
	ai.SetTeamBoard(PB_AIRM + ai.teamId, air);
}

void PsLead()
{
	if ((PsLeader() != ai.teamId) || (gPsAvail < 0))
		return;
	const int cur = int(ai.GetTeamBoard(PB_STYLE, 0.f)) - 1;
	int mask = -1, force = -1;
	float kill = 0.f, loss = 0.f, inc = 0.f, air = 0.f;
	for (int t = 0; t < 100; ++t) {
		const float seen = ai.GetTeamBoard(PB_SEEN + t, 0.f);
		if ((seen <= 0.f) || (float(ai.frame) - (seen - 1.f) > float(PS_FRESH)))
			continue;
		const int av = int(ai.GetTeamBoard(PB_AVAIL + t, 0.f)) - 1;
		if (av >= 0)
			mask &= av;
		const int f = int(ai.GetTeamBoard(PB_FORCE + t, 0.f)) - 1;
		if ((force < 0) && (f >= 0))
			force = f;
		kill += ai.GetTeamBoard(PB_KILL + t, 0.f);
		loss += ai.GetTeamBoard(PB_LOSS + t, 0.f);
		inc += ai.GetTeamBoard(PB_INC + t, 0.f);
		air += ai.GetTeamBoard(PB_AIRM + t, 0.f);
	}
	if (mask < 0)
		mask = 1 << ST_BALANCED;
	const float k = inc * ai.GetTunable("apex_trade_vol", TUNE_TRADE_VOL);
	const float ra = (k > 0.f) ? ((Military::OurArmyM() + air + k) / (Military::FoeArmyM() + k)) : 1.f;
	if (cur < 0) {
		if (ai.frame < PS_DRAW_AT)
			return;
		gPsLeadAt = ai.frame;
		if (force >= 0)
			PsSetStyle(force, 0, 1.f, "force" + (((mask & (1 << force)) == 0) ? "-unavailable" : ""));
		else
			PsSetStyle(PsDraw(-1, 0, mask), 0, 1.f, "draw mask=" + mask);
		return;
	}
	if (ai.frame < gPsLeadAt + MINUTE)
		return;
	gPsLeadAt = ai.frame;
	if (force >= 0)
		return;
	// the army reading is what the style did to the balance it inherited, not the balance itself
	const float rt = (k > 0.f) ? ((kill + k) / (loss + k)) : 1.f;
	const float ra0 = ai.GetTeamBoard(PB_RA0, 1.f);
	const float rr = ra / ((ra0 > 0.f) ? ra0 : 1.f);
	const float r = (rr < rt) ? rr : rt;
	// A STYLE GETS A REAL CHANCE (his 11-01: "hold longer"; teams went through 4-5 styles in 30 min against BARb +50):
	// no fading in its first PS_HOLD, and after that only on the PS_BAD_RUN-th bad minute in a row; recovery any time
	int bad = int(ai.GetTeamBoard(PB_BAD, 0.f));
	bad = (r < 1.f) ? (bad + 1) : 0;
	ai.SetTeamBoard(PB_BAD, float(bad));
	const bool held = float(ai.frame) - ai.GetTeamBoard(PB_AT, 0.f) >= float(PS_HOLD);
	float c = ai.GetTeamBoard(PB_C, 1.f);
	if ((r >= 1.f) || (held && (bad >= PS_BAD_RUN)))
		c *= r;
	if (c > 1.f)
		c = 1.f;
	ai.SetTeamBoard(PB_C, c);
	ai.SetTeamBoard(PB_R, r);
	ai.SetTeamBoard(PB_RT, rt);
	ai.SetTeamBoard(PB_RA, rr);
	if (pow(STYLE_AMP, c) > PERS_SEAT_AMP)
		return;
	const int used = int(ai.GetTeamBoard(PB_USED, 0.f));
	PsSetStyle(PsDraw(cur, used, mask), used, ra, "fade from " + StName(cur) + " c=" + NnF(c, 2) + " trade=" + NnF(rt, 2)
		+ " army=" + NnF(ra, 2) + "/" + NnF(ra0, 2));
}

void PsFollow()
{
	const int gen = int(ai.GetTeamBoard(PB_GEN, 0.f));
	if (gen <= 0)
		return;
	const float c = ai.GetTeamBoard(PB_C, 1.f);
	if (gen != gStyleGen) {
		gStyleGen = gen;
		gStyle = int(ai.GetTeamBoard(PB_STYLE, 1.f)) - 1;
		gStyleC = c;
		gStyleCLogged = c;
		gPsLostStyle = 0.f;
		PersSeatDraw(((gStyle >= 0) && (gStyle < ST_N)) ? ST_KEY[gStyle] : -1);
		AiLog("apex: persona t=" + ai.teamId + " style=" + StName(gStyle) + " gen=" + gen + " c=" + NnF(c, 2)
			+ " plan=" + NgName(gPlan) + " avail=" + gPsAvail + " " + PersSeatLine());
		PsFitLog();
		return;
	}
	gStyleC = c;
	if (abs(c - gStyleCLogged) >= 0.05f) {
		gStyleCLogged = c;
		AiLog("apex: persona t=" + ai.teamId + " style=" + StName(gStyle) + " gen=" + gen + " c=" + NnF(c, 2)
			+ " r=" + NnF(ai.GetTeamBoard(PB_R, 1.f), 2) + " trade=" + NnF(ai.GetTeamBoard(PB_RT, 1.f), 2)
			+ " army=" + NnF(ai.GetTeamBoard(PB_RA, 1.f), 2) + " plan=" + NgName(gPlan));
	}
}

// what the style leans in our own tree, strongest first
void PsFitLog()
{
	array<int> ds;
	array<float> ls;
	for (uint u = 1; u < PsN(); ++u) {
		const int d = int(u);
		if (!Catalog::gAvailable[d] || !Producible(d))
			continue;
		const float l = PsUnitLean(d);
		if (l <= 1.05f)
			continue;
		uint at = 0;
		while ((at < ls.length()) && (ls[at] >= l))
			++at;
		ds.insertAt(at, d);
		ls.insertAt(at, l);
	}
	string s = "";
	for (uint i = 0; (i < ds.length()) && (i < 16); ++i)
		s += " " + Catalog::Def(ds[i]).GetName() + "=" + NnF(ls[i], 2);
	AiLog("apex: persona-fit t=" + ai.teamId + " style=" + StName(gStyle) + " n=" + ds.length() + s);
}

void PsStat()
{
	if (ai.frame < gPsStatAt + MINUTE)
		return;
	gPsStatAt = ai.frame;
	float dealt = 0.f, spent = 0.f;
	for (uint u = 1; u < PsN(); ++u) {
		const int d = int(u);
		if (!Catalog::gAvailable[d] || (PsUnitLean(d) <= 1.05f))
			continue;
		const CCircuitDef@ cd = Catalog::Def(d);
		dealt += ai.YieldDealt(cd, true);
		spent += ai.YieldSpent(cd, true);
	}
	AiLog("apex: persona-stat t=" + ai.teamId + " style=" + StName(gStyle) + " gen=" + gStyleGen + " c=" + NnF(gStyleC, 2)
		+ " r=" + NnF(ai.GetTeamBoard(PB_R, 1.f), 2) + " lead=" + PsLeader()
		+ " kill=" + int(Military::gKillAll) + " loss=" + int(Military::gLossAll)
		+ " styleDealt=" + int(dealt) + " styleSpent=" + int(spent) + " styleLost=" + int(gPsLostStyle) + " lostAll=" + int(gPsLostAll)
		+ " ourArmy=" + int(Military::OurArmyM()) + " foeArmy=" + int(Military::FoeArmyM())
		+ " ord=" + gPsOrdLean + "/" + gPsOrd + " pick=" + gPsPickLean + "/" + gPsPick
		+ " top=" + gPsTopUp + "+/" + gPsTopDown + "-/" + gPsTop + " plan=" + NgName(gPlan));
}

void PersTick()
{
	if (!PersOn())
		return;
	PsPublish();
	PsLead();
	PsFollow();
	if (gStyleGen > 0)
		PsStat();
}

}  // namespace Market
