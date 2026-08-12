namespace Factory {

// What a factory builds next, as an ordered pipeline. The first rule that
// returns a task wins; `taken` means a rule wants the line to stay IDLE, which
// is a deliberate outcome here rather than a failure.
//
// The rules live in rules_*.as; their bodies are unchanged from when they were
// inline in this function.
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if (!ApexActive())
		return aiFactoryMgr.DefaultMakeTask(unit);

	FactoryDiag(unit);

	IUnitTask@ t = AssistantWork(unit);
	if (t !is null)
		return FacWon("assist", t);

	// NO RULE BELOW MAY APPEND TO A QUEUE THAT IS ALREADY FULL.
	//
	// Every Enqueue in this pipeline is blind: CanEnqueueTask and GetTasks are
	// not bound to script, and CFactoryManager::Enqueue appends unconditionally.
	// Stock throttles its own producers at two pending per factory; our rules
	// were the only ones that never did, and the register above measured the
	// result -- 9 of 10 pending recruits unstarted on two factories.
	//
	// Declining hands the line to DefaultMakeTask, which scans the pending list
	// and ASSIGNS an existing task rather than creating another. That is the
	// queue being consumed instead of grown.
	if (!QueueHasRoom())
		return FacWon("queue-full", aiFactoryMgr.DefaultMakeTask(unit));

	// Safe to sit first: this answers only for the advanced air plant, so the
	// ground line's branches below are untouched.
	@t = Air::MakeFactoryTask(unit);
	if (t !is null)
		return FacWon("air", t);

	// TARGET COMPOSITION, ahead of the generic production branches but below the
	// floors that answer a specific need (assist bots, air, rez). See
	// manager/brain/mix.as: this converges the army toward a stated mix instead
	// of letting whichever rule answers first decide what the army becomes.
	@t = Brain::MixTask(unit);
	if (t !is null)
		return FacWon("mix", t);
	// An owned line does not fall through to the old production rules. If the
	// mix could not decide this tick, the ENGINE answers -- never our floors,
	// which would quietly reintroduce the composition the mix is steering away
	// from. apexearth: "make sure the old system doesn't interact with that
	// factory and add its own things."
	if (Brain::OwnsFactory(unit))
		return FacWon("mix-default", aiFactoryMgr.DefaultMakeTask(unit));

	@t = RezBotFloor(unit);
	if (t !is null)
		return FacWon("rez", t);
	@t = BankBuysBuildPower(unit);
	if (t !is null)
		return FacWon("bank-bp", t);
	@t = LateRadarPlane(unit);
	if (t !is null)
		return FacWon("radar-plane", t);
	@t = LateFighterScreen(unit);
	if (t !is null)
		return FacWon("fighter", t);
	// A floor like the two above it, and gated on five T2 blind guns already
	// standing, so it cannot reach back into the opening or the rush.
	@t = EyesForTheGuns(unit);
	if (t !is null)
		return FacWon("eyes", t);

	bool idle = false;
	@t = RushBuildPower(unit, idle);
	if (idle || (t !is null))
		return FacWon(idle ? "rush-idle" : "rush-bp", t);

	ConBranchLog(unit);
	// Above LosingArmyPush deliberately: both answer "we are behind", and this one
	// is the answer for the case where we have also stopped attacking.
	@t = DefensiveComposition(unit);
	if (t !is null)
		return FacWon("defensive", t);
	@t = LosingArmyPush(unit);
	if (t !is null)
		return FacWon("losing-push", t);
	@t = ShareAdvancedCon(unit);
	if (t !is null)
		return FacWon("share-acon", t);
	@t = AirConMinimum(unit);
	if (t !is null)
		return FacWon("air-con", t);

	@t = EcoLeadLine(unit, idle);
	if (idle || (t !is null))
		return FacWon(idle ? "ecolead-idle" : "ecolead", t);

	// An air plant that Air:: did not claim above falls through to
	// DefaultMakeTask like every other factory.
	//
	// This used to return null for ANY air factory unless the air role had been
	// permanently abandoned, on the reasoning that every sanctioned use of an air
	// plant claims it earlier in this function. That reasoning holds only for the
	// air lead's plants while it is armed. It is false for the air-slot opener,
	// which is never the lead (the lead is elected on highest income and the
	// opener has the worst economy on the team), and it is false for the lead
	// itself whenever Air:: declines -- quota met, enemy AA too high, not yet
	// committed. In all of those cases the plant produced NOTHING, permanently.
	//
	// apexearth: "our air player made just 1 con and thats it... air lab just
	// sitting there doing nothing else", then "i bet we have some special flag or
	// branching path of logic that is breaking our air opening player", then
	// "Can we not have this whole Air::RoleAbandoned logic in here? I bet that is
	// the cause of a lot of air labs i see sitting there doing nothing."
	//
	// The concern this originally answered -- trickling bombers one at a time
	// into enemy AA -- is about how bombers are USED, not about starving every
	// air plant on the team.
	return FacWon("default", aiFactoryMgr.DefaultMakeTask(unit));
}

}  // namespace Factory
