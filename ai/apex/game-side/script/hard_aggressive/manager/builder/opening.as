namespace Builder {

// THE OPENING SEQUENCE:
//   1. take the mexes already in reach (Brain::MexWant, ranked against
//      everything else Brain::Decide considers -- see rules_offer.as/brain.as)
//   2. get income up (this file)
//   3. THEN the first T1 lab, and only that one (T1-total gate, factory/choose.as)
//   4. a sentry in the base (HomeTower, waits for the lab)
//   5. back out for more mexes and to the front line (AiMakeDefence)
//
// Step 2 used to happen invisibly in C++: CEconomyManager::UpdateFactoryTasks
// blocks the factory behind a sticky isEnergyRequired latch
// (EconomyManager.cpp:1752/1816-1820) that only UpdateEnergyTasks clears. With
// that disabled the latch never clears on its own, so this gate replaces it
// explicitly.
float OpeningEnergyGate() { return ai.GetTunable("apex_opening_energy_gate", 80.f); }
float OpeningMetalGate()  { return ai.GetTunable("apex_opening_metal_gate", 5.f); }

// Bounds the post-opening factory-rebuild mex fallback in rules_commander.as
// (a mex must be genuinely close to be worth taking over rebuilding the lab).
float OpeningMexReach() { return ai.GetTunable("apex_opening_mex_reach", 700.f); }

// NO CLOCK, ON PURPOSE: a team wiped to one constructor must re-derive this
// gate from its CURRENT economy, not from elapsed game time.
//
// AiGetFactoryToBuild (factory/choose.as) has no unit to route through
// HomeEnergy, so it can only re-read this gate -- without a second signal it
// would hold the first factory forever on a spot that can never reach the
// income target. The escape is `aiBuilderMgr.GetTaskCountOf(ENERGY)`: while
// nonzero, step 2 is actively buying the shortfall and holding is correct;
// once it drops to zero with income still short, nothing is left in flight
// to close the gap and the gate releases. Still a real state read, not a
// clock or invented number.
int gOpenGateLog = 0;
int gOpenEnergyJobs = 0;
// Never reset: lets the gate tell "still climbing from zero" apart from
// "was fine, just raided down to zero" without a clock.
float gOpenPeakMetalIncome = 0.f;
// Same idea, energy side. A base wipe that takes the generators but leaves
// mexes standing collapses ENERGY income while metal income (and any banked
// metal) stays healthy -- without this the metal-only escape below never
// fires, `short_` stays true on the energy term alone, and the gate holds
// the factory rebuild back indefinitely waiting for energy income that has
// nothing left to produce it from.
float gOpenPeakEnergyIncome = 0.f;

// Is the opening gate holding the first factory back right now? Read entirely
// from CURRENT standing state -- factory count, active factory task, income,
// energy work in flight -- so it re-derives correctly the instant those
// readings change, including after a wipe that takes every factory and every
// mex with it.
bool OpeningNeedsEconomy()
{
	if (ai.GetTunable("apex_opening_gate", 1.f) <= 0.f)
		return false;
	if (Factory::HaveAnyFactory())
		return false;
	// An ACTIVE factory task is work in progress, not a proposal, and the gate
	// must release the moment one exists or the commander walks off the lab it
	// just started. The held, inactive task CEconomyManager keeps while it
	// waits for income is not in buildTasks (BuilderManager.cpp:734-740), so
	// this reads only the real one.
	if (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::FACTORY)) > 0)
		return false;
	const float mInc = aiEconomyMgr.metal.income;
	const float eInc = aiEconomyMgr.energy.income;
	if (mInc > gOpenPeakMetalIncome)
		gOpenPeakMetalIncome = mInc;
	if (eInc > gOpenPeakEnergyIncome)
		gOpenPeakEnergyIncome = eInc;
	const bool short_ = (eInc < OpeningEnergyGate())
		|| (mInc < OpeningMetalGate());
	if (!short_)
		return false;
	// A metal income that has cleared the gate before and has since collapsed
	// near zero is a raid, not a slow-starting opening -- queued energy tasks
	// can stall forever with no metal to finish them, so the queue-empty escape
	// below never fires on its own. Release and let expansion/defence recover
	// income instead of holding the factory back for no benefit.
	if ((gOpenPeakMetalIncome >= OpeningMetalGate()) && (mInc < 1.f))
		return false;
	// Same collapse, energy side: generators destroyed while mexes (and any
	// banked metal) survive. Without this the commander sits on a full metal
	// bank forever "buying energy" it has nothing left standing to build,
	// because `short_` above stays true on the energy term alone and the
	// metal escape does not apply when metal itself never collapsed.
	if ((gOpenPeakEnergyIncome >= OpeningEnergyGate()) && (eInc < 1.f))
		return false;
	// Short of the gate AND nothing is currently being built to close the gap:
	// step 2 has run out of beneficial ground, not merely not-yet-caught-up.
	// Release rather than hold forever.
	//
	// NOT gated on gOpenEnergyJobs > 0 any more: on Supreme Isthmus 8v8 a
	// player's HomeEnergy returned null from the FIRST call (zero energy
	// requests all game), jobs stayed 0, this escape was disarmed, and the
	// gate held the factory to 6.6 minutes while cons roamed claiming mexes
	// -- apexearth: "they just walked around making lots of mexes and not
	// starting a factory." The metal side standing satisfied is the state
	// read that separates "step 2 never got a chance" (opening seconds,
	// mInc still near zero) from "nothing is buying energy and nothing will".
	if ((gOpenEnergyJobs > 0 || (mInc >= OpeningMetalGate()))
		&& (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::ENERGY)) == 0))
		return false;
	// FAILSAFE, deliberately redundant with everything above: this gate holds
	// the single most important unlock in the game, and it has wedged once
	// already on a leg no one predicted (an escape disarmed by jobs==0). An
	// energy task stuck in flight forever would still hold it today. So: once
	// metal income stands at several times what the gate protects, the hold
	// is costing more than the lab it guards -- release, whatever the energy
	// ledger claims. State-derived, no clock.
	if (mInc >= OpeningMetalGate() * ai.GetTunable("apex_opening_failsafe", 3.f)) {
		AiLog(Factory::T() + "apex: OPENING FAILSAFE released the factory --"
			+ " e=" + formatFloat(eInc, "", 0, 0)
			+ " m=" + formatFloat(mInc, "", 0, 1)
			+ " energyTasks=" + aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::ENERGY)));
		return false;
	}
	return true;
}

