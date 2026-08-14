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
	// Solo we are the only player, so we are trivially the one who techs. This
	// is the OPPOSITE of the rusher tests: those coordinate between allies and
	// must be false alone; this asks "is teching my job", and alone it always
	// is. Getting this backwards would stop a 1v1 teching at all.
	if (!TeamPlay())
		return true;
	RefreshLead();
	if (gAmLead)
		return true;
	// Nobody has been elected yet: defer to the engine's own pick, exactly as
	// this did when there was only ever one slot.
	return !LeadIsDesignated() && (ai.teamId == RushLeadTeamId());
}

// RushLeadTeamId falls back to ai.GetLeadTeamId() (lowest team id) until
// someone is elected. Rush-lead behaviour (suppressing our own army, sling
// target, skipping defence, holding followers back) only makes sense with
// allies to pool with; alone it is one player playing worse for no reason.
bool HaveAllies()
{
	array<Id>@ roster = ai.GetTeamIds();
	return (roster !is null) && (roster.length() > 1);
}

// Has anyone actually been designated yet?
bool LeadIsDesignated()
{
	if (!HaveAllies())
		return false;
	return ai.ReadTeamValue(ElectorTeamId(), TV_LEAD, -1.f) >= 0.f;
}

// May THIS instance pursue the advanced plant?
//
// Before anyone is designated, whoever is ready may pursue it -- RushReady()
// already requires a real economy. Once a lead is designated, only it
// continues, so the team pools behind one player instead of four. Follower
// release is economy-gated (FollowerEconomyReady) rather than frame-gated, so
// it cannot open for every non-lead at once the way a shared clock did.
bool MayPursueT2()
{
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

// Minimum METAL income before committing to T2 as lead. The energy gates below
// cover whether we can power a plant, not whether the lead can feed itself
// while the whole team pools behind it.
const float RUSH_MIN_METAL = 14.f;

bool RushReady()
{
	// Tunable for A/B testing. In a 1v1 the player IS the lead, so this branch
	// is the only gate on committing to T2.
	if (aiEconomyMgr.metal.income < ai.GetTunable("apex_rush_min_metal", RUSH_MIN_METAL))
		return false;
	return (aiEconomyMgr.energy.income > RUSH_ENERGY_TARGET)
		|| ((ai.frame > RUSH_LATEST) && (aiEconomyMgr.energy.income > RUSH_ENERGY_FLOOR));
}

// Metal a non-lead must be earning before it may take T2.
const float FOLLOWER_TECH_INCOME = 25.f;
// Backstop time bound; the real follower gate is FollowerEconomyReady() below
// -- what actually blocks a follower is AiIsSwitchAllowed's own bank/army-cost
// requirement (armyCost > 1.2 x cost x facCount, or the full plant cost
// banked), which this frame does not override the way the rush branch's
// no-bank switch does for the lead.
const int   FOLLOWER_TECH_FRAME  = 10 * MINUTE;

// Energy a follower must be making before taking T2 -- an advanced plant and
// its units are energy-hungry, and teching on a thin grid stalls the base
// instead of growing it. Set above what today's economy typically reaches; if
// followers stop teching entirely, check eInc in the T2GATE log before
// lowering it.
const float FOLLOWER_TECH_ENERGY = 600.f;

// May a non-lead take an advanced plant yet? Both halves, because teching on
// metal alone stalls the base rather than growing it.
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
