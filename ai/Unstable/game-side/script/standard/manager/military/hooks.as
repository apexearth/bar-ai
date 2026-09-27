namespace Military {

bool IsFodder(const CCircuitDef@ cdef)
{
	// Never a flyer: an air scout (Peeper, 39 metal, SCOUT role) passed the
	// cost+role test and the spam routing claimed it -- but spam is ground
	// fodder (spread, take fire, attack the fog); an air scout on that
	// pattern is just intel thrown away (apexearth: "air scouts -- those
	// don't count as spam"). Air:: owns everything that flies.
	return (cdef !is null) && (cdef.costM < FODDER_COST())
		&& !cdef.IsAbleToFly()
		&& cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::RAIDER.mask);
}

// True for the units DefaultMakeTask would route into Defend(ATTACK, ...).
// That is its default branch -- every role absent from its role->fight-type map,
// which is assault, skirmish and the custom roles bound to assault -- plus riot
// when no guard task can take the unit. Everything else keeps stock routing.
//
// Ground AA does NOT want massing. It was pulled in briefly (2026-08-14) to
// dodge CAntiAirTask's `rand() % terrainWidth/Height` blob positioning, but
// every AA-role def here (armjeth/corsent/legaabot, and the static
// armrl/corrl/legrl and armferret/cormadsam/legflak) is `onlytargetcategory
// VTOL` -- it cannot hit a ground unit at all. WantsMassing feeds the
// Defend->ATTACK pool (see below), so that put weapon-less units into an
// offensive ground push, where they died for nothing: apexearth watching
// live, 2026-08-14, "we've sent in those AA units to attack and they've been
// killed... worthless." Losing the blob-position fix costs less than that.
// Aircraft are excluded the same way: fighters keep FightType::AA because
// Air:: owns them, and a fighter parked in a ground squad cannot intercept.
bool WantsMassing(const CCircuitDef@ cdef)
{
	// A rolling bomb carries one explosion to one place; a squad of them dies
	// to one blast and waiting to form up spends the only asset it has.
	if (IsRollingBomb(cdef))
		return false;
	if (cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::SUPPORT.mask))
		return false;
	const Type role = ai.GetBindedRole(cdef.GetMainRole());
	if (role == RT::RIOT)
		return aiMilitaryMgr.GetGuardTaskNum() == 0;
	if (role == RT::AA)
		return false;
	// RAIDERS RAID FOR THE WHOLE GAME, as stock BARb does (apexearth
	// 2026-08-30: "we need to adapt our raider stance to be more like stable
	// barbs raider usage. I believe we have clearly regressed there").
	//
	// This flipped to the massing pool at gHaveT2, on his earlier read that
	// raiders were "finding a way behind enemy lines... but there is no way
	// around". The measurement says the flip took the whole class: across 11
	// matches the elected-fight-type ledger held ZERO raid tasks and zero
	// attack tasks -- every raider became line army the moment our advanced
	// lab stood. apex_raider_massing restores the old behaviour at 1.
	if (role == RT::RAIDER)
		return Factory::gHaveT2
			&& (ai.GetTunable("apex_raider_massing", TUNE_RAIDER_MASSING) > 0.f);
	// Mobile artillery fights as the squads' back row: rows stand each def at
	// its own weapon range, siege attr fears proximity, and the front rows ARE
	// the allied vision a long gun needs (the whole family outranges its own
	// sight -- Hound 650/400, Sharpshooter 900/455). Solo CArtilleryTask can
	// elect only STATIC targets and travels alone, so a Hound crossed the map
	// blind and died acquiring its own los (apexearth 2026-08-29: "we don't
	// want them walking up blind getting into LOS range").
	if (role == RT::ARTY)
		return ai.GetTunable("apex_arty_mass", TUNE_ARTY_MASS) > 0.f;
	return (role != RT::AH) && (role != RT::BOMBER) && (role != RT::MINE)
		&& (role != RT::SUPER) && (role != RT::SCOUT) && (role != RT::SUPPORT);
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if (!ApexActive())
		return aiMilitaryMgr.DefaultMakeTask(unit);
	// One wrapper so every return below is recorded -- see NoteFightElection.
	const double _mt = Perf::T0();
	IUnitTask@ elected = MakeTaskInner(unit);
	Perf::Add("hk.maketask.military", _mt);
	NoteFightElection(unit, elected);
	return elected;
}

