namespace Market {
// The best extraction any AVAILABLE def in the game reaches -- the ceiling
// upgrade demand is measured against.
float gBestExtract = -1.f;
float BestExtract()
{
	if (gBestExtract >= 0.f)
		return gBestExtract;
	gBestExtract = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (Catalog::gAvailable[i] && (Catalog::gExtractsM[i] > gBestExtract))
			gBestExtract = Catalog::gExtractsM[i];
	}
	return gBestExtract;
}

// Metal/s still extractable from ground we already hold, if every standing
// mex were upgraded to the game's best extractor. The tech want's fuel.
float UpDemand()
{
	const float ceil = BestExtract();
	float d = 0.f;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLExtract[i] > 0.f)
			d += gLIncome[i] * (ceil - gLExtract[i]);
	}
	return (d > 0.f) ? d : 0.f;
}

// TWO HALF-BUILT FUSIONS ARE WORSE THAN ONE FINISHED: an expensive def
// already in progress takes the next asker as a JOINER -- doubling build
// speed on the standing frame -- instead of opening a parallel copy
// (apexearth: "not too many of the same building in parallel; assist
// should count the time saved").
IUnitTask@ JoinBig(CCircuitDef@ def)
{
	if ((def is null)
		|| (def.costM < ai.GetTunable("apex_join_min_m", TUNE_JOIN_MIN_M)))
		return null;
	return Requests::LiveTaskOf(def);
}

// THE WALK IS THE RISK, not just the destination (apexearth, after a fresh
// T2 con marched into the enemy army while 4 home mexes sat unupgraded):
// known enemy mass along the corridor above the walker's own metal cost is
// a death walk whatever the spot pays. The walker's value is the bar -- a
// 100m con risks more than a 500m one, no fixed threshold anywhere.
bool DeathWalk(CCircuitUnit@ unit, const AIFloat3& in dest)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float bar = Catalog::gCostM[int(unit.circuitDef.id)];
	for (int s = 1; s <= 2; ++s) {
		AIFloat3 p = here;
		const float f = float(s) / 2.f;
		p.x += (dest.x - here.x) * f;
		p.z += (dest.z - here.z) * f;
		if (!OnMap(p))
			continue;
		if (ai.GetEnemyCostAt(p, 900.f) > bar)
			return true;
	}
	return false;
}

Want@ ProposeMex(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 here = unit.GetPos(ai.frame);
	// Threat ceiling is generous on purpose: a contested spot is priced, not
	// hidden (the leaf era's FindOpenMexSpot went silent exactly under attack).
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, here, 99.f);
	gMexOpen = (spot >= 0);
	if (spot < 0)
		return w;
	// Already committed: someone decided this spot and its task is live (or
	// recently was) -- proposing it again is the churn, not a want.
	if (LedgerFind(spot) >= 0)
		return w;
	const AIFloat3 pos = aiEconomyMgr.GetMexSpotPos(spot);
	// SUPER RISKY GROUND IS NOT A BUILD OPTION (apexearth): a spot past the
	// front is a con's death walk whatever it pays -- and refusing it also
	// stops the market hiring more cons for ground nobody can hold.
	if (Front::FoeKnown() && Builder::PastFront(pos)) {
		gMexOpen = false;
		return w;
	}
	// Deadly for THIS walker; the spot itself stays open for a safer angle,
	// so gMexOpen is not cleared.
	if (DeathWalk(unit, pos))
		return w;
	// The quiet rear stays home: no claim meaningfully closer to the enemy
	// than its own base depth (the mirror reference works pre-contact too).
	if (EcoFar(pos)) {
		gMexOpen = false;
		return w;
	}
	if (EcoQuiet() && (gEcoRefX >= 0.f)) {
		const float sdx = pos.x - gEcoRefX;
		const float sdz = pos.z - gEcoRefZ;
		const float hdx = Builder::gHomePos.x - gEcoRefX;
		const float hdz = Builder::gHomePos.z - gEcoRefZ;
		const float f = ai.GetTunable("apex_eco_reach_frac", TUNE_ECO_REACH_FRAC);
		if (sdx * sdx + sdz * sdz < (hdx * hdx + hdz * hdz) * f * f) {
			gMexOpen = false;
			return w;
		}
	}
	const float spotIncome = aiEconomyMgr.GetMexSpotIncome(spot);
	const float speed = Catalog::gSpeed[uid];
	const float dist = here.distance2D(pos);
	gAvgWalkDist = 0.8f * gAvgWalkDist + 0.2f * dist;
	const float walkSec = (speed > 1.f) ? (dist / speed) : 60.f;
	// Every extractor this builder can place, priced; the VALUE picks the
	// def (a same-yield mex at 4.7x the cost lost the nomination it used to
	// win on raw extraction -- measured: armamex over armmex).
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= 0.f))
			continue;
		Want c;
		// RELATIVE growth: a spot worth 3.4 at 16 m/s income is a 21% raise
		// to everything downstream (apexearth's arithmetic); the same spot
		// at 200 m/s is noise. The multiplier decays with wealth, so
		// expansion prioritizes itself exactly while we are behind.
		float gain = spotIncome * Catalog::gExtractsM[d];
		{
			const float inc0 = aiEconomyMgr.metal.income;
			gain *= 1.f + ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH)
					* gain / ((inc0 > gain) ? inc0 : gain);
		}
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_MEX;
			@w.def = Catalog::Def(d);
			w.pos = pos;
			w.spotId = spot;
			gLastSpotM = gain;
		}
	}
	return w;
}


}  // namespace Market
