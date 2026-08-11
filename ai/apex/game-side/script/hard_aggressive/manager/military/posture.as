namespace Military {

void UpdateRaidCaution()
{
	if (gRaidMinStock < 0.f)
		gRaidMinStock = aiMilitaryMgr.quota.raid.min;   // capture before overwriting
	const float want = Factory::gHaveT2 ? gRaidMinStock : RAID_MIN_EARLY;
	if (aiMilitaryMgr.quota.raid.min != want)
		aiMilitaryMgr.quota.raid.min = want;
}

//------------------------------------------------------------------------------
// Coordinated team push -- the "something extra" that punches through a line.
//
// apexearth: "usually you need something extra to punch through defenses and
// win a game... to defeat human players Apex AI must be unpredictable and
// dangerous", and the AIs should "cooperate with other Apex AIs to create
// united strategies".
//
// The failure this addresses is structural, not a tuning error. Every instance
// judges every fight ALONE: CAttackTask's engage test compares one squad's
// power against the local defenders. Four allied squads that would each win
// together therefore each refuse separately, and the team trickles. That is
// exactly what a human punishes, and it is what the live 10-AI game showed --
// 3,973 target groups refused across 492 decisions.
//
// So: the elector totals the ALLY TEAM's army, and when the team as a whole
// clearly outweighs the enemy it declares a push window on the shared
// blackboard. Every instance reads the same flag and, for that window, accepts
// worse local odds (SetEngageBoost) and lifts its attack cap. They commit
// together or not at all.
//
// Why this is dangerous to a human rather than merely aggressive: the army is
// visibly idle right up until it is not, and then several bases empty at once
// from different directions. The unpredictability is a side effect of the
// trigger being a STATE (relative army value) rather than a clock -- there is
// no timing to learn.
// TV_ARMY and TeamArmyCost() already exist above (UpdateKillingBlow publishes
// it every tick); reuse them rather than declaring a second copy.
const string TV_PUSH = "push";     // elector's answer: frame the window ends

// How far ahead the TEAM must be before committing everything. Deliberately
// higher than the per-squad engage margin: this spends the whole army at once,
// and being wrong costs the game rather than a squad.
const float PUSH_TEAM_RATIO = 1.6f;
// Long enough to cross the map and land, short enough that a push which has
// clearly failed is not renewed forever.
const int   PUSH_WINDOW  = 90 * SECOND;
const int   PUSH_COOLDOWN = 3 * MINUTE;
// Odds multiplier while pushing. 0.55 roughly halves the surplus the engage
// test demands -- squads still refuse a genuinely hopeless fight, but stop
// refusing the ones the rest of the team is about to join.
const float PUSH_BOOST   = 0.55f;
// Engage bias while an advanced plant is going up. apexearth, watching a 1v1:
// "when we are making a t2 lab we should ***not*** attack... im seeing we end up
// with no army left when t2 lab comes up." A T2 lab is the most expensive thing
// bought so far, and it is bought with metal that is NOT going into army -- so
// the moment we commit to it is exactly the moment we can least afford to trade
// the army we already have.
//
// Above 1 is cautious (PUSH_BOOST 0.55 is the aggressive direction). This raises
// only the bar to START an attack: CONTINUE_MARGIN governs fights already
// joined, and defence runs through CDefendTask, which does not consult this at
// all. So we still hold ground and still finish what we are in -- we just stop
// walking out to start new fights while the lab is unfinished.
const float T2_HOLD_BOOST = 1.60f;
const float PUSH_QUOTA   = 200.f;
// Nothing to push with. Below this the "ratio" is noise -- two scouts against
// one is 2.0 and means nothing.
const float PUSH_MIN_ARMY = 2500.f;

//------------------------------------------------------------------------------
// Personality.
//
// apexearth: "the AI should have different types of personalities... to defeat
// human players Apex AI must be unpredictable and dangerous."
//
// A human learns an AI by watching one game and assuming the next is the same.
// Ten identically-tuned Apex instances are one opponent repeated ten times, and
// perfectly predictable once solved. A per-instance trait, rolled at runtime and
// never announced, means the same lineup plays differently every match and the
// player cannot know which base in front of them is the cautious one.
//
// Expressed as a multiplier on the SAME engage-margin lever the team push uses,
// deliberately: it composes with everything already tuned instead of adding a
// second decision system that can disagree with the first. A personality shifts
// how readily this instance takes a fight; it does not invent new behaviour, so
// the blast radius is bounded and it cannot deadlock a role election.
//
// The team push OVERRIDES personality (see UpdateTeamPush): when the team commits
// everyone commits, including the cautious ones. Cooperation beats temperament,
// which is the point of having both.
const int PERSONA_ROLL_FRAME = 10 * SECOND;   // after Init, so teamId is settled
int   gPersona     = -1;
float gPersonaBias = 1.f;
string gPersonaName = "standard";

void RollPersona()
{
	if (gPersona >= 0)
		return;
	// AiRandom is seeded per process; teamId keeps instances from all landing on
	// the same roll in the same tick.
	gPersona = (AiRandom(0, 999) + ai.teamId * 7) % 4;
	if (gPersona == 0) {
		gPersonaBias = 0.82f;  // berserker: takes fights the others decline
		gPersonaName = "berserker";
	} else if (gPersona == 1) {
		gPersonaBias = 1.18f;  // cautious: hoards, techs, joins pushes only
		gPersonaName = "cautious";
	} else {
		gPersonaBias = 1.f;
		gPersonaName = "standard";
	}
	AiLog(Factory::T() + "apex: personality = " + gPersonaName
		+ " (engage x" + formatFloat(gPersonaBias, "", 0, 2) + ")");
}

int  gPushUntil   = 0;
int  gPushNextOk  = 0;
bool gPushLogged  = false;

void UpdateTeamPush()
{
	if (ai.frame >= PERSONA_ROLL_FRAME)
		RollPersona();

	// One writer, same pattern as the tech-lead and air-lead elections.
	if (Factory::ElectorTeamId() == ai.teamId) {
		const float teamArmy = TeamArmyCost();
		// EnemyArmyCost() only accumulates on EnemyEnterLOS, so an enemy we have
		// not looked at reads as ZERO -- and `army > 0 * 1.6` is true for any
		// army at all. Observed on the first run of this rule: every push logged
		// "vs enemy 0", i.e. it was firing on ignorance rather than on advantage.
		// EnemyArmyFloor() already exists for exactly this ("a refused query is
		// unknown, never no enemies"), so treat it as the floor.
		const float seen = EnemyArmyCost();
		const float floorFoe = EnemyArmyFloor();
		// Never push on IGNORANCE. EnemyArmyFloor is
		// PORC_THREAT_PER_ENEMY * teams -- 90 metal on a 6v6, less than one
		// scout -- so `teamArmy > foe * 1.6` was satisfied by any army at all
		// and the only real gate was PUSH_MIN_ARMY. An unscouted enemy is
		// assumed to MATCH us rather than to be absent, which makes the
		// superiority test unpassable until we have actually seen that we are
		// ahead.
		//
		// This matters more than an ordinary threshold because a declared push
		// both halves the engagement bar (PUSH_BOOST) and sets IsCommitted,
		// which stops every non-commander retreating at all -- so a push taken
		// on a bad estimate is not a worse trade, it is an army that cannot
		// disengage. apexearth: "For us to be willing to push like that, we have
		// to have superior army to the enemy's."
		//
		// The substitution applies ONLY to the unscouted case. Raising a SEEN
		// estimate up to teamArmy as well makes foe >= teamArmy unconditionally,
		// and the test below then reads `teamArmy > teamArmy * 1.6` -- false for
		// every army, so no push can ever be declared.
		const float foe = (seen > floorFoe) ? seen : teamArmy;
		const bool worth = (teamArmy >= PUSH_MIN_ARMY)
				&& (teamArmy > foe * PUSH_TEAM_RATIO);
		float until = ai.ReadTeamValue(ai.teamId, TV_PUSH, 0.f);
		if (worth && (ai.frame >= gPushNextOk) && (ai.frame > until)) {
			until = float(ai.frame + PUSH_WINDOW);
			gPushNextOk = ai.frame + PUSH_WINDOW + PUSH_COOLDOWN;
			AiLog(Factory::T() + "apex: TEAM PUSH -- army "
				+ formatFloat(teamArmy, "", 0, 0) + " vs enemy "
				+ formatFloat(foe, "", 0, 0));
			// Land and air together. Only the air lead has a force to release,
			// and it no-ops for everyone else.
			if (Air::ReleaseForPush())
				AiLog(Factory::T() + "apex: air joins the push");
		}
		ai.PublishTeamValue(TV_PUSH, until);
	}

	const int until = int(ai.ReadTeamValue(Factory::ElectorTeamId(), TV_PUSH, 0.f));
	const bool pushing = (ai.frame < until) && !Factory::EcoLeadActive();
	if (pushing) {
		ai.SetEngageBoost(PUSH_BOOST);
		// Commitment is the whole point. apexearth: "the real key there is
		// 'commitment'... if we back off we certainly won't succeed." Units in a
		// declared push stop retreating to heal; see CCircuitAI::IsCommitted.
		ai.SetCommitted(true);
		if (aiMilitaryMgr.quota.attack < PUSH_QUOTA)
			aiMilitaryMgr.quota.attack = PUSH_QUOTA;
		if (gTurtle) {
			gTurtle = false;
			gPostureUntil = ai.frame;
		}
		if (!gPushLogged) {
			gPushLogged = true;
			AiLog(Factory::T() + "apex: joining team push");
		}
	} else {
		// Personality is the resting state; the push above overrides it.
		// Teching overrides personality in the cautious direction only -- a
		// berserker at 0.82 still holds while its lab is unfinished, and a
		// cautious 1.18 is not made less careful by this.
		const float adv = Factory::OwnAdvProgress();
		const bool teching = (adv >= 0.f) && (adv < 1.f);
		float boost = gPersonaBias;
		if (teching && (T2_HOLD_BOOST > boost))
			boost = T2_HOLD_BOOST;
		ai.SetEngageBoost(boost);
		// Commitment is NOT only for declared pushes.
		//
		// IsCommitted is the one thing that stops a unit leaving a fight at its
		// own 60% health threshold, and it was wired exclusively to the team
		// push -- which is rare. So in ordinary fighting a squad dissolves one
		// unit at a time, each leaving as it drops below the bar, and the damage
		// already spent buys nothing. apexearth: "we will lose half of our army
		// to a turret that was almost killed, but then we ran away. And then the
		// turret never died... our fighting just looks really, really, really
		// bad."
		//
		// TRIED AND REVERTED, 2026-08-08: `SetCommitted(TeamArmyCost() >=
		// PUSH_MIN_ARMY)` -- commit outside a declared push too, so squads stop
		// dissolving one unit at a time at the 0.6 health bar. Measured on one
		// 18-minute 5v5 Cortex mirror: army K/D 0.38 against stock's 1.73, and
		// mobile losses 69,824 against 35,796. Blanket commitment means every
		// bad fight is fought to the death, which is worse than leaving them.
		//
		// The underlying complaint is still real and still unfixed -- "we will
		// lose half of our army to a turret that was almost killed, but then we
		// ran away." The answer is not "never retreat"; it is retreating as a
		// SQUAD rather than per unit, and finishing a target that is nearly
		// dead. Both live in the C++ fighter tasks.
		ai.SetCommitted(false);
		gPushLogged = false;
	}
}

//------------------------------------------------------------------------------
// Lateral corridor probe. Read-only: it issues no order, enqueues no task and
// spends no build power.
//
// GetAllyInflAt counts MOBILE units (see Front::Scan), so sampling it forward of
// our own ground measures where our army walks, and GetEnemyInflAt sampled
// forward of theirs measures where their army walks. Both are reported across
// the home->enemy axis, in units of the base separation: 0 is dead on the axis,
// 0.5 is half the base separation off it.
//------------------------------------------------------------------------------
const int PROBE_SAMPLE = 15 * SECOND;
const int PROBE_N      = 16;

int gNextLatProbe = 0;

void UpdateCorridorProbe()
{
	if (ai.frame < gNextLatProbe)
		return;
	gNextLatProbe = ai.frame + PROBE_SAMPLE;
	if (!Builder::gHomeSet)
		return;
	const AIFloat3 home = Builder::gHomePos;
	const AIFloat3 foe  = aiEnemyMgr.GetEnemyPos();
	const float ex = foe.x - home.x;
	const float ez = foe.z - home.z;
	const float sep = sqrt(ex * ex + ez * ez);
	if (sep < 1.f)
		return;
	const float ux = ex / sep;
	const float uz = ez / sep;

	float aw = 0.f, aAbs = 0.f, aSig = 0.f;
	float fw = 0.f, fAbs = 0.f, fSig = 0.f;
	for (int i = 0; i < PROBE_N; ++i) {
		for (int j = 0; j < PROBE_N; ++j) {
			AIFloat3 p;
			p.x = float(AiTerrainWidth())  * (float(i) + .5f) / float(PROBE_N);
			p.z = float(AiTerrainHeight()) * (float(j) + .5f) / float(PROBE_N);
			if (!ai.IsPosOnMap(p))
				continue;
			const float dx = p.x - home.x;
			const float dz = p.z - home.z;
			const float along = (dx * ux + dz * uz) / sep;
			const float lat = (dx * uz - dz * ux) / sep;
			const float mag = (lat < 0.f) ? -lat : lat;
			if ((along > 0.40f) && (along < 1.10f)) {
				const float a = ai.GetAllyInflAt(p);
				aw += a; aAbs += a * mag; aSig += a * lat;
			}
			if ((along > -0.10f) && (along < 0.60f)) {
				const float f = ai.GetEnemyInflAt(p);
				fw += f; fAbs += f * mag; fSig += f * lat;
			}
		}
	}
	if ((aw <= 0.f) && (fw <= 0.f))
		return;
	AiLog(Factory::T() + "apexlat: ours |lat|="
		+ formatFloat((aw > 0.f) ? aAbs / aw : -1.f, "", 0, 2)
		+ " lat=" + formatFloat((aw > 0.f) ? aSig / aw : 0.f, "", 0, 2)
		+ " w=" + formatFloat(aw, "", 0, 0)
		+ " | theirs |lat|=" + formatFloat((fw > 0.f) ? fAbs / fw : -1.f, "", 0, 2)
		+ " lat=" + formatFloat((fw > 0.f) ? fSig / fw : 0.f, "", 0, 2)
		+ " w=" + formatFloat(fw, "", 0, 0));
}

void UpdatePosture()
{
	// Before UpdateRushRole, which overwrites quota.attack on the lead. Captured
	// after it, this recorded the rusher's own suppressed value as the baseline,
	// so every later "restore" restored 400 (never attack).
	if (gAttackBase < 0.f)
		gAttackBase = aiMilitaryMgr.quota.attack;

	PublishDefence();   // our front-tower count and income, for the team budget
	Brain::BudgetLog();
	UpdateKillingBlow();
	UpdateRaidCaution();
	UpdateBaseDefence();
	UpdateSling();
	UpdateRushDefence();
	UpdateMassing();
	UpdateRushRole();
	UpdateEcoRole();
	UpdateEcoAid();
	// Last, so it is the final word on the quota and the posture.
	UpdateTeamPush();
	// After massing and both role rules, so it is the last word on the quota.
	// Not for the eco lead: it holds almost no army by design, and sending that
	// at a base is throwing it away rather than ending anything.
	if (gKilling && !Factory::EcoLeadActive()) {
		aiMilitaryMgr.quota.attack = ai.GetTunable("apex_kill_quota", KILL_QUOTA);
		if (gTurtle) {
			gTurtle = false;
			gPostureUntil = ai.frame;
			AiLog(Factory::T() + "apex: killing blow releases the hold");
		}
	}
	// A HOLD MUST NEVER STOP US DEFENDING OUR OWN GROUND.
	//
	// The hold is entered when our army shrinks -- which is precisely what being
	// attacked looks like. So an enemy army walking into a base drove the army
	// that should answer it into a 45-second-to-6-minute posture whose whole
	// effect is quota.attack = 240, i.e. no group is ever large enough to engage.
	// apexearth, watching: "When our base is under attack, we have armies from our
	// allies running away instead of helping. Like, we totally had an opportunity
	// to wipe out the enemy army, but instead we just ran away."
	//
	// The hold is for the case it was built for: stop feeding the army into THEIR
	// base while losing the trade. Enemies in ours is the opposite situation --
	// short supply lines, our defences shooting, their army out of position -- and
	// it is the one moment the trade is in our favour. Released the same way the
	// killing blow releases it.
	if (gTurtle && (ai.GetTunable("apex_hold_release", 1.f) > 0.f)
		&& (BaseContested() || Builder::BaseUnderAttack())) {
		gTurtle = false;
		gPostureUntil = ai.frame;
		aiMilitaryMgr.quota.attack = gAttackBase;
		AiLog(Factory::T() + "apex: base under attack -- releasing the hold to defend");
	}
	UpdateFrontGun();
	UpdateAirThreat();
	UpdateCorridorProbe();
	Commander::UpdateCaution();
	// DISABLED. Exit-code audit: aborts (exit -1003) jumped from 0-2 per 20-game
	// run to 14-17 the moment this landed, and stayed there. The engine is dying,
	// not stalemating -- which means the "3-1, commanders solved" reading was
	// drawn from the handful of games that survived, and the 82% I reported as
	// mutual turtling was 82% aborted. Either CmdMoveTo issued outside a task
	// context or GetEnemyCostAt's GetEnemyUnitsIn walk is unsafe here.
	// Builder::UpdateCommanderSafety();
	if (ai.frame < gNextSample)
		return;
	gNextSample = ai.frame + POSTURE_SAMPLE;

	const float army = aiMilitaryMgr.armyCost;
	const float prev = gArmyThen;
	gArmyThen = army;

	if ((prev <= 0.f) || (ai.frame < gPostureUntil) || (ai.frame < TURTLE_EARLIEST))
		return;

	if (gKilling)
		return;   // committed: a dip mid-push is not a reason to stop pushing

	if (!gTurtle) {
		// Shrinking army while the enemy still has a mobile force means we are
		// losing the trade, not merely between waves.
		// ... and it is not entered while they are in our base, for the same
		// reason: losses taken defending are not evidence that defending is a
		// losing trade.
		if ((army < prev * LOSING_RATIO) && (aiEnemyMgr.mobileThreat > 0.f)
			&& ((ai.GetTunable("apex_hold_release", 1.f) <= 0.f)
				|| (!BaseContested() && !Builder::BaseUnderAttack())))
		{
			gTurtle = true;
			++gTurtleCount;
			gArmyAtHold = prev;          // strength to rebuild back to
			gTurtleStarted = ai.frame;
			gPostureUntil = ai.frame + TURTLE_MIN_HOLD;
			aiMilitaryMgr.quota.attack = TURTLE_ATTACK;
			AiLog(Factory::T() + "apexturtle: HOLD #" + gTurtleCount + " frame=" + ai.frame
				+ " army " + prev + " -> " + army);
		}
	} else if ((army >= gArmyAtHold * RECOVER_OF_PEAK)
			|| (ai.frame - gTurtleStarted > TURTLE_MAX_HOLD)) {
		gTurtle = false;
		gPostureUntil = ai.frame + TURTLE_MIN_HOLD;
		// NOT gAttackBase. That is the stock 15, captured before anything
		// touched it, and the turtle block runs AFTER UpdateMassing in
		// UpdatePosture -- so every resume slammed the commit size back to
		// stock and the next group left at stock size. Measured 15 hold/resume
		// cycles in one game, i.e. fifteen small groups walking out.
		aiMilitaryMgr.quota.attack = MassWant();
		AiLog(Factory::T() + "apexturtle: RESUME frame=" + ai.frame + " army=" + army
			+ " (held from " + gArmyAtHold + ")");
	}
}

//------------------------------------------------------------------------------
// Why raising quota.attack never produced a mass.
//
// A unit that should mass is parked in a DEFEND task that promotes to ATTACK.
// CDefendTask::Update promotes on
//     (attackPower >= maxPower) || !GetTasks(check).empty()
// and DefaultMakeTask builds that task with check == ATTACK. So the moment one
// attack task exists anywhere, every DEFEND task hands its units over on its
// next tick holding one unit or twenty -- the quota is bypassed by the second
// clause, and no value of it can close the gap. That is the trickle.
//
// TaskF::Defend's three-argument form lets us choose `check`. MELEE is a
// declared FightType that nothing in CircuitAI ever enqueues, so GetTasks(MELEE)
// is permanently empty and promotion is left with only the mass test.
//
// The power passed here is superseded within 5s: UpdateDefenceTasks rewrites
// maxPower to max(minAttackers, PreMaxGroupThreat) for every DEFEND task that
// promotes to ATTACK, which is the value DefaultMakeTask would have used.
//------------------------------------------------------------------------------

// Fodder is exempt. apexearth: "we don't care about grouping these up ... they
// are fodder." Holding a 21-metal Tick back to build a mass buys nothing; its
// job is vision and pulled fire, and both only happen forward. Cost AND role,
// so a cheap AA or bomber is not swept in: the units meant here are Tick
// (armflea 21), Rascal (corfav 26), Wheelie (legscout 25), Rover (armfav 31),
// Grunt (corak 42) and Pawn (armpw 54).
const float FODDER_COST = 100.f;

}  // namespace Military
