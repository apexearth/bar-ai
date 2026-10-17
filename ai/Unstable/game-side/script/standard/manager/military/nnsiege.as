namespace Military {

// SIEGE A FORTIFICATION ON PURPOSE (his 10-14, docs/doctrine.md): the C++ fort census
// (unit/enemy/FortCensus.cpp) groups their known guns into fortifications; this
// head picks NO or SIEGE on the best-priced one, demands units that outrange it
// (SiegeGapM, production.as), and gives them a squad (C++ CSiegeTask) that exists
// only for that target until it is gone or the siege is lost.
const string NNSG_SIEGE = "fortM,ecoM,routeM,worthM,gunN,gunHD,reach,radius,shieldN,shieldH,jamN,radarN,"
	+ "homeD,fwd,blocks,forceM,haveM,lackM,foeM,ratio,defRange,defCost,forts,atkPow,armyM,minute";
const int SG_NO = 0, SG_SIEGE = 1;
// CFortCensus::Field
const int FV_GUN_N = 0, FV_GUN_H = 1, FV_GUN_D = 2, FV_REACH = 3, FV_RADIUS = 4, FV_SHIELD_N = 5;
const int FV_SHIELD_H = 6, FV_JAM_N = 7, FV_JAM_M = 8, FV_RADAR_N = 9, FV_METAL_M = 10, FV_ECO_M = 11, FV_KEY = 12;
const int SG_EVERY = 30 * SECOND;
const int SG_LOOK = 4 * SECOND;
const int SG_PULL_PER_LOOK = 4;     // raid.as's pace: one look cannot strip the line at once

bool gSgOn = false, gSgReady = false;
int gSgKey = -1;
AIFloat3 gSgPos;
float gSgReach = 0.f, gSgRadius = 0.f, gSgWatchR = 0.f;
float gSgWorth = 0.f, gSgForceM = 0.f, gSgNeedHD = 0.f, gSgFortM0 = 0.f;
int gSgDef = -1;
int gSgFrom = 0, gSgDecF = 0;
float gSgKill = 0.f, gSgLost = 0.f;
int gSgPeakN = 0;
IUnitTask@ gSgTask;
array<int> gSgClaim;
int gSgNextAt = -1, gSgLookAt = 0, gSgLogAt = 0, gSgStatAt = 0;
bool gSgHeader = false;
int gSgDecN = 0, gSgExN = 0, gSgHitN = 0, gSgGoneN = 0, gSgLostN = 0, gSgNoUnitN = 0, gSgNoFort = 0, gSgNoDef = 0;
int gSgPulled = 0;
// SiegeGapM's cache: what we own and have ordered that outranges the siege's guns
int gSgGapAt = -999999;
float gSgHaveH = 0.f, gSgHaveD = 0.f;

bool SiegeOn() { return gSgOn; }

float SgD(int d)
{
	const float h = (Catalog::gHealth[d] > 1.f) ? Catalog::gHealth[d] : 1.f;
	return Catalog::gSurfT[d] / sqrt(h);
}

// A unit whose row stands outside guns reaching `reach`.
bool SgCarry(int d, float reach)
{
	return Catalog::gMobile[d] && !Catalog::gFlyer[d] && !Catalog::gBuilder[d] && Catalog::gHitsLand[d]
		&& !Catalog::gKamikaze[d] && (Catalog::gPower[d] > 1.f) && (Catalog::gSurfT[d] > 0.01f)
		&& (Catalog::gMaxRange[d] > reach);
}

bool SgSupportDef(int d, bool jam)
{
	return Catalog::gMobile[d] && !Catalog::gBuilder[d] && !Catalog::gFlyer[d]
		&& (Catalog::gSurfT[d] + Catalog::gAirT[d] < 0.01f)
		&& (jam ? Catalog::gJammer[d] : Catalog::gRadar[d]);
}

// What our standing labs can turn out that outranges `reach`.
void SgBuildable(float reach, array<int>& defs)
{
	defs.resize(0);
	const array<int>@ own = Market::OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int ld = own[i];
		if (Catalog::gMobile[ld])
			continue;
		const array<int>@ bl = Catalog::gBuildsList[ld];
		for (uint q = 0; q < bl.length(); ++q) {
			if (SgCarry(bl[q], reach) && (defs.find(bl[q]) < 0))
				defs.insertLast(bl[q]);
		}
	}
}

