namespace Market {
//------------------------------------------------------------------------------
// WHERE A NANO STANDS -- and it is two different questions.
//
// apexearth 2026-08-31: "We tend to space our nano turrets too much. They use
// too much room. Nanos can be placed right next to the back and sides of all
// factories, and all sides of air factories. Nano turrets should prefer to be
// placed right next to each other. However, defense oriented emplacements of
// nano turrets are better when they're spread out so they don't all get blown
// up at the same time."
//
// So an ASSIST turret packs and a DEFENCE turret spreads, and the two answers
// live apart. This file is only the packed one: a lattice walk outward from
// the thing being served, taking the nearest cell nothing has claimed, so the
// turrets touch instead of sitting on their own private ring.
//
// The one piece of ground it refuses is a ground plant's EXIT LANE -- units
// roll out of a lab along the base's forward axis and a turret in the doorway
// blocks them. An air plant has no doorway, so it packs on all four sides.
//------------------------------------------------------------------------------

// Half the engine build cell, which is what a footprint count is measured in:
// a def of gFootX cells reaches gFootX * 16 / 2 elmos from its own centre.
const float NP_HALFCELL = 8.f;
// A WORK SLICE, not a reach limit. The walk stops at the first free cell, so
// this only bites on ground that is already full -- and an election that
// scanned every cell inside a nano's 500-elmo reach would be a frame spike of
// exactly the shape the frame-budget rule forbids. The next election resumes
// from the same rings with one more turret standing.
const int NP_MAX_CELLS = 96;

// Nothing this plant produces rolls: every mobile thing it builds flies, so it
// has no doorway and every side of it is packable.
bool AirPlant(int defId)
{
	if (!Catalog::ValidId(defId))
		return false;
	const array<int>@ b = Catalog::gBuildsList[defId];
	bool anyMobile = false;
	for (uint i = 0; i < b.length(); ++i) {
		const int d = b[i];
		if (!Catalog::gMobile[d])
			continue;
		anyMobile = true;
		if (!Catalog::gFlyer[d])
			return false;
	}
	return anyMobile;
}

// The ground already spoken for near `at`: every committed structure (ordered,
// framed or standing) plus every live request, as centre + half-extent. Built
// once per walk so the cell loop is a short array scan instead of a full
// ledger pass per cell.
void NearGround(const AIFloat3& in at, float span,
		array<AIFloat3>& out pos, array<float>& out hx, array<float>& out hz)
{
	pos.resize(0);
	hx.resize(0);
	hz.resize(0);
	const float sq = span * span;
	for (uint i = 0; i < ComLen(); ++i) {
		const int d = gComDef[i];
		if (!Catalog::ValidId(d) || Catalog::gMobile[d] || !OnMap(gComPos[i]))
			continue;
		if (at.SqDistance2D(gComPos[i]) > sq)
			continue;
		pos.insertLast(gComPos[i]);
		hx.insertLast(float(Catalog::gFootX[d]) * NP_HALFCELL);
		hz.insertLast(float(Catalog::gFootZ[d]) * NP_HALFCELL);
	}
	// A request enqueued this tick has no ledger row yet -- and the whole point
	// of the nano burst is that several asks resolve inside one window, so
	// reading only the ledger would hand them all the same cell.
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef is null))
			continue;
		const AIFloat3 p = t.GetBuildPos();
		if (!OnMap(p) || (at.SqDistance2D(p) > sq))
			continue;
		const int d = int(t.buildDef.id);
		pos.insertLast(p);
		hx.insertLast(float(Catalog::gFootX[d]) * NP_HALFCELL);
		hz.insertLast(float(Catalog::gFootZ[d]) * NP_HALFCELL);
	}
}

// WHAT THE TURRET IS BEING PACKED AGAINST. Every siting branch in the nano
// executor names a POSITION -- a line, a build frame, a factory -- and none of
// them carries the def whose footprint and doorway decide where the ring can
// go. The ledger already knows what stands there.
int AnchorDefAt(const AIFloat3& in at)
{
	if (!OnMap(at))
		return -1;
	int best = -1;
	float bestD = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		const int d = gComDef[i];
		if (!Catalog::ValidId(d) || Catalog::gMobile[d] || !OnMap(gComPos[i]))
			continue;
		const float dist = at.distance2D(gComPos[i]);
		// Its own footprint plus a cell: the anchor is the thing the position
		// IS, not the nearest building in the base.
		const float own = float((Catalog::gFootX[d] > Catalog::gFootZ[d])
				? Catalog::gFootX[d] : Catalog::gFootZ[d]) * NP_HALFCELL + 16.f;
		if (dist > own)
			continue;
		if ((best < 0) || (dist < bestD)) {
			best = d;
			bestD = dist;
		}
	}
	return best;
}

