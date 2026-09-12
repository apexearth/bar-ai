namespace Military {

//------------------------------------------------------------------------------
// GUARD POSTS: a unit standing by a building is cover for it, the same as a
// turret (apexearth: "a unit protecting a building also should be counting as
// cover. We should distribute our units well enough to ensure proper coverage
// of our buildings for defense").
//
// Every protect-field period the DEFEND pools' members are posted over the
// field's assets, greedily: the asset with the most uncovered worth takes the
// nearest free unit. Metal covers metal: an asset is covered when the guard
// metal that can reach it before a raider kills it matches its own worth, and
// a guard's cover fades with distance inside that reach, so the second unit
// goes to the far side of a cluster rather than on top of the first. Turrets
// count as cover the same way. The DLL walks each posted unit to its post
// while its pool has nothing to fight (CDefendTask::FallbackPosts); the pool
// still fights as one when a target is elected.
//------------------------------------------------------------------------------

int   gPostAt = -999999;
int   gPostLogAt = -999999;
float gPostUncovered = 0.f;    // uncovered worth after posting, metal
float gPostTotal = 0.f;        // worth of every asset, metal
int   gPostUnits = 0;
// The last posting: where each guard stands, its metal and its reach, so a
// spot can be priced with the units that cover it (units are cover, the
// same as turrets -- see UnitCoverAt).
array<AIFloat3> gPostUPos;
// The same posts as flat floats: CoverWith asks UnitCoverAt for every candidate
// site of every defence fill and for every asset of every posting pass, and each
// ask was a distance2D method call per posted guard.
array<float> gPostUX;
array<float> gPostUZ;
array<float> gPostUM;
array<float> gPostUReach;

// Guard metal covering `pos`: each posted unit counts fully at its post and
// fades to nothing at its reach, the falloff the posting itself uses.
float UnitCoverAt(const AIFloat3& in pos)
{
	float m = 0.f;
	for (uint i = 0; i < gPostUX.length(); ++i) {
		const float r = gPostUReach[i];
		if (r <= 1.f)
			continue;
		const float dx = gPostUX[i] - pos.x;
		const float dz = gPostUZ[i] - pos.z;
		const float d2 = dx * dx + dz * dz;
		if (d2 < r * r)
			m += gPostUM[i] * (1.f - sqrt(d2) / r);
	}
	return m;
}
int   gPostAssets = 0;
// What is still uncovered after every unit we have is posted, and the light
// units it would take to cover it (virtual posting, below): the lab's demand
// for light units is this, not a share of income (apexearth: "we still need a
// lot more light units to protect our base... a unit protecting a building
// also should be counting as cover").
int   gPostNeedN = 0;
float gPostNeedM = 0.f;
int   gPostNeedDef = -1;
// The same two figures with radar warning at every asset: what a radar
// buys is the light units it makes unnecessary (apexearth: "we need vision
// and speed in order to properly defend ourselves"; "bump up the importance
// of radar/vision -- it's cheap and we should make it").
float gPostUncoveredEyes = 0.f;
float gPostNeedEyesM = 0.f;
float gPostWarnS = 0.f;
// What must be beaten AT each asset: the wave that arrives there, and ONLY
// that. Floored at the asset's own worth as well, cover demand summed to the
// whole base's worth -- several times our army, so never met, and with no
// direction in it. ThreatM carries the home->enemy gradient, so a forward
// asset asks for more cover than one behind us.
// Threat is an engine sweep per asset; refreshed on a slower clock.
//
// INDEX-PARALLEL TO Market::gPfPos, AND THAT FIELD REORDERS. A length check is
// not enough: one building finishing and another dying inside the same ten
// seconds leaves the length identical and every later row shifted, so a threat
// stayed attached to the wrong asset. Market::gPfStamp changes exactly when the
// SET of assets does, so it is stored with the sweep and any reader that indexes
// gPfPos with these rows checks it first.
array<float> gPostReq;
int gPostReqAt = -999999;
int gPostReqStamp = -1;
// The asset each value is about, and the ground it was measured over.
array<int>   gPostReqKey;
array<float> gPostReqX;
array<float> gPostReqZ;
// What the last posting left behind, so the cover-need estimate can run on the
// tick the posting pass skips rather than piling onto the same sim frame.
array<float> gPostCov;
array<float> gPostCovEyes;
array<bool>  gPostSeen;
int gPostNeedAt = -999999;

// STANDING COVER PER ASSET, which is a reading of the turrets and of nothing
// else: it moves when a tower is built or dies, not every two seconds. Held
// against both revisions that decide it -- gPfStamp for the row->asset mapping,
// gPfTwRev for the towers themselves -- plus the point each entry was measured
// at, because PfCommit lets a value move under an unchanged key.
array<float> gPostCovCache;
array<float> gPostCovAtX;
array<float> gPostCovAtZ;
int gPostCovStamp = -1;
int gPostCovTwRev = -1;

// Light-unit metal that radar warning would save.
float EyesSavedM()
{
	const float d = gPostNeedM - gPostNeedEyesM;
	return (d > 0.f) ? d : 0.f;
}

// Fraction of the base's worth no unit or turret covers.
float CoverShort()
{
	return (gPostTotal > 1.f) ? (gPostUncovered / gPostTotal) : 0.f;
}

// Metal of light units the base still needs for coverage.
float CoverNeedM()
{
	return gPostNeedM;
}

// The light unit coverage is bought in: of what our standing factories make,
// the most ground covered per metal -- speed over cost.
// The walk is a function of WHICH defs we own and the fixed catalog, so it
// rides gOwnSetStamp; a miss is never latched.
int   gCudDef = -1;
int   gCudStamp = -1;
int CoverUnitDef()
{
	if ((gCudStamp == Market::gOwnSetStamp) && (gCudDef > 0))
		return gCudDef;
	int best = -1;
	float bestV = 0.f;
	for (uint f = 1; f < Market::gOwnCount.length(); ++f) {
		const int fd = int(f);
		if ((Market::gOwnCount[f] <= 0) || Catalog::gMobile[fd] || (Catalog::gBuildsList[fd].length() == 0))
			continue;
		const array<int>@ pb = Catalog::gBuildsList[fd];
		for (uint q = 0; q < pb.length(); ++q) {
			const int d = pb[q];
			if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gFlyer[d]
				|| Catalog::gBuilder[d] || !Market::LineCombat(d) || (Catalog::gCostM[d] <= 1.f))
				continue;
			const float v = Catalog::gSpeed[d] / Catalog::gCostM[d];
			if (v > bestV) {
				bestV = v;
				best = d;
			}
		}
	}
	gCudDef = best;
	gCudStamp = (best > 0) ? Market::gOwnSetStamp : -1;
	return best;
}

