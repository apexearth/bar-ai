namespace Military {

// SUSPECTED UNSEEN FORCES (apex_jam_sight, his 10-17: players attack us with
// jammer-supported armies). What a player knows: a contact that drops off our
// radar inside our own coverage without being seen to die, a jammer seen, our
// things killed by a shooter nobody saw. Each place holds the metal that
// evidence implies, fading over the loss field's memory; sight of its centre
// answers it. The model runs in both arms; the switch feeds the risk reads and
// prices the sight.
const int JS_VANISH = 1;
const int JS_JAMMER = 2;
const int JS_HIT = 4;

bool gJsOnSet = false;
bool gJsOnV = false;
bool JamSightOn()
{
	if (!gJsOnSet) {
		gJsOnSet = true;
		gJsOnV = ai.GetTunable("apex_jam_sight", TUNE_JAM_SIGHT) > 0.f;
	}
	return gJsOnV;
}

array<int> gJmId;
array<int> gJmDef;
array<AIFloat3> gJmPos;
array<int> gJmSeen;
array<int> gJmSweep;

array<int> gJpUid;
array<float> gJpX;
array<float> gJpZ;
array<float> gJpR;
array<float> gJpVan;      // contacts that dropped off radar here, not seen since
array<float> gJpHit;      // ours killed here by a shooter we could not see
array<float> gJpShare;    // a mobile jammer's share of their army we cannot see
array<float> gJpM;        // the force believed here now
array<float> gJpW;        // metal/s that seeing it is worth
array<int> gJpKind;
array<int> gJpEv;         // the last evidence
array<int> gJpJam;        // the jammer it stands on, -1 none
array<int> gJpLos;        // when sight of its centre arrived, -1 none
array<bool> gJpDone;      // ...and what it showed has been counted
array<int> gJpOrder;      // when a sight was last ordered for it, -1 none
array<bool> gJpCovered;   // a sight post of ours watches it
array<float> gJpDecay;    // the evidence's weight now, 0 while we see it
int gJpNext = 1;

array<float> gJsHX;
array<float> gJsHZ;
array<float> gJsHR;
array<float> gJsHM;
uint gJsHN = 0;

array<int> gJsUnitPlace(32001, 0);
array<float> gJsUnitM(32001, 0.f);

const uint JS_BLAST_N = 16;
array<AIFloat3> gJsBlastPos(JS_BLAST_N, AIFloat3(-1.f, 0.f, -1.f));
array<float> gJsBlastR(JS_BLAST_N, 0.f);
array<int> gJsBlastAt(JS_BLAST_N, -999999);
array<int> gJsBlastId(JS_BLAST_N, -1);
uint gJsBlastNext = 0;

float gJsMobJamR = -1.f;
int gJsNextAt = 0;
int gJsLogAt = 0;
int gJsVanN = 0, gJsVanOut = 0, gJsHitN = 0, gJsLookN = 0, gJsLookOrd = 0, gJsRevN = 0, gJsOrdN = 0;
float gJsVanM = 0.f, gJsHitM = 0.f, gJsRevM = 0.f;
int gJsHitNT = 0, gJsOrdNT = 0, gJsLookNT = 0, gJsRevNT = 0;
float gJsHitMT = 0.f, gJsRevMT = 0.f;
double gJsUs = 0.0;
int gJsCalls = 0;

// The widest bubble a mobile jammer of the game throws.
float JsMobJamR()
{
	if (gJsMobJamR > 0.f)
		return gJsMobJamR;
	float r = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gMobile[d] && Catalog::gJammer[d] && (Catalog::gJamR[d] > r))
			r = Catalog::gJamR[d];
	}
	if (r > 0.f)
		gJsMobJamR = r;
	return r;
}

int JsPlaceIdx(int uid)
{
	for (uint i = 0; i < gJpUid.length(); ++i) {
		if (gJpUid[i] == uid)
			return int(i);
	}
	return -1;
}

