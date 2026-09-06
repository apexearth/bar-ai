/*
 * RefCounter.h
 *
 *  Created on: Apr 6, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SCRIPT_REFCOUNTER_H_
#define SRC_CIRCUIT_SCRIPT_REFCOUNTER_H_

#include <atomic>
#include <cstddef>

namespace circuit {

/*
 * WARNING: Use asMETHODPR to register IRefCounter,
 *          asMETHOD may not detect ptrdiff_t of member function
 *          (multiple inheritance)
 */
class IRefCounter {
public:
	IRefCounter();
	virtual ~IRefCounter();

public:
	int AddRef();
	int Release();
	int GetRefCount() const;

	static constexpr int kPoison = -0x40000000;

	// CRASH DIAGNOSTIC (temporary): singletons (nil/idle/player tasks) must
	// never be released to zero before their module's dtor; trap at the
	// over-releasing call so the stack dump names it.
	// The cushion turns holder-count noise into a clean signal: a singleton's
	// count is cushion + born + holders, holders never negative, so ANY
	// release observing prev <= kCushion+1 is a net over-release -- the trap
	// fires at the offending call, not at the last legitimate holder's exit.
	static constexpr int kCushion = 1000000;
	void SetPermanent() { permanent = true; refCount += kCushion; }
	void ClearPermanent() { permanent = false; refCount -= kCushion; }
	bool IsPermanent() const { return permanent; }

	// CRASH DIAGNOSTIC (temporary): each refcounted object lives on its own
	// VirtualAlloc'd page; delete decommits but never releases the address
	// range, so ANY use-after-free faults at the guilty instruction instead
	// of corrupting whoever reused the heap block (observed: Lua GC).

private:
	std::atomic<int> refCount;
	bool permanent = false;
};

} // namespace circuit

#endif // SRC_CIRCUIT_SCRIPT_REFCOUNTER_H_
