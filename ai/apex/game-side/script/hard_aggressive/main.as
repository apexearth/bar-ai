#include "../side.as"
#include "../world.as"
#include "targets.as"          // EVERY build ratio, in one file
#include "manager/brain/budget.as"  // the one place the build split is stated
#include "manager/brain.as"       // macro view: rules propose Wants, this ranks them
#include "manager/brain/mix.as"   // ...and the target army composition
#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/brain/facqueue.as"  // ...and drives a factory itself, as a standing queue
#include "manager/economy.as"
#include "manager/air.as"
#include "manager/frontline.as"
#include "manager/baseplan.as"
#include "manager/crew.as"
#include "manager/assist.as"


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
}

void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	// Ahead of the ApexActive gate: a unit walled in by our own buildings is
	// broken in a solo game exactly as it is in a team one, and freeing it is a
	// fix rather than a piece of the team machinery that gate exists for.
	Military::UpdateUnblock();
	Military::UpdateMoveTests();

	if (!ApexActive())
		return;

	Builder::SampleWreckField();   // before the queue that reads WreckSeenValue
	Brain::UpdateFacQueues();
	Brain::LogFacQueues();
	Factory::UpdateTeamCoord();
	Military::UpdateLanePos();
	Military::UpdateSpamPosture();
	Military::UpdatePosture();
	Factory::SampleIncome();
	Factory::UpdateRushReclaim();
	Factory::LogRushState();
	Air::Update();
	Front::Update();
	Base::Update();
	Crew::Update();
	Assist::Update();
	Builder::CommIdleAttribute();
	Builder::PromoteAssistBots();
	Builder::UpdateEconomicCaps();
	Builder::AdvConDiag();
	Builder::ExpandDiag();
}

}  // namespace Main
