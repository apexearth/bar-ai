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
	if (Market::LiftHolds(unit))
		return true;
	if (IsLookDef(id) && (AtomicLookHolds(unit) || LookDispatch(unit)))
		return true;
	// A fighter on cover keeps its guard order; CoverWatch sends it home.
	if (Covering(unit.id))
		return true;
	if (FlightHolds(unit))
		return true;
	// A TORPEDO FLYER WITH NO FLOATING TARGET HAS NOTHING TO SHOOT ANYWHERE
	// ON THE MAP -- its weapons read zero surf and zero air threat -- yet
	// stock routing gave the ones we owned attack orders against land
	// armies, a flight into AA with nothing to fire (watched live, 118
	// lost). Held at home until enemy SUBS are actually seen -- the same
	// readable signal production prices them on; then stock naval targeting
	// may have them.
	// ...or SHIPS: a torpedo hits anything in the water, and on a water map
	// production bought them on the navy budget while this held them for want
	// of subs alone (none of 33 logged deaths was on a fighting task).
	if ((Catalog::gPower[id] > 1.f) && (Catalog::gSurfT[id] <= 0.01f)
		&& (Catalog::gAirT[id] <= 0.01f)
		&& (Market::EnemyWetCount() <= 0)
		&& (!Military::EnemyAfloat()
			|| (Military::EnemyCostOf(Unit::Role::SUB.type) <= 1.f)))
		return true;
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
	if (IsAtomicDef(id))
		return AtomicHold(unit);
	// The lead HOLDS, armed or not: this returned Armed(), so an unarmed lead
	// handed every plane to the stock attack as it left the pad -- 91 Thunders
	// built, 91 dead one at a time, no strike flown (apexearth 2026-09-11:
	// "build up bombers, and then eventually attack enemy eco in a large
	// mass"). EVERYONE ELSE holds too: a released fighter or bomber lands in
	// stock tasks that wander it to the front line, where it dies for nothing
	// -- apexearth: "they primarily only fly overhead of our bases... A bomber
	// is not supposed to attack armies... they should mass up and then bomb
	// enemies behind the lines." Held aircraft hover at the plant, which is
	// home; the wave release lives in Update().
	if (IsAirLead())
		return true;
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
			if ((wings[i] is null) || InWave(wings[i].id) || Covering(wings[i].id))
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
	// A frame is not a bomber: a wave of none ends on the next tick and is
	// released again, every few seconds.
	if (gWaveBombers == 0) {
		gStrike = false;
		gWave.resize(0);
		gRunWave.resize(0);
		gWaveFighters = 0;
		gWaveMass = 0.f;
		return;
	}
	gWaveLaunched = gWaveBombers;
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
	// ONE MASS AT ONE CELL: the DLL's bomb task hunts inside the focus only
	// and judges the AA over it against the wave's whole power. Published on
	// the team blackboard (strike_x/z/r/p) rather than a new binding, so a
	// DLL without the reader still compiles this script.
	if (gStrikeHas) {
		ai.PublishTeamValue("strike_x", gStrikeAt.x);
		ai.PublishTeamValue("strike_z", gStrikeAt.z);
		ai.PublishTeamValue("strike_p", WavePower());
		ai.PublishTeamValue("strike_s", Throughput(gWaveBombers));
		ai.PublishTeamValue("strike_r",
				ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R));
		Vanguard();
	}
	AiLog(Factory::T() + "apex: air strike -- " + why
		+ " bombers=" + Bombers() + " fighters=" + Fighters()
		+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0)
		+ " target=" + (gStrikeHas ? (int(gStrikeAt.x) + "," + int(gStrikeAt.z)) : "-")
		+ " prize=" + int(EcoDensity())
		+ " structs=" + int(aiEnemyMgr.GetEnemyStructCost())
		+ " scaled=" + ScaledBombers()
		+ " cellAA=" + formatFloat(gStrikeAA, "", 0, 1));
}

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
	// Spent means half of what launched is gone; an absolute three read a
	// small wave as spent on the tick it left and Release/ReArm flapped.
	const int have = gWaveBombers;
	// Weight against weight: a count of 14 Dragons against one Dragon's 16
	// units at home recalled the wave the moment the next one finished.
	const int held = int(StandingHeldMass());
	if ((have > 0) && (have * 2 >= gWaveLaunched) && (float(held) <= gWaveMass))
		return;
	RecallWave();
	ai.PublishTeamValue("strike_r", 0.f);
	gStrike = false;
	gWave.resize(0);
	gWaveBombers = 0;
	gWaveFighters = 0;
	// A fresh massing window and a fresh frozen bar for the next run --
	// without this the deadline is permanently in the past and every rebuild
	// trickles out at the floor instead of massing.
	gCommitFrame = ai.frame;
	gCommitBombers = ScaledBombers();
	RollDeadline();
	AiLog(Factory::T() + "apex: air strike over -- " + have
		+ " of the wave home, " + held + " built since; massing them together"
		+ " for the next run");
}