// Seconds of warning a radar gives a guard over its own eyes: the best mast
// our builders can place, less the unit's sight, at the fastest foe's speed.
// The mast walk rides the same owned-set token; a zero is never latched.
float gEwRadarR = 0.f;
int   gEwStamp = -1;
float EyesWarningS(int guardDef)
{
	float radarR = gEwRadarR;
	if ((gEwStamp != Market::gOwnSetStamp) || (radarR <= 0.f)) {
		radarR = 0.f;
		for (uint b = 1; b < Market::gOwnCount.length(); ++b) {
			const int bd = int(b);
			if ((Market::gOwnCount[b] <= 0) || !Catalog::gMobile[bd] || !Catalog::gBuilder[bd])
				continue;
			const array<int>@ bl = Catalog::gBuildsList[bd];
			for (uint q = 0; q < bl.length(); ++q) {
				const int o = bl[q];
				if (Catalog::gAvailable[o] && !Catalog::gMobile[o] && (Catalog::gRadarR[o] > radarR))
					radarR = Catalog::gRadarR[o];
			}
		}
		gEwRadarR = radarR;
		gEwStamp = (radarR > 0.f) ? Market::gOwnSetStamp : -1;
	}
	const float los = (guardDef > 0) ? Catalog::gLosR[guardDef] : 450.f;
	const float gap = radarR - ((los > 1.f) ? los : 450.f);
	if (gap <= 0.f)
		return 0.f;
	const float fs = Market::FoeSpeedCap();
	return gap / ((fs > 1.f) ? fs : 100.f);
}

