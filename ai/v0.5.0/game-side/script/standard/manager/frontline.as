namespace Front {

// Where our territory ends and the enemy's is about to begin: the outer
// perimeter of a LOW-bar territory field (ally-influence presence, not a
// "both sides present" or "field boundary" test -- neither has enough
// coverage to draw a line with), split by direction from our centroid to the
// enemy's so the part facing our own fog reads as BACK, not FRONT. With no
// enemy sighted yet there is no direction to split on, so the front reads
// UNKNOWN rather than guessed.

const float MIN_WIDTH = 80.f;
const float MAX_WIDTH = 2000.f;

// Territory is everything we meaningfully hold, not only where we are massed;
// a higher fraction of peak selects only the dense core and its edge sits
// behind our own army.
const float TERRITORY_FLOOR = 1.0f;
const float TERRITORY_FRAC = 0.03f;
// Enemy influence counts only what we have SEEN and peaks far below ally's, so
// it needs its own (relative, not absolute) bar or it reads zero everywhere.
const float FOE_FLOOR = 1.0f;
const float FOE_FRAC = 0.10f;

const float CHOKE_NEAR = 600.f;
// How much further than the closest front cell a cell may sit and still count
// as front; beyond this it is enemy-facing flank, not the line. Expressed as a
// fraction of our own territory radius R (ring of radius R about our centroid)
// rather than an absolute distance, because the arc half-angle
// acos(1 - band/R) depends only on band/R, not on distance to the enemy --
// an absolute band or a fraction of home-to-enemy separation would each cover
// a different arc as either side's holdings changed. 0.35 is +/-49 degrees;
// at 1.0 the arc was +/-90 and half the perimeter classified as front.
const float FRONT_BAND_FRAC = 0.35f;
const int RECLASSIFY = 10 * SECOND;
bool gClassifyPhased = false;
const int SEAM_N = 40;

// Blackboard keys for pooling the enemy bearing across the team.
const string TV_FOE_X = "apexFoeX";
const string TV_FOE_Z = "apexFoeZ";
const string TV_FOE_W = "apexFoeW";
// And for splitting the line into per-player sectors: each AI publishes where it
// lives, and a front cell belongs to whichever ally is nearest it.
const string TV_HOME_X = "apexHomeX";
const string TV_HOME_Z = "apexHomeZ";

enum Owner { EMPTY = 0, OURS = 1, CONTESTED = 2, THEIRS = 3 };
enum Edge { NONE = 0, FRONT = 1, BACK = 2 };

array<int> gIdx;
array<int> gOwner;
int gNextClassify = 0;
bool gGathered = false;

array<AIFloat3> gPerim;    // the whole ring around our territory
array<int> gEdge;          // parallel to gPerim: FRONT, BACK or NONE
array<bool> gMine;         // parallel to gPerim: this cell is THIS AI's to hold
array<float> gMateX;       // ally home positions, refreshed each Scan
array<float> gMateZ;
bool gSectored = false;    // false until at least one ally home is published
array<AIFloat3> gPrevDraw; // what we drew last pass, so it can be erased
array<float> gFoeSeen;     // persistent memory of where enemies have been
bool gFoeKnown = false;
AIFloat3 gOurMid;
AIFloat3 gFoeMid;
float gPresAlly = TERRITORY_FLOOR;
float gPresFoe = FOE_FLOOR;
int gDbgAlly = 0;
int gDbgFoe = 0;
bool gDrawn = false;
bool gChokeDrawn = false;

void Gather()
{
	if (gGathered)
		return;
	gGathered = true;
	gFoeSeen.resize(SEAM_N * SEAM_N);
	for (uint k = 0; k < gFoeSeen.length(); ++k)
		gFoeSeen[k] = 0.f;
	const int n = ai.GetChokePointCount();
	for (int i = 0; i < n; ++i) {
		const float w = ai.GetChokePointWidth(i);
		if ((w < MIN_WIDTH) || (w > MAX_WIDTH))
			continue;
		gIdx.insertLast(i);
		gOwner.insertLast(EMPTY);
	}
	AiLog("apex: frontline gathered " + gIdx.length() + "/" + n + " usable chokepoints");
}

AIFloat3 GridPos(int i, int j)
{
	AIFloat3 p;
	p.x = float(AiTerrainWidth()) * (float(i) + .5f) / float(SEAM_N);
	p.z = float(AiTerrainHeight()) * (float(j) + .5f) / float(SEAM_N);
	return p;
}

// TERRITORY IS WHAT WE HOLD, NOT WHERE THE ARMY IS STANDING.
//
// `ours[]` used to be `GetAllyInflAt(p) >= 3% of peak && > enemy influence`,
// and CircuitAI's influence map feeds AddMobileArmed into that alongside
// structures. So a squad raiding their base painted their ground as our
// territory, our perimeter followed the army rather than our holdings, and the
// mean FRONT edge came out at 0.87-0.96 of the way to the enemy centroid --
// past it entirely in a third of samples (apexearth, watching: "I see lines
// drawn through enemy territory").
//
// A structure cannot walk, so a structure is what owning ground means. Held
// cells are stamped from our own buildings and nothing else; an army excursion
// no longer moves the border, and TerritoryRadius becomes the real size of the
// base instead of most of the map.
//
// HOLD_CELLS is a grid-resolution choice, not a claim about the game: a
// building holds the cell it stands in and the ring of neighbours around it, so
// adjacent buildings merge into one region and an outlying mex stays the island
// it actually is. It scales with the map because the grid does.
const float HOLD_CELLS = 1.5f;

float HoldRadius()
{
	const float cw = float(AiTerrainWidth()) / float(SEAM_N);
	const float ch = float(AiTerrainHeight()) / float(SEAM_N);
	return sqrt(cw * cw + ch * ch) * HOLD_CELLS;
}

void StampHeld(array<bool>@ ours)
{
	for (uint k = 0; k < ours.length(); ++k)
		ours[k] = false;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	AIFloat3 mid;
	mid.x = w * .5f;
	mid.z = h * .5f;
	// One sweep of everything we own: the radius spans the map, so this is
	// "our structures", not a neighbourhood query.
	array<CCircuitUnit@>@ held = ai.GetOwnStructsNear(mid, sqrt(w * w + h * h));
	if (held is null)
		return;
	const float r = HoldRadius();
	const float cw = w / float(SEAM_N);
	const float ch = h / float(SEAM_N);
	for (uint u = 0; u < held.length(); ++u) {
		if (held[u] is null)
			continue;
		const AIFloat3 p = held[u].GetPos(ai.frame);
		if (!OnMap(p))
			continue;
		const int i0 = int((p.x - r) / cw);
		const int i1 = int((p.x + r) / cw);
		const int j0 = int((p.z - r) / ch);
		const int j1 = int((p.z + r) / ch);
		for (int i = (i0 < 0 ? 0 : i0); (i <= i1) && (i < SEAM_N); ++i) {
			for (int j = (j0 < 0 ? 0 : j0); (j <= j1) && (j < SEAM_N); ++j) {
				if (GridPos(i, j).distance2D(p) <= r)
					ours[i * SEAM_N + j] = true;
			}
		}
	}
}

int Classify(const AIFloat3& in pos)
{
	const float ally = ai.GetAllyInflAt(pos);
	const float foe = ai.GetEnemyInflAt(pos);
	if ((ally < gPresAlly) && (foe < gPresFoe))
		return EMPTY;
	if (ally > foe * 2.f)
		return OURS;
	if (foe > ally * 2.f)
		return THEIRS;
	return CONTESTED;
}

// SECTORS: which part of the team's line is THIS AI's to hold.
//
// Territory is ally-wide, so every AI computes the same perimeter and the same
// closest-approach trim, which without a split anchors every ally on whichever
// player sits furthest forward. A cell belongs to the ally whose home is
// nearest it -- a Voronoi split of the line over the team. Home positions
// aren't otherwise enumerated, so they're pooled the same way the enemy
// bearing is.
void ReadMates()
{
	gMateX.resize(0);
	gMateZ.resize(0);
	if (Builder::gHomeSet) {
		ai.PublishTeamValue(TV_HOME_X, Builder::gHomePos.x);
		ai.PublishTeamValue(TV_HOME_Z, Builder::gHomePos.z);
	}
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		const int id = int(mates[i]);
		if (id == ai.teamId)
			continue;   // ours is gHomePos; a mate entry for it would be a tie
		const float x = ai.ReadTeamValue(id, TV_HOME_X, -1.f);
		const float z = ai.ReadTeamValue(id, TV_HOME_Z, -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		gMateX.insertLast(x);
		gMateZ.insertLast(z);
	}
	// No mate has published yet, or we have no home of our own to compare
	// against: the whole line is ours, which is the pre-sector behaviour and the
	// right answer in a 1v1.
	gSectored = Builder::gHomeSet && (gMateX.length() > 0);
}

bool FoeKnown()
{
	return gFoeKnown;
}

// The REMEMBERED enemy centre. gFoeSeen accumulates sightings and decays at
// 0.995 a scan, so this is a far steadier bearing than aiEnemyMgr.GetEnemyPos():
// a raid standing in our base swings the live centroid most of the way home and
// moves this barely at all.
bool FoeMid(AIFloat3& out at)
{
	if (!gFoeKnown)
		return false;
	at = gFoeMid;
	return OnMap(at);
}

bool Mine(const AIFloat3& in p)
{
	if (!gSectored)
		return true;
	const float own = p.distance2D(Builder::gHomePos);
	for (uint i = 0; i < gMateX.length(); ++i) {
		const float dx = p.x - gMateX[i];
		const float dz = p.z - gMateZ[i];
		if (sqrt(dx * dx + dz * dz) < own)
			return false;
	}
	return true;
}

// The radius of what we hold: mean distance from our centroid to the perimeter
// this scan found. Declared after gPerim/gOurMid because a global read above its
// own declaration is a `No matching symbol` that disables the whole variant.
float TerritoryRadius()
{
	if (gPerim.length() == 0)
		return 0.f;
	float sum = 0.f;
	for (uint k = 0; k < gPerim.length(); ++k)
		sum += gPerim[k].distance2D(gOurMid);
	return sum / float(gPerim.length());
}

float FrontBand()
{
	float b = TerritoryRadius()
			* ai.GetTunable("apex_front_band_frac", TUNE_FRONT_BAND_FRAC);
	// A band under the grid's own resolution cannot mean anything: the perimeter
	// is quantised at one cell, so one cell diagonal is the floor.
	const float cw = float(AiTerrainWidth()) / float(SEAM_N);
	const float ch = float(AiTerrainHeight()) / float(SEAM_N);
	const float least = sqrt(cw * cw + ch * ch);
	return (b < least) ? least : b;
}

void Scan()
{
	gPerim.resize(0);
	gEdge.resize(0);
	gMine.resize(0);
	gDbgAlly = 0;
	gDbgFoe = 0;
	ReadMates();

	// SAMPLE EACH CELL ONCE. The 1600-cell grid used to be read three times
	// over -- both fields for the max pass, the enemy field again in the main
	// pass, and the ally field again inside the ours[] test -- about 6,400
	// engine influence reads per rescan, every ten seconds, per AI instance.
	// The values cannot change inside one Scan, so they are sampled here and
	// read from the arrays below.
	array<float> cellAlly(SEAM_N * SEAM_N);
	array<float> cellFoe(SEAM_N * SEAM_N);
	float maxAlly = 0.f, maxFoe = 0.f;
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const AIFloat3 p = GridPos(i, j);
			const float a = ai.GetAllyInflAt(p);
			const float f = ai.GetEnemyInflAt(p);
			cellAlly[i * SEAM_N + j] = a;
			cellFoe[i * SEAM_N + j] = f;
			if (a > maxAlly) maxAlly = a;
			if (f > maxFoe) maxFoe = f;
		}
	}
	gPresAlly = maxAlly * TERRITORY_FRAC;
	if (gPresAlly < TERRITORY_FLOOR) gPresAlly = TERRITORY_FLOOR;
	gPresFoe = maxFoe * FOE_FRAC;
	if (gPresFoe < FOE_FLOOR) gPresFoe = FOE_FLOOR;

	array<bool> ours(SEAM_N * SEAM_N);
	// Held ground, stamped from our own buildings -- see StampHeld.
	StampHeld(ours);
	float ox = 0.f, oz = 0.f, ow = 0.f;
	float fx = 0.f, fz = 0.f, fw = 0.f;
	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const int me = i * SEAM_N + j;
			const AIFloat3 p = GridPos(i, j);
			const float fv = cellFoe[me];
			// Ground they hold more strongly than we do is not ours, however
			// many of our buildings stand on it -- that is the state a base
			// being overrun is actually in.
			if (ours[me] && (fv > cellAlly[me]))
				ours[me] = false;
			const bool a = ours[me];
			if (a) {
				++gDbgAlly;
				ox += p.x; oz += p.z; ow += 1.f;
			}
			// Enemy sightings are REMEMBERED, not sampled. A raid that passes
			// through is gone from the influence map seconds later, but the fact
			// that their territory lies that way does not stop being true.
			if (fv >= gPresFoe) {
				++gDbgFoe;
				gFoeSeen[me] += 1.f;
			} else {
				gFoeSeen[me] *= 0.995f;
			}
			if (gFoeSeen[me] > 0.5f) {
				fx += p.x * gFoeSeen[me];
				fz += p.z * gFoeSeen[me];
				fw += gFoeSeen[me];
			}
		}
	}
	if (ow > 0.f) {
		gOurMid.x = ox / ow;
		gOurMid.z = oz / ow;
	}
	// Share the enemy bearing across the team: each AI's influence map holds
	// only what that AI has itself seen, so a rear player alone would read no
	// enemy and no front at all, even though a forward teammate's sighting is
	// just as true for it.
	if (fw > 0.f) {
		ai.PublishTeamValue(TV_FOE_X, fx / fw);
		ai.PublishTeamValue(TV_FOE_Z, fz / fw);
		ai.PublishTeamValue(TV_FOE_W, fw);
	}
	float tx = 0.f, tz = 0.f, tw = 0.f;
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		const int id = int(mates[i]);
		const float w = ai.ReadTeamValue(id, TV_FOE_W, 0.f);
		if (w <= 0.f)
			continue;
		tx += ai.ReadTeamValue(id, TV_FOE_X, 0.f) * w;
		tz += ai.ReadTeamValue(id, TV_FOE_Z, 0.f) * w;
		tw += w;
	}
	gFoeKnown = (tw > 0.f);
	if (gFoeKnown) {
		gFoeMid.x = tx / tw;
		gFoeMid.z = tz / tw;
		// Sightings on our side of the line to their base are raids, not their
		// territory; left in, a raid makes our own base read as the front.
		const AIFloat3 anchor = FoeAnchor();
		if (Builder::gHomeSet && OnMap(anchor)
				&& (gFoeMid.distance2D(Builder::gHomePos) < gFoeMid.distance2D(anchor)))
			gFoeMid = anchor;
	}

	for (int i = 0; i < SEAM_N; ++i) {
		for (int j = 0; j < SEAM_N; ++j) {
			const int me = i * SEAM_N + j;
			if (!ours[me])
				continue;
			bool edge = false;
			for (int di = -1; (di <= 1) && !edge; ++di) {
				for (int dj = -1; (dj <= 1) && !edge; ++dj) {
					const int ni = i + di;
					const int nj = j + dj;
					if ((ni < 0) || (nj < 0) || (ni >= SEAM_N) || (nj >= SEAM_N))
						continue;   // the map edge is not a front
					if (!ours[ni * SEAM_N + nj])
						edge = true;
				}
			}
			if (!edge)
				continue;
			const AIFloat3 p = GridPos(i, j);
			gPerim.insertLast(p);
			const bool mine = Mine(p);
			gMine.insertLast(mine);
			if (!gFoeKnown) {
				gEdge.insertLast(NONE);
				continue;
			}
			// Facing them is necessary but not sufficient -- the far flank of a
			// large territory faces the enemy too and is nowhere near them, so
			// the trim below also requires closeness. Measured from OUR OWN home
			// for cells that are ours, not the team centroid: the team centroid
			// is the same point for every ally, so a flank player's whole border
			// would project backwards along the team bearing and read as back
			// line, leaving it with no front of its own.
			const float rx = (mine && Builder::gHomeSet) ? Builder::gHomePos.x : gOurMid.x;
			const float rz = (mine && Builder::gHomeSet) ? Builder::gHomePos.z : gOurMid.z;
			const float facing = (p.x - rx) * (gFoeMid.x - rx)
					+ (p.z - rz) * (gFoeMid.z - rz);
			if (facing <= 0.f) {
				gEdge.insertLast(BACK);
				continue;
			}
			gEdge.insertLast(FRONT);
		}
	}

	// Trim the enemy-facing arc down to the part actually near them, trimmed
	// PER SECTOR: one closest-approach figure for the whole team would keep only
	// the arc in front of whichever ally stands furthest forward and demote
	// every other player's frontage to back line.
	if (!gFoeKnown)
		return;
	float closeMine = -1.f;
	float closeTeam = -1.f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;
		const float d = gPerim[k].distance2D(gFoeMid);
		if ((closeTeam < 0.f) || (d < closeTeam))
			closeTeam = d;
		if (gMine[k] && ((closeMine < 0.f) || (d < closeMine)))
			closeMine = d;
	}
	const float band = FrontBand();
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;
		const float ref = (gMine[k] && (closeMine >= 0.f)) ? closeMine : closeTeam;
		if (gPerim[k].distance2D(gFoeMid) > ref + band)
			gEdge[k] = BACK;
	}
}

