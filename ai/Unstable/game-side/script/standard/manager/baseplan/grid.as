namespace Base {

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

void BuildOrder(int kind, array<int>@ ord, array<float>@ cols)
{
	ord.resize(0);
	array<float> key;
	const int rows = BAND_ROWS[kind];
	const float rowPitch = BAND_ROW[kind];
	for (int r = 0; r < rows; ++r) {
		const float depth = float(r) * rowPitch;
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
