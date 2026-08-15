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
bool Governed(int bt)
{
	return (bt == int(Task::BuildType::FACTORY))
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

bool WorthJoining(float dist, float progress, float costM, uint busy)
{
	if (dist <= 0.f)
		return true;
	const float remainingMetal = costM * (1.f - progress);
	if (remainingMetal <= 0.f)
		return false;   // effectively done; nothing left for another builder to add
	const float buildRate = DRAIN * float((busy > 0) ? busy : 1);
	const float remainingTime = remainingMetal / buildRate;
	const float travelTime = dist / ASSUMED_CON_SPEED;
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
	const float drain = ai.GetTunable("apex_request_drain", DRAIN);
	if (drain <= 0.f)
		return MIN_INFLIGHT;
	const float want = aiEconomyMgr.metal.income / drain;
	if (want <= float(MIN_INFLIGHT))
		return MIN_INFLIGHT;
	return uint(want);
}

// -- the register ------------------------------------------------------------

array<IUnitTask@> gLive;

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
	return (busy > 0) && Builder::IsFusion(has) && Builder::IsFusion(want);
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

IUnitTask@ Take(CCircuitUnit@ unit, CCircuitDef@ want, Task::BuildType bt,
		Task::Priority prio, const AIFloat3& in spot, float radius, float shake,
		bool &out created)
{
	created = false;
	if ((want is null) || !OnMap(spot))
		return null;

	const int type = int(bt);
	if (!Governed(type)) {
		IUnitTask@ any = Create(want, bt, prio, spot, shake);
		created = (any !is null);
		return any;
	}

	// This ground is already requested. Help with it if there is room and it is
	// worth walking to; otherwise back off. Never a second building here.
	IUnitTask@ cover = CoverFor(want, spot, radius);
	if (cover !is null) {
		if ((want.costM >= JOIN_MIN_COST) && (Workers(cover) < InFlightCap())) {
			++gJoined;
			Log(want, "join-site");
			return cover;
		}
		++gCovered;
		Log(want, "covered");
		return null;
	}
	if (!Positional(type)) {
		// Somewhere else in reach, one of these is already going up.
		// Serializing onto it is the whole point: the metal starts flowing
		// sooner and no second site opens that the same builders would only
		// reach later.
		IUnitTask@ near = JoinFor(unit, want, spot);
		if (near !is null) {
			++gJoined;
			Log(want, "join-near");
			return near;
		}
		if (InFlight(want) >= InFlightCap()) {
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
	return InFlight(want) < InFlightCap();
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
IUnitTask@ JoinFor(CCircuitUnit@ unit, CCircuitDef@ want, const AIFloat3& in spot)
{
	if (want.costM < JOIN_MIN_COST)
		return null;
	const uint cap = InFlightCap();
	IUnitTask@ best = null;
	float bestProgress = -1.f;
	float bestDist = REACH;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const uint busy = Workers(cand);
		if ((busy >= cap) || !SameJob(cand.buildDef, want, busy))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = spot.distance2D(where);
		if (dist >= REACH)
			continue;
		if ((unit !is null) && (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO))
			continue;
		const float progress = Progress(cand);
		if (!WorthJoining(dist, progress, want.costM, busy)) {
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
uint InFlight(CCircuitDef@ want)
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

	const uint cap = InFlightCap();
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
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= REACH)
			continue;
		if (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO)
			continue;
		const float progress = Progress(cand);
		if (!WorthJoining(dist, progress, want.costM, busy)) {
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
