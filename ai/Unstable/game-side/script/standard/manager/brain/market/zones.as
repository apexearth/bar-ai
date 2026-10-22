namespace Market {

// TURRET ZONES (TUNE_ZONES; his 10-21: "I know that I'm going to have long rows of construction turrets. And I say,
// okay, this x-axis between here and here, that's entirely about construction turrets. I'm not going to put anything
// else there."). A strip one turret wide runs behind the anchor along the base's across axis, held for the turret def
// in every site search (C++ zones) from the moment it is planned, built up or not. An eco turret -- bought for a frame,
// for the spill, or flown in -- takes the free strip slot nearest its work as an exact site; every other building
// keeps its own siting, which already seeks standing lathe and now cannot stand on the strip. The next strip is
// planned beside the last, two reaches over so their bands meet, once this one's slots are mostly taken.

const int ZONE_LEN = 20;            // turret slots in a strip
const float ZONE_NEXT_FULL = 0.75f; // share of slots taken that plans the next strip

bool ZonesOn() { return ai.GetTunable("apex_zones", TUNE_ZONES) > 0.f; }

array<AIFloat3> gZoneAt;     // strip centres
array<int> gZoneTaken;       // slots handed out per strip
AIFloat3 gZoneAcross, gZoneBack;
int gZoneNano = -1;
bool gZoneShut = false;
int gZoneRetryAt = 0, gZoneNoGroundLogAt = 0;
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
	return gZoneAt[z] + gZoneAcross * ((float(k) - 0.5f * float(ZONE_LEN - 1)) * pn);
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
	if (gZoneAt.length() > 0) {
		const AIFloat3 last = gZoneAt[gZoneAt.length() - 1];
		cand.insertLast(last + gZoneBack * (2.f * reach));
		cand.insertLast(last - gZoneBack * (2.f * reach));
		cand.insertLast(last + gZoneAcross * (float(ZONE_LEN) * pn + 2.f * reach));
		cand.insertLast(last - gZoneAcross * (float(ZONE_LEN) * pn + 2.f * reach));
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
		const AIFloat3 c = ai.SnapToLattice(def, cand[ci]);
		if (!OnMap(c) || Builder::PastFront(c))
			continue;
		bool clear = true;
		for (uint z = 0; (z < gZoneAt.length()) && clear; ++z)
			clear = gZoneAt[z].distance2D(c) >= 1.5f * reach;
		if (!clear)
			continue;
		// most of the strip must be buildable ground
		int ok = 0;
		AIFloat3 got;
		for (int k = 0; k < ZONE_LEN; k += 2) {
			const AIFloat3 s = c + gZoneAcross * ((float(k) - 0.5f * float(ZONE_LEN - 1)) * pn);
			if (OnMap(s) && ai.CanPlaceCell(def, s, got))
				++ok;
		}
		if (ok * 2 < ZONE_LEN * 3 / 4)
			continue;
		gZoneAt.insertLast(c);
		gZoneTaken.insertLast(0);
		const AIFloat3 a = c - gZoneAcross * (0.5f * float(ZONE_LEN) * pn) - gZoneBack * (0.5f * pn);
		const AIFloat3 b = c + gZoneAcross * (0.5f * float(ZONE_LEN) * pn) + gZoneBack * (0.5f * pn);
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

// The free strip slot nearest `near` (or the newest strip's middle) for turret def d.
bool ZoneSlotFor(int d, const AIFloat3& in near, AIFloat3& out at)
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
	float best = -1.f;
	int bz = -1;
	for (uint z = 0; z < gZoneAt.length(); ++z) {
		for (int k = 0; k < ZONE_LEN; ++k) {
			const AIFloat3 s = ZoneSlot(z, k);
			const float dd = s.distance2D(ref);
			if ((best >= 0.f) && (dd >= best))
				continue;
			AIFloat3 got;
			if (OnMap(s) && ai.CanPlaceCell(def, s, got)) {
				best = dd;
				at = s;
				bz = int(z);
			}
		}
	}
	// the work is out of the strips' reach, or they are full: the next strip when this one is mostly taken
	if ((bz < 0) || (OnMap(near) && (best > Catalog::gBuildDist[d]))) {
		if ((gZoneAt.length() > 0) && (float(gZoneTaken[gZoneAt.length() - 1]) >= ZONE_NEXT_FULL * float(ZONE_LEN)))
			ZonePlan();
		if (bz < 0)
			return false;
		if (OnMap(near) && (best > Catalog::gBuildDist[d]))
			return false;
	}
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
	// strips nearest the work first
	array<uint> order;
	array<float> key;
	const AIFloat3 ref = OnMap(near) ? near : gZoneAt[gZoneAt.length() - 1];
	for (uint z = 0; z < gZoneAt.length(); ++z) {
		order.insertLast(z);
		key.insertLast(gZoneAt[z].distance2D(ref));
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
		const AIFloat3 rel = ref - gZoneAt[z];
		float refA = rel.x * gZoneAcross.x + rel.z * gZoneAcross.z;
		if (refA > halfLen) refA = halfLen;
		if (refA < -halfLen) refA = -halfLen;
		int tried = 0;
		for (int j = 0; ; ++j) {
			const float perp = 0.5f * pn + 0.5f * pb + float(j) * pb;
			if (perp > reach)
				break;
			const float span = sqrt(reach * reach - perp * perp);
			const int na = int((halfLen + span) / pb) + 1;
			for (int i = 0; i <= 2 * na; ++i) {
				const int ki = ((i % 2) == 0) ? (i / 2) : -((i + 1) / 2);
				const float a = refA + float(ki) * pb;
				const float outside = (a < -halfLen) ? (-halfLen - a) : ((a > halfLen) ? (a - halfLen) : 0.f);
				if (outside > span)
					continue;
				for (int side = 0; side < 2; ++side) {
					const AIFloat3 c = gZoneAt[z] + gZoneAcross * a + gZoneBack * ((side == 0) ? perp : -perp);
					if (!OnMap(c) || (++tried > 400))
						continue;
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

// The first strip is planned as soon as the anchor stands, before anything else can take its ground.
void ZoneStep()
{
	if (ZonesOn() && (gZoneAt.length() == 0) && !gZoneShut && Base::gAnchorSet && Base::gAnchorFinal)
		ZonePlan();
}

}  // namespace Market
