namespace Market {

// ROWS OF ONE KIND (TUNE_ROW_LAYOUT; his 10-20: "dense, no spacing, eco block scaling in one direction ... almost
// all build power comes from the nano turrets", and "snapping to nearby same-size buildings"). Each def had its own
// lattice phased from the map's corner, so where a 3-cell turret block met a 5-cell fusion block a strip of 1-4
// squares was left: 191 such gaps against 555 flush in his game, and the kin-first flush pass did not close them.
// Here the eco ground behind the anchor is laid out in rows across the back axis, one def to a row, each row as deep
// as its def's pitch and flush against the row before it, so two rows meet on one straight line whatever their
// footprints. An eco row opens only within a turret's reach of a turret row, opening one first when it would not.
// The cell is the request's exact site (IUnitTask.SetExactSite); a cell the engine refuses is skipped.

const float ROW_SPAN = 400.f;    // lateral half-width of a row, elmos: a block about as wide as a turret row reaches, growing back
const float ROW_START = 160.f;   // depth of the first row behind the anchor, elmos
const int ROW_SCAN = 40;         // cells tried per ask

bool RowLayoutOn() { return ai.GetTunable("apex_row_layout", TUNE_ROW_LAYOUT) > 0.f; }

array<int> gRowDef;
array<float> gRowDepth;    // front edge, elmos behind the origin
array<float> gRowPitch;
array<bool> gRowFull;
float gRowBack = 0.f;      // back edge of the last row
bool gRowFrameSet = false;
AIFloat3 gRowOrigin, gRowBackDir, gRowAcross;
int gRowsHanded = 0, gRowsRefused = 0, gRowLogAt = 0;

// The eco families a row takes: generators, converters and stores, and the turrets that work them.
bool RowFamily(int d)
{
	if (!Catalog::ValidId(d) || Catalog::gMobile[d] || Catalog::gFloater[d] || (Catalog::gExtractsM[d] > 0.f))
		return false;
	if ((Catalog::gBuildsList[d].length() > 0) || (Catalog::gPower[d] > 1.f) || Catalog::gShield[d])
		return false;
	return (Catalog::gMakeE[d] > 1.f) || (Catalog::gConvCapacity[d] > 0.f) || (Catalog::gStoreE[d] >= 1000.f)
		|| (Catalog::gBuildPower[d] > 0.f);
}

bool RowFrame()
{
	if (gRowFrameSet)
		return true;
	if (!Base::gAnchorSet)
		return false;
	// The lattice is in world axes, so the rows are: back is the cardinal nearest the anchor's rear.
	const AIFloat3 f = Base::gFwd;
	if (abs(f.x) >= abs(f.z)) {
		gRowBackDir = AIFloat3((f.x > 0.f) ? -1.f : 1.f, 0.f, 0.f);
		gRowAcross = AIFloat3(0.f, 0.f, 1.f);
	} else {
		gRowBackDir = AIFloat3(0.f, 0.f, (f.z > 0.f) ? -1.f : 1.f);
		gRowAcross = AIFloat3(1.f, 0.f, 0.f);
	}
	// On the build lines: every row edge a whole number of build squares from the map corner.
	gRowOrigin = Base::gAnchor;
	gRowOrigin.x = 16.f * floor(gRowOrigin.x / 16.f);
	gRowOrigin.z = 16.f * floor(gRowOrigin.z / 16.f);
	gRowBack = ROW_START;
	gRowFrameSet = true;
	return true;
}

float RowCentre(uint r) { return gRowDepth[r] + gRowPitch[r] * 0.5f; }

AIFloat3 RowCell(uint r, int k)
{
	return gRowOrigin + gRowBackDir * RowCentre(r) + gRowAcross * (float(k) * gRowPitch[r]);
}

int RowOpen(int d)
{
	const float p = Lattice::FootPitch(d);
	if (p < 16.f)
		return -1;
	gRowDef.insertLast(d);
	gRowDepth.insertLast(gRowBack);
	gRowPitch.insertLast(p);
	gRowFull.insertLast(false);
	gRowBack += p;
	return int(gRowDef.length()) - 1;
}

// The first free cell of row r, out from the centre line both ways. The engine's own test reads the reservation
// SetExactSite leaves, so a cell already handed out is not free again; a row with no free cell in its span is full.
bool RowNext(uint r, AIFloat3& out at)
{
	if (gRowFull[r])
		return false;
	CCircuitDef@ def = Catalog::Def(gRowDef[r]);
	const int kMax = int(ROW_SPAN / gRowPitch[r]);
	int tried = 0;
	for (int i = 0; i <= 2 * kMax; ++i) {
		const int k = ((i % 2) == 0) ? (i / 2) : -((i + 1) / 2);
		const AIFloat3 c = RowCell(r, k);
		if (!OnMap(c))
			continue;
		if (++tried > ROW_SCAN)
			return false;
		AIFloat3 got;
		if (ai.CanPlaceCell(def, c, got)) {
			at = c;
			return true;
		}
	}
	gRowFull[r] = true;
	return false;
}

// The turret row whose centre is nearest depth `c`, and how far.
int RowTurretNear(float c, float& out dist)
{
	int best = -1;
	dist = 1e9f;
	for (uint r = 0; r < gRowDef.length(); ++r) {
		if (Catalog::gBuildPower[gRowDef[r]] <= 0.f)
			continue;
		const float dd = abs(RowCentre(r) - c);
		if (dd < dist) {
			dist = dd;
			best = int(r);
		}
	}
	return best;
}

// A slot on a row of def d's kind. A turret bought for one frame (`near` on the map) takes the turret row nearest
// that frame's depth -- the long row of build power beside the work (his 10-21) -- else the one nearest the newest
// eco row.
bool RowSlot(int d, AIFloat3& out at, const AIFloat3& in near = AIFloat3(-1.f, 0.f, -1.f))
{
	if (!RowLayoutOn() || !RowFamily(d) || !RowFrame())
		return false;
	const bool turret = Catalog::gBuildPower[d] > 0.f;
	if (turret) {
		float newest = -1.f;
		for (uint r = 0; r < gRowDef.length(); ++r)
			if (Catalog::gBuildPower[gRowDef[r]] <= 0.f)
				newest = RowCentre(r);
		if (OnMap(near)) {
			const AIFloat3 rel = near - gRowOrigin;
			const float nd = rel.x * gRowBackDir.x + rel.z * gRowBackDir.z;
			if (nd > 0.f)
				newest = nd;
		}
		array<uint> order;
		array<float> key;
		for (uint r = 0; r < gRowDef.length(); ++r) {
			if ((gRowDef[r] != d) || gRowFull[r])
				continue;
			order.insertLast(r);
			key.insertLast((newest >= 0.f) ? abs(RowCentre(r) - newest) : RowCentre(r));
		}
		for (uint a = 0; a < order.length(); ++a) {
			uint bi = a;
			for (uint b = a + 1; b < order.length(); ++b)
				if (key[b] < key[bi])
					bi = b;
			const uint tr = order[bi];
			order[bi] = order[a];
			key[bi] = key[a];
			if (RowNext(tr, at))
				return RowHanded(d, tr);
		}
	} else {
		for (uint r = 0; r < gRowDef.length(); ++r)
			if ((gRowDef[r] == d) && RowNext(r, at))
				return RowHanded(d, r);
		// A new row of this kind stands within a turret's reach of a turret row, or one is opened before it.
		const int nd = NanoDefOf(Catalog::Def(d));
		if (Catalog::ValidId(nd) && (Catalog::gBuildDist[nd] > 1.f)) {
			float dist;
			RowTurretNear(gRowBack + Lattice::FootPitch(d) * 0.5f, dist);
			if (dist > Catalog::gBuildDist[nd])
				RowOpen(nd);
		}
	}
	const int nr = RowOpen(d);
	if ((nr >= 0) && RowNext(uint(nr), at))
		return RowHanded(d, uint(nr));
	++gRowsRefused;
	return false;
}

bool RowHanded(int d, uint r)
{
	++gRowsHanded;
	if (ai.frame >= gRowLogAt) {
		gRowLogAt = ai.frame + 30 * SECOND;
		AiLog("apex: rows t=" + ai.teamId + " rows=" + gRowDef.length() + " back=" + int(gRowBack)
			+ " handed=" + gRowsHanded + " refused=" + gRowsRefused
			+ " last=" + Catalog::Def(d).GetName() + "@" + r + " pitch=" + int(gRowPitch[r]));
	}
	return true;
}

}  // namespace Market
