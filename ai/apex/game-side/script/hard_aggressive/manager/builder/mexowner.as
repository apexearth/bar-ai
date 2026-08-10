namespace Builder {

// What the AI knows about which extractors are ours.
//
// The ally-mexup VETO that used to live here is gone. apexearth: "that whole bit
// of code where we refuse to build mex upgrades for allies is a terrible idea."
// It was written for a real failure -- CEconomyManager picks the upgrade spot
// through the ALLY-wide GetFriendlyUnit lookup, so an ally's extractor can be
// offered and the task cannot complete -- but the cure was worse: it needed to
// know which mexes were ours, got that wrong (ourMexes=4 on a side holding 150+),
// and silently refused OUR OWN upgrades. An aborted task costs one constructor
// trip; refusing upgrades costs the whole metal economy.
//
// UPGRADES FIRST. apexearth, repeatedly: "we make pinpoints or nuke launchers
// before upgrading any mex... you still aren't doing tier 2 mex building first."
//
// True while we own a plain mex and can build the advanced one. The big optional
// investments below (gantry, nuke silo, Pulsar) test this before spending: a
// moho pays for them, they do not pay for it.
bool MexUpgradesOutstanding()
{
	// Literals, not the armmoho/cormoho/legmoho globals: those are declared in
	// factory/techlead.as, which the shim includes AFTER builder/*, and a global
	// read before its declaration is "No matching symbol" -- which disables the
	// whole variant and still reports a normal match.
	CCircuitDef@ moho = SideDef3("armmoho", "cormoho", "legmoho");
	if ((moho is null) || !moho.IsAvailable(ai.frame))
		return false;   // cannot upgrade yet; nothing to defer for
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	return (mex !is null) && (mex.count > 0);
}


// WHAT THE ENGINE ACTUALLY OFFERS.
//
// Three sessions have now argued about why mex upgrades are rare without ever
// measuring whether the engine OFFERS one. Everything downstream -- the guard
// that used to be here, the ladder order, the optional rules -- can only lose
// offers that were made. One line a minute, counting offers by build type, so
// "we never upgrade" can be attributed to supply or to demand rather than
// guessed at.
int gOfferMexUp = 0;
int gOfferMex = 0;
int gOfferOther = 0;
int gOfferNull = 0;
int gNextOfferLog = 0;

// SPLIT BY BUILDER TIER, or the number means nothing.
//
// metalDefs.GetBuildDefs(unit->GetCircuitDef()) limits the upgrade search to
// defs THIS unit can build, and only an advanced constructor can build a moho.
// So every T1 constructor's call is structurally incapable of being offered a
// MEXUP, and counting them together buried the real rate: 0.4% across all
// builders says nothing about whether the advanced ones are being offered work.
int gAdvOfferMexUp = 0;
int gAdvOfferOther = 0;
int gAdvOfferNull = 0;

void NoteOffer(CCircuitUnit@ unit, IUnitTask@ task, bool isAdvCon)
{
	if (isAdvCon) {
		if (task is null)
			++gAdvOfferNull;
		else if ((task.GetType() == Task::Type::BUILDER)
				&& (task.GetBuildType() == Task::BuildType::MEXUP))
			++gAdvOfferMexUp;
		else
			++gAdvOfferOther;
	}
	if (task is null)
		++gOfferNull;
	else if (task.GetType() != Task::Type::BUILDER)
		++gOfferOther;
	else if (task.GetBuildType() == Task::BuildType::MEXUP)
		++gOfferMexUp;
	else if (task.GetBuildType() == Task::BuildType::MEX)
		++gOfferMex;
	else
		++gOfferOther;

	if (ai.frame < gNextOfferLog)
		return;
	gNextOfferLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: offers mexup=" + gOfferMexUp
		+ " mex=" + gOfferMex
		+ " other=" + gOfferOther
		+ " none=" + gOfferNull
		+ " | adv mexup=" + gAdvOfferMexUp
		+ " other=" + gAdvOfferOther
		+ " none=" + gAdvOfferNull);
}

}  // namespace Builder
