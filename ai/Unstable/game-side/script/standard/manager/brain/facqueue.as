namespace Brain {

//------------------------------------------------------------------------------
// THE PRODUCTION EXECUTOR. KILL PHASE (docs/20-brain-overhaul.md): the quota
// machinery is gone; what remains is the line MECHANICS -- adoption, the
// Wait-hold, the recruit abort and sweep, and the sent-ledger. Every factory
// line is taken and held; Market::ConOrderFor hands this executor its orders.
// Nothing here computes what to build.
//
// A line is kept fed a WINDOW of work rather than a single order: the Wait
// task ignores OnUnitIdle, so a line that finishes its last unit sits idle
// until the timeout re-elects it.
//
// THE TWO SCHEMES CANNOT SHARE A FACTORY. CRecruitTask::Finish() calls
// Cancel(), which CmdRemoves every build order still queued, so one recruit
// task on a driven line wipes whatever the executor ordered. A driven line is
// held on a Wait task and answered by nothing else.
//------------------------------------------------------------------------------

// The Wait task's timeout, in frames. When it expires the factory goes idle and
// AiMakeTask is called for it again, which is our re-entry point.
const int FQ_WAIT = 10 * SECOND;   // 30 made one unit per ~25s: the line idled on its own hold

array<Id> gFQId;                 // factories we drive, by id
array<CCircuitUnit@> gFQFac;     // ...and their handles, parallel to gFQId
array<int> gFQSeen;              // ...and the queue depth we last observed
array<int> gFQAt;                // ...and the frame we last sent one an order
array<int> gFQEvt;               // ...and the frame the line last did ANYTHING

// EVERY ORDER STILL OUTSTANDING, as a flat FIFO of (line, def) pairs, retired
// only when the unit is FINISHED. Reads lag sends by a whole order window
// (AICallback.cpp), so CountQueued cannot retire an entry -- it reads zero for
// work that is really on the line, and retiring on it made the ledger
// undercount and the line over-order.
array<int> gFQPendLine;
array<CCircuitDef@> gFQPendDef;

int gFQOrders = 0;               // build orders issued, all lines
int gFQMilReq = 0;               // military task requests, see NoteMilRequest
int gFQLost = 0;                 // orders presumed lost
int gNextFQLog = 0;
int gFQIdleLog = 0;

void PendAdd(int line, CCircuitDef@ d)
{
	gFQPendLine.insertLast(line);
	gFQPendDef.insertLast(d);
}

int PendCount(int line, CCircuitDef@ d)
{
	int n = 0;
	for (uint i = 0; i < gFQPendLine.length(); ++i) {
		if ((gFQPendLine[i] == line) && ((d is null) || (gFQPendDef[i] is d)))
			++n;
	}
	return n;
}

// Orders SENT for this def on any line and not yet visible as a unit. The
// count of what we own lags a send by the whole walk window, so any "read what
// we have, top it up" demand issues one order per tick for that window --
// measured as nine jammers against a demand of two.
int PendAnyOf(int defId)
{
	int n = 0;
	for (uint i = 0; i < gFQPendDef.length(); ++i) {
		if ((gFQPendDef[i] !is null) && (int(gFQPendDef[i].id) == defId))
			++n;
	}
	return n;
}

// Drop the OLDEST n entries for this line: the queue is FIFO, so the orders that
// have become visible are the ones we sent first.
void PendDrop(int line, int n)
{
	for (uint i = 0; (i < gFQPendLine.length()) && (n > 0); ) {
		if (gFQPendLine[i] == line) {
			gFQPendLine.removeAt(i);
			gFQPendDef.removeAt(i);
			--n;
			continue;
		}
		++i;
	}
}

// Lines shift down when one is forgotten, so every stored index must shift too.
void PendReindex(int gone)
{
	for (int i = int(gFQPendLine.length()) - 1; i >= 0; --i) {
		if (gFQPendLine[i] == gone) {
			gFQPendLine.removeAt(i);
			gFQPendDef.removeAt(i);
		} else if (gFQPendLine[i] > gone) {
			gFQPendLine[i] -= 1;
		}
	}
}

// What actually builds on this line: the plant's own workertime plus the share
// of the assist turrets standing over the base. Which turret serves which line
// is not tracked; an even share is enough to size a queue with.
float LineBuildPower(CCircuitUnit@ fac)
{
	if ((fac is null) || (fac.circuitDef is null))
		return 0.f;
	const float own = Catalog::gBuildPower[int(fac.circuitDef.id)];
	return (own > 0.f) ? own * (1.f + Market::AssistBPShare()) : 0.f;
}

// Work outstanding on a line, in seconds of that line's own build time.
// `skipHead` drops the oldest entry -- the one the plant is building now.
//
// THE BUFFER IS WHAT MATTERS, NOT THE TOTAL. Measuring total work let a single
// long unit satisfy the target on its own: every unit an armlab makes takes 11
// to 28 seconds, so one order cleared a 15-second bar, and the line went empty
// the moment it finished and stayed empty until the next election (apexearth,
// watched: "we are idle until we queue the next unit"). What must never run
// out is the work standing BEHIND the head.
float LineSeconds(int line, CCircuitUnit@ fac, bool skipHead)
{
	const float bp = LineBuildPower(fac);
	if (bp <= 0.f)
		return 1e9f;
	float sec = 0.f;
	bool head = skipHead;
	for (uint i = 0; i < gFQPendLine.length(); ++i) {
		if ((gFQPendLine[i] != line) || (gFQPendDef[i] is null))
			continue;
		if (head) {          // the ledger is FIFO: the oldest is in progress
			head = false;
			continue;
		}
		sec += Catalog::BuildSecondsAt(int(gFQPendDef[i].id), bp);
	}
	return sec;
}

// How deep a line is kept, in seconds of work. Anything under the re-election
// gap is idle time by construction; the margin over it covers the order lag,
// which is a whole window of its own at benchmark speed.
float LineWindow()
{
	const float m = ai.GetTunable("apex_fac_queue", TUNE_FAC_QUEUE);
	return float(FQ_WAIT) / float(SECOND) * ((m > 1.f) ? m : 1.f);
}

bool FacQueueOn()
{
	return ai.GetTunable("apex_fac_queue_brain", TUNE_FAC_QUEUE_BRAIN) > 0.f;
}

int FQIndex(Id id)
{
	for (uint i = 0; i < gFQId.length(); ++i) {
		if (gFQId[i] == id)
			return int(i);
	}
	return -1;
}

// Is this line ours? Factory::AiMakeTask asks before anything else runs.
bool DrivenFactory(CCircuitUnit@ fac)
{
	return (fac !is null) && (FQIndex(fac.id) >= 0);
}

// CCircuitUnit is registered NOCOUNT, so a stored handle is not nulled when the
// engine destroys the unit -- `is null` stays false on freed memory. Every entry
// here must be dropped from AiUnitRemoved, which is what ReleaseFactory does.
void FQForget(Id id)
{
	const int i = FQIndex(id);
	if (i < 0)
		return;
	gFQId.removeAt(i);
	gFQFac.removeAt(i);
	gFQSeen.removeAt(i);
	gFQAt.removeAt(i);
	gFQEvt.removeAt(i);
	PendReindex(i);
}

// A dead factory must not keep its line: ids are reused, and the next unit to
// take this one would silently inherit "the Brain owns this line".
void ReleaseFactory(Id id)
{
	FQForget(id);
}

void AbortRecruitsOn(CCircuitUnit@ fac)
{
	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		// An UNSTARTED recruit task -- no factory has taken it -- is backlog
		// nothing can ever start once every line is driven.
		if ((on is null) || (on.length() == 0)) {
			doomed.insertLast(t);
			continue;
		}
		for (uint u = 0; u < on.length(); ++u) {
			if (on[u].id == fac.id) {
				doomed.insertLast(t);
				break;
			}
		}
	}
	// Abort() runs AiTaskRemoved, which mutates gQTask -- collect first, then act.
	for (uint i = 0; i < doomed.length(); ++i)
		doomed[i].Abort();
	if (doomed.length() > 0) {
		AiLog(Factory::T() + "apex: facqueue aborted " + doomed.length()
			+ " recruit task(s) still holding " + fac.circuitDef.GetName()
			+ " #" + fac.id);
	}
}

