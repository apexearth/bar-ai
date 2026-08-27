namespace Military {

//------------------------------------------------------------------------------
// UNITS WALLED IN BY OUR OWN BUILDINGS.
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
// Detection is in stages, each cheap enough to gate the next:
//   1. the unit has not moved for UNBLOCK_STILL      -- free, a position read
//   2. it is ordered to walk out of the ring         -- one netted command
//   3. UNBLOCK_TEST_WAIT later it still has not moved
// Standing still is NOT enough on its own: a defend squad parked on the line is
// motionless for minutes at a time and is exactly where it should be. Refusing
// an order to move is what separates them.
//
// Stage 2 replaced eight ai.GetPathLength queries; see the block above
// StartMoveTest for why the engine call had to go.
const int   UNBLOCK_STILL     = 45 * SECOND;  // motionless this long -> candidate
const int   UNBLOCK_RECHECK   = 15 * SECOND;  // ...then again, after a clearing
const float UNBLOCK_EPS       = 48.f;   // movement under this is standing still
const int   UNBLOCK_SAMPLE    = 24;     // units whose position is read per tick
const float UNBLOCK_RING      = 700.f;  // how far out an exit has to reach
const int   UNBLOCK_RAYS      = 8;      // directions probed around the unit
// A wall has to be made of something. Below this many structures of ours in the
// ring there is nothing to blame and the unit is held by terrain, which
// reclaiming cannot fix.
const int   UNBLOCK_MIN_WALL  = 4;
const float UNBLOCK_CORRIDOR  = 96.f;   // half-width of the lane a unit needs
const int   UNBLOCK_PROBE_PERIOD = 3 * SECOND;
const int   UNBLOCK_ORDER_PERIOD = 10 * SECOND;
// How long a unit gets to obey the move order before it counts as penned.
const int   UNBLOCK_TEST_WAIT = 8 * SECOND;
const int   UNBLOCK_STRIKES   = 1;   // failed orders tolerated before acting
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

// THE VERDICT, for the Brain to act on. Reclaiming is a build choice and the
// Brain is the only thing that may spend a constructor, so this half only
// records what the move test proved: this unit cannot walk, and this building
// of ours is what stands in its way (0 when terrain holds it and there is
// nothing of ours to blame). apexearth 2026-08-27: "prevention is good, and
// then reclaim whichever is worth less" -- the choice between the two is made
// in the market, on price, where every other reclaim is priced.
array<Id>  gPenVictim;
array<Id>  gPenWall;
array<int> gPenVerdictAt;
const int PEN_VERDICT_TTL = 120 * SECOND;

void NotePenVerdict(Id victim, Id wall)
{
	for (uint i = 0; i < gPenVictim.length(); ++i) {
		if (gPenVictim[i] == victim) {
			gPenWall[i] = wall;
			gPenVerdictAt[i] = ai.frame;
			return;
		}
	}
	gPenVictim.insertLast(victim);
	gPenWall.insertLast(wall);
	gPenVerdictAt.insertLast(ai.frame);
}

void DropPenVerdict(Id victim)
{
	for (uint i = 0; i < gPenVictim.length(); ++i) {
		if (gPenVictim[i] == victim) {
			gPenVictim.removeAt(i);
			gPenWall.removeAt(i);
			gPenVerdictAt.removeAt(i);
			return;
		}
	}
}

void SweepPenVerdicts()
{
	for (uint i = 0; i < gPenVictim.length(); ) {
		if (ai.frame - gPenVerdictAt[i] > PEN_VERDICT_TTL) {
			gPenVictim.removeAt(i);
			gPenWall.removeAt(i);
			gPenVerdictAt.removeAt(i);
			continue;
		}
		++i;
	}
}

bool UnblockOn()
{
	return ai.GetTunable("apex_unblock", TUNE_UNBLOCK) > 0.f;
}

// Ground units only: a flyer is never walled in by buildings.
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

// ASKING THE UNIT TO WALK REPLACES ASKING THE ENGINE FOR A PATH.
//
// ai.GetPathLength reaches CAICallback::InitPath -> QTPFS RequestPath, which
// runs a real search on the host only, and QTPFS's own ExecuteQueuedSearches
// warns "Do NOT impact this group while the background tasks are running" --
// it desynced every paired-network test run with this AI on. An order to move
// separates a PENNED unit from a PARKED one just as well (the parked one
// obeys, the walled-in one cannot), and both issuing a move and reading a
// position are netted, so nothing here executes on the host alone. It is also
// the better test: eight rays can miss a gap the engine would route through,
// and a path query succeeding does not prove the unit will traverse it.
array<Id>       gTestId;      // unit under a move test
array<AIFloat3> gTestFrom;    // where it stood when the order went out
array<int>      gTestFrame;   // when it went out
array<AIFloat3> gTestDir;     // direction it was sent, i.e. where the wall is
array<int>      gTestStrikes; // failed move orders so far

// Where to send it: the eighth of the ring holding the fewest of our own
// buildings. Pure arithmetic over a list we already have -- the thinnest part of
// the wall, by the same reasoning the ray probe used, without the engine call.
AIFloat3 ThinnestDir(const AIFloat3& in at)
{
	array<int> count(UNBLOCK_RAYS, 0);
	array<CCircuitUnit@>@ structs = ai.GetOwnStructsNear(at, UNBLOCK_RING);
	if (structs !is null) {
		for (uint i = 0; i < structs.length(); ++i) {
			CCircuitUnit@ s = structs[i];
			if (s is null)
				continue;
			const AIFloat3 rel = s.GetPos(ai.frame) - at;
			if (rel.SqLength2D() < NEAR_ZERO)
				continue;
			float a = atan2(rel.z, rel.x);
			if (a < 0.f)
				a += 6.2831853f;
			int k = int(a / 6.2831853f * float(UNBLOCK_RAYS)) % UNBLOCK_RAYS;
			++count[k];
		}
	}
	int best = 0;
	for (int k = 1; k < UNBLOCK_RAYS; ++k) {
		if (count[k] < count[best])
			best = k;
	}
	const float a = 6.2831853f * float(best) / float(UNBLOCK_RAYS);
	return AIFloat3(cos(a), 0.f, sin(a));
}

bool UnderTest(Id id)
{
	for (uint i = 0; i < gTestId.length(); ++i) {
		if (gTestId[i] == id)
			return true;
	}
	return false;
}

void DropTest(uint i)
{
	gTestId.removeAt(i);
	gTestFrom.removeAt(i);
	gTestFrame.removeAt(i);
	gTestDir.removeAt(i);
	gTestStrikes.removeAt(i);
}

// Send it somewhere. Short of the ring, so a unit that CAN move registers the
// move well inside the verdict window.
void StartMoveTest(CCircuitUnit@ unit, const AIFloat3& in at)
{
	// NOT a unit whose task wants it standing still. A constructor building, or
	// anything else mid-task, has its orders re-asserted by that task, so our
	// move is overridden, the unit never moves, and it reads as penned when it
	// is working. Measured: without this the commander was tested at 1.0 min and
	// a wind generator was reclaimed underneath it.
	IUnitTask@ t = unit.task;
	if ((t !is null) && (t.GetType() == Task::Type::BUILDER))
		return;
	// A super parked on the defence line is standing still because it was told
	// to -- but IUnitTask exposes GetType/GetBuildType and NOT GetFightType, so
	// "parked" cannot be read directly. The existing gates cover it instead: the
	// move test only calls a unit penned after TWO refused orders, and TryUnblock
	// additionally requires UNBLOCK_MIN_WALL of our own structures ringing it.
	// A parked super obeys the first order and is cleared.
	// NOR the commander. It stands in the middle of the base by design, with our
	// buildings packed around it, and CircuitAI re-tasks it every few seconds --
	// so the move order is overridden and it reads as penned. Measured: two of
	// two clearing orders in a 12-minute game were commanders, both wrong.
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return;
	const AIFloat3 dir = ThinnestDir(at);
	const AIFloat3 to = at + dir * (UNBLOCK_RING * 0.5f);
	if (!OnMap(to))
		return;
	unit.CmdMoveTo(to);
	gTestId.insertLast(unit.id);
	gTestFrom.insertLast(at);
	gTestFrame.insertLast(ai.frame);
	gTestDir.insertLast(dir);
	gTestStrikes.insertLast(0);
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

// Stuck units already asked for, with a TTL: a reclaim that aborted (no
// builder in reach) may be re-asked later rather than never.
array<int> gStuckAsked;
array<int> gStuckAskedFrame;

bool StuckAskedFor(Id id)
{
	const int ttl = int(ai.GetTunable("apex_stuck_retry", TUNE_STUCK_RETRY)) * SECOND;
	for (uint i = 0; i < gStuckAsked.length(); ) {
		if (ai.frame - gStuckAskedFrame[i] > ttl) {
			gStuckAsked.removeAt(i);
			gStuckAskedFrame.removeAt(i);
			continue;
		}
		if (gStuckAsked[i] == int(id))
			return true;
		++i;
	}
	return false;
}

// Returns true when a clearing order went out, so the caller can hold this unit
// off for UNBLOCK_RECHECK rather than immediately asking for a second building.
bool TryUnblock(CCircuitUnit@ unit, const AIFloat3& in at, const AIFloat3& in dir)
{
	++gPennedSeen;
	int wall = 0;
	CCircuitUnit@ eat = WallToEat(at, dir, wall);
	if (wall < UNBLOCK_MIN_WALL) {
		// Held by TERRAIN: nothing of ours to eat and the unit will never
		// walk anywhere -- apexearth: "if we have units that are stuck and
		// can't go anywhere then we should reclaim them." The metal comes
		// home, the unit count drops, and a builder's lathe reaches over the
		// terrain lip the unit cannot walk. Never the commander.
		if (!unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
			&& !StuckAskedFor(unit.id))
		{
			gStuckAsked.insertLast(int(unit.id));
			gStuckAskedFrame.insertLast(ai.frame);
			NotePenVerdict(unit.id, 0);
			AiLog(Factory::T() + "apex: stuck " + unit.circuitDef.GetName()
				+ " #" + unit.id + " terrain-penned -> offered to the market");
		}
		return false;
	}
	if (eat is null)
		return false;

	NotePenVerdict(unit.id, eat.id);
	gUnblockAsked.insertLast(eat.id);
	if (gUnblockAsked.length() > 64)
		gUnblockAsked.removeAt(0);
	gNextUnblockOrder = ai.frame + UNBLOCK_ORDER_PERIOD;
	++gUnblockOrders;
	AiLog(Factory::T() + "apex: unblock " + unit.circuitDef.GetName() + " #" + unit.id
		+ " walled in (" + wall + " of ours in the ring) -> offered "
		+ eat.circuitDef.GetName() + " #" + eat.id
		+ " cost=" + formatFloat(eat.circuitDef.costM, "", 0, 0)
		+ " (order " + gUnblockOrders + " of " + gPennedSeen + " penned)");
	return true;
}

void UpdateUnblock()
{
	SweepPenVerdicts();
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
		if (frame - gPenMoved[i] < int(ai.GetTunable("apex_unblock_still", float(UNBLOCK_STILL))))
			continue;
		if ((frame < gNextProbe) || (frame < gNextUnblockOrder))
			continue;

		gNextProbe = frame + int(ai.GetTunable("apex_unblock_period", float(UNBLOCK_PROBE_PERIOD)));
		if (!UnderTest(u.id))
			StartMoveTest(u, at);
		return;   // one candidate per tick
	}
}

// The verdict half. A unit that was ordered to move and did is not penned; one
// that did not, after UNBLOCK_TEST_WAIT, is -- and the direction it failed to
// walk is where the wall stands.
void UpdateMoveTests()
{
	const int frame = ai.frame;
	const int wait = int(ai.GetTunable("apex_unblock_test_wait", float(UNBLOCK_TEST_WAIT)));
	for (uint i = 0; i < gTestId.length(); ) {
		CCircuitUnit@ u = ai.GetTeamUnit(gTestId[i]);
		if (u is null) {
			DropTest(i);
			continue;
		}
		const AIFloat3 at = u.GetPos(frame);
		if (at.distance2D(gTestFrom[i]) > UNBLOCK_EPS) {
			ForgetPenned(gTestId[i]);   // it walked; it was parked, not penned
			DropTest(i);
			continue;
		}
		if (frame - gTestFrame[i] < wait) {
			++i;
			continue;
		}
		if (gTestStrikes[i] < UNBLOCK_STRIKES) {
			// One failed order can be a task re-asserting itself in the same
			// second. Ask again before eating a building over it.
			++gTestStrikes[i];
			gTestFrame[i] = frame;
			u.CmdMoveTo(at + gTestDir[i] * (UNBLOCK_RING * 0.5f));
			++i;
			continue;
		}
		if (frame >= gNextUnblockOrder)
			TryUnblock(u, at, gTestDir[i]);
		DropTest(i);
	}
}

}  // namespace Military
