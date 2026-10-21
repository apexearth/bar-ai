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
final class Ferry {
	int def = -1;
	AIFloat3 home;
	AIFloat3 site;
	CCircuitUnit@ tower;
	int stage = 0;      // 0 building at home, 1 built and waiting, 2 flying
	int madeAt = 0;
	int seenAt = 0;     // last frame a live request stood at home
	int builtAt = 0;
}

final class LiftJob {
	CCircuitUnit@ plane;
	CCircuitUnit@ cargo;
	Ferry@ ferry;
	AIFloat3 src;
	AIFloat3 to;
	AIFloat3 last;
	int stage = 0;      // 0 free, 1 flying to load, 2 carrying
	int deadline = 0;
	bool retried = false;
	int drops = 0;
	int overAt = -1;     // first frame the plane hovered over its drop point still carrying
	bool homeSent = false;   // the move home is one order, not one a second (LiftGoHome)
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
	if ((int(unit.id) >= 0) && (int(unit.id) < int(gNpSent.length())))
		gNpSent[int(unit.id)] = -1;   // the id is reused: its next owner has had no priority sent
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

// AiUpdate runs once a second; a tenth of the turrets per call reads each one every ten seconds (a fifth
// was 0.8 ms a second per seat late in the 16-AI benchmark, hundreds of engine reads for a census).
uint gLiftSampleI = 0;
void LiftSample()
{
	const uint n = gOwnNano.length();
	if (n == 0)
		return;
	const uint per = (n + 9) / 10;
	for (uint k = 0; k < per; ++k) {
		const uint i = (gLiftSampleI++) % n;
		CCircuitUnit@ u = gOwnNano[i];
		if ((u is null) || (i >= gOwnNanoWorkAt.length()))
			continue;
		if (ai.GetResUse(u, false) > 0.f)
			gOwnNanoWorkAt[i] = ai.frame;
	}
}

// The big frame furthest short of lathe -- a fusion, an afus, a converter block
// -- when no line wants a turret (apexearth 2026-10-02: idle turrets stood at
// home while the build they could have fed rose with nobody beside it).
IUnitTask@ gSinkJob;
bool SinkSiteFor(AIFloat3& out at, float& out gap, CCircuitUnit@ plane = null)
{
	gap = 0.f;
	@gSinkJob = null;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null)
			|| !NanoSinkWorthy(int(t.buildDef.id)))
			continue;
		const AIFloat3 p = t.GetBuildPos();
		if (!OnMap(p) || Builder::SiteHot(p))
			continue;
		// Outside every turret's circle was the test, and a big base has no such frame: 486 idle, 16 planes, 2
		// moved (his 10-20). With TUNE_LIFT_TURRETS the frame is the one furthest from done at the lathe on it.
		float g = 0.f;
		if (LiftTurretsOn()) {
			const float B = float(Requests::Workers(t)) * Requests::DRAIN + NanoLatheReaching(p);
			const float R = t.buildDef.costM * (1.f - Requests::Progress(t));
			g = (B > 0.f) ? (R / B) : R;
		} else
			g = NanoGap(p);
		if (g <= gap)
			continue;
		// a frame the lathe on it finishes before the plane can reach it is no sink
		if ((plane !is null) && Requests::JoinArriveOn()) {
			uint arrived = 0;
			const float crew = Requests::ArrivedLathe(t, arrived) + Requests::RingSeen(t);
			if (Requests::JoinSavedSec(Catalog::gBuildTime[int(t.buildDef.id)] * (1.f - Requests::Progress(t)),
					crew, 1.f, plane.GetPos(ai.frame).distance2D(p) / LiftSpeed(plane)) <= 0.f)
				continue;
		}
		gap = g;
		at = p;
		@gSinkJob = t;
	}
	return gap > 0.f;
}

