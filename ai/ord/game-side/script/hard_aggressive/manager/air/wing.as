namespace Air {

float EnemyAACost()
{
	return aiEnemyMgr.GetEnemyCost(RT::AA);
}

bool Committed()
{
	return gCommitFrame >= 0;
}

// May this instance act on the strategy at all? Once committed the AA ceiling
// stops being checked here -- a wall that goes up mid-buildup is handled by the
// abort branch in Update(), which decides between striking early and standing
// down rather than simply freezing production.
bool Armed()
{
	if (gAbort || !IsAirLead())
		return false;
	if (ai.frame < AIR_FROM)
		return false;
	return Committed() || (EnemyAACost() <= AIR_AA_CEILING);
}

int Have(CCircuitDef@ def)
{
	return (def is null) ? 0 : def.count;
}

// The force is both tiers together: a basic bomber and an advanced one are both
// a bomber for the purpose of deciding whether we have enough to strike.
int Bombers()  { return Have(gBomber) + Have(gBomber1); }
int Fighters() { return Have(gFighter) + Have(gFighter1); }

bool Massed()
{
	return (Bombers() >= ScaledBombers()) && (Fighters() >= ScaledFighters());
}

bool HalfMassed()
{
	return (Bombers() * 2 >= ScaledBombers()) && (Fighters() * 2 >= ScaledFighters());
}

bool HaveAirCon()
{
	return (Have(gCon1) > 0) || (Have(gCon2) > 0);
}

// The next factory this strategy wants, or null.
//
// The T2 air plant is buildable by AIR constructors only -- armca/armaca,
// corca/coraca, legca/legaca -- and no ground constructor of any tier has it in
// its build options. The only source of an air constructor is the T1 air plant,
// so the plant chain is two steps, not one. Returning the T2 plant before an air
// con exists is the silent no-op CLAUDE.md warns about.
CCircuitDef@ FactoryToBuild()
{
	ResolveDefs();
	// A SECOND basic plant as soon as we are committed and short of a force.
	// Two plants is twice the aircraft per minute, and the strike is bounded by
	// minutes, not by metal -- 12 basic bombers is only ~1,800.
	//
	// This used to require the ADVANCED plant first. Measured in a hosted 11v13:
	// every sample read plants=1,0 -- the advanced plant never finished, so the
	// second basic one was never reachable, and four minutes of a single plant
	// is about six aircraft. The strike released on the deadline at 6 bombers
	// and 4 fighters against 12 and 8. Throughput has to come before tier.
	//
	// Gated on ECONOMY as well as commitment. apexearth, watching live:
	// "shouldn't make 2 t1 air labs at a t1 phase, just 1 max... you can have
	// more when economy is stronger." Committing is not the same as affording:
	// a second 690-metal plant during the T1 phase competes with the expansion
	// that pays for the aircraft, and two half-fed plants build no faster than
	// one fed one. The throughput argument above is right once the income is
	// there, which is what AIR_SECOND_PLANT_INCOME asks.
	if (Committed() && !Massed()
		&& (aiEconomyMgr.metal.income >= AIR_SECOND_PLANT_INCOME)
		&& (gPlant1 !is null) && gPlant1.IsAvailable(ai.frame) && (Have(gPlant1) == 1))
	{
		return gPlant1;
	}
	if ((gPlant2 is null) || !gPlant2.IsAvailable(ai.frame) || (Have(gPlant2) > 0))
		return null;
	if (Have(gPlant1) <= 0) {
		if ((gPlant1 is null) || !gPlant1.IsAvailable(ai.frame))
			return null;
		return gPlant1;
	}
	if (!HaveAirCon())
		return null;
	return gPlant2;
}

bool WantsFactory(const CCircuitDef@ facDef)
{
	if (!Armed() || (facDef is null))
		return false;
	CCircuitDef@ want = FactoryToBuild();
	return (want !is null) && (want.id == facDef.id);
}

// The advanced air plant has no entry in Opener::GetOpenInfo, so it falls back to
// the default queue -- three builders, a scout and five raiders. Those raiders are
// gunships that fly out and attack, which spends the surprise before there is
// anything to be surprising with.
bool SuppressesOpener(const CCircuitDef@ facDef)
{
	if (!Armed() || (facDef is null))
		return false;
	ResolveDefs();
	return (gPlant2 !is null) && (facDef.id == gPlant2.id);
}

// Stock reconsiders factories every AiRandom(550,900) seconds, which is longer
// than the whole window this strategy has. Probe instead -- but only while there
// is actually a plant outstanding, so the switch gate is not left open (a
// permanently-true isSwitchTime also disables EconomyManager's metal gate).
bool WantsSwitchProbe()
{
	if (!Armed() || (FactoryToBuild() is null))
		return false;
	if (ai.frame < gNextProbe)
		return false;
	gNextProbe = ai.frame + 20 * SECOND;
	return true;
}

}  // namespace Air
