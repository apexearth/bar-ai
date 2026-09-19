namespace Builder {

// CBuilderManager::EnqueueRetreat (BuilderManager.cpp) always `new
// CRetreatTask(this)` -- no dedup against an existing one, unlike every
// IBuilderTask path this codebase re-elects through (Requests::Take joins an
// in-flight request by SITE; retreat has no such join). Every call site here
// used to call it fresh on each re-election on the assumption that
// re-enqueuing an existing retreat was a cheap no-op -- it is not: a fresh
// CRetreatTask means a fresh AssignTo/RemoveAssignee pair on the SAME unit,
// which tears down and rebuilds the travel action and toggles fire state
// (AssignTo sets RETURN for a cloak-capable unit; RemoveAssignee restores the
// def's default OPEN) every re-election, roughly once a second, for as long
// as the flee condition holds. apexearth, watching a commander under
// continuous real threat the whole match (enemy influence 1.4-38 for eleven
// straight minutes, never near zero): "swapping between fire at will and
// return fire, idk what else they're thinking about... standing around doing
// nothing." The commander was correctly told to flee every time -- it just
// never got to finish leaving.
int gNextRetireLog = 0;

IUnitTask@ Retreat(CCircuitUnit@ unit)
{
	IUnitTask@ held = unit.task;
	if ((held !is null) && (held.GetType() == Task::Type::RETREAT))
		return held;
	// CRetreatTask HEALS, it does not reposition: its Update() Recovers
	// (tears down) any assignee reading >98% health on the first update,
	// before the first step -- for a healthy unit the retreat is a silent
	// no-op and it stays exactly where it was told to leave. Send the
	// healthy home by patrol instead: real movement, and a patrolling
	// builder still repairs and reclaims whatever it passes.
	if (unit.GetHealthPercent() > 0.98f) {
		if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::PATROL))
		{
			return held;
		}
		const AIFloat3 rear = Market::RetirePos();
		// A PATROL TO THE TILE YOU ARE STANDING ON IS NOT A RETREAT. Measured
		// 2026-09-07: the commander walked to the nano farm, and every patrol
		// issued afterwards had that farm as its destination -- 57 elmos away,
		// inside his own build reach. He held a LOW-priority builder task, out
		// of the market, frozen on one tile for 12,300 frames (5:20 to 12:10),
		// re-issuing the same zero-length patrol every 20 seconds. Nothing was
		// wrong with the patrol; there was nowhere to go. Returning null
		// re-elects him onto the farm's own work instead of parking him on it,
		// and his build reach is the honest measure of "already there" -- at
		// that distance he can work the site he is standing beside.
		if (OnMap(rear)
			&& (unit.GetPos(ai.frame).distance2D(rear)
				<= unit.circuitDef.GetBuildDistance()))
		{
			return null;
		}
		if (OnMap(rear)) {
			IUnitTask@ pt = aiBuilderMgr.Enqueue(TaskB::Patrol(
					Task::Priority::LOW, rear, 20 * SECOND));
			if (pt !is null) {
				if (ai.frame >= gNextRetireLog) {
					gNextRetireLog = ai.frame + 20 * SECOND;
					AiLog("apex: retire t=" + ai.teamId + " "
						+ unit.circuitDef.GetName() + " #" + unit.id
						+ " -> patrol home");
				}
				return pt;
			}
		}
	}
	return aiBuilderMgr.EnqueueRetreat();
}

// How many of ONE factory def (standing + under construction, this player's
// own count -- CCircuitDef is per-instance) is enough. Past this, refuse the
// engine's own DefaultMakeTask offer of another one. Deliberately generous
// rather than tuned tight: a strong economy legitimately wants more than one
// bot lab to parallelize production.
//
// Derived from income rather than fixed: a player on 400 metal/second and a
// player on 40 do not want the same number of plants. A full bank does NOT
// raise this: at low income a full bank means the one plant we have is not
// being fed or run -- a build-power problem the con/nano/assist rules already
// answer -- and the old flat +2 here let a starved 13 m/s player sanction a
// second lab off exactly that signal. apexearth, watching, 2026-08-15: "We
// couldn't even fully support 1 -- so why would we make a second?"
const float FACTORY_PER_INCOME  = 60.f;

int FactoryTypeCap()
{
	return 1 + int(aiEconomyMgr.metal.income / FACTORY_PER_INCOME);
}

// The count cap alone does not close the race that causes the overshoot:
// CCircuitDef.count only increments once a builder's nanolathe actually
// STARTS the structure, so several idle constructors evaluated inside that
// walk-to-site window can all read the same under-cap count and all get
// granted a build in turn. Same per-def spacing-gate pattern
// gRezzerDefs/REZ_SPACING already use elsewhere in this file for the
// identical class of race.
const int FACTORY_REQUEST_SPACING = 30 * SECOND;
array<int> gNextFactoryRequest(ai.GetDefCount() + 1);

