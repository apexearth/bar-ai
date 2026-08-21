namespace Air {

// Called from Military::AiMakeTask. True means "give this unit no task at all".
//
// There is no way to LAND an aircraft from AngelScript: CmdFindPad and CmdWait
// exist in C++ but only CmdMoveTo is registered, so the strongest available form
// of hiding is a unit with no orders, which hovers where it was built. That is
// weaker than the strategy asks for -- these planes are visible to anything that
// scouts our base -- but it does keep them off the map until the strike.
bool HoldsUnit(CCircuitUnit@ unit)
{
	if (gStrike)
		return false;
	ResolveDefs();
	const int id = unit.circuitDef.id;
	const bool strikeDef = ((gBomber !is null) && (id == gBomber.id))
		|| ((gFighter !is null) && (id == gFighter.id))
		|| ((gBomber1 !is null) && (id == gBomber1.id))
		|| ((gFighter1 !is null) && (id == gFighter1.id));
	if (!strikeDef)
		return false;
	// The air lead follows the assassin's own discipline (Armed covers the
	// abort and timing gates). EVERYONE ELSE holds too: a released fighter or
	// bomber lands in stock tasks that wander it to the front line, where it
	// dies for nothing -- apexearth: "they primarily only fly overhead of our
	// bases... A bomber is not supposed to attack armies... they should mass
	// up and then bomb enemies behind the lines." Held aircraft hover at the
	// plant, which is home; the wave release lives in Update().
	if (IsAirLead())
		return Armed();
	return ai.GetTunable("apex_air_home_wave", TUNE_AIR_HOME_WAVE) > 0.f;
}

// THE TEAM INTERCEPTOR POOL. Each player publishes the enemy AIR value over
// its own home; any player holding fighters (and not mid-strike) flies them to
// the worst-hit ally, re-issuing the move every few seconds so the stock task
// cannot recall them while the raid lasts. Fighters auto-engage whatever air
// they find there; when the ally's published value clears, the re-issue stops
// and stock tasks drift them home. No cap: response scales with what we hold.
void Intercept()
{
	if (Builder::gHomeSet && (ai.frame >= gNextRaidPub)) {
		gNextRaidPub = ai.frame + 2 * SECOND;
		ai.PublishTeamValue(TV_AIRRAID, ai.GetEnemyAirCostNear(Builder::gHomePos,
				ai.GetTunable("apex_intercept_r", TUNE_INTERCEPT_R)));
		ai.PublishTeamValue(TV_HOMEX, Builder::gHomePos.x);
		ai.PublishTeamValue(TV_HOMEZ, Builder::gHomePos.z);
	}
	if (gStrike || (ai.frame < gNextInterceptCmd))
		return;
	if (Fighters() < int(ai.GetTunable("apex_intercept_min_fighters", TUNE_INTERCEPT_MIN_FIGHTERS)))
		return;
	// Cached: team composition never changes mid-game, and calling
	// GetTeamIds thirty times a second is what exposed the binding's
	// cross-engine bug in the first place.
	if (gMatesCache is null)
		@gMatesCache = ai.GetTeamIds();
	array<Id>@ mates = gMatesCache;
	if (mates is null)
		return;
	const float bar = ai.GetTunable("apex_intercept_min", TUNE_INTERCEPT_MIN);
	int worst = -1;
	float worstRaid = bar;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;   // our own base already releases via defendHome
		const float raid = ai.ReadTeamValue(t, TV_AIRRAID, 0.f);
		if (raid > worstRaid) {
			worstRaid = raid;
			worst = t;
		}
	}
	if (worst < 0) {
		if (gInterceptTarget >= 0) {
			gInterceptTarget = -1;
			AiLog(Factory::T() + "apex: interceptors stand down");
		}
		return;
	}
	AIFloat3 to;
	to.x = ai.ReadTeamValue(worst, TV_HOMEX, -1.f);
	to.z = ai.ReadTeamValue(worst, TV_HOMEZ, -1.f);
	if ((to.x < 0.f) || !OnMap(to))
		return;
	gNextInterceptCmd = ai.frame + 4 * SECOND;
	int sent = 0;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ wings = ai.GetOwnUnitsOfDef(fd, to, 0.f);
		if (wings is null)
			continue;
		for (uint i = 0; i < wings.length(); ++i) {
			if (wings[i] !is null) {
				wings[i].CmdMoveTo(to);
				++sent;
			}
		}
	}
	if ((sent > 0) && (gInterceptTarget != worst)) {
		gInterceptTarget = worst;
		AiLog(Factory::T() + "apex: intercepting for ally t" + worst
			+ " raid=" + formatFloat(worstRaid, "", 0, 0)
			+ " fighters=" + sent);
	}
}

