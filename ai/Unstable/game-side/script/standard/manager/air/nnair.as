namespace Air {

// THE AIR STRIKE AS A PRICED DECISION (his 2026-10-05 report: a clear fusion a
// fresh bomber could kill is left standing; 48 gunships idle at home). Two
// groups decide on the same head: the bombers held at home (kind 0) and the
// gunships (kind 1). Every economy cell of theirs we know is priced: what dies
// there -- its metal and the income it denies them until rebuilt -- against
// the planes lost to the AA we know of on the way in, over the cell and on the
// way out, and their fighters that can reach the cell before we do. Damage is
// a race: our dps falls as their AA takes planes one by one, so a group either
// finishes the cell or is spent. GO flies the group at the best cell; WAIT
// keeps the bombers held and the gunships on home ground. Only what a player
// could know: remembered structures and units seen.

const string NNA_AIR = "kind,grpN,grpM,grpHP,grpDps,grpSpd,tgtV,tgtHP,tgtN,aaT,aaPath,aaFtr,flyS,killS,killF,lossN,lossM,netM,obsSurv,foeAAM,legacy,held,minute";
const int NA_WAIT = 0;
const int NA_GO = 1;
const int NA_N = 2;
const float NA_EPS = 0.01f;
const uint NA_CANDS = 32;

bool gNaHeader = false;
bool gNaCellOn = false;        // the wave in flight was sent at a priced economy cell
AIFloat3 gNaCellAt;
int gNaCellCleared = 0;
float gNaFlat = -1.f;
int gNaNextAt = -1;
int gNaTeamGoSeen = -1;   // the last team-army operation whose GO the strike decision answered
int gNaPhase = 0;
int gNaDecN = 0, gNaGoN = 0, gNaDevN = 0, gNaGoB = 0, gNaGoG = 0, gNaPullN = 0;
int gNaWaitFrom = -1;          // the bombers' last launch, or their first decision
int gNaLateN = 0;              // launches the cadence forced over a WAIT
int gNaDeepN = 0;              // gunship decisions offered the unseen base
int gNaDeepLookAt = -1;        // our gunships last stood over it
bool gNaForced = false;        // this decision's GO was the cadence's, not the net's
int gNaLegacyNext = 0;
int gNaLegacyFrame = -1000;
string gNaLegacyWhy = "";
int gNaGunNow = -1;            // the gunship decision in force
AIFloat3 gNaGunGoal;
float gNaGunR = 0.f;
int gNaArriveAt = 0;
IUnitTask@ gNaTask = null;     // the gunships' own raid
array<int> gNaClaim;           // gunships pulled off a home pool, waiting to re-elect onto it
int gNaLogAt = 0;
int gNaGunN = 0, gNaGunHome = 0, gNaGunOut = 0;
float gNaE2M = -1.f;
float gNaObsDmg = -1.f;        // measured metal destroyed per bomber sent, for the type being priced
float gNaObsLost = -1.f;       // ...and planes lost per run

// the enemy as we know it, one snapshot per decision
array<AIFloat3> gNaTurP;        // their armed ground statics: the push's breach is made of these
array<int> gNaTurD;
int gNaBreachLogAt = 0;
array<AIFloat3> gNaEcoP;        // their economy: where, what, what its death costs them
array<int> gNaEcoD;
array<float> gNaEcoV;
array<AIFloat3> gNaAAP;         // their ground and static AA: where, reach, air dps
array<float> gNaAAR;
array<float> gNaAAV;
array<AIFloat3> gNaFtP;         // their fighters: where, speed, air dps
array<float> gNaFtS;
array<float> gNaFtV;
int gNaSnapAt = -1;
int gNaCsAt = -1;
float gNaCsD = -1.f;
float gNaKeyD = 0.f;           // the deciding wing's damage before the AA spends it, x the AA: dps n^2 h / 2
uint gNaExtra0 = 0, gNaExtra1 = 0;
array<float> gNaAAG;
int gNaAAGw = 0, gNaAAGh = 0, gNaAAGAt = -2;
float gNaAAGc = 0.f;

// the bomber target that wing production prices (NaDemandStep)
array<int> gNaNeedDef;
array<int> gNaNeedN;
array<float> gNaNeedV;

class NaCand {
	AIFloat3 at;
	float v = 0.f;
	float hp = 0.f;
	int n = 0;
	float aaT = 0.f;      // air dps over the cell
}

class NaPrice {
	AIFloat3 at;
	float v = 0.f, hp = 0.f, aaT = 0.f, aaPath = 0.f, aaFtr = 0.f;
	float flyS = 0.f, killS = 0.f, killF = 0.f, lossN = 0.f, lossM = 0.f, netM = 0.f;
	int n = 0;
}

bool IsGunshipDef(int d)
{
	if ((d <= 0) || (d > Catalog::gDefCount))
		return false;
	return Catalog::gFlyer[d] && Catalog::gMobile[d] && !Catalog::gBuilder[d]
		&& !IsBomberDef(d) && !IsFighterDef(d) && !Catalog::gKamikaze[d]
		&& Catalog::gHitsLand[d] && (Catalog::gPower[d] > 1.f)
		&& (Catalog::gSurfT[d] > Catalog::gAirT[d]);
}

// Metal one energy is worth: the best converter the game offers.
float NaE2M()
{
	if (gNaE2M > 0.f)
		return gNaE2M;
	float r = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gAvailable[d] && (Catalog::gConvRatio[d] > r))
			r = Catalog::gConvRatio[d];
	}
	gNaE2M = (r > 0.f) ? r : 1.f / 60.f;
	return gNaE2M;
}

float NaAirDps(int d)
{
	if (Catalog::gSurfDpsOn)
		return Catalog::gAirDps[d];
	const float t = Catalog::gAirT[d] + Catalog::gSurfT[d] + Catalog::gWaterT[d];
	return (t > 0.f) ? Catalog::gDps[d] * Catalog::gAirT[d] / t : 0.f;
}

// What a dead economy building costs them: its metal, and its output until one
// of their constructors walks out from their base and builds it again.
float NaPrizeOf(int d, const AIFloat3& in at, const AIFloat3& in foe, float spotInc)
{
	float v = Catalog::gCostM[d];
	Military::NrConSpeed();
	const float rebuildS = at.distance2D(foe) / Military::gNrConSpd
			+ Catalog::gBuildTime[d] / Military::gNrConBP;
	float rate = Catalog::gMakeM[d] + Catalog::gMakeE[d] * NaE2M()
			+ Catalog::gConvCapacity[d] * Catalog::gConvRatio[d];
	if (Catalog::gExtractsM[d] > 0.f)
		rate += spotInc * Catalog::gExtractsM[d];
	if (rate > 0.f)
		v += rate * rebuildS;
	return v;
}

