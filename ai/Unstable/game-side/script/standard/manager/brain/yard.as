namespace Brain {

//------------------------------------------------------------------------------
// A UNIT THAT CANNOT LEAVE ITS FACTORY (apexearth 2026-10-04: "We will often
// have units stuck inside of their factory area and they can't leave").
//
// The signal is the one the engine itself acts on: a finished unit standing on
// a plant's footprint. While one does, the plant cannot start the next unit, so
// every unit on it is watched, not only the newest -- a new birth is not a sign
// the yard cleared. The door is the engine's facing: 1,230 measured exits
// across the logs followed it for every ground plant type.
//
// The cure is done by hands that are idle BECAUSE of the jam: the turrets in
// reach, whose plant has nothing to build. Builders only get the job through
// the market (a pen verdict), when no turret reaches.
//------------------------------------------------------------------------------

array<Id>  gYdUnit;    // a unit seen standing on a plant's footprint
array<Id>  gYdPlant;   // ...the plant
array<int> gYdSince;   // ...first frame it was seen there
array<int> gYdSeen;    // ...last frame it was seen there

array<Id>  gYpPlant;   // a plant whose yard is jammed
array<int> gYpActAt;   // ...earliest frame of its next act
array<int> gYpActs;    // ...acts so far in this jam: how far the door strip reaches
array<Id>  gYpEating;  // ...a blocker the last act named, until it is gone
array<bool> gYpNamed;  // ...whether the last act found anything of ours in the strip
array<int> gYpNamedAt; // ...last frame an act found something of ours to eat
array<bool> gYpPushed; // ...whether this jam has had its first act, a push alone
array<int> gYpWreckAt; // ...earliest frame of its next wreck sweep

uint gYdCursor = 0;
int  gYdLogAt = 0;
int  gYdJams = 0, gYdPushed = 0, gYdNanoSent = 0, gYdOffered = 0, gYdUnitEat = 0;
int  gYdTerrain = 0;
int  gYdWreck = 0;      // wreck sweeps ordered at a jammed door
int  gYdWorstS = 0;

int YardSlot(Id plant)
{
	for (uint i = 0; i < gYpPlant.length(); ++i) {
		if (gYpPlant[i] == plant)
			return int(i);
	}
	return -1;
}

void YardClear(Id plant)
{
	const int s = YardSlot(plant);
	if (s < 0)
		return;
	gYpPlant.removeAt(uint(s));
	gYpActAt.removeAt(uint(s));
	gYpActs.removeAt(uint(s));
	gYpEating.removeAt(uint(s));
	gYpNamed.removeAt(uint(s));
	gYpNamedAt.removeAt(uint(s));
	gYpWreckAt.removeAt(uint(s));
	gYpPushed.removeAt(uint(s));
}

AIFloat3 FacingDir(int f)
{
	return (f == 0) ? AIFloat3(0.f, 0.f, 1.f)
			: (f == 1) ? AIFloat3(1.f, 0.f, 0.f)
			: (f == 2) ? AIFloat3(0.f, 0.f, -1.f) : AIFloat3(-1.f, 0.f, 0.f);
}

// Every turret that reaches `t`, put on one DLL task eating it: a raw order was
// overwritten within seconds by the turret's own repair or wait task.
int NanosEat(CCircuitUnit@ t, int share)
{
	if ((t is null) || (t.circuitDef is null))
		return 0;
	return ai.TurretsReclaim(t, int((60.f + Catalog::gCostM[int(t.circuitDef.id)] / 90.f) * float(SECOND)), share);
}

void YardWatch()
{
	const uint np = Factory::gFacUnits.length();
	if (np == 0)
		return;
	if (gYdCursor >= np)
		gYdCursor = 0;
	CCircuitUnit@ fac = Factory::gFacUnits[gYdCursor++];
	YardCensusLog(np);
	if ((fac is null) || (fac.circuitDef is null))
		return;
	const int fd = int(fac.circuitDef.id);
	if (Market::AirPlant(fd) || (Catalog::gBuildsList[fd].length() == 0))
		return;
	const int facing = fac.GetFacing();
	if (facing < 0)
		return;
	const AIFloat3 fp = fac.GetPos(ai.frame);
	const AIFloat3 dir = FacingDir(facing);
	const float halfD = float(((facing & 1) == 0) ? Catalog::gFootZ[fd] : Catalog::gFootX[fd]) * 8.f;
	const float halfW = float(((facing & 1) == 0) ? Catalog::gFootX[fd] : Catalog::gFootZ[fd]) * 8.f;
	const float reachR = halfD + 2.f * halfW + 32.f;
	const int now = ai.frame;

	// Who stands on the footprint, and who in the apron right outside the door.
	array<CCircuitUnit@> inside;
	array<CCircuitUnit@> apron;
	for (uint cd = 1; cd < Market::gOwnCount.length(); ++cd) {
		if ((Market::gOwnCount[cd] <= 0) || !Catalog::gMobile[int(cd)] || Catalog::gFlyer[int(cd)])
			continue;
		array<CCircuitUnit@>@ near = ai.GetOwnUnitsOfDef(Catalog::Def(int(cd)), fp, reachR);
		if (near is null)
			continue;
		for (uint i = 0; i < near.length(); ++i) {
			if (near[i] is null)
				continue;
			const AIFloat3 rb = near[i].GetPos(now) - fp;
			const float al = rb.x * dir.x + rb.z * dir.z;
			const float ac = abs(rb.x * dir.z - rb.z * dir.x);
			if ((abs(al) <= halfD) && (ac <= halfW))
				inside.insertLast(near[i]);
			else if ((al > halfD) && (al <= halfD + 2.f * halfW) && (ac <= halfW)
				&& !Catalog::gBuilder[int(cd)])
				apron.insertLast(near[i]);
		}
	}

	// Only the footprint decides a jam: army standing at a door walks back to it
	// after a push, and read as stuck it cost a converter and two jammers in a
	// normal game. A sealed pocket still shows here once the plant has filled it.
	// The apron is tracked so the push and the victim can include it.
	array<CCircuitUnit@> res = inside;
	for (uint i = 0; i < apron.length(); ++i)
		res.insertLast(apron[i]);
	int oldestIn = now;
	float slowest = 0.f;
	for (uint i = 0; i < res.length(); ++i) {
		const Id uid = res[i].id;
		int slot = -1;
		for (uint k = 0; (k < gYdUnit.length()) && (slot < 0); ++k) {
			if ((gYdUnit[k] == uid) && (gYdPlant[k] == fac.id))
				slot = int(k);
		}
		if (slot < 0) {
			gYdUnit.insertLast(uid);
			gYdPlant.insertLast(fac.id);
			gYdSince.insertLast(now);
			gYdSeen.insertLast(now);
			continue;
		}
		gYdSeen[slot] = now;
		if ((i < inside.length()) && (gYdSince[slot] < oldestIn))
			oldestIn = gYdSince[slot];
		const float sp = Catalog::gSpeed[int(res[i].circuitDef.id)];
		if ((sp > 0.f) && ((slowest <= 0.f) || (sp < slowest)))
			slowest = sp;
	}
	for (uint k = 0; k < gYdUnit.length(); ) {
		// Not seen on this visit, or its plant gone from the cycle long ago.
		if (((gYdPlant[k] == fac.id) && (gYdSeen[k] != now))
			|| (now - gYdSeen[k] > int(4 * np + 60) * SECOND))
		{
			gYdUnit.removeAt(k);
			gYdPlant.removeAt(k);
			gYdSince.removeAt(k);
			gYdSeen.removeAt(k);
			continue;
		}
		++k;
	}
	if ((slowest <= 0.f) || (oldestIn >= now)) {
		YardClear(fac.id);
		return;
	}
	// Long enough to have walked off the footprint and through the apron three
	// times over. Not plus the order lag: its maximum at bench speed made this
	// 97-114 s on a T1 lab, and a push not yet applied is simply repeated.
	const float crossS = (2.f * halfD + 2.f * halfW) / slowest;
	const int limit = int(3.f * crossS * float(SECOND));
	const int age = now - oldestIn;
	if (age < limit)
		return;
	if (age / SECOND > gYdWorstS)
		gYdWorstS = age / SECOND;
	int s = YardSlot(fac.id);
	if (s < 0) {
		gYpPlant.insertLast(fac.id);
		gYpActAt.insertLast(0);
		gYpActs.insertLast(0);
		gYpEating.insertLast(0);
		gYpNamed.insertLast(false);
		gYpNamedAt.insertLast(0);
		gYpWreckAt.insertLast(0);
		gYpPushed.insertLast(false);
		s = int(gYpPlant.length()) - 1;
		++gYdJams;
	}
	if (now < gYpActAt[s])
		return;
	gYpActAt[s] = now + limit;

	// 1. Everything of ours on the footprint walks out the door, past the
	// apron; everything in the apron steps clear of it. A unit the DLL stopped
	// on a burst of move failures (CircuitAI::UnitMoveFailed) has no order and
	// would otherwise stand there for good.
	int pushed = 0;
	const AIFloat3 exitTo = fp + dir * (halfD + 2.f * halfW + 48.f);
	for (uint i = 0; i < inside.length(); ++i) {
		if (OnMap(exitTo) && !Military::StockQuietUnit(inside[i], "yard")) {
			inside[i].CmdMoveTo(exitTo);
			++pushed;
		}
	}
	for (uint i = 0; i < apron.length(); ++i) {
		AIFloat3 away = apron[i].GetPos(now) - fp;
		away.y = 0.f;
		away.SafeNormalize2D();
		const AIFloat3 to = apron[i].GetPos(now) + away * (2.f * halfW);
		if (OnMap(to) && !Military::StockQuietUnit(apron[i], "yard")) {
			apron[i].CmdMoveTo(to);
			++pushed;
		}
	}
	gYdPushed += pushed;
	// The first act only pushes: a crowd at a door clears on its own, and eating
	// on the first reading cost a converter and an advanced solar in normal games.
	if (!gYpPushed[s]) {
		gYpPushed[s] = true;
		AiLog(Factory::T() + "apex: yard jammed " + fac.circuitDef.GetName() + " #" + fac.id
			+ " facing=" + facing + " inside=" + inside.length() + " apron=" + apron.length()
			+ " age=" + (age / SECOND) + "s limit=" + (limit / SECOND) + "s pushed=" + pushed + " (push only)");
		return;
	}

	// 2. Our buildings in the door strip are eaten. The strip starts one plant
	// width deep and reaches one width further each time the jam outlives the
	// buildings already eaten -- a nano block in front of a door is rings deep.
	// A strip that held nothing of ours is not extended: the cause is elsewhere.
	// Never a mex or another plant; while the last act's buildings still stand,
	// they are what is being waited on.
	CCircuitUnit@ eating = (gYpEating[s] != 0) ? ai.GetTeamUnit(gYpEating[s]) : null;
	if ((eating is null) || (eating.circuitDef is null)) {
		gYpEating[s] = 0;
		if ((gYpActs[s] == 0) || gYpNamed[s])
			++gYpActs[s];
	}
	const float depth = 2.f * halfW * float(gYpActs[s]);
	array<CCircuitUnit@>@ st = ai.GetOwnStructsNear(fp, halfD + depth + 2.f * halfW);
	int structs = 0, nanos = 0, offered = 0;
	string eaten = "";
	Id victim = res[0].id;
	array<CCircuitUnit@> named;
	if (st !is null) {
		for (uint i = 0; i < st.length(); ++i) {
			CCircuitUnit@ b = st[i];
			if ((b is null) || (b.id == fac.id) || (b.circuitDef is null))
				continue;
			const int bd = int(b.circuitDef.id);
			const AIFloat3 rel = b.GetPos(now) - fp;
			const float along = rel.x * dir.x + rel.z * dir.z;
			const float across = abs(rel.x * dir.z - rel.z * dir.x);
			const float sr = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd])
					? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 8.f;
			if ((along + sr < halfD) || (along - sr > halfD + depth) || (across - sr > halfW))
				continue;
			if (b.circuitDef.IsMex() || (Catalog::gBuildsList[bd].length() > 0))
				continue;
			named.insertLast(b);
		}
	}
	for (uint i = 0; i < named.length(); ++i) {
		CCircuitUnit@ b = named[i];
		++structs;
		const int n = NanosEat(b, int(named.length() - i));
		nanos += n;
		if (n == 0) {
			Military::NotePenVerdict(victim, b.id, b.GetPos(now), dir, PlantFlowM(fac, res[0]));
			++offered;
		}
		if (gYpEating[s] == 0)
			gYpEating[s] = b.id;
		eaten += " " + b.circuitDef.GetName() + (n > 0 ? ("x" + n) : "@mkt");
	}
	// WRECKS IN THE DOOR (his 10-13: the vehicle lab stuck behind wrecks): a
	// tank cannot cross one, and nothing above names a feature. The nearest
	// hand sweeps the strip, at most every 15 s.
	string swept = "";
	if ((structs == 0) && (now >= gYpWreckAt[s])) {
		const AIFloat3 sc = fp + dir * (halfD + 0.5f * depth + halfW);
		const float sr = halfW + 0.5f * depth + halfW;
		if (OnMap(sc) && (ai.GetWreckValueAt(sc, sr) > 0.f)) {
			CCircuitUnit@ hand = null;
			float best = 1e30f;
			for (uint i = 0; i < Market::gWorkers.length(); ++i) {
				CCircuitUnit@ w = Market::gWorkers[i];
				if ((w is null) || w.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
					continue;
				const float dd = w.GetPos(now).distance2D(sc);
				if (dd < best) {
					best = dd;
					@hand = w;
				}
			}
			if (hand !is null) {
				IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, sc,
						1000.f, 30 * SECOND, sr, true));
				if (t !is null) {
					aiBuilderMgr.AssignTask(hand, t);
					++gYdWreck;
					gYpWreckAt[s] = now + 15 * SECOND;
					swept = " wreck-sweep=" + hand.circuitDef.GetName() + "#" + hand.id + " d=" + int(best);
				}
			}
		}
	}
	gYpNamed[s] = (structs > 0);
	if (structs > 0)
		gYpNamedAt[s] = now;
	gYdNanoSent += nanos;
	gYdOffered += offered;

	// 3. Nothing of ours in the way and pushing has not freed it: terrain or a
	// crowd holds the door, and the plant itself goes (apexearth: a blocked
	// plant reclaims its doorstep or itself). Its footprint opens the yard,
	// and the plant market rebuys a lab where a door faces open ground --
	// eating the trapped units only made room for the next one.
	string ate = "";
	// Nothing of ours in the strip: a teammate's building there is asked for
	// before the plant itself goes.
	if (structs == 0) {
		array<float>@ al = ai.GetAllyStructsNear(fp, halfD + depth + 2.f * halfW);
		for (uint i = 0; (al !is null) && (i + 4 < al.length()); i += 5) {
			const int bd = int(al[i + 2]);
			if (!Catalog::ValidId(bd) || (Catalog::gBuildsList[bd].length() > 0))
				continue;
			const float sr = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd]) ? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 8.f;
			const float rx = al[i] - fp.x, rz = al[i + 1] - fp.z;
			const float along = rx * dir.x + rz * dir.z;
			const float across = abs(rx * dir.z - rz * dir.x);
			if ((along + sr < halfD) || (along - sr > halfD + depth) || (across - sr > halfW))
				continue;
			if (Military::AskAllyReclaim(int(al[i + 3]), int(al[i + 4]), PlantFlowM(fac, res[0]))) {
				structs = 1;
				gYpNamedAt[s] = now;
				eaten += " " + Catalog::Def(bd).GetName() + "@t" + int(al[i + 4]);
				break;
			}
		}
	}
	// Twice the crossing limit is seconds for a hover; the plant is a last
	// resort, so it waits at least as long as a penned unit's test does.
	const int eatAfter = (2 * limit > Military::UNBLOCK_STILL) ? (2 * limit) : Military::UNBLOCK_STILL;
	if ((structs == 0) && (age >= eatAfter) && (now - gYpNamedAt[s] >= 2 * limit)) {
		++gYdTerrain;
		const int n = NanosEat(fac, 1);
		if (n > 0) {
			++gYdUnitEat;
			ate = " " + fac.circuitDef.GetName() + "x" + n;
		} else {
			Military::NotePenVerdict(victim, fac.id, fp, dir, PlantFlowM(fac, res[0]));
			++gYdOffered;
			ate = " " + fac.circuitDef.GetName() + "@mkt";
		}
	}

	AiLog(Factory::T() + "apex: yard jammed " + fac.circuitDef.GetName() + " #" + fac.id
		+ " facing=" + facing + " inside=" + inside.length() + " apron=" + apron.length()
		+ " age=" + (age / SECOND) + "s limit=" + (limit / SECOND) + "s act=" + gYpActs[s]
		+ " pushed=" + pushed + " strip=" + int(depth) + " eat=[" + eaten + " ]"
		+ (ate.length() > 0 ? (" plant-eat=[" + ate + " ]") : "")
		+ ((structs == 0) ? " nothing-named" : "") + swept);
}

