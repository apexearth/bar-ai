namespace Assist {

// What the T2 assist bots do once PromoteAssistBots has made them buildable.
//
// Promotion only makes them appear. Left alone they reach DefaultMakeTask and
// pick their own separate buildings, which is the opposite of assisting: 140
// build power spread over its own solar is worth less than the same 140 poured
// into a tower a front constructor has already started.
//
// This rule adds no construction of its own. It hands the bot a task that
// already exists, or a GUARD on a constructor that will make one.

string armfark("armfark"); string corfast("corfast"); string legaceb("legaceb");

array<int> gBotDefs;
bool gBotDefsResolved = false;

void ResolveBotDefs()
{
	gBotDefsResolved = true;
	array<string> names = {armfark, corfast, legaceb};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if (d !is null)
			gBotDefs.insertLast(int(d.id));
	}
}

// The assist bot for OUR side, whichever that is. gBotDefs already holds all
// three factions' -- armfark, corfast, legaceb -- so this stays faction-neutral
// by construction rather than by three call sites remembering to match.
CCircuitDef@ OurBotDef()
{
	if (!gBotDefsResolved)
		ResolveBotDefs();
	return SideDef3(armfark, corfast, legaceb);
}

bool IsAssistBot(CCircuitUnit@ unit)
{
	if (unit is null)
		return false;
	if (!gBotDefsResolved)
		ResolveBotDefs();
	const int did = int(unit.circuitDef.id);
	for (uint i = 0; i < gBotDefs.length(); ++i) {
		if (gBotDefs[i] == did)
			return true;
	}
	return false;
}

// How far a bot will travel to join work. Beyond this the walk costs more build
// power than it delivers, and the bot is better off on the ordinary ladder.
const float ASSIST_RANGE = 2000.f;

// Builders already on a site before we stop adding more. A site has one build
// position and a queue of bodies around it stops helping.
const uint SITE_STACK = 3;

// Shadows one lead may hold. Scales with the economy, never a flat cap:
// end-game construction with one builder is far too slow, so the richer the
// game the more of the pool stacks behind each lead.
uint GuardStack()
{
	return uint(1.f + aiEconomyMgr.metal.income
			/ ai.GetTunable("apex_guard_per_income", 60.f));
}

// Mirrors the timeout stock CircuitAI uses for its own builder guards
// (CBuilderManager::MakeBuilderTask). CBGuardTask with isInterrupt=true leaves
// lastTouched at -1 while a unit is assigned, so this bounds the task only once
// it is empty, not the attachment.
const int GUARD_TIMEOUT = 60 * SECOND;

const float FRONT_SCORE = 4.f;
const float DEFENCE_SCORE = 6.f;
// Ranked between "is working" (+1) and "is front crew" (+4): it re-orders which
// working constructor gets joined without overriding the front, which is where
// defences are built.
const float ADV_SCORE = 3.f;

int gSites = 0;
int gGuards = 0;

// Bot -> constructor it was told to shadow. Pruned in Update, so no removal hook
// is needed in builder.as.
array<int> gGuardBot;
array<int> gGuardVip;

uint GuardsOn(int vipId)
{
	uint n = 0;
	for (uint i = 0; i < gGuardVip.length(); ++i) {
		if (gGuardVip[i] == vipId)
			++n;
	}
	return n;
}

bool IsBuildWork(int bt)
{
	return (bt >= 0) && (bt < int(Task::BuildType::_SIZE_));
}

bool IsDefenceWork(int bt)
{
	return (bt == Task::BuildType::DEFENCE)
		|| (bt == Task::BuildType::BUNKER)
		|| (bt == Task::BuildType::BIG_GUN);
}

// The constructors this bot may attach to: the mex/front/eco crew, plus the
// commander, which is not on the crew.
array<CCircuitUnit@> Constructors(CCircuitUnit@ skip)
{
	array<CCircuitUnit@> found;
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Crew::gId[i]));
		if ((c is null) || (c is skip) || IsAssistBot(c))
			continue;
		found.insertLast(c);
	}
	if (Builder::gComm !is null)
		found.insertLast(Builder::gComm);
	return found;
}

