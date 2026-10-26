namespace Military {

// ONE ARMY COUNT, BOTH SIDES (the 10-24 review: five estimators disagreed, one per consumer). Ground only on both
// sides: mobile, armed, not a builder, not a flyer.
//   ours   = our own such units + every ally's (humans' included -- a player sees his allies)
//   theirs = foemem's believed army less its builders: seen live, remembered out of sight, and the uncertain rest
//            put back home (foemem counts commanders as army; the true numbers and our side do not)
// Scored against the true standing army (tools/armyest_score.py, 58 games): believed calls the stronger side right
// in 80% of seat-minutes where one side had 1.5x (84% after minute 15) and is 0.92 of the truth after minute 15;
// EnemyArmyCost calls it in 62% and reads a third.
float gAeOursAt = -1.f;
float gAeOurs = 0.f;
int gAeLogAt = 0;

float OwnGroundArmyM()
{
	float m = 0.f;
	const array<int>@ own = Market::OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d] || Catalog::gBuilder[d]
			|| (Catalog::gSurfDps[d] <= 0.f))
			continue;
		m += float(Market::gOwnCount[d]) * Catalog::gCostM[d];
	}
	return m;
}

float OurArmyM()
{
	if (gAeOursAt != float(ai.frame)) {
		gAeOursAt = float(ai.frame);
		gAeOurs = OwnGroundArmyM() + ai.GetAllyArmyM(false);
	}
	return gAeOurs;
}

float FoeArmyM()
{
	const float m = FoeBelievedM() - gFmBuilderM;
	return (m > 0.f) ? m : 0.f;
}

// THEIR T3: what foemem holds of their mobile T3, and from the first one seen a floor -- the biggest unit the gantry
// that built it can make (one gantry unit seen is a gantry owned; a player infers the same)
bool gAeT3Seen = false;
float gAeT3Floor = 0.f;
float gAeT3M = 0.f;
int gAeT3At = -999999;
array<bool> gAeT3Def;
void FoeT3Refresh()
{
	if (ai.frame - gAeT3At < 5 * SECOND)
		return;
	gAeT3At = ai.frame;
	if (gAeT3Def.length() == 0)
		gAeT3Def.resize(Catalog::gDefCount + 1);
	float m = 0.f;
	for (uint s = 0; s < gFmId.length(); ++s) {
		const int d = gFmDef[s];
		if ((gFmId[s] < 0) || (d <= 0) || (d > Catalog::gDefCount) || !Catalog::gMobile[d] || Catalog::gBuilder[d]
			|| (Market::TreeTier(d) < 3))
			continue;
		m += Catalog::gCostM[d];
		if (gAeT3Def[d])
			continue;
		gAeT3Def[d] = true;
		gAeT3Seen = true;
		const array<int>@ by = Catalog::gBuiltBy[d];
		for (uint i = 0; i < by.length(); ++i) {
			const int g = by[i];
			if (!Catalog::ValidId(g) || Catalog::gMobile[g])
				continue;
			const array<int>@ bo = Catalog::gBuildsList[g];
			for (uint j = 0; j < bo.length(); ++j) {
				const int u = bo[j];
				if (Catalog::ValidId(u) && Catalog::gMobile[u] && !Catalog::gBuilder[u] && (Catalog::gCostM[u] > gAeT3Floor))
					gAeT3Floor = Catalog::gCostM[u];
			}
		}
		AiLog(Factory::T() + "apex: foe-t3 t=" + ai.teamId + " seen=" + Catalog::Def(d).GetName()
			+ " floor=" + int(gAeT3Floor));
	}
	gAeT3M = m;
}
float FoeT3M()
{
	FoeT3Refresh();
	return (gAeT3Seen && (gAeT3Floor > gAeT3M)) ? gAeT3Floor : gAeT3M;
}
float OurT3M()
{
	float m = 0.f;
	const array<int>@ own = Market::OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (Catalog::ValidId(d) && Catalog::gMobile[d] && !Catalog::gBuilder[d] && (Market::TreeTier(d) >= 3))
			m += float(Market::gOwnCount[d]) * Catalog::gCostM[d];
	}
	return m;
}

void ArmyEstLog()
{
	if (ai.frame < gAeLogAt)
		return;
	gAeLogAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: armyest t=" + ai.teamId + " ours=" + int(OurArmyM()) + " own=" + int(OwnGroundArmyM())
		+ " allies=" + int(ai.GetAllyArmyM(false)) + " alliesAir=" + int(ai.GetAllyArmyM(true))
		+ " theirs=" + int(FoeArmyM()) + " theirBuilders=" + int(gFmBuilderM) + " theirT3=" + int(FoeT3M())
		+ " ourT3=" + int(OurT3M()) + " seats=" + int(TeamArmyCost()) + " armyCost=" + int(EnemyArmyCost()));
}

}  // namespace Military
