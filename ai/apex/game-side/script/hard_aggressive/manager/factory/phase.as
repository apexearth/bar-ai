namespace Factory {

// BUILD_PHASE, per docs/12-build-phases.md (apexearth's design). Diagnostic
// only: computes and logs a phase number so a future session can check it
// against real telemetry before gating any existing rule behind it. Gating
// rules is the actual fix for the crowding-out pattern this session
// independently reconfirmed five times (see notes/open-issues.md, "SESSION
// SYNTHESIS") -- this is deliberately NOT that yet. Doing that blind, this
// late in an unsupervised session, risks becoming "one more && on rules that
// still all want to fire", which the design doc itself names as the way this
// fails to help.
//
// Driven from STATE per the doc's own first rule (never a clock), so it can
// fall back down on its own the moment a signal drops -- no ratchet, no
// separate distress flag needed, because nothing is being latched here.
// Thresholds are a first approximation from constants already used elsewhere
// in this file (RUSH_MIN_METAL-scale for pre-T2, FUSION_KEEP for pre-T3) --
// calibrate against composition.py's own per-phase breakdown once telemetry
// exists, per the doc's measurement plan.
int gLastPhase = -1;
int gNextPhaseLog = 0;

bool HaveGantry()
{
	CCircuitDef@ d = SideDef3(armshltx, corgant, leggant);
	return (d !is null) && (d.count > 0);
}

// Income that stands in for "four mexes" and "one mex" of economic power. A T1
// mex yields roughly 2-3 metal/s, so four is about 10.
const float PHASE_BUILDUP_INCOME = 10.f;
const float PHASE_EXPAND_INCOME  = 3.f;

int ComputePhase()
{
	const float mInc = aiEconomyMgr.metal.income;
	const uint mex = MexCount();
	const uint fusions = Builder::gFusions.length();
	const bool hasT3 = HaveGantry();

	if (hasT3 || (fusions >= 3))
		return (hasT3 && (fusions >= 3)) ? 7 : 6;          // T3 / late
	if (gHaveT2 && (fusions >= 1 || mInc >= 40.f))
		return 5;                                          // pre-T3
	if (gHaveT2)
		return 4;                                          // T2
	if (MayPursueT2() && RushReady())
		return 3;                                          // pre-T2
	// ECONOMIC POWER, not mex count. apexearth: "we should never gate purely on
	// mex count. you can gate by economic power."
	//
	// A count is the wrong measure twice over: it ignores where the metal is
	// actually coming from (reclaim, converters, a richer spot), and it traps a
	// player that cannot expand. Measured: t0 and t3 sat at 2 mexes and phase 1
	// for thirty minutes, and phase 1 is below every economic rule in the AI --
	// the whole cluster needs phase >= 4 -- so they could not build the economy
	// that would have got them out. Mex count is kept only as an alternative way
	// to reach the rung, never as the sole way.
	// NO mex-count clause, not even as an alternative route to the rung.
	// apexearth, twice: "we should never gate purely on mex count", then
	// "remember, NO gates based on mex count. DO NOT DO THAT."
	if (mInc >= PHASE_BUILDUP_INCOME)
		return 2;                                          // build up
	if (mInc >= PHASE_EXPAND_INCOME)
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
	ai.PublishTeamValue(TV_DIST, Builder::gHomeSet
			? Builder::gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()) : 0.f);
	ai.PublishTeamValue(TV_MEX, UpdateMexHold());
	ai.PublishTeamValue(TV_FILL, (aiEconomyMgr.metal.storage > 0.f)
			? aiEconomyMgr.metal.current / aiEconomyMgr.metal.storage : 0.f);
	if (ElectorTeamId() == ai.teamId)
		RunElection();
	UpdateEcoLead();
}

// Extractors we hold, counting one under construction as still held.
//
// An upgrade REPLACES the unit: the T1 extractor is destroyed and an advanced
// one is laid down in its place, so a plain unit count reads every upgrade as a
// lost mex for the whole build -- 14,100 build time for legmoho. The eco lead
// upgrades more mexes than anyone on its team, so the release condition fired
// hardest on the player doing the most of what the role exists to do.
//
// GetDefBuildProgress reports the best progress toward a def and -1 when none is
// being built, so a nanoframe of any advanced extractor credits one back. It
// cannot distinguish two simultaneous upgrades; the sustain window below covers
// what this does not.
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
