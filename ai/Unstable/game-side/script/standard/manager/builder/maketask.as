namespace Builder {

// KILL PHASE (docs/20-brain-overhaul.md): the ladder is holds -> Brain::Decide
// -> idle. Every leaf spending rule is gone, and there is deliberately NO
// fall-through to aiBuilderMgr.DefaultMakeTask -- the engine's native economy
// is leaf logic too. A constructor the Brain has no answer for idles visibly.
//
// Rez-bot unit thoughts (flee, medic, salvage, corpse reclaim) are kept per
// the overhaul's KEEP list; they act on units that exist, they build nothing.
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if (unit is null)
		return null;
	const double _mt = Perf::T0();
	IUnitTask@ _r = MakeTaskInner(unit);
	Perf::Add("hk.maketask.builder", _mt);
	return _r;
}

IUnitTask@ MakeTaskInner(CCircuitUnit@ unit)
{

	// Unit thoughts for rez bots: safety first, then opportunism.
	IUnitTask@ t = RezzerFlee(unit);
	if (t !is null)
		return t;
	if (IsRezzer(unit)) {
		@t = RezzerMedic(unit);
		if (t !is null)
			return t;
		@t = RezzerFrontSalvage(unit);
		if (t !is null)
			return t;
		@t = RezzerEatCorpse(unit);
		if (t !is null)
			return t;
		@t = RezzerRezOrEat(unit);
		if (t !is null)
			return t;
		@t = RezzerRepairNearby(unit);
		if (t !is null)
			return t;
		return RezzerIdle(unit);
	}

	// Hold work already in progress: a task the unit is on stays its task.
	// Safety, not spending -- nothing here creates work.
	IUnitTask@ held = unit.task;
	if ((held !is null) && (held.GetType() == Task::Type::BUILDER))
		return held;

	// The arbiter. Empty market during the kill phase: Decide returns null
	// and the constructor idles.
	return Brain::Decide(unit);
}

}  // namespace Builder
