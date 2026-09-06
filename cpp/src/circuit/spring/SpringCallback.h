/*
 * SpringCallback.h
 *
 *  Created on: Nov 8, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SPRING_SPRINGCALLBACK_H_
#define SRC_CIRCUIT_SPRING_SPRINGCALLBACK_H_

#include "OOAICallback.h"  // C++ wrapper

#include <vector>

struct SSkirmishAICallback;

namespace circuit {

class COOAICallback {
public:
	COOAICallback(springai::OOAICallback* clb);
	virtual ~COOAICallback();

	void Init(const struct SSkirmishAICallback* clb);

	springai::Debug*    GetDebug()    const { return callback->GetDebug(); }
	springai::DataDirs* GetDataDirs() const { return callback->GetDataDirs(); }
	springai::File*     GetFile()     const { return callback->GetFile(); }

	springai::Economy* GetEconomy() const { return callback->GetEconomy(); }
	springai::Map*     GetMap()     const { return callback->GetMap(); }
	springai::Mod*     GetMod()     const { return callback->GetMod(); }
	springai::Resource* GetResourceByName(const char* resourceName) const {
		return callback->GetResourceByName(resourceName);
	}

	int GetEnemyTeamSize() const;

	std::vector<springai::Unit*> GetTeamUnits() const { return callback->GetTeamUnits(); }

	const std::vector<springai::Unit*>& GetFriendlyUnits();
	const std::vector<springai::Unit*>& GetFriendlyUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true);
	bool IsFriendlyUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true) const;
	const std::vector<int>& GetFriendlyUnitIdsIn(const springai::AIFloat3& pos, float radius, bool spherical = true);
	// apex: ids only -- GetFriendlyUnits() news a WrappUnit per unit, and the
	// ally-list diff only needs a wrapper for a unit it has never seen.
	// Leaf use only -- shared buffer, a nested query overwrites it.
	const std::vector<int>& GetFriendlyUnitIds();
	springai::Unit* WrapUnit(int unitId) const;

	const std::vector<springai::Unit*>& GetEnemyUnits();
	const std::vector<springai::Unit*>& GetEnemyUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true);
	bool IsEnemyUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true) const;
	// apex: the count alone, with no WrappUnit allocated per enemy.
	int CountEnemyUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true) const;
	const std::vector<int>& GetEnemyUnitIdsIn(const springai::AIFloat3& pos, float radius, bool spherical = true);

	const std::vector<springai::Unit*>& GetNeutralUnits();
	const std::vector<springai::Unit*>& GetNeutralUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true);
	bool IsNeutralUnitsIn(const springai::AIFloat3& pos, float radius, bool spherical = true) const;

	std::vector<springai::Unit*> GetSelectedUnits() const { return callback->GetSelectedUnits(); }

	springai::UnitDef* GetUnitDefByName(const char* unitName) const { return callback->GetUnitDefByName(unitName); }
	std::vector<springai::UnitDef*> GetUnitDefs() const { return callback->GetUnitDefs(); }
	std::vector<springai::WeaponDef*> GetWeaponDefs() const { return callback->GetWeaponDefs(); }

	std::vector<springai::Feature*> GetFeatures() const { return callback->GetFeatures(); }
	std::vector<springai::Feature*> GetFeaturesIn(const springai::AIFloat3& pos, float radius, bool spherical = true) const {
		return callback->GetFeaturesIn(pos, radius, spherical);
	}
	bool IsFeatures() const;
	bool IsFeaturesIn(const springai::AIFloat3& pos, float radius, bool spherical = true) const;

	int Unit_GetDefId(int unitId) const;
	bool Unit_HasCommands(int unitId) const;

	bool Feature_IsResurrectable(int featureId) const;

	// apex: id-only feature access. GetFeaturesIn() news a WrappFeature per
	// feature and every getter on it news another wrapper, so a sweep of a
	// wreck field is a few thousand heap round trips on top of the engine
	// calls -- and wrecks are what grows in a long game. These take ids.
	// Fills the shared buffer and returns how many; read it with GetFeatureIdBuf().
	// Leaf use only -- one buffer, so a nested query overwrites the outer one.
	int GetFeatureIdsIn(const springai::AIFloat3& pos, float radius, bool spherical = false);
	const int* GetFeatureIdBuf() const { return featureIds.data(); }
	int Feature_GetDefId(int featureId) const;
	int Feature_GetResurrectDefId(int featureId) const;
	float Feature_GetReclaimLeft(int featureId) const;
	springai::AIFloat3 Feature_GetPosition(int featureId) const;
	float FeatureDef_GetContainedResource(int featureDefId, int resourceId) const;
	const char* FeatureDef_GetName(int featureDefId) const;

	bool UnitDef_HasYardMap(int unitDefId) const;

private:
	const struct SSkirmishAICallback* sAICallback;
	springai::OOAICallback* callback;
	int skirmishAIId;

	std::vector<int> unitIds;
	std::vector<springai::Unit*> units;
	std::vector<int> featureIds;
};

} // namespace circuit

#endif // SRC_CIRCUIT_SPRING_SPRINGCALLBACK_H_
