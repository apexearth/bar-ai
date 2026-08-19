namespace Builder {

// Reclaiming OUR OWN buildings. Not an economy activity: what this buys is
// GROUND, what it costs is constructor time, so every decision here is about
// which cell somebody else wants (see VALUE_* and GroundValue), never about the
// metal that comes back. Two triggers share the mechanism: a large footprint
// that just failed to place (CBFactoryTask::FindBuildSite -> NoteBuildBlocked),
// and towers/economy that have been superseded.
//
// Targets are named defs, NOT a computed tier -- CCircuitDef carries no tech
// level, so a tier test would be a heuristic, and the failure mode here is
// reclaiming our own base. Never mexes, never factories, never anything armed
// above T1.5.
// 10s base, was 20: apexearth 2026-08-15, "all this obsolete reclaim should
// happen faster". The energy-income scaling below still compresses it further.
const int OBSOLETE_PERIOD = 10 * SECOND;
const float OBSOLETE_NEAR = 900.f;     // around a blocked build site
// Income a T2 player must clear before stripping its own T1 defences. A player
// that has merely touched T2 may still be holding a line against T1 armies, and
// those towers are the line.
const float OBSOLETE_T2_INCOME = 60.f;
const int   OBSOLETE_MIN_PERIOD = 1 * SECOND;
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
// the base. The cost of leaving T1 eco standing is not its metal, it is the
// reactor that cannot go there, and that cost rises with every reactor we could
// otherwise afford -- energy income is the direct measure of how far past T1
// the grid is, so it sets the clearing rate. ENERGY INCOME, NOT THE METAL BANK:
// a pinned bank prices the metal a reclaim returns, which this act does not
// care about; energy income prices the ground, continuously rather than as an
// on/off state.
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
// Entries EXPIRE: reclaim tasks abort readily (income-dip Reevaluate,
// OnUnitIdle), and a permanent mark deadlocked the whole system -- every
// standing obsolete building "already asked", rezbots idle for the rest of
// the game (apexearth reported the idling twice before this was found).
array<int> gReclaimAsked;
array<int> gReclaimAskedFrame;

bool AskedFor(int id)
{
	const int ttl = int(ai.GetTunable("apex_obsolete_retry", 45.f)) * SECOND;
	for (uint i = 0; i < gReclaimAsked.length(); ) {
		if (ai.frame - gReclaimAskedFrame[i] > ttl) {
			gReclaimAsked.removeAt(i);
			gReclaimAskedFrame.removeAt(i);
			continue;
		}
		if (gReclaimAsked[i] == id)
			return true;
		++i;
	}
	return false;
}

// A building we are eating and a building worth repairing are the same building
// to two systems that never speak. CBuilderManager's buildingDamagedHandler
// (module/BuilderManager.cpp:210) enqueues a HIGH repair for any own structure
// that takes damage without consulting its own reclaimUnits map -- the guard the
// abandoned-building scan at :1617 does use -- and CBRepairTask::Reevaluate only
// retires the task once health is full, which a reclaim in progress guarantees
// it never is.
//
// reclaimUnits is not bound to AngelScript, so this mirrors it from the task
// events we already take. Both arrays hold LIVE tasks only, and the id is
// snapshotted at add time: CCircuitUnit is NOCOUNT, so a stored handle would
// outlive the unit.
array<IUnitTask@> gDoomedTask;
array<int>        gDoomedId;
array<IUnitTask@> gStructRepair;
array<int>        gStructRepairId;
int gRepairsCancelled = 0;

bool IsDoomed(int id)
{
	for (uint i = 0; i < gDoomedId.length(); ++i) {
		if (gDoomedId[i] == id)
			return true;
	}
	return false;
}

// Aborting mutates gStructRepair through AiTaskRemoved, so the victims are
// collected first; IUnitTask is refcounted, so the local handles stay valid.
void CancelDoomedRepairs()
{
	if ((gStructRepair.length() == 0) || (gDoomedId.length() == 0))
		return;
	array<IUnitTask@> kill;
	for (uint i = 0; i < gStructRepair.length(); ++i) {
		if ((gStructRepair[i] !is null) && IsDoomed(gStructRepairId[i]))
			kill.insertLast(gStructRepair[i]);
	}
	for (uint i = 0; i < kill.length(); ++i) {
		++gRepairsCancelled;
		AiLog(Factory::T() + "apex: dropping repair of a building we are"
			+ " reclaiming (#" + gRepairsCancelled + ")");
		kill[i].Abort();
	}
}

// Cheap mobile build power, unlocked at the moment it can no longer cost us the
// advanced constructor: armfark/corfast are parked at role "support" rather
// than "builder" because CFactoryManager::GetFacRoleDef would otherwise let
// them win a share of the recruit draw against armack and delay the team's
// single shared advanced constructor. That objection is only about the RACE for
// the first one -- once we hold an advanced constructor, 210 metal for 140
// build power is the cheapest build power there is. Legion needs no promotion:
// legaceb is already role builder in behaviour_leg.json.
string armfark("armfark"); string corfast("corfast"); string legaceb("legaceb");
bool gAssistPromoted = false;

// Assist bots and advanced constructors get their limit from the economy every
// tick, not from a number in behaviour.json.
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
	// income/3, doubled at a full bank, allowed 100-200 assist bots -- the
	// wandering builder crowd apexearth kept seeing ("we build far more
	// builders than we need"). A turret is the better build-power sink and
	// already takes the full-bank bonus, so the bots stay a small mobile
	// complement that scales gently.
	int want = 2 + int(aiEconomyMgr.metal.income
			/ ai.GetTunable("apex_assist_per_income", 10.f));
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

// FOLLOWS the heavy-turret upgrade, never triggers it: enqueueing the heavy
// turret from here would put a costly DEFENCE task in a rule that runs above
// the economy offers, and would take the old tower down while its heir was
// still a nanoframe. HaveHeavyDefence only answers "do we own one anywhere", so
// HeavyCoverAt below is what checks the successor actually reaches this cell.
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

// WHICH of our copies to eat is a space question: a walkway structure blocks
// the base, a mid-footprint one sits where the next reactor goes, so the
// periphery ranks LAST -- nobody is waiting for that cell. A TURRET IS SCORED
// THE OTHER WAY ROUND: "outside the footprint" describes every tower still
// doing its job on the line, so a defence entry is eligible only where it is
// base clutter, and -1 says it is not a target at all.
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
	if (isDefence && sited)
		return (Perf::LagSeverity() >= 1.f) ? VALUE_NONE : -1;
	return VALUE_NONE;
}

