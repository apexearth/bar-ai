namespace Military {

// ENEMY ARMY MEMORY: every armed enemy ground unit we have ever had in LOS or
// radar, by unit id, until we see it die. Out of sight it walks on along its
// last heading at its own speed, and our certainty of that position fades
// over its own walk time to our edge; the share we are no longer sure of is
// put back at their base. The C++ registry forgets a ghost once its tile is
// seen empty (90 s) and never moves one; this does not forget it.
// The registry is swept a fifth per AiUpdate (one full pass ~5 s), so the
// cost per call is a fifth of the enemy units we know.
array<int> gFmSlotOf;               // unit id -> slot + 1
array<int> gFmId;
array<int> gFmDef;                  // 0 = radar blip never seen in LOS
array<AIFloat3> gFmPos;             // last position seen in LOS/radar
array<AIFloat3> gFmVel;             // per second, at that moment
array<int> gFmSeen;                 // frame of that sighting
array<bool> gFmLive;                // in LOS/radar at the last sweep
array<bool> gFmGone;                // the registry no longer holds it
array<int> gFmSweep;
array<int> gFmFree;
int gFmIdx = 0;
int gFmTotal = 0;
int gFmChunk = 0;
int gFmSweepN = 0;
array<int> gFmDeathDef;
array<AIFloat3> gFmDeathPos;

// published at the end of each sweep
array<float> gFmLiveBins(DG_BINS + 1, 0.f);   // cumulative, like gDgFoe
array<float> gFmMemBins(DG_BINS + 1, 0.f);
float gFmLiveS = 0.f, gFmLiveM = 0.f;
float gFmMemS = 0.f, gFmMemM = 0.f;            // out of sight, certainty-weighted
float gFmLostS = 0.f, gFmLostM = 0.f;          // out of sight, the uncertain rest
float gFmMemEtaS = -1.f;                       // strength-weighted, out of sight
float gFmMemCert = 0.f;
float gFmNearLive = -1.f;
int gFmNLos = 0, gFmNRadar = 0, gFmNGhost = 0, gFmNGone = 0, gFmNBlip = 0;
float gFmDeadM = 0.f, gFmEverM = 0.f;
array<float> gFmLiveD(4, 0.f);                 // live metal by rim distance quarter of the foe-base distance
array<float> gFmMemD(4, 0.f);
int gFmPublishedAt = -1;
int gFmNextLog = 0;
double gFmUs = 0.0, gFmMaxUs = 0.0;
int gFmCalls = 0;

int FmSlot(int id)
{
	if (id < 0)
		return -1;
	if (id < int(gFmSlotOf.length()) && (gFmSlotOf[id] > 0))
		return gFmSlotOf[id] - 1;
	if (id >= int(gFmSlotOf.length()))
		gFmSlotOf.resize(id + 1);
	int s;
	if (gFmFree.length() > 0) {
		s = gFmFree[gFmFree.length() - 1];
		gFmFree.removeLast();
	} else {
		s = int(gFmId.length());
		gFmId.insertLast(-1); gFmDef.insertLast(0); gFmPos.insertLast(AIFloat3());
		gFmVel.insertLast(AIFloat3()); gFmSeen.insertLast(0); gFmLive.insertLast(false);
		gFmGone.insertLast(false); gFmSweep.insertLast(-1);
	}
	gFmId[s] = id; gFmDef[s] = 0; gFmSeen[s] = ai.frame; gFmLive[s] = false;
	gFmGone[s] = false; gFmSweep[s] = gFmSweepN;
	gFmSlotOf[id] = s + 1;
	return s;
}

void FmDrop(int s)
{
	const int id = gFmId[s];
	if ((id >= 0) && (id < int(gFmSlotOf.length())))
		gFmSlotOf[id] = 0;
	gFmId[s] = -1;
	gFmFree.insertLast(s);
}

bool FmArmedGround(int d)
{
	return (d > 0) && (d <= Catalog::gDefCount) && Catalog::gMobile[d]
		&& (Catalog::gPower[d] > 1.f) && !Catalog::gFlyer[d];
}

void FoeMemNoteDeath(int d, const AIFloat3& in pos)
{
	if (!FmArmedGround(d))
		return;
	gFmDeadM += Catalog::gCostM[d];
	gFmDeathDef.insertLast(d);
	gFmDeathPos.insertLast(pos);
}

// Where an out-of-sight unit is now: on along its last heading at its own
// speed, held where it was when it stood still.
AIFloat3 FmPredict(int s, float dtOut, float spd)
{
	AIFloat3 p = gFmPos[s];
	const AIFloat3 v = gFmVel[s];
	const float vl = sqrt(v.x * v.x + v.z * v.z);
	if ((vl <= 1.f) || (dtOut <= 0.f))
		return p;
	float step = ((spd > 1.f) ? spd : vl) * dtOut / vl;
	for (int k = 0; k < 6; ++k) {
		const AIFloat3 q(p.x + v.x * step, p.y, p.z + v.z * step);
		if (OnMap(q))
			return q;
		step *= 0.5f;   // walked off the map's edge: it stopped somewhere short of it
	}
	return p;
}

void FoeMemStep()
{
	if (!Builder::gHomeSet)
		return;
	double t0 = ai.ClockUs();
	if (gFmIdx == 0) {
		gFmTotal = aiEnemyMgr.GetEnemyUnitTotal();
		gFmChunk = gFmTotal / 5 + 1;
	}
	const int end = (gFmIdx + gFmChunk < gFmTotal) ? gFmIdx + gFmChunk : gFmTotal;
	for (int i = gFmIdx; i < end; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d > 0) && !FmArmedGround(d))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const int id = aiEnemyMgr.GetEnemyUnitIdAt(i);
		const bool live = (los & 3) != 0;
		int s = ((id >= 0) && (id < int(gFmSlotOf.length()))) ? gFmSlotOf[id] - 1 : -1;
		if ((d == 0) && (s < 0)) {
			// a blip never seen in LOS: an army only once it moves
			if (!live)
				continue;
			const AIFloat3 bv = aiEnemyMgr.GetEnemyUnitVelAt(i);
			if (bv.x * bv.x + bv.z * bv.z <= 1.f)
				continue;
		}
		if (s < 0) {
			s = FmSlot(id);
			if (s < 0)
				continue;
			if (d > 0)
				gFmEverM += Catalog::gCostM[d];
		} else if ((gFmDef[s] == 0) && (d > 0)) {
			gFmEverM += Catalog::gCostM[d];
		}
		if (d > 0)
			gFmDef[s] = d;
		gFmSweep[s] = gFmSweepN;
		gFmGone[s] = false;
		gFmLive[s] = live;
		if (live) {
			gFmPos[s] = aiEnemyMgr.GetEnemyUnitPosAt(i);
			gFmVel[s] = aiEnemyMgr.GetEnemyUnitVelAt(i);
			gFmSeen[s] = ai.frame;
		}
	}
	gFmIdx = end;
	if (gFmIdx >= gFmTotal) {
		FmPublish();
		gFmIdx = 0;
		++gFmSweepN;
	}
	const double us = ai.ClockUs() - t0;
	gFmUs += us;
	if (us > gFmMaxUs)
		gFmMaxUs = us;
	++gFmCalls;
}

