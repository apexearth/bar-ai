#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "economy.as"


namespace Factory {

// Team tech coordination. Measured in a 4v4: stock has none -- each instance
// decides independently, so 0 of 4 teched on the losing side and 2 of 4 on the
// winner, essentially at random. Humans designate one player to tech and share
// advanced constructors out; everyone else follows once eco supports it.
bool gHaveT2 = false;   // set once we own an advanced factory
// The real trigger is energy, not metal: take the nearby mexes, reach roughly
// 500 energy/sec, then commit to T2. That lands around 5 minutes, and T2 should
// exist before 10. Gating on metal income 12 held the rusher on T1 until minute
// 12 and the plant only finished at 20 -- later than stock reached it unaided.
// Raised 150 -> 400, and the floor with it. 150 was far under this comment's own
// stated design of "roughly 500 energy/sec": it let the rusher commit to an
// advanced plant on a grid that could not run it, and the plant then crawled.
// The rusher is the one player the whole team is funding, so it is the last one
// that should be teching on thin energy -- and it should keep scaling energy
// afterwards, which is what the raised economy.energy.factor is for.
//
// This DELAYS the rush at today's energy curve: measured ~130 e/s at 5 min and
// ~290 at 8, so 400 is not cleared until roughly 8-9 min against 5.5 today. The
// bet is that the factor change pulls that curve up to meet it. If first-T2
// slips badly, the factor is too low -- raise it before lowering these.
const float RUSH_ENERGY_TARGET = 400.f;
const float RUSH_ENERGY_FLOOR  = 240.f;      // same 0.6 ratio to target as before
const int   RUSH_LATEST        = 5 * MINUTE; // T2 should exist before 10 min

// The whole team pools metal behind the rusher, so it must not be the poorest
// player on it -- feeding a starved economy just moves the starvation around.
// Observed live: on a map where some starts have a single mex, the AI's own
// GetLeadTeamId() picked a player on 4 metal/sec and the whole team pooled
// behind it. Merely vetoing a poor lead is not enough -- that just cancels the
// rush and nobody else takes it. The richest ally has to be picked outright.
//
// The election runs here, over the in-process blackboard. It used to run in
// synced Lua (dev_team_income.lua) because a per-instance election elected two
// leads in 1 of 533 archived matches -- not because the instances disagreed on
// the facts, but because they sampled them at different instants. Synced Lua
// cannot ship to a hosted multiplayer game, though: it has to exist on every
// client. Every AI the host adds shares one process, so the blackboard reaches
// exactly the same set of instances the gadget did, and nothing else.
//
// The property that fixed the double election is kept: ONE writer. The lowest
// team id in the ally roster elects and publishes; everyone else only reads.
//
// The rule itself is now commitment, not income: the lead is whoever is
// building an advanced plant, and if two are building, whichever plant is
// closest to finished. Nanoframes count -- ai.GetDefBuildProgress returns
// fractional progress, which is exactly the tie-break.
const string TV_ADV  = "adv";    // this team's best advanced-plant progress
const string TV_LEAD = "lead";   // the elector's answer, read by everyone
// Metal income while this team could commit to a plant, 0 when it could not.
// Electing on commitment ALONE cannot stop a stampede: nobody is designated until
// somebody has already started, so the gate stands open and every team that comes
// good in the same window starts its own plant. Observed live, twice: three
// commanders teching within 40 seconds of each other at the 5 minute mark.
const string TV_READY = "ready";

// Total builders the tech lead may hold while rushing. Enough to finish an
// advanced plant fast; beyond that each constructor is metal that buys nothing
// while the whole team is funding this one player.
const uint  RUSH_CON_CAP = 6;

// Minimum gap between two constructor orders during the rush.
//
// RUSH_CON_CAP reads GetWorkerCount(), which counts FINISHED builders only, and
// Enqueue does not dedup -- so without spacing the cap can be overshot by
// however many orders fit in one constructor's build time. An interval is used
// rather than an in-flight counter because an aborted recruit would leak a
// counter permanently and silently stop constructor production.
const int   RUSH_CON_SPACING = 12 * SECOND;
int gNextConOrder = 0;

// Army catch-up production when behind. Short: this is the thing we want a
// lot of, and the units are cheap.
const int   ARMY_PUSH_SPACING = 3 * SECOND;
int gNextArmyPush = 0;
int gNextArmyLog = 0;

// Every third catch-up push buys fodder instead of the assault mainstay.
//
// Measured over eight 4v4 infologs: apex's standing cheap-unit value (mobile,
// armed, under 120 metal) runs 3-6x below stock BARb's from minute 14 on -- 851
// against 3,727 at eighteen minutes -- while its total army value is comparable.
// The factory weights are not the cause; they still carry 10-17% cheap. This
// branch is: it overrides the configured mix every 3 seconds while behind, and
// it only ever asks for ASSAULT.
//
// One in three REQUESTS is about 7% of the metal, because a Tick is 21 and a
// Hammer 130. The stream of bodies is what is wanted, not the spend.
const int   FODDER_EVERY = 3;
int gArmyPushCount = 0;

int gRushLead = -1;   // last lead this instance saw published
bool gT1Reclaimed = false;   // one-shot: we fed our T1 lab into the plant

// False once the pooling strategy has been given up on (Military::RUSH_GIVEUP).
// The rush branch below returns null rather than producing army, so a lead that
// never reaches T2 would otherwise sit out the entire game building nothing.
bool RushWindowOpen()
{
	return ai.frame <= Military::RUSH_GIVEUP;
}

// Re-read at most once a second. Un-cached, this ran a string concatenation and
// an engine callback on EVERY IsTechLead() -- 15 call sites, several on hot
// paths -- including from inside Builder::AiUnitAdded, which ai.GiveUnits
// invokes re-entrantly while it is transferring a unit. A second is far shorter
// than any takeover deadline, so the role still moves promptly.
int gLeadCheckedAt = -1000;

// Lowest team id in the ally roster. Every instance computes the same answer
// from the same roster with no signalling, so all of them know whose blackboard
// slot carries the election result.
int ElectorTeamId()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return ai.teamId;
	int low = int(mates[0]);
	for (uint i = 1; i < mates.length(); ++i) {
		if (int(mates[i]) < low)
			low = int(mates[i]);
	}
	return low;
}

