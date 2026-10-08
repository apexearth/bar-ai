namespace Military {

//------------------------------------------------------------------------------
// PULL A LOSING SQUAD BACK UNDER OUR OWN GUNS.
//
// apexearth 2026-08-19: "if our squad is in a fight that it obviously [cannot]
// win, it must immediately turn around and retreat. If there's nearby towers or
// defenses we could go behind, then that's where we should go, and we should try
// to hide behind our defenses and fight the enemy under our towers. We can let
// the towers take some of the damage while still shooting at the enemy."
//
// WHY THIS EXISTS AT ALL. CircuitAI evaluates odds exactly once, in
// CAttackTask::FindTarget, before the squad commits. After that nothing asks
// whether the fight is going badly: CAttackTask::Update only merges, regroups
// and re-picks a target. The only way out is IFighterTask::OnUnitDamaged, which
// returns immediately while healthPerc > cdef->GetRetreat() -- so the local
// odds test below it is unreachable until a unit is already hurt, and units then
// leave ONE AT A TIME. Measured 2026-08-19: of 452 units that died retreating,
// 186 came from the pool and none from an attack; the squad dissolves rather
// than withdrawing.
//
// CMilitaryManager::AssignTask is not bound, so the squad cannot be reassigned
// from here -- but a move order can be given directly, and the task's own
// pathing yields to it in practice. Orders are re-issued while the condition
// holds, so a task that re-paths does not simply undo this.
//------------------------------------------------------------------------------

// Our fighting units, registered as they are elected (NoteFightElection). There
// is no binding that enumerates our own units, so this register is the only way
// to walk the army.
array<int> gCombatId;
array<int> gCombatSent;      // frame we last ordered this unit back
array<int> gCombatBucket;    // last observed task bucket, for transition tags
int gNextWithdraw = 0;
int gNextTaskAbort = 0;
int gWithdrawn = 0;
int gHeldCommitted = 0;
int gHeldGround = 0;
int gNextHeldGroundLog = 0;
int gNextHoldLog = 0;
int gNextWithdrawLog = 0;
int gNextCensusLog = 0;
// gTrackedCost (see state.as) is refreshed by the pass below.

void NoteCombatUnit(int id)
{
	for (uint i = 0; i < gCombatId.length(); ++i) {
		if (gCombatId[i] == id)
			return;
	}
	gCombatId.insertLast(id);
	gCombatSent.insertLast(0);
	gCombatBucket.insertLast(-1);
}

// WHERE A PULLED-BACK UNIT REFORMS. apexearth 2026-08-24: "we should prefer to
// defend at the chokepoints/frontline areas, not at our home base. It is a long
// walk all the way back home on some maps and that splits our army too much."
// Behind our own doorway first -- everything coming at us has to come through
// it, and it is a short walk from the fighting -- then the nearest point on the
// front, and home only when we have no idea where the front is.
// A pull-back must never RAISE the unit's forward fraction. FallbackSpot
// picks the nearest own gun in any direction, and since the choke-gate work
// our guns stand at forward doorways -- so "retreat" marched units TOWARD
// the fight (measured on the first --teams battery: of 492 deaths within
// 2min of a W order, 165 had moved AWAY from home and 210 died in place
// ping-ponging, median hp at the order 100%). Rearward-only is the
// constraint that was implicit in his ruling all along: hide BEHIND our
// defenses, not under the front's.
bool Rearward(const AIFloat3& in from, const AIFloat3& in to)
{
	return Military::ForwardFraction(to) < Military::ForwardFraction(from);
}

int gHeldStrong = 0;
int gNextHeldStrongLog = 0;
bool SideDwarfs()
{
	const float ours = OurArmyNow();
	return FoeArmySeen() && (ours > 1.f)
		&& (Market::StrRatio(FoeMobileMassing(), ours) <= 0.5f);
}

// The nearest ground we hold on the way home: stepping from the unit toward
// home, the first point where we are not losing (apexearth 2026-09-30: stop at
// the ground we hold, do not walk to the base).
bool HeldGroundBack(const AIFloat3& in from, AIFloat3& out at)
{
	if (!Builder::gHomeSet)
		return false;
	AIFloat3 dir = Builder::gHomePos - from;
	const float len = sqrt(dir.SqLength2D());
	if (len < 1.f)
		return false;
	dir *= (1.f / len);
	for (float s = 256.f; s < len; s += 256.f) {
		const AIFloat3 p = from + dir * s;
		if (OnMap(p) && (ai.GetNetInflAt(p) > 0.f)) {
			at = p;
			return true;
		}
	}
	return false;
}

bool RallySpot(const AIFloat3& in from, AIFloat3& out at)
{
	AIFloat3 cp;
	if (Front::FrontChoke(from, cp)
		&& Front::BehindChoke(cp, ai.GetTunable("apex_withdraw_behind", TUNE_WITHDRAW_BEHIND), at)
		&& OnMap(at) && Rearward(from, at))
	{
		return true;
	}
	if (Front::FrontNear(from, at) && OnMap(at) && Rearward(from, at))
		return true;
	// The team's rally, never our own start (apexearth 2026-10-02: a back
	// seat's army walked to the middle of its base while the front bases
	// died). Already behind it, the pack holds where it stands.
	AIFloat3 lane;
	if (!TeamLaneRead(lane))
		lane = gLaneAt;
	if (OnMap(lane) && ((lane.x > 1.f) || (lane.z > 1.f)) && Rearward(from, lane)) {
		at = lane;
		return true;
	}
	return false;
}

// WHERE HOME IS BEING HIT, not a doorway or the base centre (apexearth
// 2026-09-29: the army waited behind a hill, or walked across the map to its
// start, while the base died): the building we lost last, the group closing
// on it, home only when neither is known.
AIFloat3 HomeFightPos()
{
	if (BaseRaided() && OnMap(gRaidPos))
		return gRaidPos;
	if ((ai.frame - gIncomingAt < 15 * SECOND) && OnMap(gIncomingPos))
		return gIncomingPos;
	return Builder::gHomePos;
}

// A unit comes home only if it is no further from the fight than their front
// is: a walk of minutes arrives after the raid and leaves our line empty.
bool ArrivesInTime(const AIFloat3& in p)
{
	const AIFloat3 fight = HomeFightPos();
	const AIFloat3 foe = Front::FoeAnchor();
	if (!OnMap(foe) || ((foe.x == 0.f) && (foe.z == 0.f)))
		return true;
	return p.distance2D(fight) <= foe.distance2D(fight);
}

// The nearest gun of ours, stepped back toward home so the unit stands BEHIND
// it: the tower is between the unit and whatever is chasing it, which is the
// whole point -- it soaks while we keep shooting.
bool FallbackSpot(const AIFloat3& in from, AIFloat3& out at)
{
	float best = -1.f;
	AIFloat3 tower;
	const float fromFwd = Military::ForwardFraction(from);
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (!OnMap(gFencePos[i]))
			continue;
		if (i < gFenceDef.length()) {
			const CCircuitDef@ d = gFenceDef[i];
			// A radar mast or a jammer is not cover.
			if ((d !is null) && (d.GetSurfThreat() <= 0.f))
				continue;
		}
		// Rearward guns only -- see Rearward(). The nearest gun is often a
		// forward gate tower now, and sheltering "behind" it walks the unit
		// deeper into the fight it is leaving.
		if (Military::ForwardFraction(gFencePos[i]) >= fromFwd)
			continue;
		const float d2 = gFencePos[i].distance2D(from);
		if ((best < 0.f) || (d2 < best)) {
			best = d2;
			tower = gFencePos[i];
		}
	}
	if (best < 0.f) {
		// No guns anywhere: reform on the line rather than dying in the open.
		return RallySpot(from, at);
	}
	if (!Builder::gHomeSet) {
		at = tower;
		return OnMap(at);
	}
	AIFloat3 toHome = Builder::gHomePos - tower;
	const float len = sqrt(toHome.SqLength2D());
	if (len < 1.f) {
		at = tower;
		return OnMap(at);
	}
	toHome *= (1.f / len);
	at = tower + toHome * ai.GetTunable("apex_withdraw_behind", TUNE_WITHDRAW_BEHIND);
	return OnMap(at);
}

