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
// The MAP's raw income for each spot. CEconomyManager::GetMexSpotIncome reads a
// fixed entry of the metal manager's spot table, so it is the same number all
// game -- and PickSpot asked the engine for it once per map spot per election.
array<float> gAllSpotInc;
bool gSpotsCached = false;
// The spot list is fixed for the game, and FarmSlot asks this question once per
// candidate slot -- so the walk was (slots) x (every mex on the map).
Grid::Cells gSpotGrid;
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
		gAllSpotInc.insertLast(aiEconomyMgr.GetMexSpotIncome(i));
	}
	gSpotGrid.Begin(256.f, 0.f, 0.f,
			float(AiTerrainWidth()), float(AiTerrainHeight()));
	for (uint i = 0; i < gAllSpots.length(); ++i)
		gSpotGrid.Add(gAllSpots[i].x, gAllSpots[i].z);
}
bool NearSpotR(const AIFloat3& in p, float r)
{
	CacheSpots();
	gSpotGrid.Query(p.x, p.z, r);
	for (uint q = 0; q < gSpotGrid.hit.length(); ++q) {
		if (p.distance2D(gAllSpots[uint(gSpotGrid.hit[q])]) < r)
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

// The structure register, indexed. Rebuilt only when the register itself
// changes, which is a placement or a death -- not once per asker.
Grid::Cells gSeenGrid;
int gSeenGridStamp = -1;
void SeenGridSync()
{
	if (gSeenGridStamp == Lattice::gSeenStamp)
		return;
	gSeenGridStamp = Lattice::gSeenStamp;
	gSeenGrid.Begin(256.f, 0.f, 0.f,
			float(AiTerrainWidth()), float(AiTerrainHeight()));
	for (uint i = 0; i < Lattice::gSeen.length(); ++i)
		gSeenGrid.Add(Lattice::gSeen[i].x, Lattice::gSeen[i].z);
}

// Ground held by a structure of a DIFFERENT layout class, nearest first.
// Negative when nothing foreign stands within `within`; the layout only ever
// compares this against the touch and aisle radii, so a structure further out
// than that is indistinguishable from none and the index can skip it -- the
// walk was (candidate slots) x (every structure we own), and the second term
// grows all game.
float LayoutForeignGap(int defId, const AIFloat3& in p, float within)
{
	SeenGridSync();
	gSeenGrid.Query(p.x, p.z, within);
	const bool big = BigEcoDef(defId);
	float best = -1.f;
	for (uint q = 0; q < gSeenGrid.hit.length(); ++q) {
		const uint i = uint(gSeenGrid.hit[q]);
		// Rule 4 is per-def; the reactor tiers are one building for layout.
		if (big ? LayoutKin(defId, Lattice::gSeenDef[i])
				: (Lattice::gSeenDef[i] == defId))
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
	array<uint> pend;
	int groups = 0;
	for (uint i = 0; i < n; ++i) {
		if (grp[i] >= 0)
			continue;
		// Flood from i: anything touching the growing set joins it. Each member
		// is expanded ONCE, off a pending list -- the re-sweep-until-nothing-
		// grew form this replaces rescanned the whole set per member, O(kin^3),
		// and kin is every reactor we have committed to.
		grp[i] = groups;
		count.insertLast(1);
		pend.resize(0);
		pend.insertLast(i);
		while (pend.length() > 0) {
			const uint a = pend[pend.length() - 1];
			pend.removeLast();
			for (uint b = 0; b < n; ++b) {
				if ((grp[b] >= 0) || (kin[a].distance2D(kin[b]) > link))
					continue;
				grp[b] = groups;
				++count[groups];
				pend.insertLast(b);
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
// THE DENSEST STANDING LATHE: the turret with the most build power reaching
// it, which is the heart of whichever cluster is thickest. Invalid when no
// nano stands at all.
// THE GROUP OF TURRETS WITH THE MOST SPARE LATHE FOR THIS ASKER. One heart
// sent every ask to one group; with four or five groups standing the other
// rings idled and the walk to the one was the build time (apexearth
// 2026-09-14: "I see 4 or 5 groups of nanos, we should be willing to make
// something next to each of them in parallel... the walk times also make
// us incredibly slow"). Each turret stands for its ring: the ring's build
// power over the frames already rising in its reach, over the asker's
// walk. Invalid when no turret stands.
AIFloat3 LatheSiteFor(CCircuitUnit@ unit)
{
	AIFloat3 best(-1.f, 0.f, -1.f);
	float bestScore = 0.f;
	if (gOwnNanoPos.length() == 0)
		return best;
	const AIFloat3 me = (unit !is null) ? unit.GetPos(ai.frame) : AIFloat3(-1.f, 0.f, -1.f);
	const float speed = (unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f;
	// The frames rising, once: a live request with a standing nanoframe.
	array<AIFloat3> rising;
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt is null) || lt.IsDead() || (lt.target is null))
			continue;
		const AIFloat3 lp = lt.GetBuildPos();
		if (OnMap(lp))
			rising.insertLast(lp);
	}
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		const AIFloat3 p = gOwnNanoPos[i];
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		const float bp = RingBPAt(p);
		if (bp <= 0.f)
			continue;
		int sites = 0;
		for (uint k = 0; k < rising.length(); ++k) {
			if (p.distance2D(rising[k]) < r)
				++sites;
		}
		const float spare = bp / float(1 + sites);
		const float walkSec = ((speed > 1.f) && OnMap(me)) ? (me.distance2D(p) / speed) : 0.f;
		const float score = spare / (1.f + walkSec / 60.f);
		if (score > bestScore) {
			bestScore = score;
			best = p;
		}
	}
	return best;
}

// LATHE STANDING WITH NOTHING TO LATHE [m/s]: turrets with no rising frame
// in reach. Waste beside idle turrets is not a lathe shortage (his watched
// seat: 328 turrets at 848 income, "lots of idle nano turrets").
float gIdleNanoM = 0.f;
int gIdleNanoAt = -999999;
float IdleNanoLatheM()
{
	if (ai.frame - gIdleNanoAt < 5 * SECOND)
		return gIdleNanoM;
	gIdleNanoAt = ai.frame;
	array<AIFloat3> rising;
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt is null) || lt.IsDead() || (lt.target is null))
			continue;
		const AIFloat3 lp = lt.GetBuildPos();
		if (OnMap(lp))
			rising.insertLast(lp);
	}
	float idle = 0.f;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		bool busy = false;
		for (uint k = 0; (k < rising.length()) && !busy; ++k)
			busy = gOwnNanoPos[i].distance2D(rising[k]) < r;
		if (!busy)
			idle += NANO_ABSORB;
	}
	gIdleNanoM = idle;
	return idle;
}

