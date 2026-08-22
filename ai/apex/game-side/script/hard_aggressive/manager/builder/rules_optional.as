namespace Builder {

// The optional cluster: everything a constructor may do INSTEAD of whatever
// DefaultMakeTask would offer it. Runs ahead of expansion, so every rule in
// here spends constructor time -- see CHANGES.md 2026-08-01.

// The mexup-outstanding gates yield at late-game income: the mexup pipeline
// GUARANTEES an upgrade is always in flight, so a plain
// !MexUpgradesOutstanding() became a permanent lock -- measured live, 500
// metal/second and 22k energy with NO gantry at 37 minutes while enemy T3
// walked in (apexearth: "why aren't we making 3 gantries and 100 nano
// turrets to support them?"). Same shape as apex_mexup_monopoly_income in
// Brain::Decide: below the bar upgrades outrank the big spends, above it
// the economy affords both.
// See the ChainNearbyMex call in OptionalWork. Same spot/threat primitives
// the mex crew uses; fires only for a builder far from home with a genuinely
// NEARBY open spot, so it cannot become a licence to wander.
IUnitTask@ ChainNearbyMex(CCircuitUnit@ unit)
{
	if (!gHomeSet)
		return null;
	const AIFloat3 at = unit.GetPos(ai.frame);
	if (!OnMap(at))
		return null;
	if (at.distance2D(gHomePos) < ai.GetTunable("apex_mex_chain_home", TUNE_MEX_CHAIN_HOME))
		return null;   // near home the normal ladder is fine
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, at);
	if (spot < 0)
		return null;
	const AIFloat3 where = aiEconomyMgr.GetMexSpotPos(spot);
	if (!OnMap(where)
		|| (where.distance2D(at) > ai.GetTunable("apex_mex_chain_r", TUNE_MEX_CHAIN_R)))
	{
		return null;   // "nearby" or nothing -- a far spot is a new decision
	}
	float heat = ThreatFor(unit, where);
	heat = MexHeat(where, heat);
	if (heat > CON_THREAT_VETO)
		return null;
	return aiEconomyMgr.EnqueueMexAt(unit, spot);
}

bool MexUpMonopoly()
{
	return MexUpgradesOutstanding()
		&& (aiEconomyMgr.metal.income
			< ai.GetTunable("apex_mexup_monopoly_income", TUNE_MEXUP_MONOPOLY_INCOME));
}

