namespace Military {

// HOLDING MUST BE BOUNDED IN TIME.
//
// quota.attack is a MINIMUM number of attackers before the engine will form an
// attack at all, and MassWant() pins it at MASS_CAP whenever the enemy army
// out-values ours by MASS_HOLD_RATIO. That is a feedback trap: behind on economy
// means behind on army, which pins the quota, which means we never contest
// ground, which loses more economy. This file's own history records the same
// thing happening -- "the ratio never fell below 1.5 all game and the quota sat
// pinned at MASS_CAP", with 20 of 30 games hitting the time limit undecided.
// apexearth, watching an 8v8: "we just don't really attack ever... so the enemy
// only ever takes territory from us slowly over time and we never get any of it
// back."
//
// The hold exists for a real reason -- units trickling out one at a time and
// dying -- so it is not removed. It is given a deadline: once we have been
// pinned at the cap this long, fall back to MASS_FLOOR, which is still a group
// and never a trickle, so something goes out and the ratio can change.
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
	// SIZE THE GROUP AGAINST WHAT IT IS ATTACKING, NOT AGAINST THEIR WHOLE ARMY.
	//
	// Everything below scales the group we commit with the ratio of their total
	// army to ours, which is the right question only if the objective is their
	// army. It is not. apexearth: "comparing how much you need to attack with
	// their army size, then the goal is to attack mex locations... not their
	// army" -- and an undefended extractor needs enough to kill the extractor,
	// not enough to beat everything they own.
	//
	// Measured live in an 8v8: the ratio sat at 1.28-1.35, so this returned
	// 41-43 as the MINIMUM number of attackers before the engine would form any
	// attack at all. Behind on economy means behind on army means a bigger
	// demand means we never go, which loses more ground -- the trap this file's
	// own history already records ("the ratio never fell below 1.5 all game").
	//
	// Safety has not been given up, it has been moved to where it belongs: the
	// attack task refuses a target whose local defence outweighs the group
	// (localInfl and the strength test in CAttackTask::FindTarget), and target
	// selection now prefers UNDEFENDED economy outright (FREE_ECO_PRIORITY). So
	// a floor-sized group goes out and picks something it can actually kill,
	// instead of a map-wide army comparison deciding nobody leaves home.
	// The floor itself is now the whole answer, so it is tunable. apexearth:
	// "enemy mexes are often unguarded and could be taken out by a group of ~10
	// grunts even 15m into the game... to require 30 units for the type of attack
	// im talking about is way too much", and "think about how much 10 grunts
	// costs... 500 metal? if we have 1000+ metal worth of units we could use them
	// as an attack force to AVOID enemy army and ATTACK enemy metal."
	//
	// A Grunt is 42 metal and a Pawn 54, so ~10 of them is 420-540 metal and
	// 1,000 metal is roughly twenty. Note this quota is a POWER sum
	// (CFighterTask: attackPower += cdef->GetPower()), not a unit count and not
	// metal, so the value here is calibrated by measurement rather than typed in
	// from the metal figure.
	if (ai.GetTunable("apex_mass_vs_army", 0.f) <= 0.f)
		return ai.GetTunable("apex_mass_floor", MASS_FLOOR);

	const float ours = TeamArmyCost();
	const float theirs = EnemyMassingThreat();
	if (ours <= 1.f)
		return MASS_CAP;
	const float ratio = theirs / ours;
	if (ratio <= ATTACK_EDGE)
		return MASS_FLOOR;                    // ahead: move, but as a group
	if (ratio >= MASS_HOLD_RATIO)
		return MASS_CAP;                      // outmatched: hold
	const float t = (ratio - ATTACK_EDGE) / (MASS_HOLD_RATIO - ATTACK_EDGE);
	return MASS_FLOOR + t * (MASS_CAP - MASS_FLOOR);
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

	// No army of our own is the 2v6 case: demand a full mass rather than let
	// the first two units that exist wander out and die.
	//
	// TEAM against team. aiMilitaryMgr.armyCost is THIS player's army while
	// EnemyArmyCost() sums every enemy, so comparing them on a 4v4 is one
	// player against four and reads ~4x too pessimistic -- measured, the ratio
	// never fell below 1.5 all game and the quota sat pinned at MASS_CAP, i.e.
	// permanently holding. TeamArmyCost() sums the ally side over TV_ARMY, the
	// same figure the killing blow already compares on.
	const float ours = TeamArmyCost();
	const float theirs = EnemyMassingThreat();
	float want = MassWant();

