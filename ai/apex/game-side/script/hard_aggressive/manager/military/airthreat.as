namespace Military {

int  gNextAirLog   = 0;
bool gAAResolved   = false;
CCircuitDef@ gFlak = null;   // the faction's flak turret
CCircuitDef@ gHeavy = null;  // its other heavy static AA

void ResolveHeavyAA()
{
	if (gAAResolved)
		return;
	gAAResolved = true;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		@gFlak = ai.GetCircuitDef("corflak");  @gHeavy = ai.GetCircuitDef("corerad");
	} else if (side == "legion") {
		// leglupara is Legion's counterpart to armcir/corerad but is also its
		// superweapon entry, and DiceBigGun only re-rolls when a big gun finishes:
		// capping a def it had already picked would deny Legion any superweapon.
		@gFlak = ai.GetCircuitDef("legflak");
	} else {
		@gFlak = ai.GetCircuitDef("armflak");  @gHeavy = ai.GetCircuitDef("armcir");
	}
}

// Deliberately wider than EnemyArmyCost(), which omits HEAVY: leaving enemy T3
// out of the denominator inflates the air share exactly in the late game.
float EnemyGroundCost()
{
	return EnemyArmyCost() + aiEnemyMgr.GetEnemyCost(RT::HEAVY);
}

int LiveCount(CCircuitDef@ def)
{
	return (def is null) ? 0 : def.count;
}

void CapHeavyAA(CCircuitDef@ def, int spare)
{
	if (def !is null)
		def.maxThisUnit = def.count + spare;
}

// How seriously to take their air, 0..1. One number, used by both levers.
float AirScale(float share)
{
	float s = share / AA_SHARE_REF;
	if (s > 1.f)
		s = 1.f;
	if (s < AA_SCALE_MIN)
		s = AA_SCALE_MIN;
	return s;
}

void UpdateAirThreat()
{
	ResolveHeavyAA();

	const float airRaw = aiEnemyMgr.GetEnemyCost(RT::AIR);
	const float soft = aiEnemyMgr.GetEnemyCost(Unit::Role::BUILDER.type)
	                 + aiEnemyMgr.GetEnemyCost(Unit::Role::SCOUT.type);
	float softAir = (airRaw < soft) ? airRaw : soft;
	if (softAir > SOFT_AIR_CAP)
		softAir = SOFT_AIR_CAP;
	float air = airRaw - softAir * (1.f - SOFT_AIR_WEIGHT);
	if (air < 0.f)
		air = 0.f;
	const float ground = EnemyGroundCost() * GROUND_UNSEEN;

	if (gAirAvg < 0.f) {
		gAirAvg = air;
		gGroundAvg = ground;
	} else {
		const float k = 1.f / AIR_AVG_SECONDS;
		gAirAvg += (air - gAirAvg) * k;
		gGroundAvg += (ground - gGroundAvg) * k;
	}

	const float total = gAirAvg + gGroundAvg;
	const float share = (total > 0.f) ? gAirAvg / total : 0.f;
	const bool worth = (gAirAvg >= AA_IGNORE);
	const float scale = worth ? AirScale(share) : 0.f;

	// factor is the divisor in RoleProbability's first gate: AA is built while
	// enemyAir * ratio >= aaCost * factor, so aaCost tops out at
	// ratio/factor * enemyAir. That gate, not maxPercent, is what binds while the
	// enemy's air is small -- and it counts their air constructors as air.
	// The mobile-AA lever does not exist. GetResponseInfo/SResponseInfo are not
	// registered on CMilitaryManager -- only DefaultMakeTask, Enqueue,
	// EnqueueRetreat, DefaultMakeDefence and GetGuardTaskNum are. response.json's
	// anti_air weighting is therefore unreachable from script and needs a binding
	// before it can be scaled. Static AA below is real.

	// count includes nanoframes, so a turret still building holds its own slot.
	int heavyWant = int(gAirAvg * scale / AA_HEAVY_PER);
	if (heavyWant > AA_HEAVY_MAX)
		heavyWant = AA_HEAVY_MAX;
	const int heavyHave = LiveCount(gFlak) + LiveCount(gHeavy);
	const int spare = (heavyWant > heavyHave) ? (heavyWant - heavyHave) : 0;
	CapHeavyAA(gFlak, spare);
	CapHeavyAA(gHeavy, spare);

	if (ai.frame >= gNextAirLog) {
		gNextAirLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apexaa: airRaw=" + formatFloat(airRaw, "", 0, 0)
			+ " air=" + formatFloat(gAirAvg, "", 0, 0)
			+ " ground=" + formatFloat(gGroundAvg, "", 0, 0)
			+ " share=" + formatFloat(share, "", 0, 3)
			+ " scale=" + formatFloat(scale, "", 0, 2)
			+ " heavy=" + heavyHave + "/" + heavyWant);
	}
}

}  // namespace Military
