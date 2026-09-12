namespace Requests {

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

// `parallel` is a caller's explicit "open ANOTHER site": it skips the fold onto
// a nearby same-def request (JoinFor), which otherwise collapses a deliberate
// burst of distinct sites into one -- the nano burst measured burst=1 forever.
// The income-derived InFlight cap and the same-ground CoverFor test still hold.
IUnitTask@ Take(CCircuitUnit@ unit, CCircuitDef@ want, Task::BuildType bt,
		Task::Priority prio, const AIFloat3& in spot, float radius, float shake,
		bool &out created, bool parallel = false)
{
	created = false;
	if (Gate(G_BADREQ, (want is null) || !OnMap(spot)))
		return null;
	SweepDead();
	// THE one chokepoint every request rule passes through: an asker that
	// cannot build the def gets null BEFORE any task is enqueued, so the rule
	// falls through to its next option instead of leaving an orphan task and a
	// wasted election. GuardBuildCapability still backstops the pipeline's
	// return, but by then Take has already enqueued, so the guard nulls a
	// request whose orphan task exists.
	if (Gate(G_CANBUILD, (unit !is null) && !unit.circuitDef.CanBuild(want)))
		return null;
	// A def dying fast on repeat is held HERE, the door every lane walks
	// through -- the plant lane checked AbortBackoff and the convert lane did
	// not, so an eco commander re-elected the same doomed converter on the
	// same occupied square 156 times in one game (t7, si8-fix2-15m-s104)
	// while its energy gate sat unbuilt. See Builder::AbortBackoff.
	if (Gate(G_BACKOFF, Builder::AbortBackoff(int(want.id))))
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
		GateSeen(G_FACFORK);
		for (uint i = 0; i < gLive.length(); ++i) {
			IUnitTask@ cand = gLive[i];
			if ((cand is null) || cand.IsDead()
				|| (cand.GetBuildType() != Task::BuildType::FACTORY))
				continue;
			// SAME DEF only: a T2 lab ask during a T1 rebuild is tech, not a
			// fork -- the blanket fold made a T1 request absorb every T2
			// decision.
			if ((want !is null) && (cand.buildDef !is null)
				&& (cand.buildDef !is want))
				continue;
			// Manned only -- the engine's held placeholder task (see
			// FactoryManned) also lives in this registry, and handing IT
			// back wedged every asker on an unassignable task.
			// ...but an unmanned task the MARKET commissioned is our own
			// orphan, handed back: a commander freed off his lab left it
			// blocking every plant ask for 15 minutes (first lab at 18.97 min).
			if ((Workers(cand) == 0) && (Market::JobValue(cand) < 0.f))
				continue;
			if ((unit !is null) && (cand.buildDef !is null)
				&& !unit.circuitDef.CanBuild(cand.buildDef))
				continue;
			GateRef(G_FACFORK);
			return cand;
		}
	}

	// A SECOND EXPENSIVE REACTOR IS NEVER FOUNDED WHILE THE FIRST STILL HAS
	// ROOM FOR HANDS -- across DEFS. Not skippable by `parallel`: that flag is
	// a caller saying "open another site", and this is the one question the
	// caller is not allowed to answer for itself (the same reason the factory
	// fork test lives here). Wealth is the only exemption, and it must cover
	// the new bill on top of every bill already rising.
	// A bank that covers the second one outright is not asked to wait
	// (apexearth: "why we aren't making more advanced solars... overflowing
	// metal"); parallelism scales with wealth, and this is the wealth.
	// One big energy site at a time -- unless metal is being thrown away, when a
	// second site costs nothing that matters and the hold was 35 refused stall
	// answers in twelve minutes (canon game, 2026-09-08).
	if (Gate(G_BIGE, IsBigEnergy(want) && BigEnergyRising()
			&& !BigEnergyBetterThanRising(want) && !BankCovers(want)
			&& !Market::MetalWasting())) {
		// Hand the asker the best time-to-energy job instead of a hole in the
		// ground: e/s per second of remaining build, so a half-done fusion beats
		// a fresh afus (apexearth: "they should all focus their efforts on the
		// most efficient energy project ... (time to energy)").
		IUnitTask@ fold = Market::JoinBigEnergy(unit, want);
		if (fold !is null) {
			++gBigEFold;
			Log(want, "bigE-fold");
			return fold;
		}
		// Nothing this unit can reach or lathe. Refusing is still right: the
		// answer to "I cannot help the reactor" is a cheap generator below the
		// bar or another want entirely, never a second reactor.
		++gBigEHeld;
		Log(want, "bigE-held");
		return null;
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
	// This ground is already requested. Help with it if there is room and it is
	// worth walking to; otherwise back off. Never a second building here.
	IUnitTask@ cover = CoverFor(want, at, radius);
	if (cover !is null) {
		GateSeen(G_COVER);
		GateRef(G_COVER);
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
			if ((unit !is null) && !WorthJoiningSite(cover,
					unit.GetPos(ai.frame).distance2D(cover.GetBuildPos()),
					Catalog::gSpeed[int(unit.circuitDef.id)],
					Catalog::gBuildPower[int(unit.circuitDef.id)])) {
				++gTooFar;
				Log(want, "site-late");
				return null;
			}
			++gJoined;
			Log(want, "join-site");
			return cover;
		}
		// A site nobody more can help at, while the economy is short: open the
		// next one. Refused as covered, a cheap solar was strictly serial for
		// the whole team at 400-650 e/s income (Isthmus minutes 11-15, pull
		// 100-140 e/s over income, 44 advanced-solar elections held serial
		// and their askers falling back to radars).
		if (!(parallel && !spotWork && (bt != Task::BuildType::MEXUP))) {
			++gCovered;
			Log(want, "covered");
			return null;
		}
		Log(want, "par-site");
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
			GateSeen(G_FRAME);
			GateRef(G_FRAME);
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
			if (Gate(G_JOINNEAR, near !is null)) {
				++gJoined;
				Log(want, "join-near");
				return near;
			}
		}
		if (Gate(G_FULL, !parallel && (InFlight(want) >= EffectiveCap(want)))) {
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

}  // namespace Requests
