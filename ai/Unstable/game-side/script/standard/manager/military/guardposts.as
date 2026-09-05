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
array<float> gPostUM;
array<float> gPostUReach;

// Guard metal covering `pos`: each posted unit counts fully at its post and
// fades to nothing at its reach, the falloff the posting itself uses.
float UnitCoverAt(const AIFloat3& in pos)
{
	float m = 0.f;
	for (uint i = 0; i < gPostUPos.length(); ++i) {
		const float r = gPostUReach[i];
		if (r <= 1.f)
			continue;
		const float d = gPostUPos[i].distance2D(pos);
		if (d < r)
			m += gPostUM[i] * (1.f - d / r);
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
// What must be beaten AT each asset: the wave that arrives there, never
// less than the asset itself. A guard is in one fight at a time, so its
// metal counts against the wave at every asset it can reach, not against
// the asset's price -- the same cover-versus-threat the turret price uses.
// Threat is an engine sweep per asset; refreshed on a slower clock.
array<float> gPostReq;
int gPostReqAt = -999999;

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
int CoverUnitDef()
{
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
	return best;
}

// Seconds of warning a radar gives a guard over its own eyes: the best mast
// our builders can place, less the unit's sight, at the fastest foe's speed.
float EyesWarningS(int guardDef)
{
	float radarR = 0.f;
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
	const float los = (guardDef > 0) ? Catalog::gLosR[guardDef] : 450.f;
	const float gap = radarR - ((los > 1.f) ? los : 450.f);
	if (gap <= 0.f)
		return 0.f;
	const float fs = Market::FoeSpeedCap();
	return gap / ((fs > 1.f) ? fs : 100.f);
}

// What a unit reaches before a raider kills one of our economy buildings --
// the mexes and generators the raids come for: its speed times their average
// life under the fastest enemy's gun, plus any warning seconds it gets.
float PostReach(int d, float warnS = 0.f)
{
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
	if (n < 1.f)
		return 400.f;
	hp /= n;
	float dps = 0.f;
	for (int k = 1; k <= Catalog::gDefCount; ++k) {
		if (!Catalog::gAvailable[k] || !Market::LineCombat(k) || Catalog::gFlyer[k])
			continue;
		if ((Catalog::gSpeed[k] >= Market::FoeSpeedCap() - 0.1f) && (Catalog::gDps[k] > dps))
			dps = Catalog::gDps[k];
	}
	if (dps < 1.f)
		dps = 20.f;
	const float r = Catalog::gSpeed[d] * (hp / dps + warnS);
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

// Light units it takes to cover what `cov` leaves uncovered; cov is
// consumed. Assets with radar warning (`seen`) take the wider reach.
int VirtualPost(array<float>@ cov, array<bool>@ seen,
		float vr0, float vrE, float vm, float left)
{
	const uint n = cov.length();
	int count = 0;
	while ((left > gPostTotal * 0.05f) && (count < 60)) {
		int bi = -1;
		float bw = 0.f;
		for (uint i = 0; i < n; ++i) {
			const float u = Exposed(i, cov[i]);
			if (u > bw) {
				bw = u;
				bi = int(i);
			}
		}
		if (bi < 0)
			break;
		for (uint i = 0; i < n; ++i) {
			const float dd = Market::gPfPos[i].distance2D(Market::gPfPos[bi]);
			const float vr = seen[i] ? vrE : vr0;
			if (dd < vr)
				cov[i] += vm * (1.f - dd / vr);
		}
		++count;
		left = 0.f;
		for (uint i = 0; i < n; ++i)
			left += Exposed(i, cov[i]);
	}
	return count;
}

void UpdateGuardPosts()
{
	if (ai.GetTunable("apex_guard_posts", 1.f) <= 0.f)
		return;
	const float everyS = ai.GetTunable("apex_protect_field_s", TUNE_PROTECT_FIELD_S);
	const int every = int(((everyS > 0.1f) ? everyS : 2.f) * 30.f);
	if ((ai.frame - gPostAt) < every)
		return;
	gPostAt = ai.frame;
	if (!Builder::gHomeSet)
		return;
	Market::PfRebuild();
	const uint n = Market::gPfPos.length();
	aiMilitaryMgr.ClearGuardPosts();
	gPostUPos.resize(0);
	gPostUM.resize(0);
	gPostUReach.resize(0);
	gPostAssets = int(n);
	if (n == 0)
		return;

	// The pools' members.
	array<CCircuitUnit@> us;
	array<int> ud;
	for (uint i = 0; i < gSquads.length(); ++i) {
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
	gPostTotal = 0.f;
	const bool reqNow = (gPostReq.length() != n) || (ai.frame - gPostReqAt >= 10 * SECOND);
	if (reqNow) {
		gPostReq.resize(n);
		gPostReqAt = ai.frame;
	}
	for (uint i = 0; i < n; ++i) {
		cov[i] = Market::PfCoverPoint(Market::gPfPos[i], Market::gPfPos[i], 0.f, 0.f);
		covEyes[i] = cov[i];
		seen[i] = Market::RadarSees(Market::gPfPos[i]);
		gPostTotal += Market::gPfWorth[i];
		if (reqNow) {
			const float thr = Market::ThreatM(Market::gPfPos[i]);
			gPostReq[i] = (thr > Market::gPfWorth[i]) ? thr : Market::gPfWorth[i];
		}
	}
	gPostWarnS = EyesWarningS(CoverUnitDef());
	array<bool> used(us.length(), false);
	// Posts form a wall, not a dot (apexearth: "spreading ourselves out as a
	// wall so... we don't receive a lot of flanking damage and instead get
	// flanking damage on them"): the k-th guard on an asset stands forward
	// of it toward the enemy, offset sideways in alternation.
	array<int> onAsset(n, 0);
	const AIFloat3 foe = Front::FoeAnchor();
	const float WALL_GAP = 96.f;      // elmo between neighbours in the wall
	const float WALL_FWD_MAX = 160.f; // elmo forward of the asset, at most
	float reach = 0.f;
	for (uint k = 0; k < us.length(); ++k) {
		int bi = -1;
		float bw = -1.f;
		for (uint i = 0; i < n; ++i) {
			const float u = Exposed(i, cov[i]);
			if (u > bw) {
				bw = u;
				bi = int(i);
			}
		}
		if (bi < 0)
			break;
		int bu = -1;
		float bd = 0.f;
		for (uint j = 0; j < us.length(); ++j) {
			if (used[j])
				continue;
			const float dd = us[j].GetPos(ai.frame).distance2D(Market::gPfPos[bi]);
			if ((bu < 0) || (dd < bd)) {
				bd = dd;
				bu = int(j);
			}
		}
		if (bu < 0)
			break;
		used[bu] = true;
		const float r0 = PostReach(ud[bu]);
		const float rE = PostReach(ud[bu], gPostWarnS);
		// The post's reach is also how far from it the unit answers a target
		// (CDefendTask::LeashPosts): a guard does not leave what it covers
		// for a fight it cannot get back from.
		const AIFloat3 postAt = WallPost(Market::gPfPos[bi], foe, us[bu].circuitDef.GetMaxRange(), onAsset[bi], WALL_GAP, WALL_FWD_MAX);
		aiMilitaryMgr.SetGuardPost(us[bu], postAt, seen[bi] ? rE : r0);
		++onAsset[bi];
		gPostUPos.insertLast(postAt);
		gPostUM.insertLast(Catalog::gCostM[ud[bu]]);
		gPostUReach.insertLast(seen[bi] ? rE : r0);
		reach = r0;
		const float m = Catalog::gCostM[ud[bu]];
		for (uint i = 0; i < n; ++i) {
			const float dd = Market::gPfPos[i].distance2D(Market::gPfPos[bi]);
			const float r = seen[i] ? rE : r0;
			if (dd < r)
				cov[i] += m * (1.f - dd / r);
			if (dd < rE)
				covEyes[i] += m * (1.f - dd / rE);
		}
	}
	gPostUncovered = 0.f;
	gPostUncoveredEyes = 0.f;
	float reqMean = 0.f;
	for (uint i = 0; i < n; ++i) {
		gPostUncovered += Exposed(i, cov[i]);
		gPostUncoveredEyes += Exposed(i, covEyes[i]);
		reqMean += gPostReq[i];
	}
	reqMean /= float(n);

	// Virtual posting: keep placing the light unit at the worst-covered asset
	// until the base is covered, and count what that took. Same greedy, same
	// reach, so the count is what the real posting would use. Run twice:
	// as things stand, and with radar warning everywhere.
	gPostNeedN = 0;
	gPostNeedM = 0.f;
	gPostNeedEyesM = 0.f;
	gPostNeedDef = CoverUnitDef();
	if (gPostNeedDef > 0) {
		const float vr0 = PostReach(gPostNeedDef);
		const float vrE = PostReach(gPostNeedDef, gPostWarnS);
		const float vm = Catalog::gCostM[gPostNeedDef];
		gPostNeedN = VirtualPost(@cov, @seen, vr0, vrE, vm, gPostUncovered);
		gPostNeedM = float(gPostNeedN) * vm;
		array<bool> all(n, true);
		gPostNeedEyesM = float(VirtualPost(@covEyes, @all, vr0, vrE, vm, gPostUncoveredEyes)) * vm;
	}

	if (ai.frame >= gPostLogAt + 30 * SECOND) {
		gPostLogAt = ai.frame;
		AiLog(Factory::T() + "apex: posts t=" + ai.teamId
			+ " units=" + gPostUnits + " assets=" + gPostAssets
			+ " uncovered=" + int(gPostUncovered) + "/" + int(gPostTotal)
			+ " reach=" + int(reach)
			+ " need=" + gPostNeedN + "x" + ((gPostNeedDef > 0) ? Catalog::Def(gPostNeedDef).GetName() : "-")
			+ "=" + int(gPostNeedM)
			+ " eyes=" + int(EyesSavedM()) + "/warn=" + formatFloat(gPostWarnS, "", 0, 1) + "s"
			+ " req=" + int(reqMean));
	}
}

}  // namespace Military
