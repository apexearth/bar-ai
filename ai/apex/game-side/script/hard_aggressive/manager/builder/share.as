namespace Builder {


// The lead techs first, then hands advanced constructors to teammates so they
// can build T2 without each paying for their own advanced factory.
// Checked against BAR's unit defs for all three factions rather than assumed:
// the dearest T1 constructor is 200 (armcs, armch, corcs) and the cheapest
// advanced one 330 (legaca), so one threshold separates them everywhere.
const float ADV_CON_COST = 300.f;   // T1 cons are 100-200, T2 330-700
int gAdvConsMade = 0;
int gAdvConsGifted = 0;

array<int> gGifted;   // teams that already received their advanced con

// Observed live: the lead built its first T2 constructor and handed it straight
// over, leaving itself none. Two bugs behind it. This was called for EVERY unit
// added with no role filter, so any unit costing 300+ metal bumped the counter
// -- and the unit actually given away was whatever triggered the call, which
// need not be a constructor at all. And the guard counted cons ever MADE rather
// than cons currently HELD, so once the count was used up by combat units the
// next real constructor went out the door.
//
// Rule: never give one away while we hold only one ourselves.
// True while teammates are still waiting on an advanced constructor of their own.
// Set on a follower the moment the lead's gifted constructor arrives. That is
// the local signal that the pooling has paid off for us -- observed live, allies
// were still sending metal at 17 minutes, long after every con had been handed
// out, which is just donating our economy away.
bool gGotAdvCon = false;

// True once we hold an advanced constructor of our own, however we came by it --
// built or gifted.
bool gHaveAdvCon = false;

// How many we hold. One was the old target, and the factory ratios cannot make
// up the difference: Cortex's coravp weights constructors at ~1% against
// correap's 61%, so whatever this rule does not force does not get built.
// Measured over 16 games: 3 advanced constructors per player against stock's 8,
// with T2 spend 28,451 against 44,060 and T3 2,378 against 8,186.
int gAdvConCount = 0;

// Income is the thing an extra advanced constructor is there to spend. Below the
// first step one is plenty; a player running a real economy should be building
// out, and that is where the T2/T3 gap comes from.
const float ADV_CON_INCOME_STEP = 25.f;
// What a full bank is worth in extra constructors. apexearth: "if we are full on
// metal then obviously we need more factories/builders spending it."
const int   ADV_CON_FULL_BONUS  = 6;

// HOW MANY CONSTRUCTORS AN ECONOMY IS WORTH, LOGARITHMICALLY.
//
// Linear in income was wrong in both directions: 1 + income/25 gives 5 at 100
// metal/s where a player wants ten, and the T1 version (1 + income/6, and 1 +
// income/30 before that) keeps climbing past any number of bodies a base has
// room for. Constructors have a ground hitbox and a base has finite room, so the
// return on the twentieth is not the return on the second.
//
// The curve is fitted to apexearth's own numbers, given as a shape rather than a
// cap: "At 8 metal per second we could have ~3 T1 cons. At 100m/s maybe 15
// limit? At 500 metal per second? Idk... 20, 25?" and for T2 "20m/s 2 T2 cons?
// 100m/s 10 T2 cons? 500m/s ~25?"
//
//   income   8    20    40   100   250   500  1000        he said
//   T1     3.0   7.2  10.4  14.6  18.8  22.0  25.2        3 / 15 / 20-25
//   T2       1   2.0   6.1  11.6  17.1  21.3  25.4        2 / 10 / ~25
//
// T1 passes through all three of his points. T2 splits the difference between
// them -- through 20 and 500 exactly it would want 13.5 at 100, through 20 and
// 100 it would want 17 at 500. All four coefficients are tunable, because the
// top of the curve is where he was least certain.
//
// "Air cons would never need a limit since they have no ground hitbox to worry
// about." The ceiling that room-in-the-base justifies is what air does not need,
// and it no longer has one: behaviour.json's flat armca/corca limits are gone.
//
// It must NOT mean an unbounded FLOOR. This returned 9999, and BuildPowerFirst
// uses the number as "build a constructor while below it" -- so an air plant the
// mix claimed could never satisfy the floor, returned a constructor on every
// call, and built nothing else for the rest of the game. The floor is what the
// income justifies for everyone; only the ceiling was ever the air question.

// The def-taking form. mix.as is included BEFORE builder.as in main.as, so a
// const declared here is not visible there -- functions are module-wide but
// globals are not. Reading the tier off the def happens on this side of that
// line for exactly that reason.
int ConsWantedFor(CCircuitDef@ con)
{
	if (con is null)
		return 1;
	return ConsWantedTier(con.costM >= ADV_CON_COST,
			con.IsRoleAny(Unit::Role::AIR.mask));
}

int ConsWantedTier(bool advanced, bool air)
{
	const float inc = aiEconomyMgr.metal.income;
	if (inc < 2.f)
		return 1;
	const float a = advanced ? ai.GetTunable("apex_con_log_t2_a", 6.0f)
	                         : ai.GetTunable("apex_con_log_t1_a", 4.6f);
	const float b = advanced ? ai.GetTunable("apex_con_log_t2_b", -16.0f)
	                         : ai.GetTunable("apex_con_log_t1_b", -6.55f);
	const int want = int(a * log(inc) + b);
	return (want < 1) ? 1 : want;
}

// apexearth: "if we are full on metal then obviously we need more
// factories/builders spending it." A full bank is the economy overriding the
// curve, which is why this is added on top rather than folded into it.
int AdvConsWanted()
{
	int want = ConsWantedTier(true, false);
	if (aiEconomyMgr.isMetalFull)
		want += ADV_CON_FULL_BONUS;

	// WHAT THE ECONOMY CAN AFFORD IS A CEILING, NOT A TARGET. apexearth,
	// watching: "we made ~10 T2 cons on purple this game instead of making army
	// and defenses.... too much build power, not enough economy."
	//
	// The curve above answers "how many could we support", and we then built
	// straight to it whether or not there was anything for them to do -- so the
	// ceiling became the goal and the metal went into builders standing around
	// instead of into army. A constructor is only worth its cost while there is
	// work queued for it.
	//
	// The unit of "enough work" is the engine's own: CEconomyManager::
	// MakeEconomyTasks refuses to create more once buildTasksCount reaches
	// workers * 8, so eight tasks per worker is saturation by its reckoning.
	// Wanting another one at half that is a builder who would have a queue.
	const float per = ai.GetTunable("apex_con_tasks_each", 4.f);
	const int demand = (per > 0.f)
			? int(float(aiBuilderMgr.GetBuildTaskCount()) / per) + 1 : want;
	return (demand < want) ? demand : want;
}

bool NeedsAdvCon()
{
	return gAdvConCount < AdvConsWanted();
}

bool OwesAdvCons()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	for (uint i = 0; i < mates.length(); ++i) {
		const int cand = int(mates[i]);
		if ((cand != ai.teamId) && (gGifted.find(cand) < 0))
			return true;
	}
	return false;
}

