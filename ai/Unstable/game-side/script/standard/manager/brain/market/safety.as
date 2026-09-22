namespace Market {
//------------------------------------------------------------------------------
// COMMANDER SELF-PRESERVATION. Restored from rules_commander.as, which the
// overhaul kill removed wholesale; only the safety layer comes back, because
// the Brain now owns every question about what the commander should BUILD.
// Staying alive is not a Want -- it has no gain and no site -- so it runs
// ahead of the auction rather than inside it.
//------------------------------------------------------------------------------

const float COM_RETREAT_HEALTH = 0.85f;

int gNextCommCautionLog = 0;
int gCommHoldId = -1;
int gNextCommHoldLog = 0;
int gNextCommFleeLog = 0;
int gNextCommHpLog = 0;
int gNextCommFightLog = 0;
int gCommEngageAt = -99999;

// THE LAST COMMANDER IS CAREFUL (apexearth 2026-09-21: in a 1v1 his death is
// the game; in an 8v8 a commander may be spent to kill an army). An ally
// that publishes a live commander, or one that never publishes (a human, a
// stock AI), counts as holding one.
array<Id>@ gComMates = null;
int gLastComAt = -999999;
bool gLastComVal = true;
void PublishCommanderAlive()
{
	ai.PublishTeamValue("comalive", float(ai.frame));
}
bool LastCommander()
{
	if (ai.frame - gLastComAt < 5 * SECOND)
		return gLastComVal;
	gLastComAt = ai.frame;
	if (gComMates is null)
		@gComMates = ai.GetTeamIds();
	gLastComVal = true;
	if (gComMates is null)
		return gLastComVal;
	for (uint m = 0; m < gComMates.length(); ++m) {
		const int t = int(gComMates[m]);
		if (t == ai.teamId)
			continue;
		const float f = ai.ReadTeamValue(t, "comalive", -1.f);
		if ((f < 0.f) || (ai.frame - int(f) < 60 * SECOND)) {
			gLastComVal = false;
			break;
		}
	}
	return gLastComVal;
}
int gCommCautionWas = -1;

// INSTRUMENT (temporary): is the commander standing with nothing in his engine
// command queue, and for how long at a stretch? Sampled from AiUpdate, so one
// sample a second. `act` is the C++ black box -- the last orders that actually
// reached the engine, second-stamped -- so a stall with no new entries means
// the orders were suppressed before they were sent, not that none were made.
AIFloat3 gCwPos;
bool gCwHave = false;
int gCwStillFrom = -1;
int gNextCwPosLog = 0;
int gCwWorst = 0;
int gCwStill = 0;
int gCwSamples = 0;
int gCwEngageStill = 0;
int gCwQzero = 0;
int gCwQpos = 0;
int gNextCwLog = 0;

void CommWatch()
{
	CCircuitUnit@ u = Builder::gComm;
	if ((u is null) || (u.circuitDef is null))
		return;
	const AIFloat3 p = u.GetPos(ai.frame);
	const float moved = gCwHave ? p.distance2D(gCwPos) : 999.f;
	gCwPos = p;
	gCwHave = true;
	// Where he is, sampled: expect.py reads how far forward he spends the game.
	if (ai.frame >= gNextCwPosLog) {
		gNextCwPosLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: com-pos t=" + ai.teamId
			+ " at=" + int(p.x) + "," + int(p.z)
			+ " fwd=" + formatFloat(Military::ForwardFraction(p), "", 0, 2)
			+ " home=" + (Builder::gHomeSet ? int(p.distance2D(Builder::gHomePos)) : -1)
			+ " far=" + (ComFar(p) ? 1 : 0));
	}
	IUnitTask@ t = u.task;
	const int tt = (t is null) ? -1 : int(t.GetType());
	const int q = u.CmdQueueSize();
	if (q > 0) ++gCwQpos; else ++gCwQzero;
	++gCwSamples;
	// Not moving is still, orders or not: a penned commander holds a move
	// order it cannot execute, and the q<=0 test read him as busy for
	// seventeen minutes.
	const bool still = (moved < 8.f);
	if (still) {
		++gCwStill;
		if (gCwStillFrom < 0)
			gCwStillFrom = ai.frame;
		const int run = ai.frame - gCwStillFrom;
		if (run > gCwWorst)
			gCwWorst = run;
		if (ai.frame - gCommEngageAt < 30 * SECOND)
			++gCwEngageStill;
		// One line per stall, at three seconds in and then every fifteen: the
		// first says it started, the rest say it is still going.
		if ((run == 3 * SECOND) || ((run > 3 * SECOND) && ((run % (15 * SECOND)) < SECOND))) {
			AiLog(Factory::T() + "apex: com-still " + formatFloat(float(run) / 30.f, "", 0, 1)
				+ "s task=" + tt + " q=" + q
				+ " sinceEngage=" + ((gCommEngageAt > 0) ? int((ai.frame - gCommEngageAt) / 30) : -1)
				+ " at=" + int(p.x) + "," + int(p.z)
				+ " site=" + ((t is null) ? "-" : (int(t.GetBuildPos().x) + "," + int(t.GetBuildPos().z)
					+ "@" + int(p.distance2D(t.GetBuildPos()))))
				+ " hp=" + int(u.GetHealthPercent() * 100.f)
				+ " act=" + u.GetActTrace());
		}
	} else {
		gCwStillFrom = -1;
	}
	if (ai.frame >= gNextCwLog) {
		gNextCwLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: com-watch still=" + gCwStill + "/" + gCwSamples
			+ " q0=" + gCwQzero + " q+=" + gCwQpos
			+ " worst=" + formatFloat(float(gCwWorst) / 30.f, "", 0, 1) + "s"
			+ " postEngage=" + gCwEngageStill);
		gCwStill = 0;
		gCwSamples = 0;
		gCwQzero = 0;
		gCwQpos = 0;
		gCwWorst = 0;
		gCwEngageStill = 0;
	}
}

