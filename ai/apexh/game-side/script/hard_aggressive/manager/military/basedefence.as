namespace Military {

float ApproachThreat()
{
	return EnemyArmyCost();
}

// ORDERED BY WEAPON RANGE, ascending -- PorcToBuild takes the last affordable
// entry, so the order IS the preference. It used to pick the most expensive
// affordable def, which is not the same ordering and got it backwards: cormaw
// (290 metal) outbid corhllt (195) at every income, and reaches 410 elmos to
// corhllt's 480. A tower that cannot reach the thing shooting it is dead metal
// wherever it is placed, which is the other half of the placement complaint.
//
// The last entry of each list is the counter-battery tier. It is only ever
// reachable when the budget in PorcToBuild is opened up, which needs the enemy
// to have actually bought artillery.
// The pop-up turrets stay in the list because OurTowerValue counts it and
// build_chain still places them; ordered by range they can never be selected,
// since every entry after them is both longer-ranged and cheaper.
// The heavy tiers on the end are new. apexearth: "once t3 is on the field the
// older defenses start disappearing and we don't have enough jammers and T3 big
// boy defenses that can credibly defend against this stuff." The ladder stopped
// at the T2 counter-battery tier, so a base facing T3 had nothing left to build
// that could hurt it, and PorcToBuild simply kept re-picking a tower that dies
// to a Titan without firing.
//
// Costs from the pinned tree: armanni 3500, armbrtha 4500; cordoom 3000,
// corint 4600; legbastion 4200. PorcToBuild's budget is income x 30s (60s once
// the enemy owns artillery), so these cannot be reached on a small economy --
// they open up exactly when the income that makes T3 possible arrives.
//
// The T3 supers (armvulc 70000, corbuzz 68000, legstarfall 63000) are
// deliberately NOT here: at 30-60 seconds of income they would need 1000+
// metal/second to pass the budget, so listing them would be dead weight.
// The long-range plasma cannons -- armbrtha (Basilica) and corint -- are NOT
// here. This list is ordered by range ascending and PorcToBuild takes the LAST
// affordable entry, so putting an LRPC at the end made it win every defence
// request the moment the economy could reach it, and the actual T3 defence tower
// below it could never be picked. apexearth: "i see us mostly building
// Basilica's - the long range plasma cannon. Those aren't good for defense...
// We should make more units like the Pulsar."
//
// An LRPC is siege artillery, not something that holds ground. It still has its
// own route via the big_gun chain in build_chain.json; it just no longer
// masquerades as defence. Legion never had one in this list.
// armguard (Gauntlet, 1250) and corpun (Agitator, 1300) are NOT here. They are
// "Area Control Plasma Artillery" -- the T1.5 tier -- and this list is ordered by
// range ascending with PorcToBuild taking the LAST affordable entry, so from
// about 1,250 income-worth of budget upward they outranked armpb (680) and were
// the automatic pick until armanni (3500) came into reach. That is a wide band
// where every defence request bought one. apexearth: "we make too much t1.5
// artillery, they cost 1200 and are not worth it... t2 artillery is more
// worthwhile."
//
// Same mechanism as the Basilica removal above, one rung lower: a long-ranged
// entry at the end of a range-ordered list wins everything below it. The ladder
// is now pop-up gauss -> T3 tower.
// armamb (Rattlesnake, 2500) and cortoast (Persecutor, 2500) fill the rung
// between the pop-up gauss and the T3 tower. apexearth: "there is t2 defense
// better than a pitbull, we should prefer it" -- and, on the tier below it,
// "t2 artillery is more worthwhile" than the 1250-metal T1.5 plasma. Being last
// affordable before armanni/cordoom is what makes them the preferred pick across
// that whole income band.
array<string> PORC_NAMES_ARM = {"armclaw", "armllt", "armbeamer", "armhlt", "armpb", "armamb", "armanni"};
array<string> PORC_NAMES_COR = {"cormaw", "corllt", "corhllt", "corhlt", "corvipe", "cortoast", "cordoom"};
array<string> PORC_NAMES_LEG = {"legdtr", "leglht", "legmg", "legcluster", "legbastion"};

array<string>@ PorcNames()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return @PORC_NAMES_COR;
	if (side == "legion")
		return @PORC_NAMES_LEG;
	return @PORC_NAMES_ARM;
}

float OurTowerValue()
{
	array<string>@ names = PorcNames();
	float total = 0.f;
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if (d !is null)
			total += d.costM * float(d.count);
	}
	return total;
}

// A basic laser tower is outranged by the raiders it is meant to stop, so it
// dies without ever firing; the next tower up reaches past them. The floor
// exists because the seconds-of-income budget alone lands between the two.
const float PORC_MIN_BUDGET = 200.f;

// Seconds of income one front tower may cost. The second figure applies once the
// enemy has bought artillery, which is the case the cheap tiers cannot answer at
// all: every T2 artillery piece in the game outranges every tower below the
// counter-battery tier, so against artillery a 30-second tower is not a cheaper
// answer, it is no answer. Still bounded by PORC_ADD_CAP placements for the whole
// game, so the worst case is two towers, not a habit.
const float PORC_BUDGET_SECS = 30.f;
const float PORC_SIEGE_SECS  = 60.f;
// Enemy metal in the ARTY role before the wider budget opens. Two Pillagers.
const float PORC_SIEGE_COST  = 800.f;