	// Bound the hold. MassWant returns MASS_CAP only in the outmatched case, so
	// that is the signal we are holding rather than committing.
	const float holdSecs = ai.GetTunable("apex_mass_hold_secs", 120.f);
	// Keyed on "demanding more than the floor", not on reaching the cap. Measured
	// in a live 8v8: the ratio sat at 1.28-1.35, just UNDER MASS_HOLD_RATIO, so
	// want interpolated to 41-43 and never touched MASS_CAP -- a deadline keyed
	// on the cap would never have fired while the army waited for a group of
	// forty-plus that a halved economy cannot field.
	if (want > MASS_FLOOR + 1.f) {
		if (gHoldSince < 0)
			gHoldSince = ai.frame;
		if ((holdSecs > 0.f) && (ai.frame - gHoldSince > int(holdSecs) * SECOND)) {
			want = MASS_FLOOR;
			gHoldSince = ai.frame;   // restart, so we alternate hold and commit
			AiLog(Factory::T() + "apex: mass hold expired, committing at floor");
		}
	} else {
		gHoldSince = -1;
	}

	if (ai.frame >= gNextMassLog) {
		gNextMassLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: mass want=" + formatFloat(want, "", 0, 0)
			+ " army=" + formatFloat(ours, "", 0, 0)
			+ " enemyArmy=" + formatFloat(theirs, "", 0, 0)
			+ " ratio=" + formatFloat((ours > 0.f) ? theirs / ours : 0.f, "", 0, 2));
	}
	if (aiMilitaryMgr.quota.attack < want)
		aiMilitaryMgr.quota.attack = want;
}

//------------------------------------------------------------------------------
// KILLING BLOW.
//
// apexearth: "we are often winning but we're very slow to kill enemies ... we
// need some sort of switch which says ok now go for the killing blow."
//
// Measured, 30 games across 8 maps: 20 of them (67%) hit the time limit
// undecided, and on Quicksilver we finished 16 games holding 4.5x stock's metal,
// 35x its T3 and 8.5x its army while ELEVEN went unresolved. Dominance that does
// not convert is worth nothing -- a timed-out game is not a win.
//
// The cause is the massing rule doing its job too well. quota.attack is a
// MINIMUM number of attackers before the engine will form an attack, and
// UpdateMassing walks it up to MASS_CAP and pins it at MASS_CAP outright
// whenever the enemy out-values us. Once we are far ahead that gate is pure
// delay: we hold an army several times their size and keep waiting for a bigger
// one.
//
// So: when we are clearly winning, stop waiting. Drop the minimum so attacks
// form continuously and release the turtle if it is holding.
//
// Lowering minAttackers globally is known to be catastrophic -- 15 -> 6 scored
// 0-10. This is not that. It is
// conditional on holding KILL_EDGE times the enemy's army value, where even a
// partial commitment outnumbers everything they can field.
// 2.5x was too strict to be useful. Measured: it first became true at 36.8
// minutes of a 50-minute game -- teamArmy 44,497 against 17,783 -- which is long
// past the point where a push has time to finish anything. The whole complaint
// is that we win slowly, so a switch that only flips once the win is already
// overwhelming does not address it. 1.8x is still a commanding lead.
const int   KILL_FROM  = 15 * MINUTE;   // not before the T2 transition settles
const float KILL_EDGE  = 1.8f;          // OUR TEAM's army value against theirs
const float KILL_FLOOR = 20000.f;       // ignore ratios off a tiny enemy sample
const float KILL_QUOTA = 10.f;          // attack with what we have, repeatedly
bool gKilling = false;

// Our whole side's army value, pooled over the same blackboard the tech lead
// election uses.
//
// This has to be TEAM against TEAM. aiMilitaryMgr.armyCost is one player's army
// while EnemyArmyCost() sums the entire enemy side, so comparing them directly
// asks "is one of us worth more than all eight of them" -- measured in the first
// smoke run at army 11,525 against enemyArmy 41,903, a ratio of 3.6 AGAINST us
// in a game we were dominating. The gate was unreachable by construction, the
// same way LosingGround() is permanently TRUE for a player with no army.
const string TV_ARMY = "army";

}  // namespace Military

// One-off calibration. quota.attack is compared against a POWER SUM
// (CFighterTask: attackPower += cdef->GetPower()), not a unit count, so
// MASS_FLOOR's "30" is not thirty units and the group size apexearth is asking
// for cannot be typed in without knowing what a unit is worth. Logs the power of
// a few representative combat units once, so the floor can be set from the
// actual number instead of a guess.
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
