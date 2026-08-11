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
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
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
	// EXPANSION OUTRANKS OPTIONAL SPENDING.
	//
	// The header above says order is the design and that anything placed before
	// DefaultMakeTask claims a constructor before expansion is even considered.
	// OptionalWork and Fortify were both placed there, and between them they can
	// claim a builder for AA, a deterrence tower, an energy converter, a gantry,
	// a nuke silo, a Pulsar, a shield or a dig-in -- so a constructor that could
	// have been upgrading a mex spends itself on any of those first.
	//
	// apexearth, watching an 8v8: "in our build order we should prefer to make
	// T2 mex upgrades on OUR mexes instead of making something like an advanced
	// metal converter, or a rattlesnake. I see purple making those two things at
	// the same time instead of properly focusing on increasing their metal
	// income."
	//
	// This is the 2026-08-01 failure mode exactly: twelve rules were added ahead
	// of DefaultMakeTask, every one of them fired, and metal production fell
	// 4.3x because mex upgrades live behind them. Asking the engine FIRST and
	// taking the offer only when it is expansion costs nothing -- ExpansionAlwaysWins
	// returns null for every other build type, so the optional rules below still
	// get their turn on the same offer.
	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
	NoteOffer(unit, task, isAdvCon);
	if (isComm) {
		++gCommOffers;
		if (task is null)
			++gCommOfferNull;
		CommDiag();
	}

	@t = ExpansionAlwaysWins(task);
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
	// Below the expansion check it keeps doing its job -- bare mexes still get
	// their first turret from whatever the engine did not want for expansion --
	// and it can no longer displace the upgrade that pays for everything.
	@t = CommanderMexGuard(unit, isComm);
	if (t !is null)
		return t;

	// Before any optional spending: if the engine just offered a SECOND task for
	// a building one of ours already started (or is walking to), take that one
	// instead. A redirect of an offer already made -- it enqueues nothing.
	@t = JoinDuplicateBuild(unit, isComm, task);
	if (t !is null)
		return t;

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

	// Its own recent history says it cannot expand, so stop sending it out. The
	// tower it puts up instead is what makes the ground usable later -- but only
	// where something is not already standing; see AreaNeedsDefence.
	if (!isComm && !Factory::EcoLeadActive() && ConDugIn(unit)) {
		IUnitTask@ dig = Fortify(unit);
		if (dig !is null)
			return dig;
	}

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

	// Nothing above answered. For every other builder that is fine -- the engine
	// asks again shortly. For the commander it is measured idle time on the
	// biggest builder we own, so it gets a last resort of its own.
	@t = CommanderIdleWork(unit, isComm);
	if (isComm && (t is null))
		++gCommEndNull;
	return t;
}

}  // namespace Builder
