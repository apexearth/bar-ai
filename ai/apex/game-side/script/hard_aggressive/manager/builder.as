#include "../../unit.as"


namespace Builder {

// The lead techs first, then hands advanced constructors to teammates so they
// can build T2 without each paying for their own advanced factory.
const float ADV_CON_COST = 300.f;   // T1 cons are ~110, T2 ~600
int gAdvConsMade = 0;
int gAdvConsGifted = 0;

array<int> gGifted;   // teams that already received their advanced con

// Observed live: the lead built its first T2 constructor and handed it straight
// over, leaving itself none. Two bugs behind it. This was called for EVERY unit
// added with no role filter, so any unit costing 300+ metal bumped the counter
// -- and the unit actually given away was whatever triggered the call, which
// need not be a constructor at all. And the guard counted cons ever MADE rather
// than cons currently HELD, so once the count was used up by combat units the
// next real constructor went out the door.
//
// Rule: never give one away while we hold only one ourselves.
void ShareAdvCon(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (ai.teamId != Factory::RushLeadTeamId())
		return;
	// Actual constructors only -- not commanders, not expensive tanks.
	if (usage != Unit::UseAs::BUILDER)
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	if (cdef.IsRoleAny(Unit::Role::COMM.mask))
		return;
	if (cdef.costM < ADV_CON_COST)
		return;

	++gAdvConsMade;
	// Keep at least one for ourselves at all times: the lead is the player whose
	// job it is to upgrade mexes, and it cannot do that with no constructor.
	if ((gAdvConsMade - gAdvConsGifted) <= 1)
		return;

	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;
	// One each and then stop. Every teammate needs a T2 con to start upgrading
	// its own mexes; past that we are just giving our build power away.
	for (uint i = 0; i < mates.length(); ++i) {
		int cand = int(mates[i]);
		if ((cand == ai.teamId) || (gGifted.find(cand) >= 0))
			continue;
		gGifted.insertLast(cand);
		++gAdvConsGifted;
		array<CCircuitUnit@> gift;
		gift.insertLast(unit);
		ai.GiveUnits(gift, cand);
		AiLog("apex: gave adv con to team " + cand + " (held "
			+ (gAdvConsMade - gAdvConsGifted + 1) + ", keeping "
			+ (gAdvConsMade - gAdvConsGifted) + ")");
		return;
	}
}


CCircuitUnit@ energizer1 = null;
CCircuitUnit@ energizer2 = null;

// AIFloat3 lastPos;
// int gPauseCnt = 0;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
// 	AiDelPoint(lastPos);
// 	lastPos = unit.GetPos(ai.frame);
// 	AiAddPoint(lastPos, "task");

// 	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
// 	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)) {
// 		switch (task.GetBuildType()) {
// 		case Task::BuildType::MEX:
// 			AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 			break;
// 		case Task::BuildType::DEFENCE:
// 			AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 			break;
// 		default:
// 			break;
// 		}
// 	}
// 	return task;
	return aiBuilderMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
// 	if (task.GetType() != Task::Type::BUILDER)
// 		return;
// 	switch (task.GetBuildType()) {
// 	case Task::BuildType::ENERGY: {
// 		if (gPauseCnt == 0) {
// 			string name = task.GetBuildDef().GetName();
// 			if ((name == "armfus") || (name == "armafus") || (name == "corfus") || (name == "corafus")) {
// 				AiPause(true, "energy");
// 				++gPauseCnt;
// 			}
// 			AiAddPoint(task.GetBuildPos(), name);
// 		}
// 	} break;
// 	case Task::BuildType::FACTORY:
// 	case Task::BuildType::NANO:
// 	case Task::BuildType::STORE:
// 	case Task::BuildType::PYLON:
// 	case Task::BuildType::GEO:
// 	case Task::BuildType::GEOUP:
// 	case Task::BuildType::DEFENCE:
// 	case Task::BuildType::BUNKER:
// 	case Task::BuildType::BIG_GUN:
// 	case Task::BuildType::RADAR:
// 	case Task::BuildType::SONAR:
// 	case Task::BuildType::CONVERT:
// 	case Task::BuildType::MEX:
// 	case Task::BuildType::MEXUP:
// 		AiAddPoint(task.GetBuildPos(), task.GetBuildDef().GetName());
// 		break;
// 	case Task::BuildType::REPAIR:
// 		AiAddPoint(task.GetBuildPos(), "rep");
// 		break;
// 	case Task::BuildType::RECLAIM:
// 		AiAddPoint(task.GetBuildPos(), "rec");
// 		break;
// 	case Task::BuildType::RESURRECT:
// 		AiAddPoint(task.GetBuildPos(), "res");
// 		break;
// 	case Task::BuildType::TERRAFORM:
// 		AiAddPoint(task.GetBuildPos(), "ter");
// 		break;
// 	default:
// 		break;
// 	}
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
// 	if (task.GetType() != Task::Type::BUILDER)
// 		return;
// 	switch (task.GetBuildType()) {
// 	case Task::BuildType::FACTORY:
// 	case Task::BuildType::NANO:
// 	case Task::BuildType::STORE:
// 	case Task::BuildType::PYLON:
// 	case Task::BuildType::ENERGY:
// 	case Task::BuildType::GEO:
// 	case Task::BuildType::GEOUP:
// 	case Task::BuildType::DEFENCE:
// 	case Task::BuildType::BUNKER:
// 	case Task::BuildType::BIG_GUN:
// 	case Task::BuildType::RADAR:
// 	case Task::BuildType::SONAR:
// 	case Task::BuildType::CONVERT:
// 	case Task::BuildType::MEX:
// 	case Task::BuildType::MEXUP:
// 	case Task::BuildType::REPAIR:
// 	case Task::BuildType::RECLAIM:
// 	case Task::BuildType::RESURRECT:
// 	case Task::BuildType::TERRAFORM:
// 		AiDelPoint(task.GetBuildPos());
// 		break;
// 	default:
// 		break;
// 	}
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	ShareAdvCon(unit, usage);
	const CCircuitDef@ cdef = unit.circuitDef;
	if (usage != Unit::UseAs::BUILDER || cdef.IsRoleAny(Unit::Role::COMM.mask))
		return;

	// constructor with BASE attribute is assigned to tasks near base
	if (cdef.costM < 200.f) {
		if (energizer1 is null
			&& (uint(cdef.count) > aiMilitaryMgr.GetGuardTaskNum() || cdef.IsAbleToFly()))
		{
			@energizer1 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	} else {
		if (energizer2 is null) {
			@energizer2 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (energizer1 is unit)
		@energizer1 = null;
	else if (energizer2 is unit)
		@energizer2 = null;
}

void AiLoad(IStream& istream)
{
	Id e1id = -1, e2id = -1;
	istream >> e1id >> e2id;
	@energizer1 = ai.GetTeamUnit(e1id);
	@energizer2 = ai.GetTeamUnit(e2id);
	if (energizer1 !is null)
		energizer1.AddAttribute(Unit::Attr::BASE.type);
	if (energizer2 !is null)
		energizer2.AddAttribute(Unit::Attr::BASE.type);
}

void AiSave(OStream& ostream)
{
	ostream << Id(energizer1 !is null ? energizer1.id : -1)
			<< Id(energizer2 !is null ? energizer2.id : -1);
}

}  // namespace Builder