// Take a line and hold it. The first Wait replaces whatever a recruit task left
// on the factory; repeat is turned off because a looping queue is production
// with no target at all. During the kill phase no orders are ever laid.
IUnitTask@ FactoryQueueTask(CCircuitUnit@ fac)
{
	if (!FacQueueOn() || (fac is null))
		return null;

	int line = FQIndex(fac.id);
	if (line < 0) {
		gFQId.insertLast(fac.id);
		gFQFac.insertLast(fac);
		gFQSeen.insertLast(0);
		gFQAt.insertLast(ai.frame);
		gFQEvt.insertLast(ai.frame);
		line = int(gFQId.length()) - 1;
		AbortRecruitsOn(fac);
		fac.CmdRepeat(false);
		AiLog(Factory::T() + "apex: facqueue takes " + fac.circuitDef.GetName()
			+ " #" + fac.id + " (CRecruitTask off for this line)");
	}

	// A DROUGHT, not a stale read, is what retires an order the engine never
	// took: nothing visible on the line, nothing finished off it, and nothing
	// sent to it for a minute. NoteProduced is the honest retirement.
	if ((PendCount(line, null) > 0) && (fac.CountQueued(null) == 0)
		&& (ai.frame - gFQEvt[line] > 60 * SECOND))
	{
		gFQLost += PendCount(line, null);
		PendDrop(line, PendCount(line, null));
	}

	// KEEP THE LINE FED. One order per election idled the plant for the whole
	// re-election gap after every unit: IWaitTask ignores OnUnitIdle, so
	// nothing looks at a finished line until the Wait times out. The batch is
	// measured as the build SECONDS standing BEHIND the unit in progress, so
	// the plant always has the next order in hand when one completes. Each slot is priced by the market separately, against a ledger
	// that already holds the slots before it -- so a floor satisfied by slot 0
	// does not repeat, and the mix is the market's, not a ratio table's.
	array<CCircuitDef@> batch;
	const int outstanding = PendCount(line, null);
	const float window = LineWindow();
	// The bound is a non-termination guard (a def with no build time), not a
	// cap on production: LineSeconds grows with every slot and ends the loop.
	for (int slot = 0; slot < 16; ++slot) {
		if (LineSeconds(line, fac, true) >= window)
			break;
		CCircuitDef@ o = Market::ConOrderFor(fac, line, slot);
		if (o is null)
			break;
		batch.insertLast(o);
		PendAdd(line, o);
	}
	// AN ELECTION THAT ORDERS NOTHING IS IDLE FACTORY TIME. Logged with the
	// market's own reason, rate-limited per line, because the gap between
	// orders is otherwise invisible -- measured 2026-08-25 at 1 to 9 silent
	// elections between orders on a single lab.
	if ((batch.length() == 0) && (fac.CountQueued(null) == 0)
		&& (ai.frame >= gFQIdleLog))
	{
		gFQIdleLog = ai.frame + 10 * SECOND;
		AiLog(Factory::T() + "apex: facqueue idle " + fac.circuitDef.GetName()
			+ " #" + fac.id + " nothing ordered: "
			+ (Market::gNoOrder.length() > 0 ? Market::gNoOrder : "priced-out"));
	}
	if (batch.length() > 0) {
		// EXACTLY ONE UNIT PER ORDER: a SHIFT append is multiplied by five
		// inside CFactoryCAI, so CmdInsertBuild is the only append that queues
		// what the market asked for. It lands at position 1 -- behind whatever
		// is being built, AHEAD of everything else -- so the batch is issued
		// back to front to come out in the order it was decided, and lands in
		// front of work queued on an earlier pass. That is what puts an escort
		// or a constructor floor in front of the army: those are priced first,
		// so they sit at the head of the batch.
		uint first = 0;
		// A replace order WIPES the queue it lands on, so it is only safe on a
		// line with nothing outstanding at all -- an order still in flight has
		// not landed yet and would be erased by it.
		if ((outstanding == 0) && (fac.CountQueued(null) == 0)) {
			fac.CmdBuildUnit(batch[0], 1, true);
			first = 1;
		}
		for (int i = int(batch.length()) - 1; i >= int(first); --i)
			fac.CmdInsertBuild(batch[i], false);
		gFQAt[line] = ai.frame;
		gFQEvt[line] = ai.frame;
		gFQOrders += int(batch.length());
	}
	return aiFactoryMgr.Enqueue(TaskS::Wait(false, FQ_WAIT));
}

