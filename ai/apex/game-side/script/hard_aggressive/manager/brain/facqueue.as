namespace Brain {

//------------------------------------------------------------------------------
// QUOTA MODE: A FACTORY IS TOLD HOW MANY, NOT WHAT NEXT.
//
// apexearth: "'Quota Mode' -- where you simply set a desired target quantity and
// the factory will make sure we build up to that quantity", and on how the
// target is reached: "Calculate how much total army you want, then fill up the
// quota to the ratio of those units that you want. (round up). Remember each
// factory has it's own unique quota."
//
// So each driven line holds a target COUNT per unit type, and every tick we
// order only the shortfall -- quota minus what we hold minus what is already on
// its way. A quota that is met orders nothing, which is what bounds production
// without anything having a cap: the target itself is economic.
//
// REPEAT IS OFF, AND THAT IS THE WHOLE POINT. The first version of this file
// laid a composition down and set CmdRepeat(true). apexearth: "With repeat being
// on the amount you've queued will never go down. So you just have factory #s
// that will perpetually keep going higher." Measured in that run: 129 orders
// issued against 253 combat units registered on one line -- production had come
// loose from the plan. Worse, a floor inside the loop can never leave it: the
// constructor was one order in ten, and the re-lay test needed a third of the
// composition to move, so Builder::ConsWantedFor -- the economy curve that is
// supposed to bound constructors -- could not bind at all.
//
// Orders are issued ONE AT A TIME AND INTERLEAVED, round-robin over the types
// that are short, so the line builds the ratio rather than a run of one type.
// apexearth: "If you add 5 then instead of spreading out our build we'll build 5
// of one type and then 5 of the next, etc... that is not good." The count
// argument of CmdBuildUnit is therefore always 1.
//
// THE TWO SCHEMES STILL CANNOT SHARE A FACTORY. CRecruitTask::Finish() calls
// Cancel(), which CmdRemoves every build order still queued, so one recruit task
// on a driven line wipes the shortfall we just ordered. A driven line is held on
// a Wait task and answered by nothing else. See docs/19-factory-through-brain.md.
//------------------------------------------------------------------------------

// The Wait task's timeout, in frames. When it expires the factory goes idle and
// AiMakeTask is called for it again, which is our re-entry point; the orders on
// the line are untouched by any of that.
const int FQ_WAIT = 30 * SECOND;

// HOW MANY OF OUR ORDERS MAY BE ON A LINE AT ONCE. Not a bound on production --
// the quota is that -- but on how much of the shortfall is committed to the
// factory in advance, so the mix can still answer a change in the enemy's army
// instead of it being queued behind seventy raiders. Two is what BAR's own quota
// widget effectively holds: the unit being built, and the next one.
const float FQ_AHEAD_DEFAULT = 2.f;

// How close a finished unit must be to a driven factory to be counted as having
// come off it. Units appear on the factory's build pad.
const float FQ_CLAIM_RANGE = 400.f;

array<Id> gFQId;                 // factories we drive, by id
array<CCircuitUnit@> gFQFac;     // ...and their handles, parallel to gFQId

int gFQOrders = 0;               // build orders issued, all lines
int gFQMilReq = 0;               // military task requests, see NoteMilRequest
int gNextFQLog = 0;

bool FacQueueOn()
{
	return ai.GetTunable("apex_fac_queue_brain", 1.f) > 0.f;
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
}

// HOW MUCH ARMY THIS LINE IS FOR.
//
// Not a number invented here: brain/budget.as already states what share of
// everything we build should be army, and gSpentTotal is what we have actually
// built. Their product is the army that share has paid for, and each driven line
// owns an equal part of it. It grows with the economy because everything else
// does, which is the answer apexearth gives every time a bound is asked about.
float ArmyMetalPerLine()
{
	const uint lines = (gFQFac.length() > 0) ? gFQFac.length() : 1;
	return (gSpentTotal * TargetShare(ARMY)) / float(lines);
}

int RoundUp(float v)
{
	if (v <= 0.f)
		return 0;
	int q = int(v);
	if (float(q) < v)
		++q;
	return q;
}

// THE QUOTA FOR ONE LINE: a target count per unit type it can build.
//
// The combat roles come from the mix -- the same base/counter blend NextForMix
// reads -- turned from a share of metal into a count of units by the cost of the
// unit that fills the role, rounded up. Build power and eyes are quantities
// already, and keep the curves that own them: Builder::ConsWantedFor is what an
// economy is worth in constructors, and the scout floor scales with the ground
// there is to watch.
void QuotaFor(CCircuitUnit@ fac, array<CCircuitDef@>@ defs, array<int>@ want)
{
	defs.resize(0);
	want.resize(0);
	InitMix();
	if ((fac is null) || (gMix.length() == 0))
		return;

	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con !is null) && con.IsAvailable(ai.frame)) {
		int cap = Builder::ConsWantedFor(con);
		if (aiEconomyMgr.isMetalFull)
			cap = int(float(cap) * ai.GetTunable("apex_con_full_mult", 1.5f)) + 1;
		defs.insertLast(con);
		want.insertLast(cap);
	}

	if (ai.GetTunable("apex_mix_scout", 1.f) > 0.f) {
		CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
		if ((scout !is null) && scout.IsAvailable(ai.frame)) {
			const float per = ai.GetTunable("apex_mix_scout_per_mex",
					Targets::At(Targets::SCOUT_PER_MEX));
			int n = 1;
			if (per >= 1.f) {
				CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
				if (mex !is null)
					n = 1 + int(float(mex.count) / per);
			}
			defs.insertLast(scout);
			want.insertLast(n);
		}
	}

	float weight = 0.f;
	array<float> counter = CounterShares(fac, weight);
	array<float> base = BaseShares();

	// The shares are stated over every role in the mix; a line that cannot build
	// half of them would otherwise quietly aim for half an army. Normalising over
	// what this line CAN build is what makes the quota that line's own.
	float sum = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		const float s = Target(i, base, counter, weight);
		if (s > 0.f)
			sum += s;
	}
	if (sum <= 0.f)
		return;

	const float armyM = ArmyMetalPerLine();
	for (uint i = 0; i < gMix.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame) || (d.costM <= 0.f))
			continue;
		const float s = Target(i, base, counter, weight);
		if (s <= 0.f)
			continue;
		defs.insertLast(d);
		want.insertLast(RoundUp((s / sum) * armyM / d.costM));
	}
}

