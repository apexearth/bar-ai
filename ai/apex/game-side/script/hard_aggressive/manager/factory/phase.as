namespace Factory {

// BUILD_PHASE, per docs/12-build-phases.md. Driven from state (income,
// gHaveT2, fusion count, gantry), never a frame, so it falls back down on its
// own the moment a signal drops -- nothing here is latched.
int gLastPhase = -1;
int gNextPhaseLog = 0;

bool HaveGantry()
{
	CCircuitDef@ d = SideDef3(armshltx, corgant, leggant);
	return (d !is null) && (d.count > 0);
}

// Income that stands in for "four mexes" and "one mex" of economic power. A T1
// mex yields roughly 2-3 metal/s, so four is about 10.
// The three income bars that move a phase live in tunables.as with every
// other default (TUNE_PHASE_*), so the whole progression is tunable from one
// file rather than from a constant buried here.

int ComputePhase()
{
	const float mInc = aiEconomyMgr.metal.income;
	const uint mex = MexCount();
	const uint fusions = Builder::gFusions.length();
	const bool hasT3 = HaveGantry();

	if (hasT3 || (fusions >= 3))
		return (hasT3 && (fusions >= 3)) ? 7 : 6;          // T3 / late
	if (gHaveT2 && (fusions >= 1
		|| mInc >= ai.GetTunable("apex_phase_pret3_income", TUNE_PHASE_PRET3_INCOME)))
		return 5;                                          // pre-T3
	if (gHaveT2)
		return 4;                                          // T2
	if (MayPursueT2() && RushReady())
		return 3;                                          // pre-T2
	// Gated on income, never mex count: a count ignores where metal actually
	// comes from and can trap a player that cannot expand -- a low mex count in
	// a strong economy must not cap the phase.
	if (mInc >= ai.GetTunable("apex_phase_buildup_income", TUNE_PHASE_BUILDUP_INCOME))
		return 2;                                          // build up
	if (mInc >= ai.GetTunable("apex_phase_expand_income", TUNE_PHASE_EXPAND_INCOME))
		return 1;                                          // expand
	return 0;                                              // opening
}

void UpdatePhase()
{
	const int phase = ComputePhase();
	if ((phase != gLastPhase) || (ai.frame >= gNextPhaseLog)) {
		gNextPhaseLog = ai.frame + 60 * SECOND;
		AiLog(T() + "apexphase: " + gLastPhase + " -> " + phase
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
			+ " mex=" + MexCount() + " haveT2=" + (gHaveT2 ? "1" : "0")
			+ " fusions=" + Builder::gFusions.length());
		gLastPhase = phase;
	}
}

// Driven from AiUpdate, so every instance publishes on a fixed cadence.
// Publishing as a side effect of RushLeadTeamId() instead would make a team's
// visibility depend on which code paths happened to ask for the lead that tick,
// and a team that went quiet would look like it had lost its plant.
void UpdateTeamCoord()
{
	UpdatePhase();
	// gHaveT2 latches on in AiUnitAdded and had no way back down, but the
	// branch that REBUILDS an advanced plant is gated on !gHaveT2 -- so a
	// player whose lab died still read "we have T2" and could never start
	// another. Recomputed here rather than in AiUnitRemoved because that hook
	// gives no guarantee the dying unit has left the def yet; on this cadence
	// it self-corrects either way.
	if (gHaveT2 && !AnyAdvPlant())
		gHaveT2 = false;
	ai.PublishTeamValue(TV_ADV, OwnAdvProgress());
	ai.PublishTeamValue(TV_READY, RushReady() ? aiEconomyMgr.metal.income : 0.f);
	// With zero known enemy groups CEnemyManager's group update publishes
	// ZeroVector -- the NW corner -- so pre-contact this measured distance
	// to a corner and the eco anchor picked accordingly. Until a real
	// contact exists, the map center (the same value enemyPos initializes
	// with) is the honest stand-in.
	AIFloat3 foeAt = aiEnemyMgr.GetEnemyPos();
	if ((foeAt.x <= 1.f) && (foeAt.z <= 1.f))
		foeAt = AIFloat3(AiTerrainWidth() * 0.5f, 0.f, AiTerrainHeight() * 0.5f);
	ai.PublishTeamValue(TV_DIST, Builder::gHomeSet
			? Builder::gHomePos.distance2D(foeAt) : 0.f);
	ai.PublishTeamValue(TV_MEX, UpdateMexHold());
	ai.PublishTeamValue(TV_FILL, (aiEconomyMgr.metal.storage > 0.f)
			? aiEconomyMgr.metal.current / aiEconomyMgr.metal.storage : 0.f);
	ai.PublishTeamValue(Builder::TV_TARG, float(Builder::OwnPinpoints()));
	if (ElectorTeamId() == ai.teamId)
		RunElection();
	// UpdateEcoLead moved to Role::Resolve() at the top of AiUpdate -- one
	// resolution per tick, ahead of every consumer.
}

// Extractors held, counting one under construction as still held: an upgrade
// destroys the T1 extractor and replaces it, so a plain unit count would read
// every upgrade as a lost mex for the whole build. GetDefBuildProgress credits
// one back per nanoframe but can't distinguish two simultaneous upgrades.
uint MexCount()
{
	uint n = 0;
	for (uint i = 0; i < MEX_DEFS.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(MEX_DEFS[i]);
		if (d is null)
			continue;
		n += uint(d.count);
		if (IsAdvancedMex(i) && (ai.GetDefBuildProgress(d) > 0.f))
			++n;
	}
	return n;
}

// MEX_DEFS holds the three T1 extractors first, then the three advanced ones.
// Only the advanced half is credited: a T1 mex under construction is expansion,
// not an upgrade, and counting it would inflate the peak we measure against.
bool IsAdvancedMex(uint i)
{
	return i >= 3;
}

}  // namespace Factory
