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
	if (w.kind == WK_SUPER) {
		// A gantry is a factory and goes through the plant's own siting and
		// join; everything else here is a static weapon. BIG_GUN is the
		// engine's own build type for one, which the anti-nuke already used.
		if (w.spotId == SC_GANTRY) {
			IUnitTask@ jg = JoinBig(w.def);
			if (jg !is null)
				return jg;
			return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
					Task::Priority::NORMAL, ClearOfSpots(w.pos, 180.f), 256.f,
					SQUARE_SIZE * 16.f);
		}
		const int sbt = (w.spotId == SC_HEAVY) ? int(Task::BuildType::DEFENCE)
				: int(Task::BuildType::BIG_GUN);
		return Requests::Take(unit, w.def, Task::BuildType(sbt),
				Task::Priority::NORMAL, ClearOfSpots(w.pos, 120.f), 300.f,
				SQUARE_SIZE * 16.f);
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
		// Nanos serve factories and big frames only (apexearth): the
		// hungriest working line or the biggest uncovered build site takes
		// the turret; failing either, it parks beside any factory.
		AIFloat3 slot = w.pos;
		bool sited = false;
		// The line's pull is priced ONCE, in NeediestLine, so the turret is
		// sited by the same arithmetic that bought it.
		float worst = 0.f;
		{
			AIFloat3 lp;
			const float ln = NeediestLine(lp);
			if ((ln > 0.f) && OnMap(lp)) {
				worst = ln;
				slot = lp;
				sited = true;
			}
		}
		// NEAR THE METAL SINKS (apexearth: "if we are not empty on metal...
		// build nano turrets near the things that are currently spending
		// metal"): a live build site competes under the same bar as the
		// lines -- free flow less the lathe already on it. Bank-gated -- at an empty bank the lathe already outruns
		// income and pre-positioning BP at a sink serves nothing.
		const float mSt = aiEconomyMgr.metal.storage;
		if ((mSt > 1.f) && (aiEconomyMgr.metal.current > mSt
				* ai.GetTunable("apex_nano_sink_bank", TUNE_NANO_SINK_BANK))) {
			for (uint li = 0; li < Requests::gLive.length(); ++li) {
				IUnitTask@ lt = Requests::gLive[li];
				if ((lt is null) || (lt.buildDef is null))
					continue;
				// BIG SITES ONLY, as the want side prices them: unfiltered,
				// this loop parked turrets at 50-metal MEXES and stole every
				// one a queued lab had asked for (measured: 13 of 14 sinks
				// were armmex/armmakr).
				const int bd3 = int(lt.buildDef.id);
				if ((Catalog::gCostM[bd3] < ai.GetTunable("apex_nano_sink_m", TUNE_NANO_SINK_M))
					&& (Catalog::gMakeE[bd3] < ai.GetTunable("apex_big_e", TUNE_BIG_E)))
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
				// The crew is SUPPLY, not demand: a frame whose cons already
				// eat the free flow earns nothing from another turret.
				const float feed2 = FreeMetalFlow();
				const float u2 = ((feed2 < 35.f) ? feed2 : 35.f)
						- drain - float(nanosAt) * NANO_ABSORB;
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
	// ...and a stall opens them too. Overflow is not the only reason to build
	// two things at once: a deficit nothing in flight will cover is the other,
	// and it is the one that mattered, because a stall guarantees the bank is
	// NOT overflowing and so guaranteed the answer was serialized.
	bool par = (MCostScale() < 1.f)
			|| ((w.kind == WK_ENERGY) && EnergyShortOfOrdered());
	bool crtd = false;
	// Finish before founding: any unmanned unfinished site of this def is
	// THE want, wherever it stands (slot cursors never reuse ground, so an
	// abandoned frame would otherwise be orphaned forever).
	// A PLANT IS THE MOST EXPENSIVE THING THIS LIST FORGOT. The kinds below
	// were the four the rule was written for; a half-built lab was never
	// adopted, so an e-stall that pulled the con off it left the frame
	// standing and the next election founded a SECOND lab elsewhere
	// (apexearth: "instead of choosing to finish the original lab afterwards
	// we just start making a new one. We should be finishing the first lab we
	// started if it is still present/partially built").
	if ((w.kind == WK_ENERGY) || (w.kind == WK_CONVERT)
		|| (w.kind == WK_STORE) || (w.kind == WK_NANO)
		|| (w.kind == WK_PLANT) || (w.kind == WK_TECH))
	{
		IUnitTask@ orph = Requests::OrphanOf(w.def);
		if (orph !is null)
			return orph;
		// ...and a frame whose REQUEST is gone too, which is what an abort
		// leaves behind. Requests::Take already refuses to start a second
		// building on top of a standing frame, but only one that is near the
		// site it was handed -- so aim the request at the frame and its own
		// guard adopts it.
		CCircuitUnit@ pf = Requests::PendAnyOfDef(w.def, unit.GetPos(ai.frame));
		if (pf !is null) {
			w.pos = pf.GetPos(ai.frame);
			AiLog(Factory::T() + "apex: frame-adopt " + w.def.GetName()
				+ " done=" + formatFloat(pf.GetHealthPercent(), "", 0, 2)
				+ " at=" + int(w.pos.x) + "," + int(w.pos.z));
		}
	}
	// A LATTICE SLOT IS COVERED ONLY BY ITS OWN CELL. Requests::Take joins any
	// live request for the same def inside the cover radius, and at 96 elmos
	// that swallowed every NEIGHBOUR: a converter tiles on 48, so the slot next
	// door was read as "already being built" and the ask became a second worker
	// on the standing site instead of the building beside it. Same-def
	// structures could not be requested closer than 96 apart while a sibling
	// request was live, which is the spacing, not any blast radius.
	const float cell = Lattice::StrideOf(int(w.def.id));
	if (w.kind == WK_ENERGY) {
		// Generators pack beside their own kind, fusion tier included
		// (apexearth: "place those next to each other... fusions belong
		// in the back of the map, furthest from the enemy"). The farm sits in
		// the rear of the base axis, which is that ground.
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : BigEnergySite();
		{
			IUnitTask@ jt = JoinBig(w.def);
			if (jt !is null)
				return jt;
		}
		if (Catalog::gCostM[int(w.def.id)] > 500.f)
			w.pos = ClearOfSpots(w.pos, 150.f);
		return Requests::Take(unit, w.def, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, cell, 0.f,
				crtd, par);
	}
	if (w.kind == WK_CONVERT) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::CONVERT,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, cell, 0.f,
				crtd, par);
	}
	if (w.kind == WK_STORE) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::STORE,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, cell, 0.f);
	}
	if (w.kind == WK_PLANT) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		// A floating plant keeps the water it was priced against -- the
		// spot-clearance nudge walks the base axis and puts a shipyard inland.
		const AIFloat3 at = Catalog::gFloater[int(w.def.id)]
				? w.pos : ClearOfSpots(w.pos, 180.f);
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, at, 256.f, SQUARE_SIZE * 16.f);
	}
	return null;
}


}  // namespace Market
