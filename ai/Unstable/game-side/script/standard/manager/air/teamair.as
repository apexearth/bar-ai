namespace Air {

// THE TEAM AIR PLAN (his 2026-10-16: when we are ahead, the whole team builds air
// behind its lines and strikes at once). The leader prices AIR against NORMAL
// every 30 s on what we have seen; under AIR every seat holds its strike planes
// at one rally behind our lines and launches on the same frame, at the same
// target, once the gathered wing finishes it through the AA we know of.

const int TAB_PHASE = 6000, TAB_OP = 6001, TAB_RX = 6002, TAB_RZ = 6003;
const int TAB_TX = 6004, TAB_TZ = 6005, TAB_TR = 6006, TAB_VERDICT = 6007, TAB_FLIP = 6008;
const int TAB_NEEDM = 6009, TAB_NET = 6010, TAB_SUMM = 6011, TAB_SUMK = 6012, TAB_SUML = 6013;
const int TAB_LAUNCH_AT = 6014, TAB_END2 = 6015, TAB_NEEDN = 6016, TAB_PROJN = 6017, TAB_STRIKES = 6018;
const int TAB_TERMS = 6020;
const int TAB_NTERMS = 18;
const int TAS_AT = 6100, TAS_N = 6200, TAS_HP = 6300, TAS_DPS = 6400, TAS_COST = 6500, TAS_SPD = 6600;
const int TAS_AIRM = 6700, TAS_OUT = 6800, TAS_SENT = 6900, TAS_LOST = 7000, TAS_KILL = 7100;
const int TAS_PLANT = 7200, TAS_INC = 7300, TAS_ESC = 7400, TAS_OP = 7500, TAS_ECO = 7600;
const int TA_PH_NONE = 0, TA_PH_GATHER = 1, TA_PH_STRIKE = 2;
const array<string> TA_PH_NAMES = {"NONE", "GATHER", "STRIKE"};

array<Id> gTairSent;       // what this seat launched on the op it flew
array<Id> gTairGun;        // its gunships still out on that op
int gTairGunSent = 0;
int gTairOpFlown = 0;
float gTairSentM = 0.f, gTairLostM = 0.f, gTairKillM = 0.f;
int gTairNextAt = 0, gTairEvalAt = 0, gTairPlanAt = 0, gTairLogAt = 0;
int gTairGathN = 0;
float gTairGathHp = 0.f, gTairGathDps = 0.f, gTairGathCost = 0.f, gTairGathSpd = 0.f;
float gTairGathGunM = 0.f, gTairEscDps = 0.f, gTairAirM = 0.f, gTairOutM = 0.f, gTairOutGunM = 0.f;
float gTairAirS = 0.f;
int gTairLaunches = 0, gTairPulled = 0, gTairMoved = 0;

// the team, summed from the seats' board rows once per frame
int gTairSumAt = -1;
int gTairSeats = 0, gTairPlants = 0;
float gTairTInc = 0.f, gTairTAirM = 0.f, gTairTEco = 0.f, gTairTN = 0.f, gTairTHp = 0.f, gTairTDps = 0.f;
float gTairTCost = 0.f, gTairTSpd = 0.f, gTairTEsc = 0.f;

// what we have seen of them, split by what it shoots at
int gTairSplitAt = -1;
float gTairFoeAAM = 0.f, gTairFoeFtrM = 0.f, gTairFoeDefM = 0.f, gTairFoeArmyM = 0.f, gTairFoeEcoM = 0.f;
array<AIFloat3> gTairMobP;
array<float> gTairMobM;
array<float> gTairMobH;

array<float> gTairRetV;
array<int> gTairRetAt;

bool TairSwitch()
{
	return ai.GetTunable("apex_team_air", TUNE_TEAM_AIR) > 0.f;
}

bool TairOn()
{
	return TairSwitch() && (Market::gPlan == Market::NG_AIR);
}

int TairPhase()
{
	return int(ai.GetTeamBoard(TAB_PHASE, 0.f));
}

bool TairStrikeDef(int d)
{
	return (IsBomberDef(d) && !IsAtomicDef(d)) || IsGunshipDef(d);
}

// The plan rule's choice for the team, from the leader's last comparison.
int TairRulePlan()
{
	return (TairSwitch() && (ai.GetTeamBoard(TAB_VERDICT, 0.f) > 0.f)) ? Market::NG_AIR : Market::NG_NORMAL;
}

AIFloat3 TairRally()
{
	AIFloat3 p(ai.GetTeamBoard(TAB_RX, -1.f), 0.f, ai.GetTeamBoard(TAB_RZ, -1.f));
	if ((p.x < 0.f) || !OnMap(p))
		return Builder::gHomePos;
	p.y = ai.GetElevationAt(p);
	return p;
}

AIFloat3 TairTargetPos(float &out r)
{
	r = ai.GetTeamBoard(TAB_TR, 0.f);
	AIFloat3 p(ai.GetTeamBoard(TAB_TX, -1.f), 0.f, ai.GetTeamBoard(TAB_TZ, -1.f));
	if (p.x >= 0.f)
		p.y = ai.GetElevationAt(p);
	return p;
}

bool TairSeatFresh(int t)
{
	return float(ai.frame) - ai.GetTeamBoard(TAS_AT + t, -1e9f) < float(15 * SECOND);
}

bool TairHolds(CCircuitUnit@ unit)
{
	return TairOn() && !gDefendHome && (TairPhase() != TA_PH_NONE)
		&& IsGunshipDef(int(unit.circuitDef.id)) && !InList(gTairGun, unit.id);
}

void TairTeamSum()
{
	if (gTairSumAt == ai.frame)
		return;
	gTairSumAt = ai.frame;
	gTairSeats = 0; gTairPlants = 0;
	gTairTInc = 0.f; gTairTAirM = 0.f; gTairTEco = 0.f; gTairTN = 0.f; gTairTHp = 0.f;
	gTairTDps = 0.f; gTairTCost = 0.f; gTairTSpd = 0.f; gTairTEsc = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (!TairSeatFresh(t))
			continue;
		++gTairSeats;
		if (ai.GetTeamBoard(TAS_PLANT + t, 0.f) > 0.f)
			++gTairPlants;
		gTairTInc += ai.GetTeamBoard(TAS_INC + t, 0.f);
		gTairTAirM += ai.GetTeamBoard(TAS_AIRM + t, 0.f);
		gTairTEco += ai.GetTeamBoard(TAS_ECO + t, 0.f);
		gTairTEsc += ai.GetTeamBoard(TAS_ESC + t, 0.f);
		const float n = ai.GetTeamBoard(TAS_N + t, 0.f);
		if (n <= 0.f)
			continue;
		gTairTN += n;
		gTairTHp += ai.GetTeamBoard(TAS_HP + t, 0.f);
		gTairTDps += ai.GetTeamBoard(TAS_DPS + t, 0.f);
		gTairTCost += ai.GetTeamBoard(TAS_COST + t, 0.f);
		const float s = ai.GetTeamBoard(TAS_SPD + t, 0.f);
		if ((s > 0.f) && ((gTairTSpd <= 0.f) || (s < gTairTSpd)))
			gTairTSpd = s;
	}
}

