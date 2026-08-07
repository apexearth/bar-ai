#include "../../unit.as"


namespace Builder {

// The lead techs first, then hands advanced constructors to teammates so they
// can build T2 without each paying for their own advanced factory.
// Checked against BAR's unit defs for all three factions rather than assumed:
// the dearest T1 constructor is 200 (armcs, armch, corcs) and the cheapest
// advanced one 330 (legaca), so one threshold separates them everywhere.
const float ADV_CON_COST = 300.f;   // T1 cons are 100-200, T2 330-700
int gAdvConsMade = 0;
int gAdvConsGifted = 0;

array<int> gGifted;   // teams that already received their advanced con

// Observed live: the lead built its first T2 constructor and handed it straight
// over, leaving itself none. Two bugs behind it. This was called for EVERY unit
// added with no role filter, so any unit costing 300+ metal bumped the counter
// -- and the unit actually given away was whatever triggered the call, which
// need not be a constructor at all. And the guard counted cons ever MADE rather
// than cons currently HELD, so once the count was used up by combat units the
// next real constructor went out the door.
//
// Rule: never give one away while we hold only one ourselves.
// True while teammates are still waiting on an advanced constructor of their own.
// Set on a follower the moment the lead's gifted constructor arrives. That is
// the local signal that the pooling has paid off for us -- observed live, allies
// were still sending metal at 17 minutes, long after every con had been handed
// out, which is just donating our economy away.
bool gGotAdvCon = false;

// True once we hold an advanced constructor of our own, however we came by it --
// built or gifted.
bool gHaveAdvCon = false;

// How many we hold. One was the old target, and the factory ratios cannot make
// up the difference: Cortex's coravp weights constructors at ~1% against
// correap's 61%, so whatever this rule does not force does not get built.
// Measured over 16 games: 3 advanced constructors per player against stock's 8,
// with T2 spend 28,451 against 44,060 and T3 2,378 against 8,186.
int gAdvConCount = 0;

// Income is the thing an extra advanced constructor is there to spend. Below the
// first step one is plenty; a player running a real economy should be building
// out, and that is where the T2/T3 gap comes from.
const float ADV_CON_INCOME_STEP = 25.f;
const int   ADV_CON_MAX         = 4;

int AdvConsWanted()
{
	int want = 1 + int(aiEconomyMgr.metal.income / ADV_CON_INCOME_STEP);
	return (want > ADV_CON_MAX) ? ADV_CON_MAX : want;
}

bool NeedsAdvCon()
{
	return gAdvConCount < AdvConsWanted();
}

bool OwesAdvCons()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	for (uint i = 0; i < mates.length(); ++i) {
		const int cand = int(mates[i]);
		if ((cand != ai.teamId) && (gGifted.find(cand) < 0))
			return true;
	}
	return false;
}

// Returns true when the unit was handed to an ally, i.e. is no longer ours.
bool ShareAdvCon(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// Actual constructors only -- not commanders, not expensive tanks.
	if (usage != Unit::UseAs::BUILDER)
		return false;
	const CCircuitDef@ cdef = unit.circuitDef;
	if (cdef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if (cdef.costM < ADV_CON_COST)
		return false;

	// The follower half of the test used to sit BELOW a lead-only early return,
	// so it could never once be true and gGotAdvCon was never set. That is why
	// the symptom its own comment describes -- allies still slinging metal at 17
	// minutes -- survived the fix: Military::UpdateSling reads this flag to stop
	// donating, and it was permanently false.
	if (ai.teamId != Factory::RushLeadTeamId()) {
		gGotAdvCon = true;   // we have ours; stop paying for the lead's
		return false;
	}

	++gAdvConsMade;
	// Keep at least one for ourselves at all times: the lead is the player whose
	// job it is to upgrade mexes, and it cannot do that with no constructor.
	if ((gAdvConsMade - gAdvConsGifted) <= 1)
		return false;

	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	// One each and then stop. Every teammate needs a T2 con to start upgrading
	// its own mexes; past that we are just giving our build power away.
	for (uint i = 0; i < mates.length(); ++i) {
		int cand = int(mates[i]);
		if ((cand == ai.teamId) || (gGifted.find(cand) >= 0))
			continue;
		gGifted.insertLast(cand);
		++gAdvConsGifted;
		array<CCircuitUnit@> gift;
		gift.insertLast(unit);
		ai.GiveUnits(gift, cand);
		AiLog(Factory::T() + "apex: gave adv con to team " + cand + " (held "
			+ (gAdvConsMade - gAdvConsGifted + 1) + ", keeping "
			+ (gAdvConsMade - gAdvConsGifted) + ")");
		return true;
	}
	return false;
}


// Fusions we hold, so one can be handed to an ally that is being killed.
// apexearth: "it can also share a fus or afus to help them." A reactor is 4,300
// metal of permanent income, which is worth far more to a player whose base is
// being taken apart than another lump of metal it has no time to spend.
//
// Handles, so the same NOCOUNT hazard as gComm and gT1FacUnit applies: the
// engine does not null a handle when the unit dies, so every one of these has to
// be dropped in AiUnitRemoved or a later gift dereferences freed memory.
array<CCircuitUnit@> gFusions;
const uint FUSION_KEEP = 2;   // the ones our own economy runs on are never given

CCircuitUnit@ energizer1 = null;
CCircuitUnit@ energizer2 = null;

// AIFloat3 lastPos;
// int gPauseCnt = 0;

// Eating the field after a won fight is a large metal swing, and while the team
// is funding one player's tech it is the cheapest metal going -- nobody has to
// pay for it. But a plain area reclaim takes whatever is inside the circle, so
// a builder sent to a battlefield is as likely to chew a 12-metal tree as a
// dead Gollum. ai.GetBestWreckPos finds the richest body and we centre the
// circle on that, so corpses get valued rather than merely counted.
// This variant's whole plan is to make the enemy pay for our economy: let them
// attack into static defence backed by a massed army, and then eat the bodies.
// The third step is the one that funds everything, so it is worth reaching
// further and accepting smaller bodies than a tempo variant would -- after a
// repelled push the field is dense with wrecks and every one of them is metal
// the enemy bought for us.
const float WRECK_SEARCH  = 2200.f;  // reach the whole approach, not just home
const float WRECK_MIN     = 55.f;    // a repelled push leaves many small bodies
// A body worth INTERRUPTING a build for, and how far we will go to reach one.
// Reclaim previously required either an empty bank or an idle builder, so a
// constructor holding any task walked straight past a field of wrecks.
// apexearth, after a repelled push: "theres 1000+ metal in front of us and we
// don't even care". This variant's plan is to make the enemy pay for our
// economy and then eat the bodies -- that third step is the one that funds
// everything, and it was not happening.
// Deliberately a HIGH bar and a SHORT reach: this displaces real work, so it
// must only fire for a body big enough to be worth more than what it interrupts,
// and close enough that the walk is not the cost.
// TOTAL metal in the field, not the biggest single body: a repelled push leaves
// a dozen dead T1s, none of them individually large, and that is exactly the
// pile worth eating. apexearth: "often its a dozen t1 that just died... still
// its a lot of metal we should be eating... the building will still get made
// faster if we grab the metal - then we can make the building without waiting!"
const float WRECK_RICH    = 400.f;   // total reclaimable within WRECK_RICH_R
const float WRECK_RICH_R  = 1400.f;
const float WRECK_RADIUS  = 320.f;   // sweep the cluster, not one corpse
const int   WRECK_TIMEOUT = 1 * MINUTE;
int gNextWreck = 0;
int gNextMetalEmptyDiag = 0;  // temporary diagnostic, see the isMetalEmpty block below
// Spacing on the safe-mex grab. Short: an unclaimed spot is income we are not
// earning, and the check itself is one lookup.
const int REAR_MEX_PERIOD = 2 * SECOND;
int gNextRearMex = 0;
int gNextMexLog = 0;
int gNextRichLog = 0;

// ai.GetWreckValueAt/GetBestWreckPos were dead for every non-resigned team
// until the C++ fix in CircuitAI.cpp (2026-08): both used the CCircuitAI::
// metalRes member, which is only ever assigned inside NotifyResign() and so
// stayed null all game, making both calls return zero/invalid unconditionally.
// Fixed at the source, but every mobile builder already scans WRECK_RICH_R
// around itself every ~3s below regardless -- record what it sees here and let
// anyone without their own vantage point (factory.as's rez-bot floor) read the
// sighting instead of taking a fresh sample from wherever they happen to be.
float gWreckSeenValue = 0.f;
int gWreckSeenAt = 0;
const int WRECK_SEEN_TTL = 20 * SECOND;

void NoteWreckSeen(float value)
{
	if (value <= 0.f)
		return;
	gWreckSeenValue = value;
	gWreckSeenAt = ai.frame;
}

float WreckSeenValue()
{
	return (ai.frame - gWreckSeenAt <= WRECK_SEEN_TTL) ? gWreckSeenValue : 0.f;
}

// The engine's own build-site safety check is an AND of three terms
// (BuilderManager::MakeBuilderTask): near-zero power in the thing being built,
// hot threat map, AND influence already reading enemy-owned. Contested ground
// no enemy structure has claimed yet fails the third, so the task stays
// selectable and a constructor walks to it. This is the middle term alone.
//
// The threat map paints enemy damage-vs-builder times sqrt(health) over each
// enemy's weapon range and is still half its peak at the rim -- so a covered
// tile reads in the hundreds and an uncovered one reads zero, while an
// unidentified radar blip contributes 0.1. 4.0 is THREAT_MIN * 4, the engine's
// own "an enemy holds this ground" bar in MilitaryManager::DefaultMakeDefence.
//
// Declared here, ahead of its first use in EnqueueWreckReclaim just below:
// AngelScript has no forward declarations for globals (functions are visible
// module-wide regardless of order, but a global const must be declared before
// the line that reads it), and this constant used to live much further down,
// declared only once ThreatFor() -- which needs it -- was already in scope.
const float CON_THREAT_VETO = 4.0f;

// apexearth: "have our units never assist another unit build something if
// we are out of a resource (<5%)." Declared here, ahead of AiMakeTask's use
// of it, for the same forward-declaration reason as CON_THREAT_VETO above.
const float RESOURCE_CRISIS_FRAC = 0.05f;

IUnitTask@ EnqueueWreckReclaim(CCircuitUnit@ unit, Task::Priority priority)
{
	const AIFloat3 pos = unit.GetPos(ai.frame);
	const AIFloat3 wreck = ai.GetBestWreckPos(pos, WRECK_SEARCH, WRECK_MIN);
	if (wreck.x < 0.f)
		return null;   // nothing worth the trip
	// apexearth, watching live: "even our advanced cons are chasing wrecks
	// which are dangerous." Shared by the idle-builder fallback and the
	// rezzer-eats-wreck path; neither checked whether the wreck itself sits
	// somewhere safe before sending a constructor to it.
	if (ThreatFor(unit, wreck) > CON_THREAT_VETO)
		return null;
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(priority, wreck,
			1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
}

// Rez bots are the only units in BAR that can resurrect at all -- armrectr,
// cornecro and legrezbot plus their three ship counterparts are the whole list,
// and every faction's T1 bot lab builds one. The engine hands them a resurrect
// unconditionally: CEconomyManager::UpdateReclaimTasks takes isResurrect
// straight from IsAbleToResurrect() with no economy test, so for those units it
// only ever queues RESURRECT and never a feature RECLAIM. Resurrecting spends to
// turn a corpse back into a unit; reclaiming turns it into metal, and the field
// after a won fight is the cheapest metal in the game -- which is exactly what a
// team pooling its income behind one player's tech is short of.
//
// The flag is not reachable from here, so pre-empt the task instead: hand the
// bot a wreck reclaim ourselves and DefaultMakeTask, the thing that would have
// created the resurrect, never runs. It cannot cost us build work: these bots
// are builder=true with no buildoptions, so the most it displaces is a repair.
// Only rez bots need this. Every other constructor already gets a RECLAIM from
// the same function, because for them isResurrect is false.
//
// The gate is deliberately short. A bot that loses this race is given a
// resurrect task with a 300-second timeout and is out of the metal business
// until it expires, which costs far more than the feature scan does.
const int REZ_WRECK_PERIOD = 1 * SECOND;
int gNextRezWreck = 0;
int gNextRezFleeLog = 0;

// Which defs resurrect, learned from the engine rather than named: BuilderManager
// routes exactly the canresurrect units through UseAs::REZZER. A name list would
// need armrectr/armrecl, cornecro/correcl and legrezbot/legnavyrezsub kept in
// sync, and the config roles cannot stand in for it either -- they disagree
// across factions ("support" for Armada and Legion, "rezzer" for Cortex).
// Both ends of the index are range-checked: the array is sized once at load, and
// an id past it raises a script exception that kills the enclosing callback
// without saying so.
array<bool> gRezzerDefs(ai.GetDefCount() + 1);

bool IsRezzer(CCircuitUnit@ unit)
{
	const int id = unit.circuitDef.id;
	return (id >= 0) && (uint(id) < gRezzerDefs.length()) && gRezzerDefs[id];
}

// Reclaim turns a corpse into raw metal; resurrect returns the WHOLE unit for a
// fraction of its build cost. That is the same efficiency argument that makes
// T1 spam good -- a resurrected Thug is far cheaper than a built one.
//
// This used to require a FULL bank before it would allow a resurrect, which in
// practice never happened, so rez bots only ever reclaimed. Measured on
// Glitters: stock spent 27,385 metal resurrecting in a game it dominated on
// army 96k to 23.6k, while apex spent 0.
//
// Reclaim is now preferred only while metal is genuinely the binding
// constraint: before we own an advanced factory, or when the bank is actually
// empty and a build is stalled on it.
// apexearth: "requiring full is a bit nuts, I think 90% is a good limit", and
// earlier "if we have absolutely no metal, then reclaim". Read together: keep
// resurrecting across almost the whole band and fall back to reclaim only when
// the bank is genuinely scarce.
//
// Note isMetalFull is already storage*0.8 and isMetalEmpty storage*0.2
// (economy.as), so the original gate was "above 80%", not literally full.
const float REZ_METAL_FLOOR = 0.10f;   // reclaim below this share of storage

bool PreferReclaim()
{
	// No commander: rez ahead of everything else, including the pre-T2
	// default. gComm is null only for the real gap between death and rebuild.
	if (gComm is null)
		return false;
	if (!Factory::gHaveT2)
		return true;
	// Behind on the field, the completion risk is the whole argument: a resurrect
	// credits nothing until it finishes, so a bot pushed off one has spent the
	// time for no metal, while reclaim banks continuously and survives being
	// interrupted. Same reasoning as RezSpotHot, on the team's position instead of
	// this bot's tile. apexearth: "our resurrection box should be more likely to
	// reclaim when we're losing."
	if (Military::LosingGround())
		return true;
	return aiEconomyMgr.metal.current
	     < aiEconomyMgr.metal.storage * REZ_METAL_FLOOR;
}


// How many of ONE factory def (standing + under construction, this player's
// own count -- CCircuitDef is per-instance) is enough. Past this, refuse the
// engine's own DefaultMakeTask offer of another one. Not zero-risk to set
// low: a strong economy legitimately wants more than one bot lab to
// parallelize production, so this is deliberately generous rather than
// tuned tight -- the bug this guards against was 8-10 in a few minutes, not
// a healthy player choosing a second or third.
const int FACTORY_TYPE_CAP = 3;

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

// CThreatMap indexes its arrays straight from the position and range-checks only
// under assert; the bound is a strict less-than against the terrain extent.
// -RgtVector, the engine's "no position", fails the first test.
bool OnMap(const AIFloat3& in p)
{
	return (p.x >= 0.f) && (p.z >= 0.f)
		&& (p.x < float(AiTerrainWidth())) && (p.z < float(AiTerrainHeight()));
}

// ai.GetBuilderThreatAt is the BUILDER-role SURFACE layer, and AddEnemyUnit
// routes HasSurfToAir enemies into the air layer, so a pure AA turret adds
// nothing to it -- an air constructor cannot see what kills it. GetUnitThreatAt
// picks the layer from the unit; for a ground constructor it is the same array.
// How far toward the enemy a site may sit before it counts as their ground.
// FrontPos is published at 0.78 of the way, so this is just inside the line the
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

float ThreatFor(CCircuitUnit@ unit, const AIFloat3& in where)
{
	if (!OnMap(where))
		return 0.f;
	const float t = ai.GetUnitThreatAt(unit, where);
	if (t > 0.f)
		return t;
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

// Live MEX build tasks, so a refused one can be traded for a colder one.
//
// The script cannot enumerate metal spots -- no CMetalManager type is registered
// -- and a MEX task built here would carry spotId -1, which CBMexTask hands
// straight to mexSpots[spotId]. AiTaskAdded is the only place a MEX task is ever
// visible. IUnitTask is refcounted, so a held handle keeps the object alive, and
// every removal funnels through DequeueTask, which calls AiTaskRemoved.
array<IUnitTask@> gMexTasks;

// The script cannot ask whether a position is reachable, and the far side of the
// map usually is not.
const float REROUTE_RANGE = 3000.f;

// Same buildDef as the task the engine just offered this unit is the only proof
// available that the unit can build it: CCircuitDef exposes no CanBuild binding,
// and mex defs are per-constructor -- armck builds armmex, armack only armmoho.
IUnitTask@ SaferMex(CCircuitUnit@ unit, IUnitTask@ refused)
{
	const CCircuitDef@ want = refused.buildDef;
	if (want is null)
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestDist = REROUTE_RANGE;
	float bestThreat = 0.f;
	for (uint i = 0; i < gMexTasks.length(); ++i) {
		IUnitTask@ cand = gMexTasks[i];
		if ((cand is null) || (cand is refused))
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= bestDist)
			continue;
		const float heat = ThreatFor(unit, where);
		if (heat > CON_THREAT_VETO)
			continue;
		// Spreading over spots beats stacking constructors on one.
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy !is null) && (busy.length() > 0))
			continue;
		@best = cand;
		bestDist = dist;
		bestThreat = heat;
	}
	if (best is null)
		return null;
	++gConRerouted;
	if (ai.frame >= gNextRerouteLog) {
		gNextRerouteLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-reroute " + unit.circuitDef.GetName()
			+ " -> mex threat=" + formatFloat(bestThreat, "", 0, 0)
			+ " dist=" + formatFloat(bestDist, "", 0, 0)
			+ " rerouted=" + gConRerouted);
	}
	return best;
}