// A free nano-ring slot by the line at lp, legal for def, off doorways and allies.
AIFloat3 LiftSlotNear(int cd, const AIFloat3& in lp)
{
	array<AIFloat3> slots;
	PackSlots(cd, lp, AnchorDefAt(lp), 4, slots);
	int si = 0;
	while ((si < int(slots.length())) && LiftSlotTaken(slots[si]))
		++si;
	AIFloat3 to = (si < int(slots.length())) ? slots[si] : ai.FindBuildSiteNear(Catalog::Def(cd), lp, 300.f);
	to = OffAllyBuildings(OffFactoryExit(to));
	return ai.FindBuildSiteNear(Catalog::Def(cd), to, 150.f);   // the shifts are not checked; an illegal slot is a refused drop
}

// What this plane has hooked, read off positions: a liftable structure of ours
// hanging under it.
CCircuitUnit@ PlaneCargo(CCircuitUnit@ plane)
{
	const AIFloat3 pp = plane.GetPos(ai.frame);
	array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(pp, 48.f);
	if (near is null)
		return null;
	const int pd = int(plane.circuitDef.id);
	for (uint i = 0; i < near.length(); ++i) {
		CCircuitUnit@ u = near[i];
		if ((u is null) || (u.circuitDef is null) || !Airborne(u) || !LiftFits(pd, int(u.circuitDef.id)))
			continue;
		return u;
	}
	return null;
}

// A PLANE WITH NO JOB NEVER KEEPS ITS CARGO (his 10-10: "they should always put
// it back down in the best place available"). A pickup that landed after its
// deadline left the turret hooked while the next dispatch and the fly-home
// overwrote the unload. It goes to the neediest line's ring, else beside it.
void LiftRehome(LiftJob@ jb, CCircuitUnit@ held)
{
	const int cd = int(held.circuitDef.id);
	const AIFloat3 pp = jb.plane.GetPos(ai.frame);
	AIFloat3 lp;
	float net = 0.f;
	CCircuitUnit@ line = null;
	AIFloat3 to;
	// a ferried tower's slot died with its job: it goes down near the plane
	const bool lined = (NanoIndexOf(held.id) >= 0)
			&& ((LineSiteFor(lp, net, line) && (net > 0.f)) || SinkSiteFor(lp, net, jb.plane));
	if (lined)
		to = LiftSlotNear(cd, lp);
	if (!lined || !OnMap(to) || Builder::SiteHot(to))
		to = ai.FindBuildSiteNear(Catalog::Def(cd), OffAllyBuildings(OffFactoryExit(pp)), 600.f);
	if (!OnMap(to))
		to = pp;
	@jb.cargo = held;
	jb.src = pp;
	jb.to = to;
	jb.stage = 2;
	jb.retried = false;
	jb.drops = 0;
	jb.overAt = -1;
	jb.homeSent = false;
	jb.deadline = ai.frame + int((pp.distance2D(to) / LiftSpeed(jb.plane) * 3.f + 30.f) * float(SECOND));
	jb.plane.CmdUnloadAt(to, held);
	AiLog("apex: lift rehome t=" + ai.teamId + " #" + jb.plane.id + " holding " + held.circuitDef.GetName()
			+ " #" + held.id + " -> " + int(to.x) + "," + int(to.z) + (lined ? " line" : " near"));
}

bool LiftDispatch(LiftJob@ jb)
{
	AIFloat3 lp;
	float net = 0.f;
	CCircuitUnit@ line = null;
	bool sink = false;
	if (!LineSiteFor(lp, net, line) || (net <= 0.f)) {
		if (!SinkSiteFor(lp, net, jb.plane))
			return false;
		sink = true;
	}
	IUnitTask@ sinkJob = null;
	if (sink)
		@sinkJob = gSinkJob;
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
		if (!LiftIdleEnough(i, sec) || InLiftJob(u) || LiftRefused(u) || Builder::SiteHot(up))
			continue;
		if ((best < 0) || (sec < bestSec)) {
			best = int(i);
			bestSec = sec;
		}
	}
	if (best < 0)
		return false;
	CCircuitUnit@ cargo = gOwnNano[best];
	if ((sinkJob !is null) && Requests::JoinArriveOn()
		&& !Requests::JoinOkTask(Requests::JA_LIFT, jb.plane, sinkJob, JobGain(sinkJob), false,
			bestSec, Catalog::gBuildPower[int(cargo.circuitDef.id)]))
		return false;
	const AIFloat3 to = LiftSlotNear(int(cargo.circuitDef.id), lp);
	if (!OnMap(to) || Builder::SiteHot(to))
		return false;
	if (sinkJob !is null)
		Requests::JoinTaken(Requests::JA_LIFT, cargo, sinkJob, null, lp);
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
	return true;
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

