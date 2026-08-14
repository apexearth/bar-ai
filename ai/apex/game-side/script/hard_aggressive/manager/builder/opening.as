namespace Builder {

// THE OPENING SEQUENCE, IN THE ORDER apexearth ASKED FOR IT.
//
//   1. take the mexes already in reach (usually one to three, sometimes none)
//   2. get income up -- about 80 energy/s and 5+ metal/s
//   3. THEN the first T1 lab, and only that one
//   4. a sentry in the base
//   5. back out for more mexes and walk to the front line
//
// Step 1 is now Brain::MexWant, ranked on economic value against everything
// else Brain::Decide considers -- see rules_offer.as and brain.as, 2026-08-14
// -- rather than an early, unconditional take; step 5 is existing behaviour,
// AiMakeDefence's. Step 3's "only that one" is the T1-total gate in
// factory/choose.as; step 4 is HomeTower, which now waits for the lab. What
// lives here is step 2, which nothing in the script ever did.
//
// It used to be done in C++, invisibly. CEconomyManager::UpdateFactoryTasks
// compares income against the factory's own draw, and when it falls short it
// sets the sticky isEnergyRequired and calls UpdateEnergyTasks on the spot to
// buy the energy that clears it (EconomyManager.cpp:1816-1820; the latch is
// cleared only by CBEnergyTask::Finish/Cancel). With UpdateEnergyTasks
// disabled that call builds nothing, so the latch is set and the factory is
// blocked -- at EconomyManager.cpp:1752, before any other check -- until some
// unrelated energy task of ours happens to finish. That is why the first
// factory now lands at an erratic time, with several mexes ahead of it.
//
// Both numbers are apexearth's, from watching, and both are tunables so a
// measurement can move them rather than an argument.
//
// REVERTED to 80. apexearth: "a commander alone generates 30 e/s" -- the
// eInc=30 read at 0.4m in every opening test was the COMMANDER'S OWN passive
// output, not one generator finished, meaning almost nothing had actually been
// built yet at that point. The gate was never the problem; a commander with
// real buildpower taking 3-4 minutes to add 50 more e/s on top of that is the
// actual bug, and lowering the target would have hidden it rather than fixed
// it. Investigate why build POWER is not converting into finished generators
// -- commander idle time, task-switch thrash -- before touching this number
// again.
float OpeningEnergyGate() { return ai.GetTunable("apex_opening_energy_gate", 80.f); }
float OpeningMetalGate()  { return ai.GetTunable("apex_opening_metal_gate", 5.f); }

// "NEARBY", APEXEARTH'S OWN FIGURE: "within 5 seconds of walking... ~700 elmo
// range." Originally bounded step 1 itself (ExpansionAlwaysWins taking any mex
// the engine offered, unconditionally, ate the whole opening on a mex-rich
// map -- apexearth: "you're walking around full of metal making more metal
// extractors rather than starting your base"). Step 1 is a ranked want now
// (see the header note above) and no longer needs its own gate, but the same
// reach still bounds the post-3-minute factory-rebuild fallback in
// rules_commander.as ("a safe mex spot still exists nearby").
float OpeningMexReach() { return ai.GetTunable("apex_opening_mex_reach", 700.f); }

// NO CLOCK, ON PURPOSE. apexearth: code this open-ended -- a team wiped down
// to one constructor must re-derive the same opening from its CURRENT economy,
// not be told "you're 40 minutes in, skip the gates". A time-based escape
// valve is exactly the kind of thing that would relatch WRONG after a wipe:
// the surviving constructor's own opening would read as already past its
// deadline before it ever got to build the energy this gate exists to buy.
//
// OpeningEnergy below only ever proposes work through HomeEnergy, which is
// itself demand-bounded and returns null the moment there is no beneficial
// generator or converter left to place -- so a builder that hits that never
// gets stuck on step 2. But `AiGetFactoryToBuild` (factory/choose.as) cannot
// see that: it has no unit to ask HomeEnergy through, so it can only re-read
// this gate. Without a second signal it would hold the first factory FOREVER
// on a spot that can never reach the income gate at all -- a real deadlock,
// not a hypothetical one, for exactly the starved-economy case this was
// written to survive. The signal is `aiBuilderMgr.GetTaskCountOf(ENERGY)`:
// while it is nonzero, step 2 is actively buying the income this gate is
// waiting on and holding is correct; the moment it drops to zero with income
// still short, nothing is left in flight to close the gap, and the gate
// releases. Still no clock, no count, no invented number -- a real state
// read, of the same queue Requests::Register tracks.
int gOpenGateLog = 0;
int gOpenEnergyJobs = 0;
// Highest metal income this player has ever read. Never reset -- that is the
// point: it is what lets the gate tell "still climbing from zero, first time"
// apart from "was fine, just got raided down to zero" without a clock.
float gOpenPeakMetalIncome = 0.f;

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
	if (mInc > gOpenPeakMetalIncome)
		gOpenPeakMetalIncome = mInc;
	const bool short_ = (aiEconomyMgr.energy.income < OpeningEnergyGate())
		|| (mInc < OpeningMetalGate());
	if (!short_)
		return false;
	// MEASURED 2026-08-14, +70 handicap 8v8: four of eight teams held this gate
	// to the 25-minute cap and never released. Every one had e=133/80 (energy
	// fine) and m=0.0/5.0 -- not "still climbing", RAIDED. `GetTaskCountOf(ENERGY)`
	// stayed nonzero the whole time because dozens of energy tasks were queued
	// and simply could never finish without metal, so the queue-empty escape
	// below never saw an empty queue. Holding a factory back here helps no one:
	// nothing can be built at all, factory or otherwise, without metal income,
	// so refusing the factory only removes an option, it does not fix the
	// shortage. Once this player has ever cleared the metal gate and current
	// income has since collapsed near zero, that is a raid, not an opening --
	// release, and let expansion/defence do their own job at recovering income.
	if ((gOpenPeakMetalIncome >= OpeningMetalGate()) && (mInc < 1.f))
		return false;
	// Short of the gate AND nothing is currently being built to close the gap:
	// step 2 has run out of beneficial ground, not merely not-yet-caught-up.
	// Release rather than hold forever.
	if ((gOpenEnergyJobs > 0) && (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::ENERGY)) == 0))
		return false;
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
