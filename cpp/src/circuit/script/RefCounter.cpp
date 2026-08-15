/*
 * RefCounter.cpp
 *
 *  Created on: Apr 6, 2019
 *      Author: rlcevg
 */

#include "script/RefCounter.h"

#include <new>
#include <windows.h>

namespace circuit {

void* IRefCounter::operator new(std::size_t sz)
{
	void* p = VirtualAlloc(nullptr, sz, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (p == nullptr) {
		throw std::bad_alloc();
	}
	return p;
}

void IRefCounter::operator delete(void* p)
{
	if (p != nullptr) {
		VirtualFree(p, 0, MEM_DECOMMIT);  // keep reserved: the address must never be reused
	}
}

IRefCounter::IRefCounter()
		: refCount(1)
{
}

IRefCounter::~IRefCounter()
{
	// Poison: any AddRef/Release arriving after destruction reads this and
	// traps AT THE BAD CALL, so the engine's stack dump names the culprit
	// instead of whoever later trips over the corrupted heap.
	refCount.store(kPoison);
}

int IRefCounter::AddRef()
{
	const int prev = refCount.fetch_add(1);
	if (prev <= 0) {
		__builtin_trap();  // AddRef on a dead or already-freed object
	}
	return prev + 1;
}

int IRefCounter::Release()
{
	const int prev = refCount.fetch_sub(1);
	if (prev <= 0) {
		__builtin_trap();  // Release on a dead object: the over-release IS this call
	}
	if (permanent && (prev == 1)) {
		__builtin_trap();  // a singleton released to zero: THIS call is the imbalance
	}
	if (prev == 1) {
		delete this;
		return 0;
	}
	return prev - 1;
}

int IRefCounter::GetRefCount() const
{
	return refCount;
}

} // namespace circuit