// Carried or on the ground: a plane hovering over the drop with its cargo
// still hooked holds as still as a turret that landed. A standing turret's
// position reads ~13 above the ground, so height alone cannot say it.
bool Carried(CCircuitUnit@ cargo, CCircuitUnit@ plane)
{
	const AIFloat3 p = cargo.GetPos(ai.frame);
	return (p.distance2D(plane.GetPos(ai.frame)) < 40.f)
			&& (p.y - ai.GetElevationAt(p) > 30.f);
}

// Falling or down, for a turret whose plane died under it.
bool Airborne(CCircuitUnit@ u)
{
	const AIFloat3 p = u.GetPos(ai.frame);
	return p.y - ai.GetElevationAt(p) > 30.f;
}

// Another plane already carries a turret to this slot.
bool LiftSlotTaken(const AIFloat3& in at)
{
	for (uint k = 0; k < gLift.length(); ++k) {
		if ((gLift[k] !is null) && (gLift[k].stage >= 1) && (gLift[k].to.distance2D(at) < 48.f))
			return true;
	}
	return false;
}

// A turret the engine would not lift is not asked again.
array<Id> gLiftRefusedIds;

bool LiftRefused(CCircuitUnit@ u)
{
	return gLiftRefusedIds.find(u.id) >= 0;
}

// Between jobs a plane waits over the base, never where it made its last drop
// (apexearth 2026-09-24).
void LiftGoHome(LiftJob@ jb)
{
	if (!Base::gAnchorSet)
		return;
	if (jb.homeSent || (jb.plane.GetPos(ai.frame).distance2D(Base::gAnchor) <= 300.f))
		return;
	jb.plane.CmdMoveTo(Base::gAnchor);
	jb.homeSent = true;
}

void LiftEnd(LiftJob@ jb)
{
	@jb.ferry = null;
	@jb.cargo = null;
	jb.stage = 0;
	jb.retried = false;
	jb.drops = 0;
	jb.overAt = -1;
	jb.homeSent = false;
	LiftGoHome(jb);
}

