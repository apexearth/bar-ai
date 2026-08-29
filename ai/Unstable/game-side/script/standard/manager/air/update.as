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
	ResolveDefs();
	const int id = unit.circuitDef.id;
	bool strikeDef = false;
	for (int i = 0; i < 6; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if ((d !is null) && (id == int(d.id))) {
			strikeDef = true;
			break;
		}
	}
	if (!strikeDef)
		return false;
	// The base itself is under attack: everything flies, and nothing about the
	// strike plan applies.
	if (gDefendHome)
		return false;
	// A STRIKE OWNS ONLY WHAT IT LAUNCHED WITH. A plane finished while the wave
	// is out keeps holding: joining a run already in progress arrives alone,
	// after the surprise, into the AA the wave woke up.
	if (gStrike)
		return !InWave(unit.id);
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
	if (ai.frame < gNextInterceptCmd)
		return;
	// The fighters HELD at home are the pool an ally can call on; the ones out
	// with a strike are not, and a raid on an ally must not recall them.
	if (HeldFighters() < int(ai.GetTunable("apex_intercept_min_fighters", TUNE_INTERCEPT_MIN_FIGHTERS)))
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
			if ((wings[i] is null) || InWave(wings[i].id))
				continue;
			wings[i].CmdMoveTo(to);
			++sent;
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
	BuildWave();
	NoteStrikeLaunched();
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
	if (gBomberH !is null) {
		gBomberH.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomberH.SetRetreat(0.f);
	}
	if (gBomberN !is null) {
		gBomberN.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomberN.SetRetreat(0.f);
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

// Re-arm once the run is over. Two ways it ends, and neither is a clock:
//
//  - the wave is spent, or
//  - what has been built while it was away is already the bigger force, so
//    there is nothing left for the remnant to add by staying out.
//
// Either way the survivors come home and mass with the pool, and the next
// Release throws the whole thing at once.
void ReArm()
{
	if (!gStrike)
		return;
	ScanWave();
	// BOMBERS ONLY: the strike force IS the bombers; fighters loiter and rarely
	// die, so counting them kept `have` above the bar forever (apexearth,
	// watching: "the few bombers that I do see are just solo attacking").
	const int have = gWaveBombers;
	const int held = HeldBombers();
	if ((have >= STRIKE_SPENT_BELOW)
		&& ((held < have) || (held < STRIKE_SPENT_BELOW)))
		return;
	RecallWave();
	gStrike = false;
	gWave.resize(0);
	gWaveBombers = 0;
	gWaveFighters = 0;
	AiLog(Factory::T() + "apex: air strike over -- " + have
		+ " of the wave home, " + held + " built since; massing them together"
		+ " for the next run");
}

// EYES OVER THEIR BASE (apexearth, watching carefully: "I don't see any
// scouts flying over their base"). Stock scout tasks chase unscouted MEX
// clusters and go quiet once the map is claimed -- the enemy BASE is never
// their destination, so the peep fleet stood at home while EnemyArmyCost
// read blind. Every apex_scout_over_s an idle cheap air scout is sent
// across the enemy position; at 39 metal a pass, dying there is a fair
// price for the army target reading something real. The move order is raw
// on purpose: when it completes (or the scout dies) the unit goes idle and
// stock scouting takes it back.
int gNextOverflight = 0;

void ScoutOverflight()
{
	const float per = ai.GetTunable("apex_scout_over_s", TUNE_SCOUT_OVER_S);
	if (per <= 0.f)
		return;
	if (ai.frame < gNextOverflight)
		return;
	gNextOverflight = ai.frame + int(per) * SECOND;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d]
			|| !Catalog::gFlyer[d] || Catalog::gBuilder[d]
			|| (Catalog::gPower[d] > 1.f)
			|| (Catalog::gCostM[d] > 100.f))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d),
				foe, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			if ((us[i] is null) || (us[i].CmdQueueSize() > 0))
				continue;
			// A jittered pass so consecutive flights cross different ground.
			const float ang = float((ai.frame / SECOND) % 8) * 0.785398f;
			AIFloat3 over = foe
					+ AIFloat3(cos(ang), 0.f, sin(ang)) * 500.f;
			if (!OnMap(over))
				over = foe;
			us[i].CmdMoveTo(over);
			AiLog("apex: overflight " + Catalog::Def(d).GetName()
				+ " #" + us[i].id + " -> " + int(over.x) + "," + int(over.z));
			return;
		}
	}
}

void Update()
{
	SettleStrike();
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
		gDefendHome = defendHome;
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
		// A held force does not hover through a base invasion -- gDefendHome
		// opens HoldsUnit directly, without pretending a strike is under way.
	}

	// A NON-LEAD player's wave: mass at home, then strike together. Half the
	// lead's scaled force is a real raid without hoarding a second air army.
	if (!IsAirLead() && !gStrike
		&& (ai.GetTunable("apex_air_home_wave", TUNE_AIR_HOME_WAVE) > 0.f)
		&& (Bombers() * 2 >= ScaledBombers()))
	{
		Release("home wave massed");
	}

	// A stand-down latched against an enemy that has since lost its field army
	// un-latches: the leftover flak of a beaten enemy must not veto the game's
	// only commander-killing weapon.
	if (gAbort && IsAirLead() && !gStrike && AADominated()) {
		gAbort = false;
		AiLog(Factory::T() + "apex: air assassin BACK ON -- enemy field army gone, "
			+ "their AA small next to ours");
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
	} else if (Committed() && !StrikeWorth() && !AADominated()) {
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
