namespace Military {

// FLANK GUARDS (his 10-14, docs/24 "Defending the base": raiders go round the
// towers and eat the economy freely). The closure ring's open bearings
// (Market::ClosurePrep: on the map, no ally ahead, no tower reaching) are the
// approaches; the economy behind each one that our guns do not cover against
// the raid we have seen is its stake. A few groups out of the DEFEND pools,
// each on a stock GUARD task around the outermost exposed economy building of
// its sector: one Guard order per unit, the task fights what comes in reach of
// that building and walks back. Sites move only when the sector set does; the
// 09-08 park-order ruling is why nothing here re-issues on a clock.

const int FG_SLICE = 64;   // assets per tick, a cost bound only

float gFgRaidPk = 0.f;
int   gFgRaidAt = -1;

// The armed metal the raid answer saw at a building of ours, as a peak that
// halves like FoeRaidMassM.
float FlankRaidM()
{
	const float hl = ai.GetTunable("apex_seen_halflife", TUNE_SEEN_HALFLIFE);
	if ((gFgRaidAt >= 0) && (hl > 0.f) && (ai.frame > gFgRaidAt))
		gFgRaidPk *= pow(0.5f, (float(ai.frame - gFgRaidAt) / float(SECOND)) / hl);
	gFgRaidAt = ai.frame;
	return gFgRaidPk;
}

void FlankNoteRaid(float foeM)
{
	if (FlankRaidM() < foeM)
		gFgRaidPk = foeM;
}

bool FlankOn()
{
	return ai.GetTunable("apex_flank_guard", TUNE_FLANK_GUARD) > 0.f;
}

bool EcoDef(int d)
{
	return (Catalog::gExtractsM[d] > 0.f) || (Catalog::gMakeE[d] > 0.f)
		|| (Catalog::gConvCapacity[d] > 0.f) || (Catalog::gMakeM[d] > 0.f);
}

void FillF(array<float>& inout a, uint n, float v)
{
	a.resize(n);
	for (uint i = 0; i < n; ++i)
		a[i] = v;
}

void FillI(array<int>& inout a, uint n, int v)
{
	a.resize(n);
	for (uint i = 0; i < n; ++i)
		a[i] = v;
}

void FillB(array<bool>& inout a, uint n, bool v)
{
	a.resize(n);
	for (uint i = 0; i < n; ++i)
		a[i] = v;
}

// The sweep's snapshot: the field, its turret cover and the ring, as they
// stood when it began, so slices over several ticks read one consistent set.
int gFsPhase = 0;
uint gFsCur = 0;
int gFsStamp = -1, gFsTwRev = -1, gFsAt = -999999;
array<AIFloat3> gFsPos;
array<float> gFsW;
array<int> gFsKey;
array<float> gFsCov;
array<bool> gFsExp;
array<bool> gFsOpen;
array<float> gFsRayW;
AIFloat3 gFsMid;
float gFsRing = 0.f, gFsN = 0.f, gFsReach = 400.f, gFsWMean = 1.f;
array<float> gFbU, gFbX, gFbZ, gFbR;
// sectors of the last finished sweep
array<int> gFcMask;
array<float> gFcU, gFcPri, gFcCx, gFcCz;
array<int> gFcVip;
array<AIFloat3> gFcVp;
array<int> gFsRaySec;
array<float> gFcBest;
array<bool> gFcBestS;
int gFcSectors = 0, gFcEligible = 0;
float gFcExposed = 0.f;

// groups
array<int> gFgId;
array<int> gFgVip;
array<AIFloat3> gFgPos;
array<int> gFgMask;
array<IUnitTask@> gFgTask;
array<bool> gFgFoe;
array<float> gFgPri;
array<int> gFgMemId;
array<int> gFgMemSlot;
int gFgNextId = 1;
int gFgOrders = 0, gFgFormed = 0, gFgResite = 0, gFgDisband = 0, gFgShort = 0, gFgEng = 0;
float gFgKilledM = 0.f, gFgLostM = 0.f, gFgLostOpenM = 0.f;
int gFgStatAt = 0, gFgLogAt = 0;

bool IsFlankTask(IUnitTask@ t)
{
	if (t is null)
		return false;
	for (uint i = 0; i < gFgTask.length(); ++i) {
		if (gFgTask[i] is t)
			return true;
	}
	return false;
}

int FlankSlotOf(int uid)
{
	const int m = gFgMemId.find(uid);
	return (m < 0) ? -1 : gFgMemSlot[m];
}

int FlankGroupIdx(int slot)
{
	return gFgId.find(slot);
}

// A member's election: its group's GUARD task, made on the first arrival.
IUnitTask@ FlankTaskFor(CCircuitUnit@ unit)
{
	if (gFgId.length() == 0)
		return null;
	const int g = FlankGroupIdx(FlankSlotOf(int(unit.id)));
	if (g < 0)
		return null;
	if ((gFgTask[g] is null) || gFgTask[g].IsDead()) {
		CCircuitUnit@ vip = ai.GetTeamUnit(Id(gFgVip[g]));
		if (vip is null)
			return null;
		@gFgTask[g] = aiMilitaryMgr.Enqueue(TaskF::Guard(vip));
	}
	if (gFgTask[g] !is null)
		++gFgOrders;
	return gFgTask[g];
}

int FlankRay(const AIFloat3& in p)
{
	const int nb = int(gFsOpen.length());
	if (nb <= 0)
		return -1;
	const float ang = atan2(p.z - gFsMid.z, p.x - gFsMid.x);
	int b = int((ang / 6.2831853f) * float(nb) + 0.5f);
	return ((b % nb) + nb) % nb;
}

bool InFlankSector(const AIFloat3& in p)
{
	if ((gFgId.length() == 0) || (p.distance2D(gFsMid) > gFsRing))
		return false;
	const int b = FlankRay(p);
	if (b < 0)
		return false;
	for (uint g = 0; g < gFgMask.length(); ++g) {
		if ((gFgMask[g] & (1 << b)) != 0)
			return true;
	}
	return false;
}

void FlankNoteLoss(const AIFloat3& in at, int d)
{
	if (!FlankOn() || !Catalog::ValidId(d) || !EcoDef(d))
		return;
	if (InFlankSector(at))
		gFgLostM += Catalog::gCostM[d];
	const int b = FlankRay(at);
	if ((b >= 0) && gFsOpen[b] && (at.distance2D(gFsMid) <= gFsRing))
		gFgLostOpenM += Catalog::gCostM[d];
}

void FlankNoteKill(const AIFloat3& in pos, float m, bool byUs)
{
	if (byUs && FlankOn() && InFlankSector(pos))
		gFgKilledM += m;
}

bool FlankLogOk()
{
	if (ai.frame < gFgLogAt)
		return false;
	gFgLogAt = ai.frame + 5 * SECOND;
	return true;
}

void FlankDropMembers(int slot)
{
	for (int m = int(gFgMemId.length()) - 1; m >= 0; --m) {
		if (gFgMemSlot[m] == slot) {
			gFgMemId.removeAt(m);
			gFgMemSlot.removeAt(m);
		}
	}
}

void FlankDisband(uint g, const string why)
{
	if ((gFgTask[g] !is null) && !gFgTask[g].IsDead())
		gFgTask[g].Abort();
	++gFgDisband;
	if (FlankLogOk())
		AiLog(Factory::T() + "apex: flank disband t=" + ai.teamId + " " + why
			+ " at=" + int(gFgPos[g].x) + "," + int(gFgPos[g].z));
	FlankDropMembers(gFgId[g]);
	gFgId.removeAt(g);
	gFgVip.removeAt(g);
	gFgPos.removeAt(g);
	gFgMask.removeAt(g);
	gFgTask.removeAt(g);
	gFgFoe.removeAt(g);
	gFgPri.removeAt(g);
}

// Members sitting in some other fighter task re-elect into the group.
void FlankRecall(int slot, IUnitTask@ keep)
{
	for (uint m = 0; m < gFgMemId.length(); ++m) {
		if (gFgMemSlot[m] != slot)
			continue;
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gFgMemId[m]));
		if ((u is null) || (u.task is null) || (u.task is keep))
			continue;
		if (u.task.GetType() == Task::Type::FIGHTER)
			u.task.RemoveUnit(u);
	}
}

