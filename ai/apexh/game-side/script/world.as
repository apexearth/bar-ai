// Map geometry shared by every manager.
//
// Not in a namespace: this was Builder::OnMap and five other namespaces reached
// across for it, which is the shape of a helper that belongs to nobody.

// CThreatMap indexes its arrays straight from the position and range-checks only
// under assert; the bound is a strict less-than against the terrain extent.
// -RgtVector, the engine's "no position", fails the first test.
bool OnMap(const AIFloat3& in p)
{
	return (p.x >= 0.f) && (p.z >= 0.f)
		&& (p.x < float(AiTerrainWidth())) && (p.z < float(AiTerrainHeight()));
}

// Does apex's own game-side behaviour run at all?
//
// Everything this variant adds on top of stock is TEAM machinery: pool the
// team's metal behind one elected tech lead, hold the followers back to defend,
// elect an eco lead and an air slot, run a shared front line. With no allies
// there is nobody to pool from, nobody to hold ground and no line to share, and
// the machinery runs against itself -- see CHANGES.md 2026-08-10 for the
// per-layer measurement that establishes the size of it.
//
// `apex_solo_stock=0` restores the old behaviour for an A/B.
// Cached: GetTeamIds is an engine callback and this is read on every task
// decision. The ally roster is fixed for the game, so the first answer with a
// populated roster is the answer.
int gApexActive = -1;

bool ApexActive()
{
	if (gApexActive < 0) {
		array<Id>@ mates = ai.GetTeamIds();
		if ((mates is null) || (mates.length() == 0))
			return true;   // roster not up yet; do not latch on it
		gApexActive = ((mates.length() > 1)
			|| (ai.GetTunable("apex_solo_stock", 1.f) <= 0.f)) ? 1 : 0;
	}
	return gApexActive == 1;
}