// Mean projection of an edge kind onto the direction from our territory centroid
// toward the enemy, in elmos. FRONT must come out positive and BACK negative.
// Projected from the team centroid, not each AI's own base -- the perimeter is
// ally-wide, so measuring from one player's base can put the team's far edge
// further from it than the near edge, which isn't a geometry defect.
float MeanDist(int kind)
{
	const float dx = gFoeMid.x - gOurMid.x;
	const float dz = gFoeMid.z - gOurMid.z;
	const float len = sqrt(dx * dx + dz * dz);
	if (len < 1.f)
		return 0.f;
	float sum = 0.f;
	uint n = 0;
	for (uint k = 0; k < gEdge.length(); ++k) {
		if (gEdge[k] != kind)
			continue;
		sum += ((gPerim[k].x - gOurMid.x) * dx + (gPerim[k].z - gOurMid.z) * dz) / len;
		++n;
	}
	return (n == 0) ? 0.f : (sum / float(n));
}

uint CountEdge(int kind)
{
	uint n = 0;
	for (uint k = 0; k < gEdge.length(); ++k) {
		if (gEdge[k] == kind)
			++n;
	}
	return n;
}

uint CountOf(int owner)
{
	uint n = 0;
	for (uint k = 0; k < gOwner.length(); ++k) {
		if (gOwner[k] == owner)
			++n;
	}
	return n;
}

