namespace Factory {

// HOW MANY PLANTS OF ONE TYPE AN ECONOMY IS WORTH.
//
// behaviour.json capped armlab/armvp/armsy/armap at ONE each, forever, at every
// income. apexearth: "We should not be limiting the factory counts at 1. I'd say
// at 1000 metal per second you can have a limit of 10 t1 plants. At 20 metal the
// limit would be 1 T1 plant per type. For advanced labs... 1000 metal, 5
// advanced plants per type... 100 metal, 1 per type. For gantries, 1 per 150
// metal per second."
//
//   income    20    50   100   250   500  1000
//   T1       1.0   3.1   4.7   6.8   8.4  10.0
//   T2         1     1   1.0   2.6   3.8   5.0
//   T3         -     -     -   1.6   3.3   6.7
//
// Per TYPE, not in total: pick.count is this def's own count, so a second bot lab
// and a first vehicle plant are counted separately, which is what he asked for.
// This does not contradict "never build two of the same expensive plant" -- that
// was about building them SIMULTANEOUSLY on one economy, and at 20 metal/s this
// still says one.
int gNextPlantCapLog = 0;

// THE CAP MUST NOT COUNT RECLAIM. apexearth: "when we reclaim metal our income
// will suddenly go much higher than normal. Make sure our cap logic doesn't
// include reclaim."
//
// aiEconomyMgr.metal.income is the team's whole metal rate, reclaim included,
// and nothing in the bound surface separates the two -- SResourceInfo carries
// only current/storage/pull/income. So this filters by SHAPE instead: a reclaim
// burst is a spike, a real economy is a level that is held. The MEDIAN of the
// last minute cannot be moved by a burst shorter than half the window, while it
// tracks a genuine change within about thirty seconds.
//
// It matters because a plant, once built, is permanent: a cap read from a
// momentary peak ratchets, and only the highest sample the cap ever saw ends up
// mattering. Measured live 2026-08-12: team 3 held NINE T1 bot labs at a steady
// 66 metal/s where the curve allows three.
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

// The plant curve is applied ONCE, here, rather than at each of the dozen
// returns inside ChooseFactory. Only the opening is exempt -- see below for why
// that is not the same thing as isStart.
CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	CCircuitDef@ want = ChooseFactory(pos, isStart, isReset);
	// isStart IS NOT "the first factory of the game", and exempting it was a hole
	// the size of the whole cap. CFactoryManager::UpdateIdle
	// (module/FactoryManager.cpp:1360) calls
	// `GetFactoryToBuild(-RgtVector, true, true)` from the recovery path that runs
	// when no builder for our factory type is available, and enqueues the result
	// at Priority::NOW. That path fires again and again -- a T1 lab's builder goes
	// unavailable the moment its owner has any T2 factory -- and every one of
	// those calls arrived here with isStart true and skipped the curve.
	//
	// Measured 2026-08-12, watched 4v4: team 3 reached NINE T1 bot labs at a true
	// 66 metal/s, where PlantsWanted allows three, while the cap logged exactly
	// one refusal in the whole game and that was for a T2 lab. apexearth,
	// watching: "Purple in this game has 9 T1 bot labs at 17m in... at 100 metal
	// per second our limit on T1 labs would be something like 5."
	//
	// No exemption: PlantsWanted never returns less than 1, and CCircuitDef::count
	// counts the NANOFRAME, so a rebuild from nothing passes on have=0 while the
	// second request sees have=1 and is refused. Exempting on a factory COUNT
	// instead is what let a lost base rebuild three labs in a row.
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

