namespace Air {

void ResolveDefs()
{
	if (gDefsResolved)
		return;
	gDefsResolved = true;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		@gPlant1 = ai.GetCircuitDef("corap");   @gPlant2 = ai.GetCircuitDef("coraap");
		@gCon1   = ai.GetCircuitDef("corca");   @gCon2   = ai.GetCircuitDef("coraca");
		@gBomber = ai.GetCircuitDef("corhurc"); @gFighter = ai.GetCircuitDef("corvamp");
		@gBomber1 = ai.GetCircuitDef("corshad"); @gFighter1 = ai.GetCircuitDef("corveng");
	} else if (side == "legion") {
		@gPlant1 = ai.GetCircuitDef("legap");   @gPlant2 = ai.GetCircuitDef("legaap");
		@gCon1   = ai.GetCircuitDef("legca");   @gCon2   = ai.GetCircuitDef("legaca");
		@gBomber = ai.GetCircuitDef("legphoenix"); @gFighter = ai.GetCircuitDef("legvenator");
		// gBomber1 is the BASIC tier: a reusable strike unit built off the T1 plant,
		// held and released in waves (see Release()/ScaledBombers() below), the same
		// way corshad/armthund are. legkam ("Martyr") is a one-shot kamikaze drone,
		// unlike those two -- looked like a bug and was swapped for legmos
		// ("Mosquito") on 2026-08-05, but that regressed a confirmed Legion,Legion
		// batch 43.8% -> 31.2%. legmos's weapon has stockpile=true (a 1.8s build-up,
		// 4-shot cap, like a nuke silo) -- Release()'s hold-then-send logic has no
		// stockpile-order step, so these almost certainly flew in with zero shots
		// loaded and did nothing, worse than a kamikaze that at least explodes.
		// Reverted. legap's roster (legca, legfig, legkam, legcib, legmos, leglts,
		// legatrans) has no conventional always-loaded reusable bomber -- legkam is
		// the least-bad fit until a real alternative is found (or gBomber1 is left
		// null for Legion and this basic tier is skipped entirely).
		@gBomber1 = ai.GetCircuitDef("legkam"); @gFighter1 = ai.GetCircuitDef("legfig");
	} else {
		@gPlant1 = ai.GetCircuitDef("armap");   @gPlant2 = ai.GetCircuitDef("armaap");
		@gCon1   = ai.GetCircuitDef("armca");   @gCon2   = ai.GetCircuitDef("armaca");
		@gBomber = ai.GetCircuitDef("armpnix"); @gFighter = ai.GetCircuitDef("armhawk");
		@gBomber1 = ai.GetCircuitDef("armthund"); @gFighter1 = ai.GetCircuitDef("armfig");
	}
}

// The elector -- lowest team id in the ally roster -- is Factory::ElectorTeamId().
// Reusing it keeps one writer for both elections instead of two schemes that can
// disagree about who is allowed to publish.
void RunElection()
{
	if (ai.ReadTeamValue(ai.teamId, TV_AIRLEAD, -1.f) >= 0.f)
		return;   // latched: the role is paid for in factories, so it never moves
	if (ai.frame < AIR_FROM)
		return;

	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return;
	const int tech = Factory::RushLeadTeamId();
	const bool skipTech = (mates.length() > 1);

	int best = -1;
	float bestInc = AIR_MIN_INCOME;
	float bestSeen = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (skipTech && (t == tech))
			continue;
		const float inc = ai.ReadTeamValue(t, TV_AIRINC, -1.f);
		if (inc > bestSeen)
			bestSeen = inc;
		if (inc > bestInc) {
			bestInc = inc;
			best = t;
		}
	}
	if (best < 0) {
		// Say so. An unmet income bar and a script that never compiled produce the
		// same silence, and this bar is deliberately set above what the 4v4
		// benchmark reaches -- so "no air all game" is the expected result there
		// and has to be distinguishable from a broken build.
		if (ai.frame >= gNextElectLog) {
			gNextElectLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: no air assassin, best ally income "
				+ formatFloat(bestSeen, "", 0, 0)
				+ "/" + formatFloat(AIR_MIN_INCOME, "", 0, 0));
		}
		return;
	}

	ai.PublishTeamValue(TV_AIRLEAD, float(best));
	AiLog(Factory::T() + "apex: air assassin = team " + best
		+ " at " + formatFloat(bestInc, "", 0, 0) + " metal/s");
}

int AirLeadTeamId()
{
	if (ai.frame < gLeadCheckedAt + 1 * SECOND)
		return gAirLead;
	gLeadCheckedAt = ai.frame;
	gAirLead = int(ai.ReadTeamValue(Factory::ElectorTeamId(), TV_AIRLEAD, -1.f));
	return gAirLead;
}

bool IsAirLead()
{
	const int lead = AirLeadTeamId();
	return (lead >= 0) && (lead == ai.teamId);
}

// Permanently stood down: gAbort is never reset and the election is latched,
// so this is one-way. factory.as reads it to release the air plants it would
// otherwise lock out of production for the rest of the game.
bool RoleAbandoned()
{
	return gAbort;
}

}  // namespace Air
