namespace Persona {

//------------------------------------------------------------------------------
// PERSONALITY: seven traits per instance, rolled at start, so identically tuned
// Apex instances want different things. apexearth 2026-09-12: "Simple high
// level modifiers affecting an AI's interest in making certain things --
// Economy, Defense, Army, T3 Army, Air, Nuke Weapons, LRPC ... randomized mods
// which manipulate the AI's overall balance to make their playstyle less
// predictable."
//
// A trait is ONLY a multiplier on a lever that already exists -- the army and
// defence targets (how much of each we mean to hold), the Want ranking (the
// draw odds of an economy, defence or air-plant want), the strategic wants
// (gantry, silo, big gun, air plant) and the air commitment. It shifts how
// much, never whether: every gate still applies, so a trait cannot switch a
// behaviour off or invent one. Neutral is 1 and a roll never goes below it:
// personality adds interest, it cannot starve one.
//------------------------------------------------------------------------------

const int T_ECO = 0;
const int T_DEF = 1;
const int T_ARMY = 2;
const int T_T3 = 3;
const int T_AIR = 4;
const int T_NUKE = 5;
const int T_LRPC = 6;
const int T_N = 7;

array<float> gTrait(T_N, 1.f);   // rolled once
array<float> gAdapt(T_N, 1.f);   // the game's story, re-read every minute
bool gRolled = false;
int gNextEval = 0;
int gSince = 0;
string gStory = "";

// After a turn of the story the adaptation holds for this long, so it is a
// decision and not a flicker between two signals.
const int DWELL = 4 * MINUTE;

string NameOf(int t)
{
	if (t == T_ECO)  return "eco";
	if (t == T_DEF)  return "def";
	if (t == T_ARMY) return "army";
	if (t == T_T3)   return "t3";
	if (t == T_AIR)  return "air";
	if (t == T_NUKE) return "nuke";
	if (t == T_LRPC) return "lrpc";
	return "?";
}

string Line()
{
	string s = "";
	for (int t = 0; t < T_N; ++t)
		s += " " + NameOf(t) + "=" + formatFloat(gTrait[t] * gAdapt[t], "", 0, 2);
	return s;
}

// apex_persona_spread: each trait is log-uniform in [1, 1+s] -- up only, so
// the worst roll is the neutral AI. 0 makes every instance identical (the
// A/B arm).
void Roll()
{
	if (gRolled)
		return;
	gRolled = true;
	const float spread = ai.GetTunable("apex_persona_spread", TUNE_PERSONA_SPREAD);
	if (spread > 0.f) {
		const float top = 1.f + spread;
		for (int t = 0; t < T_N; ++t) {
			const float u = float(AiRandom(0, 10000)) / 10000.f;   // 0..1
			gTrait[t] = pow(top, u);
		}
		// A silo or a big gun takes longer than a duel lasts.
		if (Duel()) {
			gTrait[T_NUKE] = 1.f;
			gTrait[T_LRPC] = 1.f;
		}
	}
	AiLog(Factory::T() + "apex: persona t=" + ai.teamId + " rolled spread="
		+ formatFloat(spread, "", 0, 2) + Line());
}

bool Duel()
{
	array<Id>@ mates = ai.GetTeamIds();
	return ((mates is null) || (mates.length() <= 1))
		&& (ai.GetEnemyTeamSize() <= 1);
}

float Trait(int t)
{
	if (!gRolled)
		Roll();
	if ((t < 0) || (t >= T_N))
		return 1.f;
	return gTrait[t] * gAdapt[t];
}

//------------------------------------------------------------------------------
// The levers. Each caller multiplies ONE quantity it already computes.
//------------------------------------------------------------------------------

// The strategic wants, by want_super's class name.
float WantMult(const string &in kind)
{
	if (kind == "silo")     return Trait(T_NUKE);
	if (kind == "lrpc")     return Trait(T_LRPC);
	if (kind == "heavygun") return Trait(T_LRPC);
	if (kind == "gantry")   return Trait(T_T3);
	if (kind == "airplant") return Trait(T_AIR);
	return 1.f;
}

// The market's draw: a Want's value by the trait its category serves. The
// strategic wants are already multiplied where they are priced, and an army
// plant's worth is army demand, which the army TARGET carries.
float CategoryMult(int cat)
{
	if ((cat == Market::CAT_METAL) || (cat == Market::CAT_ENERGY) || (cat == Market::CAT_BP))
		return Trait(T_ECO);
	if ((cat == Market::CAT_DEFENCE) || (cat == Market::CAT_AIRDEF))
		return Trait(T_DEF);
	return 1.f;
}

// Budget-category bias; c is int(Brain::Cat): 0 ARMY, 1 DEFENCE, 2 AIRDEF, 3 ECONOMY.
float ShareMult(int c)
{
	if (c == 0) return Trait(T_ARMY);
	if (c == 1) return Trait(T_DEF);
	if (c == 2) return Trait(T_DEF);
	if (c == 3) return Trait(T_ECO);
	return 1.f;
}

// Engage margin is a fighting decision, not an interest; docs/24 owns it.
float EngageBias()
{
	return 1.f;
}

// >1 commits to air earlier and bigger: divides the income gates and scales
// the wing size where air/state.as reads them.
float AirEagerness()
{
	return Trait(T_AIR) * Market::PlanAirMult();
}

//------------------------------------------------------------------------------
// Adaptation: the game's story leans a trait, on the same signals as before.
// Signals only -- every purchase still goes through the normal rules.
//------------------------------------------------------------------------------

void Lean(const string &in story, int a, float fa, int b, float fb)
{
	if (story == gStory)
		return;
	for (int t = 0; t < T_N; ++t)
		gAdapt[t] = 1.f;
	if (a >= 0) gAdapt[a] = fa;
	if (b >= 0) gAdapt[b] = fb;
	gStory = story;
	gSince = ai.frame;
	AiLog(Factory::T() + "apex: persona t=" + ai.teamId + " -> "
		+ ((story.length() > 0) ? story : "story over") + Line());
}

void Update()
{
	if (ai.frame < 10 * SECOND)
		return;
	Roll();
	if (ai.frame < gNextEval || ai.frame < gSince + DWELL)
		return;
	gNextEval = ai.frame + 60 * SECOND;
	// Sustained pressure at home outranks every identity: dig in.
	if (Military::LosingGround() && Military::BaseContested()) {
		Lean("losing ground at home", T_DEF, 1.3f, T_ARMY, 1.15f);
		return;
	}
	// A quarter of income dying deep on their ground: hold and let eco win.
	if (Military::ForwardBleedFrac() > 0.25f) {
		Lean("bleeding on their ground", T_DEF, 1.2f, T_ECO, 1.15f);
		return;
	}
	// Their fielded army dwarfs ours: buy army before anything clever.
	const float ours = Military::TeamArmyCost();
	const float theirs = Military::EnemyArmyCost();
	if (theirs > ours * 2.f && ours > 0.f) {
		Lean("out-fielded 2:1", T_ARMY, 1.35f, -1, 1.f);
		return;
	}
	// Comfortably ahead with the income to spend: reach for a finisher --
	// the one this instance already leans to.
	if (ours > theirs * 1.5f && Factory::gHaveT2) {
		int fin = T_T3;
		if (!Duel() && (gTrait[T_NUKE] > gTrait[fin])) fin = T_NUKE;
		if (!Duel() && (gTrait[T_LRPC] > gTrait[fin])) fin = T_LRPC;
		if (gTrait[T_AIR] > gTrait[fin]) fin = T_AIR;
		Lean("ahead and funded", fin, 1.3f, -1, 1.f);
		return;
	}
	Lean("", -1, 1.f, -1, 1.f);
}

}  // namespace Persona