	// The rusher builds the advanced plant directly rather than waiting for a
	// production switch that never comes.
	// Once the economy carries it, tech to T3 rather than adding another T2 line.
	// No bot lab: get one. It is the ONLY source of ground rez bots -- corlab ->
	// cornecro, armlab -> armrectr; the vehicle plant and the advanced plant
	// cannot build them at all. A team that opens vehicles and stays there has no
	// reclaim or resurrect capability whatsoever, which is what happened: 6 of 8
	// teams opened corvp and the side resurrected nothing all game.
	//
	// Not gated on gHaveT2 alone, or a player that never techs never gets one.
	// Past FOLLOWER_TECH_FRAME the rush window is over and a second factory is
	// affordable regardless.
	// ABOVE the bot lab, because the bot lab branch returns and would otherwise
	// make this unreachable. Measured: the eco lead asked for armlab three times
	// in one 40-minute game and never once reached the air plant below.
	//
	// The bot lab is there for spam units and rez bots. This player builds no
	// spam by construction, so for it the aircraft plant -- which is pure build
	// power -- is worth more than the lab it is displacing.
	if (EcoWantsAirPlant()) {
		CCircuitDef@ ap = SideDef3(armap, corap, legap);
		if (ap !is null) {
			AiLog(T() + "apex: eco lead building " + ap.GetName()
				+ " for air constructors at "
				+ formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
			return ap;
		}
	}

	// The air assassin's plant, ABOVE the bot lab and the navy.
	//
	// It used to sit last in this function, "so it never pre-empts the tech rush,
	// the bot lab or the gantry" -- and the consequence was that it pre-empted
	// nothing and got nothing. Measured across 8 games: 133 of 134 status samples
	// read `plants=0,0 cons=0 want=corap`, i.e. the strategy armed, committed, and
	// asked for its first plant every single time while some branch above it
	// returned first. It built 0 bombers and launched 0 strikes. apexearth: "I
	// haven't been seeing our air eco assassination strategy, I only saw something
	// akin to it once in dozens of games."
	//
	// Armed() is already narrow -- the air lead only, past 15 minutes, at 60+
	// metal/s, with enemy anti-air under the ceiling -- so this cannot run away.
	//
	// It sits above the gantry as well, which IS a real trade for that one
	// player: the bot lab branch is itself above the gantry, so anything placed
	// below the bot lab is starved by it, and there is no slot that clears the
	// bot lab without also clearing the gantry. One air lead per team delays its
	// own gantry; the other seven players are untouched.
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
	// Restricted to big teams, unlike lateFallback above (which is deliberately
	// small-team-inclusive per its own comment, but at a 25-minute gate that a
	// 25-minute-capped 4v4 benchmark match almost never reaches). Diagnosed
	// entirely from 8v8 observation, and this session's dominant finding is
	// that any new spend competing with the phase-gated cluster costs a 4v4 --
	// this trigger has no BUILD_PHASE gate of its own, so keep it off the
	// benchmark the goal is actually measured against until it can be
	// threaded through that gate properly.
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
	// BOTLAB_FROM, not the follower tech clock. Waiting for T2 or thirteen minutes
	// costs us the whole early game of resurrection, and resurrection is the
	// single biggest measured gap against stock: over 6 games stock spent 21,460
	// metal a game raising its dead to our 10,396, and in one watched 8v8 it was
	// 32,890 to our 436 -- one stock player's largest sink of any kind was
	// cornecro at 17,940. We built ZERO rez bots in that game. A lab is ~600
	// metal and the bot is 130.
	// IsWaterMap() is a MAP test (land < 40%) and the failure is PER PLAYER: on a
	// mostly-land map a water starter's constructors are naval and cannot place a
	// land lab, so !HaveT1BotLab() never clears and this branch returns on every
	// call, pre-empting the naval, T2 and gantry picks below it for the rest of
	// the game. Measured: "no T1 bot lab" logged 206 times for one water player
	// and 59 for another, against 1-3 for land players, both ending techStart=-1.
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

	// No rush-window clause. RushWindowOpen() is `frame <= 15 minutes`, and it was
	// gating the only route to an advanced plant -- so a player that had not
	// teched by minute 15, for any reason, could never tech again however rich it
	// became. Measured live at 33 minutes: t6 on 257 metal/s with two fusions and
	// a bank of 13,478 overflowing 9,185 of storage, still haveT2=0.
	//
	// The rush window is about who gets there FIRST; it should never have decided
	// who may get there at all. What remains is economic: MayPursueT2() is the
	// designated lead or a follower whose income has earned it, and RushReady()
	// checks we can actually power the plant.
	//
	// apexearth: "some of our guys havent made a t2 lab... they only have 1
	// advanced con (the one shared to them)", and separately the general rule --
	// "game progression is almost always based on the size of the economy."
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
	// Nothing else in this function will ever ask for a shipyard there, so the
	// sea is a flank we can neither use nor defend.
	//
	// Placed here, below the tech rush, the bot lab and the gantry, because this
	// is a rule that SPENDS -- a factory plus the ships it makes is real metal,
	// and the last batch of individually-reasonable spending rules cut metal
	// production 4.3x between them. It takes the slot only when nothing more
	// important wants it, and only once the economy can carry it.
	// stalled is restricted to big teams for the same reason earlyReaction is
	// above: diagnosed entirely from an 8v8 live observation (a player boxed
	// onto a small land strip), it has no BUILD_PHASE gate of its own, and
	// this session's dominant finding is that any new unconditional spend
	// costs a 4v4. IsMixedWaterMap() below is unaffected -- that branch
	// predates this fix and already applied to every team size.
	// IsWaterMap() is in this test, not just IsMixedWaterMap(). The two are
	// DISJOINT by construction -- IsMixedWaterMap() is defined as
	// `!IsWaterMap() && land <= 80%` -- so on a genuine water map this branch
	// used to be unreachable, and `stalled` could not rescue it either because
	// that is restricted to big teams. Net effect: on a true water map at 4v4, a
	// player whose opening happened to land on dry ground had NO path to a
	// shipyard for the rest of the game.
	//
	// Measured on Silent Sea (4v4, 14x14): two players opened naval and spent
	// 48% and 61% of their metal on it; the other two finished on 0% and 3.7%
	// with no shipyard at all, and the game ran to the time limit with the sea
	// half-contested. apexearth: "be sure that the AI works well on water/mix
	// maps. Our AI should actively cross into water and build water units."
	const bool stalled = !IsSmallTeam() && !aiTerrainMgr.IsWaterAVoid() && ExpansionStalled();
	// A true water map uses the STALLED income floor, not the luxury one. The
	// deadlock NAVY_MIN_INCOME_STALLED exists for -- "gating the escape valve on
	// the same income bar the AI needs the escape valve to reach" -- is the
	// normal condition there, not an edge case: half the metal spots are under
	// water, so income cannot climb until we can build on them, and we cannot
	// build on them without a yard. Measured on Silent Sea: all four players
	// plateaued at 16-24 m/s, and the one that eventually cleared 15 asked for
	// its first shipyard at 21.9 minutes of a 25 minute game.
	// A water-HEAVY mixed map is the same deadlock as a true water map, just
	// less extreme, so it gets the same lower floor. Measured on Crater Islands
	// (63% land): the four players finished on 5.1, 5.2, 2.4 and 13.3 metal/s,
	// every one of them under NAVY_MIN_INCOME's 15, and exactly one ever built a
	// shipyard -- the one whose opening happened to start in water. Income
	// cannot climb past that bar precisely BECAUSE a third of the map's metal is
	// across water we never contest.
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
