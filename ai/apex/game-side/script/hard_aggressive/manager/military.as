#include "../../define.as"
#include "../../unit.as"


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
const float TURTLE_ATTACK   = 400.f;
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

float RushAttackQuota()
{
	array<Id>@ mates = ai.GetTeamIds();
	const uint size = (mates is null) ? 1 : mates.length();
	return (size >= 6) ? RUSH_SKIP_T1_BIG : RUSH_SKIP_T1_SMALL;
}

// While the team is paying for one player's tech, everyone else is deliberately
// poorer than the enemy and should not be picking fights on those terms. Hold,
// let static defence do the trading, and stall until the T2 lands -- then the
// tech advantage decides the game instead of a T1 fight we funded ourselves out
// of. Followers only; the rusher has its own, stricter quota.
//
// Deliberately not the full turtle value (400 = never attack). Sitting entirely
// passive hands the enemy the map, and the map is where the reclaim is. This is
// "defend and stall", not "do nothing".
const float RUSH_TEAM_DEFEND = 60.f;

bool gRushDefenceHeld = false;

void UpdateRushDefence()
{
	if (ai.frame > RUSH_GIVEUP) {
		// Hand the follower quota back too, or "give up on the strategy" leaves
		// everyone still holding its passive value. Only if nothing else has
		// since claimed the field -- a turtle hold or a massing target outranks
		// this and must not be clobbered.
		if (gRushDefenceHeld) {
			gRushDefenceHeld = false;
			if ((aiMilitaryMgr.quota.attack == RUSH_TEAM_DEFEND) && (gAttackBase >= 0.f)) {
				aiMilitaryMgr.quota.attack = gAttackBase;
				AiLog(Factory::T() + "apex: rush over, attack quota -> " + gAttackBase);
			}
		}
		return;
	}
	if (ai.frame < SLING_FROM)
		return;
	if (Factory::IsDesignatedLead())
		return;          // the lead is handled by UpdateRushRole
	if (gTurtle)
		return;          // an active turtle hold is stricter; do not loosen it
	if (aiMilitaryMgr.quota.attack < RUSH_TEAM_DEFEND) {
		aiMilitaryMgr.quota.attack = RUSH_TEAM_DEFEND;
		gRushDefenceHeld = true;
	}
}

// Set while we hold the rusher's attack quota, so it can be handed back.
bool gRushQuotaHeld = false;

void UpdateRushRole()
{
	// Past the deadline this must still run, to hand the quota back. Returning
	// early instead left the lead pinned at RushAttackQuota() -- 400, i.e. never
	// attack -- for the entire rest of the game.
	if ((ai.frame > RUSH_GIVEUP) || !Factory::IsDesignatedLead()) {
		// The role can move -- before the election lands this falls back to the
		// engine's pick, usually a different team. quota.attack was assigned and
		// never undone, so a team that was briefly the rusher kept the
		// do-not-attack quota all game (measured: lowest army on its team by 4x).
		if (gRushQuotaHeld) {
			gRushQuotaHeld = false;
			// Back to the stock value, not RUSH_TEAM_DEFEND: past the deadline
			// there is no strategy left to defend, and before it UpdateRushDefence
			// re-raises a follower to 60 on its own.
			aiMilitaryMgr.quota.attack = (gAttackBase >= 0.f) ? gAttackBase : RUSH_TEAM_DEFEND;
			AiLog(Factory::T() + "apex: rusher role released, attack quota -> "
				+ aiMilitaryMgr.quota.attack);
		}
		return;
	}
	if (gRushLoggedFor != ai.teamId) {
		gRushLoggedFor = ai.teamId;
		AiLog(Factory::T() + "apex: designated T2 rusher -- skipping T1 army until " + (RUSH_GIVEUP / MINUTE) + "m");
	}
	gRushQuotaHeld = true;
	aiMilitaryMgr.quota.attack = RushAttackQuota();
}

// The eco lead as the team's bank.
//
// apexearth: "if allies are hurting or we see our army losing it could share
// metal to teammates. It can also share a fus or afus to help them." This is the
// other half of the role -- it is measurably the richest player on the team
// (+59% metal produced over its teammates) and the one least able to use metal
// in a hurry, so when someone else is in trouble the metal is worth more in
// their hands than banked in ours.
//
// Deliberately keyed on IsEcoLead(), NOT EcoLeadActive(): an ally dying is one
// of the conditions that STANDS THE ROLE DOWN, so gating aid on the role being
// active would mean it could never pay out at exactly the moment it should.
const int   ECO_AID_PERIOD  = 5 * SECOND;
const float ECO_AID_KEEP    = 0.25f;    // share of storage kept as working float
const float ECO_AID_LUMP    = 1000.f;   // cap per transfer
const int   ECO_FUSION_GAP  = 2 * MINUTE;
int gNextEcoAid = 0;
int gNextEcoFusion = 0;
float gEcoAidTotal = 0.f;

void UpdateEcoAid()
{
	if (!Factory::IsEcoLead() || (ai.frame < gNextEcoAid))
		return;

	const int dying = Factory::NeediestAlly();
	const bool pressed = (dying >= 0) || gTurtle || LosingGround();
	if (!pressed)
		return;
	gNextEcoAid = ai.frame + ECO_AID_PERIOD;

	const int to = (dying >= 0) ? dying : Factory::LowestHoldAlly();
	if (to < 0)
		return;

	// A reactor outlives any amount of metal, so it goes first -- but only to
	// someone actually being killed, and never down to our own last two.
	if ((dying >= 0) && (ai.frame >= gNextEcoFusion)) {
		if (Builder::GiveFusion(dying))
			gNextEcoFusion = ai.frame + ECO_FUSION_GAP;
	}

	const float spare = aiEconomyMgr.metal.current
		- (aiEconomyMgr.metal.storage * ECO_AID_KEEP);
	if (spare <= 0.f)
		return;
	const float amount = (spare < ECO_AID_LUMP) ? spare : ECO_AID_LUMP;
	ai.SendResources(amount, 0.f, to);
	gEcoAidTotal += amount;
	if (gEcoAidTotal < amount + 1.f)   // first payment only
		AiLog(Factory::T() + "apex: eco lead aiding team " + to
			+ (dying >= 0 ? " (dying)" : " (team under pressure)"));
}

// Set while we hold the ECO lead's attack quota, so it can be handed back.
bool gEcoQuotaHeld = false;

