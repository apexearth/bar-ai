namespace Factory {

// The eco lead deliberately runs an idle production line; these are the two
// exceptions to that.

IUnitTask@ AirConMinimum(CCircuitUnit@ unit)
{
	// The eco lead's factory. Build power while it is short of it, then nothing
	// at all -- an idle line is the point, not a failure. Every unit this factory
	// does not make is income the builders spend on mexes, energy and the T2/T3
	// economy instead, which is the entire reason the role exists.
	//
	// This sits AFTER the advanced-constructor branch above deliberately: handing
	// advanced cons to the rest of the team is the tech lead's job and the eco
	// lead is still the tech lead. It only replaces what would otherwise be army.
	// The advanced air plant can only be built by an AIR constructor, and the T1
	// air plant's own ratios give constructors about 5% -- so a player can hold
	// the air slot all game and never produce one. Without the advanced plant
	// there are no fighters at all, because FactoryManager's isAvailableDef
	// requires (isActive || IsAttrRare()) and isActive goes false for a T1
	// factory the moment its owner has any T2 factory. Fighters are not rare.
	// One constructor unlocks the plant; after that the ratios decide.
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
	// A gantry is the declared win condition, and the eco lead builds no army by
	// design -- so a gantry it came by, built or resurrected, produced nothing at
	// all. It has no BUILDER-role unit either, so the constructor branch below
	// cannot absorb it and it falls through to `return null` every call.
	// apexearth: "our eco guy ressurrected a gantry and then never made any unit
	// from it". Owning one overrides the rule.
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
		// GetWorkerCount() counts every worker we own, and a nano turret IS one --
		// observed live, the eco lead logged cons=25 against a cap of 16 while
		// standing on eleven turrets. Left alone, the rectangle eats the mobile
		// constructor budget and the player ends up with turrets and nobody to
		// walk to the next mex. Count the turrets back out -- and rez bots too,
		// which CBuilderManager puts in `workers` without any build power.
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
