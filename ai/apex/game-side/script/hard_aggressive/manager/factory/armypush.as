namespace Factory {

// Army catch-up production when behind. Short: this is the thing we want a
// lot of, and the units are cheap.
// The catch-up push has no budget, and that is what makes it dangerous. It fires
// while LosingGround(), which is nearly always true once behind, so it converts
// the whole economy into army and then loses harder for want of an economy.
//
// Measured after it was pointed at the advanced plant: armbull 33.8% and armanni
// 22.0% of ALL metal -- 56% on army and defence -- against ONE T2 constructor and
// 5 mex upgrades to stock's 15 and 12. The unit choice was right and the spend was
// ruinous. At 3 seconds it was buying 180-metal Stumpies; at the same cadence it
// buys 800-metal Bulldogs.
const int   ARMY_PUSH_SPACING = 12 * SECOND;
// And it stops entirely when the economy behind it is too thin to carry it: an
// army bought by starving the mexes cannot be replaced when it dies.
const float ARMY_PUSH_MIN_INCOME = 30.f;
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

// WHAT A DEFENSIVE POSTURE BUYS.
//
// apexearth: "when we are losing and playing defensively we should stop building
// units like the 'Bull'; in a defensive posture we need to buy long range units
// which can hit enemies from the safety of within our base. Also we need to
// create spam units, cheap T1 units and use them as fodder against the enemy."
//
// Military::gTurtle is the AI's own statement that it is losing the trade and has
// stopped attacking (see military/state.as). While it holds, the army is parked in
// DEFEND tasks inside our own influence -- which is exactly the position an
// assault tank is worst in and artillery is best in. A Bull is 950 metal of
// short-ranged brawler bought to stand still; the ARTY role is 110-920 depending
// on tier and shoots from behind whatever is holding the line.
//
// This is a SUBSTITUTION, not an addition: the factory was going to spend the slot
// on something regardless, so unlike the builder-side rules CLAUDE.md warns about
// it costs no constructor time and displaces no expansion. What it displaces is
// the assault mainstay, which is the point.
//
// Alternating rather than all-artillery: artillery alone dies to anything that
// reaches it. Every other pick is fodder -- the cheap bodies that soak the charge
// while the artillery fires. Fodder() answers per factory and returns null when
// this line's cheapest unit is not actually cheap, so this never buys an
// expensive unit believing it is spam.
const int   TURTLE_MIX_SPACING = 10 * SECOND;
const int   TURTLE_ARTY_EVERY  = 2;   // every other pick is the long-range one
int gNextTurtleMix    = 0;
int gTurtleMixCount   = 0;
int gNextTurtleMixLog = 0;

int gRushLead = -1;   // last PRIMARY lead this instance saw published
bool gAmLead = false;   // this team holds one of the lead slots
bool gT1Reclaimed = false;   // one-shot: we fed our T1 lab into the plant

// ECO LEAD. One player -- the primary tech lead slot -- stops playing the map
// and does nothing but grow an economy, so the team arrives at the late game
// with something to spend there instead of four mid-sized economies that all
// stop at T2. apexearth: "they don't make army unless endangered or our allies
// are dying. they just focus on building up a huge economy."
//
// Big teams only, and for the reason already measured on the tech lead itself:
// on a four-player team one player fielding no army is a quarter of the army
// missing, and the note on the constructor monopoly below records what that
// cost (standing army 17.8k against 25.4k, real K/D 0.70 against 1.24). At
// eight players it is an eighth.
//
// Held for the whole game, not to Military::RUSH_GIVEUP: the point is the LATE
// game, so a role that expires at fifteen minutes is the one part of it that
// cannot pay off.
bool gEcoActive = false;   // this instance is running as the eco lead right now
int  gEcoLoggedFor = -1;   // team we last announced the role for

// "Being taken apart" is measured as EXTRACTORS LOST off this team's own peak.
//
// Metal income was the obvious measure and is the wrong one: apexearth, "they
// can reclaim and get a temporary boost to metal income and then later on it
// falls", which sets a peak nothing can live up to and then reads the return to
// normal as death. Energy income is worse still -- it rises and falls with the
// wind. A standing extractor count moves in one direction for one reason.
//
// Deliberately not Military::LosingGround() either: that compares the enemy's
// army value to OURS, and a player that builds no army reads "losing"
// permanently, so the release would be stuck on from the moment the role began.
// Two bars, because they answer two different questions.
//
// OURS is "we are being pushed off our own ground" -- the eco lead is the player
// least able to fight back, so it reacts early.
//
// An ALLY's is "that player is being killed", and it has to be a much harder bar
// on a big team. Seven allies each with an independent chance of standing a
// couple of mexes below their peak means "any ally at 70%" is true essentially
// all the time, which is what a first 8v8 run showed: the role was elected at
// 7.6 minutes and never once activated.
//
// Both bars are also SUSTAINED rather than instantaneous, and this is the part
// that was wrong. Upgrading a mex destroys the T1 extractor and leaves a
// nanoframe, so the standing count dips for the whole build -- and the eco lead
// upgrades more mexes than anyone (measured, 20 games: 5 against a teammate
// average of 3). The role was therefore tripping its own release on the exact
// behaviour it exists to produce: "losing our own mexes" was the single largest
// cause of standing down, 45 times across those games.
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

// How long the role survives losing its slot.
//
// Measured, 8v8 Comet Catcher at +40%: the primary slot moved team 5 -> lost ->
// 5 -> 3 -> 5 inside two minutes, so the role was taken and dropped four times
// and never ran for longer than six seconds. The election keeps an incumbent
// only while RushReady() holds, and that reads ENERGY income, which rises and
// falls with the wind -- apexearth, "wind energy goes up and down due to wind
// speed". Taking the role is immediate; giving it up waits, so a slot that
// flickers does not turn the whole strategy on and off with it.
//
// Two players can briefly believe they are the eco lead when the slot genuinely
// moves. That costs one idle factory line for this long, against the strategy
// not existing at all, which is what the flapping produced.
// 45s was not enough: across 20 games "role lost" was still the second largest
// cause of standing down, 31 times, behind only the mex dip. The election's
// incumbency test is what flickers, not the player's fitness for the job.
const int ECO_ROLE_GRACE = 150 * SECOND;
int gEcoSlotSeen = -1000000;

// Build power is the one thing the eco lead does buy from its factory. Past
// this it buys nothing at all and the income goes to the builders instead --
// mexes, energy, converters, the T2 and T3 economy.
//
// Spaced for the same reason RUSH_CON_SPACING is: Enqueue does not dedup and
// GetWorkerCount() counts only FINISHED builders, so the cap alone cannot hold.
// BUILD POWER IS THE ECONOMY, and 10 was starving the one player whose whole job
// is to grow.
//
// Measured over 7 sixty-minute games: the eco lead PRODUCED 23% more metal than
// its teammates and BUILT 36% less of it, holding 12 T1 constructors against
// their 28. It banks income it has no capacity to spend, which is why it is also
// the one player that never reaches T3 (1,557 against 22,179). At 30 minutes
// this was invisible -- the margin still looked like +71% metal -- because there
// had not yet been enough income for the ceiling to bind.
//
// A cap this size only binds late, and the spacing is what stops it being
// bought all at once. apexearth's own note: "if above ~50% metal then we can
// keep making construction turrets ... sometimes making ~4 more at a time is
// more efficient."
// Split between ground and AIR, and the ground half deliberately falls back.
// apexearth: "the eco player should try to get more air constructors and more
// nanos, less ground engineers." A ground engineer walks; at the scale this
// player is working at -- 240,000 metal produced in an hour, spread over mexes,
// fusions and a second base -- walking is most of what it does. Air constructors
// cross the same distance in seconds, and a nano turret does not travel at all.
// TODO.md carries the same rule and its caveat: air cons "allow you to scale
// everything much faster ... HOWEVER - air cons are easily shot down near the
// front line", which is survivable for THIS player because it works behind its
// own team.
const uint  ECO_CON_CAP     = 16;   // ground engineers, down from 28
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

// LATE GAME, and a standing fighter screen once it arrives.
//
// apexearth: "make sure we always make air in the late game, even if it's just
// fighters." The Air namespace next door is a different thing entirely -- one
// player, a surprise bomber strike, gated behind income 60 and the enemy's
// anti-air. That is a strategy that may never fire; this is a floor that always
// does, so the team is never simply handed the sky.
//
// TODO.md's own definition of late game: "usually 25 minutes + into the game,
// but you can gauge late game based on if we have things like fusions or afus".
// Both, so a fast economy counts as late early and a slow one still qualifies.
const int LATE_GAME_FRAME = 25 * MINUTE;
// A STANDING GARRISON, SIZED BY THE ECONOMY. Eight was flat, and apexearth has
// asked twice for about thirty fighters over the base -- "no late fighters
// max". One per this much income instead, so a big economy keeps a real
// screen and a small one still gets a few.
const float LATE_FIGHTER_INCOME = 4.f;
const int LATE_FIG_SPACING = 10 * SECOND;
// Income before a player without any air plant builds one purely for this.
const float LATE_AIR_INCOME = 55.f;

// Reactive fallback, separate from the income-gated one above: apexearth,
// watching an 8v8 live, "enemy air is really becoming brutal this game. They
// have two air players... if we see the enemy has air and we do not have any
// air, by ten minutes, we should probably be making an air lab and making
// fighters. At the very least, we need some fighter defense." The income gate
// exists to stop a plant we do not need; it says nothing about a threat we can
// already see, so this triggers off Military::gAirAvg instead of our own
// economy. Above AA_IGNORE (500): a floor meant to ignore a single air
// constructor, not a real commitment worth answering with a plant.
const int   EARLY_AIR_REACT_FRAME = 10 * MINUTE;
const float EARLY_AIR_ENEMY_MIN   = 800.f;
int gNextFighter = 0;

// Vision, not army, at ~175 metal each -- so this is a floor, and it scales
// with the economy like everything else rather than stopping at two.
const float LATE_SCOUT_INCOME = 30.f;
const int LATE_SCOUT_SPACING = 30 * SECOND;
int gNextScout = 0;

}  // namespace Factory
