namespace Market {

// AIR-LIFTED TURRETS (TODO.md, apexearth 2026-09-18 and 09-24): a construction
// turret that has stood idle is flown to the working line furthest short of
// lathe. The engine sends an AI no load/unload event, so every stage below is
// read off positions.

array<int> gLiftTurretDefs;
bool gLiftDefsReady = false;
dictionary gLiftFit;

void LiftDefsInit()
{
	if (gLiftDefsReady)
		return;
	gLiftDefsReady = true;
	for (uint d = 0; d < Catalog::gCostM.length(); ++d) {
		if (!Catalog::ValidId(int(d)) || !Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gBuildPower[d] <= 0.f) || (Catalog::gBuildsList[d].length() > 0))
			continue;
		gLiftTurretDefs.insertLast(int(d));
	}
}

bool LiftFits(int t, int c)
{
	const string k = formatInt(t * 65536 + c);
	int64 got;
	if (gLiftFit.get(k, got))
		return got != 0;
	const bool ok = Catalog::Def(t).CanLift(Catalog::Def(c));
	gLiftFit.set(k, ok ? int64(1) : int64(0));
	return ok;
}

bool IsLiftDef(int d)
{
	if (!Catalog::ValidId(d) || !Catalog::gFlyer[d] || (Catalog::gBuildPower[d] > 0.f))
		return false;
	LiftDefsInit();
	for (uint i = 0; i < gLiftTurretDefs.length(); ++i) {
		if (LiftFits(d, gLiftTurretDefs[i]))
			return true;
	}
	return false;
}

// A tower built at home for a front slot, waiting for its flight (lift_ferry.as).
class Ferry {
	int def = -1;
	AIFloat3 home;
	AIFloat3 site;
	CCircuitUnit@ tower;
	int stage = 0;      // 0 building at home, 1 built and waiting, 2 flying
	int madeAt = 0;
	int seenAt = 0;     // last frame a live request stood at home
	int builtAt = 0;
}

class LiftJob {
	CCircuitUnit@ plane;
	CCircuitUnit@ cargo;
	Ferry@ ferry;
	AIFloat3 src;
	AIFloat3 to;
	AIFloat3 last;
	int stage = 0;      // 0 free, 1 flying to load, 2 carrying
	int deadline = 0;
	bool retried = false;
}
array<LiftJob@> gLift;

// A turret whose plane died in the air lands wherever it lands.
array<CCircuitUnit@> gLiftSettle;
array<AIFloat3> gLiftSettleFrom;
array<AIFloat3> gLiftSettleLast;

int gLiftMoved = 0, gLiftAborted = 0, gLiftLost = 0;
float gLiftPriced = 0.f;
int gLiftAsk = 0, gLiftNoLine = 0;
int gLiftPricedTurrets = 0;

bool LiftHolds(CCircuitUnit@ unit)
{
	return (unit !is null) && IsLiftDef(int(unit.circuitDef.id));
}

int NanoIndexOf(Id id)
{
	for (uint i = 0; i < gOwnNanoIds.length(); ++i) {
		if (gOwnNanoIds[i] == id)
			return int(i);
	}
	return -1;
}

void NanoCensusMove(CCircuitUnit@ u, const AIFloat3& in p)
{
	const int i = NanoIndexOf(u.id);
	if (i < 0)
		return;
	gOwnNanoPos[i] = p;
	gOwnNanoWorkAt[i] = ai.frame;
	NanoGridDrop();
}

void ProtCensusMove(CCircuitUnit@ u, const AIFloat3& in p)
{
	const int pc = ProtClassOf(int(u.circuitDef.id));
	if (pc < 0)
		return;
	for (uint i = 0; i < gProtIds[pc].length(); ++i) {
		if (gProtIds[pc][i] == u.id) {
			gProtPos[pc][i] = p;
			return;
		}
	}
}

void CensusMove(CCircuitUnit@ u, const AIFloat3& in p)
{
	NanoCensusMove(u, p);
	ProtCensusMove(u, p);
}

