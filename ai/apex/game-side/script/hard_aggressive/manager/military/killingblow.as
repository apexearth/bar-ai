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
	AiLog(Factory::T() + "apex: KILLING BLOW " + (now ? "ON" : "off")
		+ " teamArmy=" + formatFloat(TeamArmyCost(), "", 0, 0)
		+ " enemyArmy=" + formatFloat(EnemyFieldCost(), "", 0, 0));
}


//------------------------------------------------------------------------------
// Base defence scaled to the threat closing in.
//
// apexearth: "scan outside the range of that base for the total threat. And if
// that value exceeds your base by some percentage, then you multiply the amount
// of porc you're willing to make."
//
// This cannot be done by asking DefaultMakeDefence for more. `prevent` is a hard
// cap -- num = min(isPorc ? defenders.size() : prevent, defenders.size()) -- and
// its per-point cost accumulator makes a repeat call walk PAST what is already
// paid for rather than add to it. So the extra towers are enqueued here.
//
// Threat is sampled on a ring OUTSIDE the base, which is the "getting closer and
// closer over four or five minutes" signal: an army massing at our doorstep
// registers on the ring long before it is inside.
//------------------------------------------------------------------------------
// FRONT-LINE AREA DEFENCE.
//
// A mechanism of its own, deliberately -- not a tweak to porcupine.prevent.
// apexearth: "I think that prevent is the wrong mechanism to tweak here. We
// need a new mechanism, that area defense, front line defense sort of thing."
// prevent applies at every cluster equally and cannot express "the front", so
// raising it walled quiet rear mexes. It is back at 2 and this owns the heavy
// defence instead.
//
// Towers are laid ACROSS the approach, not stacked on one point: offsets step
// out alternately either side of the front position, perpendicular to the
// home->enemy axis, so they form a line facing the enemy rather than a pile.
// That is the buildable approximation of apexearth's territory-grid idea while
// CInfluenceMap remains unreachable from script (see notes #12).
//
// Enemy army value against our standing towers.
//
// apexearth: "scan outside the range of that base for the total threat. And if
// that value exceeds your base by some percentage, then you multiply the amount
// of porc you're willing to make."
//
// The positional form of that was tried first and does not work. Two reasons,
// both measured:
//   - CThreatMap::GetBuilderThreatAt bounds-checks with an assert only, compiled
//     out in release, then indexes surfThreat unchecked. Sampling a ring of
//     radius 1500 around a base near the map edge read off-map memory and
//     crashed the AI at frame 3 (0xc0000005). No map-size binding exists to
//     clamp against.
//   - Sampling only positions provably inside the map (interpolations along
//     home->enemy) does not crash, but returns ZERO almost always. The same
//     query was already measured at 3% nonzero across ten games and is the
//     reason the old commander-threat retreat never fired.
//
// So the comparison keeps apexearth's shape -- their strength against ours,
// scaled -- using the enemy army value, which is a real number in these logs
// (120 to 6,648 over one game) rather than a mostly-empty map lookup.
// 2.0, not 1.5. First measurement with mDefence: static defence was 14.1% of
// our metal against stock's 5.7%, while army was 26.2% against 30.7%.
// apexearth: "the side effect is wasteful defense and then we have less army
// and are losing the overall fight." Fire only when clearly outmatched.
// Toggle for A/B: false restores the old two-per-AI behaviour exactly.
const float JAMMER_BACK     = 180.f;  // just behind the tower it covers    // was 10, then 4; see PORC_TRIGGER
// The front is the contested area; allow a real position there, not a pair.
// A leak is answered on a looser bar than the front: the point is to be present
// at all in the interior, not to build a wall there.
// How far a constructor may be sent to place one. Beyond this it is commuting
// across the map instead of building, and that is constructor time, which is the
// economy.
// How far back from the front the tower actually goes. Far enough that the
// builder is not standing in the fight, close enough that the tower still
// covers the approach.
// Enemy metal already within this radius of the site that makes it not worth
// starting. A tower that dies half-built cost the constructor-seconds anyway.
// Relaxed once territory required DOMINANCE: the front already sits in ground we
// hold, so a strict veto here refused sites that were never dangerous. Stacked
// with the setback it strangled construction -- defence built fell 21,285 ->
// 8,360 -> 2,950 metal across three runs as each veto went in. Only a genuinely
// hot site is refused now.

}  // namespace Military