// Recruit orders nobody can ever start, swept up as they appear -- and the
// slip channel: a recruit re-enqueued onto a DRIVEN line inside the GiveOrder
// lag window would build units nobody ordered.
int gNextSweep = 0;

void SweepDeadRecruits()
{
	if (ai.frame < gNextSweep)
		return;
	gNextSweep = ai.frame + 5 * SECOND;
	if (gFQFac.length() == 0)
		return;
	const bool allDriven =
			int(gFQFac.length()) >= aiFactoryMgr.GetFactoryCount();

	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if ((on is null) || (on.length() == 0)) {
			// Unstarted backlog: only safe to kill when every line is
			// driven -- an undriven factory can still legitimately take it.
			if (allDriven)
				doomed.insertLast(t);
			continue;
		}
		bool onDriven = false;
		for (uint u = 0; u < on.length() && !onDriven; ++u) {
			if (on[u] is null)
				continue;
			for (uint g = 0; g < gFQFac.length(); ++g) {
				if ((gFQFac[g] !is null) && (on[u].id == gFQFac[g].id)) {
					onDriven = true;
					break;
				}
			}
		}
		if (onDriven)
			doomed.insertLast(t);
	}
	for (uint i = 0; i < doomed.length(); ++i)
		doomed[i].Abort();
	if (doomed.length() > 0) {
		AiLog(Factory::T() + "apex: facqueue swept " + doomed.length()
			+ " recruit order(s) no line can start");
	}
}

