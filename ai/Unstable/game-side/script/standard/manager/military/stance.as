namespace Military {

//------------------------------------------------------------------------------
// THE ENEMY'S STANCE, AND OURS IN ANSWER.
//
// apexearth 2026-08-20: "Iterate until we have an appropriate balance of eco
// and army. Tailor our balance based on the stance of the enemy. Remember
// that too much silence/unknowns demand proper scouting." And earlier, the
// army-brain campaign: "If enemy is not attacking us but just being
// defensive, we should form our own defense a bit more and take the time to
// scale our army."
//
// Three readings, from signals that already exist:
//   AGGRESSIVE -- they are coming: raid pressure, base being hit, or their
//                 fresh (recently seen) army rivals ours.
//   PASSIVE    -- we can see a meaningful share of their known force and it
//                 is not coming. Greed is correct.
//   UNKNOWN    -- silence. We see nothing, or an army we once saw has gone
//                 dark. Silence is never safety (the measured trap: gates
//                 keyed on visible strength read "safe" exactly when blind);
//                 it is a demand for scouting, at neutral spend.
//
// The stance moves the ARMY/DEFENCE/ECONOMY target weights through the same
// multiplier contract Persona::ShareMult uses -- normalisation pays for every
// raise out of the other rows. Held for a minimum dwell so the estimate's
// fog-noise cannot flap the budget (the killing-blow flicker lesson).
//------------------------------------------------------------------------------

enum StanceKind { S_UNKNOWN = 0, S_PASSIVE, S_AGGRESSIVE }

int gStance = S_UNKNOWN;
int gStanceSince = 0;
int gNextStanceEval = 0;
const int STANCE_DWELL = 30 * SECOND;

int Stance() { return gStance; }
bool StanceUnknown() { return gStance == S_UNKNOWN; }

void UpdateStance()
{
	if (ai.frame < gNextStanceEval)
		return;
	gNextStanceEval = ai.frame + 5 * SECOND;
	// Influence/contested readings are garbage in the opening seconds --
	// measured: AGGRESSIVE at 0.5m with fresh=0 peak=0 ours=0.
	if (ai.frame < 2 * MINUTE)
		return;

	const float fresh = FreshMassingThreat();
	const float pressure = RaidPressure();
	const float ours = OurArmyNow();

	int want = gStance;
	const bool hit = Builder::BaseUnderAttack() || BaseContested() || BaseRaided();
	// The rival clause is DUEL-ONLY: fresh sightings are side-wide, so in an
	// 8v8 it compared the whole enemy team's visible army against ONE
	// player's own and read AGGRESSIVE 24-27 minutes of 40 for everyone --
	// the greed (and its con curve) never came back, which is exactly the
	// measured late-game scaling decay. In a team, aggression is what
	// threatens YOUR OWN ground: base contact and raid pressure.
	const bool rival = !Factory::TeamPlay()
		&& (ours > 1.f)
		&& (fresh > ours * ai.GetTunable("apex_stance_rival", TUNE_STANCE_RIVAL));
	if (hit || rival
		|| (pressure > ai.GetTunable("apex_stance_pressure", TUNE_STANCE_PRESSURE)))
	{
		want = S_AGGRESSIVE;
	}
	// Seeing a real share of what they are KNOWN to hold, and it is not
	// coming: passive. The share test is what separates "they are quiet"
	// from "we are blind" -- a big army we saw once and cannot find now is
	// the most dangerous silence there is.
	else {
		// SPLIT THRESHOLDS, or the boundary lives inside fog noise: one 60m
		// game flapped 47 times at a single 0.2 bar. Enter passive only when
		// we clearly see them (0.25 of peak); fall back to UNKNOWN only when
		// sight has clearly died (0.08). Between the two, keep the current
		// reading.
		// Absolute floor on "seeing them": with a tiny peak both bars were
		// microscopic and a single 42-metal scout entering and leaving LOS
		// toggled the whole budget. Passive requires eyes on a SQUAD.
		float hi = gSeenPeak * ai.GetTunable("apex_stance_seen_hi", TUNE_STANCE_SEEN_HI);
		const float minSeen = ai.GetTunable("apex_stance_seen_min", TUNE_STANCE_SEEN_MIN);
		if (hi < minSeen)
			hi = minSeen;
		const float lo = gSeenPeak * ai.GetTunable("apex_stance_seen_lo", TUNE_STANCE_SEEN_LO);
		if ((fresh > hi) && (fresh > 1.f))
			want = S_PASSIVE;
		else if (fresh < lo)
			want = S_UNKNOWN;
		// else: keep gStance
	}

	if (want == gStance)
		return;
	if (ai.frame - gStanceSince < STANCE_DWELL)
		return;   // hold: fog-noise must not flap the budget
	gStance = want;
	gStanceSince = ai.frame;
	AiLog(Factory::T() + "apex: stance -> "
		+ ((want == S_AGGRESSIVE) ? "AGGRESSIVE" : ((want == S_PASSIVE) ? "passive" : "UNKNOWN"))
		+ " fresh=" + formatFloat(fresh, "", 0, 0)
		+ " peak=" + formatFloat(gSeenPeak, "", 0, 0)
		+ " pressure=" + formatFloat(pressure, "", 0, 2)
		+ " ours=" + formatFloat(ours, "", 0, 0));
}

// The budget answer. Neutral 1.0 everywhere for UNKNOWN -- blindness changes
// what we SCOUT, not what we buy; guessing a budget off no information is how
// the wrong stance compounds.
float StanceShareMult(int cat)
{
	if (ai.GetTunable("apex_stance", TUNE_STANCE) <= 0.f)
		return 1.f;   // isolation A/B: stance reads but never acts
	if (gStance == S_AGGRESSIVE) {
		if (cat == int(Brain::ARMY))
			return ai.GetTunable("apex_stance_aggro_army", TUNE_STANCE_AGGRO_ARMY);
		if (cat == int(Brain::DEFENCE))
			return ai.GetTunable("apex_stance_aggro_def", TUNE_STANCE_AGGRO_DEF);
		if (cat == int(Brain::ECONOMY))
			return ai.GetTunable("apex_stance_aggro_eco", TUNE_STANCE_AGGRO_ECO);
	} else if (gStance == S_PASSIVE) {
		if (cat == int(Brain::ECONOMY))
			return ai.GetTunable("apex_stance_greed_eco", TUNE_STANCE_GREED_ECO);
		if (cat == int(Brain::ARMY))
			return ai.GetTunable("apex_stance_greed_army", TUNE_STANCE_GREED_ARMY);
	}
	return 1.f;
}

// Scouting demand: the air scouts' watch (Air::WatchGainFor). 2x while blind.
float ScoutMult()
{
	if (ai.GetTunable("apex_stance", TUNE_STANCE) <= 0.f)
		return 1.f;
	return StanceUnknown() ? ai.GetTunable("apex_scout_blind_mult", TUNE_SCOUT_BLIND_MULT) : 1.f;
}

}  // namespace Military
