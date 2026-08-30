namespace Market {

//------------------------------------------------------------------------------
// THE WALL: ground-defence sites are slots on the perimeter of what we own.
//
// apexearth 2026-08-30: "Ideally we create a long wall of towers wrapping
// around our base, joining with any allied tower walls that we have. We'd
// expect the wall to push outwards towards our enemies if we expand outwards,
// so older towers in the back can eventually be reclaimed" -- and explicitly:
// do not build this on the front-line or base-border models.
//
// So the wall is derived from the one thing that is always true: where our own
// buildings stand. The rim (protect_field.as) is the per-bearing hull of our
// assets; the wall is that hull pushed out by a standoff and sampled at tower
// pitch, so filled slots form a contiguous line of fire. A new mex or lab on
// any bearing moves that bearing's rim, and the wall follows on the next
// rebuild -- outward growth for free, and the stranded-tower reclaim
// (want_reclaim.as) retires the guns the wall has grown past.
//
// A bearing an ALLY's base sits beyond is theirs to hold: our wall ends where
// their wall begins, the same cone test the closure ring uses. A bearing that
// runs off the map is a wall already. Slots are QUANTIZED -- the rim reading
// is stepped in 256-elmo increments -- so the wall does not creep a few elmos
// every rebuild and re-elect a builder mid-walk; it stays put until the base
// genuinely outgrows it, then steps outward.
//
// The wall only offers PLACES. What a slot is worth -- stake behind it, the
// wave arriving, cover shortfall, hazard -- is priced by the same auction
// terms as every other candidate (want_protect.as, DefSiteFill).
//------------------------------------------------------------------------------

array<AIFloat3> gWallP;        // slot positions, perimeter order
array<float>    gWallThreat;   // position-only senses, cached on the field stamp
array<float>    gWallCover;
array<float>    gWallHz;
array<float>    gWallSiege;
array<bool>     gWallOpen;     // no standing tower of ours covers this slot
array<float>    gWallR;        // the wall's radius per rim bearing
bool            gWallROk = false;
int             gWallAt = -999999;
const int  WALL_MAX_SLOTS = 64;
const float WALL_QUANT = 256.f;

void WallPrep()
{
	PfRebuild();
	if (gWallAt == gPfAt)
		return;
	gWallAt = gPfAt;
	gWallP.resize(0);
	gWallThreat.resize(0);
	gWallCover.resize(0);
	gWallHz.resize(0);
	gWallSiege.resize(0);
	gWallOpen.resize(0);
	gWallROk = false;
	if (!gPfRimOk)
		return;
	const double _tWall = Perf::T0();
	const float lightR = Brain::LightTowerRange();
	const float standoff = lightR
			* ai.GetTunable("apex_wall_standoff", TUNE_WALL_STANDOFF);
	float pitch = lightR * ai.GetTunable("apex_wall_pitch", TUNE_WALL_PITCH);
	if (pitch < 64.f)
		pitch = 64.f;

	// A LONE FAR MEX MUST NOT DRAG THE WALL ACROSS THE MAP. The raw rim is the
	// furthest thing on each bearing, so one scouting-claimed mex 3,500 out
	// put wall slots mid-map, 4,000-elmo walks behind them and frames the army
	// never stood near (23 of 32 towers lost, first exercise game). The wall
	// wraps where the MASS of the base is: each bearing's radius is capped at
	// a multiple of the worth-weighted RMS distance of everything we own, so a
	// real expansion (many buildings, real worth) moves the cap and a stray
	// claim does not.
	// ...over the BUILDINGS ONLY. Extractors carry capitalized STREAM worth,
	// which dominates the field's total late game, and mexes are exactly what
	// sprawls: with them in the basis the cap grew to half the map by minute
	// 40, every tower read thousands of elmos interior, and the wall-stranded
	// retirement ate the standing defence (measured: def 340/34,451, 17 of 21
	// towers lost, most to our own reclaim). The wall follows where the base's
	// buildings go; mexes beyond it are outposts, not wall.
	float rms = 0.f;
	{
		float sw = 0.f;
		float sd2 = 0.f;
		for (uint i = 0; i < gPfPos.length(); ++i) {
			if ((i < gPfIsMex.length()) && gPfIsMex[i])
				continue;
			const float dd = gPfPos[i].distance2D(gPfMid);
			sd2 += gPfWorth[i] * dd * dd;
			sw += gPfWorth[i];
		}
		if (sw > 1.f)
			rms = sqrt(sd2 / sw);
	}
	const float capR = rms * ai.GetTunable("apex_wall_reach", TUNE_WALL_REACH);
	// One radius per bearing: capped, stepped so growth inside a quantum does
	// not move the wall, standoff outside the buildings.
	array<float> wr(PF_RAYS, 0.f);
	float perim = 0.f;
	for (int b = 0; b < PF_RAYS; ++b) {
		float rb = gPfRimR[b];
		if ((capR > 1.f) && (rb > capR))
			rb = capR;
		float rq = float(int(rb / WALL_QUANT)) * WALL_QUANT + standoff;
		if (rq < standoff)
			rq = standoff;
		wr[b] = rq;
		perim += rq * (6.2831853f / float(PF_RAYS));
	}
	if (perim / pitch > float(WALL_MAX_SLOTS))
		pitch = perim / float(WALL_MAX_SLOTS);
	gWallR = wr;
	gWallROk = true;

	// Teammate homes off the blackboard, for the ally-shield cone -- the same
	// source and cone ClosurePrep uses, never GetAllyInflAt (it counts us).
	array<float> hx;
	array<float> hz2;
	if (gShieldMates is null)
		@gShieldMates = ai.GetTeamIds();
	if (gShieldMates !is null) {
		for (uint m = 0; m < gShieldMates.length(); ++m) {
			if (int(gShieldMates[m]) == ai.teamId)
				continue;
			const float mx = ai.ReadTeamValue(int(gShieldMates[m]), "homex", -1.f);
			const float mz = ai.ReadTeamValue(int(gShieldMates[m]), "homez", -1.f);
			if ((mx < 0.f) || (mz < 0.f))
				continue;
			hx.insertLast(mx);
			hz2.insertLast(mz);
		}
	}

	RiskFill();
	RiskFillSiege();
	const float expFrac = ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	// Slots sit ON each wedge's own radius -- polar, never a chord between
	// vertices: a chord between a big lobe and a small one cut up to 2,000
	// elmos inside the lobe (measured, first exercise game: rimD -1026 at
	// election on wall slots).
	const float wedge = 6.2831853f / float(PF_RAYS);
	for (int b = 0; b < PF_RAYS; ++b) {
		const float arc = wr[b] * wedge;
		int nb = int(arc / pitch);
		if (nb < 1)
			nb = 1;
		for (int k = 0; k < nb; ++k) {
			const float ang = wedge * float(b)
					+ wedge * ((float(k) + 0.5f) / float(nb));
			const AIFloat3 dir(cos(ang), 0.f, sin(ang));
			const AIFloat3 s = gPfMid + dir * wr[b];
			if (!OnMap(s))
				continue;   // the map edge is a wall already
			bool shielded = false;
			for (uint m = 0; !shielded && (m < hx.length()); ++m) {
				const float vx = hx[m] - gPfMid.x;
				const float vz = hz2[m] - gPfMid.z;
				const float along = vx * dir.x + vz * dir.z;
				if (along <= wr[b])
					continue;
				const float lx = vx - dir.x * along;
				const float lz = vz - dir.z * along;
				if (lx * lx + lz * lz <= 0.09f * along * along)
					shielded = true;
			}
			if (shielded)
				continue;   // the ally's wall holds this bearing; ours joins it
			bool open = true;
			for (uint i = 0; open && (i < gPfTwPos.length()); ++i) {
				if (gPfTwPos[i].distance2D(s) <= gPfTwReach[i])
					open = false;
			}
			const float cv = CoverAt(s);
			gWallP.insertLast(s);
			gWallThreat.insertLast(ThreatAt(s));
			gWallCover.insertLast(cv);
			gWallHz.insertLast(HazardWith(s, cv));
			gWallSiege.insertLast(SiegeWith(s, cv, expFrac));
			gWallOpen.insertLast(open);
			if (int(gWallP.length()) >= WALL_MAX_SLOTS)
				break;
		}
		if (int(gWallP.length()) >= WALL_MAX_SLOTS)
			break;
	}
	Perf::Add("prot.wall", _tWall);
}

uint PfWallSlots(array<AIFloat3>& out sites)
{
	WallPrep();
	sites = gWallP;
	return sites.length();
}

float PfWallThreat(uint i) { return gWallThreat[i]; }
bool WallSlotOpen(uint i)
{
	return (i < gWallOpen.length()) && gWallOpen[i];
}
float PfWallCover(uint i)  { return gWallCover[i]; }
float PfWallHz(uint i)     { return gWallHz[i]; }
float PfWallSiege(uint i)  { return gWallSiege[i]; }

// Share of wall slots something standing already covers; -1 before the wall
// exists. The number the wall is judged on, logged in `apex: fronttowers`.
float WallClosureFrac()
{
	WallPrep();
	if (gWallOpen.length() == 0)
		return -1.f;
	int closed = 0;
	for (uint i = 0; i < gWallOpen.length(); ++i) {
		if (!gWallOpen[i])
			++closed;
	}
	return float(closed) / float(gWallOpen.length());
}

// How far OUTSIDE the wall this position is; negative is behind it, and the
// magnitude is how deep. 0 while the wall does not exist yet, which no caller
// may read as "on the wall" without checking it stands.
float WallRimDist(const AIFloat3& in p)
{
	WallPrep();
	if (!gWallROk)
		return 0.f;
	return p.distance2D(gPfMid) - gWallR[PfRayOf(p)];
}

bool WallStands()
{
	WallPrep();
	return gWallROk;
}

// Is the wall AHEAD of this position -- the wall point on its own bearing --
// covered by a standing tower? The wall-stranded retirement requires it:
// nothing is obsolete before its better is standing, or the wall's own
// outward steps put the standing line on a build-reclaim treadmill (measured:
// 27 towers built, 17 self-reclaimed, 10 standing).
bool WallAheadHeld(const AIFloat3& in p)
{
	WallPrep();
	if (!gWallROk)
		return false;
	AIFloat3 dir = p - gPfMid;
	if (dir.SqLength2D() < 1.f)
		return false;
	dir.SafeNormalize2D();
	const AIFloat3 wp = gPfMid + dir * gWallR[PfRayOf(p)];
	for (uint i = 0; i < gPfTwPos.length(); ++i) {
		if (gPfTwPos[i].distance2D(wp) <= gPfTwReach[i])
			return true;
	}
	return false;
}

// Of the wall segment this candidate's reach spans, how much was open? Full
// shielded-stake credit for plugging a hole, none for standing on a segment
// already covered -- the saturation that makes a redundant post worthless.
float WallAdds(const AIFloat3& in at, float reach)
{
	WallPrep();
	if ((reach <= 0.f) || (gWallP.length() == 0))
		return 0.f;
	int inReach = 0;
	int open = 0;
	for (uint i = 0; i < gWallP.length(); ++i) {
		if (at.distance2D(gWallP[i]) > reach)
			continue;
		++inReach;
		if (gWallOpen[i])
			++open;
	}
	return (inReach > 0) ? (float(open) / float(inReach)) : 0.f;
}

}  // namespace Market
