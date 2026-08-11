namespace Military {

bool IsFodder(const CCircuitDef@ cdef)
{
	return (cdef !is null) && (cdef.costM < FODDER_COST)
		&& cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::RAIDER.mask);
}

// True for the units DefaultMakeTask would route into Defend(ATTACK, ...).
// That is its default branch -- every role absent from its role->fight-type map,
// which is assault, skirmish and the custom roles bound to assault -- plus riot
// when no guard task can take the unit. Everything else keeps stock routing.
//
// GROUND AA TRAVELS WITH THE ARMY. Stock routes the AA role to FightType::AA,
// and CAntiAirTask's constructor seeds its position with
// `rand() % terrainWidth/Height` -- an AA squad's destination is a random point
// on the map, unrelated to where our army is or where their air is flying. It
// also merges only same-def units (CanAssignTo compares against the leader's
// circuitDef), so it accumulates one big single-type blob rather than spreading
// a couple of escorts over the front.
//
// Aircraft are excluded: fighters keep FightType::AA because Air:: owns them,
// and a fighter parked in a ground squad cannot intercept anything.
//
// apexearth: "our armies often need at least 1 or 2 AA units attached to them
// but theres a lot of times I don't see that... previously I'm seeing squads of
// 8 aa units very early in the game."
bool WantsMassing(const CCircuitDef@ cdef)
{
	if (cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::SUPPORT.mask))
		return false;
	const Type role = ai.GetBindedRole(cdef.GetMainRole());
	if (role == RT::RIOT)
		return aiMilitaryMgr.GetGuardTaskNum() == 0;
	if (role == RT::AA)
		return !cdef.IsAbleToFly();
	return (role != RT::RAIDER) && (role != RT::ARTY)
		&& (role != RT::AH) && (role != RT::BOMBER) && (role != RT::MINE)
		&& (role != RT::SUPER) && (role != RT::SCOUT) && (role != RT::SUPPORT);
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if (!ApexActive())
		return aiMilitaryMgr.DefaultMakeTask(unit);

	const CCircuitDef@ cdef = unit.circuitDef;
	// Returning null leaves the unit in the idle task -- ITaskModule::AssignTask
	// does nothing when MakeTask gives it nothing, and CIdleTask::Start is a
	// no-op. The unit keeps no orders and stays where it was built. That is how
	// the air force is held at home until Air::Release().
	if (Air::HoldsUnit(unit))
		return null;
	if (Factory::HoldsLateFighter(unit))
		return null;
	if (IsFodder(cdef)) {
		// RAIDERS GROUP BEFORE THEY GO. This used to send every raider straight
		// to its own RAID task the moment it was built, skipping the pool stock
		// parks them in -- Defend(RAID, quota.raid[0]) -- which holds them until
		// they add up to quota.raid[0] power and then promotes them TOGETHER.
		// The shortcut got each raider moving sooner and guaranteed it moved
		// alone, so we trickled ones and twos into a map being raided by packs.
		// Our quota.raid is [10, 65], identical to stock's, so the pack behaviour
		// was always configured -- we were routing around it.
		// apexearth: "they raid us and we never raid them.... they'll attack with
		// like 15 grunts all together... wiping out a lot of our stuff.... we
		// never really do that to the enemy... It really sets the stage/posture
		// for the T2 phase of the game. we *start* the t2 phase behind because of
		// all that raiding."
		return aiMilitaryMgr.DefaultMakeTask(unit);
	}
	// Before the massing pool: a super that reaches WantsMassing is excluded
	// there by role and falls through to DefaultMakeTask, which sends it out
	// alone. See superguard.as.
	if (WantsSuperGuard(cdef) && !SuperReleased())
		return SuperGuardTask(unit);
	if (WantsMassing(cdef)) {
		return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
				Task::FightType::ATTACK, aiMilitaryMgr.quota.attack));
	}
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
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

uint FenceCountNear(const AIFloat3& in pos, float radius)
{
	uint n = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (gFencePos[i].distance2D(pos) <= radius)
			++n;
	}
	return n;
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
	// SUPERS GET STUCK MOST, AND WERE NEVER REGISTERED. A Karganeth arrives as
	// SUPER, not COMBAT, so the walled-in detector never saw the units most
	// likely to be walled in. apexearth, watching a 1v1: "I'm actively in a good
	// situation where Karganeths are blocked" -- and the rule fired zero times
	// in that entire game.
	if ((usage == Unit::UseAs::COMBAT) || (usage == Unit::UseAs::SUPER))
		NotePenned(unit);
	if (usage != Unit::UseAs::FENCE)
		return;
	gFenceId.insertLast(unit.id);
	gFencePos.insertLast(unit.GetPos(ai.frame));
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage == Unit::UseAs::COMBAT)
		ForgetPenned(unit.id);
	if (usage != Unit::UseAs::FENCE)
		return;
	const int id = unit.id;
	for (uint i = 0; i < gFenceId.length(); ++i) {
		if (gFenceId[i] == id) {
			gFenceId.removeAt(i);
			gFencePos.removeAt(i);
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