float gNaSpotInc = -1.f;
array<NaCand@> gNaCs;

void NaSnapEnemy(const AIFloat3& in foe)
{
	if (gNaSnapAt == ai.frame)
		return;
	gNaSnapAt = ai.frame;
	gNaEcoP.resize(0); gNaEcoD.resize(0); gNaEcoV.resize(0);
	gNaAAP.resize(0); gNaAAR.resize(0); gNaAAV.resize(0);
	gNaFtP.resize(0); gNaFtS.resize(0); gNaFtV.resize(0);
	gNaTurP.resize(0); gNaTurD.resize(0);
	if (gNaSpotInc < 0.f) {
		float s = 0.f;
		for (uint i = 0; i < Market::gAllSpotInc.length(); ++i)
			s += Market::gAllSpotInc[i];
		gNaSpotInc = (Market::gAllSpotInc.length() > 0) ? s / float(Market::gAllSpotInc.length()) : 0.f;
	}
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const float aDps = NaAirDps(d);
		if ((aDps > 0.f) && (Catalog::gMaxRange[d] > 0.f)) {
			if (Catalog::gFlyer[d] && Catalog::gMobile[d]) {
				gNaFtP.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
				gNaFtS.insertLast(Catalog::gSpeed[d]);
				gNaFtV.insertLast(aDps);
			} else {
				gNaAAP.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
				gNaAAR.insertLast(Catalog::gAirRange[d]);
				gNaAAV.insertLast(aDps);
			}
		} else if (!Catalog::gMobile[d] && (Catalog::gMaxRange[d] > 0.f) && (Catalog::gSurfT[d] > 0.f)) {
			gNaTurP.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
			gNaTurD.insertLast(d);
		} else if (!Catalog::gMobile[d] && (Catalog::gMaxRange[d] <= 0.f)
			&& ((Catalog::gExtractsM[d] > 0.f) || (Catalog::gMakeE[d] > 0.f)
				|| (Catalog::gMakeM[d] > 0.f) || (Catalog::gConvCapacity[d] > 0.f)
				|| (Catalog::gBuildPower[d] > 0.f))) {
			const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
			// a submerged building is no prize to bombs or gunship guns (his 10-22)
			if (!Catalog::gFloater[d] && (Catalog::gSub[d] || (p.y < -16.f)))
				continue;
			gNaEcoP.insertLast(p);
			gNaEcoD.insertLast(d);
			gNaEcoV.insertLast(NaPrizeOf(d, p, foe, gNaSpotInc));
		}
	}
}

// The richest buildings, each with everything of theirs inside the cell around it.
void NaCands(float r, array<NaCand@>& out cs)
{
	if ((gNaCsAt == ai.frame) && (gNaCsD == gNaKeyD)) {
		cs = gNaCs;
		return;
	}
	gNaCsAt = ai.frame;
	gNaCsD = gNaKeyD;
	array<int> top;
	for (uint e = 0; e < gNaEcoV.length(); ++e) {
		uint at = top.length();
		while ((at > 0) && (gNaEcoV[top[at - 1]] < gNaEcoV[e]))
			--at;
		if (at >= NA_CANDS)
			continue;
		top.insertAt(at, int(e));
		if (top.length() > NA_CANDS)
			top.removeLast();
	}
	cs.resize(0);
	for (uint i = 0; i < top.length(); ++i) {
		NaCand c;
		c.at = gNaEcoP[top[i]];
		for (uint e = 0; e < gNaEcoP.length(); ++e) {
			if (gNaEcoP[e].distance2D(c.at) <= r) {
				c.v += gNaEcoV[e];
				c.hp += Catalog::gHealth[gNaEcoD[e]];
				++c.n;
			}
		}
		for (uint e = 0; e < gNaAAP.length(); ++e) {
			if (gNaAAP[e].distance2D(c.at) <= gNaAAR[e] + r * 0.5f)
				c.aaT += gNaAAV[e];
		}
		cs.insertLast(c);
	}
	gNaExtra0 = cs.length();
	if ((gNaKeyD > 0.f) && EveryOn())
		NaCandsWon(r, top, cs);
	gNaExtra1 = cs.length();
	// The team push's breach while its go stands: the line's guns, struck as
	// the ground push lands (his 2026-10-07: combined air and ground).
	AIFloat3 bAt;
	float bR = 0.f;
	if (Market::PushGoAt(bAt, bR)) {
		NaCand c;
		c.at = bAt;
		for (uint e = 0; e < gNaTurP.length(); ++e) {
			if (gNaTurP[e].distance2D(bAt) <= bR) {
				c.v += Catalog::gCostM[gNaTurD[e]];
				c.hp += Catalog::gHealth[gNaTurD[e]];
				++c.n;
			}
		}
		// the team army's target need not be a turret line: its economy counts too
		for (uint e = 0; e < gNaEcoP.length(); ++e) {
			if (gNaEcoP[e].distance2D(bAt) <= bR) {
				c.v += gNaEcoV[e];
				c.hp += Catalog::gHealth[gNaEcoD[e]];
				++c.n;
			}
		}
		for (uint e = 0; e < gNaAAP.length(); ++e) {
			if (gNaAAP[e].distance2D(c.at) <= gNaAAR[e] + r * 0.5f)
				c.aaT += gNaAAV[e];
		}
		if (c.n > 0)
			cs.insertLast(c);
		if ((c.n > 0) && (ai.frame >= gNaBreachLogAt)) {
			gNaBreachLogAt = ai.frame + 30 * SECOND;
			AiLog("apex: air-breach t=" + ai.teamId + " at=" + int(bAt.x) + "," + int(bAt.z) + " guns=" + c.n + " m=" + int(c.v) + " aa=" + int(c.aaT));
		}
	}
	gNaCs = cs;
}