// An idle plane's search for work (the line site, then every turret against every job) found nothing:
// another plane of its def finds nothing this update either -- same line, same turrets, only the flight
// differs. lift.step was ~92% of up.lift (0.8-4.0 ms a second per seat in his +100 scav 8v8).
array<int> gLiftIdleMiss;
void LiftStep(LiftJob@ jb)
{
	if (jb.stage == 0) {
		CCircuitUnit@ held = PlaneCargo(jb.plane);
		if (held !is null) {
			LiftRehome(jb, held);
			return;
		}
		const int pdef = int(jb.plane.circuitDef.id);
		if (gLiftIdleMiss.find(pdef) >= 0) {
			LiftGoHome(jb);
			return;
		}
		if (!FerryDispatch(jb) && !LiftDispatch(jb) && !HandDispatch(jb)) {
			gLiftIdleMiss.insertLast(pdef);
			LiftGoHome(jb);
		}
		return;
	}
	const AIFloat3 cp = jb.cargo.GetPos(ai.frame);
	if (jb.stage == 1) {
		if (Carried(jb.cargo, jb.plane)) {
			jb.stage = 2;
			jb.deadline = ai.frame + int((cp.distance2D(jb.to) / LiftSpeed(jb.plane) * 3.f + 30.f) * float(SECOND));
			jb.plane.CmdUnloadAt(jb.to, jb.cargo);
			AiLog("apex: lift up t=" + ai.teamId + " #" + jb.cargo.id);
		} else if (ai.frame > jb.deadline) {
			jb.plane.CmdStop();
			CensusMove(jb.cargo, jb.src);
			++gLiftAborted;
			gLiftRefusedIds.insertLast(jb.cargo.id);
			AiLog("apex: lift abort t=" + ai.teamId + " #" + jb.cargo.id + " never lifted");
			if (jb.ferry !is null)
				FerryDrop(jb.ferry, "never lifted");
			// a pickup landing after this is caught by PlaneCargo on the next step
			LiftEnd(jb);
		}
		return;
	}
	if (!Carried(jb.cargo, jb.plane)) {
		LiftLanded(jb.cargo, jb.src);
		const bool atTarget = cp.distance2D(jb.to) < 200.f;
		if (atTarget)
			++gLiftMoved;
		AiLog("apex: lift done t=" + ai.teamId + " #" + jb.cargo.id
				+ " at=" + int(cp.x) + "," + int(cp.z)
				+ (atTarget ? "" : " (off target)") + " moved=" + gLiftMoved);
		if (jb.ferry !is null) {
			if (atTarget && !jb.retried)
				FerryLanded(jb.ferry);
			else
				FerryDrop(jb.ferry, "set down off the front slot");
		}
		LiftEnd(jb);
		return;
	}
	// Over the drop point and still holding it: the spot is taken. Waiting out
	// the deadline (three flights + 30 s) left planes hovering with a turret for
	// up to 106 s; drop it nearby now.
	const bool over = jb.plane.GetPos(ai.frame).distance2D(jb.to) < 150.f;
	if (over && (jb.overAt < 0))
		jb.overAt = ai.frame;
	const bool stuckOver = over && (jb.drops == 0) && (ai.frame - jb.overAt > 3 * SECOND);
	if ((ai.frame <= jb.deadline) && !stuckOver)
		return;
	// A refused drop never ends with the cargo still hooked: first any legal
	// ground near the target, then any near the plane, widening each time.
	jb.retried = true;
	++jb.drops;
	// Always around the cleared slot: "anywhere near the plane" set turrets
	// down in doorways and walkways (apexearth 2026-09-30).
	const AIFloat3 pp = jb.plane.GetPos(ai.frame);
	// Three refusals at the target and it goes back where it was picked up: that
	// ground took it once (a ferried tower hovered 10 min widening to 6000 elmo).
	const bool back = jb.drops > 3;
	const AIFloat3 at = back ? jb.src : jb.to;
	const int k = back ? (jb.drops - 3) : jb.drops;
	const float r = 300.f * float((k < 4) ? k : 4);
	// THE SITE IS FOUND HERE, not by an area unload: one re-issued every 30 s
	// restarted a flight that took longer than that, so a turret hovered 15 min
	// while the radius grew to 8,400 (his 10-10 game, #16506).
	const int cd = int(jb.cargo.circuitDef.id);
	AIFloat3 spot = ai.FindBuildSiteNear(Catalog::Def(cd), at, r);
	if (OnMap(spot))
		spot = ai.FindBuildSiteNear(Catalog::Def(cd), OffAllyBuildings(OffFactoryExit(spot)), 150.f);
	if (OnMap(spot)) {
		jb.plane.CmdUnloadAt(spot, jb.cargo);
		jb.deadline = ai.frame + int((pp.distance2D(spot) / LiftSpeed(jb.plane) * 3.f + 20.f) * float(SECOND));
	} else {
		jb.plane.CmdUnloadArea(at, r);
		jb.deadline = ai.frame + 30 * SECOND;
	}
	AiLog("apex: lift refused t=" + ai.teamId + " #" + jb.cargo.id
			+ " unloading within " + int(r) + " of " + int(at.x) + "," + int(at.z)
			+ (OnMap(spot) ? (" at=" + int(spot.x) + "," + int(spot.z)) : " area")
			+ " drops=" + jb.drops + " cargoY=" + int(cp.y) + " ground=" + int(ai.GetElevationAt(cp))
			+ " planeY=" + int(pp.y) + " sep=" + int(cp.distance2D(pp)));
}

