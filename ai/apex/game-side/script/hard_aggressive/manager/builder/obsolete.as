namespace Builder {

// Reclaiming OUR OWN buildings. apexearth: "we are full of crappy buildings in
// the later game... when we're wealthy all the old buildings like wind should be
// reclaimed, all the T1.5 turrets should be reclaimed in favor of the bigger
// turrets", and "the tight packing is great, its the damned t1 buildings we
// never reclaim."
//
// THIS IS NOT AN ECONOMY ACTIVITY. What the act buys is the GROUND; what it
// costs is constructor time, which is the scarce one. So every decision below is
// about which cell somebody else wants -- the ranking is the whole design, see
// VALUE_* and GroundValue -- and never about the metal that comes back.
//
// Two cases share the mechanism:
//
// 1. apexearth: "when theres no room to build a gantry we need to reclaim
//    older t1 buildings." C++ reports where a large footprint failed to place
//    (CBFactoryTask::FindBuildSite -> NoteBuildBlocked); that spot is the
//    highest-ranked ground there is.
// 2. apexearth: "once game is clearly in t3/t2 stage we need to reclaim all
//    our t1 and t1.5 defenses." Those towers stop earning against T2/T3 units
//    and hold a cell the base has better uses for.
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
const int   OBSOLETE_MIN_PERIOD = 3 * SECOND;
// One fusion reactor's output. The unit of "how far past T1 the grid is".
const float OBSOLETE_ENERGY_SCALE = 1000.f;
int gNextObsolete = 0;   // earliest frame we may SCAN
int gObsoleteTook = 0;   // frame of the last reclaim actually enqueued

// WHAT THE GROUND UNDER A BUILDING IS WORTH, as a rank: a target is worth what
// something else wants to do with the cell it stands on. The whole ordering
// lives in these four numbers and in ValueRate below -- nothing downstream
// compares anything but the rank, so re-weighting a term (raising the walkway
// above the blocked site, say) is an edit to this block alone.
const int VALUE_NONE    = 0;   // periphery: nothing is waiting for this cell
const int VALUE_INSIDE  = 1;   // standing in the built-up footprint
const int VALUE_LANE    = 2;   // standing in a walkway
const int VALUE_BLOCKED = 3;   // a large footprint failed to place on this spot

// Multiplier on the clearing rate for a target of each rank. A corner turbine is
// not worth a constructor walking to it; a cell a gantry just failed to take is.
const float OBSOLETE_RATE_NONE    = 0.25f;
const float OBSOLETE_RATE_INSIDE  = 1.f;
const float OBSOLETE_RATE_LANE    = 2.f;
const float OBSOLETE_RATE_BLOCKED = 4.f;

float ValueRate(int value)
{
	if (value == VALUE_BLOCKED) return OBSOLETE_RATE_BLOCKED;
	if (value == VALUE_LANE)    return OBSOLETE_RATE_LANE;
	if (value == VALUE_INSIDE)  return OBSOLETE_RATE_INSIDE;
	return OBSOLETE_RATE_NONE;
}

// What a piece of ground is WORTH, expressed as the energy income standing on
// the base.
//
// apexearth: "late into a game, land becomes very valuable... To have very cheap
// ineffective buildings taking up your space is very bad, and it only becomes
// more and more bad", and then the arithmetic: "you can fit, like, four wind
// turbines on the same amount of land that you can fit an advanced fusion...
// do you want sixty energy from that land? or do you want three thousand energy
// from that land?"
//
// Read from the defs: armafus produces 3000 energy, armfus 1000, armsolar 20,
// a wind turbine varies around 60. So the cost of leaving T1 eco standing is not
// its metal, it is the reactor that cannot go there -- and that cost rises with
// every reactor we could otherwise afford. Energy income is the direct measure
// of how far past T1 the grid is, so it is what sets the clearing rate.
//
// A clock cannot express that, and neither can a clutter count: at one reclaim
// per 20 seconds the live game had junk RISE from 43 to 67 while 27 reclaims
// fired.
//
// ENERGY INCOME AND NOT THE METAL BANK is the wealth term. A pinned bank prices
// the metal a reclaim returns, which is the resource this act does not care
// about; energy income prices the ground. The rate rises with it continuously --
// there is no state in which clearing is switched on.
int ObsoletePeriod(int value)
{
	const float e = aiEconomyMgr.energy.income;
	const float scale = (1.f + e / OBSOLETE_ENERGY_SCALE) * ValueRate(value);
	int p = (scale > 0.f) ? int(float(OBSOLETE_PERIOD) / scale) : OBSOLETE_PERIOD;
	if (p < OBSOLETE_MIN_PERIOD)
		p = OBSOLETE_MIN_PERIOD;
	return p;
}

// The grid is past the tier that T1 buildings were worth their ground for.
// One fusion's worth of income; an advanced fusion is three of these.
const float LAND_PRECIOUS_ENERGY = 1000.f;

bool LandIsPrecious()
{
	return aiEconomyMgr.energy.income >= LAND_PRECIOUS_ENERGY;
}

// Targets we have already asked for. CBuilderManager::Enqueue returns the
// EXISTING task when a reclaim is already marked on a target, and the victim
// pick below is deterministic -- so without this the same still-standing
// building is re-picked every period and the rate limit is spent on a task that
// already exists.
array<int> gReclaimAsked;

bool AskedFor(int id)
{
	for (uint i = 0; i < gReclaimAsked.length(); ++i) {
		if (gReclaimAsked[i] == id)
			return true;
	}
	return false;
}

// Cheap mobile build power, unlocked at the moment it can no longer cost us the
// advanced constructor.
//
// armfark (Butler, 210m, 140 build power) and corfast (Twitcher, 210m) are
// parked as role "support" in behaviour.json rather than "builder".
// CFactoryManager::GetFacRoleDef filters the recruit draw on GetMainRole, so at
// builder weight they win a share of it against armack -- delaying the team's
// single shared advanced constructor, which is what gates T2 mex upgrades.
//
// That objection is entirely about the RACE for the first one. Once we hold an
// advanced constructor there is nothing left to delay, and 210 metal for 140
// build power is the cheapest build power there is. Legion needs no equivalent:
// legaceb is already role builder in behaviour_leg.json.
//
// apexearth: "don't forget about those t2 assist bots with build power. those
// little guys are like mobile nano turrets and might be useful for AI even
// moreso than humans."
string armfark("armfark"); string corfast("corfast"); string legaceb("legaceb");
bool gAssistPromoted = false;

// Assist bots and advanced constructors get their limit from the economy every
// tick, not from a number in behaviour.json.
//
// apexearth: "same with adv cons, make tons of them... we shouldn't have any hard
// caps, everything needs to be balanced based on the economy/game progression",
// and "in a game like that we'd need like a ton of nano turrets, 100s of butlers,
// all working to make the expensive stuff."
const float ASSIST_PER_INCOME = 3.f;
const float ASSIST_CAP_SHARE  = 0.20f;

void SetDefCap(CCircuitDef@ d, int want)
{
	if ((d is null) || (want < 1))
		return;
	if (d.GetMaxThisUnit() != want)
		d.SetMaxThisUnit(want);
}

CCircuitDef@ AssistBotDef()
{
	return SideDef3(armfark, corfast, legaceb);
}

void UpdateEconomicCaps()
{
	int want = 2 + int(aiEconomyMgr.metal.income / ASSIST_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		want *= 2;
	const int ceiling = CapShare(ASSIST_CAP_SHARE);
	if (want > ceiling)
		want = ceiling;
	SetDefCap(AssistBotDef(), want);
	SetDefCap(NanoDef(), NanoCap());
}

void PromoteAssistBots()
{
	if (gAssistPromoted || !gHaveAdvCon)
		return;
	const string side = ai.GetSideName();
	if (side == "legion") {
		gAssistPromoted = true;
		return;
	}
	CCircuitDef@ bot = (side == "cortex") ? ai.GetCircuitDef(corfast)
	                                      : ai.GetCircuitDef(armfark);
	if (bot is null)
		return;
	gAssistPromoted = true;
	bot.SetMainRole(RT::BUILDER);
	AiLog(Factory::T() + "apex: assist bot " + bot.GetName()
		+ " promoted to builder (advanced constructor held)");
}

// The turret tiers above T1.5, as defs from mexguard.as, which the shim includes
// first.
array<CCircuitDef@> HeavyDefenceDefs()
{
	array<CCircuitDef@> heavy = {
		SideDef3(armtoast, cortoastd, legramp),
		SideDef3(armpulsar, corpulsar, legpulsar),
		SideDef3(armpb, corvipe, legapopupdef)
	};
	return heavy;
}

// Do we hold anything heavier than a T1 turret?
bool HaveHeavyDefence()
{
	array<CCircuitDef@> heavy = HeavyDefenceDefs();
	for (uint i = 0; i < heavy.length(); ++i) {
		if ((heavy[i] !is null) && (heavy[i].count > 0))
			return true;
	}
	return false;
}

// IN FAVOR OF THE BIGGER TURRETS, which is a claim about a piece of ground and
// not about the roster: HaveHeavyDefence answers "do we own one anywhere", and
// that authorises eating a Beamer on the far side of the base from the only
// Pulsar we have. The successor has to reach the cell the old tower holds.
//
// FOLLOWS the upgrade, never triggers it. Enqueueing the heavy turret from here
// would put a 680-2,500 metal DEFENCE task in a rule that runs above the economy
// offers, and would take the old tower down while its heir was still a nanoframe
// -- which is the complaint this gate exists to answer.
array<AIFloat3> gCoverAt;
array<float>    gCoverR;

void RefreshHeavyCover()
{
	gCoverAt.resize(0);
	gCoverR.resize(0);
	array<CCircuitDef@> heavy = HeavyDefenceDefs();
	for (uint i = 0; i < heavy.length(); ++i) {
		CCircuitDef@ d = heavy[i];
		if ((d is null) || (d.count <= 0))
			continue;
		const float r = d.GetMaxRange() * COVER_FRAC;
		if (r <= 0.f)
			continue;
		array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(d, gHomePos, 0.f);
		if (have is null)
			continue;
		for (uint k = 0; k < have.length(); ++k) {
			if (have[k] is null)
				continue;
			gCoverAt.insertLast(have[k].GetPos(ai.frame));
			gCoverR.insertLast(r);
		}
	}
}

bool HeavyCoverAt(const AIFloat3& in at)
{
	for (uint i = 0; i < gCoverAt.length(); ++i) {
		if (gCoverAt[i].distance2D(at) <= gCoverR[i])
			return true;
	}
	return false;
}

// Past the tier T1 defences and T1 economy were built for. gHaveT3 is a gantry
// standing; the T2 half additionally wants a real economy, so a player that has
// merely touched T2 does not strip its own defences while still fighting T1
// armies. One definition, read here and by FrontTower.
bool PastT1Tier()
{
	return Factory::gHaveT3
		|| (Factory::gHaveT2 && (aiEconomyMgr.metal.income >= OBSOLETE_T2_INCOME));
}

// What makes clearing outrank the ordinary build queue is the GROUND, not how
// many. Six turbines in a corner are not urgent and one Beamer across a walkway
// is: a count says nothing about whether anything is waiting for the cell.
const int OBSOLETE_URGENT_VALUE = VALUE_LANE;

// The T1 and T1.5 towers this AI builds -- tiers 0 and 1 of the same ladder
// MexGuardTower/FrontTower/CoverDef climb.
//
// The T2 pop-ups are deliberately NOT here: they are one of the three defs
// HaveHeavyDefence() reads, so listing them made that guard authorise eating the
// very tier it gates on. The mid tier is in no part of that set, so it can be
// listed without touching the gate.
array<string> ObsoleteDefenceNames()
{
	const string side = ai.GetSideName();
	array<string> names;
	if (side == "cortex") {
		names.insertLast(corllt);
		names.insertLast(corhllt);
	} else if (side == "legion") {
		names.insertLast(leglht);
		names.insertLast(legmg);
	} else {
		names.insertLast(armllt);
		names.insertLast(armbeamer);
	}
	return names;
}

// WHICH of our copies to eat is a space question. apexearth: "reclaim what's
// stranded outside the footprint or sitting in a lane" -- a structure in a
// walkway is what makes the base uncrossable, one mid-footprint is standing
// where the next reactor goes. The periphery ranks LAST rather than first:
// nobody is waiting for that cell, and a T1 constructor moves at 36 elmos/s, so
// the walk out and back costs more time than the reclaim.
//
// A TURRET IS SCORED THE OTHER WAY ROUND. "Outside the footprint" describes
// every tower on the line -- the ones still doing the job they were built for.
// apexearth: "we reclaim our t1.5 defenses far before we even build our T2+
// defenses, and we have a horrible lack of T2+ defenses." So a defence entry is
// eligible only where it is base clutter, and -1 says it is not a target at all.
//
// InLaneAt is asked only of positions already known to be inside: it tests the
// lateral offset alone, so a building a screen away on the same band would
// otherwise read as "in a lane" without being near the base at all.
int GroundValue(const AIFloat3& in at, bool isDefence, bool sited,
		bool haveBlocked, const AIFloat3& in blocked)
{
	if (haveBlocked && (at.distance2D(blocked) <= OBSOLETE_NEAR))
		return VALUE_BLOCKED;
	if (sited && Base::Inside(at))
		return Base::InLaneAt(at) ? VALUE_LANE : VALUE_INSIDE;
	return (isDefence && sited) ? -1 : VALUE_NONE;
}

string ValueWhy(int value)
{
	if (value == VALUE_BLOCKED) return "blocking a build site";
	if (value == VALUE_LANE)    return "standing in a walkway";
	if (value == VALUE_INSIDE)  return "inside the footprint";
	return "outside the footprint";
}

// ONE pass over every candidate def, ranked by ground and then by how far the
// constructor has to walk. Per-def lists each returning on their first hit meant
// whichever ran first took nearly everything: measured in a live 37-minute game,
// 272 armwin and 63 armmakr against 3 armllt. Ranking across the whole set is
// also the only form in which "prefer the target whose ground someone wants" can
// be expressed at all.
CCircuitUnit@ ObsoletePick(CCircuitUnit@ unit, int floorValue, bool haveBlocked,
		const AIFloat3& in blocked, string& out defName, int& out value)
{
	defName = "";
	value = floorValue - 1;
	array<string> names = ObsoleteEcoNames();
	const uint ecoEnd = names.length();
	if (HaveHeavyDefence()) {
		array<string> towers = ObsoleteDefenceNames();
		for (uint i = 0; i < towers.length(); ++i)
			names.insertLast(towers[i]);
		RefreshHeavyCover();
	}

	const bool sited = Base::Ready();
	const AIFloat3 me = unit.GetPos(ai.frame);
	CCircuitUnit@ pick = null;
	float bestDist = 0.f;
	for (uint i = 0; i < names.length(); ++i) {
		const bool isDefence = (i >= ecoEnd);
		CCircuitDef@ def = ai.GetCircuitDef(names[i]);
		if ((def is null) || (def.count <= 0))
			continue;
		array<CCircuitUnit@>@ owned = ai.GetOwnUnitsOfDef(def, gHomePos, 0.f);
		if (owned is null)
			continue;
		for (uint k = 0; k < owned.length(); ++k) {
			CCircuitUnit@ victim = owned[k];
			if ((victim is null) || (victim is unit) || AskedFor(victim.id))
				continue;
			const AIFloat3 at = victim.GetPos(ai.frame);
			const int v = GroundValue(at, isDefence, sited, haveBlocked, blocked);
			if ((v < floorValue) || (v < 0))
				continue;
			// A tower goes only where its heir already reaches. The exception is
			// ground a large building has just failed to take: there the tower is
			// the reason we cannot tech up, and a heavier turret is standing
			// somewhere or the def would not be in this list.
			if (isDefence && (v != VALUE_BLOCKED) && !HeavyCoverAt(at))
				continue;
			const float d = me.distance2D(at);
			if ((v > value) || ((v == value) && (d < bestDist))) {
				value = v;
				bestDist = d;
				@pick = victim;
				defName = names[i];
			}
		}
	}
	return pick;
}

IUnitTask@ ReclaimOwnDef(CCircuitUnit@ victim, const string& in defName, int value)
{
	IUnitTask@ eat = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL, victim));
	if (eat is null)
		return null;
	gReclaimAsked.insertLast(victim.id);
	if (gReclaimAsked.length() > 64)
		gReclaimAsked.removeAt(0);
	gObsoleteTook = ai.frame;
	AiLog(Factory::T() + "apex: obsolete-reclaim " + defName + " #" + victim.id
		+ " (" + ValueWhy(value) + ") v=" + value);
	return eat;
}

