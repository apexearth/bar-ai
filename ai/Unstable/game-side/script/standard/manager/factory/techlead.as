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
// EARN THE PLANT BEHIND AN ARMY. apexearth 2026-08-19: "let's not go to T2
// unless we have a reasonably sized T1 army for our income -- so if we have ~30
// metal per second, let's have an army of ~3000." His figure, expressed as the
// ratio it is: 100 metal of army per metal/second of income, so the bar rises
// with the economy rather than sitting at a number that stops meaning anything.
// Per-instance through Persona::T2ArmyBias, so identical players do not all
// tech at the same moment.
const float T2_ARMY_PER_INCOME = 100.f;

float T2ArmyFloor()
{
	return aiEconomyMgr.metal.income
		* ai.GetTunable("apex_t2_army_per_income", TUNE_T2_ARMY_PER_INCOME)
		* Persona::T2ArmyBias();
}

int gNextT2ArmyLog = 0;

// Committing to T2 idles the army line (RushBuildPower) and waives the switch's
// own army-value requirement, so it is exactly the moment we must not be
// fielding nothing. Once T2 is up this stops asking -- the floor is about the
// transition, not a standing tax on the whole game.
bool T2ArmyReady()
{
	if (gHaveT2)
		return true;
	// The eco role's army is zero BY DESIGN -- asking it to field an army
	// before teching contradicts the role. Its cover is the team, which is
	// the deal the role is.
	if (IsEcoLead())
		return true;
	const float floorM = T2ArmyFloor();
	if (floorM <= 0.f)
		return true;
	const float have = aiMilitaryMgr.armyCost;
	if (have >= floorM)
		return true;
	// A RATIO TO INCOME IS A MOVING TARGET. Measured over a 40-minute run the
	// bar reached 5400 while the army stalled at 1856 -- income outgrew army
	// production and T2 never came at all. "Reasonably sized" is also answerable
	// against what we actually face, so matching the enemy's fielded army passes
	// too, and the gate cannot lock forever.
	const float theirs = Military::EnemyArmyCost();
	if ((theirs > 0.f) && (have >= theirs))
		return true;
	// THE TEAM'S ARMY COUNTS. In an 8v8 a pressured player's own army reads
	// ~0 forever (it dies as fast as it pools) and this gate blocked 178-306
	// times across 39 minutes per stuck player -- half the team finished
	// with 0-2 T2 cons and the side was out-scaled end-game in every team
	// format (mex end ratio 0.85 -> 0.51 monotone in team size). Defence is
	// collective: a player whose SIDE fields the floor's worth may tech.
	if (TeamPlay() && (Military::TeamArmyCost() >= floorM))
		return true;
	// DEFENCE COUNTS AS BEING ABLE TO HOLD. The floor asks whether committing to
	// the plant leaves us defenceless; a base behind guns is not. apexearth's own
	// doctrine for this game -- "hunker down and make them bleed" -- means the
	// turtling player must still be allowed to tech, or hunkering down becomes a
	// permanent T1 sentence. Measured without this: 0 of 6 games reached T2 at
	// all, 91 blocks in one game, and the metal went into advanced solars instead.
	if (have + Military::OwnDefenceMetal() >= floorM)
		return true;
	if (ai.frame >= gNextT2ArmyLog) {
		gNextT2ArmyLog = ai.frame + 60 * SECOND;
		AiLog(T() + "T2GATE blocked T2ArmyReady army="
			+ formatFloat(have, "", 0, 0) + "/" + formatFloat(floorM, "", 0, 0)
			+ " enemy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0)
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " persona=" + Persona::Name());
	}
	return false;
}

// May THIS instance pursue the advanced plant?
// THE T1-COMMIT EXPERIMENT. apexearth 2026-08-20: "When players do one versus
// one games, they often don't even reach the tier two stage. I think you
// should do some experiments where you dedicate yourself to a very strong
// land army and just try to finish the game in tier one. Obviously, if the
// enemy starts to attack you with tier two, you have to upgrade" -- and it is
// "a bit different on really large maps, which are normally not played as a
// one v one", so the mode holds only in a duel on a 1v1-sized map. Off by
// default; arm an A/B with --modoption apex_t1_commit=1.
bool gEnemyT2Seen = false;
float gT1IncPeak = 0.f;
int gT1IncPeakAt = 0;
bool gT1Plateaued = false;

