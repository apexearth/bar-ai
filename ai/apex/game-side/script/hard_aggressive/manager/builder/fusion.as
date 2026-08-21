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
// 100, was 250: the old bar was above the income the advsol itself provides
// the path to, so early game hovered stalling on winds while stock built five
// advsols to our two -- apexearth 2026-08-19: "the biggest problem early game
// is we are routinely e-stalling... they make ~5 advanced solars and we maybe
// get 2. If we get past that we do much better."
const float ADVSOL_MIN_ENERGY = 100.f;
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
// A reactor the metal income can pay for inside AFFORD_SECONDS -- the same
// tiering rule the HomeEnergy ladder steps up on.
bool ReactorAffordable()
{
	CCircuitDef@ fus = SideDef3(armfus, corfus, legfus);
	return (fus !is null) && fus.IsAvailable(ai.frame)
		&& (aiEconomyMgr.metal.income * AFFORD_SECONDS >= fus.costM);
}

CCircuitDef@ SolarDef()
{
	// A PANEL IS NEVER THE ANSWER WHILE A FUSION IS AFFORDABLE. The reclaim
	// cliff below is an INCOME test, so a late-game energy crash (reactors
	// die, income falls under the cliff) re-opened the plain-panel branch and
	// every fallback spammed 20-energy panels -- apexearth 2026-08-19, watching
	// it: "we made a bunch of solars in panic... we should have been making
	// fusions." Affordability, not income level, is what retires the panel.
	if (ReactorAffordable())
		return null;
	CCircuitDef@ adv = AdvSolDef();
	if (adv !is null)
		return adv;
	// NOT unconditionally the plain panel: after a reactor stood, this branch
	// handed back the most obsolete def in the game, and the commander built
	// it while the nano turrets reclaimed it. Null here means "the answer is
	// a reactor, not a panel" and every caller already handles null.
	CCircuitDef@ plain = SideDef3(armsolar, corsolar, legsolar);
	if ((plain !is null) && !EnergyReclaimable(plain.GetName()))
		return plain;
	return null;
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

// BATCHES, NOT FULL DISPERSION. apexearth: "you'll want to make ~10 afuses
// all near each other, but you'll want the next batch of 10 afuses to be
// outside of chainable range." Within a batch reactors pack (shared
// defence, AA, converters, compact base); BETWEEN batches the gap exceeds
// chain-blast reach, so one detonation costs at most one batch -- the
// measured chain (match 20260815-150954: five AFUS at ~400-elmo spacing
// died in one cascade, commanders included) is contained instead of
// forbidden. The gap is derived from that observed 400-elmo chain with
// margin; the batch size is his number.
const float REACTOR_SECTION = 700.f;
const int   REACTOR_BATCH   = 10;

// How many standing reactors sit within chain reach of this spot.
int ReactorNeighbors(const AIFloat3& in spot, AIFloat3& out centroid)
{
	const float gap = ai.GetTunable("apex_reactor_spacing", TUNE_REACTOR_SPACING);
	int n = 0;
	centroid = AIFloat3(0.f, 0.f, 0.f);
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i] is null)
			continue;
		const AIFloat3 at = gFusions[i].GetPos(ai.frame);
		if (at.distance2D(spot) < gap) {
			centroid += at;
			++n;
		}
	}
	if (n > 0)
		centroid = centroid * (1.f / float(n));
	return n;
}

bool ReactorBatchOK(const AIFloat3& in spot)
{
	AIFloat3 c;
	return ReactorNeighbors(spot, c)
			< int(ai.GetTunable("apex_reactor_batch", float(REACTOR_BATCH)));
}

// A spot inside a FULL batch is pushed out past the batch boundary to seed
// the next one; a veto alone would stall reactors, since the band placement
// re-proposes the same crowded spot forever.
// SHOULDER TO SHOULDER INSIDE THE BATCH. The batch rule bounds how far apart
// reactors may be (700) and how many share a blast, but nothing pulled them
// TOGETHER, so they landed wherever the band had room -- apexearth: "too often
// not completely next to each other. They should try to tighten up." Re-sites
// onto the nearest standing reactor and lets the engine find the closest legal
// cell to it; the batch cap still decides when to start a new group elsewhere.
bool TightenToBatch(CCircuitDef@ want, const AIFloat3& in cur, AIFloat3& out spot)
{
	spot = cur;
	CCircuitUnit@ near = null;
	float best = ai.GetTunable("apex_reactor_spacing", TUNE_REACTOR_SPACING);
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i] is null)
			continue;
		const float d = gFusions[i].GetPos(ai.frame).distance2D(cur);
		if (d < best) {
			best = d;
			@near = gFusions[i];
		}
	}
	if (near is null)
		return false;
	const AIFloat3 at = near.GetPos(ai.frame);
	const AIFloat3 site = ai.FindBuildSiteNear(want, at,
			ai.GetTunable("apex_reactor_tight", TUNE_REACTOR_TIGHT));
	if (!OnMap(site) || !ReactorBatchOK(site))
		return false;
	// Only accept it if it actually tightened things up.
	if (site.distance2D(at) >= best)
		return false;
	spot = site;
	return true;
}