// WHICH BRANCH TOOK THE UNIT. "We hold no raid tasks" cannot say whether the
// raiders were never built, or were built and claimed by escort or cover duty
// on the way past -- and those are opposite fixes. Counted at the election,
// which is the only place the unit and the branch are both known.
array<string> gElectTag;
array<int>    gElectN;
int gNextElectLog = 0;

// Metal standing in cover pools, by unit: added at election, dropped when
// the unit is removed. There is no unit-by-id lookup, so the cost is kept.
array<int> gCoverId;
array<float> gCoverCost;
float gCoverHeldM = 0.f;

void NoteCover(CCircuitUnit@ unit)
{
	gCoverId.insertLast(unit.id);
	gCoverCost.insertLast(Catalog::gCostM[int(unit.circuitDef.id)]);
	gCoverHeldM += Catalog::gCostM[int(unit.circuitDef.id)];
}

void ForgetCover(int id)
{
	for (uint i = 0; i < gCoverId.length(); ++i) {
		if (gCoverId[i] == id) {
			gCoverHeldM -= gCoverCost[i];
			gCoverId.removeAt(i);
			gCoverCost.removeAt(i);
			return;
		}
	}
}

float CoverHeldM()
{
	return (gCoverHeldM > 0.f) ? gCoverHeldM : 0.f;
}

// Our share of the raider metal they have fielded; with the bound off, the
// coverage need alone decides, as before.
float CoverCapM()
{
	if (ai.GetTunable("apex_cover_by_raid", TUNE_COVER_BY_RAID) <= 0.f)
		return 1e9f;
	return EnemyCostOf(Unit::Role::RAIDER.type) * Market::AnswerShare();
}

IUnitTask@ NoteElect(const string tag, IUnitTask@ task)
{
	for (uint i = 0; i < gElectTag.length(); ++i) {
		if (gElectTag[i] == tag) {
			++gElectN[i];
			return task;
		}
	}
	gElectTag.insertLast(tag);
	gElectN.insertLast(1);
	return task;
}

void ElectCensus()
{
	if (ai.frame < gNextElectLog)
		return;
	gNextElectLog = ai.frame + 60 * SECOND;
	string msg = "apex: elect";
	for (uint i = 0; i < gElectTag.length(); ++i)
		msg += " " + gElectTag[i] + "=" + gElectN[i];
	msg += " | coverM=" + int(CoverHeldM()) + "/" + int(CoverCapM())
			+ " need=" + int(CoverNeedM());
	AiLog(Factory::T() + msg);
}

