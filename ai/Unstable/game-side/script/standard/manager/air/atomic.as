namespace Air {

// THE ATOMIC BOMBER IS A STRIKE BY ITSELF (apexearth 2026-09-20, docs/24): its
// bomb takes the cell alone, so it waits for no mass. A scout flies the route
// first -- where the AA is not is the question the run is priced on -- then
// the plane goes when the cell pays for one plane's risk, hunts inside it
// under the stock bomb task, and comes home when staying no longer pays.
// While no cell pays it holds with the wing and goes out in the wave.
int gAtomId = -1;          // the plane on a run, -1: none
int gAtomLeg = 0;          // 0 to the waypoint, 1 to the cell, 2 hunting, 3 home
AIFloat3 gAtomAt, gAtomWay;
float gAtomPrize0 = 0.f;
int gAtomSince = 0;
int gAtomNextWatch = 0;
int gAtomNextLog = 0;
int gAtomFlown = 0;

// The look the run launches on: a scout over the same route and cell.
bool gAtomLookWant = false;
AIFloat3 gAtomLookCellWant;
int gAtomLookId = -1;
int gAtomLookDef = -1;
int gAtomLookLeg = 1;
AIFloat3 gAtomLookWay, gAtomLookCell;
int gAtomLookAt = -1;      // frame the last atomic look landed, -1: never
AIFloat3 gAtomLookSeen;    // the cell it landed on
int gAtomLookSince = 0;
int gAtomScoutFlown = 0;
int gAtomScoutLanded = 0;
// What runs have actually killed: the model's share is replaced by the
// measured one as runs are scored, the way the wing's ObsDmg replaces its prior.
float gAtomKilledSum = 0.f;
float gAtomPrizeSum = 0.f;

// The share of a cell's prize a run is expected to take: the model's p before
// any run, the measured share once runs have been scored, with the model
// weighing as one more run of this cell.
float AtomicKillShare(float prize, float p)
{
	if (prize <= 0.f)
		return 0.f;
	return (gAtomKilledSum + p * prize) / (gAtomPrizeSum + prize);
}

bool IsAtomicDef(int d) { return (gBomberN !is null) && (int(gBomberN.id) == d); }

CCircuitUnit@ AtomicById(int id)
{
	if ((gBomberN is null) || (id < 0))
		return null;
	array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(gBomberN, Builder::gHomePos, 0.f);
	if (us is null)
		return null;
	for (uint i = 0; i < us.length(); ++i)
		if ((us[i] !is null) && (int(us[i].id) == id))
			return us[i];
	return null;
}

CCircuitUnit@ AtomicScoutById(int id)
{
	if ((gAtomLookDef <= 0) || (id < 0))
		return null;
	array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(gAtomLookDef),
			Builder::gHomePos, 0.f);
	if (us is null)
		return null;
	for (uint i = 0; i < us.length(); ++i)
		if ((us[i] !is null) && (int(us[i].id) == id))
			return us[i];
	return null;
}

// The AA over a cell is the worst of five reads across it, not the centre:
// a flak 700 elmos off the centre read 0.1 there and killed the plane.
float CellAA(CCircuitUnit@ probe, const AIFloat3& in at, float r)
{
	if (probe is null)
		return 0.f;
	float worst = ai.GetUnitThreatAt(probe, at);
	const float h = r * 0.5f;
	for (int i = 0; i < 4; ++i) {
		const AIFloat3 p = at + AIFloat3(((i & 1) == 0) ? h : -h, 0.f,
				((i & 2) == 0) ? h : -h);
		if (!OnMap(p))
			continue;
		const float t = ai.GetUnitThreatAt(probe, p);
		if (t > worst)
			worst = t;
	}
	return worst;
}

// The share of atomic looks that landed, measured on this game's own flights:
// what a scout dying on the route says about the plane's odds there.
float AtomicScoutDelivery()
{
	return float(gAtomScoutLanded + 1) / float(gAtomScoutFlown + 1);
}

// The chance one plane reaches the cell and stays over it: what health it has
// left against the AA on the cell and along the approach, in the wing's soak
// units. RouteThreat sums six samples a leg; /6 makes a leg one cell's worth.
float AtomicThrough(CCircuitUnit@ u, float cellAA, float route)
{
	const float s = Catalog::gHealth[int(u.circuitDef.id)]
			* u.GetHealthPercent()
			* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
	if (s <= 0.f)
		return 0.f;
	return s / (s + cellAA + route / 6.f) * AtomicScoutDelivery();
}

