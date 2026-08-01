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
// built or gifted. A player with T2 and no advanced con should build one; a
// player that already has one should not build a second.
bool gHaveAdvCon = false;

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
const float WRECK_RADIUS  = 320.f;   // sweep the cluster, not one corpse
const int   WRECK_TIMEOUT = 1 * MINUTE;
int gNextWreck = 0;

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
float ThreatFor(CCircuitUnit@ unit, const AIFloat3& in where)
{
	if (!OnMap(where))
		return 0.f;
	return ai.GetUnitThreatAt(unit, where);
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

const uint  CONVERT_CON_FLOOR = 3;    // never dip below this many workers
const float CONVERT_MIN_SPARE = 70.f; // one converter's draw of unused energy
const int   CONVERT_PERIOD    = 25 * SECOND;
const float REAR_DISTANCE     = 450.f;
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

	// The T1 converter is what a T1 constructor can build: armck/armcv carry
	// armmakr, corck/corcv cormakr, legck/legcv legeconv. armfmkr is a real def
	// that NO ground constructor can build -- asking for it produced 95 requests
	// and zero converters.
	const string side = ai.GetSideName();
	CCircuitDef@ want = (side == "cortex") ? ai.GetCircuitDef(cormakr)
	                  : ((side == "legion") ? ai.GetCircuitDef(legeconv)
	                                        : ai.GetCircuitDef(armmakr));
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
const int   PULSAR_MAX        = 2;
const int   PULSAR_PERIOD     = 60 * SECOND;
const int   AA_WANT           = 4;      // enough that air picks someone else
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
	CCircuitDef@ aa = SideDef3(armrl, corrl, legrl);
	if ((aa is null) || !aa.IsAvailable(ai.frame) || (aa.count >= AA_WANT))
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
		+ "/" + AA_WANT);
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
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, spot, SQUARE_SIZE * 2));
	if (post is null)
		return null;
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
	if (IsRezzer(unit) && (ai.frame >= gNextRezWreck) && PreferReclaim()) {
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
	if (!isComm) {
		IUnitTask@ aa = CheapAA(unit);
		if (aa !is null)
			return aa;
		IUnitTask@ gun = Pulsar(unit);
		if (gun !is null)
			return gun;
		IUnitTask@ conv = EnergyConverter(unit);
		if (conv !is null)
			return conv;
	}

	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
	// Refusing to accept the job in the first place. Reached from CIdleTask, where
	// returning null simply leaves the unit idle until the next idle sweep.
	if (!isComm) {
		const string kind = SiteBuildName(task);
		if (kind != "") {
			const float heat = ThreatFor(unit, task.GetBuildPos());
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
const float COM_RETREAT_HEALTH = 0.60f;
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
		return;

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
	if (energizer1 is unit)
		@energizer1 = null;
	else if (energizer2 is unit)
		@energizer2 = null;
	// Same NOCOUNT hazard as gT1FacUnit: a dangling handle reads as non-null.
	if (gComm is unit)
		@gComm = null;
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
