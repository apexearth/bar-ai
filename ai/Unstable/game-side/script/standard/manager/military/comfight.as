namespace Military {

//------------------------------------------------------------------------------
// ONE FIGHT ESTIMATE PER GROUP (apex_com_fight; his 2026-10-16: pawns and grunts early "and don't just lose
// them straight to the enemy commander", "you have to push with that much army", "commit with enough people or
// just stay away from it", "pawns/grunts don't engage those targets", "the thugs should be fighting the Janus
// and the pawns go around").
// Every second each ground squad of ours with an armed enemy in reach -- army, towers and commanders at their
// seen or remembered positions -- is fought out on paper with focus fire both ways: their splash hitting every
// unit of ours its area covers, a shot bigger than a unit spent on that one unit, a commander's regeneration and
// the D-gun shots our own energy says a commander can afford.
//  - Units a mobile threat one-shots or beats head-on, and that outrun it, leave the group for a raid on the
//    nearest economy of theirs clear of that threat (the rest are fought on paper again next pass).
//  - A group that wins fight-walks onto the nearest armed enemy and keeps its task's push after.
//  - One that loses walks to the nearest friendly group, tower or home where the pooled estimate wins, and the
//    defended point becomes a ring its task picks no targets in, until what stands there or in the group changes.
//  - A commander inside our base pulls every group in the base onto it when they win together, else they hold
//    at home under the towers.
//------------------------------------------------------------------------------

// one pass (1 s) plus the C++ task's reaction and turn (SquadTask DGUN_REACT_S): how far ahead "in reach" looks
const float CF_REACT_S = 3.f;

bool gCfOn = false;
int gCfOnAt = -1;

bool CfOn()
{
	if (gCfOnAt != ai.frame) {
		gCfOnAt = ai.frame;
		gCfOn = ai.GetTunable("apex_com_fight", TUNE_COM_FIGHT) > 0.f;
	}
	return gCfOn;
}

// ---- what we know of theirs, rebuilt over two passes from the registry ----
// armed (E) and economy (X: extractors and constructors)
array<int> gCfEDef;
array<float> gCfEX;
array<float> gCfEZ;
array<int> gCfNDef;
array<float> gCfNX;
array<float> gCfNZ;
array<float> gCfXX;
array<float> gCfXZ;
array<float> gCfXM;
array<float> gCfYX;
array<float> gCfYZ;
array<float> gCfYM;
float gCfEReach = 0.f;
float gCfNReach = 0.f;
int gCfScanI = 0;
int gCfScanTotal = 0;
Grid::Cells gCfEGrid;
array<int8> gCfComDef;
array<float> gCfHeal;

bool CfIsCom(int d)
{
	if (int(gCfComDef.length()) <= d)
		gCfComDef.resize(d + 1);
	if (gCfComDef[d] == 0)
		gCfComDef[d] = Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask) ? 1 : -1;
	return gCfComDef[d] > 0;
}

float CfHeal(int d)
{
	if (int(gCfHeal.length()) <= d) {
		const uint was = gCfHeal.length();
		gCfHeal.resize(d + 1);
		for (uint i = was; i < gCfHeal.length(); ++i)
			gCfHeal[i] = -1.f;
	}
	if (gCfHeal[d] < 0.f) {
		gCfHeal[d] = Catalog::Def(d).GetAutoHealPerSec();
		if (CfIsCom(d))
			AiLog("apex: comfight-def " + Catalog::Def(d).GetName() + " heal/s=" + formatFloat(gCfHeal[d], "", 0, 2)
				+ " dps=" + int(Catalog::gDps[d]) + " alpha=" + int(Catalog::gAlpha[d]) + " hp=" + int(Catalog::gHealth[d])
				+ " aoe=" + int(Catalog::gAoe[d]) + " range=" + int(Catalog::gMaxRange[d]));
	}
	return gCfHeal[d];
}

void CfScanStep()
{
	if (gCfScanI == 0) {
		gCfScanTotal = aiEnemyMgr.GetEnemyUnitTotal();
		gCfNDef.resize(0); gCfNX.resize(0); gCfNZ.resize(0);
		gCfYX.resize(0); gCfYZ.resize(0); gCfYM.resize(0);
		gCfNReach = 0.f;
	}
	const int chunk = gCfScanTotal / 2 + 1;
	const int end = (gCfScanI + chunk < gCfScanTotal) ? gCfScanI + chunk : gCfScanTotal;
	for (int i = gCfScanI; i < end; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if (!Catalog::ValidId(d) || Catalog::gFlyer[d] || Catalog::gKamikaze[d])
			continue;
		const bool armed = (Catalog::gDps[d] > 0.f) && (Catalog::gSurfT[d] > 0.f) && (Catalog::gMaxRange[d] > 0.f);
		const bool eco = (Catalog::gExtractsM[d] > 0.f)
			|| (Catalog::gBuilder[d] && Catalog::gMobile[d] && !CfIsCom(d));
		if (!armed && !eco)
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (4 | 8 | 32 | 64)) != 0))
			continue;
		// out of sight, a mobile one is kept while it cannot have walked out of its own reach since
		if (((los & 3) == 0) && Catalog::gMobile[d]) {
			const float dt = float(ai.frame - aiEnemyMgr.GetEnemyUnitSeenAt(i)) / float(SECOND);
			if (!armed || (Catalog::gSpeed[d] * dt > Catalog::gMaxRange[d]))
				continue;
		}
		const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if (!OnMap(p))
			continue;
		if (eco) {
			gCfYX.insertLast(p.x);
			gCfYZ.insertLast(p.z);
			gCfYM.insertLast(Catalog::gCostM[d]);
		}
		if (!armed)
			continue;
		gCfNDef.insertLast(d);
		gCfNX.insertLast(p.x);
		gCfNZ.insertLast(p.z);
		const float reach = Catalog::gMaxRange[d] + Catalog::gSpeed[d] * CF_REACT_S;
		if (reach > gCfNReach)
			gCfNReach = reach;
	}
	gCfScanI = end;
	if (gCfScanI < gCfScanTotal)
		return;
	gCfScanI = 0;
	gCfEDef = gCfNDef;
	gCfEX = gCfNX;
	gCfEZ = gCfNZ;
	gCfXX = gCfYX;
	gCfXZ = gCfYZ;
	gCfXM = gCfYM;
	gCfEReach = gCfNReach;
	gCfEGrid.Begin(512.f, 0.f, 0.f, float(AiTerrainWidth()), float(AiTerrainHeight()));
	for (uint k = 0; k < gCfEDef.length(); ++k)
		gCfEGrid.Add(gCfEX[k], gCfEZ[k]);
}

