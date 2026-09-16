namespace Market {
int gNextELadderLog = 0;   // the mid-stall energy fallback, 10s apart
// The nano placement probe's cache (see the WK_NANO branch).
int gNextNanoBatchLog = 0;
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
		// The lane is 220 ahead by 100 wide, so nothing outside a 242-elmo box
		// can be in it -- the ledger walk was reading the whole base to find it.
		ComNear(p, 242.f);
		for (uint q = 0; q < gComGrid.hit.length(); ++q) {
			const uint i = uint(gComGrid.hit[q]);
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
		ComNear(p, 242.f);   // same 220x100 lane box as ClearExitLane
		for (uint q = 0; q < gComGrid.hit.length(); ++q) {
			const uint i = uint(gComGrid.hit[q]);
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
		// Lowest row wins, because the walk this replaces took the first match
		// in ledger order and the bucket order is not that order.
		int firstRow = -1;
		ComNear(p, 512.f);
		for (uint q = 0; q < gComGrid.hit.length(); ++q) {
			const uint i = uint(gComGrid.hit[q]);
			if ((gComState[i] == CS_FINISHED)
				|| (Catalog::gBuildsList[gComDef[i]].length() == 0))
				continue;
			if (OnMap(gComPos[i]) && (p.distance2D(gComPos[i]) < 512.f)
				&& ((firstRow < 0) || (int(i) < firstRow)))
			{
				firstRow = int(i);
			}
		}
		if (firstRow >= 0) {
			at = gComPos[uint(firstRow)];
			near = true;
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

// PAYING BACK THE STALL INTERRUPT (army.as carries the ledger; this is the
// only half that spends). The frame this unit abandoned is standing with
// nothing bound to it, and the finish-before-founding block below cannot reach
// it: that one only ever looks for an orphan of the def the market JUST
// picked, and the market does not pick the plant again -- the ledger reads it
// as committed, so the next election buys an LLT beside him instead
// (apexearth: "makes a solar, and then decides to make an LLT instead of going
// back to the factory").
//
// A Guard on the frame, not a build task: a build order needs a free square
// and the frame is standing on the only one that matters -- the same shape
// Take() and the adoption block use. Held for as long as the frame has left to
// run at one pair of hands.
IUnitTask@ StallDebtPay(CCircuitUnit@ unit)
{
	CCircuitUnit@ frame = StallDebtFrame(unit);
	if ((frame is null) || (frame.circuitDef is null))
		return null;
	float done = frame.GetHealthPercent();
	if (done < 0.f)
		done = 0.f;
	else if (done > 1.f)
		done = 1.f;
	const float left = frame.circuitDef.costM * (1.f - done);
	const int hold = int(left / Requests::DRAIN) + 10;
	IUnitTask@ res = aiBuilderMgr.Enqueue(TaskB::Guard(
			Task::Priority::NORMAL, frame, false, hold * SECOND));
	if (res is null)
		return null;   // the row stands: he owes it at the next election too
	StallDebtSettle(unit);
	const AIFloat3 fp = frame.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: stall-debt paid " + unit.circuitDef.GetName()
		+ " #" + unit.id + " -> " + frame.circuitDef.GetName()
		+ " done=" + formatFloat(done, "", 0, 2)
		+ " at=" + int(fp.x) + "," + int(fp.z)
		+ " (paid=" + DebtPaid() + " dropped=" + DebtDropped() + ")");
	return res;
}

int gMexupNullLogAt = 0;

// A second copy of a plant we own prices zero (the forwarding ruling), and
// the executor refuses it below. The proposers ask this first: the super
// want offered a second T2 air plant 454 times in one game, hoisted past
// the lottery each time, refused each time, and every hand that drew it
// fell to its second pick while the nano wants went unbuilt.
bool PlantCopyRefusable(int d)
{
	if (!Catalog::ValidId(d) || Catalog::gMobile[d])
		return false;
	return (Catalog::gBuildsList[d].length() > 0)
		&& !UnlocksProduct(d)
		&& (ComCountOf(d, CS_FINISHED) + ComCountManned(d, CS_FRAMED | CS_ORDERED) >= 1)
		&& (DupBpSubstMul(d) < 1.f)
		&& !CopyWaived(d);
}

IUnitTask@ ExecuteWant(CCircuitUnit@ unit, Want@ w)
{
	// FINISH BEFORE FOUNDING, for EVERY static kind. The adoption block used
	// to sit below the branches that return early, so mex, mexup, tech, nano,
	// sense and protect never reached it -- their orphans rotted while fresh
	// sites opened beside them.
	if ((w.def !is null) && !w.def.IsMobile()
		&& (w.kind != WK_RECLAIM) && (w.kind != WK_ASSIST))
	{
		const double _tOr = Perf::T0();
		IUnitTask@ orph0 = Requests::OrphanOf(w.def);
		Perf::Add("xw.orph", _tOr);
		if ((orph0 !is null) && AdoptWorthDetour(unit, w,
				orph0.GetBuildPos(), Requests::Progress(orph0)))
			return orph0;
		const double _tPe = Perf::T0();
		CCircuitUnit@ pf0 = Requests::PendAnyOfDef(w.def, unit.GetPos(ai.frame));
		Perf::Add("xw.pend", _tPe);
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
	if ((w.def !is null) && (w.kind != WK_RECLAIM) && (w.kind != WK_ASSIST)
		&& PlantCopyRefusable(int(w.def.id)))
	{
		AiLog("apex: INVARIANT plant-copy refused t=" + ai.teamId + " "
			+ w.def.GetName()
			+ " fin=" + ComCountOf(int(w.def.id), CS_FINISHED)
			+ " coming=" + ComCountManned(int(w.def.id), CS_FRAMED | CS_ORDERED));
		return null;
	}
	if ((w.def !is null) && !w.def.IsMobile()
		&& (w.kind != WK_RECLAIM) && (w.kind != WK_ASSIST)
		&& (Catalog::gBuildsList[int(w.def.id)].length() > 0)
		&& !UnlocksProduct(int(w.def.id))
		&& (ComCountOf(int(w.def.id), CS_FINISHED)
			+ ComCountManned(int(w.def.id), CS_FRAMED | CS_ORDERED) >= 1)
		&& (DupBpSubstMul(int(w.def.id)) < 1.f))
	{
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
		IUnitTask@ mu = aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEXUP,
				Task::Priority::NORMAL, w.def, w.pos, w.spotId));
		if ((mu is null) && (ai.frame >= gMexupNullLogAt)) {
			gMexupNullLogAt = ai.frame + 5 * SECOND;
			AiLog("apex: mexup-null t=" + ai.teamId + " " + unit.circuitDef.GetName() + " #" + unit.id
				+ " " + w.def.GetName() + " spot=" + w.spotId + " at=" + int(w.pos.x) + "," + int(w.pos.z)
				+ " canBuild=" + (unit.circuitDef.CanBuild(w.def) ? 1 : 0));
		}
		return mu;
	}
	if (w.kind == WK_TECH) {
		IUnitTask@ jt = JoinBig(w.def);
		if (jt !is null)
			return jt;
		// Probed last: the C++ reach-safe veto marks refused ground, and a
		// deterministic site would otherwise be re-elected into it forever.
		// A FLOATING plant keeps the water it was priced against -- the
		// spot-clearance and exit-lane nudges walk the base axis and would
		// put an advanced shipyard inland, the same exemption ProposePlant
		// already makes for the T1 one.
		const AIFloat3 tAt = Catalog::gFloater[int(w.def.id)]
				? w.pos
				: ProbedSite(w.def, Catalog::Def(int(unit.circuitDef.id)),
					OffFactoryExit(ClearExitLane(
						ClearOfLiveFactories(ClearOfSpots(w.pos, 180.f)))));
		return Requests::Take(unit, w.def, Task::BuildType::FACTORY,
				Task::Priority::NORMAL, tAt, 256.f, SQUARE_SIZE * 16.f);
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
		// Ground the C++ reach veto has refused is re-probed, not re-taken:
		// a targeting facility was elected into the same unreachable corner
		// 21 times in a row, eating a fifth of the eco seat's elections.
		AIFloat3 sAt = groundDef ? OffFactoryExit(w.pos) : w.pos;
		if (NearBlocked(sAt))
			sAt = ProbedSite(w.def, Catalog::Def(int(unit.circuitDef.id)), sAt);
		bool sMade = false;
		IUnitTask@ sTask = Requests::Take(unit, w.def, Task::BuildType(bt),
				Task::Priority::NORMAL, sAt, 600.f, SQUARE_SIZE * 16.f, sMade);
		// The team hears the order now, not when the frame appears.
		if (sMade && !groundDef)
			PublishSenseClaim(w.spotId, sAt);
		return sTask;
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
	if (w.kind == WK_TEETH) {
		return Requests::Take(unit, w.def, Task::BuildType::DEFENCE,
				Task::Priority::LOW, w.pos, 300.f, SQUARE_SIZE * 4.f);
	}
	if (w.kind == WK_ASSIST) {
		// The ID, never the handle, decides whether this is still the boss
		// the want priced -- reading .id off a destroyed unit IS the crash
		// this pattern causes (see gAssistTargetId).
		if ((gAssistTarget is null) || (int(gAssistTargetId) != w.spotId))
			return null;
		IUnitTask@ gt = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::LOW,
				gAssistTarget, false, gAssistGuardS * SECOND));
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
		// A floor turret stands at its factory; nothing below re-sites it.
		bool sited = (w.spotId == NS_FLOOR) && OnMap(w.pos);
		// The line's pull is priced ONCE, in NeediestLine, so the turret is
		// sited by the same arithmetic that bought it.
		float worst = 0.f;
		bool lineSited = false;
		// THE HELD FRONT LINE FIRST (apexearth: "make nano turrets up there.
		// If we're fighting enemies, we can fight within range of our nano
		// turrets and then get healed while we fight"; his fortification
		// doctrine's fourth point). A pitch behind the guns, one per
		// section -- while no lathe stands or is ordered within this one's
		// reach of the line's centre and the ground is plainly ours.
		if (!sited) {
			AIFloat3 fl;
			float flGuns = 0.f;
			const float bd = Catalog::gBuildDist[int(w.def.id)];
			if ((bd > 1.f) && WallSupportSlot(bd, fl, flGuns)) {
				slot = fl;
				sited = true;
				lineSited = true;
			}
		}
		if (!sited) {
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
		if ((w.spotId != NS_FLOOR) && (mSt > 1.f) && (aiEconomyMgr.metal.current > mSt
				* ai.GetTunable("apex_nano_sink_bank", TUNE_NANO_SINK_BANK))) {
			// Same hoist as the want side: one free-flow read for the walk.
			const float skFeed = FreeMetalFlow()
					* ai.GetTunable("apex_nano_site_share", TUNE_NANO_SITE_SHARE);
			const float skH = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
			for (uint li = 0; li < Requests::gLive.length(); ++li) {
				IUnitTask@ lt = Requests::gLive[li];
				if ((lt is null) || (lt.buildDef is null))
					continue;
				// BIG SITES ONLY, as the want side prices them: unfiltered,
				// this loop parked turrets at 50-metal MEXES and stole every
				// one a queued lab had asked for (measured: 13 of 14 sinks
				// were armmex/armmakr).
				const int bd3 = int(lt.buildDef.id);
				if (!NanoSinkWorthy(bd3))
					continue;
				array<CCircuitUnit@>@ crew = lt.GetUnits();
				if ((crew is null) || (crew.length() == 0))
					continue;
				const AIFloat3 sp = lt.GetBuildPos();
				if (!OnMap(sp))
					continue;
				// The sink's own metal density converts BP on it into m/s,
				// as the want side prices it.
				const float sdens2 = (Catalog::gBuildTime[bd3] > 1.f)
						? (Catalog::gCostM[bd3] / Catalog::gBuildTime[bd3])
						: (7.f / 80.f);
				float drain = 0.f;
				for (uint ci = 0; ci < crew.length(); ++ci) {
					if (crew[ci] !is null)
						drain += Catalog::gBuildPower[int(crew[ci].circuitDef.id)]
								* sdens2;
				}
				const float ringEat2 = RingBPAt(sp) * sdens2;
				// The crew is SUPPLY, not demand: a frame whose cons already
				// eat the free flow earns nothing from another turret.
				// Priced in the want side's currency (site_share) -- unshared
				// feed here let a sink outbid the line that won the want.
				float u2 = skFeed - drain - ringEat2;
				// Same remaining-life scale as the want side (see
				// want_nano.as): a frame's stream dies at completion, a
				// line's does not.
				{
					const float eat2 = drain + ringEat2;
					const float oneNano2 = 200.f * sdens2;
					float life2 = Catalog::gCostM[bd3]
							/ ((eat2 > oneNano2) ? eat2 : oneNano2);
					float sh2 = life2 / ((skH > 1.f) ? skH : 900.f);
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
				if (!NanoSinkWorthy(bd2))
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
					+ " need=" + formatFloat(worst, "", 0, 1)
					+ " src=" + w.spotId);
		// THE SINK'S OWN CENTER IS OCCUPIED GROUND. Every branch above names
		// the factory's or the frame's exact position, so the turret can
		// never stand on it: measured 447 nano executions, FOUR frames ever
		// created, zero finished, in one 37-minute game.
		//
		// PACKED, NOT SCATTERED (apexearth 2026-08-31: "We tend to space our
		// nano turrets too much. They use too much room... nano turrets
		// should prefer to be placed right next to each other"). The old
		// answer put each asker on its own compass spoke 96-192 elmos out and
		// then let an engine search wander 300 further, so a ring of turrets
		// took several times the ground the same lathe needs. Now the walk
		// starts at the cell TOUCHING the anchor's footprint and takes the
		// first one nothing has claimed, which is the definition of packing.
		//
		// The doorway is the only ground it refuses -- and only for a plant
		// whose units roll (see PackSlots).
		const int nAnchor = AnchorDefAt(OnMap(slot) ? slot : w.pos);
		const float nPitch = Lattice::FootPitch(int(w.def.id));
		array<AIFloat3> nPacked;
		{
			const double _tProbe = Perf::T0();
			PackSlots(int(w.def.id), OnMap(slot) ? slot : w.pos,
					nAnchor, 1, nPacked);
			Perf::Add("xw.nanoprobe", _tProbe);
		}
		if (Catalog::ValidId(nAnchor) && (Catalog::gBuildsList[nAnchor].length() > 0))
			NoteNanoDry(nAnchor, nPacked.length() == 0);
		if (nPacked.length() > 0) {
			slot = nPacked[0];
		} else {
			// Every cell in reach is taken. The engine's own search is the
			// fallback, cached as before -- an asker that finds no packed
			// cell must still be able to place somewhere rather than idle.
			const AIFloat3 raw = OnMap(slot) ? slot : w.pos;
			const int nk = (int(raw.x) >> 8) * 4096 + (int(raw.z) >> 8) + 1;
			if ((nk != gNanoSiteKey)
				|| (ai.frame - gNanoSiteAt >= 2 * SECOND))
			{
				gNanoSiteKey = nk;
				gNanoSiteAt = ai.frame;
				const double _tProbe2 = Perf::T0();
				gNanoSite = ai.FindBuildSiteNear(w.def, raw, 300.f);
				Perf::Add("xw.nanoprobe", _tProbe2);
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
		// COVER MUST BE NARROWER THAN THE PITCH. CoverFor treats any live
		// request of the same def inside `radius` as the same job, so the flat
		// 64 refused every cell a 48-elmo lattice offers next door -- packing
		// and the cover test cannot both be right at the same radius. Half a
		// pitch still folds two asks aimed at one cell, which is all it was
		// ever for; PackSlots is what keeps distinct asks off each other.
		const float nCover = (nPitch > 2.f) ? (nPitch * 0.5f) : 64.f;
		IUnitTask@ nFirst = Requests::Take(unit, w.def, Task::BuildType::NANO,
				Task::Priority::NORMAL, nSlot, nCover, 0.f,
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
				// A WORK SLICE, NOT A NANO CAP: each Take below is a ledger
				// collision scan, and a rich bank asked for 100+ in ONE
				// execution -- exec.knano measured 11.7ms per call, the
				// single largest exec cost. Executions recur (56/min in the
				// same game), InFlight subtracts what stands, so the bank
				// still converts to the same request total within seconds --
				// the work just stops landing inside one sim frame.
				if (wantN > 16)
					wantN = 16;
				if (wantN > 1) {
					int opened = 0;
					// ACROSS EVERY LINE, NOT ONE RING (his watch at 46m: one
					// cluster of 217 turrets, bare gantries, batch +1 with
					// covered=662 and tooFar=77k -- the extras all aimed at
					// one site whose 8 spokes fill instantly). Round-robin
					// over the standing factories, each asked ONCE for the
					// packed cells beside it: one lattice walk per line
					// rather than one per turret, because a walk per turret
					// re-scans the same rings and that is the bulk-in-one-
					// frame shape the frame budget forbids.
					const double _tBatch = Perf::T0();
					const uint nFacs = Factory::gFacUnits.length();
					int left = wantN - 1;
					const uint lines = (nFacs > 0) ? nFacs : 1;
					string walkLog = "";
					string lastRef = "";
					// BY UNSERVED SPEND, NOT BY HEAD (apexearth 2026-09-13, on
					// their one gantry under 170 nanos against our six under
					// fewer: "fewer Gantries -- but to better support the
					// gantries we have with nanos"). An equal split handed an
					// idle air plant as much as the working gantry.
					const float bFeed = FreeMetalFlow();
					const float bFloor = LineSpend();
					const float bCeil = LineCeilSum();
					array<float> needK(nFacs, 0.f);
					float needSum = 0.f;
					for (uint fk = 0; fk < nFacs; ++fk) {
						needK[fk] = LineUnserved(Factory::gFacUnits[fk], bFeed, bFloor, bCeil);
						needSum += needK[fk];
					}
					for (uint fi2 = 0; (fi2 < lines) && (left > 0); ++fi2) {
						AIFloat3 baseK = nSlot;
						int anchorK = nAnchor;
						int askK = left / int(lines - fi2);
						if (nFacs > 0) {
							CCircuitUnit@ fK = Factory::gFacUnits[fi2];
							if (fK is null)
								continue;
							const AIFloat3 fp = fK.GetPos(ai.frame);
							if (!OnMap(fp))
								continue;
							baseK = fp;
							anchorK = int(fK.circuitDef.id);
							if (needSum > 0.f) {
								if (needK[fi2] <= 0.f)
									continue;
								askK = int(float(wantN - 1) * needK[fi2] / needSum + 0.5f);
								if (askK > left)
									askK = left;
							}
						}
						if (askK < 1)
							askK = 1;
						array<AIFloat3> packK;
						PackSlots(int(w.def.id), baseK, anchorK, askK, packK);
						if (nFacs > 0)
							NoteNanoDry(anchorK, packK.length() == 0);
						walkLog += " " + Catalog::Def(anchorK).GetName()
								+ ":ask" + askK + "/got" + packK.length()
								+ "/taken" + gNPTaken + "/lane" + gNPLane
								+ "/door" + gNPDoor + "/out" + gNPOut;
						int folded = 0;
						int refused = 0;
						for (uint si2 = 0; si2 < packK.length(); ++si2) {
							bool mk = false;
							IUnitTask@ tk = Requests::Take(null, w.def,
									Task::BuildType::NANO,
									Task::Priority::NORMAL,
									packK[si2], nCover, 0.f, mk, true);
							if (mk) {
								++opened;
								--left;
							} else if (tk !is null) {
								++folded;
							} else {
								++refused;
								lastRef = Requests::gLastWhat;
							}
						}
						walkLog += "/fold" + folded + "/ref" + refused
								+ ((refused > 0) ? (":" + lastRef) : "");
					}
					Perf::Add("xw.nanobatch", _tBatch);
					if ((opened > 0) || (ai.frame >= gNextNanoBatchLog)) {
						gNextNanoBatchLog = ai.frame + 30 * SECOND;
						AiLog("apex: nano batch t=" + ai.teamId
							+ " +" + opened + " want=" + wantN
							+ " over=" + int(OverflowM())
							+ " bank=" + int(bankN) + walkLog);
					}
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
	// Energy short of what is ordered AND a bank that covers the rung: the
	// metal is there to feed a second site. MCostScale reads 1 in a stall
	// (requests outrun income while the bank sits at 90%), so the parallel
	// flag was off exactly when the deficit needed it.
	bool par = (MCostScale() < 1.f)
			|| ((w.kind == WK_ENERGY) && (EnergyShortOfOrdered()
				|| ((EnergyDeficitE() > 0.f) && (w.def !is null)
					&& Requests::BankCovers(w.def))));
	// ...and OVERFLOWING ENERGY opens them for the one building that exists to
	// absorb it. The test above reads the METAL side only -- MCostScale is a
	// metal stall -- so a converter, whose entire trigger is energy we are
	// throwing away, was serialized to one site at a time exactly when twenty
	// were wanted.
	if ((w.kind == WK_CONVERT) && (gESurplusEma > 1.f))
		par = true;
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
		AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id), unit) : BigEnergySite();
		// A DETERMINISTIC SLOT RE-ELECTED INTO REFUSED GROUND IS A DEADLOCK.
		// FarmSlot is a pure function of the farm, so when the C++ reach-safe
		// veto refuses that ground the next election computes the same answer
		// and the task dies again. Tech, plant and super already probe for
		// exactly this reason (see WK_TECH above); energy did not, and it is
		// the one that builds the fusions -- a team can lose every advanced
		// fusion it orders at one position with why=unreach-safe.
		//
		// Probed ONLY when the mark is near this slot, so the farm's packing --
		// generators beside their own kind, in the rear -- is untouched in
		// every other case.
		if ((unit !is null) && NearBlocked(slot)) {
			slot = ProbedSite(w.def,
					Catalog::Def(int(unit.circuitDef.id)), slot);
		}
		// Cross-def: an elected advsol joins the fusion being built. Not a
		// zero-E rung mid-stall: "make a basic solar" was routed onto a
		// 5,000-E advanced solar and the whole fleet fed it through a
		// three-minute stall.
		if (!(HardEStall() && (Catalog::gCostE[int(w.def.id)] <= 0.f))) {
			IUnitTask@ jt = JoinBigEnergy(unit, w.def);
			if (jt !is null)
				return jt;
		}
		// OFF THE METAL SPOTS, whatever the generator costs and wherever the
		// slot came from: the spot's footprint plus the generator's. w.pos is
		// cleared as well because the stall ladder below falls back to it.
		const float clr = (Catalog::gCostM[int(w.def.id)] > 500.f) ? 150.f : 120.f;
		w.pos = ClearOfSpots(w.pos, clr);
		if (OnMap(slot))
			slot = ClearOfSpots(slot, clr);
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
		// The dear rungs are never the stall answer below the solar bar: this
		// ladder handed a 5,000-E advanced solar to a builder whose solar was
		// at its cap, at 57 e/s, and the fleet folded onto it for three
		// minutes with the bank at 4-22.
		const bool zeroOnly = aiEconomyMgr.energy.income
				< ai.GetTunable("apex_stall_solar_e", TUNE_STALL_SOLAR_E);
		for (uint pass = 0; pass < 2; ++pass) {
		for (uint k = 0; k < gEAlt.length(); ++k) {
			const int ad = gEAlt[k];
			if ((w.def !is null) && (ad == int(w.def.id)))
				continue;
			if (((pass == 0) || zeroOnly) && (Catalog::gCostE[ad] > 0.f))
				continue;
			CCircuitDef@ adef = Catalog::Def(ad);
			if (adef is null)
				continue;
			AIFloat3 aslot = gFarmSet ? FarmSlot(ad, unit) : BigEnergySite();
			if (OnMap(aslot))
				aslot = ClearOfSpots(aslot, 120.f);
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
		AIFloat3 slot = gFarmSet ? FarmSlot(int(w.def.id), unit) : w.pos;
		// The same deadlock the energy branch probes for: the farm slot is
		// deterministic, and a seat whose farm sits past a cliff lost every
		// advanced converter it ordered at one point (27 unreach deaths,
		// zero built, 91% of its energy thrown away).
		if ((unit !is null) && NearBlocked(slot))
			slot = ProbedSite(w.def, Catalog::Def(int(unit.circuitDef.id)), slot);
		const AIFloat3 cAt = ClearOfSpots(OnMap(slot) ? slot : w.pos, 120.f);
		IUnitTask@ cFirst = Requests::Take(unit, w.def, Task::BuildType::CONVERT,
				Task::Priority::NORMAL, cAt, cell, 0.f, crtd, par);
		// HOW MANY, NOT WHETHER -- the same law the nano burst already uses,
		// with the SURPLUS in place of the bank (apexearth, on the nanos: "the
		// single build request could expand out into 2, 5, 10, 20, whatever we
		// can afford"). The count is arithmetic, not a cap: energy we are
		// failing to convert, divided by what one of these chews, bounded by
		// the metal that pays for them. An advanced converter is 380 metal for
		// 600 e/s at 0.01724 -- 10.3 metal/s, a 37-second payback -- so the
		// bound that binds is nearly always the surplus.
		//
		// ConvCapInFlight is already subtracted, so what is ordered is not
		// asked for twice.
		if (cFirst !is null) {
			const int cvd = int(w.def.id);
			const float capD = Catalog::gConvCapacity[cvd];
			const float perM = Catalog::gCostM[cvd];
			if ((capD > 1.f) && (perM > 1.f)) {
				const float spare = ((gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma) - ConvCapInFlight();
				// WHILE THE BANK IS PINNED, METAL IS THE ONLY REAL BOUND.
				// The surplus EMA is built from `pull`, which is demand and
				// understates the waste by an order of magnitude (see
				// EnergyPinned) -- reading it here capped the burst at one.
				// The energy a converter eats is energy we are demonstrably
				// throwing away, so what it actually costs is 380 metal for
				// 10.3 metal/s, and the bank is what says how many of those
				// we can start. It self-limits twice over: the bank empties,
				// and the pin breaks once enough capacity stands.
				int wantC = EnergyPinned() ? ETA_INF_N : int(spare / capD);
				// AFFORDABLE AGAINST INCOME, NOT THE INSTANTANEOUS BANK.
				//
				// This read metal.current / price, and we now deliberately run
				// a near-empty bank ("relying on storage is lazy -- make sure
				// spend the metal"), so afford was 0 or 1 and the burst never
				// fired once: measured, `conv batch` 0 times in a whole game
				// while armmmkr held a mean of 1.8 in flight against a cap of
				// 24, and 46-58% of all energy produced was thrown away.
				//
				// A converter is 380 metal returning 10.3 metal/s -- a
				// 37-second payback -- so the honest question is not "is it in
				// the bank" but "can this economy carry it", which is the same
				// seconds-of-economic-power test the defence dominance rule
				// uses. apexearth, on exactly this shape: "once we can afford
				// it we need to build them."
				const float affordM = EcoPowerM()
						* ai.GetTunable("apex_conv_afford_s", TUNE_CONV_AFFORD_S);
				const int afford = int(affordM / perM);
				if (wantC > afford)
					wantC = afford;
				// A WORK SLICE, NOT A CONVERTER CAP. Each Take is a ledger
				// collision scan and the lattice walk has its own budget;
				// executions recur many times a minute and ConvCapInFlight
				// subtracts what stands, so the surplus still converts to the
				// same fleet within seconds -- the work just stops landing
				// inside one sim frame.
				if (wantC > 16)
					wantC = 16;   // two rows of eight (his 2x8 block)
				if (wantC > 1) {
					const double _tC = Perf::T0();
					array<AIFloat3> packC;
					PackSlots(cvd, cAt, -1, wantC - 1, packC);
					int cOpen = 0;
					for (uint ci = 0; ci < packC.length(); ++ci) {
						bool mkc = false;
						Requests::Take(null, w.def, Task::BuildType::CONVERT,
								Task::Priority::NORMAL, packC[ci], cell, 0.f,
								mkc, true);
						if (mkc)
							++cOpen;
					}
					Perf::Add("xw.convbatch", _tC);
					if (cOpen > 0)
						AiLog("apex: conv batch t=" + ai.teamId
							+ " +" + cOpen
							+ " surplus=" + int(gESurplusEma)
							+ " inflight=" + int(ConvCapInFlight())
							+ " cap=" + int(capD));
				}
			}
		}
		return cFirst;
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