// The eco lead keeps whatever army it has at home for the whole game.
//
// UpdateRushRole hands its quota back at RUSH_GIVEUP, which is right for a tech
// rush -- the bet has either landed or lost by then. The eco role is a bet on
// the LATE game, so expiring at fifteen minutes would remove it exactly where it
// was meant to pay. Runs after UpdateRushRole so it wins on the frames both
// apply, and after UpdateMassing, which only ever raises the quota.
void UpdateEcoRole()
{
	if (!Factory::EcoLeadActive()) {
		if (gEcoQuotaHeld) {
			gEcoQuotaHeld = false;
			// Not while turtling: the hold set 400 for its own reasons and
			// restoring the baseline here would quietly cancel it.
			if (!gTurtle) {
				aiMilitaryMgr.quota.attack = (gAttackBase >= 0.f) ? gAttackBase : RUSH_TEAM_DEFEND;
				AiLog(Factory::T() + "apex: eco lead released, attack quota -> "
					+ aiMilitaryMgr.quota.attack);
			}
		}
		return;
	}
	gEcoQuotaHeld = true;
	aiMilitaryMgr.quota.attack = RUSH_SKIP_T1_BIG;
}

void UpdateSling()
{
	// Nothing to pool in the first half-minute, and the engine has not settled
	// team ids that early either.
	if ((ai.frame < SLING_FROM) || (ai.frame > RUSH_GIVEUP) || (ai.frame < gSlingNext))
		return;
	// Small amounts need a short period or the trickle is worthless: at 20-30
	// metal a transfer, ten seconds apart is 2-3 metal/s.
	gSlingNext = ai.frame + 3 * SECOND;

	if (Builder::gGotAdvCon)
		return;   // we already got our advanced con; the pooling is done
	if (!Factory::LeadIsDesignated())
		return;   // nobody has earned the role yet -- do not feed the fallback
	const int lead = Factory::RushLeadTeamId();
	if (lead == ai.teamId)
		return;                        // the lead is the one being fed

	if (lead < 0)
		return;

	// Stop once the plant we were funding exists. The window used to run to a
	// flat RUSH_GIVEUP clock, so donations continued long after the thing they
	// paid for was standing.
	if (Factory::LeadHasPlant(lead))
		return;

	// Stop while the lead is at cap. Measured 2026-08-02: ~269,000 metal went
	// into a lead whose bank sat above storage from minute 8 -- every point of
	// it wasted, while the givers ran empty and stopped expanding.
	if (Factory::LeadIsSaturated(lead))
		return;

	// Do not feed someone who is already banking metal -- that is just moving
	// waste around. Only sling while the lead is actually spending everything.
	// ai.GetTeamMetalFill() reports 1.0 unconditionally: the engine does not
	// expose another team's storage to us, so the C++ fallback read "unknown" as
	// "full" and withheld every single transfer -- slinging never once fired in
	// any test tonight. Observed live: it logged fill=1 while the lead sat under
	// half metal. Drop the dependency; the feeder already only gives away what
	// it holds above SLING_KEEP, so it cannot starve itself.
	// Over half full while the lead is still paying for its plant: that metal is
	// doing nothing, and the lead is the only thing the team is waiting on. Send
	// the whole excess instead of trickling a lump -- observed live, a follower
	// sat on a full bank at 9 min while the plant crawled to 75%.
	const float store = aiEconomyMgr.metal.storage;
	const float flood = store * SLING_FLOOD_FRAC;
	float amount = 0.f;
	if ((store > 0.f) && (aiEconomyMgr.metal.current > flood)) {
		amount = aiEconomyMgr.metal.current - flood;
	} else {
		const float spare = aiEconomyMgr.metal.current - SLING_KEEP;
		if (spare <= 0.f)
			return;
		// Otherwise a lump big enough to buy the T2 constructor, rather than
		// dribbling amounts that get spent on T1.
		amount = (spare < SLING_LUMP) ? spare : SLING_LUMP;
	}
	ai.SendResources(amount, 0.f, lead);
	gSlingTotal += amount;
	if (gSlingSent++ % 40 == 0)
		AiLog(Factory::T() + "apex: sent " + formatFloat(amount, "", 0, 0)
			+ " to lead " + lead + " (total " + formatFloat(gSlingTotal, "", 0, 0) + ")");
}

// Attack in a mass, not a trickle.
//
// quota.attack is a MINIMUM: the AI will not launch until it has that much
// army. Stock sits low, so it attacks with whatever happens to be to hand and
// feeds units into fights piecemeal -- which is exactly how an army gets ground
// down without ever threatening anything. apexearth: "store up an army until
// it's a really nice size and then attack with a big mass".
//
// The threshold grows with the game rather than being one number: a 12-unit
// push is a real threat at 8 minutes and an irrelevance at 25, when the enemy
// fields T2 and T3. Growing it also means the accumulated mass keeps pace with
// what it has to break through.
//
// Direction matters and is already measured: lowering minAttackers 15 -> 6 was
// catastrophic (0-10). This moves the other way.
// Timeline of eleven LOST games, sampled every 2 game-minutes: apex and stock
// are level on army and metal through minute 8, then diverge hard -- army 10.4k
// vs 15.9k at ten minutes, 9.9k vs 22.4k at fourteen. And apex's army PEAKS
// at minute 4 and declines from there (11.8k -> 9.9k -> 7.0k) while stock's
// grows continuously. We stop replacing losses exactly as the T2 transition
// begins, and never recover.
//
// Massing started at 8 minutes, precisely where the divergence begins: holding
// units back during the transition, when the army is already shrinking, compounds
// it. Push it past the transition so the force is rebuilt first and massed after.
// How much army we insist on before committing, driven by the armies on the
// field rather than by a clock.
//
// apexearth: "can you make massing based on how large the armies are? doesn't
// seem like it should be a time based thing. In fact, usually doing things by
// time is wrong." The clock version started at 14 minutes; measured 2026-08-02,
// apex and stock are indistinguishable through minute 4 and apex collapses at
// minute 6, so the gate arrived eight minutes after the bleeding started. Its
// first sample read "army=820 enemyArmy=11973 ratio=14.60".
//
// UNITS. quota.attack is CAttackTask's minPower, in the engine's power units.
// armyCost and EnemyArmyCost() are metal. Observed together in one line:
// want=48, army=820, enemyArmy=11973 -- three different scales. They must never
// be assigned or compared across. Only the RATIO theirs/ours is dimensionless,
// so that is the sole bridge used here; the output stays in quota units and
// inside the range below that is already known to work.
const float MASS_FLOOR  = 30.f;   // even when ahead, never trickle 2-3 units
// Ratio at or above which we stop attacking and let them come to the defences.
const float MASS_HOLD_RATIO = 1.5f;
const float MASS_CAP    = 48.f;
// Now a metal-vs-metal ratio, so 1.0 is a real parity point. It used to compare
// aiEnemyMgr.mobileThreat against armyCost; across eight 4v4 infologs that ratio
// logged 0.02-0.14 and never once approached 0.95, so the clause below could not
// fire and "refuse bad trades" did nothing all game. EnemyArmyCost() sums
// GetEnemyCost over the fighting roles, which is the same unit as armyCost.
const float ATTACK_EDGE = 0.95f;
int gNextMassLog = 0;