void NoteEnemyDefSeen(CCircuitDef@ edef)
{
	if (gEnemyT2Seen || (edef is null))
		return;
	// A mobile combat unit above T1 cost is the release: enemy defs only
	// reach script on their death, so this is late but certain. 450 sits
	// above every T1 land unit (Zeus 320, Warrior 300, Janus 290) and below
	// the T2 assault class. NOT the commander: it is 2700 metal, mobile, and
	// present from frame zero -- with the being-hit trigger it released the
	// commit at first commander skirmish in every game (measured 9.2m,
	// "confirmed (corcom)"), which is exactly the aggression fade apexearth
	// watched.
	if (edef.IsMobile() && !edef.IsRoleAny(Unit::Role::COMM.mask)
		&& (edef.costM >= ai.GetTunable("apex_t1_release_cost", TUNE_T1_RELEASE_COST)))
	{
		gEnemyT2Seen = true;
		AiLog(T() + "apex: enemy T2-class unit confirmed ("
			+ edef.GetName() + ") -- T1 commit released");
	}
}

bool T1Commit()
{
	// Default ON since 2026-08-20: paired same-seed A/Bs on Altair (trade
	// 0.31->0.52) and Comet Catcher (0.43->0.76, produced 1.01->1.92,
	// 1W2L3D -> 3W1L2D) both favoured the commit. Duel+small-map+no-enemy-T2
	// scoping below is what makes the default safe.
	if (ai.GetTunable("apex_t1_commit", TUNE_T1_COMMIT) <= 0.f)
		return false;
	if (gEnemyT2Seen || gT1Plateaued || !Persona::Duel())
		return false;   // all three latch: a converted commit never re-arms
	// Map area in map units (elmos/512 per side). Comet Catcher is 192,
	// Red Comet 96; Prismatic (256) and up are not 1v1-shaped maps.
	const float area = (float(AiTerrainWidth()) / 512.f)
			* (float(AiTerrainHeight()) / 512.f);
	if (area > ai.GetTunable("apex_t1_commit_area", TUNE_T1_COMMIT_AREA))
		return false;
	// An economy this size did not end the game at T1; the premise expired.
	if (aiEconomyMgr.metal.income
		>= ai.GetTunable("apex_t1_commit_income", TUNE_T1_COMMIT_INCOME))
	{
		return false;
	}
	// THE PLATEAU RELEASE. The income bar above is unreachable from inside
	// the commit on most maps (T1-only economies top out at ~25-40), so an
	// unfinished all-in sat at T1 forever -- apexearth 2026-08-20: "We used
	// to always be scaling our economy. Now we stop and thats really what
	// kills us." When T1 income stops GROWING, T1 scaling is exhausted and
	// the commit converts: tempo while the curve climbs, tech the moment it
	// flattens. No clock -- the trigger is the economy's own derivative.
	{
		const float inc = aiEconomyMgr.metal.income;
		if (inc > gT1IncPeak) {
			gT1IncPeak = inc;
			gT1IncPeakAt = ai.frame;
		}
		const int flat = int(ai.GetTunable("apex_t1_plateau_secs", TUNE_T1_PLATEAU_SECS)) * SECOND;
		if ((gT1IncPeakAt > 0) && (ai.frame - gT1IncPeakAt > flat)
			&& (inc < gT1IncPeak * ai.GetTunable("apex_t1_plateau_grow", TUNE_T1_PLATEAU_GROW)))
		{
			if (!gT1Plateaued) {
				gT1Plateaued = true;
				AiLog(T() + "apex: T1 income plateaued at "
					+ formatFloat(gT1IncPeak, "", 0, 1)
					+ " -- commit converts to tech");
			}
			return false;
		}
	}
	return true;
}