bool SectionSafeSpot(CCircuitDef@ want, const AIFloat3& in cur, AIFloat3& out spot)
{
	spot = cur;
	if (ReactorBatchOK(cur)) {
		AIFloat3 tight;
		if (TightenToBatch(want, cur, tight))
			spot = tight;
		return true;
	}
	const float gap = ai.GetTunable("apex_reactor_spacing", TUNE_REACTOR_SPACING);
	AIFloat3 centroid;
	ReactorNeighbors(cur, centroid);
	AIFloat3 dir = cur - centroid;
	if (dir.SqLength2D() < 1.f) {
		dir = gHomePos - centroid;   // degenerate: shove toward home
		if (dir.SqLength2D() < 1.f)
			return false;
	}
	dir.SafeNormalize2D();
	// Past the far edge of the full batch: centroid + (its radius ~ gap) + gap.
	AIFloat3 cand = centroid + dir * (gap * 2.2f);
	if (!OnMap(cand))
		return false;
	const AIFloat3 site = ai.FindBuildSiteNear(want, cand, 400.f);
	if (!OnMap(site) || !ReactorBatchOK(site))
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
	// The BANK counts alongside income: a full storage is metal already wasted
	// (excess vanishes), so it pays for reactors NOW. apexearth, watching:
	// "we're full on metal here... there should be 0 delay" between reactors.
	// Income-only concurrency serialized them with construction-length gaps
	// whenever income alone covered just one.
	const float bank = aiEconomyMgr.metal.current;
	const int n = int((aiEconomyMgr.metal.income * AFFORD_SECONDS + bank) / cost);
	return (n < 1) ? 1 : n;
}

// apexearth's own build order, stated as the rule: "I might have ~6 advanced
// solars... giving me about 1k energy and then I start my fusion." Past that
// point a panel is the WRONG buy whether or not the fusion exists yet --
// measured live (8v8 Isthmus): one player stacked 57 advsols to 204 m/s
// steady with the bank drained to single digits, and the whole team's first
// fusions slipped to minute 19. The reclaim cliffs only condemn a panel once
// a reactor STANDS, which is exactly the chicken-and-egg this breaks.
bool AdvsolPastItsPoint()
{
	return (aiEconomyMgr.energy.income
			>= ai.GetTunable("apex_advsol_stop", TUNE_ADVSOL_STOP))
		&& Factory::gHaveT2;
}

