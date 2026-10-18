namespace Base {

// The grid cell this structure should go in, already resolved to a site the
// terrain manager says is buildable.
//
// The returned position is meant to be enqueued with a shake of ZERO. Shake
// exists to find any free spot near a guess; with a grid the spot is already
// known, and the task's own site search will settle on this exact one.
bool Spot(CCircuitUnit@ unit, CCircuitDef@ def, int kind, AIFloat3& out spot)
{
	if ((def is null) || !Frame())
		return false;
	SweepReserves();

	// The band's own rectangle, with slack. Packing pitch belongs to block_map;
	// the layout only has to enforce that a site stays in its band and off a walkway.
	const float depthLo = BAND_BACK[kind] - BAND_SLACK;
	const float depthHi = BAND_BACK[kind] + float(BAND_ROWS[kind]) * BAND_ROW[kind] + BAND_SLACK;
	const float latHi = HALF_SPAN + BAND_SLACK;

	for (int pass = 0; pass < 2; ++pass) {
	const float seek = (pass == 0) ? SEEK : SEEK_LOOSE;
	// The strict pass resumes just behind the frontier so the rows fill forward;
	// the loose pass restarts at zero, which is also what refills holes.
	int start = (pass == 0) ? (gCursor[kind] - SCAN_REWIND) : 0;
	if (start < 0)
		start = 0;
	for (int n = 0; n < SCAN_MAX; ++n) {
		const int index = start + n;
		AIFloat3 cell;
		if (!CellPos(kind, index, cell)) {
			if (pass == 1)
				++gFailBand;
			break;
		}
		if (Reserved(kind, index)) {
			++gFailBusy;
			continue;
		}
		if (!OnMap(cell)) {
			++gFailTerrain;
			continue;
		}
		if (Builder::ThreatFor(unit, cell) > Builder::CON_THREAT_VETO) {
			++gFailHot;
			continue;
		}
		// Snap the INTENT to this def's own build grid (the engine's
		// Pos2BuildPos parity rule) before searching: the search then starts
		// on a legal cell for this footprint instead of 8 elmos off it, so
		// rows of mixed footprints stay flush. apexearth: "ensure that we
		// place it on a floored 2 mod grid... for any buildings."
		cell = ai.SnapBuildPos(def, cell);
		const AIFloat3 site = ai.FindBuildSiteNear(def, cell, seek);
		if (!OnMap(site)) {
			++gFailTerrain;   // nothing can stand near this cell
			continue;
		}
		float sDepth, sLat;
		Coords(site, sDepth, sLat);
		if ((sDepth < depthLo) || (sDepth > depthHi) || (Abs(sLat) > latHi)) {
			++gFailTerrain;   // left the band; treat the cell as taken
			continue;
		}
		if (LanesApply(sDepth) && ((LaneGap(sLat) < LaneHalf()) || (LaneGap(sDepth) < LaneHalf()))) {
			++gFailTerrain;   // would stand in a walkway or across a cross-street
			continue;
		}
		if (SiteTaken(kind, site)) {
			++gFailBusy;
			continue;
		}
		Reserve(kind, index);
		ReserveSite(site);
		NoteTiling(kind, site);
		Grow(kind, index);
		gCursor[kind] = index;
		++gPlaced;
		spot = site;
		return true;
	}
	}
	++gNoRoom;
	return false;
}

// Can we still tech up? Asks the terrain manager directly whether a site for an
// advanced lab exists near the base, rather than inferring it from a build that
// quietly never happens.
const float TECH_PROBE_R = 1800.f;

CCircuitDef@ TechProbeDef()
{
	return SideDef3(Factory::armalab, Factory::coralab, Factory::legalab);
}

void Update()
{
	if (!Frame())
		return;
	SweepReserves();
	if (ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 60 * SECOND;

	int techDist = -1;
	CCircuitDef@ probe = TechProbeDef();
	if (probe !is null) {
		const AIFloat3 site = ai.FindBuildSiteNear(probe, gAnchor, TECH_PROBE_R);
		if (OnMap(site))
			techDist = int(site.distance2D(gAnchor));
	}

	AIFloat3 blocked;
	AiLog(Factory::T() + "apex: base area=" + int(Area())
		+ " width=" + int(gMaxLat - gMinLat) + " depth=" + int(gMaxDepth)
		+ " placed=" + gPlaced + " noroom=" + gNoRoom
		+ " touch=" + gTouch + "/" + (gTouch + gApart)
		+ " cur=" + gCursor[NANO] + "/" + gCursor[ECO] + "/" + gCursor[HEAVY]
		+ " (band=" + gFailBand + " hot=" + gFailHot
		+ " terrain=" + gFailTerrain + " busy=" + gFailBusy + ")"
		+ " blocked=" + (ai.GetBlockedBuildPos(blocked) ? 1 : 0)
		+ " techroom=" + techDist);
}

}  // namespace Base
