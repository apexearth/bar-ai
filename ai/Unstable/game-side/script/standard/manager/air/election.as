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
		@gBomberH = ai.GetCircuitDef("corcrwh");  // Dragon, 16,700 hp (corcrw is built by NOBODY)
	} else if (side == "legion") {
		@gPlant1 = ai.GetCircuitDef("legap");   @gPlant2 = ai.GetCircuitDef("legaap");
		@gCon1   = ai.GetCircuitDef("legca");   @gCon2   = ai.GetCircuitDef("legaca");
		@gBomber = ai.GetCircuitDef("legphoenix"); @gFighter = ai.GetCircuitDef("legvenator");
		// gBomber1 is the BASIC tier held/released like corshad/armthund. legap has
		// no conventional always-loaded reusable bomber, so legkam (a one-shot
		// kamikaze) stands in; a stockpile-weapon unit does not work here because
		// Release()'s hold-then-send logic has no stockpile-order step.
		@gBomber1 = ai.GetCircuitDef("legkam"); @gFighter1 = ai.GetCircuitDef("legfig");
		@gBomberH = ai.GetCircuitDef("legfort");  // Tyrannus, 16,700 hp
	} else {
		@gPlant1 = ai.GetCircuitDef("armap");   @gPlant2 = ai.GetCircuitDef("armaap");
		@gCon1   = ai.GetCircuitDef("armca");   @gCon2   = ai.GetCircuitDef("armaca");
		@gBomber = ai.GetCircuitDef("armpnix"); @gFighter = ai.GetCircuitDef("armhawk");
		@gBomber1 = ai.GetCircuitDef("armthund"); @gFighter1 = ai.GetCircuitDef("armfig");
		@gBomberH = ai.GetCircuitDef("armblade"); // Hornet, 3,000 hp -- Armada has no true heavy
		@gBomberN = ai.GetCircuitDef("armliche"); // Liche, the Atomic Bomber
	}
}

// The elector -- lowest team id in the ally roster -- is Factory::ElectorTeamId().
// Reusing it keeps one writer for both elections instead of two schemes that can
// disagree about who is allowed to publish.
void RunElection()
{
	if (ai.ReadTeamValue(ai.teamId, TV_AIRLEAD, -1.f) >= 0.f)
		return;   // latched: the role is paid for in factories, so it never moves
	if ((ai.frame < AIR_FROM) || !AirEcoReady())
		return;

	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return;
	// The tech-lead election died with the leaf rush machinery; nobody is
	// skipped for teching until the rebuild restores a lead concept.
	const int tech = -1;
	const bool skipTech = false;

	int best = -1;
	// An airboss persona lowers its own bar; the election shape is unchanged.
	float bestInc = AIR_MIN_INCOME / Persona::AirEagerness();
	float bestSeen = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (skipTech && (t == tech))
			continue;
		// The growing eco seat is the richest ally and buys no wing: an
		// assassin that never flies.
		if (ai.ReadTeamValue(t, Military::TV_ECOSEAT, 0.f) > 0.5f)
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
		// Log it: an unmet income bar and a script that never compiled produce the
		// same silence otherwise.
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

}  // namespace Air
