namespace Factory {

// What share of our peak extractor count we still hold. Peak-tracked here rather
// than recomputed at each reader, so the peak advances exactly once per update.
// Until the peak is meaningful this reports full health rather than a ratio off
// two or three opening mexes.
int gLastMexGrowth = 0;   // frame gPeakMex was last raised

float UpdateMexHold()
{
	const uint mex = MexCount();
	if (mex > gPeakMex) {
		gPeakMex = mex;
		gLastMexGrowth = ai.frame;
	}
	gMexHold = (gPeakMex < HURT_MIN_MEX) ? 1.f : (float(mex) / float(gPeakMex));
	if (gMexHold >= HURT_SELF_FRAC)
		gHurtSince = -1;
	else if (gHurtSince < 0)
		gHurtSince = ai.frame;
	gHurt = (gHurtSince >= 0) && ((ai.frame - gHurtSince) >= HURT_SUSTAIN);
	return gMexHold;
}

// Detects a player boxed in -- out of reachable expansion for its CURRENT move
// type -- by SYMPTOM rather than geometry: no terrain-height query is
// registered to script, so a true "am I landlocked" test would need a new C++
// binding. IsMixedWaterMap() alone is not enough here because it gates on the
// MAP's average land%, which reads "mostly land" and misses a player boxed
// onto a small peninsula. A player with spare build capacity whose mex count
// has not grown in a long time is out of reachable expansion for SOME reason,
// and trying naval as an alternative move type is a reasonable response
// regardless of which reason it is.
const int   STALL_MIN_FRAME  = 6 * MINUTE;   // let the opening actually happen first
const int   STALL_DURATION   = 3 * MINUTE;   // no mex growth for this long
const uint  STALL_MIN_MEX    = 2;            // had at least a normal opening

bool ExpansionStalled()
{
	if (ai.frame < STALL_MIN_FRAME)
		return false;
	if (gPeakMex < STALL_MIN_MEX)
		return false;
	return (ai.frame - gLastMexGrowth) >= STALL_DURATION;
}

// Is any ALLY being killed? Read straight off their own published share -- each
// team is the only one that can count its own extractors.
bool AlliesHurting()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		if (ai.ReadTeamValue(t, TV_MEX, 1.f) < HURT_ALLY_FRAC)
			return true;
	}
	return false;
}

// The eco lead is the PRIMARY tech lead, not a separate election. It is already
// chosen for exactly the properties the eco player wants -- furthest from the
// enemy, able to pay -- and it is already the sling target, so the team's spare
// metal is already going there.
// Whether the role is allowed on a team under BIG_TEAM.
//
// Off by default: on a four-player team, a player fielding no army is a
// quarter of the army missing -- the same arithmetic that bars the air
// opening. Build power, converters and air constructors do not buy back the
// quarter of the team that stops fighting.
const bool ECO_ON_SMALL_TEAMS = false;

bool IsEcoLead()
{
	if (IsSmallTeam() && !ECO_ON_SMALL_TEAMS)
		return false;
	// FARMING IS AN OPENING JOB. Eco-lead election was coupled to the
	// tech-lead DESIGNATION, which waits on the tech bars -- measured on
	// Glitters 8v8s, the farmer activated at 13.5m and 23.1m while stock's
	// farmers greed from minute one, and the raised T2 energy bar pushed it
	// later still. Before any designation exists, the fallback lead id
	// (lowest team) holds the eco slot from frame one; the grace period
	// covers the handover when a real designation lands.
	if (!LeadIsDesignated())
		return ai.teamId == RushLeadTeamId();
	return IsDesignatedLead() && (ai.teamId == RushLeadTeamId());
}

// Resolved once per update and cached: EcoLeadActive() is read from three files,
// one of them CBuilderManager's task hook, and this walks the ally roster.
void UpdateEcoLead()
{
	const bool was = gEcoActive;
	if (IsEcoLead())
		gEcoSlotSeen = ai.frame;
	const bool mine = (ai.frame - gEcoSlotSeen) <= ECO_ROLE_GRACE;
	const bool allies = mine && AlliesHurting();

	// Military::gTurtle is deliberately NOT a condition here, for the same reason
	// LosingGround() is not: the hold fires when our own army SHRINKS, and this
	// player builds no army, so it can neither avoid the hold nor recover from it
	// -- as a gate it would remove the role from the game entirely.
	// A team role needs a team: it trades this player's army for the team's
	// economy, so with no team it just means no army.
	array<Id>@ roster = ai.GetTeamIds();
	const bool haveTeam = (roster !is null) && (roster.length() > 1);
	// THE FARMER FARMS THROUGH THE WAR. "An ally is dying" stood the role
	// down at 29m of the measured 8v8 -- in a big team an ally is ALWAYS
	// dying late, so the team's only compounding engine converted itself to
	// one more mediocre army player exactly when stock's farmer (183 mexes)
	// compounded hardest. A dying ally is answered with EcoAid metal (already
	// live), not with role abdication; only losing OUR OWN mexes stands the
	// role down. Tunable to restore the old behaviour.
	const bool allyStop = allies
			&& (ai.GetTunable("apex_eco_lead_holds", TUNE_ECO_LEAD_HOLDS) <= 0.f);
	gEcoActive = haveTeam && mine && !gHurt && !allyStop;

	// Which gate is holding it off, sampled while we hold the slot. The first
	// version of this role was elected and then never activated for a whole
	// game, and there was no way to tell from the log which of four conditions
	// was responsible -- so state them rather than guessing at them later.
	if (mine && !gEcoActive && (ai.frame >= gNextEcoGateLog)) {
		gNextEcoGateLog = ai.frame + 60 * SECOND;
		AiLog(T() + "apex: eco lead held off"
			+ " ourMex=" + formatFloat(gMexHold, "", 0, 2)
			+ " allyDying=" + (allies ? "1" : "0"));
	}

	if (gEcoActive == was)
		return;
	if (gEcoActive) {
		gEcoLoggedFor = ai.teamId;
		AiLog(T() + "apex: ECO LEAD -- no army, economy only");
	} else if (gEcoLoggedFor == ai.teamId) {
		AiLog(T() + "apex: eco lead standing down"
			+ (gHurt ? " (losing our own mexes)"
			 : allies ? " (an ally is dying)" : " (role lost)"));
	}
}

// Team roles do not exist without a team, and neither do the paths that read
// them. The fusion bug was the proof: the reactor rule asked EcoLeadActive() as
// its ONLY gate, so with no eco lead nobody ever built a reactor -- a solo
// player simply never teched its energy. Disabling the ROLE silently disabled a
// behaviour that had nothing to do with teams.
//
// So the rule is now: every consumer of a team role must be one of
//   (a) genuinely team-only -- it coordinates with allies, and is skipped solo;
//   (b) general behaviour that was wrongly gated on a role -- ungated, with its
//       own economic condition instead.
// TeamPlay() below is the single answer to "do team roles exist at all", so the
// question is asked in one place rather than rediscovered per rule.
bool TeamPlay()
{
	array<Id>@ roster = ai.GetTeamIds();
	return (roster !is null) && (roster.length() > 1);
}

bool EcoLeadActive()
{
	return TeamPlay() && gEcoActive;
}

// Has the late game arrived? Either the clock, or a fusion standing -- a reactor
// IS the late game economically, whenever it turns up.
bool LateGame()
{
	return (ai.frame >= LATE_GAME_FRAME) || (Builder::gFusions.length() > 0);
}

}  // namespace Factory
