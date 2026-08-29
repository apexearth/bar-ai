namespace Market {
int gNextELadderLog = 0;   // the mid-stall energy fallback, 10s apart
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
// THE EXIT LANE IS PART OF THE FACTORY (apexearth, watching live: "we just
// built a lab with a turret right in front of it - this is a great example
// of that bug where labs are built too close behind other things"). The
// engine's FindBuildSite proves the FOOTPRINT is legal and says nothing
// about the ground units must roll OUT across -- measured in that game: LLT
// at 2480,2880, the lab 13s later at 2376,2926, 114 elmos apart. Any of our
// own committed statics (ordered, framed or standing) inside the lane ahead
// of the site pushes the site one lattice pitch BACK, twice at most -- the
// engine's shake still owns the final legal square.
AIFloat3 ClearExitLane(const AIFloat3& in pos)
{
	if (!Base::Ready())
		return pos;
	AIFloat3 fwd = Base::gFwd;
	if (Base::AxisIsRearward()) {
		fwd.x = -fwd.x;
		fwd.z = -fwd.z;
	}
	AIFloat3 p = pos;
	for (uint tries = 0; tries < 3; ++tries) {
		bool blocked = false;
		for (uint i = 0; i < ComLen(); ++i) {
			const int d = gComDef[i];
			if (!Catalog::ValidId(d) || Catalog::gMobile[d]
				|| !OnMap(gComPos[i]))
				continue;
			const float rx = gComPos[i].x - p.x;
			const float rz = gComPos[i].z - p.z;
			const float ahead = rx * fwd.x + rz * fwd.z;
			if ((ahead < 40.f) || (ahead > 220.f))
				continue;   // behind or far enough ahead to drive around
			const float side = rx * fwd.z - rz * fwd.x;
			if ((side > -100.f) && (side < 100.f)) {
				blocked = true;
				break;
			}
		}
		if (!blocked)
			return p;
		p.x -= fwd.x * 96.f;
		p.z -= fwd.z * 96.f;
	}
	return p;
}

// The same lane, read the other way: is THIS site standing in the doorway
// of a factory we own or have coming? Towers took the ground in front of
// labs (his LLT at 114 elmos), so a ground-defence site inside any
// factory's exit lane slides sideways, across the axis, until clear.
AIFloat3 OffFactoryExit(const AIFloat3& in pos)
{
	if (!Base::Ready())
		return pos;
	AIFloat3 fwd = Base::gFwd;
	if (Base::AxisIsRearward()) {
		fwd.x = -fwd.x;
		fwd.z = -fwd.z;
	}
	AIFloat3 p = pos;
	for (uint tries = 0; tries < 3; ++tries) {
		bool inLane = false;
		for (uint i = 0; i < ComLen(); ++i) {
			const int d = gComDef[i];
			if (!Catalog::ValidId(d) || Catalog::gMobile[d]
				|| (Catalog::gBuildsList[d].length() == 0)
				|| !OnMap(gComPos[i]))
				continue;
			const float rx = p.x - gComPos[i].x;
			const float rz = p.z - gComPos[i].z;
			const float ahead = rx * fwd.x + rz * fwd.z;
			if ((ahead < 40.f) || (ahead > 220.f))
				continue;
			const float side = rx * fwd.z - rz * fwd.x;
			if ((side > -100.f) && (side < 100.f)) {
				inLane = true;
				break;
			}
		}
		if (!inLane)
			return p;
		p.x += fwd.z * 140.f;   // across the axis, out of the doorway
		p.z -= fwd.x * 140.f;
	}
	return p;
}

AIFloat3 ClearOfLiveFactories(const AIFloat3& in pos)
{
	AIFloat3 p = pos;
	for (uint tries = 0; tries < 4; ++tries) {
		bool near = false;
		AIFloat3 at;
		// Ledger COMING plant rows (flipped 2026-08-27): an orphaned factory
		// frame blocks its ground exactly as an ordered one does.
		for (uint i = 0; i < ComLen(); ++i) {
			if ((gComState[i] == CS_FINISHED)
				|| (Catalog::gBuildsList[gComDef[i]].length() == 0))
				continue;
			if (OnMap(gComPos[i]) && (p.distance2D(gComPos[i]) < 512.f)) {
				at = gComPos[i];
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

// A detour to finish existing work must pay for itself: the EXTRA walk (past
// the site the want was priced for) at the wage, against the metal already
// standing in the work. Adoption used to be distance-blind -- "the same frame
// WHEREVER it stands" -- which re-aimed a winner across the map on a want
// priced for the site beside him (his report: the commander pulled all the
// way home for work his election never priced).
bool AdoptWorthDetour(CCircuitUnit@ unit, Want@ w, const AIFloat3 &in at,
		float done)
{
	if (!OnMap(at))
		return false;
	const AIFloat3 up = unit.GetPos(ai.frame);
	const float dFrame = up.distance2D(at);
	const float dSite = OnMap(w.pos) ? up.distance2D(w.pos) : dFrame;
	const float extra = dFrame - dSite;
	if (extra <= 0.f)
		return true;   // on the way, or closer than the priced site
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float extraSec = (speed > 1.f) ? (extra / speed) : 60.f;
	float d0 = done;
	if (d0 < 0.f) d0 = 0.f;
	else if (d0 > 1.f) d0 = 1.f;
	return extraSec * Wage() <= d0 * ((w.def is null) ? 0.f : w.def.costM);
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
		if ((orph0 !is null) && AdoptWorthDetour(unit, w,
				orph0.GetBuildPos(), Requests::Progress(orph0)))
			return orph0;
		CCircuitUnit@ pf0 = Requests::PendAnyOfDef(w.def, unit.GetPos(ai.frame));
		if ((pf0 !is null)
			&& (Builder::ThreatFor(unit, pf0.GetPos(ai.frame))
				<= Builder::CON_THREAT_VETO)
			&& AdoptWorthDetour(unit, w, pf0.GetPos(ai.frame),
				pf0.GetHealthPercent()))
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
	// THE DOOR. His stated laws, checked where the metal is spent -- a logged
	// backstop, never the mechanism: the pricing above is supposed to make
	// these fire ZERO times, and the audit asserts exactly that. Placed AFTER
	// the adoption block so finishing a standing frame is never refused.
	// Law 1: no founding a copy of a plant we already run (the escape is a
	// substitute that cannot exist -- see DupBpSubstMul).
	if ((w.def !is null) && !w.def.IsMobile()
		&& (w.kind != WK_RECLAIM) && (w.kind != WK_ASSIST)
		&& (Catalog::gBuildsList[int(w.def.id)].length() > 0)
		&& !UnlocksProduct(int(w.def.id))
		&& (ComCountOf(int(w.def.id), CS_FINISHED)
			+ ComCountManned(int(w.def.id), CS_FRAMED | CS_ORDERED) >= 1)
		&& (DupBpSubstMul(int(w.def.id)) < 1.f))
	{
		if (!WealthWaiver()) {
			AiLog("apex: INVARIANT plant-copy refused t=" + ai.teamId + " "
				+ w.def.GetName()
				+ " fin=" + ComCountOf(int(w.def.id), CS_FINISHED)
				+ " coming=" + ComCountManned(int(w.def.id), CS_FRAMED | CS_ORDERED));
			return null;
		}
		AiLog("apex: copy waived t=" + ai.teamId + " " + w.def.GetName()
			+ " overflow=" + int(OverflowM()));
		NoteCopyWaived(int(w.def.id));
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
		// Probed last: the C++ reach-safe veto marks refused ground, and a
		// deterministic site would otherwise be re-elected into it forever.
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL,
				ProbedSite(w.def, Catalog::Def(int(unit.circuitDef.id)),
					OffFactoryExit(ClearExitLane(
						ClearOfLiveFactories(ClearOfSpots(w.pos, 180.f))))),
				256.f, SQUARE_SIZE * 16.f);
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
				Task::Priority::NORMAL,
				groundDef ? OffFactoryExit(w.pos) : w.pos,
				600.f, SQUARE_SIZE * 16.f);
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
			// The claim's clock is the eat time (cost/90, the same arithmetic
			// tCost uses) plus a walk pad; expiry frees a dead worker's victim.
			NoteReclaimClaim(tgt.id, unit.id,
					ai.frame + int((60.f + Catalog::gCostM[td] / 90.f) * SECOND),
					tgt, tgt.GetPos(ai.frame));
			if (gReclaimTgt.length() > 1)
				AiLog("apex: reclaim-parallel t=" + ai.teamId
						+ " victims=" + gReclaimTgt.length());
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
		bool lineSited = false;
		{
			AIFloat3 lp;
			const float ln = NeediestLine(lp);
			if ((ln > 0.f) && OnMap(lp)) {
				worst = ln;
				slot = lp;
				sited = true;
				lineSited = true;
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
				// Priced in the want side's currency (site_share) -- unshared
				// feed here let a sink outbid the line that won the want.
				const float feed2 = FreeMetalFlow()
						* ai.GetTunable("apex_nano_site_share", TUNE_NANO_SITE_SHARE);
				float u2 = feed2 - drain - float(nanosAt) * NANO_ABSORB;
				// Same remaining-life scale as the want side (see
				// want_nano.as): a frame's stream dies at completion, a
				// line's does not.
				{
					const float eat2 = drain + float(nanosAt) * NANO_ABSORB;
					const float H2 = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
					float life2 = Catalog::gCostM[bd3]
							/ ((eat2 > NANO_ABSORB) ? eat2 : NANO_ABSORB);
					float sh2 = life2 / ((H2 > 1.f) ? H2 : 900.f);
					if (sh2 < 1.f)
						u2 *= sh2;
				}
				if (u2 > worst) {
					worst = u2;
					slot = sp;
					sited = true;
					lineSited = false;
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
		if (lineSited)
			AiLog("apex: nano-to-line t=" + ai.teamId
					+ " need=" + formatFloat(worst, "", 0, 1));
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
			// EACH ASKER PROBES ITS OWN BEARING. Every decider converges on
			// the argmax site, the shared 2s cache handed them all the SAME
			// legal cell, and every ask after the first died "covered" at it
			// -- covered=304 vs new=274 in his 3v3 while 74k overflowed
			// ("we have tons of room to build nanos and we aren't making
			// them"). A per-asker radial origin spreads the ring around the
			// line; the 64-elmo cover radius still stops true doubles, and
			// the probe stays cached per bearing (exec.nanoprobe watches
			// the cost).
			const int spoke = int(unit.id) & 7;
			const float angN = float(spoke) * 0.785398f;
			const AIFloat3 rawN = raw
					+ AIFloat3(cos(angN), 0.f, sin(angN))
					* (96.f + 48.f * float(int(unit.id) % 3));
			const int nk = (int(raw.x) >> 8) * 4096 + (int(raw.z) >> 8) + 1
					+ (spoke + 1) * 16777216;
			if ((nk != gNanoSiteKey)
				|| (ai.frame - gNanoSiteAt >= 2 * SECOND))
			{
				gNanoSiteKey = nk;
				gNanoSiteAt = ai.frame;
				const double _tProbe = Perf::T0();
				gNanoSite = ai.FindBuildSiteNear(w.def,
						OnMap(rawN) ? rawN : raw, 300.f);
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
		const AIFloat3 nSlot = OnMap(slot) ? slot : w.pos;
		IUnitTask@ nFirst = Requests::Take(unit, w.def, Task::BuildType::NANO,
				Task::Priority::NORMAL, nSlot, 64.f, 0.f,
				made, true);
		// HOW MANY, NOT WHETHER (apexearth: "the single build request could
		// expand out into 2, 5, 10, 20, whatever we can afford" -- and, on
		// the first draft's flow arithmetic: "your logic of 'each nano
		// absorbs 17.5m/s' is not the right mentality... if we have 2000
		// metal in the bank and we are surplus metal income then just go
		// ahead and make 10 easy"). So: BANKED METAL DIVIDED BY THE PRICE,
		// whenever income runs surplus -- no absorption model, no full-bank
		// gate. The extras stand as unmanned requests adopt-orphan hands to
		// the next askers; the ring bearings keep them off each other's
		// ground. No cap: the bank is the bound and surplus refills it.
		if (nFirst !is null) {
			const float bankN = aiEconomyMgr.metal.current;
			if (aiEconomyMgr.metal.income > aiEconomyMgr.metal.pull) {
				const float perM = Catalog::gCostM[int(w.def.id)];
				int wantN = int((bankN / ((perM > 1.f) ? perM : 200.f)) + 0.5f);
				wantN -= int(Requests::InFlight(w.def));
				if (wantN > 1) {
					int opened = 0;
					const int baseSpoke = int(unit.id) & 7;
					// ACROSS EVERY LINE, NOT ONE RING (his watch at 46m: one
					// cluster of 217 turrets, bare gantries, batch +1 with
					// covered=662 and tooFar=77k -- the extras all aimed at
					// one site whose 8 spokes fill instantly, at a ring step
					// tighter than the cover radius). Round-robin over the
					// standing factories, ring step wider than cover, so the
					// bank turns into lathe AROUND the lines everywhere.
					const uint nFacs = Factory::gFacUnits.length();
					for (int k = 1; k < wantN; ++k) {
						AIFloat3 baseK = nSlot;
						if (nFacs > 0) {
							CCircuitUnit@ fK = Factory::gFacUnits[uint(k) % nFacs];
							if (fK !is null) {
								const AIFloat3 fp = fK.GetPos(ai.frame);
								if (OnMap(fp))
									baseK = fp;
							}
						}
						const float angK = float((baseSpoke + k) & 7)
								* 0.785398f + 0.3926991f;
						const AIFloat3 pk = baseK
								+ AIFloat3(cos(angK), 0.f, sin(angK))
								* (110.f + 80.f * float(k >> 3));
						if (!OnMap(pk))
							continue;
						bool mk = false;
						IUnitTask@ tk = Requests::Take(null, w.def,
								Task::BuildType::NANO, Task::Priority::NORMAL,
								pk, 64.f, float(SQUARE_SIZE) * 4.f, mk, true);
						if (mk)
							++opened;
					}
					if (opened > 0)
						AiLog("apex: nano batch t=" + ai.teamId
							+ " +" + opened
							+ " over=" + int(OverflowM())
							+ " bank=" + int(bankN));
				}
			}
		}
		return nFirst;
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
	// GIANTS MULTIPLY ONLY ON A BANK THAT PAYS FOR ALL OF THEM (apexearth,
	// watching a fusion and two AFUS rise beside 1-2 standing fusions: "it
	// was bad scaling. We would have done better early on without that").
	// The wealth-parallel branch opened big-energy frames the bank could
	// not cover -- 24k of parallel bills on a 14k bank. His own test,
	// applied to the giants: parallel only while the bank could pay the
	// whole in-flight big-energy fleet plus this one outright; otherwise
	// the ask folds onto the frame already rising.
	if (par && (w.kind == WK_ENERGY) && (w.def !is null)
		&& (Catalog::gCostM[int(w.def.id)] >= 2500.f)) {
		float gBill = Catalog::gCostM[int(w.def.id)];
		for (uint gi = 0; gi < ComLen(); ++gi) {
			if (gComState[gi] == CS_FINISHED)
				continue;
			const int gd = gComDef[gi];
			if (!Catalog::ValidId(gd) || Catalog::gMobile[gd])
				continue;
			if ((Catalog::gCostM[gd] >= 2500.f) && (Catalog::gMakeE[gd] >= 400.f))
				gBill += Catalog::gCostM[gd];
		}
		if (aiEconomyMgr.metal.current < gBill)
			par = false;
	}
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
			// Cross-def: an elected advsol joins the fusion being built.
			IUnitTask@ jt = JoinBigEnergy(unit, w.def);
			if (jt !is null)
				return jt;
		}
		if (Catalog::gCostM[int(w.def.id)] > 500.f)
			w.pos = ClearOfSpots(w.pos, 150.f);
		IUnitTask@ et = Requests::Take(unit, w.def, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, cell, 0.f,
				crtd, par);
		if (et !is null)
			return et;
		// REFUSED IS NOT "NOTHING TO DO" WHILE WE ARE STALLED. The rung the
		// proposer picked can be unstartable on its own terms -- an advanced
		// solar is strictly serial, a def at its in-flight cap answers "full"
		// -- and the asker then idles through the very stall it was elected to
		// answer (apexearth, watching: the commander "could be making a basic
		// solar" and instead "sits around waiting for the energy situation to
		// get fixed"). So walk down the same ladder the proposer already priced
		// and take the best rung that will actually start. Only while HARD
		// stalled: outside one, the serialization is the rule that stops a base
		// of wind turbines, and a builder with no energy job has other work.
		if (!HardEStall() || (unit is null) || (gEAltFor != int(unit.id)))
			return null;
		// Zero-E rungs first whatever they priced: mid-stall the cheap solar is
		// the answer even when a dearer generator outranks it, and the dear one
		// is only reached if no solar can be placed at all.
		for (uint pass = 0; pass < 2; ++pass) {
		for (uint k = 0; k < gEAlt.length(); ++k) {
			const int ad = gEAlt[k];
			if ((w.def !is null) && (ad == int(w.def.id)))
				continue;
			if ((pass == 0) && (Catalog::gCostE[ad] > 0.f))
				continue;
			CCircuitDef@ adef = Catalog::Def(ad);
			if (adef is null)
				continue;
			const AIFloat3 aslot = gFarmSet ? FarmSlot(ad) : BigEnergySite();
			bool acrtd = false;
			IUnitTask@ at = Requests::Take(unit, adef, Task::BuildType::ENERGY,
					Task::Priority::NORMAL, OnMap(aslot) ? aslot : w.pos,
					Lattice::StrideOf(ad), 0.f, acrtd, par);
			if (at is null)
				continue;
			if (ai.frame >= gNextELadderLog) {
				gNextELadderLog = ai.frame + 10 * SECOND;
				AiLog("apex: e-ladder " + unit.circuitDef.GetName() + " #" + unit.id
					+ " refused " + w.def.GetName() + " mid-stall -> "
					+ adef.GetName());
			}
			return at;
		}
		}
		return null;
	}
	if (w.kind == WK_CONVERT) {
		const AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id)) : w.pos;
		return Requests::Take(unit, w.def, Task::BuildType::CONVERT,
				Task::Priority::NORMAL, OnMap(slot) ? slot : w.pos, cell, 0.f,
				crtd, par);
	}
	if (w.kind == WK_STORE) {
		// Law 2, a tripwire: his ruling is "Stop making storage" and
		// ProposeStore proposes nothing -- anything reaching this branch is a
		// regression re-arming storage from some other path.
		AiLog("apex: INVARIANT no-storage refused t=" + ai.teamId + " "
			+ w.def.GetName());
		return null;
	}
	if (w.kind == WK_PLANT) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		// A floating plant keeps the water it was priced against -- the
		// spot-clearance nudge walks the base axis and puts a shipyard inland.
		// ...and never in ANOTHER factory's doorway either (his live catch:
		// "a t1 vehicle lab blocked by a T2 vehicle lab").
		const AIFloat3 at = Catalog::gFloater[int(w.def.id)]
				? w.pos
				: ProbedSite(w.def, Catalog::Def(int(unit.circuitDef.id)),
					OffFactoryExit(ClearExitLane(
						ClearOfLiveFactories(ClearOfSpots(w.pos, 180.f)))));
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, at, 256.f, SQUARE_SIZE * 16.f);
	}
	return null;
}


}  // namespace Market
