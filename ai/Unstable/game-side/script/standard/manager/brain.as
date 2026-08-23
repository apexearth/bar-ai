namespace Brain {

//------------------------------------------------------------------------------
// KILL PHASE (docs/20-brain-overhaul.md). The old rule-by-rule Want market is
// gone; Decide() is the ONLY function allowed to turn a constructor's time
// into a task, and its market is empty until the rebuild. The budget ledger
// (brain/budget.as) stays as a sense; the facqueue (brain/facqueue.as) is
// the production executor. The market (brain/market.as) prices the Wants.
//------------------------------------------------------------------------------

// The arbiter. The market prices the choices; this is the only spender.
IUnitTask@ Decide(CCircuitUnit@ unit)
{
	return Market::Decide(unit);
}

// The periodic macro pass. Nothing to rank yet.
void Think()
{
}

// The def's usable weapon reach, clamped -- GetMaxRange is the def's longest
// weapon whatever it is for (an anti-nuke interceptor reports 72,000 elmos),
// so consumers of a tower's range go through here. Kept as a sense: the
// military defence-line geometry reads it.
float LightTowerRange()
{
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	const float r = (light is null) ? 0.f : light.GetMaxRange();
	return (r > 1.f) ? r : 430.f;   // armllt/leglht 430, corllt 435
}

float TowerReach(const CCircuitDef@ tower)
{
	if (tower is null)
		return 0.f;
	const float r = tower.GetMaxRange();
	if (r <= 0.f)
		return 0.f;
	const float cap = LightTowerRange()
			* ai.GetTunable("apex_def_reach_cap", TUNE_DEF_REACH_CAP);
	return (r > cap) ? cap : r;
}

}  // namespace Brain
