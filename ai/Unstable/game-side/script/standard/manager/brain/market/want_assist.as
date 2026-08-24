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
	// Only lesser cons assist upward; ceiling cons do the T2 work itself.
	float myCeil = 0.f;
	const array<int>@ mine = Catalog::BuildsOf(uid);
	for (uint i = 0; i < mine.length(); ++i) {
		if (Catalog::gExtractsM[mine[i]] > myCeil)
			myCeil = Catalog::gExtractsM[mine[i]];
	}
	if (myCeil >= BestExtract())
		return w;
	// A worker BUILDING BUILD POWER is the best boss there is: BP
	// compounds, and the first nano crawling up under one lathe delays
	// everything behind it (apexearth). Then serving cons, then factories.
	CCircuitUnit@ boss = null;
	// A worker raising a FACTORY outranks everything -- one con on the T2
	// plant was the measured bottleneck (apexearth: "we are more efficient
	// when we assist building some things").
	for (uint bf = 0; bf < gWorkers.length(); ++bf) {
		CCircuitUnit@ wf = gWorkers[bf];
		if ((wf is null) || (wf.task is null) || (wf.id == unit.id))
			continue;
		if (EcoFar(wf.GetPos(ai.frame)))
			continue;
		if ((wf.task.GetType() == Task::Type::BUILDER)
			&& (int(wf.task.GetBuildType()) == int(Task::BuildType::FACTORY))) {
			@boss = wf;
			break;
		}
	}
	for (uint bi = 0; (boss is null) && (bi < gWorkers.length()); ++bi) {
		CCircuitUnit@ wb = gWorkers[bi];
		if ((wb is null) || (wb.task is null) || (wb.id == unit.id))
			continue;
		if (EcoFar(wb.GetPos(ai.frame)))
			continue;
		if (wb.task.GetType() != Task::Type::BUILDER)
			continue;
		if (int(wb.task.GetBuildType()) == int(Task::BuildType::NANO)) {
			@boss = wb;
			break;
		}
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
	w.kind = WK_ASSIST;
	w.pos = bp;
	w.spotId = int(boss.id);
	w.gain = myDrain;
	w.mCost = 1.f;
	w.tCost = (walkSec + 60.f) * Wage();   // one guard stint
	w.value = w.gain / (w.mCost + w.tCost);
	@gAssistTarget = boss;
	return w;
}


}  // namespace Market
