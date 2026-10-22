namespace Market {

// TURRET ZONES (TUNE_ZONES; his 10-21: "I know that I'm going to have long rows of construction turrets. And I say,
// okay, this x-axis between here and here, that's entirely about construction turrets. I'm not going to put anything
// else there."). A strip one turret wide runs behind the anchor along the base's across axis, held for the turret def
// in every site search (C++ zones) from the moment it is planned, built up or not. An eco turret -- bought for a frame,
// for the spill, or flown in -- takes the free strip slot nearest its work as an exact site; every other building
// keeps its own siting, which already seeks standing lathe and now cannot stand on the strip. The next strip is
// planned beside the last, two reaches over so their bands meet, once this one's slots are mostly taken.

const int ZONE_LEN = 24;            // turret slots along a strip: shorter strips side by side pass the ground check more often
const int ZONE_SLOTS = 2 * ZONE_LEN; // a strip is two turrets wide (his double rows), reserved whole
const float ZONE_NEXT_FULL = 0.9f;  // share of slots standing that plans the next strip: solid before the next (his 10-21)

bool ZonesOn() { return ai.GetTunable("apex_zones", TUNE_ZONES) > 0.f; }

array<AIFloat3> gZoneAt;     // strip centres
array<int> gZoneTaken;       // slots handed out per strip
array<AIFloat3> gZoneCol0;   // the lattice cell of the strip's first column at its first slot's row
array<int> gZoneFullAt;      // no free slot found on this strip until this frame (cost: late strips are full)
AIFloat3 gZoneAcross, gZoneBack;
int gZoneNano = -1;
bool gZoneShut = false;
int gZoneRetryAt = 0, gZoneNoGroundLogAt = 0, gZoneLastPlanAt = -999999;
AIFloat3 gZonePlantAsk(-1.f, 0.f, -1.f);
array<int> gZonePlantDone;   // plants a strip was planned beside
int gZoneLogAt = 0;

bool ZoneFrame()
{
	if (Catalog::ValidId(gZoneNano))
		return true;
	if (!Base::gAnchorSet)
		return false;
	// the turret we build first, the cheapest: the T2 one reached further and the strip refused the T1 turrets
	float cost = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i)
		if (NanoDefLike(i) && ((cost <= 0.f) || (Catalog::gCostM[i] < cost))) {
			cost = Catalog::gCostM[i];
			gZoneNano = i;
		}
	if (!Catalog::ValidId(gZoneNano))
		return false;
	const AIFloat3 f = Base::gFwd;
	if (abs(f.x) >= abs(f.z)) {
		gZoneBack = AIFloat3((f.x > 0.f) ? -1.f : 1.f, 0.f, 0.f);
		gZoneAcross = AIFloat3(0.f, 0.f, 1.f);
	} else {
		gZoneBack = AIFloat3(0.f, 0.f, (f.z > 0.f) ? -1.f : 1.f);
		gZoneAcross = AIFloat3(1.f, 0.f, 0.f);
	}
	return true;
}

AIFloat3 ZoneSlot(uint z, int k)
{
	const float pn = Lattice::FootPitch(gZoneNano);
	// slot k: column k % 2, position k / 2 along -- whole turret steps from the strip's first lattice cell, so every
	// slot is a lattice cell (from a centre line between them, every other slot read blocked)
	return gZoneCol0[z] + gZoneAcross * (float((k / 2) - (ZONE_LEN / 2)) * pn) + gZoneBack * (float(k % 2) * pn);
}

// The widest eco building a constructor we own can raise, in elmos: the row between two strips is sized for it.
// Read off every def available it measured 176 -- an 11-cell reactor nothing we had could build -- and the strips
// stood 240 apart.
float ZoneRowPitch()
{
	float w = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint oi = 0; oi < own.length(); ++oi) {
		const int bd = own[oi];
		if ((gOwnCount[bd] <= 0) || !Catalog::gBuilder[bd] || !Catalog::gMobile[bd])
			continue;
		const array<int>@ bl = Catalog::gBuildsList[bd];
		for (uint k = 0; k < bl.length(); ++k)
			if (Catalog::gAvailable[bl[k]] && ZoneBandFamily(bl[k]) && (Lattice::FootPitch(bl[k]) > w))
				w = Lattice::FootPitch(bl[k]);
	}
	return (w > 16.f) ? w : 96.f;
}

