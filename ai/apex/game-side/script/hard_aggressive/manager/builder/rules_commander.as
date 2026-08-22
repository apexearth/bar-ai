namespace Builder {

// Everything AiMakeTask does differently for the commander: its own safety
// rules before work is chosen, and its own vetoes over what work is offered.

// A null return from AiMakeTask IS commander idle time -- the engine has
// nothing to give the unit and waits for the next Reevaluate. Three of this
// file's rules can produce one by refusing an offer without a replacement;
// the counters below attribute which.
int gCommOffers = 0;        // times DefaultMakeTask was asked for a commander
int gCommOfferNull = 0;     //   ... and the engine itself had nothing
int gCommVetoReclaim = 0;   // reclaim refused in favour of a mex spot
int gCommVetoHold = 0;      // new job refused to keep the current one
int gCommEndNull = 0;       // reached the end of the pipeline with nothing
int gCommIdleJobs = 0;      // last-resort jobs CommanderIdleWork supplied
int gCommRetreatHp = 0;     // returned a retreat because health was low
int gCommGuard = 0;         // returned a mex guard
int gCommIdleUnsafe = 0;    // CommanderIdleWork refused: standing in threat
int gCommIdleNoJob = 0;     //   ... refused: mex, assist and energy all declined
int gMexSentries = 0;       // guard turrets placed on bare extractors
// Consecutive AiUpdates the commander has held a build task with no engine
// order, before treating it as stuck. Set above the measured order-application
// lag (CLAUDE.md: up to 45 AiUpdates at the benchmark's default speed cap) with
// margin, so this does not abort an order still in flight to the engine.
const int COMM_STUCK_TICKS = 60;
int gCommStuck = 0;
int gCommUnstuck = 0;
// Same shape, for the noTask bucket: consecutive AiUpdates the commander has
// sampled with literally no task (t is null/IDLE/NIL) while under influence
// high enough that CommanderTask's flee check would fire. Kept short --
// unlike a BUILDER task's order-application lag, this measures the gap
// before the engine's own idle callback re-invokes AiMakeTask at all, which
// should be near-immediate, not tens of seconds.
const int COMM_NOTASK_TICKS = 3;
int gCommNoTaskStreak = 0;
int gCommForced = 0;
// Consecutive AiUpdates the commander has HELD a retreat task. CRetreatTask
// only ends at >98% health, or (for a commander) zero enemy influence at its
// own tile -- neither is guaranteed to ever arrive while enemies loiter near
// home, and a unit holding a task is never offered to AiMakeTask again, so a
// pinned retreat is an absorbing state. Past this, the task is aborted and
// the commander re-elected through the full pipeline.
const int COMM_RETREAT_TICKS = 30;
int gCommRetreatStreak = 0;
int gCommRetreatCut = 0;
int gNextCommDiag = 0;
int gNextCommDeadman = 0;   // events.as: task-independent flee throttle
int gCommHotSince = 0;      // events.as: anti-stall clock on hot ground
int gNextCommStallFix = 0;  // events.as: panic-solar-mid-build throttle
int gCommStallSince = -1;   // events.as: persistent-stall clock
AIFloat3 gCommHotAnchor;    // events.as: where the clock was last reset
IUnitTask@ gCommLastLogged = null;  // see maketask.as's catch-all accept log

// The dev gadget's commIdle counts an EMPTY ENGINE COMMAND QUEUE, which is a
// symptom, not a cause. These four buckets are mutually exclusive and cover
// the space, sampled once per AiUpdate over our own commander:
//
//   noTask   -- no task at all. The pipeline declined; that is our bug.
//   waiting  -- holds a BUILDER task but no engine order. Almost always an
//               unfinished path query: IBuilderTask::UpdatePath returns without
//               issuing anything while one is outstanding, and the answer comes
//               back off a worker thread.
//   ordered  -- holds a task AND an engine order. Working. Not idle.
//   other    -- any other task type (retreat, wait, combat).
//
// Sample counts, so they are read against each other and against commSamp.
int gCDNoTask = 0;
int gCDWaiting = 0;
int gCDOrdered = 0;
int gCDOther = 0;
int gCDSamples = 0;

// The sampler itself lives in builder/events.as, which is where gComm is
// declared -- this shim's include order puts events.as last, and a global read
// before its declaration is a compile error that disables the whole variant.

void CommDiag()
{
	if (ai.frame < gNextCommDiag)
		return;
	gNextCommDiag = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: comm-why samples=" + gCDSamples
		+ " noTask=" + gCDNoTask + " waiting=" + gCDWaiting
		+ " ordered=" + gCDOrdered + " other=" + gCDOther
		+ " unstuck=" + gCommUnstuck + " forced=" + gCommForced
		+ " retreatCut=" + gCommRetreatCut);
	AiLog(Factory::T() + "apex: comm-diag offers=" + gCommOffers
		+ " offerNull=" + gCommOfferNull
		+ " vetoReclaim=" + gCommVetoReclaim
		+ " vetoHold=" + gCommVetoHold
		+ " endNull=" + gCommEndNull
		+ " idleJobs=" + gCommIdleJobs
		+ " retreatHp=" + gCommRetreatHp + " guard=" + gCommGuard
		+ " idleUnsafe=" + gCommIdleUnsafe + " idleNoJob=" + gCommIdleNoJob);
}

