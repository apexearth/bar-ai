namespace Builder {

// Everything AiMakeTask does differently for the commander: its own safety
// rules before work is chosen, and its own vetoes over what work is offered.

// WHY THE COMMANDER IS STANDING STILL.
//
// dev_stats_export samples every commander twice a second and reports the share
// of samples where the engine holds zero orders for it. Measured 2026-08-10 over
// a 10-minute 4v4: ours idle 56.4% of the game against stock BARb's 26.6%.
//
// A returned null from AiMakeTask IS that idle time -- the engine has nothing to
// give the unit and simply waits for the next Reevaluate. Three of this file's
// rules can produce one by REFUSING an offer without supplying a replacement,
// and none of them logged, so the counters below say which.
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
// order. Was 15 -- claimed to be "well above a path query's latency at normal
// speed" without ever being checked against it. CLAUDE.md's own measured gotcha
// says otherwise: "a factory read CountQueued == 0 for 45 consecutive AiUpdates
// ... and then took all 56 queued orders in one tick" at the benchmark's default
// speed cap. At 15 this self-sabotaged: every opening test tonight showed
// "commander stuck on bt13 ... dropping it" firing 6-8 times over 4+ minutes,
// each one aborting a factory order that the engine simply had not gotten to
// yet, restarting the whole assignment from scratch. Set above the documented
// lag with margin, not re-guessed.
const int COMM_STUCK_TICKS = 60;
int gCommStuck = 0;
int gCommUnstuck = 0;
int gNextCommDiag = 0;
IUnitTask@ gCommLastLogged = null;  // see maketask.as's catch-all accept log

// WHY THE COMMANDER IS STANDING THERE, attributed instead of guessed.
//
// The dev gadget's commIdle counts an EMPTY ENGINE COMMAND QUEUE. That is the
// symptom; it cannot say which of the possible causes it is, and every account
// of it so far has been inferred. These four buckets are mutually exclusive and
// cover the space, sampled once per AiUpdate over our own commander:
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
		+ " unstuck=" + gCommUnstuck);
	AiLog(Factory::T() + "apex: comm-diag offers=" + gCommOffers
		+ " offerNull=" + gCommOfferNull
		+ " vetoReclaim=" + gCommVetoReclaim
		+ " vetoHold=" + gCommVetoHold
		+ " endNull=" + gCommEndNull
		+ " idleJobs=" + gCommIdleJobs
		+ " retreatHp=" + gCommRetreatHp + " guard=" + gCommGuard
		+ " idleUnsafe=" + gCommIdleUnsafe + " idleNoJob=" + gCommIdleNoJob);
}

// THE DECISIVE SWITCH. With apex_comm_rules=0 every commander-specific rule in
// this file no-ops and the commander is whatever CBuilderManager makes of it, so
// one A/B says whether our idle time is ours or the engine's. Nothing else in
// AiMakeTask treats the commander specially.
bool CommRules()
{
	return ai.GetTunable("apex_comm_rules", 1.f) > 0.f;
}

