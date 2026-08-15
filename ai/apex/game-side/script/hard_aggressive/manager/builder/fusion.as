namespace Builder {

// Fusions, placed in the economy lanes of the same band. 4,300 metal each in
// this game tree, so this is self-limiting against the bank: one fusion drops
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
	CCircuitDef@ adv = AdvSolDef();
	if (adv !is null)
		return adv;
	return SideDef3(armsolar, corsolar, legsolar);
}

// count is incremented on unit CREATION, nanoframe included
// (CCircuitAI::RegisterTeamUnit), so this reads as "we are making one".
int ReactorCount()
{
	int n = 0;
	CCircuitDef@ plain = SideDef3(armfus, corfus, legfus);
	if (plain !is null)
		n += plain.count;
	CCircuitDef@ adv = SideDef3(armafus, corafus, legafus);
	if (adv !is null)
		n += adv.count;
	CCircuitDef@ sea = SideDef3(armuwfus, coruwfus, coruwfus);
	if (sea !is null)
		n += sea.count;
	return n;
}

bool HaveReactor()
{
	return ReactorCount() > 0;
}

// SECTIONS, NOT A FARM. Reactors closer than this chain their death
// explosions: measured (match 20260815-150954) five AFUS at ~400-elmo
// spacing died inside two minutes, two of them 19 frames apart, and each
// same-frame commander pair died in the middle of that cluster. apexearth:
// keep advanced fusions spread out into sections so one loss cannot take
// the base. The gap is derived from that observed 400-elmo chain, with
// margin; tunable.
const float REACTOR_SECTION = 700.f;

bool ReactorSectionClear(const AIFloat3& in spot)
{
	const float gap = ai.GetTunable("apex_reactor_spacing", REACTOR_SECTION);
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i].GetPos(ai.frame).distance2D(spot) < gap)
			return false;
	}
	return true;
}

// A blocked spot is pushed straight out of the offending section to the
// boundary and re-sited locally; a veto alone would stall reactors outright,
// since the band placement re-proposes the same crowded spot forever.
bool SectionSafeSpot(CCircuitDef@ want, const AIFloat3& in cur, AIFloat3& out spot)
{
	spot = cur;
	if (ReactorSectionClear(cur))
		return true;
	const float gap = ai.GetTunable("apex_reactor_spacing", REACTOR_SECTION);
	int nearest = -1;
	float best = 1.0e18f;
	for (uint i = 0; i < gFusions.length(); ++i) {
		const float d = gFusions[i].GetPos(ai.frame).distance2D(cur);
		if (d < best) { best = d; nearest = int(i); }
	}
	if (nearest < 0)
		return true;
	const AIFloat3 anchor = gFusions[uint(nearest)].GetPos(ai.frame);
	AIFloat3 dir = cur - anchor;
	if (dir.SqLength2D() < 1.f) {
		dir = gHomePos - anchor;   // degenerate: shove toward home
		if (dir.SqLength2D() < 1.f)
			return false;
	}
	dir.SafeNormalize2D();
	AIFloat3 cand = anchor + dir * (gap * 1.15f);
	if (!OnMap(cand))
		return false;
	const AIFloat3 site = ai.FindBuildSiteNear(want, cand, 400.f);
	if (!OnMap(site) || !ReactorSectionClear(site))
		return false;
	spot = site;
	return true;
}

// HOW MANY REACTOR TASKS MAY BE IN FLIGHT -- NOT A CEILING ON HOW MANY REACTORS
// WE MAY OWN. It bounds unfinished WORK, and every reactor that finishes frees
// its slot, so the number we end up with is still whatever the economy pays for.
//
// AFFORD_SECONDS is already this file's answer to "can income pay for this
// generator", so asking how many times over income covers it inside the same
// window is the same test applied to concurrency. Floor of one: the first
// reactor is never blocked. No ceiling -- a richer economy may run more.
int ReactorsInFlight(float cost)
{
	if (cost < 1.f)
		return 1;
	const int n = int(aiEconomyMgr.metal.income * AFFORD_SECONDS / cost);
	return (n < 1) ? 1 : n;
}