int gConRefused = 0;
int gConAbandoned = 0;
int gConRerouted = 0;
int gConDefended = 0;
int gNextConVetoLog = 0;
int gNextRerouteLog = 0;
int gNextDefenceLog = 0;

// ai.GetBuilderThreatAt is the BUILDER-role SURFACE layer, and AddEnemyUnit
// routes HasSurfToAir enemies into the air layer, so a pure AA turret adds
// nothing to it -- an air constructor cannot see what kills it. GetUnitThreatAt
// picks the layer from the unit; for a ground constructor it is the same array.
// How far toward the enemy a site may sit before it counts as their ground.
// The front line is the influence crossing now, so this sits just inside the line
// team already agrees on.
const float CON_FAR_FRAC = 0.72f;

// Is this site past the front, i.e. in enemy territory?
//
// Pure geometry against two positions that are always real -- our own base and
// the enemy centroid -- because the threat map is not.
// A MEX is worth contesting in a way an ordinary building is not: it pays for
// itself, it denies the spot to them, and refusing one costs the whole game's
// income from it. The general bar also uses the enemy CENTROID, which on an 8v8
// is the average of sixteen scattered players and therefore sits mid-map -- so
// 0.72 of the way to it lands in neutral ground we should simply be taking.
const float MEX_FAR_FRAC = 0.92f;

// The raw projection of a position onto the home->enemy axis: 0 at our base,
// 1 at the enemy centroid. Logging this is what makes a rejection explicable --
// "rejected" alone cannot distinguish a bad threshold from a bad centroid.
float FrontT(const AIFloat3& in where)
{
	if (!gHomeSet)
		return 0.f;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	const float ex = foe.x - gHomePos.x;
	const float ez = foe.z - gHomePos.z;
	const float span = ex * ex + ez * ez;
	if (span < 1.f)
		return 0.f;
	return ((where.x - gHomePos.x) * ex + (where.z - gHomePos.z) * ez) / span;
}

// A point BEHIND our base, on the same axis: home, pushed directly away from
// the enemy centroid. FrontT of the result is negative, which is what "the
// back of our base" means in this codebase's one spatial model.
//
// Clamped onto the map, because home near a map edge pushes straight off it and
// an off-map position crashes the threat map (CThreatMap bounds-checks under an
// assert that is compiled out in release).
AIFloat3 RearOfBase(float dist)
{
	AIFloat3 rear = gHomePos;
	if (!gHomeSet)
		return rear;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	const float ex = foe.x - gHomePos.x;
	const float ez = foe.z - gHomePos.z;
	const float len = sqrt(ex * ex + ez * ez);
	if (len < 1.f)
		return rear;
	rear.x = gHomePos.x - (ex / len) * dist;
	rear.z = gHomePos.z - (ez / len) * dist;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float pad = 64.f;
	if (rear.x < pad) rear.x = pad;
	if (rear.z < pad) rear.z = pad;
	if (rear.x > w - pad) rear.x = w - pad;
	if (rear.z > h - pad) rear.z = h - pad;
	return rear;
}

bool PastFrontFrac(const AIFloat3& in where, float frac)
{
	if (!gHomeSet)
		return false;
	// Front::FoeAnchor, not the mobile enemy centroid -- see its comment:
	// measured against presence, being raided shrank the claimable world to
	// the raider's distance (pastFront=225/sweep, 4-6 of 80 spots held).
	const AIFloat3 foe = Front::FoeAnchor();
	const float ex = foe.x - gHomePos.x;
	const float ez = foe.z - gHomePos.z;
	const float span = ex * ex + ez * ez;
	if (span < 1.f)
		return false;
	const float t = ((where.x - gHomePos.x) * ex + (where.z - gHomePos.z) * ez) / span;
	return t > frac;
}

// Mexes get a laxer bar than any other build type: ThreatFor's real reading
// still applies when the threat map has data, this only relaxes the
// GEOMETRIC fallback (PastFront/ThreatFor's own comment: the position threat
// map reads zero ~97% of the time), which is what actually fires today. A
// site that is not far forward is treated as safe rather than vetoed on that
// dead signal alone.
//
// Shared by both places a threat check can end a mex task -- refuse (before
// ever accepting one) and abandon (Reevaluate re-checks a task already in
// progress on every step of the walk to it). Without this, a constructor
// could accept a rear mex fine, then get knocked off it on a later
// re-evaluation by the same unprotected geometric-fallback reading that the
// refuse path exempts. One rule, one place, used by both callers now.
float MexHeat(const AIFloat3& in site, float heat)
{
	if ((heat > CON_THREAT_VETO) && !PastFrontFrac(site, MEX_FAR_FRAC))
		return 0.f;
	return heat;
}

