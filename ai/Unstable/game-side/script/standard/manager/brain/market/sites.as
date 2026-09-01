namespace Market {
// The nano FARM -- a PLANNED spot, not wherever the first nano landed
// (apexearth 2026-08-23: "we should ahead of time know generally some
// really good spots to build the economy... as far away from any active
// threat as we can"). The base frame's axis points at the front, so the
// farm sits BEHIND the anchor; the frame follows the frontline senses, so
// "behind" is already "away from influence".
AIFloat3 gFarmPos;
bool gFarmSet = false;

// Safe ground for a healthy unit told to leave the front: the farm when
// planned, else home. A function so files compiled before this one
// (Builder::Retreat in sitesafety.as) can read it -- the globals above are
// not visible there.
AIFloat3 RetirePos()
{
	if (gFarmSet)
		return gFarmPos;
	if (Builder::gHomeSet)
		return Builder::gHomePos;
	return AIFloat3(-1.f, 0.f, -1.f);
}

// The best available nano's reach -- the coverage circle everything in the
// farm must fit inside.
float gNanoRange = -1.f;
float NanoRange()
{
	if (gNanoRange > 0.f)
		return gNanoRange;
	float best = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::gAvailable[i] || Catalog::gMobile[i])
			continue;
		if ((Catalog::gBuildPower[i] <= 0.f) || (Catalog::gBuildsList[i].length() > 0))
			continue;
		if (Catalog::gBuildDist[i] > best)
			best = Catalog::gBuildDist[i];
	}
	// Sanity-capped: an exotic long-reach def must not widen the farm
	// (a 1000-elmo reach def once did, and the Take radius it fed collapsed
	// every eco want into one standing request -- a fleet-wide freeze).
	if (best > 500.f)
		best = 500.f;
	gNanoRange = (best > 64.f) ? best : 400.f;
	return gNanoRange;
}

// How wide one row of the farm runs before the next stacks behind it. A wide
// row is a LINE, and a line is walked end to end; the same slots in a narrower
// row make a block, where the next slot is always adjacent to the last
// (apexearth: "those winds are a little bit too far on both sides, so we have
// to walk - should make tighter, less walking").
// What one nano turret absorbs of a line's production appetite, metal/s.
// Every demand term that buys lathe subtracts the lathe already standing --
// that subtraction is the only thing that closes the loop, since a turret is a
// standing structure and so RAISES ArmyTarget through gAssetsM while never
// counting toward ArmyValue.
const float NANO_ABSORB = 17.5f;

// Whether growth honours the aisle as well as the seed. A tunable because it
// trades directly against base sprawl: a cluster that may not grow toward its
// neighbour seeds another one further out instead.
bool AisleOnGrow()
{
	return ai.GetTunable("apex_aisle_grow", TUNE_AISLE_GROW) > 0.f;
}

float FarmRowW()
{
	const float w = ai.GetTunable("apex_farm_row_w", TUNE_FARM_ROW_W);
	return (w > 64.f) ? w : 64.f;
}
// How far back the farm has actually been used. Read by InteriorSite to keep
// factories clear of the block.
float gFarmDepth = 0.f;

// Every metal spot on the map, cached on first use -- planned placements
// must never stand on one (watched: buildings over mexes).
array<AIFloat3> gAllSpots;
bool gSpotsCached = false;
void CacheSpots()
{
	if (gSpotsCached)
		return;
	gSpotsCached = true;
	for (int i = 0; i < 1024; ++i) {
		const AIFloat3 sp = aiEconomyMgr.GetMexSpotPos(i);
		if (sp.x < 0.f)
			break;
		gAllSpots.insertLast(sp);
	}
}
bool NearSpotR(const AIFloat3& in p, float r)
{
	CacheSpots();
	for (uint i = 0; i < gAllSpots.length(); ++i) {
		if (p.distance2D(gAllSpots[i]) < r)
			return true;
	}
	return false;
}

bool NearSpot(const AIFloat3& in p)
{
	return NearSpotR(p, 100.f);
}

//------------------------------------------------------------------------------
// THE TEMPORAL-CONSISTENCY LAW's shared primitives (apexearth's 10 m/s
// arithmetic: com + 3 cons feeding a T2 lab while 2 safe mexes sat open).
// Every proposer that claims "my BP converts to progress" buys from
// FreeMetalFlow; every feed-bound build is charged what it postpones via
// OpenSpotStream + UpDemand. New pricing goes through these, not around.
//------------------------------------------------------------------------------

// Metal flow the economy has genuinely unspent: income above pull, plus a
// bank trickle. This is ALL the throughput another pair of hands can add
// anywhere -- marginal BP at a fed site is worth zero.
float FreeMetalFlow()
{
	const float free = (aiEconomyMgr.metal.income - aiEconomyMgr.metal.pull)
			+ aiEconomyMgr.metal.current / 60.f;
	return (free > 0.f) ? free : 0.f;
}

// Where a fusion-tier generator belongs: beside standing or building kin,
// else the deep rear of the base axis, furthest from the enemy.
AIFloat3 BigEnergySite()
{
	const float bar = ai.GetTunable("apex_big_e", TUNE_BIG_E);
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || (Catalog::gMakeE[int(d)] < bar))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(int(d)),
				Builder::gHomePos, 8000.f);
		if ((us !is null) && (us.length() > 0) && (us[us.length() - 1] !is null))
			return us[us.length() - 1].GetPos(ai.frame);
	}
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt is null) || (lt.buildDef is null))
			continue;
		if (Catalog::gMakeE[int(lt.buildDef.id)] >= bar) {
			const AIFloat3 kp = lt.GetBuildPos();
			if (OnMap(kp))
				return kp;
		}
	}
	if (Base::gAnchorSet && Base::gAxisSet) {
		AIFloat3 back = Base::gAnchor
				- Base::gFwd * ai.GetTunable("apex_fus_back", TUNE_FUS_BACK);
		if (OnMap(back))
			return back;
	}
	return Builder::gHomePos;
}

