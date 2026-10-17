namespace Military {

//------------------------------------------------------------------------------
// ONE FIGHT ESTIMATE PER GROUP (apex_com_fight; his 2026-10-16: pawns and grunts early "and don't just lose
// them straight to the enemy commander", "you have to push with that much army", "commit with enough people or
// just stay away from it", "pawns/grunts don't engage those targets", "the thugs should be fighting the Janus
// and the pawns go around", "we lose entire mex areas due to those fallbacks", "if they have a blob army we
// need to match it ... defeating the enemy in detail").
// Every second each ground squad of ours with an armed enemy in reach -- army, commanders, and the towers that
// reach where it stands to fight -- is fought out on paper with focus fire both ways: their splash on every unit
// of ours its blast covers at the blast's mean falloff, a shot bigger than a unit spent on that unit, a
// commander's regeneration and the D-gun shots our own energy says a commander can afford once it closes.
// The paper is calibrated: real over predicted metal, lost and killed apart, over every fight our team took.
//  - Units a mobile threat one-shots or beats head-on, and that outrun it, leave the group for a raid on the
//    nearest economy of theirs they win at.
//  - The group fights while (calibrated loss - calibrated kill) is under what falling back abandons: our
//    metal in the threat's reach, the open spots' race there (as much as the fight destroys of them), and the
//    walk out and back. Each verdict moves only past the estimate's own measured error band.
//  - One that does not walks to the nearest friendly group, tower or home where the pooled estimate pays;
//    against their largest group every one of ours falls back onto the same point and fights it together.
//  - An attack group out of contact walks onto their group it beats by more than the error band, best
//    metal killed per second of walk and fight (defeat in detail).
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
array<float> gCfXH;
array<float> gCfYX;
array<float> gCfYZ;
array<float> gCfYM;
array<float> gCfYH;
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
		gCfYX.resize(0); gCfYZ.resize(0); gCfYM.resize(0); gCfYH.resize(0);
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
			gCfYH.insertLast(Catalog::gHealth[d]);
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
	gCfXH = gCfYH;
	gCfEReach = gCfNReach;
	gCfEGrid.Begin(512.f, 0.f, 0.f, float(AiTerrainWidth()), float(AiTerrainHeight()));
	for (uint k = 0; k < gCfEDef.length(); ++k)
		gCfEGrid.Add(gCfEX[k], gCfEZ[k]);
	CfCluster();
}

// ---- their groups: armed mobiles that can back each other within one reaction ----
array<int> gCfFcOf;          // per armed foe, its group; -1 for a static one
array<float> gCfFcM, gCfFcX, gCfFcZ;
array<int> gCfFcN;
array<float> gCfFcSpd;     // its slowest member: what can be caught
int gCfBlob = -1;            // their largest group by metal

int CfRoot(array<int>& par, int i)
{
	while (par[i] != i) {
		par[i] = par[par[i]];
		i = par[i];
	}
	return i;
}

void CfCluster()
{
	const int n = int(gCfEDef.length());
	gCfFcOf.resize(n);
	gCfFcM.resize(0); gCfFcX.resize(0); gCfFcZ.resize(0); gCfFcN.resize(0); gCfFcSpd.resize(0);
	gCfBlob = -1;
	array<int> par(n);
	for (int i = 0; i < n; ++i)
		par[i] = i;
	for (int i = 0; i < n; ++i) {
		const int di = gCfEDef[i];
		if (!Catalog::gMobile[di])
			continue;
		const float ri = Catalog::gMaxRange[di], si = Catalog::gSpeed[di];
		gCfEGrid.Query(gCfEX[i], gCfEZ[i], ri + si * CF_REACT_S + gCfEReach);
		for (uint h = 0; h < gCfEGrid.hit.length(); ++h) {
			const int j = gCfEGrid.hit[h];
			if ((j <= i) || (j >= n))
				continue;
			const int dj = gCfEDef[j];
			if (!Catalog::gMobile[dj])
				continue;
			const float rj = Catalog::gMaxRange[dj];
			const float link = ((ri > rj) ? ri : rj) + (si + Catalog::gSpeed[dj]) * CF_REACT_S;
			if (CfDist(gCfEX[i], gCfEZ[i], gCfEX[j], gCfEZ[j]) > link)
				continue;
			const int a = CfRoot(par, i), b = CfRoot(par, j);
			if (a != b)
				par[b] = a;
		}
	}
	array<int> idOf(n, -1);
	for (int i = 0; i < n; ++i) {
		const int d = gCfEDef[i];
		if (!Catalog::gMobile[d]) {
			gCfFcOf[i] = -1;
			continue;
		}
		const int rt = CfRoot(par, i);
		if (idOf[rt] < 0) {
			idOf[rt] = int(gCfFcM.length());
			gCfFcM.insertLast(0.f); gCfFcX.insertLast(0.f); gCfFcZ.insertLast(0.f); gCfFcN.insertLast(0); gCfFcSpd.insertLast(Catalog::gSpeed[d]);
		}
		const int c = idOf[rt];
		gCfFcOf[i] = c;
		const float m = Catalog::gCostM[d];
		gCfFcM[c] += m;
		gCfFcX[c] += gCfEX[i] * m;
		gCfFcZ[c] += gCfEZ[i] * m;
		++gCfFcN[c];
		if (Catalog::gSpeed[d] < gCfFcSpd[c])
			gCfFcSpd[c] = Catalog::gSpeed[d];
	}
	for (uint c = 0; c < gCfFcM.length(); ++c) {
		if (gCfFcM[c] > 0.f) {
			gCfFcX[c] /= gCfFcM[c];
			gCfFcZ[c] /= gCfFcM[c];
		}
		if ((gCfBlob < 0) || (gCfFcM[c] > gCfFcM[gCfBlob]))
			gCfBlob = int(c);
	}
	if ((gCfBlob >= 0) && (gCfFcM[gCfBlob] > gCfTheirMaxM))
		gCfTheirMaxM = gCfFcM[gCfBlob];
}

bool CfHasBlob(const array<int>@ foe)
{
	if (gCfBlob < 0)
		return false;
	for (uint i = 0; i < foe.length(); ++i) {
		if ((foe[i] < int(gCfFcOf.length())) && (gCfFcOf[foe[i]] == gCfBlob))
			return true;
	}
	return false;
}

// ---- our ground squads, read each pass ----
array<IUnitTask@> gCfGT;
array<float> gCfGX, gCfGZ, gCfGDps, gCfGHp, gCfGM, gCfGRng, gCfGSpd, gCfGSpr;
array<int> gCfGN;
array<bool> gCfGDone;
// a group walking to a fall-back point counts where it is going
array<bool> gCfGFall;
array<float> gCfGFX, gCfGFZ;