// ---- our ground squads, read each pass ----
array<IUnitTask@> gCfGT;
array<float> gCfGX, gCfGZ, gCfGDps, gCfGHp, gCfGM, gCfGRng, gCfGSpd, gCfGSpr;
array<int> gCfGN;
array<bool> gCfGDone;

void CfReadGroups()
{
	gCfGT.resize(0); gCfGX.resize(0); gCfGZ.resize(0); gCfGDps.resize(0); gCfGHp.resize(0); gCfGM.resize(0);
	gCfGRng.resize(0); gCfGSpd.resize(0); gCfGSpr.resize(0); gCfGN.resize(0); gCfGDone.resize(0);
	const float superCost = ai.GetTunable("apex_super_cost", TUNE_SUPER_COST);
	for (uint i = 0; i < gSquads.length(); ++i) {
		IUnitTask@ t = gSquads[i];
		if ((t is null) || t.IsDead())
			continue;
		const int ft = t.GetFightType();
		if ((ft != Task::FightType::RAID) && (ft != Task::FightType::ATTACK) && (ft != Task::FightType::DEFEND))
			continue;
		array<CCircuitUnit@>@ us = t.GetUnits();
		if ((us is null) || (us.length() == 0))
			continue;
		float sx = 0.f, sz = 0.f, dps = 0.f, hp = 0.f, m = 0.f, rng = 0.f, spd = 1e9f;
		int n = 0;
		bool skip = false;
		array<AIFloat3> ps;
		for (uint k = 0; k < us.length(); ++k) {
			CCircuitUnit@ u = us[k];
			if ((u is null) || (u.circuitDef is null))
				continue;
			const int d = int(u.circuitDef.id);
			if (!Catalog::ValidId(d) || Catalog::gFlyer[d])
				continue;
			if (IsChargerDef(u.circuitDef) || (Catalog::gCostM[d] >= superCost)) {
				skip = true;
				break;
			}
			const AIFloat3 p = u.GetPos(ai.frame);
			if (!OnMap(p))
				continue;
			ps.insertLast(p);
			sx += p.x;
			sz += p.z;
			dps += Catalog::gDps[d];
			hp += Catalog::gHealth[d] * u.GetHealthPercent();
			m += Catalog::gCostM[d];
			if (Catalog::gMaxRange[d] > rng)
				rng = Catalog::gMaxRange[d];
			if (Catalog::gSpeed[d] < spd)
				spd = Catalog::gSpeed[d];
			++n;
		}
		if (skip || (n == 0) || (dps <= 0.f))
			continue;
		const float cx = sx / float(n), cz = sz / float(n);
		float spr = 0.f;
		for (uint k = 0; k < ps.length(); ++k) {
			const float dd = sqrt((ps[k].x - cx) * (ps[k].x - cx) + (ps[k].z - cz) * (ps[k].z - cz));
			if (dd > spr)
				spr = dd;
		}
		gCfGT.insertLast(t); gCfGX.insertLast(cx); gCfGZ.insertLast(cz); gCfGDps.insertLast(dps);
		gCfGHp.insertLast(hp); gCfGM.insertLast(m); gCfGRng.insertLast(rng); gCfGSpd.insertLast(spd);
		gCfGSpr.insertLast(spr); gCfGN.insertLast(n); gCfGDone.insertLast(false);
	}
}

// ---- the estimate: focus fire both ways, event by event ----
float gCfDgCost = 0.f;
float gCfDgReload = 0.f;
float gCfDgRange = 0.f;
float gCfLostO = 0.f;
float gCfLostT = 0.f;

void CfReadDGun()
{
	CCircuitUnit@ c = Builder::gComm;
	if (c is null)
		return;
	const float cost = c.DGunCostE();
	if (cost > 0.f) {
		gCfDgCost = cost;
		gCfDgReload = c.DGunReload();
		gCfDgRange = c.DGunRange();
	}
}

float CfDist(float x0, float z0, float x1, float z1)
{
	return sqrt((x0 - x1) * (x0 - x1) + (z0 - z1) * (z0 - z1));
}

// the units of ours a shell with this area lands on, in a group of n spread over spr
float CfCovered(float aoe, int n, float spr)
{
	if ((aoe <= 0.f) || (n <= 1))
		return 1.f;
	const float s = (spr > aoe) ? spr : aoe;
	float c = 1.f + float(n - 1) * (aoe * aoe) / (s * s);
	return (c > float(n)) ? float(n) : c;
}

// A foe's damage per second against units of hp h in a group of n over spr: every unit its area covers, and a
// shot bigger than the unit spent on that unit alone. A commander's D-gun is counted on its own clock.
float CfEffDps(int d, float h, int n, float spr)
{
	float e = Catalog::gDps[d] * CfCovered(Catalog::gAoe[d], n, spr);
	const float a = Catalog::gAlpha[d];
	if (!CfIsCom(d) && (a > h) && (h > 0.f))
		e *= h / a;
	return e;
}

// nearest (x, z) first, in place: one sort per group, every estimate of it reuses the order
void CfSortFoes(array<int>& foe, float x, float z)
{
	const int nT = int(foe.length());
	array<float> dist(nT);
	for (int k = 0; k < nT; ++k)
		dist[k] = CfDist(gCfEX[foe[k]], gCfEZ[foe[k]], x, z);
	for (int a = 1; a < nT; ++a) {
		const int oi = foe[a];
		const float od = dist[a];
		int b = a - 1;
		while ((b >= 0) && (dist[b] > od)) {
			foe[b + 1] = foe[b];
			dist[b + 1] = dist[b];
			--b;
		}
		foe[b + 1] = oi;
		dist[b + 1] = od;
	}
}