// The lathe reaching the best band cell: the first row beside the strip with the most turrets, either side. What a
// big build placed in the bands is built with -- priced at the generic eco site, an advanced fusion's crew read as a
// few hands and the fusion out-timed it every time (diag seed 2850: 15 fusions, no AFUS, the value pick AFUS).
float gZoneLatheVal = 0.f;
int gZoneLatheAt = -999999;
float ZoneBandLathe()
{
	if (!ZoneBandsOn() || (gZoneAt.length() == 0))
		return 0.f;
	if (ai.frame - gZoneLatheAt < 5 * SECOND)
		return gZoneLatheVal;
	gZoneLatheAt = ai.frame;
	const float off = Lattice::FootPitch(gZoneNano) + 0.5f * ZoneRowPitch();
	float best = 0.f;
	for (uint z = 0; z < gZoneAt.length(); ++z)
		for (int sg = -1; sg <= 1; sg += 2) {
			const float l = NanoLatheReaching(gZoneAt[z] + gZoneBack * (float(sg) * off));
			if (l > best)
				best = l;
		}
	gZoneLatheVal = best;
	return best;
}

bool ZonePlan()
{
	if (gZoneShut || (ai.frame < gZoneRetryAt) || !ZoneFrame())
		return false;
	CCircuitDef@ def = Catalog::Def(gZoneNano);
	const float reach = Catalog::gBuildDist[gZoneNano];
	const float pn = Lattice::FootPitch(gZoneNano);
	// Candidates: beside the last strip first (bands meeting), then outward from home in rings of half a reach,
	// the rear first. A seed whose three fixed points were all rough ground planned no strip at all.
	array<AIFloat3> cand;
	// ONE REACH OF ECO BETWEEN STRIPS, A LITTLE OVERLAPPING: as many rows of the widest eco building as still let a
	// turret reach the next strip's near column (the engine's range is build distance + the target's radius), so every
	// building between two strips is in reach of both and the old strip helps build the new (his 10-22: with one row
	// between them, "most of the extra nano turrets ... only supported the creation of each other"; "a little bit of
	// overlap is nice"). 4 AFUS rows fell 8 elmos short of that; 3 overlap.
	const float rowP = ZoneRowPitch();
	const float rows = floor((reach - 0.5f * pn) / rowP);
	const float step = 2.f * pn + ((rows >= 1.f) ? rows : 1.f) * rowP;
	// a plant with no strip in its turrets' reach asks for one flush along its side (the blob round the T2 plant)
	if (OnMap(gZonePlantAsk)) {
		const int pd = AnchorDefAt(gZonePlantAsk);
		const float half = Catalog::ValidId(pd)
				? 8.f * float((Catalog::gFootX[pd] > Catalog::gFootZ[pd]) ? Catalog::gFootX[pd] : Catalog::gFootZ[pd]) : 48.f;
		// the first column's cell, flush on either side (across the plant's ends a strip ran through it)
		cand.insertLast(gZonePlantAsk + gZoneBack * (half + 0.5f * pn));
		cand.insertLast(gZonePlantAsk - gZoneBack * (half + 1.5f * pn));
		gZonePlantAsk = AIFloat3(-1.f, 0.f, -1.f);
	}
	const uint nPlantCand = cand.length();
	// one row over first, then two and three -- the block stays one block; rings round home only after (seed 2802 opened
	// a strip 432 elmos from the last when the spot one row over failed its ground check)
	if (gZoneAt.length() > 0) {
		for (int mul = 1; mul <= 3; ++mul) {
			for (uint zi = gZoneAt.length(); zi > 0; --zi) {
				const AIFloat3 zc = gZoneCol0[zi - 1];
				cand.insertLast(zc + gZoneBack * (step * float(mul)));
				cand.insertLast(zc - gZoneBack * (step * float(mul)));
				cand.insertLast(zc + gZoneAcross * (float(ZONE_LEN) * pn * float(mul)));
				cand.insertLast(zc - gZoneAcross * (float(ZONE_LEN) * pn * float(mul)));
			}
		}
	}
	// The first strip runs flush along a plant's side (his line started at his plant), so the plant's turrets
	// stand on it: smoke seed 1690 had both strips 400 elmos from the air plant and its turrets packed round it.
	if (gZoneAt.length() == 0) {
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if ((f is null) || (f.circuitDef is null))
				continue;
			const int fd = int(f.circuitDef.id);
			const AIFloat3 fp = f.GetPos(ai.frame);
			const float half = 8.f * float((Catalog::gFootX[fd] > Catalog::gFootZ[fd]) ? Catalog::gFootX[fd] : Catalog::gFootZ[fd]);
			cand.insertLast(fp + gZoneBack * (half + 0.5f * pn));
			cand.insertLast(fp - gZoneBack * (half + 1.5f * pn));
		}
	}
	{
		const AIFloat3 home = gFarmSet ? gFarmPos : Base::gAnchor;
		cand.insertLast(home);
		for (int ring = 1; ring <= 8; ++ring)
			for (int q = 0; q < 8; ++q) {
				const float ang = float(q) * 0.785398f;
				const AIFloat3 dir = gZoneBack * cos(ang) + gZoneAcross * sin(ang);
				cand.insertLast(home + dir * (0.5f * reach * float(ring)));
			}
	}
	for (uint ci = 0; ci < cand.length(); ++ci) {
		// the candidate is the first column's cell; the centre line runs between the columns and the slots
		const AIFloat3 col0 = ai.SnapToLattice(def, cand[ci]);
		const AIFloat3 c = col0 + gZoneBack * (0.5f * pn) - gZoneAcross * (0.5f * pn);
		if (!OnMap(col0) || !OnMap(c) || Builder::PastFront(c))
			continue;
		bool clear = true;
		for (uint z = 0; (z < gZoneAt.length()) && clear; ++z)
			clear = gZoneAt[z].distance2D(c) >= 0.9f * step;
		if (!clear)
			continue;
		// most of the strip must be buildable ground
		int ok = 0;
		AIFloat3 got;
		for (int k = 0; k < ZONE_LEN; k += 2) {
			const AIFloat3 s = col0 + gZoneAcross * (float(k - (ZONE_LEN / 2)) * pn);
			if (OnMap(s) && ai.CanPlaceCell(def, s, got))
				++ok;
		}
		// beside a plant the ground is crowded: half the strip clear will do
		if (ok * 2 < ((ci < nPlantCand) ? (ZONE_LEN / 2) : (ZONE_LEN * 3 / 4)))
			continue;
		gZoneAt.insertLast(c);
		gZoneCol0.insertLast(col0);
		gZoneTaken.insertLast(0);
		gZoneFullAt.insertLast(0);
		// the slots' own footprints: along from slot 0 to the last, across both columns
		const AIFloat3 a = col0 - gZoneAcross * ((float(ZONE_LEN / 2) + 0.5f) * pn) - gZoneBack * (0.5f * pn);
		const AIFloat3 b = col0 + gZoneAcross * ((float(ZONE_LEN - 1 - (ZONE_LEN / 2)) + 0.5f) * pn) + gZoneBack * (1.5f * pn);
		ai.ReserveZone(a.x, a.z, b.x, b.z, def);
		// every other turret may stand here too -- the advanced one from the extra units (his 10-21)
		for (int ti = 1; ti <= Catalog::gDefCount; ++ti)
			if ((ti != gZoneNano) && NanoDefLike(ti))
				ai.ReserveZone(a.x, a.z, b.x, b.z, Catalog::Def(ti));
		AiLog("apex: zone t=" + ai.teamId + " #" + (gZoneAt.length() - 1) + " " + int(a.x) + "," + int(a.z)
			+ " .. " + int(b.x) + "," + int(b.z) + " for " + def.GetName());
		return true;
	}
	gZoneRetryAt = ai.frame + 30 * SECOND;
	if (ai.frame >= gZoneNoGroundLogAt) {
		gZoneNoGroundLogAt = ai.frame + 120 * SECOND;
		AiLog("apex: zone t=" + ai.teamId + " no ground for strip #" + gZoneAt.length() + " (retrying)");
	}
	return false;
}

