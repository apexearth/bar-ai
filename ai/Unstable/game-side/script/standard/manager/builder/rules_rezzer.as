namespace Builder {

// Rez bots: the three places their needs differ from an ordinary constructor,
// plus the reclaim pre-empt that runs after everything else has declined.

IUnitTask@ RezzerFlee(CCircuitUnit@ unit)
{
	// Rez bots have no buildoptions and cannot dig in like an ordinary
	// constructor -- Fortify/ContestTower never apply to them -- so a hit here
	// means flee, not fortify. Nothing else in the pipeline calls ConDugIn for
	// them either, since every rez rule returns early.
	//
	// RezSpotHot/PreferReclaim below only gate which task gets ASSIGNED, and
	// RezSpotHot's ThreatFor falls back to PastFront() geometry once the
	// position threat map reads zero (the common case -- see ThreatFor's own
	// comment), so an enemy push short of the front's 72% line still reads
	// "safe" while standing on the bot. ConDugIn's HP-drop tracking is a real
	// positional signal instead: something shot us, HERE. One hit is enough --
	// unlike an armed constructor, a rez bot cannot dig in, only leave.
	if (IsRezzer(unit)) {
		ConDugIn(unit);   // side effect: refreshes gConHits/gConHp for this bot
		if (gConHits[ConSlot(unit)] > 0) {
			IUnitTask@ flee = Retreat(unit);
			if (flee !is null) {
				// TROUBLE_WINDOW holds this true for up to 90s per hit, so without a
				// log throttle this re-logs on every AiMakeTask re-entry while fleeing.
				// Retreat() (sitesafety.as) reuses the held RETREAT task instead of
				// re-enqueuing fresh each time -- EnqueueRetreat itself always
				// allocates a new CRetreatTask with no dedup.
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

// BATTLEFIELD MEDICS (apexearth 2026-08-21): a share of the rez fleet stays
// with the army instead of working the corpse geometry -- repair the wounded
// where the fight is, eat the aftermath where it fell. Deterministic by unit
// id so the split is stable across elections; the flee rule above still wins,
// so a medic under fire leaves like any other rez bot.
bool MedicBot(CCircuitUnit@ unit)
{
	const float share = ai.GetTunable("apex_medic_share", TUNE_MEDIC_SHARE);
	if (share <= 0.f)
		return false;
	return float(int(unit.id) % 100) < share * 100.f;
}

int gNextMedicLog = 0;

IUnitTask@ RezzerMedic(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit) || !MedicBot(unit))
		return null;
	AIFloat3 lane = Military::LanePos();
	if (!OnMap(lane) || (lane.SqLength2D() < 1.f))
		return null;
	// apexearth 2026-08-22: "medic bots also need to stay safe and not die."
	// The lane is the army's staging anchor -- i.e. where the shooting is. Hold
	// station this far BEHIND it, toward home, so the wounded step back to the
	// medic instead of the medic standing in the fight. Still inside apex_medic_r
	// of the line, so the repair reach is unchanged.
	const float setback = ai.GetTunable("apex_medic_setback", TUNE_MEDIC_SETBACK);
	if ((setback > 0.f) && Builder::gHomeSet) {
		AIFloat3 toHome = Builder::gHomePos - lane;
		const float len = sqrt(toHome.SqLength2D());
		if (len > 1.f) {
			const AIFloat3 back = lane + toHome * (setback / len);
			if (OnMap(back))
				lane = back;
		}
	}
	const int slot = ConSlot(unit);
	if (ai.frame < gConNextRepair[slot])
		return null;
	// The staging anchor is meant to be OUR ground; if it currently is not,
	// the medic waits rather than walking into what the army retreated from.
	if (ThreatFor(unit, lane) > CON_THREAT_VETO)
		return null;
	gConNextRepair[slot] = ai.frame + REZ_WRECK_PERIOD;
	const float reach = ai.GetTunable("apex_medic_r", TUNE_MEDIC_R);
	// The wounded near the fight come first, wherever the medic stands now.
	array<CCircuitUnit@>@ hurt = ai.GetOwnDamagedNear(lane, reach);
	if (hurt !is null) {
		CCircuitUnit@ best = null;
		float bestDist = 1.0e18f;
		const AIFloat3 here = unit.GetPos(ai.frame);
		for (uint i = 0; i < hurt.length(); ++i) {
			CCircuitUnit@ u = hurt[i];
			if ((u is null) || (u is unit) || !u.circuitDef.IsMobile())
				continue;
			const float d = here.distance2D(u.GetPos(ai.frame));
			if (d < bestDist) {
				bestDist = d;
				@best = u;
			}
		}
		if (best !is null) {
			if (ai.frame >= gNextMedicLog) {
				gNextMedicLog = ai.frame + 60 * SECOND;
				AiLog(Factory::T() + "apex: medic moving to repair at the line");
			}
			return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::NORMAL, best));
		}
	}
	// Nobody hurt: hold station at the lane, eating whatever the last fight
	// left there. The area reclaim is also the move order.
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (here.distance2D(lane) > reach)
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(
				Task::Priority::NORMAL, lane, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
	return null;
}

uint gRezSweepIdx = 0;
int gNextRezSweepLog = 0;

IUnitTask@ RezzerFrontSalvage(CCircuitUnit@ unit)
{
	// Rez bots work the DEFENCE LINE, not wherever they happen to stand. The
	// corpses pile up where the fighting is, and the search below only reaches
	// 2200 elmos from the bot itself, so a bot idling at home never finds them.
	// Search from the front whenever we are behind, OR whenever nothing local
	// is worth eating -- a LosingGround()-only gate left rez bots entirely
	// home-bound while winning, which is exactly when the front piles up the
	// most corpses.
	if (IsRezzer(unit) && (ai.frame >= gNextRezWreck)
			&& (Military::LosingGround() || (ai.GetBestWreckPos(unit.GetPos(ai.frame), WRECK_SEARCH, WRECK_MIN).x < 0.f))) {
		gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
		// THE WHOLE LINE, NOT ONE POINT -- and blind where vision is missing.
		// A single FrontLinePos search per period left most of a 10k-elmo
		// front untouched, and wreck queries are LOS-gated (a corpse field
		// nobody stands in reads empty), so the battlefield accumulated
		// thousands of features that the engine then pays for every frame --
		// measured live (8v8, min 34->55): engine sim 15->28ms/frame, the
		// late-game slowdown itself. Successive sweeps rotate across the
		// front stretches; a stretch with no KNOWN wreck is swept blind --
		// the bot's own arrival provides the vision and the area reclaim
		// eats whatever stands there. An empty blind sweep costs one walk by
		// a bot that had nothing local to do anyway.
		array<AIFloat3> line;
		if (Military::FrontLineSpots(line, WRECK_RADIUS * 1.5f, WRECK_RADIUS)
			&& (line.length() > 0))
		{
			for (uint tryN = 0; tryN < line.length(); ++tryN) {
				const AIFloat3 stretch = line[gRezSweepIdx % line.length()];
				++gRezSweepIdx;
				if (ThreatFor(unit, stretch) > CON_THREAT_VETO)
					continue;
				AIFloat3 spoil = ai.GetBestWreckPos(stretch, WRECK_SEARCH, WRECK_MIN);
				if (spoil.x < 0.f)
					spoil = stretch;
				IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
				if (harvest !is null) {
					if (ai.frame >= gNextRezSweepLog) {
						gNextRezSweepLog = ai.frame + 60 * SECOND;
						AiLog(Factory::T() + "apex: rez sweep stretch "
							+ (gRezSweepIdx % line.length()) + "/" + line.length());
					}
					return harvest;
				}
				break;
			}
		}
		AIFloat3 front;
		if (Military::FrontLinePos(front)) {
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

// The floor for a rez bot that has nothing else claiming it: repair a nearby
// damaged mobile unit rather than stand still. Rez bots are explicitly a
// rez/repair/reclaim unit (armrectr/cornecro/legrezbot's own tooltip), but
// nothing in the engine ever proposes this for them -- CBuilderManager only
// registers a damagedHandler for builders/rez-bots taking damage themselves
// and for static structures (BuilderManager.cpp's InitHandlers), never for an
// ordinary mobile combat unit, so no REPAIR task is ever created for one no
// matter how long it stands there hurt. Reuses WRECK_SEARCH above, the same
// bot's own existing search reach, rather than a new number -- Assist::
// ASSIST_RANGE would fit as well but assist.as is included after builder.as
// (see main.as), so its constants are not visible here yet.
//
// Ranked ABOVE the tree-reclaim floor (IdleFeatureReclaim in maketask.as):
// keeping an existing unit alive is worth more than a handful of scrap metal,
// and this returns null immediately whenever nothing needs it, so it never
// competes with real work above it in the pipeline.
//
// Gated PER BOT (via ConSlot), not by one shared clock. A single global gate
// here (as gNextRezWreck/gNextWreck use, correctly, for their own expensive
// scans) caps the whole team to one new repair assignment per REZ_WRECK_PERIOD
// regardless of how many rez bots are idle -- during a fight where several
// units take chip damage at once, that serializes response across the whole
// squad instead of each idle bot claiming its own nearest target immediately.

IUnitTask@ RezzerRepairNearby(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit))
		return null;
	const int slot = ConSlot(unit);
	if (ai.frame < gConNextRepair[slot])
		return null;
	gConNextRepair[slot] = ai.frame + REZ_WRECK_PERIOD;

	const AIFloat3 here = unit.GetPos(ai.frame);
	array<CCircuitUnit@>@ hurt = ai.GetOwnDamagedNear(here, WRECK_SEARCH);
	if ((hurt is null) || (hurt.length() == 0))
		return null;

	CCircuitUnit@ best = null;
	float bestDist = WRECK_SEARCH;
	for (uint i = 0; i < hurt.length(); ++i) {
		CCircuitUnit@ u = hurt[i];
		if ((u is null) || (u is unit))
			continue;
		const float dist = here.distance2D(u.GetPos(ai.frame));
		if (dist >= bestDist)
			continue;
		bestDist = dist;
		@best = u;
	}
	if (best is null)
		return null;
	if (ThreatFor(unit, best.GetPos(ai.frame)) > CON_THREAT_VETO)
		return null;

	return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::NORMAL, best));
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
	// The choice is not reclaim-versus-resurrect in the abstract -- it is what
	// the metal is FOR. Before the advanced reactor exists a field of corpses is
	// the fastest way to it; after it exists the corpse is worth more standing
	// back up than melted. Falling through hands the bot to DefaultMakeTask,
	// which gives a rezzer a RESURRECT unconditionally (UpdateReclaimTasks takes
	// isResurrect straight from IsAbleToResurrect).
	//
	// ...and only where the bot can afford the time: a resurrect that is
	// interrupted returns nothing at all, where a reclaim banks metal
	// continuously as it goes, so under threat the slow option is a total loss.
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
