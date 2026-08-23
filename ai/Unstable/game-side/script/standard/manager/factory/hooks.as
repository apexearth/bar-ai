namespace Factory {

// The pending recruit queue, mirrored in script. CFactoryManager's own list
// (factoryTasks) is not bound to script, so these two hooks are the only view
// of it -- the facqueue's recruit abort and sweep read this register.
array<IUnitTask@> gQTask;

void AiTaskAdded(IUnitTask@ task)
{
	if ((task is null) || (task.GetType() != Task::Type::FACTORY))
		return;
	if (task.GetBuildType() != Task::BuildType::RECRUIT)
		return;
	gQTask.insertLast(task);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	for (uint i = 0; i < gQTask.length(); ++i) {
		if (gQTask[i] is task) {
			gQTask.removeAt(i);
			return;
		}
	}
}

// The first T1 lab on the field: the base plan's anchor (baseplan/axis.as).
// NOCOUNT hazard: the handle is not nulled when the engine frees the unit, so
// removal below must clear it.
CCircuitUnit@ gT1FacUnit = null;

// How many factories THIS instance currently has standing, of any kind or
// tier -- and their handles.
int gFactoryCount = 0;
array<CCircuitUnit@> gFacUnits;

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
	if (usage == Unit::UseAs::FACTORY) {
		++gFactoryCount;
		gFacUnits.insertLast(unit);
	}
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0)
		gHaveT2 = true;
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T3) != 0)
		gHaveT3 = true;
	if ((usage == Unit::UseAs::FACTORY)
		&& ((Factory::userData[unit.circuitDef.id].attr
			& (Factory::Attr::T2 | Factory::Attr::T3)) == 0))
	{
		@gT1FacUnit = unit;
		AiLog(T() + "apex: T1 lab on field: " + unit.circuitDef.GetName());
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage == Unit::UseAs::FACTORY) {
		--gFactoryCount;
		// NOCOUNT: remove or later reads touch freed memory.
		for (uint i = 0; i < gFacUnits.length(); ++i) {
			if (gFacUnits[i] is unit) {
				gFacUnits.removeAt(i);
				break;
			}
		}
	}
	if (gT1FacUnit is unit)
		@gT1FacUnit = null;
	// A dead factory must not keep its line: ids are reused.
	if (usage == Unit::UseAs::FACTORY)
		Brain::ReleaseFactory(unit.id);
}

bool HaveAnyFactory()
{
	return gFactoryCount > 0;
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

// Log prefix: game time AND team id. Every AI instance on the map writes to
// one infolog behind the same shared prefix; tools/trace_flow.py parses this.
string T()
{
	return "[" + formatFloat(float(ai.frame) / float(MINUTE), "", 0, 1) + "m t"
		+ ai.teamId + "] ";
}

}  // namespace Factory