IUnitTask@ OptionalWork(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm) {
		// Sub-attribution: mt.optional spikes to 26ms single calls -- name the
		// rule. Same harness as the br.* timers.
		double opT = Perf::T0();
		// A damaged structure nearby (e.g. an HLT under fire) outranks the same
		// stand-down RepairNear does for a wounded ally -- see RepairStructureNearby's
		// own comment for why nothing else in the pipeline ever claims it.
		IUnitTask@ structRepair = RepairStructureNearby(unit);
		Perf::Add("op.structrep", opT);
		if (structRepair !is null)
			return structRepair;
		opT = Perf::T0();
		// con-heal (RepairNear) stays reflexive and ungated -- it answers
		// something happening now (a nearby wounded unit) rather than
		// claiming a slice of surplus, per docs/12-build-phases.md's own
		// split of phase-gated (investment) vs never-phase-gated (reflexive)
		// rules. RepairNear returns true when it has already handled (or is
		// standing down for) a nearby repair.
		const bool repaired = RepairNear(unit);
		Perf::Add("op.repairnear", opT);
		if (repaired) {
			++gRepairHeld;
			if (ai.frame >= gNextRepairLog) {
				gNextRepairLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: con-heal " + unit.circuitDef.GetName()
					+ " stands down, repairs=" + gArmyRepairs.length()
					+ " held=" + gRepairHeld);
			}
		}
		else {
			// CheapAA is carved out of the phase gate below: it is a tightly
			// self-gated reactive deterrent -- requires enemyAir >= 1 (an observed
			// threat, not a forecast), bounded by the side's basic cover plus
			// AA_VS_AIR of enemy air metal, throttled by AA_PERIOD -- unlike
			// HeavyAA/Pulsar/the eco cluster below, which are open-ended
			// investment and correctly wait for a teched economy.
			// The better (T2) turret sits beside it, also outside the gate, for
			// the same reason: it answers observed enemy air, is bounded the same
			// way, and cannot fire before the tech exists anyway.
			// THE FIRST FUSION OUTRANKS EVERYTHING OPTIONAL for an advanced
			// constructor. EcoFusion is otherwise LAST in the phase cluster,
			// and measured (Angel Crossing, 20260816-045743): every economic
			// gate green from 14.4 minutes, income to 138, bank to 10k, and
			// no fusion all game -- the builders that fell through to the rule
			// were T1 cons, refused by capability without a log, while the adv
			// cons were claimed higher up (stacking advanced solars among it).
			// EcoFusion's own gates (mohos standing, in-flight bound) still
			// decide WHETHER; this only decides how early an adv con asks.
			if (IsAdvConDef(unit) && !HaveReactor()) {
				IUnitTask@ firstFus = EcoFusion(unit);
				if (firstFus !is null)
					return firstFus;
			}
			// FINISH THE NEIGHBOURHOOD BEFORE WALKING HOME. apexearth
			// 2026-08-20, watching: "a con walk out to build a mex. There
			// will be 2 other mexes near the mex it just built. The con will
			// then walk home after making only 1 mex. It is very
			// inefficient." The mex crew already chains from its own
			// position; this is the same move for ANY builder already
			// deployed in the field -- the walk out is paid for, spend it.
			{
				IUnitTask@ chained = ChainNearbyMex(unit);
				if (chained !is null)
					return chained;
			}
			IUnitTask@ deter = HomeDeter(unit);
			if (deter !is null)
				return deter;
			// The deterrence-floor AA the block comment above always
			// described: self-gated (no-scout floor is AA_MIN/2, top-up only
			// from observed air), throttled by AA_PERIOD. It had silently
			// lost its call site -- see CheapAA's own comment.
			IUnitTask@ cheapAA = CheapAA(unit);
			if (cheapAA !is null)
				return cheapAA;
			// Beside HomeDeter, outside the phase gate, for the same reason:
			// heavy flak answers OBSERVED enemy air (HeavyAAWant is 0 with
			// none seen) and cannot fire early by construction.
			IUnitTask@ flakUp = HeavyFlak(unit);
			if (flakUp !is null)
				return flakUp;
			// Carved out of the phase gate for the same reason as CheapAA: a
			// 60-metal tower, one uncovered anchor at a time, and blindness is
			// what it answers -- the engine's own sensor pass never covers held
			// ground at all (see RadarNet's comment).
			opT = Perf::T0();
			IUnitTask@ eyes = RadarNet(unit);
			Perf::Add("op.radarnet", opT);
			if (eyes !is null)
				return eyes;
			// BUILD_PHASE gate on the remaining optional economy cluster: before an
			// advanced factory actually exists (gLastPhase>=4, i.e. gHaveT2), a
			// constructor's only job is expansion and reaching T2. HeavyAA, Pulsar,
			// EnergyConverter and the nano/fusion block below all wait for an
			// economy that has actually teched, not merely one that could afford
			// to -- see docs/12-build-phases.md.
			//
			// EnergyConverter stays behind this gate rather than self-gated like
			// CheapAA: it can claim a constructor's assignment before
			// DefaultMakeTask (where mex expansion is created, Priority::HIGH),
			// competing with mex for the same idle-constructor pool pre-T2.
			//
			// The crew SUPPRESSES the optional economy cluster for its members; it
			// does not replace their task selection -- dispatching the crew above
			// the whole pipeline instead would skip every threat veto, abandon and
			// repair rule an ordinary constructor gets. They fall through to
			// DefaultMakeTask, where mex work lives at Priority::HIGH, with every
			// safety rule above still applied.
			const int crewRole = Crew::RoleOf(unit);
			if (crewRole == Crew::MEX) {
				IUnitTask@ dig = Crew::MexWork(unit);
				if (dig !is null)
					return dig;
			} else if (crewRole == Crew::FRONT) {
				IUnitTask@ hold = Crew::FrontWork(unit);
				if (hold !is null)
					return hold;
			}
			// Guarding a mex is NOT in the phase-gated cluster below: it is cheap
			// early-game work, and the alternative is the army walking back to
			// chase a scout. The home crew is kept home by being offered ONLY the
			// economy cluster below and by being skipped for jobs that travel.
			//
			// EVERY role guards mexes, home crew included: MEX_GUARD_REACH is 1200
			// and HOME_RADIUS is 1600, so a nearby mex is base work by any
			// reading. It comes ahead of the home crew's own energy job below --
			// HomeEnergy always returns work, so ordering it first would starve
			// mex guarding out entirely.

			// The home crew's own job, NOT phase-gated: the pre-fusion energy curve
			// is exactly the stage this is for. The crew test lives HERE because
			// HomeEnergy no longer refuses a non-HOME builder (apex_energy_any),
			// and this is the terminal rule of OptionalWork -- offered to every
			// ECO constructor it would become the default job of the whole pool
			// and starve everything below it. Energy is still reachable for any
			// builder through Brain::Execute("energy"), ranked against the mex
			// upgrade instead of ahead of it.
			if (crewRole == Crew::HOME) {
				opT = Perf::T0();
			IUnitTask@ juice = HomeEnergy(unit);
			Perf::Add("op.energy", opT);
				if (juice !is null)
					return juice;
			}

			if ((Factory::gLastPhase >= 4)
				&& ((crewRole == Crew::ECO) || (crewRole == Crew::HOME))) {
				// Obsolete-building reclaims are enqueued centrally by
				// ObsoleteSweep and arrive via DefaultMakeTask.
				// A full bank outranks everything else here: the most expensive
				// thing we can start is the one that drains it fastest. Mex upgrades
				// still outrank a gantry, silo or Pulsar below (MexUpgradesOutstanding).
				if (!MexUpMonopoly()) {
					IUnitTask@ big = SurplusGantry(unit);
					if (big !is null)
						return big;
				}
				if (!MexUpMonopoly()) {
					IUnitTask@ nuke = NukeSilo(unit);
					if (nuke !is null)
						return nuke;
				}
				// The nano BEFORE the assist job: audited (instr-smoke 2026-08-16),
				// a factory sat 65 orders unstarted at 162 income while cons won
				// 648 assist elections against 26 nano requests -- renting a con
				// as build power forever instead of buying the 210-metal turret
				// that does it permanently. EcoNano self-gates (placement,
				// in-flight, pacing), so this claims a builder only when a nano
				// is actually due.
				// NOT while the base is contested: an assist finishes
				// something NOW; a new nano is spend on later. The build-power
				// review traced the batch-wide army-share drop to concurrent
				// construction crowding the metal pool -- under pressure,
				// finishing beats expanding build power.
				if (!BaseUnderAttack() && !Military::BaseContested()) {
					opT = Perf::T0();
			IUnitTask@ nanoFirst = EcoNano(unit);
			Perf::Add("op.econano", opT);
					if (nanoFirst !is null)
						return nanoFirst;
				}
				// Assist bots and front constructors get their standing job here,
				// where everything protective has already had its say.
				IUnitTask@ help = Assist::Work(unit);
				if (help !is null)
					return help;
				if (!Factory::EcoLeadActive()) {
					if (!MexUpMonopoly()) {
						opT = Perf::T0();
						IUnitTask@ gun = Pulsar(unit);
						Perf::Add("op.pulsar", opT);
						if (gun !is null)
							return gun;
					}
				}
				IUnitTask@ dome = Shield(unit);
				if (dome !is null)
					return dome;
				// Capped at three for the entire side, so the most this rule
				// can ever displace is ~2,400 metal of expansion across all of
				// us -- which is why it sits with the one-off structures rather
				// than behind the compounding economy block below.
				if (!MexUpMonopoly()) {
					IUnitTask@ targ = Pinpointer(unit);
					if (targ !is null)
						return targ;
				}
				// Bounded at three, ~500 metal for the whole game, and it sits
				// with the other one-off structures rather than earlier for the
				// reason this whole cluster is phase-gated: before an advanced
				// factory exists a constructor's only job is expansion.
				IUnitTask@ jam = BaseJammer(unit);
				if (jam !is null)
					return jam;
				IUnitTask@ block = EcoConverters(unit);
				if (block !is null)
					return block;
				IUnitTask@ conv = EnergyConverter(unit);
				if (conv !is null)
					return conv;
				IUnitTask@ nano = EcoNano(unit);
				if (nano !is null)
					return nano;
				IUnitTask@ fus = EcoFusion(unit);
				if (fus !is null)
					return fus;
			}
		}
	}
	return null;
}

