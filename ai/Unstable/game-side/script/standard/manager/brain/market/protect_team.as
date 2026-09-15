namespace Market {

//------------------------------------------------------------------------------
// THE TEAM HULL AND ITS GAPS.
//
// A defence is overwhelmed piece by piece when the attacker can pick where to
// hit, so the value of a gun is how much it raises the WEAKEST approach into
// what the team owns -- not what it stands beside, and not one player's base.
// Each player publishes its own hull (protect_field.as); this file unions them
// about a common centre and reads, per bearing of that team hull: can the
// enemy's ground walk in here, how much fire meets it at the edge, and how
// much of the team's metal it reaches before it meets enough.
//------------------------------------------------------------------------------

bool            gThOk = false;
AIFloat3        gThMid;
array<float>    gThR;          // team hull radius per bearing (PF_RAYS)
int             gThAt = -999999;
int             gThMates = 0;
// Vertices that carry metal: our own assets at their worth, and each ally's
// rim vertices at the worth that ally reports standing on that bearing.
array<float>    gThVX;
array<float>    gThVZ;
array<float>    gThVW;

int TeamRayOf(const AIFloat3& in p)
{
	const float dx = p.x - gThMid.x;
	const float dz = p.z - gThMid.z;
	float a = atan2(dz, dx);
	if (a < 0.f)
		a += 6.2831853f;
	int b = int(a / (6.2831853f / float(PF_RAYS)));
	if (b < 0)
		b = 0;
	if (b >= PF_RAYS)
		b = PF_RAYS - 1;
	return b;
}

void TeamHullPrep()
{
	PfRebuild();
	if (gThAt == gPfAt)
		return;
	gThAt = gPfAt;
	gThOk = false;
	gThMates = 0;
	gThVX.resize(0);
	gThVZ.resize(0);
	gThVW.resize(0);
	if (!gPfRimOk)
		return;
	const double _t = Perf::T0();
	// Every member's polygon: 24 rim vertices about its own centre. Ours from
	// the field itself, theirs from the blackboard.
	array<float> px;
	array<float> pz;
	array<float> cxs;
	array<float> czs;
	const float wedge = 6.2831853f / float(PF_RAYS);
	for (int b = 0; b < PF_RAYS; ++b) {
		float rb = gPfRimR[b];
		if ((gPfCapR > 1.f) && (rb > gPfCapR))
			rb = gPfCapR;
		const float ang = wedge * (float(b) + 0.5f);
		px.insertLast(gPfMid.x + cos(ang) * rb);
		pz.insertLast(gPfMid.z + sin(ang) * rb);
	}
	cxs.insertLast(gPfMid.x);
	czs.insertLast(gPfMid.z);
	for (uint i = 0; i < gPfPos.length(); ++i) {
		gThVX.insertLast(gPfPos[i].x);
		gThVZ.insertLast(gPfPos[i].z);
		gThVW.insertLast(gPfWorth[i]);
	}
	if (gShieldMates is null)
		@gShieldMates = ai.GetTeamIds();
	if (gShieldMates !is null) {
		for (uint m = 0; m < gShieldMates.length(); ++m) {
			const int t = int(gShieldMates[m]);
			if (t == ai.teamId)
				continue;
			const float mx = ai.ReadTeamValue(t, TV_PF_MX, -1.f);
			if (mx < 0.f)
				continue;
			const float mz = ai.ReadTeamValue(t, TV_PF_MZ, -1.f);
			if (mz < 0.f)
				continue;
			++gThMates;
			cxs.insertLast(mx);
			czs.insertLast(mz);
			for (int b = 0; b < PF_RAYS; ++b) {
				const float rb = ai.ReadTeamValue(t, "pfr" + b, 0.f);
				const float wb = ai.ReadTeamValue(t, "pfw" + b, 0.f);
				const float ang = wedge * (float(b) + 0.5f);
				const float vx = mx + cos(ang) * rb;
				const float vz = mz + sin(ang) * rb;
				px.insertLast(vx);
				pz.insertLast(vz);
				gThVX.insertLast(vx);
				gThVZ.insertLast(vz);
				gThVW.insertLast(wb);
			}
		}
	}
	// The centre is the mean of the members' centres -- geometry, not worth,
	// so the seat's metal does not drag the bearings toward the rear.
	float sx = 0.f;
	float sz = 0.f;
	for (uint i = 0; i < cxs.length(); ++i) {
		sx += cxs[i];
		sz += czs[i];
	}
	gThMid = AIFloat3(sx / float(cxs.length()), 0.f, sz / float(czs.length()));
	gThR.resize(PF_RAYS);
	for (int b = 0; b < PF_RAYS; ++b)
		gThR[b] = 0.f;
	for (uint i = 0; i < px.length(); ++i) {
		const AIFloat3 v(px[i], 0.f, pz[i]);
		const int b = TeamRayOf(v);
		const float rr = v.distance2D(gThMid);
		if (rr > gThR[b])
			gThR[b] = rr;
	}
	// Empty bearings take the chord between their occupied neighbours, as the
	// per-player rim does.
	array<float> sm = gThR;
	for (int b = 0; b < PF_RAYS; ++b) {
		if (gThR[b] > 0.f)
			continue;
		int dl = 1, dh = 1;
		while ((dl < PF_RAYS) && (gThR[(b + PF_RAYS - dl) % PF_RAYS] <= 0.f))
			++dl;
		while ((dh < PF_RAYS) && (gThR[(b + dh) % PF_RAYS] <= 0.f))
			++dh;
		if ((dl >= PF_RAYS) || (dh >= PF_RAYS))
			continue;
		const float rl = gThR[(b + PF_RAYS - dl) % PF_RAYS];
		const float rh = gThR[(b + dh) % PF_RAYS];
		sm[b] = (rl * float(dh) + rh * float(dl)) / float(dl + dh);
	}
	gThR = sm;
	gThOk = true;
	Perf::Add("prot.teamhull", _t);
}

//------------------------------------------------------------------------------
// THE GAPS. Per bearing of the team hull, at the wall's standoff outside it:
//   walk   -- the enemy's ground can reach this point from where they live
//             (an off-map, cliff or water bearing is a wall already);
//   cover  -- metal of wave the team's guns stop there (ours and allies');
//   behind -- the team's metal an army entering here reaches before it meets
//             cover of at least the wave, walking straight in;
//   open   -- the share of the wave the edge does not stop.
// The worst gap is the bearing with the most behind x open. A wall slot on a
// bearing is priced by `behind` (protect_fill.as), so the gun that closes the
// worst gap wins whether or not we have been hit there yet.
//------------------------------------------------------------------------------

array<bool>     gGapWalk;
array<float>    gGapCover;
array<float>    gGapBehind;
array<float>    gGapOpen;
array<float>    gGapStopR;     // radius the walk-in met the wave's worth of fire
float           gGapWave = 0.f;
float           gGapStandoff = 0.f;
int             gGapAt = -999999;
int             gGapHullAt = -999999;
int             gNextGapLog = 0;
const float     GAP_STEP = 256.f;

int             gGapCursor = PF_RAYS;   // next bearing of the running pass
AIFloat3        gGapFoe;
bool            gGapFoeOk = false;
const int       GAP_PER_CALL = 3;       // bearings read per call: spread, not batched

void GapsPrep(float wave, float standoff)
{
	TeamHullPrep();
	if (!gThOk)
		return;
	if (gGapCursor >= PF_RAYS) {
		if ((gGapHullAt == gThAt) && (ai.frame - gGapAt < 10 * SECOND)
			&& (gGapWave == wave))
			return;
		gGapAt = ai.frame;
		gGapHullAt = gThAt;
		gGapWave = wave;
		gGapStandoff = standoff;
		gGapFoeOk = FoeRef(gGapFoe);
		gGapCursor = 0;
		if (gGapWalk.length() != uint(PF_RAYS)) {
			gGapWalk.resize(PF_RAYS);
			gGapCover.resize(PF_RAYS);
			gGapBehind.resize(PF_RAYS);
			gGapOpen.resize(PF_RAYS);
			gGapStopR.resize(PF_RAYS);
		}
	}
	const double _t = Perf::T0();
	const float wedge = 6.2831853f / float(PF_RAYS);
	const int bEnd = (gGapCursor + GAP_PER_CALL < PF_RAYS)
			? (gGapCursor + GAP_PER_CALL) : PF_RAYS;
	for (int b = gGapCursor; b < bEnd; ++b) {
		const float ang = wedge * (float(b) + 0.5f);
		const AIFloat3 dir(cos(ang), 0.f, sin(ang));
		const float edgeR = gThR[b] + standoff;
		const AIFloat3 e = gThMid + dir * edgeR;
		gGapWalk[b] = OnMap(e) && gGapFoeOk && ai.GroundConnected(e, gGapFoe);
		gGapCover[b] = OnMap(e) ? CoverAt(e) : 0.f;
		float open = 0.f;
		if (wave > 1.f) {
			open = (wave - gGapCover[b]) / wave;
			if (open < 0.f)
				open = 0.f;
			if (open > 1.f)
				open = 1.f;
		}
		gGapOpen[b] = gGapWalk[b] ? open : 0.f;
		// Walk in until the wave meets its own worth of fire.
		float stopR = edgeR;
		if (gGapWalk[b] && (open > 0.f)) {
			stopR = 0.f;
			for (float r = edgeR - GAP_STEP; r > 0.f; r -= GAP_STEP) {
				const AIFloat3 p = gThMid + dir * r;
				if (!OnMap(p))
					continue;
				if (CoverAt(p) >= wave) {
					stopR = r;
					break;
				}
			}
		}
		gGapStopR[b] = stopR;
		float behind = 0.f;
		if (gGapWalk[b] && (open > 0.f)) {
			for (uint i = 0; i < gThVX.length(); ++i) {
				const AIFloat3 v(gThVX[i], 0.f, gThVZ[i]);
				if (TeamRayOf(v) != b)
					continue;
				if (v.distance2D(gThMid) < stopR)
					continue;
				behind += gThVW[i];
			}
		}
		gGapBehind[b] = behind;
	}
	gGapCursor = bEnd;
	Perf::Add("prot.gaps", _t);
	if ((gGapCursor >= PF_RAYS) && (ai.frame >= gNextGapLog)) {
		gNextGapLog = ai.frame + 30 * SECOND;
		int nWalk = 0;
		int nHeld = 0;
		int w0 = -1, w1 = -1, w2 = -1;
		float m0 = 0.f, m1 = 0.f, m2 = 0.f;
		string row = "";
		for (int b = 0; b < PF_RAYS; ++b) {
			if (gGapWalk[b]) {
				++nWalk;
				if (gGapOpen[b] <= 0.f)
					++nHeld;
			}
			const float gm = gGapBehind[b] * gGapOpen[b];
			if (gm > m0) {
				w2 = w1; m2 = m1; w1 = w0; m1 = m0; w0 = b; m0 = gm;
			} else if (gm > m1) {
				w2 = w1; m2 = m1; w1 = b; m1 = gm;
			} else if (gm > m2) {
				w2 = b; m2 = gm;
			}
			row += " " + b + ":" + (gGapWalk[b] ? "w" : "-")
				+ int(gGapCover[b]) + "/" + int(gGapBehind[b])
				+ "@" + int(gGapOpen[b] * 100.f);
		}
		AiLog("apex: gaps mates=" + gThMates + " mid=" + int(gThMid.x) + ","
			+ int(gThMid.z) + " wave=" + int(wave) + " walkable=" + nWalk
			+ " held=" + nHeld + " worst=" + w0 + ":" + int(m0) + "," + w1
			+ ":" + int(m1) + "," + w2 + ":" + int(m2)
			+ " |" + row);
	}
}

// The team metal a wall slot on this bearing stands in front of.
float GapBehindAt(const AIFloat3& in pos)
{
	if (!gThOk || (gGapBehind.length() == 0))
		return 0.f;
	return gGapBehind[uint(TeamRayOf(pos))];
}

bool GapWalkableAt(const AIFloat3& in pos)
{
	if (!gThOk || (gGapWalk.length() == 0))
		return true;
	return gGapWalk[uint(TeamRayOf(pos))];
}

}  // namespace Market
