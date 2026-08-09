namespace Military {

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
	const float want = MassWant();

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
