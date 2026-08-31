namespace Military {

// -- the fight-type census ---------------------------------------------------
//
// WHAT THE ARMY IS ACTUALLY DOING, counted off the LIVE tasks rather than off
// the election.
//
// NoteFightElection stamps a unit with the fight type it was elected onto, and
// that cannot separate the massing pool from the raid pool: stock CircuitAI
// enqueues raiders as Defend(promote=RAID) -- fight type DEFEND -- and the
// promotion into a real CRaidTask happens inside CDefendTask::Update via
// AssignTask, in C++, never passing back through AiMakeTask. "f4 (RAID) = 0
// across 11 matches" was read as proof we never raid; it was proof only that no
// unit is ELECTED straight onto a raid task, which is true of stock too.
//
// gSquads mirrors every live fighter task (AiTaskAdded/AiTaskRemoved) and
// GetFightType() is bound, so the live pools answer it directly. Per type:
// tasks/units/metal.
int gNextFightCensus = 0;

string FightTypeName(uint ft)
{
	if (ft == uint(Task::FightType::RALLY))   return "rally";
	if (ft == uint(Task::FightType::GUARD))   return "guard";
	if (ft == uint(Task::FightType::DEFEND))  return "defend";
	if (ft == uint(Task::FightType::SCOUT))   return "scout";
	if (ft == uint(Task::FightType::RAID))    return "raid";
	if (ft == uint(Task::FightType::ATTACK))  return "attack";
	if (ft == uint(Task::FightType::BOMB))    return "bomb";
	if (ft == uint(Task::FightType::MELEE))   return "melee";
	if (ft == uint(Task::FightType::ARTY))    return "arty";
	if (ft == uint(Task::FightType::AA))      return "aa";
	if (ft == uint(Task::FightType::AH))      return "ah";
	if (ft == uint(Task::FightType::SUPPORT)) return "support";
	if (ft == uint(Task::FightType::SUPER))   return "super";
	return "?";
}

void FightCensus()
{
	if (ai.frame < gNextFightCensus)
		return;
	gNextFightCensus = ai.frame + 60 * SECOND;
	const uint kinds = uint(Task::FightType::_SIZE_);
	array<int>   tasks(kinds, 0);
	array<int>   units(kinds, 0);
	array<float> metal(kinds, 0.f);
	int empty = 0;
	int odd = 0;
	for (uint i = 0; i < gSquads.length(); ++i) {
		if (gSquads[i] is null)
			continue;
		const int ft = gSquads[i].GetFightType();
		if ((ft < 0) || (uint(ft) >= kinds)) {
			++odd;
			continue;
		}
		++tasks[uint(ft)];
		array<CCircuitUnit@>@ on = gSquads[i].GetUnits();
		if ((on is null) || (on.length() == 0)) {
			++empty;
			continue;
		}
		units[uint(ft)] += int(on.length());
		for (uint j = 0; j < on.length(); ++j) {
			if ((on[j] !is null) && (on[j].circuitDef !is null))
				metal[uint(ft)] += on[j].circuitDef.costM;
		}
	}
	string line = "";
	for (uint k = 0; k < kinds; ++k) {
		line += " " + FightTypeName(k) + "=" + tasks[k] + "/" + units[k]
			+ "/" + formatFloat(metal[k], "", 0, 0);
	}
	AiLog(Factory::T() + "apex: fightcensus tasks/units/metal" + line
		+ " | live=" + gSquads.length() + " empty=" + empty + " unknown=" + odd);
}

}  // namespace Military
