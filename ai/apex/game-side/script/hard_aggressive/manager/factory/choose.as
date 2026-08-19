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
		// 100, was 150: apexearth 2026-08-15, on losing long 8v8s with a T3
		// deficit (751k vs 1.3M fielded): "we're probably losing just because
		// we're not making enough gantries."
		//
		// No floor-1 for T3 (the generic floor below is skipped): the floor
		// let the FIRST gantry through at any income, and once factory offers
		// always won a corgant landed on a 34 m/s economy and bankrupted it
		// (watched 2026-08-16, 59k produced vs stock's 119k). The first
		// gantry now waits for the same per-income bar as every later one.
		return int(inc / ai.GetTunable("apex_plants_t3_per", 100.f));
	else if ((userData[fac.id].attr & Attr::T2) != 0)
		// -5.8, was -7.0: the old intercept put the SECOND T2 line at 178 m/s
		// income -- one lab cannot spend a 160-income economy (audited 42% of
		// samples at the metal cap), and the second-line discipline gates
		// (own adv con, T2 mex, reactor first) still hold below this curve.
		// Second line now clears at ~90 m/s, third at ~160.
		want = int(ai.GetTunable("apex_plants_t2_a", -5.8f)
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
	// DEF COUNTS, NOT THE STANDING LIST: CCircuitDef::count includes the
	// nanoframe, so two constructors starting plants in the same window both
	// counting "zero standing" cannot double-open (seen live as Legion: two
	// T1 plants pre-T2 straight through the gate). All factions' land plants
	// are summed because resurrection hands us cross-faction labs.
	array<string> plants = {"armlab", "armvp", "armap", "armhp",
	                        "corlab", "corvp", "corap", "corhp",
	                        "leglab", "legvp", "legap", "leghp"};
	int n = 0;
	for (uint i = 0; i < plants.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(plants[i]);
		if (d !is null)
			n += int(d.count);
	}
	return n;
}

// How many T2-tier plants we hold in TOTAL, across every def -- same shape as
// T1PlantCount(), for the same reason: PlantsWanted() answers for the TIER,
// not the individual def, so a per-def count check lets two different T2
// defs each read count=0 and both pass. DEF COUNTS, NOT gFacUnits: that list
// fills from AiUnitAdded, i.e. on COMPLETION, and an advanced lab is a
// nanoframe for minutes -- reading it here let three T2 labs through before
// the first one registered (seen live 2026-08-15).
int T2PlantCount()
{
	array<string> plants = {"armalab", "armavp", "armaap",
	                        "coralab", "coravp", "coraap",
	                        "legalab", "legavp", "legaap"};
	int n = 0;
	for (uint i = 0; i < plants.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(plants[i]);
		if (d !is null)
			n += int(d.count);
	}
	return n;
}

// Approvals this gate has granted whose nanoframe does not exist yet. Even
// def counts miss the window between "yes, build it" and the builder reaching
// the site -- a 30s walk, during which every re-ask reads the same counts and
// passes. Each approval is held against the caps until the def's count rises
// past what it was when granted (the frame is down, counts cover it now) or a
// TTL passes (the ask died with its builder; do not dam the tech path).
array<CCircuitDef@> gAskDef;
array<int> gAskFrame;
array<int> gAskCount;

