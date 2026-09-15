namespace Air {

float EnemyAACost()
{
	return aiEnemyMgr.GetEnemyCost(RT::AA);
}

// The AA ceiling is ABSOLUTE, and that shape lost finished games: a drawn 40m
// game stood the assassin down against 2.5k of AA while our army out-valued a
// bare-commander remnant 12:1 -- and the bombers are the only weapon in the
// stack that targets the enemy commander, the win condition. Dominance makes
// AA affordable: their field army gone AND their AA small next to our own army.
bool AADominated()
{
	const float k = ai.GetTunable("apex_air_dominance_aa", TUNE_AIR_DOMINANCE_AA);
	if (k <= 0.f)
		return false;
	const float ours = Military::TeamArmyCost();
	if (ours <= 1.f)
		return false;
	const float armyGone = ai.GetTunable("apex_air_dominance_army", TUNE_AIR_DOMINANCE_ARMY);
	return (Military::EnemyArmyCost() < ours * armyGone)
		&& (EnemyAACost() < ours * k);
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
	if (!IsAirLead())
		return false;
	if ((ai.frame < AIR_FROM) || !AirEcoReady())
		return false;
	// The absolute AA ceiling is GONE (it stood the assassin down against 2.5k
	// of AA in a game we had already won). AA is priced instead: it raises the
	// mass ScaledBombers asks for, and the wing grows while the next plane
	// pays (MarginalWorth) -- the whole-raid payoff test read a unit COUNT
	// against a metal bill and never armed.
	return Committed() || WingGrowing() || AADominated();
}

int Have(CCircuitDef@ def)
{
	return (def is null) ? 0 : def.count;
}

// The force is both tiers together: a basic bomber and an advanced one are both
// a bomber for the purpose of deciding whether we have enough to strike.
// EVERY tier counts: a heavy or an atomic bomber standing on the pad is part of
// the strike. Counting only the two original tiers left the wing permanently
// short of ScaledBombers(), so it would never read as massed.
int Bombers()  { return Have(gBomber) + Have(gBomber1) + Have(gBomberH) + Have(gBomberN); }
int Fighters() { return Have(gFighter) + Have(gFighter1); }

bool Massed()
{
	return (Bombers() >= ScaledBombers()) && (Fighters() >= ScaledFighters());
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
			&& (inc >= ai.GetTunable("apex_intel_air_income", TUNE_INTEL_AIR_INCOME)))
			return gPlant1;
		if (inc >= ai.GetTunable("apex_air_mandatory_income", TUNE_AIR_MANDATORY_INCOME))
			return gPlant1;
		// An enemy living on the water makes air the reachability answer, not a
		// luxury -- the lead's income bar applies to everyone then.
		if (Military::EnemyAfloat()
			&& (inc >= ai.GetTunable("apex_intel_air_income", TUNE_INTEL_AIR_INCOME)))
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
		int wantN = int(inc / ai.GetTunable("apex_adv_air_income", TUNE_ADV_AIR_INCOME));
		// AIR PLANTS FOLLOW MILITARY NEED -- the first included. apexearth
		// 2026-08-19, a 1v1 lost with <10% relative army, a silo and two T2
		// air labs: "I wouldn't even want to see a first T2 air lab." While
		// army spend is under its budget target the advanced air plant is a
		// luxury and waits -- UNLESS the enemy actually flies, in which case
		// the fighters that live here are themselves the military need.
		const bool armyFedA = Brain::ShareOf(Brain::ARMY)
				>= Brain::TargetShare(Brain::ARMY)
					* ai.GetTunable("apex_extra_plant_army", TUNE_EXTRA_PLANT_ARMY)
				// ...AND THE ARMY MUST STILL BE ALIVE. ShareOf(ARMY) counts metal
				// already spent, which survives the army being wiped -- so the
				// gate opened widest just after a lost fight. Standing army
				// against what the enemy fields closes it again.
				&& !Military::Outmassed();
		// ...except on the eco seat, whose army target is zero by design
		// and whose scaling IS the advanced air constructor (apexearth
		// 2026-09-14: "we really need to get on the ball here with making
		// air and using air cons").
		if (!armyFedA && (Military::AirThreatNow() <= 0.f) && !Market::EcoRoleGrowing())
			return null;
		if ((wantN > 1) && !armyFedA)
			wantN = 1;
		// At least one, once air is mandatory at all or the enemy is afloat:
		// torpedo bombers, fighters and the advanced air constructors all live
		// here, and a long game repeatedly ended with none (the income curve
		// alone reads 0 below 150 m/s, so the plant was never asked for).
		if ((wantN < 1)
			&& (Military::EnemyAfloat()
				|| (inc >= ai.GetTunable("apex_air_mandatory_income", TUNE_AIR_MANDATORY_INCOME))))
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
