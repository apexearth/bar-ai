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

// Everything airborne right now becomes the wave. Called from Release().
void BuildWave()
{
	gWave.resize(0);
	gRunWave.resize(0);
	gWaveBombers = 0;
	gWaveMass = 0.f;
	gWaveFighters = 0;
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
int HeldFighters() { const int n = Fighters() - gWaveFighters; return (n < 0) ? 0 : n; }

// The run is over -- bring the survivors back so they mass with what was built
// while they were away, instead of hovering wherever the last bomb dropped.
void RecallWave()
{
	if (!Builder::gHomeSet)
		return;
	for (int i = 0; i < 6; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if ((us[k] !is null) && InWave(us[k].id))
				us[k].CmdMoveTo(Builder::gHomePos);
		}
	}
}

}  // namespace Air
