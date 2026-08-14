namespace Factory {

// The eco lead deliberately runs an idle production line; these are the two
// exceptions to that.

IUnitTask@ AirConMinimum(CCircuitUnit@ unit)
{
	// The eco lead's factory: build power while short, then nothing -- an idle
	// line means income goes to builders instead of army, which is the role's
	// point. Placed after the advanced-con branch since eco lead is still tech
	// lead. T1 air ratios give constructors only ~5%, and once any T2 factory
	// exists a T1 factory's isActive goes false (isAvailableDef needs
	// isActive || IsAttrRare, and fighters aren't rare) -- so without this,
	// the advanced air plant, and all fighters, may never unlock.
	if (IsAirFactory(unit.circuitDef) && (AirConCount() < AIR_CON_MIN)
		&& (ai.frame >= gNextEcoAirCon))
	{
		CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (acon !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
					acon, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextEcoAirCon = ai.frame + ECO_AIR_SPACING;
				return rec;
			}
		}
	}
	return null;
}

IUnitTask@ EcoLeadLine(CCircuitUnit@ unit, bool &out taken)
{
	taken = false;
	// A gantry has no BUILDER-role unit, so the constructor branch below cannot
	// absorb it and it would otherwise fall through to null forever. Owning one
	// overrides the eco-lead idle-line rule.
	CCircuitDef@ gantDef = T3Gantry();
	const bool isOwnGantry = (gantDef !is null)
			&& (unit.circuitDef.id == gantDef.id);

	if (gEcoActive && !isOwnGantry) {
		// The aircraft plant makes constructors and nothing else. Every other
		// branch above has already had its say, so reaching here with an air
		// factory means this player has one purely as build power.
		if (IsAirFactory(unit.circuitDef)) {
			if ((AirConCount() < ECO_AIR_CON_CAP) && (ai.frame >= gNextEcoAirCon)) {
				CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
				if (acon !is null) {
					IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
							Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
							acon, unit.GetPos(ai.frame), 0.f));
					if (rec !is null) {
						gNextEcoAirCon = ai.frame + ECO_AIR_SPACING;
						return rec;
					}
				}
			}
			taken = true;
			return null;
		}
		// GetWorkerCount() counts every worker we own, including nano turrets and
		// rez bots (CBuilderManager puts both in `workers`), so both must be
		// subtracted or turrets alone can fill the mobile-con budget.
		if ((int(aiBuilderMgr.GetWorkerCount()) - Builder::NanoCount() - Builder::RezCount()
				< int(ECO_CON_CAP))
			&& (ai.frame >= gNextEcoCon))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextEcoCon = ai.frame + ECO_CON_SPACING;
					return rec;
				}
			}
		}
		if (ai.frame >= gNextEcoLog) {
			gNextEcoLog = ai.frame + 60 * SECOND;
			AiLog(T() + "apex: eco lead idle line, cons="
				+ aiBuilderMgr.GetWorkerCount()
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
		}
		taken = true;
		return null;
	}
	return null;
}

}  // namespace Factory