// Up to `n` packed slots for turrets of `nanoDef` beside `at`, nearest first.
//
// ONE WALK FOR THE WHOLE BURST. A nano execution opens several sites at once,
// and asking this per site would re-scan the same rings once per turret -- the
// bulk-work-in-one-frame shape the frame-budget rule forbids. The walk stops
// as soon as it has `n`, so the common single-slot ask still ends on ring one.
int NanoPackSlots(int nanoDef, const AIFloat3& in at, int anchorDef, int n,
		array<AIFloat3>& out slots)
{
	slots.resize(0);
	if (!Catalog::ValidId(nanoDef) || !OnMap(at) || (n < 1))
		return 0;
	const float pitch = Lattice::FootPitch(nanoDef);
	if (pitch < 1.f)
		return 0;
	const float nhx = float(Catalog::gFootX[nanoDef]) * NP_HALFCELL;
	const float nhz = float(Catalog::gFootZ[nanoDef]) * NP_HALFCELL;

	// A turret that cannot lathe what it stands beside is not packing, it is
	// sprawl -- so the walk never leaves the reach that bought it.
	float reach = Catalog::gBuildDist[nanoDef];
	if (reach < pitch)
		reach = pitch * 6.f;

	// Start outside the anchor's own footprint: the interior rings are all
	// refused anyway (the anchor is in the ledger) and walking them is the
	// most expensive part of a walk that usually ends on the first free cell.
	float ah = 0.f;
	if (Catalog::ValidId(anchorDef)) {
		ah = float(Catalog::gFootX[anchorDef]) * NP_HALFCELL;
		const float az = float(Catalog::gFootZ[anchorDef]) * NP_HALFCELL;
		if (az > ah)
			ah = az;
	}
	int ring0 = int((ah + nhx) / pitch);
	if (ring0 < 1)
		ring0 = 1;
	const int ringN = int(reach / pitch);
	if (ringN < ring0)
		return 0;

	// THE DOORWAY. A ground plant's units roll out along the base axis; an air
	// plant's take off, so it has no lane to keep clear.
	AIFloat3 fwd(0.f, 0.f, 0.f);
	bool lane = false;
	if (Catalog::ValidId(anchorDef) && Base::Ready()
		&& (Catalog::gBuildsList[anchorDef].length() > 0)
		&& !AirPlant(anchorDef))
	{
		fwd = Base::gFwd;
		if (Base::AxisIsRearward()) {
			fwd.x = -fwd.x;
			fwd.z = -fwd.z;
		}
		lane = true;
	}

	array<AIFloat3> op;
	array<float> ohx;
	array<float> ohz;
	NearGround(at, reach + pitch * 2.f, op, ohx, ohz);

	int budget = NP_MAX_CELLS;
	for (int ring = ring0; ring <= ringN; ++ring) {
		for (int i = -ring; i <= ring; ++i) {
			for (int j = -ring; j <= ring; ++j) {
				// The ring's own edge only -- the interior was walked already.
				if ((i > -ring) && (i < ring) && (j > -ring) && (j < ring))
					continue;
				if (budget <= 0)
					return int(slots.length());
				--budget;
				AIFloat3 p = at;
				p.x += float(i) * pitch;
				p.z += float(j) * pitch;
				if (!OnMap(p) || (p.distance2D(at) > reach))
					continue;
				if (lane) {
					// Ahead of the plant and within the width units roll
					// through: that is the doorway, whatever ring it is on.
					const float rx = p.x - at.x;
					const float rz = p.z - at.z;
					const float ahead = rx * fwd.x + rz * fwd.z;
					const float side = rx * fwd.z - rz * fwd.x;
					if ((ahead > 0.f) && (abs(side) < ah + pitch))
						continue;
				}
				bool taken = false;
				for (uint k = 0; k < op.length(); ++k) {
					if ((abs(p.x - op[k].x) < (nhx + ohx[k]))
						&& (abs(p.z - op[k].z) < (nhz + ohz[k])))
					{
						taken = true;
						break;
					}
				}
				if (taken)
					continue;
				slots.insertLast(p);
				// A slot just handed out is ground the next one must not take.
				op.insertLast(p);
				ohx.insertLast(nhx);
				ohz.insertLast(nhz);
				if (int(slots.length()) >= n)
					return int(slots.length());
			}
		}
	}
	return int(slots.length());
}

// The single packed slot, or an off-map vector when nothing in reach is free.
AIFloat3 NanoPackSlot(int nanoDef, const AIFloat3& in at, int anchorDef)
{
	array<AIFloat3> one;
	if (NanoPackSlots(nanoDef, at, anchorDef, 1, one) > 0)
		return one[0];
	return AIFloat3(-1.f, 0.f, -1.f);
}

}  // namespace Market
