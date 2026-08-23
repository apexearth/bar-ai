namespace Factory {

string armca("armca");   string corca("corca");   string legca("legca");

CCircuitDef@ AirConDef()
{
	return SideDef3(armca, corca, legca);
}

int AirConCount()
{
	CCircuitDef@ d = AirConDef();
	return (d is null) ? 0 : d.count;
}

// Any aircraft plant of ours, basic or advanced. AIR_FAC already names all six.
bool HaveAirFactory()
{
	for (uint i = 0; i < AIR_FAC.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(AIR_FAC[i]);
		if ((d !is null) && (d.count > 0))
			return true;
	}
	return false;
}

// The eco lead's aircraft plant exists to make CONSTRUCTORS, not an air force,
// which is why it is not gated on MayOpenAir(): that rule is about who fights in
// the air, and bars the tech lead outright. This asks for a plant only once the
// economy is large enough that ground engineers are the thing holding it back.
bool EcoWantsAirPlant()
{
	return gEcoActive && gHaveT2 && !HaveAirFactory()
		&& (aiEconomyMgr.metal.income >= ECO_AIR_PLANT_INCOME);
}

// The ally holding least of its own peak, whatever the bar. Used when the team
// is under pressure but nobody is dying yet: somebody still has it worst, and
// they are the one to push metal at.
int LowestHoldAlly()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return -1;
	int worst = -1;
	float worstHold = 2.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		const float hold = ai.ReadTeamValue(t, TV_MEX, 1.f);
		if (hold < worstHold) {
			worstHold = hold;
			worst = t;
		}
	}
	return worst;
}

// The ally in the worst trouble, by its own published share of peak extractors,
// or -1 when nobody is under the bar. Used for aid, so it deliberately reads the
// same number the release condition does.
int NeediestAlly()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return -1;
	int worst = -1;
	float worstHold = HURT_ALLY_FRAC;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		const float hold = ai.ReadTeamValue(t, TV_MEX, 1.f);
		if (hold < worstHold) {
			worstHold = hold;
			worst = t;
		}
	}
	return worst;
}

// Refresh the primary lead and whether THIS team holds any lead slot. Both come
// off one cadence because they read the same blackboard: un-cached this ran a
// string concatenation and an engine callback on every IsTechLead().
void RefreshLead()
{
	if (ai.frame < gLeadCheckedAt + 1 * SECOND)
		return;
	gLeadCheckedAt = ai.frame;

	// Read the ELECTOR's slots, not our own, and never anything keyed on
	// ai.allyTeamId: that read 0 for every instance in the shipped DLL, which
	// had ally 1 pooling behind ally 0's lead.
	const int elector = ElectorTeamId();
	const uint quota = TechLeadQuota();
	bool mine = false;
	for (uint s = 0; s < quota; ++s) {
		if (int(ai.ReadTeamValue(elector, LeadKey(s), -1.f)) == ai.teamId) {
			mine = true;
			break;
		}
	}
	if (mine != gAmLead) {
		AiLog(T() + "apex: tech lead role " + (mine ? "TAKEN" : "released")
			+ " (quota " + quota + ")");
		gAmLead = mine;
	}

	const int lead = int(ai.ReadTeamValue(elector, TV_LEAD, -1.f));
	// Nobody has committed yet. Keep the last known lead if we ever had one,
	// rather than reporting "nobody".
	if (lead < 0)
		return;

	// Not latched here: the elector can hand a slot over if its holder loses its
	// plant before the give-up frame.
	if (lead != gRushLead) {
		AiLog(T() + "apex: tech lead "
			+ ((gRushLead < 0) ? "= team " + lead
			                   : "CHANGED team " + gRushLead + " -> " + lead));
		gRushLead = lead;
		// gT1Reclaimed is deliberately NOT cleared: the reclaim stays one-shot
		// per instance.
	}
}

// Is the lead saturated -- i.e. is a donation now just overflow?
bool LeadIsSaturated(int lead)
{
	return ai.ReadTeamValue(lead, TV_FILL, 0.f) >= SLING_STOP_FILL;
}

// Has the lead got the plant the pooling was paying for?
bool LeadHasPlant(int lead)
{
	return ai.ReadTeamValue(lead, TV_ADV, -1.f) >= 1.f;
}

// The PRIMARY lead (slot 0). Slinging and the air lead want a single target, not
// the whole set -- donations split across two leads fund neither.
int RushLeadTeamId()
{
	// SOLO HAS NO LEAD TO ELECT. The fallback is ai.GetLeadTeamId(), which with
	// no allies is US -- so "am I the rusher", "am I the sling target" and "am I
	// the air tech lead" all read TRUE, and the whole team pathway ran in a 1v1
	// while the role itself was supposedly off. -1 matches no team id, so every
	// such test is false and the general-purpose paths take over.
	if (!TeamPlay())
		return -1;
	RefreshLead();
	return (gRushLead >= 0) ? gRushLead : ai.GetLeadTeamId();
}

}  // namespace Factory