void FmPublish()
{
	array<float> live(DG_BINS + 1, 0.f);
	array<float> mem(DG_BINS + 1, 0.f);
	for (uint q = 0; q < 4; ++q) { gFmLiveD[q] = 0.f; gFmMemD[q] = 0.f; }
	float liveS = 0.f, liveM = 0.f, memS = 0.f, memM = 0.f, lostS = 0.f, lostM = 0.f;
	float etaW = 0.f, certW = 0.f, knS = 0.f, knM = 0.f;
	int knN = 0, nLos = 0, nRad = 0, nGh = 0, nGone = 0, nBlip = 0;
	float near = -1.f;
	const float staleS = ai.GetTunable("apex_ghost_stale_min", 15.f) * 60.f;
	AIFloat3 fb = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(fb))
		fb = Front::FoeAnchor();
	const float baseD = OnMap(fb) ? fb.distance2D(Builder::gHomePos) : -1.f;
	float baseRim = OnMap(fb) ? DgRim(fb) : -1.f;
	if (baseRim < 0.f && OnMap(fb))
		baseRim = 0.f;
	const uint n = gFmId.length();
	// Pass 1: who is still held, the deaths seen out of sight, the mean blip.
	for (uint s = 0; s < n; ++s) {
		if (gFmId[s] < 0)
			continue;
		if (gFmSweep[s] != gFmSweepN) {
			// not met this sweep: skipped by a registry shuffle, or unregistered
			const int los = aiEnemyMgr.GetEnemyUnitLos(gFmId[s]);
			if (los >= 0) {
				gFmSweep[s] = gFmSweepN;
				if ((los & (8 | 32 | 64)) != 0) {
					FmDrop(s);
					continue;
				}
			} else if (gFmLive[s]) {
				// left the registry while we were watching it: it died
				FmDrop(s);
				continue;
			} else {
				gFmGone[s] = true;
			}
		}
		const float dtOut = float(ai.frame - gFmSeen[s]) / float(SECOND);
		if (!gFmLive[s] && (dtOut > staleS)) {
			FmDrop(s);
			continue;
		}
		const int d = gFmDef[s];
		if (d > 0) {
			knS += DgStr(d);
			knM += Catalog::gCostM[d];
			++knN;
		}
	}
	// a death we saw takes out the nearest unregistered unit of its def
	for (uint k = 0; k < gFmDeathDef.length(); ++k) {
		int best = -1;
		float bestD = 0.f;
		for (uint s = 0; s < n; ++s) {
			if ((gFmId[s] < 0) || !gFmGone[s] || (gFmDef[s] != gFmDeathDef[k]))
				continue;
			const float dd = gFmDeathPos[k].distance2D(gFmPos[s]);
			if ((best < 0) || (dd < bestD)) {
				best = int(s);
				bestD = dd;
			}
		}
		if (best >= 0)
			FmDrop(best);
	}
	gFmDeathDef.resize(0);
	gFmDeathPos.resize(0);
	const float blipS = (knN > 0) ? knS / float(knN) : 0.f;
	const float blipM = (knN > 0) ? knM / float(knN) : 0.f;
	const float blipSpd = (gDgFoeSpd > 1.f) ? gDgFoeSpd : Market::FoeSpeedCap();
	// Pass 2: bin every held unit by its arrival.
	for (uint s = 0; s < n; ++s) {
		if (gFmId[s] < 0)
			continue;
		const int d = gFmDef[s];
		float str, m, spd, rng;
		if (d > 0) {
			str = DgStr(d);
			m = Catalog::gCostM[d];
			spd = Catalog::gSpeed[d];
			rng = Catalog::gMaxRange[d];
		} else {
			str = blipS;
			m = blipM;
			spd = blipSpd;
			rng = 0.f;
			++nBlip;
		}
		if ((spd <= 1.f) || (str <= 0.f))
			continue;
		if (gFmLive[s]) {
			float gap = DgRim(gFmPos[s]) - rng;
			if (gap < 0.f)
				gap = 0.f;
			const float eta = gap / spd;
			live[DgBin(eta)] += str;
			liveS += str;
			liveM += m;
			if ((near < 0.f) || (eta < near))
				near = eta;
			if (baseD > 0.f) {
				int q = int(4.f * DgRim(gFmPos[s]) / baseD);
				gFmLiveD[(q < 0) ? 0 : ((q > 3) ? 3 : q)] += m;
			}
			continue;
		}
		if (gFmGone[s])
			++nGone;
		else
			++nGh;
		const float dtOut = float(ai.frame - gFmSeen[s]) / float(SECOND);
		float gap0 = DgRim(gFmPos[s]) - rng;
		if (gap0 < 0.f)
			gap0 = 0.f;
		float tw = gap0 / spd;
		if (tw < DG_BIN_S)
			tw = DG_BIN_S;
		const float cert = tw / (tw + ((dtOut > 0.f) ? dtOut : 0.f));
		const AIFloat3 p = FmPredict(s, dtOut, spd);
		float gap = DgRim(p) - rng;
		if (gap < 0.f)
			gap = 0.f;
		const float eta = gap / spd;
		mem[DgBin(eta)] += str * cert;
		memS += str * cert;
		memM += m * cert;
		etaW += eta * str * cert;
		certW += cert * str;
		if (baseD > 0.f) {
			int q = int(4.f * DgRim(p) / baseD);
			gFmMemD[(q < 0) ? 0 : ((q > 3) ? 3 : q)] += m * cert;
		}
		const float lost = str * (1.f - cert);
		if ((lost > 0.f) && (baseRim >= 0.f)) {
			float bg = baseRim - rng;
			if (bg < 0.f)
				bg = 0.f;
			mem[DgBin(bg / spd)] += lost;
			lostS += lost;
			lostM += m * (1.f - cert);
		}
	}
	for (int b = 1; b <= DG_BINS; ++b) {
		live[b] += live[b - 1];
		mem[b] += mem[b - 1];
	}
	gFmLiveBins = live;
	gFmMemBins = mem;
	gFmLiveS = liveS; gFmLiveM = liveM;
	gFmMemS = memS; gFmMemM = memM;
	gFmLostS = lostS; gFmLostM = lostM;
	gFmMemEtaS = (memS > 0.f) ? etaW / memS : -1.f;
	const float outS = memS + lostS;
	gFmMemCert = (outS > 0.f) ? certW / outS : 0.f;
	gFmNearLive = near;
	gFmNGhost = nGh; gFmNGone = nGone; gFmNBlip = nBlip;
	gFmPublishedAt = ai.frame;
	FmCensus();
}

