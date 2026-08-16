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
	IUnitTask@ task = DefenceShareScreen(unit, isCommander, MakeTaskInner(unit));
	return GuardBuildCapability(unit, task);
}

// GENERAL CAPABILITY GUARD -- generalizes the 2026-08-14 IsAdvConDef fix.
//
// mexguard.as/converter.as patched two call sites after a T1 constructor
// handed an advanced-only def died its task every single time (45/45
// samples, zero engine errors -- see CHANGES.md). Any rule above this line
// can make the same mistake for any def; this is the one place every one of
// them passes through before the engine ever sees the order. CanBuild is
// CircuitAI's own buildOptions lookup (an unordered_set::find already kept
// for native task assignment), not a re-derivation from cost or name.
IUnitTask@ GuardBuildCapability(CCircuitUnit@ unit, IUnitTask@ task)
{
	if ((task is null) || (unit is null))
		return task;
	if (task.GetType() != Task::Type::BUILDER)
		return task;
	// Only CONSTRUCTION types carry a def the worker must be able to BUILD.
	// REPAIR/RECLAIM/RESURRECT/RECRUIT tasks put the TARGET's def in buildDef
	// (a repair of an armck reads buildDef=armck), so checking those against
	// buildOptions blocked legitimate assist/repair work -- measured 291
	// commander-assists-advsol and 43 con-repairs-con nulled in one game.
	if (int(task.GetBuildType()) >= int(Task::BuildType::REPAIR))
		return task;
	CCircuitDef@ def = task.buildDef;
	if (def is null)
		return task;
	if (unit.circuitDef.CanBuild(def))
		return task;

	// A worker that cannot BUILD the def can still ASSIST it once a nanoframe
	// stands -- and a repair task on the nanoframe is exactly that. This is
	// what a Butler (armfark) is for, and it also breaks the hot re-election
	// loop: a bare null sent the unit back through the pipeline to receive the
	// same offer next tick, ~2,500 times a game per pair (measured, 8v8
	// Glitters 20260815-080058).
	CCircuitUnit@ frame = task.target;
	if (frame !is null)
		return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::NORMAL, frame));

	AiLog("apex: BUG blocked " + unit.circuitDef.GetName() + " -> "
		+ def.GetName() + " (not in buildOptions)");
	return null;
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

	// A REZ BOT BUILDS NOTHING (armrectr/cornecro buildoptions are empty), so
	// every build rule below is a guaranteed GuardBuildCapability block for it
	// -- measured 1443 blocked tasks for cornecro in one 30-minute game, each
	// one a wasted election. Rez work, repair, the engine's own reclaim/rez
	// offers, then idle feature reclaim; never the build pipeline.
	if (IsRezzer(unit)) {
		@t = RezzerRepairNearby(unit);
		if (t !is null)
			return t;
		@t = aiBuilderMgr.DefaultMakeTask(unit);
		if (t !is null)
			return GuardBuildCapability(unit, t);
		// An idle rez bot clears obsolete buildings before eating trees --
		// same directive as the con idle floor and NanoTidy.
		@t = ObsoleteReclaim(unit, false, true, VALUE_NONE);
		if (t !is null)
			return t;
		return IdleFeatureReclaim(unit, false);
	}

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

	// AHEAD OF THE HOLD BELOW, ON PURPOSE: HoldWorkInProgress returns the held
	// task unconditionally for any named site, which is exactly what stops a
	// walking builder ever reaching DefaultMakeTask/MexOffer again -- see
	// PassingMex's own comment for why that turned "walked past an unclaimed
	// mex" into a standing gap rather than a one-off.
	@t = PassingMex(unit, isComm);
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

	// THE FIRST FUSION BEATS THE NEXT MEX UPGRADE for a freshly-free advanced
	// constructor. Measured (tournament 20260815-223228): 10 games, incomes to
	// 300, banks to 20k, 20-30 mohos, 45-68 advanced solars -- and zero
	// fusions, because Brain::Decide's mexup want re-claimed every advanced
	// con the moment it freed, and the optional-cluster hook below Decide was
	// never reached by a unit that could act. Bounded hard: only while NO
	// reactor exists (a nanoframe counts as one), and EcoFusion's own moho
	// trigger and in-flight bound still decide whether.
	// THE ECONOMY PIPELINES, above the mexup want, ONE claim each: a reactor
	// (fusion or AFUS, serial -- apexearth: "always making a fusion or afus
	// once we get to that stage... only build one at a time") and one advanced
	// converter ("always making the advanced energy converters... we need a
	// lot"). Each rule refuses while its one slot is occupied, so at most two
	// advanced cons are ever claimed here and the rest stay on mohos -- the
	// bank-refill stampede this hook once caused (mexups halved, metal -33%)
	// cannot recur.
	// LANE 0, ahead of the reactor: the moho. apexearth: "we have 3 regular
	// mexes right in the middle of our base... upgrade priority. Ideally we
	// have more than 1 advanced con and one works on the mex upgrades while
	// the other makes the fusion stuff... an upgraded mex gives 4 times the
	// metal." One upgrade under way at all times, read from the live MEXUP
	// task count -- no ledger to drift, nothing to resync.
	if (isAdvCon
		&& (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::MEXUP)) == 0))
	{
		Brain::Want@ up = Brain::MexUpgradeWant(unit);
		if ((up !is null) && (up.def !is null)
			&& unit.circuitDef.CanBuild(up.def))
		{
			IUnitTask@ upt = aiBuilderMgr.EnqueueMexUp(up.pos, up.def);
			if (upt !is null) {
				AiLog(Factory::T() + "apex: mexup pipeline by "
					+ unit.circuitDef.GetName());
				return upt;
			}
		}
	}
	if (isAdvCon && ReactorPipelineOpen()) {
		@t = EcoFusion(unit);
		if (t !is null)
			return t;
	}
	if (isAdvCon) {
		@t = ConverterPipeline(unit);
		if (t !is null)
			return t;
	}
	// LANE 3: front fortresses, past the T3-income bar. See FrontFortress.
	if (isAdvCon) {
		@t = FrontFortress(unit);
		if (t !is null)
			return t;
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