// Only the elector runs this, and it publishes under its OWN slot.
void RunElection()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;

	const int held = int(ai.ReadTeamValue(ai.teamId, TV_LEAD, -1.f));
	// Past the give-up frame the title stops moving. Sharing has stopped by then
	// anyway; the team keeps its tech lead rather than handing the role around.
	if ((held >= 0) && (ai.frame > Military::RUSH_GIVEUP))
		return;
	// Keep the incumbent while it still holds a plant or a nanoframe. Reopening
	// only when it has genuinely lost one is what stops the role flapping
	// between two teams whose progress is neck and neck.
	if ((held >= 0) && (ai.ReadTeamValue(held, TV_ADV, -1.f) > 0.f))
		return;
	// Keep a provisional pick that has not spent anything yet but is still able
	// to. Without this the title flaps between ready teams every tick and each
	// starts a plant on its turn -- the same stampede, slower.
	if ((held >= 0) && (ai.ReadTeamValue(held, TV_READY, 0.f) > 0.f))
		return;

	int best = -1;
	float bestProgress = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		const float p = ai.ReadTeamValue(t, TV_ADV, -1.f);
		if (p <= 0.f)
			continue;   // has not committed to an advanced plant
		if ((p > bestProgress) || ((p == bestProgress) && (t < best))) {
			bestProgress = p;
			best = t;
		}
	}
	// ISOLATION TEST: readiness fallback disabled. Restricting who may tech cost
	// 30% of metal production in an 8-game measurement, so this establishes
	// whether the stampede gate is what did it.
	if (false) {
		float bestReady = 0.f;
		for (uint i = 0; i < mates.length(); ++i) {
			const int t = int(mates[i]);
			const float r = ai.ReadTeamValue(t, TV_READY, 0.f);
			if (r <= 0.f)
				continue;
			if ((r > bestReady) || ((r == bestReady) && (best >= 0) && (t < best))) {
				bestReady = r;
				best = t;
			}
		}
	}
	ai.PublishTeamValue(TV_LEAD, float(best));
}

// Driven from AiUpdate, so every instance publishes on a fixed cadence.
// Publishing as a side effect of RushLeadTeamId() instead would make a team's
// visibility depend on which code paths happened to ask for the lead that tick,
// and a team that went quiet would look like it had lost its plant.
void UpdateTeamCoord()
{
	ai.PublishTeamValue(TV_ADV, OwnAdvProgress());
	ai.PublishTeamValue(TV_READY, RushReady() ? aiEconomyMgr.metal.income : 0.f);
	if (ElectorTeamId() == ai.teamId)
		RunElection();
}

int RushLeadTeamId()
{
	if (ai.frame < gLeadCheckedAt + 1 * SECOND)
		return (gRushLead >= 0) ? gRushLead : ai.GetLeadTeamId();
	gLeadCheckedAt = ai.frame;

	// Read the ELECTOR's slot, not our own, and never anything keyed on
	// ai.allyTeamId: that read 0 for every instance in the shipped DLL, which
	// had ally 1 pooling behind ally 0's lead.
	const int lead = int(ai.ReadTeamValue(ElectorTeamId(), TV_LEAD, -1.f));
	// Nobody has committed yet. Defer to the engine's own pick, and to the last
	// known lead if we ever had one, rather than reporting "nobody".
	if (lead < 0)
		return (gRushLead >= 0) ? gRushLead : ai.GetLeadTeamId();

	// Not latched here: the elector can hand the role over if the lead loses its
	// plant before the give-up frame.
	if (lead != gRushLead) {
		AiLog(T() + "apex: tech lead "
			+ ((gRushLead < 0) ? "= team " + lead
			                   : "CHANGED team " + gRushLead + " -> " + lead));
		gRushLead = lead;
		// gT1Reclaimed is deliberately NOT cleared: the reclaim stays one-shot
		// per instance.
	}
	return gRushLead;
}

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
	const string side = ai.GetSideName();
	CCircuitDef@ moho = ai.GetCircuitDef((side == "cortex") ? cormoho
	                                   : ((side == "legion") ? legmoho : armmoho));
	gHaveT2Mex = (moho !is null) && (moho.count > 0);
	return gHaveT2Mex;
}

bool IsTechLead()
{
	return ai.teamId == RushLeadTeamId();
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
	return !LeadIsDesignated() || IsTechLead();
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
	if (aiEconomyMgr.metal.income < RUSH_MIN_METAL)
		return false;
	return (aiEconomyMgr.energy.income > RUSH_ENERGY_TARGET)
		|| ((ai.frame > RUSH_LATEST) && (aiEconomyMgr.energy.income > RUSH_ENERGY_FLOOR));
}

const float FOLLOWER_TECH_INCOME = 28.f;   // followers wait for a running economy
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
const float FOLLOWER_TECH_ENERGY = 800.f;


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

string armlab  ("armlab");
string armalab ("armalab");
string armvp   ("armvp");
string armavp  ("armavp");
string armsy   ("armsy");
string armasy  ("armasy");
string armap   ("armap");
string armaap  ("armaap");
string armshltx("armshltx");

string corlab  ("corlab");
string coralab ("coralab");
string corvp   ("corvp");
string coravp  ("coravp");
string corsy   ("corsy");
string corasy  ("corasy");
string corap   ("corap");
string coraap  ("coraap");
string corgant ("corgant");

string leglab  ("leglab");
string legalab ("legalab");
string legvp   ("legvp");
string legavp  ("legavp");
string legsy   ("legsy");
string legap   ("legap");
string legaap  ("legaap");
string leggant ("leggant");

int switchInterval = MakeSwitchInterval();

