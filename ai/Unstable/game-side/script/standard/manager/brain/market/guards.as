namespace Market {
// A hard stall re-opens held decisions: abort ONE non-energy build per
// sweep (the commander first) so its holder falls back into the market,
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
		return wkr;
	}
	return null;
}
void EscortGone(Id id)
{
	for (uint e = 0; e < gEscWorker.length(); ) {
		if ((gEscWorker[e] == id) || (gEscUnit[e] == id)) {
			gEscWorker.removeAt(e);
			gEscUnit.removeAt(e);
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

bool HardEStall()
{
	const float eInc = aiEconomyMgr.energy.income;
	const float eCur = aiEconomyMgr.energy.current;
	const float eStore = aiEconomyMgr.energy.storage;
	return (aiEconomyMgr.energy.pull > eInc)
		&& (eStore > 1.f) && (eCur < 0.25f * eStore);
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
