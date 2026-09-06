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
		if (slot < 0) {
			gStuckId.insertLast(u.id);
			gStuckX.insertLast(p.x);
			gStuckZ.insertLast(p.z);
			gStuckDone.insertLast(done);
			gStuckSince.insertLast(ai.frame);
			continue;
		}
		const uint i = uint(slot);
		const float dx = p.x - gStuckX[i];
		const float dz = p.z - gStuckZ[i];
		if (((dx * dx + dz * dz) > (STUCK_MOVED * STUCK_MOVED))
			|| (done > gStuckDone[i]))
		{
			gStuckX[i] = p.x;
			gStuckZ[i] = p.z;
			gStuckDone[i] = done;
			gStuckSince[i] = ai.frame;
			continue;
		}
		if (float(ai.frame - gStuckSince[i]) < secs * float(SECOND))
			continue;
		++gStuckFreed;
		AiLog("apex: stuck -- " + u.circuitDef.GetName() + " #" + u.id
			+ " held " + t.buildDef.GetName()
			+ " progress=" + formatFloat(done, "", 0, 2)
			+ " still " + int(float(ai.frame - gStuckSince[i]) / float(SECOND))
			+ "s at " + int(p.x) + "," + int(p.z) + " -- re-electing");
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
