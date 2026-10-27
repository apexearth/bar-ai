namespace Market {
// CALIBRATION, STEP ONE: WHAT THE PRICE ASSUMED (his 10-27: make the pricing sound, then train a new net). Every
// structure of ours that finishes logs the risk the survival discount priced at its spot -- StreamRisk, a rate per
// second -- with its hazard and shortfall parts and its forward fraction; tools/calib.py joins it to the building's
// death (BARAI_DEATH by uid) and sets the predicted rate against the observed one, per kind and forward band.
void CalibNoteBorn(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null) || unit.circuitDef.IsMobile() || !Builder::gHomeSet)
		return;
	const AIFloat3 p = unit.GetPos(ai.frame);
	if (!OnMap(p))
		return;
	CbBorn(unit, p);
	CbBuildMatch(int(unit.circuitDef.id), p);
	AiLog("apex: calib-born t=" + ai.teamId + " uid=" + int(unit.id) + " def=" + unit.circuitDef.GetName()
		+ " fwd=" + NnF(Military::ForwardFraction(p), 2) + " risk=" + NnF(StreamRisk(p), 5)
		+ " hz=" + NnF(HazardAt(p), 5) + " short=" + NnF(ShortfallAt(p), 2));
}

// STEP THREE: BUILD TIME. An executed structure want leaves what the price assumed -- its walk and build seconds --
// against its def and site; the first such record for a def within CB_SITE_R of where a building of that def
// finishes is matched and all of them there are dropped, so re-elections and joiners fold into the first decision.
// `apex: calib-build ... pred=walk+build actual=` -- tools/calib.py sets them side by side per kind.
const float CB_SITE_R = 400.f;
array<int> gCxDef, gCxAt;
array<float> gCxX, gCxZ, gCxWalk, gCxBuild;
void CalibNoteExec(Want@ w)
{
	if ((w is null) || (w.def is null) || Catalog::gMobile[int(w.def.id)] || !OnMap(w.pos))
		return;
	const int d = int(w.def.id);
	for (uint i = 0; i < gCxDef.length(); ++i)
		if ((gCxDef[i] == d) && (Sq(gCxX[i] - w.pos.x) + Sq(gCxZ[i] - w.pos.z) < CB_SITE_R * CB_SITE_R))
			return;   // the first decision for this site already stands
	for (int i = int(gCxDef.length()) - 1; i >= 0; --i) {
		if (ai.frame - gCxAt[i] > 20 * MINUTE) {
			gCxDef.removeAt(i); gCxAt.removeAt(i); gCxX.removeAt(i); gCxZ.removeAt(i);
			gCxWalk.removeAt(i); gCxBuild.removeAt(i);
		}
	}
	gCxDef.insertLast(d);
	gCxAt.insertLast(ai.frame);
	gCxX.insertLast(w.pos.x);
	gCxZ.insertLast(w.pos.z);
	gCxWalk.insertLast(w.walkSec);
	gCxBuild.insertLast(w.buildSec);
}

float Sq(float x) { return x * x; }

void CbBuildMatch(int d, const AIFloat3& in p)
{
	int best = -1;
	for (uint i = 0; i < gCxDef.length(); ++i) {
		if ((gCxDef[i] != d) || (Sq(gCxX[i] - p.x) + Sq(gCxZ[i] - p.z) >= CB_SITE_R * CB_SITE_R))
			continue;
		if ((best < 0) || (gCxAt[i] < gCxAt[uint(best)]))
			best = int(i);
	}
	if (best < 0)
		return;
	const uint b = uint(best);
	AiLog("apex: calib-build t=" + ai.teamId + " def=" + Catalog::Def(d).GetName() + " fwd="
		+ NnF(Military::ForwardFraction(p), 2) + " walk=" + int(gCxWalk[b]) + " build=" + int(gCxBuild[b])
		+ " actual=" + int(float(ai.frame - gCxAt[b]) / 30.f) + " inc=" + int(Eco::MInc()));
	for (int i = int(gCxDef.length()) - 1; i >= 0; --i) {
		if ((gCxDef[i] == d) && (Sq(gCxX[i] - p.x) + Sq(gCxZ[i] - p.z) < CB_SITE_R * CB_SITE_R)) {
			gCxDef.removeAt(i); gCxAt.removeAt(i); gCxX.removeAt(i); gCxZ.removeAt(i);
			gCxWalk.removeAt(i); gCxBuild.removeAt(i);
		}
	}
}

