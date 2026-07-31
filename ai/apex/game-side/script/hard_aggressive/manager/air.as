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
const float AIR_MIN_INCOME = 60.f;

// Enemy anti-air already on the field, in metal, above which we do not start.
// GetEnemyCost sums what we have SEEN, so it is a floor on their AA rather than a
// measurement of it -- which biases this gate towards committing.
const float AIR_AA_CEILING = 2500.f;

const int   AIR_BOMBERS    = 20;
const int   AIR_FIGHTERS   = 20;

// Enqueue does not dedup and CCircuitDef::count only moves when a unit is
// registered, so back-to-back orders overshoot the target. Same reason
// Factory::RUSH_CON_SPACING exists.
const int   AIR_ORDER_SPACING = 2 * SECOND;

// Massing forever is its own failure. Past this, strike with whatever is built
// provided it is at least half a force.
const int   AIR_DEADLINE   = 8 * MINUTE;

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
CCircuitDef@ gBomber  = null;
CCircuitDef@ gFighter = null;

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
	} else if (side == "legion") {
		@gPlant1 = ai.GetCircuitDef("legap");   @gPlant2 = ai.GetCircuitDef("legaap");
		@gCon1   = ai.GetCircuitDef("legca");   @gCon2   = ai.GetCircuitDef("legaca");
		@gBomber = ai.GetCircuitDef("legphoenix"); @gFighter = ai.GetCircuitDef("legvenator");
	} else {
		@gPlant1 = ai.GetCircuitDef("armap");   @gPlant2 = ai.GetCircuitDef("armaap");
		@gCon1   = ai.GetCircuitDef("armca");   @gCon2   = ai.GetCircuitDef("armaca");
		@gBomber = ai.GetCircuitDef("armpnix"); @gFighter = ai.GetCircuitDef("armhawk");
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

bool Massed()
{
	return (Have(gBomber) >= AIR_BOMBERS) && (Have(gFighter) >= AIR_FIGHTERS);
}

bool HalfMassed()
{
	return (Have(gBomber) * 2 >= AIR_BOMBERS) && (Have(gFighter) * 2 >= AIR_FIGHTERS);
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

CCircuitDef@ NextAirDef()
{
	const int nb = Have(gBomber);
	const int nf = Have(gFighter);
	// Grow the escort in step with the strike force rather than after it.
	if ((gFighter !is null) && gFighter.IsAvailable(ai.frame)
		&& (nf * AIR_BOMBERS < nb * AIR_FIGHTERS))
	{
		return gFighter;
	}
	if ((gBomber !is null) && gBomber.IsAvailable(ai.frame) && (nb < AIR_BOMBERS))
		return gBomber;
	if ((gFighter !is null) && gFighter.IsAvailable(ai.frame) && (nf < AIR_FIGHTERS))
		return gFighter;
	return null;
}

// Called from Factory::AiMakeTask. Null means "not my business", not "idle".
IUnitTask@ MakeFactoryTask(CCircuitUnit@ fac)
{
	if (!Armed() || gStrike)
		return null;
	ResolveDefs();
	if ((gPlant2 is null) || (fac.circuitDef.id != gPlant2.id))
		return null;
	if (ai.frame < gNextAirOrder)
		return null;

	CCircuitDef@ want = NextAirDef();
	if (want is null)
		return null;
	IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
			want, fac.GetPos(ai.frame), 0.f));
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
		|| ((gFighter !is null) && (id == gFighter.id));
}

void Release(const string& in why)
{
	gStrike = true;
	// ANTI_STAT makes CBombTask::FindTarget skip enemy army but keep static eco,
	// builders and commanders. CCircuitDef is owned per CCircuitAI instance, so
	// this and the retreat below change nothing for our allies.
	if (gBomber !is null) {
		gBomber.AddAttribute(Unit::Attr::ANTI_STAT.type);
		gBomber.SetRetreat(0.f);
	}
	if (gFighter !is null)
		gFighter.SetRetreat(0.f);
	AiLog(Factory::T() + "apex: air strike -- " + why
		+ " bombers=" + Have(gBomber) + " fighters=" + Have(gFighter)
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

	// Heartbeat. A gate that never fires and an input that is dead read the same
	// in a log that only prints on transitions.
	if (Armed() && (ai.frame >= gNextLog)) {
		gNextLog = ai.frame + 60 * SECOND;
		CCircuitDef@ want = FactoryToBuild();
		AiLog(Factory::T() + "apex: air " + Have(gBomber) + "/" + AIR_BOMBERS
			+ " bombers, " + Have(gFighter) + "/" + AIR_FIGHTERS + " fighters"
			+ " plants=" + Have(gPlant1) + "," + Have(gPlant2)
			+ " cons=" + (HaveAirCon() ? "1" : "0")
			+ " want=" + ((want is null) ? "-" : want.GetName())
			+ " enemyAA=" + formatFloat(EnemyAACost(), "", 0, 0));
	}
}

}  // namespace Air