// The cheapest body THIS factory can actually make. Scout first, then raider:
// armlab answers armflea, corlab has no scout unit and falls through to corak,
// leglab answers leggob. Military::IsFodder is the gate, so a factory whose
// cheapest option is not actually cheap returns null and the caller buys the
// assault mainstay as before.
CCircuitDef@ Fodder(const CCircuitDef@ facDef)
{
	CCircuitDef@ d = aiFactoryMgr.GetRoleDef(facDef, Unit::Role::SCOUT.type);
	if (Military::IsFodder(d))
		return d;
	@d = aiFactoryMgr.GetRoleDef(facDef, Unit::Role::RAIDER.type);
	if (Military::IsFodder(d))
		return d;
	return null;
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	// Safe to sit first: this answers only for the advanced air plant, so the
	// ground line's branches below are untouched.
	IUnitTask@ air = Air::MakeFactoryTask(unit);
	if (air !is null)
		return air;

	// aiMilitaryMgr.quota.attack only caps how many units get SENT to attack; it
	// does not stop the factory building them. Measured: the rusher's standing
	// army grew 240 -> 3400 metal while its bank sat at 1 metal, so every sling
	// its allies sent was converted straight into T1 units instead of into the
	// plant. Idle the line outright once the rush window is open, until the
	// advanced plant exists.
	// Do NOT simply idle here. Measured on Comet Catcher: the lead sat with
	// rushReady since 5.0 min and its bank climbing to 2261 unspent metal, and
	// still placed no plant until 13.9 min. The blocker is ENERGY, not metal --
	// EconomyManager checks (engyFactor < energyPower) and returns before it ever
	// consults IsSwitchAllowed, and unlike the metal check that branch is not
	// bypassed by isSwitchTime. So banked metal is simply wasted metal here.
	//
	// Turn it into build power instead: more constructors means solars and
	// converters go up faster, which is the thing the gate is actually waiting
	// on. Those constructors are also exactly what we need afterwards to upgrade
	// mexes and to hand to allies.
	// CAPPED. This had no limit at all: it recruited a constructor on every
	// factory decision from RushReady until the advanced plant existed, which on
	// an 8v8 is the entire rush window. Observed live -- the player going for T2
	// sitting on 15-20 T1 constructors. That is thousands of metal in build power
	// that cannot be spent, buying nothing, at exactly the moment the team has
	// pooled everything behind this player.
	//
	// A handful is enough to finish a plant quickly; past that each one is pure
	// waste. GetWorkerCount() is the engine's own count of our builders, so this
	// counts what we actually hold rather than what we have ever ordered.
	if (MayPursueT2() && !gHaveT2 && RushReady() && !IsSmallTeam()
		&& RushWindowOpen())
	{
		// Cap AND spacing: the cap alone cannot hold, because GetWorkerCount()
		// only sees finished builders (see RUSH_CON_SPACING above).
		if ((aiBuilderMgr.GetWorkerCount() < RUSH_CON_CAP)
			&& (ai.frame >= gNextConOrder))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextConOrder = ai.frame + RUSH_CON_SPACING;
					return rec;
				}
			}
		}
		return null;   // never fall through to army production during the rush
	}

	// The tech lead buys roughly four or five minutes of T2 before the enemy
	// catches up, and spending that on one advanced tank is close to wasting it.
	// Spent on constructors it compounds instead: ours upgrades our own mexes,
	// and every one handed to an ally lets them upgrade theirs -- T2 mexes are
	// four times the metal, across the whole team, for the rest of the game.
	// So build nothing but build power until every teammate has one.
	// Both overrides are for BIG teams only. On a four-player team the rusher
	// producing no army at all is a quarter of the team's army missing -- the
	// same arithmetic that rules out an air player on a 4v4. Measured across 5
	// maps: standing army 17.8k against stock's 25.4k and real K/D 0.70 against
	// 1.24, while the tech lead itself was up 8 minutes. A tech lead that cannot
	// hold the ground it techs on does not convert. Small teams keep stock
	// production and lean on quota.attack = RUSH_SKIP_T1_SMALL to stay eco-first.
	// Small teams were excluded after enabling this at NOW priority lost 3-13 with
	// t2Mex falling 3.2 -> 1.8. That test conflated two separate things: sharing
	// constructors at all, versus MONOPOLISING the factory line to do it. NOW
	// means the lead builds nothing else, which a four-player team cannot afford.
	// Observed live with sharing off: "we went t2 but didn't share any cons" and
	// then all four built their own advanced plants late -- the expensive outcome
	// that sharing exists to prevent. So share everywhere, but only pre-empt the
	// line on a big team.
	// Two reasons to build an advanced constructor, and the second was missing.
	// The lead builds them to SHARE, which is the design. But anyone who reaches
	// T2 and holds no advanced con needs one for themselves -- otherwise a
	// follower that techs while the designated lead does not ends up with a T2
	// plant and nothing to upgrade mexes with. Observed in an 8v8: a player
	// finished its advanced lab at 10:01 and immediately built Banishers, mobile
	// radars and a Tiger, while the team upgraded ZERO mexes in 45 minutes.
	// Instrumented because four mex upgrades across eight players (stock: 96) and
	// zero gifts means this branch is barely firing, and guessing which of five
	// conditions fails has already wasted a run. Log every input, once per 30s.
	if (ai.frame >= gNextConLog) {
		gNextConLog = ai.frame + 30 * SECOND;
		CCircuitDef@ probe = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		AiLog(T() + "conbranch fac=" + unit.circuitDef.GetName()
			+ " haveT2=" + (gHaveT2 ? "1" : "0")
			+ " lead=" + (IsTechLead() ? "1" : "0")
			+ " owes=" + (Builder::OwesAdvCons() ? "1" : "0")
			+ " haveCon=" + (Builder::gHaveAdvCon ? "1" : "0")
			+ " roleDef=" + ((probe is null) ? "NULL" : probe.GetName()));
	}
	// Behind on the field, with T2 and a mex upgraded: pour income into the cheap
	// mainstay rather than anything else. apexearth, watching a game lost from a
	// winning tech position: "if we just built T1 labs and spammed out a lot of
	// those Thug units, that would be enough to turn the tide, and it would be
	// way cheaper". GetRoleDef(ASSAULT) returns whatever THIS factory can make --
	// Thug from a bot lab, Brute from a vehicle plant -- so it never asks for a
	// unit the factory cannot build.
	//
	// Spaced, for the same reason RUSH_CON_SPACING exists: Enqueue does not dedup
	// and the cap it would otherwise respect only counts finished units.
	// T1 factories only. Asking the ADVANCED plant for its assault unit returned
	// Reaper and Bulldog -- exactly the expensive T2 units this is meant to
	// avoid buying while behind.
	const bool isT1Fac =
		((Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) == 0);
	if (isT1Fac && gHaveT2 && HaveT2Mex() && Military::LosingGround()
		&& (ai.frame >= gNextArmyPush))
	{
		CCircuitDef@ want = null;
		if ((++gArmyPushCount % FODDER_EVERY) == 0)
			@want = Fodder(unit.circuitDef);
		if (want is null)
			@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ASSAULT.type);
		if (want !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					want, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextArmyPush = ai.frame + ARMY_PUSH_SPACING;
				if (ai.frame >= gNextArmyLog) {
					gNextArmyLog = ai.frame + 30 * SECOND;
					AiLog(T() + "apex: behind on the field, massing " + want.GetName()
						+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
						+ " enemyArmy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
				}
				return rec;
			}
		}
	}

	if (gHaveT2 && ((IsDesignatedLead() && Builder::OwesAdvCons()) || !Builder::gHaveAdvCon)) {
		// BUILDER, not BUILDER2. builderT2 is registered as a SUBROLE of builder
		// (AiAddRole("builderT2", BUILDER.type)) and the factory role map is
		// indexed by BASE roles only -- FactoryManager.cpp:1057 looks up
		// ROLE_TYPE(BUILDER) itself. Asking for BUILDER2 returned NULL every time,
		// so this branch silently fell through to normal production: a plant would
		// finish and immediately build Banishers and radars while the team upgraded
		// no mexes at all. For an advanced plant the base builder IS the advanced
		// constructor -- coravp's only builder is coracv.
		CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (con !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER,
					IsSmallTeam() ? Task::Priority::NORMAL : Task::Priority::NOW,
					con, unit.GetPos(ai.frame), 0.f));
			if (rec !is null)
				return rec;
		}
	}
	return aiFactoryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