void FlankStartSweep()
{
	if (!Builder::gHomeSet)
		return;
	const bool changed = (gFsStamp != Market::gPfStamp) || (gFsTwRev != Market::gPfTwRev);
	bool lost = false;
	for (uint g = 0; g < gFgId.length(); ++g)
		lost = lost || (ai.GetTeamUnit(Id(gFgVip[g])) is null);
	// the minute is for raid size and budget drift, which move no stamp
	if (!changed && !lost && (ai.frame - gFsAt < 60 * SECOND))
		return;
	Market::ClosurePrep();
	const uint n = Market::gPfPos.length();
	if (!Market::gClRingOk || (n == 0) || (gPostCovCache.length() != n)
		|| (gPostCovStamp != Market::gPfStamp) || (gPostCovTwRev != Market::gPfTwRev))
		return;
	float wave = FlankRaidM();
	if (wave <= 1.f)
		wave = EnemyCostOf(Unit::Role::RAIDER.type) * Market::AnswerShare();
	if (wave <= 1.f)
		return;
	gFsAt = ai.frame;
	gFsStamp = Market::gPfStamp;
	gFsTwRev = Market::gPfTwRev;
	gFsPos = Market::gPfPos;
	gFsW = Market::gPfWorth;
	gFsKey = Market::gPfKey;
	gFsCov = gPostCovCache;
	gFsOpen = Market::gClRingOpen;
	gFsRayW = Market::gClRingW;
	gFsMid = Market::gClMid;
	gFsRing = Market::gClRingR;
	gFsN = wave;
	gFsReach = (gPostNeedDef > 0) ? PostReach(gPostNeedDef) : 400.f;
	const uint nb = gFsOpen.length();
	gFsWMean = (nb > 0) ? (Market::gClRingWSum / float(nb)) : 1.f;
	if (gFsWMean <= 0.f)
		gFsWMean = 1.f;
	FillB(gFsExp, n, false);
	FillF(gFbU, nb, 0.f);
	FillF(gFbX, nb, 0.f);
	FillF(gFbZ, nb, 0.f);
	FillF(gFbR, nb, 0.f);
	gFsCur = 0;
	gFsPhase = 1;
}