void TairFoeSplit()
{
	if (gTairSplitAt == ai.frame)
		return;
	gTairSplitAt = ai.frame;
	gTairFoeAAM = 0.f; gTairFoeFtrM = 0.f; gTairFoeDefM = 0.f; gTairFoeArmyM = 0.f; gTairFoeEcoM = 0.f;
	gTairMobP.resize(0); gTairMobM.resize(0); gTairMobH.resize(0);
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const float m = Catalog::gCostM[d];
		const float t = Catalog::gAirT[d] + Catalog::gSurfT[d] + Catalog::gWaterT[d];
		if ((Catalog::gMaxRange[d] > 0.f) && (Catalog::gDps[d] > 0.f) && (t > 0.f)) {
			const float airS = Catalog::gAirT[d] / t;
			const float gndS = 1.f - airS;
			if (Catalog::gFlyer[d] && Catalog::gMobile[d]) {
				gTairFoeFtrM += m * airS;
				gTairFoeArmyM += m * gndS;
			} else if (Catalog::gMobile[d]) {
				gTairFoeAAM += m * airS;
				gTairFoeArmyM += m * gndS;
				gTairMobP.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
				gTairMobM.insertLast(m);
				gTairMobH.insertLast(Catalog::gHealth[d]);
			} else {
				gTairFoeAAM += m * airS;
				gTairFoeDefM += m * gndS;
			}
		} else if (!Catalog::gMobile[d]
			&& ((Catalog::gExtractsM[d] > 0.f) || (Catalog::gMakeE[d] > 0.f) || (Catalog::gMakeM[d] > 0.f)
				|| (Catalog::gConvCapacity[d] > 0.f) || (Catalog::gBuildPower[d] > 0.f))) {
			gTairFoeEcoM += m;
		}
	}
}

// Square-law ground fight of G against E, q our measured kill per metal lost.
// The winner's survivors go on into the loser's economy, metal for metal.
float TairGround(float G, float E, float q, float foeEco, float ourEco)
{
	if (G < 0.f)
		G = 0.f;
	if (E <= 0.f)
		return (G < foeEco) ? G : foeEco;
	if (q <= 0.f)
		return -(G + ((E < ourEco) ? E : ourEco));
	if (q * G * G >= E * E) {
		const float gs = sqrt(G * G - E * E / q);
		return E + ((gs < foeEco) ? gs : foeEco) - (G - gs);
	}
	const float es = sqrt(E * E - q * G * G);
	return (E - es) - (G + ((es < ourEco) ? es : ourEco));
}

// One sortie of n planes from `from`: cell after cell, best net first, the wing
// thinning by what each cell costs it. Only seen buildings and AA.
float TairSortie(const AIFloat3& in from, int n, float h, float dps1, float cost1, float spd, float esc)
{
	if ((n <= 0) || (spd <= 0.f) || (h <= 0.f) || (dps1 <= 0.f))
		return 0.f;
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	array<NaCand@> cs;
	NaCands(r, cs);
	const uint m = cs.length();
	if (m == 0)
		return 0.f;
	array<float> pAA(m), fAA(m), fly(m);
	for (uint i = 0; i < m; ++i) {
		fly[i] = from.distance2D(cs[i].at) / spd;
		pAA[i] = NaPathAA(from, cs[i].at);
		const float f = NaFighterAA(cs[i].at, fly[i]) - esc;
		fAA[i] = (f > 0.f) ? f : 0.f;
	}
	gNaObsDmg = -1.f;
	gNaObsLost = -1.f;
	array<bool> used(m, false);
	float N = float(n), total = 0.f;
	for (uint pass = 0; pass < m; ++pass) {
		int bi = -1;
		float bv = 0.f, bLoss = 0.f;
		for (uint i = 0; i < m; ++i) {
			if (used[i])
				continue;
			NaPrice@ p = NaPrice();
			const float v = NaEval(cs[i], pAA[i], fAA[i], int(N), h, dps1, cost1, spd, fly[i], true, -1.f, p);
			if ((bi < 0) || (v > bv)) {
				bi = int(i);
				bv = v;
				bLoss = p.lossN;
			}
		}
		if ((bi < 0) || (bv <= 0.f))
			break;
		total += bv;
		N -= bLoss;
		for (uint i = 0; i < m; ++i) {
			if (cs[i].at.distance2D(cs[uint(bi)].at) <= r)
				used[i] = true;
		}
		if (N < 1.f)
			break;
	}
	return total;
}

