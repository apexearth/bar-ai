namespace Requests {

// ONE PLACE DECIDES WHETHER A BUILDING MAY BE STARTED.
//
// A request queue: something decides we want a building; the request is
// placed once; whoever takes it works it; if the worker is pulled away the
// request goes back to being available; when the building is up the request
// is gone. There is no way to place the same request twice.
//
// THE REQUEST RECORD IS THE ENGINE'S OWN TASK, not a parallel structure, so
// the lifecycle is real rather than bookkeeping kept in step by hand:
//
//   proposed     an IBuilderTask in the queue with no assignee. Available: the
//                next caller that wants this def here is handed THIS task.
//   claimed      GetUnits() is non-empty. A builder is walking to it.
//   in-progress  `target` is set -- IBuilderTask::SetTarget runs when the
//                nanoframe appears (BuilderTask.cpp:403).
//   cancelled    the builder was reassigned; the task keeps its place in the
//                queue with no assignee, i.e. it is proposed again.
//   done/aborted DequeueTask -> AiTaskRemoved -> Forget.
//
// AND IT SEES EVERY PRODUCER, not just the script ones: every task, including
// those made by C++ (DefaultMakeDefence, MakeEconomyTasks, build_chain), is
// created through CBuilderManager::Enqueue, which fires TaskAdded
// (BuilderManager.cpp:744) -> AiTaskAdded -> Register below.

// -- what is governed --------------------------------------------------------
//
// NOT mex/mexup/geo/geoup: two extractor spots are two different things wanted
// for their own sake, there is no duplicate to prevent, and stacking builders on
// one is the opposite of what expansion wants. Those keep their own path.
//
// The rest splits in two, because "duplicate" means different things for them:
//
//   ECONOMY   a second one started at the same time is redundancy. Serialized
//             hard: join an existing one anywhere within reach, and never hold
//             more requests of one def than the income can feed.
//   POSITIONAL(DEFENCE) two towers at two places on the front are BOTH wanted,
//             so only the site itself is exclusive -- one request per patch of
//             ground. How much defence we may hold at all is Builder's
//             DefenceShareScreen and Military::DefenceAllowedAt, which already
//             exist; a second ceiling here would be the same bound twice.
// Live requests of one build type, dead excluded -- the market's plant
// gates count these against the income-support rule, because a factory
// REQUESTED is a factory the count does not see yet (measured: 41 lines
// licensed while gFactoryCount lagged the pipeline).
int LiveCountOf(int bt)
{
	int n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].GetBuildType() == Task::BuildType(bt)))
			++n;
	}
	return n;
}

// An unmanned live request for this def, wherever it stands -- the market
// adopts these before founding a new site (a stall interrupt pulls a con
// off a nano; the re-decided nano must FINISH that frame, not start a
// fresh slot -- watched: nanoframes abandoned beside new starts).
IUnitTask@ OrphanOf(CCircuitDef@ def)
{
	if (def is null)
		return null;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead())
			continue;
		if ((t.buildDef is null) || (t.buildDef !is def))
			continue;
		if (Workers(t) == 0)
			return t;
	}
	return null;
}

// The live task itself, for joining an in-progress build of this def.
IUnitTask@ LiveTaskOf(CCircuitDef@ def)
{
	if (def is null)
		return null;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].buildDef !is null) && (gLive[i].buildDef is def))
			return gLive[i];
	}
	return null;
}

// Any live request (manned or not) for exactly this def.
bool LiveOfDef(CCircuitDef@ def)
{
	if (def is null)
		return false;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].buildDef !is null) && (gLive[i].buildDef is def))
			return true;
	}
	return false;
}

// METAL WORK IS GOVERNED TOO. MEX and MEXUP were absent here, so an extractor
// or an upgrade never entered the register at all: it could not be joined (the
// join rung only sees registered tasks), and it did not count in
// LiveSiteCount, so every other site's crew was sized as though no metal work
// were happening -- while those hands were drawing metal the whole time
// (apexearth 2026-08-25: "if a want is still in progress (like a mexup) we
// should be willing to put more guys on it to build it faster").
bool Governed(int bt)
{
	return (bt == int(Task::BuildType::MEX))
		|| (bt == int(Task::BuildType::MEXUP))
		|| (bt == int(Task::BuildType::FACTORY))
		|| (bt == int(Task::BuildType::NANO))
		|| (bt == int(Task::BuildType::STORE))
		|| (bt == int(Task::BuildType::ENERGY))
		|| (bt == int(Task::BuildType::CONVERT))
		|| (bt == int(Task::BuildType::DEFENCE))
		|| (bt == int(Task::BuildType::BUNKER))
		|| (bt == int(Task::BuildType::BIG_GUN))
		|| (bt == int(Task::BuildType::RADAR))
		|| (bt == int(Task::BuildType::SONAR));
}

bool Positional(int bt)
{
	return (bt == int(Task::BuildType::DEFENCE));
}

// How close counts as the same ground for an EXACT-POINT request. Comfortably
// bigger than any T1/T2 economy footprint, so a real second site a short walk
// away is untouched. An AREA request passes its own radius instead.
const float SAME_SITE = 150.f;

// Beyond this, helping costs more in walk time than it saves, and the script
// cannot ask whether a position is even reachable.
const float REACH = 1500.f;

// How much nearer a request somebody is already working is treated as being,
// when choosing between it and one merely sitting in the queue.
const float ASSIGNED_BIAS = 400.f;

// Below this cost, walking across the base to help is worse than building your
// own -- solar is 155, wind 43, a construction turret 210, a T1 lab 500. It
// bounds JOINING only. Whether a second request may EXIST is a different
// question and is asked at every cost: measured 2026-08-13, armsolar piled six
// duplicates onto one tile.
const float JOIN_MIN_COST = 200.f;

// WORTH THE WALK. A site's remaining build time is (unbuilt metal) / (build
// power already on it); if that is shorter than this unit's walk there, the
// walk buys nothing -- the site finishes, or gets close enough that one more
// constructor is negligible, before it could arrive. apexearth, watching
// 2026-08-14: "our units are willing to walk long distances to build a
// building which would be built by the time they get there."
//
// APPROXIMATE, not exact, for two reasons: CCircuitDef exposes no move-speed
// binding to script (grep of InitScript.cpp confirmed, 2026-08-14), so travel
// time uses one flat assumed speed rather than the joining unit's own -- a
// fast vehicle con may be turned away from a join that would in fact still be
// worth it, while a slow bot con is the case this actually protects. And the
// site's current build power is read as DRAIN per worker already assigned
// (the same per-constructor pull InFlightCap uses elsewhere), not the site's
// true buildSpeed, which script cannot read either.
const float ASSUMED_CON_SPEED = 40.f;  // elmos/s; armck/corck are 36, armcv/corcv 54 (unit defs, 2026-08-14)