// Exposed economy on open bearings: worth times the share of the raid our
// guns there fail to stop.
void FlankAccumulate()
{
	const uint n = gFsPos.length();
	const uint end = (gFsCur + FG_SLICE < n) ? (gFsCur + FG_SLICE) : n;
	for (uint i = gFsCur; i < end; ++i) {
		const int key = gFsKey[i];
		if (key >= 0) {
			CCircuitUnit@ u = ai.GetTeamUnit(Id(key));
			if ((u is null) || (u.circuitDef is null) || !EcoDef(int(u.circuitDef.id)))
				continue;
		}
		float s = 1.f - gFsCov[i] / gFsN;
		if (s <= 0.f)
			continue;
		if (s > 1.f)
			s = 1.f;
		const int b = FlankRay(gFsPos[i]);
		if ((b < 0) || !gFsOpen[b])
			continue;
		const float e = gFsW[i] * s;
		gFbU[b] += e;
		gFbX[b] += e * gFsPos[i].x;
		gFbZ[b] += e * gFsPos[i].z;
		gFbR[b] += e * gFsPos[i].distance2D(gFsMid);
		gFsExp[i] = true;
	}
	gFsCur = end;
	if (gFsCur < n)
		return;
	FlankSectors();
	gFsCur = 0;
	gFsPhase = 2;
}

