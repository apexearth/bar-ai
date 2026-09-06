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
// terms as every other candidate (protect_fill.as, DefSiteFill).
//------------------------------------------------------------------------------

array<AIFloat3> gWallP;        // slot positions, perimeter order
array<float>    gWallThreat;   // position-only senses, cached on the field stamp
array<float>    gWallCover;
array<float>    gWallHz;
array<float>    gWallSiege;
array<bool>     gWallOpen;     // no standing tower of ours covers this slot
array<bool>     gWallLine;     // slot belongs to the FRONT LINE, not the ring
array<bool>     gWallAdj;      // a neighbouring slot is already held
int             gWallAdjAt = -999999;   // ...built on first ask per wall stamp
float           gWallAdjPitch = 0.f;
array<float>    gWallR;        // the wall's radius per rim bearing
bool            gWallROk = false;
// THE FRONT LINE (apexearth, watching a 2v2: "I'm expecting a clear line of
// towers across the map"). A ring wraps one base; a front is a LINE: slots
// along the perpendicular to the home->enemy axis, standing at the wall's
// forward radius, running laterally until the map edge or an ALLY'S LANE --
// their line continues ours, which is what joins two allies' walls into one
// front. The ring stays for the flanks and rear the line does not cover.
bool            gWallLineOk = false;
AIFloat3        gWallA;        // the line's anchor point
AIFloat3        gWallF;        // unit home->enemy direction
int             gWallAt = -999999;
const int  WALL_MAX_SLOTS = 64;
const int  WALL_LINE_ROWS = 2;
const float WALL_QUANT = 256.f;

void WallEmitSlot(const AIFloat3& in s, bool line, float expFrac)
{
	const bool open = !PfCoveredAt(s);   // same test, off the tower index
	const float cv = CoverAt(s);
	gWallP.insertLast(s);
	gWallThreat.insertLast(ThreatAt(s));
	gWallCover.insertLast(cv);
	gWallHz.insertLast(HazardWith(s, cv));
	gWallSiege.insertLast(SiegeWith(s, cv, expFrac));
	gWallOpen.insertLast(open);
	gWallLine.insertLast(line);
}

