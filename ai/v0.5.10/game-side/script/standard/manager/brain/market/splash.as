namespace Market {

// SPLASH AGAINST THE BALL THEY BRING, for towers and splash units (his 2026-10-13: "to defeat that much
// metal in tanks you need some AOE damage"). Every 10 s, each visible enemy
// ground fighter's neighbours by distance, binned; a shell of radius r then
// catches, on average, the neighbours inside r weighted by the linear falloff
// (1 - d/r). The last reading holds while their army is out of sight.

const int SPL_BINS = 32;
const float SPL_BIN = 16.f;   // elmos: 32 bins cover a 512 radius
const uint SPL_CAP = 300;     // targets per refresh: 45k pair checks at most
array<float> gSplNear(SPL_BINS, 0.f);
array<float> gSplNearM(SPL_BINS, 0.f);   // the same pairs, by the neighbour's metal
int gSplTargets = 0;
float gSplMetal = 0.f;
int gSplAt = -999999;
int gSplLogAt = 0;

void SplashRefresh()
{
	if (ai.frame < gSplAt + 10 * SECOND)
		return;
	gSplAt = ai.frame;
	array<AIFloat3> p;
	array<float> c;
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; (i < total) && (p.length() < SPL_CAP); ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount) || !Catalog::gMobile[d] || Catalog::gFlyer[d]
			|| (Catalog::gPower[d] <= 1.f))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		p.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
		c.insertLast(Catalog::gCostM[d]);
	}
	if (p.length() < 2)
		return;
	for (int b = 0; b < SPL_BINS; ++b) {
		gSplNear[b] = 0.f;
		gSplNearM[b] = 0.f;
	}
	const float reach = float(SPL_BINS) * SPL_BIN;
	float metal = 0.f;
	for (uint i = 0; i < p.length(); ++i) {
		metal += c[i];
		for (uint j = i + 1; j < p.length(); ++j) {
			const float dd = p[i].distance2D(p[j]);
			if (dd < reach) {
				const int b = int(dd / SPL_BIN);
				gSplNear[b] += 2.f;
				gSplNearM[b] += c[i] + c[j];
			}
		}
	}
	gSplTargets = int(p.length());
	gSplMetal = metal;
	if (ai.frame >= gSplLogAt) {
		gSplLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: splash t=" + ai.teamId + " targets=" + gSplTargets
			+ " hits@48=" + formatFloat(SplashHits(48.f), "", 0, 2)
			+ " @96=" + formatFloat(SplashHits(96.f), "", 0, 2)
			+ " @192=" + formatFloat(SplashHits(192.f), "", 0, 2));
	}
}

// Extra enemies one shell of this radius catches, weighted by falloff.
float SplashHits(float r)
{
	if ((r <= 1.f) || (gSplTargets == 0))
		return 0.f;
	float hits = 0.f;
	for (int b = 0; b < SPL_BINS; ++b) {
		const float mid = (float(b) + 0.5f) * SPL_BIN;
		if (mid >= r)
			break;
		hits += gSplNear[b] * (1.f - mid / r);
	}
	return hits / float(gSplTargets);
}

float SplashMul(int d)
{
	SplashRefresh();
	return 1.f + SplashHits(Catalog::gAoe[d]);
}

// Mean metal standing inside r of one of their fighters, the fighter excluded.
float SplashMetalNear(float r)
{
	if ((r <= 1.f) || (gSplTargets == 0))
		return 0.f;
	float m = 0.f;
	for (int b = 0; b < SPL_BINS; ++b) {
		if ((float(b) + 0.5f) * SPL_BIN >= r)
			break;
		m += gSplNearM[b];
	}
	return m / float(gSplTargets);
}

// Mobile splash against their ball (apex_aoe_vs_blob). A shell catching h extra
// enemies deals (1 + h) single-target shots, priced as worth.as prices dps;
// h/(1+h) is the share of its damage that exists only because they bunch.

bool AoeOn()
{
	return ai.GetTunable("apex_aoe_vs_blob", TUNE_AOE_VS_BLOB) > 0.f;
}

bool AoeCapable(int d)
{
	return Catalog::gMobile[d] && !Catalog::gFlyer[d] && !Catalog::gKamikaze[d]
		&& !Catalog::gBuilder[d] && (Catalog::gPower[d] > 1.f)
		&& (Catalog::gSurfT[d] > 0.01f) && (Catalog::gAoe[d] > 1.f);
}

float AoeHits(int d)
{
	if (!AoeCapable(d))
		return 0.f;
	SplashRefresh();
	return SplashHits(Catalog::gAoe[d]);
}

float AoeShareOf(float h)
{
	return h / (1.f + h);
}

// Our standing splash, each unit by the share of its damage the bunching gives.
float gAoeOwnV = 0.f;
int gAoeOwnStamp = -1;
int gAoeOwnAt = -1;