string armmex("armmex");
string cormex("cormex");
string legmex("legmex");

// apexearth: "we aren't doing too bad here but it feels noticeably less good
// than yesterday" -> traced (2026-08-05) to the factory-cap veto below leaving
// a refused constructor fully idle -- its own comment already says so: "CIdleTask
// assigns whatever comes back... simply leaves the unit idle until the next idle
// sweep." A timeline (analyze_stats.py) on Armada,Armada showed mex count
// dead even with stock through minute 6, then falling behind by minute 8 --
// entirely in the T1 window -- and infolog con-veto counts showed "factory-cap"
// as the dominant refusal reason for armck specifically (26 of 45 in one game,
// more than mex+mexup combined). SaferMex (above) cannot help here: it matches
// candidates by the REFUSED task's own buildDef, and a factory-cap refusal's
// buildDef is a factory, not a mex. But the basic T1 mex is buildable by every
// side's T1 constructor by design (this is what those constructors are FOR),
// so it does not need the "engine already proved buildability" trick SaferMex
// relies on for tiers that vary per-constructor (armck builds armmex, armack
// only armmoho -- see SaferMex's own comment).
IUnitTask@ FallbackMex(CCircuitUnit@ unit)
{
	const CCircuitDef@ want = SideDef3(armmex, cormex, legmex);
	if (want is null)
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	IUnitTask@ best = null;
	float bestDist = REROUTE_RANGE;
	for (uint i = 0; i < gMexTasks.length(); ++i) {
		IUnitTask@ cand = gMexTasks[i];
		if (cand is null)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist >= bestDist)
			continue;
		if (ThreatFor(unit, where) > CON_THREAT_VETO)
			continue;
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy !is null) && (busy.length() > 0))
			continue;
		@best = cand;
		bestDist = dist;
	}
	if (best is null)
		return null;
	++gConRerouted;
	if (ai.frame >= gNextRerouteLog) {
		gNextRerouteLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-reroute " + unit.circuitDef.GetName()
			+ " -> factory-cap-fallback-mex dist=" + formatFloat(bestDist, "", 0, 0)
			+ " rerouted=" + gConRerouted);
	}
	return best;
}

// Contest the mex rather than sit on it. apexearth: "build defenses a safe
// distance from the mex we desire to control. That is usually what I would do."
// The standoff walks back toward our own start until the threat map reads clear,
// so it is set by the enemy's reach rather than by a constant.
const float DEF_STEP    = 160.f;
const int   DEF_STEPS   = 6;
const float DEF_SPACING = 500.f;
const int   DEF_PERIOD  = 30 * SECOND;

AIFloat3 gConDefPos;
bool gConDefPlaced = false;
int  gNextConDef = 0;

// apexearth: "its terrible if they just get full of metal and stop doing
// anything." AA/HeavyAA/Pulsar/ContestDefence/EcoFusion all gate off while
// aiEconomyMgr.isEnergyStalling, so a team can end up with every one of
// those rules simultaneously refusing to fire while metal keeps piling up
// with nowhere to go -- a fully idle unit sitting on a capped bank. Metal
// overflowing and doing nothing is strictly worse than spending some of a
// stalling energy reserve on cheap ground defense, so the last-resort
// fallback at the end of AiMakeTask bypasses that gate deliberately.
const int METAL_FULL_DEF_PERIOD = 30 * SECOND;
int gNextMetalFullDef = 0;

// How much defence has to already stand here before we stop adding to it.
//
// apexearth, asking for the dig-in behaviour back: "Last time it seemed
// unbounded so this time only do it if there seems to be a lack of defenses in
// the area already." The unbounded version was one of twelve spending rules that
// together cut metal production 4.3x -- every one of them confirmed firing, and
// the dig-in fortresses were among the most expensive.
//
// gConDefPos is not that bound: it remembers only the ONE most recent tower, so
// it cannot see a porcupine cluster build_chain already put here.
// Military::FenceCountNear reads the register of every finished defence we own,
// whatever placed it.
const float DIG_AREA      = 700.f;
const uint  DIG_MAX_FENCE = 2;
// FENCE only fires on FINISHED, so without this a burst of orders would all see
// an empty area and each add another tower. Expires on its own: a task can be
// dropped and there is no completion hook to clear it against.
const int   DIG_ORDER_TTL = 90 * SECOND;
array<AIFloat3> gDigOrderPos;
array<int>      gDigOrderAt;

uint DefenceAround(const AIFloat3& in pos)
{
	uint n = Military::FenceCountNear(pos, DIG_AREA);
	for (int i = int(gDigOrderAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gDigOrderAt[i] > DIG_ORDER_TTL) {
			gDigOrderAt.removeAt(i);
			gDigOrderPos.removeAt(i);
		} else if (gDigOrderPos[i].distance2D(pos) <= DIG_AREA) {
			++n;
		}
	}
	return n;
}

const int   TROUBLE_HITS    = 3;
// Never stack more than this in one 700-elmo area, however hot it gets.
const uint DIG_FENCE_CAP = 5;

// apexearth: "Areas should have a general limit to how much they'll build
// there, especially on things like jammers... I often see many jammers all
// close together." Traced: build_chain.json attaches a jammer to MULTIPLE
// separate parent hubs independently (e.g. armjamt on three different hook
// triggers), each firing once per matching parent instance finishing, at a
// fixed offset from THAT parent -- with nothing checking whether a jammer
// already stands nearby from a DIFFERENT parent's hub. Three fusions built
// near each other (normal) produce three jammers near each other too.
//
// SiteBuildName() has no "jammer" kind at all (jammers fall through its
// whitelist as ""), so the existing con-veto/threat-check block never sees
// them. Same pattern as DefenceAround/gDigOrderPos above (no completion
// hook to clear an order against, so track by TTL instead), scoped to the
// four jammer defs actually seen in build_chain.json this session.
string armjamt("armjamt");
string corjamt("corjamt");
string legjam2("legjam");
string legajam("legajam");
const float JAMMER_AREA     = 900.f;   // jammer coverage is wider than a defence fence
const int   JAMMER_ORDER_TTL = 180 * SECOND;   // jammers are slow to build; outlive DIG_ORDER_TTL
array<AIFloat3> gJammerPos;
array<int>      gJammerAt;

bool IsJammerDef(const CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string name = def.GetName();
	return (name == armjamt) || (name == corjamt) || (name == legjam2) || (name == legajam);
}

// Returns true if a jammer already stands (or was recently ordered) within
// JAMMER_AREA of pos -- i.e. a new one here would cluster, not cover new
// ground. Ages out its own tracked orders past JAMMER_ORDER_TTL the same
// way gDigOrderPos does.
bool AreaHasJammer(const AIFloat3& in pos)
{
	for (int i = int(gJammerAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gJammerAt[i] > JAMMER_ORDER_TTL) {
			gJammerAt.removeAt(i);
			gJammerPos.removeAt(i);
		} else if (gJammerPos[i].distance2D(pos) <= JAMMER_AREA) {
			return true;
		}
	}
	return false;
}

// How much defence an area needs, given how dangerous it has proven to be.
//
// apexearth: "This area is dangerous, and therefore, I should defend it better
// than it already is defended." DIG_MAX_FENCE was a flat 2 -- the same bar for a
// quiet back mex and a spot the enemy army is walking through.
//
// hits is the count of times the constructor working here has been struck. It is
// already tracked per constructor for the dig-in trigger, and unlike
// GetBuilderThreatAt -- which reads zero 97% of the time and crashes off-map --
// it is a real, positional measure of danger: something shot us, here.
uint FenceWanted(int hits)
{
	uint want = DIG_MAX_FENCE;
	if (hits >= TROUBLE_HITS * 3)
		want += 3;
	else if (hits >= TROUBLE_HITS * 2)
		want += 2;
	else if (hits >= TROUBLE_HITS)
		want += 1;
	return (want > DIG_FENCE_CAP) ? DIG_FENCE_CAP : want;
}

bool AreaNeedsDefence(const AIFloat3& in pos, uint wanted = DIG_MAX_FENCE)
{
	return DefenceAround(pos) < wanted;
}

void NoteDigOrder(const AIFloat3& in pos)
{
	gDigOrderPos.insertLast(pos);
	gDigOrderAt.insertLast(ai.frame);
}

// Split by tier because the tiers share nothing: armck/corck/legck build
// armllt/corllt/leglht and no advanced tower, armack/armacv build armpb but
// neither armllt nor armmex. Read from each constructor's buildoptions.
string armllt("armllt");
string corllt("corllt");
string leglht("leglht");
string armpb("armpb");
string corvipe("corvipe");
string legapopupdef("legapopupdef");

// T1 energy converters, at the back wall. apexearth: "t1 energy converters are
// super duper cheap, to make t1 cons, send them to the back wall, and make
// converters should be a super easy and safe task to do."
//
// The costs, read from the defs: 1 metal, 1,150 energy, 2,600 buildtime (a mex is
// 50 / 500 / 1,800). So this is free in the scarce resource, paid for in the one
// being thrown away -- 131,422 energy wasted per player in the last 8 games, or
// about 114 converters' worth -- and the only real price is builder TIME.
//
// Which is why the floor below matters more than anything else here. Every rule
// added this session was of the form "if X then take a constructor", and with one
// constructor that is all of the build power rather than a share of it. This one
// asks whether we can spare a builder first, and never takes the last two.
string armmakr("armmakr");
string cormakr("cormakr");
string legeconv("legeconv");
// Advanced converters. 380 metal for 600 E/s at efficiency 0.01724 -- 10.3
// metal/s each, against the small one's 1.0, and better per joule too (1 metal
// per 58 energy against 1 per 70). Buildable only by advanced constructors.
string armmmkr("armmmkr");
string cormmkr("cormmkr");
string legadveconv("legadveconv");

// The NAVAL forms of both tiers. A ship constructor's buildoptions contain only
// these -- corcs carries corfmkr and no cormakr -- so handing a naval builder the
// land def is the same silent no-op, in reverse, that the note above records for
// armfmkr. Legion has no naval advanced converter in this game tree; its T2 naval
// constructor is coracsub (reached through corasy, which legcs builds), and that
// carries coruwmmm.
string armfmkr("armfmkr");
string corfmkr("corfmkr");
string legfeconv("legfeconv");
string armuwmmm("armuwmmm");
string coruwmmm("coruwmmm");

// CCircuitDef::isFloater is set only when the unit can exist on water and NOT on
// land (minElev < -1 && maxElev < 1), so it separates ship constructors from the
// commander and from hovers, which carry the land defs anyway.
bool IsNavalBuilder(CCircuitUnit@ unit)
{
	return unit.circuitDef.IsFloater() || unit.circuitDef.IsSubmarine();
}

CCircuitDef@ SmallConvDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armfmkr, corfmkr, legfeconv);
	return SideDef3(armmakr, cormakr, legeconv);
}

CCircuitDef@ BigConvDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armuwmmm, coruwmmm, coruwmmm);
	return SideDef3(armmmkr, cormmkr, legadveconv);
}

const uint  CONVERT_CON_FLOOR = 3;    // never dip below this many workers
const float CONVERT_MIN_SPARE = 70.f; // one converter's draw of unused energy
const int   CONVERT_PERIOD    = 25 * SECOND;
const float REAR_DISTANCE     = 450.f;

// Enemy centroid this close to home means they are in the base.
// 2200, was 1100. GetEnemyPos is the centroid of ALL enemies, so on a 4v4 with
// them spread out it sits mid-map and reads far from every base even while one
// of them is standing in ours. Measured: fired once in a 20-minute game while
// three commanders died. Widening trades precision for actually firing; the
// commander only takes a back-wall job, so a false positive costs one solar
// built somewhere safe.
const float COMM_BASE_DANGER = 2200.f;
const int   COMM_HIDE_PERIOD = 30 * SECOND;
int gNextCommHide = 0;
// OFF. On Comet Catcher 4v4 the enemy TEAM CENTROID sits under COMM_BASE_DANGER
// from ~1 minute in and stays there for the whole game (logged distances
// 1300-2200 throughout), because the map is small enough that four spread-out
// enemies average close to home regardless of whether anyone is actually
// attacking. BaseUnderAttack() was not reading a threat on this map; it was
// reading map scale. That fired this branch roughly every COMM_HIDE_PERIOD for
// the entire game, spending the commander's build time -- normally the single
// fastest builder early -- on repeat back-wall solars instead of the opening
// build.
//
// Measured, 8-game control vs BARb:stable:hard_aggressive, Comet Catcher 4v4
// +25% Cortex/Cortex, 25 min: paired K/D log-ratio went from t=-13..-17
// (apex crushed every game, decided 0-5/0-7) to t=-0.87, not distinguishable
// from even (1-1 head to head, apex won one outright, 6/8 games ran the full
// 25 minutes instead of collapsing by minute 6-10). This was the single
// largest lever found in the session -- see notes/open-issues.md.
//
// COM_RETREAT_HEALTH (health-based retreat) is unaffected by this flag and is
// still the thing that pulls a commander out of real danger.
const bool COMM_BACK_WALL_ON = false;
string armsolar("armsolar");  string corsolar("corsolar");  string legsolar("legsolar");

bool BaseUnderAttack()
{
	if (!gHomeSet)
		return false;
	return gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()) < COMM_BASE_DANGER;
}
int gNextConvert = 0;
int gConverts = 0;

