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
// WHAT A FACTORY LINE SHOULD BUILD, which is not the same question as what the
// income curve could support. Every caller of this is a factory constructor
// quota, so both bounds AdvConsWanted already argues for belong here too:
// queued work, and whether metal is the thing we are short of.
int ConsWantedFor(CCircuitDef@ con)
{
	if (con is null)
		return 1;
	const bool advanced = (con.costM >= ADV_CON_COST);
	int want = ConsWantedTier(advanced, con.IsRoleAny(Unit::Role::AIR.mask));
	// The curve answers "how many could we support", not "how many have work".
	// Same ceiling as AdvConsWanted: a builder per apex_con_tasks_each queued
	// jobs is a builder with a real queue rather than one standing idle.
	//
	// ADVANCED ONLY. Task count is itself a product of how many constructors we
	// have, so clamping the T1 curve by it is a loop that settles low -- which
	// is the measured starvation the T2ArmyShort caller warns about (armack=7/3,
	// conT2 stuck at 4 against stock's 16). The overshoot being fixed here is a
	// late-game one, and late game is where the advanced curve runs away.
	const float per = ai.GetTunable("apex_con_tasks_each", TUNE_CON_TASKS_EACH);
	if (advanced && (per > 0.f)) {
		const int demand = int(float(aiBuilderMgr.GetBuildTaskCount()) / per) + 1;
		if (demand < want)
			want = demand;
	}
	// A STANDING REACTOR REQUEST IS TWO LANES OF WORK. With one T2 con the
	// fusion waits behind the moho queue (measured 2026-08-21: asked at
	// 12.8m, stood ~24m, nine mohos built in between). The economy that
	// justified the reactor buys the second pair of hands.
	if (advanced && (want < 2) && !HaveReactor() && (gFusionsAsked > 0)
		&& (Factory::SteadyIncome()
			>= ai.GetTunable("apex_fusion_prefer_income", TUNE_FUSION_PREFER_INCOME)))
	{
		want = 2;
	}
	// GREED BUYS BUILDERS. Stock's team eco players hold 2.5-4x our
	// constructor fleet by 10m (8v8 measured: con-metal 2130 vs 790 best)
	// and the mex race follows the con race. A PASSIVE stance is the
	// license: while the enemy visibly is not coming, the con curve rises.
	if (Military::Stance() == int(Military::S_PASSIVE)) {
		want = int(float(want)
				* Policy::GreedCons());
	}
	// AN EMPTY BANK IS NOT A BUILD-POWER SHORTAGE. More constructors add build
	// power we cannot feed, and cost the metal we do not have -- the mirror of
	// the full-bank bonus the facqueue applies on the other side.
	if (aiEconomyMgr.isMetalEmpty)
		want = int(float(want) * ai.GetTunable("apex_con_empty_mult", TUNE_CON_EMPTY_MULT));
	// THE BUDGET BINDS ITS BIGGEST SPENDER. Cons and labs are the BUILDPOWER
	// category, and this curve answered only "how many could we support" --
	// measured 2026-08-20 (t009 Altored): bp share 0.62 against target 0.16
	// while army sat at 0.10 of a 0.48 target, and the game was lost with the
	// commander alone at home. While build power is over its share and the
	// army is under its own, the want scales down by the overage ratio -- a
	// deferral that reopens by itself as the shares move, not a cap.
	const float bpShare = Brain::ShareOf(Brain::BUILDPOWER);
	const float bpTarget = Brain::TargetShare(Brain::BUILDPOWER);
	if ((bpShare > bpTarget)
		&& (Brain::ShareOf(Brain::ARMY) < Brain::TargetShare(Brain::ARMY)))
	{
		float mult = bpTarget / bpShare;
		const float lo = ai.GetTunable("apex_con_budget_floor", TUNE_CON_BUDGET_FLOOR);
		if (mult < lo)
			mult = lo;
		want = int(float(want) * mult);
	}
	return (want < 1) ? 1 : want;
}

int ConsWantedTier(bool advanced, bool air)
{
	const float inc = aiEconomyMgr.metal.income;
	if (inc < 2.f)
		return 1;
	const float a = advanced ? Policy::ConLogT2A() : Policy::ConLogT1A();
	const float b = advanced ? Policy::ConLogT2B() : Policy::ConLogT1B();
	const int want = int(a * log(inc) + b);
	return (want < 1) ? 1 : want;
}

