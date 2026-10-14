namespace Market {

// SPLASH AGAINST THE BALL THEY BRING, for towers (his 2026-10-13: "to defeat that much
// metal in tanks you need some AOE damage"). Every 10 s, each visible enemy
// ground fighter's neighbours by distance, binned; a shell of radius r then
// catches, on average, the neighbours inside r weighted by the linear falloff
// (1 - d/r). The last reading holds while their army is out of sight.

const int SPL_BINS = 32;
const float SPL_BIN = 16.f;   // elmos: 32 bins cover a 512 radius
const uint SPL_CAP = 300;     // targets per refresh: 45k pair checks at most
array<float> gSplNear(SPL_BINS, 0.f);
int gSplTargets = 0;
int gSplAt = -999999;
int gSplLogAt = 0;

void SplashRefresh()
{
	if (ai.frame < gSplAt + 10 * SECOND)
		return;
	gSplAt = ai.frame;
	array<AIFloat3> p;
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
	}
	if (p.length() < 2)
		return;
	for (int b = 0; b < SPL_BINS; ++b)
		gSplNear[b] = 0.f;
	const float reach = float(SPL_BINS) * SPL_BIN;
	for (uint i = 0; i < p.length(); ++i) {
		for (uint j = i + 1; j < p.length(); ++j) {
			const float dd = p[i].distance2D(p[j]);
			if (dd < reach)
				gSplNear[int(dd / SPL_BIN)] += 2.f;
		}
	}
	gSplTargets = int(p.length());
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

}  // namespace Market