// The longest-reaching tower we can currently afford to place.
CCircuitDef@ PorcToBuild()
{
	array<string>@ names = PorcNames();
	const float secs = (aiEnemyMgr.GetEnemyCost(Unit::Role::ARTY.type) >= PORC_SIEGE_COST)
			? PORC_SIEGE_SECS : PORC_BUDGET_SECS;
	const float paced = aiEconomyMgr.metal.income * secs;
	const float budget = (paced > PORC_MIN_BUDGET) ? paced : PORC_MIN_BUDGET;
	CCircuitDef@ best = null;
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		if (d.costM > budget)
			continue;              // do not stall the economy on one tower
		@best = d;                 // the list is ordered by range; later is better
	}
	return best;
}

// A jammer denies the radar that siege artillery needs to shoot at range, so it
// belongs ON the defensive line rather than back beside a fusion, where the two
// existing hubs put it. apexearth: "Jammers need to be part of that defensive
// line. So all this logic that we've built to really shore up our defenses need
// to include a jammer with them. This is what allows us to less easily go under
// siege."
// There is no T2 jammer tower in this game -- corjamt (115m, jam 360),
// armjamt (240m, 500) and legjam (140m, 390) are the only immobile jammers, so
// the T1 tower IS the answer. Cheap enough that one per placed tower is a
// rounding error against a 195-480 metal tower.
string armjamt("armjamt");
string corjamt("corjamt");
string legjam("legjam");

CCircuitDef@ JammerDef()
{
	return SideDef3(armjamt, corjamt, legjam);
}

// One jammer per tower placed on the line, so the cover grows with the line
// instead of being a single point the enemy can shoot out.
void PlaceLineJammer(const AIFloat3& in spot)
{
	CCircuitDef@ jam = JammerDef();
	if ((jam is null) || !jam.IsAvailable(ai.frame))
		return;
	if (int(jam.count) >= int(gPorcAdded) + 1)
		return;   // already covered by an earlier placement
	// Behind the tower it covers: the jammer is the thing being protected.
	AIFloat3 back = spot;
	if (Builder::gHomeSet) {
		const float dx = Builder::gHomePos.x - spot.x;
		const float dz = Builder::gHomePos.z - spot.z;
		const float len = sqrt(dx * dx + dz * dz);
		if (len > 1.f) {
			back.x += dx / len * JAMMER_BACK;
			back.z += dz / len * JAMMER_BACK;
		}
	}
	if (!OnMap(back))
		return;
	IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, jam, back, SQUARE_SIZE * 16));
	if (t !is null) {
		AiLog(Factory::T() + "apex: line-jammer " + jam.GetName()
			+ " standing=" + jam.count);
	}
}