float AtomicRoute(CCircuitUnit@ u, const AIFloat3& in cell, const AIFloat3& in way)
{
	const AIFloat3 orig = u.GetPos(ai.frame);
	if (way.distance2D(cell) < 1.f)
		return RouteThreat(u, orig, cell);
	return RouteThreat(u, orig, way) + RouteThreat(u, way, cell);
}

bool AtomicLookFresh(const AIFloat3& in cell)
{
	if ((gAtomLookAt < 0) || (gAtomLookSeen.distance2D(cell) > 1.f))
		return false;
	const float horizon = ai.GetTunable("apex_ghost_stale_min", 15.f) * float(MINUTE);
	return float(ai.frame - gAtomLookAt) < horizon;
}

CCircuitUnit@ AnyAircraft()
{
	CCircuitUnit@ b = AnyBomber();
	if (b !is null)
		return b;
	for (int i = 4; i < 6; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k)
			if (us[k] !is null)
				return us[k];
	}
	return null;
}

// The draw's price for the atomic bomber: its own run on the current picture,
// not a share of the wing's soak (which never reached its bar: 2300 hp of
// soak against a 3,300 bill read wing0 all game). One at a time.
float AtomicGainFor(float fillSec)
{
	if ((gBomberN is null) || !gAtomCellHas || !Builder::gHomeSet)
		return 0.f;
	const int d = int(gBomberN.id);
	if ((Have(gBomberN) > 0) || (Brain::PendAnyOf(d) > 0))
		return 0.f;
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	CCircuitUnit@ probe = AnyAircraft();
	float cellAA = 0.f, route = 0.f;
	if (probe !is null) {
		cellAA = CellAA(probe, gAtomCellAt, r);
		route = AtomicRoute(probe, gAtomCellAt, LookRoute(probe, gAtomCellAt));
	}
	const float s = Catalog::gHealth[d]
			* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
	if (s <= 0.f)
		return 0.f;
	const float p = s / (s + cellAA + route / 6.f) * AtomicScoutDelivery();
	const float gain = gAtomCellPrize * AtomicKillShare(gAtomCellPrize, p);
	if (gain < Catalog::gCostM[d] * ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF))
		return 0.f;
	return gain / ((fillSec > 1.f) ? fillSec : 180.f);
}

// HoldsUnit for an atomic bomber. True: held by this run or with the wing;
// false: the stock bomb task's, inside the published focus.
bool AtomicHold(CCircuitUnit@ unit)
{
	const int id = int(unit.id);
	if (gAtomId == id)
		return gAtomLeg != 2;
	if ((gAtomId >= 0) || gStrike || !gAtomCellHas || !Builder::gHomeSet)
		return true;
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	const AIFloat3 way = LookRoute(unit, gAtomCellAt);
	const float route = AtomicRoute(unit, gAtomCellAt, way);
	const float cellAA = CellAA(unit, gAtomCellAt, r);
	const float p = AtomicThrough(unit, cellAA, route);
	const float need = Catalog::gCostM[int(unit.circuitDef.id)]
			* ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF);
	const float q = AtomicKillShare(gAtomCellPrize, p);
	const bool pays = gAtomCellPrize * q >= need;
	const bool fresh = AtomicLookFresh(gAtomCellAt);
	if (pays && !fresh) {
		gAtomLookWant = true;
		gAtomLookCellWant = gAtomCellAt;
	}
	if (!pays || !fresh) {
		if (ai.frame >= gAtomNextLog) {
			gAtomNextLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: air atomic " + (pays ? "waits for the look" : "holding")
				+ " #" + id
				+ " cell=" + int(gAtomCellAt.x) + "," + int(gAtomCellAt.z)
				+ " prize=" + int(gAtomCellPrize)
				+ " cellAA=" + formatFloat(cellAA, "", 0, 1)
				+ " route=" + formatFloat(route / 6.f, "", 0, 1)
				+ " scouts=" + gAtomScoutLanded + "/" + gAtomScoutFlown
				+ " p=" + formatFloat(p, "", 0, 2)
				+ " q=" + formatFloat(q, "", 0, 2)
				+ " worth=" + int(gAtomCellPrize * q) + "/" + int(need)
				+ " look=" + ((gAtomLookId >= 0) ? "flying" : (fresh ? "fresh" : "none")));
		}
		return true;
	}
	gAtomId = id;
	gAtomAt = gAtomCellAt;
	gAtomWay = way;
	gAtomPrize0 = gAtomCellPrize;
	gAtomSince = ai.frame;
	gAtomLeg = (way.distance2D(gAtomCellAt) < 1.f) ? 1 : 0;
	gAtomNextWatch = 0;
	++gAtomFlown;
	unit.CmdMoveTo((gAtomLeg == 0) ? way : gAtomCellAt);
	Cover(unit, gAtomCellAt, "atomic");
	AiLog(Factory::T() + "apex: air atomic #" + id + " -> "
		+ int(gAtomCellAt.x) + "," + int(gAtomCellAt.z)
		+ ((gAtomLeg == 0) ? (" via " + int(way.x) + "," + int(way.z)) : " direct")
		+ " prize=" + int(gAtomCellPrize)
		+ " cellAA=" + formatFloat(cellAA, "", 0, 1)
		+ " route=" + formatFloat(route / 6.f, "", 0, 1)
		+ " scouts=" + gAtomScoutLanded + "/" + gAtomScoutFlown
		+ " p=" + formatFloat(p, "", 0, 2)
		+ " q=" + formatFloat(q, "", 0, 2)
		+ " worth=" + int(gAtomCellPrize * q) + "/" + int(need)
		+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0)
		+ " looked=" + ((ai.frame - gAtomLookAt) / SECOND) + "s ago"
		+ " flown=" + gAtomFlown);
	return true;
}

