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
// TEMP comm-churn diag (apexearth, 2026-08-16, watching: "He constantly
// changes his mind on what he wants to do. Sometimes walks a long distance and
// then just turns around."). One line per BUILD-TYPE change -- returning a
// different handle of the SAME type does not reassign (IBuilderTask::
// Reevaluate), so only type flips are real mind-changes.
IUnitTask@ gCommChurnPrev;
int gCommChurnBt = -99;
int gCommChurnFrame = 0;
AIFloat3 gCommChurnPos;
int gCommChurnN = 0;

// IDLE-ELECTION BACKOFF. From ~minute 30 of a rich game, hundreds of builders
// sat on the idle task while every want's own bound was met, and each of them
// re-ran this whole pipeline every engine pass for another null -- measured
// 2,434 idle-still samples in minutes 30-50 of one hosted session, pure CPU on
// the host with no outcome (apexearth: "we run really inefficiently and it
// makes me lag"). A unit whose election just returned null waits a growing
// beat before the full pipeline runs again; any real answer clears it. Only
// units already holding IDLE/NIL -- a unit with work keeps its safety
// re-elections -- and never the commander.
array<int> gIdleBackId;
array<int> gIdleBackUntil;
array<int> gIdleBackStrikes;
const uint IDLE_BACK_MAX = 256;

int IdleBackSlot(int id)
{
	for (uint i = 0; i < gIdleBackId.length(); ++i) {
		if (gIdleBackId[i] == id)
			return int(i);
	}
	return -1;
}

bool IdleOrNil(CCircuitUnit@ unit)
{
	IUnitTask@ t = unit.task;
	if (t is null)
		return true;
	const int tt = t.GetType();
	return (tt == Task::Type::IDLE) || (tt == Task::Type::NIL);
}

bool IdleBackoffHolds(CCircuitUnit@ unit)
{
	if (!IdleOrNil(unit))
		return false;
	const int s = IdleBackSlot(int(unit.id));
	return (s >= 0) && (ai.frame < gIdleBackUntil[s]);
}

void NoteIdleElection(CCircuitUnit@ unit, IUnitTask@ result)
{
	const int id = int(unit.id);
	int s = IdleBackSlot(id);
	if (result !is null) {
		if (s >= 0) {
			gIdleBackId.removeAt(uint(s));
			gIdleBackUntil.removeAt(uint(s));
			gIdleBackStrikes.removeAt(uint(s));
		}
		return;
	}
	if (!IdleOrNil(unit))
		return;
	if (s < 0) {
		// Scratch, like AdvSlot: drop the lot rather than tracking removals.
		if (gIdleBackId.length() >= IDLE_BACK_MAX) {
			gIdleBackId.resize(0);
			gIdleBackUntil.resize(0);
			gIdleBackStrikes.resize(0);
		}
		gIdleBackId.insertLast(id);
		gIdleBackUntil.insertLast(0);
		gIdleBackStrikes.insertLast(0);
		s = int(gIdleBackId.length()) - 1;
	}
	int strikes = gIdleBackStrikes[s] + 1;
	const int capN = int(ai.GetTunable("apex_idle_backoff_maxmult", 4.f));
	if (strikes > capN)
		strikes = capN;
	gIdleBackStrikes[s] = strikes;
	gIdleBackUntil[s] = ai.frame
			+ strikes * int(ai.GetTunable("apex_idle_backoff", 2.f) * float(SECOND));
}

int gElectFrame = -1;
int gElectCount = 0;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	const bool isCommander = (unit !is null)
			&& unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	if (!isCommander && (unit !is null) && IdleBackoffHolds(unit))
		return null;
	Brain::gDecideDeferred = false;
	// THE WHOLE LADDER IS BUDGETED PER FRAME, not just the Brain: at 8v8
	// minute 55+ the engine sim alone eats ~24 of the 33ms frame budget, so
	// the AI's allowance is what is left -- elections beyond the budget defer
	// exactly like Brain deferrals (no backoff strike, the engine re-asks, a
	// builder decides a few frames later instead of the frame melting).
	// Commanders are never deferred.
	if (!isCommander && (unit !is null)) {
		if (gElectFrame != ai.frame) {
			gElectFrame = ai.frame;
			gElectCount = 0;
		}
		// Income-adaptive: a rich late game has 16 instances sharing one sim
		// thread and thousands of units already paying the engine's own cost,
		// so the budget halves exactly when each election is least urgent (a
		// metal-full base loses nothing to a 10-frame decision).
		const int electBudget = (aiEconomyMgr.metal.income
				>= ai.GetTunable("apex_elect_rich_income", 150.f))
				? 1 : int(ai.GetTunable("apex_elect_per_frame", 2.f));
		if (gElectCount >= electBudget) {
			Brain::gDecideDeferred = true;   // reuse: skips NoteIdleElection
			Perf::Note("mt.elect.defer");
			return null;
		}
		++gElectCount;
	}
	IUnitTask@ task = DefenceShareScreen(unit, isCommander, MakeTaskInner(unit));
	@task = GuardBuildCapability(unit, task);
	// A budget-deferred election is not a failed one: no backoff strike, the
	// engine re-asks next pass and the same decision is made a frame later.
	if (!isCommander && (unit !is null) && !Brain::gDecideDeferred)
		NoteIdleElection(unit, task);
	if (isCommander)
		CommChurnDiag(unit, task);
	return task;
}