// A structure already standing and unfinished, that this bot can help with
// whatever it can build.
//
// IBuilderTask::Execute issues CmdRepair once target is set, and CmdBuild only
// while it is null -- so a task with a live target is assistable by any builder,
// and one without it is not unless the bot happens to have that def in its
// buildoptions. target is the gate, not a preference.
IUnitTask@ BestSite(CCircuitUnit@ unit, bool allowDefence = true,
		float range = ASSIST_RANGE)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	array<CCircuitUnit@> cons = Constructors(unit);
	IUnitTask@ best = null;
	float bestScore = 0.f;
	for (uint i = 0; i < cons.length(); ++i) {
		CCircuitUnit@ c = cons[i];
		IUnitTask@ t = c.task;
		if ((t is null) || (t.GetType() != Task::Type::BUILDER))
			continue;
		const int bt = t.GetBuildType();
		if (!IsBuildWork(bt) || (t.target is null))
			continue;
		// Refused a new tower by the defence-share cap: joining an existing one
		// walks the constructor to the same place the cap just declined to send
		// it, and counts against the same share. See Builder::DefenceShareScreen.
		if (!allowDefence && IsDefenceWork(bt))
			continue;
		const AIFloat3 where = t.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist > range)
			continue;
		if (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO)
			continue;
		array<CCircuitUnit@>@ crew = t.GetUnits();
		if ((crew !is null) && (crew.length() >= SITE_STACK))
			continue;
		float score = 1.f;
		if (IsDefenceWork(bt))
			score += DEFENCE_SCORE;
		if (Crew::RoleOf(c) == Crew::FRONT)
			score += FRONT_SCORE;
		score /= (1.f + dist / range);
		if (score > bestScore) {
			bestScore = score;
			@best = t;
		}
	}
	return best;
}

// Nothing is standing yet, so shadow the constructor that is going to put
// something up. Front crew first: that is where the defences this was asked for
// get built.
CCircuitUnit@ BestVip(CCircuitUnit@ unit, float range = ASSIST_RANGE)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	array<CCircuitUnit@> cons = Constructors(unit);
	CCircuitUnit@ best = null;
	float bestScore = 0.f;
	for (uint i = 0; i < cons.length(); ++i) {
		CCircuitUnit@ c = cons[i];
		const bool isFront = (Crew::RoleOf(c) == Crew::FRONT);
		IUnitTask@ t = c.task;
		const bool isWorking = (t !is null) && (t.GetType() == Task::Type::BUILDER)
				&& IsBuildWork(t.GetBuildType());
		if (!isFront && !isWorking)
			continue;
		if (GuardsOn(int(c.id)) >= GuardStack())
			continue;
		const AIFloat3 where = c.GetPos(ai.frame);
		if (!OnMap(where))
			continue;
		const float dist = here.distance2D(where);
		if (dist > range)
			continue;
		if (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO)
			continue;
		float score = isWorking ? 2.f : 1.f;
		if (isFront)
			score += FRONT_SCORE;
		// A preference, not a filter: an advanced constructor is the only one
		// that can be on a moho, a reactor or a gantry, so a lathe-second beside
		// it buys the most.
		if (c.circuitDef.costM >= Builder::ADV_CON_COST)
			score += ADV_SCORE;
		score /= (1.f + dist / range);
		if (score > bestScore) {
			bestScore = score;
			@best = c;
		}
	}
	return best;
}

