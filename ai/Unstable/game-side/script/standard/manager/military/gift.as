namespace Military {

//------------------------------------------------------------------------------
// ARMY FLOWS TO THE FRONT (apexearth, twice): back players GIVE their ground
// army to the front-line players. Ownership is what fixes the repercussions
// he named -- a gifted unit's retreat/heal anchor becomes the FRONT player's
// base instead of a home half the map away, and squads consolidate under one
// commander instead of trickling in per-player.
//
// Election mirrors the rear-specialist's: allies' homes off the team
// blackboard, enemy reference = ally centroid mirrored through map center.
// The `apex_front_n` closest homes are RECEIVERS; everyone else ships.
// Only instances that PUBLISH homes participate -- human allies never
// appear on the blackboard, so nothing is ever gifted to a person.
//------------------------------------------------------------------------------

int gGiftNextAt = 0;
int gGiftTarget = -1;      // receiving teamId, -1 = we are front (or unknown)
int gGiftShipped = 0;

void ElectGiftTarget()
{
	gGiftTarget = -1;
	if (!Builder::gHomeSet)
		return;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 3))
		return;
	array<int> ids;
	array<float> hx, hz;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const float x = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float z = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		ids.insertLast(int(mates[i]));
		hx.insertLast(x);
		hz.insertLast(z);
		cx += x;
		cz += z;
	}
	if (ids.length() < 3)
		return;
	cx /= float(ids.length());
	cz /= float(ids.length());
	const float ex = float(AiTerrainWidth()) - cx;
	const float ez = float(AiTerrainHeight()) - cz;
	array<float> ds;
	for (uint i = 0; i < ids.length(); ++i) {
		const float dx = hx[i] - ex;
		const float dz = hz[i] - ez;
		ds.insertLast(dx * dx + dz * dz);
	}
	const int frontN = int(ai.GetTunable("apex_front_n", TUNE_FRONT_N));
	// The frontN smallest distances are the receivers.
	array<float> sorted = ds;
	sorted.sortAsc();
	const float bar = sorted[(frontN <= int(sorted.length()))
			? uint(frontN - 1) : sorted.length() - 1];
	float mine = -1.f;
	int best = -1;
	float bestD = -1.f;
	for (uint i = 0; i < ids.length(); ++i) {
		if (ids[i] == ai.teamId)
			mine = ds[i];
		else if ((ds[i] <= bar) && ((bestD < 0.f) || (ds[i] < bestD))) {
			bestD = ds[i];
			best = ids[i];
		}
	}
	// We ship only if we are NOT a receiver ourselves.
	if ((mine >= 0.f) && (mine > bar) && (best >= 0))
		gGiftTarget = best;
}

void UpdateGifts()
{
	if (ai.frame < gGiftNextAt)
		return;
	gGiftNextAt = ai.frame + 30 * SECOND;
	if (ai.GetTunable("apex_gift_army", TUNE_GIFT_ARMY) <= 0.f)
		return;
	ElectGiftTarget();
	if (gGiftTarget < 0)
		return;
	// Home under threat keeps its army: the gift is surplus positioning,
	// never self-disarmament.
	if (Builder::gHomeSet && (ai.GetEnemyCostAt(Builder::gHomePos, 2500.f) > 250.f))
		return;
	array<CCircuitUnit@> give;
	const AIFloat3 home = Builder::gHomeSet ? Builder::gHomePos : AIFloat3();
	const float r = float(AiTerrainWidth() + AiTerrainHeight());
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		// Ground army only: builders keep working, fighters guard their own
		// air lead's plan, and rezzers stay with their wreck fields.
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d] || Catalog::gFlyer[d]
			|| Catalog::gRezzer[d] || (Catalog::gPower[d] <= 1.f))
			continue;
		CCircuitDef@ cdef = Catalog::Def(d);
		if ((cdef is null) || (cdef.count <= 0))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(cdef, home, r);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			if (us[i] !is null)
				give.insertLast(us[i]);
		}
	}
	if (give.length() == 0)
		return;
	ai.GiveUnits(give, gGiftTarget);
	gGiftShipped += int(give.length());
	AiLog("apex: gifted " + give.length() + " army unit(s) to front team "
			+ gGiftTarget + " (total " + gGiftShipped + ")");
}

}  // namespace Military