void CommChurnDiag(CCircuitUnit@ unit, IUnitTask@ task)
{
	if ((task is null) || (task is gCommChurnPrev))
		return;
	const int bt = int(task.GetBuildType());
	const AIFloat3 here = unit.GetPos(ai.frame);
	if ((gCommChurnPrev !is null) && (bt != gCommChurnBt)) {
		++gCommChurnN;
		const AIFloat3 site = task.GetBuildPos();
		AiLog(Factory::T() + "apex: comm-switch #" + gCommChurnN
			+ " ty" + int(task.GetType())
			+ " bt" + gCommChurnBt + "->bt" + bt
			+ " held=" + ((ai.frame - gCommChurnFrame) / SECOND) + "s"
			+ " walked=" + formatFloat(here.distance2D(gCommChurnPos), "", 0, 0)
			+ " " + SiteBuildName(task)
			+ " dist=" + (OnMap(site)
				? formatFloat(here.distance2D(site), "", 0, 0) : "?"));
	}
	@gCommChurnPrev = task;
	gCommChurnBt = bt;
	gCommChurnFrame = ai.frame;
	gCommChurnPos = here;
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
	// A STATIC worker can only work what its lathe reaches -- construction,
	// repair and reclaim alike. Checked BEFORE the repair/reclaim early
	// return below, because reach applies to those too (apexearth, live:
	// "nano turrets trying to reclaim obsolete buildings which are out of
	// their range" -- a permanent silent no-op). Small slack: build distance
	// is to the target's edge, GetBuildPos is its centre.
	if (!unit.circuitDef.IsMobile()) {
		const AIFloat3 site = task.GetBuildPos();
		if (OnMap(site) && (unit.GetPos(ai.frame).distance2D(site)
			> unit.circuitDef.GetBuildDistance() + 64.f))
		{
			return null;
		}
	}
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

	// Above the holds: a held mex on an empty energy bank is exactly the walk
	// they exist to protect, and protecting it freezes the builder at the site.
	@t = EnergyBeforeMex(unit);
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
	double tp = Perf::T0();
	@t = HoldWorkInProgress(unit, isComm);
	Perf::Add("mt.hold", tp);
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

	// The air plant the intel curve already wants -- mandatory-income lab, the
	// advanced plant, the enemy-afloat reaction. Same slot and bounds as the
	// rule above: PlantApproved's ledger is what keeps it one-at-a-time.
	@t = WantedAirPlant(unit);
	if (t !is null)
		return t;

	// A bare extractor outranks expansion, at any tier and for any builder: one
	// cheap turret per mex, asked once each. It cannot run away -- an extractor
	// with cover or a pending order is skipped -- and a raided mex costs more than
	// the turret every time.
	@t = CommanderMexGuard(unit, isComm);
	if (t !is null)
		return t;
	tp = Perf::T0();
	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
	Perf::Add("mt.default", tp);
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

	// A FACTORY OFFER IS NEVER OPTIONAL. Every eco rule below (EcoFusion,
	// converters, Brain wants) early-returns before the engine offer is
	// accepted, so an approved plant's task sat in the pool while the adv cons
	// built fusion after fusion -- an armshltx approved at 7.3m was still
	// unbuilt at 32m with zero T3 fielded against 54k (watched 2026-08-16).
	// Not for the commander: its walk-hold and safety rules below must keep
	// the final say on what it accepts.
	if (!isComm && (task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == Task::BuildType::FACTORY))
	{
		return task;
	}

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
	tp = Perf::T0();
	@t = Brain::Decide(unit, isAdvCon);
	Perf::Add("mt.brain", tp);
	if (t !is null)
		return t;
	// Deferred, not declined: stop here so the unit is not handed lower-ranked
	// optional work it would never have taken had Decide run this frame.
	if (Brain::gDecideDeferred)
		return null;

	tp = Perf::T0();
	@t = OptionalWork(unit, isComm);
	Perf::Add("mt.optional", tp);
	if (t !is null)
		return t;

	@task = VetoCommanderReclaim(unit, isComm, task);
	@task = VetoCommanderHold(unit, isComm, task);
	@task = VetoCrisisAssist(task);

	bool taken = false;
	@task = ScreenOffer(unit, isComm, task, taken);
	if (taken)
		return task;

	tp = Perf::T0();
	@t = ScavengeWrecks(unit, isComm, isAdvCon);
	Perf::Add("mt.scavenge", tp);
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
	tp = Perf::T0();
	@t = Assist::Fallback(unit, isComm);
	Perf::Add("mt.fallback", tp);
	return t;
}

}  // namespace Builder
