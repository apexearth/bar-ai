namespace Builder {

// Everything AiMakeTask does differently for the commander: its own safety
// rules before work is chosen, and its own vetoes over what work is offered.

IUnitTask@ CommanderTask(CCircuitUnit@ unit, bool isComm)
{
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
	return null;
}

IUnitTask@ CommanderMexGuard(CCircuitUnit@ unit, bool isComm)
{
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
	return null;
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
	if (isComm && (task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == Task::BuildType::RECLAIM)
		&& (aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame)) >= 0))
	{
		@task = null;
	}
	return task;
}

IUnitTask@ VetoCommanderHold(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)
{
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
	return task;
}

}  // namespace Builder