// One row of line slots: the row's anchor, then outward each side a pitch at
// a time until the map edge, an ally's lane or the choke's shoulder. False
// once the slot table is full.
bool WallEmitRow(const AIFloat3& in rowA, const AIFloat3& in lat, float pitch,
		float lineHalf, const array<float>& in hx, const array<float>& in hz,
		float expFrac)
{
	WallEmitSlot(rowA, true, expFrac);
	for (int sideK = -1; sideK <= 1; sideK += 2) {
		for (int k = 1; k <= WALL_MAX_SLOTS; ++k) {
			if ((lineHalf >= 0.f) && (pitch * float(k) > lineHalf))
				break;   // past the choke's shoulder
			const AIFloat3 s = rowA + lat * (pitch * float(k * sideK));
			if (!OnMap(s))
				break;
			bool allyLane = false;
			const float dUs = s.distance2D(gPfMid);
			for (uint m = 0; !allyLane && (m < hx.length()); ++m) {
				if (s.distance2D(AIFloat3(hx[m], 0.f, hz[m])) < dUs)
					allyLane = true;
			}
			if (allyLane)
				break;
			WallEmitSlot(s, true, expFrac);
			if (int(gWallP.length()) >= WALL_MAX_SLOTS)
				return false;
		}
	}
	return int(gWallP.length()) < WALL_MAX_SLOTS;
}

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
	gWallLine.resize(0);
	gWallAdj.resize(0);
	gWallROk = false;
	gWallLineOk = false;
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
	// THE LINE FIRST -- see the header. Anchored at the wall's forward radius
	// on the enemy bearing, running along the perpendicular until the map
	// edge (a wall already) or an ally's lane (a slot closer to their home
	// than ours is theirs to hold -- their line continues ours).
	AIFloat3 foeP;
	if (FoeRef(foeP)) {
		AIFloat3 fd = foeP - gPfMid;
		const float foeD = sqrt(fd.SqLength2D());
		if (foeD > 1.f) {
			fd *= (1.f / foeD);
			// THE LINE STANDS AT THE FRONTIER, NOT THE BASE (apexearth
			// 2026-08-30: "Players often walk up to map halfway point,
			// capping mexes, and then making the tower wall"). Its distance
			// is the furthest extractor we have actually CAPPED along the
			// enemy axis -- claimed ground, the one read here that is never
			// a model -- bounded by the halfway point so a lone deep claim
			// cannot drag it into their half. No forward mexes yet means it
			// hugs the base hull; every capped mex walks it out.
			float lineR = wr[PfRayOf(gPfMid + fd * 1000.f)];
			float mexFwd = 0.f;
			for (uint i = 0; i < gPfPos.length(); ++i) {
				if ((i >= gPfIsMex.length()) || !gPfIsMex[i])
					continue;
				const float df = (gPfPos[i].x - gPfMid.x) * fd.x
						+ (gPfPos[i].z - gPfMid.z) * fd.z;
				if (df > mexFwd)
					mexFwd = df;
			}
			if (mexFwd + standoff > lineR)
				lineR = float(int(mexFwd / WALL_QUANT)) * WALL_QUANT
						+ standoff;
			// Halfway is measured from HOME, not from the base centroid: the
			// centroid walks forward with every capped mex, so a cap taken
			// from it put the line at 0.65 of the start separation -- their
			// half of the map (measured: lineFwd=0.65, 42 wins for mex
			// guards and none for the line, a commander dead at 0.43).
			float halfD = foeD * 0.5f;
			if (Builder::gHomeSet) {
				const AIFloat3 hrel = gPfMid - Builder::gHomePos;
				const AIFloat3 frel = foeP - Builder::gHomePos;
				const float midAhead = (frel.x * fd.x + frel.z * fd.z) * 0.5f
						- (hrel.x * fd.x + hrel.z * fd.z);
				if (midAhead < halfD)
					halfD = midAhead;
			}
			if (halfD < standoff)
				halfD = standoff;
			if (lineR > halfD)
				lineR = float(int(halfD / WALL_QUANT)) * WALL_QUANT;
			if (lineR < standoff)
				lineR = standoff;
			AIFloat3 anchor = gPfMid + fd * lineR;
			// THE NARROWEST PASSAGE WINS (apexearth: "Ideally we hold a
			// frontline at a narrower part of the map... holding that line
			// is best"). With a choke on our lane the line stands on it and
			// runs along its own cross-section, end to end plus a shoulder
			// each side; the frontier-of-capped-mexes rule above is the
			// stand-in for a lane with no choke. The choke is picked between
			// home and their base, so it is inside the halfway bound.
			AIFloat3 chokeAt;
			AIFloat3 chokeAcross;
			float chokeHalfW = 0.f;
			const bool onChoke = ChokeTarget(chokeAt, chokeAcross, chokeHalfW);
			AIFloat3 lineLat(-fd.z, 0.f, fd.x);
			float lineHalf = -1.f;   // < 0: run to the map edge or an ally lane
			if (onChoke) {
				lineLat = chokeAcross;
				// The line faces across its own run, toward them.
				AIFloat3 nrm(-lineLat.z, 0.f, lineLat.x);
				if ((nrm.x * fd.x + nrm.z * fd.z) < 0.f)
					nrm = AIFloat3(-nrm.x, 0.f, -nrm.z);
				fd = nrm;
				// OUR MOUTH OF THE PASSAGE, NOT ITS MIDDLE. The choke's
				// centre is the map's centre on Aethermoor, contested
				// equally from both ends (apexearth, watching: "the logic
				// of the front line on this particular map... seemed to
				// want to make our guys just build directly in the center
				// of the map"). The guns stand a tower's reach back on our
				// side, so the passage itself is in their range and whoever
				// comes through it walks into them.
				anchor = chokeAt - fd * lightR;
				lineHalf = chokeHalfW + pitch;
				// AS CLOSE TO THE CHOKE AS IS SAFE (apexearth: "Build
				// defenses as close as is safe, no point half-building
				// something only to lose it"). From our mouth of the passage
				// the anchor steps back toward home a pitch at a time until
				// it stands on ground that is not hot and that our influence
				// holds; as the army pushes forward the line follows it up,
				// and while the passage is theirs the line is wherever ours
				// ends -- never the passage itself, never only the base.
				{
					const AIFloat3 homeP = Builder::gHomeSet
							? Builder::gHomePos : gPfMid;
					const AIFloat3 relA = anchor - homeP;
					const float span = relA.x * fd.x + relA.z * fd.z;
					const int steps = int(span / pitch) - 1;
					for (int st = 0; st < steps; ++st) {
						const bool safe = OnMap(anchor)
								&& !Builder::SiteHot(anchor)
								&& (ai.GetAllyInflAt(anchor) >= ai.GetEnemyInflAt(anchor));
						if (safe)
							break;
						anchor -= fd * pitch;
					}
				}
			}
			if (OnMap(anchor)) {
				gWallLineOk = true;
				gWallA = anchor;
				gWallF = fd;
				// TWO ROWS DEEP (apexearth: "if you're not gonna build all
				// the stuff and you just half ass it, then it's never gonna
				// work... It needs to be really strong to succeed"). One
				// tower per slot was the whole line; the second row, a
				// pitch behind the first, doubles it and puts the guns in
				// each other's cover.
				for (int row = 0; row < WALL_LINE_ROWS; ++row) {
					const AIFloat3 rowA = anchor - fd * (pitch * float(row));
					if (!OnMap(rowA) || !WallEmitRow(rowA, lineLat, pitch,
							lineHalf, hx, hz2, expFrac))
						break;
				}
			}
		}
	}
	// The ring covers what the line does not: slots sit ON each wedge's own
	// radius -- polar, never a chord between vertices: a chord between a big
	// lobe and a small one cut up to 2,000 elmos inside the lobe (measured,
	// first exercise game: rimD -1026 at election on wall slots).
	const float wedge = 6.2831853f / float(PF_RAYS);
	for (int b = 0; b < PF_RAYS; ++b) {
		if (gWallLineOk) {
			// Within 60 degrees of the enemy bearing the LINE is the wall.
			const float angC = wedge * (float(b) + 0.5f);
			if (cos(angC) * gWallF.x + sin(angC) * gWallF.z > 0.5f)
				continue;
		}
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
			WallEmitSlot(s, false, expFrac);
			if (int(gWallP.length()) >= WALL_MAX_SLOTS)
				break;
		}
		if (int(gWallP.length()) >= WALL_MAX_SLOTS)
			break;
	}
	// The adjacency pass that used to stand here is now built on demand --
	// see WallAdjPrep. It is every slot against every slot, and nothing has
	// asked it a question since the pull stopped consulting it.
	gWallAdjPitch = pitch;
	gWallAdjAt = -999999;
	Perf::Add("prot.wall", _tWall);
}