// The defense zone, as two rings around home. Inner: the C++ base-defence
// range -- DefendTask's fight-at-any-odds boost and the defence builder both
// honor it, so this is the ground the army actually treats as home. Outer:
// the incoming-push alarm radius (apex_push_notice_r). Same queue, same
// erase-and-repaint cadence as the front line, same 60s-eraser window.
int gNextZoneDraw = 0;
array<AIFloat3> gZoneDrawn;

// Drive the C++ ring from the built base. The engine froze it at
// clamp(mapDiagonal*0.3, base_rad) on config load -- a 1400-elmo circle on a
// 1v1 map whatever stood there, and everything inside is fight-at-any-odds
// ground for DefendTask. DefenceData still clamps to config base_rad, so
// this can only move within [800, 1400].
int gNextZoneSet = 0;

void ApplyDefenseZone()
{
	if (ai.GetTunable("apex_defzone_dynamic", TUNE_DEFZONE_DYNAMIC) <= 0.f)
		return;
	if ((ai.frame < gNextZoneSet) || (Military::gBaseExtent <= 1.f))
		return;
	gNextZoneSet = ai.frame + 30 * SECOND;
	aiMilitaryMgr.SetBaseDefRange(Military::gBaseExtent
			+ ai.GetTunable("apex_defzone_pad", TUNE_DEFZONE_PAD));
}