// How long one of our economy buildings -- the mexes and generators the raids
// come for -- lives under the fastest enemy's gun. Nothing in it varies per
// guard, so it is taken once a posting pass rather than inside PostReach:
// two walks of every def in the game, and PostReach is asked twice per guard.
float gPostLifeS = 0.f;   // <= 0: we own no economy building yet
// Two def-table walks a posting pass, for two numbers that move on their own
// events: the mean hit points only when a unit is gained or lost, and the
// raider's damage rate only when a faster foe is first seen (FoeSpeedCap
// latches on its own). Both walks were re-run every two seconds regardless.
float gPostLifeHp = 0.f;
int   gPostLifeOwn = -1;
float gPostRaidDps = 0.f;
float gPostRaidFast = -1.f;

void RefreshPostLife()
{
	if (gPostLifeOwn != Market::gOwnStamp) {
		gPostLifeOwn = Market::gOwnStamp;
		float hp = 0.f, n = 0.f;
		for (uint k = 1; k < Market::gOwnCount.length(); ++k) {
			const int kd = int(k);
			if ((Market::gOwnCount[k] <= 0) || Catalog::gMobile[kd] || (Catalog::gHealth[kd] <= 1.f))
				continue;
			if ((Catalog::gExtractsM[kd] <= 0.f) && (Catalog::gMakeE[kd] <= 1.f))
				continue;
			hp += float(Market::gOwnCount[k]) * Catalog::gHealth[kd];
			n += float(Market::gOwnCount[k]);
		}
		gPostLifeHp = (n < 1.f) ? 0.f : (hp / n);
	}
	if (gPostLifeHp <= 0.f) {
		gPostLifeS = 0.f;
		return;
	}
	const float fastest = Market::FoeSpeedCap() - 0.1f;
	if (gPostRaidFast != fastest) {
		gPostRaidFast = fastest;
		float dps = 0.f;
		// The two SELECTIVE tests first. LineCombat is six array reads behind a
		// call and it was answering for every def in the game before speed and
		// dps -- which between them reject nearly all of them -- had been looked
		// at. Same set accepted, same maximum: the running max only grows, so
		// skipping a def whose dps cannot beat it is the old `> dps` guard moved
		// earlier.
		for (int k = 1; k <= Catalog::gDefCount; ++k) {
			if ((Catalog::gSpeed[k] < fastest) || (Catalog::gDps[k] <= dps))
				continue;
			if (!Catalog::gAvailable[k] || Catalog::gFlyer[k] || !Market::LineCombat(k))
				continue;
			dps = Catalog::gDps[k];
		}
		gPostRaidDps = (dps < 1.f) ? 20.f : dps;
	}
	gPostLifeS = gPostLifeHp / gPostRaidDps;
}

// What a unit reaches before a raider kills one of those buildings: its speed
// times their life, plus any warning seconds it gets.
float PostReach(int d, float warnS = 0.f)
{
	if (gPostLifeS <= 0.f)
		return 400.f;
	const float r = Catalog::gSpeed[d] * (gPostLifeS + warnS);
	return (r < 150.f) ? 150.f : ((r > 1500.f) ? 1500.f : r);
}

