namespace Builder {

// KILL PHASE (docs/20-brain-overhaul.md): the hooks keep only senses and the
// Requests plumbing's bookkeeping. All spend-side ledgers died with their
// rules.

// Per-unit task history ring, read by the death log in main.as.
array<int>    gHistId;
array<string> gHistBuf;

int HistSlot(int id)
{
	for (uint i = 0; i < gHistId.length(); ++i) {
		if (gHistId[i] == id)
			return int(i);
	}
	return -1;
}

string TakeHistFor(int id)
{
	const int s = HistSlot(id);
	if (s < 0)
		return "";
	const string hist = gHistBuf[s];
	gHistId.removeAt(uint(s));
	gHistBuf.removeAt(uint(s));
	return hist;
}

void AiTaskAdded(IUnitTask@ task)
{
	const double _t = Perf::T0();
	TaskAddedInner(task);
	Perf::Add("hk.taskadd.bld", _t);
}

void TaskAddedInner(IUnitTask@ task)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	Requests::Register(task);
	Market::ComTaskAdded(task);
}

// WHY A TASK DIES. Requests counts what is CREATED; nothing counted what left,
// or whether it left finished. A player on 26 metal/second opened 1,967
// requests, started 12 wind turbines and banked the rest -- with no site-fail
// and no exec-refused, so the task was built, sited, and then removed unfinished
// with nothing recording it.
array<int> gGoneOk(0);
array<int> gGoneBad(0);
array<int> gGoneBadNoPos(0);
int gNextGoneLog = 0;
int gAbortLog = 0;

// INSTANT-ABORT BACKOFF. A def whose task dies unfinished several times in
// quick succession is stuck in an elect-order-abort loop: elected, ordered and
// killed by the DLL's site check the same frame, burning the con's walk each
// round. Three fast deaths hold that def's proposals for two minutes; a
// finished build clears the streak.
array<int> gAbortStreak;
array<int> gAbortAt;

// A plant is never held: its refused ground is already marked per def
// (NoteBuildBlocked), and two minutes without a T2 lab ask cost more than
// the doomed-converter loop this guards against (three fast aborts at 8.0
// min held the lab while its site was re-probed, his Isthmus game).
bool AbortBackoff(int d)
{
	if ((d <= 0) || (d >= int(gAbortStreak.length())))
		return false;
	if (!Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0))
		return false;
	return (gAbortStreak[d] >= 3)
		&& (ai.frame < gAbortAt[d] + 120 * SECOND);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	const double _t = Perf::T0();
	TaskRemovedInner(task, done);
	Perf::Add("hk.taskdel.bld", _t);
}

