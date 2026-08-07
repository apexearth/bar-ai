#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"


namespace Air {

//------------------------------------------------------------------------------
// Surprise air eco-assassination.
//
// One player per ally team quietly builds a T2 air force, keeps it at home while
// it grows, then throws all of it at the enemy economy and never brings it back.
// apexearth: "nobody has seen air the entire game, then suddenly there's a ton of
// air doing a nasty attack. It's the surprise that makes it possible. If the
// enemy already has a lot of anti-air, the chance is gone."
//
// NONE OF THIS IS MEASURED. Every constant below is reasoned from unit costs and
// from the C++ it drives; not one game has been run with it.
//------------------------------------------------------------------------------

// Mid-game only. Before this the whole team is pooling metal behind the tech
// lead (Military::RUSH_GIVEUP, same frame), and an air plant competes with it.
const int   AIR_FROM       = 15 * MINUTE;

// The candidate's OWN metal income. 20 bombers + 20 fighters is ~7,400 metal for
// Armada and ~8,900 for Cortex, so this is roughly two minutes of one player's
// income. Deliberately out of reach of the ~40 m/s the 4v4 benchmark reaches and
// comfortable at the 150-400 m/s observed in hosted games.
// Lowered 60 -> 40, because 60 was self-defeating. Measured: the assassin was
// elected at 63 metal/s and by then EnemyAACost() was already over the ceiling
// below, so Armed() never became true and it built nothing. The strategy needs
// SURPRISE -- "if the enemy already has a lot of anti-air, the chance is gone" --
// and waiting for a bigger income is waiting for the enemy to build the very
// thing that cancels it. 20 bombers + 20 fighters is ~7,400-8,900 metal, so at
// 40 metal/s that is about three and a half minutes of one player's income.
const float AIR_MIN_INCOME = 40.f;

// Enemy anti-air already on the field, in metal, above which we do not start.
// GetEnemyCost sums what we have SEEN, so it is a floor on their AA rather than a
// measurement of it -- which biases this gate towards committing.
const float AIR_AA_CEILING = 2500.f;

// Sized for the game we now play, not the one these were guessed for.
//
// Measured over 6 games with the basic tier: committed at 15.0 min, 11 bombers
// and 10 fighters by 18.0, 14 and 14 by 19.0 -- and then the heartbeat stops,
// because the game was already WON. Nothing was wrong with production; 20+20 and
// a deadline of commit+8min simply land after the killing blow has ended it.
//
// 12 basic bombers is ~1,800 metal and still a real strike on economy, with 8
// fighters as escort rather than a matching wing.
const int   AIR_BOMBERS    = 12;
const int   AIR_FIGHTERS   = 8;

// Scale the strike size with our own economy. apexearth: "I think it should
// be standard air logic to save up 10+ bombers before using them. Scaled
// based on how good our economy is." AIR_BOMBERS/AIR_FIGHTERS above are the
// floor (already above the "10+" bar); a stronger economy can afford, and
// profits more from, a bigger and more decisive strike than the minimum.
const float AIR_SCALE_INCOME = 80.f;   // extra metal/s per extra bomber above the floor
const int   AIR_BOMBERS_MAX  = 30;

int ScaledBombers()
{
	const int extra = int(aiEconomyMgr.metal.income / AIR_SCALE_INCOME);
	const int want = AIR_BOMBERS + extra;
	return (want > AIR_BOMBERS_MAX) ? AIR_BOMBERS_MAX : want;
}

int ScaledFighters()
{
	// Same escort ratio as the floor (8 fighters per 12 bombers), scaled
	// with the bomber count rather than income directly.
	return int(float(ScaledBombers()) * float(AIR_FIGHTERS) / float(AIR_BOMBERS));
}

// Enqueue does not dedup and CCircuitDef::count only moves when a unit is
// registered, so back-to-back orders overshoot the target. Same reason
// Factory::RUSH_CON_SPACING exists.
const int   AIR_ORDER_SPACING = 2 * SECOND;

// How many aircraft to queue per order, so the plant never stands idle between
// them. apexearth: "build units on repeat -- you aren't using all your resources
// because there's a delay from once a unit gets built and you give the order to
// build another unit."
//
// There is no repeat flag to set: CmdBuild takes one def per call and Spring's
// CMD_REPEAT is not bound to the script. But CFactoryManager::DefaultMakeTask
// scans factoryTasks for an existing unassigned recruit before creating one, so
// several queued tasks ARE picked up by an idle factory in turn. Queue depth is
// the repeat order, spelled at this layer.
//
// Overshoot is bounded by the same counters that bound a single order: the batch
// is only issued while the force is still short of ScaledBombers()/ScaledFighters().
const int   AIR_BATCH = 6;

// Priority::NOW while the strike is being built, and constructors pulled onto
// the plant to assist it.
//
// apexearth: "an airstrike with only six bombers is really pathetic. We should
// try to boost the priority on production when we choose to do that." Measured:
// the strike released on the deadline path with 6 bombers and 4 fighters -- the
// half-mass floor -- because four minutes of ONE plant's build rate is about six
// aircraft.
//
// Priority alone cannot fix that: an air plant builds nothing but air, so
// out-prioritising its own queue buys nothing. What it does buy is resources
// under a stall, since CmdPriority decides who gets metal first. The throughput
// levers are build power (assist) and a SECOND plant, so all three go together.

// Massing forever is its own failure. Past this, strike with whatever is built
// provided it is at least half a force.
// Also cut, for the same reason: eight minutes after commitment was past the end
// of several games.
const int   AIR_DEADLINE   = 4 * MINUTE;

// One writer per slot, as with the tech-lead election in factory.as: every
// instance publishes its own income, and only the elector publishes the answer.
const string TV_AIRINC  = "airinc";
const string TV_AIRLEAD = "airlead";

int  gAirLead      = -1;
int  gLeadCheckedAt = -1000;
int  gCommitFrame  = -1;
bool gStrike       = false;
bool gAbort        = false;
int  gNextAirOrder = 0;
int  gNextProbe    = 0;
int  gNextLog      = 0;
int  gNextElectLog = 0;
bool gAnnounced    = false;

bool gDefsResolved = false;
CCircuitDef@ gPlant1  = null;   // T1 air plant
CCircuitDef@ gPlant2  = null;   // T2 air plant
CCircuitDef@ gCon1    = null;   // T1 air constructor
CCircuitDef@ gCon2    = null;   // T2 air constructor
CCircuitDef@ gBomber  = null;   // advanced bomber
CCircuitDef@ gFighter = null;   // advanced fighter
// BASIC tier, from the plant we actually get built.
//
// Measured across 4 games: the strategy reached at most 6 bombers and 5 fighters
// against a release bar of 20 and 20, so it never struck once -- it built a
// handful of aircraft and held them idle at home for the rest of the game, which
// is worse than not building them. The cause is upstream: nearly every sample
// read plants=1,0, i.e. the ADVANCED plant never finished, and both defs above
// are advanced-only.
//
// The basic tier is a third of the price -- armthund 145 and armfig 73 against
// armpnix 230 and armhawk -- and comes from the plant that does get built. It
// also suits the premise better: the whole idea is surprise, and surprise is
// cheapest early.
CCircuitDef@ gBomber1  = null;
CCircuitDef@ gFighter1 = null;

void ResolveDefs()
{
	if (gDefsResolved)
		return;
	gDefsResolved = true;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		@gPlant1 = ai.GetCircuitDef("corap");   @gPlant2 = ai.GetCircuitDef("coraap");
		@gCon1   = ai.GetCircuitDef("corca");   @gCon2   = ai.GetCircuitDef("coraca");
		@gBomber = ai.GetCircuitDef("corhurc"); @gFighter = ai.GetCircuitDef("corvamp");
		@gBomber1 = ai.GetCircuitDef("corshad"); @gFighter1 = ai.GetCircuitDef("corveng");
	} else if (side == "legion") {
		@gPlant1 = ai.GetCircuitDef("legap");   @gPlant2 = ai.GetCircuitDef("legaap");
		@gCon1   = ai.GetCircuitDef("legca");   @gCon2   = ai.GetCircuitDef("legaca");
		@gBomber = ai.GetCircuitDef("legphoenix"); @gFighter = ai.GetCircuitDef("legvenator");
		// gBomber1 is the BASIC tier: a reusable strike unit built off the T1 plant,
		// held and released in waves (see Release()/ScaledBombers() below), the same
		// way corshad/armthund are. legkam ("Martyr") is a one-shot kamikaze drone,
		// unlike those two -- looked like a bug and was swapped for legmos
		// ("Mosquito") on 2026-08-05, but that regressed a confirmed Legion,Legion
		// batch 43.8% -> 31.2%. legmos's weapon has stockpile=true (a 1.8s build-up,
		// 4-shot cap, like a nuke silo) -- Release()'s hold-then-send logic has no
		// stockpile-order step, so these almost certainly flew in with zero shots
		// loaded and did nothing, worse than a kamikaze that at least explodes.
		// Reverted. legap's roster (legca, legfig, legkam, legcib, legmos, leglts,
		// legatrans) has no conventional always-loaded reusable bomber -- legkam is
		// the least-bad fit until a real alternative is found (or gBomber1 is left
		// null for Legion and this basic tier is skipped entirely).
		@gBomber1 = ai.GetCircuitDef("legkam"); @gFighter1 = ai.GetCircuitDef("legfig");
	} else {
		@gPlant1 = ai.GetCircuitDef("armap");   @gPlant2 = ai.GetCircuitDef("armaap");
		@gCon1   = ai.GetCircuitDef("armca");   @gCon2   = ai.GetCircuitDef("armaca");
		@gBomber = ai.GetCircuitDef("armpnix"); @gFighter = ai.GetCircuitDef("armhawk");
		@gBomber1 = ai.GetCircuitDef("armthund"); @gFighter1 = ai.GetCircuitDef("armfig");
	}
}

