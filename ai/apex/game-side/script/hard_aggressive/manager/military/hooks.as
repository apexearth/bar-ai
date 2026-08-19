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
	if (cdef.IsRoleAny(Unit::Role::SCOUT.mask | Unit::Role::SUPPORT.mask))
		return false;
	const Type role = ai.GetBindedRole(cdef.GetMainRole());
	if (role == RT::RIOT)
		return aiMilitaryMgr.GetGuardTaskNum() == 0;
	if (role == RT::AA)
		return false;
	// Raiders raid EARLY, then fight as army: apexearth, watching 14m in --
	// "all our raiders are still trying to fight like raiders, finding a way
	// behind enemy lines... but there is no way around... we need to be
	// trying to use them as an army." gHaveT2 is the codebase's early/late
	// split; before it, raiding pays, after it the flanks are walled.
	if (role == RT::RAIDER)
		return Factory::gHaveT2;
	return (role != RT::ARTY)
		&& (role != RT::AH) && (role != RT::BOMBER) && (role != RT::MINE)
		&& (role != RT::SUPER) && (role != RT::SCOUT) && (role != RT::SUPPORT);
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if (!ApexActive())
		return aiMilitaryMgr.DefaultMakeTask(unit);

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
		if (SpamPhase())
			return aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::SCOUT));
		// Before spam phase, raiders group before they go: routing straight to a
		// RAID task per unit bypassed the pool (Defend(RAID, quota.raid.min)) that
		// holds them until they add up to that power and promotes them together,
		// so they trickled out alone instead of massing into a raid pack.
		// UpdateRaidCaution raises the promotion floor further while still on T1.
		return aiMilitaryMgr.DefaultMakeTask(unit);
	}
	// T3 CHARGERS GO FOR THE BASE. In the massing pool they inherited the
	// group's target logic and spent the game trading with army -- apexearth
	// 2026-08-19: stock "walks their T3s straight into the center of our base.
	// We don't... we get distracted and just fight army." A solo ATTACK task is
	// stock's own shape for a mobile super, and the C++ charge pair (no engage
	// margin, straight-line path -- see IsChargerDef) makes it the beeline.
	// While home is being hit they defend it instead, same gate as the pool.
	if (IsChargerDef(cdef) && (ai.GetTunable("apex_charger_strike", 1.f) > 0.f)) {
		NotePostureDef(cdef, false);
		if ((ai.GetTunable("apex_defend_home", 1.f) > 0.f)
			&& (Builder::BaseUnderAttack() || BaseContested()))
		{
			return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
					Task::FightType::MELEE, aiMilitaryMgr.quota.attack));
		}
		AiLog(Factory::T() + "apex: " + cdef.GetName() + " charges the enemy base");
		return aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::ATTACK));
	}
	// Before the massing pool: a super that reaches WantsMassing is excluded
	// there by role and falls through to DefaultMakeTask, which sends it out
	// alone. See superguard.as.
	if (WantsSuperGuard(cdef) && !SuperReleased())
		return SuperGuardTask(unit);
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
		//
		// An ally being overrun counts as our base being hit: AllyAidPos is the
		// heaviest fight on our side within reach, our own included, from the
		// loss-weighted hotspot each player publishes -- a better "under attack"
		// trigger than BaseUnderAttack(), which only asks about enemy influence
		// at our own start position. It is not gated on here, though: any ally
		// losing metal within reach is true almost continuously in a 4v4, so
		// gating the pool on it kept the army permanently defensive and ground
		// down in place instead of attacking. Publishing stays; the response
		// needs a per-task position this layer does not have -- see CHANGES.md.
		if ((ai.GetTunable("apex_defend_home", 1.f) > 0.f)
			&& (Builder::BaseUnderAttack() || BaseContested()))
		{
			return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
					Task::FightType::MELEE, aiMilitaryMgr.quota.attack));
		}
		return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
				Task::FightType::ATTACK, aiMilitaryMgr.quota.attack));
	}
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

// OUR SQUADS, mirrored from the task hooks. Nothing in the bound surface
// enumerates fighter tasks, so this register is the only way to ask how many
// groups we are fielding or how big they are.
array<IUnitTask@> gSquads;

void AiTaskAdded(IUnitTask@ task)
{
	if ((task is null) || (task.GetType() != Task::Type::FIGHTER))
		return;
	gSquads.insertLast(task);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	for (uint i = 0; i < gSquads.length(); ++i) {
		if (gSquads[i] is task) {
			gSquads.removeAt(i);
			return;
		}
	}
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
	uint attack = 0;
	uint defend = 0;
	for (uint i = 0; i < gSquads.length(); ++i) {
		array<CCircuitUnit@>@ on = gSquads[i].GetUnits();
		if ((on is null) || (on.length() == 0))
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

// How recently, and how repeatedly, we have lost a tower near here. Zero is
// "never"; each loss contributes its remaining freshness, so a position that has
// eaten several towers scores above one that has eaten one. Expired entries are
// dropped as they are walked, which is the only place this list shrinks.
float FenceLostNear(const AIFloat3& in pos, float radius)
{
	const float life = ai.GetTunable("apex_fence_loss_memory", 180.f) * float(SECOND);
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
	if (usage == Unit::UseAs::COMBAT)
		ForgetPenned(unit.id);
	if (usage != Unit::UseAs::FENCE)
		return;
	Builder::NoteShieldLost(unit.circuitDef);   // feeds the LRPC shield want
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
