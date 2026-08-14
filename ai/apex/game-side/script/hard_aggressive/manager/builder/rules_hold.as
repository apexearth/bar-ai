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
	// tower is abandoned. Without this hold, script-placed static defence is
	// accepted but never finished.
	//
	// Deliberately narrow: only a DEFENCE build already in progress, only while
	// its site is not itself dangerous (the abandon checks below still own that
	// case), and never for the commander, which has its own hold rule.
	//
	// THE THREAT GATE EXCLUDES EXACTLY THE FRONT: a site on the line is
	// contested by definition, so this hold fires for a mex guard at home and
	// not for the Brain's front request. apex_hold_front extends the hold to a
	// forward defence task as well, since the front curve sits a setback inside
	// our own side of the crossing that is meant to make the site survivable.
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
			// SiteBuildName deliberately excludes RECLAIM, so the abandon check
			// above never covered it: a destination checked safe ONCE at dispatch
			// is never re-checked during the walk or while reclaiming, and an
			// active battlefield's safety can flip in that time. Same abandon
			// pattern as mex/build above, but no ContestDefence -- building a
			// tower at a corpse pile doesn't fit the same shape as holding a mex.
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
	// DO NOT DISPLACE WORK ALREADY IN PROGRESS.
	//
	// This hook is not only called for an idle builder: IBuilderTask::Reevaluate
	// calls it on every task update for as long as the builder is away from its
	// build position, and the engine swaps the unit's task whenever what we hand
	// back differs in BUILD TYPE. So an optional rule further down the pipeline
	// could otherwise yank a constructor off a site it was walking to, leaving a
	// claimed task nobody works. The veto/abandon checks above have already run,
	// so anything still held here is work the AI still considers safe.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (SiteBuildName(busy) != ""))
			return busy;
		// RECLAIM is deliberately excluded from SiteBuildName (see its comment),
		// which left it unheld here: AbandonUnsafeSite already re-checks safety
		// for a reclaim every tick and refuses it explicitly when it goes hot, so
		// a reclaim that survives that check is exactly as "still wanted" as a
		// mex or an energy building is. Without this, a builder mid-reclaim fell
		// through every tick to a fresh DefaultMakeTask offer, which differs in
		// build type from RECLAIM and so swaps the unit off the walk -- the
		// mex-A/mex-B flip-flop apexearth watched live, just as documented at
		// the top of AiMakeTask for the commander's own hold.
		if ((busy !is null) && (busy.GetType() == Task::Type::BUILDER)
			&& (busy.GetBuildType() == Task::BuildType::RECLAIM))
		{
			return busy;
		}
	}
	return null;
}

}  // namespace Builder
