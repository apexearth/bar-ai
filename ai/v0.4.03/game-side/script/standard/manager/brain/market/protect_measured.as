namespace Market {
// DEFENCE ON THE MEASURED ATTACK RATE (apex_def_measured; his 2026-10-15: "if
// they aren't pushing we can put our efforts into smarter places"). An arrival
// is a rising edge of seen armed enemy metal within apex_threat_r of a probe
// (home and each standing mex); probes are swept a fifth per update.

const int DM_MAX = 24;
array<float> gDmAX, gDmAZ, gDmAN;   // arrivals, decayed counts
array<float> gDmLX, gDmLZ, gDmLN;   // our structure deaths, decayed counts
int gDmLast = 0;
array<float> gDmPX, gDmPZ, gDmPPrev;
int gDmPL = -1, gDmPO = -1;
uint gDmPIdx = 0;
int gDmArrN = 0, gDmLossN = 0;
float gDmArrM = 0.f;
float gDmTgtRaw = 0.f, gDmTgtK = 1.f;

bool gDmOnSet = false;
bool gDmOn = false;
float gDmR = 900.f;
float gDmH = 120.f;
bool DefMeasuredOn()
{
	if (!gDmOnSet) {
		gDmOnSet = true;
		gDmOn = ai.GetTunable("apex_def_measured", TUNE_DEF_MEASURED) > 0.5f;
		gDmR = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
		if (gDmR <= 1.f)
			gDmR = 900.f;
		gDmH = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
		if (gDmH <= 1.f)
			gDmH = TUNE_EXPOSED_LOSS_S;
	}
	return gDmOn;
}

void DmDecay()
{
	const int step = ai.frame - gDmLast;
	if (step <= 0)
		return;
	gDmLast = ai.frame;
	float k = 1.f - (float(step) / 30.f) / LossTau();
	if (k < 0.f)
		k = 0.f;
	for (uint i = 0; i < gDmAN.length(); ++i)
		gDmAN[i] *= k;
	for (uint i = 0; i < gDmLN.length(); ++i)
		gDmLN[i] *= k;
}

void DmAdd(array<float>& inout xs, array<float>& inout zs, array<float>& inout ns, float x, float z)
{
	DmDecay();
	const float r2 = LOSS_MERGE_R * LOSS_MERGE_R;
	for (uint i = 0; i < ns.length(); ++i) {
		const float dx = xs[i] - x;
		const float dz = zs[i] - z;
		if (dx * dx + dz * dz < r2) {
			ns[i] += 1.f;
			return;
		}
	}
	if (int(ns.length()) >= DM_MAX) {
		uint worst = 0;
		for (uint i = 1; i < ns.length(); ++i)
			if (ns[i] < ns[worst])
				worst = i;
		if (ns[worst] >= 1.f)
			return;
		xs.removeAt(worst);
		zs.removeAt(worst);
		ns.removeAt(worst);
	}
	xs.insertLast(x);
	zs.insertLast(z);
	ns.insertLast(1.f);
}

void DmNoteLoss(const AIFloat3& in at)
{
	++gDmLossN;
	DmAdd(gDmLX, gDmLZ, gDmLN, at.x, at.z);
}

void DmProbesRebuild()
{
	gDmPL = gLStamp;
	gDmPO = gOwnStamp;
	array<float> px, pz, pp;
	px.insertLast(Builder::gHomePos.x);
	pz.insertLast(Builder::gHomePos.z);
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		px.insertLast(gLPos[uint(rows[q])].x);
		pz.insertLast(gLPos[uint(rows[q])].z);
	}
	// A probe that stood before keeps its last reading, or every rebuild would
	// re-arm an edge on a raid already counted.
	for (uint i = 0; i < px.length(); ++i) {
		float prev = -1.f;
		for (uint j = 0; j < gDmPX.length(); ++j) {
			if ((gDmPX[j] == px[i]) && (gDmPZ[j] == pz[i])) {
				prev = gDmPPrev[j];
				break;
			}
		}
		pp.insertLast(prev);
	}
	gDmPX = px;
	gDmPZ = pz;
	gDmPPrev = pp;
	if (gDmPIdx >= gDmPX.length())
		gDmPIdx = 0;
}

// Per update: a fifth of the probes, one grid query each.
void DefMeasuredStep()
{
	if (!Builder::gHomeSet)
		return;
	DefMeasuredOn();
	if ((gDmPL != gLStamp) || (gDmPO != gOwnStamp) || (gDmPX.length() == 0))
		DmProbesRebuild();
	const uint n = gDmPX.length();
	uint todo = n / 5 + 1;
	while ((todo > 0) && (n > 0)) {
		--todo;
		if (gDmPIdx >= n)
			gDmPIdx = 0;
		const uint i = gDmPIdx++;
		const AIFloat3 p(gDmPX[i], 0.f, gDmPZ[i]);
		const float m = ai.GetEnemyArmedCostNear(p, gDmR);
		if ((gDmPPrev[i] >= 0.f) && (gDmPPrev[i] < 1.f) && (m >= 1.f)) {
			DmAdd(gDmAX, gDmAZ, gDmAN, p.x, p.z);
			++gDmArrN;
			gDmArrM += m;
		}
		gDmPPrev[i] = m;
	}
	DefMeasuredLog();
}

