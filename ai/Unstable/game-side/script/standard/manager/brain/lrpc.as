namespace Brain {

// THE BATTERY FIRES AS ONE (apex_lrpc_focus; his 10-23: "When we make LRPC its kinda like nukes, we should have them
// all focusing specific enemy areas which we want to defeat"; "sometimes switching targets fully and suddenly will
// catch someone else off-guard"). Each gun used to shoot whatever the engine picked in its reach. Every 10 s the
// enemy buildings we know of (seen or remembered), and armies on our half, are summed per 256-elmo cell; a cell is
// worth its metal times the guns of ours that reach it, and every gun in reach of the chosen cell is ordered onto it.
// The battery holds the
// cell until it is spent (half its value gone) or another is worth half again as much, then moves whole.

const float LR_CELL = 256.f;
AIFloat3 gLrFocus;
bool gLrHave = false;
float gLrFocusV0 = 0.f;    // the cell's metal when chosen
int gLrSerial = 0;         // bumped on every switch
array<int> gLrOrdered;     // gun ids ordered onto the current focus
array<int> gLrTarget;      // ...and the enemy id each was given (parallel)
int gLrNextAt = 0;

// An army on our half is a target, at its metal like a building (his 11-15: "if our artillery can severely damage an
// attacking army they should ... if the enemy is encroaching, sick the lrpc on them"). Seen or on radar now only.
bool LrWorth(int d, int los, const AIFloat3& in p)
{
	if (!Catalog::gMobile[d])
		return true;
	if (Catalog::gFlyer[d] || (Catalog::gSurfT[d] <= 0.01f) || ((los & (1 | 2)) == 0))
		return false;
	return Military::ForwardFraction(p) < 0.5f;
}

// hand every held gun back to its own aim (CSuperTask)
void LrLetGo(array<CCircuitUnit@>@ guns, bool stop)
{
	for (uint g = 0; g < guns.length(); ++g) {
		if (gLrOrdered.find(int(guns[g].id)) < 0)
			continue;
		if (stop)
			guns[g].CmdStop();
		guns[g].SetScriptFree(false);
	}
	gLrOrdered.resize(0);
	gLrTarget.resize(0);
}

bool LrpcFocusOn()
{
	return ai.GetTunable("apex_lrpc_focus", TUNE_LRPC_FOCUS) > 0.f;
}

void UpdateLrpc()
{
	if (!LrpcFocusOn() || (ai.frame < gLrNextAt))
		return;
	gLrNextAt = ai.frame + 10 * SECOND;
	// our guns
	array<CCircuitUnit@> guns;
	array<float> reach;
	float splash = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::ValidId(d) || Catalog::gMobile[d] || (Market::SuperClassOf(d) != Market::SC_LRPC))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), Builder::gHomePos, 0.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if (us[k] is null)
				continue;
			guns.insertLast(us[k]);
			reach.insertLast(Catalog::gMaxRange[d]);
			if (Catalog::gAoe[d] * 1.25f > splash)
				splash = Catalog::gAoe[d] * 1.25f;
		}
	}
	if (guns.length() == 0)
		return;
	// their buildings, per cell
	const int cols = int(AiTerrainWidth() / LR_CELL) + 1;
	const int rows = int(AiTerrainHeight() / LR_CELL) + 1;
	array<float> cm(cols * rows, 0.f), cam(cols * rows, 0.f), cx(cols * rows, 0.f), cz(cols * rows, 0.f), cr(cols * rows, 0.f);
	array<int> used;
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if (!OnMap(p) || !LrWorth(d, los, p))
			continue;
		const int c = int(p.x / LR_CELL) + cols * int(p.z / LR_CELL);
		if ((c < 0) || (c >= cols * rows))
			continue;
		if (cm[c] <= 0.f)
			used.insertLast(c);
		const float m = Catalog::gCostM[d];
		cm[c] += m;
		if (Catalog::gMobile[d]) {
			cam[c] += m;
			const float walk = Catalog::gMaxRange[d] + Catalog::gSpeed[d] * 10.f;
			if (walk > cr[c])
				cr[c] = walk;
		}
		cx[c] += p.x * m;
		cz[c] += p.z * m;
	}
	// the best cell, and the current focus's standing
	float bestS = 0.f, bestV = 0.f, bestA = 0.f, curS = 0.f, curV = 0.f;
	int bestN = 0, curN = 0;
	AIFloat3 bestAt;
	const int curC = gLrHave ? (int(gLrFocus.x / LR_CELL) + cols * int(gLrFocus.z / LR_CELL)) : -1;
	for (uint u = 0; u < used.length(); ++u) {
		const int c = used[u];
		const AIFloat3 at(cx[c] / cm[c], 0.f, cz[c] / cm[c]);
		int n = 0;
		for (uint g = 0; g < guns.length(); ++g)
			if (guns[g].GetPos(ai.frame).distance2D(at) <= reach[g])
				++n;
		// an army is also worth what of ours it reaches before the next look (its reach plus ten seconds' walk), up to
		// its own metal: it trades about at par before it is stopped, so a lone raider near a rich base does not borrow
		// the base's value (review 11-16) (lrpc_army: 16 Hammers walked into four Berthas while the battery broke fusions)
		float threat = 0.f;
		if (cam[c] > 0.f) {
			threat = Market::StakeAt(at, cr[c]);
			if (threat > cam[c])
				threat = cam[c];
		}
		const float v = cm[c] + threat;
		const float s = v * float(n);
		if (c == curC) {
			curS = s;
			curV = v;
			curN = n;
		}
		if (s > bestS) {
			bestS = s;
			bestV = v;
			bestA = cam[c];
			bestN = n;
			bestAt = at;
		}
	}
	string why = "";
	if (!gLrHave && (bestS > 0.f))
		why = "first";
	else if (gLrHave && ((curN == 0) || (curV < 0.5f * gLrFocusV0)) && (bestS > 0.f))
		why = (curV <= 0.f) ? "spent" : ((curN == 0) ? "out-of-reach" : "spent");
	else if (gLrHave && (bestS >= 1.5f * curS) && (bestS > 0.f))
		why = "better";
	if (why != "") {
		LrLetGo(guns, false);
		gLrFocus = bestAt;
		gLrFocus.y = ai.GetElevationAt(gLrFocus);
		gLrHave = true;
		gLrFocusV0 = bestV;
		++gLrSerial;
		AiLog(Factory::T() + "apex: lrpc-focus t=" + ai.teamId + " guns=" + bestN + "/" + guns.length()
			+ " at=" + int(bestAt.x) + "," + int(bestAt.z) + " value=" + int(bestV) + " army=" + int(bestA) + " why=" + why
			+ " was=" + int(curV) + "/" + int(gLrFocusV0));
	} else if (gLrHave && (bestS <= 0.f)) {
		gLrHave = false;   // nothing of theirs left in reach: the guns pick their own targets again
		LrLetGo(guns, true);
		AiLog(Factory::T() + "apex: lrpc-focus t=" + ai.teamId + " released");
		return;
	}
	if (!gLrHave)
		return;
	// an army walks out of a gun's order between looks; while one is the focus, look every 3 s (review 11-16)
	const int fc = int(gLrFocus.x / LR_CELL) + cols * int(gLrFocus.z / LR_CELL);
	if ((fc >= 0) && (fc < cols * rows) && (cam[fc] > 0.f))
		gLrNextAt = ai.frame + 3 * SECOND;
	// AIM AT THE BUILDINGS, NOT THE CELL: ground fire at its centre of mass splashed between them (lrpc_focus: fusions
	// at 11/23/23 s against 10/10/11 s for the engine's own picks). The cell's buildings, dearest first; each gun in
	// reach takes the next one, kept until it dies.
	array<int> tid;
	array<float> tm;
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const AIFloat3 q = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if ((q.distance2D(gLrFocus) > LR_CELL) || !LrWorth(d, los, q))
			continue;
		// never into our own metal: the C++ aim's guard, which the director bypasses (review 11-16: an army in melee
		// with our line)
		if (ai.GetFriendlyCostIn(q, splash) > 0.f)
			continue;
		const float m = Catalog::gCostM[d];
		uint at = tm.length();
		while ((at > 0) && (tm[at - 1] < m))
			--at;
		tm.insertAt(at, m);
		tid.insertAt(at, aiEnemyMgr.GetEnemyUnitIdAt(i));
	}
	if (tid.length() == 0) {
		LrLetGo(guns, true);   // nothing safe to shoot there: the guns aim themselves until the next look
		return;
	}
	uint next = 0;
	for (uint g = 0; g < guns.length(); ++g) {
		const int id = int(guns[g].id);
		const bool inReach = guns[g].GetPos(ai.frame).distance2D(gLrFocus) <= reach[g];
		const int have = gLrOrdered.find(id);
		if (!inReach) {
			if (have >= 0) {
				guns[g].CmdStop();
				guns[g].SetScriptFree(false);
				gLrOrdered.removeAt(uint(have));
				gLrTarget.removeAt(uint(have));
			}
			continue;
		}
		if ((have >= 0) && (tid.find(gLrTarget[uint(have)]) >= 0))
			continue;   // its target still stands
		const int t = tid[next % tid.length()];
		++next;
		if (!guns[g].CmdAttackEnemy(t))
			continue;
		guns[g].SetScriptFree(true);   // held: CSuperTask leaves it alone (a gun not held aims itself, as before)
		if (have >= 0) {
			gLrTarget[uint(have)] = t;
		} else {
			gLrOrdered.insertLast(id);
			gLrTarget.insertLast(t);
		}
	}
}

}  // namespace Brain