// What a jammed plant stops putting into the field each second: its own build
// power on what it was making. Turret assist is left out -- a floor, not a guess.
float PlantFlowM(CCircuitUnit@ fac, CCircuitUnit@ made)
{
	if ((fac is null) || (made is null) || (made.circuitDef is null))
		return 0.f;
	const int ud = int(made.circuitDef.id);
	const float bt = Catalog::gBuildTime[ud];
	if (bt <= 0.f)
		return 0.f;
	return Catalog::gBuildPower[int(fac.circuitDef.id)] * Catalog::gCostM[ud] / bt;
}

void YardCensusLog(uint np)
{
	if (ai.frame < gYdLogAt)
		return;
	gYdLogAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: yard census plants=" + np + " watched=" + gYdUnit.length()
		+ " jammed-now=" + gYpPlant.length() + " worst=" + gYdWorstS + "s"
		+ " | jams=" + gYdJams + " pushed=" + gYdPushed + " nano-eat=" + gYdNanoSent
		+ " offered=" + gYdOffered + " nothing-named=" + gYdTerrain + " plant-eat=" + gYdUnitEat + " wreck-sweep=" + gYdWreck);
	gYdWorstS = 0;
}

//------------------------------------------------------------------------------
// CAN A UNIT LEAVING THIS PLANT'S DOOR GET OUT? (his 10-30 crowd game: a teammate's anti-air shut a T2 lab's way out,
// and the yard watch above, which sees only units standing ON a plant, counted no jam all game.) The engine's own
// pathing, which sees every building, from the door toward the enemy (C++ FacExitGap): `gap` is how far short
// the path stops. One plant per FX_STEP, so each is checked about every FX_STEP x plants; a shut one is logged with
// what stands where the path stops, ours and allies'.
//------------------------------------------------------------------------------