bool InLiftJob(CCircuitUnit@ u)
{
	for (uint j = 0; j < gLift.length(); ++j) {
		if ((gLift[j].stage > 0) && (gLift[j].cargo is u))
			return true;
	}
	return false;
}

void LiftNoteFinished(CCircuitUnit@ unit)
{
	FerryNoteFinished(unit);
	if (!LiftHolds(unit))
		return;
	LiftJob@ j = LiftJob();
	@j.plane = unit;
	gLift.insertLast(j);
	AiLog("apex: lift plane t=" + ai.teamId + " " + unit.circuitDef.GetName()
			+ " #" + unit.id + " fleet=" + gLift.length());
}

void LiftNoteDead(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	for (uint i = 0; i < gLiftSettle.length(); ++i) {
		if (gLiftSettle[i] is unit) {
			gLiftSettle.removeAt(i);
			gLiftSettleFrom.removeAt(i);
			gLiftSettleLast.removeAt(i);
			break;
		}
	}
	for (uint j = 0; j < gLift.length(); ++j) {
		LiftJob@ jb = gLift[j];
		if (jb.plane is unit) {
			if ((jb.stage == 2) && (jb.cargo !is null)) {
				gLiftSettle.insertLast(jb.cargo);
				gLiftSettleFrom.insertLast(jb.src);
				gLiftSettleLast.insertLast(jb.cargo.GetPos(ai.frame));
				++gLiftLost;
				if (jb.ferry !is null)
					FerryDrop(jb.ferry, "plane shot down carrying it");
			} else if ((jb.stage == 1) && (jb.cargo !is null)) {
				CensusMove(jb.cargo, jb.src);
				if (jb.ferry !is null)
					jb.ferry.stage = 1;
			}
			AiLog("apex: lift plane-dead t=" + ai.teamId + " #" + unit.id
					+ " stage=" + jb.stage);
			gLift.removeAt(j);
			return;
		}
		if ((jb.stage > 0) && (jb.cargo is unit)) {
			AiLog("apex: lift cargo-dead t=" + ai.teamId + " #" + unit.id
					+ " stage=" + jb.stage);
			jb.plane.CmdStop();
			if (jb.ferry !is null)
				FerryDrop(jb.ferry, "tower died");
			@jb.ferry = null;
			@jb.cargo = null;
			jb.stage = 0;
			return;
		}
	}
	FerryNoteDead(unit);
}

float LiftSpeed(CCircuitUnit@ plane)
{
	const float s = Catalog::gSpeed[int(plane.circuitDef.id)];
	return (s > 1.f) ? s : 100.f;
}

// Out of action for the flight: a turret idle for longer than that has, on
// its own record, more idle ahead of it than the move takes.
bool LiftIdleEnough(uint i, float flightSec)
{
	if (i >= gOwnNanoWorkAt.length())
		return false;
	return float(ai.frame - gOwnNanoWorkAt[i]) / float(SECOND) >= flightSec;
}

// AiUpdate runs once a second; a fifth of the turrets per call reads each one
// every five seconds.
uint gLiftSampleI = 0;
void LiftSample()
{
	const uint n = gOwnNano.length();
	if (n == 0)
		return;
	const uint per = (n + 4) / 5;
	for (uint k = 0; k < per; ++k) {
		const uint i = (gLiftSampleI++) % n;
		CCircuitUnit@ u = gOwnNano[i];
		if ((u is null) || (i >= gOwnNanoWorkAt.length()))
			continue;
		if (ai.GetResUse(u, false) > 0.f)
			gOwnNanoWorkAt[i] = ai.frame;
	}
}