// The plane the wing is made of: the team's gathered average, else the bomber we would buy.
bool TairPlane(float &out h, float &out dps1, float &out cost1, float &out spd)
{
	TairTeamSum();
	if ((gTairTN > 0.f) && (gTairTSpd > 0.f)) {
		h = gTairTHp / gTairTN;
		dps1 = gTairTDps / gTairTN;
		cost1 = gTairTCost / gTairTN;
		spd = gTairTSpd;
		return (h > 0.f) && (dps1 > 0.f) && (cost1 > 0.f);
	}
	const int b = BuyableBomberDef();
	if (b <= 0)
		return false;
	h = Catalog::gHealth[b];
	dps1 = Catalog::gSurfDps[b];
	cost1 = Catalog::gCostM[b];
	spd = Catalog::gSpeed[b];
	return (h > 0.f) && (dps1 > 0.f) && (cost1 > 0.f) && (spd > 0.f);
}

// What an air army of A metal nets in one sortie, the model blended with the
// strikes this plan has scored, weighted by the metal each speaks for.
float TairAirNet(float A, const AIFloat3& in from)
{
	float h, dps1, cost1, spd;
	if ((A <= 0.f) || !TairPlane(h, dps1, cost1, spd))
		return 0.f;
	const float model = TairSortie(from, int(A / cost1), h, dps1, cost1, spd, gTairTEsc);
	const float sm = ai.GetTeamBoard(TAB_SUMM, 0.f);
	if (sm <= 0.f)
		return model;
	const float meas = (ai.GetTeamBoard(TAB_SUMK, 0.f) - ai.GetTeamBoard(TAB_SUML, 0.f)) / sm;
	const float w = sm / (sm + A);
	return (1.f - w) * model + w * meas * A;
}

void TairPlanEval()
{
	TairTeamSum();
	const AIFloat3 foe = NaFoe();
	NaSnapEnemy(OnMap(foe) ? foe : Builder::gHomePos);
	TairFoeSplit();
	const AIFloat3 from = TairRally();
	const float S = gTairTInc * float(Market::NG_HOLD_S) * Brain::TargetShare(Brain::ARMY);
	const float plantM = (gPlant1 !is null) ? Catalog::gCostM[int(gPlant1.id)] : 0.f;
	const int missing = gTairSeats - gTairPlants;
	float airS = S - float((missing > 0) ? missing : 0) * plantM;
	if (airS < 0.f)
		airS = 0.f;
	gTairAirS = airS;
	float G0 = Military::TeamArmyCost() - gTairTAirM;
	if (G0 < 0.f)
		G0 = 0.f;
	const float E = gTairFoeArmyM + gTairFoeDefM;
	const float q = Military::TradeRatio();
	const float gnd0 = TairGround(G0, E, q, gTairFoeEcoM, gTairTEco);
	const float gndS = TairGround(G0 + S, E, q, gTairFoeEcoM, gTairTEco);
	const float air0 = TairAirNet(gTairTAirM, from);
	const float air1 = TairAirNet(gTairTAirM + airS, from);
	const float vAir = gnd0 + air1;
	const float vNorm = gndS + air0;
	const bool airWins = vAir > vNorm;
	ai.SetTeamBoard(TAB_VERDICT, airWins ? 1.f : 0.f);
	array<float> terms = {vAir, vNorm, gnd0, gndS, air1, air0, S, airS, G0, E, q,
		gTairFoeAAM, gTairFoeFtrM, gTairFoeDefM, gTairFoeArmyM, gTairFoeEcoM, gTairTEco, gTairTAirM};
	for (uint i = 0; i < terms.length(); ++i)
		ai.SetTeamBoard(TAB_TERMS + int(i), terms[i]);
	// the plan is written only over NORMAL or AIR, never an explorer's, never a forced one
	const int cur = Market::gPlan;
	const bool explorer = (int(ai.GetTeamBoard(Market::BOARD_PLAN_LEAD, 0.f)) - 1) >= 0;
	const bool forced = ai.GetTunable("apex_plan_force", TUNE_PLAN_FORCE) >= 0.f;
	if (explorer || forced || ((cur != Market::NG_NORMAL) && (cur != Market::NG_AIR)))
		return;
	const int want = airWins ? Market::NG_AIR : Market::NG_NORMAL;
	if (want == cur) {
		ai.SetTeamBoard(TAB_FLIP, 0.f);
		if (cur == Market::NG_AIR)
			Market::PlanSet(cur, "team air renews");
		return;
	}
	// two reads running before the plan moves: one noisy sample changes nothing
	const float flips = ai.GetTeamBoard(TAB_FLIP, 0.f) + 1.f;
	ai.SetTeamBoard(TAB_FLIP, flips);
	if (flips < 2.f)
		return;
	ai.SetTeamBoard(TAB_FLIP, 0.f);
	Market::PlanSet(want, "team air " + int(vAir) + " vs normal " + int(vNorm));
	AiLog(Factory::T() + "apex: teamair-plan t=" + ai.teamId + " -> " + Market::NgName(want)
		+ " vAir=" + int(vAir) + " (gnd " + int(gnd0) + " + air " + int(air1) + ")"
		+ " vNorm=" + int(vNorm) + " (gnd " + int(gndS) + " + air " + int(air0) + ")"
		+ " S=" + int(S) + " airS=" + int(airS) + " G0=" + int(G0) + " E=" + int(E) + " q=" + Market::NnF(q, 2)
		+ " foeAA=" + int(gTairFoeAAM) + " foeFtr=" + int(gTairFoeFtrM) + " foeDef=" + int(gTairFoeDefM)
		+ " foeArmy=" + int(gTairFoeArmyM) + " foeEco=" + int(gTairFoeEcoM)
		+ " ledger=" + int(ai.GetTeamBoard(TAB_SUMM, 0.f)) + "/" + int(ai.GetTeamBoard(TAB_SUMK, 0.f))
		+ "/" + int(ai.GetTeamBoard(TAB_SUML, 0.f)));
}