// FILLING THE QUOTA, THE WAY BAR'S OWN QUOTA MODE DOES IT.
//
// apexearth: "You are not using Quota mode. You are just adding a lot of things
// on the Queue mode."
//
// He was right, and the reason was mechanical: every earlier version had to
// GUESS what was already on the factory, because nothing in the bound surface
// reads a unit's command queue. Tracking orders by type left phantoms that
// silenced the line; crediting any nearby unit over-credited and kept appending.
// Both are the same mistake in different clothes.
//
// BAR's own widget (luaui/Widgets/unit_factory_quota.lua) does not guess. It
// reads the queue with Spring.GetFactoryCommands, and every 15 frames it adds
// ONE unit -- whichever type has the lowest count/quota ratio -- and only while
// its own previous order is no longer at the head. The queue never grows.
//
// CCircuitUnit::CountQueued is that same read, bound for this. So this is the
// widget's loop: one order at a time, neediest ratio first, and nothing added
// while the line still has our orders on it.
//
// Nothing here replaces the factory's queue. A replace would take the unit
// under construction with it, and the widget goes out of its way not to do that
// either -- it refuses to displace a build more than 7.5% done.
void FillQuota(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	const int ahead = int(ai.GetTunable("apex_fac_ahead", FQ_AHEAD_DEFAULT));
	if (fac.CountQueued(null) >= ahead)
		return;

	array<CCircuitDef@> defs;
	array<int> want;
	QuotaFor(fac, defs, want);

	CCircuitDef@ best = null;
	float worst = 1.0e18f;
	for (uint i = 0; i < defs.length(); ++i) {
		if (want[i] <= 0)
			continue;
		// Held plus already ordered: the widget counts the units a factory has
		// alive, and reading the queue is what stops the same shortfall being
		// ordered again on the next tick.
		const int have = defs[i].count + fac.CountQueued(defs[i]);
		if (have >= want[i])
			continue;
		const float ratio = float(have) / float(want[i]);
		if (ratio < worst) {
			worst = ratio;
			@best = defs[i];
		}
	}
	if (best is null)
		return;      // every quota met: the line stops, which is the point

	fac.CmdBuildUnit(best, 1, false);
	++gFQOrders;
	if (gFQOrders <= 5 || (gFQOrders % 25 == 0)) {
		AiLog(Factory::T() + "apex: facqueue " + fac.circuitDef.GetName() + " #"
			+ fac.id + " +1 " + best.GetName() + " (have " + best.count
			+ ", quota-ratio " + formatFloat(worst, "", 0, 2)
			+ ", queued " + fac.CountQueued(null) + ")");
	}
}