// Slot k of strip z holds a turret, standing or ordered.
bool SlotFilled(uint z, int k)
{
	if ((k < 0) || (k >= ZONE_SLOTS))
		return false;
	const AIFloat3 p = ZoneSlot(z, k);
	const float tol = 0.5f * Lattice::FootPitch(gZoneNano);
	NanoNear(p, tol + 8.f);
	for (uint q = 0; q < gNanoGrid.hit.length(); ++q)
		if (gOwnNanoPos[uint(gNanoGrid.hit[q])].distance2D(p) < tol)
			return true;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null) || (Catalog::gBuildPower[int(t.buildDef.id)] <= 0.f))
			continue;
		if (t.GetBuildPos().distance2D(p) < tol)
			return true;
	}
	return false;
}

// The along-strip extent of strip z's standing turrets, from its middle; false with none standing.
bool StripExtent(uint z, float& out lo, float& out hi)
{
	const float pn = Lattice::FootPitch(gZoneNano);
	const float tol = 0.5f * pn;
	bool any = false;
	for (int k = 0; k < ZONE_SLOTS; ++k) {
		const AIFloat3 p = ZoneSlot(z, k);
		NanoNear(p, tol + 8.f);
		bool here = false;
		for (uint q = 0; (q < gNanoGrid.hit.length()) && !here; ++q)
			here = gOwnNanoPos[uint(gNanoGrid.hit[q])].distance2D(p) < tol;
		if (!here)
			continue;
		const float a = (float((k / 2) - (ZONE_LEN / 2)) + 0.5f) * pn;
		if (!any || (a < lo)) lo = a;
		if (!any || (a > hi)) hi = a;
		any = true;
	}
	return any;
}

