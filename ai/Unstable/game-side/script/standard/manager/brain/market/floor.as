namespace Market {
// NOBODY STANDS STILL. A constructor that ends an election holding nothing
// is build power the economy already paid for and is not spending, and the
// cheapest useful thing a lathe can always do is point it at work somebody
// else has already started -- a guard auto-assists whatever its target
// builds. Reached from BOTH idle exits of Decide: no want priced positive,
// and (the one that actually fires) every priced want refused by the
// executor.
int gNextFloorLog = 0;

// WHAT THE ARBITER PAID FOR EACH JOB IN FLIGHT. A live builder task carries
// its def and its progress but not its price, so "which of the five things
// we are building matters most" was unanswerable and idle hands went to
// whoever was nearest or happened to be first in a list (apexearth
// 2026-08-26: "if 1 of them is way more important than the rest, I'm hoping
// our constructors will assist the building which is the most important").
// The value the winning Want carried is recorded when the task is commissioned
// and read back here -- the market's own currency, not a second opinion.
array<IUnitTask@> gJobTask;
array<float> gJobVal;
array<float> gJobGain;   // metal/s the finished thing returns -- what an
                         // assist on it is actually accelerating
// The job BestJobBoss ranked first, for callers that need to price the help
// rather than just walk to it.
IUnitTask@ gBossJob;

void NoteJob(IUnitTask@ t, Want@ w)
{
	if ((t is null) || (w is null))
		return;
	for (uint i = 0; i < gJobTask.length(); ++i) {
		if (gJobTask[i] is t) {
			gJobVal[i] = w.value;
			gJobGain[i] = w.gain;
			return;
		}
	}
	gJobTask.insertLast(t);
	gJobVal.insertLast(w.value);
	gJobGain.insertLast(w.gain);
}

void JobSweep()
{
	for (uint i = 0; i < gJobTask.length(); ) {
		if ((gJobTask[i] is null) || gJobTask[i].IsDead()) {
			gJobTask.removeAt(i);
			gJobVal.removeAt(i);
			gJobGain.removeAt(i);
			continue;
		}
		++i;
	}
}

// -1 for work the market never priced -- the engine makes tasks of its own
// (build_chain, the native ladders) and those must not be ranked against a
// number they never had.
float JobValue(IUnitTask@ t)
{
	for (uint i = 0; i < gJobTask.length(); ++i) {
		if (gJobTask[i] is t)
			return gJobVal[i];
	}
	return -1.f;
}

// What the finished building returns, metal/s. -1 for work nobody priced.
float JobGain(IUnitTask@ t)
{
	for (uint i = 0; i < gJobTask.length(); ++i) {
		if (gJobTask[i] is t)
			return gJobGain[i];
	}
	return -1.f;
}

// THE MOST IMPORTANT THING WE ARE BUILDING THAT THIS UNIT CAN STILL HELP.
// Ranked by what the arbiter paid for it, halved for every hand already on
// site (the second lathe on a site doubles its speed, the tenth adds a
// tenth), and discounted for the walk. Every physical bound the join path
// already enforces still holds -- a saturated site cannot absorb another
// drain, and a site that finishes before the walk ends buys nothing.
// Why no job was joinable, for the floor's own diagnostic line.
int gJobSeen = 0, gJobUnpriced = 0, gJobFar = 0, gJobFull = 0,
	gJobLate = 0, gJobCant = 0, gJobHot = 0;

// BOTH RUNGS OUT OF ONE WALK. "Near only" is a FILTER on the same candidate
// set scored the same way, so the near answer is just the best candidate that
// also passed it -- and the caller asked for near, then for any, walking the
// whole live list, the sweep, the crew bounds and the threat probe twice, and
// four times per idle election once BestJobBoss ran its own pair. The near
// winner is left here; the return is the any-distance winner.
IUnitTask@ gJobNearBest;
// THE COMMANDER'S LEASH, one test for the election, the floor and the
// chase: further toward them than the caution cap, measured from HOME (from
// his feet it ratchets; from the lab it refused a tower at his own start,
// the lab standing 450 behind it), or past the eco leash from home. He is
// the game; a job out there is not worth him.
bool ComFar(const AIFloat3& in p)
{
	if (!Builder::gHomeSet)
		return false;
	if (p.distance2D(Builder::gHomePos) > ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH))
		return true;
	return (Military::ForwardFraction(p) - Military::ForwardFraction(Builder::gHomePos))
			> ai.GetTunable("apex_comm_fwd_cap", TUNE_COMM_FWD_CAP);
}