// Lanchester (SquadTask's safeAt): what we own and have ordered that outranges `reach`.
void SgHave(float reach, float& out h, float& out dsum, float& out metal)
{
	h = 0.f;
	dsum = 0.f;
	metal = 0.f;
	array<int> defs;
	SgBuildable(reach, defs);
	const array<int>@ own = Market::OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		if (SgCarry(own[i], reach) && (defs.find(own[i]) < 0))
			defs.insertLast(own[i]);
	}
	// owned plus ordered: a def's first unit is in no owned list until it walks out
	for (uint i = 0; i < defs.length(); ++i) {
		const int d = defs[i];
		const int owned = (d < int(Market::gOwnCount.length())) ? Market::gOwnCount[d] : 0;
		const float n = float(owned + Brain::PendAnyOf(d));
		h += n * Catalog::gHealth[d];
		dsum += n * SgD(d);
		metal += n * Catalog::gCostM[d];
	}
}

// Units of d to add to (h, dsum) so h x dsum reaches need.
float SgUnitsFor(int d, float h, float dsum, float need)
{
	const float a = Catalog::gHealth[d] * SgD(d);
	if (a <= 0.f)
		return 1e9f;
	const float b = h * SgD(d) + dsum * Catalog::gHealth[d];
	const float c = h * dsum - need;
	if (c >= 0.f)
		return 0.f;
	return (-b + sqrt(b * b - 4.f * a * c)) / (2.f * a);
}

float SgNeedHD(int i)
{
	const float h = aiMilitaryMgr.GetFortVal(i, FV_GUN_H) + aiMilitaryMgr.GetFortVal(i, FV_SHIELD_H);
	return h * aiMilitaryMgr.GetFortVal(i, FV_GUN_D) * ANSWER_PARITY;
}

float SgSegDist(const AIFloat3& in p, const AIFloat3& in a, const AIFloat3& in b)
{
	const float dx = b.x - a.x, dz = b.z - a.z;
	const float l2 = dx * dx + dz * dz;
	float t = (l2 > 1.f) ? ((p.x - a.x) * dx + (p.z - a.z) * dz) / l2 : 0.f;
	t = (t < 0.f) ? 0.f : ((t > 1.f) ? 1.f : t);
	const float ex = a.x + t * dx - p.x, ez = a.z + t * dz - p.z;
	return sqrt(ex * ex + ez * ez);
}

float SiegeNnScore(const array<float>& in st, const array<float>& in f, array<float>& w)
{
	const int h = Market::PnHead(NNSG_SIEGE);
	if (h < 0)
		return 0.f;
	Market::PnTilt(h, st, f, w);
	return 1.f;
}