int JsPlaceAdd(const AIFloat3& in p, float r, int jam)
{
	gJpUid.insertLast(gJpNext++);
	gJpX.insertLast(p.x);
	gJpZ.insertLast(p.z);
	gJpR.insertLast(r);
	gJpVan.insertLast(0.f);
	gJpHit.insertLast(0.f);
	gJpShare.insertLast(0.f);
	gJpM.insertLast(0.f);
	gJpW.insertLast(0.f);
	gJpKind.insertLast(0);
	gJpEv.insertLast(ai.frame);
	gJpJam.insertLast(jam);
	gJpLos.insertLast(-1);
	gJpDone.insertLast(false);
	gJpOrder.insertLast(-1);
	gJpCovered.insertLast(false);
	gJpDecay.insertLast(1.f);
	return int(gJpUid.length()) - 1;
}

void JsPlaceRemove(uint i)
{
	gJpUid.removeAt(i);
	gJpX.removeAt(i);
	gJpZ.removeAt(i);
	gJpR.removeAt(i);
	gJpVan.removeAt(i);
	gJpHit.removeAt(i);
	gJpShare.removeAt(i);
	gJpM.removeAt(i);
	gJpW.removeAt(i);
	gJpKind.removeAt(i);
	gJpEv.removeAt(i);
	gJpJam.removeAt(i);
	gJpLos.removeAt(i);
	gJpDone.removeAt(i);
	gJpOrder.removeAt(i);
	gJpCovered.removeAt(i);
	gJpDecay.removeAt(i);
}

// The place whose ground holds (x, z), nearest edge first.
int JsPlaceAt(float x, float z, float slack)
{
	int best = -1;
	float bd = 0.f;
	for (uint i = 0; i < gJpUid.length(); ++i) {
		const float dx = gJpX[i] - x;
		const float dz = gJpZ[i] - z;
		const float e = sqrt(dx * dx + dz * dz) - gJpR[i];
		if ((e < slack) && ((best < 0) || (e < bd))) {
			best = int(i);
			bd = e;
		}
	}
	return best;
}

bool JsRadarCovers(const AIFloat3& in p, float margin)
{
	const uint n = Market::gProtPos[Market::PROT_RADAR].length();
	for (uint i = 0; i < n; ++i) {
		const float rr = Catalog::gRadarR[Market::gProtDefId[Market::PROT_RADAR][i]];
		if ((rr > 1.f) && (p.distance2D(Market::gProtPos[Market::PROT_RADAR][i]) + margin < rr))
			return true;
	}
	return false;
}

void JsUncredit(int id)
{
	if ((id < 0) || (id >= int(gJsUnitPlace.length())) || (gJsUnitPlace[id] == 0))
		return;
	const int k = JsPlaceIdx(gJsUnitPlace[id]);
	if (k >= 0) {
		gJpVan[k] -= gJsUnitM[id];
		if (gJpVan[k] < 0.f)
			gJpVan[k] = 0.f;
	}
	gJsUnitPlace[id] = 0;
	gJsUnitM[id] = 0.f;
}

// Evidence lands in the place that holds it, or founds one there.
int JsPlaceFor(const AIFloat3& in p, float slack, float r0)
{
	int k = JsPlaceAt(p.x, p.z, slack);
	if (k < 0) {
		float r = JsMobJamR();
		if (r < r0)
			r = r0;
		k = JsPlaceAdd(p, r, -1);
	}
	return k;
}

void JsShiftCentre(int k, const AIFloat3& in p, float m)
{
	if (gJpJam[k] >= 0)
		return;
	const float w0 = gJpVan[k] + gJpHit[k];
	const float tot = w0 + m;
	if (tot <= 0.f)
		return;
	gJpX[k] = (gJpX[k] * w0 + p.x * m) / tot;
	gJpZ[k] = (gJpZ[k] * w0 + p.z * m) / tot;
}

