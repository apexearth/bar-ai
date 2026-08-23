namespace Factory {

// Army catch-up production when behind. Unbudgeted by design (fires while
// LosingGround(), nearly always true once behind), so spacing and the income
// floor below are what stop it converting the whole economy into army.
const int   ARMY_PUSH_SPACING = 12 * SECOND;
// Stops entirely when the economy behind it is too thin to carry it: an army
// bought by starving the mexes cannot be replaced when it dies.
const float ARMY_PUSH_MIN_INCOME = 30.f;
int gNextArmyPush = 0;
int gNextArmyLog = 0;

// Every third catch-up push buys fodder instead of the assault mainstay --
// overriding the configured factory mix, since that mix isn't the cause of a
// thin cheap-unit count while behind. One in three requests is a small share of
// metal (a Tick is 21, a Hammer 130): the stream of bodies is what's wanted.
const int   FODDER_EVERY = 3;
int gArmyPushCount = 0;

// While Military::gTurtle holds (losing the trade, army parked in DEFEND
// tasks), buy artillery instead of the assault mainstay -- a short-ranged
// brawler is worst parked defensively, artillery is best. A substitution, not
// an addition: displaces the assault mainstay, costs no constructor time.
// Alternates with fodder rather than all-artillery, since artillery alone dies
// to anything that reaches it.
const int   TURTLE_MIX_SPACING = 10 * SECOND;
const int   TURTLE_ARTY_EVERY  = 2;   // every other pick is the long-range one
int gNextTurtleMix    = 0;
int gTurtleMixCount   = 0;
int gNextTurtleMixLog = 0;

int gRushLead = -1;   // last PRIMARY lead this instance saw published
bool gAmLead = false;   // this team holds one of the lead slots
bool gT1Reclaimed = false;   // one-shot: we fed our T1 lab into the plant

// ECO LEAD: the primary tech-lead slot stops fielding army and grows economy
// only, so the team has something to spend late instead of four economies that
// all stop at T2. Big-team only -- on a small team, one player fielding no
// army is too large a share of the team's total. Held for the whole game, not
// bounded by Military::RUSH_GIVEUP, since the payoff is specifically late.
bool gEcoActive = false;   // this instance is running as the eco lead right now
int  gEcoLoggedFor = -1;   // team we last announced the role for

// "Being taken apart" is measured as EXTRACTORS LOST off this team's own peak,
// not metal income (which spikes on reclaim and returns to normal without
// meaning "death") and not Military::LosingGround() (compares army value, so a
// player fielding none reads "losing" permanently). Two separate bars: our own
// share reacts early since the eco lead is least able to fight back; an ally's
// bar is set harder since any-ally-below-X is near-always true on a big team.
// Both are SUSTAINED, not instantaneous -- an upgrade destroys the T1 extractor
// before the advanced one exists, so the standing count dips for the whole
// build, and the eco lead upgrades mexes more than anyone.
const float HURT_SELF_FRAC = 0.55f;
const float HURT_ALLY_FRAC = 0.40f;
const uint  HURT_MIN_MEX   = 6;   // under this a single lost mex is not a trend
// A mex takes well under this to rebuild or upgrade; a base being eaten does not
// recover inside it.
const int   HURT_SUSTAIN   = 40 * SECOND;
int gHurtSince = -1;   // frame our own share first went under the bar, -1 if not
// Both tiers, all three sides; we only ever hold our own side's units, so the
// others contribute zero. T1 first, advanced second -- MexCount indexes on that
// split. Summing the two tiers is NOT by itself enough to make an upgrade
// neutral, because the old unit is destroyed before the new one exists.
array<string> MEX_DEFS = {"armmex", "cormex", "legmex",
                          "armmoho", "cormoho", "legmoho"};
bool  gHurt = false;
float gMexHold = 1.f;   // our own share of peak, published for our allies
uint  gPeakMex = 0;

// Grace period before the role gives up its slot. Election incumbency reads
// RushReady(), which is ENERGY income and flickers with wind, so taking the
// role is immediate but giving it up waits -- otherwise a flickering slot turns
// the whole strategy on and off with it. Costs at most one idle factory line
// for this long if the slot briefly double-holds during a genuine handover.
const int ECO_ROLE_GRACE = 150 * SECOND;
int gEcoSlotSeen = -1000000;

// Build power cap for the eco lead's factory; past it income goes to builders
// instead (mexes, energy, converters, T2/T3). Spaced for the same reason as
// RUSH_CON_SPACING: GetWorkerCount() counts only finished builders, so the cap
// alone cannot hold against Enqueue not deduping.
//
// Split ground vs air, ground falling back: a ground engineer spends most of
// its time walking at this scale, while an air con crosses the same distance
// in seconds and a nano turret doesn't travel at all. Air cons are more
// vulnerable near the front, which doesn't apply here since the eco lead works
// behind its own team.
const uint  ECO_CON_CAP     = 16;   // ground engineers
const int   ECO_CON_SPACING = 10 * SECOND;
const int   ECO_AIR_CON_CAP = 12;
// Enough to unlock the advanced air plant, which is the only durable source of
// fighters. Anything above this is left to the factory ratios.
const int   AIR_CON_MIN     = 1;
const int   ECO_AIR_SPACING = 8 * SECOND;
// The eco lead earns its own aircraft plant once it is clearly the team's bank.
// Not before: a second factory this player cannot yet feed is the "rules that
// spend" trap, and the air plant is only worth it for what it builds.
const float ECO_AIR_PLANT_INCOME = 45.f;
int gNextEcoAirCon = 0;
int gNextEcoCon = 0;
int gNextEcoLog = 0;
int gNextEcoGateLog = 0;

// Late-game fighter screen. Distinct from the Air namespace's surprise bomber
// strike (income/AA gated, may never fire): this is an always-on floor. "Late"
// is time OR fusions/AFUS present, so a fast economy counts as late early.
const int LATE_GAME_FRAME = 25 * MINUTE;
// Garrison size scales with income rather than a flat cap, so a big economy
// keeps a real screen and a small one still gets a few.
const float LATE_FIGHTER_INCOME = 4.f;
const int LATE_FIG_SPACING = 10 * SECOND;
// Income before a player without any air plant builds one purely for this.
const float LATE_AIR_INCOME = 55.f;

// Reactive fallback, separate from the income gate above: that gate stops a
// plant we don't need but says nothing about a threat already visible, so this
// triggers off Military::gAirAvg (observed enemy air) instead of our own
// economy. Above AA_IGNORE (500) to ignore a single air constructor rather
// than a real commitment.
const int   EARLY_AIR_REACT_FRAME = 10 * MINUTE;
const float EARLY_AIR_ENEMY_MIN   = 800.f;
int gNextFighter = 0;

// Vision, not army, at ~175 metal each -- so this is a floor, and it scales
// with the economy like everything else rather than stopping at two.
const float LATE_SCOUT_INCOME = 30.f;
const int LATE_SCOUT_SPACING = 30 * SECOND;
int gNextScout = 0;

}  // namespace Factory