void UpdateBaseDefence()
{
	if (!Builder::gHomeSet)
		return;
	// The count cap only governs the GUESSED positions. apexearth: "if theres a
	// frontline we should build defenses there regardless of any cap" -- two
	// towers per AI for a whole game is a token, not a line, and that cap is why
	// the front never looked defended.
	//
	// Uncapping is the spending class of change, so note what still governs it:
	// the threat trigger below only fires while enemy army exceeds PORC_TRIGGER
	// times our standing tower value, so this is self-limiting and stops once the
	// line is strong enough; PORC_ADD_SPACING still paces one placement per 20s
	// per AI; and AreaNeedsDefence still refuses to stack them.
	if ((gPorcAdded >= PORC_ADD_CAP) && (!FRONT_UNCAPPED || !Front::IsFrontKnown()))
		return;
	if (ai.frame < gNextPorcAdd)
		return;

	const float threat = ApproachThreat();
	if (threat <= 0.f)
		return;
	const float ours = OurTowerValue();
	if (threat < (ours + 1.f) * PORC_TRIGGER)
		return;

	CCircuitDef@ def = PorcToBuild();
	if (def is null)
		return;

	// ON THE EDGE OF OUR TERRITORY, not at home and not on a lane. apexearth:
	// "what we really need are defenses closer to the front line, which are gonna
	// kill the enemy and turn our fights around", and "ideally what you try to
	// form is a line on the edge of our controlled territory".
	//
	// Each successive tower goes one holding further back from the tip, so the
	// two of them stand on separate clusters along that edge rather than on one
	// interpolated point. The gadget-published front is the fallback only.
	// Prefer the measured front to the geometric guesses. BorderPos walks our own
	// holdings outward and FrontPos reads a gadget-published lane; both estimate
	// a line that Front:: now actually computes, as the enemy-facing edge of our
	// territory. FrontChoke first -- a front cell that also sits in a BWEM
	// corridor is worth far more per tower than one in open ground. The old pair
	// stay as the fallback for the opening, when no enemy has been seen and the
	// front is honestly unknown.
	// WHERE WE ARE ACTUALLY BLEEDING comes first.
	//
	// apexearth: "we lose stuff to 'leaks' because we don't even have any
	// defenses on our deep inside mexes... especially not in the important areas
	// where most of the 'leaks' are actually happening". Both the front line and
	// the old geometric guesses answer "where is the edge", and neither answers
	// "where are we losing things" -- ApproachThreat is EnemyArmyCost, a global
	// scalar with no position at all. A raider inside our base and an army massing
	// on the border look identical to it.
	//
	// ai.GetAttackHotspot is the cost-weighted, decaying centroid of our own
	// losses, so a leak in the interior registers as itself rather than as
	// pressure on the front. It takes priority: a hole behind the line is worth
	// more than one more tower on it.
	AIFloat3 spot;
	bool haveSpot = false;
	AIFloat3 hot;
	float hotWeight = 0.f;
	if (ai.GetAttackHotspot(hot, hotWeight) && ai.IsPosOnMap(hot)
			&& Builder::AreaNeedsDefence(hot, PORC_LEAK_FENCE)) {
		spot = hot;
		haveSpot = true;
	}
	if (!haveSpot)
		haveSpot = Front::FrontChoke(Builder::gHomePos, spot)
				|| Front::FrontNear(Builder::gHomePos, spot);
	// A tower is built by a constructor that has to walk there. apexearth on the
	// uncapped front: "cons commuting into stupid places frankly". Anything past
	// this is somebody else's part of the line.
	if (haveSpot && (spot.distance2D(Builder::gHomePos) > PORC_MAX_REACH))
		haveSpot = false;

	// BEHIND the line, not on it. apexearth: "what is the point in trying to make
	// a tower that can never be built? You go to some really dangerous place and
	// are like, oh, I'm just gonna take a minute and build this. It's dumb."
	//
	// The front is by definition the most contested ground on the map, and a
	// tower is a constructor standing still for a long time. Pull the site back
	// toward our own territory so the tower still covers the approach but the
	// builder is not parked in the fight, then refuse outright if the enemy is
	// already on top of it -- a request that dies to a raider costs the
	// constructor-seconds either way.
	if (haveSpot) {
		const float dx = Builder::gHomePos.x - spot.x;
		const float dz = Builder::gHomePos.z - spot.z;
		const float len = sqrt(dx * dx + dz * dz);
		if (len > 1.f) {
			spot.x += dx / len * PORC_SETBACK;
			spot.z += dz / len * PORC_SETBACK;
		}
		if (!ai.IsPosOnMap(spot)
				|| (ai.GetEnemyCostAt(spot, PORC_DANGER_RADIUS) > PORC_DANGER_COST))
			haveSpot = false;
	}
	if (!haveSpot) {
		// Past the cap, ONLY a measured front position earns a tower. The
		// geometric guesses stay capped at two, because uncapping a guess is how
		// you get a field of towers somewhere nothing is happening.
		if (gPorcAdded >= PORC_ADD_CAP)
			return;
		haveSpot = BorderPos(spot, gPorcAdded) || FrontPos(spot);
	}
	if (!haveSpot)
		return;

	// Do not stack them, but the front is by definition the contested area, so
	// it earns a higher bar than a quiet mex would.
	if (!Builder::AreaNeedsDefence(spot, PORC_FRONT_FENCE))
		return;

	IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::HIGH, def, spot, SQUARE_SIZE * 24));
	if (t !is null) {
		++gPorcAdded;
		gNextPorcAdd = ai.frame + PORC_ADD_SPACING;
		PlaceLineJammer(spot);
		AiLog(Factory::T() + "apex: porc+ " + def.GetName() + " #" + gPorcAdded
			+ " at-border enemyArmy=" + formatFloat(threat, "", 0, 0)
			+ " enemyArty=" + formatFloat(aiEnemyMgr.GetEnemyCost(Unit::Role::ARTY.type), "", 0, 0)
			+ " ourTowers=" + formatFloat(ours, "", 0, 0));
	}
}


// No suicide runs while the army IS the defence.
//
// apexearth: "really early in the game, you don't wanna be doing suicide runs.
// Imagine you do a suicide run that fails, and then your army is half size, and
// you fed all that metal or resurrection ability to the enemy. Bam. Now you're
// fucked." A deep strike that trades units for their economy is a good deal
// LATER, when losses are replaceable -- and this AI's whole plan is to make the
// enemy pay by dying on our defences and leaving wrecks, so handing them ours is
// the same mistake in reverse.
//
// raid.min is the maxPower of the Defend task raiders sit in before it promotes
// (MilitaryManager.cpp:1696), i.e. the size a raid group leaves at. Raising it
// keeps them home massing instead of trickling out.
//
// Reached via quota.raid.min, NOT the quotaRaidMin shorthand: that shorthand is
// registered in the current C++ source but is absent from the deployed
// SkirmishAI.dll, which predates it. Source is not the binary.
//
// Keyed on OWNING T2, not on a clock -- apexearth: "usually doing things by time
// is wrong". Before the advanced plant the army is the entire defence and every
// loss is a large share of it; after, there is economy behind it to replace
// what a strike costs.
const float RAID_MIN_EARLY = 45.f;   // hold them home
float gRaidMinStock = -1.f;

}  // namespace Military