// WHERE A BIG FRAME RISES FASTEST: the legal footprint the most standing
// lathe already reaches. Its arrival is the bill over the lathe that can
// touch it, so the turrets choose the ground, not the farm flank. The K
// richest turret rings are probed, one per block.
const int LATHE_SITE_PROBES = 6;
// The cell C++ will keep, not the engine's raw square, or the score is read
// off ground the build never stands on.
AIFloat3 LatticeFit(CCircuitDef@ def, const AIFloat3& in raw)
{
	if (!OnMap(raw))
		return raw;
	const AIFloat3 cell = ai.SnapToLattice(def, raw);
	const float pitch = Lattice::FootPitch(int(def.id));
	const AIFloat3 s = ai.FindBuildSiteNear(def, cell, pitch);
	if (OnMap(s) && (s.distance2D(cell) < pitch * 0.5f))
		return cell;
	return ai.FindBuildSiteNear(def, cell, pitch * 3.f);
}
array<int> gLSDefs;
array<AIFloat3> gLSPos;
array<int> gLSAt;
AIFloat3 LatheSite(CCircuitDef@ def, CCircuitDef@ mover, const AIFloat3& in interior)
{
	if ((def is null) || (gOwnNanoPos.length() == 0) || !Base::gAnchorSet)
		return interior;
	const int did = int(def.id);
	for (uint i = 0; i < gLSDefs.length(); ++i) {
		if ((gLSDefs[i] == did) && (ai.frame - gLSAt[i] < 10 * SECOND))
			return gLSPos[i];
	}
	// One probe per BLOCK: the richest squares all sit inside one block,
	// and a big footprint fits nowhere near a block's middle.
	array<float> ringBP;
	ringBP.resize(gOwnNanoPos.length());
	for (uint i = 0; i < gOwnNanoPos.length(); ++i)
		ringBP[i] = RingBPAt(gOwnNanoPos[i]);
	array<int> top;
	for (int k = 0; k < LATHE_SITE_PROBES; ++k) {
		int pick = -1;
		for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
			if ((ringBP[i] <= 0.f) || ((pick >= 0) && (ringBP[i] <= ringBP[uint(pick)])))
				continue;
			const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
			bool dup = false;
			for (uint t = 0; (t < top.length()) && !dup; ++t)
				dup = gOwnNanoPos[i].distance2D(gOwnNanoPos[uint(top[t])]) < r;
			if (!dup)
				pick = int(i);
		}
		if (pick < 0)
			break;
		top.insertLast(pick);
	}
	// A line's nano block is not a lab site: the same eco leash the fallback
	// rings keep, and the constructor's own past-the-front test.
	const float leash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	// The interior is a candidate on the same terms: scored where a footprint
	// FITS, not at the ask -- asked inside a block it reads the richest lathe
	// of all and fits nowhere, and the widening walk leaves for bare ground.
	AIFloat3 best = interior;
	float bestBP = -1.f;
	float interiorBP = -1.f;
	// A ground plant on the rim faces OUT: a site whose doorway the block
	// already fills is the walled-in plant the move law would eat again.
	const bool doorway = !AirPlant(did) && (Catalog::gBuildsList[did].length() > 0);
	int doorRefused = 0;
	if (OnMap(interior)) {
		const AIFloat3 s0 = LatticeFit(def, ai.FindBuildSiteNear(def, interior, NanoRange() * 2.f));
		if (OnMap(s0) && !NearBlocked(s0) && ReachableBy(mover, s0)
			&& !(doorway && (ClearExitLane(s0).distance2D(s0) > 1.f))) {
			best = s0;
			bestBP = RingBPAt(s0);
			interiorBP = bestBP;
		}
	}
	int fwdRefused = 0;
	for (uint t = 0; t < top.length(); ++t) {
		const uint i = uint(top[t]);
		// The window is the block's width: the nearest legal footprint to
		// a block's centre is on its rim, and the score below still demands
		// lathe on it.
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		const AIFloat3 s = LatticeFit(def, ai.FindBuildSiteNear(def, gOwnNanoPos[i], r * 2.f));
		if (!OnMap(s) || NearBlocked(s) || !ReachableBy(mover, s))
			continue;
		if ((s.distance2D(Base::gAnchor) > leash) || Builder::PastFront(s)) {
			++fwdRefused;
			continue;
		}
		if (doorway && (ClearExitLane(s).distance2D(s) > 1.f)) {
			++doorRefused;
			continue;
		}
		const float bp = RingBPAt(s);
		if (bp > bestBP) {
			bestBP = bp;
			best = s;
		}
	}
	AiLog("apex: lathe-site t=" + ai.teamId + " " + def.GetName()
		+ " interior=" + int(interior.x) + "," + int(interior.z)
		+ " bp=" + int(interiorBP)
		+ " to=" + int(best.x) + "," + int(best.z) + " bp=" + int(bestBP)
		+ " probed=" + top.length() + " fwdRefused=" + fwdRefused
		+ " doorRefused=" + doorRefused);
	bool cached = false;
	for (uint i = 0; i < gLSDefs.length(); ++i) {
		if (gLSDefs[i] == did) {
			gLSPos[i] = best;
			gLSAt[i] = ai.frame;
			cached = true;
			break;
		}
	}
	if (!cached) {
		gLSDefs.insertLast(did);
		gLSPos.insertLast(best);
		gLSAt.insertLast(ai.frame);
	}
	return best;
}