// The richest UNGUARDED building cluster (apexearth: "we still don't
// defend the buildings we make with simple sentry defenses -- a 50 metal
// enemy unit destroys 100s of our value"). Anchors are where structures
// actually gather: factories, the fusion pack, the farm. Clock-gated;
// coverage within 450 zeroes a site.
AIFloat3 gInsPos;
float gInsM = 0.f;
int gInsAt = 127;   // phase offset -- see AiUpdate lockstep note
void RefreshInsureCluster()
{
	if (ai.frame < gInsAt)
		return;
	gInsAt = ai.frame + 10 * SECOND;
	gInsM = 0.f;
	array<AIFloat3> sites;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if (Factory::gFacUnits[fi] !is null)
			sites.insertLast(Factory::gFacUnits[fi].GetPos(ai.frame));
	}
	sites.insertLast(BigEnergySite());
	if (gFarmSet)
		sites.insertLast(gFarmPos);
	for (uint si = 0; si < sites.length(); ++si) {
		if (!OnMap(sites[si]) || ProtCovered(PROT_DEF, sites[si], 450.f))
			continue;
		float m = 0.f;
		for (uint dd = 1; dd < gOwnCount.length(); ++dd) {
			if ((gOwnCount[dd] <= 0) || Catalog::gMobile[int(dd)])
				continue;
			array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(
					Catalog::Def(int(dd)), sites[si], 500.f);
			if (us !is null)
				m += float(us.length()) * Catalog::gCostM[int(dd)];
		}
		if (m > gInsM) {
			gInsM = m;
			gInsPos = sites[si];
		}
	}
}


// Metal spots are sacred ground: an UNCLAIMED spot is legal terrain to the
// engine's site search, so a factory landed smack on one (watched). Intent
// positions step backward (then sideways) until the footprint clears.
AIFloat3 ClearOfSpots(const AIFloat3& in pos, float clear)
{
	if (!NearSpotR(pos, clear))
		return pos;
	for (int step = 1; step <= 8; ++step) {
		if (Base::gAxisSet) {
			AIFloat3 b = pos - Base::gFwd * (96.f * float(step));
			if (OnMap(b) && !NearSpotR(b, clear))
				return b;
			AIFloat3 l = pos + Base::gAcross * (96.f * float(step));
			if (OnMap(l) && !NearSpotR(l, clear))
				return l;
			AIFloat3 rr = pos - Base::gAcross * (96.f * float(step));
			if (OnMap(rr) && !NearSpotR(rr, clear))
				return rr;
		}
	}
	return pos;
}

// Where this def already stands or is already going, near the farm. Gathered
// ONCE per placement: the island test runs per candidate slot, and
// GetOwnUnitsOfDef walks every unit we own.
// FUSION AND AFUS ARE ONE BUILDING FOR LAYOUT PURPOSES.
//
// apexearth 2026-08-31: "We should prefer to build our AFUS/fusion nearby each
// other so they can take advantage of nearby nano turrets to build even
// faster. If we can ensure the nanos are nice and tightly packed then the afus
// can also be nice and tightly packed."
//
// The lattice's kinship was per-DEF, so an advanced fusion read a fusion as a
// FOREIGN def: rule 4 refused every slot touching one, and the two tiers were
// pushed apart by construction rather than by any spacing decision. Both tiers
// also sized their cluster cap off their own count alone, so three fusions and
// four AFUS became four clusters of two instead of one block a turret ring can
// serve.
//
// The predicate is the one FarmSlot already uses for the blast-aisle rule --
// cost or output that only a reactor reaches -- so there is no second
// definition of "reactor" in this file. Advanced solar (350 metal, 75 e/s) and
// geothermal (560, 300) are both outside it.
bool BigEcoDef(int d)
{
	return Catalog::ValidId(d) && !Catalog::gMobile[d]
			&& ((Catalog::gCostM[d] >= 2500.f)
				|| (Catalog::gMakeE[d] >= 400.f));
}

// Same layout class: the same def, or two reactors.
bool LayoutKin(int a, int b)
{
	return (a == b) || (BigEcoDef(a) && BigEcoDef(b));
}

// How many of this def's LAYOUT CLASS we have committed to, at any stage. The
// cluster cap is a statement about how much of the economy one blast reaches,
// and that is a property of the reactors, not of one tier of them.
int LayoutKinCount(int defId)
{
	if (!BigEcoDef(defId))
		return (uint(defId) < gOwnCount.length()) ? gOwnCount[defId] : 0;
	int n = 0;
	for (uint i = 0; i < ComLen(); ++i) {
		if (LayoutKin(defId, gComDef[i]))
			++n;
	}
	return n;
}

// Ground held by a structure of a DIFFERENT layout class, nearest first.
// Negative when nothing foreign stands anywhere near. Lattice::ForeignGap
// answers the same question per def; this one knows the reactor class.
float LayoutForeignGap(int defId, const AIFloat3& in p)
{
	if (!BigEcoDef(defId))
		return Lattice::ForeignGap(defId, p);
	float best = -1.f;
	for (uint i = 0; i < Lattice::gSeen.length(); ++i) {
		if (LayoutKin(defId, Lattice::gSeenDef[i]))
			continue;
		const float d = Lattice::gSeen[i].distance2D(p);
		if ((best < 0.f) || (d < best))
			best = d;
	}
	return best;
}