// The scout the look bought flies it: a raw move across their structures
// (the mirrored start until one is seen), held in the idle task so nothing
// re-routes it, and handed back to stock the moment the look is not wanted.
bool LookDispatch(CCircuitUnit@ unit)
{
	if (int(unit.id) == gLookScout)
		return true;
	if ((gLookScout >= 0) || !LookPays(int(unit.circuitDef.id)))
		return false;
	// A pass that showed nothing means the mirror is not where they live:
	// the next one crosses their army instead, then the mirror again wider.
	AIFloat3 over = Front::FoeAnchor();
	if ((gLookMiss % 2) == 1) {
		const AIFloat3 army = aiEnemyMgr.GetEnemyPos();
		if (OnMap(army) && (army.distance2D(over) > 1000.f)
			&& (army.SqLength2D() > 1.f))
			over = army;
	}
	if (!OnMap(over))
		return false;
	const float ang = float((ai.frame / SECOND) % 8) * 0.785398f;
	const AIFloat3 jit = over + AIFloat3(cos(ang), 0.f, sin(ang))
			* (500.f * float(1 + (gLookMiss / 2) % 3));
	if (OnMap(jit))
		over = jit;
	gLookWay = LookRoute(unit, over);
	gLookLeg = gLookWay.distance2D(over) > 1.f ? 0 : 1;
	unit.CmdMoveTo((gLookLeg == 0) ? gLookWay : over);
	Cover(unit, over, "look");
	gLookScout = int(unit.id);
	gLookDef = int(unit.circuitDef.id);
	gLookTarget = over;
	gLookSeen0 = aiEnemyMgr.GetEnemyStructCost();
	++gLookFlown;
	AiLog(Factory::T() + "apex: air look " + unit.circuitDef.GetName()
		+ " #" + unit.id + " -> " + int(over.x) + "," + int(over.z)
		+ ((gLookLeg == 0) ? (" via " + int(gLookWay.x) + "," + int(gLookWay.z)) : "")
		+ " structs=" + int(gLookSeen0)
		+ " mirror=" + int(MirrorPrize())
		+ " stale=" + formatFloat(LookStale(), "", 0, 2)
		+ " p=" + formatFloat(LookDelivery(), "", 0, 2)
		+ " worth=" + int(LookWorth()));
	return true;
}

// The straight line crosses the front, where the scout dies before it sees
// anything. Three approaches -- straight, and wide around either flank -- are
// read off the air-threat map for this scout; the quietest one is flown, as
// a waypoint first when it is not the straight line.
float RouteThreat(CCircuitUnit@ unit, const AIFloat3& in a, const AIFloat3& in b)
{
	float sum = 0.f;
	for (int i = 1; i <= 6; ++i) {
		const AIFloat3 p = a + (b - a) * (float(i) / 6.f);
		if (OnMap(p))
			sum += ai.GetUnitThreatAt(unit, p);
	}
	return sum;
}

