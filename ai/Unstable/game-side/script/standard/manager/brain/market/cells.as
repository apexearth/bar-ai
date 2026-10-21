namespace Market {

// ECO CELLS (TUNE_CELL_LAYOUT; his 10-21: "we keep building outward in our blob, why not just pick a new area of
// the map and start building eco there? small blobs of nano turrets which you can build around at all angles are
// more efficient"). A cell is a 4x4 core of turrets with its eco buildings ringed round it, inside the reach of the
// core's near side. When a building fits nowhere in any ring, the next cell opens: on idle turrets at home first,
// then open ground a ring's width from the others, nearest home. Turrets, built or flown in, take the core of the
// cell where the work is. The cell is the request's exact site (IUnitTask.SetExactSite).

const int CELL_CORE = 4;       // turrets per core side
const int CELL_SCAN = 300;     // ring cells tried per ask: a ring among standing turrets is mostly taken

bool CellLayoutOn() { return ai.GetTunable("apex_cell_layout", TUNE_CELL_LAYOUT) > 0.f; }

array<AIFloat3> gCellAt;
array<bool> gCellCoreFull;
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
	return Catalog::ValidId(nd) ? (0.5f * float(CELL_CORE) * Lattice::FootPitch(nd)) : 96.f;
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
	return CellReach() - CellCoreHalf() + 0.5f * Lattice::FootPitch(d);
}

bool CellRingFull(uint c, int d)
{
	return gCellFullDefs[c].find(d) >= 0;
}

// The first free core cell of cell c, nearest the centre.
bool CellCoreNext(uint c, AIFloat3& out at)
{
	if (gCellCoreFull[c])
		return false;
	const int nd = CellNanoDef();
	if (!Catalog::ValidId(nd))
		return false;
	CCircuitDef@ def = Catalog::Def(nd);
	const float pn = Lattice::FootPitch(nd);
	array<AIFloat3> cand;
	array<float> key;
	for (int i = 0; i < CELL_CORE; ++i) {
		for (int j = 0; j < CELL_CORE; ++j) {
			const AIFloat3 p = gCellAt[c] + AIFloat3((float(i) - 0.5f * float(CELL_CORE - 1)) * pn, 0.f,
					(float(j) - 0.5f * float(CELL_CORE - 1)) * pn);
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
	const float step = 2.f * (reach - CellCoreHalf());
	{
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
