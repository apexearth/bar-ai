namespace Factory {

// KILL PHASE (docs/20-brain-overhaul.md): every factory line is adopted by the
// facqueue and held silent on a Wait task. No recruiting rules, no
// DefaultMakeTask -- the engine must not produce units on its own. The
// facqueue's line mechanics (adoption, Wait-hold, recruit abort, sweep) are
// the production EXECUTOR the rebuilt arbiter will feed.
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	return Brain::FactoryQueueTask(unit);
}

}  // namespace Factory