// The size a group commits at, from the armies on the field.
//
// CDefendTask is created with maxPower = minAttackers and stops accepting units
// once it reaches it, then promotes to an attack and leaves. So this number IS
// the size each group leaves at -- not a threshold it grows past.
float MassWant()
{
	const float ours = TeamArmyCost();
	const float theirs = EnemyArmyCost();
	if (ours <= 1.f)
		return MASS_CAP;
	const float ratio = theirs / ours;
	if (ratio <= ATTACK_EDGE)
		return MASS_FLOOR;                    // ahead: move, but as a group
	if (ratio >= MASS_HOLD_RATIO)
		return MASS_CAP;                      // outmatched: hold
	const float t = (ratio - ATTACK_EDGE) / (MASS_HOLD_RATIO - ATTACK_EDGE);
	return MASS_FLOOR + t * (MASS_CAP - MASS_FLOOR);
}

void UpdateMassing()
{
	// The killing blow owns the quota once it is on: massing is what was holding
	// the win up, so re-raising the minimum here would undo it every tick.
	if (gKilling)
		return;
	if (gTurtle)
		return;   // an active hold is stricter; do not loosen it
	if (ai.teamId == Factory::RushLeadTeamId() && !Factory::gHaveT2)
		return;   // the rusher has its own quota while teching

	// No army of our own is the 2v6 case: demand a full mass rather than let
	// the first two units that exist wander out and die.
	//
	// TEAM against team. aiMilitaryMgr.armyCost is THIS player's army while
	// EnemyArmyCost() sums every enemy, so comparing them on a 4v4 is one
	// player against four and reads ~4x too pessimistic -- measured, the ratio
	// never fell below 1.5 all game and the quota sat pinned at MASS_CAP, i.e.
	// permanently holding. TeamArmyCost() sums the ally side over TV_ARMY, the
	// same figure the killing blow already compares on.
	const float ours = TeamArmyCost();
	const float theirs = EnemyArmyCost();
	const float want = MassWant();

	if (ai.frame >= gNextMassLog) {
		gNextMassLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: mass want=" + formatFloat(want, "", 0, 0)
			+ " army=" + formatFloat(ours, "", 0, 0)
			+ " enemyArmy=" + formatFloat(theirs, "", 0, 0)
			+ " ratio=" + formatFloat((ours > 0.f) ? theirs / ours : 0.f, "", 0, 2));
	}
	if (aiMilitaryMgr.quota.attack < want)
		aiMilitaryMgr.quota.attack = want;
}

//------------------------------------------------------------------------------
// KILLING BLOW.
//
// apexearth: "we are often winning but we're very slow to kill enemies ... we
// need some sort of switch which says ok now go for the killing blow."
//
// Measured, 30 games across 8 maps: 20 of them (67%) hit the time limit
// undecided, and on Quicksilver we finished 16 games holding 4.5x stock's metal,
// 35x its T3 and 8.5x its army while ELEVEN went unresolved. Dominance that does
// not convert is worth nothing -- a timed-out game is not a win.
//
// The cause is the massing rule doing its job too well. quota.attack is a
// MINIMUM number of attackers before the engine will form an attack, and
// UpdateMassing walks it up to MASS_CAP and pins it at MASS_CAP outright
// whenever the enemy out-values us. Once we are far ahead that gate is pure
// delay: we hold an army several times their size and keep waiting for a bigger
// one.
//
// So: when we are clearly winning, stop waiting. Drop the minimum so attacks
// form continuously and release the turtle if it is holding.
//
// Lowering minAttackers globally is known to be catastrophic -- 15 -> 6 scored
// 0-10. This is not that. It is
// conditional on holding KILL_EDGE times the enemy's army value, where even a
// partial commitment outnumbers everything they can field.
// 2.5x was too strict to be useful. Measured: it first became true at 36.8
// minutes of a 50-minute game -- teamArmy 44,497 against 17,783 -- which is long
// past the point where a push has time to finish anything. The whole complaint
// is that we win slowly, so a switch that only flips once the win is already
// overwhelming does not address it. 1.8x is still a commanding lead.
const int   KILL_FROM  = 15 * MINUTE;   // not before the T2 transition settles
const float KILL_EDGE  = 1.8f;          // OUR TEAM's army value against theirs
const float KILL_FLOOR = 20000.f;       // ignore ratios off a tiny enemy sample
const float KILL_QUOTA = 10.f;          // attack with what we have, repeatedly
bool gKilling = false;

// Our whole side's army value, pooled over the same blackboard the tech lead
// election uses.
//
// This has to be TEAM against TEAM. aiMilitaryMgr.armyCost is one player's army
// while EnemyArmyCost() sums the entire enemy side, so comparing them directly
// asks "is one of us worth more than all eight of them" -- measured in the first
// smoke run at army 11,525 against enemyArmy 41,903, a ratio of 3.6 AGAINST us
// in a game we were dominating. The gate was unreachable by construction, the
// same way LosingGround() is permanently TRUE for a player with no army.
const string TV_ARMY = "army";

float TeamArmyCost()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return aiMilitaryMgr.armyCost;
	float total = 0.f;
	for (uint i = 0; i < mates.length(); ++i)
		total += ai.ReadTeamValue(int(mates[i]), TV_ARMY, 0.f);
	return total;
}

bool KillingBlow()
{
	if (ai.frame < KILL_FROM)
		return false;
	const float ours = TeamArmyCost();
	const float theirs = EnemyArmyCost();
	if (ours < KILL_FLOOR)
		return false;
	// Hysteresis, so a single lost engagement does not flip us back to massing
	// half way through the push that is winning the game.
	return gKilling ? (ours > theirs * (KILL_EDGE * 0.6f))
	                : (ours > theirs * KILL_EDGE);
}

void UpdateKillingBlow()
{
	ai.PublishTeamValue(TV_ARMY, aiMilitaryMgr.armyCost);
	const bool now = KillingBlow();
	if (now == gKilling)
		return;
	gKilling = now;
	AiLog(Factory::T() + "apex: KILLING BLOW " + (now ? "ON" : "off")
		+ " teamArmy=" + formatFloat(TeamArmyCost(), "", 0, 0)
		+ " enemyArmy=" + formatFloat(EnemyArmyCost(), "", 0, 0));
}