// The AA over each cell of the map, so a building's cover is one read.
void NaAAGrid(float r)
{
	if ((gNaAAGAt == gNaSnapAt) && (gNaAAGc == r))
		return;
	gNaAAGAt = gNaSnapAt;
	gNaAAGc = r;
	gNaAAGw = int(float(AiTerrainWidth()) / r) + 1;
	gNaAAGh = int(float(AiTerrainHeight()) / r) + 1;
	gNaAAG.resize(gNaAAGw * gNaAAGh);
	for (uint i = 0; i < gNaAAG.length(); ++i)
		gNaAAG[i] = 0.f;
	const float halfDiag = r * 0.7072f;
	for (uint e = 0; e < gNaAAP.length(); ++e) {
		const float reach = gNaAAR[e] + r * 0.5f;
		int x0 = int((gNaAAP[e].x - reach) / r), x1 = int((gNaAAP[e].x + reach) / r);
		int z0 = int((gNaAAP[e].z - reach) / r), z1 = int((gNaAAP[e].z + reach) / r);
		x0 = (x0 < 0) ? 0 : x0; z0 = (z0 < 0) ? 0 : z0;
		x1 = (x1 >= gNaAAGw) ? gNaAAGw - 1 : x1; z1 = (z1 >= gNaAAGh) ? gNaAAGh - 1 : z1;
		for (int z = z0; z <= z1; ++z) {
			for (int x = x0; x <= x1; ++x) {
				const AIFloat3 c((float(x) + 0.5f) * r, 0.f, (float(z) + 0.5f) * r);
				if (c.distance2D(gNaAAP[e]) <= reach + halfDiag)
					gNaAAG[z * gNaAAGw + x] += gNaAAV[e];
			}
		}
	}
}

float NaAAAt(const AIFloat3& in p)
{
	if ((gNaAAGw <= 0) || (gNaAAGc <= 0.f))
		return 0.f;
	int x = int(p.x / gNaAAGc), z = int(p.z / gNaAAGc);
	x = (x < 0) ? 0 : ((x >= gNaAAGw) ? gNaAAGw - 1 : x);
	z = (z < 0) ? 0 : ((z >= gNaAAGh) ? gNaAAGh - 1 : z);
	return gNaAAG[z * gNaAAGw + x];
}

// THE CELLS THIS WING BEATS (apex_air_every). The richest buildings sit under their AA, so a small wing found
// every one of them a loss and held for a wing one slow plant never fills. Each building is also ranked by
// what the wing at home could kill of it before the AA over it spends the wing -- the race's own
// dps n^2 h / 2A against its health -- and the best of those join the cells NaEval prices.
void NaCandsWon(float r, const array<int>& in top, array<NaCand@>& cs)
{
	NaAAGrid(r);
	array<int> pick;
	array<float> key;
	const uint want = NA_CANDS / 2;
	for (uint e = 0; e < gNaEcoV.length(); ++e) {
		if (top.find(int(e)) >= 0)
			continue;
		const float aa = NaAAAt(gNaEcoP[e]);
		const float hpE = Catalog::gHealth[gNaEcoD[e]];
		float k = gNaEcoV[e];
		if ((aa > 0.f) && (hpE > 0.f)) {
			const float f = gNaKeyD / (aa * hpE);
			if (f < 1.f)
				k *= f;
		}
		uint at = pick.length();
		while ((at > 0) && (key[at - 1] < k))
			--at;
		if (at >= want)
			continue;
		pick.insertAt(at, int(e));
		key.insertAt(at, k);
		if (pick.length() > want) {
			pick.removeLast();
			key.removeLast();
		}
	}
	for (uint i = 0; i < pick.length(); ++i) {
		NaCand c;
		c.at = gNaEcoP[pick[i]];
		for (uint e = 0; e < gNaEcoP.length(); ++e) {
			if (gNaEcoP[e].distance2D(c.at) <= r) {
				c.v += gNaEcoV[e];
				c.hp += Catalog::gHealth[gNaEcoD[e]];
				++c.n;
			}
		}
		for (uint e = 0; e < gNaAAP.length(); ++e) {
			if (gNaAAP[e].distance2D(c.at) <= gNaAAR[e] + r * 0.5f)
				c.aaT += gNaAAV[e];
		}
		cs.insertLast(c);
	}
}

// Air dps times elmos flown inside its reach, on the straight line in.
float NaPathAA(const AIFloat3& in from, const AIFloat3& in to)
{
	const float len = from.distance2D(to);
	if ((len < 1.f) || (gNaAAP.length() == 0))
		return 0.f;
	const float seg = len / 6.f;
	float sum = 0.f;
	const float dx = to.x - from.x, dz = to.z - from.z;
	const float len2 = dx * dx + dz * dz;
	for (uint e = 0; e < gNaAAP.length(); ++e) {
		// over the cell is the race's, not the path's
		if (gNaAAP[e].distance2D(to) <= gNaAAR[e])
			continue;
		// farther from the whole segment than its reach: no sample point on it can be inside (the same sum, one
		// distance instead of six; this pass was 72% of the demand step and grew 107x over an hour)
		float u = ((gNaAAP[e].x - from.x) * dx + (gNaAAP[e].z - from.z) * dz) / len2;
		u = (u < 0.f) ? 0.f : ((u > 1.f) ? 1.f : u);
		const float cx = from.x + dx * u - gNaAAP[e].x, cz = from.z + dz * u - gNaAAP[e].z;
		if (cx * cx + cz * cz > gNaAAR[e] * gNaAAR[e])
			continue;
		for (int k = 0; k < 6; ++k) {
			const float f = (float(k) + 0.5f) / 6.f;
			const AIFloat3 p(from.x + (to.x - from.x) * f, 0.f, from.z + (to.z - from.z) * f);
			if (gNaAAP[e].distance2D(p) <= gNaAAR[e])
				sum += gNaAAV[e] * seg;
		}
	}
	return sum;
}

// Their fighters that reach the cell before we finish there.
float NaFighterAA(const AIFloat3& in to, float flyS)
{
	float a = 0.f;
	for (uint e = 0; e < gNaFtP.length(); ++e) {
		if (gNaFtP[e].distance2D(to) <= gNaFtS[e] * flyS)
			a += gNaFtV[e];
	}
	return a;
}

