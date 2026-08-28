namespace Market {
// A hard stall re-opens held decisions: abort non-energy builds (the
// commander first), as many as the shortfall needs, so their holders fall
// back into the market,
// where the stall-priced solar now wins. Held tasks are otherwise never
// re-asked -- the engine stops re-electing once a builder is in range
// (apexearth 2026-08-23: "interrupt that commander's action and switch to
// make a basic solar").
int gNextStallSweep = 0;

// Who the market sent to assist what. A guard on an IDLE factory is a
// locked builder doing nothing while mexes sit open (apexearth 2026-08-23);
// the sweep releases them the moment the boss has no work.
array<CCircuitUnit@> gGuardUnit;
array<CCircuitUnit@> gGuardBoss;
void GuardNote(CCircuitUnit@ u, CCircuitUnit@ boss)
{
	gGuardUnit.insertLast(u);
	gGuardBoss.insertLast(boss);
}
// Constructor escorts (apexearth 2026-08-23: "we need to escort our
// constructors with at least 1 grunt or better"). The market knows which
// workers are exposed; the military election asks here before pooling a
// unit. One escort per worker; entries drop when either party dies or the
// escort's task ends.
array<Id> gEscWorker;
array<Id> gEscUnit;
// The escort's def, kept beside the pairing so the army model can tell what is
// standing from what is committed -- there is no unit-by-id lookup bound.
array<int> gEscDef;
int gEscDiagAt = 0;
int gEscOrderAt = 0;         // frame of the last escort order, all lines
bool gEscortFloor = false;   // the order ConOrderFor just returned is an escort
CCircuitUnit@ EscortNeeded(CCircuitUnit@ mil)
{
	if ((mil is null) || !gFarmSet)
		return null;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if ((wkr is null) || (wkr.task is null))
			continue;
		if (Catalog::gFlyer[int(wkr.circuitDef.id)])
			continue;   // air cons outrun ground escorts
		if (wkr.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;   // the commander is his own escort (apexearth)
		const float expo = wkr.GetPos(ai.frame).distance2D(gFarmPos)
				/ ((expoR > 1.f) ? expoR : 1200.f);
		if (expo < 0.5f)
			continue;
		bool has = false;
		for (uint e = 0; e < gEscWorker.length(); ++e) {
			if (gEscWorker[e] == wkr.id) {
				has = true;
				break;
			}
		}
		if (has)
			continue;
		// Only a NEARBY unit takes the duty: a cross-map death march
		// delivered 16 of 63 army losses as lone escorts (ladder autopsy).
		// A far worker's escort comes from the next unit produced closer,
		// or from its own raider demand (EscortShortfall).
		const float ms = Catalog::gSpeed[int(mil.circuitDef.id)];
		if ((ms > 1.f)
			&& (mil.GetPos(ai.frame).distance2D(wkr.GetPos(ai.frame)) / ms > 45.f))
			continue;
		gEscWorker.insertLast(wkr.id);
		gEscUnit.insertLast(mil.id);
		gEscDef.insertLast(int(mil.circuitDef.id));
		return wkr;
	}
	return null;
}
// Escorts ORDERED but not yet standing beside anyone. An escort queued behind
// a busy line took 77 seconds to arrive (measured, smoke seed 1), so a
// time-decayed order ledger expires and the floor re-orders. The sent-ledger
// alone is the answer: it holds every order until the unit is finished, so
// adding CountQueued to it would count the same escort twice.
int EscortInFlight(CCircuitDef@ d)
{
	if (d is null)
		return 0;
	int n = 0;
	for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
		CCircuitUnit@ f = Brain::gFQFac[i];
		if (f is null)
			continue;
		n += Brain::PendCount(int(i), d);
	}
	return n;
}

