namespace Builder {

// Work already in progress, and the two reasons to drop it.

// "On the way, not a special trip." HoldWorkInProgress (below) returns the
// held task unconditionally for any named site, so once a builder is mid-walk
// to a factory/nano/energy/etc. it never reaches DefaultMakeTask/MexOffer
// again until it arrives or the site becomes unsafe -- confirmed against
// IBuilderTask::Reevaluate (task/builder/BuilderTask.cpp:534), which DOES
// call MakeTask on this builder roughly once a second while it travels, but
// the script never lets that offer through. apexearth watched this live
// 2026-08-14 as "we are still walking past mexes without building with our
// cons" -- a moving con, not an idle one (that gap was MexOffer, same night).
//
// The detour test is geometric, not a value threshold: extra distance to
// swing through the mex before continuing to the original site, against
// distance still left to travel there. A permanent mex is worth far more
// than a short detour, but this only ever fires for one that is genuinely on
// or near the path already being walked.
const float PASS_MEX_DETOUR_FRAC = 0.35f;

IUnitTask@ PassingMex(CCircuitUnit@ unit, bool isComm)
{
	if (ai.GetTunable("apex_take_passing_mex", TUNE_TAKE_PASSING_MEX) <= 0.f)
		return null;
	if (isComm)
		return null;
	// A nano turret tidying in place has a busy task and a position -- the
	// detour math then reads near-zero and it "passes" a mex it can neither
	// walk to nor build (26 blocked tasks in one audited game).
	CCircuitDef@ mexDef = SideDef3("armmex", "cormex", "legmex");
	if ((mexDef !is null) && !unit.circuitDef.CanBuild(mexDef))
		return null;
	IUnitTask@ busy = unit.task;
	if (busy is null)
		return null;
	const string kind = SiteBuildName(busy);
	// Nothing to improve on a walk that is already expansion.
	if ((kind == "") || (kind == "mex") || (kind == "mexup"))
		return null;

	const AIFloat3 pos = unit.GetPos(ai.frame);
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, pos);
	if (spot < 0)
		return null;
	const AIFloat3 mpos = aiEconomyMgr.GetMexSpotPos(spot);
	if (OnMap(mpos) && (ThreatFor(unit, mpos) > CON_THREAT_VETO))
		return null;

	const AIFloat3 dest = busy.GetBuildPos();
	const float remaining = sqrt(pos.SqDistance2D(dest));
	const float detour = sqrt(pos.SqDistance2D(mpos)) + sqrt(mpos.SqDistance2D(dest)) - remaining;
	if (detour > remaining * PASS_MEX_DETOUR_FRAC)
		return null;

	return aiEconomyMgr.EnqueueMexAt(unit, spot);
}

IUnitTask@ HoldDefenceInProgress(CCircuitUnit@ unit, bool isComm)
{
	// Let a constructor FINISH the defence it already started.
	//
	// AiMakeTask re-decides from scratch on every call, and IBuilderTask::
	// Reevaluate swaps the unit's task whenever we hand back a different BUILD
	// TYPE. Fortify only fires while ConDugIn() is true, i.e. while the con is
	// being shot at -- so the moment the shooting stops the pipeline offers a
	// mex or an energy building instead, the swap happens, and the half-built
	// tower is abandoned. Without this hold, script-placed static defence is
	// accepted but never finished.
	//
	// Deliberately narrow: only a DEFENCE build already in progress, only while
	// its site is not itself dangerous (the abandon checks below still own that
	// case), and never for the commander, which has its own hold rule.
	//
	// THE THREAT GATE EXCLUDES EXACTLY THE FRONT: a site on the line is
	// contested by definition, so this hold fires for a mex guard at home and
	// not for the Brain's front request. apex_hold_front extends the hold to a
	// forward defence task as well, since the front curve sits a setback inside
	// our own side of the crossing that is meant to make the site survivable.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (busy.GetType() == Task::Type::BUILDER)
			&& (busy.GetBuildType() == Task::BuildType::DEFENCE))
		{
			const AIFloat3 at = busy.GetBuildPos();
			if (ThreatFor(unit, at) <= CON_THREAT_VETO)
				return busy;
			if ((ai.GetTunable("apex_hold_front", TUNE_HOLD_FRONT) > 0.f) && OnMap(at)
				&& (Military::OnBorder(at) || Military::NearFront(at)))
			{
				return busy;
			}
		}
	}
	return null;
}

