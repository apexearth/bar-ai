namespace Military {

// GATHER, THEN GO (his 2026-10-16). A raid pack's members are fixed when it launches: nnraid prices the
// pack in the field and the raiders gathered at home as two groups, never one, so a GO launches the gathered
// group whole as a new pack and nothing walks out alone to a pack already in contact. A pack sent home is
// dissolved there into the gathering pools. C++ (apex_gather): pools never walk out to a launched squad, an
// all-raider pool never promotes itself, a goal pack takes no recruits and paths around what beats it.

bool GthOn() { return ai.GetTunable("apex_gather", TUNE_GATHER) > 0.f; }

int gGthMode = 1;            // the group nnraid is pricing: 0 the live pack alone, 1 the gathered raiders
bool gGthQueue1 = false;
bool gGthWait = false;       // the gathered group's last decision was WAIT
array<int> gGthRoster;       // the live pack's members at launch

array<IUnitTask@> gGthOutT;  // launched packs no longer nnraid's handle
array<AIFloat3> gGthOutGoal;
array<float> gGthOutR;
array<bool> gGthOutHome;
array<array<int>> gGthOutRoster;

int gGthTickAt = 0;
int gGthLaunchAt = -999999;
int gGthLogAt = 0;
int gGthGathered = 0;
array<int> gGthLaunchBy(4, 0);
float gGthMarginSum = 0.f;
int gGthMarginN = 0;
int gGthArmedIn = 0;         // launches at a target with armed enemies counted in reach (predicted won)
int gGthAlone = 0;           // ...of them, one or two units
int gGthDevGo = 0;           // launches the net chose against a predicted loss
int gGthHeld = 0;            // gathered raiders held while a pack was out
int gGthLate = 0;            // units in a launched pack that were not in it at launch
int gGthRegoal = 0;
array<int> gGthDeathBy(4, 0);
array<float> gGthDeathM(4, 0.f);
array<int> gGthArmyS(6, 0);  // chosen targets by their nearest armed mobile's arrival: <15,<30,<60,<120,120+ s, none
int gGthDissolved = 0, gGthRetired = 0, gGthWaitN = 0, gGthGoN = 0;

int GthSizeBin(int n)
{
	return (n <= 1) ? 0 : ((n == 2) ? 1 : ((n <= 5) ? 2 : 3));
}

bool GthIsOut(IUnitTask@ t)
{
	return gGthOutT.findByRef(t) >= 0;
}

void GthRetire(bool launch = true)
{
	if ((gAskTask is null) || gAskTask.IsDead())
		return;
	gGthOutT.insertLast(gAskTask);
	gGthOutGoal.insertLast(gNrGoal);
	gGthOutR.insertLast(gNrGoalR);
	gGthOutHome.insertLast(gNrGoalHome);
	gGthOutRoster.insertLast(gGthRoster);
	@gAskTask = null;
	gGthRoster.resize(0);
	if (launch)
		++gGthRetired;
}

void GthOutRemove(uint i)
{
	gGthOutT.removeAt(i);
	gGthOutGoal.removeAt(i);
	gGthOutR.removeAt(i);
	gGthOutHome.removeAt(i);
	gGthOutRoster.removeAt(i);
}

// Every pack out is priced in turn: the oldest becomes nnraid's handle for this clock, the current one goes
// to the back. Never while a launch's claimed units are still on their way to their new pack.
void GthRotate()
{
	if (ai.frame - gGthLaunchAt < 10 * SECOND)
		return;
	for (int i = int(gGthOutT.length()) - 1; i >= 0; --i) {
		if ((gGthOutT[i] is null) || gGthOutT[i].IsDead())
			GthOutRemove(uint(i));
	}
	if (gGthOutT.length() == 0)
		return;
	IUnitTask@ t = gGthOutT[0];
	const AIFloat3 g = gGthOutGoal[0];
	const float r = gGthOutR[0];
	const bool h = gGthOutHome[0];
	array<int> ros = gGthOutRoster[0];
	GthOutRemove(0);
	GthRetire(false);
	@gAskTask = t;
	gNrGoal = g;
	gNrGoalR = r;
	gNrGoalHome = h;
	gNrGoalHas = true;
	gGthRoster = ros;
}

// a gathered-group decision: n raiders, launched or held
void GthNoteGathered(int n, bool go, bool live)
{
	gGthGathered = n;
	if (go)
		++gGthGoN;
	else
		++gGthWaitN;
	if (!go && live)
		gGthHeld += n;
}

void GthNoteLaunch(int n, float netM, float grpM, bool armed, float tArr, bool predLoss)
{
	gGthLaunchAt = ai.frame;
	++gGthLaunchBy[GthSizeBin(n)];
	if (grpM > 0.f) {
		gGthMarginSum += netM / grpM;
		++gGthMarginN;
	}
	if (armed) {
		++gGthArmedIn;
		if (n <= 2)
			++gGthAlone;
	}
	if (predLoss)
		++gGthDevGo;
	const int b = (tArr < 0.f) ? 5 : ((tArr < 15.f) ? 0 : ((tArr < 30.f) ? 1 : ((tArr < 60.f) ? 2 : ((tArr < 120.f) ? 3 : 4))));
	++gGthArmyS[b];
}

int GthCountLate(IUnitTask@ t, array<int>& roster)
{
	array<CCircuitUnit@>@ on = t.GetUnits();
	if ((on is null) || (roster.length() == 0))
		return 0;
	int late = 0;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] is null) || (roster.find(int(on[i].id)) >= 0))
			continue;
		roster.insertLast(int(on[i].id));
		++late;
	}
	return late;
}

