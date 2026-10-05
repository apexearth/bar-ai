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

uint gYdCursor = 0;
int  gYdLogAt = 0;
int  gYdJams = 0, gYdPushed = 0, gYdNanoSent = 0, gYdOffered = 0, gYdUnitEat = 0;
int  gYdTerrain = 0;
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
		if (OnMap(exitTo)) {
			inside[i].CmdMoveTo(exitTo);
			++pushed;
		}
	}
	for (uint i = 0; i < apron.length(); ++i) {
		AIFloat3 away = apron[i].GetPos(now) - fp;
		away.y = 0.f;
		away.SafeNormalize2D();
		const AIFloat3 to = apron[i].GetPos(now) + away * (2.f * halfW);
		if (OnMap(to)) {
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
	gYpNamed[s] = (structs > 0);
	if (structs > 0)
		gYpNamedAt[s] = now;
	gYdNanoSent += nanos;
	gYdOffered += offered;

	// 3. Nothing of ours in the way and pushing has not freed it: terrain or a
	// crowd holds the door. The trapped unit goes when it is worth less than
	// the plant it blocks (apexearth: "if we have units that are stuck and
	// can't go anywhere then we should reclaim them"); never a builder.
	string ate = "";
	if ((structs == 0) && (age >= 2 * limit) && (now - gYpNamedAt[s] >= 2 * limit)) {
		++gYdTerrain;
		for (uint i = 0; i < inside.length(); ++i) {
			CCircuitUnit@ u = inside[i];
			const int ud = int(u.circuitDef.id);
			if (Catalog::gBuilder[ud] || (Catalog::gCostM[ud] >= Catalog::gCostM[fd]))
				continue;
			int since = now;
			for (uint k = 0; k < gYdUnit.length(); ++k) {
				if ((gYdUnit[k] == u.id) && (gYdPlant[k] == fac.id))
					since = gYdSince[k];
			}
			if (now - since < 2 * limit)
				continue;
			const int n = NanosEat(u, 1);
			if (n > 0) {
				++gYdUnitEat;
				ate += " " + u.circuitDef.GetName() + "x" + n;
			}
		}
	}

	AiLog(Factory::T() + "apex: yard jammed " + fac.circuitDef.GetName() + " #" + fac.id
		+ " facing=" + facing + " inside=" + inside.length() + " apron=" + apron.length()
		+ " age=" + (age / SECOND) + "s limit=" + (limit / SECOND) + "s act=" + gYpActs[s]
		+ " pushed=" + pushed + " strip=" + int(depth) + " eat=[" + eaten + " ]"
		+ (ate.length() > 0 ? (" unit-eat=[" + ate + " ]") : "")
		+ ((structs == 0) ? " nothing-named" : ""));
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
		+ " offered=" + gYdOffered + " nothing-named=" + gYdTerrain + " unit-eat=" + gYdUnitEat);
	gYdWorstS = 0;
}

}  // namespace Brain