IUnitTask@ AbandonUnsafeSite(CCircuitUnit@ unit, bool isComm)
{
	// Already walking to a site that is now inside enemy fire. IBuilderTask::
	// Reevaluate calls this hook on every task update for as long as the builder
	// is away from its build position, so the whole walk is covered -- but it
	// swaps the unit's task only when what we hand back differs in build type,
	// so a refusal here has to be a real task rather than null.
	if (!isComm) {
		IUnitTask@ held = unit.task;
		const string kind = SiteBuildName(held);
		if (kind != "") {
			float heat = ThreatFor(unit, held.GetBuildPos());
			if (kind == "mex")
				heat = MexHeat(held.GetBuildPos(), heat);
			if (heat > CON_THREAT_VETO) {
				++gConAbandoned;
				ConStrike(unit);
				LogConVeto(unit, "abandon", kind, heat);
				// A defence post and a retreat both differ in build type; another
				// mex would not, so the reroute belongs on the refuse path only.
				IUnitTask@ post = ContestDefence(unit, kind, heat, held.GetBuildPos());
				if (post !is null)
					return post;
				IUnitTask@ flee = Retreat(unit);
				if (flee !is null)
					return flee;
			}
		} else if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::RECLAIM))
		{
			// SiteBuildName deliberately excludes RECLAIM, so the abandon check
			// above never covered it: a destination checked safe ONCE at dispatch
			// is never re-checked during the walk or while reclaiming, and an
			// active battlefield's safety can flip in that time. Same abandon
			// pattern as mex/build above, but no ContestDefence -- building a
			// tower at a corpse pile doesn't fit the same shape as holding a mex.
			const float heat = ThreatFor(unit, held.GetBuildPos());
			if (heat > CON_THREAT_VETO) {
				++gConAbandoned;
				ConStrike(unit);
				LogConVeto(unit, "abandon", "reclaim", heat);
				IUnitTask@ flee = Retreat(unit);
				if (flee !is null)
					return flee;
			}
		}
	}
	return null;
}

// A mex (or moho) on an EMPTY energy bank is a frozen build: the engine
// CmdWaits any non-comm builder that arrives (BuilderTask.cpp:518) and leaves
// a commander standing at the site building at zero speed -- and in-range
// Reevaluate never calls MakeTask again, so the script cannot intervene once
// the builder arrives. apexearth, watching: "the proper thing to do would be
// to insert the energy build order in front of the mex". So during the WALK
// (where re-election still reaches us) swap to a solar at the builder's feet;
// the mex spot stays open and is re-elected the moment the solar stands.
// Requests::Take's own in-flight cap keeps a whole crew from all doing this
// at once -- a null grant means energy is already being fixed, keep walking.
IUnitTask@ EnergyBeforeMex(CCircuitUnit@ unit)
{
	if (!aiEconomyMgr.isEnergyEmpty)
		return null;
	IUnitTask@ held = unit.task;
	if ((held is null) || (held.GetType() != Task::Type::BUILDER))
		return null;
	const int bt = held.GetBuildType();
	if ((bt != Task::BuildType::MEX) && (bt != Task::BuildType::MEXUP))
		return null;
	CCircuitDef@ gen = SolarDef();
	if ((gen is null) || !gen.IsAvailable(ai.frame))
		return null;
	IUnitTask@ fix = Requests::Take(unit, gen, Task::BuildType::ENERGY,
			Task::Priority::HIGH, unit.GetPos(ai.frame), 0.f, SQUARE_SIZE * 8);
	if (fix !is null)
		AiLog(Factory::T() + "apex: energy first -- solar before "
			+ SiteBuildName(held) + " (" + unit.circuitDef.GetName() + ")");
	return fix;
}