void LiftDispatch(LiftJob@ jb)
{
	AIFloat3 lp;
	float net = 0.f;
	CCircuitUnit@ line = null;
	if (!LineSiteFor(lp, net, line) || (net <= 0.f))
		return;
	const int pd = int(jb.plane.circuitDef.id);
	const float speed = LiftSpeed(jb.plane);
	const AIFloat3 pp = jb.plane.GetPos(ai.frame);
	int best = -1;
	float bestSec = 0.f;
	for (uint i = 0; i < gOwnNano.length(); ++i) {
		CCircuitUnit@ u = gOwnNano[i];
		if (u is null)
			continue;
		const int c = int(u.circuitDef.id);
		if (!LiftFits(pd, c))
			continue;
		const AIFloat3 up = gOwnNanoPos[i];
		if (up.distance2D(lp) < Catalog::gBuildDist[c])
			continue;
		const float sec = (pp.distance2D(up) + up.distance2D(lp)) / speed;
		if (!LiftIdleEnough(i, sec) || InLiftJob(u) || Builder::SiteHot(up))
			continue;
		if ((best < 0) || (sec < bestSec)) {
			best = int(i);
			bestSec = sec;
		}
	}
	if (best < 0)
		return;
	CCircuitUnit@ cargo = gOwnNano[best];
	const int cd = int(cargo.circuitDef.id);
	array<AIFloat3> slots;
	PackSlots(cd, lp, AnchorDefAt(lp), 1, slots);
	AIFloat3 to = (slots.length() > 0) ? slots[0] : ai.FindBuildSiteNear(Catalog::Def(cd), lp, 300.f);
	if (!OnMap(to) || Builder::SiteHot(to))
		return;
	@jb.cargo = cargo;
	jb.src = cargo.GetPos(ai.frame);
	jb.to = to;
	jb.stage = 1;
	jb.retried = false;
	jb.deadline = ai.frame + int((pp.distance2D(jb.src) / speed * 3.f + 30.f) * float(SECOND));
	jb.plane.CmdLoadUnit(cargo);
	const int idleSec = (ai.frame - gOwnNanoWorkAt[best]) / SECOND;
	NanoCensusMove(cargo, to);
	AiLog("apex: lift go t=" + ai.teamId + " " + jb.plane.circuitDef.GetName()
			+ " #" + jb.plane.id + " takes " + cargo.circuitDef.GetName() + " #" + cargo.id
			+ " from=" + int(jb.src.x) + "," + int(jb.src.z)
			+ " to=" + int(to.x) + "," + int(to.z)
			+ " line=" + ((line !is null) ? line.circuitDef.GetName() : "?")
			+ " net=" + formatFloat(net, "", 0, 1)
			+ " idle=" + idleSec + "s"
			+ " flight=" + int(bestSec) + "s");
}

void LiftLanded(CCircuitUnit@ cargo, const AIFloat3& in src)
{
	const AIFloat3 at = cargo.GetPos(ai.frame);
	aiFactoryMgr.UnitRelocated(cargo, src);
	CensusMove(cargo, at);
	if (NanoIndexOf(cargo.id) < 0)
		return;
	AIFloat3 p = at;
	p.x += 48.f;
	p.z += 48.f;
	cargo.CmdPatrolTo(p);
}

