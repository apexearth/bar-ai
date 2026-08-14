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
// Coordinated team push.
//
// The failure this addresses is structural: every instance judges every fight
// ALONE, since CAttackTask's engage test compares one squad's power against
// the local defenders. Four allied squads that would each win together
// therefore each refuse separately, and the team trickles (measured live:
// 3,973 target groups refused across 492 decisions).
//
// So: the elector totals the ALLY TEAM's army, and when the team as a whole
// clearly outweighs the enemy it declares a push window on the shared
// blackboard. Every instance reads the same flag and, for that window, accepts
// worse local odds (SetEngageBoost) and lifts its attack cap. They commit
// together or not at all -- the army is idle right up until it is not, and the
// trigger is a STATE (relative army value) rather than a clock, so there is no
// timing to learn.
//
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
// Engage bias while an advanced plant is going up: a T2 lab is bought with
// metal that is NOT going into army, so the moment we commit to it is exactly
// the moment we can least afford to trade the army we already have.
//
// Above 1 is cautious (PUSH_BOOST 0.55 is the aggressive direction). This
// raises only the bar to START an attack: CONTINUE_MARGIN governs fights
// already joined, and defence runs through CDefendTask, which does not
// consult this at all -- we still hold ground and finish what we are in, we
// just stop starting new fights while the lab is unfinished.
const float T2_HOLD_BOOST = 1.60f;
const float PUSH_QUOTA   = 200.f;
// Nothing to push with. Below this the "ratio" is noise -- two scouts against
// one is 2.0 and means nothing.
const float PUSH_MIN_ARMY = 2500.f;

//------------------------------------------------------------------------------
// Personality: a per-instance trait, rolled at runtime and never announced, so
// identically-tuned Apex instances do not all play as one predictable opponent.
//
// Expressed as a multiplier on the SAME engage-margin lever the team push uses,
// so it composes with everything already tuned instead of adding a second
// decision system that can disagree with the first; it shifts how readily an
// instance takes a fight rather than inventing new behaviour, bounding its
// blast radius.
//
// The team push OVERRIDES personality (see UpdateTeamPush): when the team
// commits, everyone commits, including the cautious ones.
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
		// EnemyArmyCost() only accumulates on EnemyEnterLOS, so an unscouted
		// enemy reads as ZERO and `army > 0 * 1.6` is true for any army at all --
		// a push fired on ignorance rather than advantage. EnemyArmyFloor() is
		// "a refused query is unknown, never no enemies", so it is used as the
		// floor for the unscouted case. This matters more than an ordinary
		// threshold: a declared push both halves the engagement bar (PUSH_BOOST)
		// and sets IsCommitted, which stops every non-commander retreating, so a
		// push on a bad estimate is an army that cannot disengage.
		//
		// The substitution applies ONLY to the unscouted case: raising a SEEN
		// estimate up to teamArmy as well would make foe >= teamArmy
		// unconditionally, and the test below would then always read false.
		const float seen = EnemyFieldCost();
		const float floorFoe = EnemyArmyFloor();
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
		// Units in a declared push stop retreating to heal; see
		// CCircuitAI::IsCommitted.
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
		// IsCommitted stops a unit leaving a fight at its 60% health threshold,
		// and is wired only to the team push (rare) -- so in ordinary fighting a
		// squad dissolves one unit at a time as each drops below the bar.
		// Committing outside a declared push was tried and reverted: it made
		// every bad fight fight to the death (army K/D 0.38 vs stock's 1.73 in
		// one measured mirror), which is worse than leaving. The real fix is
		// retreating as a SQUAD rather than per unit, and finishing a nearly-dead
		// target; both live in the C++ fighter tasks.
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