// STEP 2. Sits below expansion, so a mex still outranks a solar and step 1 is
// unchanged, and above everything optional, so the opening is not spent on a
// turret or a converter instead.
IUnitTask@ OpeningEnergy(CCircuitUnit@ unit)
{
	if ((unit is null) || !OpeningNeedsEconomy())
		return null;
	// This rule enqueues and AiMakeTask is a re-election, so a builder already
	// standing on a site is left alone. `target` is the nanoframe, which is what
	// separates real work from a task not yet started.
	IUnitTask@ held = unit.task;
	if ((held !is null) && (SiteBuildName(held) != "") && (held.target !is null))
		return null;
	IUnitTask@ juice = HomeEnergy(unit);
	if (juice is null)
		return null;
	++gOpenEnergyJobs;
	if (ai.frame >= gOpenGateLog) {
		gOpenGateLog = ai.frame + 15 * SECOND;
		AiLog(Factory::T() + "apex: opening economy-first, no lab yet -- e="
			+ formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
			+ "/" + formatFloat(OpeningEnergyGate(), "", 0, 0)
			+ " m=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ "/" + formatFloat(OpeningMetalGate(), "", 0, 1)
			+ " jobs=" + gOpenEnergyJobs);
	}
	return juice;
}

}  // namespace Builder