void SweepPlantAsks()
{
	const int ttl = int(ai.GetTunable("apex_plant_ask_ttl", 90.f)) * SECOND;
	// The TTL alone is not enough to expire an ask: a T2 lab at 20 m/s income
	// is not STARTED inside 90s, so the ask aged out, the gate read have=0
	// again, and a second armalab was approved and built (watched 2026-08-16).
	// The engine's factory-task pool is ground truth -- while it still holds a
	// FACTORY build task per ledger entry, every ask is alive however old it
	// is. The TTL now only clears asks the pool has actually lost. The pool
	// count alone was not enough: a task ASSIGNED to a builder leaves it, so
	// during the walk-and-build phase the pool read empty and the TTL
	// double-approved armalab again (3.5m + 5.8m, 20260816-223928) -- so
	// builders currently holding FACTORY work count as live asks too.
	uint alive = aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::FACTORY));
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Crew::gId[i]));
		if (c is null)
			continue;
		IUnitTask@ t = c.task;
		if ((t !is null) && (t.GetType() == Task::Type::BUILDER)
			&& (t.GetBuildType() == Task::BuildType::FACTORY))
		{
			++alive;
		}
	}
	const bool poolShort = alive < gAskDef.length();
	// A PHANTOM DIES FAST. The engine QUERIES GetFactoryToBuild without
	// always enqueuing (probes, recovery checks), and every approved query
	// registers here -- so an ask no task ever backed blocked the whole
	// opening for the full 90s TTL (approved 0.4m, first lab 2.3-4.0m, both
	// live MP and the 4v4 smoke). With the pool short, an ask still young
	// enough that a real enqueue would already show gets a short fuse; the
	// long TTL remains for asks that were once backed (walk-and-build gaps).
	const int fuse = int(ai.GetTunable("apex_plant_ask_fuse", 10.f)) * SECOND;
	for (uint i = gAskDef.length(); i > 0; --i) {
		const uint k = i - 1;
		const int age = ai.frame - gAskFrame[k];
		if ((gAskDef[k] is null)
			|| (int(gAskDef[k].count) > gAskCount[k])
			|| (poolShort && (age > ttl))
			|| (poolShort && (alive == 0) && (age > fuse)))
		{
			gAskDef.removeAt(k);
			gAskFrame.removeAt(k);
			gAskCount.removeAt(k);
		}
	}
}

// An approval whose Requests::Take then FAILED must give the ask back at
// once: registered-but-never-built, it wedged the ledger for its whole 90s
// TTL and blocked every other path from placing the lab -- watched live (MP
// 2026-08-17), the opening approval at 1 m/s income was refused by the
// request cap and three players walked mexes for 90 seconds with a phantom
// ask holding the gate shut.
void PlantAskAbort(const CCircuitDef@ def)
{
	for (int i = int(gAskDef.length()) - 1; i >= 0; --i) {
		if (gAskDef[i] is def) {
			gAskDef.removeAt(i);
			gAskFrame.removeAt(i);
			gAskCount.removeAt(i);
			AiLog(T() + "apex: plant ask returned -- " + def.GetName()
				+ " request was refused");
			return;
		}
	}
}

int InFlightOf(const CCircuitDef@ def)
{
	int n = 0;
	for (uint i = 0; i < gAskDef.length(); ++i) {
		if (gAskDef[i] is def)
			++n;
	}
	return n;
}

// tierMask: Attr::T2 | Attr::T3 picks those tiers; 0 picks T1 (no tier bit).
int InFlightTier(int tierMask)
{
	int n = 0;
	for (uint i = 0; i < gAskDef.length(); ++i) {
		const int attr = userData[gAskDef[i].id].attr;
		if (tierMask == 0 ? ((attr & (Attr::T2 | Attr::T3)) == 0)
		                  : ((attr & tierMask) != 0))
			++n;
	}
	return n;
}

int gNextOpenGateLog = 0;
int gNextT1TotalLog = 0;
int gNextT2TotalLog = 0;
// Frame the pre-T2 gate first found itself blocked; -1 while not blocked.
int gT2StuckSince = -1;

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
	return PlantApproved(want) ? want : null;
}

// THE ONE GATE. Every path that gets a plant enqueued -- the engine's three
// C++ hooks (all through AiGetFactoryToBuild above) AND our own script rules
// that enqueue a factory directly (Builder::AdvancedPlantAtRear) -- must pass
// through here, where the caps, the tier discipline, the ledger and the
// approval log all live. apexearth has reported gate bypasses FOUR times
// ("we're still making a second T2 lab... whatever you do to fix it is not
// working"); every one was a second entrance. Do not add another: route it
// here.
string armafus("armafus");   string corafus("corafus");   string legafus("legafus");
string armpulsarS("armanni"); string corpulsarS("cordoom"); string legpulsarS("legbastion");