// Behind our own base, measured away from the enemy. Converters detonate, so the
// back wall is both safer for them and safer for everything near them.
bool RearPos(CCircuitUnit@ unit, AIFloat3& out spot)
{
	if (!gHomeSet)
		return false;
	AIFloat3 away = gHomePos - aiEnemyMgr.GetEnemyPos();
	if (away.SqLength2D() < NEAR_ZERO)
		return false;
	away.SafeNormalize2D();
	for (int i = 1; i <= 3; ++i) {
		const AIFloat3 back = gHomePos + away * (REAR_DISTANCE * float(i));
		if (!OnMap(back))
			continue;
		if (ThreatFor(unit, back) <= CON_THREAT_VETO) {
			spot = back;
			return true;
		}
	}
	return false;
}

float EnergySpare()
{
	return aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
}

// Are we actually THROWING ENERGY AWAY?
//
// income - pull is not that number and reading it as though it were is what kept
// the converter block to a handful of buildings: the eco lead logged spareE of
// 72-216 while the engine recorded 12.8 million energy wasted per game, 46.7% of
// everything it made. Pull counts demand that is being met from storage as well
// as from income, so a base that is spilling can still show almost no "spare".
//
// A full store is unambiguous -- Economy::AiUpdateEconomy sets isEnergyFull at
// 88% of storage, and past that every joule made is a joule binned.
bool EnergyWasting()
{
	return aiEconomyMgr.isEnergyFull || (EnergySpare() >= CONVERT_MIN_SPARE);
}

// The eco lead's converter BLOCK -- a packed rectangle, not the one-every-25s
// trickle the generic rule below places.
//
// Measured over 8 sixty-minute games: the eco lead threw away 12.8 million
// energy per game, 46.7% of everything it made, while a normal teammate wasted
// 22.5%. A converter eats 70 energy/s and returns 1 metal/s
// (energyconv_capacity 70, efficiency 1/70, read from armmakr.lua), and costs
// ONE metal to build. That spill is worth roughly sixty converters, i.e. about
// sixty metal a second, for essentially no metal outlay.
//
// apexearth sent the blueprint tutorial for this: humans lay energy and
// conversion out as dense packed rectangles rather than scattering them. A
// converter is 3x3, so a tight lattice is what it is meant to sit in.
const int   CONV_COLS      = 8;      // width of the block, in converters
const float CONV_STEP      = 64.f;   // 3x3 footprint plus a lane
const float CONV_BACK      = 1250.f; // behind the turret rows and the eco lanes
const int   CONV_PERIOD    = 6 * SECOND;
const int   CONV_INFLIGHT  = 6;
const int   CONV_STALE     = 16;
const int   CONV_MAX       = 90;
const int   ADV_CONV_AFTER = 8;   // small converters standing before switching up
int gNextEcoConv = 0;
int gEcoConvAsked = 0;

int SmallConvCount(CCircuitUnit@ unit)
{
	CCircuitDef@ d = SmallConvDef(unit);
	return (d is null) ? 0 : d.count;
}

// A rectangle CONV_COLS wide, growing backwards row by row, centred on the base
// axis so it lands behind the turret band rather than across it.
bool ConvSpot(CCircuitUnit@ unit, int index, AIFloat3& out spot)
{
	if (!gHomeSet)
		return false;
	AIFloat3 away = gHomePos - aiEnemyMgr.GetEnemyPos();
	if (away.SqLength2D() < NEAR_ZERO)
		return false;
	away.SafeNormalize2D();
	const AIFloat3 across(-away.z, 0.f, away.x);
	const int col = index % CONV_COLS;
	const int row = index / CONV_COLS;
	const float lateral = (float(col) - float(CONV_COLS - 1) * 0.5f) * CONV_STEP;
	const AIFloat3 p = gHomePos
		+ away * (CONV_BACK + float(row) * CONV_STEP)
		+ across * lateral;
	if (!OnMap(p) || (ThreatFor(unit, p) > CON_THREAT_VETO))
		return false;
	spot = p;
	return true;
}

IUnitTask@ EcoConverters(CCircuitUnit@ unit)
{
	if (!Factory::EcoLeadActive() || (ai.frame < gNextEcoConv))
		return null;
	// Only while energy is actually being binned, and self-limiting: every
	// converter raises pull by 70, so the store drains and this stops on its own.
	if (!EnergyWasting())
		return null;

	// An ADVANCED converter when the constructor asking can build one.
	//
	// apexearth: "at late game they're making advanced energy converters ... they
	// give you ten energy conversion each and six hundred energy of cost ... and
	// you just don't have to make so many little ones. They're also a lot more
	// durable." Confirmed against the defs: armmmkr is 380 metal for 600 E/s at
	// efficiency 0.01724 -- 10.3 metal/s, against the small one's 1.0 -- and it is
	// also better per joule, 1 metal per 58 energy against 1 per 70. Health 445
	// against 167.
	//
	// Chosen off the BUILDER's cost, not off gHaveAdvCon: only advanced
	// constructors carry armmmkr in their buildoptions, and handing a T1
	// constructor a task it cannot build is dropped silently -- the failure that
	// once cost 33 rush requests and an entire tech path.
	// Two ways to earn the advanced one. The asking constructor being advanced is
	// the safe case -- it can certainly build it. Otherwise, once the small block
	// is established and the team holds advanced constructors, ask anyway and let
	// one of them pick the task up: if nothing claims it the small block is still
	// standing and still converting, so the downside is bounded.
	//
	// Measured before this: a 40-minute game placed nine converters and every one
	// was armmakr, because the branch is nearly always reached by a T1 builder.
	const bool advBuilder = ((unit.circuitDef.costM >= ADV_CON_COST)
			&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		|| (gHaveAdvCon && (SmallConvCount(unit) >= ADV_CONV_AFTER));
	CCircuitDef@ small = SmallConvDef(unit);
	CCircuitDef@ big = BigConvDef(unit);
	CCircuitDef@ want = (advBuilder && (big !is null) && big.IsAvailable(ai.frame))
		? big : small;
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;

	// Counted across BOTH tiers, so the bookkeeping survives the switch from
	// small to advanced part way through a game.
	const int built = ((small is null) ? 0 : small.count) + ((big is null) ? 0 : big.count);
	if (built >= CONV_MAX)
		return null;

	// Outstanding bound, for the same reason the turrets have one: count sees
	// finished buildings only and Enqueue does not dedup.
	int outstanding = gEcoConvAsked - built;
	if (outstanding > CONV_STALE) {
		gEcoConvAsked = built;
		outstanding = 0;
	}
	if (outstanding >= CONV_INFLIGHT)
		return null;

	AIFloat3 spot;
	if (!ConvSpot(unit, gEcoConvAsked, spot))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT,
			Task::Priority::NORMAL, want, spot, SQUARE_SIZE * 4));
	if (post is null)
		return null;
	gNextEcoConv = ai.frame + CONV_PERIOD;
	++gEcoConvAsked;
	if ((gEcoConvAsked % 10) == 1)
		AiLog(Factory::T() + "apex: eco converter block " + want.GetName()
			+ " standing=" + built + " asked=" + gEcoConvAsked
			+ " spareE=" + formatFloat(EnergySpare(), "", 0, 0));
	return post;
}

IUnitTask@ EnergyConverter(CCircuitUnit@ unit)
{
	if (ai.frame < gNextConvert)
		return null;
	// Share, not truth: leave enough builders doing ordinary work.
	if (aiBuilderMgr.GetWorkerCount() <= CONVERT_CON_FLOOR)
		return null;
	// Only what the grid can actually feed. Self-limiting -- every converter
	// raises pull, so spare falls and this stops on its own.
	const float spare = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
	if (spare < CONVERT_MIN_SPARE)
		return null;

	// The T1 converter is what THIS constructor can build: armck/armcv carry
	// armmakr, corck/corcv cormakr, legck/legcv legeconv, and the ship
	// constructors carry only the naval def. Asking a ground constructor for
	// armfmkr produced 95 requests and zero converters; the mirror of that is what
	// SmallConvDef avoids for naval builders.
	CCircuitDef@ want = SmallConvDef(unit);
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;

	AIFloat3 spot;
	if (!RearPos(unit, spot))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT,
			Task::Priority::NORMAL, want, spot, SQUARE_SIZE * 8));
	if (post is null)
		return null;
	gNextConvert = ai.frame + CONVERT_PERIOD;
	++gConverts;
	AiLog(Factory::T() + "apex: converter " + want.GetName()
		+ " spare=" + formatFloat(spare, "", 0, 0)
		+ " workers=" + aiBuilderMgr.GetWorkerCount()
		+ " asked=" + gConverts + " standing=" + want.count);
	return post;
}

// Construction turrets for the eco lead, laid out as a LONG RECTANGLE behind the
// base rather than piled where a constructor happens to stand.
//
// apexearth: "ideally it creates a long rectangle of nanos and builds the eco
// all around those", and separately "boost its build power or start building
// more in parallel if it's used all the nanos in one area already". A turret
// only assists what is inside its radius, so stacking them on one yard
// saturates: the tenth turret queues behind the same work as the first. Two
// parallel rows, laid along the axis ACROSS the enemy direction and growing
// outward from the centre, give a band of overlapping radii instead -- every
// point along it is covered by several turrets, and the band is what the economy
// then gets built inside.
//
// The rows sit behind home on the same axis RearPos uses for converters, so the
// buildings that rule places already land within the band.
string armnanotc("armnanotc"); string cornanotc("cornanotc"); string legnanotc("legnanotc");

const float NANO_BACK = 400.f;   // how far behind home the first row sits
const float NANO_ROW  = 220.f;   // gap between the two rows
const float NANO_STEP = 300.f;   // spacing along a row; under a turret's radius
                                 // so neighbouring fields overlap

// How far outside the turret rows the economy sits. Under a turret's radius, so
// an eco slot is inside the assist field of the row it hugs.
const float ECO_INSET = 180.f;

// Where the index-th building of the band goes -- turret rows when nano is true,
// the economy rows that flank them when it is false. Deterministic in the index,
// so the shape is the same whichever constructor is asked to build it, and the
// two lattices share one anchor and one axis so they interlock rather than
// fighting each other for ground.
//
// apexearth: "the organization of the eco and the nanoturrets is very important
// to an efficient strategy."
bool BandSpot(CCircuitUnit@ unit, int index, bool nano, AIFloat3& out spot)
{
	if (!gHomeSet)
		return false;
	AIFloat3 away = gHomePos - aiEnemyMgr.GetEnemyPos();
	if (away.SqLength2D() < NEAR_ZERO)
		return false;
	away.SafeNormalize2D();
	// Perpendicular in the XZ plane: the long side of the rectangle.
	const AIFloat3 across(-away.z, 0.f, away.x);

	const int row = index % 2;          // which of the two rows
	const int col = index / 2;          // how far along it
	// Turret rows sit at NANO_BACK and one row deeper; the economy flanks them,
	// one lane in front of the first and one behind the last.
	const float back = nano
		? (NANO_BACK + float(row) * NANO_ROW)
		: ((row == 0) ? (NANO_BACK - ECO_INSET)
		              : (NANO_BACK + 2.f * NANO_ROW + ECO_INSET));
	// Alternate right and left of centre so the rectangle grows outward from the
	// base instead of marching off in one direction.
	const int step = ((col % 2) == 0) ? (col / 2) : -((col + 2) / 2);
	const AIFloat3 p = gHomePos + away * back + across * (float(step) * NANO_STEP);
	if (!OnMap(p) || (ThreatFor(unit, p) > CON_THREAT_VETO))
		return false;
	spot = p;
	return true;
}

// Only while metal is genuinely piling up. The eco lead's measured failure is
// income it has no capacity to spend -- over 7 sixty-minute games it PRODUCED
// 23% more metal than its teammates and BUILT 36% less, holding 12 constructors
// to their 28, and it was the only player never to reach T3. Buying the capacity
// to spend is what converts that bank into economy.
//
// Gating on the bank rather than on income is what keeps this off the list of
// rules that quietly ate the economy: when metal is tight this cannot fire at
// all, so it never displaces a mex upgrade.
const float NANO_MIN_BANK = 0.5f;   // share of metal storage standing unspent
// Raised with the shift away from ground engineers: a turret is 210 metal and
// never walks anywhere, which is why it is the build power this player should
// hold most of. Two rows of twenty is the rectangle it fills out.
const int   NANO_MAX      = 40;
const int   NANO_INFLIGHT = 4;    // turrets ordered but not yet standing
const int   NANO_STALE    = 12;   // beyond this the counter has drifted, resync
const int   NANO_PERIOD   = 15 * SECOND;
int gNextNano = 0;
int gNanosAsked = 0;

CCircuitDef@ NanoDef()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(cornanotc);
	if (side == "legion")
		return ai.GetCircuitDef(legnanotc);
	return ai.GetCircuitDef(armnanotc);
}

// Turrets we hold. aiBuilderMgr.GetWorkerCount() counts these as workers, so any
// cap meant for MOBILE constructors has to subtract them.
int NanoCount()
{
	CCircuitDef@ d = NanoDef();
	return (d is null) ? 0 : d.count;
}

IUnitTask@ EcoNano(CCircuitUnit@ unit)
{
	if (!Factory::EcoLeadActive() || (ai.frame < gNextNano))
		return null;
	if (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * NANO_MIN_BANK)
		return null;
	// A turret costs 3200 energy to put up; buying build power on a grid that
	// cannot pay for it stalls both.
	if (aiEconomyMgr.isEnergyStalling)
		return null;

	const string side = ai.GetSideName();
	CCircuitDef@ want = (side == "cortex") ? ai.GetCircuitDef(cornanotc)
	                  : ((side == "legion") ? ai.GetCircuitDef(legnanotc)
	                                        : ai.GetCircuitDef(armnanotc));
	if ((want is null) || !want.IsAvailable(ai.frame) || (want.count >= NANO_MAX))
		return null;

	// Bound what is OUTSTANDING, not just what stands. want.count sees finished
	// turrets only and Enqueue does not dedup, so the cap alone let this run to
	// asked=40 against standing=11 in one 20-minute stretch -- ordering a fresh
	// turret every period while thirty were already queued. Same failure the
	// rush constructor cap hit, and spacing alone does not fix it.
	//
	// The counter is resynced rather than trusted forever: a turret that dies
	// leaves asked permanently ahead of count, which would otherwise wedge this
	// rule shut for the rest of the game.
	int outstanding = gNanosAsked - want.count;
	if (outstanding > NANO_STALE) {
		gNanosAsked = want.count;
		outstanding = 0;
	}
	if (outstanding >= NANO_INFLIGHT)
		return null;

	AIFloat3 here;
	if (!BandSpot(unit, gNanosAsked, true, here))
		return null;

	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::NANO,
			Task::Priority::NORMAL, want, here, SQUARE_SIZE * 8));
	if (post is null)
		return null;
	gNextNano = ai.frame + NANO_PERIOD;
	++gNanosAsked;
	AiLog(Factory::T() + "apex: eco nano " + want.GetName()
		+ " standing=" + want.count + " asked=" + gNanosAsked
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0));
	return post;
}

// Fusions, placed in the economy lanes of the same band.
//
// The eco lead built NO fusion at all in the game that was read unit by unit,
// while every one of its teammates had one -- it is the player with the largest
// income and it was not buying the thing that turns income into late game. Left
// to stock task selection it spends on mexes and stalls there.
//
// 4,300 metal each in this game tree (upstream says 3,350 -- read from the defs,
// not remembered), so this is self-limiting against the bank: one fusion drops
// us under the gate until the economy refills it.
string armfus("armfus"); string corfus("corfus"); string legfus("legfus");
string armafus("armafus"); string corafus("corafus"); string legafus("legafus");
// The naval reactors. armacsub/coracsub carry armuwfus/coruwfus and no land
// reactor, so a ship or sub constructor handed corfus holds a task it can never
// start. Legion reaches T2 sea through coracsub, hence the Cortex def for it.
// Declared here rather than beside the converter defs above because a global has
// to precede its first use; a function does not.
string armuwfus("armuwfus"); string coruwfus("coruwfus");
string armadvsol("armadvsol"); string coradvsol("coradvsol"); string legadvsol("legadvsol");

