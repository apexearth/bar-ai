namespace Market {

// A BUILDER HOLDING A BUILD TASK IS EITHER WALKING TO ITS SITE OR BUILDING.
// Neither, for long enough, is stuck. Watched 2026-09-06: the commander was
// sent to an LLT, stopped 240 elmos short of it, and stood on one coordinate
// for 2m10s with the frame at 0.00 while metal overflowed -- freed only when
// an unrelated energy-stall interrupt happened to abort the task.
//
// Abort is the whole response, deliberately. Re-election is idempotent when
// the job was right (he takes it again and gets a FRESH move order, which is
// exactly what a builder stopped short of its site needs) and curative when it
// was not, so this never has to work out WHY he stopped.
array<Id>    gStuckId;
array<float> gStuckX;
array<float> gStuckZ;
array<float> gStuckDone;
array<float> gStuckDist;     // nearest the unit has been to its site
array<int>   gStuckSince;
array<int>   gStuckDeadAt;   // first frame seen holding a task with no engine order
// The engine applies an order some frames after it is given, and the lag
// scales with sim speed (S13): 18-90 frames at 37x, 1-3 at 1x. Measured on
// every task-holder that goes from no order to one, so the dead wait is
// sized to this game's own lag and never to a clock.
int gOrderLagMax = 0;
uint gStuckCursor = 0;
int  gStuckFreed = 0;
int  gStuckLogAt = 0;
int  gNextStuckComLog = 0;
bool unit_is_comm(CCircuitUnit@ u) { return u.circuitDef.IsRoleAny(Unit::Role::COMM.mask); }

// Under one building footprint: the position is the engine's own, so there is
// no jitter to filter -- the watched commander held the same integer coordinate
// for 3,900 frames.
const float STUCK_MOVED = 16.f;

int StuckSlot(Id id)
{
	for (uint i = 0; i < gStuckId.length(); ++i) {
		if (gStuckId[i] == id)
			return int(i);
	}
	return -1;
}

void StuckDrop(uint i)
{
	gStuckId.removeAt(i);
	gStuckX.removeAt(i);
	gStuckZ.removeAt(i);
	gStuckDone.removeAt(i);
	gStuckDist.removeAt(i);
	gStuckSince.removeAt(i);
	gStuckDeadAt.removeAt(i);
}

void UpdateStuckBuilds()
{
	const float secs = ai.GetTunable("apex_stuck_secs", TUNE_STUCK_SECS);
	if (secs <= 0.f)
		return;
	const uint n = gWorkers.length();
	if (n == 0)
		return;
	// A slice per call, not the fleet: each unit is compared against its OWN
	// last sample, so visiting it every eighth pass measures the same thing at
	// an eighth of the per-frame cost.
	const uint step = (n + 7) / 8;
	// Gathered, not aborted in place: Abort re-elects, and a re-election can
	// append to gWorkers underneath the cursor we are walking.
	array<CCircuitUnit@> freed;
	array<IUnitTask@> freedTask;
	for (uint k = 0; k < step; ++k) {
		if (gStuckCursor >= n)
			gStuckCursor = 0;
		CCircuitUnit@ u = gWorkers[gStuckCursor++];
		if (u is null)
			continue;
		IUnitTask@ t = u.task;
		const int slot = StuckSlot(u.id);
		// Only a task raising a building can stall this way; repair, reclaim
		// and patrol hold no frame whose progress could be read.
		if ((t is null) || (t.buildDef is null)) {
			if (slot >= 0)
				StuckDrop(uint(slot));
			continue;
		}
		AIFloat3 p = u.GetPos(ai.frame);
		const float done = Requests::Progress(t);
		// A task-holder the engine has no order for is not walking and not
		// building, and the engine fires no idle for a unit that was already
		// idle when its order was refused: nothing ends this but us. Off his
		// site only -- on it, a dropped order is the DLL's retry to make.
		const AIFloat3 bp0 = t.GetBuildPos();
		const bool noOrder = (u.CmdQueueSize() == 0) && OnMap(bp0)
			&& (p.distance2D(bp0) > Catalog::gBuildDist[int(u.circuitDef.id)]);
		// ON THE SITE WITH AN ORDER IS NOT STUCK, however still the frame: a
		// build starved by an energy stall makes no progress for minutes, and
		// reading that as stuck aborted a framed T2 lab twice in the canon game
		// (2026-09-08) and cost four minutes of T2.
		// ON THE JOB means building, or standing in reach with an order --
		// not "near the site": within reach+64 counted as working, and a
		// commander stood 2.5 min at 178 elmo from a site it could not
		// reach, progress 0, re-armed every pass.
		const float dSite0 = OnMap(bp0) ? p.distance2D(bp0) : -1.f;
		// The engine builds from buildDistance plus the buildee's own radius:
		// a hand 180 elmo from a converter's centre is building it.
		const int bdId = int(t.buildDef.id);
		const int foot = (Catalog::gFootX[bdId] > Catalog::gFootZ[bdId])
				? Catalog::gFootX[bdId] : Catalog::gFootZ[bdId];
		const float reach = Catalog::gBuildDist[int(u.circuitDef.id)]
				+ float(foot) * 8.f + 16.f;
		const bool inReach = (dSite0 >= 0.f) && (dSite0 <= reach);
		const bool onJob = (u.CmdQueueSize() > 0) && inReach;
		if (slot < 0) {
			gStuckId.insertLast(u.id);
			gStuckX.insertLast(p.x);
			gStuckZ.insertLast(p.z);
			gStuckDone.insertLast(done);
			gStuckDist.insertLast(dSite0);
			gStuckSince.insertLast(ai.frame);
			gStuckDeadAt.insertLast(noOrder ? ai.frame : -1);
			continue;
		}
		const uint i = uint(slot);
		if (unit_is_comm(u) && (ai.frame >= gNextStuckComLog)) {
			gNextStuckComLog = ai.frame + 15 * SECOND;
			AiLog(Factory::T() + "apex: stuck-com q=" + u.CmdQueueSize()
				+ " dSite=" + int(dSite0) + " best=" + int(gStuckDist[i])
				+ " reach=" + int(reach)
				+ " done=" + formatFloat(done, "", 0, 2) + "/" + formatFloat(gStuckDone[i], "", 0, 2)
				+ " onJob=" + (onJob ? 1 : 0) + " noOrder=" + (noOrder ? 1 : 0)
				+ " sinceS=" + int(float(ai.frame - gStuckSince[i]) / float(SECOND))
				+ " secs=" + int(secs));
		}
		if (onJob) {
			gStuckSince[i] = ai.frame;
			gStuckDeadAt[i] = -1;
			continue;
		}
		if (!noOrder) {
			if (gStuckDeadAt[i] >= 0) {
				const int lag = ai.frame - gStuckDeadAt[i];
				if (lag > gOrderLagMax)
					gOrderLagMax = lag;
			}
			gStuckDeadAt[i] = -1;
		} else if (gStuckDeadAt[i] < 0) {
			gStuckDeadAt[i] = ai.frame;
		}
		// The order-lag verdict only hurries the 30 s stuck rule; it never
		// undercuts a third of it. At 2 s it beat the engine to the order.
		int deadWait = 3 * gOrderLagMax;
		if (deadWait < int(secs * float(SECOND)) / 3)
			deadWait = int(secs * float(SECOND)) / 3;
		// No verdict before the lag has been measured once: the 2 s floor
		// fired before any order could arrive, aborting the lab 13 times in
		// a row -- and each abort kept the lag from ever being learned.
		const bool dead = (gOrderLagMax > 0) && (gStuckDeadAt[i] >= 0)
				&& (ai.frame - gStuckDeadAt[i] >= deadWait);
		const float dx = p.x - gStuckX[i];
		const float dz = p.z - gStuckZ[i];
		// A hand that MOVED or whose frame GREW is not dead whatever the
		// queue read: the order-lag verdict freed a commander mid-walk to his
		// lab three times (q=0 at 3 s, toSite 422 -> 387), and the plant
		// ask was blocked for 15 minutes behind the orphan he left.
		// With a site, only getting NEARER it counts as moving: a unit
		// pushing at a wall it cannot path through drifts a few elmos a
		// second and read as walking.
		// Against the distance at the LAST RESET, not the best so far: a slow
		// walker closes 6-15 elmo between visits, never 16 in one, and was
		// aborted every 30 s on a 3,000-elmo walk (his game: 103 aborts).
		const bool nearer = (dSite0 >= 0.f) && (gStuckDist[i] >= 0.f)
				&& (dSite0 < gStuckDist[i] - STUCK_MOVED);
		const bool moved = (dSite0 < 0.f)
				&& ((dx * dx + dz * dz) > (STUCK_MOVED * STUCK_MOVED));
		// A frame growing under OTHER hands does not excuse a hand that is
		// not in reach of it (the commander held a converter 207 elmo off
		// for four minutes while others built it).
		const bool assisting = (done > gStuckDone[i])
				&& ((dSite0 < 0.f) || (dSite0 <= reach + 64.f));
		if (nearer || moved || assisting) {
			gStuckX[i] = p.x;
			gStuckZ[i] = p.z;
			gStuckDone[i] = done;
			if (dSite0 >= 0.f)
				gStuckDist[i] = dSite0;   // the distance this reset was taken at
			gStuckSince[i] = ai.frame;
			continue;
		}
		if (!dead && (float(ai.frame - gStuckSince[i]) < secs * float(SECOND)))
			continue;
		++gStuckFreed;
		// HOW FAR FROM THE SITE IT STOPPED. A parked builder at ~0 is standing
		// ON the site refusing to place; a parked builder far from it stopped
		// short. Those are different bugs and the abort hides both.
		const AIFloat3 bp = t.GetBuildPos();
		const float dSite = OnMap(bp) ? p.distance2D(bp) : -1.f;
		AiLog("apex: stuck -- " + u.circuitDef.GetName() + " #" + u.id
			+ " held " + t.buildDef.GetName()
			+ " progress=" + formatFloat(done, "", 0, 2)
			+ " toSite=" + formatFloat(dSite, "", 0, 0)
			+ " buildDist=" + formatFloat(Catalog::gBuildDist[int(u.circuitDef.id)], "", 0, 0)
			+ " still " + int(float(ai.frame - gStuckSince[i]) / float(SECOND))
			+ "s at " + int(p.x) + "," + int(p.z)
			+ (dead ? (" q=0 lagMax=" + gOrderLagMax + " -- no engine order, re-electing") : " -- re-electing"));
		// The site is at fault only when the hand stalled NEAR it; a walk that
		// stalled far away says nothing about the site.
		if ((dSite > reach) && (dSite <= 4.f * reach) && (done <= 0.f))
			BlockNote(bp);
		freed.insertLast(u);
		freedTask.insertLast(t);
		StuckDrop(i);
	}
	for (uint i = 0; i < freed.length(); ++i) {
		DebtNote(freed[i], freedTask[i]);   // before Abort: the task holds the frame
		freedTask[i].Abort();
	}
	if (ai.frame >= gStuckLogAt) {
		gStuckLogAt = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: stuckwatch freed=" + gStuckFreed
			+ " tracked=" + gStuckId.length() + " workers=" + n);
	}
}

}  // namespace Market
