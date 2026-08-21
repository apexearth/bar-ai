namespace Military {

float TeamArmyCost()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return aiMilitaryMgr.armyCost;
	float total = 0.f;
	for (uint i = 0; i < mates.length(); ++i)
		total += ai.ReadTeamValue(int(mates[i]), TV_ARMY, 0.f);
	return total;
}

bool KillingBlow()
{
	// THE T1 COMMIT IS ALL OR NOTHING. apexearth 2026-08-20, watching it
	// fail: "we aren't aggressive enough to win in that 'T1-commit' tactic.
	// Spend too much time being distracted running all over the map and we
	// don't truly attack the enemy base. 'all or nothing' style." A tempo
	// strategy's army has one job -- the enemy base -- so while committed the
	// blow arms with no clock floor and at a tempo edge instead of the
	// late-game 1.8x: believe you are stronger, go end it. Every loss in the
	// 2026-08-20 set was the tempo never cashing while the army ran map
	// errands and raiders ate the builders at home.
	if (Factory::T1Commit()) {
		const float oursT1 = OurArmyNow();
		float theirsT1 = FoeMobileMassing();
		if (gSeenPeak > theirsT1)
			theirsT1 = gSeenPeak;
		const float edge = ai.GetTunable("apex_t1_push_edge", TUNE_T1_PUSH_EDGE);
		// WIDE hysteresis, or it is not "all or nothing". At on=1.2x/off=0.72x
		// the fog-driven enemy estimate wobbled the blow ON and off 15 times
		// in one 35-minute draw (zero pushes actually broken -- every one was
		// CALLED OFF), while we led economy and army throughout. Armed, the
		// commit holds until a genuine reversal: their read at twice ours.
		const float offEdge = ai.GetTunable("apex_t1_push_off", TUNE_T1_PUSH_OFF);
		if ((oursT1 >= MassFloor() / 0.017f)
			&& (oursT1 > theirsT1 * (gKilling ? offEdge : edge)))
		{
			return true;
		}
		// fall through: the normal gates below may still arm it
	}
	if (ai.frame < KILL_FROM)
		return false;
	// OurArmyNow, not TeamArmyCost: armyCost read ~40% of the field telemetry
	// (see massing.as). And KILL_FLOOR=20000 was an absolute no benchmark-scale
	// economy ever reaches -- the blow could not fire at all below ~100 m/s
	// income (zero firings across every 2026-08-20 game). Both guards it stood
	// for are kept, economy-derived: the fog guard commits only past the most
	// army they have ever shown at once, and the size guard is one real attack
	// group at the massing system's own floor, in metal.
	const float ours = OurArmyNow();
	float theirs = EnemyFieldCost();
	if (gSeenPeak > theirs)
		theirs = gSeenPeak;
	if (ours < MassFloor() / 0.017f)
		return false;
	// Hysteresis, so a single lost engagement does not flip us back to massing
	// half way through the push that is winning the game.
	return gKilling ? (ours > theirs * (KILL_EDGE() * 0.6f))
	                : (ours > theirs * KILL_EDGE());
}

void UpdateKillingBlow()
{
	ai.PublishTeamValue(TV_ARMY, aiMilitaryMgr.armyCost);
	const bool now = KillingBlow();
	if (now == gKilling)
		return;
	gKilling = now;
	// The C++ attack pather reads this: while the blow is on, squads path like
	// chargers (pure distance, no threat detour). apexearth, watching the won
	// endgame: an enormous army orbiting two doomsday guns' range rings
	// instead of saturating them -- caution is for games still in doubt.
	ai.PublishTeamValue("kill", now ? 1.f : 0.f);
	AiLog(Factory::T() + "apex: KILLING BLOW " + (now ? "ON" : "off")
		+ " teamArmy=" + formatFloat(TeamArmyCost(), "", 0, 0)
		+ " enemyArmy=" + formatFloat(EnemyFieldCost(), "", 0, 0));
}


//------------------------------------------------------------------------------
// Front-line area defence, sized to the threat closing in.
//
// `prevent` (porcupine.prevent) is a hard per-cluster cap, and its cost
// accumulator makes a repeat call walk PAST what is already paid for rather
// than add to it -- it applies equally at every cluster and cannot express
// "the front" -- so the extra towers for a threatened front are enqueued
// here instead. Threat is sampled on a ring OUTSIDE the base so an army
// massing at our doorstep registers before it is inside.
//
// Towers are laid ACROSS the approach, not stacked on one point: offsets step
// out alternately either side of the front position, perpendicular to the
// home->enemy axis, so they form a line facing the enemy rather than a pile.
//
// Compares enemy army value against our standing towers, not a positional
// threat sample: CThreatMap::GetBuilderThreatAt is unsafe near the map edge
// (bounds-checked only by an assert, compiled out in release, then indexes
// surfThreat unchecked) and reads zero almost everywhere else on the interior.
//------------------------------------------------------------------------------
const float JAMMER_BACK     = 180.f;  // stand the jammer just behind the tower it covers

}  // namespace Military