bool WorthJoining(float dist, float progress, float costM, uint busy,
		float speed = 0.f)
{
	if (dist <= 0.f)
		return true;
	const float remainingMetal = costM * (1.f - progress);
	if (remainingMetal <= 0.f)
		return false;   // effectively done; nothing left for another builder to add
	const float buildRate = DRAIN * float((busy > 0) ? busy : 1);
	const float remainingTime = remainingMetal / buildRate;
	// THE ASKER'S OWN LEGS (apexearth: "our T1 air cons should be making
	// tons of those" -- a flying con at ~5x ASSUMED_CON_SPEED was refused
	// joins it could make in seconds, 78k tooFar refusals in one watched
	// game, its elections wasted on re-asking).
	const float v = (speed > 1.f) ? speed : ASSUMED_CON_SPEED;
	const float travelTime = dist / v;
	return travelTime <= remainingTime;
}

int gTooFar = 0;    // refused: this site will finish (or near enough) before the walk

// HOW MANY REQUESTS OF ONE DEF MAY BE IN FLIGHT AT ONCE, from what the ECONOMY
// can feed -- never a flat number and never a clock.
//
// A lathe pulls a roughly constant metal/s while it builds, set by its
// buildSpeed and not by what it is building; the cost only decides how long the
// drain lasts. So the number of parallel jobs an economy can keep fed is
// income/drain. Above that, K buildings in parallel all land at K*T and nothing
// pays until then -- the metal is spent either way, and the only thing more
// parallel sites can buy is taking it off everything else.
const float DRAIN = 7.0f;   // metal/s one constructor pulls
const uint  MIN_INFLIGHT = 2;

uint InFlightCap()
{
	const float drain = ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN);
	if (drain <= 0.f)
		return MIN_INFLIGHT;
	const float want = aiEconomyMgr.metal.income / drain;
	if (want <= float(MIN_INFLIGHT))
		return MIN_INFLIGHT;
	return uint(want);
}

// A DUPLICATE COSTS THE WHOLE BUILDING AGAIN. InFlightCap answers how many
// requests the INCOME can feed across a def -- it knows nothing about what one
// of them costs, so the same income licensed several parallel advanced solars
// and duplicate T3 defence on an empty bank (apexearth 2026-08-21: "We are
// still making duplicate buildings at the same time when we are not wealthy
// enough to do so"; earlier, on Pulsars: "Do we want 1 T3 defense in 1/3rd the
// time, or 3 T3 defense in 3/3rds that time..?"). The extra site is allowed
// only while the BANK already holds the duplicate's cost -- banked metal is
// the one honest signal of "wealthy enough to pay twice at once". The first
// site is never blocked; this only serializes duplicates.
uint EffectiveCap(const CCircuitDef@ want)
{
	// ADVANCED SOLARS ARE STRICTLY SERIAL, whatever the bank. apexearth
	// 2026-08-21: "A new advanced solar order should not be wanted while we
	// already have one being fulfilled." The pack rule keeps them adjacent;
	// the ORDER is one at a time -- a second asker folds onto the live one
	// through JoinFor and helps finish it instead of opening another.
	if (ai.GetTunable("apex_advsol_serial", TUNE_ADVSOL_SERIAL) > 0.f) {
		const string n = want.GetName();
		if ((n == "armadvsol") || (n == "coradvsol") || (n == "legadvsol"))
			return 1;
	}
	uint cap = InFlightCap();
	const float per = want.costM * ai.GetTunable("apex_dup_bank", TUNE_DUP_BANK);
	if (per > 0.f) {
		const uint wealth = 1 + uint(aiEconomyMgr.metal.current / per);
		if (wealth < cap)
			cap = wealth;
	}
	// SERIAL UNTIL SATURATED (apexearth 2026-08-30: four cons on four fusions
	// is power in four minutes; the same four on ONE fusion is power in one --
	// "there's no reason we should ever make two identical, really expensive
	// things right next to each other at the same time"). The metal is spent
	// either way; parallel only moves the first completion LATER. So wealth
	// licenses a duplicate only once every manned site of this def already
	// holds its full crew -- hands that could still join must join first.
	// Cheap defs saturate at two or three hands, so converters and nanos still
	// parallelize freely; "really expensive" falls out of the crew arithmetic.
	if (!SitesSaturated(want)) {
		const uint have = InFlight(want);
		if (have < cap)
			cap = (have > 0) ? have : 1;
	}
	return cap;
}

// Every manned live site of this def carries its full crew. An unmanned
// proposal does not block (it is claimable, not a working site).
bool SitesSaturated(const CCircuitDef@ want)
{
	const uint cap = SiteWorkerCap(want);
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		const CCircuitDef@ has = t.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const uint busy = Workers(t);
		if ((busy > 0) && (busy < cap))
			return false;
	}
	return true;
}

// HOW MANY WORKERS ONE SITE IS WORTH, from the building's own cost. Piling the
// whole pool onto one site was the old bound (InFlightCap, an ECONOMY-wide
// number), which serialized every def to one site until it saturated -- a rich
// economy that wants several converters or nanos AT ONCE could never open a
// second site. Each worker adds ~DRAIN metal/s of lathe, so cost/per is the
// point past which another pair of hands shortens the build less than opening
// the next site would; parallel site count stays bounded by InFlightCap, i.e.
// by income. apexearth: "we should be willing to make more than 1 of any
// building at one time if we are wealthy enough."
// The cost-derived arm on its own: how many hands the SITE is worth before
// another pair shortens the build less than opening the next site would.
// OVERFLOW FEEDS HANDS (apexearth 2026-08-28: "If we're overflowing
// metal our *want* ... should increase even more, we should be willing
// to create a whole bunch of them at the same time ... I have a hunch
// that we only think about making more buildings every ~N seconds, and
// often just 1 or 2 at a time"). His hunch was the CREW: cost/300 caps
// an advanced solar at ~2 hands, so "3 cons on one build" was
// arithmetically impossible -- joins refused as full, the parallel
// opener the only outlet, and metal rotting anyway. Wasted metal is
// exactly the feed for more hands: every DRAIN of overflow funds one
// more worker on any site.
uint CostCrew(const CCircuitDef@ want)
{
	const float per = ai.GetTunable("apex_site_cost_per_worker", TUNE_SITE_COST_PER_WORKER);
	uint n = (per > 0.f) ? uint(1.f + want.costM / per) : MIN_INFLIGHT;
	n += uint(Market::OverflowM()
			/ ((ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN) > 1.f)
				? ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN) : 7.f));
	return (n < MIN_INFLIGHT) ? MIN_INFLIGHT : n;
}

