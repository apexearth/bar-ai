namespace Role {

// THE ROLE LAYER, kill phase (docs/20-brain-overhaul.md): the policy methods
// and objective machinery died with their consumers. What survives is the
// SENSE the rebuild will price Wants from -- the build-power measurement --
// and the two answers kept callers still ask.

// Per-class lathe drains, unit PHYSICS (measured workerTime scale), not policy.
const float DRAIN_CON_T1  = 7.f;    // armck/corck ~90 workerTime
const float DRAIN_CON_AIR = 8.f;    // armca ~100
const float DRAIN_CON_ADV = 14.f;   // armack ~180
const float DRAIN_NANO    = 15.f;   // armnanotc ~200
const float DRAIN_COMM    = 23.f;   // armcom ~300

float gBP = 0.f;

float CountDrain(CCircuitDef@ d, float per)
{
	return (d is null) ? 0.f : float(d.count) * per;
}

float StandingBP()
{
	float bp = 0.f;
	bp += CountDrain(SideDef3("armck",     "corck",     "legck"),     DRAIN_CON_T1);
	bp += CountDrain(SideDef3("armcv",     "corcv",     "legcv"),     DRAIN_CON_T1);
	bp += CountDrain(SideDef3("armca",     "corca",     "legca"),     DRAIN_CON_AIR);
	bp += CountDrain(SideDef3("armack",    "corack",    "legack"),    DRAIN_CON_ADV);
	bp += CountDrain(SideDef3("armacv",    "coracv",    "legacv"),    DRAIN_CON_ADV);
	bp += CountDrain(SideDef3("armaca",    "coraca",    "legaca"),    DRAIN_CON_ADV);
	bp += CountDrain(SideDef3("armnanotc", "cornanotc", "legnanotc"), DRAIN_NANO);
	// The commander is deliberately NOT counted: it is the opening's given,
	// not a controller purchase.
	return bp;
}

void Resolve()
{
	gBP = StandingBP();
}

// The quiet rear specialist builds no GROUND defence; every request rule
// funnels through this gate (Requests::Take), so paths the market does not
// own are covered too. Take exempts air-only defence: static AA shares the
// DEFENCE build-type, and the rear specialist still has to answer bombers.
bool DefenceAllowed()
{
	return !Market::EcoQuiet();
}

}  // namespace Role
