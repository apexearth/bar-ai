namespace Air {

// FIGHTER COVER (apexearth 2026-09-16): a scout, radar plane or bomber sent
// out alone dies to the first enemy fighter it meets. Held fighters go with
// it on a guard order and are sent home when the guard ends. Strike bombers
// are covered through the election instead (Military hooks, TaskF::Guard).
array<Id> gCoverUnit;
array<Id> gCoverVip;
int gNextCoverWatch = 0;
int gCoverRR = 0;

bool Covering(Id id) { return InList(gCoverUnit, id); }

bool IsFighterDef(int d)
{
	if ((gFighter  !is null) && (int(gFighter.id)  == d)) return true;
	if ((gFighter1 !is null) && (int(gFighter1.id) == d)) return true;
	return false;
}

// What we hold in FIGHTERS alone. The AA role counts every anti-air unit
// together, so 21,000 metal of mobile ground AA read the role as satisfied and
// stopped the fighters being bought -- against 64,634 metal of enemy air that
// went on harassing us unopposed (apexearth 2026-09-23).
float FighterMetalHeld()
{
	float m = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!IsFighterDef(d))
			continue;
		const int have = Catalog::Def(d).count;
		if (have > 0)
			m += float(have) * Catalog::gCostM[d];
	}
	return m;
}

CCircuitUnit@ FighterById(Id id)
{
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter1 : gFighter;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ ws = ai.GetOwnUnitsOfDef(fd, Builder::gHomePos, 0.f);
		if (ws is null)
			continue;
		for (uint i = 0; i < ws.length(); ++i)
			if ((ws[i] !is null) && (ws[i].id == id))
				return ws[i];
	}
	return null;
}

// Enough fighter metal to match the enemy AIR metal along the way (the
// threat map for a plane is mostly ground AA, which no escort answers), and
// never none: the census reads zero exactly when we have not seen their air
// yet, which is when the lone scout dies. Basic fighters go first. An idle
// fighter takes the order whatever it was hovering on; one in a stock AA
// task is pulled out of it (measured: 12 held, 0 sent, scout lost 30 s
// later, while only an empty command queue qualified).
int Cover(CCircuitUnit@ vip, const AIFloat3& in to, const string& in why)
{
	if ((vip is null) || (ai.GetTunable("apex_air_cover", TUNE_AIR_COVER) <= 0.f))
		return 0;
	const AIFloat3 orig = vip.GetPos(ai.frame);
	float need = 0.f;
	for (int i = 0; i <= 6; ++i) {
		const AIFloat3 p = orig + (to - orig) * (float(i) / 6.f);
		if (!OnMap(p))
			continue;
		const float m = ai.GetEnemyAirCostNear(p, 1200.f);
		if (m > need)
			need = m;
	}
	float have = 0.f;
	int sent = 0;
	for (int pass = 0; pass < 2; ++pass) {
		CCircuitDef@ fd = (pass == 0) ? gFighter1 : gFighter;
		if (fd is null)
			continue;
		array<CCircuitUnit@>@ ws = ai.GetOwnUnitsOfDef(fd, orig, 0.f);
		if (ws is null)
			continue;
		for (uint i = 0; i < ws.length(); ++i) {
			if ((sent > 0) && (have >= need))
				break;
			CCircuitUnit@ w = ws[i];
			if ((w is null) || (w.id == vip.id) || InWave(w.id) || Covering(w.id))
				continue;
			IUnitTask@ t = w.task;
			const bool idle = (t is null) || (t.GetType() == Task::Type::IDLE)
					|| (t.GetType() == Task::Type::NIL);
			if (!idle && (t.GetType() != Task::Type::FIGHTER))
				continue;
			// Registered first: the re-election RemoveUnit triggers reads
			// Covering() in HoldsUnit and leaves the fighter without a task.
			gCoverUnit.insertLast(w.id);
			gCoverVip.insertLast(vip.id);
			if (!idle)
				t.RemoveUnit(w);
			w.CmdGuard(vip);
			have += Catalog::gCostM[int(fd.id)];
			++sent;
		}
	}
	AiLog(Factory::T() + "apex: air cover " + why + " " + vip.circuitDef.GetName()
		+ " #" + vip.id + " fighters=" + sent
		+ " needM=" + int(need) + " haveM=" + int(have)
		+ " held=" + HeldFighters());
	return sent;
}