// Null once a reactor stands: obsolete.as already names a reactor as this def's
// successor and reclaims it, so without this the same def was built and torn
// down at the same time.
CCircuitDef@ AdvSolDef()
{
	if (HaveReactor())
		return null;
	if (aiEconomyMgr.energy.income
			< ai.GetTunable("apex_advsol_energy", ADVSOL_MIN_ENERGY))
		return null;
	CCircuitDef@ adv = SideDef3(armadvsol, coradvsol, legadvsol);
	return ((adv !is null) && adv.IsAvailable(ai.frame)) ? adv : null;
}


// HOW GOOD A GENERATOR IS, IN ENERGY PER METAL -- the single ranking every rung
// of the ladder is judged by. -1 means "not a candidate": no def, not yet
// buildable, or no cost to divide by.
//
// GetEnergyMake reports what a def makes on THIS map, so a wind turbine is
// scored at the map's own wind speed with no wind API needed. Nothing here asks
// whether the bank can pay: how many builders may pile onto one expensive site
// is bounded by income in Requests::InFlightCap, which is the constraint the old
// AFFORD_SECONDS bank gate was standing in for.
float EnergyValuePerMetal(CCircuitDef@ d)
{
	if ((d is null) || !d.IsAvailable(ai.frame) || (d.costM <= 0.f))
		return -1.f;
	return aiEconomyMgr.GetEnergyMake(d) / d.costM;
}
// How far from home to look when the grid has no cell left.
const float ECO_FALLBACK_RANGE = 1400.f;
// Tight enough that the next building lands touching the last one.
const float ECO_PACK_RANGE = 180.f;
AIFloat3 gEcoLast;
bool gEcoPacked = false;
// Energy income wanted per point of metal income before the grid is 'enough'.
const float ENERGY_LEAD_RATIO = 12.f;

// An advanced fusion is roughly three reactors in one building and one
// footprint, which matters once the base is full of them. Chosen once the
// economy can pay for it and the constructor can actually build it -- asking a
// T1 constructor for one is a silent no-op. Both thresholds are tunable.
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

// The cooldown exists because script-side Enqueue has no CanEnqueueTask check
// (BuilderScript.cpp:67), unlike the C++ economy generator, which is budgeted
// via CEconomyManager::MakeEconomyTasks (buildTasksCount < workers.size() * 8)
// and whose unassigned tasks hold a slot for ASSIGN_TIMEOUT (300s) -- an
// uncooled rung can spend that shared budget faster than it's reclaimed.
// The cooldown applies only to the advanced converter (380 metal); the cheap T1
// converter (1 metal) is not serialised, since the spill already bounds how
// many the grid can feed.
const int   HOME_CONV_PERIOD = 90 * SECOND;
const int   HOME_CONV_T1_PERIOD = 3 * SECOND;   // enough to not queue duplicates
int gNextConv = 0;