// Is this unit standing somewhere we are clearly losing? Net influence is
// ally-minus-enemy at a point, the same reading BaseContested and the lane
// walk-back already trust, and unlike a count it is a strength comparison.
bool LosingHere(const AIFloat3& in pos)
{
	return ai.GetNetInflAt(pos) < -ai.GetTunable("apex_withdraw_infl", TUNE_WITHDRAW_INFL);
}

// THE SCOREBOARD OUTRANKS THE MAP. Both sensors above model strength --
// OutgunnedHere from the threat map, LosingHere from influence -- and both can
// call a fight fine while it is being lost in observed fact: a streaming enemy
// reads weak at every instant, influence lags until our units are already
// dying. Recent deaths are ground truth with no lag and nothing hidden. This
// keeps a short ledger of combat deaths on both sides, with position, and
// calls a spot lost when OUR combat metal is dying there and theirs is not.
// Ours counts mobile combat only -- a building dying while the army stands is
// the army's cue to fight, not to leave.
array<AIFloat3> gTradeAt;
array<float> gTradeM;
array<bool> gTradeOurs;
array<int> gTradeFrame;

void NoteLocalDeath(const AIFloat3& in at, float costM, bool ours)
{
	if (!OnMap(at) || (costM <= 0.f))
		return;
	const int keep = int(ai.GetTunable("apex_trade_window", TUNE_TRADE_WINDOW)) * SECOND;
	// Entries are appended in frame order, so the expired ones are always a
	// PREFIX: find how long it is and drop it in one shift. Walking the whole
	// ledger per death and calling removeAt (an O(n) shift of its own) made
	// every death cost the deaths of the last fifteen seconds -- the one part
	// of a death hook that grew with how hard the game was being fought.
	uint drop = 0;
	while ((drop < gTradeFrame.length()) && (ai.frame - gTradeFrame[drop] > keep))
		++drop;
	if (drop > 0) {
		const uint kept = gTradeFrame.length() - drop;
		for (uint i = 0; i < kept; ++i) {
			gTradeAt[i] = gTradeAt[i + drop];
			gTradeM[i] = gTradeM[i + drop];
			gTradeOurs[i] = gTradeOurs[i + drop];
			gTradeFrame[i] = gTradeFrame[i + drop];
		}
		gTradeAt.resize(kept);
		gTradeM.resize(kept);
		gTradeOurs.resize(kept);
		gTradeFrame.resize(kept);
	}
	gTradeAt.insertLast(at);
	gTradeM.insertLast(costM);
	gTradeOurs.insertLast(ours);
	gTradeFrame.insertLast(ai.frame);
}