IUnitTask@ MakeTaskInner(CCircuitUnit@ unit)
{

	// A unit built off a standing queue finishes with no owning task and lands in
	// CIdleTask, so this hook is the only thing that can give it a role. An idle
	// unit re-asks every idle update, so requests far above units registered is
	// what "the army came out unassigned and stood still" looks like from a log.
	Brain::NoteMilRequest();

	const CCircuitDef@ cdef = unit.circuitDef;
	// Returning null leaves the unit in the idle task -- ITaskModule::AssignTask
	// does nothing when MakeTask gives it nothing, and CIdleTask::Start is a
	// no-op. The unit keeps no orders and stays where it was built. That is how
	// the air force is held at home until Air::Release().
	if (Air::HoldsUnit(unit))
		return null;
	if (Factory::HoldsLateFighter(unit))
		return null;
	if ((ai.GetTunable("apex_stock_army", TUNE_STOCK_ARMY) > 0.f)
		&& !cdef.IsAbleToFly() && !cdef.IsRoleAny(Unit::Role::COMM.mask)
		&& !Catalog::gBuilder[int(cdef.id)] && (Catalog::gPower[int(cdef.id)] > 1.f))
		return NoteElect("stock.army", aiMilitaryMgr.DefaultMakeTask(unit));
	// A RELEASED BOMBER BOMBS -- whatever its config role says. The heavy tier
	// the strike holds and releases (armblade, corcrw, legfort) carries role
	// "heavy", not "bomber": DefaultMakeTask has no BOMB entry for that role
	// and WantsMassing does not exclude it, so every one we released joined the
	// GROUND massing pool and traded with armies. ANTI_STAT and the eco-value
	// target scoring live in CBombTask::FindTarget, which those never reached.
	if (Air::IsBomberDef(int(cdef.id)))
		return NoteElect("air.bomb",
				aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::BOMB)));
	// A WAVE FIGHTER FLIES WITH A BOMBER (apexearth 2026-09-16: "when we send
	// bombers ... have fighters to guard them"). Stock's AA task hunts on its
	// own; the guard task follows the bomber and engages only air.
	if (Air::InWave(unit.id) && Air::IsFighterDef(int(cdef.id))
		&& (ai.GetTunable("apex_air_cover", TUNE_AIR_COVER) > 0.f)) {
		CCircuitUnit@ b = Air::WaveBomberFor(unit);
		if (b !is null)
			return NoteElect("air.cover", aiMilitaryMgr.Enqueue(TaskF::Guard(b)));
	}
	// A ROLLING BOMB IS NEVER PACKED. It is roled `raider`, so the director
	// would pull it into a pack and the pack would walk it in formation: one
	// blast then takes the whole group, and the walk spends the surprise that
	// is the only thing it carries. It keeps stock raider routing, alone.
	if (IsRollingBomb(cdef)) {
		DropRaidClaim(int(unit.id));
		return NoteElect("bomb.solo", aiMilitaryMgr.DefaultMakeTask(unit));
	}
	// A UNIT THE RAID DIRECTOR PULLED goes to the pack, ahead of every duty
	// below -- it was taken off one of them on purpose. See raid.as.
	if (RaidClaimed(int(unit.id))) {
		DropRaidClaim(int(unit.id));
		IUnitTask@ pack = RaidTaskFor();
		if (pack !is null)
			return NoteElect("raid.pull", pack);
	}
	// ESCORT DUTY outranks the pools for cheap ground army: an exposed
	// constructor without an escort claims one guard (Market keeps the
	// one-per-worker registry).
	// ESCORTS FIGHT CLOSE, and must be fast enough to catch a raider or tough
	// enough to outlast one -- Market::EscortWorthy is the single test, shared
	// with the production floor that ORDERS them, so nothing is built for the
	// duty that would then refuse it.
	if ((Market::EscortWorthy(int(cdef.id)) || Market::FighterEscortWorthy(int(cdef.id)))
		&& (ai.GetTunable("apex_con_escort", TUNE_CON_ESCORT) > 0.f)) {
		// A unit back in the election is no longer guarding anyone (retreat,
		// aborted task); its pairing dropped only on death, so its worker
		// read escorted by nobody for the rest of the game.
		Market::EscortGone(unit.id);
		CCircuitUnit@ vip = Market::EscortNeeded(unit);
		if (vip !is null) {
			AiLog(Factory::T() + "apex: " + cdef.GetName() + " #" + unit.id
				+ " escorts " + vip.circuitDef.GetName() + " #" + vip.id);
			return NoteElect("escort", aiMilitaryMgr.Enqueue(TaskF::Guard(vip)));
		}
	}
	// COVER UNITS: what the base buys against raiders (guardposts.as), spread
	// over the buildings (apexearth: "keep our units spread out enough to
	// react quickly"). Two bounds, his 2026-09-12 ruling after a 40-minute
	// game held 427 units here against 13-27k of enemy army: the pool
	// promotes to ATTACK like stock's, so a full pool leaves and home keeps
	// whatever is still filling; and no more metal is posted than the
	// raider metal they have fielded -- our share of it, the same answer law
	// the AA counter uses -- so a base facing nothing keeps a small guard.
	// The need itself is not the bound: it counts sites, and a pool never
	// stands on the posts, so at scale it never closed.
	if ((Military::CoverNeedM() > 0.f) && !cdef.IsAbleToFly()
		&& Market::LineCombat(int(cdef.id))
		&& (Market::CoverPerMetal(int(cdef.id)) >= 1.f)
		&& (CoverHeldM() < CoverCapM()))
	{
		NotePostureDef(cdef, false);
		NoteCover(unit);
		const bool leaves = ai.GetTunable("apex_cover_leaves", TUNE_COVER_LEAVES) > 0.f;
		return NoteElect("cover", aiMilitaryMgr.Enqueue(TaskF::Defend(
				leaves ? Task::FightType::ATTACK : Task::FightType::MELEE,
				leaves ? Task::FightType::ATTACK : Task::FightType::MELEE,
				aiMilitaryMgr.quota.attack)));
	}
	if (IsFodder(cdef)) {
		// The set of defs the spam posture applies to, discovered rather than
		// listed. See NoteFodderDef.
		NoteFodderDef(cdef);
		// In spam phase they do not form squads: CScoutTask is the only fighter
		// task in CircuitAI that cannot become a group (derives from IFighterTask,
		// not ISquadTask, so no CheckMergeTask), and it is used here regardless of
		// role -- ITaskModule::AssignTask calls AssignTo directly on whatever
		// MakeTask returns, bypassing CanAssignTo's role check. Each task's
		// destination (CMilitaryManager::GetScoutPosition) claims its own
		// unscouted metal cluster, so N of them spread over N clusters instead of
		// walking the same lane. This also drops the quota.scout ceiling, since it
		// does not route through DefaultMakeTask.
		// SPOTTING IS FOR SCOUTS, NOT FOR RAIDERS. CScoutTask cannot group
		// (it derives from IFighterTask, not ISquadTask, so nothing merges
		// it) and each task claims its own unscouted metal cluster, which is
		// map coverage rather than pressure. Routing the raider role through
		// it after T2 is the second half of why we hold no raid tasks at all;
		// stock never does this. Scout-role chaff still spreads out.
		if (SpamPhase()
			&& (!cdef.IsRoleAny(Unit::Role::RAIDER.mask)
				|| (ai.GetTunable("apex_spam_raiders", TUNE_SPAM_RAIDERS) > 0.f)))
			return NoteElect("spamscout", aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::SCOUT)));
		// Before spam phase, raiders group before they go: routing straight to a
		// RAID task per unit bypassed the pool (Defend(RAID, quota.raid.min)) that
		// holds them until they add up to that power and promotes them together,
		// so they trickled out alone instead of massing into a raid pack.
		// UpdateRaidCaution raises the promotion floor further while still on T1.
		return NoteElect("fodder.stock", aiMilitaryMgr.DefaultMakeTask(unit));
	}
	// T3 CHARGERS GO FOR THE BASE. In the massing pool they inherited the
	// group's target logic and spent the game trading with army -- apexearth
	// 2026-08-19: stock "walks their T3s straight into the center of our base.
	// We don't... we get distracted and just fight army." A solo ATTACK task is
	// stock's own shape for a mobile super, and the C++ charge pair (no engage
	// margin, straight-line path -- see IsChargerDef) makes it the beeline.
	// While home is being hit they defend it instead, same gate as the pool.
	if (IsChargerDef(cdef) && (ai.GetTunable("apex_charger_strike", TUNE_CHARGER_STRIKE) > 0.f)) {
		NotePostureDef(cdef, false);
		// The pool's own gate, need-capped and registered: the raw
		// under-attack test parked every Titan born while shells landed.
		if (HoldHome()) {
			AiLog(Factory::T() + "apex: " + cdef.GetName() + " holds home heldM="
				+ int(gHoldHeldM) + " needM=" + int(HoldNeedM()));
			NoteHold(unit);
			return NoteElect("charger.hold", aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
					Task::FightType::MELEE, aiMilitaryMgr.quota.attack)));
		}
		AiLog(Factory::T() + "apex: " + cdef.GetName() + " charges the enemy base");
		return NoteElect("charger", aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::ATTACK)));
	}
	// Before the massing pool: a super that reaches WantsMassing is excluded
	// there by role and falls through to DefaultMakeTask, which sends it out
	// alone. See superguard.as.
	if (WantsSuperGuard(cdef) && !SuperReleased())
		return NoteElect("superguard", SuperGuardTask(unit));
	if (WantsMassing(cdef)) {
		// Registered so ApplyRetreatPosture can weigh its cost against income.
		NotePostureDef(cdef, false);
		// WHILE OUR BASE IS BEING HIT, THE POOL DOES NOT LEAVE.
		//
		// quota.attack (the third argument) is a PROMOTION TRIGGER: at that much
		// power the DEFEND task converts to ATTACK and marches on the enemy, so
		// the moment we have enough army to defend ourselves is the moment it
		// leaves, whether or not home is under attack. Promoting to MELEE instead
		// holds it: nothing in CircuitAI ever enqueues a MELEE task, and
		// UpdateDefenceTasks only rewrites maxPower for tasks that promote to
		// ATTACK, so a MELEE-promoting task keeps the power we gave it and never
		// converts -- the pool stays a defence and CDefendTask sends it at
		// whatever is threatening us. It reverts by itself: this only decides the
		// task a unit is joining now, so once the attack is over, new units pool
		// into ordinary attack-promoting tasks again.
		// An ally being overrun is answered by gift.as (army given to it), not
		// here: gating the pool on "any ally losing metal" kept the army
		// permanently defensive in a 4v4.
		// A MELEE-promoting pool never leaves (see above). Three reasons to be
		// in one: our own base is being hit, buildings of ours are dying on our
		// own ground, or we are not the aggressor in this game and they are --
		// ConservativeStance, apexearth's own doctrine: if we chose economy and
		// they chose offence, the army we bought is for holding, not for
		// trading. Every one of these reverts by itself; it only decides the
		// task a unit joins now.
		if (HoldHome()) {
			NoteHold(unit);
			return NoteElect("mass.hold", aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
					Task::FightType::MELEE, aiMilitaryMgr.quota.attack)));
		}
		// `check` IS THE REINFORCE HATCH, AND MELEE NAILED IT SHUT.
		//
		// TaskF::Defend's three-argument form is Defend(check, promote, power).
		// CDefendTask::Update tests `!GetTasks(check).empty()` to decide whether
		// this pool may join an attack that already exists -- and NOTHING in this
		// codebase ever enqueues a MELEE task. The hold branch above relies on
		// exactly that fact deliberately (see its comment); copying the same
		// MELEE into the ATTACK branch's `check` slot made the clause
		// permanently false, so the only remaining way out of defence was a
		// single pool, alone, reaching its whole power bar.
		//
		// Stock passes the TWO-argument form, which sets check = promote =
		// ATTACK: the instant one pool promotes, every other pool sees an attack
		// exists and merges into it, and one pool bootstraps the army. That is
		// how BARb arrives at our base while we hold 2,000 metal of DEFEND at
		// home with attack=0/0/0 (fightcensus, 20260907-202519, final samples).
		//
		// The guard the author actually wanted is untouched and now reachable:
		// apex_reinforce_frac still demands half a bar before a pool leaves, so
		// this is not the old any-attack-exists shortcut that fed solos.
		return NoteElect("mass.attack", aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK,
				Task::FightType::ATTACK, aiMilitaryMgr.quota.attack)));
	}
	return NoteElect("stock", aiMilitaryMgr.DefaultMakeTask(unit));
}