// Null once a reactor stands: obsolete.as already names a reactor as this def's
// successor and reclaims it, so without this the same def was built and torn
// down at the same time.
CCircuitDef@ AdvSolDef()
{
	// The reclaim cliff, not HaveReactor(): one standing fusion used to end
	// all advsol building while the reclaim side needed income past its cliff
	// to start eating them -- the band between was where the base built and
	// ate the same def at once. Now both sides flip at the same line.
	CCircuitDef@ adv = SideDef3(armadvsol, coradvsol, legadvsol);
	if ((adv is null) || EnergyReclaimable(adv.GetName()) || AdvsolPastItsPoint())
		return null;
	if (aiEconomyMgr.energy.income
			< ai.GetTunable("apex_advsol_energy", TUNE_ADVSOL_ENERGY))
		return null;
	return adv.IsAvailable(ai.frame) ? adv : null;
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
	// Never BUILD what obsolete.as would reclaim -- building and tearing down
	// the same def at once is pure constructor-time loss, and it happened live
	// (commander building the def the con turrets were eating). ONE predicate,
	// shared with the reclaim list, decides both sides: EnergyReclaimable.
	const string n = d.GetName();
	if (EnergyReclaimable(n))
		return -1.f;
	if (((n == armadvsol) || (n == coradvsol) || (n == legadvsol))
		&& AdvsolPastItsPoint())
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

int MohoCount()
{
	CCircuitDef@ moho = SideDef3("armmoho", "cormoho", "legmoho");
	return (moho is null) ? 0 : int(moho.count);
}

// THE REACTOR PIPELINE: once the first reactor stands, one -- exactly one --
// fusion or AFUS is under construction at ALL times. apexearth: "we are
// always making a fusion or afus once we get to that stage... We should only
// build one at a time. No making a fusion AND afus at the same time."
// CCircuitDef::count includes nanoframes, so "underway" needs a completion
// ledger: main.as feeds finished/destroyed events here.
int gReactorsDone = 0;

bool IsReactorDef(const string& in n)
{
	return (n == armfus) || (n == corfus) || (n == legfus)
		|| (n == armafus) || (n == corafus) || (n == legafus)
		|| (n == armuwfus) || (n == coruwfus);
}

void NoteEcoFinished(const string& in n)
{
	if (IsReactorDef(n))
		++gReactorsDone;
	else if (IsBigConvDef(n))
		++gBigConvDone;
}

void NoteEcoGone(const string& in n, bool wasFinished)
{
	// The ask dies with the reactor, finished or nanoframe: gFusionsAsked
	// tracks history while ReactorCount tracks the living, so a death leaves
	// asked > count and ReactorPipelineOpen() reads CLOSED -- and the serial
	// gate in EcoFusion nulls before the resync there can heal it. Losing
	// every fusion wedged the pipeline shut exactly when a replacement was
	// most urgent (teal, 2026-08-16).
	if (IsReactorDef(n)) {
		if (gFusionsAsked > 0)
			--gFusionsAsked;
		if (wasFinished && (gReactorsDone > 0))
			--gReactorsDone;
		return;
	}
	if (!wasFinished)
		return;   // a dead nanoframe never counted as done
	if (IsBigConvDef(n) && (gBigConvDone > 0))
		--gBigConvDone;
}

int ReactorsUnderway()
{
	const int n = ReactorCount() - gReactorsDone;
	return (n < 0) ? 0 : n;
}

// Open = nothing building and nothing asked-but-unstarted. gFusionsAsked
// resyncs against ReactorCount inside EcoFusion, so drift self-heals there.
bool ReactorPipelineOpen()
{
	return (ReactorsUnderway() == 0) && (gFusionsAsked <= ReactorCount());
}

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
			+ " fusCount=" + FusionDef(unit).count
			+ " advCon=" + (gHaveAdvCon ? "1" : "0")
			+ " moho=" + MohoCount()
			+ " asked=" + gFusionsAsked
			+ " canBuild=" + (unit.circuitDef.CanBuild(FusionDef(unit)) ? "1" : "0"));
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
	// "Some advanced mexes" is proof the T2 economy is real, and the FIRST
	// fusion then jumps the income bar outright. apexearth: "after we have
	// some advanced mexes we really should be making that first fusion.
	// Fusions (economy) are super important in this game. And the efficiency
	// difference between a fusion and an advanced solar is huge."
	bool firstFusionDue = false;
	if (!HaveReactor()) {
		CCircuitDef@ moho = SideDef3("armmoho", "cormoho", "legmoho");
		firstFusionDue = (moho !is null) && (float(moho.count)
				>= ai.GetTunable("apex_first_fusion_mohos", TUNE_FIRST_FUSION_MOHOS));
	}
	// The income bar applies only BEFORE the first reactor: after it the
	// pipeline is continuous -- apexearth: "we are always making a fusion or
	// afus once we get to that stage."
	if (!HaveReactor() && !investedEnough && !firstFusionDue
		&& (Factory::SteadyIncome()
			< ai.GetTunable("apex_fusion_income", TUNE_FUSION_INCOME)))
	{
		return null;
	}
	// A T2 CONSTRUCTOR, not a T2 factory: the factory stood in for "someone
	// can build it", which gated the WANT on tech the team might hold in a
	// different form. apexearth: 'Change this to: "We must have a T2 con."'
	if (!gHaveAdvCon)
		return null;
	// The grid must afford BUILDING it -- see Policy::FusionMinEnergy. The
	// advsol ladder keeps running below the bar and is what raises it.
	if (!HaveReactor()
		&& (aiEconomyMgr.energy.income < Policy::FusionMinEnergy()))
	{
		return null;
	}
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
	// SERIAL: one reactor under construction at a time, fusion or AFUS, never
	// both. The gap-free half lives in the pipeline hook (maketask.as), which
	// re-asks the moment ReactorPipelineOpen() reads true again.
	if ((ai.GetTunable("apex_reactor_serial", TUNE_REACTOR_SERIAL) > 0.f) && !ReactorPipelineOpen())
		return null;
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

	// Only an asker that can actually BUILD the reactor may take the task --
	// measured (8v8 Glitters, 20260815-064126): 208 fusion tasks handed to
	// T1 constructors, every one a guaranteed capability-guard null. But
	// "leave the want standing for the next advanced constructor" assumed one
	// ever ARRIVES here: measured 2026-08-20 (46m 1v1, seed 27), the single
	// adv con lived on the moho pipeline and never idled through this rule --
	// asked=0, canBuild=0 on every diag, zero fusions at 103-169 m/s while
	// stock built three and rode them to gantry. So an incapable asker now
	// POSTS the task into the pool instead of dropping it; the elector hands
	// it to whoever can build it, same shape as the factory build-power ask.
	if ((want !is null) && !unit.circuitDef.CanBuild(want)) {
		if (!gHaveAdvCon)
			return null;
		AIFloat3 pooledAt(-1.f, 0.f, -1.f);   // invalid until a picker fills it
		// NANO GRAVITY (apexearth 2026-08-21: "Nano turrets should be like
		// gravity -- we want to build near them"): the pool-post is the
		// busiest fusion path (a T1 con or the commander proposes, an adv con
		// executes), and it was the one place the reactor site ignored the
		// assist field it would otherwise finish inside.
		AIFloat3 nn;
		if (NanoCluster(nn)) {
			const AIFloat3 s = ai.FindBuildSiteNear(want, nn, 450.f);
			if (OnMap(s))
				pooledAt = s;
		}
		if (!OnMap(pooledAt) && !BandSpot(unit, want, false, pooledAt))
			pooledAt = gHomePos;
		if (!OnMap(pooledAt))
			return null;
		IUnitTask@ posted = Requests::Create(want, Task::BuildType::ENERGY,
				Task::Priority::HIGH, pooledAt, SQUARE_SIZE * 32);
		if (posted !is null) {
			++gFusionsAsked;
			AiLog(Factory::T() + "apex: fusion posted to the pool -- asker "
				+ unit.circuitDef.GetName() + " cannot build it");
		}
		return null;
	}

	AIFloat3 spot;
	const bool okDef = (want !is null) && want.IsAvailable(ai.frame);
	// BandSpot's deep band is only the BACK of the base while the latched axis
	// points at the enemy, so it cannot be the only answer for a reactor.
	// ReactorSpot declining falls through to exactly the old placement.
	int rear = 0;
	// Near the nano cluster first: turrets assist the build, and a reactor
	// that dies gets replaced at nano speed instead of one lathe's
	// (apexearth: "prefer making our buildings near nano turrets if
	// possible"). SectionSafeSpot below still pushes it out of a full
	// chain-blast batch, so the batching rule keeps the final say.
	if (okDef) {
		AIFloat3 nn;
		if (NanoCluster(nn)) {
			const AIFloat3 s = ai.FindBuildSiteNear(want, nn, 400.f);
			if (OnMap(s)) {
				spot = s;
				rear = 3;
			}
		}
	}
	if (okDef && (rear == 0))
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
	// THE DEF MUST MATCH THE GROUND. A naval constructor reaching this rule
	// gets the underwater def from FusionDef, and the rear-band spot is LAND
	// -- watched live (8v8 mirror, t13: five dead coruwfus asks at a land
	// position, fusCount=0 at 146 m/s while its bank piled). An underwater
	// reactor on dry ground -- or a dry one on the seafloor -- is a permanent
	// silent no-op, so the mismatch refuses before the ask counter moves.
	if (okSpot && (want !is null)) {
		const string wn = want.GetName();
		const bool uw = (wn == armuwfus) || (wn == coruwfus);
		if (uw != (spot.y < 0.f))
			okSpot = false;
	}
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
	++gFusionsAsked;
	// at= is what separates this path from HomeEnergy's and from the C++
	// placement in a log: without a position all three look alike.
	string via = "band";
	if (rear == 1)
		via = "heavy";
	else if (rear == 2)
		via = "rear";
	else if (rear == 3)
		via = "nano";
	AiLog(Factory::T() + "apex: eco fusion " + want.GetName()
		+ " standing=" + want.count + " asked=" + gFusionsAsked
		+ " at=" + int(spot.x) + "," + int(spot.z)
		+ " via=" + via
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0));
	return post;
}

}  // namespace Builder
