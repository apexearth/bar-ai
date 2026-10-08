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
const int   UNBLOCK_RAYS      = 16;     // directions probed around the unit
// The pocket: a lane with nothing of ours across it this far out is open.
const float UNBLOCK_REACH     = UNBLOCK_RING * 0.5f;
const int   UNBLOCK_PROBE_PERIOD = 3 * SECOND;
const int   UNBLOCK_ORDER_PERIOD = 10 * SECOND;
// How long a unit gets to obey the move order before it counts as penned.
const int   UNBLOCK_TEST_WAIT = 8 * SECOND;
const int   UNBLOCK_STRIKES   = 1;   // failed orders tolerated before acting
// The dearest wall a cheap unit may cost us; a dearer unit may cost its own
// price, and the market still eats whichever of the two is worth less.
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
array<AIFloat3> gPenExit;   // where the wall stood: the hole once it is eaten
array<AIFloat3> gPenDir;    // the way out through it
array<float> gPenFlow;      // metal/s a jammed plant gets back when it is cleared
const int PEN_VERDICT_TTL = 120 * SECOND;

void NotePenVerdict(Id victim, Id wall, const AIFloat3& in exit, const AIFloat3& in dir,
	float flow = 0.f)
{
	for (uint i = 0; i < gPenVictim.length(); ++i) {
		if (gPenVictim[i] == victim) {
			gPenWall[i] = wall;
			gPenVerdictAt[i] = ai.frame;
			gPenExit[i] = exit;
			gPenDir[i] = dir;
			gPenFlow[i] = flow;
			return;
		}
	}
	gPenVictim.insertLast(victim);
	gPenWall.insertLast(wall);
	gPenVerdictAt.insertLast(ai.frame);
	gPenExit.insertLast(exit);
	gPenDir.insertLast(dir);
	gPenFlow.insertLast(flow);
}

// The wall standing between this victim and everything else, or 0.
Id PenWallOf(Id victim)
{
	for (uint i = 0; i < gPenVictim.length(); ++i) {
		if (gPenVictim[i] != victim)
			continue;
		if (gPenWall[i] == 0)
			return 0;
		CCircuitUnit@ wall = ai.GetTeamUnit(gPenWall[i]);
		return ((wall !is null) && (wall.circuitDef !is null)) ? gPenWall[i] : 0;
	}
	return 0;
}

void DropPenVerdict(Id victim)
{
	for (uint i = 0; i < gPenVictim.length(); ++i) {
		if (gPenVictim[i] == victim) {
			gPenVictim.removeAt(i);
			gPenWall.removeAt(i);
			gPenVerdictAt.removeAt(i);
			gPenExit.removeAt(i);
			gPenDir.removeAt(i);
			gPenFlow.removeAt(i);
			return;
		}
	}
}

// The victim walks through the hole the moment its wall dies, before the
// lattice refills it; a verdict with no wall would otherwise offer the victim.
int gUnblockWalks = 0;

