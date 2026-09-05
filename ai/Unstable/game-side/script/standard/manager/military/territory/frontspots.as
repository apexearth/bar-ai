namespace Military {

// WHERE THE LINE ACTUALLY SITS. Every reading of the defence telemetry so far has
// had to infer this: a tower measured at 0.03 of the way to the enemy is either a
// placement rule ignoring the front or a front that really is at our doorstep, and
// the two are indistinguishable from the outside.
int gNextFrontLog = 0;
void FrontDiag()
{
	if (ai.frame < gNextFrontLog)
		return;
	gNextFrontLog = ai.frame + 30 * SECOND;
	float lo = 9.f;
	float hi = -9.f;
	float sum = 0.f;
	int uncontested = 0;
	for (uint i = 0; i < gFrontLane.length(); ++i) {
		const float t = gFrontLane[i];
		sum += t;
		if (t < lo) lo = t;
		if (t > hi) hi = t;
		if (t == 0.5f) ++uncontested;
	}
	// IS THE BINDING TELLING THE TRUTH? "There is no safe ground forward" is a
	// strong claim resting entirely on GetBuilderThreatAt, which this repo has
	// already caught reading nonsense once. Raw values along the axis, including
	// our own base, which must read ~0 early or the reading is not what we think.
	string ray = "";
	for (int k = 0; k <= 5; ++k) {
		const float t = 0.1f * float(k);
		const AIFloat3 p = gFrontHome + gFrontFwd * t;
		ray += OnMap(p) ? formatFloat(ai.GetBuilderThreatAt(p), "", 0, 1) : "-";
		ray += " ";
	}
	float safeSum = 0.f;
	float safeMax = 0.f;
	for (uint i = 0; i < gFrontSafe.length(); ++i) {
		safeSum += gFrontSafe[i];
		if (gFrontSafe[i] > safeMax)
			safeMax = gFrontSafe[i];
	}
	const float sn = float(gFrontSafe.length());
	const float n = float(gFrontLane.length());
	AiLog(Factory::T() + "apex: front-diag lanes=" + gFrontLane.length()
		+ " ray[0..0.5]=" + ray
		+ " safeMean=" + formatFloat((sn > 0.f) ? safeSum / sn : 0.f, "", 0, 2)
		+ " safeMax=" + formatFloat(safeMax, "", 0, 2)
		+ " mean=" + formatFloat((n > 0.f) ? sum / n : 0.f, "", 0, 2)
		+ " min=" + formatFloat(lo, "", 0, 2)
		+ " max=" + formatFloat(hi, "", 0, 2)
		+ " uncontested=" + uncontested
		+ " gap=" + formatFloat(FrontLaneGap(), "", 0, 0));

	// THE RING, WHICH IS WHAT ACTUALLY SITES DEFENCE. Everything above describes
	// the LANE scan; FrontLineSpots, FrontCurve and OnBorder all read gRayR, and
	// nothing reported it -- so "the towers are too far up" and "the front is
	// where we think it is" could not be told apart from a log.
	//
	// r/sep is the radius as a share of the home->enemy separation: the fraction
	// of the way to the enemy this line sits at, directly comparable with
	// front-diag's own mean.
	float rSum = 0.f;
	float rMin = -1.f;
	float rMax = 0.f;
	float sSum = 0.f;
	int hotN = 0;
	int metN = 0;
	for (uint i = 0; i < gRayR.length(); ++i) {
		if ((i < gRayMet.length()) && gRayMet[i])
			++metN;
		if ((i >= gRayHot.length()) || !gRayHot[i])
			continue;
		++hotN;
		rSum += gRayR[i];
		if ((rMin < 0.f) || (gRayR[i] < rMin))
			rMin = gRayR[i];
		if (gRayR[i] > rMax)
			rMax = gRayR[i];
		if ((i < gRaySafe.length()) && (gRayR[i] > 1.f))
			sSum += gRaySafe[i] / gRayR[i];
	}
	float axis = sqrt(gFrontFwd.SqLength2D());
	if (axis < 1.f)
		axis = 1.f;
	const float hn = float((hotN > 0) ? hotN : 1);
	AiLog(Factory::T() + "apex: ring-diag rays=" + hotN + "/" + gRayR.length()
		+ " contested=" + metN
		+ " sep=" + int(axis)
		+ " r/sep mean=" + formatFloat(rSum / hn / axis, "", 0, 2)
		+ " min=" + formatFloat(((rMin < 0.f) ? 0.f : rMin) / axis, "", 0, 2)
		+ " max=" + formatFloat(rMax / axis, "", 0, 2)
		+ " safe/r=" + formatFloat(sSum / hn, "", 0, 2)
		+ " bar=" + int(gRingAllyBar) + "/" + int(gRingFoeBar)
		+ " sector=" + gRaySector);

	GhostDiag();
}

// HOW MUCH OF THE ENEMY ARMY WE ARE COUNTING IS A MEMORY. The gap between the
// raw sum and the fresh one is everything we saw once and have not seen since.
// EnemyCostOf consumes it at apex_ghost_weight, so this is the input to every
// posture, threat and tech gate rather than a spectator.
void GhostDiag()
{
	const float raw = aiEnemyMgr.GetEnemyCost(Unit::Role::ASSAULT.type)
	                + aiEnemyMgr.GetEnemyCost(Unit::Role::RAIDER.type)
	                + aiEnemyMgr.GetEnemyCost(Unit::Role::RIOT.type)
	                + aiEnemyMgr.GetEnemyCost(Unit::Role::SKIRM.type);
	const float fresh = aiEnemyMgr.GetEnemyCostFresh(Unit::Role::ASSAULT.type)
	                  + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::RAIDER.type)
	                  + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::RIOT.type)
	                  + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::SKIRM.type);
	AiLog(Factory::T() + "apexfoe: raw=" + int(raw)
		+ " fresh=" + int(fresh)
		+ " ghost%=" + int((raw > 1.f) ? (raw - fresh) * 100.f / raw : 0.f)
		+ " w=" + formatFloat(ai.GetTunable("apex_ghost_weight", TUNE_GHOST_WEIGHT), "", 0, 2));
}

