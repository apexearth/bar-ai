namespace Market {

//------------------------------------------------------------------------------
// KEEP-OUT DETECTION (apexearth 2026-10-09: "we should have 'keep out'
// detection with our defenses ... complete coverage to prevent enemy units
// from getting into our backline", and "our defenses + all ally defenses").
//
// The backline is the ALLIANCE's: the convex hull of every allied seat's
// generators, converters, storage, nanos and labs (ours and allies', humans
// included), so the ground between two allied bases is interior. Its
// perimeter is pushed out to where an enemy could shoot the rim from, sampled,
// and each sample asks: can their ground walk here, and how much allied gun
// power reaches it. Runs of reachable samples whose guns fall short of the
// wave are gaps; each gap goes to the nearest of OUR AIs (or whoever claimed
// it on the team board), and the owner's defence proposer offers a site in it.
// Like the stuck watchdog: measured continuously, logged, acted on.
//------------------------------------------------------------------------------

const int KO_IDLE = 0, KO_GATHER = 1, KO_SAMPLE = 2, KO_FINISH = 3;
const int KO_PER_CALL = 12;            // samples read per update: spread, not batched
const int KO_BOARD = 5000;             // team-board claims: x, z, team+1, until
const int KO_CLAIMS = 32;
const string TV_KO_AT = "koat";        // frame of this seat's last finished census

int gKoStage = KO_IDLE;
int gKoPassAt = -999999;
int gKoLogAt = 0;
int gKoSumAt = 0;
array<int> gKoSensDef;                 // per def: -1 unknown, 0 no, 1 sensitive

// The pass being built.
array<float> gKoPX;                    // sensitive points, alliance-wide
array<float> gKoPZ;
array<float> gKoPW;
int gKoOwnPts = 0;
AIFloat3 gKoMid;
float gKoSpacing = 0.f;
float gKoStandoff = 0.f;
float gKoNeed = 0.f;
float gKoWave = 0.f;
bool gKoFoeOk = false;
AIFloat3 gKoFoe;
array<float> gKoSX;
array<float> gKoSZ;
array<float> gKoSCos;
array<bool> gKoSWalk;
array<float> gKoSCover;
int gKoCursor = 0;
float gKoStep = 0.f;
float gKoPerim = 0.f;
int gKoHullN = 0;

// The last finished pass: what the proposer and the leak join read.
bool gKoOk = false;
int gKoDoneAt = -999999;
array<float> gKoDX;
array<float> gKoDZ;
array<bool> gKoDWalk;
array<float> gKoDCover;
array<int> gKoDGap;                    // gap index of each sample, -1 held/closed
float gKoDStep = 0.f;
float gKoDNeed = 0.f;
// Gaps of the last pass, alliance-wide.
array<float> gKoGX;                    // the site: the gap's most exposed sample
array<float> gKoGZ;
array<float> gKoGMX;                   // the run's middle, for matching passes
array<float> gKoGMZ;
array<float> gKoGLen;
array<float> gKoGOpen;
array<float> gKoGCos;
array<float> gKoGThreat;
array<float> gKoGT2;
array<float> gKoGEta;
array<float> gKoGScore;
array<int> gKoGOwner;
array<int> gKoGId;
array<int> gKoGRun;                    // the uncovered run a piece was cut from
array<float> gKoRunLen;
int gKoNextId = 0;
// Our own share of them, ranked by score.
array<int> gKoOwnG;                    // gap index
array<float> gKoOwnShape;              // score / best owned score
array<float> gKoOwnRing;               // nano build power standing at the site
array<int> gKoIdSlot;                  // gap id -> index in gKoOwnG, -1 none
// Per election: the quickest gun of this hand at an owned gap.
int gKoElec = 0;
array<int> gKoElAt;
array<float> gKoElBest;
array<float> gKoElBestT2;

// Census figures for the logs.
float gKoCov = 0.f, gKoHeld = 0.f, gKoOpenFrac = 0.f;
int gKoReachN = 0, gKoAllyPts = 0;
// Game totals.
int gKoPasses = 0;
float gKoCovSum = 0.f, gKoHeldSum = 0.f, gKoOpenSum = 0.f, gKoWorstLen = 0.f;
int gKoLeakN = 0, gKoLeakGap = 0, gKoLeakUncov = 0, gKoLeakOwn = 0;
float gKoLeakM = 0.f, gKoLeakGapM = 0.f;
int gKoNewGapN = 0, gKoWonN = 0, gKoLateN = 0, gKoT1N = 0, gKoPickN = 0, gKoClaimN = 0;

bool KoSensitive(int d)
{
	if (!Catalog::ValidId(d))
		return false;
	if (int(gKoSensDef.length()) <= d) {
		const uint was = gKoSensDef.length();
		gKoSensDef.resize(uint(d + 1));
		for (uint i = was; i < gKoSensDef.length(); ++i)
			gKoSensDef[i] = -1;
	}
	if (gKoSensDef[d] < 0) {
		const string c = LeakCls(d);
		gKoSensDef[d] = ((c == "eco") || (c == "nano") || (c == "lab")) ? 1 : 0;
	}
	return gKoSensDef[d] > 0;
}

void KoGather()
{
	gKoPX.resize(0);
	gKoPZ.resize(0);
	gKoPW.resize(0);
	gKoOwnPts = 0;
	gKoAllyPts = 0;
	array<CCircuitUnit@>@ st = ai.GetOwnStructsNear(Builder::gHomePos, 0.f);
	for (uint i = 0; (st !is null) && (i < st.length()); ++i) {
		CCircuitUnit@ u = st[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const int d = int(u.circuitDef.id);
		if (!KoSensitive(d))
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		if (!OnMap(p))
			continue;
		gKoPX.insertLast(p.x);
		gKoPZ.insertLast(p.z);
		gKoPW.insertLast(Catalog::gCostM[d]);
		++gKoOwnPts;
	}
	const array<float>@ al = ai.GetAllyStatics();
	for (uint k = 0; (al !is null) && (k + 2 < al.length()); k += 3) {
		const int d = int(al[k + 2]);
		if (!KoSensitive(d))
			continue;
		gKoPX.insertLast(al[k]);
		gKoPZ.insertLast(al[k + 1]);
		gKoPW.insertLast(Catalog::gCostM[d]);
		++gKoAllyPts;
	}
}

// The hull of the gathered points (outliers past the wall's own reach cap
// dropped), its perimeter pushed out by the standoff, sampled at spacing.
bool KoHullSamples()
{
	const uint n = gKoPX.length();
	if (n == 0)
		return false;
	float sx = 0.f, sz = 0.f, sw = 0.f;
	for (uint i = 0; i < n; ++i) {
		const float w = (gKoPW[i] > 1.f) ? gKoPW[i] : 1.f;
		sx += gKoPX[i] * w;
		sz += gKoPZ[i] * w;
		sw += w;
	}
	gKoMid = AIFloat3(sx / sw, 0.f, sz / sw);
	float sd2 = 0.f;
	for (uint i = 0; i < n; ++i) {
		const float w = (gKoPW[i] > 1.f) ? gKoPW[i] : 1.f;
		const float dx = gKoPX[i] - gKoMid.x, dz = gKoPZ[i] - gKoMid.z;
		sd2 += w * (dx * dx + dz * dz);
	}
	const float capR = sqrt(sd2 / sw) * ai.GetTunable("apex_wall_reach", TUNE_WALL_REACH);
	// Sorted on an 8-elmo key (x major), duplicates dropped: one footprint
	// square is finer than anything the ring resolves.
	array<int> keys;
	for (uint i = 0; i < n; ++i) {
		const float dx = gKoPX[i] - gKoMid.x, dz = gKoPZ[i] - gKoMid.z;
		if ((capR > 1.f) && (dx * dx + dz * dz > capR * capR))
			continue;
		const int kx = int(gKoPX[i] / 8.f);
		const int kz = int(gKoPZ[i] / 8.f);
		if ((kx < 0) || (kz < 0) || (kx >= 8192) || (kz >= 8192))
			continue;
		keys.insertLast(kx * 8192 + kz);
	}
	if (keys.length() == 0)
		return false;
	keys.sortAsc();
	array<float> hx;
	array<float> hz;
	array<float> qx;
	array<float> qz;
	int lastKey = -1;
	for (uint i = 0; i < keys.length(); ++i) {
		if (keys[i] == lastKey)
			continue;
		lastKey = keys[i];
		qx.insertLast(float(keys[i] / 8192) * 8.f);
		qz.insertLast(float(keys[i] % 8192) * 8.f);
	}
	// Andrew's monotone chain: counter-clockwise in (x, z).
	const int m = int(qx.length());
	if (m >= 3) {
		for (int i = 0; i < m; ++i) {
			while (hx.length() >= 2) {
				const uint t = hx.length();
				const float cr = (hx[t - 1] - hx[t - 2]) * (qz[i] - hz[t - 2])
						- (hz[t - 1] - hz[t - 2]) * (qx[i] - hx[t - 2]);
				if (cr > 0.f)
					break;
				hx.removeLast();
				hz.removeLast();
			}
			hx.insertLast(qx[i]);
			hz.insertLast(qz[i]);
		}
		const uint lower = hx.length() + 1;
		for (int i = m - 2; i >= 0; --i) {
			while (hx.length() >= lower) {
				const uint t = hx.length();
				const float cr = (hx[t - 1] - hx[t - 2]) * (qz[i] - hz[t - 2])
						- (hz[t - 1] - hz[t - 2]) * (qx[i] - hx[t - 2]);
				if (cr > 0.f)
					break;
				hx.removeLast();
				hz.removeLast();
			}
			hx.insertLast(qx[i]);
			hz.insertLast(qz[i]);
		}
		hx.removeLast();
		hz.removeLast();
	} else {
		hx = qx;
		hz = qz;
	}
	const int hn = int(hx.length());
	gKoHullN = hn;
	const float s = gKoStandoff;
	// Edge normals (outward for a counter-clockwise hull), then the offset
	// path's length: every edge plus the arc turned at every vertex.
	array<float> nx(uint(hn), 0.f);
	array<float> nz(uint(hn), 0.f);
	array<float> el(uint(hn), 0.f);
	array<float> a0(uint(hn), 0.f);
	array<float> sw2(uint(hn), 0.f);
	float total = 0.f;
	if (hn == 1) {
		a0[0] = 0.f;
		sw2[0] = 6.2831853f;
		total = s * 6.2831853f;
	} else {
		for (int i = 0; i < hn; ++i) {
			const int j = (i + 1) % hn;
			float dx = hx[j] - hx[i], dz = hz[j] - hz[i];
			const float ln = sqrt(dx * dx + dz * dz);
			el[i] = ln;
			if (ln > 0.01f) {
				dx /= ln;
				dz /= ln;
			}
			nx[i] = dz;
			nz[i] = -dx;
			total += ln;
		}
		for (int i = 0; i < hn; ++i) {
			const int p = (i + hn - 1) % hn;
			const float aP = atan2(nz[p], nx[p]);
			float d = atan2(nz[i], nx[i]) - aP;
			while (d < 0.f)
				d += 6.2831853f;
			while (d >= 6.2831853f)
				d -= 6.2831853f;
			if ((hn == 2) && (d < 0.01f))
				d = 3.1415927f;
			a0[i] = aP;
			sw2[i] = d;
			total += s * d;
		}
	}
	gKoPerim = total;
	gKoSX.resize(0);
	gKoSZ.resize(0);
	gKoSCos.resize(0);
	if (total < 1.f)
		return false;
	int ns = int(total / gKoSpacing + 0.5f);
	if (ns < 3)
		ns = 3;
	gKoStep = total / float(ns);
	float next = 0.5f * gKoStep;
	float acc = 0.f;
	for (int i = 0; i < hn; ++i) {
		const float arcL = s * sw2[i];
		while ((next <= acc + arcL) && (int(gKoSX.length()) < ns)) {
			const float a = a0[i] + ((s > 0.01f) ? ((next - acc) / s) : 0.f);
			gKoSX.insertLast(hx[i] + cos(a) * s);
			gKoSZ.insertLast(hz[i] + sin(a) * s);
			next += gKoStep;
		}
		acc += arcL;
		if (hn == 1)
			break;
		const int j = (i + 1) % hn;
		while ((next <= acc + el[i]) && (int(gKoSX.length()) < ns)) {
			const float t = (el[i] > 0.01f) ? ((next - acc) / el[i]) : 0.f;
			gKoSX.insertLast(hx[i] + (hx[j] - hx[i]) * t + nx[i] * s);
			gKoSZ.insertLast(hz[i] + (hz[j] - hz[i]) * t + nz[i] * s);
			next += gKoStep;
		}
		acc += el[i];
	}
	const float ex = gKoFoe.x - gKoMid.x, ez = gKoFoe.z - gKoMid.z;
	const float ne = sqrt(ex * ex + ez * ez);
	for (uint i = 0; i < gKoSX.length(); ++i) {
		const float vx = gKoSX[i] - gKoMid.x, vz = gKoSZ[i] - gKoMid.z;
		const float nv = sqrt(vx * vx + vz * vz);
		gKoSCos.insertLast((gKoFoeOk && (nv > 1.f) && (ne > 1.f)) ? (vx * ex + vz * ez) / (nv * ne) : 0.f);
	}
	gKoSWalk.resize(gKoSX.length());
	gKoSCover.resize(gKoSX.length());
	return gKoSX.length() > 0;
}

string KoFacing(float c)
{
	return (c > 0.5f) ? "front" : ((c > -0.5f) ? "flank" : "rear");
}

float KoFacingW(float c)
{
	float rear = ai.GetTunable("apex_wall_rear", TUNE_WALL_REAR);
	if (rear < 0.f) rear = 0.f;
	if (rear > 1.f) rear = 1.f;
	return rear + (1.f - rear) * (0.5f + 0.5f * c);
}

float KoClaimR(uint g)
{
	return 0.5f * gKoGLen[g] + gKoDStep;
}

void KoFinish()
{
	const uint n = gKoSX.length();
	// No walkable sample with a known foe means the ground test failed (their
	// reference in the sea, an island read), not a fortress.
	int nWalk = 0;
	for (uint i = 0; i < n; ++i)
		if (gKoSWalk[i])
			++nWalk;
	if (nWalk == 0) {
		for (uint i = 0; i < n; ++i) {
			gKoSWalk[i] = OnMap(AIFloat3(gKoSX[i], 0.f, gKoSZ[i]));
			if (gKoSWalk[i])
				++nWalk;
		}
	}
	// Previous gaps, for ids and the new-gap log.
	array<float> pmx = gKoGMX;
	array<float> pmz = gKoGMZ;
	array<float> plen = gKoGLen;
	array<int> pid = gKoGId;
	array<int> prevOwnIds;
	for (uint k = 0; k < gKoOwnG.length(); ++k)
		prevOwnIds.insertLast(gKoGId[uint(gKoOwnG[k])]);

	gKoDX = gKoSX;
	gKoDZ = gKoSZ;
	gKoDWalk = gKoSWalk;
	gKoDCover = gKoSCover;
	gKoDStep = gKoStep;
	gKoDNeed = gKoNeed;
	gKoDGap.resize(n);
	array<bool> open(n, false);
	int nCov = 0, nHeld = 0, nOpen = 0;
	for (uint i = 0; i < n; ++i) {
		gKoDGap[i] = -1;
		if (!gKoSWalk[i])
			continue;
		if (gKoSCover[i] > 0.f)
			++nCov;
		if (gKoSCover[i] >= gKoNeed)
			++nHeld;
		else {
			open[i] = true;
			++nOpen;
		}
	}
	gKoReachN = nWalk;
	gKoCov = (nWalk > 0) ? float(nCov) / float(nWalk) : 1.f;
	gKoHeld = (nWalk > 0) ? float(nHeld) / float(nWalk) : 1.f;
	gKoOpenFrac = (nWalk > 0) ? float(nOpen) / float(nWalk) : 0.f;

	gKoGX.resize(0); gKoGZ.resize(0); gKoGMX.resize(0); gKoGMZ.resize(0);
	gKoGLen.resize(0); gKoGOpen.resize(0); gKoGCos.resize(0); gKoGThreat.resize(0);
	gKoGT2.resize(0); gKoGEta.resize(0); gKoGScore.resize(0); gKoGOwner.resize(0); gKoGId.resize(0);
	gKoGRun.resize(0); gKoRunLen.resize(0);
	if (nOpen > 0) {
		// Runs on the closed loop, started just after a held or closed sample.
		int start = 0;
		if (nOpen < int(n)) {
			for (uint i = 0; i < n; ++i) {
				if (!open[i]) {
					start = int(i) + 1;
					break;
				}
			}
		}
		int runFrom = -1;
		for (int k = 0; k <= int(n); ++k) {
			const int i = (start + k) % int(n);
			const bool o = (k < int(n)) && open[uint(i)];
			if (o && (runFrom < 0))
				runFrom = k;
			if (!o && (runFrom >= 0)) {
				// A run longer than one light tower closes is cut into pieces
				// that each take one gun: each has its own site and owner.
				const int cnt = k - runFrom;
				const int run = int(gKoRunLen.length());
				gKoRunLen.insertLast(float(cnt) * gKoStep);
				int pieces = int(float(cnt) * gKoStep / (2.f * Brain::LightTowerRange()) + 0.999f);
				if (pieces < 1)
					pieces = 1;
				if (pieces > cnt)
					pieces = cnt;
				for (int pc = 0; pc < pieces; ++pc) {
					const int q0 = runFrom + (cnt * pc) / pieces;
					const int q1 = runFrom + (cnt * (pc + 1)) / pieces;
					const int g = int(gKoGX.length());
					float sumOpen = 0.f, bestW = -1.f;
					int bestI = -1;
					for (int q = q0; q < q1; ++q) {
						const uint si = uint((start + q) % int(n));
						gKoDGap[si] = g;
						float sh = 1.f - gKoSCover[si] / gKoNeed;
						if (sh < 0.f) sh = 0.f;
						sumOpen += sh;
						const float w = sh * KoFacingW(gKoSCos[si]);
						if (w > bestW) {
							bestW = w;
							bestI = int(si);
						}
					}
					const uint mi = uint((start + (q0 + q1) / 2) % int(n));
					gKoGX.insertLast(gKoSX[uint(bestI)]);
					gKoGZ.insertLast(gKoSZ[uint(bestI)]);
					gKoGMX.insertLast(gKoSX[mi]);
					gKoGMZ.insertLast(gKoSZ[mi]);
					gKoGLen.insertLast(float(q1 - q0) * gKoStep);
					gKoGOpen.insertLast(sumOpen / float(q1 - q0));
					gKoGCos.insertLast(gKoSCos[uint(bestI)]);
					gKoGThreat.insertLast(0.f);
					gKoGT2.insertLast(0.f);
					gKoGEta.insertLast(-1.f);
					gKoGScore.insertLast(0.f);
					gKoGOwner.insertLast(-1);
					gKoGId.insertLast(-1);
					gKoGRun.insertLast(run);
				}
				runFrom = -1;
			}
		}
	}
	const uint ng = gKoGX.length();
	// The threat that can use each gap: every armed enemy ground unit we
	// have seen goes to the gap it reaches first.
	// The sweep lists units group by group at the group's position; a group
	// walks as one, at its fastest unit's pace and its longest reach.
	DtFoeSweep();
	float foeM = 0.f, foeT2 = 0.f;
	array<AIFloat3> fgP;
	array<float> fgM;
	array<float> fgT2;
	array<float> fgSpd;
	array<float> fgRng;
	for (uint u = 0; u < gDtFoeP.length(); ++u) {
		const float um = gDtFoeM[u];
		foeM += um;
		if (gDtFoeT2[u])
			foeT2 += um;
		const uint last = fgP.length();
		if ((last == 0) || (fgP[last - 1].x != gDtFoeP[u].x) || (fgP[last - 1].z != gDtFoeP[u].z)) {
			fgP.insertLast(gDtFoeP[u]);
			fgM.insertLast(0.f);
			fgT2.insertLast(0.f);
			fgSpd.insertLast(0.f);
			fgRng.insertLast(0.f);
		}
		const uint fi = fgP.length() - 1;
		fgM[fi] += um;
		if (gDtFoeT2[u])
			fgT2[fi] += um;
		if (gDtFoeSpd[u] > fgSpd[fi])
			fgSpd[fi] = gDtFoeSpd[u];
		if (gDtFoeRng[u] > fgRng[fi])
			fgRng[fi] = gDtFoeRng[u];
	}
	for (uint f = 0; (ng > 0) && (f < fgP.length()); ++f) {
		int bg = -1;
		float be = 0.f;
		for (uint g = 0; g < ng; ++g) {
			float gd = fgP[f].distance2D(AIFloat3(gKoGX[g], 0.f, gKoGZ[g])) - fgRng[f];
			if (gd < 0.f)
				gd = 0.f;
			const float e = gd / fgSpd[f];
			if ((bg < 0) || (e < be)) {
				bg = int(g);
				be = e;
			}
		}
		gKoGThreat[uint(bg)] += fgM[f];
		gKoGT2[uint(bg)] += fgT2[f];
		if ((gKoGEta[uint(bg)] < 0.f) || (be < gKoGEta[uint(bg)]))
			gKoGEta[uint(bg)] = be;
	}
	float horiz = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	if (horiz <= 1.f)
		horiz = 300.f;
	for (uint g = 0; g < ng; ++g) {
		const float arrive = (gKoGEta[g] >= 0.f) ? horiz / (horiz + gKoGEta[g]) : 0.f;
		gKoGScore[g] = gKoGLen[g] * gKoGOpen[g]
				* (gKoGThreat[g] * arrive + gKoWave * KoFacingW(gKoGCos[g]));
	}
	// Ids carried over from the last pass.
	for (uint g = 0; g < ng; ++g) {
		for (uint q = 0; q < pmx.length(); ++q) {
			const float dx = gKoGMX[g] - pmx[q], dz = gKoGMZ[g] - pmz[q];
			const float r = 0.5f * plen[q] + gKoStep;
			if (dx * dx + dz * dz <= r * r) {
				gKoGId[g] = pid[q];
				break;
			}
		}
	}
	// OWNERSHIP. A live claim on the team board wins; otherwise the nearest
	// of our AIs, whoever's base the gap fronts -- a human ally's included.
	array<int> seatT;
	array<float> seatX;
	array<float> seatZ;
	seatT.insertLast(ai.teamId);
	seatX.insertLast(gPfRimOk ? gPfMid.x : Builder::gHomePos.x);
	seatZ.insertLast(gPfRimOk ? gPfMid.z : Builder::gHomePos.z);
	if (gShieldMates is null)
		@gShieldMates = ai.GetTeamIds();
	for (uint m = 0; (gShieldMates !is null) && (m < gShieldMates.length()); ++m) {
		const int t = int(gShieldMates[m]);
		if (t == ai.teamId)
			continue;
		const float at = ai.ReadTeamValue(t, TV_KO_AT, -1.f);
		if ((at < 0.f) || (float(ai.frame) - at > 60.f * float(SECOND)))
			continue;
		const float mx = ai.ReadTeamValue(t, TV_PF_MX, -1.f);
		const float mz = ai.ReadTeamValue(t, TV_PF_MZ, -1.f);
		if ((mx < 0.f) || (mz < 0.f))
			continue;
		seatT.insertLast(t);
		seatX.insertLast(mx);
		seatZ.insertLast(mz);
	}
	array<float> clX;
	array<float> clZ;
	array<int> clT;
	for (int c = 0; c < KO_CLAIMS; ++c) {
		const int b = KO_BOARD + 4 * c;
		if (ai.GetTeamBoard(b + 3, -1.f) <= float(ai.frame))
			continue;
		clX.insertLast(ai.GetTeamBoard(b, -1.f));
		clZ.insertLast(ai.GetTeamBoard(b + 1, -1.f));
		clT.insertLast(int(ai.GetTeamBoard(b + 2, 0.f)) - 1);
	}
	for (uint g = 0; g < ng; ++g) {
		int owner = -1;
		const float cr = 0.5f * gKoGLen[g] + gKoStep;
		for (uint c = 0; (c < clX.length()) && (owner < 0); ++c) {
			const float dx = clX[c] - gKoGMX[g];
			const float dz = clZ[c] - gKoGMZ[g];
			if (dx * dx + dz * dz <= cr * cr)
				owner = clT[c];
		}
		if (owner < 0) {
			float bd = -1.f;
			for (uint k = 0; k < seatT.length(); ++k) {
				const float dx = seatX[k] - gKoGX[g], dz = seatZ[k] - gKoGZ[g];
				const float dd = dx * dx + dz * dz;
				if ((bd < 0.f) || (dd < bd)) {
					bd = dd;
					owner = seatT[k];
				}
			}
		}
		gKoGOwner[g] = owner;
	}
	// Our gaps, best first.
	gKoOwnG.resize(0);
	gKoOwnShape.resize(0);
	gKoOwnRing.resize(0);
	float bestScore = 0.f;
	for (uint g = 0; g < ng; ++g) {
		if (gKoGOwner[g] != ai.teamId)
			continue;
		uint at = gKoOwnG.length();
		for (uint k = 0; k < gKoOwnG.length(); ++k) {
			if (gKoGScore[g] > gKoGScore[uint(gKoOwnG[k])]) {
				at = k;
				break;
			}
		}
		gKoOwnG.insertAt(at, int(g));
		if (gKoGScore[g] > bestScore)
			bestScore = gKoGScore[g];
	}
	bool newOwned = false;
	for (uint g = 0; g < ng; ++g) {
		const bool fresh = (gKoGId[g] < 0);
		if (fresh)
			gKoGId[g] = gKoNextId++;
		if (gKoGOwner[g] != ai.teamId)
			continue;
		if (prevOwnIds.find(gKoGId[g]) < 0)
			newOwned = true;
		if (fresh && (gKoGCos[g] > -0.5f)) {
			++gKoNewGapN;
			AiLog(Factory::T() + "apex: keepout-gap t=" + ai.teamId + " id=" + gKoGId[g]
				+ " at=" + int(gKoGX[g]) + "," + int(gKoGZ[g]) + " len=" + int(gKoGLen[g]) + " run=" + int(gKoRunLen[uint(gKoGRun[g])])
				+ " open=" + int(gKoGOpen[g] * 100.f) + " facing=" + KoFacing(gKoGCos[g])
				+ " threatM=" + int(gKoGThreat[g]) + " t2=" + int(gKoGT2[g])
				+ " eta=" + int(gKoGEta[g]) + " owner=" + gKoGOwner[g]);
		}
	}
	if (int(gKoIdSlot.length()) < gKoNextId) {
		const uint was = gKoIdSlot.length();
		gKoIdSlot.resize(uint(gKoNextId));
		for (uint i = was; i < gKoIdSlot.length(); ++i)
			gKoIdSlot[i] = -1;
	}
	for (uint k = 0; k < prevOwnIds.length(); ++k)
		if ((prevOwnIds[k] >= 0) && (prevOwnIds[k] < int(gKoIdSlot.length())))
			gKoIdSlot[uint(prevOwnIds[k])] = -1;
	for (uint k = 0; k < gKoOwnG.length(); ++k) {
		const uint g = uint(gKoOwnG[k]);
		gKoIdSlot[uint(gKoGId[g])] = int(k);
		gKoOwnShape.insertLast((bestScore > 0.f) ? (gKoGScore[g] / bestScore) : 1.f);
		gKoOwnRing.insertLast(RingBPAt(AIFloat3(gKoGX[g], 0.f, gKoGZ[g])));
	}
	gKoElAt.resize(gKoOwnG.length());
	gKoElBest.resize(gKoOwnG.length());
	gKoElBestT2.resize(gKoOwnG.length());
	for (uint k = 0; k < gKoElAt.length(); ++k)
		gKoElAt[k] = -1;
	// A gap this seat newly owns re-ranks the defence sites now, not at the
	// next minute's refill.
	if (newOwned) {
		for (uint d = 0; d < gDsAt.length(); ++d)
			if (gDsAt[d] > 1)
				gDsAt[d] = 1;
	}
	gKoOk = true;
	gKoDoneAt = ai.frame;
	ai.PublishTeamValue(TV_KO_AT, float(ai.frame));
	++gKoPasses;
	gKoCovSum += gKoCov;
	gKoHeldSum += gKoHeld;
	gKoOpenSum += gKoOpenFrac;
	int wg = -1;
	for (uint g = 0; g < ng; ++g) {
		if ((wg < 0) || (gKoGScore[g] > gKoGScore[uint(wg)]))
			wg = int(g);
		if (gKoRunLen[uint(gKoGRun[g])] > gKoWorstLen)
			gKoWorstLen = gKoRunLen[uint(gKoGRun[g])];
	}
	if (ai.frame >= gKoLogAt) {
		gKoLogAt = ai.frame + 60 * SECOND;
		float ownLen = 0.f;
		for (uint k = 0; k < gKoOwnG.length(); ++k)
			ownLen += gKoGLen[uint(gKoOwnG[k])];
		string owners = "";
		for (uint k = 0; k < seatT.length(); ++k) {
			int cnt = 0;
			for (uint g = 0; g < ng; ++g)
				if (gKoGOwner[g] == seatT[k])
					++cnt;
			owners += ((k > 0) ? "," : "") + seatT[k] + ":" + cnt;
		}
		string worst = " worst=-";
		if (wg >= 0) {
			const uint w = uint(wg);
			worst = " worst=" + int(gKoGX[w]) + "," + int(gKoGZ[w]) + " len=" + int(gKoRunLen[uint(gKoGRun[w])])
				+ " open=" + int(gKoGOpen[w] * 100.f) + " facing=" + KoFacing(gKoGCos[w])
				+ " threatM=" + int(gKoGThreat[w]) + " t2=" + int(gKoGT2[w])
				+ " eta=" + int(gKoGEta[w]) + " owner=" + gKoGOwner[w];
		}
		AiLog(Factory::T() + "apex: keepout t=" + ai.teamId + " scope=ally cov=" + int(gKoCov * 100.f)
			+ " held=" + int(gKoHeld * 100.f) + " gaps=" + gKoRunLen.length() + " pieces=" + ng + worst
			+ " need=" + int(gKoNeed) + " foeM=" + int(foeM) + " foeT2=" + int(foeT2)
			+ " n=" + n + " reach=" + nWalk + " step=" + int(gKoStep) + " standoff=" + int(gKoStandoff)
			+ " hull=" + gKoHullN + " perim=" + int(gKoPerim) + " pts=" + gKoOwnPts + "+" + gKoAllyPts
			+ " mid=" + int(gKoMid.x) + "," + int(gKoMid.z) + " own=" + gKoOwnG.length() + "/" + int(ownLen)
			+ " owners=" + owners);
	}
	if (ai.frame >= gKoSumAt) {
		gKoSumAt = ai.frame + 60 * SECOND;
		const float np = float(gKoPasses);
		AiLog(Factory::T() + "apex: keepout-sum t=" + ai.teamId + " passes=" + gKoPasses
			+ " cov=" + int(100.f * gKoCovSum / np) + " held=" + int(100.f * gKoHeldSum / np)
			+ " open=" + int(100.f * gKoOpenSum / np) + " worstLen=" + int(gKoWorstLen)
			+ " newGaps=" + gKoNewGapN + " leakN=" + gKoLeakN + " leakGap=" + gKoLeakGap
			+ " leakUncov=" + gKoLeakUncov + " leakOwn=" + gKoLeakOwn + " leakM=" + int(gKoLeakM)
			+ " leakGapM=" + int(gKoLeakGapM) + " best=" + gKoWonN + " late=" + gKoLateN
			+ " t1refused=" + gKoT1N + " sited=" + gKoPickN + " claims=" + gKoClaimN);
	}
}

// One step of the census per update; a pass every ten seconds at most.
void KeepOutUpdate()
{
	if (!Builder::gHomeSet)
		return;
	const double _t = Perf::T0();
	if (gKoStage == KO_IDLE) {
		if (ai.frame - gKoPassAt < 10 * SECOND)
			return;
		gKoPassAt = ai.frame;
		gKoStage = KO_GATHER;
		KoGather();
		Perf::Add("prot.keepout", _t);
		return;
	}
	if (gKoStage == KO_GATHER) {
		PfRebuild();
		gKoFoeOk = FoeRef(gKoFoe);
		// Guns stand where an enemy could shoot the rim from; half a light
		// tower's reach between samples, so no stretch a gun's width long
		// falls between two of them.
		const float lightR = Brain::LightTowerRange();
		gKoStandoff = lightR * ai.GetTunable("apex_wall_standoff", TUNE_WALL_STANDOFF);
		if (Military::FoeReach() > gKoStandoff)
			gKoStandoff = Military::FoeReach();
		gKoSpacing = 0.5f * lightR;
		gKoWave = TeamWave(ai.ReadTeamValue(ai.teamId, TV_PF_WAVE, 0.f));
		gKoNeed = (gKoWave > LightTowerCostM()) ? gKoWave : LightTowerCostM();
		if (gKoNeed < 1.f)
			gKoNeed = 1.f;
		gKoCursor = 0;
		gKoStage = KoHullSamples() ? KO_SAMPLE : KO_IDLE;
		Perf::Add("prot.keepout", _t);
		return;
	}
	if (gKoStage == KO_SAMPLE) {
		PfRebuild();
		const int end = (gKoCursor + KO_PER_CALL < int(gKoSX.length()))
				? (gKoCursor + KO_PER_CALL) : int(gKoSX.length());
		for (int i = gKoCursor; i < end; ++i) {
			const AIFloat3 p(gKoSX[i], 0.f, gKoSZ[i]);
			const bool on = OnMap(p);
			gKoSWalk[i] = on && (!gKoFoeOk || ai.GroundConnected(p, gKoFoe));
			gKoSCover[i] = on ? PfCoverPoint(p, p, -1.f, 0.f) : 0.f;
		}
		gKoCursor = end;
		if (gKoCursor >= int(gKoSX.length()))
			gKoStage = KO_FINISH;
		Perf::Add("prot.keepout", _t);
		return;
	}
	KoFinish();
	gKoStage = KO_IDLE;
	Perf::Add("prot.keepout", _t);
}

// Our open gaps' sites, for the defence fill; ids parallel, -1 never.
void KoFillSites(array<AIFloat3>& sites, array<int>& ids)
{
	if (!gKoOk)
		return;
	for (uint k = 0; k < gKoOwnG.length(); ++k) {
		const uint g = uint(gKoOwnG[k]);
		sites.insertLast(AIFloat3(gKoGX[g], 0.f, gKoGZ[g]));
		ids.insertLast(gKoGId[g]);
	}
}

int KoOwnedOpen()
{
	return gKoOk ? int(gKoOwnG.length()) : 0;
}

// The gap behind a fill's site, by id: its index among ours, -1 closed.
int KoOwnIndex(int id)
{
	if ((id < 0) || (id >= int(gKoIdSlot.length())))
		return -1;
	return gKoIdSlot[uint(id)];
}

float KoShape(int id)
{
	const int k = KoOwnIndex(id);
	return (k >= 0) ? gKoOwnShape[uint(k)] : 0.f;
}

float KoThreatM(int id)
{
	const int k = KoOwnIndex(id);
	return (k >= 0) ? gKoGThreat[uint(gKoOwnG[uint(k)])] : 0.f;
}

// A gun that cannot stand before the threat at this gap arrives is the wrong
// gun while one that can exists; against their T2, a basic tower is too.
bool KoWrongGun(int id, int d, float handBP, float walkS, const array<int>@ builds)
{
	const int k = KoOwnIndex(id);
	if (k < 0)
		return true;
	const uint g = uint(gKoOwnG[uint(k)]);
	const float eta = gKoGEta[g];
	if (eta < 0.f)
		return false;
	const float ring = gKoOwnRing[uint(k)];
	if (gKoElAt[uint(k)] != gKoElec) {
		gKoElAt[uint(k)] = gKoElec;
		float best = -1.f, best2 = -1.f;
		for (uint i = 0; (builds !is null) && (i < builds.length()); ++i) {
			const int b = builds[i];
			if (!Catalog::gAvailable[b] || Catalog::gMobile[b] || (ProtClassOf(b) != PROT_DEF)
				|| (Catalog::gSurfT[b] <= 0.01f))
				continue;
			const float sb = walkS + Catalog::BuildSecondsAt(b, handBP + ring);
			if ((best < 0.f) || (sb < best))
				best = sb;
			if (!T1Tower(b) && ((best2 < 0.f) || (sb < best2)))
				best2 = sb;
		}
		gKoElBest[uint(k)] = best;
		gKoElBestT2[uint(k)] = best2;
	}
	float limit = eta;
	if (gKoElBest[uint(k)] > limit)
		limit = gKoElBest[uint(k)];
	const float stand = walkS + Catalog::BuildSecondsAt(d, handBP + ring);
	if (stand > limit + 1.f) {
		++gKoLateN;
		return true;
	}
	if ((gKoGT2[g] > 0.f) && T1Tower(d) && (gKoElBestT2[uint(k)] >= 0.f)
		&& (gKoElBestT2[uint(k)] <= limit + 1.f)) {
		++gKoT1N;
		return true;
	}
	return false;
}

// A ground gun about to be sited: inside one of our gaps, the gap is claimed
// on the team board so another of our AIs does not close it too.
void KoNoteSited(const AIFloat3& in s)
{
	if (!gKoOk)
		return;
	int bk = -1;
	float bd = 0.f;
	for (uint k = 0; k < gKoOwnG.length(); ++k) {
		const uint g = uint(gKoOwnG[k]);
		const float r = 0.5f * gKoGLen[g] + gKoStandoff + gKoDStep;
		const float dd = s.distance2D(AIFloat3(gKoGX[g], 0.f, gKoGZ[g]));
		if ((dd <= r) && ((bk < 0) || (dd < bd))) {
			bk = int(k);
			bd = dd;
		}
	}
	if (bk < 0)
		return;
	++gKoPickN;
	const uint g = uint(gKoOwnG[uint(bk)]);
	int own = -1, spare = -1, oldest = -1;
	float soonest = -1.f;
	for (int c = 0; (c < KO_CLAIMS) && (own < 0); ++c) {
		const int b = KO_BOARD + 4 * c;
		const float until = ai.GetTeamBoard(b + 3, -1.f);
		if (until <= float(ai.frame)) {
			if (spare < 0)
				spare = c;
			continue;
		}
		const float cx = ai.GetTeamBoard(b, -1.f) - gKoGMX[g];
		const float cz = ai.GetTeamBoard(b + 1, -1.f) - gKoGMZ[g];
		if ((int(ai.GetTeamBoard(b + 2, 0.f)) - 1 == ai.teamId)
			&& (cx * cx + cz * cz <= KoClaimR(g) * KoClaimR(g)))
			own = c;
		else if ((soonest < 0.f) || (until < soonest)) {
			soonest = until;
			oldest = c;
		}
	}
	const int slot = (own >= 0) ? own : ((spare >= 0) ? spare : oldest);
	if (slot < 0)
		return;
	const int b = KO_BOARD + 4 * slot;
	ai.SetTeamBoard(b, gKoGMX[g]);
	ai.SetTeamBoard(b + 1, gKoGMZ[g]);
	ai.SetTeamBoard(b + 2, float(ai.teamId + 1));
	ai.SetTeamBoard(b + 3, float(ai.frame + DS_HOLD));
	++gKoClaimN;
}

// A leak: which ring sample did it come past, and was that sample open?
void KoNoteLeak(const AIFloat3& in at, float m)
{
	if (!gKoOk || (gKoDX.length() == 0))
		return;
	int bi = -1;
	float bd = 0.f;
	for (uint i = 0; i < gKoDX.length(); ++i) {
		if (!gKoDWalk[i])
			continue;
		const float dx = gKoDX[i] - at.x, dz = gKoDZ[i] - at.z;
		const float dd = dx * dx + dz * dz;
		if ((bi < 0) || (dd < bd)) {
			bi = int(i);
			bd = dd;
		}
	}
	if (bi < 0)
		return;
	const uint i = uint(bi);
	const int g = gKoDGap[i];
	++gKoLeakN;
	gKoLeakM += m;
	if (g >= 0) {
		++gKoLeakGap;
		gKoLeakGapM += m;
		if (gKoGOwner[uint(g)] == ai.teamId)
			++gKoLeakOwn;
	}
	if (gKoDCover[i] <= 0.f)
		++gKoLeakUncov;
	AiLog(Factory::T() + "apex: keepout-leak t=" + ai.teamId + " at=" + int(at.x) + "," + int(at.z)
		+ " m=" + int(m) + " ring=" + int(gKoDX[i]) + "," + int(gKoDZ[i]) + " ringD=" + int(sqrt(bd))
		+ " cover=" + int(gKoDCover[i]) + " need=" + int(gKoDNeed)
		+ " gap=" + ((g >= 0) ? ("" + gKoGId[uint(g)]) : "-")
		+ " len=" + ((g >= 0) ? int(gKoRunLen[uint(gKoGRun[uint(g)])]) : 0)
		+ " owner=" + ((g >= 0) ? gKoGOwner[uint(g)] : -1)
		+ " ageS=" + ((ai.frame - gKoDoneAt) / SECOND));
}

}  // namespace Market
