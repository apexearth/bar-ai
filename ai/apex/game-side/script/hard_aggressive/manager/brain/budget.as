namespace Brain {

//------------------------------------------------------------------------------
// WHERE THE BUILD RATIO IS DEFINED.
//
// Four independent governors used to decide it between them, none able to see
// the others: gMix set ratios WITHIN the army, the fence budget capped defence
// against income, the Wants ranking bought economy on metal-per-second, and the
// constructor and plant curves bought build power. The split BETWEEN those four
// was an outcome nobody chose, and army was always last because it had no rule
// claiming metal for it.
//
// SPEND IS COUNTED FROM WHAT FINISHES. Every manager's AiUnitAdded already
// receives Unit::UseAs, the engine's own answer to "what is this unit for", so
// the categories cost nothing to maintain and cannot drift from what was built.
//------------------------------------------------------------------------------

// AIRDEF IS ITS OWN ROW. Anti-air and land defence used to share one category
// and one want kind, so a number meant only for anti-air throttled every tower
// on the map. See targets.as.
enum Cat { ARMY = 0, DEFENCE = 1, AIRDEF = 2, ECONOMY = 3, BUILDPOWER = 4, CATS = 5 };

array<float> gSpent(CATS, 0.f);
float gSpentTotal = 0.f;
int gNextBudgetLog = 0;

// The target split of METAL SPENT. Deliberately one table in one place, so the
// question "what are we trying to build" has a single answer. Every entry is
// tunable.
//
// RELATIVE WEIGHTS, NOT PERCENTAGES: the four rows in targets.as are read at the
// current income and normalised against each other, so raising one row lowers
// the others without anything having to be re-balanced by hand -- the same
// contract the ROLE_ rows already had.
float RawTarget(Cat c)
{
	float w = RawBase(c) * Persona::ShareMult(int(c));
	// Enemy-stance lean: greed against a passive enemy, army/defence against
	// an aggressive one, neutral while blind. See Military::UpdateStance.
	w *= Military::StanceShareMult(int(c));
	// Losing the army faster than it kills raises the ARMY row itself; the
	// normalisation below then pays for it out of every other category. See
	// Military::LossArmyMult -- pressure-scaled and bounded, never a switch.
	if (c == ARMY)
		w *= Military::LossArmyMult();
	return w;
}

// GetTunable CACHES the value it returns on the FIRST call (CircuitAI.cpp
// GetTunable), so handing it a live curve as the "default" froze that curve at
// its frame-0 reading for the whole game. Every share below is a function of
// income, income is 0 at frame 0, and SPEND_ARMY's income-0 column is 0.0 --
// so the ARMY row was zero in every game ever played, and the other four sat
// on their opening columns. Read the override against a sentinel instead and
// evaluate the curve fresh on every call.
float ShareOverride(const string &in name)
{
	return ai.GetTunable(name, -1.f);
}

// The curve, read live -- or reproducing the cached frame-0 reading the bug
// produced, which is what every measured game to date actually played.
//
// TURNING THIS ON IS AN UNTUNED CHANGE, NOT JUST A FIX. The numbers in
// targets.as were authored against a system that never read them past column 0,
// so they have never been exercised. Measured 2026-08-22 over three paired
// 50-minute runs against medium (40 games per side): live curves went 23W-8L-9D
// against 20W-10L-10D, inside the noise floor, with win times mixed and metal
// rate 21% lower (12.2k/min against 15.6k). No win-speed benefit was shown, so
// the default stays on the behaviour that was measured. Re-tuning SPEND_* with
// the curves live is the campaign this needs.
float CurveAt(const array<float>& in curve)
{
	if (ai.GetTunable("apex_budget_live", TUNE_BUDGET_LIVE) > 0.f)
		return Targets::At(curve);
	return Targets::At(curve, 0.f);
}

float RawBase(Cat c)
{
	if (c == ARMY) {
		const float ov = ShareOverride("apex_share_army");
		return (ov >= 0.f) ? ov : CurveAt(Targets::SPEND_ARMY);
	}
	if (c == DEFENCE) {
		const float ov = ShareOverride("apex_share_defence");
		return (ov >= 0.f) ? ov : CurveAt(Targets::SPEND_DEFENCE);
	}
	if (c == AIRDEF) {
		const float ov = ShareOverride("apex_share_airdef");
		return (ov >= 0.f) ? ov : CurveAt(Targets::SPEND_AIRDEF);
	}
	if (c == ECONOMY) {
		const float ov = ShareOverride("apex_share_economy");
		return (ov >= 0.f) ? ov : CurveAt(Targets::SPEND_ECONOMY);
	}
	const float ov = ShareOverride("apex_share_buildpower");
	return (ov >= 0.f) ? ov : CurveAt(Targets::SPEND_BUILDPOWER);
}

float TargetShare(Cat c)
{
	float sum = 0.f;
	for (int i = 0; i < int(CATS); ++i)
		sum += RawTarget(Cat(i));
	if (sum <= 0.f)
		return 0.f;
	return RawTarget(c) / sum;
}

// An energy maker is ECONOMY whichever manager reports it: corsolar arrives here
// as UseAs::FENCE and was counted as defence. Decide from the unit, not the
// attribute. See CHANGES.md 2026-08-12.
bool IsEnergyBuilding(const CCircuitDef@ d)
{
	return (d !is null) && !d.IsMobile() && (aiEconomyMgr.GetEnergyMake(d) > 1.f);
}

Cat CatOf(const CCircuitDef@ def, Unit::UseAs usage)
{
	if (IsEnergyBuilding(def))
		return ECONOMY;
	// A static anti-air turret is spent from the air-defence row, not the land
	// one -- they are the same UseAs to the engine and must not be to us.
	if ((def !is null) && !def.IsMobile() && def.IsRoleAny(Unit::Role::AA.mask))
		return AIRDEF;
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
	gSpent[CatOf(unit.circuitDef, usage)] += m;
	gSpentTotal += m;
}

float ShareOf(Cat c)
{
	return (gSpentTotal > 1.f) ? (gSpent[c] / gSpentTotal) : 0.f;
}

// How much a category's next purchase is worth, relative to its target.
//
// Above target it is damped, below target boosted -- the same "furthest below
// target wins" shape the army mix uses for roles, one level up. Bounded both
// ways so a category can never be switched off entirely.
const float BUDGET_MIN = 0.35f;
const float BUDGET_MAX = 2.0f;

float BudgetMult(Cat c)
{
	if (ai.GetTunable("apex_budget", TUNE_BUDGET) <= 0.f)
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
		+ " aa=" + formatFloat(ShareOf(AIRDEF), "", 0, 2)
		+ "/" + formatFloat(TargetShare(AIRDEF), "", 0, 2)
		+ " eco=" + formatFloat(ShareOf(ECONOMY), "", 0, 2)
		+ "/" + formatFloat(TargetShare(ECONOMY), "", 0, 2)
		+ " bp=" + formatFloat(ShareOf(BUILDPOWER), "", 0, 2)
		+ "/" + formatFloat(TargetShare(BUILDPOWER), "", 0, 2)
		// The income the target CURVES are indexed by. Every row in targets.as
		// is a function of this one number, so a wrong reading silently pins
		// every curve to its opening column.
		+ " inc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 2)
		+ " total=" + formatFloat(gSpentTotal, "", 0, 0)
		+ " raw=" + formatFloat(gSpent[ARMY], "", 0, 0)
		+ "/" + formatFloat(gSpent[DEFENCE], "", 0, 0)
		+ "/" + formatFloat(gSpent[AIRDEF], "", 0, 0)
		+ "/" + formatFloat(gSpent[ECONOMY], "", 0, 0)
		+ "/" + formatFloat(gSpent[BUILDPOWER], "", 0, 0));
}

}  // namespace Brain