float AoeOwnValue()
{
	SplashRefresh();
	if ((gAoeOwnStamp == gOwnStamp) && (gAoeOwnAt == gSplAt))
		return gAoeOwnV;
	gAoeOwnStamp = gOwnStamp;
	gAoeOwnAt = gSplAt;
	float v = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if ((gOwnCount[d] <= 0) || !AoeCapable(d) || ReachDead(d))
			continue;
		v += float(gOwnCount[d]) * Catalog::gCostM[d] * AoeShareOf(SplashHits(Catalog::gAoe[d]));
	}
	gAoeOwnV = v;
	return v;
}

// Splash metal owed against their ball at this unit's radius: our share of their
// army times the bunching share, never more than our whole army target.
float AoeTargetM(float h, float armyT)
{
	SplashRefresh();
	float t = gSplMetal * AnswerShare() * AoeShareOf(h);
	if (t > armyT)
		t = armyT;
	return t;
}

// 0..1: how much of a splash unit's role weight comes from the clump.
float AoeRoleW(float h, float armyT, float ownV)
{
	const float t = AoeTargetM(h, armyT);
	if (t <= 1.f)
		return 0.f;
	float g = (t - ownV) / t;
	if (g < 0.f)
		g = 0.f;
	return AoeShareOf(h) * g;
}

// What the factories priced, for the minute line.
array<int> gAoeSeen;
array<float> gAoeMulOf;
array<float> gAoeRwOf;
array<float> gAoeRwNoOf;
array<float> gAoeVOf;
array<float> gAoeVNoOf;
int gAoeStatAt = 0;

void AoeRecord(int d, float mul, float rw, float rwNo, float v, float vNo)
{
	if (int(gAoeMulOf.length()) <= Catalog::gDefCount) {
		gAoeMulOf.resize(Catalog::gDefCount + 1);
		gAoeRwOf.resize(Catalog::gDefCount + 1);
		gAoeRwNoOf.resize(Catalog::gDefCount + 1);
		gAoeVOf.resize(Catalog::gDefCount + 1);
		gAoeVNoOf.resize(Catalog::gDefCount + 1);
		for (int i = 0; i <= Catalog::gDefCount; ++i)
			gAoeMulOf[i] = 0.f;
	}
	if (gAoeMulOf[d] <= 0.f)
		gAoeSeen.insertLast(d);
	gAoeMulOf[d] = mul;
	gAoeRwOf[d] = rw;
	gAoeRwNoOf[d] = rwNo;
	gAoeVOf[d] = v;
	gAoeVNoOf[d] = vNo;
}

void AoeStatLog(float armyT)
{
	if (ai.frame < gAoeStatAt)
		return;
	gAoeStatAt = ai.frame + 60 * SECOND;
	SplashRefresh();
	float bigM = 0.f;
	int bigN = 0;
	const int ng = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < ng; ++gi) {
		float m = 0.f;
		int n = 0;
		const int nu = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nu; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if ((d <= 0) || (d > Catalog::gDefCount) || !Catalog::gMobile[d] || Catalog::gFlyer[d]
				|| (Catalog::gPower[d] <= 1.f))
				continue;
			m += Catalog::gCostM[d];
			++n;
		}
		if (m > bigM) {
			bigM = m;
			bigN = n;
		}
	}
	string s = "apex: aoe-stat t=" + ai.teamId + " on=" + (AoeOn() ? 1 : 0)
		+ " bigGroupM=" + int(bigM) + " bigGroupN=" + bigN
		+ " seenM=" + int(gSplMetal) + " seenN=" + gSplTargets
		+ " share=" + formatFloat(AnswerShare(), "", 0, 2)
		+ " ownSplashM=" + int(AoeOwnValue());
	const array<float> radii = {64.f, 128.f, 256.f};
	for (uint i = 0; i < radii.length(); ++i) {
		const float r = radii[i];
		s += " dens@" + int(r) + "=" + formatFloat(SplashMetalNear(r) * 1000.f / (3.14159f * r * r), "", 0, 2)
			+ "/hits" + formatFloat(SplashHits(r), "", 0, 2);
	}
	array<int> top;
	for (uint i = 0; i < gAoeSeen.length(); ++i) {
		const int d = gAoeSeen[i];
		uint at = top.length();
		for (uint j = 0; j < top.length(); ++j) {
			if (gAoeMulOf[d] > gAoeMulOf[top[j]]) {
				at = j;
				break;
			}
		}
		if (at < 3)
			top.insertAt(at, d);
		if (top.length() > 3)
			top.removeLast();
	}
	for (uint j = 0; j < top.length(); ++j) {
		const int d = top[j];
		const float h = SplashHits(Catalog::gAoe[d]);
		s += " " + Catalog::Def(d).GetName() + "(aoe" + int(Catalog::gAoe[d])
			+ ",x" + formatFloat(gAoeMulOf[d], "", 0, 2)
			+ ",owed" + int(AoeTargetM(h, armyT))
			+ ",r" + formatFloat(gAoeRwOf[d], "", 0, 2) + "/" + formatFloat(gAoeRwNoOf[d], "", 0, 2)
			+ ",v" + formatFloat(gAoeVOf[d] * 1000.f, "", 0, 1)
			+ "/" + formatFloat(gAoeVNoOf[d] * 1000.f, "", 0, 1) + ")";
	}
	AiLog(s);
}

}  // namespace Market
