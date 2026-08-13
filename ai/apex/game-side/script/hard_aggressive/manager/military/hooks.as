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
		// IN SPAM PHASE THEY DO NOT FORM SQUADS. apexearth: "they shouldn't form
		// squads, they spread out and waste enemy firepower... they run in to spot
		// the enemy with little regard for their safety."
		//
		// CScoutTask is the only fighter task in CircuitAI that cannot become a
		// group: it derives from IFighterTask and not ISquadTask, so it has no
		// CheckMergeTask and no other task can absorb it, and its CanAssignTo is
		// `units.empty() && IsRoleScout()` -- one unit, forever. The role half of
		// that gate is bypassed here because ITaskModule::AssignTask calls
		// AssignTo directly on whatever MakeTask returns; CanAssignTo only guards
		// the merge and re-assignment paths, which is exactly the part we want
		// closed. So a raider-role Grunt can hold a scout task, and nothing can
		// join it.
		//
		// Where each one goes is CMilitaryManager::GetScoutPosition, which claims
		// an unscouted metal cluster per task and skips any cluster another scout
		// task already holds -- so N of them spread over N clusters instead of
		// walking the same lane. Unlooked-at ground reads as zero threat, so the
		// ground they are sent to is by construction the ground we know least
		// about, which is where the enemy estimate is wrong.
		//
		// It also drops the quota.scout ceiling for them: that gate lives in
		// DefaultMakeTask, and this does not go through it. Two eyes was a cap,
		// and how many we field is a production question, not a routing one.
		if (SpamPhase())
			return aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::SCOUT));
		// BEFORE SPAM PHASE, RAIDERS GROUP BEFORE THEY GO. This used to send every
		// raider straight to its own RAID task the moment it was built, skipping
		// the pool stock parks them in -- Defend(RAID, quota.raid.min) -- which
		// holds them until they add up to that much power and then promotes them
		// TOGETHER. The shortcut got each raider moving sooner and guaranteed it
		// moved alone, so we trickled ones and twos into a map being raided by
		// packs. quota.raid is configured for the pack -- we were routing around
		// it. UpdateRaidCaution raises the promotion floor further while we are
		// still on T1, which is the same instruction stated in power.
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
		// WHILE OUR BASE IS BEING HIT, THE POOL DOES NOT LEAVE.
		//
		// apexearth, for the third time: "when an enemy attacks us we should
		// converge on them and kill them but instead we just stand around doing
		// nothing to help our base... heck our armies actively run away from our
		// base when our base is under attack", and "early on we could wipe out
		// enemy armies but instead we let them beat us up."
		//
		// The third argument is a PROMOTION TRIGGER: at that much power the DEFEND
		// task converts to ATTACK and marches on the enemy. So the moment we have
		// enough army to defend ourselves is the exact moment it leaves -- which
		// is what he is watching. Nothing in it ever asked whether home was under
		// attack.
		//
		// Promoting to MELEE instead is what holds it: this file's own comment
		// records that nothing in CircuitAI ever enqueues a MELEE task, and
		// UpdateDefenceTasks only rewrites maxPower for tasks that promote to
		// ATTACK -- so a MELEE-promoting task keeps the power we gave it and never
		// converts. The pool stays a defence, and CDefendTask sends it at whatever
		// is threatening us.
		//
		// It reverts by itself: this only decides the task a unit is joining now,
		// so once the attack is over, new units pool into ordinary attack-promoting
		// tasks again.
		// AN ALLY BEING OVERRUN COUNTS AS OUR BASE BEING HIT. apexearth: "it's not
		// just about our own base. It's about seeing that an ally's base is in
		// their attack and going to assist them."
		//
		// AllyAidPos is the heaviest fight on our side within reach, our own
		// included, from the loss-weighted hotspot each player now publishes. It
		// is also a far better "we are under attack" trigger than
		// BaseUnderAttack(), which fired twice in six games because it asks about
		// enemy influence at our own start position.
		// MEASURED AND REVERTED, 2026-08-11. Gating this on AllyAidPos -- any ally
		// losing 300 metal within 6,000 elmos -- is true almost continuously in a
		// 4v4, so the pool never promoted to ATTACK at all and the army was ground
		// down in place: at minute 20, army 4,676 against stock's 15,309 (from
		// 9,467/13,244) and metal lost 42,166 against 16,332.
		//
		// The publishing side is kept and is sound; what is wrong is the RESPONSE.
		// "An ally is being hurt somewhere" must change where the army goes, not
		// forbid it from ever attacking -- a permanent defensive stance is how you
		// lose slowly. Sending a FRACTION of the army needs a per-task position,
		// which this layer does not have; see CHANGES.md before trying again.
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
			if (OnMap(gFencePos[i])) {
				gFenceLostPos.insertLast(gFencePos[i]);
				gFenceLostAt.insertLast(ai.frame);
			}
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