bool CommRules()
{
	return ai.GetTunable("apex_comm_rules", TUNE_COMM_RULES) > 0.f;
}

// HOW BRAVE THE COMMANDER MAY BE, read off what is fielded against him
// (apexearth: "Our commander is too brave when lots of T2 and T3 are on the
// field. He should run but he doesn't"). The stake is his own cost, so both
// bars scale with the game instead of naming a number.
bool CommCaution(CCircuitUnit@ unit)
{
	const float mine = unit.circuitDef.costM;
	if (mine <= 0.f)
		return false;
	// Our OWN T2 standing is caution enough, unconditionally. The enemy
	// readings below are LOS-accumulated and read "safe" exactly when blind:
	// a Glacier 1v1 logged ZERO caution/flee events in 27 minutes against a
	// T2 enemy, and the commander died walking to a mid-map job at fwd 0.35.
	// By our own T2 his build share has collapsed while his death still ends
	// the game -- progression-anchored, no clock, no sensing required. The
	// enemy clauses remain as PRE-T2 escalators (a heavy rush earns caution
	// before we tech).
	if (Factory::gHaveT2)
		return true;
	const float heavies = aiEnemyMgr.GetEnemyCost(RT::HEAVY)
			+ aiEnemyMgr.GetEnemyCost(RT::SUPER);
	if (heavies >= mine * ai.GetTunable("apex_comm_heavy_frac", TUNE_COMM_HEAVY_FRAC))
		return true;
	// Their metal at his own strength-per-metal: a field of heavier-than-mean
	// units reads bigger than its bill, a field of scouts smaller.
	const float commQ = UnitStrength(int(unit.circuitDef.id)) / mine;
	return Military::FoeMobileMassing() * FoeQualityM() / ((commQ > 0.f) ? commQ : 1.f)
			>= mine * ai.GetTunable("apex_comm_mass_mult", TUNE_COMM_MASS_MULT);
}

// Influence at the position AND four compass points around it: a cautious
// commander reacts to danger approaching, not danger already on his tile.
// The tile sample alone is the clean-until-dead trap -- one measured game
// read threat 0.00 at full health and lost him 930 frames later.
float RingInflMax(const AIFloat3& in pos, float r)
{
	float best = ai.GetEnemyInflAt(pos);
	for (int i = 0; i < 4; ++i) {
		AIFloat3 p = pos;
		if (i == 0)      p.x += r;
		else if (i == 1) p.x -= r;
		else if (i == 2) p.z += r;
		else             p.z -= r;
		if (!OnMap(p))
			continue;
		const float v = ai.GetEnemyInflAt(p);
		if (v > best)
			best = v;
	}
	return best;
}