string ValueWhy(int value)
{
	if (value == VALUE_BLOCKED) return "blocking a build site";
	if (value == VALUE_LANE)    return "standing in a walkway";
	if (value == VALUE_INSIDE)  return "inside the footprint";
	return "outside the footprint";
}

// ONE pass over every candidate def, ranked by ground and then by how far the
// constructor has to walk -- per-def lists that each return on their first hit
// let whichever ran first take nearly everything. Ranking across the whole set
// is the only way to express "prefer the target whose ground someone wants".
CCircuitUnit@ ObsoletePick(const AIFloat3& in origin, int skipId, int floorValue,
		bool haveBlocked, const AIFloat3& in blocked,
		string& out defName, int& out value)
{
	defName = "";
	value = floorValue - 1;
	array<string> names = ObsoleteEcoNames();
	const uint ecoEnd = names.length();
	// Deep lag cuts: past severity 1 the tower list joins unconditionally and
	// the sparing below relaxes -- a lagging host needs the objects gone more
	// than it needs a T1 tower holding a line.
	if ((Perf::LagSeverity() >= 1.f) || HaveHeavyDefence()) {
		array<string> towers = ObsoleteDefenceNames();
		for (uint i = 0; i < towers.length(); ++i)
			names.insertLast(towers[i]);
		RefreshHeavyCover();
	}

	const bool sited = Base::Ready();
	const AIFloat3 me = origin;
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
			if ((victim is null) || (int(victim.id) == skipId)
				|| AskedFor(victim.id))
				continue;
			const AIFloat3 at = victim.GetPos(ai.frame);
			const int v = GroundValue(at, isDefence, sited, haveBlocked, blocked);
			if ((v < floorValue) || (v < 0))
				continue;
			// A tower goes only where its heir already reaches. The exception is
			// ground a large building has just failed to take: there the tower is
			// the reason we cannot tech up, and a heavier turret is standing
			// somewhere or the def would not be in this list.
			if (isDefence && (v != VALUE_BLOCKED) && !HeavyCoverAt(at)
				&& (Perf::LagSeverity() < 1.f))
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
	gReclaimAskedFrame.insertLast(ai.frame);
	if (gReclaimAsked.length() > 64) {
		gReclaimAsked.removeAt(0);
		gReclaimAskedFrame.removeAt(0);
	}
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
// CON TURRETS TIDY THEIR OWN REACH. A nano sits on a native guard/patrol --
// a task class that never re-elects through AiMakeTask -- so it can never be
// handed reclaim work by the pipeline: apexearth, watching, "our con turrets
// should work to reclaim obsolete buildings instead of sitting idle...
// getting us valuable land/space." Periodic sweep instead: each standing
// turret is offered the best obsolete building inside its own lathe reach.
// armnanotc builddistance is 400; the margin keeps a victim's own footprint
// inside reach.
const float NANO_TIDY_REACH  = 380.f;

// Tidy attempts per victim id; three failed assignments blacklist it for the
// turret sweep (the mobile obsolete path still may take it). Bounded ring.
array<int> gTidyVictimId;
array<int> gTidyVictimTries;

bool TidyStruckOut(int id)
{
	for (uint i = 0; i < gTidyVictimId.length(); ++i) {
		if (gTidyVictimId[i] == id) {
			if (gTidyVictimTries[i] >= 3)
				return true;
			++gTidyVictimTries[i];
			return false;
		}
	}
	gTidyVictimId.insertLast(id);
	gTidyVictimTries.insertLast(1);
	if (gTidyVictimId.length() > 64) {
		gTidyVictimId.removeAt(0);
		gTidyVictimTries.removeAt(0);
	}
	return false;
}
// Every second, not every 20: a turret's lathe is free and junk is ground
// (apexearth: "nano tidy sweep should run once every second unless it is very
// heavy"). The batch bound is what keeps the 1s period affordable: at most
// this many turrets SCAN per sweep, on a rotating cursor, so the per-second
// cost is flat however many turrets stand.
const int   NANO_TIDY_PERIOD = 1 * SECOND;
const int   NANO_TIDY_BATCH  = 6;
int gNextNanoTidy = 0;
uint gNanoTidyCursor = 0;
array<int> gNanoIds;
array<int> gNanoBorn;

void NanoNoteBuilt(Id id)
{
	gNanoIds.insertLast(int(id));
	gNanoBorn.insertLast(ai.frame);
}

void NanoNoteGone(Id id)
{
	for (int i = int(gNanoIds.length()) - 1; i >= 0; --i) {
		if (gNanoIds[i] == int(id)) {
			gNanoIds.removeAt(uint(i));
			gNanoBorn.removeAt(uint(i));
		}
	}
}

void NanoTidy()
{
	if (ai.frame < gNextNanoTidy)
		return;
	gNextNanoTidy = ai.frame
			+ int(ai.GetTunable("apex_nano_tidy_period", float(NANO_TIDY_PERIOD)));
	const uint total = gNanoIds.length();
	if (total == 0)
		return;
	uint batch = uint(ai.GetTunable("apex_nano_tidy_batch", float(NANO_TIDY_BATCH)));
	if (batch > total)
		batch = total;
	for (uint step = 0; step < batch; ++step) {
		if (gNanoIds.length() == 0)
			return;
		const uint i = (gNanoTidyCursor++) % gNanoIds.length();
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gNanoIds[i]));
		if (u is null) {
			gNanoIds.removeAt(i);   // stale id; the unit is gone
			gNanoBorn.removeAt(i);
			continue;
		}
		// CLUSTERS ONLY (apexearth 2026-08-18): a turret group with nothing but
		// turrets in its reach works nothing, wherever it stands -- the old
		// front exemption is gone with the front-nano concept. The formation
		// grace is what keeps this off a cluster still being seeded: a fresh
		// turret beside a big build is useful now and judged later.
		{
			const int grace = int(ai.GetTunable("apex_nano_form_grace", 120.f)
					* float(SECOND));
			if (ai.frame - gNanoBorn[i] >= grace) {
				const AIFloat3 up = u.GetPos(ai.frame);
				CCircuitDef@ nd = Builder::NanoDef();
				array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(up,
						u.circuitDef.GetBuildDistance() + 64.f);
				int nonNano = 0;
				bool building = false;
				if (near !is null) {
					for (uint k = 0; k < near.length(); ++k) {
						CCircuitUnit@ o = near[k];
						if ((o is null) || (o.id == u.id))
							continue;
						if ((nd is null) || (o.circuitDef.id != nd.id))
							++nonNano;
						if (!Main::WasFinished(int(o.id)))
							building = true;
					}
				}
				if ((nonNano == 0) && !building) {
					IUnitTask@ gone = aiBuilderMgr.Enqueue(
							TaskB::Reclaim(Task::Priority::NORMAL, u));
					if (gone !is null) {
						AiLog(Factory::T() + "apex: orphan nano #" + u.id
							+ " reclaimed -- only turrets in reach");
						gNanoIds.removeAt(i);
						gNanoBorn.removeAt(i);
						continue;
					}
				}
			}
		}
		IUnitTask@ held = u.task;
		if ((held !is null) && (held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::RECLAIM))
		{
			// Self-heal, whatever path assigned it: a static turret holding a
			// reclaim beyond its lathe reach works nothing and reads "busy"
			// forever (apexearth, live 2026-08-17).
			const AIFloat3 at = held.GetBuildPos();
			if (OnMap(at) && (u.GetPos(ai.frame).distance2D(at)
				> u.circuitDef.GetBuildDistance() + 64.f))
			{
				held.Abort();
				AiLog(Factory::T() + "apex: nano-tidy #" + u.id
					+ " dropped an out-of-reach reclaim");
			}
			continue;                     // already tidying (or just freed)
		}
		string dn;
		int v;
		AIFloat3 none;
		CCircuitUnit@ victim = ObsoletePick(u.GetPos(ai.frame), int(u.id),
				0, false, none, dn, v);
		if (victim is null)
			continue;
		if (u.GetPos(ai.frame).distance2D(victim.GetPos(ai.frame)) > NANO_TIDY_REACH)
			continue;                     // a turret cannot walk to it
		// GIVE UP ON A BOUNCER. The engine aborts some of these right after
		// assignment (its own reach geometry or refusal), and re-picking the
		// same victim every sweep was the visible "turret trying to reclaim
		// something out of its range" -- measured 16-26 repeat assignments
		// per pair, 914 in one game. Three strikes and the victim is left to
		// the mobile reclaim path.
		if (TidyStruckOut(victim.id))
			continue;
		IUnitTask@ eat = ReclaimOwnDef(victim, dn, v);
		if (eat !is null) {
			aiBuilderMgr.AssignTask(u, eat);
			AiLog(Factory::T() + "apex: nano-tidy #" + u.id + " reclaims "
				+ dn + " in reach");
			// One target PER TURRET per sweep, not one per sweep total: a
			// turret's lathe time is nearly free, and one-per-sweep made a
			// cluttered base tidy itself at three buildings a minute.
		}
	}
}