void KinNear(CCircuitDef@ def, array<AIFloat3>& out kin)
{
	kin.resize(0);
	if (def is null)
		return;
	// The commitment ledger, not GetOwnUnitsOfDef: it is per-def, and the
	// window that matters is exactly when two tiers decide together -- an
	// ORDERED reactor has to be kin or the second one starts its own cluster.
	if (BigEcoDef(int(def.id))) {
		for (uint i = 0; i < ComLen(); ++i) {
			if (LayoutKin(int(def.id), gComDef[i]) && OnMap(gComPos[i]))
				kin.insertLast(gComPos[i]);
		}
		return;
	}
	array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(def, gFarmPos, 6000.f);
	if (us !is null) {
		for (uint i = 0; i < us.length(); ++i) {
			if (us[i] !is null)
				kin.insertLast(us[i].GetPos(ai.frame));
		}
	}
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef !is def))
			continue;
		const AIFloat3 bp = t.GetBuildPos();
		if (OnMap(bp))
			kin.insertLast(bp);
	}
}

// Sizes of the connected clusters `kin` forms, one entry per kin. Two of a def
// belong to the same cluster when they touch on the lattice, so a cluster is
// exactly the block a builder works without walking -- and its size is what
// says whether the next one starts here or somewhere else.
void ClusterSizes(const array<AIFloat3>& in kin, float link, array<int>& out size)
{
	const uint n = kin.length();
	array<int> grp(n, -1);
	array<int> count;
	int groups = 0;
	for (uint i = 0; i < n; ++i) {
		if (grp[i] >= 0)
			continue;
		// Flood from i: anything touching the growing set joins it.
		grp[i] = groups;
		count.insertLast(1);
		bool grew = true;
		while (grew) {
			grew = false;
			for (uint a = 0; a < n; ++a) {
				if (grp[a] != groups)
					continue;
				for (uint b = 0; b < n; ++b) {
					if ((grp[b] >= 0) || (kin[a].distance2D(kin[b]) > link))
						continue;
					grp[b] = groups;
					++count[groups];
					grew = true;
				}
			}
		}
		++groups;
	}
	size.resize(n);
	for (uint i = 0; i < n; ++i)
		size[i] = count[grp[i]];
}

