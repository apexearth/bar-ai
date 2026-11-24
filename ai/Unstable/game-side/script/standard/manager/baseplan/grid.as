namespace Base {

float Abs(float v) { return (v < 0.f) ? -v : v; }

// apex_streets (his 11-22): 1 the street grid everywhere forward of the anchor; 2 a street only where it serves one of
// our ground plants (forward of it, on its column: "lanes are only useful if we have a factory in the back which needs
// to get out of the base"), laid on the 12-square block grid -- a block wide, its edges on the block lines from the
// map corner where every building's lattice is phased, so the blocks beside it stay whole ("if the lane itself is off
// by one or two in comparison to our grid, then that causes some pretty stiff friction")
const float BLOCK = 192.f;
int StreetsMode() { return int(ai.GetTunable("apex_streets", TUNE_STREETS) + .5f); }
float LanePitch() { return (StreetsMode() >= 2) ? BLOCK * 4.f : LANE_PITCH; }
AIFloat3 LaneOrigin()
{
	if (StreetsMode() < 2)
		return gAnchor;
	return AIFloat3(floor(gAnchor.x / BLOCK) * BLOCK + BLOCK * .5f, gAnchor.y,
			floor(gAnchor.z / BLOCK) * BLOCK + BLOCK * .5f);
}

// Distance from an offset -- lateral or depth, the lanes cross -- to the nearest
// walkway centre, the offsets measured from the anchor (Coords).
float LaneGap(float u)
{
	const float p = LanePitch();
	const float k = u / p;
	const int n = int((k >= 0.f) ? (k + .5f) : (k - .5f));
	return Abs(u - float(n) * p);
}
float LaneGapD(float depth)
{
	float d0, l0;
	Coords(LaneOrigin(), d0, l0);
	return LaneGap(depth - d0);
}
float LaneGapL(float lat)
{
	float d0, l0;
	Coords(LaneOrigin(), d0, l0);
	return LaneGap(lat - l0);
}

// apex_streets 2: our ground plants in base coordinates, refreshed every 2 s
array<float> gGroundD, gGroundL;
int gGroundAt = -1;
bool StreetNeeded(float depth, float lat)
{
	if (StreetsMode() < 2)
		return true;
	if (ai.frame >= gGroundAt) {
		gGroundAt = ai.frame + 2 * SECOND;
		gGroundD.resize(0);
		gGroundL.resize(0);
		for (uint i = 0; i < Factory::gFacUnits.length(); ++i) {
			CCircuitUnit@ f = Factory::gFacUnits[i];
			if ((f is null) || (f.circuitDef is null) || (Market::PlantClass(int(f.circuitDef.id)) != Market::PC_LAND))
				continue;
			float d, l;
			Coords(f.GetPos(ai.frame), d, l);
			gGroundD.insertLast(d);
			gGroundL.insertLast(l);
		}
	}
	const float p = LanePitch();
	for (uint i = 0; i < gGroundD.length(); ++i) {
		if ((depth <= gGroundD[i] + p) && (Abs(lat - gGroundL[i]) <= p))
			return true;
	}
	return false;
}

// Half-width of a walkway. A street exists so the biggest thing we field can
// walk down it, which is the question Lattice::AisleW already answers for the
// ground between two clusters -- so it is that number, not a second one. The
// fixed 72 this replaces gave a 144-elmo street to a 128-elmo hull: one hull
// wide, which is by AisleW's own reasoning a lane the pathfinder refuses under
// any crowding.
float LaneHalf()
{
	float h = Lattice::AisleW() * .5f;
	if (h < LANE_HALF_MIN)
		h = LANE_HALF_MIN;
	if (StreetsMode() >= 2)
		h = BLOCK * .5f * ceil(h / (BLOCK * .5f));   // whole blocks wide
	return h;
}

// The bands' own column/row drop: streets on every band under mode 1; under mode 2 the site tests (spot.as, C++)
// decide, since a street exists only near a ground plant
bool InLane(float u, float half)
{
	if (StreetsMode() >= 2)
		return false;
	return LaneGap(u) < (LaneHalf() + half);
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

void BuildOrder(int kind, array<int>@ ord, array<float>@ cols)
{
	ord.resize(0);
	array<float> key;
	const int rows = BAND_ROWS[kind];
	const float rowPitch = BAND_ROW[kind];
	for (int r = 0; r < rows; ++r) {
		const float depth = float(r) * rowPitch;
		// Rows are dropped for a cross-street exactly as columns are for a
		// walkway. Without this the slot is still offered and C++ pushes it out
		// of the lane onto its neighbour's ground, which is the sprawl the
		// lattice exists to stop.
		if (InLane(BAND_BACK[kind] + depth, BAND_HALF[kind]))
			continue;
		for (uint c = 0; c < cols.length(); ++c) {
			const float lat = cols[c];
			ord.insertLast(r * 1000 + int(c));
			key.insertLast(lat * lat + depth * depth);
		}
	}
	for (uint i = 0; i < ord.length(); ++i) {
		uint best = i;
		for (uint j = i + 1; j < ord.length(); ++j) {
			if (key[j] < key[best])
				best = j;
		}
		if (best != i) {
			const float tk = key[i]; key[i] = key[best]; key[best] = tk;
			const int to = ord[i]; ord[i] = ord[best]; ord[best] = to;
		}
	}
}

void EnsureCols()
{
	if (gColsBuilt)
		return;
	gColsBuilt = true;
	// Pitch is the FOOTPRINT of what stands in the band, in whole build cells --
	// the only pitch on which two of them touch. HEAVY is deliberately looser
	// than the reactor's own footprint; the site search closes any gap smaller
	// than the pitch by taking the nearest position the blocking map allows.
	BAND_BACK = {224.f, 576.f, 1440.f};
	BAND_ROW  = { 48.f,  64.f,  144.f};
	BAND_COL  = { 48.f,  64.f,  144.f};
	BAND_HALF = { 32.f,  40.f,   64.f};
	BAND_ROWS = {    4,    12,       5};
	gCursor   = {    0,     0,       0};
	BuildCols(NANO, @gColN);
	BuildCols(ECO, @gColE);
	BuildCols(HEAVY, @gColH);
	BuildOrder(NANO, @gOrdN, @gColN);
	BuildOrder(ECO, @gOrdE, @gColE);
	BuildOrder(HEAVY, @gOrdH, @gColH);
	AiLog("apex: base grid cols nano=" + gColN.length()
		+ " eco=" + gColE.length() + " heavy=" + gColH.length()
		+ " slots=" + gOrdN.length() + "/" + gOrdE.length() + "/" + gOrdH.length());
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

// Band coordinates of the index-th slot, in visit order.
bool SlotAt(int kind, int index, float& out lat, float& out depth)
{
	if (index < 0)
		return false;
	int code;
	if (kind == NANO) {
		if (uint(index) >= gOrdN.length()) return false;
		code = gOrdN[index];
	} else if (kind == ECO) {
		if (uint(index) >= gOrdE.length()) return false;
		code = gOrdE[index];
	} else {
		if (uint(index) >= gOrdH.length()) return false;
		code = gOrdH[index];
	}
	lat = ColAt(kind, uint(code % 1000));
	depth = BAND_BACK[kind] + float(code / 1000) * BAND_ROW[kind];
	return true;
}

// The axis is latched once, so a bad choice (water, a cliff face) makes the
// whole rectangle unbuildable permanently. Probe all four right-angle
// orientations and keep the front-derived one unless another is far better.
const int AXIS_PROBE_ROWS = 4;
const uint AXIS_PROBE_STEP = 3;

}  // namespace Base