// With apex_comm_rules=0 every commander-specific rule in this file no-ops and
// the commander is whatever CBuilderManager makes of it, isolating our idle
// time from the engine's for an A/B.
bool CommRules()
{
	return ai.GetTunable("apex_comm_rules", TUNE_COMM_RULES) > 0.f;
}

// HOW BRAVE THE COMMANDER MAY BE, read off what is fielded against him.
// apexearth 2026-08-21: "Our commander is too brave when lots of T2 and T3
// are on the field. He should run but he doesn't." The stake is his own
// cost, so the bars scale with the game rather than a fixed number: fielded
// HEAVY/SUPER mass at half his value can already snipe him from full
// health, and once enemy T2 is out, an enemy mobile mass at twice his value
// means the map is no place for him regardless of tech mix.
bool CommCaution(CCircuitUnit@ unit)
{
	const float mine = unit.circuitDef.costM;
	if (mine <= 0.f)
		return false;
	const float heavies = aiEnemyMgr.GetEnemyCost(RT::HEAVY)
			+ aiEnemyMgr.GetEnemyCost(RT::SUPER);
	if (heavies >= mine * ai.GetTunable("apex_comm_heavy_frac", TUNE_COMM_HEAVY_FRAC))
		return true;
	return Factory::gEnemyT2Seen
		&& (Military::FoeMobileMassing()
			>= mine * ai.GetTunable("apex_comm_mass_mult", TUNE_COMM_MASS_MULT));
}

// Influence at the position and at four compass points around it: a cautious
// commander reacts to danger APPROACHING, not danger already on his tile --
// the tile sample is exactly the clean-until-dead trap, one ring out.
float RingInflMax(const AIFloat3& in pos, float r)
{
	float best = ai.GetEnemyInflAt(pos);
	for (int i = 0; i < 4; ++i) {
		AIFloat3 p = pos;
		if (i == 0)      p.x += r;
		else if (i == 1) p.x -= r;
		else if (i == 2) p.z += r;
		else             p.z -= r;
		if (!OnMap(p))
			continue;
		const float v = ai.GetEnemyInflAt(p);
		if (v > best)
			best = v;
	}
	return best;
}

int gNextCommCautionLog = 0;