// The race over the cell. n planes of h hp each, dps1 each, cost1 metal each.
// Linear attrition: planes fall at A/h a second, so the damage done by time t
// is dps1 (n t - A t^2 / 2h); the cell dies first or the group does.
float NaEval(const NaCand@ c, float pathAAx, float ftrA, int n, float h, float dps1, float cost1,
	float spd, float flyS, bool back, float obsSurv, NaPrice@ res)
{
	const float N = float(n);
	const float pathD = (spd > 0.f) ? pathAAx / spd : 0.f;
	float lostIn = (h > 0.f) ? pathD / h : N;
	lostIn = (lostIn > N) ? N : lostIn;
	const float N1 = N - lostIn;
	const float A = c.aaT + ftrA;
	float killF = 0.f, tk = 0.f, lostT = 0.f;
	if ((N1 > 0.f) && (dps1 > 0.f) && (c.hp > 0.f)) {
		if (A <= 0.f) {
			killF = 1.f;
			tk = c.hp / (N1 * dps1);
		} else {
			const float dMax = dps1 * N1 * N1 * h / (2.f * A);
			if (dMax >= c.hp) {
				float disc = N1 * N1 - 2.f * A * c.hp / (dps1 * h);
				disc = (disc > 0.f) ? disc : 0.f;
				tk = (N1 - sqrt(disc)) * h / A;
				killF = 1.f;
				lostT = A * tk / h;
			} else {
				killF = dMax / c.hp;
				tk = N1 * h / A;
				lostT = N1;
			}
		}
	}
	float N2 = N1 - lostT;
	N2 = (N2 > 0.f) ? N2 : 0.f;
	float lostOut = 0.f;
	if (back && (h > 0.f)) {
		lostOut = pathD / h;
		lostOut = (lostOut > N2) ? N2 : lostOut;
	}
	float lossN = lostIn + lostT + lostOut;
	// MEASURED BEATS MODELLED: a scored run of this type carries the AA we never saw
	// ...as a number of planes, not a share: AA kills so many per pass, so a wing
	// bigger than the measured run loses no more than it did (his 10-11: mass and rush)
	if (obsSurv >= 0.f) {
		float floorN = N * (1.f - obsSurv);
		if ((gNaObsLost >= 0.f) && (floorN > gNaObsLost))
			floorN = gNaObsLost;
		if (lossN < floorN)
			lossN = floorN;
	}
	lossN = (lossN > N) ? N : lossN;
	// a building half-shot is repaired: only the ones finished count
	if ((killF < 1.f) && (c.n > 0))
		killF = float(int(killF * float(c.n))) / float(c.n);
	// ...and a scored run of this type caps what a plane sent actually destroys
	float got = c.v * killF;
	if ((gNaObsDmg >= 0.f) && (got > gNaObsDmg * N))
		got = gNaObsDmg * N;
	if (res !is null) {
		res.at = c.at; res.v = c.v; res.hp = c.hp; res.n = c.n; res.aaT = c.aaT;
		res.aaPath = pathAAx; res.aaFtr = ftrA; res.flyS = flyS; res.killS = tk;
		res.killF = killF; res.lossN = lossN; res.lossM = lossN * cost1;
		res.netM = got - lossN * cost1;
	}
	return got - lossN * cost1;
}

// The group a decision is about: held bombers (kind 0) or gunships (kind 1).
array<CCircuitUnit@> gNaU;
array<IUnitTask@> gNaT;

void NaSnapGroup(int kind, float& out grpM, float& out hp, float& out dps, float& out spd, AIFloat3& out ctr)
{
	gNaU.resize(0);
	gNaT.resize(0);
	grpM = 0.f; hp = 0.f; dps = 0.f; spd = 0.f;
	float cx = 0.f, cz = 0.f;
	if (kind == 0) {
		for (int i = 0; i < 3; ++i) {
			CCircuitDef@ d = StrikeDef(i);
			if (d is null)
				continue;
			array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
			if (us is null)
				continue;
			for (uint k = 0; k < us.length(); ++k) {
				if ((us[k] is null) || InWave(us[k].id) || Covering(us[k].id))
					continue;
				gNaU.insertLast(us[k]);
				gNaT.insertLast(null);
			}
		}
	} else {
		for (uint i = 0; i < Military::gSquads.length(); ++i) {
			IUnitTask@ t = Military::gSquads[i];
			if ((t is null) || t.IsDead())
				continue;
			const int ft = t.GetFightType();
			if ((ft != int(Task::FightType::RAID)) && (ft != int(Task::FightType::DEFEND)))
				continue;
			array<CCircuitUnit@>@ on = t.GetUnits();
			if (on is null)
				continue;
			for (uint j = 0; j < on.length(); ++j) {
				if ((on[j] is null) || (on[j].circuitDef is null)
					|| !IsGunshipDef(int(on[j].circuitDef.id)))
					continue;
				gNaU.insertLast(on[j]);
				gNaT.insertLast(t);
			}
		}
	}
	for (uint i = 0; i < gNaU.length(); ++i) {
		const int d = int(gNaU[i].circuitDef.id);
		grpM += Catalog::gCostM[d];
		hp += Catalog::gHealth[d];
		dps += Catalog::gSurfDps[d];
		spd = ((spd <= 0.f) || (Catalog::gSpeed[d] < spd)) ? Catalog::gSpeed[d] : spd;
		const AIFloat3 p = gNaU[i].GetPos(ai.frame);
		cx += p.x; cz += p.z;
	}
	if (gNaU.length() > 0) {
		ctr = AIFloat3(cx / float(gNaU.length()), 0.f, cz / float(gNaU.length()));
		ctr.y = ai.GetElevationAt(ctr);
	}
}

float NnAirScore(const array<float>& in st, const array<float>& in f, array<float>& w)
{
	return Market::NnHeadScore(Market::NNA_ON, Market::NNA_STATE, NNA_AIR, Market::NNA_S,
		Market::NNA_O, Market::NNA_H, Market::NNA_XM, Market::NNA_XS, Market::NNA_W1,
		Market::NNA_B1, Market::NNA_W2, Market::NNA_B2, Market::NNA_WO, Market::NNA_BO,
		Market::NNA_TRUST, st, f, w);
}

string NaName(int o) { return (o == NA_GO) ? "GO" : "WAIT"; }

AIFloat3 NaFoe()
{
	AIFloat3 foe = Front::FoeAnchor();
	if (!OnMap(foe))
		foe = aiEnemyMgr.GetEnemyPos();
	return foe;
}