void DrawDefenseZone()
{
	if (ai.GetTunable("apex_draw_defzone", TUNE_DRAW_DEFZONE) <= 0.f)
		return;
	if ((ai.frame < gNextZoneDraw) || !Builder::gHomeSet)
		return;
	gNextZoneDraw = ai.frame + 20 * SECOND;
	for (uint i = 0; i < gZoneDrawn.length(); ++i)
		Enqueue(gZoneDrawn[i], gZoneDrawn[i]);   // erase the last paint
	gZoneDrawn.resize(0);
	array<float> radii = {aiMilitaryMgr.GetBaseDefRange(),
			ai.GetTunable("apex_incoming_notice_r", TUNE_INCOMING_NOTICE_R)};
	const AIFloat3 home = Builder::gHomePos;
	for (uint r = 0; r < radii.length(); ++r) {
		if (radii[r] <= 1.f)
			continue;
		const int SEGS = 24;
		AIFloat3 prev;
		bool prevOk = false;
		for (int s = 0; s <= SEGS; ++s) {
			const float a = 6.2831853f * float(s) / float(SEGS);
			AIFloat3 pt = home;
			pt.x += cos(a) * radii[r];
			pt.z += sin(a) * radii[r];
			const bool ok = OnMap(pt);
			if (ok && prevOk) {
				Enqueue(prev, pt);
				gZoneDrawn.insertLast(prev);
			}
			prev = pt;
			prevOk = ok;
		}
	}
}