IUnitTask@ HoldWorkInProgress(CCircuitUnit@ unit, bool isComm)
{
	// DO NOT DISPLACE WORK ALREADY IN PROGRESS.
	//
	// This hook is not only called for an idle builder: IBuilderTask::Reevaluate
	// calls it on every task update for as long as the builder is away from its
	// build position, and the engine swaps the unit's task whenever what we hand
	// back differs in BUILD TYPE. So an optional rule further down the pipeline
	// could otherwise yank a constructor off a site it was walking to, leaving a
	// claimed task nobody works. The veto/abandon checks above have already run,
	// so anything still held here is work the AI still considers safe.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (SiteBuildName(busy) != "")) {
			// SURPLUS ASSISTERS RE-ENTER THE AUCTION (apexearth: "if we're a
			// con already assisting a building we should consider building
			// the other thing we want"). The hold glued every joiner to the
			// site until completion, so build power pooled on whatever
			// started first and the want distribution never rebalanced.
			// A site keeps its ETA-derived worker count; workers beyond it
			// fall through to Decide. The release is deterministic -- the
			// HIGHEST ids go first -- because every surplus worker evaluates
			// this on the same stale count (orders are async), and without
			// a tiebreak the whole pack would leave at once.
			if ((ai.GetTunable("apex_assist_release", TUNE_ASSIST_RELEASE) > 0.f)
				&& (busy.GetType() == Task::Type::BUILDER)
				&& (busy.buildDef !is null))
			{
				array<CCircuitUnit@>@ crew2 = busy.GetUnits();
				if (crew2 !is null) {
					int wantN = BigBuildWorkersWanted(busy.buildDef);
					if (wantN < 1)
						wantN = 1;
					// Same eco-keep the peeler applies: income sites hold a
					// bigger crew before anyone is surplus.
					const int bt3 = busy.GetBuildType();
					if ((bt3 == Task::BuildType::ENERGY)
						|| (bt3 == Task::BuildType::CONVERT)
						|| (bt3 == Task::BuildType::MEXUP)
						|| (bt3 == Task::BuildType::MEX))
					{
						wantN = int(float(wantN)
								* ai.GetTunable("apex_peel_eco_keep", TUNE_PEEL_ECO_KEEP));
					}
					const int surplus = int(crew2.length()) - wantN;
					if (surplus > 0) {
						int higher = 0;
						for (uint c2 = 0; c2 < crew2.length(); ++c2) {
							if ((crew2[c2] !is null)
								&& (int(crew2[c2].id) > int(unit.id)))
								++higher;
						}
						if (higher < surplus)
							return null;
					}
				}
			}
			return busy;
		}
		// RECLAIM is deliberately excluded from SiteBuildName (see its comment),
		// which left it unheld here: AbandonUnsafeSite already re-checks safety
		// for a reclaim every tick and refuses it explicitly when it goes hot, so
		// a reclaim that survives that check is exactly as "still wanted" as a
		// mex or an energy building is. Without this, a builder mid-reclaim fell
		// through every tick to a fresh DefaultMakeTask offer, which differs in
		// build type from RECLAIM and so swaps the unit off the walk -- the
		// mex-A/mex-B flip-flop apexearth watched live, just as documented at
		// the top of AiMakeTask for the commander's own hold.
		if ((busy !is null) && (busy.GetType() == Task::Type::BUILDER)
			&& (busy.GetBuildType() == Task::BuildType::RECLAIM))
		{
			return busy;
		}
	}
	return null;
}

