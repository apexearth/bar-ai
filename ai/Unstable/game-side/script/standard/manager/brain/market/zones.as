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
	if (gZoneShut || !ZoneFrame())
		return false;
	CCircuitDef@ def = Catalog::Def(gZoneNano);
	const float reach = Catalog::gBuildDist[gZoneNano];
	const float pn = Lattice::FootPitch(gZoneNano);
	array<AIFloat3> cand;
	if (gZoneAt.length() == 0) {
		const AIFloat3 home = gFarmSet ? gFarmPos : Base::gAnchor;
		cand.insertLast(home);
		cand.insertLast(home + gZoneBack * reach);
		cand.insertLast(home - gZoneBack * reach);
	} else {
		const AIFloat3 last = gZoneAt[gZoneAt.length() - 1];
		cand.insertLast(last + gZoneBack * (2.f * reach));
		cand.insertLast(last - gZoneBack * (2.f * reach));
		cand.insertLast(last + gZoneAcross * (float(ZONE_LEN) * pn + 2.f * reach));
		cand.insertLast(last - gZoneAcross * (float(ZONE_LEN) * pn + 2.f * reach));
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
	gZoneShut = true;
	AiLog("apex: zone t=" + ai.teamId + " no ground for strip #" + gZoneAt.length());
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

// The first strip is planned as soon as the anchor stands, before anything else can take its ground.
void ZoneStep()
{
	if (ZonesOn() && (gZoneAt.length() == 0) && !gZoneShut && Base::gAnchorSet && Base::gAnchorFinal)
		ZonePlan();
}

}  // namespace Market