void LiftStep(LiftJob@ jb)
{
	if (jb.stage == 0) {
		if (!FerryDispatch(jb))
			LiftDispatch(jb);
		return;
	}
	const AIFloat3 cp = jb.cargo.GetPos(ai.frame);
	if (jb.stage == 1) {
		if (cp.distance2D(jb.src) > 20.f) {
			jb.stage = 2;
			jb.last = cp;
			jb.deadline = ai.frame + int((cp.distance2D(jb.to) / LiftSpeed(jb.plane) * 3.f + 30.f) * float(SECOND));
			jb.plane.CmdUnloadAt(jb.to, jb.cargo);
			AiLog("apex: lift up t=" + ai.teamId + " #" + jb.cargo.id);
		} else if (ai.frame > jb.deadline) {
			jb.plane.CmdStop();
			CensusMove(jb.cargo, jb.src);
			++gLiftAborted;
			AiLog("apex: lift abort t=" + ai.teamId + " #" + jb.cargo.id + " never lifted");
			if (jb.ferry !is null)
				FerryDrop(jb.ferry, "never lifted");
			@jb.ferry = null;
			@jb.cargo = null;
			jb.stage = 0;
		}
		return;
	}
	const bool still = cp.distance2D(jb.last) < 2.f;
	jb.last = cp;
	if (still && (cp.distance2D(jb.to) < 64.f)) {
		LiftLanded(jb.cargo, jb.src);
		++gLiftMoved;
		AiLog("apex: lift done t=" + ai.teamId + " #" + jb.cargo.id
				+ " at=" + int(cp.x) + "," + int(cp.z) + " moved=" + gLiftMoved);
		if (jb.ferry !is null) {
			if (jb.retried)
				FerryDrop(jb.ferry, "drop refused at the front");
			else
				FerryLanded(jb.ferry);
		}
		@jb.ferry = null;
		@jb.cargo = null;
		jb.stage = 0;
		return;
	}
	if (ai.frame <= jb.deadline)
		return;
	if (!jb.retried) {
		// The game refuses a drop on slopes and water; where it stood is known good.
		jb.retried = true;
		jb.to = jb.src;
		jb.deadline = ai.frame + int((cp.distance2D(jb.src) / LiftSpeed(jb.plane) * 3.f + 30.f) * float(SECOND));
		jb.plane.CmdUnloadAt(jb.to, jb.cargo);
		AiLog("apex: lift refused t=" + ai.teamId + " #" + jb.cargo.id + " returning it");
		return;
	}
	jb.plane.CmdStop();
	++gLiftAborted;
	AiLog("apex: lift abort t=" + ai.teamId + " #" + jb.cargo.id + " cannot unload");
	gLiftSettle.insertLast(jb.cargo);
	gLiftSettleFrom.insertLast(jb.src);
	gLiftSettleLast.insertLast(cp);
	if (jb.ferry !is null)
		FerryDrop(jb.ferry, "cannot unload");
	@jb.ferry = null;
	@jb.cargo = null;
	jb.stage = 0;
}

void LiftSettleStep()
{
	for (uint i = 0; i < gLiftSettle.length(); ++i) {
		CCircuitUnit@ u = gLiftSettle[i];
		const AIFloat3 p = u.GetPos(ai.frame);
		if (p.distance2D(gLiftSettleLast[i]) >= 2.f) {
			gLiftSettleLast[i] = p;
			continue;
		}
		LiftLanded(u, gLiftSettleFrom[i]);
		AiLog("apex: lift settled t=" + ai.teamId + " #" + u.id
				+ " at=" + int(p.x) + "," + int(p.z));
		gLiftSettle.removeAt(i);
		gLiftSettleFrom.removeAt(i);
		gLiftSettleLast.removeAt(i);
		return;
	}
}

int gLiftLogAt = 0;
void LiftUpdate()
{
	LiftSample();
	FerryUpdate();
	for (uint j = 0; j < gLift.length(); ++j)
		LiftStep(gLift[j]);
	LiftSettleStep();
	if (ai.frame < gLiftLogAt)
		return;
	gLiftLogAt = ai.frame + 60 * SECOND;
	int idle = 0;
	for (uint i = 0; i < gOwnNano.length(); ++i) {
		if ((i < gOwnNanoWorkAt.length()) && (ai.frame - gOwnNanoWorkAt[i] > 60 * SECOND))
			++idle;
	}
	AiLog("apex: lift census t=" + ai.teamId + " turrets=" + gOwnNano.length()
			+ " idle60=" + idle + " fleet=" + gLift.length()
			+ " moved=" + gLiftMoved + " aborted=" + gLiftAborted + " lost=" + gLiftLost
			+ " lastGain=" + formatFloat(gLiftPriced, "", 0, 2) + " over=" + gLiftPricedTurrets
			+ " asked=" + gLiftAsk + " noLine=" + gLiftNoLine
			+ " ferryPlans=" + gFerryPlans + " ferried=" + gFerried
			+ " ferryDropped=" + gFerryDropped + " ferryOnsite=" + gFerryOnsite
			+ " repriced=" + gFerryRepriced + " ferryHeld=" + gFerryHeld
			+ " missSlots=" + gFerryMissM.length() + " missM=" + formatFloat(FerryMissSum(), "", 0, 1)
			+ " plantLift=" + formatFloat(gPlantLiftLast, "", 0, 3));
}

