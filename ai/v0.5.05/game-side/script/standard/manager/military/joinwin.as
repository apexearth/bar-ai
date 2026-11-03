namespace Military {

// THE JOIN WINDOW (docs/doctrine.md): a squad takes members while it forms and none from the moment it
// launches. A launch admits its roster -- the units claimed for it, re-electing onto it -- for JW_ADMIT and
// shuts the window (C++ IFighterTask::JoinCommit; under apex_gather every join path refuses). Every election
// that hands a unit to a task that already exists goes through JwJoinable (tools/joinwin_check.py).
const int JW_ADMIT = 10 * SECOND;

void JwCommit(IUnitTask@ t, const array<int>@ roster, int also = -1)
{
	if ((t is null) || t.IsDead())
		return;
	if (roster !is null) {
		for (uint i = 0; i < roster.length(); ++i)
			t.JoinAdmit(roster[i]);
	}
	if (also >= 0)
		t.JoinAdmit(also);
	t.JoinCommit(JW_ADMIT);
}

void JwCommitIds(IUnitTask@ t, const array<Id>@ roster, int also = -1)
{
	array<int> r;
	if (roster !is null) {
		for (uint i = 0; i < roster.length(); ++i)
			r.insertLast(int(roster[i]));
	}
	JwCommit(t, r, also);
}

// a launch without a task (a flight, an intercept, a gift of planes): its refusals count in joinwin-stat
const int JW_EV_REFUSED = 2;   // CMilitaryManager::JW_REFUSED
void JwRefused(int fightType, int n)
{
	if (n > 0)
		aiMilitaryMgr.NoteJoinWin(fightType, JW_EV_REFUSED, n);
}

IUnitTask@ JwJoinable(IUnitTask@ t, CCircuitUnit@ u)
{
	if ((t is null) || t.IsDead() || (u is null))
		return t;
	return t.JoinOpen(u) ? t : null;
}

// a unit out on a launched squad: a guard or escort sent to it would be joining that squad
bool JwLaunched(CCircuitUnit@ u)
{
	if ((u is null) || !GthOn())
		return false;
	IUnitTask@ t = u.task;
	return (t !is null) && !t.IsDead() && t.IsJoinCommitted();
}

// every member within r of home: a launched squad back home forms again
bool JwHome(IUnitTask@ t, float r)
{
	if ((t is null) || t.IsDead() || !Builder::gHomeSet)
		return false;
	array<CCircuitUnit@>@ on = t.GetUnits();
	if (on is null)
		return false;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] !is null) && (on[i].GetPos(ai.frame).distance2D(Builder::gHomePos) > r))
			return false;
	}
	return true;
}

}  // namespace Military