// THE BASE LAYOUT, one slot at a time (apexearth 2026-08-25). A building goes
// beside kin of its own def -- top, bottom, left or right -- until that cluster
// is big enough, and then the next one starts a fresh cluster an aisle away.
// Nothing is spaced by what its death does; see manager/lattice.as.
//
// Slots come off the shared lattice anchored on the BASE ANCHOR, not the farm
// centre: C++ snaps every placement onto the anchor's grid
// (CCircuitAI::SnapToBaseGrid), so a scan run from any other origin has each
// answer moved off the phase the scan itself is walking. The farm only decides
// where on the lattice to start looking.
//
// A slot is taken only if the engine agrees it is buildable AT THAT POINT. The
// old code handed out a row/column intent and let the task's own 1600-elmo
// search settle it, which is what turned a blocked slot into a building across
// the base and lost the lattice phase for everything after it.
AIFloat3 FarmSlot(int defId)
{
	CCircuitDef@ def = Catalog::Def(defId);
	if (def is null)
		return gFarmPos;
	const float pitch = Lattice::StrideOf(defId);
	const float touch = pitch * 1.05f;   // an orthogonal neighbour, and only that
	const float link = pitch * 1.45f;    // same cluster: orthogonal or diagonal
	const float aisle = Lattice::AisleW();
	const int cluN = Lattice::ClusterN();
	// HALF THE ECONOMY MUST SURVIVE ONE BLAST (apexearth 2026-08-28:
	// "Better if only half our economy blows up instead of the entire
	// thing"). A big generator's cluster caps at half its standing fleet
	// -- never under 2 -- and its clusters part by a blast-scale aisle
	// instead of a walkway. Same-def only; the foreign-def lattice
	// spacing is untouched.
	int cluCap = cluN;
	float sameAisle = aisle;
	{
		const bool bigEco = (Catalog::gCostM[defId] >= 2500.f)
				|| (Catalog::gMakeE[defId] >= 400.f);
		if (bigEco) {
			const int own = LayoutKinCount(defId);
			int half = (own + 1) / 2;
			if (half < 2)
				half = 2;
			if (half < cluCap)
				cluCap = half;
			const float bg = ai.GetTunable("apex_blast_aisle", TUNE_BLAST_AISLE);
			if (bg > sameAisle)
				sameAisle = bg;
		}
	}

	array<AIFloat3> kin;
	KinNear(def, kin);
	array<int> csize;
	ClusterSizes(kin, link, csize);

	// GROUND ALREADY ASKED FOR IS NOT FREE GROUND. A request that exists but
	// has not started its nanoframe does not block the engine's map, so the
	// scan below reads its slot as empty and hands it to the next asker too --
	// who is then refused by Requests::Take as "covered" and walks away with
	// nothing. Measured: energy was the most-refused want of all, 229 refusals
	// against 201 elections that ended in no task at all.
	array<AIFloat3> claimed;
	array<int> claimedDef;
	for (uint qi = 0; qi < Requests::gLive.length(); ++qi) {
		IUnitTask@ qt = Requests::gLive[qi];
		if ((qt is null) || qt.IsDead())
			continue;
		const AIFloat3 qp = qt.GetBuildPos();
		if (!OnMap(qp))
			continue;
		claimed.insertLast(qp);
		claimedDef.insertLast((qt.buildDef is null) ? 0 : int(qt.buildDef.id));
	}

	float depth0 = 0.f, lat0 = 0.f;
	Base::Coords(gFarmPos, depth0, lat0);
	depth0 = Lattice::Snap(depth0, pitch);
	lat0 = Lattice::Snap(lat0, pitch);
	// AT LEAST ONE CLUSTER WIDE, whatever the footprint. apex_farm_row_w is an
	// absolute width, so dividing it by the def's pitch left big footprints a
	// corridor: at 320 elmos a solar (pitch 64) gets 5 columns, an advanced
	// solar or a fusion 3, and anything wider than 160 elmos exactly ONE --
	// against 28 rows of depth. A one-column window cannot hold the square
	// block ClusterSide() is asking for, so the grow scoring had no choice but
	// to extend the line it was standing on.
	int lat = int((FarmRowW() * .5f) / pitch);
	{
		const int half = (Lattice::ClusterSide() + 1) / 2;
		if (lat < half)
			lat = half;
	}
	const int rows = int(ai.GetTunable("apex_farm_rows", TUNE_FARM_ROWS));

	// GROW slots (beside kin, cluster not yet full) and the best SEED slot
	// (clear ground for a new cluster), collected in one pass and resolved
	// after: growth always wins, so a cluster fills before another opens.
	//
	// A LIST, not a single best. The engine has the last word on whether a slot
	// is buildable, and when only the top candidate was offered to it a single
	// blocked cell -- a wreck, a slope, a unit standing there -- fell straight
	// through to the seed and started a new cluster an aisle away for no
	// reason. Every grow slot is tried in score order before that happens.
	array<AIFloat3> growAt;
	array<int> growScore;
	array<int> growRow;
	AIFloat3 seedAt;
	float seedScore = -1.f;
	int seedJ = 0;

	for (int j = 0; j <= rows; ++j) {
		for (int i = -lat; i <= lat; ++i) {
			const AIFloat3 p = Base::gAnchor
					+ Base::gAcross * (lat0 + float(i) * pitch)
					- Base::gFwd * (depth0 + float(j) * pitch);
			if (!OnMap(p) || NearSpot(p))
				continue;
			// LEAVE THE WALKWAYS EMPTY. The old band grid dropped every column
			// overlapping a lane; this scan did not, and the eco yards that used to
			// space the block incidentally were zeroed at the same time -- so the
			// farm became a solid slab across the base's central corridor (a lane
			// sits at lateral 0 by construction) and walled the commander in. It
			// held a task, could not move, and burned every retry until the task
			// aborted, over and over. The FOOTPRINT has to clear the lane, not just
			// the centre point.
			{
				float pd = 0.f, pl = 0.f;
				Base::Coords(p, pd, pl);
				if (Base::LaneGap(pl) < (Base::LANE_HALF + pitch * 0.5f))
					continue;
			}
			// Rule 1/2: how many kin this slot would touch, how many it would
			// join, and whether that cluster still has room.
			//
			// NEAR, not just TOUCHING. Kin that were placed off the lattice --
			// the opening builds before the farm exists, anything the engine's
			// own site search settled -- sit at no exact multiple of the pitch,
			// so an adjacency-only test finds no slot beside them and starts a
			// fresh cluster instead. Growing from `link` re-anchors the block
			// onto the lattice around them.
			int adj = 0;
			int near = 0;
			bool full = false;
			float kinGap = -1.f;
			for (uint k = 0; k < kin.length(); ++k) {
				const float d = kin[k].distance2D(p);
				if ((kinGap < 0.f) || (d < kinGap))
					kinGap = d;
				if (d < touch)
					++adj;
				if (d < link) {
					++near;
					if (csize[k] >= cluCap)
						full = true;
				}
			}
			// Rule 4: a slot touching a different def is not this def's ground,
			// however well it suits the cluster -- except that the two reactor
			// tiers are not different buildings here (see LayoutKin).
			const float foreignGap = LayoutForeignGap(defId, p);
			bool blocked = (foreignGap >= 0.f) && (foreignGap < touch);
			for (uint qj = 0; (qj < claimed.length()) && !blocked; ++qj) {
				const float d = claimed[qj].distance2D(p);
				if (d < pitch)
					blocked = true;   // already asked for, whoever asked
				else if (d < touch) {
					if (!LayoutKin(defId, claimedDef[qj]))
						blocked = true;
					else
						++adj;   // an in-flight neighbour still grows a cluster
				}
			}
			if (blocked)
				continue;
			if (near > 0) {
				if (full)
					continue;
				// KEEP THE STREET THE SEED LEFT. Rule 3 parts clusters by an
				// aisle, but only the SEED test enforced it -- growth was free
				// to fill toward a foreign cluster until the two were flush,
				// which is how a walkable gap becomes a pocket with a unit in
				// it. A grow slot may not close the gap below the aisle; the
				// cluster simply grows the other way.
				if (AisleOnGrow() && (foreignGap >= 0.f) && (foreignGap < aisle))
					continue;
				// Prefer the slot with the MOST kin around it: that fills the
				// concave corner of a block rather than extending a line, which
				// is what keeps a cluster square and the walking short. Touching
				// outranks merely near, so a flush slot always beats a re-anchor.
				growAt.insertLast(p);
				growScore.insertLast(adj * 16 + near);
				growRow.insertLast(j);
				continue;
			}
			// Rule 3: a new cluster starts on ground an aisle clear of
			// everything, so big units keep a street between the blocks --
			// and a BIG generator's next cluster starts a blast away from
			// its own kind.
			if ((kinGap >= 0.f) && (kinGap < sameAisle))
				continue;
			if ((foreignGap >= 0.f) && (foreignGap < aisle))
				continue;
			// Nearest such ground to the farm centre, so a new cluster opens
			// beside the base rather than out in the map.
			const float d0 = p.distance2D(gFarmPos);
			if ((seedScore < 0.f) || (d0 < seedScore)) {
				seedScore = d0;
				seedAt = p;
				seedJ = j;
			}
		}
	}

	// Onto this def's own build parity before asking, or the search starts half
	// a cell off and answers with a neighbouring slot.
	const int tries = int(ai.GetTunable("apex_slot_tries", TUNE_SLOT_TRIES));
	for (int t = 0; t < tries; ++t) {
		int best = -1;
		for (uint g = 0; g < growAt.length(); ++g) {
			if ((growScore[g] >= 0)
				&& ((best < 0) || (growScore[g] > growScore[best])))
				best = int(g);
		}
		if (best < 0)
			break;
		growScore[best] = -1;   // spent, whatever the engine says
		const AIFloat3 want = ai.SnapBuildPos(def, growAt[best]);
		const AIFloat3 site = ai.FindBuildSiteNear(def, want, Lattice::CELL);
		if (OnMap(site) && (site.distance2D(want) <= Lattice::CELL * .5f)) {
			const float depth = float(growRow[best]) * pitch;
			if (depth > gFarmDepth)
				gFarmDepth = depth;
			return site;
		}
	}
	if (seedScore >= 0.f) {
		const AIFloat3 want = ai.SnapBuildPos(def, seedAt);
		const AIFloat3 site = ai.FindBuildSiteNear(def, want, Lattice::CELL);
		if (OnMap(site) && (site.distance2D(want) <= Lattice::CELL * .5f)) {
			const float depth = float(seedJ) * pitch;
			if (depth > gFarmDepth)
				gFarmDepth = depth;
			return site;
		}
	}
	return gFarmPos - Base::gFwd * gFarmDepth;
}