// Which lane a position falls in, and how far along the axis it sits.
int LaneOf(const AIFloat3& in pos)
{
	const AIFloat3 d = pos - gFrontHome;
	const float off = d.x * gFrontSide.x + d.z * gFrontSide.z;
	int lane = int(off / FrontLaneGap() + (off >= 0.f ? 0.5f : -0.5f));
	if (lane < -FRONT_LANES)
		lane = -FRONT_LANES;
	if (lane > FRONT_LANES)
		lane = FRONT_LANES;
	return lane + FRONT_LANES;   // into array space
}

// Where the front sits in THIS position's lane, as a fraction along home->enemy.
float FrontFractionAt(const AIFloat3& in pos)
{
	RebuildFront();
	if (!gFrontValid || (gFrontLane.length() == 0))
		return 0.5f;
	return gFrontLane[LaneOf(pos)];
}

// The whole line, for callers that want the shape rather than one answer.
// THE FRONT LINE ITSELF: where our territory ends, per contested bearing.
//
// This is a statement about the battlefield, and it is what gets DRAWN. It is
// NOT a list of places to build -- conflating the two once showed build spots
// (clamped to the safe edge, dropping most bearings) instead of the front, so
// the drawn line was a few stubs near the base rather than the actual front.
bool FrontCurve(array<AIFloat3>& out pts)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid)
		return false;
	for (uint i = 0; i < gRayR.length(); ++i) {
		// CONTESTED, not merely held. gRayHot is true wherever we own ground,
		// which is every forward bearing around our own base -- drawing that
		// traced our territory boundary as a ring, off the map edge included.
		if ((i < gRayMet.length()) && !gRayMet[i])
			continue;   // nobody is out on this bearing: it is not a front
		const float ang = 6.2831853f * float(i) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		const AIFloat3 p = gFrontHome + dir * gRayR[i];
		if (OnMap(p))
			pts.insertLast(p);
	}
	return pts.length() > 0;
}