//------------------------------------------------------------------------------
// Base defence scaled to the threat closing in.
//
// apexearth: "scan outside the range of that base for the total threat. And if
// that value exceeds your base by some percentage, then you multiply the amount
// of porc you're willing to make."
//
// This cannot be done by asking DefaultMakeDefence for more. `prevent` is a hard
// cap -- num = min(isPorc ? defenders.size() : prevent, defenders.size()) -- and
// its per-point cost accumulator makes a repeat call walk PAST what is already
// paid for rather than add to it. So the extra towers are enqueued here.
//
// Threat is sampled on a ring OUTSIDE the base, which is the "getting closer and
// closer over four or five minutes" signal: an army massing at our doorstep
// registers on the ring long before it is inside.
//------------------------------------------------------------------------------
// FRONT-LINE AREA DEFENCE.
//
// A mechanism of its own, deliberately -- not a tweak to porcupine.prevent.
// apexearth: "I think that prevent is the wrong mechanism to tweak here. We
// need a new mechanism, that area defense, front line defense sort of thing."
// prevent applies at every cluster equally and cannot express "the front", so
// raising it walled quiet rear mexes. It is back at 2 and this owns the heavy
// defence instead.
//
// Towers are laid ACROSS the approach, not stacked on one point: offsets step
// out alternately either side of the front position, perpendicular to the
// home->enemy axis, so they form a line facing the enemy rather than a pile.
// That is the buildable approximation of apexearth's territory-grid idea while
// CInfluenceMap remains unreachable from script (see notes #12).
//
// Enemy army value against our standing towers.
//
// apexearth: "scan outside the range of that base for the total threat. And if
// that value exceeds your base by some percentage, then you multiply the amount
// of porc you're willing to make."
//
// The positional form of that was tried first and does not work. Two reasons,
// both measured:
//   - CThreatMap::GetBuilderThreatAt bounds-checks with an assert only, compiled
//     out in release, then indexes surfThreat unchecked. Sampling a ring of
//     radius 1500 around a base near the map edge read off-map memory and
//     crashed the AI at frame 3 (0xc0000005). No map-size binding exists to
//     clamp against.
//   - Sampling only positions provably inside the map (interpolations along
//     home->enemy) does not crash, but returns ZERO almost always. The same
//     query was already measured at 3% nonzero across ten games and is the
//     reason the old commander-threat retreat never fired.
//
// So the comparison keeps apexearth's shape -- their strength against ours,
// scaled -- using the enemy army value, which is a real number in these logs
// (120 to 6,648 over one game) rather than a mostly-empty map lookup.
// 2.0, not 1.5. First measurement with mDefence: static defence was 14.1% of
// our metal against stock's 5.7%, while army was 26.2% against 30.7%.
// apexearth: "the side effect is wasteful defense and then we have less army
// and are losing the overall fight." Fire only when clearly outmatched.
const float PORC_TRIGGER    = 2.0f;
const int   PORC_ADD_SPACING = 20 * SECOND;
const uint  PORC_ADD_CAP    = 2;    // was 10, then 4; see PORC_TRIGGER
// The front is the contested area; allow a real position there, not a pair.
const uint  PORC_FRONT_FENCE = 4;
// Spacing between towers along the line.
const float PORC_LINE_STEP  = 320.f;
uint gPorcAdded = 0;
int  gNextPorcAdd = 0;

float ApproachThreat()
{
	return EnemyArmyCost();
}

array<string> PORC_NAMES_ARM = {"armllt", "armbeamer", "armhlt", "armclaw"};
array<string> PORC_NAMES_COR = {"corllt", "corhllt", "corhlt", "cormaw"};
array<string> PORC_NAMES_LEG = {"leglht", "legmg", "legdtr"};

array<string>@ PorcNames()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return @PORC_NAMES_COR;
	if (side == "legion")
		return @PORC_NAMES_LEG;
	return @PORC_NAMES_ARM;
}

float OurTowerValue()
{
	array<string>@ names = PorcNames();
	float total = 0.f;
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if (d !is null)
			total += d.costM * float(d.count);
	}
	return total;
}

// A basic laser tower is outranged by the raiders it is meant to stop, so it
// dies without ever firing; the next tower up reaches past them. The floor
// exists because the seconds-of-income budget alone lands between the two.
const float PORC_MIN_BUDGET = 200.f;

// The heaviest tower we can currently afford to place.
CCircuitDef@ PorcToBuild()
{
	array<string>@ names = PorcNames();
	const float paced = aiEconomyMgr.metal.income * 30.f;
	const float budget = (paced > PORC_MIN_BUDGET) ? paced : PORC_MIN_BUDGET;
	CCircuitDef@ best = null;
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		if (d.costM > budget)
			continue;              // do not stall the economy on one tower
		if ((best is null) || (d.costM > best.costM))
			@best = d;
	}
	return best;
}

void UpdateBaseDefence()
{
	if (!Builder::gHomeSet || (gPorcAdded >= PORC_ADD_CAP))
		return;
	if (ai.frame < gNextPorcAdd)
		return;

	const float threat = ApproachThreat();
	if (threat <= 0.f)
		return;
	const float ours = OurTowerValue();
	if (threat < (ours + 1.f) * PORC_TRIGGER)
		return;

	CCircuitDef@ def = PorcToBuild();
	if (def is null)
		return;

	// AT THE FRONT, not at home. apexearth: "I often see our AI making defenses
	// in the back of the map... what we really need are defenses closer to the
	// front line, which are gonna kill the enemy and turn our fights around."
	// Same reasoning UpdateFrontGun already applies to the big gun.
	//
	// FrontPos is the team front, published at 78% of the way to the enemy. It
	// comes from dev_team_income.lua, so it is absent in a hosted game -- fall
	// back to two thirds of the way along our own home->enemy line, which is
	// forward of the base without needing the gadget.
	AIFloat3 spot;
	bool haveFront = FrontPos(spot);
	if (!haveFront) {
		AIFloat3 toEnemy = aiEnemyMgr.GetEnemyPos() - Builder::gHomePos;
		const float len = sqrt(toEnemy.x * toEnemy.x + toEnemy.z * toEnemy.z);
		spot = Builder::gHomePos;
		if (len > 1.f) {
			spot.x += toEnemy.x / len * (len * 0.66f);
			spot.z += toEnemy.z / len * (len * 0.66f);
		}
	}
	// Step across the front rather than piling up: alternate sides, widening.
	// Perpendicular to the axis we face the enemy along.
	AIFloat3 axis = aiEnemyMgr.GetEnemyPos() - Builder::gHomePos;
	const float alen = sqrt(axis.x * axis.x + axis.z * axis.z);
	if (alen > 1.f) {
		const int step = int(gPorcAdded) + 1;
		const float side = ((step % 2) == 0) ? 1.f : -1.f;
		const float outw = float((step + 1) / 2) * PORC_LINE_STEP;
		spot.x += (-axis.z / alen) * outw * side;
		spot.z += ( axis.x / alen) * outw * side;
	}

	// Do not stack them, but the front is by definition the contested area, so
	// it earns a higher bar than a quiet mex would.
	if (!Builder::AreaNeedsDefence(spot, PORC_FRONT_FENCE))
		return;

	IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::HIGH, def, spot, SQUARE_SIZE * 24));
	if (t !is null) {
		++gPorcAdded;
		gNextPorcAdd = ai.frame + PORC_ADD_SPACING;
		AiLog(Factory::T() + "apex: porc+ " + def.GetName() + " #" + gPorcAdded
			+ " at-front enemyArmy=" + formatFloat(threat, "", 0, 0)
			+ " ourTowers=" + formatFloat(ours, "", 0, 0));
	}
}