bool MayPursueT2()
{
	if (T1Commit())
		return false;
	if (!T2ArmyReady())
		return false;
	// SOLO IS ITS OWN DECISION, NOT A ROLE: a duel techs when its army and
	// economy are ready, full stop -- the lead/follower split below is team
	// coordination and IsDesignatedLead is now false solo by design.
	if (!TeamPlay())
		return true;
	return IsDesignatedLead() || FollowerEconomyReady();
}

// Am I the ACTUAL designated lead? Distinct from IsTechLead(), which is true for
// team 0 from frame 0 via the fallback. Role behaviour -- suppressing our army,
// being the sling target, skipping defence -- must key on this, or team 0 idles
// its army from the opening and the whole team feeds it before anyone has
// earned the role.
bool IsDesignatedLead()
{
	// Solo, LeadIsDesignated() is unreachable (it early-returns false without
	// THE ROLE IS TEAM-ONLY. This returned true solo (2026-08-14, to route a
	// duel through the rush path's safety checks) and every behavioural
	// consumer then treated a solo player as a rush lead: 0.35x defence,
	// eating its own T1 lab, the mex hold. apexearth 2026-08-20: "There
	// should be no technical lead in a one versus one game." Solo tech
	// timing now has its own branch in MayPursueT2, and the safety checks
	// live where they always did (RushReady).
	if (!TeamPlay())
		return false;
	return LeadIsDesignated() && IsTechLead();
}

// Minimum METAL income before committing to T2 as lead. The energy gates below
// cover whether we can power a plant, not whether the lead can feed itself
// while the whole team pools behind it.
const float RUSH_MIN_METAL = 14.f;

bool RushReady()
{
	if (T1Commit())
		return false;
	// In a 1v1 the player IS the lead, so this branch is the only gate on
	// committing to T2. Metal side of the pair (apex_t2_energy is the other).
	if (aiEconomyMgr.metal.income < Policy::T2Metal())
		return false;
	// RushBuildPower idles the factory's own army line and AiIsSwitchAllowed
	// waives the normal army-value requirement for this branch, so committing
	// here means fielding nothing new while the plant goes up. Pooled teams
	// absorb that on a teammate's front; alone there is no one else on the
	// board, so the same commit is fielding nothing while the ENTIRE board is
	// undefended. LosingGround/BaseContested are the signals defenceline.as
	// already uses for this exact question ("is now safe to stop defending
	// and commit"); no team-size branch, since the risk is the same shape in
	// both cases and pooling only changes how often it is covered by someone
	// else.
	// The safety veto blocks tech exactly where tech is the way out: on a
	// choke map we read losing-ground/contested near-permanently, and the H9
	// arm (energy gate off) proved teching through it anyway is what finally
	// moved Altair (kill/loss 0.31 -> 0.61, first 4-win arm). Tunable so the
	// open-map caution stays available.
	// ...except for the eco role: it sits in the back with the team covering
	// it, and the veto reads near-permanently on a choke map -- measured
	// +100 seed-33, the designated anchor teched at 17.7m while an unvetoed
	// follower managed 6.7m. Teching through pressure is the role's job.
	if ((ai.GetTunable("apex_t2_safety", TUNE_T2_SAFETY) > 0.f)
		&& !IsEcoLead()
		&& (Military::LosingGround() || Military::BaseContested()))
		return false;
	// No clock. Real energy, or a reactor grid already rising.
	// The eco role runs its own bar (default 600, the same energy a
	// follower techs at): the T2 lab IS its economy engine, and the lead
	// bar held it at T1 until minute 15 (+100 seed-33, eInc=60/1200 in the
	// rush log) while an unvetoed follower teched at 6.
	if (IsEcoLead())
		return aiEconomyMgr.energy.income > Role::T2EnergyBar();
	return (aiEconomyMgr.energy.income
			> Policy::T2Energy())
		|| (Builder::HaveReactor()
			&& (aiEconomyMgr.energy.income
				> Policy::T2EnergyReactor()));
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
