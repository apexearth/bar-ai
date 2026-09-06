#include "tunables.as"       // EVERY default, in one file -- edit here
#include "../side.as"
#include "../world.as"
#include "perf.as"
#include "manager/grid.as"     // the bucket grid every "what is near here" walk asks
#include "manager/catalog.as"  // def economics + who-builds-what, read once at init
#include "manager/lattice.as"  // the base lattice + its chain-explosion model
#include "targets.as"          // EVERY build ratio, in one file
#include "policy.as"           // ...and every eco THRESHOLD, in this one
#include "manager/brain/budget.as"  // the spend ledger and target split (a sense)
#include "manager/brain/nukes.as"   // the nuke director: volleys, targets, antinuke accounting
#include "manager/brain.as"       // the arbiter: Decide is the only spender (empty market)
#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/role.as"        // the eco/tech role's POLICY, one place
#include "manager/persona.as"     // per-instance identity: biases, never gates
#include "manager/brain/facqueue.as"  // the production executor: every line held silent
#include "manager/brain/market.as"    // the Want market: proposers + pricing (prototype 1)
#include "manager/economy.as"
#include "manager/air.as"
#include "manager/frontline.as"
#include "manager/baseplan.as"
// Watch-game overlays. LAST on purpose: it reads globals from builder, military
// and frontline, and a global must be declared before the line that reads it.
#include "manager/frontline/draw_diag.as"


namespace Main {

void AiMain()
{
	Catalog::Init();
	Lattice::Init();

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

	// THE BEHEMOTH GETS A WIDE BERTH. Its D-gun one-shots whatever walks into
	// range, which flat DPS-derived threat underprices. Scaling the threat
	// kernel makes the threat map hot around every enemy corjugg: squads demand
	// better odds near one and threat-aware paths detour around it. Calibrated
	// by probe (SetThreatKernel(1), read, rescale) because the kernel itself is
	// write-only. Side effect, accepted: def power scales too, so our OWN
	// Behemoths read stronger -- they are chargers and ignore the margin anyway.
	{
		const float mult = ai.GetTunable("apex_behemoth_threat", TUNE_BEHEMOTH_THREAT);
		CCircuitDef@ jugg = ai.GetCircuitDef("corjugg");
		if ((jugg !is null) && (mult > 1.f)) {
			const float t0 = jugg.threat;
			jugg.SetThreatKernel(1.f);
			const float unitK = jugg.threat;
			if ((t0 > 0.f) && (unitK > 0.0001f)) {
				jugg.SetThreatKernel(mult * t0 / unitK);
				AiLog("apex: behemoth berth -- corjugg threat "
					+ formatFloat(t0, "", 0, 0) + " -> "
					+ formatFloat(jugg.threat, "", 0, 0));
			}
		}
	}
}

// PERIODIC JOBS MUST NOT SHARE A PHASE. Every job below re-arms as
// `ai.frame + N * SECOND`, so any two that first fire on the same AiUpdate stay
// locked together for the whole game. Measured 2026-08-31 (Supreme Isthmus
// v2.1, 1v1 cortex, +100%): slow frames landed at frame == 1 (mod 300) -- a
// median gap of 302 frames, exactly 10 seconds, which is what apexearth saw as
// "a noticeable pause in the game" on a 10-second beat. No single job was
// expensive; a dozen 2-5 ms jobs firing on the same frame reached 176 ms.
//
// Their `gNext*` globals are therefore seeded with distinct primes rather than
// 0. That is a phase offset, not a delay: it shifts only the first fire, and
// the separation then persists forever.
void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	// Ahead of the ApexActive gate: a unit walled in by our own buildings is
	// broken in a solo game exactly as it is in a team one, and freeing it is a
	// fix rather than a piece of the team machinery that gate exists for.
	{ double _t = Perf::T0(); Military::UpdateUnblock(); Perf::Add("up.unblock", _t); }
	{ double _t = Perf::T0(); Military::UpdateMoveTests(); Perf::Add("up.movetests", _t); }

	if (!ApexActive())
		return;