// Where the k-th guard of an asset stands: forward of it toward `foe` by up
// to half its gun range, and beside the previous guards in alternation, so
// the guards of one asset are a line facing the enemy rather than a pile.
AIFloat3 WallPost(const AIFloat3& in at, const AIFloat3& in foe, float range, int k, float gap, float fwdMax)
{
	float dx = foe.x - at.x, dz = foe.z - at.z;
	const float len = sqrt(dx * dx + dz * dz);
	if (len < 1.f) {
		dx = 0.f;
		dz = -1.f;
	} else {
		dx /= len;
		dz /= len;
	}
	float fwd = 0.5f * range;
	if (fwd > fwdMax)
		fwd = fwdMax;
	const float side = float((k + 1) / 2) * gap * ((k % 2 == 1) ? 1.f : -1.f) * ((k == 0) ? 0.f : 1.f);
	AIFloat3 p = at;
	p.x += dx * fwd - dz * side;
	p.z += dz * fwd + dx * side;
	const float w = float(AiTerrainWidth()), h = float(AiTerrainHeight());
	if (p.x < 32.f) p.x = 32.f;
	if (p.z < 32.f) p.z = 32.f;
	if (p.x > w - 32.f) p.x = w - 32.f;
	if (p.z > h - 32.f) p.z = h - 32.f;
	return p;
}

// Worth left exposed at asset i: its worth times the share of the wave
// there that no guard reaches.
float Exposed(uint i, float cov)
{
	const float req = gPostReq[i];
	if (req <= 1.f)
		return 0.f;
	const float sh = (req - cov) / req;
	return (sh > 0.f) ? Market::gPfWorth[i] * sh : 0.f;
}

// Mean position of a set of points on the home->enemy axis. Telemetry only.
float MeanForward(const array<AIFloat3>@ ps)
{
	if ((ps is null) || (ps.length() == 0))
		return 0.f;
	float s = 0.f;
	for (uint i = 0; i < ps.length(); ++i)
		s += ForwardFraction(ps[i]);
	return s / float(ps.length());
}

// The same axis, weighted by each asset's cover requirement: where the DEMAND
// for guards sits, as against where the assets sit. Above the plain mean means
// the front of the base is asking for the guards. Telemetry only.
float ReqForward()
{
	if ((gPostReq.length() != Market::gPfPos.length())
		|| (gPostReqStamp != Market::gPfStamp))
		return 0.f;
	float s = 0.f, w = 0.f;
	for (uint i = 0; i < gPostReq.length(); ++i) {
		s += gPostReq[i] * ForwardFraction(Market::gPfPos[i]);
		w += gPostReq[i];
	}
	return (w > 0.f) ? (s / w) : 0.f;
}

// Light units it takes to cover what `cov` leaves uncovered; cov is
// consumed. Assets with radar warning (`seen`) take the wider reach.
int VirtualPost(array<float>@ cov, array<bool>@ seen,
		float vr0, float vrE, float vm, float left)
{
	const uint n = cov.length();
	int count = 0;
	// The same flat copies UpdateGuardPosts takes, for the same reason: this
	// walks n up to 120 times a pass and the loop body was two AIFloat3 array
	// reads, a distance2D call and a call to Exposed per asset.
	array<float> px(n);
	array<float> pz(n);
	array<float> wm(n);
	array<float> rqv(n);
	array<float> expo(n);
	// Applying a placement, re-totalling what is left and finding the next
	// worst asset all read the same cov[i]: one walk of n, not three.
	int bi = -1;
	float bw = 0.f;
	for (uint i = 0; i < n; ++i) {
		const AIFloat3 ap = Market::gPfPos[i];
		px[i] = ap.x;
		pz[i] = ap.z;
		wm[i] = Market::gPfWorth[i];
		const float rq2 = gPostReq[i];
		rqv[i] = rq2;
		float u = 0.f;
		if (rq2 > 1.f) {
			const float sh = (rq2 - cov[i]) / rq2;
			if (sh > 0.f)
				u = wm[i] * sh;
		}
		expo[i] = u;
		if (u > bw) {
			bw = u;
			bi = int(i);
		}
	}
	const float vrMax = (vrE > vr0) ? vrE : vr0;
	const float vrMax2 = vrMax * vrMax;
	while ((left > gPostTotal * 0.05f) && (count < 60)) {
		if (bi < 0)
			break;
		const uint at = uint(bi);
		const float ax = px[at];
		const float az = pz[at];
		bi = -1;
		bw = 0.f;
		left = 0.f;
		for (uint i = 0; i < n; ++i) {
			const float ddx = px[i] - ax;
			const float ddz = pz[i] - az;
			const float d2 = ddx * ddx + ddz * ddz;
			if (d2 < vrMax2) {
				const float dd = sqrt(d2);
				const float vr = seen[i] ? vrE : vr0;
				if (dd < vr)
					cov[i] += vm * (1.f - dd / vr);
				const float rq2 = rqv[i];
				float u = 0.f;
				if (rq2 > 1.f) {
					const float sh = (rq2 - cov[i]) / rq2;
					if (sh > 0.f)
						u = wm[i] * sh;
				}
				expo[i] = u;
			}
			const float e = expo[i];
			left += e;
			if (e > bw) {
				bw = e;
				bi = int(i);
			}
		}
		++count;
	}
	return count;
}

