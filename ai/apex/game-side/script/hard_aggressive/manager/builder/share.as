namespace Builder {


// The lead techs first, then hands advanced constructors to teammates so they
// can build T2 without each paying for their own advanced factory. 300
// separates every faction's dearest T1 con (200) from its cheapest T2 (330).
const float ADV_CON_COST = 300.f;   // T1 cons are 100-200, T2 330-700
int gAdvConsMade = 0;
int gAdvConsGifted = 0;

array<int> gGifted;   // teams that already received their advanced con

// True while teammates are still waiting on an advanced constructor of their
// own. Set on a follower once the lead's gifted constructor arrives, which is
// the local signal to stop sending it metal for this purpose.
bool gGotAdvCon = false;

// True once we hold an advanced constructor of our own, however we came by it --
// built or gifted.
bool gHaveAdvCon = false;

// How many we hold. Factory ratios alone can't be relied on to build enough:
// Cortex's coravp weights constructors at ~1% against correap's 61%, so
// whatever this rule doesn't force doesn't get built.
int gAdvConCount = 0;

// Income is the thing an extra advanced constructor is there to spend. Below the
// first step one is plenty; a player running a real economy should be building
// out, and that is where the T2/T3 gap comes from.
const float ADV_CON_INCOME_STEP = 25.f;
// What a full bank is worth in extra constructors: a full bank means more
// build power to spend it, not less.
const int   ADV_CON_FULL_BONUS  = 6;

// Constructors wanted, logarithmic in income rather than linear: a base has
// finite room and a ground hitbox per constructor, so the return on the
// twentieth is not the return on the second, and a linear formula keeps
// climbing past any number that fits. Air constructors have no ground hitbox
// and so are exempt from the ceiling this curve otherwise justifies, but the
// curve is still a floor for everyone -- it must never return an effectively
// unbounded value, since BuildPowerFirst treats "below this number" as
// license to keep building constructors and nothing else.

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

// A full bank overrides the curve, added on top rather than folded into it.
int AdvConsWanted()
{
	int want = ConsWantedTier(true, false);
	if (aiEconomyMgr.isMetalFull)
		want += ADV_CON_FULL_BONUS;

	// What the economy can afford is a ceiling, not a target: the curve above
	// answers "how many could we support", not "how many have queued work" --
	// building straight to it puts metal into idle builders instead of army.
	// CEconomyManager::MakeEconomyTasks saturates at buildTasksCount ==
	// workers * 8, so wanting one at half that is a builder with a real queue.
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

	// Military::UpdateSling reads gGotAdvCon to stop donating metal to the
	// lead once a follower has its own advanced constructor.
	if (ai.teamId != Factory::RushLeadTeamId()) {
		gGotAdvCon = true;   // we have ours; stop paying for the lead's
		return false;
	}

	++gAdvConsMade;
	// The keep-floor scales with the lead's OWN economy, not a flat one: at
	// 8v8 the flat floor gifted seven in a row while the lead ran a 13k-energy
	// base on a single constructor and its first moho slipped to minute 18
	// (apexearth: "they only made 1 advanced con for themselves... maybe this
	// is a tech player issue?"). Half of AdvConsWanted keeps early gifting
	// unchanged (wanted 2 -> keep 1) and retains the moho/reactor/converter
	// lanes' workers once the income is real.
	int keep = AdvConsWanted() / 2;
	if (keep < 1)
		keep = 1;
	if ((gAdvConsMade - gAdvConsGifted) <= keep)
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


// Fusions we hold, so one can be handed to an ally that is being killed --
// permanent income is worth more to a losing base than a lump of metal it has
// no time to spend.
//
// Handles carry the same NOCOUNT hazard as gComm/gT1FacUnit: the engine does
// not null a handle when the unit dies, so each must be dropped in
// AiUnitRemoved or a later gift dereferences freed memory.
array<CCircuitUnit@> gFusions;
const uint FUSION_KEEP = 2;   // the ones our own economy runs on are never given

CCircuitUnit@ energizer1 = null;
CCircuitUnit@ energizer2 = null;

// AIFloat3 lastPos;
// int gPauseCnt = 0;

}  // namespace Builder
