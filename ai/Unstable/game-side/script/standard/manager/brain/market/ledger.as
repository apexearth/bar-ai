namespace Market {
//------------------------------------------------------------------------------
// Proposers -- pure, one Want each, value <= 0 means "not now".
//------------------------------------------------------------------------------

// Whether the last mex probe found open ground; the production market reads
// this as its demand signal for more claiming capacity.
bool gMexOpen = false;
float gAvgWalkDist = 600.f;   // smoothed claim walk, seeds at a near spot
// Rolling value of EXECUTED builder wants -- what a unit of spend is
// actually earning right now; the factory lines' opportunity floor.
float gWantEmaV = 0.f;
int gSupportDiagAt = 0;

// The rear-specialist election's enemy reference (ally centroid mirrored
// through map center), kept for the quiet rear's reach filter.
float gEcoRefX = -1.f;
float gEcoRefZ = -1.f;

// A constructor's mobility, as cycle speed on the CURRENT map's walks. Air
// cons fly the straight line and ignore blockage/pathing -- in a packed
// nano farm they are often the only realistic builder (apexearth
// 2026-08-23). MODEL: the flyer shortcut fraction.
float MobilityMult(int defId)
{
	const float speed = Catalog::gSpeed[defId];
	if (speed <= 1.f)
		return 1.f;
	float dist = gAvgWalkDist;
	if (Catalog::gFlyer[defId])
		dist *= ai.GetTunable("apex_fly_short", TUNE_FLY_SHORT);
	const float cycle = dist / speed + 12.f;   // walk + a claim's build
	float mob = 60.f / ((cycle > 1.f) ? cycle : 1.f);
	if (mob < 0.5f)
		mob = 0.5f;
	if (mob > 2.5f)
		mob = 2.5f;
	return mob;
}

// The last probed open spot's real yield (income x extraction); the tunable
// is only the pre-probe fallback. This was a MODEL term until the
// GetMexSpotIncome binding landed.
float gLastSpotM = -1.f;
float SpotM()
{
	return (gLastSpotM > 0.f) ? gLastSpotM
			: ai.GetTunable("apex_spot_m", TUNE_SPOT_M);
}

//------------------------------------------------------------------------------
// The claimed-spot ledger: which spots are ours, at what standing extraction.
// Fed by our own decisions and the finished/destroyed events; upgrade demand
// (and through it the tech want) is computed from this.
//------------------------------------------------------------------------------

array<int> gLSpot;
array<AIFloat3> gLPos;
array<float> gLIncome;    // the spot's raw income (extraction 1.0)
array<float> gLExtract;   // standing extraction; 0 until a mex FINISHES here
array<int> gLClaimAt;     // frame of the claim; unfinished claims expire
int LedgerFind(int spotId)
{
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLSpot[i] == spotId)
			return int(i);
	}
	return -1;
}
void LedgerClaim(int spotId, const AIFloat3& in pos, float income)
{
	if (LedgerFind(spotId) >= 0)
		return;
	gLSpot.insertLast(spotId);
	gLPos.insertLast(pos);
	gLIncome.insertLast(income);
	gLExtract.insertLast(0.f);
	gLClaimAt.insertLast(ai.frame);
}
// A claim that never finished releases its spot for re-proposal; without
// this, an aborted mex task left its ledger entry blocking the spot (and
// with it, the 21-decides-per-second churn cycling the same ground).
void LedgerSweep()
{
	for (uint i = 0; i < gLSpot.length(); ) {
		if ((gLExtract[i] <= 0.f) && (ai.frame - gLClaimAt[i] > 120 * SECOND)) {
			gLSpot.removeAt(i);
			gLPos.removeAt(i);
			gLIncome.removeAt(i);
			gLExtract.removeAt(i);
			gLClaimAt.removeAt(i);
			continue;
		}
		++i;
	}
}
int LedgerNearest(const AIFloat3& in pos)
{
	int best = -1;
	float bestD = 150.f;   // a mex stands on its spot; anything further is not it
	for (uint i = 0; i < gLPos.length(); ++i) {
		const float dd = pos.distance2D(gLPos[i]);
		if (dd < bestD) {
			bestD = dd;
			best = int(i);
		}
	}
	return best;
}

}  // namespace Market