// A RECRUIT TASK ALREADY ASSIGNED TO THIS FACTORY WILL WIPE OUR QUEUE.
//
// CRecruitTask::Finish() calls Cancel(), which CmdRemoves every build order left
// on the factory -- it does not know, or care, which of them were its own. A line
// we take mid-game has such tasks on it already, from the opener and from
// whatever the mix enqueued before the takeover, and each one that completes
// silences the line until the stuck detector notices 90 seconds later. Measured
// 2026-08-12: a taken vehicle plant produced 5 units in 6 minutes, and the units
// that DID appear were ones we had never ordered.
//
// Factory::gQTask is the pending recruit list, mirrored from the task hooks
// because CFactoryManager::GetTasks is not bound. Aborting is safe here and only
// here: it happens once, before our first order goes down.
void AbortRecruitsOn(CCircuitUnit@ fac)
{
	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		// An UNSTARTED recruit task -- no factory has taken it -- is the backlog
		// that made CFactoryManager want more factories. Nothing can ever start
		// it once we drive the lines, because a driven line refuses recruits, so
		// it would sit in the pending list for the rest of the game. A factory we
		// do NOT drive can create its own again on its next ask.
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

// Take a line and hold it. The first order replaces whatever is on the factory,
// which clears anything a recruit task left there; repeat is turned off because
// a looping queue is production with no target at all.
IUnitTask@ FactoryQueueTask(CCircuitUnit@ fac)
{
	if (!FacQueueOn() || (fac is null))
		return null;

	int line = FQIndex(fac.id);
	if (line < 0) {
		array<CCircuitDef@> defs;
		array<int> want;
		QuotaFor(fac, defs, want);
		if (defs.length() == 0)
			return null;      // not a line we can drive: a nano turret has no roles
		gFQId.insertLast(fac.id);
		gFQFac.insertLast(fac);
		line = int(gFQId.length()) - 1;
		AbortRecruitsOn(fac);
		fac.CmdRepeat(false);
		AiLog(Factory::T() + "apex: facqueue takes " + fac.circuitDef.GetName()
			+ " #" + fac.id + " (CRecruitTask off for this line)");
		FillQuota(line);
	}
	return aiFactoryMgr.Enqueue(TaskS::Wait(false, FQ_WAIT));
}

// Recruit orders nobody can ever start, swept up as they appear.
//
// AbortRecruitsOn clears the backlog when a line is TAKEN, which is not enough:
// Factory::AiUnitAdded enqueues an opener for every new factory, and once every
// line is driven those orders can never be assigned to anything. They then sit
// in the pending list forever, and a pending list that never drains is one of
// the things CFactoryManager answers by building another factory -- the seven
// bot labs above. Only while we drive every factory we own; below that, a line
// we do not drive can still take them.
int gNextSweep = 0;

void SweepDeadRecruits()
{
	if (ai.frame < gNextSweep)
		return;
	gNextSweep = ai.frame + 5 * SECOND;
	if ((gFQFac.length() == 0)
		|| (int(gFQFac.length()) < aiFactoryMgr.GetFactoryCount()))
		return;

	array<IUnitTask@> doomed;
	for (uint i = 0; i < Factory::gQTask.length(); ++i) {
		IUnitTask@ t = Factory::gQTask[i];
		if (t is null)
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if ((on is null) || (on.length() == 0))
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
	for (uint i = 0; i < gFQFac.length(); ++i)
		FillQuota(int(i));
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
	AiLog(Factory::T() + "apex: facqueue lines=" + gFQFac.length()
		+ " orders=" + gFQOrders
		+ " armyM/line=" + formatFloat(ArmyMetalPerLine(), "", 0, 0)
		+ " milreq=" + gFQMilReq);
}

}  // namespace Brain