// Our side: nO bodies of dO dps, hO hp and mO metal each, then the towers as one body behind them.
// Their side: the foe indices, nearest the fight first. True when every one of them dies first.
bool CfFight(float nOf, float dO, float hO, float mO, float spr, float rngO, float twDps, float twHp,
		const array<int>@ ord)
{
	gCfLostO = 0.f;
	gCfLostT = 0.f;
	const int nT = int(ord.length());
	if (nT == 0)
		return true;
	int nO = int(floor(nOf + 0.5f));
	if (nO < 1)
		nO = 1;
	float sumT = 0.f, sumTs = 0.f, comSpd = 0.f;
	int coms = 0;
	for (int k = 0; k < nT; ++k) {
		const int d = gCfEDef[ord[k]];
		sumT += Catalog::gDps[d];
		sumTs += CfEffDps(d, hO, nO, spr);
		if (CfIsCom(d)) {
			++coms;
			if (Catalog::gSpeed[d] > comSpd)
				comSpd = Catalog::gSpeed[d];
		}
	}
	// the D-gun reaches a group that has to come inside it to shoot, or that it closes on within one reaction
	const bool dgReach = rngO <= gCfDgRange + comSpd * CF_REACT_S;
	float dgI = 1e9f;
	if ((coms > 0) && (gCfDgCost > 0.f)) {
		const float eInc = Eco::EInc();
		dgI = (eInc > 1.f) ? gCfDgCost / eInc : 1e9f;
		if (dgI < gCfDgReload)
			dgI = gCfDgReload;
	}
	float sumO = dO * float(nO) + twDps;
	bool twAlive = (twDps > 0.f) && (twHp > 0.f);
	float hpO = hO;
	float hpTw = twHp;
	int io = 0;
	int it = 0;
	float hpT = Catalog::gHealth[gCfEDef[ord[0]]];
	float t = 0.f;
	float nextDg = (coms > 0) ? 0.f : 1e9f;
	for (int iter = 0; iter < 512; ++iter) {
		if (it >= nT)
			return true;
		if ((io >= nO) && !twAlive)
			break;
		const int d = gCfEDef[ord[it]];
		const bool com = CfIsCom(d);
		const float regen = com ? CfHeal(d) : 0.f;
		const float ourRate = sumO - regen;
		const float a = (ourRate > 0.f) ? hpT / ourRate : 1e9f;
		const bool onUnits = io < nO;
		const float theirRate = onUnits ? sumTs : sumT;
		const float b = (theirRate > 0.f) ? (onUnits ? hpO : hpTw) / theirRate : 1e9f;
		const float c = ((coms > 0) && onUnits && dgReach) ? nextDg - t : 1e9f;
		float dt = a;
		if (b < dt) dt = b;
		if (c < dt) dt = c;
		if (dt >= 1e8f)
			break;
		if (dt < 0.f)
			dt = 0.f;
		t += dt;
		hpT -= ((ourRate > 0.f) ? ourRate : 0.f) * dt;
		if (onUnits)
			hpO -= theirRate * dt;
		else
			hpTw -= theirRate * dt;
		if (a <= dt) {
			gCfLostT += Catalog::gCostM[d];
			sumT -= Catalog::gDps[d];
			sumTs -= CfEffDps(d, hO, nO, spr);
			if (com) {
				--coms;
				if (coms <= 0)
					nextDg = 1e9f;
			}
			++it;
			if (it < nT)
				hpT = Catalog::gHealth[gCfEDef[ord[it]]];
		}
		if ((b <= dt) || ((c <= dt) && onUnits)) {
			if (onUnits) {
				gCfLostO += mO;
				sumO -= dO;
				++io;
				hpO = hO;
			} else {
				twAlive = false;
				sumO -= twDps;
			}
			if (c <= dt)
				nextDg = t + dgI;
		}
	}
	return false;
}

// ---- verdicts and episodes ----
const int CF_ENGAGE = 1;
const int CF_FALL = 2;
const int CF_HOME = 3;
const int CF_BASE_ENGAGE = 4;
const int CF_BASE_HOLD = 5;

array<IUnitTask@> gCfEpT;
array<int> gCfEpV;
array<bool> gCfEpPW;
array<float> gCfEpPL, gCfEpPK, gCfEpLost, gCfEpKill, gCfEpX, gCfEpZ, gCfEpR;
array<int> gCfEpLast;
array<bool> gCfEpLatch;
// the defended point it decided not to take: ring, what stood there, what we had, where it fell back to
array<bool> gCfEpKo;
array<float> gCfEpKoX, gCfEpKoZ, gCfEpKoR, gCfEpKoM, gCfEpFX, gCfEpFZ;
array<int> gCfEpKoN, gCfEpKoOurN;
array<bool> gCfEpOut;

int CfEpSlot(IUnitTask@ t)
{
	for (uint i = 0; i < gCfEpT.length(); ++i) {
		if (gCfEpT[i] is t)
			return int(i);
	}
	return -1;
}

int CfEpNew(IUnitTask@ t)
{
	gCfEpT.insertLast(t); gCfEpV.insertLast(0); gCfEpPW.insertLast(false); gCfEpPL.insertLast(0.f);
	gCfEpPK.insertLast(0.f); gCfEpLost.insertLast(0.f); gCfEpKill.insertLast(0.f); gCfEpX.insertLast(0.f);
	gCfEpZ.insertLast(0.f); gCfEpR.insertLast(0.f); gCfEpLast.insertLast(ai.frame); gCfEpLatch.insertLast(false);
	gCfEpKo.insertLast(false); gCfEpKoX.insertLast(0.f); gCfEpKoZ.insertLast(0.f); gCfEpKoR.insertLast(0.f);
	gCfEpKoM.insertLast(0.f); gCfEpFX.insertLast(0.f); gCfEpFZ.insertLast(0.f); gCfEpKoN.insertLast(0);
	gCfEpKoOurN.insertLast(0); gCfEpOut.insertLast(false);
	return int(gCfEpT.length()) - 1;
}

void CfEpDrop(int i)
{
	gCfEpT.removeAt(i); gCfEpV.removeAt(i); gCfEpPW.removeAt(i); gCfEpPL.removeAt(i); gCfEpPK.removeAt(i);
	gCfEpLost.removeAt(i); gCfEpKill.removeAt(i); gCfEpX.removeAt(i); gCfEpZ.removeAt(i); gCfEpR.removeAt(i);
	gCfEpLast.removeAt(i); gCfEpLatch.removeAt(i); gCfEpKo.removeAt(i); gCfEpKoX.removeAt(i);
	gCfEpKoZ.removeAt(i); gCfEpKoR.removeAt(i); gCfEpKoM.removeAt(i); gCfEpFX.removeAt(i); gCfEpFZ.removeAt(i);
	gCfEpKoN.removeAt(i); gCfEpKoOurN.removeAt(i); gCfEpOut.removeAt(i);
}

// minute counters
int gCfInReach = 0, gCfComReach = 0, gCfEngage = 0, gCfFall = 0, gCfMerged = 0, gCfHome = 0, gCfHold = 0;
int gCfBaseW = 0, gCfBaseL = 0, gCfFlips = 0, gCfKoSet = 0, gCfKoKept = 0, gCfKoLift = 0, gCfDither = 0;
int gCfEpN = 0, gCfEpPredW = 0, gCfComKills = 0;
int gCfSplits = 0, gCfReleased = 0, gCfOneShot = 0, gCfNoEco = 0;
float gCfEpLostM = 0.f, gCfEpKillM = 0.f, gCfEpPredL = 0.f, gCfEpPredK = 0.f, gCfEcoKillM = 0.f;
array<int> gCfMove(5, 0);       // still, retreat, advance, lateral, unknown
array<float> gCfKiller(5, 0.f); // commander, tower, splash, other, unseen
double gCfUs = 0.0, gCfMaxUs = 0.0;
int gCfCalls = 0;
int gCfNextLog = 0;

