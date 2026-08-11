namespace Builder {

// How many of ONE factory def (standing + under construction, this player's
// own count -- CCircuitDef is per-instance) is enough. Past this, refuse the
// engine's own DefaultMakeTask offer of another one. Not zero-risk to set
// low: a strong economy legitimately wants more than one bot lab to
// parallelize production, so this is deliberately generous rather than
// tuned tight -- the bug this guards against was 8-10 in a few minutes, not
// a healthy player choosing a second or third.
// Derived from income rather than fixed. A player on 400 metal/second and a
// player on 40 do not want the same number of plants, and a full bank means the
// plants we have are not keeping up -- apexearth: "if we are full on metal then
// obviously we need more factories/builders spending it."
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
// STARTS the structure (same delay HaveT1BotLab() had), so several idle
// constructors evaluated inside that walk-to-site window can all read the
// same under-cap count and all get granted a build in turn -- apexearth,
// watching live minutes after the count-cap fix shipped: "teal has 7 or 8
// t1 botlabs... keeps making more over time... this is a bug." Same
// per-def spacing-gate pattern gRezzerDefs/REZ_SPACING already use
// elsewhere in this file for the identical class of race.
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
// apexearth, ten minutes into a game: "we've left a lot of open mexes that we
// should have easily just gone ahead and taken."
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
// progress on every step of the walk to it). apexearth, watching live: "the
// commander only goes forward to build mexes -- we lose fights and end up
// with almost none. Need more constructor aggression in building mexes
// behind us." Traced to the refuse path having this exemption and the
// abandon path NOT having it: a constructor could accept a rear mex fine,
// then get knocked off it on a later re-evaluation by the exact same
// unprotected geometric-fallback reading -- five abandon events on the same
// mex in under 30 seconds, all at threat=5, barely over CON_THREAT_VETO's
// 4.0. One rule, one place, used by both callers now.
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
// points come from StandoffPos/geometry with no buildability check at all.
// Measured consequence: script-placed towers were ACCEPTED by a builder (probe
// inside IBuilderTask::CanAssignTo showed corllt accepted six times in one
// game) and then never completed, while stock CircuitAI's own defence, which
// picks sites from real defence clusters, built normally.
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
	// not far along that axis, reads perfectly safe. That is the shape of
	// apexearth's report: "I still see cons running into enemy fire too much."
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
	// THE THREAT MAP READS ZERO. Measured over a 20-minute 4v4: 121 samples, 0
	// nonzero, max 0.00 -- so every CON_THREAT_VETO test passed unconditionally
	// and constructors walked wherever they liked. apexearth, watching: "still
	// see us sending construction units directly into clearly very dangerous
	// area". Same dead signal that stopped the commander retreat ever firing.
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
// gated on a team-state signal rather than distance alone. apexearth: "make
// our rezbots reclaim instead of resurrecting when they are in danger. If
// the enemy influence is creeping towards them... By the time they even
// take damage it is almost always too late."
//
// A raw distance-to-enemy-centroid proxy was tried for exactly this kind of
// early warning already (BaseUnderAttack(), for commander safety) and
// measured actively harmful on this map: Comet Catcher is small enough that
// the enemy centroid sits close to home from ~1 minute in for the ENTIRE
// game regardless of whether anyone is actually attacking -- it read map
// scale, not danger, and crushed the win rate before being disabled
// (COMM_BACK_WALL_ON, see its own comment). Do not repeat that mistake here.
//
// PastFrontFrac is relative instead of absolute -- how far along the
// home->enemy axis THIS position specifically sits -- and combining it with
// Military::LosingGround() (already used by PreferReclaim() for the same
// "we are under pressure" reasoning) keeps this from firing on ordinary
// forward positioning during a game we are winning.
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
