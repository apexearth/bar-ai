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

// No ceiling. apexearth: "we shouldn't have any hard caps, everything needs to be
// balanced based on the economy/game progression." The old ADV_CON_MAX of 4 bound
// from about 75 metal/second upward, so every economy from a modest one to 400+
// got the same four constructors -- which is most of why a large bank never
// turned back into units.
int AdvConsWanted()
{
	int want = 1 + int(aiEconomyMgr.metal.income / ADV_CON_INCOME_STEP);
	if (aiEconomyMgr.isMetalFull)
		want += ADV_CON_FULL_BONUS;
	return want;
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
