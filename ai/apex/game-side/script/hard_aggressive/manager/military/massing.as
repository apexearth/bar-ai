namespace Military {

// HOLDING MUST BE BOUNDED IN TIME.
//
// quota.attack is a MINIMUM attacker count before the engine will form an
// attack, and MassWant() pins it at MASS_CAP whenever the enemy out-values us
// by MASS_HOLD_RATIO -- a feedback trap where falling behind economically
// raises the bar to attack at all, so ground is never contested and the
// economy falls further behind. The hold itself stays (a trickle just dies for
// nothing) but gets a deadline: once pinned at the cap this long, fall back to
// MASS_FLOOR so something goes out and the ratio can change.
int gHoldSince = -1;

// EnemyArmyCost() plus a discounted share of enemy static defence, for sizing
// the group that commits to an attack. See MassWant() below for why this is
// not folded into EnemyArmyCost() itself.
float EnemyMassingThreat()
{
	return EnemyArmyCost() + STATIC_DEFENSE_WEIGHT * aiEnemyMgr.GetEnemyCost(RT::STATIC);
}

// The size a group commits at, from the armies on the field.
//
// CDefendTask is created with maxPower = minAttackers and stops accepting units
// once it reaches it, then promotes to an attack and leaves. So this number IS
// the size each group leaves at -- not a threshold it grows past.
float MassWant()
{
	// Sized against what the group can actually kill, not against the enemy's
	// whole army: comparing to their total army answers "can we beat all of
	// them", but the objective is usually undefended economy, which only needs
	// enough to kill the extractor. Falling behind on army would otherwise raise
	// this demand and we never go, losing more ground.
	//
	// Safety is not given up, it moves to target selection: the attack task
	// refuses a target whose local defence outweighs the group (localInfl and
	// the strength test in CAttackTask::FindTarget), and target selection
	// prefers UNDEFENDED economy outright (FREE_ECO_PRIORITY). A floor-sized
	// group can go out and pick something it can actually kill.
	//
	// The floor is tunable and calibrated by LogUnitPower() below: quota.attack
	// is a POWER sum (CFighterTask: attackPower += cdef->GetPower()), not a
	// unit count or metal value, so it cannot be derived directly from a metal
	// figure.
	if (ai.GetTunable("apex_mass_vs_army", 0.f) <= 0.f)
		return MassFloor();

	const float ours = TeamArmyCost();
	const float theirs = EnemyMassingThreat();
	if (ours <= 1.f)
		return MASS_CAP;
	const float floorNow = MassFloor();
	const float capNow = (MASS_CAP > floorNow) ? MASS_CAP : floorNow;
	const float ratio = theirs / ours;
	if (ratio <= ATTACK_EDGE)
		return floorNow;                      // ahead: move, but as a group
	if (ratio >= MASS_HOLD_RATIO)
		return capNow;                        // outmatched: hold
	const float t = (ratio - ATTACK_EDGE) / (MASS_HOLD_RATIO - ATTACK_EDGE);
	return floorNow + t * (capNow - floorNow);
}

// The floor scales with our own army: a fixed 12-power squad is a real group
// over a 2k-metal army and a suicide trickle over 100k. Sized as a share of
// standing army value, converted at Grunt-class power-per-metal (~0.017,
// LogUnitPower); floored at the old constant so the opening is unchanged.
// apexearth 2026-08-15: the squad minimum scales with economy/army, not flat.
float gQuotaConfig = -1.f;   // behaviour.json's quota.attack, read once at start

float MassFloor()
{
	if (gQuotaConfig < 0.f)
		gQuotaConfig = aiMilitaryMgr.quota.attack;
	float base = ai.GetTunable("apex_mass_floor", MASS_FLOOR);
	if (base < gQuotaConfig)
		base = gQuotaConfig;   // never undercut the config's own opening minimum
	const float scaled = TeamArmyCost()
			* ai.GetTunable("apex_mass_per_army", 0.0017f);
	return (scaled > base) ? scaled : base;
}

void UpdateMassing()
{
	LogUnitPower();
	// The killing blow owns the quota once it is on: massing is what was holding
	// the win up, so re-raising the minimum here would undo it every tick.
	if (gKilling)
		return;
	if (gTurtle)
		return;   // an active hold is stricter; do not loosen it
	if (ai.teamId == Factory::RushLeadTeamId() && !Factory::gHaveT2)
		return;   // the rusher has its own quota while teching

	// TEAM against team: aiMilitaryMgr.armyCost is THIS player's army while
	// EnemyArmyCost() sums every enemy, so comparing them directly on a 4v4 is
	// one player against four and reads far too pessimistic. TeamArmyCost()
	// sums the ally side over TV_ARMY, the same figure the killing blow uses.
	const float ours = TeamArmyCost();
	const float theirs = EnemyMassingThreat();
	float want = MassWant();

	// Bound the hold. MassWant returns MASS_CAP only in the outmatched case, so
	// that is the signal we are holding rather than committing.
	const float holdSecs = ai.GetTunable("apex_mass_hold_secs", 120.f);
	// Keyed on "demanding more than the floor", not on reaching the cap: the
	// interpolated want can sit just under MASS_HOLD_RATIO and never touch
	// MASS_CAP, so a deadline keyed on the cap would never fire.
	const float floorNow = MassFloor();
	if (want > floorNow + 1.f) {
		if (gHoldSince < 0)
			gHoldSince = ai.frame;
		if ((holdSecs > 0.f) && (ai.frame - gHoldSince > int(holdSecs) * SECOND)) {
			want = floorNow;
			gHoldSince = ai.frame;   // restart, so we alternate hold and commit
			AiLog(Factory::T() + "apex: mass hold expired, committing at floor");
		}
	} else {
		gHoldSince = -1;
	}

	if (ai.frame >= gNextMassLog) {
		gNextMassLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: mass want=" + formatFloat(want, "", 0, 0)
			+ " floor=" + formatFloat(floorNow, "", 0, 0)
			+ " army=" + formatFloat(ours, "", 0, 0)
			+ " enemyArmy=" + formatFloat(theirs, "", 0, 0)
			+ " ratio=" + formatFloat((ours > 0.f) ? theirs / ours : 0.f, "", 0, 2));
		// HOW BIG "HOME GROUND" IS: CAttackTask's isHome waives the odds check
		// wherever net influence >= INFL_SAFE (2.0). Walk the home->enemy axis
		// and log where that isoline actually ends, against the full distance,
		// so the exemption's reach is a measured number and not a guess.
		if (Builder::gHomeSet) {
			const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
			const float total = Builder::gHomePos.distance2D(foe);
			if ((total > 1.f) && OnMap(foe)) {
				float safeDist = 0.f;
				for (float d = 200.f; d < total; d += 200.f) {
					AIFloat3 p = Builder::gHomePos + (foe - Builder::gHomePos) * (d / total);
					if (!OnMap(p) || (ai.GetAllyInflAt(p) - ai.GetEnemyInflAt(p) < 2.f))
						break;
					safeDist = d;
				}
				AiLog(Factory::T() + "apex: home-edge safe=" + int(safeDist)
					+ " of " + int(total) + " ("
					+ formatFloat(100.f * safeDist / total, "", 0, 0) + "%)");
			}
		}
	}
	// Tracks the want BOTH ways: with an army-scaled floor, a ratchet that only
	// rises would leave the bar stuck at a dead army's size -- a side that just
	// lost 30k of army could never form another attack. gKilling/gTurtle return
	// early above, so nothing else owns the quota while this writes it.
	aiMilitaryMgr.quota.attack = want;
}