// THE INVERTED PIPELINE: the obsolete building asks to be removed, instead of
// every builder election scanning for one. One central scan per period
// enqueues an ownerless reclaim task; DefaultMakeTask hands it to the nearest
// free constructor. AskedFor is what stops the sweep re-enqueueing the same
// victim every pass -- the documented orphan-task failure mode.
// Deep lag cut: standing assist bots beyond the economy-derived cap are
// walking sim cost -- reclaim the surplus, newest first, one per sweep per
// severity point. The cap itself already scales with income, so this is the
// standing pool catching down to it (apexearth: "keep cutting back").
int gNextBotTrim = 0;

void TrimSurplusBuilders()
{
	if (ai.frame < gNextBotTrim)
		return;
	gNextBotTrim = ai.frame + 5 * SECOND;
	CCircuitDef@ bot = AssistBotDef();
	if (bot is null)
		return;
	const int cap = 2 + int(aiEconomyMgr.metal.income
			/ ai.GetTunable("apex_assist_per_income", 10.f));
	int excess = int(bot.count) - cap;
	if (excess <= 0)
		return;
	int quota = int(Perf::LagSeverity());
	array<CCircuitUnit@>@ bots = ai.GetOwnUnitsOfDef(bot, gHomePos, 0.f);
	if (bots is null)
		return;
	for (int i = int(bots.length()) - 1; (i >= 0) && (excess > 0) && (quota > 0); --i) {
		CCircuitUnit@ b = bots[i];
		if ((b is null) || AskedFor(b.id))
			continue;
		IUnitTask@ gone = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL, b));
		if (gone !is null) {
			gReclaimAsked.insertLast(int(b.id));
			gReclaimAskedFrame.insertLast(ai.frame);
			--excess;
			--quota;
			AiLog(Factory::T() + "apex: lag trim -- reclaiming surplus "
				+ bot.GetName() + " (" + bot.count + " held, cap " + cap + ")");
		}
	}
}

