namespace Persona {

//------------------------------------------------------------------------------
// PERSONALITY: one identity per instance, rolled at start and allowed to change
// mid-game, so identically-tuned Apex instances play differently and a game's
// story can turn. apexearth: "help to create an AI which can have a personality
// capable of changing or adapting mid-game. Try to make our games unique and
// interesting while staying efficient."
//
// A persona is ONLY a set of multipliers on levers that already exist -- the
// budget split (brain/budget.as), the Want ranking (brain.as), the engage
// margin (posture.as), the air commitment (air/state.as). It shifts how much,
// never whether: every gate a rule carries still applies, so a persona cannot
// switch a behaviour off or invent a new one.
//------------------------------------------------------------------------------

// REARM is adaptation-only (never rolled): out-fielded, it buys army harder
// while DEMANDING better odds -- the opposite of berserker's discount, which
// measured terribly as an out-fielded reaction (Altair, them 3.4 K/D).
enum Kind { STANDARD = 0, BERSERKER, TURTLE, GREEDY, AIRBOSS, SILOIST, REARM, KINDS };

int    gKind      = -1;          // -1 until rolled
int    gSince     = 0;           // frame the current persona took effect
int    gNextEval  = 0;
string gWhy       = "rolled";

// After a switch the persona holds for this long, so adaptation is a decision
// and not a flicker between two signals.
const int DWELL = 4 * MINUTE;

string NameOf(int k)
{
	if (k == BERSERKER) return "berserker";
	if (k == TURTLE)    return "turtle";
	if (k == GREEDY)    return "greedy";
	if (k == AIRBOSS)   return "airboss";
	if (k == SILOIST)   return "siloist";
	if (k == REARM)     return "rearm";
	return "standard";
}

string Name() { return NameOf(gKind); }

void Become(int k, const string &in why)
{
	if (k == gKind)
		return;
	gKind = k;
	gSince = ai.frame;
	gWhy = why;
	AiLog(Factory::T() + "apex: persona -> " + NameOf(k) + " (" + why + ")");
}

// A duel: one enemy, no allies. AIRBOSS and SILOIST are team identities --
// measured 2026-08-20, airboss opened 3 of 8 benchmark 1v1s and lost the
// ground war under its air plants, and siloist sank 6k+ into silos that never
// fire inside a short game. apexearth: "We don't want to pick personas which
// are very bad for a 1v1."
bool Duel()
{
	array<Id>@ mates = ai.GetTeamIds();
	return ((mates is null) || (mates.length() <= 1))
		&& (ai.GetEnemyTeamSize() <= 1);
}

// apex_persona: -1 rolls freely (default); 0..5 forces that Kind and disables
// adaptation, which is what an A/B needs.
void Roll()
{
	if (gKind >= 0)
		return;
	const int forced = int(ai.GetTunable("apex_persona", TUNE_PERSONA));
	if (forced >= 0 && forced < int(KINDS)) {
		Become(forced, "forced");
		return;
	}
	// Standard stays the most likely: the specials are seasoning, not the meal.
	const int r = (AiRandom(0, 999) + ai.teamId * 7) % 100;
	int k = STANDARD;                 // 30
	if      (r < 15) k = BERSERKER;   // 15
	else if (r < 30) k = TURTLE;      // 15
	else if (r < 45) k = GREEDY;      // 15
	else if (r < 57) k = AIRBOSS;     // 12
	else if (r < 70) k = SILOIST;     // 13
	if (Duel() && ((k == AIRBOSS) || (k == SILOIST)))
		k = STANDARD;
	Become(k, "rolled");
}

//------------------------------------------------------------------------------
// The multipliers. Read by budget.as (share), brain.as (wants), posture.as
// (engage), air/state.as and air/wing.as (air commitment). All neutral at 1.
//------------------------------------------------------------------------------

// Budget-category bias; c is int(Brain::Cat).
float ShareMult(int c)
{
	if (gKind == BERSERKER) return (c == 0) ? 1.35f : 1.f;               // ARMY
	if (gKind == REARM)     return (c == 0) ? 1.35f : ((c == 1) ? 1.2f : 1.f);
	if (gKind == TURTLE)    return (c == 1) ? 1.5f : ((c == 2) ? 1.2f : 1.f); // DEFENCE, AIRDEF
	if (gKind == GREEDY)    return (c == 3) ? 1.35f : 1.f;               // ECONOMY
	if (gKind == SILOIST)   return (c == 3) ? 1.15f : 1.f;               // silo needs the eco
	if (gKind == AIRBOSS)   return (c == 0) ? 1.1f : 1.f;                // bombers are ARMY
	return 1.f;
}

// Want-kind bias for the Brain's ranking.
float WantMult(const string &in kind)
{
	if (gKind == SILOIST) {
		if (kind == "silo")     return 2.5f;
		if (kind == "pinpoint") return 1.5f;
	}
	if (gKind == GREEDY && (kind == "mexup" || kind == "convert"))
		return 1.2f;
	return 1.f;
}

// Engage-margin bias: <1 takes fights earlier, >1 wants better odds.
// Same lever the team push already overrides.
float EngageBias()
{
	if (gKind == BERSERKER) return 0.82f;
	if (gKind == TURTLE)    return 1.18f;
	if (gKind == GREEDY)    return 1.18f;
	if (gKind == REARM)     return 1.18f;
	return 1.f;
}

// HOW MUCH T1 ARMY THIS INSTANCE WANTS STANDING BEFORE IT TECHS.
// Multiplies Factory::T2ArmyFloor's per-income figure, so a berserker earns its
// plant behind a bigger T1 mass and a greedy one reaches for tech sooner. A
// multiplier on a floor that already scales with income -- it changes how much,
// never whether, and every other T2 gate still applies.
float T2ArmyBias()
{
	if (gKind == BERSERKER) return 1.4f;
	if (gKind == TURTLE)    return 1.3f;
	if (gKind == REARM)     return 1.5f;   // out-fielded: field something first
	if (gKind == GREEDY)    return 0.7f;
	if (gKind == SILOIST)   return 0.8f;
	if (gKind == AIRBOSS)   return 0.8f;   // its army is in the air, not on armyCost
	return 1.f;
}

// >1 commits to air earlier and bigger: divides the income gates and scales
// the wing size where air/state.as reads them.
float AirEagerness()
{
	return (gKind == AIRBOSS) ? 1.6f : 1.f;
}

//------------------------------------------------------------------------------
// Adaptation. Signals only -- each persona still buys through the normal rules.
//------------------------------------------------------------------------------

void Update()
{
	if (ai.frame < 10 * SECOND)
		return;
	Roll();
	if (int(ai.GetTunable("apex_persona", TUNE_PERSONA)) >= 0)
		return;                   // forced persona never adapts
	if (ai.frame < gNextEval || ai.frame < gSince + DWELL)
		return;
	gNextEval = ai.frame + 60 * SECOND;

	// Sustained pressure at home outranks every identity: dig in.
	if (Military::LosingGround() && Military::BaseContested()) {
		Become(TURTLE, "losing ground at home");
		return;
	}
	// A quarter of income dying deep on their ground: stop identifying as the
	// aggressor, hold the line and let the eco lead win instead.
	if (Military::ForwardBleedFrac() > 0.25f) {
		if (gKind == BERSERKER || gKind == STANDARD)
			Become(TURTLE, "bleeding on their ground");
		return;
	}
	// Their fielded army dwarfs ours: buy army before anything clever.
	const float ours = Military::TeamArmyCost();
	const float theirs = Military::EnemyArmyCost();
	if (theirs > ours * 2.f && ours > 0.f) {
		Become(REARM, "out-fielded 2:1");
		return;
	}
	// Comfortably ahead on the ground with the income to spend: reach for the
	// finisher -- nukes if the game has gone long, otherwise press the lead.
	if (ours > theirs * 1.5f && Factory::gHaveT2) {
		if (gKind != SILOIST && gKind != BERSERKER) {
			// In a duel the finisher is always pressure: a silo takes longer
			// than the lead lasts (see Duel()).
			Become((!Duel() && (AiRandom(0, 1) == 0)) ? SILOIST : BERSERKER,
				"ahead and funded");
		}
		return;
	}
}

}  // namespace Persona
