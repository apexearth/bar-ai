namespace Market {

// THE ARMY-MIX HEADS (his 10-10: "how much of each type we make is controlled
// somehow by the NN so we get a safe smooth transition"), each a continuous head
// on a 30 s clock, 1x = the rule.
// tmix: the share of the army gap a lower-tier ground line keeps beyond what the
//   better lines measurably deliver (production.as yield). 0 = every unit past
//   cover waits for the better line; 1 = the lower line fills what it does not deliver.
// aa: the air our AA is sized against, static (StaticAAAirM) and mobile (RoleTarget).
const string NNTM_OWN = "minute,inc,armyV,armyT,foeArmy,topTier,lowBP,topBP,lowGot,topGot,topRingN,topNanoDue,lag";
const float TM_LO = 0.f, TM_HI = 6.f;
const string NNAD_OWN = "minute,inc,airSeen,airAvg,airFresh,aaStatic,aaMobile,fighters,airLoss,foeArmy,flakFloor";
const float AD_LO = 0.f, AD_HI = 8.f;
float gTierMixMul = 1.f;
float gAAMul = 1.f;
int gArmyNetAt = -1;
int gTierMixLogAt = 0;
int gAAWantLogAt = 0;

void TierMixDecide(const array<float>& in st)
{
	const int top = TopGroundPlantTier();
	float lowBP = 0.f, topBP = 0.f, lowGot = 0.f, topGot = 0.f;
	CCircuitUnit@ topFac = null;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null) || AirPlant(int(f.circuitDef.id)))
			continue;
		const float bp = Brain::LineBuildPower(f);
		const float got = Brain::LineOutMps(f.id);
		if (PlantTier(int(f.circuitDef.id)) >= top) {
			topBP += bp;
			topGot += got;
			if (topFac is null)
				@topFac = f;
		} else {
			lowBP += bp;
			lowGot += got;
		}
	}
	float ringN = 0.f;
	int due = 0;
	if (topFac !is null) {
		const int nd = NanoDefOf(null);
		const float nbp = Catalog::ValidId(nd) ? Catalog::gBuildPower[nd] : 0.f;
		if (nbp > 0.f) {
			ringN = RingBPAt(topFac.GetPos(ai.frame)) / nbp;
			due = NanosDueFor(int(topFac.circuitDef.id), nd);
		}
	}
	array<float> f;
	f.insertLast(float(ai.frame) / 1800.f);
	f.insertLast(Eco::MInc());
	f.insertLast(ArmyValue());
	f.insertLast(ArmyTarget());
	f.insertLast(Military::EnemyArmyCost());
	f.insertLast(float(top));
	f.insertLast(lowBP);
	f.insertLast(topBP);
	f.insertLast(lowGot);
	f.insertLast(topGot);
	f.insertLast(ringN);
	f.insertLast(float(due));
	f.insertLast(Perf::LagSeverity());
	gTierMixMul = NnValDecide("tmix", NNTM_OWN, TM_LO, TM_HI, 1.f, NNTM_ON, NNTM_STATE, NNTM_S, NNTM_O, NNTM_H,
		NNTM_XM, NNTM_XS, NNTM_W1, NNTM_B1, NNTM_W2, NNTM_B2, NNTM_WO, NNTM_BO, NNTM_TRUST, NNTM_LO, NNTM_HI, st, f);
}

void AADecide(const array<float>& in st)
{
	const int aaRole = int(Unit::Role::AA.type);
	array<float> f;
	f.insertLast(float(ai.frame) / 1800.f);
	f.insertLast(Eco::MInc());
	f.insertLast(Military::AirSeenEver());
	f.insertLast(Military::AirThreatSeen());
	f.insertLast(aiEnemyMgr.GetEnemyCostFresh(RT::AIR));
	f.insertLast(StaticAAHaveM());
	f.insertLast(RoleValue(aaRole));
	f.insertLast(Air::FighterMetalHeld());
	f.insertLast(Military::AirLossRate());
	f.insertLast(Military::EnemyArmyCost());
	f.insertLast(float(Military::FlakFloorN()));
	gAAMul = NnValDecide("aa", NNAD_OWN, AD_LO, AD_HI, 1.f, NNAD_ON, NNAD_STATE, NNAD_S, NNAD_O, NNAD_H,
		NNAD_XM, NNAD_XS, NNAD_W1, NNAD_B1, NNAD_W2, NNAD_B2, NNAD_WO, NNAD_BO, NNAD_TRUST, NNAD_LO, NNAD_HI, st, f);
}

void AAWantLog()
{
	if (ai.frame < gAAWantLogAt)
		return;
	gAAWantLogAt = ai.frame + 60 * SECOND;
	const int aaRole = int(Unit::Role::AA.type);
	const float statAir = StaticAAAirM();
	AiLog(Factory::T() + "apex: aa-want t=" + ai.teamId
		+ " seen=" + int(Military::AirSeenEver()) + " fresh=" + int(aiEnemyMgr.GetEnemyCostFresh(RT::AIR))
		+ " airLoss=" + NnF(Military::AirLossRate(), 2)
		+ " static=" + int(StaticAAHaveM()) + "/" + int(statAir * AACoverFrac())
		+ " flakFloor=" + Military::FlakFloorN()
		+ " mobile=" + int(RoleValue(aaRole)) + "/" + int(RoleTarget(aaRole, ArmyTarget()))
		+ " fighters=" + int(Air::FighterMetalHeld())
		+ " v=" + NnF(gAAMul, 2));
}

void ArmyNetDecide()
{
	if (!Builder::gHomeSet)
		return;
	AAWantLog();
	if (gArmyNetAt < 0)
		gArmyNetAt = 15 * SECOND + (ai.teamId % 15) * SECOND;
	if (ai.frame < gArmyNetAt)
		return;
	gArmyNetAt = ai.frame + 30 * SECOND;
	array<float> st;
	NnState(null, st);
	AADecide(st);
	TierMixDecide(st);
}

}  // namespace Market