IUnitTask@ BestLiveJob(CCircuitUnit@ unit, bool requireFeed)
{
	JobSweep();
	Requests::SweepDead();
	gJobSeen = 0; gJobUnpriced = 0; gJobFar = 0; gJobFull = 0;
	gJobLate = 0; gJobCant = 0; gJobHot = 0;
	@gJobNearBest = null;
	float nearScore = 0.f;
	IUnitTask@ best = null;
	float bestScore = 0.f;
	const AIFloat3 me = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	// EcoFar's first two terms do not read the site; taken once.
	const bool leashed = EcoQuiet() && Builder::gHomeSet;
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ cand = Requests::gLive[i];
		if ((cand is null) || cand.IsDead()
			|| (cand.GetType() != Task::Type::BUILDER)
			|| (cand.buildDef is null))
			continue;
		if (cand is unit.task)
			continue;
		++gJobSeen;
		const float val = JobValue(cand);
		if (val <= 0.f) {
			++gJobUnpriced;
			continue;   // never priced, or priced at nothing
		}
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const bool far = isComm ? ComFar(where) : (leashed && EcoFar(where));
		if (far)
			++gJobFar;
		const float progress = Requests::Progress(cand);
		// Starting a building needs the build option; adding a lathe to a
		// nanoframe that already stands does not.
		if ((progress <= 0.f) && !unit.circuitDef.CanBuild(cand.buildDef)) {
			++gJobCant;
			continue;
		}
		const uint busy = Requests::Workers(cand);
		// THE CREW CAP IS A CLAIM ABOUT THE ECONOMY, NOT ABOUT THIS SITE:
		// SiteWorkerCap splits the income's hands EVENLY over live sites, so
		// with thirteen of them every one reads "full" at a single lathe --
		// measured, and it is why this rung never fired at all. While the
		// economy has flow going unspent there is room for another lathe, and
		// it belongs to the most valuable job rather than to whichever site
		// happened to fall under its equal share. Self-limiting with no
		// number anywhere: each hand that joins raises pull and closes the
		// gap behind it.
		if (requireFeed && (busy >= Requests::SiteWorkerCap(cand.buildDef))
			&& (FreeMetalFlow() < Requests::DRAIN)) {
			++gJobFull;
			continue;   // the income genuinely cannot feed another hand
		}
		const float dist = me.distance2D(where);
		if (requireFeed
			&& !Requests::WorthJoiningSite(cand, dist, speed,
				Catalog::gBuildPower[int(unit.circuitDef.id)])) {
			++gJobLate;
			continue;   // it lands before we arrive
		}
		if (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO) {
			++gJobHot;
			continue;
		}
		const float walkSec = (speed > 1.f) ? (dist / speed) : 60.f;
		// The hands on it are its crew, the guards already following that
		// crew, and the turrets whose reach covers it -- a frame the ring
		// finishes needs nobody (his watched seat: 30 guards on one nano
		// builder at a site full of turrets, advanced converters raised
		// alone where none stood).
		if (requireFeed
			&& Requests::NanoFed(cand, (busy > 0) ? busy : 1, dist, speed)) {
			++gJobFull;
			continue;
		}
		const float hands = float(busy) + float(GuardsOnJob(cand))
				+ NanoLatheReaching(where) / Requests::DRAIN;
		const float score = val / (hands + 1.f) / (1.f + walkSec / 60.f);
		if (!far && (score > nearScore)) {
			nearScore = score;
			@gJobNearBest = cand;
		}
		if (score > bestScore) {
			bestScore = score;
			@best = cand;
		}
	}
	return best;
}

