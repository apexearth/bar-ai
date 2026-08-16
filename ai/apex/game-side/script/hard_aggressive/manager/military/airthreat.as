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

// The enemy air value safe to REACT to. GetEnemyCost(AIR) also counts air
// builders/scouts (behaviour.json roles, and CFactoryManager gives AIR to
// anything IsAbleToFly); gAirAvg discounts and time-averages that. Returns 0
// below AA_IGNORE rather than a small nonzero a normalising caller could round
// into overreaction.
float AirThreatSeen()
{
	if (gAirAvg < AA_IGNORE)
		return 0.f;
	return gAirAvg;
}

// Gate presence on this, not AirThreatSeen(): it is this tick's reading, not a
// 240s EMA of it, so a raid is answered as it develops rather than four minutes
// later. Still floored at AA_IGNORE so a single overflight is not a "threat".
float AirThreatNow()
{
	if (gAirRaw < AA_IGNORE)
		return 0.f;
	return gAirRaw;
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

// How many heavy static AA the observed air justifies. Factored out so the
// rule that actually ORDERS them (Builder::HeavyFlak) reads the same number
// UpdateAirThreat logs -- the two must never disagree.
int HeavyAAWant()
{
	const bool worth = (gAirAvg >= AA_IGNORE) || (gAirRaw >= AA_IGNORE);
	if (!worth)
		return 0;
	const float total = gAirAvg + gGroundAvg;
	const float share = (total > 0.f) ? gAirAvg / total : 0.f;
	const float heavyBasis = (gAirRaw > gAirAvg) ? gAirRaw : gAirAvg;
	return int(heavyBasis * AirScale(share) / AA_HEAVY_PER);
}

void UpdateAirThreat()
{
	ResolveHeavyAA();

	// Fresh, not GetEnemyCost: GetEnemyCost never forgets a unit once registered
	// (EnemyManager.h/.cpp), so one early air scout, seen once and since dead,
	// pinned this reading above AA_IGNORE for the rest of the match -- and once
	// AirThreatNow() (below) started gating presence off this same tick's value,
	// that stale sighting opened the AA gate permanently the instant it was seen,
	// not just eventually via the smoothed average. GetEnemyCostFresh only counts
	// what was seen within the last freshFrames (60s default), so the reading
	// actually falls back to 0 once the sighting goes stale.
	const float airRaw = aiEnemyMgr.GetEnemyCostFresh(RT::AIR);
	const float soft = aiEnemyMgr.GetEnemyCostFresh(Unit::Role::BUILDER.type)
	                 + aiEnemyMgr.GetEnemyCostFresh(Unit::Role::SCOUT.type);
	float softAir = (airRaw < soft) ? airRaw : soft;
	if (softAir > SOFT_AIR_CAP)
		softAir = SOFT_AIR_CAP;
	float air = airRaw - softAir * (1.f - SOFT_AIR_WEIGHT);
	if (air < 0.f)
		air = 0.f;
	const float ground = EnemyGroundCost() * GROUND_UNSEEN;
	gAirRaw = air;

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
	// Also worth it off the raw reading: gating purely on the smoothed average
	// left scale at 0 (and so heavyWant at 0) for however long the 240s EMA
	// took to catch up to an already-large airRaw.
	const bool worth = (gAirAvg >= AA_IGNORE) || (gAirRaw >= AA_IGNORE);
	const float scale = worth ? AirScale(share) : 0.f;

	// The mobile-AA lever does not exist: GetResponseInfo/SResponseInfo are not
	// registered on CMilitaryManager, so response.json's anti_air weighting is
	// unreachable from script. Static AA below is the only lever this can pull.

	// Sized off the larger of the smoothed and this-tick reading: gAirAvg alone
	// left heavyWant at 0 while airRaw climbed 150->4924 over ~10 minutes (see
	// gAirRaw comment, defenceline.as) because the 240s average had not caught
	// up. share/scale stay off the smoothed value so a single spike does not
	// swing the RATIO, only how much of the already-scaled demand counts.
	// count includes nanoframes, so a turret still building holds its own slot.
	int heavyWant = HeavyAAWant();
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