// One decision for one group. Returns the option chosen, -1 when there was no group.
int NaDecide(int kind, const string why)
{
	if (!Builder::gHomeSet || TairOn()) {
		EvNoteSkip(kind, "teamair");
		return -1;
	}
	if ((kind == 0) && gStrike) {
		EvNoteSkip(kind, "out");
		return -1;
	}
	const double _t = Perf::T0();
	float grpM, hpSum, dpsSum, spd;
	AIFloat3 ctr = Builder::gHomePos;
	NaSnapGroup(kind, grpM, hpSum, dpsSum, spd, ctr);
	const int n = int(gNaU.length());
	if ((n == 0) || (spd <= 0.f)) {
		EvNoteSkip(kind, "none");
		Perf::Add("air.nnair", _t);
		return -1;
	}
	const bool legacy = (kind == 0) && (ai.frame - gNaLegacyFrame <= 8);
	const AIFloat3 foe = NaFoe();
	NaSnapEnemy(OnMap(foe) ? foe : ctr);
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	array<NaCand@> cs;
	gNaKeyD = EveryOn() ? dpsSum * hpSum * 0.5f : 0.f;
	NaCands(r, cs);
	const uint ex0 = gNaExtra0, ex1 = gNaExtra1;
	gNaKeyD = 0.f;
	// THE BASE NOBODY HAS SEEN (his 2026-10-12: the gunships never got deep enough to find the fusions,
	// and with no air scout bought for them they hit edge mexes or flew at cells worth 0). A gunship wing
	// prices their mirrored start as a cell holding the economy we have not found yet.
	if ((kind == 1) && Builder::gHomeSet) {
		const AIFloat3 deep(AiTerrainWidth() - Builder::gHomePos.x, 0.f, AiTerrainHeight() - Builder::gHomePos.z);
		if (OnMap(deep) && (ctr.distance2D(deep) <= r))
			gNaDeepLookAt = ai.frame;
		const float seats = (Military::AllyCount() > 1.f) ? Military::AllyCount() : 1.f;
		float seenHere = 0.f, aaAll = 0.f, ecoM = 0.f;
		for (uint e = 0; e < gNaEcoP.length(); ++e) {
			ecoM += Catalog::gCostM[gNaEcoD[e]];
			if (gNaEcoP[e].distance2D(deep) <= r)
				seenHere += Catalog::gCostM[gNaEcoD[e]];
		}
		for (uint e = 0; e < gNaAAV.length(); ++e)
			aaAll += gNaAAV[e];
		float fade = 1.f;
		if (gNaDeepLookAt >= 0) {
			const float horizon = ai.GetTunable("apex_ghost_stale_min", TUNE_GHOST_STALE_MIN) * float(MINUTE);
			fade = (horizon > 1.f) ? (float(ai.frame - gNaDeepLookAt) / horizon) : 1.f;
			if (fade > 1.f)
				fade = 1.f;
		}
		const float unseen = (MirrorPrize() / seats - seenHere) * fade;
		const float mph = Market::StructureMetalPerHp();
		if ((unseen > 0.f) && (mph > 0.f) && OnMap(deep)) {
			NaCand c;
			c.at = deep;
			c.v = unseen;
			c.hp = unseen / mph;
			const float per = (gNaEcoP.length() > 0) ? (ecoM / float(gNaEcoP.length())) : unseen;
			c.n = (per > 1.f) ? int(unseen / per) + 1 : 1;
			for (uint e = 0; e < gNaAAP.length(); ++e) {
				if (gNaAAP[e].distance2D(deep) <= gNaAAR[e] + r * 0.5f)
					c.aaT += gNaAAV[e];
			}
			if (c.aaT < aaAll / seats)
				c.aaT = aaAll / seats;
			cs.insertLast(c);
			++gNaDeepN;
		}
	}
	const float h = hpSum / float(n);
	const float dps1 = dpsSum / float(n);
	const float cost1 = grpM / float(n);
	const float obs = (kind == 0) ? ObsSurv(DominantBomberDef()) : -1.f;
	gNaObsDmg = (kind == 0) ? ObsDmg(DominantBomberDef()) : -1.f;
	gNaObsLost = (kind == 0) ? ObsLost(DominantBomberDef()) : -1.f;
	NaPrice@ best = NaPrice();
	bool have = false;
	uint bestI = 0;
	for (uint i = 0; i < cs.length(); ++i) {
		const float flyS = ctr.distance2D(cs[i].at) / spd;
		const float pAA = NaPathAA(ctr, cs[i].at);
		const float fAA = NaFighterAA(cs[i].at, flyS);
		NaPrice@ p = NaPrice();
		NaEval(cs[i], pAA, fAA, n, h, dps1, cost1, spd, flyS, kind == 0, obs, p);
		if (!have || (p.netM > best.netM)) {
			@best = p;
			have = true;
			bestI = i;
		}
	}
	int rule;
	if (have)
		rule = (best.netM > 0.f) ? NA_GO : NA_WAIT;
	else
		rule = legacy ? NA_GO : NA_WAIT;   // nothing of theirs known: the wing's own clock
	array<float> st;
	Market::NnState(null, st);
	const int held = (kind == 0) ? HeldBombers() : n;
	array<float> f;
	f.insertLast(float(kind));
	f.insertLast(float(n));
	f.insertLast(grpM);
	f.insertLast(hpSum);
	f.insertLast(dpsSum);
	f.insertLast(spd);
	f.insertLast(best.v);
	f.insertLast(best.hp);
	f.insertLast(float(best.n));
	f.insertLast(best.aaT);
	f.insertLast(best.aaPath);
	f.insertLast(best.aaFtr);
	f.insertLast(best.flyS);
	f.insertLast(best.killS);
	f.insertLast(best.killF);
	f.insertLast(best.lossN);
	f.insertLast(best.lossM);
	f.insertLast(have ? best.netM : 0.f);
	f.insertLast(obs);
	f.insertLast(EnemyAACost());
	f.insertLast(legacy ? 1.f : 0.f);
	f.insertLast(float(held));
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> w(NA_N);
	for (int o = 0; o < NA_N; ++o)
		w[o] = (o == rule) ? 1.f : NA_EPS;
	const float trust = NnAirScore(st, f, w);
	float sum = 0.f;
	for (int o = 0; o < NA_N; ++o)
		sum += w[o];
	const float flat = Market::NnHeadFlat();
	const bool explore = flat > 0.f;
	if (Market::gNnExplore)
		gNaFlat = flat;
	array<float> pr(NA_N);
	for (int o = 0; o < NA_N; ++o) {
		if ((trust > 0.f) || (flat > 0.f))
			pr[o] = (1.f - flat) * w[o] / sum + flat / float(NA_N);
		else
			pr[o] = (o == rule) ? 1.f : 0.f;
	}
	int chosen = rule;
	if (flat > 0.f) {
		const float x = float(AiRandom(0, 10000)) / 10000.f;
		chosen = (x < pr[NA_WAIT]) ? NA_WAIT : NA_GO;
	} else if (trust > 0.f) {
		chosen = Market::NnTop(pr, rule);
		Market::NnOneHot(pr, chosen);
	}
	// GO needs somewhere to go: with nothing known and no wing clock, WAIT stands
	// ...so WAIT ran with certainty, and the row says so
	if (!have && !((kind == 0) && gStrikeHas)) {
		chosen = NA_WAIT;
		pr[NA_WAIT] = 1.f;
		pr[NA_GO] = 0.f;
	}
	// THE WING ALWAYS FLIES (his 2026-10-12): a wing held a whole cadence since its last launch goes at
	// the best cell it knows, even when heavy AA prices every cell below zero.
	if (kind == 0) {
		if (gNaWaitFrom < 0)
			gNaWaitFrom = ai.frame;
		if (have && (chosen == NA_WAIT) && (ai.frame - gNaWaitFrom >= AIR_CADENCE)
			&& (BomberMass() >= DeadlineBombBar()) && (BomberMass() >= NaFinishBar()))
		{
			chosen = NA_GO;
			pr[NA_WAIT] = 0.f;
			pr[NA_GO] = 1.f;
			++gNaLateN;
			gNaForced = true;
		}
	}
	++gNaDecN;
	if ((chosen != rule) && !gNaForced)
		++gNaDevN;
	gNaForced = false;
	if (!gNaHeader) {
		gNaHeader = true;
		AiLog("apex: nnair-schema v2 state=" + Market::NN_STATE + " air=" + NNA_AIR
			+ " opt=name,w,p opts=WAIT,GO");
	}
	string ln = "apex: nnair t=" + ai.teamId + " f=" + ai.frame + " why=" + why + " rule=" + NaName(rule)
		+ " ex=" + (explore ? 1 : 0) + " trust=" + Market::NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + Market::NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < f.length(); ++k)
		ln += ((k == 0) ? " " : ",") + Market::NnF(f[k], 3);
	for (int o = 0; o < NA_N; ++o)
		ln += ((o == 0) ? " | " : " ; ") + NaName(o) + "," + Market::NnF(w[o], 4) + "," + Market::NnF(pr[o], 6);
	ln += " | chosen=" + chosen;
	AiLog(ln);
	EvNoteWing(kind, chosen, have, best.netM, n, have && (bestI >= ex0) && (bestI < ex1));
	NaBind(kind, chosen, best, have, why, r);
	Perf::Add("air.nnair", _t);
	return chosen;
}