// WHAT A COMBAT UNIT WAS DOING BEFORE IT RETREATED.
//
// apexearth 2026-08-19, on a death report where 35% of lost metal read simply
// "retreat": "you should be looking at what the last action was just before
// retreat." A retreat is never the decision that killed the unit -- it is the
// consequence of one, and the death log could not name it.
//
// Builder::SampleTaskHist cannot serve: it walks Crew::gId, which combat units
// never join, and nothing enumerates our own units. AiMakeTask is where a
// fighter is ELECTED, so it is the one place unit and new task are both known;
// a retreat enqueued in C++ never passes through here, which is exactly why the
// last election is still the answer to "doing what".
array<int>    gFHistId;
array<string> gFHistBuf;
const uint FIGHT_HIST_MAX = 6;

// The state a unit carried INTO a transition -- hp and map depth -- appended
// to every fight-hist entry so a death reads as a story instead of a terminal
// task. apexearth 2026-08-21: "no 'retreat' is not a valid answer. You need
// to be recording something like 'attack-retreat'... I still see units doing
// stupid things and we need to answer why."
string FightCtx(CCircuitUnit@ u)
{
	if (u is null)
		return "";
	return ":h" + int(u.GetHealthPercent() * 100.f)
		+ ":w" + formatFloat(Military::ForwardFraction(u.GetPos(ai.frame)), "", 0, 2);
}