// Rebuilt per FarmSlot call from that call's own kin and claim sets; kept at
// file scope so Begin reuses the buckets instead of allocating a table a call.
Grid::Cells gFarmKinGrid;
Grid::Cells gFarmClaimGrid;
// Cheap generators pack flush (block_map.json) in groups of ClusterN, groups
// an aisle apart: the ask is the anchor of the nearest group with room, and
// the engine's spiral fills the group from it. A fresh group opens only on
// ground none of our structures stand on -- solars and winds asked from one
// point interleave in one spiral -- and a started one is filled until full.
// ...and converters: asked at the farm centre they have no slot once the
// centre fills and the probe ring places them. A converter yard is a block
// of ClusterN an aisle from the next.
bool GroupedDef(int d)
{
	return Catalog::ValidId(d) && !Catalog::gMobile[d] && !BigEcoDef(d)
			&& ((Catalog::gMakeE[d] > 0.f) || (Catalog::gConvCapacity[d] > 0.f))
			&& !Catalog::gNeedGeo[d];
}
array<int> gGroupLast;
AIFloat3 GroupAnchor(int defId, CCircuitUnit@ unit = null)
{
	CCircuitDef@ def = Catalog::Def(defId);
	// A converter yard starts at the densest turret ring, not the farm
	// centre: raised where no turret reaches, each one was one con's work
	// while forty hands stood where the turrets were (apexearth 2026-09-14).
	AIFloat3 origin = gFarmPos;
	if (Catalog::gConvCapacity[defId] > 0.f) {
		const AIFloat3 heart = LatheSiteFor(unit);
		if (OnMap(heart))
			origin = heart;
	}
	const float pitch = Lattice::StrideOf(defId);
	const float side = float(Lattice::ClusterSide()) * pitch;
	const float step = side + Lattice::AisleW();
	// A fresh group needs only its own first cell (apexearth 2026-09-16:
	// different types directly beside each other, "you want things to be
	// very tight"); three-quarters of a side held every foreign cluster a
	// block apart.
	const float within = pitch;
	const float cell = step * 0.5f;       // every kin counts to one anchor
	const int cap = Lattice::ClusterN();
	array<AIFloat3> kin;
	KinNear(def, kin);
	gFarmKinGrid.Begin(256.f, 0.f, 0.f,
			float(AiTerrainWidth()), float(AiTerrainHeight()));
	for (uint k = 0; k < kin.length(); ++k)
		gFarmKinGrid.Add(kin[k].x, kin[k].z);
	// Asked-for ground of another def: its request sits at its own anchor
	// until the engine sites it, which is exactly when two defs would race
	// for one clean anchor.
	array<AIFloat3> claimed;
	for (uint qi = 0; qi < Requests::gLive.length(); ++qi) {
		IUnitTask@ qt = Requests::gLive[qi];
		if ((qt is null) || qt.IsDead() || (qt.buildDef is null) || (qt.buildDef is def))
			continue;
		const AIFloat3 qp = qt.GetBuildPos();
		if (OnMap(qp))
			claimed.insertLast(qp);
	}
	gFarmClaimGrid.Begin(256.f, 0.f, 0.f,
			float(AiTerrainWidth()), float(AiTerrainHeight()));
	for (uint gq = 0; gq < claimed.length(); ++gq)
		gFarmClaimGrid.Add(claimed[gq].x, claimed[gq].z);
	// Never forward of the farm; nearest anchor first, a shallower one on ties.
	const int span = int(Base::HALF_SPAN / step);
	int bi = 0, bj = 0, bn = 0;
	float bestD = -1.f;
	for (int j = 0; j <= span; ++j) {
		for (int i = -span; i <= span; ++i) {
			const AIFloat3 a = origin + Base::gAcross * (float(i) * step)
					- Base::gFwd * (float(j) * step);
			if (!OnMap(a))
				continue;
			const float d = float(i * i + j * j) + float(j) * 0.01f;
			if ((bestD >= 0.f) && (d >= bestD))
				continue;
			int n = 0;
			gFarmKinGrid.Query(a.x, a.z, cell);
			for (uint q = 0; q < gFarmKinGrid.hit.length(); ++q) {
				if (kin[uint(gFarmKinGrid.hit[q])].distance2D(a) < cell)
					++n;
			}
			if (n >= cap)
				continue;
			if (n == 0) {
				if (LayoutForeignGap(defId, a, within) >= 0.f)
					continue;
				bool asked = false;
				gFarmClaimGrid.Query(a.x, a.z, within);
				for (uint q = 0; (q < gFarmClaimGrid.hit.length()) && !asked; ++q)
					asked = claimed[uint(gFarmClaimGrid.hit[q])].distance2D(a) < within;
				if (asked)
					continue;
			}
			bestD = d;
			bi = i;
			bj = j;
			bn = n;
		}
	}
	if (bestD < 0.f)
		return origin;
	if (uint(defId) >= gGroupLast.length())
		gGroupLast.resize(uint(defId) + 1);
	const int key = (bi + 100) * 1000 + bj + 1;
	if (gGroupLast[defId] != key) {
		gGroupLast[defId] = key;
		AiLog("apex: group t=" + ai.teamId + " " + def.GetName()
			+ " anchor=" + bi + "," + bj + " n=" + bn + " kin=" + kin.length()
			+ " step=" + int(step));
	}
	return origin + Base::gAcross * (float(bi) * step)
			- Base::gFwd * (float(bj) * step);
}

