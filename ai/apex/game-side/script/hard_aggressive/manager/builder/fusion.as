namespace Builder {

// Fusions, placed in the economy lanes of the same band.
//
// The eco lead built NO fusion at all in the game that was read unit by unit,
// while every one of its teammates had one -- it is the player with the largest
// income and it was not buying the thing that turns income into late game. Left
// to stock task selection it spends on mexes and stalls there.
//
// 4,300 metal each in this game tree (upstream says 3,350 -- read from the defs,
// not remembered), so this is self-limiting against the bank: one fusion drops
// us under the gate until the economy refills it.
string armfus("armfus"); string corfus("corfus"); string legfus("legfus");
string armafus("armafus"); string corafus("corafus"); string legafus("legafus");
// The naval reactors. armacsub/coracsub carry armuwfus/coruwfus and no land
// reactor, so a ship or sub constructor handed corfus holds a task it can never
// start. Legion reaches T2 sea through coracsub, hence the Cortex def for it.
// Declared here rather than beside the converter defs above because a global has
// to precede its first use; a function does not.
string armuwfus("armuwfus"); string coruwfus("coruwfus");
string armadvsol("armadvsol"); string coradvsol("coradvsol"); string legadvsol("legadvsol");
// Energy income before the advanced collector is worth its 5,000-energy build.
const float ADVSOL_MIN_ENERGY = 200.f;
// A generator is affordable when income covers its BUILD cost -- both resources --
// inside this many seconds. This is the whole tiering rule: nothing else decides
// when the ladder steps up.
const float AFFORD_SECONDS = 90.f;

bool AffordableGen(CCircuitDef@ d)
{
	if ((d is null) || !d.IsAvailable(ai.frame))
		return false;
	if (d.costM > aiEconomyMgr.metal.income * AFFORD_SECONDS)
		return false;
	if (d.costE > aiEconomyMgr.energy.income * AFFORD_SECONDS)
		return false;
	return true;
}
// How far from home to look when the grid has no cell left.
const float ECO_FALLBACK_RANGE = 1400.f;
// Tight enough that the next building lands touching the last one.
const float ECO_PACK_RANGE = 180.f;
AIFloat3 gEcoLast;
bool gEcoPacked = false;
// Energy income wanted per point of metal income before the grid is 'enough'.
const float ENERGY_LEAD_RATIO = 12.f;

CCircuitDef@ FusionDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armuwfus, coruwfus, coruwfus);
	return SideDef3(armfus, corfus, legfus);
}

// Converters get the same cooldown a reactor gets, and for the same reason: a
// script-side aiBuilderMgr.Enqueue is bound straight to CBuilderManager::Enqueue
// with no CanEnqueueTask check (BuilderScript.cpp:67), while the C++ economy
// generator that creates mex and mex-upgrade tasks is budgeted --
// CEconomyManager::MakeEconomyTasks returns null on
// !CanEnqueueTask() == !(buildTasksCount < workers.size() * 8). An unassigned
// build task holds its slot for ASSIGN_TIMEOUT (300s) before ITaskModule::Update
// aborts it, so an uncooled rung spends that shared budget faster than it can be
// reclaimed.
const int   HOME_CONV_PERIOD = 90 * SECOND;
int gNextConv = 0;

const float FUSION_MIN_BANK = 0.55f;
const int   FUSION_PERIOD   = 45 * SECOND;
const int   FUSION_DIAG_PERIOD = 45 * SECOND;
int gNextFusion = 0;
int gNextFusionLog = 0;
int gNextFusionDiagLog = 0;
int gFusionsAsked = 0;

IUnitTask@ EcoFusion(CCircuitUnit@ unit)
{
	// Diagnostic for notes/next-session-hypotheses.md #2: unconditional (ahead of
	// every early return below) so it also shows how often this function's OWN
	// gates are what block it, versus DefaultMakeTask falling through to the
	// engine's score-sorted energy list (economy.json) further down, where solar
	// and advsol sort ahead of fusion's default e-income bar.
	if (ai.frame >= gNextFusionDiagLog) {
		gNextFusionDiagLog = ai.frame + FUSION_DIAG_PERIOD;
		CCircuitDef@ solarDef = SideDef3(armadvsol, coradvsol, legadvsol);
		AiLog(Factory::T() + "apex: fusion-gate diag lead=" + (Factory::EcoLeadActive() ? "1" : "0")
			+ " haveT2=" + (Factory::gHaveT2 ? "1" : "0")
			+ " income=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
			+ "/" + formatFloat(aiEconomyMgr.metal.storage * FUSION_MIN_BANK, "", 0, 0)
			+ " wasting=" + (EnergyWasting() ? "1" : "0")
			+ " advsolCount=" + ((solarDef is null) ? -1 : solarDef.count)
			+ " fusCount=" + FusionDef(unit).count);
	}

	if (!Factory::EcoLeadActive() || (ai.frame < gNextFusion))
		return null;
	// A T1 constructor cannot build one; asking anyway is the silent no-op this
	// repo has been bitten by before.
	if (!Factory::gHaveT2)
		return null;
	if (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * FUSION_MIN_BANK)
		return null;
	// Not while we are already spilling energy. Measured over 8 games, the eco
	// lead wasted 46.7% of every joule it made -- 12.8 million per game against a
	// teammate's 2.2 -- so another 4,300-metal reactor was buying more of the one
	// thing it already could not use. Converters below turn that spill into
	// metal; a reactor only helps once the spill is gone.
	if (EnergyWasting())
		return null;

	CCircuitDef@ want = FusionDef(unit);

	// Instrumented because the first run of this rule fired ZERO times in 24
	// minutes while every gate above it read clear -- bank 1237/1250 against a
	// bar of 55%, haveT2 set, income 87 -- and there was no way to tell which of
	// def, placement or enqueue was refusing. Guessing at that has cost this repo
	// whole runs before.
	AIFloat3 spot;
	const bool okDef = (want !is null) && want.IsAvailable(ai.frame);
	const bool okSpot = okDef && BandSpot(unit, want, false, spot);
	IUnitTask@ post = okSpot
		? aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY,
				Task::Priority::NORMAL, want, spot, 0.f))
		: null;
	if (post is null) {
		if (ai.frame >= gNextFusionLog) {
			gNextFusionLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: eco fusion BLOCKED"
				+ " def=" + ((want is null) ? "null" : want.GetName())
				+ " avail=" + (okDef ? "1" : "0")
				+ " spot=" + (okSpot ? "1" : "0")
				+ " home=" + (gHomeSet ? "1" : "0"));
		}
		return null;
	}
	gNextFusion = ai.frame + FUSION_PERIOD;
	++gFusionsAsked;
	AiLog(Factory::T() + "apex: eco fusion " + want.GetName()
		+ " standing=" + want.count + " asked=" + gFusionsAsked
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0));
	return post;
}

}  // namespace Builder