void AtomicOver(const string& in why, float left)
{
	const float killed = gAtomPrize0 - left;
	gAtomKilledSum += (killed > 0.f) ? killed : 0.f;
	gAtomPrizeSum += gAtomPrize0;
	AiLog(Factory::T() + "apex: air atomic run over -- " + why + " #" + gAtomId
		+ " killed=" + int(gAtomPrize0 - left) + "/" + int(gAtomPrize0)
		+ " in " + ((ai.frame - gAtomSince) / SECOND) + "s leg=" + gAtomLeg
		+ " share=" + formatFloat(gAtomKilledSum / gAtomPrizeSum, "", 0, 2)
		+ " over " + gAtomFlown + " runs");
	if (!gStrike && (gAtomLeg >= 2))
		ai.PublishTeamValue("strike_r", 0.f);
	CoverRelease(Id(gAtomId), "atomic " + why);
	gAtomId = -1;
	gAtomLeg = 0;
}

void AtomicWatch()
{
	if ((gAtomId < 0) || (ai.frame < gAtomNextWatch))
		return;
	gAtomNextWatch = ai.frame + 2 * SECOND;
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	const float left = aiEnemyMgr.GetEnemyStructCostAt(gAtomAt, r);
	CCircuitUnit@ u = AtomicById(gAtomId);
	if (u is null) {
		AtomicOver("lost", left);
		return;
	}
	if (gStrike && InWave(u.id)) {
		AtomicOver("joined the wave", left);
		return;
	}
	// Home defence takes every bomber (HoldsUnit, before this run is asked):
	// the plane is stock's now, and the run is over with it.
	if (gDefendHome) {
		AtomicOver("base contested", left);
		return;
	}
	const AIFloat3 at = u.GetPos(ai.frame);
	if (gAtomLeg == 0) {
		if (at.distance2D(gAtomWay) < 300.f) {
			gAtomLeg = 1;
			u.CmdMoveTo(gAtomAt);
		} else if (u.CmdQueueSize() == 0) {
			u.CmdMoveTo(gAtomWay);
		}
		return;
	}
	if (gAtomLeg == 1) {
		if (at.distance2D(gAtomAt) > Catalog::gLosR[int(u.circuitDef.id)]) {
			if (u.CmdQueueSize() == 0)
				u.CmdMoveTo(gAtomAt);
			return;
		}
		gAtomLeg = 2;
		// The idle pass re-elects it into the bomb task within seconds; the
		// focus keeps that task inside the cell, as it does the wing's.
		if (!gStrike) {
			ai.PublishTeamValue("strike_x", gAtomAt.x);
			ai.PublishTeamValue("strike_z", gAtomAt.z);
			ai.PublishTeamValue("strike_p", Catalog::gPower[int(u.circuitDef.id)]);
			ai.PublishTeamValue("strike_r", r);
		}
		AiLog(Factory::T() + "apex: air atomic over the cell #" + gAtomId
			+ " left=" + int(left) + "/" + int(gAtomPrize0)
			+ " hp=" + int(u.GetHealthPercent() * 100.f) + "%");
		return;
	}
	if (gAtomLeg == 2) {
		// Staying pays on the same bar it launched on, re-read: what is left
		// in the cell against what the plane has left.
		const float aa = CellAA(u, gAtomAt, r);
		const float p = AtomicThrough(u, aa, 0.f);
		const float need = Catalog::gCostM[int(u.circuitDef.id)]
				* ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF);
		if (left * p >= need)
			return;
		gAtomLeg = 3;
		IUnitTask@ t = u.task;
		if ((t !is null) && (t.GetType() != Task::Type::IDLE)
			&& (t.GetType() != Task::Type::NIL))
			t.RemoveUnit(u);
		u.CmdMoveTo(Builder::gHomePos);
		if (!gStrike)
			ai.PublishTeamValue("strike_r", 0.f);
		AiLog(Factory::T() + "apex: air atomic home #" + gAtomId
			+ " left=" + int(left) + "/" + int(gAtomPrize0)
			+ " cellAA=" + formatFloat(aa, "", 0, 1)
			+ " hp=" + int(u.GetHealthPercent() * 100.f) + "%"
			+ " p=" + formatFloat(p, "", 0, 2)
			+ " worth=" + int(left * p) + "/" + int(need));
		return;
	}
	if (at.distance2D(Builder::gHomePos) < 600.f)
		AtomicOver("home", left);
}