void CfReadGroups()
{
	gCfGT.resize(0); gCfGX.resize(0); gCfGZ.resize(0); gCfGDps.resize(0); gCfGHp.resize(0); gCfGM.resize(0);
	gCfGRng.resize(0); gCfGSpd.resize(0); gCfGSpr.resize(0); gCfGN.resize(0); gCfGDone.resize(0);
	gCfGFall.resize(0); gCfGFX.resize(0); gCfGFZ.resize(0);
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
		const int s = CfEpSlot(t);
		const bool falling = (s >= 0) && (gCfEpV[s] == CF_FALL);
		gCfGFall.insertLast(falling);
		gCfGFX.insertLast(falling ? gCfEpFX[s] : cx);
		gCfGFZ.insertLast(falling ? gCfEpFZ[s] : cz);
	}
	// our largest group, as pooled
	for (uint g = 0; g < gCfGT.length(); ++g) {
		float m = 0.f;
		for (uint o = 0; o < gCfGT.length(); ++o) {
			if (CfDist(gCfGX[o], gCfGZ[o], gCfGX[g], gCfGZ[g]) <= gCfGRng[o] + gCfGSpd[o] * CF_REACT_S + gCfGSpr[o])
				m += gCfGM[o];
		}
		if (m > gCfOurMaxM)
			gCfOurMaxM = m;
	}
}

// ---- the estimate: focus fire both ways, event by event ----
float gCfDgCost = 0.f;
float gCfDgReload = 0.f;
float gCfDgRange = 0.f;
float gCfLostO = 0.f;
float gCfLostT = 0.f;
float gCfLostTMob = 0.f;
float gCfSimT = 0.f;

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

// The units of ours a shell with this blast radius damages, in units of a full hit, in a group of n spread over
// spr: the struck one, and the rest at the blast's mean linear falloff (edgeEffectiveness 0, the engine default:
// a third over the disc it covers).
float CfCovered(float aoe, int n, float spr)
{
	if ((aoe <= 0.f) || (n <= 1))
		return 1.f;
	float f;
	if (spr <= aoe)
		f = 1.f - 2.f * spr / (3.f * aoe);
	else
		f = aoe * aoe / (3.f * spr * spr);
	return 1.f + float(n - 1) * f;
}