// THE BANK PREPAYS THE JOB. The two clamps below ration hands by what the
// INCOME can keep fed -- but a site whose whole bill is already banked draws
// nothing from income, and every hand it is denied is metal left rotting
// while the building arrives later (apexearth: "putting all that total build
// power onto one fusion would make it build that much faster"). With the
// bill covered, only the cost-derived crew bounds the site.
bool BankCovers(const CCircuitDef@ want)
{
	return (want !is null) && (aiEconomyMgr.metal.current >= want.costM);
}

uint SiteWorkerCap(const CCircuitDef@ want)
{
	if (want is null)
		return MIN_INFLIGHT;
	uint n = CostCrew(want);
	if (BankCovers(want))
		return n;
	const uint pool = InFlightCap();
	if (n > pool)
		n = pool;
	const uint fed = FeedableCrew(want);
	return (n > fed) ? fed : n;
}

// -- the register ------------------------------------------------------------

array<IUnitTask@> gLive;

// HOW MANY HANDS ONE SITE CAN ACTUALLY BE FED. A lathe pulls a roughly constant
// DRAIN whatever it is building, so the hands an economy can keep working at
// once is income/DRAIN -- that is InFlightCap. Split across the sites actually
// standing, it is the crew past which another pair of hands adds no progress
// here and only absence somewhere else. Cost decides how LONG a site drains,
// never how many may drain it at once; keying crew size on cost is what let a
// ~10k afus authorise 22 workers while defences and open spots went unbuilt.
// Scales with income and with how much else is in flight -- no flat number.
uint LiveSiteCount()
{
	uint n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		++n;
	}
	return (n > 0) ? n : 1;
}

// Income buildings keep a bigger crew: they finish fast on purpose and pay for
// everything downstream (apexearth, after the first peeled game: "we a little
// bit do not focus enough on eco now"). The multiplier is the eco-vs-rest
// balance knob, now applied to a rate rather than to a cost.
bool IsEcoDef(const CCircuitDef@ want)
{
	if (want is null)
		return false;
	const int d = int(want.id);
	return (Catalog::gMakeE[d] > 1.f) || (Catalog::gExtractsM[d] > 0.f)
			|| (Catalog::gConvCapacity[d] > 0.f);
}

uint FeedableCrew(const CCircuitDef@ want)
{
	// Same exemption as SiteWorkerCap, and the same number: a banked job's
	// crew is bounded by cost, so the peel rung cannot trim what the join
	// rung admitted (peeling against a different number only cycles them).
	if (BankCovers(want))
		return CostCrew(want);
	float n = float(InFlightCap()) / float(LiveSiteCount());
	if (IsEcoDef(want))
		n *= ai.GetTunable("apex_peel_eco_keep", TUNE_PEEL_ECO_KEEP);
	return (n < 1.f) ? 1 : uint(n);
}

// LATHE IS CREW (apexearth: "avoid having cons assist making nanos which are
// near other nanos which can already assist it. This should help us get more
// individual builders creating more nanos"). A standing nano finishes any
// frame its reach covers -- the patrol auto-assist plus the C++ repair
// fallback -- but only a mobile constructor can FOUND the next frame, so a
// join here spends the one thing the cluster cannot supply and parks the
// builder out of the auction for the whole build. Refused when the lathe
// already on the site clears the remaining bill within the joiner's walk
// plus apex_nano_fed_s; a fusion's long middle still takes hands, only the
// covered tail sheds them. Founders are exempt: a site with no workers has
// nobody to raise or guard the frame, whatever lathe stands nearby.
bool NanoFed(IUnitTask@ cand, uint busy, float dist, float speed)
{
	if ((cand is null) || (busy == 0) || (cand.target is null))
		return false;
	const float fedS = ai.GetTunable("apex_nano_fed_s", TUNE_NANO_FED_S);
	if (fedS <= 0.f)
		return false;
	const AIFloat3 where = cand.GetBuildPos();
	if (!OnMap(where))
		return false;
	float lathe = Market::NanoLatheReaching(where);
	if (lathe <= 0.f)
		return false;
	// One nano works one frame at a time: share the lathe across the frames
	// standing in the same cluster, or five frames would each claim the same
	// two turrets.
	uint frames = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.target is null))
			continue;
		const AIFloat3 tp = t.GetBuildPos();
		if (OnMap(tp) && (where.distance2D(tp) < 400.f))
			++frames;
	}
	if (frames > 1)
		lathe /= float(frames);
	const float costM = (cand.buildDef !is null) ? cand.buildDef.costM : 0.f;
	const float remainM = costM * (1.f - Progress(cand));
	const float v = (speed > 1.f) ? speed : ASSUMED_CON_SPEED;
	return remainM / lathe <= dist / v + fedS;
}

int gDupLog = 0;
int gCreated = 0;
int gJoined = 0;
int gCovered = 0;    // refused: this ground is already requested
int gFull = 0;       // refused: the income cannot feed another of this def

// PER-DEF, NOT GLOBAL. A single shared cooldown meant a burst on one def (say
// six armadvsol requested close together) could be silenced by an unrelated
// def's log resetting the same timer moments earlier -- exactly the failure
// mode apexearth asked to diagnose (multiple advanced solars appearing to
// build at once with nothing in the log explaining why). Sized and indexed
// like gNextFactoryRequest in sitesafety.as.
array<int> gNextDefLog(ai.GetDefCount() + 1);

// IUnitTask is refcounted, so a held handle stays valid, and every removal
// funnels through DequeueTask -> AiTaskRemoved.
void Register(IUnitTask@ task)
{
	if (task is null)
		return;
	const int bt = task.GetBuildType();
	if (!Governed(bt))
		return;
	if (task.buildDef is null)
		return;
	gLive.insertLast(task);
}