void CfVerdict(int g, int v, float tx, float tz, bool predWin, float r)
{
	IUnitTask@ t = gCfGT[g];
	AIFloat3 to(tx, 0.f, tz);
	to.y = ai.GetElevationAt(to);
	t.SetScriptMove(to, ai.frame + int(CF_REACT_S * float(SECOND)), (v == CF_ENGAGE) || (v == CF_BASE_ENGAGE));
	gCfGDone[g] = true;
	int s = CfEpSlot(t);
	if (s < 0) {
		s = CfEpNew(t);
		gCfEpPW[s] = predWin;
		gCfEpPL[s] = gCfLostO;
		gCfEpPK[s] = gCfLostT;
	} else if ((gCfEpV[s] != 0) && (gCfEpV[s] != v)) {
		++gCfFlips;
	}
	gCfEpV[s] = v;
	gCfEpX[s] = gCfGX[g];
	gCfEpZ[s] = gCfGZ[g];
	gCfEpR[s] = r;
	gCfEpLast[s] = ai.frame;
	if (v == CF_ENGAGE) ++gCfEngage;
	else if (v == CF_FALL) ++gCfFall;
	else if (v == CF_HOME) ++gCfHome;
	else if (v == CF_BASE_ENGAGE) ++gCfBaseW;
	else if (v == CF_BASE_HOLD) ++gCfBaseL;
}

// the armed enemies a group at (x, z) reaches, or that reach it, within one reaction; nearest first
void CfFoesNear(float x, float z, float rng, float spd, float spr, array<int>& out foe, bool& out com)
{
	foe.resize(0);
	com = false;
	if (gCfEDef.length() == 0)
		return;
	const float rq = ((gCfEReach > rng) ? gCfEReach : rng) + spd * CF_REACT_S + spr;
	gCfEGrid.Query(x, z, rq);
	for (uint h = 0; h < gCfEGrid.hit.length(); ++h) {
		const int k = gCfEGrid.hit[h];
		const int d = gCfEDef[k];
		const float er = Catalog::gMaxRange[d];
		const float reach = ((er > rng) ? er : rng) + (Catalog::gSpeed[d] + spd) * CF_REACT_S + spr;
		if (CfDist(gCfEX[k], gCfEZ[k], x, z) > reach)
			continue;
		foe.insertLast(k);
		if (CfIsCom(d))
			com = true;
	}
	CfSortFoes(foe, x, z);
}

// Our strength standing at (x, z): every group within its own reach of it, the towers covering it and our
// allies' army there at our metal's dps and hp. `with` counts wherever it stands (the one walking in).
float gCfPN = 0.f, gCfPDps = 0.f, gCfPHp = 0.f, gCfPM = 0.f, gCfPSpr = 0.f, gCfPRng = 0.f, gCfPTwD = 0.f, gCfPTwH = 0.f;
void CfPoolAt(float x, float z, int with)
{
	gCfPN = 0.f; gCfPDps = 0.f; gCfPHp = 0.f; gCfPM = 0.f; gCfPSpr = 0.f; gCfPRng = 0.f;
	for (uint o = 0; o < gCfGT.length(); ++o) {
		const float d = CfDist(gCfGX[o], gCfGZ[o], x, z);
		if ((int(o) != with) && (d > gCfGRng[o] + gCfGSpd[o] * CF_REACT_S + gCfGSpr[o]))
			continue;
		gCfPN += float(gCfGN[o]);
		gCfPDps += gCfGDps[o];
		gCfPHp += gCfGHp[o];
		gCfPM += gCfGM[o];
		const float s = gCfGSpr[o] + ((int(o) == with) ? 0.f : d);
		if (s > gCfPSpr)
			gCfPSpr = s;
		if (gCfGRng[o] > gCfPRng)
			gCfPRng = gCfGRng[o];
	}
	CfPoolExtras(x, z, gCfPRng + gCfPSpr);
}

void CfPoolExtras(float x, float z, float allyR)
{
	AIFloat3 p(x, 0.f, z);
	Market::ComGunAt(p, gCfPTwD, gCfPTwH);
	if (gCfPM > 0.f) {
		const float allyM = ai.GetAllyArmyMAt(p, allyR);
		if (allyM > 0.f) {
			const float k = allyM / gCfPM;
			gCfPN += gCfPN * k;
			gCfPDps += gCfPDps * k;
			gCfPHp += gCfPHp * k;
			gCfPM += allyM;
		}
	}
}

bool CfPoolFight(const array<int>@ foe)
{
	if (gCfPN <= 0.f)
		return false;
	return CfFight(gCfPN, gCfPDps / gCfPN, gCfPHp / gCfPN, gCfPM / gCfPN, gCfPSpr, gCfPRng, gCfPTwD, gCfPTwH, foe);
}

// the nearest armed enemy, mobile first
void CfNearestFoe(const array<int>@ foe, float x, float z, float& out tx, float& out tz)
{
	float best = -1.f;
	bool bestMob = false;
	tx = x;
	tz = z;
	for (uint i = 0; i < foe.length(); ++i) {
		const int k = foe[i];
		const bool mob = Catalog::gMobile[gCfEDef[k]];
		const float d = CfDist(gCfEX[k], gCfEZ[k], x, z);
		if ((best >= 0.f) && bestMob && !mob)
			continue;
		if ((best < 0.f) || (mob && !bestMob) || (d < best)) {
			best = d;
			bestMob = mob;
			tx = gCfEX[k];
			tz = gCfEZ[k];
		}
	}
}

// ---- the split by matchup: units a threat counters go around it to their economy ----
array<int> gCfClaimId;
array<int> gCfClaimSlot;
array<IUnitTask@> gCfEcoT;
array<float> gCfEcoX, gCfEcoZ, gCfEcoR, gCfEcoKX, gCfEcoKZ, gCfEcoKR;
array<int> gCfEcoAt, gCfEcoKDef;

bool CfClaimed(int id)
{
	for (uint i = 0; i < gCfClaimId.length(); ++i) {
		if (gCfClaimId[i] == id)
			return true;
	}
	return false;
}

// the claimed unit's re-election: onto the raid made for its split, made on the first arrival
IUnitTask@ CfEcoTaskFor(int id)
{
	int s = -1;
	for (uint i = 0; i < gCfClaimId.length(); ++i) {
		if (gCfClaimId[i] == id) {
			s = gCfClaimSlot[i];
			gCfClaimId.removeAt(i);
			gCfClaimSlot.removeAt(i);
			break;
		}
	}
	if ((s < 0) || (s >= int(gCfEcoT.length())))
		return null;
	if ((gCfEcoT[s] is null) || gCfEcoT[s].IsDead()) {
		@gCfEcoT[s] = aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::RAID));
		if (gCfEcoT[s] is null)
			return null;
		AIFloat3 goal(gCfEcoX[s], 0.f, gCfEcoZ[s]);
		goal.y = ai.GetElevationAt(goal);
		gCfEcoT[s].SetRaidGoal(goal, gCfEcoR[s]);
		AIFloat3 ko(gCfEcoKX[s], 0.f, gCfEcoKZ[s]);
		gCfEcoT[s].SetKeepOut(ko, gCfEcoKR[s], ai.frame + int(CF_REACT_S * float(SECOND)));
	}
	return gCfEcoT[s];
}