// No suicide runs while the army IS the defence.
//
// apexearth: "really early in the game, you don't wanna be doing suicide runs.
// Imagine you do a suicide run that fails, and then your army is half size, and
// you fed all that metal or resurrection ability to the enemy. Bam. Now you're
// fucked." A deep strike that trades units for their economy is a good deal
// LATER, when losses are replaceable -- and this AI's whole plan is to make the
// enemy pay by dying on our defences and leaving wrecks, so handing them ours is
// the same mistake in reverse.
//
// raid.min is the maxPower of the Defend task raiders sit in before it promotes
// (MilitaryManager.cpp:1696), i.e. the size a raid group leaves at. Raising it
// keeps them home massing instead of trickling out.
//
// Reached via quota.raid.min, NOT the quotaRaidMin shorthand: that shorthand is
// registered in the current C++ source but is absent from the deployed
// SkirmishAI.dll, which predates it. Source is not the binary.
//
// Keyed on OWNING T2, not on a clock -- apexearth: "usually doing things by time
// is wrong". Before the advanced plant the army is the entire defence and every
// loss is a large share of it; after, there is economy behind it to replace
// what a strike costs.
const float RAID_MIN_EARLY = 45.f;   // hold them home
float gRaidMinStock = -1.f;

void UpdateRaidCaution()
{
	if (gRaidMinStock < 0.f)
		gRaidMinStock = aiMilitaryMgr.quota.raid.min;   // capture before overwriting
	const float want = Factory::gHaveT2 ? gRaidMinStock : RAID_MIN_EARLY;
	if (aiMilitaryMgr.quota.raid.min != want)
		aiMilitaryMgr.quota.raid.min = want;
}

void UpdatePosture()
{
	// Before UpdateRushRole, which overwrites quota.attack on the lead. Captured
	// after it, this recorded the rusher's own suppressed value as the baseline,
	// so every later "restore" restored 400 (never attack).
	if (gAttackBase < 0.f)
		gAttackBase = aiMilitaryMgr.quota.attack;

	UpdateKillingBlow();
	UpdateRaidCaution();
	UpdateBaseDefence();
	UpdateSling();
	UpdateRushDefence();
	UpdateMassing();
	UpdateRushRole();
	UpdateEcoRole();
	UpdateEcoAid();
	// After massing and both role rules, so it is the last word on the quota.
	// Not for the eco lead: it holds almost no army by design, and sending that
	// at a base is throwing it away rather than ending anything.
	if (gKilling && !Factory::EcoLeadActive()) {
		aiMilitaryMgr.quota.attack = KILL_QUOTA;
		if (gTurtle) {
			gTurtle = false;
			gPostureUntil = ai.frame;
			AiLog(Factory::T() + "apex: killing blow releases the hold");
		}
	}
	UpdateFrontGun();
	UpdateAirThreat();
	Commander::UpdateCaution();
	// DISABLED. Exit-code audit: aborts (exit -1003) jumped from 0-2 per 20-game
	// run to 14-17 the moment this landed, and stayed there. The engine is dying,
	// not stalemating -- which means the "3-1, commanders solved" reading was
	// drawn from the handful of games that survived, and the 82% I reported as
	// mutual turtling was 82% aborted. Either CmdMoveTo issued outside a task
	// context or GetEnemyCostAt's GetEnemyUnitsIn walk is unsafe here.
	// Builder::UpdateCommanderSafety();
	if (ai.frame < gNextSample)
		return;
	gNextSample = ai.frame + POSTURE_SAMPLE;

	const float army = aiMilitaryMgr.armyCost;
	const float prev = gArmyThen;
	gArmyThen = army;

	if ((prev <= 0.f) || (ai.frame < gPostureUntil) || (ai.frame < TURTLE_EARLIEST))
		return;

	if (gKilling)
		return;   // committed: a dip mid-push is not a reason to stop pushing

	if (!gTurtle) {
		// Shrinking army while the enemy still has a mobile force means we are
		// losing the trade, not merely between waves.
		if ((army < prev * LOSING_RATIO) && (aiEnemyMgr.mobileThreat > 0.f)) {
			gTurtle = true;
			++gTurtleCount;
			gArmyAtHold = prev;          // strength to rebuild back to
			gTurtleStarted = ai.frame;
			gPostureUntil = ai.frame + TURTLE_MIN_HOLD;
			aiMilitaryMgr.quota.attack = TURTLE_ATTACK;
			AiLog(Factory::T() + "apexturtle: HOLD #" + gTurtleCount + " frame=" + ai.frame
				+ " army " + prev + " -> " + army);
		}
	} else if ((army >= gArmyAtHold * RECOVER_OF_PEAK)
			|| (ai.frame - gTurtleStarted > TURTLE_MAX_HOLD)) {
		gTurtle = false;
		gPostureUntil = ai.frame + TURTLE_MIN_HOLD;
		// NOT gAttackBase. That is the stock 15, captured before anything
		// touched it, and the turtle block runs AFTER UpdateMassing in
		// UpdatePosture -- so every resume slammed the commit size back to
		// stock and the next group left at stock size. Measured 15 hold/resume
		// cycles in one game, i.e. fifteen small groups walking out.
		aiMilitaryMgr.quota.attack = MassWant();
		AiLog(Factory::T() + "apexturtle: RESUME frame=" + ai.frame + " army=" + army
			+ " (held from " + gArmyAtHold + ")");
	}
}

//------------------------------------------------------------------------------
// Why raising quota.attack never produced a mass.
//
// A unit that should mass is parked in a DEFEND task that promotes to ATTACK.
// CDefendTask::Update promotes on
//     (attackPower >= maxPower) || !GetTasks(check).empty()
// and DefaultMakeTask builds that task with check == ATTACK. So the moment one
// attack task exists anywhere, every DEFEND task hands its units over on its
// next tick holding one unit or twenty -- the quota is bypassed by the second
// clause, and no value of it can close the gap. That is the trickle.
//
// TaskF::Defend's three-argument form lets us choose `check`. MELEE is a
// declared FightType that nothing in CircuitAI ever enqueues, so GetTasks(MELEE)
// is permanently empty and promotion is left with only the mass test.
//
// The power passed here is superseded within 5s: UpdateDefenceTasks rewrites
// maxPower to max(minAttackers, PreMaxGroupThreat) for every DEFEND task that
// promotes to ATTACK, which is the value DefaultMakeTask would have used.
//------------------------------------------------------------------------------

// Fodder is exempt. apexearth: "we don't care about grouping these up ... they
// are fodder." Holding a 21-metal Tick back to build a mass buys nothing; its
// job is vision and pulled fire, and both only happen forward. Cost AND role,
// so a cheap AA or bomber is not swept in: the units meant here are Tick
// (armflea 21), Rascal (corfav 26), Wheelie (legscout 25), Rover (armfav 31),
// Grunt (corak 42) and Pawn (armpw 54).
const float FODDER_COST = 100.f;

bool IsFodder(const CCircuitDef@ cdef)
{
	return (cdef !is null) && (cdef.costM < FODDER_COST)
		&& cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::RAIDER.mask);
}

