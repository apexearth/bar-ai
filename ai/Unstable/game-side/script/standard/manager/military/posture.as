namespace Military {

// Set while the army is deliberately standing on our own defence line rather
// than at the front -- see the buildup hold in the lane selection below.
bool gBuildupHeld = false;
bool gBehindGuns = false;

// Still short of the T1 army the advanced plant is gated on. Factory::T2ArmyReady
// returns true once T2 exists, so this closes by itself.
bool ArmyBuildupHold()
{
	if (ai.GetTunable("apex_t2_army_hold", TUNE_T2_ARMY_HOLD) <= 0.f)
		return false;
	return false;   // the T2 army-buildup gate died with the leaf rush machinery
}

// The tower of ours that stands closest to the enemy: "the borders where all
// our turrets are placed", read from the defence ledger rather than guessed at.
bool gChokeHeld = false;

bool ForwardMostFence(AIFloat3& out at)
{
	float best = 0.f;
	bool have = false;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (!OnMap(gFencePos[i]))
			continue;
		const float f = ForwardFraction(gFencePos[i]);
		if (!have || (f > best)) {
			best = f;
			at = gFencePos[i];
			have = true;
		}
	}
	return have;
}


void UpdateRaidCaution()
{
	if (gRaidMinStock < 0.f)
		gRaidMinStock = aiMilitaryMgr.quota.raid.min;   // capture before overwriting
	// RAID_MIN_EARLY=45 was "hold them home" made permanent: ~2,600 metal of
	// raiders had to pool before ONE raid could leave pre-T2, so raiding was
	// effectively abolished -- census f4 near-zero all day while the enemy
	// raided us freely. apexearth 2026-08-20: "We can't let OUR constructors
	// be harassed and killed if we aren't going to harass and kill theirs...
	// tit for tat." A raid PACK is 4-6 raiders: base 8 power plus a fifth of
	// income, so packs grow with the economy instead of never forming.
	const float pack = ai.GetTunable("apex_raid_pack", TUNE_RAID_PACK)
			+ Eco::MInc() * ai.GetTunable("apex_raid_per_income", TUNE_RAID_PER_INCOME);
	const float want = Factory::gHaveT2 ? gRaidMinStock : pack;
	if (aiMilitaryMgr.quota.raid.min != want)
		aiMilitaryMgr.quota.raid.min = want;
}