// The elector -- lowest team id in the ally roster -- is Factory::ElectorTeamId().
// Reusing it keeps one writer for both elections instead of two schemes that can
// disagree about who is allowed to publish.
void RunElection()
{
	if (ai.ReadTeamValue(ai.teamId, TV_AIRLEAD, -1.f) >= 0.f)
		return;   // latched: the role is paid for in factories, so it never moves
	if (ai.frame < AIR_FROM)
		return;

	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return;
	const int tech = Factory::RushLeadTeamId();
	const bool skipTech = (mates.length() > 1);

	int best = -1;
	float bestInc = AIR_MIN_INCOME;
	float bestSeen = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (skipTech && (t == tech))
			continue;
		const float inc = ai.ReadTeamValue(t, TV_AIRINC, -1.f);
		if (inc > bestSeen)
			bestSeen = inc;
		if (inc > bestInc) {
			bestInc = inc;
			best = t;
		}
	}
	if (best < 0) {
		// Say so. An unmet income bar and a script that never compiled produce the
		// same silence, and this bar is deliberately set above what the 4v4
		// benchmark reaches -- so "no air all game" is the expected result there
		// and has to be distinguishable from a broken build.
		if (ai.frame >= gNextElectLog) {
			gNextElectLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: no air assassin, best ally income "
				+ formatFloat(bestSeen, "", 0, 0)
				+ "/" + formatFloat(AIR_MIN_INCOME, "", 0, 0));
		}
		return;
	}

	ai.PublishTeamValue(TV_AIRLEAD, float(best));
	AiLog(Factory::T() + "apex: air assassin = team " + best
		+ " at " + formatFloat(bestInc, "", 0, 0) + " metal/s");
}

