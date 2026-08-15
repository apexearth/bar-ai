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
IUnitTask@ Retreat(CCircuitUnit@ unit)
{
	IUnitTask@ held = unit.task;
	if ((held !is null) && (held.GetType() == Task::Type::RETREAT))
		return held;
	return aiBuilderMgr.EnqueueRetreat();
}

// How many of ONE factory def (standing + under construction, this player's
// own count -- CCircuitDef is per-instance) is enough. Past this, refuse the
// engine's own DefaultMakeTask offer of another one. Deliberately generous
// rather than tuned tight: a strong economy legitimately wants more than one
// bot lab to parallelize production.
//
// Derived from income rather than fixed: a player on 400 metal/second and a
// player on 40 do not want the same number of plants, and a full bank means
// the plants we have are not keeping up with what we can spend.
const float FACTORY_PER_INCOME  = 60.f;
const int   FACTORY_FULL_BONUS  = 2;

int FactoryTypeCap()
{
	int cap = 1 + int(aiEconomyMgr.metal.income / FACTORY_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		cap += FACTORY_FULL_BONUS;
	return cap;
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
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
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
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
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
	const float foes = ai.GetEnemyCostAt(where, CON_FOE_RADIUS);
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
	return Military::LosingGround() && PastFrontFrac(unit.GetPos(ai.frame), REZ_EXPOSED_FRAC);
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

}  // namespace Builder