void LiftSettleStep()
{
	for (uint i = 0; i < gLiftSettle.length(); ++i) {
		CCircuitUnit@ u = gLiftSettle[i];
		if (Airborne(u))
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		LiftLanded(u, gLiftSettleFrom[i]);
		AiLog("apex: lift settled t=" + ai.teamId + " #" + u.id
				+ " at=" + int(p.x) + "," + int(p.z));
		gLiftSettle.removeAt(i);
		gLiftSettleFrom.removeAt(i);
		gLiftSettleLast.removeAt(i);
		return;
	}
}


// BUILD POWER WHERE IT IS NEEDED (apexearth 2026-10-03: "use the importance
// option for nano turrets working on what we need more, and set unimportant
// the items we are over supplied on"). BAR's passive builders draw only what
// the active ones leave. While the army is at its target, the factories and
// the turrets that can only reach a factory go passive; a turret with an
// economy frame rising in reach stays active. A few turrets per pass.
uint gNpNext = 0;
int gNpAt = -999999;
bool gNpOver = false;
// The priority last sent per unit id: CmdBARPriority is a network command, and the pass re-sent every turret's
// and every factory's each cycle whether it changed or not (his 10-18: our orders lag the online game).
array<int8> gNpSent(32001, -1);
void NpSend(CCircuitUnit@ u, bool low)
{
	const int id = int(u.id);
	const int8 v = low ? 0 : 1;
	if ((id >= 0) && (id < int(gNpSent.length())) && (gNpSent[id] == v))
		return;
	u.CmdBARPriority(low ? 0.f : 1.f);
	if ((id >= 0) && (id < int(gNpSent.length())))
		gNpSent[id] = v;
}
int gNpLow = 0, gNpHigh = 0;
int gNpLogAt = 0;
bool NanoEcoFrameNear(const AIFloat3& in p, float r)
{
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null))
			continue;
		const int d = int(t.buildDef.id);
		if (Catalog::gMobile[d])
			continue;
		if ((Catalog::gMakeE[d] <= 0.f) && (Catalog::gConvCapacity[d] <= 0.f)
			&& (Catalog::gExtractsM[d] <= 0.f) && (Catalog::gStoreE[d] <= 0.f))
			continue;
		if (t.GetBuildPos().distance2D(p) < r)
			return true;
	}
	return false;
}
void NanoPriorityPass()
{
	if (ai.frame - gNpAt < SECOND)
		return;
	gNpAt = ai.frame;
	if (gNpNext == 0) {
		gNpOver = (ArmyValue() + ArmyInFlightM() >= ArmyTarget()) && !MetalWasting();
		for (uint f = 0; f < Factory::gFacUnits.length(); ++f) {
			CCircuitUnit@ fac = Factory::gFacUnits[f];
			if (fac !is null)
				NpSend(fac, gNpOver);
		}
	}
	const uint n = gOwnNano.length();
	for (uint k = 0; (k < 8) && (gNpNext < n); ++k, ++gNpNext) {
		CCircuitUnit@ u = gOwnNano[gNpNext];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		const float r = Catalog::gBuildDist[int(u.circuitDef.id)] + 64.f;
		bool low = false;
		if (gNpOver && !NanoEcoFrameNear(p, r)) {
			for (uint f = 0; (f < Factory::gFacUnits.length()) && !low; ++f) {
				CCircuitUnit@ fac = Factory::gFacUnits[f];
				low = (fac !is null) && (fac.GetPos(ai.frame).distance2D(p) < r + 64.f);
			}
		}
		NpSend(u, low);
		if (low)
			++gNpLow;
		else
			++gNpHigh;
	}
	if (gNpNext >= n) {
		gNpNext = 0;
		if (ai.frame >= gNpLogAt) {
			gNpLogAt = ai.frame + 60 * SECOND;
			AiLog("apex: nanoprio t=" + ai.teamId + " over=" + (gNpOver ? 1 : 0)
				+ " facs=" + Factory::gFacUnits.length() + " low=" + gNpLow + " high=" + gNpHigh);
		}
		gNpLow = 0;
		gNpHigh = 0;
	}
}