// Called from AiMakeTask ahead of the ordinary ladder. Returns null for anything
// that is not an assist bot, and for a bot with no work worth joining.
IUnitTask@ Work(CCircuitUnit@ unit)
{
	if (!IsAssistBot(unit))
		return null;

	IUnitTask@ held = unit.task;
	int heldBt = -1;
	if ((held !is null) && (held.GetType() == Task::Type::BUILDER))
		heldBt = held.GetBuildType();

	// Already on real construction: leave it alone. Joining a site and then being
	// pulled off it for a better one is the churn that stopped script-placed
	// defence ever being finished.
	if (IsBuildWork(heldBt))
		return held;

	IUnitTask@ site = BestSite(unit);
	if (site !is null) {
		if (heldBt != Task::BuildType::GUARD) {
			++gSites;
			AiLog(Factory::T() + "apex: assist " + unit.circuitDef.GetName()
				+ " -> site " + int(site.GetBuildType()) + " sites=" + gSites);
		}
		return site;
	}

	// A second Enqueue here would build a task the engine then discards: an
	// existing GUARD and a new GUARD share a build type, and IBuilderTask::
	// Reevaluate only swaps when the type differs.
	if (heldBt == Task::BuildType::GUARD)
		return held;

	CCircuitUnit@ vip = BestVip(unit);
	if (vip is null)
		return null;
	IUnitTask@ shadow = aiBuilderMgr.Enqueue(TaskB::Guard(
			Task::Priority::NORMAL, vip, true, GUARD_TIMEOUT));
	if (shadow is null)
		return null;
	gGuardBot.insertLast(int(unit.id));
	gGuardVip.insertLast(int(vip.id));
	++gGuards;
	AiLog(Factory::T() + "apex: assist " + unit.circuitDef.GetName()
		+ " -> shadow " + vip.circuitDef.GetName()
		+ ((Crew::RoleOf(vip) == Crew::FRONT) ? " (front)" : "")
		+ " guards=" + gGuards);
	return shadow;
}

// THE TERMINAL FALLBACK. Called from the last line of Builder::AiMakeTask.
//
// Returning null from AiMakeTask is not "ask again later": ITaskModule::
// AssignTask does nothing when MakeTask returns null, so the unit is never taken
// out of CIdleTask and CIdleTask::Update asks again every 8 frames for the same
// null.
//
// Both legs JOIN work that already exists -- nothing is enqueued but a GUARD, so
// this cannot outbid expansion for constructor time. GUARD is also the one build
// type IBuilderTask::Reevaluate re-elects even when the unit is standing in
// range (it skips the in-range early return for GUARD alone), so a constructor
// parked here is re-offered every task the engine holds, every update, and
// leaves the moment one is worth taking.
int gFallbacks = 0;

// DEBOUNCE: a bot whose fallback assignment did not stick re-entered this
// rung SEVERAL TIMES A SECOND (n=1105->1108 inside 1.5s, one player, live MP
// 2026-08-18), and every re-entry runs the whole election ladder -- churn
// that both signals and feeds the lag. One offer per bot per
// apex_assist_debounce seconds; between offers the bot simply waits.
array<int> gFbBotId;
array<int> gFbBotUntil;

bool FallbackDebounced(CCircuitUnit@ unit)
{
	const int hold = int(ai.GetTunable("apex_assist_debounce", 5.f)) * SECOND;
	for (uint i = 0; i < gFbBotId.length(); ) {
		if (ai.frame >= gFbBotUntil[i]) {
			gFbBotId.removeAt(i);
			gFbBotUntil.removeAt(i);
			continue;
		}
		if (gFbBotId[i] == int(unit.id))
			return true;
		++i;
	}
	gFbBotId.insertLast(int(unit.id));
	gFbBotUntil.insertLast(ai.frame + hold);
	return false;
}