void Update()
{
	{ double _t = Perf::T0(); Gather(); Perf::Add("front.gather", _t); }
	{ double _t = Perf::T0(); ApplyDefenseZone(); Perf::Add("front.defzone", _t); }
	{ double _t = Perf::T0(); DrawFrontLine(); Perf::Add("front.drawline", _t); }
	{ double _t = Perf::T0(); DrawDefenseZone(); Perf::Add("front.drawzone", _t); }
	{ double _t = Perf::T0(); DrawDiagnostics(); Perf::Add("front.drawdiag", _t); }
	{ double _t = Perf::T0(); PumpDraw(); Perf::Add("front.pumpdraw", _t); }   // every tick, not every rescan -- see DRAW_PER_TICK
	if (ai.frame < gNextClassify)
		return;
	// PHASE THE RESCAN PER INSTANCE. AiUpdate's own offset is the skirmish AI
	// id, a handful of frames, so in an 8v8 all eight instances ran this sweep
	// within a quarter of a second of each other -- one synchronised spike
	// every ten seconds rather than eight small ones spread through it. Same
	// period and same work; only which frame it lands on changes.
	if (!gClassifyPhased) {
		gClassifyPhased = true;
		gNextClassify = ai.frame + (ai.teamId % 10) * (RECLASSIFY / 10);
		return;
	}
	gNextClassify = ai.frame + RECLASSIFY;

	{ double _t = Perf::T0(); Scan(); Perf::Add("front.scan", _t); }
	for (uint k = 0; k < gIdx.length(); ++k)
		gOwner[k] = Classify(ai.GetChokePointPos(gIdx[k]));

	array<AIFloat3> _gates;
	AiLog("apex: frontline perim=" + gPerim.length()
			+ " gates=" + GateChokes(_gates)
			+ " front=" + CountEdge(FRONT) + " back=" + CountEdge(BACK)
			+ " mine=" + MineEdge(FRONT) + " sectors=" + (gSectored ? int(gMateX.length()) + 1 : 1)
			+ " foeKnown=" + (gFoeKnown ? 1 : 0)
			+ " cAlly=" + gDbgAlly + " cFoe=" + gDbgFoe
			+ " bar=" + int(gPresAlly) + "/" + int(gPresFoe)
			+ " R=" + int(TerritoryRadius()) + " band=" + int(FrontBand())
			+ " ourMid=" + int(gOurMid.x) + "," + int(gOurMid.z)
			+ " foeMid=" + int(gFoeMid.x) + "," + int(gFoeMid.z)
			+ " lane=" + int(aiSetupMgr.GetLanePos().x) + "," + int(aiSetupMgr.GetLanePos().z)
			+ " frontD=" + int(MeanDist(FRONT)) + " backD=" + int(MeanDist(BACK)));

	// frontPos is published by Posture::UpdateLanePos, which vets the point for
	// direction, on-map and stickiness. This function ran more often and with none
	// of those checks, so whichever it wrote last is what the army got.

	Draw();
}