// Turrets standing on strip z (handed slots planned a new strip while the old one stood near empty: six by minute 22).
int ZoneStanding(uint z)
{
	const float tol = 0.5f * Lattice::FootPitch(gZoneNano);
	int n = 0;
	for (int k = 0; k < ZONE_SLOTS; ++k) {
		const AIFloat3 p = ZoneSlot(z, k);
		NanoNear(p, tol + 8.f);
		for (uint q = 0; q < gNanoGrid.hit.length(); ++q)
			if (gOwnNanoPos[uint(gNanoGrid.hit[q])].distance2D(p) < tol) {
				++n;
				break;
			}
	}
	return n;
}

// The free strip slot nearest `near` (or the newest strip's middle) for turret def d.
// A turret standing on a strip, which the transports leave where it is.
bool OnStrip(const AIFloat3& in p)
{
	if (!ZonesOn() || !Catalog::ValidId(gZoneNano))
		return false;
	const float pn = Lattice::FootPitch(gZoneNano);
	const float halfLen = 0.5f * float(ZONE_LEN) * pn;
	for (uint z = 0; z < gZoneAt.length(); ++z) {
		const AIFloat3 r = p - gZoneAt[z];
		const float a = r.x * gZoneAcross.x + r.z * gZoneAcross.z;
		const float b = r.x * gZoneBack.x + r.z * gZoneBack.z;
		if ((abs(a) <= halfLen) && (abs(b) <= 1.25f * pn))
			return true;
	}
	return false;
}

// Every strip full: the next is planned on the spot and the turret takes it (his 10-21 watch at minute 30: 873
// turrets, 17% on a strip -- the late buying outran the 90%-standing rule and packed the rest anywhere).
bool ZoneSlotFor(int d, const AIFloat3& in near, AIFloat3& out at)
{
	if (ZoneSlotForOnce(d, near, at))
		return true;
	if (!ZonesOn() || !NanoDefLike(d) || (gZoneAt.length() == 0))
		return false;
	// at most one new strip in 5 s (review: any failed search planned a strip per election), but not held for the
	// newest to stand half full -- a late burst of turrets emptied every strip at once and scattered (his 10-21 watch:
	// 97% on strips at minute 20, 28% of 755 at minute 30)
	if (ai.frame < gZoneLastPlanAt + 5 * SECOND)
		return false;
	gZoneLastPlanAt = ai.frame;
	gZoneRetryAt = 0;
	return ZonePlan() && ZoneSlotForOnce(d, near, at);
}