IUnitTask@ CommanderTask(CCircuitUnit@ unit, bool isComm)
{
	if (isComm && CommRules()) {
		LogCommanderThreat(unit);
		// A CAUTIOUS COMMANDER DOES NOT WORK FORWARD AT ALL. Zero influence
		// needed: standing on forward ground while heavies roam is the
		// mistake, not the contact that follows it. Home ground stays
		// workable; the flee below covers danger that comes to him there.
		if (CommCaution(unit)
			&& (Military::ForwardFraction(unit.GetPos(ai.frame))
				> ai.GetTunable("apex_comm_fwd_cap", TUNE_COMM_FWD_CAP)))
		{
			if (ai.frame >= gNextCommCautionLog) {
				gNextCommCautionLog = ai.frame + 15 * SECOND;
				AiLog(Factory::T() + "apex: commander running -- heavies fielded, "
					+ "fwd=" + formatFloat(Military::ForwardFraction(unit.GetPos(ai.frame)), "", 0, 2));
			}
			IUnitTask@ run = Retreat(unit);
			if (run !is null)
				return run;
		}
		// A health trigger fires once, after damage already lands, and an army
		// that arrives in force kills a commander from full health before that
		// ever fires. Uses the INFLUENCE map, not ai.GetBuilderThreatAt: threat
		// reads clean at the victim's own tile when the killer is at range;
		// influence is not fooled by that.
		//
		// Was DEFAULT OFF pending a measured threshold. Turned on 2026-08-14
		// after a watched match's own commander sampled threat=0.00 hp=100 at
		// frame 26745 and was destroyed 930 frames later with no sample in
		// between -- the exact clean-until-dead failure this exists to catch.
		// The threshold reuses BaseUnderAttack's own calibration (converter.as),
		// which already treats ANY nonzero GetEnemyInflAt at a fixed point as
		// "attacked" -- this asks the same question at the commander's own tile.
		// apexearth 2026-08-14: the commander is a strong early-game unit and
		// should stay active then; only later game does it need to play safe.
		// Factory::gHaveT2 is this codebase's established early/late split
		// (see CLAUDE.md "Progression is economy, not time"), so gate the
		// any-influence instant flee to post-T2 -- it still catches the
		// clean-until-dead late-game snipe this was added for, without
		// yanking the commander off a lone early scout.
		// Caution also arms the flee pre-T2 and widens its senses: the ring
		// sample sees an approach one step out instead of waiting for the
		// commander's own tile to go hot.
		const bool caution = CommCaution(unit);
		const float fleeInfl = (Factory::gHaveT2 || caution)
				? ai.GetTunable("apex_comm_flee_influence", TUNE_COMM_FLEE_INFLUENCE) : 0.f;
		if (fleeInfl > 0.f) {
			const float hereInfl = caution
					? RingInflMax(unit.GetPos(ai.frame),
						ai.GetTunable("apex_comm_flee_ring", TUNE_COMM_FLEE_RING))
					: ai.GetEnemyInflAt(unit.GetPos(ai.frame));
			// A retreat only helps when the ground fled TO is safer than the
			// ground fled FROM. When home is just as hot, standing at the haven
			// "retreating" defends nothing -- fall through and keep working;
			// every build rule's own site-safety veto steers the work off hot
			// ground anyway.
			if ((hereInfl > fleeInfl)
				&& (ai.GetEnemyInflAt(gHomePos) < hereInfl * 0.5f))
			{
				// NEVER flee into the pack: retreats converge on the same last
				// haven, and a commander death explosion chains at pack range --
				// four commanders died in ONE frame at ~280-elmo spacing (match
				// 20260815-154651). With an ally commander already inside
				// spacing, flee AWAY from it: a solar build at the pushed-out
				// spot is a destination the task system can actually walk to,
				// same shape as the back-wall branch below.
				AIFloat3 packed;
				if (AllyCommNear(packed)) {
					AIFloat3 away = unit.GetPos(ai.frame) - packed;
					if (away.SqLength2D() >= 1.f) {
						away.SafeNormalize2D();
						const AIFloat3 spread = unit.GetPos(ai.frame)
								+ away * ai.GetTunable("apex_comm_spacing", TUNE_COMM_SPACING);
						CCircuitDef@ safeDef = SolarDef();   // never a panel late-game
						if (OnMap(spread) && (safeDef !is null)
							&& safeDef.IsAvailable(ai.frame)
							&& unit.circuitDef.CanBuild(safeDef))
						{
							IUnitTask@ apart = Requests::Take(unit, safeDef,
									Task::BuildType::ENERGY, Task::Priority::NORMAL,
									spread, 0.f, SQUARE_SIZE * 8);
							if (apart !is null) {
								if (ai.frame >= gNextCommFleeLog) {
									gNextCommFleeLog = ai.frame + 15 * SECOND;
									AiLog(Factory::T() + "apex: commander spreading "
										+ "from the pack instead of fleeing into it");
								}
								return apart;
							}
						}
					}
				}
				if (ai.frame >= gNextCommFleeLog) {
					gNextCommFleeLog = ai.frame + 15 * SECOND;
					AiLog(Factory::T() + "apex: commander leaving, enemy influence "
						+ formatFloat(hereInfl, "", 0, 2) + " > " + formatFloat(fleeInfl, "", 0, 2));
				}
				IUnitTask@ bail = Retreat(unit);
				if (bail !is null)
					return bail;
			}
		}
		// The commander guards the mexes it just made: MexGuard picks the
		// NEAREST undefended mex within MEX_GUARD_REACH, which for a commander
		// that has just finished one is the mex under its feet.
		if (unit.GetHealthPercent() >= COM_RETREAT_HEALTH) {
			// Above MexGuard: the base is worth more than the extractor the
			// commander happens to be standing next to, and this asks once.
			IUnitTask@ home = HomeTower(unit, isComm);
			if (home !is null)
				return home;
			// HomeTower only ever builds a MISSING tower -- an existing one taking
			// damage (the commander standing right next to it) is left alone by
			// every other rule here too. RepairStructureNearby is the one path that
			// reaches it: the engine's own repair task for it exists (buildingDamaged
			// Handler) but native ranking never offers it to a commander at all
			// (RepairTask.cpp's CanAssignTo excludes IsRoleComm unconditionally) --
			// see that function's own comment.
			IUnitTask@ homeRepair = RepairStructureNearby(unit);
			if (homeRepair !is null)
				return homeRepair;
		}
		const float hp = unit.GetHealthPercent();
		if (hp < COM_RETREAT_HEALTH) {
			// Only keep forcing a flee while genuinely still under local threat;
			// once safe, fall through to DefaultMakeTask's own commander logic
			// (CBuilderManager::MakeCommPeaceTask/MakeCommDangerTask), which
			// already decides hide-vs-assist from local influence, instead of
			// looping a bare retreat forever at low health.
			const float hereThreat = ThreatFor(unit, unit.GetPos(ai.frame));
			if (hereThreat > CON_THREAT_VETO) {
			if (ai.frame >= gNextRetreatLog) {
				gNextRetreatLog = ai.frame + 20 * SECOND;
				AiLog(Factory::T() + "apex: commander retreating at "
					+ formatFloat(hp * 100.f, "", 0, 0) + "% health, frame=" + ai.frame);
			}
			// CRITICAL HEALTH: CRetreatTask walks to the haven, and the haven
			// is the base being overrun -- watched live 2026-08-18, eight
			// re-elections while health fell 81% -> 40% -> dead in place.
			// Below this bar the commander is STEERED instead: a raw move
			// directly away from the enemy centroid, re-issued every election
			// (commanders are exempt from idle backoff), and null so no task
			// walks it back into the blast.
			if (hp < ai.GetTunable("apex_comm_flee_hp", TUNE_COMM_FLEE_HP)) {
				AIFloat3 here = unit.GetPos(ai.frame);
				AIFloat3 away = here - aiEnemyMgr.GetEnemyPos();
				if (away.SqLength2D() > NEAR_ZERO) {
					away.SafeNormalize2D();
					for (int step = 3; step >= 1; --step) {
						AIFloat3 to = here + away * (250.f * float(step));
						if (OnMap(to)) {
							unit.CmdMoveTo(to);
							if (ai.frame >= gNextRetreatLog) {
								gNextRetreatLog = ai.frame + 20 * SECOND;
								AiLog(Factory::T()
									+ "apex: commander CRITICAL -- steered flight");
							}
							return null;
						}
					}
				}
			}
			IUnitTask@ flee = Retreat(unit);
			if (flee !is null) {
				++gCommRetreatHp;
				return flee;
			}
			}
		}
		// The enemy centroid has come to US. PastFront cannot see this: the base
		// centre sits at fraction ~0 on the home->enemy axis, so it always reads
		// safe however many enemies are standing in it.
		//
		// Relocates by giving the commander a job at the RearPos (same one the
		// converter rule uses) rather than a move order: CmdMoveTo correlated
		// with engine aborts (see CLAUDE.md) and is deliberately not called here.
		//
		// LIMITATION: GetEnemyPos is the centroid of ALL enemies, so this catches
		// the massed case, not a single raider elsewhere on a spread-out map.
		if (COMM_BACK_WALL_ON && BaseUnderAttack() && (ai.frame >= gNextCommHide)) {
			// Energy full: just leave. The solar exists only to give the
			// commander somewhere to walk to; building one on a full bank is
			// pure waste.
			if (aiEconomyMgr.isEnergyFull) {
				IUnitTask@ flee = Retreat(unit);
				if (flee !is null) {
					gNextCommHide = ai.frame + COMM_HIDE_PERIOD;
					return flee;
				}
			}
			AIFloat3 back;
			if (RearPos(unit, back)) {
				CCircuitDef@ safe = SolarDef();   // never a panel late-game
				if ((safe !is null) && safe.IsAvailable(ai.frame)
					&& unit.circuitDef.CanBuild(safe)) {
					IUnitTask@ hide = Requests::Take(unit, safe,
							Task::BuildType::ENERGY, Task::Priority::NORMAL,
							back, 0.f, SQUARE_SIZE * 8);
					if (hide !is null) {
						gNextCommHide = ai.frame + COMM_HIDE_PERIOD;
						AiLog(Factory::T() + "apex: commander to the back wall, enemy "
							+ formatFloat(gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()), "", 0, 0)
							+ " from home");
						return hide;
					}
				}
			}
		}
		// Pull the commander off a site that is in enemy ground. Every other
		// builder already gets this a few lines below, behind `if (!isComm)`.
		//
		// Retreat only -- no ContestDefence. A constructor answers danger by
		// building a tower into it; a commander must not stand there doing that.
		// Not CmdMoveTo: see the back-wall note above.
		{
			IUnitTask@ held = unit.task;
			const string kind = SiteBuildName(held);
			if (kind != "") {
				const float heat = ThreatFor(unit, held.GetBuildPos());
				if (heat > CON_THREAT_VETO) {
					LogConVeto(unit, "comm-abandon", kind, heat);
					IUnitTask@ flee = Retreat(unit);
					if (flee !is null)
						return flee;
				}
			}
		}
		// Commander-assists-the-first-T2-mex REMOVED, and it must not be rebuilt
		// this way. TaskB::Common leaves SBuildTask.ref.target null, and
		// CBuilderManager::Enqueue's REPAIR case dereferences it immediately:
		//   auto it = repairUnits.find(ti.ref.target->GetId());
		// so a positional REPAIR is an instant access violation. Only
		// TaskB::Repair(priority, target) is safe, and the script cannot obtain
		// the mex nanoframe -- IUnitTask exposes GetBuildPos() and the assigned
		// builders, never the thing being built.

		// A player with no factory left has no way back. Below every safety
		// check above: a commander actively fleeing or hiding from a real
		// threat must keep doing that, not detour to a build site.
		//
		// Gated on OpeningNeedsEconomy() rather than a fixed elapsed time: a
		// literal clock is wrong for a team wiped down to one constructor,
		// which must re-derive readiness from its own current economy. Once
		// that gate stops holding (income cleared, or its own escape valve
		// released it), there is nothing left to wait for.
		if (!Factory::HaveAnyFactory() && !OpeningNeedsEconomy()) {
			// Safety: reuse the same ThreatFor check the retreat branches
			// above already use. A wiped-out commander standing in the open
			// must keep fleeing, not stop to build.
			const float hereThreat = ThreatFor(unit, unit.GetPos(ai.frame));
			if (hereThreat > CON_THREAT_VETO) {
				IUnitTask@ flee = Retreat(unit);
				if (flee !is null)
					return flee;
			} else {
				// ALREADY WALKING TO OR BUILDING THE FACTORY: hold it, before
				// trying anything else. Without this, every Reevaluate ran the
				// mex/rebuild logic below from scratch off the commander's
				// CURRENT (moving) position, FindOpenMexSpot always found a
				// fresh in-reach spot -- the OpeningMexReach bound stops one
				// jump, not a chain -- and the factory request further down was
				// made once and then abandoned before the commander ever
				// reached the site. See ISSUES.md 2026-08-14, "commander
				// chains nearby mexes forever, factory never requested".
				IUnitTask@ held = unit.task;
				if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
					&& (held.GetBuildType() == Task::BuildType::FACTORY))
					return held;

				// STEP 3 OUTRANKS ANOTHER MEX, once safe and income is judged
				// sufficient (OpeningNeedsEconomy released): request the
				// factory FIRST, and only fall to mex if none is buildable
				// right now. HaveAnyFactory counts FINISHED factories, so
				// while the first lab is still a nanoframe this branch stays
				// true; the task-count check stops a second rebuild request
				// once one is in flight (caught by the held-check above once
				// it is actually assigned to this unit).
				// THE SCORED PICK, not a hard-coded bot lab: this branch fires
				// at every normal game start (no factory exists yet), and the
				// hard-coded T1BotLab here was why the engine's terrain-scored
				// choice -- measured picking the vehicle plant about half the
				// time on Comet -- never decided a single opening. apexearth:
				// "we *always* seem to start with botlabs. We never seem to
				// care about vehicles." ChooseFactory keeps the water/air-map
				// overrides and latches gT1Fac; the bot lab stays the fallback.
				// THE LAB IS PLANNED AT HOME, NOT WHERE THE COMMANDER STANDS.
				// The request used to carry unit.GetPos() -- whatever spot the
				// commander had wandered to when the income gate released, which
				// is how the first lab ended up in the trees at a fourth mex
				// (watched twice, two different maps). Home is where the start
				// mexes are; building there is also what puts the commander
				// next to them for the sentry pass afterwards.
				AIFloat3 labAnchor = unit.GetPos(ai.frame);
				if (gHomeSet)
					labAnchor = gHomePos;
				CCircuitDef@ lab = Factory::ChooseFactory(labAnchor, true, false);
				if ((lab is null)
					|| ((Factory::userData[lab.id].attr
						& (Factory::Attr::T2 | Factory::Attr::T3)) != 0))
					@lab = Factory::T1BotLab();
				// THROUGH THE GATE, not around it: this Take was the fifth
				// bypass -- the request never entered the plant-ask ledger,
				// so during the commander's walk (no nanoframe, no ask) the
				// engine's recovery path read zero T1 plants and got a SECOND
				// lab approved (apexearth: "we're also still making 2 T1
				// labs"). PlantApproved both checks and registers the ask.
				// AN OUTSTANDING FACTORY REQUEST IS THE COMMANDER'S JOB, not a
				// reason to mex: the engine's own ask (approved through the
				// gate) sat unbuilt while this branch -- gated on "no factory
				// task exists" -- walked mexes for 90 seconds until the ask
				// expired (watched live MP + reproduced in the 4v4 smoke:
				// approved 0.4m, on field 2.3m). Joining needs no approval
				// (it creates no new plant); only a genuinely NEW request
				// passes PlantApproved, and a refused new request returns
				// its ask at once.
				if ((lab !is null) && lab.IsAvailable(ai.frame)
					&& (lab.count <= 0))
				{
					const bool outstanding = aiBuilderMgr.GetTaskCountOf(
							int(Task::BuildType::FACTORY)) > 0;
					// Joining means building the def that was ASKED. Passing
					// this unit's own pick to Take() when the standing request
					// is a different def creates a second plant (watched
					// 2026-08-21: "joining" armlab built an armvp beside it).
					if (outstanding) {
						CCircuitDef@ liveDef = Requests::LiveFactoryDef();
						if (liveDef !is null)
							@lab = liveDef;
					}
					if (outstanding || Factory::PlantApproved(lab)) {
						AIFloat3 labAt = unit.GetPos(ai.frame);
						const AIFloat3 labSite = ai.FindBuildSiteNear(lab, labAnchor,
								OpeningMexReach());
						if (OnMap(labSite))
							labAt = labSite;
						IUnitTask@ rebuild = Requests::Take(unit, lab,
								Task::BuildType::FACTORY, Task::Priority::HIGH,
								labAt, 0.f, 0.f);
						if (rebuild !is null) {
							AiLog(Factory::T() + "apex: commander "
								+ (outstanding ? "joining the standing factory request"
								               : "rebuilding a factory -- we have none"));
							return rebuild;
						}
						if (!outstanding)
							Factory::PlantAskAbort(lab);
					}
				}

				// No factory buildable right now (def unavailable, or the
				// request pool declined): keep the commander on economy
				// rather than idle. Bounded to OpeningMexReach (same as
				// opening step 1) rather than FindOpenMexSpot's whole-map
				// search, so a distant mex cannot starve the factory request
				// above forever.
				const int spot = aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame));
				if (spot >= 0) {
					IUnitTask@ mex = aiEconomyMgr.EnqueueMexAt(unit, spot);
					if ((mex !is null)
						&& (unit.GetPos(ai.frame).distance2D(mex.GetBuildPos()) <= OpeningMexReach()))
					{
						AiLog(Factory::T() + "apex: commander economy-first, no factory yet -- mex before rebuild");
						return mex;
					}
				}
			}
		}
	}
	return null;
}