// Live FACTORY tasks by the synchronous registry -- unlike the builder
// manager's pool count (assignment empties it) or def counts (need a
// nanoframe), this covers a task through its whole walk-and-build window,
// whoever holds it and whoever created it (AiTaskAdded registers engine-made
// tasks too). The plant-ask sweep keys on this so a factory ask can never
// expire while its task is still alive in the commander's hands.
// MANNED only, on purpose: CEconomyManager also keeps a HELD, INACTIVE
// factory task while it waits for income (BuilderManager.cpp:734-740 keeps
// it out of buildTasks for exactly this reason), and AiTaskAdded registers
// that one too. Counting it read "a factory is in flight" from frame ~500 of
// every game, the ask never expired, and no factory was EVER approved --
// facCount=0 at 10 minutes, 2 of 3 smokes. A worker on the task is what
// separates the commander's real walk-and-build from the engine's parked
// placeholder; the unassigned-active ones are the pool count's job.
uint FactoryManned()
{
	uint n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].GetBuildType() == Task::BuildType::FACTORY)
			&& (Workers(gLive[i]) > 0))
			++n;
	}
	return n;
}

void Forget(IUnitTask@ task)
{
	for (uint i = 0; i < gLive.length(); ++i) {
		if (gLive[i] is task) {
			gLive.removeAt(i);
			return;
		}
	}
}

uint Workers(IUnitTask@ t)
{
	if (t is null)
		return 0;
	array<CCircuitUnit@>@ busy = t.GetUnits();
	return (busy is null) ? 0 : busy.length();
}

// HOW CLOSE TO DONE. `target` is the nanoframe (IBuilderTask::SetTarget,
// null until it exists) and a unit under construction reports its build
// percentage through health percent -- 0 for nothing yet, 1 for finished.
// apexearth: "if we are in progress on more than one, we reassign ourselves
// to focus on the one that is more close to being complete... focus as much
// build power as we can on just the one building". This is the signal that
// lets JoinFor/ClaimFor/Redirect do that instead of picking on distance
// alone -- a half-built nanoframe should win over a fresh one within reach.
float Progress(IUnitTask@ t)
{
	if (t is null)
		return 0.f;
	CCircuitUnit@ nano = t.target;
	return (nano is null) ? 0.f : nano.GetHealthPercent();
}

// -- buildings of ours already standing half-finished -------------------------
//
// A NANOFRAME OUTLIVES ITS REQUEST. IBuilderTask::OnUnitDestroyed aborts on
// `(target == nullptr) || units.empty()`, so losing the one builder mid-build
// removes the task while the frame stays up; nothing else remembers it, because
// the census credits a structure at AiUnitFinished. Between the two the market
// reads "none standing, none coming", sites another, and a nano turret in range
// quietly finishes the first -- two anti-nukes for one decision.
//
// Ids, not handles: every entry is re-read through ai.GetTeamUnit, so a frame
// that dies between events cannot leave a dangling pointer behind.
// The orphan register LIVES IN THE COMMITMENT LEDGER now (a frame whose
// request died is a FRAMED row with no task -- Market::ComIsOrphan). These
// keep the Requests:: API surface; PendNote keeps only the frame-orphan log
// line the audit reads.
void PendNote(IUnitTask@ task)
{
	if (task is null)
		return;
	CCircuitUnit@ frame = task.target;
	if ((frame is null) || (frame.circuitDef is null))
		return;
	if (frame.circuitDef.IsMobile())
		return;
	const AIFloat3 at = frame.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: frame-orphan " + frame.circuitDef.GetName()
		+ " at=" + int(at.x) + "," + int(at.z)
		+ " done=" + formatFloat(frame.GetHealthPercent(), "", 0, 2));
}

// How many of this def stand unfinished with no request of their own.
uint PendCount(const CCircuitDef@ want)
{
	if (want is null)
		return 0;
	return Market::ComOrphanCount(int(want.id));
}

// The abandoned frame of this def nearest `spot`, within `reach`.
CCircuitUnit@ PendNear(const CCircuitDef@ want, const AIFloat3& in spot, float reach)
{
	if ((want is null) || !OnMap(spot))
		return null;
	return Market::ComOrphanUnit(int(want.id), spot, reach);
}

// ...and the same frame WHEREVER it stands. PendNear answers "is one already
// here", which is the right question when the market has picked a site; it is
// the wrong one when the market has picked a DIFFERENT site, because the
// abandoned frame is then never near anything and is orphaned for good
// (apexearth: "when we e-stall we think to do something else... instead of
// choosing to finish the original lab afterwards we just start making a new
// one"). Nearest to `from` so a fleet of frames is worked in a sane order.
CCircuitUnit@ PendAnyOfDef(const CCircuitDef@ want, const AIFloat3& in from)
{
	if (want is null)
		return null;
	return Market::ComOrphanUnit(int(want.id), from, -1.f);
}

// The same job, for matching purposes. Same def always; and one reactor rung
// counts as another, because HomeEnergy re-ranks fusion against advanced fusion
// every call and each rung was otherwise blind to the other rung's work. Only a
// request somebody is ALREADY on may match across defs: assisting a live
// nanoframe needs no build option, starting one does, and a commander that can
// build armfus cannot build armafus.
bool SameJob(const CCircuitDef@ has, const CCircuitDef@ want, uint busy)
{
	if ((has is null) || (want is null))
		return false;
	if (has.id == want.id)
		return true;
	if (busy == 0)
		return false;
	if (Builder::IsFusion(has) && Builder::IsFusion(want))
		return true;
	// AN ENERGY JOB IS AN ENERGY JOB once hands are on it (apexearth
	// 2026-08-28: T1 cons "go make an advanced solar instead of going to
	// help the T2 fusion being made. Our join logic seems to only care
	// about assisting our own tier"). A T1 con's energy want is the advsol
	// it can place; the standing fusion is the better home for those hands.
	// One direction only -- the standing job must be at least as big as the
	// want it absorbs, or a T2 con's fusion want would downgrade into
	// assisting someone's solar.
	return (has.costM >= want.costM)
		&& (aiEconomyMgr.GetEnergyMake(has) > 1.f)
		&& (aiEconomyMgr.GetEnergyMake(want) > 1.f);
}

// -- the one question a caller asks ------------------------------------------
//
// "Here is what I want built and roughly where. Give me the task to work --
// whether that is one that already exists or a fresh one -- or tell me to back
// off." No caller does its own distance or collision arithmetic; that split
// between SpotCollides and JoinTaskFor is what let a duplicate slip between
// them.
//
// `radius` 0 means the exact point in `spot`. `radius` > 0 means "anywhere in
// this circle would do", which is what defence and AA placement actually want.
//
// `unit` may be null: a manager-side caller placing an order for whoever the
// engine elects gets the same duplicate protection, and simply has nobody to
// assign.
//
// Returns null when the answer is "not now" -- either this ground is already
// requested, or the economy cannot feed another of these.
IUnitTask@ Take(CCircuitUnit@ unit, CCircuitDef@ want, Task::BuildType bt,
		Task::Priority prio, const AIFloat3& in spot, float radius, float shake)
{
	bool created = false;
	return Take(unit, want, bt, prio, spot, radius, shake, created);
}