bool ZoneSlotForOnce(int d, const AIFloat3& in near, AIFloat3& out at)
{
	if (!ZonesOn() || (Catalog::gBuildPower[d] <= 0.f) || Catalog::gMobile[d])
		return false;
	if ((gZoneAt.length() == 0) && !ZonePlan())
		return false;
	// any turret: the strip is held for each (a wider one takes the slots its footprint covers)
	if (!NanoDefLike(d))
		return false;
	CCircuitDef@ def = Catalog::Def(d);
	const AIFloat3 ref = OnMap(near) ? near : gZoneAt[gZoneAt.length() - 1];
	// A STRIP FILLS OUTWARD FROM ITS MIDDLE, solid (his 10-21: "hilariously space inefficient"): the slot nearest the
	// work strewed turrets along a 40-slot strip wherever the builders stood. The strip nearest the work, then its free
	// slot nearest the middle; a full strip passes to the next nearest.
	float best = -1.f;
	int bz = -1;
	array<uint> zo;
	array<float> zk;
	for (uint z = 0; z < gZoneAt.length(); ++z) {
		zo.insertLast(z);
		zk.insertLast(gZoneAt[z].distance2D(ref));
	}
	for (uint o = 0; (o < zo.length()) && (bz < 0); ++o) {
		uint bi = o;
		for (uint q = o + 1; q < zo.length(); ++q)
			if (zk[q] < zk[bi])
				bi = q;
		const uint z = zo[bi];
		zo[bi] = zo[o];
		zk[bi] = zk[o];
		if (ai.frame < gZoneFullAt[z])
			continue;
		// TOUCHING, NO SPACING (his 10-21: "throw them all as close as you can to each other"): the free slot beside
		// a turret standing or ordered, nearest the middle; an empty strip starts at its middle.
		// two passes: a slot touching a turret first, any slot after -- a strip with no touching slot free still
		// takes the turret (refused, 65-80% of turrets went off the strips)
		const bool any = ZoneStanding(z) > 0;
		for (int pass = (any ? 0 : 1); (pass < 2) && (bz < 0); ++pass) {
			for (int i = 0; i < ZONE_LEN; ++i) {
				const int idx = (ZONE_LEN / 2) + (((i % 2) == 0) ? (i / 2) : -((i + 1) / 2));
				if ((idx < 0) || (idx >= ZONE_LEN))
					continue;
				for (int col = 0; (col < 2) && (bz < 0); ++col) {
					const int k = 2 * idx + col;
					if ((pass == 0) && !SlotFilled(z, k - 2) && !SlotFilled(z, k + 2) && !SlotFilled(z, (col == 0) ? (k + 1) : (k - 1)))
						continue;
					const AIFloat3 s = ZoneSlot(z, k);
					AIFloat3 got;
					if (OnMap(s) && ai.CanPlaceCell(def, s, got)) {
						best = s.distance2D(ref);
						at = s;
						bz = int(z);
					}
				}
				if (bz >= 0)
					break;
			}
		}
		if (bz < 0)
			gZoneFullAt[z] = ai.frame + 2 * SECOND;
	}
	// TURRETS STAY ON THE STRIPS (his 10-21 watch: 714 turrets strewn over the base, the strips near empty -- a turret
	// sent beside every frame out of a strip's reach). The work comes to the strip, in its bands; the turret takes the
	// strip slot nearest it whatever the distance, and the next strip is planned once this one is mostly taken.
	if ((gZoneAt.length() > 0) && (float(ZoneStanding(gZoneAt.length() - 1)) >= ZONE_NEXT_FULL * float(ZONE_SLOTS)))
		ZonePlan();
	if (bz < 0)
		return false;
	++gZoneTaken[uint(bz)];
	if (ai.frame >= gZoneLogAt) {
		gZoneLogAt = ai.frame + 30 * SECOND;
		AiLog("apex: zone t=" + ai.teamId + " strips=" + gZoneAt.length() + " slot #" + bz + " taken=" + gZoneTaken[uint(bz)]
			+ " at=" + int(at.x) + "," + int(at.z));
	}
	return true;
}