void ObsoleteSweep()
{
	if (ai.frame < gNextObsolete)
		return;
	AIFloat3 blocked;
	const bool haveBlocked = ai.GetBlockedBuildPos(blocked);
	// A tower on ground a gantry has just failed to take is clutter whatever the
	// tech state says; everything else waits until we are past the tier these
	// buildings were worth their ground for.
	int floorValue = VALUE_NONE;
	if (!PastT1Tier()) {
		if (!haveBlocked)
			return;
		floorValue = VALUE_BLOCKED;
	} else if (ai.frame >= gNextJunkLog) {
		gNextJunkLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: obsolete junk standing=" + ObsoleteJunkCount()
			+ " income=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
			+ " t2=" + (Factory::gHaveT2 ? "1" : "0")
			+ " t3=" + (Factory::gHaveT3 ? "1" : "0"));
	}
	gNextObsolete = ai.frame + OBSOLETE_MIN_PERIOD;
	// Rank from the blocked cell when there is one -- that is the ground
	// someone is waiting for; otherwise from home. The walk-distance tiebreak
	// happens naturally when the engine assigns the nearest constructor.
	const AIFloat3 origin = haveBlocked ? blocked : gHomePos;
	string defName;
	int value = 0;
	// In cleanup mode the sweep goes PARALLEL: one target at a time was why
	// clutter outlived the economy that obsoleted it. Concurrency scales with
	// income; AskedFor dedups repeats.
	int picks = 1;
	if (CleanupMode()) {
		picks = int((1.f + aiEconomyMgr.metal.income
				/ ai.GetTunable("apex_cleanup_per", 150.f))
				* (1.f + Perf::LagSeverity()));
		// A perf bound, not policy: each pick walks full unit lists, and an
		// unbounded sweep burned 277-475ms single frames (seed 200, min
		// 54-56) -- a lag reducer must not be a lag spike. The same total
		// work spreads across consecutive sweeps instead.
		const int most = int(ai.GetTunable("apex_cleanup_max_picks", 5.f));
		if (picks > most)
			picks = most;
	}
	if (Perf::LagSeverity() >= 1.f)
		TrimSurplusBuilders();
	for (int n = 0; n < picks; ++n) {
		CCircuitUnit@ pick = ObsoletePick(origin, -1, floorValue, haveBlocked,
				blocked, defName, value);
		if (pick is null)
			return;
		// The permit is computed for the rank actually found, so a cell a
		// gantry wants is not made to wait behind the cooldown a corner
		// turbine earned. Cleanup mode skips the pacing: the whole point is
		// speed, and the ground-value ranking still orders the eating.
		if (!CleanupMode() && (ai.frame < gObsoleteTook + ObsoletePeriod(value)))
			return;
		ReclaimOwnDef(pick, defName, value);
	}
}