// The lead's own T1 lab, kept so it can be fed back into the T2 plant.
// gT1Reclaimed is declared with the other rush state above, because
// RushLeadTeamId() clears it on a handover and AngelScript resolves globals in
// declaration order.
CCircuitUnit@ gT1FacUnit = null;

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0)
		gHaveT2 = true;
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T3) != 0)
		gHaveT3 = true;
	if ((usage == Unit::UseAs::FACTORY)
		&& ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) == 0))
	{
		@gT1FacUnit = unit;
		AiLog(T() + "apex: T1 lab on field: " + unit.circuitDef.GetName());
	}
//	if (!factories.empty() || (this->circuit->GetBuilderManager()->GetWorkerCount() > 2)) return;
	if (usage != Unit::UseAs::FACTORY)
		return;

	const CCircuitDef@ facDef = unit.circuitDef;
	if (userData[facDef.id].attr & Attr::T3 != 0) {
		// if (ai.teamId != ai.GetLeadTeamId()) then this change affects only target selection,
		// while threatmap still counts "ignored" here units.
// 		AiLog("ignore newly created armpw, corak, armflea, armfav, corfav");
		array<string> spam = {"armpw", "corak", "armflea", "armfav", "corfav", "leggob", "legscout"};
		for (uint i = 0; i < spam.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(spam[i]);
			if (cdef !is null)
				cdef.SetIgnore(true);
		}
	}

	if (Air::SuppressesOpener(facDef))
		return;

	const array<Opener::SO>@ opener = Opener::GetOpener(facDef);
	if (opener is null)
		return;

	const AIFloat3 pos = unit.GetPos(ai.frame);
	for (uint i = 0, icount = opener.length(); i < icount; ++i) {
		CCircuitDef@ buildDef = aiFactoryMgr.GetRoleDef(facDef, opener[i].role);
		if ((buildDef is null) || !buildDef.IsAvailable(ai.frame))
			continue;

		Task::Priority priority;
		Task::RecruitType recruit;
		if (opener[i].role == Unit::Role::BUILDER.type) {
			priority = Task::Priority::NORMAL;
			recruit  = Task::RecruitType::BUILDPOWER;
		} else {
			priority = Task::Priority::HIGH;
			recruit  = Task::RecruitType::FIREPOWER;
		}
		for (uint j = 0, jcount = opener[i].count; j < jcount; ++j)
			aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, buildDef, pos, 64.f));
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// CCircuitUnit is registered NOCOUNT, so a handle is not nulled when the
	// engine destroys the unit and `is null` stays false on freed memory.
	// Leaving this unset crashed UpdateRushReclaim's Enqueue (0xc0000005).
	if (gT1FacUnit is unit)
		@gT1FacUnit = null;
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * New factory switch condition; switch event is also based on eco + caretakers.
 */
// Every AiLog line was unanchored in time, so a log could show the rush firing
// while saying nothing about *when* -- which is the only thing that matters for a
// deadline of "T2 before 10 minutes". Stamp everything.
// Log prefix: game time AND team id.
//
// Every AI instance on the map writes to one infolog behind the same
// "Skirmish AI <BARbarIAn Apex-apex>:" prefix, so without the team id four
// players' lines are indistinguishable. That made the questions this strategy
// actually raises -- who is the lead, who is slinging, who teched first --
// unanswerable from a log, and forced them to be guessed at instead. Prefix
// every line and they become a per-team timeline. tools/trace_flow.py parses it.
string T()
{
	return "[" + formatFloat(float(ai.frame) / float(MINUTE), "", 0, 1) + "m t"
		+ ai.teamId + "] ";
}

