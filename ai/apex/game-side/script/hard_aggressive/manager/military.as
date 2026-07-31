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
const int   MASS_FROM   = 14 * MINUTE;
const float MASS_START  = 30.f;
const float MASS_PER_MIN = 3.5f;        // ~100 by 28 min
// Was 140. Measured: apex finished on 92k metal against stock's 125k while
// holding a smaller army, which is what happens when the army never leaves home
// -- the enemy takes the map and we hold a wall around too few mexes. The plan
// is capture territory THEN wall it, not wall an empty base. 80 still refuses
// piecemeal trickle attacks while letting a real force move and take ground.
// 80 was set while CDefendTask's promote shortcut made this unenforceable. Now
// that it binds, 80 is not reachable under pressure and the army never attacks.
const float MASS_CAP    = 36.f;
// Now a metal-vs-metal ratio, so 1.0 is a real parity point. It used to compare
// aiEnemyMgr.mobileThreat against armyCost; across eight 4v4 infologs that ratio
// logged 0.02-0.14 and never once approached 0.95, so the clause below could not
// fire and "refuse bad trades" did nothing all game. EnemyArmyCost() sums
// GetEnemyCost over the fighting roles, which is the same unit as armyCost.
const float ATTACK_EDGE = 0.95f;
int gNextMassLog = 0;

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

	// Do not trade into a stronger army. Nothing in the AI compares our force to
	// the enemy's before committing, so it will walk into a losing fight as
	// readily as a winning one -- observed: "we are trying to have our armies go
	// toe to toe with the enemy who is dedicating everything just on aggression".
	// When they out-mass us, demand a bigger mass before moving, which in
	// practice means holding behind the defences and continuing to build while
	// they break themselves on static defence.
	const float ours = aiMilitaryMgr.armyCost;
	const float theirs = EnemyArmyCost();
	if ((ours > 0.f) && (theirs > ours * ATTACK_EDGE)) {
		want = MASS_CAP;   // hold: let them come to the defences instead
	}
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

