namespace Builder {

// Work already in progress, and the two reasons to drop it.

IUnitTask@ HoldDefenceInProgress(CCircuitUnit@ unit, bool isComm)
{
	// Let a constructor FINISH the defence it already started.
	//
	// AiMakeTask re-decides from scratch on every call, and IBuilderTask::
	// Reevaluate swaps the unit's task whenever we hand back a different BUILD
	// TYPE. Fortify only fires while ConDugIn() is true, i.e. while the con is
	// being shot at -- so the moment the shooting stops the pipeline offers a
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
	// THE THREAT GATE EXCLUDES EXACTLY THE FRONT. A site on the line is contested
	// by definition, so this hold fires for a mex guard at home and never for the
	// Brain's front request -- which is why 7 of 235 front orders became towers
	// while towers at home were built normally. Arm under test: hold a FORWARD
	// defence task through the walk as well. The front curve already sits a
	// setback inside our own side of the crossing, which is what is supposed to
	// make the site survivable.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (busy.GetType() == Task::Type::BUILDER)
			&& (busy.GetBuildType() == Task::BuildType::DEFENCE))
		{
			const AIFloat3 at = busy.GetBuildPos();
			if (ThreatFor(unit, at) <= CON_THREAT_VETO)
				return busy;
			if ((ai.GetTunable("apex_hold_front", 0.f) > 0.f) && OnMap(at)
				&& (Military::OnBorder(at) || Military::NearFront(at)))
			{
				return busy;
			}
		}
	}
	return null;
}

IUnitTask@ AbandonUnsafeSite(CCircuitUnit@ unit, bool isComm)
{
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
	return null;
}

IUnitTask@ HoldWorkInProgress(CCircuitUnit@ unit, bool isComm)
{
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
	return null;
}

}  // namespace Builder