CCircuitDef@ FusionDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armuwfus, coruwfus, coruwfus);
	return SideDef3(armfus, corfus, legfus);
}

const float FUSION_MIN_BANK = 0.55f;
const int   FUSION_PERIOD   = 45 * SECOND;
const int   FUSION_DIAG_PERIOD = 45 * SECOND;
int gNextFusion = 0;
int gNextFusionLog = 0;
int gNextFusionDiagLog = 0;
int gFusionsAsked = 0;

IUnitTask@ EcoFusion(CCircuitUnit@ unit)
{
	// Diagnostic for notes/next-session-hypotheses.md #2: unconditional (ahead of
	// every early return below) so it also shows how often this function's OWN
	// gates are what block it, versus DefaultMakeTask falling through to the
	// engine's score-sorted energy list (economy.json) further down, where solar
	// and advsol sort ahead of fusion's default e-income bar.
	if (ai.frame >= gNextFusionDiagLog) {
		gNextFusionDiagLog = ai.frame + FUSION_DIAG_PERIOD;
		CCircuitDef@ solarDef = SideDef3(armadvsol, coradvsol, legadvsol);
		AiLog(Factory::T() + "apex: fusion-gate diag lead=" + (Factory::EcoLeadActive() ? "1" : "0")
			+ " haveT2=" + (Factory::gHaveT2 ? "1" : "0")
			+ " income=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
			+ "/" + formatFloat(aiEconomyMgr.metal.storage * FUSION_MIN_BANK, "", 0, 0)
			+ " wasting=" + (EnergyWasting() ? "1" : "0")
			+ " advsolCount=" + ((solarDef is null) ? -1 : solarDef.count)
			+ " fusCount=" + FusionDef(unit).count);
	}

	if (!Factory::EcoLeadActive() || (ai.frame < gNextFusion))
		return null;
	// A T1 constructor cannot build one; asking anyway is the silent no-op this
	// repo has been bitten by before.
	if (!Factory::gHaveT2)
		return null;
	if (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * FUSION_MIN_BANK)
		return null;
	// Not while we are already spilling energy. Measured over 8 games, the eco
	// lead wasted 46.7% of every joule it made -- 12.8 million per game against a
	// teammate's 2.2 -- so another 4,300-metal reactor was buying more of the one
	// thing it already could not use. Converters below turn that spill into
	// metal; a reactor only helps once the spill is gone.
	if (EnergyWasting())
		return null;

	CCircuitDef@ want = FusionDef(unit);

	// Instrumented because the first run of this rule fired ZERO times in 24
	// minutes while every gate above it read clear -- bank 1237/1250 against a
	// bar of 55%, haveT2 set, income 87 -- and there was no way to tell which of
	// def, placement or enqueue was refusing. Guessing at that has cost this repo
	// whole runs before.
	AIFloat3 spot;
	const bool okDef = (want !is null) && want.IsAvailable(ai.frame);
	const bool okSpot = okDef && BandSpot(unit, gFusionsAsked, false, spot);
	IUnitTask@ post = okSpot
		? aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY,
				Task::Priority::NORMAL, want, spot, SQUARE_SIZE * 8))
		: null;
	if (post is null) {
		if (ai.frame >= gNextFusionLog) {
			gNextFusionLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: eco fusion BLOCKED"
				+ " def=" + ((want is null) ? "null" : want.GetName())
				+ " avail=" + (okDef ? "1" : "0")
				+ " spot=" + (okSpot ? "1" : "0")
				+ " home=" + (gHomeSet ? "1" : "0"));
		}
		return null;
	}
	gNextFusion = ai.frame + FUSION_PERIOD;
	++gFusionsAsked;
	AiLog(Factory::T() + "apex: eco fusion " + want.GetName()
		+ " standing=" + want.count + " asked=" + gFusionsAsked
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0));
	return post;
}

// Pulsars, and cheap AA. Both are things stock does that we do not.
//
// apexearth: "I don't see all that many pulsars in our defense lineup either.
// Pulsars would be a pretty good counter to hold back the onslaught." Pulsar is
// armanni -- and it is stock BARb's single largest metal sink, 14.0% of
// everything it builds, while ours is ~0%. Their defence outspends their army.
// It sits at porcupine.land index 12, which an ordinary cluster never reaches
// because porcupine.prevent is 2.
//
// And on AA: "lots of the time people just make AA because its so cheap, and if
// you have like 3 or 4 of them then the enemy air actively avoids you." That is
// DETERRENCE, not attrition -- armrl is 80 metal against flak's 820, so four of
// them is 320 metal to change the enemy's target selection. An earlier design
// sized flak at 45% of enemy air VALUE, up to 30 turrets and 24,600 metal, to
// kill an air force it could have simply discouraged.
string armanni("armanni");   string cordoom("cordoom");   string legbastion("legbastion");
string armrl("armrl");       string corrl("corrl");       string legrl("legrl");

const float PULSAR_MIN_INCOME = 60.f;
// apexearth: "we need at least 1000 energy per second before we should start
// thinking about making those". One fusion is armfus 1000 / corfus 1100 / legfus 1200.
const float PULSAR_MIN_ENERGY = 1000.f;
// 4 reached 22.0% of ALL metal -- more than stock's 14% -- while we held one T2
// constructor. Two is a pair covering one approach, which is what the economy can
// carry; raise it when metal production is no longer half of stock's.
const int   PULSAR_MAX        = 1;
const int   PULSAR_PERIOD     = 60 * SECOND;
// A flat standing count answered two aircraft and forty identically. These are
// 80 metal each and only built once the enemy actually flies, so the ceiling can
// be generous; the floor is what makes air pick someone else.
const int   AA_MIN            = 2;
const int   AA_MAX            = 12;
const float AA_PER_AIR        = 1000.f;  // one more turret per this much enemy air
const int   AA_PERIOD         = 20 * SECOND;
const uint  DEF_CON_FLOOR     = 3;      // never take the last builders
int gNextPulsar = 0;
int gNextAA = 0;
int gNextAADiag = 0;  // temporary diagnostic, see CheapAA

CCircuitDef@ SideDef3(const string& in a, const string& in c, const string& in l)
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(c);
	if (side == "legion")
		return ai.GetCircuitDef(l);
	return ai.GetCircuitDef(a);
}

// Cheap AA, kept at a small standing count. Any constructor can build it.
IUnitTask@ CheapAA(CCircuitUnit@ unit)
{
	if ((ai.frame < gNextAA) || aiEconomyMgr.isEnergyStalling)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	// Only if the enemy actually flies. This had no such test, while
	// DefaultMakeDefence has always skipped AA defs when GetEnemyCost(AIR) < 1 --
	// so in a ground-only game this was the single largest defence spend: 30
	// turrets in one 20-minute 4v4, more than the front line and the dig-ins
	// together. Measured with the new mDefence counter: static defence was 12.6%
	// of our metal against stock's 5.4%, with army 29.4% against 38.1%.
	// apexearth: "the side effect is wasteful defense and then we have less army
	// and are losing the overall fight."
	const float enemyAir = aiEnemyMgr.GetEnemyCost(Unit::Role::AIR.type);
	// DIAGNOSTIC, apexearth: "I didn't see us making AA... check it." GetEnemyCost
	// only accumulates on EnemyEnterLOS (not radar contact) and is otherwise never
	// reduced except on enemy death -- a fast hit-and-run flyer that stays at radar
	// range without crossing into true LOS could plausibly never get counted at
	// all. mobileThreat/GetEnemyThreat(AIR) are separate accumulators (threat, not
	// cost) that may behave differently; logging both to compare against the gate
	// this function actually uses. Remove once the hypothesis is confirmed or
	// ruled out.
	if (ai.frame >= gNextAADiag) {
		gNextAADiag = ai.frame + 20 * SECOND;
		AiLog(Factory::T() + "apex: AA-gate enemyAir(cost)=" + formatFloat(enemyAir, "", 0, 1)
			+ " enemyAirThreat=" + formatFloat(aiEnemyMgr.GetEnemyThreat(Unit::Role::AIR.type), "", 0, 1)
			+ " mobileThreat=" + formatFloat(aiEnemyMgr.mobileThreat, "", 0, 1)
			+ " rlCount=" + (SideDef3(armrl, corrl, legrl) is null ? -1 : int(SideDef3(armrl, corrl, legrl).count)));
	}
	if (enemyAir < 1.f)
		return null;
	int want = AA_MIN + int(enemyAir / AA_PER_AIR);
	if (want > AA_MAX)
		want = AA_MAX;
	CCircuitDef@ aa = SideDef3(armrl, corrl, legrl);
	if ((aa is null) || !aa.IsAvailable(ai.frame) || (aa.count >= want))
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, aa, here, SQUARE_SIZE * 4));
	if (post is null)
		return null;
	gNextAA = ai.frame + AA_PERIOD;
	AiLog(Factory::T() + "apex: cheap-aa " + aa.GetName() + " standing=" + aa.count
		+ "/" + want + " enemyAir=" + formatFloat(enemyAir, "", 0, 0));
	return post;
}

// armrl/corrl/legrl is DETERRENCE, not an answer: 80 metal, and CheapAA caps at
// AA_MAX=12 regardless of how much air the enemy actually has. apexearth,
// watching a game lost from this exact hole: "the enemies attacked us with
// like ten gunships on one of our bases, and we had like eight of the light
// AA. They did nothing. Light AA is so bad versus T2 gunships."
//
// So a second, heavier tier: cormadsam/armferret/legflak. All VTOL-only
// structures, one tier up in cost (315-820 metal against corrl's 80) and
// correspondingly harder-hitting. Gated on enemyAir being a real strike force
// rather than CheapAA's "the enemy owns one aircraft" bar, and on income.
//
// OFF. Measured worse, not better -- the same failure this comment set out to
// avoid. 8-game control vs BARb:stable:hard_aggressive, Comet Catcher 4v4 +25%
// Cortex/Cortex, 25 min, against the back-wall-fix baseline (see CHANGES.md,
// commander back-wall hiding): head to head 1-1 -> 0-5, metal produced
// 40,743 -> 27,382, static defence share 10.6% -> 11.5%, wiped-out player-games
// 9/32 -> 13/32. One game in a smaller trial run did win the economy and K/D
// outright (265,925 metal, K/D 1.13), so the mechanism is not obviously always
// bad -- it may need a higher income floor, a lower AA_HEAVY_MAX, or gating on
// SUSTAINED enemy air rather than a one-shot cost reading. Left in place,
// disabled, rather than deleted, since re-testing a narrower version is
// plausible future work.
const bool  AA_HEAVY_ON          = false;
const float AA_HEAVY_ENEMY_AIR   = 2500.f;  // roughly two-plus real attack aircraft, not scouts
const int   AA_HEAVY_MIN         = 1;
const int   AA_HEAVY_MAX         = 4;
const float AA_HEAVY_PER_AIR     = 1800.f;
const float AA_HEAVY_MIN_INCOME  = 20.f;
const int   AA_HEAVY_PERIOD      = 25 * SECOND;
int gNextHeavyAA = 0;
string armferret("armferret"); string cormadsam("cormadsam"); string legflak("legflak");

IUnitTask@ HeavyAA(CCircuitUnit@ unit)
{
	if (!AA_HEAVY_ON || (ai.frame < gNextHeavyAA) || aiEconomyMgr.isEnergyStalling)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	if (aiEconomyMgr.metal.income < AA_HEAVY_MIN_INCOME)
		return null;
	const float enemyAir = aiEnemyMgr.GetEnemyCost(Unit::Role::AIR.type);
	if (enemyAir < AA_HEAVY_ENEMY_AIR)
		return null;
	int want = AA_HEAVY_MIN + int((enemyAir - AA_HEAVY_ENEMY_AIR) / AA_HEAVY_PER_AIR);
	if (want > AA_HEAVY_MAX)
		want = AA_HEAVY_MAX;
	CCircuitDef@ aa = SideDef3(armferret, cormadsam, legflak);
	if ((aa is null) || !aa.IsAvailable(ai.frame) || (aa.count >= want))
		return null;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, aa, here, SQUARE_SIZE * 4));
	if (post is null)
		return null;
	gNextHeavyAA = ai.frame + AA_HEAVY_PERIOD;
	AiLog(Factory::T() + "apex: heavy-aa " + aa.GetName() + " standing=" + aa.count
		+ "/" + want + " enemyAir=" + formatFloat(enemyAir, "", 0, 0));
	return post;
}

// The heavy gun that holds ground. T2 constructors only -- armck/armcv cannot
// build it, and asking would be dropped in silence.
IUnitTask@ Pulsar(CCircuitUnit@ unit)
{
	if ((ai.frame < gNextPulsar) || aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	if (aiEconomyMgr.metal.income < PULSAR_MIN_INCOME)
		return null;
	// These are energy monsters, not metal ones: cordoom 37,000E, legbastion 58,000E,
	// armanni 74,000E, against 3000-4200 metal. The metal gate above is reachable on
	// T1 mexes alone, which is how a gun went up at 24.0 min ahead of the fusion at
	// 26.0. One fusion is 1000-1200 E/s, so this is "not before a fusion is paying".
	if (aiEconomyMgr.energy.income < PULSAR_MIN_ENERGY)
		return null;
	CCircuitDef@ gun = SideDef3(armanni, cordoom, legbastion);
	if ((gun is null) || !gun.IsAvailable(ai.frame) || (gun.count >= PULSAR_MAX))
		return null;
	AIFloat3 spot;
	if (!StandoffPos(unit, unit.GetPos(ai.frame), spot))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, gun, spot, SQUARE_SIZE * 2));
	if (post is null)
		return null;
	gNextPulsar = ai.frame + PULSAR_PERIOD;
	AiLog(Factory::T() + "apex: pulsar " + gun.GetName() + " standing=" + gun.count
		+ "/" + PULSAR_MAX + " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0));
	return post;
}

CCircuitDef@ ContestTower(CCircuitUnit@ unit)
{
	const string side = ai.GetSideName();
	if (unit.circuitDef.costM >= ADV_CON_COST) {
		if (side == "cortex")
			return ai.GetCircuitDef(corvipe);
		if (side == "legion")
			return ai.GetCircuitDef(legapopupdef);
		return ai.GetCircuitDef(armpb);
	}
	if (side == "cortex")
		return ai.GetCircuitDef(corllt);
	if (side == "legion")
		return ai.GetCircuitDef(leglht);
	return ai.GetCircuitDef(armllt);
}

// Reclaiming OUR OWN buildings, for two reasons that share one mechanism.
//
// 1. apexearth: "when theres no room to build a gantry we need to reclaim
//    older t1 buildings." C++ reports where a large footprint failed to place
//    (CBFactoryTask::FindBuildSite -> NoteBuildBlocked); we clear T1 clutter
//    near that spot.
// 2. apexearth: "once game is clearly in t3/t2 stage we need to reclaim all
//    our t1 and t1.5 defenses." Those towers stop earning against T2/T3 units
//    and their metal is better in something current.
//
// Targets are named defs, NOT a computed tier. CCircuitDef carries no tech
// level, so any tier test would be a heuristic -- and the failure mode here is
// reclaiming our own base, which is not a thing to be approximate about. These
// are exactly the towers ContestTower/MetalFullTower build, and the solar every
// opening puts down, so the list cannot drift away from what we actually own.
// Never mexes, never factories, never anything armed above T1.5.
const int OBSOLETE_PERIOD = 20 * SECOND;
const float OBSOLETE_NEAR = 900.f;     // around a blocked build site
// Income a T2 player must clear before stripping its own T1 defences. A player
// that has merely touched T2 may still be holding a line against T1 armies, and
// those towers are the line.
const float OBSOLETE_T2_INCOME = 60.f;
int gNextObsolete = 0;

