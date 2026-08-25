namespace Market {
// The best extraction any AVAILABLE def in the game reaches -- the ceiling
// upgrade demand is measured against.
float gBestExtract = -1.f;
float BestExtract()
{
	// NEVER CACHE A ZERO: Catalog::gAvailable is frame-dependent, so a first
	// call before extractors unlock would latch 0 forever -- and UpDemand, and
	// with it the entire tech want, would read 0 for the rest of the game.
	if (gBestExtract > 0.f)
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

// THE ARMY A LONG BUILD CANNOT AFFORD. apexearth: "during that entire time
// you're making an AFUS you can afford military better and protect yourself.
// You're giving yourself options." Two of the three costs he names are already
// priced -- the build may die (the survival discount) and it delays extraction
// (the streams below). The third was not: income and lathes committed to a
// frame for eighteen minutes are income and lathes the army and defence wanted,
// and a build that delivers in forty seconds surrenders almost none of that.
// Same currency and the same unserved-demand shape as the extraction streams.
float ArmyGapStream()
{
	const float gap = ArmyTarget() - ArmyValue();
	if (gap <= 0.f)
		return 0.f;
	const float fill = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	return gap / ((fill > 1.f) ? fill : 180.f);
}

// UpDemand BOUNDED BY HANDS THAT CAN SERVE IT. Catalog::gAvailable is not
// tier-gated, so BestExtract() names the moho from frame zero and UpDemand
// reports the full upgrade stream while we own no constructor able to place
// one. Charging that against every build taxes a T1 solar for work nobody
// could do. Zero until some owned mobile builder reaches the ceiling.
float ServableUpDemand()
{
	const float ceil = BestExtract();
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		const array<int>@ bb = Catalog::gBuildsList[di];
		for (uint q = 0; q < bb.length(); ++q) {
			if (Catalog::gExtractsM[bb[q]] >= ceil)
				return UpDemand();
		}
	}
	return 0.f;
}

// THE EXPANSION STREAM A LONG BUILD POSTPONES. UpDemand is the metal/s waiting
// on mex UPGRADES; this is the metal/s waiting on mex CLAIMS. Charging only the
// first meant a build that eats the economy for minutes was billed nothing on a
// map where we hold almost nothing to upgrade -- measured on Supreme Isthmus,
// held=4 of mapSpots=90 with upD=16, so an afus postponed "nothing" while what
// it actually postponed was eighty-four spots (apexearth, watching it happen
// again). Bounded by the hands that could actually claim them, the same
// unserved-demand shape used everywhere else.
float OpenSpotStream()
{
	CacheSpots();
	const int open = int(gAllSpots.length()) - int(gLSpot.length());
	if (open <= 0)
		return 0.f;
	float claimers = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] > 0) && Catalog::gMobile[int(d)] && Catalog::gBuilder[int(d)])
			claimers += float(gOwnCount[d]);
	}
	if (claimers < 1.f)
		claimers = 1.f;
	const float reach = (float(open) < claimers) ? float(open) : claimers;
	return reach * SpotM();
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

// WHY A MEX WANT DID NOT HAPPEN. apexearth: "our largest problem is still that
// we are not making enough mexes. If we aren't capturing half the map worth of
// mexes in a 1v1 then we're losing the game." Each refusal is counted at its
// own gate so the answer is read, not guessed.
int gMexNoOpen = 0, gMexPastFront = 0, gMexDeathWalk = 0, gMexEcoFar = 0;
int gMexEcoQuiet = 0, gMexClaimed = 0, gMexPriced = 0, gNextMexDiag = 0;
int gMexDeep = 0;
void MexDiag()
{
	if (ai.frame < gNextMexDiag)
		return;
	gNextMexDiag = ai.frame + 60 * SECOND;
	CacheSpots();
	// How DEEP the ground we hold is: 0 = our own start, 1 = theirs. The whole
	// point of the gradient is to keep the opening constructors off contested
	// centre spots (apexearth: "stop our initial constructors from taking what
	// are often thought of as more valuable mexes or geos in the center of the
	// map - highly contested areas"), so it is the number to watch.
	float gMax = 0.f, gSum = 0.f;
	for (uint gi = 0; gi < gLPos.length(); ++gi) {
		const float gg = ThreatGradient(gLPos[gi]);
		gSum += gg;
		if (gg > gMax) gMax = gg;
	}
	const float gAvg = (gLPos.length() > 0) ? (gSum / float(gLPos.length())) : 0.f;
	AiLog("apex: mexdiag t=" + ai.teamId + " mapSpots=" + gAllSpots.length()
		+ " held=" + gLSpot.length()
		+ " depthAvg=" + formatFloat(gAvg, "", 0, 2)
		+ " depthMax=" + formatFloat(gMax, "", 0, 2)
		+ " | noOpen=" + gMexNoOpen + " claimed=" + gMexClaimed
		+ " pastFront=" + gMexPastFront + " deathWalk=" + gMexDeathWalk
		+ " ecoFar=" + gMexEcoFar + " ecoQuiet=" + gMexEcoQuiet
		+ " deep=" + gMexDeep
		+ " priced=" + gMexPriced);
	gMexNoOpen = 0; gMexPastFront = 0; gMexDeathWalk = 0; gMexEcoFar = 0;
	gMexEcoQuiet = 0; gMexClaimed = 0; gMexPriced = 0;
	gMexDeep = 0;
}

