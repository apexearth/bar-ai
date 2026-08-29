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
	return Military::FoeMobileMassing()
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
		const float mine = unit.circuitDef.costM;
		const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
		// The enemy groups themselves, not the PUSH sensor: that one wants a
		// closing formation of real size and never fired once in a 1v1 (0
		// engagements, measured), while the raids actually eating our mexes are
		// two units. Nearest group standing on OUR half that he outweighs.
		AIFloat3 foeAt;
		bool fresh = false;
		float bestD = -1.f;
		float bestCost = 0.f;
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
			if (aiEnemyMgr.GetEnemyGroupCost(gi) > mine)
				continue;
			const float dd = here.distance2D(gp);
			if ((bestD < 0.f) || (dd < bestD)) {
				bestD = dd;
				bestCost = aiEnemyMgr.GetEnemyGroupCost(gi);
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
			const float tripS = (spd > 1.f) ? (2.f * bestD / spd) : 60.f;
			const float worthIt = Wage() * tripS;
			if ((theirs > worthIt) && (theirs <= mine)) {
				if (ai.frame >= gNextCommFightLog) {
					gNextCommFightLog = ai.frame + 15 * SECOND;
					AiLog("apex: commander engaging -- "
						+ formatFloat(theirs, "", 0, 0) + " metal raiding our ground,"
						+ " he is worth " + formatFloat(mine, "", 0, 0));
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
		if ((hereInfl > fleeInfl)
			&& (ai.GetEnemyInflAt(Builder::gHomePos) < hereInfl * 0.5f))
		{
			if (ai.frame >= gNextCommFleeLog) {
				gNextCommFleeLog = ai.frame + 15 * SECOND;
				AiLog("apex: commander leaving, enemy influence "
					+ formatFloat(hereInfl, "", 0, 2) + " > "
					+ formatFloat(fleeInfl, "", 0, 2));
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