void SiegeDecide()
{
	const int nF = aiMilitaryMgr.GetFortCount();
	if (nF <= 0) {
		++gSgNoFort;
		return;
	}
	AIFloat3 ecoAt;
	float ecoCellM = 0.f;
	const bool route = StrikeTarget(ecoAt, ecoCellM);
	array<int> defs;
	int best = -1, bestDef = -1;
	float bestRatio = -1.f;
	array<float> bf;
	for (int i = 0; i < nF; ++i) {
		if (aiMilitaryMgr.GetFortAllyClaim(i) >= 0)
			continue;   // an ally is sieging it
		const float reach = aiMilitaryMgr.GetFortVal(i, FV_REACH);
		SgBuildable(reach, defs);
		float hH = 0.f, hD = 0.f, haveM = 0.f;
		SgHave(reach, hH, hD, haveM);
		const float need = SgNeedHD(i);
		int pick = -1;
		float forceM = 1e12f;
		for (uint k = 0; k < defs.length(); ++k) {
			const int d = defs[k];
			float n = ceil(sqrt(need / (Catalog::gHealth[d] * SgD(d))));
			n = (n < 1.f) ? 1.f : n;
			if (n * Catalog::gCostM[d] < forceM) {
				forceM = n * Catalog::gCostM[d];
				pick = d;
			}
		}
		if ((pick < 0) && (haveM > 0.f))
			forceM = haveM;   // nothing buildable outranges it, but we already own a force that does
		if (forceM >= 1e11f)
			continue;
		const AIFloat3 fp = aiMilitaryMgr.GetFortPos(i);
		const float radius = aiMilitaryMgr.GetFortVal(i, FV_RADIUS);
		const bool blocks = route && Builder::gHomeSet
			&& (SgSegDist(fp, Builder::gHomePos, ecoAt) < reach + radius);
		const float fortM = aiMilitaryMgr.GetFortVal(i, FV_METAL_M);
		const float ecoM = aiMilitaryMgr.GetFortVal(i, FV_ECO_M);
		const float routeM = blocks ? ecoCellM : 0.f;
		const float worth = fortM + ecoM + routeM;
		const float haveF = (need > 0.f) ? sqrt(hH * hD / need) : 1.f;
		const float lackM = forceM * ((haveF < 1.f) ? (1.f - haveF) : 0.f);
		// An outranging force is not spent by the siege -- it outlives the guns and rejoins the army --
		// so the price is the part still to buy and what their army there can kill.
		const float watchR = radius + reach + ((pick > 0) ? Catalog::gMaxRange[pick] : reach);
		const float foeM = SgFoeNearM(fp, watchR + reach);
		const float cost = lackM + foeM;
		const float ratio = worth / ((cost > 1.f) ? cost : 1.f);
		if (ratio <= bestRatio)
			continue;
		bestRatio = ratio;
		best = i;
		bestDef = pick;
		bf.resize(0);
		bf.insertLast(fortM);
		bf.insertLast(ecoM);
		bf.insertLast(routeM);
		bf.insertLast(worth);
		bf.insertLast(aiMilitaryMgr.GetFortVal(i, FV_GUN_N));
		bf.insertLast(aiMilitaryMgr.GetFortVal(i, FV_GUN_H) * aiMilitaryMgr.GetFortVal(i, FV_GUN_D));
		bf.insertLast(reach);
		bf.insertLast(radius);
		bf.insertLast(aiMilitaryMgr.GetFortVal(i, FV_SHIELD_N));
		bf.insertLast(aiMilitaryMgr.GetFortVal(i, FV_SHIELD_H));
		bf.insertLast(aiMilitaryMgr.GetFortVal(i, FV_JAM_N));
		bf.insertLast(aiMilitaryMgr.GetFortVal(i, FV_RADAR_N));
		bf.insertLast(Builder::gHomeSet ? fp.distance2D(Builder::gHomePos) : -1.f);
		bf.insertLast(ForwardFraction(fp));
		bf.insertLast(blocks ? 1.f : 0.f);
		bf.insertLast(forceM);
		bf.insertLast(haveM);
		bf.insertLast(lackM);
		bf.insertLast(foeM);
		bf.insertLast(ratio);
		bf.insertLast((pick > 0) ? Catalog::gMaxRange[pick] : 0.f);
		bf.insertLast((pick > 0) ? Catalog::gCostM[pick] : 0.f);
	}
	if (best < 0) {
		++gSgNoDef;
		return;
	}
	if (!gSgHeader) {
		gSgHeader = true;
		AiLog("apex: nnsiege-schema v1 state=" + Market::NN_STATE + " siege=" + NNSG_SIEGE + " opt=name,w,p opts=NO,SIEGE");
	}
	array<float> st;
	Market::NnState(null, st);
	array<float> f = bf;
	f.insertLast(float(nF));
	f.insertLast(aiMilitaryMgr.GetAttackPower());
	f.insertLast(TeamArmyCost());
	f.insertLast(float(ai.frame) / 1800.f);
	// THE RULE SIEGES WHEN THE FORTIFICATION IS WORTH THE FORCE THAT KILLS IT: its metal, the economy
	// inside its reach and, when it stands on the road to their richest economy, that economy too,
	// against the metal still to buy of the cheapest outranging force that beats its guns at the answer parity.
	const int rule = (bestRatio >= 1.f) ? SG_SIEGE : SG_NO;
	array<float> w(2, Market::NE2_EPS);
	w[rule] = 1.f;
	const float trust = SiegeNnScore(st, f, w);
	array<float> p(2);
	const float flat = Market::NnHeadFlat();
	const int c = Market::EcoDraw(rule, trust, w, p, flat);
	array<string> names = {"NO", "SIEGE"};
	AiLog(Market::EcoLine("nnsiege", names[rule], flat > 0.f, trust, st, f, names, w, p, c));
	++gSgDecN;
	if (flat > 0.f)
		++gSgExN;
	if (c == SG_SIEGE)
		SiegeStart(best, bestDef, bf[3], bf[15]);
}

