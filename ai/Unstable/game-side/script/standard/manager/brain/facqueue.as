namespace Brain {

//------------------------------------------------------------------------------
// THE PRODUCTION EXECUTOR. KILL PHASE (docs/20-brain-overhaul.md): the quota
// machinery is gone; what remains is the line MECHANICS -- adoption, the
// Wait-hold, the recruit abort and sweep, and the sent-ledger. Every factory
// line is taken and held silent. The rebuilt arbiter will hand this executor
// its orders; nothing here computes what to build.
//
// THE TWO SCHEMES CANNOT SHARE A FACTORY. CRecruitTask::Finish() calls
// Cancel(), which CmdRemoves every build order still queued, so one recruit
// task on a driven line wipes whatever the executor ordered. A driven line is
// held on a Wait task and answered by nothing else.
//------------------------------------------------------------------------------

// The Wait task's timeout, in frames. When it expires the factory goes idle and
// AiMakeTask is called for it again, which is our re-entry point.
const int FQ_WAIT = 30 * SECOND;

array<Id> gFQId;                 // factories we drive, by id
array<CCircuitUnit@> gFQFac;     // ...and their handles, parallel to gFQId
array<int> gFQSeen;              // ...and the queue depth we last observed
array<int> gFQAt;                // ...and the frame we last sent one an order

// ORDERS SENT BUT NOT YET VISIBLE, as a flat FIFO of (line, def) pairs.
// Reads lag sends (AICallback.cpp), so `count + CountQueued(def)` both read
// stale for a whole lag window; this ledger is the ground truth for in-flight
// orders.
array<int> gFQPendLine;
array<CCircuitDef@> gFQPendDef;

int gFQOrders = 0;               // build orders issued, all lines
int gFQMilReq = 0;               // military task requests, see NoteMilRequest
int gFQLost = 0;                 // orders presumed lost
int gNextFQLog = 0;

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
		line = int(gFQId.length()) - 1;
		AbortRecruitsOn(fac);
		fac.CmdRepeat(false);
		AiLog(Factory::T() + "apex: facqueue takes " + fac.circuitDef.GetName()
			+ " #" + fac.id + " (CRecruitTask off for this line)");
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
			+ "+" + PendCount(int(i), null);
	}
	AiLog(Factory::T() + "apex: facqueue lines=" + gFQFac.length()
		+ " orders=" + gFQOrders + " lost=" + gFQLost
		+ " milreq=" + gFQMilReq + " depth+pend:" + d);
}

}  // namespace Brain