// A CONTINUOUS LINE, SPACED BY WHAT A TURRET CAN ACTUALLY SHOOT.
//
// Sample the arc at intervals of the turret's OWN weapon range, so a raider
// cannot pass between two of them. The spacing is read from the def via
// GetMaxRange rather than guessed -- the old FRONT_FENCE_SPREAD was a flat 700
// for an armllt that reaches 430 and a Rattlesnake that reaches much further,
// which leaves a hole in one case and wastes metal in the other.
//
// Sampling the ARC rather than the bearings is the point: 24 fixed bearings put
// points 785 elmos apart at radius 3000 and 130 apart at radius 500, so the same
// ring is full of holes far out and stacked up close. Arc length is the honest
// unit for "no gaps".
// EXTRA DENSITY AT THE MAP EDGE, DERIVED RATHER THAN GUESSED. A point deep in
// the interior is engaged from all sides; a point at the map edge only from
// the interior side, so it needs denser cover to match.
//
// The geometry is exact. A point on the line is engaged by every turret within
// range R OF IT ALONG THE LINE. In the interior that is a span of 2R -- R of
// line on each side. Within d < R of the map edge only min(R, d) of line exists
// on the outward side, because there is no map to put turrets on, so the
// covering span falls to R + min(R, d) -- as little as HALF, hard against the
// edge. Restoring equal cover means shrinking the spacing by that same ratio:
//
//     spacing(d) = spacing * (R + min(R, d)) / 2R
//
// 0.5x at the edge (double the turret density), 1.0x once a full turret range
// inland, linear between. Nothing is invented here: R is the very range the
// caller already spaced the line by, and the factor is the coverage deficit it
// is correcting.
float EdgeSpacing(const AIFloat3& in at, float spacing, float reach)
{
	if (reach < 1.f)
		return spacing;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	float d = at.x;
	if (at.z < d)      d = at.z;
	if (w - at.x < d)  d = w - at.x;
	if (h - at.z < d)  d = h - at.z;
	if (d < 0.f)       d = 0.f;
	if (d > reach)     d = reach;
	return spacing * (reach + d) / (2.f * reach);
}

// HOW MUCH OF THE APPROACH IS EVEN REACHABLE -- the share of the bearings an
// attacker could stand on that are actually map.
//
// EdgeSpacing's deficit does NOT invert into a value. Spacing answers "this
// point is on a line we have already decided to hold, and fewer turrets can
// reach it", which is true at a wall. Value answers "should we hold this ground
// at all", and at a wall the answer is that half the attacks cannot come:
// EdgeExposure returned 1/EdgeSpacing, i.e. up to 2.0 hard against the map
// edge, so a turret was worth DOUBLE exactly where nothing can attack from.
// With a base 575 elmos off the west wall and turrets reaching 450-700, that
// premium covered the whole rear of the base and none of the enemy side
// (apexearth, watched: "defenses in the back of our base... the opposite of
// where they should be").
//
// LineClosure already states the rule this uses -- a bearing that runs off the
// map is closed, the edge is the wall. Same geometry, read with the sign that
// matches the question.
const int OPEN_RAYS = 8;
float OpenFraction(const AIFloat3& in at, float reach)
{
	// The attacker's own standoff is the radius it can stand at, the same
	// radius CoverAt asks its ring on; before we have seen them, the turret's
	// reach is the honest stand-in.
	float standoff = FoeReach();
	if (standoff < 1.f)
		standoff = reach;
	if (standoff < 1.f)
		return 1.f;
	int open = 0;
	for (int b = 0; b < OPEN_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(OPEN_RAYS);
		if (OnMap(at + AIFloat3(cos(ang), 0.f, sin(ang)) * standoff))
			++open;
	}
	return float(open) / float(OPEN_RAYS);
}

// Memo: the spot list for one (spacing, reach) pair on the same 30-frame stamp
// RebuildFront already uses. Decide re-asks this several times a second per
// player and the fill loop was a top term in the 44-66% AI frame share
// measured live; the front does not move inside a stamp.
array<AIFloat3> gSpotsMemo;
bool  gSpotsMemoOk = false;
int   gSpotsMemoStamp = -1;
float gSpotsMemoSpacing = -1.f;
float gSpotsMemoReach = -1.f;