// The T1/T1.5 towers this AI builds, cheapest first.
array<string> ObsoleteDefenceNames()
{
	const string side = ai.GetSideName();
	array<string> names;
	if (side == "cortex") {
		names.insertLast(corllt);
		names.insertLast(corvipe);
	} else if (side == "legion") {
		names.insertLast(leglht);
		names.insertLast(legapopupdef);
	} else {
		names.insertLast(armllt);
		names.insertLast(armpb);
	}
	return names;
}

// The opening solar, by name. SideDef3 returns a def; here we need the name.
string ObsoleteSolarName()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return corsolar;
	if (side == "legion")
		return legsolar;
	return armsolar;
}

IUnitTask@ ReclaimOwnDef(CCircuitUnit@ unit, const string& in defName,
		const AIFloat3& in near, float radius, const string& in why)
{
	CCircuitDef@ def = ai.GetCircuitDef(defName);
	if ((def is null) || (def.count <= 0))
		return null;
	array<CCircuitUnit@>@ owned = ai.GetOwnUnitsOfDef(def, near, radius);
	if ((owned is null) || (owned.length() == 0))
		return null;
	for (uint i = 0; i < owned.length(); ++i) {
		CCircuitUnit@ victim = owned[i];
		if ((victim is null) || (victim is unit))
			continue;
		IUnitTask@ eat = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL, victim));
		if (eat !is null) {
			gNextObsolete = ai.frame + OBSOLETE_PERIOD;
			AiLog(Factory::T() + "apex: obsolete-reclaim " + defName + " (" + why + ")");
			return eat;
		}
	}
	return null;
}

IUnitTask@ ObsoleteReclaim(CCircuitUnit@ unit)
{
	if (ai.frame < gNextObsolete)
		return null;

	// Case 1: something large could not be placed. Clear the cheapest clutter
	// first -- a solar is 155 metal and rebuildable anywhere, a T1 tower is
	// dead weight by the time we are placing gantries.
	AIFloat3 blocked;
	if (ai.GetBlockedBuildPos(blocked)) {
		array<string> clutter;
		clutter.insertLast(ObsoleteSolarName());
		array<string> towers = ObsoleteDefenceNames();
		for (uint i = 0; i < towers.length(); ++i)
			clutter.insertLast(towers[i]);
		for (uint i = 0; i < clutter.length(); ++i) {
			IUnitTask@ eat = ReclaimOwnDef(unit, clutter[i], blocked, OBSOLETE_NEAR, "blocked build");
			if (eat !is null)
				return eat;
		}
	}

	// Case 2: we are clearly past the tier these towers defend against. gHaveT3
	// is a gantry standing; the T2 half additionally wants a real economy, so a
	// player that merely touched T2 does not strip its own defences while still
	// fighting T1 armies.
	const bool lateEnough = Factory::gHaveT3
			|| (Factory::gHaveT2 && (aiEconomyMgr.metal.income >= OBSOLETE_T2_INCOME));
	if (!lateEnough)
		return null;
	array<string> towers = ObsoleteDefenceNames();
	for (uint i = 0; i < towers.length(); ++i) {
		IUnitTask@ eat = ReclaimOwnDef(unit, towers[i], gHomePos, 0.f, "past its tier");
		if (eat !is null)
			return eat;
	}
	return null;
}

bool StandoffPos(CCircuitUnit@ unit, const AIFloat3& in hot, AIFloat3& out spot)
{
	if (!gHomeSet)
		return false;
	AIFloat3 dir = gHomePos - hot;
	if (dir.SqLength2D() < NEAR_ZERO)
		return false;
	dir.SafeNormalize2D();
	for (int i = 1; i <= DEF_STEPS; ++i) {
		const AIFloat3 back = hot + dir * (DEF_STEP * float(i));
		if (!OnMap(back))
			continue;
		if (ThreatFor(unit, back) <= CON_THREAT_VETO) {
			spot = back;
			return true;
		}
	}
	return false;
}

IUnitTask@ ContestDefence(CCircuitUnit@ unit, const string& in kind,
		float heat, const AIFloat3& in hot)
{
	// A tower is 680-15,000 energy, and handing a task over directly bypasses
	// CanAssignTo, which is where the engine's own energy test lives.
	if ((ai.frame < gNextConDef) || aiEconomyMgr.isEnergyStalling)
		return null;
	CCircuitDef@ tower = ContestTower(unit);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	AIFloat3 spot;
	if (!StandoffPos(unit, hot, spot))
		return null;
	if (gConDefPlaced && (gConDefPos.distance2D(spot) < DEF_SPACING))
		return null;
	if (!AreaNeedsDefence(spot))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, spot, SQUARE_SIZE * 2));
	if (post is null)
		return null;
	NoteDigOrder(spot);
	gNextConDef = ai.frame + DEF_PERIOD;
	gConDefPos = spot;
	gConDefPlaced = true;
	++gConDefended;
	if (ai.frame >= gNextDefenceLog) {
		gNextDefenceLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-defend " + unit.circuitDef.GetName()
			+ " " + kind + " threat=" + formatFloat(heat, "", 0, 0)
			+ " -> " + tower.GetName()
			+ " back=" + formatFloat(hot.distance2D(spot), "", 0, 0)
			+ " defended=" + gConDefended);
	}
	return post;
}

// A constructor that keeps getting shot will not expand, whatever the threat map
// says at the instant we ask. apexearth: "if a con has to retreat too much in its
// recent history it should just go into safety and make defenses. Because at that
// point it's unable to expand due to threats."
//
// History rather than prediction, because prediction demonstrably misses:
// ContestDefence above fires off ThreatFor at the build site, and in a watched
// 20-minute game constructors died with con-veto firing ZERO times -- the shooter
// is outside the tile being tested. Losing health is not a forecast.
// (declared above FenceWanted, which needs it)
const int   TROUBLE_WINDOW  = 90 * SECOND;   // quiet for this long and the count clears
const int   FORTIFY_TIME    = 120 * SECOND;  // how long a struck con stays dug in
const int   FORTIFY_PERIOD  = 20 * SECOND;   // one tower per con per this
const float TROUBLE_HP_DROP = 0.02f;
const uint  CON_TRACK_MAX   = 48;
const int   CON_TRACK_STALE = 3 * MINUTE;

array<int>   gConId;
array<int>   gConHits;
array<int>   gConHurtAt;
array<float> gConHp;
array<int>   gConDigUntil;
array<int>   gConNextDig;
array<int>   gConTouch;
int gConFortified = 0;
int gNextFortifyLog = 0;

// AiUnitRemoved does not fire for every tracked constructor, so dead ones are
// dropped by staleness rather than on death.
int ConSlot(CCircuitUnit@ unit)
{
	const int id = unit.id;
	for (uint i = 0; i < gConId.length(); ++i) {
		if (gConId[i] == id) {
			gConTouch[i] = ai.frame;
			return int(i);
		}
	}
	if (gConId.length() >= CON_TRACK_MAX) {
		for (int i = int(gConId.length()) - 1; i >= 0; --i) {
			if (ai.frame - gConTouch[i] > CON_TRACK_STALE) {
				gConId.removeAt(i);
				gConHits.removeAt(i);
				gConHurtAt.removeAt(i);
				gConHp.removeAt(i);
				gConDigUntil.removeAt(i);
				gConNextDig.removeAt(i);
				gConTouch.removeAt(i);
			}
		}
	}
	gConId.insertLast(id);
	gConHits.insertLast(0);
	gConHurtAt.insertLast(0);
	gConHp.insertLast(unit.GetHealthPercent());
	gConDigUntil.insertLast(0);
	gConNextDig.insertLast(0);
	gConTouch.insertLast(ai.frame);
	return int(gConId.length()) - 1;
}

void ConStrikeAt(int i)
{
	++gConHits[i];
	gConHurtAt[i] = ai.frame;
	if ((gConHits[i] >= TROUBLE_HITS) && (ai.frame >= gConDigUntil[i]))
		gConDigUntil[i] = ai.frame + FORTIFY_TIME;
}

// Being refused a site counts the same as being shot at it: both say this
// constructor is not getting to expand here.
void ConStrike(CCircuitUnit@ unit)
{
	ConStrikeAt(ConSlot(unit));
}

bool ConDugIn(CCircuitUnit@ unit)
{
	const int i = ConSlot(unit);
	if ((gConHits[i] > 0) && (ai.frame - gConHurtAt[i] > TROUBLE_WINDOW))
		gConHits[i] = 0;
	const float hp = unit.GetHealthPercent();
	if (hp < gConHp[i] - TROUBLE_HP_DROP)
		ConStrikeAt(i);
	gConHp[i] = hp;
	return ai.frame < gConDigUntil[i];
}

IUnitTask@ Fortify(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	const int i = ConSlot(unit);
	if (ai.frame < gConNextDig[i])
		return null;
	CCircuitDef@ tower = ContestTower(unit);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	AIFloat3 spot;
	if (!StandoffPos(unit, unit.GetPos(ai.frame), spot))
		return null;
	// The bound. Without it this is the version that was reverted -- but the bar
	// now rises with how hard this spot is being contested.
	if (!AreaNeedsDefence(spot, FenceWanted(gConHits[i])))
		return null;
	IUnitTask@ dig = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, spot, SQUARE_SIZE * 2));
	if (dig is null)
		return null;
	NoteDigOrder(spot);
	gConNextDig[i] = ai.frame + FORTIFY_PERIOD;
	++gConFortified;
	if (ai.frame >= gNextFortifyLog) {
		gNextFortifyLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-dig " + unit.circuitDef.GetName()
			+ " hits=" + gConHits[i] + " -> " + tower.GetName()
			+ " fence=" + Military::FenceCountNear(spot, DIG_AREA)
			+ " here=" + DefenceAround(spot)
			+ " fortified=" + gConFortified);
	}
	return dig;
}

// Wounded units already have repair tasks waiting; the constructors were busy
// buying economy.
//
// Two engine paths raise them, both for units we own: CRetreatTask::AssignTo
// enqueues TaskB::Repair(HIGH) for every non-air unit that starts retreating,
// and IFighterTask::OnUnitDamaged enqueues one at NOW for a `heavy` under 90%.
// Both land in CBuilderManager's REPAIR queue, and the ONLY way a constructor is
// ever elected onto one is aiBuilderMgr.DefaultMakeTask -- which sits below the
// optional economy rules in AiMakeTask, so an idle constructor reaches the
// converter first and the queue is never read.
//
// AiTaskAdded is the only place a repair task is visible from here: nothing
// enumerates the task queue and nothing enumerates friendly units. IUnitTask is
// refcounted so a held handle keeps the object alive, and every removal funnels
// through DequeueTask, which calls AiTaskRemoved -- the same contract gMexTasks
// relies on. CBuilderManager::Enqueue returns the existing task for a target
// that already has one, before TaskAdded, so a target cannot be listed twice.
//
// MOBILE targets only. Damaged buildings raise a repair task constantly, and
// including them would hold the gate open for the whole game.
array<IUnitTask@> gArmyRepairs;

// Only constructors near the casualty stand down; the rest of the base keeps
// building. Far enough to cover a fight the constructor is working behind,
// short enough that the walk is not the cost.
const float REPAIR_REACH = 1200.f;
int gRepairHeld = 0;
int gNextRepairLog = 0;

bool RepairNear(CCircuitUnit@ unit)
{
	if (gArmyRepairs.length() == 0)
		return false;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return false;
	for (uint i = 0; i < gArmyRepairs.length(); ++i) {
		IUnitTask@ cand = gArmyRepairs[i];
		if (cand is null)
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where) || (here.distance2D(where) > REPAIR_REACH))
			continue;
		// Somebody is already on it. Self-limiting: the first constructor to take
		// the task closes the gate for everyone else.
		array<CCircuitUnit@>@ busy = cand.GetUnits();
		if ((busy is null) || (busy.length() == 0))
			return true;
	}
	return false;
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
// 	AiDelPoint(lastPos);
// 	lastPos = unit.GetPos(ai.frame);
// 	AiAddPoint(lastPos, "task");