void TaskRemovedInner(IUnitTask@ task, bool done)
{
	if ((gComm !is null) && ComIdleOn()) {
		array<CCircuitUnit@>@ cu = task.GetUnits();
		if (cu !is null)
			for (uint i = 0; i < cu.length(); ++i)
				if (cu[i] is gComm) {
					ComIdleBegin();
					break;
				}
	}
	if (task.GetType() != Task::Type::BUILDER)
		return;
	if (gGoneOk.length() == 0) {
		gGoneOk.resize(Catalog::gDefCount + 1);
		gGoneBad.resize(Catalog::gDefCount + 1);
		gGoneBadNoPos.resize(Catalog::gDefCount + 1);
		gAbortStreak.resize(Catalog::gDefCount + 1);
		gAbortAt.resize(Catalog::gDefCount + 1);
	}
	const int d = (task.buildDef !is null) ? int(task.buildDef.id) : 0;
	if ((d >= 0) && (d < int(gGoneOk.length()))) {
		if (done) {
			++gGoneOk[d];
			if (d > 0)
				gAbortStreak[d] = 0;
		} else {
			// d==0 is a builder task with NO buildDef (reclaim, repair):
			// those removals are normal churn, and Catalog::Def(0) is null
			// -- counting them crashed the script here on every third
			// reclaim-task removal (his live game, 2026-08-28 19:0x:
			// "Exception: Null pointer access ... TaskRemovedInner").
			if (d > 0) {
				gAbortStreak[d] = (ai.frame < gAbortAt[d] + 30 * SECOND)
						? (gAbortStreak[d] + 1) : 1;
				gAbortAt[d] = ai.frame;
				if ((gAbortStreak[d] == 3) && (gAbortLog < 30))
					AiLog("apex: abort-backoff t=" + ai.teamId + " "
						+ Catalog::Def(d).GetName()
						+ " -- 3 fast aborts, held 120s");
			}
			++gGoneBad[d];
			if (!OnMap(task.GetBuildPos()))
				++gGoneBadNoPos[d];
			// DID ANYONE ACTUALLY GO? apexearth: "can you tell me that team five
			// really did try to make one... I just see team five sitting there
			// doing nothing at all". A valid buildPos only proves Execute ran once.
			// How far the site was, and whether a builder was still on the task
			// when it died, is what says whether anybody set out.
			array<CCircuitUnit@>@ ws = task.GetUnits();
			const int nw = (ws is null) ? 0 : int(ws.length());
			float dHome = -1.f, dMan = -1.f;
			if (OnMap(task.GetBuildPos())) {
				if (Builder::gHomeSet)
					dHome = Builder::gHomePos.distance2D(task.GetBuildPos());
				if ((nw > 0) && (ws[0] !is null))
					dMan = ws[0].GetPos(ai.frame).distance2D(task.GetBuildPos());
			}
			// d==0 (no buildDef: reclaim/repair) has no Def to name --
			// Catalog::Def(0) is null and .GetName() on it throws.
			if ((d > 0) && (gAbortLog < 30)) {
				++gAbortLog;
				// DID THE REASON FOR THE BUILD EVAPORATE WHILE WE WALKED TO IT?
				// apexearth 2026-09-07: "I wonder if we need the turret because
				// the ground is unsafe, but then because a con comes over with
				// an escort, the escort adds safety and then defense no longer
				// perceived as necessary?" CoverWith counts posted units as
				// cover exactly like turrets, so a guard arriving near the site
				// raises cover, closes the shortfall, and zeroes the very want
				// that sent the builder. Printing the unit share of cover AT
				// THE ABORTED SITE is what separates that from an ordinary
				// re-election.
				float abCov = -1.f, abUnit = -1.f;
				if (OnMap(task.GetBuildPos())) {
					abCov = Market::CoverAt(task.GetBuildPos());
					abUnit = Military::UnitCoverAt(task.GetBuildPos());
				}
				AiLog("apex: abort t=" + ai.teamId + " "
					+ Catalog::Def(d).GetName() + " workers=" + nw
					+ " siteFromHome=" + int(dHome)
					+ " builderToSite=" + int(dMan)
					+ " cover=" + formatFloat(abCov, "", 0, 0)
					+ " unitCover=" + formatFloat(abUnit, "", 0, 0));
			}

		}
	}
	if (ai.frame >= gNextGoneLog) {
		gNextGoneLog = ai.frame + 60 * SECOND;
		string ln = "apex: task-gone t=" + ai.teamId + " |";
		for (uint k = 1; k < gGoneBad.length(); ++k) {
			if ((gGoneBad[k] + gGoneOk[k]) < 10)
				continue;
			ln += " " + Catalog::Def(int(k)).GetName()
				+ " done=" + gGoneOk[k] + " abort=" + gGoneBad[k]
				+ "(nopos " + gGoneBadNoPos[k] + ")";
		}
		AiLog(ln);
	}
	// The frame this task raised is still standing and is about to have no
	// record anywhere: hand it to the ledger before the task goes.
	if (!done)
		Requests::PendNote(task);
	Market::ComTaskRemoved(task, done);
	Requests::Forget(task);
}

// Fusion ledger: a sense read by requests dedup, LateGame and the role
// objective. Names, not a cost band.
array<CCircuitUnit@> gFusions;

bool IsFusion(const CCircuitDef@ cdef)
{
	if (cdef is null)
		return false;
	const string n = cdef.GetName();
	return (n == "armfus") || (n == "corfus") || (n == "legfus")
		|| (n == "armafus") || (n == "corafus") || (n == "legafus");
}

// The commander handle and home position: the anchor every front-fraction and
// rear-of-base read derives from (sitesafety.as, military).
// CCircuitUnit is registered NOCOUNT -- a stored handle is not nulled when the
// engine destroys the unit, so removal MUST clear it.
CCircuitUnit@ gComm = null;
AIFloat3 gHomePos;
bool gHomeSet = false;

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	const double _t = Perf::T0();
	UnitAddedInner(unit, usage);
	Perf::Add("hk.unitadd.bld", _t);
}

void UnitAddedInner(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
	if (IsFusion(unit.circuitDef))
		gFusions.insertLast(unit);
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask) && (gComm is null)) {
		@gComm = unit;
		gHomePos = unit.GetPos(ai.frame);
		gHomeSet = true;
	}
	// A constructor sealed into a pocket is the same failure as a walled-in
	// squad. See military/unblock.as.
	if ((usage == Unit::UseAs::BUILDER) || (usage == Unit::UseAs::REZZER))
		Military::NotePenned(unit);
	if (usage == Unit::UseAs::REZZER) {
		const int rid = unit.circuitDef.id;
		if ((rid >= 0) && (uint(rid) < gRezzerDefs.length()) && !gRezzerDefs[rid]) {
			gRezzerDefs[rid] = true;
			gRezzerIds.insertLast(rid);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	const double _t = Perf::T0();
	UnitRemovedInner(unit, usage);
	Perf::Add("hk.unitdel.bld", _t);
}

void UnitRemovedInner(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if ((usage == Unit::UseAs::BUILDER) || (usage == Unit::UseAs::REZZER))
		Military::ForgetPenned(unit.id);
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i] is unit) {
			gFusions.removeAt(i);
			break;
		}
	}
	if (gComm is unit) {
		AiLog(Factory::T() + "apex: COMMANDER LOST frame=" + ai.frame
			+ " hp=" + formatFloat(unit.GetHealthPercent() * 100.f, "", 0, 0));
		Market::ComDeathNote();
		@gComm = null;
	}
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

}  // namespace Builder