bool PastFront(const AIFloat3& in where)
{
	if (!gHomeSet)
		return false;
	const AIFloat3 foe = Front::FoeAnchor();
	const float ex = foe.x - gHomePos.x;
	const float ez = foe.z - gHomePos.z;
	const float span = ex * ex + ez * ez;
	if (span < 1.f)
		return false;
	// Project the site onto the home->enemy axis and compare the fraction.
	const float t = ((where.x - gHomePos.x) * ex + (where.z - gHomePos.z) * ez) / span;
	return t > CON_FAR_FRAC;
}

// How far around a build site we look for actual enemies, and how many make it
// hostile. 600 is inside most T1 weapon ranges plus a little walking room: if
// something armed is that close, a constructor standing still to build is being
// shot, not "near the front".
const float CON_FOE_RADIUS = 600.f;
const float CON_FOE_COUNT  = 1.f;
int gNextFoeDiag = 0;

// GetEnemyCostAt is a GetEnemyUnitsIn round trip that allocates a handle per
// enemy in the radius, and the rezzer chain asks it of the bot's own tile three
// times in one election (RezSpotHot, then twice inside RezzerRezOrEat) before
// any candidate site is even considered. Answered once per (frame, position):
// the enemy set the sweep reads cannot change inside one election.
const uint FOE_SLOTS = 10;
array<float> gFnX;
array<float> gFnZ;
array<float> gFnV;
int  gFnFrame = -1;
uint gFnNext = 0;

float FoesNear(const AIFloat3& in where)
{
	if (gFnFrame != ai.frame) {
		gFnFrame = ai.frame;
		gFnX.resize(0);
		gFnZ.resize(0);
		gFnV.resize(0);
		gFnNext = 0;
	}
	for (uint i = 0; i < gFnX.length(); ++i) {
		if ((gFnX[i] == where.x) && (gFnZ[i] == where.z))
			return gFnV[i];
	}
	const float v = ai.GetEnemyCostAt(where, CON_FOE_RADIUS);
	if (gFnX.length() < FOE_SLOTS) {
		gFnX.insertLast(where.x);
		gFnZ.insertLast(where.z);
		gFnV.insertLast(v);
	} else {
		gFnX[gFnNext] = where.x;
		gFnZ[gFnNext] = where.z;
		gFnV[gFnNext] = v;
		gFnNext = (gFnNext + 1) % FOE_SLOTS;
	}
	return v;
}

// Site-search radius for script-placed static defence.
//
// Every DEFENCE task in this file passed SQUARE_SIZE*2 or *4 -- 16 or 32 elmos
// -- while TaskB::Common's own default is SQUARE_SIZE*32, i.e. 256. That
// effectively demanded a buildable site on the exact point handed in, and the
// points come from StandoffPos/geometry with no buildability check at all,
// so a builder could accept the task and then never complete it.
const float DEF_SHAKE = SQUARE_SIZE * 32;

float ThreatFor(CCircuitUnit@ unit, const AIFloat3& in where)
{
	if (!OnMap(where))
		return 0.f;
	const float t = ai.GetUnitThreatAt(unit, where);
	if (t > 0.f)
		return t;

	// Enemies ACTUALLY near the spot, before falling back to geometry.
	//
	// PastFront below projects onto the home->enemy-CENTROID axis, which is a
	// 1-D test and wrong in two ways that matter here: with enemies spread out
	// the centroid sits where nobody is, and the projection ignores
	// perpendicular distance entirely -- so a site beside an enemy army, but
	// not far along that axis, reads perfectly safe.
	//
	// GetEnemyCostAt returns a COUNT of enemy units in the radius despite its
	// name (CircuitAI.cpp). It is LOS-gated, which is acceptable precisely
	// here: the danger this is meant to catch is close enough to see. OnMap is
	// already checked above, which is the guard the threat-map crash needed.
	const float foes = FoesNear(where);
	// Only the hot case is worth a line; "no enemies near this site" is the
	// overwhelming majority and says nothing.
	if ((foes > 0.f) && (ai.frame >= gNextFoeDiag)) {
		gNextFoeDiag = ai.frame + 10 * SECOND;
		AiLog(Factory::T() + "apex: con-foe-diag near=" + formatFloat(foes, "", 0, 0)
			+ " unitThreat=" + formatFloat(t, "", 0, 2)
			+ " pastFront=" + (PastFront(where) ? "1" : "0"));
	}
	if (foes >= CON_FOE_COUNT)
		return CON_THREAT_VETO + 1.f;
	// THE THREAT MAP READS ZERO almost everywhere, so a CON_THREAT_VETO test
	// against it alone passes unconditionally and constructors walk wherever
	// they like. Same dead signal that stopped the commander retreat ever firing.
	//
	// Geometry is the fallback: a site past the front is treated as hostile.
	// Crude next to a real threat map, but it is answering with data that exists.
	return PastFront(where) ? (CON_THREAT_VETO + 1.f) : 0.f;
}