// What the record says is what happens. Bombers: GO releases the wave at the
// cell; WAIT keeps them held. Gunships: GO points every gunship raid at the
// cell and pulls the ones idling in a home pool onto it; WAIT holds their raids
// on home ground, where they still meet whatever comes near.
void NaBind(int kind, int chosen, NaPrice@ best, bool have, const string why, float r)
{
	if (kind == 0) {
		if (chosen != NA_GO)
			return;
		++gNaGoN;
		++gNaGoB;
		gNaWaitFrom = ai.frame;
		if (have) {
			gStrikeHas = true;
			gStrikeAt = best.at;
			gStrikePrize = best.v;
			gNaCellAt = best.at;
			gNaCellOn = true;
			gStrikeAA = best.aaT;
		}
		Release("nnair " + why + " net=" + int(best.netM) + " killF=" + Market::NnF(best.killF, 2)
			+ " lossN=" + Market::NnF(best.lossN, 1));
		return;
	}
	gNaGunNow = chosen;
	if (chosen == NA_GO) {
		++gNaGoN;
		const bool moved = (gNaGunR <= 0.f) || (gNaGunGoal.distance2D(best.at) > r);
		gNaGunGoal = best.at;
		gNaGunR = r;
		if (moved) {
			++gNaGoG;
			AiLog(Factory::T() + "apex: nnair-go gunships n=" + gNaU.length() + " at="
				+ int(best.at.x) + "," + int(best.at.z) + " v=" + int(best.v)
				+ " killF=" + Market::NnF(best.killF, 2) + " lossN=" + Market::NnF(best.lossN, 1)
				+ " net=" + int(best.netM));
		}
		const float homeR = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R) * 2.f;
		NaWingLaunch(homeR);
		const bool gth = Military::AirGthOn();
		for (uint i = 0; i < gNaU.length(); ++i) {
			IUnitTask@ t = gNaT[i];
			if ((t is null) || t.IsDead())
				continue;
			if (gth && (t !is gNaTask) && t.IsJoinCommitted() && !Military::JwHome(t, homeR))
				continue;
			// ONE WING, ONE TASK: a gunship goaled in its own raid flew alone and arrived alone (his 10-12:
			// "they do this with just 1 at a time"), while the GO was priced on all n arriving together.
			if (t is gNaTask) {
				t.SetRaidGoal(gNaGunGoal, gNaGunR);
				continue;
			}
			if (gNaClaim.find(int(gNaU[i].id)) >= 0)
				continue;
			t.RemoveUnit(gNaU[i]);
			gNaClaim.insertLast(int(gNaU[i].id));
			++gNaPullN;
		}
		if (gNaClaim.length() > 64)
			gNaClaim.removeRange(0, gNaClaim.length() - 64);
		Military::JwCommit(gNaTask, gNaClaim);
		return;
	}
	gNaGunGoal = Builder::gHomePos;
	gNaGunR = 0.f;
	NaHoldGunships();
}

// A gunship GO launches the gunships at home: a wing still out keeps its members and its goal and the
// gathered ones go as a new wing; a wing back home forms again (apex_gather).
void NaWingLaunch(float homeR)
{
	if (!Military::AirGthOn() || (gNaTask is null) || gNaTask.IsDead() || !gNaTask.IsJoinCommitted())
		return;
	if (Military::JwHome(gNaTask, homeR))
		gNaTask.JoinReopen();
	else
		@gNaTask = null;
}