// Where the big eco is asked for -- the safest ground we have. How much a
// standing building sits on it, 1 at the anchor falling to 0 at `r`.
float BigEcoGroundAt(const AIFloat3& in pos, float r)
{
	if (!gFarmSet || (r <= 1.f))
		return 0.f;
	AIFloat3 anchor = gFarmPos;
	if (Base::gAxisSet) {
		const AIFloat3 back = gFarmPos - Base::gFwd * 400.f;
		if (OnMap(back))
			anchor = back;
	}
	const float f = 1.f - pos.distance2D(anchor) / r;
	return (f > 0.f) ? f : 0.f;
}

AIFloat3 FarmSlot(int defId, CCircuitUnit@ unit = null)
{
	CCircuitDef@ def = Catalog::Def(defId);
	if (def is null)
		return gFarmPos;
	if (GroupedDef(defId) && Base::gAxisSet)
		return GroupAnchor(defId, unit);
	// The ask is the farm centre, big energy a step further back (BARb's
	// energyBase2); the engine's spiral and the stock block map choose the
	// square. The lattice scan that stood here is in git (4fca2ee0's tree).
	if (BigEcoDef(defId) && Base::gAxisSet) {
		AIFloat3 back = gFarmPos - Base::gFwd * 400.f;
		// A BIG BUILD GRAVITATES TO THE LATHE. Where the densest ring of
		// turrets reaches more build power than the rear point does, the ask
		// goes there and the lattice rings find the cell beside it
		// (apexearth 2026-09-14: "prefer to build our really large
		// buildings as close as we can to our nano turrets. This is often
		// the difference between whether or not we make it at double speed").
		const AIFloat3 heart = LatheSiteFor(unit);
		if (OnMap(heart) && (RingBPAt(heart) > RingBPAt(back)))
			back = heart;
		if (OnMap(back))
			return back;
	}
	return gFarmPos;
}

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
const uint  BLOCK_MAX  = 48;   // a cliff map bans many spots at once
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