// Periodic dump of every input the rush decision reads, so a slow tech can be
// attributed to a specific gate rather than guessed at. One line per 30s.
// The T1 lab is ~600-900 metal standing idle -- the rush already stops it
// producing, so it is pure banked metal doing nothing. Feed it into the plant it
// is being replaced by; a T1 lab can be rebuilt later once T2 economy is up.
void UpdateRushReclaim()
{
	if (gT1Reclaimed || gHaveT2 || !IsTechLead() || !RushWindowOpen())
		return;
	if (gT1FacUnit is null)
		return;
	// The advanced plant must EXIST, not merely have been chosen.
	// AiGetFactoryToBuild returning it is a preference; placement came minutes
	// later. Eating the T1 lab in that gap leaves the lead with no factory, and
	// CircuitAI answers by building a fresh T1 one -- observed live: vehicle lab
	// reclaimed, bot lab built, T2 plant only minutes after that.
	// CCircuitDef::count is incremented in RegisterTeamUnit, which runs for the
	// nanoframe, so this is true as soon as construction actually starts.
	CCircuitDef@ adv = AdvCounterpart();
	if ((adv is null) || (adv.count <= 0))
		return;
	gT1Reclaimed = true;
	AiLog(T() + "apex: reclaiming T1 lab " + gT1FacUnit.circuitDef.GetName()
		+ " into the advanced plant");
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, gT1FacUnit));
}

int gNextRushLog = 0;
void LogRushState()
{
	if (ai.frame < gNextRushLog)
		return;
	gNextRushLog = ai.frame + 30 * SECOND;

	const bool lead = IsTechLead();
	if (!lead && gHaveT2)
		return;   // followers that already teched are not interesting

	const bool rushReady = RushReady();
	CCircuitDef@ adv = AdvCounterpart();
	const float advCost = (adv is null) ? 0.f : adv.costM;

	AiLog(T() + "rush team=" + ai.teamId + (lead ? " LEAD" : " follower")
		+ " haveT2=" + (gHaveT2 ? "1" : "0")
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
		+ "/" + formatFloat(RUSH_ENERGY_TARGET, "", 0, 0)
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(advCost * 0.5f, "", 0, 0)
		+ " rushReady=" + (rushReady ? "1" : "0")
		+ " facs=" + aiFactoryMgr.GetFactoryCount()
		+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0));
}

int gNextSwitchProbe = 0;
int gNextConLog = 0;
const int T3_MAX_PROBES = 4;   // bounded: enough to place one gantry, never a pile
int gT3Probes = 0;
int gNextT3Probe = 0;

