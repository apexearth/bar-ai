namespace Military {

// Not mobileThreat: threat and armyCost are different units (a
// threat-vs-metal comparison reads "we are ahead" almost always and any gate
// built on it never fires). GetEnemyCost returns enemyInfos[type].cost, a
// metal sum, directly comparable to armyCost (accumulated from GetCostM).
// Summed over the roles that actually fight.
// Mobile roles only. A building we saw once is still there; a raider is not.
// GetEnemyCostFresh counts only what was seen inside the manager's freshness
// window; the remainder is a ghost, weighted by apex_ghost_weight. At the
// default 1.0 this is arithmetically identical to the raw sum.
float EnemyCostOf(int role)
{
	const float raw = aiEnemyMgr.GetEnemyCost(role);
	float fresh = aiEnemyMgr.GetEnemyCostFresh(role);
	if (fresh > raw)
		fresh = raw;
	// Half-weighted: measured live the raw sum read the enemy army at 3x OURS
	// while apexearth watched us dominate -- the ghost share was ~2/3 of the
	// total and only ever ratchets up, so every posture gate (massing, attack
	// odds, the killing blow) leaned defensive off units that mostly no longer
	// existed. A mobile unit unseen for the whole freshness window is more
	// likely dead or elsewhere than waiting where we saw it.
	return fresh + (raw - fresh) * ai.GetTunable("apex_ghost_weight", TUNE_GHOST_WEIGHT);
}

float EnemyArmyCost()
{
	return EnemyCostOf(Unit::Role::ASSAULT.type)
	     + EnemyCostOf(Unit::Role::RAIDER.type)
	     + EnemyCostOf(Unit::Role::RIOT.type)
	     + EnemyCostOf(Unit::Role::SKIRM.type)
	     + EnemyCostOf(Unit::Role::ARTY.type)
	     + EnemyCostOf(Unit::Role::AH.type);
}

// THE SEEN ENEMY LIVES ON THE WATER, so land production cannot reach them --
// build ships, seaplanes or air instead. Two signals, because the role table
// cannot separate a destroyer from a tank (both read RAIDER/ASSAULT): a real
// sub fleet is unambiguous, and otherwise the enemy's centre of mass sitting
// beside water a shipyard could float on is the closest thing script can read
// (no terrain-elevation binding exists; enemyPos is the group centroid from
// the DLL's GetEnemyPos binding). Cached: FindBuildSiteNear is not free and
// this is asked per builder election.
bool gAfloat = false;
int gAfloatStreak = 0;
int gNextAfloatCheck = 0;
int gNextAfloatLog = 0;

bool EnemyAfloat()
{
	if (aiTerrainMgr.IsWaterAVoid())
		return false;
	if (ai.frame < gNextAfloatCheck)
		return gAfloat;
	gNextAfloatCheck = ai.frame + 10 * SECOND;
	// ...a fleet that outweighs what they field ASHORE: two subs beside a
	// massive ground army read "afloat" and handed every player on an 8v8
	// an air plant while the ground army walked in (his watch).
	const float subs = EnemyCostOf(Unit::Role::SUB.type);
	bool now = (subs >= ai.GetTunable("apex_afloat_sub_cost", TUNE_AFLOAT_SUB_COST))
			&& (subs >= EnemyArmyCost());
	if (!now && (aiTerrainMgr.GetLandPercent()
			<= ai.GetTunable("apex_afloat_land_pct", TUNE_AFLOAT_LAND_PCT))
		// A centroid means nothing before an enemy is actually SEEN --
		// GetEnemyPos returns a default with no groups registered, which read
		// as afloat at frame 18 of a land game (measured, Glacial Gap).
		&& (EnemyArmyCost() + EnemyCostOf(Unit::Role::STATIC.type)
			>= ai.GetTunable("apex_afloat_seen", TUNE_AFLOAT_SEEN)))
	{
		const AIFloat3 at = aiEnemyMgr.GetEnemyPos();
		if (OnMap(at)) {
			CCircuitDef@ sy = SideDef3(Factory::armsy, Factory::corsy, Factory::legsy);
			if (sy !is null) {
				// Tight: the enemy's mass must sit ON the water's edge, not a
				// screen from a lake -- 900 bought shipyards against a land
				// army camped by frozen lakes.
				const float near = ai.GetTunable("apex_afloat_near", TUNE_AFLOAT_NEAR);
				const AIFloat3 wet = ai.FindBuildSiteNear(sy, at, near);
				now = OnMap(wet) && (wet.distance2D(at) <= near);
			}
		}
	}
	// LATCH ON A STREAK, not one sample: the centroid jitters as sightings age,
	// and a flapping answer buys and abandons the reaction repeatedly.
	gAfloatStreak = now ? (gAfloatStreak + 1) : 0;
	const bool latched = gAfloatStreak
			>= int(ai.GetTunable("apex_afloat_streak", TUNE_AFLOAT_STREAK));
	if (latched != gAfloat || (latched && (ai.frame >= gNextAfloatLog))) {
		gNextAfloatLog = ai.frame + 120 * SECOND;
		AiLog(Factory::T() + "apex: enemy afloat=" + (latched ? "1" : "0")
			+ " subs=" + int(EnemyCostOf(Unit::Role::SUB.type))
			+ " land%=" + formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 0));
	}
	gAfloat = latched;
	return gAfloat;
}