// The engage margin each instance fights at: its personality, raised by the
// caution learned from where our metal is dying. The team push that used to
// override this (team army summed against the enemy we could SEE, entered at
// 1.6x and armed on all eight seats at 4.2 min of his 8v8) was removed at his
// call, 2026-09-27, with the killing blow before it.
void UpdateTeamPush()
{
	Persona::Update();
	ai.SetEngageBoost(Persona::EngageBias() * BleedCaution());
	// IsCommitted stops a unit leaving a fight at its 60% health threshold.
	// Committing every fight was tried and reverted: army K/D 0.38 vs stock's
	// 1.73 in one measured mirror.
	ai.SetCommitted(false);
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
float LANE_FORWARD() { return ai.GetTunable("apex_lane_forward", TUNE_LANE_FORWARD); }
int gNextLane = 0;
AIFloat3 gLanePinged;
// gLaneAt is declared in state.as: massing.as reads it and is included first.
// How far the front must actually move before the army is asked to move with
// it. Roughly two turret ranges: below this it is jitter, above it is a real
// shift of the line.
float LANE_STICKY() { return ai.GetTunable("apex_lane_sticky", TUNE_LANE_STICKY); }
bool gTradeHold = false;    // the anchor is pulled back while the trade is bad
int gNextLaneLostLog = 0;

// THE LIGHT T1 STOPS BEING A RAIDER AND BECOMES EYES, BUT ONLY IN T2 PHASE.
//
// Two halves. This one is willingness to die: behaviour.json states ONE retreat
// value for the whole game, so the config cannot express a posture that changes,
// and CCircuitDef::SetRetreat was bound for it. The original is kept and
// restored, so a pre-T2 Grunt is as cautious as it ever was. The other half is
// where they go and whether they go alone -- Military::AiMakeTask in hooks.as.
bool gRaiderSuicidal = false;

// Every combat def we have actually built, discovered as it passes AiMakeTask.
// Nothing in the bindings enumerates CCircuitDefs, and a hand-written per-faction
// list would be a fourth place to keep parity.
// unit.circuitDef is a const handle and SetRetreat is not const, so the id is
// round-tripped through ai.GetCircuitDef to get a writable one.
array<CCircuitDef@> gPostureDef;
array<float>        gPostureRetreat;  // parallel: the value config gave each def
array<bool>         gPostureFodder;   // parallel: registered via IsFodder
array<bool>         gPostureWasZero;  // parallel: last frame's zeroed state
uint gRetreatZeroed = 999;            // last no-retreat count, so the log fires on change

// The one predicate. Routing (hooks.as) and posture must never disagree about
// whether these units are spam right now, so both ask this.
bool SpamPhase()
{
	return Factory::gHaveT2 && (ai.GetTunable("apex_spam_suicidal", TUNE_SPAM_SUICIDAL) > 0.f);
}

void NotePostureDef(const CCircuitDef@ cdef, bool fodder)
{
	if (cdef is null)
		return;
	for (uint i = 0; i < gPostureDef.length(); ++i) {
		if (gPostureDef[i].id == cdef.id)
			return;
	}
	CCircuitDef@ d = ai.GetCircuitDef(cdef.id);
	if (d is null)
		return;
	gPostureDef.insertLast(d);
	// Scaled once at registration so the snapshot and the engine's own copy
	// agree: 59% of the metal we lose dies with retreat as its last action,
	// and a unit pulled out at 0.8 hp runs the whole way home being shot
	// while dealing nothing back.
	float r0 = d.GetRetreat();
	const float rs = ai.GetTunable("apex_retreat_scale", TUNE_RETREAT_SCALE);
	if ((rs > 0.f) && (rs != 1.f) && (r0 > 0.f)) {
		r0 *= rs;
		d.SetRetreat(r0);
	}
	gPostureRetreat.insertLast(r0);
	gPostureFodder.insertLast(fodder);
	gPostureWasZero.insertLast(false);
}

void NoteFodderDef(const CCircuitDef@ cdef)
{
	NotePostureDef(cdef, true);
}

// A cost-vs-income no-retreat bar measured WORSE: retreat is also
// disengage-and-repair, and units denied it press losing fights at half HP.
// Default 0 keeps this off; the tunable remains for experiments.
void ApplyRetreatPosture()
{
	const float secs = ai.GetTunable("apex_retreat_cost_secs", TUNE_RETREAT_COST_SECS);
	const float bar = (secs > 0.f) ? (Eco::MInc() * secs) : 0.f;
	uint zeroed = 0;
	for (uint i = 0; i < gPostureDef.length(); ++i) {
		// A charger is never pulled back (docs/24); the walk home is what kills it.
		const bool zero = (gPostureFodder[i] && gRaiderSuicidal)
			|| (gPostureDef[i].costM < bar) || IsChargerDef(gPostureDef[i]);
		// WRITE ON THE EDGE, NOT EVERY FRAME. gPostureRetreat is a snapshot
		// taken once at registration -- before any rezbot existed -- and this
		// runs every frame, so it overwrote RetreatRefresh's value on the frame
		// after each 15 s recompute. The heal bonus (worth up to +0.25 once
		// medics are fielded) therefore never reached the engine at all: a Pawn
		// that should pull out at 0.35 fought to 0.098. Restore the snapshot
		// only when leaving the zeroed state; otherwise leave the live value
		// alone, which is the whole point of recomputing it.
		if (zero) {
			gPostureDef[i].SetRetreat(0.f);
			++zeroed;
		} else if (gPostureWasZero[i]) {
			gPostureDef[i].SetRetreat(gPostureRetreat[i]);
		}
		gPostureWasZero[i] = zero;
	}
	if (zeroed != gRetreatZeroed) {
		gRetreatZeroed = zeroed;
		AiLog(Factory::T() + "apex: retreat-bar " + formatFloat(bar, "", 0, 0)
			+ " metal; no-retreat " + zeroed + "/" + gPostureDef.length() + " defs");
	}
}

void UpdateSpamPosture()
{
	const bool spam = SpamPhase();
	if (spam != gRaiderSuicidal) {
		gRaiderSuicidal = spam;
		string how = "raider";
		if (spam)
			how = "spotter";
		AiLog(Factory::T() + "apex: spam posture -> " + how);
	}
	ApplyRetreatPosture();
}

// Where the army stages right now; ZERO vector until the lane is first set.
AIFloat3 LanePos() { return gLaneAt; }

// ONE TEAM LANE (apexearth 2026-10-01: "The enemy puts all of their army
// together in the front line... we trickle in one squad at a time"). Each seat
// staged at the front point nearest its OWN base, so eight seats filled eight
// pools along one front. The leader -- the lowest allied seat that publishes a
// home, i.e. one of ours -- takes the lane from the team's centre and publishes
// it; every other seat stands its pools there. A stale lane falls back to the
// seat's own, as before.
int gNextTeamLaneLog = 0;
const string TV_LANEX = "lanex";
const string TV_LANEZ = "lanez";
const string TV_LANEF = "lanef";
int LaneLeader()
{
	array<Id>@ mates = ai.GetTeamIds();
	int lead = ai.teamId;
	if (mates is null)
		return lead;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if ((t < lead) && (ai.ReadTeamValue(t, "homex", -1.f) >= 0.f))
			lead = t;
	}
	return lead;
}
AIFloat3 TeamHomeRef()
{
	array<Id>@ mates = ai.GetTeamIds();
	float cx = 0.f, cz = 0.f;
	int n = 0;
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		const float x = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float z = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		cx += x;
		cz += z;
		++n;
	}
	if (n == 0)
		return Builder::gHomePos;
	return AIFloat3(cx / float(n), 0.f, cz / float(n));
}
bool TeamLaneRead(AIFloat3& out p)
{
	const int lead = LaneLeader();
	if (lead == ai.teamId)
		return false;
	const float f = ai.ReadTeamValue(lead, TV_LANEF, -1.f);
	if ((f < 0.f) || (ai.frame - int(f) > 30 * SECOND))
		return false;
	p = AIFloat3(ai.ReadTeamValue(lead, TV_LANEX, -1.f), 0.f, ai.ReadTeamValue(lead, TV_LANEZ, -1.f));
	return OnMap(p);
}
void TeamLanePublish()
{
	if ((LaneLeader() != ai.teamId) || !OnMap(gLaneAt))
		return;
	ai.PublishTeamValue(TV_LANEX, gLaneAt.x);
	ai.PublishTeamValue(TV_LANEZ, gLaneAt.z);
	ai.PublishTeamValue(TV_LANEF, float(ai.frame));
}