// Behind our lines: from the team's home centroid, away from their front, half
// the way to the map edge; the centroid itself when that ground is contested.
AIFloat3 TairRallyCalc()
{
	float hx = 0.f, hz = 0.f, hn = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (Market::TaFresh(t) && (ai.GetTeamBoard(Market::BOARD_TA_HOMEX + t, -1.f) >= 0.f)) {
			hx += ai.GetTeamBoard(Market::BOARD_TA_HOMEX + t, 0.f);
			hz += ai.GetTeamBoard(Market::BOARD_TA_HOMEZ + t, 0.f);
			hn += 1.f;
		}
	}
	if (hn <= 0.f)
		return Builder::gHomePos;
	AIFloat3 c(hx / hn, 0.f, hz / hn);
	c.y = ai.GetElevationAt(c);
	const AIFloat3 foe = NaFoe();
	if (!OnMap(foe) || ((foe.x == 0.f) && (foe.z == 0.f)))
		return c;
	float dx = c.x - foe.x, dz = c.z - foe.z;
	const float len = sqrt(dx * dx + dz * dz);
	if (len < 1.f)
		return c;
	dx /= len;
	dz /= len;
	const float w = float(AiTerrainWidth()), hgt = float(AiTerrainHeight());
	float edge = 1e9f;
	if (dx > 0.001f) { const float s = (w - c.x) / dx; edge = (s < edge) ? s : edge; }
	if (dx < -0.001f) { const float s = -c.x / dx; edge = (s < edge) ? s : edge; }
	if (dz > 0.001f) { const float s = (hgt - c.z) / dz; edge = (s < edge) ? s : edge; }
	if (dz < -0.001f) { const float s = -c.z / dz; edge = (s < edge) ? s : edge; }
	if (edge >= 1e8f)
		return c;
	AIFloat3 at(c.x + dx * edge * 0.5f, 0.f, c.z + dz * edge * 0.5f);
	at.x = (at.x < 64.f) ? 64.f : ((at.x > w - 64.f) ? w - 64.f : at.x);
	at.z = (at.z < 64.f) ? 64.f : ((at.z > hgt - 64.f) ? hgt - 64.f : at.z);
	at.y = ai.GetElevationAt(at);
	if (!OnMap(at) || (aiMilitaryMgr.GetEnemyInflNear(at, ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R)) > 0.f))
		return c;
	return at;
}

// The target: the cell the projected wing nets most on. The need: the smallest
// wing that finishes it and still comes out ahead through the AA we know of --
// the square law of the race in NaEval. The gathered wing goes when it is that
// big, or when a whole cadence has passed since the last launch (his 10-12).
void TairTargetEval(const AIFloat3& in rally)
{
	float h, dps1, cost1, spd;
	if (!TairPlane(h, dps1, cost1, spd))
		return;
	const AIFloat3 foe = NaFoe();
	NaSnapEnemy(OnMap(foe) ? foe : Builder::gHomePos);
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	array<NaCand@> cs;
	NaCands(r, cs);
	if (cs.length() == 0)
		return;
	gNaObsDmg = -1.f;
	gNaObsLost = -1.f;
	const int nNow = int(gTairTN);
	int nProj = int((gTairTAirM + gTairAirS) / cost1);
	if (nProj < nNow)
		nProj = nNow;
	if (nProj < 1)
		nProj = 1;
	int ti = -1, ni = -1;
	float tv = 0.f, nv = 0.f;
	array<float> pAA(cs.length()), fAA(cs.length()), fly(cs.length());
	for (uint i = 0; i < cs.length(); ++i) {
		fly[i] = rally.distance2D(cs[i].at) / spd;
		pAA[i] = NaPathAA(rally, cs[i].at);
		const float f = NaFighterAA(cs[i].at, fly[i]) - gTairTEsc;
		fAA[i] = (f > 0.f) ? f : 0.f;
		const float v = NaEval(cs[i], pAA[i], fAA[i], nProj, h, dps1, cost1, spd, fly[i], true, -1.f, null);
		if ((ti < 0) || (v > tv)) { ti = int(i); tv = v; }
		if (nNow > 0) {
			const float vn = NaEval(cs[i], pAA[i], fAA[i], nNow, h, dps1, cost1, spd, fly[i], true, -1.f, null);
			if ((ni < 0) || (vn > nv)) { ni = int(i); nv = vn; }
		}
	}
	const uint u = uint(ti);
	int need = -1;
	NaPrice@ p = NaPrice();
	for (int nn = 1; nn <= 1024; nn *= 2) {
		const float v = NaEval(cs[u], pAA[u], fAA[u], nn, h, dps1, cost1, spd, fly[u], true, -1.f, p);
		if ((v <= 0.f) || (p.killF < 1.f))
			continue;
		int lo = (nn > 1) ? nn / 2 + 1 : 1, hi = nn - 1;
		need = nn;
		while (lo <= hi) {
			const int mid = (lo + hi) / 2;
			const float vm = NaEval(cs[u], pAA[u], fAA[u], mid, h, dps1, cost1, spd, fly[u], true, -1.f, p);
			if ((vm > 0.f) && (p.killF >= 1.f)) {
				need = mid;
				hi = mid - 1;
			} else {
				lo = mid + 1;
			}
		}
		break;
	}
	ai.SetTeamBoard(TAB_TX, cs[u].at.x);
	ai.SetTeamBoard(TAB_TZ, cs[u].at.z);
	ai.SetTeamBoard(TAB_TR, r);
	ai.SetTeamBoard(TAB_NEEDN, float(need));
	ai.SetTeamBoard(TAB_NEEDM, float((need > 0) ? need : nProj) * cost1);
	ai.SetTeamBoard(TAB_PROJN, float(nProj));
	ai.SetTeamBoard(TAB_NET, tv);
	if (nNow <= 0)
		return;
	const bool ready = (need > 0) && (nNow >= need);
	const bool late = (float(ai.frame) - ai.GetTeamBoard(TAB_LAUNCH_AT, float(ai.frame))) >= float(AIR_CADENCE);
	if (!ready && !late)
		return;
	uint go = u;
	string why = "need " + need + " <= " + nNow;
	if (!ready) {
		go = uint(ni);
		why = "cadence";
	}
	NaEval(cs[go], pAA[go], fAA[go], nNow, h, dps1, cost1, spd, fly[go], true, -1.f, p);
	const int op = int(ai.GetTeamBoard(TAB_OP, 0.f)) + 1;
	ai.SetTeamBoard(TAB_TX, cs[go].at.x);
	ai.SetTeamBoard(TAB_TZ, cs[go].at.z);
	ai.SetTeamBoard(TAB_NET, p.netM);
	ai.SetTeamBoard(TAB_LAUNCH_AT, float(ai.frame));
	ai.SetTeamBoard(TAB_END2, 0.f);
	ai.SetTeamBoard(TAB_PHASE, float(TA_PH_STRIKE));
	ai.SetTeamBoard(TAB_OP, float(op));
	AiLog(Factory::T() + "apex: teamair-go t=" + ai.teamId + " op=" + op + " (" + why + ") at="
		+ int(cs[go].at.x) + "," + int(cs[go].at.z) + " n=" + nNow + " need=" + need + " proj=" + nProj
		+ " v=" + int(cs[go].v) + " aa=" + int(cs[go].aaT) + " path=" + int(pAA[go]) + " ftr=" + int(fAA[go])
		+ " killF=" + Market::NnF(p.killF, 2) + " lossN=" + Market::NnF(p.lossN, 1) + " net=" + int(p.netM)
		+ " seats=" + gTairSeats);
}