// THE WHOLE ENEMY ARMY, INCLUDING THE PART THAT DECIDES GAMES.
//
// EnemyArmyCost above sums six roles and counts NEITHER heavy NOR super, so
// dozens of T3 unit defs -- armbanth, corjugg, corkorg, legeheatraymech and the
// rest -- are worth exactly zero to us. A declared push sets IsCommitted, so
// no unit may retreat, and committing while genuinely behind on real standing
// army (T3 invisible to the estimate) is an army that cannot disengage.
//
// Ten defs carry a counted role AND heavy and are double-counted here.
// Over-counting an enemy is the safe error; reading their Korgoths as absent is
// not. Only the two commit decisions read this -- LosingGround and the sizing
// helpers keep the narrower sum, because widening those moves reclaim, rez and
// the front-tower rule as well.
float EnemyFieldCost()
{
	return EnemyArmyCost()
	     + EnemyCostOf(Unit::Role::HEAVY.type)
	     + EnemyCostOf(Unit::Role::SUPER.type);
}

// Behind on the field: they field more army value than we do.
const float BEHIND_RATIO = 1.0f;

// ENEMIES HOLDING GROUND IN OUR OWN BASE, WITHOUT AN INVENTED THRESHOLD.
//
// Builder::BaseUnderAttack asks whether the enemy CENTROID is within 2200 of
// home, and in a team game the centroid of several enemies sits in the middle
// of the map forever, so it never fires except on a 1v1 massed push.
//
// Net influence is ally minus enemy at a point (CInfluenceMap::GetInfluenceAt
// returns influence - INFL_BASE), so its ZERO CROSSING is the question already
// asked in the right units: who owns this ground. No constant to guess at, and
// it is local to our base rather than an average over the whole map.
bool BaseContested()
{
	if (!Builder::gHomeSet)
		return false;
	return ai.GetNetInflAt(Builder::gHomePos) < 0.f;
}

bool LosingGround()
{
	return EnemyArmyCost() > aiMilitaryMgr.armyCost * BEHIND_RATIO;
}

float EnemyArmyFloor()
{
	// A refused query is "unknown", never "no enemies" -- reading a refusal as a
	// meaningful zero is what silently disabled slinging once already.
	const int teams = ai.GetEnemyTeamSize();
	return PORC_THREAT_PER_ENEMY * float((teams > 0) ? teams : 1);
}

// The team front, published by dev_team_income.lua at 78% of the way from our
// own centroid to the enemy's.
// FrontPos is gone with the gadget that fed it: it read ai_frontx_<team>, which
// only ever existed in BAR.sdd. FrontLinePos above answers the same question
// from the influence map, in any game.

}  // namespace Military
