namespace Brain {

//------------------------------------------------------------------------------
// WHERE THE BUILD RATIO IS DEFINED.
//
// apexearth: "So if we focus on defenses more than the enemy, or if we focus on
// economy more than the enemy, we're not gonna have as much army as them. Where
// do we define our target build ratios?"
//
// Nowhere, until this file. Four independent governors decided it between them
// and none could see the others: gMix set ratios WITHIN the army, the fence
// budget capped defence against income, the Wants ranking bought economy on
// metal-per-second, and the constructor and plant curves bought build power. The
// split BETWEEN those four was an outcome nobody chose -- composition.py reports
// it after the fact -- and army was always last in the queue because it is the
// only one with no rule claiming metal for it.
//
// That is what the unit limits were secretly doing. Measured 2026-08-11 over
// four 6-game arms: every cap removed moved metal into constructors, factories
// and towers, and the standing army fell every time. The caps were a proxy for
// this file.
//
// SPEND IS COUNTED FROM WHAT FINISHES. Every manager's AiUnitAdded already
// receives Unit::UseAs, which is the engine's own answer to "what is this unit
// for", so the categories cost nothing to maintain and cannot drift from what
// was actually built.
//------------------------------------------------------------------------------

enum Cat { ARMY = 0, DEFENCE = 1, ECONOMY = 2, BUILDPOWER = 3, CATS = 4 };

array<float> gSpent(CATS, 0.f);
float gSpentTotal = 0.f;
int gNextBudgetLog = 0;

// The target split of METAL SPENT. Deliberately one table in one place, so the
// question "what are we trying to build" has a single answer that can be argued
// with. Every entry is tunable.
//
// These are a starting point, not a measurement: they are close to what the
// pre-Brain build actually produced (army 35.6%, defence 22.2%, constructors
// 10.5%, factories 11.1%) with army raised, because that build was itself losing
// the trade and stock fields more army than either of us.
float TargetShare(Cat c)
{
	if (c == ARMY)
		return ai.GetTunable("apex_share_army", Targets::At(Targets::SPEND_ARMY));
	if (c == DEFENCE)
		return ai.GetTunable("apex_share_defence", Targets::At(Targets::SPEND_DEFENCE));
	if (c == ECONOMY)
		return ai.GetTunable("apex_share_economy", Targets::At(Targets::SPEND_ECONOMY));
	return ai.GetTunable("apex_share_buildpower", Targets::At(Targets::SPEND_BUILDPOWER));
}

Cat CatOf(Unit::UseAs usage)
{
	switch (usage) {
	case Unit::UseAs::COMBAT:
	case Unit::UseAs::SUPER:
		return ARMY;
	case Unit::UseAs::FENCE:
		return DEFENCE;
	case Unit::UseAs::BUILDER:
	case Unit::UseAs::REZZER:
	case Unit::UseAs::FACTORY:
	case Unit::UseAs::ASSIST:
		return BUILDPOWER;
	default:
		break;
	}
	return ECONOMY;   // energy, geo, mex, convert, store, airpad
}

void NoteSpend(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (unit is null)
		return;
	const float m = unit.circuitDef.costM;
	if (m <= 0.f)
		return;
	gSpent[CatOf(usage)] += m;
	gSpentTotal += m;
}

float ShareOf(Cat c)
{
	return (gSpentTotal > 1.f) ? (gSpent[c] / gSpentTotal) : 0.f;
}

// How much a category's next purchase is worth, relative to its target.
//
// Above target it is damped, below target it is boosted, and at target it is
// unchanged -- the same "furthest below target wins" shape the army mix already
// uses for roles, applied one level up to the categories themselves. Bounded
// both ways so a category can never be switched off: being over budget makes
// something less attractive, never forbidden. apexearth, twice: nothing should
// have a hard cap.
const float BUDGET_MIN = 0.35f;
const float BUDGET_MAX = 2.0f;

float BudgetMult(Cat c)
{
	if (ai.GetTunable("apex_budget", 1.f) <= 0.f)
		return 1.f;
	const float target = TargetShare(c);
	if (target <= 0.f)
		return BUDGET_MIN;
	// Opening: nothing has been built, so every category reads zero and the
	// multiplier is its cap. That is correct -- everything is under target -- and
	// the ranking between them is unchanged because they all scale together.
	const float have = ShareOf(c);
	const float mult = target / ((have > 0.001f) ? have : 0.001f);
	if (mult > BUDGET_MAX)
		return BUDGET_MAX;
	if (mult < BUDGET_MIN)
		return BUDGET_MIN;
	return mult;
}

void BudgetLog()
{
	if (ai.frame < gNextBudgetLog)
		return;
	gNextBudgetLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: budget army=" + formatFloat(ShareOf(ARMY), "", 0, 2)
		+ "/" + formatFloat(TargetShare(ARMY), "", 0, 2)
		+ " def=" + formatFloat(ShareOf(DEFENCE), "", 0, 2)
		+ "/" + formatFloat(TargetShare(DEFENCE), "", 0, 2)
		+ " eco=" + formatFloat(ShareOf(ECONOMY), "", 0, 2)
		+ "/" + formatFloat(TargetShare(ECONOMY), "", 0, 2)
		+ " bp=" + formatFloat(ShareOf(BUILDPOWER), "", 0, 2)
		+ "/" + formatFloat(TargetShare(BUILDPOWER), "", 0, 2)
		+ " total=" + formatFloat(gSpentTotal, "", 0, 0));
}

}  // namespace Brain
