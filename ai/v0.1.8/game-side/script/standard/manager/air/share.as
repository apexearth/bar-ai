namespace Air {

//------------------------------------------------------------------------------
// ONE WING, NOT FOUR HALF-WINGS (apexearth 2026-09-29: "share aircraft to
// somebody who's maybe got the most air already so that they can be the one to
// more quickly launch the next raid"). Not the elected lead -- there is not
// always one: the ally holding the most bomber weight at home receives, and
// every other seat hands it the bombers it holds that are not out on a strike.
// Same faction only (a wing counts its own faction's bombers), never while our
// own base is being defended, never the atomic bomber (its own strike). Human
// allies never publish, so nothing goes to a person.
//------------------------------------------------------------------------------

const string TV_AIRHELD = "airheld";
const string TV_AIRBDEF = "airbdef";
int gShareAt = 0;
int gShareGiven = 0;

void ShareWing()
{
	if (ai.frame < gShareAt)
		return;
	gShareAt = ai.frame + 10 * SECOND;
	const float mine = HeldMassAtHome();
	const float bdef = (gBomber !is null) ? float(gBomber.id) : -1.f;
	ai.PublishTeamValue(TV_AIRHELD, mine);
	ai.PublishTeamValue(TV_AIRBDEF, bdef);
	if ((mine <= 0.f) || (bdef < 0.f) || gDefendHome)
		return;
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;
	int to = -1;
	float best = mine;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if ((t == ai.teamId) || (ai.ReadTeamValue(t, TV_AIRBDEF, -1.f) != bdef))
			continue;
		const float held = ai.ReadTeamValue(t, TV_AIRHELD, -1.f);
		// Equal wings pool on the lower team id, so two halves still become one.
		if ((held > best) || ((held == best) && (t < ai.teamId) && ((to < 0) || (t < to)))) {
			best = held;
			to = t;
		}
	}
	if (to < 0)
		return;
	array<CCircuitUnit@> give;
	for (int i = 0; i < 3; ++i) {   // heavy, advanced, basic -- not the atomic
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && !InWave(us[k].id) && !Covering(us[k].id))
				give.insertLast(us[k]);
		}
	}
	if (give.length() == 0)
		return;
	ai.GiveUnits(give, to);
	gShareGiven += int(give.length());
	AiLog(Factory::T() + "apex: air share " + give.length() + " bombers -> t=" + to
		+ " mine=" + int(mine) + " theirs=" + int(best) + " total=" + gShareGiven);
}

// The pooled wing: the largest held bomber weight any same-faction ally has
// published, ours included.
float TeamWingHeld()
{
	float best = HeldMassAtHome();
	const float bdef = (gBomber !is null) ? float(gBomber.id) : -1.f;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (bdef < 0.f))
		return best;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if ((t == ai.teamId) || (ai.ReadTeamValue(t, TV_AIRBDEF, -1.f) != bdef))
			continue;
		const float held = ai.ReadTeamValue(t, TV_AIRHELD, -1.f);
		if (held > best)
			best = held;
	}
	return best;
}

// Bomber weight at home that a strike could take, finished planes only.
float HeldMassAtHome()
{
	float m = 0.f;
	for (int i = 0; i < 3; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && !InWave(us[k].id))
				m += BomberUnits(d);
		}
	}
	return m;
}

}  // namespace Air