int FightHistSlot(int id)
{
	for (uint i = 0; i < gFHistId.length(); ++i) {
		if (gFHistId[i] == id)
			return int(i);
	}
	return -1;
}

void NoteFightElection(CCircuitUnit@ unit, IUnitTask@ task)
{
	if ((unit is null) || (task is null))
		return;
	if (task.GetType() != Task::Type::FIGHTER)
		return;
	// The same election is the only place our own combat units can be
	// registered -- nothing enumerates them. See withdraw.as.
	NoteCombatUnit(int(unit.id));
	AppendFightHist(int(unit.id), "f" + task.GetFightType(), FightCtx(unit));
}

// Shared with withdraw.as, which marks a pull-back order as "W" so the
// unit-destroyed line shows whether we ever told the dead unit to leave.
void AppendFightHist(int id, const string tag, const string ctx = "")
{
	int s = FightHistSlot(id);
	if (s < 0) {
		// Bounded: drop the oldest slot rather than growing for every unit
		// built across a whole match.
		if (gFHistId.length() >= 512) {
			gFHistId.removeAt(0);
			gFHistBuf.removeAt(0);
		}
		gFHistId.insertLast(id);
		gFHistBuf.insertLast("");
		s = int(gFHistId.length()) - 1;
	}
	array<string>@ parts = gFHistBuf[s].split(";");
	if ((parts.length() == 1) && (parts[0] == ""))
		parts.removeLast();
	// Transitions only, or one long attack fills the ring with itself.
	if ((parts.length() > 0) && (parts[parts.length() - 1].findFirst(tag) == 0))
		return;
	parts.insertLast(tag + "@" + ai.frame + ctx);
	while (parts.length() > FIGHT_HIST_MAX)
		parts.removeAt(0);
	string joined = "";
	for (uint j = 0; j < parts.length(); ++j) {
		if (j > 0)
			joined += ";";
		joined += parts[j];
	}
	gFHistBuf[s] = joined;
}

