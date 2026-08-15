namespace Factory {

// armmoho/cormoho/legmoho (the T2 mex upgrade) are already declared as
// globals in techlead.as -- same namespace, one declaration only.

// How many plants of one factory DEF the current income curve allows -- see
// PlantsWanted(). Per def, not in total: pick.count is this def's own count, so
// a second bot lab and a first vehicle plant are counted separately.
int gNextPlantCapLog = 0;

// aiEconomyMgr.metal.income is the team's whole metal rate with reclaim mixed
// in, and SResourceInfo carries no way to separate the two. The MEDIAN of the
// last minute is immune to a reclaim burst shorter than half the window, so the
// cap reads the held level rather than a momentary spike -- important because a
// plant, once built, is permanent, so a cap read off a peak ratchets.
const int STEADY_SAMPLES = 60;      // one per AiUpdate, so about a minute
array<float> gIncomeRing;
uint gIncomeAt = 0;

void SampleIncome()
{
	if (gIncomeRing.length() < uint(STEADY_SAMPLES)) {
		gIncomeRing.insertLast(aiEconomyMgr.metal.income);
		return;
	}
	gIncomeRing[gIncomeAt] = aiEconomyMgr.metal.income;
	gIncomeAt = (gIncomeAt + 1) % uint(STEADY_SAMPLES);
}

float SteadyIncome()
{
	const uint n = gIncomeRing.length();
	if (n == 0)
		return aiEconomyMgr.metal.income;
	array<float> sorted = gIncomeRing;
	sorted.sortAsc();
	return sorted[n / 2];
}

int PlantsWanted(const CCircuitDef@ fac)
{
	if (fac is null)
		return 1;
	const float inc = SteadyIncome();
	if (inc < 2.f)
		return 1;
	int want;
	if ((userData[fac.id].attr & Attr::T3) != 0)
		want = int(inc / ai.GetTunable("apex_plants_t3_per", 150.f));
	else if ((userData[fac.id].attr & Attr::T2) != 0)
		want = int(ai.GetTunable("apex_plants_t2_a", -7.0f)
				+ ai.GetTunable("apex_plants_t2_b", 1.737f) * log(inc));
	else
		want = int(ai.GetTunable("apex_plants_t1_a", -5.892f)
				+ ai.GetTunable("apex_plants_t1_b", 2.301f) * log(inc));
	return (want < 1) ? 1 : want;
}

// How many T1-tier plants we hold in TOTAL, across every type. PlantsWanted is
// per def, so a first bot lab and a first vehicle plant each read count=0.
int T1PlantCount()
{
	int n = 0;
	for (uint i = 0; i < gFacUnits.length(); ++i) {
		if (gFacUnits[i] is null)
			continue;
		if ((userData[gFacUnits[i].circuitDef.id].attr & (Attr::T2 | Attr::T3)) == 0)
			++n;
	}
	return n;
}

// How many T2-tier plants we hold in TOTAL, across every def -- same shape as
// T1PlantCount(), for the same reason: PlantsWanted() answers for the TIER,
// not the individual def, so a per-def count check lets two different T2
// defs each read count=0 and both pass.
int T2PlantCount()
{
	int n = 0;
	for (uint i = 0; i < gFacUnits.length(); ++i) {
		if (gFacUnits[i] is null)
			continue;
		if ((userData[gFacUnits[i].circuitDef.id].attr & Attr::T2) != 0)
			++n;
	}
	return n;
}

int gNextOpenGateLog = 0;
int gNextT1TotalLog = 0;
int gNextT2TotalLog = 0;

// The plant curve is applied ONCE, here, rather than at each of the dozen
// returns inside ChooseFactory. Only the opening is exempt -- see below for why
// that is not the same thing as isStart.
CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	// STEP 3 OF THE OPENING: the first lab waits for the income step 2 buys.
	// Not gated on isStart -- that flag is also true on the recovery path (see
	// below) -- but on owning no factory at all, which is what "first" means,
	// so a wiped team with one surviving constructor re-enters this same gate
	// from its own current readings rather than being treated as past it.
	// No clock: Builder::OpeningNeedsEconomy() cannot deadlock a player whose
	// income never arrives, because OpeningEnergy stops proposing work the
	// moment HomeEnergy has nothing beneficial left to place -- see opening.as.
	if (ApexActive() && Builder::OpeningNeedsEconomy()) {
		if (ai.frame >= gNextOpenGateLog) {
			gNextOpenGateLog = ai.frame + 30 * SECOND;
			AiLog(T() + "apex: opening gate holds the first factory -- e="
				+ formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
				+ "/" + formatFloat(Builder::OpeningEnergyGate(), "", 0, 0)
				+ " m=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ "/" + formatFloat(Builder::OpeningMetalGate(), "", 0, 1));
		}
		return null;
	}
	CCircuitDef@ want = ChooseFactory(pos, isStart, isReset);
	// isStart IS NOT "the first factory of the game": CFactoryManager::UpdateIdle
	// (module/FactoryManager.cpp:1360) also calls
	// `GetFactoryToBuild(-RgtVector, true, true)` from its recovery path whenever
	// no builder for our factory type is available -- which recurs, since a T1
	// lab's builder goes unavailable the moment its owner has any T2 factory --
	// so exempting isStart from the cap exempted that whole recovery path too.
	// No exemption: PlantsWanted never returns less than 1, and CCircuitDef::count
	// counts the NANOFRAME, so a rebuild from nothing passes on have=0 while the
	// second request sees have=1 and is refused.
	if ((want is null) || !ApexActive())
		return want;
	const int have = want.count;
	const int allowed = PlantsWanted(want);
	if (have >= allowed) {
		if (ai.frame >= gNextPlantCapLog) {
			gNextPlantCapLog = ai.frame + 60 * SECOND;
			AiLog(T() + "apex: " + want.GetName() + " held " + have + " >= "
				+ allowed + " at " + formatFloat(SteadyIncome(), "", 0, 0)
				+ " m/s -- no more of this type yet");
		}
		return null;
	}

	// A second T1 line competes with the T2 plant for the same metal. The cap
	// above is per DEF, so a first bot lab and a first vehicle plant both read
	// count=0 and both pass it -- this applies the same curve to the T1 TOTAL
	// instead. Naval and air are exempt: a shipyard is the only route to water
	// metal and carries its own income floors, and the air-plant branches
	// carry theirs.
	//
	// apexearth: "Before we've gone T2 we really shouldn't be making more
	// than 1 T1 lab" -- flat, not income-scaled: the comment's own argument
	// (a second T1 line competes with the T2 plant for the same metal)
	// doesn't get weaker as income rises, so letting `allowed` climb above 1
	// pre-T2 was inconsistent with the reasoning already written here.
	//
	// "And after we've gone T2 we don't want to immediately make an extra T1
	// lab before we've spent the ~500 metal on the adv con and another ~500
	// on the T2 mex... we need to be smart with how we spend our money." The
	// SAME competition-for-metal argument holds for a short window right
	// after gHaveT2 flips true: the new line's own advanced constructor and
	// at least one T2 mex upgrade are the immediate, higher-value spend, so
	// the second-T1-line refusal now stays active until both exist, instead
	// of lifting the instant a T2 plant merely stands.
	if (((userData[want.id].attr & (Attr::T2 | Attr::T3)) == 0)
		&& !IsAirFactory(want))
	{
		CCircuitDef@ navy = NavalOpening();
		if (!((navy !is null) && (want is navy))) {
			bool stillCompeting = !gHaveT2;
			if (!stillCompeting) {
				CCircuitDef@ advCon = aiFactoryMgr.GetRoleDef(want, RT::BUILDER2);
				const bool haveAdvCon = (advCon !is null) && (advCon.count > 0);
				CCircuitDef@ t2mex = SideDef3(armmoho, cormoho, legmoho);
				const bool haveT2Mex = (t2mex !is null) && (t2mex.count > 0);
				stillCompeting = !haveAdvCon || !haveT2Mex;
			}
			const int t1have = T1PlantCount();
			if (stillCompeting ? (t1have >= 1) : (t1have >= allowed)) {
				if (ai.frame >= gNextT1TotalLog) {
					gNextT1TotalLog = ai.frame + 60 * SECOND;
					AiLog(T() + "apex: " + want.GetName() + " refused -- " + t1have
						+ " T1 plant(s) already, " + (stillCompeting ? "still competing with tech spend" : "at cap")
						+ ", at " + formatFloat(SteadyIncome(), "", 0, 0)
						+ " m/s the T2 plant is the better buy");
				}
				return null;
			}
		}
	}
	// A second T2 line before the first one has paid for its own advanced con
	// and T2 mex competes for the same metal -- same reasoning as the T1 cap
	// above. PlantsWanted() depends only on income and tier, not on which T2
	// def is asked, so applying its answer PER DEF let two different T2
	// plants (e.g. an advanced bot lab and an advanced vehicle plant) each
	// read their own count=0 and both pass. apexearth, watching, 2026-08-15:
	// "we're making a second T2 lab this game... idk why."
	if ((userData[want.id].attr & Attr::T2) != 0) {
		CCircuitDef@ advCon2 = aiFactoryMgr.GetRoleDef(want, RT::BUILDER2);
		const bool haveAdvCon2 = (advCon2 !is null) && (advCon2.count > 0);
		CCircuitDef@ t2mex2 = SideDef3(armmoho, cormoho, legmoho);
		const bool haveT2Mex2 = (t2mex2 !is null) && (t2mex2.count > 0);
		const int t2have = T2PlantCount();
		const bool stillCompeting2 = !haveAdvCon2 || !haveT2Mex2;
		if (stillCompeting2 ? (t2have >= 1) : (t2have >= allowed)) {
			if (ai.frame >= gNextT2TotalLog) {
				gNextT2TotalLog = ai.frame + 60 * SECOND;
				AiLog(T() + "apex: " + want.GetName() + " refused -- " + t2have
					+ " T2 plant(s) already, " + (stillCompeting2 ? "still competing with adv con/T2 mex spend" : "at cap")
					+ ", at " + formatFloat(SteadyIncome(), "", 0, 0)
					+ " m/s");
			}
			return null;
		}
	}
	return want;
}

CCircuitDef@ ChooseFactory(const AIFloat3& in pos, bool isStart, bool isReset)
{
	if (!ApexActive())
		return aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);

	CCircuitDef@ pick = aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
	if (isStart || (pick is null)) {
		// Logged unconditionally: IsWaterAt is built on pos.y, and a binding that
		// quietly returns 0 for everything would look exactly like "no water start
		// here" on every map. This line is what says the height is real.
		if (isStart) {
			AiLog(T() + "apex: start pos y=" + formatFloat(pos.y, "", 0, 1)
				+ " commSet=" + (Builder::gHomeSet ? "1" : "0")
				+ " commY=" + (Builder::gHomeSet
					? formatFloat(Builder::gHomePos.y, "", 0, 1) : "n/a")
				+ " land=" + formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 0) + "%");
		}
		// A water start outranks every other opening rule, including the air
		// override below: if the spot is sea then a land lab cannot go there, so
		// there is nothing to weigh up. DefaultGetFactoryToBuild picks its water
		// variant off factory.json's select.min_land, which is the same map-wide
		// 40% test as IsWaterMap and so misses this case entirely.
		if (isStart && IsWaterAt(pos)) {
			CCircuitDef@ sea = NavalOpening();
			AiLog(T() + "apex: water start (y="
				+ formatFloat(pos.y, "", 0, 0) + ") -- opening "
				+ ((sea is null) ? "FAILED, no shipyard def" : sea.GetName())
				+ ((pick is null) ? "" : " instead of " + pick.GetName()));
			if (sea !is null) {
				@gT1Fac = sea;
				return sea;
			}
		}
		if (isStart && IsAirFactory(pick) && !MayOpenAir()) {
			CCircuitDef@ ground = IsWaterMap() ? NavalOpening() : GroundOpening();
			if (ground !is null) {
				AiLog(T() + "apex: opening " + pick.GetName() + " -> "
					+ ground.GetName()
					+ (IsSmallTeam() ? " (no air on a small team)"
					 : IsTechLead()  ? " (no air tech lead)"
					                 : " (air slot is team " + AirSlotTeamId() + ")"));
				@pick = ground;
			}
		}
		if (pick !is null)
			@gT1Fac = pick;
		return pick;   // opening factory is always T1
	}
	if ((gT1Fac is null) && ((Factory::userData[pick.id].attr & Factory::Attr::T2) == 0))
		@gT1Fac = pick;

	// ABOVE the bot lab branch, which otherwise returns first and makes this
	// unreachable. The eco lead builds no combat spam, so for it the air plant
	// (pure build power) outranks the bot lab it would otherwise be offered.
	if (EcoWantsAirPlant()) {
		CCircuitDef@ ap = SideDef3(armap, corap, legap);
		if (ap !is null) {
			AiLog(T() + "apex: eco lead building " + ap.GetName()
				+ " for air constructors at "
				+ formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
			return ap;
		}
	}

	// The air assassin's plant, ABOVE the bot lab and the navy: a branch placed
	// below them never gets reached, since they return first on most teams.
	// Armed() is narrow -- the air lead only, past 15 minutes, at 60+ metal/s,
	// enemy anti-air under the ceiling -- so this cannot run away with the slot.
	// One air lead per team delays only its own gantry; the other players are
	// untouched.
	if (Air::Armed()) {
		CCircuitDef@ airFac = Air::FactoryToBuild();
		if (airFac !is null) {
			AiLog(T() + "apex: air assassin building " + airFac.GetName());
			return airFac;
		}
	}

	// Somebody has to OWN an air plant for the fighter floor to mean anything.
	// The eco lead builds one for constructors on a big team; this covers every
	// other case -- small teams, and games where the eco role never activated.
	// Bounded to the air slot holder, the same one-per-team cap the air opening
	// uses, so eight players do not each build a plant.
	const bool lateFallback  = LateGame() && (aiEconomyMgr.metal.income >= LATE_AIR_INCOME);
	// Restricted to big teams, unlike lateFallback above: this trigger has no
	// BUILD_PHASE gate of its own, so it stays off small teams where an
	// unconditional spend competes directly with the phase-gated cluster.
	const bool earlyReaction = !IsSmallTeam() && (ai.frame >= EARLY_AIR_REACT_FRAME)
		&& (Military::gAirAvg >= EARLY_AIR_ENEMY_MIN);
	if (!HaveAirFactory() && (ai.teamId == AirSlotTeamId()) && (lateFallback || earlyReaction))
	{
		const string aside = ai.GetSideName();
		CCircuitDef@ lap = (aside == "cortex") ? ai.GetCircuitDef(corap)
		                 : ((aside == "legion") ? ai.GetCircuitDef(legap)
		                                        : ai.GetCircuitDef(armap));
		if (lap !is null) {
			AiLog(T() + "apex: " + (earlyReaction ? "enemy air seen (" +
				formatFloat(Military::gAirAvg, "", 0, 0) + "), no air of our own"
				: "late game with no air") + " -- building " + lap.GetName()
				+ " for a fighter screen");
			return lap;
		}
	}

	// Skipped on water: this branch returns before every other pick in the
	// function, so it would pre-empt any naval choice for the rest of the game.
	// BOTLAB_FROM, not the follower tech clock: waiting for T2 costs the whole
	// early game of resurrection, the bot lab being the only source of rez bots.
	// IsWaterMap() is a MAP test (land < 40%) and the failure is PER PLAYER: on a
	// mostly-land map a water starter's constructors are naval and cannot place a
	// land lab, so !HaveT1BotLab() never clears and this branch pre-empts the
	// naval, T2 and gantry picks below it for the rest of the game.
	if (!IsWaterMap() && !(Builder::gHomeSet && IsWaterAt(Builder::gHomePos))
		&& !HaveT1BotLab()
		&& (ai.frame >= gNextBotLabRequest)
		&& (gHaveT2 || (ai.frame > BOTLAB_FROM)))
	{
		CCircuitDef@ lab = T1BotLab();
		if (lab !is null) {
			gNextBotLabRequest = ai.frame + BOTLAB_REQUEST_COOLDOWN;
			AiLog(T() + "apex: no T1 bot lab -- building " + lab.GetName()
				+ " for spam and rez bots");
			return lab;
		}
	}

	if (WantMoreGantries() && T3Worthwhile()) {
		CCircuitDef@ gant = T3Gantry();
		if (gant !is null) {
			AiLog(T() + "apex: building T3 gantry " + gant.GetName()
				+ " at " + formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s"
				+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
				+ " enemyArmy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
			return gant;
		}
	}

	// No rush-window clause: RushWindowOpen() (`frame <= 15 minutes`) is about who
	// gets to T2 FIRST, not who may get there at all, so gating the only route to
	// an advanced plant on it would strand a late-teching player permanently.
	// MayPursueT2() is the designated lead or a follower whose income has earned
	// it; RushReady() checks we can actually power the plant.
	if (MayPursueT2() && !gHaveT2 && RushReady()) {
		CCircuitDef@ adv = AdvCounterpart();
		if (adv !is null) {
			AiLog(T() + "apex: building advanced plant " + adv.GetName()
				+ " (from " + gT1Fac.GetName() + ")");
			return adv;
		}
		AiLog(T() + "apex: rush WANTS T2 but no counterpart for "
			+ ((gT1Fac is null) ? "<unknown T1 factory>" : gT1Fac.GetName()));
	}

	// Contest the water on a map that has plenty of it but is not a water map,
	// OR try it as a fallback once our own expansion has stalled -- see
	// ExpansionStalled() above for why the map-average test alone misses a
	// player boxed onto a small peninsula on an otherwise land-majority map.
	//
	// Placed here, below the tech rush, the bot lab and the gantry, since this
	// rule SPENDS -- a factory plus the ships it makes is real metal -- so it
	// takes the slot only once nothing more important wants it.
	// stalled is restricted to big teams for the same reason earlyReaction is:
	// it has no BUILD_PHASE gate of its own. IsMixedWaterMap() below is
	// unaffected and already applies to every team size.
	// IsWaterMap() is in this test, not just IsMixedWaterMap(). The two are
	// DISJOINT by construction -- IsMixedWaterMap() is `!IsWaterMap() && land <=
	// 80%` -- so without it a genuine water map left a player whose opening
	// landed on dry ground with no path to a shipyard for the rest of the game.
	const bool stalled = !IsSmallTeam() && !aiTerrainMgr.IsWaterAVoid() && ExpansionStalled();
	// A true water map uses the STALLED income floor, not the luxury one: half
	// the metal spots are under water, so income cannot climb past the luxury
	// bar until we can build on them, and we cannot build on them without a yard
	// -- gating the escape valve on the income bar it exists to unblock is a
	// deadlock, not a safeguard.
	// A water-HEAVY mixed map is the same deadlock, less extreme, so it gets the
	// same lower floor.
	//
	// Bounded to genuinely water-heavy maps: a mixed map that is mostly land
	// keeps the luxury floor, since there a yard really is optional.
	const bool waterHeavy = IsMixedWaterMap()
			&& (aiTerrainMgr.GetLandPercent() <= NAVY_HEAVY_LAND_PCT);
	const bool waterEscape = IsWaterMap() || stalled || waterHeavy;
	if ((IsWaterMap() || IsMixedWaterMap() || stalled) && !HaveShipyard()
		&& (aiEconomyMgr.metal.income >= (waterEscape ? NAVY_MIN_INCOME_STALLED : NAVY_MIN_INCOME)))
	{
		CCircuitDef@ sy = NavalOpening();
		if (sy !is null) {
			AiLog(T() + "apex: " + (stalled ? "expansion stalled"
				: (IsWaterMap() ? "water map (" : "mixed map (") +
				formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 0) + "% land)")
				+ " -- building " + sy.GetName() + " to contest the water"
				+ " at " + formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
			return sy;
		}
	}

	return pick;
}

/* --- Utils --- */

float MakeSwitchLimit()
{
	return AiRandom(16000, 30000) * SECOND;
}

int MakeSwitchInterval()
{
	return AiRandom(550, 900) * SECOND;
}

}  // namespace Factory