// Slot s of the enemy memory was live and is not: inside our standing radar's
// cover, with the bank to run it, that is a jammer (or stealth) hiding it.
void JsNoteVanish(int s)
{
	const int id = gFmId[s];
	const int d = gFmDef[s];
	const AIFloat3 p = gFmPos[s];
	if ((id < 0) || !OnMap(p))
		return;
	float m = gFmBlipM;
	float spd = (gDgFoeSpd > 1.f) ? gDgFoeSpd : Market::FoeSpeedCap();
	if (d > 0) {
		m = Catalog::gCostM[d];
		spd = Catalog::gSpeed[d];
	}
	if (m <= 0.f)
		return;
	// radar does not see under water: a sub or a wader that went in is not hidden by a jammer
	if ((ai.GetElevationAt(p) < 0.f) && ((d <= 0) || Catalog::gSub[d] || Catalog::gAmphib[d])) {
		++gJsVanOut;
		return;
	}
	const float dt = float(ai.frame - gFmSeen[s]) / float(SECOND);
	const float margin = (dt > 0.f) ? spd * dt : 0.f;
	if ((Eco::ECur() < Eco::EPull()) || !JsRadarCovers(p, margin)) {
		++gJsVanOut;
		return;
	}
	++gJsVanN;
	gJsVanM += m;
	JsUncredit(id);
	const int k = JsPlaceFor(p, margin, margin);
	JsShiftCentre(k, p, m);
	gJpVan[k] += m;
	gJpKind[k] |= JS_VANISH;
	gJpEv[k] = ai.frame;
	if (id < int(gJsUnitPlace.length())) {
		gJsUnitPlace[id] = gJpUid[k];
		gJsUnitM[id] = m;
	}
}

void JsJammerRemove(uint j)
{
	gJmId.removeAt(j);
	gJmDef.removeAt(j);
	gJmPos.removeAt(j);
	gJmSeen.removeAt(j);
	gJmSweep.removeAt(j);
}

void JsNoteJammer(int i, int d)
{
	const int id = aiEnemyMgr.GetEnemyUnitIdAt(i);
	if (id < 0)
		return;
	const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
	int k = -1;
	for (uint j = 0; j < gJmId.length(); ++j) {
		if (gJmId[j] == id) {
			k = int(j);
			break;
		}
	}
	if ((los < 0) || ((los & (8 | 32 | 64)) != 0)) {
		if (k >= 0)
			JsJammerRemove(uint(k));
		return;
	}
	if (k < 0) {
		gJmId.insertLast(id);
		gJmDef.insertLast(d);
		gJmPos.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
		gJmSeen.insertLast(ai.frame);
		gJmSweep.insertLast(gFmSweepN);
		k = int(gJmId.length()) - 1;
	}
	gJmSweep[k] = gFmSweepN;
	if ((los & 3) != 0) {
		const AIFloat3 jp = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if (OnMap(jp)) {
			gJmPos[k] = jp;
			gJmSeen[k] = ai.frame;
		}
	}
}

void JsNoteOwnBlast(int id, const AIFloat3& in at, int d)
{
	if (!Catalog::ValidId(d) || (Catalog::gBlastR[d] <= 0.f) || !OnMap(at))
		return;
	const uint k = gJsBlastNext;
	gJsBlastNext = (gJsBlastNext + 1) % JS_BLAST_N;
	gJsBlastPos[k] = at;
	gJsBlastR[k] = Catalog::gBlastR[d];
	gJsBlastAt[k] = ai.frame;
	gJsBlastId[k] = id;
}

// Could anything we see have made that hit: a blast of ours, or a live enemy
// within its own reach plus its walk since we saw it.
bool JsHitExplained(int id, const AIFloat3& in at)
{
	for (uint k = 0; k < JS_BLAST_N; ++k) {
		if ((gJsBlastId[k] != id) && (ai.frame - gJsBlastAt[k] < 3 * SECOND)
			&& (gJsBlastPos[k].distance2D(at) < gJsBlastR[k]))
			return true;
	}
	const float reach = FoeReach();
	for (uint s = 0; s < gFmId.length(); ++s) {
		if ((gFmId[s] < 0) || !gFmLive[s])
			continue;
		const int d = gFmDef[s];
		const float rng = (d > 0) ? Catalog::gLandRange[d] : reach;
		const float spd = (d > 0) ? Catalog::gSpeed[d] : gDgFoeSpd;
		const float dt = float(ai.frame - gFmSeen[s]) / float(SECOND);
		if (gFmPos[s].distance2D(at) < rng + spd * dt)
			return true;
	}
	return false;
}

// One of ours died to a mobile weapon whose shooter we could not see.
void JsNoteUnseenLoss(CCircuitUnit@ unit, float costM)
{
	if ((unit is null) || (costM <= 0.f) || (unit.GetDamagedWeapon() < 0))
		return;
	const AIFloat3 at = unit.GetPos(ai.frame);
	if (!OnMap(at) || JsHitExplained(int(unit.id), at))
		return;
	++gJsHitN;
	gJsHitM += costM;
	++gJsHitNT;
	gJsHitMT += costM;
	float r = FoeReach();
	const int k = JsPlaceFor(at, r, r);
	JsShiftCentre(k, at, costM);
	gJpHit[k] += costM;
	gJpKind[k] |= JS_HIT;
	gJpEv[k] = ai.frame;
}