// The hand working the most valuable job, for callers that guard a UNIT
// rather than take the task -- the priced assist want's target.
// WHICH JOB MATTERS MOST is a different question from WHETHER ANOTHER LATHE
// CAN BE FED. When the economy has nothing unspent, no hand adds progress
// anywhere -- but the hand should still be standing beside the work that
// matters most, because that is where it starts drawing the moment flow
// frees. So this ranks with the feed test off.
CCircuitUnit@ BestJobBoss(CCircuitUnit@ unit)
{
	@gBossJob = null;
	IUnitTask@ any = BestLiveJob(unit, false);
	IUnitTask@ job = (gJobNearBest !is null) ? gJobNearBest : any;
	if (job is null)
		return null;
	@gBossJob = job;
	array<CCircuitUnit@>@ on = job.GetUnits();
	if ((on is null) || (on.length() == 0))
		return null;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] !is null) && (on[i].id != unit.id))
			return on[i];
	}
	return null;
}

// What to lend a lathe to, best first: build power compounds, so a worker
// raising a nano outranks one raising a factory, which outranks any other
// build, which outranks a line that merely has something queued. Guards,
// patrols and reclaims are not bosses -- a guard chain does no work.
CCircuitUnit@ FloorBoss(CCircuitUnit@ unit, bool nearOnly)
{
	CCircuitUnit@ nano = null;
	CCircuitUnit@ fac = null;
	CCircuitUnit@ any = null;
	const bool leashed = nearOnly && EcoQuiet() && Builder::gHomeSet;
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ w = gWorkers[i];
		if ((w is null) || (w.id == unit.id) || (w.task is null))
			continue;
		if (w.task.GetType() != Task::Type::BUILDER)
			continue;
		if (isComm ? ComFar(w.GetPos(ai.frame)) : (leashed && EcoFar(w.GetPos(ai.frame))))
			continue;
		const int bt = int(w.task.GetBuildType());
		if (bt == int(Task::BuildType::NANO)) {
			if (nano is null)
				@nano = w;
		} else if (bt == int(Task::BuildType::FACTORY)) {
			if (fac is null)
				@fac = w;
		} else if ((bt != int(Task::BuildType::GUARD))
				&& (bt != int(Task::BuildType::PATROL))
				&& (bt != int(Task::BuildType::WAIT))
				&& (bt != int(Task::BuildType::COMBAT))
				&& (bt != int(Task::BuildType::RECLAIM))
				&& (bt != int(Task::BuildType::RESURRECT))) {
			if (any is null)
				@any = w;
		}
	}
	if (nano !is null)
		return nano;
	if (fac !is null)
		return fac;
	if (any !is null)
		return any;
	for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
		CCircuitUnit@ f = Brain::gFQFac[i];
		if (f is null)
			continue;
		if (leashed && EcoFar(f.GetPos(ai.frame)))
			continue;
		if (f.CountQueued(null) > 0)
			return f;
	}
	return null;
}