// How many T1 structures we are still standing on. Counted from the same name
// lists the reclaim uses, so the trigger and the target cannot drift apart.
int ObsoleteJunkCount()
{
	int n = 0;
	array<string> junk = ObsoleteEcoNames();
	for (uint i = 0; i < junk.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(junk[i]);
		if (d !is null)
			n += d.count;
	}
	array<string> towers = ObsoleteDefenceNames();
	for (uint i = 0; i < towers.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(towers[i]);
		if (d !is null)
			n += d.count;
	}
	return n;
}

int gNextJunkLog = 0;

// The promoted path: same act, but ahead of the economy offers instead of behind
// everything. What keeps it from becoming a constructor sink is the rank floor
// -- it will only take ground somebody is waiting for.
IUnitTask@ ObsoleteUrgent(CCircuitUnit@ unit)
{
	if (!PastT1Tier())
		return null;
	const int junk = ObsoleteJunkCount();
	if (ai.frame >= gNextJunkLog) {
		gNextJunkLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: obsolete junk standing=" + junk
			+ " income=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
			+ " t2=" + (Factory::gHaveT2 ? "1" : "0")
			+ " t3=" + (Factory::gHaveT3 ? "1" : "0"));
	}
	return ObsoleteReclaim(unit, false, OBSOLETE_URGENT_VALUE);
}

