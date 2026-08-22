namespace Builder {

// ONE CURRENCY FOR EVERY ECONOMY PURCHASE: metal-equivalent per second.
// apexearth: "standardize our energy and metal logic based on efficiency and
// time to profit." A mex yields metal directly; a generator's energy converts
// at the rate the economy itself pays for the exchange (a converter's own
// make-per-drain); a converter yields metal directly. On top of the gain, two
// standard measures every rule can share:
//
//   EcoEfficiency  gain per second per metal invested -- ranks WHAT to buy.
//   EcoPayback     seconds until the purchase has repaid its metal -- with
//                  affordability (income covering the cost inside a horizon),
//                  decides WHETHER NOW.
//
// Both are derived from def stats and live map/economy reads. No flat gates.

// Metal bought per 1 energy: the small converter's own numbers (1 metal/s per
// 70 energy/s drained). This is the marginal exchange rate the economy can
// always realise, so it is the honest FLOOR on what a point of energy is worth.
float EnergyToMetalRate()
{
	return 1.f / Brain::CONVERT_DRAW;
}

// What this def adds, in metal-equivalent per second, on THIS map.
// GetMetalMake covers mexes (spot average x extraction) and converters
// (make); GetEnergyMake covers every generator including wind at the map's
// average and geo at the vent's yield.
float EcoGainPerSec(CCircuitDef@ d)
{
	if (d is null)
		return 0.f;
	const float m = aiEconomyMgr.GetMetalMake(d);
	if (m > 0.f)
		return m;
	return aiEconomyMgr.GetEnergyMake(d) * EnergyToMetalRate();
}

// Gain per second per metal invested. Higher is better; <= 0 means "not an
// economy building" and the caller should not rank it here.
float EcoEfficiency(CCircuitDef@ d)
{
	if ((d is null) || (d.costM <= 0.f))
		return 0.f;
	return EcoGainPerSec(d) / d.costM;
}

// Seconds until the purchase has repaid its own metal. Infinity-ish for a
// def with no yield; callers compare paybacks, they do not gate on a magic
// ceiling.
float EcoPayback(CCircuitDef@ d)
{
	const float g = EcoGainPerSec(d);
	if ((d is null) || (g <= 0.f))
		return 1.0e9f;
	return d.costM / g;
}

// CAN THE FLOW PAY FOR IT INSIDE THE HORIZON -- the liquidity half of "time
// to profit", asked separately for each resource because they starve
// independently: a geo is trivial metal (560) and enormous energy (13,000),
// so at 250 e/s it is ~52 seconds of the grid's whole output. AFFORD_SECONDS
// (fusion.as) is the established metal horizon; the energy horizon gets its
// own tunable with the same default.
bool EcoAffordableM(CCircuitDef@ d)
{
	if (d is null)
		return false;
	return aiEconomyMgr.metal.income
			* ai.GetTunable("apex_afford_secs", AFFORD_SECONDS) >= d.costM;
}

bool EcoAffordableE(CCircuitDef@ d)
{
	if (d is null)
		return false;
	return aiEconomyMgr.energy.income
			* ai.GetTunable("apex_afford_e_secs", TUNE_AFFORD_E_SECS) >= d.costE;
}

// The standing table, for calibration: what the standardized math says about
// every rung it would compare, so an arm's log shows where the shared
// currency and the live rules disagree before any rule is cut over to it.
int gNextEcoMathLog = 0;
void EcoMathDiag()
{
	if (ai.frame < gNextEcoMathLog)
		return;
	gNextEcoMathLog = ai.frame + 120 * SECOND;
	string line = "apex: eco-math";
	array<CCircuitDef@> defs = {
		SideDef3("armmex", "cormex", "legmex"),
		SideDef3("armmoho", "cormoho", "legmoho"),
		SideDef3(armwin, corwin, legwin),
		SideDef3(armsolar, corsolar, legsolar),
		SideDef3(armadvsol, coradvsol, legadvsol),
		SideDef3("armgeo", "corgeo", "leggeo"),
		SideDef3(armfus, corfus, legfus)
	};
	for (uint i = 0; i < defs.length(); ++i) {
		CCircuitDef@ d = defs[i];
		if (d is null)
			continue;
		line += " " + d.GetName()
			+ "=" + formatFloat(EcoGainPerSec(d), "", 0, 2)
			+ "/" + formatFloat(EcoPayback(d), "", 0, 0) + "s"
			+ (EcoAffordableM(d) ? "" : "!m") + (EcoAffordableE(d) ? "" : "!e");
	}
	AiLog(Factory::T() + line);
}

}  // namespace Builder