int gNextCommAssist = 0;
int gNextCommEnergy = 0;
const int COMM_ASSIST_PERIOD = 2 * SECOND;

// Everything at the tail of AiMakeTask that could otherwise answer an idle
// commander is gated `!isComm` (MetalFullFallback, TidyObsolete, the dig-in),
// so this is its only fallback. Ordered by what the metal is worth: take
// ground, then put build power on the line that is producing, then buy
// energy.
IUnitTask@ CommanderIdleWork(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm || !CommRules())
		return null;
	// A commander that is standing still because it is in danger is handled by
	// the retreat branches above; do not hand it a job that walks it back out.
	// VetoCommanderReclaim and VetoCommanderHold null the engine's offer in order
	// to KEEP the commander on what it is already doing. Handing it fresh work
	// here caused exactly the task switch those vetoes exist to prevent, so a
	// commander genuinely mid-job is left alone. Mid-WALK counts as mid-job:
	// `target` (the nanoframe) is null the whole way to the site, and gating
	// on it had this rule hand the walking commander a solar every
	// COMM_ASSIST_PERIOD -- see VetoCommanderHold's comment.
	IUnitTask@ held = unit.task;
	if ((held !is null) && (SiteBuildName(held) != ""))
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (ThreatFor(unit, here) > CON_THREAT_VETO) {
		++gCommIdleUnsafe;
		return null;
	}

	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, here);
	if (spot >= 0) {
		IUnitTask@ mex = aiEconomyMgr.EnqueueMexAt(unit, spot);
		if (mex !is null) {
			++gCommIdleJobs;
			return mex;
		}
	}

	// Assisting is a REPAIR task on the factory itself, which is the only shape
	// the engine accepts: a positional REPAIR dereferences a null target inside
	// CBuilderManager::Enqueue. Rate-limited because the task persists once
	// taken, so asking every call would queue duplicates.
	if ((Factory::gT1FacUnit !is null) && (ai.frame >= gNextCommAssist)) {
		IUnitTask@ help = aiBuilderMgr.Enqueue(
				TaskB::Repair(Task::Priority::NORMAL, Factory::gT1FacUnit));
		if (help !is null) {
			gNextCommAssist = ai.frame + COMM_ASSIST_PERIOD;
			++gCommIdleJobs;
			return help;
		}
	}

	if (!aiEconomyMgr.isMetalEmpty && gHomeSet && !EnergyWasting()
		&& (ai.frame >= gNextCommEnergy)) {
		CCircuitDef@ gen = SolarDef();
		if ((gen !is null) && gen.IsAvailable(ai.frame)) {
			IUnitTask@ post = Requests::Take(unit, gen, Task::BuildType::ENERGY,
					Task::Priority::NORMAL, gHomePos, 0.f, SQUARE_SIZE * 8);
			if (post !is null) {
				gNextCommEnergy = ai.frame + COMM_ASSIST_PERIOD;
				++gCommIdleJobs;
				return post;
			}
		}
	}
	++gCommIdleNoJob;
	return null;
}