// -- the shift-queue chain: a real engine build queue for a builder ----------
//
// apexearth 2026-08-22: "queue up our next build item while we're already
// building something. That would speed up our building." The task layer is
// one order per builder, re-elected only after completion, so every building
// pays idle-think-walk overhead a human's shift-queue never does. Once a
// builder's cheap ENERGY/CONVERT build has a nanoframe standing (its own
// order is already applied -- appending earlier would be wiped by it), K more
// sites of the same def are SHIFT-appended, and the unit is held from
// re-election while the engine walks the chain with zero think-gaps.
//
// The hold has two shapes: task alive -> return it (same build type, no
// swap); task done -> holdIdle, and AiMakeTask returns null outright so no
// later rule issues the queue-wiping fresh order. CountQueued reads APPLIED
// commands only (the GiveOrder lag), so a sent-window frame bound covers the
// gap; at extreme headless sim speeds the window can expire early and cut a
// chain short -- that degrades to today's behaviour, never worse.
array<int> gChainIds;
array<int> gChainUntil;
int gChainQueuedTotal = 0;
// Hard ceiling on a chain hold past the sent window: two cheap builds plus
// walks. Past this the builder re-elects no matter what the queue reads.
const int CHAIN_HARD_FRAMES = 90 * SECOND;

IUnitTask@ ChainBuildRule(CCircuitUnit@ unit, bool isComm, bool &out holdIdle)
{
	holdIdle = false;
	const int id = int(unit.id);
	const int slot = gChainIds.find(id);
	IUnitTask@ busy = unit.task;
	if (slot >= 0) {
		// TIME-BOUNDED, ALWAYS: holding on the queue alone wedged builders
		// forever when an order stuck (measured seed-37: side-wide economy
		// HALVED, 18 cons parked). The sent window covers the order lag; a
		// live queue may extend the hold only to the hard ceiling, and past
		// it the unit re-elects whatever the queue says.
		const bool inWindow = ai.frame < gChainUntil[slot];
		const bool queueAlive = (unit.CountQueued(null) > 0)
				&& (ai.frame < gChainUntil[slot] + CHAIN_HARD_FRAMES);
		if (inWindow || queueAlive) {
			if (busy !is null)
				return busy;
			holdIdle = true;    // engine queue drives the idle unit
			return null;
		}
		gChainIds.removeAt(slot);
		gChainUntil.removeAt(slot);
		return null;
	}
	const int extras = int(ai.GetTunable("apex_chain_builds", TUNE_CHAIN_BUILDS));
	if ((extras <= 0) || isComm)
		return null;
	if ((busy is null) || (busy.GetType() != Task::Type::BUILDER))
		return null;
	const int bt = busy.GetBuildType();
	if ((bt != Task::BuildType::ENERGY) && (bt != Task::BuildType::CONVERT)
		&& (bt != Task::BuildType::NANO))
		return null;
	if (busy.target is null)
		return null;            // nanoframe first; see the header comment
	CCircuitDef@ d = busy.buildDef;
	if ((d is null)
		|| (d.costM > ai.GetTunable("apex_chain_max_cost", TUNE_CHAIN_MAX_COST)))
		return null;
	const AIFloat3 at0 = busy.GetBuildPos();
	if (!OnMap(at0))
		return null;
	int queued = 0;
	AIFloat3 seed = at0;
	for (int i = 0; i < extras; ++i) {
		const AIFloat3 s = ai.FindBuildSiteNear(d, seed, 350.f);
		if (!OnMap(s))
			break;
		unit.CmdBuildQueuedAt(d, s);
		seed = s;
		++queued;
	}
	if (queued == 0)
		return null;
	gChainIds.insertLast(id);
	gChainUntil.insertLast(ai.frame + 15 * SECOND);
	if (gChainQueuedTotal < 3 || (gChainQueuedTotal % 20 == 0)) {
		AiLog(Factory::T() + "apex: chain-queued " + queued + "x "
			+ d.GetName() + " behind the one being built");
	}
	gChainQueuedTotal += queued;
	return busy;
}

}  // namespace Builder