// ONE PASS'S CONSTANTS AND GRIDS. Every unit of the pass summed the whole army,
// every fence and the whole trade ledger within one radius, and re-read the
// same tunables; the grids answer each with the cells under the radius and
// the same distance test.
float gWdR = 0.f, gWdR2 = 0.f, gWdOddsK = 1.f, gWdFloor = 0.f, gWdLoseTrade = 1.f;
int gWdKeep = 0;
Grid::Cells gWdAlly;
Grid::Cells gWdFence;
array<int> gWdFenceIdx;
Grid::Cells gWdTrade;
array<int> gWdTradeIdx;
void WdPassPrep(const array<AIFloat3>@ allyPos)
{
	gWdR = ai.GetTunable("apex_withdraw_ally_r", TUNE_WITHDRAW_ALLY_R);
	gWdR2 = gWdR * gWdR;
	gWdOddsK = ai.GetTunable("apex_withdraw_odds", TUNE_WITHDRAW_ODDS);
	gWdFloor = ai.GetTunable("apex_losing_floor", TUNE_LOSING_FLOOR);
	gWdLoseTrade = ai.GetTunable("apex_losing_trade", TUNE_LOSING_TRADE);
	gWdKeep = int(ai.GetTunable("apex_trade_window", TUNE_TRADE_WINDOW)) * SECOND;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float cell = (gWdR > 64.f) ? gWdR : 64.f;
	gWdAlly.Begin(cell, 0.f, 0.f, w, h);
	for (uint i = 0; i < allyPos.length(); ++i)
		gWdAlly.Add(allyPos[i].x, allyPos[i].z);
	gWdFence.Begin(cell, 0.f, 0.f, w, h);
	gWdFenceIdx.resize(0);
	for (uint i = 0; (i < gFencePos.length()) && (i < gFenceDef.length()); ++i) {
		const CCircuitDef@ d = gFenceDef[i];
		if ((d is null) || (d.GetSurfThreat() <= 0.f))
			continue;
		gWdFence.Add(gFencePos[i].x, gFencePos[i].z);
		gWdFenceIdx.insertLast(int(i));
	}
	gWdTrade.Begin(cell, 0.f, 0.f, w, h);
	gWdTradeIdx.resize(0);
	for (uint i = 0; i < gTradeAt.length(); ++i) {
		if (ai.frame - gTradeFrame[i] > gWdKeep)
			continue;
		gWdTrade.Add(gTradeAt[i].x, gTradeAt[i].z);
		gWdTradeIdx.insertLast(int(i));
	}
}

bool LosingFightHere(const AIFloat3& in p, float& out lost, float& out killed)
{
	lost = 0.f;
	killed = 0.f;
	if (gWdFloor <= 0.f)
		return false;
	gWdTrade.Query(p.x, p.z, gWdR);
	for (uint h = 0; h < gWdTrade.hit.length(); ++h) {
		const uint i = uint(gWdTradeIdx[uint(gWdTrade.hit[h])]);
		if (gTradeAt[i].SqDistance2D(p) > gWdR2)
			continue;
		if (gTradeOurs[i])
			lost += gTradeM[i];
		else
			killed += gTradeM[i];
	}
	return (lost >= gWdFloor) && (lost > killed * gWdLoseTrade);
}

// The influence test above LAGS: influence is built from standing presence, so
// at the contact line it reads ~0 until our units are already dying. This is
// the leading version of the same question: the threat map already knows what
// is standing there, so compare it against what WE have standing nearby -- our
// combat units plus our own towers -- and call the spot lost when they outgun
// us by the margin. Threat-map values and GetSurfThreat are the same scale.
int gWithdrawAllySaved = 0;
int gWithdrawAllyLogAt = 0;

