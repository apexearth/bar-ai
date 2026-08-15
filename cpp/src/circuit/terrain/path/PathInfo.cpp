/*
 * PathInfo.cpp
 *
 *  Created on: Apr 21, 2022
 *      Author: rlcevg
 */

#include "terrain/path/PathInfo.h"
#include "terrain/path/PathFinder.h"

#include <new>
#include <windows.h>

namespace circuit {

void* CPathInfo::operator new(std::size_t sz)
{
	void* p = VirtualAlloc(nullptr, sz, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (p == nullptr) {
		throw std::bad_alloc();
	}
	return p;
}

void CPathInfo::operator delete(void* p)
{
	if (p != nullptr) {
		VirtualFree(p, 0, MEM_DECOMMIT);
	}
}


using namespace springai;

void CPathInfo::PushPos(const AIFloat3& pos, CPathFinder* pathfinder)
{
	posPath.push_back(pos);
	path.push_back(pathfinder->Pos2PathIndex(pos));
}

} // namespace circuit