// Metal income above which a reactor is worth it regardless of role. A fusion
// is ~4,300 metal and pays for every advanced thing that follows.
const float FUSION_SOLO_INCOME = 30.f;
// apexearth: choose fusion over advanced solar outright once income clears
// this, rather than waiting for the per-metal ranking to (unreliably) favor
// it -- see HomeEnergy's forcedFusion override.
const float FUSION_PREFER_INCOME = 50.f;
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
	// Unconditional, ahead of every early return below, so it also shows how
	// often this rule's OWN gates block it versus DefaultMakeTask's fallback
	// energy list ranking solar/advsol ahead of fusion.
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

	// A reactor is not gated on EcoLeadActive() (an ally election, false for a
	// solo player). The role decides CADENCE only, not permission: eco lead comes
	// back to this sooner, everyone else builds a reactor once their own economy
	// clears these same conditions.
	// Steady income, so a reclaim burst does not trigger one early.
	//
	// OR: the advsol farm has already proven the demand. The income bar is
	// per-player and solo-calibrated; in a team game players sit under it for
	// twenty minutes while stacking advanced solars -- once the metal already
	// sunk into them exceeds a fusion's cost, the economy has demonstrated it
	// wants fusion-scale energy and the bar has nothing left to protect
	// (apexearth, watching: a player "makes the fusion far far too late";
	// measured 20-30 minute firsts and two players never, one 8v8).
	bool investedEnough = false;
	{
		CCircuitDef@ advsol = SideDef3(armadvsol, coradvsol, legadvsol);
		CCircuitDef@ plainFus = SideDef3(armfus, corfus, legfus);
		if ((advsol !is null) && (plainFus !is null))
			investedEnough = float(advsol.count) * advsol.costM >= plainFus.costM;
	}
	if (!investedEnough
		&& (Factory::SteadyIncome()
			< ai.GetTunable("apex_fusion_income", FUSION_SOLO_INCOME)))
	{
		return null;
	}
	// A T1 constructor cannot build one; asking anyway is the silent no-op this
	// repo has been bitten by before.
	if (!Factory::gHaveT2)
		return null;
	// apexearth 2026-08-15: this used to refuse while EnergyWasting() (bank
	// nearly full or spare energy over CONVERT_MIN_SPARE), on the theory that
	// converters would clear the spill first and a reactor could wait. In
	// practice EnergyWasting() is true almost permanently once the base
	// matures -- T1 cons keep stacking armadvsol (the only reactor-tier
	// generator they can build) to answer exactly this kind of spare energy,
	// which keeps the bank topped up, which never let this rule see
	// !EnergyWasting() again. Confirmed live: wasting=1 on nearly every
	// sample from 9 minutes on, fusCount stuck at 0 through 375 income.
	// Chronic waste from generator sprawl is what a reactor is FOR, not a
	// reason to withhold one -- see the same fix in HomeEnergy()'s own
	// EnergyWasting() branch.

	CCircuitDef@ want = FusionDef(unit);

	// Outstanding bound. count sees FINISHED buildings only and Enqueue does not
	// dedup, so the cooldown alone re-asks for the whole minutes a reactor takes.
	// Left inside the null check so a missing def still reaches the diagnostic.
	if (want !is null) {
		const int allowed = ReactorsInFlight(want.costM);
		const int built = ReactorCount();
		int outstanding = gFusionsAsked - built;
		// HomeEnergy builds reactors without touching gFusionsAsked, so this can
		// drift negative; resetting on EITHER side keeps a desync from wedging
		// it. Negative was the live case and only the high side was caught, so
		// the bound stopped binding entirely once HomeEnergy got ahead.
		if ((outstanding < 0) || (outstanding > allowed * 2)) {
			gFusionsAsked = built;
			outstanding = 0;
		}
		if (outstanding >= allowed)
			return null;
	}

	// Only an asker that can actually BUILD the reactor may request one --
	// measured (8v8 Glitters, 20260815-064126): 208 fusion tasks handed to
	// T1 constructors, every one a guaranteed capability-guard null, zero
	// fusions built all game while stock built nine on the same income. The
	// early return leaves the want standing for the next advanced constructor
	// that reaches this rule instead of burning it on a unit that cannot act.
	if ((want !is null) && !unit.circuitDef.CanBuild(want))
		return null;

	AIFloat3 spot;
	const bool okDef = (want !is null) && want.IsAvailable(ai.frame);
	// BandSpot's deep band is only the BACK of the base while the latched axis
	// points at the enemy, so it cannot be the only answer for a reactor.
	// ReactorSpot declining falls through to exactly the old placement.
	int rear = 0;
	if (okDef)
		rear = ReactorSpot(unit, want, spot);
	bool okSpot = okDef && ((rear != 0) || BandSpot(unit, want, false, spot));
	// Out of any existing reactor's chain-blast section, or shifted out of it.
	if (okSpot) {
		AIFloat3 sectioned;
		if (SectionSafeSpot(want, spot, sectioned))
			spot = sectioned;
		else
			okSpot = false;
	}
	// Same handoff as HomeEnergy: this rule decides a reactor is wanted here,
	// Requests decides whether that is a new one or joining one already
	// requested. Neither the counter nor the cooldown moves for a join --
	// nothing new was asked for.
	bool created = false;
	IUnitTask@ post = null;
	if (okSpot) {
		@post = Requests::Take(unit, want, Task::BuildType::ENERGY,
				Task::Priority::NORMAL, spot, 0.f, 0.f, created);
	}
	if ((post !is null) && !created)
		return post;
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
	// at= is what separates this path from HomeEnergy's and from the C++
	// placement in a log: without a position all three look alike.
	string via = "band";
	if (rear == 1)
		via = "heavy";
	else if (rear == 2)
		via = "rear";
	AiLog(Factory::T() + "apex: eco fusion " + want.GetName()
		+ " standing=" + want.count + " asked=" + gFusionsAsked
		+ " at=" + int(spot.x) + "," + int(spot.z)
		+ " via=" + via
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0));
	return post;
}

}  // namespace Builder
