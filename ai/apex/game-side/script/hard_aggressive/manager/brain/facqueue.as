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

// HOW MANY UNITS THIS LINE IS FOR: the unit limit, less what we already hold.
//
// apexearth: "Take a look at your unit limit and divvy up your quota based on
// something reasonable. Let's say you have 100 buildings, 2000 unit limit,
// you're in T1... then your split is on 1900 available units."
//
// The previous sizing was a share of metal we had ALREADY SPENT, and it was
// wrong in the way that matters: it lagged, so a met quota stopped the line, and
// a stopped line is how apex fielded army 0/2700/150/0 against stock's
// 5455/6435/5595/6865 in a 22-minute 4v4.
//
// Slots do not lag. They also make the absolute number stop mattering -- split
// 1900 ways by ratio and no combat target is ever reached -- which is the point:
// the quota becomes a SHAPE, "whichever type is furthest below its share goes
// next", and the line only falls quiet when the map is full or the tier moved.
// The engine's own limit is the ceiling, so nothing here invents one.
int SlotsForArmy()
{
	const int limit = ai.GetUnitMax();
	if (limit <= 0)
		return 0;
	// Buildings are the part of the limit that is not army and never will be.
	const int used = ai.GetTeamUnitCount(true);
	const int free = limit - used;
	return (free > 0) ? free : 0;
}

int SlotsPerLine()
{
	const uint lines = (gFQFac.length() > 0) ? gFQFac.length() : 1;
	return SlotsForArmy() / int(lines);
}

// WHAT A TIER IS STILL WORTH ONCE THE NEXT ONE IS ON THE FIELD.
//
// apexearth: "Later when you get to T2 you reduce your target T1, removing some
// entirely, and now target to create T2 units... later on when T3 is on the
// field, adjust your T2 army accordingly."
//
// Dropping a tier's share below what we already hold is what makes its line go
// quiet, because a quota already met orders nothing. That is the one place in
// this design where the absolute number does real work.
float TierShare(CCircuitDef@ d)
{
	const bool isT2 = (Factory::userData[d.id].attr & Factory::Attr::T2) != 0;
	const bool isT3 = (Factory::userData[d.id].attr & Factory::Attr::T3) != 0;
	if (isT3)
		return 1.f;
	if (isT2)
		return Factory::gHaveT3
			? ai.GetTunable("apex_quota_t2_after_t3", 0.4f) : 1.f;
	if (Factory::gHaveT3)
		return ai.GetTunable("apex_quota_t1_after_t3", 0.f);
	return Factory::gHaveT2
		? ai.GetTunable("apex_quota_t1_after_t2", 0.25f) : 1.f;
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

	const float slots = float(SlotsPerLine());
	for (uint i = 0; i < gMix.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame) || (d.costM <= 0.f))
			continue;
		const float s = Target(i, base, counter, weight);
		if (s <= 0.f)
			continue;
		defs.insertLast(d);
		want.insertLast(RoundUp((s / sum) * slots * TierShare(d)));
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
// THE ADVANCED CONSTRUCTOR JUMPS THE QUEUE.
//
// apexearth: "(force your advanced cons to build first by giving them an
// inserted queue mode order)".
//
// A new advanced plant is the one moment where order matters more than ratio:
// everything the tier change is for -- upgraded extractors, the T2 economy, the
// plants that follow -- waits on that constructor, and behind a queue of army it
// arrives minutes late. CmdInsertBuild is CMD_INSERT, so it goes to the front
// WITHOUT clearing the queue or touching the unit under construction.
//
// Once per line: gFQConDone records that this line has had its jump.
array<Id> gFQConDone;

bool ConAlreadyJumped(Id id)
{
	for (uint i = 0; i < gFQConDone.length(); ++i) {
		if (gFQConDone[i] == id)
			return true;
	}
	return false;
}

// THE OPENING IS NOT THROWN AWAY WHEN WE TAKE THE LINE.
//
// Taking a factory aborts the recruit tasks on it, which includes the OPENER --
// the specific first units Opener::GetOpener lays down for that plant, in order.
// Green's log, 0.9 min: "facqueue aborted 10 recruit task(s) still holding
// corlab" -- the whole opening, gone, replaced a second later by whatever the
// quota ratio happened to want. apexearth: "green is still not acting normal",
// and it does the same thing every game because the opener is aborted every
// game.
//
// So the opener is re-issued as our own orders. Inserted in REVERSE: CMD_INSERT
// puts each order at the front, so laying them backwards is what makes the queue
// read forwards.
void OpenerFirst(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	const array<Opener::SO>@ opener = Opener::GetOpener(fac.circuitDef);
	if (opener is null)
		return;
	int laid = 0;
	for (int i = int(opener.length()) - 1; i >= 0; --i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, opener[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		for (uint j = 0; j < opener[i].count; ++j) {
			fac.CmdInsertBuild(d, true);
			++laid;
		}
	}
	gFQOrders += laid;
	AiLog(Factory::T() + "apex: facqueue " + fac.circuitDef.GetName() + " #"
		+ fac.id + " opens with " + laid + " unit(s)");
}

void AdvConFirst(int line)
{
	CCircuitUnit@ fac = gFQFac[line];
	if ((Factory::userData[fac.circuitDef.id].attr & Factory::Attr::T2) == 0)
		return;      // only an advanced plant has an advanced constructor to make
	if (ConAlreadyJumped(fac.id))
		return;
	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con is null) || !con.IsAvailable(ai.frame))
		return;
	gFQConDone.insertLast(fac.id);
	fac.CmdInsertBuild(con, true);
	AiLog(Factory::T() + "apex: facqueue " + fac.circuitDef.GetName() + " #"
		+ fac.id + " inserts " + con.GetName() + " at the front");
}

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

	// INSERT, NEVER SHIFT-APPEND. FactoryCAI::GetCountMultiplierFromOptions is
	// `if (opts & SHIFT_KEY) ret *= 5`, so every append we made was FIVE units,
	// not one -- which is why the line kept filling up however low the look-ahead
	// was set. apexearth: "you're sending their command with shift, which adds 5",
	// and "queuing army 5 at a time is no good... just queue 2 or 3 of what you
	// want". CMD_INSERT carries no multiplier, which is exactly why BAR's own
	// quota widget uses it rather than a shift-append.
	fac.CmdInsertBuild(best, false);
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
		OpenerFirst(line);
		AdvConFirst(line);
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
		+ " slots/line=" + SlotsPerLine() + " limit=" + ai.GetUnitMax()
		+ " milreq=" + gFQMilReq);
}

}  // namespace Brain
