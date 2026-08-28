namespace Market {
// The nano placement probe's cache (see the WK_NANO branch).
AIFloat3 gNanoSite(-1.f, 0.f, -1.f);
int gNanoSiteKey = 0;
int gNanoSiteAt = -999999;

// TWO FACTORIES THAT CHOOSE ADJACENT SPOTS WALL EACH OTHER IN. Both asks
// resolve in the same window, before either blocker map entry stands, so the
// block_map yards that keep STANDING factories apart never see the pair
// (apexearth, watching: "two factories choose to make at spots right next to
// each other. So during placement the issue happens"). The ask itself steps
// away from any factory request already in flight; the engine's own search
// still handles the standing world.
AIFloat3 ClearOfLiveFactories(const AIFloat3& in pos)
{
	AIFloat3 p = pos;
	for (uint tries = 0; tries < 4; ++tries) {
		bool near = false;
		AIFloat3 at;
		for (uint i = 0; i < Requests::gLive.length(); ++i) {
			IUnitTask@ t = Requests::gLive[i];
			if ((t is null) || t.IsDead()
				|| (t.GetBuildType() != Task::BuildType::FACTORY))
				continue;
			at = t.GetBuildPos();
			if (OnMap(at) && (p.distance2D(at) < 512.f)) {
				near = true;
				break;
			}
		}
		if (!near)
			return p;
		AIFloat3 dir = p - at;
		const float len = sqrt(dir.x * dir.x + dir.z * dir.z);
		if (len > 1.f) {
			dir.x /= len;
			dir.z /= len;
		} else if (Base::gAxisSet) {
			dir.x = -Base::gFwd.x;   // straight back into the base
			dir.z = -Base::gFwd.z;
		} else {
			dir.x = 1.f;
			dir.z = 0.f;
		}
		p = at + dir * 560.f;
		if (!OnMap(p))
			return pos;
	}
	return p;
}

IUnitTask@ ExecuteWant(CCircuitUnit@ unit, Want@ w)
{
	// FINISH BEFORE FOUNDING, for EVERY static kind. The adoption block used
	// to sit below the branches that return early, so mex, mexup, tech, nano,
	// sense and protect never reached it -- their orphans (armrad 48, armmex
	// 43, armmoho 35, armnanotc 24 in one game) rotted while fresh sites
	// opened beside them.
	if ((w.def !is null) && !w.def.IsMobile()
		&& (w.kind != WK_RECLAIM) && (w.kind != WK_ASSIST))
	{
		IUnitTask@ orph0 = Requests::OrphanOf(w.def);
		if (orph0 !is null)
			return orph0;
		CCircuitUnit@ pf0 = Requests::PendAnyOfDef(w.def, unit.GetPos(ai.frame));
		if ((pf0 !is null)
			&& (Builder::ThreatFor(unit, pf0.GetPos(ai.frame))
				<= Builder::CON_THREAT_VETO))
		{
			float done0 = pf0.GetHealthPercent();
			if (done0 < 0.f)
				done0 = 0.f;
			else if (done0 > 1.f)
				done0 = 1.f;
			const float left0 = w.def.costM * (1.f - done0);
			const int hold0 = int(left0 / Requests::DRAIN) + 10;
			IUnitTask@ g0 = aiBuilderMgr.Enqueue(TaskB::Guard(
					Task::Priority::NORMAL, pf0, false, hold0 * SECOND));
			if (g0 !is null) {
				AiLog(Factory::T() + "apex: frame-adopt " + w.def.GetName()
					+ " done=" + formatFloat(done0, "", 0, 2)
					+ " at=" + int(pf0.GetPos(ai.frame).x)
					+ "," + int(pf0.GetPos(ai.frame).z));
				return g0;
			}
		}
	}
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
				Task::Priority::NORMAL,
				ClearOfLiveFactories(ClearOfSpots(w.pos, 180.f)), 256.f,
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
		// 600, not 300: the defence auction's best site jitters between
		// neighbouring cluster centres as the 2s cache refills, and at 300 the
		// re-elected want missed the standing request next door -- a new task
		// per election, each killing the last (117 tasks, 2 towers, watched).
		return Requests::Take(unit, w.def, Task::BuildType(bt),
				Task::Priority::NORMAL, w.pos, 600.f, SQUARE_SIZE * 16.f);
	}
	if (w.kind == WK_SUPER) {
		// A gantry is a factory and goes through the plant's own siting and
		// join; everything else here is a static weapon. BIG_GUN is the
		// engine's own build type for one, which the anti-nuke already used.
		// The mandated air plant is a factory the same way.
		if ((w.spotId == SC_GANTRY) || (w.spotId == SC_AIRPLANT)) {
			IUnitTask@ jg = JoinBig(w.def);
			if (jg !is null)
				return jg;
			return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
					Task::Priority::NORMAL,
					ClearOfLiveFactories(ClearOfSpots(w.pos, 180.f)), 256.f,
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
		IUnitTask@ rt = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL, tgt));
		if (rt !is null) {
			const int td = int(tgt.circuitDef.id);
			if (w.retire && !Catalog::gMobile[td])
				NoteDefRetired(td);
		}
		return rt;
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
				// FreeMetalFlow unclamped -- the 35 here was the same bare
				// floor the want side already removed, quietly capping which
				// sink could ever look hungry.
				const float feed2 = FreeMetalFlow();
				const float u2 = feed2 - drain - float(nanosAt) * NANO_ABSORB;
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
		// THE SINK'S OWN CENTER IS OCCUPIED GROUND. Every branch above names
		// the factory's or the frame's exact position, and the ask went out
		// with zero shake -- so the engine could not place the turret and the
		// task died unbuilt: measured 447 nano executions, FOUR frames ever
		// created, zero finished, in one 37-minute game. Probe for the
		// nearest legal cell inside assist reach instead -- cached on a 2s
		// clock per sink cell, because FindBuildSiteNear is an engine search
		// (same caution as WetPlantSite) and per-exec probing spiked one
		// election to 271ms.
		{
			const AIFloat3 raw = OnMap(slot) ? slot : w.pos;
			const int nk = (int(raw.x) >> 8) * 4096 + (int(raw.z) >> 8) + 1;
			if ((nk != gNanoSiteKey)
				|| (ai.frame - gNanoSiteAt >= 2 * SECOND))
			{
				gNanoSiteKey = nk;
				gNanoSiteAt = ai.frame;
				const double _tProbe = Perf::T0();
				gNanoSite = ai.FindBuildSiteNear(w.def, raw, 300.f);
				Perf::Add("exec.nanoprobe", _tProbe);
			}
			if (OnMap(gNanoSite))
				slot = gNanoSite;
		}
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
				? w.pos : ClearOfLiveFactories(ClearOfSpots(w.pos, 180.f));
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, at, 256.f, SQUARE_SIZE * 16.f);
	}
	return null;
}


}  // namespace Market