// Factory ground: the REAR FLANK of the farm block (apexearth: T2 labs
// "further in the back of our base area", and the vehicle lab needs room
// in front of it -- packed interior blocked its exit). Beside the farm,
// behind the base, lateral ground open for roll-out; flanks alternate.
// THE MASS CENTRE OF WHAT WE OWN, and how far our stuff reaches from it.
//
// apexearth: "Figure out what the mass center of our base is - compute that
// x/y and then place our defenses towards the enemy base/start box. ensure our
// sides are also covered." Weighted by metal, so the centre sits where the
// value is rather than on the start position, and it MOVES as the base grows.
bool BaseCentroid(AIFloat3& out c, float& out extent)
{
	PfRebuild();
	float wsum = 0.f;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < gPfPos.length(); ++i) {
		cx += gPfPos[i].x * gPfWorth[i];
		cz += gPfPos[i].z * gPfWorth[i];
		wsum += gPfWorth[i];
	}
	if (wsum <= 1.f)
		return false;
	c = AIFloat3(cx / wsum, 0.f, cz / wsum);
	if (!OnMap(c))
		return false;
	// How far the base actually reaches, so the closure ring sits just outside
	// it instead of at some radius nobody chose.
	extent = 0.f;
	for (uint i = 0; i < gPfPos.length(); ++i) {
		const float dd = c.distance2D(gPfPos[i]);
		if (dd > extent)
			extent = dd;
	}
	return true;
}

// A SHIELD ARC facing the enemy, wrapping past both flanks.
//
// Posts sit one denied radius outside the base edge, so they meet an attacker
// before it reaches anything, and they are spaced by what each one actually
// denies so the arc has no holes. The arc runs +/-110 degrees off the enemy
// bearing: the enemy half plus both sides ("ensure our sides are also
// covered"), and deliberately not the full circle -- the rear is where towers
// were landing uselessly.
const float SHIELD_ARC = 1.92f;   // 110 degrees in radians

bool ShieldArcSpots(array<AIFloat3>& out pts, float denyR)
{
	pts.resize(0);
	if (denyR < 1.f)
		return false;
	AIFloat3 c;
	float extent = 0.f;
	if (!BaseCentroid(c, extent))
		return false;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return false;
	AIFloat3 dir = foe - c;
	if (dir.SqLength2D() < NEAR_ZERO)
		return false;
	dir.SafeNormalize2D();
	const float baseAng = atan2(dir.z, dir.x);
	const float ringR = extent + denyR;
	const float arcLen = 2.f * SHIELD_ARC * ringR;
	int n = int(arcLen / (2.f * denyR));
	if (n < 3) n = 3;
	if (n > 12) n = 12;   // a bound on WORK, not on how much defence we may own
	for (int k = 0; k <= n; ++k) {
		const float t = (float(k) / float(n)) * 2.f - 1.f;   // -1..+1
		const float ang = baseAng + t * SHIELD_ARC;
		const AIFloat3 p = c + AIFloat3(cos(ang), 0.f, sin(ang)) * ringR;
		if (OnMap(p))
			pts.insertLast(p);
	}
	return pts.length() > 0;
}

// CAN A BUILDER ACTUALLY GET THERE?
//
// The plant site was chosen on geometry alone -- a lateral offset off the base
// axis -- and nothing asked whether a constructor could reach it. On a map cut
// by terrain that offset lands across a cliff or a channel, and the engine
// then rejects the build order the instant it is issued: the con stands still,
// goes idle, is re-Executed, and idles again about FOURTEEN TIMES A SECOND
// until the task burns its retries and aborts. Measured: 584 aborted advanced
// labs in 14 minutes with the con parked 537 elmos away and the site never
// moving, while cheap builds at the farm went up fine.
//
// ai.CanDefReach is the engine's own answer, so ask it before handing a site
// out rather than discovering it one rejected order at a time.
bool ReachableBy(CCircuitDef@ mover, const AIFloat3& in to)
{
	if (!OnMap(to))
		return false;
	if ((mover is null) || !Builder::gHomeSet)
		return true;
	return ai.CanDefReach(mover, Builder::gHomePos, to);
}