	{ double _t = Perf::T0(); Builder::SampleWreckField(); Perf::Add("up.wreck", _t); }
	{ double _t = Perf::T0(); Requests::PeelSurplus(); Perf::Add("up.peel", _t); }
	{ double _t = Perf::T0(); Requests::ConsolidateEnergy(); Perf::Add("up.econsolidate", _t); }
	{ double _t = Perf::T0(); Market::ComSweep(); Perf::Add("up.comsweep", _t); }
	{ double _t = Perf::T0(); Role::Resolve(); Perf::Add("up.role", _t); }
	{ double _t = Perf::T0(); Brain::UpdateFacQueues(); Perf::Add("up.facqueue", _t); }
	{ double _t = Perf::T0(); Brain::LogFacQueues(); Perf::Add("up.facqueuelog", _t); }
	{ double _t = Perf::T0(); Military::UpdateLanePos(); Perf::Add("up.lanepos", _t); }
	{ double _t = Perf::T0(); Military::UpdateDeathLedger(); Perf::Add("up.deathledger", _t); }
	{ double _t = Perf::T0(); Military::UpdateWithdraw(); Perf::Add("up.withdraw", _t); }
	{ double _t = Perf::T0(); Military::UpdateGifts(); Perf::Add("up.gifts", _t); }
	{ double _t = Perf::T0(); Air::UpdateFighterStations(); Perf::Add("up.airstations", _t); }
	{ double _t = Perf::T0(); Air::RecycleOldFighters(); Perf::Add("up.airrecycle", _t); }
	{ double _t = Perf::T0(); Brain::UpdateNukes(); Perf::Add("up.nukes", _t); }
	{ double _t = Perf::T0(); Market::NanoReclaimAssist(); Perf::Add("up.nanorec", _t); }
	{ double _t = Perf::T0(); Military::UpdateSpamPosture(); Perf::Add("up.spamposture", _t); }
	{ double _t = Perf::T0(); Military::UpdatePosture(); Perf::Add("up.posture", _t); }
	{ double _t = Perf::T0(); Air::Update(); Perf::Add("up.air", _t); }
	{ double _t = Perf::T0(); Air::ScoutOverflight(); Perf::Add("up.overfly", _t); }
	{ double _t = Perf::T0(); Front::Update(); Perf::Add("up.front", _t); }
	{ double _t = Perf::T0(); Market::ChokeUpdate(); Perf::Add("up.choke", _t); }
	{ double _t = Perf::T0(); Market::LogFrontTowers(); Perf::Add("up.fronttowers", _t); }
	Market::IncomeMultProbe();   // once, ~30s in: is the handicap binding real
	{ double _t = Perf::T0(); Brain::Think(); Perf::Add("up.think", _t); }
	{ double _t = Perf::T0(); Base::Update(); Perf::Add("up.base", _t); }
	{ double _t = Perf::T0(); Lattice::Update(); Perf::Add("up.lattice", _t); }
	// The two instruments: which gates in the request chokepoint are ever
	// reached, and what the live fighter pools actually are. Both self-rate to
	// one line a game-minute, so the last one is the game-end census.
	{ double _t = Perf::T0(); Requests::GateCensus(); Perf::Add("up.gatecensus", _t); }
	{ double _t = Perf::T0(); Military::UpdateRaidAsk(); Perf::Add("up.raidask", _t); }
	{ double _t = Perf::T0(); Military::FightCensus(); Military::ElectCensus(); Perf::Add("up.fightcensus", _t); }
	{ double _t = Perf::T0(); Military::UpdateGuardPosts(); Perf::Add("up.guardposts", _t); }
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
// Per-id flag, NOT a sorted ring: the engine hands unit ids out of a free
// list, so they are not monotonic and a binary-searched append-order ring
// missed nearly every lookup -- measured 2026-08-19, built=0 on 165/173
// mobile combat deaths, which silently starved the whole loss-feedback stack
// (bleed caution, trade ratio, loss-driven army budget). Spring ids are hard-
// capped at 32k, so a flat flag array is exact and O(1). The flag is cleared
// one death-event late (gFinishedClearPending) because AiUnitDestroyedBy
// fires right after AiUnitDestroyed and reads it too.
array<bool> gFinished(32001, false);
int gFinishedClearPending = -1;

bool WasFinished(int id)
{
	return (id >= 0) && (id < int(gFinished.length())) && gFinished[id];
}

void AiUnitFinished(CCircuitUnit@ unit)
{
	const double _t = Perf::T0();
	UnitFinishedInner(unit);
	Perf::Add("hk.finished", _t);
}

void UnitFinishedInner(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	Brain::NoteProduced(unit);
	Market::NoteFinished(unit);
	Market::ComUnitFinished(unit);
	Market::NoteFarm(unit);
	Brain::NoteSiloFinished(unit);
	if ((int(unit.id) >= 0) && (int(unit.id) < int(gFinished.length())))
		gFinished[int(unit.id)] = true;
	// A tower that actually FINISHED on the front line. The defsite counters are
	// auction wins, which a killed builder or a blocked site never turns into a
	// standing gun.
	if ((unit.circuitDef !is null) && !unit.circuitDef.IsMobile()
		&& (Market::ProtClassOf(int(unit.circuitDef.id)) == Market::PROT_DEF))
	{
		Market::NoteTowerBuilt(unit.GetPos(ai.frame), unit.circuitDef.costM);
	}
	// The defense zone follows the BUILT base: every finished rear structure
	// can stretch the ring, forward fences and mex guards never do (a front
	// tower at fwd 0.6 must not turn half the map into fight-at-any-odds
	// ground -- that oversized ring is the streaming-deaths mechanism
	// apexearth identified watching the overlay).
	if ((unit.circuitDef !is null) && !unit.circuitDef.IsMobile()
		&& Builder::gHomeSet)
	{
		const AIFloat3 sp = unit.GetPos(ai.frame);
		if (Military::ForwardFraction(sp) < 0.35f) {
			const float dEx = sp.distance2D(Builder::gHomePos);
			if (dEx > Military::gBaseExtent)
				Military::gBaseExtent = dEx;
		}
	}
}

// CInitScript::UnitDestroyed (InitScript.cpp:1224) looks this exact signature
// up and calls it for every one of OUR units destroyed, across all managers --
// it was simply never implemented, which is the "AiUnitDestroyed ... not
// found!" warning at every match start. Task history is builder-crew only;
// see Builder::SampleTaskHist/TakeHistFor in manager/builder/events.as.
void AiUnitDestroyed(CCircuitUnit@ unit)
{
	Market::NoteDead(unit);
	if (unit is null)
		return;
	Market::ComUnitDead(unit);
	// The PREVIOUS death's flag is cleared now, so this id can be reused
	// cleanly, while AiUnitDestroyedBy (which follows this call) still read it.
	if ((gFinishedClearPending >= 0)
		&& (gFinishedClearPending < int(gFinished.length()))
		&& (gFinishedClearPending != int(unit.id)))
	{
		gFinished[gFinishedClearPending] = false;
	}
	gFinishedClearPending = int(unit.id);
	double hkT = Perf::T0();
	const CCircuitDef@ cdef = unit.circuitDef;
	const AIFloat3 at = unit.GetPos(ai.frame);
	IUnitTask@ t = unit.task;
	const int tt = (t is null) ? -1 : t.GetType();
	const int bt = ((t !is null) && (tt == Task::Type::BUILDER)) ? t.GetBuildType() : -1;
	// The fight type IS "the last major action" for a combat unit -- attack,
	// defend, raid, retreat all leave a distinct value here -- and the forward
	// fraction says WHERE it died (0 home, 1 at the enemy). tools/deaths.py
	// aggregates these lines into metal-lost-by-last-action.
	const int ft = ((t !is null) && (tt == Task::Type::FIGHTER)) ? t.GetFightType() : -1;
	// Finished mobile combat only: nanoframes and builders are not evidence
	// about whether FIGHTING forward is paying.
	if ((cdef !is null) && cdef.IsMobile() && WasFinished(int(unit.id))
		&& (Military::WantsMassing(cdef) || Military::IsFodder(cdef)))
	{
		Military::NoteCombatLoss(cdef.costM, Military::ForwardFraction(at));
		Military::NoteLocalDeath(at, cdef.costM, true);
	}
	// OUR COMMANDER'S CORPSE IS A RESURRECTION JOB, not food (apexearth:
	// "make sure we resurrect our commanders instead of reclaiming them").
	// Publish where it fell so every ally's rez bots can race to it -- the
	// ReclaimTask filter refuses to eat *com_dead either way, and an active
	// resurrect marks the area so area reclaims steer off it.
	if ((cdef !is null) && cdef.IsRoleAny(Unit::Role::COMM.mask) && OnMap(at)) {
		ai.PublishTeamValue("comwx", at.x);
		ai.PublishTeamValue("comwz", at.z);
		ai.PublishTeamValue("comwf", float(ai.frame));
		AiLog("apex: commander fell t=" + ai.teamId
			+ " at=" + int(at.x) + "," + int(at.z)
			+ " -- corpse published for resurrection");
	}
	// A BUILDING OF OURS DYING ON OUR OWN GROUND IS THE INVASION SIGNAL.
	// Filtered out of the combat ledger above (mobile only) and read by nothing
	// else, so an enemy could level the base without any defence rule noticing.
	if ((cdef !is null) && !cdef.IsMobile() && WasFinished(int(unit.id))) {
		Military::NoteStructureLoss(at, cdef.costM);
		// The same death, kept by PLACE and with no home-ground filter: the
		// ledger above drops everything past FWD_HOME, which is where the
		// outlying mexes die.
		Market::NoteEcoLoss(at, cdef.costM);
		if (Market::ProtClassOf(int(cdef.id)) == Market::PROT_DEF)
			Market::NoteTowerLost(at);
	}
	const string hist = Builder::TakeHistFor(int(unit.id));
	AiLog(Factory::T() + "apex: unit-destroyed " + ((cdef !is null) ? cdef.GetName() : "?")
		+ " acts=" + unit.GetActTrace()
		+ " id=" + unit.id + " frame=" + ai.frame
		+ " at=" + int(at.x) + "," + int(at.z)
		+ " curTask=t" + tt + "b" + bt + "f" + ft
		+ " cost=" + int((cdef !is null) ? cdef.costM : 0.f)
		+ " fwd=" + formatFloat(Military::ForwardFraction(at), "", 0, 2)
		+ " built=" + (WasFinished(int(unit.id)) ? 1 : 0)
		+ " mob=" + (((cdef !is null) && cdef.IsMobile()) ? 1 : 0)
		+ " hist=[" + hist + "]"
		+ " fhist=[" + Military::TakeFightHistFor(int(unit.id)) + "]");
	Perf::Add("hk.destroyed", hkT);
}

// Attribution arrives on a separate optional callback (the DLL fires it right
// after AiUnitDestroyed, only when the attacker's def is known), so the frozen
// variants' scripts keep their unchanged AiUnitDestroyed. Same combat filter
// as the loss ledger: nanoframes and builders say nothing about the army.
void AiUnitDestroyedBy(CCircuitUnit@ unit, CCircuitDef@ attackerDef)
{
	const double _t = Perf::T0();
	UnitDestroyedByInner(unit, attackerDef);
	Perf::Add("hk.destroyedby", _t);
}

void UnitDestroyedByInner(CCircuitUnit@ unit, CCircuitDef@ attackerDef)
{
	if ((unit is null) || (attackerDef is null))
		return;
	// The tier census FIRST: it is about what THEY field, so it must not sit
	// behind the filters that ask what WE lost.
	Military::NoteFoeDef(attackerDef.costM, attackerDef);
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
	Military::NoteFoeDef(edef.costM, edef);
	double hkT = Perf::T0();
	Military::NoteEnemyKill(edef.costM, Military::ForwardFraction(pos), byUs);
	Military::NoteLocalDeath(pos, edef.costM, false);
	if (byUs)
		Market::LossNote(int(edef.id));   // their wreck is rez work too
	Perf::Add("hk.enemydead", hkT);
}

}  // namespace Main