bool AiIsSwitchTime(int lastSwitchFrame)
{
	// THE bug behind late teching: MakeSwitchInterval() is AiRandom(550,900)
	// seconds, so the AI only *considers* a factory change every 9-15 minutes.
	// The rush override was correct but never got asked -- hence T2 at 22.9m
	// instead of before 10. While the designated rusher still lacks T2, let it
	// reconsider every tick.
	// Returning true on EVERY call was a real bug, not just noise. In
	// EconomyManager the same flag disables the metal gate:
	//   if ((metalFactor < factoryPower) && !isSwitchTime && ...) return nullptr;
	// so a permanently-true isSwitchTime means the AI starts another factory
	// whenever it holds any metal at all. Observed live: one AI with THREE T1
	// bot labs. The intent was only to stop the stock 9-15 minute reconsider
	// interval from making the rush unreachable, which a short probe interval
	// achieves without leaving the gate open.
	// MayPursueT2, not IsTechLead. This probe is what makes teching reachable at
	// all -- the stock interval is AiRandom(550,900) seconds -- and gating it on
	// IsTechLead handed team 0 a probe every 10s while everyone else waited 9-15
	// minutes. Blue therefore built the first advanced plant in every game
	// regardless of income, because nobody else was ever asked. RushReady still
	// demands >= 14 metal/s before anything is actually placed.
	if (MayPursueT2() && !gHaveT2) {
		if (ai.frame < gNextSwitchProbe)
			return false;
		gNextSwitchProbe = ai.frame + 10 * SECOND;
		return true;
	}
	// T3 probe REMOVED after measurement, not after theorising. Bounded probing
	// worked mechanically -- 3645 metal of T3 fielded, the first time this AI has
	// ever reached T3, against stock's 0 -- and lost 4-12 with the CI excluding
	// 50%. Metal fell 136k -> 88k and army 25k -> 13k: a gantry plus its units
	// costs more than the game gives back at these income levels, and the match
	// is decided long before the investment pays.
	//
	// The doctrine is not wrong; the economy is not yet big enough to afford its
	// win condition. T3 belongs behind an economy that can carry it, which means
	// the eco half has to come good FIRST. Re-enable this only alongside a
	// measured economy that outpaces stock's ~136k.
	// Everyone should at least be trying for T2 by ~20 minutes.
	if (!gHaveT2 && (ai.frame > 20 * MINUTE))
		return true;
	if (Air::WantsSwitchProbe())
		return true;
	if (lastSwitchFrame + switchInterval <= ai.frame) {
		switchInterval = MakeSwitchInterval();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	// First, ahead of the follower gates below. The advanced air plant carries the
	// T2 attribute, so the FOLLOWER_TECH_ENERGY gate would refuse it on any grid
	// under 800 energy/sec -- and the air assassin is by construction not the
	// designated tech lead, so that gate applies to it. Place it and pour income
	// in, same as the rush plant.
	if (Air::WantsFactory(facDef)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// "Defend, hold, tech up to turn the tide" -- the holding half was
	// implemented and the teching half was not, so the AI sat on banked metal
	// instead of spending it. Holding is exactly when tech should be bought:
	// the army is not being reinforced, so the stock requirement of
	// armyCost > 1.2 * facCost * facCount can never be met while turtling.
	// Followers hold on T1 until the economy can carry a second tech base;
	// the lead keeps stock behaviour and techs first.
	// Measured 4v4: this gate at income 45 left our side with 1 of 4 teched at
	// 25.4m while stock got 3 of 4 by 21m -- it was suppressing tech outright
	// rather than sequencing it. Followers now only wait until the rush window
	// has passed OR the economy is genuinely running, whichever comes first.
	// Followers were deadlocked: the gate keyed off their own metal income, but
	// slinging is what suppresses that income -- so donating blocked the tech it
	// was paying for. Release on elapsed time instead, and only hold them during
	// the pooling window.
	// LeadIsDesignated() is load-bearing, not belt-and-braces. The lead is now
	// "whoever is building an advanced plant", so holding every non-lead back
	// until FOLLOWER_TECH_FRAME deadlocks: nobody may start a plant, so nobody
	// becomes lead, so nobody may start a plant. Measured -- the first election
	// landed at 10.5 min in two runs, the frame the gate opens, against a 5.7 min
	// baseline. Before anyone has committed the slot is open and whoever is ready
	// races for it; once someone holds it, the rest are followers again.
	if (LeadIsDesignated() && !IsDesignatedLead()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& (ai.frame < FOLLOWER_TECH_FRAME))
	{
		return false;
	}
	// A follower needs real energy behind the plant, not just metal.
	//
	// This is a single early guard rather than another clause on the no-bank
	// branch below, because a follower has FOUR routes to T2 in this function --
	// the no-bank branch, the turtle branch, and both halves of the stock
	// fallback -- and every one of them grants it on metal alone. Gating one
	// leaves the others open.
	//
	// LeadIsDesignated() is required here for the same reason it is above: gate
	// every non-lead on energy before anyone has been elected and nobody can
	// start a plant, so nobody becomes lead, so nobody can start a plant. The
	// energy bar applies once the team has a lead to pool behind.
	// Bounded to the pooling window, like every other follower gate. Without the
	// frame clause it pre-empted the follower release below FOREVER: that branch
	// asks only for metal income past FOLLOWER_TECH_FRAME and could never be
	// reached by anyone under 800 energy/s. Observed live at 33 minutes -- a
	// wealthy player, metal storage full, no advanced plant and no way to start
	// one. Nothing logged, because the T2GATE line lives in the branch this
	// returns before.
	if (LeadIsDesignated() && !IsDesignatedLead()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& (ai.frame < FOLLOWER_TECH_FRAME)
		&& (aiEconomyMgr.energy.income < FOLLOWER_TECH_ENERGY))
	{
		return false;
	}
	// The designated player is rushing: buy T2 as soon as the metal is on hand,
	// without the stock army-value requirement. It is not meant to be
	// contributing T1 army at all, so that requirement can never be met.
	// Was 0.5 * factory cost banked (~1450 metal). The rusher never holds that
	// much because it spends as the slings arrive, so the plant did not start
	// until 12 min. It does not need the whole cost up front -- construction
	// draws from income, and seven feeders keep paying into it.
	// Measured, 8v8 Glitters: energy cleared the rush bar at 5.0 min and stayed
	// clear, but the bank sat at 1-120 metal for the entire game against a
	// required 1400 (0.5 * plant cost), so this branch never once fired. The
	// requirement was never reachable -- metal income is ~13/s and every point of
	// it is spent as it arrives. Banking is the wrong model anyway: in BAR you
	// place the plant and pour income into the nanoframe. So place it on zero
	// metal and let income, seven slinging allies and assisting builders finish
	// it. isAssistRequired is now true for exactly that reason -- with no bank,
	// build power is the only thing that closes the gap.
	if (MayPursueT2() && !gHaveT2 && RushReady()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0))
	{
		// EconomyManager returns before this on (engyFactor < energyPower) and on
		// the sticky isEnergyRequired, neither of which isSwitchTime bypasses.
		// This line marks the frame we were actually reached on.
		AiLog(T() + "T2GATE reached IsSwitchAllowed"
			+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1));
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	if (Military::gTurtle && (aiEconomyMgr.metal.current > facDef.costM * 0.6f)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = false;
		return true;
	}
	// T3 is this variant's declared win condition and it has NEVER been fielded:
	// zero across every measured game, while stock manages 670 with no T3 logic
	// at all. AiGetFactoryToBuild already asks for the gantry -- the request dies
	// here. The stock gate wants either armyCost > 1.2x cost x facCount or the
	// full cost banked, and a gantry runs several thousand metal, so neither is
	// reachable for an eco variant that deliberately holds a modest army.
	//
	// Same reasoning as the T2 plant: you do not bank for a factory in BAR, you
	// place it and pour income into it. Require a real economy behind it rather
	// than a pile of metal, and turn assist ON so builders actually finish it --
	// with no bank, build power is the only thing that closes the gap.
	if (WantMoreGantries() && ((userData[facDef.id].attr & Attr::T3) != 0)
		&& T3Worthwhile())
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// Followers could never tech. Measured: 4.6k of T2 unit spend against stock's
	// 11-14k, 1.4 mex upgrades against 2.5-2.9, and three of four followers still
	// reading haveT2=0 at eighteen minutes while earning 30-73 metal/s. Releasing
	// the clock changed nothing, which proved the clock was never the blocker --
	// this gate is. It wants armyCost > 1.2x cost x facCount or the full plant
	// cost banked, and a follower holds neither.
	//
	// The lead escapes this via the rush branch above. Give followers the same
	// once the pooling window has closed: place the plant on income rather than
	// banking for it, with assist on so build power finishes it. Pooling behind
	// one player is only worth it if the others follow afterwards.
	// Staggering by team id was tried and LOST 2-14 (CI 71-100%). It did flatten
	// the army curve slightly -- 10.9k vs 17.8k at fourteen minutes, up from 8.9k
	// vs 25.1k -- but pushing the last follower to minute 16 costs more T2
	// economy than the smoother curve is worth. The synchronised transition is a
	// real cost; delaying teching is not the way to pay it.
	// !gHaveT2 was missing here, so a follower that ALREADY owned an advanced
	// plant kept being granted a no-bank switch to build ANOTHER one. Observed
	// live: a player with a T2 vehicle plant went and built a T2 bot lab as well,
	// and all four teched simultaneously late in the game. One advanced plant per
	// follower is the whole point -- the second is metal that should have been
	// army or mex upgrades, spent at the worst possible moment.
	if (!IsDesignatedLead() && !gHaveT2 && (ai.frame >= FOLLOWER_TECH_FRAME)
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& (aiEconomyMgr.metal.income > 18.f))
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	const bool isOK = (aiMilitaryMgr.armyCost > 1.2f * facDef.costM * aiFactoryMgr.GetFactoryCount())
		|| (aiEconomyMgr.metal.current > facDef.costM);
	aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = !isOK;
	return isOK;
}

// The advanced plant has to be one our own constructors can actually build.
// Measured: the rusher opened a BOT lab, whose constructor (corck) can build
// only coralab, while this function forced coravp -- the advanced VEHICLE plant.
// All 33 rush requests in a 14-minute game asked for a factory nothing on the
// field could place, were silently dropped, and T2 never started. The earlier
// "prefer Gollums over Sumos" bias that introduced coravp here was measured on
// games where a vehicle plant happened to be the opening, so it never showed up
// as a failure -- it just quietly disabled the whole rush on bot openings.
array<string> T1_FAC = {armlab, armvp, armsy, armap,
                        corlab, corvp, corsy, corap,
                        leglab, legvp};
array<string> T2_FAC = {armalab, armavp, armasy, armaap,
                        coralab, coravp, corasy, coraap,
                        legalab, legavp};

// Our best progress toward an advanced plant, 0..1, or -1 if we hold none.
// Nanoframes count -- commitment is the question the election asks, and the
// fraction is what separates two teams that have both committed.
//
// Air plants are skipped: the team pools its metal expecting a T2 ground push,
// which an air plant cannot deliver. The previous election excluded air leads
// for the same reason.
//
// Declared here rather than beside the election because T2_FAC is a global, and
// AngelScript needs globals declared before use. Functions are order-free.
float OwnAdvProgress()
{
	float best = -1.f;
	for (uint i = 0; i < T2_FAC.length(); ++i) {
		CCircuitDef@ def = ai.GetCircuitDef(T2_FAC[i]);
		if ((def is null) || IsAirFactory(def))
			continue;
		const float p = ai.GetDefBuildProgress(def);
		if (p > best)
			best = p;
	}
	return best;
}

// Two separate reasons to refuse an air OPENING.
//
// 1. On a small team it is simply a losing choice: "on a 4v4 nobody should go
//    air, to main air on a 4v4 is a recipe for loss -- we'd beat BARb if we just
//    did 4x ground". One of four players contributing no ground army is a
//    quarter of the team missing. On a big team one air player is affordable and
//    can be useful, so only the lead is barred there.
// 2. Air is a bad sling target regardless of team size: the team pools its metal
//    into one player expecting a T2 ground push, and an air opening cannot give
//    them one.
//
// This gates the opening factory only. A later air plant, once the ground game
// is established, is fine and is left alone.
const uint BIG_TEAM = 6;   // same threshold the rush attack quota uses

array<string> AIR_FAC = {armap, armaap, corap, coraap, legap, legaap};

bool IsSmallTeam()
{
	array<Id>@ mates = ai.GetTeamIds();
	return (mates is null) || (mates.length() < BIG_TEAM);
}

bool IsAirFactory(CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string name = def.GetName();
	for (uint i = 0; i < AIR_FAC.length(); ++i) {
		if (AIR_FAC[i] == name)
			return true;
	}
	return false;
}

// At most ONE air opening per ally team on a big team.
//
// Each instance decides its opening alone from the same map data, so on an 8v8
// several would pick air independently. One slot is chosen deterministically
// from the ally roster instead -- every instance computes the same answer at
// frame 0, with no signalling. Highest team id, to avoid landing on the same
// player as the engine's GetLeadTeamId (the early tech lead).
//
// A cap, not a quota: if the slot holder does not want air, the team opens
// none.
int AirSlotTeamId()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return -1;
	int slot = -1;
	for (uint i = 0; i < mates.length(); ++i) {
		if (int(mates[i]) > slot)
			slot = int(mates[i]);
	}
	return slot;
}

