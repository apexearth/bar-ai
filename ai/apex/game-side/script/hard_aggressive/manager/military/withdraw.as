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
int gNextWithdraw = 0;
int gWithdrawn = 0;
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
}

// The nearest gun of ours, stepped back toward home so the unit stands BEHIND
// it: the tower is between the unit and whatever is chasing it, which is the
// whole point -- it soaks while we keep shooting.
bool FallbackSpot(const AIFloat3& in from, AIFloat3& out at)
{
	float best = -1.f;
	AIFloat3 tower;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (!OnMap(gFencePos[i]))
			continue;
		if (i < gFenceDef.length()) {
			const CCircuitDef@ d = gFenceDef[i];
			// A radar mast or a jammer is not cover.
			if ((d !is null) && (d.GetSurfThreat() <= 0.f))
				continue;
		}
		const float d2 = gFencePos[i].distance2D(from);
		if ((best < 0.f) || (d2 < best)) {
			best = d2;
			tower = gFencePos[i];
		}
	}
	if (best < 0.f) {
		// No guns anywhere: home is still better than dying in the open.
		if (!Builder::gHomeSet)
			return false;
		at = Builder::gHomePos;
		return OnMap(at);
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

// The influence test above LAGS: influence is built from standing presence, so
// at the contact line it reads ~0 until our units are already dying (measured
// 2026-08-20: a 9-unit squad fed itself to a commander over 36 seconds and the
// first withdraw order came after the fifth death). This is the leading
// version of the same question: the threat map already knows what is standing
// there, so compare it against what WE have standing nearby -- our combat
// units plus our own towers -- and call the spot lost when they outgun us by
// the margin. Threat-map values and GetSurfThreat are the same scale.
bool OutgunnedHere(CCircuitUnit@ u, const AIFloat3& in p,
	const array<AIFloat3>@ allyPos, const array<float>@ allyPow, float& out oddsFor)
{
	const float enemyT = ai.GetUnitThreatAt(u, p);
	oddsFor = 0.f;
	if (enemyT <= 0.f)
		return false;
	const float r = ai.GetTunable("apex_withdraw_ally_r", TUNE_WITHDRAW_ALLY_R);
	const float r2 = r * r;
	float ours = 0.f;
	for (uint i = 0; i < allyPos.length(); ++i) {
		if (allyPos[i].SqDistance2D(p) <= r2)
			ours += allyPow[i];
	}
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (i >= gFenceDef.length())
			break;
		const CCircuitDef@ d = gFenceDef[i];
		if ((d !is null) && (d.GetSurfThreat() > 0.f)
			&& (gFencePos[i].SqDistance2D(p) <= r2))
		{
			ours += d.GetSurfThreat();
		}
	}
	oddsFor = (ours > 0.f) ? (enemyT / ours) : 99.f;
	return enemyT > ours * ai.GetTunable("apex_withdraw_odds", TUNE_WITHDRAW_ODDS);
}

void UpdateWithdraw()
{
	if ((ai.frame < gNextWithdraw) || !ApexActive())
		return;
	gNextWithdraw = ai.frame + 2 * SECOND;
	if (ai.GetTunable("apex_withdraw", TUNE_WITHDRAW) <= 0.f)
		return;
	// A committed finisher is the one time being out there is the decision.
	if (gKilling)
		return;

	// Pass 1: prune the dead, cache everyone's position and power once --
	// pass 2 sums local strength around each candidate from this cache.
	array<AIFloat3> allyPos;
	array<float> allyPow;
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
			continue;
		}
		const AIFloat3 p = u.GetPos(ai.frame);
		if (!OnMap(p))
			continue;
		allyPos.insertLast(p);
		allyPow.insertLast((u.circuitDef !is null) ? u.circuitDef.GetSurfThreat() : 0.f);
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
			+ " | incM=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " incE=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 1)
			+ " foeAir=" + formatFloat(aiEnemyMgr.GetEnemyCost(RT::AIR), "", 0, 0)
			// The aggression gate's two inputs and the enemy side's static
			// term, so a "we never attack" game can be attributed to the
			// reading rather than to the posture rules (measured 2026-08-20:
			// gate said 9000 vs 3853 while the field was 6125 vs 7410).
			+ " ourCost=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
			+ " foeMass=" + formatFloat(EnemyMassingThreat(), "", 0, 0)
			+ " foeStatic=" + formatFloat(aiEnemyMgr.GetEnemyCost(RT::STATIC), "", 0, 0));
	}

	const int reissue = int(ai.GetTunable("apex_withdraw_reissue", TUNE_WITHDRAW_REISSUE)) * SECOND;
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
		const AIFloat3 p = allyPos[j];
		// THE DEFEND LEASH. Every suicide poke this project has reconstructed
		// is a DEFEND-pool member that waded to the enemy base (deaths at
		// fwd 0.8-0.93 with fhist=[f2...], battles.py 2026-08-20): CDefendTask
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
		float odds = 0.f;
		const bool outgunned = OutgunnedHere(u, p, allyPos, allyPow, odds);
		if (!leash && !outgunned && !LosingHere(p))
			continue;
		if (ai.frame - gCombatSent[i] < reissue)
			continue;
		AIFloat3 back;
		if (!FallbackSpot(p, back))
			continue;
		// Already behind the guns: nothing to do but fight.
		if (back.distance2D(p) < ai.GetTunable("apex_withdraw_near", TUNE_WITHDRAW_NEAR))
			continue;
		u.CmdMoveTo(back);
		gCombatSent[i] = ai.frame;
		++gWithdrawn;
		AppendFightHist(int(u.id), "W");
		if (ai.frame >= gNextWithdrawLog) {
			gNextWithdrawLog = ai.frame + 15 * SECOND;
			AiLog(Factory::T() + "apex: withdraw "
				+ ((u.circuitDef !is null) ? u.circuitDef.GetName() : "?")
				+ " at=" + int(p.x) + "," + int(p.z)
				+ (leash ? " leash" : (outgunned ? (" odds=" + formatFloat(odds, "", 0, 2)) : " infl"))
				+ " -- " + gWithdrawn + " orders so far, "
				+ gCombatId.length() + " tracked");
		}
	}
}

}  // namespace Military