// What the enemy has shown anywhere, as a per-site rate: every arrival and
// loss spread over our probes, plus their seen army against ours over the
// time the nearest of it needs to reach us.
int gDmFlAt = -1;
float gDmFloor = 0.f, gDmFlSpread = 0.f, gDmFlSeen = 0.f;
float DefMeasuredFloor()
{
	if (gDmFlAt == ai.frame)
		return gDmFloor;
	gDmFlAt = ai.frame;
	DmDecay();
	const float tau = LossTau();
	float a = 0.f, l = 0.f;
	for (uint i = 0; i < gDmAN.length(); ++i)
		a += gDmAN[i];
	for (uint i = 0; i < gDmLN.length(); ++i)
		l += gDmLN[i];
	const float np = float((gDmPX.length() > 0) ? gDmPX.length() : 1);
	gDmFlSpread = ((a > l) ? a : l) / tau / np;
	const float seen = Military::EnemyArmyCost() * AnswerShare();
	const float ours = Military::OurArmyNow();
	gDmFlSeen = 0.f;
	if (seen > 0.f) {
		const float eta = (Military::gDgNearEta >= 0.f) ? Military::gDgNearEta : tau;
		gDmFlSeen = (seen / (seen + ((ours > 0.f) ? ours : 0.f))) / (tau + eta);
	}
	gDmFloor = gDmFlSpread + gDmFlSeen;
	return gDmFloor;
}

// Lethal arrivals per second at this ground: the arrivals or our losses within
// twice the loss-merge radius, whichever is more, over the loss window.
float DefMeasuredAt(const AIFloat3& in pos)
{
	DmDecay();
	const float rr2 = 4.f * LOSS_MERGE_R * LOSS_MERGE_R;
	float a = 0.f, l = 0.f;
	for (uint i = 0; i < gDmAN.length(); ++i) {
		const float dx = gDmAX[i] - pos.x;
		const float dz = gDmAZ[i] - pos.z;
		if (dx * dx + dz * dz < rr2)
			a += gDmAN[i];
	}
	for (uint i = 0; i < gDmLN.length(); ++i) {
		const float dx = gDmLX[i] - pos.x;
		const float dz = gDmLZ[i] - pos.z;
		if (dx * dx + dz * dz < rr2)
			l += gDmLN[i];
	}
	return ((a > l) ? a : l) / LossTau() + DefMeasuredFloor();
}

// The chance an attack lands inside the exposure window, as a share of the
// chance the 1/apex_exposed_loss_s prior assumed: 1 at the prior's rate.
float DefMeasuredPressure(float rate)
{
	DefMeasuredOn();
	const float x = rate * gDmH;
	if (x <= 0.f)
		return 0.f;
	return (1.f - pow(2.718282f, -x)) / (1.f - pow(2.718282f, -1.f));
}

// Mean over the probes, on a 5 s clock: the holding is sized for every site.
int gDmMeanAt = -999999;
float gDmMean = 0.f, gDmMexMean = 0.f;
float DefMeasuredMean()
{
	if (ai.frame < gDmMeanAt + 5 * SECOND)
		return gDmMean;
	gDmMeanAt = ai.frame;
	float s = 0.f, sm = 0.f;
	const uint n = gDmPX.length();
	for (uint i = 0; i < n; ++i) {
		const float r = DefMeasuredAt(AIFloat3(gDmPX[i], 0.f, gDmPZ[i]));
		s += r;
		if (i > 0)
			sm += r;
	}
	gDmMean = (n > 0) ? (s / float(n)) : DefMeasuredFloor();
	gDmMexMean = (n > 1) ? (sm / float(n - 1)) : gDmMean;
	return gDmMean;
}

int gDmNextLog = 0;
int gDmLastOffered = 0, gDmLastWon = 0, gDmLastBuilt = 0;
void DefMeasuredLog()
{
	if (ai.frame < gDmNextLog)
		return;
	gDmNextLog = ai.frame + 60 * SECOND;
	DefMeasuredMean();
	const float prior = 1.f / gDmH;
	const float homeM = DefMeasuredAt(Builder::gHomePos);
	DefenceTarget();
	AiLog(Factory::T() + "apex: defmeasured-stat t=" + ai.teamId + " on=" + (gDmOn ? 1 : 0)
		+ " prior=" + formatFloat(prior, "", 0, 5)
		+ " mexRate=" + formatFloat(gDmMexMean, "", 0, 5)
		+ " siege=" + formatFloat(SiegeExpect(Builder::gHomePos), "", 0, 5)
		+ " homeRate=" + formatFloat(homeM, "", 0, 5)
		+ " meanRate=" + formatFloat(gDmMean, "", 0, 5)
		+ " floor=" + formatFloat(gDmFlSpread, "", 0, 5) + "+" + formatFloat(gDmFlSeen, "", 0, 5)
		+ " k=" + formatFloat(DefMeasuredPressure(gDmMean), "", 0, 3)
		+ " target=" + int(gDmTgtRaw) + "->" + int(gDmTgtRaw * gDmTgtK)
		+ " have=" + int(DefenceValue())
		+ " arrivals=" + gDmArrN + " arrM=" + int(gDmArrM) + " losses=" + gDmLossN
		+ " probes=" + gDmPX.length()
		+ " offered=" + (gDmOffered - gDmLastOffered) + "/" + gDmOffered
		+ " won=" + (gDmWon - gDmLastWon) + "/" + gDmWon
		+ " built=" + (gDmBuilt - gDmLastBuilt) + "/" + gDmBuilt);
	gDmLastOffered = gDmOffered;
	gDmLastWon = gDmWon;
	gDmLastBuilt = gDmBuilt;
}

}  // namespace Market