// DEAD HANDLES ARE DROPPED, NOT SERVED. AiTaskRemoved -> Forget is the normal
// exit, but any removal that misses it leaves a dead task in gLive -- and a
// dead task returned from here is refused by AssignTask (it has no owner
// queue), so the asking constructor idles forever on the same stale handle.
// Observed live: advanced cons idle at full metal while EcoFusion's request
// kept resolving to a dead cover task.
void SweepDead()
{
	for (uint i = 0; i < gLive.length(); ) {
		if ((gLive[i] is null) || gLive[i].IsDead())
			gLive.removeAt(i);
		else
			++i;
	}
}

// Does this def shoot things on the ground? Read from the catalog, which is
// empty until Catalog::Resolve runs, so the length is checked rather than
// assumed -- an out-of-range index here is a script exception that would take
// the whole variant down.
bool ShootsGround(CCircuitDef@ d)
{
	const int id = int(d.id);
	if ((id < 0) || (uint(id) >= Catalog::gSurfT.length()))
		return true;
	return Catalog::gSurfT[id] > 0.01f;
}

// `parallel` is a caller's explicit "open ANOTHER site": it skips the fold onto
// a nearby same-def request (JoinFor), which otherwise collapses a deliberate
// burst of distinct sites into one -- the nano burst measured burst=1 forever.
// The income-derived InFlight cap and the same-ground CoverFor test still hold.
IUnitTask@ Take(CCircuitUnit@ unit, CCircuitDef@ want, Task::BuildType bt,
		Task::Priority prio, const AIFloat3& in spot, float radius, float shake,
		bool &out created, bool parallel = false)
{
	created = false;
	if ((want is null) || !OnMap(spot))
		return null;
	SweepDead();
	// THE one chokepoint every request rule passes through: an asker that
	// cannot build the def gets null BEFORE any task is enqueued, so the rule
	// falls through to its next option instead of leaving an orphan task and a
	// wasted election. GuardBuildCapability still backstops the pipeline's
	// return, but by then Take had already enqueued -- measured (8v8 Glitters
	// 20260815-065302): 975 armck->armfus, 777 ->armmoho, 594 comm->advsol per
	// game, all guard-nulled after the orphan already existed.
	if ((unit !is null) && !unit.circuitDef.CanBuild(want))
		return null;
	// A def dying fast on repeat is held HERE, the door every lane walks
	// through -- the plant lane checked AbortBackoff and the convert lane did
	// not, so an eco commander re-elected the same doomed converter on the
	// same occupied square 156 times in one game (t7, si8-fix2-15m-s104)
	// while its energy gate sat unbuilt. See Builder::AbortBackoff.
	if (Builder::AbortBackoff(int(want.id)))
		return null;

	// A FACTORY IS NEVER A FORK -- enforced at THE chokepoint, because the
	// per-path guards kept losing: PlantApproved covers every rule that asks
	// permission, but the commander's join branch infers permission from the
	// task pool and takes this door directly -- and JoinFor's REACH and
	// WorthJoining bounds made a distant asker MISS the standing request and
	// open a second plant beside the first (the recurring two-T1-labs
	// report). Any live factory request IS the answer, whatever the distance
	// and whatever def the asker brought; and a new T1 land plant while one
	// already stands under the T1 cap is refused outright, so no entrance --
	// present or future -- can duplicate the line again.
	if (bt == Task::BuildType::FACTORY) {
		for (uint i = 0; i < gLive.length(); ++i) {
			IUnitTask@ cand = gLive[i];
			if ((cand is null) || cand.IsDead()
				|| (cand.GetBuildType() != Task::BuildType::FACTORY))
				continue;
			// SAME DEF only: a T2 lab ask during a T1 rebuild is tech, not a
			// fork -- the blanket fold made a T1 request absorb every T2
			// decision (watched, 8v8: overflowing, no T2 lab).
			if ((want !is null) && (cand.buildDef !is null)
				&& (cand.buildDef !is want))
				continue;
			// Manned only -- the engine's held placeholder task (see
			// FactoryManned) also lives in this registry, and handing IT
			// back wedged every asker on an unassignable task.
			if (Workers(cand) == 0)
				continue;
			if ((unit !is null) && (cand.buildDef !is null)
				&& !unit.circuitDef.CanBuild(cand.buildDef))
				continue;
			return cand;
		}
	}

	const AIFloat3 at = spot;

	const int type = int(bt);
	// Extractor work is never a duplicate: two spots are two different things
	// wanted for their own sake (see Governed above).
	const bool spotWork = (type == int(Task::BuildType::MEX))
			|| (type == int(Task::BuildType::MEXUP));
	// WHY A SECOND TASK FOR A DEF THAT ALREADY HAS ONE. ~500 tasks were created
	// for one advanced lab while only 1-2 were ever live, and each new one
	// re-targets the builder mid-walk -- which is why it oscillates instead of
	// arriving. Log the state dedup saw when it let another through.
	if (gDupLog < 25) {
		const uint already = InFlight(want);
		if (already > 0) {
			++gDupLog;
			uint manned = 0;
			for (uint z = 0; z < gLive.length(); ++z) {
				if ((gLive[z] !is null) && !gLive[z].IsDead()
					&& (gLive[z].buildDef !is null) && (gLive[z].buildDef is want)
					&& (Workers(gLive[z]) > 0))
					++manned;
			}
			AiLog("apex: dup t=" + ai.teamId + " " + want.GetName()
				+ " bt=" + type + " live=" + already + " manned=" + manned
				+ " governed=" + (Governed(type) ? 1 : 0));
		}
	}
	if (!Governed(type)) {
		IUnitTask@ any = Create(want, bt, prio, at, shake);
		created = (any !is null);
		return any;
	}

	// This ground is already requested. Help with it if there is room and it is
	// worth walking to; otherwise back off. Never a second building here.
	IUnitTask@ cover = CoverFor(want, at, radius);
	if (cover !is null) {
		// An unmanned request here is an ORPHAN, not cover: hand it to the
		// asker whatever it costs. JOIN_MIN_COST bounds walking to HELP a
		// manned site; below it this branch refused everything, so a cheap
		// tower whose builder was pulled away blocked its own ground forever
		// -- re-asked and refused as "covered" every election, never built.
		if (Workers(cover) == 0) {
			++gJoined;
			Log(want, "adopt-orphan");
			return cover;
		}
		if (NanoFed(cover, Workers(cover),
			(unit !is null)
				? unit.GetPos(ai.frame).distance2D(cover.GetBuildPos()) : 0.f,
			(unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f))
		{
			++gCovered;
			Log(want, "nano-fed");
			return null;
		}
		if ((want.costM >= JOIN_MIN_COST) && (Workers(cover) < SiteWorkerCap(want))) {
			++gJoined;
			Log(want, "join-site");
			return cover;
		}
		++gCovered;
		Log(want, "covered");
		return null;
	}
	// A FRAME OF OURS IS ALREADY UP HERE -- FINISH IT, NEVER START A SECOND.
	// The metal in it is spent, and the alternative is what turns into two of
	// the same building: nothing is working the frame, so a passing nano turret
	// completes it while this decision raises another somewhere else. Guard,
	// not a fresh build task -- a build order needs a free square and the frame
	// is standing on the only one that matters. Not extractor work: two spots
	// are two different things wanted for their own sake, which is the same
	// reason mex and mexup are exempt from the dedup above.
	if (!spotWork) {
		const float pendReach = Positional(type)
				? ((radius > 0.f) ? radius : SAME_SITE) : REACH;
		CCircuitUnit@ frame = PendNear(want, at, pendReach);
		if ((frame !is null) && (unit !is null)
			&& (Builder::ThreatFor(unit, frame.GetPos(ai.frame))
				> Builder::CON_THREAT_VETO))
			@frame = null;   // abandoned because the ground is hot; still is
		if (frame !is null) {
			if (unit is null) {
				++gCovered;
				Log(want, "frame-standing");
				return null;
			}
			// Committed for as long as the frame has left to run at one pair
			// of hands, so the guard does not outlive the job it was taken
			// for; if it is still up after that the market re-decides and
			// lands back here.
			// Clamped: GetHealthPercent subtracts capture progress and reads
			// negative on a fresh frame, which would price the hold above the
			// building's whole cost.
			float done = frame.GetHealthPercent();
			if (done < 0.f)
				done = 0.f;
			else if (done > 1.f)
				done = 1.f;
			const float left = want.costM * (1.f - done);
			const int hold = int(left / DRAIN) + 10;
			IUnitTask@ res = aiBuilderMgr.Enqueue(
					TaskB::Guard(prio, frame, false, hold * SECOND));
			if (res !is null) {
				++gJoined;
				Log(want, "resume-frame");
				return res;
			}
		}
	}

	if (!Positional(type)) {
		// Somewhere else in reach, one of these is already going up.
		// Serializing onto it is the point for an unsaturated site: the metal
		// starts flowing sooner. POOL FIRST EVEN WHEN RICH (apexearth,
		// watching: "we have 3 separate T1 cons all starting an advanced
		// solar at the same time. They should each work on 1 together.
		// They'll see rewards faster and that'll compound") -- `parallel`
		// used to skip this fold entirely, which is how a filling bank
		// opened three solo advsol sites in two minutes. JoinFor's crew cap
		// already answers "full": a saturated site returns null here and
		// falls through to the parallel Create below, which is the one case
		// parallel was ever for.
		{
			IUnitTask@ near = JoinFor(unit, want, at);
			if (near !is null) {
				++gJoined;
				Log(want, "join-near");
				return near;
			}
		}
		if (!parallel && InFlight(want) >= EffectiveCap(want)) {
			// FULL MEANS TAKE ONE OFF THE QUEUE, NOT STAND STILL. A request
			// nobody is working is available by definition -- that is the whole
			// of "if the building is cancelled by whoever took the order then it
			// goes back to being available for someone else to handle". Handing
			// one out here is also what stops a couple of unworkable proposals
			// wedging a def shut until they time out.
			IUnitTask@ idle = ClaimFor(want, spot);
			if (idle !is null) {
				++gJoined;
				Log(want, "claim");
				return idle;
			}
			++gFull;
			Log(want, "full");
			return null;
		}
	}
	IUnitTask@ post = Create(want, bt, prio, spot, shake);
	created = (post !is null);
	return post;
}

// Would a fresh request for this def here be allowed? For the two callers that
// must build their own task shape (TaskB::Factory carries a reprDef Take cannot
// know), so they ask the same question and then enqueue themselves.
bool Allowed(CCircuitDef@ want, Task::BuildType bt, const AIFloat3& in spot,
		float radius)
{
	if ((want is null) || !OnMap(spot))
		return false;
	if (!Governed(int(bt)))
		return true;
	if (CoverFor(want, spot, radius) !is null)
		return false;
	if (Positional(int(bt)))
		return true;
	if (JoinFor(null, want, spot) !is null)
		return false;
	return InFlight(want) < EffectiveCap(want);
}

// The live request covering this ground, if there is one. `radius` 0 is an
// exact point (SAME_SITE around it); `radius` > 0 is the caller's own circle,
// anywhere in which counts as the same job.
IUnitTask@ CoverFor(CCircuitDef@ want, const AIFloat3& in spot, float radius)
{
	const float reach = (radius > 0.f) ? radius : SAME_SITE;
	const float sqReach = reach * reach;
	IUnitTask@ best = null;
	float bestDist = 0.f;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const uint busy = Workers(cand);
		if (!SameJob(cand.buildDef, want, busy))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where) || (spot.SqDistance2D(where) >= sqReach))
			continue;
		const float d = spot.distance2D(where);
		if ((best is null) || (d < bestDist)) {
			@best = cand;
			bestDist = d;
		}
	}
	return best;
}

