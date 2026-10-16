namespace Military {

//------------------------------------------------------------------------------
// UNITS THAT HAVE AN ORDER AND DO NOT MOVE (apex_unstick).
//
// The walled-in watch (unblock.as) waits 45 s of stillness and then tests one
// unit per sweep, because a parked unit and a penned one look the same. A unit
// holding a move or fight order that has not moved is not parked: every client
// re-paths it while it pushes at a nano turret (his 8v8 of 10-15). The verdict
// is the builder watch's own (stuck.as): ground covered at a quarter of the
// unit's speed since the last reset, judged after a third of apex_stuck_secs --
// the soonest that rule ever calls a hand dead.
//
// The response, in order: a move to the nearest open ground it can reach along
// the lane crossing the fewest of our buildings; if it still does not move, the
// unblock move test proves the pen and the market prices the wall; if the wall
// still stands while what it traps loses more service than the wall is worth,
// the wall is self-destructed.
//------------------------------------------------------------------------------

bool UnstickOn()
{
	return ai.GetTunable("apex_unstick", TUNE_UNSTICK) > 0.f;
}

// Parallel to gPenId: kept in step by UsAdd/UsDrop at every site that edits it.
array<AIFloat3> gUsAt;       // where the current stillness window began
array<int>      gUsSince;    // ...and when
array<int>      gUsNudgeAt;  // frame a nudge went out, -1 for none
array<AIFloat3> gUsNudgeFrom;
array<int>      gUsNudges;   // nudges this unit has had
uint gUsCursor = 0;
array<Id> gUsQueue;          // stuck, waiting for a nudge: one is computed per tick

int gUsSeen = 0;      // ordered combat units found not moving
int gUsNudged = 0;    // nudges sent (combat units)
int gUsFreed = 0;     // nudged units seen to have moved afterwards
int gUsNoGround = 0;  // no open reachable ground found to send it to
int gUsPenned = 0;    // nudge refused: handed to the walled-in move test
int gUsAgain = 0;     // stuck again where a nudge already freed it: its task leads it back, so the move test judges it
int gUsBNudged = 0;   // builders freed by the stuck watch that had not moved, nudged
int gUsBFreed = 0;
int gUsSelfD = 0;
float gUsSelfDM = 0.f;
float gUsTrappedM = 0.f;
int gUsSiteDoor = 0;  // nano/converter cells refused for a ground plant's door lane past the old depth
int gUsSiteCut = 0;   // ...for splitting the open ground around them
array<Id> gUsSelfDAsked;
int gUsStatAt = 241;   // phase offset off the other minute lines

void UsAdd(const AIFloat3& in at)
{
	gUsAt.insertLast(at);
	gUsSince.insertLast(ai.frame);
	gUsNudgeAt.insertLast(-1);
	gUsNudgeFrom.insertLast(at);
	gUsNudges.insertLast(0);
}

void UsDrop(uint i)
{
	if (i >= gUsAt.length())
		return;
	gUsAt.removeAt(i);
	gUsSince.removeAt(i);
	gUsNudgeAt.removeAt(i);
	gUsNudgeFrom.removeAt(i);
	gUsNudges.removeAt(i);
}

void UsReset(uint i, const AIFloat3& in at)
{
	gUsAt[i] = at;
	gUsSince[i] = ai.frame;
}

bool UsQueued(Id id)
{
	for (uint i = 0; i < gUsQueue.length(); ++i) {
		if (gUsQueue[i] == id)
			return true;
	}
	return false;
}

int UsSlot(Id id)
{
	for (uint i = 0; i < gPenId.length(); ++i) {
		if (gPenId[i] == id)
			return int(i);
	}
	return -1;
}

// A builder the stuck watch freed without it having moved at all: the same
// nudge, after its re-election has issued the new job's orders.
void UnstickBuilder(CCircuitUnit@ u)
{
	if ((u is null) || !UnstickOn() || UsQueued(u.id))
		return;
	gUsQueue.insertLast(u.id);
}

bool UsCovered(array<CCircuitUnit@>@ structs, const AIFloat3& in p, float r)
{
	for (uint i = 0; (structs !is null) && (i < structs.length()); ++i) {
		CCircuitUnit@ s = structs[i];
		if ((s is null) || (s.circuitDef is null))
			continue;
		const float sh = HalfOf(s.circuitDef) + r;
		const AIFloat3 sp = s.GetPos(ai.frame);
		if ((abs(sp.x - p.x) < sh) && (abs(sp.z - p.z) < sh))
			return true;
	}
	return false;
}

// The same over a teammate's buildings, [x, z, defId, unitId, team] flat.
bool UsAllyCovered(const array<float>@ al, const AIFloat3& in p, float r)
{
	for (uint i = 0; (al !is null) && (i + 4 < al.length()); i += 5) {
		const int d = int(al[i + 2]);
		if (!Catalog::ValidId(d))
			continue;
		const float sh = float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]) * 8.f + r;
		if ((abs(al[i] - p.x) < sh) && (abs(al[i + 1] - p.z) < sh))
			return true;
	}
	return false;
}