int AirLeadTeamId()
{
	if (ai.frame < gLeadCheckedAt + 1 * SECOND)
		return gAirLead;
	gLeadCheckedAt = ai.frame;
	gAirLead = int(ai.ReadTeamValue(Factory::ElectorTeamId(), TV_AIRLEAD, -1.f));
	return gAirLead;
}

bool IsAirLead()
{
	const int lead = AirLeadTeamId();
	return (lead >= 0) && (lead == ai.teamId);
}

// Permanently stood down: gAbort is never reset and the election is latched,
// so this is one-way. factory.as reads it to release the air plants it would
// otherwise lock out of production for the rest of the game.
bool RoleAbandoned()
{
	return gAbort;
}

float EnemyAACost()
{
	return aiEnemyMgr.GetEnemyCost(RT::AA);
}

bool Committed()
{
	return gCommitFrame >= 0;
}

// May this instance act on the strategy at all? Once committed the AA ceiling
// stops being checked here -- a wall that goes up mid-buildup is handled by the
// abort branch in Update(), which decides between striking early and standing
// down rather than simply freezing production.
bool Armed()
{
	if (gAbort || !IsAirLead())
		return false;
	if (ai.frame < AIR_FROM)
		return false;
	return Committed() || (EnemyAACost() <= AIR_AA_CEILING);
}