// WHAT MAY ESCORT AT ALL (apexearth 2026-08-25: "we want fast or tough units
// on escort, rocket bots die in a 1v1 vs a pawn/grunt so not good protection
// vs raiders"). What kills a constructor is something fast in its face, so an
// escort has to either CATCH it or SURVIVE it -- above the ground field's own
// average on one axis or the other. A Rocketeer is neither, and its role tag
// is `assault`, which is why a SKIRM/ARTY filter never caught it.
float gEscMeanSpd = -1.f;
void EscortMeans()
{
	if (gEscMeanSpd > 0.f)
		return;   // frame-dependent availability: never cache a mean over nothing
	float sp = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d) || Catalog::gFlyer[d])
			continue;
		sp += Catalog::gSpeed[d];
		++n;
	}
	gEscMeanSpd = (n > 0) ? (sp / float(n)) : -1.f;
}

bool EscortWorthy(int di)
{
	if (!Catalog::gAvailable[di] || !Catalog::gMobile[di] || Catalog::gBuilder[di]
		|| Catalog::gKamikaze[di] || Catalog::gFlyer[di]
		|| (Catalog::gPower[di] <= 1.f) || (Catalog::gCostM[di] <= 0.f))
		return false;
	if (Catalog::gCostM[di]
			> ai.GetTunable("apex_escort_max_cost", TUNE_ESCORT_MAX_COST))
		return false;
	CCircuitDef@ cd = Catalog::Def(di);
	if (cd.IsRoleAny(Unit::Role::SKIRM.mask)
		|| cd.IsRoleAny(Unit::Role::ARTY.mask))
		return false;   // indirect fire cannot answer what kills cons
	EscortMeans();
	if (gEscMeanSpd <= 0.f)
		return false;
	// FAST: above the ground field's own mean speed, so it can stay with a
	// worker and catch what comes for it.
	if (Catalog::gSpeed[di] >= gEscMeanSpd
			* ai.GetTunable("apex_escort_speed", TUNE_ESCORT_SPEED))
		return true;
	// TOUGH: a RIOT unit, which is the game's own name for the answer to
	// raiders -- a health bar cannot express this, because the tanky cheap
	// bot at T1 IS the rocket bot (Rocketeer 720hp against a Pawn's 370).
	return cd.IsRoleAny(Unit::Role::RIOT.mask);
}

// A CONSTRUCTOR STANDING WITHOUT A GUARD IS DEMAND FOR ONE, NOT A BID
// (apexearth 2026-08-25: "make producing guards a high priority when we have
// a constructor with no guard"). The raider role target already carries the
// metal at risk, but a role weight is a share of a draw -- it can lose for
// minutes while the con it would have saved dies. This is the floor: the line
// orders one cheap escort now, ahead of the proportional draw.
CCircuitDef@ EscortOrderFor(CCircuitUnit@ fac)
{
	if ((fac is null) || (ai.GetTunable("apex_con_escort", TUNE_CON_ESCORT) <= 0.f))
		return null;
	const int need = EscortShortfall();
	EscortMeans();
	if (ai.frame >= gEscDiagAt) {
		gEscDiagAt = ai.frame + 60 * SECOND;
		AiLog("apex: escort-diag t=" + ai.teamId
			+ " workers=" + gWorkers.length()
			+ " short=" + need
			+ " paired=" + gEscWorker.length()
			+ " risk=" + formatFloat(EscortMetalAtRisk(), "", 0, 0)
			// What escort duty has taken out of the free army, and what is
			// left standing for everything else -- the pair that used to be
			// indistinguishable in this line.
			+ " committed=" + formatFloat(RoleCommitted(int(Unit::Role::RAIDER.type)), "", 0, 0)
			+ " freeRaid=" + formatFloat(RoleValue(int(Unit::Role::RAIDER.type)), "", 0, 0)
			+ " spdBar=" + formatFloat(gEscMeanSpd, "", 0, 0));
	}
	if (need <= 0)
		return null;
	// Eligibility is the military hook's, exactly: anything else we order
	// here would be produced and then refuse the duty.
	const array<int>@ prods = Catalog::BuildsOf(int(fac.circuitDef.id));
	int best = -1;
	float bestS = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!EscortWorthy(d))
			continue;
		// Combat per metal x speed: the escort has to both fight off a raid
		// and keep up with a worker that walks. That is the Pawn/Grunt shape.
		const float s = (Catalog::gCombat[d] / Catalog::gCostM[d])
				* Catalog::gSpeed[d];
		if (s > bestS) {
			bestS = s;
			best = d;
		}
	}
	if (best < 0)
		return null;
	CCircuitDef@ pick = Catalog::Def(best);
	// One order per unescorted worker: what is already coming counts. An order
	// is invisible to BOTH counts for one message round-trip -- the sent-ledger
	// is dropped for the whole line as soon as any order becomes visible, and
	// an escort is queued behind exactly that -- so a fresh order also holds
	// the floor for one sweep.
	if (ai.frame - gEscOrderAt < Brain::FQ_WAIT)
		return null;
	if (need - EscortInFlight(pick) <= 0)
		return null;
	gEscOrderAt = ai.frame;
	return pick;
}

