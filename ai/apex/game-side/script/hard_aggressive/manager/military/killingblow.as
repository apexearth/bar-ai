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
	if (ai.frame < KILL_FROM)
		return false;
	const float ours = TeamArmyCost();
	const float theirs = EnemyFieldCost();
	if (ours < KILL_FLOOR)
		return false;
	// Hysteresis, so a single lost engagement does not flip us back to massing
	// half way through the push that is winning the game.
	return gKilling ? (ours > theirs * (KILL_EDGE * 0.6f))
	                : (ours > theirs * KILL_EDGE);
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
