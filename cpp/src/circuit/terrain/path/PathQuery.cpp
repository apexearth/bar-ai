/*
 * PathQuery.cpp
 *
 *  Created on: Apr 22, 2020
 *      Author: rlcevg
 */

#include "terrain/path/PathQuery.h"

#include <new>
#include <windows.h>

namespace circuit {

void* IPathQuery::operator new(std::size_t sz)
{
	void* p = VirtualAlloc(nullptr, sz, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (p == nullptr) {
		throw std::bad_alloc();
	}
	return p;
}

void IPathQuery::operator delete(void* p)
{
	if (p != nullptr) {
		VirtualFree(p, 0, MEM_DECOMMIT);
	}
}


IPathQuery::IPathQuery(const CPathFinder& pathfinder, int id, Type type)
		: pathfinder(pathfinder)
		, id(id)
		, type(type)
		, state(State::NONE)
		, canMoveArray(nullptr)
		, threatArray(nullptr)
		, unit(nullptr)
{
}

IPathQuery::~IPathQuery()
{
}

void IPathQuery::Init(const float* canMoveArray, const float* threatArray,
		NSMicroPather::CostFunc&& moveFun, NSMicroPather::CostFunc&& threatFun,
		CCircuitUnit* unit)
{
	this->canMoveArray = canMoveArray;
	this->threatArray = threatArray;
	this->moveFun = moveFun;
	this->threatFun = threatFun;
	this->unit = unit;  // optional
}

} // namespace circuit
