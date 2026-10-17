namespace Market {

// EXPAND FAR (apex_expand_far). A claim is worth its spot's income x P(we hold it), against
// the walk and the hand it risks; no threat bar refuses it.
//   P(open)  = tF / (tF + t)     their next hand reaches the spot tF s from now (rank from their
//              box at a mirrored claim rate + their walk, or a con of theirs we see), ours in t;
//              0 on a spot a seen enemy extractor stands on
//   road     = worst heat / (heat + max(THREAT_MIN, our influence)) over the walk
// Under the switch the hot-spot veto, the death-walk refusal and the 120 s claim kept by a dead
// task stand down; the DLL walks a mex task through a hot road instead of aborting it and hands
// back the asked spot when it is open (apex_expand_far, C++).

const float XF_THREAT_MIN = 1.f;   // the engine's THREAT_MIN: the bar the executor held a road to

bool gXfOn = false;
bool gXfOnRead = false;
bool ExpandFarOn()
{
	if (!gXfOnRead) {
		gXfOnRead = true;
		gXfOn = ai.GetTunable("apex_expand_far", TUNE_EXPAND_FAR) > 0.f;
	}
	return gXfOn;
}

array<float> gXfTF;
array<int> gXfZone;
int gXfAt = -999999;
float gXfRate = 0.f;
int gXfFoeKnown = 0;

int gXfHot = 0, gXfBlocked = 0, gXfClaimed = 0, gXfNoOpen = 0, gXfDeath = 0, gXfFoe = 0;
int gXfReleased = 0, gXfDied = 0;
array<int> gXfExec(3, 0);
float gXfPSum = 0.f, gXfRSum = 0.f;
int gXfBuilt = 0, gXfLost = 0;
int gXfLogAt = 1800;

// 0 our side, 1 the middle, 2 their side: the share of the home-to-their-box walk.
int XfZoneOf(const AIFloat3& in p)
{
	if (!Builder::gHomeSet)
		return 0;
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(box))
		return 0;
	const float dh = p.distance2D(Builder::gHomePos);
	const float db = p.distance2D(box);
	const float f = (dh + db > 1.f) ? dh / (dh + db) : 0.f;
	return (f < 0.42f) ? 0 : ((f > 0.58f) ? 2 : 1);
}

void XfRefresh()
{
	gXfAt = ai.frame;
	CacheSpots();
	const uint n = gAllSpots.length();
	gXfTF.resize(n);
	gXfZone.resize(n);
	gXfFoeKnown = 0;
	for (uint s = 0; s < n; ++s) {
		gXfTF[s] = -1.f;
		gXfZone[s] = XfZoneOf(gAllSpots[s]);
	}
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	const int mex = ClaimExtractDef(false);
	if ((n == 0) || !OnMap(box) || (mex <= 0))
		return;
	if (gSprSpace < 0.f)
		SprSpacing();
	const float v = Military::NrConSpeed();
	const float vF = (v > 1.f) ? v : 1.f;
	const float bp = (Military::gNrConBP > 0.f) ? Military::gNrConBP : 1.f;
	const float cyc = Catalog::gBuildTime[mex] / bp + gSprSpace / vF;
	int foes = int(ai.GetEnemyTeamSize());
	if (foes < 1)
		foes = 1;
	const float hands = float(foes) * (1.f + float(ConsOwnedAny() + ConsInFlightAny()));
	gXfRate = (cyc > 0.1f) ? hands / cyc : 0.f;
	const bool marks = gMsHeld.length() == n;
	array<int> key;
	for (uint s = 0; s < n; ++s) {
		if (marks && (gMsHeld[s] == 2)) {
			gXfTF[s] = 0.f;
			++gXfFoeKnown;
			continue;
		}
		if ((marks && (gMsHeld[s] == 1)) || !OnMap(gAllSpots[s]))
			continue;
		key.insertLast(int(gAllSpots[s].distance2D(box)) * 4096 + int(s));
	}
	key.sortAsc();
	for (uint r = 0; r < key.length(); ++r) {
		const int s = key[r] % 4096;
		const AIFloat3 p = gAllSpots[s];
		float tF = ((gXfRate > 0.f) ? float(r) / gXfRate : 1e6f) + p.distance2D(box) / vF;
		for (uint i = 0; i < gSprFcP.length(); ++i) {
			const int d = gSprFcD[i];
			if ((Catalog::gSpeed[d] <= 0.f) || (Catalog::gBuildPower[d] <= 0.f))
				continue;
			const float ts = gSprFcP[i].distance2D(p) / Catalog::gSpeed[d] + Catalog::gBuildTime[mex] / Catalog::gBuildPower[d];
			if (ts < tF)
				tF = ts;
		}
		gXfTF[s] = tF;
	}
}

void XfEnsure()
{
	if ((ai.frame - gXfAt >= 5 * SECOND) || (gXfTF.length() != gAllSpots.length()))
		XfRefresh();
}

// The chance the spot is still open when our hand, t seconds out, arrives.
float ExpandFarPOpen(int s, float t)
{
	return ExpandFarOn() ? XfPOpen(s, t) : 1.f;
}

float XfPOpen(int s, float t)
{
	XfEnsure();
	if ((s < 0) || (uint(s) >= gXfTF.length()))
		return 1.f;
	const float tF = gXfTF[s];
	if (tF < 0.f)
		return 1.f;
	if (tF <= 0.f)
		return 0.f;
	return tF / (tF + ((t > 0.f) ? t : 0.f));
}

