namespace Market {
//------------------------------------------------------------------------------
// THE COMMITMENT LEDGER. One census of every immobile structure we own or have
// committed to, whatever its stage. Every other ownership read in the market is
// a partial truth with a lying window -- gOwnCount sees only finishes,
// Def().count only placed frames (nothing during the builder's walk),
// Requests::gLive only requests that still remember themselves -- and every
// duplicate-purchase bug in this AI's history was a want priced inside one of
// those windows. Proposers ask this ledger instead.
//
// States. ORDERED: a build task exists, nothing stands (the walk window).
// FRAMED: a nanoframe stands (with or without a live task -- an orphaned frame
// stays FRAMED with a null task). FINISHED: the structure works.
//
// Writers are the events (TaskAdded/TaskRemoved/UnitFinished/UnitDestroyed).
// ComSweep is a BACKSTOP for missed events, never the primary signal; it also
// promotes ORDERED->FRAMED, because no script event fires at nanoframe
// creation (verified: the C++ UnitCreated handler never crosses into script).
//
// Unit handles are NEVER stored (CCircuitUnit is NOCOUNT); ids are. The task
// handle is refcounted and safe to hold.
//------------------------------------------------------------------------------

const int CS_ORDERED  = 1;
const int CS_FRAMED   = 2;
const int CS_FINISHED = 4;
const int CS_COMING   = CS_ORDERED | CS_FRAMED;
const int CS_ANY      = CS_ORDERED | CS_FRAMED | CS_FINISHED;

array<int>        gComDef;
array<int>        gComState;
array<Id>         gComId;      // -1 until framed
array<AIFloat3>   gComPos;
array<IUnitTask@> gComTask;    // null once orphaned or finished
array<int>        gComAt;      // frame of last transition

int gComDriftUnit = 0;     // unit vanished without its death event reaching us
int gComDriftTask = 0;     // task vanished without its removal reaching us
int gComDriftEngine = 0;   // ledger vs Def().count disagreement (log-only)
int gComSweepNext = 199;   // phase offset -- see AiUpdate lockstep note
int gComSummaryNext = 0;

uint ComLen() { return gComDef.length(); }

int ComFindTask(IUnitTask@ t)
{
	if (t is null)
		return -1;
	for (uint i = 0; i < gComTask.length(); ++i) {
		if (gComTask[i] is t)
			return int(i);
	}
	return -1;
}

int ComFindId(Id id)
{
	if (int(id) < 0)
		return -1;
	for (uint i = 0; i < gComId.length(); ++i) {
		if (gComId[i] == id)
			return int(i);
	}
	return -1;
}

void ComDrop(uint i)
{
	gComDef.removeAt(i);
	gComState.removeAt(i);
	gComId.removeAt(i);
	gComPos.removeAt(i);
	gComTask.removeAt(i);
	gComAt.removeAt(i);
}

// Promote a row to FRAMED on the frame unit `uid`. If another row already
// carries that id (a later request adopted an orphaned frame), the two are the
// same structure: keep the id-bearing row, hand it this row's task if it has
// none, and drop this row. Returns the surviving row index.
int ComBindFrame(uint i, Id uid, const AIFloat3 &in where)
{
	for (uint j = 0; j < gComId.length(); ++j) {
		if ((j == i) || (gComId[j] != uid))
			continue;
		if ((gComTask[j] is null) && (gComTask[i] !is null))
			@gComTask[j] = gComTask[i];
		ComDrop(i);
		return (j > i) ? int(j - 1) : int(j);
	}
	gComId[i] = uid;
	gComPos[i] = where;
	if (gComState[i] == CS_ORDERED) {
		gComState[i] = CS_FRAMED;
		gComAt[i] = ai.frame;
	}
	return int(i);
}

void ComTaskAdded(IUnitTask@ task)
{
	if ((task is null) || (task.buildDef is null))
		return;
	const int d = int(task.buildDef.id);
	if (Catalog::gMobile[d])
		return;
	if (ComFindTask(task) >= 0)
		return;
	gComDef.insertLast(d);
	gComState.insertLast(CS_ORDERED);
	gComId.insertLast(Id(-1));
	gComPos.insertLast(task.GetBuildPos());
	gComTask.insertLast(task);
	gComAt.insertLast(ai.frame);
}

void ComTaskRemoved(IUnitTask@ task, bool done)
{
	int i = ComFindTask(task);
	if (i < 0)
		return;
	// A removal that follows the frame's own death still carries the target
	// handle; GetTeamUnit is the aliveness test (a destroyed unit is already
	// unregistered by the time this event runs).
	CCircuitUnit@ tgt = task.target;   // transient read only -- NOCOUNT
	if ((tgt !is null) && (tgt.circuitDef !is null)
		&& (ai.GetTeamUnit(tgt.id) !is null))
	{
		i = ComBindFrame(uint(i), tgt.id, tgt.GetPos(ai.frame));
	}
	@gComTask[i] = null;
	// done: the finish event sets/has set FINISHED by id. !done with no frame:
	// nothing stands, the commitment is gone.
	if (!done && (gComState[i] != CS_FINISHED) && (int(gComId[i]) < 0))
		ComDrop(uint(i));
}

void ComUnitFinished(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null))
		return;
	const int d = int(unit.circuitDef.id);
	if (Catalog::gMobile[d])
		return;
	const AIFloat3 at = unit.GetPos(ai.frame);
	int i = ComFindId(unit.id);
	if (i < 0) {
		// The finish can land before the task learned its target: match the
		// order by def and ground (build positions are snapped, the pad is
		// geometric tolerance, not policy).
		for (uint j = 0; j < gComDef.length(); ++j) {
			if ((gComState[j] == CS_ORDERED) && (gComDef[j] == d)
				&& (at.distance2D(gComPos[j]) < 64.f))
			{
				i = int(j);
				break;
			}
		}
	}
	if (i < 0) {
		// Never task-tracked: resurrected, or otherwise engine-made.
		gComDef.insertLast(d);
		gComState.insertLast(CS_FINISHED);
		gComId.insertLast(unit.id);
		gComPos.insertLast(at);
		IUnitTask@ none = null;
		gComTask.insertLast(none);
		gComAt.insertLast(ai.frame);
		return;
	}
	i = ComBindFrame(uint(i), unit.id, at);
	gComState[i] = CS_FINISHED;
	@gComTask[i] = null;
	gComAt[i] = ai.frame;
}