// THE BANDS BESIDE A STRIP (TUNE_ZONE_BANDS): generators, converters and stores stand in the cells either side of a
// strip, inside its turrets' reach, nearest the strip first and along it nearest the work. A cell is the footprint's,
// not a def's (his 10-21: an anti-nuke slots where an advanced converter would). Exact site.
bool ZoneBandsOn() { return ZonesOn() && (ai.GetTunable("apex_zone_bands", TUNE_ZONE_BANDS) > 0.f); }

bool ZoneBandFamily(int d)
{
	if (!Catalog::ValidId(d) || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d]
		|| (Catalog::gExtractsM[d] > 0.f) || (Catalog::gBuildsList[d].length() > 0) || (Catalog::gPower[d] > 1.f)
		|| Catalog::gShield[d] || (Catalog::gBuildPower[d] > 0.f) || Catalog::gNeedGeo[d])
		return false;
	return (Catalog::gMakeE[d] > 1.f) || (Catalog::gConvCapacity[d] > 0.f) || (Catalog::gStoreE[d] >= 1000.f);
}

array<int> gZbFullPitch;   // per strip, the pitches whose bands had no free cell
array<int> gZbFullStrip;
int gZbFullAt = 0;

bool ZoneBandSlot(int d, const AIFloat3& in near, AIFloat3& out at)
{
	if (!ZoneBandsOn() || !ZoneBandFamily(d))
		return false;
	if ((gZoneAt.length() == 0) && !ZonePlan())
		return false;
	// a full band is re-read every 30 s: buildings die and frames are cancelled
	if (ai.frame >= gZbFullAt + 30 * SECOND) {
		gZbFullAt = ai.frame;
		gZbFullPitch.resize(0);
		gZbFullStrip.resize(0);
	}
	CCircuitDef@ def = Catalog::Def(d);
	const float pn = Lattice::FootPitch(gZoneNano);
	const float pb = Lattice::FootPitch(d);
	if (pb < 16.f)
		return false;
	const float reach = Catalog::gBuildDist[gZoneNano] + 0.5f * pb;
	const float halfLen = 0.5f * float(ZONE_LEN) * pn;
	// strips nearest the work first -- but while metal spills, the strip with the most idle turrets (his 10-21 watch:
	// 1,060 m/s of metal and 19,500 e/s spilling beside ~600 idle turrets, nothing in their reach to build)
	array<uint> order;
	array<float> key;
	const AIFloat3 ref = OnMap(near) ? near : gZoneAt[gZoneAt.length() - 1];
	const bool spill = MetalWasting();
	for (uint z = 0; z < gZoneAt.length(); ++z) {
		order.insertLast(z);
		key.insertLast(spill ? -IdleNanoLatheNear(gZoneAt[z]) : gZoneAt[z].distance2D(ref));
	}
	for (uint o = 0; o < order.length(); ++o) {
		uint bi = o;
		for (uint q = o + 1; q < order.length(); ++q)
			if (key[q] < key[bi])
				bi = q;
		const uint z = order[bi];
		order[bi] = order[o];
		key[bi] = key[o];
		bool full = false;
		for (uint f = 0; (f < gZbFullStrip.length()) && !full; ++f)
			full = (gZbFullStrip[f] == int(z)) && (gZbFullPitch[f] == int(pb));
		if (full)
			continue;
		// outward from the strip's middle, row by row: the asker's position strewed the bands along the whole strip.
		// And no further along than the strip's standing turrets reach, plus a slot: the block grows as its line does.
		const float refA = 0.f;
		float loA = 0.f, hiA = 0.f;
		const bool manned = StripExtent(z, loA, hiA);
		int tried = 0;
		for (int j = 0; ; ++j) {
			const float perp = pn + 0.5f * pb + float(j) * pb;
			if (perp > reach)
				break;
			const float span = sqrt(reach * reach - perp * perp);
			const int na = int((halfLen + span) / pb) + 1;
			for (int i = 0; i <= 2 * na; ++i) {
				const int ki = ((i % 2) == 0) ? (i / 2) : -((i + 1) / 2);
				const float a = refA + float(ki) * pb;
				const float lo = manned ? (loA - pn) : -pn;
				const float hi = manned ? (hiA + pn) : pn;
				const float outside = (a < lo) ? (lo - a) : ((a > hi) ? (a - hi) : 0.f);
				if (outside > span)
					continue;
				for (int side = 0; side < 2; ++side) {
					const float sg = (side == 0) ? 1.f : -1.f;
					// tested and built at the same cell: the building's own lattice cell (review: tested snapped, built
					// unsnapped)
					const AIFloat3 c = ai.SnapToLattice(def, gZoneAt[z] + gZoneAcross * a + gZoneBack * (sg * perp));
					if (!OnMap(c) || (++tried > 400))
						continue;
					// TOUCHING (his 10-21: "build all the buildings as close as you can to the turrets. Don't have any
					// spacing"): an outer row only where the cell between it and the strip is taken
					if (j > 0) {
						const AIFloat3 inner = c - gZoneBack * (sg * pb);
						AIFloat3 g2;
						if (ai.CanPlaceCell(def, inner, g2))
							continue;
					}
					AIFloat3 got;
					if (ai.CanPlaceCell(def, c, got)) {
						at = c;
						return true;
					}
				}
			}
		}
		gZbFullStrip.insertLast(int(z));
		gZbFullPitch.insertLast(int(pb));
	}
	// every band full: the next strip, and its band next time
	ZonePlan();
	return false;
}

