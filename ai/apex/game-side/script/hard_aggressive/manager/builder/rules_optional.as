namespace Builder {

// The optional cluster: everything a constructor may do INSTEAD of whatever
// DefaultMakeTask would offer it. Runs ahead of expansion, so every rule in
// here spends constructor time -- see CHANGES.md 2026-08-01.

IUnitTask@ OptionalWork(CCircuitUnit@ unit, bool isComm)
{
	if (!isComm) {
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
			// CheapAA carved out of the phase gate below, 2026-08-05: apexearth
			// live-watched a Legion game with aaT1=0 at 7+ minutes against active
			// mosquito-gunship pressure, and the phase telemetry confirms why --
			// gHaveT2 (and so gLastPhase>=4) stayed at 0 for the entire pre-T2
			// window every game, so CheapAA was structurally unreachable exactly
			// when hit-and-run air is cheapest to punish. Unlike HeavyAA/Pulsar/
			// the eco cluster below (open-ended investment, correctly deferred
			// until the economy has actually teched), CheapAA is already a
			// tightly self-gated reactive deterrent: it requires enemyAir >= 1
			// (a real observed threat, not a forecast), is bounded by the side's
			// basic cover plus AA_VS_AIR of their air metal, and is throttled by
			// AA_PERIOD -- it cannot crowd out expansion the way the rest of this
			// cluster measurably did.
			// The better turret sits beside the cheap one, outside the phase
			// gate, for the same reason CheapAA was carved out of it: it answers
			// OBSERVED enemy air rather than forecasting, it is bounded by the
			// same ratio, and the def is T2 so it cannot fire before the tech
			// exists anyway.
			// Inside the gate it needed gHaveT2 AND an ECO/HOME crew role, which
			// is why the good AA never appeared in time.
			IUnitTask@ deter = HomeDeter(unit);
			if (deter !is null)
				return deter;
			// BUILD_PHASE gate on the remaining optional economy cluster.
			// Progression, 2026-08-04: phase >= 2 (mex >= 4) reverted, 0 wins in
			// 13 decided. phase >= 3 (RushReady) confirmed a real improvement, 5
			// wins in 22 decided (22.7%) across 4 batches. phase >= 4 (gHaveT2 --
			// an advanced factory actually finished, not just afforded) measured
			// BEST: 6 wins in 10 decided (60.0%, 95% CI 31.3%-83.2%) across 2
			// batches, P(>=6 wins in 10 | baseline true rate 7.9%) = 0.00004, and
			// most games (14/16 in the larger batch) ran the full time limit
			// competitively rather than being decided either way. See
			// notes/open-issues.md issue 15 for the full data and CHANGES.md for
			// the summary. Before an advanced factory exists, a constructor's
			// only job is expansion and reaching T2; HeavyAA, Pulsar, EnergyConverter
			// and the nano/fusion block below can all wait for an economy that has
			// actually teched, not merely one that could afford to.
			//
			// EnergyConverter was carved out of this gate earlier tonight (same
			// evidence shape as CheapAA -- self-gated on real spare energy, not a
			// forecast) after apexearth asked "why no energy converters?" at 9
			// minutes. REVERTED, same session, same night: apexearth immediately
			// afterward, watching mex expansion specifically: "I'd say we do build
			// too many cons... but huge issue is they just aren't placing enough
			// priority on building mexes." EnergyConverter was checked and could
			// claim a constructor's assignment BEFORE DefaultMakeTask (which is
			// what actually creates new mex-expansion tasks, Priority::HIGH in
			// EconomyManager.cpp) ever ran -- so unblocking it pre-T2 meant it
			// could now win the same idle-constructor pool mex expansion needs,
			// in exactly the 0-9 minute window this complaint is about. Mex
			// expansion matters more than energy conversion; reverted to
			// gLastPhase>=4 until a fix that does not compete with mex for
			// constructor time exists.
			// The crew SUPPRESSES the optional economy cluster for its members;
			// it does not replace their task selection.
			//
			// First attempt dispatched the crew above the whole pipeline, which
			// skipped every threat veto, abandon and repair rule an ordinary
			// constructor gets -- apexearth: "cons seem really dumb, dark green
			// just walking its cons off to die", and the economy was worse. The
			// intent was only ever to stop converters/nanos/fusions outbidding
			// mex expansion for these units, and that is all this does now:
			// they fall through to DefaultMakeTask, where mex work lives at
			// Priority::HIGH, with every safety rule above still applied.
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
			// Guarding a mex is NOT in the phase-gated cluster below: it is an
			// early-game job, it is the cheapest thing on this list, and the
			// alternative is the army walking back to chase a scout.
			// The home crew never leaves. apexearth: "some should ALWAYS be
			// doing economy at home." They are kept home by being offered ONLY
			// the economy cluster below, which is all base work by construction,
			// and by being skipped for the jobs that travel.
			// EVERY role guards mexes, home crew included: MEX_GUARD_REACH is
			// 1200 and HOME_RADIUS is 1600, so a nearby mex is base work by any
			// reading. Excluding them dropped guards from 32 to 9 in a game --
			// with 2 home and 3 mex out of about 5 constructors there was nobody
			// left to place one. apexearth: "we NEED to have at least one llt
			// early game within range of our mexes... it'll make them last so
			// much longer."
			// Guarding a mex comes FIRST -- ahead of the home crew's energy job.
			// HomeEnergy always returns work now, so putting it first meant the
			// home crew never reached this and guards fell 18 -> 6 in a game.
			// A 130-metal turret that saves a 620-metal mex outranks a solar.

			// The home crew's own job, NOT phase-gated: the pre-fusion energy
			// curve is exactly the stage this is for. The crew test lives HERE
			// because HomeEnergy itself no longer refuses a non-HOME builder --
			// apex_energy_any defaults on -- and this is the terminal rule of
			// OptionalWork, the one that always finds work. Offered to every ECO
			// constructor it became the default job of the whole pool and starved
			// everything below it. Energy is still reachable for any builder
			// through Brain::Execute("energy"), ranked against the mex upgrade
			// instead of ahead of it.
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
				// A full bank outranks everything else here. The most expensive
				// thing we can start is the one that drains it fastest.
				// A MOHO BEFORE A GANTRY, A SILO OR A PULSAR. apexearth: "we make
				// pinpoints or nuke launchers before upgrading any mex."
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
// apexearth: "we didn't prioritize making a T2 lab early enough. Once we make
// ~30+ metal per second we definitely should be making a T2 lab with high
// priority in a SAFE location behind our base."
//
// Both halves needed a rule. CEconomyManager::UpdateFactoryTasks enqueues the
// plant as `TaskB::Factory(priority, facDef, -RgtVector, representer)` -- the
// position is -RgtVector, meaning "engine, you choose" -- and it only gets there
// after CheckAssistRequired and a chain of income tests, which is why the plant
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
// apexearth: "T2_REAR_SEARCH = 700, is this the same # as a unit's attack range?
// If so then that search radius is too small." It was: corllt's weapon range is
// 435 and cornanotc's builddistance is 400, so 700 was barely more than one
// turret's reach and a crowded base would yield no site at all. A base is
// thousands of elmos across; anchoring at RearOfBase and searching this far
// still lands behind it.
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
	// Someone is already on it -- ours or the engine's. Either way, not twice.
	if (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::FACTORY)) > 0)
		return null;
	CCircuitDef@ adv = Factory::AdvCounterpart();
	if ((adv is null) || !adv.IsAvailable(ai.frame) || (adv.count > 0))
		return null;

	const AIFloat3 rear = RearOfBase(ai.GetTunable("apex_t2_rear_dist", T2_REAR_DIST));
	if (!OnMap(rear))
		return null;

	// UNDER A NANO IF THERE IS ONE. apexearth: "You want to have it towards the
	// back and preferrably within range of existing nano turrets." A turret that
	// already reaches the site assists the plant up -- which is most of the point
	// of building it early -- and repairs it afterwards. So the rearmost nano is
	// tried first, and RearOfBase is the fallback for a base that has none.
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

	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH,
			adv, site, null, 0.f));
	if (post is null)
		return null;
	AiLog(Factory::T() + "apex: T2 plant " + adv.GetName() + " at the rear, "
		+ formatFloat(Factory::SteadyIncome(), "", 0, 0) + " m/s steady, fwd="
		+ formatFloat(Military::ForwardFraction(site), "", 0, 2));
	return post;
}

// WHERE A REACTOR GOES. apexearth: "We make AFUS in unsafe places. They should
// be made far in the back-line."
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