float ExpandFarHeatAt(const AIFloat3& in p)
{
	if (!OnMap(p))
		return 0.f;
	const float h = ai.GetThreatAt(p);
	if (h <= 0.f)
		return 0.f;
	const float infl = ai.GetAllyDefendInflAt(p);
	return h / (h + ((infl > XF_THREAT_MIN) ? infl : XF_THREAT_MIN));
}

float ExpandFarRoadRisk(const AIFloat3& in from, const AIFloat3& in to)
{
	float worst = ExpandFarHeatAt(to);
	if (!OnMap(from))
		return worst;
	for (int k = 1; k <= 3; ++k) {
		const AIFloat3 p = from + (to - from) * (float(k) * 0.25f);
		const float r = ExpandFarHeatAt(p);
		if (r > worst)
			worst = r;
	}
	return worst;
}

void ExpandFarNoteExec(const AIFloat3& in pos, float pOpen, float risk)
{
	const int z = XfZoneOf(pos);
	++gXfExec[uint(z)];
	gXfPSum += pOpen;
	gXfRSum += risk;
}

// A mex task that died before its frame stood: its claim stops hiding the spot.
void ExpandFarTaskGone(IUnitTask@ task, bool done)
{
	if (done || (task is null) || (task.GetBuildType() != Task::BuildType::MEX) || (task.target !is null))
		return;
	++gXfDied;
	if (!ExpandFarOn())
		return;
	const AIFloat3 at = task.GetBuildPos();
	if (!OnMap(at))
		return;
	const int i = LedgerNearest(at);
	if ((i < 0) || (gLExtract[uint(i)] > 0.f))
		return;
	gLSpot.removeAt(uint(i));
	gLPos.removeAt(uint(i));
	gLIncome.removeAt(uint(i));
	gLExtract.removeAt(uint(i));
	gLClaimAt.removeAt(uint(i));
	++gLStamp;
	++gLFreeStamp;
	++gXfReleased;
}

void ExpandFarNoteBuilt() { ++gXfBuilt; }
void ExpandFarNoteLost() { ++gXfLost; }

void ExpandFarUpdate()
{
	if (ai.frame < gXfLogAt)
		return;
	gXfLogAt = ai.frame + 60 * SECOND;
	XfRefresh();
	const uint n = gAllSpots.length();
	array<int> ours(3, 0);
	array<int> team(3, 0);
	array<int> foe(3, 0);
	array<int> open(3, 0);
	array<float> pz(3, 0.f);
	const array<int>@ lidx = LedgerIdx();
	const array<bool>@ allyHeld = AllyHeldSpots();
	const float tRef = (Military::NrConSpeed() > 1.f) ? 1.f / Military::NrConSpeed() : 0.f;
	for (uint s = 0; s < n; ++s) {
		const uint z = uint(gXfZone[s]);
		const int row = (int(s) < int(lidx.length())) ? lidx[s] : -1;
		if ((row >= 0) && (gLExtract[uint(row)] > 0.f))
			++ours[z];
		else if ((s < allyHeld.length()) && allyHeld[s])
			++team[z];
		else if (gXfTF[s] == 0.f)
			++foe[z];
		else {
			++open[z];
			const float t = Builder::gHomeSet ? gAllSpots[s].distance2D(Builder::gHomePos) * tRef : 0.f;
			pz[z] += (gXfTF[s] > 0.f) ? gXfTF[s] / (gXfTF[s] + t) : 1.f;
		}
	}
	array<int> cons(3, 0);
	int hands = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u is null) || u.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;
		++hands;
		if ((u.task is null) || (u.task.GetType() != Task::Type::BUILDER)
				|| (u.task.GetBuildType() != Task::BuildType::MEX))
			continue;
		const AIFloat3 bp = u.task.GetBuildPos();
		if (OnMap(bp))
			++cons[uint(XfZoneOf(bp))];
	}
	const int ex = gXfExec[0] + gXfExec[1] + gXfExec[2];
	string zs = "";
	const array<string> zn = {"own", "mid", "far"};
	for (uint z = 0; z < 3; ++z)
		zs += " " + zn[z] + "=" + ours[z] + "/" + team[z] + "/" + foe[z] + "/" + open[z]
			+ "@" + NnF((open[z] > 0) ? pz[z] / float(open[z]) : 0.f, 2);
	AiLog(Factory::T() + "apex: expand-stat t=" + ai.teamId + " on=" + (ExpandFarOn() ? 1 : 0)
		+ " spots(ours/ally/foe/open@P)" + zs
		+ " rateF=" + NnF(gXfRate * 60.f, 1) + "/m"
		+ " cons=" + cons[0] + "/" + cons[1] + "/" + cons[2] + " of " + hands
		+ " claims=" + gXfExec[0] + "/" + gXfExec[1] + "/" + gXfExec[2]
		+ " P=" + NnF((ex > 0) ? gXfPSum / float(ex) : 0.f, 2) + " risk=" + NnF((ex > 0) ? gXfRSum / float(ex) : 0.f, 2)
		+ " refused hot=" + gXfHot + " blocked=" + gXfBlocked + " claimed=" + gXfClaimed + " noOpen=" + gXfNoOpen
		+ " deathWalk=" + gXfDeath + " foeHeld=" + gXfFoe
		+ " died=" + gXfDied + " released=" + gXfReleased
		+ " built=" + gXfBuilt + " lost=" + gXfLost);
	gXfHot = 0; gXfBlocked = 0; gXfClaimed = 0; gXfNoOpen = 0; gXfDeath = 0; gXfFoe = 0;
	gXfReleased = 0; gXfDied = 0;
	gXfExec[0] = 0; gXfExec[1] = 0; gXfExec[2] = 0;
	gXfPSum = 0.f; gXfRSum = 0.f;
	gXfBuilt = 0; gXfLost = 0;
}

}  // namespace Market