bool OutgunnedHere(CCircuitUnit@ u, const AIFloat3& in p,
	const array<AIFloat3>@ allyPos, const array<float>@ allyPow, float& out oddsFor)
{
	const float enemyT = ai.GetUnitThreatAt(u, p);
	oddsFor = 0.f;
	if (enemyT <= 0.f)
		return false;
	const float r = gWdR;
	const float r2 = gWdR2;
	float ours = 0.f;
	gWdAlly.Query(p.x, p.z, r);
	for (uint h = 0; h < gWdAlly.hit.length(); ++h) {
		const uint i = uint(gWdAlly.hit[h]);
		if (allyPos[i].SqDistance2D(p) <= r2)
			ours += allyPow[i];
	}
	gWdFence.Query(p.x, p.z, r);
	for (uint h = 0; h < gWdFence.hit.length(); ++h) {
		const uint i = uint(gWdFenceIdx[uint(gWdFence.hit[h])]);
		if (gFencePos[i].SqDistance2D(p) <= r2)
			ours += gFenceDef[i].GetSurfThreat();
	}
	float oddsK = gWdOddsK;
	// A LOSS ON THEIR GROUND PAYS THEM (his 2026-09-28: "10,000 army and it
	// all died, that turns into 5,000 metal for the other team to reclaim").
	// Forward of home, whoever holds the ground takes the wrecks, so a
	// losing trade there costs half again; the odds we accept tighten to match.
	{
		float fwd = ForwardFraction(p);
		if (fwd > 1.f)
			fwd = 1.f;
		if (fwd > 0.f)
			oddsK /= 1.f + 0.5f * fwd;
	}
	// Our allies' army standing here is our side too; asked only when our own
	// would already lose, so the scan runs for the few, not the whole army.
	if (enemyT > ours * oddsK) {
		const float allies = ai.GetAllyPowerAt(p, r);
		if ((allies > 0.f) && (enemyT <= (ours + allies) * oddsK))
			++gWithdrawAllySaved;
		ours += allies;
	}
	oddsFor = (ours > 0.f) ? (enemyT / ours) : 99.f;
	return enemyT > ours * oddsK;
}

// Nothing a withdraw pass does moves the hold, so it is asked once per pass.
int gHoldHomePass = -1;
bool HoldHomeOnce()
{
	if (gHoldHomePass < 0)
		gHoldHomePass = HoldHome() ? 1 : 0;
	return gHoldHomePass > 0;
}

// WHICH TASK BALLS UP: per fight type, of our units with enemy influence on
// them, the mean count of our own within splash range (docs/24, "never a
// ball"; his 8v8 showed 7-12 to BARb's 3-5).
int gNextPackLog = 0;
void PackingCensus(const array<CCircuitUnit@>@ alive, const array<AIFloat3>@ pos)
{
	if (ai.frame < gNextPackLog)
		return;
	gNextPackLog = ai.frame + 30 * SECOND;
	array<int> n(16, 0);
	array<int> k(16, 0);
	for (uint j = 0; j < alive.length(); ++j) {
		IUnitTask@ t = alive[j].task;
		if ((t is null) || (t.GetType() != Task::Type::FIGHTER))
			continue;
		const AIFloat3 p = pos[j];
		if (ai.GetEnemyInflAt(p) <= 0.01f)
			continue;
		const int ft = t.GetFightType();
		if ((ft < 0) || (ft >= 16))
			continue;
		int c = 0;
		gWdAlly.Query(p.x, p.z, 150.f);
		for (uint h = 0; h < gWdAlly.hit.length(); ++h) {
			const uint i2 = uint(gWdAlly.hit[h]);
			if ((i2 != j) && (pos[i2].SqDistance2D(p) <= 150.f * 150.f))
				++c;
		}
		++n[ft];
		k[ft] += c;
	}
	string ln = "";
	for (int ft = 0; ft < 16; ++ft) {
		if (n[ft] > 0)
			ln += " " + FightTypeName(uint(ft)) + "=" + formatFloat(float(k[ft]) / float(n[ft]), "", 0, 1) + "/" + n[ft];
	}
	if (ln.length() > 0)
		AiLog(Factory::T() + "apex: packing t=" + ai.teamId + " (own within 150 / units in contact)" + ln);
}

