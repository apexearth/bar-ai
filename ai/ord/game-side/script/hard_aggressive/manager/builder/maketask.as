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
	@t = CommanderMexGuard(unit, isComm);
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

	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);

	@t = ExpansionAlwaysWins(task);
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

	return RezzerPreemptReclaim(unit, isComm, task);
}

}  // namespace Builder