IUnitTask@ ObsoleteReclaim(CCircuitUnit@ unit, bool allowAdv = false,
		int minValue = VALUE_NONE)
{
	// NOT THE ADVANCED CONSTRUCTORS. apexearth: "I see T2 con time is being used
	// to reclaim obsolete buildings. Let's not have that be important for them at
	// all. Rezbots, T1 cons, and con turrets can do that." An advanced con is the
	// only unit that can build a moho, a reactor or a heavy turret, and there are
	// never many; tidying is work anything else can do.
	//
	// allowAdv is the one exception, and only the caller can establish it: the
	// last-resort path runs after the engine's own offer came back null and after
	// every rule above declined, so there is no moho for this constructor to be
	// taken off. It is passed the bank state as well -- apexearth, watching an
	// 8v8: "These guys have tons of metal so they could spend some time reclaiming
	// old stuff." The promoted path above the economy offers never passes it.
	if (IsAdvConDef(unit) && !allowAdv)
		return null;
	// Two rate limits, because the permit depends on what the scan finds. The
	// scan itself is bounded here at the shortest period any target could earn --
	// AiMakeTask is a re-election and runs per builder per update, and each scan
	// walks teamUnits once per candidate def.
	if (ai.frame < gNextObsolete)
		return null;

	AIFloat3 blocked;
	const bool haveBlocked = ai.GetBlockedBuildPos(blocked);
	// A tower on ground a gantry has just failed to take is clutter whatever the
	// tech state says; everything else waits until we are past the tier these
	// buildings were worth their ground for.
	int floorValue = minValue;
	if (!PastT1Tier()) {
		if (!haveBlocked)
			return null;
		if (floorValue < VALUE_BLOCKED)
			floorValue = VALUE_BLOCKED;
	}

	string defName;
	int value = 0;
	gNextObsolete = ai.frame + OBSOLETE_MIN_PERIOD;
	CCircuitUnit@ pick = ObsoletePick(unit, floorValue, haveBlocked, blocked,
			defName, value);
	if (pick is null)
		return null;
	// The permit is computed for the rank actually found, so a cell a gantry
	// wants is not made to wait behind the cooldown a corner turbine earned.
	if (ai.frame < gObsoleteTook + ObsoletePeriod(value))
		return null;
	return ReclaimOwnDef(pick, defName, value);
}