int Have(CCircuitDef@ def)
{
	return (def is null) ? 0 : def.count;
}

// The force is both tiers together: a basic bomber and an advanced one are both
// a bomber for the purpose of deciding whether we have enough to strike.
int Bombers()  { return Have(gBomber) + Have(gBomber1); }
int Fighters() { return Have(gFighter) + Have(gFighter1); }

bool Massed()
{
	return (Bombers() >= ScaledBombers()) && (Fighters() >= ScaledFighters());
}

bool HalfMassed()
{
	return (Bombers() * 2 >= ScaledBombers()) && (Fighters() * 2 >= ScaledFighters());
}

bool HaveAirCon()
{
	return (Have(gCon1) > 0) || (Have(gCon2) > 0);
}

// The next factory this strategy wants, or null.
//
// The T2 air plant is buildable by AIR constructors only -- armca/armaca,
// corca/coraca, legca/legaca -- and no ground constructor of any tier has it in
// its build options. The only source of an air constructor is the T1 air plant,
// so the plant chain is two steps, not one. Returning the T2 plant before an air
// con exists is the silent no-op CLAUDE.md warns about.
CCircuitDef@ FactoryToBuild()
{
	ResolveDefs();
	// A SECOND basic plant as soon as we are committed and short of a force.
	// Two plants is twice the aircraft per minute, and the strike is bounded by
	// minutes, not by metal -- 12 basic bombers is only ~1,800.
	//
	// This used to require the ADVANCED plant first. Measured in a hosted 11v13:
	// every sample read plants=1,0 -- the advanced plant never finished, so the
	// second basic one was never reachable, and four minutes of a single plant
	// is about six aircraft. The strike released on the deadline at 6 bombers
	// and 4 fighters against 12 and 8. Throughput has to come before tier.
	if (Committed() && !Massed()
		&& (gPlant1 !is null) && gPlant1.IsAvailable(ai.frame) && (Have(gPlant1) == 1))
	{
		return gPlant1;
	}
	if ((gPlant2 is null) || !gPlant2.IsAvailable(ai.frame) || (Have(gPlant2) > 0))
		return null;
	if (Have(gPlant1) <= 0) {
		if ((gPlant1 is null) || !gPlant1.IsAvailable(ai.frame))
			return null;
		return gPlant1;
	}
	if (!HaveAirCon())
		return null;
	return gPlant2;
}

bool WantsFactory(const CCircuitDef@ facDef)
{
	if (!Armed() || (facDef is null))
		return false;
	CCircuitDef@ want = FactoryToBuild();
	return (want !is null) && (want.id == facDef.id);
}

// The advanced air plant has no entry in Opener::GetOpenInfo, so it falls back to
// the default queue -- three builders, a scout and five raiders. Those raiders are
// gunships that fly out and attack, which spends the surprise before there is
// anything to be surprising with.
bool SuppressesOpener(const CCircuitDef@ facDef)
{
	if (!Armed() || (facDef is null))
		return false;
	ResolveDefs();
	return (gPlant2 !is null) && (facDef.id == gPlant2.id);
}

// Stock reconsiders factories every AiRandom(550,900) seconds, which is longer
// than the whole window this strategy has. Probe instead -- but only while there
// is actually a plant outstanding, so the switch gate is not left open (a
// permanently-true isSwitchTime also disables EconomyManager's metal gate).
bool WantsSwitchProbe()
{
	if (!Armed() || (FactoryToBuild() is null))
		return false;
	if (ai.frame < gNextProbe)
		return false;
	gNextProbe = ai.frame + 20 * SECOND;
	return true;
}

