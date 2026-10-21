namespace Market {

// ECO CELLS (TUNE_CELL_LAYOUT; his 10-21: "we keep building outward in our blob, why not just pick a new area of
// the map and start building eco there? small blobs of nano turrets which you can build around at all angles are
// more efficient"). A cell is a 4x4 core of turrets with its eco buildings ringed round it, inside the reach of the
// core's near side. When a building fits nowhere in any ring, the next cell opens: on idle turrets at home first,
// then open ground a ring's width from the others, nearest home. Turrets, built or flown in, take the core of the
// cell where the work is. The cell is the request's exact site (IUnitTask.SetExactSite).

// The cell's shape is under test (his 10-21: "try with some different settings until you figure out which one
// works best"): core side, spacing, how far the ring reaches, and whether idle home turrets seed cells.
int CellCore() { const int k = int(ai.GetTunable("apex_cell_core", TUNE_CELL_CORE)); return (k < 2) ? 2 : k; }
const int CELL_SCAN = 300;     // ring cells tried per ask: a ring among standing turrets is mostly taken

bool CellLayoutOn() { return ai.GetTunable("apex_cell_layout", TUNE_CELL_LAYOUT) > 0.f; }

array<AIFloat3> gCellAt;
array<bool> gCellCoreFull;
array<int> gCellLo, gCellHi;          // line mode: the turret slots the line holds, lo..hi (empty while hi < lo)
array<bool> gCellLoShut, gCellHiShut; // line mode: an end that met ground no turret can stand on
AIFloat3 gCellNear(-1.f, 0.f, -1.f);   // the ask's work, for the end a line grows from
array<array<int>> gCellFullDefs;   // defs whose ring in this cell has no free cell left
bool gCellsExhausted = false;
int gCellNano = -1;
int gCellsHanded = 0, gCellsRefused = 0, gCellLogAt = 0;

int CellNanoDef()
{
	if (Catalog::ValidId(gCellNano))
		return gCellNano;
	float reach = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (NanoDefLike(i) && (Catalog::gBuildDist[i] > reach)) {
			reach = Catalog::gBuildDist[i];
			gCellNano = i;
		}
	}
	return gCellNano;
}

float CellCoreHalf()
{
	const int nd = CellNanoDef();
	return Catalog::ValidId(nd) ? (0.5f * float(CellCore()) * Lattice::FootPitch(nd)) : 96.f;
}

// How far from the centre a building of def d may stand: in reach of the core's near side (his 10-21: "the areas
// are too small"; the farthest turret's reach left a 290-elmo ring).
float CellReach()
{
	const int nd = CellNanoDef();
	return Catalog::ValidId(nd) ? Catalog::gBuildDist[nd] : 400.f;
}
float CellRingMax(int d)
{
	// apex_cell_ring: 0 the core's near side reaches it, 1 its farthest turret does
	const float k = (ai.GetTunable("apex_cell_ring", TUNE_CELL_RING) > 0.f) ? 1.414f : 1.f;
	return CellReach() - k * CellCoreHalf() + 0.5f * Lattice::FootPitch(d);
}

bool CellRingFull(uint c, int d)
{
	return gCellFullDefs[c].find(d) >= 0;
}

// The first free core cell of cell c, nearest the centre.
bool CellCoreNext(uint c, AIFloat3& out at)
{
	if (CellLineOn())
		return LineCoreNext(c, at);
	if (gCellCoreFull[c])
		return false;
	const int nd = CellNanoDef();
	if (!Catalog::ValidId(nd))
		return false;
	CCircuitDef@ def = Catalog::Def(nd);
	const float pn = Lattice::FootPitch(nd);
	array<AIFloat3> cand;
	array<float> key;
	for (int i = 0; i < CellCore(); ++i) {
		for (int j = 0; j < CellCore(); ++j) {
			const AIFloat3 p = gCellAt[c] + AIFloat3((float(i) - 0.5f * float(CellCore() - 1)) * pn, 0.f,
					(float(j) - 0.5f * float(CellCore() - 1)) * pn);
			cand.insertLast(p);
			key.insertLast(p.distance2D(gCellAt[c]));
		}
	}
	for (uint a = 0; a < cand.length(); ++a) {
		uint bi = a;
		for (uint b = a + 1; b < cand.length(); ++b)
			if (key[b] < key[bi])
				bi = b;
		const AIFloat3 p = cand[bi];
		cand[bi] = cand[a];
		key[bi] = key[a];
		if (!OnMap(p))
			continue;
		AIFloat3 got;
		if (ai.CanPlaceCell(def, p, got)) {
			at = p;
			return true;
		}
	}
	gCellCoreFull[c] = true;
	return false;
}