// THE REFERENCE POINT IS THE DECISION. FindOpenMexSpot answers with ONE spot
// near whatever position it is handed, so asking only from the builder's feet
// made the search stop at the nearest cluster -- and when that one answer was
// already ours, the want returned empty and expansion left the auction
// entirely for that election (apexearth: "we easily get into funks where we
// don't even try to capture additional mex locations"). The map's own spot
// list is already cached, so rank every spot we do not hold by what it pays
// against the walk, and let the engine confirm what is actually open near the
// best of them. The engine keeps sole authority over occupancy, reachability
// and buildability; the ranking only chooses where to ask.
const int MEX_TRIES = 3;
int PickSpot(CCircuitUnit@ unit, const AIFloat3& in here, float speed)
{
	CacheSpots();
	array<int> cand;
	array<float> score;
	for (uint si = 0; si < gAllSpots.length(); ++si) {
		if (LedgerFind(int(si)) >= 0)
			continue;
		const AIFloat3 sp = gAllSpots[si];
		if (!OnMap(sp))
			continue;
		const float inc = aiEconomyMgr.GetMexSpotIncome(int(si));
		if (inc <= 0.f)
			continue;
		// Geometry-only vetoes are applied here so a refused spot does not
		// consume one of the engine probes below; DeathWalk stays on the
		// chosen spot, where its enemy-cost samples are paid for once.
		// A MEX IS WORTH CONTESTING FURTHER OUT THAN A BUILDING IS. PastFront
		// applies the CONSTRUCTOR bar (CON_FAR_FRAC 0.72) while sitesafety.as
		// already carries MEX_FAR_FRAC (0.92) written for exactly this and used
		// only by MexHeat. On a 90-spot map the strict bar refused 1,976 spot
		// evaluations in one 60s window and we held FOUR of ninety
		// (apexearth's Supreme Isthmus game). The spot is still priced for
		// risk after this -- StreamSurvival and the exposure charge both bite.
		if (Front::FoeKnown()
			&& Builder::PastFrontFrac(sp, Builder::MEX_FAR_FRAC)) {
			++gMexPastFront;
			continue;
		}
		if (EcoFar(sp)) {
			++gMexEcoFar;
			continue;
		}
		const float walk = (speed > 1.f) ? (here.distance2D(sp) / speed) : 60.f;
		cand.insertLast(int(si));
		score.insertLast(inc / (walk + 1.f));
	}
	for (int k = 0; k < MEX_TRIES; ++k) {
		int bi = -1;
		float bs = 0.f;
		for (uint i = 0; i < score.length(); ++i) {
			if (score[i] > bs) {
				bs = score[i];
				bi = int(i);
			}
		}
		if (bi < 0)
			break;
		const int sid = cand[bi];
		score[bi] = -1.f;
		// Threat ceiling is generous on purpose: a contested spot is priced,
		// not hidden (the leaf era's FindOpenMexSpot went silent exactly under
		// attack).
		const int open = aiEconomyMgr.FindOpenMexSpot(unit, gAllSpots[sid], 99.f);
		if (open < 0)
			continue;
		if (LedgerFind(open) >= 0) {
			++gMexClaimed;
			continue;
		}
		return open;
	}
	return -1;
}

Want@ ProposeMex(CCircuitUnit@ unit)
{
	Want w;
	MexDiag();
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 here = unit.GetPos(ai.frame);
	int spot = PickSpot(unit, here, Catalog::gSpeed[uid]);
	gMexOpen = (spot >= 0);
	if (spot < 0) {
		++gMexNoOpen;
		return w;
	}
	const AIFloat3 pos = aiEconomyMgr.GetMexSpotPos(spot);
	// SUPER RISKY GROUND IS NOT A BUILD OPTION (apexearth): a spot past the
	// front is a con's death walk whatever it pays -- and refusing it also
	// stops the market hiring more cons for ground nobody can hold.
	if (Front::FoeKnown()
		&& Builder::PastFrontFrac(pos, Builder::MEX_FAR_FRAC)) {
		++gMexPastFront;
		gMexOpen = false;
		return w;
	}
	// Deadly for THIS walker; the spot itself stays open for a safer angle,
	// so gMexOpen is not cleared.
	if (DeathWalk(unit, pos)) {
		++gMexDeathWalk;
		return w;
	}
	// The quiet rear stays home: no claim meaningfully closer to the enemy
	// than its own base depth (the mirror reference works pre-contact too).
	if (EcoFar(pos)) {
		++gMexEcoFar;
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
			++gMexEcoQuiet;
			gMexOpen = false;
			return w;
		}
	}
	++gMexPriced;
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
			// Share of TOTAL economic power, the same denominator the energy
			// premium uses -- see want_energy.as.
			const float inc0 = EcoPowerM();
			gain *= 1.f + ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH)
					* gain / ((inc0 > gain) ? inc0 : gain);
		}
		// Only what we expect to still be collecting: an unguarded spot keeps
		// its income for as long as it lives, and no longer.
		gain *= StreamSurvival(pos);
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_MEX;
			@w.def = Catalog::Def(d);
			w.pos = pos;
			w.spotId = spot;
			// The RAW yield. Storing the premium- and survival-scaled gain
			// here made SpotM -- and through it OpenSpotStream and every
			// build's displacement charge -- a number that is not a yield.
			gLastSpotM = spotIncome * Catalog::gExtractsM[d];
		}
	}
	return w;
}


}  // namespace Market
