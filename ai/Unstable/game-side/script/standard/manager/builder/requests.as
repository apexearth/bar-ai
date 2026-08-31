// namespace Requests, split across requests/. THE ORDER BELOW IS LOAD-BEARING
// -- see manager/builder.as for why. It is the order the file had before the
// split; nothing moved between parts.
//
// ONE PLACE DECIDES WHETHER A BUILDING MAY BE STARTED.
//
// A request queue: something decides we want a building; the request is
// placed once; whoever takes it works it; if the worker is pulled away the
// request goes back to being available; when the building is up the request
// is gone. There is no way to place the same request twice.
//
// THE REQUEST RECORD IS THE ENGINE'S OWN TASK, not a parallel structure, so
// the lifecycle is real rather than bookkeeping kept in step by hand:
//
//   proposed     an IBuilderTask in the queue with no assignee. Available: the
//                next caller that wants this def here is handed THIS task.
//   claimed      GetUnits() is non-empty. A builder is walking to it.
//   in-progress  `target` is set -- IBuilderTask::SetTarget runs when the
//                nanoframe appears (BuilderTask.cpp:403).
//   cancelled    the builder was reassigned; the task keeps its place in the
//                queue with no assignee, i.e. it is proposed again.
//   done/aborted DequeueTask -> AiTaskRemoved -> Forget.
//
// AND IT SEES EVERY PRODUCER, not just the script ones: every task, including
// those made by C++ (DefaultMakeDefence, MakeEconomyTasks, build_chain), is
// created through CBuilderManager::Enqueue, which fires TaskAdded
// (BuilderManager.cpp:744) -> AiTaskAdded -> Register below.
#include "requests/census.as"    // the gate census: seen/refused per early return
#include "requests/governed.as"  // what is governed; the income-derived caps and crews
#include "requests/register.as"  // the big-energy class, the live register, standing frames
#include "requests/take.as"      // Take(): the chokepoint itself
#include "requests/join.as"      // cover, folds onto standing work, claims, in-flight
#include "requests/peel.as"      // peeling surplus hands, energy consolidation

// Create() and Log() stay in THIS file rather than a part: tools/check.py's
// spend census allowlists the request plumbing's own Enqueue by this exact
// path, and a part file would read as leaf logic growing back.
namespace Requests {

IUnitTask@ Create(CCircuitDef@ want, Task::BuildType bt, Task::Priority prio,
		const AIFloat3& in spot, float shake)
{
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(bt, prio, want, spot, shake));
	if (post !is null) {
		++gCreated;
		Log(want, "new");
	}
	return post;
}

void Log(CCircuitDef@ want, const string& in what)
{
	const int id = want.id;
	const bool tracked = (id >= 0) && (uint(id) < gNextDefLog.length());
	if (tracked && (ai.frame < gNextDefLog[id]))
		return;
	if (tracked)
		gNextDefLog[id] = ai.frame + 10 * SECOND;
	// inFlight/cap answer the actual question a burst of one def raises: was
	// this "new" allowed because the economy could genuinely feed another one
	// in parallel, or did it slip past a cap that should have refused it.
	AiLog(Factory::T() + "apex: request " + what + " " + want.GetName()
		+ " inFlight=" + InFlight(want) + " cap=" + InFlightCap()
		+ " live=" + gLive.length()
		+ " new=" + gCreated + " join=" + gJoined
		+ " covered=" + gCovered + " full=" + gFull + " tooFar=" + gTooFar);
}

}  // namespace Requests