AIFloat3 LookRoute(CCircuitUnit@ unit, const AIFloat3& in over)
{
	const AIFloat3 orig = unit.GetPos(ai.frame);
	AIFloat3 axis = over - orig;
	const float span = axis.Length2D();
	if (span < 1.f)
		return over;
	AIFloat3 perp(-axis.z / span, 0.f, axis.x / span);
	const AIFloat3 mid = orig + axis * 0.5f;
	float bestT = RouteThreat(unit, orig, over);
	AIFloat3 best = over;
	const float wide = 0.5f * span;
	const float mw = float(AiTerrainWidth());
	const float mh = float(AiTerrainHeight());
	for (int side = -1; side <= 1; side += 2) {
		AIFloat3 w = mid + perp * (wide * float(side));
		w.x = (w.x < 64.f) ? 64.f : ((w.x > mw - 64.f) ? mw - 64.f : w.x);
		w.z = (w.z < 64.f) ? 64.f : ((w.z > mh - 64.f) ? mh - 64.f : w.z);
		if (w.distance2D(mid) < 500.f)
			continue;
		const float t = RouteThreat(unit, orig, w) + RouteThreat(unit, w, over);
		if (t < bestT) {
			bestT = t;
			best = w;
		}
	}
	return best;
}

// The look is delivered when the scout's sight reaches the target; a scout
// that dies short of it delivers whatever it saw on the way, and the census
// says how much that was.
void LookWatch()
{
	if (gLookScout < 0)
		return;
	CCircuitUnit@ scout = null;
	if (gLookDef > 0) {
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(gLookDef),
				Builder::gHomePos, 0.f);
		if (us !is null) {
			for (uint i = 0; i < us.length(); ++i) {
				if ((us[i] !is null) && (int(us[i].id) == gLookScout)) {
					@scout = us[i];
					break;
				}
			}
		}
	}
	const float seen = aiEnemyMgr.GetEnemyStructCost();
	const bool saw = seen > gLookSeen0 + 1.f;
	if (scout !is null) {
		const AIFloat3 at = scout.GetPos(ai.frame);
		if ((gLookLeg == 0) && (at.distance2D(gLookWay) < 300.f)) {
			gLookLeg = 1;
			scout.CmdMoveTo(gLookTarget);
		}
		if (at.distance2D(gLookTarget) > Catalog::gLosR[gLookDef])
			return;
	}
	if (saw) {
		gLookAt = ai.frame;
		gLookMiss = 0;
		++gLookDelivered;
	} else {
		++gLookMiss;
	}
	AiLog(Factory::T() + "apex: air look " + ((scout is null) ? "lost" : "landed")
		+ " #" + gLookScout + " structs=" + int(gLookSeen0) + "->" + int(seen)
		+ " miss=" + gLookMiss
		+ " next=" + int(MarginalGain(BuyableBomberDef(), HeldBombers())));
	CoverRelease(Id(gLookScout), (scout is null) ? "look lost" : "look landed");
	gLookScout = -1;
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
	// The radar plane stations FORWARD, not over the farm: its set reaches
	// ~2,300 elmos, so 45% of the way to the enemy paints their approaches
	// and the ground the silo wants lit ("our nukes don't land in smart
	// places because we haven't seen those smart places").
	if (Builder::gHomeSet) {
		const array<int>@ ownedR = Market::OwnedDefs();
		for (uint oi = 0; oi < ownedR.length(); ++oi) {
			const int rd = ownedR[oi];
			if (!Catalog::gAvailable[rd] || !Catalog::gMobile[rd]
				|| !Catalog::gFlyer[rd] || Catalog::gBuilder[rd]
				|| !Catalog::gRadar[rd]
				|| (Catalog::gCostM[rd] <= 100.f))
				continue;
			array<CCircuitUnit@>@ rs = ai.GetOwnUnitsOfDef(Catalog::Def(rd),
					foe, 0.f);
			if (rs is null)
				continue;
			for (uint ri = 0; ri < rs.length(); ++ri) {
				if ((rs[ri] is null) || (rs[ri].CmdQueueSize() > 0))
					continue;
				AIFloat3 post = Builder::gHomePos
						+ (foe - Builder::gHomePos) * 0.45f;
				const float angR = float((ai.frame / SECOND + int(ri) * 3) % 8)
						* 0.785398f;
				post += AIFloat3(cos(angR), 0.f, sin(angR)) * 400.f;
				if (!OnMap(post))
					continue;
				rs[ri].CmdMoveTo(post);
				Cover(rs[ri], post, "radar-post");
				AiLog("apex: radar-post " + Catalog::Def(rd).GetName()
					+ " #" + rs[ri].id + " -> " + int(post.x) + "," + int(post.z));
				break;
			}
		}
	}
	const array<int>@ ownedS = Market::OwnedDefs();
	for (uint oi = 0; oi < ownedS.length(); ++oi) {
		const int d = ownedS[oi];
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
			Cover(us[i], over, "overflight");
			AiLog("apex: overflight " + Catalog::Def(d).GetName()
				+ " #" + us[i].id + " -> " + int(over.x) + "," + int(over.z));
			return;
		}
	}
}