// THE ADVANCED PLANT, EARLY, AND AT THE BACK OF THE BASE.
//
// CEconomyManager::UpdateFactoryTasks enqueues the plant as
// `TaskB::Factory(priority, facDef, -RgtVector, representer)` -- the position
// is -RgtVector, meaning "engine, you choose" -- and it only gets there after
// CheckAssistRequired and a chain of income tests, which is why the plant
// arrives late and wherever FindBuildSite happens to land it. Enqueueing it
// ourselves is the only lever on either timing or place.
//
// SteadyIncome, not metal.income: the trigger must not be tripped by a reclaim
// burst. See Factory::SteadyIncome.
//
// This is a REDIRECT of a build the engine would make anyway, not a new class of
// spend -- but it does make it EARLIER, so it is gated hard: one at a time, only
// while no factory task is on the books at all (CircuitAI's own
// UpdateFactoryTasks makes the same check before it will queue one), and only
// before we have T2.
const float T2_REAR_DIST = 600.f;
// How far from the rear point a site may be found when no nano covers the back.
// A base is thousands of elmos across; anchoring at RearOfBase and searching
// this far still lands behind it, while a radius near a turret's own weapon
// range would leave a crowded base with no site at all.
const float T2_REAR_SEARCH = 1600.f;
// Fraction of the nano's OWN build range -- a host modoption can change it, so a
// fixed elmo count would silently find no site.
const float T2_NANO_FRAC = 0.95f;