string TakeFightHistFor(int id)
{
	const int s = FightHistSlot(id);
	if (s < 0)
		return "";
	const string h = gFHistBuf[s];
	gFHistId.removeAt(uint(s));
	gFHistBuf.removeAt(uint(s));
	return h;
}

// OUR SQUADS, mirrored from the task hooks. Nothing in the bound surface
// enumerates fighter tasks, so this register is the only way to ask how many
// groups we are fielding or how big they are.
array<IUnitTask@> gSquads;

void AiTaskAdded(IUnitTask@ task)
{
	const double _t = Perf::T0();
	TaskAddedInner(task);
	Perf::Add("hk.taskadd.mil", _t);
}

// S7: THIS CALLBACK MAY BE DEAD. The fight census built on gSquads reports
// live=0 for a whole game -- every type zero, every count zero -- which is
// either an army that fields no squads or a hook nobody calls. Those look
// identical in the census, so count the raw arrivals and what type they were.
int gTaskAddCalls = 0;
int gTaskAddFighter = 0;
int gTaskAddNull = 0;
array<int> gTaskAddByType(8, 0);

void TaskAddedInner(IUnitTask@ task)
{
	++gTaskAddCalls;
	if (task is null) {
		++gTaskAddNull;
		return;
	}
	const int ty = int(task.GetType());
	if ((ty >= 0) && (ty < int(gTaskAddByType.length())))
		++gTaskAddByType[ty];
	if (task.GetType() != Task::Type::FIGHTER)
		return;
	++gTaskAddFighter;
	gSquads.insertLast(task);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	const double _t = Perf::T0();
	TaskRemovedInner(task, done);
	Perf::Add("hk.taskdel.mil", _t);
}

// 292 fighter tasks were inserted and the register still reads length 0, so
// either every one of them is removed as fast as it arrives or something else
// empties it. Count the removals that MATCH against the ones that do not.
int gTaskDelCalls = 0;
int gTaskDelHit = 0;
int gTaskDelMiss = 0;
int gSquadsPeak = 0;

