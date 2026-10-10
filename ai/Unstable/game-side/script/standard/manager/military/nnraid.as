namespace Military {

// THE RAID AS A PRICED DECISION (his 2026-10-05 ask: "price raids properly and
// let the net refine it"). The raiders we hold -- in the home pools, in
// goal-less stock raids, on escort duty -- are one group. Every target on
// their half is priced: the economy we know (or, for a spot never seen, expect)
// stands there, against the Lanchester loss to what holds it and what can
// reach it while we work, and against what the same raiders save at home over
// the whole trip. GO sends the group at the best target (CRaidTask goal);
// WAIT keeps them where they are (a live pack walks home). Only what a player
// could know: remembered structures, units seen, spots we have looked at.

const string NNR_RAID = "grpM,grpS,grpN,tgtV,tgtPrior,tgtE,armyS,defS,pathS,lossF,walkS,killS,altM,netM,escRisk,lossRate,live,minute";
const int NR_WAIT = 0;
const int NR_GO = 1;
const int NR_N = 2;
const float NR_EPS = 0.01f;

int gNrNextAt = -1;
int gNrNow = -1;           // the decision in force (binding until the next one)
int gNrHeldN = 0;          // stock raid tasks held home under WAIT
float gNrHomeR = 600.f;    // the hold radius: twice the group's sight, set at each decision
int gNrArriveAt = 0;
bool gNrHeader = false;
float gNrFlat = -1.f;
bool gNrGoalHas = false;
bool gNrGoalHome = false;
AIFloat3 gNrGoal;
float gNrGoalR = 0.f;
int gNrGoalSince = 0;
int gNrDecN = 0, gNrGoN = 0, gNrDevN = 0, gNrLaunchN = 0, gNrPullN = 0, gNrRegoalN = 0;
float gNrKillM = 0.f, gNrKillEcoM = 0.f;
int gNrKillN = 0, gNrKillEcoN = 0;
float gNrLostM = 0.f;
int gNrLostN = 0;
float gNrEcoLostM = 0.f;     // our mexes and constructors killed by their mobile units
int gNrFirstLossAt = -1;
int gNrLogAt = 0;
float gNrConSpd = -1.f;
array<int> gNrSpotSeen;      // frame a spot was last in our LOS; -1 never
uint gNrSpotI = 0;

// the enemy as we know it, one snapshot per decision
array<AIFloat3> gNeP;
array<int> gNeD;
array<int> gNeK;             // 1 economy, 2 static gun, 3 mobile army

// THE SNAPSHOT IN CELLS. Pricing every spot against every enemy grew as
// spots x units and froze a 7v7 frame for ~50 ms per bot; each spot now reads
// only the cells its own distance tests can reach. A static gun whose reach
// is past NR_LONG (LRPC-class) is kept in a list every spot reads.
const float NR_CELL = 512.f;
const float NR_LONG = 2048.f;
int gNrGW = 0, gNrGH = 0;
array<array<int>> gNrG1, gNrG2, gNrG3;
array<int> gNrLong2;
float gNrMaxR2 = 0.f, gNrMaxR3 = 0.f, gNrMaxSpd3 = 0.f;

void NrGridBuild()
{
	if (gNrGW == 0) {
		gNrGW = int(float(AiTerrainWidth()) / NR_CELL) + 1;
		gNrGH = int(float(AiTerrainHeight()) / NR_CELL) + 1;
		gNrG1.resize(gNrGW * gNrGH);
		gNrG2.resize(gNrGW * gNrGH);
		gNrG3.resize(gNrGW * gNrGH);
	}
	for (uint c = 0; c < gNrG1.length(); ++c) {
		gNrG1[c].resize(0);
		gNrG2[c].resize(0);
		gNrG3[c].resize(0);
	}
	gNrLong2.resize(0);
	gNrMaxR2 = 0.f;
	gNrMaxR3 = 0.f;
	gNrMaxSpd3 = 0.f;
	for (uint e = 0; e < gNeP.length(); ++e) {
		int cx = int(gNeP[e].x / NR_CELL), cz = int(gNeP[e].z / NR_CELL);
		cx = (cx < 0) ? 0 : ((cx >= gNrGW) ? gNrGW - 1 : cx);
		cz = (cz < 0) ? 0 : ((cz >= gNrGH) ? gNrGH - 1 : cz);
		const int c = cz * gNrGW + cx;
		const int d = gNeD[e];
		if (gNeK[e] == 1) {
			gNrG1[c].insertLast(int(e));
		} else if (gNeK[e] == 2) {
			if (Catalog::gMaxRange[d] > NR_LONG) {
				gNrLong2.insertLast(int(e));
			} else {
				gNrG2[c].insertLast(int(e));
				gNrMaxR2 = (Catalog::gMaxRange[d] > gNrMaxR2) ? Catalog::gMaxRange[d] : gNrMaxR2;
			}
		} else if (gNeK[e] == 3) {
			gNrG3[c].insertLast(int(e));
			gNrMaxR3 = (Catalog::gMaxRange[d] > gNrMaxR3) ? Catalog::gMaxRange[d] : gNrMaxR3;
			gNrMaxSpd3 = (Catalog::gSpeed[d] > gNrMaxSpd3) ? Catalog::gSpeed[d] : gNrMaxSpd3;
		}
	}
}

// The snapshot entries of one kind in every cell within r of p (a superset:
// the caller's own distance test still decides).
void NrNear(const array<array<int>>& in g, const AIFloat3& in p, float r, array<int>& res)
{
	res.resize(0);
	int x0 = int((p.x - r) / NR_CELL), x1 = int((p.x + r) / NR_CELL);
	int z0 = int((p.z - r) / NR_CELL), z1 = int((p.z + r) / NR_CELL);
	x0 = (x0 < 0) ? 0 : x0;
	z0 = (z0 < 0) ? 0 : z0;
	x1 = (x1 >= gNrGW) ? gNrGW - 1 : x1;
	z1 = (z1 >= gNrGH) ? gNrGH - 1 : z1;
	for (int z = z0; z <= z1; ++z) {
		for (int x = x0; x <= x1; ++x) {
			const array<int>@ cell = g[z * gNrGW + x];
			for (uint i = 0; i < cell.length(); ++i)
				res.insertLast(cell[i]);
		}
	}
}

// the group, one snapshot per decision
array<CCircuitUnit@> gNrU;
array<IUnitTask@> gNrT;
array<float> gNrAltRate;     // metal/s this unit saves where it is now
array<int> gNrPackId;        // the pack's units at the last update

bool NrOn() { return ai.GetTunable("apex_nnraid", TUNE_NNRAID) > 0.f; }

bool NrRaider(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null))
		return false;
	const CCircuitDef@ d = u.circuitDef;
	return d.IsMobile() && !d.IsAbleToFly() && !IsRollingBomb(d)
		&& d.IsRoleAny(Unit::Role::RAIDER.mask) && (d.power > 1.f);
}

