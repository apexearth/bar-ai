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

// Detects a player boxed in -- out of reachable expansion for its CURRENT
// move type, not merely "the map has some water". apexearth, watching an
// 8v8 live: a player started on a small strip of land, chose bots, and
// stood doing nothing once local mexes ran out, with an ocean it could not
// build ships on (no shipyard, bots-only) and mexes on a nearby hill it
// could not reach (no air con) -- IsMixedWaterMap() gates the shipyard
// trigger on the MAP's average land%, which reads "mostly land" and never
// fires for a player boxed onto a small peninsula regardless of THEIR own
// situation. No terrain-height query is registered to script (checked
// vendor/engine/.../InitScript.cpp), so a true geometric "am I landlocked"
// test would need a new C++ binding -- too large a change to add blind this
// late in an unsupervised session, especially after this session's own
// experience with an under-tested C++ addition crashing the engine.
//
// This is the binding-free alternative: detect the SYMPTOM instead of the
// geometric cause. A player with spare build capacity whose mex count has
// not grown in a long time, well past the opening, is out of reachable
// expansion for SOME reason -- water, cliffs, an enemy wall, a hill --
// and trying an alternative move type (naval here; air is the harder case,
// left for a future session per the note below) is a reasonable response
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
// Off by default, and the reason is measured: on a four-player team a player
// fielding no army is a quarter of the army missing, which is the same
// arithmetic that bars the air opening and the constructor monopoly there
// (standing army 17.8k against 25.4k, real K/D 0.70 against 1.24).
//
// RE-TESTED 2026-08-02 against the current, much stronger role and the verdict
// held. Six 4v4 games each way, same three maps and seeds, only this flag
// differing: OFF went 2-1 on 904,267 metal and 166,643 army; ON went 0-4 on
// 516,702 metal and 80,671 army, and its games ended SOONER (41 min against 48)
// -- it is not slower, it is dead earlier. Build power, converters and air
// constructors do not buy back the quarter of the team that stops fighting.
const bool ECO_ON_SMALL_TEAMS = false;

bool IsEcoLead()
{
	if (IsSmallTeam() && !ECO_ON_SMALL_TEAMS)
		return false;
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
	// player builds no army, so it can neither avoid the hold nor recover from
	// it. Measured in the same run: HOLD at 8.7 min on army 1897 -> 1266, RESUME
	// only at 15.0 on army 110 -- the maximum hold, six minutes, expiring rather
	// than recovering. As a gate it removed the role from the game.
	// A TEAM ROLE NEEDS A TEAM. apexearth, watching a 1v1: "it certainly
	// shouldn't be solo running the eco lead role." The role trades this
	// player's army for the team's economy; with no team it just means no army.
	array<Id>@ roster = ai.GetTeamIds();
	const bool haveTeam = (roster !is null) && (roster.length() > 1);
	gEcoActive = haveTeam && mine && !gHurt && !allies;

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

bool EcoLeadActive()
{
	return gEcoActive;
}

// Has the late game arrived? Either the clock, or a fusion standing -- a reactor
// IS the late game economically, whenever it turns up.
bool LateGame()
{
	return (ai.frame >= LATE_GAME_FRAME) || (Builder::gFusions.length() > 0);
}

}  // namespace Factory