void ComUnitDead(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int i = ComFindId(unit.id);
	if (i >= 0)
		ComDrop(uint(i));
}

int ComCountOf(int defId, int mask)
{
	int n = 0;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if ((gComDef[i] == defId) && ((gComState[i] & mask) != 0))
			++n;
	}
	return n;
}

// Unfinished rows count only with hands on them: an unmanned order or frame
// is a held placeholder (the async-sim-orders law) whose manning path IS the
// def's own want -- counting it as satisfied strangles that path (measured
// seed 8: both opening factories ordered, zeroed as their own copies, and
// unreachable for 11 minutes).
int ComCountManned(int defId, int mask)
{
	int n = 0;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if ((gComDef[i] != defId) || ((gComState[i] & mask) == 0))
			continue;
		if (gComState[i] != CS_FINISHED) {
			if ((gComTask[i] is null) || (Requests::Workers(gComTask[i]) == 0))
				continue;
		}
		++n;
	}
	return n;
}

bool ComAny(int defId, int mask)
{
	for (uint i = 0; i < gComDef.length(); ++i) {
		if ((gComDef[i] == defId) && ((gComState[i] & mask) != 0))
			return true;
	}
	return false;
}

int ComNearest(int defId, const AIFloat3 &in pos, float reach, int mask)
{
	int best = -1;
	float bestD = reach;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if ((gComDef[i] != defId) || ((gComState[i] & mask) == 0))
			continue;
		const float dd = pos.distance2D(gComPos[i]);
		if (dd < bestD) {
			bestD = dd;
			best = int(i);
		}
	}
	return best;
}

// Any lathe in the ledger, ordered or standing, within `reach` of `pos`.
bool ComLatheNear(const AIFloat3& in pos, float reach)
{
	for (uint i = 0; i < gComDef.length(); ++i) {
		if (IsLatheDef(gComDef[i]) && (pos.distance2D(gComPos[i]) < reach))
			return true;
	}
	return false;
}

float ComLeftM(uint i)
{
	if (i >= gComDef.length())
		return 0.f;
	const float cost = Catalog::gCostM[gComDef[i]];
	if (gComState[i] == CS_FINISHED)
		return 0.f;
	if (gComTask[i] !is null)
		return cost * (1.f - Requests::Progress(gComTask[i]));
	if (int(gComId[i]) >= 0) {
		CCircuitUnit@ u = ai.GetTeamUnit(gComId[i]);
		if (u !is null)
			return cost * (1.f - u.GetHealthPercent());
	}
	return cost;
}