void EscortGone(Id id)
{
	for (uint e = 0; e < gEscWorker.length(); ) {
		if ((gEscWorker[e] == id) || (gEscUnit[e] == id)) {
			gEscWorker.removeAt(e);
			gEscUnit.removeAt(e);
			gEscDef.removeAt(e);
			continue;
		}
		++e;
	}
}

void GuardSweep()
{
	for (uint i = 0; i < gGuardUnit.length(); ) {
		CCircuitUnit@ u = gGuardUnit[i];
		CCircuitUnit@ b = gGuardBoss[i];
		bool drop = (u is null) || (b is null) || (u.task is null)
			|| (int(u.task.GetBuildType()) != int(Task::BuildType::GUARD));
		if (!drop) {
			// A factory boss with nothing queued (and nothing in flight) is
			// idle: release the guard into the market.
			const bool bossIsFac = !b.circuitDef.IsMobile();
			if (bossIsFac && (b.CountQueued(null) == 0)) {
				u.task.Abort();
				drop = true;
			}
			// A mobile boss that stopped building releases its guards too.
			if (!bossIsFac && ((b.task is null)
					|| (b.task.GetType() != Task::Type::BUILDER))) {
				u.task.Abort();
				drop = true;
			}
		}
		if (drop) {
			gGuardUnit.removeAt(i);
			gGuardBoss.removeAt(i);
			continue;
		}
		++i;
	}
}

// A PAUSE HIDES THE STALL FROM THE ONLY TEST THAT LOOKS FOR IT. pull > income
// is what a stall looks like from the outside, but the moment the throttle
// parks the fleet, pull falls BELOW income while the bank sits empty --
// measured live: cur=203/1250 (16%), income 102, pull 76, and every gate here
// read "healthy" while nothing could be built (apexearth: "there is some logic
// which puts units in 'wait' mode when e gets low, i wonder if the e-stall
// isn't triggering because of the pausing"). The drained bank is the stall
// whatever the pull says -- isEnergyStalling is the engine's own reading of it
// (empty bank, or income under pull with the bank low), and it is the same
// signal that pauses the work, so our answer now fires exactly when the
// throttle engages instead of never.
bool HardEStall()
{
	const float eInc = aiEconomyMgr.energy.income;
	const float eCur = aiEconomyMgr.energy.current;
	const float eStore = aiEconomyMgr.energy.storage;
	if (eStore <= 1.f)
		return false;
	if (aiEconomyMgr.isEnergyStalling)
		return true;
	return (aiEconomyMgr.energy.pull > eInc) && (eCur < 0.25f * eStore);
}

// Builders known to the market: upserted as they pass through Decide (the
// commander included), dropped on death. CCircuitUnit is NOCOUNT -- every
// handle here MUST be removed by NoteDead or it dangles on freed memory.
array<CCircuitUnit@> gWorkers;
array<Id> gWorkerIds;
array<int> gWorkerBorn;   // first-seen frame: the age gate for reclaim
void WorkerSeen(CCircuitUnit@ u)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == u.id)
			return;
	}
	gWorkers.insertLast(u);
	gWorkerIds.insertLast(u.id);
	gWorkerBorn.insertLast(ai.frame);
}
void WorkerGone(Id id)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == id) {
			gWorkerBorn.removeAt(i);
			gWorkers.removeAt(i);
			gWorkerIds.removeAt(i);
			return;
		}
	}
}


}  // namespace Market