IUnitTask@ IdleFloor(CCircuitUnit@ unit, const string &in why)
{
	if (unit is null)
		return null;
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	const bool logIt = (ai.frame >= gNextFloorLog);
	// The commander takes only jobs inside his leash (ComFar). Far out
	// with nothing near, he walks home (below), never to any job.
	// FIRST CHOICE: take the most valuable job in flight and work it
	// directly. Taking the task beats guarding whoever holds it -- the hand
	// is counted on the site, so the crew bounds see it and the next idle
	// con ranks the same site as one hand busier.
	{
		IUnitTask@ any = BestLiveJob(unit, true);
		IUnitTask@ job = gJobNearBest;
		if ((job is null) && !isComm)
			@job = any;
		if (job !is null) {
			if (logIt) {
				gNextFloorLog = ai.frame + 30 * SECOND;
				AiLog("apex: floor " + unit.circuitDef.GetName() + " #" + unit.id
					+ " -> join:" + ((job.buildDef is null) ? "?" : job.buildDef.GetName())
					+ " v=" + formatFloat(JobValue(job) * 1000.f, "", 0, 2)
					+ " hands=" + Requests::Workers(job)
					+ " (" + why + ")");
			}
			return job;
		}
	}
	if (logIt) {
		AiLog("apex: floor-diag live=" + Requests::gLive.length()
			+ " priced=" + gJobTask.length()
			+ " seen=" + gJobSeen + " unpriced=" + gJobUnpriced
			+ " far=" + gJobFar + " cant=" + gJobCant + " full=" + gJobFull
			+ " late=" + gJobLate + " hot=" + gJobHot);
	}
	// The commander stays inside the leash: his death is the game, and a
	// cross-map assist is exactly the walk that kills him.
	// Nothing can be fed right now: stand beside the work that matters most,
	// and fall back to the class order only for work nobody priced.
	CCircuitUnit@ boss = BestJobBoss(unit);
	if (boss is null)
		@boss = FloorBoss(unit, true);
	if ((boss is null) && !isComm)
		@boss = FloorBoss(unit, false);
	if (boss !is null) {
		// SHORT LEASH. A held builder task is not re-elected, so the floor
		// must not lock a lathe out of the market: the priced assist want
		// commits for a minute, this one only fills the gap until the next
		// election has something to say.
		IUnitTask@ gt = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::LOW,
				boss, false, 15 * SECOND));
		if (gt !is null) {
			GuardNote(unit, boss);
			if (logIt) {
				gNextFloorLog = ai.frame + 30 * SECOND;
				AiLog("apex: floor " + unit.circuitDef.GetName() + " #" + unit.id
					+ " -> assist:" + boss.circuitDef.GetName() + " #" + boss.id
					+ " on " + (((boss.task is null) || (boss.task.buildDef is null))
						? "?" : boss.task.buildDef.GetName())
					+ " (" + why + ")");
			}
			return gt;
		}
	}
	// A commander with nothing to do out past his leash walks home first.
	if (isComm && ComFar(unit.GetPos(ai.frame))) {
		IUnitTask@ home = Builder::Retreat(unit);
		if (home !is null) {
			if (logIt) {
				gNextFloorLog = ai.frame + 30 * SECOND;
				AiLog("apex: floor " + unit.circuitDef.GetName() + " #" + unit.id
					+ " -> home, past the leash (" + why + ")");
			}
			return home;
		}
	}
	// Nothing to help: metal lying on the ground is still metal.
	IUnitTask@ rt = Builder::IdleFeatureReclaim(unit, isComm);
	if (rt !is null) {
		if (logIt) {
			gNextFloorLog = ai.frame + 30 * SECOND;
			AiLog("apex: floor " + unit.circuitDef.GetName() + " #" + unit.id
				+ " -> reclaim (" + why + ")");
		}
		return rt;
	}
	// Last resort: sit on the farm, where a patrol auto-assists anything
	// that starts there rather than standing wherever it stopped.
	if (gFarmSet) {
		IUnitTask@ pt = aiBuilderMgr.Enqueue(TaskB::Patrol(Task::Priority::LOW,
				gFarmPos, 20 * SECOND));
		if (pt !is null) {
			if (logIt) {
				gNextFloorLog = ai.frame + 30 * SECOND;
				AiLog("apex: floor " + unit.circuitDef.GetName() + " #" + unit.id
					+ " -> farm patrol (" + why + ")");
			}
			return pt;
		}
	}
	if (logIt) {
		gNextFloorLog = ai.frame + 30 * SECOND;
		AiLog("apex: floor " + unit.circuitDef.GetName() + " #" + unit.id
			+ " -> idle, nothing to assist (" + why + ")");
	}
	return null;
}


}  // namespace Market