void JsNoteSightOrder(const AIFloat3& in at)
{
	int best = -1;
	float bd = 0.f;
	for (uint i = 0; i < gJpUid.length(); ++i) {
		const float d = at.distance2D(AIFloat3(gJpX[i], 0.f, gJpZ[i]));
		if ((best < 0) || (d < bd)) {
			best = int(i);
			bd = d;
		}
	}
	++gJsOrdN;
	++gJsOrdNT;
	if (best >= 0)
		gJpOrder[best] = ai.frame;
}

// The share of a place's ground we see now: its centre and the cover rays'
// bearings at half and full radius. What we see of it holds nothing hidden.
float JsSeenFrac(uint i)
{
	const AIFloat3 c(gJpX[i], 0.f, gJpZ[i]);
	int seen = ai.IsPosInLos(c) ? 1 : 0;
	int all = 1;
	for (int ring = 1; ring <= 2; ++ring) {
		const float rho = 0.5f * float(ring) * gJpR[i];
		for (int b = 0; b < Market::COVER_RAYS; ++b) {
			const float a = 6.283185f * float(b) / float(Market::COVER_RAYS);
			const AIFloat3 q(c.x + rho * cos(a), 0.f, c.z + rho * sin(a));
			++all;
			if (!OnMap(q) || ai.IsPosInLos(q))
				++seen;
		}
	}
	return float(seen) / float(all);
}

// Where a sight post stands to watch place i: toward home from its centre, as
// far as it still sees the whole place wherever the request's shake puts it.
AIFloat3 JsSightSite(uint i, int post)
{
	const AIFloat3 c(gJpX[i], 0.f, gJpZ[i]);
	const float dx = Builder::gHomePos.x - c.x;
	const float dz = Builder::gHomePos.z - c.z;
	const float span = sqrt(dx * dx + dz * dz);
	if (!Builder::gHomeSet || (span < 1.f))
		return AIFloat3(c.x, ai.GetElevationAt(c), c.z);
	float off = Catalog::gLosR[post] - gJpR[i] - SQUARE_SIZE * 16.f;
	if (off < 0.f)
		off = 0.f;
	if (off > span)
		off = span;
	AIFloat3 at(c.x + dx / span * off, 0.f, c.z + dz / span * off);
	at.y = ai.GetElevationAt(at);
	return at;
}

bool JsWatched(const AIFloat3& in c)
{
	const array<int>@ posts = Catalog::SightPosts();
	for (uint q = 0; q < posts.length(); ++q) {
		const int d = posts[q];
		if (Market::ComNearest(d, c, Catalog::gLosR[d], Market::CS_ANY) >= 0)
			return true;
	}
	return false;
}

bool JsLookClaimed(const AIFloat3& in c)
{
	for (uint i = 0; i < gLkKind.length(); ++i) {
		if ((gLkKind[i] == LOOK_JAM) && (gLkBy[i] >= 0) && (gLkPos[i].distance2D(c) < LOOK_MERGE_R))
			return true;
	}
	return false;
}

// The force near p that could reach a disc of radius r around it.
float JsSuspectM(const AIFloat3& in p, float r)
{
	if ((gJsHN == 0) || !JamSightOn())
		return 0.f;
	float m = 0.f;
	for (uint i = 0; i < gJsHN; ++i) {
		const float dx = gJsHX[i] - p.x;
		const float dz = gJsHZ[i] - p.z;
		const float rr = r + gJsHR[i];
		if (dx * dx + dz * dz < rr * rr)
			m += gJsHM[i];
	}
	return m;
}

// Their armed metal near p: what we see or remember there, or the force we
// suspect there, whichever is more.
float ArmedNearM(const AIFloat3& in p, float r)
{
	const float a = ai.GetEnemyArmedCostNear(p, r);
	const float s = JsSuspectM(p, r);
	return (s > a) ? s : a;
}