// A foe's damage per second against units of hp h in a group of n over spr: every unit its blast reaches, and a
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
// Their side: unit defs, nearest the fight first; a commander's first D-gun no sooner than dgT0.
// True when every one of them dies first. Lost metal both ways, their mobile part, and the time it took.
bool CfSim(float nOf, float dO, float hO, float mO, float spr, float rngO, float twDps, float twHp,
		const array<int>@ defs, float dgT0)
{
	gCfLostO = 0.f;
	gCfLostT = 0.f;
	gCfLostTMob = 0.f;
	gCfSimT = 0.f;
	const int nT = int(defs.length());
	if (nT == 0)
		return true;
	int nO = int(floor(nOf + 0.5f));
	if (nO < 1)
		nO = 1;
	float sumT = 0.f, sumTs = 0.f, comSpd = 0.f;
	int coms = 0;
	for (int k = 0; k < nT; ++k) {
		const int d = defs[k];
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
	float hpT = Catalog::gHealth[defs[0]];
	float t = 0.f;
	float nextDg = (coms > 0) ? dgT0 : 1e9f;
	for (int iter = 0; iter < 512; ++iter) {
		if (it >= nT) {
			gCfSimT = t;
			return true;
		}
		if ((io >= nO) && !twAlive)
			break;
		const int d = defs[it];
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
			if (Catalog::gMobile[d])
				gCfLostTMob += Catalog::gCostM[d];
			sumT -= Catalog::gDps[d];
			sumTs -= CfEffDps(d, hO, nO, spr);
			if (com) {
				--coms;
				if (coms <= 0)
					nextDg = 1e9f;
			}
			++it;
			if (it < nT)
				hpT = Catalog::gHealth[defs[it]];
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
	gCfSimT = t;
	return false;
}

// The same fight against foe indices of the registry.
bool CfFight(float nOf, float dO, float hO, float mO, float spr, float rngO, float twDps, float twHp,
		const array<int>@ ord, float dgT0)
{
	array<int> defs(ord.length());
	for (uint k = 0; k < ord.length(); ++k)
		defs[k] = gCfEDef[ord[k]];
	return CfSim(nOf, dO, hO, mO, spr, rngO, twDps, twHp, defs, dgT0);
}

// When a commander among them can first D-gun a group standing at (x, z) over spr: its walk to reach.
float CfDgT0(const array<int>@ foe, float x, float z, float spr)
{
	float best = -1.f;
	for (uint i = 0; i < foe.length(); ++i) {
		const int k = foe[i];
		const int d = gCfEDef[k];
		if (!CfIsCom(d))
			continue;
		float gap = CfDist(gCfEX[k], gCfEZ[k], x, z) - gCfDgRange - spr;
		if (gap < 0.f)
			gap = 0.f;
		const float sp = Catalog::gSpeed[d];
		const float t = (sp > 0.f) ? gap / sp : ((gap > 0.f) ? 1e9f : 0.f);
		if ((best < 0.f) || (t < best))
			best = t;
	}
	return (best >= 0.f) ? best : 0.f;
}

// Where a group at (x, z) stands to fight a target at (tx, tz) with its range.
void CfStandAt(float x, float z, float tx, float tz, float rng, float& out sx, float& out sz)
{
	const float d = CfDist(x, z, tx, tz);
	if (d <= rng) {
		sx = x;
		sz = z;
		return;
	}
	const float f = rng / d;
	sx = tx + (x - tx) * f;
	sz = tz + (z - tz) * f;
}

// A tower fires only on what comes inside its range: it counts where the group stands to fight.
void CfDropFarStatics(array<int>& foe, float sx, float sz, float spr)
{
	for (int i = int(foe.length()) - 1; i >= 0; --i) {
		const int k = foe[i];
		const int d = gCfEDef[k];
		if (Catalog::gMobile[d])
			continue;
		if (CfDist(gCfEX[k], gCfEZ[k], sx, sz) > Catalog::gMaxRange[d] + spr)
			foe.removeAt(uint(i));
	}
}

// ---- calibration: real over predicted metal, per side, over every settled fight our team took ----
const array<string> CF_CAL_KEYS = {"cfN", "cfPL", "cfAL", "cfPL2", "cfAL2", "cfXL", "cfPK", "cfAK", "cfPK2", "cfAK2", "cfXK"};
array<float> gCfCalS(11, 0.f);   // this seat's sums
array<float> gCfCalT(11, 0.f);   // the team's
int gCfCalAt = -1;
float gCfRL = 1.f, gCfRK = 1.f, gCfSL = 1.f, gCfSK = 1.f;

// One side's running ratio and the calibrated estimate's relative error. The prior is one pseudo-fight of the
// mean size whose real equals its predicted (the ratio starts at 1) and whose error is all of it (the band
// starts at the whole estimate).
void CfCalSide(float n, float P, float A, float P2, float A2, float X, float& out r, float& out s)
{
	r = 1.f;
	s = 1.f;
	if (n < 1.f)
		return;
	const float m = (P + A) / (2.f * n);
	if (P + m > 0.f)
		r = (A + m) / (P + m);
	float rss = A2 - 2.f * r * X + r * r * P2;
	if (rss < 0.f)
		rss = 0.f;
	const float pm = r * m;
	const float den = r * r * P2 + pm * pm;
	if (den > 0.f)
		s = sqrt((rss + pm * pm) / den);
}

void CfCalRead()
{
	if (gCfCalAt == ai.frame)
		return;
	gCfCalAt = ai.frame;
	for (uint k = 0; k < gCfCalS.length(); ++k)
		gCfCalT[k] = gCfCalS[k];
	array<Id>@ mates = ai.GetTeamIds();
	if (mates !is null) {
		for (uint i = 0; i < mates.length(); ++i) {
			const int tm = int(mates[i]);
			if (tm == ai.teamId)
				continue;
			for (uint k = 0; k < gCfCalS.length(); ++k)
				gCfCalT[k] += ai.ReadTeamValue(tm, CF_CAL_KEYS[k], 0.f);
		}
	}
	CfCalSide(gCfCalT[0], gCfCalT[1], gCfCalT[2], gCfCalT[3], gCfCalT[4], gCfCalT[5], gCfRL, gCfSL);
	CfCalSide(gCfCalT[0], gCfCalT[6], gCfCalT[7], gCfCalT[8], gCfCalT[9], gCfCalT[10], gCfRK, gCfSK);
}

void CfCalAdd(float pl, float al, float pk, float ak)
{
	gCfCalS[0] += 1.f;
	gCfCalS[1] += pl; gCfCalS[2] += al; gCfCalS[3] += pl * pl; gCfCalS[4] += al * al; gCfCalS[5] += pl * al;
	gCfCalS[6] += pk; gCfCalS[7] += ak; gCfCalS[8] += pk * pk; gCfCalS[9] += ak * ak; gCfCalS[10] += pk * ak;
	for (uint k = 0; k < gCfCalS.length(); ++k)
		ai.PublishTeamValue(CF_CAL_KEYS[k], gCfCalS[k]);
}

// Fight or not, given the cost of fighting over falling back (X) and its error band. A verdict in force moves
// only once the estimate is past it by the band.
bool CfFightCond(float X, float band, int prev)
{
	if ((prev == CF_ENGAGE) || (prev == CF_BASE_ENGAGE))
		return X <= band;
	if ((prev == CF_FALL) || (prev == CF_HOME) || (prev == CF_BASE_HOLD))
		return X < -band;
	return X <= 0.f;
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
// a fight taken: predicted shares summed over its segments, what was lost while not engaged
array<bool> gCfEpRec, gCfEpMain;
array<float> gCfEpLostF;
// the open segment: its estimate (loss, kill, seconds), contact seconds so far, the group and foe metal it was
// taken at and its error band
array<bool> gCfEpSOn;
array<float> gCfEpSL, gCfEpSK, gCfEpST, gCfEpSA, gCfEpSGM, gCfEpSFM, gCfEpSB;
array<int> gCfEpSAt;

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
	gCfEpRec.insertLast(false); gCfEpMain.insertLast(false); gCfEpLostF.insertLast(0.f);
	gCfEpSOn.insertLast(false); gCfEpSL.insertLast(0.f); gCfEpSK.insertLast(0.f); gCfEpST.insertLast(0.f);
	gCfEpSA.insertLast(0.f); gCfEpSGM.insertLast(0.f); gCfEpSFM.insertLast(0.f); gCfEpSB.insertLast(0.f);
	gCfEpSAt.insertLast(ai.frame);
	return int(gCfEpT.length()) - 1;
}

void CfEpDrop(int i)
{
	gCfEpT.removeAt(i); gCfEpV.removeAt(i); gCfEpPW.removeAt(i); gCfEpPL.removeAt(i); gCfEpPK.removeAt(i);
	gCfEpLost.removeAt(i); gCfEpKill.removeAt(i); gCfEpX.removeAt(i); gCfEpZ.removeAt(i); gCfEpR.removeAt(i);
	gCfEpLast.removeAt(i); gCfEpLatch.removeAt(i); gCfEpKo.removeAt(i); gCfEpKoX.removeAt(i);
	gCfEpKoZ.removeAt(i); gCfEpKoR.removeAt(i); gCfEpKoM.removeAt(i); gCfEpFX.removeAt(i); gCfEpFZ.removeAt(i);
	gCfEpKoN.removeAt(i); gCfEpKoOurN.removeAt(i); gCfEpOut.removeAt(i);
	gCfEpRec.removeAt(i); gCfEpMain.removeAt(i); gCfEpLostF.removeAt(i);
	gCfEpSOn.removeAt(i); gCfEpSL.removeAt(i); gCfEpSK.removeAt(i); gCfEpST.removeAt(i); gCfEpSA.removeAt(i);
	gCfEpSGM.removeAt(i); gCfEpSFM.removeAt(i); gCfEpSB.removeAt(i); gCfEpSAt.removeAt(i);
}

// ---- segments: a prediction covers the fight from the state it was taken in. While engaged, a change in our
// group's metal or the enemy metal in reach beyond the estimate's error band closes the segment at the share of
// its predicted duration spent in contact and opens a new one; an episode that ends engaged counts its open
// segment whole. Outcomes count only while engaged, so both sides cover the same fight. ----
int gCfSegOpen = 0, gCfSegCut = 0;
float gCfSegCutL = 0.f, gCfSegCutK = 0.f;

void CfSegOpen(int s, float pl, float pk, float T, float gm, float fm)
{
	gCfEpSOn[s] = true;
	gCfEpSL[s] = pl;
	gCfEpSK[s] = pk;
	gCfEpST[s] = T;
	gCfEpSA[s] = 0.f;
	gCfEpSGM[s] = gm;
	gCfEpSFM[s] = fm;
	gCfEpSB[s] = sqrt(gCfSL * gCfRL * pl * gCfSL * gCfRL * pl + gCfSK * gCfRK * pk * gCfSK * gCfRK * pk);
	gCfEpSAt[s] = ai.frame;
	++gCfSegOpen;
}

void CfSegStep(int s, bool contact)
{
	float dt = float(ai.frame - gCfEpSAt[s]) / float(SECOND);
	if (dt > 2.f * CF_REACT_S)
		dt = 2.f * CF_REACT_S;
	if (contact && (dt > 0.f))
		gCfEpSA[s] += dt;
	gCfEpSAt[s] = ai.frame;
}

void CfSegClose(int s, bool whole)
{
	if (!gCfEpSOn[s])
		return;
	float f = 1.f;
	if (!whole && (gCfEpST[s] > 0.f)) {
		f = gCfEpSA[s] / gCfEpST[s];
		if (f > 1.f)
			f = 1.f;
	}
	gCfEpPL[s] += f * gCfEpSL[s];
	gCfEpPK[s] += f * gCfEpSK[s];
	if (!whole) {
		++gCfSegCut;
		gCfSegCutL += (1.f - f) * gCfEpSL[s];
		gCfSegCutK += (1.f - f) * gCfEpSK[s];
	}
	gCfEpSOn[s] = false;
}

bool CfSegStale(int s, float gm, float fm)
{
	return !gCfEpSOn[s] || (abs(gm - gCfEpSGM[s]) + abs(fm - gCfEpSFM[s]) > gCfEpSB[s]);
}

float CfFoeMetal(const array<int>@ foe)
{
	float m = 0.f;
	for (uint i = 0; i < foe.length(); ++i)
		m += Catalog::gCostM[gCfEDef[foe[i]]];
	return m;
}

// in contact: some foe within the longer of the two ranges of the group's edge
bool CfContact(int g, const array<int>@ foe)
{
	for (uint i = 0; i < foe.length(); ++i) {
		const int k = foe[i];
		const float er = Catalog::gMaxRange[gCfEDef[k]];
		const float rr = ((er > gCfGRng[g]) ? er : gCfGRng[g]) + gCfGSpr[g];
		if (CfDist(gCfEX[k], gCfEZ[k], gCfGX[g], gCfGZ[g]) <= rr)
			return true;
	}
	return false;
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
// the calibrated decision's minute
int gCfFlipEF = 0, gCfBandHeld = 0, gCfByStake = 0, gCfFallDec = 0, gCfEngDec = 0, gCfAsmSet = 0, gCfAsmJoin = 0;
int gCfTakenMain = 0, gCfTakenIso = 0, gCfHunts = 0, gCfFallEp = 0, gCfRecEp = 0;
float gCfTakenMainM = 0.f, gCfTakenIsoM = 0.f, gCfFallLostM = 0.f;
float gCfDecNet = 0.f, gCfDecStake = 0.f, gCfDecRetake = 0.f, gCfDecSave = 0.f;
float gCfTheirMaxM = 0.f, gCfOurMaxM = 0.f;
array<int> gCfPackOld(6, 0);    // raid GOs by pack size 1..6+: the old loss model's
array<int> gCfPackNew(6, 0);    // ...and the calibrated one's
int gCfPackAsk = 0;

void CfNotePack(int n, bool oldGo, bool newGo)
{
	++gCfPackAsk;
	int b = n - 1;
	if (b < 0)
		b = 0;
	if (b > 5)
		b = 5;
	if (oldGo)
		++gCfPackOld[b];
	if (newGo)
		++gCfPackNew[b];
}

bool CfIsEngage(int v)
{
	return (v == CF_ENGAGE) || (v == CF_BASE_ENGAGE);
}

// pl, pk: this group's share of the pooled fight's predicted loss and kill over segT seconds (segT < 0: no fresh
// estimate this pass); fm: the enemy metal in reach
void CfVerdict(int g, int v, float tx, float tz, bool predWin, float r, float pl, float pk, bool vsMain,
		float segT = -1.f, float fm = 0.f, bool contact = true)
{
	IUnitTask@ t = gCfGT[g];
	AIFloat3 to(tx, 0.f, tz);
	to.y = ai.GetElevationAt(to);
	t.SetScriptMove(to, ai.frame + int(CF_REACT_S * float(SECOND)), CfIsEngage(v));
	gCfGDone[g] = true;
	int s = CfEpSlot(t);
	if (s < 0) {
		s = CfEpNew(t);
		gCfEpPW[s] = predWin;
	} else if ((gCfEpV[s] != 0) && (gCfEpV[s] != v)) {
		++gCfFlips;
		if (CfIsEngage(gCfEpV[s]) != CfIsEngage(v))
			++gCfFlipEF;
	}
	if (CfIsEngage(v) && !gCfEpRec[s]) {
		gCfEpRec[s] = true;
		gCfEpPW[s] = predWin;
		gCfEpPL[s] = 0.f;
		gCfEpPK[s] = 0.f;
		gCfEpMain[s] = vsMain;
		gCfEpLost[s] = 0.f;
		gCfEpKill[s] = 0.f;
		if (segT >= 0.f)
			CfSegOpen(s, pl, pk, segT, gCfGM[g], fm);
		if (vsMain) {
			++gCfTakenMain;
			gCfTakenMainM += gCfGM[g];
		} else {
			++gCfTakenIso;
			gCfTakenIsoM += gCfGM[g];
		}
	} else if (gCfEpRec[s]) {
		if (gCfEpSOn[s])
			CfSegStep(s, contact && CfIsEngage(gCfEpV[s]));
		if (!CfIsEngage(v)) {
			CfSegClose(s, false);
		} else if ((segT >= 0.f) && CfSegStale(s, gCfGM[g], fm)) {
			CfSegClose(s, false);
			CfSegOpen(s, pl, pk, segT, gCfGM[g], fm);
		}
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

// Our strength standing at (x, z): every group within its own reach of it or walking to it, the towers covering
// it and our allies' army there at our metal's dps and hp. `with` counts wherever it stands (the one walking in).
float gCfPN = 0.f, gCfPDps = 0.f, gCfPHp = 0.f, gCfPM = 0.f, gCfPSpr = 0.f, gCfPRng = 0.f, gCfPTwD = 0.f, gCfPTwH = 0.f;
void CfPoolAt(float x, float z, int with)
{
	gCfPN = 0.f; gCfPDps = 0.f; gCfPHp = 0.f; gCfPM = 0.f; gCfPSpr = 0.f; gCfPRng = 0.f;
	for (uint o = 0; o < gCfGT.length(); ++o) {
		const float reach = gCfGRng[o] + gCfGSpd[o] * CF_REACT_S + gCfGSpr[o];
		const float d = CfDist(gCfGX[o], gCfGZ[o], x, z);
		const bool coming = gCfGFall[o] && (CfDist(gCfGFX[o], gCfGFZ[o], x, z) <= reach);
		if ((int(o) != with) && (d > reach) && !coming)
			continue;
		gCfPN += float(gCfGN[o]);
		gCfPDps += gCfGDps[o];
		gCfPHp += gCfGHp[o];
		gCfPM += gCfGM[o];
		const float s = gCfGSpr[o] + (((int(o) == with) || coming) ? 0.f : d);
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

bool CfPoolFight(const array<int>@ foe, float x, float z)
{
	if (gCfPN <= 0.f) {
		gCfLostO = 0.f;
		gCfLostT = 0.f;
		gCfLostTMob = 0.f;
		gCfSimT = 0.f;
		return false;
	}
	return CfFight(gCfPN, gCfPDps / gCfPN, gCfPHp / gCfPN, gCfPM / gCfPN, gCfPSpr, gCfPRng, gCfPTwD, gCfPTwH, foe,
		CfDgT0(foe, x, z, gCfPSpr));
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

// ---- a pack sent alone: its calibrated share lost at a target ----
// A pack of units: bodies, mean dps, hp, metal, spread and longest range.
void CfPackOf(array<CCircuitUnit@>@ us, float& out n, float& out dps, float& out hp, float& out m,
		float& out spr, float& out rng)
{
	n = 0.f; dps = 0.f; hp = 0.f; m = 0.f; spr = 0.f; rng = 0.f;
	float sx = 0.f, sz = 0.f;
	for (uint i = 0; i < us.length(); ++i) {
		CCircuitUnit@ u = us[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const int d = int(u.circuitDef.id);
		if (!Catalog::ValidId(d))
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		sx += p.x;
		sz += p.z;
		n += 1.f;
		dps += Catalog::gDps[d];
		hp += Catalog::gHealth[d] * u.GetHealthPercent();
		m += Catalog::gCostM[d];
		if (Catalog::gMaxRange[d] > rng)
			rng = Catalog::gMaxRange[d];
	}
	if (n <= 0.f)
		return;
	const float cx = sx / n, cz = sz / n;
	for (uint i = 0; i < us.length(); ++i) {
		CCircuitUnit@ u = us[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		const float dd = CfDist(p.x, p.z, cx, cz);
		if (dd > spr)
			spr = dd;
	}
	// at the target the pack stands within its range of it, however scattered it gathers from
	if (spr > rng)
		spr = rng;
	dps /= n;
	hp /= n;
	m /= n;
}

// The calibrated share of a pack lost at `at` against these defs at these positions: all of it when the pack
// does not win, else real-over-predicted times what the estimate loses.
float CfPackLossF(float n, float dps, float hp, float m, float spr, float rng, const array<int>@ defs,
		const array<float>@ px, const array<float>@ pz, float atX, float atZ)
{
	if ((n <= 0.f) || (m <= 0.f))
		return 1.f;
	const int nd = int(defs.length());
	if (nd == 0)
		return 0.f;
	// nearest the target first
	array<int> ord(nd);
	array<float> dist(nd);
	for (int k = 0; k < nd; ++k) {
		ord[k] = k;
		dist[k] = CfDist(px[k], pz[k], atX, atZ);
	}
	for (int a = 1; a < nd; ++a) {
		const int oi = ord[a];
		const float od = dist[a];
		int b = a - 1;
		while ((b >= 0) && (dist[b] > od)) {
			ord[b + 1] = ord[b];
			dist[b + 1] = dist[b];
			--b;
		}
		ord[b + 1] = oi;
		dist[b + 1] = od;
	}
	array<int> sd(nd);
	float dg = -1.f;
	for (int k = 0; k < nd; ++k) {
		const int d = defs[ord[k]];
		sd[k] = d;
		if (!CfIsCom(d))
			continue;
		float gap = dist[k] - gCfDgRange - spr;
		if (gap < 0.f)
			gap = 0.f;
		const float t = (Catalog::gSpeed[d] > 0.f) ? gap / Catalog::gSpeed[d] : 0.f;
		if ((dg < 0.f) || (t < dg))
			dg = t;
	}
	const float lo = gCfLostO, lt = gCfLostT, lm = gCfLostTMob, st = gCfSimT;
	const bool win = CfSim(n, dps, hp, m, spr, rng, 0.f, 0.f, sd, (dg >= 0.f) ? dg : 0.f);
	float lf = 1.f;
	if (win) {
		lf = gCfRL * gCfLostO / (n * m);
		if (lf > 1.f)
			lf = 1.f;
	}
	gCfLostO = lo;
	gCfLostT = lt;
	gCfLostTMob = lm;
	gCfSimT = st;
	return lf;
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
		// it launched at the split: its roster is what the split claimed
		array<int> ros;
		for (uint i = 0; i < gCfClaimId.length(); ++i) {
			if (gCfClaimSlot[i] == s)
				ros.insertLast(gCfClaimId[i]);
		}
		JwCommit(gCfEcoT[s], ros, id);
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
	array<int> one(1, kd);
	const float lo = gCfLostO, lt = gCfLostT, lm = gCfLostTMob, st = gCfSimT;
	const bool r = !CfSim(float(n), Catalog::gDps[c], Catalog::gHealth[c], Catalog::gCostM[c], spr,
			Catalog::gMaxRange[c], 0.f, 0.f, one, 0.f);
	gCfLostO = lo;
	gCfLostT = lt;
	gCfLostTMob = lm;
	gCfSimT = st;
	gCfPairC.insertLast(c);
	gCfPairN.insertLast(n);
	gCfPairK.insertLast(kd);
	gCfPairR.insertLast(r);
	return r;
}

// Units of a kind a mobile threat in reach counters, and that outrun it, leave for the nearest economy of
// theirs clear of it that the leaving pack wins at: what can reach it while the pack kills it, against the
// calibrated estimate, for more than the pack risks. True when some left (the rest are read again next pass).
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
	// the leaving pack
	array<CCircuitUnit@> pack;
	for (uint i = 0; i < us.length(); ++i) {
		CCircuitUnit@ u = us[i];
		if ((u is null) || (u.circuitDef is null) || CfClaimed(int(u.id)))
			continue;
		const int j = defs.find(int(u.circuitDef.id));
		if ((j >= 0) && (by[j] >= 0))
			pack.insertLast(u);
	}
	float pn, pd, ph, pm, ps, pr;
	CfPackOf(pack, pn, pd, ph, pm, ps, pr);
	if (pn <= 0.f)
		return false;
	// candidates out of every countering threat's reach, nearest first; at most six asked (each a fight on paper)
	array<int> cand;
	array<float> cd;
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
		cand.insertLast(int(e));
		cd.insertLast(CfDist(gCfXX[e], gCfXZ[e], gCfGX[g], gCfGZ[g]));
	}
	int bestE = -1;
	for (int tries = 0; (tries < 6) && (bestE < 0); ++tries) {
		int bi = -1;
		for (uint i = 0; i < cd.length(); ++i) {
			if ((cd[i] >= 0.f) && ((bi < 0) || (cd[i] < cd[bi])))
				bi = int(i);
		}
		if (bi < 0)
			break;
		cd[bi] = -1.f;
		const int e = cand[bi];
		const float killS = (pd > 0.f) ? gCfXH[e] / (pd * pn) : 0.f;
		array<int> ed;
		array<float> ex, ez;
		gCfEGrid.Query(gCfXX[e], gCfXZ[e], gCfEReach * (1.f + killS / CF_REACT_S) + ps);
		for (uint h = 0; h < gCfEGrid.hit.length(); ++h) {
			const int k = gCfEGrid.hit[h];
			const int kd = gCfEDef[k];
			const float reach = Catalog::gMaxRange[kd] + Catalog::gSpeed[kd] * killS + ps;
			if (CfDist(gCfEX[k], gCfEZ[k], gCfXX[e], gCfXZ[e]) > reach)
				continue;
			ed.insertLast(kd);
			ex.insertLast(gCfEX[k]);
			ez.insertLast(gCfEZ[k]);
		}
		const float lf = CfPackLossF(pn, pd, ph, pm, ps, pr, ed, ex, ez, gCfXX[e], gCfXZ[e]);
		if (gCfXM[e] * (1.f - lf) - lf * pm * pn > 0.f)
			bestE = e;
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

// ---- what falling back abandons ----
// Our metal within the mobile threat's reach of where the group stands (extractors at their capitalized
// stream, constructors at cost) and the open spots' race there. Towers alone take no ground.
float CfStake(const array<int>@ foe, float x, float z, float spr)
{
	float R = 0.f;
	for (uint i = 0; i < foe.length(); ++i) {
		const int d = gCfEDef[foe[i]];
		if (!Catalog::gMobile[d])
			continue;
		const float rr = Catalog::gMaxRange[d] + Catalog::gSpeed[d] * CF_REACT_S;
		if (rr > R)
			R = rr;
	}
	if (R <= 0.f)
		return 0.f;
	R += spr;
	AIFloat3 p(x, 0.f, z);
	float st = Market::StakeAt(p, R);
	for (uint i = 0; i < Market::gWorkers.length(); ++i) {
		CCircuitUnit@ w = Market::gWorkers[i];
		if ((w is null) || (w.circuitDef is null))
			continue;
		const int d = int(w.circuitDef.id);
		if (!Catalog::ValidId(d) || CfIsCom(d))
			continue;
		const AIFloat3 wp = w.GetPos(ai.frame);
		if (CfDist(wp.x, wp.z, x, z) <= R)
			st += Catalog::gCostM[d];
	}
	st += Market::SprHoldPrizeNear(p, R);
	return st;
}

void CfDecLog(int g, int v, int prev, float Lc, float Kc, float net, float stake, float q, float retake, float band,
		bool win, bool vsMain, float fbx, float fbz)
{
	gCfDecNet += net;
	if (stake >= 0.f) {
		gCfDecStake += stake;
		gCfDecRetake += retake;
		gCfDecSave += q * stake + retake;
	}
	if (CfIsEngage(v))
		++gCfEngDec;
	else
		++gCfFallDec;
	AiLog(Factory::T() + "apex: comfight-dec t=" + ai.teamId + " at=" + int(gCfGX[g]) + "," + int(gCfGZ[g])
		+ " n=" + gCfGN[g] + " m=" + int(gCfGM[g]) + " v=" + v + " prev=" + prev + " win=" + (win ? 1 : 0)
		+ " main=" + (vsMain ? 1 : 0) + " | fight L=" + int(Lc) + " K=" + int(Kc) + " net=" + int(net)
		+ " | fall stake=" + int(stake) + " q=" + formatFloat(q, "", 0, 2) + " retake=" + int(retake)
		+ " save=" + int((stake >= 0.f) ? q * stake + retake : 0.f) + " band=" + int(band)
		+ " to=" + int(fbx) + "," + int(fbz) + " | rL=" + formatFloat(gCfRL, "", 0, 2) + " rK=" + formatFloat(gCfRK, "", 0, 2));
}

// ---- their largest group: every group of ours falls back onto one point and fights it together ----
float gCfAsmX = 0.f, gCfAsmZ = 0.f;
int gCfAsmAt = -999999;

bool CfAsmLive()
{
	return (gCfBlob >= 0) && (ai.frame - gCfAsmAt <= int(CF_REACT_S * float(SECOND)));
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
		const bool win = CfPoolFight(foe, cx, cz);
		const bool vsMain = CfHasBlob(foe);
		const float poolD = gCfPDps + gCfPTwD;
		const float fm = CfFoeMetal(foe);
		for (uint i = 0; i < pool.length(); ++i) {
			const int g = pool[i];
			if (win)
				CfVerdict(g, CF_BASE_ENGAGE, cx, cz, true, baseR,
					(gCfPM > 0.f) ? gCfLostO * gCfGM[g] / gCfPM : 0.f,
					(poolD > 0.f) ? gCfLostT * gCfGDps[g] / poolD : 0.f, vsMain, gCfSimT, fm, CfContact(g, foe));
			else
				CfVerdict(g, CF_BASE_HOLD, home.x, home.z, false, baseR, 0.f, 0.f, vsMain);
		}
	}
}

void CfEngageAt(int g, float tx, float tz, bool win, float r, float pl, float pk, bool vsMain, float segT, float fm,
		bool contact)
{
	CfVerdict(g, CF_ENGAGE, tx, tz, win, r, pl, pk, vsMain, segT, fm, contact);
	const int s = CfEpSlot(gCfGT[g]);
	if ((s >= 0) && (CfDist(tx, tz, gCfGX[g], gCfGZ[g]) <= gCfGRng[g] + gCfGSpr[g]))
		gCfEpLatch[s] = true;
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
	float tx = x, tz = z;
	if (foe.length() > 0) {
		CfNearestFoe(foe, x, z, tx, tz);
		float sx, sz;
		CfStandAt(x, z, tx, tz, gCfGRng[g], sx, sz);
		CfDropFarStatics(foe, sx, sz, gCfGSpr[g]);
	}
	int s = CfEpSlot(gCfGT[g]);
	if (foe.length() == 0) {
		if ((s >= 0) && gCfEpKo[s])
			gCfEpOut[s] = true;
		CfHunt(g);
		return;
	}
	CfNearestFoe(foe, x, z, tx, tz);
	++gCfInReach;
	if (com)
		++gCfComReach;
	const float r = gCfGRng[g] + gCfGSpd[g] * CF_REACT_S + gCfGSpr[g];
	const bool vsMain = CfHasBlob(foe);
	const float fm = CfFoeMetal(foe);
	const bool contact = CfContact(g, foe);
	// engaged and in contact, the fight is fought out (doctrine: a committed push punches through); its
	// estimate is taken again only when the fight changed past its band
	if ((s >= 0) && gCfEpLatch[s] && (gCfEpV[s] == CF_ENGAGE)) {
		float lpl = 0.f, lpk = 0.f, lT = -1.f;
		if (gCfEpRec[s] && CfSegStale(s, gCfGM[g], fm)) {
			CfPoolAt(x, z, g);
			CfPoolFight(foe, x, z);
			const float lpD = gCfPDps + gCfPTwD;
			lpl = (gCfPM > 0.f) ? gCfLostO * gCfGM[g] / gCfPM : 0.f;
			lpk = (lpD > 0.f) ? gCfLostT * gCfGDps[g] / lpD : 0.f;
			lT = gCfSimT;
		}
		CfVerdict(g, CF_ENGAGE, tx, tz, gCfEpPW[s], r, lpl, lpk, vsMain, lT, fm, contact);
		return;
	}
	// decided once per approach: a ring that still holds keeps the group out of it
	if ((s >= 0) && CfRingHolds(s, gCfGN[g])) {
		++gCfKoKept;
		if (CfDist(x, z, gCfEpKoX[s], gCfEpKoZ[s]) <= gCfEpKoR[s] + gCfGSpd[g] * CF_REACT_S + gCfGSpr[g]) {
			if (gCfEpOut[s])
				++gCfDither;
			gCfEpOut[s] = false;
			CfVerdict(g, CF_FALL, gCfEpFX[s], gCfEpFZ[s], false, r, 0.f, 0.f, vsMain);
		} else {
			gCfEpOut[s] = true;
			gCfGDone[g] = true;
		}
		return;
	}
	if (CfSplit(g, foe))
		return;
	CfPoolAt(x, z, g);
	const bool win = CfPoolFight(foe, x, z);
	const float L = gCfLostO, K = gCfLostT, KMob = gCfLostTMob, segT = gCfSimT;
	const float poolD = gCfPDps + gCfPTwD;
	const float pl = (gCfPM > 0.f) ? L * gCfGM[g] / gCfPM : 0.f;
	const float pk = (poolD > 0.f) ? K * gCfGDps[g] / poolD : 0.f;
	const float Lc = gCfRL * L, Kc = gCfRK * K;
	const float net = Lc - Kc;
	const float band = sqrt(gCfSL * Lc * gCfSL * Lc + gCfSK * Kc * gCfSK * Kc);
	const int prev = (s >= 0) ? gCfEpV[s] : 0;
	if (CfFightCond(net, band, prev)) {
		if (net > 0.f)
			++gCfBandHeld;
		if (!CfIsEngage(prev))
			CfDecLog(g, CF_ENGAGE, prev, Lc, Kc, net, -1.f, 0.f, 0.f, band, win, vsMain, tx, tz);
		CfEngageAt(g, tx, tz, win, r, pl, pk, vsMain, segT, fm, contact);
		return;
	}
	// where it would fall back to
	float fx = 0.f, fz = 0.f;
	for (uint i = 0; i < foe.length(); ++i) {
		fx += gCfEX[foe[i]];
		fz += gCfEZ[foe[i]];
	}
	fx /= float(foe.length());
	fz /= float(foe.length());
	float bx = fx, bz = fz;
	if (vsMain) {
		bx = gCfFcX[gCfBlob];
		bz = gCfFcZ[gCfBlob];
	}
	const float myD = CfDist(bx, bz, x, z);
	float fbx = x, fbz = z;
	int v = 0;
	if (vsMain && CfAsmLive() && (CfDist(gCfAsmX, gCfAsmZ, bx, bz) > myD)) {
		v = CF_FALL;
		fbx = gCfAsmX;
		fbz = gCfAsmZ;
		++gCfAsmJoin;
	}
	if (v == 0) {
		// candidates: other groups, our towers; only ones further from them than we are
		array<float> cx, cz, cd;
		array<bool> cg;
		for (uint o = 0; o < gCfGT.length(); ++o) {
			if ((int(o) == g) || (CfDist(gCfGX[o], gCfGZ[o], bx, bz) <= myD))
				continue;
			cx.insertLast(gCfGX[o]); cz.insertLast(gCfGZ[o]); cd.insertLast(CfDist(gCfGX[o], gCfGZ[o], x, z));
			cg.insertLast(true);
		}
		Market::ComTowersFill();
		for (uint w = 0; w < Market::gCdTwPos.length(); ++w) {
			const AIFloat3 tp = Market::gCdTwPos[w];
			if (CfDist(tp.x, tp.z, bx, bz) <= myD)
				continue;
			cx.insertLast(tp.x); cz.insertLast(tp.z); cd.insertLast(CfDist(tp.x, tp.z, x, z));
			cg.insertLast(false);
		}
		// nearest first, at most six asked (each one a fight on paper); against their largest group the one
		// with the most of ours gathers everyone when none pays yet
		float mostM = -1.f, mostX = x, mostZ = z;
		bool mostG = false;
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
			array<int> fc = foe;
			CfDropFarStatics(fc, cx[bi], cz[bi], gCfPSpr);
			CfPoolFight(fc, cx[bi], cz[bi]);
			if (gCfRL * gCfLostO - gCfRK * gCfLostT <= 0.f) {
				v = CF_FALL;
				fbx = cx[bi];
				fbz = cz[bi];
				if (cg[bi])
					++gCfMerged;
			} else if (gCfPM > mostM) {
				mostM = gCfPM;
				mostX = cx[bi];
				mostZ = cz[bi];
				mostG = cg[bi];
			}
		}
		if ((v == 0) && vsMain && (mostM > 0.f)) {
			v = CF_FALL;
			fbx = mostX;
			fbz = mostZ;
			if (mostG)
				++gCfMerged;
		}
		if ((v != 0) && vsMain) {
			gCfAsmX = fbx;
			gCfAsmZ = fbz;
			++gCfAsmSet;
		}
	}
	if (vsMain && (v == CF_FALL))
		gCfAsmAt = ai.frame;
	if ((v == 0) && Builder::gHomeSet
		&& (CfDist(Builder::gHomePos.x, Builder::gHomePos.z, x, z) > gCfGRng[g] + gCfGSpr[g])
		&& (CfDist(Builder::gHomePos.x, Builder::gHomePos.z, bx, bz) > myD))
	{
		v = CF_HOME;
		fbx = Builder::gHomePos.x;
		fbz = Builder::gHomePos.z;
	}
	// what falling back abandons: the stake as much as this fight would have held it, and the walk out and back
	const float stake = CfStake(foe, x, z, gCfGSpr[g]);
	float foeMobM = 0.f;
	for (uint i = 0; i < foe.length(); ++i) {
		if (Catalog::gMobile[gCfEDef[foe[i]]])
			foeMobM += Catalog::gCostM[gCfEDef[foe[i]]];
	}
	float q = 1.f;
	if (!win && (foeMobM > 0.f)) {
		q = gCfRK * KMob / foeMobM;
		if (q > 1.f)
			q = 1.f;
	}
	float retake = 0.f;
	if ((v != 0) && (gCfGSpd[g] > 0.f)) {
		const float H = Market::PayH();
		if (H > 0.f)
			retake = gCfGM[g] * (2.f * CfDist(x, z, fbx, fbz) / gCfGSpd[g]) / H;
	}
	const float X = net - (q * stake + retake);
	const bool goFight = CfFightCond(X, band, prev);
	if (goFight != (X <= 0.f))
		++gCfBandHeld;
	if (goFight) {
		++gCfByStake;
		if (!CfIsEngage(prev))
			CfDecLog(g, CF_ENGAGE, prev, Lc, Kc, net, stake, q, retake, band, win, vsMain, tx, tz);
		CfEngageAt(g, tx, tz, win, r, pl, pk, vsMain, segT, fm, contact);
		return;
	}
	if (v == 0) {
		++gCfHold;
		return;
	}
	if ((prev == 0) || CfIsEngage(prev))
		CfDecLog(g, v, prev, Lc, Kc, net, stake, q, retake, band, win, vsMain, fbx, fbz);
	CfVerdict(g, v, fbx, fbz, false, r, 0.f, 0.f, vsMain);
	s = CfEpSlot(gCfGT[g]);
	if (s >= 0)
		CfSetRing(s, foe, gCfGN[g], fbx, fbz);
}

// ---- defeat in detail: an attack group out of contact walks onto their group it beats by more than the
// estimate's error band, best calibrated metal killed less lost per second of walk and fight; every other group
// of theirs that can arrive before the fight ends fights in it ----
void CfHunt(int g)
{
	if (gCfGDone[g] || (gCfGT[g].GetFightType() != Task::FightType::ATTACK) || (gCfFcM.length() == 0))
		return;
	const float x = gCfGX[g], z = gCfGZ[g], spd = gCfGSpd[g];
	if (spd <= 0.f)
		return;
	CfPoolAt(x, z, g);
	if (gCfPN <= 0.f)
		return;
	const float pN = gCfPN, pD = gCfPDps / gCfPN, pH = gCfPHp / gCfPN, pM = gCfPM / gCfPN, pS = gCfPSpr, pR = gCfPRng;
	array<float> cd(gCfFcM.length());
	for (uint c = 0; c < gCfFcM.length(); ++c)
		cd[c] = CfDist(gCfFcX[c], gCfFcZ[c], x, z);
	float bestV = 0.f, bestX = x, bestZ = z;
	bool have = false;
	for (int tries = 0; tries < 6; ++tries) {
		int bi = -1;
		for (uint c = 0; c < cd.length(); ++c) {
			if ((cd[c] >= 0.f) && ((bi < 0) || (cd[c] < cd[bi])))
				bi = int(c);
		}
		if (bi < 0)
			break;
		const float walkS = ((cd[bi] > pR) ? cd[bi] - pR : 0.f) / spd;
		cd[bi] = -1.f;
		if (gCfFcSpd[bi] >= spd)
			continue;   // it walks away as fast as we close
		const float cx = gCfFcX[bi], cz = gCfFcZ[bi];
		// the group, the towers covering it, then everything that can arrive within walk + fight
		array<int> foe;
		float fightS = 0.f;
		bool win = false;
		for (int pass = 0; pass < 2; ++pass) {
			foe.resize(0);
			const float within = walkS + fightS;
			for (uint k = 0; k < gCfEDef.length(); ++k) {
				const int d = gCfEDef[k];
				const float dk = CfDist(gCfEX[k], gCfEZ[k], cx, cz);
				bool joins = false;
				if (!Catalog::gMobile[d])
					joins = dk <= Catalog::gMaxRange[d] + pS;
				else if ((k < gCfFcOf.length()) && (gCfFcOf[k] == bi))
					joins = true;
				else
					joins = dk <= Catalog::gMaxRange[d] + Catalog::gSpeed[d] * within + pS;
				if (joins)
					foe.insertLast(int(k));
			}
			CfSortFoes(foe, cx, cz);
			win = CfFight(pN, pD, pH, pM, pS, pR, 0.f, 0.f, foe, CfDgT0(foe, cx, cz, pS));
			fightS = gCfSimT;
		}
		const float Lc = gCfRL * gCfLostO, Kc = gCfRK * gCfLostT;
		const float band = sqrt(gCfSL * Lc * gCfSL * Lc + gCfSK * Kc * gCfSK * Kc);
		if (!win || (Lc - Kc + band >= 0.f))
			continue;
		const float val = (Kc - Lc) / (walkS + gCfSimT + CF_REACT_S);
		if (!have || (val > bestV)) {
			have = true;
			bestV = val;
			bestX = cx;
			bestZ = cz;
		}
	}
	if (!have)
		return;
	AIFloat3 to(bestX, 0.f, bestZ);
	to.y = ai.GetElevationAt(to);
	gCfGT[g].SetScriptMove(to, ai.frame + int(CF_REACT_S * float(SECOND)), true);
	gCfGDone[g] = true;
	++gCfHunts;
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
		if (gCfEpRec[i]) {
			CfSegClose(i, CfIsEngage(gCfEpV[i]));
			++gCfRecEp;
			if (gCfEpPW[i])
				++gCfEpPredW;
			gCfEpLostM += gCfEpLost[i];
			gCfEpKillM += gCfEpKill[i];
			gCfEpPredL += gCfEpPL[i];
			gCfEpPredK += gCfEpPK[i];
			CfCalAdd(gCfEpPL[i], gCfEpLost[i], gCfEpPK[i], gCfEpKill[i]);
		} else {
			++gCfFallEp;
		}
		gCfFallLostM += gCfEpLostF[i];
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
	if (s < 0)
		return;
	if (gCfEpRec[s] && CfIsEngage(gCfEpV[s]))
		gCfEpLost[s] += Catalog::gCostM[d];
	else
		gCfEpLostF[s] += Catalog::gCostM[d];
}

void CfNoteEnemyDeath(const CCircuitDef@ edef, const AIFloat3& in pos, bool byUs)
{
	if (!CfOn() || (edef is null))
		return;
	if (byUs) {
		for (uint i = 0; i < gCfEpT.length(); ++i) {
			if (gCfEpRec[i] && CfIsEngage(gCfEpV[i]) && (CfDist(gCfEpX[i], gCfEpZ[i], pos.x, pos.z) <= gCfEpR[i])) {
				gCfEpKill[i] += edef.costM;
				break;
			}
		}
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
	string packs = "";
	for (uint b = 0; b < 6; ++b)
		packs += ((b == 0) ? "" : " ") + (b + 1) + ((b == 5) ? "+" : "") + ":" + gCfPackOld[b] + "/" + gCfPackNew[b];
	AiLog(Factory::T() + "apex: comfight-cal t=" + ai.teamId
		+ " rL=" + formatFloat(gCfRL, "", 0, 3) + " rK=" + formatFloat(gCfRK, "", 0, 3)
		+ " sL=" + formatFloat(gCfSL, "", 0, 3) + " sK=" + formatFloat(gCfSK, "", 0, 3)
		+ " teamN=" + int(gCfCalT[0]) + " teamPL=" + int(gCfCalT[1]) + " teamAL=" + int(gCfCalT[2])
		+ " teamPK=" + int(gCfCalT[6]) + " teamAK=" + int(gCfCalT[7])
		+ " | settled taken=" + gCfRecEp + " predL=" + int(gCfEpPredL) + " realL=" + int(gCfEpLostM)
		+ " predK=" + int(gCfEpPredK) + " realK=" + int(gCfEpKillM)
		+ " fallEp=" + gCfFallEp + " fallLost=" + int(gCfFallLostM)
		+ " seg open=" + gCfSegOpen + " cut=" + gCfSegCut + " cutL=" + int(gCfSegCutL) + " cutK=" + int(gCfSegCutK)
		+ " | dec engage=" + gCfEngDec + " fall=" + gCfFallDec + " byStake=" + gCfByStake + " bandHeld=" + gCfBandHeld
		+ " flipsEF=" + gCfFlipEF + " net=" + int(gCfDecNet) + " stake=" + int(gCfDecStake)
		+ " retake=" + int(gCfDecRetake) + " save=" + int(gCfDecSave)
		+ " | blob theirMax=" + int(gCfTheirMaxM) + " ourMax=" + int(gCfOurMaxM)
		+ " asmSet=" + gCfAsmSet + " asmJoin=" + gCfAsmJoin
		+ " taken main=" + gCfTakenMain + "/" + int(gCfTakenMainM) + " iso=" + gCfTakenIso + "/" + int(gCfTakenIsoM)
		+ " hunts=" + gCfHunts
		+ " | packs old/new " + packs + " asks=" + gCfPackAsk);
	gCfInReach = 0; gCfComReach = 0; gCfEngage = 0; gCfFall = 0; gCfMerged = 0; gCfHome = 0; gCfHold = 0;
	gCfBaseW = 0; gCfBaseL = 0; gCfFlips = 0; gCfKoSet = 0; gCfKoKept = 0; gCfKoLift = 0; gCfDither = 0;
	gCfEpN = 0; gCfEpPredW = 0; gCfComKills = 0; gCfSplits = 0; gCfReleased = 0; gCfOneShot = 0; gCfNoEco = 0;
	gCfEpLostM = 0.f; gCfEpKillM = 0.f; gCfEpPredL = 0.f; gCfEpPredK = 0.f; gCfEcoKillM = 0.f;
	for (uint i = 0; i < 5; ++i) {
		gCfMove[i] = 0;
		gCfKiller[i] = 0.f;
	}
	gCfUs = 0.0; gCfMaxUs = 0.0; gCfCalls = 0;
	gCfFlipEF = 0; gCfBandHeld = 0; gCfByStake = 0; gCfFallDec = 0; gCfEngDec = 0; gCfAsmSet = 0; gCfAsmJoin = 0;
	gCfTakenMain = 0; gCfTakenIso = 0; gCfHunts = 0; gCfFallEp = 0; gCfRecEp = 0;
	gCfTakenMainM = 0.f; gCfTakenIsoM = 0.f; gCfFallLostM = 0.f;
	gCfSegOpen = 0; gCfSegCut = 0; gCfSegCutL = 0.f; gCfSegCutK = 0.f;
	gCfDecNet = 0.f; gCfDecStake = 0.f; gCfDecRetake = 0.f; gCfDecSave = 0.f;
	gCfTheirMaxM = 0.f; gCfOurMaxM = 0.f;
	for (uint b = 0; b < 6; ++b) {
		gCfPackOld[b] = 0;
		gCfPackNew[b] = 0;
	}
	gCfPackAsk = 0;
}

void UpdateComFight()
{
	if (StockQuiet("comfight"))
		return;
	if (!CfOn())
		return;
	const double t0 = ai.ClockUs();
	CfSamplePositions();
	CfScanStep();
	CfReadDGun();
	CfCalRead();
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