IUnitTask@ Fallback(CCircuitUnit@ unit, bool isComm, bool allowDefence = true)
{
	// The commander has CommanderIdleWork immediately above this, and
	// CBRepairTask::CanAssignTo refuses it outright.
	if ((unit is null) || isComm)
		return null;
	if (ai.GetTunable("apex_idle_assist", 1.f) <= 0.f)
		return null;
	if (FallbackDebounced(unit))
		return null;
	if (!OnMap(unit.GetPos(ai.frame)))
		return null;

	// THE TERMINAL RUNG SEARCHES WIDE: a walk beats standing idle for the rest
	// of the game, which is what 2,434 idle-still samples in minutes 30-50 of
	// one hosted session actually were.
	const float range = ai.GetTunable("apex_idle_assist_range", 3500.f);

	// An advanced constructor takes the SITE leg only at a full bank. Below
	// that the old reasoning holds -- joining a site locks it out of the
	// decision loop until the structure finishes (IBuilderTask::Reevaluate
	// early-returns in range for everything but GUARD), and a moho may want it
	// any moment. At a full bank nothing above this rung wanted it: the mexup
	// pipeline, the reactor lane and every Brain want already declined, so the
	// lock-in displaces nothing and the lathe converts bank into buildings.
	const bool advMay = aiEconomyMgr.isMetalFull;
	IUnitTask@ site = ((unit.circuitDef.costM >= Builder::ADV_CON_COST) && !advMay)
			? null : BestSite(unit, allowDefence, range);
	if (site !is null) {
		++gFallbacks;
		AiLog(Factory::T() + "apex: idle-assist " + unit.circuitDef.GetName()
			+ " -> site " + int(site.GetBuildType()) + " n=" + gFallbacks);
		return site;
	}

	CCircuitUnit@ vip = BestVip(unit, range);
	if (vip !is null) {
		IUnitTask@ shadow = aiBuilderMgr.Enqueue(TaskB::Guard(
				Task::Priority::NORMAL, vip, true, GUARD_TIMEOUT));
		if (shadow !is null) {
			gGuardBot.insertLast(int(unit.id));
			gGuardVip.insertLast(int(vip.id));
			++gFallbacks;
			AiLog(Factory::T() + "apex: idle-assist " + unit.circuitDef.GetName()
				+ " -> shadow " + vip.circuitDef.GetName()
				+ ((vip.circuitDef.costM >= Builder::ADV_CON_COST) ? " (adv)" : "")
				+ " n=" + gFallbacks);
			return shadow;
		}
	}

	// LAST: assist the nearest factory. A driven line is never idle late game,
	// so a guard here converts an otherwise-idle lathe into production speed --
	// this is the leg that makes the fallback actually terminal (both legs
	// above need a working CONSTRUCTOR in reach, which a mature quiet base
	// often has none of).
	CCircuitUnit@ fac = null;
	float facDist = range;
	const AIFloat3 me = unit.GetPos(ai.frame);
	for (uint i = 0; i < Factory::gFacUnits.length(); ++i) {
		CCircuitUnit@ f = Factory::gFacUnits[i];
		if (f is null)
			continue;
		const AIFloat3 at = f.GetPos(ai.frame);
		if (!OnMap(at))
			continue;
		if (GuardsOn(int(f.id)) >= GuardStack())
			continue;
		const float d = me.distance2D(at);
		if (d < facDist) {
			facDist = d;
			@fac = f;
		}
	}
	if (fac is null)
		return null;
	IUnitTask@ helper = aiBuilderMgr.Enqueue(TaskB::Guard(
			Task::Priority::NORMAL, fac, true, GUARD_TIMEOUT));
	if (helper is null)
		return null;
	gGuardBot.insertLast(int(unit.id));
	gGuardVip.insertLast(int(fac.id));
	++gFallbacks;
	AiLog(Factory::T() + "apex: idle-assist " + unit.circuitDef.GetName()
		+ " -> factory " + fac.circuitDef.GetName() + " n=" + gFallbacks);
	return helper;
}

int gNextLog = 0;

void Update()
{
	for (uint i = 0; i < gGuardBot.length(); ) {
		CCircuitUnit@ bot = ai.GetTeamUnit(Id(gGuardBot[i]));
		bool live = false;
		if (bot !is null) {
			IUnitTask@ t = bot.task;
			live = (t !is null) && (t.GetType() == Task::Type::BUILDER)
					&& (t.GetBuildType() == Task::BuildType::GUARD);
		}
		if (live) {
			++i;
		} else {
			gGuardBot.removeAt(i);
			gGuardVip.removeAt(i);
		}
	}
	if (ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: assist sites=" + gSites
		+ " guards=" + gGuards + " shadowing=" + gGuardBot.length()
		+ " fallback=" + gFallbacks);
}

}  // namespace Assist
