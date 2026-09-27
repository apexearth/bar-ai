namespace Military {

//------------------------------------------------------------------------------
// T3 HEAVIES STAND ON THE DEFENCE LINE INSTEAD OF WALKING OUT ALONE.
//
// CMilitaryManager::DefaultMakeTask has one branch for the SUPER role, and for a
// MOBILE super it is `Enqueue(TaskF::Common(ATTACK))` -- a brand new CAttackTask
// holding exactly one unit, the frame that unit finishes. So a Korgoth crosses
// the map on its own, and the second one gets its own task and crosses on its
// own too. Nothing routes them home and nothing groups them.
//
// The mechanisms this uses, all read from CircuitAI:
//
//  - A DEFEND task whose `promote` is NOT ATTACK is skipped by
//    CMilitaryManager::UpdateDefenceTasks, which otherwise rewrites maxPower
//    every 5 s to max(minAttackers, PreMaxGroupThreat). That is why the ordinary
//    massing pool cannot be given a holding power and this can.
//  - CDefendTask::Update promotes on
//    `(attackPower >= maxPower) || !GetTasks(check).empty()`. Nothing in
//    CircuitAI ever enqueues a MELEE task, so the second clause is dead, and
//    SUPER_HOLD_POWER puts the first out of reach.
//  - With no target inside our own influence, CDefendTask falls back to
//    CMilitaryManager::FillFrontPos, which returns the DEFENCE POINTS of the
//    metal cluster nearest our lane toward the enemy. That is where the squad
//    parks: on our own defence line, facing them.
//  - CDefendTask::CanAssignTo requires an equal `promote`, so this squad merges
//    only with itself, never with the ATTACK-promoting massing pool.
//
// promote is RALLY rather than a type that can never fire: if maxPower is ever
// reached, CRallyTask carries maxPower 1 and converts the whole group into a
// single ATTACK task, so the failure mode is "they attack together" rather than
// "they stand still forever".
const float SUPER_HOLD_POWER = 1000000.f;

// Which units this is about. Role SUPER is the config's own word for it --
// armbanth, armthor, corkorg, corjugg, armepoch, corblackhy -- but Legion tags
// none of its gantry units that way (legeheatraymech, 23,500 metal, is only
// "heavy"), so keying on the role alone would leave Legion at stock behaviour.
// Cost is the second key, and it has to be well clear of the T2 heavies: corsumo
// is 2,200, armvang 3,300 and legpede 5,500, all T2, against legeheatraymech
// 23,500 and legeshotgunmech 7,000.
const float SUPER_COST = 7000.f;

int gSuperHeld = 0;

// The exception, and the reason this file has a second predicate: the units
// that detonate on death -- corjugg (Behemoth), corkorg (Juggernaut), armbanth
// (Titan). Their value is delivered by ARRIVING at something of the enemy's,
// so parking one on our own defence line is the one place it can never pay for
// itself.
//
// ROLE SUPER COUNTS, NOT ONLY HEAVY. All three carry role super in
// behaviour.json, so a heavy-only test named them and matched none of them:
// they fell through to the guard below and stood on our own line all game.
// C++ CCircuitDef::IsCharger is the same test, and keys CAttackTask's charge
// (ignore the engage margin, path straight at the target instead of round the
// map edge). Keeping the two identical is what makes "charger" one behaviour
// rather than two that disagree.
bool IsChargerDef(const CCircuitDef@ cdef)
{
	return (cdef !is null)
		&& cdef.IsRoleAny(Unit::Role::HEAVY.mask | Unit::Role::SUPER.mask)
		&& cdef.IsAttrAny(Unit::Attr::MELEE.mask);
}

bool WantsSuperGuard(const CCircuitDef@ cdef)
{
	if ((cdef is null) || !cdef.IsMobile() || cdef.IsAbleToFly())
		return false;
	if (IsChargerDef(cdef))
		return false;
	if (ai.GetTunable("apex_super_guard", TUNE_SUPER_GUARD) <= 0.f)
		return false;   // control arm: stock routing, one solo attack task each
	if (ai.GetBindedRole(cdef.GetMainRole()) == RT::SUPER)
		return true;
	return cdef.costM >= ai.GetTunable("apex_super_cost", TUNE_SUPER_COST);
}

// The hold is not absolute. When the whole team commits -- a declared push or
// the killing blow -- the heaviest units we own are exactly what should be in
// front of it, so they take stock routing instead.
//
// This is decided when the unit is TASKED. A super already holding stays
// holding: nothing in the ~405 bindings can move a unit out of a task it has
// been assigned to, so a release has to be read at assignment time or come from
// C++.
// Our SUPER-role mobile mass, memoized: the release test below runs from
// unit-add hooks and a def sweep per call would be a per-frame ring walk.
float gSuperMass = 0.f;
int gNextSuperMass = 0;

float SuperMassOwned()
{
	if (ai.frame < gNextSuperMass)
		return gSuperMass;
	gNextSuperMass = ai.frame + 5 * SECOND;
	float m = 0.f;
	for (Id defId = 1, n = ai.GetDefCount(); defId <= n; ++defId) {
		CCircuitDef@ d = ai.GetCircuitDef(defId);
		if ((d is null) || (d.count == 0) || !d.IsMobile())
			continue;
		if (ai.GetBindedRole(d.GetMainRole()) != RT::SUPER)
			continue;
		m += d.costM * float(d.count);
	}
	gSuperMass = m;
	return m;
}

bool SuperReleased()
{
	if (ai.frame < int(ai.ReadTeamValue(Factory::ElectorTeamId(), TV_PUSH, 0.f)))
		return true;
	// TWO TITANS BY A HILL ARE THE ARMY. Holding supers back is right while
	// they are the spearhead of something bigger; once the held supers are
	// this share of our whole army value, the wait is the army waiting for
	// itself (apexearth 2026-08-21, watching two idle titans: "so sad").
	const float supers = SuperMassOwned();
	return (supers > 1.f)
		&& (supers > OurArmyNow() * ai.GetTunable("apex_super_self_frac", TUNE_SUPER_SELF_FRAC));
}

// The hold tasks, so the release can END them: a MELEE-promote task never
// converts on its own, so a super already holding when the release flips
// would stand by its hill forever regardless (the two watched titans).
array<IUnitTask@> gSuperHolds;

IUnitTask@ SuperGuardTask(CCircuitUnit@ unit)
{
	++gSuperHeld;
	AiLog(Factory::T() + "apex: " + unit.circuitDef.GetName()
		+ " holds the defence line (#" + gSuperHeld + ")");
	IUnitTask@ hold = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
			Task::FightType::RALLY, SUPER_HOLD_POWER));
	if (hold !is null)
		gSuperHolds.insertLast(hold);
	return hold;
}

// Called from the military update: when the release flips, the standing
// holds are aborted so their supers re-elect into the army.
void ReleaseHeldSupers()
{
	if (gSuperHolds.length() == 0)
		return;
	for (uint i = 0; i < gSuperHolds.length(); ) {
		if ((gSuperHolds[i] is null) || gSuperHolds[i].IsDead()) {
			gSuperHolds.removeAt(i);
			continue;
		}
		++i;
	}
	if ((gSuperHolds.length() == 0) || !SuperReleased())
		return;
	AiLog(Factory::T() + "apex: releasing " + gSuperHolds.length()
		+ " held super task(s) -- the wait is over");
	for (uint i = 0; i < gSuperHolds.length(); ++i)
		gSuperHolds[i].Abort();
	gSuperHolds.resize(0);
}

}  // namespace Military
