namespace Military {

// THE ARMY (apex_squads, docs/army.md): owns every ground combat unit from its first election -- held in the idle
// task, out of every C++ task (CCircuitUnit::SetSquadOwned) -- and hands each squad what it wants: guard home, or
// the target it wins at. Needs apex_stock_army underneath so every older layer is already silent.

int gSqOn = -1;
array<int8> gSqDef;
int gSqNextLog = 0;
double gSqUs = 0.0, gSqMaxUs = 0.0;
const double SQ_SLICE_US = 2000.0;

bool SqOn()
{
	if (gSqOn < 0) {
		const bool want = ai.GetTunable("apex_squads", TUNE_SQUADS) > 0.f;
		gSqOn = (want && StockArmy()) ? 1 : 0;
		if (want && !StockArmy())
			AiLog("apex: squad-stat t=" + ai.teamId + " off: apex_squads needs apex_stock_army=1");
	}
	return gSqOn > 0;
}

// ground combat: what stock army control takes, less scouts, fliers, ammunition, ships and guns that cannot hit land
bool SqDef(const CCircuitDef@ cd)
{
	if ((cd is null) || !StockDef(cd))
		return false;
	const int d = int(cd.id);
	if (int(gSqDef.length()) <= d)
		gSqDef.resize(d + 1);
	if (gSqDef[d] == 0) {
		const bool ok = Catalog::ValidId(d) && !Catalog::gFlyer[d] && !Catalog::gKamikaze[d] && !Catalog::gBuilder[d]
			&& Catalog::gHitsLand[d] && (Catalog::gSurfDps[d] > 0.f) && (Catalog::gMaxRange[d] > 0.f)
			&& (!Catalog::gFloater[d] || Catalog::gAmphib[d])
			&& (Catalog::gRole[d] != int(Unit::Role::SCOUT.type));   // main role: pawn/grunt carry "scout" as an attribute
		gSqDef[d] = ok ? 1 : -1;
	}
	return gSqDef[d] > 0;
}

// the election's first line: an owned unit gets no C++ task
bool SqClaim(CCircuitUnit@ unit)
{
	if ((unit is null) || !SqOn() || !SqDef(unit.circuitDef))
		return false;
	if (!unit.IsSquadOwned()) {
		unit.SetSquadOwned(true);
		ArmyAdopt(unit);
	}
	return true;
}

Squad@ SqNew(int state)
{
	Squad@ s = Squad();
	s.id = gSqdNextId++;
	s.state = state;
	s.since = ai.frame;
	gSqd.insertLast(s);
	return s;
}

void ArmyAdopt(CCircuitUnit@ unit)
{
	Squad@ to = null;
	for (uint i = 0; (i < gSqd.length()) && (to is null); ++i) {
		if (gSqd[i].state == SQ_FORMING)
			@to = gSqd[i];
	}
	for (uint i = 0; (i < gSqd.length()) && (to is null); ++i) {
		if (gSqd[i].state == SQ_REGROUP)
			@to = gSqd[i];
	}
	if (to is null)
		@to = SqNew(SQ_FORMING);
	SqJoin(to, unit);
}

void SqForget(CCircuitUnit@ unit)
{
	for (uint i = 0; i < gSqd.length(); ++i) {
		Squad@ s = gSqd[i];
		for (uint k = 0; k < s.u.length(); ++k) {
			if (s.u[k] is unit) {
				++gSqDied[s.state];
				if (s.state == SQ_FALLING)
					++gSqFbLost;
				if (s.epOn)
					s.epLost += Catalog::gCostM[int(unit.circuitDef.id)];
				SqRemoveAt(s, k);
				return;
			}
		}
	}
}

void SqHome(float& out x, float& out z)
{
	AIFloat3 h = aiSetupMgr.GetBasePos();
	if (Builder::gHomeSet)
		h = Builder::gHomePos;
	x = h.x;
	z = h.z;
}

void SqFoeBase(float& out x, float& out z)
{
	AIFloat3 b = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(b))
		b = Front::FoeAnchor();
	x = b.x;
	z = b.z;
}

// the edge of our base facing theirs
void SqRally(float& out x, float& out z)
{
	float hx, hz, bx, bz;
	SqHome(hx, hz);
	SqFoeBase(bx, bz);
	x = hx;
	z = hz;
	const float d = CfDist(hx, hz, bx, bz);
	if ((d <= 1.f) || (bx < 0.f))
		return;
	float e = gBaseExtent;
	if (e > d * 0.5f)
		e = d * 0.5f;
	x = hx + (bx - hx) * e / d;
	z = hz + (bz - hz) * e / d;
}