// The instrument: what we hold of their army and where, once a game-minute.
void FmCensus()
{
	if (ai.frame < gFmNextLog)
		return;
	gFmNextLog = ai.frame + 60 * SECOND;
	int nLos = 0, nRad = 0;
	for (uint s = 0; s < gFmId.length(); ++s) {
		if ((gFmId[s] < 0) || !gFmLive[s])
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLos(gFmId[s]);
		if ((los & 1) != 0)
			++nLos;
		else if ((los & 2) != 0)
			++nRad;
	}
	gFmNLos = nLos; gFmNRadar = nRad;
	float raw = 0.f, fresh = 0.f;
	array<int> roles = {int(Unit::Role::ASSAULT.type), int(Unit::Role::RAIDER.type), int(Unit::Role::RIOT.type),
		int(Unit::Role::SKIRM.type), int(Unit::Role::ARTY.type), int(Unit::Role::AH.type)};
	for (uint r = 0; r < roles.length(); ++r) {
		raw += aiEnemyMgr.GetEnemyCost(roles[r]);
		fresh += aiEnemyMgr.GetEnemyCostFresh(roles[r]);
	}
	AiLog(Factory::T() + "apex: foemem t=" + ai.teamId
		+ " los=" + nLos + " radar=" + nRad + " ghost=" + gFmNGhost + " gone=" + gFmNGone
		+ " blip=" + gFmNBlip
		+ " liveM=" + formatFloat(gFmLiveM, "", 0, 0)
		+ " memM=" + formatFloat(gFmMemM, "", 0, 0)
		+ " lostM=" + formatFloat(gFmLostM, "", 0, 0)
		+ " everM=" + formatFloat(gFmEverM, "", 0, 0)
		+ " deadM=" + formatFloat(gFmDeadM, "", 0, 0)
		+ " armyCost=" + formatFloat(EnemyArmyCost(), "", 0, 0)
		+ " raw=" + formatFloat(raw, "", 0, 0) + " fresh=" + formatFloat(fresh, "", 0, 0)
		+ " liveD=" + formatFloat(gFmLiveD[0], "", 0, 0) + "/" + formatFloat(gFmLiveD[1], "", 0, 0)
		+ "/" + formatFloat(gFmLiveD[2], "", 0, 0) + "/" + formatFloat(gFmLiveD[3], "", 0, 0)
		+ " memD=" + formatFloat(gFmMemD[0], "", 0, 0) + "/" + formatFloat(gFmMemD[1], "", 0, 0)
		+ "/" + formatFloat(gFmMemD[2], "", 0, 0) + "/" + formatFloat(gFmMemD[3], "", 0, 0)
		+ " memEta=" + formatFloat(gFmMemEtaS, "", 0, 0)
		+ " cert=" + formatFloat(gFmMemCert, "", 0, 2)
		+ " reg=" + gFmTotal + " slots=" + (gFmId.length() - gFmFree.length())
		+ " us=" + formatFloat((gFmCalls > 0) ? gFmUs / gFmCalls : 0.0, "", 0, 0)
		+ " maxUs=" + formatFloat(gFmMaxUs, "", 0, 0));
	gFmUs = 0.0; gFmCalls = 0; gFmMaxUs = 0.0;
}

