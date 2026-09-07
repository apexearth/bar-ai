/*
 * TravelAction.cpp
 *
 *  Created on: Feb 16, 2016
 *      Author: rlcevg
 */

#include "unit/action/TravelAction.h"
#include "unit/CircuitUnit.h"
#include "unit/CircuitDef.h"
#include "task/UnitTask.h"
#include "task/fighter/FighterTask.h"  // FightTypeName for the goal trace
#include "CircuitAI.h"
#include "module/TaskModule.h"  // complete ITaskModule for GetCircuit() in the goal trace
#include "Log.h"                // complete springai::Log for the LOG macro
#include "util/Utils.h"

#include "spring/SpringCallback.h"

#include <algorithm>

namespace circuit {

using namespace springai;

ITravelAction::ITravelAction(CCircuitUnit* owner, Type type, int squareSize, float speed)
		: IUnitAction(owner, type)
		, speed(speed)
		, pathIterator(0)
		, lastSector(-1)
		, lastFrame(-1)
{
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	CCircuitDef* cdef = unit->GetCircuitDef();
	int size = std::max(cdef->GetMoveXSize(), cdef->GetMoveZSize());
	int incMod = std::max(size / 4, 1);
	if (cdef->IsPlane()) {
		incMod *= 8;
	} else if (cdef->IsAbleToFly()) {
		incMod *= 3;
	} else if (cdef->IsTurnLarge()) {
		incMod *= 2;
	}
	increment = incMod * DEFAULT_SLACK / squareSize + 1;
	minSqDist = squareSize * increment;  // / 2;
	minSqDist *= minSqDist;
}

ITravelAction::ITravelAction(CCircuitUnit* owner, Type type, const std::shared_ptr<CPathInfo>& pPath,
		int squareSize, float speed)
		: ITravelAction(owner, type, squareSize, speed)
{
	this->pPath = pPath;
}

ITravelAction::~ITravelAction()
{
}

void ITravelAction::OnEnd()
{
	IAction::OnEnd();
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	unit->GetTask()->OnTravelEnd(unit);  // WARNING: do not clear/delete unit actions
}

void ITravelAction::SetPath(const std::shared_ptr<CPathInfo>& pPath, float speed)
{
	// NOTE: pPath can be null. Caller uses StateWait() after this call in such cases
	pathIterator = 0;
	this->pPath = pPath;
	// apex: A UNIT'S GOAL CHANGING IS THE DECISION; the waypoints it walks are
	// not. Measuring the waypoints counted a curving path as indecision and
	// produced the 'travel -> travel bouncing' figure, which said nothing about
	// whether anyone had changed their mind. This says exactly that.
	if ((pPath != nullptr) && !pPath->posPath.empty()) {
		CCircuitUnit* u = static_cast<CCircuitUnit*>(ownerList);
		ITaskModule* mgr = (u != nullptr) ? u->GetManager() : nullptr;
		CCircuitAI* c = (mgr != nullptr) ? mgr->GetCircuit() : nullptr;
		if ((c != nullptr) && (c->GetTunable("apex_order_trace", 0.f) > 0.f)) {
			const springai::AIFloat3& goal = pPath->posPath.back();
			const springai::AIFloat3& was = u->GetTravelGoal();
			const bool had = utils::is_valid(was);
			const int f = c->GetLastFrame();
			// WHICH KIND of fighter task owns it. Joining the goal change to the
			// order stream named only travel/fightwalk -- the execution layer that
			// carries out the new path -- which is circular. The decider is the task.
			const char* ft = "-";
			if ((u->GetTask() != nullptr)
				&& (u->GetTask()->GetType() == IUnitTask::Type::FIGHTER)) {
				ft = IFighterTask::FightTypeName(int(
						static_cast<IFighterTask*>(u->GetTask())->GetFightType()));
			}
			// start/min: how far the PREVIOUS goal was when it was set, and the
			// closest the unit ever came to it before this order replaced it. A
			// unit hovering between two places closes neither: min stays a large
			// fraction of start, every time.
			c->LOG("apex: goal t=%i u=%i %s f=%i to=%.0f,%.0f moved=%.0f held=%.1f"
					" task=%i ft=%s start=%.0f min=%.0f",
					c->GetTeamId(), (int)u->GetId(),
					(u->GetCircuitDef() != nullptr) ? u->GetCircuitDef()->GetDef()->GetName() : "?",
					f, goal.x, goal.z,
					had ? goal.distance2D(was) : -1.f,
					had ? float(f - u->GetTravelGoalFrame()) / FRAMES_PER_SEC : -1.f,
					(u->GetTask() != nullptr) ? int(u->GetTask()->GetType()) : -1,
					ft, u->GetGoalDistStart(), u->GetGoalDistMin());
		}
		u->SetTravelGoal(pPath->posPath.back(), c != nullptr ? c->GetLastFrame() : 0);
	}
	this->speed = speed;
//	lastSector = -1;
	lastFrame = -1;
	StateActivate();
}

// IS THE UNIT WHERE WE ASKED IT TO BE? -- apexearth: "it is useful to know if
// they are moving as we intend."
//
// The per-goal-change numbers cannot answer this. They are conditioned on the
// goal being REPLACED, so a squad that arrives and stays leaves the sample
// entirely -- the better the commitment works, the worse "arrived%" looks.
// This samples every travelling unit once a second regardless of what happens
// to its orders: occupancy, not interruptions.
static unsigned sAtSamples[int(IFighterTask::FightType::_SIZE_) + 1] = {0};
static unsigned sAtGoal[int(IFighterTask::FightType::_SIZE_) + 1] = {0};
static double sAtDist[int(IFighterTask::FightType::_SIZE_) + 1] = {0};
static int sAtLogAt = 0;

static void NoteAtGoal(CCircuitAI* circuit, CCircuitUnit* unit, float dist)
{
	const int n = int(IFighterTask::FightType::_SIZE_);
	int ft = n;  // everything that is not a fighter: builders, the control group
	IUnitTask* task = unit->GetTask();
	if ((task != nullptr) && (task->GetType() == IUnitTask::Type::FIGHTER)) {
		ft = int(static_cast<IFighterTask*>(task)->GetFightType());
		if ((ft < 0) || (ft >= n)) {
			ft = n;
		}
	}
	++sAtSamples[ft];
	sAtDist[ft] += dist;
	if (dist < 200.f) {  // the arrival tolerance the goal trace already uses
		++sAtGoal[ft];
	}

	const int frame = circuit->GetLastFrame();
	if (frame < sAtLogAt) {
		return;
	}
	sAtLogAt = frame + FRAMES_PER_SEC * 60;
	for (int i = 0; i <= n; ++i) {
		if (sAtSamples[i] == 0) {
			continue;
		}
		circuit->LOG("apex: atgoal ft=%s samples=%u at=%u meandist=%.0f",
				(i < n) ? IFighterTask::FightTypeName(i) : "OTHER",
				sAtSamples[i], sAtGoal[i], sAtDist[i] / sAtSamples[i]);
	}
}

void ITravelAction::FaceStep(int idx)
{
	CCircuitUnit* u = static_cast<CCircuitUnit*>(ownerList);
	if ((u->GetFormLateral() == 0.f) || (pPath == nullptr) || pPath->posPath.empty()) {
		return;
	}
	const int last = int(pPath->posPath.size()) - 1;
	const int a = std::max(0, std::min(idx, last));
	const int b = std::max(0, std::min(idx + 1, last));
	if (a == b) {
		return;
	}
	AIFloat3 dir = pPath->posPath[b] - pPath->posPath[a];
	dir.y = 0.f;
	if (dir.SqLength2D() >= 1.f) {
		u->SetFormDir(dir);
	}
}

int ITravelAction::CalcSpeedStep(CCircuitAI* circuit, float& stepSpeed)
{
	CCircuitUnit* unit = static_cast<CCircuitUnit*>(ownerList);
	const AIFloat3& pos = unit->GetPos(lastFrame);
	// Sampled here because both CMoveAction and CFightAction come through it,
	// once a second per unit -- the cheapest honest place to ask how close the
	// unit has actually got to the destination somebody chose for it.
	if (utils::is_valid(unit->GetTravelGoal())) {
		const float d = pos.distance2D(unit->GetTravelGoal());
		unit->NoteGoalDist(d);
		NoteAtGoal(circuit, unit, d);
	}
	int pathMaxIndex = pPath->posPath.size() - 1;

//	int lastStep = pathIterator;
	float sqDistToStep = pos.SqDistance2D(pPath->posPath[pathIterator]);
	int step = std::min(pathIterator + increment, pathMaxIndex);
	float sqNextDistToStep = pos.SqDistance2D(pPath->posPath[step]);
	while ((sqNextDistToStep < sqDistToStep) && (pathIterator < pathMaxIndex)) {
		pathIterator = step;
		sqDistToStep = sqNextDistToStep;
		step = std::min(pathIterator + increment, pathMaxIndex);
		sqNextDistToStep = pos.SqDistance2D(pPath->posPath[step]);
	}

	if (/*(pathIterator == lastStep) && */((int)sqDistToStep > minSqDist)
		&& (pPath->path[pathIterator + pPath->start] == lastSector))
	{
		return -1;
	} else {
		stepSpeed = speed;
	}
	lastSector = pPath->path[pathIterator + pPath->start];

	if ((int)sqDistToStep <= minSqDist) {
		pathIterator = step;
		if (pathIterator == pathMaxIndex) {
			StateFinish();
			return circuit->GetCallback()->Unit_HasCommands(unit->GetId()) ? -2 : -1;
		}
	}

	return pathMaxIndex;
}

#ifdef DEBUG_VIS
void ITravelAction::Log(CCircuitAI* circuit)
{
	circuit->LOG("travel: %p | state: %i", this, state);
}
#endif

} // namespace circuit