// their armed unit nearest home among those that can shoot our buildings within one reaction
bool SqHomeThreat(float& out x, float& out z)
{
	float hx, hz;
	SqHome(hx, hz);
	x = hx;
	z = hz;
	float best = -1.f;
	for (uint e = 0; e < gCfEDef.length(); ++e) {
		const int d = gCfEDef[e];
		const float dh = CfDist(gCfEX[e], gCfEZ[e], hx, hz);
		if (dh > gBaseExtent + Catalog::gMaxRange[d] + Catalog::gSpeed[d] * CF_REACT_S)
			continue;
		if ((best < 0.f) || (dh < best)) {
			best = dh;
			x = gCfEX[e];
			z = gCfEZ[e];
		}
	}
	return best >= 0.f;
}

// the target still stands; a moving one is followed
bool SqTargetLive(Squad@ s)
{
	if (s.tKind == SQ_T_HOME) {
		float x, z;
		if (!SqHomeThreat(x, z))
			return false;
		s.tx = x;
		s.tz = z;
		return true;
	}
	if (s.tKind == SQ_T_BASE)
		return CfDist(s.p.x, s.p.z, s.tx, s.tz) > s.p.rng + s.p.spr;
	float best = -1.f, bx = 0.f, bz = 0.f;
	if (s.tKind == SQ_T_ECON) {
		for (uint k = 0; k < gCfXX.length(); ++k) {
			const float d = CfDist(gCfXX[k], gCfXZ[k], s.tx, s.tz);
			if ((best < 0.f) || (d < best)) {
				best = d; bx = gCfXX[k]; bz = gCfXZ[k];
			}
		}
		if ((best < 0.f) || (best > s.p.minRng))
			return false;
	} else if (s.tKind == SQ_T_ARMY) {
		for (uint k = 0; k < gCfEDef.length(); ++k) {
			if (!Catalog::gMobile[gCfEDef[k]])
				continue;
			const float d = CfDist(gCfEX[k], gCfEZ[k], s.tx, s.tz);
			if ((best < 0.f) || (d < best)) {
				best = d; bx = gCfEX[k]; bz = gCfEZ[k];
			}
		}
		if ((best < 0.f) || (best > s.p.rng + gSqEMaxSpd * 2.f))
			return false;
	} else {
		return false;
	}
	s.tx = bx;
	s.tz = bz;
	return true;
}

// The target it wins at, best metal per second of walk first: their economy, a group of their army, then their
// base against the army we remember. Priced a slice per update; the scan resumes where it stopped.
bool SqPickTarget(Squad@ s)
{
	array<float> cx, cz, cv;
	array<int> ck;
	const float spd = (s.p.spd > 1.f) ? s.p.spd : 1.f;
	for (uint k = 0; k < gCfXX.length(); ++k) {
		cx.insertLast(gCfXX[k]); cz.insertLast(gCfXZ[k]); ck.insertLast(SQ_T_ECON);
		cv.insertLast(gCfXM[k] / (CfDist(s.p.x, s.p.z, gCfXX[k], gCfXZ[k]) / spd + 1.f));
	}
	for (uint g = 0; g < gCfFcM.length(); ++g) {
		if (gCfFcN[g] <= 0)
			continue;
		cx.insertLast(gCfFcX[g]); cz.insertLast(gCfFcZ[g]); ck.insertLast(SQ_T_ARMY);
		cv.insertLast(gCfFcM[g] / (CfDist(s.p.x, s.p.z, gCfFcX[g], gCfFcZ[g]) / spd + 1.f));
	}
	const int nC = int(cx.length());
	array<int> ord(nC);
	for (int i = 0; i < nC; ++i)
		ord[i] = i;
	for (int a = 1; a < nC; ++a) {
		const int oi = ord[a];
		int b = a - 1;
		while ((b >= 0) && (cv[ord[b]] < cv[oi])) {
			ord[b + 1] = ord[b];
			--b;
		}
		ord[b + 1] = oi;
	}
	float bx, bz;
	SqFoeBase(bx, bz);
	if ((bx >= 0.f) && (CfDist(s.p.x, s.p.z, bx, bz) > s.p.rng + s.p.spr)) {
		ord.insertLast(nC);
		cx.insertLast(bx); cz.insertLast(bz); ck.insertLast(SQ_T_BASE); cv.insertLast(0.f);
	}
	const double t0 = ai.ClockUs();
	const float gr = SqGatherR(s.p);
	if (s.scanI >= int(ord.length()))
		s.scanI = 0;
	while (s.scanI < int(ord.length())) {
		const int c = ord[s.scanI];
		++s.scanI;
		if (SqAssess(s.p, s.p.x, s.p.z, cx[c], cz[c], ck[c] == SQ_T_BASE, SqPrevAt(s, cx[c], cz[c], gr))) {
			s.tKind = ck[c];
			s.tx = cx[c];
			s.tz = cz[c];
			s.scanI = 0;
			return true;
		}
		if (ai.ClockUs() - t0 > SQ_SLICE_US)
			return false;
	}
	s.scanI = 0;
	return false;
}

