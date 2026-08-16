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
	Builder::SampleTaskHist();
	Builder::PromoteAssistBots();
	Builder::UpdateEconomicCaps();
	Builder::AdvConDiag();
	Builder::ExpandDiag();
	Builder::CancelDoomedRepairs();
	Builder::UpdateSiege();
	Builder::NanoTidy();
}

// The per-unit FINISHED event, all managers -- unlike Builder::AiUnitAdded,
// which is the ECONOMY module's hook and fires only for economy-tracked units
// (a radar tower never reaches it). Looked up by name, same as AiUnitDestroyed.
// Finished ids, so the death log can say whether a unit ever COMPLETED --
// without this a base assault's nanoframe kills read as full-cost "taskless"
// deaths and drowned the real combat attribution (44-47% of "lost metal" in
// the first audited games). Bounded ring, oldest dropped.
array<int> gFinishedIds;
const uint FINISHED_RING = 4096;

bool WasFinished(int id)
{
	for (uint i = 0; i < gFinishedIds.length(); ++i) {
		if (gFinishedIds[i] == id)
			return true;
	}
	return false;
}

void AiUnitFinished(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	gFinishedIds.insertLast(int(unit.id));
	if (gFinishedIds.length() > FINISHED_RING)
		gFinishedIds.removeAt(0);
	// The reactor/converter pipelines need COMPLETIONS, not creations --
	// def.count moves on the nanoframe.
	if (unit.circuitDef !is null)
		Builder::NoteEcoFinished(unit.circuitDef.GetName());
	// RadarNet's standing ledger: positions, because coverage is a place, and
	// a dead radar must re-open its border rank (a count cannot say where).
	CCircuitDef@ radDef = Builder::RadarTowerDef();
	if ((radDef !is null) && (unit.circuitDef.id == radDef.id))
		Builder::RadarStandAdd(unit.GetPos(ai.frame));
	CCircuitDef@ nanoDef = Builder::NanoDef();
	if ((nanoDef !is null) && (unit.circuitDef.id == nanoDef.id))
		Builder::NanoNoteBuilt(unit.id);
}

// CInitScript::UnitDestroyed (InitScript.cpp:1224) looks this exact signature
// up and calls it for every one of OUR units destroyed, across all managers --
// it was simply never implemented, which is the "AiUnitDestroyed ... not
// found!" warning at every match start. Task history is builder-crew only;
// see Builder::SampleTaskHist/TakeHistFor in manager/builder/events.as.
void AiUnitDestroyed(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	const AIFloat3 at = unit.GetPos(ai.frame);
	IUnitTask@ t = unit.task;
	const int tt = (t is null) ? -1 : t.GetType();
	const int bt = ((t !is null) && (tt == Task::Type::BUILDER)) ? t.GetBuildType() : -1;
	CCircuitDef@ radDefGone = Builder::RadarTowerDef();
	if ((cdef !is null) && (radDefGone !is null) && (cdef.id == radDefGone.id))
		Builder::RadarStandRemoveNear(at);
	CCircuitDef@ nanoGone = Builder::NanoDef();
	if ((cdef !is null) && (nanoGone !is null) && (cdef.id == nanoGone.id))
		Builder::NanoNoteGone(unit.id);
	// The fight type IS "the last major action" for a combat unit -- attack,
	// defend, raid, retreat all leave a distinct value here -- and the forward
	// fraction says WHERE it died (0 home, 1 at the enemy). tools/deaths.py
	// aggregates these lines into metal-lost-by-last-action.
	const int ft = ((t !is null) && (tt == Task::Type::FIGHTER)) ? t.GetFightType() : -1;
	if (cdef !is null)
		Builder::NoteEcoGone(cdef.GetName(), WasFinished(int(unit.id)));
	const string hist = Builder::TakeHistFor(int(unit.id));
	AiLog(Factory::T() + "apex: unit-destroyed " + ((cdef !is null) ? cdef.GetName() : "?")
		+ " id=" + unit.id + " frame=" + ai.frame
		+ " at=" + int(at.x) + "," + int(at.z)
		+ " curTask=t" + tt + "b" + bt + "f" + ft
		+ " cost=" + int((cdef !is null) ? cdef.costM : 0.f)
		+ " fwd=" + formatFloat(Military::ForwardFraction(at), "", 0, 2)
		+ " built=" + (WasFinished(int(unit.id)) ? 1 : 0)
		+ " mob=" + (((cdef !is null) && cdef.IsMobile()) ? 1 : 0)
		+ " hist=[" + hist + "]");
}

}  // namespace Main
