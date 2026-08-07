#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"
#include "manager/air.as"


namespace Main {

// A gap narrower than this is an artefact between interior areas, not a corridor
// an army could hold; wider than this is open ground that no line would cover.
const float CHOKE_MIN_WIDTH = 200.f;
const float CHOKE_MAX_WIDTH = 2000.f;

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
}

// BWEM chokepoint inventory, logged once. Confirmed returning real data on
// Comet Catcher (8) and Jade Empress (100); kept as a one-liner because the
// usable count, not the raw count, is what the front-line work depends on --
// most of Jade's 100 are sub-200-elmo slivers between interior areas.
bool gChokeProbed = false;
void ProbeChokePoints()
{
	if (gChokeProbed || (ai.frame < 2 * SECOND))
		return;
	gChokeProbed = true;
	const int n = ai.GetChokePointCount();
	int usable = 0;
	for (int i = 0; i < n; ++i) {
		const float w = ai.GetChokePointWidth(i);
		if ((w >= CHOKE_MIN_WIDTH) && (w <= CHOKE_MAX_WIDTH))
			++usable;
	}
	AiLog("apex: chokepoints count=" + n + " usable=" + usable);
}

void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	ProbeChokePoints();
	Factory::UpdateTeamCoord();
	Military::UpdatePosture();
	Factory::UpdateRushReclaim();
	Factory::LogRushState();
	Air::Update();
}

}  // namespace Main