IUnitTask@ AdvancedPlantAtRear(CCircuitUnit@ unit)
{
	if (Factory::gHaveT2 || !gHomeSet)
		return null;
	if (ai.GetTunable("apex_t2_rear", TUNE_T2_REAR) <= 0.f)
		return null;
	// Policy::T2Metal, the SAME knob as the tech commit (RushReady): two
	// income gates on one decision drift apart the first time one is tuned.
	if (Factory::SteadyIncome() < Policy::T2Metal())
		return null;
	// NextT2Counterpart, not AdvCounterpart: the latter only ever answers for
	// the single remembered OPENING factory, which silently misses a T2 built
	// off a factory the team switched to afterward -- see its own comment
	// in factorydefs.as for the measured miss (armalab built, died, with
	// zero rear-placement coverage at all).
	CCircuitDef@ adv = Factory::NextT2Counterpart();
	if ((adv is null) || !adv.IsAvailable(ai.frame) || (adv.count > 0))
		return null;
	// THE ONE GATE, same as every other plant path. This rule enqueued the
	// advanced plant with its own thin checks and none of the tier discipline
	// -- the silent second entrance behind every "we're still making a second
	// T2 lab" report (fourth time, 8v8 Isthmus: T2 labs finishing with zero
	// approval lines in the log). PlantApproved also records the ledger entry
	// and prints the approval, so this path finally has attribution.
	if (!Factory::PlantApproved(adv))
		return null;
	// Someone is already walking to start THIS plant -- ours or the engine's,
	// either way not twice. GetTaskCountOf(FACTORY) used to gate this, but it
	// counts every factory task team-wide, so an ordinary second T1 lab being
	// built at the same time silently vetoed this whole rule and let
	// DefaultMakeTask place the advanced plant instead -- with no rear bias,
	// wherever FindBuildSite landed it (see the comment at the call site).
	// GetDefBuildProgress is per-def and turns >=0 as soon as a nanoframe
	// exists, closing the same race adv.count above closes, without firing on
	// an unrelated factory.
	if (ai.GetDefBuildProgress(adv) >= 0.f)
		return null;

	const AIFloat3 rear = RearOfBase(ai.GetTunable("apex_t2_rear_dist", TUNE_T2_REAR_DIST));
	if (!OnMap(rear))
		return null;

	// UNDER A NANO IF THERE IS ONE: a turret that already reaches the site
	// assists the plant up -- most of the point of building it early -- and
	// repairs it afterwards. The rearmost nano is tried first, and RearOfBase
	// is the fallback for a base that has none.
	AIFloat3 site;
	bool have = false;
	CCircuitDef@ nano = NanoDef();
	if (nano !is null) {
		array<CCircuitUnit@>@ ours = ai.GetOwnUnitsOfDef(nano, gHomePos, 0.f);
		if (ours !is null) {
			AIFloat3 bestNano;
			bool haveNano = false;
			float rearmost = 0.f;
			for (uint i = 0; i < ours.length(); ++i) {
				if (ours[i] is null)
					continue;
				const AIFloat3 at = ours[i].GetPos(ai.frame);
				if (!OnMap(at))
					continue;
				// Smaller forward fraction is further from the enemy.
				const float fwd = Military::ForwardFraction(at);
				if (!haveNano || (fwd < rearmost)) {
					rearmost = fwd;
					bestNano = at;
					haveNano = true;
				}
			}
			if (haveNano) {
				const float reach = nano.GetBuildDistance() * T2_NANO_FRAC;
				AIFloat3 near = ai.FindBuildSiteNear(adv, bestNano, reach);
				if (OnMap(near)) {
					site = near;
					have = true;
				}
			}
		}
	}
	if (!have) {
		AIFloat3 back = ai.FindBuildSiteNear(adv, rear, T2_REAR_SEARCH);
		if (!OnMap(back))
			return null;
		site = back;
	}
	// "Safe" is the point of putting it at the back, so refuse a site that is not.
	if (ThreatFor(unit, site) > CON_THREAT_VETO)
		return null;

	// Same as the gantry: a factory task carries a reprDef Requests cannot know,
	// so ask permission and enqueue our own shape.
	if (!Requests::Allowed(adv, Task::BuildType::FACTORY, site, 0.f))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH,
			adv, site, null, 0.f));
	if (post is null)
		return null;
	AiLog(Factory::T() + "apex: T2 plant " + adv.GetName() + " at the rear, "
		+ formatFloat(Factory::SteadyIncome(), "", 0, 0) + " m/s steady, fwd="
		+ formatFloat(Military::ForwardFraction(site), "", 0, 2));
	return post;
}

