namespace Requests {

// SURPLUS ASSISTERS ARE PEELED, NOT WAITED OUT. The engine only re-elects a
// builder while it is AWAY from its build position (IBuilderTask::Reevaluate),
// so a con parked at a big site assists until completion however many wants
// starve -- apexearth, watching an afus: "~30+ cons all focus... soon as it
// was done we spread out to make ~7 or 8 needed advanced converters. The
// issue is elections just don't happen often enough." Every slow update this
// detaches workers beyond the site's ETA-derived count (RemoveUnit hands
// them to the idle task, which is a fresh election next frame). Only sites
// with a standing nanoframe: walkers already re-elect on their own.
int gPeeled = 0;
int gNanoFedPeel = 0;   // sites trimmed to the founder because the ring is on them
int gNextPeelLog = 0;
void PeelSurplus()
{
	if (ai.GetTunable("apex_assist_release", TUNE_ASSIST_RELEASE) <= 0.f)
		return;
	int peeledNow = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		if ((t.buildDef is null) || (t.target is null))
			continue;
		array<CCircuitUnit@>@ crew = t.GetUnits();
		if (crew is null)
			continue;
		// The same feed-derived crew the join rung authorises, so a peeled
		// worker cannot walk straight back on: peeling against one number
		// while SiteWorkerCap admitted against another only cycled them.
		// Big energy peels to the SAME number the join rung admits (its
		// cost-derived crew), or the two rungs cycle the same hands.
		int wantN = IsBigEnergy(t.buildDef)
				? int(SiteWorkerCap(t.buildDef))
				: int(FeedableCrew(t.buildDef));
		// THE FOUNDER NEVER LEAVES. A ring seen lathing the frame trims the
		// crew to one hand, never to none: turrets work their nearest target
		// and an unattended frame decays (apexearth 2026-09-20: "those nano
		// turrets don't seem to give a crap").
		if ((wantN > 1) && NanoFed(t, crew.length(), 0.f, 0.f)) {
			wantN = 1;
			++gNanoFedPeel;
			const AIFloat3 fAt = t.GetBuildPos();
			AiLog(Factory::T() + "apex: ring-trim " + t.buildDef.GetName()
				+ " at=" + int(fAt.x) + "," + int(fAt.z)
				+ " done=" + formatFloat(Progress(t), "", 0, 2)
				+ " crew=" + crew.length()
				+ " seen=" + int(RingSeen(t)));
		}
		int surplus = int(crew.length()) - wantN;
		// A few at a time, largest ids first -- the same stampede guard the
		// hold rung uses: everyone reads the same pre-order counts.
		const int PEEL_PER_TICK = 3;
		for (int k = 0; (k < surplus) && (k < PEEL_PER_TICK); ++k) {
			CCircuitUnit@ top = null;
			for (uint c = 0; c < crew.length(); ++c) {
				CCircuitUnit@ u2 = crew[c];
				if (u2 is null)
					continue;
				if ((top is null) || (int(u2.id) > int(top.id)))
					@top = u2;
			}
			if (top is null)
				break;
			t.RemoveUnit(top);
			Builder::NotePeel(int(top.id));
			++gPeeled;
			++peeledNow;
			@crew = t.GetUnits();
			if (crew is null)
				break;
		}
	}
	if ((peeledNow > 0) && (ai.frame >= gNextPeelLog)) {
		gNextPeelLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: peeled " + peeledNow
			+ " surplus assister(s) back to the auction (total " + gPeeled
			+ " nanoFed=" + gNanoFedPeel + ")");
	}
}