float gNrConBP = 1.f;
float NrConSpeed()
{
	if (gNrConSpd > 0.f)
		return gNrConSpd;
	float s = 0.f, bp = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gBuilder[d] && Catalog::gMobile[d] && !Catalog::gFlyer[d]
			&& (Catalog::gMaxRange[d] <= 0.f) && (Catalog::gSpeed[d] > 0.f)
			&& (Catalog::gBuildPower[d] > 0.f)) {
			s += Catalog::gSpeed[d];
			bp += Catalog::gBuildPower[d];
			++n;
		}
	}
	gNrConSpd = (n > 0) ? s / float(n) : 1.f;
	gNrConBP = (n > 0) ? bp / float(n) : 1.f;
	return gNrConSpd;
}

int gNrMexDef = -1;
// the plainest extractor the game offers: what stands on a spot we never saw
int NrMexDef()
{
	if (gNrMexDef >= 0)
		return gNrMexDef;
	float e = 0.f;
	int best = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		const float x = Catalog::gExtractsM[d];
		if (Catalog::gAvailable[d] && (x > 0.f) && ((e <= 0.f) || (x < e))) {
			e = x;
			best = d;
		}
	}
	if (best > 0)
		gNrMexDef = best;
	return best;
}

bool NrTheirHalf(const AIFloat3& in p, const AIFloat3& in foe)
{
	return p.distance2D(foe) < p.distance2D(Builder::gHomePos);
}

// A spot looked at: a few a second, the whole list in seconds.
void NrSpotLook()
{
	const uint n = Market::gAllSpots.length();
	if (n == 0)
		return;
	if (gNrSpotSeen.length() != n) {
		gNrSpotSeen.resize(n);
		for (uint i = 0; i < n; ++i)
			gNrSpotSeen[i] = -1;
	}
	for (uint k = 0; (k < 8) && (k < n); ++k) {
		gNrSpotI = (gNrSpotI + 1) % n;
		if (OnMap(Market::gAllSpots[gNrSpotI]) && ai.IsPosInLos(Market::gAllSpots[gNrSpotI]))
			gNrSpotSeen[gNrSpotI] = ai.frame;
	}
}