// THE ARMY HOLDS WHERE THE LANE IS.
//
// CMilitaryManager::FillFrontPos takes the metal cluster nearest lanePos and
// returns that cluster's defence points, so lanePos is the whole answer to where
// the army stands. Left alone it sits at the start position, which is the middle
// of the base. Pushed toward the enemy by a fraction of the way to the front, the
// nearest cluster becomes a forward one and the army holds the edge instead.
//
// Not a CmdMoveTo: issuing those outside a task context is what drove engine
// aborts from 0-2 to 14-17 per 20-game run (see the disabled block below). This
// moves the engine's own anchor and lets it do the moving.
const float LANE_FORWARD = 0.35f;   // fraction of the way from base to enemy
int gNextLane = 0;
AIFloat3 gLanePinged;
AIFloat3 gLaneAt;
// How far the front must actually move before the army is asked to move with
// it. Roughly two turret ranges: below this it is jitter, above it is a real
// shift of the line.
const float LANE_STICKY = 900.f;

// THE LIGHT T1 STOPS BEING A RAIDER AND BECOMES EYES, BUT ONLY IN T2 PHASE.
//
// Two halves. This one is willingness to die: behaviour.json states ONE retreat
// value for the whole game, so the config cannot express a posture that changes,
// and CCircuitDef::SetRetreat was bound for it. The original is kept and
// restored, so a pre-T2 Grunt is as cautious as it ever was. The other half is
// where they go and whether they go alone -- Military::AiMakeTask in hooks.as.
bool gRaiderSuicidal = false;

// Every fodder def we have actually built, discovered as it passes AiMakeTask.
// Nothing in the bindings enumerates CCircuitDefs, and a hand-written per-faction
// list would be a fourth place to keep parity; IsFodder is already the predicate
// that decides which units are spam, so the register follows it exactly.
// unit.circuitDef is a const handle and SetRetreat is not const, so the id is
// round-tripped through ai.GetCircuitDef to get a writable one.
array<CCircuitDef@> gFodderDef;
array<float>        gFodderRetreat;   // parallel: the value config gave each def

// The one predicate. Routing (hooks.as) and posture must never disagree about
// whether these units are spam right now, so both ask this.
bool SpamPhase()
{
	return Factory::gHaveT2 && (ai.GetTunable("apex_spam_suicidal", 1.f) > 0.f);
}

void NoteFodderDef(const CCircuitDef@ cdef)
{
	if (cdef is null)
		return;
	for (uint i = 0; i < gFodderDef.length(); ++i) {
		if (gFodderDef[i].id == cdef.id)
			return;
	}
	CCircuitDef@ d = ai.GetCircuitDef(cdef.id);
	if (d is null)
		return;
	gFodderDef.insertLast(d);
	gFodderRetreat.insertLast(d.GetRetreat());
	// A def first seen mid-phase still has to take the posture already in force.
	d.SetRetreat(gRaiderSuicidal ? 0.f : gFodderRetreat[gFodderRetreat.length() - 1]);
}

void UpdateSpamPosture()
{
	const bool spam = SpamPhase();
	if (spam == gRaiderSuicidal)
		return;
	gRaiderSuicidal = spam;
	string names = "";
	for (uint i = 0; i < gFodderDef.length(); ++i) {
		gFodderDef[i].SetRetreat(spam ? 0.f : gFodderRetreat[i]);
		if (i > 0)
			names += " ";
		names += gFodderDef[i].GetName();
	}
	string how = "raider";
	if (spam)
		how = "spotter";
	AiLog(Factory::T() + "apex: spam posture -> " + how + " [" + names + "]");
}