// True for the units DefaultMakeTask would route into Defend(ATTACK, ...).
// That is its default branch -- every role absent from its role->fight-type map,
// which is assault, skirmish and the custom roles bound to assault -- plus riot
// when no guard task can take the unit. Everything else keeps stock routing.
bool WantsMassing(const CCircuitDef@ cdef)
{
	if (cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::SUPPORT.mask))
		return false;
	const Type role = ai.GetBindedRole(cdef.GetMainRole());
	if (role == RT::RIOT)
		return aiMilitaryMgr.GetGuardTaskNum() == 0;
	return (role != RT::RAIDER) && (role != RT::ARTY) && (role != RT::AA)
		&& (role != RT::AH) && (role != RT::BOMBER) && (role != RT::MINE)
		&& (role != RT::SUPER) && (role != RT::SCOUT) && (role != RT::SUPPORT);
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	const CCircuitDef@ cdef = unit.circuitDef;
	// Returning null leaves the unit in the idle task -- ITaskModule::AssignTask
	// does nothing when MakeTask gives it nothing, and CIdleTask::Start is a
	// no-op. The unit keeps no orders and stays where it was built. That is how
	// the air force is held at home until Air::Release().
	if (Air::HoldsUnit(unit))
		return null;
	if (IsFodder(cdef)) {
		// Scouts already get an ungrouped SCOUT task from stock. Raiders are
		// first parked in Defend(RAID, quota.raid[0]); skip straight past that.
		if (cdef.IsRoleAny(Unit::Role::RAIDER.mask))
			return aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::RAID));
		return aiMilitaryMgr.DefaultMakeTask(unit);
	}
	if (WantsMassing(cdef)) {
		return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
				Task::FightType::ATTACK, aiMilitaryMgr.quota.attack));
	}
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

// Where our own defences stand.
//
// Nothing in the ~405 bindings enumerates friendly units or asks "what is
// defended here", so the only way to answer that is to accumulate it from the
// events. MilitaryManager's fenceFinished/fenceDestroyed handlers call
// UnitAdded/UnitRemoved with UseAs::FENCE for every defence structure we own,
// whatever placed it -- build_chain porcupine clusters, DefaultMakeDefence, or
// Builder::Fortify -- so this register sees all of them, not just ours.
//
// FENCE fires on FINISHED, not on placement. A tower under construction is
// therefore invisible here; Builder::Fortify counts its own outstanding orders
// separately for that reason.
array<int>      gFenceId;
array<AIFloat3> gFencePos;

uint FenceCountNear(const AIFloat3& in pos, float radius)
{
	uint n = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (gFencePos[i].distance2D(pos) <= radius)
			++n;
	}
	return n;
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage != Unit::UseAs::FENCE)
		return;
	gFenceId.insertLast(unit.id);
	gFencePos.insertLast(unit.GetPos(ai.frame));
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage != Unit::UseAs::FENCE)
		return;
	const int id = unit.id;
	for (uint i = 0; i < gFenceId.length(); ++i) {
		if (gFenceId[i] == id) {
			gFenceId.removeAt(i);
			gFencePos.removeAt(i);
			return;
		}
	}
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

//------------------------------------------------------------------------------
// Defence gating.
//
// First, what is not available. Checked against CircuitAI's script/*.cpp:
// CThreatMap is registered but exposes only ApplyRange(), CInfluenceMap is not
// registered at all, CMetalManager is not registered so the `cluster` argument
// cannot be resolved into anything, and CEnemyManager exposes four global scalars
// -- GetEnemyPos() and GetEnemyGroups() exist in C++ and are not bound. There is
// no way to ask "how close is the enemy to this position" from AngelScript.
// mobileThreat is a whole-map sum over every known enemy mobile unit; using it as
// a stand-in for proximity would be the same class of error as reading
// GetTeamMetalFill() == 1 as "the lead is rich".
//
// Second, what the C++ underneath already does. DefaultMakeDefence bails on ally
// zones, raises a cluster to the full defender list when two neighbouring
// clusters read hot on the threat map or when our influence at the site is zero,
// caps spend at amountFactor * min(avg metal income, avg energy income) * eco
// factor, only adds AA once enemy air cost is nonzero, and orients the towers
// along GetEnemyPos(). The positional judgement
// exists -- it sits one level below this hook. So the hook's real job is deciding
// whether to ask at all, and its honest inputs for that are global.
//
// Hence: ask once the enemy actually fields an army, and skip while it does not,
// which is the user's "if enemies are really far away then probably not needed
// right away". Sites outside our own footprint bypass that gate; see below for
// why that is a proxy rather than proximity.
//------------------------------------------------------------------------------
// behaviour.json sets quota.attack = 15 -- the group threat at which BARb itself
// rates a force worth attacking. Read that as one enemy player's worth of fielded
// army and scale it by the number of enemy teams, because mobileThreat sums the
// whole enemy team: an unscaled constant is met by one scouting wave in an 8v8
// and by a genuine push in a 1v1, which is backwards.
const float PORC_THREAT_PER_ENEMY = 15.f;
// Deadband on the way back down. Without it the gate flips every time a raider
// dies and porc tasks get enqueued and aborted in alternation.
const float PORC_RELEASE = 0.8f;

// DefaultMakeDefence calls a cluster front-line when it sits further than 1000
// elmos from GetBasePos(). That accessor is not bound, so approximate the base
// with the mean of the sites this hook is handed in the opening: those are metal
// clusters we own or have queued, so early on their mean is our own ground.
//
// Be clear about what this measures -- distance from OUR mass, not distance to
// the enemy. It is a proxy and it can be wrong on a map where we expand away from
// the fight. It is therefore only ever allowed to let defence through, never to
// suppress it, so a bad reading costs metal and not a base.
const int   PORC_ANCHOR_UNTIL = 4 * MINUTE;
const float PORC_FRONTIER     = 1000.f;

float gAnchorX   = 0.f;
float gAnchorZ   = 0.f;
int   gAnchorN   = 0;
bool  gPorcArmed = false;

void NoteDefenceSite(const AIFloat3& in pos)
{
	if ((gAnchorN > 0) && (ai.frame > PORC_ANCHOR_UNTIL))
		return;
	gAnchorX += pos.x;
	gAnchorZ += pos.z;
	++gAnchorN;
}

bool IsFrontierSite(const AIFloat3& in pos)
{
	if (gAnchorN == 0)
		return false;
	const float n = float(gAnchorN);
	const float dx = pos.x - gAnchorX / n;
	const float dz = pos.z - gAnchorZ / n;
	return (dx * dx + dz * dz) > (PORC_FRONTIER * PORC_FRONTIER);
}