void NrSnapEnemy()
{
	gNeP.resize(0);
	gNeD.resize(0);
	gNeK.resize(0);
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		int k = 0;
		const bool armed = (Catalog::gMaxRange[d] > 0.f) && (Catalog::gDps[d] > 0.f);
		if (!Catalog::gMobile[d]) {
			if (armed)
				k = 2;
			else if ((Catalog::gExtractsM[d] > 0.f) || (Catalog::gMakeE[d] > 0.f)
					|| (Catalog::gMakeM[d] > 0.f) || (Catalog::gConvCapacity[d] > 0.f)
					|| (Catalog::gBuildPower[d] > 0.f))
				k = 1;
		} else if (!Catalog::gFlyer[d]) {
			if (Catalog::gBuilder[d] && !armed)
				k = 1;
			else if (FmArmedGround(d))
				k = 3;
		}
		if (k == 0)
			continue;
		gNeP.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
		gNeD.insertLast(d);
		gNeK.insertLast(k);
	}
	NrGridBuild();
}

// What a dead economy unit costs them: its metal, and for an extractor the
// income lost until a constructor walks out from their base and rebuilds it.
float NrPrizeOf(int d, const AIFloat3& in at, float spotInc, const AIFloat3& in foe)
{
	float v = Catalog::gCostM[d];
	if (Catalog::gExtractsM[d] > 0.f) {
		// one of their constructors walks out from their base and builds it again
		const float rebuildS = at.distance2D(foe) / NrConSpeed() + Catalog::gBuildTime[d] / gNrConBP;
		v += spotInc * Catalog::gExtractsM[d] * rebuildS;
	}
	return v;
}

// The group: raiders in home pools, in raids with no goal of ours, and on
// escort duty, each with what it saves where it stands.
float gNrHomeRate = 0.f;

void NrSnapGroup(float& out grpM, float& out grpS, AIFloat3& out ctr, float& out spd, float& out losR,
	float& out dps)
{
	gNrU.resize(0);
	gNrT.resize(0);
	gNrAltRate.resize(0);
	grpM = 0.f; grpS = 0.f; spd = 0.f; losR = 0.f; dps = 0.f;
	float cx = 0.f, cz = 0.f, px = 0.f, pz = 0.f;
	int pn = 0;
	// what raids cost us per second at home, shared over everything defending it
	const float elapsed = (gNrFirstLossAt >= 0) ? float(ai.frame - gNrFirstLossAt) / 30.f : 0.f;
	const float lossRate = (elapsed > 0.f) ? gNrEcoLostM / elapsed : 0.f;
	gNrHomeRate = lossRate;
	const float homeS = HomeStrength();
	for (uint i = 0; i < gSquads.length(); ++i) {
		IUnitTask@ t = gSquads[i];
		if ((t is null) || t.IsDead() || IsAnswerTask(t))
			continue;
		const int ft = t.GetFightType();
		const bool ours = (gAskTask !is null) && (t is gAskTask);
		if (!ours && (ft != int(Task::FightType::DEFEND)) && (ft != int(Task::FightType::GUARD))
			&& (ft != int(Task::FightType::RAID)))
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if (on is null)
			continue;
		const bool guard = ft == int(Task::FightType::GUARD);
		for (uint j = 0; j < on.length(); ++j) {
			CCircuitUnit@ u = on[j];
			if (!NrRaider(u) || (guard && !EscortSpare(u.id)))
				continue;   // a GO pulls the whole group: a needed escort is not in it
			const int d = int(u.circuitDef.id);
			const float s = DgStr(d);
			gNrU.insertLast(u);
			gNrT.insertLast(t);
			// an escort saves the expected loss on the worker it guards (the
			// task's target handle reads null on a fighter task; the registry has it)
			float alt = ours ? 0.f : lossRate * s / (homeS + s);
			if (guard) {
				alt = 0.f;
				for (uint e = 0; e < Market::gEscUnit.length(); ++e) {
					if (Market::gEscUnit[e] != u.id)
						continue;
					CCircuitUnit@ vip = ai.GetTeamUnit(Market::gEscWorker[e]);
					if ((vip !is null) && (vip.circuitDef !is null)) {
						const AIFloat3 vp = vip.GetPos(ai.frame);
						if (OnMap(vp))
							alt = Market::ExpectedLossAt(vp, Catalog::gCostM[int(vip.circuitDef.id)]);
					}
					break;
				}
			}
			gNrAltRate.insertLast(alt);
			grpM += Catalog::gCostM[d];
			grpS += s;
			dps += Catalog::gDps[d];
			const AIFloat3 p = u.GetPos(ai.frame);
			cx += p.x; cz += p.z;
			if (ours) {
				px += p.x; pz += p.z; ++pn;
			}
			spd = ((spd <= 0.f) || (Catalog::gSpeed[d] < spd)) ? Catalog::gSpeed[d] : spd;
			losR = (Catalog::gLosR[d] > losR) ? Catalog::gLosR[d] : losR;
		}
	}
	// a pack in the field prices from where it stands; the rest catch up
	if (pn > 0) {
		ctr = AIFloat3(px / float(pn), 0.f, pz / float(pn));
		ctr.y = ai.GetElevationAt(ctr);
	} else if (gNrU.length() > 0) {
		ctr = AIFloat3(cx / float(gNrU.length()), 0.f, cz / float(gNrU.length()));
		ctr.y = ai.GetElevationAt(ctr);
	}
}