// T1 economy and AA that a T2/T3 base has outgrown. Per-faction, because a
// name list that only covers Cortex is the recurring faction-parity trap.
//
// The T1 converter and the T1 AA turret belong here -- apexearth: "those become
// trash long into a game". What had to change is the two rules that were
// REBUILDING them behind us: CheapAA and the generic EnergyConverter both now
// stand down past T1 tier, so reclaiming one no longer queues its replacement.
// REPLACE, DO NOT JUST REMOVE. apexearth, watching: "I saw us reclaiming t1
// converters before t2 converters were even made. Should replace t1s with t2s
// otherwise we just lower our metal income."
//
// PastT1Tier() asks whether we have TECHED, never whether the replacement was
// actually built -- so a base at T2 with the income for it tore out its cheap
// converters and its solars while nothing had taken over the job. Both of those
// are income: a converter IS metal income, and a solar is what runs it.
//
// So each of those two entries now waits for its own successor to be standing.
// Wind and the T1 AA turret are unconditional: wind is superseded by any
// generator at all, and the AA turret is not economy.
bool HaveReplacementFor(const string& in name)
{
	CCircuitDef@ better = null;
	if ((name == armmakr) || (name == cormakr) || (name == legeconv))
		@better = SideDef3(armmmkr, cormmkr, legadveconv);
	else if ((name == armsolar) || (name == corsolar) || (name == legsolar))
		@better = SideDef3(armadvsol, coradvsol, legadvsol);
	// A reactor is the advanced collector's successor: once one stands the panels
	// are footprint and metal the base wants back.
	else if ((name == armadvsol) || (name == coradvsol) || (name == legadvsol))
		@better = SideDef3(armfus, corfus, legfus);
	else
		return true;   // no successor to wait for
	return (better !is null) && (better.count > 0);
}

array<string> ObsoleteEcoNames()
{
	array<string> names;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		names.insertLast(corwin);
		if (HaveReplacementFor(corsolar))
			names.insertLast(corsolar);
		if (HaveReplacementFor(cormakr))
			names.insertLast(cormakr);
		if (HaveReplacementFor(coradvsol))
			names.insertLast(coradvsol);
		names.insertLast(corrl);
	} else if (side == "legion") {
		names.insertLast(legwin);
		if (HaveReplacementFor(legsolar))
			names.insertLast(legsolar);
		if (HaveReplacementFor(legeconv))
			names.insertLast(legeconv);
		if (HaveReplacementFor(legadvsol))
			names.insertLast(legadvsol);
		names.insertLast(legrl);
	} else {
		names.insertLast(armwin);
		if (HaveReplacementFor(armsolar))
			names.insertLast(armsolar);
		if (HaveReplacementFor(armmakr))
			names.insertLast(armmakr);
		if (HaveReplacementFor(armadvsol))
			names.insertLast(armadvsol);
		names.insertLast(armrl);
	}
	return names;
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
			Task::Priority::NORMAL, tower, spot, DEF_SHAKE));
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

}  // namespace Builder
