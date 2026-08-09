namespace Builder {

// A mex upgrade is only ours to make if the mex underneath it is OURS.
//
// CEconomyManager::UpdateEconomyTasks picks the spot to upgrade with a
// predicate that reads the extraction rate of every unit returned by
// GetFriendlyUnitIdsIn(), resolving each id through GetFriendlyUnit() -- the
// ALLY-wide lookup, with the own-team GetTeamUnit() call commented out beside
// it. So an ally's extractor counts as "a mex on this spot yielding less than
// what I can build", and a MEXUP task is enqueued at HIGH priority on ground
// we do not own.
//
// It can never complete. CBMexUpTask::Execute cannot place the building -- the
// ally's extractor occupies the spot -- and its fallback, reclaim the old mex
// and build on the second pass, resolves the occupant through GetTeamUnit(),
// which returns null for another team's unit. So oldMex stays null, the task
// aborts, the spot is released, and the next AiMakeTask picks it again. The
// constructor walks to the ally's base, turns round, and walks back, for as
// long as the condition holds.
//
// Which mexes are ours needs no def list: CEconomyManager's own
// mexFinishedHandler fires UnitAdded(UseAs::MEX) for every extractor we
// finish, and mexDestroyedHandler the reverse, so the set below covers all
// three factions, the moho tier and the underwater pair by construction.
// Economy::AiUnitAdded feeds it.

const float OWN_MEX_R = 96.f;   // the task builds on the spot the mex stands on

array<int>      gOwnMexId;
array<AIFloat3> gOwnMexPos;
int gNextAllyMexLog = 0;

void NoteOwnMex(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int id = int(unit.id);
	for (uint i = 0; i < gOwnMexId.length(); ++i) {
		if (gOwnMexId[i] == id)
			return;
	}
	gOwnMexId.insertLast(id);
	gOwnMexPos.insertLast(unit.GetPos(ai.frame));
}

void DropOwnMex(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int id = int(unit.id);
	for (uint i = 0; i < gOwnMexId.length(); ++i) {
		if (gOwnMexId[i] == id) {
			gOwnMexId.removeAt(i);
			gOwnMexPos.removeAt(i);
			return;
		}
	}
}

bool OnOurMex(const AIFloat3& in p)
{
	const float r2 = OWN_MEX_R * OWN_MEX_R;
	for (uint i = 0; i < gOwnMexPos.length(); ++i) {
		const float dx = p.x - gOwnMexPos[i].x;
		const float dz = p.z - gOwnMexPos[i].z;
		if (dx * dx + dz * dz <= r2)
			return true;
	}
	return false;
}

// Screens DefaultMakeTask's offer, ahead of ExpansionAlwaysWins -- an upgrade
// on an ally's spot reads as expansion and would otherwise be taken outright.
IUnitTask@ VetoAllyMexUp(CCircuitUnit@ unit, IUnitTask@ task)
{
	if ((task is null) || (task.GetType() != Task::Type::BUILDER)
			|| (task.GetBuildType() != Task::BuildType::MEXUP))
		return task;
	if (OnOurMex(task.GetBuildPos()))
		return task;
	if (ai.frame >= gNextAllyMexLog) {
		gNextAllyMexLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: mexup refused, not our mex -- "
			+ unit.circuitDef.GetName() + " ourMexes=" + gOwnMexId.length());
	}
	return null;
}

}  // namespace Builder
