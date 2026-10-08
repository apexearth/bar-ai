//==============================================================================
// TARGETS -- how the metal is split by what it is FOR, as curves over income.
//
// Every row below is a CURVE, read against metal income. One shared income
// axis, one row per thing, interpolated between the columns -- below the first
// column the first value holds, above the last the last value holds.
//
// Edit a number, redeploy (python tools/deploy_ai.py deploy apex), done: there
// is no build step for AngelScript. Nothing else in the codebase should contain
// a composition number.
//
// Two rules for anything added here:
//   * a ratio against economic power, never a count and never a clock;
//   * relative weights, not percentages -- EVERY row here is normalised against
//     its neighbours, so {3, 1, 2, 2} says exactly what {0.375, 0.125, 0.25,
//     0.25} says. Raise one entry and the others fall by themselves. This is
//     true of the SPEND_ rows and the ROLE_ rows alike.
//
// WRITING THE NUMBERS: they are AngelScript float literals, so they need a
// decimal point AND the f -- `2.f` or `2.0f`, never `2f` and never `.5f`. A bad
// literal here does not fail loudly: the whole variant stops compiling and the
// match still runs, with apex playing as near-stock and nothing on screen
// saying so. Check any edit with:
//
//     python tools/deploy_ai.py deploy apex && python tools/run_match.py \
//         --a Apex:apex:standard --b BARb:stable:hard \
//         --map "Comet Catcher" --minutes 5 --out matches/_check
//     grep -c " : ERR " matches/_check/infolog.txt      # must be 0
//==============================================================================

namespace Targets {

// The economic brackets every curve below is read against, in metal/second.
// Roughly: opening, first expansion, a real economy, a strong one, late game.
array<float> INCOME = { 8.f,  20.f,  50.f, 100.f, 300.f};

//------------------------------------------------------------------------------
// HOW THE METAL IS SPLIT, by what it is FOR.
//
// Early the economy and build power matter most; once there is an economy to
// spend, the army takes the largest share. Nothing else here claims metal for
// the army by default, so without this split it gets only what towers and
// constructors leave behind.
//
// RELATIVE WEIGHTS -- they do NOT have to add up to anything. {3, 1, 2, 2} says
// the same as {0.375, 0.125, 0.25, 0.25}; raise one row and the others fall by
// themselves. Written here as thirds and halves so the intent is readable rather
// than as decimals that happen to sum to one.
//                            8     20     50    100    300
//------------------------------------------------------------------------------
// LAND DEFENCE AND AIR DEFENCE ARE SEPARATE ROWS, AND THEY MUST BE: a single
// SPEND_DEFENCE row applies one dampening figure to every tower, but
// AirCoverWant and FrontDefenceWant both propose under the same "fence" kind
// and so competed for one allowance.
//
// Every entry is tunable (apex_share_defence, apex_share_airdef).
//                            8     20     50    100    300
// WARNING (build-power review, 2026-08-16): this row is currently consulted
// by NOTHING that produces combat units -- BudgetCatOf has no "army" kind,
// and QuotaFor's wants are demand-unbounded anyway (measured wants in the
// thousands against held in the tens). Army metal share is decided by what
// ELSE is being built concurrently, not by this number. Kept because the
// budget log reads it; treat any claimed effect from editing it as false
// until Cat::ARMY is wired into the metal-allocation level.
// RAISED 2026-08-19. apexearth, 24 minutes into a game we were winning on
// economy and map control: "we only have 55k army vs 140k army on the other
// side... it feels a bit like we never rotate hard into making a nice strong
// army... the bottom line is we need stronger weight on army." Measured beside
// it, every composition table that session: army 12-15% of our metal against
// BARb's 22-34%, while we out-produced them on metal.
// RETUNED 2026-08-20, apexearth: "tune army down to something like .3 and
// add more to eco." Each column set so army/total ~= 0.30 with the removed
// weight moved into SPEND_ECONOMY below (def/airdef/buildpower untouched).
// The 2026-08-19 raise this replaces was measured against the OLD spend
// machinery; with the budget deferrals live, the target now actually binds.
array<float> SPEND_ARMY       = { 6.0f,  6.0f,  6.0f,  6.0f,   6.0f };   // his 2026-10-04: "go hard into a nice army that will protect us" (was 4,4,5,5,5)
// LOW until T3-scale income, then RISING HARD -- apexearth: pre-T3 "defenses
// are really only good versus raiders", but "at late game we should be
// aggressive with flak on our front lines, T3 defense too. Right now we are
// *not* aggressive with this at all." The ramp starts at the 100 column and
// peaks steep at 300: ~8-9% early/mid, ~12% at 100, ~19% at 300.
array<float> SPEND_DEFENCE    = { 4.0f,  4.0f,  4.0f,  4.0f,  4.0f };  // every validated Altair arm ran share_defence=4; online has no modoption, so the tested value IS the default
array<float> SPEND_AIRDEF     = { 1.0f,  2.0f,  1.5f,  1.5f,  2.0f };
array<float> SPEND_ECONOMY    = { 5.0f,  5.0f,  5.0f,  5.0f,  5.0f };   // absorbs the army cut, see SPEND_ARMY
array<float> SPEND_BUILDPOWER = { 3.0f,  2.0f,  2.0f,  2.0f,  2.0f };

//------------------------------------------------------------------------------
// Piecewise-linear read of any row above, against metal income. Below the first
// bracket the first value holds; above the last, the last.
//------------------------------------------------------------------------------
float At(const array<float>& in curve, float income)
{
	if ((curve.length() == 0) || (INCOME.length() == 0))
		return 0.f;
	if (income <= INCOME[0])
		return curve[0];
	for (uint i = 1; (i < INCOME.length()) && (i < curve.length()); ++i) {
		if (income < INCOME[i]) {
			const float span = INCOME[i] - INCOME[i - 1];
			if (span <= 0.f)
				return curve[i];
			const float t = (income - INCOME[i - 1]) / span;
			return curve[i - 1] + (curve[i] - curve[i - 1]) * t;
		}
	}
	return curve[curve.length() - 1];
}

float At(const array<float>& in curve)
{
	return At(curve, Eco::MInc());
}

}  // namespace Targets