void SweepPenVerdicts()
{
	for (uint i = 0; i < gPenVictim.length(); ) {
		const bool expired = ai.frame - gPenVerdictAt[i] > PEN_VERDICT_TTL;
		const bool wallGone = (gPenWall[i] != 0) && (ai.GetTeamUnit(gPenWall[i]) is null);
		// A victim that got clear of the ring on its own is not penned: the
		// verdict held a freed commander on a walk back to eat its wall.
		bool walkedOut = false;
		if (!wallGone && !expired) {
			CCircuitUnit@ v = ai.GetTeamUnit(gPenVictim[i]);
			walkedOut = (v is null)
				|| (v.GetPos(ai.frame).distance2D(gPenExit[i]) > 2.f * UNBLOCK_RING);
			if (walkedOut && (v !is null))
				AiLog(Factory::T() + "apex: unblock-free " + v.circuitDef.GetName()
					+ " #" + v.id + " clear of the ring on its own");
		}
		if (wallGone && !expired) {
			CCircuitUnit@ v = ai.GetTeamUnit(gPenVictim[i]);
			if (v !is null) {
				const AIFloat3 to = gPenExit[i] + gPenDir[i] * (UNBLOCK_RING * 0.5f);
				v.CmdMoveTo(OnMap(to) ? to : gPenExit[i]);
				MarkPenMoved(gPenVictim[i], v.GetPos(ai.frame));
				++gUnblockWalks;
				AiLog(Factory::T() + "apex: unblock-walk " + v.circuitDef.GetName()
					+ " #" + v.id + " through " + int(gPenExit[i].x) + ","
					+ int(gPenExit[i].z) + " (walk " + gUnblockWalks + ")");
			}
		}
		if (expired || wallGone || walkedOut) {
			gPenVictim.removeAt(i);
			gPenWall.removeAt(i);
			gPenVerdictAt.removeAt(i);
			gPenExit.removeAt(i);
			gPenDir.removeAt(i);
			gPenFlow.removeAt(i);
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

// A unit that walked is parked today, not exempt forever: it stays watched.
void MarkPenMoved(Id id, const AIFloat3& in at)
{
	for (uint i = 0; i < gPenId.length(); ++i) {
		if (gPenId[i] == id) {
			gPenPos[i] = at;
			gPenMoved[i] = ai.frame;
			return;
		}
	}
}

Id gCandId = 0;
float gCandCost = -1.f;
AIFloat3 gCandAt;
bool gSweepDone = false;

bool HasPenVerdict(Id id)
{
	for (uint i = 0; i < gPenVictim.length(); ++i) {
		if (gPenVictim[i] == id)
			return true;
	}
	return false;
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

AIFloat3 RayDir(int k)
{
	const float a = 6.2831853f * float(k) / float(UNBLOCK_RAYS);
	return AIFloat3(cos(a), 0.f, sin(a));
}

// Half the width a footprint sweeps (gFootX is in 16-elmo cells).
float HalfOf(const CCircuitDef@ d)
{
	const int i = int(d.id);
	const int f = (Catalog::gFootX[i] > Catalog::gFootZ[i]) ? Catalog::gFootX[i] : Catalog::gFootZ[i];
	return (f > 0) ? float(f) * 8.f : 8.f;
}

// Terrain the unit could cross if nothing of ours stood on it. The side of a
// base with no buildings is usually a cliff or the map edge, so the emptiest
// lane was the one terrain closes and every unit sent down it read as penned.
// Where the area map does not hold the unit's own ground (`known` false) it
// cannot judge, and treating that as shut offered free units for reclaim.
bool LaneWalkable(CCircuitDef@ def, const AIFloat3& in at, const AIFloat3& in dir, bool known)
{
	const AIFloat3 to = at + dir * UNBLOCK_REACH;
	if (!OnMap(to))
		return false;
	if (!known)
		return true;
	const AIFloat3 mid = at + dir * (UNBLOCK_REACH * 0.5f);
	return ai.CanDefReach(def, at, mid) && ai.CanDefReach(def, at, to);
}

bool TerrainKnown(CCircuitDef@ def, const AIFloat3& in at)
{
	return (def !is null) && ai.CanDefReach(def, at, at);
}

// Our structures whose footprint crosses the strip this unit sweeps walking
// `dir` out of the pocket; returns the nearest.
CCircuitUnit@ LaneFirst(array<CCircuitUnit@>@ structs, const AIFloat3& in at,
	const AIFloat3& in dir, float unitHalf, int& out count)
{
	count = 0;
	if (structs is null)
		return null;
	CCircuitUnit@ first = null;
	float firstAlong = 0.f;
	for (uint i = 0; i < structs.length(); ++i) {
		CCircuitUnit@ s = structs[i];
		if ((s is null) || (s.circuitDef is null))
			continue;
		const float sh = HalfOf(s.circuitDef);
		const AIFloat3 rel = s.GetPos(ai.frame) - at;
		const float along = rel.x * dir.x + rel.z * dir.z;
		if ((along <= 0.f) || (along > UNBLOCK_REACH + sh))
			continue;
		if (abs(rel.x * dir.z - rel.z * dir.x) > unitHalf + sh)
			continue;
		++count;
		if ((first is null) || (along < firstAlong)) {
			firstAlong = along;
			@first = s;
		}
	}
	return first;
}

// Where to send it: the walkable lane crossing the fewest of our buildings.
AIFloat3 ThinnestDir(CCircuitUnit@ unit, const AIFloat3& in at)
{
	array<CCircuitUnit@>@ structs = ai.GetOwnStructsNear(at, UNBLOCK_RING);
	const float uh = HalfOf(unit.circuitDef);
	CCircuitDef@ def = Catalog::Def(int(unit.circuitDef.id));
	const bool known = TerrainKnown(def, at);
	int best = -1;
	int bestN = 0;
	for (int k = 0; k < UNBLOCK_RAYS; ++k) {
		const AIFloat3 dir = RayDir(k);
		if (!LaneWalkable(def, at, dir, known))
			continue;
		int n = 0;
		LaneFirst(structs, at, dir, uh, n);
		if ((best < 0) || (n < bestN)) {
			best = k;
			bestN = n;
		}
	}
	return RayDir((best < 0) ? 0 : best);
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
bool StartMoveTest(CCircuitUnit@ unit, const AIFloat3& in at)
{
	// NOT a unit whose task wants it standing still. A constructor building, or
	// anything else mid-task, has its orders re-asserted by that task, so our
	// move is overridden, the unit never moves, and it reads as penned when it
	// is working. Measured: without this the commander was tested at 1.0 min and
	// a wind generator was reclaimed underneath it.
	// ...UNLESS IT IS NOWHERE NEAR ITS SITE. A builder still for the pen
	// window with a build order it cannot reach is not working, it is walled
	// in -- his commander on Supreme Isthmus held 69 unreachable orders and
	// 13 stuck re-elections from minute 2 to its death at 18.7, penned by its
	// own solars 44 elmos away (apexearth: "They never ever fix the situation.
	// They should reclaim whatever made them stuck"). At its site it works and
	// is left alone; a build distance away from it, it is tested like any
	// other unit, the commander included -- the trade below eats the cheaper
	// side, which is never him.
	// Working means a nanoframe stands: in range with nothing raised after
	// the still window is a site it cannot start, not a site it is building.
	IUnitTask@ t = unit.task;
	if ((t !is null) && (t.GetType() == Task::Type::BUILDER) && (t.target !is null)) {
		const AIFloat3 site = t.GetBuildPos();
		const float reach = Catalog::gBuildDist[int(unit.circuitDef.id)];
		if (!OnMap(site) || (at.distance2D(site) <= reach + 64.f))
			return false;
	}
	const AIFloat3 dir = ThinnestDir(unit, at);
	const AIFloat3 to = at + dir * UNBLOCK_REACH;
	if (!OnMap(to))
		return false;
	unit.CmdMoveTo(to);
	gTestId.insertLast(unit.id);
	gTestFrom.insertLast(at);
	gTestFrame.insertLast(ai.frame);
	gTestDir.insertLast(dir);
	gTestStrikes.insertLast(0);
	return true;
}

// THE CHEAPEST DOOR. Every walkable lane out of the pocket is closed by the
// first structure of ours across it; the door is the cheapest of those. A lane
// with nothing across it means the pocket is not ours to open.
//
// Never a mex (the metal spot is the reason the base is here), never a factory
// (IsBuilder -- eating what produces the unit to free the unit is not a trade).
int gLaneWalk = 0, gLaneOpen = 0, gLaneShut = 0;   // the last pocket read
bool gTerrainKnown = true;
int gPenBlind = 0;
AIFloat3 gDoorDir;

// A TEAMMATE'S BUILDING IN THE WAY: an ally's extractor or turret pens our
// units. Our bots on a team share a board in one
// process; a bot names the blocker and its owner reclaims it through its own
// reclaim market. A human's or another AI's building is never touched.
const int BOARD_APEX = 1000, BOARD_ASK = 1100, BOARD_ASK_AT = 1200, BOARD_ASK_FLOW = 1300;
int gAllyAsked = 0, gAllyAskTaken = 0;
int gAllyAskSeen = -1;

bool IsApexTeam(int t)
{
	return (t >= 0) && (t < 100) && (ai.GetTeamBoard(BOARD_APEX + t, 0.f) > 0.f);
}

bool AskAllyReclaim(int unitId, int team, float flow)
{
	if (!IsApexTeam(team) || (team == ai.teamId))
		return false;
	ai.SetTeamBoard(BOARD_ASK + team, float(unitId));
	ai.SetTeamBoard(BOARD_ASK_AT + team, float(ai.frame));
	ai.SetTeamBoard(BOARD_ASK_FLOW + team, flow);
	++gAllyAsked;
	return true;
}

void AllyAskWatch()
{
	if (ai.teamId < 100)
		ai.SetTeamBoard(BOARD_APEX + ai.teamId, 1.f);
	const int at = int(ai.GetTeamBoard(BOARD_ASK_AT + ai.teamId, -1.f));
	if ((at < 0) || (at == gAllyAskSeen))
		return;
	gAllyAskSeen = at;
	CCircuitUnit@ u = ai.GetTeamUnit(Id(int(ai.GetTeamBoard(BOARD_ASK + ai.teamId, 0.f))));
	if ((u is null) || (u.circuitDef is null))
		return;
	// the trapped side and the wall are the same building: the market eats it,
	// priced as its metal back plus the flow it frees
	NotePenVerdict(u.id, u.id, u.GetPos(ai.frame), AIFloat3(0.f, 0.f, 0.f),
		ai.GetTeamBoard(BOARD_ASK_FLOW + ai.teamId, 0.f));
	++gAllyAskTaken;
	AiLog(Factory::T() + "apex: ally-ask taken t=" + ai.teamId + " " + u.circuitDef.GetName() + " #" + u.id
		+ " n=" + gAllyAskTaken);
}

// The first allied structure along a lane, as an index into the flat
// [x, z, defId, unitId, team] array, or -1.
int AllyLaneFirst(const array<float>@ al, const AIFloat3& in at, const AIFloat3& in dir, float unitHalf)
{
	int first = -1;
	float firstAlong = 0.f;
	for (uint i = 0; (al !is null) && (i + 4 < al.length()); i += 5) {
		const int d = int(al[i + 2]);
		if (!Catalog::ValidId(d))
			continue;
		const float sh = float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]) * 8.f;
		const float rx = al[i] - at.x, rz = al[i + 1] - at.z;
		const float along = rx * dir.x + rz * dir.z;
		if ((along <= 0.f) || (along > UNBLOCK_REACH + sh))
			continue;
		if (abs(rx * dir.z - rz * dir.x) > unitHalf + sh)
			continue;
		if ((first < 0) || (along < firstAlong)) {
			firstAlong = along;
			first = int(i);
		}
	}
	return first;
}

int gAllyWallId = 0, gAllyWallTeam = -1, gAllyWallDef = -1;

CCircuitUnit@ WallToEat(CCircuitUnit@ unit, const AIFloat3& in at)
{
	gAllyWallId = 0;
	gAllyWallTeam = -1;
	gAllyWallDef = -1;
	float allyCost = 0.f;
	array<float>@ allies = ai.GetAllyStructsNear(at, UNBLOCK_RING);
	gLaneWalk = 0;
	gLaneOpen = 0;
	gLaneShut = 0;
	array<CCircuitUnit@>@ structs = ai.GetOwnStructsNear(at, UNBLOCK_RING);
	CCircuitDef@ def = Catalog::Def(int(unit.circuitDef.id));
	const float uh = HalfOf(unit.circuitDef);
	const float cap = (unit.circuitDef.costM > UNBLOCK_MAX_COST) ? unit.circuitDef.costM : UNBLOCK_MAX_COST;
	CCircuitUnit@ door = null;
	float doorCost = 0.f;
	gTerrainKnown = TerrainKnown(def, at);
	if (!gTerrainKnown)
		++gPenBlind;
	for (int k = 0; k < UNBLOCK_RAYS; ++k) {
		const AIFloat3 dir = RayDir(k);
		if (!LaneWalkable(def, at, dir, gTerrainKnown))
			continue;
		++gLaneWalk;
		int n = 0;
		CCircuitUnit@ first = LaneFirst(structs, at, dir, uh, n);
		if (first is null) {
			const int ai2 = AllyLaneFirst(allies, at, dir, uh);
			if (ai2 < 0) {
				++gLaneOpen;
				continue;
			}
			// shut by a teammate's building: the cheapest such wall is asked for
			++gLaneShut;
			const int ad = int(allies[ai2 + 2]);
			const int at2 = int(allies[ai2 + 4]);
			if (!Catalog::ValidId(ad) || !IsApexTeam(at2))
				continue;
			if ((gAllyWallId == 0) || (Catalog::gCostM[ad] < allyCost)) {
				gAllyWallId = int(allies[ai2 + 3]);
				gAllyWallTeam = at2;
				gAllyWallDef = ad;
				allyCost = Catalog::gCostM[ad];
			}
			continue;
		}
		const CCircuitDef@ fd = first.circuitDef;
		if (fd.IsMex() || fd.IsBuilder() || (fd.costM > cap)) {
			++gLaneShut;
			continue;
		}
		// A wall already being eaten for another victim opens this pocket too.
		const float c = UnblockAsked(first.id) ? 0.f : fd.costM;
		if ((door is null) || (c < doorCost)) {
			@door = first;
			doorCost = c;
			gDoorDir = dir;
		}
	}
	return door;
}

// Stuck units already asked for, with a TTL: a reclaim that aborted (no
// builder in reach) may be re-asked later rather than never.
array<int> gStuckAsked;
array<int> gStuckAskedFrame;
int gStuckOffered = 0;   // units offered to the market as unreachable
int gPenOpen = 0;        // refused to walk with an open lane: not a pen
int gPenShut = 0;        // penned, and every door too dear to eat

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
	CCircuitUnit@ eat = WallToEat(unit, at);
	if ((eat is null) && (gAllyWallId != 0)
		&& AskAllyReclaim(gAllyWallId, gAllyWallTeam, 0.f))
	{
		AiLog(Factory::T() + "apex: pen-ally " + unit.circuitDef.GetName() + " #" + unit.id
			+ " wall=" + Catalog::Def(gAllyWallDef).GetName() + " #" + gAllyWallId + " owner=t" + gAllyWallTeam
			+ " asked=" + gAllyAsked);
		return true;
	}
	// A unit that refused to walk out is stuck whatever the rays say: a gap
	// too narrow for it reads as an open lane. Eat the cheapest building around
	// it (apexearth 2026-09-30: "just reclaim whatever is cheapest").
	if ((gLaneOpen > 0) && (eat is null)) {
		// It refused to walk with an open lane beside it: its own task holds it
		// (a squad re-asserting its post), or units crowd it. Nothing of ours to eat.
		++gPenOpen;
		AiLog(Factory::T() + "apex: pen-open " + unit.circuitDef.GetName() + " #" + unit.id
			+ " lanes=" + gLaneWalk + " open=" + gLaneOpen + " at=" + int(at.x) + "," + int(at.z));
		return false;
	}
	++gPennedSeen;
	if (gLaneWalk == 0) {
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
			++gStuckOffered;
			NotePenVerdict(unit.id, 0, at, dir);
			AiLog(Factory::T() + "apex: stuck " + unit.circuitDef.GetName()
				+ " #" + unit.id + " terrain-penned -> offered to the market"
				+ " at=" + int(at.x) + "," + int(at.z));
		}
		return false;
	}
	if (eat is null) {
		// Every lane out is a mex, a lab or dearer than the unit.
		++gPenShut;
		AiLog(Factory::T() + "apex: pen-shut " + unit.circuitDef.GetName() + " #" + unit.id
			+ " lanes=" + gLaneWalk + " shut=" + gLaneShut
			+ " at=" + int(at.x) + "," + int(at.z));
		return false;
	}

	if (!UnblockAsked(eat.id)) {
		gUnblockAsked.insertLast(eat.id);
		if (gUnblockAsked.length() > 64)
			gUnblockAsked.removeAt(0);
	}
	NotePenVerdict(unit.id, eat.id, eat.GetPos(ai.frame), gDoorDir);
	gNextUnblockOrder = ai.frame + UNBLOCK_ORDER_PERIOD;
	++gUnblockOrders;
	AiLog(Factory::T() + "apex: unblock " + unit.circuitDef.GetName() + " #" + unit.id
		+ " cost=" + formatFloat(unit.circuitDef.costM, "", 0, 0)
		+ " walled in (" + gLaneWalk + " lanes, " + gLaneShut + " shut) -> offered "
		+ eat.circuitDef.GetName() + " #" + eat.id
		+ " cost=" + formatFloat(eat.circuitDef.costM, "", 0, 0)
		+ " (order " + gUnblockOrders + " of " + gPennedSeen + " penned)");
	return true;
}

// THE COUNTER, because "it fires" was all this could say before. An unblock
// order and a stuck-reclaim are both rare by design, so the number that matters
// is how many units are STANDING penned right now -- the layout is what decides
// that, and a layout change is judged on this line, not on a win rate.
int gPenDiagAt = 211;   // phase offset -- see AiUpdate lockstep note

void PenDiag()
{
	if (ai.frame < gPenDiagAt)
		return;
	gPenDiagAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: pendiag watched=" + gPenId.length()
		+ " testing=" + gTestId.length() + " verdicts=" + gPenVictim.length()
		+ " | penned=" + gPennedSeen + " ate-wall=" + gUnblockOrders
		+ " walked=" + gUnblockWalks + " offered-unit=" + gStuckOffered
		+ " shut=" + gPenShut + " not-penned=" + gPenOpen + " blind=" + gPenBlind);
}