// ONE TOWER AT HOME, before the commander wanders off. MexGuard covers
// extractors and Fortify answers a constructor under repeated fire; neither
// covers the base itself, and the commander is the only builder present in
// the opening. The count check below stops asking once one stands, so this
// cannot become a porcupine habit.
const float HOME_TOWER_RADIUS = 900.f;
// GetOwnUnitsOfDef only returns FINISHED units, so while the tower is a
// nanoframe this rule would otherwise see a bare base and order another.
const int   HOME_TOWER_RETRY  = 90 * SECOND;
int gHomeTowerOrders = 0;
int gNextHomeTower = 0;
// The retry gate above bounds how OFTEN this asks, not how many orders are
// outstanding, and the standing-unit test cannot see a tower that was ordered
// but never built. Holding the task handle (same pattern as gMexTasks/
// gAimTask, tested via IsDefenceTaskLive) is what stops a repeat order.
IUnitTask@ gHomeTowerTask = null;

IUnitTask@ HomeTower(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm || !CommRules() || !gHomeSet || (ai.frame < gNextHomeTower))
		return null;
	// STEP 4 COMES AFTER STEP 3. This rule sits above DefaultMakeTask, so
	// during the opening it can take the commander off the economy the first
	// lab is waiting on. OpeningNeedsEconomy() alone is only the step-2 energy
	// gate and can release before a factory exists (its escape valve fires as
	// soon as no energy task is in flight) -- gate on Factory::HaveAnyFactory()
	// too, the actual step-3 condition, not this proxy for it.
	if (OpeningNeedsEconomy() || !Factory::HaveAnyFactory())
		return null;
	// One outstanding order at a time. See gHomeTowerTask.
	if (IsDefenceTaskLive(gHomeTowerTask))
		return null;
	// A forward base is exactly the case he was describing, so it gets the
	// heavier tower; a rear start keeps the cheap one.
	CCircuitDef@ tower = null;
	if (Military::OnBorder(gHomePos) || Military::NearFront(gHomePos))
		@tower = SideDef3(armbeamer, corhllt, legmg);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		@tower = SideDef3(armllt, corllt, leglht);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	// Anything of ours already standing here counts, so a base that got its
	// defence some other way is left alone.
	array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(tower, gHomePos, HOME_TOWER_RADIUS);
	if ((have !is null) && (have.length() > 0))
		return null;

	const AIFloat3 site = ai.FindBuildSiteNear(tower, gHomePos, HOME_TOWER_RADIUS);
	if (!OnMap(site))
		return null;
	IUnitTask@ post = Requests::Take(unit, tower, Task::BuildType::DEFENCE,
			Task::Priority::HIGH, site, 0.f, 0.f);
	if (post is null)
		return null;
	@gHomeTowerTask = post;
	gNextHomeTower = ai.frame + HOME_TOWER_RETRY;
	// A base whose position IS the front line needs the jammer too.
	// PlaceLineJammer previously fired only off a porcupine tower going up on
	// the line, which rarely happens for a base built on the line itself --
	// reusing it here rather than writing a second jammer rule.
	Military::PlaceLineJammer(site);
	++gHomeTowerOrders;
	AiLog(Factory::T() + "apex: home tower " + tower.GetName()
		+ " #" + gHomeTowerOrders + " -- base had none");
	return post;
}