// ---- accessors (strength units unless named M; seconds) ----
// Their army in LOS/radar now.
float FoeLiveStr() { return gFmLiveS; }
// Out of sight, at the certainty we still have of where it walked.
float FoeRememberedStr() { return gFmMemS; }
// Out of sight and no longer placed: assumed back at their base.
float FoeLostStr() { return gFmLostS; }
// Strength-weighted seconds for the remembered army to reach our edge; -1 if none.
float FoeRememberedEtaS() { return gFmMemEtaS; }
// 0..1: how sure we are of where the out-of-sight army is.
float FoeMemCertainty() { return gFmMemCert; }
// Believed army, metal: seen, remembered and lost-track together.
float FoeBelievedM() { return gFmLiveM + gFmMemM + gFmLostM; }
bool FoeMemReady() { return gFmPublishedAt >= 0; }
float FoeLiveM() { return gFmLiveM; }
float FoeRememberedM() { return gFmMemM; }
float FoeLostM() { return gFmLostM; }
// Seconds for the nearest SEEN armed enemy ground unit to reach gun range of our edge.
float FoeNearLiveS() { return gFmNearLive; }
float FoeMemCum(bool liveOnly, float horizonS)
{
	if (horizonS < 0.f)
		return 0.f;
	const int b = DgBin(horizonS);
	return liveOnly ? gFmLiveBins[b] : gFmLiveBins[b] + gFmMemBins[b];
}

}  // namespace Military