// Ring offsets for one footprint pitch, nearest the centre first: outside the core, inside the ring's reach. Sorted
// once per pitch (the per-ask sort over ~300 cells was the whole cost of a ring search).
array<float> gRoPitch;
array<array<AIFloat3>> gRoOff;
const array<AIFloat3>@ RingOffsets(int d)
{
	const float pb = Lattice::FootPitch(d);
	for (uint i = 0; i < gRoPitch.length(); ++i)
		if (abs(gRoPitch[i] - pb) < 0.5f)
			return gRoOff[i];
	const float rMax = CellRingMax(d);
	const float coreOut = CellCoreHalf() + 0.5f * pb;
	const int k = int(rMax / pb) + 1;
	array<AIFloat3> cand;
	array<float> key;
	for (int i = -k; i <= k; ++i) {
		for (int j = -k; j <= k; ++j) {
			const float dx = float(i) * pb, dz = float(j) * pb;
			if ((abs(dx) < coreOut) && (abs(dz) < coreOut))
				continue;
			const float r = sqrt(dx * dx + dz * dz);
			if (r > rMax)
				continue;
			cand.insertLast(AIFloat3(dx, 0.f, dz));
			key.insertLast(r);
		}
	}
	for (uint a = 0; a < cand.length(); ++a) {
		uint bi = a;
		for (uint b = a + 1; b < cand.length(); ++b)
			if (key[b] < key[bi])
				bi = b;
		const AIFloat3 t = cand[bi];
		cand[bi] = cand[a];
		cand[a] = t;
		const float tk = key[bi];
		key[bi] = key[a];
		key[a] = tk;
	}
	gRoPitch.insertLast(pb);
	gRoOff.insertLast(cand);
	return gRoOff[gRoOff.length() - 1];
}

// The nearest free ring cell of def d round cell c.
bool CellRingNext(uint c, int d, AIFloat3& out at)
{
	if (CellLineOn())
		return LineBandNext(c, d, at);
	if (CellRingFull(c, d) || (Lattice::FootPitch(d) < 16.f))
		return false;
	CCircuitDef@ def = Catalog::Def(d);
	const array<AIFloat3>@ off = RingOffsets(d);
	int tried = 0;
	for (uint a = 0; a < off.length(); ++a) {
		const AIFloat3 p = gCellAt[c] + off[a];
		if (!OnMap(p))
			continue;
		if (++tried > CELL_SCAN)
			return false;
		AIFloat3 got;
		if (ai.CanPlaceCell(def, p, got)) {
			at = p;
			return true;
		}
	}
	gCellFullDefs[c].insertLast(d);
	return false;
}

// LINES OF TURRETS (TUNE_CELL_LINE; his 10-21: "I just made a line of nanoturrets. And as we kept getting stronger
// and stronger, I just made that line longer and longer. And why do I choose a line? Because I know that I can build
// above it, and I can build below it"). The core is one row of turrets along the base's across axis, grown a turret
// at a time from the end nearer the work, flush; the buildings fill the bands on both sides, nearest the line first,
// on ground a turret of the line reaches. A line that cannot grow and has no band cell left opens the next beside it.
const int LINE_MAX = 40;   // turrets in one line
bool CellLineOn() { return ai.GetTunable("apex_cell_line", TUNE_CELL_LINE) > 0.f; }

AIFloat3 LineSlot(uint c, int k)
{
	return gCellAt[c] + gRowAcross * (float(k) * Lattice::FootPitch(CellNanoDef()));
}

// A turret ordered on the slot: the request's site within half a pitch.
bool LiveTurretAt(const AIFloat3& in p)
{
	const float tol = 0.5f * Lattice::FootPitch(CellNanoDef());
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null) || (Catalog::gBuildPower[int(t.buildDef.id)] <= 0.f))
			continue;
		if (t.GetBuildPos().distance2D(p) < tol)
			return true;
	}
	return false;
}

// A flown turret is set down a few elmos off its slot: half a pitch is still the slot.
bool OwnTurretAt(const AIFloat3& in p)
{
	const float tol = 0.5f * Lattice::FootPitch(CellNanoDef());
	NanoNear(p, tol + 8.f);
	for (uint q = 0; q < gNanoGrid.hit.length(); ++q)
		if (gOwnNanoPos[uint(gNanoGrid.hit[q])].distance2D(p) < tol)
			return true;
	return false;
}