const int FX_STEP = 3 * SECOND;
const float FX_SHUT = 256.f;   // a stop this far from the bus end is reported (the end is a sector point, ~one sector)
int gFxNextAt = 0;
uint gFxCursor = 0;
int gFxChecked = 0, gFxShut = 0, gFxNoPath = 0;
float gFxWorst = 0.f;
int gFxLogAt = 0;

void FacExitWatch()
{
	if (ai.frame < gFxNextAt)
		return;
	gFxNextAt = ai.frame + FX_STEP;
	const uint n = Factory::gFacUnits.length();
	if (ai.frame >= gFxLogAt) {
		gFxLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: facexit-stat t=" + ai.teamId + " plants=" + n + " checked=" + gFxChecked + " shut=" + gFxShut
			+ " cured=" + gFxCured + " asked=" + gFxAsked + " offered=" + gFxOffered
			+ " nopath=" + gFxNoPath + " worstGap=" + int(gFxWorst));
		gFxChecked = 0;
		gFxShut = 0;
		gFxNoPath = 0;
		gFxWorst = 0.f;
	}
	if (n == 0)
		return;
	gFxCursor = (gFxCursor + 1) % n;
	CCircuitUnit@ f = Factory::gFacUnits[gFxCursor];
	if ((f is null) || (f.circuitDef is null) || Market::AirPlant(int(f.circuitDef.id)))
		return;
	// toward the enemy, not to the bus end: that end is one sector out of the door (crowd6: 383 from it), so a pocket
	// wider than a sector read open
	AIFloat3 goal = Front::FoeAnchor();
	if (!OnMap(goal))
		goal = AIFloat3(0.5f * float(AiTerrainWidth()), 0.f, 0.5f * float(AiTerrainHeight()));
	AIFloat3 door, stop;
	const float gap = ai.FacExitGap(f, goal, door, stop);
	if (gap < 0.f) {
		++gFxNoPath;
		return;
	}
	++gFxChecked;
	if (gap > gFxWorst)
		gFxWorst = gap;
	if (gap <= FX_SHUT)
		return;
	++gFxShut;
	string near;
	array<CCircuitUnit@>@ own = ai.GetOwnStructsNear(stop, 160.f);
	for (uint i = 0; (own !is null) && (i < own.length()) && (near.length() < 140); ++i) {
		if ((own[i] !is null) && (own[i].circuitDef !is null))
			near += " " + own[i].circuitDef.GetName() + "@t" + ai.teamId;
	}
	array<float>@ al = ai.GetAllyStructsNear(stop, 160.f);
	for (uint i = 0; (al !is null) && (i + 4 < al.length()) && (near.length() < 240); i += 5) {
		const int bd = int(al[i + 2]);
		if (Catalog::ValidId(bd))
			near += " " + Catalog::Def(bd).GetName() + "@t" + int(al[i + 4]);
	}
	AiLog("apex: fac-exit-shut t=" + ai.teamId + " " + f.circuitDef.GetName() + "#" + f.id
		+ " door=" + int(door.x) + "," + int(door.z) + " goal=" + int(goal.x) + "," + int(goal.z)
		+ " stop=" + int(stop.x) + "," + int(stop.z) + " gap=" + int(gap) + " near=" + near);
	// PENNED: the path stops nearer the door than the goal (a path that crosses the map and stops beside the target
	// is terrain there). Twice running, the buildings where it stops are eaten (crowd7: 6 plants penned for 3-11
	// minutes, by teammates' AA, nano turrets, solars and converters as much as by our own).
	if (door.distance2D(stop) >= gap)
		return;
	const int k = gFxPenPlant.find(int(f.id));
	if (k < 0) {
		gFxPenPlant.insertLast(int(f.id));
		gFxPenSeen.insertLast(1);
		gFxPenActAt.insertLast(0);
		return;
	}
	++gFxPenSeen[uint(k)];
	if ((gFxPenSeen[uint(k)] < 2) || (ai.frame < gFxPenActAt[uint(k)]))
		return;
	gFxPenActAt[uint(k)] = ai.frame + 30 * SECOND;
	FacExitCure(f, stop, door);
}

