namespace Military {


//------------------------------------------------------------------------------
// Reactive posture.
//
// Telemetry showed the real failure: from ~10 minutes our real-value K/D sits
// at 0.5 while the opponent holds 1.5-2.3, and we lose roughly double the metal
// per engagement. Stock BARb has no notion of "I am losing trades" -- it keeps
// feeding units into fights it is losing.
//
// So: watch our own army value. If it is shrinking while the enemy fields a
// mobile threat, stop attacking, hold, and let static defence do the trading --
// defences are cheap per unit of damage and cannot be chased down. Resume once
// the army has rebuilt. The aim is to stop donating metal and make the enemy
// feed us instead.
//------------------------------------------------------------------------------
// Metal standing in our own tracked combat units, refreshed each withdraw.as
// pass. aiMilitaryMgr.armyCost read ~40% of what the field telemetry showed
// (2026-08-20: 2054 against armyReal 5500), and every aggression gate that
// trusted it held forever; this is the count of units we can actually walk.
// Declared here because massing.as loads before withdraw.as in the shim.
float gTrackedCost = 0.f;
// Farthest FINISHED rear structure from home, in elmos -- the built base's
// real extent, fed to the C++ base-defence ring (main.as AiUnitFinished
// grows it; frontline.as applies it through SetBaseDefRange).
float gBaseExtent = 0.f;

// The lane the army masses on (posture.as maintains it; massing.as reads it
// for the local-odds override, and include order forces the declaration here).
AIFloat3 gLaneAt;

const int   POSTURE_SAMPLE  = 20 * SECOND;   // how far back we compare army value
const float LOSING_RATIO    = 0.82f;         // army fell to this share -> turtle
// Resume when the army is back to most of what it had BEFORE the collapse, not
// merely above the last sample -- comparing to the previous sample let it
// resume at a third of its pre-hold strength, straight back into the fight it
// was losing. Capped so a hopeless position does not turtle forever.
const float RECOVER_OF_PEAK = 0.85f;
const int   TURTLE_MAX_HOLD = 6 * MINUTE;
// minAttackers while turtling. A DEFEND task cannot target anything outside
// our own influence (CDefendTask::FindTarget skips every enemy where
// GetAllyDefendInflAt < INFL_EPS), so at 400 the whole army was parked unable
// to see enemy-territory targets at all; a value that removes that parking but
// is too low just feeds a badly-trading army faster (measured: 96 raised
// engagements 13 -> 113 but army K/D fell 0.49 -> 0.32). 240 is the midpoint --
// enough to leave for a real target, not enough to send the whole pool out on
// a bad trade.
const float TURTLE_ATTACK   = 240.f;
const int   TURTLE_MIN_HOLD = 45 * SECOND;   // avoid flapping between postures
// This variant's plan is to let the enemy attack into static defence and die
// there, so holding early is intended, not a failure state -- it still
// requires the army to actually be losing value, so it cannot fire in a quiet
// opening.
const int   TURTLE_EARLIEST = 5 * MINUTE;

bool  gTurtle        = false;
float gAttackBase    = -1.f;
float gArmyThen      = 0.f;
int   gNextSample    = 0;
int   gPostureUntil  = 0;
int   gTurtleCount   = 0;
float gArmyAtHold    = 0.f;
int   gTurtleStarted = 0;


//------------------------------------------------------------------------------
// Slinging: pool the team's spare metal behind ONE designated player so it
// reaches T2 far sooner than four independent economies would.
//
// Requires ai.SendResources(), which we added to the script API. The engine
// command (COMMAND_SEND_RESOURCES) always existed; CircuitAI only used it when
// resigning, so a team of AIs had no way to pool anything.
//------------------------------------------------------------------------------
// Deadline for the WHOLE pooling strategy, not just the metal transfers.
// Pooling is a bet: the team runs poor and the lead runs armyless on the
// promise of an early T2. If that has not landed by now the bet has lost, and
// keeping it running only compounds the loss -- so every part of it stops here
// and play reverts to stock. Matches TAKEOVER_UNTIL in dev_team_income.lua.
const int   RUSH_GIVEUP = 15 * MINUTE;
// What a feeder keeps for itself. A follower pooling behind the lead is
// SPENDING its own income, so its bank hovers near zero and rarely crosses a
// high threshold -- keep a small working float instead and let the rest go in
// whatever size it happens to be.
const float SLING_KEEP  = 40.f;
const int   SLING_FROM  = 5 * MINUTE;    // nothing worth pooling before this
// Cap per transfer, not a minimum. The old comment argued for big lumps so the
// lead did not fritter them on T1 -- that no longer applies, the rush branch
// idles the lead's army production outright.
const float SLING_LUMP  = 450.f;
const float SLING_FLOOD_FRAC = 0.5f;     // above this share of storage, send it all
int gSlingNext = 0;
float gSlingTotal = 0.f;
int gSlingSent = 0;
int gRushLoggedFor = -1;   // team we last announced ourselves rusher for

// Suppress the lead's attack formation during the rush so its metal goes into
// economy and tech rather than a T1 army it is not meant to field. Defence
// still builds; this only stops it committing an attack.
// How much T1 the rusher gives up scales with team size. On a 4v4 one player
// contributing nothing is a quarter of the army missing and the team folds
// before the tech lands; on an 8v8 it is an eighth and the tech pays for itself.
const float RUSH_SKIP_T1_BIG   = 400.f;  // large team: effectively no attacking
const float RUSH_SKIP_T1_SMALL = 30.f;   // small team: minimal army, eco first

}  // namespace Military