// BACKUP CONSOLIDATION (apexearth 2026-08-30, six energy frames rising at
// once, one at ETA 64m, one abandoned: "if it does happen again, they should
// all focus their efforts on the most efficient energy project. (taking in
// to account the TTE efficiency (time to energy))"). The energy fold stops
// the fan-out at request time; this rung is for the state where several
// manned energy sites are ALREADY rising. While the best time-to-energy site
// still has room for hands, workers on every other energy site go back to
// the auction (RemoveUnit -> idle -> fresh election), where the fold sends
// them to that best site. The worse frames stand part-paid and unmanned;
// they are adopted in TTE order once the best one saturates or finishes.
int gConsolidated = 0;
int gNextConsLog = 0;
void ConsolidateEnergy()
{
	if (ai.GetTunable("apex_assist_release", TUNE_ASSIST_RELEASE) <= 0.f)
		return;
	// Same bar as the fold: wind and other trinkets finish in seconds and
	// are not worth churning hands over.
	float minM = ai.GetTunable("apex_join_min_m", TUNE_JOIN_MIN_M);
	if (minM > 150.f)
		minM = 150.f;
	IUnitTask@ bestT = null;
	float bestScore = 0.f;
	uint sites = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		const CCircuitDef@ d = t.buildDef;
		if ((d is null) || (t.target is null) || (d.costM < minM))
			continue;   // walkers re-elect on their own
		const float makeE = aiEconomyMgr.GetEnergyMake(d);
		if (makeE <= 1.f)
			continue;
		const uint busy = Workers(t);
		if (busy == 0)
			continue;
		++sites;
		const float score = Market::EnergyTTEWith(makeE, d.costM, d.costE, Progress(t), busy);
		if ((bestT is null) || (score > bestScore)) {
			bestScore = score;
			@bestT = t;
		}
	}
	if ((sites < 2) || (bestT is null))
		return;
	// Only while the best site can absorb them; otherwise peeled hands
	// would bounce between sites.
	if (Workers(bestT) >= SiteWorkerCap(bestT.buildDef))
		return;
	int moved = 0;
	const int PEEL_PER_TICK = 3;
	for (uint i = 0; (i < gLive.length()) && (moved < PEEL_PER_TICK); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t is bestT)
			|| (t.GetType() != Task::Type::BUILDER))
			continue;
		const CCircuitDef@ d = t.buildDef;
		if ((d is null) || (t.target is null) || (d.costM < minM)
			|| (aiEconomyMgr.GetEnergyMake(d) <= 1.f))
			continue;
		array<CCircuitUnit@>@ crew = t.GetUnits();
		// Never the last hand: the engine deletes a frame at zero progress the
		// moment no one lathes it, so moving it throws the project away.
		while ((crew !is null) && (crew.length() > 1) && (moved < PEEL_PER_TICK)) {
			CCircuitUnit@ top = null;
			for (uint c = 0; c < crew.length(); ++c) {
				CCircuitUnit@ u2 = crew[c];
				if (u2 is null)
					continue;
				if ((top is null) || (int(u2.id) > int(top.id)))
					@top = u2;
			}
			if (top is null)
				break;
			t.RemoveUnit(top);
			Builder::NotePeel(int(top.id));
			++gConsolidated;
			++moved;
			@crew = t.GetUnits();
		}
	}
	if ((moved > 0) && (ai.frame >= gNextConsLog)) {
		gNextConsLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: energy consolidate " + moved
			+ " hand(s) -> " + ((bestT.buildDef !is null)
				? bestT.buildDef.GetName() : "?")
			+ " (total " + gConsolidated + ")");
	}
}

// The def of a live FACTORY request, if any -- so a joiner helps build what
// was actually ASKED. Joining with the joiner's own preferred def is not a
// join: Take() finds no task for that def and creates a second plant.
CCircuitDef@ LiveFactoryDef()
{
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if ((cand is null) || (cand.GetType() != Task::Type::BUILDER))
			continue;
		if (cand.GetBuildType() != Task::BuildType::FACTORY)
			continue;
		const CCircuitDef@ bd = cand.buildDef;
		if (bd is null)
			continue;
		CCircuitDef@ has = ai.GetCircuitDef(bd.id);
		if (has !is null)
			return has;
	}
	return null;
}

}  // namespace Requests