// STEP FOUR: THE OPPORTUNITY CHARGE'S WAIT (apex_opp_wait). OppTimeReprice charges a want the runner-up's gain for
// the runner-up's delay, the winner's whole walk + build -- as if it waited for this hand. Measured (ckr, 2,509 cards):
// another hand started the runner-up's kind in a median 10-19 s for extractors, towers, energy, assists, upgrades and
// nanos, 35-80 s for converters, sensors and labs, 183 s for supers. Each execution leaves the kind it passed over;
// the next execution of that kind by another hand closes it, and the wait is an EMA per kind from those medians.
array<float> gOwWait;
array<int> gOwPendAt, gOwPendKind, gOwPendUnit;
int gOwOn = -1, gOwLogAt = 0;
bool OppWaitOn()
{
	if (gOwOn < 0)
		gOwOn = (ai.GetTunable("apex_opp_wait", TUNE_OPP_WAIT) > 0.f) ? 1 : 0;
	return gOwOn > 0;
}

float OwPrior(int k)
{
	if ((k == WK_MEX) || (k == WK_MEXUP) || (k == WK_NANO) || (k == WK_ASSIST))
		return 13.f;
	if ((k == WK_PROTECT) || (k == WK_TECH))
		return 16.f;
	if (k == WK_ENERGY)
		return 19.f;
	if ((k == WK_CONVERT) || (k == WK_RECLAIM))
		return 30.f;
	if ((k == WK_AIRDEF) || (k == WK_SENSE) || (k == WK_PLANT))
		return 70.f;
	if (k == WK_SUPER)
		return 180.f;
	return 30.f;
}

float OppWaitOf(int k)
{
	if (k < 0)
		return 30.f;
	if (int(gOwWait.length()) <= k) {
		const uint o = gOwWait.length();
		gOwWait.resize(k + 1);
		for (uint i = o; i < gOwWait.length(); ++i)
			gOwWait[i] = OwPrior(int(i));
	}
	return gOwWait[k];
}

void OppNoteExec(CCircuitUnit@ unit, int kind, Want@ passed)
{
	if (!OppWaitOn() || (unit is null))
		return;
	const int uid = int(unit.id);
	// this execution closes every pending pass of its kind by another hand
	for (int i = int(gOwPendAt.length()) - 1; i >= 0; --i) {
		const float age = float(ai.frame - gOwPendAt[i]) / 30.f;
		const bool closes = (gOwPendKind[i] == kind) && (gOwPendUnit[i] != uid);
		if (closes || (age > 600.f)) {
			const int k = gOwPendKind[i];
			const float w = closes ? age : 600.f;
			OppWaitOf(k);
			gOwWait[k] = 0.95f * gOwWait[k] + 0.05f * w;
			gOwPendAt.removeAt(i); gOwPendKind.removeAt(i); gOwPendUnit.removeAt(i);
		}
	}
	if ((passed !is null) && (passed.kind >= 0) && (gOwPendAt.length() < 64)) {
		gOwPendAt.insertLast(ai.frame);
		gOwPendKind.insertLast(passed.kind);
		gOwPendUnit.insertLast(uid);
	}
	if (ai.frame >= gOwLogAt) {
		gOwLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: opp-wait t=" + ai.teamId + " mex=" + NnF(OppWaitOf(WK_MEX), 0) + " protect="
			+ NnF(OppWaitOf(WK_PROTECT), 0) + " energy=" + NnF(OppWaitOf(WK_ENERGY), 0) + " plant="
			+ NnF(OppWaitOf(WK_PLANT), 0) + " super=" + NnF(OppWaitOf(WK_SUPER), 0) + " pending=" + gOwPendAt.length());
	}
}