CCircuitDef@ NextAirDef(bool advanced)
{
	CCircuitDef@ bomber  = advanced ? gBomber  : gBomber1;
	CCircuitDef@ fighter = advanced ? gFighter : gFighter1;
	// Progress is counted across BOTH tiers, so a basic plant stops producing
	// once the advanced one has finished the job and vice versa.
	const int nb = Bombers();
	const int nf = Fighters();
	// Grow the escort in step with the strike force rather than after it.
	// Ratio-based, not scaled-count-based, so it holds regardless of how big
	// ScaledBombers()/ScaledFighters() have grown -- AIR_BOMBERS/AIR_FIGHTERS
	// is the same proportion ScaledFighters()/ScaledBombers() scales from.
	if ((fighter !is null) && fighter.IsAvailable(ai.frame)
		&& (nf * AIR_BOMBERS < nb * AIR_FIGHTERS))
	{
		return fighter;
	}
	if ((bomber !is null) && bomber.IsAvailable(ai.frame) && (nb < ScaledBombers()))
		return bomber;
	if ((fighter !is null) && fighter.IsAvailable(ai.frame) && (nf < ScaledFighters()))
		return fighter;
	return null;
}

// Called from Factory::AiMakeTask. Null means "not my business", not "idle".
// Queue AIR_BATCH of the same aircraft and hand back the first. The rest sit in
// factoryTasks and the plant takes them itself as it finishes each one, with no
// round trip through the script.
IUnitTask@ EnqueueBatch(CCircuitUnit@ fac, CCircuitDef@ want)
{
	const AIFloat3 pos = fac.GetPos(ai.frame);
	IUnitTask@ first = null;
	for (int i = 0; i < AIR_BATCH; ++i) {
		IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
				Task::RecruitType::FIREPOWER, Task::Priority::NOW,
				want, pos, 0.f));
		if (rec is null)
			break;
		if (first is null)
			@first = rec;
	}
	return first;
}

IUnitTask@ MakeFactoryTask(CCircuitUnit@ fac)
{
	if (!Armed() || gStrike)
		return null;
	ResolveDefs();
	if (ai.frame < gNextAirOrder)
		return null;

	// The BASIC plant's one job: an air constructor, because FactoryToBuild will
	// not ask for the advanced plant until HaveAirCon() is true. Nothing was
	// producing one -- this function answered only for gPlant2, so the chain
	// needed a constructor that the only plant we owned was never told to build.
	// Measured across 8 games: 133 of 134 samples read cons=0, and 0 bombers were
	// ever built.
	if ((gPlant1 !is null) && (fac.circuitDef.id == gPlant1.id)) {
		// The air constructor first -- it is the only route to the advanced
		// plant, and nothing else was ever going to build one.
		if (!HaveAirCon() && (gCon1 !is null) && gCon1.IsAvailable(ai.frame)) {
			IUnitTask@ con = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
					gCon1, fac.GetPos(ai.frame), 0.f));
			if (con !is null) {
				gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
				AiLog(Factory::T() + "apex: air assassin building " + gCon1.GetName()
					+ " to reach the advanced plant");
			}
			return con;
		}
		// Then the strike force itself, in the BASIC tier. Waiting for the
		// advanced plant is what left this strategy holding six bombers at the
		// end of a game.
		CCircuitDef@ want1 = NextAirDef(false);
		if (want1 is null)
			return null;
		IUnitTask@ rec1 = EnqueueBatch(fac, want1);
		if (rec1 !is null)
			gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
		return rec1;
	}

	if ((gPlant2 is null) || (fac.circuitDef.id != gPlant2.id))
		return null;

	CCircuitDef@ want = NextAirDef(true);
	if (want is null)
		return null;
	IUnitTask@ rec = EnqueueBatch(fac, want);
	if (rec is null)
		return null;
	gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
	return rec;
}

// Called from Military::AiMakeTask. True means "give this unit no task at all".
//
// There is no way to LAND an aircraft from AngelScript: CmdFindPad and CmdWait
// exist in C++ but only CmdMoveTo is registered, so the strongest available form
// of hiding is a unit with no orders, which hovers where it was built. That is
// weaker than the strategy asks for -- these planes are visible to anything that
// scouts our base -- but it does keep them off the map until the strike.
bool HoldsUnit(CCircuitUnit@ unit)
{
	if (gStrike || !Armed())
		return false;
	ResolveDefs();
	const int id = unit.circuitDef.id;
	return ((gBomber !is null) && (id == gBomber.id))
		|| ((gFighter !is null) && (id == gFighter.id))
		|| ((gBomber1 !is null) && (id == gBomber1.id))
		|| ((gFighter1 !is null) && (id == gFighter1.id));
}