// THE SAME CELL, THE SAME MOMENT: a bomber strike takes the gunships with it.
void NaJoinStrike(const AIFloat3& in at, float r)
{
	float m, hp, dps, spd;
	AIFloat3 ctr;
	NaSnapGroup(1, m, hp, dps, spd, ctr);
	if (gNaU.length() == 0)
		return;
	NaPrice p;
	p.at = at;
	NaBind(1, NA_GO, p, true, "strike", r);
}

// Gunship raids under WAIT hunt only around home.
void NaHoldGunships()
{
	const float homeR = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R) * 2.f;
	for (uint i = 0; i < Military::gSquads.length(); ++i) {
		IUnitTask@ t = Military::gSquads[i];
		if ((t is null) || t.IsDead() || (t.GetFightType() != int(Task::FightType::RAID)))
			continue;
		if (NaAirTask(t))
			t.SetRaidGoal(Builder::gHomePos, homeR);
	}
}

// A raid task flown by aircraft: the ground raid decision does not own it.
bool NaAirTask(IUnitTask@ t)
{
	if ((t is null) || t.IsDead())
		return false;
	array<CCircuitUnit@>@ on = t.GetUnits();
	if ((on is null) || (on.length() == 0))
		return false;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] !is null) && (on[i].circuitDef !is null) && on[i].circuitDef.IsAbleToFly())
			return true;
	}
	return false;
}

bool NaClaimed(CCircuitUnit@ unit)
{
	if ((unit is null) || (gNaClaim.length() == 0))
		return false;
	const int at = gNaClaim.find(int(unit.id));
	if (at < 0)
		return false;
	gNaClaim.removeAt(at);
	return true;
}

// Called from Military::MakeTaskInner for a claimed gunship.
IUnitTask@ NaTask(CCircuitUnit@ unit)
{
	if ((gNaTask is null) || gNaTask.IsDead()) {
		@gNaTask = aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::RAID));
		Military::JwCommit(gNaTask, gNaClaim, int(unit.id));
	}
	if ((gNaTask !is null) && (gNaGunNow == NA_GO) && (gNaGunR > 0.f))
		gNaTask.SetRaidGoal(gNaGunGoal, gNaGunR);
	return gNaTask;
}

// The old release rules (massed, worth, deadline, home wave) still say when the
// wing thinks it is ready; they are an input to the decision now, not a release.
void NaLegacy(const string why)
{
	if (Military::StockQuietAir("air"))
		return;
	gNaLegacyFrame = ai.frame;
	gNaLegacyWhy = why;
	if (ai.frame >= gNaLegacyNext) {
		gNaLegacyNext = ai.frame + 10 * SECOND;
		NaDecide(0, "legacy:" + why);
	}
}

// What the wing needs for the best cell, per bomber type: the smallest wing
// that finishes the cell and still comes out ahead, and what that run nets.
// Production prices bombers on it (StrikeGainFor).
void NaDemandStep()
{
	if (gNaNeedDef.length() != 3) {
		gNaNeedDef.resize(3);
		gNaNeedN.resize(3);
		gNaNeedV.resize(3);
	}
	const AIFloat3 foe = NaFoe();
	if (!OnMap(foe))
		return;
	const double _tS = Perf::T0();
	NaSnapEnemy(foe);
	Perf::Add("air.nd.snap", _tS);
	const double _tC = Perf::T0();
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	array<NaCand@> cs;
	gNaKeyD = 0.f;
	NaCands(r, cs);
	Perf::Add("air.nd.cands", _tC);
	const double _tP = Perf::T0();
	const AIFloat3 from = Builder::gHomePos;
	array<float> pAA(cs.length());
	for (uint i = 0; i < cs.length(); ++i)
		pAA[i] = NaPathAA(from, cs[i].at);
	gNaPAA = pAA;
	gNaPAAAt = ai.frame;
	gNaPAAFrom = from;
	Perf::Add("air.nd.pathaa", _tP);
	gNdCandsN += int(cs.length());
	const double _tE = Perf::T0();
	for (int k = 0; k < 3; ++k) {
		CCircuitDef@ cd = StrikeDef(k);
		gNaNeedDef[k] = (cd is null) ? -1 : int(cd.id);
		gNaNeedN[k] = 0;
		gNaNeedV[k] = 0.f;
		if (cd is null)
			continue;
		const int d = int(cd.id);
		const float spd = Catalog::gSpeed[d];
		if ((spd <= 0.f) || (Catalog::gDps[d] <= 0.f))
			continue;
		const float obs = ObsSurv(d);
		gNaObsDmg = ObsDmg(d);
		gNaObsLost = ObsLost(d);
		for (uint i = 0; i < cs.length(); ++i) {
			// no wing nets more than the cell holds
			if (cs[i].v <= gNaNeedV[k])
				continue;
			const float flyS = from.distance2D(cs[i].at) / spd;
			const float fAA = NaFighterAA(cs[i].at, flyS);
			for (int nn = 1; nn <= 64; nn *= 2) {
				// doubling, then halving down to the smallest wing that pays
				const float net = NaEval(cs[i], pAA[i], fAA, nn, Catalog::gHealth[d], Catalog::gSurfDps[d],
						Catalog::gCostM[d], spd, flyS, true, obs, null);
				if (net <= 0.f)
					continue;
				int lo = (nn > 1) ? nn / 2 + 1 : 1;
				int need = nn;
				float v = net;
				int hi = nn - 1;
				while (lo <= hi) {
					const int m = (lo + hi) / 2;
					const float nm = NaEval(cs[i], pAA[i], fAA, m, Catalog::gHealth[d], Catalog::gSurfDps[d],
							Catalog::gCostM[d], spd, flyS, true, obs, null);
					if (nm > 0.f) {
						need = m;
						v = nm;
						hi = m - 1;
					} else {
						lo = m + 1;
					}
				}
				if (v > gNaNeedV[k]) {
					gNaNeedV[k] = v;
					gNaNeedN[k] = need;
				}
				break;
			}
		}
	}
	Perf::Add("air.nd.eval", _tE);
	if (ai.frame >= gNdLogAt) {
		gNdLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: nademand-size t=" + ai.teamId + " cands=" + cs.length() + " candsSum=" + gNdCandsN);
	}
}
int gNdCandsN = 0;
int gNdLogAt = 0;
// The route AA of NaDemandStep's candidates, reused by EvDemandStep on the same frame (the same cached NaCands list
// and the same home): it was computed twice back to back.
array<float> gNaPAA;
int gNaPAAAt = -1;
AIFloat3 gNaPAAFrom;

