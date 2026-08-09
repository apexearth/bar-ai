namespace Builder {

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
	// Rez bots have no buildoptions and cannot dig in like an ordinary
	// constructor -- Fortify/ContestTower never apply to them -- so a hit here
	// means flee, not fortify. And nothing else in this function ever calls
	// ConDugIn for them, since every rez branch below returns early: a bot
	// that commits to a resurrect has nothing re-checking it while the task
	// runs. apexearth, watching an enemy army arrive live: "eight rez bots
	// resurrecting... they have no time... they keep rezzing... and die...
	// lots of metal around, all could have been taken... our bad logic
	// prevented us from taking that metal and running."
	//
	// RezSpotHot/PreferReclaim below only gate which task gets ASSIGNED, and
	// RezSpotHot's ThreatFor falls back to PastFront() geometry once the
	// position threat map reads zero -- which ThreatFor's own comment says is
	// ~97% of the time -- so an enemy push that has not crossed the front's
	// 72% line still reads "safe" while standing on the bot. ConDugIn's
	// HP-drop tracking is a real positional signal instead: something shot us,
	// HERE. One hit is enough -- unlike an armed constructor, a rez bot cannot
	// answer fire by digging in, only by leaving.
	if (IsRezzer(unit)) {
		ConDugIn(unit);   // side effect: refreshes gConHits/gConHp for this bot
		if (gConHits[ConSlot(unit)] > 0) {
			IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
			if (flee !is null) {
				// TROUBLE_WINDOW holds this true for up to 90s per hit, so without a
				// log throttle this call re-logs on every AiMakeTask re-entry while
				// fleeing -- 399 lines in one 15-minute smoke test. EnqueueRetreat
				// itself is called every time regardless (same as the commander
				// retreat above), on the same assumption that re-enqueuing an
				// existing retreat is a cheap no-op, not a restart.
				if (ai.frame >= gNextRezFleeLog) {
					gNextRezFleeLog = ai.frame + 20 * SECOND;
					AiLog(Factory::T() + "apex: rez bot taking fire, retreating with whatever it banked");
				}
				return flee;
			}
		}
	}

	// Rez bots work the DEFENCE LINE, not wherever they happen to stand.
	//
	// apexearth: "if we are losing then reclaim becomes even more important, as
	// those defenses kill enemies on our border -- we can resurrect or reclaim
	// the metal". The corpses pile up where the fighting is, and the search below
	// only reaches 2200 elmos from the bot itself, so a bot idling at home never
	// finds them. Search from the front instead while we are behind.
	if (IsRezzer(unit) && Military::LosingGround() && (ai.frame >= gNextRezWreck)) {
		AIFloat3 front;
		if (Military::FrontPos(front)) {
			gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
			const AIFloat3 spoil = ai.GetBestWreckPos(front, WRECK_SEARCH, WRECK_MIN);
			if (spoil.x >= 0.f) {
				IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
				if (harvest !is null)
					return harvest;
			}
		}
	}

	// Eat the corpse rather than rebuild it, before the engine gets the chance
	// to queue a resurrect for this bot.
	if (IsRezzer(unit) && (ai.frame >= gNextRezWreck)
			&& (PreferReclaim() || RezSpotHot(unit) || RezBotExposed(unit))) {
		gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
		IUnitTask@ eat = EnqueueWreckReclaim(unit, Task::Priority::HIGH);
		if (eat !is null)
			return eat;
	}

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

	// Let a constructor FINISH the defence it already started.
	//
	// AiMakeTask re-decides from scratch on every call, and IBuilderTask::
	// Reevaluate swaps the unit's task whenever we hand back a different BUILD
	// TYPE. Fortify only fires while ConDugIn() is true, i.e. while the con is
	// being shot at -- so the moment the shooting stops this function offers a
	// mex or an energy building instead, the swap happens, and the half-built
	// tower is abandoned.
	//
	// That is why script-placed static defence has never appeared in a game.
	// Measured with a probe inside IBuilderTask::CanAssignTo: corllt tasks were
	// ACCEPTED by a builder six times in one game and corllt was built ZERO
	// times, while stock CircuitAI's own corhlt/corhllt built normally. Energy
	// survived the same churn only because the metal-full fallback keeps
	// handing back ENERGY -- the same type, so no swap.
	//
	// Deliberately narrow: only a DEFENCE build already in progress, only while
	// its site is not itself dangerous (the abandon checks below still own that
	// case), and never for the commander, which has its own hold rule.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (busy.GetType() == Task::Type::BUILDER)
			&& (busy.GetBuildType() == Task::BuildType::DEFENCE)
			&& (ThreatFor(unit, busy.GetBuildPos()) <= CON_THREAT_VETO))
		{
			return busy;
		}
	}
	if (isComm) {
		LogCommanderThreat(unit);
		// LEAVE BECAUSE OF WHAT IS THERE, NOT BECAUSE YOU ARE ALREADY HURT.
		//
		// COM_RETREAT_HEALTH already pulls the commander out on first real
		// damage, and it is still dying: apexearth, watching a 1v1, "we keep
		// losing to our commander going banzai into enemy armies... almost every
		// time", then the correction that matters -- "he's defending the base,
		// but the enemy army is too big for him to take on so he should not do
		// it". An army that arrives in force kills a commander from full health,
		// so a health trigger fires once and too late.
		//
		// Uses the INFLUENCE map, not ai.GetBuilderThreatAt: the threat map read
		// LOWER than baseline in the 30s before a commander died across ten
		// games (3% nonzero vs 8%), because the killer is at range and the
		// victim's own tile reads clean. Influence is a different signal.
		//
		// DEFAULT OFF. The last position-based commander retreat fired whenever
		// 3+ enemies were within 800, returned a Patrol task, and went 0-20 with
		// metal at 6,631. The threshold here is not measured either, so it ships
		// inert and is switched on per-match for the A/B that sets it.
		const float fleeInfl = ai.GetTunable("apex_comm_flee_influence", 0.f);
		if (fleeInfl > 0.f) {
			const float hereInfl = ai.GetEnemyInflAt(unit.GetPos(ai.frame));
			if (hereInfl > fleeInfl) {
				if (ai.frame >= gNextCommFleeLog) {
					gNextCommFleeLog = ai.frame + 15 * SECOND;
					AiLog(Factory::T() + "apex: commander leaving, enemy influence "
						+ formatFloat(hereInfl, "", 0, 2) + " > " + formatFloat(fleeInfl, "", 0, 2));
				}
				IUnitTask@ bail = aiBuilderMgr.EnqueueRetreat();
				if (bail !is null)
					return bail;
			}
		}
		// The commander guards the mexes it just made. apexearth: "even the
		// commander does this... he's right there making the mex and then he
		// just walks away like they arent important to protect." MexGuard picks
		// the NEAREST undefended mex within MEX_GUARD_REACH, so for a commander
		// that has just finished one this is the mex under its feet.
		if (unit.GetHealthPercent() >= COM_RETREAT_HEALTH) {
			IUnitTask@ cguard = MexGuard(unit);
			if (cguard !is null)
				return cguard;
		}
		const float hp = unit.GetHealthPercent();
		if (hp < COM_RETREAT_HEALTH) {
			// apexearth, watching live: "once the commander retreats to the back
			// of his base he stays there too long, even while at 50% health he's
			// still cowering there... He should stand behind his t1 lab and help
			// it build stuff!" Previously this fired EnqueueRetreat() every single
			// cycle while hp stayed low, with no check on whether the commander
			// had already reached safety -- so it could never fall through to
			// DefaultMakeTask's own commander logic (CBuilderManager::
			// DefaultMakeTask, MakeCommPeaceTask/MakeCommDangerTask), which
			// already decides hide-vs-assist from LOCAL enemy influence at the
			// commander's current position, not health. Only keep forcing a
			// flee while genuinely still under local threat; once safe, let that
			// existing C++ logic take over instead of looping a bare retreat.
			const float hereThreat = ThreatFor(unit, unit.GetPos(ai.frame));
			if (hereThreat > CON_THREAT_VETO) {
			if (ai.frame >= gNextRetreatLog) {
				gNextRetreatLog = ai.frame + 20 * SECOND;
				AiLog(Factory::T() + "apex: commander retreating at "
					+ formatFloat(hp * 100.f, "", 0, 0) + "% health, frame=" + ai.frame);
			}
			IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
			if (flee !is null)
				return flee;
			}
		}
		// The enemy centroid has come to US. PastFront cannot see this: the base
		// centre sits at fraction ~0 on the home->enemy axis, so it always reads
		// safe, however many enemies are standing in it. apexearth: "sometimes
		// they have a tendency of just running into the center of their base only
		// to get blown up... convince commanders to hide and defend themselves
		// behind their base."
		//
		// So put the commander to work at the BACK WALL instead, using the RearPos
		// the converter rule already uses -- measured away from the enemy, OnMap
		// checked. It relocates by having a job there, which needs no movement
		// command: CmdMoveTo is what UpdateCommanderSafety used and it correlated
		// with 14-17 engine aborts per 20-game run.
		//
		// LIMITATION: GetEnemyPos is the centroid of ALL enemies, so on a big map
		// with spread enemies it can read far away while one of them is in our
		// base. This catches the massed case, not the single raider.
		if (COMM_BACK_WALL_ON && BaseUnderAttack() && (ai.frame >= gNextCommHide)) {
			// Energy full: just leave. The solar is only a way to make the
			// commander WALK somewhere -- it is not wanted for its own sake, and
			// building one on a full bank is pure waste. This fired 21 times in a
			// single game before the check existed. apexearth: "these guys are
			// just making solars while they're on full energy... idk why".
			if (aiEconomyMgr.isEnergyFull) {
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null) {
					gNextCommHide = ai.frame + COMM_HIDE_PERIOD;
					return flee;
				}
			}
			AIFloat3 back;
			if (RearPos(unit, back)) {
				CCircuitDef@ safe = SideDef3(armsolar, corsolar, legsolar);
				if ((safe !is null) && safe.IsAvailable(ai.frame)) {
					IUnitTask@ hide = aiBuilderMgr.Enqueue(TaskB::Common(
							Task::BuildType::ENERGY, Task::Priority::NORMAL,
							safe, back, SQUARE_SIZE * 8));
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
		// builder already gets this a few lines below, behind `if (!isComm)`, so
		// the commander was the ONE unit that would keep walking into fire.
		// apexearth: "sometimes they have a tendency of just running into the
		// center of their base only to get blown up."
		//
		// Retreat only -- no ContestDefence. A constructor answers danger by
		// building a tower into it; a commander must not stand there doing that.
		// EnqueueRetreat is the same call the health path above already makes for
		// commanders, so this adds no new mechanism. In particular it is NOT
		// CmdMoveTo: that is what UpdateCommanderSafety used, and it correlated
		// with 14-17 engine aborts per 20-game run before being removed.
		{
			IUnitTask@ held = unit.task;
			const string kind = SiteBuildName(held);
			if (kind != "") {
				const float heat = ThreatFor(unit, held.GetBuildPos());
				if (heat > CON_THREAT_VETO) {
					LogConVeto(unit, "comm-abandon", kind, heat);
					IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
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

		// A player with no factory left has no way back -- see
		// Factory::HaveAnyFactory()'s own comment for how this was found.
		// Below every safety check above: a commander actively fleeing or
		// hiding from a real threat must keep doing that, not detour to a
		// build site. Gated past the opening (3 min) so this never competes
		// with the normal game-start sequence, which already places the
		// first factory through its own, separately-verified path.
		if (!Factory::HaveAnyFactory() && (ai.frame >= 3 * MINUTE)) {
			// apexearth, watching live: "when we have 0 buildings, we
			// shouldn't start by making a lab... green ran out of
			// everything, his first building to make after that was a
			// botlab, then he started a vehicle lab.... he should get to
			// high safety area and make economy first." This block used to
			// build unconditionally at unit.GetPos() with no safety or
			// economy check at all -- exactly that.
			//
			// Safety: reuse the same ThreatFor check the retreat branches
			// above already use. A wiped-out commander standing in the open
			// must keep fleeing, not stop to build.
			const float hereThreat = ThreatFor(unit, unit.GetPos(ai.frame));
			if (hereThreat > CON_THREAT_VETO) {
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null)
					return flee;
			} else {
				// Economy before factory, once actually safe: a rebuilt
				// factory with no income behind it just gets lost the same
				// way again. Only while a safe, reachable mex spot still
				// exists nearby -- once none is left, fall through to the
				// factory rebuild below rather than stalling forever
				// waiting for a spot that isn't there.
				const int spot = aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame));
				if (spot >= 0) {
					IUnitTask@ mex = aiEconomyMgr.EnqueueMexAt(unit, spot);
					if (mex !is null) {
						AiLog(Factory::T() + "apex: commander economy-first, no factory yet -- mex before rebuild");
						return mex;
					}
				}
			}

			CCircuitDef@ lab = Factory::T1BotLab();
			if ((lab !is null) && lab.IsAvailable(ai.frame)) {
				IUnitTask@ rebuild = aiBuilderMgr.Enqueue(TaskB::Common(
						Task::BuildType::FACTORY, Task::Priority::HIGH,
						lab, unit.GetPos(ai.frame), 0.f));
				if (rebuild !is null) {
					AiLog(Factory::T() + "apex: commander rebuilding a factory -- we have none");
					return rebuild;
				}
			}
		}
	}
	// Already walking to a site that is now inside enemy fire. IBuilderTask::
	// Reevaluate calls this hook on every task update for as long as the builder
	// is away from its build position, so the whole walk is covered -- but it
	// swaps the unit's task only when what we hand back differs in build type,
	// so a refusal here has to be a real task rather than null.
	if (!isComm) {
		IUnitTask@ held = unit.task;
		const string kind = SiteBuildName(held);
		if (kind != "") {
			float heat = ThreatFor(unit, held.GetBuildPos());
			if (kind == "mex")
				heat = MexHeat(held.GetBuildPos(), heat);
			if (heat > CON_THREAT_VETO) {
				++gConAbandoned;
				ConStrike(unit);
				LogConVeto(unit, "abandon", kind, heat);
				// A defence post and a retreat both differ in build type; another
				// mex would not, so the reroute belongs on the refuse path only.
				IUnitTask@ post = ContestDefence(unit, kind, heat, held.GetBuildPos());
				if (post !is null)
					return post;
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null)
					return flee;
			}
		} else if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::RECLAIM))
		{
			// apexearth, watching live: "constructors seem to want to roam
			// out towards the enemy army to reclaim ... they all died."
			// SiteBuildName deliberately excludes RECLAIM (every wreck-
			// chasing dispatch point already threat-checks the destination
			// before sending a constructor there -- see EnqueueWreckReclaim/
			// the rich-pile block), so this abandon-and-recheck loop above
			// never covered reclaim: a destination checked safe ONCE at
			// dispatch was never re-checked again during the walk or while
			// reclaiming. An active battlefield's safety can flip in the
			// time it takes to walk there -- there was no path back once it
			// did. Same abandon pattern as mex/build above, no
			// ContestDefence (building a tower at a corpse pile doesn't fit
			// the same shape as holding a mex).
			const float heat = ThreatFor(unit, held.GetBuildPos());
			if (heat > CON_THREAT_VETO) {
				++gConAbandoned;
				ConStrike(unit);
				LogConVeto(unit, "abandon", "reclaim", heat);
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null)
					return flee;
			}
		}
	}

	// After the reactive branches above, before ordinary work. It pre-empts
	// DefaultMakeTask, which is where mex upgrades live, so it is bounded twice
	// over: one every 25 seconds, and never when it would leave us short of
	// builders. Twelve rules pre-empting here with neither bound is what cut metal
	// production 4.3x.
	// DO NOT DISPLACE WORK ALREADY IN PROGRESS.
	//
	// This hook is not only called for an idle builder: IBuilderTask::Reevaluate
	// calls it on every task update for as long as the builder is away from its
	// build position, and the engine swaps the unit's task whenever what we hand
	// back differs in BUILD TYPE. So every optional rule below -- AA, the gun,
	// converters, nanos, fusions, dig-ins -- could yank a constructor off a site
	// it was walking to, leaving a claimed task nobody works.
	// apexearth: "I noticed more recently buildings getting started and then
	// canceled... maybe you have some logic that isn't checking if there's
	// already a task and you are replacing tasks."
	// Measured: 60 live MEX tasks with 60 of them unworked, repeatedly.
	// The veto/abandon check above has already run, so anything still held here
	// is work the AI still considers safe and wants finished.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (SiteBuildName(busy) != ""))
			return busy;
	}


	// The commander plants most of the early mexes, and was the ONE builder
	// forbidden from protecting them: MexGuard lives inside the !isComm block
	// below, so every mex the commander made stood bare unless some other
	// constructor happened past. apexearth, watching: "the commander here makes
	// 5 mexes and doesnt build a sentry tower next to any of them."
	// Self-limiting without a cooldown: AreaNeedsDefence only returns a mex that
	// is not already covered, so this stops asking once they are.
	if (isComm) {
		IUnitTask@ commGuard = MexGuard(unit);
		if (commGuard !is null)
			return commGuard;
	}

	if (!isComm) {
		// con-heal (RepairNear) stays reflexive and ungated -- it answers
		// something happening now (a nearby wounded unit) rather than
		// claiming a slice of surplus, per docs/12-build-phases.md's own
		// split of phase-gated (investment) vs never-phase-gated (reflexive)
		// rules. RepairNear returns true when it has already handled (or is
		// standing down for) a nearby repair.
		if (RepairNear(unit)) {
			++gRepairHeld;
			if (ai.frame >= gNextRepairLog) {
				gNextRepairLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: con-heal " + unit.circuitDef.GetName()
					+ " stands down, repairs=" + gArmyRepairs.length()
					+ " held=" + gRepairHeld);
			}
		}
		else {
			// CheapAA carved out of the phase gate below, 2026-08-05: apexearth
			// live-watched a Legion game with aaT1=0 at 7+ minutes against active
			// mosquito-gunship pressure, and the phase telemetry confirms why --
			// gHaveT2 (and so gLastPhase>=4) stayed at 0 for the entire pre-T2
			// window every game, so CheapAA was structurally unreachable exactly
			// when hit-and-run air is cheapest to punish. Unlike HeavyAA/Pulsar/
			// the eco cluster below (open-ended investment, correctly deferred
			// until the economy has actually teched), CheapAA is already a
			// tightly self-gated reactive deterrent: it requires enemyAir >= 1
			// (a real observed threat, not a forecast), caps at AA_MIN..AA_MAX,
			// and is throttled by AA_PERIOD -- it cannot crowd out expansion the
			// way the rest of this cluster measurably did.
			IUnitTask@ aa = CheapAA(unit);
			if (aa !is null)
				return aa;
			// The better turret sits beside the cheap one, outside the phase
			// gate, for the same reason CheapAA was carved out of it: it answers
			// OBSERVED enemy air rather than forecasting, it is bounded at 1..4,
			// and the def is T2 so it cannot fire before the tech exists anyway.
			// Inside the gate it needed gHaveT2 AND an ECO/HOME crew role, which
			// is why the good AA never appeared in time.
			IUnitTask@ heavyAa = HeavyAA(unit);
			if (heavyAa !is null)
				return heavyAa;
			IUnitTask@ deter = HomeDeter(unit);
			if (deter !is null)
				return deter;
			// BUILD_PHASE gate on the remaining optional economy cluster.
			// Progression, 2026-08-04: phase >= 2 (mex >= 4) reverted, 0 wins in
			// 13 decided. phase >= 3 (RushReady) confirmed a real improvement, 5
			// wins in 22 decided (22.7%) across 4 batches. phase >= 4 (gHaveT2 --
			// an advanced factory actually finished, not just afforded) measured
			// BEST: 6 wins in 10 decided (60.0%, 95% CI 31.3%-83.2%) across 2
			// batches, P(>=6 wins in 10 | baseline true rate 7.9%) = 0.00004, and
			// most games (14/16 in the larger batch) ran the full time limit
			// competitively rather than being decided either way. See
			// notes/open-issues.md issue 15 for the full data and CHANGES.md for
			// the summary. Before an advanced factory exists, a constructor's
			// only job is expansion and reaching T2; HeavyAA, Pulsar, EnergyConverter
			// and the nano/fusion block below can all wait for an economy that has
			// actually teched, not merely one that could afford to.
			//
			// EnergyConverter was carved out of this gate earlier tonight (same
			// evidence shape as CheapAA -- self-gated on real spare energy, not a
			// forecast) after apexearth asked "why no energy converters?" at 9
			// minutes. REVERTED, same session, same night: apexearth immediately
			// afterward, watching mex expansion specifically: "I'd say we do build
			// too many cons... but huge issue is they just aren't placing enough
			// priority on building mexes." EnergyConverter was checked and could
			// claim a constructor's assignment BEFORE DefaultMakeTask (which is
			// what actually creates new mex-expansion tasks, Priority::HIGH in
			// EconomyManager.cpp) ever ran -- so unblocking it pre-T2 meant it
			// could now win the same idle-constructor pool mex expansion needs,
			// in exactly the 0-9 minute window this complaint is about. Mex
			// expansion matters more than energy conversion; reverted to
			// gLastPhase>=4 until a fix that does not compete with mex for
			// constructor time exists.
			// The crew SUPPRESSES the optional economy cluster for its members;
			// it does not replace their task selection.
			//
			// First attempt dispatched the crew above this whole function, which
			// skipped every threat veto, abandon and repair rule an ordinary
			// constructor gets -- apexearth: "cons seem really dumb, dark green
			// just walking its cons off to die", and the economy was worse. The
			// intent was only ever to stop converters/nanos/fusions outbidding
			// mex expansion for these units, and that is all this does now:
			// they fall through to DefaultMakeTask, where mex work lives at
			// Priority::HIGH, with every safety rule above still applied.
			const int crewRole = Crew::RoleOf(unit);
			if (crewRole == Crew::MEX) {
				IUnitTask@ dig = Crew::MexWork(unit);
				if (dig !is null)
					return dig;
			} else if (crewRole == Crew::FRONT) {
				IUnitTask@ hold = Crew::FrontWork(unit);
				if (hold !is null)
					return hold;
			}
			// Guarding a mex is NOT in the phase-gated cluster below: it is an
			// early-game job, it is the cheapest thing on this list, and the
			// alternative is the army walking back to chase a scout.
			// The home crew never leaves. apexearth: "some should ALWAYS be
			// doing economy at home." They are kept home by being offered ONLY
			// the economy cluster below, which is all base work by construction,
			// and by being skipped for the jobs that travel.
			// EVERY role guards mexes, home crew included: MEX_GUARD_REACH is
			// 1200 and HOME_RADIUS is 1600, so a nearby mex is base work by any
			// reading. Excluding them dropped guards from 32 to 9 in a game --
			// with 2 home and 3 mex out of about 5 constructors there was nobody
			// left to place one. apexearth: "we NEED to have at least one llt
			// early game within range of our mexes... it'll make them last so
			// much longer."
			// Guarding a mex comes FIRST -- ahead of the home crew's energy job.
			// HomeEnergy always returns work now, so putting it first meant the
			// home crew never reached this and guards fell 18 -> 6 in a game.
			// A 130-metal turret that saves a 620-metal mex outranks a solar.
			IUnitTask@ guard = MexGuard(unit);
			if (guard !is null)
				return guard;

			// The home crew's own job, NOT phase-gated: the pre-fusion energy
			// curve is exactly the stage this is for. HomeEnergy returns null for
			// anyone who is not Crew::HOME, so this call cannot reach the rest of
			// the constructor pool.
			IUnitTask@ juice = HomeEnergy(unit);
			if (juice !is null)
				return juice;

			if ((Factory::gLastPhase >= 4)
				&& ((crewRole == Crew::ECO) || (crewRole == Crew::HOME))) {
				// Clearing an obsolete base outranks ADDING to it. ObsoleteReclaim
				// also sits at the end of this function, which is why it fired
				// twice in thirty minutes: a constructor was always offered
				// something else first. Promoted only above the ECO offers -- the
				// cheapest constructor time here -- and only once the junk is
				// thick enough to be the thing in the way.
				IUnitTask@ clear = ObsoleteUrgent(unit);
				if (clear !is null)
					return clear;
				// A full bank outranks everything else here. The most expensive
				// thing we can start is the one that drains it fastest.
				IUnitTask@ big = SurplusGantry(unit);
				if (big !is null)
					return big;
				IUnitTask@ nuke = NukeSilo(unit);
				if (nuke !is null)
					return nuke;
				// Assist bots and front constructors get their standing job here,
				// where everything protective has already had its say.
				IUnitTask@ help = Assist::Work(unit);
				if (help !is null)
					return help;
				if (!Factory::EcoLeadActive()) {
					IUnitTask@ gun = Pulsar(unit);
					if (gun !is null)
						return gun;
				}
				IUnitTask@ dome = Shield(unit);
				if (dome !is null)
					return dome;
				IUnitTask@ block = EcoConverters(unit);
				if (block !is null)
					return block;
				IUnitTask@ conv = EnergyConverter(unit);
				if (conv !is null)
					return conv;
				IUnitTask@ nano = EcoNano(unit);
				if (nano !is null)
					return nano;
				IUnitTask@ fus = EcoFusion(unit);
				if (fus !is null)
					return fus;
			}
		}
	}

	// Its own recent history says it cannot expand, so stop sending it out. The
	// tower it puts up instead is what makes the ground usable later -- but only
	// where something is not already standing; see AreaNeedsDefence.
	if (!isComm && !Factory::EcoLeadActive() && ConDugIn(unit)) {
		IUnitTask@ dig = Fortify(unit);
		if (dig !is null)
			return dig;
	}

	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);

	// EXPANSION IS NEVER OVERRIDDEN.
	//
	// Everything below this line can null `task` -- threat vetoes, the comm-hold
	// rule, the assist gate -- and every one of them was written about some other
	// build type. When the engine hands back a MEX, MEXUP, GEO or GEOUP it has
	// already decided we should expand, at Priority::HIGH, from the one function
	// that creates that work at all (CEconomyManager::MakeEconomyTasks). Refusing
	// it does not defer expansion, it discards the only offer of it.
	//
	// This repo has the collapse on record: mex upgrades 11 -> 2 across a session
	// where twelve rules were added in front of DefaultMakeTask, each individually
	// reasonable. Today's 1v1 measurements found the same shape from the other
	// end -- MEX tasks standing unworked at 2, 4, 8, 13, 23 while no builder was
	// on one for fourteen minutes.
	//
	// Taken from Felnious/Skirmish, which reaches the same conclusion structurally
	// rather than by tuning: the same six lines appear in five of its role files.
	// See docs/13-other-ais.md. It is a STOP, not a spend -- it enqueues nothing
	// and cannot cost constructor time, it only declines to throw work away.
	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)) {
		const int bt = task.GetBuildType();
		if ((bt == int(Task::BuildType::MEX)) || (bt == int(Task::BuildType::MEXUP))
			|| (bt == int(Task::BuildType::GEO)) || (bt == int(Task::BuildType::GEOUP)))
		{
			return task;
		}
	}

	// apexearth, watching live: "commanders are often walking unreasonably
	// long distances to get the reclaim when their time would be better
	// spent getting mexes... once they have mexes reclaim is fine." The
	// isComm gates on the wreck blocks below only stop the commander from
	// CREATING a new reclaim task; they cannot stop CBuilderManager::
	// MakeCommPeaceTask (native C++, runs inside DefaultMakeTask above) from
	// picking up a Reclaim task some OTHER unit already enqueued into the
	// shared buildTasks pool. Those reclaim tasks carry Task::Priority::HIGH,
	// which dominates that picker's distance-cost weighting regardless of how
	// far away the pile actually is -- so the commander can get pulled onto
	// someone else's reclaim job from clear across the map. Reject it while
	// there is still an unclaimed safe mex spot nearby; once the mex phase is
	// done, let it through same as everyone else.
	if (isComm && (task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == Task::BuildType::RECLAIM)
		&& (aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame)) >= 0))
	{
		@task = null;
	}

	// General form of the veto above: keep what the commander is already
	// doing rather than swapping to a different build type. `unit.task` is
	// still the OLD task here -- Reevaluate only swaps it once this function
	// returns a differing build type -- so this compares current against
	// proposed. Danger is handled earlier, by the comm-abandon retreat.
	// The FIRST factory is never worth holding a mex over. The commander is the
	// only builder in the opening, so while it is pinned to a mex chain nothing
	// else can start the lab -- and there is always another mex spot, so the pin
	// does not release on its own. apexearth, watching a 6v6: "'calm phil' didn't
	// make a lab until 4m in... he was walking around unsure what to do with
	// himself." That player took 4.1 minutes to a first factory against 1.0-2.8
	// for the other five.
	const bool firstFactory = (task !is null)
			&& (task.GetType() == Task::Type::BUILDER)
			&& (task.GetBuildType() == Task::BuildType::FACTORY)
			&& !Factory::HaveAnyFactory();
	if (isComm && !firstFactory && (task !is null) && (task.GetType() == Task::Type::BUILDER)) {
		IUnitTask@ held = unit.task;
		const string heldKind = SiteBuildName(held);
		if ((heldKind != "") && (held.GetBuildType() != task.GetBuildType())
			&& (ThreatFor(unit, held.GetBuildPos()) <= CON_THREAT_VETO))
		{
			LogConVeto(unit, "comm-hold", heldKind, 0.f);
			@task = null;
		}
	}

	// apexearth: "have our units never assist another unit build something if
	// we are out of a resource (<5%). This should help encourage getting
	// mexes." Only about JOINING someone else's build -- task.GetUnits() is
	// the set of units already on it, so an empty list means this unit would
	// be starting fresh, not assisting, and is left alone. Mex/mex-upgrade
	// tasks are exempt: assisting one of those is exactly the behavior a
	// resource crunch should produce more of, not less.
	// A fresh-context agent flagged this (added in 6214df3, smoke-tested
	// only at the time) as a possible contributor to Cortex's drop from a
	// documented 96.3% peak (2a9613e) to 68.8%. Tested directly: disabling
	// this AND the factory-cap exemption above for a 16-game Cortex mirror
	// (same seeds as the 68.8% baseline) gave 62.5% -- no recovery.
	// Hypothesis rejected by data; restored.
	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() != Task::BuildType::MEX)
		&& (task.GetBuildType() != Task::BuildType::MEXUP)
		&& (task.GetUnits().length() > 0))
	{
		const bool metalCrit = (aiEconomyMgr.metal.storage > 0.f)
				&& (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * RESOURCE_CRISIS_FRAC);
		const bool energyCrit = (aiEconomyMgr.energy.storage > 0.f)
				&& (aiEconomyMgr.energy.current < aiEconomyMgr.energy.storage * RESOURCE_CRISIS_FRAC);
		if (metalCrit || energyCrit) {
			@task = null;
		}
	}

	// Refusing to accept the job in the first place. Reached from CIdleTask, where
	// returning null simply leaves the unit idle until the next idle sweep.
	if (!isComm) {
		// Jammer area-clustering veto (see AreaHasJammer's own comment). Checked
		// before SiteBuildName's whitelist, since jammers fall outside it (kind
		// would be "" and none of the checks below would ever see this task).
		// GetBuildPos() is only valid for BUILDER-type tasks -- SiteBuildName
		// guards this same way; missing it here crashed the native DLL at
		// ~1.2 minutes in every game of an 8-game batch (armada-bisect-
		// outrange-revert-8) the first time this path was actually exercised.
		if ((task !is null) && (task.GetType() == Task::Type::BUILDER) && IsJammerDef(task.buildDef)) {
			const AIFloat3 jsite = task.GetBuildPos();
			if (AreaHasJammer(jsite)) {
				++gConRefused;
				LogConVeto(unit, "refuse", "jammer-cluster", 0.f);
				@task = null;
			} else {
				gJammerPos.insertLast(jsite);
				gJammerAt.insertLast(ai.frame);
			}
		}
		string kind = SiteBuildName(task);
		// Cap redundant same-type factories. tools/combat_events.py (built this
		// session) caught what the earlier bot-lab-request-cooldown fix
		// (BOTLAB_REQUEST_COOLDOWN) missed: that fix only gates the ONE script
		// branch that asks for a bot lab when we have none, but corlab kept
		// getting placed again and again well after the first one existed --
		// 8, even 10 placements inside a few minutes for a single
		// healthy-economy player, gaps as short as 6 seconds apart. Nothing
		// that fast is a rebuild-after-loss; this can only be the stock
		// engine's own DefaultMakeTask independently offering the same
		// factory type to every idle constructor, with nothing on the script
		// side capping how many of one type we actually want. CCircuitDef is
		// owned per CCircuitAI instance (see Air.as's own note on this), so
		// .count here is THIS player's own standing+in-progress count, not
		// the team's.
		// apexearth's T2 rush stalling at 18m traced (fresh-context agent
		// review, 2026-08-06) to exactly this cap: a constructor legitimately
		// pulled off the advanced-lab build by real threat (con-veto abandon,
		// threat=12) tried to resume the SAME single in-progress build once
		// safe, and this cap refused it every time as if it were requesting
		// a brand new redundant factory -- rerouting to factory-cap-fallback-
		// mex instead of finishing the T2 lab, repeatedly, well past the
		// factory-cap threat window's own frame. task.GetUnits() is the set
		// of units ALREADY on this task; a nonzero count means this is a
		// build already underway, not a new request, and can't be redundant
		// by definition -- exempt it from both the count cap and the spacing
		// cooldown, which exist only to stop DefaultMakeTask independently
		// offering a brand new factory to every idle constructor.
		//
		// A different fresh-context agent later flagged this exemption as a
		// possible contributor to Cortex's drop from a documented 96.3% peak
		// (2a9613e) to 68.8%. Tested directly: reverting this AND the
		// resource-crisis block below to a 16-game Cortex mirror (same
		// seeds as the 68.8% baseline) gave 62.5% -- no recovery, slightly
		// worse if anything. Hypothesis rejected by data; restored.
		if ((kind == "factory") && (task !is null) && (task.GetUnits().length() == 0)) {
			const CCircuitDef@ wantFac = task.buildDef;
			if (wantFac !is null) {
				const int id = wantFac.id;
				const bool tracked = (id >= 0) && (uint(id) < gNextFactoryRequest.length());
				const bool tooSoon = tracked && (ai.frame < gNextFactoryRequest[id]);
				if ((wantFac.count >= FactoryTypeCap()) || tooSoon) {
					++gConRefused;
					LogConVeto(unit, "refuse", "factory-cap", float(wantFac.count));
					// Previously just @task = null here, which (per CIdleTask's own
					// contract, see the function-level comment above) leaves the
					// unit fully idle until the next idle sweep. Redirect to
					// expansion first -- see FallbackMex's own comment for the
					// traced mechanism and evidence.
					IUnitTask@ fallback = FallbackMex(unit);
					@task = fallback;
					if (fallback !is null)
						kind = "mex";
				} else if (tracked) {
					gNextFactoryRequest[id] = ai.frame + FACTORY_REQUEST_SPACING;
				}
			}
		}
		if ((task !is null) && (kind != "")) {
			const AIFloat3 site = task.GetBuildPos();
			float heat = ThreatFor(unit, site);
			if (kind == "mex")
				heat = MexHeat(site, heat);
			if (heat > CON_THREAT_VETO) {
				++gConRefused;
				LogConVeto(unit, "refuse", kind, heat);
				// CIdleTask assigns whatever comes back, so unlike the abandon
				// path above this one can hand over a task the engine already
				// holds -- a mex the same constructor reads as cold.
				if (kind == "mex") {
					IUnitTask@ other = SaferMex(unit, task);
					if (other !is null)
						return other;
				}
				IUnitTask@ post = ContestDefence(unit, kind, heat, task.GetBuildPos());
				if (post !is null)
					return post;
				// ConStrike (which can trigger Fortify/dig-in once TROUBLE_HITS is
				// reached) previously fired unconditionally on every refusal, even
				// when SaferMex/ContestDefence immediately found a working
				// alternative one line later -- three routine successful reroutes
				// (business as usual, not persistent blocking) could trip the same
				// threshold as three genuine repeated failures. apexearth, watching
				// a game: "i see us making too many t1.5 defenses and advanced
				// energy converters before we've even captured all our backline
				// mexes." Moved to only the true-failure path, where no alternative
				// was found at all.
				ConStrike(unit);
				@task = null;
			}
		}
	}
	// Observed: a commander stands next to reclaimable metal with an empty bank
	// and keeps its build task instead of eating it. It is not IDLE -- it holds a
	// task it cannot afford -- so the idle-only path below never fired. When
	// metal is actually empty, reclaiming beats standing still: it is the only
	// thing that unblocks the task it is already holding.
	// DIAGNOSTIC, apexearth: "We're totally out of metal and we have three
	// construction turrets helping to build something, but we don't even have
	// the metal to build it. One of those conturrets could have been
	// reclaiming... basically - if you have <2% metal and reclaim is in your
	// vicinity - reclaim!" IBuilderTask::Reevaluate's own doc comment says it
	// fires "for as long as the builder is away from its build position" --
	// unclear whether an ALREADY-ARRIVED, actively-assisting nano turret ever
	// reaches AiMakeTask again at all, as opposed to a mobile constructor
	// walking to a site. Logging whether this branch is even entered for a
	// static/turret unit while metal-empty, before building a new redirect
	// mechanism blind.
	//
	// Both this and the rich-pile block below are now isComm-gated. They were
	// not until 2026-08 -- but GetWreckValueAt/GetBestWreckPos were dead all
	// last session (CircuitAI::metalRes only ever assigned on resign, so both
	// always returned zero/invalid), so nothing chased a pile from here for
	// ANYONE, commander included, and that masked this being reachable at all.
	// Fixing the underlying binding unmasked it immediately: apexearth,
	// watching live, "something makes our commanders all run out to the front
	// line - maybe they're going for the reclaim - they should prioritize
	// making those early game mexes." The rich-pile block below is explicitly
	// the one case in this function that DISPLACES an already-assigned task --
	// exactly the commander's early mex task from DefaultMakeTask.
	if (!isComm && aiEconomyMgr.isMetalEmpty && (ai.frame >= gNextMetalEmptyDiag)) {
		gNextMetalEmptyDiag = ai.frame + 10 * SECOND;
		AiLog(Factory::T() + "apex: metal-empty-diag " + unit.circuitDef.GetName()
			+ " static=" + (!unit.circuitDef.IsMobile() ? "1" : "0")
			+ " hasTask=" + ((unit.task !is null) ? "1" : "0"));
	}
	if (!isComm && !isAdvCon && aiEconomyMgr.isMetalEmpty && (ai.frame >= gNextWreck)) {
		gNextWreck = ai.frame + 3 * SECOND;
		const AIFloat3 here = unit.GetPos(ai.frame);
		const AIFloat3 near = ai.GetBestWreckPos(here, WRECK_SEARCH, 15.f);
		// apexearth, watching live: "even our advanced cons are chasing wrecks
		// which are dangerous." Same fix as the commander exclusion above,
		// generalized: unmasked by the same metalRes fix, this now finds real
		// piles and had no idea whether the pile sits somewhere safe. Reuse
		// the same ThreatFor/CON_THREAT_VETO check mex dispatch already uses.
		if ((near.x >= 0.f) && (ThreatFor(unit, near) <= CON_THREAT_VETO)) {
			NoteWreckSeen(ai.GetWreckValueAt(near, WRECK_RADIUS));
			IUnitTask@ rec = aiBuilderMgr.Enqueue(TaskB::Reclaim(
					Task::Priority::HIGH, near, 400.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
			if (rec !is null)
				return rec;
		}
	}
	// The one case that DOES displace real work. Everything above this point is
	// strictly additive by design; a rich corpse pile next to us is the exception,
	// because the metal it returns exceeds anything the interrupted task was
	// producing in the same seconds -- true for an ordinary constructor, not for
	// a commander whose displaced task is the early mex expansion the team's
	// whole economy depends on, nor for an advanced one whose displaced task is
	// a moho. See the isComm note above the metal-empty block.
	if (!isComm && !isAdvCon && (ai.frame >= gNextWreck)) {
		const AIFloat3 self = unit.GetPos(ai.frame);
		if (OnMap(self)) {
			// Gate on the field's TOTAL value, then aim at its richest body so the
			// reclaim circle lands on the corpses rather than on a tree.
			const float pile = ai.GetWreckValueAt(self, WRECK_RICH_R);
			NoteWreckSeen(pile);
			const AIFloat3 rich = (pile >= WRECK_RICH)
					? ai.GetBestWreckPos(self, WRECK_RICH_R, 15.f)
					: AIFloat3(-1.f, 0.f, -1.f);
			// Same threat check as above -- a rich pile is worth an interrupted
			// task, it is not worth walking an advanced constructor into fire
			// for. Checked at the PILE's position, not the constructor's
			// current one: a con already standing somewhere safe should not
			// walk toward a hot pile just because it can see it.
			if ((rich.x >= 0.f) && (ThreatFor(unit, rich) <= CON_THREAT_VETO)) {
				gNextWreck = ai.frame + 3 * SECOND;
				IUnitTask@ fat = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, rich, 1000.f, WRECK_TIMEOUT,
						WRECK_RADIUS, true));
				if (fat !is null) {
					if (ai.frame >= gNextRichLog) {
						gNextRichLog = ai.frame + 30 * SECOND;
						AiLog(Factory::T() + "apex: rich-wreck reclaim pile=" + formatFloat(pile, "", 0, 0));
					}
					return fat;
				}
			}
		}
	}

	if (task !is null)
		return task;   // strictly additive: never displace real work

	// Last resort: everything above declined and we still have metal. Buys
	// energy, not defence -- what this spends is constructor time, and a con
	// part-way through a 680-metal/14,000-energy turret cannot take the mex
	// upgrade that frees up thirty seconds later. See CHANGES.md 2026-08-07.
	if (!isComm && !aiEconomyMgr.isMetalEmpty && gHomeSet
		&& !EnergyWasting() && (ai.frame >= gNextMetalFullDef))
	{
		CCircuitDef@ gen = Factory::gHaveT2
				? SideDef3(armadvsol, coradvsol, legadvsol)
				: SideDef3(armsolar, corsolar, legsolar);
		if ((gen is null) || !gen.IsAvailable(ai.frame))
			@gen = SideDef3(armsolar, corsolar, legsolar);
		if ((gen !is null) && gen.IsAvailable(ai.frame)) {
			IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY,
					Task::Priority::NORMAL, gen, gHomePos, SQUARE_SIZE * 8));
			if (post !is null) {
				gNextMetalFullDef = ai.frame + METAL_FULL_DEF_PERIOD;
				AiLog(Factory::T() + "apex: metal-full-fallback " + unit.circuitDef.GetName()
					+ " -> " + gen.GetName());
				return post;
			}
		}
	}

	// Clearing our own obsolete buildings. Both cases are the same act -- pick
	// one of OUR structures and reclaim it -- so they share ObsoleteReclaim();
	// what differs is only which defs and where. See its comment for the gates.
	if (!isComm) {
		IUnitTask@ tidy = ObsoleteReclaim(unit);
		if (tidy !is null)
			return tidy;
	}

	// Reached by an idle builder, and by one whose only offer was refused above.
	// Rate-limited so a field of them does not each run their own scan every tick.
	// isComm-gated same as the rest of this function's wreck-chasing -- this
	// was the one remaining ungated path that could hand a self-initiated
	// reclaim task back to a commander whose real task was rejected above.
	//
	// Rez bots only. For every other constructor this path was pure pre-emption:
	// DefaultMakeTask offers them a RECLAIM anyway (isResurrect is false for
	// them -- see the REZ_WRECK_PERIOD comment), so returning one HERE does not
	// add reclaim, it just jumps the queue ahead of the mex expansion that lives
	// in DefaultMakeTask. Rez bots still need the pre-empt, because for them the
	// engine's offer is a RESURRECT with a 300s timeout.
	if (isComm || !IsRezzer(unit) || (ai.frame < gNextWreck))
		return task;
	// Stop pre-empting once the reactor the metal was for is already standing.
	// apexearth: "resurrecting a titan is only useful sometimes. oftentimes that
	// sudden boost in resources will pay for an AFUS and that can be a big deal
	// if you don't have an AFUS yet!" So the choice is not reclaim-versus-
	// resurrect in the abstract -- it is what the metal is FOR. Before the
	// advanced reactor exists a field of corpses is the fastest way to it, and
	// after it exists the corpse is worth more standing back up than melted.
	// Falling through hands the bot to DefaultMakeTask, which gives a rezzer a
	// RESURRECT unconditionally (UpdateReclaimTasks takes isResurrect straight
	// from IsAbleToResurrect).
	// ...and only where the bot can afford the time. apexearth: "rezzing takes
	// MUCH LONGER than reclaiming... so if in a dangerous area you should
	// generally reclaim." A resurrect that is interrupted returns nothing at all,
	// where a reclaim banks metal continuously as it goes, so under threat the
	// slow option is not merely worse, it is a total loss.
	if (!IsNavalBuilder(unit)
		&& (ThreatFor(unit, unit.GetPos(ai.frame)) <= CON_THREAT_VETO))
	{
		CCircuitDef@ afus = SideDef3(armafus, corafus, legafus);
		if ((afus !is null) && (afus.count > 0))
			return task;
	}
	gNextWreck = ai.frame + 3 * SECOND;   // corpses decay; do not dawdle

	return EnqueueWreckReclaim(unit, Task::Priority::NORMAL);
}

}  // namespace Builder
