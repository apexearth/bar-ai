namespace Builder {

// Metal on the ground, and the two last-resort jobs for a constructor that
// everything above declined.

IUnitTask@ ScavengeWrecks(CCircuitUnit@ unit, bool isComm, bool isAdvCon)
{
	// A commander standing next to reclaimable metal with an empty bank is not
	// IDLE -- it holds a task it cannot afford -- so an idle-only path never
	// fires. When metal is actually empty, reclaiming beats standing still: it
	// is the only thing that unblocks the task already held.
	//
	// Both this and the rich-pile block below are isComm-gated. The rich-pile
	// block is explicitly the one case in this function that DISPLACES an
	// already-assigned task -- exactly the commander's early mex task from
	// DefaultMakeTask -- so it must not run for the commander or an advanced
	// constructor, whose displaced task is a moho.
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
		// Same ThreatFor/CON_THREAT_VETO check mex dispatch already uses: a
		// nearby pile is not automatically a safe walk.
		if ((near.x >= 0.f) && (ThreatFor(unit, near) <= CON_THREAT_VETO)) {
			NoteWreckSeen(ai.GetWreckValueAt(near, WRECK_RADIUS));
			IUnitTask@ rec = aiBuilderMgr.Enqueue(TaskB::Reclaim(
					Task::Priority::HIGH, near, 400.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
			if (rec !is null)
				return rec;
		}
	}
	// The one case that DOES displace real work: a rich corpse pile next to us,
	// because the metal it returns exceeds anything the interrupted task was
	// producing in the same seconds. Excluded above for the commander and an
	// advanced constructor, whose displaced task matters more (mex expansion,
	// a moho).
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
	return null;
}

IUnitTask@ MetalFullFallback(CCircuitUnit@ unit, bool isComm)
{
	// Last resort: everything above declined and we still have metal. Buys
	// energy, not defence -- a con part-way through an expensive turret cannot
	// take the mex upgrade that frees up shortly after.
	if (!isComm && !aiEconomyMgr.isMetalEmpty && gHomeSet
		&& !EnergyWasting() && (ai.frame >= gNextMetalFullDef))
	{
		CCircuitDef@ gen = SolarDef();
		if ((gen !is null) && gen.IsAvailable(ai.frame)) {
			IUnitTask@ post = Requests::Take(unit, gen, Task::BuildType::ENERGY,
					Task::Priority::NORMAL, gHomePos, 0.f, SQUARE_SIZE * 8);
			if (post !is null) {
				gNextMetalFullDef = ai.frame + METAL_FULL_DEF_PERIOD;
				AiLog(Factory::T() + "apex: metal-full-fallback " + unit.circuitDef.GetName()
					+ " -> " + gen.GetName());
				return post;
			}
		}
	}
	return null;
}

IUnitTask@ TidyObsolete(CCircuitUnit@ unit, bool isComm)
{
	// Obsolete-building reclaims are enqueued centrally by ObsoleteSweep; an
	// idle constructor receives one through DefaultMakeTask, so nothing is
	// left for this rule to scan.
	return null;
}

}  // namespace Builder
