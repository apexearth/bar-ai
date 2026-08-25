namespace Market {
// The nano FARM -- a PLANNED spot, not wherever the first nano landed
// (apexearth 2026-08-23: "we should ahead of time know generally some
// really good spots to build the economy... as far away from any active
// threat as we can"). The base frame's axis points at the front, so the
// farm sits BEHIND the anchor; the frame follows the frontline senses, so
// "behind" is already "away from influence".
AIFloat3 gFarmPos;
bool gFarmSet = false;

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

// The farm's SLOT PLAN. Random shake around one anchor scattered eco in
// staggered diagonals (apexearth's screenshot, 2026-08-23: "some of the
// buildings are just slightly off"). Each def gets rows of flush slots:
// pitch = footprint rounded up to the 16-elmo lattice (odd-celled defs get
// their unavoidable half-cell gap), rows stack rearward, columns run along
// the base's across axis. The cursor never reuses a slot; a failed build
// leaves a hole, never an overlap.
// How wide one row of the farm runs before the next stacks behind it. A wide
// row is a LINE, and a line is walked end to end; the same slots in a narrower
// row make a block, where the next slot is always adjacent to the last
// (apexearth: "those winds are a little bit too far on both sides, so we have
// to walk - should make tighter, less walking").
float FarmRowW()
{
	const float w = ai.GetTunable("apex_farm_row_w", TUNE_FARM_ROW_W);
	return (w > 64.f) ? w : 64.f;
}
array<int> gFRowDef;      // row -> def id
array<int> gFRowNext;     // row -> next column index
array<float> gFRowPitch;  // row -> slot pitch (elmos)
array<float> gFRowZ;      // row -> rearward offset of the row's center line
float gFarmDepth = 0.f;   // next free rearward offset

float PitchOf(int defId)
{
	int side = 1;
	while (side * side < Catalog::gAreaCells[defId])
		++side;
	// Odd-celled footprints cannot sit flush on the 16-lattice; round up.
	if ((side & 1) == 1)
		++side;
	return float(side) * 16.f;
}

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
int gInsAt = 0;
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

AIFloat3 FarmSlot(int defId)
{
	const float pitch = PitchOf(defId);
	int row = -1;
	for (uint i = 0; i < gFRowDef.length(); ++i) {
		if ((gFRowDef[i] == defId)
			&& (float(gFRowNext[i]) * pitch < FarmRowW()))
		{
			row = int(i);
			break;
		}
	}
	if (row < 0) {
		gFRowDef.insertLast(defId);
		gFRowNext.insertLast(0);
		gFRowPitch.insertLast(pitch);
		gFRowZ.insertLast(gFarmDepth + pitch * 0.5f);
		row = int(gFRowDef.length()) - 1;
		gFarmDepth += pitch;
	}
	// Skip slots that would stand on a metal spot (cursor advances; the
	// hole stays a hole).
	for (int tries = 0; tries < 8; ++tries) {
		const int col = gFRowNext[row];
		gFRowNext[row] = col + 1;
		// Columns fill ACROSS the row, offset so the finished row is still
		// centered on the axis. Alternating outward (0, -p, +p, -2p, +2p...)
		// centered it just as well but put every consecutive slot on the far
		// side of the block from the last one, so the builder crossed the
		// whole farm for every turbine (apexearth, watching: "our commander
		// keeps flip flopping to opposite sides to build these winds").
		const int cols = (pitch > 0.f) ? int(FarmRowW() / pitch) : 1;
		const float lat = (float(col) - float((cols > 1) ? (cols - 1) : 0) * 0.5f)
				* pitch;
		AIFloat3 p = gFarmPos + Base::gAcross * lat - Base::gFwd * gFRowZ[row];
		if (!NearSpot(p))
			return p;
	}
	return gFarmPos - Base::gFwd * gFarmDepth;
}

// Factory ground: the REAR FLANK of the farm block (apexearth: T2 labs
// "further in the back of our base area", and the vehicle lab needs room
// in front of it -- packed interior blocked its exit). Beside the farm,
// behind the base, lateral ground open for roll-out; flanks alternate.
int gPlantFlank = 0;
// THE MASS CENTRE OF WHAT WE OWN, and how far our stuff reaches from it.
//
// apexearth: "Figure out what the mass center of our base is - compute that
// x/y and then place our defenses towards the enemy base/start box. ensure our
// sides are also covered." Weighted by metal, so the centre sits where the
// value is rather than on the start position, and it MOVES as the base grows.
bool BaseCentroid(AIFloat3& out c, float& out extent)
{
	float wsum = 0.f;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < gLPos.length(); ++i) {
		if (gLExtract[i] <= 0.f)
			continue;
		const float w = 620.f;   // an extractor's own footprint of value
		cx += gLPos[i].x * w; cz += gLPos[i].z * w; wsum += w;
	}
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if (gOwnBig[i] is null) continue;
		const AIFloat3 p = gOwnBig[i].GetPos(ai.frame);
		const float w = Catalog::gCostM[int(gOwnBig[i].circuitDef.id)];
		cx += p.x * w; cz += p.z * w; wsum += w;
	}
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null) continue;
		const AIFloat3 p = gOwnGen[i].GetPos(ai.frame);
		const float w = Catalog::gCostM[int(gOwnGen[i].circuitDef.id)];
		cx += p.x * w; cz += p.z * w; wsum += w;
	}
	if (wsum <= 1.f)
		return false;
	c = AIFloat3(cx / wsum, 0.f, cz / wsum);
	if (!OnMap(c))
		return false;
	// How far the base actually reaches, so the ring sits just outside it
	// instead of at some radius nobody chose.
	extent = 0.f;
	for (uint i = 0; i < gLPos.length(); ++i) {
		if (gLExtract[i] <= 0.f) continue;
		const float dd = c.distance2D(gLPos[i]);
		if (dd > extent) extent = dd;
	}
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null) continue;
		const float dd = c.distance2D(gOwnGen[i].GetPos(ai.frame));
		if (dd > extent) extent = dd;
	}
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if (gOwnBig[i] is null) continue;
		const float dd = c.distance2D(gOwnBig[i].GetPos(ai.frame));
		if (dd > extent) extent = dd;
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

