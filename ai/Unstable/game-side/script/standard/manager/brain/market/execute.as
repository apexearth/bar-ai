namespace Market {
IUnitTask@ ExecuteWant(CCircuitUnit@ unit, Want@ w)
{
	if (w.kind == WK_MEX) {
		// Help the one already going before opening another, exactly as every
		// other build type does -- the metal path used to skip this rung.
		IUnitTask@ jm = Requests::JoinSpot(unit, w.def, w.pos);
		if (jm !is null)
			return jm;
		// TaskB::Spot, not Common: CBMexTask::Execute refuses to issue the
		// build order unless IsOpenSpot(spotId) holds, and Common leaves
		// spotId at -1 (measured: one decide, then a game-long freeze).
		IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEX,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
		if (t !is null)
			LedgerClaim(w.spotId, w.pos, aiEconomyMgr.GetMexSpotIncome(w.spotId));
		return t;
	}
	if (w.kind == WK_MEXUP) {
		IUnitTask@ ju = Requests::JoinSpot(unit, w.def, w.pos);
		if (ju !is null)
			return ju;
		return aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEXUP,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
	}
	if (w.kind == WK_TECH) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, ClearOfSpots(w.pos, 180.f), 256.f,
				SQUARE_SIZE * 16.f);
	}
	if ((w.kind == WK_PROTECT) || (w.kind == WK_SENSE)
		|| (w.kind == WK_AIRDEF)) {
		// THE chokepoint, not the proposers: three separate PROT_DEF gain
		// branches each carried their own ValueOf-and-continue, and gating
		// two of them still let claws through (measured three times).
		// Whatever proposes, nothing EXECUTES ground defence on the quiet
		// rear.
		// Classify by the DEF, not spotId: the defence branches store the
		// CLUSTER id in spotId, so a PROT_DEF compare only caught cluster 4
		// -- claws sailed past this gate on every other cluster (three
		// "airtight" runs, measured 2026-08-23). A ground-shooting weapon
		// is ground defence wherever it points; AA (air-only threat) stays
		// allowed, matching the audit's mDefAA split.
		const bool groundDef = (w.def !is null)
				&& (Catalog::gSurfT[int(w.def.id)] > 0.01f);
		if (groundDef)
			AiLog("apex: prot-exec t=" + ai.teamId + " def=" + w.def.GetName()
					+ " role=" + (gEcoRole ? 1 : 0)
					+ " danger=" + (EcoDangerNear() ? 1 : 0)
					+ " streak=" + gEcoDangerStreak);
		const int bt = (w.spotId == PROT_RADAR) ? int(Task::BuildType::RADAR)
				: ((w.spotId == PROT_DEF) || (w.spotId == PROT_SHIELD)
					|| (w.spotId == PROT_AA))
					? int(Task::BuildType::DEFENCE)
				: (w.spotId == PROT_ANTINUKE) ? int(Task::BuildType::BIG_GUN)
				: int(Task::BuildType::ENERGY);
		return Requests::Take(unit, w.def, Task::BuildType(bt),
				Task::Priority::NORMAL, w.pos, 300.f, SQUARE_SIZE * 16.f);
	}
	if (w.kind == WK_ASSIST) {
		if ((gAssistTarget is null) || (int(gAssistTarget.id) != w.spotId))
			return null;
		IUnitTask@ gt = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::LOW,
				gAssistTarget, false, 60 * SECOND));
		if (gt !is null)
			GuardNote(unit, gAssistTarget);
		return gt;
	}
	if (w.kind == WK_RECLAIM) {
		CCircuitUnit@ tgt = w.target;
		if ((tgt is null) || (int(tgt.id) != w.spotId))
			return null;
		// A condemned unit stands for it -- walking away made the reclaimer
		// chase it across the base (apexearth).
		if (tgt.circuitDef.IsMobile())
			tgt.CmdMoveTo(unit.GetPos(ai.frame));
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL, tgt));
	}
	if (w.kind == WK_NANO) {
		// Nano placement follows the demand math: the line with the LARGEST
		// unserved spend gets the next turret (the binary has-one check
		// capped the army lab at a single nano while metal overflowed --
		// watched twice).
		// The FARM BLOCK is the default home (apexearth: "nanos go in
		// zones of future construction, not just where they're needed
		// presently" -- eco builds already site at the farm, so coverage
		// there is coverage of everything about to exist). A factory line
		// pulls a nano away only when its unserved spend clears a real
		// bar, not merely being the hungriest.
		// The FARM BLOCK IS DEAD (apexearth: nanos only beside factories
		// and expensive builds): the hungriest line or big frame takes the
		// turret; failing either, it parks beside any working factory.
		AIFloat3 slot = w.pos;
		bool sited = false;
		const float per = LineSpend();
		float worst = 0.f;
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if ((f is null) || (f.CountQueued(null) == 0))
				continue;
			const AIFloat3 fp = f.GetPos(ai.frame);
			int nanosNear = 0;
			for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
				if (fp.distance2D(gOwnNanoPos[ni]) < 350.f)
					++nanosNear;
			}
			const float u = per - float(nanosNear) * NANO_ABSORB;
			if (u > worst) {
				worst = u;
				slot = fp;
				sited = true;
			}
		}
		// NEAR THE METAL SINKS (apexearth: "if we are not empty on metal...
		// build nano turrets near the things that are currently spending
		// metal"): a live build site's pull is its assigned crew's drain;
		// the biggest uncovered sink competes under the same bar as the
		// lines. Bank-gated -- at an empty bank the lathe already outruns
		// income and pre-positioning BP at a sink serves nothing.
		const float mSt = aiEconomyMgr.metal.storage;
		if ((mSt > 1.f) && (aiEconomyMgr.metal.current > mSt
				* ai.GetTunable("apex_nano_sink_bank", TUNE_NANO_SINK_BANK))) {
			for (uint li = 0; li < Requests::gLive.length(); ++li) {
				IUnitTask@ lt = Requests::gLive[li];
				if ((lt is null) || (lt.buildDef is null))
					continue;
				array<CCircuitUnit@>@ crew = lt.GetUnits();
				if ((crew is null) || (crew.length() == 0))
					continue;
				const AIFloat3 sp = lt.GetBuildPos();
				if (!OnMap(sp))
					continue;
				float drain = 0.f;
				for (uint ci = 0; ci < crew.length(); ++ci) {
					if (crew[ci] !is null)
						drain += Catalog::gBuildPower[int(crew[ci].circuitDef.id)]
								* (7.f / 80.f);
				}
				int nanosAt = 0;
				for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
					if (sp.distance2D(gOwnNanoPos[ni]) < 350.f)
						++nanosAt;
				}
				const float u2 = drain - float(nanosAt) * NANO_ABSORB;
				if (u2 > worst) {
					worst = u2;
					slot = sp;
					sited = true;
					AiLog("apex: nano-to-sink t=" + ai.teamId + " at "
							+ lt.buildDef.GetName()
							+ " drain=" + formatFloat(u2, "", 0, 1));
				}
			}
		}
		// Bare big frames (no crew yet) are sites too: "if you're making
		// these fusions or afus somewhere, just go ahead and make nanos
		// beside them."
		if (!sited) {
			for (uint li = 0; li < Requests::gLive.length(); ++li) {
				IUnitTask@ lt2 = Requests::gLive[li];
				if ((lt2 is null) || (lt2.buildDef is null))
					continue;
				const int bd2 = int(lt2.buildDef.id);
				if ((Catalog::gCostM[bd2] < ai.GetTunable("apex_nano_sink_m", TUNE_NANO_SINK_M))
					&& (Catalog::gMakeE[bd2] < ai.GetTunable("apex_big_e", TUNE_BIG_E)))
					continue;
				const AIFloat3 sp4 = lt2.GetBuildPos();
				if (OnMap(sp4)) {
					slot = sp4;
					sited = true;
					break;
				}
			}
		}
		if (!sited) {
			for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
				CCircuitUnit@ f2 = Factory::gFacUnits[fi];
				if (f2 !is null) {
					slot = f2.GetPos(ai.frame);
					sited = true;
					break;
				}
			}
		}
		if (!sited)
			return null;
		// PARALLEL on purpose: the default Take folds every nano ask onto
		// the one standing request -- "burst=1 forever" (requests.as's own
		// measurement) -- the root of every "not enough nanos" report. Each
		// decider opens its OWN slot; FarmSlot's rows make the block
		// rectangular; the income-derived InFlight cap still bounds it.
		bool made = false;
		return Requests::Take(unit, w.def, Task::BuildType::NANO,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 64.f, 0.f,
				made, true);
	}
	if (w.kind == WK_GEO) {
		return aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::GEO,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
	}
	// An overflowing bank opens PARALLEL sites: the serialized default folds
	// every asker onto one standing request, and one fusion at a time was
	// the 45%-excess bottleneck. parallel skips the fold; the wealth cap
	// (EffectiveCap) still bounds it.
	bool par = (MCostScale() < 1.f);
	bool crtd = false;
	// Finish before founding: any unmanned unfinished site of this def is
	// THE want, wherever it stands (slot cursors never reuse ground, so an
	// abandoned frame would otherwise be orphaned forever).
	if ((w.kind == WK_ENERGY) || (w.kind == WK_CONVERT)
		|| (w.kind == WK_STORE) || (w.kind == WK_NANO))
	{
		IUnitTask@ orph = Requests::OrphanOf(w.def);
		if (orph !is null)
			return orph;
	}
	if (w.kind == WK_ENERGY) {
		// Fusion-tier generators pack together in the DEEP REAR
		// (apexearth: "place those next to each other... fusions belong
		// in the back of the map, furthest from the enemy").
		const bool bigE = Catalog::gMakeE[int(w.def.id)]
				>= ai.GetTunable("apex_big_e", TUNE_BIG_E);
		if (bigE)
			w.pos = BigEnergySite();
		const AIFloat3 slot = bigE ? w.pos
				: (gFarmSet ? FarmSlot(int(w.def.id)) : w.pos);
		{
			IUnitTask@ jt = JoinBig(w.def);
			if (jt !is null)
				return jt;
		}
		if (Catalog::gCostM[int(w.def.id)] > 500.f)
			w.pos = ClearOfSpots(w.pos, 150.f);
		return Requests::Take(unit, w.def, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 96.f, 0.f,
				crtd, par);
	}
	if (w.kind == WK_CONVERT) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::CONVERT,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 96.f, 0.f,
				crtd, par);
	}
	if (w.kind == WK_STORE) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::STORE,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, 96.f, 0.f);
	}
	if (w.kind == WK_PLANT) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, ClearOfSpots(w.pos, 180.f), 256.f,
				SQUARE_SIZE * 16.f);
	}
	return null;
}


}  // namespace Market