// Adjacency, for the creep: a slot whose neighbour is already HELD may rise
// under that tower's fire even where the enemy stands. Built on first ask per
// wall stamp and against HELD slots only -- it was every slot against every
// slot in WallPrep, for a reading DefSiteFill can no longer reach. Kept
// because the creep is his ruling; rewiring the pull to it is his decision.
void WallAdjPrep()
{
	WallPrep();
	if (gWallAdjAt == gWallAt)
		return;
	gWallAdjAt = gWallAt;
	const uint n = gWallP.length();
	gWallAdj.resize(n);
	array<uint> held;
	for (uint j = 0; j < n; ++j) {
		if (!gWallOpen[j])
			held.insertLast(j);
	}
	const float rr = gWallAdjPitch * 1.6f;
	for (uint i = 0; i < n; ++i) {
		bool adj = false;
		for (uint k = 0; !adj && (k < held.length()); ++k) {
			const uint j = held[k];
			if ((i != j) && (gWallP[i].distance2D(gWallP[j]) <= rr))
				adj = true;
		}
		gWallAdj[i] = adj;
	}
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

bool WallSlotLine(uint i)
{
	return (i < gWallLine.length()) && gWallLine[i];
}

bool WallSlotAdjHeld(uint i)
{
	WallAdjPrep();
	return (i < gWallAdj.length()) && gWallAdj[i];
}

// How much of the LINE stands: covered line slots / line slots. -1 without a
// line. "It needs to extend the whole way" is judged on this number.
float WallLineFill()
{
	WallPrep();
	if (!gWallLineOk)
		return -1.f;
	int n = 0;
	int held = 0;
	for (uint i = 0; i < gWallLine.length(); ++i) {
		if (!gWallLine[i])
			continue;
		++n;
		if (!gWallOpen[i])
			++held;
	}
	return (n > 0) ? (float(held) / float(n)) : -1.f;
}
// HOW WIDE THE LINE IS, in slots. lineFill alone cannot be read: values of
// 0.00, 0.50 and 1.00 across a team say nothing about whether the line is 2
// slots or 40, and the whole question ("we have almost no defenses really on
// our front line") is a question about its width. The lateral walk stops at
// the first slot nearer a teammate's home than ours, which in a packed team
// box is close by, so this is the number that says whether each player's line
// is a sliver.
// Total wall slots, line and ring together -- the denominator lineSlots is a
// share of.
int PfWallSlotCount()
{
	WallPrep();
	return int(gWallP.length());
}

int WallLineSlots()
{
	WallPrep();
	int n = 0;
	for (uint i = 0; i < gWallLine.length(); ++i) {
		if (gWallLine[i])
			++n;
	}
	return n;
}

// THE HELD LINE, for what fortifies it. apexearth 2026-09-02, after a 4v4
// whose line stood for ten minutes: "One thing we didn't do well that game
// was making Jammers/radar up front, and anti air." The centroid of the
// line slots a standing tower covers, one pitch back toward home so the
// sensor stands behind the guns; `n` is how many slots are held. False
// while fewer than `minHeld` are.
bool WallLineHeld(AIFloat3& out at, int& out n, int minHeld)
{
	WallPrep();
	n = 0;
	if (!gWallLineOk)
		return false;
	float sx = 0.f, sz = 0.f;
	for (uint i = 0; i < gWallLine.length(); ++i) {
		if (!gWallLine[i] || gWallOpen[i])
			continue;
		sx += gWallP[i].x;
		sz += gWallP[i].z;
		++n;
	}
	if (n < minHeld)
		return false;
	const float pitch = Brain::LightTowerRange()
			* ai.GetTunable("apex_wall_pitch", TUNE_WALL_PITCH);
	at = AIFloat3(sx / float(n), 0.f, sz / float(n)) - gWallF * pitch;
	return OnMap(at);
}

// The held line on ground plainly ours: two slots held, not hot, and our
// influence at twice theirs. What fortifies the line (sensors, AA, a lathe)
// sites here -- the choke flickers hot and cold as the fight moves, and
// "quiet this second" sent builders 3,000 elmos to let go on arrival.
bool WallLineQuiet(AIFloat3& out at, int& out n)
{
	return WallLineHeld(at, n, 2)
			&& !Builder::SiteHot(at)
			&& (ai.GetAllyInflAt(at) > ai.GetEnemyInflAt(at) * 2.f);
}

// The line's anchor point itself, for the army to stand on.
bool WallLineAnchor(AIFloat3& out at)
{
	WallPrep();
	if (!gWallLineOk)
		return false;
	at = gWallA;
	return OnMap(at);
}

// Where the line's anchor stands on the home->enemy axis; -9 without a line.
float WallLineFwd()
{
	WallPrep();
	return gWallLineOk ? Military::ForwardFraction(gWallA) : -9.f;
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
	// In the line's cone, depth is measured against the LINE: signed
	// distance along the enemy axis, so the line's advance is what strands
	// a tower there, not the ring radius behind it.
	if (gWallLineOk) {
		AIFloat3 d = p - gPfMid;
		const float l = sqrt(d.SqLength2D());
		if ((l > 1.f)
			&& ((d.x * gWallF.x + d.z * gWallF.z) / l > 0.5f))
		{
			return (p.x - gWallA.x) * gWallF.x
					+ (p.z - gWallA.z) * gWallF.z;
		}
	}
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
	if (!gWallROk || (gWallP.length() == 0))
		return false;
	// The wall ahead of a tower is its NEAREST slot -- line or ring, the
	// section it belonged to. Held means a standing tower covers that slot.
	uint ni = 0;
	float nd = 1e12f;
	for (uint i = 0; i < gWallP.length(); ++i) {
		const float dd = p.distance2D(gWallP[i]);
		if (dd < nd) {
			nd = dd;
			ni = i;
		}
	}
	return !gWallOpen[ni];
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
