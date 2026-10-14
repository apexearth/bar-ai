namespace Factory {

// KILL PHASE (docs/20-brain-overhaul.md): every factory line is adopted by the
// facqueue and held silent on a Wait task. No recruiting rules, no
// DefaultMakeTask -- the engine must not produce units on its own. The
// facqueue's line mechanics (adoption, Wait-hold, recruit abort, sweep) are
// the production EXECUTOR the rebuilt arbiter will feed.
//
// ASSIST TURRETS ARE NOT LINES. CFactoryManager hands us its nano turrets
// through the same hook, and a turret has no build options -- held on the
// facqueue's Wait it puts its build power on nothing at all. Its assist task
// is the DLL's own (CreateAssistTask, reached only through DefaultMakeTask).
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null))
		return null;
	if (Catalog::BuildsOf(int(unit.circuitDef.id)).length() == 0)
		return aiFactoryMgr.DefaultMakeTask(unit);
	const double _mt = Perf::T0();
	IUnitTask@ _r = Brain::FactoryQueueTask(unit);
	Perf::Add("hk.maketask.factory", _mt);
	return _r;
}

}  // namespace Factory