// What the enemy's mobile army is WORTH, in metal.
//
// Not mobileThreat: UpdateMassing's own comment already warns that threat and
// armyCost are different units, and it is right -- observed army=10727 against
// enemyThr=296, so a threat-vs-metal comparison reads "we are ahead" almost
// always and any gate built on it never fires. GetEnemyCost returns
// enemyInfos[type].cost, a metal sum, which is directly comparable to armyCost
// (accumulated from GetCostM). Summed over the roles that actually fight.
float EnemyArmyCost()
{
	return aiEnemyMgr.GetEnemyCost(Unit::Role::ASSAULT.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::RAIDER.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::RIOT.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::SKIRM.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::ARTY.type)
	     + aiEnemyMgr.GetEnemyCost(Unit::Role::AH.type);
}

// Behind on the field: they field more army value than we do.
const float BEHIND_RATIO = 1.0f;

bool LosingGround()
{
	return EnemyArmyCost() > aiMilitaryMgr.armyCost * BEHIND_RATIO;
}

float EnemyArmyFloor()
{
	// A refused query is "unknown", never "no enemies" -- reading a refusal as a
	// meaningful zero is what silently disabled slinging once already.
	const int teams = ai.GetEnemyTeamSize();
	return PORC_THREAT_PER_ENEMY * float((teams > 0) ? teams : 1);
}

// The team front, published by dev_team_income.lua at 78% of the way from our
// own centroid to the enemy's.
bool FrontPos(AIFloat3& out p)
{
	const float x = ai.GetGameRulesParam("ai_frontx_" + ai.teamId, -1.f);
	const float z = ai.GetGameRulesParam("ai_frontz_" + ai.teamId, -1.f);
	if ((x < 0.f) || (z < 0.f))
		return false;
	p = AIFloat3(x, 0.f, z);
	return true;
}

string armanni("armanni");
string cordoom("cordoom");
string legbastion("legbastion");

CCircuitDef@ BigGun()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(cordoom);
	if (side == "legion")
		return ai.GetCircuitDef(legbastion);
	return ai.GetCircuitDef(armanni);
}

// The big gun used to hang off the T3 gantry's build chain, so it was placed
// beside whichever base owned the gantry -- a back-line player walling its own
// empty base while the front player got nothing. Same unit, same trigger, but
// put it where the fighting is.
const float BIGGUN_INCOME = 18.f;
bool gBigGunPlaced = false;

void UpdateFrontGun()
{
	if (gBigGunPlaced || !Factory::gHaveT3)
		return;
	if (aiEconomyMgr.metal.income <= BIGGUN_INCOME)
		return;
	CCircuitDef@ gun = BigGun();
	if (gun is null)
		return;
	AIFloat3 front;
	if (!FrontPos(front))
		return;
	gBigGunPlaced = true;
	AiLog(Factory::T() + "apex: big gun " + gun.GetName() + " at the team front");
	// BUNKER takes only a def and a position -- no target, no spot id.
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::BUNKER,
			Task::Priority::NORMAL, gun, front, 0.f));
}

// Is this cluster on the team's defence line? IsFrontierSite only measures
// distance from OUR OWN mass, which says nothing about where the fighting is.
// The published front does.
const float FRONT_RADIUS = 1600.f;

bool NearFront(const AIFloat3& in pos)
{
	AIFloat3 f;
	if (!FrontPos(f))
		return false;
	const float dx = pos.x - f.x;
	const float dz = pos.z - f.z;
	return (dx * dx + dz * dz) < (FRONT_RADIUS * FRONT_RADIUS);
}

void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	NoteDefenceSite(pos);

	if (gTurtle) {
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);  // porc hard while holding
		return;
	}

	const float armyFloor = EnemyArmyFloor();
	const float threat = aiEnemyMgr.mobileThreat;
	if (gPorcArmed ? (threat < armyFloor * PORC_RELEASE) : (threat >= armyFloor)) {
		gPorcArmed = !gPorcArmed;
		AiLog(Factory::T() + "apex: porc " + (gPorcArmed ? "ON" : "OFF") + " frame=" + ai.frame
			+ " mobileThreat=" + formatFloat(threat, "", 0, 1)
			+ "/" + formatFloat(armyFloor, "", 0, 1)
			+ " enemies=" + ai.GetEnemyTeamSize());
	}

	// Something to defend against. Frontier sites skip this test, and so does the
	// opening: before either side has an army a single known raider still justifies
	// one tower, which is what the old gate's `mobileThreat > 0` clause bought.
	// A site on the team's defence line is worth building whatever the global
	// threat gate says: that is where the attacks land, and a tower there that
	// arrives late is a tower that arrives never. apexearth: "treat defenses
	// more important, at least when they're at that team defense area in the
	// middle".
	// The tech lead's job is narrow: get the plant up, make advanced cons, make
	// T2 mexes, then keep scaling economy. apexearth: "they shouldn't even really
	// be building too many defenses unless they are feeling threatened -- focus
	// on eco and the T2". Every tower it builds is metal the team pooled for tech
	// spent on something else. Threat still overrides: staying alive is the one
	// early job it does have.
	if (Factory::IsDesignatedLead() && !gPorcArmed && !gTurtle && !LosingGround())
		return;

	const bool onLine = NearFront(pos);

	const bool early = (ai.frame <= 5 * MINUTE) && (threat > 0.f);
	// A BACK-LINE cluster needs more than "the enemy owns an army somewhere".
	// gPorcArmed is global and trips as early as 2.3 min, so on its own it let
	// every quiet rear mex through and they got walled while the front had
	// nothing. apexearth: "too much defenses being spent in the back line when
	// they could have been made up front to support the front line."
	//
	// Front and frontier sites are unchanged -- that is where the fighting is.
	//
	// LosingGround() used to open this gate too, which made every rear cluster on
	// the map eligible the moment we fell behind. Being behind is precisely when
	// build power must go to army instead, and the border is already covered by
	// the two clauses above, so it no longer bypasses the rear guard.
	if (!onLine && !IsFrontierSite(pos) && !early)
		return;

	// Something to pay with. Unchanged from the old gate, including the way that
	// same opening clause bypassed the income requirement outright.
	if ((ai.frame <= 5 * MINUTE) && (aiEconomyMgr.metal.income <= 10.f)
		&& !early && !onLine)
		return;

	// A front-line cluster still needs an enemy army to be worth walling. On a
	// small map almost every cluster reads as on-line, so `onLine` alone approved
	// the whole map and DefaultMakeDefence put a tower on every defence point.
	// Measured over five tournaments: static defence 15.5-21% of our metal
	// against stock's 7-8.4%, and halving our own front-tower rule
	// (PORC_ADD_CAP 4 -> 2) moved it 16.4% -> 16.8%, i.e. not at all -- the spend
	// is this call, not ours.
	if (!gPorcArmed && !gTurtle && !LosingGround() && !early)
		return;

	aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
}