// Where the front should be before anyone has seen anything, from start-box
// geometry alone. CSetupManager already derives this: it spreads the allies
// along a line taken from the start-box geometry and hands each AI its own
// slot as lanePos, a per-player share of that midline rather than one point
// the whole team would crowd.
bool LaneFront(AIFloat3& out spot)
{
	const AIFloat3 lane = aiSetupMgr.GetLanePos();
	if (!ai.IsPosOnMap(lane))
		return false;
	spot = lane;
	return true;
}

// Nearest point on the front to `from`. Falls back to the start-box lane while
// no enemy has been seen. Tries our own sector first -- nearest-cell over the
// whole team line can pick an ally's frontage once the trim has demoted ours
// -- and only falls through to the team line if we own no front cell at all.
bool FrontNear(const AIFloat3& in from, AIFloat3& out spot)
{
	if (!gFoeKnown)
		return LaneFront(spot);
	for (int pass = 0; pass < 2; ++pass) {
		float best = -1.f;
		for (uint k = 0; k < gPerim.length(); ++k) {
			if (gEdge[k] != FRONT)
				continue;
			if ((pass == 0) && !gMine[k])
				continue;
			const float d = gPerim[k].distance2D(from);
			if ((best < 0.f) || (d < best)) {
				best = d;
				spot = gPerim[k];
			}
		}
		if (best >= 0.f)
			return true;
	}
	return false;
}

// A front cell that also sits in a corridor: the best metal-per-tower there is.
bool FrontChoke(const AIFloat3& in from, AIFloat3& out spot)
{
	float best = -1.f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if ((gEdge[k] != FRONT) || !gMine[k])
			continue;   // an ally's corridor is an ally's to hold
		for (uint c = 0; c < gIdx.length(); ++c) {
			const AIFloat3 cp = ai.GetChokePointPos(gIdx[c]);
			if (cp.distance2D(gPerim[k]) > CHOKE_NEAR)
				continue;
			const float d = cp.distance2D(from);
			if ((best < 0.f) || (d < best)) {
				best = d;
				spot = cp;
			}
		}
	}
	return best >= 0.f;
}

// IS THIS SPOT A DOORWAY, and where does the ground behind it lie? apexearth
// 2026-08-19: "identify where the chokepoint is and make defenses right behind
// it... kill the enemies in a chokepoint." A tower covering a corridor is worth
// several covering open ground, because everything that comes through has to
// come through there.
//
// FrontChoke above computed exactly this and was never called by anything.
bool ChokeAt(const AIFloat3& in pos, AIFloat3& out cp)
{
	float best = -1.f;
	for (uint c = 0; c < gIdx.length(); ++c) {
		const AIFloat3 p = ai.GetChokePointPos(gIdx[c]);
		if (!OnMap(p))
			continue;
		const float d = p.distance2D(pos);
		if ((d <= CHOKE_NEAR) && ((best < 0.f) || (d < best))) {
			best = d;
			cp = p;
		}
	}
	return best >= 0.f;
}

// A step back from the doorway, toward our own ground: the gun sits behind the
// gap and shoots into it, rather than standing in it and being walked over.
bool BehindChoke(const AIFloat3& in cp, float back, AIFloat3& out at)
{
	if (!Builder::gHomeSet)
		return false;
	AIFloat3 toHome = Builder::gHomePos - cp;
	const float len = sqrt(toHome.SqLength2D());
	if (len < 1.f)
		return false;
	toHome *= (1.f / len);
	at = cp + toHome * back;
	return OnMap(at);
}