// A site the script itself found unreachable (the stuck watch: a builder
// that never closed on it) joins the same memory, or it is re-elected the
// moment the task is freed.
void BlockNote(const AIFloat3& in b)
{
	if (!OnMap(b))
		return;
	for (uint i = 0; i < gBlockPos.length(); ++i) {
		if (gBlockPos[i].distance2D(b) < BLOCK_NEAR) {
			gBlockAt[i] = ai.frame;
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
		// A fallback site is still THIS want's site. The rings stay inside the
		// eco leash of the base, and a gun stays in reach of what it was
		// placed to cover: a 5,600 ring put the commander's first LLT in the
		// far corner, 5,000 elmo from the lab it covered, and he walked there.
		const float leash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
		// ...and what it SERVES stays in reach of the primary: a gun's range,
		// a jammer's or a shield's dome, a radar's sweep. Unbounded, a line
		// jammer fell to the base ring 3,400 elmos from the line and the
		// next one stood beside it.
		float reachR = Catalog::gMaxRange[did];
		if (Catalog::gJamR[did] > reachR) reachR = Catalog::gJamR[did];
		if (Catalog::gShieldR[did] > reachR) reachR = Catalog::gShieldR[did];
		if (Catalog::gRadarR[did] > reachR) reachR = Catalog::gRadarR[did];
		for (uint r = 0; !ok && (r < 4) && (ring <= leash); ++r) {
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
				if ((reachR > 0.f) && (s2.distance2D(primary) > reachR))
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
	// The farm latches only once the anchor is final: before the lab the
	// anchor tracks the centroid of what stands (Base::Frame).
	if (!gFarmSet && Base::gAnchorSet && Base::gAxisSet && Base::gAnchorFinal) {
		// Within nano reach of the anchor: the block must serve the lab AND
		// the eco builds beside it (apexearth: nanos "not even within range
		// of the T1 lab they would support").
		float back = ai.GetTunable("apex_farm_back", TUNE_FARM_BACK);
		if (back > NanoRange() * 0.8f)
			back = NanoRange() * 0.8f;
		AIFloat3 spot = Base::gAnchor - Base::gFwd * back;
		// The rear of the axis can be past a cliff (Supreme Isthmus corner
		// seat: farm at 11197,558, every converter and radar asked there
		// died unreachable, 91% of the energy wasted). Walk the farm back
		// toward the anchor until the asker can reach it.
		CCircuitDef@ mover = (unit !is null) ? Catalog::Def(int(unit.circuitDef.id)) : null;
		if ((mover !is null) && !Catalog::gFlyer[int(mover.id)]) {
			for (int step = 0; (step < 4) && (!OnMap(spot) || !ReachableBy(mover, spot)); ++step) {
				back *= 0.5f;
				spot = Base::gAnchor - Base::gFwd * back;
			}
		}
		if (OnMap(spot)) {
			gFarmPos = spot;
			gFarmSet = true;
			AiLog("apex: nano farm planned at "
				+ formatFloat(spot.x, "", 0, 0) + "," + formatFloat(spot.z, "", 0, 0)
				+ " (rear of base axis, r=" + formatFloat(NanoRange(), "", 0, 0) + ")");
		}
	}
	if (gFarmSet)
		return gFarmPos;
	if (Base::gAnchorSet && Base::gAxisSet) {
		float back = ai.GetTunable("apex_farm_back", TUNE_FARM_BACK);
		if (back > NanoRange() * 0.8f)
			back = NanoRange() * 0.8f;
		const AIFloat3 spot = Base::gAnchor - Base::gFwd * back;
		if (OnMap(spot))
			return spot;
	}
	return unit.GetPos(ai.frame);
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
// One line's unserved spend: its share of the free flow, floored by the
// per-line appetite, less the lathe already standing on it. Zero for a line
// that is not working. The nano batch splits by this, so the gantry with a
// queue takes the turrets and an idle plant takes none.
// ...AND THE WORK MUST BE ARMY. A line whose queue is constructors is not
// spending the flow the nano want prices: a con is a starter, and a turret
// at a con lab only makes cons faster (the eco seat: `line=1003` of nano
// demand at its T2 lab churning constructors, `sink=194` at the reactor
// field where the metal went; 42 turrets against 118 cons). apexearth
// 2026-09-14, on nanos following the spend: "ok on both".
bool LineWorkingArmy(CCircuitUnit@ f)
{
	if ((f is null) || !LineWorking(f))
		return false;
	const int line = Brain::FQIndex(f.id);
	const array<int>@ pr = Catalog::BuildsOf(int(f.circuitDef.id));
	for (uint q = 0; q < pr.length(); ++q) {
		const int d = pr[q];
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		CCircuitDef@ cd = Catalog::Def(d);
		if (cd is null)
			continue;
		if (f.CountQueued(cd) > 0)
			return true;
		if ((line >= 0) && (Brain::PendCount(line, cd) > 0))
			return true;
	}
	return false;
}

float LineUnserved(CCircuitUnit@ f, float feed, float spendFloor, float sumCeil)
{
	if ((f is null) || !LineWorkingArmy(f))
		return 0.f;
	float share = (sumCeil > 1.f)
			? (feed * LineCostCeil(f) / sumCeil)
			: feed;
	if (spendFloor > share)
		share = spendFloor;
	const AIFloat3 fp = f.GetPos(ai.frame);
	if (!OnMap(fp))
		return 0.f;
	// THE LATHE ALREADY STANDING IS NOT SUBTRACTED. It is busy on a working
	// line, so its eating is already inside the pull that FreeMetalFlow
	// nets off: taking it off again capped a line's lathe at the unspent
	// flow's share however much overflowed. The eco seat's gantries read
	// line=0 with 592 s queued, a full bank and 270 m/s of waste while 77
	// turrets stood idle elsewhere. The flow itself is the stop: each
	// turret bought here pulls, and the free flow falls by what it eats.
	return share;
}

float LineCeilSum()
{
	float sumCeil = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if ((Factory::gFacUnits[fi] !is null) && LineWorkingArmy(Factory::gFacUnits[fi]))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	return sumCeil;
}

float NeediestLine(AIFloat3& out at)
{
	float worst = 0.f;
	const float feed = FreeMetalFlow();
	// The army want floors every working line's share: the ceiling weight
	// alone let one standing gantry (ceil 29000) starve a T2 lab to ~2% of
	// feed, below its own lathe -- so labs priced zero nano demand while
	// metal overflowed. LineSpend is the per-line army/overflow appetite.
	const float spendFloor = LineSpend();
	const float sumCeil = LineCeilSum();
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		const float u = LineUnserved(f, feed, spendFloor, sumCeil);
		if (u > worst) {
			worst = u;
			at = f.GetPos(ai.frame);
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
	// Nothing further out than the longest reach can cover this ground, so the
	// walk over every turret was reading a base to answer about a square.
	NanoNear(at, NanoMaxReach());
	for (uint q = 0; q < gNanoGrid.hit.length(); ++q) {
		const uint i = uint(gNanoGrid.hit[q]);
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		if (at.distance2D(gOwnNanoPos[i]) < r)
			lathe += NANO_ABSORB;
	}
	return lathe;
}

// Raw build power [BP] from standing nanos whose reach covers this ground.
// IS THIS SITE WORTH PARKING LATHE ON?
//
// It used to ask "is this EXPENSIVE" -- cost >= apex_nano_sink_m (1000) or
// output >= apex_big_e (500). The advanced converter answers no to both: 380
// metal, and it MAKES no energy, it eats it. So the one building that most
// needs help never got any.
//
// apexearth: "That is because we aren't making the T2 advanced converters fast
// enough. How can we make those quicker?" -- and the def says why. Buildtime
// per metal, read off the pinned tree:
//
//     armmmkr  380m / 35,000bt = 92      armafus 9,700m / 312,500bt = 32
//     armmoho  620m / 14,900bt = 24      armfus  4,300m /  70,000bt = 16
//     armnanotc 210m / 5,300bt = 25      armalab 2,900m /  16,200bt =  5
//
// The advanced converter is the most buildtime-dense thing we build, by 3-6x.
// 35,000 buildtime is minutes of one constructor's life for 380 metal, which
// is exactly what a lathe fleet is for -- and metal cost cannot see it.
//
// So the third clause is BUILD TIME, and its bar is derived rather than picked:
// a site is worth a turret's attention when it takes longer to build than the
// turret itself does. Below that the helper costs more time than it saves.
// The yardstick: how long the best turret we could stand takes to build.
// Cached on a slow clock -- NanoSinkWorthy is called inside the per-site loops
// and a full def scan per call is the bulk-work-in-one-frame shape the frame
// budget forbids. What is available changes on tech, not on ticks.
float gLatheBt = -1.f;
int gLatheBtAt = -999999;
float LatheBuildTime()
{
	if ((gLatheBt >= 0.f) && (ai.frame - gLatheBtAt < 30 * SECOND))
		return gLatheBt;
	gLatheBtAt = ai.frame;
	gLatheBt = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::gAvailable[i] || Catalog::gMobile[i]
			|| (Catalog::gBuildPower[i] <= 0.f)
			|| (Catalog::gBuildsList[i].length() > 0))
			continue;
		if (Catalog::gBuildTime[i] > gLatheBt)
			gLatheBt = Catalog::gBuildTime[i];
	}
	return gLatheBt;
}

bool NanoSinkWorthy(int bd)
{
	if (!Catalog::ValidId(bd))
		return false;
	if ((Catalog::gCostM[bd] >= ai.GetTunable("apex_nano_sink_m", TUNE_NANO_SINK_M))
		|| (Catalog::gMakeE[bd] >= ai.GetTunable("apex_big_e", TUNE_BIG_E)))
		return true;
	const float bt = Catalog::gBuildTime[bd];
	if (bt <= 0.f)
		return false;
	return (LatheBuildTime() > 1.f) && (bt >= LatheBuildTime());
}

// How far this ground sits OUTSIDE the nearest standing nano's circle:
// negative when a turret already covers it, and NO_NANO when none stands.
// Signed, so the sentinel cannot be read as "covered".
const float NO_NANO = 1.0e6f;
float NanoGap(const AIFloat3& in at)
{
	float gap = NO_NANO;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		const float d = at.distance2D(gOwnNanoPos[i]) - r;
		if (d < gap)
			gap = d;
	}
	return gap;
}

float RingBPAt(const AIFloat3& in at)
{
	float bp = 0.f;
	NanoNear(at, NanoMaxReach());
	for (uint q = 0; q < gNanoGrid.hit.length(); ++q) {
		const uint i = uint(gNanoGrid.hit[q]);
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
			&& LineWorkingArmy(Factory::gFacUnits[fi]))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || !LineWorkingArmy(f))
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