// Runs of open bearings, cut to the arc one group spans: twice its reach at
// the exposed economy's mean radius.
void FlankSectors()
{
	const int nb = int(gFsOpen.length());
	gFcMask.resize(0);
	gFcU.resize(0);
	gFcPri.resize(0);
	gFcCx.resize(0);
	gFcCz.resize(0);
	FillI(gFsRaySec, uint(nb), -1);
	float su = 0.f, sr = 0.f;
	for (int b = 0; b < nb; ++b) {
		su += gFbU[b];
		sr += gFbR[b];
	}
	gFcExposed = su;
	gFcSectors = 0;
	gFcEligible = 0;
	if (su <= 0.f)
		return;
	const float rMean = sr / su;
	const float arc = 6.2831853f * ((rMean > 1.f) ? rMean : 1.f) / float(nb);
	int width = int(2.f * gFsReach / arc);
	if (width < 1)
		width = 1;
	int start = 0;
	for (int b = 0; b < nb; ++b) {
		if (!gFsOpen[b] || (gFbU[b] <= 0.f)) {
			start = b;
			break;
		}
	}
	int cur = -1, len = 0;
	float wsum = 0.f;
	for (int k = 0; k < nb; ++k) {
		const int b = (start + k) % nb;
		const bool live = gFsOpen[b] && (gFbU[b] > 0.f);
		if (!live || (len >= width)) {
			if (cur >= 0)
				gFcPri[cur] = gFcU[cur] * (wsum / float(len)) / gFsWMean;
			cur = -1;
			len = 0;
			wsum = 0.f;
		}
		if (!live)
			continue;
		if (cur < 0) {
			cur = int(gFcMask.length());
			gFcMask.insertLast(0);
			gFcU.insertLast(0.f);
			gFcPri.insertLast(0.f);
			gFcCx.insertLast(0.f);
			gFcCz.insertLast(0.f);
		}
		gFcMask[cur] |= (1 << b);
		gFcU[cur] += gFbU[b];
		gFcCx[cur] += gFbX[b];
		gFcCz[cur] += gFbZ[b];
		wsum += (b < int(gFsRayW.length())) ? gFsRayW[b] : 1.f;
		gFsRaySec[b] = cur;
		++len;
	}
	if (cur >= 0)
		gFcPri[cur] = gFcU[cur] * (wsum / float(len)) / gFsWMean;
	const uint ns = gFcMask.length();
	gFcSectors = int(ns);
	FillI(gFcVip, ns, -1);
	gFcVp.resize(ns);
	FillF(gFcBest, ns, -1.f);
	FillB(gFcBestS, ns, false);
	for (uint s = 0; s < ns; ++s) {
		gFcCx[s] /= gFcU[s];
		gFcCz[s] /= gFcU[s];
	}
}

// The post: the outermost exposed economy building within one reach of the
// sector's exposed centre -- a building, not a mex slot, when there is one.
void FlankPickPosts()
{
	const uint n = gFsPos.length();
	const uint end = (gFsCur + FG_SLICE < n) ? (gFsCur + FG_SLICE) : n;
	for (uint i = gFsCur; i < end; ++i) {
		if (!gFsExp[i])
			continue;
		const int b = FlankRay(gFsPos[i]);
		if ((b < 0) || (gFsRaySec[b] < 0))
			continue;
		const uint s = uint(gFsRaySec[b]);
		const AIFloat3 c = AIFloat3(gFcCx[s], 0.f, gFcCz[s]);
		if (gFsPos[i].distance2D(c) > gFsReach)
			continue;
		const bool st = gFsKey[i] >= 0;
		if (gFcBestS[s] && !st)
			continue;
		const float r = gFsPos[i].distance2D(gFsMid);
		if ((st && !gFcBestS[s]) || (r > gFcBest[s])) {
			gFcBest[s] = r;
			gFcBestS[s] = st;
			gFcVip[s] = gFsKey[i];
			gFcVp[s] = gFsPos[i];
		}
	}
	gFsCur = end;
	if (gFsCur >= n)
		gFsPhase = 3;
}

// A mex slot's own building, looked up once when a group is sited on it.
int FlankVipId(int key, const AIFloat3& in at)
{
	if (key >= 0)
		return key;
	array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(at, 64.f);
	for (uint i = 0; (near !is null) && (i < near.length()); ++i) {
		if ((near[i] !is null) && (near[i].circuitDef !is null)
			&& (Catalog::gExtractsM[int(near[i].circuitDef.id)] > 0.f))
			return int(near[i].id);
	}
	return -1;
}