AIFloat3 InteriorSite(const AIFloat3& in fallback, CCircuitDef@ mover)
{
	// The first factory rises where the builder stands -- the flank plan is
	// for a base that exists (watched: a long opening walk to lab #1).
	if (Factory::gFactoryCount == 0)
		return fallback;
	if (gFarmSet && Base::gAxisSet) {
		// TAKE THE SAFER FLANK, DO NOT ALTERNATE BLINDLY. gFwd is snapped to a
		// cardinal, so on a map where the enemy sits diagonally gAcross carries
		// a real component TOWARD them -- and a ~700 elmo sideways offset then
		// puts the lab closer to the enemy than the base it is supposed to sit
		// behind (measured: lab at fwd=0.41 while the asker stood at 0.06, and
		// again at -0.07 against an anchor at -0.25). Both flanks are scored on
		// the true enemy bearing and the more rearward one wins; ties still
		// alternate, so a second lab does not stack on the first.
		// A PROPOSER MUST BE PURE. This flipped the flank on every READ, so each
		// time the tech want was priced it asked for the opposite side of the
		// base -- different ground, so CoverFor missed, JoinFor was out of reach
		// (the flanks are ~700 apart) and Take created ANOTHER task. Measured on
		// one player: new=1967 join=6, 517 aborted advanced-lab tasks and zero
		// built, with the assigned constructor turned around every few seconds
		// (builderToSite 502 -> 356 -> 512 -> 325, never converging). The stable
		// FarmSlot positions built fine throughout.
		//
		// The flank still alternates per PLANT -- it just reads the count we
		// already own instead of mutating on every price check.
		const float side = ((Factory::gFactoryCount % 2) == 0) ? 1.f : -1.f;
		const AIFloat3 back = Base::gFwd * (gFarmDepth * 0.5f);
		const AIFloat3 lat = Base::gAcross * (FarmRowW() * 0.5f + 300.f);
		AIFloat3 pA = gFarmPos + lat * side - back;
		AIFloat3 pB = gFarmPos - lat * side - back;
		const bool okA = OnMap(pA) && ReachableBy(mover, pA);
		const bool okB = OnMap(pB) && ReachableBy(mover, pB);
		if (okA && okB) {
			return (Military::ForwardFraction(pB) < Military::ForwardFraction(pA))
					? pB : pA;
		}
		if (okA)
			return pA;
		if (okB)
			return pB;
	}
	if (gFarmSet)
		return gFarmPos;
	// NO FARM YET, AND THE FALLBACK IS THE ASKER'S OWN FEET -- so a con that
	// walked forward to claim a mex put the T2 lab up on the front line
	// (apexearth, watched: "we just started T2 lab in a dangerous area...
	// off to the side is a smarter location than in the direct path the enemy
	// would take to attack us"). Behind the anchor and off the attack axis is
	// that location, and it is the same rear-flank shape the farm branch uses.
	if (Base::gAnchorSet && Base::gAxisSet) {
		const float side2 = ((Factory::gFactoryCount % 2) == 0) ? 1.f : -1.f;
		AIFloat3 a = Base::gAnchor
				+ Base::gAcross * (side2 * (FarmRowW() * 0.5f + 300.f))
				- Base::gFwd * 300.f;
		if (OnMap(a) && ReachableBy(mover, a))
			return a;
		a = Base::gAnchor - Base::gAcross * (side2 * (FarmRowW() * 0.5f + 300.f))
				- Base::gFwd * 300.f;
		if (OnMap(a) && ReachableBy(mover, a))
			return a;
	}
	if (Base::gAnchorSet && OnMap(Base::gAnchor))
		return Base::gAnchor;
	return fallback;
}

// KEEP LOOKING (apexearth, watching a 2v2: a player at 1,400 metal/s held
// the same failing gantry site for minutes -- "he should keep looking and
// trying. I actually see a ton of available spots right near home").
// InteriorSite is a pure function of the farm and axis, so when its answer
// cannot fit the footprint the C++ search fails at the same anchor forever.
// Probe the chosen spot with the engine's own site search; when it cannot
// deliver, walk rings outward around the base -- further out is allowed,
// unreachable ground is not, and the most rearward candidate on a ring wins.
array<int> gProbeDefs;
array<AIFloat3> gProbePos;
array<int> gProbeAt;

// EVERY REFUSED SLOT, NOT JUST THE LAST ONE.
//
// CCircuitAI::NoteBuildBlocked keeps ONE position, overwritten by each refusal,
// so a base with two bad slots ping-pongs between them: marking B forgets A,
// the next election picks A, marking A forgets B. Measured on SI 8v8 -- after
// the energy path started honouring the mark at all, team 4 went from 21 of 21
// advanced fusions lost to 8 of 64, while team 2 still lost 21 of 22, now
// across exactly TWO positions instead of one.
//
// The mark is polled and accumulated here instead. This is the same mechanism
// with a memory, not a new policy: the C++ side still decides what is refused,
// and script only stops forgetting. Entries expire so ground that becomes
// reachable (a wreck cleared, a lane opened) is not banned for the game.
const float BLOCK_NEAR = 250.f;    // matches the C++ mark's own granularity
const int   BLOCK_TTL  = 3 * MINUTE;
const uint  BLOCK_MAX  = 16;
array<AIFloat3> gBlockPos;
array<int> gBlockAt;

void BlockPoll()
{
	AIFloat3 b(-1.f, 0.f, -1.f);
	if (!ai.GetBlockedBuildPos(b) || !OnMap(b))
		return;
	for (uint i = 0; i < gBlockPos.length(); ++i) {
		if (gBlockPos[i].distance2D(b) < BLOCK_NEAR) {
			gBlockAt[i] = ai.frame;   // still being refused; keep it alive
			return;
		}
	}
	gBlockPos.insertLast(b);
	gBlockAt.insertLast(ai.frame);
	while (gBlockPos.length() > BLOCK_MAX) {
		gBlockPos.removeAt(0);
		gBlockAt.removeAt(0);
	}
}

