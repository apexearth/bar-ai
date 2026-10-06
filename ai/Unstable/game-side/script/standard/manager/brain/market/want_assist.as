namespace Market {
int gFacGuardBids = 0;
int gFacGuardWins = 0;
int gNextFacGuardLog = 0;
int gAssistGuardS = 60;   // the guard stint Execute enqueues for the last assist priced
// Assisting T2+ work is a PRICED want, not an idleness fallback (apexearth
// 2026-08-23: "T1 cons are still not assisting T2 cons, helping build T2+
// buildings, or assisting factories"). A joiner transfers its whole drain
// into a build the market already values at clearing rates; the bill is
// the walk and the occupied time. That beats a marginal solar and loses to
// a fresh mex -- the right ordering by construction.
// Can this builder def raise a nano turret (a static lathe with no build list)?
array<int> gHandNano;   // per def: 0 unknown, 1 yes, 2 no
bool HandBuildsNano(int uid)
{
	if (int(gHandNano.length()) <= Catalog::gDefCount)
		gHandNano.resize(Catalog::gDefCount + 1);
	if ((uid < 0) || (uid > Catalog::gDefCount))
		return false;
	if (gHandNano[uid] == 0) {
		gHandNano[uid] = 2;
		const array<int>@ b = Catalog::gBuildsList[uid];
		for (uint i = 0; i < b.length(); ++i) {
			const int d = b[i];
			if (Catalog::gAvailable[d] && !Catalog::gMobile[d] && (Catalog::gBuildPower[d] > 0.f)
				&& (Catalog::gBuildsList[d].length() == 0)) {
				gHandNano[uid] = 1;
				break;
			}
		}
	}
	return gHandNano[uid] == 1;
}

// Does a standing basic (non-ceiling) constructor of ours build this def?
bool BasicHandCan(int d)
{
	const array<int>@ _own31 = OwnedDefs();
	for (uint _oi31 = 0; _oi31 < _own31.length(); ++_oi31) {
		const uint c = uint(_own31[_oi31]);
		const int hd = int(c);
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[hd] || !Catalog::gBuilder[hd]
			|| ReachesCeiling(hd))
			continue;
		if (Catalog::gBuildsList[hd].find(d) >= 0)
			return true;
	}
	return false;
}

// METAL FIRST (apexearth 2026-09-19): the unlock in flight -- an advanced
// plant or a mex upgrade -- takes every free hand that can reach it while
// its crew is short and the feed can carry another. Priced nowhere: the
// priced assist read the T2 lab at v=0.5 and it rose on one hand for 99 s
// with ten allowed. Decide hoists this ahead of the draw.
// A defence gun joins the same way while defence is behind its target; its crew
// cap grows with the shortfall (FeedableCrew), so the further behind, the more
// hands (apexearth 2026-09-28).
int gUnlockAssists = 0;
int gDefJoinAssists = 0;
int gUnlockOrphanJoins = 0;
int gNextUnlockOrphanLog = 0;
void UnlockOrphanLog(const CCircuitDef@ d, float done, const string &in kind)
{
	if ((d is null) || (ai.frame < gNextUnlockOrphanLog))
		return;
	gNextUnlockOrphanLog = ai.frame + 30 * SECOND;
	AiLog(Factory::T() + "apex: unlock-orphan t=" + ai.teamId + " " + d.GetName()
		+ " " + kind + " done=" + formatFloat(done, "", 0, 2)
		+ " total=" + gUnlockOrphanJoins);
}