// GROUND A CONSTRUCTOR SHOULD NOT WALK ONTO. apexearth 2026-09-02: "They're
// trying to walk straight into the fight to make the defensive turrets. They
// should just make the turrets as close as reasonably possible to the
// frontline as they can. If it's too dangerous then they should pull back or
// build further away."
//
// Two readings, both required, so a lone scout does not count (the hair
// trigger ISSUES.md records): something of theirs is actually within reach
// of the spot, AND their influence there beats ours -- ground our own army
// dominates is ground a builder can work under cover, whoever else is on
// it. The same "theirs means stronger, not merely present" test the ring
// march and the wall's danger gate use.
bool SiteHot(const AIFloat3& in where)
{
	if (!OnMap(where))
		return false;
	// A constructor died here in the last minutes: hot whatever we can see.
	if (Market::NearConDeath(where))
		return true;
	if (FoesNear(where) < CON_FOE_COUNT)
		return false;
	return ai.GetEnemyInflAt(where) > ai.GetAllyInflAt(where);
}

// The nearest quiet ground behind a hot site, stepping `step` elmos along
// `back` up to `steps` times; the site itself if it is quiet, off-map (-1)
// if nothing behind it is either.
AIFloat3 PullBack(const AIFloat3& in site, const AIFloat3& in back, float step, int steps)
{
	if (!SiteHot(site))
		return site;
	for (int k = 1; k <= steps; ++k) {
		const AIFloat3 p = site + back * (step * float(k));
		if (!OnMap(p))
			break;
		if (!SiteHot(p))
			return p;
	}
	return AIFloat3(-1.f, 0.f, -1.f);
}

// HOW FAR THE NEAREST ENEMY STILL HAS TO WALK BEFORE IT CAN SHOOT HERE.
// Negative means it already can. The DLL's rez guard (BuilderManager's
// UpdateRezGuard) walks bots out of exactly this envelope six times a second;
// an election that ignored it would hand the bot straight back in, so every
// rez rule asks the same question of the ground it is about to send one to.
//
// This is not the threat map: ThreatFor reads zero almost everywhere and falls
// back to a 1-D front projection (see its own comment). This is the enemies we
// can actually see, each with its own weapon reach and speed.
// EnemyReachSlack walks every enemy we know of, and the enemy set is the other
// thing that grows all game. One rezzer election asks it of the bot's own tile
// from the decide gate and again from the chain's own pressed counter, and then
// of every candidate site it considers -- twice each, until RezSiteOk stopped
// asking the second time. Answered once per (frame, position), which is the
// same answer the sweep gives: nothing inside one election moves an enemy.
const uint SLACK_SLOTS = 12;
array<float> gRsX;
array<float> gRsZ;
array<float> gRsV;
int  gRsFrame = -1;
uint gRsNext = 0;
// Latched: GetTunable is frozen for the game on its first read (CircuitAI.cpp
// caches per name), and this one was paid on every cache MISS -- a std::string
// built from the literal and a map walk, on the one path that already grows
// with both the bot count and the enemy count.
bool  gRsReactSet = false;
float gRsReactS = 0.f;

float ReachSlack(const AIFloat3 &in where)
{
	if (!OnMap(where))
		return 1.0e6f;
	if (gRsFrame != ai.frame) {
		gRsFrame = ai.frame;
		gRsX.resize(0);
		gRsZ.resize(0);
		gRsV.resize(0);
		gRsNext = 0;
	}
	for (uint i = 0; i < gRsX.length(); ++i) {
		if ((gRsX[i] == where.x) && (gRsZ[i] == where.z))
			return gRsV[i];
	}
	if (!gRsReactSet) {
		gRsReactSet = true;
		gRsReactS = ai.GetTunable("apex_rez_react_s", TUNE_REZ_REACT_S);
	}
	const float v = ai.EnemyReachSlack(where, gRsReactS);
	if (gRsX.length() < SLACK_SLOTS) {
		gRsX.insertLast(where.x);
		gRsZ.insertLast(where.z);
		gRsV.insertLast(v);
	} else {
		gRsX[gRsNext] = where.x;
		gRsZ[gRsNext] = where.z;
		gRsV[gRsNext] = v;
		gRsNext = (gRsNext + 1) % SLACK_SLOTS;
	}
	return v;
}