bool NearBlocked(const AIFloat3& in p)
{
	if (!OnMap(p))
		return false;
	BlockPoll();
	for (uint i = 0; i < gBlockPos.length(); ) {
		if (ai.frame - gBlockAt[i] > BLOCK_TTL) {
			gBlockPos.removeAt(i);
			gBlockAt.removeAt(i);
			continue;
		}
		if (gBlockPos[i].distance2D(p) < BLOCK_NEAR)
			return true;
		++i;
	}
	return false;
}

AIFloat3 ProbedSite(CCircuitDef@ def, CCircuitDef@ mover, const AIFloat3& in primary)
{
	if ((def is null) || !OnMap(primary))
		return primary;
	// C++ refusals mark the ground (site-search failure, and OnTravelEnd's
	// reach-safe veto -- the loop where a deterministic site was re-elected
	// and aborted forever). A candidate near the mark is skipped, and a
	// cached answer that has since been marked is re-probed, not served.
	BlockPoll();
	const int did = int(def.id);
	for (uint i = 0; i < gProbeDefs.length(); ++i) {
		if ((gProbeDefs[i] == did) && (ai.frame - gProbeAt[i] < 30 * SECOND)) {
			if (NearBlocked(gProbePos[i]))
				break;
			return gProbePos[i];
		}
	}
	const float seek = 600.f;
	AIFloat3 found = primary;
	bool ok = false;
	{
		const AIFloat3 s = ai.FindBuildSiteNear(def, primary, seek);
		if (OnMap(s) && (s.distance2D(primary) <= seek)
			&& !NearBlocked(s)) {
			found = s;
			ok = true;
		}
	}
	if (!ok) {
		const AIFloat3 c = gFarmSet ? gFarmPos
				: (Base::gAnchorSet ? Base::gAnchor : primary);
		float ring = 700.f;
		for (uint r = 0; !ok && (r < 4); ++r) {
			float bestFwd = 1e9f;
			for (int b = 0; b < 8; ++b) {
				const float ang = float(b) * 0.7853981f;
				const AIFloat3 cand = c
						+ AIFloat3(cos(ang), 0.f, sin(ang)) * ring;
				if (!OnMap(cand) || !ReachableBy(mover, cand))
					continue;
				const AIFloat3 s2 = ai.FindBuildSiteNear(def, cand, seek);
				if (!OnMap(s2) || (s2.distance2D(cand) > seek))
					continue;
				if (NearBlocked(s2))
					continue;
				const float fwd = Military::ForwardFraction(s2);
				if (fwd < bestFwd) {
					bestFwd = fwd;
					found = s2;
					ok = true;
				}
			}
			if (ok)
				AiLog("apex: site-widen t=" + ai.teamId + " " + def.GetName()
					+ " from=" + int(primary.x) + "," + int(primary.z)
					+ " to=" + int(found.x) + "," + int(found.z)
					+ " ring=" + int(ring));
			ring *= 2.f;
		}
	}
	// Cache even a failed probe: re-running the same arithmetic every
	// election is the loop this exists to break.
	bool cached = false;
	for (uint i = 0; i < gProbeDefs.length(); ++i) {
		if (gProbeDefs[i] == did) {
			gProbePos[i] = found;
			gProbeAt[i] = ai.frame;
			cached = true;
			break;
		}
	}
	if (!cached) {
		gProbeDefs.insertLast(did);
		gProbePos.insertLast(found);
		gProbeAt.insertLast(ai.frame);
	}
	return found;
}

AIFloat3 EcoSiteFor(CCircuitUnit@ unit)
{
	if (!gFarmSet && Base::gAnchorSet && Base::gAxisSet) {
		// Within nano reach of the anchor: the block must serve the lab AND
		// the eco builds beside it (apexearth: nanos "not even within range
		// of the T1 lab they would support").
		float back = ai.GetTunable("apex_farm_back", TUNE_FARM_BACK);
		if (back > NanoRange() * 0.8f)
			back = NanoRange() * 0.8f;
		AIFloat3 spot = Base::gAnchor - Base::gFwd * back;
		if (OnMap(spot)) {
			gFarmPos = spot;
			gFarmSet = true;
			AiLog("apex: nano farm planned at "
				+ formatFloat(spot.x, "", 0, 0) + "," + formatFloat(spot.z, "", 0, 0)
				+ " (rear of base axis, r=" + formatFloat(NanoRange(), "", 0, 0) + ")");
		}
	}
	return gFarmSet ? gFarmPos : unit.GetPos(ai.frame);
}

// Nano turrets: standing build power, priced by the BP gap it fills. A nano
// is an immobile lathe with no build options; its drain is its workertime
// at the game's metal-per-workertime rate (7 m/s per 80 WT, the T1 con's
// measured pull).
// Unabsorbed line spend across working factories: each nano near a line
// absorbs ~17.5 m/s; a hot line justifies a RING, not one turret.
// A line's fair share of the production appetite scales with what it can
// BUILD: the T2 lab making 700-metal units earns a bigger nano ring than a
// pawn line (apexearth: "need more nano turrets near our T2 lab").
float LineCostCeil(CCircuitUnit@ f)
{
	float ceil = 100.f;
	const array<int>@ pr = Catalog::BuildsOf(int(f.circuitDef.id));
	for (uint q = 0; q < pr.length(); ++q) {
		if (Catalog::gMobile[pr[q]] && (Catalog::gCostM[pr[q]] > ceil))
			ceil = Catalog::gCostM[pr[q]];
	}
	return ceil;
}