// The best cell's net run, offered while the wing is short of the planes it
// takes -- and, in the army's own currency, the army gap at the rate this run
// returns metal for metal: a line unit trades about its cost, a Phoenix that
// kills an undefended fusion returns several times its own.
// BIG ENOUGH TO FINISH IT (apex_air_finish; his 10-22: "our air attacks stay small when they need to get bigger";
// "massive attacks work better than lots of small attacks"). The cadence launch went at DeadlineBombBar, which falls
// to AIR_BOMBERS the longer it is past due, so late wings flew at a dozen whatever the cell needed. It now also waits
// for the smallest wing that finishes the best known cell (gNaNeedN, the same need NaTargetGain prices bombers
// toward); with no need known the old bar stands alone.
float NaFinishBar()
{
	if (ai.GetTunable("apex_air_finish", TUNE_AIR_FINISH) <= 0.f)
		return 0.f;
	// in BomberMass's units: the need is a count of one bomber type, weighed as BomberMass weighs it
	float need = 0.f;
	for (uint k = 0; k < gNaNeedN.length(); ++k) {
		if ((gNaNeedV.length() <= k) || (gNaNeedDef.length() <= k) || (gNaNeedV[k] <= 0.f) || (gNaNeedN[k] <= 0)
			|| !Catalog::ValidId(gNaNeedDef[k]))
			continue;
		const float m = float(gNaNeedN[k]) * BomberUnits(Catalog::Def(gNaNeedDef[k]));
		if (m > need)
			need = m;
	}
	return need;
}

float NaTargetGain(int d, float fillSec, float armyGap)
{
	int held = HeldBombers();
	const int pool = int(TeamWingHeld());
	if (pool > held)
		held = pool;
	for (uint k = 0; k < gNaNeedDef.length(); ++k) {
		if ((gNaNeedDef[k] != d) || (gNaNeedN[k] <= 0) || (gNaNeedV[k] <= 0.f))
			continue;
		if (held >= gNaNeedN[k])
			return 0.f;
		const float fs = (fillSec > 1.f) ? fillSec : 180.f;
		const float own = gNaNeedV[k] / fs;
		const float spend = float(gNaNeedN[k]) * Catalog::gCostM[d];
		const float viaGap = ((armyGap > 0.f) && (spend > 0.f)) ? armyGap / fs * gNaNeedV[k] / spend : 0.f;
		return (viaGap > own) ? viaGap : own;
	}
	return 0.f;
}

// The gunship raid is at its cell and nothing of theirs is left there.
bool NaArrived()
{
	if ((gNaGunNow != NA_GO) || (gNaGunR <= 0.f) || (gNaTask is null) || gNaTask.IsDead())
		return false;
	array<CCircuitUnit@>@ on = gNaTask.GetUnits();
	if (on is null)
		return false;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] !is null) && (on[i].GetPos(ai.frame).distance2D(gNaGunGoal) <= gNaGunR))
			return aiEnemyMgr.GetEnemyStructCostAt(gNaGunGoal, gNaGunR) <= 1.f;
	}
	return false;
}

void NaUpdate()
{
	if (!Builder::gHomeSet || !ApexActive())
		return;
	if ((gNaGunNow == NA_WAIT) && !TairOn())
		NaHoldGunships();
	// AIR AND LAND TOGETHER (his 10-11): a team-army operation entering GO asks the
	// strike decision now, with the operation's target among the cells, not on its clock
	const int goOp = Market::TeamGoOp();
	if ((goOp > 0) && (goOp != gNaTeamGoSeen)) {
		gNaTeamGoSeen = goOp;
		NaDecide(0, "teamgo");
		NaDecide(1, "teamgo");
	}
	if (gNaNextAt < 0)
		gNaNextAt = ai.frame + (ai.teamId % 15) * SECOND;
	if ((ai.frame >= gNaArriveAt) && NaArrived()) {
		gNaArriveAt = ai.frame + 3 * SECOND;
		NaDecide(1, "arrive");
	} else if (ai.frame >= gNaNextAt) {
		// one piece per tick, a 15 s cycle: demand, gunships, bombers
		gNaNextAt = ai.frame + 5 * SECOND;
		gNaPhase = (gNaPhase + 1) % 3;
		if (gNaPhase == 0) {
			double _t = Perf::T0();
			NaDemandStep();
			Perf::Add("air.nademand", _t);
			const double _t2 = Perf::T0();
			EvDemandStep(ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S));
			Perf::Add("air.evdemand", _t2);
			Perf::Add("air.nnair.demand", _t);
		} else if (gNaPhase == 1) {
			NaDecide(1, "clock");
		} else {
			NaDecide(0, "clock");
		}
	}
	if (ai.frame >= gNaLogAt) {
		gNaLogAt = ai.frame + 60 * SECOND;
		int gn = 0, home = 0, away = 0;
		for (uint i = 0; i < Military::gSquads.length(); ++i) {
			IUnitTask@ t = Military::gSquads[i];
			if ((t is null) || t.IsDead())
				continue;
			array<CCircuitUnit@>@ on = t.GetUnits();
			if (on is null)
				continue;
			for (uint j = 0; j < on.length(); ++j) {
				if ((on[j] is null) || (on[j].circuitDef is null) || !IsGunshipDef(int(on[j].circuitDef.id)))
					continue;
				++gn;
				if (on[j].GetPos(ai.frame).distance2D(Builder::gHomePos)
						<= ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R) * 2.f)
					++home;
				else
					++away;
			}
		}
		string need = "";
		for (uint k = 0; k < gNaNeedDef.length(); ++k) {
			if (gNaNeedDef[k] > 0)
				need += " " + Catalog::Def(gNaNeedDef[k]).GetName() + ":" + gNaNeedN[k] + "/" + int(gNaNeedV[k]);
		}
		AiLog(Factory::T() + "apex: nnair-stat t=" + ai.teamId + " dec=" + gNaDecN + " go=" + gNaGoN
			+ " dev=" + gNaDevN + " goB=" + gNaGoB + " late=" + gNaLateN + " deep=" + gNaDeepN + " goG=" + gNaGoG + " pulled=" + gNaPullN
			+ " gun=" + gn + " home=" + home + " out=" + away + " gunNow=" + gNaGunNow
			+ " held=" + HeldBombers() + " need" + need + " flat=" + Market::NnF(gNaFlat, 2));
	}
}

}  // namespace Air
