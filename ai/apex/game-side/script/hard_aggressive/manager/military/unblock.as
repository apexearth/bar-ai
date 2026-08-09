namespace Military {

//------------------------------------------------------------------------------
// UNITS WALLED IN BY OUR OWN BUILDINGS.
//
// apexearth: "we need to detect units that are blocked and reclaim cheapest
// buildings we can to unblock their movement. This often happens in late game
// where units are completely locked into an area and cannot move outside.
// Usually theres just 1 or 2 buildings in the way."
//
// Why nothing already catches this:
//
//  - CircuitAI's own reachability test is CTerrainManager::CanMoveToPos, which
//    reads the areas CTerrainData computes from SLOPE AND DEPTH. Structures are
//    not in it. A pocket sealed by four solars is, to every piece of CircuitAI's
//    routing, open ground -- so the unit is given a destination it cannot reach
//    and keeps trying.
//  - Nothing enumerates friendly units either, so "who has not moved" cannot be
//    asked without keeping the register below.
//
// The oracle is the ENGINE's path manager, reached through
// ai.GetPathLength(unit, to) (CAICallback::GetPathLength -> pathManager->
// RequestPath). That one reads the synced blocking map, buildings included.
//
// Detection is deliberately in three stages, each one cheap enough to gate the
// next:
//   1. the unit has not moved for UNBLOCK_STILL         -- free, a position read
//   2. our own structures are packed around it          -- one array walk
//   3. every direction out of it fails a path query     -- 8 engine searches
// Stage 3 is the only expensive one and it runs for at most one unit at a time,
// no more often than UNBLOCK_PROBE_PERIOD.
//
// Standing still is NOT enough on its own: a defend squad parked on the line is
// motionless for minutes at a time and is exactly where it should be. Failing
// every exit is what separates them.
const int   UNBLOCK_STILL     = 45 * SECOND;  // motionless this long -> candidate
const int   UNBLOCK_RECHECK   = 15 * SECOND;  // ...then again, after a clearing
const float UNBLOCK_EPS       = 48.f;   // movement under this is standing still
const int   UNBLOCK_SAMPLE    = 24;     // units whose position is read per tick
const float UNBLOCK_RING      = 700.f;  // how far out an exit has to reach
const int   UNBLOCK_RAYS      = 8;      // directions probed around the unit
// A path that reaches the ring is at least the straight line long; a search that
// stops against a wall comes back SHORT, not long. Both bounds are therefore
// failures, and the short one is the one a pen actually produces.
const float UNBLOCK_MIN_RATIO = 0.90f;
const float UNBLOCK_MAX_RATIO = 3.00f;
// A wall has to be made of something. Below this many structures of ours in the
// ring there is nothing to blame and the unit is held by terrain, which
// reclaiming cannot fix.
const int   UNBLOCK_MIN_WALL  = 4;
const float UNBLOCK_CORRIDOR  = 96.f;   // half-width of the lane a unit needs
const int   UNBLOCK_PROBE_PERIOD = 3 * SECOND;
const int   UNBLOCK_ORDER_PERIOD = 10 * SECOND;
// Never eat something expensive to answer this. A solar is 155, a wind ~40, a
// T1 tower 100-350, a converter ~700. Anything dearer is a reactor, a lab or a
// T2/T3 gun, and a walled-in squad is not worth one.
const float UNBLOCK_MAX_COST  = 800.f;

// The register. Ids, not handles: CCircuitUnit is registered NOCOUNT, so a
// stored handle is not nulled when the engine destroys the unit and `is null`
// reads false on freed memory. ai.GetTeamUnit re-resolves it safely.
array<Id>       gPenId;
array<AIFloat3> gPenPos;     // where it was when last read
array<int>      gPenMoved;   // frame it was last seen to have moved
uint gPenCursor = 0;
int  gNextProbe = 0;
int  gNextUnblockOrder = 0;
int  gUnblockOrders = 0;
int  gPennedSeen = 0;
// Structures we have already ordered cleared. CBuilderManager::Enqueue hands
// back the EXISTING task when a target is already marked, so without this the
// same building is re-picked every period and the rate limit is spent on a task
// that already exists -- the same trap Builder::gReclaimAsked exists for.
array<Id> gUnblockAsked;

bool UnblockOn()
{
	return ai.GetTunable("apex_unblock", 1.f) > 0.f;
}

// Ground units only. A flyer is never walled in, and ai.GetPathLength has no
// move type to answer with for one -- it returns -1, which reads here as
// "no way out" and would fire on every aircraft we own.
void NotePenned(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	if ((cdef is null) || !cdef.IsMobile() || cdef.IsAbleToFly())
		return;
	gPenId.insertLast(unit.id);
	gPenPos.insertLast(unit.GetPos(ai.frame));
	gPenMoved.insertLast(ai.frame);
}

void ForgetPenned(Id id)
{
	for (uint i = 0; i < gPenId.length(); ++i) {
		if (gPenId[i] == id) {
			gPenId.removeAt(i);
			gPenPos.removeAt(i);
			gPenMoved.removeAt(i);
			return;
		}
	}
}

bool UnblockAsked(Id id)
{
	for (uint i = 0; i < gUnblockAsked.length(); ++i) {
		if (gUnblockAsked[i] == id)
			return true;
	}
	return false;
}

// Can this unit reach anywhere UNBLOCK_RING away? One ray is enough: a unit that
// can get out in one direction is not penned, whatever it is doing standing
// still. `outDir` returns the ray that came closest to working, which is where
// the wall we want to eat stands.
bool HasWayOut(CCircuitUnit@ unit, const AIFloat3& in at, AIFloat3& out outDir)
{
	float bestReach = -1.f;
	AIFloat3 bestDir(0.f, 0.f, 0.f);
	for (int k = 0; k < UNBLOCK_RAYS; ++k) {
		const float a = 6.2831853f * float(k) / float(UNBLOCK_RAYS);
		AIFloat3 dir(cos(a), 0.f, sin(a));
		const AIFloat3 probe = at + dir * UNBLOCK_RING;
		if (!OnMap(probe))
			continue;
		const float len = ai.GetPathLength(unit, probe);
		if ((len >= UNBLOCK_RING * UNBLOCK_MIN_RATIO)
			&& (len <= UNBLOCK_RING * UNBLOCK_MAX_RATIO))
			return true;
		// A partial path stops against whatever stopped it. The ray that got
		// furthest is the thinnest part of the wall.
		if (len > bestReach) {
			bestReach = len;
			bestDir = dir;
		}
	}
	outDir = bestDir;
	return false;
}

// The cheapest thing of OURS standing in the lane the unit would leave by.
//
// Never a mex (the metal spot is the reason the base is here), never a factory
// or a nano (IsBuilder covers both -- eating what produces the unit to free the
// unit is not a trade), never anything dear.
CCircuitUnit@ WallToEat(const AIFloat3& in at, const AIFloat3& in dir, int& out wallCount)
{
	wallCount = 0;
	array<CCircuitUnit@>@ structs = ai.GetOwnStructsNear(at, UNBLOCK_RING);
	if (structs is null)
		return null;
	wallCount = int(structs.length());

	CCircuitUnit@ pick = null;
	float bestCost = -1.f;
	for (uint i = 0; i < structs.length(); ++i) {
		CCircuitUnit@ s = structs[i];
		if (s is null)
			continue;
		const CCircuitDef@ sdef = s.circuitDef;
		if ((sdef is null) || sdef.IsMex() || sdef.IsBuilder())
			continue;
		if (sdef.costM > UNBLOCK_MAX_COST)
			continue;
		if (UnblockAsked(s.id))
			continue;
		// In the lane: ahead of the unit along `dir`, and within a corridor wide
		// enough to walk down.
		const AIFloat3 rel = s.GetPos(ai.frame) - at;
		const float along = rel.x * dir.x + rel.z * dir.z;
		if (along <= 0.f)
			continue;
		const float across = abs(rel.x * dir.z - rel.z * dir.x);
		if (across > UNBLOCK_CORRIDOR)
			continue;
		if ((bestCost < 0.f) || (sdef.costM < bestCost)) {
			bestCost = sdef.costM;
			@pick = s;
		}
	}
	return pick;
}

// Returns true when a clearing order went out, so the caller can hold this unit
// off for UNBLOCK_RECHECK rather than immediately asking for a second building.
bool TryUnblock(CCircuitUnit@ unit, const AIFloat3& in at)
{
	AIFloat3 dir;
	if (HasWayOut(unit, at, dir))
		return false;
	if (dir.SqLength2D() < NEAR_ZERO)
		return false;   // every ray was off-map; nothing to reason about

	++gPennedSeen;
	int wall = 0;
	CCircuitUnit@ eat = WallToEat(at, dir, wall);
	if (wall < UNBLOCK_MIN_WALL)
		return false;   // held by terrain, not by us
	if (eat is null)
		return false;

	IUnitTask@ task = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, eat));
	if (task is null)
		return false;

	gUnblockAsked.insertLast(eat.id);
	if (gUnblockAsked.length() > 64)
		gUnblockAsked.removeAt(0);
	gNextUnblockOrder = ai.frame + UNBLOCK_ORDER_PERIOD;
	++gUnblockOrders;
	AiLog(Factory::T() + "apex: unblock " + unit.circuitDef.GetName() + " #" + unit.id
		+ " walled in (" + wall + " of ours in the ring) -> reclaim "
		+ eat.circuitDef.GetName() + " #" + eat.id
		+ " cost=" + formatFloat(eat.circuitDef.costM, "", 0, 0)
		+ " (order " + gUnblockOrders + " of " + gPennedSeen + " penned)");
	return true;
}