// Lanchester square law: the share of a force of strength F lost beating E.
float NrLossFrac(float E, float F)
{
	if (F <= 0.f)
		return 1.f;
	if (E >= F)
		return 1.f;
	const float r = E / F;
	return 1.f - sqrt(1.f - r * r);
}

// Strength per metal of their army, as seen; ours when nothing is seen.
float NrFoeSPerM(float grpS, float grpM)
{
	const float fm = FoeLiveM();
	if (fm > 0.f)
		return FoeLiveStr() / fm;
	return (grpM > 0.f) ? grpS / grpM : 0.f;
}

// one priced target
class NrTarget {
	AIFloat3 at;
	float v = 0.f;        // known economy there, metal
	float prior = 0.f;    // expected economy on a spot never looked at
	float eS = 0.f;       // total opposition strength
	float armyS = 0.f;
	float defS = 0.f;
	float pathS = 0.f;
	float lossF = 1.f;
	float walkS = 0.f;
	float killS = 0.f;
	float altM = 0.f;
	float netM = 0.f;
	float hp = 0.f;
}

// THE DECISION IN SLICES. Pricing every spot in one frame froze a bot for
// 30-50 ms on a crowded map; the spots are priced a time budget per update
// and the decision is made when the last one is.
const double NR_SLICE_US = 3000.0;
bool gNrJob = false;
string gNjWhy = "";
AIFloat3 gNjFoe, gNjCtr;
float gNjRP = 0.f, gNjSPerM = 0.f, gNjOcc = 0.f, gNjAlt = 0.f;
float gNjGrpM = 0.f, gNjGrpS = 0.f, gNjSpd = 0.f, gNjDps = 0.f, gNjLosR = 0.f;
uint gNjN = 0, gNjS = 0;
bool gNjHave = false;
NrTarget@ gNjBest;

bool NrPriceBegin(const AIFloat3& in foe, float grpM, float grpS, const AIFloat3& in ctr, float spd,
	float losR, float dps)
{
	const uint n = Market::gAllSpots.length();
	if ((n == 0) || (spd <= 0.f))
		return false;
	gNjRP = (losR > 1.f) ? losR : 300.f;
	gNjSPerM = NrFoeSPerM(grpS, grpM);
	// their occupancy, as we have looked: their extractors known over their spots seen
	int seenN = 0, mexN = 0;
	for (uint s = 0; s < n; ++s) {
		const AIFloat3 sp = Market::gAllSpots[s];
		if (!OnMap(sp) || !NrTheirHalf(sp, foe))
			continue;
		if ((gNrSpotSeen.length() == n) && (gNrSpotSeen[s] >= 0))
			++seenN;
	}
	for (uint e = 0; e < gNeD.length(); ++e) {
		if (Catalog::gExtractsM[gNeD[e]] > 0.f)
			++mexN;
	}
	gNjOcc = float(mexN + 1) / float(((seenN > mexN) ? seenN : mexN) + 2);
	gNjAlt = 0.f;
	for (uint i = 0; i < gNrAltRate.length(); ++i)
		gNjAlt += gNrAltRate[i];
	gNjFoe = foe;
	gNjCtr = ctr;
	gNjGrpM = grpM;
	gNjGrpS = grpS;
	gNjSpd = spd;
	gNjDps = dps;
	gNjLosR = losR;
	gNjN = n;
	gNjS = 0;
	gNjHave = false;
	@gNjBest = NrTarget();
	return true;
}

