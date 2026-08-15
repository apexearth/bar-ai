/*
 * Action.cpp
 *
 *  Created on: Jan 5, 2015
 *      Author: rlcevg
 *      Origin: Randy Gaul (http://gamedevelopment.tutsplus.com/tutorials/the-action-list-data-structure-good-for-ui-ai-animations-and-more--gamedev-9264)
 */

#include "util/Action.h"

#include <new>
#include <windows.h>

namespace circuit {

void* IAction::operator new(std::size_t sz)
{
	void* p = VirtualAlloc(nullptr, sz, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (p == nullptr) {
		throw std::bad_alloc();
	}
	return p;
}

void IAction::operator delete(void* p)
{
	if (p != nullptr) {
		VirtualFree(p, 0, MEM_DECOMMIT);  // keep reserved: address never reused
	}
}

IAction::IAction(CActionList* owner)
		: ownerList(owner)
		, isBlocking(false)
		, state(State::ACTIVE)
{
}

IAction::~IAction()
{
}

void IAction::OnStart()
{
}

void IAction::OnEnd()
{
	state = State::HALT;
}

} // namespace circuit
