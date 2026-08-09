namespace Factory {

// Lowest team id in the ally roster. Every instance computes the same answer
// from the same roster with no signalling, so all of them know whose blackboard
// slot carries the election result.
int ElectorTeamId()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return ai.teamId;
	int low = int(mates[0]);
	for (uint i = 1; i < mates.length(); ++i) {
		if (int(mates[i]) < low)
			low = int(mates[i]);
	}
	return low;
}

// Only the elector runs this, and it publishes under its OWN slot.
void RunElection()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;

	const uint quota = TechLeadQuota();

	// Incumbents first. A slot is kept while its holder still has a plant or a
	// nanoframe, or is still able to pay for one -- reopening only on a genuine
	// loss is what stops the role flapping between two teams whose progress is
	// neck and neck.
	//
	// Deliberately NOT bounded by Military::RUSH_GIVEUP: that made retention
	// unconditional past 15 min, so a lead that lost its plant kept the slot
	// and it never reopened. TV_ADV already tracks the loss live.
	array<int> leads;
	for (uint s = 0; s < quota; ++s) {
		const int held = int(ai.ReadTeamValue(ai.teamId, LeadKey(s), -1.f));
		if (held < 0)
			continue;
		if ((ai.ReadTeamValue(held, TV_ADV, -1.f) > 0.f)
			|| (ai.ReadTeamValue(held, TV_READY, 0.f) > 0.f))
		{
			leads.insertLast(held);
		}
	}

	// Fill whatever is left. Committed teams rank first, by how far along their
	// plant is; then, for slots still empty, the FURTHEST-BACK team that could
	// afford one -- the player who goes helpless should be the one least likely
	// to be attacked while it is. Richest-that-is-ready ignored position
	// entirely, which is how the front-line player ended up teching.
	while (leads.length() < quota) {
		int best = -1;
		float bestProgress = 0.f;
		for (uint i = 0; i < mates.length(); ++i) {
			const int t = int(mates[i]);
			if (IsInLeadList(leads, t))
				continue;
			const float p = ai.ReadTeamValue(t, TV_ADV, -1.f);
			if (p <= 0.f)
				continue;   // has not committed to an advanced plant
			if ((p > bestProgress) || ((p == bestProgress) && (t < best))) {
				bestProgress = p;
				best = t;
			}
		}
		if (best < 0) {
			float bestDist = -1.f;
			for (uint i = 0; i < mates.length(); ++i) {
				const int t = int(mates[i]);
				if (IsInLeadList(leads, t))
					continue;
				if (ai.ReadTeamValue(t, TV_READY, 0.f) <= 0.f)
					continue;   // cannot afford it anyway
				const float d = ai.ReadTeamValue(t, TV_DIST, 0.f);
				if ((d > bestDist) || ((d == bestDist) && (best >= 0) && (t < best))) {
					bestDist = d;
					best = t;
				}
			}
		}
		if (best < 0)
			break;   // no further candidate; leave the slot empty
		leads.insertLast(best);
	}

	for (uint s = 0; s < quota; ++s)
		ai.PublishTeamValue(LeadKey(s), (s < leads.length()) ? float(leads[s]) : -1.f);
}

bool IsInLeadList(const array<int>@ leads, int team)
{
	for (uint i = 0; i < leads.length(); ++i) {
		if (leads[i] == team)
			return true;
	}
	return false;
}

}  // namespace Factory