bool PlantApproved(CCircuitDef@ want)
{
	if (want is null)
		return false;
	SweepPlantAsks();
	const int have = int(want.count) + InFlightOf(want);
	// ONE basic air plant, full stop (apexearth, twice: "stop us from making
	// 2 t1 air labs"). Backstopped HERE so no entrance -- ours or the
	// unattributed C++ one ISSUES.md tracks -- can duplicate it.
	if (IsAirFactory(want) && ((userData[want.id].attr & (Attr::T2 | Attr::T3)) == 0)
		&& (have >= 1))
	{
		return false;
	}
	const int allowed = PlantsWanted(want);
	if (have >= allowed) {
		if (ai.frame >= gNextPlantCapLog) {
			gNextPlantCapLog = ai.frame + 60 * SECOND;
			AiLog(T() + "apex: " + want.GetName() + " held " + have + " >= "
				+ allowed + " at " + formatFloat(SteadyIncome(), "", 0, 0)
				+ " m/s -- no more of this type yet");
		}
		return false;
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
	// Air's exemption is POST-T2 only. apexearth, after a Greenhaven loss with
	// bot+vehicle+air all pre-T2: the air plant's own income floors did not
	// stop it, and pre-T2 the competition-for-metal argument applies to an air
	// plant exactly as to a second land lab.
	// The air exemption is the air STRATEGY's, not any air plant's: exempting
	// every post-T2 air plant let corap through with three T1-tier plants
	// standing (audit flag plant-gate, every audited game). Air::WantsFactory
	// is true exactly when the committed air lead is asking for this plant.
	if (((userData[want.id].attr & (Attr::T2 | Attr::T3)) == 0)
		&& (!IsAirFactory(want)
			|| (!Air::WantsFactory(want) && !Air::WantsIntelPlant(want))))
	{
		CCircuitDef@ navy = NavalOpening();
		if (!((navy !is null) && (want is navy))) {
			bool stillCompeting = !gHaveT2;
			if (!stillCompeting) {
				CCircuitDef@ advCon = aiFactoryMgr.GetRoleDef(want, RT::BUILDER2);
				const bool haveAdvCon = (advCon !is null) && (advCon.count > 0);
				CCircuitDef@ t2mex = SideDef3(armmoho, cormoho, legmoho);
				const bool haveT2Mex = (t2mex !is null) && (t2mex.count > 0);
				// ...and a REACTOR: apexearth, after the third second-T1-lab
				// report -- "we shouldn't make more than 1 until we have a
				// fusion or better. it really nerfs our early game." The
				// fusion is the milestone that says the economy is past the
				// stretch where a duplicate T1 line steals from tech.
				stillCompeting = !haveAdvCon || !haveT2Mex
						|| !Builder::HaveReactor();
			}
			const int t1have = T1PlantCount() + InFlightTier(0);
			if (stillCompeting ? (t1have >= 1) : (t1have >= allowed)) {
				if (ai.frame >= gNextT1TotalLog) {
					gNextT1TotalLog = ai.frame + 60 * SECOND;
					AiLog(T() + "apex: " + want.GetName() + " refused -- " + t1have
						+ " T1 plant(s) already, " + (stillCompeting ? "still competing with tech spend" : "at cap")
						+ ", at " + formatFloat(SteadyIncome(), "", 0, 0)
						+ " m/s the T2 plant is the better buy");
				}
				return false;
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
	// The intel/mandatory air plant is exempt from the T2-total discipline the
	// same way it is from the T1 one above: IntelPlantToBuild carries its own
	// income-scaled count, and holding it behind the LAND T2 budget is how long
	// games ended with no advanced air plant at all -- at 100-200 m/s the land
	// labs fill `allowed` and armaap was refused forever.
	// A SECOND advanced plant of ANY kind -- 2nd T2 lab, T2 air lab, intel
	// plant included -- waits until the base can survive being weak while it
	// pays for itself: an ADVANCED FUSION standing and PULSAR defense at home.
	// apexearth 2026-08-18: "we make a T2 air lab while we should still be
	// making our eco... super dangerous, we should instead make a pulsar in
	// our base... before we even have an afus yet. We make 2nd T2 lab, T2
	// air lab, all these things before we even have any pulsar defense."
	// The first T2 plant (the tech transition) is untouched; T3 gantries
	// keep their own earlier timing.
	if (((userData[want.id].attr & Attr::T2) != 0)
		&& (T2PlantCount() + InFlightTier(Attr::T2) >= 1)) {
		// THE FIRST T2 PLANT CAN NEVER BE "EXTRA". The count above includes
		// nanoframes and orphaned orders, so a first plant whose builders
		// keep dying wedged a player below T2 forever -- measured live
		// 2026-08-19: t0 refused coravp for minutes at 74-79 m/s with
		// haveT2=0, inflight=2, t2=1 (matches/_engine 27m). Until a T2 plant
		// actually STANDS, a blocked transition re-opens after
		// apex_t2_stuck_secs; the afus+pulsar discipline below governs only
		// genuinely EXTRA plants (a finished T2 exists).
		if (!gHaveT2) {
			if (gT2StuckSince < 0)
				gT2StuckSince = ai.frame;
			if (ai.frame - gT2StuckSince
				>= int(ai.GetTunable("apex_t2_stuck_secs", 240.f)) * SECOND)
			{
				gT2StuckSince = ai.frame;   // re-arm: one re-order per window
				AiLog(T() + "apex: first T2 plant is stuck unfinished -- "
					+ "re-opening the order for " + want.GetName());
				return true;
			}
			if (ai.frame >= gNextT2TotalLog) {
				gNextT2TotalLog = ai.frame + 60 * SECOND;
				AiLog(T() + "apex: " + want.GetName()
					+ " waits -- first T2 plant still under way");
			}
			return false;
		}
		CCircuitDef@ afus = SideDef3(armafus, corafus, legafus);
		CCircuitDef@ gun = SideDef3(armpulsarS, corpulsarS, legpulsarS);
		const bool safeEnough = (afus !is null) && (afus.count > 0)
				&& (gun !is null) && (gun.count > 0);
		if (!safeEnough) {
			if (ai.frame >= gNextT2TotalLog) {
				gNextT2TotalLog = ai.frame + 60 * SECOND;
				AiLog(T() + "apex: " + want.GetName() + " refused -- extra "
					+ "advanced plant waits for afus+pulsar (afus="
					+ (((afus !is null) && (afus.count > 0)) ? "1" : "0")
					+ " pulsar=" + (((gun !is null) && (gun.count > 0)) ? "1" : "0")
					+ ") at " + formatFloat(SteadyIncome(), "", 0, 0) + " m/s");
			}
			return false;
		}
	}
	if (((userData[want.id].attr & Attr::T2) != 0)
		&& !(IsAirFactory(want) && Air::WantsIntelPlant(want))) {
		CCircuitDef@ advCon2 = aiFactoryMgr.GetRoleDef(want, RT::BUILDER2);
		const bool haveAdvCon2 = (advCon2 !is null) && (advCon2.count > 0);
		CCircuitDef@ t2mex2 = SideDef3(armmoho, cormoho, legmoho);
		const bool haveT2Mex2 = (t2mex2 !is null) && (t2mex2.count > 0);
		const int t2have = T2PlantCount() + InFlightTier(Attr::T2);
		// A GIFTED advanced constructor makes the first T2 plant's main early
		// product redundant -- the fusion IS the better first buy then.
		// apexearth 2026-08-15: "making your first fusion should come before
		// making your first T2 lab (if you were given a T2 con by a teammate)."
		// Held only while the gifted con is actually alive to build it and the
		// economy clears the fusion ladder's own income bar -- either failing
		// releases the plant, so this cannot deadlock the tech path.
		if ((t2have == 0) && Builder::gGotAdvCon && haveAdvCon2
			&& !Builder::HaveReactor()
			&& (SteadyIncome() >= ai.GetTunable("apex_fusion_income", 30.f)))
		{
			if (ai.frame >= gNextT2TotalLog) {
				gNextT2TotalLog = ai.frame + 60 * SECOND;
				AiLog(T() + "apex: " + want.GetName() + " held -- gifted adv con"
					+ " builds the first fusion before the first T2 plant");
			}
			return false;
		}
		// The first fusion also comes before a SECOND T2 line: apexearth,
		// watching, 2026-08-15: "we make our second T2 lab before making our
		// first fusion... it slows down our economy by a lot."
		const bool stillCompeting2 = !haveAdvCon2 || !haveT2Mex2
				|| !Builder::HaveReactor();
		if (stillCompeting2 ? (t2have >= 1) : (t2have >= allowed)) {
			if (ai.frame >= gNextT2TotalLog) {
				gNextT2TotalLog = ai.frame + 60 * SECOND;
				AiLog(T() + "apex: " + want.GetName() + " refused -- " + t2have
					+ " T2 plant(s) already, " + (stillCompeting2 ? "still competing with adv con/T2 mex spend" : "at cap")
					+ ", at " + formatFloat(SteadyIncome(), "", 0, 0)
					+ " m/s");
			}
			return false;
		}
	}
	// Every plant the gate grants is logged and held in the ask ledger; the
	// C++ side has three enqueue paths and none of them logs, so this line is
	// the only attribution for "why did a lab appear".
	gAskDef.insertLast(want);
	gAskFrame.insertLast(ai.frame);
	gAskCount.insertLast(int(want.count));
	AiLog(T() + "apex: plant approved " + want.GetName()
		+ " have=" + have + "/" + allowed
		+ " t1=" + (T1PlantCount() + InFlightTier(0))
		+ " t2=" + (T2PlantCount() + InFlightTier(Attr::T2))
		+ " inflight=" + gAskDef.length()
		+ " at " + formatFloat(SteadyIncome(), "", 0, 0) + " m/s");
	return true;
}

// Maps where the whole team should open air. Curated: these carry a map-wide
// ground hazard (or ground-hostile layout) the terrain analysis cannot see.
// Matched case-insensitively as a substring of the map name.
bool AirMap()
{
	array<string> airMaps = {"acidicquarry"};
	string name = ai.GetMapName();
	for (uint i = 0; i < name.length(); ++i) {
		const uint8 c = name[i];
		if ((c >= 65) && (c <= 90))
			name[i] = c + 32;   // ASCII tolower; AngelScript string has no lower()
	}
	for (uint i = 0; i < airMaps.length(); ++i) {
		if (name.findFirst(airMaps[i]) >= 0)
			return true;
	}
	return false;
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
		// KNOWN AIR MAPS. Terrain analysis scores factories by traversable
		// area, and a map-wide hazard like acid is walkable-but-lethal --
		// invisible to it. This is map knowledge, the same way a human knows
		// it. apexearth, watching AcidicQuarry: "we should know that we need
		// to play as air."
		if (isStart && AirMap() && !IsAirFactory(pick)) {
			CCircuitDef@ ap = SideDef3(armap, corap, legap);
			if (ap !is null) {
				AiLog(T() + "apex: air map (" + ai.GetMapName()
					+ ") -- opening " + ap.GetName()
					+ " instead of " + pick.GetName());
				@gT1Fac = ap;
				return ap;
			}
		}
		if (isStart && IsAirFactory(pick) && !MayOpenAir() && !AirMap()) {
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

	// INTEL AIR: eyes, not a strike -- fires from apex_intel_air_income (25)
	// regardless of the enemy AA that gates Armed(). The old late fallback
	// below proposed a plant the gate then refused every time once the air
	// exemption was narrowed to Air::WantsFactory -- which is how a 60-minute
	// 4v4 ended with zero air (apexearth: "Air would help us understand the
	// enemy strength").
	CCircuitDef@ intelFac = Air::IntelPlantToBuild();
	if (intelFac !is null) {
		AiLog(T() + "apex: intel air plant " + intelFac.GetName());
		return intelFac;
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
	// The observed enemy living on the water is its own trigger, whatever the
	// map-wide percentages say: composition follows where the enemy IS, and an
	// unreachable enemy is the same emergency as stalled expansion, so it gets
	// the same lower income floor.
	const bool afloat = Military::EnemyAfloat();
	const bool waterEscape = IsWaterMap() || stalled || waterHeavy || afloat;
	if ((IsWaterMap() || IsMixedWaterMap() || stalled || afloat) && !HaveShipyard()
		&& (aiEconomyMgr.metal.income >= (waterEscape ? NAVY_MIN_INCOME_STALLED : NAVY_MIN_INCOME)))
	{
		CCircuitDef@ sy = NavalOpening();
		if (sy !is null) {
			AiLog(T() + "apex: " + (afloat ? "enemy afloat"
				: stalled ? "expansion stalled"
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