// May this instance open with an air factory at all?
bool MayOpenAir()
{
	if (IsSmallTeam())
		return false;             // under BIG_TEAM: nobody opens air
	if (IsDesignatedLead())
		return false;             // the rusher techs on the ground
	return ai.teamId == AirSlotTeamId();
}

// Ground opening for the tech lead when the default picks air. Vehicles over
// bots: the construction vehicle builds the advanced vehicle plant, and its
// heavy assault line (Gollum) pushes where the bot line (Sumo) holds.
CCircuitDef@ GroundOpening()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corvp);
	if (side == "legion")
		return ai.GetCircuitDef(legvp);
	return ai.GetCircuitDef(armvp);
}

// The opening factory, remembered so we can tech into its own advanced version.
CCircuitDef@ gT1Fac = null;

CCircuitDef@ AdvCounterpart()
{
	if (gT1Fac is null)
		return null;
	const string name = gT1Fac.GetName();
	for (uint i = 0; i < T1_FAC.length(); ++i) {
		if (T1_FAC[i] == name)
			return ai.GetCircuitDef(T2_FAC[i]);
	}
	return null;
}

// T3 is this variant's WIN CONDITION, and it has never once been reached: mean
// T3 metal across 36 measured player-games is exactly zero. The doctrine is
// hold cheaply, out-eco behind the wall, then finish with T3 -- but nothing ever
// decided to build the gantry, so every game was decided at T2 by whoever had
// more army. Without this the rest of the plan has no ending.
//
// Gated on a real economy rather than a clock: the gantry is expensive and
// starting one the economy cannot finish is the same trap that starting an
// unaffordable T2 plant was.
// Was 38. apex's economy runs poorer than stock's by design-cost, so 38 was
// reached only near game end -- 420 metal of T3 fielded, a token rather than the
// hammer the doctrine calls for. 26 is still a real economy and leaves time to
// actually build a T3 force with it.
// apexearth, on when a human commits to T3: "you shouldn't really be making big
// T3 until you're usually over 100m per second. That's after having 1 or 2 afus
// usually." That matches the arithmetic measured here -- a Korgoth is ~11,000
// metal, so at 40 m/s one unit costs 275 seconds of the whole team's income, and
// the two or three we ever fielded were exactly what that affords.
//
// The gate was 26, roughly four times too low: it committed to a gantry the
// economy could not feed, which is why T3 spend sat near 3,500 for a whole game
// while the metal would have bought a real T2 force instead. 100 is the real
// bar, and reaching it is an ECONOMY problem -- advanced fusion first.
const float T3_METAL_INCOME = 100.f;

