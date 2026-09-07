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
	// CommCaution already IS "late game with heavies about", so its inverse is
	// exactly the window he should be fighting in. He goes at anything raiding
	// our own ground that is worth less than he is -- his own cost is the
	// measure, so this stops on its own once the field outgrows him. Standing
	// on them is enough: units fire at what is in range, and a D-gun is
	// point-blank anyway.
	if (!caution && (ai.GetTunable("apex_comm_fight", TUNE_COMM_FIGHT) > 0.f)
		&& (unit.GetHealthPercent() >= COM_RETREAT_HEALTH))
	{
		// His strength at his current hp, against theirs -- not metal against
		// metal (apexearth, docs/24). The kill is still WORTH metal below.
		const float mine = UnitStrength(int(unit.circuitDef.id)) * unit.GetHealthPercent();
		const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
		// The enemy groups themselves, not the PUSH sensor: that one wants a
		// closing formation of real size and never fired once in a 1v1 (0
		// engagements, measured), while the raids actually eating our mexes are
		// two units. Nearest group standing on OUR half that he outweighs.
		AIFloat3 foeAt;
		bool fresh = false;
		float bestD = -1.f;
		float bestCost = 0.f;
		float bestVel = 0.f;
		float bestApp = 0.f;
		float bestStr = 0.f;
		const int nG = aiEnemyMgr.GetEnemyGroupCount();
		for (int gi = 0; gi < nG; ++gi) {
			const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
			if (!OnMap(gp) || (Military::ForwardFraction(gp) >= 0.5f))
				continue;
			// HE DEFENDS WHAT WE OWN, he does not go on tour. "Our half of the
			// map" was too loose a leash: he chased to the midpoint, chained
			// the next target from there and ended up duelling the enemy
			// commander in their base while ours stood empty (apexearth,
			// watched -- we won that game, which is not evidence it was right).
			// The bar is now our own property: something of ours must be
			// standing within the raider's reach, so there is nothing to
			// defend at their base and nothing to chase toward.
			if (StakeAt(gp, r) <= 0.f)
				continue;
			const float gStr = EnemyGroupStrength(gi);
			if (gStr > mine)
				continue;
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
				bestVel = aiEnemyMgr.GetEnemyGroupVel(gi);
				bestApp = app;
				bestStr = gStr;
				foeAt = gp;
				fresh = true;
			}
		}
		if (fresh) {
			// The GROUP's own cost, not a radius sample: the sample read 1
			// metal for raids the group model valued properly.
			const float theirs = (bestCost > 0.f) ? bestCost
					: ai.GetEnemyCostAt(foeAt, r);
			// WORTH THE WALK. His time is priced like any builder-second, so a
			// detour is only justified when it denies more metal than it costs
			// -- otherwise he trails a 1-metal scout around the base forever
			// (measured: 6 engagements, every one against "1 metal"). No new
			// constant: Wage() is the market's own price for his time.
			const float spd = Catalog::gSpeed[int(unit.circuitDef.id)];
			// The trip is the CATCH at closing speed plus the walk back; a group
			// moving as fast as he does is never caught (apexearth: "enemy pawns
			// are able to distract our commander for minutes").
			const float closing = spd + bestApp;
			const float tripS = ((spd > 1.f) && (closing > 1.f))
					? (bestD / closing + bestD / spd) : 1e9f;
			const float worthIt = Wage() * tripS;
			if ((theirs > worthIt) && (bestStr <= mine)) {
				if (ai.frame >= gNextCommFightLog) {
					gNextCommFightLog = ai.frame + 15 * SECOND;
					AiLog("apex: commander engaging -- "
						+ formatFloat(theirs, "", 0, 0) + " metal raiding our ground,"
						+ " str " + formatFloat(bestStr, "", 0, 2) + " vs his " + formatFloat(mine, "", 0, 2)
						+ " approaching " + formatFloat(bestApp, "", 0, 0) + "/s at " + int(bestD));
				}
				unit.CmdMoveTo(foeAt);
				return null;
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
