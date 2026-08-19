#include "../side.as"
#include "../world.as"
#include "perf.as"
#include "targets.as"          // EVERY build ratio, in one file
#include "manager/brain/budget.as"  // the one place the build split is stated
#include "manager/brain.as"       // macro view: rules propose Wants, this ranks them
#include "manager/brain/mix.as"   // ...and the target army composition
#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/persona.as"     // per-instance identity: biases, never gates
#include "manager/brain/nukes.as" // the nuke director: saved volleys vs antinukes
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

	double t = Perf::T0();
	Builder::SampleWreckField();   // before the queue that reads WreckSeenValue
	Perf::Add("upd.WreckField", t);
	t = Perf::T0();
	Brain::UpdateFacQueues();
	Brain::LogFacQueues();
	Perf::Add("upd.FacQueues", t);
	t = Perf::T0();
	Factory::UpdateTeamCoord();
	Perf::Add("upd.TeamCoord", t);
	t = Perf::T0();
	Military::UpdateLanePos();
	Military::UpdateDeathLedger();
	Brain::UpdateNukes();
	Military::UpdateSpamPosture();
	Military::UpdatePosture();
	Perf::Add("upd.Military", t);
	t = Perf::T0();
	Factory::SampleIncome();
	Factory::UpdateRushReclaim();
	Factory::LogRushState();
	Perf::Add("upd.FactoryMisc", t);
	t = Perf::T0();
	Air::Update();
	Perf::Add("upd.Air", t);
	t = Perf::T0();
	Front::Update();
	Perf::Add("upd.Front", t);
	t = Perf::T0();
	Base::Update();
	Perf::Add("upd.Base", t);
	t = Perf::T0();
	Crew::Update();
	Perf::Add("upd.Crew", t);
	t = Perf::T0();
	Assist::Update();
	Perf::Add("upd.Assist", t);
	t = Perf::T0();
	Builder::CommIdleAttribute();
	Builder::SampleTaskHist();
	Builder::PromoteAssistBots();
	Builder::UpdateEconomicCaps();
	Builder::AdvConDiag();
	Builder::ExpandDiag();
	Builder::CancelDoomedRepairs();
	Builder::UpdateSiege();
	Builder::NanoTidy();
	Builder::ObsoleteSweep();
	Builder::ConCensus();
	Perf::Add("upd.BuilderMisc", t);
	Perf::TickSpeed();
	Perf::Flush();
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
	// Binary search: unit ids are handed out monotonically and the ring
	// appends in finish order, so it stays sorted (engine id REUSE after
	// 32k units could break ordering; the ring's own 4096 bound makes that
	// window negligible). The linear walk here ran twice per death and
	// death-heavy battle frames at 12k units were the late-game spikes.
	int lo = 0;
	int hi = int(gFinishedIds.length()) - 1;
	while (lo <= hi) {
		const int mid = (lo + hi) / 2;
		const int v = gFinishedIds[mid];
		if (v == id)
			return true;
		if (v < id)
			lo = mid + 1;
		else
			hi = mid - 1;
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
	Brain::NoteSiloFinished(unit);
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
	double hkT = Perf::T0();
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
	// Finished mobile combat only: nanoframes and builders are not evidence
	// about whether FIGHTING forward is paying.
	if ((cdef !is null) && cdef.IsMobile() && WasFinished(int(unit.id))
		&& (Military::WantsMassing(cdef) || Military::IsFodder(cdef)))
	{
		Military::NoteCombatLoss(cdef.costM, Military::ForwardFraction(at));
	}
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
	Perf::Add("hk.destroyed", hkT);
}

// Attribution arrives on a separate optional callback (the DLL fires it right
// after AiUnitDestroyed, only when the attacker's def is known), so the frozen
// variants' scripts keep their unchanged AiUnitDestroyed. Same combat filter
// as the loss ledger: nanoframes and builders say nothing about the army.
void AiUnitDestroyedBy(CCircuitUnit@ unit, CCircuitDef@ attackerDef)
{
	if ((unit is null) || (attackerDef is null))
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	if ((cdef is null) || !cdef.IsMobile() || !WasFinished(int(unit.id)))
		return;
	if (!Military::WantsMassing(cdef) && !Military::IsFodder(cdef))
		return;
	Military::NoteDeathSource(cdef.costM, attackerDef);
}

// An enemy death we witnessed. byUs is true only when the killer was one of
// OUR OWN units (the event's attacker contract: non-(-1) means allied).
void AiEnemyDestroyed(CCircuitDef@ edef, const AIFloat3& in pos, bool byUs)
{
	if (edef is null)
		return;
	double hkT = Perf::T0();
	Military::NoteEnemyKill(edef.costM, Military::ForwardFraction(pos), byUs);
	Perf::Add("hk.enemydead", hkT);
}

}  // namespace Main