//------------------------------------------------------------------------------
// KILLING BLOW: once clearly winning, stop waiting for a bigger army.
//
// UpdateMassing walks quota.attack up to MASS_CAP and pins it there outright
// whenever the enemy out-values us. Once we are far ahead that gate is pure
// delay: we hold an army several times their size and keep waiting for a
// bigger one. So when clearly winning, drop the minimum so attacks form
// continuously and release the turtle if it is holding -- conditional on
// holding KILL_EDGE times the enemy's army value, so even a partial commitment
// outnumbers everything they can field. Lowering minAttackers globally is known
// to be catastrophic; this only lowers it once we are already dominant.
const int   KILL_FROM  = 15 * MINUTE;   // not before the T2 transition settles
const float KILL_EDGE  = 1.8f;          // OUR TEAM's army value against theirs
const float KILL_FLOOR = 20000.f;       // ignore ratios off a tiny enemy sample
const float KILL_QUOTA = 300.f;         // concentrate the push, do not disperse
bool gKilling = false;

// Our whole side's army value, pooled over the same blackboard the tech lead
// election uses. Has to be TEAM against TEAM: aiMilitaryMgr.armyCost is one
// player's army while EnemyArmyCost() sums the entire enemy side, so a direct
// comparison asks "is one of us worth more than all of them" and is
// unreachable by construction.
const string TV_ARMY = "army";

}  // namespace Military

// One-off calibration: quota.attack is a POWER SUM (CFighterTask::attackPower
// += cdef->GetPower()), not a unit count, so MASS_FLOOR cannot be set without
// knowing what a unit is worth. Logs a few representative units' power once.
bool gPowerLogged = false;
void LogUnitPower()
{
	if (gPowerLogged || (ai.frame < 30 * SECOND))
		return;
	gPowerLogged = true;
	array<string> names = {"armpw", "armrock", "armwar", "corak", "corthud", "armzeus", "armjeth",
	                       "armbanth", "corkorg", "corshiva", "armmanni"};
	string msg = "apex: unit power --";
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if (d !is null)
			msg += " " + names[i] + "=" + formatFloat(d.power, "", 0, 1);
	}
	AiLog(msg);
}
