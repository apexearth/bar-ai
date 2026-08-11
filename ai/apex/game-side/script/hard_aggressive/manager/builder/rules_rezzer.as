namespace Builder {

// Rez bots: the three places their needs differ from an ordinary constructor,
// plus the reclaim pre-empt that runs after everything else has declined.

IUnitTask@ RezzerFlee(CCircuitUnit@ unit)
{
	// Rez bots have no buildoptions and cannot dig in like an ordinary
	// constructor -- Fortify/ContestTower never apply to them -- so a hit here
	// means flee, not fortify. And nothing else in the task pipeline ever calls
	// ConDugIn for them, since every rez rule returns early: a bot
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
	return null;
}

IUnitTask@ RezzerFrontSalvage(CCircuitUnit@ unit)
{
	// Rez bots work the DEFENCE LINE, not wherever they happen to stand.
	//
	// apexearth: "if we are losing then reclaim becomes even more important, as
	// those defenses kill enemies on our border -- we can resurrect or reclaim
	// the metal". The corpses pile up where the fighting is, and the search below
	// only reaches 2200 elmos from the bot itself, so a bot idling at home never
	// finds them. Search from the front instead while we are behind.
	if (IsRezzer(unit) && Military::LosingGround() && (ai.frame >= gNextRezWreck)) {
		AIFloat3 front;
		if (Military::FrontLinePos(front)) {
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
	return null;
}

IUnitTask@ RezzerEatCorpse(CCircuitUnit@ unit)
{
	// Eat the corpse rather than rebuild it, before the engine gets the chance
	// to queue a resurrect for this bot.
	if (IsRezzer(unit) && (ai.frame >= gNextRezWreck)
			&& (PreferReclaim() || RezSpotHot(unit) || RezBotExposed(unit))) {
		gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
		IUnitTask@ eat = EnqueueWreckReclaim(unit, Task::Priority::HIGH);
		if (eat !is null)
			return eat;
	}
	return null;
}

IUnitTask@ RezzerPreemptReclaim(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)
{
	// Reached by an idle builder, and by one whose only offer was refused above.
	// Rate-limited so a field of them does not each run their own scan every tick.
	// isComm-gated same as the rest of the pipeline's wreck-chasing -- this
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
