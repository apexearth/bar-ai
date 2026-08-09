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
// lead, and an air plant competes with it.
//
// 15 -> 11 min on 2026-08-07. 15 was RUSH_GIVEUP's own frame, i.e. the clock at
// which pooling formally stops -- but the thing pooling BUYS, the lead's
// advanced plant, is measured in this repo at a 6.3 min median. So from about
// 7 minutes the competition this guarded against is already over, and the
// remaining 8 minutes were spent waiting for a clock rather than for a state.
//
// Cost of waiting, measured over 16 games vs BARb medium (median length 21.3
// min): the assassin armed in all 16 and committed in all 16, but only 7
// strikes ever released and 5 of those were AIR_DEADLINE forcing a half-massed
// launch. It had ~6 minutes to build and mass ~40 aircraft. BAR's own pro guide
// on early air raids puts the raid at the T1->T2 transition for exactly this
// reason -- the value is in hitting before anti-air exists, and AIR_AA_CEILING
// already encodes that same idea as a gate we lose by waiting.
//
// Not moved to the T1->T2 transition proper: that IS the pooling window, and
// this AI's whole team strategy is built on it. 11 keeps the plant clear of the
// pool and still nearly doubles the time available to mass.
const int   AIR_FROM       = 11 * MINUTE;

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

// Income before a SECOND basic air plant is worth owning. Twice the bar for
// arming at all: the first plant is the strategy, the second is throughput, and
// throughput is only real if the metal exists to keep both busy.
const float AIR_SECOND_PLANT_INCOME = 80.f;

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

// How far behind on the ground cancels the whole strategy. Above parity by a
// clear margin, so an even fight does not veto it; see the check in Update().
const float GROUND_LOST_RATIO = 1.5f;

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

}  // namespace Air