void JsUpdate()
{
	if (!Builder::gHomeSet || (Catalog::gDefCount <= 0) || (ai.frame < gJsNextAt))
		return;
	gJsNextAt = ai.frame + 2 * SECOND;
	const double t0 = ai.ClockUs();
	const float tau = Market::LossTau() * float(SECOND);
	for (int j = int(gJmId.length()) - 1; j >= 0; --j) {
		if (gFmSweepN - gJmSweep[j] < 2)
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLos(gJmId[j]);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			JsJammerRemove(uint(j));
	}
	for (uint i = 0; i < gJpUid.length(); ++i) {
		if (gJpJam[i] < 0)
			continue;
		bool alive = false;
		for (uint j = 0; (j < gJmId.length()) && !alive; ++j)
			alive = gJmId[j] == gJpJam[i];
		if (!alive)
			gJpJam[i] = -1;
	}
	for (uint j = 0; j < gJmId.length(); ++j) {
		const int d = gJmDef[j];
		const float jr = Catalog::gJamR[d];
		if (jr <= 1.f)
			continue;
		int k = -1;
		for (uint i = 0; (i < gJpUid.length()) && (k < 0); ++i) {
			if (gJpJam[i] == gJmId[j])
				k = int(i);
		}
		if (k < 0) {
			for (uint i = 0; i < gJpUid.length(); ++i) {
				if ((gJpJam[i] < 0) && (gJmPos[j].distance2D(AIFloat3(gJpX[i], 0.f, gJpZ[i])) < jr + gJpR[i])) {
					k = int(i);
					gJpJam[i] = gJmId[j];
					break;
				}
			}
		}
		if (k < 0)
			k = JsPlaceAdd(gJmPos[j], jr, gJmId[j]);
		gJpX[k] = gJmPos[j].x;
		gJpZ[k] = gJmPos[j].z;
		if (gJpR[k] < jr)
			gJpR[k] = jr;
		gJpKind[k] |= JS_JAMMER;
		if (Catalog::gMobile[d] && (gJmSeen[j] > gJpEv[k]))
			gJpEv[k] = gJmSeen[j];
	}
	const uint n = gJpUid.length();
	array<float> seen(n, 0.f);
	array<bool> mob(n, false);
	int nMobDark = 0;
	for (uint i = 0; i < n; ++i) {
		seen[i] = JsSeenFrac(i);
		if (gJpJam[i] < 0)
			continue;
		for (uint j = 0; j < gJmId.length(); ++j) {
			if ((gJmId[j] == gJpJam[i]) && Catalog::gMobile[gJmDef[j]]) {
				mob[i] = true;
				break;
			}
		}
		if (mob[i] && (seen[i] < 1.f))
			++nMobDark;
	}
	float unseen = FoeBelievedM() - FoeLiveM();
	if (unseen < 0.f)
		unseen = 0.f;
	const float share = (nMobDark > 0) ? unseen / float(nMobDark) : 0.f;
	for (int ii = int(n) - 1; ii >= 0; --ii) {
		const uint i = uint(ii);
		const AIFloat3 c(gJpX[i], 0.f, gJpZ[i]);
		if ((seen[i] >= 1.f) && (gJpLos[i] < 0)) {
			gJpLos[i] = ai.frame;
			gJpDone[i] = false;
			++gJsLookN;
			++gJsLookNT;
			if ((gJpOrder[i] >= 0) || JsLookClaimed(c))
				++gJsLookOrd;
		}
		gJpDecay[i] = pow(2.718282f, -float(ai.frame - gJpEv[i]) / tau) * (1.f - seen[i]);
		gJpShare[i] = (mob[i] && (seen[i] < 1.f)) ? share : 0.f;
		float m = gJpVan[i];
		if (gJpHit[i] > m)
			m = gJpHit[i];
		if (gJpShare[i] > m)
			m = gJpShare[i];
		gJpM[i] = m * gJpDecay[i];
		// what the sight showed: units seen inside the place since it arrived,
		// once the enemy memory has swept them
		if ((gJpLos[i] >= 0) && !gJpDone[i] && (gFmPublishedAt >= gJpLos[i] + 5 * SECOND)) {
			gJpDone[i] = true;
			float rev = 0.f;
			for (uint s = 0; s < gFmId.length(); ++s) {
				if ((gFmId[s] < 0) || (gFmSeen[s] < gJpLos[i]) || (gFmDef[s] <= 0))
					continue;
				if (gFmPos[s].distance2D(c) < gJpR[i])
					rev += Catalog::gCostM[gFmDef[s]];
			}
			if (rev > 0.f) {
				++gJsRevN;
				++gJsRevNT;
				gJsRevM += rev;
				gJsRevMT += rev;
			}
		}
		if ((gJpLos[i] >= 0) && gJpDone[i]) {
			gJpVan[i] = 0.f;
			gJpHit[i] = 0.f;
			if (gJpJam[i] < 0) {
				JsPlaceRemove(i);
				continue;
			}
			if (seen[i] < 1.f)
				gJpLos[i] = -1;
		}
		if ((gJpJam[i] < 0) && (gJpLos[i] < 0) && (gJpM[i] < 1.f))
			JsPlaceRemove(i);
	}
	for (int i = int(gJpUid.length()) - 1; i >= 0; --i) {
		if (gJpJam[i] >= 0)
			continue;
		for (int j = 0; j < i; ++j) {
			if (gJpJam[j] >= 0)
				continue;
			const float dx = gJpX[i] - gJpX[j];
			const float dz = gJpZ[i] - gJpZ[j];
			const float rr = (gJpR[i] > gJpR[j]) ? gJpR[i] : gJpR[j];
			if (dx * dx + dz * dz >= rr * rr)
				continue;
			gJpVan[j] += gJpVan[i];
			gJpHit[j] += gJpHit[i];
			if (gJpM[i] > gJpM[j])
				gJpM[j] = gJpM[i];
			gJpKind[j] |= gJpKind[i];
			if (gJpEv[i] > gJpEv[j])
				gJpEv[j] = gJpEv[i];
			if (gJpOrder[i] > gJpOrder[j])
				gJpOrder[j] = gJpOrder[i];
			JsPlaceRemove(uint(i));
			break;
		}
	}
	JsPrice();
	gJsHX.resize(0);
	gJsHZ.resize(0);
	gJsHR.resize(0);
	gJsHM.resize(0);
	for (uint i = 0; i < gJpUid.length(); ++i) {
		if (gJpM[i] < 1.f)
			continue;
		gJsHX.insertLast(gJpX[i]);
		gJsHZ.insertLast(gJpZ[i]);
		gJsHR.insertLast(gJpR[i]);
		gJsHM.insertLast(gJpM[i]);
	}
	gJsHN = gJsHX.length();
	gJsUs += ai.ClockUs() - t0;
	++gJsCalls;
	JsLog();
}