// The next slot at one end: our own turret standing there already is the line, so the end walks past it.
bool LineEnd(uint c, bool hiEnd, AIFloat3& out at)
{
	const int nd = CellNanoDef();
	CCircuitDef@ def = Catalog::Def(nd);
	int skipped = 0;
	AIFloat3 blockedAt(-1.f, 0.f, -1.f);
	for (int guard = 0; guard < LINE_MAX; ++guard) {
		if (gCellHi[c] - gCellLo[c] + 1 >= LINE_MAX)
			return false;
		const bool empty = gCellHi[c] < gCellLo[c];
		const int k = empty ? 0 : (hiEnd ? (gCellHi[c] + 1) : (gCellLo[c] - 1));
		const AIFloat3 p = LineSlot(c, k);
		if (!OnMap(p))
			break;
		if (OwnTurretAt(p) || LiveTurretAt(p)) {
			if (empty) { gCellLo[c] = 0; gCellHi[c] = 0; }
			else if (hiEnd) gCellHi[c] = k;
			else gCellLo[c] = k;
			gCellFullDefs[c].resize(0);
			continue;
		}
		AIFloat3 got;
		if (!ai.CanPlaceCell(def, p, got)) {
			// a building on the line's path: the line steps past it, up to three slots, and is shut only by a wall
			if (++skipped > 3) {
				blockedAt = p;
				break;
			}
			if (empty) { gCellLo[c] = 0; gCellHi[c] = 0; }
			else if (hiEnd) gCellHi[c] = k;
			else gCellLo[c] = k;
			continue;
		}
		// handed, not held: the end moves over this slot once a turret stands or is ordered on it
		at = p;
		return true;
	}
	if (hiEnd)
		gCellHiShut[c] = true;
	else
		gCellLoShut[c] = true;
	AiLog("apex: cells t=" + ai.teamId + " line #" + c + (hiEnd ? " hi" : " lo") + " shut len=" + (gCellHi[c] - gCellLo[c] + 1)
		+ (OnMap(blockedAt) ? (" by " + StandingNear(blockedAt, 40.f) + " at=" + int(blockedAt.x) + "," + int(blockedAt.z)) : " off map"));
	return false;
}

bool LineCoreNext(uint c, AIFloat3& out at)
{
	if (!RowFrame() || !Catalog::ValidId(CellNanoDef()))
		return false;
	if (gCellLoShut[c] && gCellHiShut[c]) {
		gCellCoreFull[c] = true;
		return false;
	}
	bool hiFirst = (gCellHi[c] - gCellLo[c]) % 2 == 0;
	if (OnMap(gCellNear)) {
		const AIFloat3 rel = gCellNear - gCellAt[c];
		const float along = rel.x * gRowAcross.x + rel.z * gRowAcross.z;
		const float pn = Lattice::FootPitch(CellNanoDef());
		hiFirst = along >= 0.5f * float(gCellLo[c] + gCellHi[c]) * pn;
	}
	for (int t = 0; t < 2; ++t) {
		const bool hiEnd = (t == 0) ? hiFirst : !hiFirst;
		if ((hiEnd ? gCellHiShut[c] : gCellLoShut[c]))
			continue;
		if (LineEnd(c, hiEnd, at))
			return true;
	}
	if (gCellLoShut[c] && gCellHiShut[c])
		gCellCoreFull[c] = true;
	return false;
}

// The band cell nearest the line, on ground a turret the line holds (or its first slot) reaches.
bool LineBandNext(uint c, int d, AIFloat3& out at)
{
	if (CellRingFull(c, d) || !RowFrame())
		return false;
	const float pb = Lattice::FootPitch(d);
	const int nd = CellNanoDef();
	if ((pb < 16.f) || !Catalog::ValidId(nd))
		return false;
	CCircuitDef@ def = Catalog::Def(d);
	const float pn = Lattice::FootPitch(nd);
	const float reach = Catalog::gBuildDist[nd] + 0.5f * pb;
	const int lo = (gCellHi[c] < gCellLo[c]) ? 0 : gCellLo[c];
	const int hi = (gCellHi[c] < gCellLo[c]) ? 0 : gCellHi[c];
	const float loA = float(lo) * pn, hiA = float(hi) * pn, midA = 0.5f * (loA + hiA);
	int tried = 0;
	for (int j = 0; ; ++j) {
		const float perp = 0.5f * pn + 0.5f * pb + float(j) * pb;
		if (perp > reach)
			break;
		const float span = sqrt(reach * reach - perp * perp);
		const int na = int((0.5f * (hiA - loA) + span) / pb) + 1;
		for (int side = 0; side < 2; ++side) {
			const float pp = (side == 0) ? perp : -perp;
			for (int i = 0; i <= 2 * na; ++i) {
				const int ki = ((i % 2) == 0) ? (i / 2) : -((i + 1) / 2);
				const float a = midA + float(ki) * pb;
				const float outside = (a < loA) ? (loA - a) : ((a > hiA) ? (a - hiA) : 0.f);
				// past an end that can still grow, by the few turrets that end will take for this frame
				const bool open = (a < loA) ? !gCellLoShut[c] : ((a > hiA) ? !gCellHiShut[c] : false);
				if (outside > span + (open ? 3.f * pn : 0.f))
					continue;
				const AIFloat3 p = gCellAt[c] + gRowAcross * a + gRowBackDir * pp;
				if (!OnMap(p))
					continue;
				if (++tried > CELL_SCAN)
					return false;
				AIFloat3 got;
				if (ai.CanPlaceCell(def, p, got)) {
					at = p;
					return true;
				}
			}
		}
	}
	gCellFullDefs[c].insertLast(d);
	return false;
}

