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
const float TURTLE_ATTACK   = 400.f;         // minAttackers while turtling
const int   TURTLE_MIN_HOLD = 45 * SECOND;   // avoid flapping between postures
// Six-match read: the only game that held at 6 min also teched latest (22.4m)
// and lost, while all three clean wins never held and teched at 15.6-19.6m. An
// 18% army dip at minute 6 is two dead raiders, not a losing position -- holding
// then just stalls the opening.
const int   TURTLE_EARLIEST = 11 * MINUTE;

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
const int   SLING_UNTIL = 20 * MINUTE;
const float SLING_KEEP  = 220.f;         // early banks are small; keep little
const int   SLING_FROM  = 5 * MINUTE;    // nothing worth pooling before this
const float SLING_LUMP  = 450.f;         // enough to pay for the lead's T2 constructor
int gSlingNext = 0;
int gSlingBlocked = 0;
int gSlingSent = 0;
bool gRushLogged = false;

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

void UpdateRushDefence()
{
	if ((ai.frame < SLING_FROM) || (ai.frame > SLING_UNTIL))
		return;
	if (ai.teamId == Factory::RushLeadTeamId())
		return;          // the lead is handled by UpdateRushRole
	if (gTurtle)
		return;          // an active turtle hold is stricter; do not loosen it
	if (aiMilitaryMgr.quota.attack < RUSH_TEAM_DEFEND)
		aiMilitaryMgr.quota.attack = RUSH_TEAM_DEFEND;
}

void UpdateRushRole()
{
	if (ai.frame > SLING_UNTIL)
		return;
	if (ai.teamId != Factory::RushLeadTeamId())
		return;
	if (!gRushLogged) {
		gRushLogged = true;
		AiLog("apex: designated T2 rusher -- skipping T1 army until " + (SLING_UNTIL / MINUTE) + "m");
	}
	aiMilitaryMgr.quota.attack = RushAttackQuota();
}

void UpdateSling()
{
	// Nothing to pool in the first half-minute, and the engine has not settled
	// team ids that early either.
	if ((ai.frame < SLING_FROM) || (ai.frame > SLING_UNTIL) || (ai.frame < gSlingNext))
		return;
	gSlingNext = ai.frame + 10 * SECOND;

	if (Builder::gGotAdvCon)
		return;   // we already got our advanced con; the pooling is done
	const int lead = Factory::RushLeadTeamId();
	if (lead == ai.teamId)
		return;                        // the lead is the one being fed

	if (lead < 0)
		return;

	// Do not feed someone who is already banking metal -- that is just moving
	// waste around. Only sling while the lead is actually spending everything.
	// ai.GetTeamMetalFill() reports 1.0 unconditionally: the engine does not
	// expose another team's storage to us, so the C++ fallback read "unknown" as
	// "full" and withheld every single transfer -- slinging never once fired in
	// any test tonight. Observed live: it logged fill=1 while the lead sat under
	// half metal. Drop the dependency; the feeder already only gives away what
	// it holds above SLING_KEEP, so it cannot starve itself.
	const float spare = aiEconomyMgr.metal.current - SLING_KEEP;
	if (spare <= 0.f)
		return;
	// Hand over a lump big enough to actually buy the T2 constructor rather
	// than dribbling small amounts that get spent on T1.
	const float amount = (spare < SLING_LUMP) ? spare : SLING_LUMP;
	ai.SendResources(amount, 0.f, lead);
	if (gSlingSent++ % 8 == 0)
		AiLog("apex: sent " + amount + " metal to lead " + lead);
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
const int   MASS_FROM   = 8 * MINUTE;   // before this, early aggression is fine
const float MASS_START  = 30.f;
const float MASS_PER_MIN = 3.5f;        // ~100 by 28 min
const float MASS_CAP    = 140.f;

void UpdateMassing()
{
	if (gTurtle || (ai.frame < MASS_FROM))
		return;   // an active hold is stricter; do not loosen it
	if (ai.teamId == Factory::RushLeadTeamId() && !Factory::gHaveT2)
		return;   // the rusher has its own quota while teching

	const float mins = float(ai.frame - MASS_FROM) / float(MINUTE);
	float want = MASS_START + mins * MASS_PER_MIN;
	if (want > MASS_CAP)
		want = MASS_CAP;
	if (aiMilitaryMgr.quota.attack < want)
		aiMilitaryMgr.quota.attack = want;
}

void UpdatePosture()
{
	UpdateSling();
	UpdateRushDefence();
	UpdateMassing();
	UpdateRushRole();
	Commander::UpdateCaution();
	if (gAttackBase < 0.f)
		gAttackBase = aiMilitaryMgr.quota.attack;

	if (ai.frame < gNextSample)
		return;
	gNextSample = ai.frame + POSTURE_SAMPLE;

	const float army = aiMilitaryMgr.armyCost;
	const float prev = gArmyThen;
	gArmyThen = army;

	if ((prev <= 0.f) || (ai.frame < gPostureUntil) || (ai.frame < TURTLE_EARLIEST))
		return;

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
			AiLog("apexturtle: HOLD #" + gTurtleCount + " frame=" + ai.frame
				+ " army " + prev + " -> " + army);
		}
	} else if ((army >= gArmyAtHold * RECOVER_OF_PEAK)
			|| (ai.frame - gTurtleStarted > TURTLE_MAX_HOLD)) {
		gTurtle = false;
		gPostureUntil = ai.frame + TURTLE_MIN_HOLD;
		aiMilitaryMgr.quota.attack = gAttackBase;
		AiLog("apexturtle: RESUME frame=" + ai.frame + " army=" + army
			+ " (held from " + gArmyAtHold + ")");
	}
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
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

float EnemyArmyFloor()
{
	// A refused query is "unknown", never "no enemies" -- reading a refusal as a
	// meaningful zero is what silently disabled slinging once already.
	const int teams = ai.GetEnemyTeamSize();
	return PORC_THREAT_PER_ENEMY * float((teams > 0) ? teams : 1);
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
		AiLog("apex: porc " + (gPorcArmed ? "ON" : "OFF") + " frame=" + ai.frame
			+ " mobileThreat=" + formatFloat(threat, "", 0, 1)
			+ "/" + formatFloat(armyFloor, "", 0, 1)
			+ " enemies=" + ai.GetEnemyTeamSize());
	}

	// Something to defend against. Frontier sites skip this test, and so does the
	// opening: before either side has an army a single known raider still justifies
	// one tower, which is what the old gate's `mobileThreat > 0` clause bought.
	const bool early = (ai.frame <= 5 * MINUTE) && (threat > 0.f);
	if (!gPorcArmed && !early && !IsFrontierSite(pos))
		return;

	// Something to pay with. Unchanged from the old gate, including the way that
	// same opening clause bypassed the income requirement outright.
	if ((ai.frame <= 5 * MINUTE) && (aiEconomyMgr.metal.income <= 10.f) && !early)
		return;

	aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
}

/*
 * anti-air threat threshold;
 * air factories will stop production when AA threat exceeds
 */
// FIXME: Remove/replace, deprecated.
bool AiIsAirValid()
{
	return aiEnemyMgr.GetEnemyThreat(Unit::Role::AA.type) <= 999999.f;
}

}  // namespace Military