bool FrontLineSpots(array<AIFloat3>& out pts, float spacing, float reach = 0.f)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid || (spacing < 1.f))
		return false;
	if ((gSpotsMemoStamp == gFrontStamp) && (gSpotsMemoSpacing == spacing)
		&& (gSpotsMemoReach == reach))
	{
		pts = gSpotsMemo;
		return gSpotsMemoOk;
	}
	const float back = ai.GetTunable("apex_front_setback", TUNE_FRONT_SETBACK);
	const bool useSafe = ai.GetTunable("apex_front_safe_edge", TUNE_FRONT_SAFE_EDGE) > 0.f;
	const float minReach = ai.GetTunable("apex_front_min_reach", TUNE_FRONT_MIN_REACH);
	const float step = 6.2831853f / float(FRONT_RAYS);

	for (uint i = 0; i < gRayR.length(); ++i) {
		if (!RayFacesFront(i))
			continue;
		const uint j = (i + 1) % gRayR.length();
		const bool pairHot = RayFacesFront(j);

		// This bearing's buildable radius, and the next one's, so the segment
		// between them can be filled at the requested spacing.
		float d0 = gRayR[i] * (1.f - back);
		if (useSafe && (i < gRaySafe.length()) && (gRaySafe[i] < d0))
			d0 = gRaySafe[i];
		if ((d0 <= 0.f) || (d0 < gRayR[i] * (1.f - back) * minReach))
			continue;
		float d1 = d0;
		if (pairHot) {
			d1 = gRayR[j] * (1.f - back);
			if (useSafe && (j < gRaySafe.length()) && (gRaySafe[j] < d1))
				d1 = gRaySafe[j];
			if (d1 <= 0.f)
				d1 = d0;
		}

		// How many turrets this segment of arc needs to be gap-free -- at the
		// spacing this part of the line needs, which is tighter near the map edge.
		// See EdgeSpacing.
		const float arc = step * ((d0 + d1) * 0.5f);
		const float midAng = 6.2831853f * (float(i) + 0.5f) / float(FRONT_RAYS);
		const AIFloat3 mid = gFrontHome
				+ AIFloat3(cos(midAng), 0.f, sin(midAng)) * ((d0 + d1) * 0.5f);
		const float useSpacing = EdgeSpacing(mid, spacing, reach);
		int n = int(arc / ((useSpacing > 1.f) ? useSpacing : spacing));
		if (n < 1)
			n = 1;
		for (int k = 0; k < n; ++k) {
			const float t = float(k) / float(n);
			const float ang = 6.2831853f * (float(i) + t) / float(FRONT_RAYS);
			const float d = d0 + (d1 - d0) * t;
			const AIFloat3 p = gFrontHome
					+ AIFloat3(cos(ang), 0.f, sin(ang)) * d;
			if (OnMap(p))
				pts.insertLast(p);
		}
	}
	gSpotsMemo = pts;
	gSpotsMemoOk = pts.length() > 0;
	gSpotsMemoStamp = gFrontStamp;
	gSpotsMemoSpacing = spacing;
	gSpotsMemoReach = reach;
	return gSpotsMemoOk;
}

// WHERE A TOWER COVERING THAT LINE CAN ACTUALLY GO.
//
// Derived from the line, and different from it in three ways, each measured:
// pulled back by the setback so the builder is not parked in the fight; clamped
// to ground whose builder threat the engine's site search will accept, because
// past that the order is never staffed at all; and dropped entirely on bearings
// where that workable ground does not reach a decent share of the way out --
// otherwise every bearing collapses to the same short radius and the ring
// degenerates into a heap of turrets outside the base.
// A NET AROUND THE BASE, WITH FALLBACKS DEEPER IN.
//
// gRayR already describes our perimeter on 24 bearings, but FrontBuildSpots
// offers only the HOT ones -- a picket facing wherever we last saw someone,
// not a ring (apexearth: "a 'net' of defenses *around* our base rather than
// just in the center of it... with some fallbacks deeper in").
//
// Two differences. Every bearing is offered, so the net closes all the way
// round. And each bearing is offered at LAYERS stepping inward, so a leak
// through the outer ring meets another behind it.
//
// denyR is the radius a turret actually DENIES: its own weapon range minus the
// standoff an attacker shoots from (see Market::CoverAt). Everything else falls
// out of it -- posts sit 2*denyR apart so their denied discs just touch, and
// layers sit 2*denyR deep for the same reason. So the spacing, the layer count
// and the depth of the net are all consequences of one measured quantity; no
// ring count is chosen anywhere. A turret that cannot out-reach the attacker
// has denyR <= 0 and earns no net at all, which is the correct answer.
array<AIFloat3> gNetMemo;
bool  gNetMemoOk = false;
int   gNetMemoStamp = -1;
float gNetMemoDeny = -1.f;

