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
		const bool onJob = (u.CmdQueueSize() > 0) && OnMap(bp0)
			&& (p.distance2D(bp0) <= Catalog::gBuildDist[int(u.circuitDef.id)] + 64.f);
		if (slot < 0) {
			gStuckId.insertLast(u.id);
			gStuckX.insertLast(p.x);
			gStuckZ.insertLast(p.z);
			gStuckDone.insertLast(done);
			gStuckSince.insertLast(ai.frame);
			gStuckDeadAt.insertLast(noOrder ? ai.frame : -1);
			continue;
		}
		const uint i = uint(slot);
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
		int deadWait = 3 * gOrderLagMax;
		if (deadWait < 2 * SECOND)
			deadWait = 2 * SECOND;
		const bool dead = (gStuckDeadAt[i] >= 0) && (ai.frame - gStuckDeadAt[i] >= deadWait);
		const float dx = p.x - gStuckX[i];
		const float dz = p.z - gStuckZ[i];
		// A hand that MOVED or whose frame GREW is not dead whatever the
		// queue read: the order-lag verdict freed a commander mid-walk to his
		// lab three times (q=0 at 3 s, toSite 422 -> 387), and the plant
		// ask was blocked for 15 minutes behind the orphan he left.
		if ((((dx * dx + dz * dz) > (STUCK_MOVED * STUCK_MOVED))
			|| (done > gStuckDone[i])))
		{
			gStuckX[i] = p.x;
			gStuckZ[i] = p.z;
			gStuckDone[i] = done;
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