// THE DOORWAYS OF OUR TERRITORY. apexearth 2026-08-29: "We want to gain
// control of mexes and then defend chokepoints ahead of where the mexes are.
// We want to prevent the enemy from getting in there." A gate is a choke whose
// home side is ours and whose far side is not: the corridor an attack on our
// ground has to come through. Each is returned a step behind the gap, toward
// home, so the gun shoots into the doorway rather than standing in it. The
// sample step is HoldRadius() -- the territory grid's own resolution, so the
// two probes straddle the door at the same scale ownership is known at.
// The gate test with the choke INDEX kept, for callers that need the gap's
// own geometry (the teeth line reads GetChokePointEnds).
uint GateChokeIdxs(array<int>& out idxs)
{
	idxs.resize(0);
	if (!Builder::gHomeSet)
		return 0;
	const float step = HoldRadius();
	for (uint c = 0; c < gIdx.length(); ++c) {
		const AIFloat3 cp = ai.GetChokePointPos(gIdx[c]);
		if (!OnMap(cp))
			continue;
		AIFloat3 toHome = Builder::gHomePos - cp;
		const float len = sqrt(toHome.SqLength2D());
		if (len < 1.f)
			continue;
		toHome *= (1.f / len);
		AIFloat3 pBack = cp + toHome * step;
		AIFloat3 pFwd = cp - toHome * step;
		if (!OnMap(pBack) || !OnMap(pFwd))
			continue;
		if ((Classify(pBack) != OURS) || (Classify(pFwd) == OURS))
			continue;
		idxs.insertLast(gIdx[c]);
	}
	return idxs.length();
}

uint GateChokes(array<AIFloat3>& out gates)
{
	gates.resize(0);
	if (!Builder::gHomeSet)
		return 0;
	const float step = HoldRadius();
	const float back = 180.f;
	for (uint c = 0; c < gIdx.length(); ++c) {
		const AIFloat3 cp = ai.GetChokePointPos(gIdx[c]);
		if (!OnMap(cp))
			continue;
		AIFloat3 toHome = Builder::gHomePos - cp;
		const float len = sqrt(toHome.SqLength2D());
		if (len < 1.f)
			continue;
		toHome *= (1.f / len);
		AIFloat3 pBack = cp + toHome * step;
		AIFloat3 pFwd = cp - toHome * step;
		if (!OnMap(pBack) || !OnMap(pFwd))
			continue;
		if ((Classify(pBack) != OURS) || (Classify(pFwd) == OURS))
			continue;
		AIFloat3 at = cp + toHome * back;
		if (!OnMap(at))
			at = cp;
		gates.insertLast(at);
	}
	return gates.length();
}

// The durable "where the enemy lives" anchor for geometric site tests: the
// centre of their known STRUCTURES, and until one has been seen the mirror
// of our own start. Not presence (GetEnemyPos walks home with their army)
// and not the sighting memory (gFoeMid: the first enemy ever seen is a raid
// inside our base, and the anchor landed on its corpses and stayed there,
// refusing every mex spot beyond them). Function accessor so include order
// cannot break a global read.
AIFloat3 gFoeAnchorPos;
int gFoeAnchorAt = -1;
AIFloat3 FoeAnchor()
{
	// Both enemy reads walk every known enemy; asked per candidate site.
	if (gFoeAnchorAt != ai.frame) {
		gFoeAnchorAt = ai.frame;
		gFoeAnchorPos = FoeAnchorRead();
	}
	return gFoeAnchorPos;
}

AIFloat3 FoeAnchorRead()
{
	if (aiEnemyMgr.GetEnemyStructCost() > 0.f) {
		const AIFloat3 s = aiEnemyMgr.GetEnemyStructPos();
		if (OnMap(s))
			return s;
	}
	// Their start boxes are where they are until a structure says otherwise;
	// the point mirror pointed at the wrong corner on diagonal-start maps.
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	if (OnMap(box))
		return box;
	if (Builder::gHomeSet) {
		return AIFloat3(float(AiTerrainWidth()) - Builder::gHomePos.x, 0.f,
				float(AiTerrainHeight()) - Builder::gHomePos.z);
	}
	return aiEnemyMgr.GetEnemyPos();
}

uint MineEdge(int kind)
{
	uint n = 0;
	for (uint k = 0; k < gEdge.length(); ++k) {
		if ((gEdge[k] == kind) && gMine[k])
			++n;
	}
	return n;
}

uint FrontSize() { return CountEdge(FRONT); }
bool IsFrontKnown() { return gFoeKnown; }

// ---------------------------------------------------------------------------
// Debug overlay. Map LINES, not points. A point is a PING -- it fires an alert
// and a minimap flash -- which at this density is unreadable. Lines just draw.
// Allies and spectators see these. Off for anything but a watched game.
const bool DRAW = false;  // ON draws real map markers -- allies see them

// The server silently drops map-draw commands once 25 arrive with under 50ms
// between each (GameServer.cpp NETMSG_MAPDRAW: `mapDrawTimings[a].second > 25
// -> break`), so drawing everything in one burst per rescan loses most of it
// with no error. Queued and metered instead: a small batch per tick, so the
// gap between ticks keeps the server's consecutive-command count clear.
// AiUpdate's tick is 1 game second but the server's window is REAL time, so at
// high sim speed consecutive ticks can still share one 50ms window -- keep the
// batch small enough to stay under 25 even then.
const uint DRAW_PER_TICK = 8;
array<AIFloat3> gQueueA;
array<AIFloat3> gQueueB;   // == A means erase-at-A rather than line A->B