bool GthNear(IUnitTask@ t, const AIFloat3& in at, float r, bool all)
{
	array<CCircuitUnit@>@ on = t.GetUnits();
	if ((on is null) || (on.length() == 0))
		return false;
	for (uint i = 0; i < on.length(); ++i) {
		if (on[i] is null)
			continue;
		const bool inR = on[i].GetPos(ai.frame).distance2D(at) <= r;
		if (all && !inR)
			return false;
		if (!all && inR)
			return true;
	}
	return all;
}

void GthDissolve(IUnitTask@ t)
{
	array<CCircuitUnit@>@ on = t.GetUnits();
	if (on is null)
		return;
	for (uint i = 0; i < on.length(); ++i) {
		if (on[i] !is null)
			t.RemoveUnit(on[i]);
	}
	++gGthDissolved;
}

// once a second: late joiners, packs home dissolved, retired packs that cleared their goal sent home
void GthTick()
{
	if (!Builder::gHomeSet)
		return;
	const float homeR = gNrHomeR * 1.5f;
	if (NrLive()) {
		gGthLate += GthCountLate(gAskTask, gGthRoster);
		if (gNrGoalHome && GthNear(gAskTask, Builder::gHomePos, homeR, true)) {
			GthDissolve(gAskTask);
			@gAskTask = null;
			gGthRoster.resize(0);
			gNrGoalHas = false;
		}
	}
	for (int i = int(gGthOutT.length()) - 1; i >= 0; --i) {
		IUnitTask@ t = gGthOutT[i];
		bool drop = (t is null) || t.IsDead();
		if (!drop) {
			gGthLate += GthCountLate(t, gGthOutRoster[i]);
			if (!gGthOutHome[i] && GthNear(t, gGthOutGoal[i], gGthOutR[i], false)
				&& (aiEnemyMgr.GetEnemyStructCostAt(gGthOutGoal[i], gGthOutR[i]) <= 1.f)) {
				gGthOutHome[i] = true;
				t.SetRaidGoal(Builder::gHomePos, gNrHomeR);
			}
			if (GthNear(t, Builder::gHomePos, homeR, true)) {
				GthDissolve(t);
				drop = true;
			}
		}
		if (drop)
			GthOutRemove(uint(i));
	}
}

