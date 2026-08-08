namespace Base {

// One base layout, shared by every rule that places a structure.
//
// What this replaces: three separate lattices -- BandSpot (nano rows plus eco
// flanks), ConvSpot (the converter block) and RearPos (converters, again) --
// each re-deriving its own axis from gHomePos and the enemy centroid, none
// aware of the others, and none asking whether anything can stand where it
// pointed. Everything else went out as a position plus a shake radius and the
// engine slid it anywhere inside that radius. There was no footprint, no rows
// and no lanes, which is why the radius could only ever trade sprawl against
// self-walling.
//
// The model here is the one a human uses: an anchored rectangle, structures on
// a grid pitch inside it, and walkways left empty at a fixed spacing so the
// base stays crossable however densely it fills in.

// --- the frame ---------------------------------------------------------------
//
// Anchor is the first factory once there is one, latched, because a factory is
// where the base actually centres; the commander's start position stands in
// until then. Axis points at the front, so the base grows BACKWARD, away from
// the fighting.
//
// Both are latched once set. An anchor or axis that keeps re-deriving is worse
// than a slightly wrong one -- it moves the whole grid out from under every
// structure already standing, and what was a lane becomes a row.
AIFloat3 gAnchor;
AIFloat3 gFwd;      // unit vector, anchor -> front
AIFloat3 gAcross;   // unit vector, perpendicular
bool gAnchorSet = false;
bool gAnchorFinal = false;
bool gAxisSet = false;
bool gPublished = false;
const int ANCHOR_DEADLINE = 3 * MINUTE;

// --- grid geometry -----------------------------------------------------------
//
// Lanes are defined in WORLD offsets rather than column indices, so that bands
// with different pitches still leave their gaps in the same places and the gaps
// line up into an actual corridor. The lane at lateral 0 is the axis itself:
// the road out of the factory toward the front.
// CELL is the pitch C++ snaps to, and every band pitch and band depth below is a
// whole multiple of it. That is load-bearing: IBuilderTask::Execute snaps EVERY
// non-fixed placement onto this grid, including the ones this file positions
// itself, so a band on some other pitch would have its own cells moved off it.
const float CELL       = 72.f;
const float LANE_PITCH = 720.f;   // spacing between walkways: one column in ten
const float LANE_HALF  = 72.f;    // half-width of a walkway
const float HALF_SPAN  = 1512.f;  // lateral cap; a bound, not a target
const float GRID_RANGE = 2200.f;  // beyond this a placement is not "in the base"

// Bands, measured backward from the anchor. Nanos sit closest so their assist
// radius covers the factory and the first eco rows; heavy energy sits furthest
// back, where a fusion going up does not take the rest of the base with it.
enum Kind { NANO = 0, ECO = 1, HEAVY = 2, KINDS = 3 };

// depth of the first row, row pitch, column pitch, half-footprint, row count.
// Filled in EnsureCols rather than at global scope: a global initialiser that
// fails to compile takes the whole variant down silently.
array<float> BAND_BACK;
array<float> BAND_ROW;
array<float> BAND_COL;
array<float> BAND_HALF;
array<int>   BAND_ROWS;

// How far off its grid cell the engine may settle a site and still count as
// having honoured the grid. Beyond this the cell is taken and we move on rather
// than let the site drift into a lane.
const float SNAP = 48.f;
// Second pass. Measured on Callisto: every placement failure was the terrain
// manager refusing the cell -- band=0, hot=0, terrain=11,328 on a player that
// placed NOTHING all game -- because a site had to exist within 48 elmos of the
// cell's exact centre, which rough ground rarely offers. A tidy grid that cannot
// be built on is worse than a slightly loose one that can, so a failed strict
// pass retries at two cells of slack before giving up. apexearth: "ive
// repeatedly seen us perform extra bad on maps where we don't have a lot of
// room."
const float SNAP_LOOSE = CELL * 2.f;

// Cells examined per placement. The scan restarts at zero every time so holes
// left by losses get refilled, which is the whole point of having a grid.
const int SCAN_MAX = 96;

// A handed-out cell is not blocked until its nanoframe exists, so two requests
// in the same few seconds would both pass FindBuildSiteNear on the same cell.
const int RESERVE_TTL = 90 * SECOND;

array<float> gColN;   // allowed lateral offsets, per kind, ordered outward
array<float> gColE;
array<float> gColH;
bool gColsBuilt = false;

array<int> gResIdx;    // reserved cells: kind * 100000 + index
array<int> gResFrame;

// Footprint, in band coordinates: how far back and how wide we have actually
// committed to. Grown only by slots we USED.
float gMinLat = 0.f, gMaxLat = 0.f, gMaxDepth = 0.f;
bool gGrown = false;

int gPlaced = 0;
// Why a placement failed, split by cause. One combined counter conflated four
// unrelated things and was read as "the base is full" when it may have been
// none of them -- apexearth: "noroom is wrong".
int gNoRoom = 0;      // scan exhausted: every reason below, summed
int gFailBand = 0;    // ran off the end of the band's rows
int gFailHot = 0;     // cells rejected by the threat veto
int gFailTerrain = 0; // terrain manager would not take the cell
int gFailBusy = 0;    // cell already reserved by an in-flight request
int gNextLog = 0;

float Abs(float v) { return (v < 0.f) ? -v : v; }

// Distance from a lateral offset to the nearest walkway centre.
float LaneGap(float u)
{
	const float k = u / LANE_PITCH;
	const int n = int((k >= 0.f) ? (k + .5f) : (k - .5f));
	return Abs(u - float(n) * LANE_PITCH);
}

bool InLane(float u, float half)
{
	return LaneGap(u) < (LANE_HALF + half);
}

// Lateral offsets a structure of this kind may occupy, ordered outward from the
// axis and alternating sides, with anything overlapping a walkway dropped.
void BuildCols(int kind, array<float>@ cols)
{
	cols.resize(0);
	const float pitch = BAND_COL[kind];
	const float half = BAND_HALF[kind];
	const int n = int(HALF_SPAN / pitch);
	for (int k = 0; k <= n; ++k) {
		for (int s = 0; s < 2; ++s) {
			if ((k == 0) && (s == 1))
				continue;
			const float u = float(k) * pitch * ((s == 0) ? 1.f : -1.f);
			if (InLane(u, half))
				continue;
			cols.insertLast(u);
		}
	}
}

void EnsureCols()
{
	if (gColsBuilt)
		return;
	gColsBuilt = true;
	BAND_BACK = {216.f, 576.f, 1440.f};
	BAND_ROW  = { 72.f,  72.f,  144.f};
	BAND_COL  = { 72.f,  72.f,  144.f};
	BAND_HALF = { 32.f,  40.f,   64.f};
	BAND_ROWS = {    4,    12,       5};
	BuildCols(NANO, @gColN);
	BuildCols(ECO, @gColE);
	BuildCols(HEAVY, @gColH);
	AiLog("apex: base grid cols nano=" + gColN.length()
		+ " eco=" + gColE.length() + " heavy=" + gColH.length());
}

uint ColCount(int kind)
{
	if (kind == NANO) return gColN.length();
	if (kind == ECO) return gColE.length();
	return gColH.length();
}

float ColAt(int kind, uint i)
{
	if (kind == NANO) return gColN[i];
	if (kind == ECO) return gColE[i];
	return gColH[i];
}

// Establish anchor and axis, latching each once it is real.
bool Frame()
{
	EnsureCols();
	if (!gAnchorSet) {
		if (Factory::gT1FacUnit !is null) {
			gAnchor = Factory::gT1FacUnit.GetPos(ai.frame);
			gAnchorSet = true;
		} else if (Builder::gHomeSet) {
			gAnchor = Builder::gHomePos;
			gAnchorSet = true;
		} else {
			return false;
		}
	} else if (!gAnchorFinal && (Factory::gT1FacUnit !is null)) {
		// Promote from the commander's start to the factory, once. Moving the
		// anchor after anything is standing would slide every row out from under
		// it, and what was a lane would become a row -- so the promotion is also
		// what makes the anchor final, and it is given a deadline in case no
		// factory ever appears.
		gAnchor = Factory::gT1FacUnit.GetPos(ai.frame);
	}
	if (!gAnchorFinal
			&& ((Factory::gT1FacUnit !is null) || (ai.frame >= ANCHOR_DEADLINE)))
		gAnchorFinal = true;

	if (!gAxisSet) {
		AIFloat3 toward;
		bool have = Front::FrontNear(gAnchor, toward);
		if (!have) {
			toward = aiEnemyMgr.GetEnemyPos();
			have = Builder::OnMap(toward);
		}
		if (!have)
			return false;
		AIFloat3 f = toward - gAnchor;
		if (f.SqLength2D() < NEAR_ZERO)
			return false;
		f.SafeNormalize2D();
		gFwd = f;
		gAcross = AIFloat3(-f.z, 0.f, f.x);
		gAxisSet = true;
		AiLog("apex: base frame anchor=" + int(gAnchor.x) + "," + int(gAnchor.z)
			+ " fwd=" + formatFloat(gFwd.x, "", 0, 2) + "," + formatFloat(gFwd.z, "", 0, 2));
	}

	// Hand the frame down to C++, which snaps every non-fixed placement onto it
	// -- including the ones stock task selection makes, which is the whole base
	// rather than the handful of structures this file positions itself. Held back
	// until the anchor is final: a grid that moves is worse than none, because
	// everything already standing is then off it.
	if (!gPublished && gAnchorFinal) {
		gPublished = true;
		ai.SetBaseGrid(gAnchor, gFwd, CELL, LANE_PITCH, LANE_HALF, GRID_RANGE);
		AiLog("apex: base grid published cell=" + int(CELL)
			+ " lane=" + int(LANE_PITCH) + "/" + int(LANE_HALF)
			+ " range=" + int(GRID_RANGE));
	}
	return true;
}

bool Ready() { return gAnchorSet && gAxisSet; }

// Band coordinates of a world position: how far BACK of the anchor, and how far
// to the side. Only meaningful once the frame is latched.
void Coords(const AIFloat3& in p, float& out depth, float& out lat)
{
	const float dx = p.x - gAnchor.x;
	const float dz = p.z - gAnchor.z;
	depth = -(dx * gFwd.x + dz * gFwd.z);
	lat = dx * gAcross.x + dz * gAcross.z;
}

bool CellPos(int kind, int index, AIFloat3& out cell)
{
	const uint cols = ColCount(kind);
	if (cols == 0)
		return false;
	const int row = index / int(cols);
	if (row >= BAND_ROWS[kind])
		return false;
	const float lat = ColAt(kind, uint(index) % cols);
	const float depth = BAND_BACK[kind] + float(row) * BAND_ROW[kind];
	cell = gAnchor - gFwd * depth + gAcross * lat;
	return true;
}

void Reserve(int kind, int index)
{
	const int key = kind * 100000 + index;
	for (uint i = 0; i < gResIdx.length(); ++i) {
		if (gResIdx[i] == key) {
			gResFrame[i] = ai.frame;
			return;
		}
	}
	gResIdx.insertLast(key);
	gResFrame.insertLast(ai.frame);
}

bool Reserved(int kind, int index)
{
	const int key = kind * 100000 + index;
	for (uint i = 0; i < gResIdx.length(); ++i) {
		if ((gResIdx[i] == key) && (ai.frame < gResFrame[i] + RESERVE_TTL))
			return true;
	}
	return false;
}

void SweepReserves()
{
	for (uint i = 0; i < gResIdx.length();) {
		if (ai.frame >= gResFrame[i] + RESERVE_TTL) {
			gResIdx.removeAt(i);
			gResFrame.removeAt(i);
		} else {
			++i;
		}
	}
}

void Grow(int kind, int index)
{
	const uint cols = ColCount(kind);
	if (cols == 0)
		return;
	const float lat = ColAt(kind, uint(index) % cols);
	const float depth = BAND_BACK[kind] + float(index / int(cols)) * BAND_ROW[kind];
	if (!gGrown) {
		gGrown = true;
		gMinLat = lat;
		gMaxLat = lat;
		gMaxDepth = depth;
		return;
	}
	if (lat < gMinLat) gMinLat = lat;
	if (lat > gMaxLat) gMaxLat = lat;
	if (depth > gMaxDepth) gMaxDepth = depth;
}

// The committed rectangle, in elmos squared. Reported rather than acted on: it
// is the measure of whether the layout is holding, and it can be read without a
// win rate.
float Area()
{
	return gGrown ? ((gMaxLat - gMinLat) * gMaxDepth) : 0.f;
}

bool Inside(const AIFloat3& in p)
{
	if (!Ready() || !gGrown)
		return false;
	float depth, lat;
	Coords(p, depth, lat);
	return (depth >= -BAND_BACK[NANO]) && (depth <= gMaxDepth + BAND_ROW[HEAVY])
		&& (lat >= gMinLat - LANE_PITCH) && (lat <= gMaxLat + LANE_PITCH);
}

// Is this position standing in a walkway? Only asked of things already known to
// be inside the footprint.
bool InLaneAt(const AIFloat3& in p)
{
	if (!Ready())
		return false;
	float depth, lat;
	Coords(p, depth, lat);
	return LaneGap(lat) < LANE_HALF;
}

// The grid cell this structure should go in, already resolved to a site the
// terrain manager says is buildable.
//
// The returned position is meant to be enqueued with a shake of ZERO. Shake
// exists to find any free spot near a guess; with a grid the spot is already
// known, and the task's own site search will settle on this exact one.
bool Spot(CCircuitUnit@ unit, CCircuitDef@ def, int kind, AIFloat3& out spot)
{
	if ((def is null) || !Frame())
		return false;
	SweepReserves();

	for (int pass = 0; pass < 2; ++pass) {
	const float snap = (pass == 0) ? SNAP : SNAP_LOOSE;
	for (int index = 0; index < SCAN_MAX; ++index) {
		AIFloat3 cell;
		if (!CellPos(kind, index, cell)) {
			if (pass == 0)
				++gFailBand;
			break;
		}
		if (Reserved(kind, index)) {
			++gFailBusy;
			continue;
		}
		if (!Builder::OnMap(cell)) {
			++gFailTerrain;
			continue;
		}
		if (Builder::ThreatFor(unit, cell) > Builder::CON_THREAT_VETO) {
			++gFailHot;
			continue;
		}
		const AIFloat3 site = ai.FindBuildSiteNear(def, cell, snap);
		if (!Builder::OnMap(site)) {
			++gFailTerrain;   // nothing can stand in this cell
			continue;
		}
		if (site.distance2D(cell) > snap) {
			++gFailTerrain;   // slid off the grid; treat the cell as taken
			continue;
		}
		Reserve(kind, index);
		Grow(kind, index);
		++gPlaced;
		spot = site;
		return true;
	}
	}
	++gNoRoom;
	return false;
}

// Can we still tech up?
//
// "No room to build a gantry" is the end state sprawl produces, and it was only
// ever visible as a build that quietly never happened. This asks the terrain
// manager the question directly -- is there a site for an advanced lab near the
// base, and how far out did it have to go to find one -- so the layout can be
// judged on the thing it is for rather than on a win rate.
const float TECH_PROBE_R = 1800.f;

CCircuitDef@ TechProbeDef()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(Factory::coralab);
	if (side == "legion")
		return ai.GetCircuitDef(Factory::legalab);
	return ai.GetCircuitDef(Factory::armalab);
}

void Update()
{
	if (!Frame())
		return;
	SweepReserves();
	if (ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 60 * SECOND;

	int techDist = -1;
	CCircuitDef@ probe = TechProbeDef();
	if (probe !is null) {
		const AIFloat3 site = ai.FindBuildSiteNear(probe, gAnchor, TECH_PROBE_R);
		if (Builder::OnMap(site))
			techDist = int(site.distance2D(gAnchor));
	}

	AIFloat3 blocked;
	AiLog(Factory::T() + "apex: base area=" + int(Area())
		+ " width=" + int(gMaxLat - gMinLat) + " depth=" + int(gMaxDepth)
		+ " placed=" + gPlaced + " noroom=" + gNoRoom
		+ " (band=" + gFailBand + " hot=" + gFailHot
		+ " terrain=" + gFailTerrain + " busy=" + gFailBusy + ")"
		+ " blocked=" + (ai.GetBlockedBuildPos(blocked) ? 1 : 0)
		+ " techroom=" + techDist);
}

}  // namespace Base
