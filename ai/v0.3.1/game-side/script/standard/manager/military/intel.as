namespace Military {

// WHAT WE BELIEVE THE ENEMY HAS, sampled on a fixed clock.
//
// Every posture gate reads these numbers, and nothing recorded them: a hold or
// a push could only be explained by re-deriving the reading from the decision
// it produced. GetEnemyCost is the raw sum including units seen once and never
// again; GetEnemyCostFresh is only what was seen inside the freshness window.
// Both are logged because the gap between them IS the ghost share, and the
// ghost weight is what the gates actually consume (EnemyCostOf).
int gNextIntelLog = 0;
float gIntelRaw = 0.f;
float gIntelFresh = 0.f;

// Appends "name=fresh/raw" for one role and accumulates the totals. Silent for
// a role we have never seen, so the line stays short early.
string IntelRole(const string& in name, int role)
{
	const float raw = aiEnemyMgr.GetEnemyCost(role);
	float fresh = aiEnemyMgr.GetEnemyCostFresh(role);
	if (fresh > raw)
		fresh = raw;
	gIntelRaw += raw;
	gIntelFresh += fresh;
	if (raw <= 0.f)
		return "";
	return " " + name + "=" + formatFloat(fresh, "", 0, 0)
		+ "/" + formatFloat(raw, "", 0, 0);
}

void IntelDiag()
{
	if (ai.frame < gNextIntelLog)
		return;
	gNextIntelLog = ai.frame + 30 * SECOND;

	gIntelRaw = 0.f;
	gIntelFresh = 0.f;
	string per = "";
	per += IntelRole("raider",  Unit::Role::RAIDER.type);
	per += IntelRole("assault", Unit::Role::ASSAULT.type);
	per += IntelRole("riot",    Unit::Role::RIOT.type);
	per += IntelRole("skirm",   Unit::Role::SKIRM.type);
	per += IntelRole("arty",    Unit::Role::ARTY.type);
	per += IntelRole("ah",      Unit::Role::AH.type);
	per += IntelRole("air",     Unit::Role::AIR.type);
	per += IntelRole("bomber",  Unit::Role::BOMBER.type);
	per += IntelRole("aa",      Unit::Role::AA.type);
	per += IntelRole("sub",     Unit::Role::SUB.type);
	per += IntelRole("static",  Unit::Role::STATIC.type);
	per += IntelRole("heavy",   Unit::Role::HEAVY.type);
	per += IntelRole("super",   Unit::Role::SUPER.type);
	per += IntelRole("builder", Unit::Role::BUILDER.type);

	AiLog(Factory::T() + "apex: intel"
		+ " ours=" + formatFloat(OurArmyNow(), "", 0, 0)
		+ " army=" + formatFloat(EnemyArmyCost(), "", 0, 0)
		+ " massing=" + formatFloat(EnemyMassingThreat(), "", 0, 0)
		+ " mobile=" + formatFloat(FoeMobileMassing(), "", 0, 0)
		+ " peak=" + formatFloat(gSeenPeak, "", 0, 0)
		+ " groups=" + aiEnemyMgr.GetEnemyGroupCount()
		+ " fresh=" + formatFloat(gIntelFresh, "", 0, 0)
		+ " raw=" + formatFloat(gIntelRaw, "", 0, 0)
		+ " |" + per);
}

}  // namespace Military
