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
	// NO SECOND BASIC PLANT, ever -- apexearth 2026-08-18: "stop us from
	// making 2 t1 air labs. We do it all the time", and the 80-income bar
	// here was "too low". Throughput comes from the T2 plant, which also
	// retires the T1 line's army floors the moment it stands.
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

// INTEL AIR, outside the strike strategy entirely. Scouts are eyes, not a
// strike, and the AA ceiling that rightly guards the strike commitment kept
// whole games at zero air -- apexearth, 60 minutes in: "we have not made any
// air... Air would help us understand the enemy strength." The air lead
// builds ONE basic plant once income is real; the facqueue scout floor mans
// it from there, and Armed()/the strike machinery stay untouched.
CCircuitDef@ IntelPlantToBuild()
{
	ResolveDefs();
	const float inc = aiEconomyMgr.metal.income;
	// The basic plant: the air lead builds the team's early one at intel income;
	// past apex_air_mandatory_income EVERY player owes themselves one -- air
	// constructors are the most efficient build power there is, and a mature
	// economy without them is leaving lathe on the table (apexearth: "An air lab
	// once we have 100s of metal per second should be mandatory").
	if ((gPlant1 !is null) && gPlant1.IsAvailable(ai.frame)
		&& (Have(gPlant1) == 0))
	{
		if (IsAirLead()
			&& (inc >= ai.GetTunable("apex_intel_air_income", 25.f)))
			return gPlant1;
		if (inc >= ai.GetTunable("apex_air_mandatory_income", 100.f))
			return gPlant1;
		// An enemy living on the water makes air the reachability answer, not a
		// luxury -- the lead's income bar applies to everyone then.
		if (Military::EnemyAfloat()
			&& (inc >= ai.GetTunable("apex_intel_air_income", 25.f)))
			return gPlant1;
		return null;
	}
	// The advanced plant, once an air con exists to place it (no ground
	// constructor of any tier has it -- see FactoryToBuild's comment). This is
	// where fighters and the advanced air constructors live; without it the
	// late game has neither. The count scales with income, one per
	// apex_adv_air_income of metal -- a rich economy wants several, and
	// PlantApproved's per-def curve still bounds it.
	if ((gPlant2 !is null) && gPlant2.IsAvailable(ai.frame) && HaveAirCon()) {
		int wantN = int(inc / ai.GetTunable("apex_adv_air_income", 150.f));
		// At least one, once air is mandatory at all or the enemy is afloat:
		// torpedo bombers, fighters and the advanced air constructors all live
		// here, and a long game repeatedly ended with none (the income curve
		// alone reads 0 below 150 m/s, so the plant was never asked for).
		if ((wantN < 1)
			&& (Military::EnemyAfloat()
				|| (inc >= ai.GetTunable("apex_air_mandatory_income", 100.f))))
			wantN = 1;
		if (Have(gPlant2) < wantN)
			return gPlant2;
	}
	return null;
}

bool WantsIntelPlant(const CCircuitDef@ facDef)
{
	CCircuitDef@ p = IntelPlantToBuild();
	return (p !is null) && (facDef !is null) && (p.id == facDef.id);
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
