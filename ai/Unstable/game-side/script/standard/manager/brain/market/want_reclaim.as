namespace Market {

// How far from a blocked lattice slot one of our own structures counts as the
// thing standing in it. A footprint's reach, not a search radius: further away
// and it is not what refused the slot.
const float BLOCKER_REACH = 160.f;

// Obsolete generators price their own metal back into the market: when the
// E economy is structurally in surplus (removing the candidate keeps it so)
// and the bank has room for the burst, a weak generator's banked metal
// beats its trickle. Weakest first (lowest makeE per metal).
// WHAT RETIRING ONE OF OUR OWN STRUCTURES IS WORTH -- one price, so a solar,
// a dominated turret and a superseded lab compare on the same scale. The metal
// back plus the defended ground it stops renting, minus the output it still
// makes. Ground is SpaceRentM, the same rent every eco placement already pays,
// so a building inside our own cover has to earn its cells.
float RetireGain(CCircuitUnit@ tgt, int d, float ePM, float hz)
{
	const int cells = (Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1;
	return (Catalog::gCostM[d] + SpaceRentM(tgt.GetPos(ai.frame), cells)) / hz
			- Catalog::gMakeE[d] * ePM;
}

float RetireValue(CCircuitUnit@ unit, CCircuitUnit@ tgt, int d, float ePM,
		float wage, float hz)
{
	const float gain = RetireGain(tgt, d, ePM, hz);
	if (gain <= 0.f)
		return 0.f;
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(tgt.GetPos(ai.frame)) / speed) : 60.f;
	return gain / (1.f + (walkSec + Catalog::gCostM[d] / 90.f) * wage);
}

Want@ ProposeReclaimObsolete(CCircuitUnit@ unit)
{
	Want w;
	// SURPLUS CONS (apexearth: "made too many t1 cons... we should reclaim
	// them"): the quiet rear with no claimable safe ground and no BP
	// deficit turns constructor metal back into ladder money. Only a con a
	// standing factory could re-make (never the commander), cheapest
	// first; BPGap turning positive stops the next one -- self-balancing.
	// ...and only once the SUCCESSOR fleet exists: reclaiming the claim
	// fleet before any ceiling con stands starved the ladder that was
	// supposed to replace it (seed 23: cons cut to the floor by 10m, T2
	// lab at 12.3m). Same law as generator reclaim -- obsolescence is
	// RELATIVE efficiency, and nothing is obsolete before its better.
	if (EcoQuiet() && !gMexOpen && (BPGap() <= 0.f) && (ServingCons() > 0)) {
		// Only a LESSER con spends its time on this: a ceiling con
		// reclaiming T1s traded scaling time for tidying (watched --
		// "T2 cons immediately try reclaiming T1 cons").
		bool lesser = true;
		{
			const array<int>@ mine0 = Catalog::BuildsOf(int(unit.circuitDef.id));
			for (uint mi = 0; mi < mine0.length(); ++mi) {
				if (Catalog::gExtractsM[mine0[mi]] >= BestExtract()) {
					lesser = false;
					break;
				}
			}
		}
		CCircuitUnit@ rc = null;
		int rcDef = -1;
		int landCons = 0;
		for (uint wi = 0; lesser && (wi < gWorkers.length()); ++wi) {
			CCircuitUnit@ wu = gWorkers[wi];
			if ((wu is null) || (wu is unit))
				continue;
			const int wd = int(wu.circuitDef.id);
			// Air cons are exempt: no pathing cost, no placement blocking
			// (apexearth) -- and land cons below the keep-floor stay for
			// nano work. A JUST-BUILT con is never eaten: reclaiming what
			// we paid buildtime for minutes ago is churn, not tidying.
			if (Catalog::gFlyer[wd])
				continue;
			if ((wi < gWorkerBorn.length()) && (ai.frame - gWorkerBorn[wi]
					< int(ai.GetTunable("apex_reclaim_age_s", TUNE_RECLAIM_AGE_S)) * SECOND))
				continue;
			bool remake = false;
			for (uint fi = 0; fi < Factory::gFacUnits.length() && !remake; ++fi) {
				if (Factory::gFacUnits[fi] is null)
					continue;
				const array<int>@ fb = Catalog::BuildsOf(
						int(Factory::gFacUnits[fi].circuitDef.id));
				for (uint q = 0; q < fb.length(); ++q) {
					if (fb[q] == wd) {
						remake = true;
						break;
					}
				}
			}
			if (!remake)
				continue;
			++landCons;
			if ((rcDef < 0) || (Catalog::gCostM[wd] < Catalog::gCostM[rcDef])) {
				@rc = wu;
				rcDef = wd;
			}
		}
		if ((rc !is null)
			&& (float(landCons) > ai.GetTunable("apex_eco_con_keep", TUNE_ECO_CON_KEEP))) {
			const float hz0 = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
			w.kind = WK_RECLAIM;
			@w.def = Catalog::Def(rcDef);
			w.pos = rc.GetPos(ai.frame);
			w.spotId = int(rc.id);
			w.gain = Catalog::gCostM[rcDef] / ((hz0 > 1.f) ? hz0 : 300.f);
			w.mCost = 1.f;
			w.tCost = (Catalog::gCostM[rcDef] / 90.f) * Wage();
			w.value = w.gain / (w.mCost + w.tCost);
			@w.target = rc;
			@gReclaimTarget = rc;
			return w;
		}
	}
	// Obsolescence is RELATIVE efficiency: for generators the metric is E per
	// CELL of ground (measured from the defs -- solar 0.80, advsol 4.69,
	// fusion 33.3, AFUS 83.3, so the rungs are 5.9x, 7.1x and 2.5x;
	// apexearth: "eventually we need physical space"). For defences it is the
	// def's power under a far stronger neighbor's umbrella.
	//
	// The bank band that used to stand here (0.3-0.85 of storage, for "room
	// for the refund burst") gated on a FRACTION, and storage differs per
	// player -- measured 1300 against 4425 between two teams of one game, so
	// the same absolute headroom read "full" for one and "broke" for the
	// other. Both sat outside the band permanently, at 0.15 and 0.98, so this
	// want never evaluated once and mReclaim was 0. The refund's own worth is
	// already priced below (gain minus the generation given up), and the
	// energy-surplus test guards the stall the floor was reaching for.
	const float ratio = ai.GetTunable("apex_obsolete_ratio", TUNE_OBSOLETE_RATIO);
	const float hzR = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float hz = (hzR > 1.f) ? hzR : 300.f;
	const float ePM = EPriceFloor();
	const float wageR = Wage();
	// Converters are an elastic sink, not demand -- they are sized against
	// income by construction, so counting their chew as pull made a structural
	// surplus read as fully spent: measured over a 43-minute game, eFree sat at
	// -435, +3 and -1463 E/s while energy EXCESS reached 1,084,434.
	const float eFree = aiEconomyMgr.energy.income
			- (aiEconomyMgr.energy.pull - ConvUseE());
	CCircuitUnit@ best = null;
	int bestDef = -1;
	float bestValue = 0.f;
	// Generators, best-priced retirement first, only when dwarfed by the best.
	float ownBestEcell = 0.f;
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null)
			continue;
		const int d = int(gOwnGen[i].circuitDef.id);
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ec > ownBestEcell)
			ownBestEcell = ec;
	}
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		CCircuitUnit@ g = gOwnGen[i];
		if (g is null)
			continue;
		const int d = int(g.circuitDef.id);
		// Removing it must LEAVE a surplus -- reclaim never causes a stall.
		// The margin is a share of the CANDIDATE'S own output, not of income:
		// scaled to income it grew with the economy, so the bigger we got the
		// less we could retire.
		if (eFree - Catalog::gMakeE[d] <= 0.1f * Catalog::gMakeE[d])
			continue;
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ownBestEcell < ratio * ec)
			continue;   // not dwarfed: still pulling its weight per cell
		// PRICED, not ranked by E-per-cell. An argmin on that metric put the
		// worst generator we own permanently in front: a solar reads 0.80 and
		// an advanced solar 4.69, so while one T1 panel stood the advanced
		// solar could never even be the candidate. Measured over a 43-minute
		// game: 24 reclaim decisions, every one armsolar, zero armadvsol.
		const float v = RetireValue(unit, g, d, ePM, wageR, hz);
		if (v > bestValue) {
			bestValue = v;
			@best = g;
			bestDef = d;
		}
	}
	// Defences: dominated by a much stronger one covering the same ground.
	for (uint i = 0; i < gProtUnit[PROT_DEF].length(); ++i) {
		CCircuitUnit@ g = gProtUnit[PROT_DEF][i];
		if (g is null)
			continue;
		const int d = gProtDefId[PROT_DEF][i];
		bool dominated = false;
		for (uint j = 0; j < gProtUnit[PROT_DEF].length(); ++j) {
			if (i == j)
				continue;
			const int d2 = gProtDefId[PROT_DEF][j];
			if ((Catalog::Def(d2) !is null)
				&& (Catalog::Def(d2).power >= ratio * Catalog::Def(d).power)
				&& (gProtPos[PROT_DEF][i].distance2D(gProtPos[PROT_DEF][j]) < 400.f))
			{
				dominated = true;
				break;
			}
		}
		// ...or the PERIMETER HAS GROWN PAST IT. apexearth: "as our base grows,
		// reclaim old defenses as needed and extend defense outwards." The
		// defence sites are already chosen on the rim of what we own -- the
		// measured problem is that the base then grows around them, so a tower
		// sited on the edge ends up 150-300 elmos inside it and is guarding
		// ground that is now interior. Retiring it is what funds the post at
		// the new edge; the auction picks that site on its own.
		//
		// "Whenever the rim has moved past it" is his ruling (2026-08-27), so
		// there is no still-covers-something clause. Depth is measured in the
		// tower's OWN reach, so a long gun has to be far deeper in than a
		// light one before it counts as stranded, and it is a share of the
		// rim as well so it means the same thing on a small base and a large.
		bool stranded = false;
		if (!dominated && gPfRimOk) {
			const AIFloat3 tp = gProtPos[PROT_DEF][i];
			const float rimHere = PfRimAt(tp);
			const float deep = -PfRimDist(tp);
			const float rr = (Catalog::gMaxRange[d] > 1.f)
					? Catalog::gMaxRange[d] : 500.f;
			// ...AND IT MUST BE GUARDING NOTHING. A heavy gun is the most
			// attractive candidate here by construction -- the refund rises
			// with cost -- so an interior test on its own retires the base's
			// main weapon and the auction re-sites it wherever it next scores,
			// which can be deeper in than it started (apexearth: "just saw us
			// reclaim a doomsday gun and then make one further behind in our
			// base"). Measured over two 60-minute games: 1,694 and 1,645
			// decisions to reclaim a cordoom.
			//
			// A cover-versus-threat test does NOT catch this: threat in a quiet
			// interior reads ~0, so removing the gun trivially "leaves the
			// ground covered". The honest question is whether the turret is
			// doing work, and the measure of that is the metal standing inside
			// its reach. Compared against its own price, so nothing is chosen:
			// a turret guarding less than it is worth is not paying for
			// itself; one standing over the base is, wherever the rim has got
			// to.
			stranded = (rimHere > rr) && (deep > rr)
					&& (PfStakeAt(tp, rr) <= Catalog::gCostM[d]);
		}
		if (!dominated && !stranded)
			continue;
		const float v = RetireValue(unit, g, d, ePM, wageR, hz);
		if (v > bestValue) {
			bestValue = v;
			@best = g;
			bestDef = d;
		}
	}
	// GROUND LABS RETIRE FOR THE QUIET REAR once an owned AIR lab fields
	// flying cons of equal reach (apexearth: "reclaim the T1 and T2 labs,
	// go for T1 and T2 air labs... then make the huge T3"). Successor-first,
	// same law as everything else here: nothing is obsolete before its
	// better is standing.
	if (EcoQuiet()) {
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if (f is null)
				continue;
			const int fd = int(f.circuitDef.id);
			float fReach = 0.f;
			bool fFlies = false;
			const array<int>@ fp = Catalog::gBuildsList[fd];
			for (uint q = 0; q < fp.length(); ++q) {
				if (!Catalog::gMobile[fp[q]] || !Catalog::gBuilder[fp[q]])
					continue;
				if (Catalog::gFlyer[fp[q]])
					fFlies = true;
				const array<int>@ fpb = Catalog::gBuildsList[fp[q]];
				for (uint r = 0; r < fpb.length(); ++r) {
					if (Catalog::gExtractsM[fpb[r]] > fReach)
						fReach = Catalog::gExtractsM[fpb[r]];
				}
			}
			if (fFlies)
				continue;   // air labs are the successors, never the retired
			bool succeeded = false;
			// A strictly deeper-reaching plant, standing OR under
			// construction, retires this one (apexearth: "reclaiming the
			// T1 lab while building the T2 lab").
			for (uint gi2 = 0; gi2 < Factory::gFacUnits.length() && !succeeded; ++gi2) {
				CCircuitUnit@ g3 = Factory::gFacUnits[gi2];
				if ((g3 is null) || (g3 is f))
					continue;
				float g3Reach = 0.f;
				const array<int>@ g3p = Catalog::gBuildsList[int(g3.circuitDef.id)];
				for (uint q3 = 0; q3 < g3p.length(); ++q3) {
					if (!Catalog::gMobile[g3p[q3]] || !Catalog::gBuilder[g3p[q3]])
						continue;
					const array<int>@ g3b = Catalog::gBuildsList[g3p[q3]];
					for (uint r3 = 0; r3 < g3b.length(); ++r3) {
						if (Catalog::gExtractsM[g3b[r3]] > g3Reach)
							g3Reach = Catalog::gExtractsM[g3b[r3]];
					}
				}
				if (g3Reach > fReach)
					succeeded = true;
			}
			for (uint gi = 0; gi < Factory::gFacUnits.length() && !succeeded; ++gi) {
				CCircuitUnit@ g2 = Factory::gFacUnits[gi];
				if ((g2 is null) || (g2 is f))
					continue;
				const array<int>@ gp = Catalog::gBuildsList[int(g2.circuitDef.id)];
				for (uint q2 = 0; q2 < gp.length(); ++q2) {
					if (!Catalog::gMobile[gp[q2]] || !Catalog::gBuilder[gp[q2]]
						|| !Catalog::gFlyer[gp[q2]])
						continue;
					float gReach = 0.f;
					const array<int>@ gpb = Catalog::gBuildsList[gp[q2]];
					for (uint r2 = 0; r2 < gpb.length(); ++r2) {
						if (Catalog::gExtractsM[gpb[r2]] > gReach)
							gReach = Catalog::gExtractsM[gpb[r2]];
					}
					if (gReach >= fReach) {
						succeeded = true;
						break;
					}
				}
			}
			if (succeeded) {
				const float v = RetireValue(unit, f, fd, ePM, wageR, hz);
				if (v > bestValue) {
					bestValue = v;
					@best = f;
					bestDef = fd;
				}
			}
		}
	}
	if (best is null)
		return w;
	// One-shot metal amortized at the market's payback scale -- 60s priced a
	// single refund like a perpetual stream and it outbid every mex.
	const AIFloat3 gp = best.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(gp) / speed) : 60.f;
	w.kind = WK_RECLAIM;
	@w.def = Catalog::Def(bestDef);
	w.pos = gp;
	w.spotId = int(best.id);
	w.gain = RetireGain(best, bestDef, ePM, hz);
	w.mCost = 1.f;
	w.tCost = (walkSec + Catalog::gCostM[bestDef] / 90.f) * wageR;
	w.value = bestValue;
	@w.target = best;
	@gReclaimTarget = best;
	return w;
}

