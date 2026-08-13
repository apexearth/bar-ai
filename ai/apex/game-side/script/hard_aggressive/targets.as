//==============================================================================
// TARGETS -- every build ratio this AI aims at, as curves over economic power.
//
// apexearth: "I want to have a pretty easy to look at and modify file to manage
// our army composition targets", then "I need to be able to split this into
// economic brackets somehow. Or to be able to build a curve. Raiders at .3 to
// start is OK but later on I want it lower."
//
// So every row below is a CURVE, read against metal income. One shared income
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
//         --a Apex:apex:hard_aggressive --b BARb:stable:hard \
//         --map "Comet Catcher" --minutes 5 --out matches/_check
//     grep -c " : ERR " matches/_check/infolog.txt      # must be 0
//==============================================================================

namespace Targets {

// The economic brackets every curve below is read against, in metal/second.
// Roughly: opening, first expansion, a real economy, a strong one, late game.
array<float> INCOME = { 8.f,  20.f,  50.f, 100.f, 300.f};

//------------------------------------------------------------------------------
// 1. HOW THE METAL IS SPLIT, by what it is FOR.
//
// Measured live before this existed: army 0.11-0.21, defence 0.25-0.35,
// buildpower 0.33-0.39. Nothing claimed metal for the army, so it got whatever
// towers and constructors left behind -- which is why the trade ratio sat at
// 0.39 against stock's 1.22.
//
// Early the economy and build power matter most; once there is an economy to
// spend, the army takes the largest share.
//
// RELATIVE WEIGHTS -- they do NOT have to add up to anything. {3, 1, 2, 2} says
// the same as {0.375, 0.125, 0.25, 0.25}; raise one row and the others fall by
// themselves. Written here as thirds and halves so the intent is readable rather
// than as decimals that happen to sum to one.
//                            8     20     50    100    300
//------------------------------------------------------------------------------
// LAND DEFENCE AND AIR DEFENCE ARE SEPARATE ROWS, AND THEY MUST BE.
//
// apexearth, 2026-08-12: "dampening defense at 10% is what I said to do for Air
// defenses. I do not mean we should do that for land defenses." The old single
// SPEND_DEFENCE row carried the number he gave for ANTI-AIR and applied it to
// every tower, and AirCoverWant and FrontDefenceWant both proposed under the
// same "fence" kind, so they competed for one allowance.
//
// SPEND_AIRDEF keeps the row he specified, unchanged, and now means only what he
// meant by it.
//
// SPEND_DEFENCE is a MEASURED default, not a chosen one. Static defence spend as
// a share of metal built, 4v4 Comet Catcher vs BARb:stable:hard, 22-24 minutes,
// two runs (matches/20260812-081605-*, -083510-*): stock 10.8-30.5% while
// trading 1.94 in metal, us 2.4-13.3% while trading 0.31. The row below sits at
// ~21% of the split early and tapers as the army share climbs, which puts us in
// stock's measured band instead of a fifth of it. It is a starting point to be
// A/B'd, and every entry is tunable (apex_share_defence, apex_share_airdef).
//                            8     20     50    100    300
array<float> SPEND_ARMY       = {  3.f,   4.f,   5.f,   6.f,   10.f};
// ~26% of the split early: the upper half of stock's measured 15-33% band.
//
// THE LATE-GAME DEFENCE SHARE MUST NOT BE THE SMALLEST. apexearth, three times
// on 2026-08-12: "we need EXTRA defense on the edges", "whatever logic you have
// for making defenses in general isn't good enough", "We should be making tons of
// T3 defenses and shields late in the game."
//
// This row used to be the only one that FELL with income -- after normalising
// against the other four it gave 25.9% at 8 metal/s, 27.6% at 20, 22.6% at 50,
// 18.9% at 100 and 8.3% at 300 -- so the budget shrank exactly where he wants it
// largest. The 8 and 20 entries are unchanged measured values; 50 and 100 are set
// equal to the 20 entry, holding the measured mid-game weight flat rather than
// decaying it; and 300 is chosen so that after normalisation against the RISING
// army row the late share is not the smallest of the five. That gives
// 25.9 / 27.6 / 28.0 / 27.2 / 27.5 percent, inside stock's measured band at every
// step. Above ~4.5 at the 300 step every further point comes out of ARMY, not the
// economy: at that income the economy row is 1.0 and its share barely moves.
array<float> SPEND_DEFENCE    = {3.5f,   4.f,   4.f,   4.f,   5.f};
array<float> SPEND_AIRDEF     = {  1.f,   2.f,  1.5f,  1.5f,  0.5f};
array<float> SPEND_ECONOMY    = {3.5f,  2.7f,   2.f,  1.5f,   1.f};
array<float> SPEND_BUILDPOWER = {2.5f,  1.8f,  1.8f,  1.7f,  1.7f};

//------------------------------------------------------------------------------
// 2. WHAT THE ARMY IS MADE OF.
//
// The role decides how CircuitAI uses the unit, so these are tactical choices:
//     RAIDER  -> raid parties, roam for weak spots        (Pawn, Grunt)
//     ASSAULT -> the main attack group                    (Hound, Welder)
//     SKIRM   -> outranges riots and assaults             (Gunslinger)
//     RIOT    -> DEFEND tasks; the anti-raider answer     (Marauder)
//     ARTY    -> siege, outranges static defence
//     AA      -> anti-air, further scaled by observed enemy air
//     HEAVY   -> the T2 push units                        (Fatboy)
//     AH/AHA  -> anti-heavy; snipers and tank-killers     (Sharpshooter)
//
// Chaff fades as the economy grows -- "Raiders at .3 to start is OK but later on
// I want it lower", and a 54-metal Pawn dies to one shot from anything a real
// economy fields. The heavy and anti-heavy rows climb to meet it, because that
// is what the metal buys instead.
//                            8     20     50    100    300
//------------------------------------------------------------------------------
// RAIDERS ARE A T1 UNIT. apexearth: "We should make more snipers, fatboys,
// jammers, *no* T2 raiders." A raider's job is reaching undefended ground early;
// once both sides hold a line it is metal walking into a turret. The row goes to
// zero above the T1 economy rather than tapering, because "some" T2 raiders is
// what a taper buys and he asked for none.
// Never zero past T1. It read {..., 0, 0, 0}, so from 50 metal/s upward we built
// no cheap fast unit at all -- exactly when enemy jammers make seeing them the
// problem. apexearth: "once we are in T2 phase the only T1 we should make is the
// lightest T1 units, not a TON of them, and their behavior should be far more
// suicidal." A small standing share of 42-metal Grunts is a lot of eyes.
array<float> ROLE_RAIDER  = {0.35f, 0.10f, 0.05f, 0.04f, 0.03f};
array<float> ROLE_ASSAULT = {0.35f, 0.2f, 0.24f, 0.18f, 0.08f};
array<float> ROLE_SKIRM   = {0.12f, 0.25f, 0.17f, 0.15f, 0.14f};
array<float> ROLE_RIOT    = {0.10f, 0.10f, 0.10f, 0.09f, 0.08f};
array<float> ROLE_ARTY    = {0.03f, 0.05f, 0.08f, 0.10f, 0.12f};
array<float> ROLE_AA      = {0.05f, 0.06f, 0.07f, 0.07f, 0.07f};
// Fatboys, and the anti-heavy pair that is Snipers and tank-killers. These are
// what the raider share becomes: units that hold ground and outrange what walks
// into them, which is the composition for being pushed back rather than pushing.
array<float> ROLE_HEAVY   = {0.00f, 0.02f, 0.20f, 0.26f, 0.28f};
array<float> ROLE_AH      = {0.00f, 0.00f, 0.07f, 0.10f, 0.12f};
array<float> ROLE_AHA     = {0.00f, 0.00f, 0.07f, 0.10f, 0.11f};

//------------------------------------------------------------------------------
// 2b. HOW DEFENCE ITSELF IS SPLIT.
//
// Two different jobs share the SPEND_DEFENCE share, and they must not compete
// for it: holding the front line is the Brain's macro decision, while guarding
// an extractor or answering a constructor that keeps being shot is local work
// that belongs to the rule that noticed. On one shared allowance the local work
// wins by sheer number -- there are far more mexes than lanes -- and the front
// line ends up depending on how many extractors we happen to own.
//
// Relative weights, like everything else here.
//                       8     20     50    100    300
//------------------------------------------------------------------------------
array<float> DEF_FRONT = {1.f,  2.f,  3.f,  3.f,  3.f};   // the Brain's line
array<float> DEF_LOCAL = {2.f,  2.f,  1.f,  1.f,  1.f};   // mex guards, dig-ins

//------------------------------------------------------------------------------
// 3. HOW FAR THE OBSERVED ENEMY MOVES THE MIX.
//
// Each role answers particular enemy roles -- riot answers raiders, skirmish
// answers riots and assaults. This is the most their composition may pull the
// table above: 0 keeps it fixed, 1 would let one sighting rewrite it.
//------------------------------------------------------------------------------
const float COUNTER_MAX = 0.6f;

//------------------------------------------------------------------------------
// 4. SCOUTS.
//
// Eyes are a floor rather than a share -- they are too cheap for a metal share
// to yield a useful count. This is how many extractors we hold per scout wanted,
// and it rises with income because a rich base has radar and better things to
// spend a slot on.
//                       8     20     50    100    300
//------------------------------------------------------------------------------
array<float> SCOUT_PER_MEX = {1.f,  1.f,  2.f, 4.f, 8.f};

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
	return At(curve, aiEconomyMgr.metal.income);
}

}  // namespace Targets