float ComProgress(uint i)
{
	if (i >= gComDef.length())
		return 0.f;
	if (gComState[i] == CS_FINISHED)
		return 1.f;
	if (gComTask[i] !is null)
		return Requests::Progress(gComTask[i]);
	if (int(gComId[i]) >= 0) {
		CCircuitUnit@ u = ai.GetTeamUnit(gComId[i]);
		if (u !is null) {
			const float h = u.GetHealthPercent();
			return (h < 0.f) ? 0.f : ((h > 1.f) ? 1.f : h);
		}
	}
	return 0.f;
}

// EVERY BIG REACTOR THE LEDGER SAYS IS RISING -- and how many of them could
// still take another pair of hands. The founding gate used to ask gLive, which
// holds TASKS: a frame whose request died is invisible there, and so were the
// ones a nano was quietly finishing. Both are sites, and a gate that cannot see
// them founds another beside them (measured 2026-08-30: peak 7 advanced solars
// at once with the gLive-based test in place). The ledger is the register that
// survives the task, so the gate asks it instead.
// Cached per frame: the founding gate asks this on every big-energy request
// and the scan walks the whole ledger. Invalidated by hand whenever a
// big-energy request is registered or forgotten, so a second ask in the SAME
// frame cannot be answered from a snapshot taken before the first one landed.
int gBigEFrame = -1;
uint gBigEN = 0;
uint gBigERoom = 0;

void ComBigEInvalidate()
{
	gBigEFrame = -1;
}

// The best energy OUTPUT among expensive-energy buildings currently rising.
// Lives here rather than in Requests because gComDef is a global and market.as
// is included after builder.as.
float ComBigEnergyBestMakeE()
{
	float best = 0.f;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		const int d = gComDef[i];
		if (!Catalog::ValidId(d))
			continue;
		if (!Requests::IsBigEnergy(ai.GetCircuitDef(d)))
			continue;
		if (Catalog::gMakeE[d] > best)
			best = Catalog::gMakeE[d];
	}
	return best;
}

uint ComBigEnergyRising(uint &out room)
{
	if (gBigEFrame == ai.frame) {
		room = gBigERoom;
		return gBigEN;
	}
	room = 0;
	uint n = 0;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		const int d = gComDef[i];
		if (!Catalog::ValidId(d))
			continue;
		CCircuitDef@ def = ai.GetCircuitDef(d);
		if (!Requests::IsBigEnergy(def))
			continue;
		++n;
		IUnitTask@ t = gComTask[i];
		const uint busy = ((t is null) || t.IsDead()) ? 0 : Requests::Workers(t);
		if (busy < Requests::SiteWorkerCap(def))
			++room;
	}
	gBigEFrame = ai.frame;
	gBigEN = n;
	gBigERoom = room;
	return n;
}

// The orphan register: a frame whose request died is FRAMED with no task.
bool ComIsOrphan(uint i)
{
	return (gComState[i] == CS_FRAMED) && (gComTask[i] is null);
}

uint ComOrphanCount(int defId)
{
	uint n = 0;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if ((gComDef[i] == defId) && ComIsOrphan(i))
			++n;
	}
	return n;
}

// The orphaned frame of `defId` nearest `from` (reach < 0 = anywhere),
// resolved to the live unit; a row whose unit is gone is ComSweep's business.
CCircuitUnit@ ComOrphanUnit(int defId, const AIFloat3 &in from, float reach)
{
	CCircuitUnit@ best = null;
	float bestD = (reach < 0.f) ? 1.0e9f : reach;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if ((gComDef[i] != defId) || !ComIsOrphan(i))
			continue;
		const float dd = OnMap(from) ? from.distance2D(gComPos[i]) : 0.f;
		if (dd > bestD)
			continue;
		CCircuitUnit@ u = ai.GetTeamUnit(gComId[i]);
		if (u is null)
			continue;
		@best = u;
		bestD = dd;
	}
	return best;
}

// Shadow reads: a consumer computes its old answer and the ledger's answer,
// returns the old one, and this records the disagreement. A flip whose shadow
// stayed clean is a proven no-op; one that didn't is a measured change, with
// its data in hand before it ships.
array<string> gShadowWho;
array<int> gShadowNext;
array<int> gShadowMiss;
void ComShadowNote(const string &in who, int oldV, int newV)
{
	if (oldV == newV)
		return;
	int s = -1;
	for (uint i = 0; i < gShadowWho.length(); ++i) {
		if (gShadowWho[i] == who) {
			s = int(i);
			break;
		}
	}
	if (s < 0) {
		gShadowWho.insertLast(who);
		gShadowNext.insertLast(0);
		gShadowMiss.insertLast(0);
		s = int(gShadowWho.length()) - 1;
	}
	++gShadowMiss[s];
	if (ai.frame < gShadowNext[s])
		return;
	gShadowNext[s] = ai.frame + 10 * SECOND;
	AiLog("apex: ledger shadow " + who + " old=" + oldV + " new=" + newV
		+ " misses=" + gShadowMiss[s]);
}