// One spot of the job, priced against the job's snapshot.
void NrPriceSpot(uint s)
{
	const AIFloat3 foe = gNjFoe, ctr = gNjCtr;
	const float rP = gNjRP, sPerM = gNjSPerM, occ = gNjOcc, altRate = gNjAlt;
	const float grpM = gNjGrpM, grpS = gNjGrpS, spd = gNjSpd, dps = gNjDps;
	const uint n = gNjN;
	NrTarget@ best = gNjBest;
	bool have = gNjHave;
	array<int> near;
	{
	const AIFloat3 sp = Market::gAllSpots[s];
	if (!OnMap(sp) || !NrTheirHalf(sp, foe))
		return;
	NrTarget t;
	t.at = sp;
	float hp = 0.f;
	bool mexKnown = false;
	NrNear(gNrG1, sp, rP, near);
	for (uint i = 0; i < near.length(); ++i) {
		const uint e = uint(near[i]);
		const int d = gNeD[e];
		if (gNeP[e].distance2D(sp) <= rP) {
			t.v += NrPrizeOf(d, gNeP[e], Market::gAllSpotInc[s], foe);
			hp += Catalog::gHealth[d];
			if (Catalog::gExtractsM[d] > 0.f)
				mexKnown = true;
		}
	}
	NrNear(gNrG2, sp, gNrMaxR2 + rP * 0.5f, near);
	for (uint i = 0; i < gNrLong2.length(); ++i)
		near.insertLast(gNrLong2[i]);
	for (uint i = 0; i < near.length(); ++i) {
		const uint e = uint(near[i]);
		const int d = gNeD[e];
		if (gNeP[e].distance2D(sp) <= Catalog::gMaxRange[d] + rP * 0.5f)
			t.defS += DgStr(d);
	}
	const bool looked = (gNrSpotSeen.length() == n) && (gNrSpotSeen[s] >= 0);
	if (!mexKnown && !looked) {
		// a spot we never saw: an extractor there as often as we find them
		const int md = NrMexDef();
		if (md > 0) {
			const float mexV = NrPrizeOf(md, sp, Market::gAllSpotInc[s], foe);
			t.prior = occ * mexV;
			hp += occ * Catalog::gHealth[md];
			// a look moves this spot's price by 2*occ*(1-occ)*prize, on average
			NoteLook(LOOK_RAID, sp, 2.f * occ * (1.f - occ) * mexV, 45);
		}
	}
	if (t.v + t.prior <= 0.f)
		return;
	t.walkS = ctr.distance2D(sp) / spd;
	t.killS = (dps > 0.f) ? hp / dps : t.walkS;
	// their army that can stand on the spot while we work there
	const float stay = t.killS;
	NrNear(gNrG3, sp, gNrMaxR3 + gNrMaxSpd3 * stay, near);
	for (uint i = 0; i < near.length(); ++i) {
		const uint e = uint(near[i]);
		const int d = gNeD[e];
		if (gNeP[e].distance2D(sp) <= Catalog::gMaxRange[d] + Catalog::gSpeed[d] * stay)
			t.armyS += DgStr(d);
	}
	// the risk model's wave at the target and its approach; the pack's path
	// is threat-routed, so the open middle is what it walks around. The wave
	// is there only as often as it arrives (HazardAt, per second) over the
	// seconds we stand inside their ground.
	float worstM = 0.f;
	const float expoS = t.killS + t.walkS * 0.25f;
	for (int k = 3; k <= 4; ++k) {
		const float f = float(k) / 4.f;
		AIFloat3 p(ctr.x + (sp.x - ctr.x) * f, 0.f, ctr.z + (sp.z - ctr.z) * f);
		if (!OnMap(p))
			continue;
		float pr = Market::HazardAt(p) * expoS;
		pr = (pr > 1.f) ? 1.f : pr;
		const float m = Market::ThreatM(p) * pr;
		worstM = (m > worstM) ? m : worstM;
	}
	t.pathS = worstM * sPerM;
	const float army = (t.armyS > t.pathS) ? t.armyS : t.pathS;
	t.eS = army + t.defS;
	t.lossF = NrLossFrac(t.eS, grpS);
	const float tripS = 2.f * t.walkS + t.killS;
	t.altM = altRate * tripS;
	t.netM = (t.v + t.prior) * (1.f - t.lossF) - t.lossF * grpM - t.altM;
	t.hp = hp;
	if (!have || (t.netM > best.netM)) {
		best.at = t.at; best.v = t.v; best.prior = t.prior; best.eS = t.eS;
		best.armyS = t.armyS; best.defS = t.defS; best.pathS = t.pathS;
		best.lossF = t.lossF; best.walkS = t.walkS; best.killS = t.killS;
		best.altM = t.altM; best.netM = t.netM; best.hp = t.hp;
		have = true;
	}
	}
	gNjHave = have;
}

// Called by RaidTaskFor on the pack it creates: the goal travels with it.
void NrApplyGoal(IUnitTask@ t)
{
	if ((t is null) || t.IsDead() || !gNrGoalHas)
		return;
	t.SetRaidGoal(gNrGoal, gNrGoalR);
}