// A strip slot within maxD of `near` for turret def d -- a plant's turret, which must reach its plant. No strip is
// planned for it.
bool ZoneSlotWithin(int d, const AIFloat3& in near, float maxD, AIFloat3& out at)
{
	if (!ZonesOn() || !NanoDefLike(d) || (gZoneAt.length() == 0) || !OnMap(near))
		return false;
	CCircuitDef@ def = Catalog::Def(d);
	float best = -1.f;
	int bz = -1;
	for (uint z = 0; z < gZoneAt.length(); ++z) {
		for (int k = 0; k < ZONE_SLOTS; ++k) {
			const AIFloat3 s = ZoneSlot(z, k);
			const float dd = s.distance2D(near);
			if ((dd > maxD) || ((best >= 0.f) && (dd >= best)))
				continue;
			AIFloat3 got;
			if (OnMap(s) && ai.CanPlaceCell(def, s, got)) {
				best = dd;
				at = s;
				bz = int(z);
			}
		}
	}
	if (bz < 0) {
		// no strip reaches this plant: plan one along its side, once a plant
		const int pid = PlantIdAt(near);
		if ((pid >= 0) && (gZonePlantDone.find(pid) < 0)) {
			gZonePlantDone.insertLast(pid);
			gZonePlantAsk = near;
			gZoneRetryAt = 0;
			ZonePlan();
		}
		return false;
	}
	++gZoneTaken[uint(bz)];
	return true;
}

// The id of our plant standing at p, -1 with none.
int PlantIdAt(const AIFloat3& in p)
{
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f !is null) && (f.GetPos(ai.frame).distance2D(p) < 96.f))
			return int(f.id);
	}
	return -1;
}

// Half the footprint of the plant standing at p, for a turret's reach to its edge; 0 with none there.
float PlantHalf(const AIFloat3& in p)
{
	const int d = AnchorDefAt(p);
	if (!Catalog::ValidId(d) || (Catalog::gBuildsList[d].length() == 0))
		return 0.f;
	return 8.f * float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]);
}

// The first strip is planned as soon as the anchor stands, before anything else can take its ground.
void ZoneStep()
{
	if (ZonesOn() && (gZoneAt.length() == 0) && !gZoneShut && Base::gAnchorSet && Base::gAnchorFinal
		&& (Factory::gFacUnits.length() > 0))
		ZonePlan();
}

}  // namespace Market