void UpdateLanePos()
{
	if (ai.frame < gNextLane)
		return;
	gNextLane = ai.frame + 10 * SECOND;
	if (!Builder::gHomeSet)
		return;
	AIFloat3 meet;
	if (PostAnchor(meet)) {
		gLaneAt = meet;
		aiSetupMgr.SetLanePos(meet);
		ai.SetFrontPos(meet);
		return;
	}
	AIFloat3 teamLane;
	if (TeamLaneRead(teamLane)) {
		if (ai.frame >= gNextTeamLaneLog) {
			gNextTeamLaneLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: team-lane t=" + ai.teamId + " lead=t" + LaneLeader()
				+ " at=" + int(teamLane.x) + "," + int(teamLane.z));
		}
		gLaneAt = teamLane;
		aiSetupMgr.SetLanePos(teamLane);
		ai.SetFrontPos(teamLane);
		return;
	}
	const AIFloat3 home = (LaneLeader() == ai.teamId) ? TeamHomeRef() : Builder::gHomePos;
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
		&& Front::FrontNear(home, lane)
		&& OnMap(lane)
		&& (ForwardFraction(lane) > 0.f);
	if (!onFront) {
		const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
		if (!OnMap(foe))
			return;
		const float f = ai.GetTunable("apex_lane_forward", TUNE_LANE_FORWARD);
		lane = home + (foe - home) * f;
	}
	// TRADING BADLY -> STAND DEFENSIVELY. When recent combat is a clearly losing
	// exchange (TradeRatio below the bar on real volume), the regroup anchor
	// pulls back over our own ground so the rebuilt army masses behind the
	// defences instead of feeding into the same front. The budget tilt
	// (LossArmyMult) is buying the army; this is where it stands. Releases by
	// itself as the ledger drains or the trade recovers.
	// A muster state was tried here (anchor waits at the line until the army
	// is half the enemy's per-player threat) and REVERTED: it collapsed
	// production and lost every game -- the
	// hold ceded the map, the ceded map shrank the army, and the bar became a
	// ratchet. Standing forward is what protects the income that pays for the
	// army; only ground the enemy actually holds (the net-influence walk
	// below) and a measured bad trade may pull the anchor back.
	if (TradeBad() && Builder::gHomeSet && !AllIn()) {
		const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
		if (OnMap(e)) {
			const float f = ai.GetTunable("apex_lane_defensive", TUNE_LANE_DEFENSIVE);
			AIFloat3 back = home + (e - home) * f;
			if (OnMap(back)
				&& (back.SqDistance2D(home) < lane.SqDistance2D(home)))
			{
				lane = back;
			}
		}
		if (!gTradeHold) {
			gTradeHold = true;
			AiLog(Factory::T() + "apex: trade " + formatFloat(TradeRatio(), "", 0, 2)
				+ " -- army stands defensively while it rebuilds");
		}
	} else if (gTradeHold) {
		gTradeHold = false;
		AiLog(Factory::T() + "apex: trade recovered -- army returns to the front");
	}
	// EARN THE PLANT AT HOME. apexearth 2026-08-19, on the T1-army floor never
	// being reached: "that's because our army kept getting itself killed. Try
	// keeping them in the base to defend, stop going outside the base... just
	// defend the borders where all our turrets are placed." While we are still
	// accumulating the T1 army that Factory::T2ArmyReady is waiting on, the
	// anchor stands on our own defence line, so the army rebuilds behind the
	// guns instead of trickling out to trade badly. Ends the moment the floor
	// is met or T2 exists; it does not touch what builders buy.
	if (ArmyBuildupHold() && Builder::gHomeSet) {
		AIFloat3 fence;
		if (ForwardMostFence(fence) && OnMap(fence)) {
			lane = fence;
		} else {
			const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
			if (OnMap(e)) {
				const float f = ai.GetTunable("apex_lane_defensive", TUNE_LANE_DEFENSIVE);
				AIFloat3 back = home + (e - home) * f;
				if (OnMap(back))
					lane = back;
			}
		}
		if (!gBuildupHeld) {
			gBuildupHeld = true;
			AiLog(Factory::T() + "apex: army holds the defence line while it"
				+ " builds toward the T2 floor");
		}
	} else if (gBuildupHeld) {
		gBuildupHeld = false;
		AiLog(Factory::T() + "apex: T2 army floor met -- the army moves out");
	}
	// THE ANCHOR MUST NOT STAND FORWARD OF OUR OWN GUNS.
	//
	// Measured 2026-08-19 (32m 4v4, matches/20260820-0343...): of 452 units that
	// died while RETREATING, 186 had last been elected to the DEFEND pool and
	// NONE to an attack -- and they died at a median forward fraction of 0.51,
	// midfield. The pool was massing in the open past our own defence line, so
	// units took damage with no cover, peeled off one at a time to retreat, and
	// were run down crossing ground we do not hold. That also dismantles the
	// group mid-fight, which is how a defence loses an engagement it should win.
	//
	// apexearth: "we don't create a front line, we don't hold our army at around
	// the front line... hunker down and make them bleed, control where that metal
	// falls on the playing field, so we can resurrect or reclaim." Behind the
	// guns, the enemy that follows a damaged unit walks into the turrets and the
	// wreckage falls on our ground.
	//
	// THE CHOKE IS THE LINE, guns or no guns yet. apexearth 2026-09-02,
	// watching the 4v4: "Ideally we hold a frontline at a narrower part of
	// the map... holding that line is best." The wall's line stands on the
	// map's choke (Market::ChokeTarget), 3,000-4,000 elmos from home, and a
	// tower there is refused by the danger gate while the enemy stands on it
	// -- so the army holds the passage first, on our side of it, and the guns
	// come up under the army. The choke therefore counts as our forward-most
	// fence below; a bad trade still pulls the anchor back as ever.
	// The line itself, not the raw choke: the wall's anchor is the choke
	// stepped back to the nearest safe ground, and that is where the guns
	// and the nanos stand (apexearth: "we can fight within range of our nano
	// turrets and then get healed while we fight"). The army holds the line;
	// as it wins ground the line steps up and the army with it.
	AIFloat3 chokeHold;
	// A choke BEHIND the front is our own wall: the whole team stood in its base
	// on it (his 8v8, 10-01, choke at the centre of our starts). The army holds
	// the narrow ground near the enemy, not its own doorstep.
	const bool chokeOk = !TradeBad() && Market::ChokeOnLane()
			&& Market::WallLineAnchor(chokeHold)
			&& (!onFront || (ForwardFraction(chokeHold) >= ForwardFraction(lane)));
	if (chokeOk) {
		lane = chokeHold;
		if (!gChokeHeld) {
			gChokeHeld = true;
			AiLog(Factory::T() + "apex: army holds the choke at "
				+ int(chokeHold.x) + "," + int(chokeHold.z));
		}
	} else if (gChokeHeld) {
		gChokeHeld = false;
	}
	if (ai.GetTunable("apex_lane_behind_guns", TUNE_LANE_BEHIND_GUNS) > 0.f) {
		AIFloat3 guns;
		bool haveGuns = ForwardMostFence(guns) && OnMap(guns);
		if (chokeOk && (!haveGuns || (ForwardFraction(chokeHold) > ForwardFraction(guns)))) {
			guns = chokeHold;
			haveGuns = true;
		}
		// Our own perimeter is never "forward of our guns": the front is
		// where our holdings end (docs/24), and the forward mexes are
		// holdings. Pulled back to the rim towers the army stood at 0.18
		// while every spot past 0.3 went to the enemy; the pull-back keeps
		// its meaning for the fallback lane, which is a guess at a front.
		if (haveGuns && !onFront && (ForwardFraction(lane) > ForwardFraction(guns)))
		{
			lane = guns;
			if (!gBehindGuns) {
				gBehindGuns = true;
				AiLog(Factory::T() + "apex: army anchor pulled back behind our"
					+ " own guns");
			}
		} else if (gBehindGuns) {
			gBehindGuns = false;
		}
	}
	// A LOST LANE MUST BE PERCEIVED AS LOST. The anchor used to stand at the
	// front edge regardless of who now holds that ground, so the pool's fill
	// stream walked one-by-one into enemy territory -- apexearth 2026-08-19:
	// "that defend streaming in the game looks like an attack. We aren't
	// perceiving how the forward lane is lost and we entirely need to be
	// pulling back." Sample net influence at the anchor and walk it toward
	// home until it stands on ground that is actually ours; it advances again
	// the same way as our influence retakes the lane.
	if (Builder::gHomeSet && OnMap(lane)) {
		AIFloat3 toHome = home - lane;
		const float len = sqrt(toHome.SqLength2D());
		if (len > 1.f) {
			toHome *= (1.f / len);
			const float step = ai.GetTunable("apex_lane_back_step", TUNE_LANE_BACK_STEP);
			int steps = 0;
			while ((steps < 10) && OnMap(lane)
				&& (float(steps) * step < len)
				&& (ai.GetNetInflAt(lane) < -0.01f))
			{
				lane += toHome * step;
				++steps;
			}
			if ((steps > 0) && (ai.frame >= gNextLaneLostLog)) {
				gNextLaneLostLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: forward lane is lost -- anchor pulled back "
					+ int(float(steps) * step) + " toward home");
			}
		}
	}
	if (!OnMap(lane))
		return;

	// COMMIT TO AN ANCHOR. A regroup point that moves every ten seconds is an
	// army permanently in transit, and averaging two candidates is exactly the
	// middle of the map. So a new anchor has to be a MEANINGFUL distance from
	// the one already in use before it is adopted -- small drift is ignored, a
	// genuine shift of the front is not.
	if (OnMap(gLaneAt)
		&& (lane.distance2D(gLaneAt) < ai.GetTunable("apex_lane_sticky", TUNE_LANE_STICKY)))
	{
		aiSetupMgr.SetLanePos(gLaneAt);   // keep standing where we already stand
		ai.SetFrontPos(gLaneAt);
		TeamLanePublish();
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
	TeamLanePublish();

	// WHY THE ARMY IS THERE, ON THE MAP: this is the anchor FillFrontPos picks
	// the regroup cluster from, so it is the single most useful thing to see.
	// OFF BY DEFAULT: this is a map marker human allies see. The harness turns it
	// back on with --modoption apex_ping=1; see apex_draw_front in frontline.as.
	if (ai.GetTunable("apex_ping", TUNE_PING) > 0.f) {
		if (OnMap(gLanePinged))
			AiDelPoint(gLanePinged);
		gLanePinged = gLaneAt;
		AiAddPoint(gLaneAt, "REGROUP " + (onFront ? "front" : "fallback")
			+ " mass=" + formatFloat(aiMilitaryMgr.quota.attack, "", 0, 0)
			+ (gTurtle ? " TURTLE" : ""));
	}
}