void Release(const string& in why)
{
	gStrike = true;
	Economy::isSwitchAssist = false;   // stop holding build power on the plant
	// ANTI_STAT makes CBombTask::FindTarget skip enemy army but keep static eco,
	// builders and commanders. CCircuitDef is owned per CCircuitAI instance, so
	// this and the retreat below change nothing for our allies.
	if (gBomber !is null) {
		gBomber.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomber.SetRetreat(0.f);
	}
	if (gBomber1 !is null) {
		gBomber1.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomber1.SetRetreat(0.f);
	}
	if (gFighter !is null)
		gFighter.SetRetreat(0.f);
	if (gFighter1 !is null)
		gFighter1.SetRetreat(0.f);
	AiLog(Factory::T() + "apex: air strike -- " + why
		+ " bombers=" + Bombers() + " fighters=" + Fighters()
		+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0));
}

void Update()
{
	ResolveDefs();
	ai.PublishTeamValue(TV_AIRINC, aiEconomyMgr.metal.income);
	if (Factory::ElectorTeamId() == ai.teamId)
		RunElection();

	if (!IsAirLead() || gStrike || gAbort)
		return;

	if (!gAnnounced && Armed()) {
		gAnnounced = true;
		AiLog(Factory::T() + "apex: air assassin armed, enemyAA="
			+ formatFloat(EnemyAACost(), "", 0, 0)
			+ "/" + formatFloat(AIR_AA_CEILING, "", 0, 0));
	}

	// Constructors and nanos assist the plant while the force is being built.
	// Economy::AiUpdateEconomy recomputes isAssistRequired every update, so the
	// flag has to be asserted here rather than set once; it is dropped again in
	// Release() so the assist does not outlive the strike.
	if (Committed() && !Massed())
		Economy::isSwitchAssist = true;

	if (!Committed() && Armed()) {
		CCircuitDef@ first = FactoryToBuild();
		if (first !is null) {
			gCommitFrame = ai.frame;
			AiLog(Factory::T() + "apex: air assassin committing, first plant "
				+ first.GetName());
		}
	}

	if (Massed()) {
		Release("massed");
	} else if (Committed() && (EnemyAACost() > AIR_AA_CEILING)) {
		if (HalfMassed()) {
			Release("enemy AA rising, going early");
		} else {
			gAbort = true;
			AiLog(Factory::T() + "apex: air assassin STANDING DOWN, enemyAA="
				+ formatFloat(EnemyAACost(), "", 0, 0)
				+ " with only " + Have(gBomber) + "/" + Have(gFighter) + " built");
		}
	} else if (Committed() && (ai.frame > gCommitFrame + AIR_DEADLINE) && HalfMassed()) {
		Release("deadline");
	}

	// Why we are NOT armed, when we hold the role. Without this the only evidence
	// is silence: measured twice, the assassin was elected (63 and 81 metal/s)
	// and never armed, and nothing in the log said whether the blocker was the
	// clock, the enemy's anti-air, or an abort.
	if (!Armed() && (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: air lead NOT armed"
			+ " frame=" + ai.frame + "/" + AIR_FROM
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0)
			+ "/" + formatFloat(AIR_AA_CEILING, "", 0, 0)
			+ " abort=" + (gAbort ? "1" : "0"));
	}

	// Heartbeat. A gate that never fires and an input that is dead read the same
	// in a log that only prints on transitions.
	if (Armed() && (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		CCircuitDef@ want = FactoryToBuild();
		AiLog(Factory::T() + "apex: air " + Bombers() + "/" + ScaledBombers()
			+ " bombers, " + Fighters() + "/" + ScaledFighters() + " fighters"
			+ " plants=" + Have(gPlant1) + "," + Have(gPlant2)
			+ " cons=" + (HaveAirCon() ? "1" : "0")
			+ " want=" + ((want is null) ? "-" : want.GetName())
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0));
	}
}

}  // namespace Air