void TairLead()
{
	TairTeamSum();
	if (ai.frame >= gTairPlanAt) {
		gTairPlanAt = ai.frame + 30 * SECOND;
		TairPlanEval();
	}
	const int ph = TairPhase();
	if (!TairOn()) {
		if (ph != TA_PH_NONE) {
			ai.SetTeamBoard(TAB_PHASE, float(TA_PH_NONE));
			AiLog(Factory::T() + "apex: teamair-phase t=" + ai.teamId + " NONE (plan " + Market::NgName(Market::gPlan) + ")");
		}
		return;
	}
	const AIFloat3 rally = TairRallyCalc();
	ai.SetTeamBoard(TAB_RX, rally.x);
	ai.SetTeamBoard(TAB_RZ, rally.z);
	if (ph == TA_PH_NONE) {
		ai.SetTeamBoard(TAB_LAUNCH_AT, float(ai.frame));
		ai.SetTeamBoard(TAB_PHASE, float(TA_PH_GATHER));
		AiLog(Factory::T() + "apex: teamair-phase t=" + ai.teamId + " GATHER rally=" + int(rally.x) + "," + int(rally.z));
		return;
	}
	if (ph == TA_PH_GATHER) {
		if (ai.frame >= gTairEvalAt) {
			gTairEvalAt = ai.frame + 8 * SECOND;
			TairTargetEval(rally);
		}
		return;
	}
	// STRIKE ends when every seat has flown this op and nothing it sent is still out
	const int op = int(ai.GetTeamBoard(TAB_OP, 0.f));
	bool all = true;
	float outM = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (!TairSeatFresh(t))
			continue;
		if (int(ai.GetTeamBoard(TAS_OP + t, 0.f)) != op)
			all = false;
		outM += ai.GetTeamBoard(TAS_OUT + t, 0.f);
	}
	if (!all || (outM > 0.f)) {
		ai.SetTeamBoard(TAB_END2, 0.f);
		return;
	}
	const float e2 = ai.GetTeamBoard(TAB_END2, 0.f) + 1.f;
	ai.SetTeamBoard(TAB_END2, e2);
	if (e2 < 2.f)
		return;
	float K = 0.f, L = 0.f, M = 0.f;
	for (int t = 0; t < 64; ++t) {
		if (!TairSeatFresh(t) || (int(ai.GetTeamBoard(TAS_OP + t, 0.f)) != op))
			continue;
		const float k = ai.GetTeamBoard(TAS_KILL + t, 0.f);
		K = (k > K) ? k : K;
		L += ai.GetTeamBoard(TAS_LOST + t, 0.f);
		M += ai.GetTeamBoard(TAS_SENT + t, 0.f);
	}
	ai.SetTeamBoard(TAB_SUMM, ai.GetTeamBoard(TAB_SUMM, 0.f) + M);
	ai.SetTeamBoard(TAB_SUMK, ai.GetTeamBoard(TAB_SUMK, 0.f) + K);
	ai.SetTeamBoard(TAB_SUML, ai.GetTeamBoard(TAB_SUML, 0.f) + L);
	ai.SetTeamBoard(TAB_STRIKES, ai.GetTeamBoard(TAB_STRIKES, 0.f) + 1.f);
	ai.SetTeamBoard(TAB_PHASE, float(TA_PH_GATHER));
	AiLog(Factory::T() + "apex: teamair-settled t=" + ai.teamId + " op=" + op + " sent=" + int(M)
		+ " killed=" + int(K) + " lost=" + int(L) + " ledger=" + int(ai.GetTeamBoard(TAB_SUMM, 0.f))
		+ "/" + int(ai.GetTeamBoard(TAB_SUMK, 0.f)) + "/" + int(ai.GetTeamBoard(TAB_SUML, 0.f)));
}