// The best request of this def worth JOINING from `spot`, anywhere in reach and
// under its worker cap. Distance is measured from the SITE, not from the
// builder: five idle constructors scattered around one base each found nothing
// within reach of THEMSELVES and each then computed its own spot, landing the
// five spots within ~200 elmos of each other. Duplicate-ness is a property of
// the site, not of which builder happened to notice it.
// A SECOND PAIR OF HANDS ON THE SAME METAL SITE. Mex and mex-upgrade wants are
// enqueued straight onto the builder manager and never pass through Take, so
// they never reach JoinFor either -- there was no path by which a second
// constructor could help one, whatever the crew rung would have allowed. This
// is that path: same def, same ground, room under the site's crew.
//
// JOIN_MIN_COST still applies, so a ~50 metal T1 extractor is not worth a walk
// to assist -- for those the second asker takes ANOTHER SPOT, which is the
// same answer arrived at by not joining.
IUnitTask@ JoinSpot(CCircuitUnit@ unit, CCircuitDef@ want, const AIFloat3& in spot)
{
	if ((want is null) || (want.costM < JOIN_MIN_COST) || !OnMap(spot))
		return null;
	const uint cap = SiteWorkerCap(want);
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if ((cand is null) || cand.IsDead() || (cand.buildDef !is want))
			continue;
		if (Workers(cand) >= cap)
			continue;
		if (NanoFed(cand, Workers(cand), 0.f, 0.f))
			continue;
		if ((unit !is null) && !unit.circuitDef.CanBuild(want))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where) || (spot.distance2D(where) > SAME_SITE))
			continue;
		return cand;
	}
	return null;
}