// Virtual posting: keep placing the light unit at the worst-covered asset
// until the base is covered, and count what that took -- twice, as things
// stand and with radar warning everywhere, so the difference prices a radar.
// It reads the snapshot the last posting left, off that posting's own tick
// and on gPostReq's slower clock: light-unit demand and the radar price are
// what consume it, and neither moves inside two seconds.
void UpdateCoverNeed()
{
	const uint n = gPostCov.length();
	if ((n == 0) || (gPostCovEyes.length() != n) || (gPostSeen.length() != n))
		return;
	// The field is rebuilt from the auction too; a snapshot that no longer
	// indexes the same assets is not one to post over -- and a length that
	// happens to match is not the same set of assets.
	if ((Market::gPfPos.length() != n) || (gPostReq.length() != n)
		|| (gPostReqStamp != Market::gPfStamp))
		return;
	if ((ai.frame - gPostNeedAt) < 10 * SECOND)
		return;
	gPostNeedAt = ai.frame;
	gPostNeedN = 0;
	gPostNeedM = 0.f;
	gPostNeedEyesM = 0.f;
	if (gPostNeedDef <= 0)
		return;
	const double _tN = Perf::T0();
	const float vr0 = PostReach(gPostNeedDef);
	const float vrE = PostReach(gPostNeedDef, gPostWarnS);
	const float vm = Catalog::gCostM[gPostNeedDef];
	gPostNeedN = VirtualPost(@gPostCov, @gPostSeen, vr0, vrE, vm, gPostUncovered);
	gPostNeedM = float(gPostNeedN) * vm;
	array<bool> all(n, true);
	gPostNeedEyesM = float(VirtualPost(@gPostCovEyes, @all, vr0, vrE, vm, gPostUncoveredEyes)) * vm;
	Perf::Add("prot.need", _tN);
}