// Every strike plane and escort of ours that is idle comes to the rally; a
// gunship in a fight squad is pulled out to come too. Counts what stands there.
void TairSeatScan()
{
	gTairGathN = 0;
	gTairGathHp = 0.f; gTairGathDps = 0.f; gTairGathCost = 0.f; gTairGathSpd = 0.f;
	gTairGathGunM = 0.f; gTairEscDps = 0.f; gTairAirM = 0.f; gTairOutM = 0.f; gTairOutGunM = 0.f;
	const bool gather = TairOn() && (TairPhase() != TA_PH_NONE) && !gDefendHome;
	const AIFloat3 rally = TairRally();
	const float R = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	const array<int>@ own = Market::OwnedDefs();
	int k = 0;
	for (uint oi = 0; oi < own.length(); ++oi) {
		const int d = own[oi];
		const bool strike = TairStrikeDef(d);
		const bool ftr = IsFighterDef(d);
		if (!strike && !ftr)
			continue;
		const bool gun = IsGunshipDef(d);
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ un = us[i];
			if (un is null)
				continue;
			if (strike)
				gTairAirM += Catalog::gCostM[d];
			if (InWave(un.id) || InList(gTairGun, un.id)) {
				gTairOutM += Catalog::gCostM[d];
				if (gun)
					gTairOutGunM += Catalog::gCostM[d];
				continue;
			}
			if (!gather)
				continue;
			IUnitTask@ tk = un.task;
			if ((tk is null) || (tk.GetType() != int(Task::Type::IDLE))) {
				if (gun && (tk !is null) && (tk.GetType() == int(Task::Type::FIGHTER))) {
					tk.RemoveUnit(un);
					++gTairPulled;
				}
				continue;
			}
			if (Covering(un.id) || (FlightOutIdx(un.id) >= 0) || InList(gHunters, un.id))
				continue;
			const AIFloat3 p = un.GetPos(ai.frame);
			if (p.distance2D(rally) > R) {
				if (un.CmdQueueSize() == 0) {
					const float ang = float(k) * 2.39996f;
					AIFloat3 at = rally + AIFloat3(cos(ang), 0.f, sin(ang)) * (R * 0.5f * sqrt(float(k % 16 + 1) / 16.f));
					if (!OnMap(at))
						at = rally;
					un.CmdMoveTo(at);
					++gTairMoved;
				}
				++k;
				continue;
			}
			++k;
			if (ftr) {
				gTairEscDps += NaAirDps(d);
				continue;
			}
			++gTairGathN;
			gTairGathHp += Catalog::gHealth[d];
			gTairGathDps += Catalog::gSurfDps[d];
			gTairGathCost += Catalog::gCostM[d];
			if (gun)
				gTairGathGunM += Catalog::gCostM[d];
			const float s = Catalog::gSpeed[d];
			if ((s > 0.f) && ((gTairGathSpd <= 0.f) || (s < gTairGathSpd)))
				gTairGathSpd = s;
		}
	}
}

void TairPublish()
{
	const int t = ai.teamId;
	ai.SetTeamBoard(TAS_AT + t, float(ai.frame));
	ai.SetTeamBoard(TAS_N + t, float(gTairGathN));
	ai.SetTeamBoard(TAS_HP + t, gTairGathHp);
	ai.SetTeamBoard(TAS_DPS + t, gTairGathDps);
	ai.SetTeamBoard(TAS_COST + t, gTairGathCost);
	ai.SetTeamBoard(TAS_SPD + t, gTairGathSpd);
	ai.SetTeamBoard(TAS_AIRM + t, gTairAirM);
	ai.SetTeamBoard(TAS_OUT + t, gTairOutM);
	ai.SetTeamBoard(TAS_SENT + t, gTairSentM);
	ai.SetTeamBoard(TAS_LOST + t, gTairLostM);
	ai.SetTeamBoard(TAS_KILL + t, gTairKillM);
	ai.SetTeamBoard(TAS_PLANT + t, ((Have(gPlant1) + Have(gPlant2)) > 0) ? 1.f : 0.f);
	ai.SetTeamBoard(TAS_INC + t, Eco::MInc());
	ai.SetTeamBoard(TAS_ESC + t, gTairEscDps);
	ai.SetTeamBoard(TAS_OP + t, float(gTairOpFlown));
	ai.SetTeamBoard(TAS_ECO + t, Market::gAssetsM);
}