void UpdateLanePos()
{
	if (ai.frame < gNextLane)
		return;
	gNextLane = ai.frame + 10 * SECOND;
	if (!Builder::gHomeSet)
		return;
	// THE FRONT ITSELF, not a fraction of the way to it. FrontNear returns the
	// nearest perimeter point that is a FRONT edge, preferring ground we hold;
	// FillFrontPos then picks a cluster there whose influence is ours and which
	// is reachable, so safety is the predicate's job rather than a setback we
	// would have to guess at.
	//
	// Toward the enemy, or not at all: FrontNear has no direction test, so
	// before the enemy is located a bearing running off the map edge classified
	// the same as a real front, and the anchor flip-flopped between mid-map and
	// our own back edge. ForwardFraction is positive toward the enemy, so
	// requiring it rules out the rear perimeter, and IsFrontKnown keeps us on
	// the deterministic fallback until there is a real front to stand on.
	AIFloat3 lane;
	bool onFront = Front::IsFrontKnown()
		&& Front::FrontNear(Builder::gHomePos, lane)
		&& OnMap(lane)
		&& (ForwardFraction(lane) > 0.f);
	if (!onFront) {
		const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
		if (!OnMap(foe))
			return;
		const float f = ai.GetTunable("apex_lane_forward", LANE_FORWARD);
		lane = Builder::gHomePos + (foe - Builder::gHomePos) * f;
	}
	if (!OnMap(lane))
		return;

	// COMMIT TO AN ANCHOR. A regroup point that moves every ten seconds is an
	// army permanently in transit, and averaging two candidates is exactly the
	// middle of the map. So a new anchor has to be a MEANINGFUL distance from
	// the one already in use before it is adopted -- small drift is ignored, a
	// genuine shift of the front is not.
	if (OnMap(gLaneAt)
		&& (lane.distance2D(gLaneAt) < ai.GetTunable("apex_lane_sticky", LANE_STICKY)))
	{
		aiSetupMgr.SetLanePos(gLaneAt);   // keep standing where we already stand
		ai.SetFrontPos(gLaneAt);
		return;
	}
	gLaneAt = lane;
	aiSetupMgr.SetLanePos(lane);
	// frontPos, NOT just lanePos, is what moves the army. GetLanePos reaches only
	// GetDefenceStand, a dead branch of FillFrontPos, and a retreat rally -- no
	// attack or defend task reads it. GetGuardAnchor reads frontPos, and every
	// DEFEND task's position is rewritten from it each pass. The guards above were
	// therefore being applied to the anchor nothing consumed.
	ai.SetFrontPos(lane);

	// WHY THE ARMY IS THERE, ON THE MAP: this is the anchor FillFrontPos picks
	// the regroup cluster from, so it is the single most useful thing to see.
	// OFF BY DEFAULT: this is a map marker human allies see. The harness turns it
	// back on with --modoption apex_ping=1; see apex_draw_front in frontline.as.
	if (ai.GetTunable("apex_ping", 0.f) > 0.f) {
		if (OnMap(gLanePinged))
			AiDelPoint(gLanePinged);
		gLanePinged = gLaneAt;
		AiAddPoint(gLaneAt, "REGROUP " + (onFront ? "front" : "fallback")
			+ " mass=" + formatFloat(aiMilitaryMgr.quota.attack, "", 0, 0)
			+ (gTurtle ? " TURTLE" : "") + (gKilling ? " KILL" : ""));
	}
}

void UpdatePosture()
{
	// Before UpdateRushRole, which overwrites quota.attack on the lead. Captured
	// after it, this recorded the rusher's own suppressed value as the baseline,
	// so every later "restore" restored 400 (never attack).
	if (gAttackBase < 0.f)
		gAttackBase = aiMilitaryMgr.quota.attack;

	PublishDefence();   // our front-tower count and income, for the team budget
	LogAidState();      // read-only: what an ally-aid response would do
	Brain::BudgetLog();
	UpdateKillingBlow();
	UpdateRaidCaution();
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
	// The hold is entered when our army shrinks -- precisely what being attacked
	// looks like -- so an enemy walking into our base drove the army that should
	// answer it into a posture whose whole effect is quota.attack = 240, i.e. no
	// group is ever large enough to engage. The hold is for the case it was
	// built for: stop feeding the army into THEIR base while losing the trade.
	// Enemies in ours is the opposite -- short supply lines, our defences
	// shooting, their army out of position -- and the one moment the trade is in
	// our favour. Released the same way the killing blow releases it.
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
	// DISABLED: engine aborts (exit -1003) jumped sharply the moment this
	// landed. Either CmdMoveTo issued outside a task context or
	// GetEnemyCostAt's GetEnemyUnitsIn walk is unsafe here.
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

// Fodder is exempt from massing: holding a 21-metal Tick back to build a mass
// buys nothing, since its job is vision and pulled fire, both forward-only.
// Cost AND role, so a cheap AA or bomber is not swept in.
const float FODDER_COST = 100.f;

}  // namespace Military
