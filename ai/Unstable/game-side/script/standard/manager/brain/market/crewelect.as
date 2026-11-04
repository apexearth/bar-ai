namespace Market {
// ONE ELECTION PER CREW (his 10-15: "split 100 T1 air cons into ~4 groups, and do the 'what should
// we do' logic on each of them... unless its about going to a dangerous place then break off
// some"). A full election publishes its job and its ranked list; a hand of the same def and crew
// side, within what it walks while the list's prices are still served (MemoTtl), takes the job --
// or, once the job has the hands it absorbs, the next want down the list -- without running the
// market. A hot site, a role the list cannot serve, or a list used up sends the hand to its own
// election, which publishes in turn.
int gCsOn = -1;
bool CrewElectOn()
{
	if (gCsOn < 0)
		gCsOn = (ai.GetTunable("apex_crew_elect", TUNE_CREW_ELECT) > 0.f) ? 1 : 0;
	return gCsOn > 0;
}

final class CrewShare {
	int defId = -1;
	int leader = -1;
	int at = 0;
	bool field = false;
	AIFloat3 pos;
	array<Want@> list;
	array<int> taken;
	array<int> cap;   // -1 until a member asks
}
array<CrewShare@> gCs;   // oldest first
int gCsRun = 0, gCsPub = 0, gCsShared = 0;
int gCsBrkDanger = 0, gCsBrkRole = 0, gCsBrkSpent = 0;
int gNextCsLog = 0;
void CrewNoteRun() { ++gCsRun; }

// The commander, a held advanced-defence hand and an upgrade hand keep their own elections.
bool CrewHand(CCircuitUnit@ unit)
{
	const int id = int(unit.id);
	if ((id < 0) || (id >= int(gDrOf.length())) || unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if (gDrOf[id])
		return false;
	return !((gUhOn > 0) && (gUhIds.find(id) >= 0));
}

// ranked[0] is the job just executed; the rest go behind it by value, undoing this hand's role and
// hoist order but keeping its crew-side and economy filters, which its crew shares.
void CrewPublish(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	if (!CrewElectOn() || (ranked.length() == 0) || !CrewHand(unit))
		return;
	CrewShare@ s = CrewShare();
	s.defId = int(unit.circuitDef.id);
	s.leader = int(unit.id);
	s.at = ai.frame;
	s.field = CrewIsField(unit);
	s.pos = unit.GetPos(ai.frame);
	s.list.insertLast(ranked[0]);
	for (uint i = 1; i < ranked.length(); ++i) {
		Want@ w = ranked[i];
		uint at = 1;
		while ((at < s.list.length()) && (s.list[at].value >= w.value))
			++at;
		s.list.insertAt(at, w);
	}
	s.taken.resize(s.list.length());
	s.cap.resize(s.list.length());
	for (uint i = 0; i < s.list.length(); ++i) {
		s.taken[i] = 0;
		s.cap[i] = -1;
	}
	s.taken[0] = 1;
	gCs.insertLast(s);
	++gCsPub;
}

// The hands one want absorbs: a building's site crew (the join rung), else the one hand.
int CrewCap(Want@ w)
{
	if ((w.def is null) || w.def.IsMobile() || (w.kind == WK_RECLAIM) || (w.kind == WK_ASSIST))
		return 1;
	return int(Requests::SiteWorkerCap(w.def));
}

void CrewExecNote(CCircuitUnit@ unit, Want@ w, IUnitTask@ t, int leader)
{
	if (w.kind == WK_MEXUP)
		++gMuStarted;
	// Joining the leader's own site changes no count that priced the kind.
	const bool join = (leader >= 0) && (leader < int(gIncTask.length())) && (gIncTask[leader] is t);
	if (!join)
		MemoEvictKind(w.kind, (w.kind == WK_MEX) ? w.spotId : -1);
	NoteJob(t, w);
	DefRoleExecuted(unit, w);
	if ((w.kind == WK_MEX) || ((w.kind == WK_RECLAIM) && (w.spotId == RCM_SPOT)))
		NoteClaim(unit, w);
	OpenNoteExec(false, w.kind);
	if (!unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
		ExpandFarNoteElect(w.kind);
		ErNoteExec(w.kind);
	}
	if (DecideLogOn())
		AiLog("apex: exec t=" + ai.teamId + " " + unit.circuitDef.GetName()
			+ " #" + unit.id + " " + KindName(w.kind) + ":"
			+ ((w.def is null) ? "-" : w.def.GetName())
			+ " pick=0 at=" + int(w.pos.x) + "," + int(w.pos.z) + ExecTaskAt(t, w) + " crew=#" + leader);
	const int uid = int(unit.id);
	if ((uid >= 0) && (uid < int(gIncTask.length()))) {
		@gIncTask[uid] = t;
		gIncVal[uid] = w.value / w.nnMult;
		gIncGain[uid] = w.gain;
	}
}

IUnitTask@ CrewTake(CCircuitUnit@ unit)
{
	if (!CrewElectOn() || !CrewHand(unit))
		return null;
	const int win = MemoTtl();
	while ((gCs.length() > 0) && (ai.frame - gCs[0].at > win))
		gCs.removeAt(0);
	if (gCs.length() == 0)
		return null;
	const int d = int(unit.circuitDef.id);
	const int uid = int(unit.id);
	const AIFloat3 up = unit.GetPos(ai.frame);
	// Near enough that its walk differs from the leader's by no more than the list's prices are stale.
	const float reach = Catalog::gSpeed[d] * float(win) / float(SECOND);
	const bool field = CrewIsField(unit);
	CrewShare@ s = null;
	for (int k = int(gCs.length()) - 1; (k >= 0) && (s is null); --k) {
		CrewShare@ c = gCs[uint(k)];
		if ((c.defId == d) && (c.leader != uid) && (c.field == field)
			&& (up.distance2D(c.pos) <= reach))
			@s = c;
	}
	if (s is null)
		return null;
	array<uint> order;
	const int role = ConRoleOf(unit);
	if ((role >= 0) && (CategoryOf(s.list[0].kind) != role)) {
		for (uint i = 0; i < s.list.length(); ++i)
			if (CategoryOf(s.list[i].kind) == role)
				order.insertLast(i);
		if (order.length() == 0) {
			++gCsBrkRole;
			return null;
		}
		for (uint i = 0; i < s.list.length(); ++i)
			if (CategoryOf(s.list[i].kind) != role)
				order.insertLast(i);
	} else {
		for (uint i = 0; i < s.list.length(); ++i)
			order.insertLast(i);
	}
	for (uint o = 0; o < order.length(); ++o) {
		const uint i = order[o];
		if (s.cap[i] < 0)
			s.cap[i] = CrewCap(s.list[i]);
		if (s.taken[i] >= s.cap[i])
			continue;
		Want@ w = s.list[i];
		if (!((w.kind == WK_MEX) && ExpandFarOn())
			&& Builder::SiteLiveHot(w.pos) && !Builder::EscortCovers(unit, w.pos)) {
			++gCsBrkDanger;
			return null;
		}
		IUnitTask@ t = ExecuteWant(unit, w);
		if (t is null) {
			s.taken[i] = s.cap[i];   // refused here, refused for the crew
			continue;
		}
		++s.taken[i];
		CrewExecNote(unit, w, t, s.leader);
		if (ElecPending(unit))
			ElecDrop(uid);
		++gCsShared;
		return t;
	}
	++gCsBrkSpent;
	return null;
}

void CrewElectLog()
{
	if (ai.frame < gNextCsLog)
		return;
	gNextCsLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: crew-elect-stat t=" + ai.teamId + " on=" + (CrewElectOn() ? 1 : 0)
		+ " run=" + gCsRun + " shared=" + gCsShared
		+ " breakoff=" + (gCsBrkDanger + gCsBrkRole + gCsBrkSpent)
		+ " (danger=" + gCsBrkDanger + " role=" + gCsBrkRole + " spent=" + gCsBrkSpent + ")"
		+ " pub=" + gCsPub
		+ " crew=" + formatFloat((gCsPub > 0) ? float(gCsPub + gCsShared) / float(gCsPub) : 0.f, "", 0, 2)
		+ " live=" + gCs.length());
	gCsRun = 0;
	gCsPub = 0;
	gCsShared = 0;
	gCsBrkDanger = 0;
	gCsBrkRole = 0;
	gCsBrkSpent = 0;
}

}  // namespace Market