AIFloat3 InteriorSite(const AIFloat3& in fallback)
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
		gPlantFlank = 1 - gPlantFlank;
		const float side = (gPlantFlank == 0) ? 1.f : -1.f;
		const AIFloat3 back = Base::gFwd * (gFarmDepth * 0.5f);
		const AIFloat3 lat = Base::gAcross * (FarmRowW() * 0.5f + 300.f);
		AIFloat3 pA = gFarmPos + lat * side - back;
		AIFloat3 pB = gFarmPos - lat * side - back;
		const bool okA = OnMap(pA);
		const bool okB = OnMap(pB);
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
		gPlantFlank = 1 - gPlantFlank;
		const float side2 = (gPlantFlank == 0) ? 1.f : -1.f;
		AIFloat3 a = Base::gAnchor
				+ Base::gAcross * (side2 * (FarmRowW() * 0.5f + 300.f))
				- Base::gFwd * 300.f;
		if (OnMap(a))
			return a;
		a = Base::gAnchor - Base::gAcross * (side2 * (FarmRowW() * 0.5f + 300.f))
				- Base::gFwd * 300.f;
		if (OnMap(a))
			return a;
	}
	if (Base::gAnchorSet && OnMap(Base::gAnchor))
		return Base::gAnchor;
	return fallback;
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

// THE WORST-SERVED WORKING LINE, and how short of hands it is. Same
// arithmetic as UnservedLineSpend, but it keeps the position: a nano bought to
// serve a factory has to STAND at that factory. It was sited at the eco farm,
// which is behind the anchor and outside assist reach, so line-demand nanos
// could never touch the line that priced them.
float NeediestLine(AIFloat3& out at)
{
	float worst = 0.f;
	const float per = LineSpend();
	float sumCeil = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if ((Factory::gFacUnits[fi] !is null)
			&& (Factory::gFacUnits[fi].CountQueued(null) > 0))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.CountQueued(null) == 0))
			continue;
		const float share = (sumCeil > 1.f)
				? (per * float(Factory::gFactoryCount) * LineCostCeil(f) / sumCeil)
				: per;
		const AIFloat3 fp = f.GetPos(ai.frame);
		if (!OnMap(fp))
			continue;
		int nanosNear = 0;
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
				++nanosNear;
		}
		const float u = share - float(nanosNear) * 17.5f;
		if (u > worst) {
			worst = u;
			at = fp;
		}
	}
	return worst;
}

// A working line at all, worst-served first -- the site an ARMY shortfall
// wants a lathe at even when the line's own spend is already served.
bool AnyLineSite(AIFloat3& out at)
{
	float fewest = -1.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (f is null)
			continue;
		const AIFloat3 fp = f.GetPos(ai.frame);
		if (!OnMap(fp))
			continue;
		float nanosNear = 0.f;
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
				nanosNear += 1.f;
		}
		if ((fewest < 0.f) || (nanosNear < fewest)) {
			fewest = nanosNear;
			at = fp;
		}
	}
	return fewest >= 0.f;
}

float UnservedLineSpend()
{
	float unserved = 0.f;
	const float per = LineSpend();
	float sumCeil = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		if ((Factory::gFacUnits[fi] !is null)
			&& (Factory::gFacUnits[fi].CountQueued(null) > 0))
			sumCeil += LineCostCeil(Factory::gFacUnits[fi]);
	}
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.CountQueued(null) == 0))
			continue;
		const float share = (sumCeil > 1.f)
				? (per * float(Factory::gFactoryCount) * LineCostCeil(f) / sumCeil)
				: per;
		int nanosNear = 0;
		const AIFloat3 fp = f.GetPos(ai.frame);
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
				++nanosNear;
		}
		const float u = share - float(nanosNear) * 17.5f;
		if (u > 0.f)
			unserved += u;
	}
	return unserved;
}


}  // namespace Market
