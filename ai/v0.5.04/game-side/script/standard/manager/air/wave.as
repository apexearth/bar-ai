namespace Air {

//------------------------------------------------------------------------------
// THE WAVE ROSTER. A strike owns the aircraft that were standing when it
// launched, and nothing else. Without this, gStrike alone opened HoldsUnit for
// every plane, so each one built during a run left the pad alone into airspace
// the wave had already stirred up -- and, because ReArm counted TOTAL bombers,
// that same trickle held the count above the spent bar and the strike never
// re-armed. One wave, then a full rebuild, is worth more than a permanent
// dribble of the same metal.
//------------------------------------------------------------------------------

// The six defs a strike can be made of, in one place so the roster, the hold
// gate and the survivor count cannot drift apart. Indices 0-3 are bombers.
CCircuitDef@ StrikeDef(int i)
{
	if (i == 0) return gBomberH;
	if (i == 1) return gBomber;
	if (i == 2) return gBomber1;
	if (i == 3) return gBomberN;
	if (i == 4) return gFighter;
	if (i == 5) return gFighter1;
	return null;
}

bool InList(const array<Id>@ l, Id id)
{
	if (l is null)
		return false;
	for (uint i = 0; i < l.length(); ++i) {
		if (l[i] == id)
			return true;
	}
	return false;
}

bool InWave(Id id)
{
	return InList(gWave, id);
}

// The wave's bomb tasks, one per bomber type, each made on its first arrival and closed to all but the wave
// (Military::JwCommit): a bomber finished after the launch is held for the next wave.
array<IUnitTask@> gStrikeT;
array<int> gStrikeTDef;

bool StrikeHolds(CCircuitUnit@ unit)
{
	return Military::AirGthOn() && gStrike && InWave(unit.id);
}

IUnitTask@ StrikeTask(CCircuitUnit@ unit)
{
	if (!StrikeHolds(unit))
		return null;
	const int d = int(unit.circuitDef.id);
	for (uint i = 0; i < gStrikeT.length(); ++i) {
		if ((gStrikeTDef[i] == d) && (gStrikeT[i] !is null) && !gStrikeT[i].IsDead())
			return gStrikeT[i];
	}
	IUnitTask@ t = aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::BOMB));
	if (t is null)
		return null;
	Military::JwCommitIds(t, gWave, int(unit.id));
	gStrikeT.insertLast(t);
	gStrikeTDef.insertLast(d);
	return t;
}

// A wave fighter's guard on its bomber: made at the launch, it takes the wave's fighters only.
IUnitTask@ WaveCoverTask(CCircuitUnit@ b, CCircuitUnit@ unit)
{
	IUnitTask@ t = aiMilitaryMgr.Enqueue(TaskF::Guard(b));
	if ((t is null) || t.IsJoinCommitted())
		return t;
	array<CCircuitUnit@>@ on = t.GetUnits();
	if ((on is null) || (on.length() == 0))
		Military::JwCommitIds(t, gWave, int(unit.id));
	return t;
}

// Everything airborne right now becomes the wave. Called from Release().
void BuildWave()
{
	gStrikeT.resize(0);
	gStrikeTDef.resize(0);
	gWave.resize(0);
	gRunWave.resize(0);
	gWaveBombers = 0;
	gWaveMass = 0.f;
	gWaveFighters = 0;
	// apex_gather: the wave is what stands where it gathers (the team rally, else home); a plane elsewhere --
	// still flying in, or handed over at an ally's base -- is sent there for the next wave
	const bool gth = Military::AirGthOn();
	const bool atRally = TairOn() && (TairPhase() != TA_PH_NONE);
	const AIFloat3 gatherAt = atRally ? TairRally() : Builder::gHomePos;
	float gatherR = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R) * 1.5f;
	if (!atRally && (aiMilitaryMgr.GetBaseDefRange() > gatherR))
		gatherR = aiMilitaryMgr.GetBaseDefRange();
	int away = 0;
	for (int i = 0; i < 6; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] is null) || Covering(us[k].id))
				continue;
			if (gth && OnMap(gatherAt) && (us[k].GetPos(ai.frame).distance2D(gatherAt) > gatherR)) {
				IUnitTask@ ut = us[k].task;
				if (((ut is null) || (ut.GetType() == Task::Type::IDLE)) && (us[k].CmdQueueSize() == 0))
					us[k].CmdMoveTo(gatherAt);
				++away;
				continue;
			}
			gWave.insertLast(us[k].id);
			if (i < 4) {
				gRunWave.insertLast(us[k].id);
				++gWaveBombers;
				gWaveMass += BomberUnits(d);
			} else {
				++gWaveFighters;
			}
		}
	}
	Military::JwRefused(int(Task::FightType::BOMB), away);
}

// The wave's combined threat value, the mass the bomb task weighs AA against.
float WavePower()
{
	float p = 0.f;
	for (int i = 0; i < 4; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && InWave(us[k].id))
				p += Catalog::gPower[int(d.id)];
		}
	}
	return p;
}