// Returns true when the unit was handed to an ally, i.e. is no longer ours.
bool ShareAdvCon(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// Actual constructors only -- not commanders, not expensive tanks.
	if (usage != Unit::UseAs::BUILDER)
		return false;
	const CCircuitDef@ cdef = unit.circuitDef;
	if (cdef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if (cdef.costM < ADV_CON_COST)
		return false;

	// The follower half of the test used to sit BELOW a lead-only early return,
	// so it could never once be true and gGotAdvCon was never set. That is why
	// the symptom its own comment describes -- allies still slinging metal at 17
	// minutes -- survived the fix: Military::UpdateSling reads this flag to stop
	// donating, and it was permanently false.
	if (ai.teamId != Factory::RushLeadTeamId()) {
		gGotAdvCon = true;   // we have ours; stop paying for the lead's
		return false;
	}

	++gAdvConsMade;
	// Keep at least one for ourselves at all times: the lead is the player whose
	// job it is to upgrade mexes, and it cannot do that with no constructor.
	if ((gAdvConsMade - gAdvConsGifted) <= 1)
		return false;

	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	// One each and then stop. Every teammate needs a T2 con to start upgrading
	// its own mexes; past that we are just giving our build power away.
	for (uint i = 0; i < mates.length(); ++i) {
		int cand = int(mates[i]);
		if ((cand == ai.teamId) || (gGifted.find(cand) >= 0))
			continue;
		gGifted.insertLast(cand);
		++gAdvConsGifted;
		array<CCircuitUnit@> gift;
		gift.insertLast(unit);
		ai.GiveUnits(gift, cand);
		AiLog(Factory::T() + "apex: gave adv con to team " + cand + " (held "
			+ (gAdvConsMade - gAdvConsGifted + 1) + ", keeping "
			+ (gAdvConsMade - gAdvConsGifted) + ")");
		return true;
	}
	return false;
}


// Fusions we hold, so one can be handed to an ally that is being killed.
// apexearth: "it can also share a fus or afus to help them." A reactor is 4,300
// metal of permanent income, which is worth far more to a player whose base is
// being taken apart than another lump of metal it has no time to spend.
//
// Handles, so the same NOCOUNT hazard as gComm and gT1FacUnit applies: the
// engine does not null a handle when the unit dies, so every one of these has to
// be dropped in AiUnitRemoved or a later gift dereferences freed memory.
array<CCircuitUnit@> gFusions;
const uint FUSION_KEEP = 2;   // the ones our own economy runs on are never given

CCircuitUnit@ energizer1 = null;
CCircuitUnit@ energizer2 = null;

// AIFloat3 lastPos;
// int gPauseCnt = 0;

}  // namespace Builder
