#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"
#include "../task.as"


namespace Main {

//------------------------------------------------------------------------------
// apex2
//
// Drives CircuitAI's existing machinery through the script API rather than
// replacing it. Every binding used here is registered in
// CircuitAI/src/circuit/script/MilitaryScript.cpp (see vendor/circuitai).
//------------------------------------------------------------------------------

// Scouting. Stock quota is 2. Scouts are cheap, and their vision cannot be
// denied by radar jammers the way the radar picture can. Ramp instead of
// starting high so the opening is not starved of real units.
const uint SCOUT_OPENING = 12;
const uint SCOUT_MID     = 26;
const int  SCOUT_RAMP_AT = 8 * MINUTE;

// Anti-air is handled statically in response.json (ratio 0.75 -> 1.6,
// max_percent 0.50 -> 0.75). Doing it dynamically from here would need
// SResponseInfo, which is not a visible data type in main.as's module scope --
// the managers register their types against their own module namespaces.

// All-in. CircuitAI commits to an attack once enough army exists
// (quota.attack == minAttackers). Temporarily collapsing that threshold makes
// the army commit in one mass rather than trickling in -- trickling is the
// failure mode a human exploits by defeating each wave in detail.
const float ALLIN_ARMY_FLOOR = 6000.f;   // armyCost before an all-in is considered
const float ALLIN_ATTACK_LOW = 2.f;      // minAttackers while committed
const int   ALLIN_DURATION   = 90 * SECOND;
const int   ALLIN_COOLDOWN   = 4 * MINUTE;
const int   ALLIN_EARLIEST   = 6 * MINUTE;

float gAttackQuotaBase = -1.f;
bool  gAllIn           = false;
int   gAllInEnds       = 0;
int   gAllInNextAt     = 0;
int   gAllInCount      = 0;

void AiMain()
{
	// --- stock behaviour, preserved verbatim ----------------------------
	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
		if (cdef.costM >= 200.f && !cdef.IsMobile() && aiEconomyMgr.GetEnergyMake(cdef) > 1.f)
			cdef.AddAttribute(Unit::Attr::BASE.type);  // Build heavy energy at base
	}

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

	// --- apex2 additions -------------------------------------------------
	gAttackQuotaBase = aiMilitaryMgr.quota.attack;
	gAllInNextAt = ALLIN_EARLIEST;
	aiMilitaryMgr.quota.scout = SCOUT_OPENING;

	AiLog("apex2 init: attackQuota=" + gAttackQuotaBase + " scoutQuota=" + SCOUT_OPENING);
}

void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	UpdateScouting();
	UpdateAllIn();
}

void UpdateScouting()
{
	uint want = (ai.frame < SCOUT_RAMP_AT) ? SCOUT_OPENING : SCOUT_MID;
	if (aiMilitaryMgr.quota.scout != want)
		aiMilitaryMgr.quota.scout = want;
}

void UpdateAllIn()
{
	if (gAllIn) {
		if (ai.frame >= gAllInEnds) {
			gAllIn = false;
			aiMilitaryMgr.quota.attack = gAttackQuotaBase;
			AiLog("apex2: all-in #" + gAllInCount + " ended");
		}
		return;
	}

	if ((ai.frame < gAllInNextAt) || (aiMilitaryMgr.armyCost < ALLIN_ARMY_FLOOR))
		return;

	gAllIn = true;
	++gAllInCount;
	gAllInEnds = ai.frame + ALLIN_DURATION;
	gAllInNextAt = ai.frame + ALLIN_COOLDOWN;
	// Lowering minAttackers is the whole lever: CMilitaryManager forms its own
	// CAttackTask against this threshold, so the army commits en masse instead
	// of trickling. Do NOT also call Enqueue(TaskF::Common(ATTACK)) -- that
	// crashed the AI ~3 frames later in 4 of 12 round-1 matches.
	aiMilitaryMgr.quota.attack = ALLIN_ATTACK_LOW;

	AiLog("apex2: ALL-IN #" + gAllInCount + " frame=" + ai.frame
		+ " armyCost=" + aiMilitaryMgr.armyCost);
}

}  // namespace Main