int gLiftLogAt = 0;
void LiftUpdate()
{
	{ const double _t = Perf::T0(); LiftSample(); Perf::Add("lift.sample", _t); }
	{ const double _t = Perf::T0(); NanoPriorityPass(); Perf::Add("lift.prio", _t); }
	{ const double _t = Perf::T0(); FerryUpdate(); Perf::Add("lift.ferry", _t); }
	gLiftIdleMiss.resize(0);
	const double _tLs = Perf::T0();
	for (uint j = 0; j < gLift.length(); ++j)
		LiftStep(gLift[j]);
	Perf::Add("lift.step", _tLs);
	{ const double _t = Perf::T0(); LiftSettleStep(); Perf::Add("lift.settle", _t); }
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
// HANDS FLOWN TO THE WORK (TUNE_LIFT_HANDS; his 10-20: price a transport by "how it can quickly move ground units,
// like the commander, to get them around the field faster and save walk time" -- and "a transporting commander
// which is shot down DIES"). A ground builder walking to a far job is lifted when the seconds the flight saves, at
// its own lathe, beat what the flight risks: the AA we have seen along the route against the plane's health, times
// the plane and its cargo -- for the commander, everything we own.
const float LIFT_HAND_OVERHEAD_S = 10.f;   // load and unload, measured off the turret lifts' up/done lines
int gLiftHandsSent = 0;
bool LiftHandsOn() { return ai.GetTunable("apex_lift_hands", TUNE_LIFT_HANDS) > 0.f; }

float LiftRouteLossP(CCircuitUnit@ plane, const AIFloat3& in a, const AIFloat3& in b)
{
	const int pd = int(plane.circuitDef.id);
	const float hp = (Catalog::gHealth[pd] > 1.f) ? Catalog::gHealth[pd] : 1.f;
	const float sec = a.distance2D(b) / LiftSpeed(plane);
	float dmg = 0.f;
	for (int k = 0; k <= 8; ++k) {
		const float f = float(k) / 8.f;
		dmg += Air::NaAAAt(a + (b - a) * f) * sec / 9.f;
	}
	return (dmg >= hp) ? 1.f : (dmg / hp);
}

float LiftHandWorth(CCircuitUnit@ plane, CCircuitUnit@ u, AIFloat3& out site, float& out saved)
{
	saved = 0.f;
	if ((u is null) || (u.circuitDef is null) || (u.task is null) || (u.task.GetType() != Task::Type::BUILDER))
		return 0.f;
	const int ud = int(u.circuitDef.id);
	if (!Catalog::gMobile[ud] || Catalog::gFlyer[ud] || !LiftFits(int(plane.circuitDef.id), ud) || InLiftJob(u))
		return 0.f;
	site = u.task.GetBuildPos();
	if (!OnMap(site))
		return 0.f;
	const float speed = Catalog::gSpeed[ud];
	if (speed <= 1.f)
		return 0.f;
	const AIFloat3 at = u.GetPos(ai.frame);
	const float reach = Catalog::gBuildDist[ud];
	const float d = at.distance2D(site) - reach;
	if (d <= 0.f)
		return 0.f;
	const float vp = LiftSpeed(plane);
	const float flown = plane.GetPos(ai.frame).distance2D(at) / vp + d / vp + LIFT_HAND_OVERHEAD_S;
	saved = d / speed - flown;
	if (saved <= 0.f)
		return 0.f;
	const bool com = u.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	const float stake = (com ? ComHomeWorthM() : Catalog::gCostM[ud]) + Catalog::gCostM[int(plane.circuitDef.id)];
	return saved * WageOf(u) - LiftRouteLossP(plane, at, site) * stake;
}

bool HandDispatch(LiftJob@ jb)
{
	if (!LiftHandsOn())
		return false;
	CCircuitUnit@ best = null;
	float bestV = 0.f, bestSaved = 0.f;
	AIFloat3 bestSite;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		AIFloat3 site;
		float saved;
		const float v = LiftHandWorth(jb.plane, gWorkers[i], site, saved);
		if (v > bestV) {
			bestV = v;
			@best = gWorkers[i];
			bestSite = site;
			bestSaved = saved;
		}
	}
	if (best is null)
		return false;
	const AIFloat3 at = best.GetPos(ai.frame);
	const float reach = Catalog::gBuildDist[int(best.circuitDef.id)] * 0.7f;
	const float d = at.distance2D(bestSite);
	jb.to = (d > reach) ? (bestSite + (at - bestSite) * (reach / d)) : at;
	@jb.cargo = best;
	jb.src = at;
	jb.stage = 1;
	jb.retried = false;
	const float speed = LiftSpeed(jb.plane);
	jb.deadline = ai.frame + int((jb.plane.GetPos(ai.frame).distance2D(at) / speed * 3.f + 30.f) * float(SECOND));
	jb.plane.CmdLoadUnit(best);   // join-arrive: the hand is flown to its own job, not sent into another's
	++gLiftHandsSent;
	AiLog("apex: lift hand t=" + ai.teamId + " " + jb.plane.circuitDef.GetName() + " #" + jb.plane.id
		+ " takes " + best.circuitDef.GetName() + " #" + best.id + " saves=" + int(bestSaved) + "s v=" + int(bestV)
		+ " to=" + int(jb.to.x) + "," + int(jb.to.z) + " sent=" + gLiftHandsSent);
	return true;
}

