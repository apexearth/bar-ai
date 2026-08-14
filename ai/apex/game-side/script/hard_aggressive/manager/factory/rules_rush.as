namespace Factory {

// The tech rush and the two things that replace ordinary army production
// while it runs.

IUnitTask@ RushBuildPower(CCircuitUnit@ unit, bool &out taken)
{
	taken = false;
	// quota.attack caps units sent, not units built, so it can't stop the factory
	// converting slung metal into T1 army; idle the line outright during the
	// rush window instead.
	//
	// Not simply idled: EconomyManager gates the factory switch on energy
	// (engyFactor < energyPower) before ever consulting IsSwitchAllowed, and
	// that check is not bypassed by isSwitchTime -- so banked metal alone would
	// go to waste while energy is the real blocker.
	//
	// Turned into build power instead: more constructors raise energy (solars,
	// converters) faster, which is what the gate above is waiting on, and are
	// needed afterward to upgrade mexes and hand to allies.
	//
	// Capped -- an unbounded version recruited a constructor on every factory
	// decision for the whole rush window, far more build power than one player
	// can use. A handful is enough to finish a plant quickly; past that each
	// one is waste. GetWorkerCount() counts what we actually hold, not what we
	// have ever ordered.
	if (MayPursueT2() && !gHaveT2 && RushReady() && !IsSmallTeam()
		&& RushWindowOpen())
	{
		// Cap AND spacing: the cap alone cannot hold, because GetWorkerCount()
		// only sees finished builders (see RUSH_CON_SPACING above).
		if ((int(aiBuilderMgr.GetWorkerCount()) - Builder::RezCount() < int(RUSH_CON_CAP))
			&& (ai.frame >= gNextConOrder))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextConOrder = ai.frame + RUSH_CON_SPACING;
					return rec;
				}
			}
		}
		taken = true;
		return null;   // never fall through to army production during the rush
	}
	return null;
}

void ConBranchLog(CCircuitUnit@ unit)
{
	// Diagnostic: logs every input the advanced-con branches below gate on, so a
	// blocked branch can be attributed to a specific condition instead of guessed.
	if (ai.frame >= gNextConLog) {
		gNextConLog = ai.frame + 30 * SECOND;
		CCircuitDef@ probe = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		AiLog(T() + "conbranch fac=" + unit.circuitDef.GetName()
			+ " haveT2=" + (gHaveT2 ? "1" : "0")
			+ " lead=" + (IsTechLead() ? "1" : "0")
			+ " owes=" + (Builder::OwesAdvCons() ? "1" : "0")
			+ " haveCon=" + (Builder::gHaveAdvCon ? "1" : "0")
			+ " roleDef=" + ((probe is null) ? "NULL" : probe.GetName()));
	}
}

IUnitTask@ ShareAdvancedCon(CCircuitUnit@ unit)
{
	// OwesAdvCons() is false solo (no allies to gift), so gating on !gHaveAdvCon
	// alone capped this at exactly one constructor forever. NeedsAdvCon() scales
	// the count with income and a full bank instead.
	if (gHaveT2 && ((IsDesignatedLead() && Builder::OwesAdvCons())
			|| Builder::NeedsAdvCon())) {
		// BUILDER, not BUILDER2: builderT2 is a SUBROLE of BUILDER
		// (AiAddRole("builderT2", BUILDER.type)) and FactoryManager's role map is
		// indexed by BASE roles only, so GetRoleDef(BUILDER2) returns NULL. For an
		// advanced plant the base builder IS the advanced constructor anyway
		// (coravp's only builder is coracv).
		CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (con !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER,
					IsSmallTeam() ? Task::Priority::NORMAL : Task::Priority::NOW,
					con, unit.GetPos(ai.frame), 0.f));
			if (rec !is null)
				return rec;
		}
	}
	return null;
}