void UpdatePosture()
{
	// Before UpdateRushRole, which overwrites quota.attack on the lead. Captured
	// after it, this recorded the rusher's own suppressed value as the baseline,
	// so every later "restore" restored 400 (never attack).
	if (gAttackBase < 0.f)
		gAttackBase = aiMilitaryMgr.quota.attack;

	{ double _t = Perf::T0(); UpdateStance(); Perf::Add("post.stance", _t); }     // enemy stance: budget lean + scout demand
	{ double _t = Perf::T0(); AIFloat3 hs; Builder::HealStation(hs); Perf::Add("post.heal", _t); }   // medic station, published for retreats
	{ double _t = Perf::T0(); ReleaseHeldSupers(); Perf::Add("post.supers", _t); }   // held titans re-join the army when the wait ends
	{ double _t = Perf::T0(); UpdateApproach(); Perf::Add("post.approach", _t); }   // is a visible enemy group closing on our home?
	{ double _t = Perf::T0(); PublishDefence(); Perf::Add("post.pubdef", _t); }   // our front-tower count and income, for the team budget
	{ double _t = Perf::T0(); Brain::BudgetLog(); Perf::Add("post.budgetlog", _t); }
	{ double _t = Perf::T0(); IntelDiag(); Perf::Add("post.inteldiag", _t); }       // read-only: the enemy reading every gate above consumed
	PublishArmy();
	{ double _t = Perf::T0(); UpdateGifts(); Perf::Add("post.gifts", _t); }
	{ double _t = Perf::T0(); UpdateRaidCaution(); Perf::Add("post.raidcaution", _t); }
	{ double _t = Perf::T0(); UpdateMassing(); Perf::Add("post.massing", _t); }
	{ double _t = Perf::T0(); ReleaseHold(); Perf::Add("post.hold", _t); }
	// Last, so it is the final word on the quota and the posture.
	{ double _t = Perf::T0(); UpdateTeamPush(); Perf::Add("post.teampush", _t); }
	// A HOLD MUST NEVER STOP US DEFENDING OUR OWN GROUND.
	//
	// The hold is entered when our army shrinks -- precisely what being attacked
	// looks like -- so an enemy walking into our base drove the army that should
	// answer it into a posture whose whole effect is quota.attack = 240, i.e. no
	// group is ever large enough to engage. The hold is for the case it was
	// built for: stop feeding the army into THEIR base while losing the trade.
	// Enemies in ours is the opposite -- short supply lines, our defences
	// shooting, their army out of position -- and the one moment the trade is in
	// our favour.
	if (gTurtle && (ai.GetTunable("apex_hold_release", TUNE_HOLD_RELEASE) > 0.f)
		&& (BaseContested() || Builder::BaseUnderAttack())) {
		gTurtle = false;
		gPostureUntil = ai.frame;
		aiMilitaryMgr.quota.attack = gAttackBase;
		AiLog(Factory::T() + "apex: base under attack -- releasing the hold to defend");
	}
	// NO GROUP LEAVES WHILE WE ARE STILL EARNING THE PLANT. Same commit size the
	// hold posture uses, applied after UpdateMassing (which overwrites it) and
	// left off entirely once the base is actually being fought over -- defending
	// our own ground is the trade we want, and the release below says so.
	if (ArmyBuildupHold() && !BaseContested() && !BaseRaided()
		&& (aiMilitaryMgr.quota.attack < TURTLE_ATTACK))
	{
		aiMilitaryMgr.quota.attack = TURTLE_ATTACK;
	}
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

	if (!gTurtle) {
		// Shrinking army while the enemy still has a mobile force means we are
		// losing the trade, not merely between waves.
		// ... and it is not entered while they are in our base, for the same
		// reason: losses taken defending are not evidence that defending is a
		// losing trade.
		if ((army < prev * LOSING_RATIO) && (aiEnemyMgr.mobileThreat > 0.f)
			&& ((ai.GetTunable("apex_hold_release", TUNE_HOLD_RELEASE) <= 0.f)
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
		// UpdatePosture -- so every resume slams the commit size back to stock
		// and the next group leaves at stock size, one small group per cycle.
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
float FODDER_COST() { return ai.GetTunable("apex_fodder_cost", TUNE_FODDER_COST); }

}  // namespace Military
