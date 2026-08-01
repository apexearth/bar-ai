#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"
#include "manager/air.as"


namespace Main {

void AiMain()
{
	// NOTE: Initialize config params
// 	aiTerrainMgr.SetAllyZoneRange(600);  // returns 576: (multiples of 128) div 2
// 	aiEconomyMgr.reclConvertEff = 2.f;
// 	aiEconomyMgr.reclEnergyEff = 20.f;
// 	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
// 		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
// 		AiLog(cdef.GetName() + " | threat = " + cdef.threat + " | power = " + cdef.power +
// 			" | air = " + cdef.GetAirThreat() + " | surf = " + cdef.GetSurfThreat() + " | water = " + cdef.GetWaterThreat());
// 		cdef.SetThreatKernel((cdef.costM + cdef.costE * 0.02f) * 0.001f);
// 	}

	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
		if (cdef.costM >= 200.f && !cdef.IsMobile() && aiEconomyMgr.GetEnergyMake(cdef) > 1.f)
			cdef.AddAttribute(Unit::Attr::BASE.type);  // Build heavy energy at base
	}

	// Example of user-assigned custom attributes
	array<string> names = {Factory::armalab, Factory::coralab, Factory::legalab, Factory::armavp, Factory::coravp, Factory::legavp,
		Factory::armaap, Factory::coraap, Factory::legaap, Factory::armasy, Factory::corasy};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T2;
	}
	names = {Factory::armshltx, Factory::corgant, Factory::leggant};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T3;
	}

	// A map with a puddle of water does not justify amphibious units, which cost
	// more than the land unit they displace and fight worse once ashore.
	// apexearth: "if theres only a tiny bit of water in the map we shouldn't make
	// any T1 or T2 amphibious tanks."
	//
	// GetLandPercent is 0-100 -- TerrainData scales the sector counts by
	// 100/(convertStoHM^2). SetMaxThisUnit(0) makes IsAvailable() false at every
	// site that asks -- factory weights, build chains, role lookups -- rather than
	// each of them needing to learn a water rule.
	// No dry-map unit disabling, deliberately. A name list missed every hovercraft;
	// sweeping the surface class instead caught 128 defs, including ships that need
	// a shipyard no dry map can host and hover/amphibious units that fight fine on
	// land. Dropped as not worth the blast radius. The bindings exist if it is ever
	// wanted: SetMaxThisUnit plus IsSurfer/IsFloater/IsAmphibious/IsSubmarine.
}

void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	Builder::UpdateIncomeAvg();
	Factory::UpdateTeamCoord();
	Military::UpdatePosture();
	Factory::UpdateRushReclaim();
	Factory::LogRushState();
	Air::Update();
}

}  // namespace Main