IUnitTask@ CommanderMexGuard(CCircuitUnit@ unit, bool isComm, bool urgentOnly = false,
		bool nearOnly = false, bool lightOnly = false)
{
	// The commander plants most of the early mexes; MexGuard (inside the
	// !isComm block below) does not cover it, so this handles ANY builder, ANY
	// tier -- an unguarded extractor is what matters, not who is free.
	//
	// Self-limiting, which is what lets it sit high in the pipeline: it answers
	// only for an extractor with no cover and no pending cover, so each mex
	// draws one turret and then stops asking. apex_mex_sentry turns it down for
	// games against humans, who raid far less than the AI does.
	if (ai.GetTunable("apex_mex_sentry", TUNE_MEX_SENTRY) <= 0.f)
		return null;
	if (isComm && !CommRules())
		return null;
	// STEP 4 COMES AFTER STEP 3, same as HomeTower. Only excludes the
	// COMMANDER specifically: any other builder guarding a mex is not the sole
	// opening builder, so it costs nothing there.
	if (isComm && !Factory::HaveAnyFactory())
		return null;
	CCircuitDef@ mex = MexDef();
	if ((mex is null) || (mex.count <= 0))
		return null;
	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, gHomePos, 0.f);
	if ((mine is null) || (mine.length() == 0))
		return null;

	const AIFloat3 me = unit.GetPos(ai.frame);
	AIFloat3 bare;
	bool have = false;
	float bestD = 0.f;
	for (uint i = 0; i < mine.length(); ++i) {
		if (mine[i] is null)
			continue;
		const AIFloat3 at = mine[i].GetPos(ai.frame);
		if (!OnMap(at))
			continue;
		if (DefenceWithin(at, MEX_IN_RANGE) > 0)
			continue;                       // already shot over
		if (DefenceTaskNear(at, MEX_IN_RANGE))
			continue;                       // someone is already on it
		// URGENT pass: only a bare mex with an enemy actually visible near it
		// qualifies -- this is the call hoisted ABOVE the next-mex claim, so
		// the commander guards the thing the radar says is about to die
		// instead of walking away from it (apexearth: "an enemy in his radar
		// range after making a mex and a solar. He walks away... as soon as
		// he is gone the two things he just dedicated 30 seconds on are
		// destroyed"). The ordinary no-enemy pass keeps its old, lower slot.
		if (urgentOnly && (RingInflMax(at, 500.f) <= 0.01f))
			continue;
		const float d = me.distance2D(at);
		// NEAR pass: only the mex underfoot -- typically the one this builder
		// just finished. Sits above the next-mex claim so a fresh extractor
		// gets its turret before the builder walks away from it; the far
		// bare ones stay with the ordinary lower slot and its longer reach.
		if (nearOnly && (d > MEX_GUARD_HERE))
			continue;
		if (!have || (d < bestD)) {
			bestD = d;
			bare = at;
			have = true;
		}
	}
	if (!have)
		return null;

	// lightOnly: the dedicated metal crew's underfoot sentry stays the cheap
	// tier whatever the income -- MexGuardTower tiers up to T2 towers past
	// 50 m/s, which is build power the crew owes to mexes, not fortresses.
	CCircuitDef@ tower = lightOnly ? SideDef3(armllt, corllt, leglht)
			: MexGuardTower(unit, bare);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	const AIFloat3 site = ai.FindBuildSiteNear(tower, bare, MEX_GUARD_RADIUS);
	if (!OnMap(site))
		return null;

	// DefenceAllowedAt is not asked: it bounds the FRONT allowance and refuses the
	// rear, where extractors are.
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, tower, Task::BuildType::DEFENCE,
			Task::Priority::HIGH, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	// Without this the mex reads bare again next tick: FENCE only fires on a
	// FINISHED turret, so nothing suppresses the repeat until it is built.
	NoteDigOrder(site);
	CloakWithWalls(unit, tower, site, Task::Priority::HIGH);
	++gMexSentries;
	if (gMexSentries <= 3 || (gMexSentries % 10 == 0)) {
		AiLog(Factory::T() + "apex: mex sentry #" + gMexSentries + " "
			+ tower.GetName() + " on a bare extractor, mex=" + mex.count);
	}
	return post;
}