// A raid made for a split keeps out of the threat while it is seen near where it was: the ring follows the
// nearest armed enemy of that kind within its walk of one reaction, and lapses with it.
void CfEcoRefresh()
{
	for (int c = int(gCfClaimId.length()) - 1; c >= 0; --c) {
		if (ai.GetTeamUnit(Id(gCfClaimId[c])) is null) {
			gCfClaimId.removeAt(c);
			gCfClaimSlot.removeAt(c);
		}
	}
	for (int s = int(gCfEcoT.length()) - 1; s >= 0; --s) {
		const bool live = (gCfEcoT[s] !is null) && !gCfEcoT[s].IsDead();
		const bool waiting = (gCfEcoT[s] is null) && (ai.frame - gCfEcoAt[s] < 10 * SECOND);
		if (!live && !waiting) {
			bool claimed = false;
			for (uint c = 0; c < gCfClaimSlot.length(); ++c)
				claimed = claimed || (gCfClaimSlot[c] == s);
			if (!claimed) {
				gCfEcoT.removeAt(s); gCfEcoX.removeAt(s); gCfEcoZ.removeAt(s); gCfEcoR.removeAt(s);
				gCfEcoKX.removeAt(s); gCfEcoKZ.removeAt(s); gCfEcoKR.removeAt(s); gCfEcoAt.removeAt(s);
				gCfEcoKDef.removeAt(s);
				for (uint c = 0; c < gCfClaimSlot.length(); ++c) {
					if (gCfClaimSlot[c] > s)
						--gCfClaimSlot[c];
				}
			}
			continue;
		}
		if (!live)
			continue;
		const int kd = gCfEcoKDef[s];
		const float walk = Catalog::gMaxRange[kd] + Catalog::gSpeed[kd] * CF_REACT_S;
		float best = -1.f;
		for (uint k = 0; k < gCfEDef.length(); ++k) {
			if (gCfEDef[k] != kd)
				continue;
			const float d = CfDist(gCfEX[k], gCfEZ[k], gCfEcoKX[s], gCfEcoKZ[s]);
			if ((d <= walk) && ((best < 0.f) || (d < best))) {
				best = d;
				gCfEcoKX[s] = gCfEX[k];
				gCfEcoKZ[s] = gCfEZ[k];
			}
		}
		if (best < 0.f)
			continue;
		AIFloat3 ko(gCfEcoKX[s], 0.f, gCfEcoKZ[s]);
		gCfEcoT[s].SetKeepOut(ko, gCfEcoKR[s], ai.frame + int(CF_REACT_S * float(SECOND)));
	}
}

// Head-on, does foe k beat the n units of def c in this group? One-shot is the hard case of the same test:
// a shot that kills a unit outright takes one per volley whatever the rest of the matchup.
// asked per (our def, count, their def) once a pass: the fight reads only defs
array<int> gCfPairC, gCfPairN, gCfPairK;
array<bool> gCfPairR;

bool CfCounters(int k, int c, int n, float spr)
{
	const int kd = gCfEDef[k];
	if (CfIsCom(kd) || !Catalog::gMobile[kd])
		return false;
	for (uint i = 0; i < gCfPairC.length(); ++i) {
		if ((gCfPairC[i] == c) && (gCfPairN[i] == n) && (gCfPairK[i] == kd))
			return gCfPairR[i];
	}
	array<int> one = {k};
	const float lo = gCfLostO, lt = gCfLostT;
	const bool r = !CfFight(float(n), Catalog::gDps[c], Catalog::gHealth[c], Catalog::gCostM[c], spr,
			Catalog::gMaxRange[c], 0.f, 0.f, one);
	gCfLostO = lo;
	gCfLostT = lt;
	gCfPairC.insertLast(c);
	gCfPairN.insertLast(n);
	gCfPairK.insertLast(kd);
	gCfPairR.insertLast(r);
	return r;
}

// Units of a kind a mobile threat in reach counters, and that outrun it, leave for the nearest economy of
// theirs clear of it. True when some left (the rest are read again next pass).
bool CfSplit(int g, const array<int>@ foe)
{
	array<CCircuitUnit@>@ us = gCfGT[g].GetUnits();
	if ((us is null) || (us.length() == 0))
		return false;
	array<int> defs;
	array<int> cnt;
	for (uint i = 0; i < us.length(); ++i) {
		if ((us[i] is null) || (us[i].circuitDef is null))
			continue;
		const int d = int(us[i].circuitDef.id);
		int j = defs.find(d);
		if (j < 0) {
			defs.insertLast(d);
			cnt.insertLast(0);
			j = int(defs.length()) - 1;
		}
		++cnt[j];
	}
	array<int> by(defs.length(), -1);
	bool any = false;
	for (uint j = 0; j < defs.length(); ++j) {
		const int c = defs[j];
		for (uint i = 0; i < foe.length(); ++i) {
			const int kd = gCfEDef[foe[i]];
			if (Catalog::gSpeed[c] <= Catalog::gSpeed[kd])
				continue;
			const bool oneShot = !CfIsCom(kd) && Catalog::gMobile[kd] && (Catalog::gAlpha[kd] >= Catalog::gHealth[c]);
			if (oneShot || CfCounters(foe[i], c, cnt[j], gCfGSpr[g])) {
				by[j] = foe[i];
				any = true;
				if (oneShot)
					++gCfOneShot;
				break;
			}
		}
	}
	if (!any)
		return false;
	// the countering threats, and the nearest economy of theirs out of every one's reach
	float bestD = -1.f;
	int bestE = -1;
	for (uint e = 0; e < gCfXX.length(); ++e) {
		bool clear = true;
		for (uint j = 0; (j < defs.length()) && clear; ++j) {
			if (by[j] < 0)
				continue;
			const int k = by[j];
			const int kd = gCfEDef[k];
			clear = CfDist(gCfXX[e], gCfXZ[e], gCfEX[k], gCfEZ[k])
				> Catalog::gMaxRange[kd] + Catalog::gSpeed[kd] * CF_REACT_S + gCfGSpr[g];
		}
		if (!clear)
			continue;
		const float d = CfDist(gCfXX[e], gCfXZ[e], gCfGX[g], gCfGZ[g]);
		if ((bestD < 0.f) || (d < bestD)) {
			bestD = d;
			bestE = int(e);
		}
	}
	if (bestE < 0) {
		++gCfNoEco;
		return false;
	}
	int released = 0;
	for (uint j = 0; j < defs.length(); ++j) {
		if (by[j] < 0)
			continue;
		const int k = by[j];
		const int kd = gCfEDef[k];
		gCfEcoT.insertLast(null);
		gCfEcoX.insertLast(gCfXX[bestE]);
		gCfEcoZ.insertLast(gCfXZ[bestE]);
		gCfEcoR.insertLast(Catalog::gLosR[defs[j]]);
		gCfEcoKX.insertLast(gCfEX[k]);
		gCfEcoKZ.insertLast(gCfEZ[k]);
		gCfEcoKR.insertLast(Catalog::gMaxRange[kd] + Catalog::gSpeed[kd] * CF_REACT_S);
		gCfEcoAt.insertLast(ai.frame);
		gCfEcoKDef.insertLast(kd);
		const int slot = int(gCfEcoT.length()) - 1;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ u = us[i];
			if ((u is null) || (u.circuitDef is null) || (int(u.circuitDef.id) != defs[j]) || CfClaimed(int(u.id)))
				continue;
			Market::EscortGone(u.id);
			gCfGT[g].RemoveUnit(u);
			gCfClaimId.insertLast(int(u.id));
			gCfClaimSlot.insertLast(slot);
			++released;
		}
	}
	if (released == 0)
		return false;
	++gCfSplits;
	gCfReleased += released;
	gCfGDone[g] = true;
	return true;
}