void SiegeStart(int i, int def, float worth, float forceM)
{
	gSgOn = true;
	gSgReady = false;
	gSgKey = int(aiMilitaryMgr.GetFortVal(i, FV_KEY));
	gSgPos = aiMilitaryMgr.GetFortPos(i);
	gSgReach = aiMilitaryMgr.GetFortVal(i, FV_REACH);
	gSgRadius = aiMilitaryMgr.GetFortVal(i, FV_RADIUS);
	gSgWatchR = gSgRadius + gSgReach + ((def > 0) ? Catalog::gMaxRange[def] : gSgReach);
	gSgWorth = worth;
	gSgForceM = forceM;
	gSgNeedHD = SgNeedHD(i);
	gSgFortM0 = aiMilitaryMgr.GetFortVal(i, FV_METAL_M);
	gSgDef = def;
	gSgFrom = ai.frame;
	gSgDecF = ai.frame;
	gSgKill = 0.f;
	gSgLost = 0.f;
	gSgPeakN = 0;
	gSgGapAt = -999999;
	gSgClaim.resize(0);
	++gSgHitN;
	aiMilitaryMgr.SetSiege(gSgPos, gSgRadius, gSgReach, gSgKey);
	aiMilitaryMgr.SetSiegeReady(false);
	AiLog(Factory::T() + "apex: siege start t=" + ai.teamId + " key=" + gSgKey + " at=" + int(gSgPos.x) + "," + int(gSgPos.z)
		+ " guns=" + int(aiMilitaryMgr.GetFortVal(i, FV_GUN_N)) + " needHD=" + int(gSgNeedHD)
		+ " reach=" + int(gSgReach) + " r=" + int(gSgRadius)
		+ " shield=" + int(aiMilitaryMgr.GetFortVal(i, FV_SHIELD_N)) + " jam=" + int(aiMilitaryMgr.GetFortVal(i, FV_JAM_N))
		+ " fortM=" + int(gSgFortM0) + " worth=" + int(worth) + " forceM=" + int(forceM)
		+ " def=" + ((def > 0) ? Catalog::Def(def).GetName() : "-"));
}

void SiegeEnd(const string why)
{
	if (!gSgOn)
		return;
	const int i = aiMilitaryMgr.GetSiegeFort();
	const float left = (i >= 0) ? aiMilitaryMgr.GetFortVal(i, FV_METAL_M) : 0.f;
	gSgOn = false;
	aiMilitaryMgr.ClearSiege();
	gSgClaim.resize(0);
	if (why == "gone")
		++gSgGoneN;
	else if (why == "lost")
		++gSgLostN;
	else
		++gSgNoUnitN;
	const float denom = gSgWorth + gSgLost;
	const float done = (denom > 0.f) ? (gSgKill - gSgLost) / denom : 0.f;
	AiLog(Factory::T() + "apex: siege end t=" + ai.teamId + " why=" + why + " key=" + gSgKey
		+ " s=" + ((ai.frame - gSgFrom) / SECOND) + " kill=" + int(gSgKill) + " lost=" + int(gSgLost)
		+ " fortM0=" + int(gSgFortM0) + " left=" + int(left) + " worth=" + int(gSgWorth) + " peakN=" + gSgPeakN);
	AiLog("apex: nnsiege-done t=" + ai.teamId + " f=" + gSgDecF + " opt=1 done=" + Market::NnF(done, 3)
		+ " kill=" + int(gSgKill) + " lost=" + int(gSgLost) + " worth=" + int(gSgWorth));
}

// Both death hooks: what dies around the fortification while we siege it.
void SiegeNoteDeath(const AIFloat3& in pos, float m, bool ours, bool byUs)
{
	if (!gSgOn || (m <= 0.f) || !OnMap(pos) || (pos.distance2D(gSgPos) > gSgWatchR))
		return;
	if (ours)
		gSgLost += m;
	else if (byUs)
		gSgKill += m;
}

bool SiegeClaimed(int id)
{
	return gSgClaim.find(id) >= 0;
}

IUnitTask@ SiegeTaskFor()
{
	if ((gSgTask !is null) && !gSgTask.IsDead())
		return gSgTask;
	@gSgTask = aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::SIEGE));
	return gSgTask;
}

// The squad as it stands: Lanchester terms of its long guns, its screen's metal, its sensors.
void SgSquad(float& out h, float& out dsum, float& out screenM, int& out radars, int& out jams, int& out n, float& out dist)
{
	h = 0.f;
	dsum = 0.f;
	screenM = 0.f;
	radars = 0;
	jams = 0;
	n = 0;
	dist = -1.f;
	if ((gSgTask is null) || gSgTask.IsDead())
		return;
	array<CCircuitUnit@>@ on = gSgTask.GetUnits();
	if (on is null)
		return;
	AIFloat3 c(0.f, 0.f, 0.f);
	for (uint k = 0; k < on.length(); ++k) {
		CCircuitUnit@ u = on[k];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const int d = int(u.circuitDef.id);
		++n;
		const AIFloat3 up = u.GetPos(ai.frame);
		c.x += up.x;
		c.z += up.z;
		if (SgCarry(d, gSgReach)) {
			h += Catalog::gHealth[d];
			dsum += SgD(d);
		} else if (SgSupportDef(d, false)) {
			++radars;
		} else if (SgSupportDef(d, true)) {
			++jams;
		} else {
			screenM += Catalog::gCostM[d];
		}
	}
	if (n > 0) {
		c.x /= float(n);
		c.z /= float(n);
		dist = c.distance2D(gSgPos);
	}
}