// our ground fighter died: how many of ours stood within 400 of it
void GthNoteDeath(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null))
		return;
	const CCircuitDef@ cdef = unit.circuitDef;
	const int d = int(cdef.id);
	if (!cdef.IsMobile() || cdef.IsAbleToFly() || Catalog::gBuilder[d] || (cdef.power <= 1.f))
		return;
	const AIFloat3 at = unit.GetPos(ai.frame);
	int n = 1;
	for (uint i = 0; i < gCombatId.length(); ++i) {
		if (gCombatId[i] == int(unit.id))
			continue;
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		if (u.GetPos(ai.frame).distance2D(at) <= 400.f)
			++n;
	}
	const int b = GthSizeBin(n);
	++gGthDeathBy[b];
	gGthDeathM[b] += cdef.costM;
}

void GthLog()
{
	if (ai.frame < gGthLogAt)
		return;
	gGthLogAt = ai.frame + 60 * SECOND;
	int outN = 0;
	for (uint i = 0; i < gGthOutT.length(); ++i) {
		if ((gGthOutT[i] is null) || gGthOutT[i].IsDead())
			continue;
		array<CCircuitUnit@>@ on = gGthOutT[i].GetUnits();
		if (on !is null)
			outN += int(on.length());
	}
	int liveN = 0;
	if (NrLive())
		liveN = int(gAskTask.GetUnits().length());
	AiLog(Factory::T() + "apex: gather-stat t=" + ai.teamId + " on=" + (GthOn() ? 1 : 0)
		+ " gathering=" + gGthGathered + " live=" + liveN
		+ " outPacks=" + gGthOutT.length() + " outN=" + outN
		+ " | dec go=" + gGthGoN + " wait=" + gGthWaitN
		+ " launched 1:" + gGthLaunchBy[0] + " 2:" + gGthLaunchBy[1] + " 3-5:" + gGthLaunchBy[2] + " 6+:" + gGthLaunchBy[3]
		+ " margin=" + ((gGthMarginN > 0) ? formatFloat(gGthMarginSum / float(gGthMarginN), "", 0, 2) : "-")
		+ " armedIn=" + gGthArmedIn + " small=" + gGthAlone + " devGo=" + gGthDevGo
		+ " held=" + gGthHeld + " late=" + gGthLate + " regoal=" + gGthRegoal
		+ " retired=" + gGthRetired + " dissolved=" + gGthDissolved
		+ " | armyS <15:" + gGthArmyS[0] + " <30:" + gGthArmyS[1] + " <60:" + gGthArmyS[2] + " <120:" + gGthArmyS[3]
		+ " 120+:" + gGthArmyS[4] + " none:" + gGthArmyS[5]
		+ " | deaths 1:" + gGthDeathBy[0] + "/" + int(gGthDeathM[0]) + " 2:" + gGthDeathBy[1] + "/" + int(gGthDeathM[1])
		+ " 3-5:" + gGthDeathBy[2] + "/" + int(gGthDeathM[2]) + " 6+:" + gGthDeathBy[3] + "/" + int(gGthDeathM[3]));
	for (uint k = 0; k < 4; ++k) {
		gGthLaunchBy[k] = 0;
		gGthDeathBy[k] = 0;
		gGthDeathM[k] = 0.f;
	}
	for (uint k = 0; k < 6; ++k)
		gGthArmyS[k] = 0;
	gGthMarginSum = 0.f;
	gGthMarginN = gGthArmedIn = gGthAlone = gGthDevGo = gGthHeld = gGthLate = gGthRegoal = 0;
	gGthRetired = gGthDissolved = gGthGoN = gGthWaitN = 0;
}

void UpdateGather()
{
	if (StockQuiet("gather"))
		return;
	if (!ApexActive())
		return;
	if (GthOn() && (ai.frame >= gGthTickAt)) {
		gGthTickAt = ai.frame + SECOND;
		GthTick();
	}
	GthLog();
}

}  // namespace Military
