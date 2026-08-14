namespace Builder {

// What a constructor does next, as an ordered pipeline. Read top to bottom: the
// first rule that returns something wins, and everything after
// DefaultMakeTask() only screens or replaces the offer the engine made.
//
// ORDER IS THE DESIGN HERE. Anything placed above DefaultMakeTask can claim a
// constructor before mex expansion is even offered. Adding a rule means
// choosing where in this list it goes.
//
// The rules themselves live in rules_*.as; the signatures take isComm/isAdvCon
// rather than recomputing them.
//
// TaskModuleScript looks up this exact signature. MakeTaskInner below does the
// ranking; this wrapper exists only so the defence-share cap has ONE site every
// path passes through -- see defcap.as.
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	const bool isCommander = (unit !is null)
			&& unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	return DefenceShareScreen(unit, isCommander, MakeTaskInner(unit));
}

IUnitTask@ MakeTaskInner(CCircuitUnit@ unit)
{
// 	AiDelPoint(lastPos);
// 	lastPos = unit.GetPos(ai.frame);
// 	AiAddPoint(lastPos, "task");

// 	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
// 	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)) {
// 		switch (task.GetBuildType()) {
// 		case Task::BuildType::MEX:
// 			AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 			break;
// 		case Task::BuildType::DEFENCE:
// 			AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 			break;
// 		default:
// 			break;
// 		}
// 	}
// 	return task;

	if (!ApexActive())
		return aiBuilderMgr.DefaultMakeTask(unit);

	// Above every early return below, including AskingForNewWork's: recording
	// what a builder can SEE is not a decision to go and eat it, so it carries
	// none of ScavengeWrecks' exclusions -- an advanced constructor still never
	// chases a pile, and still reports one.
	NoteWreckSighting(unit);

	IUnitTask@ t = RezzerFlee(unit);
	if (t !is null)
		return t;
	@t = RezzerFrontSalvage(unit);
	if (t !is null)
		return t;
	@t = RezzerEatCorpse(unit);
	if (t !is null)
		return t;

	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	// Only an advanced constructor can build a moho. The wreck rules below sit
	// ahead of the "never displace real work" line and hand it an AREA reclaim
	// (CmdReclaimInArea with CONTROL_KEY, which ignores the autoreclaimable
	// filter), so it can be pulled off a moho onto whatever is in the circle.
	const bool isAdvCon = !isComm && (unit.circuitDef.costM >= ADV_CON_COST);

	@t = HoldDefenceInProgress(unit, isComm);
	if (t !is null)
		return t;
	@t = CommanderTask(unit, isComm);
	if (t !is null)
		return t;
	@t = AbandonUnsafeSite(unit, isComm);
	if (t !is null)
		return t;
	@t = HoldWorkInProgress(unit, isComm);
	if (t !is null)
		return t;

	// THE ADVANCED PLANT OUTRANKS EXPANSION, ONCE AND ONLY ONCE.
	//
	// Deliberately placed above DefaultMakeTask, and bounded to match: one
	// plant, one builder, only while no factory task exists at all, only before
	// we have T2, and only on a reclaim-proof income reading. A redirect rather
	// than a new class of spend -- the engine builds this plant regardless,
	// later and wherever FindBuildSite lands it.
	@t = AdvancedPlantAtRear(unit);
	if (t !is null)
		return t;

	// A bare extractor outranks expansion, at any tier and for any builder: one
	// cheap turret per mex, asked once each. It cannot run away -- an extractor
	// with cover or a pending order is skipped -- and a raided mex costs more than
	// the turret every time.
	@t = CommanderMexGuard(unit, isComm);
	if (t !is null)
		return t;
	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
	NoteOffer(unit, task, isAdvCon);
	if (isComm) {
		++gCommOffers;
		if (task is null)
			++gCommOfferNull;
		CommDiag();
	}

	// EXPANSION IS A WANT, NOT AN EARLY RETURN: it competes in Brain::Decide,
	// ranked on economic value against every other option, and otherwise falls
	// through to `if (task !is null) return task;` further down, which returns
	// any leftover engine offer -- mex included -- once nothing else claimed the
	// builder. That is the whole of "last resort"; no dedicated rule is needed.
	//
	// EXCEPT when the engine's offer is ALREADY a mex: see MexOffer in
	// rules_offer.as for why Brain::Decide cannot be trusted to rank a home mex
	// at all in that case, let alone correctly.
	@t = MexOffer(task, unit);
	if (t !is null)
		return t;

	// STEP 2 OF THE OPENING, AND ONLY DURING IT.
	//
	// Below expansion so the mexes still come first, above everything optional
	// so the opening is not spent on a turret or a converter. Inert the moment
	// a factory exists or a factory task is active -- see builder/opening.as
	// for the C++ latch this replaces.
	@t = OpeningEnergy(unit);
	if (t !is null)
		return t;

	// Below expansion, above everything optional: a front tower the engine has
	// already elected a builder for is work in progress, not a proposal.
	@t = FrontDefenceOffer(task);
	if (t !is null)
		return t;

	// Before any optional spending: if the engine just offered a SECOND task for
	// a building one of ours already started (or is walking to), take that one
	// instead. A redirect of an offer already made -- it enqueues nothing.
	@t = Requests::Redirect(unit, isComm, task);
	if (t !is null)
		return t;

	// BELOW THIS LINE EVERY RULE ENQUEUES, AND THIS FUNCTION IS OFTEN A
	// RE-ELECTION RATHER THAN A REQUEST FOR WORK.
	//
	// IBuilderTask::Reevaluate calls MakeTask on every task update for a builder
	// that has not reached its site yet, and reassigns only on a different build
	// type. Handing back the engine's own offer keeps that re-election working
	// (it is an existing task, not a new one); what stops here is US inventing
	// work for a builder that already has some.
	//
	// EXCEPT this return bypasses VetoCommanderHold entirely: if AskingForNewWork
	// is already false because the commander is mid-walk to a held task, `task`
	// here is just this tick's fresh DefaultMakeTask offer, and if IT differs in
	// build type from what is held, returning it swaps the commander off the walk
	// before VetoCommanderHold -- further down -- ever gets a chance to protect
	// it. So the same "is this the first factory, already assigned" check runs
	// here too, first, so the walk is protected on every path.
	if (isComm && CommRules()) {
		IUnitTask@ held = unit.task;
		if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::FACTORY)
			&& !Factory::HaveAnyFactory()
			&& (ThreatFor(unit, held.GetBuildPos()) <= CON_THREAT_VETO))
		{
			return held;
		}
	}
	if (!Brain::AskingForNewWork(unit)) {
		// A REAL ENERGY CRISIS BREAKS THE HOLD. AskingForNewWork gates entry to
		// Brain::Decide (whose own energy want carries a stall multiplier,
		// ENERGY_STALL_MULT in brain.as) on the unit being genuinely free, so a
		// commander already committed to something else never got asked, no
		// matter how starved energy got. Scoped to a real crisis (<5% of
		// storage, same bar VetoCrisisAssist uses) and to the commander, the
		// one unit whose hold protection is strong enough to matter here; never
		// overrides a build that is itself already the fix.
		const bool energyCrisis = isComm
				&& (aiEconomyMgr.energy.storage > 0.f)
				&& (aiEconomyMgr.energy.current < aiEconomyMgr.energy.storage * RESOURCE_CRISIS_FRAC)
				&& (SiteBuildName(unit.task) != "energy")
				&& (SiteBuildName(unit.task) != "convert");
		if (!energyCrisis)
			return task;
	}

	// THE MACRO VIEW GETS ITS SAY BEFORE ANY OPTIONAL SPENDING.
	//
	// Rules below propose one thing each and the first one wins; Brain::Decide
	// ranks the mex upgrade against the whole optional class -- gantry, silo,
	// Pulsar, Pinpointer, converter, energy, nano -- and acts on the best whose
	// own rule accepts. It sits here, below the engine's expansion offer, so an
	// upgrade still outranks everything optional. See docs/18-brain.md.
	@t = Brain::Decide(unit, isAdvCon);
	if (t !is null)
		return t;

	@t = OptionalWork(unit, isComm);
	if (t !is null)
		return t;

	@task = VetoCommanderReclaim(unit, isComm, task);
	@task = VetoCommanderHold(unit, isComm, task);
	@task = VetoCrisisAssist(task);

	bool taken = false;
	@task = ScreenOffer(unit, isComm, task, taken);
	if (taken)
		return task;

	@t = ScavengeWrecks(unit, isComm, isAdvCon);
	if (t !is null)
		return t;

	if (task !is null) {
		// Rate-limited on the task handle changing, not a timer, so this logs
		// once per acceptance rather than once per re-election tick (AiMakeTask
		// re-runs this every update for a builder still walking to its site).
		if (isComm && (task !is gCommLastLogged)) {
			@gCommLastLogged = task;
			AiLog(Factory::T() + "apex: commander accepted " + SiteBuildName(task)
				+ " at " + formatFloat(task.GetBuildPos().x, "", 0, 0)
				+ "," + formatFloat(task.GetBuildPos().z, "", 0, 0));
		}
		return task;   // strictly additive: never displace real work
	}

	@t = MetalFullFallback(unit, isComm);
	if (t !is null)
		return t;
	@t = TidyObsolete(unit, isComm);
	if (t !is null)
		return t;

	// Rez bots only, and above the tree-reclaim floor below: a nearby damaged
	// unit that keeps existing is worth more than a handful of scrap metal, and
	// nothing above this claimed the bot, so there is no real work to displace.
	// See RezzerRepairNearby's own comment for why the engine never proposes
	// this on its own.
	@t = RezzerRepairNearby(unit);
	if (t !is null)
		return t;

	// THE FLOOR: task is null, we are past every productive rule above, and the
	// unit is otherwise going to stand still. Reclaiming a tree is strictly
	// better than idling -- see IdleFeatureReclaim's comment in reclaim.as for
	// why the metal-value floors above (ScavengeWrecks, TidyObsolete) never
	// covered this case.
	@t = IdleFeatureReclaim(unit, isComm);
	if (t !is null)
		return t;

	@t = RezzerPreemptReclaim(unit, isComm, task);
	if (t !is null)
		return t;

	// For the commander this is measured idle time on the biggest builder we own,
	// so it gets a last resort of its own.
	@t = CommanderIdleWork(unit, isComm);
	if (isComm && (t is null))
		++gCommEndNull;
	if (t !is null)
		return t;

	// THE LAST LINE, BELOW EVERY OTHER RULE. Safe because `task` is null here (the
	// engine declined) and Brain::AskingForNewWork was true above, so this unit
	// holds IDLE/NIL/WAIT and has no work to displace. Assist::Fallback enqueues
	// no building.
	return Assist::Fallback(unit, isComm);
}

}  // namespace Builder