// 	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
// 	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)) {
// 		switch (task.GetBuildType()) {
// 		case Task::BuildType::MEX:
// 			AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 			break;
// 		case Task::BuildType::DEFENCE:
// 			AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 			break;
// 		default:
// 			break;
// 		}
// 	}
// 	return task;
	// Rez bots have no buildoptions and cannot dig in like an ordinary
	// constructor -- Fortify/ContestTower never apply to them -- so a hit here
	// means flee, not fortify. And nothing else in this function ever calls
	// ConDugIn for them, since every rez branch below returns early: a bot
	// that commits to a resurrect has nothing re-checking it while the task
	// runs. apexearth, watching an enemy army arrive live: "eight rez bots
	// resurrecting... they have no time... they keep rezzing... and die...
	// lots of metal around, all could have been taken... our bad logic
	// prevented us from taking that metal and running."
	//
	// RezSpotHot/PreferReclaim below only gate which task gets ASSIGNED, and
	// RezSpotHot's ThreatFor falls back to PastFront() geometry once the
	// position threat map reads zero -- which ThreatFor's own comment says is
	// ~97% of the time -- so an enemy push that has not crossed the front's
	// 72% line still reads "safe" while standing on the bot. ConDugIn's
	// HP-drop tracking is a real positional signal instead: something shot us,
	// HERE. One hit is enough -- unlike an armed constructor, a rez bot cannot
	// answer fire by digging in, only by leaving.
	if (IsRezzer(unit)) {
		ConDugIn(unit);   // side effect: refreshes gConHits/gConHp for this bot
		if (gConHits[ConSlot(unit)] > 0) {
			IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
			if (flee !is null) {
				// TROUBLE_WINDOW holds this true for up to 90s per hit, so without a
				// log throttle this call re-logs on every AiMakeTask re-entry while
				// fleeing -- 399 lines in one 15-minute smoke test. EnqueueRetreat
				// itself is called every time regardless (same as the commander
				// retreat above), on the same assumption that re-enqueuing an
				// existing retreat is a cheap no-op, not a restart.
				if (ai.frame >= gNextRezFleeLog) {
					gNextRezFleeLog = ai.frame + 20 * SECOND;
					AiLog(Factory::T() + "apex: rez bot taking fire, retreating with whatever it banked");
				}
				return flee;
			}
		}
	}

	// Rez bots work the DEFENCE LINE, not wherever they happen to stand.
	//
	// apexearth: "if we are losing then reclaim becomes even more important, as
	// those defenses kill enemies on our border -- we can resurrect or reclaim
	// the metal". The corpses pile up where the fighting is, and the search below
	// only reaches 2200 elmos from the bot itself, so a bot idling at home never
	// finds them. Search from the front instead while we are behind.
	if (IsRezzer(unit) && Military::LosingGround() && (ai.frame >= gNextRezWreck)) {
		AIFloat3 front;
		if (Military::FrontPos(front)) {
			gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
			const AIFloat3 spoil = ai.GetBestWreckPos(front, WRECK_SEARCH, WRECK_MIN);
			if (spoil.x >= 0.f) {
				IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
				if (harvest !is null)
					return harvest;
			}
		}
	}

	// Eat the corpse rather than rebuild it, before the engine gets the chance
	// to queue a resurrect for this bot.
	if (IsRezzer(unit) && (ai.frame >= gNextRezWreck)
			&& (PreferReclaim() || RezSpotHot(unit) || RezBotExposed(unit))) {
		gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
		IUnitTask@ eat = EnqueueWreckReclaim(unit, Task::Priority::HIGH);
		if (eat !is null)
			return eat;
	}

	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	// Only an advanced constructor can build a moho, so it is the one unit that
	// can convert a mex into the biggest economy step available. The two wreck
	// rules below sit ahead of the "never displace real work" line and so can
	// take it off exactly that job -- and the reclaim they hand it is an AREA
	// order (CmdReclaimInArea with CONTROL_KEY, which deliberately ignores the
	// autoreclaimable filter), so it eats whatever is in the circle. apexearth,
	// watching live: "our t2 con is wasting his time reclaiming trees instead
	// of upgrading mexes."
	const bool isAdvCon = !isComm && (unit.circuitDef.costM >= ADV_CON_COST);
	if (isComm) {
		LogCommanderThreat(unit);
		const float hp = unit.GetHealthPercent();
		if (hp < COM_RETREAT_HEALTH) {
			// apexearth, watching live: "once the commander retreats to the back
			// of his base he stays there too long, even while at 50% health he's
			// still cowering there... He should stand behind his t1 lab and help
			// it build stuff!" Previously this fired EnqueueRetreat() every single
			// cycle while hp stayed low, with no check on whether the commander
			// had already reached safety -- so it could never fall through to
			// DefaultMakeTask's own commander logic (CBuilderManager::
			// DefaultMakeTask, MakeCommPeaceTask/MakeCommDangerTask), which
			// already decides hide-vs-assist from LOCAL enemy influence at the
			// commander's current position, not health. Only keep forcing a
			// flee while genuinely still under local threat; once safe, let that
			// existing C++ logic take over instead of looping a bare retreat.
			const float hereThreat = ThreatFor(unit, unit.GetPos(ai.frame));
			if (hereThreat > CON_THREAT_VETO) {
			if (ai.frame >= gNextRetreatLog) {
				gNextRetreatLog = ai.frame + 20 * SECOND;
				AiLog(Factory::T() + "apex: commander retreating at "
					+ formatFloat(hp * 100.f, "", 0, 0) + "% health, frame=" + ai.frame);
			}
			IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
			if (flee !is null)
				return flee;
			}
		}
		// The enemy centroid has come to US. PastFront cannot see this: the base
		// centre sits at fraction ~0 on the home->enemy axis, so it always reads
		// safe, however many enemies are standing in it. apexearth: "sometimes
		// they have a tendency of just running into the center of their base only
		// to get blown up... convince commanders to hide and defend themselves
		// behind their base."
		//
		// So put the commander to work at the BACK WALL instead, using the RearPos
		// the converter rule already uses -- measured away from the enemy, OnMap
		// checked. It relocates by having a job there, which needs no movement
		// command: CmdMoveTo is what UpdateCommanderSafety used and it correlated
		// with 14-17 engine aborts per 20-game run.
		//
		// LIMITATION: GetEnemyPos is the centroid of ALL enemies, so on a big map
		// with spread enemies it can read far away while one of them is in our
		// base. This catches the massed case, not the single raider.
		if (COMM_BACK_WALL_ON && BaseUnderAttack() && (ai.frame >= gNextCommHide)) {
			// Energy full: just leave. The solar is only a way to make the
			// commander WALK somewhere -- it is not wanted for its own sake, and
			// building one on a full bank is pure waste. This fired 21 times in a
			// single game before the check existed. apexearth: "these guys are
			// just making solars while they're on full energy... idk why".
			if (aiEconomyMgr.isEnergyFull) {
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null) {
					gNextCommHide = ai.frame + COMM_HIDE_PERIOD;
					return flee;
				}
			}
			AIFloat3 back;
			if (RearPos(unit, back)) {
				CCircuitDef@ safe = SideDef3(armsolar, corsolar, legsolar);
				if ((safe !is null) && safe.IsAvailable(ai.frame)) {
					IUnitTask@ hide = aiBuilderMgr.Enqueue(TaskB::Common(
							Task::BuildType::ENERGY, Task::Priority::NORMAL,
							safe, back, SQUARE_SIZE * 8));
					if (hide !is null) {
						gNextCommHide = ai.frame + COMM_HIDE_PERIOD;
						AiLog(Factory::T() + "apex: commander to the back wall, enemy "
							+ formatFloat(gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()), "", 0, 0)
							+ " from home");
						return hide;
					}
				}
			}
		}
		// Pull the commander off a site that is in enemy ground. Every other
		// builder already gets this a few lines below, behind `if (!isComm)`, so
		// the commander was the ONE unit that would keep walking into fire.
		// apexearth: "sometimes they have a tendency of just running into the
		// center of their base only to get blown up."
		//
		// Retreat only -- no ContestDefence. A constructor answers danger by
		// building a tower into it; a commander must not stand there doing that.
		// EnqueueRetreat is the same call the health path above already makes for
		// commanders, so this adds no new mechanism. In particular it is NOT
		// CmdMoveTo: that is what UpdateCommanderSafety used, and it correlated
		// with 14-17 engine aborts per 20-game run before being removed.
		{
			IUnitTask@ held = unit.task;
			const string kind = SiteBuildName(held);
			if (kind != "") {
				const float heat = ThreatFor(unit, held.GetBuildPos());
				if (heat > CON_THREAT_VETO) {
					LogConVeto(unit, "comm-abandon", kind, heat);
					IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
					if (flee !is null)
						return flee;
				}
			}
		}
		// Commander-assists-the-first-T2-mex REMOVED, and it must not be rebuilt
		// this way. TaskB::Common leaves SBuildTask.ref.target null, and
		// CBuilderManager::Enqueue's REPAIR case dereferences it immediately:
		//   auto it = repairUnits.find(ti.ref.target->GetId());
		// so a positional REPAIR is an instant access violation. Only
		// TaskB::Repair(priority, target) is safe, and the script cannot obtain
		// the mex nanoframe -- IUnitTask exposes GetBuildPos() and the assigned
		// builders, never the thing being built.

		// A player with no factory left has no way back -- see
		// Factory::HaveAnyFactory()'s own comment for how this was found.
		// Below every safety check above: a commander actively fleeing or
		// hiding from a real threat must keep doing that, not detour to a
		// build site. Gated past the opening (3 min) so this never competes
		// with the normal game-start sequence, which already places the
		// first factory through its own, separately-verified path.
		if (!Factory::HaveAnyFactory() && (ai.frame >= 3 * MINUTE)) {
			// apexearth, watching live: "when we have 0 buildings, we
			// shouldn't start by making a lab... green ran out of
			// everything, his first building to make after that was a
			// botlab, then he started a vehicle lab.... he should get to
			// high safety area and make economy first." This block used to
			// build unconditionally at unit.GetPos() with no safety or
			// economy check at all -- exactly that.
			//
			// Safety: reuse the same ThreatFor check the retreat branches
			// above already use. A wiped-out commander standing in the open
			// must keep fleeing, not stop to build.
			const float hereThreat = ThreatFor(unit, unit.GetPos(ai.frame));
			if (hereThreat > CON_THREAT_VETO) {
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null)
					return flee;
			} else {
				// Economy before factory, once actually safe: a rebuilt
				// factory with no income behind it just gets lost the same
				// way again. Only while a safe, reachable mex spot still
				// exists nearby -- once none is left, fall through to the
				// factory rebuild below rather than stalling forever
				// waiting for a spot that isn't there.
				const int spot = aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame));
				if (spot >= 0) {
					IUnitTask@ mex = aiEconomyMgr.EnqueueMexAt(unit, spot);
					if (mex !is null) {
						AiLog(Factory::T() + "apex: commander economy-first, no factory yet -- mex before rebuild");
						return mex;
					}
				}
			}

			CCircuitDef@ lab = Factory::T1BotLab();
			if ((lab !is null) && lab.IsAvailable(ai.frame)) {
				IUnitTask@ rebuild = aiBuilderMgr.Enqueue(TaskB::Common(
						Task::BuildType::FACTORY, Task::Priority::HIGH,
						lab, unit.GetPos(ai.frame), 0.f));
				if (rebuild !is null) {
					AiLog(Factory::T() + "apex: commander rebuilding a factory -- we have none");
					return rebuild;
				}
			}
		}
	}
	// Already walking to a site that is now inside enemy fire. IBuilderTask::
	// Reevaluate calls this hook on every task update for as long as the builder
	// is away from its build position, so the whole walk is covered -- but it
	// swaps the unit's task only when what we hand back differs in build type,
	// so a refusal here has to be a real task rather than null.
	if (!isComm) {
		IUnitTask@ held = unit.task;
		const string kind = SiteBuildName(held);
		if (kind != "") {
			float heat = ThreatFor(unit, held.GetBuildPos());
			if (kind == "mex")
				heat = MexHeat(held.GetBuildPos(), heat);
			if (heat > CON_THREAT_VETO) {
				++gConAbandoned;
				ConStrike(unit);
				LogConVeto(unit, "abandon", kind, heat);
				// A defence post and a retreat both differ in build type; another
				// mex would not, so the reroute belongs on the refuse path only.
				IUnitTask@ post = ContestDefence(unit, kind, heat, held.GetBuildPos());
				if (post !is null)
					return post;
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null)
					return flee;
			}
		} else if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::RECLAIM))
		{
			// apexearth, watching live: "constructors seem to want to roam
			// out towards the enemy army to reclaim ... they all died."
			// SiteBuildName deliberately excludes RECLAIM (every wreck-
			// chasing dispatch point already threat-checks the destination
			// before sending a constructor there -- see EnqueueWreckReclaim/
			// the rich-pile block), so this abandon-and-recheck loop above
			// never covered reclaim: a destination checked safe ONCE at
			// dispatch was never re-checked again during the walk or while
			// reclaiming. An active battlefield's safety can flip in the
			// time it takes to walk there -- there was no path back once it
			// did. Same abandon pattern as mex/build above, no
			// ContestDefence (building a tower at a corpse pile doesn't fit
			// the same shape as holding a mex).
			const float heat = ThreatFor(unit, held.GetBuildPos());
			if (heat > CON_THREAT_VETO) {
				++gConAbandoned;
				ConStrike(unit);
				LogConVeto(unit, "abandon", "reclaim", heat);
				IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
				if (flee !is null)
					return flee;
			}
		}
	}

	// After the reactive branches above, before ordinary work. It pre-empts
	// DefaultMakeTask, which is where mex upgrades live, so it is bounded twice
	// over: one every 25 seconds, and never when it would leave us short of
	// builders. Twelve rules pre-empting here with neither bound is what cut metal
	// production 4.3x.
	// DO NOT DISPLACE WORK ALREADY IN PROGRESS.
	//
	// This hook is not only called for an idle builder: IBuilderTask::Reevaluate
	// calls it on every task update for as long as the builder is away from its
	// build position, and the engine swaps the unit's task whenever what we hand
	// back differs in BUILD TYPE. So every optional rule below -- AA, the gun,
	// converters, nanos, fusions, dig-ins -- could yank a constructor off a site
	// it was walking to, leaving a claimed task nobody works.
	// apexearth: "I noticed more recently buildings getting started and then
	// canceled... maybe you have some logic that isn't checking if there's
	// already a task and you are replacing tasks."
	// Measured: 60 live MEX tasks with 60 of them unworked, repeatedly.
	// The veto/abandon check above has already run, so anything still held here
	// is work the AI still considers safe and wants finished.
	if (!isComm) {
		IUnitTask@ busy = unit.task;
		if ((busy !is null) && (SiteBuildName(busy) != ""))
			return busy;
	}

	if (!isComm) {
		// con-heal (RepairNear) stays reflexive and ungated -- it answers
		// something happening now (a nearby wounded unit) rather than
		// claiming a slice of surplus, per docs/12-build-phases.md's own
		// split of phase-gated (investment) vs never-phase-gated (reflexive)
		// rules. RepairNear returns true when it has already handled (or is
		// standing down for) a nearby repair.
		if (RepairNear(unit)) {
			++gRepairHeld;
			if (ai.frame >= gNextRepairLog) {
				gNextRepairLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: con-heal " + unit.circuitDef.GetName()
					+ " stands down, repairs=" + gArmyRepairs.length()
					+ " held=" + gRepairHeld);
			}
		}
		else {
			// CheapAA carved out of the phase gate below, 2026-08-05: apexearth
			// live-watched a Legion game with aaT1=0 at 7+ minutes against active
			// mosquito-gunship pressure, and the phase telemetry confirms why --
			// gHaveT2 (and so gLastPhase>=4) stayed at 0 for the entire pre-T2
			// window every game, so CheapAA was structurally unreachable exactly
			// when hit-and-run air is cheapest to punish. Unlike HeavyAA/Pulsar/
			// the eco cluster below (open-ended investment, correctly deferred
			// until the economy has actually teched), CheapAA is already a
			// tightly self-gated reactive deterrent: it requires enemyAir >= 1
			// (a real observed threat, not a forecast), caps at AA_MIN..AA_MAX,
			// and is throttled by AA_PERIOD -- it cannot crowd out expansion the
			// way the rest of this cluster measurably did.
			IUnitTask@ aa = CheapAA(unit);
			if (aa !is null)
				return aa;
			// BUILD_PHASE gate on the remaining optional economy cluster.
			// Progression, 2026-08-04: phase >= 2 (mex >= 4) reverted, 0 wins in
			// 13 decided. phase >= 3 (RushReady) confirmed a real improvement, 5
			// wins in 22 decided (22.7%) across 4 batches. phase >= 4 (gHaveT2 --
			// an advanced factory actually finished, not just afforded) measured
			// BEST: 6 wins in 10 decided (60.0%, 95% CI 31.3%-83.2%) across 2
			// batches, P(>=6 wins in 10 | baseline true rate 7.9%) = 0.00004, and
			// most games (14/16 in the larger batch) ran the full time limit
			// competitively rather than being decided either way. See
			// notes/open-issues.md issue 15 for the full data and CHANGES.md for
			// the summary. Before an advanced factory exists, a constructor's
			// only job is expansion and reaching T2; HeavyAA, Pulsar, EnergyConverter
			// and the nano/fusion block below can all wait for an economy that has
			// actually teched, not merely one that could afford to.
			//
			// EnergyConverter was carved out of this gate earlier tonight (same
			// evidence shape as CheapAA -- self-gated on real spare energy, not a
			// forecast) after apexearth asked "why no energy converters?" at 9
			// minutes. REVERTED, same session, same night: apexearth immediately
			// afterward, watching mex expansion specifically: "I'd say we do build
			// too many cons... but huge issue is they just aren't placing enough
			// priority on building mexes." EnergyConverter was checked and could
			// claim a constructor's assignment BEFORE DefaultMakeTask (which is
			// what actually creates new mex-expansion tasks, Priority::HIGH in
			// EconomyManager.cpp) ever ran -- so unblocking it pre-T2 meant it
			// could now win the same idle-constructor pool mex expansion needs,
			// in exactly the 0-9 minute window this complaint is about. Mex
			// expansion matters more than energy conversion; reverted to
			// gLastPhase>=4 until a fix that does not compete with mex for
			// constructor time exists.
			if (Factory::gLastPhase >= 4) {
				IUnitTask@ heavyAa = HeavyAA(unit);
				if (heavyAa !is null)
					return heavyAa;
				if (!Factory::EcoLeadActive()) {
					IUnitTask@ gun = Pulsar(unit);
					if (gun !is null)
						return gun;
				}
				IUnitTask@ block = EcoConverters(unit);
				if (block !is null)
					return block;
				IUnitTask@ conv = EnergyConverter(unit);
				if (conv !is null)
					return conv;
				IUnitTask@ nano = EcoNano(unit);
				if (nano !is null)
					return nano;
				IUnitTask@ fus = EcoFusion(unit);
				if (fus !is null)
					return fus;
			}
		}
	}

	// Its own recent history says it cannot expand, so stop sending it out. The
	// tower it puts up instead is what makes the ground usable later -- but only
	// where something is not already standing; see AreaNeedsDefence.
	if (!isComm && !Factory::EcoLeadActive() && ConDugIn(unit)) {
		IUnitTask@ dig = Fortify(unit);
		if (dig !is null)
			return dig;
	}

	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);

	// apexearth, watching live: "commanders are often walking unreasonably
	// long distances to get the reclaim when their time would be better
	// spent getting mexes... once they have mexes reclaim is fine." The
	// isComm gates on the wreck blocks below only stop the commander from
	// CREATING a new reclaim task; they cannot stop CBuilderManager::
	// MakeCommPeaceTask (native C++, runs inside DefaultMakeTask above) from
	// picking up a Reclaim task some OTHER unit already enqueued into the
	// shared buildTasks pool. Those reclaim tasks carry Task::Priority::HIGH,
	// which dominates that picker's distance-cost weighting regardless of how
	// far away the pile actually is -- so the commander can get pulled onto
	// someone else's reclaim job from clear across the map. Reject it while
	// there is still an unclaimed safe mex spot nearby; once the mex phase is
	// done, let it through same as everyone else.
	if (isComm && (task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() == Task::BuildType::RECLAIM)
		&& (aiEconomyMgr.FindOpenMexSpot(unit, unit.GetPos(ai.frame)) >= 0))
	{
		@task = null;
	}

	// General form of the veto above: keep what the commander is already
	// doing rather than swapping to a different build type. `unit.task` is
	// still the OLD task here -- Reevaluate only swaps it once this function
	// returns a differing build type -- so this compares current against
	// proposed. Danger is handled earlier, by the comm-abandon retreat.
	if (isComm && (task !is null) && (task.GetType() == Task::Type::BUILDER)) {
		IUnitTask@ held = unit.task;
		const string heldKind = SiteBuildName(held);
		if ((heldKind != "") && (held.GetBuildType() != task.GetBuildType())
			&& (ThreatFor(unit, held.GetBuildPos()) <= CON_THREAT_VETO))
		{
			LogConVeto(unit, "comm-hold", heldKind, 0.f);
			@task = null;
		}
	}

	// apexearth: "have our units never assist another unit build something if
	// we are out of a resource (<5%). This should help encourage getting
	// mexes." Only about JOINING someone else's build -- task.GetUnits() is
	// the set of units already on it, so an empty list means this unit would
	// be starting fresh, not assisting, and is left alone. Mex/mex-upgrade
	// tasks are exempt: assisting one of those is exactly the behavior a
	// resource crunch should produce more of, not less.
	// A fresh-context agent flagged this (added in 6214df3, smoke-tested
	// only at the time) as a possible contributor to Cortex's drop from a
	// documented 96.3% peak (2a9613e) to 68.8%. Tested directly: disabling
	// this AND the factory-cap exemption above for a 16-game Cortex mirror
	// (same seeds as the 68.8% baseline) gave 62.5% -- no recovery.
	// Hypothesis rejected by data; restored.
	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() != Task::BuildType::MEX)
		&& (task.GetBuildType() != Task::BuildType::MEXUP)
		&& (task.GetUnits().length() > 0))
	{
		const bool metalCrit = (aiEconomyMgr.metal.storage > 0.f)
				&& (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * RESOURCE_CRISIS_FRAC);
		const bool energyCrit = (aiEconomyMgr.energy.storage > 0.f)
				&& (aiEconomyMgr.energy.current < aiEconomyMgr.energy.storage * RESOURCE_CRISIS_FRAC);
		if (metalCrit || energyCrit) {
			@task = null;
		}
	}

	// Refusing to accept the job in the first place. Reached from CIdleTask, where
	// returning null simply leaves the unit idle until the next idle sweep.
	if (!isComm) {
		// Jammer area-clustering veto (see AreaHasJammer's own comment). Checked
		// before SiteBuildName's whitelist, since jammers fall outside it (kind
		// would be "" and none of the checks below would ever see this task).
		// GetBuildPos() is only valid for BUILDER-type tasks -- SiteBuildName
		// guards this same way; missing it here crashed the native DLL at
		// ~1.2 minutes in every game of an 8-game batch (armada-bisect-
		// outrange-revert-8) the first time this path was actually exercised.
		if ((task !is null) && (task.GetType() == Task::Type::BUILDER) && IsJammerDef(task.buildDef)) {
			const AIFloat3 jsite = task.GetBuildPos();
			if (AreaHasJammer(jsite)) {
				++gConRefused;
				LogConVeto(unit, "refuse", "jammer-cluster", 0.f);
				@task = null;
			} else {
				gJammerPos.insertLast(jsite);
				gJammerAt.insertLast(ai.frame);
			}
		}
		string kind = SiteBuildName(task);
		// Cap redundant same-type factories. tools/combat_events.py (built this
		// session) caught what the earlier bot-lab-request-cooldown fix
		// (BOTLAB_REQUEST_COOLDOWN) missed: that fix only gates the ONE script
		// branch that asks for a bot lab when we have none, but corlab kept
		// getting placed again and again well after the first one existed --
		// 8, even 10 placements inside a few minutes for a single
		// healthy-economy player, gaps as short as 6 seconds apart. Nothing
		// that fast is a rebuild-after-loss; this can only be the stock
		// engine's own DefaultMakeTask independently offering the same
		// factory type to every idle constructor, with nothing on the script
		// side capping how many of one type we actually want. CCircuitDef is
		// owned per CCircuitAI instance (see Air.as's own note on this), so
		// .count here is THIS player's own standing+in-progress count, not
		// the team's.
		// apexearth's T2 rush stalling at 18m traced (fresh-context agent
		// review, 2026-08-06) to exactly this cap: a constructor legitimately
		// pulled off the advanced-lab build by real threat (con-veto abandon,
		// threat=12) tried to resume the SAME single in-progress build once
		// safe, and this cap refused it every time as if it were requesting
		// a brand new redundant factory -- rerouting to factory-cap-fallback-
		// mex instead of finishing the T2 lab, repeatedly, well past the
		// factory-cap threat window's own frame. task.GetUnits() is the set
		// of units ALREADY on this task; a nonzero count means this is a
		// build already underway, not a new request, and can't be redundant
		// by definition -- exempt it from both the count cap and the spacing
		// cooldown, which exist only to stop DefaultMakeTask independently
		// offering a brand new factory to every idle constructor.
		//
		// A different fresh-context agent later flagged this exemption as a
		// possible contributor to Cortex's drop from a documented 96.3% peak
		// (2a9613e) to 68.8%. Tested directly: reverting this AND the
		// resource-crisis block below to a 16-game Cortex mirror (same
		// seeds as the 68.8% baseline) gave 62.5% -- no recovery, slightly
		// worse if anything. Hypothesis rejected by data; restored.
		if ((kind == "factory") && (task !is null) && (task.GetUnits().length() == 0)) {
			const CCircuitDef@ wantFac = task.buildDef;
			if (wantFac !is null) {
				const int id = wantFac.id;
				const bool tracked = (id >= 0) && (uint(id) < gNextFactoryRequest.length());
				const bool tooSoon = tracked && (ai.frame < gNextFactoryRequest[id]);
				if ((wantFac.count >= FACTORY_TYPE_CAP) || tooSoon) {
					++gConRefused;
					LogConVeto(unit, "refuse", "factory-cap", float(wantFac.count));
					// Previously just @task = null here, which (per CIdleTask's own
					// contract, see the function-level comment above) leaves the
					// unit fully idle until the next idle sweep. Redirect to
					// expansion first -- see FallbackMex's own comment for the
					// traced mechanism and evidence.
					IUnitTask@ fallback = FallbackMex(unit);
					@task = fallback;
					if (fallback !is null)
						kind = "mex";
				} else if (tracked) {
					gNextFactoryRequest[id] = ai.frame + FACTORY_REQUEST_SPACING;
				}
			}
		}
		if ((task !is null) && (kind != "")) {
			const AIFloat3 site = task.GetBuildPos();
			float heat = ThreatFor(unit, site);
			if (kind == "mex")
				heat = MexHeat(site, heat);
			if (heat > CON_THREAT_VETO) {
				++gConRefused;
				LogConVeto(unit, "refuse", kind, heat);
				// CIdleTask assigns whatever comes back, so unlike the abandon
				// path above this one can hand over a task the engine already
				// holds -- a mex the same constructor reads as cold.
				if (kind == "mex") {
					IUnitTask@ other = SaferMex(unit, task);
					if (other !is null)
						return other;
				}
				IUnitTask@ post = ContestDefence(unit, kind, heat, task.GetBuildPos());
				if (post !is null)
					return post;
				// ConStrike (which can trigger Fortify/dig-in once TROUBLE_HITS is
				// reached) previously fired unconditionally on every refusal, even
				// when SaferMex/ContestDefence immediately found a working
				// alternative one line later -- three routine successful reroutes
				// (business as usual, not persistent blocking) could trip the same
				// threshold as three genuine repeated failures. apexearth, watching
				// a game: "i see us making too many t1.5 defenses and advanced
				// energy converters before we've even captured all our backline
				// mexes." Moved to only the true-failure path, where no alternative
				// was found at all.
				ConStrike(unit);
				@task = null;
			}
		}
	}
	// Observed: a commander stands next to reclaimable metal with an empty bank
	// and keeps its build task instead of eating it. It is not IDLE -- it holds a
	// task it cannot afford -- so the idle-only path below never fired. When
	// metal is actually empty, reclaiming beats standing still: it is the only
	// thing that unblocks the task it is already holding.
	// DIAGNOSTIC, apexearth: "We're totally out of metal and we have three
	// construction turrets helping to build something, but we don't even have
	// the metal to build it. One of those conturrets could have been
	// reclaiming... basically - if you have <2% metal and reclaim is in your
	// vicinity - reclaim!" IBuilderTask::Reevaluate's own doc comment says it
	// fires "for as long as the builder is away from its build position" --
	// unclear whether an ALREADY-ARRIVED, actively-assisting nano turret ever
	// reaches AiMakeTask again at all, as opposed to a mobile constructor
	// walking to a site. Logging whether this branch is even entered for a
	// static/turret unit while metal-empty, before building a new redirect
	// mechanism blind.
	//
	// Both this and the rich-pile block below are now isComm-gated. They were
	// not until 2026-08 -- but GetWreckValueAt/GetBestWreckPos were dead all
	// last session (CircuitAI::metalRes only ever assigned on resign, so both
	// always returned zero/invalid), so nothing chased a pile from here for
	// ANYONE, commander included, and that masked this being reachable at all.
	// Fixing the underlying binding unmasked it immediately: apexearth,
	// watching live, "something makes our commanders all run out to the front
	// line - maybe they're going for the reclaim - they should prioritize
	// making those early game mexes." The rich-pile block below is explicitly
	// the one case in this function that DISPLACES an already-assigned task --
	// exactly the commander's early mex task from DefaultMakeTask.
	if (!isComm && aiEconomyMgr.isMetalEmpty && (ai.frame >= gNextMetalEmptyDiag)) {
		gNextMetalEmptyDiag = ai.frame + 10 * SECOND;
		AiLog(Factory::T() + "apex: metal-empty-diag " + unit.circuitDef.GetName()
			+ " static=" + (!unit.circuitDef.IsMobile() ? "1" : "0")
			+ " hasTask=" + ((unit.task !is null) ? "1" : "0"));
	}
	if (!isComm && !isAdvCon && aiEconomyMgr.isMetalEmpty && (ai.frame >= gNextWreck)) {
		gNextWreck = ai.frame + 3 * SECOND;
		const AIFloat3 here = unit.GetPos(ai.frame);
		const AIFloat3 near = ai.GetBestWreckPos(here, WRECK_SEARCH, 15.f);
		// apexearth, watching live: "even our advanced cons are chasing wrecks
		// which are dangerous." Same fix as the commander exclusion above,
		// generalized: unmasked by the same metalRes fix, this now finds real
		// piles and had no idea whether the pile sits somewhere safe. Reuse
		// the same ThreatFor/CON_THREAT_VETO check mex dispatch already uses.
		if ((near.x >= 0.f) && (ThreatFor(unit, near) <= CON_THREAT_VETO)) {
			NoteWreckSeen(ai.GetWreckValueAt(near, WRECK_RADIUS));
			IUnitTask@ rec = aiBuilderMgr.Enqueue(TaskB::Reclaim(
					Task::Priority::HIGH, near, 400.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
			if (rec !is null)
				return rec;
		}
	}
	// The one case that DOES displace real work. Everything above this point is
	// strictly additive by design; a rich corpse pile next to us is the exception,
	// because the metal it returns exceeds anything the interrupted task was
	// producing in the same seconds -- true for an ordinary constructor, not for
	// a commander whose displaced task is the early mex expansion the team's
	// whole economy depends on, nor for an advanced one whose displaced task is
	// a moho. See the isComm note above the metal-empty block.
	if (!isComm && !isAdvCon && (ai.frame >= gNextWreck)) {
		const AIFloat3 self = unit.GetPos(ai.frame);
		if (OnMap(self)) {
			// Gate on the field's TOTAL value, then aim at its richest body so the
			// reclaim circle lands on the corpses rather than on a tree.
			const float pile = ai.GetWreckValueAt(self, WRECK_RICH_R);
			NoteWreckSeen(pile);
			const AIFloat3 rich = (pile >= WRECK_RICH)
					? ai.GetBestWreckPos(self, WRECK_RICH_R, 15.f)
					: AIFloat3(-1.f, 0.f, -1.f);
			// Same threat check as above -- a rich pile is worth an interrupted
			// task, it is not worth walking an advanced constructor into fire
			// for. Checked at the PILE's position, not the constructor's
			// current one: a con already standing somewhere safe should not
			// walk toward a hot pile just because it can see it.
			if ((rich.x >= 0.f) && (ThreatFor(unit, rich) <= CON_THREAT_VETO)) {
				gNextWreck = ai.frame + 3 * SECOND;
				IUnitTask@ fat = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, rich, 1000.f, WRECK_TIMEOUT,
						WRECK_RADIUS, true));
				if (fat !is null) {
					if (ai.frame >= gNextRichLog) {
						gNextRichLog = ai.frame + 30 * SECOND;
						AiLog(Factory::T() + "apex: rich-wreck reclaim pile=" + formatFloat(pile, "", 0, 0));
					}
					return fat;
				}
			}
		}
	}

	if (task !is null)
		return task;   // strictly additive: never displace real work

	// Last resort: everything above declined and we still have metal. Buys
	// energy, not defence -- what this spends is constructor time, and a con
	// part-way through a 680-metal/14,000-energy turret cannot take the mex
	// upgrade that frees up thirty seconds later. See CHANGES.md 2026-08-07.
	if (!isComm && !aiEconomyMgr.isMetalEmpty && gHomeSet
		&& !EnergyWasting() && (ai.frame >= gNextMetalFullDef))
	{
		CCircuitDef@ gen = Factory::gHaveT2
				? SideDef3(armadvsol, coradvsol, legadvsol)
				: SideDef3(armsolar, corsolar, legsolar);
		if ((gen is null) || !gen.IsAvailable(ai.frame))
			@gen = SideDef3(armsolar, corsolar, legsolar);
		if ((gen !is null) && gen.IsAvailable(ai.frame)) {
			IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY,
					Task::Priority::NORMAL, gen, gHomePos, SQUARE_SIZE * 8));
			if (post !is null) {
				gNextMetalFullDef = ai.frame + METAL_FULL_DEF_PERIOD;
				AiLog(Factory::T() + "apex: metal-full-fallback " + unit.circuitDef.GetName()
					+ " -> " + gen.GetName());
				return post;
			}
		}
	}

	// Clearing our own obsolete buildings. Both cases are the same act -- pick
	// one of OUR structures and reclaim it -- so they share ObsoleteReclaim();
	// what differs is only which defs and where. See its comment for the gates.
	if (!isComm) {
		IUnitTask@ tidy = ObsoleteReclaim(unit);
		if (tidy !is null)
			return tidy;
	}

	// Reached by an idle builder, and by one whose only offer was refused above.
	// Rate-limited so a field of them does not each run their own scan every tick.
	// isComm-gated same as the rest of this function's wreck-chasing -- this
	// was the one remaining ungated path that could hand a self-initiated
	// reclaim task back to a commander whose real task was rejected above.
	if (isComm || (ai.frame < gNextWreck))
		return task;
	gNextWreck = ai.frame + 3 * SECOND;   // corpses decay; do not dawdle

	return EnqueueWreckReclaim(unit, Task::Priority::NORMAL);
}

