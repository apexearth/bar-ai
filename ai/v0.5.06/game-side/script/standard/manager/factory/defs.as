namespace Factory {

string armlab  ("armlab");
string armalab ("armalab");
string armvp   ("armvp");
string armavp  ("armavp");
string armsy   ("armsy");
string armasy  ("armasy");
string armap   ("armap");
string armaap  ("armaap");
string armshltx("armshltx");

string corlab  ("corlab");
string coralab ("coralab");
string corvp   ("corvp");
string coravp  ("coravp");
string corsy   ("corsy");
string corasy  ("corasy");
string corap   ("corap");
string coraap  ("coraap");
string corgant ("corgant");

string leglab  ("leglab");
string legalab ("legalab");
string legvp   ("legvp");
string legavp  ("legavp");
string legsy   ("legsy");
string legap   ("legap");
string legaap  ("legaap");
string leggant ("leggant");

string armshltxuw("armshltxuw");
string corgantuw ("corgantuw");

// Tier tags per def, assigned in Main::AiMain -- read by the T2/T3 latches.
enum Attr {
	T1 = 0x0001, T2 = 0x0002, T3 = 0x0004, T4 = 0x0008
}

class SUserData {
	SUserData(int a) {
		attr = a;
	}
	SUserData() {}
	int attr = 0;
}

array<SUserData> userData(ai.GetDefCount() + 1);

const uint BIG_TEAM = 6;

bool IsSmallTeam()
{
	array<Id>@ mates = ai.GetTeamIds();
	return (mates is null) || (mates.length() < BIG_TEAM);
}

// Late game is economy, not only time: any fusion standing counts.
const int LATE_GAME_FRAME = 25 * MINUTE;

bool LateGame()
{
	return (ai.frame >= LATE_GAME_FRAME) || (Builder::gFusions.length() > 0);
}

// The cheapest body THIS factory can actually make. Scout first, then raider:
// armlab answers armflea, corlab has no scout unit and falls through to corak,
// leglab answers leggob. Military::IsFodder is the gate, so a factory whose
// cheapest option is not actually cheap returns null and the caller buys the
// assault mainstay as before.
CCircuitDef@ Fodder(const CCircuitDef@ facDef)
{
	CCircuitDef@ d = aiFactoryMgr.GetRoleDef(facDef, Unit::Role::SCOUT.type);
	if (Military::IsFodder(d))
		return d;
	@d = aiFactoryMgr.GetRoleDef(facDef, Unit::Role::RAIDER.type);
	if (Military::IsFodder(d))
		return d;
	return null;
}

// A screen only defends if it stays home. Without this, a newly built screen
// fighter got a normal military task and was sent to attack alone like any
// other AA-role unit. apexearth, watching an 8v8 live: "I see us making air
// and immediately sending them into the enemy to die. Can't be using air like
// this... you build fighters, you leave them in your base to defend your
// base." Same mechanism as Air::HoldsUnit -- returning null from
// Military::AiMakeTask leaves the unit idle, and an idle unit still
// auto-fires on anything that comes into weapon range, so parking at home IS
// the defence.
//
// Skipped for the air lead: Air:: already owns the lifecycle of its own
// aircraft (held pre-strike, released at Air::Release()), and the advanced
// AA-role def can be the exact same def the assassin escort flies -- an
// unconditional hold here would trap the escort right after release.
//
// Restricted to big teams. LateGame() goes true off EITHER the 25-minute
// clock OR any fusion existing -- and this AA-role check is not scoped to
// only the freshly-recruited screen floor, it holds EVERY unit of that
// role, including ones already mid-fight. On a 25-minute-capped 4v4 with
// the phase-gated economy now pushing tech faster, a fusion before the
// cap is plausible, and this session's dominant finding is that any new
// unconditional behavior change costs the benchmark. Diagnosed entirely
// from 8v8 observation; gating it there matches earlyReaction/stalled in
// factory.as, both restricted for the same reason.
bool HoldsLateFighter(CCircuitUnit@ unit)
{
	if (IsSmallTeam() || !LateGame() || Air::IsAirLead())
		return false;
	const CCircuitDef@ cdef = unit.circuitDef;
	return (cdef !is null) && cdef.IsAbleToFly() && cdef.IsRoleAny(Unit::Role::AA.mask);
}

}  // namespace Factory