// Income alone is the wrong gate. Observed live: the team reached 100 metal/s,
// committed to an ~8000-metal gantry, and lost every engagement on the map
// while it built -- the same metal spent on T2 units would have held the line.
// A gantry is only worth starting from a position that is not collapsing.
//
// Two conditions, both from signals already maintained here:
//   gTurtle       -- Military sets this when our army value fell 18% in 20s
//                    while the enemy still fields a mobile force. That is
//                    precisely "we are losing trades right now".
//   army vs threat -- and we should at least be matching what they field, not
//                    merely have stopped bleeding.
const float T3_ARMY_RATIO = 1.0f;

// Metal income above which the gTurtle and army-ratio vetoes stop applying, so a
// gantry gets placed while we are LOSING -- which is the case they were refusing.
// See T3Worthwhile().
//
// 150, only 50 above the T3_METAL_INCOME floor, because the point is to catch
// the situation early rather than to mark an elite economy. At 150 m/s a gantry
// is 56 seconds of income and a Shiva is 10; if enemy T3 is in the base, that is
// already worth spending whatever the army ratio says. The live observation that
// prompted this was a player at 398 m/s building nothing, so the bar only has to
// sit far enough below that to trigger well before the game is decided.
const float T3_INCOME_URGENT = 150.f;

// One gantry per this much metal income, floor 1, cap GANTRY_MAX.
//
// gHaveT3 is a latch set the moment the first gantry appears, and both build
// decisions tested !gHaveT3 -- so the AI built exactly ONE gantry per game at any
// income. Reported from a hosted game: "for a very long time no gantries were
// being made, except for the first one." A gantry builds one unit at a time, so
// at the 400 m/s these games reach that single plant is the throughput ceiling on
// the whole T3 win condition.
//
// gHaveT3 itself stays -- military.as reads it for big-gun placement -- it just
// no longer decides whether to build another.
const float GANTRY_PER_INCOME = 150.f;
const int   GANTRY_MAX        = 4;

// A T1 bot lab is wanted for the whole game, not just the opening: it is the
// cheap assault spam and the only source of rez bots. apexearth: "one T2
// assault unit costs like 5 or 6 T1 assault units, and that many T1s can kill
// the T2 if the T2 doesn't have a good mass".
CCircuitDef@ T1BotLab()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corlab);
	if (side == "legion")
		return ai.GetCircuitDef(leglab);
	return ai.GetCircuitDef(armlab);
}

bool HaveT1BotLab()
{
	CCircuitDef@ lab = T1BotLab();
	// count is incremented in RegisterTeamUnit, which runs for the nanoframe, so
	// a lab already under construction counts and this cannot re-request one.
	return (lab !is null) && (lab.count > 0);
}

// Do we want another gantry? Counts nanoframes: CCircuitDef::count is
// incremented in RegisterTeamUnit, which runs for the nanoframe, so one already
// under construction is counted and this cannot double-request.
bool WantMoreGantries()
{
	CCircuitDef@ gant = T3Gantry();
	if (gant is null)
		return false;
	int want = int(aiEconomyMgr.metal.income / GANTRY_PER_INCOME);
	if (want < 1)
		want = 1;
	else if (want > GANTRY_MAX)
		want = GANTRY_MAX;
	return int(gant.count) < want;
}

bool T3Worthwhile()
{
	const float inc = aiEconomyMgr.metal.income;
	if (inc <= T3_METAL_INCOME)
		return false;
	// Above a large economy the two vetoes below block exactly the case they
	// should permit, so they stop applying.
	//
	// Observed live in a hosted +40% game: the best player was on 398 metal/s
	// with enemy T3 already in the base, and built no gantry at all. gTurtle was
	// set -- that is what "their army is on our doorstep" looks like -- and our
	// armyCost was below theirs precisely because they had T3 and we did not. So
	// both vetoes fired for the same reason, and the AI stood still.
	//
	// Those vetoes were calibrated when a gantry was a large, irreversible bet.
	// It is not at this income. Real costs: corgant 8400, corshiva 1550,
	// armbanth 13500. At 398 m/s that is 21 s, 4 s and 34 s of income. Refusing
	// to spend 21 seconds of income on the counter to the thing killing you is
	// the wrong answer at any army ratio.
	if (inc >= T3_INCOME_URGENT)
		return true;
	if (Military::gTurtle)
		return false;
	return aiMilitaryMgr.armyCost >= Military::EnemyArmyCost() * T3_ARMY_RATIO;
}
bool gHaveT3 = false;

CCircuitDef@ T3Gantry()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corgant);
	if (side == "legion")
		return ai.GetCircuitDef(leggant);
	return ai.GetCircuitDef(armshltx);
}

CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	CCircuitDef@ pick = aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
	if (isStart || (pick is null)) {
		if (isStart && IsAirFactory(pick) && !MayOpenAir()) {
			CCircuitDef@ ground = GroundOpening();
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
	if (!HaveT1BotLab() && (gHaveT2 || (ai.frame > FOLLOWER_TECH_FRAME))) {
		CCircuitDef@ lab = T1BotLab();
		if (lab !is null) {
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

	if (MayPursueT2() && !gHaveT2 && RushReady() && RushWindowOpen()) {
		CCircuitDef@ adv = AdvCounterpart();
		if (adv !is null) {
			AiLog(T() + "apex: rusher building advanced plant " + adv.GetName()
				+ " (from " + gT1Fac.GetName() + ")");
			return adv;
		}
		AiLog(T() + "apex: rush WANTS T2 but no counterpart for "
			+ ((gT1Fac is null) ? "<unknown T1 factory>" : gT1Fac.GetName()));
	}

	// Last, so it never pre-empts the tech rush, the bot lab or the gantry.
	if (Air::Armed()) {
		CCircuitDef@ airFac = Air::FactoryToBuild();
		if (airFac !is null) {
			AiLog(T() + "apex: air assassin building " + airFac.GetName());
			return airFac;
		}
	}

	return pick;
}

/* --- Utils --- */

int MakeSwitchInterval()
{
	return AiRandom(550, 900) * SECOND;
}

}  // namespace Factory