// T1 economy and AA that a T2/T3 base has outgrown. Per-faction, since a name
// list covering only one faction is the recurring parity trap.
//
// REPLACE, DO NOT JUST REMOVE: PastT1Tier() asks whether we have TECHED, never
// whether the replacement was actually built, so a converter or solar entry
// waits for its own successor to be standing before it is eligible -- both of
// those are metal income, and tearing them out before the replacement exists
// just lowers it. CheapAA and the generic EnergyConverter both stand down past
// T1 tier, so reclaiming one no longer queues its replacement. Wind and the T1
// AA turret are unconditional: wind is superseded by any generator at all, and
// the AA turret is not economy.
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

// ONE predicate for both sides. The builder's energy ranking and the reclaim
// target list must agree exactly, or the base builds and eats the same def at
// once -- apexearth watched his commander building the def his con turrets
// were reclaiming. Eligibility = the replacement STANDS (never strip a tier
// whose successor is not on the field) AND energy income clears a CLIFF, so
// eating panels can never crash the grid down to one advanced solar.
// Wind's cliff scales with THIS map's measured wind: a bad-wind map obsoletes
// turbines sooner. apexearth 2026-08-15: "so long as our energy income is
// > ~500 we can reclaim solars... >2000 reclaim wind and advanced solar...
// based on efficiency for the map."
float EnergyReclaimCliff(const string& in name)
{
	if ((name == armsolar) || (name == corsolar) || (name == legsolar))
		return ai.GetTunable("apex_reclaim_solar_e", 500.f);
	if ((name == armadvsol) || (name == coradvsol) || (name == legadvsol))
		return ai.GetTunable("apex_reclaim_advsol_e", 2000.f);
	if ((name == armwin) || (name == corwin) || (name == legwin)) {
		const float base = ai.GetTunable("apex_reclaim_wind_e", 2000.f);
		CCircuitDef@ wind = SideDef3(armwin, corwin, legwin);
		CCircuitDef@ sol = SideDef3(armadvsol, coradvsol, legadvsol);
		if ((wind !is null) && (sol !is null)
			&& (wind.costM > 0.f) && (sol.costM > 0.f))
		{
			const float sEpm = aiEconomyMgr.GetEnergyMake(sol) / sol.costM;
			if (sEpm > 0.f) {
				float rel = (aiEconomyMgr.GetEnergyMake(wind) / wind.costM) / sEpm;
				if (rel > 1.f)
					rel = 1.f;
				const float scaled = base * rel;
				return (scaled < 300.f) ? 300.f : scaled;
			}
		}
		return base;
	}
	return 0.f;   // converters, AA: the replacement-standing rule alone decides
}