// Long range and fodder while we are holding. See the TURTLE_MIX_SPACING note in
// armypush.as for why this is a substitution rather than a new spend.
IUnitTask@ DefensiveComposition(CCircuitUnit@ unit)
{
	if (gEcoActive || !Military::gTurtle)
		return null;
	// Air plants are Air::'s to schedule, and an aircraft is not what "hit them
	// from inside our base" means.
	if (IsAirFactory(unit.circuitDef))
		return null;

	CCircuitDef@ want = null;
	if ((gTurtleMixCount % TURTLE_ARTY_EVERY) == 0)
		@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ARTY.type);
	// Fall back BOTH ways: a bot lab that has no artillery unit still contributes
	// fodder, and a plant whose cheapest unit is not cheap enough to be fodder
	// still contributes artillery. Only a line that can do neither passes.
	if (want is null)
		@want = Fodder(unit.circuitDef);
	if (want is null)
		@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ARTY.type);
	if ((want is null) || !want.IsAvailable(ai.frame))
		return null;

	IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
			want, unit.GetPos(ai.frame), 0.f));
	if (rec is null)
		return null;
	++gTurtleMixCount;
	gNextTurtleMix = ai.frame + TURTLE_MIX_SPACING;
	if (ai.frame >= gNextTurtleMixLog) {
		gNextTurtleMixLog = ai.frame + 30 * SECOND;
		AiLog(T() + "apex: holding, buying " + want.GetName()
			+ " cost=" + formatFloat(want.costM, "", 0, 0)
			+ " picks=" + gTurtleMixCount);
	}
	return rec;
}

IUnitTask@ LosingArmyPush(CCircuitUnit@ unit)
{
	// Behind on the field: pour income into the cheap mainstay. GetRoleDef(ASSAULT)
	// returns whatever THIS factory can make (Thug from a bot lab, Brute from a
	// vehicle plant), so it never asks for a unit the factory cannot build.
	//
	// Spaced for the same reason as RUSH_CON_SPACING: Enqueue doesn't dedup, and
	// the cap it would respect only counts finished units. This branch bypasses
	// the factory tier weights entirely (asks GetRoleDef(ASSAULT) directly), so
	// while behind it also produces T2/T3 answers -- cheap T1 units alone cannot
	// trade against a teched enemy.
	const bool isT1Fac =
		((Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) == 0);
	const bool isT2Fac =
		((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0);
	// !gEcoActive: the eco lead fields no army by design, so LosingGround() is
	// permanently true for it and this branch must not claim its whole income.
	// The economic gates (HaveT2Mex, ARMY_PUSH_MIN_INCOME) apply to the ADVANCED
	// plant only -- a T1-lab fodder push must stay ungated by them, since a
	// collapsing player loses mexes and income first and would otherwise be
	// denied the one thing it can still afford.
	const bool advPushOk = isT2Fac && HaveT2Mex()
			&& (aiEconomyMgr.metal.income >= ARMY_PUSH_MIN_INCOME);
	if (!gEcoActive && (isT1Fac ? !gHaveT2 : advPushOk) && Military::LosingGround()
		&& (ai.frame >= gNextArmyPush))
	{
		// "Spam" means fodder (ticks, grunts, wheelies -- cheap, fast, for vision
		// and distraction), not the ASSAULT mainstay tank. Split by what the
		// factory IS: a T1 lab makes fodder, the advanced plant makes the army
		// that can actually trade.
		++gArmyPushCount;
		CCircuitDef@ want = null;
		if (isT1Fac) {
			@want = Fodder(unit.circuitDef);
		} else if (Military::gTurtle) {
			// DefensiveComposition above already claims most slots while holding,
			// but it is spaced and this is not -- without the same substitution
			// here the gap between its picks is where the Bulls came from.
			@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ARTY.type);
			if (want is null)
				@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ASSAULT.type);
		} else {
			@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ASSAULT.type);
		}
		if (want !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					want, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextArmyPush = ai.frame + ARMY_PUSH_SPACING;
				if (ai.frame >= gNextArmyLog) {
					gNextArmyLog = ai.frame + 30 * SECOND;
					AiLog(T() + "apex: behind on the field, massing " + want.GetName()
						+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
						+ " enemyArmy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
				}
				return rec;
			}
		}
	}
	return null;
}

}  // namespace Factory
