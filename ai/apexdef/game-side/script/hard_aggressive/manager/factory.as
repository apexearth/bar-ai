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
const float RUSH_ENERGY_TARGET = 150.f;      // measured: BARb hits this ~5.5 min
const float RUSH_ENERGY_FLOOR  = 90.f;       // fallback: reached before 4 min
const int   RUSH_LATEST        = 5 * MINUTE; // T2 should exist before 10 min

// The whole team pools metal behind the rusher, so it must not be the poorest
// player on it -- feeding a starved economy just moves the starvation around.
// Require the designated lead to sit in the top half of ally metal incomes.
//
// Every instance evaluates this over the same synced data (allied team incomes
// are readable; the engine returns -1 only when it refuses), so lead and
// followers agree on the answer without needing to talk to each other. A refusal
// is treated as "unknown", never as "poor" -- otherwise a permissions quirk
// would silently disable the rush the way it once disabled slinging.
// Observed live: on a map where some starts have a single mex, the AI's own
// GetLeadTeamId() picked a player on 4 metal/sec and the whole team pooled
// behind it. Merely vetoing a poor lead is not enough -- that just cancels the
// rush and nobody else takes it. Pick the richest ally outright.
//
// Every instance evaluates this over the same synced data, so lead and
// followers reach the same answer with no cross-team signalling. Ties break on
// lowest team id so the choice is deterministic. A -1 means the engine refused
// the query; that is "unknown", never "poor" -- reading a refusal as a
// meaningful zero is what silently disabled slinging once already.
// Choosing a lead early is choosing it on noise: at 2 minutes every ally reads
// a near-identical trickle and the "richest" is whoever happened to finish a mex
// first. Wait for 5 minutes, by which point the economies have actually
// separated. The exception is accelerated settings -- some games hand out enough
// income that the picture is clear well before then -- so an ally already over
// 15 metal/s is decisive evidence and we commit immediately.
const int   RUSH_DECIDE_FRAME  = 5 * MINUTE;
const float RUSH_DECIDE_INCOME = 15.f;

int gRushLead = -1;   // latched once chosen: a dip must not hand the role over

int RushLeadTeamId()
{
	if (gRushLead >= 0)
		return gRushLead;

	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return ai.GetLeadTeamId();

	int best = -1;
	float bestInc = -1.f;
	uint known = 0;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = mates[i];
		const float inc = ai.GetTeamMetalIncome(t);
		if (inc < 0.f)
			continue;
		++known;
		if ((inc > bestInc) || ((inc == bestInc) && (t < best))) {
			bestInc = inc;
			best = t;
		}
	}
	// Nothing readable yet (very early game): fall back to the engine's pick,
	// but do not latch it -- re-decide once incomes exist.
	if ((known == 0) || (best < 0))
		return ai.GetLeadTeamId();

	if ((ai.frame < RUSH_DECIDE_FRAME) && (bestInc < RUSH_DECIDE_INCOME))
		return best;   // provisional -- keep re-deciding until the field settles

	gRushLead = best;
	AiLog(T() + "apex: rush lead = team " + best + " at "
		+ formatFloat(bestInc, "", 0, 1) + " metal/s (richest of "
		+ known + " allies)");
	return best;
}

bool LeadIsRichEnough()
{
	return RushLeadTeamId() >= 0;
}

bool IsTechLead()
{
	return ai.teamId == RushLeadTeamId();
}

bool RushReady()
{
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
// metal of T2 units to apexdef's 4,595 and upgrades 2.9 mexes to our 1.4. The
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

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
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
	if (IsTechLead() && !gHaveT2 && RushReady() && !IsSmallTeam()) {
		CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (con !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
					con, unit.GetPos(ai.frame), 0.f));
			if (rec !is null)
				return rec;
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
	if (gHaveT2 && IsTechLead() && !IsSmallTeam() && Builder::OwesAdvCons()) {
		CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER2.type);
		if (con !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::NOW,
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
CCircuitUnit@ gT1FacUnit = null;
bool gT1Reclaimed = false;
// Set once the rusher has actually asked for the advanced plant, so we never
// eat the T1 lab before there is something to spend it on.
bool gRushCommitted = false;

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
string T()
{
	return "[" + formatFloat(float(ai.frame) / float(MINUTE), "", 0, 1) + "m] ";
}

// Periodic dump of every input the rush decision reads, so a slow tech can be
// attributed to a specific gate rather than guessed at. One line per 30s.
// The T1 lab is ~600-900 metal standing idle -- the rush already stops it
// producing, so it is pure banked metal doing nothing. Feed it into the plant it
// is being replaced by; a T1 lab can be rebuilt later once T2 economy is up.
void UpdateRushReclaim()
{
	if (gT1Reclaimed || gHaveT2 || !IsTechLead() || !RushReady())
		return;
	if (gT1FacUnit is null)
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
	if (IsTechLead() && !gHaveT2) {
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
	if (lastSwitchFrame + switchInterval <= ai.frame) {
		switchInterval = MakeSwitchInterval();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
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
	if (!IsTechLead() && ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& (ai.frame < FOLLOWER_TECH_FRAME))
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
	if (IsTechLead() && !gHaveT2 && RushReady()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0))
	{
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
	if (!gHaveT3 && ((userData[facDef.id].attr & Attr::T3) != 0)
		&& (aiEconomyMgr.metal.income > T3_METAL_INCOME))
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
	if (!IsTechLead() && (ai.frame >= FOLLOWER_TECH_FRAME)
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
// Was 38. apexdef's economy runs poorer than stock's by design-cost, so 38 was
// reached only near game end -- 420 metal of T3 fielded, a token rather than the
// hammer the doctrine calls for. 26 is still a real economy and leaves time to
// actually build a T3 force with it.
const float T3_METAL_INCOME = 26.f;
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
		if (isStart && IsAirFactory(pick) && (IsSmallTeam() || IsTechLead())) {
			CCircuitDef@ ground = GroundOpening();
			if (ground !is null) {
				AiLog(T() + "apex: opening " + pick.GetName() + " -> "
					+ ground.GetName()
					+ (IsSmallTeam() ? " (no air on a small team)"
					                 : " (no air tech lead)"));
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
	if (!gHaveT3 && (aiEconomyMgr.metal.income > T3_METAL_INCOME)) {
		CCircuitDef@ gant = T3Gantry();
		if (gant !is null) {
			AiLog(T() + "apex: building T3 gantry " + gant.GetName()
				+ " at " + formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
			return gant;
		}
	}

	if (IsTechLead() && !gHaveT2 && RushReady()) {
		CCircuitDef@ adv = AdvCounterpart();
		if (adv !is null) {
			gRushCommitted = true;
			AiLog(T() + "apex: rusher building advanced plant " + adv.GetName()
				+ " (from " + gT1Fac.GetName() + ")");
			return adv;
		}
		AiLog(T() + "apex: rush WANTS T2 but no counterpart for "
			+ ((gT1Fac is null) ? "<unknown T1 factory>" : gT1Fac.GetName()));
	}

	return pick;
}

/* --- Utils --- */

int MakeSwitchInterval()
{
	return AiRandom(550, 900) * SECOND;
}

}  // namespace Factory