//------------------------------------------------------------------------------
// Anti-air, sized to the enemy's actual ground-vs-air mix.
//
// Static and mobile AA are counted separately and need separate levers: only
// mobile units reach CMilitaryManager::AddResponse, so the response table's
// figures are mobile-only. Static AA is bounded through CCircuitDef::maxThisUnit,
// which IsAvailable() gates on in every path that can place one -- build chain
// hubs, DefaultMakeDefence, base defence, factory. Neither lever exists in
// build_chain.json, whose conditions are sampled once when the parent finishes
// and never re-checked.
//
// GetEnemyCost(AIR) is not "enemy aircraft". Air constructors and scouts carry
// ["builder", "air"] / ["scout", "air"] in behaviour.json, and CFactoryManager
// gives the AIR enemy role to every def that IsAbleToFly. Two enemy air
// constructors read as 680 metal of "air".
//------------------------------------------------------------------------------
// Enemy air value below which we build no AA at all beyond the cheap tiers.
// One Armada air constructor is 340 metal, one Cortex 360.
const float AA_IGNORE    = 500.f;
// Air share at which we answer their air at full stock strength. Below it, scale
// down; scale is never above 1, so this only ever builds less AA than stock.
const float AA_SHARE_REF = 0.25f;
const float AA_SCALE_MIN = 0.10f;
// Ceiling on AA as a share of our own army. response.json's own max_percent.
const float AA_MAX_PCT   = 0.50f;
// Enemy air metal, scaled, that buys one heavy AA turret (armflak/armcir
// 820/750, corflak/corerad 850/800, legflak 820).
const float AA_HEAVY_PER = 1500.f;
const int   AA_HEAVY_MAX = 6;

// Air is over-counted and ground under-counted by simple visibility: aircraft
// fly over us constantly, ground sits in fog. Weight ground up, and average both
// so a single overflight does not swing the answer.
const float GROUND_UNSEEN  = 3.0f;
const float AIR_AVG_SECONDS = 240.f;
// Enemy air builders and scouts are counted as AIR. They cannot be separated
// from ground ones by role, so discount by the most that could plausibly be air.
const float SOFT_AIR_WEIGHT = 0.10f;
// Cap the discount: enemy builders+scouts include ground ones, so an uncapped
// subtraction erases a real bomber fleet. ~7 air constructors' worth.
const float SOFT_AIR_CAP = 2500.f;
float gAirAvg    = -1.f;
float gGroundAvg = -1.f;

int  gNextAirLog   = 0;
bool gAAResolved   = false;
CCircuitDef@ gFlak = null;   // the faction's flak turret
CCircuitDef@ gHeavy = null;  // its other heavy static AA

void ResolveHeavyAA()
{
	if (gAAResolved)
		return;
	gAAResolved = true;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		@gFlak = ai.GetCircuitDef("corflak");  @gHeavy = ai.GetCircuitDef("corerad");
	} else if (side == "legion") {
		// leglupara is Legion's counterpart to armcir/corerad but is also its
		// superweapon entry, and DiceBigGun only re-rolls when a big gun finishes:
		// capping a def it had already picked would deny Legion any superweapon.
		@gFlak = ai.GetCircuitDef("legflak");
	} else {
		@gFlak = ai.GetCircuitDef("armflak");  @gHeavy = ai.GetCircuitDef("armcir");
	}
}

// Deliberately wider than EnemyArmyCost(), which omits HEAVY: leaving enemy T3
// out of the denominator inflates the air share exactly in the late game.
float EnemyGroundCost()
{
	return EnemyArmyCost() + aiEnemyMgr.GetEnemyCost(RT::HEAVY);
}

int LiveCount(CCircuitDef@ def)
{
	return (def is null) ? 0 : def.count;
}

void CapHeavyAA(CCircuitDef@ def, int spare)
{
	if (def !is null)
		def.maxThisUnit = def.count + spare;
}

// How seriously to take their air, 0..1. One number, used by both levers.
float AirScale(float share)
{
	float s = share / AA_SHARE_REF;
	if (s > 1.f)
		s = 1.f;
	if (s < AA_SCALE_MIN)
		s = AA_SCALE_MIN;
	return s;
}

void UpdateAirThreat()
{
	ResolveHeavyAA();

	const float airRaw = aiEnemyMgr.GetEnemyCost(RT::AIR);
	const float soft = aiEnemyMgr.GetEnemyCost(Unit::Role::BUILDER.type)
	                 + aiEnemyMgr.GetEnemyCost(Unit::Role::SCOUT.type);
	float softAir = (airRaw < soft) ? airRaw : soft;
	if (softAir > SOFT_AIR_CAP)
		softAir = SOFT_AIR_CAP;
	float air = airRaw - softAir * (1.f - SOFT_AIR_WEIGHT);
	if (air < 0.f)
		air = 0.f;
	const float ground = EnemyGroundCost() * GROUND_UNSEEN;

	if (gAirAvg < 0.f) {
		gAirAvg = air;
		gGroundAvg = ground;
	} else {
		const float k = 1.f / AIR_AVG_SECONDS;
		gAirAvg += (air - gAirAvg) * k;
		gGroundAvg += (ground - gGroundAvg) * k;
	}

	const float total = gAirAvg + gGroundAvg;
	const float share = (total > 0.f) ? gAirAvg / total : 0.f;
	const bool worth = (gAirAvg >= AA_IGNORE);
	const float scale = worth ? AirScale(share) : 0.f;

	// factor is the divisor in RoleProbability's first gate: AA is built while
	// enemyAir * ratio >= aaCost * factor, so aaCost tops out at
	// ratio/factor * enemyAir. That gate, not maxPercent, is what binds while the
	// enemy's air is small -- and it counts their air constructors as air.
	// The mobile-AA lever does not exist. GetResponseInfo/SResponseInfo are not
	// registered on CMilitaryManager -- only DefaultMakeTask, Enqueue,
	// EnqueueRetreat, DefaultMakeDefence and GetGuardTaskNum are. response.json's
	// anti_air weighting is therefore unreachable from script and needs a binding
	// before it can be scaled. Static AA below is real.

	// count includes nanoframes, so a turret still building holds its own slot.
	int heavyWant = int(gAirAvg * scale / AA_HEAVY_PER);
	if (heavyWant > AA_HEAVY_MAX)
		heavyWant = AA_HEAVY_MAX;
	const int heavyHave = LiveCount(gFlak) + LiveCount(gHeavy);
	const int spare = (heavyWant > heavyHave) ? (heavyWant - heavyHave) : 0;
	CapHeavyAA(gFlak, spare);
	CapHeavyAA(gHeavy, spare);

	if (ai.frame >= gNextAirLog) {
		gNextAirLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apexaa: airRaw=" + formatFloat(airRaw, "", 0, 0)
			+ " air=" + formatFloat(gAirAvg, "", 0, 0)
			+ " ground=" + formatFloat(gGroundAvg, "", 0, 0)
			+ " share=" + formatFloat(share, "", 0, 3)
			+ " scale=" + formatFloat(scale, "", 0, 2)
			+ " heavy=" + heavyHave + "/" + heavyWant);
	}
}

}  // namespace Military