bool FlankForm(uint s, float need)
{
	const int vip = FlankVipId(gFcVip[s], gFcVp[s]);
	if (vip < 0)
		return false;
	const AIFloat3 at = gFcVp[s];
	array<CCircuitUnit@> cu;
	array<IUnitTask@> ct;
	array<float> cd;
	for (uint i = 0; i < gSquads.length(); ++i) {
		IUnitTask@ t = gSquads[i];
		if ((t is null) || t.IsDead() || (t.GetFightType() != int(Task::FightType::DEFEND)))
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		for (uint j = 0; (on !is null) && (j < on.length()); ++j) {
			CCircuitUnit@ u = on[j];
			if (!RaidWorthPulling(u) || IsRollingBomb(u.circuitDef))
				continue;
			const int uid = int(u.id);
			if (RaidClaimed(uid) || AnswerClaimed(uid) || (gFgMemId.find(uid) >= 0))
				continue;
			const float d = u.GetPos(ai.frame).distance2D(at);
			uint k = cd.length();
			while ((k > 0) && (cd[k - 1] > d))
				--k;
			cu.insertAt(k, u);
			ct.insertAt(k, t);
			cd.insertAt(k, d);
		}
	}
	float have = 0.f;
	uint take = 0;
	while ((take < cu.length()) && (have < need)) {
		have += Catalog::gCostM[int(cu[take].circuitDef.id)];
		++take;
	}
	if (have < need) {
		++gFgShort;
		if (FlankLogOk())
			AiLog(Factory::T() + "apex: flank short t=" + ai.teamId + " at=" + int(at.x) + "," + int(at.z)
				+ " need=" + int(need) + " have=" + int(have) + "/" + cu.length());
		return false;
	}
	const int id = gFgNextId++;
	gFgId.insertLast(id);
	gFgVip.insertLast(vip);
	gFgPos.insertLast(at);
	gFgMask.insertLast(gFcMask[s]);
	gFgTask.insertLast(null);
	gFgFoe.insertLast(false);
	gFgPri.insertLast(gFcPri[s]);
	for (uint k = 0; k < take; ++k) {
		gFgMemId.insertLast(int(cu[k].id));
		gFgMemSlot.insertLast(id);
		ct[k].RemoveUnit(cu[k]);
	}
	++gFgFormed;
	if (FlankLogOk())
		AiLog(Factory::T() + "apex: flank form t=" + ai.teamId + " at=" + int(at.x) + "," + int(at.z)
			+ " vip=" + vip + " exposed=" + int(gFcU[s]) + " need=" + int(need)
			+ " m=" + int(have) + " n=" + take + " near=" + int(cd[0]));
	return true;
}

