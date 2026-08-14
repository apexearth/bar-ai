namespace Builder {

// True while we own a plain mex and can build the advanced one. The big
// optional investments below (gantry, nuke silo, Pulsar) test this before
// spending: a moho pays for them, they do not pay for it.
//
// CEconomyManager picks the upgrade spot through an ALLY-wide GetFriendlyUnit
// lookup, so an ally's extractor can be offered and the task fails to
// complete -- an aborted task costs one constructor trip, which is cheaper
// than a veto that misidentifies our own mexes and refuses our upgrades.
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


// Counts what the engine actually offers, by build type, so a low mex-upgrade
// rate can be attributed to supply (engine never offers one) vs demand
// (something downstream loses offers that were made).
int gOfferMexUp = 0;
int gOfferMex = 0;
int gOfferOther = 0;
int gOfferNull = 0;
int gNextOfferLog = 0;

// Split by builder tier: metalDefs.GetBuildDefs limits the search to defs the
// unit can build, and only an advanced constructor can build a moho, so
// pooling T1 and T2 offers together dilutes the rate that actually matters.
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