// What seeing each place is worth, metal/s: the loss its force threatens on
// what we have in its reach, priced the way ExpectedLossAt prices any stake,
// and the losses it is causing now.
void JsPrice()
{
	const uint n = gJpUid.length();
	if (n == 0)
		return;
	Market::RiskFill();
	const float reach = FoeReach();
	const float army = OurArmyNow();
	const float tau = Market::LossTau();
	array<float> unitsM(n, 0.f);
	bool any = false;
	for (uint i = 0; (i < n) && !any; ++i)
		any = gJpM[i] >= 1.f;
	if (any) {
		for (uint u = 0; u < gCombatId.length(); ++u) {
			CCircuitUnit@ cu = ai.GetTeamUnit(Id(gCombatId[u]));
			if ((cu is null) || (cu.circuitDef is null))
				continue;
			const AIFloat3 up = cu.GetPos(ai.frame);
			for (uint i = 0; i < n; ++i) {
				if ((gJpM[i] >= 1.f) && (up.distance2D(AIFloat3(gJpX[i], 0.f, gJpZ[i])) < gJpR[i] + reach))
					unitsM[i] += Catalog::gCostM[int(cu.circuitDef.id)];
			}
		}
	}
	const float fill = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	for (uint i = 0; i < n; ++i) {
		const AIFloat3 c(gJpX[i], 0.f, gJpZ[i]);
		gJpW[i] = 0.f;
		gJpCovered[i] = false;
		const float m = gJpM[i];
		if (m < 1.f)
			continue;
		gJpCovered[i] = JsWatched(c);
		const float cover = Market::CoverAt(c);
		const float stake = Market::StakeAt(c, gJpR[i] + reach) + unitsM[i];
		const float hz = Market::gRkAnchor * m / (m + army + cover);
		gJpW[i] = stake * hz * Market::ShortWith(c, cover, m)
				+ gJpHit[i] * gJpDecay[i] / ((tau > 1.f) ? tau : 180.f);
		if (JamSightOn() && !gJpCovered[i] && !StockArmy() && (gJpW[i] > 0.f))
			NoteLook(LOOK_JAM, c, gJpW[i] * ((fill > 1.f) ? fill : 180.f), 12);
	}
}