// ---- the defended point it decided not to take ----
// What stands in the ring now: count and metal of the armed enemies within it.
void CfRingNow(float x, float z, float r, int& out n, float& out m)
{
	n = 0;
	m = 0.f;
	if (gCfEDef.length() == 0)
		return;
	gCfEGrid.Query(x, z, r);
	for (uint h = 0; h < gCfEGrid.hit.length(); ++h) {
		const int k = gCfEGrid.hit[h];
		if (CfDist(gCfEX[k], gCfEZ[k], x, z) > r)
			continue;
		++n;
		m += Catalog::gCostM[gCfEDef[k]];
	}
}

void CfSetRing(int s, const array<int>@ foe, int ourN, float fbx, float fbz)
{
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < foe.length(); ++i) {
		cx += gCfEX[foe[i]];
		cz += gCfEZ[foe[i]];
	}
	cx /= float(foe.length());
	cz /= float(foe.length());
	float r = 0.f;
	for (uint i = 0; i < foe.length(); ++i) {
		const float rr = CfDist(gCfEX[foe[i]], gCfEZ[foe[i]], cx, cz) + Catalog::gMaxRange[gCfEDef[foe[i]]];
		if (rr > r)
			r = rr;
	}
	gCfEpKo[s] = true;
	gCfEpKoX[s] = cx;
	gCfEpKoZ[s] = cz;
	gCfEpKoR[s] = r;
	int n;
	float m;
	CfRingNow(cx, cz, r, n, m);
	gCfEpKoN[s] = n;
	gCfEpKoM[s] = m;
	gCfEpKoOurN[s] = ourN;
	gCfEpFX[s] = fbx;
	gCfEpFZ[s] = fbz;
	gCfEpOut[s] = false;
	++gCfKoSet;
	AIFloat3 ko(cx, 0.f, cz);
	gCfEpT[s].SetKeepOut(ko, r, ai.frame + int(CF_REACT_S * float(SECOND)));
}

// A ring holds while what stands in it and what the group is are what they were when it was decided.
bool CfRingHolds(int s, int ourN)
{
	if (!gCfEpKo[s])
		return false;
	int n;
	float m;
	CfRingNow(gCfEpKoX[s], gCfEpKoZ[s], gCfEpKoR[s], n, m);
	if ((n != gCfEpKoN[s]) || (abs(m - gCfEpKoM[s]) > 0.5f) || ((ourN >= 0) && (ourN != gCfEpKoOurN[s]))) {
		gCfEpKo[s] = false;
		++gCfKoLift;
		AIFloat3 ko(gCfEpKoX[s], 0.f, gCfEpKoZ[s]);
		gCfEpT[s].SetKeepOut(ko, 0.f, -1);
		return false;
	}
	return true;
}

// ---- the decisions ----
// A commander inside our base: every group in the base onto it if they win together, else they hold at the
// factory under the towers.
void CfBasePull()
{
	if (!Builder::gHomeSet)
		return;
	const float baseR = aiMilitaryMgr.GetBaseDefRange();
	const AIFloat3 home = Builder::gHomePos;
	for (uint k = 0; k < gCfEDef.length(); ++k) {
		if (!CfIsCom(gCfEDef[k]) || (CfDist(gCfEX[k], gCfEZ[k], home.x, home.z) > baseR))
			continue;
		const float cx = gCfEX[k], cz = gCfEZ[k];
		array<int> pool;
		float spdMax = 0.f, rngMax = 0.f;
		for (uint g = 0; g < gCfGT.length(); ++g) {
			if (gCfGDone[g] || (CfDist(gCfGX[g], gCfGZ[g], home.x, home.z) > baseR))
				continue;
			pool.insertLast(int(g));
			if (gCfGSpd[g] > spdMax) spdMax = gCfGSpd[g];
			if (gCfGRng[g] > rngMax) rngMax = gCfGRng[g];
		}
		if (pool.length() == 0)
			continue;
		array<int> foe;
		bool com;
		CfFoesNear(cx, cz, rngMax, spdMax, 0.f, foe, com);
		gCfPN = 0.f; gCfPDps = 0.f; gCfPHp = 0.f; gCfPM = 0.f; gCfPSpr = 0.f; gCfPRng = rngMax;
		for (uint i = 0; i < pool.length(); ++i) {
			const int g = pool[i];
			gCfPN += float(gCfGN[g]);
			gCfPDps += gCfGDps[g];
			gCfPHp += gCfGHp[g];
			gCfPM += gCfGM[g];
			if (gCfGSpr[g] > gCfPSpr) gCfPSpr = gCfGSpr[g];
		}
		CfPoolExtras(cx, cz, baseR);
		const bool win = CfPoolFight(foe);
		for (uint i = 0; i < pool.length(); ++i) {
			const int g = pool[i];
			if (win)
				CfVerdict(g, CF_BASE_ENGAGE, cx, cz, true, baseR);
			else
				CfVerdict(g, CF_BASE_HOLD, home.x, home.z, false, baseR);
		}
	}
}

