/*
 * UnitTask.cpp
 *
 *  Created on: Sep 2, 2014
 *      Author: rlcevg
 */

#include "task/UnitTask.h"
#include <cstring>
#include "task/IdleTask.h"
#include "task/builder/BuilderTask.h"
#include "module/TaskModule.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathQuery.h"
#include "unit/CircuitUnit.h"
#include "unit/action/AntiCapAction.h"
#include "CircuitAI.h"
#include "Log.h"
#include "util/Utils.h"

#include <map>

#include "Drawer.h"

#if CIRCUIT_TASK_REGISTRY
#include <cstdlib>
#include <mutex>
#include <unordered_map>
#include <utility>
#endif

namespace circuit {

using namespace springai;

#if CIRCUIT_TASK_REGISTRY
namespace {

// Every accessor leaks its object deliberately: a task freed during static
// destruction would otherwise touch a destroyed container, which is a second
// crash in the code meant to diagnose the first.
struct SRec {
	IUnitTask::Type type;
	int sub;  // derived subtype ordinal, -1 until NoteSubtype refines it
};
typedef std::unordered_map<const IUnitTask*, SRec> TaskTypeMap;

std::mutex& RegLock()      { static std::mutex* m = new std::mutex(); return *m; }
TaskTypeMap& LiveTasks()   { static TaskTypeMap* m = new TaskTypeMap(); return *m; }
// Two generations of freed addresses, so a miss can still report what last
// occupied the address. `young` fills to GRAVE_MAX, becomes `old`, and a fresh
// `young` starts -- bounded memory, at least GRAVE_MAX recent entries kept.
TaskTypeMap& GraveYoung()  { static TaskTypeMap* m = new TaskTypeMap(); return *m; }
TaskTypeMap& GraveOld()    { static TaskTypeMap* m = new TaskTypeMap(); return *m; }
const size_t GRAVE_MAX = 8192;

// Read once. The registry is a diagnostic; this is the switch that turns it
// off on a shipped DLL without a rebuild.
bool RegistryOn()
{
	static const bool on = (std::getenv("CIRCUIT_NO_TASK_REGISTRY") == nullptr);
	return on;
}

void RegisterLive(const IUnitTask* task, IUnitTask::Type type)
{
	if (!RegistryOn()) {
		return;
	}
	// Tasks are refcounted with std::atomic and can be released off the sim
	// thread, so the registry carries its own lock.
	std::lock_guard<std::mutex> guard(RegLock());
	SRec rec;
	rec.type = type;
	rec.sub = -1;
	LiveTasks()[task] = rec;  // an address recycled for a new task is live again
}

void UnregisterLive(const IUnitTask* task, IUnitTask::Type type)
{
	if (!RegistryOn()) {
		return;
	}
	std::lock_guard<std::mutex> guard(RegLock());
	SRec rec;
	rec.type = type;
	rec.sub = -1;
	TaskTypeMap& live = LiveTasks();
	TaskTypeMap::const_iterator known = live.find(task);
	if (known != live.end()) {
		rec = known->second;  // keep the subtype the derived ctor recorded
	}
	live.erase(task);
	TaskTypeMap& young = GraveYoung();
	if (young.size() >= GRAVE_MAX) {
		GraveOld() = std::move(young);
		young.clear();
	}
	young[task] = rec;
}

} // namespace

IUnitTask::SLiveness IUnitTask::Probe(const IUnitTask* task)
{
	SLiveness res;
	res.live = false;
	res.known = false;
	res.type = Type::NIL;
	res.sub = -1;
	if (!RegistryOn()) {
		res.live = true;  // gate off: callers must behave exactly as before
		return res;
	}

	std::lock_guard<std::mutex> guard(RegLock());
	const TaskTypeMap& live = LiveTasks();
	TaskTypeMap::const_iterator it = live.find(task);
	if (it != live.end()) {
		res.live = true;
		res.known = true;
		res.type = it->second.type;
		res.sub = it->second.sub;
		return res;
	}
	const TaskTypeMap& young = GraveYoung();
	it = young.find(task);
	if (it != young.end()) {
		res.known = true;
		res.type = it->second.type;
		res.sub = it->second.sub;
		return res;
	}
	const TaskTypeMap& old = GraveOld();
	it = old.find(task);
	if (it != old.end()) {
		res.known = true;
		res.type = it->second.type;
		res.sub = it->second.sub;
	}
	return res;
}

void IUnitTask::NoteSubtype(const IUnitTask* task, int sub)
{
	if (!RegistryOn()) {
		return;
	}
	std::lock_guard<std::mutex> guard(RegLock());
	TaskTypeMap& live = LiveTasks();
	TaskTypeMap::iterator it = live.find(task);
	if (it != live.end()) {
		it->second.sub = sub;
	}
}
#else
IUnitTask::SLiveness IUnitTask::Probe(const IUnitTask* task)
{
	(void)task;
	SLiveness res;
	res.live = true;
	res.known = false;
	res.type = Type::NIL;
	res.sub = -1;
	return res;
}

void IUnitTask::NoteSubtype(const IUnitTask* task, int sub)
{
	(void)task; (void)sub;
}
#endif

const char* IUnitTask::TypeName(Type t)
{
	switch (t) {
		case Type::NIL:     return "NIL";
		case Type::PLAYER:  return "PLAYER";
		case Type::IDLE:    return "IDLE";
		case Type::WAIT:    return "WAIT";
		case Type::RETREAT: return "RETREAT";
		case Type::BUILDER: return "BUILDER";
		case Type::FACTORY: return "FACTORY";
		case Type::FIGHTER: return "FIGHTER";
	}
	return "?";
}

IUnitTask::IUnitTask(ITaskModule* mgr, Priority priority, Type type, int timeout)
		: manager(mgr)
		, type(type)
		, priority(priority)
		, state(State::ROAM)
		, timeout(timeout)
		, updCount(0)
		, isDead(false)
		, pingPos(-RgtVector)
{
	lastTouched = manager->GetCircuit()->GetLastFrame();
#if CIRCUIT_TASK_REGISTRY
	RegisterLive(this, type);
#endif
}

IUnitTask::IUnitTask(ITaskModule* mgr, Type type)
		: manager(mgr)
		, type(type)
		, priority(Priority::LOW)
		, state(State::ROAM)
		, lastTouched(-1)
		, timeout(-1)
		, updCount(0)
		, isDead(false)
		, pingPos(-RgtVector)
{
#if CIRCUIT_TASK_REGISTRY
	RegisterLive(this, type);
#endif
}

IUnitTask::~IUnitTask()
{
#if CIRCUIT_TASK_REGISTRY
	// `type` is an IUnitTask member, so it is still readable here even though
	// the derived part is already destroyed.
	UnregisterLive(this, type);
#endif
}

void IUnitTask::ClearRelease()
{
	pathQueries.clear();
	Release();
}

bool IUnitTask::CanAssignTo(CCircuitUnit* unit) const
{
	return true;
}

void IUnitTask::AssignTo(CCircuitUnit* unit)
{
	lastTouched = -1;

	manager->GetIdleTask()->RemoveAssignee(unit);
	unit->SetTask(this);
	units.insert(unit);

	TRY_UNIT(manager->GetCircuit(), unit,
		unit->RemoveWait();
	)

	if (!unit->GetCircuitDef()->IsMobile() && manager->GetCircuit()->GetSetupManager()->IsAntiCap()) {
		unit->PushBack(new CAntiCapAction(unit));
	}
}

void IUnitTask::RemoveAssignee(CCircuitUnit* unit)
{
	pathQueries.erase(unit);
	units.erase(unit);
	unit->ClearAct();  // NOT the inherited CActionList::Clear -- that deletes the actions but leaves dgunAct/travelAct dangling (the heap-corruption writer)

	manager->GetIdleTask()->AssignTo(unit);

	if (units.empty()) {
		lastTouched = manager->GetCircuit()->GetLastFrame();
	}
}

void IUnitTask::Stop(bool done)
{
	if (done) {
		Finish();
	} else {
		Cancel();
	}

	CIdleTask* idleTask = manager->GetIdleTask();
	for (CCircuitUnit* unit : units) {
		unit->ClearAct();  // NOT the inherited CActionList::Clear -- that deletes the actions but leaves dgunAct/travelAct dangling (the heap-corruption writer)
		idleTask->AssignTo(unit);
	}
	units.clear();
	pathQueries.clear();
}

void IUnitTask::Finish()
{
}

void IUnitTask::Cancel()
{
}

// THE RANDOM STUMBLE, COUNTED. A failed move sends the unit to a random point
// 256 elmos away, and the traced builders that never reach their sites are all
// carrying orders of exactly that shape. Whether that is the whole story turns
// on how OFTEN this fires and whether it fires REPEATEDLY on the same unit:
// once is a nudge past an obstacle, forty times is a unit walking in circles
// until its task is aborted. Counted before it is changed.
static std::map<int, int> sMfPerUnit;
static unsigned sMfFires = 0;
static int sMfLogAt = 0;

void IUnitTask::OnUnitMoveFailed(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();

	++sMfFires;
	const int n = ++sMfPerUnit[(int)unit->GetId()];
	if (frame >= sMfLogAt) {
		sMfLogAt = frame + FRAMES_PER_SEC * 60;
		int worst = 0, worstId = -1, repeaters = 0;
		for (const auto& kv : sMfPerUnit) {
			if (kv.second > 1) { ++repeaters; }
			if (kv.second > worst) { worst = kv.second; worstId = kv.first; }
		}
		circuit->LOG("apex: movefail t=%i fires=%u units=%i repeaters=%i worst=%i(u%i)",
				circuit->GetTeamId(), sMfFires, (int)sMfPerUnit.size(),
				repeaters, worst, worstId);
	}
	// The individual case, rate-limited by repeat count so the log shows the
	// shape without one unit flooding it: how far it still is from the job it
	// cannot reach.
	if ((n == 5) || (n == 25) || (n == 100)) {
		IUnitTask* t = unit->GetTask();
		float toSite = -1.f;
		if ((t != nullptr) && (t->GetType() == IUnitTask::Type::BUILDER)) {
			const AIFloat3& bp = static_cast<IBuilderTask*>(t)->GetPosition();
			if (utils::is_valid(bp)) {
				toSite = unit->GetPos(frame).distance2D(bp);
			}
		}
		circuit->LOG("apex: movefail-unit t=%i u=%i %s n=%i toSite=%.0f",
				circuit->GetTeamId(), (int)unit->GetId(),
				(unit->GetCircuitDef() != nullptr)
						? unit->GetCircuitDef()->GetDef()->GetName() : "?",
				n, toSite);
	}

	AIFloat3 pos = utils::get_radial_pos(unit->GetPos(frame), SQUARE_SIZE * 32);
	CTerrainManager::CorrectPosition(pos);
	TRY_UNIT(circuit, unit,
		unit->CmdMoveTo(pos, UNIT_CMD_OPTION, frame + FRAMES_PER_SEC, CCircuitUnit::OrdSrc::BUILD);
	)
}

void IUnitTask::OnTravelEnd(CCircuitUnit* unit)
{
}

void IUnitTask::OnRearmStart(CCircuitUnit* unit)
{
}

void IUnitTask::Dead()
{
	isDead = true;
	pathQueries.clear();  // free queries
}

void IUnitTask::Abort()
{
	// Only the script calls this; without a note every such death reads "?".
	if ((type == Type::BUILDER) && (std::strcmp(static_cast<IBuilderTask*>(this)->GetDeathNote(), "?") == 0)) {
		static_cast<IBuilderTask*>(this)->SetDeathNote("script-abort");
	}
	manager->AbortTask(this);
}

void IUnitTask::Done()
{
	manager->DoneTask(this);
}

bool IUnitTask::IsQueryReady(CCircuitUnit* unit) const
{
	const auto it = pathQueries.find(unit);
	std::shared_ptr<IPathQuery> query = (it == pathQueries.end()) ? nullptr : it->second;
	return (query == nullptr) || (IPathQuery::State::READY == query->GetState());
}

void IUnitTask::IntentPing(const AIFloat3& pos, const std::string& msg)
{
	CCircuitAI* circuit = manager->GetCircuit();
	if (circuit->GetTunable("apex_ping", 0.f) <= 0.f) {
		return;
	}
	// The unchanged-intent window: re-ping only once the squad has moved far
	// enough that the old mark no longer says where it is.
	if ((msg == pingMsg) && utils::is_valid(pingPos)
		&& (pos.SqDistance2D(pingPos) < SQUARE(600.f)))
	{
		return;
	}
	if (utils::is_valid(pingPos)) {
		circuit->GetDrawer()->DeletePointsAndLines(pingPos);
	}
	circuit->GetDrawer()->AddPoint(pos, msg.c_str());
	pingMsg = msg;
	pingPos = pos;
}

#define SERIALIZE(stream, func)	\
	utils::binary_##func(stream, priority);		\
	utils::binary_##func(stream, state);		\
	utils::binary_##func(stream, lastTouched);	\
	utils::binary_##func(stream, timeout);		\
	utils::binary_##func(stream, updCount);		\
	utils::binary_##func(stream, isDead);

bool IUnitTask::Load(std::istream& is)
{
	SERIALIZE(is, read)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | priority=%i | state=%i | lastTouched=%i | timeout=%i | updCount=%i | isDead=%i",
			__PRETTY_FUNCTION__, priority, state, lastTouched, timeout, updCount, isDead);
#endif
	return true;
}

void IUnitTask::Save(std::ostream& os) const
{
	SERIALIZE(os, write)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | priority=%i | state=%i | lastTouched=%i | timeout=%i | updCount=%i | isDead=%i",
			__PRETTY_FUNCTION__, priority, state, lastTouched, timeout, updCount, isDead);
#endif
}

#ifdef DEBUG_VIS
void IUnitTask::Log()
{
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->LOG("task: %lx | type: %i | state: %i", this, type, state);
}
#endif

} // namespace circuit