void Update()
{
	{ double _tA = Perf::T0(); SettleStrike(); Perf::Add("air.SettleStrike", _tA); }
	{ double _tA = Perf::T0(); ResolveDefs(); Perf::Add("air.ResolveDefs", _tA); }
	{ double _tA = Perf::T0(); ReArm(); Perf::Add("air.ReArm", _tA); }
	{ double _tA = Perf::T0(); AtomicWatch(); Perf::Add("air.AtomicWatch", _tA); }
	{ double _tA = Perf::T0(); AtomicLookWatch(); Perf::Add("air.AtomicLookWatch", _tA); }
	{ double _tA = Perf::T0(); LookWatch(); Perf::Add("air.LookWatch", _tA); }
	{ double _tA = Perf::T0(); FlightWatch(); Perf::Add("air.FlightWatch", _tA); }
	{ double _tA = Perf::T0(); ShareWing(); Perf::Add("air.ShareWing", _tA); }
	{ double _tA = Perf::T0(); Market::EnemyWetCount(); Perf::Add("air.EnemyWetCount", _tA); }
	{ double _tA = Perf::T0(); CoverWatch(); Perf::Add("air.CoverWatch", _tA); }
	{ double _tA = Perf::T0(); StrikeScanStep(); Perf::Add("air.StrikeScanStep", _tA); }
	ai.PublishTeamValue(TV_AIRINC, Eco::MInc());
	if (Factory::ElectorTeamId() == ai.teamId)
		{ double _tA = Perf::T0(); RunElection(); Perf::Add("air.RunElection", _tA); }
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
		// EVERY bomber tier, not just the two basic ones: the heavy (index 0)
		// and the atomic (3) were given ANTI_STAT once at Release and never
		// again, so they kept hunting army through a base invasion and kept
		// ignoring it after one.
		//
		// A bombing run never turns around: the bomb is the sortie's whole
		// value and the flak is thickest on the way BACK OUT -- apexearth:
		// "Air bombing attacks should never retreat. You'll take 75% losses
		// and achieve nothing." Previously zeroed only at Release; a wave
		// that took hits inbound still peeled home with bombs unspent.
		for (int i = 0; i <= 3; ++i) {
			CCircuitDef@ b = StrikeDef(i);
			if (b is null)
				continue;
			if (defendHome) b.DelAttribute(Unit::Attr::ANTI_STAT.type);
			else            b.AddAttribute(Unit::Attr::ANTI_STAT.type);
			b.SetRetreat(0.f);
		}
		// A held force does not hover through a base invasion -- gDefendHome
		// opens HoldsUnit directly, without pretending a strike is under way.
	}

	// A NON-LEAD player's wave: mass at home, then strike together. Half the
	// lead's scaled force is a real raid without hoarding a second air army.
	if (!IsAirLead() && !gStrike
		&& (ai.GetTunable("apex_air_home_wave", TUNE_AIR_HOME_WAVE) > 0.f)
		&& (StandingHeldMass() * 2.f >= float(ScaledBombers()))
		&& (ReadyFighters() >= EscortWant()))
	{
		Release("home wave massed");
	}

	if (!IsAirLead() || gStrike)
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
	if (Committed() && WingGrowing())
		Economy::isSwitchAssist = true;

	// Do not start an air force while the ground war is being lost badly: the
	// assassin fields no ground army while it builds, affordable from a stable
	// position and not from a losing one. GROUND_LOST_RATIO rather than
	// Military::LosingGround(), which fires at mere parity and would cancel the
	// strategy almost always -- this wants a real deficit. Checked only before
	// COMMITTING; a force already paid for is better spent than abandoned, and
	// Update()'s own abort path below handles anti-air appearing mid-build.
	// A wing already standing is not held hostage to it: with planes bought,
	// the clock below starts and the strike rules apply.
	const float ourGround = Military::TeamArmyCost();
	const float foeGround = Military::EnemyArmyCost();
	// The ground-war hold-off that stood here is gone (see WingBuys); the
	// deficit is logged with the commit instead.
	if (!Committed() && (Bombers() == 0) && (foeGround > ourGround * GROUND_LOST_RATIO)
		&& (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: air assassin committing behind on the ground "
			+ formatFloat(ourGround, "", 0, 0) + " vs " + formatFloat(foeGround, "", 0, 0));
	}

	if (!Committed() && Armed()) {
		CCircuitDef@ first = FactoryToBuild();
		if (first !is null) {
			gCommitFrame = ai.frame;
			gCommitBombers = ScaledBombers();
			RollDeadline();
			AiLog(Factory::T() + "apex: air assassin committing, first plant "
				+ first.GetName());
		} else if (Bombers() > 0) {
			// The wing can stand without this player ever ASKING for a
			// plant -- the market builds air plants on its own law, so
			// FactoryToBuild() reads null and nothing starts the clock, and
			// the wing is held forever. A standing bomber commits the
			// deadline.
			gCommitFrame = ai.frame;
			gCommitBombers = ScaledBombers();
			RollDeadline();
			AiLog(Factory::T() + "apex: air clock started -- wing standing, "
				+ Bombers() + " bombers, sizing " + gCommitBombers
				+ ", window " + (gDeadlineFrames / MINUTE) + "m");
		}
	}

	// Standing down is gone: a wing that cannot grow any further goes with
	// what stands, because the next plane not paying is the end of "build up"
	// and the beginning of "eventually" -- and the planes are already bought.
	// What stands must still be a wing: below the floor this threw a spent
	// run's survivors back out the tick they were recalled, six at a time.
	if (Massed()) {
		Release("massed");
	} else if (Committed() && !WingGrowing() && (HeldBombers() >= AIR_BOMBERS)) {
		Release("wing at its worth -- the next bomber would not pay");
	} else if (Committed() && (ai.frame > gCommitFrame + gDeadlineFrames)
		&& (BomberMass() >= DeadlineBombBar()))
	{
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
			+ " prize=" + int(EcoDensity())
			+ " next=" + formatFloat(MarginalGain(BuyableBomberDef(), HeldBombers()), "", 0, 0)
			+ " held=" + HeldBombers() + "/" + ScaledBombers());
	}

	// Heartbeat. A gate that never fires and an input that is dead read the same
	// in a log that only prints on transitions.
	if (Armed() && (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		CCircuitDef@ want = FactoryToBuild();
		const int buy = BuyableBomberDef();
		AiLog(Factory::T() + "apex: air " + Bombers() + "/" + ScaledBombers()
			+ " bombers, " + Fighters() + "/" + ScaledFighters() + " fighters"
			+ " bar=" + (Committed() ? int(DeadlineBombBar()) : -1)
			+ " plants=" + Have(gPlant1) + "," + Have(gPlant2)
			+ " cons=" + (HaveAirCon() ? "1" : "0")
			+ " want=" + ((want is null) ? "-" : want.GetName())
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0)
			+ " structs=" + int(aiEnemyMgr.GetEnemyStructCost())
			+ " cell=" + int(EcoDensity())
			+ " next=" + int(MarginalGain(buy, HeldBombers()))
			+ "/" + ((buy < 0) ? 0 : int(Catalog::gCostM[buy]
				* ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF)))
			+ " held=" + HeldBombers());
	}
}

}  // namespace Air