IUnitTask@ CommanderTask(CCircuitUnit@ unit, bool isComm)
{
	if (isComm && CommRules()) {
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
			// Above MexGuard: the base is worth more than the extractor the
			// commander happens to be standing next to, and this asks once.
			IUnitTask@ home = HomeTower(unit, isComm);
			if (home !is null)
				return home;
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
			if (flee !is null) {
				++gCommRetreatHp;
				return flee;
			}
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
		// build site.
		//
		// WAS a literal `ai.frame >= 3 * MINUTE`, on the theory that the
		// engine's own AiGetFactoryToBuild path (factory/choose.as) already
		// places the first factory earlier and this would just be a backstop.
		// Traced live, 8v8 +70 handicap: that path's own gate-holding log
		// ("opening gate holds the first factory") never printed ONCE in any
		// of eight players across three matches -- it was never even being
		// asked -- so THIS was the only path that ever requested a factory,
		// and it was dead on a stopwatch regardless of economy. Every lab in
		// that scenario landed in a tight 3.0-4.4m band no matter how income
		// varied, which is the clock, not the game. Gate on the same signal
		// step 2 already uses instead: once OpeningNeedsEconomy() is no
		// longer holding (income cleared, or the escape valve released it),
		// there is nothing left to wait for -- no clock needed, and a wiped
		// team with one surviving constructor re-enters this correctly from
		// its own current economy rather than a fixed elapsed time.
		if (!Factory::HaveAnyFactory() && !OpeningNeedsEconomy()) {
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
				// exists NEARBY -- once none is left, fall through to the
				// factory rebuild below rather than stalling forever waiting
				// for a spot that isn't there.
				//
				// "Nearby" was unbounded: FindOpenMexSpot searches the whole
				// map, so on any real map there is always ANOTHER spot
				// somewhere, just farther away -- this fired every single
				// re-election from 3m onward in every opening test tonight,
				// permanently starving the rebuild below rather than
				// eventually falling through to it. Same reach as step 1 of
				// the opening (OpeningMexReach, apexearth's own "~700 elmo"
				// figure) so a genuinely close mex still wins, and a distant
				// one no longer blocks the one thing this whole block exists
				// to do once the close ones are gone.
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

			// ONE REBUILD, NOT ONE PER TICK. HaveAnyFactory counts FINISHED
			// factories, so while the first lab is still a nanoframe this branch
			// stays true and queues another, and another. Measured live: 127
			// rebuild orders on one player, five bot labs standing at 20 metal/s
			// where PlantsWanted allows one -- and this path enqueues directly, so
			// the plant curve never saw any of them. lab.count includes the
			// nanoframe; the task check covers the gap before construction starts.
			CCircuitDef@ lab = Factory::T1BotLab();
			if ((lab !is null) && lab.IsAvailable(ai.frame)
				&& (lab.count <= 0)
				&& (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::FACTORY)) <= 0))
			{
				IUnitTask@ rebuild = Requests::Take(unit, lab,
						Task::BuildType::FACTORY, Task::Priority::HIGH,
						unit.GetPos(ai.frame), 0.f, 0.f);
				if (rebuild !is null) {
					AiLog(Factory::T() + "apex: commander rebuilding a factory -- we have none");
					return rebuild;
				}
			}
		}
	}
	return null;
}

int gNextCommAssist = 0;
int gNextCommEnergy = 0;
const int COMM_ASSIST_PERIOD = 2 * SECOND;

// THE COMMANDER HAD NO FALLBACK, AND THAT IS WHERE THE IDLE TIME COMES FROM.
//
// Measured with the comm-diag counters above, 16-minute 4v4: across four
// commanders the pipeline ended with nothing 105-407 times, and in every case
// `offerNull` accounts for nearly all of it -- the ENGINE's own commander task
// makers (CBuilderManager::MakeCommPeaceTask / MakeCommDangerTask) declined, and
// our ladder had nothing to add. Our two vetoes are not the cause: three of the
// four players logged 0-2 of them.
//
// Everything at the tail of AiMakeTask that could have answered is gated
// `!isComm` -- MetalFullFallback, TidyObsolete, the dig-in. So the one unit that
// is most of our build power for the whole opening was the only one with no
// last resort at all, and it stood still for 48% of the game against stock's
// 33%.
//
// Ordered by what the metal is worth, not by convenience: take ground, then put
// build power on the line that is producing, then buy energy. apexearth, on the
// same behaviour seen from the other side: "He should stand behind his t1 lab
// and help it build stuff!"
IUnitTask@ CommanderIdleWork(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm || !CommRules())
		return null;
	// A commander that is standing still because it is in danger is handled by
	// the retreat branches above; do not hand it a job that walks it back out.
	// VetoCommanderReclaim and VetoCommanderHold null the engine's offer in order
	// to KEEP the commander on what it is already doing. Handing it fresh work
	// here caused exactly the task switch those vetoes exist to prevent, so a
	// commander genuinely mid-job is left alone. `target` is the nanoframe, which
	// is what separates real work from a task it has not started.
	IUnitTask@ held = unit.task;
	if ((held !is null) && (SiteBuildName(held) != "") && (held.target !is null))
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

