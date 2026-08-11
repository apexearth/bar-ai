namespace Builder {

// Metal on the ground, and the two last-resort jobs for a constructor that
// everything above declined.

IUnitTask@ ScavengeWrecks(CCircuitUnit@ unit, bool isComm, bool isAdvCon)
{
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
	return null;
}

IUnitTask@ MetalFullFallback(CCircuitUnit@ unit, bool isComm)
{
	// Last resort: everything above declined and we still have metal. Buys
	// energy, not defence -- what this spends is constructor time, and a con
	// part-way through a 680-metal/14,000-energy turret cannot take the mex
	// upgrade that frees up thirty seconds later. See CHANGES.md 2026-08-07.
	if (!isComm && !aiEconomyMgr.isMetalEmpty && gHomeSet
		&& !EnergyWasting() && (ai.frame >= gNextMetalFullDef))
	{
		CCircuitDef@ gen = SolarDef();
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
	return null;
}

IUnitTask@ TidyObsolete(CCircuitUnit@ unit, bool isComm)
{
	// Clearing our own obsolete buildings. Both cases are the same act -- pick
	// one of OUR structures and reclaim it -- so they share ObsoleteReclaim();
	// what differs is only which defs and where. See its comment for the gates.
	if (!isComm) {
		IUnitTask@ tidy = ObsoleteReclaim(unit);
		if (tidy !is null)
			return tidy;
	}
	return null;
}

}  // namespace Builder
