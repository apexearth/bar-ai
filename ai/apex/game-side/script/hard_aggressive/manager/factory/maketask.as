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
	double facT = Perf::T0();
	IUnitTask@ facR = FacMakeInner(unit);
	Perf::Add("mt.factory", facT);
	return facR;
}

IUnitTask@ FacMakeInner(CCircuitUnit@ unit)
{
	FactoryDiag(unit);

	double fT = Perf::T0();
	IUnitTask@ t = AssistantWork(unit);
	Perf::Add("fac.assist", fT);
	if (t !is null)
		return FacWon("assist", t);
	fT = Perf::T0();

	// A LINE THE BRAIN DRIVES IS ANSWERED HERE AND NOWHERE ELSE.
	//
	// It holds a standing queue laid with CmdBuildUnit, and CRecruitTask::Finish()
	// calls Cancel(), which CmdRemoves every build order still on the factory. So
	// one recruit task assigned to a driven line -- by our rules or by
	// DefaultMakeTask below -- wipes the queue at its first completion. Sitting
	// above the queue-full branch is deliberate for the same reason: that branch
	// hands the line to DefaultMakeTask, which is exactly what must not reach it.
	// The Wait keeps the factory manager treating the line as busy.
	if (Brain::DrivenFactory(unit)) {
		IUnitTask@ dq = Brain::FactoryQueueTask(unit);
		Perf::Add("fac.driven", fT);
		return FacWon("facqueue", dq);
	}
	Perf::Add("fac.free", fT);
	fT = Perf::T0();

	// Safe to sit first: this answers only for the advanced air plant, so the
	// ground line's branches below are untouched.
	@t = Air::MakeFactoryTask(unit);
	if (t !is null)
		return FacWon("air", t);

	// TAKING A LINE. Below Air:: so an air plant the air manager wants keeps its
	// own pathway -- and ABOVE the queue-full branch, which is the order that
	// matters.
	//
	// It sat below, and that made the whole scheme self-defeating. A driven line
	// refuses recruit tasks, so the pending recruit list never drains; the
	// queue-full branch then handed the NEXT factory that asked back to
	// DefaultMakeTask, so it was never adopted, so it created more recruit tasks.
	// Meanwhile a permanently-full recruit list plus income is one of the things
	// CFactoryManager answers by building another factory. Measured live,
	// 2026-08-12: `queue=10 unstarted=10 facs=7` on one player -- seven T1 labs,
	// ten recruit orders nobody could ever start, three of the seven lines ours.
	// apexearth, watching: "now at 40 m/s teal has 6 t1 botlabs."
	//
	// Nothing below this line can enqueue a recruit for a factory we drive, so
	// the queue-full throttle has nothing to protect on a driven line.
	@t = Brain::FactoryQueueTask(unit);
	if (t !is null)
		return FacWon("facqueue", t);

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
