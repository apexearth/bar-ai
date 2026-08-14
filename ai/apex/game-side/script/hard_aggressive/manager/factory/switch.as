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

	// MakeSwitchInterval() is AiRandom(550,900) seconds, so the AI only
	// *considers* a factory change every 9-15 minutes -- too rare for the rush
	// override to ever get asked. While the designated rusher still lacks T2,
	// let it reconsider every tick instead.
	// Returning true unconditionally is not safe here: in EconomyManager the
	// same flag disables the metal gate --
	//   if ((metalFactor < factoryPower) && !isSwitchTime && ...) return nullptr;
	// -- so a permanently-true isSwitchTime starts another factory whenever any
	// metal is held. Gated on MayPursueT2 rather than IsTechLead, since the
	// latter answers only for the primary lead and leaves every other slot on
	// the slow stock interval.
	if (MayPursueT2() && !gHaveT2) {
		if (ai.frame < gNextSwitchProbe)
			return false;
		gNextSwitchProbe = ai.frame + 10 * SECOND;
		return true;
	}
	// T3 probe removed: bounded probing reached T3 mechanically but cost more
	// metal than the game gives back at benchmark income levels, and the match
	// is decided long before the investment pays. T3 belongs behind an economy
	// that can carry it -- re-enable only once the eco half comes good first.
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
		// Not while the T2 transition is in flight. A player that has decided to
		// tech is paying for a plant, advanced constructors and the mexes to feed
		// them; an air plant on top of that buys a second unfinished thing
		// instead of finishing the first.
		//
		// State, not a threshold: once the advanced plant is up this stops
		// applying by itself, and a player not pursuing T2 at all is unaffected.
		if (!gHaveT2 && MayPursueT2())
			return false;
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// One guard for every non-lead route to an advanced plant. Has to be a
	// single early guard rather than a clause on the no-bank branch below,
	// because a non-lead has FOUR routes to T2 in this function -- the no-bank
	// branch, the turtle branch, and both halves of the stock fallback -- and
	// every one grants it on metal alone (or, in the turtle case, on banked
	// metal with no income test at all). Gating one leaves the others open.
	//
	// LeadIsDesignated() is load-bearing, not belt-and-braces: gating every
	// non-lead here without it would mean nobody can start a plant, so nobody
	// becomes lead, so nobody can start a plant. It cannot deadlock, because the
	// elector designates on TV_READY (published from RushReady, no plant
	// required) as well as on commitment, so slots fill without anyone having
	// to spend first.
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
	// without the stock army-value requirement -- it is not meant to be
	// contributing T1 army at all, so that requirement can never be met.
	// No bank requirement: in BAR you place the plant and pour income into the
	// nanoframe rather than saving the full cost first. Place it on zero metal
	// and let income, slinging allies and assisting builders finish it --
	// isAssistRequired is true for exactly that reason.
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
	// Same reasoning as the T2 plant: the stock gate wants armyCost > 1.2x cost x
	// facCount or the full cost banked, neither reachable for an eco variant
	// that deliberately holds a modest army and a gantry costing several
	// thousand metal. Require a real economy behind it instead, and turn assist
	// on so builders finish it without banking.
	if (WantMoreGantries() && ((userData[facDef.id].attr & Attr::T3) != 0)
		&& T3Worthwhile())
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// The lead escapes the guard above via the rush branch. Give followers the
	// same once the pooling window has closed: place the plant on income rather
	// than banking for it, with assist on so build power finishes it. Pooling
	// behind one player is only worth it if the others follow afterwards.
	// !gHaveT2 keeps this to ONE advanced plant per follower -- without it, a
	// follower that already owned one kept being granted a no-bank switch to
	// build another. Reaching here at all means the guard at the top of this
	// function passed, i.e. FollowerEconomyReady().
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