// Returns a task when the commander should be saving himself instead of
// working, else null. MUST be consulted before Decide's finish-what's-started
// early return: a commander with progress on a frame would otherwise never
// reach this at all.
IUnitTask@ CommanderSafety(CCircuitUnit@ unit)
{
	if ((unit is null) || !CommRules())
		return null;
	if (!unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return null;

	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return null;
	const bool caution = CommCaution(unit);
	// The flip and its inputs: commander.as's CAUTIOUS/loose heartbeat reads a
	// different test and said "loose" through a game this one held from 3.4 m.
	if (int(caution ? 1 : 0) != gCommCautionWas) {
		gCommCautionWas = caution ? 1 : 0;
		AiLog(Factory::T() + "apex: commander caution=" + (caution ? "on" : "off")
			+ " haveT2=" + (Factory::gHaveT2 ? 1 : 0)
			+ " heavies=" + formatFloat(aiEnemyMgr.GetEnemyCost(RT::HEAVY) + aiEnemyMgr.GetEnemyCost(RT::SUPER), "", 0, 0)
			+ " foeMobile=" + formatFloat(Military::FoeMobileMassing(), "", 0, 0)
			+ " q=" + formatFloat(FoeQualityM(), "", 0, 2));
	}
	// "If enemy is running away, fine - let them" (apexearth). Hold position
	// shoots whatever reaches him and never walks after anything; maneuvre
	// let the engine chase to leash+range from his last order, and a
	// move-failed builder used to be switched to roam for the whole game.
	if (int(unit.id) != gCommHoldId) {
		unit.SetMoveState(0);
		gCommHoldId = int(unit.id);
		AiLog("apex: commander hold-position t=" + ai.teamId);
	}

	// HE IS A BADASS, SO LET HIM BE ONE. This file only ever taught the
	// commander to run (apexearth, twice: "does our commander only have flee
	// logic and no fight logic? ... ours is playing like a coward. He should
	// only be careful late game when really powerful units are on the field").
	//
	// T1 AT THE BASE IS HIS TO KILL, cautious or not, scratched or not
	// (apexearth 2026-09-20, watching artillery pound a base: "all the
	// commander had to do was walk up to them and D-gun them... there's a good
	// chance he'll die, but if he doesn't, he will have lost his entire base").
	// The gates that used to hold him back were measured at zero engagements
	// in his 4v4: caution is true from minute 3 of any team game (four
	// enemies' mobile mass against one commander), and a strength sum with the
	// D-gun excluded reads five T1 as more than him. The tier of what is
	// attacking is his test, so it is the test here. T2 and up keep the old
	// bars: not cautious, unhurt, and outweighing them.
	if (ai.GetTunable("apex_comm_fight", TUNE_COMM_FIGHT) > 0.f)
	{
		// His strength at his current hp, against theirs -- not metal against
		// metal (apexearth, docs/24). The kill is still WORTH metal below.
		const float mine = UnitStrength(int(unit.circuitDef.id)) * unit.GetHealthPercent();
		const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
		const bool heavyOk = !caution && (unit.GetHealthPercent() >= COM_RETREAT_HEALTH);
		PublishCommanderAlive();
		// T1 keeps the T2 bar's strength and health halves for the last
		// commander; the caution half would refuse every raid once their T2
		// is on the field.
		const bool lastCom = LastCommander();
		const bool t1Ok = !lastCom || ((unit.GetHealthPercent() >= COM_RETREAT_HEALTH));
		const float leash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
		// The enemy groups themselves, not the PUSH sensor: that one wants a
		// closing formation of real size and never fired once in a 1v1 (0
		// engagements, measured), while the raids actually eating our mexes are
		// two units. Nearest group with something of ours inside ITS reach.
		AIFloat3 foeAt;
		bool fresh = false;
		float bestD = -1.f;
		float bestCost = 0.f;
		float bestStake = 0.f;
		float bestDpsM = 0.f;
		float bestApp = 0.f;
		float bestStr = 0.f;
		int bestTier = 0;
		int bestN = 0;
		const int nG = aiEnemyMgr.GetEnemyGroupCount();
		for (int gi = 0; gi < nG; ++gi) {
			const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
			if (!OnMap(gp) || (Military::ForwardFraction(gp) >= 0.5f))
				continue;
			// The highest tier among its mobile members; a group of nothing
			// mobile (a turret creeping in) is not his to walk at.
			int tier = 0;
			int nMob = 0;
			float dps = 0.f;
			const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
			for (int k = 0; k < nU; ++k) {
				const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
				if (!Catalog::ValidId(d) || !Catalog::gMobile[d])
					continue;
				++nMob;
				dps += Catalog::gDps[d];
				const int t = DefTier(d);
				if (t > tier)
					tier = t;
			}
			if (nMob == 0)
				continue;
			// HE DEFENDS WHAT WE OWN, he does not go on tour. "Our half of the
			// map" was too loose a leash: he chased to the midpoint, chained
			// the next target from there and ended up duelling the enemy
			// commander in their base while ours stood empty (apexearth,
			// watched -- we won that game, which is not evidence it was right).
			// The bar is our own property inside THEIR reach: artillery shells
			// the base from past the threat radius, and standing outside the
			// home leash by exactly its range is how it does that.
			float reach = aiEnemyMgr.GetEnemyGroupRange(gi);
			if (reach < r)
				reach = r;
			const float stake = StakeAt(gp, reach);
			if (stake <= 0.f)
				continue;
			// Half the leash forward is where his claims stop (ComFar), so
			// it is where his chases stop too: a lone Pawn 2,646 out was
			// worth a 141 s walk by this test, and the base stood empty.
			if (ComFar(gp) && (!Builder::gHomeSet
				|| (gp.distance2D(Builder::gHomePos) > 0.5f * leash + reach)))
				continue;
			const float gStr = EnemyGroupStrength(gi);
			if ((tier >= 2) && (!heavyOk || (gStr > mine)))
				continue;
			if ((tier < 2) && (!t1Ok || (lastCom && (gStr > mine))))
				continue;
			// A FIGHT HE LOSES IS A TRADE, and the trade has to pay: what
			// he kills before he falls (Lanchester's square law on the two
			// strengths) or what his walk saves must be worth more than he is.
			if ((tier < 2) && !lastCom && (gStr > mine) && (mine > 0.f)) {
				const float rr = mine / gStr;
				const float killed = 1.f - sqrt(1.f - rr * rr);
				const float him = Catalog::gCostM[int(unit.circuitDef.id)];
				if ((killed * aiEnemyMgr.GetEnemyGroupCost(gi) < him) && (stake < him))
					continue;
			}
			// Coming at us, or leaving: a group walking away is let go.
			const AIFloat3 vv = aiEnemyMgr.GetEnemyGroupVelVec(gi);
			AIFloat3 toMe = here - gp;
			toMe.SafeNormalize2D();
			const float app = vv.x * toMe.x + vv.z * toMe.z;
			if (app < -1.f)
				continue;
			const float dd = here.distance2D(gp);
			if ((bestD < 0.f) || (dd < bestD)) {
				bestD = dd;
				bestCost = aiEnemyMgr.GetEnemyGroupCost(gi);
				bestStake = stake;
				bestDpsM = dps * StructureMetalPerHp();
				bestApp = app;
				bestStr = gStr;
				bestTier = tier;
				bestN = nMob;
				foeAt = gp;
				fresh = true;
			}
		}
		if (fresh) {
			// WORTH THE WALK. His time is priced like any builder-second, so a
			// detour is only justified when it denies more metal than it costs
			// -- otherwise he trails a 1-metal scout around the base forever
			// (measured: 6 engagements, every one against "1 metal"). What the
			// walk denies is the raiders AND what they destroy while he walks:
			// their damage per second in metal, so five artillery pieces shelling
			// the base outweigh the trip and a flea sitting in a corner does not.
			// No new constant: Wage() is the market's own price for his time.
			const float spd = Catalog::gSpeed[int(unit.circuitDef.id)];
			// The trip is the CATCH at closing speed plus the walk back; a group
			// moving as fast as he does is never caught (apexearth: "enemy pawns
			// are able to distract our commander for minutes").
			const float closing = spd + bestApp;
			const float tripS = ((spd > 1.f) && (closing > 1.f))
					? (bestD / closing + bestD / spd) : 1e9f;
			// They cannot destroy more than is in their reach, however long
			// the walk: unbounded, a far group read as the richer target.
			const float denied = bestDpsM * tripS;
			const float theirs = bestCost + ((denied < bestStake) ? denied : bestStake);
			const float worthIt = Wage() * tripS;
			if (theirs > worthIt) {
				// A TASK, NOT A MOVE ORDER. CmdMoveTo from here was overridden by
				// the build task Decide handed back on the same election -- three
				// engagements logged, 15-45 s standing still after each, zero
				// kills (measured 2026-09-20). A builder patrol is a task the C++
				// keeps, it fights whatever it meets, and it carries the D-gun
				// action that walks him in on a target. Held across re-elections
				// while it still points at the group.
				IUnitTask@ held = unit.task;
				if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
					&& (held.GetBuildType() == Task::BuildType::PATROL)
					&& (held.GetBuildPos().distance2D(foeAt) < 300.f))
				{
					return held;
				}
				const int dwell = int((bestD / ((spd > 1.f) ? spd : 1.f) + 15.f) * SECOND);
				IUnitTask@ pt = aiBuilderMgr.Enqueue(TaskB::Patrol(
						Task::Priority::HIGH, foeAt, dwell));
				if (pt !is null) {
					if (ai.frame >= gNextCommFightLog) {
						gNextCommFightLog = ai.frame + 15 * SECOND;
						AiLog("apex: commander engaging -- T" + bestTier + " x" + bestN + ", "
							+ formatFloat(bestCost, "", 0, 0) + " metal killing "
							+ formatFloat(bestDpsM, "", 0, 1) + " m/s at "
							+ formatFloat(bestStake, "", 0, 0) + " of ours,"
							+ " str " + formatFloat(bestStr, "", 0, 2) + " vs his " + formatFloat(mine, "", 0, 2)
							+ " hp=" + int(unit.GetHealthPercent() * 100.f)
							+ (caution ? " cautious" : "") + (lastCom ? " last" : "")
							+ " approaching " + formatFloat(bestApp, "", 0, 0) + "/s at " + int(bestD)
							+ " worth " + formatFloat(theirs, "", 0, 0) + "/" + formatFloat(worthIt, "", 0, 0));
					}
					gCommEngageAt = ai.frame;
					return pt;
				}
			}
		}
	}

	// A CAUTIOUS COMMANDER DOES NOT WORK FORWARD AT ALL. No influence needed:
	// standing on forward ground while heavies roam is the mistake, not the
	// contact that follows it.
	if (caution) {
		const float fwd = Military::ForwardFraction(here);
		if (fwd > ai.GetTunable("apex_comm_fwd_cap", TUNE_COMM_FWD_CAP)) {
			if (ai.frame >= gNextCommCautionLog) {
				gNextCommCautionLog = ai.frame + 15 * SECOND;
				AiLog("apex: commander running -- heavies fielded, fwd="
					+ formatFloat(fwd, "", 0, 2));
			}
			IUnitTask@ run = Builder::Retreat(unit);
			if (run !is null)
				return run;
		}
	}

	// INFLUENCE, not ai.GetBuilderThreatAt: threat reads clean at the victim's
	// own tile while the killer shoots from range, and it is ~97% zero anyway.
	// Armed post-T2, or earlier once caution holds -- the commander is a strong
	// early unit and should stay active then.
	const float fleeInfl = (Factory::gHaveT2 || caution)
			? ai.GetTunable("apex_comm_flee_influence", TUNE_COMM_FLEE_INFLUENCE)
			: 0.f;
	if (fleeInfl > 0.f) {
		const float hereInfl = caution
				? RingInflMax(here, ai.GetTunable("apex_comm_flee_ring", TUNE_COMM_FLEE_RING))
				: ai.GetEnemyInflAt(here);
		// Fleeing only helps when the ground fled TO is safer. With home just
		// as hot, "retreating" defends nothing -- fall through and keep working;
		// the wants' own site-safety vetoes steer the work off hot ground.
		// Compare strength (apexearth): what is actually near him against what
		// he is at this hp. A field he outguns is one he holds, not one he
		// hides from for 20 s at a time; influence with no seen mobile source
		// (a creeping turret, a unit under the fog) still moves him.
		float nearStr = 0.f;
		const float mineNow = UnitStrength(int(unit.circuitDef.id)) * unit.GetHealthPercent();
		if (hereInfl > fleeInfl) {
			const float fr = ai.GetTunable("apex_comm_flee_ring", TUNE_COMM_FLEE_RING);
			const int nG2 = aiEnemyMgr.GetEnemyGroupCount();
			for (int g2 = 0; g2 < nG2; ++g2) {
				const AIFloat3 gp2 = aiEnemyMgr.GetEnemyGroupPos(g2);
				if (OnMap(gp2) && (gp2.distance2D(here) <= fr))
					nearStr += EnemyGroupStrength(g2);
			}
		}
		const bool outgunned = (nearStr <= 0.f) || (nearStr > mineNow);
		// HE ONLY LEAVES GROUND THAT IS THEIRS (apexearth 2026-09-07, watching
		// him stand still from 5:20 to 12:10: "He had no good reason to run.
		// idk what jank stupid logic that is").
		//
		// The two sides of the old test read different populations at different
		// places. `hereInfl` is a max over a 600-elmo cross of the influence
		// map, which carries every enemy ever seen -- CEnemyManager retires a
		// ghost only after TWENTY game-minutes -- so it climbed 0.63 -> 8.04 ->
		// 33.05 -> 94.09 with nothing within 600 elmos of him, while `nearStr`
		// correctly read 0.0000 and `outgunned` defaults to true on a zero. The
		// "is home safer" clause compared that ring maximum against a single
		// point at home, so it could not refuse either. Structurally the test
		// could only ever say run, and it did, 24 times.
		//
		// SiteHot is this repo's own answer to the same question and every other
		// danger test already uses it: "theirs means stronger, not merely
		// present" -- both sides of the comparison read the same layer at the
		// same point. Standing in his own base among his own army and towers,
		// ours dominates and he stays; when a real push arrives, theirs exceeds
		// ours and he leaves that instant. No new number.
		const float allyHere = ai.GetAllyInflAt(here);
		const bool theirGround = ai.GetEnemyInflAt(here) > allyHere;
		if ((hereInfl > fleeInfl) && (!outgunned || !theirGround)
			&& (ai.frame >= gNextCommHoldLog)) {
			gNextCommHoldLog = ai.frame + 15 * SECOND;
			AiLog("apex: commander holding, enemy influence " + formatFloat(hereInfl, "", 0, 2)
				+ ", near str " + formatFloat(nearStr, "", 0, 4) + " vs his " + formatFloat(mineNow, "", 0, 4)
				+ ", ally " + formatFloat(allyHere, "", 0, 2)
				+ " vs theirs " + formatFloat(ai.GetEnemyInflAt(here), "", 0, 2));
		}
		if ((hereInfl > fleeInfl) && outgunned && theirGround)
		{
			if (ai.frame >= gNextCommFleeLog) {
				gNextCommFleeLog = ai.frame + 15 * SECOND;
				AiLog("apex: commander leaving, enemy influence "
					+ formatFloat(hereInfl, "", 0, 2) + " > "
					+ formatFloat(fleeInfl, "", 0, 2) + ", near str "
					+ formatFloat(nearStr, "", 0, 4) + " vs his "
					+ formatFloat(mineNow, "", 0, 4)
					// Both sides of the ground test, so a misfire is one line, not
					// a position trace (this one cost a whole session to find).
					+ ", ally " + formatFloat(allyHere, "", 0, 2)
					+ " vs theirs " + formatFloat(ai.GetEnemyInflAt(here), "", 0, 2)
					+ ", home " + formatFloat(ai.GetEnemyInflAt(Builder::gHomePos), "", 0, 2));
			}
			IUnitTask@ bail = Builder::Retreat(unit);
			if (bail !is null)
				return bail;
		}
	}

	// Damage already landed. Only keep forcing a flee while local threat is
	// real -- firing on health alone left him cowering at the back at 50%
	// (apexearth, watched).
	const float hp = unit.GetHealthPercent();
	if (hp < COM_RETREAT_HEALTH) {
		if (Builder::ThreatFor(unit, here) > Builder::CON_THREAT_VETO) {
			if (ai.frame >= gNextCommHpLog) {
				gNextCommHpLog = ai.frame + 20 * SECOND;
				AiLog("apex: commander retreating at "
					+ formatFloat(hp * 100.f, "", 0, 0) + "% health");
			}
			// CRITICAL: CRetreatTask walks to the haven, and the haven can BE
			// the ground being overrun -- watched, eight re-elections while
			// health fell 81% -> 40% -> dead in place. Below this bar he is
			// steered directly away from the enemy centroid instead, and the
			// null return keeps any task from walking him back into it.
			if (hp < ai.GetTunable("apex_comm_flee_hp", TUNE_COMM_FLEE_HP)) {
				AIFloat3 away = here - aiEnemyMgr.GetEnemyPos();
				if (away.SqLength2D() > NEAR_ZERO) {
					away.SafeNormalize2D();
					for (int step = 3; step >= 1; --step) {
						const AIFloat3 to = here + away * (250.f * float(step));
						if (OnMap(to)) {
							unit.CmdMoveTo(to);
							return null;
						}
					}
				}
			}
			IUnitTask@ hurt = Builder::Retreat(unit);
			if (hurt !is null)
				return hurt;
		}
	}
	return null;
}


}  // namespace Market