float NnRaidScore(const array<float>& in st, const array<float>& in f, array<float>& w)
{
	return Market::NnHeadScore(Market::NNR_ON, Market::NNR_STATE, NNR_RAID, Market::NNR_S,
		Market::NNR_O, Market::NNR_H, Market::NNR_XM, Market::NNR_XS, Market::NNR_W1,
		Market::NNR_B1, Market::NNR_W2, Market::NNR_B2, Market::NNR_WO, Market::NNR_BO,
		Market::NNR_TRUST, st, f, w);
}

string NrName(int o) { return (o == NR_GO) ? "GO" : "WAIT"; }

bool NrLive()
{
	if ((gAskTask is null) || gAskTask.IsDead())
		return false;
	array<CCircuitUnit@>@ on = gAskTask.GetUnits();
	return (on !is null) && (on.length() > 0);
}

void NrDecide(const string why)
{
	if (gNrJob || !Builder::gHomeSet || !Market::gSpotsCached)
		return;
	AIFloat3 foe = Front::FoeAnchor();
	if (!OnMap(foe)) {
		foe = aiEnemyMgr.GetEnemyPos();
		if (!OnMap(foe))
			return;
	}
	float grpM, grpS, spd, losR, dps;
	AIFloat3 ctr;
	NrSnapGroup(grpM, grpS, ctr, spd, losR, dps);
	if (gNrU.length() == 0)
		return;
	{ double _t = Perf::T0(); NrSnapEnemy(); Perf::Add("nr.snap", _t); }
	if (!NrPriceBegin(foe, grpM, grpS, ctr, spd, losR, dps))
		return;
	gNrJob = true;
	gNjWhy = why;
	NrStep();
}

// Price spots until the slice is spent; on the last one, decide.
void NrStep()
{
	if (!gNrJob)
		return;
	const double t0 = ai.ClockUs();
	while ((gNjS < gNjN) && (ai.ClockUs() - t0 < NR_SLICE_US)) {
		NrPriceSpot(gNjS);
		++gNjS;
	}
	Perf::Add("nr.price", Perf::On() ? t0 : 0.0);
	if (gNjS < gNjN)
		return;
	gNrJob = false;
	if (gNjHave && (gNrU.length() > 0))
		NrFinish(gNjWhy, gNjBest, gNjGrpM, gNjGrpS, gNjLosR);
}

void NrFinish(const string why, NrTarget@ best, float grpM, float grpS, float losR)
{
	const bool live = NrLive();
	const int rule = (best.netM > 0.f) ? NR_GO : NR_WAIT;
	array<float> st;
	Market::NnState(null, st);
	array<float> rf;
	rf.insertLast(grpM);
	rf.insertLast(grpS);
	rf.insertLast(float(gNrU.length()));
	rf.insertLast(best.v);
	rf.insertLast(best.prior);
	rf.insertLast(best.eS);
	rf.insertLast(best.armyS);
	rf.insertLast(best.defS);
	rf.insertLast(best.pathS);
	rf.insertLast(best.lossF);
	rf.insertLast(best.walkS);
	rf.insertLast(best.killS);
	rf.insertLast(best.altM);
	rf.insertLast(best.netM);
	rf.insertLast(Market::EscortMetalAtRisk());
	rf.insertLast(gNrHomeRate);
	rf.insertLast(live ? 1.f : 0.f);
	rf.insertLast(float(ai.frame) / 1800.f);
	array<float> w(NR_N);
	for (int o = 0; o < NR_N; ++o)
		w[o] = (o == rule) ? 1.f : NR_EPS;
	const float trust = NnRaidScore(st, rf, w);
	float sum = 0.f;
	for (int o = 0; o < NR_N; ++o)
		sum += w[o];
	const float flat = Market::NnHeadFlat();
	const bool explore = flat > 0.f;
	if (Market::gNnExplore)
		gNrFlat = flat;
	array<float> p(NR_N);
	for (int o = 0; o < NR_N; ++o) {
		if ((trust > 0.f) || (flat > 0.f))
			p[o] = (1.f - flat) * w[o] / sum + flat / float(NR_N);
		else
			p[o] = (o == rule) ? 1.f : 0.f;
	}
	int chosen = rule;
	if ((trust > 0.f) || (flat > 0.f)) {
		const float r = float(AiRandom(0, 10000)) / 10000.f;
		chosen = (r < p[NR_WAIT]) ? NR_WAIT : NR_GO;
	}
	++gNrDecN;
	if (chosen != rule)
		++gNrDevN;
	if (!gNrHeader) {
		gNrHeader = true;
		AiLog("apex: nnraid-schema v1 state=" + Market::NN_STATE + " raid=" + NNR_RAID
			+ " opt=name,w,p opts=WAIT,GO");
	}
	string ln = "apex: nnraid t=" + ai.teamId + " f=" + ai.frame + " why=" + why + " rule=" + NrName(rule)
		+ " ex=" + (explore ? 1 : 0) + " trust=" + Market::NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + Market::NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < rf.length(); ++k)
		ln += ((k == 0) ? " " : ",") + Market::NnF(rf[k], 3);
	for (int o = 0; o < NR_N; ++o)
		ln += ((o == 0) ? " | " : " ; ") + NrName(o) + "," + Market::NnF(w[o], 4) + "," + Market::NnF(p[o], 6);
	ln += " | chosen=" + chosen;
	AiLog(ln);
	NrBind(chosen, best, losR);
}

