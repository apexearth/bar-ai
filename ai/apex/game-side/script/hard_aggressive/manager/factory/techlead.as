namespace Factory {

string armmoho ("armmoho");
string cormoho ("cormoho");
string legmoho ("legmoho");

// One advanced extractor standing. A T2 mex is roughly a 300% increase on that
// spot's metal and pays for the next constructor by itself, so it comes before
// a second constructor and before the T1.5 defence rung.
bool gHaveT2Mex = false;   // latched: an upgraded mex does not un-upgrade

bool HaveT2Mex()
{
	if (gHaveT2Mex)
		return true;
	CCircuitDef@ moho = SideDef3(armmoho, cormoho, legmoho);
	gHaveT2Mex = (moho !is null) && (moho.count > 0);
	return gHaveT2Mex;
}

bool IsTechLead()
{
	RefreshLead();
	if (gAmLead)
		return true;
	// Nobody has been elected yet: defer to the engine's own pick, exactly as
	// this did when there was only ever one slot.
	return !LeadIsDesignated() && (ai.teamId == RushLeadTeamId());
}

// Has anyone actually been designated yet?
//
// Until the gadget publishes one, RushLeadTeamId falls back to
// ai.GetLeadTeamId() -- the engine's ally leader, which is always the lowest
// team id. That made team 0 declare itself the rusher at frame 0, so it was the
// only player that ever tried to tech, so it was always first to commit, so it
// was always elected. Observed live: blue built the first advanced plant every
// single game, even when green was richer and ready sooner. "Whoever commits
// first" had quietly collapsed into "team 0".
bool LeadIsDesignated()
{
	return ai.ReadTeamValue(ElectorTeamId(), TV_LEAD, -1.f) >= 0.f;
}

// May THIS instance pursue the advanced plant?
//
// Before anyone is designated the answer is "whoever is ready" -- that is the
// whole point of selecting on commitment rather than prediction, and RushReady
// already demands a real economy behind it. Once someone is designated, only
// they continue, so the team pools behind one player instead of four.
bool MayPursueT2()
{
	// Only the designated lead. The elector now designates on READINESS as well as
	// commitment, so there is no window where nobody holds the title and everyone
	// is therefore free to spend. "Whoever is ready" was open to all of them at
	// once. This cannot deadlock the way gating on commitment did: that needed a
	// plant nobody was allowed to start, whereas readiness is earned by the economy
	// growing. The frame clause is a backstop only -- past it the rush window is
	// over and followers are released anyway.
	// The release used to be a clock, and the clock is what let everyone in: past
	// FOLLOWER_TECH_FRAME this returned true for every player at once, and the
	// rush branch then asked only for RUSH_MIN_METAL. A non-lead now earns T2
	// with its economy instead of by waiting.
	return IsDesignatedLead() || FollowerEconomyReady();
}

// Am I the ACTUAL designated lead? Distinct from IsTechLead(), which is true for
// team 0 from frame 0 via the fallback. Role behaviour -- suppressing our army,
// being the sling target, skipping defence -- must key on this, or team 0 idles
// its army from the opening and the whole team feeds it before anyone has
// earned the role.
bool IsDesignatedLead()
{
	return LeadIsDesignated() && IsTechLead();
}

// Minimum METAL income before committing to T2. The energy gates below say
// "can we power a plant"; nothing said "can we afford to be the player the whole
// team pools behind". Measured on Quicksilver 4v4: apex committed at 2.9 min on
// 6.0 metal/s while stock waited until 9.1 min on 35.9, and apex lost. A lead
// that cannot feed itself turns the pooling into one starving player plus three
// donors. apexearth: "don't do T2 unless you got like fourteen metal per second
// ... instead we just have one useless team member".
const float RUSH_MIN_METAL = 14.f;

bool RushReady()
{
	// Tunable so the threshold can be A/B'd rather than argued about.
	// apexearth, watching a 1v1: "in this game im watching we really failed to
	// take mexes before making the T2 it seemed". 14 metal/s is about five or
	// six mexes; in a 1v1 the player IS the lead, so this rush branch is the one
	// that fires and nothing else holds it back.
	if (aiEconomyMgr.metal.income < ai.GetTunable("apex_rush_min_metal", RUSH_MIN_METAL))
		return false;
	return (aiEconomyMgr.energy.income > RUSH_ENERGY_TARGET)
		|| ((ai.frame > RUSH_LATEST) && (aiEconomyMgr.energy.income > RUSH_ENERGY_FLOOR));
}

// Metal a NON-LEAD must be making before it may take T2. This constant existed
// and was never read by anything -- the follower routes all gated on metal 18 or
// on nothing at all.
//
// apexearth, watching an 8v8: "if someone is not rushing T2 then they really
// need more metal and energy income before they try for it ... ~25+ metal per
// second along with ~600+ energy".
const float FOLLOWER_TECH_INCOME = 25.f;
// Was 13 min, tuned when the lead itself only reached T2 around 20. The lead now
// has its plant at a median of 6.3 min and starts handing out advanced
// constructors well before 13, so holding followers that long leaves them
// sitting on cons they are not allowed to use. Measured: followers teched at
// 15-21 min while the rusher was done at 5.4.
// Tried 9 minutes, on the reasoning that the lead now techs at 6.3 so followers
// should not wait until 13. Measured across 5 maps it went the wrong way: real
// K/D fell from ~1.00 to 0.64 and standing army from 19.3k to 15.9k, because
// each follower started its OWN advanced plant during the window where the team
// still has to hold the ground -- which is the "4 AI all trying to make T2 =
// SLOW" failure this whole pooling strategy exists to avoid. Followers get T2
// from the constructors the lead hands them, not from their own factories.
// THE economy bottleneck, found by comparing composition: stock builds 14,625
// metal of T2 units to apex's 4,595 and upgrades 2.9 mexes to our 1.4. The
// pooling design gets ONE player to T2 quickly, but stock's everyone-techs-
// independently ends up with far more T2 economy in total -- measured, three of
// four followers still read haveT2=0 at eighteen minutes while earning 30-73
// metal/s. A fast tech lead is worthless if it is the team's only one.
//
// 9 minutes was tried before and looked bad, but that measurement contained the
// duplicate-factory bug (AiIsSwitchTime held permanently open), so it is void.
// Tried 10 minutes to unblock follower teching. It did NOT work: t2Mex moved
// 1.4 -> 1.5 and T2 unit spend 4,595 -> 4,652, i.e. nothing, while the run lost
// 4-13 with the CI excluding 50%. So the clock was never the blocker.
//
// What actually blocks a follower is the SAME stock gate that once blocked the
// lead, in AiIsSwitchAllowed below: armyCost > 1.2 x cost x facCount, or the
// full plant cost banked. A follower never holds 2800 metal, so it never techs
// whatever the clock says. The lead only escapes because the rush branch above
// grants it a no-bank switch. Giving followers an equivalent -- place it and
// pour income in -- is the actual fix, and is untested.
// Retested at 10 now that the metal gate below is released. The earlier 10-min
// test was CONFOUNDED: followers were blocked by AiIsSwitchAllowed's bank
// requirement whatever the clock said, so moving the clock could not show an
// effect and t2Mex went 1.4 -> 1.5. With the gate open the clock is finally the
// binding constraint, and followers still convert only 7.7k of T2 against
// stock's 12.2k -- they tech, but too late to compound.
const int   FOLLOWER_TECH_FRAME  = 10 * MINUTE;

// Energy a FOLLOWER must be making before it may take T2. An advanced plant and
// its units are energy-hungry, and teching on a thin grid stalls the base rather
// than growing it -- followers were being granted T2 on metal alone.
//
// Deliberately above what the AI currently reaches: measured across a 20-minute
// 4v4, energy income ran ~130/s at 5 min, ~290 at 8 and ~415 at 14. Those peaks
// are low BECAUSE energy was under-prioritised, which the raised
// economy.energy.factor is meant to correct; this bar is what the economy should
// clear, not what it clears today. If followers stop teching at all, that is the
// factor being too low, not this number being wrong -- check eInc in the T2GATE
// log before lowering it.
const float FOLLOWER_TECH_ENERGY = 600.f;

// May a non-lead take an advanced plant yet? Both halves, because teching on
// metal alone stalls the base rather than growing it.
//
// This replaces a pure clock. The clock is what produced the stampede: every
// follower gate was bounded by FOLLOWER_TECH_FRAME, so at ten minutes they all
// expired at once and the rush branch below granted T2 to anyone holding
// RUSH_MIN_METAL. Measured, 8v8 Supreme Isthmus: seven of eight players
// committed to an advanced plant, five of them inside fifteen minutes, and
// every single one did it at 14-16 metal/s. Army share came out 19.3% against
// stock's 31.7% and T1 spend 11,671 against 26,879.
bool FollowerEconomyReady()
{
	return (aiEconomyMgr.metal.income >= FOLLOWER_TECH_INCOME)
		&& (aiEconomyMgr.energy.income >= FOLLOWER_TECH_ENERGY);
}


enum Attr {
	T1 = 0x0001, T2 = 0x0002, T3 = 0x0004, T4 = 0x0008
}

class SUserData {
	SUserData(int a) {
		attr = a;
	}
	SUserData() {}
	int attr = 0;
}

// Example of userData per UnitDef
array<SUserData> userData(ai.GetDefCount() + 1);

}  // namespace Factory