Want@ ProposeUnlockAssist(CCircuitUnit@ unit, bool defence)
{
	Want w;
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return w;
	// Not withheld while the feed is short: the frame's share of a short feed
	// is its share of the lathes drawing on it, and the crew stays bounded by
	// what the income feeds (SiteWorkerCap).
	if (defence && (DefenceShortfall() <= 0.f))
		return w;
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestD = 0.f;
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt is null) || lt.IsDead() || (lt.buildDef is null))
			continue;
		if (defence) {
			// The peel's own test: a ring-fed frame is trimmed to its founder.
			if ((ProtClassOf(int(lt.buildDef.id)) != PROT_DEF)
				|| Requests::NanoFed(lt, Requests::Workers(lt), 0.f, 0.f))
				continue;
		} else if (!Requests::IsMetalUnlock(lt.buildDef))
			continue;
		const AIFloat3 bp = lt.GetBuildPos();
		if (CrewSplitOn() && !CrewIsField(unit) && FieldSite(bp))
			continue;   // the home crew does not walk out to field work
		// Guards count against the cap. They never become Workers -- they sit
		// on a Guard task -- so counting only the crew, every free hand saw a
		// short site and piled on: the priced assist above already folds them
		// in for the same reason.
		// An unmanned unlock frame is taken up too: its def's want stands
		// aside while the request lives (LiveOfDef), so nothing else returns
		// to it and the frame decays.
		const bool orphan = !defence && (Requests::Workers(lt) == 0) && (lt.target !is null);
		if (!OnMap(bp) || ((Requests::Workers(lt) == 0) && !orphan)
			|| ((Requests::Workers(lt) + uint(GuardsOnJob(lt)))
				>= Requests::SiteWorkerCap(lt.buildDef)))
			continue;
		if (!ai.CanDefReach(Catalog::Def(int(unit.circuitDef.id)), here, bp))
			continue;
		const float d = here.distance2D(bp);
		if ((best is null) || (d < bestD)) {
			@best = lt;
			bestD = d;
		}
	}
	// ...and an advanced plant frame whose request died with its builder: it
	// still holds every other advanced plant ask (AdvPlantInFlight), its own
	// def included, so this is the only way back to it.
	if ((best is null) && !defence && AdvPlantInFlight() && (gAdvInFlightRow >= 0)
		&& ComIsOrphan(uint(gAdvInFlightRow)))
	{
		const uint row = uint(gAdvInFlightRow);
		CCircuitUnit@ fr = ai.GetTeamUnit(gComId[row]);
		if (fr is null)
			return w;
		uint onFrame = 0;
		for (uint g = 0; g < gGuardBId.length(); ++g) {
			if (gGuardBId[g] == fr.id)
				++onFrame;
		}
		if (onFrame >= Requests::SiteWorkerCap(Catalog::Def(gComDef[row])))
			return w;
		const AIFloat3 fp = fr.GetPos(ai.frame);
		if (!OnMap(fp) || !ai.CanDefReach(Catalog::Def(int(unit.circuitDef.id)), here, fp))
			return w;
		float done = fr.GetHealthPercent();
		done = (done < 0.f) ? 0.f : ((done > 1.f) ? 1.f : done);
		w.kind = WK_ASSIST;
		w.pos = fp;
		w.spotId = int(fr.id);
		w.gain = 1.f;
		w.mCost = 1.f;
		w.tCost = 1.f;
		w.value = 1.f;
		@w.def = Catalog::Def(gComDef[row]);
		@gAssistTarget = fr;
		gAssistTargetId = fr.id;
		gAssistGuardS = int(Catalog::gCostM[gComDef[row]] * (1.f - done) / Requests::DRAIN) + 10;
		++gUnlockOrphanJoins;
		++gUnlockAssists;
		UnlockOrphanLog(w.def, done, "frame");
		return w;
	}
	if (best is null)
		return w;
	array<CCircuitUnit@>@ on = best.GetUnits();
	CCircuitUnit@ boss = null;
	for (uint i = 0; (on !is null) && (i < on.length()); ++i) {
		if ((on[i] !is null) && (on[i].id != unit.id)) {
			@boss = on[i];
			break;
		}
	}
	if ((boss is null) && !defence && (best.target !is null)) {
		@boss = best.target;   // the frame itself: Execute joins the task, else guards it
		++gUnlockOrphanJoins;
		UnlockOrphanLog(best.buildDef, Requests::Progress(best), "task");
	}
	if (boss is null)
		return w;
	w.kind = WK_ASSIST;
	w.pos = best.GetBuildPos();
	w.spotId = int(boss.id);
	w.gain = 1.f;
	w.mCost = 1.f;
	w.tCost = 1.f;
	w.value = 1.f;
	@w.def = best.buildDef;
	@gAssistTarget = boss;
	gAssistTargetId = boss.id;
	gAssistGuardS = 60;
	if (defence)
		++gDefJoinAssists;
	else
		++gUnlockAssists;
	return w;
}

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
	double _tA = Perf::T0();
	CCircuitUnit@ boss = BestJobBoss(unit);
	Perf::Add("as.boss", _tA);
	_tA = Perf::T0();
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
	Perf::Add("as.fallback", _tA);
	_tA = Perf::T0();
	if (boss is null)
		return w;
	// A fallback boss's own task is the job: the pricing below reads its
	// gain and its progress; without it every fallback bid the flat
	// transfer.
	if ((gBossJob is null) && boss.circuitDef.IsMobile() && (boss.task !is null)
		&& (boss.task.GetType() == Task::Type::BUILDER))
		@gBossJob = boss.task;
	// A CEILING CON DOES NOT ASSIST WORK A BASIC HAND CAN DO. Its exclusive
	// work -- the advanced converter, the fusion -- is what nobody else can
	// start; a T2 con holding a T1 con's nano frame is that work undone
	// (apexearth 2026-09-14, watching a full bank: "bunch of T2 cons doing
	// nothing but assisting T1 cons. come on... this is STUPID logic").
	// Only while basic hands exist to do it instead.
	if (ReachesCeiling(uid) && (gBossJob !is null) && (gBossJob.buildDef !is null)
		&& !ReachesCeiling(int(gBossJob.buildDef.id)) && BasicHandCan(int(gBossJob.buildDef.id)))
		return w;
	// A lathe cannot draw without energy: assist delivers its drain TIMES
	// what the E economy can feed it (measured stall: lab -> mex -> assist
	// while solar lost the auction at a drained bank; the assist was
	// worthless and blocking the fix).
	float eFeed = 1.f;
	if (HardEStall()) {
		eFeed = 0.1f;
	} else {
		const float eInc = Eco::EInc();
		const float ePull = Eco::EPull();
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
	float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
	if (H < 1.f)
		H = 900.f;
	// Work nobody priced is still a ONE-OFF: the metal the stint moves,
	// annuitized like the priced case. As a standing rate it bid like a
	// permanent stream.
	float occupiedSec = 60.f;
	float gainRate = myDrain * occupiedSec / H;
	if ((gBossJob !is null) && (gBossJob.buildDef !is null)) {
		const float G = JobGain(gBossJob);
		// ...the guards already sent and the ring reaching the site
		// included, or the fortieth guard prices like the first.
		const uint hands = Requests::Workers(gBossJob) + uint(GuardsOnJob(gBossJob));
		const float B = float((hands > 0) ? hands : 1) * Requests::DRAIN
				+ NanoLatheReaching(gBossJob.GetBuildPos());
		float R = gBossJob.buildDef.costM
				* (1.f - Requests::Progress(gBossJob));
		if (R < 1.f)
			R = 1.f;
		const float savedSec = R * myDrain / (B * (B + myDrain));
		occupiedSec = R / (B + myDrain);
		gainRate = (G > 0.f) ? (G * savedSec / H)
				: (myDrain * occupiedSec / H);
	}

	Perf::Add("as.price", _tA);
	w.kind = WK_ASSIST;
	w.pos = bp;
	w.spotId = int(boss.id);
	w.gain = gainRate;
	// The metal the stint moves is NOT the assist's cost: the market paid it
	// when it bought the job, and billing every helper for it again left
	// one hand on the T2 lab. The annuitized gain already falls as hands
	// pile on; the hand's own time is the cost.
	w.mCost = 1.f;
	// The seconds this actually commits, not a flat stint: a lonely 9,000
	// metal reactor is a ten-minute posting and has to be priced as one.
	w.tCost = (walkSec + occupiedSec) * Wage();
	w.value = w.gain / (w.mCost + w.tCost);
	@gAssistTarget = boss;
	gAssistTargetId = (boss !is null) ? boss.id : -1;
	gAssistGuardS = 60;
	return w;
}