// Prune the roster to what is still flying. Death is the only way out of it, so
// this is also what tells ReArm the run is over.
void ScanWave()
{
	if (gWave.length() == 0) {
		gWaveBombers = 0;
		gWaveMass = 0.f;
		gWaveFighters = 0;
		return;
	}
	array<Id> alive;
	int bomb = 0;
	float mass = 0.f;
	int fight = 0;
	for (int i = 0; i < 6; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] is null) || !InWave(us[k].id))
				continue;
			alive.insertLast(us[k].id);
			if (i < 4) { ++bomb; mass += BomberUnits(d); } else ++fight;
		}
	}
	gWave = alive;
	gWaveBombers = bomb;
	gWaveMass = mass;
	gWaveFighters = fight;
}

// Bombers of the SCORED run still alive. Separate from the roster because the
// run settles on its own clock and the roster is cleared when the strike ends.
int RunSurvivors()
{
	if (gRunWave.length() == 0)
		return 0;
	int n = 0;
	for (int i = 0; i < 4; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && InList(gRunWave, us[k].id))
				++n;
		}
	}
	return n;
}

// Bombers/fighters standing at home, i.e. NOT part of the wave that is out.
// THE WING IS WEIGHED, NOT COUNTED. The bars (ScaledBombers, the deadline)
// were laid out in advanced-bomber units; a heavy gunship counted as ONE of
// them, so nine Tyrannus -- 50k of air -- sat at home for a dozen minutes
// under a bar of 22 (apexearth 2026-09-14: "when are we going to use it? It
// is very boring"). Every bomber def weighs its cost over the advanced
// bomber's; held and flown are compared in those units.
float gWaveMass = 0.f;
float BomberUnits(CCircuitDef@ d)
{
	// The atomic bomber is its own strike (atomic.as): read as ten Phoenixes
	// of mass, one Liche sent a four-plane wave at the deadline bar.
	if ((d is null) || IsAtomicDef(int(d.id)))
		return 0.f;
	const float unit = ((gBomber !is null) && (Catalog::gCostM[int(gBomber.id)] > 1.f))
			? Catalog::gCostM[int(gBomber.id)] : 1000.f;
	const float w = Catalog::gCostM[int(d.id)] / unit;
	return (w < 1.f) ? 1.f : w;
}
float BomberMass()
{
	return float(Have(gBomber)) * BomberUnits(gBomber) + float(Have(gBomber1)) * BomberUnits(gBomber1)
		+ float(Have(gBomberH)) * BomberUnits(gBomberH) + float(Have(gBomberN)) * BomberUnits(gBomberN);
}
int HeldBombers()  { const float n = BomberMass() - gWaveMass;  return (n < 0.f) ? 0 : int(n); }

// Finished bombers at home, weighed: def.count includes nanoframes, which no
// wave can take, so one Dragon frame read as 16 bombers home and recalled the
// wave every second.
float StandingHeldMass()
{
	float m = 0.f;
	for (int i = 0; i < 4; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && !InWave(us[k].id))
				m += BomberUnits(d);
		}
	}
	return m;
}
int HeldFighters() { const int n = Fighters() - gWaveFighters; return (n < 0) ? 0 : n; }

// Finished fighters free to fly with the next wave: not out on one, not
// covering, not scouting, not hunting.
int ReadyFighters()
{
	int n = 0;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter : gFighter1;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(fd, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && !InWave(us[k].id) && !Covering(us[k].id)
				&& (FlightOutIdx(us[k].id) < 0) && !InList(gHunters, us[k].id))
				++n;
		}
	}
	return n;
}

// The escort a wave waits for: the lead's whole ratio, a home wave half of
// it, as the home wave is half the lead's bombers.
int EscortWant()
{
	const int f = ScaledFighters();
	return EvEscortCap(IsAirLead() ? f : ((f + 1) / 2));
}

// The run is over -- bring the survivors back so they mass with what was built
// while they were away, instead of hovering wherever the last bomb dropped.
void RecallWave()
{
	if (!Builder::gHomeSet)
		return;
	int kept = 0;
	for (int i = 0; i < 6; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] is null) || !InWave(us[k].id))
				continue;
			// Past the point of no return the bomb task presses on; a raw move
			// home here only flip-flops against it (the wave "circling").
			const AIFloat3 at = us[k].GetPos(ai.frame);
			if (gStrikeHas && (RouteThreat(us[k], at, Builder::gHomePos)
					> RouteThreat(us[k], at, gStrikeAt))) {
				++kept;
				continue;
			}
			us[k].CmdMoveTo(Builder::gHomePos);
		}
	}
	if (kept > 0)
		AiLog(Factory::T() + "apex: air recall -- " + kept
			+ " bombers past the point of no return press on");
}

}  // namespace Air