// The nearest ground out along the lane crossing the fewest of our buildings
// that this def can reach and no structure of ours or a teammate's covers.
bool UsOpenGround(CCircuitUnit@ u, const AIFloat3& in at, AIFloat3& out to)
{
	CCircuitDef@ def = Catalog::Def(int(u.circuitDef.id));
	array<CCircuitUnit@>@ structs = ai.GetOwnStructsNear(at, UNBLOCK_RING);
	const float uh = HalfOf(u.circuitDef);
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
	if (best < 0)
		return false;
	const AIFloat3 dir = RayDir(best);
	const float step = uh * 2.f + Lattice::CELL;
	array<float>@ allies = ai.GetAllyStructsNear(at, UNBLOCK_RING);
	for (float d = step; d <= UNBLOCK_REACH; d += step) {
		const AIFloat3 p = at + dir * d;
		if (!OnMap(p))
			break;
		if (known && !ai.CanDefReach(def, at, p))
			continue;
		if (UsCovered(structs, p, uh + Lattice::CELL) || UsAllyCovered(allies, p, uh + Lattice::CELL))
			continue;
		to = p;
		return true;
	}
	return false;
}

void UsNudgeOne()
{
	while (gUsQueue.length() > 0) {
		const Id id = gUsQueue[0];
		gUsQueue.removeAt(0);
		CCircuitUnit@ u = ai.GetTeamUnit(id);
		if ((u is null) || (u.circuitDef is null))
			continue;
		const AIFloat3 at = u.GetPos(ai.frame);
		AIFloat3 to;
		if (!UsOpenGround(u, at, to)) {
			++gUsNoGround;
			// Nowhere open to go: the move test decides whether a wall of ours is why.
			if (UnblockOn() && !UnderTest(id) && !HasPenVerdict(id) && StartMoveTest(u, at))
				++gUsPenned;
			return;
		}
		u.CmdMoveTo(to);
		const bool bld = Catalog::gBuilder[int(u.circuitDef.id)];
		if (bld)
			++gUsBNudged;
		else
			++gUsNudged;
		const int s = UsSlot(id);
		if (s >= 0) {
			gUsNudgeAt[uint(s)] = ai.frame;
			gUsNudgeFrom[uint(s)] = at;
			++gUsNudges[uint(s)];
		}
		AiLog(Factory::T() + "apex: unstick-nudge " + u.circuitDef.GetName() + " #" + id
			+ " q=" + u.CmdQueueSize() + " at=" + int(at.x) + "," + int(at.z)
			+ " to=" + int(to.x) + "," + int(to.z) + (bld ? " builder" : ""));
		return;
	}
}

// What a nudged unit did with it: walked (freed), or stood (the move test).
void UsJudgeNudge(CCircuitUnit@ u, uint i, const AIFloat3& in at)
{
	const bool bld = Catalog::gBuilder[int(u.circuitDef.id)];
	if (at.distance2D(gUsNudgeFrom[i]) > UNBLOCK_EPS) {
		if (bld)
			++gUsBFreed;
		else
			++gUsFreed;
		gUsNudgeAt[i] = -1;
		UsReset(i, at);
		return;
	}
	if (ai.frame - gUsNudgeAt[i] < UNBLOCK_TEST_WAIT)
		return;
	gUsNudgeAt[i] = -1;
	UsReset(i, at);
	if (UnblockOn() && !UnderTest(u.id) && !HasPenVerdict(u.id) && StartMoveTest(u, at))
		++gUsPenned;
}

bool UsHoldsStill(CCircuitUnit@ u)
{
	IUnitTask@ t = u.task;
	if ((t is null) || (t.GetType() != Task::Type::FIGHTER))
		return false;
	const int ft = t.GetFightType();
	// Standing is their job: beside a guarded unit, or shelling from range.
	return (ft == int(Task::FightType::GUARD)) || (ft == int(Task::FightType::ARTY))
		|| (ft == int(Task::FightType::SIEGE)) || (ft == int(Task::FightType::SUPPORT))
		|| (ft == int(Task::FightType::AA));
}