IUnitTask@ JoinFor(CCircuitUnit@ unit, CCircuitDef@ want, const AIFloat3& in spot)
{
	if (want.costM < JOIN_MIN_COST)
		return null;
	// Per-site saturation, not the economy-wide pool: see SiteWorkerCap.
	const uint cap = SiteWorkerCap(want);
	IUnitTask@ best = null;
	float bestProgress = -1.f;
	float bestDist = REACH;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const uint busy = Workers(cand);
		// The site's crew cap belongs to the def actually being BUILT there:
		// pricing a fusion's crew off the advsol want that walked in read a
		// 2-hand cap against a job that feeds many more.
		const uint candCap = ((cand.buildDef is null) || (cand.buildDef is want))
				? cap : SiteWorkerCap(cand.buildDef);
		if ((busy >= candCap) || !SameJob(cand.buildDef, want, busy))
			continue;
		if ((unit !is null) && (cand.buildDef !is null)
			&& !unit.circuitDef.CanBuild(cand.buildDef)
			&& (cand.target is null))
			continue;   // cannot place the def and no frame stands yet; a
			            // standing nanoframe takes ANY hands (repair) -- the
			            // law SameJob already states for the commander's
			            // fusion rungs, now honored here too
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = spot.distance2D(where);
		// A BUILD THAT TRANSFORMS THE ECONOMY IS WORTH A LONGER WALK
		// (apexearth: "detect that this building will double our energy
		// output and thus be very much worth joining"). Impact is the def's
		// own yield against the matching CURRENT income, so a reactor equal
		// to the standing grid doubles this site's join reach and a solar
		// moves it nothing; capped so one late-game monolith cannot recruit
		// the whole map. WorthJoining's travel-vs-remaining test keeps the
		// final say.
		float reach = REACH;
		if (cand.buildDef !is null) {
			const float eMake = aiEconomyMgr.GetEnergyMake(cand.buildDef);
			const float mMake = aiEconomyMgr.GetMetalMake(cand.buildDef);
			float impact = 0.f;
			if (eMake > 0.f) {
				const float eInc = aiEconomyMgr.energy.income;
				impact = eMake / ((eInc < 1.f) ? 1.f : eInc);
			} else if (mMake > 0.f) {
				const float mInc = aiEconomyMgr.metal.income;
				impact = mMake / ((mInc < 1.f) ? 1.f : mInc);
			}
			if (impact > 3.f)
				impact = 3.f;
			reach *= 1.f + impact;
		}
		if (dist >= reach)
			continue;
		if ((unit !is null) && (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO))
			continue;
		if (NanoFed(cand, busy, dist,
			(unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f))
			continue;
		const float progress = Progress(cand);
		// Remaining work is the CANDIDATE's bill, not the want's: pricing a
		// fusion's join by the 320m advsol that walked in read minutes of
		// remaining lathe as not worth a forty-second walk.
		if (!WorthJoining(dist, progress,
				(cand.buildDef !is null) ? cand.buildDef.costM : want.costM,
				busy,
				(unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f)) {
			++gTooFar;
			continue;
		}
		// PROGRESS FIRST, DISTANCE ONLY BREAKS A TIE. A half-built nanoframe
		// always outranks a fresh one within reach -- concentrating build
		// power on whichever is closer to done, rather than spreading it
		// thin across several that each individually take longer to finish
		// and so sit exposed to the idle/order-drop abort path longer.
		if ((progress < bestProgress) || ((progress == bestProgress) && (dist >= bestDist)))
			continue;
		@best = cand;
		bestProgress = progress;
		bestDist = dist;
	}
	if ((best !is null) && (unit !is null) && (best.buildDef !is null)
		&& !unit.circuitDef.CanBuild(best.buildDef))
	{
		AiLog("apex: join assist t=" + ai.teamId + " "
			+ unit.circuitDef.GetName() + " #" + unit.id
			+ " -> " + best.buildDef.GetName()
			+ " (cross-tier: wanted " + want.GetName() + ")");
	}
	return best;
}

// The request for this def that NOBODY is working, ranked by progress first
// (a nanoframe abandoned mid-build -- its worker died, got vetoed off, or
// hit the idle/order-drop retry ceiling -- is exactly the case to finish
// before starting anything fresh) and distance second. No cost floor: this
// is not "come and help", it is "this order is unowned, take it" -- so the
// walk is the walk the builder would have made to its own site anyway.
IUnitTask@ ClaimFor(CCircuitDef@ want, const AIFloat3& in spot)
{
	IUnitTask@ best = null;
	float bestProgress = -1.f;
	float bestDist = REACH;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		if (Workers(cand) > 0)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = spot.distance2D(where);
		if (dist >= REACH)
			continue;
		const float progress = Progress(cand);
		if ((progress < bestProgress) || ((progress == bestProgress) && (dist >= bestDist)))
			continue;
		@best = cand;
		bestProgress = progress;
		bestDist = dist;
	}
	return best;
}

// How many requests for this exact def are live, in any state.
uint InFlight(const CCircuitDef@ want)
{
	if (want is null)
		return 0;
	uint n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has !is null) && (has.id == want.id))
			++n;
	}
	return n;
}