// This seat's part of a team launch: the bombers and escorts as a wave at the
// target, the gunships claimed onto one raid goaled there.
void TairLaunch(int op)
{
	gTairOpFlown = op;
	gTairSent.resize(0);
	gTairGun.resize(0);
	gTairGunSent = 0;
	gTairSentM = 0.f;
	gTairLostM = 0.f;
	gTairKillM = 0.f;
	float r = 0.f;
	const AIFloat3 at = TairTargetPos(r);
	if (!OnMap(at) || (r <= 0.f) || gDefendHome)
		return;
	if (!gStrike) {
		gStrikeHas = true;
		gStrikeAt = at;
		gStrikePrize = ai.GetTeamBoard(TAB_NET, 0.f);
		gStrikeAA = 0.f;
		gNaCellAt = at;
		gNaCellOn = true;
		gNaWaitFrom = ai.frame;
		Release("teamair op " + op);
		for (uint i = 0; i < gWave.length(); ++i) {
			CCircuitUnit@ wu = ai.GetTeamUnit(gWave[i]);
			if ((wu is null) || (wu.circuitDef is null))
				continue;
			gTairSent.insertLast(wu.id);
			gTairSentM += Catalog::gCostM[int(wu.circuitDef.id)];
		}
	}
	NaWingLaunch(ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R) * 2.f);
	const array<int>@ own = Market::OwnedDefs();
	for (uint oi = 0; oi < own.length(); ++oi) {
		const int d = own[oi];
		if (!IsGunshipDef(d))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ un = us[i];
			if ((un is null) || Covering(un.id))
				continue;
			const bool claimed = gNaClaim.find(int(un.id)) >= 0;
			const bool idle = (un.task !is null) && (un.task.GetType() == int(Task::Type::IDLE));
			if (!claimed && !idle)
				continue;
			// apex_gather: the launch takes what stands at the rally
			if (Military::GthOn() && (un.GetPos(ai.frame).distance2D(TairRally())
					> ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R) * 1.5f)) {
				Military::JwRefused(int(Task::FightType::RAID), 1);
				continue;
			}
			if (!claimed)
				gNaClaim.insertLast(int(un.id));
			gTairGun.insertLast(un.id);
			gTairSent.insertLast(un.id);
			gTairSentM += Catalog::gCostM[d];
		}
	}
	gTairGunSent = int(gTairGun.length());
	if (gTairGunSent > 0) {
		gNaGunNow = NA_GO;
		gNaGunGoal = at;
		gNaGunR = r;
		if ((gNaTask !is null) && !gNaTask.IsDead())
			gNaTask.SetRaidGoal(at, r);
		Military::JwCommit(gNaTask, gNaClaim);
	}
	++gTairLaunches;
	AiLog(Factory::T() + "apex: teamair-launch t=" + ai.teamId + " op=" + op + " at=" + int(at.x) + "," + int(at.z)
		+ " wave=" + gWaveBombers + "b/" + gWaveFighters + "f gunships=" + gTairGunSent + " metal=" + int(gTairSentM));
}

// The seat's gunship run is over when half are gone, the cell is clear, or what
// gathered since outweighs what is out; the survivors come back to the rally.
void TairSeatWatch()
{
	if (gTairGun.length() == 0)
		return;
	array<Id> alive;
	for (uint i = 0; i < gTairGun.length(); ++i) {
		if (ai.GetTeamUnit(gTairGun[i]) !is null)
			alive.insertLast(gTairGun[i]);
	}
	gTairGun = alive;
	const bool over = (gTairGun.length() == 0) || (int(gTairGun.length()) * 2 < gTairGunSent)
		|| NaArrived() || (gTairGathGunM > gTairOutGunM);
	if (!over)
		return;
	for (uint i = 0; i < gTairGun.length(); ++i) {
		CCircuitUnit@ un = ai.GetTeamUnit(gTairGun[i]);
		if ((un !is null) && (un.task !is null) && (un.task.GetType() == int(Task::Type::FIGHTER)))
			un.task.RemoveUnit(un);
	}
	AiLog(Factory::T() + "apex: teamair-gun-home t=" + ai.teamId + " op=" + gTairOpFlown + " back="
		+ gTairGun.length() + "/" + gTairGunSent + " lost=" + int(gTairLostM) + " killed=" + int(gTairKillM));
	gTairGun.resize(0);
	gNaGunNow = NA_WAIT;
	gNaGunR = 0.f;
	gNaGunGoal = Builder::gHomePos;
}

void TairNoteDeath(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null) || (gTairSent.length() == 0) || !InList(gTairSent, unit.id))
		return;
	gTairLostM += unit.circuitDef.costM;
}

// Every death in the cell while the op is out, whoever is credited (S30).
void TairNoteKill(CCircuitDef@ edef, const AIFloat3& in pos)
{
	if ((edef is null) || (gTairOpFlown <= 0) || (TairPhase() != TA_PH_STRIKE)
		|| (int(ai.GetTeamBoard(TAB_OP, 0.f)) != gTairOpFlown))
		return;
	float r = 0.f;
	const AIFloat3 at = TairTargetPos(r);
	if ((r > 0.f) && OnMap(pos) && (pos.distance2D(at) <= r))
		gTairKillM += edef.costM;
}

// What a metal of this plane returns at the team's target: the race over the
// cell for a wing of it sized to the need. Bombers price its buildings only;
// gunships its buildings and the ground army we have seen standing there.
float TairReturn(int d)
{
	if (gTairRetV.length() == 0) {
		gTairRetV.resize(Catalog::gDefCount + 1);
		gTairRetAt.resize(Catalog::gDefCount + 1);
		for (uint i = 0; i < gTairRetAt.length(); ++i)
			gTairRetAt[i] = -1000000;
	}
	if ((d <= 0) || (d >= int(gTairRetV.length())))
		return 0.f;
	if (ai.frame < gTairRetAt[d] + 30 * SECOND)
		return gTairRetV[d];
	gTairRetAt[d] = ai.frame;
	gTairRetV[d] = 0.f;
	float r = 0.f;
	const AIFloat3 at = TairTargetPos(r);
	const float needM = ai.GetTeamBoard(TAB_NEEDM, 0.f);
	const float cost = Catalog::gCostM[d], spd = Catalog::gSpeed[d];
	if (!OnMap(at) || (r <= 0.f) || (needM <= 0.f) || (cost <= 0.f) || (spd <= 0.f) || (Catalog::gDps[d] <= 0.f))
		return 0.f;
	int n = int(needM / cost);
	if (n < 1)
		n = 1;
	const AIFloat3 foe = NaFoe();
	NaSnapEnemy(OnMap(foe) ? foe : Builder::gHomePos);
	TairFoeSplit();
	NaCand c;
	c.at = at;
	for (uint e = 0; e < gNaEcoP.length(); ++e) {
		if (gNaEcoP[e].distance2D(at) <= r) {
			c.v += gNaEcoV[e];
			c.hp += Catalog::gHealth[gNaEcoD[e]];
			++c.n;
		}
	}
	if (IsGunshipDef(d)) {
		for (uint e = 0; e < gTairMobP.length(); ++e) {
			if (gTairMobP[e].distance2D(at) <= r) {
				c.v += gTairMobM[e];
				c.hp += gTairMobH[e];
				++c.n;
			}
		}
	}
	for (uint e = 0; e < gNaAAP.length(); ++e) {
		if (gNaAAP[e].distance2D(at) <= gNaAAR[e] + r * 0.5f)
			c.aaT += gNaAAV[e];
	}
	const AIFloat3 from = TairRally();
	const float flyS = from.distance2D(at) / spd;
	TairTeamSum();
	float fAA = NaFighterAA(at, flyS) - gTairTEsc;
	fAA = (fAA > 0.f) ? fAA : 0.f;
	gNaObsDmg = -1.f;
	gNaObsLost = -1.f;
	const float net = NaEval(c, NaPathAA(from, at), fAA, n, Catalog::gHealth[d], Catalog::gSurfDps[d], cost, spd,
			flyS, true, -1.f, null);
	gTairRetV[d] = net / (float(n) * cost);
	return gTairRetV[d];
}