bool EnergyReclaimable(const string& in name)
{
	bool standing;
	if ((name == armwin) || (name == corwin) || (name == legwin)) {
		CCircuitDef@ adv = SideDef3(armadvsol, coradvsol, legadvsol);
		standing = HaveReactor() || ((adv !is null) && (adv.count > 0));
	} else {
		standing = HaveReplacementFor(name);
	}
	if (!standing)
		return false;
	return aiEconomyMgr.energy.income >= EnergyReclaimCliff(name);
}

// CLEANUP MODE: a huge economy no longer needs its small things, and a
// LAGGING HOST needs them gone whatever the income -- apexearth: "if the
// host can't handle what we're doing we need to clean up after ourselves
// and get rid of all unimportant things."
bool CleanupMode()
{
	return (aiEconomyMgr.metal.income >= ai.GetTunable("apex_bigeco_income", 500.f))
		|| Perf::GameLagging();
}

array<string> ObsoleteEcoNames()
{
	array<string> names;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		if (EnergyReclaimable(corwin))
			names.insertLast(corwin);
		if (EnergyReclaimable(corsolar))
			names.insertLast(corsolar);
		if (HaveReplacementFor(cormakr))
			names.insertLast(cormakr);
		if (EnergyReclaimable(coradvsol))
			names.insertLast(coradvsol);
		names.insertLast(corrl);
		if (WallsObsolete())
			names.insertLast("cordrag");
	} else if (side == "legion") {
		if (EnergyReclaimable(legwin))
			names.insertLast(legwin);
		if (EnergyReclaimable(legsolar))
			names.insertLast(legsolar);
		if (HaveReplacementFor(legeconv))
			names.insertLast(legeconv);
		if (EnergyReclaimable(legadvsol))
			names.insertLast(legadvsol);
		names.insertLast(legrl);
		if (WallsObsolete())
			names.insertLast("legdrag");
	} else {
		if (EnergyReclaimable(armwin))
			names.insertLast(armwin);
		if (EnergyReclaimable(armsolar))
			names.insertLast(armsolar);
		if (HaveReplacementFor(armmakr))
			names.insertLast(armmakr);
		if (EnergyReclaimable(armadvsol))
			names.insertLast(armadvsol);
		names.insertLast(armrl);
		if (WallsObsolete())
			names.insertLast("armdrag");
	}
	// THE BIG-ECONOMY PURGE (apexearth 2026-08-18: "clean up after itself...
	// all our little buildings, storage... none of them are important when
	// we're at 500 metal a second"): past the bar, T1 storage of both kinds
	// joins the list. The bank a storage holds is minutes of income now.
	if (CleanupMode()) {
		array<string> smalls = (side == "cortex")
			? array<string> = {"cormstor", "corestor"}
			: (side == "legion")
				? array<string> = {"legmstor", "legestor"}
				: array<string> = {"armmstor", "armestor"};
		for (uint i = 0; i < smalls.length(); ++i)
			names.insertLast(smalls[i]);
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
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, tower, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, spot, 0.f, DEF_SHAKE, created);
	if (post is null)
		return null;
	if (!created)
		return post;
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