// What the record says is what happens: GO points the pack at the target and
// pulls every raider of the group onto it; WAIT pulls nobody and walks a live
// pack home, where its goal is our own ground.
void NrBind(int chosen, NrTarget@ best, float losR)
{
	gNrNow = chosen;
	gNrHomeR = ((losR > 1.f) ? losR : 300.f) * 2.f;
	const float rP = (losR > 1.f) ? losR : 300.f;
	if (chosen == NR_GO) {
		++gNrGoN;
		const bool moved = !gNrGoalHas || gNrGoalHome || (gNrGoal.distance2D(best.at) > rP);
		gNrGoalHas = true;
		gNrGoalHome = false;
		gNrGoal = best.at;
		gNrGoalR = rP;
		if (moved) {
			gNrGoalSince = ai.frame;
			++gNrLaunchN;
			AiLog("apex: nnraid-go t=" + ai.teamId + " at=" + int(best.at.x) + "," + int(best.at.z)
				+ " n=" + gNrU.length() + " v=" + int(best.v + best.prior) + " lossF=" + Market::NnF(best.lossF, 2)
				+ " walkS=" + int(best.walkS));
		}
		if (NrLive()) {
			gAskTask.SetRaidGoal(gNrGoal, gNrGoalR);
			++gNrRegoalN;
		}
		for (uint i = 0; i < gNrU.length(); ++i) {
			IUnitTask@ t = gNrT[i];
			CCircuitUnit@ u = gNrU[i];
			if ((gAskTask !is null) && (t is gAskTask))
				continue;
			if (RaidClaimed(int(u.id)))
				continue;
			// the claim routes it to the pack before the escort branch could unpair it
			Market::EscortGone(u.id);
			t.RemoveUnit(u);
			gAskClaim.insertLast(int(u.id));
			++gNrPullN;
		}
		return;
	}
	if (NrLive() && !gNrGoalHome) {
		gNrGoalHas = true;
		gNrGoalHome = true;
		gNrGoal = Builder::gHomePos;
		gNrGoalR = rP * 2.f;
		gNrGoalSince = ai.frame;
		gAskTask.SetRaidGoal(gNrGoal, gNrGoalR);
	}
}

// The pack is at its goal and nothing of theirs is left there: go further.
bool NrArrived()
{
	if (!gNrGoalHas || gNrGoalHome || !NrLive())
		return false;
	array<CCircuitUnit@>@ on = gAskTask.GetUnits();
	bool near = false;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] !is null) && (on[i].GetPos(ai.frame).distance2D(gNrGoal) <= gNrGoalR)) {
			near = true;
			break;
		}
	}
	if (!near)
		return false;
	return aiEnemyMgr.GetEnemyStructCostAt(gNrGoal, gNrGoalR) <= 1.f;
}