// Metal per buildtime-unit of the line's flagship product: converts BP
// serving this line into the m/s it can actually absorb. The flat 7/80
// average read a gantry nano at 17.5 m/s when a Vanguard line runs it at
// 7.3 -- so the supply ledger said "served" at half the ring the line
// needed, which is the arithmetic behind their 35-nano gantry vs our 6.
float LineDensity(CCircuitUnit@ f)
{
	float dens = 7.f / 80.f;
	if ((f is null) || (f.circuitDef is null))
		return dens;
	float best = 0.f;
	const array<int>@ pr = Catalog::BuildsOf(int(f.circuitDef.id));
	for (uint q = 0; q < pr.length(); ++q) {
		if (!Catalog::gMobile[pr[q]] || (Catalog::gCostM[pr[q]] <= best))
			continue;
		best = Catalog::gCostM[pr[q]];
		if (Catalog::gBuildTime[pr[q]] > 1.f)
			dens = Catalog::gCostM[pr[q]] / Catalog::gBuildTime[pr[q]];
	}
	return dens;
}

// What the lathe standing at this line actually eats [m/s]: its own arm plus
// the nano ring, at the line's product density.
float LineEat(CCircuitUnit@ f, const AIFloat3& in fp)
{
	return (Catalog::gBuildPower[int(f.circuitDef.id)] + RingBPAt(fp))
			* LineDensity(f);
}

// IS THIS LINE WORKING? CountQueued lags sends by a whole order window and
// reads zero for work that is really on the line (facqueue.as), so the sent
// ledger answers too.
bool LineWorking(CCircuitUnit@ f)
{
	if (f is null)
		return false;
	if (f.CountQueued(null) > 0)
		return true;
	const int line = Brain::FQIndex(f.id);
	return (line >= 0) && (Brain::PendCount(line, null) > 0);
}

// THE WORST-SERVED WORKING LINE, and how short of hands it is. A nano bought
// to serve a factory has to STAND at that factory, so the position comes back
// with the number.
//
// A LINE IS PRICED IN THE SAME CURRENCY AS A BUILD SITE: what the economy can
// feed it, less the lathe already standing on it. It used to be priced on the
// ARMY SHORTFALL rate alone, which sits near zero whenever the army is near
// target -- measured 0.6-2.5 m/s against a build site's 26 m/s, so six of nine
// turrets in a game walked past a queued, nano-less lab to a fusion frame
// (apexearth: "we rarely make them around factories that are building units").
// The queue is the demand signal -- the market already decided those units are
// worth buying; free flow is the ceiling, so lathe is never bought idle.
float NeediestLine(AIFloat3& out at)
{
	float worst = 0.f;
	const float feed = FreeMetalFlow();
	// The army want floors every working line's share: the ceiling weight
	// alone let one standing gantry (ceil 29000) starve a T2 lab to ~2% of
	// feed, below its own lathe -- so labs priced zero nano demand while
	// metal overflowed. LineSpend is the per-line army/overflow appetite.
	const float spendFloor = LineSpend();
	float sumCeil = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if ((Factory::gFacUnits[fi] !is null) && LineWorking(Factory::gFacUnits[fi]))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || !LineWorking(f))
			continue;
		float share = (sumCeil > 1.f)
				? (feed * LineCostCeil(f) / sumCeil)
				: feed;
		if (spendFloor > share)
			share = spendFloor;
		const AIFloat3 fp = f.GetPos(ai.frame);
		if (!OnMap(fp))
			continue;
		// The plant's own lathe counts: it is already eating part of the
		// share -- at the line's own product density, not the 7/80 average.
		const float u = share - LineEat(f, fp);
		if (u > worst) {
			worst = u;
			at = fp;
		}
	}
	return worst;
}

// A working line at all, worst-served first -- the site an ARMY shortfall
// wants a lathe at even when the line's own spend is already served.
// The line with the least lathe on it, and HOW MUCH [m/s] is already there.
// The eat is an out param because the caller has to net it off its own
// demand: an army shortfall that ignores the turrets already serving the
// line asks for the same turret forever.
bool AnyLineSite(AIFloat3& out at, float& out lathe)
{
	float fewest = -1.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (f is null)
			continue;
		const AIFloat3 fp = f.GetPos(ai.frame);
		if (!OnMap(fp))
			continue;
		const float eat = LineEat(f, fp);
		if ((fewest < 0.f) || (eat < fewest)) {
			fewest = eat;
			at = fp;
		}
	}
	lathe = (fewest > 0.f) ? fewest : 0.f;
	return fewest >= 0.f;
}

// Lathe [m/s] from standing nanos whose own build reach covers this ground.
// Finished nanos only (the census registry); each contributes NANO_ABSORB.
float NanoLatheReaching(const AIFloat3& in at)
{
	float lathe = 0.f;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		if (at.distance2D(gOwnNanoPos[i]) < r)
			lathe += NANO_ABSORB;
	}
	return lathe;
}

// Raw build power [BP] from standing nanos whose reach covers this ground.
float RingBPAt(const AIFloat3& in at)
{
	float bp = 0.f;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		if (at.distance2D(gOwnNanoPos[i]) < r)
			bp += (i < gOwnNanoBP.length()) ? gOwnNanoBP[i] : 200.f;
	}
	return bp;
}

float UnservedLineSpend()
{
	float unserved = 0.f;
	const float per = LineSpend();
	float sumCeil = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if ((Factory::gFacUnits[fi] !is null)
			&& LineWorking(Factory::gFacUnits[fi]))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || !LineWorking(f))
			continue;
		const float share = (sumCeil > 1.f)
				? (per * float(Factory::gFactoryCount) * LineCostCeil(f) / sumCeil)
				: per;
		const AIFloat3 fp = f.GetPos(ai.frame);
		const float u = share - LineEat(f, fp);
		if (u > 0.f)
			unserved += u;
	}
	return unserved;
}


}  // namespace Market