// SURPLUS ASSISTERS ARE PEELED, NOT WAITED OUT. The engine only re-elects a
// builder while it is AWAY from its build position (IBuilderTask::Reevaluate),
// so a con parked at a big site assists until completion however many wants
// starve -- apexearth, watching an afus: "~30+ cons all focus... soon as it
// was done we spread out to make ~7 or 8 needed advanced converters. The
// issue is elections just don't happen often enough." Every slow update this
// detaches workers beyond the site's ETA-derived count (RemoveUnit hands
// them to the idle task, which is a fresh election next frame). Only sites
// with a standing nanoframe: walkers already re-elect on their own.
int gPeeled = 0;
int gNextPeelLog = 0;
void PeelSurplus()
{
	if (ai.GetTunable("apex_assist_release", TUNE_ASSIST_RELEASE) <= 0.f)
		return;
	int peeledNow = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		if ((t.buildDef is null) || (t.target is null))
			continue;
		array<CCircuitUnit@>@ crew = t.GetUnits();
		if (crew is null)
			continue;
		// The same feed-derived crew the join rung authorises, so a peeled
		// worker cannot walk straight back on: peeling against one number
		// while SiteWorkerCap admitted against another only cycled them.
		const int wantN = int(FeedableCrew(t.buildDef));
		int surplus = int(crew.length()) - wantN;
		// A few at a time, largest ids first -- the same stampede guard the
		// hold rung uses: everyone reads the same pre-order counts.
		const int PEEL_PER_TICK = 3;
		for (int k = 0; (k < surplus) && (k < PEEL_PER_TICK); ++k) {
			CCircuitUnit@ top = null;
			for (uint c = 0; c < crew.length(); ++c) {
				CCircuitUnit@ u2 = crew[c];
				if (u2 is null)
					continue;
				if ((top is null) || (int(u2.id) > int(top.id)))
					@top = u2;
			}
			if (top is null)
				break;
			t.RemoveUnit(top);
			++gPeeled;
			++peeledNow;
			@crew = t.GetUnits();
			if (crew is null)
				break;
		}
	}
	if ((peeledNow > 0) && (ai.frame >= gNextPeelLog)) {
		gNextPeelLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: peeled " + peeledNow
			+ " surplus assister(s) back to the auction (total " + gPeeled + ")");
	}
}

// The def of a live FACTORY request, if any -- so a joiner helps build what
// was actually ASKED. Joining with the joiner's own preferred def is not a
// join: Take() finds no task for that def and creates a second plant.
CCircuitDef@ LiveFactoryDef()
{
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if ((cand is null) || (cand.GetType() != Task::Type::BUILDER))
			continue;
		if (cand.GetBuildType() != Task::BuildType::FACTORY)
			continue;
		const CCircuitDef@ bd = cand.buildDef;
		if (bd is null)
			continue;
		CCircuitDef@ has = ai.GetCircuitDef(bd.id);
		if (has !is null)
			return has;
	}
	return null;
}

IUnitTask@ Create(CCircuitDef@ want, Task::BuildType bt, Task::Priority prio,
		const AIFloat3& in spot, float shake)
{
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(bt, prio, want, spot, shake));
	if (post !is null) {
		++gCreated;
		Log(want, "new");
	}
	return post;
}

void Log(CCircuitDef@ want, const string& in what)
{
	const int id = want.id;
	const bool tracked = (id >= 0) && (uint(id) < gNextDefLog.length());
	if (tracked && (ai.frame < gNextDefLog[id]))
		return;
	if (tracked)
		gNextDefLog[id] = ai.frame + 10 * SECOND;
	// inFlight/cap answer the actual question a burst of one def raises: was
	// this "new" allowed because the economy could genuinely feed another one
	// in parallel, or did it slip past a cap that should have refused it.
	AiLog(Factory::T() + "apex: request " + what + " " + want.GetName()
		+ " inFlight=" + InFlight(want) + " cap=" + InFlightCap()
		+ " live=" + gLive.length()
		+ " new=" + gCreated + " join=" + gJoined
		+ " covered=" + gCovered + " full=" + gFull + " tooFar=" + gTooFar);
}

// -- screening an offer the ENGINE made --------------------------------------
//
// CBuilderManager::MakeBuilderTask picks the cheapest-to-reach candidate out of
// its queue, and the queue can legitimately hold several tasks for one def. Two
// idle constructors evaluated a few frames apart therefore take two DIFFERENT
// tasks for the same def and each walks off to its own site.
// IBuilderTask::CanAssignTo would have refused the second builder on ONE task
// once it had enough build power -- it has no opinion at all about a second
// task.
//
// Redirecting is a serialization, not a cancellation: the offered task stays in
// the queue and gets built later, by whoever is idle then. Nothing is enqueued
// and no constructor time is created.
IUnitTask@ Redirect(CCircuitUnit@ unit, bool isComm, IUnitTask@ offer)
{
	if (isComm || (unit is null) || (offer is null)
		|| (offer.GetType() != Task::Type::BUILDER))
	{
		return null;
	}
	const int type = offer.GetBuildType();
	if (!Governed(type) || Positional(type))
		return null;
	// Matching on the OFFERED def is the only proof available that this unit can
	// build the thing at all -- CCircuitDef exposes no CanBuild binding.
	CCircuitDef@ want = offer.buildDef;
	if ((want is null) || (want.costM < JOIN_MIN_COST))
		return null;
	if (Workers(offer) > 0)
		return null;   // this offer IS the one under way; taking it is the default

	const uint cap = SiteWorkerCap(want);
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestProgress = -1.f;
	float bestDist = REACH;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if ((cand is null) || (cand is offer))
			continue;
		const uint busy = Workers(cand);
		// An assignee is what makes a cross-def reactor match safe, and here it
		// is required outright: the point of this screen is to fold a second
		// task into work SOMEBODY IS ALREADY DOING.
		if ((busy == 0) || (busy >= cap))
			continue;
		if (!SameJob(cand.buildDef, want, busy))
			continue;
		// SameJob allows cross-def matches (reactor classes), so the offered
		// def proves nothing about the CANDIDATE's def -- an armck redirected
		// onto an armafus site loops through the capability guard forever
		// (measured 60k blocked elections in one long 8v8).
		if ((cand.buildDef !is null) && !unit.circuitDef.CanBuild(cand.buildDef))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= REACH)
			continue;
		if (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO)
			continue;
		if (NanoFed(cand, busy, dist,
			Catalog::gSpeed[int(unit.circuitDef.id)]))
			continue;
		const float progress = Progress(cand);
		if (!WorthJoining(dist, progress, want.costM, busy,
				(unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f)) {
			++gTooFar;
			continue;
		}
		// Same rule as JoinFor/ClaimFor: fold onto whichever is furthest
		// along, not merely nearest.
		if ((progress < bestProgress) || ((progress == bestProgress) && (dist >= bestDist)))
			continue;
		@best = cand;
		bestProgress = progress;
		bestDist = dist;
	}
	if (best is null)
		return null;
	++gJoined;
	Log(want, "redirect");
	return best;
}

}  // namespace Requests