// ONE TOWER AT HOME, BEFORE THE COMMANDER WANDERS OFF.
//
// apexearth: "our frontline guys bases die early game because commander walks
// away without building a tower in the base. (just takes 1 to save a whole lot
// of time)"
//
// MexGuard covers extractors, and Fortify answers a constructor that keeps being
// shot at -- neither covers the base itself, and the commander is the only
// builder present in the opening. A Sentry is 85 metal against the whole start
// position, and it only has to exist once: the count check below stops asking
// the moment one stands, so this cannot turn into a porcupine habit.
const float HOME_TOWER_RADIUS = 900.f;
// GetOwnUnitsOfDef only returns FINISHED units, so while the tower was a
// nanoframe this rule saw a bare base and ordered another -- 85 orders across
// four players in one 14-minute game. The gate is what stops that: ask, then
// leave it alone long enough to actually get built.
const int   HOME_TOWER_RETRY  = 90 * SECOND;
int gHomeTowerOrders = 0;
int gNextHomeTower = 0;
// THE ORDER WE ALREADY PLACED. The retry gate above bounds how OFTEN this asks,
// not how many orders can be outstanding, and the standing-unit test cannot see
// a tower that was ordered and never built -- so a base whose tower never gets
// made re-orders one every 90s forever. Measured on team 1: four orders in five
// minutes with none standing. Holding the task handle is the same pattern
// gMexTasks and gAimTask use, and IsDefenceTaskLive is its existing test.
IUnitTask@ gHomeTowerTask = null;

IUnitTask@ HomeTower(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm || !CommRules() || !gHomeSet || (ai.frame < gNextHomeTower))
		return null;
	// STEP 4 COMES AFTER STEP 3. This rule sits above DefaultMakeTask, so
	// during the opening it can take the commander off the economy the first
	// lab is waiting on. The turret is cheap; the commander's time here is not.
	//
	// OpeningNeedsEconomy() alone is not "step 3 is done" -- it is only the
	// step-2 energy gate, and its own escape valve releases the moment no
	// energy task is in flight, which can be almost immediately if the single
	// opening builder simply hasn't been asked for another one yet. Measured
	// 8v8 +70 handicap: the gate released at 1.2m with no factory anywhere,
	// and this rule then won the commander's turn on every re-election ahead
	// of the (also newly eligible) factory offer -- armllt requested at 1.2,
	// 1.6, 2.7, 3.5, 3.8m while the T1 lab didn't land until 3.5-4.0m, team-
	// wide. Gate on the actual step-3 condition, not its proxy.
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
	// A BASE ON THE LINE NEEDS THE JAMMER TOO. apexearth: "green always dies
	// first... they're so rarely making good frontline and usually never have a
	// jammer. Their base basically IS on the frontline."
	//
	// PlaceLineJammer already exists and was only ever called when a porcupine
	// tower went up on the line -- which for a player whose base IS the line
	// happens rarely, so the one position that most needs the cover never got it.
	// Reusing the same function rather than writing a second jammer rule.
	Military::PlaceLineJammer(site);
	++gHomeTowerOrders;
	AiLog(Factory::T() + "apex: home tower " + tower.GetName()
		+ " #" + gHomeTowerOrders + " -- base had none");
	return post;
}

