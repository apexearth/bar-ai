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

	// Incumbents first: a slot is kept while its holder still has (or can afford)
	// a plant, so it reopens only on a genuine loss rather than flapping between
	// close teams. Not bounded by Military::RUSH_GIVEUP -- TV_ADV already tracks
	// the loss live, so a separate frame bound is unnecessary.
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

	// The eco anchor takes slot 0 whenever it qualifies: the role is decided
	// at frame 0 and sticky (see EcoAnchorTeamId), so the election must not
	// move the sling target off it mid-game -- that transfer is what left
	// the first holder's army standing and its payments unpaid.
	// UNCONDITIONALLY: qualifying on TV_READY let a faster teammate commit
	// first and take the designation, which then BLOCKED the anchor's own T2
	// (MayPursueT2: once designated, only the lead continues) -- measured
	// +100 seed-33: the anchor teched at 14.2m while the elected teammate
	// teched at 7.1m and collected the payments. The anchor exists to tech;
	// it holds slot 0 from the first election.
	const int anchor = EcoAnchorTeamId();
	if ((anchor >= 0) && !IsInLeadList(leads, anchor)) {
		leads.insertAt(0, anchor);
		if (leads.length() > quota)
			leads.removeAt(leads.length() - 1);
	}

	// Fill remaining slots: committed teams first by plant progress, then for
	// empty slots the FURTHEST-BACK team that could afford one -- the player who
	// goes helpless while teching should be least likely to be attacked for it.
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
