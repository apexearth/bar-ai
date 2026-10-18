namespace Market {
// THE ADVANCED DEFENCE ROLE (apexearth 2026-10-09: "15 T2 cons... they all are
// instead assisting each other on mex or energy tasks"). Only an advanced hand
// can raise an advanced gun, and the home crew's economy filter strips every
// gun from a home advanced hand while any economy want is listed -- so T2 guns
// came only from the field crew. A share of the advanced hands, sized by the
// open gap in advanced defence against the enemy's identified T2+ share, takes
// the best advanced-gun want first and skips the crew and economy hoists while
// it holds the role. The role goes when the gap closes or no such want is offered.
array<bool> gDrOf(32001, false);
array<int> gDrHandMemo;     // per def: -1 unknown, 0 no, 1 builds an advanced gun
array<int> gDrT1Memo;       // per def: -1 unknown, 0 advanced gun, 1 not
int gDrAt = -999999;
int gDrHands = 0;
int gDrHeld = 0;
int gDrQuota = 0;
float gDrNeedM = 0.f;
float gDrGapM = 0.f;
int gDrTaken = 0;
int gDrReleased = 0;
int gDrOrdered = 0;
int gDrOrderedRole = 0;
int gNextDrLog = 0;

bool DrHandDef(int d)
{
	if ((d < 0) || (d > Catalog::gDefCount))
		return false;
	if (int(gDrHandMemo.length()) <= d) {
		const uint was = gDrHandMemo.length();
		gDrHandMemo.resize(Catalog::gDefCount + 1);
		for (uint k = was; k < gDrHandMemo.length(); ++k)
			gDrHandMemo[k] = -1;
	}
	if (gDrHandMemo[d] < 0) {
		const bool t1 = (d < int(Catalog::gT1Hand.length())) && Catalog::gT1Hand[d];
		gDrHandMemo[d] = (!t1 && Catalog::gMobile[d] && HandHasT2Tower(Catalog::gBuildsList[d])) ? 1 : 0;
	}
	return gDrHandMemo[d] > 0;
}

bool DrAdvancedGun(int d)
{
	if ((d < 0) || (d > Catalog::gDefCount))
		return false;
	if (int(gDrT1Memo.length()) <= d) {
		const uint was = gDrT1Memo.length();
		gDrT1Memo.resize(Catalog::gDefCount + 1);
		for (uint k = was; k < gDrT1Memo.length(); ++k)
			gDrT1Memo[k] = -1;
	}
	if (gDrT1Memo[d] < 0)
		gDrT1Memo[d] = (!Catalog::gMobile[d] && (ProtClassOf(d) == PROT_DEF) && !T1Tower(d)) ? 0 : 1;
	return gDrT1Memo[d] == 0;
}

// An advanced gun to raise, or one rising to help.
bool DefRoleWant(Want@ w)
{
	if ((w is null) || (w.def is null) || (w.value <= 0.f))
		return false;
	if ((w.kind == WK_PROTECT) && (w.spotId == PROT_DEF))
		return DrAdvancedGun(int(w.def.id));
	return (w.kind == WK_ASSIST) && DrAdvancedGun(int(w.def.id));
}

bool DefRoleHeld(CCircuitUnit@ unit)
{
	const int id = int(unit.id);
	return (id >= 0) && (id < int(gDrOf.length())) && gDrOf[id];
}

void DefRoleForget(int id)
{
	if ((id >= 0) && (id < int(gDrOf.length())) && gDrOf[id]) {
		gDrOf[id] = false;
		if (gDrHeld > 0)
			--gDrHeld;
		++gDrReleased;
	}
}

// The advanced defence the enemy's identified tier asks for, less what stands
// and what is ordered; the hands it earns are that unmet share of the role
// share of our advanced hands.
void DefRoleCensus()
{
	if (ai.frame - gDrAt < 2 * SECOND)
		return;
	gDrAt = ai.frame;
	gDrHands = 0;
	gDrHeld = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u is null) || u.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
			|| !DrHandDef(int(u.circuitDef.id)))
			continue;
		++gDrHands;
		if (DefRoleHeld(u))
			++gDrHeld;
	}
	gDrNeedM = DefenceTarget() * Military::FoeTierAbove(1);
	float have = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		if (DrAdvancedGun(d))
			have += Catalog::gCostM[d];
	}
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef is null))
			continue;
		const int d = int(t.buildDef.id);
		if (DrAdvancedGun(d))
			have += Catalog::gCostM[d];
	}
	gDrGapM = gDrNeedM - have;
	if (gDrGapM < 0.f)
		gDrGapM = 0.f;
	gDrQuota = 0;
	if ((gDrNeedM > 1.f) && (gDrGapM > 0.f) && (gDrHands > 1)) {
		const float shareK = ai.GetTunable("apex_role_share", TUNE_ROLE_SHARE);
		gDrQuota = GunpCount(int(ceil(float(gDrHands) * shareK * gDrGapM / gDrNeedM)));
	}
}

// Take, keep or release the role; while held, the advanced-gun wants lead the
// list. True when this election is the role's.
bool DefRoleApply(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	const int id = int(unit.id);
	if ((id < 0) || (id >= int(gDrOf.length()))
		|| unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
		|| !DrHandDef(int(unit.circuitDef.id)))
		return false;
	DefRoleCensus();
	bool offered = false;
	for (uint i = 0; (i < ranked.length()) && !offered; ++i)
		offered = DefRoleWant(ranked[i]);
	if (gDrOf[id]) {
		if (!offered || (gDrHeld > gDrQuota)) {
			DefRoleForget(id);
			return false;
		}
	} else {
		if (!offered || (gDrHeld >= gDrQuota) || SoleAdvancedHand(unit))
			return false;
		gDrOf[id] = true;
		++gDrHeld;
		++gDrTaken;
		ConRoleForget(id);
		CrewForget(id);
	}
	uint at = 0;
	for (uint i = 0; i < ranked.length(); ++i) {
		if (!DefRoleWant(ranked[i]))
			continue;
		if (i != at) {
			Want@ w = ranked[i];
			ranked.removeAt(i);
			ranked.insertAt(at, w);
		}
		++at;
	}
	return true;
}

// An executed want: an advanced gun is counted, and a role hand that ended up
// on anything else has left the role.
void DefRoleExecuted(CCircuitUnit@ unit, Want@ w)
{
	const bool gun = (w !is null) && (w.kind == WK_PROTECT) && (w.def !is null)
			&& DrAdvancedGun(int(w.def.id));
	const bool held = DefRoleHeld(unit);
	if (gun) {
		++gDrOrdered;
		if (held)
			++gDrOrderedRole;
	}
	if (held && !DefRoleWant(w))
		DefRoleForget(int(unit.id));
}

void DefRoleLog()
{
	if (ai.frame < gNextDrLog)
		return;
	gNextDrLog = ai.frame + 60 * SECOND;
	DefRoleCensus();
	AiLog(Factory::T() + "apex: defrole t=" + ai.teamId + " t2hands=" + gDrHands
		+ " assigned=" + gDrHeld + " quota=" + gDrQuota
		+ " needM=" + int(gDrNeedM) + " gapM=" + int(gDrGapM)
		+ " t2gunsOrdered=" + gDrOrdered + " byRole=" + gDrOrderedRole
		+ " t2gunsDone=" + gT2GunDone
		+ " taken=" + gDrTaken + " released=" + gDrReleased);
}

}  // namespace Market
