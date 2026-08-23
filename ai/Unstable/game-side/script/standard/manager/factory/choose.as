namespace Factory {

// KILL PHASE stubs (docs/20-brain-overhaul.md). These three signatures are
// looked up by the engine (FactoryScript.cpp); a MISSING AiGetFactoryToBuild
// falls back to the engine's native DefaultGetFactoryToBuild -- a leaf
// spender -- so the stub must exist and answer null. Plant choice returns as
// a Want in the rebuild.
CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	return null;
}

bool AiIsSwitchTime(int lastSwitchFrame)
{
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	return false;
}

}  // namespace Factory
