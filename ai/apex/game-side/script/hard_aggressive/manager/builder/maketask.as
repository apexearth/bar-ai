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
int gNextEcoYieldLog = 0;

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
	const int capN = int(ai.GetTunable("apex_idle_backoff_maxmult", TUNE_IDLE_BACKOFF_MAXMULT));
	if (strikes > capN)
		strikes = capN;
	gIdleBackStrikes[s] = strikes;
	gIdleBackUntil[s] = ai.frame
			+ strikes * int(ai.GetTunable("apex_idle_backoff", TUNE_IDLE_BACKOFF) * float(SECOND));
}

int gElectFrame = -1;
double gElectUs = 0.0;
// Builder id -> next frame its guard may be fully re-elected. GUARD is the one
// build type Reevaluate re-elects every update even in range, so without this
// hold every shadowing builder walked the whole ladder every update.
dictionary gGuardHold;
int gNextEnergyAheadLog = 0;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	const bool isCommander = (unit !is null)
			&& unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	if (!isCommander && (unit !is null) && IdleBackoffHolds(unit))
		return null;
	// SQUAD HOLD: a builder shadowing a lead keeps its guard between periodic
	// full re-elections instead of re-running the ladder every update. The
	// re-election period is what lets it still leave for real work.
	if (!isCommander && (unit !is null)) {
		IUnitTask@ held = unit.task;
		if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::GUARD)) {
			const string k = "" + int(unit.id);
			int next = 0;
			gGuardHold.get(k, next);
			if (ai.frame < next) {
				Perf::Note("mt.guardhold");
				return held;
			}
			gGuardHold.set(k, ai.frame
					+ int(ai.GetTunable("apex_guard_reelect", TUNE_GUARD_REELECT) * float(SECOND)));
		}
	}
	Brain::gDecideDeferred = false;
	// A TIME budget, never a count: the count budgets (2/frame, halved and
	// frame-staggered when rich) rationed builder ACTIVITY to protect frame
	// time, and stacked with the other throttles the builders visibly did
	// nothing (apexearth, live 2026-08-18: "by far the largest issue in the
	// game"). Elections now run freely until this frame has genuinely spent
	// its election milliseconds; only then do the rest defer to the next
	// frame. Cheap frames serve every builder; only an expensive frame
	// rations, and only by what it measured, not by a guess.
	// Commanders are never deferred.
	if (!isCommander && (unit !is null)) {
		if (gElectFrame != ai.frame) {
			gElectFrame = ai.frame;
			gElectUs = 0.0;
		}
		if (gElectUs > ai.GetTunable("apex_elect_ms", TUNE_ELECT_MS) * 1000.f) {
			Brain::gDecideDeferred = true;   // reuse: skips NoteIdleElection
			Perf::Note("mt.elect.defer");
			return null;
		}
	}
	const double electT0 = ai.ClockUs();
	IUnitTask@ task = DefenceShareScreen(unit, isCommander, MakeTaskInner(unit));
	if (!isCommander)
		gElectUs += ai.ClockUs() - electT0;
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
	@t = RezzerMedic(unit);
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
		// Obsolete-building reclaims are enqueued centrally by ObsoleteSweep
		// and reach an idle rez bot through DefaultMakeTask above.
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

	// DEDICATED CREWS work their own domain before the shared ladder can
	// claim them; an empty domain falls through rather than idling. See
	// crewdedicated.as for the ladders and crew.as for the ratio that
	// opens the slots.
	if (!isComm) {
		const int crewRole = Crew::RoleOf(unit);
		if (crewRole == int(Crew::ENERGY)) {
			@t = EnergyCrewTask(unit);
			if (t !is null)
				return t;
		} else if (crewRole == int(Crew::METAL)) {
			@t = MetalCrewTask(unit);
			if (t !is null)
				return t;
		}
	}

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
	// A THREATENED bare mex outranks the next claim: the guard's ordinary
	// slot is below expansion, which walked the commander away from radar
	// contacts standing over his fresh extractor. Urgent pass fires only
	// with an enemy visible near the bare mex.
	@t = CommanderMexGuard(unit, isComm, true);
	if (t !is null)
		return t;
	// The mex just built gets its sentry before the builder leaves it: the
	// near-only pass costs no walk at all, where the ordinary slot below
	// expansion left the opening mexes bare until ~6 minutes (watched on
	// Altair Crossing -- "no sentry to defend his initial 3 mexes").
	@t = CommanderMexGuard(unit, isComm, false, true);
	if (t !is null)
		return t;
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

	// The T3 gantry, sited by us with a widening search -- the engine's own
	// siting fails silently on its footprint in a full base core.
	@t = GantryAtRear(unit);
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
	// A big frame short of its cost-scaled worker floor pulls this builder
	// before expansion can -- a placed reactor or gantry is dead metal until
	// it finishes. Not for the commander: its own rules keep the final say.
	if (!isComm) {
		@t = BigBuildAssist(unit);
		if (t !is null)
			return t;
	}
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

	// A MEX SOMEONE IS ALREADY BUILDING IS NEVER WORTH A WALK. The engine's
	// MakeBuilderTask hands its queue to any re-electing builder, and a con
	// out claiming distant mexes gets pulled all the way home to help finish
	// a 50-metal extractor already under a lathe (apexearth 2026-08-21:
	// "cons which are out trying to find mexes far away from home will choose
	// to walk all the way home"). If this con has an open spot of its own no
	// farther than the offered walk, it claims that instead; the offered task
	// stays in the pool for whoever is actually near it.
	if (!isComm && (task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == Task::BuildType::MEX)
		&& (Requests::Workers(task) > 0))
	{
		const AIFloat3 offerAt = task.GetBuildPos();
		const AIFloat3 me = unit.GetPos(ai.frame);
		if (OnMap(offerAt)) {
			const int nearSpot = aiEconomyMgr.FindOpenMexSpot(unit, me);
			if (nearSpot >= 0) {
				const AIFloat3 mine = aiEconomyMgr.GetMexSpotPos(nearSpot);
				if (OnMap(mine) && (me.distance2D(mine) < me.distance2D(offerAt))) {
					float heat = ThreatFor(unit, mine);
					heat = MexHeat(mine, heat);
					if (heat <= CON_THREAT_VETO) {
						IUnitTask@ digNear = aiEconomyMgr.EnqueueMexAt(unit, nearSpot);
						if (digNear !is null) {
							AiLog(Factory::T() + "apex: manned-mex join refused -- "
								+ "own open spot is closer than the walk");
							return digNear;
						}
					}
				}
			}
		}
	}

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
	// BUILD POWER ON THE LINE OUTRANKS THE ECONOMY LANES.
	//
	// Above mexup/reactor/converter/energy on purpose: those lanes claim every
	// constructor we own, which is why the idle-assist fallback below almost
	// never fires and why 41 m/s of income sat unspent while army ran at 12-15%
	// of our metal against BARb's 22-34%. Bounded by Assist::LineWantsHelp
	// (spare income only) and an economy-scaled stack, so a line that is already
	// fast enough, or an economy with nothing spare, releases the builder back
	// to the lanes below.
	@t = Assist::AssistFactory(unit, isComm, isAdvCon);
	if (t !is null)
		return t;

	// A VISIBLE PUSH OUTRANKS THE ECONOMY LANES: the tower only beats the walk
	// if it starts now. Gated on Military::PushIncoming, so it is idle in
	// every quiet game.
	if (Military::PushIncoming()) {
		@t = PushAnswer(unit);
		if (t !is null)
			return t;
	}
	// THE ECONOMY LANES YIELD ONCE ECONOMY IS OVER ITS SHARE.
	//
	// Every lane below returns before Brain::Decide, so the budget RANKED
	// spending it never BOUNDED -- which is why a 0.49 army target coexisted
	// with 0.24 actual army spend and eco ran at 0.46 against 0.22 (measured
	// 32m 4v4, 2026-08-19). Raising the army weight alone cannot fix that; the
	// weight has to be able to bind.
	//
	// A builder released here is not idle: it falls through to the factory
	// assist and the engine's own offer, which is where army production and
	// expansion live. The lanes resume the moment eco drops back under target.
	const bool ecoOverrun = (Brain::gSpentTotal > 1.f)
			&& (Brain::ShareOf(Brain::ECONOMY)
				> Brain::TargetShare(Brain::ECONOMY)
					* ai.GetTunable("apex_eco_overrun", TUNE_ECO_OVERRUN));
	if (ecoOverrun && (ai.frame >= gNextEcoYieldLog)) {
		gNextEcoYieldLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: eco lanes yield -- share "
			+ formatFloat(Brain::ShareOf(Brain::ECONOMY), "", 0, 2)
			+ " over target "
			+ formatFloat(Brain::TargetShare(Brain::ECONOMY), "", 0, 2)
			+ ", army at " + formatFloat(Brain::ShareOf(Brain::ARMY), "", 0, 2)
			+ "/" + formatFloat(Brain::TargetShare(Brain::ARMY), "", 0, 2));
	}

	// HOME MEXES FIRST, WITH EVERY ADVANCED CON. While un-upgraded extractors
	// stand in the home patch, one-at-a-time is the wrong bound: a second adv
	// con used to fall through to the fusion lane here. Until the home patch is
	// fully upgraded (or metal is full and the upgrade buys nothing), each adv
	// con takes its own upgrade -- concurrent MEXUP tasks up to the number of
	// mexes left, and the reactor lane below waits its turn.
	const uint homeLeft = Builder::HomeMexOutstanding();
	const bool homeRush = isAdvCon && (homeLeft > 0) && !aiEconomyMgr.isMetalFull;
	if (isAdvCon) {
		const int upTasks = aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::MEXUP));
		// The orphan guard: never re-enqueue for a builder already on an
		// upgrade -- Reevaluate calls this every update, and each extra enqueue
		// after the first is a task nobody will ever work.
		const bool onUpgrade = (SiteBuildName(unit.task) == "mexup");
		if (!onUpgrade
			&& ((upTasks == 0) || (homeRush && (upTasks < int(homeLeft)))))
		{
			Brain::Want@ up = Brain::MexUpgradeWant(unit);
			if ((up !is null) && (up.def !is null)
				&& unit.circuitDef.CanBuild(up.def))
			{
				IUnitTask@ upt = aiBuilderMgr.EnqueueMexUp(up.pos, up.def);
				if (upt !is null) {
					AiLog(Factory::T() + "apex: mexup pipeline by "
						+ unit.circuitDef.GetName()
						+ (homeRush ? (" (home rush, " + homeLeft + " left)") : ""));
					return upt;
				}
			}
		}
	}
	if (isAdvCon && !ecoOverrun && !homeRush && ReactorPipelineOpen()) {
		@t = EcoFusion(unit);
		if (t !is null)
			return t;
	}
	if (isAdvCon && !ecoOverrun) {
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

	// ALWAYS BE BUILDING ENERGY -- ahead of need, not behind it. The energy
	// want only RANKED against everything else, so generators were bought
	// reactively and the T2 transition's sudden drain (adv cons, mohos, the
	// lab itself) hit an economy sized to yesterday -- apexearth 2026-08-19:
	// "we aren't building energy which we're going to need, we only satisfy
	// current needs." One ENERGY build stays permanently under way while
	// income is below the FORECAST: current pull with headroom, and before
	// T2 a floor for the cliff that is coming. Bounded to one task in
	// flight, so it claims one builder, not the economy.
	// ONE AT A TIME COULD NOT CLIMB FAST ENOUGH. A single generator in flight
	// walks a ~100 e/s economy toward the pre-T2 forecast slower than the T2
	// transition arrives, so the buffer was never there when the drain hit
	// (apexearth: "we still aren't buffering enough energy for T2", after an
	// e-stall). Concurrency is the reactor rule reused -- how many times income
	// plus the bank covers this generator inside the same affordability window
	// -- so a poor economy still serialises and a rich one does not.
	// THE ECO LANES BYPASS THE ARBITER, AND THAT IS WHY THE ARMY IS SMALL.
	//
	// Every rule above returns before Brain::Decide, so the budget only ever
	// RANKED spending it never actually bounded. Measured 2026-08-19, 32m 4v4:
	// eco took 0.46 of spend against a 0.22 target while ARMY took 0.24 against
	// a 0.49 target, and army was 14.7% of our metal against BARb's 34.2%. The
	// metal was there -- 64,223 produced, 48,993 built -- we simply never chose
	// units with it. apexearth: "what use is twice their economy if we have 1/5th
	// the army?"
	//
	// A constructor refused here falls through to the assist fallback, which
	// guards a factory -- so the freed build power becomes production speed
	// rather than another generator.
	if (Brain::ShareOf(Brain::ECONOMY)
		> Brain::TargetShare(Brain::ECONOMY)
			* ai.GetTunable("apex_eco_overrun", TUNE_ECO_OVERRUN))
	{
		if (ai.frame >= gNextEnergyAheadLog) {
			gNextEnergyAheadLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: energy lane yields -- eco share "
				+ formatFloat(Brain::ShareOf(Brain::ECONOMY), "", 0, 2)
				+ " over target "
				+ formatFloat(Brain::TargetShare(Brain::ECONOMY), "", 0, 2));
		}
	} else {
	// THE TARGET SCALES WITH THE METAL ECONOMY, NOT WITH CURRENT DEMAND.
	// energy.pull measures THROTTLED demand: factories and lathes slow down
	// on a short grid, which lowers pull, which told this lane the grid was
	// fine exactly while it starved -- the circular read behind every "we
	// still SUCK with energy" session (apexearth 2026-08-21: "Prioritize it
	// more. This whole fallback makes energy the last resort... It's not
	// enough"). Metal income is the un-throttled measure of what the base
	// wants to spend, and converters make surplus fungible, so the grid
	// target follows it (Policy::EPerMetal).
	float needE = aiEconomyMgr.energy.pull * Policy::EnergyHeadroom();
	{
		const float fromMetal = aiEconomyMgr.metal.income * Policy::EPerMetal();
		if (needE < fromMetal)
			needE = fromMetal;
	}
	if (!Factory::gHaveT2
		&& (aiEconomyMgr.metal.income >= Policy::T2EnergyFrom()))
	{
		const float floorE = Policy::T2Energy();
		if (needE < floorE)
			needE = floorE;
	}
	// THE DEFICIT SIZES THE PIPELINE. One-energy-task-at-a-time was the real
	// throttle: while one solar built, every other asker skipped this lane. A
	// deep hole now opens one standing task per missing rung of the cheapest
	// generator (the duplicate governor still bank-bounds parallel sites of
	// one def, and serial advsolars stay serial).
	int eTasks = ecoOverrun ? 0 : 1;
	{
		CCircuitDef@ gen = SolarDef();
		if (gen !is null) {
			eTasks = ReactorsInFlight(gen.costM);
			const float make = aiEconomyMgr.GetEnergyMake(gen);
			const float hole = needE - aiEconomyMgr.energy.income;
			if ((make > 0.f) && (hole > 0.f)) {
				const int rungs = 1 + int(hole / make);
				if (rungs > eTasks)
					eTasks = rungs;
			}
		}
	}
	if (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::ENERGY)) < uint(eTasks)) {
		// A FULL STORE FALSIFIES THE FORECAST. `energy.pull` includes what our
		// own builders are drawing to build the generators, so the rule fed
		// itself: more energy under construction raised the pull, which raised
		// the forecast, which justified more. Measured over 6x 4v4
		// (tournaments/20260819-201232): forecasts of 2481 and 3442 e/s at 1834
		// income, coradvsol 35% of ALL metal spent, and 18,484 energy WASTED
		// against BARb's 4,086 -- while mex upgrades ran 1 against their 4.
		// Waste is the falsifier: if the store is full we do not need more,
		// whatever the pull says.
		if (aiEconomyMgr.energy.income < needE && !aiEconomyMgr.isEnergyFull) {
			IUnitTask@ et = HomeEnergy(unit);
			if (et !is null) {
				if (ai.frame >= gNextEnergyAheadLog) {
					gNextEnergyAheadLog = ai.frame + 30 * SECOND;
					AiLog(Factory::T() + "apex: energy pipeline -- eInc "
						+ formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
						+ " below forecast "
						+ formatFloat(needE, "", 0, 0));
				}
				return et;
			}
		}
	}
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

	// Below the Brain so a ranked mex upgrade still wins; above everything
	// optional and the engine offer, because when nothing eco is in flight
	// eco IS the best choice (apexearth's always-expand rule; see AlwaysEco).
	tp = Perf::T0();
	@t = AlwaysEco(unit);
	Perf::Add("mt.alwayseco", tp);
	if (t !is null)
		return t;

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

	// ENERGY STORAGE IS ALMOST NEVER THE RIGHT BUY. apexearth 2026-08-21:
	// "We keep making energy storage too... we really really don't need those
	// unless we're trying to shoot something like a starfall. Deprioritize a
	// lot." The engine's own economy logic offers storage whenever capacity
	// trails income; refuse the ENERGY-storage offers outright (metal storage
	// untouched) unless the tunable re-opens them for a superweapon game.
	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == int(Task::BuildType::STORE))
		&& (ai.GetTunable("apex_estor", TUNE_ESTOR) <= 0.f)
		&& (task.buildDef !is null))
	{
		const string sn = task.buildDef.GetName();
		if ((sn.findFirst("estor") >= 0) || (sn.findFirst("adves") >= 0))
			@task = null;
	}

	// A MEX ACROSS THE MAP IS THE WRONG MEX. apexearth, watching Prismatic
	// 2026-08-21: "Just watched a con walk from one corner of the map to the
	// next corner, passing by 6 mexes as they walked, not building any" -- and
	// the walk cannot self-correct: Reevaluate only reassigns on a DIFFERENT
	// build type, so ChainNearbyMex proposing a nearer mex mid-walk is ignored
	// for the whole trip. The only working moment is election, here: when the
	// offer is a mex far away and an open spot sits much nearer, take the near
	// one. The far spot goes back in the pool for whoever is actually close.
	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == int(Task::BuildType::MEX)))
	{
		const AIFloat3 mine = unit.GetPos(ai.frame);
		const float offerD = task.GetBuildPos().distance2D(mine);
		if (offerD > ai.GetTunable("apex_mex_walk_cap", TUNE_MEX_WALK_CAP)) {
			const int near = aiEconomyMgr.FindOpenMexSpot(unit, mine);
			if (near >= 0) {
				const AIFloat3 np = aiEconomyMgr.GetMexSpotPos(near);
				if (OnMap(np) && (np.distance2D(mine) < offerD * 0.5f)) {
					IUnitTask@ nt = aiEconomyMgr.EnqueueMexAt(unit, near);
					if (nt !is null)
						return nt;
				}
			}
		}
	}

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
	if (t !is null)
		return t;
	// BELOW even that: a standing patrol, the same trick the nano turrets got.
	// A patrolling builder auto-assists/repairs/reclaims whatever it passes and
	// an air constructor drifts back over the base and finds work -- watched
	// live 2026-08-18: advanced con aircraft hovering idle 5+ minutes beside a
	// finished nuke silo, plus idle rezbots and cons. Engine-side behaviour, no
	// task consumed: the next election can still take the unit the moment real
	// work exists.
	IdlePatrol(unit, isComm);
	return null;
}