// Production's price for one more strike plane: the team's shortfall against
// the target's need, this seat's share of it among the seats with a plant, at
// the metal-for-metal return the plane makes there.
float TairGainFor(int d, float fillSec)
{
	if (!TairOn() || !TairStrikeDef(d))
		return 0.f;
	TairTeamSum();
	const float needM = ai.GetTeamBoard(TAB_NEEDM, 0.f);
	const float shortM = needM - gTairTAirM - float(Brain::PendAnyOf(d)) * Catalog::gCostM[d];
	if (shortM <= 0.f)
		return 0.f;
	const float ret = TairReturn(d);
	if (ret <= 0.f)
		return 0.f;
	const float seats = (gTairPlants > 1) ? float(gTairPlants) : 1.f;
	return shortM / seats * ret / ((fillSec > 1.f) ? fillSec : 180.f);
}

// Escorts only against fighters we have seen: our share of their fighter metal.
float TairEscortGainFor(int d, float fillSec)
{
	if (!IsFighterDef(d))
		return 0.f;
	TairTeamSum();
	const float seats = (gTairSeats > 1) ? float(gTairSeats) : 1.f;
	const float want = FoeFighterM() / seats;
	const float have = FighterMetalHeld() + float(Brain::PendAnyOf(d)) * Catalog::gCostM[d];
	if (want <= have)
		return 0.f;
	return (want - have) / ((fillSec > 1.f) ? fillSec : 180.f);
}

void TairLog()
{
	if (ai.frame < gTairLogAt)
		return;
	gTairLogAt = ai.frame + 60 * SECOND;
	TairTeamSum();
	string terms = "";
	const array<string> names = {"vAir", "vNorm", "gnd0", "gndS", "air1", "air0", "S", "airS", "G0", "E", "q",
		"foeAA", "foeFtr", "foeDef", "foeArmy", "foeEco", "teamEco", "teamAirM"};
	for (int i = 0; i < TAB_NTERMS; ++i)
		terms += " " + names[i] + "=" + Market::NnF(ai.GetTeamBoard(TAB_TERMS + i, 0.f), (i == 10) ? 2 : 0);
	float r = 0.f;
	const AIFloat3 tp = TairTargetPos(r);
	const int ph = TairPhase();
	AiLog(Factory::T() + "apex: teamair-stat t=" + ai.teamId + " plan=" + Market::NgName(Market::gPlan)
		+ " phase=" + (((ph >= 0) && (ph < 3)) ? TA_PH_NAMES[ph] : "?") + " lead=" + Market::TaLeader()
		+ " verdict=" + int(ai.GetTeamBoard(TAB_VERDICT, 0.f)) + terms
		+ " seats=" + gTairSeats + " plants=" + gTairPlants
		+ " mineAirM=" + int(gTairAirM) + " mineGath=" + gTairGathN + " mineOut=" + int(gTairOutM)
		+ " teamGathN=" + int(gTairTN) + " teamGathM=" + int(gTairTCost) + " esc=" + int(gTairTEsc)
		+ " need=" + int(ai.GetTeamBoard(TAB_NEEDN, 0.f)) + " needM=" + int(ai.GetTeamBoard(TAB_NEEDM, 0.f))
		+ " proj=" + int(ai.GetTeamBoard(TAB_PROJN, 0.f)) + " tgt=" + int(tp.x) + "," + int(tp.z)
		+ " net=" + int(ai.GetTeamBoard(TAB_NET, 0.f))
		+ " op=" + int(ai.GetTeamBoard(TAB_OP, 0.f)) + " flown=" + gTairOpFlown + " launches=" + gTairLaunches
		+ " sent=" + int(gTairSentM) + " killed=" + int(gTairKillM) + " lost=" + int(gTairLostM)
		+ " ledger=" + int(ai.GetTeamBoard(TAB_SUMM, 0.f)) + "/" + int(ai.GetTeamBoard(TAB_SUMK, 0.f))
		+ "/" + int(ai.GetTeamBoard(TAB_SUML, 0.f)) + " strikes=" + int(ai.GetTeamBoard(TAB_STRIKES, 0.f))
		+ " pulled=" + gTairPulled + " moved=" + gTairMoved);
}

void TairUpdate()
{
	if (Military::StockQuiet("air"))
		return;
	if (!TairSwitch() || !Builder::gHomeSet || (ai.frame < gTairNextAt))
		return;
	gTairNextAt = ai.frame + 4 * SECOND;
	const double _t = Perf::T0();
	if ((TairPhase() == TA_PH_STRIKE) && (int(ai.GetTeamBoard(TAB_OP, 0.f)) > gTairOpFlown))
		TairLaunch(int(ai.GetTeamBoard(TAB_OP, 0.f)));
	TairSeatScan();
	TairSeatWatch();
	TairPublish();
	if (Market::TaLeader() == ai.teamId)
		TairLead();
	TairLog();
	Perf::Add("air.tair", _t);
}

}  // namespace Air