void UpdateUnstick()
{
	UnstickStat();
	const uint n = gPenId.length();
	if (n == 0)
		return;
	if (gUsAt.length() != n) {
		// Out of step only if an edit site was missed; rebuilt rather than misread.
		gUsAt.resize(0); gUsSince.resize(0); gUsNudgeAt.resize(0); gUsNudgeFrom.resize(0); gUsNudges.resize(0);
		for (uint i = 0; i < n; ++i)
			UsAdd(gPenPos[i]);
	}
	const float secs = ai.GetTunable("apex_stuck_secs", TUNE_STUCK_SECS);
	if (secs <= 0.f)
		return;
	const int still = int(secs * float(SECOND)) / 3;
	const bool on = UnstickOn();
	const int frame = ai.frame;
	// Every unit once per eight calls: each is judged against its own window.
	const uint step = (n + 7) / 8;
	for (uint k = 0; k < step; ++k) {
		if (gUsCursor >= gPenId.length())
			gUsCursor = 0;
		const uint i = gUsCursor++;
		CCircuitUnit@ u = ai.GetTeamUnit(gPenId[i]);
		if ((u is null) || (u.circuitDef is null))
			continue;   // the unblock sweep drops it
		const int d = int(u.circuitDef.id);
		const AIFloat3 at = u.GetPos(frame);
		if (gUsNudgeAt[i] >= 0) {
			UsJudgeNudge(u, i, at);
			continue;
		}
		// Builders are the stuck watch's (stuck.as): one at its site stands still working.
		if (Catalog::gBuilder[d] || (Catalog::gMaxRange[d] <= 0.f)) {
			UsReset(i, at);
			continue;
		}
		const float sinceS = float(frame - gUsSince[i]) / float(SECOND);
		float walkFloor = 0.25f * Catalog::gSpeed[d] * sinceS;
		if (walkFloor < Market::STUCK_MOVED)
			walkFloor = Market::STUCK_MOVED;
		if (at.distance2D(gUsAt[i]) > walkFloor) {
			UsReset(i, at);
			continue;
		}
		if (frame - gUsSince[i] < still)
			continue;
		UsReset(i, at);
		if (UsHoldsStill(u) || (u.CmdQueueSize() == 0))
			continue;
		// Fighting is standing with an order too: shot at, or a foe inside its reach.
		if ((frame - u.GetDamagedFrame() < still)
			|| (ai.GetEnemyCostAt(at, Catalog::gMaxRange[d] + UNBLOCK_EPS) > 0.f))
			continue;
		++gUsSeen;
		if (!on || UnderTest(u.id) || HasPenVerdict(u.id) || UsQueued(u.id))
			continue;
		if ((gUsNudges[i] > 0) && (at.distance2D(gUsNudgeFrom[i]) < UNBLOCK_REACH)) {
			++gUsAgain;
			if (UnblockOn() && StartMoveTest(u, at))
				++gUsPenned;
			continue;
		}
		gUsQueue.insertLast(u.id);
	}
	if (on)
		UsNudgeOne();
}

// THE WALL THAT STAYS. The market eats a pen's wall when a builder gets to it;
// meanwhile what it traps is out of service. Once the service lost so far --
// the trapped metal amortized over apex_reclaim_amort, as every reclaim here is
// -- exceeds the wall's own metal, the wall is worth less than the wait.
void UnstickSelfD(uint i)
{
	if (!UnstickOn() || (gPenWall[i] == 0) || (gPenWall[i] == gPenVictim[i]))
		return;
	CCircuitUnit@ wall = ai.GetTeamUnit(gPenWall[i]);
	if ((wall is null) || (wall.circuitDef is null))
		return;
	const CCircuitDef@ wd = wall.circuitDef;
	if (wd.IsMex() || wd.IsBuilder())
		return;
	for (uint k = 0; k < gUsSelfDAsked.length(); ++k) {
		if (gUsSelfDAsked[k] == wall.id)
			return;
	}
	float trapped = 0.f;
	int victims = 0;
	for (uint k = 0; k < gPenVictim.length(); ++k) {
		if (gPenWall[k] != gPenWall[i])
			continue;
		CCircuitUnit@ v = ai.GetTeamUnit(gPenVictim[k]);
		if ((v is null) || (v.circuitDef is null))
			continue;
		trapped += v.circuitDef.costM;
		++victims;
	}
	const float hzP = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float hz = (hzP > 1.f) ? hzP : 300.f;
	const float ageS = float(ai.frame - gPenVerdictAt[i]) / float(SECOND);
	if (trapped * ageS / hz <= wd.costM)
		return;
	gUsSelfDAsked.insertLast(wall.id);
	if (gUsSelfDAsked.length() > 64)
		gUsSelfDAsked.removeAt(0);
	wall.SelfDestruct(true);
	++gUsSelfD;
	gUsSelfDM += wd.costM;
	gUsTrappedM += trapped;
	const AIFloat3 wp = wall.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: unstick-selfd " + wd.GetName() + " #" + wall.id
		+ " cost=" + int(wd.costM) + " trapped=" + int(trapped) + " victims=" + victims
		+ " waited=" + int(ageS) + "s at=" + int(wp.x) + "," + int(wp.z));
}

void UnstickStat()
{
	if (ai.frame < gUsStatAt)
		return;
	gUsStatAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: unstick-stat t=" + ai.teamId + " on=" + (UnstickOn() ? 1 : 0)
		+ " seen=" + gUsSeen + " nudged=" + gUsNudged + " freed=" + gUsFreed
		+ " noGround=" + gUsNoGround + " again=" + gUsAgain + " penned=" + gUsPenned
		+ " bNudged=" + gUsBNudged + " bFreed=" + gUsBFreed
		+ " selfd=" + gUsSelfD + " selfdM=" + int(gUsSelfDM) + " trappedM=" + int(gUsTrappedM)
		+ " ateWall=" + gUnblockOrders
		+ " siteDoor=" + gUsSiteDoor + " siteCut=" + gUsSiteCut
		+ " queue=" + gUsQueue.length() + " watched=" + gPenId.length());
}

}  // namespace Military
