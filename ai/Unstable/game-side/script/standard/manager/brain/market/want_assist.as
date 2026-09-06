namespace Market {
// Assisting T2+ work is a PRICED want, not an idleness fallback (apexearth
// 2026-08-23: "T1 cons are still not assisting T2 cons, helping build T2+
// buildings, or assisting factories"). A joiner transfers its whole drain
// into a build the market already values at clearing rates; the bill is
// the walk and the occupied time. That beats a marginal solar and loses to
// a fresh mex -- the right ordering by construction.
Want@ ProposeAssist(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	// (The "only lesser cons may assist" gate is gone with the repricing: a
	// role may change how much, never whether. A ceiling con's own upgrade
	// work is now priced against the acceleration below and wins on its own
	// merits, so the ban was deciding an auction the auction can decide.)
	// THE MOST IMPORTANT JOB IN FLIGHT TAKES THE HELP FIRST (apexearth
	// 2026-08-26: "if 1 of them is way more important than the rest, I'm
	// hoping our constructors will assist the building which is the most
	// important"). What follows it is the fallback for work the market never
	// priced: build power compounds, so a worker raising a nano outranks one
	// raising a factory, then serving cons, then a line with a queue.
	CCircuitUnit@ boss = BestJobBoss(unit);
	// A worker raising a FACTORY outranks everything -- one con on the T2
	// plant was the measured bottleneck (apexearth: "we are more efficient
	// when we assist building some things").
	// ONE PASS, not two. The factory walk and the nano walk below it ran the
	// same three filters over the same list in the same order, and the second
	// only ran when the first found nothing -- so whenever no factory is being
	// raised (the common case) the whole worker fleet was walked twice, with a
	// GetPos and a leash test each time. The factory still wins outright and the
	// nano is still the fallback, and each is the same element its own walk
	// returned: first in gWorkers order, same filters.
	if (boss is null) {
		CCircuitUnit@ firstNano = null;
		// THE LEASH IS ASKED LAST. Only a FACTORY or a NANO worker can win here,
		// and the two are a handful of the fleet -- but the leash test came
		// first, so every one of the thirty-odd workers paid a GetPos and an
		// EcoFar to be rejected on its build type a line later. Same filters,
		// same order of decision: a far worker is still skipped.
		for (uint bf = 0; bf < gWorkers.length(); ++bf) {
			CCircuitUnit@ wf = gWorkers[bf];
			if ((wf is null) || (wf.task is null) || (wf.id == unit.id))
				continue;
			if (wf.task.GetType() != Task::Type::BUILDER)
				continue;
			const int bt = int(wf.task.GetBuildType());
			const bool isFac = (bt == int(Task::BuildType::FACTORY));
			const bool isNano = (bt == int(Task::BuildType::NANO));
			if (!isFac && !(isNano && (firstNano is null)))
				continue;
			if (EcoFar(wf.GetPos(ai.frame)))
				continue;
			if (isFac) {
				@boss = wf;
				break;
			}
			@firstNano = wf;
		}
		if (boss is null)
			@boss = firstNano;
	}
	if (boss is null)
		@boss = NextServingCon();
	if ((boss !is null) && ((boss.task is null)
			|| (boss.task.GetType() != Task::Type::BUILDER)))
		@boss = null;
	if (boss is null) {
		for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
			CCircuitUnit@ f = Brain::gFQFac[i];
			if ((f !is null) && (f.CountQueued(null) > 0)) {
				@boss = f;
				break;
			}
		}
	}
	if (boss is null)
		return w;
	// A lathe cannot draw without energy: assist delivers its drain TIMES
	// what the E economy can feed it (measured stall: lab -> mex -> assist
	// while solar lost the auction at a drained bank; the assist was
	// worthless and blocking the fix).
	float eFeed = 1.f;
	if (HardEStall()) {
		eFeed = 0.1f;
	} else {
		const float eInc = aiEconomyMgr.energy.income;
		const float ePull = aiEconomyMgr.energy.pull;
		if ((ePull > 1.f) && (eInc < ePull))
			eFeed = eInc / ePull;
	}
	float myDrain = Catalog::gBuildPower[uid] * (7.f / 80.f) * eFeed;
	// THE METAL TWIN of eFeed above, and the missing half of the temporal
	// law: an assist delivers at most the flow the economy has unspent.
	// gain=myDrain at mCost=1 bid in the hundreds at a fed site, which is
	// how com + 3 cons all fed a 5-minute T2 lab while 2 safe mexes sat
	// open (apexearth's 10 m/s arithmetic). At zero free flow the want
	// dies and the mex claims win the room.
	{
		const float mFree = FreeMetalFlow();
		if (mFree < myDrain)
			myDrain = mFree;
	}
	if (myDrain <= 0.05f)
		return w;
	// Against a factory boss the bid is bounded by what the line actually
	// leaves unserved -- and floored at a trickle so SOME help arrives.
	if ((boss !is null) && !boss.circuitDef.IsMobile()) {
		const float u = UnservedLineSpend();
		if (u < myDrain)
			myDrain = (u > 1.f) ? u : 1.f;
	}
	const AIFloat3 bp = boss.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(bp) / speed) : 60.f;
	// THE RETURN ON AN ASSIST IS THE ACCELERATION, NOT THE TRANSFER
	// (apexearth 2026-08-26). Metal moved into a site is metal the market
	// already committed -- pricing the drain itself made every assist worth
	// the same, so helping a fusion and helping a wind turbine bid alike.
	// What the second lathe actually buys is the building arriving sooner:
	//
	//   B  = busy * DRAIN          the flow the site already draws
	//   d  = my fed drain          what I add on top
	//   R  = costM * (1-progress)  metal still to go
	//   dT = R*d / (B*(B+d))       how much sooner it lands
	//   Tocc = R / (B+d)           how long I am stuck here
	//   gain = G * dT / H          the one-off, annuitized
	//
	// The return scales with the JOB's own return G and falls away as the
	// site fills -- one hand on a lonely fusion is worth the fusion, the
	// tenth hand is worth a tenth of it. Unfed drain gives dT = 0 and the
	// want dies on its own, which is the eFeed/FreeMetalFlow bound above
	// doing its work rather than a second rule.
	//
	// DIVIDING BY THE PAYBACK HORIZON IS WHAT MAKES IT COMPARABLE. Every
	// other want's gain is a rate that runs forever; an assist buys a
	// ONE-OFF G*dT metal and then stops. Priced as a rate over its own
	// stint it read as enormous exactly when the stint was shortest -- a
	// site seconds from done bid v=446 against a mex at 18 (measured), which
	// is the arithmetic saying "infinite return for no time" rather than
	// anything real. Annuitized over the same horizon the rest of the market
	// pays back against, a nearly-finished site is worth nearly nothing to
	// join and a lonely reactor is worth a lot.
	float gainRate = myDrain;              // work nobody priced: the old flat transfer
	float occupiedSec = 60.f;              // ...and its flat guard stint
	if ((gBossJob !is null) && (gBossJob.buildDef !is null)) {
		const float G = JobGain(gBossJob);
		if (G > 0.f) {
			const uint hands = Requests::Workers(gBossJob);
			const float B = float((hands > 0) ? hands : 1) * Requests::DRAIN;
			float R = gBossJob.buildDef.costM
					* (1.f - Requests::Progress(gBossJob));
			if (R < 1.f)
				R = 1.f;
			const float savedSec = R * myDrain / (B * (B + myDrain));
			float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
			if (H < 1.f)
				H = 900.f;
			gainRate = G * savedSec / H;
			occupiedSec = R / (B + myDrain);
		}
	}
	w.kind = WK_ASSIST;
	w.pos = bp;
	w.spotId = int(boss.id);
	w.gain = gainRate;
	w.mCost = 1.f;
	// The seconds this actually commits, not a flat stint: a lonely 9,000
	// metal reactor is a ten-minute posting and has to be priced as one.
	w.tCost = (walkSec + occupiedSec) * Wage();
	w.value = w.gain / (w.mCost + w.tCost);
	@gAssistTarget = boss;
	gAssistTargetId = (boss !is null) ? boss.id : -1;
	return w;
}


}  // namespace Market
