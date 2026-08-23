/*
 * UnitTask.h
 *
 *  Created on: Sep 2, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_UNITTASK_H_
#define SRC_CIRCUIT_TASK_UNITTASK_H_

// Task liveness registry -- diagnosis for the stale-task crash, not a fix.
// Build with -DCIRCUIT_TASK_REGISTRY=0 to compile it out entirely; set
// CIRCUIT_NO_TASK_REGISTRY in the environment to disable it without a rebuild.
#ifndef CIRCUIT_TASK_REGISTRY
#define CIRCUIT_TASK_REGISTRY 1
#endif

#include "script/RefCounter.h"

#include "AIFloat3.h"
//#define DEBUG_SAVELOAD 1
#ifdef DEBUG_SAVELOAD
#include "Log.h"
#endif

#include <set>
#include <map>
#include <memory>
#include <string>

namespace springai {
	class Unit;
}

namespace circuit {

class CCircuitUnit;
class CEnemyInfo;
class ITaskModule;
class IPathQuery;
class CQueryPathSingle;
class CQueryPathMulti;

class IUnitTask: public IRefCounter {  // CSquad, IAction
public:
	enum class Priority: char {LOW = 0, NORMAL = 1, HIGH = 2, NOW = 99};
	enum class Type: char {NIL, PLAYER, IDLE, WAIT, RETREAT, BUILDER, FACTORY, FIGHTER};
	enum class State: char {ROAM, ENGAGE, DISENGAGE, REGROUP};

protected:
	IUnitTask(ITaskModule* mgr, Priority priority, Type type, int timeout);
	IUnitTask(ITaskModule* mgr, Type type);  // Load
	virtual ~IUnitTask();
public:
	virtual void ClearRelease();

	virtual bool CanAssignTo(CCircuitUnit* unit) const;
	virtual void AssignTo(CCircuitUnit* unit);
	virtual void RemoveAssignee(CCircuitUnit* unit);

	virtual void Start(CCircuitUnit* unit) = 0;  // <=> IAction::OnStart()
	virtual void Update() = 0;
	virtual void Stop(bool done);  // <=> IAction::OnEnd()
protected:
	// NOTE: Do not run time consuming code here. Instead create separate task.
	virtual void Finish();
	virtual void Cancel();  // TODO: Make pure virtual?

public:
	virtual void OnUnitIdle(CCircuitUnit* unit) = 0;
	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) = 0;
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) = 0;
	void OnUnitMoveFailed(CCircuitUnit* unit);

	virtual void OnTravelEnd(CCircuitUnit* unit);
	virtual void OnRearmStart(CCircuitUnit* unit);

	const std::set<CCircuitUnit*>& GetAssignees() const { return units; }
	Priority GetPriority() const { return priority; }
	Type GetType() const { return type; }
	ITaskModule* GetManager() const { return manager; }

	int GetLastTouched() const { return lastTouched; }
	int GetTimeout() const { return timeout; }

	virtual void Dead();
	bool IsDead() const { return isDead; }

	// AS API
	void Abort();
	void Done();

	// Liveness registry. CCircuitUnit::task is a RAW pointer and IRefCounter
	// deletes at zero, so a stranded task pointer is freed memory that still
	// reads as a pointer -- the vtable fetch is what faults. Probe answers
	// "is a live IUnitTask registered at this address" WITHOUT dereferencing
	// it. An address the allocator has already recycled for a new task reads
	// as live, so this proves absence, never identity.
	struct SLiveness {
		bool live;   // a live IUnitTask is registered at this address
		bool known;  // address seen before (live now, or freed earlier)
		Type type;   // type recorded FOR THAT ADDRESS; junk unless `known`
		int sub;     // subtype ordinal recorded by NoteSubtype, -1 if none
	};
	static SLiveness Probe(const IUnitTask* task);
	static const char* TypeName(Type t);
	// Refines a live entry with a derived-class subtype. Must be called from
	// the DERIVED constructor: at IUnitTask's own ctor the derived part does
	// not exist yet. Kept as an opaque int so this base header does not have
	// to know any derived enum.
	static void NoteSubtype(const IUnitTask* task, int sub);

protected:
	bool IsQueryReady(CCircuitUnit* unit) const;

	// Intent ping for a watching player (apex_ping=1): marks the map when this
	// task's intent CHANGES. The same message near the last mark is silent, so
	// a decision point that re-fires every update cycle draws once per actual
	// change of mind, and the previous mark is erased to keep the map legible.
	void IntentPing(const springai::AIFloat3& pos, const std::string& msg);

public:
	friend bool operator>>(std::istream& is, IUnitTask& data);
	friend std::ostream& operator<<(std::ostream& os, const IUnitTask& data);
protected:
	virtual bool Load(std::istream& is);
	virtual void Save(std::ostream& os) const;

	ITaskModule* manager;
	std::set<CCircuitUnit*> units;
	Type type;
	Priority priority;
	State state;
	std::map<CCircuitUnit*, std::shared_ptr<IPathQuery>> pathQueries;  // IPathQuery owner

	int lastTouched;
	int timeout;

	unsigned int updCount;
	bool isDead;

	std::string pingMsg;                 // see IntentPing
	springai::AIFloat3 pingPos;

#ifdef DEBUG_VIS
public:
	virtual void Log();
#endif
};

inline bool operator>>(std::istream& is, IUnitTask& data)
{
	return data.Load(is);
}

inline std::ostream& operator<<(std::ostream& os, const IUnitTask& data)
{
	data.Save(os);
	return os;
}

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_UNITTASK_H_