void UpdateGuardPosts()
{
	if (ai.GetTunable("apex_guard_posts", 1.f) <= 0.f)
		return;
	const float everyS = ai.GetTunable("apex_protect_field_s", TUNE_PROTECT_FIELD_S);
	const int every = int(((everyS > 0.1f) ? everyS : 2.f) * 30.f);
	if ((ai.frame - gPostAt) < every) {
		// AiUpdate runs twice as often as the posting does, so the estimate
		// rides the spare tick and the two never land on one frame.
		UpdateCoverNeed();
		return;
	}
	gPostAt = ai.frame;
	{ const double _tL = Perf::T0(); RefreshPostLife(); Perf::Add("gp.life", _tL); }
	if (!Builder::gHomeSet)
		return;
	Market::PfRebuild();
	const uint n = Market::gPfPos.length();
	gPostUPos.resize(0);
	gPostUX.resize(0);
	gPostUZ.resize(0);
	gPostUM.resize(0);
	gPostUReach.resize(0);
	gPostAssets = int(n);
	if (n == 0)
		return;

	// The pools' members. Positions are read ONCE, into two float arrays rather
	// than AIFloat3 objects: nothing moves during the pass, and the
	// nearest-free-unit scan below asks u^2/2 times.
	array<CCircuitUnit@> us;
	array<int> ud;
	array<float> ux;
	array<float> uz;
	// PER-BUILDING GUARD POSTS ARE CUT (apexearth, 2026-09-08). They were the
	// largest single source of "go stand somewhere" orders -- park orders
	// outnumbered fight orders 10 to 1 -- and CMilitaryManager::SetGuardPost no
	// longer exists. What survives here is the COVER ACCOUNTING the economy and
	// placement layers read (CoverShort, CoverNeedM, UnitCoverAt, EyesSavedM):
	// with no unit posted, that cover is now turrets only, which is the honest
	// answer. A unit we do not station somewhere is not cover.
	for (uint i = 0; (i < gSquads.length()) && false; ++i) {
		if ((gSquads[i] is null) || (gSquads[i].GetFightType() != int(Task::FightType::DEFEND)))
			continue;
		array<CCircuitUnit@>@ on = gSquads[i].GetUnits();
		if (on is null)
			continue;
		for (uint j = 0; j < on.length(); ++j) {
			if ((on[j] is null) || (on[j].circuitDef is null))
				continue;
			us.insertLast(on[j]);
			ud.insertLast(int(on[j].circuitDef.id));
			const AIFloat3 up = on[j].GetPos(ai.frame);
			ux.insertLast(up.x);
			uz.insertLast(up.z);
		}
	}
	gPostUnits = int(us.length());

	// Cover per asset, in metal: the turrets that reach it to start with.
	// covEyes is the same posting with radar warning at every asset; the
	// difference is what a radar is worth. seen[i] says which assets already
	// have it, so a standing radar widens the real reach too.
	array<float> cov(n);
	array<float> covEyes(n);
	array<bool> seen(n);
	// The posting loop below is O(guards x assets) -- 168 x 277 at minute 59 of
	// a sixteen-AI game -- and every term of it used to reach through a
	// namespace-global array of AIFloat3 and call distance2D. Flat float copies
	// of the three fields that loop reads, taken once per pass, so the inner
	// term is array reads and arithmetic. The arithmetic is unchanged.
	array<float> px(n);
	array<float> pz(n);
	array<float> wm(n);
	array<float> rqv(n);
	gPostTotal = 0.f;
	// A REORDER IS AS STALE AS AN EXPIRY -- AND IS NOT A REASON TO SWEEP AGAIN.
	// The clock alone kept each threat for ten seconds against a field rebuilt
	// every two, so a value sat on the wrong asset; throwing the array away
	// instead would cost a full engine sweep per building finished. PfCommit
	// keeps survivors in their old relative order with newcomers on the end, so
	// one walk of both gPfKey lists carries every value forward, checked against
	// the point it was measured over -- ThreatM is a function of position alone.
	const bool reqAge = (ai.frame - gPostReqAt >= 10 * SECOND);
	array<float> rq(n, -1.f);
	if (!reqAge) {
		uint p = 0;
		const uint on = gPostReq.length();
		for (uint i = 0; i < n; ++i) {
			while ((p < on) && (gPostReqKey[p] != Market::gPfKey[i]))
				++p;
			if (p >= on)
				break;   // the rest are newcomers: they sit after every survivor
			if ((gPostReqX[p] == Market::gPfPos[i].x)
				&& (gPostReqZ[p] == Market::gPfPos[i].z))
				rq[i] = gPostReq[p];
			++p;
		}
	} else {
		gPostReqAt = ai.frame;
	}
	gPostReq = rq;
	gPostReqKey = Market::gPfKey;
	gPostReqX.resize(n);
	gPostReqZ.resize(n);
	gPostReqStamp = Market::gPfStamp;
	// PfCommit lets an asset be nudged under an unchanged key, so the points
	// are checked as well as the two revisions -- and a single mismatch
	// refills the whole array, which is one traversal per TOWER rather than
	// the per-asset query it replaces.
	bool covOk = (gPostCovCache.length() == n)
			&& (gPostCovStamp == Market::gPfStamp)
			&& (gPostCovTwRev == Market::gPfTwRev);
	for (uint i = 0; covOk && (i < n); ++i) {
		covOk = (gPostCovAtX[i] == Market::gPfPos[i].x)
				&& (gPostCovAtZ[i] == Market::gPfPos[i].z);
	}
	if (!covOk) {
		const double _tCv = Perf::T0();
		Market::PfCoverField(gPostCovCache);
		Perf::Add("gp.cover", _tCv);
		gPostCovAtX.resize(n);
		gPostCovAtZ.resize(n);
		for (uint i = 0; i < n; ++i) {
			gPostCovAtX[i] = Market::gPfPos[i].x;
			gPostCovAtZ[i] = Market::gPfPos[i].z;
		}
	}
	const double _tSc = Perf::T0();
	for (uint i = 0; i < n; ++i) {
		const AIFloat3 ap = Market::gPfPos[i];
		px[i] = ap.x;
		pz[i] = ap.z;
		cov[i] = gPostCovCache[i];
		covEyes[i] = cov[i];
		seen[i] = Market::RadarSees(ap);
		wm[i] = Market::gPfWorth[i];
		gPostTotal += wm[i];
		if (gPostReq[i] < 0.f) {
			const double _tTh = Perf::T0();
			gPostReq[i] = Market::ThreatM(ap);
			Perf::Add("gp.threat", _tTh);
		}
		rqv[i] = gPostReq[i];
		gPostReqX[i] = ap.x;
		gPostReqZ[i] = ap.z;
	}
	Perf::Add("gp.scan", _tSc);
	gPostCovStamp = Market::gPfStamp;
	gPostCovTwRev = Market::gPfTwRev;
	// Wanted once, read twice: it sets the warning a radar buys that guard,
	// and it is the unit the cover-need estimate posts.
	gPostNeedDef = CoverUnitDef();
	gPostWarnS = EyesWarningS(gPostNeedDef);
	// Guards not yet posted, compacted into freeIdx[0, nFree): the chosen one is
	// swapped off the end, so the nearest-free scan below shrinks with each
	// assignment instead of re-walking the whole pool every time.
	array<uint> freeIdx(us.length());
	for (uint j = 0; j < us.length(); ++j)
		freeIdx[j] = j;
	uint nFree = us.length();
	// Posts form a wall, not a dot (apexearth: "spreading ourselves out as a
	// wall so... we don't receive a lot of flanking damage and instead get
	// flanking damage on them"): the k-th guard on an asset stands forward
	// of it toward the enemy, offset sideways in alternation.
	array<int> onAsset(n, 0);
	const AIFloat3 foe = Front::FoeAnchor();
	const float WALL_GAP = 96.f;      // elmo between neighbours in the wall
	const float WALL_FWD_MAX = 160.f; // elmo forward of the asset, at most
	float reach = 0.f;
	// The worst-covered asset, carried between guards by the cover-apply pass
	// at the bottom of the loop instead of rescanned at the top: same argmax
	// over the same cov, one walk of n per guard instead of two.
	int bi = -1;
	float bw = -1.f;
	// Exposed() inlined here and in the guard loop below: the same expression on
	// the same values, off the flat copies, so the argmax costs array reads
	// instead of a script call that indexes two namespace globals per asset.
	array<float> expo(n);
	for (uint i = 0; i < n; ++i) {
		const float rq2 = rqv[i];
		float u = 0.f;
		if (rq2 > 1.f) {
			const float sh = (rq2 - cov[i]) / rq2;
			if (sh > 0.f)
				u = wm[i] * sh;
		}
		expo[i] = u;
		if (u > bw) {
			bw = u;
			bi = int(i);
		}
	}
	for (uint k = 0; k < us.length(); ++k) {
		if ((bi < 0) || (nFree == 0))
			break;
		const float bx = px[bi];
		const float bz = pz[bi];
		uint bp = 0;
		// Squared distance: same argmin, and it drops u^2/2 square roots.
		float dxf = ux[freeIdx[0]] - bx;
		float dzf = uz[freeIdx[0]] - bz;
		float bd = dxf * dxf + dzf * dzf;
		for (uint j = 1; j < nFree; ++j) {
			const uint c = freeIdx[j];
			dxf = ux[c] - bx;
			dzf = uz[c] - bz;
			const float dd = dxf * dxf + dzf * dzf;
			if (dd < bd) {
				bd = dd;
				bp = j;
			}
		}
		const uint bu = freeIdx[bp];
		--nFree;
		freeIdx[bp] = freeIdx[nFree];
		const uint at = uint(bi);
		const float r0 = PostReach(ud[bu]);
		const float rE = PostReach(ud[bu], gPostWarnS);
		// The post's reach is also how far from it the unit answers a target
		// (CDefendTask::LeashPosts): a guard does not leave what it covers
		// for a fight it cannot get back from.
		const AIFloat3 postAt = WallPost(Market::gPfPos[at], foe, us[bu].circuitDef.GetMaxRange(), onAsset[at], WALL_GAP, WALL_FWD_MAX);
		++onAsset[at];
		gPostUPos.insertLast(postAt);
		gPostUX.insertLast(postAt.x);
		gPostUZ.insertLast(postAt.z);
		gPostUM.insertLast(Catalog::gCostM[ud[bu]]);
		gPostUReach.insertLast(seen[at] ? rE : r0);
		reach = r0;
		const float m = Catalog::gCostM[ud[bu]];
		const float ax = px[at];
		const float az = pz[at];
		// Nothing past the wider of the two reaches changes, so its exposure is
		// the value this loop left last time and only the argmax has to see it.
		const float rMax = (rE > r0) ? rE : r0;
		const float rMax2 = rMax * rMax;
		bi = -1;
		bw = -1.f;
		for (uint i = 0; i < n; ++i) {
			const float ddx = px[i] - ax;
			const float ddz = pz[i] - az;
			const float d2 = ddx * ddx + ddz * ddz;
			if (d2 < rMax2) {
				const float dd = sqrt(d2);
				const float r = seen[i] ? rE : r0;
				if (dd < r)
					cov[i] += m * (1.f - dd / r);
				if (dd < rE)
					covEyes[i] += m * (1.f - dd / rE);
				const float rq2 = rqv[i];
				float u = 0.f;
				if (rq2 > 1.f) {
					const float sh = (rq2 - cov[i]) / rq2;
					if (sh > 0.f)
						u = wm[i] * sh;
				}
				expo[i] = u;
			}
			if (expo[i] > bw) {
				bw = expo[i];
				bi = int(i);
			}
		}
	}
	gPostUncovered = 0.f;
	gPostUncoveredEyes = 0.f;
	float reqMean = 0.f;
	for (uint i = 0; i < n; ++i) {
		gPostUncovered += expo[i];   // the loop above kept this current
		gPostUncoveredEyes += Exposed(i, covEyes[i]);
		reqMean += rqv[i];
	}
	reqMean /= float(n);

	// The virtual posting reads these, on the tick this pass does not use.
	gPostCov = cov;
	gPostCovEyes = covEyes;
	gPostSeen = seen;

	if (ai.frame >= gPostLogAt + 30 * SECOND) {
		gPostLogAt = ai.frame;
		AiLog(Factory::T() + "apex: posts t=" + ai.teamId
			+ " units=" + gPostUnits + " assets=" + gPostAssets
			+ " uncovered=" + int(gPostUncovered) + "/" + int(gPostTotal)
			+ " reach=" + int(reach)
			+ " need=" + gPostNeedN + "x" + ((gPostNeedDef > 0) ? Catalog::Def(gPostNeedDef).GetName() : "-")
			+ "=" + int(gPostNeedM)
			+ " eyes=" + int(EyesSavedM()) + "/warn=" + formatFloat(gPostWarnS, "", 0, 1) + "s"
			+ " req=" + int(reqMean)
			// Where the guards actually stand on the home->enemy axis, against
			// where the assets are: the wall leans forward only if the first
			// number is the larger one (apexearth: "we spread ourselves out
			// around both the front AND back of our base").
			+ " fwd=" + formatFloat(MeanForward(gPostUPos), "", 0, 2)
			+ "/" + formatFloat(MeanForward(Market::gPfPos), "", 0, 2)
			+ " reqfwd=" + formatFloat(ReqForward(), "", 0, 2));
	}
}

}  // namespace Military