void UpdateWithdraw()
{
	if ((ai.frame < gNextWithdraw) || !ApexActive())
		return;
	gNextWithdraw = ai.frame + 2 * SECOND;
	{ double _t = Perf::T0(); ArmyCoverSample(); Perf::Add("up.armycover", _t); }
	if ((ai.GetTunable("apex_withdraw", TUNE_WITHDRAW) <= 0.f) || AllIn())
		return;
	if (ai.frame >= gWithdrawAllyLogAt) {
		gWithdrawAllyLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: withdraw-allies t=" + ai.teamId + " kept=" + gWithdrawAllySaved);
	}

	// Pass 1: prune the dead, cache everyone's position and power once --
	// pass 2 sums local strength around each candidate from this cache.
	array<AIFloat3> allyPos;
	array<float> allyPow;
	array<float> allyCost;
	array<CCircuitUnit@> alive;
	array<int> aliveSlot;
	// Census: what task the army is actually on, split home/field. The
	// tightness telemetry shows 7-12 singletons in the field at any moment;
	// this says which task type they belong to, which nothing else records.
	array<int> cenHome(20);
	array<int> cenField(20);
	float trackedCost = 0.f;
	for (int i = int(gCombatId.length()) - 1; i >= 0; --i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gCombatId[i]));
		if (u is null) {
			gCombatId.removeAt(i);
			gCombatSent.removeAt(i);
			gCombatBucket.removeAt(i);
			// Every slot cached so far came from ABOVE this index (the walk
			// descends), so this removal shifted each of them down one --
			// un-shifted, pass 2 reads a neighbour's stamp, writes the wrong
			// unit's reissue frame, and the highest entry indexes past the
			// end (the line-500 out-of-bounds that aborts the whole tick).
			for (uint q = 0; q < aliveSlot.length(); ++q)
				--aliveSlot[q];
			continue;
		}
		const AIFloat3 p = u.GetPos(ai.frame);
		if (!OnMap(p))
			continue;
		// A RUNNER IS NOT SUPPORT. apexearth: "Do the units that stay and
		// fight realize that the runners won't count as part of their army
		// value/strength?" They did not: the odds sum counted every nearby
		// body at paper value, so stayers overestimated support exactly
		// while it evaporated, then the sum collapsed all at once when the
		// runners cleared the radius. A unit on the engine RETREAT task, or
		// one this pass ordered back within the last 8s, contributes zero.
		bool fleeing = (ai.frame - gCombatSent[i] < 8 * SECOND);
		IUnitTask@ preTask = u.task;
		if (!fleeing && (preTask !is null)
			&& (preTask.GetType() == Task::Type::RETREAT))
		{
			fleeing = true;
		}
		allyPos.insertLast(p);
		allyPow.insertLast((!fleeing && (u.circuitDef !is null))
				? u.circuitDef.GetSurfThreat() : 0.f);
		allyCost.insertLast((u.circuitDef !is null) ? u.circuitDef.costM : 0.f);
		alive.insertLast(u);
		aliveSlot.insertLast(i);
		if (u.circuitDef !is null)
			trackedCost += u.circuitDef.costM;
		int bucket = 19;   // 0-12 fight types; 13 retreat; 14 other
		IUnitTask@ ct = u.task;
		if (ct !is null) {
			if (ct.GetType() == Task::Type::FIGHTER) {
				const int f = ct.GetFightType();
				bucket = ((f >= 0) && (f < 13)) ? f : 14;
			} else if (ct.GetType() == Task::Type::RETREAT) {
				bucket = 13;
			} else {
				bucket = 14;
			}
		}
		const bool inField = Builder::gHomeSet
			&& (p.distance2D(Builder::gHomePos) > 600.f);
		if (inField)
			++cenField[bucket];
		else
			++cenHome[bucket];
		// TRANSITIONS INTO STATES ELECTIONS NEVER SEE. NoteFightElection tags
		// every fight assignment, but the C++ RetreatTask and idle states are
		// assigned outside our hooks -- the moment a unit STOPS fighting was
		// invisible, and every death read as bare "retreat" with no story.
		// R = entered retreat, O = entered other/idle; hp and depth at the
		// moment of the transition ride along (2s sampling resolution).
		if (bucket != gCombatBucket[i]) {
			if (bucket == 13)
				AppendFightHist(gCombatId[i], "R", FightCtx(u));
			else if (bucket == 14)
				AppendFightHist(gCombatId[i], "O", FightCtx(u));
			gCombatBucket[i] = bucket;
		}
	}
	gTrackedCost = trackedCost;
	if (ai.frame >= gNextCensusLog) {
		gNextCensusLog = ai.frame + 60 * SECOND;
		string cen = "";
		for (int b = 0; b < 15; ++b) {
			if ((cenHome[b] == 0) && (cenField[b] == 0))
				continue;
			const string nm = (b == 13) ? "ret" : ((b == 14) ? "oth" : ("f" + b));
			cen += " " + nm + "=" + cenHome[b] + "h/" + cenField[b] + "f";
		}
		// The tier inputs GetFacTierProbs uses (FactoryManager.cpp:1744):
		// min(metal,energy) income picks the tier row, and enemy AIR cost
		// above our AA cost silently switches the whole lab to its air table.
		AiLog(Factory::T() + "apex: army-census n=" + alive.length() + cen
			+ " | incM=" + formatFloat(Eco::MInc(), "", 0, 1)
			+ " incE=" + formatFloat(Eco::EInc(), "", 0, 1)
			+ " foeAir=" + formatFloat(aiEnemyMgr.GetEnemyCost(RT::AIR), "", 0, 0)
			// The aggression gate's two inputs and the enemy side's static
			// term, so a "we never attack" game can be attributed to the
			// reading rather than to the posture rules.
			+ " ourCost=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
			+ " foeMass=" + formatFloat(EnemyMassingThreat(), "", 0, 0)
			+ " foeStatic=" + formatFloat(aiEnemyMgr.GetEnemyCost(RT::STATIC), "", 0, 0));
	}

	WdPassPrep(allyPos);
	PackingCensus(alive, allyPos);
	const int reissue = int(ai.GetTunable("apex_withdraw_reissue", TUNE_WITHDRAW_REISSUE)) * SECOND;
	// A recall brings home what the threat there needs, not the whole front:
	// attackers already home-side count first, then each recalled unit.
	const float recallFwd = ai.GetTunable("apex_recall_home_fwd", TUNE_RECALL_HOME_FWD);
	float recallHave = -1.f;
	gHoldHomePass = -1;
	for (uint j = 0; j < alive.length(); ++j) {
		CCircuitUnit@ u = alive[j];
		const int i = aliveSlot[j];
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::FIGHTER))
			continue;
		const int ft = t.GetFightType();
		// ATTACK and RAID are the committed ones -- but DEFEND belongs here too,
		// and is in fact the population that dies: CDefendTask sends its units
		// at whatever is threatening us, so a pooling group does NOT stay on the
		// clamped anchor and can be drawn into a fight far from any cover. The
		// measured retreat deaths were 186 defend-pool units and no attackers.
		// Scouts are excluded: being out there is their job.
		if ((ft != Task::FightType::ATTACK) && (ft != Task::FightType::RAID)
			&& (ft != Task::FightType::DEFEND))
		{
			continue;
		}
		// CHARGERS AND COLOSSI ARE NEVER PULLED BACK. apexearth 2026-08-29:
		// "they try to charge in on the enemy and break through defenses...
		// they shouldn't be distracted by every little unit that comes up on
		// them. They should just keep moving forward." They deliver value by
		// arriving; a local-odds recall mid-march is the distraction in
		// reverse. Same class test as the C++ colossus targeting.
		if ((u.circuitDef !is null)
			&& (IsChargerDef(u.circuitDef)
				|| (u.circuitDef.costM >= ai.GetTunable("apex_super_cost", TUNE_SUPER_COST))))
		{
			continue;
		}
		const AIFloat3 p = allyPos[j];
		// THE DEFEND LEASH. Every suicide poke this project has reconstructed
		// is a DEFEND-pool member that waded to the enemy base: CDefendTask
		// chases whatever threatened us with no notion of how far it has
		// walked. A defend unit standing on THEIR influence past the front is
		// in the wrong place by the task's own meaning, whatever the local
		// odds -- recall it before asking whether it is winning.
		bool leash = false;
		if (ft == Task::FightType::DEFEND) {
			leash = (Military::ForwardFraction(p)
					> ai.GetTunable("apex_defend_leash", TUNE_DEFEND_LEASH))
				&& (ai.GetNetInflAt(p) < 0.f);
		}
		// THE COMMIT CHOICE. apexearth 2026-08-21, watching our base take hits
		// for minutes while the army "roamed around ... without getting anything
		// useful done": an attacking squad comes home. BaseUnderAttack() is our own
		// physical enemy presence at home, not a clock, so this only fires while
		// the threat is actually standing there.
		bool recallHome = false;
		// ...while what stands at home cannot answer what is there
		// (HoldHome, reading the buildings dying there as well as the
		// enemies seen). His rule: armies ignore enemies under half their
		// strength unless defending the home base.
		if (((ft == Task::FightType::ATTACK) || (ft == Task::FightType::RAID))
			&& (ai.GetTunable("apex_recall_home", TUNE_RECALL_HOME) > 0.f)
			&& Builder::gHomeSet && Builder::BaseUnderAttack()
			&& HoldHomeOnce())
		{
			recallHome = (Military::ForwardFraction(p) > recallFwd) && ArrivesInTime(p);
			if (recallHome && (recallHave < 0.f)) {
				recallHave = gHoldHeldM;
				for (uint h = 0; h < alive.length(); ++h) {
					IUnitTask@ th = alive[h].task;
					if ((th is null) || (th.GetType() != Task::Type::FIGHTER)
						|| (alive[h].circuitDef is null))
						continue;
					const int fh = th.GetFightType();
					if (((fh == Task::FightType::ATTACK) || (fh == Task::FightType::RAID))
						&& (Military::ForwardFraction(allyPos[h]) <= recallFwd))
						recallHave += alive[h].circuitDef.costM;
				}
			}
			if (recallHome) {
				if ((u.circuitDef is null) || (recallHave >= HoldNeedFor(int(u.circuitDef.id))))
					recallHome = false;
				else
					recallHave += u.circuitDef.costM;
			}
		}
		float odds = 0.f;
		const bool outgunned = OutgunnedHere(u, p, allyPos, allyPow, odds);
		float tLost = 0.f;
		float tKilled = 0.f;
		const bool losingFight = LosingFightHere(p, tLost, tKilled);
		// PRE-CONTACT CONSOLIDATION. apexearth, watching a mace and a rocket
		// bot die to four thugs: "a 2v4 wasn't a winning fight and we took
		// it anyways." The log's verdict on that fight: every unit died ON
		// the retreat task, W'd at FULL health -- once a pack is in weapon
		// range no order disengages you. The only working answer is before
		// contact: while the approach tracker holds a group carrying more
		// metal than stands beside this defender, fall back to the rally NOW
		// and meet them as a group or behind guns. Metal against metal, the
		// tracker's own currency.
		bool consolidate = false;
		if ((ft == Task::FightType::DEFEND)
			&& (ai.frame - Military::gIncomingAt < 15 * SECOND)
			&& OnMap(Military::gIncomingPos))
		{
			const float packD = p.distance2D(Military::gIncomingPos);
			if (packD < ai.GetTunable("apex_consolidate_r", TUNE_CONSOLIDATE_R)) {
				float nearM = 0.f;
				gWdAlly.Query(p.x, p.z, gWdR);
				for (uint h2 = 0; h2 < gWdAlly.hit.length(); ++h2) {
					const uint i2 = uint(gWdAlly.hit[h2]);
					if (allyPos[i2].SqDistance2D(p) <= gWdR2)
						nearM += allyCost[i2];
				}
				consolidate = nearM
						* ai.GetTunable("apex_consolidate_edge", TUNE_CONSOLIDATE_EDGE)
						< Military::gIncomingCost;
			}
		}
		// A LOST FIGHT ENDS AS A TASK, NOT AS A CROWD OF ORDERS. The per-unit
		// pull-back measurably fails: the W order is one-shot and the task
		// re-asserts every tick, so units die in place ping-ponging or
		// walking the wrong way, at full hp. Aborting the task is
		// the C++ attack-break's own shape -- every member re-elects at once,
		// pools at home behind the massing bar, and leaves together with the
		// next real group. ATTACK/RAID only: a home DEFEND pool must keep
		// fighting, and chargers/colossi were already exempted above.
		// MEASURED AND REVERTED TO OPT-IN (winrate6, 8+8 decision-length
		// games): 37 aborts, combined 1W-11L against iteration 4's 4W-10L,
		// Glacier trade 0.597 -> 0.348. The ledger reads "losing" transiently
		// in any bloody attrition fight, and aborting mid-commitment throws
		// away units already engaged -- the retreat-death shape at squad
		// scale. Default 0; the arm stays for A/B.
		if ((ai.GetTunable("apex_fight_abort", TUNE_FIGHT_ABORT) > 0.f)
			&& losingFight
			&& ((ft == Task::FightType::ATTACK) || (ft == Task::FightType::RAID))
			&& (ai.frame >= gNextTaskAbort))
		{
			gNextTaskAbort = ai.frame + 5 * SECOND;
			AppendFightHist(int(u.id), "A", FightCtx(u));
			AiLog(Factory::T() + "apex: fight-abort "
				+ ((u.circuitDef !is null) ? u.circuitDef.GetName() : "?")
				+ " at=" + int(p.x) + "," + int(p.z)
				+ " trade=" + int(tLost) + ":" + int(tKilled)
				+ " -- task re-pools");
			t.Abort();
			continue;
		}
		if (!leash && !recallHome && !outgunned && !losingFight
			&& !consolidate && !LosingHere(p))
			continue;
		// THE MEXES UNDER OUR FEET ARE WORTH THE FIGHT (apexearth 2026-09-19,
		// watching: the enemy took the middle mexes, we were contesting them,
		// "we decided to retreat and then they ended up keeping those mexes
		// and using that metal advantage to win"). Influence and an incoming
		// group are the enemy ARRIVING on contested ground; at odds near
		// parity a unit within its own reach of a spot we hold or could
		// claim stands, so the cons can take it. Being outgunned, losing
		// the trade, the leash and a base under attack still pull it back.
		if (!leash && !recallHome && !outgunned && !losingFight
			&& (ai.GetTunable("apex_hold_mex_ground", TUNE_HOLD_MEX_GROUND) > 0.f)
			&& (u.circuitDef !is null)
			&& Market::HeldOrOpenSpotNear(p, Catalog::gMaxRange[int(u.circuitDef.id)] + 64.f))
		{
			++gHeldGround;
			if (ai.frame >= gNextHeldGroundLog) {
				gNextHeldGroundLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: hold-ground "
					+ u.circuitDef.GetName() + " at=" + int(p.x) + "," + int(p.z)
					+ (consolidate ? " pack" : " infl") + " -- " + gHeldGround + " held");
			}
			continue;
		}
		// WE ARE FAR STRONGER (apexearth 2026-09-30: "we're so powerful that
		// it doesn't even matter"): while our side's army is at least twice
		// theirs, a local deficit is a gap reinforcements close, not a reason
		// to walk away. His 8v8 read 98k against 7-10k and still pulled units
		// home from the enemy's side of the map.
		if (!leash && !recallHome && SideDwarfs()) {
			++gHeldStrong;
			if (ai.frame >= gNextHeldStrongLog) {
				gNextHeldStrongLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: hold-strong at=" + int(p.x) + "," + int(p.z)
					+ " ours=" + int(OurArmyNow()) + " theirs=" + int(FoeMobileMassing())
					+ " -- " + gHeldStrong + " held");
			}
			continue;
		}
		// COMMIT COHERENCE. A unit whose ground the enemy's guns already
		// cover does not get a solo pull-out: the order is a rout, not a
		// retreat (wdeaths: 43% die in place ping-ponging the re-asserting
		// task, 34% die walking away rear-shot, median 15s order-to-death
		// at full hp), and each leaver strands the ones still firing.
		// apexearth, watching the arena: "some of our units keep fighting
		// while others are running away... this splits our forces and we
		// get clobbered because of it." Strategic recalls (leash, recall,
		// consolidate) keep working where they work: out of contact.
		if ((ai.GetTunable("apex_hold_committed", TUNE_HOLD_COMMITTED) > 0.f)
			&& (ai.GetUnitThreatAt(u, p) > 0.f))
		{
			++gHeldCommitted;
			if (ai.frame >= gNextHoldLog) {
				gNextHoldLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: withdraw-hold in-contact -- "
					+ gHeldCommitted + " held, " + gWithdrawn + " ordered");
			}
			continue;
		}
		if (ai.frame - gCombatSent[i] < reissue)
			continue;
		AIFloat3 back;
		// A recall goes to the fight at home, on one point so it does not
		// arrive piecemeal; a pack reforms at the doorway we hold.
		if (recallHome) {
			back = HomeFightPos();
		} else if (consolidate) {
			if (!RallySpot(p, back))
				continue;
		} else {
			AIFloat3 gun, held;
			const bool hasGun = FallbackSpot(p, gun);
			const bool hasHeld = HeldGroundBack(p, held);
			if (!hasGun && !hasHeld)
				continue;
			back = (hasHeld && (!hasGun || (held.distance2D(p) < gun.distance2D(p)))) ? held : gun;
		}
		// A point the unit cannot walk to parks it against the nearest cliff.
		if ((u.circuitDef !is null)
			&& !ai.CanDefReachAt(Catalog::Def(int(u.circuitDef.id)), p, back, 64.f))
			continue;
		// Already behind the guns: nothing to do but fight.
		if (back.distance2D(p) < ai.GetTunable("apex_withdraw_near", TUNE_WITHDRAW_NEAR))
			continue;
		u.CmdMoveTo(back);
		gCombatSent[i] = ai.frame;
		++gWithdrawn;
		AppendFightHist(int(u.id), recallHome ? "H" : "W", FightCtx(u));
		if (ai.frame >= gNextWithdrawLog) {
			gNextWithdrawLog = ai.frame + 15 * SECOND;
			// Intent ping, on the same throttle as the log: withdrawals are
			// per-unit orders no C++ task pings, so without this they are the
			// largest unexplained movement on the map.
			if (ai.GetTunable("apex_ping", TUNE_PING) > 0.f)
				AiAddPoint(p, "WDRAW " + (leash ? "leash" : (recallHome ? "recall"
					: (outgunned ? ("odds " + formatFloat(odds, "", 0, 1))
					: (losingFight ? "trade" : (consolidate ? "pack" : "infl"))))));
			AiLog(Factory::T() + "apex: withdraw "
				+ ((u.circuitDef !is null) ? u.circuitDef.GetName() : "?")
				+ " at=" + int(p.x) + "," + int(p.z)
				+ (leash ? " leash" : (recallHome ? " recall-home"
					: (outgunned ? (" odds=" + formatFloat(odds, "", 0, 2))
					: (losingFight ? (" trade=" + int(tLost) + ":" + int(tKilled))
					: (consolidate ? " pack" : " infl")))))
				+ " -> " + int(back.x) + "," + int(back.z)
				+ " -- " + gWithdrawn + " orders so far, "
				+ gCombatId.length() + " tracked");
		}
	}
}

}  // namespace Military