void UpdateFacQueues()
{
	if (!FacQueueOn())
		return;
	SweepDeadRecruits();
}

// The honest reconcile: the ordered unit APPEARED. CountQueued lags sends by
// up to ~45s of game time at bench speed, so ledger-vs-queue comparisons
// starve the line; the finished event does not lie.
void NoteProduced(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	for (uint i = 0; i < gFQPendDef.length(); ++i) {
		if ((gFQPendDef[i] !is null) && (gFQPendDef[i] is unit.circuitDef)) {
			const int line = gFQPendLine[i];
			if ((line >= 0) && (line < int(gFQEvt.length())))
				gFQEvt[line] = ai.frame;
			gFQPendLine.removeAt(i);
			gFQPendDef.removeAt(i);
			return;
		}
	}
}

void NoteMilRequest()
{
	++gFQMilReq;
}

void LogFacQueues()
{
	if (!FacQueueOn() || (gFQFac.length() == 0))
		return;
	if (ai.frame < gNextFQLog)
		return;
	gNextFQLog = ai.frame + 30 * SECOND;
	string d = "";
	for (uint i = 0; i < gFQFac.length(); ++i) {
		d += " #" + gFQFac[i].id + ":" + gFQFac[i].CountQueued(null)
			+ "+" + PendCount(int(i), null)
			+ "/" + formatFloat(LineSeconds(int(i), gFQFac[i], false), "", 0, 0)
			+ "s buf" + formatFloat(LineSeconds(int(i), gFQFac[i], true), "", 0, 0) + "s";
	}
	AiLog(Factory::T() + "apex: facqueue lines=" + gFQFac.length()
		+ " orders=" + gFQOrders + " lost=" + gFQLost
		+ " milreq=" + gFQMilReq + " depth+pend:" + d);
}

}  // namespace Brain
