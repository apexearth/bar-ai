namespace Market {
// docs/24: one gun is not a defence; the lines face the front; defend the
// raided side. Prices for DefSiteFill, not gates. Guns fight together (strength
// goes with the square of the guns firing at once), so a gun is priced at its
// share of finishing the knot it joins; the siege hazard is spread over
// bearings by what we have seen, mean 1, so the rear gives to the front.

const int FACE_N = 12;
const int KNOT_SITES_MAX = 32;   // work per fill, not a defence count

array<float> gFaceW(FACE_N, 1.f);
int      gFaceAt = -999999;
bool     gFaceOk = false;
AIFloat3 gFaceMid;
float    gFacePriorM = 0.f;
float    gFaceLossM = 0.f;
float    gFaceGrpM = 0.f;
int      gNextFaceLog = 0;

// m spread over the half-plane facing `ang`, by cosine.
void FaceAdd(float ang, float m)
{
	for (int k = 0; k < FACE_N; ++k) {
		const float a = 6.2831853f * float(k) / float(FACE_N);
		const float c = cos(a - ang);
		if (c > 0.f)
			gFaceW[uint(k)] += m * c;
	}
}

void FacePrep()
{
	if (ai.frame - gFaceAt < 2 * SECOND)
		return;
	gFaceAt = ai.frame;
	gFaceOk = false;
	for (int k = 0; k < FACE_N; ++k)
		gFaceW[uint(k)] = 0.f;
	const AIFloat3 mid = gPfRimOk ? gPfMid
			: (Builder::gHomeSet ? Builder::gHomePos : AIFloat3(-1.f, 0.f, -1.f));
	if (!OnMap(mid)) {
		for (int k = 0; k < FACE_N; ++k)
			gFaceW[uint(k)] = 1.f;
		return;
	}
	gFaceMid = mid;
	float rear = ai.GetTunable("apex_wall_rear", TUNE_WALL_REAR);
	if (rear < 0.f) rear = 0.f;
	if (rear > 1.f) rear = 1.f;
	AIFloat3 foe;
	const bool foeOk = FoeRef(foe);
	const float span = foeOk ? foe.distance2D(mid) : 0.f;
	RiskFill();
	gFacePriorM = (gRkHost > 1.f) ? gRkHost : 1.f;
	if (foeOk && (span > 1.f)) {
		const float fa = atan2(foe.z - mid.z, foe.x - mid.x);
		for (int k = 0; k < FACE_N; ++k) {
			const float a = 6.2831853f * float(k) / float(FACE_N);
			gFaceW[uint(k)] += gFacePriorM
					* (rear + (1.f - rear) * (0.5f + 0.5f * cos(a - fa)));
		}
	} else {
		for (int k = 0; k < FACE_N; ++k)
			gFaceW[uint(k)] += gFacePriorM;
	}
	DecayLossField();
	gFaceLossM = 0.f;
	for (uint i = 0; i < gLossX.length(); ++i) {
		const float m = gLossM[i];
		const float dx = gLossX[i] - mid.x;
		const float dz = gLossZ[i] - mid.z;
		if ((m <= 1.f) || (dx * dx + dz * dz < 1.f))
			continue;
		FaceAdd(atan2(dz, dx), m);
		gFaceLossM += m;
	}
	gFaceGrpM = 0.f;
	for (uint g = 0; g < gRkApM.length(); ++g) {
		const float dx = gRkApX[g] - mid.x;
		const float dz = gRkApZ[g] - mid.z;
		const float dd = sqrt(dx * dx + dz * dz);
		if (dd < 1.f)
			continue;
		float prox = (span > 1.f) ? (1.f - dd / span) : 1.f;
		if (prox <= 0.f)
			continue;
		if (prox > 1.f)
			prox = 1.f;
		FaceAdd(atan2(dz, dx), gRkApM[g] * prox);
		gFaceGrpM += gRkApM[g] * prox;
	}
	float sum = 0.f;
	for (int k = 0; k < FACE_N; ++k)
		sum += gFaceW[uint(k)];
	if (sum <= 0.f) {
		for (int k = 0; k < FACE_N; ++k)
			gFaceW[uint(k)] = 1.f;
		return;
	}
	for (int k = 0; k < FACE_N; ++k)
		gFaceW[uint(k)] *= float(FACE_N) / sum;
	gFaceOk = true;
	if (ai.frame >= gNextFaceLog) {
		gNextFaceLog = ai.frame + 60 * SECOND;
		string s = "";
		for (int k = 0; k < FACE_N; ++k)
			s += " " + formatFloat(gFaceW[uint(k)], "", 0, 2);
		AiLog("apex: defface t=" + ai.teamId + " mid=" + int(mid.x) + "," + int(mid.z)
			+ " foeDeg=" + (foeOk ? int(atan2(foe.z - mid.z, foe.x - mid.x) * 57.29578f) : -999)
			+ " priorM=" + int(gFacePriorM) + " lossM=" + int(gFaceLossM)
			+ " walkM=" + int(gFaceGrpM) + " sectors(0deg=+x, 30deg steps):" + s);
	}
}

// The siege hazard's share at this bearing from the base; 1 = the average.
float FaceAt(const AIFloat3& in p)
{
	FacePrep();
	if (!gFaceOk)
		return 1.f;
	const float dx = p.x - gFaceMid.x;
	const float dz = p.z - gFaceMid.z;
	if (dx * dx + dz * dz < 1.f)
		return 1.f;
	float a = atan2(dz, dx);
	if (a < 0.f)
		a += 6.2831853f;
	const float t = a / 6.2831853f * float(FACE_N);
	int k0 = int(t);
	const float f = t - float(k0);
	k0 = k0 % FACE_N;
	const int k1 = (k0 + 1) % FACE_N;
	return gFaceW[uint(k0)] * (1.f - f) + gFaceW[uint(k1)] * f;
}

// The wave a knot must beat: the raid metal they field, never less than two
// of this gun (one gun is not a defence).
float KnotWave(float adds)
{
	RiskFill();
	const float two = 2.f * adds;
	return (gRkRaid > two) ? gRkRaid : two;
}

// A gun's share of finishing the knot it joins, against the linear price.
float KnotKappa(float supCover, float wave)
{
	if ((wave <= 1.f) || (supCover <= 0.f))
		return 1.f;
	if (supCover < wave)
		return 1.f + supCover / wave;
	return wave / supCover;
}

// Our standing guns, clustered by mutual reach (a light tower's range); cached
// on the tower field's revision.
array<float> gKnX;
array<float> gKnZ;
array<int>   gKnN;
int gKnRev = -1;
int gKnAt = -999999;
int gNextKnotLog = 0;

void KnotPrep()
{
	PfRebuild();
	if ((gKnRev == gPfTwRev) && (ai.frame - gKnAt < 30 * SECOND))
		return;
	gKnRev = gPfTwRev;
	gKnAt = ai.frame;
	gKnX.resize(0);
	gKnZ.resize(0);
	gKnN.resize(0);
	const float r = Brain::LightTowerRange();
	const float r2 = r * r;
	const uint nGun = gProtPos[PROT_DEF].length();
	const uint nDef = gProtDefId[PROT_DEF].length();
	for (uint i = 0; i < nGun; ++i) {
		const int d = (i < nDef) ? gProtDefId[PROT_DEF][i] : -1;
		if ((d <= 0) || (d > Catalog::gDefCount) || (Catalog::gSurfT[d] <= 0.01f))
			continue;
		const AIFloat3 p = gProtPos[PROT_DEF][i];
		int hit = -1;
		for (uint j = 0; (j < gKnX.length()) && (hit < 0); ++j) {
			const float dx = gKnX[j] - p.x;
			const float dz = gKnZ[j] - p.z;
			if (dx * dx + dz * dz <= r2)
				hit = int(j);
		}
		if (hit < 0) {
			gKnX.insertLast(p.x);
			gKnZ.insertLast(p.z);
			gKnN.insertLast(1);
			continue;
		}
		const uint h = uint(hit);
		const float nAfter = float(gKnN[h] + 1);
		gKnX[h] += (p.x - gKnX[h]) / nAfter;
		gKnZ[h] += (p.z - gKnZ[h]) / nAfter;
		gKnN[h] += 1;
	}
	if (ai.frame >= gNextKnotLog) {
		gNextKnotLog = ai.frame + 60 * SECOND;
		int n1 = 0, n2 = 0, n3 = 0, n4 = 0, guns = 0;
		for (uint j = 0; j < gKnN.length(); ++j) {
			guns += gKnN[j];
			if (gKnN[j] == 1) ++n1;
			else if (gKnN[j] == 2) ++n2;
			else if (gKnN[j] == 3) ++n3;
			else ++n4;
		}
		AiLog("apex: defknot t=" + ai.teamId + " guns=" + guns + " knots=" + gKnN.length()
			+ " size1=" + n1 + " size2=" + n2 + " size3=" + n3 + " size4plus=" + n4
			+ " raidM=" + int(gRkRaid) + " r=" + int(r));
	}
}

// One candidate per knot, a footprint out from the base on the knot's bearing:
// the executor's lattice probe puts the gun on the nearest free cell there.
void KnotSites(array<AIFloat3>& inout sites, int d)
{
	KnotPrep();
	const float cells = float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	const float step = sqrt(cells) * 16.f;
	AIFloat3 foe;
	const bool foeOk = FoeRef(foe);
	const uint n = (gKnX.length() < uint(KNOT_SITES_MAX)) ? gKnX.length() : uint(KNOT_SITES_MAX);
	for (uint j = 0; j < n; ++j) {
		const AIFloat3 c(gKnX[j], 0.f, gKnZ[j]);
		AIFloat3 dir = gPfRimOk ? (c - gPfMid) : AIFloat3(0.f, 0.f, 0.f);
		if ((dir.SqLength2D() < 1.f) && foeOk)
			dir = foe - c;
		AIFloat3 s = c;
		if (dir.SqLength2D() >= 1.f) {
			dir.SafeNormalize2D();
			const AIFloat3 s2 = c + dir * step;
			if (OnMap(s2))
				s = s2;
		}
		if (OnMap(s))
			sites.insertLast(s);
	}
}
}  // namespace Market
