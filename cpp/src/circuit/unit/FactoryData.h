/*
 * FactoryData.h
 *
 *  Created on: Dec 8, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_UNIT_FACTORYDATA_H_
#define SRC_CIRCUIT_UNIT_FACTORYDATA_H_

#include "unit/CircuitDef.h"

#include <unordered_map>

namespace circuit {

class CCircuitAI;

class CFactoryData {
public:
	CFactoryData();
	virtual ~CFactoryData();

	CCircuitDef* GetFactoryToBuild(CCircuitAI* circuit, springai::AIFloat3 position = -RgtVector,
								   bool isStart = false, bool isReset = false);
	void AddFactory(const CCircuitDef* cdef);
	void DelFactory(const CCircuitDef* cdef);

private:
	unsigned int choiceNum;
	struct SFactory {
		int count = 0;
	};
	std::unordered_map<CCircuitDef::Id, SFactory> allFactories;
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_FACTORYDATA_H_
