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
// apexearth: "we make too many basic solars and not enough advanced solars...
// if we make over 250 energy per second then make advanced solars."
const float ADVSOL_MIN_ENERGY = 250.f;
// A generator is affordable when income covers its BUILD cost -- both resources --
// inside this many seconds. This is the whole tiering rule: nothing else decides
// when the ladder steps up.
const float AFFORD_SECONDS = 90.f;

// WHICH SOLAR, EVERYWHERE.
//
// HomeEnergy's ladder already tiered up correctly, but it was not the only thing
// building collectors: the Brain's energy-stall want, the metal-full fallback and
// the commander's last resort each picked armsolar directly -- two of them off
// `Factory::gHaveT2`, which is a tech question, not an energy one. So a base
// making 400 energy/second kept putting down 20-energy panels from three
// different rules. This is the single answer they all use now.
CCircuitDef@ SolarDef()
{
	if (aiEconomyMgr.energy.income
			>= ai.GetTunable("apex_advsol_energy", ADVSOL_MIN_ENERGY)) {
		CCircuitDef@ adv = SideDef3(armadvsol, coradvsol, legadvsol);
		if ((adv !is null) && adv.IsAvailable(ai.frame))
			return adv;
	}
	return SideDef3(armsolar, corsolar, legsolar);
}


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

// THE LADDER HAS A TOP RUNG AND WE NEVER CLIMBED IT. apexearth: "we have 9
// fusions but don't seem to care to make any AFUS."
//
// An advanced fusion is roughly three reactors in one building and one
// footprint, which matters once the base is full of them. Chosen once the
// economy can pay for it and the constructor can actually build it -- asking a
// T1 constructor for one is the silent no-op this repo has been bitten by.
// Roughly where a human gets to it -- two fusions and a few advanced converters
// in, well under 100 m/s. An expectation, not a rule; both are tunable.
const float AFUS_INCOME = 70.f;    // metal/s at which the big reactor pays
const int   AFUS_AFTER  = 2;       // ...and only once two plain ones are up

CCircuitDef@ FusionDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armuwfus, coruwfus, coruwfus);
	CCircuitDef@ plain = SideDef3(armfus, corfus, legfus);
	if ((aiEconomyMgr.metal.income >= AFUS_INCOME)
		&& (plain !is null) && (plain.count >= AFUS_AFTER))
	{
		CCircuitDef@ adv = SideDef3("armafus", "corafus", "legafus");
		if ((adv !is null) && adv.IsAvailable(ai.frame))
			return adv;
	}
	return plain;
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
// The cooldown is about the ADVANCED converter, which is 380 metal and 21,000
// energy to build. A cheap one costs ONE metal, and the spill already says how
// many the grid can feed -- so serialising those at 90 seconds apiece meant a
// base overflowing energy crawled towards the fix a converter and a half per
// game minute. apexearth: "Don't be afraid to make more than one tier1
// converter at a time."
const int   HOME_CONV_PERIOD = 90 * SECOND;
const int   HOME_CONV_T1_PERIOD = 3 * SECOND;   // enough to not queue duplicates
int gNextConv = 0;

// Metal income above which a reactor is worth it regardless of role. A fusion
// is ~4,300 metal and pays for every advanced thing that follows.
const float FUSION_SOLO_INCOME = 30.f;
// How much longer a non-eco-lead waits between reactors.
const float FUSION_OTHER_MULT = 2.0f;
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
			+ " steady=" + formatFloat(Factory::SteadyIncome(), "", 0, 0)
			+ " wasting=" + (EnergyWasting() ? "1" : "0")
			+ " advsolCount=" + ((solarDef is null) ? -1 : solarDef.count)
			+ " fusCount=" + FusionDef(unit).count);
	}

	// A REACTOR IS NOT A TEAM ROLE. This required EcoLeadActive(), which is an
	// election among ALLIES -- so a solo player never built a fusion at all, and
	// in a team game only one player ever did. apexearth, watching a 1v1 against
	// hard: "hard AI dominating us, making fusions way earlier even though we
	// seemed to have good early game mexes... we are full metal but haven't even
	// started a fusion."
	//
	// Anyone whose economy has outgrown solar belongs on reactors. The eco lead
	// still gets its own faster cadence below; this is the floor for everyone
	// else.
	// NO "NEVER" ON ECONOMY. apexearth: "non-eco players should always build
	// fusions and converters when they get to the proper economy. Shouldn't ever
	// have that kind of logic that says 'never do this' when it comes to eco."
	//
	// The role decides the CADENCE, not the permission: the eco lead comes back
	// to this sooner because that is its job, and everyone else builds a reactor
	// the moment their own economy justifies one. The conditions below -- T2
	// exists, the bank can pay, energy is not already spilling -- are the real
	// answer, and they are the same for every player.
	// apexearth: "after I go T2, upgrade my mexes, I'm usually then making a
	// fusion. and I usually have over 30 metal per second after having upgraded my
	// mexes." Steady income, so a reclaim burst does not trigger one early.
	if (Factory::SteadyIncome()
		< ai.GetTunable("apex_fusion_income", FUSION_SOLO_INCOME))
	{
		return null;
	}
	// A T1 constructor cannot build one; asking anyway is the silent no-op this
	// repo has been bitten by before.
	if (!Factory::gHaveT2)
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
	// Cadence is where the role lives now: the eco lead returns to reactors
	// sooner because that is its job, everyone else waits longer between them.
	gNextFusion = ai.frame + (Factory::EcoLeadActive()
			? FUSION_PERIOD : int(float(FUSION_PERIOD) * FUSION_OTHER_MULT));
	++gFusionsAsked;
	AiLog(Factory::T() + "apex: eco fusion " + want.GetName()
		+ " standing=" + want.count + " asked=" + gFusionsAsked
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0));
	return post;
}

}  // namespace Builder