IUnitTask@ VetoCommanderReclaim(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)
{
	// The isComm gates on the wreck blocks below only stop the commander from
	// CREATING a new reclaim task; they cannot stop CBuilderManager::
	// MakeCommPeaceTask (native C++, inside DefaultMakeTask above) from picking
	// up a HIGH-priority Reclaim task some OTHER unit already enqueued into the
	// shared buildTasks pool, regardless of distance. Reject it while an
	// unclaimed safe mex spot is still nearby; once the mex phase is done, let
	// it through same as everyone else.
	if (isComm && CommRules() && (task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == Task::BuildType::RECLAIM)
		&& (aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame)) >= 0))
	{
		++gCommVetoReclaim;
		@task = null;
	}
	return task;
}

IUnitTask@ VetoCommanderHold(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)
{
	// General form of the veto above: keep what the commander is already
	// doing rather than swapping to a different build type. `unit.task` is
	// still the OLD task here -- Reevaluate only swaps it once AiMakeTask
	// returns a differing build type -- so this compares current against
	// proposed. Danger is handled earlier, by the comm-abandon retreat.
	// The FIRST factory is never worth holding a mex over. The commander is the
	// only builder in the opening, so while it is pinned to a mex chain nothing
	// else can start the lab -- and there is always another mex spot, so the pin
	// does not release on its own.
	const bool firstFactory = (task !is null)
			&& (task.GetType() == Task::Type::BUILDER)
			&& (task.GetBuildType() == Task::BuildType::FACTORY)
			&& !Factory::HaveAnyFactory();
	if (isComm && CommRules() && !firstFactory && (task !is null) && (task.GetType() == Task::Type::BUILDER)) {
		IUnitTask@ held = unit.task;
		const string heldKind = SiteBuildName(held);
		// HOLD ONLY REAL WORK. `held` names a build type from the moment the task
		// exists, but `target` is the nanoframe -- null until something is
		// actually standing there. Vetoing on the name alone means the commander
		// refuses every new job while "holding" a task it has not started, and
		// AiMakeTask returning null leaves it with nothing to do at all.
		//
		// ... AND the walk to any named site: `target` stays null for the whole
		// walk, so gating on it left the commander swappable the entire way
		// there -- measured as 25+ MEX<->GUARD build-type flips in 10 seconds
		// (comm-switch diag, 20260816-214818), each flip enqueueing an orphan
		// mex claim so the next election picked a farther spot. The stuck
		// breaker above (COMM_STUCK_TICKS) still cuts a walk whose engine
		// order never arrives, and comm-abandon still cuts a site gone hot.
		const bool reallyWorking = (held !is null)
				&& ((held.target !is null) || (SiteBuildName(held) != ""));
		if (reallyWorking && (heldKind != "") && (held.GetBuildType() != task.GetBuildType())
			&& (ThreatFor(unit, held.GetBuildPos()) <= CON_THREAT_VETO))
		{
			++gCommVetoHold;
			LogConVeto(unit, "comm-hold", heldKind, 0.f);
			@task = null;
		}
	}
	return task;
}

}  // namespace Builder
