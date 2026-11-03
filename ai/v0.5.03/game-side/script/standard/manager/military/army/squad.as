namespace Military {

// A SQUAD (docs/army.md): the army hands it an intent, it decides how on its own update. Its states, each change
// logged with its reason as `apex: squad`:
//   forming -> moving -> engaged -> {winning: continue | losing: falling_back} -> regrouping -> forming
// Members join only while it forms or regroups (SqJoin). SqIssue is the one place an owned unit gets an order.

const int SQ_FORMING = 0;
const int SQ_MOVING = 1;
const int SQ_ENGAGED = 2;
const int SQ_FALLING = 3;
const int SQ_REGROUP = 4;
const array<string> SQ_NAME = {"forming", "moving", "engaged", "falling_back", "regrouping"};

// what the army asked for
const int SQ_T_NONE = 0;
const int SQ_T_ECON = 1;     // their economy: extractors and constructors
const int SQ_T_ARMY = 2;     // a group of their army it beats
const int SQ_T_BASE = 3;     // their base, nothing better known
const int SQ_T_HOME = 4;     // an enemy at our buildings
const array<string> SQ_TNAME = {"none", "econ", "army", "base", "home"};

const int SQ_O_NONE = 0;
const int SQ_O_MOVE = 1;
const int SQ_O_FIGHT = 2;
const int SQ_O_STOP = 3;

class Squad {
	int id = 0;
	int state = SQ_FORMING;
	int since = 0;
	array<CCircuitUnit@> u;
	array<int> ordK;
	array<float> ordX, ordZ;
	int tKind = SQ_T_NONE;
	float tx = 0.f, tz = 0.f;
	float failX = -1.f, failZ = -1.f;   // the place it last fell back from
	int fbN0 = 0;                       // members when that fall back began
	int scanI = 0;                      // target search, resumed across updates
	int lastJoin = -1;
	// the fight it is in, for calibration: predicted (raw) and real metal lost and killed
	bool epOn = false;
	float epPL = 0.f, epPK = 0.f, epLost = 0.f, epKill = 0.f;
	SqPool p;
}

array<Squad@> gSqd;
int gSqdNextId = 1;

// per-minute counters
int gSqTrans = 0, gSqFb = 0, gSqFbWhole = 0, gSqFbKept = 0, gSqFbLost = 0, gSqLaunch = 0, gSqHome = 0;
int gSqRefused = 0, gSqOrders = 0, gSqEpN = 0, gSqWaitGrew = 0;
int gSqAN = 0, gSqAN0 = 0;   // estimates made, and the count when this squad's update began
array<int> gSqDied(5, 0);

bool SqOpen(const Squad@ s)
{
	return (s.state == SQ_FORMING) || (s.state == SQ_REGROUP);
}

// the join window: open while it forms or regroups, closed from launch until it is back
bool SqJoin(Squad@ s, CCircuitUnit@ un)
{
	if ((s is null) || (un is null))
		return false;
	if (!SqOpen(s)) {
		++gSqRefused;
		JwRefused(Task::FightType::ATTACK, 1);
		return false;
	}
	s.u.insertLast(un);
	s.lastJoin = ai.frame;
	s.ordK.insertLast(SQ_O_NONE);
	s.ordX.insertLast(0.f);
	s.ordZ.insertLast(0.f);
	return true;
}

void SqRemoveAt(Squad@ s, uint i)
{
	s.u.removeAt(i);
	s.ordK.removeAt(i);
	s.ordX.removeAt(i);
	s.ordZ.removeAt(i);
}

void SqClampToMap(float x, float z, float &out ox, float &out oz)
{
	const float w = float(AiTerrainWidth()) - 8.f, h = float(AiTerrainHeight()) - 8.f;
	ox = (x < 8.f) ? 8.f : ((x > w) ? w : x);
	oz = (z < 8.f) ? 8.f : ((z > h) ? h : z);
}

// THE ONE ORDER PATH. The C++ bindings refuse an order to a squad-owned unit unless this window is open, and count
// the refusal as a leak (stockarmy-stat). A ledger keeps it from re-sending what the unit already has (S13).
void SqIssue(Squad@ s, uint i, int kind, float x, float z)
{
	CCircuitUnit@ un = s.u[i];
	if (un is null)
		return;
	const int d = int(un.circuitDef.id);
	if (s.ordK[i] == kind) {
		if (kind == SQ_O_STOP)
			return;
		if (CfDist(s.ordX[i], s.ordZ[i], x, z) <= 0.5f * Catalog::gLandRange[d])
			return;
	}
	SqClampToMap(x, z, x, z);
	s.ordK[i] = kind;
	s.ordX[i] = x;
	s.ordZ[i] = z;
	++gSqOrders;
	AIFloat3 at(x, 0.f, z);
	ai.SetSquadOrders(true);
	if (kind == SQ_O_MOVE)
		un.CmdMoveTo(at);
	else if (kind == SQ_O_FIGHT)
		un.CmdFightTo(at);
	else if (kind == SQ_O_STOP)
		un.CmdStop();
	ai.SetSquadOrders(false);
}

void SqAll(Squad@ s, int kind, float x, float z)
{
	for (uint i = 0; i < s.u.length(); ++i)
		SqIssue(s, i, kind, x, z);
}

// pool over the members, or over those within r of (cx, cz) when r > 0
void SqRead(Squad@ s, float r, float cx, float cz)
{
	SqPool@ p = s.p;
	p.n = 0.f; p.dps = 0.f; p.hp = 0.f; p.m = 0.f; p.spr = 0.f; p.rng = 0.f; p.minRng = 1e9f; p.spd = 1e9f;
	p.foot = 0.f;
	float sx = 0.f, sz = 0.f;
	array<float> xs, zs;
	for (uint i = 0; i < s.u.length(); ++i) {
		CCircuitUnit@ un = s.u[i];
		if (un is null)
			continue;
		const AIFloat3 q = un.GetPos(ai.frame);
		if ((r > 0.f) && (CfDist(q.x, q.z, cx, cz) > r))
			continue;
		const int d = int(un.circuitDef.id);
		xs.insertLast(q.x);
		zs.insertLast(q.z);
		sx += q.x;
		sz += q.z;
		p.n += 1.f;
		p.dps += Catalog::gSurfDps[d];
		p.hp += Catalog::gHealth[d] * un.GetHealthPercent();
		p.m += Catalog::gCostM[d];
		const float rg = Catalog::gLandRange[d];
		if (rg > p.rng) p.rng = rg;
		if (rg < p.minRng) p.minRng = rg;
		if (Catalog::gSpeed[d] < p.spd) p.spd = Catalog::gSpeed[d];
		const float f = 16.f * float((Catalog::gFootX[d] > Catalog::gFootZ[d]) ? Catalog::gFootX[d] : Catalog::gFootZ[d]);
		p.foot += f;
	}
	if (p.n <= 0.f) {
		p.minRng = 0.f;
		p.spd = 0.f;
		return;
	}
	p.x = sx / p.n;
	p.z = sz / p.n;
	p.foot /= p.n;
	for (uint k = 0; k < xs.length(); ++k) {
		const float dd = CfDist(xs[k], zs[k], p.x, p.z);
		if (dd > p.spr)
			p.spr = dd;
	}
}

// how far from the middle a member still fights with the body: the body's packed radius and its shortest gun
float SqGatherR(const SqPool@ p)
{
	return p.foot * sqrt((p.n > 1.f) ? p.n : 1.f) + p.minRng;
}

void SqTo(Squad@ s, int to, const string &in why)
{
	const int from = s.state;
	if (to == SQ_FALLING) {
		++gSqFb;
		s.fbN0 = int(s.u.length());
		s.failX = s.tx;
		s.failZ = s.tz;
	}
	if ((from == SQ_FALLING) && (to != SQ_FALLING) && (to != SQ_ENGAGED)) {
		gSqFbKept += int(s.u.length());
		if (int(s.u.length()) >= s.fbN0)
			++gSqFbWhole;
	}
	if ((from == SQ_FORMING) && (to == SQ_MOVING)) {
		if (s.tKind == SQ_T_HOME)
			++gSqHome;
		else
			++gSqLaunch;
	}
	const bool fight = (to == SQ_ENGAGED) || (to == SQ_FALLING);
	if (s.epOn && !fight)
		SqEpClose(s);
	if (!s.epOn && fight) {
		s.epOn = true;
		const bool assessed = gSqAN != gSqAN0;
		s.epPL = assessed ? gSqAL : 0.f;
		s.epPK = assessed ? gSqAK : 0.f;
		s.epLost = 0.f;
		s.epKill = 0.f;
	}
	s.state = to;
	s.since = ai.frame;
	s.scanI = 0;
	++gSqTrans;
	AiLog(Factory::T() + "apex: squad t=" + ai.teamId + " id=" + s.id + " " + SQ_NAME[from] + "->" + SQ_NAME[to]
		+ " why=" + why + " n=" + s.u.length() + " m=" + int(s.p.m) + " target=" + SQ_TNAME[s.tKind]
		+ "@" + int(s.tx) + "," + int(s.tz) + " X=" + int(gSqAX) + " band=" + int(gSqABand)
		+ " them=" + int(gSqAThemM) + "/" + gSqAThemN + " at=" + int(s.p.x) + "," + int(s.p.z));
	if (gSqAN != gSqAN0)
		AiLog(Factory::T() + SqAssessLine(s.p) + " id=" + s.id);
}

// a fight over: what the paper said against what it cost, into comfight's calibration (the band's measure)
void SqEpClose(Squad@ s)
{
	s.epOn = false;
	if ((s.epPL + s.epPK) <= 0.f)
		return;   // no fight on paper (a raid on structures): nothing to calibrate
	CfCalAdd(s.epPL, s.epLost, s.epPK, s.epKill);
	++gSqEpN;
	AiLog(Factory::T() + "apex: squad-fight t=" + ai.teamId + " id=" + s.id + " predL=" + int(s.epPL) + " lost="
		+ int(s.epLost) + " predK=" + int(s.epPK) + " killed=" + int(s.epKill));
}

// their unit killed near a squad in a fight
void SqNoteEnemyDeath(const CCircuitDef@ edef, const AIFloat3& in pos, bool byUs)
{
	if (!byUs || (edef is null) || (gSqOn <= 0))
		return;
	for (uint i = 0; i < gSqd.length(); ++i) {
		Squad@ s = gSqd[i];
		if (s.epOn && (CfDist(s.p.x, s.p.z, pos.x, pos.z) <= s.p.rng + s.p.spr)) {
			s.epKill += edef.costM;
			return;
		}
	}
}

// (x, z) is where it fell back from: going there again needs the estimate past its band
int SqPrevAt(const Squad@ s, float x, float z, float r)
{
	if ((s.failX >= 0.f) && (CfDist(s.failX, s.failZ, x, z) <= r))
		return CF_FALL;
	return 0;
}

// gather on the middle when spread past the body's radius, else walk on to (x, z)
void SqAdvance(Squad@ s, float x, float z)
{
	const float gr = SqGatherR(s.p);
	if (s.p.spr <= gr) {
		SqAll(s, SQ_O_MOVE, x, z);
		return;
	}
	for (uint i = 0; i < s.u.length(); ++i) {
		const AIFloat3 q = s.u[i].GetPos(ai.frame);
		if (CfDist(q.x, q.z, s.p.x, s.p.z) > gr)
			SqIssue(s, i, SQ_O_MOVE, s.p.x, s.p.z);
		else
			SqIssue(s, i, SQ_O_STOP, q.x, q.z);
	}
}

void SqGatherAt(Squad@ s, float x, float z)
{
	const float gr = SqGatherR(s.p);
	for (uint i = 0; i < s.u.length(); ++i) {
		const AIFloat3 q = s.u[i].GetPos(ai.frame);
		if (CfDist(q.x, q.z, x, z) > gr)
			SqIssue(s, i, SQ_O_MOVE, x, z);
	}
}

bool SqGathered(Squad@ s, float x, float z)
{
	const float gr = SqGatherR(s.p);
	for (uint i = 0; i < s.u.length(); ++i) {
		const AIFloat3 q = s.u[i].GetPos(ai.frame);
		if (CfDist(q.x, q.z, x, z) > gr)
			return false;
	}
	return true;
}

// ---- the update, one per state ----

void SqUpdateForming(Squad@ s)
{
	float rx, rz;
	SqRally(rx, rz);
	float hx, hz;
	if (SqHomeThreat(hx, hz)) {
		s.tKind = SQ_T_HOME;
		s.tx = hx;
		s.tz = hz;
		if (SqAssess(s.p, s.p.x, s.p.z, hx, hz, false, SqPrevAt(s, hx, hz, SqGatherR(s.p)))) {
			SqTo(s, SQ_MOVING, "guard-home");
			return;
		}
		SqGatherAt(s, rx, rz);
		return;
	}
	// a squad that grew since the last update waits one: a batch claimed over several frames launches as one
	if (ai.frame - s.lastJoin < SECOND) {
		++gSqWaitGrew;
		SqGatherAt(s, rx, rz);
		return;
	}
	// launch with the body: members within its radius of the middle; the rest form the next squad
	SqPool all = s.p;
	const float gr = SqGatherR(all);
	SqRead(s, gr, all.x, all.z);
	if ((s.p.n > 0.f) && SqPickTarget(s)) {
		SqSplitStragglers(s, gr, all.x, all.z);
		SqTo(s, SQ_MOVING, "launch");
		return;
	}
	s.p = all;
	SqGatherAt(s, rx, rz);
}

void SqUpdateMoving(Squad@ s)
{
	array<int> foe;
	SqFoesIn(s.p, foe);
	if (foe.length() > 0) {
		const bool win = SqAssess(s.p, s.p.x, s.p.z, s.p.x, s.p.z, false, 0);
		SqTo(s, win ? SQ_ENGAGED : SQ_FALLING, win ? "contact-wins" : "contact-loses");
		return;
	}
	if (!SqTargetLive(s)) {
		if (s.tKind == SQ_T_HOME) {
			SqTo(s, SQ_REGROUP, "home-clear");
			return;
		}
		if (!SqPickTarget(s)) {
			SqTo(s, SQ_REGROUP, "no-target-it-wins");
			return;
		}
		SqTo(s, SQ_MOVING, "retarget");
	}
	if ((s.tKind == SQ_T_ECON) && (CfDist(s.p.x, s.p.z, s.tx, s.tz) <= s.p.rng + s.p.spr)) {
		SqTo(s, SQ_ENGAGED, "at-target");
		return;
	}
	SqAdvance(s, s.tx, s.tz);
}

void SqUpdateEngaged(Squad@ s)
{
	array<int> foe;
	SqFoesIn(s.p, foe);
	if (foe.length() == 0) {
		if ((s.tKind == SQ_T_ECON) && SqTargetLive(s)) {
			SqAll(s, SQ_O_FIGHT, s.tx, s.tz);
			return;
		}
		SqTo(s, SQ_MOVING, "fight-over");
		if (!SqTargetLive(s) && (s.tKind != SQ_T_HOME) && !SqPickTarget(s))
			SqTo(s, SQ_REGROUP, "no-target-it-wins");
		return;
	}
	if (!SqAssess(s.p, s.p.x, s.p.z, s.p.x, s.p.z, false, CF_ENGAGE)) {
		SqTo(s, SQ_FALLING, "losing");
		return;
	}
	float fx, fz;
	CfNearestFoe(foe, s.p.x, s.p.z, fx, fz);
	SqAll(s, SQ_O_FIGHT, fx, fz);
}

void SqUpdateFalling(Squad@ s)
{
	float rx, rz;
	SqRally(rx, rz);
	array<int> foe;
	SqFoesIn(s.p, foe);
	if (foe.length() == 0) {
		SqTo(s, SQ_REGROUP, "out-of-reach");
		return;
	}
	if (SqAssess(s.p, s.p.x, s.p.z, s.p.x, s.p.z, false, CF_FALL)) {
		SqTo(s, SQ_ENGAGED, "turns-wins-here");
		return;
	}
	SqAll(s, SQ_O_MOVE, rx, rz);
}

void SqUpdateRegroup(Squad@ s)
{
	float rx, rz;
	SqRally(rx, rz);
	if (SqGathered(s, rx, rz)) {
		SqTo(s, SQ_FORMING, "gathered");
		return;
	}
	SqGatherAt(s, rx, rz);
}

void SqUpdate(Squad@ s)
{
	SqRead(s, 0.f, 0.f, 0.f);
	if (s.p.n <= 0.f)
		return;
	gSqAN0 = gSqAN;
	if (s.state == SQ_FORMING)
		SqUpdateForming(s);
	else if (s.state == SQ_MOVING)
		SqUpdateMoving(s);
	else if (s.state == SQ_ENGAGED)
		SqUpdateEngaged(s);
	else if (s.state == SQ_FALLING)
		SqUpdateFalling(s);
	else
		SqUpdateRegroup(s);
}

}  // namespace Military