void FlankApply()
{
	gFsPhase = 0;
	const float need = gFsN * ANSWER_PARITY;
	array<uint> el;
	for (uint s = 0; s < gFcMask.length(); ++s) {
		if ((gFcU[s] < need) || (gFcBest[s] < 0.f))
			continue;
		uint k = el.length();
		while ((k > 0) && (gFcPri[el[k - 1]] < gFcPri[s]))
			--k;
		el.insertAt(k, s);
	}
	gFcEligible = int(el.length());
	float raiders = EnemyCostOf(Unit::Role::RAIDER.type) * Market::AnswerShare();
	if (raiders < gFsN)
		raiders = gFsN;
	const int budget = int(raiders / gFsN);
	array<bool> used(gFcMask.length(), false);
	for (int g = int(gFgId.length()) - 1; g >= 0; --g) {
		const uint gi = uint(g);
		const bool vipOk = ai.GetTeamUnit(Id(gFgVip[gi])) !is null;
		int match = -1;
		float bd = 0.f;
		for (uint e = 0; e < el.length(); ++e) {
			const uint s = el[e];
			if (used[s])
				continue;
			const float d = gFcVp[s].distance2D(gFgPos[gi]);
			if ((vipOk && (d > gFsReach)) || ((match >= 0) && (d >= bd)))
				continue;
			match = int(s);
			bd = d;
		}
		if (match < 0) {
			FlankDisband(gi, vipOk ? "covered" : "lost");
			continue;
		}
		used[uint(match)] = true;
		gFgMask[gi] = gFcMask[uint(match)];
		gFgPri[gi] = gFcPri[uint(match)];
		if (vipOk)
			continue;
		const int vip = FlankVipId(gFcVip[uint(match)], gFcVp[uint(match)]);
		if (vip < 0) {
			FlankDisband(gi, "novip");
			continue;
		}
		if ((gFgTask[gi] !is null) && !gFgTask[gi].IsDead())
			gFgTask[gi].Abort();
		@gFgTask[gi] = null;
		gFgVip[gi] = vip;
		gFgPos[gi] = gFcVp[uint(match)];
		FlankRecall(gFgId[gi], null);
		++gFgResite;
		if (FlankLogOk())
			AiLog(Factory::T() + "apex: flank resite t=" + ai.teamId
				+ " at=" + int(gFgPos[gi].x) + "," + int(gFgPos[gi].z) + " d=" + int(bd));
	}
	while (int(gFgId.length()) > budget) {
		uint lo = 0;
		for (uint g = 1; g < gFgId.length(); ++g) {
			if (gFgPri[g] < gFgPri[lo])
				lo = g;
		}
		FlankDisband(lo, "budget");
	}
	for (uint e = 0; (e < el.length()) && (int(gFgId.length()) < budget); ++e) {
		if (used[el[e]])
			continue;
		if (!FlankForm(el[e], need))
			break;
	}
}

// Members gone, empty groups, and the first sighting of armed enemies at a post.
void FlankUpkeep()
{
	for (int m = int(gFgMemId.length()) - 1; m >= 0; --m) {
		if (ai.GetTeamUnit(Id(gFgMemId[m])) is null) {
			gFgMemId.removeAt(m);
			gFgMemSlot.removeAt(m);
		}
	}
	for (int g = int(gFgId.length()) - 1; g >= 0; --g) {
		const uint gi = uint(g);
		if (gFgMemSlot.find(gFgId[gi]) < 0) {
			FlankDisband(gi, "empty");
			continue;
		}
		const bool foe = ai.GetEnemyArmedCostNear(gFgPos[gi], gFsReach) > 0.f;
		if (foe && !gFgFoe[gi])
			++gFgEng;
		gFgFoe[gi] = foe;
	}
}

void UpdateFlankGuard()
{
	if (!FlankOn())
		return;
	FlankUpkeep();
	if (gFsPhase == 0)
		FlankStartSweep();
	else if (gFsPhase == 1)
		FlankAccumulate();
	else if (gFsPhase == 2)
		FlankPickPosts();
	else
		FlankApply();
	if (ai.frame >= gFgStatAt) {
		gFgStatAt = ai.frame + 60 * SECOND;
		float m = 0.f;
		int u = 0;
		for (uint k = 0; k < gFgMemId.length(); ++k) {
			CCircuitUnit@ c = ai.GetTeamUnit(Id(gFgMemId[k]));
			if ((c is null) || (c.circuitDef is null))
				continue;
			m += Catalog::gCostM[int(c.circuitDef.id)];
			++u;
		}
		AiLog(Factory::T() + "apex: flank-stat t=" + ai.teamId + " sectors=" + gFcSectors
			+ " eligible=" + gFcEligible + " groups=" + gFgId.length() + " units=" + u + " metal=" + int(m)
			+ " wave=" + int(gFsN) + " exposed=" + int(gFcExposed) + " reach=" + int(gFsReach)
			+ " orders=" + gFgOrders + " formed=" + gFgFormed + " resite=" + gFgResite
			+ " disband=" + gFgDisband + " short=" + gFgShort + " eng=" + gFgEng
			+ " killedM=" + int(gFgKilledM) + " lostM=" + int(gFgLostM) + " lostOpenM=" + int(gFgLostOpenM));
	}
}

}  // namespace Military