// Unit id -> next frame its idle patrol may be re-issued.
dictionary gIdlePatrolNext;

// CONSTRUCTOR CENSUS: apexearth sees cons standing idle that every idle net
// misses -- which means they hold tasks they cannot execute. Every 30s, one
// line per player: builders by task type, and how many have not MOVED since
// the last sample split by whether they hold a build task. `still-build`
// high = stuck build tasks (unreachable sites); `still-other` high = stuck
// guards/retreats. Diagnosis first; the fix follows the census.
dictionary gCensusPos;
int gNextCensus = 0;

void ConCensus()
{
	if (ai.frame < gNextCensus)
		return;
	gNextCensus = ai.frame + 30 * SECOND;
	int nBuild = 0, nIdle = 0, nWait = 0, nRetreat = 0, nOther = 0;
	int stillBuild = 0, stillOther = 0;
	const uint n = Crew::gId.length();
	for (uint i = 0; i < n; ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Crew::gId[i]));
		if (c is null)
			continue;
		IUnitTask@ t = c.task;
		const int tt = (t is null) ? -1 : int(t.GetType());
		bool isBuild = false;
		if (tt == int(Task::Type::BUILDER)) { ++nBuild; isBuild = true; }
		else if ((tt == int(Task::Type::IDLE)) || (tt == int(Task::Type::NIL))) ++nIdle;
		else if (tt == int(Task::Type::WAIT)) ++nWait;
		else if (tt == int(Task::Type::RETREAT)) ++nRetreat;
		else ++nOther;
		const AIFloat3 at = c.GetPos(ai.frame);
		const string k = "" + Crew::gId[i];
		string prev;
		const string cur = int(at.x) + ":" + int(at.z);
		if (gCensusPos.get(k, prev) && (prev == cur)) {
			if (isBuild) ++stillBuild; else ++stillOther;
		}
		gCensusPos.set(k, cur);
	}
	if (n > 0) {
		AiLog(Factory::T() + "apex: con census n=" + n + " build=" + nBuild
			+ " idle=" + nIdle + " wait=" + nWait + " retreat=" + nRetreat
			+ " other=" + nOther + " still-build=" + stillBuild
			+ " still-other=" + stillOther);
	}
}

void IdlePatrol(CCircuitUnit@ unit, bool isComm)
{
	if ((unit is null) || isComm || !unit.circuitDef.IsMobile())
		return;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return;
	const string k = "" + int(unit.id);
	int next = 0;
	gIdlePatrolNext.get(k, next);
	if (ai.frame < next)
		return;
	gIdlePatrolNext.set(k, ai.frame
			+ int(ai.GetTunable("apex_idle_patrol_period", TUNE_IDLE_PATROL_PERIOD) * float(SECOND)));
	// Toward home, so the patrol leg crosses the base's work rather than empty
	// ground; a unit already at home gets a short local leg.
	AIFloat3 to = gHomePos;
	if (here.distance2D(gHomePos) < 300.f) {
		to = here;
		to.x += 400.f;
	}
	if (!OnMap(to))
		return;
	unit.CmdPatrolTo(to);
	Perf::Note("mt.idlepatrol");
}

}  // namespace Builder