bool NetSpots(array<AIFloat3>& out pts, float denyR)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid || (denyR < 1.f))
		return false;
	if ((gNetMemoStamp == gFrontStamp) && (gNetMemoDeny == denyR)) {
		pts = gNetMemo;
		return gNetMemoOk;
	}
	const float back = ai.GetTunable("apex_front_setback", TUNE_FRONT_SETBACK);
	const bool useSafe = ai.GetTunable("apex_front_safe_edge", TUNE_FRONT_SAFE_EDGE) > 0.f;
	const float step = 6.2831853f / float(FRONT_RAYS);
	const float pitch = 2.f * denyR;
	for (uint i = 0; i < gRayR.length(); ++i) {
		// The net never asked which way the bearing faced, so it layered rings
		// inward on all 24 and filled our own rear with posts. Only the rear
		// ray's safe edge of 0 kept them off the map's far side, and only while
		// apex_front_safe_edge stays on.
		if (!RayFacesFront(i))
			continue;
		float d0 = gRayR[i] * (1.f - back);
		if (useSafe && (i < gRaySafe.length()) && (gRaySafe[i] < d0))
			d0 = gRaySafe[i];
		if (d0 <= 0.f)
			continue;
		// Outward ring first, then fall back toward home a full denied
		// diameter at a time until the layers meet the core.
		for (float r = d0; r > denyR; r -= pitch) {
			const float midAng = 6.2831853f * (float(i) + 0.5f) / float(FRONT_RAYS);
			const AIFloat3 mid = gFrontHome
					+ AIFloat3(cos(midAng), 0.f, sin(midAng)) * r;
			const float sp = EdgeSpacing(mid, pitch, denyR);
			const float arc = step * r;
			int n = int(arc / ((sp > 1.f) ? sp : pitch));
			if (n < 1)
				n = 1;
			for (int k = 0; k < n; ++k) {
				const float t = float(k) / float(n);
				const float ang = 6.2831853f * (float(i) + t) / float(FRONT_RAYS);
				const AIFloat3 p = gFrontHome
						+ AIFloat3(cos(ang), 0.f, sin(ang)) * r;
				if (OnMap(p))
					pts.insertLast(p);
			}
		}
	}
	gNetMemo = pts;
	gNetMemoOk = pts.length() > 0;
	gNetMemoStamp = gFrontStamp;
	gNetMemoDeny = denyR;
	return gNetMemoOk;
}

bool FrontBuildSpots(array<AIFloat3>& out pts)
{
	RebuildFront();
	pts.resize(0);
	if (!gFrontValid)
		return false;
	const float back = ai.GetTunable("apex_front_setback", TUNE_FRONT_SETBACK);
	const bool useSafe = ai.GetTunable("apex_front_safe_edge", TUNE_FRONT_SAFE_EDGE) > 0.f;
	const float minReach = ai.GetTunable("apex_front_min_reach", TUNE_FRONT_MIN_REACH);
	for (uint i = 0; i < gRayR.length(); ++i) {
		if (!RayFacesFront(i))
			continue;
		const float ang = 6.2831853f * float(i) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		const float line = gRayR[i] * (1.f - back);
		float d = line;
		if (useSafe && (i < gRaySafe.length()) && (gRaySafe[i] < d))
			d = gRaySafe[i];
		if ((d <= 0.f) || (d < line * minReach))
			continue;
		const AIFloat3 p = gFrontHome + dir * d;
		if (OnMap(p))
			pts.insertLast(p);
	}
	return pts.length() > 0;
}


// The crossing directly ahead, kept for callers that want a single point.
bool FrontLinePos(AIFloat3& out p)
{
	RebuildFront();
	if (!gFrontValid)
		return false;
	p = gFrontHome + gFrontFwd * FrontFractionAt(gFrontHome);
	return OnMap(p);
}

// On the line, or past it. A tower behind the crossing is defending ground
// nobody is contesting.
bool OnBorder(const AIFloat3& in pos)
{
	RebuildFront();
	if (!gFrontValid || (gRayR.length() == 0))
		return false;
	// Against the ring's radius on THIS position's bearing. The band is a share
	// of that radius rather than a fixed distance, so it means the same thing on
	// a small map and a large one.
	const float band = ai.GetTunable("apex_front_band", TUNE_FRONT_BAND);
	const int r = RayOf(pos);
	const float here = pos.distance2D(gFrontHome);
	return here >= (gRayR[r] * (1.f - band));
}


// What the enemy's mobile army is WORTH, in metal.
//

}  // namespace Military