// a launch takes the body; members still walking up form the next squad
void SqSplitStragglers(Squad@ s, float r, float cx, float cz)
{
	Squad@ rest = null;
	for (int i = int(s.u.length()) - 1; i >= 0; --i) {
		const AIFloat3 q = s.u[i].GetPos(ai.frame);
		if (CfDist(q.x, q.z, cx, cz) <= r)
			continue;
		if (rest is null)
			@rest = SqNew(SQ_FORMING);
		SqJoin(rest, s.u[i]);
		SqRemoveAt(s, uint(i));
	}
	if (rest !is null)
		AiLog(Factory::T() + "apex: squad t=" + ai.teamId + " id=" + rest.id + " split-from=" + s.id
			+ " n=" + rest.u.length());
}

// forming squads stand at the same rally: the later ones join the first
void SqMergeForming()
{
	Squad@ first = null;
	for (uint i = 0; i < gSqd.length(); ++i) {
		Squad@ s = gSqd[i];
		if (s.state != SQ_FORMING)
			continue;
		if (first is null) {
			@first = s;
			continue;
		}
		const int n = int(s.u.length());
		for (uint k = 0; k < s.u.length(); ++k)
			SqJoin(first, s.u[k]);
		s.u.resize(0); s.ordK.resize(0); s.ordX.resize(0); s.ordZ.resize(0);
		if (n > 0)
			AiLog(Factory::T() + "apex: squad t=" + ai.teamId + " id=" + s.id + " merged-into=" + first.id + " n=" + n);
	}
}

void UpdateSquads()
{
	if (!SqOn())
		return;
	const double t0 = ai.ClockUs();
	SqAssessRead();
	SqMergeForming();
	for (uint i = 0; i < gSqd.length(); ++i)
		SqUpdate(gSqd[i]);
	for (int i = int(gSqd.length()) - 1; i >= 0; --i) {
		if (gSqd[i].u.length() == 0) {
			if (gSqd[i].epOn)
				SqEpClose(gSqd[i]);
			gSqd.removeAt(uint(i));
		}
	}
	const double us = ai.ClockUs() - t0;
	gSqUs += us;
	if (us > gSqMaxUs)
		gSqMaxUs = us;
	SqStat();
}

void SqStat()
{
	if (ai.frame < gSqNextLog)
		return;
	gSqNextLog = ai.frame + 60 * SECOND;
	array<int> by(5, 0);
	int owned = 0;
	for (uint i = 0; i < gSqd.length(); ++i) {
		++by[gSqd[i].state];
		owned += int(gSqd[i].u.length());
	}
	string st, died;
	for (uint k = 0; k < SQ_NAME.length(); ++k) {
		st += " " + SQ_NAME[k] + "=" + by[k];
		died += ((k == 0) ? "" : " ") + SQ_NAME[k] + "=" + gSqDied[k];
		gSqDied[k] = 0;
	}
	AiLog(Factory::T() + "apex: squad-stat t=" + ai.teamId + " squads=" + gSqd.length() + st + " owned=" + owned
		+ " trans=" + gSqTrans + " launch=" + gSqLaunch + " home=" + gSqHome + " fb=" + gSqFb
		+ " fbWhole=" + gSqFbWhole + " fbKept=" + gSqFbKept + " fbLost=" + gSqFbLost + " died=[" + died + "]"
		+ " refused=" + gSqRefused + " waitGrew=" + gSqWaitGrew + " fights=" + gSqEpN + " cal=" + int(gCfCalT[0])
		+ " orders=" + gSqOrders + " us=" + int(gSqUs) + " maxUs=" + int(gSqMaxUs));
	gSqTrans = 0; gSqLaunch = 0; gSqHome = 0; gSqFb = 0; gSqFbWhole = 0; gSqFbKept = 0; gSqFbLost = 0;
	gSqRefused = 0; gSqOrders = 0; gSqUs = 0.0; gSqMaxUs = 0.0; gSqEpN = 0; gSqWaitGrew = 0;
}

}  // namespace Military