// The first T2 mex is what pays for everything after it, so put the commander on
// it until it is up. The script cannot address the nanoframe directly -- IUnitTask
// exposes only the build position, and a MEXUP task carries a spot id we cannot
// read -- so this is a positional REPAIR, which in Spring is exactly what
// assisting a nanoframe is. Same shape as the wreck reclaim above, which already
// enqueues a positional task with no buildDef.
AIFloat3 gMexUpPos;
bool gMexUpActive = false;
int  gCommAssistNext = 0;

void AiTaskAdded(IUnitTask@ task)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	const int bt = task.GetBuildType();
	if (bt == Task::BuildType::MEXUP) {
		gMexUpPos = task.GetBuildPos();
		gMexUpActive = true;
	} else if (bt == Task::BuildType::MEX) {
		gMexTasks.insertLast(task);
	} else if (bt == Task::BuildType::REPAIR) {
		CCircuitUnit@ hurt = task.target;
		if ((hurt !is null) && hurt.circuitDef.IsMobile())
			gArmyRepairs.insertLast(task);
	}
// 	if (task.GetType() != Task::Type::BUILDER)
// 		return;
// 	switch (task.GetBuildType()) {
// 	case Task::BuildType::ENERGY: {
// 		if (gPauseCnt == 0) {
// 			string name = task.GetBuildDef().GetName();
// 			if ((name == "armfus") || (name == "armafus") || (name == "corfus") || (name == "corafus")) {
// 				AiPause(true, "energy");
// 				++gPauseCnt;
// 			}
// 			AiAddPoint(task.GetBuildPos(), name);
// 		}
// 	} break;
// 	case Task::BuildType::FACTORY:
// 	case Task::BuildType::NANO:
// 	case Task::BuildType::STORE:
// 	case Task::BuildType::PYLON:
// 	case Task::BuildType::GEO:
// 	case Task::BuildType::GEOUP:
// 	case Task::BuildType::DEFENCE:
// 	case Task::BuildType::BUNKER:
// 	case Task::BuildType::BIG_GUN:
// 	case Task::BuildType::RADAR:
// 	case Task::BuildType::SONAR:
// 	case Task::BuildType::CONVERT:
// 	case Task::BuildType::MEX:
// 	case Task::BuildType::MEXUP:
// 		AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 		break;
// 	case Task::BuildType::REPAIR:
// 		AiAddPoint(task.GetBuildPos(), "rep");
// 		break;
// 	case Task::BuildType::RECLAIM:
// 		AiAddPoint(task.GetBuildPos(), "rec");
// 		break;
// 	case Task::BuildType::RESURRECT:
// 		AiAddPoint(task.GetBuildPos(), "res");
// 		break;
// 	case Task::BuildType::TERRAFORM:
// 		AiAddPoint(task.GetBuildPos(), "ter");
// 		break;
// 	default:
// 		break;
// 	}
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	const int bt = task.GetBuildType();
	if (bt == Task::BuildType::MEXUP) {
		gMexUpActive = false;
	} else if (bt == Task::BuildType::MEX) {
		for (uint i = 0; i < gMexTasks.length(); ++i) {
			if (gMexTasks[i] is task) {
				gMexTasks.removeAt(i);
				break;
			}
		}
	} else if (bt == Task::BuildType::REPAIR) {
		// By identity, not by target: the target may already be dead here.
		for (uint i = 0; i < gArmyRepairs.length(); ++i) {
			if (gArmyRepairs[i] is task) {
				gArmyRepairs.removeAt(i);
				break;
			}
		}
	}
