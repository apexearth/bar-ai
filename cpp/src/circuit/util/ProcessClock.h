/*
 * ProcessClock.h
 *
 * Time since this process started, in nanoseconds. The engine stamps its log
 * lines with the time since its first log call, the same moment to within a
 * few milliseconds, so our own log file can carry the same [t=].
 */

#ifndef SRC_CIRCUIT_UTIL_PROCESSCLOCK_H_
#define SRC_CIRCUIT_UTIL_PROCESSCLOCK_H_

#include <cstdint>

namespace utils {

int64_t ProcessAgeNs();

}  // namespace utils

#endif  // SRC_CIRCUIT_UTIL_PROCESSCLOCK_H_