// ONE MEX UPGRADE ALWAYS RUNNING. Brain.as:1601 promised this lane and it
// never existed -- past apex_mexup_monopoly_income the mexup want competes
// on a score the eco normalisation crushes (measured 0.0007 against
// antinuke's 13 at 700 m/s, "brain orders mexup" ZERO all game), so a rich
// economy stopped upgrading extractors entirely. This keeps exactly one
// moho in flight whenever an advanced con is free and a target exists; the
// auction still decides everything past the first.
IUnitTask@ MexUpLane(CCircuitUnit@ unit)
{
	if (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::MEXUP)) > 0)
		return null;
	Want@ w = Brain::MexUpgradeWant(unit);
	if ((w is null) || (w.def is null))
		return null;
	if (!unit.circuitDef.CanBuild(w.def))
		return null;
	if (ThreatFor(unit, w.pos) > CON_THREAT_VETO)
		return null;
	IUnitTask@ t = aiBuilderMgr.EnqueueMexUp(w.pos, w.def);
	if (t !is null)
		AiLog(Factory::T() + "apex: mexup lane -- one upgrade back in flight at "
			+ formatFloat(Factory::SteadyIncome(), "", 0, 0) + " m/s");
	return t;
}

// THE GANTRY GETS SITED BY US, WIDENING OUTWARD. The T3 pick returns a def
// to the engine, and the engine's own siting fails silently on a footprint
// that big in a full base core -- an armshltx approved at 19.8m was still
// unplaced at 36m in a watched 400 m/s game. Same shape as
// AdvancedPlantAtRear above, with the search radius doubling until ground is
// found (apexearth: "maybe we need to be willing to make these further
// away") -- at gantry income the walk is cheaper than the wait.
IUnitTask@ GantryAtRear(CCircuitUnit@ unit)
{
	if (!gHomeSet || !Factory::gHaveT2)
		return null;
	if (!Factory::WantMoreGantries() || !Factory::T3Worthwhile())
		return null;
	CCircuitDef@ gant = Factory::T3Gantry();
	if ((gant is null) || !gant.IsAvailable(ai.frame))
		return null;
	if (!unit.circuitDef.CanBuild(gant))
		return null;
	if (ai.GetDefBuildProgress(gant) >= 0.f)
		return null;
	if (!Factory::PlantApproved(gant))
		return null;
	const AIFloat3 rear = RearOfBase(ai.GetTunable("apex_t2_rear_dist", TUNE_T2_REAR_DIST));
	if (!OnMap(rear))
		return null;
	AIFloat3 site;
	bool have = false;
	float search = T2_REAR_SEARCH;
	for (int tries = 0; tries < 4 && !have; ++tries) {
		AIFloat3 at = ai.FindBuildSiteNear(gant, rear, search);
		if (OnMap(at) && (ThreatFor(unit, at) <= CON_THREAT_VETO)) {
			site = at;
			have = true;
		}
		search *= 2.f;
	}
	if (!have)
		return null;
	if (!Requests::Allowed(gant, Task::BuildType::FACTORY, site, 0.f))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH,
			gant, site, null, 0.f));
	if (post is null)
		return null;
	AiLog(Factory::T() + "apex: T3 gantry " + gant.GetName() + " sited at r="
		+ int(search * 0.5f) + " fwd="
		+ formatFloat(Military::ForwardFraction(site), "", 0, 2));
	return post;
}