void UpdatePosture()
{
	// Before UpdateRushRole, which overwrites quota.attack on the lead. Captured
	// after it, this recorded the rusher's own suppressed value as the baseline,
	// so every later "restore" restored 400 (never attack).
	if (gAttackBase < 0.f)
		gAttackBase = aiMilitaryMgr.quota.attack;

	UpdateSling();
	UpdateRushDefence();
	UpdateMassing();
	UpdateRushRole();
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
		aiMilitaryMgr.quota.attack = gAttackBase;
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

CCircuitDef@ BigGun()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(cordoom);
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
	if (!gPorcArmed && !early && !onLine && !IsFrontierSite(pos))
		return;

	// Something to pay with. Unchanged from the old gate, including the way that
	// same opening clause bypassed the income requirement outright.
	if ((ai.frame <= 5 * MINUTE) && (aiEconomyMgr.metal.income <= 10.f)
		&& !early && !onLine)
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
// Ceiling on AA as a share of our own army. response.json's own max_percent.
const float AA_MAX_PCT   = 0.50f;
// AA is sized as a FRACTION OF THEIR AIR IN METAL, not as a fixed count.
//
// apexearth: "if an enemy makes 10 legion heavy air they'll have like almost 40k
// of metal ... you'd need more than [10 heavy AA] to deal with 10 legion heavy
// air attacking in a mass." legfort is 5,600 metal each, so ten is 56,000 -- and
// a flat cap of 6 turrets answered that with 4,920 metal of flak. A count that
// does not scale with their spend cannot be right at both ends of a game.
//
// The divisor is the turret's own cost, read from the def, so this reads as "keep
// AA worth about this fraction of their air".
const float AA_METAL_RATIO = 0.45f;
// Enough to matter the moment air is worth answering at all, since the averaged
// figure lags the raw one.
const int   AA_HEAVY_MIN = 2;
// A runaway guard, not a working limit. It was 6, and 6 was binding constantly.
const int   AA_HEAVY_MAX = 30;

// Air is over-counted and ground under-counted by simple visibility: aircraft
// fly over us constantly, ground sits in fog. Weight ground up, and average both
// so a single overflight does not swing the answer.
const float GROUND_UNSEEN  = 3.0f;
const float AIR_AVG_SECONDS = 240.f;
// Rising air is believed far sooner than it is forgotten.
const float AIR_RISE_SECONDS = 30.f;
// Enemy air builders and scouts are counted as AIR. They cannot be separated
// from ground ones by role, so discount by the most that could plausibly be air.
const float SOFT_AIR_WEIGHT = 0.10f;
// Cap the discount: enemy builders+scouts include ground ones, so an uncapped
// subtraction erases a real bomber fleet. ~7 air constructors' worth.
const float SOFT_AIR_CAP = 2500.f;
float gAirAvg    = -1.f;
float gGroundAvg = -1.f;

// Raising maxThisUnit only PERMITS a turret; nothing was asking for one. Measured
// live: heavy=0/4 -- four wanted, none standing -- because flak sits at index 8 of
// porcupine.land and porcupine.prevent is 1, so an ordinary cluster never walks
// past landDefenders[0]. Builder::AirDefence reads these and actually enqueues.
int gHeavyWant = 0;

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

CCircuitDef@ HeavyAADef()
{
	return (gFlak !is null) ? gFlak : gHeavy;
}

int HeavyAADeficit()
{
	return gHeavyWant - (LiveCount(gFlak) + LiveCount(gHeavy));
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

// AirScale REMOVED. It turned the air figure into a fraction of the enemy army
// and multiplied the AA count by it, which cannot be right: 4,700 metal of
// aircraft needs answering whether or not the same enemy also owns 13,000 metal
// of tanks. What threatens us is how much air there is, not what proportion of
// their army it represents. AA_IGNORE already stops us reacting to a lone scout.
//
// It was also unreachable in practice. GROUND_UNSEEN inflates ground x3 to cover
// what we cannot see while air is DISCOUNTED, so the ratio came out about an
// order of magnitude low -- measured live at share=0.034 where the real air to
// ground ratio was 0.26, against an AA_SHARE_REF of 0.25 that therefore could
// never be met. heavy=0/0 with 4,720 metal of enemy air on the field.

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
		// Rise fast, decay slow. Symmetric smoothing over four minutes meant a real
		// air force took minutes to register, by which time it had already hit us.
		// Losing AA slowly is cheap; noticing air slowly is not.
		const float kUp = 1.f / AIR_RISE_SECONDS;
		const float kDn = 1.f / AIR_AVG_SECONDS;
		gAirAvg += (air - gAirAvg) * ((air > gAirAvg) ? kUp : kDn);
		gGroundAvg += (ground - gGroundAvg) * kDn;
	}

	// Compare like with like: gGroundAvg carries the GROUND_UNSEEN inflation, so
	// undo it here or the ratio is nonsense. Reported only -- nothing sizes off it.
	const float total = gAirAvg + gGroundAvg / GROUND_UNSEEN;
	const float share = (total > 0.f) ? gAirAvg / total : 0.f;
	const bool worth = (gAirAvg >= AA_IGNORE);

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
	const float aaCost = ((gFlak !is null) && (gFlak.costM > 1.f)) ? gFlak.costM : 820.f;
	int heavyWant = 0;
	if (worth) {
		heavyWant = int(gAirAvg * AA_METAL_RATIO / aaCost);
		if (heavyWant < AA_HEAVY_MIN)
			heavyWant = AA_HEAVY_MIN;
		if (heavyWant > AA_HEAVY_MAX)
			heavyWant = AA_HEAVY_MAX;
	}
	gHeavyWant = heavyWant;
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
			+ " heavy=" + heavyHave + "/" + heavyWant);
	}
}

}  // namespace Military
