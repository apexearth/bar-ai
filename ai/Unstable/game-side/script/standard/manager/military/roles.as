namespace Military {

// KILL PHASE (docs/20-brain-overhaul.md): the rush/eco team roles, ally aid
// and metal slinging died with the leaf election machinery. The massing
// constants below are army-USE policy and stay.

// Attack in a mass, not a trickle.
//
// quota.attack is a MINIMUM: the AI will not launch until it has that much
// army. A low value attacks with whatever is to hand and feeds units into
// fights piecemeal, which grinds an army down without ever threatening
// anything. Lowering minAttackers globally is known to be catastrophic
// (15 -> 6 scored 0-10); this file's values move the other way.
//
// quota.attack is a POWER sum (CAttackTask's minPower), not a unit count and
// not metal -- armyCost/EnemyArmyCost() are metal, so only the dimensionless
// ratio theirs/ours bridges the two; the output stays in quota units. A Grunt
// is ~0.9 power, so MASS_FLOOR of 12 is roughly 13 Grunts or 8 Thugs: a real
// group, not a trickle.
// Ratio at or above which we stop attacking and let them come to the defences.
float MASS_HOLD_RATIO() { return ai.GetTunable("apex_mass_hold_ratio", TUNE_MASS_HOLD_RATIO); }
float MASS_CAP() { return ai.GetTunable("apex_mass_cap", TUNE_MASS_CAP); }
// A metal-vs-metal ratio, so 1.0 is a real parity point. EnemyArmyCost() sums
// GetEnemyCost over the fighting roles, the same unit as armyCost -- not
// aiEnemyMgr.mobileThreat, which is a different scale and never approaches 1.
float ATTACK_EDGE() { return ai.GetTunable("apex_attack_edge", TUNE_ATTACK_EDGE); }
int gNextMassLog = 0;

// EnemyArmyCost() sums only the mobile fighting roles, so a defended
// chokepoint reads identically to open ground as long as mobile counts match
// -- static defence is otherwise invisible to the massing decision.
//
// Weighted at half, not 1:1: a turret is a sunk cost with no upkeep, cannot
// retreat or redeploy, and only threatens the ground it covers, unlike a
// mobile unit of the same value. Folding it in at full weight would let a
// static-heavy base pin quota.attack at MASS_CAP for the rest of the game, so
// this is scoped to MassWant()/UpdateMassing() only -- KillingBlow() and
// T3Worthwhile(), which read EnemyArmyCost() directly, are unaffected, and the
// killing-blow override still bypasses this once we are dominant.
float STATIC_DEFENSE_WEIGHT() { return ai.GetTunable("apex_static_defense_weight", TUNE_STATIC_DEFENSE_WEIGHT); }

}  // namespace Military