void TaskRemovedInner(IUnitTask@ task, bool done)
{
	++gTaskDelCalls;
	if (int(gSquads.length()) > gSquadsPeak)
		gSquadsPeak = int(gSquads.length());
	for (uint i = 0; i < gSquads.length(); ++i) {
		if (gSquads[i] is task) {
			gSquads.removeAt(i);
			++gTaskDelHit;
			return;
		}
	}
	++gTaskDelMiss;
}

// Groups with units actually in them. An empty fighter task is a request nobody
// has been elected onto, not a squad on the field.
uint SquadCount()
{
	uint n = 0;
	for (uint i = 0; i < gSquads.length(); ++i) {
		array<CCircuitUnit@>@ on = gSquads[i].GetUnits();
		if ((on !is null) && (on.length() > 0))
			++n;
	}
	return n;
}

// Squads an ESCORT can attach to.
//
// SquadCount above counts EVERY fighter task -- rally, guard, defend, scout,
// raid, attack, bomb, arty, AA, AH, support, super -- because until
// GetFightType was bound nothing could tell them apart. CSupportTask only ever
// joins an ATTACK task, or a DEFEND task when there is no attack at all, so
// those two are the only ones that can take a radar or a jammer.
uint EscortSquadCount()
{
	// Only squads worth a real army's metal are owed sensors. Attack-else-
	// defend mirrors CSupportTask's own candidate list: counting squads the
	// attacher will never pick buys escorts that stand at home waiting.
	const float bar = ai.GetTunable("apex_escort_squad_value", TUNE_ESCORT_SQUAD_VALUE);
	uint attack = 0;
	uint defend = 0;
	for (uint i = 0; i < gSquads.length(); ++i) {
		array<CCircuitUnit@>@ on = gSquads[i].GetUnits();
		if ((on is null) || (on.length() == 0))
			continue;
		float value = 0.f;
		for (uint j = 0; j < on.length(); ++j)
			value += on[j].circuitDef.costM;
		if (value <= bar)
			continue;
		const int ft = gSquads[i].GetFightType();
		if (ft == int(Task::FightType::ATTACK))
			++attack;
		else if (ft == int(Task::FightType::DEFEND))
			++defend;
	}
	return (attack > 0) ? attack : defend;
}

// Where our own defences stand.
//
// Nothing in the ~405 bindings enumerates friendly units or asks "what is
// defended here", so the only way to answer that is to accumulate it from the
// events. MilitaryManager's fenceFinished/fenceDestroyed handlers call
// UnitAdded/UnitRemoved with UseAs::FENCE for every defence structure we own,
// whatever placed it -- build_chain porcupine clusters, DefaultMakeDefence, or
// Builder::Fortify -- so this register sees all of them, not just ours.
//
// FENCE fires on FINISHED, not on placement. A tower under construction is
// therefore invisible here; Builder::Fortify counts its own outstanding orders
// separately for that reason.
array<int>      gFenceId;
array<AIFloat3> gFencePos;
// Parallel to the two above and maintained with them: what each one IS. Nothing
// else records it -- gFencePos is positions only -- so "is the thing we are about
// to place better than what already stands here" had no way to be asked.
array<const CCircuitDef@> gFenceDef;

// WHERE A TOWER OF OURS DIED. AiUnitRemoved dropped the position and kept
// nothing, so ground that had just proved it needs defending read identical to
// ground nobody has ever contested. Nothing else in the AI records this: the
// FENCE removal event is the only notice we get.
array<AIFloat3> gFenceLostPos;
array<int>      gFenceLostAt;

uint FenceCountNear(const AIFloat3& in pos, float radius)
{
	uint n = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (gFencePos[i].distance2D(pos) <= radius)
			++n;
	}
	return n;
}

// The guns already covering this ground, and the dearest of them.
//
// Only a fence with a SURFACE gun counts. An anti-air turret, a jammer or a line
// of dragon teeth does not shoot at something walking in, so counting one as
// cover would refuse a ground tower on ground that has none.
uint FenceGunsNear(const AIFloat3& in pos, float radius, float& out topCost)
{
	topCost = 0.f;
	uint n = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (gFencePos[i].distance2D(pos) > radius)
			continue;
		if (i >= gFenceDef.length())
			continue;
		const CCircuitDef@ d = gFenceDef[i];
		if ((d is null) || (d.GetSurfThreat() <= 0.f))
			continue;
		++n;
		if (d.costM > topCost)
			topCost = d.costM;
	}
	return n;
}