bool InEnemyReach(const AIFloat3 &in where)
{
	return ReachSlack(where) < 0.f;
}

// A resurrect pays out only on completion, so a bot driven off one has nothing
// to show for the time; reclaim credits metal continuously and can be abandoned
// part-done. On ground we may not get to keep, take the one that banks as it
// goes.
bool RezSpotHot(CCircuitUnit@ unit)
{
	return ThreatFor(unit, unit.GetPos(ai.frame)) > CON_THREAT_VETO;
}

// Earlier than RezSpotHot's own front-crossing line (PastFront's 72%), and
// gated on a team-state signal rather than distance alone, so a rez bot can
// switch to reclaiming before it actually takes damage.
//
// A raw distance-to-enemy-centroid proxy (BaseUnderAttack(), for commander
// safety) is not reused here: on a small map the centroid sits close to home
// from minute one regardless of whether anyone is attacking, reading map
// scale rather than danger.
//
// PastFrontFrac is relative instead of absolute -- how far along the
// home->enemy axis THIS position specifically sits -- and combining it with
// Military::LosingGround() (the same "under pressure" signal PreferReclaim()
// uses) keeps this from firing on ordinary forward positioning while winning.
const float REZ_EXPOSED_FRAC = 0.55f;

bool RezBotExposed(CCircuitUnit@ unit)
{
	return LosingNow() && PastFrontFrac(unit.GetPos(ai.frame), REZ_EXPOSED_FRAC);
}

// Empty means "not a build this rule covers". Defence, bunkers and big guns
// belong at the front by definition, and this variant reclaims battlefields on
// purpose, so none of them appear here.
string SiteBuildName(IUnitTask@ task)
{
	if ((task is null) || (task.GetType() != Task::Type::BUILDER))
		return "";
	const int bt = task.GetBuildType();
	if (bt == Task::BuildType::MEX)     return "mex";
	if (bt == Task::BuildType::MEXUP)   return "mexup";
	if (bt == Task::BuildType::ENERGY)  return "energy";
	if (bt == Task::BuildType::GEO)     return "geo";
	if (bt == Task::BuildType::GEOUP)   return "geoup";
	if (bt == Task::BuildType::CONVERT) return "convert";
	if (bt == Task::BuildType::STORE)   return "store";
	if (bt == Task::BuildType::PYLON)   return "pylon";
	if (bt == Task::BuildType::RADAR)   return "radar";
	if (bt == Task::BuildType::SONAR)   return "sonar";
	if (bt == Task::BuildType::NANO)    return "nano";
	if (bt == Task::BuildType::FACTORY) return "factory";
	return "";
}

void LogConVeto(CCircuitUnit@ unit, const string& in what,
		const string& in kind, float threat)
{
	if (ai.frame < gNextConVetoLog)
		return;
	gNextConVetoLog = ai.frame + 5 * SECOND;
	AiLog(Factory::T() + "apex: con-veto " + what + " " + unit.circuitDef.GetName()
		+ " -> " + kind + " threat=" + formatFloat(threat, "", 0, 0)
		+ " refused=" + gConRefused + " abandoned=" + gConAbandoned
		+ " rerouted=" + gConRerouted + " defended=" + gConDefended);
}


// THE INVASION SENSE. Enemy influence AT our own position, not distance to
// GetEnemyPos() (the centroid of all known enemies, which in a team game
// rarely comes near our base even during a raid). Read by the military stance,
// posture and withdraw layers.
const float BASE_DANGER_DIST = 2200.f;
// Latched, same law as gRsReactS above: frozen on first read, and the stance,
// posture and withdraw layers all ask this every update.
bool  gBaseInflSet = false;
float gBaseInflBar = 0.f;

bool BaseUnderAttack()
{
	if (!gHomeSet)
		return false;
	if (!gBaseInflSet) {
		gBaseInflSet = true;
		gBaseInflBar = ai.GetTunable("apex_base_attack_infl", TUNE_BASE_ATTACK_INFL);
	}
	if (ai.GetEnemyInflAt(gHomePos) > gBaseInflBar)
		return true;
	// Buildings dying at home in the last 45 s: an attack whatever the
	// influence map, which reads the enemies it can see.
	if (Military::BaseRaided())
		return true;
	return gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()) < BASE_DANGER_DIST;
}

}  // namespace Builder
