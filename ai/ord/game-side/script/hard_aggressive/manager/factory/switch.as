namespace Factory {

bool AiIsSwitchTime(int lastSwitchFrame)
{
	if (!ApexActive()) {
		const float value = pow((ai.frame - lastSwitchFrame), 0.9)
				* aiEconomyMgr.metal.income + (aiEconomyMgr.metal.current * 7);
		if (value > switchLimit) {
			switchLimit = MakeSwitchLimit();
			return true;
		}
		return false;
	}

	// THE bug behind late teching: MakeSwitchInterval() is AiRandom(550,900)
	// seconds, so the AI only *considers* a factory change every 9-15 minutes.
	// The rush override was correct but never got asked -- hence T2 at 22.9m
	// instead of before 10. While the designated rusher still lacks T2, let it
	// reconsider every tick.
	// Returning true on EVERY call was a real bug, not just noise. In
	// EconomyManager the same flag disables the metal gate:
	//   if ((metalFactor < factoryPower) && !isSwitchTime && ...) return nullptr;
	// so a permanently-true isSwitchTime means the AI starts another factory
	// whenever it holds any metal at all. Observed live: one AI with THREE T1
	// bot labs. The intent was only to stop the stock 9-15 minute reconsider
	// interval from making the rush unreachable, which a short probe interval
	// achieves without leaving the gate open.
	// MayPursueT2, not IsTechLead. This probe is what makes teching reachable at
	// all -- the stock interval is AiRandom(550,900) seconds -- and gating it on
	// IsTechLead handed team 0 a probe every 10s while everyone else waited 9-15
	// minutes. Blue therefore built the first advanced plant in every game
	// regardless of income, because nobody else was ever asked. RushReady still
	// demands >= 14 metal/s before anything is actually placed.
	if (MayPursueT2() && !gHaveT2) {
		if (ai.frame < gNextSwitchProbe)
			return false;
		gNextSwitchProbe = ai.frame + 10 * SECOND;
		return true;
	}
	// T3 probe REMOVED after measurement, not after theorising. Bounded probing
	// worked mechanically -- 3645 metal of T3 fielded, the first time this AI has
	// ever reached T3, against stock's 0 -- and lost 4-12 with the CI excluding
	// 50%. Metal fell 136k -> 88k and army 25k -> 13k: a gantry plus its units
	// costs more than the game gives back at these income levels, and the match
	// is decided long before the investment pays.
	//
	// The doctrine is not wrong; the economy is not yet big enough to afford its
	// win condition. T3 belongs behind an economy that can carry it, which means
	// the eco half has to come good FIRST. Re-enable this only alongside a
	// measured economy that outpaces stock's ~136k.
	// Everyone should at least be trying for T2 by ~20 minutes.
	if (!gHaveT2 && (ai.frame > 20 * MINUTE))
		return true;
	if (Air::WantsSwitchProbe())
		return true;
	if (lastSwitchFrame + switchInterval <= ai.frame) {
		switchInterval = MakeSwitchInterval();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	if (!ApexActive())
		return true;   // the `hard` profile allows every switch

	// First, ahead of the non-lead guard below. The advanced air plant carries the
	// T2 attribute, so FollowerEconomyReady would refuse it on any grid under
	// FOLLOWER_TECH_ENERGY -- and the air assassin is by construction not a
	// designated tech lead, so that guard applies to it. Place it and pour income
	// in, same as the rush plant.
	if (Air::WantsFactory(facDef)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// One guard for every non-lead route to an advanced plant.
	//
	// It has to be a single early guard rather than a clause on the no-bank
	// branch below, because a non-lead has FOUR routes to T2 in this function --
	// the no-bank branch, the turtle branch, and both halves of the stock
	// fallback -- and every one of them grants it on metal alone, or in the
	// turtle case on banked metal with no income test whatsoever. Gating one
	// leaves the others open.
	//
	// This used to be two guards, both bounded by ai.frame < FOLLOWER_TECH_FRAME,
	// which is what produced the stampede: at ten minutes both expired for
	// everyone simultaneously and the whole team teched on RUSH_MIN_METAL. The
	// bound is now the economy, so a player is held until it can actually carry
	// a second tech base and released the moment it can.
	//
	// LeadIsDesignated() is load-bearing, not belt-and-braces. Gate every
	// non-lead and nobody can start a plant, so nobody becomes lead, so nobody
	// can start a plant. That deadlock was measured: the first election landed at
	// 10.5 min in two runs -- the frame the old gate opened -- against a 5.7 min
	// baseline. It cannot recur here, because the elector designates on TV_READY
	// (published from RushReady, no plant required) as well as on commitment, so
	// slots fill without anyone having to spend first.
	if (LeadIsDesignated() && !IsDesignatedLead()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& !FollowerEconomyReady())
	{
		// The "T2GATE reached" log below only fires on the PASSING path, so a
		// player permanently short of the bar left no record of how short.
		if (ai.frame >= gNextT2GateBlockLog) {
			gNextT2GateBlockLog = ai.frame + 60 * SECOND;
			AiLog(T() + "T2GATE blocked FollowerEconomyReady"
				+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
				+ "/" + formatFloat(FOLLOWER_TECH_ENERGY, "", 0, 0)
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ "/" + formatFloat(FOLLOWER_TECH_INCOME, "", 0, 1));
		}
		return false;
	}
	// The designated player is rushing: buy T2 as soon as the metal is on hand,
	// without the stock army-value requirement. It is not meant to be
	// contributing T1 army at all, so that requirement can never be met.
	// Was 0.5 * factory cost banked (~1450 metal). The rusher never holds that
	// much because it spends as the slings arrive, so the plant did not start
	// until 12 min. It does not need the whole cost up front -- construction
	// draws from income, and seven feeders keep paying into it.
	// Measured, 8v8 Glitters: energy cleared the rush bar at 5.0 min and stayed
	// clear, but the bank sat at 1-120 metal for the entire game against a
	// required 1400 (0.5 * plant cost), so this branch never once fired. The
	// requirement was never reachable -- metal income is ~13/s and every point of
	// it is spent as it arrives. Banking is the wrong model anyway: in BAR you
	// place the plant and pour income into the nanoframe. So place it on zero
	// metal and let income, seven slinging allies and assisting builders finish
	// it. isAssistRequired is now true for exactly that reason -- with no bank,
	// build power is the only thing that closes the gap.
	if (MayPursueT2() && !gHaveT2 && RushReady()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0))
	{
		// EconomyManager returns before this on (engyFactor < energyPower) and on
		// the sticky isEnergyRequired, neither of which isSwitchTime bypasses.
		// This line marks the frame we were actually reached on.
		AiLog(T() + "T2GATE reached IsSwitchAllowed"
			+ " lead=" + (IsDesignatedLead() ? "1" : "0")
			+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1));
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	if (Military::gTurtle && (aiEconomyMgr.metal.current > facDef.costM * 0.6f)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = false;
		return true;
	}
	// T3 is this variant's declared win condition and it has NEVER been fielded:
	// zero across every measured game, while stock manages 670 with no T3 logic
	// at all. AiGetFactoryToBuild already asks for the gantry -- the request dies
	// here. The stock gate wants either armyCost > 1.2x cost x facCount or the
	// full cost banked, and a gantry runs several thousand metal, so neither is
	// reachable for an eco variant that deliberately holds a modest army.
	//
	// Same reasoning as the T2 plant: you do not bank for a factory in BAR, you
	// place it and pour income into it. Require a real economy behind it rather
	// than a pile of metal, and turn assist ON so builders actually finish it --
	// with no bank, build power is the only thing that closes the gap.
	if (WantMoreGantries() && ((userData[facDef.id].attr & Attr::T3) != 0)
		&& T3Worthwhile())
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// Followers could never tech. Measured: 4.6k of T2 unit spend against stock's
	// 11-14k, 1.4 mex upgrades against 2.5-2.9, and three of four followers still
	// reading haveT2=0 at eighteen minutes while earning 30-73 metal/s. Releasing
	// the clock changed nothing, which proved the clock was never the blocker --
	// this gate is. It wants armyCost > 1.2x cost x facCount or the full plant
	// cost banked, and a follower holds neither.
	//
	// The lead escapes this via the rush branch above. Give followers the same
	// once the pooling window has closed: place the plant on income rather than
	// banking for it, with assist on so build power finishes it. Pooling behind
	// one player is only worth it if the others follow afterwards.
	// Staggering by team id was tried and LOST 2-14 (CI 71-100%). It did flatten
	// the army curve slightly -- 10.9k vs 17.8k at fourteen minutes, up from 8.9k
	// vs 25.1k -- but pushing the last follower to minute 16 costs more T2
	// economy than the smoother curve is worth. The synchronised transition is a
	// real cost; delaying teching is not the way to pay it.
	// !gHaveT2 was missing here, so a follower that ALREADY owned an advanced
	// plant kept being granted a no-bank switch to build ANOTHER one. Observed
	// live: a player with a T2 vehicle plant went and built a T2 bot lab as well,
	// and all four teched simultaneously late in the game. One advanced plant per
	// follower is the whole point -- the second is metal that should have been
	// army or mex upgrades, spent at the worst possible moment.
	// The clock and the metal-18 bar are both gone: reaching here at all now means
	// the guard at the top of this function passed, i.e. FollowerEconomyReady().
	if (!IsDesignatedLead() && !gHaveT2
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& FollowerEconomyReady())
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	const bool isOK = (aiMilitaryMgr.armyCost > 1.2f * facDef.costM * aiFactoryMgr.GetFactoryCount())
		|| (aiEconomyMgr.metal.current > facDef.costM);
	aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = !isOK;
	return isOK;
}

}  // namespace Factory