void CfDecide(int g)
{
	const float x = gCfGX[g], z = gCfGZ[g];
	array<int> foe;
	bool com;
	CfFoesNear(x, z, gCfGRng[g], gCfGSpd[g], gCfGSpr[g], foe, com);
	// a group already split off round a threat leaves that kind to its keep-out ring
	for (uint e = 0; e < gCfEcoT.length(); ++e) {
		if (!(gCfEcoT[e] is gCfGT[g]))
			continue;
		for (int i = int(foe.length()) - 1; i >= 0; --i) {
			if (gCfEDef[foe[i]] == gCfEcoKDef[e])
				foe.removeAt(uint(i));
		}
		break;
	}
	int s = CfEpSlot(gCfGT[g]);
	if (foe.length() == 0) {
		if ((s >= 0) && gCfEpKo[s])
			gCfEpOut[s] = true;
		return;
	}
	++gCfInReach;
	if (com)
		++gCfComReach;
	const float r = gCfGRng[g] + gCfGSpd[g] * CF_REACT_S + gCfGSpr[g];
	float tx, tz;
	CfNearestFoe(foe, x, z, tx, tz);
	// engaged and in contact, the fight is fought out (doctrine: a committed push punches through)
	if ((s >= 0) && gCfEpLatch[s] && (gCfEpV[s] == CF_ENGAGE)) {
		CfVerdict(g, CF_ENGAGE, tx, tz, gCfEpPW[s], r);
		return;
	}
	// decided once per approach: a ring that still holds keeps the group out of it
	if ((s >= 0) && CfRingHolds(s, gCfGN[g])) {
		++gCfKoKept;
		if (CfDist(x, z, gCfEpKoX[s], gCfEpKoZ[s]) <= gCfEpKoR[s] + gCfGSpd[g] * CF_REACT_S + gCfGSpr[g]) {
			if (gCfEpOut[s])
				++gCfDither;
			gCfEpOut[s] = false;
			CfVerdict(g, CF_FALL, gCfEpFX[s], gCfEpFZ[s], false, r);
		} else {
			gCfEpOut[s] = true;
			gCfGDone[g] = true;
		}
		return;
	}
	if (CfSplit(g, foe))
		return;
	CfPoolAt(x, z, g);
	if (CfPoolFight(foe)) {
		CfVerdict(g, CF_ENGAGE, tx, tz, true, r);
		s = CfEpSlot(gCfGT[g]);
		if ((s >= 0) && (CfDist(tx, tz, x, z) <= gCfGRng[g] + gCfGSpr[g]))
			gCfEpLatch[s] = true;
		return;
	}
	const float lostO = gCfLostO, lostT = gCfLostT;
	float fx = 0.f, fz = 0.f;
	for (uint i = 0; i < foe.length(); ++i) {
		fx += gCfEX[foe[i]];
		fz += gCfEZ[foe[i]];
	}
	fx /= float(foe.length());
	fz /= float(foe.length());
	const float myD = CfDist(fx, fz, x, z);
	// candidates: other groups, our towers; only ones further from them than we are
	array<float> cx, cz, cd;
	array<bool> cg;
	for (uint o = 0; o < gCfGT.length(); ++o) {
		if ((int(o) == g) || (CfDist(gCfGX[o], gCfGZ[o], fx, fz) <= myD))
			continue;
		cx.insertLast(gCfGX[o]); cz.insertLast(gCfGZ[o]); cd.insertLast(CfDist(gCfGX[o], gCfGZ[o], x, z));
		cg.insertLast(true);
	}
	Market::ComTowersFill();
	for (uint w = 0; w < Market::gCdTwPos.length(); ++w) {
		const AIFloat3 tp = Market::gCdTwPos[w];
		if (CfDist(tp.x, tp.z, fx, fz) <= myD)
			continue;
		cx.insertLast(tp.x); cz.insertLast(tp.z); cd.insertLast(CfDist(tp.x, tp.z, x, z));
		cg.insertLast(false);
	}
	float fbx = x, fbz = z;
	int v = 0;
	// nearest first, at most six asked (each one a fight on paper)
	for (int tries = 0; (tries < 6) && (v == 0); ++tries) {
		int bi = -1;
		for (uint i = 0; i < cd.length(); ++i) {
			if ((cd[i] >= 0.f) && ((bi < 0) || (cd[i] < cd[bi])))
				bi = int(i);
		}
		if (bi < 0)
			break;
		cd[bi] = -1.f;
		CfPoolAt(cx[bi], cz[bi], g);
		if (CfPoolFight(foe)) {
			v = CF_FALL;
			fbx = cx[bi];
			fbz = cz[bi];
			if (cg[bi])
				++gCfMerged;
		}
	}
	gCfLostO = lostO;
	gCfLostT = lostT;
	if ((v == 0) && Builder::gHomeSet
		&& (CfDist(Builder::gHomePos.x, Builder::gHomePos.z, x, z) > gCfGRng[g] + gCfGSpr[g])
		&& (CfDist(Builder::gHomePos.x, Builder::gHomePos.z, fx, fz) > myD))
	{
		v = CF_HOME;
		fbx = Builder::gHomePos.x;
		fbz = Builder::gHomePos.z;
	}
	if (v == 0) {
		++gCfHold;
		return;
	}
	CfVerdict(g, v, fbx, fbz, false, r);
	s = CfEpSlot(gCfGT[g]);
	if (s >= 0)
		CfSetRing(s, foe, gCfGN[g], fbx, fbz);
}

void CfEndEpisodes()
{
	for (int i = int(gCfEpT.length()) - 1; i >= 0; --i) {
		const bool dead = gCfEpT[i].IsDead();
		if (!dead && gCfEpKo[i] && CfRingHolds(i, -1)) {
			AIFloat3 ko(gCfEpKoX[i], 0.f, gCfEpKoZ[i]);
			gCfEpT[i].SetKeepOut(ko, gCfEpKoR[i], ai.frame + int(CF_REACT_S * float(SECOND)));
			continue;
		}
		if (!dead && (ai.frame - gCfEpLast[i] < 5 * SECOND))
			continue;
		++gCfEpN;
		if (gCfEpPW[i])
			++gCfEpPredW;
		gCfEpLostM += gCfEpLost[i];
		gCfEpKillM += gCfEpKill[i];
		gCfEpPredL += gCfEpPL[i];
		gCfEpPredK += gCfEpPK[i];
		CfEpDrop(i);
	}
}

// ---- the census ----
// Moving state of our dying combat units, from the position sampled a pass before.
array<float> gCfPX;
array<float> gCfPZ;
array<int> gCfPF;

void CfSamplePositions()
{
	if (gCfPF.length() == 0) {
		gCfPX.resize(32001);
		gCfPZ.resize(32001);
		gCfPF.resize(32001);
	}
	for (uint i = 0; i < gCombatId.length(); ++i) {
		const int id = gCombatId[i];
		if ((id < 0) || (id > 32000))
			continue;
		CCircuitUnit@ u = ai.GetTeamUnit(Id(id));
		if (u is null)
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		gCfPX[id] = p.x;
		gCfPZ[id] = p.z;
		gCfPF[id] = ai.frame;
	}
}