// A FULL METAL BANK MEANS "WE CANNOT SPEND", WHICH IS NOT ALWAYS "WE ARE RICH".
//
// apexearth 2026-08-19: "sometimes it's really bad because we also don't have
// any energy... it happens right after we got attacked. So our build power got
// interrupted, but they didn't hit enough of our economy. So we're full of
// metal. Maybe they killed our fusion. So we're kinda trying to rebuild, but we
// just make 6 advanced cons while we also slowly rebuild our energy."
//
// Constructors CONSUME energy to build, so answering an energy-caused metal
// surplus with more constructors makes the thing that caused it worse. The bank
// only argues for more builders when the reason it is full is that we have more
// metal than hands -- not when it is full because the grid is down.
//
// Reuses the energy lane's own forecast (apex_energy_headroom) rather than a new
// number, and refuses outright while a generator is being rebuilt: that IS the
// "we are recovering" case, and it is exactly when the surge was landing.
bool MetalSurplusIsReal()
{
	if (!aiEconomyMgr.isMetalFull)
		return false;
	if (aiEconomyMgr.isEnergyStalling)
		return false;
	if (aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::ENERGY)) > 0)
		return false;
	const float need = aiEconomyMgr.energy.pull * Policy::EnergyHeadroom();
	return aiEconomyMgr.energy.income >= need;
}

// A full bank overrides the curve, added on top rather than folded into it.
int AdvConsWanted()
{
	int want = ConsWantedTier(true, false);
	if (MetalSurplusIsReal())
		want += ADV_CON_FULL_BONUS;

	// What the economy can afford is a ceiling, not a target: the curve above
	// answers "how many could we support", not "how many have queued work" --
	// building straight to it puts metal into idle builders instead of army.
	// CEconomyManager::MakeEconomyTasks saturates at buildTasksCount ==
	// workers * 8, so wanting one at half that is a builder with a real queue.
	const float per = ai.GetTunable("apex_con_tasks_each", TUNE_CON_TASKS_EACH);
	const int demand = (per > 0.f)
			? int(float(aiBuilderMgr.GetBuildTaskCount()) / per) + 1 : want;
	return (demand < want) ? demand : want;
}

bool NeedsAdvCon()
{
	return gAdvConCount < AdvConsWanted();
}

int AdvConCount()
{
	return gAdvConCount;
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
	//
	// NOT in a duel: with no allies there are no gifts, but this branch set
	// the flag on our OWN first adv con, and the choose.as "gifted adv con
	// builds the first fusion before the first T2 plant" hold then treated
	// our only builder as a spare -- measured 2026-08-20 (46m seed-27 loss),
	// it held the T2 lab REBUILD from 32.7m to game end, haveT2=0 for the
	// last 13 minutes.
	if (ai.teamId != Factory::RushLeadTeamId()) {
		if (!Persona::Duel())
			gGotAdvCon = true;   // we have ours; stop paying for the lead's
		return false;
	}

	// AT A REAL RESOURCE BONUS THE TRANSACTION IS OFF (apexearth 2026-08-22:
	// "When we are +100 handicap we do not need to give T2 constructors to
	// teammembers. I think at +50 and above we don't need to share these.")
	// -- a bonused teammate affords its own; the lead keeps every con for
	// its own scaling. The sling still runs: it funds the lead's plant and
	// eco, which is what the team is buying at any handicap.
	if (!Role::GiftsCons()) {
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
	// While ANY teammate still lacks its constructor, the keep-floor drops to
	// the tunable (default 1): the teammates PAID for these cons via the
	// sling, so delivery outranks the lead's own fleet. The income-scaled
	// floor above delivered the first gift at minute 18 of a 23-minute game
	// (apexearth: "Gifts should be coming out earlier than 10m - all of
	// them"); once everyone has one it governs again as before.
	array<Id>@ roster = ai.GetTeamIds();
	if ((roster !is null) && (gGifted.length() + 1 < roster.length()))
		keep = int(ai.GetTunable("apex_role_gift_keep", TUNE_ROLE_GIFT_KEEP));
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