// RECLAIM WHAT IS STANDING IN THE SLOT. C++ records a lattice slot it could
// not place on (CCircuitAI::NoteBuildBlocked); this is the only thing that
// reads it. apexearth: "if we want to complete/extend a grid we should reclaim
// whatever building(s) are in the way so long as they are not much more
// valuable in comparison to the building we want to place."
//
// "Much more valuable" is not a ratio here -- it is the arithmetic. The ground
// is worth what the BEST generator we own would make on it instead of what is
// standing there, and clearing it costs that building's own output plus the
// time. A fusion blocking a wind slot prices itself out on the first term; a
// stray T1 solar does not.
Want@ ProposeReclaimBlocker(CCircuitUnit@ unit)
{
	Want w;
	if (ai.GetTunable("apex_reclaim_blocker", TUNE_RECLAIM_BLOCKER) < 0.5f)
		return w;
	AIFloat3 bp;
	if (!ai.GetBlockedBuildPos(bp) || !OnMap(bp))
		return w;
	// Best energy per cell we can actually build, and the eco structure of ours
	// nearest the blocked slot. Only ECONOMY is a candidate: extractors and
	// geothermals stand on ground they had to have, plants are the room the
	// lattice exists to protect, and towers and sensors were sited to cover
	// something rather than to sit in a row.
	float bestEcell = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gNeedGeo[d])
			continue;
		const int cells = (Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1;
		const float ec = Catalog::gMakeE[d] / float(cells);
		if (ec > bestEcell)
			bestEcell = ec;
	}
	CCircuitUnit@ blk = null;
	int blkDef = -1;
	float nearest = 1e9f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[di] || Catalog::gNeedGeo[di])
			continue;
		if ((Catalog::gExtractsM[di] > 0.f)
			|| (Catalog::gBuildsList[di].length() > 0))
			continue;
		if ((Catalog::gMakeE[di] < 1.f) && (Catalog::gConvCapacity[di] < 1.f)
			&& (Catalog::gStoreE[di] < 1.f) && (Catalog::gStoreM[di] < 1.f))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(di), bp,
				BLOCKER_REACH);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			if (us[i] is null)
				continue;
			const float dd = us[i].GetPos(ai.frame).distance2D(bp);
			if (dd < nearest) {
				nearest = dd;
				@blk = us[i];
				blkDef = di;
			}
		}
	}
	if (blk is null)
		return w;
	const int cells = (Catalog::gAreaCells[blkDef] > 0)
			? Catalog::gAreaCells[blkDef] : 1;
	const float ecell = Catalog::gMakeE[blkDef] / float(cells);
	const float horizon = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const AIFloat3 gp = blk.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(gp) / speed) : 60.f;
	w.kind = WK_RECLAIM;
	@w.def = Catalog::Def(blkDef);
	w.pos = gp;
	w.spotId = int(blk.id);
	// The metal back, plus the energy the ground would make once cleared minus
	// what it makes now. Both terms are zero or negative for anything already
	// pulling its weight, so this want simply never wins for those.
	w.gain = Catalog::gCostM[blkDef] / ((horizon > 1.f) ? horizon : 300.f)
			+ (bestEcell - ecell) * float(cells) * EPriceFloor();
	w.mCost = 1.f;
	w.tCost = (walkSec + Catalog::gCostM[blkDef] / 90.f) * Wage();
	w.value = (w.gain > 0.f) ? (w.gain / (w.mCost + w.tCost)) : 0.f;
	@w.target = blk;
	return w;
}


}  // namespace Market