// STEP TWO: THE MEASURED RATE (apex_calib_risk). 18 games of 2v2 at +50 (cala/b/c): the survival price read a flat
// 0.0020-0.0035/s everywhere -- the siege prior, foe/(foe+defended)/180 s -- while our structures died at 0.0003/s
// (rear energy) to 0.0045/s (forward extractors). Our own structures' enemy-caused deaths over the seconds they
// stood, by class (extractor or not) and forward fraction, read through a kernel; each band starts from that batch's
// rate, worth an hour of standing, until the game has its own.
const int CB_BINS = 16;
const float CB_F0 = -0.4f;
const float CB_W = 0.1f;
const float CB_PRIOR_S = 3600.f;
array<float> gCbN(2 * CB_BINS, 0.f), gCbExp(2 * CB_BINS, 0.f), gCbDie(2 * CB_BINS, 0.f);
array<int> gCbSlot;      // per unit id: class*CB_BINS + bin + 1, 0 none
array<bool> gCbAlive;
int gCbLast = -1;
int gCbOn = -1;
bool CalibRiskOn()
{
	if (gCbOn < 0)
		gCbOn = (ai.GetTunable("apex_calib_risk", TUNE_CALIB_RISK) > 0.f) ? 1 : 0;
	return gCbOn > 0;
}

int CbBin(float f)
{
	int b = int((f - CB_F0) / CB_W);
	return (b < 0) ? 0 : ((b >= CB_BINS) ? CB_BINS - 1 : b);
}

// the batch's rate per second at forward fraction f: rear (< 0.2), mid, forward (>= 0.4), linear between band centres
float CbPrior(int cls, float f)
{
	const float r0 = (cls == 0) ? 0.00073f : 0.00034f;
	const float r1 = (cls == 0) ? 0.0022f : 0.00062f;
	const float r2 = (cls == 0) ? 0.0045f : 0.00074f;
	if (f <= 0.1f)
		return r0;
	if (f <= 0.3f)
		return r0 + (r1 - r0) * (f - 0.1f) / 0.2f;
	if (f <= 0.5f)
		return r1 + (r2 - r1) * (f - 0.3f) / 0.2f;
	return r2;
}

void CbStep()
{
	if (gCbLast < 0) {
		gCbLast = ai.frame;
		return;
	}
	const int step = ai.frame - gCbLast;
	if (step <= 0)
		return;
	gCbLast = ai.frame;
	const float dt = float(step) / 30.f;
	float k = 1.f - dt / (4.f * LossTau());
	if (k < 0.f)
		k = 0.f;
	for (int i = 0; i < 2 * CB_BINS; ++i) {
		gCbExp[i] = gCbExp[i] * k + gCbN[i] * dt;
		gCbDie[i] *= k;
	}
}

void CbBorn(CCircuitUnit@ unit, const AIFloat3& in p)
{
	const int id = int(unit.id);
	if (id < 0)
		return;
	if (int(gCbSlot.length()) <= id) {
		gCbSlot.resize(id + 1024);
		gCbAlive.resize(id + 1024);
	}
	CbStep();
	const int cls = (Catalog::gExtractsM[int(unit.circuitDef.id)] > 0.f) ? 0 : 1;
	const int s = cls * CB_BINS + CbBin(Military::ForwardFraction(p));
	gCbSlot[id] = s + 1;
	gCbAlive[id] = true;
	gCbN[s] += 1.f;
}

// a structure of ours left the field; byEnemy counts it as a death
void CalibNoteGone(CCircuitUnit@ unit, bool byEnemy)
{
	if (unit is null)
		return;
	const int id = int(unit.id);
	if ((id < 0) || (id >= int(gCbSlot.length())) || (gCbSlot[id] <= 0))
		return;
	CbStep();
	const int s = gCbSlot[id] - 1;
	if (gCbAlive[id]) {
		gCbAlive[id] = false;
		gCbN[s] -= 1.f;
		if (gCbN[s] < 0.f)
			gCbN[s] = 0.f;
	}
	if (byEnemy) {
		gCbDie[s] += 1.f;
		gCbSlot[id] = 0;   // one death per building
	}
}

float CalibRate(int cls, float f)
{
	CbStep();
	const float pr = CbPrior(cls, f);
	float d = pr * CB_PRIOR_S, e = CB_PRIOR_S;
	for (int b = 0; b < CB_BINS; ++b) {
		const float u = (CB_F0 + (float(b) + 0.5f) * CB_W - f) / 0.15f;
		const float kk = 1.f / (1.f + u * u * u * u);
		d += kk * gCbDie[cls * CB_BINS + b];
		e += kk * gCbExp[cls * CB_BINS + b];
	}
	return d / e;
}

float CalibRateAt(int cls, const AIFloat3& in p)
{
	return CalibRate(cls, Military::ForwardFraction(p));
}

}  // namespace Market
