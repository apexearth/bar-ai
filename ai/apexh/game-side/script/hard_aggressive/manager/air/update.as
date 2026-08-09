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
	if (gStrike || !Armed())
		return false;
	ResolveDefs();
	const int id = unit.circuitDef.id;
	return ((gBomber !is null) && (id == gBomber.id))
		|| ((gFighter !is null) && (id == gFighter.id))
		|| ((gBomber1 !is null) && (id == gBomber1.id))
		|| ((gFighter1 !is null) && (id == gFighter1.id));
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

// Release the strike because the LAND army is going in right now.
//
// apexearth: "sometimes a combination of an air bombing raid on that front-line
// at the time our land army is engaging there (like they're actually there, not
// 2000 elos away walking towards it) is a great combination of army and air. Our
// AI needs to have this advanced ability to coordinate at the right times."
//
// The assassin's own triggers are Massed() and AIR_DEADLINE -- both about the
// air force's internal state, neither aware of what the ground army is doing. A
// team push is the moment the ground army commits, so it is exactly the moment
// bombers are worth spending: the enemy's attention and its repair are already
// on the land assault.
//
// HalfMassed() rather than Massed(): a coordinated half-strike lands with the
// push, and a full one that lands two minutes later does not. Returns whether it
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

// Re-arm once the wave is spent.
//
// gStrike is set on Release and was NEVER reset. HoldsUnit returns false while
// it is set, so before the first strike new aircraft are held at base and massed
// -- and after it, every plane we build is released the moment it rolls out,
// alone, into the same defended airspace. apexearth: "we keep our air assassin
// role on 'attack' even once we've lost all our attack force.... so we just keep
// sending them in as we build."
//
// Massing is the entire point of the role, so once the force is gone the right
// state is the one we started in: hold and rebuild.
void ReArm()
{
	if (!gStrike)
		return;
	int have = 0;
	if (gBomber !is null) have += gBomber.count;
	if (gFighter !is null) have += gFighter.count;
	if (gBomber1 !is null) have += gBomber1.count;
	if (gFighter1 !is null) have += gFighter1.count;
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

	// Do not start an air force while the ground war is being lost badly.
	//
	// apexearth: "we should not do these air assassin strategies if we're losing
	// the ground war considerably." The assassin costs 7,000-9,000 metal of one
	// player's production and deliberately fields no ground army while it builds
	// -- which is affordable from a stable position and suicidal from a losing
	// one. A raid also only pays if there is still a game to win when it lands.
	//
	// GROUND_LOST_RATIO, not Military::LosingGround(): that fires at parity
	// (enemy > ours * 1.0), which is normal mid-game and would cancel the
	// strategy almost always. "Considerably" is the ask, so this wants a real
	// deficit. Checked only before COMMITTING -- a force already paid for is
	// better spent than abandoned, and Update()'s own abort path handles the
	// case where anti-air appears mid-build.
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

	// Why we are NOT armed, when we hold the role. Without this the only evidence
	// is silence: measured twice, the assassin was elected (63 and 81 metal/s)
	// and never armed, and nothing in the log said whether the blocker was the
	// clock, the enemy's anti-air, or an abort.
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