void CfNoteDeath(CCircuitUnit@ unit, const CCircuitDef@ atk)
{
	if (!CfOn() || (unit is null) || (unit.circuitDef is null))
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	if (!cdef.IsMobile() || (!WantsMassing(cdef) && !IsFodder(cdef)))
		return;
	const int d = int(cdef.id);
	const AIFloat3 at = unit.GetPos(ai.frame);
	const int id = int(unit.id);
	int ms = 4;
	if ((id >= 0) && (id < int(gCfPF.length())) && (gCfPF[id] > 0) && (ai.frame - gCfPF[id] <= 2 * SECOND)
		&& (ai.frame > gCfPF[id]) && Builder::gHomeSet)
	{
		const float dx = at.x - gCfPX[id], dz = at.z - gCfPZ[id];
		const float len = sqrt(dx * dx + dz * dz);
		const float v = len * float(SECOND) / float(ai.frame - gCfPF[id]);
		if ((v < 0.1f * Catalog::gSpeed[d]) || (len < 1.f)) {
			ms = 0;
		} else {
			AIFloat3 h = Builder::gHomePos - at;
			h.SafeNormalize2D();
			const float c = (dx * h.x + dz * h.z) / len;
			ms = (c > 0.5f) ? 1 : ((c < -0.5f) ? 2 : 3);
		}
	}
	++gCfMove[ms];
	int kc = 4;
	if (atk !is null) {
		const int a = int(atk.id);
		if (!Catalog::ValidId(a))
			kc = 3;
		else if (CfIsCom(a))
			kc = 0;
		else if (!atk.IsMobile())
			kc = 1;
		else if (Catalog::gAoe[a] > 16.f * float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]))
			kc = 2;
		else
			kc = 3;
	}
	gCfKiller[kc] += Catalog::gCostM[d];
	IUnitTask@ t = unit.task;
	if (t is null)
		return;
	const int s = CfEpSlot(t);
	if (s >= 0)
		gCfEpLost[s] += Catalog::gCostM[d];
}

void CfNoteEnemyDeath(const CCircuitDef@ edef, const AIFloat3& in pos, bool byUs)
{
	if (!CfOn() || (edef is null))
		return;
	for (uint i = 0; i < gCfEpT.length(); ++i) {
		if (CfDist(gCfEpX[i], gCfEpZ[i], pos.x, pos.z) <= gCfEpR[i]) {
			gCfEpKill[i] += edef.costM;
			break;
		}
	}
	if (byUs) {
		for (uint s = 0; s < gCfEcoT.length(); ++s) {
			if ((gCfEcoT[s] !is null) && (CfDist(gCfEcoX[s], gCfEcoZ[s], pos.x, pos.z) <= gCfEcoR[s] * 2.f)) {
				gCfEcoKillM += edef.costM;
				break;
			}
		}
		if (edef.IsRoleAny(Unit::Role::COMM.mask))
			++gCfComKills;
	}
}

void CfLog()
{
	if (ai.frame < gCfNextLog)
		return;
	gCfNextLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: comfight-stat t=" + ai.teamId
		+ " inReach=" + gCfInReach + " comReach=" + gCfComReach
		+ " engage=" + gCfEngage + " fall=" + gCfFall + " merged=" + gCfMerged + " home=" + gCfHome
		+ " hold=" + gCfHold + " base=" + gCfBaseW + "/" + gCfBaseL + " flips=" + gCfFlips
		+ " | ring set=" + gCfKoSet + " kept=" + gCfKoKept + " lifted=" + gCfKoLift + " dither=" + gCfDither
		+ " | split=" + gCfSplits + " released=" + gCfReleased + " oneShot=" + gCfOneShot + " noEco=" + gCfNoEco
		+ " ecoKilled=" + int(gCfEcoKillM)
		+ " | ep=" + gCfEpN + " predW=" + gCfEpPredW + " predLost=" + int(gCfEpPredL) + " lost=" + int(gCfEpLostM)
		+ " predKill=" + int(gCfEpPredK) + " killed=" + int(gCfEpKillM) + " comKills=" + gCfComKills
		+ " | move still=" + gCfMove[0] + " retreat=" + gCfMove[1] + " advance=" + gCfMove[2]
		+ " lateral=" + gCfMove[3] + " unk=" + gCfMove[4]
		+ " | lostBy com=" + int(gCfKiller[0]) + " tower=" + int(gCfKiller[1]) + " splash=" + int(gCfKiller[2])
		+ " other=" + int(gCfKiller[3]) + " unseen=" + int(gCfKiller[4])
		+ " | foes=" + gCfEDef.length() + " eco=" + gCfXX.length() + " groups=" + gCfGT.length()
		+ " us=" + int((gCfCalls > 0) ? gCfUs / double(gCfCalls) : 0.0) + "/" + int(gCfMaxUs));
	gCfInReach = 0; gCfComReach = 0; gCfEngage = 0; gCfFall = 0; gCfMerged = 0; gCfHome = 0; gCfHold = 0;
	gCfBaseW = 0; gCfBaseL = 0; gCfFlips = 0; gCfKoSet = 0; gCfKoKept = 0; gCfKoLift = 0; gCfDither = 0;
	gCfEpN = 0; gCfEpPredW = 0; gCfComKills = 0; gCfSplits = 0; gCfReleased = 0; gCfOneShot = 0; gCfNoEco = 0;
	gCfEpLostM = 0.f; gCfEpKillM = 0.f; gCfEpPredL = 0.f; gCfEpPredK = 0.f; gCfEcoKillM = 0.f;
	for (uint i = 0; i < 5; ++i) {
		gCfMove[i] = 0;
		gCfKiller[i] = 0.f;
	}
	gCfUs = 0.0; gCfMaxUs = 0.0; gCfCalls = 0;
}

void UpdateComFight()
{
	if (!CfOn())
		return;
	const double t0 = ai.ClockUs();
	CfSamplePositions();
	CfScanStep();
	CfReadDGun();
	CfReadGroups();
	gCfPairC.resize(0);
	gCfPairN.resize(0);
	gCfPairK.resize(0);
	gCfPairR.resize(0);
	CfEcoRefresh();
	CfBasePull();
	for (uint g = 0; g < gCfGT.length(); ++g) {
		if (!gCfGDone[g])
			CfDecide(int(g));
	}
	CfEndEpisodes();
	const double us = ai.ClockUs() - t0;
	gCfUs += us;
	if (us > gCfMaxUs)
		gCfMaxUs = us;
	++gCfCalls;
	CfLog();
}

}  // namespace Military