void Enqueue(const AIFloat3& in a, const AIFloat3& in b)
{
	gQueueA.insertLast(a);
	gQueueB.insertLast(b);
}

void PumpDraw()
{
	uint sent = 0;
	while ((gQueueA.length() > 0) && (sent < DRAW_PER_TICK)) {
		if (gQueueA[0] == gQueueB[0])
			ai.DrawErase(gQueueA[0]);
		else
			ai.DrawLine(gQueueA[0], gQueueB[0]);
		gQueueA.removeAt(0);
		gQueueB.removeAt(0);
		++sent;
	}
}

// Draws the computed front on the map: segments between consecutive points of
// Military::FrontCurve, the influence crossing lane by lane. Redrawn on a slow
// cadence -- BAR's own auto-mapmark-eraser widget removes every mark after 60
// seconds, so this repaints inside that window rather than accumulating.
int gNextFrontDraw = 0;
array<AIFloat3> gFrontDrawn;

void DrawFrontLine()
{
	// OFF BY DEFAULT because this ships. Tunables resolve through
	// GetRulesParamFloat, which only dev_tunables.lua in BAR.sdd ever sets, and
	// multiplayer plays the rapid packages -- so a default of 1 meant every
	// hosted game drew on the map for human allies who never asked for it.
	// Opt in with --modoption apex_draw_front=1 or the dashboard toggle.
	if (ai.GetTunable("apex_draw_front", TUNE_DRAW_FRONT) <= 0.f)
		return;
	if (ai.frame < gNextFrontDraw)
		return;
	gNextFrontDraw = ai.frame + 20 * SECOND;

	for (uint i = 0; i < gFrontDrawn.length(); ++i)
		Enqueue(gFrontDrawn[i], gFrontDrawn[i]);   // erase the last one
	gFrontDrawn.resize(0);

	array<AIFloat3> line;
	if (!Military::FrontCurve(line) || (line.length() < 2))
		return;
	// THE LINE ENDS WHERE IT RUNS OUT, IT DOES NOT WRAP ROUND THE BACK.
	//
	// FrontCurve emits only the contested bearings, so the arc has gaps wherever
	// a ray met nobody or walked off the map. Joining every consecutive pair
	// regardless would draw a chord straight across our own half between the
	// two ends of the arc. Neighbouring bearings sit one ring-step apart;
	// anything much wider than that is the gap, not a neighbour -- break the
	// polyline there instead.
	const float step = 6.2831853f / float(Military::FRONT_RAYS);
	for (uint i = 1; i < line.length(); ++i) {
		if (!OnMap(line[i - 1]) || !OnMap(line[i]))
			continue;
		const float r = line[i].distance2D(Military::gFrontHome);
		if (line[i - 1].distance2D(line[i]) > (r * step * 2.5f))
			continue;   // the arc ended here
		Enqueue(line[i - 1], line[i]);
		gFrontDrawn.insertLast(line[i - 1]);
	}
}

void Draw()
{
	if (!DRAW)
		return;

	// ONE AI draws. Ally influence is ally-wide, so every teammate computes
	// virtually the same perimeter, and DeletePointsAndLines erases marks at a
	// position regardless of who drew them -- multiple drawers would erase each
	// other's lines.
	if (ai.teamId != Factory::ElectorTeamId())
		return;

	// A rescan replaces the queue outright; a backlog of stale segments is worse
	// than a gap, and the 60s auto-eraser cleans up anything left behind.
	gQueueA.resize(0);
	gQueueB.resize(0);
	if (gDrawn) {
		for (uint k = 0; k < gPrevDraw.length(); ++k)
			Enqueue(gPrevDraw[k], gPrevDraw[k]);
	}
	gPrevDraw.resize(0);

	// Join each front cell to its TWO nearest front neighbours. Linking every
	// pair within range drew a mesh of four-plus lines per cell; two gives a
	// contour.
	const float span = float(AiTerrainWidth()) / float(SEAM_N) * 1.6f;
	for (uint k = 0; k < gPerim.length(); ++k) {
		if (gEdge[k] != FRONT)
			continue;   // the back is a danger zone, but it is not the front
		int drawn = 0;
		for (uint m = 0; (m < gPerim.length()) && (drawn < 2); ++m) {
			if ((m == k) || (gEdge[m] != FRONT))
				continue;
			if (gPerim[k].distance2D(gPerim[m]) > span)
				continue;
			Enqueue(gPerim[k], gPerim[m]);
			++drawn;
		}
		gPrevDraw.insertLast(gPerim[k]);
	}
	gDrawn = true;

	// Chokepoints must be REDRAWN, not drawn once: BAR's auto-mapmark-eraser
	// widget (eraseTime = 60) deletes every mark a minute after it appears.
	for (uint k = 0; k < gIdx.length(); ++k) {
		AIFloat3 e1, e2;
		if (ai.GetChokePointEnds(gIdx[k], e1, e2))
			Enqueue(e1, e2);
	}
}

}  // namespace Front