// What the hands' walks would save a plane of def d, for the production market: the best lift on offer now.
float LiftHandsWorthFor(int d)
{
	if (!LiftHandsOn())
		return 0.f;
	float best = 0.f;
	for (uint j = 0; j < gLift.length(); ++j)
		if ((gLift[j] !is null) && (gLift[j].plane !is null) && (gLift[j].stage == 0))
			return 0.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u is null) || (u.circuitDef is null) || (u.task is null) || (u.task.GetType() != Task::Type::BUILDER))
			continue;
		const int ud = int(u.circuitDef.id);
		if (!Catalog::gMobile[ud] || Catalog::gFlyer[ud] || !Catalog::Def(d).CanLift(u.circuitDef))
			continue;
		const AIFloat3 site = u.task.GetBuildPos();
		const float speed = Catalog::gSpeed[ud];
		if (!OnMap(site) || (speed <= 1.f))
			continue;
		const float dist = u.GetPos(ai.frame).distance2D(site) - Catalog::gBuildDist[ud];
		const float vp = (Catalog::gSpeed[d] > 1.f) ? Catalog::gSpeed[d] : 100.f;
		const float saved = dist / speed - dist / vp - LIFT_HAND_OVERHEAD_S;
		if (saved > 0.f)
			best += saved * WageOf(u);
	}
	return best;
}

float gLiftTookDist = 0.f;   // the summed flight of the turrets LiftTurretWorth took, for the fleet's throughput
int gLiftPriceLogAt = 0;
void LiftPriceLog(int d, const string &in why, float took, float need, float have, float worth)
{
	if (ai.frame < gLiftPriceLogAt)
		return;
	gLiftPriceLogAt = ai.frame + 60 * SECOND;
	AiLog("apex: lift-price t=" + ai.teamId + " " + Catalog::Def(d).GetName() + " why=" + why
		+ " took=" + int(took) + " need=" + formatFloat(need, "", 0, 1) + " have=" + int(have)
		+ " worth=" + int(worth) + " turrets=" + gOwnNano.length());
}