void Release(const string& in why)
{
	gStrike = true;
	Economy::isSwitchAssist = false;   // stop holding build power on the plant
	// ANTI_STAT makes CBombTask::FindTarget skip enemy army but keep static eco,
	// builders and commanders. CCircuitDef is owned per CCircuitAI instance, so
	// this and the retreat below change nothing for our allies.
	if (gBomber !is null) {
		gBomber.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomber.SetRetreat(0.f);
	}
	if (gBomber1 !is null) {
		gBomber1.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomber1.SetRetreat(0.f);
	}
	if (gFighter !is null)
		gFighter.SetRetreat(0.f);
	if (gFighter1 !is null)
		gFighter1.SetRetreat(0.f);
	AiLog(Factory::T() + "apex: air strike -- " + why
		+ " bombers=" + Bombers() + " fighters=" + Fighters()
		+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0));
}

// Release the strike because the LAND army is going in right now: the
// assassin's own triggers (Massed()/AIR_DEADLINE) know nothing about the ground
// army, but a team push is exactly when the enemy's attention and repair are on
// the land assault. HalfMassed() rather than Massed(): a coordinated half-strike
// lands with the push; a full one two minutes later does not. Returns whether it
// fired so the caller can log it.
bool ReleaseForPush()
{
	if (gStrike || !Armed() || !Committed())
		return false;
	if (!HalfMassed())
		return false;
	Release("team push -- hitting the line with the army");
	return true;
}

// How many aircraft still flying counts as "the strike force still exists".
const int STRIKE_SPENT_BELOW = 3;

// Re-arm once the wave is spent. HoldsUnit returns false while gStrike is set,
// so without this every plane built after the first strike is released alone
// into the same defended airspace instead of massing again.
void ReArm()
{
	if (!gStrike)
		return;
	// BOMBERS ONLY: the strike force IS the bombers; fighters loiter at home
	// and rarely die, so counting them kept `have` above the bar forever --
	// gStrike never re-armed and every bomber built after the first strike
	// released SOLO into defended airspace (apexearth, watching: "the few
	// bombers that I do see are just solo attacking").
	const int have = Bombers();
	if (have >= STRIKE_SPENT_BELOW)
		return;
	gStrike = false;
	AiLog(Factory::T() + "apex: air strike spent (" + have
		+ " left) -- holding and rebuilding instead of trickling");
}