void ComDriftLog(uint i, const string &in why)
{
	CCircuitDef@ cd = Catalog::Def(gComDef[i]);
	AiLog("apex: ledger drift t=" + ai.teamId + " "
		+ ((cd is null) ? ("def" + gComDef[i]) : cd.GetName())
		+ " state=" + gComState[i] + " id=" + gComId[i] + " why=" + why);
}

void ComSweep()
{
	if (ai.frame < gComSweepNext)
		return;
	gComSweepNext = ai.frame + 5 * SECOND;
	for (int i = int(gComDef.length()) - 1; i >= 0; --i) {
		const uint ui = uint(i);
		if (gComState[ui] == CS_ORDERED) {
			IUnitTask@ t = gComTask[ui];
			if ((t is null) || t.IsDead()) {
				// Missed removal. A standing frame would have been bound by
				// ComTaskRemoved; with no id here, nothing stands.
				ComDriftLog(ui, "task-gone");
				++gComDriftTask;
				ComDrop(ui);
				continue;
			}
			CCircuitUnit@ tgt = t.target;
			if ((tgt !is null) && (tgt.circuitDef !is null))
				ComBindFrame(ui, tgt.id, tgt.GetPos(ai.frame));
			continue;
		}
		CCircuitUnit@ u = ai.GetTeamUnit(gComId[ui]);
		if ((u is null) || (u.circuitDef is null)) {
			ComDriftLog(ui, "unit-gone");
			++gComDriftUnit;
			ComDrop(ui);
		}
	}
	// Engine cross-check, log-only: Def().count legitimately includes gifts
	// and captures the ledger never saw, so a mismatch is a reading, not a
	// correction.
	{
		array<int> defs;
		array<int> counts;
		for (uint i = 0; i < gComDef.length(); ++i) {
			if ((gComState[i] & (CS_FRAMED | CS_FINISHED)) == 0)
				continue;
			int at = -1;
			for (uint j = 0; j < defs.length(); ++j) {
				if (defs[j] == gComDef[i]) {
					at = int(j);
					break;
				}
			}
			if (at < 0) {
				defs.insertLast(gComDef[i]);
				counts.insertLast(0);
				at = int(defs.length()) - 1;
			}
			++counts[at];
		}
		for (uint j = 0; j < defs.length(); ++j) {
			CCircuitDef@ cd = Catalog::Def(defs[j]);
			if (cd is null)
				continue;
			// A ledger short of the engine WITH an order outstanding is the
			// normal promotion-latency window (frame placed, sweep not yet
			// run), not drift.
			if (counts[j] < cd.count) {
				bool ordered = false;
				for (uint k = 0; k < gComDef.length(); ++k) {
					if ((gComDef[k] == defs[j])
						&& (gComState[k] == CS_ORDERED))
					{
						ordered = true;
						break;
					}
				}
				if (ordered)
					continue;
			}
			if (cd.count != counts[j]) {
				++gComDriftEngine;
				if (ai.frame >= gComSummaryNext) {
					AiLog("apex: ledger enginediff " + cd.GetName()
						+ " ledger=" + counts[j] + " engine=" + cd.count);
				}
			}
		}
	}
	if (ai.frame >= gComSummaryNext) {
		gComSummaryNext = ai.frame + 60 * SECOND;
		int ord = 0, frm = 0, fin = 0;
		for (uint i = 0; i < gComState.length(); ++i) {
			if (gComState[i] == CS_ORDERED) ++ord;
			else if (gComState[i] == CS_FRAMED) ++frm;
			else ++fin;
		}
		int miss = 0;
		for (uint s = 0; s < gShadowMiss.length(); ++s)
			miss += gShadowMiss[s];
		AiLog("apex: ledger t=" + ai.teamId + " rows=" + gComDef.length()
			+ " ord=" + ord + " frm=" + frm + " fin=" + fin
			+ " drift=" + (gComDriftUnit + gComDriftTask)
			+ " enginediff=" + gComDriftEngine + " shadow=" + miss);
	}
}


}  // namespace Market