// Their armed ground metal within reach of the fortification: what the screen is there to meet.
float SgFoeNearM(const AIFloat3 &in at, float r)
{
	float m = 0.f;
	const int n = aiEnemyMgr.GetEnemyGroupCount();
	for (int g = 0; g < n; ++g) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(g);
		if (!OnMap(gp) || (gp.distance2D(at) > r))
			continue;
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(g);
		for (int k = 0; k < nU; ++k) {
			const int ud = aiEnemyMgr.GetEnemyGroupUnitDef(g, k);
			if ((ud > 0) && (ud <= Catalog::gDefCount) && FmArmedGround(ud))
				m += Catalog::gCostM[ud];
		}
	}
	return m;
}

// The election: a claimed unit, a long gun the squad still lacks, a sensor it has none of.
IUnitTask@ SiegeTaskForUnit(CCircuitUnit@ unit)
{
	if (!gSgOn)
		return null;
	const int id = int(unit.id);
	const int i = gSgClaim.find(id);
	if (i >= 0) {
		gSgClaim.removeAt(uint(i));
		return SiegeTaskFor();
	}
	const int d = int(unit.circuitDef.id);
	float h, dsum, screenM, dist;
	int radars, jams, n;
	if (SgCarry(d, gSgReach)) {
		SgSquad(h, dsum, screenM, radars, jams, n, dist);
		if (h * dsum < gSgNeedHD)
			return SiegeTaskFor();
		return null;
	}
	const bool rad = SgSupportDef(d, false);
	const bool jam = SgSupportDef(d, true);
	if (rad || jam) {
		SgSquad(h, dsum, screenM, radars, jams, n, dist);
		if ((n > 0) && ((rad && (radars == 0)) || (jam && (jams == 0))))
			return SiegeTaskFor();
	}
	return null;
}

// Long guns, then a screen against their army near the fort, out of the home and attack pools.
void SiegePull(float h, float dsum, float screenM)
{
	float needScreen = SgFoeNearM(gSgPos, gSgWatchR + gSgReach) * ANSWER_PARITY;
	int pulled = 0;
	for (uint s = 0; (s < gSquads.length()) && (pulled < SG_PULL_PER_LOOK); ++s) {
		IUnitTask@ t = gSquads[s];
		if ((t is null) || t.IsDead() || (t is gSgTask))
			continue;
		const int ft = t.GetFightType();
		if ((ft != int(Task::FightType::DEFEND)) && (ft != int(Task::FightType::ATTACK)))
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if (on is null)
			continue;
		for (uint k = 0; (k < on.length()) && (pulled < SG_PULL_PER_LOOK); ++k) {
			CCircuitUnit@ u = on[k];
			if ((u is null) || (u.circuitDef is null) || SiegeClaimed(int(u.id)))
				continue;
			const int d = int(u.circuitDef.id);
			bool take = false;
			if (SgCarry(d, gSgReach)) {
				take = h * dsum < gSgNeedHD;
				if (take) {
					h += Catalog::gHealth[d];
					dsum += SgD(d);
				}
			} else if ((screenM < needScreen) && !Catalog::gFlyer[d] && (Catalog::gPower[d] > 1.f)
				&& (Market::LineClassOf(d) == Market::LC_TANK)) {
				take = true;
				screenM += Catalog::gCostM[d];
			}
			if (!take)
				continue;
			t.RemoveUnit(u);
			gSgClaim.insertLast(int(u.id));
			++pulled;
			++gSgPulled;
		}
	}
}