// THE LOOK. A scout standing anywhere takes it, pulled out of whatever stock
// task it was in; none standing, the production draw buys one at the run's
// worth (LookWorth). Lost scouts count against the plane's odds on the route
// (AtomicScoutDelivery), so a hot route stops being flown on its own.
bool AtomicLookHolds(CCircuitUnit@ unit)
{
	return int(unit.id) == gAtomLookId;
}

float AtomicLookWorth()
{
	if (!gAtomLookWant || (gAtomLookId >= 0) || (gAtomId >= 0) || !gAtomCellHas
		|| (Have(gBomberN) == 0))
		return 0.f;
	return gAtomCellPrize;
}

void AtomicLookWatch()
{
	if (gAtomLookId >= 0) {
		CCircuitUnit@ s = AtomicScoutById(gAtomLookId);
		if (s !is null) {
			const AIFloat3 at = s.GetPos(ai.frame);
			if ((gAtomLookLeg == 0) && (at.distance2D(gAtomLookWay) < 300.f)) {
				gAtomLookLeg = 1;
				s.CmdMoveTo(gAtomLookCell);
			}
			if (at.distance2D(gAtomLookCell) > Catalog::gLosR[gAtomLookDef])
				return;
			gAtomLookAt = ai.frame;
			gAtomLookSeen = gAtomLookCell;
			++gAtomScoutLanded;
		}
		gAtomLookWant = false;
		AiLog(Factory::T() + "apex: air atomic look " + ((s is null) ? "lost" : "landed")
			+ " #" + gAtomLookId + " cell=" + int(gAtomLookCell.x) + "," + int(gAtomLookCell.z)
			+ " in " + ((ai.frame - gAtomLookSince) / SECOND) + "s"
			+ " scouts=" + gAtomScoutLanded + "/" + gAtomScoutFlown
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0));
		CoverRelease(Id(gAtomLookId), (s is null) ? "atomic look lost" : "atomic look landed");
		gAtomLookId = -1;
		return;
	}
	if (Have(gBomberN) == 0)
		gAtomLookWant = false;
	if (!gAtomLookWant || (gAtomId >= 0) || !Builder::gHomeSet)
		return;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!IsLookDef(d))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d),
				Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ s = us[i];
			if ((s is null) || (int(s.id) == gLookScout) || Covering(s.id))
				continue;
			IUnitTask@ t = s.task;
			if ((t !is null) && (t.GetType() != Task::Type::IDLE)
				&& (t.GetType() != Task::Type::NIL))
				t.RemoveUnit(s);
			gAtomLookCell = gAtomLookCellWant;
			gAtomLookWay = LookRoute(s, gAtomLookCell);
			gAtomLookLeg = (gAtomLookWay.distance2D(gAtomLookCell) > 1.f) ? 0 : 1;
			s.CmdMoveTo((gAtomLookLeg == 0) ? gAtomLookWay : gAtomLookCell);
			Cover(s, gAtomLookCell, "atomic look");
			gAtomLookId = int(s.id);
			gAtomLookDef = d;
			gAtomLookSince = ai.frame;
			++gAtomScoutFlown;
			AiLog(Factory::T() + "apex: air atomic look " + Catalog::Def(d).GetName()
				+ " #" + s.id + " -> " + int(gAtomLookCell.x) + "," + int(gAtomLookCell.z)
				+ ((gAtomLookLeg == 0) ? (" via " + int(gAtomLookWay.x) + "," + int(gAtomLookWay.z)) : " direct")
				+ " scouts=" + gAtomScoutLanded + "/" + gAtomScoutFlown);
			return;
		}
	}
}

}  // namespace Air
