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
// Spacing on the safe-mex grab. Short: an unclaimed spot is income we are not
// earning, and the check itself is one lookup.
const int REAR_MEX_PERIOD = 2 * SECOND;
int gNextRearMex = 0;
int gNextMexLog = 0;
int gNextRichLog = 0;

IUnitTask@ EnqueueWreckReclaim(CCircuitUnit@ unit, Task::Priority priority)
{
	const AIFloat3 pos = unit.GetPos(ai.frame);
	const AIFloat3 wreck = ai.GetBestWreckPos(pos, WRECK_SEARCH, WRECK_MIN);
	if (wreck.x < 0.f)
		return null;   // nothing worth the trip
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
	if (!Factory::gHaveT2)
		return true;
	return aiEconomyMgr.metal.current
	     < aiEconomyMgr.metal.storage * REZ_METAL_FLOOR;
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
const float CON_THREAT_VETO = 4.0f;

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

CCircuitDef@ FusionDef(CCircuitUnit@ unit)
{
	if (IsNavalBuilder(unit))
		return SideDef3(armuwfus, coruwfus, coruwfus);
	return SideDef3(armfus, corfus, legfus);
}

const float FUSION_MIN_BANK = 0.55f;
const int   FUSION_PERIOD   = 45 * SECOND;
int gNextFusion = 0;
int gNextFusionLog = 0;
int gFusionsAsked = 0;

IUnitTask@ EcoFusion(CCircuitUnit@ unit)
{
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
			&& (PreferReclaim() || RezSpotHot(unit))) {
		gNextRezWreck = ai.frame + REZ_WRECK_PERIOD;
		IUnitTask@ eat = EnqueueWreckReclaim(unit, Task::Priority::HIGH);
		if (eat !is null)
			return eat;
	}

	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	if (isComm) {
		LogCommanderThreat(unit);
		const float hp = unit.GetHealthPercent();
		if (hp < COM_RETREAT_HEALTH) {
			if (ai.frame >= gNextRetreatLog) {
				gNextRetreatLog = ai.frame + 20 * SECOND;
				AiLog(Factory::T() + "apex: commander retreating at "
					+ formatFloat(hp * 100.f, "", 0, 0) + "% health, frame=" + ai.frame);
			}
			IUnitTask@ flee = aiBuilderMgr.EnqueueRetreat();
			if (flee !is null)
				return flee;
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
		if (BaseUnderAttack() && (ai.frame >= gNextCommHide)) {
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
			const float heat = ThreatFor(unit, held.GetBuildPos());
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
		IUnitTask@ aa = CheapAA(unit);
		if (aa !is null)
			return aa;
		// The eco lead skips the Pulsar. It is a 60-income, 1000-energy piece of
		// standing defence, i.e. precisely the spend the role exists to not make.
		// CheapAA above is NOT skipped: an economy with no army is what air goes
		// looking for, and AA is the cheapest thing on this list.
		if (!Factory::EcoLeadActive()) {
			IUnitTask@ gun = Pulsar(unit);
			if (gun !is null)
				return gun;
		}
		// The eco lead's block first: it is the same purchase as the generic rule
		// below but sized to a spill that rule was never built for.
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

	// Its own recent history says it cannot expand, so stop sending it out. The
	// tower it puts up instead is what makes the ground usable later -- but only
	// where something is not already standing; see AreaNeedsDefence.
	if (!isComm && !Factory::EcoLeadActive() && ConDugIn(unit)) {
		IUnitTask@ dig = Fortify(unit);
		if (dig !is null)
			return dig;
	}

	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
	// Refusing to accept the job in the first place. Reached from CIdleTask, where
	// returning null simply leaves the unit idle until the next idle sweep.
	if (!isComm) {
		const string kind = SiteBuildName(task);
		if (kind != "") {
			const AIFloat3 site = task.GetBuildPos();
			float heat = ThreatFor(unit, site);
			// Mexes get the laxer bar. ThreatFor's real reading still applies when
			// the threat map has data; this only relaxes the GEOMETRIC fallback,
			// which is what actually fires today.
			if ((kind == "mex") && (heat > CON_THREAT_VETO)
				&& !PastFrontFrac(site, MEX_FAR_FRAC))
			{
				heat = 0.f;
			}
			if (heat > CON_THREAT_VETO) {
				++gConRefused;
				ConStrike(unit);
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
				@task = null;
			}
		}
	}
	// Observed: a commander stands next to reclaimable metal with an empty bank
	// and keeps its build task instead of eating it. It is not IDLE -- it holds a
	// task it cannot afford -- so the idle-only path below never fired. When
	// metal is actually empty, reclaiming beats standing still: it is the only
	// thing that unblocks the task it is already holding.
	if (aiEconomyMgr.isMetalEmpty && (ai.frame >= gNextWreck)) {
		gNextWreck = ai.frame + 3 * SECOND;
		const AIFloat3 here = unit.GetPos(ai.frame);
		const AIFloat3 near = ai.GetBestWreckPos(here, WRECK_SEARCH, 15.f);
		if (near.x >= 0.f) {
			IUnitTask@ rec = aiBuilderMgr.Enqueue(TaskB::Reclaim(
					Task::Priority::HIGH, near, 400.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
			if (rec !is null)
				return rec;
		}
	}
	// The one case that DOES displace real work. Everything above this point is
	// strictly additive by design; a rich corpse pile next to us is the exception,
	// because the metal it returns exceeds anything the interrupted task was
	// producing in the same seconds.
	if (ai.frame >= gNextWreck) {
		const AIFloat3 self = unit.GetPos(ai.frame);
		if (OnMap(self)) {
			// Gate on the field's TOTAL value, then aim at its richest body so the
			// reclaim circle lands on the corpses rather than on a tree.
			const float pile = ai.GetWreckValueAt(self, WRECK_RICH_R);
			const AIFloat3 rich = (pile >= WRECK_RICH)
					? ai.GetBestWreckPos(self, WRECK_RICH_R, 15.f)
					: AIFloat3(-1.f, 0.f, -1.f);
			if (rich.x >= 0.f) {
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

	// Reached by an idle builder, and by one whose only offer was refused above.
	// Rate-limited so a field of them does not each run their own scan every tick.
	if (ai.frame < gNextWreck)
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

void LogCommanderThreat(CCircuitUnit@ unit)
{
	if (ai.frame < gNextThreatLog)
		return;
	gNextThreatLog = ai.frame + 30 * SECOND;
	const AIFloat3 here = unit.GetPos(ai.frame);
	AiLog(Factory::T() + "apex: comm threat=" + formatFloat(ai.GetBuilderThreatAt(here), "", 0, 2)
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
	if (gComm is unit)
		@gComm = null;
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