array<int> gFxPenPlant;    // a plant found penned
array<int> gFxPenSeen;     // ...checks it has been found so
array<int> gFxPenActAt;    // ...earliest frame of its next cure
int gFxCured = 0, gFxAsked = 0, gFxOffered = 0;

// What the plant puts into the field each second while it can: its build power on the mean of what it makes.
float FacFlowM(CCircuitUnit@ fac)
{
	const int fd = int(fac.circuitDef.id);
	const array<int>@ b = Catalog::gBuildsList[fd];
	float sum = 0.f;
	int n = 0;
	for (uint i = 0; i < b.length(); ++i) {
		if (!Catalog::gMobile[b[i]] || (Catalog::gBuildTime[b[i]] <= 0.f))
			continue;
		sum += Catalog::gCostM[b[i]] / Catalog::gBuildTime[b[i]];
		++n;
	}
	return (n > 0) ? (Catalog::gBuildPower[fd] * sum / float(n)) : 0.f;
}

// The buildings where a penned plant's path stops: ours eaten by the turrets in reach, or offered to the reclaim market
// at the plant's flow; a teammate's asked of its owner (one of our bots), as the yard watch asks for a door strip. No
// plant is eaten here: a plant against a plant is the plot's and the yard's call.
void FacExitCure(CCircuitUnit@ f, const AIFloat3& in stop, const AIFloat3& in door)
{
	const float flow = FacFlowM(f);
	const AIFloat3 dir = (stop.distance2D(door) > 1.f) ? (stop - door) / stop.distance2D(door) : AIFloat3(0.f, 0.f, 1.f);
	string ate;
	array<CCircuitUnit@>@ own = ai.GetOwnStructsNear(stop, 160.f);
	for (uint i = 0; (own !is null) && (i < own.length()); ++i) {
		CCircuitUnit@ b = own[i];
		if ((b is null) || (b.circuitDef is null) || (b is f) || (Catalog::gBuildsList[int(b.circuitDef.id)].length() > 0)
			|| (Catalog::gExtractsM[int(b.circuitDef.id)] > 0.f))
			continue;
		const int n = NanosEat(b, 1);
		if (n == 0) {
			Military::NotePenVerdict(f.id, b.id, b.GetPos(ai.frame), dir, flow);
			++gFxOffered;
		}
		++gFxCured;
		ate += " " + b.circuitDef.GetName() + ((n > 0) ? ("x" + n) : "@mkt");
	}
	array<float>@ al = ai.GetAllyStructsNear(stop, 160.f);
	for (uint i = 0; (al !is null) && (i + 4 < al.length()); i += 5) {
		const int bd = int(al[i + 2]);
		if (!Catalog::ValidId(bd) || (Catalog::gBuildsList[bd].length() > 0) || (Catalog::gExtractsM[bd] > 0.f))
			continue;
		if (Military::AskAllyReclaim(int(al[i + 3]), int(al[i + 4]), flow)) {
			++gFxAsked;
			ate += " " + Catalog::Def(bd).GetName() + "@t" + int(al[i + 4]);
			break;   // one ask per team board slot at a time
		}
	}
	AiLog("apex: fac-exit-cure t=" + ai.teamId + " " + f.circuitDef.GetName() + "#" + f.id + " flow="
		+ formatFloat(flow, "", 0, 2) + " ate=" + (ate.isEmpty() ? " none" : ate));
}

}  // namespace Brain