// What a transport of def d is worth [metal/s over the fill]: the turrets it
// could carry into the short line instead of building them there, and the
// front towers lost building on site that it would have flown instead. A plane
// we already have answers the same cargo, so it answers the same demand.
float LiftGainFor(int d, float fillSec)
{
	++gLiftAsk;
	if (!IsLiftDef(d) || (Brain::PendAnyOf(d) > 0))
		return 0.f;
	const float fill = (fillSec > 1.f) ? fillSec : 180.f;
	float took = 0.f;
	const float worth = LiftTurretWorth(d, took);
	gLiftPriced = (worth + FerryMissedFor(d, fill)) / fill;
	gLiftPricedTurrets = int(took);
	return gLiftPriced;
}

// The metal of the idle turrets a plane of def d could carry into the short
// line, and how many.
float LiftTurretWorth(int d, float& out took)
{
	took = 0.f;
	AIFloat3 lp;
	float net = 0.f;
	CCircuitUnit@ line = null;
	if (!LineSiteFor(lp, net, line) || (net <= 0.f)) {
		++gLiftNoLine;
		return 0.f;
	}
	const float need = net / NANO_ABSORB;
	const float speed = (Catalog::gSpeed[d] > 1.f) ? Catalog::gSpeed[d] : 100.f;
	float worth = 0.f;
	for (uint i = 0; (i < gOwnNano.length()) && (took < need); ++i) {
		CCircuitUnit@ u = gOwnNano[i];
		if (u is null)
			continue;
		const int c = int(u.circuitDef.id);
		if (!LiftFits(d, c))
			continue;
		bool served = false;
		for (uint j = 0; (j < gLift.length()) && !served; ++j)
			served = LiftFits(int(gLift[j].plane.circuitDef.id), c);
		if (served)
			continue;
		const AIFloat3 up = gOwnNanoPos[i];
		if (up.distance2D(lp) < Catalog::gBuildDist[c])
			continue;
		if (!LiftIdleEnough(i, 2.f * up.distance2D(lp) / speed))
			continue;
		worth += Catalog::gCostM[c];
		took += 1.f;
	}
	return worth;
}

// What a new plant adds by being able to build transports [metal/s over the
// fill]: the best net saving -- carried cargo less the plane's own price --
// of any transport on its list. Nothing while a plant we already own offers
// one: that demand is served, and a second plant would count it twice.
float gPlantLiftLast = 0.f;
float PlantLiftGain(int plant)
{
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (f is null)
			continue;
		const array<int>@ fl = Catalog::gBuildsList[int(f.circuitDef.id)];
		for (uint k = 0; k < fl.length(); ++k) {
			if (Catalog::gAvailable[fl[k]] && IsLiftDef(fl[k]))
				return 0.f;
		}
	}
	float fill = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	if (fill <= 1.f)
		fill = 180.f;
	float best = 0.f;
	const array<int>@ pl = Catalog::gBuildsList[plant];
	for (uint i = 0; i < pl.length(); ++i) {
		const int t = pl[i];
		if (!Catalog::gAvailable[t] || !IsLiftDef(t))
			continue;
		float took = 0.f;
		const float net = LiftTurretWorth(t, took) + FerryMissedFor(t, fill)
				- Catalog::gCostM[t];
		if (net > best)
			best = net;
	}
	gPlantLiftLast = best / fill;
	return gPlantLiftLast;
}

}  // namespace Market