void UpdateUnblock()
{
	SweepPenVerdicts();
	PenDiag();
	if (!UnblockOn() || (gPenId.length() == 0))
		return;

	const int frame = ai.frame;
	uint scan = gPenId.length();
	if (scan > uint(UNBLOCK_SAMPLE))
		scan = uint(UNBLOCK_SAMPLE);

	for (uint k = 0; k < scan; ++k) {
		if (gPenId.length() == 0)
			return;   // the drop below can empty it mid-walk
		if (gPenCursor >= gPenId.length()) {
			gPenCursor = 0;
			gSweepDone = true;
		}
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
		if (UnderTest(u.id) || HasPenVerdict(u.id))
			continue;
		if (u.circuitDef.costM > gCandCost) {
			gCandId = u.id;
			gCandCost = u.circuitDef.costM;
			gCandAt = at;
		}
	}

	// The dearest still unit of the whole sweep is tested first: a gantry's
	// T3 waits behind no rez bot.
	if (!gSweepDone || (frame < gNextProbe) || (gCandId == 0))
		return;
	CCircuitUnit@ c = ai.GetTeamUnit(gCandId);
	if ((c !is null) && (c.GetPos(frame).distance2D(gCandAt) <= UNBLOCK_EPS)) {
		if (StartMoveTest(c, gCandAt))
			gNextProbe = frame + int(ai.GetTunable("apex_unblock_period", float(UNBLOCK_PROBE_PERIOD)));
		else
			MarkPenMoved(c.id, gCandAt);   // a builder at work: not the top candidate again
	}
	gCandId = 0;
	gCandCost = -1.f;
	gSweepDone = false;
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
			MarkPenMoved(gTestId[i], at);   // it walked; it was parked, not penned
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
		if (frame < gNextUnblockOrder) {
			++i;   // judged when the order slot frees, not thrown away
			continue;
		}
		TryUnblock(u, at, gTestDir[i]);
		MarkPenMoved(gTestId[i], at);
		DropTest(i);
	}
}

}  // namespace Military