IUnitTask@ CommanderMexGuard(CCircuitUnit@ unit, bool isComm)
{
	// The commander plants most of the early mexes, and was the ONE builder
	// forbidden from protecting them: MexGuard lives inside the !isComm block
	// below, so every mex the commander made stood bare unless some other
	// constructor happened past. apexearth, watching: "the commander here makes
	// 5 mexes and doesnt build a sentry tower next to any of them."
	// ANY builder, ANY tier: an unguarded extractor is the thing being asked
	// about, not who happens to be free. apexearth: "If we have an unguarded mex
	// then guarding it should be a boosted priority."
	//
	// Self-limiting, which is what lets it sit high in the pipeline: it answers
	// only for an extractor with no cover and no pending cover, so each mex draws
	// one turret and then stops asking. apex_mex_sentry turns it down for games
	// against humans, who raid far less than the AI does.
	if (ai.GetTunable("apex_mex_sentry", 1.f) <= 0.f)
		return null;
	if (isComm && !CommRules())
		return null;
	// STEP 4 COMES AFTER STEP 3, same as HomeTower. This rule has no phase
	// exclusion for the COMMANDER specifically (any other builder guarding a
	// mex is not the sole opening builder, so it costs nothing there): traced
	// live, 8v8 +70 handicap -- the commander took 4 mexes by 0.6m, then spent
	// 1.2m to 3.8m walking to and building two sentries before the T1 lab was
	// even requested. apexearth still wants the commander guarding mexes it
	// just made; the ordering, not the behaviour, was wrong.
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
		const float d = me.distance2D(at);
		if (!have || (d < bestD)) {
			bestD = d;
			bare = at;
			have = true;
		}
	}
	if (!have)
		return null;

	CCircuitDef@ tower = MexGuardTower(unit, bare);
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
	// Measured without it: 170 sentries for a player holding one extractor.
	NoteDigOrder(site);
	++gMexSentries;
	if (gMexSentries <= 3 || (gMexSentries % 10 == 0)) {
		AiLog(Factory::T() + "apex: mex sentry #" + gMexSentries + " "
			+ tower.GetName() + " on a bare extractor, mex=" + mex.count);
	}
	return post;
}

IUnitTask@ VetoCommanderReclaim(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)
{
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
	// does not release on its own. apexearth, watching a 6v6: "'calm phil' didn't
	// make a lab until 4m in... he was walking around unsure what to do with
	// himself." That player took 4.1 minutes to a first factory against 1.0-2.8
	// for the other five.
	const bool firstFactory = (task !is null)
			&& (task.GetType() == Task::Type::BUILDER)
			&& (task.GetBuildType() == Task::BuildType::FACTORY)
			&& !Factory::HaveAnyFactory();
	if (isComm && CommRules() && !firstFactory && (task !is null) && (task.GetType() == Task::Type::BUILDER)) {
		IUnitTask@ held = unit.task;
		const string heldKind = SiteBuildName(held);
		// HOLD ONLY REAL WORK. `held` names a build type from the moment the task
		// exists, but `target` is the nanoframe -- null until something is
		// actually standing there. Vetoing on the name alone meant the commander
		// refused every new job while "holding" a task it had not started, and
		// AiMakeTask returning null leaves it with nothing to do at all.
		// apexearth, twice, watching the opening: "the commander stands around
		// for some time after making the first mex, takes him a while to figure
		// out what to do next." Measured: 14 comm-hold vetoes before minute 7,
		// in bursts of seven, five game-seconds apart.
		//
		// EXCEPT the walk to the first factory itself, which this same reasoning
		// left completely unprotected: `target` stays null for the whole walk, so
		// `reallyWorking` reads false the entire time the commander is en route,
		// and the very next tick that proposes anything else (the opening gate
		// flip-flopping, a mex guard, a home tower) swapped the commander off the
		// walk with nothing to show for it -- there is no second builder in the
		// opening to pick the abandoned task back up, so it sat at workers=0 for
		// the rest of the game. Measured live: the FIRST factory task offered,
		// five seconds in, was still unclaimed at game end. A factory is the one
		// build in the opening worth protecting mid-walk on its own name alone,
		// same as firstFactory above already refuses to let a held MEX block it
		// from being taken in the first place -- this is that same exemption
		// applied to KEEPING it once assigned.
		const bool holdingFirstFactory = (held !is null)
				&& (held.GetType() == Task::Type::BUILDER)
				&& (held.GetBuildType() == Task::BuildType::FACTORY)
				&& !Factory::HaveAnyFactory();
		const bool reallyWorking = holdingFirstFactory
				|| ((held !is null) && (held.target !is null));
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