// 	if (task.GetType() != Task::Type::BUILDER)
// 		return;
// 	switch (task.GetBuildType()) {
// 	case Task::BuildType::FACTORY:
// 	case Task::BuildType::NANO:
// 	case Task::BuildType::STORE:
// 	case Task::BuildType::PYLON:
// 	case Task::BuildType::ENERGY:
// 	case Task::BuildType::GEO:
// 	case Task::BuildType::GEOUP:
// 	case Task::BuildType::DEFENCE:
// 	case Task::BuildType::BUNKER:
// 	case Task::BuildType::BIG_GUN:
// 	case Task::BuildType::RADAR:
// 	case Task::BuildType::SONAR:
// 	case Task::BuildType::CONVERT:
// 	case Task::BuildType::MEX:
// 	case Task::BuildType::MEXUP:
// 	case Task::BuildType::REPAIR:
// 	case Task::BuildType::RECLAIM:
// 	case Task::BuildType::RESURRECT:
// 	case Task::BuildType::TERRAFORM:
// 		AiDelPoint(task.GetBuildPos());
// 		break;
// 	default:
// 		break;
// 	}
}

// Commander safety, issued as a raw move order rather than a task.
//
// Commander survival is the measured determinant of these games: 2.3-3.0 lost
// when we lose, 0.0-1.3 when we win, across four runs. Every commander.json
// lever was tried individually and none moved it, because `hide` needs elapsed
// time AND a global threat bar while these deaths happen with the commander out
// working somewhere specific.
//
// Expressing the response as a task returned from AiMakeTask lost 0-20 with
// metal at 6,631 -- that hook is the ONLY place the commander gets work, so a
// retreat task replaces everything it would have built. CmdMoveTo issues the
// order directly and leaves the task slot alone, so it keeps its job and simply
// walks away from the danger first.
CCircuitUnit@ gComm = null;
AIFloat3 gHomePos;
bool gHomeSet = false;
const float COM_DANGER_RADIUS = 800.f;
const float COM_DANGER_FOES   = 3.f;   // a lone scout reads 1; a raid is 3+
int gNextComMove = 0;

// UpdateCommanderSafety() REMOVED, not merely disabled.
//
// Exit-code audit: aborts (exit -1003) went from 0-2 per 20-game run to 14-17
// the moment it landed, and stayed there for four consecutive runs. The engine
// was dying, so the "3-1, commanders solved" result came from the few games that
// survived, and the 82% I reported as mutual turtling was 82% aborted.
//
// Unsafe is one of: CmdMoveTo issued outside a task context, or GetEnemyCostAt's
// GetEnemyUnitsIn walk. Both bindings remain registered but nothing calls them,
// so no script path can reach either. They need isolating and testing one at a
// time in a throwaway variant before anything depends on them again.

// Diagnostic only. ai.GetBuilderThreatAt reads the engine's own per-position
// threat map -- the thing mobileThreat (a global scalar) and GetEnemyCostAt (a
// unit count, which crashed) were both standing in for. Log it where the
// commander actually is, so a retreat threshold can be set from measurement
// rather than invented. Nothing acts on this yet: the last two attempts to act
// immediately on a new signal cost 0-20 and four days of wrong conclusions.
// Commander retreat, triggered on HEALTH rather than position threat.
//
// Measured across 10 games: ai.GetBuilderThreatAt readings within 30s of a
// commander dying were LOWER than baseline (3% nonzero vs 8%). The map is not
// broken -- it is being sampled in the wrong place. apexearth: "sometimes a com
// dies to that 1 or 2 last plasma shots from a distance while it is running
// away". The killer is at range, so the victim's own position reads clean right
// up until it dies.
//
// Health loss is unambiguous and fires whether the shooter is adjacent or 800
// elmos off. 60% is a reasoned starting point, not a measured one: retreating at
// 25% is too late when the last two shots can finish you mid-flight, so the bar
// has to leave enough health to escape ON. Also: "the risk should probably be
// divided by their % of health" -- at 60% the same incoming fire is already
// worth far more than at full.
//
// Unlike the earlier position-based attempt -- which fired whenever 3+ enemies
// were within 800, returned a Patrol task from AiMakeTask, and destroyed the
// economy (0-20, metal 6,631) -- this fires only when the commander has actually
// been hurt, which is rare. A commander that is being shot SHOULD stop building.
// 0.85, was 0.60. At 0.60 the commander stood there until it had lost FORTY
// PERCENT of its health, by which point it is inside an army. Measured in a
// watched 4v4: three commanders died and this fired once. 0.85 means it leaves
// on the first real damage, which is the whole point -- apexearth: "our guys are
// still just standing in the middle of the base about to be killed, like a bunch
// of idiots."
const float COM_RETREAT_HEALTH = 0.85f;
int gNextRetreatLog = 0;

int gNextThreatLog = 0;

// Health added alongside threat (both were logged separately before, neither
// with the other). There is no AiUnitDestroyed hook in this script -- the
// engine warns "Script: 'void AiUnitDestroyed(CCircuitUnit@)' not found!" at
// every match start -- so the only way to see a commander's last moments from
// the infolog is the gap between this heartbeat's last line and the point it
// stops. A health trace turns "the log stopped at 13.3m" into "health was
// still N% at 13.3m" or "already retreating and dropping fast", which is the
// difference between "died suddenly" and "the existing retreat failed slowly".
void LogCommanderThreat(CCircuitUnit@ unit)
{
	if (ai.frame < gNextThreatLog)
		return;
	gNextThreatLog = ai.frame + 30 * SECOND;
	const AIFloat3 here = unit.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: comm threat=" + formatFloat(ai.GetBuilderThreatAt(here), "", 0, 2)
		+ " hp=" + formatFloat(unit.GetHealthPercent() * 100.f, "", 0, 0)
		+ " frame=" + ai.frame);
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// Before every early return below, or a fusion finishing while some other
	// branch claims the unit is never recorded.
	if (IsFusion(unit.circuitDef))
		gFusions.insertLast(unit);
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask) && (gComm is null)) {
		@gComm = unit;
		gHomePos = unit.GetPos(ai.frame);
		gHomeSet = true;
	}
	// ai.GiveUnits unregisters the unit and fires its removal event from inside
	// the call, so once it returns true this unit is already gone. Recording it
	// below would park a foreign unit in an energizer slot whose AiUnitRemoved
	// has been and gone, wedging that slot for the rest of the game.
	// Anything advanced-constructor sized that we KEEP means we are covered.
	// Tracked separately from gGotAdvCon, which only records a gift arriving: a
	// player that built its own is equally covered and must not build more.
	if ((usage == Unit::UseAs::BUILDER)
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		&& (unit.circuitDef.costM >= ADV_CON_COST))
	{
		gHaveAdvCon = true;
	}
	if (ShareAdvCon(unit, usage))
		return;   // handed to an ally; it is not ours to count
	if ((usage == Unit::UseAs::BUILDER)
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		&& (unit.circuitDef.costM >= ADV_CON_COST))
	{
		++gAdvConCount;
	}

	if (usage == Unit::UseAs::REZZER) {
		const int rid = unit.circuitDef.id;
		if ((rid >= 0) && (uint(rid) < gRezzerDefs.length()))
			gRezzerDefs[rid] = true;
		return;
	}

	const CCircuitDef@ cdef = unit.circuitDef;
	if (usage != Unit::UseAs::BUILDER || cdef.IsRoleAny(Unit::Role::COMM.mask))
		return;

	// A gifted advanced constructor materialises where it stood, in the lead's
	// base, and the receiving AI then picks its own work -- observed live, an
	// ally used one to start a mex on the front line. Nothing on the giving side
	// can prevent that: the whole binding surface has no way to move, order or
	// otherwise steer a unit, ai.GiveUnits takes no position, and the receiver's
	// UnitGiven issues CmdStop on arrival anyway.
	//
	// The receiver runs this same script, though, and it can tell the unit was a
	// gift: with no advanced factory of our own we cannot have built an advanced
	// constructor. Unit::Attr::BASE is the one lever that changes what it then
	// does. DefaultMakeTask routes a BASE unit to MakeEnergizerTask, which walks
	// task types in a fixed order instead of picking purely by distance -- energy,
	// storage, factory and nano first, then MEXUP ahead of MEX -- caps everything
	// after those four to 2000 elmos of the unit and of base, and drops any
	// position under enemy influence outright, where the ordinary builder path
	// only drops it when threat and influence and low build-power all coincide.
	// Upgrading the mexes we already hold is what the gift was for; opening a new
	// spot at the front is what it was not.
	if (!Factory::gHaveT2 && (cdef.costM >= ADV_CON_COST)) {
		unit.AddAttribute(Unit::Attr::BASE.type);
		AiLog(Factory::T() + "apex: received adv con " + cdef.GetName()
			+ " -- holding it to base work");
		return;
	}

	// constructor with BASE attribute is assigned to tasks near base
	if (cdef.costM < 200.f) {
		if (energizer1 is null
			&& (uint(cdef.count) > aiMilitaryMgr.GetGuardTaskNum() || cdef.IsAbleToFly()))
		{
			@energizer1 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	} else {
		if (energizer2 is null) {
			@energizer2 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// Losing one has to re-open the slot, or a player that loses its advanced
	// constructors never replaces them.
	if ((usage == Unit::UseAs::BUILDER)
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		&& (unit.circuitDef.costM >= ADV_CON_COST)
		&& (gAdvConCount > 0))
	{
		--gAdvConCount;
	}
	if (energizer1 is unit)
		@energizer1 = null;
	else if (energizer2 is unit)
		@energizer2 = null;
	// Same NOCOUNT hazard as gT1FacUnit: a dangling handle reads as non-null.
	if (gComm is unit) {
		// A commander is never a gift candidate (ShareAdvCon excludes
		// Role::COMM), so this removal IS a death signal -- the real one this
		// file has lacked. "comm threat=... hp=..." (LogCommanderThreat) only
		// samples every 30s and cannot tell "died suddenly" from "log just
		// went quiet because nothing needed reevaluating"; this fires exactly
		// once, at the actual removal.
		AiLog(Factory::T() + "apex: COMMANDER LOST frame=" + ai.frame
			+ " hp=" + formatFloat(unit.GetHealthPercent() * 100.f, "", 0, 0));
		@gComm = null;
	}
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i] is unit) {
			gFusions.removeAt(i);
			break;
		}
	}
}

bool IsFusion(const CCircuitDef@ cdef)
{
	if (cdef is null)
		return false;
	const string n = cdef.GetName();
	return (n == armfus) || (n == corfus) || (n == legfus)
		|| (n == armafus) || (n == corafus) || (n == legafus);
}

// Hand our newest reactor to a teammate. Returns true when one went.
//
// The unit is dropped from the list BEFORE the call: ai.GiveUnits unregisters
// the unit and fires its removal event from inside the call, so by the time it
// returns this handle is already dead -- the same re-entrancy ShareAdvCon
// documents.
bool GiveFusion(int team)
{
	while ((gFusions.length() > FUSION_KEEP) && (gFusions[gFusions.length() - 1] is null))
		gFusions.removeLast();
	if (gFusions.length() <= FUSION_KEEP)
		return false;
	CCircuitUnit@ give = gFusions[gFusions.length() - 1];
	if (give is null)
		return false;
	gFusions.removeLast();
	array<CCircuitUnit@> gift;
	gift.insertLast(give);
	ai.GiveUnits(gift, team);
	AiLog(Factory::T() + "apex: gave " + give.circuitDef.GetName()
		+ " to team " + team + " (kept " + gFusions.length() + ")");
	return true;
}

void AiLoad(IStream& istream)
{
	Id e1id = -1, e2id = -1;
	istream >> e1id >> e2id;
	@energizer1 = ai.GetTeamUnit(e1id);
	@energizer2 = ai.GetTeamUnit(e2id);
	if (energizer1 !is null)
		energizer1.AddAttribute(Unit::Attr::BASE.type);
	if (energizer2 !is null)
		energizer2.AddAttribute(Unit::Attr::BASE.type);
}

void AiSave(OStream& ostream)
{
	ostream << Id(energizer1 !is null ? energizer1.id : -1)
			<< Id(energizer2 !is null ? energizer2.id : -1);
}

}  // namespace Builder