void UpdateNnRaid()
{
	if (!NrOn() || !ApexActive())
		return;
	NrSpotLook();
	gNrPackId.resize(0);
	if (NrLive()) {
		array<CCircuitUnit@>@ on = gAskTask.GetUnits();
		for (uint i = 0; i < on.length(); ++i) {
			if (on[i] !is null)
				gNrPackId.insertLast(int(on[i].id));
		}
	}
	if (gAskClaim.length() > 32)
		gAskClaim.removeRange(0, gAskClaim.length() - 32);
	// WAIT holds every raid, not just ours: a stock raid pool launching on its
	// own would make the record say WAIT while raiders went out.
	if ((gNrNow == NR_WAIT) && Builder::gHomeSet) {
		for (uint i = 0; i < gSquads.length(); ++i) {
			IUnitTask@ t = gSquads[i];
			if ((t is null) || t.IsDead() || (t is gAskTask) || IsAnswerTask(t)
				|| (t.GetFightType() != int(Task::FightType::RAID)) || Air::NaAirTask(t))
				continue;
			t.SetRaidGoal(Builder::gHomePos, gNrHomeR);
			++gNrHeldN;
		}
	}
	if (gNrNextAt < 0)
		gNrNextAt = ai.frame + (ai.teamId % 15) * SECOND;
	if (gNrJob) {
		NrStep();
	} else if ((ai.frame >= gNrArriveAt) && NrArrived()) {
		gNrArriveAt = ai.frame + 3 * SECOND;
		NrDecide("arrive");
	} else if (ai.frame >= gNrNextAt) {
		gNrNextAt = ai.frame + 15 * SECOND;
		NrDecide("clock");
	}
	if (ai.frame >= gNrLogAt) {
		gNrLogAt = ai.frame + 60 * SECOND;
		int liveN = 0;
		int gd = -1;
		if (NrLive()) {
			array<CCircuitUnit@>@ on = gAskTask.GetUnits();
			liveN = on.length();
			for (uint i = 0; i < on.length(); ++i) {
				if (on[i] is null)
					continue;
				const int dd = int(on[i].GetPos(ai.frame).distance2D(gNrGoal));
				gd = ((gd < 0) || (dd < gd)) ? dd : gd;
			}
		}
		AiLog("apex: nnraid-stat t=" + ai.teamId + " dec=" + gNrDecN + " go=" + gNrGoN + " dev=" + gNrDevN + " held=" + gNrHeldN
			+ " launched=" + gNrLaunchN + " pulled=" + gNrPullN + " live=" + liveN + " goalDist=" + gd
			+ " goal=" + (gNrGoalHas ? (int(gNrGoal.x) + "," + int(gNrGoal.z) + (gNrGoalHome ? "(home)" : "")) : "-")
			+ " killM=" + int(gNrKillM) + " killN=" + gNrKillN
			+ " ecoKillM=" + int(gNrKillEcoM) + " ecoKillN=" + gNrKillEcoN
			+ " lostM=" + int(gNrLostM) + " lostN=" + gNrLostN
			+ " ourEcoLostM=" + int(gNrEcoLostM) + " flat=" + Market::NnF(gNrFlat, 2));
	}
}

// An enemy death our raid pack was in reach of is the pack's kill.
void NrNoteEnemyDeath(const CCircuitDef@ edef, const AIFloat3& in pos, bool byUs)
{
	if (!byUs || (edef is null) || !NrLive())
		return;
	array<CCircuitUnit@>@ on = gAskTask.GetUnits();
	for (uint i = 0; i < on.length(); ++i) {
		CCircuitUnit@ u = on[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const float reach = Catalog::gMaxRange[int(u.circuitDef.id)] + 100.f;
		if (u.GetPos(ai.frame).distance2D(pos) > reach)
			continue;
		const int d = int(edef.id);
		gNrKillM += edef.costM;
		++gNrKillN;
		const bool eco = (Catalog::gExtractsM[d] > 0.f)
			|| (Catalog::gBuilder[d] && Catalog::gMobile[d] && (Catalog::gMaxRange[d] <= 0.f));
		if (eco) {
			gNrKillEcoM += edef.costM;
			++gNrKillEcoN;
		}
		AiLog("apex: nnraid-kill t=" + ai.teamId + " " + edef.GetName() + " m=" + int(edef.costM)
			+ " eco=" + (eco ? 1 : 0) + " at=" + int(pos.x) + "," + int(pos.z));
		return;
	}
}

// Our side of the ledger: raiders lost on the pack, and our economy killed by
// their mobile units (what raiders at home are for).
void NrNoteOwnLoss(CCircuitUnit@ unit, const CCircuitDef@ attackerDef)
{
	if ((unit is null) || (unit.circuitDef is null))
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	const int d = int(cdef.id);
	// the task has already let go of a dead unit: read the last roll call
	if (gNrPackId.find(int(unit.id)) >= 0) {
		gNrLostM += cdef.costM;
		++gNrLostN;
		gNrPackId.removeAt(gNrPackId.find(int(unit.id)));
	}
	if ((attackerDef is null) || !attackerDef.IsMobile())
		return;
	const bool eco = (Catalog::gExtractsM[d] > 0.f)
		|| (Catalog::gBuilder[d] && Catalog::gMobile[d] && (Catalog::gMaxRange[d] <= 0.f));
	if (!eco)
		return;
	if (gNrFirstLossAt < 0)
		gNrFirstLossAt = ai.frame;
	gNrEcoLostM += cdef.costM;
}

}  // namespace Military