// THE AIR PLANT THE INTEL CURVE WANTS, WITHOUT WAITING FOR THE SWITCH CLOCK.
//
// Air::IntelPlantToBuild is otherwise consulted only inside ChooseFactory,
// which the engine calls on its own factory-switch cadence (AiRandom(550,900)
// seconds) and only when it proposes a plant of its own -- so the mandatory
// air lab and the advanced air plant arrived late or never. Same shape as
// AdvancedPlantAtRear above: a redirect of a build the curve already wants,
// through PlantApproved (the one gate) and Requests::Allowed, placed at home.
// The CanBuild test is the whole asker filter -- only an air constructor can
// place the advanced plant, any ground con the basic one.
IUnitTask@ WantedAirPlant(CCircuitUnit@ unit)
{
	if (!gHomeSet)
		return null;
	CCircuitDef@ plant = Air::IntelPlantToBuild();
	if ((plant is null) || !unit.circuitDef.CanBuild(plant))
		return null;
	// Only the cases the switch-clock path actually failed: the mandatory lab
	// on a rich economy, the advanced plant, the enemy-afloat reaction. The air
	// lead's early intel lab at 25 m/s keeps its old cadence -- placing THAT
	// above mex expansion would be a new early spend, not a fix.
	if (((Factory::userData[plant.id].attr & Factory::Attr::T2) == 0)
		&& !Military::EnemyAfloat()
		&& (aiEconomyMgr.metal.income
			< ai.GetTunable("apex_air_mandatory_income", TUNE_AIR_MANDATORY_INCOME)))
	{
		return null;
	}
	if (ai.GetDefBuildProgress(plant) >= 0.f)
		return null;   // one already going up somewhere
	if (!Factory::PlantApproved(plant))
		return null;
	AIFloat3 site = ai.FindBuildSiteNear(plant, gHomePos, T2_REAR_SEARCH);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;
	if (!Requests::Allowed(plant, Task::BuildType::FACTORY, site, 0.f))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH,
			plant, site, null, 0.f));
	if (post is null)
		return null;
	AiLog(Factory::T() + "apex: wanted air plant " + plant.GetName()
		+ " by " + unit.circuitDef.GetName() + " at "
		+ formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
	return post;
}

// WHERE A REACTOR GOES.
//
// 0 leaves the placement to the ordinary eco layout, 1 is the grid's heavy band,
// 2 anchors on the rear point instead -- the heavy band is only the back of the
// base while the latched axis is rearward.
int ReactorSpot(CCircuitUnit@ unit, CCircuitDef@ gen, AIFloat3& out spot)
{
	if (!gHomeSet || (gen is null))
		return 0;
	if (ai.GetTunable("apex_reactor_rear", TUNE_REACTOR_REAR) <= 0.f)
		return 0;
	AIFloat3 site;
	if (Base::AxisIsRearward() && Base::Spot(unit, gen, Base::HEAVY, site)
			&& (FrontT(site) <= 0.f)) {
		spot = site;
		return 1;
	}
	const AIFloat3 rear = RearOfBase(ai.GetTunable("apex_reactor_rear_dist", TUNE_REACTOR_REAR_DIST));
	if (!OnMap(rear))
		return 0;
	site = ai.FindBuildSiteNear(gen, rear, T2_REAR_SEARCH);
	if (!OnMap(site) || (FrontT(site) > 0.f))
		return 0;
	if (ThreatFor(unit, site) > CON_THREAT_VETO)
		return 0;
	spot = site;
	return 2;
}

}  // namespace Builder