// A new cell. First on turrets already standing idle at home (his 10-21: "our home base is filled with
// nanoturrets, and there's no eco on them"): the idle turret with the most idle lathe in its reach, a ring's
// width from every cell. Then open ground a ring's width from the others, nearest home, never past the front.
bool CellOpen()
{
	if (gCellsExhausted || !Base::gAnchorSet)
		return false;
	const int nd = CellNanoDef();
	if (!Catalog::ValidId(nd))
		return false;
	const float reach = Catalog::gBuildDist[nd];
	const AIFloat3 home = gFarmSet ? gFarmPos : Base::gAnchor;
	CCircuitDef@ def = Catalog::Def(nd);
	const float step = 2.f * (reach - CellCoreHalf()) * ai.GetTunable("apex_cell_space", TUNE_CELL_SPACE);
	if (ai.GetTunable("apex_cell_home", TUNE_CELL_HOME) > 0.f) {
		IdleNanoLatheM();
		float bestIdle = 0.f;
		AIFloat3 seed;
		for (uint i = 0; (i < gOwnNanoPos.length()) && (i < gIdleNanoFlag.length()); ++i) {
			if (!gIdleNanoFlag[i] || Builder::PastFront(gOwnNanoPos[i]))
				continue;
			bool clear = true;
			for (uint c = 0; (c < gCellAt.length()) && clear; ++c)
				clear = gCellAt[c].distance2D(gOwnNanoPos[i]) >= 0.95f * step;
			if (!clear)
				continue;
			const float idle = IdleNanoLatheNear(gOwnNanoPos[i]);
			if (idle > bestIdle) {
				bestIdle = idle;
				seed = gOwnNanoPos[i];
			}
		}
		if (bestIdle > 0.f) {
			CellAdd(ai.SnapToLattice(def, seed));
			return true;
		}
	}
	if (CellLineOn() && (gCellAt.length() > 0) && RowFrame()) {
		// The next line runs beside the last, its bands meeting the last one's (his 10-21: "eventually, I get out of
		// range of my line on the above and below. And I just make more nanoturrets over there").
		const AIFloat3 last = gCellAt[gCellAt.length() - 1];
		for (int side = 0; side < 2; ++side) {
			const AIFloat3 p = ai.SnapToLattice(def, last + gRowBackDir * (((side == 0) ? 2.f : -2.f) * reach));
			if (!OnMap(p) || Builder::PastFront(p))
				continue;
			bool clear = true;
			for (uint c = 0; (c < gCellAt.length()) && clear; ++c)
				clear = gCellAt[c].distance2D(p) >= 1.9f * reach;
			AIFloat3 got;
			if (clear && ai.CanPlaceCell(def, p, got)) {
				CellAdd(p);
				return true;
			}
		}
	}
	if (gCellAt.length() == 0) {
		AIFloat3 got;
		const AIFloat3 c0 = ai.SnapToLattice(def, home);
		if (OnMap(c0) && ai.CanPlaceCell(def, c0, got)) {
			CellAdd(c0);
			return true;
		}
	}
	AIFloat3 best;
	float bestD = -1.f;
	for (int ring = 1; ring <= 6; ++ring) {
		for (int i = -ring; i <= ring; ++i) {
			for (int j = -ring; j <= ring; ++j) {
				if ((abs(i) != ring) && (abs(j) != ring))
					continue;
				const AIFloat3 p = ai.SnapToLattice(def, home + AIFloat3(float(i) * step, 0.f, float(j) * step));
				if (!OnMap(p) || Builder::PastFront(p))
					continue;
				bool clear = true;
				for (uint c = 0; (c < gCellAt.length()) && clear; ++c)
					clear = gCellAt[c].distance2D(p) >= 0.95f * step;
				if (!clear)
					continue;
				// ground for a core and most of a ring: the centre and six of eight compass points at half reach
				AIFloat3 got;
				if (!ai.CanPlaceCell(def, p, got))
					continue;
				int open = 0;
				for (int q = 0; q < 8; ++q) {
					const float ang = float(q) * 0.785398f;
					const AIFloat3 s = p + AIFloat3(cos(ang) * 0.5f * reach, 0.f, sin(ang) * 0.5f * reach);
					if (OnMap(s) && ai.CanPlaceCell(def, s, got))
						++open;
				}
				if (open < 6)
					continue;
				const float dd = p.distance2D(home);
				if ((bestD < 0.f) || (dd < bestD)) {
					bestD = dd;
					best = p;
				}
			}
		}
		if (bestD >= 0.f)
			break;
	}
	if (bestD < 0.f) {
		gCellsExhausted = true;
		return false;
	}
	CellAdd(best);
	return true;
}