void CoverHome(uint i, const string& in why)
{
	CCircuitUnit@ w = FighterById(gCoverUnit[i]);
	if (w !is null)
		w.CmdMoveTo(Builder::gHomePos);
	AiLog(Factory::T() + "apex: air cover home #" + gCoverUnit[i] + " " + why);
	gCoverUnit.removeAt(i);
	gCoverVip.removeAt(i);
}

// The mission is over: its cover flies home.
void CoverRelease(Id vip, const string& in why)
{
	for (int i = int(gCoverUnit.length()) - 1; i >= 0; --i)
		if (gCoverVip[i] == vip)
			CoverHome(uint(i), why);
}

// A guard order outlives nothing: when the VIP dies the queue empties and the
// fighter hovers wherever that was. Every few seconds, an empty queue means
// home.
void CoverWatch()
{
	if (ai.frame < gNextCoverWatch)
		return;
	gNextCoverWatch = ai.frame + 5 * SECOND;
	for (int i = int(gCoverUnit.length()) - 1; i >= 0; --i) {
		CCircuitUnit@ w = FighterById(gCoverUnit[i]);
		if (w is null) {
			gCoverUnit.removeAt(uint(i));
			gCoverVip.removeAt(uint(i));
			continue;
		}
		if (w.CmdQueueSize() == 0)
			CoverHome(uint(i), "guard ended");
	}
}

// WHAT THE COVER COSTS IN FIGHTERS: the AA role is a pure counter and
// reads zero against an enemy that has shown no air, so a scout flew out
// alone with nothing held. Our own mission aircraft -- scouts, radar
// planes, bombers; air constructors have their own escort ledger -- are
// fighter demand in proportion to their metal, and never under one basic
// fighter while any of them exists. Recomputed every 2 s.
float gCoverDemandM = 0.f;
int gCoverDemandAt = -1;
float CoverDemandM()
{
	if (ai.GetTunable("apex_air_cover", TUNE_AIR_COVER) <= 0.f)
		return 0.f;
	if ((gCoverDemandAt >= 0) && (ai.frame < gCoverDemandAt + 2 * SECOND))
		return gCoverDemandM;
	gCoverDemandAt = ai.frame;
	float m = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || !Catalog::gFlyer[d]
			|| Catalog::gBuilder[d] || IsFighterDef(d)
			|| (Catalog::gAirT[d] > 0.01f))
			continue;
		const int have = Catalog::Def(d).count;
		if (have <= 0)
			continue;
		n += have;
		m += float(have) * Catalog::gCostM[d];
	}
	CCircuitDef@ fd = (gFighter1 !is null) ? gFighter1 : gFighter;
	if ((n > 0) && (fd !is null) && (m < Catalog::gCostM[int(fd.id)]))
		m = Catalog::gCostM[int(fd.id)];
	gCoverDemandM = m;
	return m;
}

// The strike's fighters guard its bombers, one bomber each in turn. Called
// from the election for a wave fighter; null means no bomber is left to guard.
CCircuitUnit@ WaveBomberFor(CCircuitUnit@ fighter)
{
	array<CCircuitUnit@> bombers;
	for (int i = 0; i < 4; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k)
			if ((us[k] !is null) && InWave(us[k].id))
				bombers.insertLast(us[k]);
	}
	if (bombers.length() == 0)
		return null;
	return bombers[uint(gCoverRR++) % bombers.length()];
}

}  // namespace Air