void Update()
{
	ResolveDefs();
	ReArm();
	ai.PublishTeamValue(TV_AIRINC, aiEconomyMgr.metal.income);
	if (Factory::ElectorTeamId() == ai.teamId)
		RunElection();
	Intercept();

	// BOMBER DOCTRINE, every player, every tick: bombers never hunt armies.
	// ANTI_STAT keeps static economy, builders and commanders as targets; the
	// one exception is the enemy INSIDE our base (BaseContested, not merely
	// near) while their AA is thin -- apexearth: "a bomber's priority is
	// *only* an army during home base defense... its only if the enemy is
	// getting really close and danger is high. We will certainly lose a lot
	// of air if the enemy has flak trucks."
	{
		const bool defendHome = Military::BaseContested()
			&& (EnemyAACost() < ai.GetTunable("apex_bomb_defend_aa", TUNE_BOMB_DEFEND_AA));
		if (gBomber !is null) {
			if (defendHome) gBomber.DelAttribute(Unit::Attr::ANTI_STAT.type);
			else            gBomber.AddAttribute(Unit::Attr::ANTI_STAT.type);
		}
		if (gBomber1 !is null) {
			if (defendHome) gBomber1.DelAttribute(Unit::Attr::ANTI_STAT.type);
			else            gBomber1.AddAttribute(Unit::Attr::ANTI_STAT.type);
		}
		// A bombing run never turns around: the bomb is the sortie's whole
		// value and the flak is thickest on the way BACK OUT -- apexearth:
		// "Air bombing attacks should never retreat. You'll take 75% losses
		// and achieve nothing." Previously zeroed only at Release; a wave
		// that took hits inbound still peeled home with bombs unspent.
		if (gBomber !is null)  gBomber.SetRetreat(0.f);
		if (gBomber1 !is null) gBomber1.SetRetreat(0.f);
		// A held force does not hover through a base invasion: the same tight
		// condition that permits army targets also releases whatever is massed.
		if (defendHome && !gStrike && (Bombers() + Fighters() > 0))
			Release("defending home");
	}

	// A NON-LEAD player's wave: mass at home, then strike together. Half the
	// lead's scaled force is a real raid without hoarding a second air army.
	if (!IsAirLead() && !gStrike
		&& (ai.GetTunable("apex_air_home_wave", TUNE_AIR_HOME_WAVE) > 0.f)
		&& (Bombers() * 2 >= ScaledBombers()))
	{
		Release("home wave massed");
	}

	if (!IsAirLead() || gStrike || gAbort)
		return;

	if (!gAnnounced && Armed()) {
		gAnnounced = true;
		AiLog(Factory::T() + "apex: air assassin armed, enemyAA="
			+ formatFloat(EnemyAACost(), "", 0, 0)
			+ "/" + formatFloat(AIR_AA_CEILING, "", 0, 0));
	}

	// Constructors and nanos assist the plant while the force is being built.
	// Economy::AiUpdateEconomy recomputes isAssistRequired every update, so the
	// flag has to be asserted here rather than set once; it is dropped again in
	// Release() so the assist does not outlive the strike.
	if (Committed() && !Massed())
		Economy::isSwitchAssist = true;

	// Do not start an air force while the ground war is being lost badly: the
	// assassin fields no ground army while it builds, affordable from a stable
	// position and not from a losing one. GROUND_LOST_RATIO rather than
	// Military::LosingGround(), which fires at mere parity and would cancel the
	// strategy almost always -- this wants a real deficit. Checked only before
	// COMMITTING; a force already paid for is better spent than abandoned, and
	// Update()'s own abort path below handles anti-air appearing mid-build.
	const float ourGround = Military::TeamArmyCost();
	const float foeGround = Military::EnemyArmyCost();
	if (!Committed() && (foeGround > ourGround * GROUND_LOST_RATIO)) {
		if (ai.frame >= gNextLog) {
			gNextLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: air assassin holding off -- losing the ground war "
				+ formatFloat(ourGround, "", 0, 0) + " vs " + formatFloat(foeGround, "", 0, 0));
		}
		return;
	}

	if (!Committed() && Armed()) {
		CCircuitDef@ first = FactoryToBuild();
		if (first !is null) {
			gCommitFrame = ai.frame;
			AiLog(Factory::T() + "apex: air assassin committing, first plant "
				+ first.GetName());
		}
	}

	if (Massed()) {
		Release("massed");
	} else if (Committed() && (EnemyAACost() > AIR_AA_CEILING)) {
		if (HalfMassed()) {
			Release("enemy AA rising, going early");
		} else {
			gAbort = true;
			AiLog(Factory::T() + "apex: air assassin STANDING DOWN, enemyAA="
				+ formatFloat(EnemyAACost(), "", 0, 0)
				+ " with only " + Have(gBomber) + "/" + Have(gFighter) + " built");
		}
	} else if (Committed() && (ai.frame > gCommitFrame + AIR_DEADLINE) && HalfMassed()) {
		Release("deadline");
	}

	// Why we are NOT armed, when we hold the role -- without this the only
	// evidence is silence, indistinguishable from a dead build.
	if (!Armed() && (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: air lead NOT armed"
			+ " frame=" + ai.frame + "/" + AIR_FROM
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0)
			+ "/" + formatFloat(AIR_AA_CEILING, "", 0, 0)
			+ " abort=" + (gAbort ? "1" : "0"));
	}

	// Heartbeat. A gate that never fires and an input that is dead read the same
	// in a log that only prints on transitions.
	if (Armed() && (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		CCircuitDef@ want = FactoryToBuild();
		AiLog(Factory::T() + "apex: air " + Bombers() + "/" + ScaledBombers()
			+ " bombers, " + Fighters() + "/" + ScaledFighters() + " fighters"
			+ " plants=" + Have(gPlant1) + "," + Have(gPlant2)
			+ " cons=" + (HaveAirCon() ? "1" : "0")
			+ " want=" + ((want is null) ? "-" : want.GetName())
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0));
	}
}

}  // namespace Air
