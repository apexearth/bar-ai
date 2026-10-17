namespace Military {

// ONE ASSESSMENT for the squads (docs/army.md): their armed strength that can be at a place when we are, against
// ours there, fought out on comfight's calibrated paper (CfSim: focus fire both ways, their splash on our clump, a
// commander's regeneration and D-gun, towers that reach where we stand). Every squad decision calls SqAssess.

class SqPool {
	float n = 0.f, dps = 0.f, hp = 0.f, m = 0.f, spr = 0.f, rng = 0.f, minRng = 0.f, spd = 0.f, foot = 0.f;
	float x = 0.f, z = 0.f;
}

// the last SqAssess
float gSqAX = 0.f;        // calibrated metal lost minus killed
float gSqABand = 0.f;     // its error band
float gSqAThemM = 0.f;    // their armed metal in the fight
int gSqAThemN = 0;
float gSqAFx = 0.f, gSqAFz = 0.f;   // their armed unit nearest the place
float gSqAL = 0.f, gSqAK = 0.f;     // raw predicted metal lost and killed (what calibration compares)
float gSqATwD = 0.f, gSqAAllyM = 0.f;
bool gSqAWin = false;
int gSqAUpd = -1;
float gSqEMaxSpd = 0.f;

// The registry comfight keeps, read whole every update: a decision on a half-built one saw units spawned since the
// last full pass as absent (open_blob launched at 0/0 against 20).
void SqAssessRead()
{
	if (gSqAUpd == ai.frame)
		return;
	gSqAUpd = ai.frame;
	CfScanStep();
	if (gCfScanI != 0)
		CfScanStep();
	CfReadDGun();
	CfCalRead();
	gSqEMaxSpd = 0.f;
	for (uint e = 0; e < gCfEDef.length(); ++e) {
		const int d = gCfEDef[e];
		if (Catalog::gMobile[d] && (Catalog::gSpeed[d] > gSqEMaxSpd))
			gSqEMaxSpd = Catalog::gSpeed[d];
	}
}

// Our units at (x, z) against every armed foe that reaches the walk from (fx, fz) to (x, z) by the time we pass
// there: a tower whose range covers a step of it, a mobile that can walk into range of that step first. `blind`
// adds the army we remember but cannot see, at their base (foemem.as puts the unsure rest there).
// prev: 0 decides afresh, CF_ENGAGE keeps a fight until past the band, CF_FALL re-enters only past it.
bool SqAssess(const SqPool@ p, float fx, float fz, float x, float z, bool blind, int prev)
{
	gSqAX = 0.f;
	gSqABand = 0.f;
	gSqAThemM = 0.f;
	gSqAThemN = 0;
	gSqAFx = x;
	gSqAFz = z;
	gSqAL = 0.f;
	gSqAK = 0.f;
	gSqATwD = 0.f;
	gSqAAllyM = 0.f;
	gSqAWin = false;
	++gSqAN;
	if ((p is null) || (p.n <= 0.f))
		return false;
	const int nE = int(gCfEDef.length());
	array<bool> seen(nE, false);
	array<int> ord;
	const float len = CfDist(fx, fz, x, z);
	float step = gCfEReach;
	if (step < p.rng + p.spr)
		step = p.rng + p.spr;
	int steps = (len > 0.f) ? int(ceil(len / step)) : 0;
	const float spd = (p.spd > 1.f) ? p.spd : 1.f;
	// we close on them over one reaction as they close on us (comfight's CfFoesNear reach)
	const float ourClose = p.spd * CF_REACT_S;
	float reachQ = gCfEReach;
	if (reachQ < p.rng)
		reachQ = p.rng;
	for (int k = 0; k <= steps; ++k) {
		const float f = (steps > 0) ? float(k) / float(steps) : 1.f;
		const float sx = fx + (x - fx) * f, sz = fz + (z - fz) * f;
		const float tUs = len * f / spd + CF_REACT_S;
		gCfEGrid.Query(sx, sz, reachQ + p.spr + ourClose + gSqEMaxSpd * tUs);
		for (uint h = 0; h < gCfEGrid.hit.length(); ++h) {
			const int e = gCfEGrid.hit[h];
			if ((e >= nE) || seen[e])
				continue;
			const int d = gCfEDef[e];
			float er = Catalog::gMaxRange[d];
			if (er < p.rng)
				er = p.rng;
			const float gap = CfDist(gCfEX[e], gCfEZ[e], sx, sz) - er - p.spr;
			const float walk = ourClose + (Catalog::gMobile[d] ? Catalog::gSpeed[d] * tUs : 0.f);
			if (gap > walk)
				continue;
			seen[e] = true;
			ord.insertLast(e);
		}
	}
	CfSortFoes(ord, x, z);
	array<int> defs;
	for (uint k = 0; k < ord.length(); ++k) {
		const int d = gCfEDef[ord[k]];
		defs.insertLast(d);
		gSqAThemM += Catalog::gCostM[d];
	}
	if (ord.length() > 0) {
		gSqAFx = gCfEX[ord[0]];
		gSqAFz = gCfEZ[ord[0]];
	}
	if (blind) {
		for (uint s = 0; s < gFmId.length(); ++s) {
			if ((gFmId[s] < 0) || gFmLive[s] || (gFmDef[s] <= 0))
				continue;
			const int d = gFmDef[s];
			const float dt = float(ai.frame - gFmSeen[s]) / float(SECOND);
			if (Catalog::gSpeed[d] * dt <= Catalog::gMaxRange[d])
				continue;   // the registry still holds it where it was
			defs.insertLast(d);
			gSqAThemM += Catalog::gCostM[d];
		}
	}
	gSqAThemN = int(defs.length());
	if (defs.length() == 0) {
		gSqAWin = true;
		return true;
	}
	AIFloat3 at(x, 0.f, z);
	float twD = 0.f, twH = 0.f;
	Market::ComGunAt(at, twD, twH);
	float n = p.n, dps = p.dps, hp = p.hp, m = p.m;
	const float allyM = ai.GetAllyArmyMAt(at, p.rng + p.spr);
	if ((allyM > 0.f) && (m > 0.f)) {
		const float k = allyM / m;
		n += n * k;
		dps += dps * k;
		hp += hp * k;
		m += allyM;
	}
	CfSim(n, dps / n, hp / n, m / n, p.spr, p.rng, twD, twH, defs, CfDgT0(ord, x, z, p.spr));
	gSqAL = gCfLostO;
	gSqAK = gCfLostT;
	gSqATwD = twD;
	gSqAAllyM = allyM;
	const float Lc = gCfRL * gCfLostO, Kc = gCfRK * gCfLostT;
	gSqAX = Lc - Kc;
	// the band is the estimate's measured error; before any fight is measured there is none to hold a verdict by
	// (the prior band is the whole estimate, which no verdict ever crosses)
	gSqABand = (gCfCalT[0] >= 1.f) ? sqrt(gCfSL * Lc * gCfSL * Lc + gCfSK * Kc * gCfSK * Kc) : 0.f;
	gSqAWin = CfFightCond(gSqAX, gSqABand, prev);
	return gSqAWin;
}

string SqAssessLine(const SqPool@ p)
{
	return "apex: squad-assess t=" + ai.teamId + " us=" + int(p.n) + "u/" + int(p.dps) + "dps/" + int(p.hp) + "hp/"
		+ int(p.m) + "m spr=" + int(p.spr) + " rng=" + int(p.rng) + " spd=" + int(p.spd)
		+ " them=" + gSqAThemN + "u/" + int(gSqAThemM) + "m reg=" + gCfEDef.length() + " tw=" + int(gSqATwD)
		+ " ally=" + int(gSqAAllyM) + " L=" + int(gSqAL) + " K=" + int(gSqAK)
		+ " cal=" + int(gCfCalT[0]) + " rL=" + formatFloat(gCfRL, "", 0, 2) + " rK=" + formatFloat(gCfRK, "", 0, 2)
		+ " sL=" + formatFloat(gCfSL, "", 0, 2) + " sK=" + formatFloat(gCfSK, "", 0, 2)
		+ " X=" + int(gSqAX) + " band=" + int(gSqABand) + " win=" + (gSqAWin ? 1 : 0);
}

// the armed foes within reach of a group standing where it is, nearest first (comfight's own reach)
void SqFoesIn(const SqPool@ p, array<int>& out foe)
{
	bool com;
	CfFoesNear(p.x, p.z, p.rng, p.spd, p.spr, foe, com);
	if (foe.length() > 0) {
		float tx, tz, sx, sz;
		CfNearestFoe(foe, p.x, p.z, tx, tz);
		CfStandAt(p.x, p.z, tx, tz, p.rng, sx, sz);
		CfDropFarStatics(foe, sx, sz, p.spr);
	}
}

}  // namespace Military
