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

void ArmyEstLog()
{
	if (ai.frame < gAeLogAt)
		return;
	gAeLogAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: armyest t=" + ai.teamId + " ours=" + int(OurArmyM()) + " own=" + int(OwnGroundArmyM())
		+ " allies=" + int(ai.GetAllyArmyM(false)) + " alliesAir=" + int(ai.GetAllyArmyM(true))
		+ " theirs=" + int(FoeArmyM()) + " theirBuilders=" + int(gFmBuilderM) + " seats=" + int(TeamArmyCost()) + " armyCost=" + int(EnemyArmyCost()));
}

}  // namespace Military
