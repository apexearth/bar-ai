namespace Builder {

// What a constructor does next, as an ordered pipeline. Read top to bottom: the
// first rule that returns something wins, and everything after
// DefaultMakeTask() only screens or replaces the offer the engine made.
//
// ORDER IS THE DESIGN HERE. Anything placed above DefaultMakeTask can claim a
// constructor before mex expansion is even offered, which is how twelve
// individually reasonable rules cut metal production 4.3x -- see CHANGES.md
// 2026-08-01. Adding a rule means choosing where in this list it goes, and that
// choice is the whole decision.
//
// The rules themselves live in rules_*.as; the signatures take isComm/isAdvCon
// rather than recomputing them so the bodies are unchanged from when they were
// inline here.
// THE ENGINE'S ENTRY POINT. TaskModuleScript looks up this exact signature.
//
// The ladder is MakeTaskInner below; this exists so the defence-share cap has ONE
// site. Defence work reaches a constructor from eleven script Enqueues and from
// the engine's own elector and build_chain porcupine entries, and the only thing
// they all pass through is the answer returned here. See defcap.as.
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
	// Only an advanced constructor can build a moho, so it is the one unit that
	// can convert a mex into the biggest economy step available. The two wreck
	// rules below sit ahead of the "never displace real work" line and so can
	// take it off exactly that job -- and the reclaim they hand it is an AREA
	// order (CmdReclaimInArea with CONTROL_KEY, which deliberately ignores the
	// autoreclaimable filter), so it eats whatever is in the circle. apexearth,
	// watching live: "our t2 con is wasting his time reclaiming trees instead
	// of upgrading mexes."
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
	// apexearth: "once we make ~30+ metal per second we definitely should be
	// making a T2 lab with high priority in a SAFE location behind our base."
	// High priority means above DefaultMakeTask, which is where mex expansion
	// lives -- so this is the one rule deliberately placed in the zone the header
	// warns about, and it is bounded to match: one plant, one builder, only while
	// no factory task exists at all, only before we have T2, and only on a
	// reclaim-proof income reading. It is also a redirect rather than a new class
	// of spend -- the engine builds this plant regardless, later and wherever
	// FindBuildSite lands it.
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

	// EXPANSION IS A WANT NOW, NOT AN EARLY RETURN. ExpansionAlwaysWins used to
	// sit here and take any mex offer immediately, ahead of energy, defence and
	// everything Brain::Decide ranks -- exactly backwards from what it was meant
	// to be. apexearth: "ExpansionAlwaysWins was always supposed to be a 'last
	// resort' task when there's nothing better to do. The mentality is -
	// 'nothing super urgent, so let's keep expanding our economy'." Measured
	// live, 8v8: of every offer the engine made, 493 were mex against 46
	// everything else combined, because a mex-rich map means a mex is almost
	// always available to grab first. brain.as's own MexWant already ranks mex
	// against every other option on real economic value (0.033 metal/metal
	// against a reactor's 0.0034 -- expansion earns most wins on merit, it does
	// not need a queue-jump to get them) and documents this exact intent:
	// apexearth, "expansion always wins is now being replaced by logic in the
	// brain." This early return was the one piece of that move that never
	// actually happened. Nothing new is needed to make expansion the true last
	// resort: `if (task !is null) return task;` further down already returns
	// ANY leftover engine offer, mex included, once nothing else claimed the
	// builder -- that is the whole of "last resort", already in the pipeline.

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

	// A TURRET ON A MEX MUST NOT OUTRANK UPGRADING ONE.
	//
	// This rule used to sit ABOVE DefaultMakeTask, so a constructor that the
	// engine would have sent to a MEXUP built a guard tower instead -- measured
	// in a 1v1: 162 mex-guard picks against 4 upgrades all game, t2Mex still 1
	// at eighteen minutes. apexearth, for the fifth time: "still are not
	// prioritising mex upgrades... there's probably special logic in here, and
	// it is overriding our mex stuff."
	//
	// Moved above DefaultMakeTask 2026-08-12 at apexearth's request -- "if we have
	// an unguarded mex then guarding it should be a boosted priority" -- so this
	// second call would only ever find what the first one already declined.
	//
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
	// that has not reached its site yet, purely to ask "is there something more
	// important?", and reassigns only on a different build type. Each of our
	// enqueueing rules answering that question creates a task -- and if the type
	// matches, the builder stays where it was and the new task is an orphan with
	// no worker. See Brain::AskingForNewWork for the measurement.
	//
	// Handing back the engine's own offer keeps CircuitAI's re-election working
	// (that offer is an existing task, not a new one); what stops is US inventing
	// work for a builder that already has some.
	//
	// EXCEPT this return bypasses VetoCommanderHold entirely: if AskingForNewWork
	// is already false because the commander is mid-walk to a held task, `task`
	// here is just this tick's fresh DefaultMakeTask offer, and if IT differs in
	// build type from what is held, returning it swaps the commander off the walk
	// before VetoCommanderHold -- which lives further down, past this early
	// return -- ever gets a chance to protect it. Measured live: the first
	// factory task, offered five seconds in, sat at workers=0 for a whole
	// 5-minute game because of exactly this. Ask the same "is this the first
	// factory, already assigned" question here, first, so the walk is protected
	// on every path, not only the one that reaches VetoCommanderHold.
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
	if (!Brain::AskingForNewWork(unit))
		return task;

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

	if (task !is null)
		return task;   // strictly additive: never displace real work

	@t = MetalFullFallback(unit, isComm);
	if (t !is null)
		return t;
	@t = TidyObsolete(unit, isComm);
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

	// THE LAST LINE, BELOW EVERY OTHER RULE. Two things are already proven true
	// here and they are the whole reason this position is safe: `task` is null,
	// because the `if (task !is null) return task` above returned otherwise -- so
	// the engine declined on this call; and Brain::AskingForNewWork was true at
	// the top of the optional block, so this unit holds IDLE/NIL/WAIT. It has no
	// work to displace. Assist::Fallback enqueues no building.
	return Assist::Fallback(unit, isComm);
}

}  // namespace Builder