void UpdateUnblock()
{
	if (!UnblockOn() || (gPenId.length() == 0))
		return;

	const int frame = ai.frame;
	uint scan = gPenId.length();
	if (scan > uint(UNBLOCK_SAMPLE))
		scan = uint(UNBLOCK_SAMPLE);

	for (uint k = 0; k < scan; ++k) {
		if (gPenId.length() == 0)
			return;   // the drop below can empty it mid-walk
		if (gPenCursor >= gPenId.length())
			gPenCursor = 0;
		const uint i = gPenCursor;
		CCircuitUnit@ u = ai.GetTeamUnit(gPenId[i]);
		if (u is null) {
			// Destroyed without its removal event reaching us. Drop it here and
			// leave the cursor where it is -- the next entry has shifted into it.
			gPenId.removeAt(i);
			gPenPos.removeAt(i);
			gPenMoved.removeAt(i);
			continue;
		}
		++gPenCursor;

		const AIFloat3 at = u.GetPos(frame);
		if (at.distance2D(gPenPos[i]) > UNBLOCK_EPS) {
			gPenPos[i] = at;
			gPenMoved[i] = frame;
			continue;
		}
		if (frame - gPenMoved[i] < UNBLOCK_STILL)
			continue;
		if ((frame < gNextProbe) || (frame < gNextUnblockOrder))
			continue;

		gNextProbe = frame + UNBLOCK_PROBE_PERIOD;
		if (TryUnblock(u, at)) {
			// Give the reclaim time to happen before asking for another one on
			// this unit's behalf; if it walks away the timer is reset anyway.
			gPenMoved[i] = frame - (UNBLOCK_STILL - UNBLOCK_RECHECK);
		}
		return;   // one probe set per tick, whatever it found
	}
}

}  // namespace Military