float LiftGainFor(int d, float fillSec)
{
	++gLiftAsk;
	if (!IsLiftDef(d))
		return 0.f;
	if (Brain::PendAnyOf(d) > 0) {
		LiftPriceLog(d, "pending", 0.f, 0.f, float(gLift.length()), 0.f);
		return 0.f;
	}
	// A free plane already answers the cargo: ten were bought for jobs two
	// planes were doing, the rest hovering over the air plant (10-01).
	// ...with TUNE_LIFT_TURRETS the fleet answers what it can carry in the fill, not whether one plane is free this
	// instant: between trips one always was, and six planes served 578 turrets with 305 idle (his 10-20 game).
	if (!LiftTurretsOn()) {
		for (uint i = 0; i < gLift.length(); ++i) {
			if ((gLift[i] !is null) && (gLift[i].plane !is null) && (gLift[i].stage == 0))
				return 0.f;
		}
	}
	const float fill = (fillSec > 1.f) ? fillSec : 180.f;
	float took = 0.f;
	float worth = LiftTurretWorth(d, took) + LiftHandsWorthFor(d);
	if (LiftTurretsOn() && (took > 0.f)) {
		const float v = (Catalog::gSpeed[d] > 1.f) ? Catalog::gSpeed[d] : 100.f;
		const float planeSec = took * (2.f * gLiftTookDist / took / v + LIFT_HAND_OVERHEAD_S);
		const float needPlanes = planeSec / fill;
		const float have = float(gLift.length());
		if (needPlanes <= have) {
			LiftPriceLog(d, "covered", took, needPlanes, have, worth);
			return 0.f;
		}
		worth *= (needPlanes - have) / needPlanes;
		LiftPriceLog(d, "buy", took, needPlanes, have, worth);
	} else if (LiftTurretsOn())
		LiftPriceLog(d, "none-idle", took, 0.f, float(gLift.length()), worth);
	gLiftPriced = (worth + FerryMissedFor(d, fill)) / fill;
	gLiftPricedTurrets = int(took);
	return gLiftPriced;
}

// The metal of the idle turrets a plane of def d could carry into the short
// line, and how many.
// A TRANSPORT IS WORTH WHAT IT MOVES (TUNE_LIFT_TURRETS; his 10-20: "you can price a transport by its ability to
// move nano turrets"). With no line short of lathe, the big frame the turrets on it finish slowest takes the idle
// turrets a plane can fly: as many as finish what is left of it within a minute.
bool LiftTurretsOn() { return ai.GetTunable("apex_lift_turrets", TUNE_LIFT_TURRETS) > 0.f; }

float LiftTurretWorth(int d, float& out took)
{
	took = 0.f;
	gLiftTookDist = 0.f;
	AIFloat3 lp;
	float net = 0.f;
	CCircuitUnit@ line = null;
	float need = 0.f;
	if (LineSiteFor(lp, net, line) && (net > 0.f))
		need = LiftTurretsOn() ? float(gOwnNano.length()) : (net / NANO_ABSORB);   // the fleet is sized on every idle turret
	else {
		++gLiftNoLine;
		float gap = 0.f;
		if (!LiftTurretsOn() || !SinkSiteFor(lp, gap) || (gSinkJob is null) || (gSinkJob.buildDef is null))
			return 0.f;
		// Every idle turret the fleet could put to work, not the few that finish one frame in a minute: priced on
		// those, two planes read as plenty beside 194 idle turrets (his 10-20 game). Each lifted turret works the
		// next frame furthest from done in its turn.
		need = float(gOwnNano.length());
	}
	const float speed = (Catalog::gSpeed[d] > 1.f) ? Catalog::gSpeed[d] : 100.f;
	float worth = 0.f;
	for (uint i = 0; (i < gOwnNano.length()) && (took < need); ++i) {
		CCircuitUnit@ u = gOwnNano[i];
		if (u is null)
			continue;
		const int c = int(u.circuitDef.id);
		if (!LiftFits(d, c))
			continue;
		if (!LiftTurretsOn() && LiftServed(c))   // with TUNE_LIFT_TURRETS the fleet's throughput answers this, not one owned plane
			continue;
		const AIFloat3 up = gOwnNanoPos[i];
		if (up.distance2D(lp) < Catalog::gBuildDist[c])
			continue;
		if (!LiftIdleEnough(i, 2.f * up.distance2D(lp) / speed))
			continue;
		worth += Catalog::gCostM[c];
		took += 1.f;
		gLiftTookDist += up.distance2D(lp);
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