void JsLog()
{
	if (ai.frame < gJsLogAt)
		return;
	gJsLogAt = ai.frame + 60 * SECOND;
	float sumM = 0.f, sumW = 0.f;
	int kv = 0, kj = 0, kh = 0, cov = 0;
	array<int> ord;
	for (uint i = 0; i < gJpUid.length(); ++i) {
		sumM += gJpM[i];
		sumW += gJpW[i];
		if ((gJpKind[i] & JS_VANISH) != 0) ++kv;
		if ((gJpKind[i] & JS_JAMMER) != 0) ++kj;
		if ((gJpKind[i] & JS_HIT) != 0) ++kh;
		if (gJpCovered[i]) ++cov;
		uint at = ord.length();
		while ((at > 0) && (gJpM[uint(ord[at - 1])] < gJpM[i]))
			--at;
		ord.insertAt(at, int(i));
	}
	int mobJ = 0;
	for (uint j = 0; j < gJmId.length(); ++j) {
		if (Catalog::gMobile[gJmDef[j]])
			++mobJ;
	}
	string top = "";
	for (uint q = 0; (q < ord.length()) && (q < 3); ++q) {
		const uint i = uint(ord[q]);
		if (gJpM[i] < 1.f)
			break;
		top += ((q > 0) ? ";" : "") + int(gJpX[i]) + "," + int(gJpZ[i]) + ":r" + int(gJpR[i])
			+ ":m" + int(gJpM[i]) + ":"
			+ (((gJpKind[i] & JS_VANISH) != 0) ? "v" : "") + (((gJpKind[i] & JS_JAMMER) != 0) ? "j" : "")
			+ (((gJpKind[i] & JS_HIT) != 0) ? "h" : "")
			+ ":w" + formatFloat(gJpW[i], "", 0, 2)
			+ ":age" + int(float(ai.frame - gJpEv[i]) / float(SECOND))
			+ (gJpCovered[i] ? ":cov" : "") + ((gJpOrder[i] >= 0) ? ":ord" : "");
	}
	AiLog(Factory::T() + "apex: jamsight-stat t=" + ai.teamId + " on=" + (JamSightOn() ? 1 : 0)
		+ " places=" + gJpUid.length() + " forceM=" + int(sumM) + " worthW=" + formatFloat(sumW, "", 0, 2)
		+ " kinds=v" + kv + "/j" + kj + "/h" + kh + " covered=" + cov
		+ " jammers=" + gJmId.length() + "/mob" + mobJ
		+ " vanish=" + gJsVanN + "/" + int(gJsVanM) + " vanishOut=" + gJsVanOut
		+ " hit=" + gJsHitN + "/" + int(gJsHitM) + " hitT=" + gJsHitNT + "/" + int(gJsHitMT)
		+ " orders=" + gJsOrdN + " ordersT=" + gJsOrdNT
		+ " looks=" + gLkNoted[LOOK_JAM] + "/s" + gLkSettled[LOOK_JAM]
		+ " looked=" + gJsLookN + "/ord" + gJsLookOrd + " lookedT=" + gJsLookNT
		+ " revealed=" + gJsRevN + "/" + int(gJsRevM) + " revealedT=" + gJsRevNT + "/" + int(gJsRevMT)
		+ " top=" + ((top == "") ? "-" : top)
		+ " us=" + formatFloat((gJsCalls > 0) ? gJsUs / gJsCalls : 0.0, "", 0, 0));
	gJsVanN = 0; gJsVanOut = 0; gJsVanM = 0.f;
	gJsHitN = 0; gJsHitM = 0.f;
	gJsOrdN = 0; gJsLookN = 0; gJsLookOrd = 0;
	gJsRevN = 0; gJsRevM = 0.f;
	gJsUs = 0.0; gJsCalls = 0;
}

}  // namespace Military