// The METAL of surface guns covering this ground. A count reads one LLT as
// cover against a heavy push; metal does not.
float FenceGunMetalNear(const AIFloat3& in pos, float radius)
{
	float m = 0.f;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (gFencePos[i].distance2D(pos) > radius)
			continue;
		if (i >= gFenceDef.length())
			continue;
		const CCircuitDef@ d = gFenceDef[i];
		if ((d !is null) && (d.GetSurfThreat() > 0.f))
			m += d.costM;
	}
	return m;
}

// Distance to the nearest of our own defences: the fence ring is the measured
// extent of the base, so this is "how far from our edge". Function rather than
// a gFencePos read because basedefence.as compiles before this file.
// Every defence we hold, at cost. What the base can hold with when the army is
// away or still being built -- read by the T2 army floor.
float OwnDefenceMetal()
{
	float m = 0.f;
	for (uint i = 0; i < gFenceDef.length(); ++i) {
		const CCircuitDef@ d = gFenceDef[i];
		if (d !is null)
			m += d.costM;
	}
	return m;
}

float NearestFenceDist(const AIFloat3& in pos)
{
	float best = 1.0e9f;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		const float d = gFencePos[i].distance2D(pos);
		if (d < best)
			best = d;
	}
	return best;
}

// How recently, and how repeatedly, we have lost a tower near here. Zero is
// "never"; each loss contributes its remaining freshness, so a position that has
// eaten several towers scores above one that has eaten one. Expired entries are
// dropped as they are walked, which is the only place this list shrinks.
float FenceLostNear(const AIFloat3& in pos, float radius)
{
	const float life = ai.GetTunable("apex_fence_loss_memory", TUNE_FENCE_LOSS_MEMORY) * float(SECOND);
	if (life <= 0.f)
		return 0.f;
	float w = 0.f;
	for (int i = int(gFenceLostAt.length()) - 1; i >= 0; --i) {
		const float age = float(ai.frame - gFenceLostAt[i]);
		if (age > life) {
			gFenceLostPos.removeAt(i);
			gFenceLostAt.removeAt(i);
			continue;
		}
		if (gFenceLostPos[i].distance2D(pos) <= radius)
			w += 1.f - (age / life);
	}
	return w;
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	const double _t = Perf::T0();
	UnitAddedInner(unit, usage);
	Perf::Add("hk.unitadd.mil", _t);
}

void UnitAddedInner(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
	// A Karganeth arrives as SUPER, not COMBAT, so the walled-in detector never
	// saw the units most likely to be walled in unless SUPER is registered too.
	if ((usage == Unit::UseAs::COMBAT) || (usage == Unit::UseAs::SUPER))
		NotePenned(unit);
	if (usage != Unit::UseAs::FENCE)
		return;
	gFenceId.insertLast(unit.id);
	gFencePos.insertLast(unit.GetPos(ai.frame));
	gFenceDef.insertLast(unit.circuitDef);
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	const double _t = Perf::T0();
	UnitRemovedInner(unit, usage);
	Perf::Add("hk.unitdel.mil", _t);
}

void UnitRemovedInner(CCircuitUnit@ unit, Unit::UseAs usage)
{
	// SUPER is registered by UnitAddedInner, so it has to be forgotten here too
	// or the register keeps an id that only the null sweep will ever clear.
	if ((usage == Unit::UseAs::COMBAT) || (usage == Unit::UseAs::SUPER)) {
		ForgetPenned(unit.id);
		ForgetCover(unit.id);
		ForgetHold(unit.id);
	}
	if (usage != Unit::UseAs::FENCE)
		return;
	const int id = unit.id;
	for (uint i = 0; i < gFenceId.length(); ++i) {
		if (gFenceId[i] == id) {
			if (OnMap(gFencePos[i])) {
				gFenceLostPos.insertLast(gFencePos[i]);
				gFenceLostAt.insertLast(ai.frame);
			}
			gFenceId.removeAt(i);
			gFencePos.removeAt(i);
			if (i < gFenceDef.length())
				gFenceDef.removeAt(i);
			return;
		}
	}
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

}  // namespace Military
