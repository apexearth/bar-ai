namespace Builder {

// The optional cluster: everything a constructor may do INSTEAD of whatever
// DefaultMakeTask would offer it. Runs ahead of expansion, so every rule in
// here spends constructor time -- see CHANGES.md 2026-08-01.

IUnitTask@ OptionalWork(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm) {
		// A damaged structure nearby (e.g. an HLT under fire) outranks the same
		// stand-down RepairNear does for a wounded ally -- see RepairStructureNearby's
		// own comment for why nothing else in the pipeline ever claims it.
		IUnitTask@ structRepair = RepairStructureNearby(unit);
		if (structRepair !is null)
			return structRepair;
		// con-heal (RepairNear) stays reflexive and ungated -- it answers
		// something happening now (a nearby wounded unit) rather than
		// claiming a slice of surplus, per docs/12-build-phases.md's own
		// split of phase-gated (investment) vs never-phase-gated (reflexive)
		// rules. RepairNear returns true when it has already handled (or is
		// standing down for) a nearby repair.
		if (RepairNear(unit)) {
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
			IUnitTask@ deter = HomeDeter(unit);
			if (deter !is null)
				return deter;
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
				IUnitTask@ juice = HomeEnergy(unit);
				if (juice !is null)
					return juice;
			}

			if ((Factory::gLastPhase >= 4)
				&& ((crewRole == Crew::ECO) || (crewRole == Crew::HOME))) {
				// Clearing an obsolete base outranks ADDING to it. ObsoleteReclaim
				// also sits at the end of the pipeline, which is why it fired
				// twice in thirty minutes: a constructor was always offered
				// something else first. Promoted only above the ECO offers -- the
				// cheapest constructor time here -- and only once the junk is
				// thick enough to be the thing in the way.
				IUnitTask@ clear = ObsoleteUrgent(unit);
				if (clear !is null)
					return clear;
				// A full bank outranks everything else here: the most expensive
				// thing we can start is the one that drains it fastest. Mex upgrades
				// still outrank a gantry, silo or Pulsar below (MexUpgradesOutstanding).
				if (!MexUpgradesOutstanding()) {
					IUnitTask@ big = SurplusGantry(unit);
					if (big !is null)
						return big;
				}
				if (!MexUpgradesOutstanding()) {
					IUnitTask@ nuke = NukeSilo(unit);
					if (nuke !is null)
						return nuke;
				}
				// Assist bots and front constructors get their standing job here,
				// where everything protective has already had its say.
				IUnitTask@ help = Assist::Work(unit);
				if (help !is null)
					return help;
				if (!Factory::EcoLeadActive()) {
					if (!MexUpgradesOutstanding()) {
						IUnitTask@ gun = Pulsar(unit);
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
				if (!MexUpgradesOutstanding()) {
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
	if (ai.GetTunable("apex_t2_rear", 1.f) <= 0.f)
		return null;
	if (Factory::SteadyIncome() < ai.GetTunable("apex_t2_income", 30.f))
		return null;
	CCircuitDef@ adv = Factory::AdvCounterpart();
	if ((adv is null) || !adv.IsAvailable(ai.frame) || (adv.count > 0))
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

	const AIFloat3 rear = RearOfBase(ai.GetTunable("apex_t2_rear_dist", T2_REAR_DIST));
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

// WHERE A REACTOR GOES.
//
// 0 leaves the placement to the ordinary eco layout, 1 is the grid's heavy band,
// 2 anchors on the rear point instead -- the heavy band is only the back of the
// base while the latched axis is rearward.
int ReactorSpot(CCircuitUnit@ unit, CCircuitDef@ gen, AIFloat3& out spot)
{
	if (!gHomeSet || (gen is null))
		return 0;
	if (ai.GetTunable("apex_reactor_rear", 1.f) <= 0.f)
		return 0;
	AIFloat3 site;
	if (Base::AxisIsRearward() && Base::Spot(unit, gen, Base::HEAVY, site)
			&& (FrontT(site) <= 0.f)) {
		spot = site;
		return 1;
	}
	const AIFloat3 rear = RearOfBase(ai.GetTunable("apex_reactor_rear_dist", T2_REAR_DIST));
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