void CellAdd(const AIFloat3& in p)
{
	gCellAt.insertLast(p);
	gCellCoreFull.insertLast(false);
	array<int> none;
	gCellFullDefs.insertLast(none);
	gCellLo.insertLast(0);
	gCellHi.insertLast(-1);
	gCellLoShut.insertLast(false);
	gCellHiShut.insertLast(false);
	AiLog("apex: cells t=" + ai.teamId + " open #" + (gCellAt.length() - 1) + " at=" + int(p.x) + "," + int(p.z));
}

// A slot in a cell for def d. A turret takes the core of the cell nearest `near` (the frame it was bought for, or
// the one a transport carries it to), else the newest cell with room; a building the nearest ring with room, else
// a new cell.
bool CellSlot(int d, AIFloat3& out at, const AIFloat3& in near = AIFloat3(-1.f, 0.f, -1.f))
{
	if (!CellLayoutOn() || !RowFamily(d) || !Base::gAnchorSet)
		return false;
	if (gCellAt.length() == 0)
		CellOpen();
	const bool turret = Catalog::gBuildPower[d] > 0.f;
	gCellNear = near;
	const AIFloat3 ref = OnMap(near) ? near : ((gCellAt.length() > 0) ? gCellAt[gCellAt.length() - 1]
			: (gFarmSet ? gFarmPos : Base::gAnchor));
	// A BUILDING GOES WHERE THE IDLE TURRETS ARE (his 10-21: converters "all around the same area instead of
	// spreading out to use more build power from different locations"; "we made a nano farm and then didn't use it
	// for 5m"). Nearest-first sent a burst to one ring while idle cores stood elsewhere: the idle lathe a cell's core
	// holds ranks it first, distance breaks the tie. A turret still takes the cell nearest its frame.
	array<uint> order;
	array<float> key;
	for (uint c = 0; c < gCellAt.length(); ++c) {
		order.insertLast(c);
		const float dist = gCellAt[c].distance2D(ref);
		key.insertLast(turret ? dist : (dist - 1e4f * IdleNanoLatheNear(gCellAt[c])));
	}
	for (uint a = 0; a < order.length(); ++a) {
		uint bi = a;
		for (uint b = a + 1; b < order.length(); ++b)
			if (key[b] < key[bi])
				bi = b;
		const uint c = order[bi];
		order[bi] = order[a];
		key[bi] = key[a];
		if (turret ? CellCoreNext(c, at) : CellRingNext(c, d, at))
			return CellHanded(d, c);
	}
	// Every core full: the turret packs beside the work it was bought for. A cell opens only when a building fits
	// no ring (his 10-21: "we are not fully utilizing them before going off and building another one").
	if (turret) {
		++gCellsRefused;
		return false;
	}
	if (CellOpen() && CellRingNext(gCellAt.length() - 1, d, at))
		return CellHanded(d, gCellAt.length() - 1);
	++gCellsRefused;
	return false;
}

bool CellHanded(int d, uint c)
{
	++gCellsHanded;
	if (ai.frame >= gCellLogAt) {
		gCellLogAt = ai.frame + 30 * SECOND;
		int coreFull = 0;
		for (uint i = 0; i < gCellCoreFull.length(); ++i)
			if (gCellCoreFull[i])
				++coreFull;
		AiLog("apex: cells t=" + ai.teamId + " cells=" + gCellAt.length() + " coreFull=" + coreFull
			+ " handed=" + gCellsHanded + " refused=" + gCellsRefused
			+ " last=" + Catalog::Def(d).GetName() + "@" + c + (gCellsExhausted ? " exhausted" : ""));
	}
	return true;
}

}  // namespace Market
