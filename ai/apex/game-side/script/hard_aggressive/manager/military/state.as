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
const int   POSTURE_SAMPLE  = 20 * SECOND;   // how far back we compare army value
const float LOSING_RATIO    = 0.82f;         // army fell to this share -> turtle
// Resume when the army is back to most of what it had BEFORE the collapse, not
// merely above the last sample -- comparing to the previous sample let it
// resume at a third of its pre-hold strength, straight back into the fight it
// was losing. Capped so a hopeless position does not turtle forever.
const float RECOVER_OF_PEAK = 0.85f;
const int   TURTLE_MAX_HOLD = 6 * MINUTE;
// minAttackers while turtling. Deliberately NOT retuned alongside the AiMakeTask
// change that finally puts it in force -- see the note there. Until then this is
// a number picked when it could not bite, and it is the first thing to measure.
// 400 parked the whole army in DEFEND tasks, which CANNOT target anything
// outside our own influence -- CDefendTask::FindTarget skips every enemy where
// GetAllyDefendInflAt < INFL_EPS. Units only become able to see enemy-territory
// targets after promoting past quota.attack, and FRONT_HOLD_POWER doubles this
// to 800 near the front. Measured across one 8v8: the turtle held for a mean 55%
// of the game, so for over half of it "attack their economy" was not in the
// candidate set at all. apexearth: "we don't attack their economy because we're
// too busy chasing after the little guys attacking our economy."
//
// 96 is 2x MASS_CAP -- hold harder than the strictest massing gate, rather than
// never leave. Survives the 2x front doubling at 192, which a mid-game army can
// actually reach.
// 96 was tried and measured WORSE, 2026-08-08: engagements went 13 -> 113 (the
// army really does leave home now) but army K/D fell 0.49 -> 0.32 and mobile
// losses doubled to 136,986. Un-parking an army that trades badly just feeds it
// faster. Fighting quality has to come first; this leash comes off after.
// 240 is the midpoint -- enough to leave for a real target, not enough to send
// the whole pool out on a bad trade.
const float TURTLE_ATTACK   = 240.f;
const int   TURTLE_MIN_HOLD = 45 * SECOND;   // avoid flapping between postures
// Six-match read: the only game that held at 6 min also teched latest (22.4m)
// and lost, while all three clean wins never held and teched at 15.6-19.6m. An
// 18% army dip at minute 6 is two dead raiders, not a losing position -- holding
// then just stalls the opening.
// 11 minutes was tuned for a TEMPO variant, where an early hold just stalled
// the opening. This variant's plan is the opposite -- let them attack into
// static defence and die there -- so holding early is the intended behaviour,
// not a failure state. It still requires the army to actually be losing value,
// so it cannot fire in a quiet opening.
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
// reaches T2 far sooner than four independent economies would. Observed live:
// a tech-spot commander held 9 mexes at 7 minutes with no factory -- that player
// could have been on T2 already with the team feeding it.
//
// Requires ai.SendResources(), which we added to the script API. The engine
// command (COMMAND_SEND_RESOURCES) always existed; CircuitAI only used it when
// resigning, so a team of AIs had no way to pool anything.
//------------------------------------------------------------------------------
// Measured: the plant is placed ~8 min and takes ~5.5 min to build, so a window
// closing at 12 min cut the feed off half way through the thing it was paying
// for. Cover the construction instead of the run-up to it.
// Deadline for the WHOLE pooling strategy, not just the metal transfers.
// Pooling is a bet: the team runs poor and the lead runs armyless on the promise
// of an early T2. If that has not landed by now the bet has lost, and keeping it
// running only compounds the loss -- so every part of it stops here and play
// reverts to stock. Matches TAKEOVER_UNTIL in dev_team_income.lua.
const int   RUSH_GIVEUP = 15 * MINUTE;
// What a feeder keeps for itself. 220 was far too high: a follower pooling
// behind the lead is SPENDING its income, so its bank hovers near zero and never
// crosses the threshold -- measured, a whole team of seven moved 2,746 metal in
// ten minutes, about 0.65 metal/s each. Keep a small working float instead and
// let the rest go in whatever size it happens to be, 20 and 30 at a time.
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

// "One AI should focus on reaching T2 and expanding eco -- they shouldn't help
// T1 much at all." Suppress the lead's attack formation during the rush so its
// metal goes into economy and tech rather than a T1 army it is not meant to
// field. Defence still builds; this only stops it committing an attack.
// How much T1 the rusher gives up scales with team size. On a 4v4 one player
// contributing nothing is a quarter of the army missing and the team folds
// before the tech lands; on an 8v8 it is an eighth and the tech pays for itself.
const float RUSH_SKIP_T1_BIG   = 400.f;  // large team: effectively no attacking
const float RUSH_SKIP_T1_SMALL = 30.f;   // small team: minimal army, eco first

}  // namespace Military