// BARb'S FLOOR, the other half (apexearth 2026-09-11: "OK"): a constructor
// within 600 elmos of a factory that is recruiting guards it for 10 s while
// the bank is above 20% of storage and energy is not stalling -- stock
// EconomyManager.cpp CheckMobileAssistRequired, the bank test being what
// economy.as already writes into isAssistRequired. Priced at the hand's own
// fed drain -- the factory converts it into army for the rest of the game --
// and taken only where it beats the priced assist above. Measured before it:
// 0.8-0.9% of our constructor time on a factory against BARb's 12.8-21.6%.
Want@ ProposeFactoryGuard(CCircuitUnit@ unit, const Want& in priced)
{
	Want w = priced;
	if (!aiFactoryMgr.isAssistRequired || (Brain::gFQFac.length() == 0))
		return w;
	const AIFloat3 me = unit.GetPos(ai.frame);
	CCircuitUnit@ fac = null;
	float best = 600.f * 600.f;
	for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
		CCircuitUnit@ f = Brain::gFQFac[i];
		if ((f is null) || (f.CountQueued(null) <= 0))
			continue;
		const float d2 = me.SqDistance2D(f.GetPos(ai.frame));
		if (d2 < best) {
			best = d2;
			@fac = f;
		}
	}
	if (fac is null)
		return w;
	const int uid = int(unit.circuitDef.id);
	float eFeed = 1.f;
	{
		const float eInc = Eco::EInc();
		const float ePull = Eco::EPull();
		if ((ePull > 1.f) && (eInc < ePull))
			eFeed = eInc / ePull;
	}
	float drain = Catalog::gBuildPower[uid] * (7.f / 80.f) * eFeed;
	const float mFree = FreeMetalFlow();
	if (mFree < drain)
		drain = mFree;
	if (drain <= 0.05f)
		return w;
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f) ? (sqrt(best) / speed) : 60.f;
	// A FLOOR, priced as one: the stint's metal as a one-off over the
	// market's horizon, not a standing rate.
	float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
	if (H < 1.f)
		H = 900.f;
	// WASTE IS FREE LATHE -- the nano want's own law: while metal overflows a
	// hand on the line converts metal being thrown away, so the stint is worth
	// that rate standing, not a one-off amortised into nothing.
	// ...but only for a hand that cannot raise a lathe itself: one that can is
	// worth more raising the nano that turns the waste into builds after it
	// leaves (a guard's stint adds nothing that stays).
	float over = HandBuildsNano(uid) ? 0.f : OverflowM();
	if (over > drain)
		over = drain;
	Want g;
	g.kind = WK_ASSIST;
	g.pos = fac.GetPos(ai.frame);
	g.spotId = int(fac.id);
	g.gain = drain * 10.f / H + over;
	g.mCost = drain * 10.f * MCostScale();
	g.tCost = (walkSec + 10.f) * Wage();
	g.value = g.gain / (g.mCost + g.tCost);
	++gFacGuardBids;
	if (g.value <= w.value)
		return w;
	++gFacGuardWins;
	if (ai.frame >= gNextFacGuardLog) {
		gNextFacGuardLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: facguard " + unit.circuitDef.GetName()
			+ " bids=" + gFacGuardBids + " wins=" + gFacGuardWins
			+ " over=" + formatFloat(over, "", 0, 1)
			+ " drain=" + formatFloat(drain, "", 0, 1)
			+ " v=" + formatFloat(g.value * 1000.f, "", 0, 2)
			+ " beat=" + formatFloat(w.value * 1000.f, "", 0, 2));
	}
	@gAssistTarget = fac;
	gAssistTargetId = fac.id;
	gAssistGuardS = 10;
	return g;
}



}  // namespace Market