void SiegeLook()
{
	const int i = aiMilitaryMgr.GetSiegeFort();
	if (i < 0) {
		SiegeEnd("gone");
		return;
	}
	gSgPos = aiMilitaryMgr.GetFortPos(i);
	gSgReach = aiMilitaryMgr.GetFortVal(i, FV_REACH);
	gSgRadius = aiMilitaryMgr.GetFortVal(i, FV_RADIUS);
	gSgNeedHD = SgNeedHD(i);
	if (gSgLost > gSgWorth) {
		SiegeEnd("lost");
		return;
	}
	float h, dsum, screenM, dist;
	int radars, jams, n;
	SgSquad(h, dsum, screenM, radars, jams, n, dist);
	if (n > gSgPeakN)
		gSgPeakN = n;
	// it marches once the long guns beat the guns and the screen matches their army there, and stays committed after
	if (!gSgReady && (h * dsum >= gSgNeedHD) && (screenM >= SgFoeNearM(gSgPos, gSgWatchR + gSgReach) * ANSWER_PARITY)) {
		gSgReady = true;
		aiMilitaryMgr.SetSiegeReady(true);
		AiLog(Factory::T() + "apex: siege ready t=" + ai.teamId + " key=" + gSgKey + " n=" + n
			+ " hd=" + int(h * dsum) + "/" + int(gSgNeedHD) + " s=" + ((ai.frame - gSgFrom) / SECOND));
	}
	if ((n == 0) && (gSgClaim.length() == 0)) {
		array<int> defs;
		SgBuildable(gSgReach, defs);
		float hH = 0.f, hD = 0.f, haveM = 0.f;
		SgHave(gSgReach, hH, hD, haveM);
		if ((defs.length() == 0) && (haveM <= 0.f)) {
			SiegeEnd("nounits");
			return;
		}
	}
	// the squad marched: its window is shut (CSiegeTask commits at ready)
	if (!gSgReady || !GthOn())
		SiegePull(h, dsum, screenM);
	if (ai.frame >= gSgLogAt) {
		gSgLogAt = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: siege look t=" + ai.teamId + " key=" + gSgKey + " n=" + n
			+ " hd=" + int(h * dsum) + "/" + int(gSgNeedHD) + " screenM=" + int(screenM)
			+ " radar=" + radars + " jam=" + jams + " dist=" + int(dist)
			+ " guns=" + int(aiMilitaryMgr.GetFortVal(i, FV_GUN_N))
			+ " fortM=" + int(aiMilitaryMgr.GetFortVal(i, FV_METAL_M)) + "/" + int(gSgFortM0)
			+ " kill=" + int(gSgKill) + " lost=" + int(gSgLost) + " claimed=" + gSgClaim.length()
			+ " pulled=" + gSgPulled + " s=" + ((ai.frame - gSgFrom) / SECOND));
	}
}

// Siege-fit units' share of the army gap: the long guns the siege still lacks, in this def's units.
float SiegeGapM(int d)
{
	if (!gSgOn || !SgCarry(d, gSgReach))
		return 0.f;
	if (ai.frame >= gSgGapAt + 2 * SECOND) {
		gSgGapAt = ai.frame;
		float m = 0.f;
		SgHave(gSgReach, gSgHaveH, gSgHaveD, m);
	}
	return SgUnitsFor(d, gSgHaveH, gSgHaveD, gSgNeedHD) * Catalog::gCostM[d];
}

// One radar and one jammer per squad (production.as's support demand): the siege squad is one.
float SiegeSupportSlots()
{
	return gSgOn ? 1.f : 0.f;
}

void UpdateSiege()
{
	if (!Builder::gHomeSet)
		return;
	if (gSgNextAt < 0)
		gSgNextAt = 90 * SECOND + (ai.teamId % 15) * 2 * SECOND;
	if (gSgOn && (ai.frame >= gSgLookAt)) {
		gSgLookAt = ai.frame + SG_LOOK;
		SiegeLook();
	}
	if (!gSgOn && (ai.frame >= gSgNextAt) && (ai.GetTunable("apex_siege", TUNE_SIEGE) > 0.f)) {
		gSgNextAt = ai.frame + SG_EVERY;
		SiegeDecide();
	}
	if (ai.frame >= gSgStatAt) {
		gSgStatAt = ai.frame + 60 * SECOND;
		if (gSgDecN + gSgNoFort + gSgNoDef > 0)
			AiLog(Factory::T() + "apex: siege-stat t=" + ai.teamId + " dec=" + gSgDecN + " ex=" + gSgExN
				+ " siege=" + gSgHitN + " gone=" + gSgGoneN + " lost=" + gSgLostN + " nounits=" + gSgNoUnitN
				+ " noFort=" + gSgNoFort + " noDef=" + gSgNoDef + " pulled=" + gSgPulled + " on=" + (gSgOn ? 1 : 0));
	}
}

}  // namespace Military
